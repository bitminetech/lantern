#include "lantern/consensus/state.h"

#include <inttypes.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "lantern/support/log.h"
#include "lantern/support/strings.h"
#include "lantern/support/time.h"
#include "lantern/metrics/lean_metrics.h"

#include "lantern/consensus/duties.h"
#include "lantern/consensus/fork_choice.h"
#include "lantern/consensus/hash.h"
#include "lantern/consensus/quorum.h"

struct lantern_vote_record {
    LanternVote vote;
    LanternSignature signature;
    bool has_vote;
    bool has_signature;
};

static void record_attestation_validation_metric(double start_seconds, bool valid) {
    lean_metrics_record_attestation_validation(lantern_time_now_seconds() - start_seconds, valid);
}

static void format_root_hex(const LanternRoot *root, char *out, size_t out_len) {
    if (!out || out_len == 0) {
        return;
    }
    out[0] = '\0';
    if (!root) {
        return;
    }
    if (lantern_bytes_to_hex(root->bytes, LANTERN_ROOT_SIZE, out, out_len, 1) != 0) {
        out[0] = '\0';
    }
}

static bool finalization_trace_enabled(void) {
    return false;
}

static bool lantern_checkpoint_equal(const LanternCheckpoint *a, const LanternCheckpoint *b);

static int lantern_root_list_append(struct lantern_root_list *list, const LanternRoot *root);
static int lantern_root_list_drop_front(struct lantern_root_list *list, size_t count);
static int lantern_bitlist_set_bit(struct lantern_bitlist *list, size_t index, bool value);
static int lantern_bitlist_get_bit(const struct lantern_bitlist *list, size_t index, bool *out_value);
static int lantern_bitlist_ensure_length(struct lantern_bitlist *list, size_t bit_length);
static int lantern_bitlist_drop_front(struct lantern_bitlist *list, size_t bits);
static void lantern_root_zero(LanternRoot *root);
static int lantern_state_append_historical_root(LanternState *state, const LanternRoot *root);
static int lantern_state_set_justified_slot_bit(LanternState *state, uint64_t slot, bool value);
bool lantern_state_slot_in_justified_window(const LanternState *state, uint64_t slot);
int lantern_state_get_justified_slot_bit(const LanternState *state, uint64_t slot, bool *out_value);
static bool attestation_list_contains_validator(const LanternAttestations *list, uint64_t validator_id);
static int collect_attestations_for_checkpoint(
    const LanternState *state,
    const LanternCheckpoint *checkpoint,
    LanternAttestations *out_attestations,
    LanternSignatureList *out_signatures);
static int lantern_state_process_attestations_internal(
    LanternState *state,
    const LanternAttestations *attestations,
    const LanternSignatureList *signatures,
    bool apply_consensus_effects);

static bool signature_is_zero(const LanternSignature *signature) {
    if (!signature) {
        return true;
    }
    for (size_t i = 0; i < LANTERN_SIGNATURE_SIZE; ++i) {
        if (signature->bytes[i] != 0u) {
            return false;
        }
    }
    return true;
}

static bool attestation_list_contains_validator(const LanternAttestations *list, uint64_t validator_id) {
    if (!list || !list->data || list->length == 0) {
        return false;
    }
    for (size_t i = 0; i < list->length; ++i) {
        if (list->data[i].validator_id == validator_id) {
            return true;
        }
    }
    return false;
}

static int collect_attestations_for_checkpoint(
    const LanternState *state,
    const LanternCheckpoint *checkpoint,
    LanternAttestations *out_attestations,
    LanternSignatureList *out_signatures) {
    if (!state || !checkpoint || !out_attestations || !out_signatures) {
        return -1;
    }
    if (!state->validator_votes || state->validator_votes_len == 0) {
        return 0;
    }
    for (size_t i = 0; i < state->validator_votes_len; ++i) {
        const struct lantern_vote_record *record = &state->validator_votes[i];
        if (!record->has_vote) {
            continue;
        }
        if (!lantern_checkpoint_equal(&record->vote.source, checkpoint)) {
            continue;
        }
        if (attestation_list_contains_validator(out_attestations, record->vote.validator_id)) {
            continue;
        }
        if (out_attestations->length >= LANTERN_MAX_ATTESTATIONS) {
            (void)lantern_attestations_resize(out_attestations, 0);
            (void)lantern_signature_list_resize(out_signatures, 0);
            return -1;
        }
        LanternVote vote = record->vote;
        if (lantern_attestations_append(out_attestations, &vote) != 0) {
            (void)lantern_attestations_resize(out_attestations, 0);
            (void)lantern_signature_list_resize(out_signatures, 0);
            return -1;
        }
        LanternSignature signature;
        memset(&signature, 0, sizeof(signature));
        if (record->has_signature) {
            signature = record->signature;
        }
        if (lantern_signature_list_append(out_signatures, &signature) != 0) {
            (void)lantern_attestations_resize(out_attestations, 0);
            (void)lantern_signature_list_resize(out_signatures, 0);
            return -1;
        }
    }
    return 0;
}


int lantern_state_mark_justified_slot(LanternState *state, uint64_t slot);

static size_t bitlist_required_bytes(size_t bit_length) {
    if (bit_length == 0) {
        return 0;
    }
    return (bit_length + 7) / 8;
}

static int ensure_root_capacity(struct lantern_root_list *list, size_t required) {
    if (!list) {
        return -1;
    }
    if (list->capacity >= required) {
        return 0;
    }
    size_t new_capacity = list->capacity == 0 ? 4 : list->capacity;
    while (new_capacity < required) {
        if (new_capacity > (SIZE_MAX / 2)) {
            return -1;
        }
        new_capacity *= 2;
    }
    LanternRoot *items = realloc(list->items, new_capacity * sizeof(*items));
    if (!items) {
        return -1;
    }
    list->items = items;
    list->capacity = new_capacity;
    return 0;
}

static int ensure_bit_capacity(struct lantern_bitlist *list, size_t required_bytes) {
    if (!list) {
        return -1;
    }
    if (list->capacity >= required_bytes) {
        return 0;
    }
    size_t new_capacity = list->capacity == 0 ? 4 : list->capacity;
    while (new_capacity < required_bytes) {
        if (new_capacity > (SIZE_MAX / 2)) {
            return -1;
        }
        new_capacity *= 2;
    }
    size_t old_capacity = list->capacity;
    uint8_t *bytes = realloc(list->bytes, new_capacity * sizeof(*bytes));
    if (!bytes) {
        return -1;
    }
    if (new_capacity > old_capacity) {
        memset(bytes + old_capacity, 0, new_capacity - old_capacity);
    }
    list->bytes = bytes;
    list->capacity = new_capacity;
    return 0;
}

void lantern_root_list_init(struct lantern_root_list *list) {
    if (!list) {
        return;
    }
    list->items = NULL;
    list->length = 0;
    list->capacity = 0;
}

void lantern_root_list_reset(struct lantern_root_list *list) {
    if (!list) {
        return;
    }
    free(list->items);
    list->items = NULL;
    list->length = 0;
    list->capacity = 0;
}

static int clone_root_list(struct lantern_root_list *dst, const struct lantern_root_list *src) {
    lantern_root_list_init(dst);
    if (!src || src->length == 0) {
        return 0;
    }
    if (!src->items) {
        return -1;
    }
    size_t count = src->length;
    LanternRoot *items = malloc(count * sizeof(*items));
    if (!items) {
        return -1;
    }
    memcpy(items, src->items, count * sizeof(*items));
    dst->items = items;
    dst->length = count;
    dst->capacity = count;
    return 0;
}

static int clone_bitlist(struct lantern_bitlist *dst, const struct lantern_bitlist *src) {
    lantern_bitlist_init(dst);
    if (!src || src->bit_length == 0) {
        return 0;
    }
    size_t bytes = bitlist_required_bytes(src->bit_length);
    if (bytes == 0) {
        dst->bit_length = 0;
        dst->capacity = 0;
        return 0;
    }
    if (!src->bytes) {
        return -1;
    }
    uint8_t *copy = malloc(bytes);
    if (!copy) {
        return -1;
    }
    memcpy(copy, src->bytes, bytes);
    dst->bytes = copy;
    dst->bit_length = src->bit_length;
    dst->capacity = bytes;
    return 0;
}

static int lantern_state_clone_view(const LanternState *source, LanternState *dest) {
    if (!source || !dest) {
        return -1;
    }
    lantern_state_init(dest);
    dest->config = source->config;
    dest->slot = source->slot;
    dest->latest_block_header = source->latest_block_header;
    dest->latest_justified = source->latest_justified;
    dest->latest_finalized = source->latest_finalized;
    dest->validator_registry_root = source->validator_registry_root;
    dest->historical_roots_offset = source->historical_roots_offset;
    dest->justified_slots_offset = source->justified_slots_offset;

    if (clone_root_list(&dest->historical_block_hashes, &source->historical_block_hashes) != 0) {
        goto error;
    }
    if (clone_root_list(&dest->justification_roots, &source->justification_roots) != 0) {
        goto error;
    }
    if (clone_bitlist(&dest->justified_slots, &source->justified_slots) != 0) {
        goto error;
    }
    if (clone_bitlist(&dest->justification_validators, &source->justification_validators) != 0) {
        goto error;
    }

    if (source->validator_votes && source->validator_votes_len > 0) {
        size_t len = source->validator_votes_len;
        struct lantern_vote_record *records = malloc(len * sizeof(*records));
        if (!records) {
            goto error;
        }
        memcpy(records, source->validator_votes, len * sizeof(*records));
        dest->validator_votes = records;
        dest->validator_votes_len = len;
    }
    if (source->validators && source->validator_count > 0) {
        size_t bytes = source->validator_count * sizeof(*source->validators);
        LanternValidator *validators = malloc(bytes);
        if (!validators) {
            goto error;
        }
        memcpy(validators, source->validators, bytes);
        dest->validators = validators;
        dest->validator_count = source->validator_count;
        dest->validator_capacity = source->validator_count;
    }
    dest->fork_choice = NULL;
    return 0;

error:
    lantern_state_reset(dest);
    return -1;
}


int lantern_root_list_resize(struct lantern_root_list *list, size_t new_length) {
    if (!list) {
        return -1;
    }
    if (new_length == 0) {
        if (list->items && list->length > 0) {
            memset(list->items, 0, list->length * sizeof(*list->items));
        }
        list->length = 0;
        return 0;
    }
    if (ensure_root_capacity(list, new_length) != 0) {
        return -1;
    }
    size_t old_length = list->length;
    if (new_length > old_length) {
        size_t added = new_length - old_length;
        memset(&list->items[old_length], 0, added * sizeof(*list->items));
    } else if (new_length < old_length) {
        size_t removed = old_length - new_length;
        memset(&list->items[new_length], 0, removed * sizeof(*list->items));
    }
    list->length = new_length;
    return 0;
}

static bool lantern_root_is_zero(const LanternRoot *root) {
    if (!root) {
        return false;
    }
    for (size_t i = 0; i < LANTERN_ROOT_SIZE; ++i) {
        if (root->bytes[i] != 0) {
            return false;
        }
    }
    return true;
}

static uint64_t lantern_u64_isqrt(uint64_t value) {
    uint64_t result = 0;
    uint64_t bit = 1ull << 62;
    while (bit > value) {
        bit >>= 2;
    }
    while (bit != 0) {
        if (value >= result + bit) {
            value -= result + bit;
            result = (result >> 1) + bit;
        } else {
            result >>= 1;
        }
        bit >>= 2;
    }
    return result;
}

static bool lantern_is_pronic(uint64_t delta) {
    if (delta == 0) {
        return true;
    }
    uint64_t root = lantern_u64_isqrt(delta);
    uint64_t candidates[3];
    size_t count = 0;
    if (root > 0) {
        candidates[count++] = root - 1;
    }
    candidates[count++] = root;
    if (root < UINT64_MAX) {
        candidates[count++] = root + 1;
    }
    for (size_t i = 0; i < count; ++i) {
        uint64_t a = candidates[i];
        if (a == UINT64_MAX) {
            continue;
        }
        uint64_t b = a + 1;
        if (b == 0) {
            continue;
        }
        if (a > UINT64_MAX / b) {
            continue;
        }
        if (a * b == delta) {
            return true;
        }
    }
    return false;
}

static bool lantern_slot_is_justifiable(uint64_t candidate_slot, uint64_t finalized_slot) {
    if (candidate_slot < finalized_slot) {
        return false;
    }
    uint64_t delta = candidate_slot - finalized_slot;
    if (delta <= 5) {
        return true;
    }
    uint64_t root = lantern_u64_isqrt(delta);
    if (root * root == delta) {
        return true;
    }
    return lantern_is_pronic(delta);
}

static int lantern_root_list_append(struct lantern_root_list *list, const LanternRoot *root) {
    if (!list || !root) {
        return -1;
    }
    if (lantern_root_list_resize(list, list->length + 1) != 0) {
        return -1;
    }
    list->items[list->length - 1] = *root;
    return 0;
}

static int lantern_root_list_drop_front(struct lantern_root_list *list, size_t count) {
    if (!list || count == 0) {
        return 0;
    }
    if (count >= list->length) {
        return lantern_root_list_resize(list, 0);
    }
    size_t remaining = list->length - count;
    memmove(list->items, list->items + count, remaining * sizeof(*list->items));
    memset(list->items + remaining, 0, count * sizeof(*list->items));
    list->length = remaining;
    return 0;
}

static int lantern_bitlist_set_bit(struct lantern_bitlist *list, size_t index, bool value) {
    if (!list) {
        return -1;
    }
    size_t required_bytes = bitlist_required_bytes(index + 1);
    if (ensure_bit_capacity(list, required_bytes) != 0) {
        return -1;
    }
    if (!list->bytes) {
        return -1;
    }
    size_t byte_index = index / 8u;
    if (byte_index >= list->capacity) {
        return -1;
    }
    size_t bit_index = index % 8u;
    uint8_t mask = (uint8_t)(1u << bit_index);
    if (value) {
        list->bytes[byte_index] |= mask;
    } else {
        list->bytes[byte_index] &= (uint8_t)~mask;
    }
    if (index + 1 > list->bit_length) {
        list->bit_length = index + 1;
    }
    return 0;
}

static int lantern_bitlist_get_bit(const struct lantern_bitlist *list, size_t index, bool *out_value) {
    if (!list || !out_value) {
        return -1;
    }
    if (index >= list->bit_length) {
        return -1;
    }
    if (!list->bytes) {
        return -1;
    }
    size_t byte_index = index / 8u;
    size_t bit_index = index % 8u;
    uint8_t mask = (uint8_t)(1u << bit_index);
    *out_value = (list->bytes[byte_index] & mask) != 0;
    return 0;
}

static int lantern_bitlist_append(struct lantern_bitlist *list, bool value) {
    if (!list) {
        return -1;
    }
    size_t new_length = list->bit_length + 1;
    if (lantern_bitlist_resize(list, new_length) != 0) {
        return -1;
    }
    return lantern_bitlist_set_bit(list, new_length - 1, value);
}

static int lantern_bitlist_drop_front(struct lantern_bitlist *list, size_t bits) {
    if (!list || bits == 0) {
        return 0;
    }
    if (bits >= list->bit_length) {
        return lantern_bitlist_resize(list, 0);
    }
    size_t byte_len = bitlist_required_bytes(list->bit_length);
    size_t byte_shift = bits / 8u;
    size_t bit_shift = bits % 8u;
    if (byte_shift > 0) {
        memmove(list->bytes, list->bytes + byte_shift, byte_len - byte_shift);
        memset(list->bytes + (byte_len - byte_shift), 0, byte_shift);
        byte_len -= byte_shift;
    }
    if (bit_shift > 0 && byte_len > 0) {
        uint8_t carry = 0;
        for (size_t i = byte_len; i > 0; --i) {
            size_t idx = i - 1;
            uint8_t current = list->bytes[idx];
            /* Shift right to drop low-order bits, carry in from higher byte. */
            uint8_t next_carry = (uint8_t)(current << (8u - bit_shift));
            list->bytes[idx] = (uint8_t)((current >> bit_shift) | carry);
            carry = next_carry;
        }
    }
    size_t new_length = list->bit_length - bits;
    return lantern_bitlist_resize(list, new_length);
}

bool lantern_state_slot_in_justified_window(const LanternState *state, uint64_t slot) {
    if (!state) {
        return false;
    }
    uint64_t offset = state->justified_slots_offset;
    if (slot < offset) {
        return true;
    }
    uint64_t bit_length = state->justified_slots.bit_length;
    uint64_t window_end = offset + bit_length;
    return slot >= offset && slot < window_end;
}

static bool lantern_state_has_justified_between(
    const LanternState *state,
    uint64_t start_slot,
    uint64_t end_slot) {
    if (!state || end_slot <= start_slot + 1u) {
        return false;
    }
    for (uint64_t slot = start_slot + 1u; slot < end_slot; ++slot) {
        bool bit = false;
        if (lantern_state_get_justified_slot_bit(state, slot, &bit) != 0) {
            return true;
        }
        if (bit) {
            return true;
        }
    }
    return false;
}

/**
 * Check if any slot between start_slot (exclusive) and end_slot (exclusive)
 * is justifiable relative to the finalized_slot.
 *
 * This implements the LeanSpec finalization check (lines 435-439):
 *   if not any(
 *       Slot(slot).is_justifiable_after(self.latest_finalized.slot)
 *       for slot in range(source_slot + 1, target_slot)
 *   ):
 *       latest_finalized = source
 */
static bool has_justifiable_slot_between(
    uint64_t start_slot,
    uint64_t end_slot,
    uint64_t finalized_slot) {
    if (end_slot <= start_slot + 1u) {
        return false;
    }
    for (uint64_t slot = start_slot + 1u; slot < end_slot; ++slot) {
        if (lantern_slot_is_justifiable(slot, finalized_slot)) {
            return true;
        }
    }
    return false;
}

int lantern_state_get_justified_slot_bit(const LanternState *state, uint64_t slot, bool *out_value) {
    if (!state || !out_value) {
        return -1;
    }
    uint64_t offset = state->justified_slots_offset;
    if (slot < offset) {
        *out_value = true;
        return 0;
    }
    if (!lantern_state_slot_in_justified_window(state, slot)) {
        *out_value = false;
        if (finalization_trace_enabled()) {
            lantern_log_debug(
                "state",
                &(const struct lantern_log_metadata){.has_slot = true, .slot = state->slot},
                "justification trace read slot=%" PRIu64 " value=false (outside window offset=%" PRIu64 ")",
                slot,
                state->justified_slots_offset);
        }
        return 0;
    }
    uint64_t relative = slot - offset;
    if (relative > SIZE_MAX) {
        return -1;
    }
    int rc = lantern_bitlist_get_bit(&state->justified_slots, (size_t)relative, out_value);
    if (rc == 0 && finalization_trace_enabled()) {
        lantern_log_debug(
            "state",
            &(const struct lantern_log_metadata){.has_slot = true, .slot = state->slot},
            "justification trace read slot=%" PRIu64 " value=%s offset=%" PRIu64,
            slot,
            *out_value ? "true" : "false",
            state->justified_slots_offset);
    }
    return rc;
}

static int lantern_state_ensure_justified_slot_index(LanternState *state, uint64_t slot, size_t *out_index) {
    if (!state) {
        return -1;
    }
    size_t limit = LANTERN_HISTORICAL_ROOTS_LIMIT;
    if (limit == 0) {
        return -1;
    }
    uint64_t offset = state->justified_slots_offset;
    if (slot < offset) {
        return 1;
    }
    uint64_t relative = slot - offset;
    if (relative >= limit) {
        uint64_t drop = (relative - limit) + 1u;
        if (drop > SIZE_MAX) {
            return -1;
        }
        if (lantern_bitlist_drop_front(&state->justified_slots, (size_t)drop) != 0) {
            return -1;
        }
        state->justified_slots_offset += drop;
        offset += drop;
        relative = slot >= offset ? slot - offset : 0;
    }
    if (relative > SIZE_MAX) {
        return -1;
    }
    size_t desired_length = (size_t)relative + 1u;
    if (desired_length > state->justified_slots.bit_length) {
        if (lantern_bitlist_ensure_length(&state->justified_slots, desired_length) != 0) {
            return -1;
        }
    }
    if (out_index) {
        *out_index = (size_t)relative;
    }
    return 0;
}

static int lantern_state_set_justified_slot_bit(LanternState *state, uint64_t slot, bool value) {
    if (!state) {
        return -1;
    }
    if (slot < state->justified_slots_offset) {
        return 0;
    }
    if (slot > SIZE_MAX) {
        return -1;
    }
    size_t index = 0;
    int rc = lantern_state_ensure_justified_slot_index(state, slot, &index);
    if (rc > 0) {
        return 0;
    }
    if (rc != 0) {
        return -1;
    }
    return lantern_bitlist_set_bit(&state->justified_slots, index, value);
}

static int lantern_state_append_historical_root(LanternState *state, const LanternRoot *root) {
    if (!state || !root) {
        return -1;
    }
    if (state->historical_block_hashes.length >= LANTERN_HISTORICAL_ROOTS_LIMIT) {
        if (state->historical_block_hashes.length == 0) {
            return -1;
        }
        if (lantern_root_list_drop_front(&state->historical_block_hashes, 1) != 0) {
            return -1;
        }
        state->historical_roots_offset += 1u;
    }
    return lantern_root_list_append(&state->historical_block_hashes, root);
}

static int lantern_bitlist_ensure_length(struct lantern_bitlist *list, size_t bit_length) {
    if (!list) {
        return -1;
    }
    if (bit_length <= list->bit_length) {
        return 0;
    }
    size_t original = list->bit_length;
    if (lantern_bitlist_resize(list, bit_length) != 0) {
        return -1;
    }
    for (size_t i = original; i < bit_length; ++i) {
        if (lantern_bitlist_set_bit(list, i, false) != 0) {
            return -1;
        }
    }
    return 0;
}

static void lantern_vote_record_reset(struct lantern_vote_record *record) {
    if (!record) {
        return;
    }
    memset(record, 0, sizeof(*record));
}

static bool lantern_checkpoint_equal(const LanternCheckpoint *a, const LanternCheckpoint *b) {
    if (!a || !b) {
        return false;
    }
    if (a->slot != b->slot) {
        return false;
    }
    return memcmp(a->root.bytes, b->root.bytes, LANTERN_ROOT_SIZE) == 0;
}

static bool lantern_votes_equal(const LanternVote *a, const LanternVote *b) {
    if (!a || !b) {
        return false;
    }
    if (a->slot != b->slot) {
        return false;
    }
    if (!lantern_checkpoint_equal(&a->head, &b->head)) {
        return false;
    }
    if (!lantern_checkpoint_equal(&a->target, &b->target)) {
        return false;
    }
    if (!lantern_checkpoint_equal(&a->source, &b->source)) {
        return false;
    }
    return true;
}

static size_t lantern_quorum_threshold(uint64_t validator_count) {
    uint64_t threshold = lantern_consensus_quorum_threshold(validator_count);
    if (threshold > SIZE_MAX) {
        return SIZE_MAX;
    }
    return (size_t)threshold;
}

/* === Justification vote tracking helpers === */

/**
 * Find the index of a root in the justification_roots list.
 * Returns -1 if not found, otherwise returns the index.
 */
static int lantern_state_find_justification_root_index(
    const LanternState *state,
    const LanternRoot *root) {
    if (!state || !root) {
        return -1;
    }
    for (size_t i = 0; i < state->justification_roots.length; ++i) {
        if (memcmp(state->justification_roots.items[i].bytes, root->bytes, LANTERN_ROOT_SIZE) == 0) {
            return (int)i;
        }
    }
    return -1;
}

/**
 * Add a new root to track justification votes for.
 * Inserts the root in lexicographically sorted order to match LeanSpec behavior.
 * Initializes all validator vote bits to false.
 * Returns the index of the new root, or -1 on error.
 */
static int lantern_state_add_justification_root(
    LanternState *state,
    const LanternRoot *root,
    size_t validator_count) {
    if (!state || !root || validator_count == 0) {
        return -1;
    }

    /* Find the insertion position to maintain sorted order (lexicographically by root bytes) */
    size_t insert_pos = 0;
    while (insert_pos < state->justification_roots.length &&
           memcmp(state->justification_roots.items[insert_pos].bytes, root->bytes, LANTERN_ROOT_SIZE) < 0) {
        insert_pos++;
    }

    /* First, expand the root list by appending (we'll shift elements afterward) */
    if (lantern_root_list_append(&state->justification_roots, root) != 0) {
        return -1;
    }

    /* Expand justification_validators bitlist by validator_count bits */
    size_t old_root_count = state->justification_roots.length - 1;
    size_t new_bit_length = state->justification_validators.bit_length + validator_count;
    if (lantern_bitlist_ensure_length(&state->justification_validators, new_bit_length) != 0) {
        /* Rollback root addition */
        state->justification_roots.length--;
        return -1;
    }

    /* If inserting at the end, we're done - no shifting needed */
    if (insert_pos == old_root_count) {
        return (int)insert_pos;
    }

    /* Shift roots from insert_pos to make room for the new root.
     * The new root is currently at the end, we need to move it to insert_pos. */
    LanternRoot temp_root = state->justification_roots.items[old_root_count];
    for (size_t i = old_root_count; i > insert_pos; --i) {
        state->justification_roots.items[i] = state->justification_roots.items[i - 1];
    }
    state->justification_roots.items[insert_pos] = temp_root;

    /* Shift validator bits to match the new root order.
     * We need to move bits from [insert_pos * validator_count] onward.
     * The bits for the new root (currently at the end) should move to insert_pos. */
    size_t bits_to_shift = (old_root_count - insert_pos) * validator_count;
    if (bits_to_shift > 0) {
        /* Create a temporary buffer to hold the bits we need to shift */
        size_t shift_start_bit = insert_pos * validator_count;
        size_t new_root_start_bit = old_root_count * validator_count;

        /* Copy existing bits from insert_pos onward to temporary storage */
        size_t temp_bytes_needed = (bits_to_shift + 7) / 8;
        uint8_t *temp_bits = (uint8_t *)calloc(temp_bytes_needed, 1);
        if (!temp_bits) {
            /* Can't shift bits - this is a critical error but we'll proceed with unsorted */
            return (int)insert_pos;
        }

        /* Extract bits from [shift_start_bit, new_root_start_bit) */
        for (size_t i = 0; i < bits_to_shift; ++i) {
            bool bit_value = false;
            if (lantern_bitlist_get_bit(&state->justification_validators, shift_start_bit + i, &bit_value) == 0 && bit_value) {
                temp_bits[i / 8] |= (uint8_t)(1u << (i % 8));
            }
        }

        /* Clear the region we're about to rewrite: [shift_start_bit, new_bit_length) */
        for (size_t i = shift_start_bit; i < new_bit_length; ++i) {
            lantern_bitlist_set_bit(&state->justification_validators, i, false);
        }

        /* Write zeros at insert_pos (validator_count bits) - new root votes are all false */
        /* (already done by clearing above) */

        /* Write shifted bits starting at (insert_pos + 1) * validator_count */
        size_t dest_start = (insert_pos + 1) * validator_count;
        for (size_t i = 0; i < bits_to_shift; ++i) {
            bool bit_value = (temp_bits[i / 8] & (1u << (i % 8))) != 0;
            if (bit_value) {
                lantern_bitlist_set_bit(&state->justification_validators, dest_start + i, true);
            }
        }

        free(temp_bits);
    }

    return (int)insert_pos;
}

/**
 * Get whether a validator has voted for a specific justification root.
 */
static int lantern_state_get_justification_vote(
    const LanternState *state,
    int root_index,
    size_t validator_id,
    size_t validator_count,
    bool *out_value) {
    if (!state || !out_value || root_index < 0 || validator_count == 0) {
        return -1;
    }
    if (validator_id >= validator_count) {
        return -1;
    }
    size_t bit_index = (size_t)root_index * validator_count + validator_id;
    return lantern_bitlist_get_bit(&state->justification_validators, bit_index, out_value);
}

/**
 * Record a validator's vote for a justification root.
 */
static int lantern_state_set_justification_vote(
    LanternState *state,
    int root_index,
    size_t validator_id,
    size_t validator_count,
    bool value) {
    if (!state || root_index < 0 || validator_count == 0) {
        return -1;
    }
    if (validator_id >= validator_count) {
        return -1;
    }
    size_t bit_index = (size_t)root_index * validator_count + validator_id;
    return lantern_bitlist_set_bit(&state->justification_validators, bit_index, value);
}

/**
 * Count the number of validators who have voted for a justification root.
 */
static size_t lantern_state_count_justification_votes(
    const LanternState *state,
    int root_index,
    size_t validator_count) {
    if (!state || root_index < 0 || validator_count == 0) {
        return 0;
    }
    size_t count = 0;
    for (size_t i = 0; i < validator_count; ++i) {
        bool voted = false;
        if (lantern_state_get_justification_vote(state, root_index, i, validator_count, &voted) == 0 && voted) {
            count++;
        }
    }
    return count;
}

/**
 * Remove a root from justification tracking after it has been justified.
 * This shifts all remaining roots and their vote bits.
 */
static int lantern_state_remove_justification_root(
    LanternState *state,
    int root_index,
    size_t validator_count) {
    if (!state || root_index < 0 || validator_count == 0) {
        return -1;
    }
    size_t idx = (size_t)root_index;
    if (idx >= state->justification_roots.length) {
        return -1;
    }
    
    /* Remove the root from the list by shifting */
    size_t remaining_roots = state->justification_roots.length - idx - 1;
    if (remaining_roots > 0) {
        memmove(
            &state->justification_roots.items[idx],
            &state->justification_roots.items[idx + 1],
            remaining_roots * sizeof(LanternRoot));
    }
    state->justification_roots.length--;
    
    /* Remove the validator vote bits for this root by shifting */
    size_t start_bit = idx * validator_count;
    size_t bits_to_remove = validator_count;
    size_t total_bits = state->justification_validators.bit_length;
    
    if (start_bit + bits_to_remove <= total_bits) {
        /* Shift all bits after this root's section */
        size_t remaining_bits = total_bits - start_bit - bits_to_remove;
        for (size_t i = 0; i < remaining_bits; ++i) {
            bool bit = false;
            if (lantern_bitlist_get_bit(&state->justification_validators, start_bit + bits_to_remove + i, &bit) == 0) {
                lantern_bitlist_set_bit(&state->justification_validators, start_bit + i, bit);
            }
        }
        /* Resize to remove the extra bits */
        lantern_bitlist_resize(&state->justification_validators, total_bits - bits_to_remove);
    }
    
    return 0;
}

static int lantern_state_find_latest_slot_for_root(
    const LanternState *state,
    const LanternRoot *root,
    uint64_t start_slot,
    uint64_t *out_slot) {
    if (!state || !root || !out_slot) {
        return -1;
    }
    size_t length = state->historical_block_hashes.length;
    if (length == 0) {
        return 1;
    }
    uint64_t offset = state->historical_roots_offset;
    uint64_t end_slot = offset + (uint64_t)length - 1u;
    if (start_slot > end_slot) {
        return 1;
    }
    size_t start_index = 0;
    if (start_slot > offset) {
        uint64_t diff = start_slot - offset;
        if (diff > SIZE_MAX) {
            return -1;
        }
        if ((size_t)diff >= length) {
            return 1;
        }
        start_index = (size_t)diff;
    }
    for (size_t i = length; i-- > start_index;) {
        if (memcmp(state->historical_block_hashes.items[i].bytes, root->bytes, LANTERN_ROOT_SIZE) == 0) {
            *out_slot = offset + (uint64_t)i;
            return 0;
        }
    }
    return 1;
}

static int lantern_state_prune_justification_roots(
    LanternState *state,
    uint64_t base_finalized_slot,
    uint64_t finalized_slot,
    size_t validator_count,
    const struct lantern_log_metadata *meta) {
    if (!state || validator_count == 0) {
        return -1;
    }
    if (state->justification_roots.length == 0) {
        return 0;
    }
    if (base_finalized_slot == UINT64_MAX) {
        return -1;
    }
    uint64_t start_slot = base_finalized_slot + 1u;
    for (size_t i = state->justification_roots.length; i-- > 0;) {
        uint64_t latest_slot = 0;
        int find_rc = lantern_state_find_latest_slot_for_root(
            state,
            &state->justification_roots.items[i],
            start_slot,
            &latest_slot);
        if (find_rc != 0) {
            if (meta) {
                lantern_log_warn(
                    "state",
                    meta,
                    "justification root missing from history during pruning");
            }
            return -1;
        }
        if (latest_slot <= finalized_slot) {
            if (lantern_state_remove_justification_root(state, (int)i, validator_count) != 0) {
                if (meta) {
                    lantern_log_warn(
                        "state",
                        meta,
                        "failed to prune justification root at slot %" PRIu64,
                        latest_slot);
                }
                return -1;
            }
        }
    }
    return 0;
}

int lantern_state_prepare_validator_votes(LanternState *state, uint64_t validator_count) {
    if (!state || validator_count == 0) {
        return -1;
    }
    if (validator_count > (uint64_t)LANTERN_VALIDATOR_REGISTRY_LIMIT) {
        return -1;
    }
    if (validator_count > SIZE_MAX) {
        return -1;
    }
    size_t count = (size_t)validator_count;
    if (state->validator_votes && state->validator_votes_len != count) {
        free(state->validator_votes);
        state->validator_votes = NULL;
        state->validator_votes_len = 0;
    }
    if (!state->validator_votes) {
        struct lantern_vote_record *records = calloc(count, sizeof(*records));
        if (!records) {
            return -1;
        }
        state->validator_votes = records;
        state->validator_votes_len = count;
    } else {
        for (size_t i = 0; i < count; ++i) {
            lantern_vote_record_reset(&state->validator_votes[i]);
        }
    }
    return 0;
}

size_t lantern_state_validator_capacity(const LanternState *state) {
    if (!state || !state->validator_votes) {
        return 0;
    }
    return state->validator_votes_len;
}

bool lantern_state_validator_has_vote(const LanternState *state, size_t index) {
    if (!state || !state->validator_votes || index >= state->validator_votes_len) {
        return false;
    }
    return state->validator_votes[index].has_vote;
}

int lantern_state_get_signed_validator_vote(
    const LanternState *state,
    size_t index,
    LanternSignedVote *out_vote) {
    if (!state || !state->validator_votes || index >= state->validator_votes_len || !out_vote) {
        return -1;
    }
    const struct lantern_vote_record *record = &state->validator_votes[index];
    if (!record->has_vote) {
        return -1;
    }
    memset(out_vote, 0, sizeof(*out_vote));
    out_vote->data = record->vote;
    out_vote->data.validator_id = (uint64_t)index;
    if (record->has_signature) {
        out_vote->signature = record->signature;
    }
    return 0;
}

int lantern_state_get_validator_vote(const LanternState *state, size_t index, LanternVote *out_vote) {
    if (!out_vote) {
        return -1;
    }
    LanternSignedVote signed_vote;
    if (lantern_state_get_signed_validator_vote(state, index, &signed_vote) != 0) {
        return -1;
    }
    *out_vote = signed_vote.data;
    return 0;
}

int lantern_state_set_signed_validator_vote(
    LanternState *state,
    size_t index,
    const LanternSignedVote *vote) {
    if (!state || !state->validator_votes || index >= state->validator_votes_len || !vote) {
        return -1;
    }
    struct lantern_vote_record *record = &state->validator_votes[index];
    LanternVote previous_vote = record->vote;
    LanternSignature previous_signature = record->signature;
    bool previous_has_signature = record->has_signature;
    record->vote = vote->data;
    record->vote.validator_id = (uint64_t)index;
    record->has_vote = true;
    if (!signature_is_zero(&vote->signature)) {
        record->signature = vote->signature;
        record->has_signature = true;
    } else if (previous_has_signature && lantern_votes_equal(&previous_vote, &record->vote)) {
        record->signature = previous_signature;
        record->has_signature = true;
    } else {
        memset(&record->signature, 0, sizeof(record->signature));
        record->has_signature = false;
    }
    return 0;
}

int lantern_state_set_validator_vote(LanternState *state, size_t index, const LanternVote *vote) {
    if (!vote) {
        return -1;
    }
    LanternSignedVote signed_vote;
    memset(&signed_vote, 0, sizeof(signed_vote));
    signed_vote.data = *vote;
    return lantern_state_set_signed_validator_vote(state, index, &signed_vote);
}

void lantern_state_clear_validator_vote(LanternState *state, size_t index) {
    if (!state || !state->validator_votes || index >= state->validator_votes_len) {
        return;
    }
    lantern_vote_record_reset(&state->validator_votes[index]);
}

int lantern_state_set_validator_pubkeys(LanternState *state, const uint8_t *pubkeys, size_t count) {
    if (!state) {
        return -1;
    }
    if (count > (size_t)LANTERN_VALIDATOR_REGISTRY_LIMIT) {
        return -1;
    }
    if (count > 0 && !pubkeys) {
        return -1;
    }
    if (count > 0 && count > SIZE_MAX / sizeof(*state->validators)) {
        return -1;
    }
    LanternRoot registry_root;
    lantern_root_zero(&registry_root);
    if (count > 0) {
        if (lantern_hash_tree_root_validators(pubkeys, count, &registry_root) != 0) {
            return -1;
        }
    }
    LanternValidator *items = NULL;
    if (count > 0) {
        items = malloc(count * sizeof(*items));
        if (!items) {
            return -1;
        }
        for (size_t i = 0; i < count; ++i) {
            memcpy(
                items[i].pubkey,
                pubkeys + (i * LANTERN_VALIDATOR_PUBKEY_SIZE),
                LANTERN_VALIDATOR_PUBKEY_SIZE);
            items[i].index = (uint64_t)i;
        }
    }
    if (state->validators) {
        free(state->validators);
    }
    state->validators = items;
    state->validator_count = count;
    state->validator_capacity = count;
    state->validator_registry_root = registry_root;
    return 0;
}

size_t lantern_state_validator_count(const LanternState *state) {
    if (!state || !state->validators) {
        return 0;
    }
    return state->validator_count;
}

const uint8_t *lantern_state_validator_pubkey(const LanternState *state, size_t index) {
    if (!state || !state->validators || index >= state->validator_count) {
        return NULL;
    }
    return state->validators[index].pubkey;
}

static void lantern_root_zero(LanternRoot *root) {
    if (root) {
        memset(root->bytes, 0, LANTERN_ROOT_SIZE);
    }
}

void lantern_state_init(LanternState *state) {
    if (!state) {
        return;
    }
    memset(state, 0, sizeof(*state));
    lantern_root_list_init(&state->historical_block_hashes);
    lantern_bitlist_init(&state->justified_slots);
    lantern_root_list_init(&state->justification_roots);
    lantern_bitlist_init(&state->justification_validators);
}

void lantern_state_reset(LanternState *state) {
    if (!state) {
        return;
    }
    struct lantern_fork_choice *attached = state->fork_choice;
    lantern_root_list_reset(&state->historical_block_hashes);
    lantern_bitlist_reset(&state->justified_slots);
    lantern_root_list_reset(&state->justification_roots);
    lantern_bitlist_reset(&state->justification_validators);
    if (state->validator_votes) {
        free(state->validator_votes);
        state->validator_votes = NULL;
        state->validator_votes_len = 0;
    }
    if (state->validators) {
        free(state->validators);
        state->validators = NULL;
        state->validator_count = 0;
        state->validator_capacity = 0;
    }
    memset(state, 0, sizeof(*state));
    lantern_root_list_init(&state->historical_block_hashes);
    lantern_bitlist_init(&state->justified_slots);
    lantern_root_list_init(&state->justification_roots);
    lantern_bitlist_init(&state->justification_validators);
    state->fork_choice = attached;
}

void lantern_state_attach_fork_choice(LanternState *state, struct lantern_fork_choice *fork_choice) {
    if (!state) {
        return;
    }
    state->fork_choice = fork_choice;
}

int lantern_state_generate_genesis(LanternState *state, uint64_t genesis_time, uint64_t num_validators) {
    if (!state || num_validators == 0) {
        return -1;
    }
    if (num_validators > (uint64_t)LANTERN_VALIDATOR_REGISTRY_LIMIT) {
        return -1;
    }
    lantern_state_reset(state);
    if (lantern_state_prepare_validator_votes(state, num_validators) != 0) {
        lantern_state_reset(state);
        return -1;
    }
    state->config.num_validators = num_validators;
    state->config.genesis_time = genesis_time;
    state->slot = 0;

    lantern_root_zero(&state->latest_block_header.parent_root);
    lantern_root_zero(&state->latest_block_header.state_root);
    state->latest_block_header.slot = 0;
    state->latest_block_header.proposer_index = 0;

    LanternBlockBody empty_body;
    lantern_block_body_init(&empty_body);
    LanternRoot body_root;
    if (lantern_hash_tree_root_block_body(&empty_body, &body_root) != 0) {
        lantern_block_body_reset(&empty_body);
        lantern_state_reset(state);
        return -1;
    }
    state->latest_block_header.body_root = body_root;
    lantern_block_body_reset(&empty_body);

    lantern_root_zero(&state->latest_justified.root);
    state->latest_justified.slot = 0;
    lantern_root_zero(&state->latest_finalized.root);
    state->latest_finalized.slot = 0;
    if (state->latest_finalized.slot != UINT64_MAX) {
        if (state->latest_finalized.slot > UINT64_MAX - 1u) {
            lantern_state_reset(state);
            return -1;
        }
        state->justified_slots_offset = state->latest_finalized.slot + 1u;
    }

    return 0;
}

int lantern_state_process_slot(LanternState *state) {
    if (!state) {
        return -1;
    }
    if (lantern_root_is_zero(&state->latest_block_header.state_root)) {
        LanternRoot computed;
        if (lantern_hash_tree_root_state(state, &computed) != 0) {
            return -1;
        }
        state->latest_block_header.state_root = computed;
    }
    return 0;
}

int lantern_state_process_slots(LanternState *state, uint64_t target_slot) {
    if (!state) {
        return -1;
    }
    if (target_slot <= state->slot) {
        const struct lantern_log_metadata meta = {
            .has_slot = true,
            .slot = state->slot,
        };
        lantern_log_warn(
            "state",
            &meta,
            "process slots target=%" PRIu64 " must be in the future (current=%" PRIu64 ")",
            target_slot,
            state->slot);
        return -1;
    }
    while (state->slot < target_slot) {
        if (lantern_state_process_slot(state) != 0) {
            return -1;
        }
        if (state->slot == UINT64_MAX) {
            return -1;
        }
        state->slot += 1;
        lantern_log_debug(
            "state",
            &(const struct lantern_log_metadata){
                .has_slot = true,
                .slot = state->slot},
            "slot advanced");
    }
    return 0;
}







int lantern_state_mark_justified_slot(LanternState *state, uint64_t slot) {
    if (!state) {
        return -1;
    }
    if (slot > SIZE_MAX) {
        return -1;
    }
    int rc = lantern_state_set_justified_slot_bit(state, slot, true);
    if (rc == 0 && finalization_trace_enabled()) {
        lantern_log_debug(
            "state",
            &(const struct lantern_log_metadata){.has_slot = true, .slot = state->slot},
            "justification trace mark slot=%" PRIu64 " offset=%" PRIu64 " window=%zu",
            slot,
            state->justified_slots_offset,
            state->justified_slots.bit_length);
    }
    return rc;
}

int lantern_state_process_block_header(LanternState *state, const LanternBlock *block) {
    if (!state || !block) {
        return -1;
    }
    const struct lantern_log_metadata meta = {
        .has_slot = true,
        .slot = block->slot,
    };
    if (block->slot != state->slot) {
        lantern_log_warn(
            "state",
            &meta,
            "header rejected: block slot %" PRIu64 " expected state slot %" PRIu64,
            block->slot,
            state->slot);
        return -1;
    }
    if (block->slot <= state->latest_block_header.slot) {
        const char *reason = block->slot == state->latest_block_header.slot ? "duplicate" : "stale";
        lantern_log_warn(
            "state",
            &meta,
            "header rejected: %s slot %" PRIu64 " latest %" PRIu64,
            reason,
            block->slot,
            state->latest_block_header.slot);
        return -1;
    }
    uint64_t expected_proposer = 0;
    if (lantern_proposer_for_slot(block->slot, state->config.num_validators, &expected_proposer) != 0) {
        return -1;
    }
    if (block->proposer_index != expected_proposer) {
        lantern_log_warn(
            "state",
            &meta,
            "header rejected: proposer %" PRIu64 " expected %" PRIu64,
            block->proposer_index,
            expected_proposer);
        return -1;
    }

    LanternRoot latest_header_root;
    if (lantern_hash_tree_root_block_header(&state->latest_block_header, &latest_header_root) != 0) {
        return -1;
    }
    if (memcmp(block->parent_root.bytes, latest_header_root.bytes, LANTERN_ROOT_SIZE) != 0) {
        char expected_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
        char received_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
        if (lantern_bytes_to_hex(
                latest_header_root.bytes,
                LANTERN_ROOT_SIZE,
                expected_hex,
                sizeof(expected_hex),
                1)
            != 0) {
            expected_hex[0] = '\0';
        }
        if (lantern_bytes_to_hex(
                block->parent_root.bytes,
                LANTERN_ROOT_SIZE,
                received_hex,
                sizeof(received_hex),
                1)
            != 0) {
            received_hex[0] = '\0';
        }
        lantern_log_warn(
            "state",
            &meta,
            "header rejected: parent mismatch expected=%s received=%s",
            expected_hex[0] ? expected_hex : "0x0",
            received_hex[0] ? received_hex : "0x0");
        return -1;
    }

    if (state->latest_block_header.slot == 0) {
        state->latest_justified.root = block->parent_root;
        state->latest_finalized.root = block->parent_root;
    }

    uint64_t parent_slot = state->latest_block_header.slot;
    if (lantern_state_append_historical_root(state, &block->parent_root) != 0) {
        return -1;
    }
    if (lantern_state_set_justified_slot_bit(state, parent_slot, parent_slot == 0) != 0) {
        return -1;
    }

    uint64_t delta = block->slot - parent_slot;
    if (delta > 1) {
        LanternRoot zero_root;
        lantern_root_zero(&zero_root);
        for (uint64_t i = 0; i < delta - 1; ++i) {
            uint64_t slot = parent_slot + 1 + i;
            if (lantern_state_append_historical_root(state, &zero_root) != 0) {
                return -1;
            }
            if (lantern_state_set_justified_slot_bit(state, slot, false) != 0) {
                return -1;
            }
        }
    }

    LanternRoot body_root;
    if (lantern_hash_tree_root_block_body(&block->body, &body_root) != 0) {
        return -1;
    }
    state->latest_block_header.slot = block->slot;
    state->latest_block_header.proposer_index = block->proposer_index;
    state->latest_block_header.parent_root = block->parent_root;
    state->latest_block_header.body_root = body_root;
    lantern_root_zero(&state->latest_block_header.state_root);

    return 0;
}

static int lantern_state_process_attestations_internal(
    LanternState *state,
    const LanternAttestations *attestations,
    const LanternSignatureList *signatures,
    bool apply_consensus_effects) {
    if (!state || !attestations) {
        return -1;
    }
    uint64_t validator_count_u64 = state->config.num_validators;
    if (validator_count_u64 == 0 || validator_count_u64 > SIZE_MAX) {
        return -1;
    }
    size_t validator_count = (size_t)validator_count_u64;
    bool trace_finalization = finalization_trace_enabled();
    const struct lantern_log_metadata meta = {
        .has_slot = true,
        .slot = state->slot,
    };
    if (!state->validator_votes || state->validator_votes_len != validator_count) {
        return -1;
    }
    if (attestations->length > LANTERN_MAX_ATTESTATIONS) {
        return -1;
    }
    for (size_t i = 0; i < state->justification_roots.length; ++i) {
        if (lantern_root_is_zero(&state->justification_roots.items[i])) {
            lantern_log_warn(
                "state",
                &meta,
                "zero hash is not allowed in justification roots");
            return -1;
        }
    }

    LanternCheckpoint latest_justified = state->latest_justified;
    LanternCheckpoint latest_finalized = state->latest_finalized;
    uint64_t base_finalized_slot = latest_finalized.slot;
    double att_batch_start = lantern_time_now_seconds();
    size_t att_attempted = 0;
    bool finalization_attempted = false;


    for (size_t i = 0; i < attestations->length; ++i) {
        const LanternVote *vote = &attestations->data[i];
        const LanternSignature *signature = NULL;
        if (signatures && signatures->data && i < signatures->length) {
            signature = &signatures->data[i];
        }
        att_attempted += 1;
        double att_validation_start = lantern_time_now_seconds();
        if (vote->validator_id >= validator_count) {
            lantern_log_warn(
                "state",
                &meta,
                "attestation rejected: validator %" PRIu64 " out of range (validators=%" PRIu64 ")",
                vote->validator_id,
                (uint64_t)validator_count);
            record_attestation_validation_metric(att_validation_start, false);
            continue;
        }
        if (vote->target.slot <= vote->source.slot) {
            /* LeanSpec: silently skip if target <= source (state.py:406) */
            continue;
        }
        if (vote->source.slot > SIZE_MAX || vote->target.slot > SIZE_MAX) {
            lantern_log_warn(
                "state",
                &meta,
                "attestation rejected: slot range (%" PRIu64 ", %" PRIu64 ") exceeds size_t capacity",
                vote->source.slot,
                vote->target.slot);
            record_attestation_validation_metric(att_validation_start, false);
            continue;
        }
        if (!lantern_state_slot_in_justified_window(state, vote->source.slot)) {
            /* LeanSpec: silently skip attestations with source outside justified window */
            if (trace_finalization) {
                lantern_log_debug(
                    "state",
                    &meta,
                    "finalization trace skip source_outside_window source_slot=%" PRIu64
                    " window=[%" PRIu64 ",%" PRIu64 ")",
                    vote->source.slot,
                    state->justified_slots_offset,
                    state->justified_slots_offset + state->justified_slots.bit_length);
            }
            continue;
        }
        bool source_is_justified = false;
        if (lantern_state_get_justified_slot_bit(state, vote->source.slot, &source_is_justified) != 0) {
            /* LeanSpec: silently skip if we can't read source justified status */
            if (trace_finalization) {
                lantern_log_debug(
                    "state",
                    &meta,
                    "finalization trace skip source_bit_unreadable source_slot=%" PRIu64,
                    vote->source.slot);
            }
            continue;
        }
        if (!source_is_justified) {
            /* LeanSpec: silently skip attestations with unjustified source (state.py:386) */
            if (trace_finalization) {
                lantern_log_debug(
                    "state",
                    &meta,
                    "finalization trace skip source_unjustified source_slot=%" PRIu64,
                    vote->source.slot);
            }
            continue;
        }

        if (lantern_root_is_zero(&vote->source.root) || lantern_root_is_zero(&vote->target.root)) {
            if (trace_finalization) {
                lantern_log_debug(
                    "state",
                    &meta,
                    "finalization trace skip zero_hash_vote source_slot=%" PRIu64 " target_slot=%" PRIu64,
                    vote->source.slot,
                    vote->target.slot);
            }
            continue;
        }

        /* LeanSpec: skip if either source or target root mismatches history (state.py:398-402). */
        bool source_matches = false;
        size_t source_slot_idx = (size_t)vote->source.slot;
        if (source_slot_idx < state->historical_block_hashes.length) {
            source_matches = memcmp(
                vote->source.root.bytes,
                state->historical_block_hashes.items[source_slot_idx].bytes,
                LANTERN_ROOT_SIZE) == 0;
        }

        bool target_matches = false;
        size_t target_slot_idx = (size_t)vote->target.slot;
        if (target_slot_idx < state->historical_block_hashes.length) {
            target_matches = memcmp(
                vote->target.root.bytes,
                state->historical_block_hashes.items[target_slot_idx].bytes,
                LANTERN_ROOT_SIZE) == 0;
        }

        if (!source_matches || !target_matches) {
            if (trace_finalization) {
                lantern_log_debug(
                    "state",
                    &meta,
                    "finalization trace skip roots_mismatch source_slot=%" PRIu64 " target_slot=%" PRIu64,
                    vote->source.slot,
                    vote->target.slot);
            }
            continue;
        }

        if (trace_finalization) {
            lantern_log_debug(
                "state",
                &meta,
                "finalization trace validator=%" PRIu64 " vote_slot=%" PRIu64 " source_slot=%" PRIu64
                " target_slot=%" PRIu64,
                vote->validator_id,
                vote->slot,
                vote->source.slot,
                vote->target.slot);
        }
        bool target_is_justified = false;
        if (lantern_state_slot_in_justified_window(state, vote->target.slot)) {
            if (lantern_state_get_justified_slot_bit(state, vote->target.slot, &target_is_justified) != 0) {
                /* LeanSpec: silently skip if we can't read target justified status */
                if (trace_finalization) {
                    lantern_log_debug(
                        "state",
                        &meta,
                        "finalization trace skip target_bit_unreadable target_slot=%" PRIu64,
                        vote->target.slot);
                }
                continue;
            }
        }
        LanternSignedVote stored_vote;
        memset(&stored_vote, 0, sizeof(stored_vote));
        stored_vote.data = *vote;
        if (signature) {
            stored_vote.signature = *signature;
        }
        if (lantern_state_set_signed_validator_vote(state, (size_t)vote->validator_id, &stored_vote) != 0) {
            record_attestation_validation_metric(att_validation_start, false);
            return -1;
        }

        if (!apply_consensus_effects) {
            record_attestation_validation_metric(att_validation_start, true);
            continue;
        }

        /* Skip if target is already justified (leanSpec line 394) */
        if (target_is_justified) {
            if (trace_finalization) {
                lantern_log_debug(
                    "state",
                    &meta,
                    "finalization trace skip target_already_justified target_slot=%" PRIu64,
                    vote->target.slot);
            }
            record_attestation_validation_metric(att_validation_start, true);
            continue;
        }

        /* Target slot must be justifiable after the latest finalized slot (leanSpec line 410) */
        if (!lantern_slot_is_justifiable(vote->target.slot, latest_finalized.slot)) {
            if (trace_finalization) {
                lantern_log_debug(
                    "state",
                    &meta,
                    "finalization trace skip non-justifiable target_slot=%" PRIu64 " finalized=%" PRIu64,
                    vote->target.slot,
                    latest_finalized.slot);
            }
            record_attestation_validation_metric(att_validation_start, true);
            continue;
        }

        /* Track vote for justification - find or add the target root */
        int root_idx = lantern_state_find_justification_root_index(state, &vote->target.root);
        if (root_idx < 0) {
            /* New target root - add to tracking */
            root_idx = lantern_state_add_justification_root(state, &vote->target.root, validator_count);
            if (root_idx < 0) {
                lantern_log_warn(
                    "state",
                    &meta,
                    "failed to add justification root for slot %" PRIu64,
                    vote->target.slot);
                record_attestation_validation_metric(att_validation_start, false);
                continue;
            }
            if (trace_finalization) {
                lantern_log_debug(
                    "state",
                    &meta,
                    "finalization trace added justification root for target_slot=%" PRIu64 " root_idx=%d",
                    vote->target.slot,
                    root_idx);
            }
        }

        /* Check if this validator already voted for this target */
        bool already_voted = false;
        if (lantern_state_get_justification_vote(state, root_idx, (size_t)vote->validator_id, validator_count, &already_voted) != 0) {
            record_attestation_validation_metric(att_validation_start, false);
            continue;
        }

        /* Record the validator's vote if they haven't voted yet */
        if (!already_voted) {
            if (lantern_state_set_justification_vote(state, root_idx, (size_t)vote->validator_id, validator_count, true) != 0) {
                record_attestation_validation_metric(att_validation_start, false);
                continue;
            }
        }

        /* Count total votes for this target */
        size_t vote_count = lantern_state_count_justification_votes(state, root_idx, validator_count);
        size_t quorum = lantern_quorum_threshold(validator_count_u64);

        if (trace_finalization) {
            lantern_log_debug(
                "state",
                &meta,
                "finalization trace validator=%" PRIu64 " target_slot=%" PRIu64 " votes=%zu quorum=%zu",
                vote->validator_id,
                vote->target.slot,
                vote_count,
                quorum);
        }

        /* Check if 2/3 supermajority reached (leanSpec line 428: 3 * count >= 2 * validators) */
        bool target_was_justified = false;
        if (vote_count >= quorum) {
            /* Supermajority reached - mark as justified */
            if (lantern_state_mark_justified_slot(state, vote->target.slot) != 0) {
                record_attestation_validation_metric(att_validation_start, false);
                return -1;
            }
            target_is_justified = true;
            target_was_justified = true;

            latest_justified = vote->target;

            if (trace_finalization) {
                lantern_log_debug(
                    "state",
                    &meta,
                    "finalization trace marked target slot=%" PRIu64 " justified (votes=%zu quorum=%zu)",
                    vote->target.slot,
                    vote_count,
                    quorum);
            }

            /* Clean up tracking for this root (leanSpec line 431) */
            if (lantern_state_remove_justification_root(state, root_idx, validator_count) != 0) {
                lantern_log_warn(
                    "state",
                    &meta,
                    "failed to remove justification root after justifying slot %" PRIu64,
                    vote->target.slot);
            }

            /* Finalization: if the target is the next valid justifiable slot after source (leanSpec lines 435-439)
             *
             * The key is to check if there's any JUSTIFIABLE slot between source and target,
             * relative to the current finalized slot. Both Zeam and the devnet use the progressively
             * updated finalized slot during the loop (self.latest_finalized in Zeam, line 411).
             *
             * IMPORTANT: We use latest_finalized.slot (the locally updated value) to match Zeam behavior.
             */
            bool has_justifiable_between = has_justifiable_slot_between(
                vote->source.slot, vote->target.slot, latest_finalized.slot);
            bool vote_has_consecutive_source = !has_justifiable_between;

            if (trace_finalization) {
                lantern_log_debug(
                    "state",
                    &meta,
                    "finalization trace validator=%" PRIu64 " target_was_justified=%s vote_consecutive=%s "
                    "latest_finalized=%" PRIu64 " latest_justified=%" PRIu64,
                    vote->validator_id,
                    target_was_justified ? "true" : "false",
                    vote_has_consecutive_source ? "true" : "false",
                    latest_finalized.slot,
                    latest_justified.slot);
            }

            if (vote_has_consecutive_source) {
                /* Finalize the source checkpoint */
                uint64_t old_finalized_slot = latest_finalized.slot;
                latest_finalized = vote->source;
                finalization_attempted = true;
                lean_metrics_record_finalization_attempt(true);
                if (latest_finalized.slot > old_finalized_slot) {
                    uint64_t delta = latest_finalized.slot - old_finalized_slot;
                    if (delta > SIZE_MAX) {
                        if (finalization_attempted) {
                            lean_metrics_record_finalization_attempt(false);
                        }
                        record_attestation_validation_metric(att_validation_start, false);
                        return -1;
                    }
                    if (delta > 0) {
                        if (lantern_bitlist_drop_front(&state->justified_slots, (size_t)delta) != 0) {
                            if (finalization_attempted) {
                                lean_metrics_record_finalization_attempt(false);
                            }
                            record_attestation_validation_metric(att_validation_start, false);
                            return -1;
                        }
                        if (state->justified_slots_offset <= UINT64_MAX - delta) {
                            state->justified_slots_offset += delta;
                        } else {
                            if (finalization_attempted) {
                                lean_metrics_record_finalization_attempt(false);
                            }
                            record_attestation_validation_metric(att_validation_start, false);
                            return -1;
                        }
                    }
                    if (lantern_state_prune_justification_roots(
                            state,
                            base_finalized_slot,
                            latest_finalized.slot,
                            validator_count,
                            &meta)
                        != 0) {
                        if (finalization_attempted) {
                            lean_metrics_record_finalization_attempt(false);
                        }
                        record_attestation_validation_metric(att_validation_start, false);
                        return -1;
                    }
                }
                if (trace_finalization) {
                    lantern_log_debug(
                        "state",
                        &meta,
                        "finalization trace updated checkpoints finalized=%" PRIu64 " justified=%" PRIu64,
                        latest_finalized.slot,
                        latest_justified.slot);
                }
            }
        }

        record_attestation_validation_metric(att_validation_start, true);
    }

    if (apply_consensus_effects) {
        if (lantern_state_mark_justified_slot(state, latest_justified.slot) != 0) {
            if (finalization_attempted) {
                lean_metrics_record_finalization_attempt(false);
            }
            return -1;
        }
        if (lantern_state_mark_justified_slot(state, latest_finalized.slot) != 0) {
            if (finalization_attempted) {
                lean_metrics_record_finalization_attempt(false);
            }
            return -1;
        }

        state->latest_justified = latest_justified;
        state->latest_finalized = latest_finalized;
        if (trace_finalization) {
            lantern_log_debug(
                "state",
                &meta,
                "finalization trace commit finalized=%" PRIu64 " justified=%" PRIu64,
                state->latest_finalized.slot,
                state->latest_justified.slot);
        }
        if (state->fork_choice) {
            if (lantern_fork_choice_update_checkpoints(
                    state->fork_choice,
                    &state->latest_justified,
                    &state->latest_finalized)
                != 0) {
                if (finalization_attempted) {
                    lean_metrics_record_finalization_attempt(false);
                }
                return -1;
            }
        }
    }
    lean_metrics_record_state_transition_attestations(att_attempted, lantern_time_now_seconds() - att_batch_start);
    return 0;
}

int lantern_state_process_attestations(
    LanternState *state,
    const LanternAttestations *attestations,
    const LanternSignatureList *signatures) {
    return lantern_state_process_attestations_internal(state, attestations, signatures, true);
}

static int lantern_state_stage_attestations(
    LanternState *state,
    const LanternAttestations *attestations,
    const LanternSignatureList *signatures) {
    return lantern_state_process_attestations_internal(state, attestations, signatures, false);
}

int lantern_state_process_block(
    LanternState *state,
    const LanternBlock *block,
    const LanternBlockSignatures *signatures,
    const LanternSignedVote *proposer_attestation) {
    if (!state || !block) {
        return -1;
    }
    double block_metrics_start = lantern_time_now_seconds();
    if (lantern_state_process_block_header(state, block) != 0) {
        return -1;
    }
    (void)signatures;
    size_t validator_count = 0;
    if (state->config.num_validators > SIZE_MAX) {
        return -1;
    }
    validator_count = (size_t)state->config.num_validators;
    LanternAttestations expanded = {0};
    lantern_attestations_init(&expanded);
    if (lantern_expand_aggregated_attestations(&block->body.attestations, validator_count, &expanded) != 0) {
        lantern_attestations_reset(&expanded);
        return -1;
    }
    if (lantern_state_process_attestations(state, &expanded, NULL) != 0) {
        lantern_attestations_reset(&expanded);
        return -1;
    }
    lantern_attestations_reset(&expanded);

    if (proposer_attestation && state->config.num_validators > 0) {
        const LanternVote *vote = &proposer_attestation->data;
        uint64_t validator_id = vote->validator_id;
        if (validator_id < state->config.num_validators && vote->target.slot > vote->source.slot) {
            LanternVote proposer_vote = *vote;
            LanternAttestations proposer_batch = {
                .data = &proposer_vote,
                .length = 1,
                .capacity = 1,
            };
            LanternSignature proposer_sig = proposer_attestation->signature;
            LanternSignatureList proposer_sig_batch = {
                .data = &proposer_sig,
                .length = 1,
                .capacity = 1,
            };
            const LanternSignatureList *sig_view = signature_is_zero(&proposer_sig) ? NULL : &proposer_sig_batch;
            if (lantern_state_stage_attestations(state, &proposer_batch, sig_view) != 0) {
                return -1;
            }
        }
    }
    if (state->fork_choice) {
        if (lantern_fork_choice_add_block(
                state->fork_choice,
                block,
                proposer_attestation,
                &state->latest_justified,
                &state->latest_finalized,
                NULL)
            != 0) {
            return -1;
        }
    }
    lean_metrics_record_state_transition_block(lantern_time_now_seconds() - block_metrics_start);
    return 0;
}

int lantern_state_transition(LanternState *state, const LanternSignedBlock *signed_block) {
    if (!state || !signed_block) {
        return -1;
    }
    const LanternBlock *block = &signed_block->message.block;
    double transition_metrics_start = lantern_time_now_seconds();
#define STATE_FAIL(fmt, ...)                                                                 \
    do {                                                                                     \
        lantern_log_warn(                                                                    \
            "state",                                                                         \
            &(const struct lantern_log_metadata){.has_slot = true, .slot = block->slot},     \
            fmt,                                                                             \
            ##__VA_ARGS__);                                                                  \
        return -1;                                                                           \
    } while (0)

    if (block->slot <= state->slot) {
        STATE_FAIL("block slot %" PRIu64 " not ahead of state %" PRIu64, block->slot, state->slot);
    }
    uint64_t slot_before = state->slot;
    double slots_metrics_start = lantern_time_now_seconds();
    if (lantern_state_process_slots(state, block->slot) != 0) {
        STATE_FAIL("process slots failed current=%" PRIu64, state->slot);
    }
    double slots_duration = lantern_time_now_seconds() - slots_metrics_start;
    uint64_t slots_processed = block->slot >= slot_before ? (block->slot - slot_before) : 0;
    lean_metrics_record_state_transition_slots(slots_processed, slots_duration);
    LanternSignedVote proposer_signed;
    memset(&proposer_signed, 0, sizeof(proposer_signed));
    proposer_signed.data = signed_block->message.proposer_attestation;
    proposer_signed.signature = signed_block->signatures.proposer_signature;

    if (lantern_state_process_block(state, block, &signed_block->signatures, &proposer_signed) != 0) {
        STATE_FAIL("process block failed");
    }
    LanternRoot computed_state_root;
    bool hashed_state = lantern_hash_tree_root_state(state, &computed_state_root) == 0;
    if (hashed_state) {
        if (memcmp(block->state_root.bytes, computed_state_root.bytes, LANTERN_ROOT_SIZE) != 0) {
            char expected_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
            char computed_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
            if (lantern_bytes_to_hex(
                    block->state_root.bytes,
                    LANTERN_ROOT_SIZE,
                    expected_hex,
                    sizeof(expected_hex),
                    1)
                != 0) {
                expected_hex[0] = '\0';
            }
            if (lantern_bytes_to_hex(
                    computed_state_root.bytes,
                    LANTERN_ROOT_SIZE,
                    computed_hex,
                    sizeof(computed_hex),
                    1)
                != 0) {
                computed_hex[0] = '\0';
            }
            lantern_log_warn(
                "state",
                &(const struct lantern_log_metadata){.has_slot = true, .slot = block->slot},
                "state root mismatch: expected=%s computed=%s",
                expected_hex[0] ? expected_hex : "0x0",
                computed_hex[0] ? computed_hex : "0x0");
            char finalized_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
            char justified_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
            finalized_hex[0] = '\0';
            justified_hex[0] = '\0';
            if (lantern_bytes_to_hex(
                    state->latest_finalized.root.bytes,
                    LANTERN_ROOT_SIZE,
                    finalized_hex,
                    sizeof(finalized_hex),
                    1)
                != 0) {
                finalized_hex[0] = '\0';
            }
            if (lantern_bytes_to_hex(
                    state->latest_justified.root.bytes,
                    LANTERN_ROOT_SIZE,
                    justified_hex,
                    sizeof(justified_hex),
                    1)
                != 0) {
                justified_hex[0] = '\0';
            }
            lantern_log_warn(
                "state",
                &(const struct lantern_log_metadata){.has_slot = true, .slot = block->slot},
                "state root context state_slot=%" PRIu64 " header_slot=%" PRIu64
                " finalized_slot=%" PRIu64 " justified_offset=%" PRIu64
                " justified_bits=%zu hist_offset=%" PRIu64 " hist_len=%zu"
                " just_roots=%zu just_votes=%zu",
                state->slot,
                state->latest_block_header.slot,
                state->latest_finalized.slot,
                state->justified_slots_offset,
                state->justified_slots.bit_length,
                state->historical_roots_offset,
                state->historical_block_hashes.length,
                state->justification_roots.length,
                state->justification_validators.bit_length);
            lantern_log_warn(
                "state",
                &(const struct lantern_log_metadata){.has_slot = true, .slot = block->slot},
                "state root checkpoints finalized_slot=%" PRIu64 " finalized_root=%s"
                " justified_slot=%" PRIu64 " justified_root=%s",
                state->latest_finalized.slot,
                finalized_hex[0] ? finalized_hex : "0x0",
                state->latest_justified.slot,
                justified_hex[0] ? justified_hex : "0x0");
            STATE_FAIL("state root mismatch for slot %" PRIu64, block->slot);
        }
    } else {
        STATE_FAIL("failed to hash state for slot %" PRIu64, block->slot);
    }

    state->slot = block->slot;
    lean_metrics_record_state_transition(lantern_time_now_seconds() - transition_metrics_start);
#undef STATE_FAIL
    return 0;
}

int lantern_state_select_block_parent(LanternState *state, LanternRoot *out_parent_root) {
    if (!state || !out_parent_root) {
        return -1;
    }
    if (state->config.num_validators == 0) {
        return -1;
    }

    if (lantern_state_process_slot(state) != 0) {
        return -1;
    }

    LanternRoot header_root;
    if (lantern_hash_tree_root_block_header(&state->latest_block_header, &header_root) != 0) {
        return -1;
    }

    if (state->fork_choice) {
        LanternRoot head_root;
        if (lantern_fork_choice_current_head(state->fork_choice, &head_root) != 0) {
            return -1;
        }
        if (memcmp(head_root.bytes, header_root.bytes, LANTERN_ROOT_SIZE) != 0) {
            return -1;
        }
        *out_parent_root = head_root;
    } else {
        *out_parent_root = header_root;
    }
    return 0;
}

int lantern_state_collect_attestations_for_block(
    const LanternState *state,
    uint64_t block_slot,
    uint64_t proposer_index,
    const LanternRoot *parent_root,
    const LanternSignedVote *proposer_attestation,
    LanternAttestations *out_attestations,
    LanternSignatureList *out_signatures) {
    if (!state || !out_attestations || !out_signatures || !parent_root) {
        return -1;
    }
    if (!state->validator_votes || state->validator_votes_len == 0) {
        return -1;
    }
    if (block_slot <= state->slot) {
        return -1;
    }
    if (lantern_attestations_resize(out_attestations, 0) != 0) {
        return -1;
    }
    if (lantern_signature_list_resize(out_signatures, 0) != 0) {
        (void)lantern_attestations_resize(out_attestations, 0);
        return -1;
    }

    LanternState slot_snapshot;
    lantern_state_init(&slot_snapshot);
    LanternState scratch;
    lantern_state_init(&scratch);
    int rc = 0;
    bool fixed_point = false;
    const LanternSignedVote *proposer_ptr = proposer_attestation;
    LanternAggregatedAttestations aggregated_view;
    lantern_aggregated_attestations_init(&aggregated_view);

    if (lantern_state_clone_view(state, &slot_snapshot) != 0) {
        rc = -1;
        goto cleanup;
    }
    if (lantern_state_process_slots(&slot_snapshot, block_slot) != 0) {
        rc = -1;
        goto cleanup;
    }

    LanternCheckpoint checkpoint = slot_snapshot.latest_justified;
    size_t iteration = 0;
    size_t iteration_guard = state->validator_votes_len == 0 ? 1 : state->validator_votes_len;
    if (iteration_guard < SIZE_MAX) {
        iteration_guard += 1u;
    }
    const struct lantern_log_metadata meta = {
        .has_slot = true,
        .slot = block_slot,
    };
    while (true) {
        if (collect_attestations_for_checkpoint(&slot_snapshot, &checkpoint, out_attestations, out_signatures) != 0) {
            rc = -1;
            goto cleanup;
        }
        lantern_aggregated_attestations_reset(&aggregated_view);
        if (lantern_wrap_attestations_as_aggregated(out_attestations, &aggregated_view) != 0) {
            rc = -1;
            goto cleanup;
        }

        lantern_state_reset(&scratch);
        if (lantern_state_clone_view(&slot_snapshot, &scratch) != 0) {
            rc = -1;
            goto cleanup;
        }

        LanternBlock candidate;
        memset(&candidate, 0, sizeof(candidate));
        candidate.slot = block_slot;
        candidate.proposer_index = proposer_index;
        candidate.parent_root = *parent_root;
        candidate.body.attestations.data = aggregated_view.data;
        candidate.body.attestations.length = aggregated_view.length;
        candidate.body.attestations.capacity = aggregated_view.length;

        if (lantern_state_process_block(&scratch, &candidate, NULL, proposer_ptr) != 0) {
            rc = -1;
            goto cleanup;
        }

        LanternCheckpoint post_checkpoint = scratch.latest_justified;
        lantern_state_reset(&scratch);
        if (lantern_checkpoint_equal(&post_checkpoint, &checkpoint)) {
            fixed_point = true;
            break;
        }
        checkpoint = post_checkpoint;
        iteration += 1u;
        if (iteration > iteration_guard) {
            lantern_log_warn(
                "state",
                &meta,
                "attestation collection failed to converge after %zu iterations (validators=%zu)",
                iteration,
                state->validator_votes_len);
            break;
        }
    }

cleanup:
    lantern_state_reset(&scratch);
    lantern_state_reset(&slot_snapshot);
    lantern_aggregated_attestations_reset(&aggregated_view);
    if (!fixed_point) {
        rc = -1;
    }
    if (rc != 0) {
        (void)lantern_attestations_resize(out_attestations, 0);
        (void)lantern_signature_list_resize(out_signatures, 0);
    }
    return rc;
}

int lantern_state_preview_post_state_root(
    const LanternState *state,
    const LanternSignedBlock *block,
    LanternRoot *out_state_root) {
    if (!state || !block || !out_state_root) {
        return -1;
    }
    if (block->message.block.slot <= state->slot) {
        return -1;
    }
    LanternState scratch;
    if (lantern_state_clone_view(state, &scratch) != 0) {
        return -1;
    }
    scratch.fork_choice = NULL;
    int rc = 0;
    if (lantern_state_process_slots(&scratch, block->message.block.slot) != 0) {
        rc = -1;
        goto cleanup;
    }
    LanternSignedVote proposer_signed;
    memset(&proposer_signed, 0, sizeof(proposer_signed));
    proposer_signed.data = block->message.proposer_attestation;
    proposer_signed.signature = block->signatures.proposer_signature;
    if (lantern_state_process_block(&scratch, &block->message.block, &block->signatures, &proposer_signed) != 0) {
        rc = -1;
        goto cleanup;
    }
    if (lantern_hash_tree_root_state(&scratch, out_state_root) != 0) {
        rc = -1;
    }

cleanup:
    lantern_state_reset(&scratch);
    return rc;
}

void lantern_state_profile_dump(void) {
    return;
}

int lantern_state_compute_vote_checkpoints(
    const LanternState *state,
    LanternCheckpoint *out_head,
    LanternCheckpoint *out_target,
    LanternCheckpoint *out_source) {
    if (!state || !out_head || !out_target || !out_source) {
        return -1;
    }
    if (!state->fork_choice) {
        return -1;
    }

    const LanternForkChoice *store = state->fork_choice;
    bool trace_finalization = finalization_trace_enabled();
    struct lantern_log_metadata trace_meta = {.has_slot = true, .slot = state->slot};
    char head_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    char target_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    char parent_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    char safe_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    LanternRoot head_root;
    if (lantern_fork_choice_current_head(store, &head_root) != 0) {
        return -1;
    }
    uint64_t head_slot = 0;
    if (lantern_fork_choice_block_info(store, &head_root, &head_slot, NULL, NULL) != 0) {
        return -1;
    }
    const LanternCheckpoint *store_justified = lantern_fork_choice_latest_justified(store);
    const LanternCheckpoint *store_finalized = lantern_fork_choice_latest_finalized(store);
    LanternCheckpoint source_checkpoint = state->latest_justified;
    LanternCheckpoint finalized_checkpoint = state->latest_finalized;
    if (store_justified && !lantern_root_is_zero(&store_justified->root)) {
        source_checkpoint = *store_justified;
    }
    if (store_finalized && !lantern_root_is_zero(&store_finalized->root)) {
        finalized_checkpoint = *store_finalized;
    }
    LanternRoot target_root = head_root;
    uint64_t target_slot = head_slot;
    uint64_t source_slot = source_checkpoint.slot;
    bool candidate_valid = false;
    LanternRoot candidate_root;
    uint64_t candidate_slot = 0;
    if (trace_finalization) {
        format_root_hex(&head_root, head_hex, sizeof(head_hex));
        lantern_log_debug(
            "state",
            &trace_meta,
            "finalization trace checkpoints head slot=%" PRIu64 " root=%s",
            head_slot,
            head_hex[0] ? head_hex : "0x0");
    }
    if (head_slot > source_slot && lantern_slot_is_justifiable(head_slot, finalized_checkpoint.slot)) {
        candidate_valid = true;
        candidate_root = head_root;
        candidate_slot = head_slot;
    }

    uint64_t safe_slot = head_slot;
    bool has_safe = false;
    const LanternRoot *safe_ptr = lantern_fork_choice_safe_target(store);
    if (safe_ptr) {
        if (lantern_fork_choice_block_info(store, safe_ptr, &safe_slot, NULL, NULL) != 0) {
            return -1;
        }
        has_safe = true;
        if (trace_finalization) {
            format_root_hex(safe_ptr, safe_hex, sizeof(safe_hex));
            lantern_log_debug(
                "state",
                &trace_meta,
                "finalization trace checkpoints safe_target slot=%" PRIu64 " root=%s",
                safe_slot,
                safe_hex[0] ? safe_hex : "0x0");
        }
    }

    if (has_safe) {
        for (size_t i = 0; i < 3 && target_slot > safe_slot; ++i) {
            LanternRoot parent_root;
            bool has_parent = false;
            if (lantern_fork_choice_block_info(store, &target_root, &target_slot, &parent_root, &has_parent) != 0) {
                return -1;
            }
            if (!has_parent) {
                break;
            }
            uint64_t parent_slot = 0;
            if (lantern_fork_choice_block_info(store, &parent_root, &parent_slot, NULL, NULL) != 0) {
                return -1;
            }
            if (trace_finalization) {
                format_root_hex(&target_root, target_hex, sizeof(target_hex));
                format_root_hex(&parent_root, parent_hex, sizeof(parent_hex));
                lantern_log_debug(
                    "state",
                    &trace_meta,
                    "finalization trace checkpoints safe_step=%zu current_slot=%" PRIu64
                    " parent_slot=%" PRIu64 " root=%s parent=%s",
                    i + 1,
                    target_slot,
                    parent_slot,
                    target_hex[0] ? target_hex : "0x0",
                    parent_hex[0] ? parent_hex : "0x0");
        }
        target_root = parent_root;
        target_slot = parent_slot;
        if (target_slot > source_slot && lantern_slot_is_justifiable(target_slot, finalized_checkpoint.slot)) {
            candidate_valid = true;
            candidate_root = target_root;
            candidate_slot = target_slot;
        }
    }
}

    bool justifiable_slot_found = true;
    while (!lantern_slot_is_justifiable(target_slot, finalized_checkpoint.slot)) {
        LanternRoot parent_root;
        bool has_parent = false;
        if (lantern_fork_choice_block_info(store, &target_root, &target_slot, &parent_root, &has_parent) != 0) {
            return -1;
        }
        if (!has_parent) {
            justifiable_slot_found = false;
            break;
        }
        uint64_t parent_slot = 0;
        if (lantern_fork_choice_block_info(store, &parent_root, &parent_slot, NULL, NULL) != 0) {
            return -1;
        }
        if (parent_slot < finalized_checkpoint.slot) {
            justifiable_slot_found = false;
            if (trace_finalization) {
                format_root_hex(&target_root, target_hex, sizeof(target_hex));
                format_root_hex(&parent_root, parent_hex, sizeof(parent_hex));
                lantern_log_debug(
                    "state",
                    &trace_meta,
                    "finalization trace checkpoints justifiable_stop target_slot=%" PRIu64
                    " parent_slot=%" PRIu64 " root=%s parent=%s",
                    target_slot,
                    parent_slot,
                    target_hex[0] ? target_hex : "0x0",
                    parent_hex[0] ? parent_hex : "0x0");
            }
            break;
        }
        if (trace_finalization) {
            format_root_hex(&target_root, target_hex, sizeof(target_hex));
            format_root_hex(&parent_root, parent_hex, sizeof(parent_hex));
            lantern_log_debug(
                "state",
                &trace_meta,
                "finalization trace checkpoints justifiable_step target_slot=%" PRIu64
                " parent_slot=%" PRIu64 " root=%s parent=%s",
                target_slot,
                parent_slot,
                target_hex[0] ? target_hex : "0x0",
                parent_hex[0] ? parent_hex : "0x0");
        }
        target_root = parent_root;
        target_slot = parent_slot;
        if (target_slot > source_slot && lantern_slot_is_justifiable(target_slot, finalized_checkpoint.slot)) {
            candidate_valid = true;
            candidate_root = target_root;
            candidate_slot = target_slot;
        }
    }
    if (trace_finalization && !justifiable_slot_found) {
        lantern_log_debug(
            "state",
            &trace_meta,
            "finalization trace checkpoints justifiable_slot_unreachable finalized=%" PRIu64
            " current=%" PRIu64,
            finalized_checkpoint.slot,
            target_slot);
    }
    if (target_slot > source_slot && lantern_slot_is_justifiable(target_slot, finalized_checkpoint.slot)) {
        candidate_valid = true;
        candidate_root = target_root;
        candidate_slot = target_slot;
    }
    if (target_slot <= source_slot && candidate_valid) {
        if (trace_finalization) {
            format_root_hex(&target_root, target_hex, sizeof(target_hex));
            char candidate_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
            format_root_hex(&candidate_root, candidate_hex, sizeof(candidate_hex));
            lantern_log_debug(
                "state",
                &trace_meta,
                "finalization trace checkpoints promote target slot=%" PRIu64 "->%" PRIu64
                " root=%s promoted=%s source=%" PRIu64,
                target_slot,
                candidate_slot,
                target_hex[0] ? target_hex : "0x0",
                candidate_hex[0] ? candidate_hex : "0x0",
                source_slot);
        }
        target_root = candidate_root;
        target_slot = candidate_slot;
    }

    out_head->root = head_root;
    out_head->slot = head_slot;
    out_target->root = target_root;
    out_target->slot = target_slot;
    *out_source = source_checkpoint;
    if (trace_finalization) {
        lantern_log_debug(
            "state",
            &trace_meta,
            "finalization trace checkpoints head=%" PRIu64 " target=%" PRIu64 " source=%" PRIu64,
            out_head->slot,
            out_target->slot,
            out_source->slot);
    }
    return 0;
}
