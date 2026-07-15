#ifndef LANTERN_STRING_LIST_H
#define LANTERN_STRING_LIST_H

#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

struct lantern_string_list {
    char **items;
    size_t len;
    size_t capacity;
};

void lantern_string_list_init(struct lantern_string_list *list);
void lantern_string_list_reset(struct lantern_string_list *list);
int lantern_string_list_append(struct lantern_string_list *list, const char *value);
int lantern_string_list_append_unique(struct lantern_string_list *list, const char *value);
bool lantern_string_list_contains(const struct lantern_string_list *list, const char *value);
int lantern_string_list_copy(struct lantern_string_list *dst, const struct lantern_string_list *src);

#ifdef __cplusplus
}
#endif

#endif /* LANTERN_STRING_LIST_H */
