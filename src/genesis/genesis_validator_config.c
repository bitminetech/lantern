/**
 * @file genesis_validator_config.c
 * @brief Validator configuration helpers for genesis bootstrapping.
 *
 * Implements:
 * - Lookup helpers for validator-config entries
 * - Default contiguous range assignment
 * - Explicit validator index assignment parsing from validators.yaml mappings
 *
 * @spec Lantern validator-config.yaml and validators.yaml mapping formats.
 */

#include "lantern/genesis/genesis.h"

#include <ctype.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "genesis_internal.h"
#include "lantern/support/strings.h"

static const size_t GENESIS_LINE_BUFFER_LEN = 2048;

static int compare_u64(const void *lhs, const void *rhs);
static bool entry_has_assignment_index(
    const struct lantern_validator_config_entry *entry,
    uint64_t index);
static int append_assignment_index(struct lantern_validator_config_entry *entry, uint64_t index);
static int parse_assignment_item_index(
    const char *trimmed,
    bool *out_has_index,
    uint64_t *out_index);
static int parse_assignment_mapping_key(
    struct lantern_validator_config *config,
    char *line,
    bool *out_is_mapping_key,
    struct lantern_validator_config_entry **out_entry);

static int parse_assignment_file(
    struct lantern_validator_config *config,
    FILE *fp,
    bool *assigned,
    uint64_t validator_count,
    bool *out_has_matching_entry,
    size_t *out_assigned_total);

static int finalize_assignment_entries(
    struct lantern_validator_config *config);


/**
 * Compare two `uint64_t` values for ascending sort order.
 *
 * @param lhs Pointer to a `uint64_t`.
 * @param rhs Pointer to a `uint64_t`.
 *
 * @return -1 if lhs < rhs.
 * @return  1 if lhs > rhs.
 * @return  0 if equal.
 *
 * @note Thread safety: Thread-safe.
 */
static int compare_u64(const void *lhs, const void *rhs)
{
    const uint64_t *left_value = lhs;
    const uint64_t *right_value = rhs;
    if (*left_value < *right_value)
    {
        return -1;
    }
    if (*left_value > *right_value)
    {
        return 1;
    }
    return 0;
}

static bool entry_has_assignment_index(
    const struct lantern_validator_config_entry *entry,
    uint64_t index)
{
    if (!entry)
    {
        return false;
    }

    for (size_t index_pos = 0; index_pos < entry->indices_len; ++index_pos)
    {
        if (entry->indices[index_pos] == index)
        {
            return true;
        }
    }

    return false;
}


/**
 * Append a validator index to an entry's explicit index list.
 *
 * Appends an index after the caller has checked it for duplication.
 *
 * @param entry Entry to update.
 * @param index Validator index to append.
 *
 * @return LANTERN_GENESIS_OK on success.
 * @return LANTERN_GENESIS_ERR_INVALID_PARAM if entry is NULL.
 * @return LANTERN_GENESIS_ERR_INVALID_DATA if index is already present.
 * @return LANTERN_GENESIS_ERR_OUT_OF_MEMORY on allocation failure.
 * @return LANTERN_GENESIS_ERR_OVERFLOW on capacity overflow.
 *
 * @note Thread safety: Not thread-safe. Caller must ensure exclusive access to entry.
 */
static int append_assignment_index(struct lantern_validator_config_entry *entry, uint64_t index)
{
    if (!entry)
    {
        return LANTERN_GENESIS_ERR_INVALID_PARAM;
    }

    if (entry->indices_len >= entry->count)
    {
        return LANTERN_GENESIS_ERR_INVALID_DATA;
    }
    if (!entry->indices)
    {
        if (entry->count > SIZE_MAX / sizeof(*entry->indices))
        {
            return LANTERN_GENESIS_ERR_OVERFLOW;
        }
        entry->indices = malloc((size_t)entry->count * sizeof(*entry->indices));
        if (!entry->indices)
        {
            return LANTERN_GENESIS_ERR_OUT_OF_MEMORY;
        }
    }

    entry->indices[entry->indices_len] = index;
    entry->indices_len++;
    return LANTERN_GENESIS_OK;
}

static int parse_assignment_item_index(
    const char *trimmed,
    bool *out_has_index,
    uint64_t *out_index)
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

    if (strncmp(value, "index", 5) == 0 && value[5] == ':')
    {
        value = lantern_trim_whitespace((char *)(value + 6));
    }

    int is_valid_index = 0;
    uint64_t parsed = genesis_parse_u64(value, &is_valid_index);
    if (!is_valid_index)
    {
        return LANTERN_GENESIS_ERR_INVALID_DATA;
    }

    *out_has_index = true;
    *out_index = parsed;
    return LANTERN_GENESIS_OK;
}


/**
 * Parse a validators.yaml mapping key line.
 *
 * Accepts `<name>:` lines with optional trailing whitespace and/or a `#` comment,
 * and rejects inline values (e.g. `name: 1`). When a mapping is detected, `line`
 * is modified in place by replacing the colon with `\0`.
 *
 * @param config          Validator config to search.
 * @param line            Line buffer to parse (modified in place).
 * @param out_is_mapping_key Set to true if the line is a mapping key, false otherwise.
 * @param out_entry       Set to the matching entry, or NULL if not found.
 *
 * @return LANTERN_GENESIS_OK on success (including non-mapping lines).
 * @return LANTERN_GENESIS_ERR_INVALID_PARAM on invalid parameters.
 * @return LANTERN_GENESIS_ERR_INVALID_DATA if the mapping key is empty.
 *
 * @note Thread safety: Not thread-safe. Caller must ensure exclusive access to config.
 */
static int parse_assignment_mapping_key(
    struct lantern_validator_config *config,
    char *line,
    bool *out_is_mapping_key,
    struct lantern_validator_config_entry **out_entry)
{
    if (!config || !line || !out_is_mapping_key || !out_entry)
    {
        return LANTERN_GENESIS_ERR_INVALID_PARAM;
    }

    *out_is_mapping_key = false;
    *out_entry = NULL;

    char *colon = strchr(line, ':');
    if (!colon)
    {
        return LANTERN_GENESIS_OK;
    }

    char *value = colon + 1;
    while (*value != '\0' && isspace((unsigned char)*value))
    {
        ++value;
    }
    if (*value != '\0' && *value != '#')
    {
        return LANTERN_GENESIS_OK;
    }

    *colon = '\0';
    char *name = lantern_trim_whitespace(line);
    if (!name || *name == '\0')
    {
        return LANTERN_GENESIS_ERR_INVALID_DATA;
    }

    size_t name_len = strlen(name);
    if (name_len >= 2
        && ((name[0] == '"' && name[name_len - 1] == '"')
            || (name[0] == '\'' && name[name_len - 1] == '\'')))
    {
        name[name_len - 1] = '\0';
        ++name;
    }

    if (*name == '\0')
    {
        return LANTERN_GENESIS_ERR_INVALID_DATA;
    }

    *out_entry = lantern_validator_config_find(config, name);
    *out_is_mapping_key = true;
    return LANTERN_GENESIS_OK;
}


/**
 * Parse a validators.yaml mapping file into explicit indices on config entries.
 *
 * Updates `entry->indices` for each mapping key that matches a config entry. List
 * items under unknown mapping keys are ignored. If `assigned` is provided, it is
 * used as a global uniqueness tracker across all entries.
 *
 * @param config             Validator config to update in place.
 * @param fp                 Open file handle to read from.
 * @param assigned           Optional bitset of length validator_count, or NULL.
 * @param validator_count    Maximum allowed validator index is validator_count - 1.
 * @param out_has_matching_entry Set true if at least one mapping key matched an entry.
 * @param out_assigned_total Total number of unique indices assigned across entries.
 *
 * @return LANTERN_GENESIS_OK on success.
 * @return LANTERN_GENESIS_ERR_INVALID_PARAM on invalid parameters.
 * @return LANTERN_GENESIS_ERR_INVALID_DATA on malformed, duplicate, or out-of-range data.
 * @return LANTERN_GENESIS_ERR_OUT_OF_MEMORY on allocation failure.
 * @return LANTERN_GENESIS_ERR_OVERFLOW on overflow.
 *
 * @note Thread safety: Not thread-safe. Caller must ensure exclusive access to config.
 */
static int parse_assignment_file(
    struct lantern_validator_config *config,
    FILE *fp,
    bool *assigned,
    uint64_t validator_count,
    bool *out_has_matching_entry,
    size_t *out_assigned_total)
{
    if (!fp || !config || !out_has_matching_entry || !out_assigned_total)
    {
        return LANTERN_GENESIS_ERR_INVALID_PARAM;
    }

    *out_has_matching_entry = false;
    *out_assigned_total = 0;

    struct lantern_validator_config_entry *current = NULL;

    char line[GENESIS_LINE_BUFFER_LEN];
    while (fgets(line, sizeof(line), fp))
    {
        bool is_indented = isspace((unsigned char)line[0]) != 0;
        char *trimmed = lantern_trim_whitespace(line);
        if (!trimmed || *trimmed == '\0' || *trimmed == '#')
        {
            continue;
        }

        bool has_index = false;
        uint64_t parsed = 0;
        int item_rc = parse_assignment_item_index(trimmed, &has_index, &parsed);
        if (item_rc != LANTERN_GENESIS_OK)
        {
            return item_rc;
        }
        if (has_index)
        {
            if (!current || !assigned || parsed >= validator_count)
            {
                continue;
            }

            if (entry_has_assignment_index(current, parsed))
            {
                continue;
            }
            if (assigned[(size_t)parsed])
            {
                return LANTERN_GENESIS_ERR_INVALID_DATA;
            }

            int result = append_assignment_index(current, parsed);
            if (result != LANTERN_GENESIS_OK)
            {
                return result;
            }

            assigned[(size_t)parsed] = true;
            (*out_assigned_total)++;
            continue;
        }

        struct lantern_validator_config_entry *entry = NULL;
        bool is_mapping_key = false;
        int mapping_rc = parse_assignment_mapping_key(config, trimmed, &is_mapping_key, &entry);
        if (mapping_rc != LANTERN_GENESIS_OK)
        {
            return mapping_rc;
        }
        if (!is_mapping_key)
        {
            if (is_indented && current)
            {
                continue;
            }
            current = NULL;
            continue;
        }

        current = entry;
        if (entry)
        {
            *out_has_matching_entry = true;
            entry->indices_len = 0;
        }
    }

    return LANTERN_GENESIS_OK;
}


/**
 * Validate and finalize config entries after explicit assignments are parsed.
 *
 * Ensures each entry has exactly `entry->count` explicit indices, then sorts
 * each list for binary-search lookup.
 *
 * @param config          Validator config to validate and update in place.
 * @param validator_count Total number of validators (must be non-zero).
 *
 * @return LANTERN_GENESIS_OK on success.
 * @return LANTERN_GENESIS_ERR_INVALID_PARAM on invalid parameters.
 * @return LANTERN_GENESIS_ERR_INVALID_DATA if any entry is missing indices or has a mismatch.
 * @return LANTERN_GENESIS_ERR_OVERFLOW if computing the end index would overflow.
 *
 * @note Thread safety: Not thread-safe. Caller must ensure exclusive access to config.
 */
static int finalize_assignment_entries(struct lantern_validator_config *config)
{
    if (!config || !config->entries || config->count == 0)
    {
        return LANTERN_GENESIS_ERR_INVALID_PARAM;
    }

    for (size_t entry_index = 0; entry_index < config->count; ++entry_index)
    {
        struct lantern_validator_config_entry *entry = &config->entries[entry_index];
        if (entry->indices_len != entry->count || entry->indices_len == 0)
        {
            return LANTERN_GENESIS_ERR_INVALID_DATA;
        }

        qsort(entry->indices, entry->indices_len, sizeof(*entry->indices), compare_u64);
    }

    return LANTERN_GENESIS_OK;
}


/**
 * Find a validator config entry by name.
 *
 * @spec Lantern validator-config.yaml and validators.yaml mapping formats.
 *
 * @param config Validator config to search.
 * @param name   Entry name to match (exact string compare).
 *
 * @return Matching entry pointer, or NULL if not found.
 *
 * @note Thread safety: Not thread-safe. Caller must ensure exclusive access to config.
 */
struct lantern_validator_config_entry *lantern_validator_config_find(
    struct lantern_validator_config *config,
    const char *name)
{
    if (!config || !name || !config->entries)
    {
        return NULL;
    }

    for (size_t entry_index = 0; entry_index < config->count; ++entry_index)
    {
        if (config->entries[entry_index].name
            && strcmp(config->entries[entry_index].name, name) == 0)
        {
            return &config->entries[entry_index];
        }
    }

    return NULL;
}


/**
 * Assign contiguous validator index ranges for each config entry.
 *
 * Entries receive sequential index lists starting at zero, in config order.
 *
 * @spec Lantern validator-config.yaml and validators.yaml mapping formats.
 *
 * @param config          Validator config to update in place.
 * @param validator_count Total number of validators expected across all entries.
 *
 * @return LANTERN_GENESIS_OK on success.
 * @return LANTERN_GENESIS_ERR_INVALID_PARAM on invalid parameters.
 * @return LANTERN_GENESIS_ERR_INVALID_DATA if counts do not sum to validator_count.
 *
 * @note Thread safety: Not thread-safe. Caller must ensure exclusive access to config.
 */
int lantern_validator_config_assign_ranges(
    struct lantern_validator_config *config,
    uint64_t validator_count)
{
    if (!config || !config->entries || config->count == 0 || validator_count == 0)
    {
        return LANTERN_GENESIS_ERR_INVALID_PARAM;
    }

    uint64_t next_index = 0;
    for (size_t entry_index = 0; entry_index < config->count; ++entry_index)
    {
        struct lantern_validator_config_entry *entry = &config->entries[entry_index];
        if (entry->count == 0)
        {
            return LANTERN_GENESIS_ERR_INVALID_DATA;
        }

        if (entry->count > (validator_count - next_index))
        {
            return LANTERN_GENESIS_ERR_INVALID_DATA;
        }

        if (entry->count > SIZE_MAX / sizeof(*entry->indices))
        {
            return LANTERN_GENESIS_ERR_OVERFLOW;
        }
        uint64_t *indices = realloc(
            entry->indices,
            (size_t)entry->count * sizeof(*entry->indices));
        if (!indices)
        {
            return LANTERN_GENESIS_ERR_OUT_OF_MEMORY;
        }
        entry->indices = indices;
        entry->indices_len = (size_t)entry->count;
        for (size_t i = 0; i < entry->indices_len; ++i)
        {
            entry->indices[i] = next_index + i;
        }
        next_index += entry->count;
    }

    if (next_index != validator_count)
    {
        return LANTERN_GENESIS_ERR_INVALID_DATA;
    }

    return LANTERN_GENESIS_OK;
}


/**
 * Apply explicit validator index assignments from a validators.yaml mapping file.
 *
 * The file is expected to contain YAML mappings of the form:
 *
 *   <entry-name>:
 *     - <validator-index>
 *     - ...
 *
 * Each config entry must list exactly `entry->count` unique indices, and the union
 * of all indices must cover `[0, validator_count)` with no duplicates.
 *
 * @spec Lantern validator-config.yaml and validators.yaml mapping formats.
 *
 * @param config          Validator config to update in place.
 * @param path            Filesystem path to validators.yaml.
 * @param validator_count Total number of validators expected.
 *
 * @return LANTERN_GENESIS_OK on success.
 * @return LANTERN_GENESIS_ERR_INVALID_PARAM on invalid parameters.
 * @return LANTERN_GENESIS_ERR_IO if the file cannot be opened.
 * @return LANTERN_GENESIS_ERR_OUT_OF_MEMORY on allocation failure.
 * @return LANTERN_GENESIS_ERR_INVALID_DATA on malformed or inconsistent assignments.
 * @return LANTERN_GENESIS_ERR_OVERFLOW on size/count overflow.
 *
 * @note Thread safety: Not thread-safe. Caller must ensure exclusive access to config.
 */
int lantern_validator_config_apply_assignments(
    struct lantern_validator_config *config,
    const char *path,
    uint64_t validator_count)
{
    if (!config || !config->entries || config->count == 0 || !path || validator_count == 0)
    {
        return LANTERN_GENESIS_ERR_INVALID_PARAM;
    }

    if (validator_count > SIZE_MAX)
    {
        return LANTERN_GENESIS_ERR_OVERFLOW;
    }

    int result = LANTERN_GENESIS_OK;
    FILE *fp = fopen(path, "r");
    if (!fp)
    {
        return LANTERN_GENESIS_ERR_IO;
    }

    size_t assigned_len = (size_t)validator_count;
    bool *assigned = NULL;
    if (assigned_len > 0)
    {
        assigned = calloc(assigned_len, sizeof(*assigned));
        if (!assigned)
        {
            result = LANTERN_GENESIS_ERR_OUT_OF_MEMORY;
            goto cleanup;
        }
    }

    bool has_matching_entry = false;
    size_t assigned_total = 0;
    result = parse_assignment_file(
        config,
        fp,
        assigned,
        validator_count,
        &has_matching_entry,
        &assigned_total);
    if (result != LANTERN_GENESIS_OK)
    {
        goto cleanup;
    }

    if (!has_matching_entry)
    {
        goto cleanup;
    }

    if (assigned_total != assigned_len)
    {
        result = LANTERN_GENESIS_ERR_INVALID_DATA;
        goto cleanup;
    }

    result = finalize_assignment_entries(config);

cleanup:
    fclose(fp);
    free(assigned);
    return result;
}
