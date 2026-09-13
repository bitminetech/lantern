#include "lantern/support/string_list.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "lantern/support/strings.h"

struct lantern_string_list_storage
{
    char **items;
    size_t len;
    size_t capacity;
};

static enum lantern_string_list_result string_list_reserve(
    struct lantern_string_list *list, size_t new_capacity)
{
    struct lantern_string_list_storage *storage = list->storage;

    if (storage && new_capacity <= storage->capacity)
    {
        return LANTERN_STRING_LIST_OK;
    }

    if (new_capacity > SIZE_MAX / sizeof(*storage->items))
    {
        return LANTERN_STRING_LIST_ERR_RANGE;
    }

    bool created = false;

    if (!storage)
    {
        storage = calloc(1u, sizeof(*storage));

        if (!storage)
        {
            return LANTERN_STRING_LIST_ERR_ALLOC;
        }

        created = true;
    }

    size_t adjusted = storage->capacity == 0 ? 4u : storage->capacity;

    while (adjusted < new_capacity)
    {
        if (adjusted > SIZE_MAX / 2u)
        {
            adjusted = new_capacity;
            break;
        }

        adjusted *= 2u;
    }

    if (adjusted > SIZE_MAX / sizeof(*storage->items))
    {
        if (created)
        {
            free(storage);
        }

        return LANTERN_STRING_LIST_ERR_RANGE;
    }

    char **items = realloc(storage->items, adjusted * sizeof(*items));

    if (!items)
    {
        if (created)
        {
            free(storage);
        }

        return LANTERN_STRING_LIST_ERR_ALLOC;
    }

    storage->items = items;
    storage->capacity = adjusted;
    list->storage = storage;
    return LANTERN_STRING_LIST_OK;
}

void lantern_string_list_init(struct lantern_string_list *list)
{
    if (list)
    {
        list->storage = NULL;
    }
}

void lantern_string_list_reset(struct lantern_string_list *list)
{
    if (!list || !list->storage)
    {
        return;
    }

    struct lantern_string_list_storage *storage = list->storage;

    for (size_t i = 0; i < storage->len; ++i)
    {
        free(storage->items[i]);
    }

    free(storage->items);
    free(storage);
    list->storage = NULL;
}

enum lantern_string_list_result lantern_string_list_append(
    struct lantern_string_list *list, const char *value)
{
    if (!list || !value)
    {
        return LANTERN_STRING_LIST_ERR_INVALID;
    }

    size_t len = list->storage ? list->storage->len : 0u;

    if (len == SIZE_MAX)
    {
        return LANTERN_STRING_LIST_ERR_RANGE;
    }

    /* Copy first so allocation failure leaves the list unchanged. */
    char *copy = lantern_string_duplicate(value);

    if (!copy)
    {
        return LANTERN_STRING_LIST_ERR_ALLOC;
    }

    enum lantern_string_list_result reserve_result =
        string_list_reserve(list, len + 1u);

    if (reserve_result != LANTERN_STRING_LIST_OK)
    {
        free(copy);
        return reserve_result;
    }

    list->storage->items[len] = copy;
    list->storage->len = len + 1u;
    return LANTERN_STRING_LIST_OK;
}

bool lantern_string_list_contains(const struct lantern_string_list *list,
                                  const char *value)
{
    if (!list || !list->storage || !value)
    {
        return false;
    }

    for (size_t i = 0; i < list->storage->len; ++i)
    {
        if (strcmp(list->storage->items[i], value) == 0)
        {
            return true;
        }
    }

    return false;
}

enum lantern_string_list_result
lantern_string_list_remove(struct lantern_string_list *list,
                           const char *value)
{
    if (!list || !value)
    {
        return LANTERN_STRING_LIST_ERR_INVALID;
    }

    if (!list->storage)
    {
        return LANTERN_STRING_LIST_NOT_FOUND;
    }

    struct lantern_string_list_storage *storage = list->storage;

    for (size_t i = 0; i < storage->len; ++i)
    {
        if (strcmp(storage->items[i], value) != 0)
        {
            continue;
        }

        free(storage->items[i]);

        if (i + 1u < storage->len)
        {
            memmove(&storage->items[i], &storage->items[i + 1u],
                    (storage->len - i - 1u) * sizeof(*storage->items));
        }

        storage->len -= 1u;
        storage->items[storage->len] = NULL;
        return LANTERN_STRING_LIST_OK;
    }

    return LANTERN_STRING_LIST_NOT_FOUND;
}

enum lantern_string_list_result lantern_string_list_append_unique(
    struct lantern_string_list *list, const char *value)
{
    if (!list || !value)
    {
        return LANTERN_STRING_LIST_ERR_INVALID;
    }

    if (*value == '\0' || lantern_string_list_contains(list, value))
    {
        return LANTERN_STRING_LIST_OK;
    }

    return lantern_string_list_append(list, value);
}

enum lantern_string_list_result lantern_string_list_copy(
    struct lantern_string_list *dst, const struct lantern_string_list *src)
{
    if (!dst || !src)
    {
        return LANTERN_STRING_LIST_ERR_INVALID;
    }

    if (dst == src)
    {
        return LANTERN_STRING_LIST_OK;
    }

    struct lantern_string_list copy;
    lantern_string_list_init(&copy);

    /* Build a separate replacement so failure preserves the destination. */
    size_t count = lantern_string_list_count(src);

    if (count > 0)
    {
        enum lantern_string_list_result result =
            string_list_reserve(&copy, count);

        if (result != LANTERN_STRING_LIST_OK)
        {
            return result;
        }
    }

    for (size_t i = 0; i < count; ++i)
    {
        char *item = lantern_string_duplicate(lantern_string_list_get(src, i));

        if (!item)
        {
            lantern_string_list_reset(&copy);
            return LANTERN_STRING_LIST_ERR_ALLOC;
        }

        copy.storage->items[copy.storage->len++] = item;
    }

    lantern_string_list_reset(dst);
    *dst = copy;
    return LANTERN_STRING_LIST_OK;
}

size_t lantern_string_list_count(const struct lantern_string_list *list)
{
    return list && list->storage ? list->storage->len : 0u;
}

const char *lantern_string_list_get(const struct lantern_string_list *list,
                                   size_t index)
{
    if (!list || !list->storage || index >= list->storage->len)
    {
        return NULL;
    }

    return list->storage->items[index];
}
