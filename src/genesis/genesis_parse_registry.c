/**
 * @file genesis_parse_registry.c
 * @brief Parsing helpers for Lantern validator registry genesis artifacts.
 *
 * Implements internal helpers for parsing validators registry YAML files.
 *
 * @spec Lantern devnet genesis artifact files (lean quickstart).
 */

#include "genesis_internal.h"

#include <limits.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "lantern/support/strings.h"

static const size_t GENESIS_SMALL_LINE_BUFFER_LEN = 1024;

static const char *const VALIDATOR_REGISTRY_FIELD_INDEX = "index";

/**
 * Collect all validator indices from an annotated_validators.yaml mapping.
 *
 * Duplicate indices are collapsed because annotated manifests carry both
 * attester and proposer entries for each validator index.
 *
 * @param path             Filesystem path to annotated_validators.yaml.
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
static int collect_registry_record_count(
    const char *path,
    size_t *out_record_count)
{
    if (!path || !out_record_count)
    {
        return LANTERN_GENESIS_ERR_INVALID_PARAM;
    }

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

        if (*trimmed != '-')
        {
            continue;
        }

        const char *value = lantern_trim_whitespace(trimmed + 1);
        size_t prefix_len = strlen(VALIDATOR_REGISTRY_FIELD_INDEX);
        if (!value || strncmp(value, VALIDATOR_REGISTRY_FIELD_INDEX, prefix_len) != 0
            || value[prefix_len] != ':')
        {
            result = LANTERN_GENESIS_ERR_INVALID_DATA;
            break;
        }

        int ok = 0;
        uint64_t parsed = genesis_parse_u64(
            lantern_trim_whitespace((char *)(value + prefix_len + 1u)),
            &ok);
        if (!ok || parsed > SIZE_MAX || parsed >= (uint64_t)LANTERN_VALIDATOR_REGISTRY_LIMIT)
        {
            result = LANTERN_GENESIS_ERR_INVALID_DATA;
            break;
        }

        size_t index = (size_t)parsed;
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

    *out_record_count = max_index + 1u;
    free(seen);
    return LANTERN_GENESIS_OK;
}


/**
 * Parse a validator registry file.
 *
 * Supports the annotated_validators.yaml node mapping emitted by lean-quickstart.
 * On success, `registry` owns the returned record array and must be released with
 * `genesis_free_validator_registry()`.
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
    size_t record_count = 0;
    int result = collect_registry_record_count(path, &record_count);
    if (result != LANTERN_GENESIS_OK)
    {
        return result;
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
