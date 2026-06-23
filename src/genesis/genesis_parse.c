/**
 * @file genesis_parse.c
 * @brief Parsing and memory helpers for Lantern genesis artifacts.
 *
 * Implements internal helpers used by the public genesis API:
 * - YAML parsing for config/validators/validator-config/nodes files
 * - Binary blob loading for genesis SSZ state
 * - Memory ownership helpers for registry/config structures
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
#include "lantern/networking/libp2p.h"
#include "lantern/support/secure_mem.h"
#include "lantern/support/strings.h"

static const size_t GENESIS_LINE_BUFFER_LEN = 2048;
static const size_t GENESIS_SMALL_LINE_BUFFER_LEN = 1024;
static const size_t GENESIS_INITIAL_PUBKEY_CAPACITY = 4;
static const size_t GENESIS_PEER_ID_BUFFER_LEN = 128;
static const size_t GENESIS_PUBKEY_HEX_BUFFER_LEN = (LANTERN_VALIDATOR_PUBKEY_SIZE * 2u) + 3u;

static const char *const CHAIN_CONFIG_KEY_GENESIS_TIME = "GENESIS_TIME";
static const char *const CHAIN_CONFIG_KEY_VALIDATOR_COUNT = "VALIDATOR_COUNT";
static const char *const CHAIN_CONFIG_KEY_NUM_VALIDATORS = "NUM_VALIDATORS";
static const char *const CHAIN_CONFIG_KEY_ATTESTATION_COMMITTEE_COUNT = "ATTESTATION_COMMITTEE_COUNT";
static const char *const CHAIN_CONFIG_KEY_GENESIS_VALIDATORS = "GENESIS_VALIDATORS";
static const char *const CHAIN_CONFIG_FIELD_ATTESTATION_PUBKEY = "attestation_pubkey";
static const char *const CHAIN_CONFIG_FIELD_PROPOSAL_PUBKEY = "proposal_pubkey";

static const char *const VALIDATOR_CONFIG_SCALAR_SHUFFLE = "shuffle";
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
static int read_scalar_value(const char *path, const char *key, char **out_value);
static enum lantern_validator_client_kind classify_validator_client(const char *name);
static int derive_peer_id_from_privkey_hex(const char *hex, char **out_peer_id);

static int ensure_pubkey_pair_capacity(
    uint8_t **attestation_pubkeys,
    uint8_t **proposal_pubkeys,
    size_t *cap,
    size_t required);
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
 * Read a top-level scalar value from a YAML file (`key: value`).
 *
 * On success, `*out_value` is allocated and must be freed by the caller.
 *
 * @param path      Filesystem path to the YAML file.
 * @param key       Scalar key to read.
 * @param out_value Output pointer for the allocated value string.
 *
 * @return LANTERN_GENESIS_OK on success.
 * @return LANTERN_GENESIS_ERR_INVALID_PARAM on invalid parameters.
 * @return LANTERN_GENESIS_ERR_IO if the file cannot be opened.
 * @return LANTERN_GENESIS_ERR_OUT_OF_MEMORY on allocation failure.
 * @return LANTERN_GENESIS_ERR_PARSE if the key cannot be found.
 *
 * @note Thread safety: Thread-safe if callers provide exclusive access to outputs.
 */
static int read_scalar_value(const char *path, const char *key, char **out_value)
{
    if (!path || !key || !out_value)
    {
        return LANTERN_GENESIS_ERR_INVALID_PARAM;
    }

    *out_value = NULL;

    FILE *fp = fopen(path, "r");
    if (!fp)
    {
        return LANTERN_GENESIS_ERR_IO;
    }

    int result = LANTERN_GENESIS_ERR_PARSE;
    char line[GENESIS_SMALL_LINE_BUFFER_LEN];
    const size_t key_len = strlen(key);

    while (fgets(line, sizeof(line), fp))
    {
        char *trimmed = lantern_trim_whitespace(line);
        if (!trimmed || *trimmed == '\0' || *trimmed == '#')
        {
            continue;
        }

        if (strncmp(trimmed, key, key_len) != 0)
        {
            continue;
        }
        if (trimmed[key_len] != ':')
        {
            continue;
        }

        char *value = lantern_trim_whitespace(trimmed + key_len + 1);
        *out_value = genesis_dup_trimmed(value);
        result = *out_value ? LANTERN_GENESIS_OK : LANTERN_GENESIS_ERR_OUT_OF_MEMORY;
        break;
    }

    fclose(fp);
    return result;
}


/**
 * Classify validator client kind based on its name prefix.
 *
 * @param name Validator client name.
 *
 * @return Parsed validator client kind enum value.
 *
 * @note Thread safety: Thread-safe.
 */
static enum lantern_validator_client_kind classify_validator_client(const char *name)
{
    if (!name)
    {
        return LANTERN_VALIDATOR_CLIENT_UNKNOWN;
    }

    if (strncmp(name, "lantern", sizeof("lantern") - 1) == 0)
    {
        return LANTERN_VALIDATOR_CLIENT_LANTERN;
    }
    if (strncmp(name, "qlean", sizeof("qlean") - 1) == 0)
    {
        return LANTERN_VALIDATOR_CLIENT_QLEAN;
    }
    if (strncmp(name, "ream", sizeof("ream") - 1) == 0)
    {
        return LANTERN_VALIDATOR_CLIENT_REAM;
    }
    if (strncmp(name, "zeam", sizeof("zeam") - 1) == 0)
    {
        return LANTERN_VALIDATOR_CLIENT_ZEAM;
    }

    return LANTERN_VALIDATOR_CLIENT_UNKNOWN;
}


/**
 * Derive a libp2p peer ID from a secp256k1 private key (hex).
 *
 * On success, `*out_peer_id` is allocated and must be freed by the caller.
 *
 * @param hex         Private key as a hex string.
 * @param out_peer_id Output pointer for the allocated peer ID text.
 *
 * @return LANTERN_GENESIS_OK on success.
 * @return LANTERN_GENESIS_ERR_INVALID_PARAM on invalid parameters.
 * @return LANTERN_GENESIS_ERR_OUT_OF_MEMORY on allocation failure.
 * @return LANTERN_GENESIS_ERR_PARSE on decode/derivation failures.
 *
 * @note Thread safety: Thread-safe if callers provide exclusive access to outputs.
 */
static int derive_peer_id_from_privkey_hex(const char *hex, char **out_peer_id)
{
    if (!hex || !out_peer_id)
    {
        return LANTERN_GENESIS_ERR_INVALID_PARAM;
    }

    *out_peer_id = NULL;

    uint8_t secret[32];
    if (lantern_hex_decode(hex, secret, sizeof(secret)) != 0)
    {
        lantern_secure_zero(secret, sizeof(secret));
        return LANTERN_GENESIS_ERR_PARSE;
    }

    uint8_t public_key[LIBP2P_PEER_ID_SECP256K1_COMPRESSED_PUBLIC_KEY_BYTES];
    size_t public_key_len = 0;
    if (libp2p_peer_id_public_key_from_private_key(
            secret,
            sizeof(secret),
            1,
            public_key,
            sizeof(public_key),
            &public_key_len)
        != LIBP2P_PEER_ID_OK)
    {
        lantern_secure_zero(secret, sizeof(secret));
        return LANTERN_GENESIS_ERR_PARSE;
    }
    lantern_secure_zero(secret, sizeof(secret));

    struct lantern_peer_id peer_id;
    size_t peer_id_len = 0;
    if (libp2p_peer_id_from_secp256k1_public_key(
            public_key,
            public_key_len,
            peer_id.bytes,
            sizeof(peer_id.bytes),
            &peer_id_len)
        != LIBP2P_PEER_ID_OK)
    {
        return LANTERN_GENESIS_ERR_PARSE;
    }
    peer_id.len = peer_id_len;

    char buffer[GENESIS_PEER_ID_BUFFER_LEN];
    if (lantern_peer_id_to_text(&peer_id, buffer, sizeof(buffer)) < 0)
    {
        return LANTERN_GENESIS_ERR_PARSE;
    }

    char *dup = lantern_string_duplicate(buffer);
    if (!dup)
    {
        return LANTERN_GENESIS_ERR_OUT_OF_MEMORY;
    }

    *out_peer_id = dup;
    return LANTERN_GENESIS_OK;
}


/**
 * Ensure capacity for packed attestation/proposal pubkey buffers.
 *
 * Grows both allocations together so callers can treat index `i` in each array
 * as one validator entry.
 *
 * @param attestation_pubkeys Pointer to the attestation pubkey buffer pointer.
 * @param proposal_pubkeys    Pointer to the proposal pubkey buffer pointer.
 * @param cap                 Pointer to the current capacity in validator entries.
 * @param required            Minimum required capacity in validator entries.
 *
 * @return LANTERN_GENESIS_OK on success.
 * @return LANTERN_GENESIS_ERR_INVALID_PARAM on invalid parameters.
 * @return LANTERN_GENESIS_ERR_OUT_OF_MEMORY on allocation failure.
 * @return LANTERN_GENESIS_ERR_OVERFLOW on capacity overflow.
 *
 * @note Thread safety: Not thread-safe. Caller must ensure exclusive access to the buffers.
 */
static int ensure_pubkey_pair_capacity(
    uint8_t **attestation_pubkeys,
    uint8_t **proposal_pubkeys,
    size_t *cap,
    size_t required)
{
    if (!attestation_pubkeys || !proposal_pubkeys || !cap)
    {
        return LANTERN_GENESIS_ERR_INVALID_PARAM;
    }

    if (*cap >= required)
    {
        return LANTERN_GENESIS_OK;
    }

    size_t new_cap = (*cap == 0) ? GENESIS_INITIAL_PUBKEY_CAPACITY : *cap;
    while (new_cap < required)
    {
        if (new_cap > SIZE_MAX / 2)
        {
            return LANTERN_GENESIS_ERR_OVERFLOW;
        }
        new_cap *= 2;
    }

    if (new_cap > SIZE_MAX / LANTERN_VALIDATOR_PUBKEY_SIZE)
    {
        return LANTERN_GENESIS_ERR_OVERFLOW;
    }

    size_t bytes_len = new_cap * LANTERN_VALIDATOR_PUBKEY_SIZE;
    uint8_t *grown_attestation = malloc(bytes_len);
    uint8_t *grown_proposal = malloc(bytes_len);
    if (!grown_attestation || !grown_proposal)
    {
        free(grown_attestation);
        free(grown_proposal);
        return LANTERN_GENESIS_ERR_OUT_OF_MEMORY;
    }

    if (*cap > 0)
    {
        size_t copy_len = (*cap) * LANTERN_VALIDATOR_PUBKEY_SIZE;
        if (*attestation_pubkeys)
        {
            memcpy(grown_attestation, *attestation_pubkeys, copy_len);
        }
        if (*proposal_pubkeys)
        {
            memcpy(grown_proposal, *proposal_pubkeys, copy_len);
        }
    }

    free(*attestation_pubkeys);
    free(*proposal_pubkeys);
    *attestation_pubkeys = grown_attestation;
    *proposal_pubkeys = grown_proposal;
    *cap = new_cap;
    return LANTERN_GENESIS_OK;
}


/**
 * Free resources held by a validator registry.
 *
 * Frees any owned record array and associated strings, then resets `registry`
 * to an empty state. Safe to call with NULL.
 *
 * @spec Lantern devnet genesis artifact files (lean quickstart).
 *
 * @param registry Registry to reset.
 *
 * @note Thread safety: Not thread-safe. Caller must ensure exclusive access to registry.
 */
void genesis_free_validator_registry(struct lantern_validator_registry *registry)
{
    if (!registry)
    {
        return;
    }

    if (registry->records)
    {
        for (size_t i = 0; i < registry->count; ++i)
        {
            free(registry->records[i].pubkey_hex);
            free(registry->records[i].withdrawal_credentials_hex);
        }
        free(registry->records);
    }

    registry->records = NULL;
    registry->count = 0;
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
    entry->name = NULL;

    if (entry->privkey_hex)
    {
        size_t len = strlen(entry->privkey_hex);
        if (len > 0)
        {
            lantern_secure_zero(entry->privkey_hex, len);
        }
        free(entry->privkey_hex);
    }
    entry->privkey_hex = NULL;

    free(entry->peer_id_text);
    entry->peer_id_text = NULL;

    entry->client_kind = LANTERN_VALIDATOR_CLIENT_UNKNOWN;

    free(entry->enr.ip);
    entry->enr.ip = NULL;
    entry->enr.quic_port = 0;
    entry->enr.sequence = 0;
    entry->enr.is_aggregator = false;

    entry->count = 0;

    free(entry->xmss_dir);
    entry->xmss_dir = NULL;

    entry->start_index = 0;
    entry->end_index = 0;
    entry->has_range = false;

    free(entry->indices);
    entry->indices = NULL;
    entry->indices_len = 0;
    entry->indices_cap = 0;
}


/**
 * Free resources held by a validator config.
 *
 * Frees any owned entries and the shuffle string, then resets `config` to an
 * empty state. Safe to call with NULL.
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

    config->entries = NULL;
    config->count = 0;

    free(config->shuffle);
    config->shuffle = NULL;
}


/**
 * Merge chain config pubkeys into an existing validator registry.
 *
 * Populates missing `pubkey_bytes` and (best-effort) `pubkey_hex` for records
 * in `registry` using the attestation pubkeys from `config`.
 *
 * @spec Lantern devnet genesis artifact files (lean quickstart).
 *
 * @param config   Chain config containing packed validator keypairs.
 * @param registry Registry to update in place.
 *
 * @note Thread safety: Not thread-safe. Caller must ensure exclusive access to registry.
 */
void genesis_merge_chain_pubkeys_into_registry(
    const struct lantern_chain_config *config,
    struct lantern_validator_registry *registry)
{
    if (!config || !registry || !registry->records || registry->count == 0)
    {
        return;
    }
    if (!config->validator_attestation_pubkeys || config->validator_pubkeys_count == 0)
    {
        return;
    }
    if (config->validator_pubkeys_count > SIZE_MAX / LANTERN_VALIDATOR_PUBKEY_SIZE)
    {
        return;
    }

    size_t limit = registry->count;
    if (config->validator_pubkeys_count < limit)
    {
        limit = config->validator_pubkeys_count;
    }

    for (size_t i = 0; i < limit; ++i)
    {
        struct lantern_validator_record *rec = &registry->records[i];

        if (!rec->has_pubkey_bytes)
        {
            memcpy(
                rec->pubkey_bytes,
                config->validator_attestation_pubkeys
                    + (i * LANTERN_VALIDATOR_PUBKEY_SIZE),
                LANTERN_VALIDATOR_PUBKEY_SIZE);
            rec->has_pubkey_bytes = true;
        }

        if (!rec->pubkey_hex)
        {
            char hex[GENESIS_PUBKEY_HEX_BUFFER_LEN];
            if (lantern_bytes_to_hex(
                    rec->pubkey_bytes,
                    LANTERN_VALIDATOR_PUBKEY_SIZE,
                    hex,
                    sizeof(hex),
                    1)
                == 0)
            {
                rec->pubkey_hex = lantern_string_duplicate(hex);
            }
        }
    }
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
    config->validator_pubkeys_count = 0;

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

    size_t count = 0;
    size_t cap = 0;
    uint8_t *attestation_pubkeys = NULL;
    uint8_t *proposal_pubkeys = NULL;
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

        result = ensure_pubkey_pair_capacity(
            &attestation_pubkeys,
            &proposal_pubkeys,
            &cap,
            count + 1);
        if (result == LANTERN_GENESIS_OK)
        {
            result = genesis_decode_validator_pubkey_hex(
                attestation_hex,
                attestation_pubkeys + (count * LANTERN_VALIDATOR_PUBKEY_SIZE));
        }
        if (result == LANTERN_GENESIS_OK)
        {
            result = genesis_decode_validator_pubkey_hex(
                proposal_hex,
                proposal_pubkeys + (count * LANTERN_VALIDATOR_PUBKEY_SIZE));
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

        ++count;
    }

    lantern_yaml_free_objects(objects, object_count);

    if (result != LANTERN_GENESIS_OK)
    {
        free(attestation_pubkeys);
        free(proposal_pubkeys);
        return result;
    }

    if (count == 0)
    {
        free(attestation_pubkeys);
        free(proposal_pubkeys);
        return LANTERN_GENESIS_OK;
    }

    *out_attestation_pubkeys = attestation_pubkeys;
    *out_proposal_pubkeys = proposal_pubkeys;
    *out_count = count;
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

    entry->client_kind = classify_validator_client(entry->name);

    int result = derive_peer_id_from_privkey_hex(entry->privkey_hex, &entry->peer_id_text);
    if (result != LANTERN_GENESIS_OK)
    {
        return result;
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

    char *shuffle = NULL;
    int result = read_scalar_value(path, VALIDATOR_CONFIG_SCALAR_SHUFFLE, &shuffle);
    if (result != LANTERN_GENESIS_OK)
    {
        return result;
    }

    size_t object_count = 0;
    LanternYamlObject *objects = lantern_yaml_read_array(
        path,
        VALIDATOR_CONFIG_ARRAY_VALIDATORS,
        &object_count);
    if (!objects || object_count == 0)
    {
        lantern_yaml_free_objects(objects, object_count);
        free(shuffle);
        return LANTERN_GENESIS_ERR_PARSE;
    }

    if (object_count > SIZE_MAX / sizeof(*config->entries))
    {
        lantern_yaml_free_objects(objects, object_count);
        free(shuffle);
        return LANTERN_GENESIS_ERR_OVERFLOW;
    }

    struct lantern_validator_config_entry *entries = calloc(object_count, sizeof(*entries));
    if (!entries)
    {
        lantern_yaml_free_objects(objects, object_count);
        free(shuffle);
        return LANTERN_GENESIS_ERR_OUT_OF_MEMORY;
    }

    for (size_t i = 0; i < object_count; ++i)
    {
        result = parse_validator_config_entry(&objects[i], &entries[i]);
        if (result != LANTERN_GENESIS_OK)
        {
            for (size_t j = 0; j <= i; ++j)
            {
                free_validator_config_entry(&entries[j]);
            }
            free(entries);
            lantern_yaml_free_objects(objects, object_count);
            free(shuffle);
            return result;
        }
    }

    lantern_yaml_free_objects(objects, object_count);

    config->shuffle = shuffle;
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


/**
 * Read a genesis state SSZ blob from disk.
 *
 * On success, `*bytes` is allocated and must be freed by the caller.
 *
 * @spec Lantern devnet genesis artifact files (lean quickstart).
 *
 * @param path  Path to the genesis state SSZ file.
 * @param bytes Output pointer for the allocated buffer.
 * @param size  Output pointer for the buffer length in bytes.
 *
 * @return LANTERN_GENESIS_OK on success.
 * @return LANTERN_GENESIS_ERR_INVALID_PARAM on invalid parameters.
 * @return LANTERN_GENESIS_ERR_IO on file I/O errors.
 * @return LANTERN_GENESIS_ERR_OUT_OF_MEMORY on allocation failure.
 * @return LANTERN_GENESIS_ERR_OVERFLOW if the file is too large.
 * @return LANTERN_GENESIS_ERR_INVALID_DATA if the file is empty or unreadable.
 *
 * @note Thread safety: Thread-safe if callers provide exclusive access to outputs.
 */
int genesis_read_state_blob(const char *path, uint8_t **bytes, size_t *size)
{
    if (!path || !bytes || !size)
    {
        return LANTERN_GENESIS_ERR_INVALID_PARAM;
    }

    *bytes = NULL;
    *size = 0;

    FILE *fp = fopen(path, "rb");
    if (!fp)
    {
        return LANTERN_GENESIS_ERR_IO;
    }

    int result = LANTERN_GENESIS_OK;

    if (fseek(fp, 0, SEEK_END) != 0)
    {
        result = LANTERN_GENESIS_ERR_IO;
        goto cleanup;
    }

    long file_size = ftell(fp);
    if (file_size < 0)
    {
        result = LANTERN_GENESIS_ERR_IO;
        goto cleanup;
    }
    if (file_size == 0)
    {
        result = LANTERN_GENESIS_ERR_INVALID_DATA;
        goto cleanup;
    }
    if ((unsigned long long)file_size > SIZE_MAX)
    {
        result = LANTERN_GENESIS_ERR_OVERFLOW;
        goto cleanup;
    }

    if (fseek(fp, 0, SEEK_SET) != 0)
    {
        result = LANTERN_GENESIS_ERR_IO;
        goto cleanup;
    }

    size_t length = (size_t)file_size;
    uint8_t *buffer = malloc(length);
    if (!buffer)
    {
        result = LANTERN_GENESIS_ERR_OUT_OF_MEMORY;
        goto cleanup;
    }

    size_t read_bytes = fread(buffer, 1, length, fp);
    if (read_bytes != length)
    {
        free(buffer);
        result = LANTERN_GENESIS_ERR_IO;
        goto cleanup;
    }

    *bytes = buffer;
    *size = read_bytes;

cleanup:
    fclose(fp);
    return result;
}
