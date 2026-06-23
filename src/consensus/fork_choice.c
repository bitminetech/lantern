#include "lantern/consensus/fork_choice.h"

#include <inttypes.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>

#include "lantern/consensus/hash.h"
#include "lantern/consensus/quorum.h"
#include "lantern/consensus/store.h"
#include "lantern/metrics/lean_metrics.h"
#include "lantern/support/log.h"
#include "lantern/support/strings.h"
#include "lantern/support/time.h"

#define LANTERN_FORK_CHOICE_DEFAULT_SECONDS_PER_SLOT 4u
#define LANTERN_FORK_CHOICE_DEFAULT_INTERVALS_PER_SLOT 5u
#define LANTERN_FORK_CHOICE_MILLISECONDS_PER_SECOND 1000u

struct fork_choice_latest_vote {
    bool has_checkpoint;
    LanternCheckpoint checkpoint;
    uint64_t slot;
};

static void zero_root(LanternRoot *root) {
    if (root) {
        memset(root->bytes, 0, sizeof(root->bytes));
    }
}

static bool root_is_zero(const LanternRoot *root) {
    if (!root) {
        return true;
    }
    for (size_t i = 0; i < sizeof(root->bytes); ++i) {
        if (root->bytes[i] != 0) {
            return false;
        }
    }
    return true;
}

static void checkpoint_snapshot_init(struct lantern_fork_choice_checkpoint_snapshot *snapshot) {
    if (!snapshot) {
        return;
    }
    atomic_init(&snapshot->sequence, 0u);
    atomic_init(&snapshot->justified_slot, 0u);
    atomic_init(&snapshot->finalized_slot, 0u);
    for (size_t i = 0; i < LANTERN_ROOT_SIZE; ++i) {
        atomic_init(&snapshot->justified_root[i], 0u);
        atomic_init(&snapshot->finalized_root[i], 0u);
    }
}

static void checkpoint_snapshot_publish_one(
    atomic_uint_fast64_t *slot,
    atomic_uchar *root,
    const LanternCheckpoint *checkpoint) {
    uint64_t checkpoint_slot = checkpoint ? checkpoint->slot : 0u;
    atomic_store_explicit(slot, checkpoint_slot, memory_order_relaxed);
    for (size_t i = 0; i < LANTERN_ROOT_SIZE; ++i) {
        uint8_t byte = checkpoint ? checkpoint->root.bytes[i] : 0u;
        atomic_store_explicit(&root[i], byte, memory_order_relaxed);
    }
}

static void fork_choice_publish_current_checkpoints(LanternForkChoice *store) {
    if (!store) {
        return;
    }
    struct lantern_fork_choice_checkpoint_snapshot *snapshot = &store->checkpoint_snapshot;
    uint64_t sequence = atomic_load_explicit(&snapshot->sequence, memory_order_relaxed);
    if ((sequence & 1u) != 0u) {
        sequence += 1u;
    }

    atomic_store_explicit(&snapshot->sequence, sequence + 1u, memory_order_release);
    checkpoint_snapshot_publish_one(
        &snapshot->justified_slot,
        snapshot->justified_root,
        &store->latest_justified);
    checkpoint_snapshot_publish_one(
        &snapshot->finalized_slot,
        snapshot->finalized_root,
        &store->latest_finalized);
    atomic_store_explicit(&snapshot->sequence, sequence + 2u, memory_order_release);
}

static int root_compare(const LanternRoot *a, const LanternRoot *b) {
    return memcmp(a->bytes, b->bytes, sizeof(a->bytes));
}

static bool find_block_index(const LanternForkChoice *store, const LanternRoot *root, size_t *out_index) {
    if (!store || !root || !store->blocks) {
        return false;
    }
    for (size_t i = 0; i < store->block_len; ++i) {
        if (root_compare(&store->blocks[i].root, root) == 0) {
            if (out_index) {
                *out_index = i;
            }
            return true;
        }
    }
    return false;
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

static void states_reset(LanternForkChoice *store) {
    if (!store || !store->states) {
        return;
    }
    for (size_t i = 0; i < store->state_cap; ++i) {
        struct lantern_fork_choice_state_entry *entry = &store->states[i];
        if (!entry->has_state) {
            continue;
        }
        lantern_state_reset(&entry->state);
        entry->has_state = false;
    }
    free(store->states);
    store->states = NULL;
    store->state_cap = 0;
}

static int ensure_block_capacity(LanternForkChoice *store, size_t required) {
    if (!store) {
        return -1;
    }
    if (store->block_cap >= required) {
        return 0;
    }
    size_t previous_cap = store->block_cap;
    size_t capacity = store->block_cap == 0 ? 4u : store->block_cap;
    while (capacity < required) {
        if (capacity > (SIZE_MAX / 2)) {
            return -1;
        }
        capacity *= 2;
    }
    struct lantern_fork_choice_block_entry *entries = realloc(
        store->blocks,
        capacity * sizeof(*entries));
    if (!entries) {
        return -1;
    }
    store->blocks = entries;
    if (capacity > previous_cap) {
        memset(&store->blocks[previous_cap], 0, (capacity - previous_cap) * sizeof(*store->blocks));
    }

    struct lantern_fork_choice_state_entry *states = realloc(
        store->states,
        capacity * sizeof(*states));
    if (!states) {
        return -1;
    }
    store->states = states;
    if (capacity > store->state_cap) {
        memset(&store->states[store->state_cap], 0, (capacity - store->state_cap) * sizeof(*store->states));
    }
    store->block_cap = capacity;
    store->state_cap = capacity;
    return 0;
}

static bool parent_index_for_block(const LanternForkChoice *store, size_t block_index, size_t *out_parent) {
    if (!store || !store->blocks || block_index >= store->block_len || !out_parent) {
        return false;
    }
    const LanternRoot *parent_root = &store->blocks[block_index].parent_root;
    if (root_is_zero(parent_root)) {
        return false;
    }
    if (find_block_index(store, parent_root, out_parent)) {
        return true;
    }
    return false;
}

static bool block_descends_from(
    const LanternForkChoice *store,
    size_t block_index,
    size_t ancestor_index) {
    if (!store || !store->blocks || block_index >= store->block_len || ancestor_index >= store->block_len) {
        return false;
    }
    size_t current = block_index;
    for (size_t depth = 0; depth < store->block_len && current < store->block_len; ++depth) {
        if (current == ancestor_index) {
            return true;
        }
        size_t parent = 0;
        if (!parent_index_for_block(store, current, &parent)) {
            return false;
        }
        current = parent;
    }
    return false;
}

void lantern_fork_choice_init(LanternForkChoice *store) {
    if (!store) {
        return;
    }
    memset(store, 0, sizeof(*store));
    checkpoint_snapshot_init(&store->checkpoint_snapshot);
    store->seconds_per_slot = LANTERN_FORK_CHOICE_DEFAULT_SECONDS_PER_SLOT;
    store->intervals_per_slot = LANTERN_FORK_CHOICE_DEFAULT_INTERVALS_PER_SLOT;
    store->milliseconds_per_interval =
        ((uint64_t)store->seconds_per_slot * LANTERN_FORK_CHOICE_MILLISECONDS_PER_SECOND) / store->intervals_per_slot;
}

void lantern_fork_choice_reset(LanternForkChoice *store) {
    if (!store) {
        return;
    }
    size_t validator_count = store->validator_count;
    const struct lantern_aggregated_payload_pool *new_aggregated_payloads =
        store->new_aggregated_payloads;
    const struct lantern_aggregated_payload_pool *known_aggregated_payloads =
        store->known_aggregated_payloads;
    const struct lantern_attestation_data_by_root *attestation_data_by_root =
        store->attestation_data_by_root;
    states_reset(store);
    free(store->blocks);
    store->blocks = NULL;
    store->block_cap = 0;
    store->block_len = 0;

    store->initialized = false;
    store->has_anchor = false;
    zero_root(&store->anchor_root);
    store->anchor_slot = 0;
    store->has_head = false;
    store->has_safe_target = false;
    zero_root(&store->head);
    zero_root(&store->safe_target);
    memset(&store->latest_justified, 0, sizeof(store->latest_justified));
    memset(&store->latest_finalized, 0, sizeof(store->latest_finalized));
    checkpoint_snapshot_init(&store->checkpoint_snapshot);
    store->time_intervals = 0;
    store->seconds_per_slot = LANTERN_FORK_CHOICE_DEFAULT_SECONDS_PER_SLOT;
    store->intervals_per_slot = LANTERN_FORK_CHOICE_DEFAULT_INTERVALS_PER_SLOT;
    store->milliseconds_per_interval =
        ((uint64_t)store->seconds_per_slot * LANTERN_FORK_CHOICE_MILLISECONDS_PER_SECOND) / store->intervals_per_slot;
    store->validator_count = validator_count;
    store->new_aggregated_payloads = new_aggregated_payloads;
    store->known_aggregated_payloads = known_aggregated_payloads;
    store->attestation_data_by_root = attestation_data_by_root;
}

int lantern_fork_choice_configure(LanternForkChoice *store, const LanternConfig *config) {
    if (!store || !config) {
        return -1;
    }
    if (config->num_validators == 0) {
        return -1;
    }
    lantern_fork_choice_reset(store);

    store->config = *config;
    store->validator_count = (size_t)config->num_validators;
    store->seconds_per_slot = LANTERN_FORK_CHOICE_DEFAULT_SECONDS_PER_SLOT;
    store->intervals_per_slot = LANTERN_FORK_CHOICE_DEFAULT_INTERVALS_PER_SLOT;
    store->milliseconds_per_interval =
        ((uint64_t)store->seconds_per_slot * LANTERN_FORK_CHOICE_MILLISECONDS_PER_SECOND) / store->intervals_per_slot;
    store->initialized = true;
    return 0;
}

static int register_block(
    LanternForkChoice *store,
    const LanternRoot *root,
    const LanternRoot *parent_root,
    uint64_t slot,
    LanternValidatorIndex proposer_index) {
    if (!store || !root) {
        return -1;
    }
    size_t existing_index = 0;
    if (find_block_index(store, root, &existing_index)) {
        struct lantern_fork_choice_block_entry *entry = &store->blocks[existing_index];
        entry->slot = slot;
        entry->proposer_index = proposer_index;
        if (parent_root) {
            entry->parent_root = *parent_root;
        }
        return 0;
    }
    if (ensure_block_capacity(store, store->block_len + 1) != 0) {
        return -1;
    }
    struct lantern_fork_choice_block_entry *entry = &store->blocks[store->block_len];
    entry->root = *root;
    if (parent_root) {
        entry->parent_root = *parent_root;
    } else {
        zero_root(&entry->parent_root);
    }
    entry->slot = slot;
    entry->proposer_index = proposer_index;
    entry->has_validator_count = false;
    entry->validator_count = 0;
    store->block_len += 1;
    return 0;
}

int lantern_fork_choice_set_block_validator_count(
    LanternForkChoice *store,
    const LanternRoot *root,
    uint64_t validator_count) {
    if (!store || !root || validator_count == 0) {
        return -1;
    }
    size_t index = 0;
    if (!find_block_index(store, root, &index)) {
        return -1;
    }
    if (!store->blocks || index >= store->block_len) {
        return -1;
    }
    struct lantern_fork_choice_block_entry *entry = &store->blocks[index];
    entry->validator_count = validator_count;
    entry->has_validator_count = true;
    return 0;
}

int lantern_fork_choice_set_block_state(
    LanternForkChoice *store,
    const LanternRoot *root,
    const LanternState *state) {
    if (!store || !root || !state) {
        return -1;
    }
    size_t index = 0;
    if (!find_block_index(store, root, &index)) {
        return -1;
    }
    if (!store->states || index >= store->state_cap) {
        return -1;
    }

    LanternState cloned;
    lantern_state_init(&cloned);
    if (lantern_state_clone(state, &cloned) != 0) {
        lantern_state_reset(&cloned);
        return -1;
    }

    struct lantern_fork_choice_state_entry *entry = &store->states[index];
    if (entry->has_state) {
        lantern_state_reset(&entry->state);
    }
    entry->state = cloned;
    entry->has_state = true;
    return 0;
}

const LanternState *lantern_fork_choice_block_state(
    const LanternForkChoice *store,
    const LanternRoot *root) {
    if (!store || !root) {
        return NULL;
    }
    size_t index = 0;
    if (!find_block_index(store, root, &index)) {
        return NULL;
    }
    if (!store->states || index >= store->state_cap) {
        return NULL;
    }
    const struct lantern_fork_choice_state_entry *entry = &store->states[index];
    return entry->has_state ? &entry->state : NULL;
}

const LanternRoot *lantern_fork_choice_anchor_root(const LanternForkChoice *store) {
    if (!store || !store->has_anchor) {
        return NULL;
    }
    return &store->anchor_root;
}

int lantern_fork_choice_anchor_slot(const LanternForkChoice *store, uint64_t *out_slot) {
    if (!store || !store->has_anchor || !out_slot) {
        return -1;
    }
    *out_slot = store->anchor_slot;
    return 0;
}

int lantern_fork_choice_set_anchor(
    LanternForkChoice *store,
    const LanternBlock *anchor_block,
    const LanternCheckpoint *latest_justified,
    const LanternCheckpoint *latest_finalized,
    const LanternRoot *block_root_hint) {
    return lantern_fork_choice_set_anchor_with_state(
        store,
        anchor_block,
        latest_justified,
        latest_finalized,
        block_root_hint,
        NULL);
}

int lantern_fork_choice_set_anchor_with_state(
    LanternForkChoice *store,
    const LanternBlock *anchor_block,
    const LanternCheckpoint *latest_justified,
    const LanternCheckpoint *latest_finalized,
    const LanternRoot *block_root_hint,
    const LanternState *anchor_state) {
    if (!store || !store->initialized || !anchor_block) {
        return -1;
    }
    struct lantern_log_metadata meta = {.has_slot = true, .slot = anchor_block->slot};
    LanternRoot root;
    if (block_root_hint) {
        root = *block_root_hint;
    } else {
        if (lantern_hash_tree_root_block(anchor_block, &root) != SSZ_SUCCESS) {
            return -1;
        }
    }
    size_t existing_index = 0;
    bool existed = find_block_index(store, &root, &existing_index);
    struct lantern_fork_choice_block_entry previous_entry;
    memset(&previous_entry, 0, sizeof(previous_entry));
    if (existed) {
        if (!store->blocks || existing_index >= store->block_len) {
            return -1;
        }
        previous_entry = store->blocks[existing_index];
    }
    size_t previous_block_len = store->block_len;
    LanternCheckpoint previous_latest_justified = store->latest_justified;
    LanternCheckpoint previous_latest_finalized = store->latest_finalized;
    LanternRoot previous_anchor_root = store->anchor_root;
    uint64_t previous_anchor_slot = store->anchor_slot;
    LanternRoot previous_head = store->head;
    bool previous_has_head = store->has_head;
    LanternRoot previous_safe_target = store->safe_target;
    bool previous_has_safe_target = store->has_safe_target;
    bool previous_has_anchor = store->has_anchor;
    uint64_t previous_time_intervals = store->time_intervals;

    if (register_block(
            store,
            &root,
            &anchor_block->parent_root,
            anchor_block->slot,
            anchor_block->proposer_index)
        != 0) {
        return -1;
    }
    char root_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    char parent_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    char justified_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    char finalized_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    format_root_hex(&root, root_hex, sizeof(root_hex));
    format_root_hex(&anchor_block->parent_root, parent_hex, sizeof(parent_hex));
    format_root_hex(
        latest_justified ? &latest_justified->root : NULL,
        justified_hex,
        sizeof(justified_hex));
    format_root_hex(
        latest_finalized ? &latest_finalized->root : NULL,
        finalized_hex,
        sizeof(finalized_hex));
    lantern_log_info(
        "forkchoice",
        &meta,
        "set anchor slot=%" PRIu64 " root=%s parent=%s justified_slot=%" PRIu64
        " justified_root=%s finalized_slot=%" PRIu64 " finalized_root=%s"
        " block_root_hint=%s anchor_state=%s existed=%s",
        anchor_block->slot,
        root_hex[0] ? root_hex : "0x0",
        parent_hex[0] ? parent_hex : "0x0",
        latest_justified ? latest_justified->slot : 0u,
        justified_hex[0] ? justified_hex : "0x0",
        latest_finalized ? latest_finalized->slot : 0u,
        finalized_hex[0] ? finalized_hex : "0x0",
        block_root_hint ? "true" : "false",
        anchor_state ? "true" : "false",
        existed ? "true" : "false");
    LanternCheckpoint anchor_checkpoint = {
        .root = root,
        .slot = anchor_block->slot,
    };
    store->latest_justified = latest_justified ? *latest_justified : anchor_checkpoint;
    store->latest_finalized = latest_finalized ? *latest_finalized : anchor_checkpoint;
    store->head = root;
    store->has_head = true;
    store->safe_target = root;
    store->has_safe_target = true;
    store->has_anchor = true;
    store->anchor_root = root;
    store->anchor_slot = anchor_block->slot;
    uint64_t anchor_intervals = anchor_block->slot * store->intervals_per_slot;
    store->time_intervals = anchor_intervals;
    if (anchor_state && lantern_fork_choice_set_block_state(store, &root, anchor_state) != 0) {
        store->latest_justified = previous_latest_justified;
        store->latest_finalized = previous_latest_finalized;
        store->anchor_root = previous_anchor_root;
        store->anchor_slot = previous_anchor_slot;
        store->head = previous_head;
        store->has_head = previous_has_head;
        store->safe_target = previous_safe_target;
        store->has_safe_target = previous_has_safe_target;
        store->has_anchor = previous_has_anchor;
        store->time_intervals = previous_time_intervals;
        if (existed) {
            store->blocks[existing_index] = previous_entry;
        } else {
            store->block_len = previous_block_len;
        }
        return -1;
    }
    fork_choice_publish_current_checkpoints(store);
    return 0;
}

static bool checkpoint_known_in_store(
    const LanternForkChoice *store,
    const LanternCheckpoint *checkpoint) {
    if (!store || !checkpoint || root_is_zero(&checkpoint->root)) {
        return false;
    }
    size_t checkpoint_index = 0;
    if (!find_block_index(store, &checkpoint->root, &checkpoint_index)) {
        return false;
    }
    if (!store->blocks || checkpoint_index >= store->block_len) {
        return false;
    }
    return store->blocks[checkpoint_index].slot == checkpoint->slot;
}

static bool should_replace_checkpoint(
    const LanternCheckpoint *current,
    const LanternCheckpoint *candidate) {
    if (!current || !candidate || root_is_zero(&candidate->root)) {
        return false;
    }
    return candidate->slot > current->slot;
}

static void log_checkpoint_decision(
    const char *label,
    const char *decision,
    const LanternCheckpoint *current,
    const LanternCheckpoint *candidate) {
    if (!label || !decision || !current || !candidate) {
        return;
    }
    char current_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    char candidate_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    format_root_hex(&current->root, current_hex, sizeof(current_hex));
    format_root_hex(&candidate->root, candidate_hex, sizeof(candidate_hex));
    lantern_log_info(
        "forkchoice",
        &(const struct lantern_log_metadata){0},
        "checkpoint %s label=%s current_slot=%" PRIu64 " current_root=%s"
        " candidate_slot=%" PRIu64 " candidate_root=%s",
        decision,
        label,
        current->slot,
        current_hex[0] ? current_hex : "0x0",
        candidate->slot,
        candidate_hex[0] ? candidate_hex : "0x0");
}

static int update_latest_checkpoints(
    LanternForkChoice *store,
    const LanternCheckpoint *post_justified,
    const LanternCheckpoint *post_finalized,
    bool publish_snapshot) {
    if (!store) {
        return -1;
    }
    LanternCheckpoint latest_justified = store->latest_justified;
    LanternCheckpoint latest_finalized = store->latest_finalized;

    if (post_justified && !root_is_zero(&post_justified->root)) {
        if (should_replace_checkpoint(&latest_justified, post_justified)) {
            if (!checkpoint_known_in_store(store, post_justified)) {
                return -1;
            }
            log_checkpoint_decision(
                "justified",
                "advance",
                &latest_justified,
                post_justified);
            latest_justified = *post_justified;
        } else if (
            post_justified->slot == latest_justified.slot
            && root_compare(&post_justified->root, &latest_justified.root) != 0) {
            log_checkpoint_decision(
                "justified",
                "tie_keep_current",
                &latest_justified,
                post_justified);
        }
    }
    if (post_finalized && !root_is_zero(&post_finalized->root)) {
        if (should_replace_checkpoint(&latest_finalized, post_finalized)) {
            if (!checkpoint_known_in_store(store, post_finalized)) {
                return -1;
            }
            log_checkpoint_decision(
                "finalized",
                "advance",
                &latest_finalized,
                post_finalized);
            latest_finalized = *post_finalized;
        } else if (
            post_finalized->slot == latest_finalized.slot
            && root_compare(&post_finalized->root, &latest_finalized.root) != 0) {
            log_checkpoint_decision(
                "finalized",
                "tie_keep_current",
                &latest_finalized,
                post_finalized);
        }
    }

    if (latest_finalized.slot > latest_justified.slot) {
        return -1;
    }

    store->latest_justified = latest_justified;
    store->latest_finalized = latest_finalized;
    if (publish_snapshot) {
        fork_choice_publish_current_checkpoints(store);
    }
    return 0;
}

int lantern_fork_choice_add_block(
    LanternForkChoice *store,
    const LanternBlock *block,
    const LanternCheckpoint *post_justified,
    const LanternCheckpoint *post_finalized,
    const LanternRoot *block_root_hint) {
    return lantern_fork_choice_add_block_with_state(
        store,
        block,
        post_justified,
        post_finalized,
        block_root_hint,
        NULL);
}

int lantern_fork_choice_add_block_with_state(
    LanternForkChoice *store,
    const LanternBlock *block,
    const LanternCheckpoint *post_justified,
    const LanternCheckpoint *post_finalized,
    const LanternRoot *block_root_hint,
    const LanternState *post_state) {
    if (!store || !store->initialized || !store->has_anchor || !block) {
        return -1;
    }
    struct lantern_log_metadata diag_meta = {.has_slot = true, .slot = block->slot};
    char block_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    char parent_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    double metrics_start = lantern_time_now_seconds();
    LanternRoot block_root;
    if (block_root_hint) {
        block_root = *block_root_hint;
    } else {
        if (lantern_hash_tree_root_block(block, &block_root) != SSZ_SUCCESS) {
            return -1;
        }
    }
    LanternRoot hashed_block_root = {0};
    bool have_hashed_block_root = lantern_hash_tree_root_block(block, &hashed_block_root) == SSZ_SUCCESS;
    char hinted_block_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    char hashed_block_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    if (block_root_hint && have_hashed_block_root
        && root_compare(&hashed_block_root, &block_root) != 0) {
        format_root_hex(&block_root, hinted_block_hex, sizeof(hinted_block_hex));
        format_root_hex(&hashed_block_root, hashed_block_hex, sizeof(hashed_block_hex));
        lantern_log_info(
            "forkchoice",
            &diag_meta,
            "block root hint differs from block hash slot=%" PRIu64
            " hinted_root=%s hashed_root=%s",
            block->slot,
            hinted_block_hex[0] ? hinted_block_hex : "0x0",
            hashed_block_hex[0] ? hashed_block_hex : "0x0");
    }

    LanternCheckpoint previous_latest_justified = store->latest_justified;
    LanternCheckpoint previous_latest_finalized = store->latest_finalized;
    LanternRoot previous_head = store->head;
    bool had_head = store->has_head;

    size_t existing_index = 0;
    bool existed = find_block_index(store, &block_root, &existing_index);
    struct lantern_fork_choice_block_entry previous_entry;
    memset(&previous_entry, 0, sizeof(previous_entry));
    if (existed) {
        if (!store->blocks || existing_index >= store->block_len) {
            return -1;
        }
        previous_entry = store->blocks[existing_index];
    }

    size_t previous_block_len = store->block_len;

    if (register_block(
            store,
            &block_root,
            &block->parent_root,
            block->slot,
            block->proposer_index)
        != 0) {
        format_root_hex(&block_root, block_hex, sizeof(block_hex));
        format_root_hex(&block->parent_root, parent_hex, sizeof(parent_hex));
        lantern_log_warn(
            "forkchoice",
            &diag_meta,
            "add_block register failed slot=%" PRIu64 " root=%s parent=%s",
            block->slot,
            block_hex[0] ? block_hex : "0x0",
            parent_hex[0] ? parent_hex : "0x0");
        return -1;
    }
    if (update_latest_checkpoints(store, post_justified, post_finalized, false) != 0) {
        char justified_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
        char finalized_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
        char anchor_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
        bool post_justified_known =
            post_justified && checkpoint_known_in_store(store, post_justified);
        bool post_finalized_known =
            post_finalized && checkpoint_known_in_store(store, post_finalized);
        format_root_hex(&block_root, block_hex, sizeof(block_hex));
        format_root_hex(&block->parent_root, parent_hex, sizeof(parent_hex));
        format_root_hex(
            post_justified ? &post_justified->root : NULL,
            justified_hex,
            sizeof(justified_hex));
        format_root_hex(
            post_finalized ? &post_finalized->root : NULL,
            finalized_hex,
            sizeof(finalized_hex));
        format_root_hex(
            store->has_anchor ? &store->anchor_root : NULL,
            anchor_hex,
            sizeof(anchor_hex));
        lantern_log_warn(
            "forkchoice",
            &diag_meta,
            "add_block rejected checkpoints slot=%" PRIu64 " root=%s parent=%s"
            " anchor_slot=%" PRIu64 " anchor_root=%s post_justified_slot=%" PRIu64
            " post_justified_root=%s post_justified_known=%s"
            " post_finalized_slot=%" PRIu64 " post_finalized_root=%s"
            " post_finalized_known=%s",
            block->slot,
            block_hex[0] ? block_hex : "0x0",
            parent_hex[0] ? parent_hex : "0x0",
            store->anchor_slot,
            anchor_hex[0] ? anchor_hex : "0x0",
            post_justified ? post_justified->slot : 0u,
            justified_hex[0] ? justified_hex : "0x0",
            post_justified_known ? "true" : "false",
            post_finalized ? post_finalized->slot : 0u,
            finalized_hex[0] ? finalized_hex : "0x0",
            post_finalized_known ? "true" : "false");
        goto rollback;
    }

    if (lantern_fork_choice_recompute_head(store) != 0) {
        char justified_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
        char finalized_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
        format_root_hex(&block_root, block_hex, sizeof(block_hex));
        format_root_hex(&store->latest_justified.root, justified_hex, sizeof(justified_hex));
        format_root_hex(&store->latest_finalized.root, finalized_hex, sizeof(finalized_hex));
        lantern_log_warn(
            "forkchoice",
            &diag_meta,
            "add_block head recompute failed slot=%" PRIu64 " root=%s"
            " latest_justified_slot=%" PRIu64 " latest_justified_root=%s"
            " latest_finalized_slot=%" PRIu64 " latest_finalized_root=%s",
            block->slot,
            block_hex[0] ? block_hex : "0x0",
            store->latest_justified.slot,
            justified_hex[0] ? justified_hex : "0x0",
            store->latest_finalized.slot,
            finalized_hex[0] ? finalized_hex : "0x0");
        goto rollback;
    }
    if (post_state && lantern_fork_choice_set_block_state(store, &block_root, post_state) != 0) {
        format_root_hex(&block_root, block_hex, sizeof(block_hex));
        lantern_log_warn(
            "forkchoice",
            &diag_meta,
            "add_block failed to attach post-state slot=%" PRIu64 " root=%s",
            block->slot,
            block_hex[0] ? block_hex : "0x0");
        goto rollback;
    }
    lean_metrics_record_fork_choice_block_time(lantern_time_now_seconds() - metrics_start);
    fork_choice_publish_current_checkpoints(store);
    return 0;

rollback:
    store->latest_justified = previous_latest_justified;
    store->latest_finalized = previous_latest_finalized;
    store->head = previous_head;
    store->has_head = had_head;

    if (existed) {
        store->blocks[existing_index] = previous_entry;
    } else {
        store->block_len = previous_block_len;
    }

    return -1;
}

int lantern_fork_choice_update_checkpoints(
    LanternForkChoice *store,
    const LanternCheckpoint *latest_justified,
    const LanternCheckpoint *latest_finalized) {
    if (!store || !store->initialized) {
        return -1;
    }
    return update_latest_checkpoints(store, latest_justified, latest_finalized, true);
}

int lantern_fork_choice_restore_checkpoints(
    LanternForkChoice *store,
    const LanternCheckpoint *latest_justified,
    const LanternCheckpoint *latest_finalized) {
    if (!store || !store->initialized || !store->has_anchor) {
        return -1;
    }
    struct lantern_log_metadata meta = {0};
    char anchor_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    format_root_hex(&store->anchor_root, anchor_hex, sizeof(anchor_hex));

    LanternCheckpoint restored_latest_justified = store->latest_justified;
    LanternCheckpoint restored_latest_finalized = store->latest_finalized;

    if (latest_justified && !root_is_zero(&latest_justified->root)) {
        if (!checkpoint_known_in_store(store, latest_justified)) {
            char justified_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
            format_root_hex(&latest_justified->root, justified_hex, sizeof(justified_hex));
            lantern_log_warn(
                "forkchoice",
                &meta,
                "restore checkpoints missing justified checkpoint slot=%" PRIu64
                " root=%s anchor_slot=%" PRIu64 " anchor_root=%s block_len=%zu",
                latest_justified->slot,
                justified_hex[0] ? justified_hex : "0x0",
                store->anchor_slot,
                anchor_hex[0] ? anchor_hex : "0x0",
                store->block_len);
            return -1;
        }
        restored_latest_justified = *latest_justified;
    }
    if (latest_finalized && !root_is_zero(&latest_finalized->root)) {
        if (!checkpoint_known_in_store(store, latest_finalized)) {
            char finalized_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
            format_root_hex(&latest_finalized->root, finalized_hex, sizeof(finalized_hex));
            lantern_log_warn(
                "forkchoice",
                &meta,
                "restore checkpoints missing finalized checkpoint slot=%" PRIu64
                " root=%s anchor_slot=%" PRIu64 " anchor_root=%s block_len=%zu",
                latest_finalized->slot,
                finalized_hex[0] ? finalized_hex : "0x0",
                store->anchor_slot,
                anchor_hex[0] ? anchor_hex : "0x0",
                store->block_len);
            return -1;
        }
        restored_latest_finalized = *latest_finalized;
    }
    if (restored_latest_finalized.slot > restored_latest_justified.slot) {
        char justified_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
        char finalized_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
        format_root_hex(&restored_latest_justified.root, justified_hex, sizeof(justified_hex));
        format_root_hex(&restored_latest_finalized.root, finalized_hex, sizeof(finalized_hex));
        lantern_log_warn(
            "forkchoice",
            &meta,
            "restore checkpoints rejected ordering justified_slot=%" PRIu64
            " justified_root=%s finalized_slot=%" PRIu64 " finalized_root=%s",
            restored_latest_justified.slot,
            justified_hex[0] ? justified_hex : "0x0",
            restored_latest_finalized.slot,
            finalized_hex[0] ? finalized_hex : "0x0");
        return -1;
    }

    LanternCheckpoint previous_latest_justified = store->latest_justified;
    LanternCheckpoint previous_latest_finalized = store->latest_finalized;
    LanternRoot previous_head = store->head;
    bool previous_has_head = store->has_head;

    store->latest_justified = restored_latest_justified;
    store->latest_finalized = restored_latest_finalized;
    if (!root_is_zero(&restored_latest_justified.root)
        && lantern_fork_choice_recompute_head(store) != 0) {
        char justified_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
        char finalized_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
        format_root_hex(&restored_latest_justified.root, justified_hex, sizeof(justified_hex));
        format_root_hex(&restored_latest_finalized.root, finalized_hex, sizeof(finalized_hex));
        lantern_log_warn(
            "forkchoice",
            &meta,
            "restore checkpoints head recompute failed justified_slot=%" PRIu64
            " justified_root=%s finalized_slot=%" PRIu64 " finalized_root=%s",
            restored_latest_justified.slot,
            justified_hex[0] ? justified_hex : "0x0",
            restored_latest_finalized.slot,
            finalized_hex[0] ? finalized_hex : "0x0");
        store->latest_justified = previous_latest_justified;
        store->latest_finalized = previous_latest_finalized;
        store->head = previous_head;
        store->has_head = previous_has_head;
        return -1;
    }

    fork_choice_publish_current_checkpoints(store);
    return 0;
}

int lantern_fork_choice_prune_states(LanternForkChoice *store) {
    if (!store || !store->initialized || !store->has_anchor || !store->has_head) {
        return -1;
    }
    if (store->block_len == 0 || !store->states) {
        return 0;
    }
    if (store->state_cap < store->block_len) {
        return -1;
    }
    if (root_is_zero(&store->latest_finalized.root)) {
        return 0;
    }

    size_t head_index = 0;
    size_t finalized_index = 0;
    if (!find_block_index(store, &store->head, &head_index)
        || !find_block_index(store, &store->latest_finalized.root, &finalized_index)) {
        return -1;
    }
    if (head_index >= store->block_len || finalized_index >= store->block_len) {
        return -1;
    }

    uint8_t *canonical = calloc(store->block_len, sizeof(*canonical));
    if (!canonical) {
        return -1;
    }

    bool found_finalized = false;
    size_t current = head_index;
    while (current < store->block_len) {
        canonical[current] = 1u;
        if (current == finalized_index) {
            found_finalized = true;
            break;
        }
        size_t parent_index = 0;
        if (!parent_index_for_block(store, current, &parent_index)) {
            break;
        }
        current = parent_index;
    }

    if (!found_finalized) {
        free(canonical);
        return -1;
    }

    uint64_t finalized_slot = store->blocks[finalized_index].slot;
    uint8_t *keep_block = calloc(store->block_len, sizeof(*keep_block));
    size_t *old_to_new = malloc(store->block_len * sizeof(*old_to_new));
    if (!keep_block || !old_to_new) {
        free(canonical);
        free(keep_block);
        free(old_to_new);
        return -1;
    }
    for (size_t i = 0; i < store->block_len; ++i) {
        old_to_new[i] = SIZE_MAX;
        if (block_descends_from(store, i, finalized_index)) {
            keep_block[i] = 1u;
        }
    }
    if (!keep_block[head_index]) {
        free(canonical);
        free(keep_block);
        free(old_to_new);
        return -1;
    }

    size_t kept = 0;
    size_t evicted = 0;
    size_t total_with_state = 0;
    for (size_t i = 0; i < store->block_len; ++i) {
        struct lantern_fork_choice_state_entry *entry = &store->states[i];
        if (!entry->has_state) {
            continue;
        }
        total_with_state++;
        if (i == finalized_index) {
            kept++;
            continue;
        }
        if (canonical[i] && store->blocks[i].slot >= finalized_slot) {
            kept++;
            continue;
        }
        lantern_state_reset(&entry->state);
        entry->has_state = false;
        evicted++;
    }

    size_t blocks_before = store->block_len;
    size_t blocks_kept = 0;
    for (size_t i = 0; i < store->block_len; ++i) {
        if (keep_block[i]) {
            old_to_new[i] = blocks_kept++;
        }
    }

    if (blocks_kept < store->block_len) {
        struct lantern_fork_choice_block_entry *new_blocks = NULL;
        struct lantern_fork_choice_state_entry *new_states = NULL;
        if (blocks_kept > 0) {
            new_blocks = calloc(blocks_kept, sizeof(*new_blocks));
            new_states = calloc(blocks_kept, sizeof(*new_states));
            if (!new_blocks || !new_states) {
                free(new_blocks);
                free(new_states);
                free(canonical);
                free(keep_block);
                free(old_to_new);
                return -1;
            }
        }

        for (size_t old_index = 0; old_index < store->block_len; ++old_index) {
            size_t new_index = old_to_new[old_index];
            if (new_index == SIZE_MAX) {
                continue;
            }
            new_blocks[new_index] = store->blocks[old_index];
            new_states[new_index] = store->states[old_index];
        }

        for (size_t i = 0; i < store->block_len; ++i) {
            if (keep_block[i]) {
                continue;
            }
            if (store->states[i].has_state) {
                lantern_state_reset(&store->states[i].state);
                store->states[i].has_state = false;
            }
        }

        free(store->blocks);
        free(store->states);
        store->blocks = new_blocks;
        store->states = new_states;
        store->block_len = blocks_kept;
        store->block_cap = blocks_kept;
        store->state_cap = blocks_kept;
        store->anchor_root = store->latest_finalized.root;
        store->anchor_slot = finalized_slot;
        store->has_anchor = true;

        if (store->has_safe_target) {
            size_t safe_index = 0;
            if (!find_block_index(store, &store->safe_target, &safe_index)) {
                store->safe_target = store->latest_finalized.root;
            }
        }
        size_t justified_index = 0;
        if (!root_is_zero(&store->latest_justified.root)
            && !find_block_index(store, &store->latest_justified.root, &justified_index)) {
            store->latest_justified = store->latest_finalized;
        }
    }

    lantern_log_info(
        "forkchoice",
        NULL,
        "prune_states finalized_slot=%" PRIu64
        " blocks_before=%zu blocks_after=%zu states_before=%zu evicted=%zu kept=%zu",
        finalized_slot,
        blocks_before,
        store->block_len,
        total_with_state,
        evicted,
        kept);

    fork_choice_publish_current_checkpoints(store);
    free(old_to_new);
    free(keep_block);
    free(canonical);
    return 0;
}

static int find_start_index(
    const LanternForkChoice *store,
    const LanternRoot *start_root,
    size_t *out_index) {
    if (!store || store->block_len == 0) {
        return -1;
    }
    if (root_is_zero(start_root)) {
        size_t best = 0;
        uint64_t best_slot = store->blocks[0].slot;
        for (size_t i = 1; i < store->block_len; ++i) {
            if (store->blocks[i].slot < best_slot) {
                best_slot = store->blocks[i].slot;
                best = i;
            }
        }
        *out_index = best;
        return 0;
    }
    if (find_block_index(store, start_root, out_index)) {
        return 0;
    }
    return -1;
}

static int lmd_ghost_compute(
    const LanternForkChoice *store,
    const LanternRoot *start_root,
    const struct fork_choice_latest_vote *votes,
    size_t vote_count,
    uint64_t min_score,
    LanternRoot *out_head) {
    if (!store || !votes || !out_head) {
        return -1;
    }
    if (store->block_len == 0) {
        return -1;
    }
    size_t start_index = 0;
    if (find_start_index(store, start_root, &start_index) != 0) {
        return -1;
    }
    const struct lantern_fork_choice_block_entry *blocks = store->blocks;
    uint64_t start_slot = blocks[start_index].slot;

    uint64_t *weights = calloc(store->block_len, sizeof(uint64_t));
    if (!weights) {
        return -1;
    }

    for (size_t i = 0; i < vote_count; ++i) {
        const struct fork_choice_latest_vote *vote = &votes[i];
        if (!vote->has_checkpoint) {
            continue;
        }
        size_t node_index = 0;
        if (!find_block_index(store, &vote->checkpoint.root, &node_index)) {
            continue;
        }
        while (true) {
            if (node_index >= store->block_len) {
                break;
            }
            const struct lantern_fork_choice_block_entry *node = &blocks[node_index];
            if (node->slot <= start_slot) {
                break;
            }
            if (weights[node_index] < UINT64_MAX) {
                weights[node_index] += 1;
            }
            size_t parent = 0;
            if (!parent_index_for_block(store, node_index, &parent)) {
                break;
            }
            node_index = parent;
        }
    }

    size_t *best_child = malloc(store->block_len * sizeof(size_t));
    if (!best_child) {
        free(weights);
        return -1;
    }
    for (size_t i = 0; i < store->block_len; ++i) {
        best_child[i] = SIZE_MAX;
    }
    for (size_t i = 0; i < store->block_len; ++i) {
        size_t parent = 0;
        if (!parent_index_for_block(store, i, &parent)) {
            continue;
        }
        if (weights[i] < min_score) {
            continue;
        }
        size_t current_best = best_child[parent];
        bool better = false;
        if (current_best == SIZE_MAX) {
            better = true;
        } else if (weights[i] > weights[current_best]) {
            better = true;
        } else if (weights[i] == weights[current_best]) {
            if (root_compare(&blocks[i].root, &blocks[current_best].root) > 0) {
                better = true;
            }
        }
        if (better) {
            best_child[parent] = i;
        }
    }

    size_t current = start_index;
    while (best_child[current] != SIZE_MAX) {
        current = best_child[current];
    }
    *out_head = blocks[current].root;
    free(best_child);
    free(weights);
    return 0;
}

static void safe_target_consider_vote(
    struct fork_choice_latest_vote *merged_votes,
    uint64_t *latest_slots,
    size_t vote_count,
    size_t validator_index,
    const LanternCheckpoint *head,
    uint64_t attestation_slot) {
    if (!merged_votes || !latest_slots || !head || validator_index >= vote_count) {
        return;
    }
    struct fork_choice_latest_vote *merged = &merged_votes[validator_index];
    if (!merged->has_checkpoint || attestation_slot > latest_slots[validator_index]) {
        merged->checkpoint = *head;
        merged->has_checkpoint = true;
        latest_slots[validator_index] = attestation_slot;
    }
}

static const LanternAttestationData *safe_target_lookup_attestation_data(
    const LanternForkChoice *store,
    const LanternRoot *data_root) {
    if (!store || !store->attestation_data_by_root || !data_root) {
        return NULL;
    }
    const struct lantern_attestation_data_by_root *cache = store->attestation_data_by_root;
    for (size_t i = 0; i < cache->length; ++i) {
        if (memcmp(cache->entries[i].data_root.bytes, data_root->bytes, LANTERN_ROOT_SIZE) == 0) {
            return &cache->entries[i].data;
        }
    }
    return NULL;
}

static void safe_target_merge_payload_pool(
    const LanternForkChoice *store,
    const struct lantern_aggregated_payload_pool *pool,
    struct fork_choice_latest_vote *merged_votes,
    uint64_t *latest_slots,
    size_t vote_count) {
    if (!store || !pool || !merged_votes || !latest_slots || !pool->entries) {
        return;
    }
    for (size_t i = 0; i < pool->length; ++i) {
        const struct lantern_aggregated_payload_entry *entry = &pool->entries[i];
        const LanternAttestationData *attestation_data =
            safe_target_lookup_attestation_data(store, &entry->data_root);
        if (!attestation_data) {
            continue;
        }
        if (attestation_data->head.slot <= store->latest_finalized.slot) {
            continue;
        }
        const struct lantern_bitlist *participants = &entry->proof.participants;
        if (participants->bit_length == 0 || !participants->bytes) {
            continue;
        }
        size_t limit = participants->bit_length;
        if (limit > vote_count) {
            limit = vote_count;
        }
        for (size_t validator = 0; validator < limit; ++validator) {
            if (!lantern_bitlist_get(participants, validator)) {
                continue;
            }
            safe_target_consider_vote(
                merged_votes,
                latest_slots,
                vote_count,
                validator,
                &attestation_data->head,
                attestation_data->slot);
        }
    }
}

static int collect_payload_pool_votes(
    const LanternForkChoice *store,
    const struct lantern_aggregated_payload_pool *pool,
    struct fork_choice_latest_vote **out_votes,
    size_t *out_vote_count) {
    if (!store || !out_votes || !out_vote_count) {
        return -1;
    }
    *out_votes = NULL;
    *out_vote_count = 0;
    size_t vote_count = store->validator_count;
    struct fork_choice_latest_vote *votes = NULL;
    uint64_t *latest_slots = NULL;
    if (vote_count > 0) {
        votes = calloc(vote_count, sizeof(*votes));
        latest_slots = calloc(vote_count, sizeof(*latest_slots));
        if (!votes || !latest_slots) {
            free(votes);
            free(latest_slots);
            return -1;
        }
        safe_target_merge_payload_pool(store, pool, votes, latest_slots, vote_count);
    }
    free(latest_slots);
    *out_votes = votes;
    *out_vote_count = vote_count;
    return 0;
}

static bool fork_choice_has_attached_payload_views(const LanternForkChoice *store) {
    return store
        && store->new_aggregated_payloads
        && store->known_aggregated_payloads
        && store->attestation_data_by_root;
}

static int collect_known_weight_votes(
    const LanternForkChoice *store,
    struct fork_choice_latest_vote **out_votes,
    size_t *out_vote_count) {
    if (!store || !out_votes || !out_vote_count) {
        return -1;
    }
    return collect_payload_pool_votes(
        store,
        fork_choice_has_attached_payload_views(store) ? store->known_aggregated_payloads : NULL,
        out_votes,
        out_vote_count);
}

static int compute_known_block_weights(
    const LanternForkChoice *store,
    uint64_t *weights,
    size_t weight_count) {
    if (!store || !weights || weight_count < store->block_len) {
        return -1;
    }
    memset(weights, 0, weight_count * sizeof(*weights));
    if (store->block_len == 0) {
        return 0;
    }

    struct fork_choice_latest_vote *votes = NULL;
    size_t vote_count = 0;
    if (collect_known_weight_votes(store, &votes, &vote_count) != 0) {
        return -1;
    }

    uint64_t start_slot = store->latest_finalized.slot;
    for (size_t i = 0; i < vote_count; ++i) {
        const struct fork_choice_latest_vote *vote = &votes[i];
        if (!vote->has_checkpoint) {
            continue;
        }
        size_t node_index = 0;
        if (!find_block_index(store, &vote->checkpoint.root, &node_index)) {
            continue;
        }
        while (node_index < store->block_len) {
            const struct lantern_fork_choice_block_entry *node = &store->blocks[node_index];
            if (node->slot <= start_slot) {
                break;
            }
            if (weights[node_index] < UINT64_MAX) {
                weights[node_index] += 1u;
            }
            size_t parent = 0;
            if (!parent_index_for_block(store, node_index, &parent)) {
                break;
            }
            node_index = parent;
        }
    }

    free(votes);
    return 0;
}

static size_t fork_choice_reorg_depth(
    const LanternForkChoice *store,
    size_t old_index,
    size_t new_index) {
    if (!store || old_index >= store->block_len || new_index >= store->block_len) {
        return 0;
    }
    size_t depth = 0;
    uint64_t old_slot = store->blocks[old_index].slot;
    uint64_t new_slot = store->blocks[new_index].slot;

    while (old_index != new_index) {
        if (old_slot > new_slot) {
            size_t parent = 0;
            if (!parent_index_for_block(store, old_index, &parent)) {
                return 0;
            }
            old_index = parent;
            old_slot = store->blocks[old_index].slot;
            depth += 1;
            continue;
        }
        if (new_slot > old_slot) {
            size_t parent = 0;
            if (!parent_index_for_block(store, new_index, &parent)) {
                return 0;
            }
            new_index = parent;
            new_slot = store->blocks[new_index].slot;
            continue;
        }

        size_t old_parent = 0;
        size_t new_parent = 0;
        if (!parent_index_for_block(store, old_index, &old_parent)
            || !parent_index_for_block(store, new_index, &new_parent)) {
            return 0;
        }
        old_index = old_parent;
        new_index = new_parent;
        old_slot = store->blocks[old_index].slot;
        new_slot = store->blocks[new_index].slot;
        depth += 1;
    }

    return depth;
}

int lantern_fork_choice_recompute_head(LanternForkChoice *store) {
    if (!store || !store->initialized || !store->has_anchor) {
        return -1;
    }
    LanternRoot previous_head = store->head;
    bool had_head = store->has_head;
    LanternRoot head;
    struct fork_choice_latest_vote *votes = NULL;
    size_t vote_count = 0;
    if (collect_known_weight_votes(store, &votes, &vote_count) != 0) {
        return -1;
    }
    if (lmd_ghost_compute(
            store,
            &store->latest_justified.root,
            votes,
            vote_count,
            0,
            &head)
        != 0) {
        free(votes);
        return -1;
    }
    free(votes);
    store->head = head;
    store->has_head = true;

    if (had_head && root_compare(&previous_head, &head) != 0) {
        size_t old_index = 0;
        size_t new_index = 0;
        if (find_block_index(store, &previous_head, &old_index)
            && find_block_index(store, &head, &new_index)) {
            size_t depth = fork_choice_reorg_depth(store, old_index, new_index);
            if (depth > 0) {
                lean_metrics_record_fork_choice_reorg(depth);
            }
        }
    }

    return 0;
}

int lantern_fork_choice_accept_new_aggregated_payloads(LanternForkChoice *store) {
    if (!store || !store->initialized) {
        return -1;
    }
    return lantern_fork_choice_recompute_head(store);
}

int lantern_fork_choice_update_safe_target(LanternForkChoice *store) {
    if (!store || !store->initialized || !store->has_anchor) {
        return -1;
    }
    uint64_t validator_count = store->config.num_validators;
    if (store->has_head && store->blocks) {
        size_t head_index = 0;
        if (find_block_index(store, &store->head, &head_index) && head_index < store->block_len) {
            const struct lantern_fork_choice_block_entry *head_entry = &store->blocks[head_index];
            if (head_entry->has_validator_count && head_entry->validator_count > 0) {
                validator_count = head_entry->validator_count;
            }
        }
    }
    uint64_t threshold = lantern_consensus_quorum_threshold(validator_count);
    struct fork_choice_latest_vote *safe_votes = NULL;
    size_t safe_vote_count = 0;
    if (collect_payload_pool_votes(
            store,
            store->new_aggregated_payloads,
            &safe_votes,
            &safe_vote_count)
        != 0) {
        return -1;
    }
    LanternRoot safe;
    if (lmd_ghost_compute(
            store,
            &store->latest_justified.root,
            safe_votes,
            safe_vote_count,
            threshold,
            &safe)
        != 0) {
        free(safe_votes);
        return -1;
    }
    free(safe_votes);
    store->safe_target = safe;
    store->has_safe_target = true;
    return 0;
}

static int tick_interval(LanternForkChoice *store, bool has_proposal) {
    if (!store) {
        return -1;
    }
    store->time_intervals += 1;
    uint64_t current_interval = store->time_intervals % store->intervals_per_slot;
    switch (current_interval) {
    case 0:
        if (has_proposal) {
            return lantern_fork_choice_accept_new_aggregated_payloads(store);
        }
        return 0;
    case 1:
        /* Interval 1: collect new votes, no store mutation. */
        return 0;
    case 2:
        /* Interval 2: committee aggregation handled at validator layer. */
        return 0;
    case 3:
        return lantern_fork_choice_update_safe_target(store);
    case 4:
        return lantern_fork_choice_accept_new_aggregated_payloads(store);
    default:
        return 0;
    }
}

int lantern_fork_choice_advance_time(
    LanternForkChoice *store,
    uint64_t now_milliseconds,
    bool has_proposal) {
    if (!store || !store->initialized || !store->has_anchor) {
        return -1;
    }
    uint64_t genesis_milliseconds =
        (uint64_t)store->config.genesis_time * LANTERN_FORK_CHOICE_MILLISECONDS_PER_SECOND;
    if (now_milliseconds < genesis_milliseconds) {
        /* Before genesis - no time to advance yet, but this is not an error */
        return 0;
    }
    if (store->milliseconds_per_interval == 0) {
        return -1;
    }
    uint64_t elapsed = now_milliseconds - genesis_milliseconds;
    uint64_t target_interval = elapsed / store->milliseconds_per_interval;
    while (store->time_intervals < target_interval) {
        bool will_propose = has_proposal && (store->time_intervals + 1 == target_interval);
        if (tick_interval(store, will_propose) != 0) {
            return -1;
        }
    }
    return 0;
}

int lantern_fork_choice_current_head(const LanternForkChoice *store, LanternRoot *out_head) {
    if (!store || !out_head || !store->has_head) {
        return -1;
    }
    *out_head = store->head;
    return 0;
}

int lantern_fork_choice_block_info(
    const LanternForkChoice *store,
    const LanternRoot *root,
    uint64_t *out_slot,
    LanternRoot *out_parent_root,
    bool *out_has_parent) {
    if (!store || !store->initialized || !root) {
        return -1;
    }
    size_t index = 0;
    if (!find_block_index(store, root, &index)) {
        return -1;
    }
    if (!store->blocks || index >= store->block_len) {
        return -1;
    }
    const struct lantern_fork_choice_block_entry *entry = &store->blocks[index];
    if (out_slot) {
        *out_slot = entry->slot;
    }
    if (out_parent_root) {
        *out_parent_root = entry->parent_root;
    }
    if (out_has_parent) {
        size_t parent = 0;
        *out_has_parent = parent_index_for_block(store, index, &parent);
    }
    return 0;
}

const LanternCheckpoint *lantern_fork_choice_latest_justified(const LanternForkChoice *store) {
    if (!store) {
        return NULL;
    }
    return &store->latest_justified;
}

const LanternCheckpoint *lantern_fork_choice_latest_finalized(const LanternForkChoice *store) {
    if (!store) {
        return NULL;
    }
    return &store->latest_finalized;
}

bool lantern_fork_choice_read_checkpoint_snapshot(
    const LanternForkChoice *store,
    LanternCheckpoint *out_justified,
    LanternCheckpoint *out_finalized) {
    if (!store || (!out_justified && !out_finalized)) {
        return false;
    }

    const struct lantern_fork_choice_checkpoint_snapshot *snapshot = &store->checkpoint_snapshot;
    for (;;) {
        uint64_t before = atomic_load_explicit(&snapshot->sequence, memory_order_acquire);
        if (before == 0u) {
            return false;
        }
        if ((before & 1u) != 0u) {
            continue;
        }

        LanternCheckpoint justified;
        LanternCheckpoint finalized;
        memset(&justified, 0, sizeof(justified));
        memset(&finalized, 0, sizeof(finalized));
        justified.slot = atomic_load_explicit(&snapshot->justified_slot, memory_order_relaxed);
        finalized.slot = atomic_load_explicit(&snapshot->finalized_slot, memory_order_relaxed);
        for (size_t i = 0; i < LANTERN_ROOT_SIZE; ++i) {
            justified.root.bytes[i] =
                atomic_load_explicit(&snapshot->justified_root[i], memory_order_relaxed);
            finalized.root.bytes[i] =
                atomic_load_explicit(&snapshot->finalized_root[i], memory_order_relaxed);
        }

        uint64_t after = atomic_load_explicit(&snapshot->sequence, memory_order_acquire);
        if (before == after && (after & 1u) == 0u) {
            if (out_justified) {
                *out_justified = justified;
            }
            if (out_finalized) {
                *out_finalized = finalized;
            }
            return true;
        }
    }
}

const LanternRoot *lantern_fork_choice_safe_target(const LanternForkChoice *store) {
    if (!store || !store->has_safe_target) {
        return NULL;
    }
    return &store->safe_target;
}

void lantern_fork_choice_tree_snapshot_reset(struct lantern_fork_choice_tree_snapshot *snapshot) {
    if (!snapshot) {
        return;
    }
    free(snapshot->nodes);
    memset(snapshot, 0, sizeof(*snapshot));
}

int lantern_fork_choice_snapshot_tree(
    const LanternForkChoice *store,
    struct lantern_fork_choice_tree_snapshot *out_snapshot) {
    if (!store || !out_snapshot || !store->initialized || !store->has_anchor || !store->has_head) {
        return -1;
    }
    memset(out_snapshot, 0, sizeof(*out_snapshot));

    uint64_t *weights = NULL;
    if (store->block_len > 0) {
        weights = calloc(store->block_len, sizeof(*weights));
        if (!weights) {
            return -1;
        }
        if (compute_known_block_weights(store, weights, store->block_len) != 0) {
            free(weights);
            return -1;
        }
    }

    uint64_t finalized_slot = store->latest_finalized.slot;
    size_t node_count = 0;
    for (size_t i = 0; i < store->block_len; ++i) {
        if (store->blocks[i].slot >= finalized_slot) {
            node_count += 1u;
        }
    }

    struct lantern_fork_choice_tree_node *nodes = NULL;
    if (node_count > 0) {
        nodes = calloc(node_count, sizeof(*nodes));
        if (!nodes) {
            free(weights);
            return -1;
        }
    }

    size_t next = 0;
    for (size_t i = 0; i < store->block_len; ++i) {
        const struct lantern_fork_choice_block_entry *entry = &store->blocks[i];
        if (entry->slot < finalized_slot) {
            continue;
        }
        nodes[next].root = entry->root;
        nodes[next].slot = entry->slot;
        nodes[next].parent_root = entry->parent_root;
        nodes[next].proposer_index = entry->proposer_index;
        nodes[next].weight = weights ? weights[i] : 0u;
        next += 1u;
    }

    out_snapshot->nodes = nodes;
    out_snapshot->node_count = node_count;
    out_snapshot->head = store->head;
    out_snapshot->justified = store->latest_justified;
    out_snapshot->finalized = store->latest_finalized;
    if (store->has_safe_target) {
        out_snapshot->safe_target = store->safe_target;
    } else {
        zero_root(&out_snapshot->safe_target);
    }

    free(weights);
    return 0;
}
