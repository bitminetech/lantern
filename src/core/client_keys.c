/**
 * @file client_keys.c
 * @brief XMSS key management for local validators
 *
 * Implements key loading, path resolution, and manifest parsing for xmss
 * cryptographic keys used by local validators.
 *
 * @note Lock ordering (acquire in this order to prevent deadlocks):
 *       1. state_lock
 *       2. status_lock
 *       3. pending_lock
 *       4. validator_lock
 *       5. connection_lock
 *       6. peer_vote_lock
 */

#include "client_internal.h"

#include <ctype.h>
#include <errno.h>
#include <inttypes.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "internal/yaml_parser.h"
#include "lantern/crypto/xmss.h"
#include "lantern/support/log.h"
#include "lantern/support/secure_mem.h"
#include "lantern/support/strings.h"


/* ============================================================================
 * Forward Declarations
 * ============================================================================ */

static int xmss_join_path(const char *dir, const char *leaf, char **out_path);
static bool xmss_size_add_overflow(size_t a, size_t b, size_t *out_sum);


/* ============================================================================
 * Constants
 * ============================================================================ */

static const size_t XMSS_HEX_PREFIX_LENGTH = 2u;
static const size_t XMSS_HEX_CHARS_PER_BYTE = 2u;
static const size_t XMSS_KEY_FILENAME_MAX_LEN = 64u;
static const size_t XMSS_WINDOWS_ABS_PATH_MIN_LEN = 3u;
static const size_t XMSS_WINDOWS_COLON_INDEX = 1u;
static const size_t XMSS_WINDOWS_SEPARATOR_INDEX = 2u;

static const char XMSS_DEFAULT_KEYS_DIR[] = "xmss-keys";


/* ============================================================================
 * Local Helpers
 * ============================================================================ */

static void free_local_secret_key_handles(struct lantern_local_validator *validator)
{
    if (!validator)
    {
        return;
    }

    if (validator->attestation_secret_key
        && validator->attestation_secret_key == validator->proposal_secret_key)
    {
        pq_secret_key_free(validator->attestation_secret_key);
    }
    else
    {
        if (validator->attestation_secret_key)
        {
            pq_secret_key_free(validator->attestation_secret_key);
        }
        if (validator->proposal_secret_key)
        {
            pq_secret_key_free(validator->proposal_secret_key);
        }
    }

    validator->attestation_secret_key = NULL;
    validator->proposal_secret_key = NULL;
    free(validator->proposal_secret_path);
    validator->proposal_secret_path = NULL;
    validator->has_attestation_secret_handle = false;
    validator->has_proposal_secret_handle = false;
}


/* ============================================================================
 * Local Validator Lifecycle
 * ============================================================================ */

/**
 * Clean up a single local validator's resources.
 *
 * @spec subspecs/xmss/keygen.py - key management
 *
 * @param validator  Validator to clean up
 *
 * @note Thread safety: Caller must ensure exclusive access to the validator
 */
void lantern_client_local_validator_cleanup(struct lantern_local_validator *validator)
{
    if (!validator)
    {
        return;
    }

    if (validator->secret)
    {
        if (validator->secret_len > 0)
        {
            lantern_secure_zero(validator->secret, validator->secret_len);
        }
        free(validator->secret);
        validator->secret = NULL;
    }
    validator->secret_len = 0;
    validator->has_secret = false;

    free_local_secret_key_handles(validator);

    validator->last_proposed_slot = UINT64_MAX;
    validator->last_attested_slot = UINT64_MAX;
}


/**
 * Reset all local validators and free resources.
 *
 * @spec subspecs/xmss/keygen.py - key management
 *
 * @param client  Client instance
 *
 * @note Thread safety: Caller must ensure exclusive access during shutdown
 */
void lantern_client_reset_local_validators(struct lantern_client *client)
{
    if (!client)
    {
        return;
    }

    if (client->local_validators)
    {
        for (size_t i = 0; i < client->local_validator_count; ++i)
        {
            lantern_client_local_validator_cleanup(&client->local_validators[i]);
        }
        free(client->local_validators);
        client->local_validators = NULL;
    }
    client->local_validator_count = 0;
}


/* ============================================================================
 * Secret Key Decoding
 * ============================================================================ */

/**
 * Decode a hex-encoded validator secret key.
 *
 * @spec subspecs/xmss/keygen.py - key encoding
 *
 * @param hex      Hex string (with optional 0x prefix)
 * @param out_key  Output buffer (caller must free)
 * @param out_len  Output length
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM if any parameter is NULL
 * @return LANTERN_CLIENT_ERR_ALLOC if allocation fails
 * @return LANTERN_CLIENT_ERR_VALIDATOR if the hex string is invalid
 *
 * @note Thread safety: This function is thread-safe
 */
int lantern_client_decode_validator_secret(
    const char *hex,
    uint8_t **out_key,
    size_t *out_len)
{
    if (!hex || !out_key || !out_len)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    *out_key = NULL;
    *out_len = 0;

    int result = LANTERN_CLIENT_ERR_VALIDATOR;
    char *dup = NULL;
    size_t dup_len = 0;
    uint8_t *secret = NULL;
    size_t secret_len = 0;

    dup = lantern_string_duplicate(hex);
    if (!dup)
    {
        return LANTERN_CLIENT_ERR_ALLOC;
    }
    dup_len = strlen(dup);

    char *trimmed = lantern_trim_whitespace(dup);
    if (!trimmed || *trimmed == '\0')
    {
        goto cleanup;
    }

    const char *hex_start = trimmed;
    if (hex_start[0] == '0' && (hex_start[1] == 'x' || hex_start[1] == 'X'))
    {
        hex_start += XMSS_HEX_PREFIX_LENGTH;
    }
    size_t hex_len = strlen(hex_start);
    if (hex_len == 0 || (hex_len % XMSS_HEX_CHARS_PER_BYTE) != 0)
    {
        goto cleanup;
    }

    secret_len = hex_len / XMSS_HEX_CHARS_PER_BYTE;
    secret = malloc(secret_len);
    if (!secret)
    {
        result = LANTERN_CLIENT_ERR_ALLOC;
        goto cleanup;
    }

    if (lantern_hex_decode(hex_start, secret, secret_len) != 0)
    {
        goto cleanup;
    }

    *out_key = secret;
    *out_len = secret_len;
    secret = NULL;
    secret_len = 0;
    result = LANTERN_CLIENT_OK;

cleanup:
    if (secret)
    {
        if (secret_len > 0)
        {
            lantern_secure_zero(secret, secret_len);
        }
        free(secret);
    }
    if (dup)
    {
        if (dup_len > 0)
        {
            lantern_secure_zero(dup, dup_len);
        }
        free(dup);
    }
    return result;
}


/* ============================================================================
 * Hash-Sig Manifest Types
 * ============================================================================ */

/**
 * Entry in a xmss key manifest.
 */
struct xmss_manifest_entry
{
    uint64_t index;                /**< Validator global index */
    char *attestation_secret_file; /**< Attestation secret key path or filename */
    char *proposal_secret_file;    /**< Proposal secret key path or filename */
};


/**
 * XMSS key manifest containing validator key paths.
 */
struct xmss_manifest
{
    struct xmss_manifest_entry *entries; /**< Manifest entries */
    size_t count;                            /**< Entry count */
};


/* ============================================================================
 * Hash-Sig Manifest Functions
 * ============================================================================ */

/**
 * Initialize a manifest structure.
 *
 * @param manifest  Manifest to initialize
 *
 * @note Thread safety: This function is thread-safe
 */
static void xmss_manifest_init(struct xmss_manifest *manifest)
{
    if (!manifest)
    {
        return;
    }
    manifest->entries = NULL;
    manifest->count = 0;
}


/**
 * Reset and free manifest resources.
 *
 * @param manifest  Manifest to reset
 *
 * @note Thread safety: This function is thread-safe
 */
static void xmss_manifest_reset(struct xmss_manifest *manifest)
{
    if (!manifest)
    {
        return;
    }

    if (!manifest->entries)
    {
        manifest->count = 0;
        return;
    }
    for (size_t i = 0; i < manifest->count; ++i)
    {
        free(manifest->entries[i].attestation_secret_file);
        free(manifest->entries[i].proposal_secret_file);
    }
    free(manifest->entries);
    manifest->entries = NULL;
    manifest->count = 0;
}


/**
 * Get a string value from a YAML object.
 *
 * @param object  YAML object
 * @param key     Key to look up
 * @return Value string or NULL if not found
 *
 * @note Thread safety: This function is thread-safe
 */
static const char *xmss_yaml_value(const LanternYamlObject *object, const char *key)
{
    if (!object || !key || !object->pairs)
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
 * Parse a uint64 from text.
 *
 * @param text       Text to parse
 * @param out_value  Output value
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM if any parameter is NULL
 * @return LANTERN_CLIENT_ERR_CONFIG if parsing fails
 *
 * @note Thread safety: This function is thread-safe
 */
static int xmss_parse_u64(const char *text, uint64_t *out_value)
{
    if (!text || !out_value)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    char *end = NULL;
    errno = 0;
    unsigned long long parsed = strtoull(text, &end, 0);
    if (errno != 0 || end == text)
    {
        return LANTERN_CLIENT_ERR_CONFIG;
    }

    while (*end != '\0' && isspace((unsigned char)*end))
    {
        ++end;
    }
    if (*end != '\0')
    {
        return LANTERN_CLIENT_ERR_CONFIG;
    }
    if (parsed > UINT64_MAX)
    {
        return LANTERN_CLIENT_ERR_CONFIG;
    }

    *out_value = (uint64_t)parsed;
    return LANTERN_CLIENT_OK;
}


enum xmss_secret_key_role
{
    XMSS_SECRET_KEY_ROLE_UNKNOWN = 0,
    XMSS_SECRET_KEY_ROLE_ATTESTATION,
    XMSS_SECRET_KEY_ROLE_PROPOSAL,
};


static const char *xmss_path_basename(const char *path)
{
    if (!path)
    {
        return NULL;
    }

    const char *slash = strrchr(path, '/');
    const char *backslash = strrchr(path, '\\');
    const char *sep = slash;
    if (backslash && (!sep || backslash > sep))
    {
        sep = backslash;
    }
    return sep ? (sep + 1) : path;
}


static bool xmss_string_ends_with(const char *value, const char *suffix)
{
    if (!value || !suffix)
    {
        return false;
    }

    size_t value_len = strlen(value);
    size_t suffix_len = strlen(suffix);
    if (value_len < suffix_len)
    {
        return false;
    }

    return strcmp(value + (value_len - suffix_len), suffix) == 0;
}


static enum xmss_secret_key_role xmss_classify_secret_key_file(const char *path)
{
    const char *basename = xmss_path_basename(path);
    if (!basename || basename[0] == '\0')
    {
        return XMSS_SECRET_KEY_ROLE_UNKNOWN;
    }

    if (xmss_string_ends_with(basename, "_attester_key_sk.ssz")
        || xmss_string_ends_with(basename, "_attester_key_sk.json"))
    {
        return XMSS_SECRET_KEY_ROLE_ATTESTATION;
    }
    if (xmss_string_ends_with(basename, "_proposer_key_sk.ssz")
        || xmss_string_ends_with(basename, "_proposer_key_sk.json"))
    {
        return XMSS_SECRET_KEY_ROLE_PROPOSAL;
    }

    return XMSS_SECRET_KEY_ROLE_UNKNOWN;
}


static int xmss_manifest_load_annotated(
    const char *path,
    const char *node_id,
    struct xmss_manifest *manifest)
{
    int result = LANTERN_CLIENT_ERR_CONFIG;
    LanternYamlObject *objects = NULL;
    size_t count = 0;
    struct xmss_manifest_entry *entries = NULL;
    size_t entry_count = 0;

    if (!path || !node_id || !manifest)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    xmss_manifest_reset(manifest);

    objects = lantern_yaml_read_array(path, node_id, &count);
    if (!objects || count == 0)
    {
        result = LANTERN_CLIENT_ERR_CONFIG;
        goto cleanup;
    }

    if (count > (SIZE_MAX / sizeof(*entries)))
    {
        result = LANTERN_CLIENT_ERR_CONFIG;
        goto cleanup;
    }
    entries = calloc(count, sizeof(*entries));
    if (!entries)
    {
        result = LANTERN_CLIENT_ERR_ALLOC;
        goto cleanup;
    }

    for (size_t i = 0; i < count; ++i)
    {
        const char *index_text = xmss_yaml_value(&objects[i], "index");
        const char *pubkey_hex = xmss_yaml_value(&objects[i], "pubkey_hex");
        const char *secret_file = xmss_yaml_value(&objects[i], "privkey_file");
        if (!index_text || !pubkey_hex || !secret_file)
        {
            result = LANTERN_CLIENT_ERR_CONFIG;
            goto cleanup;
        }

        uint64_t index = 0;
        result = xmss_parse_u64(index_text, &index);
        if (result != 0)
        {
            goto cleanup;
        }

        size_t slot = entry_count;
        for (size_t j = 0; j < entry_count; ++j)
        {
            if (entries[j].index == index)
            {
                slot = j;
                break;
            }
        }
        if (slot == entry_count)
        {
            entries[slot].index = index;
            ++entry_count;
        }

        struct xmss_manifest_entry *entry = &entries[slot];
        enum xmss_secret_key_role role = xmss_classify_secret_key_file(secret_file);
        if (role == XMSS_SECRET_KEY_ROLE_UNKNOWN)
        {
            result = LANTERN_CLIENT_ERR_CONFIG;
            goto cleanup;
        }

        char **secret_dst =
            (role == XMSS_SECRET_KEY_ROLE_ATTESTATION)
                ? &entry->attestation_secret_file
                : &entry->proposal_secret_file;
        if (*secret_dst)
        {
            result = LANTERN_CLIENT_ERR_CONFIG;
            goto cleanup;
        }

        *secret_dst = lantern_string_duplicate(secret_file);
        if (!*secret_dst)
        {
            result = LANTERN_CLIENT_ERR_ALLOC;
            goto cleanup;
        }
    }

    for (size_t i = 0; i < entry_count; ++i)
    {
        if (!entries[i].attestation_secret_file
            || !entries[i].proposal_secret_file)
        {
            result = LANTERN_CLIENT_ERR_CONFIG;
            goto cleanup;
        }
    }

    manifest->entries = entries;
    manifest->count = entry_count;
    entries = NULL;
    result = LANTERN_CLIENT_OK;

cleanup:
    lantern_yaml_free_objects(objects, count);
    if (entries)
    {
        struct xmss_manifest tmp = {.entries = entries, .count = entry_count};
        xmss_manifest_reset(&tmp);
    }
    return result;
}


/**
 * Find an entry in a manifest by validator index.
 *
 * @param manifest  Manifest to search
 * @param index     Validator index
 * @return Entry pointer or NULL if not found
 *
 * @note Thread safety: This function is thread-safe
 */
static const struct xmss_manifest_entry *xmss_manifest_find(
    const struct xmss_manifest *manifest,
    uint64_t index)
{
    if (!manifest || !manifest->entries)
    {
        return NULL;
    }
    for (size_t i = 0; i < manifest->count; ++i)
    {
        if (manifest->entries[i].index == index)
        {
            return &manifest->entries[i];
        }
    }
    return NULL;
}


/* ============================================================================
 * Path Resolution Helpers
 * ============================================================================ */

/**
 * Return value if non-empty, otherwise NULL.
 *
 * @param value  String to check
 * @return value if non-empty, NULL otherwise
 *
 * @note Thread safety: This function is thread-safe
 */
static const char *xmss_non_empty(const char *value)
{
    return (value && value[0] != '\0') ? value : NULL;
}


/**
 * Add two size_t values with overflow checking.
 *
 * @param a        First value
 * @param b        Second value
 * @param out_sum  Output sum
 * @return true if overflow would occur, false otherwise
 *
 * @note Thread safety: This function is thread-safe
 */
static bool xmss_size_add_overflow(size_t a, size_t b, size_t *out_sum)
{
    if (!out_sum)
    {
        return true;
    }
    if (SIZE_MAX - a < b)
    {
        return true;
    }
    *out_sum = a + b;
    return false;
}


/**
 * Join a directory and filename into a path.
 *
 * @param dir       Directory path
 * @param leaf      Filename
 * @param out_path  Output path (caller must free)
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM if any parameter is NULL
 * @return LANTERN_CLIENT_ERR_ALLOC if allocation fails
 * @return LANTERN_CLIENT_ERR_CONFIG if path length overflows
 *
 * @note Thread safety: This function is thread-safe
 */
static int xmss_join_path(const char *dir, const char *leaf, char **out_path)
{
    if (!dir || !leaf || !out_path)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    *out_path = NULL;

    size_t dir_len = strlen(dir);
    size_t leaf_len = strlen(leaf);
    bool need_sep = dir_len > 0 && dir[dir_len - 1] != '/' && dir[dir_len - 1] != '\\';
    size_t total = 0;
    if (xmss_size_add_overflow(dir_len, need_sep ? 1u : 0u, &total)
        || xmss_size_add_overflow(total, leaf_len, &total)
        || xmss_size_add_overflow(total, 1u, &total))
    {
        return LANTERN_CLIENT_ERR_CONFIG;
    }
    char *buffer = malloc(total);
    if (!buffer)
    {
        return LANTERN_CLIENT_ERR_ALLOC;
    }
    memcpy(buffer, dir, dir_len);
    size_t offset = dir_len;
    if (need_sep)
    {
        buffer[offset++] = '/';
    }
    memcpy(buffer + offset, leaf, leaf_len);
    buffer[offset + leaf_len] = '\0';
    *out_path = buffer;
    return LANTERN_CLIENT_OK;
}


static bool xmss_file_exists(const char *path)
{
    if (!path || path[0] == '\0')
    {
        return false;
    }

    FILE *fp = fopen(path, "rb");
    if (!fp)
    {
        return false;
    }

    fclose(fp);
    return true;
}


static int xmss_resolve_validator_keys_path(
    const struct lantern_client *client,
    char **out_path)
{
    if (!client || !out_path)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    *out_path = NULL;

    if (client->genesis_paths.validator_registry_path
        && client->genesis_paths.validator_registry_path[0] != '\0')
    {
        *out_path = lantern_string_duplicate(client->genesis_paths.validator_registry_path);
        if (!*out_path)
        {
            return LANTERN_CLIENT_ERR_ALLOC;
        }
        return LANTERN_CLIENT_OK;
    }

    return LANTERN_CLIENT_ERR_CONFIG;
}


/**
 * Format a template path with a validator index.
 *
 * @param template   Path template with %llu placeholder
 * @param index      Validator index
 * @param out_path   Output path (caller must free)
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM if any parameter is NULL
 * @return LANTERN_CLIENT_ERR_ALLOC if allocation fails
 * @return LANTERN_CLIENT_ERR_CONFIG if the template is invalid or overflows
 *
 * @note Thread safety: This function is thread-safe
 */
static int xmss_format_index_template(const char *template, uint64_t index, char **out_path)
{
    if (!template || !out_path)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    *out_path = NULL;

    unsigned long long value = (unsigned long long)index;
    int required = snprintf(NULL, 0, template, value);
    if (required < 0 || (size_t)required > SIZE_MAX - 1u)
    {
        return LANTERN_CLIENT_ERR_CONFIG;
    }
    size_t length = (size_t)required + 1u;
    char *buffer = malloc(length);
    if (!buffer)
    {
        return LANTERN_CLIENT_ERR_ALLOC;
    }
    if (snprintf(buffer, length, template, value) < 0)
    {
        free(buffer);
        return LANTERN_CLIENT_ERR_CONFIG;
    }
    *out_path = buffer;
    return LANTERN_CLIENT_OK;
}


/**
 * Derive a default key directory from genesis paths.
 *
 * @param paths  Genesis paths
 * @return Derived directory path (caller must free) or NULL
 *
 * @note Thread safety: This function is thread-safe
 */
static char *xmss_derive_default_dir(const struct lantern_genesis_paths *paths)
{
    if (!paths || !paths->validator_config_path)
    {
        return NULL;
    }
    const char *config_path = paths->validator_config_path;
    const char *slash = strrchr(config_path, '/');
    const char *backslash = strrchr(config_path, '\\');
    const char *sep = slash;
    if (backslash && (!sep || backslash > sep))
    {
        sep = backslash;
    }
    if (!sep)
    {
        return NULL;
    }
    size_t dir_len = (size_t)(sep - config_path);
    if (dir_len == 0)
    {
        return NULL;
    }
    size_t suffix_len = strlen(XMSS_DEFAULT_KEYS_DIR);
    size_t total = 0;
    if (xmss_size_add_overflow(dir_len, 1u, &total)
        || xmss_size_add_overflow(total, suffix_len, &total)
        || xmss_size_add_overflow(total, 1u, &total))
    {
        return NULL;
    }
    char *buffer = malloc(total);
    if (!buffer)
    {
        return NULL;
    }
    memcpy(buffer, config_path, dir_len);
    buffer[dir_len] = '/';
    memcpy(buffer + dir_len + 1, XMSS_DEFAULT_KEYS_DIR, suffix_len);
    buffer[dir_len + 1 + suffix_len] = '\0';
    return buffer;
}


/**
 * Clear secret key handles from all local validators.
 *
 * @param client  Client instance
 *
 * @note Thread safety: Caller must ensure exclusive access during key operations
 */
static void clear_local_secret_handles(struct lantern_client *client)
{
    if (!client || !client->local_validators)
    {
        return;
    }
    for (size_t i = 0; i < client->local_validator_count; ++i)
    {
        free_local_secret_key_handles(&client->local_validators[i]);
    }
}


/**
 * Check if a path is absolute.
 *
 * @param path  Path to check
 * @return true if absolute, false otherwise
 *
 * @note Thread safety: This function is thread-safe
 */
static bool xmss_path_is_absolute(const char *path)
{
    if (!path || path[0] == '\0')
    {
        return false;
    }
    if (path[0] == '/' || path[0] == '\\')
    {
        return true;
    }
    if (strlen(path) >= XMSS_WINDOWS_ABS_PATH_MIN_LEN
        && isalpha((unsigned char)path[0])
        && path[XMSS_WINDOWS_COLON_INDEX] == ':'
        && (path[XMSS_WINDOWS_SEPARATOR_INDEX] == '/'
            || path[XMSS_WINDOWS_SEPARATOR_INDEX] == '\\'))
    {
        return true;
    }
    return false;
}


/**
 * Resolve the path to a validator's secret key file.
 *
 * @param client    Client instance
 * @param manifest  Optional manifest
 * @param index     Validator global index
 * @param use_proposal_key Select the proposal secret key path when true,
 *                         attestation secret key path otherwise
 * @param out_path  Output path (caller must free)
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM if any parameter is NULL
 * @return LANTERN_CLIENT_ERR_ALLOC if allocation fails
 * @return LANTERN_CLIENT_ERR_CONFIG if no path can be resolved
 *
 * @note Thread safety: This function is thread-safe
 */
static int resolve_secret_key_path(
    struct lantern_client *client,
    const struct xmss_manifest *manifest,
    uint64_t index,
    bool use_proposal_key,
    char **out_path)
{
    if (!client || !out_path)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    *out_path = NULL;

    if (client->xmss_secret_template)
    {
        return xmss_format_index_template(client->xmss_secret_template, index, out_path);
    }
    if (manifest)
    {
        const struct xmss_manifest_entry *entry = xmss_manifest_find(manifest, index);
        const char *secret_file =
            entry
                ? (use_proposal_key ? entry->proposal_secret_file : entry->attestation_secret_file)
                : NULL;
        if (secret_file)
        {
            if (xmss_path_is_absolute(secret_file))
            {
                char *copy = lantern_string_duplicate(secret_file);
                if (!copy)
                {
                    return LANTERN_CLIENT_ERR_ALLOC;
                }
                *out_path = copy;
                return LANTERN_CLIENT_OK;
            }
            if (client->xmss_key_dir)
            {
                return xmss_join_path(client->xmss_key_dir, secret_file, out_path);
            }
        }
    }
    if (client->xmss_key_dir)
    {
        char filename[XMSS_KEY_FILENAME_MAX_LEN];
        int written = snprintf(filename, sizeof(filename), "validator_%" PRIu64 "_sk.json", index);
        if (written < 0 || (size_t)written >= sizeof(filename))
        {
            return LANTERN_CLIENT_ERR_CONFIG;
        }
        return xmss_join_path(client->xmss_key_dir, filename, out_path);
    }
    if (client->xmss_secret_path)
    {
        if (client->validator_assignment.count > 1)
        {
            return LANTERN_CLIENT_ERR_CONFIG;
        }
        char *copy = lantern_string_duplicate(client->xmss_secret_path);
        if (!copy)
        {
            return LANTERN_CLIENT_ERR_ALLOC;
        }
        *out_path = copy;
        return LANTERN_CLIENT_OK;
    }
    return LANTERN_CLIENT_ERR_CONFIG;
}


/* ============================================================================
 * Secret Key Loading
 * ============================================================================ */

/**
 * Load xmss secret keys for all local validators.
 *
 * @param client    Client instance
 * @param manifest  Optional manifest
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM if client is NULL
 *
 * @note Thread safety: Caller must ensure exclusive access during key operations
 */
static int load_xmss_secret_keys(
    struct lantern_client *client,
    const struct xmss_manifest *manifest)
{
    if (!client)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    if (client->local_validator_count == 0)
    {
        return LANTERN_CLIENT_OK;
    }

    bool has_template = client->xmss_secret_template != NULL;
    bool has_dir = client->xmss_key_dir != NULL;
    bool has_single = (client->xmss_secret_path != NULL)
        && (client->validator_assignment.count == 1);
    if (!has_template && !has_dir && !has_single)
    {
        lantern_log_debug(
            "crypto",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "xmss secret key sources unavailable; skipping local key load");
        return LANTERN_CLIENT_OK;
    }

    clear_local_secret_handles(client);
    struct lantern_log_metadata meta = {.validator = client->node_id};
    size_t resolved = 0;
    size_t loaded = 0;
    for (size_t i = 0; i < client->local_validator_count; ++i)
    {
        struct lantern_local_validator *validator = &client->local_validators[i];
        char *attestation_path = NULL;
        char *proposal_path = NULL;
        if (resolve_secret_key_path(
                client,
                manifest,
                validator->global_index,
                false,
                &attestation_path)
            != 0)
        {
            lantern_log_warn(
                "crypto",
                &meta,
                "unable to resolve attestation xmss secret key path for validator=%" PRIu64 "; skipping",
                validator->global_index);
            continue;
        }
        if (resolve_secret_key_path(
                client,
                manifest,
                validator->global_index,
                true,
                &proposal_path)
            != 0)
        {
            lantern_log_warn(
                "crypto",
                &meta,
                "unable to resolve proposal xmss secret key path for validator=%" PRIu64 "; skipping",
                validator->global_index);
            free(attestation_path);
            free(proposal_path);
            continue;
        }
        ++resolved;
        lantern_log_debug(
            "crypto",
            &meta,
            "xmss secret key paths resolved validator=%" PRIu64 " attestation=%s proposal=%s",
            validator->global_index,
            attestation_path,
            proposal_path);

        struct PQSignatureSchemeSecretKey *attestation_secret = NULL;
        if (lantern_xmss_load_secret_file(attestation_path, &attestation_secret) != 0)
        {
            lantern_log_warn(
                "crypto",
                &meta,
                "failed to load attestation xmss secret key validator=%" PRIu64 " path=%s; skipping",
                validator->global_index,
                attestation_path);
            free(attestation_path);
            free(proposal_path);
            continue;
        }
        char *owned_proposal_path = lantern_string_duplicate(proposal_path);
        if (!owned_proposal_path)
        {
            lantern_log_warn(
                "crypto",
                &meta,
                "failed to retain proposal xmss secret key path validator=%" PRIu64 " path=%s; skipping",
                validator->global_index,
                proposal_path);
            pq_secret_key_free(attestation_secret);
            free(attestation_path);
            free(proposal_path);
            continue;
        }
        free(attestation_path);
        free(proposal_path);

        validator->attestation_secret_key = attestation_secret;
        validator->proposal_secret_key = NULL;
        validator->proposal_secret_path = owned_proposal_path;
        validator->has_attestation_secret_handle = true;
        validator->has_proposal_secret_handle = false;
        ++loaded;
    }
    lantern_log_info(
        "crypto",
        &meta,
        "xmss secret key pairs loaded=%zu/%zu resolved=%zu dir=%s template=%s",
        loaded,
        client->local_validator_count,
        resolved,
        client->xmss_key_dir ? client->xmss_key_dir : "-",
        client->xmss_secret_template ? client->xmss_secret_template : "-");
    return LANTERN_CLIENT_OK;
}


/* ============================================================================
 * Public Key Management
 * ============================================================================ */

/**
 * Free all loaded public key handles.
 *
 * @spec subspecs/xmss/keygen.py - key management
 *
 * @param client  Client instance
 *
 * @note Thread safety: Caller must ensure exclusive access during shutdown
 */
void lantern_client_free_xmss_pubkeys(struct lantern_client *client)
{
    if (!client || !client->validator_pubkeys)
    {
        return;
    }
    for (size_t i = 0; i < client->validator_pubkey_count; ++i)
    {
        if (client->validator_pubkeys[i])
        {
            pq_public_key_free(client->validator_pubkeys[i]);
            client->validator_pubkeys[i] = NULL;
        }
    }
    free(client->validator_pubkeys);
    client->validator_pubkeys = NULL;
    client->validator_pubkey_count = 0;
}


/* ============================================================================
 * Key Source Configuration
 * ============================================================================ */

/**
 * Configure xmss key sources from options and environment.
 *
 * @spec subspecs/xmss/keygen.py - key management
 *
 * @param client   Client instance
 * @param options  Client options
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM if any parameter is NULL
 * @return LANTERN_CLIENT_ERR_ALLOC if allocation fails
 *
 * @note Thread safety: This function should be called during initialization
 */
int lantern_client_configure_xmss_sources(
    struct lantern_client *client,
    const struct lantern_client_options *options)
{
    if (!client || !options)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    struct lantern_log_metadata meta = {.validator = client->node_id};
    const char *env_dir = xmss_non_empty(getenv("XMSS_KEY_DIR"));
    const char *env_public_path = xmss_non_empty(getenv("XMSS_PK_PATH"));
    const char *env_secret_path = xmss_non_empty(getenv("XMSS_SK_PATH"));
    const char *env_public_template = xmss_non_empty(getenv("XMSS_PK_TEMPLATE"));
    const char *env_secret_template = xmss_non_empty(getenv("XMSS_SK_TEMPLATE"));

    const char *resolved_dir = xmss_non_empty(options->xmss_key_dir);
    if (!resolved_dir)
    {
        resolved_dir = env_dir;
    }
    if (!resolved_dir && client->assigned_validators && client->assigned_validators->xmss_dir)
    {
        resolved_dir = client->assigned_validators->xmss_dir;
    }
    if (resolved_dir)
    {
        if (set_owned_string(&client->xmss_key_dir, resolved_dir) != 0)
        {
            return LANTERN_CLIENT_ERR_ALLOC;
        }
    }
    else
    {
        char *derived = xmss_derive_default_dir(&client->genesis_paths);
        if (derived)
        {
            int rc = set_owned_string(&client->xmss_key_dir, derived);
            free(derived);
            if (rc != 0)
            {
                return LANTERN_CLIENT_ERR_ALLOC;
            }
        }
    }

    const char *resolved_public_template = xmss_non_empty(options->xmss_public_template);
    if (!resolved_public_template)
    {
        resolved_public_template = env_public_template;
    }
    if (resolved_public_template)
    {
        if (set_owned_string(&client->xmss_public_template, resolved_public_template) != 0)
        {
            return LANTERN_CLIENT_ERR_ALLOC;
        }
    }

    const char *resolved_secret_template = xmss_non_empty(options->xmss_secret_template);
    if (!resolved_secret_template)
    {
        resolved_secret_template = env_secret_template;
    }
    if (resolved_secret_template)
    {
        if (set_owned_string(&client->xmss_secret_template, resolved_secret_template) != 0)
        {
            return LANTERN_CLIENT_ERR_ALLOC;
        }
    }

    const char *resolved_public_path = xmss_non_empty(options->xmss_public_path);
    if (!resolved_public_path)
    {
        resolved_public_path = env_public_path;
    }
    if (resolved_public_path)
    {
        if (set_owned_string(&client->xmss_public_path, resolved_public_path) != 0)
        {
            return LANTERN_CLIENT_ERR_ALLOC;
        }
    }

    const char *resolved_secret_path = xmss_non_empty(options->xmss_secret_path);
    if (!resolved_secret_path)
    {
        resolved_secret_path = env_secret_path;
    }
    if (resolved_secret_path)
    {
        if (set_owned_string(&client->xmss_secret_path, resolved_secret_path) != 0)
        {
            return LANTERN_CLIENT_ERR_ALLOC;
        }
    }
    lantern_log_info(
        "crypto",
        &meta,
        "xmss sources resolved dir=%s annotated_validators=%s pk_path=%s sk_path=%s pk_template=%s sk_template=%s",
        client->xmss_key_dir ? client->xmss_key_dir : "-",
        client->genesis_paths.validator_registry_path ? client->genesis_paths.validator_registry_path : "-",
        client->xmss_public_path ? client->xmss_public_path : "-",
        client->xmss_secret_path ? client->xmss_secret_path : "-",
        client->xmss_public_template ? client->xmss_public_template : "-",
        client->xmss_secret_template ? client->xmss_secret_template : "-");
    return LANTERN_CLIENT_OK;
}


/* ============================================================================
 * Key Loading Entry Point
 * ============================================================================ */

/**
 * Load all xmss keys for the client.
 *
 * @spec subspecs/xmss/keygen.py - key loading
 *
 * @param client  Client instance
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM if client is NULL
 * @return LANTERN_CLIENT_ERR_ALLOC if allocation fails
 * @return LANTERN_CLIENT_ERR_RUNTIME if xmss bindings are unavailable
 *
 * @note Thread safety: This function should be called during initialization
 */
int lantern_client_load_xmss_keys(struct lantern_client *client)
{
    if (!client)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    struct lantern_log_metadata meta = {.validator = client->node_id};
    if (!lantern_xmss_is_available())
    {
        lantern_log_error(
            "crypto",
            &meta,
            "xmss bindings unavailable");
        return LANTERN_CLIENT_ERR_RUNTIME;
    }

    struct xmss_manifest manifest;
    xmss_manifest_init(&manifest);
    bool manifest_loaded = false;
    char *annotated_path = NULL;

    int annotated_path_result = xmss_resolve_validator_keys_path(
        client,
        &annotated_path);
    if (annotated_path_result == LANTERN_CLIENT_OK && annotated_path)
    {
        bool have_annotated_file = xmss_file_exists(annotated_path);
        if (have_annotated_file)
        {
            int manifest_result = xmss_manifest_load_annotated(
                annotated_path,
                client->node_id,
                &manifest);
            if (manifest_result == LANTERN_CLIENT_OK)
            {
                manifest_loaded = true;
            }
            else
            {
                free(annotated_path);
                xmss_manifest_reset(&manifest);
                return manifest_result;
            }
        }
    }
    else if (annotated_path_result != LANTERN_CLIENT_ERR_CONFIG)
    {
        xmss_manifest_reset(&manifest);
        return annotated_path_result;
    }

    const struct xmss_manifest *manifest_ptr = manifest_loaded ? &manifest : NULL;
    lantern_log_info(
        "crypto",
        &meta,
        "xmss load start key_dir=%s annotated_validators=%s manifest=%s validators=%" PRIu64 " local=%zu",
        client->xmss_key_dir ? client->xmss_key_dir : "-",
        annotated_path ? annotated_path : "-",
        manifest_loaded ? "loaded" : "missing",
        client->genesis.chain_config.validator_count,
        client->local_validator_count);
    /* Note: load_xmss_public_keys removed - per LeanSpec, verification uses
     * 52-byte serialized pubkeys from state, not full JSON key handles */
    if (client->local_validator_count > 0)
    {
        int result = load_xmss_secret_keys(client, manifest_ptr);
        if (result != 0)
        {
            free(annotated_path);
            xmss_manifest_reset(&manifest);
            return result;
        }
    }
    free(annotated_path);
    xmss_manifest_reset(&manifest);
    return LANTERN_CLIENT_OK;
}
