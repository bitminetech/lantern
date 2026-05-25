#include "internal/yaml_parser.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum { LANTERN_YAML_MAX_STACK_DEPTH = 64 };

static int get_indentation(const char *line) {
    int count = 0;
    while (*line == ' ' || *line == '\t') {
        ++count;
        ++line;
    }
    return count;
}

static char *trim_left(char *str) {
    while (isspace((unsigned char)*str)) {
        ++str;
    }
    return str;
}

static void rstrip(char *str) {
    size_t len = strlen(str);
    while (len > 0) {
        if (!isspace((unsigned char)str[len - 1])) {
            break;
        }
        str[len - 1] = '\0';
        --len;
    }
}

static char *build_path(char **keys, int count) {
    if (count <= 0) {
        return NULL;
    }

    size_t total = 0;
    for (int i = 0; i < count; ++i) {
        total += strlen(keys[i]);
    }
    total += (size_t)(count - 1);

    char *path = malloc(total + 1);
    if (!path) {
        return NULL;
    }

    path[0] = '\0';
    for (int i = 0; i < count; ++i) {
        strcat(path, keys[i]);
        if (i < count - 1) {
            strcat(path, ".");
        }
    }
    return path;
}

static void pop_stack(char *keys_stack[], int *stack_size) {
    if (*stack_size <= 0) {
        return;
    }
    free(keys_stack[*stack_size - 1]);
    keys_stack[*stack_size - 1] = NULL;
    --(*stack_size);
}

static void add_pair(LanternYamlObject *obj, const char *key, const char *value) {
    if (!obj || !key || !value) {
        return;
    }

    if (obj->num_pairs == obj->capacity) {
        size_t new_capacity = obj->capacity == 0 ? 4 : obj->capacity * 2;
        LanternYamlKeyValPair *pairs = realloc(obj->pairs, new_capacity * sizeof(*pairs));
        if (!pairs) {
            return;
        }
        obj->pairs = pairs;
        obj->capacity = new_capacity;
    }

    obj->pairs[obj->num_pairs].key = strdup(key);
    obj->pairs[obj->num_pairs].value = strdup(value);
    if (!obj->pairs[obj->num_pairs].key || !obj->pairs[obj->num_pairs].value) {
        free(obj->pairs[obj->num_pairs].key);
        free(obj->pairs[obj->num_pairs].value);
        obj->pairs[obj->num_pairs].key = NULL;
        obj->pairs[obj->num_pairs].value = NULL;
        return;
    }
    obj->num_pairs++;
}

static int commit_current(
    LanternYamlObject *current,
    LanternYamlObject **objects,
    size_t *capacity,
    size_t *count) {
    if (!current || current->num_pairs == 0) {
        return 0;
    }

    if (*count == *capacity) {
        size_t new_capacity = (*capacity == 0) ? 4 : (*capacity * 2);
        LanternYamlObject *new_objects = realloc(*objects, new_capacity * sizeof(*new_objects));
        if (!new_objects) {
            return -1;
        }
        *objects = new_objects;
        *capacity = new_capacity;
    }

    (*objects)[*count] = *current;
    (*count)++;

    current->pairs = NULL;
    current->num_pairs = 0;
    current->capacity = 0;
    return 0;
}

static void free_yaml_object(LanternYamlObject *object) {
    if (!object || !object->pairs) {
        return;
    }
    for (size_t i = 0; i < object->num_pairs; ++i) {
        free(object->pairs[i].key);
        free(object->pairs[i].value);
    }
    free(object->pairs);
    object->pairs = NULL;
    object->num_pairs = 0;
    object->capacity = 0;
}

LanternYamlObject *lantern_yaml_read_array(const char *file_path, const char *array_name, size_t *out_count) {
    if (!file_path || !array_name || !out_count) {
        return NULL;
    }

    *out_count = 0;

    FILE *fp = fopen(file_path, "r");
    if (!fp) {
        return NULL;
    }

    int stack_size = 0;
    char *keys_stack[LANTERN_YAML_MAX_STACK_DEPTH] = {0};
    int indent_stack[LANTERN_YAML_MAX_STACK_DEPTH] = {0};
    int in_target_array = 0;
    int array_depth = -1;
    int parse_error = 0;

    LanternYamlObject current = {.pairs = NULL, .num_pairs = 0, .capacity = 0};
    LanternYamlObject *objects = NULL;
    size_t capacity = 0;

    char line[2048];
    while (fgets(line, sizeof(line), fp)) {
        rstrip(line);
        char *content = trim_left(line);
        if (*content == '\0') {
            continue;
        }

        int indent = get_indentation(line);

        if (content[0] == '-') {
            while (stack_size > 0 && indent_stack[stack_size - 1] >= indent) {
                if (in_target_array && stack_size == array_depth && indent_stack[stack_size - 1] == indent) {
                    break;
                }
                pop_stack(keys_stack, &stack_size);
                if (in_target_array && stack_size < array_depth) {
                    if (commit_current(&current, &objects, &capacity, out_count) != 0) {
                        parse_error = 1;
                        break;
                    }
                    in_target_array = 0;
                }
            }
            if (parse_error) {
                break;
            }
            if (in_target_array) {
                if (commit_current(&current, &objects, &capacity, out_count) != 0) {
                    parse_error = 1;
                    break;
                }
            }
            content++;
            while (isspace((unsigned char)*content)) {
                content++;
            }
            if (*content == '\0') {
                continue;
            }
        } else {
            while (stack_size > 0 && indent_stack[stack_size - 1] >= indent) {
                pop_stack(keys_stack, &stack_size);
                if (in_target_array && stack_size < array_depth) {
                    if (commit_current(&current, &objects, &capacity, out_count) != 0) {
                        parse_error = 1;
                        break;
                    }
                    in_target_array = 0;
                }
            }
            if (parse_error) {
                break;
            }
        }

        char *sep = strchr(content, ':');
        if (!sep) {
            continue;
        }
        *sep = '\0';
        char *key = content;
        char *val = sep + 1;
        while (*val && isspace((unsigned char)*val)) {
            ++val;
        }

        char *key_copy = strdup(key);
        if (!key_copy) {
            parse_error = 1;
            break;
        }

        if (stack_size >= LANTERN_YAML_MAX_STACK_DEPTH) {
            free(key_copy);
            parse_error = 1;
            break;
        }

        keys_stack[stack_size] = key_copy;
        indent_stack[stack_size] = indent;
        stack_size++;

        char *full_path = build_path(keys_stack, stack_size);
        if (!full_path) {
            pop_stack(keys_stack, &stack_size);
            parse_error = 1;
            break;
        }

        if (strcmp(full_path, array_name) == 0) {
            in_target_array = 1;
            array_depth = stack_size;
        }

        if (in_target_array && strcmp(full_path, array_name) != 0) {
            const char *store_key = key;
            char *last_dot = strrchr(full_path, '.');
            if (last_dot && *(last_dot + 1)) {
                store_key = last_dot + 1;
            }
            add_pair(&current, store_key, val);
        }

        free(full_path);
    }

    fclose(fp);

    if (!parse_error && in_target_array) {
        if (commit_current(&current, &objects, &capacity, out_count) != 0) {
            parse_error = 1;
        }
    }

    if (parse_error) {
        free_yaml_object(&current);
        lantern_yaml_free_objects(objects, *out_count);
        for (int i = 0; i < stack_size; ++i) {
            free(keys_stack[i]);
        }
        *out_count = 0;
        return NULL;
    }

    for (int i = 0; i < stack_size; ++i) {
        free(keys_stack[i]);
    }
    free_yaml_object(&current);

    if (*out_count == 0) {
        free(objects);
        objects = NULL;
    }

    return objects;
}

void lantern_yaml_free_objects(LanternYamlObject *objects, size_t count) {
    if (!objects) {
        return;
    }
    for (size_t i = 0; i < count; ++i) {
        for (size_t j = 0; j < objects[i].num_pairs; ++j) {
            free(objects[i].pairs[j].key);
            free(objects[i].pairs[j].value);
        }
        free(objects[i].pairs);
    }
    free(objects);
}
