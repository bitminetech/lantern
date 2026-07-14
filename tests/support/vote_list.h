#ifndef LANTERN_TESTS_VOTE_LIST_H
#define LANTERN_TESTS_VOTE_LIST_H

#include <stddef.h>
#include <stdlib.h>
#include <string.h>

#include "lantern/consensus/containers.h"

typedef struct {
    LanternVote *data;
    size_t length;
    size_t capacity;
} LanternAttestations;

static inline void lantern_attestations_init(LanternAttestations *list) {
    if (list) {
        memset(list, 0, sizeof(*list));
    }
}

static inline void lantern_attestations_reset(LanternAttestations *list) {
    if (list) {
        free(list->data);
        memset(list, 0, sizeof(*list));
    }
}

static inline int lantern_attestations_resize(LanternAttestations *list, size_t length) {
    if (!list || length > SIZE_MAX / sizeof(*list->data)) {
        return -1;
    }
    if (length > list->capacity) {
        LanternVote *data = realloc(list->data, length * sizeof(*data));
        if (!data) {
            return -1;
        }
        list->data = data;
        list->capacity = length;
    }
    if (length > list->length) {
        memset(list->data + list->length, 0, (length - list->length) * sizeof(*list->data));
    } else if (length < list->length) {
        memset(list->data + length, 0, (list->length - length) * sizeof(*list->data));
    }
    list->length = length;
    return 0;
}

#endif /* LANTERN_TESTS_VOTE_LIST_H */
