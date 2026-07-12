#include "lantern/consensus/duties.h"

#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

void lantern_validator_assignment_init(struct lantern_validator_assignment *assignment) {
    if (!assignment) {
        return;
    }
    *assignment = (struct lantern_validator_assignment){0};
}

void lantern_validator_assignment_reset(struct lantern_validator_assignment *assignment) {
    if (!assignment) {
        return;
    }
    free(assignment->indices);
    *assignment = (struct lantern_validator_assignment){0};
}

bool lantern_validator_assignment_is_valid(const struct lantern_validator_assignment *assignment) {
    return assignment && assignment->indices && assignment->length > 0;
}

int lantern_validator_assignment_copy(
    struct lantern_validator_assignment *dst,
    const struct lantern_validator_assignment *src) {
    if (!dst || !src || !lantern_validator_assignment_is_valid(src)) {
        return -1;
    }
    lantern_validator_assignment_reset(dst);
    dst->indices = malloc(src->length * sizeof(*dst->indices));
    if (!dst->indices) {
        return -1;
    }
    memcpy(dst->indices, src->indices, src->length * sizeof(*dst->indices));
    dst->length = src->length;
    return 0;
}

int lantern_validator_assignment_from_config(
    const struct lantern_validator_config_entry *entry,
    struct lantern_validator_assignment *assignment) {
    if (!assignment) {
        return -1;
    }
    lantern_validator_assignment_init(assignment);
    if (!entry || !entry->indices || entry->indices_len == 0
        || entry->indices_len != entry->count) {
        return -1;
    }
    uint64_t *indices = malloc(entry->indices_len * sizeof(*indices));
    if (!indices) {
        return -1;
    }
    memcpy(indices, entry->indices, entry->indices_len * sizeof(*indices));
    assignment->indices = indices;
    assignment->length = entry->indices_len;
    return 0;
}

int lantern_proposer_for_slot(uint64_t slot, uint64_t validator_count, uint64_t *out_proposer_index) {
    if (!out_proposer_index || validator_count == 0) {
        return -1;
    }
    *out_proposer_index = slot % validator_count;
    return 0;
}

bool lantern_validator_assignment_contains(
    const struct lantern_validator_assignment *assignment,
    uint64_t global_validator_index,
    uint64_t *out_local_index) {
    if (!lantern_validator_assignment_is_valid(assignment)) {
        return false;
    }
    size_t low = 0;
    size_t high = assignment->length;
    while (low < high) {
        size_t mid = low + ((high - low) / 2);
        uint64_t value = assignment->indices[mid];
        if (value == global_validator_index) {
            if (out_local_index) {
                *out_local_index = mid;
            }
            return true;
        }
        if (value < global_validator_index) {
            low = mid + 1;
        } else {
            high = mid;
        }
    }
    return false;
}
