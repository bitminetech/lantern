#ifndef LANTERN_INTERNAL_YAML_PARSER_H
#define LANTERN_INTERNAL_YAML_PARSER_H

#include <stddef.h>

#include <yaml.h>

struct lantern_yaml_document {
    yaml_document_t value;
    int loaded;
};

int lantern_yaml_document_load(const char *path, struct lantern_yaml_document *document);
void lantern_yaml_document_reset(struct lantern_yaml_document *document);
const yaml_node_t *lantern_yaml_root(const struct lantern_yaml_document *document);
const yaml_node_t *lantern_yaml_mapping_get(
    const struct lantern_yaml_document *document,
    const yaml_node_t *mapping,
    const char *key);
const char *lantern_yaml_scalar(const yaml_node_t *node);
size_t lantern_yaml_sequence_length(const yaml_node_t *sequence);
const yaml_node_t *lantern_yaml_sequence_get(
    const struct lantern_yaml_document *document,
    const yaml_node_t *sequence,
    size_t index);

#endif /* LANTERN_INTERNAL_YAML_PARSER_H */
