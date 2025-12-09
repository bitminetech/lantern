/**
 * @file client_keys.c
 * @brief Hash-sig key management for local validators
 *
 * Implements key loading, path resolution, and manifest parsing for hash-sig
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

#include "lantern/crypto/hash_sig.h"
#include "lantern/support/log.h"
#include "lantern/support/secure_mem.h"
#include "lantern/support/strings.h"
#include "internal/yaml_parser.h"

#include <ctype.h>
#include <errno.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>


/* ============================================================================
 * Local Validator Lifecycle
 * ============================================================================ */

/**
 * Clean up a single local validator's resources.
 *
 * @param validator  Validator to clean up
 *
 * @note Thread safety: Caller must ensure exclusive access to the validator
 */
void local_validator_cleanup(struct lantern_local_validator *validator)
{
    if (!validator)
    {
        return;
    }
    if (validator->secret && validator->secret_len > 0)
    {
        lantern_secure_zero(validator->secret, validator->secret_len);
        free(validator->secret);
    }
    validator->secret = NULL;
    validator->secret_len = 0;
    validator->has_secret = false;
    if (validator->secret_key)
    {
        pq_secret_key_free(validator->secret_key);
        validator->secret_key = NULL;
    }
    validator->has_secret_handle = false;
    validator->last_proposed_slot = UINT64_MAX;
    validator->last_attested_slot = UINT64_MAX;
    validator->has_pending_attestation = false;
    validator->pending_attestation_slot = UINT64_MAX;
    memset(&validator->pending_attestation, 0, sizeof(validator->pending_attestation));
}


/**
 * Reset all local validators and free resources.
 *
 * @param client  Client instance
 *
 * @note Thread safety: Caller must ensure exclusive access during shutdown
 */
void reset_local_validators(struct lantern_client *client)
{
    if (!client)
    {
        return;
    }
    if (client->local_validators)
    {
        for (size_t i = 0; i < client->local_validator_count; ++i)
        {
            local_validator_cleanup(&client->local_validators[i]);
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
 * @param hex      Hex string (with optional 0x prefix)
 * @param out_key  Output buffer (caller must free)
 * @param out_len  Output length
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: This function is thread-safe
 */
int decode_validator_secret(const char *hex, uint8_t **out_key, size_t *out_len)
{
    if (!hex || !out_key || !out_len)
    {
        return -1;
    }

    char *dup = lantern_string_duplicate(hex);
    if (!dup)
    {
        return -1;
    }
    char *trimmed = lantern_trim_whitespace(dup);
    if (!trimmed || *trimmed == '\0')
    {
        lantern_secure_zero(dup, strlen(dup));
        free(dup);
        return -1;
    }

    const char *hex_start = trimmed;
    if (hex_start[0] == '0' && (hex_start[1] == 'x' || hex_start[1] == 'X'))
    {
        hex_start += 2;
    }
    size_t hex_len = strlen(hex_start);
    if (hex_len == 0 || (hex_len % 2) != 0)
    {
        lantern_secure_zero(dup, strlen(dup));
        free(dup);
        return -1;
    }

    size_t secret_len = hex_len / 2;
    uint8_t *secret = malloc(secret_len);
    if (!secret)
    {
        lantern_secure_zero(dup, strlen(dup));
        free(dup);
        return -1;
    }

    if (lantern_hex_decode(trimmed, secret, secret_len) != 0)
    {
        lantern_secure_zero(secret, secret_len);
        free(secret);
        lantern_secure_zero(dup, strlen(dup));
        free(dup);
        return -1;
    }

    lantern_secure_zero(dup, strlen(dup));
    free(dup);

    *out_key = secret;
    *out_len = secret_len;
    return 0;
}


/* ============================================================================
 * Hash-Sig Manifest Types
 * ============================================================================ */

/**
 * Entry in a hash-sig key manifest.
 */
struct hash_sig_manifest_entry
{
    uint64_t index;
    char *public_file;
    char *secret_file;
};


/**
 * Hash-sig key manifest containing validator key paths.
 */
struct hash_sig_manifest
{
    struct hash_sig_manifest_entry *entries;
    size_t count;
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
static void hash_sig_manifest_init(struct hash_sig_manifest *manifest)
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
static void hash_sig_manifest_reset(struct hash_sig_manifest *manifest)
{
    if (!manifest || !manifest->entries)
    {
        return;
    }
    for (size_t i = 0; i < manifest->count; ++i)
    {
        free(manifest->entries[i].public_file);
        free(manifest->entries[i].secret_file);
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
static const char *hash_sig_yaml_value(const LanternYamlObject *object, const char *key)
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
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: This function is thread-safe
 */
static int hash_sig_parse_u64(const char *text, uint64_t *out_value)
{
    if (!text || !out_value)
    {
        return -1;
    }
    char *end = NULL;
    errno = 0;
    unsigned long long parsed = strtoull(text, &end, 0);
    if (errno != 0 || end == text)
    {
        return -1;
    }
    *out_value = (uint64_t)parsed;
    return 0;
}


/**
 * Load a manifest from a directory.
 *
 * @param dir       Directory containing the manifest file
 * @param manifest  Output manifest structure
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: This function is thread-safe
 */
static int hash_sig_manifest_load(const char *dir, struct hash_sig_manifest *manifest)
{
    if (!dir || !manifest)
    {
        return -1;
    }
    hash_sig_manifest_reset(manifest);

    char *manifest_path = NULL;
    size_t dir_len = strlen(dir);
    const char *filename = "validator-keys-manifest.yaml";
    size_t filename_len = strlen(filename);
    bool need_sep = dir_len > 0 && dir[dir_len - 1] != '/' && dir[dir_len - 1] != '\\';
    size_t total = dir_len + (need_sep ? 1 : 0) + filename_len + 1;
    manifest_path = malloc(total);
    if (!manifest_path)
    {
        return -1;
    }
    memcpy(manifest_path, dir, dir_len);
    size_t offset = dir_len;
    if (need_sep)
    {
        manifest_path[offset++] = '/';
    }
    memcpy(manifest_path + offset, filename, filename_len);
    manifest_path[offset + filename_len] = '\0';

    size_t count = 0;
    LanternYamlObject *objects = lantern_yaml_read_array(manifest_path, "validators", &count);
    free(manifest_path);
    manifest_path = NULL;
    if (!objects || count == 0)
    {
        lantern_yaml_free_objects(objects, count);
        return -1;
    }

    struct hash_sig_manifest_entry *entries = calloc(count, sizeof(*entries));
    if (!entries)
    {
        lantern_yaml_free_objects(objects, count);
        return -1;
    }

    for (size_t i = 0; i < count; ++i)
    {
        const char *index_text = hash_sig_yaml_value(&objects[i], "index");
        const char *public_file = hash_sig_yaml_value(&objects[i], "public_key_file");
        const char *secret_file = hash_sig_yaml_value(&objects[i], "secret_key_file");
        if (!index_text || !public_file || !secret_file)
        {
            lantern_yaml_free_objects(objects, count);
            hash_sig_manifest_reset(&(struct hash_sig_manifest){.entries = entries, .count = count});
            return -1;
        }
        uint64_t index = 0;
        if (hash_sig_parse_u64(index_text, &index) != 0)
        {
            lantern_yaml_free_objects(objects, count);
            hash_sig_manifest_reset(&(struct hash_sig_manifest){.entries = entries, .count = count});
            return -1;
        }
        entries[i].index = index;
        entries[i].public_file = lantern_string_duplicate(public_file);
        entries[i].secret_file = lantern_string_duplicate(secret_file);
        if (!entries[i].public_file || !entries[i].secret_file)
        {
            lantern_yaml_free_objects(objects, count);
            hash_sig_manifest_reset(&(struct hash_sig_manifest){.entries = entries, .count = count});
            return -1;
        }
    }

    lantern_yaml_free_objects(objects, count);
    manifest->entries = entries;
    manifest->count = count;
    return 0;
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
static const struct hash_sig_manifest_entry *hash_sig_manifest_find(
    const struct hash_sig_manifest *manifest,
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
static const char *hash_sig_non_empty(const char *value)
{
    return (value && value[0] != '\0') ? value : NULL;
}


/**
 * Join a directory and filename into a path.
 *
 * @param dir       Directory path
 * @param leaf      Filename
 * @param out_path  Output path (caller must free)
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: This function is thread-safe
 */
static int hash_sig_join_path(const char *dir, const char *leaf, char **out_path)
{
    if (!dir || !leaf || !out_path)
    {
        return -1;
    }
    size_t dir_len = strlen(dir);
    size_t leaf_len = strlen(leaf);
    bool need_sep = dir_len > 0 && dir[dir_len - 1] != '/' && dir[dir_len - 1] != '\\';
    size_t total = dir_len + (need_sep ? 1 : 0) + leaf_len + 1;
    char *buffer = malloc(total);
    if (!buffer)
    {
        return -1;
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
    return 0;
}


/**
 * Format a template path with a validator index.
 *
 * @param template   Path template with %llu placeholder
 * @param index      Validator index
 * @param out_path   Output path (caller must free)
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: This function is thread-safe
 */
static int hash_sig_format_index_template(const char *template, uint64_t index, char **out_path)
{
    if (!template || !out_path)
    {
        return -1;
    }
    unsigned long long value = (unsigned long long)index;
    int required = snprintf(NULL, 0, template, value);
    if (required < 0)
    {
        return -1;
    }
    size_t length = (size_t)required + 1u;
    char *buffer = malloc(length);
    if (!buffer)
    {
        return -1;
    }
    if (snprintf(buffer, length, template, value) < 0)
    {
        free(buffer);
        return -1;
    }
    *out_path = buffer;
    return 0;
}


/**
 * Derive a default key directory from genesis paths.
 *
 * @param paths  Genesis paths
 * @return Derived directory path (caller must free) or NULL
 *
 * @note Thread safety: This function is thread-safe
 */
static char *hash_sig_derive_default_dir(const struct lantern_genesis_paths *paths)
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
    const char *suffix = "hash-sig-keys";
    size_t suffix_len = strlen(suffix);
    size_t total = dir_len + 1 + suffix_len + 1;
    char *buffer = malloc(total);
    if (!buffer)
    {
        return NULL;
    }
    memcpy(buffer, config_path, dir_len);
    buffer[dir_len] = '/';
    memcpy(buffer + dir_len + 1, suffix, suffix_len);
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
        struct lantern_local_validator *validator = &client->local_validators[i];
        if (validator->secret_key)
        {
            pq_secret_key_free(validator->secret_key);
            validator->secret_key = NULL;
        }
        validator->has_secret_handle = false;
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
static bool hash_sig_path_is_absolute(const char *path)
{
    if (!path || path[0] == '\0')
    {
        return false;
    }
    if (path[0] == '/' || path[0] == '\\')
    {
        return true;
    }
    if (strlen(path) >= 3 && isalpha((unsigned char)path[0]) && path[1] == ':' && (path[2] == '/' || path[2] == '\\'))
    {
        return true;
    }
    return false;
}


/**
 * Resolve the path to a validator's public key file.
 *
 * @param client    Client instance
 * @param manifest  Optional manifest
 * @param index     Validator global index
 * @param out_path  Output path (caller must free)
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: This function is thread-safe
 */
static int resolve_public_key_path(
    struct lantern_client *client,
    const struct hash_sig_manifest *manifest,
    uint64_t index,
    char **out_path)
{
    if (!client || !out_path)
    {
        return -1;
    }
    if (client->hash_sig_public_template)
    {
        return hash_sig_format_index_template(client->hash_sig_public_template, index, out_path);
    }
    if (manifest)
    {
        const struct hash_sig_manifest_entry *entry = hash_sig_manifest_find(manifest, index);
        if (entry && entry->public_file)
        {
            if (hash_sig_path_is_absolute(entry->public_file))
            {
                char *copy = lantern_string_duplicate(entry->public_file);
                if (!copy)
                {
                    return -1;
                }
                *out_path = copy;
                return 0;
            }
            if (client->hash_sig_key_dir)
            {
                return hash_sig_join_path(client->hash_sig_key_dir, entry->public_file, out_path);
            }
        }
    }
    if (client->hash_sig_key_dir)
    {
        char filename[64];
        int written = snprintf(filename, sizeof(filename), "validator_%" PRIu64 "_pk.json", index);
        if (written < 0 || (size_t)written >= sizeof(filename))
        {
            return -1;
        }
        return hash_sig_join_path(client->hash_sig_key_dir, filename, out_path);
    }
    if (client->hash_sig_public_path && client->genesis.chain_config.validator_count == 1)
    {
        char *copy = lantern_string_duplicate(client->hash_sig_public_path);
        if (!copy)
        {
            return -1;
        }
        *out_path = copy;
        return 0;
    }
    return -1;
}


/**
 * Resolve the path to a validator's secret key file.
 *
 * @param client    Client instance
 * @param manifest  Optional manifest
 * @param index     Validator global index
 * @param out_path  Output path (caller must free)
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: This function is thread-safe
 */
static int resolve_secret_key_path(
    struct lantern_client *client,
    const struct hash_sig_manifest *manifest,
    uint64_t index,
    char **out_path)
{
    if (!client || !out_path)
    {
        return -1;
    }
    if (client->hash_sig_secret_template)
    {
        return hash_sig_format_index_template(client->hash_sig_secret_template, index, out_path);
    }
    if (manifest)
    {
        const struct hash_sig_manifest_entry *entry = hash_sig_manifest_find(manifest, index);
        if (entry && entry->secret_file)
        {
            if (hash_sig_path_is_absolute(entry->secret_file))
            {
                char *copy = lantern_string_duplicate(entry->secret_file);
                if (!copy)
                {
                    return -1;
                }
                *out_path = copy;
                return 0;
            }
            if (client->hash_sig_key_dir)
            {
                return hash_sig_join_path(client->hash_sig_key_dir, entry->secret_file, out_path);
            }
        }
    }
    if (client->hash_sig_key_dir)
    {
        char filename[64];
        int written = snprintf(filename, sizeof(filename), "validator_%" PRIu64 "_sk.json", index);
        if (written < 0 || (size_t)written >= sizeof(filename))
        {
            return -1;
        }
        return hash_sig_join_path(client->hash_sig_key_dir, filename, out_path);
    }
    if (client->hash_sig_secret_path)
    {
        if (client->validator_assignment.count > 1)
        {
            return -1;
        }
        char *copy = lantern_string_duplicate(client->hash_sig_secret_path);
        if (!copy)
        {
            return -1;
        }
        *out_path = copy;
        return 0;
    }
    return -1;
}


/* ============================================================================
 * Secret Key Loading
 * ============================================================================ */

/**
 * Load hash-sig secret keys for all local validators.
 *
 * @param client    Client instance
 * @param manifest  Optional manifest
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: Caller must ensure exclusive access during key operations
 */
static int load_hash_sig_secret_keys(struct lantern_client *client, const struct hash_sig_manifest *manifest)
{
    if (!client)
    {
        return -1;
    }
    if (client->local_validator_count == 0)
    {
        return 0;
    }

    bool has_template = client->hash_sig_secret_template != NULL;
    bool has_dir = client->hash_sig_key_dir != NULL;
    bool has_single = client->hash_sig_secret_path != NULL && client->validator_assignment.count == 1;
    if (!has_template && !has_dir && !has_single)
    {
        lantern_log_debug(
            "crypto",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "hash-sig secret key sources unavailable; skipping local key load");
        return 0;
    }

    clear_local_secret_handles(client);
    struct lantern_log_metadata meta = {.validator = client->node_id};
    size_t resolved = 0;
    size_t loaded = 0;
    for (size_t i = 0; i < client->local_validator_count; ++i)
    {
        struct lantern_local_validator *validator = &client->local_validators[i];
        char *path = NULL;
        if (resolve_secret_key_path(client, manifest, validator->global_index, &path) != 0)
        {
            lantern_log_warn(
                "crypto",
                &meta,
                "unable to resolve hash-sig secret key path for validator=%" PRIu64 "; skipping",
                validator->global_index);
            continue;
        }
        ++resolved;
        lantern_log_debug(
            "crypto",
            &meta,
            "hash-sig secret key resolved validator=%" PRIu64 " path=%s",
            validator->global_index,
            path);
        struct PQSignatureSchemeSecretKey *secret = NULL;
        if (lantern_hash_sig_load_secret_file(path, &secret) != 0)
        {
            lantern_log_warn(
                "crypto",
                &meta,
                "failed to load hash-sig secret key validator=%" PRIu64 " path=%s; skipping",
                validator->global_index,
                path);
            free(path);
            continue;
        }
        free(path);
        validator->secret_key = secret;
        validator->has_secret_handle = true;
        ++loaded;
    }
    lantern_log_info(
        "crypto",
        &meta,
        "hash-sig secret keys loaded=%zu/%zu resolved=%zu dir=%s template=%s",
        loaded,
        client->local_validator_count,
        resolved,
        client->hash_sig_key_dir ? client->hash_sig_key_dir : "-",
        client->hash_sig_secret_template ? client->hash_sig_secret_template : "-");
    return 0;
}


/* ============================================================================
 * Public Key Management
 * ============================================================================ */

/**
 * Free all loaded public key handles.
 *
 * @param client  Client instance
 *
 * @note Thread safety: Caller must ensure exclusive access during shutdown
 */
void free_hash_sig_pubkeys(struct lantern_client *client)
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
 * Configure hash-sig key sources from options and environment.
 *
 * @param client   Client instance
 * @param options  Client options
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: This function should be called during initialization
 */
int configure_hash_sig_sources(struct lantern_client *client, const struct lantern_client_options *options)
{
    if (!client || !options)
    {
        return -1;
    }
    struct lantern_log_metadata meta = {.validator = client->node_id};
    const char *env_dir = hash_sig_non_empty(getenv("HASH_SIG_KEY_DIR"));
    const char *env_public_path = hash_sig_non_empty(getenv("HASH_SIG_PK_PATH"));
    const char *env_secret_path = hash_sig_non_empty(getenv("HASH_SIG_SK_PATH"));
    const char *env_public_template = hash_sig_non_empty(getenv("HASH_SIG_PK_TEMPLATE"));
    const char *env_secret_template = hash_sig_non_empty(getenv("HASH_SIG_SK_TEMPLATE"));

    const char *resolved_dir = hash_sig_non_empty(options->hash_sig_key_dir);
    if (!resolved_dir)
    {
        resolved_dir = env_dir;
    }
    if (!resolved_dir && client->assigned_validators && client->assigned_validators->hash_sig_dir)
    {
        resolved_dir = client->assigned_validators->hash_sig_dir;
    }
    if (resolved_dir)
    {
        if (set_owned_string(&client->hash_sig_key_dir, resolved_dir) != 0)
        {
            return -1;
        }
    }
    else
    {
        char *derived = hash_sig_derive_default_dir(&client->genesis_paths);
        if (derived)
        {
            int rc = set_owned_string(&client->hash_sig_key_dir, derived);
            free(derived);
            if (rc != 0)
            {
                return -1;
            }
        }
    }

    const char *resolved_public_template = hash_sig_non_empty(options->hash_sig_public_template);
    if (!resolved_public_template)
    {
        resolved_public_template = env_public_template;
    }
    if (resolved_public_template)
    {
        if (set_owned_string(&client->hash_sig_public_template, resolved_public_template) != 0)
        {
            return -1;
        }
    }

    const char *resolved_secret_template = hash_sig_non_empty(options->hash_sig_secret_template);
    if (!resolved_secret_template)
    {
        resolved_secret_template = env_secret_template;
    }
    if (resolved_secret_template)
    {
        if (set_owned_string(&client->hash_sig_secret_template, resolved_secret_template) != 0)
        {
            return -1;
        }
    }

    const char *resolved_public_path = hash_sig_non_empty(options->hash_sig_public_path);
    if (!resolved_public_path)
    {
        resolved_public_path = env_public_path;
    }
    if (resolved_public_path)
    {
        if (set_owned_string(&client->hash_sig_public_path, resolved_public_path) != 0)
        {
            return -1;
        }
    }

    const char *resolved_secret_path = hash_sig_non_empty(options->hash_sig_secret_path);
    if (!resolved_secret_path)
    {
        resolved_secret_path = env_secret_path;
    }
    if (resolved_secret_path)
    {
        if (set_owned_string(&client->hash_sig_secret_path, resolved_secret_path) != 0)
        {
            return -1;
        }
    }
    lantern_log_info(
        "crypto",
        &meta,
        "hash-sig sources resolved dir=%s pk_path=%s sk_path=%s pk_template=%s sk_template=%s",
        client->hash_sig_key_dir ? client->hash_sig_key_dir : "-",
        client->hash_sig_public_path ? client->hash_sig_public_path : "-",
        client->hash_sig_secret_path ? client->hash_sig_secret_path : "-",
        client->hash_sig_public_template ? client->hash_sig_public_template : "-",
        client->hash_sig_secret_template ? client->hash_sig_secret_template : "-");
    return 0;
}


/* ============================================================================
 * Key Loading Entry Point
 * ============================================================================ */

/**
 * Load all hash-sig keys for the client.
 *
 * @param client  Client instance
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: This function should be called during initialization
 */
int load_hash_sig_keys(struct lantern_client *client)
{
    if (!client)
    {
        return -1;
    }
    struct lantern_log_metadata meta = {.validator = client->node_id};
    if (!lantern_hash_sig_is_available())
    {
        lantern_log_error(
            "crypto",
            &meta,
            "hash-sig bindings unavailable");
        return -1;
    }

    struct hash_sig_manifest manifest;
    hash_sig_manifest_init(&manifest);
    bool manifest_loaded = false;
    if (client->hash_sig_key_dir && hash_sig_manifest_load(client->hash_sig_key_dir, &manifest) == 0)
    {
        manifest_loaded = true;
    }

    const struct hash_sig_manifest *manifest_ptr = manifest_loaded ? &manifest : NULL;
    lantern_log_info(
        "crypto",
        &meta,
        "hash-sig load start key_dir=%s manifest=%s validators=%" PRIu64 " local=%zu",
        client->hash_sig_key_dir ? client->hash_sig_key_dir : "-",
        manifest_loaded ? "loaded" : "missing",
        client->genesis.chain_config.validator_count,
        client->local_validator_count);
    /* Note: load_hash_sig_public_keys removed - per LeanSpec, verification uses
     * 52-byte serialized pubkeys from state, not full JSON key handles */
    if (client->local_validator_count > 0)
    {
        if (load_hash_sig_secret_keys(client, manifest_ptr) != 0)
        {
            hash_sig_manifest_reset(&manifest);
            return -1;
        }
    }
    hash_sig_manifest_reset(&manifest);
    return 0;
}
