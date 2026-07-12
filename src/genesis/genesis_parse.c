/**
 * @file genesis_parse.c
 * @brief Parsing and memory helpers for Lantern genesis artifacts.
 *
 * Implements internal helpers used by the public genesis API:
 * - YAML parsing for config/validators/validator-config/nodes files
 * - Memory ownership helpers for validator config structures
 *
 * @spec Lantern devnet genesis artifact files (lean quickstart).
 */

#include "genesis_internal.h"

#include <ctype.h>
#include <inttypes.h>
#include <limits.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "internal/yaml_parser.h"
#include "lantern/support/secure_mem.h"
#include "lantern/support/strings.h"

static const size_t GENESIS_LINE_BUFFER_LEN = 2048;
static const size_t GENESIS_SMALL_LINE_BUFFER_LEN = 1024;

static const char *const CHAIN_CONFIG_KEY_GENESIS_TIME = "GENESIS_TIME";
static const char *const CHAIN_CONFIG_KEY_VALIDATOR_COUNT = "VALIDATOR_COUNT";
static const char *const CHAIN_CONFIG_KEY_NUM_VALIDATORS = "NUM_VALIDATORS";
static const char *const CHAIN_CONFIG_KEY_ATTESTATION_COMMITTEE_COUNT = "ATTESTATION_COMMITTEE_COUNT";
static const char *const CHAIN_CONFIG_KEY_GENESIS_VALIDATORS = "GENESIS_VALIDATORS";
static const char *const CHAIN_CONFIG_FIELD_ATTESTATION_PUBKEY = "attestation_pubkey";
static const char *const CHAIN_CONFIG_FIELD_PROPOSAL_PUBKEY = "proposal_pubkey";

static const char *const VALIDATOR_CONFIG_ARRAY_VALIDATORS = "validators";
static const char *const VALIDATOR_CONFIG_FIELD_NAME = "name";
static const char *const VALIDATOR_CONFIG_FIELD_PRIVKEY = "privkey";
static const char *const VALIDATOR_CONFIG_FIELD_COUNT = "count";
static const char *const VALIDATOR_CONFIG_FIELD_IP = "ip";
static const char *const VALIDATOR_CONFIG_FIELD_QUIC = "quic";
static const char *const VALIDATOR_CONFIG_FIELD_SEQ = "seq";
static const char *const VALIDATOR_CONFIG_FIELD_IS_AGGREGATOR = "is_aggregator";
static const char *const VALIDATOR_CONFIG_FIELD_XMSS_DIR = "xmssDir";
static const char *const VALIDATOR_CONFIG_FIELD_SUBNET = "subnet";

static int parse_bool(const char *value, int *ok);

static int parse_validator_config_entry(
    const LanternYamlObject *object,
    struct lantern_validator_config_entry *entry);
static void free_validator_config_entry(struct lantern_validator_config_entry *entry);

static int parse_bool(const char *value, int *ok)
{
    if (ok)
    {
        *ok = 0;
    }
    if (!value)
    {
        return 0;
    }

    char *trimmed = genesis_dup_trimmed(value);
    if (!trimmed)
    {
        return 0;
    }

    for (char *p = trimmed; *p; ++p)
    {
        *p = (char)tolower((unsigned char)*p);
    }

    int parsed = 0;
    if (strcmp(trimmed, "true") == 0 || strcmp(trimmed, "1") == 0)
    {
        parsed = 1;
        if (ok)
        {
            *ok = 1;
        }
    }
    else if (strcmp(trimmed, "false") == 0 || strcmp(trimmed, "0") == 0)
    {
        parsed = 0;
        if (ok)
        {
            *ok = 1;
        }
    }
    free(trimmed);
    return parsed;
}


/**
 * Free resources held by a validator config entry.
 *
 * Clears any sensitive material (privkey hex) before freeing.
 *
 * @param entry Entry to reset.
 *
 * @note Thread safety: Not thread-safe. Caller must ensure exclusive access to entry.
 */
static void free_validator_config_entry(struct lantern_validator_config_entry *entry)
{
    if (!entry)
    {
        return;
    }

    free(entry->name);

    if (entry->privkey_hex)
    {
        size_t len = strlen(entry->privkey_hex);
        if (len > 0)
        {
            lantern_secure_zero(entry->privkey_hex, len);
        }
    }
    free(entry->privkey_hex);
    free(entry->enr.ip);
    free(entry->xmss_dir);
    free(entry->indices);
}


/**
 * Free resources held by a validator config.
 *
 * Frees owned entries, then resets `config` to an empty state. Safe to call
 * with NULL.
 *
 * @spec Lantern devnet genesis artifact files (lean quickstart).
 *
 * @param config Config to reset.
 *
 * @note Thread safety: Not thread-safe. Caller must ensure exclusive access to config.
 */
void genesis_free_validator_config(struct lantern_validator_config *config)
{
    if (!config)
    {
        return;
    }

    if (config->entries)
    {
        for (size_t i = 0; i < config->count; ++i)
        {
            free_validator_config_entry(&config->entries[i]);
        }
        free(config->entries);
    }

    *config = (struct lantern_validator_config){0};
}


/**
 * Parse chain configuration scalars from a chain config file.
 *
 * Parses the top-level `GENESIS_TIME` and validator-count scalar
 * (`VALIDATOR_COUNT` or `NUM_VALIDATORS`). Any prior packed pubkeys in
 * `config` are freed and the pubkey fields are reset.
 *
 * @spec Lantern devnet genesis artifact files (lean quickstart).
 *
 * @param path   Path to the chain config YAML file.
 * @param config Config to populate (modified in place).
 *
 * @return LANTERN_GENESIS_OK on success.
 * @return LANTERN_GENESIS_ERR_INVALID_PARAM on invalid parameters.
 * @return LANTERN_GENESIS_ERR_IO on file I/O errors.
 * @return LANTERN_GENESIS_ERR_INVALID_DATA on parse/validation failures.
 *
 * @note Thread safety: Not thread-safe. Caller must ensure exclusive access to config.
 */
int genesis_parse_chain_config(const char *path, struct lantern_chain_config *config)
{
    if (!path || !config)
    {
        return LANTERN_GENESIS_ERR_INVALID_PARAM;
    }

    config->genesis_time = 0;
    config->validator_count = 0;
    config->attestation_committee_count = 0;

    free(config->validator_attestation_pubkeys);
    config->validator_attestation_pubkeys = NULL;
    free(config->validator_proposal_pubkeys);
    config->validator_proposal_pubkeys = NULL;

    FILE *fp = fopen(path, "r");
    if (!fp)
    {
        return LANTERN_GENESIS_ERR_IO;
    }

    int result = LANTERN_GENESIS_OK;
    char line[GENESIS_SMALL_LINE_BUFFER_LEN];

    while (fgets(line, sizeof(line), fp))
    {
        char *trimmed = lantern_trim_whitespace(line);
        if (!trimmed || *trimmed == '\0' || *trimmed == '#')
        {
            continue;
        }

        char *sep = strchr(trimmed, ':');
        if (!sep)
        {
            continue;
        }

        *sep = '\0';
        const char *key = trimmed;
        char *value = lantern_trim_whitespace(sep + 1);

        if (strcmp(key, CHAIN_CONFIG_KEY_GENESIS_TIME) == 0)
        {
            int ok = 0;
            config->genesis_time = genesis_parse_u64(value, &ok);
            if (!ok || config->genesis_time == 0)
            {
                result = LANTERN_GENESIS_ERR_INVALID_DATA;
                break;
            }
        }
        else if (strcmp(key, CHAIN_CONFIG_KEY_VALIDATOR_COUNT) == 0
                 || strcmp(key, CHAIN_CONFIG_KEY_NUM_VALIDATORS) == 0)
        {
            int ok = 0;
            config->validator_count = genesis_parse_u64(value, &ok);
            if (!ok)
            {
                result = LANTERN_GENESIS_ERR_INVALID_DATA;
                break;
            }
        }
        else if (strcmp(key, CHAIN_CONFIG_KEY_ATTESTATION_COMMITTEE_COUNT) == 0)
        {
            int ok = 0;
            config->attestation_committee_count = genesis_parse_u64(value, &ok);
            if (!ok || config->attestation_committee_count == 0)
            {
                result = LANTERN_GENESIS_ERR_INVALID_DATA;
                break;
            }
        }
    }

    fclose(fp);

    if (result != LANTERN_GENESIS_OK)
    {
        return result;
    }

    if (config->genesis_time == 0)
    {
        return LANTERN_GENESIS_ERR_INVALID_DATA;
    }

    return LANTERN_GENESIS_OK;
}


/**
 * Parse genesis validator pubkeys from a chain config file.
 *
 * Supports the dual-key object format:
 *
 *   GENESIS_VALIDATORS:
 *     - attestation_pubkey: 0x...
 *       proposal_pubkey: 0x...
 *
 * On success, any non-NULL output arrays are caller-owned and must be freed
 * with `free()`.
 *
 * @spec Lantern devnet genesis artifact files (lean quickstart).
 *
 * @param path                     Path to the chain config YAML file.
 * @param out_attestation_pubkeys  Output pointer for packed attestation pubkeys.
 * @param out_proposal_pubkeys     Output pointer for packed proposal pubkeys.
 * @param out_count                Output pointer for the validator count.
 *
 * @return LANTERN_GENESIS_OK on success.
 * @return LANTERN_GENESIS_ERR_INVALID_PARAM on invalid parameters.
 * @return LANTERN_GENESIS_ERR_IO on file I/O errors.
 * @return LANTERN_GENESIS_ERR_OUT_OF_MEMORY on allocation failure.
 * @return LANTERN_GENESIS_ERR_OVERFLOW on size/capacity overflow.
 * @return LANTERN_GENESIS_ERR_INVALID_DATA on parse/validation failures.
 *
 * @note Thread safety: Thread-safe if callers provide exclusive access to outputs.
 */
int genesis_parse_genesis_validator_pubkeys(
    const char *path,
    uint8_t **out_attestation_pubkeys,
    uint8_t **out_proposal_pubkeys,
    size_t *out_count)
{
    if (!path || !out_attestation_pubkeys || !out_proposal_pubkeys || !out_count)
    {
        return LANTERN_GENESIS_ERR_INVALID_PARAM;
    }

    *out_attestation_pubkeys = NULL;
    *out_proposal_pubkeys = NULL;
    *out_count = 0;

    size_t object_count = 0;
    LanternYamlObject *objects = lantern_yaml_read_array(
        path,
        CHAIN_CONFIG_KEY_GENESIS_VALIDATORS,
        &object_count);
    if (!objects || object_count == 0)
    {
        lantern_yaml_free_objects(objects, object_count);
        return LANTERN_GENESIS_OK;
    }

    if (object_count > SIZE_MAX / LANTERN_VALIDATOR_PUBKEY_SIZE)
    {
        lantern_yaml_free_objects(objects, object_count);
        return LANTERN_GENESIS_ERR_OVERFLOW;
    }
    size_t pubkeys_len = object_count * LANTERN_VALIDATOR_PUBKEY_SIZE;
    uint8_t *attestation_pubkeys = malloc(pubkeys_len);
    uint8_t *proposal_pubkeys = malloc(pubkeys_len);
    if (!attestation_pubkeys || !proposal_pubkeys)
    {
        free(attestation_pubkeys);
        free(proposal_pubkeys);
        lantern_yaml_free_objects(objects, object_count);
        return LANTERN_GENESIS_ERR_OUT_OF_MEMORY;
    }
    int result = LANTERN_GENESIS_OK;

    for (size_t i = 0; i < object_count; ++i)
    {
        const char *attestation_value = genesis_yaml_object_value(
            &objects[i],
            CHAIN_CONFIG_FIELD_ATTESTATION_PUBKEY);
        const char *proposal_value = genesis_yaml_object_value(
            &objects[i],
            CHAIN_CONFIG_FIELD_PROPOSAL_PUBKEY);
        if (!attestation_value || !proposal_value)
        {
            result = LANTERN_GENESIS_ERR_INVALID_DATA;
            break;
        }

        char *attestation_hex = genesis_dup_trimmed(attestation_value);
        char *proposal_hex = genesis_dup_trimmed(proposal_value);
        if (!attestation_hex || !proposal_hex)
        {
            free(attestation_hex);
            free(proposal_hex);
            result = LANTERN_GENESIS_ERR_OUT_OF_MEMORY;
            break;
        }

        result = genesis_decode_validator_pubkey_hex(
            attestation_hex,
            attestation_pubkeys + (i * LANTERN_VALIDATOR_PUBKEY_SIZE));
        if (result == LANTERN_GENESIS_OK)
        {
            result = genesis_decode_validator_pubkey_hex(
                proposal_hex,
                proposal_pubkeys + (i * LANTERN_VALIDATOR_PUBKEY_SIZE));
        }

        free(attestation_hex);
        free(proposal_hex);

        if (result != LANTERN_GENESIS_OK)
        {
            result = (result == LANTERN_GENESIS_ERR_OUT_OF_MEMORY)
                ? result
                : LANTERN_GENESIS_ERR_INVALID_DATA;
            break;
        }
    }

    lantern_yaml_free_objects(objects, object_count);

    if (result != LANTERN_GENESIS_OK)
    {
        free(attestation_pubkeys);
        free(proposal_pubkeys);
        return result;
    }

    *out_attestation_pubkeys = attestation_pubkeys;
    *out_proposal_pubkeys = proposal_pubkeys;
    *out_count = object_count;
    return LANTERN_GENESIS_OK;
}


/**
 * Parse a validator-config.yaml entry into a config entry struct.
 *
 * Populates `entry` by duplicating required fields from `object`. On success,
 * `entry` owns any allocated strings and must be released with
 * `free_validator_config_entry()`.
 *
 * @param object YAML object to parse.
 * @param entry  Entry to populate (modified in place).
 *
 * @return LANTERN_GENESIS_OK on success.
 * @return LANTERN_GENESIS_ERR_INVALID_PARAM on invalid parameters.
 * @return LANTERN_GENESIS_ERR_OUT_OF_MEMORY on allocation failure.
 * @return LANTERN_GENESIS_ERR_INVALID_DATA on validation failures.
 * @return LANTERN_GENESIS_ERR_PARSE on decode/derivation failures.
 *
 * @note Thread safety: Not thread-safe. Caller must ensure exclusive access to entry.
 */
static int parse_validator_config_entry(
    const LanternYamlObject *object,
    struct lantern_validator_config_entry *entry)
{
    if (!object || !entry)
    {
        return LANTERN_GENESIS_ERR_INVALID_PARAM;
    }

    const char *name_val = genesis_yaml_object_value(object, VALIDATOR_CONFIG_FIELD_NAME);
    const char *priv_val = genesis_yaml_object_value(object, VALIDATOR_CONFIG_FIELD_PRIVKEY);
    const char *count_val = genesis_yaml_object_value(object, VALIDATOR_CONFIG_FIELD_COUNT);
    const char *ip_val = genesis_yaml_object_value(object, VALIDATOR_CONFIG_FIELD_IP);
    const char *quic_val = genesis_yaml_object_value(object, VALIDATOR_CONFIG_FIELD_QUIC);
    const char *seq_val = genesis_yaml_object_value(object, VALIDATOR_CONFIG_FIELD_SEQ);
    const char *is_aggregator_val = genesis_yaml_object_value(object, VALIDATOR_CONFIG_FIELD_IS_AGGREGATOR);
    const char *xmss_dir_val = genesis_yaml_object_value(object, VALIDATOR_CONFIG_FIELD_XMSS_DIR);
    const char *subnet_val = genesis_yaml_object_value(object, VALIDATOR_CONFIG_FIELD_SUBNET);

    entry->name = genesis_dup_trimmed(name_val);
    entry->privkey_hex = genesis_dup_trimmed(priv_val);
    if (!entry->name || !entry->privkey_hex)
    {
        return LANTERN_GENESIS_ERR_OUT_OF_MEMORY;
    }

    int ok = 0;
    entry->count = genesis_parse_u64(count_val, &ok);
    if (!ok || entry->count == 0)
    {
        return LANTERN_GENESIS_ERR_INVALID_DATA;
    }

    entry->enr.ip = genesis_dup_trimmed(ip_val);
    if (ip_val && !entry->enr.ip)
    {
        return LANTERN_GENESIS_ERR_OUT_OF_MEMORY;
    }

    uint64_t quic_port = genesis_parse_u64(quic_val, &ok);
    if (!ok || quic_port > UINT16_MAX)
    {
        return LANTERN_GENESIS_ERR_INVALID_DATA;
    }
    entry->enr.quic_port = (uint16_t)quic_port;

    entry->enr.sequence = 1;
    if (seq_val && *seq_val)
    {
        entry->enr.sequence = genesis_parse_u64(seq_val, &ok);
        if (!ok)
        {
            return LANTERN_GENESIS_ERR_INVALID_DATA;
        }
    }

    entry->enr.is_aggregator = false;
    if (is_aggregator_val && *is_aggregator_val)
    {
        int bool_ok = 0;
        entry->enr.is_aggregator = parse_bool(is_aggregator_val, &bool_ok) ? true : false;
        if (!bool_ok)
        {
            return LANTERN_GENESIS_ERR_INVALID_DATA;
        }
    }

    entry->has_subnet = false;
    entry->subnet = 0;
    if (subnet_val && *subnet_val)
    {
        entry->subnet = genesis_parse_u64(subnet_val, &ok);
        if (!ok)
        {
            return LANTERN_GENESIS_ERR_INVALID_DATA;
        }
        entry->has_subnet = true;
    }

    entry->xmss_dir = genesis_dup_trimmed(xmss_dir_val);
    if (xmss_dir_val && !entry->xmss_dir)
    {
        return LANTERN_GENESIS_ERR_OUT_OF_MEMORY;
    }
    return LANTERN_GENESIS_OK;
}


/**
 * Parse validator configuration entries from a validator-config.yaml file.
 *
 * On success, `config` owns the returned buffers and must be released with
 * `genesis_free_validator_config()`.
 *
 * @spec Lantern devnet genesis artifact files (lean quickstart).
 *
 * @param path   Path to validator-config.yaml.
 * @param config Config to populate.
 *
 * @return LANTERN_GENESIS_OK on success.
 * @return LANTERN_GENESIS_ERR_INVALID_PARAM on invalid parameters.
 * @return LANTERN_GENESIS_ERR_IO on file I/O errors.
 * @return LANTERN_GENESIS_ERR_OUT_OF_MEMORY on allocation failure.
 * @return LANTERN_GENESIS_ERR_OVERFLOW on size/capacity overflow.
 * @return LANTERN_GENESIS_ERR_INVALID_DATA on validation failures.
 * @return LANTERN_GENESIS_ERR_PARSE on parse failures.
 *
 * @note Thread safety: Not thread-safe. Caller must ensure exclusive access to config.
 */
int genesis_parse_validator_config(const char *path, struct lantern_validator_config *config)
{
    if (!path || !config)
    {
        return LANTERN_GENESIS_ERR_INVALID_PARAM;
    }

    genesis_free_validator_config(config);

    size_t object_count = 0;
    LanternYamlObject *objects = lantern_yaml_read_array(
        path,
        VALIDATOR_CONFIG_ARRAY_VALIDATORS,
        &object_count);
    if (!objects || object_count == 0)
    {
        lantern_yaml_free_objects(objects, object_count);
        return LANTERN_GENESIS_ERR_PARSE;
    }

    if (object_count > SIZE_MAX / sizeof(*config->entries))
    {
        lantern_yaml_free_objects(objects, object_count);
        return LANTERN_GENESIS_ERR_OVERFLOW;
    }

    struct lantern_validator_config_entry *entries = calloc(object_count, sizeof(*entries));
    if (!entries)
    {
        lantern_yaml_free_objects(objects, object_count);
        return LANTERN_GENESIS_ERR_OUT_OF_MEMORY;
    }

    for (size_t i = 0; i < object_count; ++i)
    {
        int result = parse_validator_config_entry(&objects[i], &entries[i]);
        if (result != LANTERN_GENESIS_OK)
        {
            for (size_t j = 0; j <= i; ++j)
            {
                free_validator_config_entry(&entries[j]);
            }
            free(entries);
            lantern_yaml_free_objects(objects, object_count);
            return result;
        }
    }

    lantern_yaml_free_objects(objects, object_count);

    config->entries = entries;
    config->count = object_count;
    return LANTERN_GENESIS_OK;
}


/**
 * Parse `nodes.yaml` and append ENR entries to a list.
 *
 * @spec Lantern devnet genesis artifact files (lean quickstart).
 *
 * @param path Path to nodes.yaml.
 * @param list Record list to append to.
 *
 * @return LANTERN_GENESIS_OK on success.
 * @return LANTERN_GENESIS_ERR_INVALID_PARAM on invalid parameters.
 * @return LANTERN_GENESIS_ERR_IO on file I/O errors.
 * @return LANTERN_GENESIS_ERR_PARSE on parse failures.
 *
 * @note Thread safety: Not thread-safe. Caller must ensure exclusive access to list.
 */
int genesis_parse_nodes_file(const char *path, struct lantern_enr_record_list *list)
{
    if (!path || !list)
    {
        return LANTERN_GENESIS_ERR_INVALID_PARAM;
    }

    FILE *fp = fopen(path, "r");
    if (!fp)
    {
        return LANTERN_GENESIS_ERR_IO;
    }

    int result = LANTERN_GENESIS_OK;
    char line[GENESIS_LINE_BUFFER_LEN];

    while (fgets(line, sizeof(line), fp))
    {
        char *trimmed = lantern_trim_whitespace(line);
        if (!trimmed || *trimmed == '\0' || *trimmed == '#')
        {
            continue;
        }

        char *enr = strstr(trimmed, "enr:");
        if (!enr)
        {
            continue;
        }

        enr = lantern_trim_whitespace(enr);
        if (!enr || *enr == '\0')
        {
            continue;
        }

        if (lantern_enr_record_list_append(list, enr) != 0)
        {
            result = LANTERN_GENESIS_ERR_PARSE;
            break;
        }
    }

    fclose(fp);
    return result;
}
