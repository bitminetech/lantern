#include "internal/yaml_parser.h"

#include <stdio.h>
#include <string.h>

int lantern_yaml_document_load(const char *path, struct lantern_yaml_document *document)
{
    if (!path || !document)
    {
        return -1;
    }
    *document = (struct lantern_yaml_document){0};
    FILE *file = fopen(path, "rb");
    if (!file)
    {
        return -1;
    }
    yaml_parser_t parser;
    int ok = yaml_parser_initialize(&parser);
    if (ok)
    {
        yaml_parser_set_input_file(&parser, file);
        ok = yaml_parser_load(&parser, &document->value);
        yaml_parser_delete(&parser);
    }
    fclose(file);
    document->loaded = ok;
    return ok ? 0 : -1;
}

void lantern_yaml_document_reset(struct lantern_yaml_document *document)
{
    if (document && document->loaded)
    {
        yaml_document_delete(&document->value);
        *document = (struct lantern_yaml_document){0};
    }
}

const yaml_node_t *lantern_yaml_root(const struct lantern_yaml_document *document)
{
    return document && document->loaded
        ? yaml_document_get_root_node((yaml_document_t *)&document->value)
        : NULL;
}

const char *lantern_yaml_scalar(const yaml_node_t *node)
{
    return node && node->type == YAML_SCALAR_NODE ? (const char *)node->data.scalar.value : NULL;
}

const yaml_node_t *lantern_yaml_mapping_get(
    const struct lantern_yaml_document *document,
    const yaml_node_t *mapping,
    const char *key)
{
    if (!document || !document->loaded || !mapping || mapping->type != YAML_MAPPING_NODE || !key)
    {
        return NULL;
    }
    for (yaml_node_pair_t *pair = mapping->data.mapping.pairs.start;
         pair < mapping->data.mapping.pairs.top;
         ++pair)
    {
        const yaml_node_t *key_node = yaml_document_get_node(
            (yaml_document_t *)&document->value,
            pair->key);
        const char *name = lantern_yaml_scalar(key_node);
        if (name && strcmp(name, key) == 0)
        {
            return yaml_document_get_node((yaml_document_t *)&document->value, pair->value);
        }
    }
    return NULL;
}

size_t lantern_yaml_sequence_length(const yaml_node_t *sequence)
{
    return sequence && sequence->type == YAML_SEQUENCE_NODE
        ? (size_t)(sequence->data.sequence.items.top - sequence->data.sequence.items.start)
        : 0u;
}

const yaml_node_t *lantern_yaml_sequence_get(
    const struct lantern_yaml_document *document,
    const yaml_node_t *sequence,
    size_t index)
{
    size_t length = lantern_yaml_sequence_length(sequence);
    if (!document || !document->loaded || index >= length)
    {
        return NULL;
    }
    return yaml_document_get_node(
        (yaml_document_t *)&document->value,
        sequence->data.sequence.items.start[index]);
}
