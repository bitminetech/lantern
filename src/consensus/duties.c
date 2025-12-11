#include "lantern/consensus/duties.h"

#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

static int add_u64(uint64_t a, uint64_t b, uint64_t *out) {
    if (!out) {
        return -1;
    }
    if (a > UINT64_MAX - b) {
        return -1;
    }
    *out = a + b;
    return 0;
}

void lantern_validator_assignment_init(struct lantern_validator_assignment *assignment) {
    if (!assignment) {
        return;
    }
    assignment->start_index = 0;
    assignment->count = 0;
    assignment->indices = NULL;
    assignment->length = 0;
}

void lantern_validator_assignment_reset(struct lantern_validator_assignment *assignment) {
    if (!assignment) {
        return;
    }
    free(assignment->indices);
    assignment->indices = NULL;
    assignment->length = 0;
    assignment->start_index = 0;
    assignment->count = 0;
}

bool lantern_validator_assignment_is_valid(const struct lantern_validator_assignment *assignment) {
    return assignment && assignment->count > 0 && assignment->indices && assignment->length == assignment->count;
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
    dst->count = src->count;
    dst->start_index = src->start_index;
    return 0;
}

int lantern_validator_assignment_from_config(
    const struct lantern_validator_config *config,
    const struct lantern_validator_config_entry *entry,
    struct lantern_validator_assignment *assignment) {
    if (!assignment) {
        return -1;
    }
    lantern_validator_assignment_init(assignment);
    if (!config || !entry || entry->count == 0) {
        return -1;
    }
    if (!config->entries || config->count == 0) {
        return -1;
    }
    uint64_t count = entry->count;
    uint64_t *indices = malloc((size_t)count * sizeof(*indices));
    if (!indices) {
        return -1;
    }

    if (entry->indices && entry->indices_len == entry->count) {
        memcpy(indices, entry->indices, entry->count * sizeof(*indices));
    } else {
        uint64_t start_index = entry->start_index;
        if (!entry->has_range) {
            uint64_t offset = 0;
            bool found = false;
            for (size_t i = 0; i < config->count; ++i) {
                const struct lantern_validator_config_entry *current = &config->entries[i];
                if (current == entry) {
                    found = true;
                    break;
                }
                if (add_u64(offset, current->count, &offset) != 0) {
                    free(indices);
                    return -1;
                }
            }
            if (!found) {
                free(indices);
                return -1;
            }
            start_index = offset;
        }
        uint64_t end_index = start_index + count;
        if (end_index < start_index) {
            free(indices);
            return -1;
        }
        for (uint64_t i = 0; i < count; ++i) {
            indices[i] = start_index + i;
        }
    }

    assignment->indices = indices;
    assignment->length = (size_t)count;
    assignment->count = count;
    assignment->start_index = indices[0];
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
