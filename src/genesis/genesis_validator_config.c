#include "lantern/genesis/genesis.h"

#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

#include "genesis_internal.h"

static int compare_u64(const void *left, const void *right)
{
    uint64_t lhs = *(const uint64_t *)left;
    uint64_t rhs = *(const uint64_t *)right;
    return lhs < rhs ? -1 : lhs > rhs;
}

struct lantern_validator_config_entry *lantern_validator_config_find(
    struct lantern_validator_config *config,
    const char *name)
{
    if (!config || !name)
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
    if (!config || !config->entries || config->count == 0u || validator_count == 0u)
    {
        return LANTERN_GENESIS_ERR_INVALID_PARAM;
    }
    uint64_t next = 0u;
    for (size_t entry_index = 0; entry_index < config->count; ++entry_index)
    {
        struct lantern_validator_config_entry *entry = &config->entries[entry_index];
        if (entry->count == 0u || next > validator_count
            || entry->count > validator_count - next
            || entry->count > SIZE_MAX / sizeof(*entry->indices))
        {
            return LANTERN_GENESIS_ERR_INVALID_DATA;
        }
        uint64_t *indices = realloc(entry->indices, (size_t)entry->count * sizeof(*indices));
        if (!indices)
        {
            return LANTERN_GENESIS_ERR_OUT_OF_MEMORY;
        }
        entry->indices = indices;
        entry->indices_len = (size_t)entry->count;
        for (size_t i = 0; i < entry->indices_len; ++i)
        {
            entry->indices[i] = next++;
        }
    }
    return next == validator_count ? LANTERN_GENESIS_OK : LANTERN_GENESIS_ERR_INVALID_DATA;
}

static bool entry_has_index(const struct lantern_validator_config_entry *entry, uint64_t index)
{
    for (size_t i = 0; entry && i < entry->indices_len; ++i)
    {
        if (entry->indices[i] == index)
        {
            return true;
        }
    }
    return false;
}

static const char *assignment_index_text(
    const struct lantern_yaml_document *document,
    const yaml_node_t *item)
{
    if (!item)
    {
        return NULL;
    }
    if (item->type == YAML_SCALAR_NODE)
    {
        return lantern_yaml_scalar(item);
    }
    return lantern_yaml_scalar(lantern_yaml_mapping_get(document, item, "index"));
}

int lantern_validator_config_apply_assignments(
    struct lantern_validator_config *config,
    const char *path,
    uint64_t validator_count)
{
    if (!config || !config->entries || config->count == 0u || !path
        || validator_count == 0u || validator_count > SIZE_MAX)
    {
        return LANTERN_GENESIS_ERR_INVALID_PARAM;
    }
    struct lantern_yaml_document document;
    if (lantern_yaml_document_load(path, &document) != 0)
    {
        return LANTERN_GENESIS_ERR_IO;
    }
    const yaml_node_t *root = lantern_yaml_root(&document);
    bool *assigned = calloc((size_t)validator_count, sizeof(*assigned));
    int result = assigned && root && root->type == YAML_MAPPING_NODE
        ? LANTERN_GENESIS_OK
        : LANTERN_GENESIS_ERR_INVALID_DATA;
    size_t assigned_count = 0u;
    bool matched = false;

    for (size_t entry_index = 0; result == LANTERN_GENESIS_OK && entry_index < config->count;
         ++entry_index)
    {
        struct lantern_validator_config_entry *entry = &config->entries[entry_index];
        const yaml_node_t *sequence = lantern_yaml_mapping_get(&document, root, entry->name);
        if (!sequence)
        {
            continue;
        }
        matched = true;
        if (entry->count > SIZE_MAX / sizeof(*entry->indices))
        {
            result = LANTERN_GENESIS_ERR_INVALID_DATA;
            break;
        }
        uint64_t *indices = realloc(entry->indices, (size_t)entry->count * sizeof(*indices));
        if (!indices)
        {
            result = LANTERN_GENESIS_ERR_OUT_OF_MEMORY;
            break;
        }
        entry->indices = indices;
        entry->indices_len = 0u;
        for (size_t i = 0; i < lantern_yaml_sequence_length(sequence); ++i)
        {
            int ok = 0;
            uint64_t index = genesis_parse_u64(
                assignment_index_text(
                    &document,
                    lantern_yaml_sequence_get(&document, sequence, i)),
                &ok);
            if (!ok || index >= validator_count)
            {
                result = LANTERN_GENESIS_ERR_INVALID_DATA;
                break;
            }
            if (entry_has_index(entry, index))
            {
                continue;
            }
            if (assigned[(size_t)index] || entry->indices_len >= entry->count)
            {
                result = LANTERN_GENESIS_ERR_INVALID_DATA;
                break;
            }
            entry->indices[entry->indices_len++] = index;
            assigned[(size_t)index] = true;
            ++assigned_count;
        }
    }
    if (result == LANTERN_GENESIS_OK && matched)
    {
        if (assigned_count != (size_t)validator_count)
        {
            result = LANTERN_GENESIS_ERR_INVALID_DATA;
        }
        for (size_t i = 0; result == LANTERN_GENESIS_OK && i < config->count; ++i)
        {
            if (config->entries[i].indices_len != config->entries[i].count)
            {
                result = LANTERN_GENESIS_ERR_INVALID_DATA;
            }
            else
            {
                qsort(
                    config->entries[i].indices,
                    config->entries[i].indices_len,
                    sizeof(*config->entries[i].indices),
                    compare_u64);
            }
        }
    }
    free(assigned);
    lantern_yaml_document_reset(&document);
    return result;
}
