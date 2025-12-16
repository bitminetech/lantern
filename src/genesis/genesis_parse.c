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
static const size_t GENESIS_PEER_ID_BUFFER_LEN = 128;
static const size_t GENESIS_PUBKEY_HEX_BUFFER_LEN = (LANTERN_VALIDATOR_PUBKEY_SIZE * 2u) + 3u;

static const char *const CHAIN_CONFIG_KEY_GENESIS_TIME = "GENESIS_TIME";
static const char *const CHAIN_CONFIG_KEY_VALIDATOR_COUNT = "VALIDATOR_COUNT";
static const char *const CHAIN_CONFIG_KEY_GENESIS_VALIDATORS = "GENESIS_VALIDATORS";

static const char *const VALIDATOR_CONFIG_SCALAR_SHUFFLE = "shuffle";
static const char *const VALIDATOR_CONFIG_ARRAY_VALIDATORS = "validators";
static const char *const VALIDATOR_CONFIG_FIELD_NAME = "name";
static const char *const VALIDATOR_CONFIG_FIELD_PRIVKEY = "privkey";
static const char *const VALIDATOR_CONFIG_FIELD_COUNT = "count";
static const char *const VALIDATOR_CONFIG_FIELD_IP = "ip";
static const char *const VALIDATOR_CONFIG_FIELD_QUIC = "quic";
static const char *const VALIDATOR_CONFIG_FIELD_SEQ = "seq";
static const char *const VALIDATOR_CONFIG_FIELD_HASH_SIG_DIR = "hashSigDir";

static uint64_t parse_u64(const char *value, int *ok);
static char *dup_trimmed(const char *value);
static char *strip_optional_quotes(char *value);
static const char *yaml_object_value(const LanternYamlObject *object, const char *key);
static int read_scalar_value(const char *path, const char *key, char **out_value);
static enum lantern_validator_client_kind classify_validator_client(const char *name);
static int derive_peer_id_from_privkey_hex(const char *hex, char **out_peer_id);
static int decode_validator_pubkey_hex(const char *hex, uint8_t out[LANTERN_VALIDATOR_PUBKEY_SIZE]);

static int ensure_pubkey_capacity(uint8_t **pubkeys, size_t *cap, size_t required);
static int parse_validator_config_entry(
    const LanternYamlObject *object,
    struct lantern_validator_config_entry *entry);
static void free_validator_config_entry(struct lantern_validator_config_entry *entry);


/**
 * Parse an unsigned 64-bit integer from a string, allowing a trailing comment.
 *
 * The parsed value may be followed by whitespace and an optional `#` comment.
 * Callers must use `ok` to disambiguate a successful parse of `0` from failure.
 *
 * @param value Input string to parse (not modified).
 * @param ok    Optional output flag set to 1 on success, 0 on failure.
 *
 * @return Parsed value on success, 0 on failure.
 *
 * @note Thread safety: Thread-safe.
 */
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
    if (parsed > (unsigned long long)UINT64_MAX)
    {
        return 0;
    }

    if (ok)
    {
        *ok = 1;
    }
    return (uint64_t)parsed;
}


/**
 * Duplicate a string after trimming whitespace and optional surrounding quotes.
 *
 * @param value Input string to trim and duplicate.
 *
 * @return Newly allocated trimmed string, or NULL on allocation failure.
 *
 * @note Thread safety: Thread-safe.
 */
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


/**
 * Strip optional surrounding quotes from a YAML scalar (in place).
 *
 * Removes matching surrounding single/double quotes. The input buffer is
 * modified in place.
 *
 * @param value Input string buffer to modify.
 *
 * @return Pointer to the unquoted string within `value`.
 *
 * @note Thread safety: Thread-safe if callers provide exclusive access to `value`.
 */
static char *strip_optional_quotes(char *value)
{
    if (!value || *value == '\0')
    {
        return value;
    }

    if (*value == '"' || *value == '\'')
    {
        char quote = *value;
        ++value;
        char *endq = strrchr(value, quote);
        if (endq)
        {
            *endq = '\0';
        }
    }

    return value;
}


/**
 * Lookup a key value in a YAML object.
 *
 * @param object YAML object to search.
 * @param key    Key to match (exact string compare).
 *
 * @return Matching value pointer, or NULL if not found.
 *
 * @note Thread safety: Thread-safe.
 */
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
        *out_value = dup_trimmed(value);
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


/**
 * Decode a validator pubkey hex string into bytes.
 *
 * @param hex Pubkey as a hex string (no `0x` prefix expected).
 * @param out Output buffer for the decoded pubkey bytes.
 *
 * @return LANTERN_GENESIS_OK on success.
 * @return LANTERN_GENESIS_ERR_INVALID_PARAM on invalid parameters.
 * @return LANTERN_GENESIS_ERR_PARSE on decode failures.
 *
 * @note Thread safety: Thread-safe if callers provide exclusive access to outputs.
 */
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


/**
 * Ensure capacity for a packed pubkey buffer (count elements).
 *
 * Grows the allocation for `*pubkeys` to hold at least `required` pubkeys,
 * returning `LANTERN_VALIDATOR_PUBKEY_SIZE` bytes per element.
 *
 * @param pubkeys Pointer to the packed pubkey buffer pointer.
 * @param cap     Pointer to the current capacity in pubkey elements.
 * @param required Minimum required capacity in pubkey elements.
 *
 * @return LANTERN_GENESIS_OK on success.
 * @return LANTERN_GENESIS_ERR_INVALID_PARAM on invalid parameters.
 * @return LANTERN_GENESIS_ERR_OUT_OF_MEMORY on allocation failure.
 * @return LANTERN_GENESIS_ERR_OVERFLOW on capacity overflow.
 *
 * @note Thread safety: Not thread-safe. Caller must ensure exclusive access to `pubkeys` and `cap`.
 */
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
 * in `registry` using the packed pubkey buffer in `config`.
 *
 * @spec Lantern devnet genesis artifact files (lean quickstart).
 *
 * @param config   Chain config containing packed pubkeys.
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


/**
 * Parse chain configuration scalars from a chain config file.
 *
 * Parses the top-level `GENESIS_TIME` and `VALIDATOR_COUNT` scalars. Any prior
 * packed pubkeys in `config->validator_pubkeys` are freed and the pubkey fields
 * are reset.
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


/**
 * Parse genesis validator pubkeys from a chain config file.
 *
 * Reads the `GENESIS_VALIDATORS` list and returns a packed pubkey buffer. On
 * success, `*out_pubkeys` is caller-owned and must be freed with `free()`.
 *
 * @spec Lantern devnet genesis artifact files (lean quickstart).
 *
 * @param path        Path to the chain config YAML file.
 * @param out_pubkeys Output pointer for the packed pubkeys buffer.
 * @param out_count   Output pointer for the pubkey count.
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

        val = strip_optional_quotes(val);

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
    if (ip_val && !entry->enr.ip)
    {
        return LANTERN_GENESIS_ERR_OUT_OF_MEMORY;
    }

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
    if (hash_dir_val && !entry->hash_sig_dir)
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
