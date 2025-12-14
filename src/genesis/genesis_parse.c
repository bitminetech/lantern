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
#include <errno.h>
#include <inttypes.h>
#include <limits.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "peer_id/peer_id.h"

#include "internal/yaml_parser.h"
#include "lantern/networking/libp2p.h"
#include "lantern/support/secure_mem.h"
#include "lantern/support/strings.h"

static const size_t GENESIS_LINE_BUFFER_LEN = 2048;
static const size_t GENESIS_SMALL_LINE_BUFFER_LEN = 1024;
static const size_t GENESIS_INITIAL_PUBKEY_CAPACITY = 4;
static const size_t GENESIS_INITIAL_MAPPING_INDEX_CAPACITY = 8;
static const size_t GENESIS_PEER_ID_BUFFER_LEN = 128;
static const size_t GENESIS_PUBKEY_HEX_BUFFER_LEN = (LANTERN_VALIDATOR_PUBKEY_SIZE * 2u) + 3u;

static const char *CHAIN_CONFIG_KEY_GENESIS_TIME = "GENESIS_TIME";
static const char *CHAIN_CONFIG_KEY_VALIDATOR_COUNT = "VALIDATOR_COUNT";
static const char *CHAIN_CONFIG_KEY_GENESIS_VALIDATORS = "GENESIS_VALIDATORS";

static const char *VALIDATOR_REGISTRY_ARRAY_KEY = "validators";
static const char *VALIDATOR_REGISTRY_FIELD_INDEX = "index";
static const char *VALIDATOR_REGISTRY_FIELD_PUBKEY = "pubkey";
static const char *VALIDATOR_REGISTRY_FIELD_WITHDRAWAL_CREDENTIALS = "withdrawal_credentials";

static const char *VALIDATOR_CONFIG_SCALAR_SHUFFLE = "shuffle";
static const char *VALIDATOR_CONFIG_ARRAY_VALIDATORS = "validators";
static const char *VALIDATOR_CONFIG_FIELD_NAME = "name";
static const char *VALIDATOR_CONFIG_FIELD_PRIVKEY = "privkey";
static const char *VALIDATOR_CONFIG_FIELD_COUNT = "count";
static const char *VALIDATOR_CONFIG_FIELD_IP = "ip";
static const char *VALIDATOR_CONFIG_FIELD_QUIC = "quic";
static const char *VALIDATOR_CONFIG_FIELD_SEQ = "seq";
static const char *VALIDATOR_CONFIG_FIELD_HASH_SIG_DIR = "hashSigDir";

static uint64_t parse_u64(const char *value, int *ok);
static char *dup_trimmed(const char *value);
static const char *yaml_object_value(const LanternYamlObject *object, const char *key);
static int read_scalar_value(const char *path, const char *key, char **out_value);
static enum lantern_validator_client_kind classify_validator_client(const char *name);
static int derive_peer_id_from_privkey_hex(const char *hex, char **out_peer_id);
static int decode_validator_pubkey_hex(const char *hex, uint8_t out[LANTERN_VALIDATOR_PUBKEY_SIZE]);
static int set_record_pubkey(struct lantern_validator_record *record);

static int ensure_pubkey_capacity(uint8_t **pubkeys, size_t *cap, size_t required);
static int collect_registry_mapping_indices(
    const char *path,
    size_t **out_indices,
    size_t *out_count,
    size_t *out_max_index);
static int validate_registry_index_coverage(
    const size_t *indices,
    size_t count,
    size_t max_index,
    size_t *out_record_count);
static int build_index_only_registry(
    size_t record_count,
    struct lantern_validator_registry *registry);
static int scan_registry_objects(
    const LanternYamlObject *objects,
    size_t object_count,
    bool *out_has_pubkey_field,
    bool *out_have_explicit_indices,
    size_t *out_record_count);
static int populate_registry_records_from_objects(
    LanternYamlObject *objects,
    size_t object_count,
    bool has_pubkey_field,
    bool have_explicit_indices,
    struct lantern_validator_record *records,
    size_t record_count,
    bool *assigned);
static int validate_registry_full_coverage(const bool *assigned, size_t record_count);
static int parse_validator_registry_objects(
    LanternYamlObject *objects,
    size_t object_count,
    struct lantern_validator_registry *registry);
static int parse_validator_registry_mapping(
    const char *path,
    struct lantern_validator_registry *registry);
static int parse_validator_config_entry(
    const LanternYamlObject *object,
    struct lantern_validator_config_entry *entry);
static void free_validator_config_entry(struct lantern_validator_config_entry *entry);


/** @brief Parse a uint64_t with optional trailing comment. */
static uint64_t parse_u64(const char *value, int *ok)
{
    if (ok)
    {
        *ok = 0;
    }
    if (!value)
    {
        return 0;
    }

    errno = 0;
    char *end = NULL;
    unsigned long long parsed = strtoull(value, &end, 0);
    if (errno != 0 || end == value)
    {
        return 0;
    }

    while (end && *end && isspace((unsigned char)*end))
    {
        ++end;
    }
    if (end && *end != '\0' && *end != '#')
    {
        return 0;
    }
    if (parsed > UINT64_MAX)
    {
        return 0;
    }

    if (ok)
    {
        *ok = 1;
    }
    return (uint64_t)parsed;
}


/** @brief Duplicate a string after trimming whitespace and optional surrounding quotes. */
static char *dup_trimmed(const char *value)
{
    if (!value)
    {
        return NULL;
    }

    const char *start = value;
    while (*start && isspace((unsigned char)*start))
    {
        ++start;
    }

    const char *end = start + strlen(start);
    while (end > start && isspace((unsigned char)*(end - 1)))
    {
        --end;
    }

    if ((end - start) >= 2
        && ((*start == '"' && *(end - 1) == '"') || (*start == '\'' && *(end - 1) == '\'')))
    {
        ++start;
        --end;
    }

    return lantern_string_duplicate_len(start, (size_t)(end - start));
}


/** @brief Lookup a key value in a YAML object. */
static const char *yaml_object_value(const LanternYamlObject *object, const char *key)
{
    if (!object || !key)
    {
        return NULL;
    }

    for (size_t i = 0; i < object->num_pairs; ++i)
    {
        if (object->pairs[i].key && strcmp(object->pairs[i].key, key) == 0)
        {
            return object->pairs[i].value;
        }
    }

    return NULL;
}


/** @brief Read a top-level scalar value from a YAML file (`key: value`). */
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
        *out_value = dup_trimmed(value);
        result = *out_value ? LANTERN_GENESIS_OK : LANTERN_GENESIS_ERR_OUT_OF_MEMORY;
        break;
    }

    fclose(fp);
    return result;
}


/** @brief Classify validator client kind based on its name prefix. */
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


/** @brief Derive a libp2p peer ID from a secp256k1 private key (hex). */
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

    uint8_t *encoded = NULL;
    size_t encoded_len = 0;
    if (lantern_libp2p_encode_secp256k1_private_key_proto(
            secret,
            sizeof(secret),
            &encoded,
            &encoded_len)
        != 0)
    {
        lantern_secure_zero(secret, sizeof(secret));
        return LANTERN_GENESIS_ERR_PARSE;
    }
    lantern_secure_zero(secret, sizeof(secret));

    peer_id_t peer_id = {0};
    peer_id_error_t perr = peer_id_create_from_private_key(encoded, encoded_len, &peer_id);
    if (encoded)
    {
        lantern_secure_zero(encoded, encoded_len);
    }
    free(encoded);

    if (perr != PEER_ID_SUCCESS)
    {
        return LANTERN_GENESIS_ERR_PARSE;
    }

    char buffer[GENESIS_PEER_ID_BUFFER_LEN];
    if (peer_id_to_string(&peer_id, PEER_ID_FMT_BASE58_LEGACY, buffer, sizeof(buffer)) < 0)
    {
        peer_id_destroy(&peer_id);
        return LANTERN_GENESIS_ERR_PARSE;
    }
    peer_id_destroy(&peer_id);

    char *dup = lantern_string_duplicate(buffer);
    if (!dup)
    {
        return LANTERN_GENESIS_ERR_OUT_OF_MEMORY;
    }

    *out_peer_id = dup;
    return LANTERN_GENESIS_OK;
}


/** @brief Decode a validator pubkey hex string into bytes. */
static int decode_validator_pubkey_hex(const char *hex, uint8_t out[LANTERN_VALIDATOR_PUBKEY_SIZE])
{
    if (!hex || !out)
    {
        return LANTERN_GENESIS_ERR_INVALID_PARAM;
    }

    if (lantern_hex_decode(hex, out, LANTERN_VALIDATOR_PUBKEY_SIZE) != 0)
    {
        return LANTERN_GENESIS_ERR_PARSE;
    }

    return LANTERN_GENESIS_OK;
}


/** @brief Populate a registry record's pubkey bytes from its pubkey hex string. */
static int set_record_pubkey(struct lantern_validator_record *record)
{
    if (!record || !record->pubkey_hex)
    {
        return LANTERN_GENESIS_ERR_INVALID_PARAM;
    }

    int result = decode_validator_pubkey_hex(record->pubkey_hex, record->pubkey_bytes);
    if (result != LANTERN_GENESIS_OK)
    {
        return result;
    }

    record->has_pubkey_bytes = true;
    return LANTERN_GENESIS_OK;
}


/** @brief Ensure capacity for a packed pubkey buffer (count elements). */
static int ensure_pubkey_capacity(uint8_t **pubkeys, size_t *cap, size_t required)
{
    if (!pubkeys || !cap)
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

    void *grown = realloc(*pubkeys, new_cap * LANTERN_VALIDATOR_PUBKEY_SIZE);
    if (!grown)
    {
        return LANTERN_GENESIS_ERR_OUT_OF_MEMORY;
    }

    *pubkeys = grown;
    *cap = new_cap;
    return LANTERN_GENESIS_OK;
}


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


/** @brief Free resources held by a validator config entry. */
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

    entry->count = 0;

    free(entry->hash_sig_dir);
    entry->hash_sig_dir = NULL;

    entry->start_index = 0;
    entry->end_index = 0;
    entry->has_range = false;

    free(entry->indices);
    entry->indices = NULL;
    entry->indices_len = 0;
    entry->indices_cap = 0;
}


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


void genesis_merge_chain_pubkeys_into_registry(
    const struct lantern_chain_config *config,
    struct lantern_validator_registry *registry)
{
    if (!config || !registry || !registry->records || registry->count == 0)
    {
        return;
    }
    if (!config->validator_pubkeys || config->validator_pubkeys_count == 0)
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
                config->validator_pubkeys + (i * LANTERN_VALIDATOR_PUBKEY_SIZE),
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


int genesis_parse_chain_config(const char *path, struct lantern_chain_config *config)
{
    if (!path || !config)
    {
        return LANTERN_GENESIS_ERR_INVALID_PARAM;
    }

    config->genesis_time = 0;
    config->validator_count = 0;

    free(config->validator_pubkeys);
    config->validator_pubkeys = NULL;
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
            config->genesis_time = parse_u64(value, &ok);
            if (!ok || config->genesis_time == 0)
            {
                result = LANTERN_GENESIS_ERR_INVALID_DATA;
                break;
            }
        }
        else if (strcmp(key, CHAIN_CONFIG_KEY_VALIDATOR_COUNT) == 0)
        {
            int ok = 0;
            config->validator_count = parse_u64(value, &ok);
            if (!ok)
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


int genesis_parse_genesis_validator_pubkeys(
    const char *path,
    uint8_t **out_pubkeys,
    size_t *out_count)
{
    if (!path || !out_pubkeys || !out_count)
    {
        return LANTERN_GENESIS_ERR_INVALID_PARAM;
    }

    *out_pubkeys = NULL;
    *out_count = 0;

    FILE *fp = fopen(path, "r");
    if (!fp)
    {
        return LANTERN_GENESIS_ERR_IO;
    }

    bool in_array = false;
    size_t count = 0;
    size_t cap = 0;
    uint8_t *pubkeys = NULL;
    int result = LANTERN_GENESIS_OK;

    char line[GENESIS_SMALL_LINE_BUFFER_LEN];
    while (fgets(line, sizeof(line), fp))
    {
        char *trimmed = lantern_trim_whitespace(line);
        if (!trimmed || *trimmed == '\0' || *trimmed == '#')
        {
            continue;
        }

        if (!in_array
            && strncmp(
                   trimmed,
                   CHAIN_CONFIG_KEY_GENESIS_VALIDATORS,
                   strlen(CHAIN_CONFIG_KEY_GENESIS_VALIDATORS))
                == 0)
        {
            in_array = true;
            continue;
        }

        if (!in_array)
        {
            continue;
        }

        if (*trimmed != '-')
        {
            in_array = false;
            continue;
        }

        char *val = lantern_trim_whitespace(trimmed + 1);
        if (!val || *val == '\0')
        {
            continue;
        }

        if (*val == '"' || *val == '\'')
        {
            char quote = *val;
            ++val;
            char *endq = strrchr(val, quote);
            if (endq)
            {
                *endq = '\0';
            }
        }

        uint8_t decoded[LANTERN_VALIDATOR_PUBKEY_SIZE];
        result = decode_validator_pubkey_hex(val, decoded);
        if (result != LANTERN_GENESIS_OK)
        {
            result = LANTERN_GENESIS_ERR_INVALID_DATA;
            break;
        }

        result = ensure_pubkey_capacity(&pubkeys, &cap, count + 1);
        if (result != LANTERN_GENESIS_OK)
        {
            break;
        }

        memcpy(
            pubkeys + (count * LANTERN_VALIDATOR_PUBKEY_SIZE),
            decoded,
            LANTERN_VALIDATOR_PUBKEY_SIZE);
        ++count;
    }

    fclose(fp);

    if (result != LANTERN_GENESIS_OK)
    {
        free(pubkeys);
        return result;
    }

    if (count == 0)
    {
        free(pubkeys);
        return LANTERN_GENESIS_OK;
    }

    *out_pubkeys = pubkeys;
    *out_count = count;
    return LANTERN_GENESIS_OK;
}


/** @brief Collect all validator indices from a mapping/scalar-list validators.yaml. */
static int collect_registry_mapping_indices(
    const char *path,
    size_t **out_indices,
    size_t *out_count,
    size_t *out_max_index)
{
    if (!path || !out_indices || !out_count || !out_max_index)
    {
        return LANTERN_GENESIS_ERR_INVALID_PARAM;
    }

    *out_indices = NULL;
    *out_count = 0;
    *out_max_index = 0;

    FILE *fp = fopen(path, "r");
    if (!fp)
    {
        return LANTERN_GENESIS_ERR_IO;
    }

    size_t *indices = NULL;
    size_t count = 0;
    size_t cap = 0;
    size_t max_index = 0;
    int result = LANTERN_GENESIS_OK;

    char line[GENESIS_SMALL_LINE_BUFFER_LEN];
    while (fgets(line, sizeof(line), fp))
    {
        char *trimmed = lantern_trim_whitespace(line);
        if (!trimmed || *trimmed != '-')
        {
            continue;
        }

        trimmed = lantern_trim_whitespace(trimmed + 1);
        if (!trimmed || *trimmed == '\0')
        {
            continue;
        }

        int ok = 0;
        uint64_t value = parse_u64(trimmed, &ok);
        if (!ok || value > SIZE_MAX)
        {
            result = LANTERN_GENESIS_ERR_INVALID_DATA;
            break;
        }

        if (count == cap)
        {
            if (cap > SIZE_MAX / 2)
            {
                result = LANTERN_GENESIS_ERR_OVERFLOW;
                break;
            }

            size_t new_cap = (cap == 0) ? GENESIS_INITIAL_MAPPING_INDEX_CAPACITY : (cap * 2);
            void *grown = realloc(indices, new_cap * sizeof(*indices));
            if (!grown)
            {
                result = LANTERN_GENESIS_ERR_OUT_OF_MEMORY;
                break;
            }
            indices = grown;
            cap = new_cap;
        }

        indices[count++] = (size_t)value;
        if ((size_t)value > max_index)
        {
            max_index = (size_t)value;
        }
    }

    fclose(fp);

    if (result != LANTERN_GENESIS_OK)
    {
        free(indices);
        return result;
    }

    if (count == 0)
    {
        free(indices);
        return LANTERN_GENESIS_ERR_INVALID_DATA;
    }

    *out_indices = indices;
    *out_count = count;
    *out_max_index = max_index;
    return LANTERN_GENESIS_OK;
}


/** @brief Validate that indices are unique and cover [0, max_index]. */
static int validate_registry_index_coverage(
    const size_t *indices,
    size_t count,
    size_t max_index,
    size_t *out_record_count)
{
    if (!indices || count == 0 || !out_record_count)
    {
        return LANTERN_GENESIS_ERR_INVALID_PARAM;
    }

    if (max_index == SIZE_MAX)
    {
        return LANTERN_GENESIS_ERR_OVERFLOW;
    }

    size_t record_count = max_index + 1;
    bool *seen = calloc(record_count, sizeof(*seen));
    if (!seen)
    {
        return LANTERN_GENESIS_ERR_OUT_OF_MEMORY;
    }

    for (size_t i = 0; i < count; ++i)
    {
        size_t idx = indices[i];
        if (idx >= record_count || seen[idx])
        {
            free(seen);
            return LANTERN_GENESIS_ERR_INVALID_DATA;
        }
        seen[idx] = true;
    }

    for (size_t i = 0; i < record_count; ++i)
    {
        if (!seen[i])
        {
            free(seen);
            return LANTERN_GENESIS_ERR_INVALID_DATA;
        }
    }

    free(seen);
    *out_record_count = record_count;
    return LANTERN_GENESIS_OK;
}


/** @brief Allocate and populate an index-only validator registry. */
static int build_index_only_registry(
    size_t record_count,
    struct lantern_validator_registry *registry)
{
    if (!registry || record_count == 0)
    {
        return LANTERN_GENESIS_ERR_INVALID_PARAM;
    }

    struct lantern_validator_record *records = calloc(record_count, sizeof(*records));
    if (!records)
    {
        return LANTERN_GENESIS_ERR_OUT_OF_MEMORY;
    }

    for (size_t i = 0; i < record_count; ++i)
    {
        records[i].index = (uint64_t)i;
    }

    registry->records = records;
    registry->count = record_count;
    return LANTERN_GENESIS_OK;
}


/** @brief Populate an index-only registry from mapping/scalar list indices. */
static int parse_validator_registry_mapping(
    const char *path,
    struct lantern_validator_registry *registry)
{
    if (!path || !registry)
    {
        return LANTERN_GENESIS_ERR_INVALID_PARAM;
    }

    size_t *indices = NULL;
    size_t count = 0;
    size_t max_index = 0;
    int result = collect_registry_mapping_indices(path, &indices, &count, &max_index);
    if (result != LANTERN_GENESIS_OK)
    {
        return result;
    }

    size_t record_count = 0;
    result = validate_registry_index_coverage(indices, count, max_index, &record_count);
    free(indices);
    if (result != LANTERN_GENESIS_OK)
    {
        return result;
    }

    return build_index_only_registry(record_count, registry);
}


/** @brief Scan registry objects to determine format and record count. */
static int scan_registry_objects(
    const LanternYamlObject *objects,
    size_t object_count,
    bool *out_has_pubkey_field,
    bool *out_have_explicit_indices,
    size_t *out_record_count)
{
    if (!objects
        || object_count == 0
        || !out_has_pubkey_field
        || !out_have_explicit_indices
        || !out_record_count)
    {
        return LANTERN_GENESIS_ERR_INVALID_PARAM;
    }

    bool has_pubkey_field = false;
    for (size_t i = 0; i < object_count; ++i)
    {
        if (yaml_object_value(&objects[i], VALIDATOR_REGISTRY_FIELD_PUBKEY))
        {
            has_pubkey_field = true;
            break;
        }
    }

    bool have_explicit_indices = false;
    size_t max_index = 0;
    for (size_t i = 0; i < object_count; ++i)
    {
        const char *index_val = yaml_object_value(&objects[i], VALIDATOR_REGISTRY_FIELD_INDEX);
        if (!index_val)
        {
            continue;
        }

        int ok = 0;
        uint64_t parsed_index = parse_u64(index_val, &ok);
        if (!ok || parsed_index > SIZE_MAX)
        {
            return LANTERN_GENESIS_ERR_INVALID_DATA;
        }

        have_explicit_indices = true;
        if ((size_t)parsed_index > max_index)
        {
            max_index = (size_t)parsed_index;
        }
    }

    if (have_explicit_indices && max_index == SIZE_MAX)
    {
        return LANTERN_GENESIS_ERR_OVERFLOW;
    }

    *out_has_pubkey_field = has_pubkey_field;
    *out_have_explicit_indices = have_explicit_indices;
    *out_record_count = have_explicit_indices ? (max_index + 1) : object_count;
    return LANTERN_GENESIS_OK;
}


/** @brief Populate registry records from YAML objects. */
static int populate_registry_records_from_objects(
    LanternYamlObject *objects,
    size_t object_count,
    bool has_pubkey_field,
    bool have_explicit_indices,
    struct lantern_validator_record *records,
    size_t record_count,
    bool *assigned)
{
    if (!objects || object_count == 0 || !records || record_count == 0 || !assigned)
    {
        return LANTERN_GENESIS_ERR_INVALID_PARAM;
    }

    for (size_t i = 0; i < object_count; ++i)
    {
        size_t slot = i;
        if (have_explicit_indices)
        {
            const char *index_val = yaml_object_value(&objects[i], VALIDATOR_REGISTRY_FIELD_INDEX);
            int ok = 0;
            uint64_t parsed_index = parse_u64(index_val, &ok);
            if (!index_val || !ok || parsed_index >= record_count)
            {
                return LANTERN_GENESIS_ERR_INVALID_DATA;
            }
            slot = (size_t)parsed_index;
        }

        if (assigned[slot])
        {
            return LANTERN_GENESIS_ERR_INVALID_DATA;
        }

        records[slot].index = (uint64_t)slot;

        if (has_pubkey_field)
        {
            const char *pubkey = yaml_object_value(&objects[i], VALIDATOR_REGISTRY_FIELD_PUBKEY);
            const char *withdrawal = yaml_object_value(
                &objects[i],
                VALIDATOR_REGISTRY_FIELD_WITHDRAWAL_CREDENTIALS);
            if (!pubkey || !withdrawal)
            {
                return LANTERN_GENESIS_ERR_INVALID_DATA;
            }

            records[slot].pubkey_hex = dup_trimmed(pubkey);
            records[slot].withdrawal_credentials_hex = dup_trimmed(withdrawal);
            if (!records[slot].pubkey_hex || !records[slot].withdrawal_credentials_hex)
            {
                return LANTERN_GENESIS_ERR_OUT_OF_MEMORY;
            }

            int rc = set_record_pubkey(&records[slot]);
            if (rc != LANTERN_GENESIS_OK)
            {
                return LANTERN_GENESIS_ERR_INVALID_DATA;
            }
        }

        assigned[slot] = true;
    }

    return LANTERN_GENESIS_OK;
}


/** @brief Validate full coverage for explicit-index registries. */
static int validate_registry_full_coverage(const bool *assigned, size_t record_count)
{
    if (!assigned || record_count == 0)
    {
        return LANTERN_GENESIS_ERR_INVALID_PARAM;
    }

    for (size_t i = 0; i < record_count; ++i)
    {
        if (!assigned[i])
        {
            return LANTERN_GENESIS_ERR_INVALID_DATA;
        }
    }

    return LANTERN_GENESIS_OK;
}


/** @brief Parse a validator registry from YAML objects (annotated or index-only). */
static int parse_validator_registry_objects(
    LanternYamlObject *objects,
    size_t object_count,
    struct lantern_validator_registry *registry)
{
    if (!objects || object_count == 0 || !registry)
    {
        return LANTERN_GENESIS_ERR_INVALID_PARAM;
    }

    bool has_pubkey_field = false;
    bool have_explicit_indices = false;
    size_t record_count = 0;

    int result = scan_registry_objects(
        objects,
        object_count,
        &has_pubkey_field,
        &have_explicit_indices,
        &record_count);
    if (result != LANTERN_GENESIS_OK)
    {
        return result;
    }

    struct lantern_validator_record *records = calloc(record_count, sizeof(*records));
    if (!records)
    {
        return LANTERN_GENESIS_ERR_OUT_OF_MEMORY;
    }

    bool *assigned = calloc(record_count, sizeof(*assigned));
    if (!assigned)
    {
        free(records);
        return LANTERN_GENESIS_ERR_OUT_OF_MEMORY;
    }

    struct lantern_validator_registry tmp = {.records = records, .count = record_count};

    result = populate_registry_records_from_objects(
        objects,
        object_count,
        has_pubkey_field,
        have_explicit_indices,
        records,
        record_count,
        assigned);
    if (result == LANTERN_GENESIS_OK && have_explicit_indices)
    {
        result = validate_registry_full_coverage(assigned, record_count);
    }

    free(assigned);

    if (result != LANTERN_GENESIS_OK)
    {
        genesis_free_validator_registry(&tmp);
        return result;
    }

    registry->records = records;
    registry->count = record_count;
    return LANTERN_GENESIS_OK;
}


int genesis_parse_validator_registry(const char *path, struct lantern_validator_registry *registry)
{
    if (!path || !registry)
    {
        return LANTERN_GENESIS_ERR_INVALID_PARAM;
    }

    size_t object_count = 0;
    LanternYamlObject *objects = lantern_yaml_read_array(
        path,
        VALIDATOR_REGISTRY_ARRAY_KEY,
        &object_count);
    if (!objects || object_count == 0)
    {
        lantern_yaml_free_objects(objects, object_count);
        return parse_validator_registry_mapping(path, registry);
    }

    int result = parse_validator_registry_objects(objects, object_count, registry);
    lantern_yaml_free_objects(objects, object_count);
    return result;
}


/** @brief Parse a validator-config.yaml entry into a config entry struct. */
static int parse_validator_config_entry(
    const LanternYamlObject *object,
    struct lantern_validator_config_entry *entry)
{
    const char *name_val = yaml_object_value(object, VALIDATOR_CONFIG_FIELD_NAME);
    const char *priv_val = yaml_object_value(object, VALIDATOR_CONFIG_FIELD_PRIVKEY);
    const char *count_val = yaml_object_value(object, VALIDATOR_CONFIG_FIELD_COUNT);
    const char *ip_val = yaml_object_value(object, VALIDATOR_CONFIG_FIELD_IP);
    const char *quic_val = yaml_object_value(object, VALIDATOR_CONFIG_FIELD_QUIC);
    const char *seq_val = yaml_object_value(object, VALIDATOR_CONFIG_FIELD_SEQ);
    const char *hash_dir_val = yaml_object_value(object, VALIDATOR_CONFIG_FIELD_HASH_SIG_DIR);

    entry->name = dup_trimmed(name_val);
    entry->privkey_hex = dup_trimmed(priv_val);
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
    entry->count = parse_u64(count_val, &ok);
    if (!ok || entry->count == 0)
    {
        return LANTERN_GENESIS_ERR_INVALID_DATA;
    }

    entry->enr.ip = dup_trimmed(ip_val);

    uint64_t quic_port = parse_u64(quic_val, &ok);
    if (!ok || quic_port > UINT16_MAX)
    {
        return LANTERN_GENESIS_ERR_INVALID_DATA;
    }
    entry->enr.quic_port = (uint16_t)quic_port;

    entry->enr.sequence = 1;
    if (seq_val && *seq_val)
    {
        entry->enr.sequence = parse_u64(seq_val, &ok);
        if (!ok)
        {
            return LANTERN_GENESIS_ERR_INVALID_DATA;
        }
    }

    entry->hash_sig_dir = dup_trimmed(hash_dir_val);
    return LANTERN_GENESIS_OK;
}


int genesis_parse_validator_config(const char *path, struct lantern_validator_config *config)
{
    if (!path || !config)
    {
        return LANTERN_GENESIS_ERR_INVALID_PARAM;
    }

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
    if (file_size <= 0)
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
