#include "lantern/support/string_list.h"

#include "lantern/support/strings.h"

#include <stdlib.h>
#include <string.h>

void lantern_string_list_init(struct lantern_string_list *list) {
    if (!list) {
        return;
    }
    list->items = NULL;
    list->len = 0;
    list->capacity = 0;
}

void lantern_string_list_reset(struct lantern_string_list *list) {
    if (!list) {
        return;
    }
    if (list->items) {
        size_t limit = list->len;
        if (list->capacity > 0 && limit > list->capacity) {
            limit = list->capacity;
        }
        for (size_t i = 0; i < limit; ++i) {
            free(list->items[i]);
            list->items[i] = NULL;
        }
        free(list->items);
    }
    list->items = NULL;
    list->len = 0;
    list->capacity = 0;
}

static int lantern_string_list_reserve(struct lantern_string_list *list, size_t new_capacity) {
    if (new_capacity <= list->capacity) {
        return 0;
    }
    size_t adjusted = list->capacity == 0 ? 4 : list->capacity;
    while (adjusted < new_capacity) {
        adjusted *= 2;
    }

    char **items = realloc(list->items, adjusted * sizeof(char *));
    if (!items) {
        return -1;
    }

    for (size_t i = list->capacity; i < adjusted; ++i) {
        items[i] = NULL;
    }

    list->items = items;
    list->capacity = adjusted;
    return 0;
}

int lantern_string_list_append(struct lantern_string_list *list, const char *value) {
    if (!list || !value) {
        return -1;
    }

    if (lantern_string_list_reserve(list, list->len + 1) != 0) {
        return -1;
    }

    char *copy = lantern_string_duplicate(value);
    if (!copy) {
        return -1;
    }

    list->items[list->len++] = copy;
    return 0;
}

bool lantern_string_list_contains(const struct lantern_string_list *list, const char *value) {
    if (!list || !value) {
        return false;
    }
    for (size_t i = 0; i < list->len; ++i) {
        if (list->items[i] && strcmp(list->items[i], value) == 0) {
            return true;
        }
    }
    return false;
}

int lantern_string_list_append_unique(struct lantern_string_list *list, const char *value) {
    if (!list || !value) {
        return -1;
    }
    if (*value == '\0' || lantern_string_list_contains(list, value)) {
        return 0;
    }
    return lantern_string_list_append(list, value);
}

int lantern_string_list_copy(struct lantern_string_list *dst, const struct lantern_string_list *src) {
    if (!dst || !src) {
        return -1;
    }

    lantern_string_list_reset(dst);

    if (src->len == 0) {
        return 0;
    }

    if (lantern_string_list_reserve(dst, src->len) != 0) {
        return -1;
    }

    for (size_t i = 0; i < src->len; ++i) {
        char *copy = lantern_string_duplicate(src->items[i]);
        if (!copy) {
            lantern_string_list_reset(dst);
            return -1;
        }
        dst->items[dst->len++] = copy;
    }

    return 0;
}
