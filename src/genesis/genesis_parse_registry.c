/**
 * @file genesis_parse_registry.c
 * @brief Parsing helpers for Lantern validator registry genesis artifacts.
 *
 * Implements internal helpers for parsing validators registry YAML files.
 *
 * @spec Lantern devnet genesis artifact files (lean quickstart).
 */

#include "genesis_internal.h"

#include <ctype.h>
#include <errno.h>
#include <limits.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "internal/yaml_parser.h"
#include "lantern/consensus/containers.h"
#include "lantern/support/strings.h"

static const size_t GENESIS_SMALL_LINE_BUFFER_LEN = 1024;

static const char *const VALIDATOR_REGISTRY_ARRAY_KEY = "validators";
static const char *const VALIDATOR_REGISTRY_FIELD_INDEX = "index";
static const char *const VALIDATOR_REGISTRY_FIELD_PUBKEY = "pubkey";
static const char *const VALIDATOR_REGISTRY_FIELD_WITHDRAWAL_CREDENTIALS = "withdrawal_credentials";

static uint64_t parse_u64(const char *value, int *ok);
static char *dup_trimmed(const char *value);
static const char *yaml_object_value(const LanternYamlObject *object, const char *key);
static int decode_validator_pubkey_hex(const char *hex, uint8_t out[LANTERN_VALIDATOR_PUBKEY_SIZE]);
static int set_record_pubkey(struct lantern_validator_record *record);
static int parse_registry_mapping_item_index(
    const char *trimmed,
    bool *out_has_index,
    size_t *out_index);

static int collect_registry_mapping_indices(
    const char *path,
    bool **out_seen_indices,
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
 * Populate a registry record's pubkey bytes from its pubkey hex string.
 *
 * @param record Record to update.
 *
 * @return LANTERN_GENESIS_OK on success.
 * @return LANTERN_GENESIS_ERR_INVALID_PARAM on invalid parameters.
 * @return LANTERN_GENESIS_ERR_PARSE on decode failures.
 *
 * @note Thread safety: Not thread-safe. Caller must ensure exclusive access to record.
 */
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


/**
 * Parse a registry mapping list item into a validator index.
 *
 * Supports both legacy scalar-list items (`- 3`) and annotated items
 * (`- index: 3`).
 *
 * @param trimmed        Trimmed input line.
 * @param out_has_index  Output flag set when a validator index was found.
 * @param out_index      Output validator index.
 *
 * @return LANTERN_GENESIS_OK on success.
 * @return LANTERN_GENESIS_ERR_INVALID_PARAM on invalid parameters.
 * @return LANTERN_GENESIS_ERR_INVALID_DATA on malformed indices.
 */
static int parse_registry_mapping_item_index(
    const char *trimmed,
    bool *out_has_index,
    size_t *out_index)
{
    if (!trimmed || !out_has_index || !out_index)
    {
        return LANTERN_GENESIS_ERR_INVALID_PARAM;
    }

    *out_has_index = false;
    *out_index = 0;

    if (*trimmed != '-')
    {
        return LANTERN_GENESIS_OK;
    }

    const char *value = lantern_trim_whitespace((char *)(trimmed + 1));
    if (!value || *value == '\0')
    {
        return LANTERN_GENESIS_OK;
    }

    size_t prefix_len = strlen(VALIDATOR_REGISTRY_FIELD_INDEX);
    if (strncmp(value, VALIDATOR_REGISTRY_FIELD_INDEX, prefix_len) == 0 && value[prefix_len] == ':')
    {
        value = lantern_trim_whitespace((char *)(value + prefix_len + 1u));
    }

    int ok = 0;
    uint64_t parsed = parse_u64(value, &ok);
    if (!ok || parsed > SIZE_MAX || parsed >= (uint64_t)LANTERN_VALIDATOR_REGISTRY_LIMIT)
    {
        return LANTERN_GENESIS_ERR_INVALID_DATA;
    }

    *out_has_index = true;
    *out_index = (size_t)parsed;
    return LANTERN_GENESIS_OK;
}


/**
 * Collect all validator indices from an annotated_validators.yaml mapping.
 *
 * Duplicate indices are collapsed because annotated manifests carry both
 * attester and proposer entries for each validator index.
 *
 * @param path             Filesystem path to annotated_validators.yaml.
 * @param out_seen_indices Output pointer for the allocated coverage bitmap.
 * @param out_record_count Output pointer for the validator count.
 *
 * @return LANTERN_GENESIS_OK on success.
 * @return LANTERN_GENESIS_ERR_INVALID_PARAM on invalid parameters.
 * @return LANTERN_GENESIS_ERR_IO if the file cannot be opened.
 * @return LANTERN_GENESIS_ERR_OUT_OF_MEMORY on allocation failure.
 * @return LANTERN_GENESIS_ERR_OVERFLOW on size/capacity overflow.
 * @return LANTERN_GENESIS_ERR_INVALID_DATA on parse/validation failures.
 *
 * @note Thread safety: Thread-safe if callers provide exclusive access to outputs.
 */
static int collect_registry_mapping_indices(
    const char *path,
    bool **out_seen_indices,
    size_t *out_record_count)
{
    if (!path || !out_seen_indices || !out_record_count)
    {
        return LANTERN_GENESIS_ERR_INVALID_PARAM;
    }

    *out_seen_indices = NULL;
    *out_record_count = 0;

    FILE *fp = fopen(path, "r");
    if (!fp)
    {
        return LANTERN_GENESIS_ERR_IO;
    }

    bool *seen = calloc((size_t)LANTERN_VALIDATOR_REGISTRY_LIMIT, sizeof(*seen));
    size_t unique_count = 0;
    size_t max_index = 0;
    int result = LANTERN_GENESIS_OK;
    if (!seen)
    {
        fclose(fp);
        return LANTERN_GENESIS_ERR_OUT_OF_MEMORY;
    }

    char line[GENESIS_SMALL_LINE_BUFFER_LEN];
    while (fgets(line, sizeof(line), fp))
    {
        char *trimmed = lantern_trim_whitespace(line);
        if (!trimmed || *trimmed == '\0')
        {
            continue;
        }

        bool has_index = false;
        size_t index = 0;
        result = parse_registry_mapping_item_index(trimmed, &has_index, &index);
        if (result != LANTERN_GENESIS_OK)
        {
            break;
        }
        if (!has_index)
        {
            continue;
        }

        if (!seen[index])
        {
            seen[index] = true;
            ++unique_count;
            if (index > max_index)
            {
                max_index = index;
            }
        }
    }

    fclose(fp);

    if (result != LANTERN_GENESIS_OK)
    {
        free(seen);
        return result;
    }

    if (unique_count == 0)
    {
        free(seen);
        return LANTERN_GENESIS_ERR_INVALID_DATA;
    }

    for (size_t i = 0; i <= max_index; ++i)
    {
        if (!seen[i])
        {
            free(seen);
            return LANTERN_GENESIS_ERR_INVALID_DATA;
        }
    }

    *out_seen_indices = seen;
    *out_record_count = max_index + 1u;
    return LANTERN_GENESIS_OK;
}


/**
 * Allocate and populate an index-only validator registry.
 *
 * @param record_count Number of records to allocate.
 * @param registry     Registry to populate (modified in place).
 *
 * @return LANTERN_GENESIS_OK on success.
 * @return LANTERN_GENESIS_ERR_INVALID_PARAM on invalid parameters.
 * @return LANTERN_GENESIS_ERR_OUT_OF_MEMORY on allocation failure.
 *
 * @note Thread safety: Not thread-safe. Caller must ensure exclusive access to registry.
 */
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


/**
 * Populate an index-only registry from an annotated_validators.yaml mapping.
 *
 * @param path     Filesystem path to annotated_validators.yaml.
 * @param registry Registry to populate (modified in place).
 *
 * @return LANTERN_GENESIS_OK on success.
 * @return LANTERN_GENESIS_ERR_INVALID_PARAM on invalid parameters.
 * @return LANTERN_GENESIS_ERR_IO if the file cannot be opened.
 * @return LANTERN_GENESIS_ERR_OUT_OF_MEMORY on allocation failure.
 * @return LANTERN_GENESIS_ERR_OVERFLOW on size/count overflow.
 * @return LANTERN_GENESIS_ERR_INVALID_DATA on validation failures.
 *
 * @note Thread safety: Not thread-safe. Caller must ensure exclusive access to registry.
 */
static int parse_validator_registry_mapping(
    const char *path,
    struct lantern_validator_registry *registry)
{
    if (!path || !registry)
    {
        return LANTERN_GENESIS_ERR_INVALID_PARAM;
    }

    bool *seen_indices = NULL;
    size_t record_count = 0;
    int result = collect_registry_mapping_indices(path, &seen_indices, &record_count);
    if (result != LANTERN_GENESIS_OK)
    {
        return result;
    }

    free(seen_indices);

    return build_index_only_registry(record_count, registry);
}


/**
 * Scan registry objects to determine format and record count.
 *
 * Determines whether the registry is annotated with pubkeys and/or explicit indices.
 *
 * @param objects                  YAML objects to scan.
 * @param object_count             Number of objects in `objects`.
 * @param out_has_pubkey_field     Output flag set if any object has a pubkey field.
 * @param out_have_explicit_indices Output flag set if any object has an explicit index.
 * @param out_record_count         Output pointer for the expected record count.
 *
 * @return LANTERN_GENESIS_OK on success.
 * @return LANTERN_GENESIS_ERR_INVALID_PARAM on invalid parameters.
 * @return LANTERN_GENESIS_ERR_OVERFLOW on size/count overflow.
 * @return LANTERN_GENESIS_ERR_INVALID_DATA on validation failures.
 *
 * @note Thread safety: Thread-safe if callers provide exclusive access to outputs.
 */
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
    if (have_explicit_indices && max_index >= (size_t)LANTERN_VALIDATOR_REGISTRY_LIMIT)
    {
        return LANTERN_GENESIS_ERR_INVALID_DATA;
    }
    if (!have_explicit_indices && object_count > (size_t)LANTERN_VALIDATOR_REGISTRY_LIMIT)
    {
        return LANTERN_GENESIS_ERR_INVALID_DATA;
    }

    *out_has_pubkey_field = has_pubkey_field;
    *out_have_explicit_indices = have_explicit_indices;
    *out_record_count = have_explicit_indices ? (max_index + 1) : object_count;
    return LANTERN_GENESIS_OK;
}


/**
 * Populate registry records from YAML objects.
 *
 * @param objects               YAML objects to parse.
 * @param object_count          Number of objects in `objects`.
 * @param has_pubkey_field      Whether the registry contains pubkey annotations.
 * @param have_explicit_indices Whether objects contain explicit indices.
 * @param records               Record array to populate.
 * @param record_count          Number of records in `records`.
 * @param assigned              Assignment bitmap for explicit-index registries.
 *
 * @return LANTERN_GENESIS_OK on success.
 * @return LANTERN_GENESIS_ERR_INVALID_PARAM on invalid parameters.
 * @return LANTERN_GENESIS_ERR_OUT_OF_MEMORY on allocation failure.
 * @return LANTERN_GENESIS_ERR_INVALID_DATA on validation failures.
 *
 * @note Thread safety: Not thread-safe. Caller must ensure exclusive access to records.
 */
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


/**
 * Validate full coverage for explicit-index registries.
 *
 * @param assigned    Assignment bitmap.
 * @param record_count Expected record count.
 *
 * @return LANTERN_GENESIS_OK on success.
 * @return LANTERN_GENESIS_ERR_INVALID_PARAM on invalid parameters.
 * @return LANTERN_GENESIS_ERR_INVALID_DATA if any record is unassigned.
 *
 * @note Thread safety: Thread-safe.
 */
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


/**
 * Parse a validator registry from YAML objects (annotated or index-only).
 *
 * @param objects      YAML objects to parse.
 * @param object_count Number of objects in `objects`.
 * @param registry     Registry to populate.
 *
 * @return LANTERN_GENESIS_OK on success.
 * @return LANTERN_GENESIS_ERR_INVALID_PARAM on invalid parameters.
 * @return LANTERN_GENESIS_ERR_OUT_OF_MEMORY on allocation failure.
 * @return LANTERN_GENESIS_ERR_OVERFLOW on size/count overflow.
 * @return LANTERN_GENESIS_ERR_INVALID_DATA on validation failures.
 *
 * @note Thread safety: Not thread-safe. Caller must ensure exclusive access to registry.
 */
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


/**
 * Parse a validator registry file.
 *
 * Supports an annotated YAML array under the `validators` key, or a fallback
 * annotated_validators.yaml-style node mapping. On success, `registry` owns the
 * returned record array and must be released with `genesis_free_validator_registry()`.
 *
 * @spec Lantern devnet genesis artifact files (lean quickstart).
 *
 * @param path     Path to annotated_validators.yaml.
 * @param registry Registry to populate.
 *
 * @return LANTERN_GENESIS_OK on success.
 * @return LANTERN_GENESIS_ERR_INVALID_PARAM on invalid parameters.
 * @return LANTERN_GENESIS_ERR_IO on file I/O errors.
 * @return LANTERN_GENESIS_ERR_OUT_OF_MEMORY on allocation failure.
 * @return LANTERN_GENESIS_ERR_OVERFLOW on size/count overflow.
 * @return LANTERN_GENESIS_ERR_INVALID_DATA on validation failures.
 * @return LANTERN_GENESIS_ERR_PARSE on parse failures.
 *
 * @note Thread safety: Not thread-safe. Caller must ensure exclusive access to registry.
 */
int genesis_parse_validator_registry(const char *path, struct lantern_validator_registry *registry)
{
    if (!path || !registry)
    {
        return LANTERN_GENESIS_ERR_INVALID_PARAM;
    }

    genesis_free_validator_registry(registry);

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
