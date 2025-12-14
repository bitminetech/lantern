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
#include <errno.h>
#include <limits.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "genesis_internal.h"
#include "lantern/support/strings.h"

static const size_t GENESIS_LINE_BUFFER_LEN = 2048;
static const size_t GENESIS_INITIAL_INDEX_CAPACITY = 4;

static uint64_t parse_u64(const char *value, int *ok);
static int compare_u64(const void *lhs, const void *rhs);
static int append_assignment_index(struct lantern_validator_config_entry *entry, uint64_t index);
static int parse_assignment_mapping_key(
    char *line,
    struct lantern_validator_config *config,
    struct lantern_validator_config_entry **out_entry);

static int parse_assignment_file(
    FILE *fp,
    struct lantern_validator_config *config,
    bool *assigned,
    uint64_t validator_count,
    bool *out_saw_mapping,
    size_t *out_assigned_total);

static int finalize_assignment_entries(
    struct lantern_validator_config *config,
    uint64_t validator_count);


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


/** @brief Compare two uint64_t values for qsort. */
static int compare_u64(const void *lhs, const void *rhs)
{
    const uint64_t *a = lhs;
    const uint64_t *b = rhs;
    if (*a < *b)
    {
        return -1;
    }
    if (*a > *b)
    {
        return 1;
    }
    return 0;
}


/** @brief Append a validator index to an entry's explicit assignment list. */
static int append_assignment_index(struct lantern_validator_config_entry *entry, uint64_t index)
{
    if (!entry)
    {
        return LANTERN_GENESIS_ERR_INVALID_PARAM;
    }

    for (size_t i = 0; i < entry->indices_len; ++i)
    {
        if (entry->indices[i] == index)
        {
            return LANTERN_GENESIS_ERR_INVALID_DATA;
        }
    }

    if (entry->indices_len == entry->indices_cap)
    {
        if (entry->indices_cap > SIZE_MAX / 2)
        {
            return LANTERN_GENESIS_ERR_OVERFLOW;
        }

        size_t new_cap = GENESIS_INITIAL_INDEX_CAPACITY;
        if (entry->indices_cap != 0)
        {
            new_cap = entry->indices_cap * 2;
        }
        if (new_cap < (entry->indices_len + 1))
        {
            new_cap = entry->indices_len + 1;
        }
        if (new_cap > SIZE_MAX / sizeof(*entry->indices))
        {
            return LANTERN_GENESIS_ERR_OVERFLOW;
        }

        void *grown = realloc(entry->indices, new_cap * sizeof(*entry->indices));
        if (!grown)
        {
            return LANTERN_GENESIS_ERR_OUT_OF_MEMORY;
        }

        entry->indices = grown;
        entry->indices_cap = new_cap;
    }

    entry->indices[entry->indices_len] = index;
    entry->indices_len++;
    return LANTERN_GENESIS_OK;
}


/** @brief Parse a YAML mapping key of the form "<name>:" with no inline value. */
static int parse_assignment_mapping_key(
    char *line,
    struct lantern_validator_config *config,
    struct lantern_validator_config_entry **out_entry)
{
    if (!line || !config || !out_entry)
    {
        return LANTERN_GENESIS_ERR_INVALID_PARAM;
    }

    *out_entry = NULL;

    char *colon = strchr(line, ':');
    if (!colon)
    {
        return 0;
    }

    for (char *p = colon + 1; p && *p; ++p)
    {
        if (!isspace((unsigned char)*p))
        {
            return 0;
        }
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

    *out_entry = lantern_validator_config_find(config, name);
    return 1;
}


/** @brief Parse validators.yaml mapping into explicit indices on config entries. */
static int parse_assignment_file(
    FILE *fp,
    struct lantern_validator_config *config,
    bool *assigned,
    uint64_t validator_count,
    bool *out_saw_mapping,
    size_t *out_assigned_total)
{
    if (!fp || !config || !out_saw_mapping || !out_assigned_total)
    {
        return LANTERN_GENESIS_ERR_INVALID_PARAM;
    }

    *out_saw_mapping = false;
    *out_assigned_total = 0;

    struct lantern_validator_config_entry *current = NULL;

    char line[GENESIS_LINE_BUFFER_LEN];
    while (fgets(line, sizeof(line), fp))
    {
        char *trimmed = lantern_trim_whitespace(line);
        if (!trimmed || *trimmed == '\0' || *trimmed == '#')
        {
            continue;
        }

        if (*trimmed == '-')
        {
            if (!current || !assigned)
            {
                continue;
            }

            char *value = lantern_trim_whitespace(trimmed + 1);
            if (!value || *value == '\0')
            {
                continue;
            }

            int ok = 0;
            uint64_t parsed = parse_u64(value, &ok);
            if (!ok || parsed >= validator_count)
            {
                return LANTERN_GENESIS_ERR_INVALID_DATA;
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
        int mapping_rc = parse_assignment_mapping_key(trimmed, config, &entry);
        if (mapping_rc < 0)
        {
            return mapping_rc;
        }
        if (mapping_rc == 0)
        {
            current = NULL;
            continue;
        }

        current = entry;
        if (entry)
        {
            *out_saw_mapping = true;
            entry->indices_len = 0;
        }
    }

    return LANTERN_GENESIS_OK;
}


/** @brief Validate and finalize assignment entries after parsing. */
static int finalize_assignment_entries(
    struct lantern_validator_config *config,
    uint64_t validator_count)
{
    if (!config || !config->entries || config->count == 0 || validator_count == 0)
    {
        return LANTERN_GENESIS_ERR_INVALID_PARAM;
    }

    for (size_t i = 0; i < config->count; ++i)
    {
        struct lantern_validator_config_entry *entry = &config->entries[i];
        if (entry->indices_len != entry->count || entry->indices_len == 0)
        {
            return LANTERN_GENESIS_ERR_INVALID_DATA;
        }

        qsort(entry->indices, entry->indices_len, sizeof(*entry->indices), compare_u64);

        entry->start_index = entry->indices[0];

        uint64_t last = entry->indices[entry->indices_len - 1];
        if (last == UINT64_MAX)
        {
            return LANTERN_GENESIS_ERR_OVERFLOW;
        }

        entry->end_index = last + 1;
        entry->has_range = true;
    }

    return LANTERN_GENESIS_OK;
}


struct lantern_validator_config_entry *lantern_validator_config_find(
    struct lantern_validator_config *config,
    const char *name)
{
    if (!config || !name || !config->entries)
    {
        return NULL;
    }

    for (size_t i = 0; i < config->count; ++i)
    {
        if (config->entries[i].name && strcmp(config->entries[i].name, name) == 0)
        {
            return &config->entries[i];
        }
    }

    return NULL;
}


int lantern_validator_config_assign_ranges(
    struct lantern_validator_config *config,
    uint64_t validator_count)
{
    if (!config || !config->entries || config->count == 0 || validator_count == 0)
    {
        return LANTERN_GENESIS_ERR_INVALID_PARAM;
    }

    uint64_t next_index = 0;
    for (size_t i = 0; i < config->count; ++i)
    {
        struct lantern_validator_config_entry *entry = &config->entries[i];
        if (entry->count == 0)
        {
            return LANTERN_GENESIS_ERR_INVALID_DATA;
        }

        entry->start_index = next_index;

        if (entry->count > (validator_count - next_index))
        {
            return LANTERN_GENESIS_ERR_INVALID_DATA;
        }

        uint64_t end = next_index + entry->count;
        entry->end_index = end;
        entry->has_range = true;
        next_index = end;
    }

    if (next_index != validator_count)
    {
        return LANTERN_GENESIS_ERR_INVALID_DATA;
    }

    return LANTERN_GENESIS_OK;
}


int lantern_validator_config_apply_assignments(
    struct lantern_validator_config *config,
    const char *path,
    uint64_t validator_count)
{
    if (!config || !config->entries || config->count == 0 || !path)
    {
        return LANTERN_GENESIS_ERR_INVALID_PARAM;
    }

    if (validator_count > SIZE_MAX)
    {
        return LANTERN_GENESIS_ERR_OVERFLOW;
    }

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
            fclose(fp);
            return LANTERN_GENESIS_ERR_OUT_OF_MEMORY;
        }
    }

    bool saw_mapping = false;
    size_t assigned_total = 0;
    int result = parse_assignment_file(
        fp,
        config,
        assigned,
        validator_count,
        &saw_mapping,
        &assigned_total);

    fclose(fp);

    if (!saw_mapping)
    {
        free(assigned);
        return (result == LANTERN_GENESIS_OK) ? LANTERN_GENESIS_OK : result;
    }

    if (result != LANTERN_GENESIS_OK)
    {
        free(assigned);
        return result;
    }

    if (assigned_total != assigned_len)
    {
        free(assigned);
        return LANTERN_GENESIS_ERR_INVALID_DATA;
    }

    result = finalize_assignment_entries(config, validator_count);
    free(assigned);
    return result;
}
