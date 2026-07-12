#include "internal/yaml_parser.h"

#include <ctype.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static char *trim_left(char *text) {
    while (isspace((unsigned char)*text)) {
        ++text;
    }
    return text;
}

static void trim_right(char *text) {
    size_t length = strlen(text);
    while (length > 0u && isspace((unsigned char)text[length - 1u])) {
        text[--length] = '\0';
    }
}

static size_t indentation(const char *line) {
    size_t count = 0u;
    while (line[count] == ' ' || line[count] == '\t') {
        ++count;
    }
    return count;
}

static void yaml_object_reset(LanternYamlObject *object) {
    if (!object) {
        return;
    }
    for (size_t i = 0u; i < object->num_pairs; ++i) {
        free(object->pairs[i].key);
        free(object->pairs[i].value);
    }
    free(object->pairs);
    *object = (LanternYamlObject){0};
}

static int yaml_object_add_pair(LanternYamlObject *object, const char *key, const char *value) {
    if (!object || !key || !value) {
        return -1;
    }
    if (object->num_pairs == object->capacity) {
        size_t capacity = object->capacity ? object->capacity * 2u : 4u;
        if (capacity < object->capacity || capacity > SIZE_MAX / sizeof(*object->pairs)) {
            return -1;
        }
        LanternYamlKeyValPair *pairs = realloc(object->pairs, capacity * sizeof(*pairs));
        if (!pairs) {
            return -1;
        }
        object->pairs = pairs;
        object->capacity = capacity;
    }
    char *key_copy = strdup(key);
    char *value_copy = strdup(value);
    if (!key_copy || !value_copy) {
        free(key_copy);
        free(value_copy);
        return -1;
    }
    object->pairs[object->num_pairs++] = (LanternYamlKeyValPair){
        .key = key_copy,
        .value = value_copy,
    };
    return 0;
}

static int append_object(
    LanternYamlObject *current,
    LanternYamlObject **objects,
    size_t *count,
    size_t *capacity) {
    if (current->num_pairs == 0u) {
        return 0;
    }
    if (*count == *capacity) {
        size_t next_capacity = *capacity ? *capacity * 2u : 4u;
        if (next_capacity < *capacity
            || next_capacity > SIZE_MAX / sizeof(**objects)) {
            return -1;
        }
        LanternYamlObject *next = realloc(*objects, next_capacity * sizeof(*next));
        if (!next) {
            return -1;
        }
        *objects = next;
        *capacity = next_capacity;
    }
    (*objects)[(*count)++] = *current;
    *current = (LanternYamlObject){0};
    return 0;
}

LanternYamlObject *lantern_yaml_read_array(
    const char *file_path,
    const char *array_name,
    size_t *out_count) {
    if (!file_path || !array_name || !out_count) {
        return NULL;
    }
    *out_count = 0u;
    FILE *file = fopen(file_path, "r");
    if (!file) {
        return NULL;
    }

    LanternYamlObject current = {0};
    LanternYamlObject *objects = NULL;
    size_t capacity = 0u;
    size_t target_indent = 0u;
    size_t item_indent = 0u;
    bool in_target = false;
    bool have_item = false;
    bool failed = false;
    char line[2048];

    while (fgets(line, sizeof(line), file)) {
        trim_right(line);
        char *content = trim_left(line);
        if (*content == '\0' || *content == '#') {
            continue;
        }
        size_t indent = indentation(line);

        if (!in_target) {
            char *separator = strchr(content, ':');
            if (!separator) {
                continue;
            }
            *separator = '\0';
            trim_right(content);
            char *value = trim_left(separator + 1);
            if (strcmp(content, array_name) == 0
                && (*value == '\0' || *value == '#')) {
                in_target = true;
                target_indent = indent;
            }
            continue;
        }

        if (indent < target_indent || (indent == target_indent && *content != '-')) {
            break;
        }
        if (*content == '-' && (!have_item || indent <= item_indent)) {
            if (append_object(&current, &objects, out_count, &capacity) != 0) {
                failed = true;
                break;
            }
            have_item = true;
            item_indent = indent;
            content = trim_left(content + 1);
            if (*content == '\0') {
                continue;
            }
        }
        if (!have_item) {
            continue;
        }

        char *separator = strchr(content, ':');
        if (!separator) {
            continue;
        }
        *separator = '\0';
        trim_right(content);
        char *value = trim_left(separator + 1);
        if (*content == '\0' || yaml_object_add_pair(&current, content, value) != 0) {
            failed = true;
            break;
        }
    }

    fclose(file);
    if (!failed && in_target
        && append_object(&current, &objects, out_count, &capacity) != 0) {
        failed = true;
    }
    yaml_object_reset(&current);
    if (failed) {
        lantern_yaml_free_objects(objects, *out_count);
        *out_count = 0u;
        return NULL;
    }
    if (*out_count == 0u) {
        free(objects);
        return NULL;
    }
    return objects;
}

void lantern_yaml_free_objects(LanternYamlObject *objects, size_t count) {
    if (!objects) {
        return;
    }
    for (size_t i = 0u; i < count; ++i) {
        yaml_object_reset(&objects[i]);
    }
    free(objects);
}
