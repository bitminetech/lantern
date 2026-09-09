#include "lantern/consensus/fork_choice.h"

#include <limits.h>
#include <stdlib.h>
#include <string.h>

#include "lantern/consensus/hash.h"
#include "lantern/consensus/quorum.h"
#include "lantern/consensus/slot_clock.h"
#include "lantern/metrics/lean_metrics.h"
#include "lantern/support/time.h"

enum
{
    POST_STATE_CACHE_CAPACITY = 10,
};

/* Retain roots rather than entry addresses: block-array growth can relocate entries. */
struct lantern_post_state_cache
{
    struct lantern_state_storage storage;
    LanternRoot roots[POST_STATE_CACHE_CAPACITY];
    size_t length;
};

static const size_t s_post_state_cache_bytes = 64u * 1024u * 1024u;

struct lantern_fork_choice_root_index_entry {
    bool occupied;
    LanternRoot root;
    size_t block_index;
};

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

static void fork_choice_publish_current_checkpoints(LanternStore *store) {
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

static uint64_t root_hash(const LanternRoot *root) {
    uint64_t hash = UINT64_C(14695981039346656037);
    for (size_t i = 0u; i < LANTERN_ROOT_SIZE; ++i) {
        hash ^= root->bytes[i];
        hash *= UINT64_C(1099511628211);
    }
    return hash;
}

static bool root_index_lookup(
    const LanternStore *store,
    const LanternRoot *root,
    size_t *out_index) {
    if (!store || !root || !store->root_index || store->root_index_cap == 0u) {
        return false;
    }
    size_t slot = (size_t)(root_hash(root) % store->root_index_cap);
    for (size_t checked = 0u; checked < store->root_index_cap; ++checked) {
        const struct lantern_fork_choice_root_index_entry *entry =
            &store->root_index[slot];
        if (!entry->occupied) {
            return false;
        }
        if (root_compare(&entry->root, root) == 0) {
            if (out_index) {
                *out_index = entry->block_index;
            }
            return true;
        }
        slot = (slot + 1u) % store->root_index_cap;
    }
    return false;
}

static void root_index_insert(
    struct lantern_fork_choice_root_index_entry *entries,
    size_t capacity,
    const LanternRoot *root,
    size_t block_index) {
    size_t slot = (size_t)(root_hash(root) % capacity);
    while (entries[slot].occupied) {
        if (root_compare(&entries[slot].root, root) == 0) {
            entries[slot].block_index = block_index;
            return;
        }
        slot = (slot + 1u) % capacity;
    }
    entries[slot].occupied = true;
    entries[slot].root = *root;
    entries[slot].block_index = block_index;
}

static int rebuild_root_index(LanternStore *store, size_t required_blocks) {
    if (!store) {
        return -1;
    }
    if (required_blocks == 0u) {
        free(store->root_index);
        store->root_index = NULL;
        store->root_index_cap = 0u;
        return 0;
    }
    if (required_blocks > SIZE_MAX / 2u) {
        return -1;
    }
    size_t capacity = 8u;
    while (capacity < required_blocks * 2u) {
        if (capacity > SIZE_MAX / 2u) {
            return -1;
        }
        capacity *= 2u;
    }
    struct lantern_fork_choice_root_index_entry *entries =
        calloc(capacity, sizeof(*entries));
    if (!entries) {
        return -1;
    }
    for (size_t i = 0u; i < store->block_len; ++i) {
        root_index_insert(entries, capacity, &store->blocks[i].root, i);
    }
    free(store->root_index);
    store->root_index = entries;
    store->root_index_cap = capacity;
    return 0;
}

static int ensure_root_index_capacity(LanternStore *store, size_t required_blocks) {
    if (!store) {
        return -1;
    }
    if (store->root_index
        && required_blocks <= store->root_index_cap / 2u) {
        return 0;
    }
    return rebuild_root_index(store, required_blocks);
}

static void refresh_root_index(LanternStore *store) {
    if (!store || rebuild_root_index(store, store->block_len) == 0) {
        return;
    }
    free(store->root_index);
    store->root_index = NULL;
    store->root_index_cap = 0u;
}

static bool find_block_index(const LanternStore *store, const LanternRoot *root, size_t *out_index) {
    if (!store || !root || !store->blocks) {
        return false;
    }
    if (store->root_index) {
        return root_index_lookup(store, root, out_index);
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

static size_t post_state_bytes(const LanternState *state)
{
    /* Cloned/decoded states own these buffers; transient Merkle caches are not cloned. */
    return sizeof(*state)
        + state->historical_block_hashes.capacity * sizeof(LanternRoot)
        + state->justification_roots.capacity * sizeof(LanternRoot)
        + state->justified_slots.capacity
        + state->justification_validators.capacity
        + state->validator_count * sizeof(*state->validators);
}

static void state_cache_forget(const LanternStore *store, const LanternRoot *root)
{
    struct lantern_post_state_cache *cache = store->state_cache;
    if (!cache)
    {
        return;
    }

    for (size_t i = 0; i < cache->length; ++i)
    {
        if (root_compare(&cache->roots[i], root) == 0)
        {
            memmove(&cache->roots[i], &cache->roots[i + 1u],
                (cache->length - i - 1u) * sizeof(*cache->roots));
            --cache->length;
            return;
        }
    }
}

static void state_cache_touch(const LanternStore *store, const LanternRoot *root)
{
    struct lantern_post_state_cache *cache = store->state_cache;
    if (!cache)
    {
        return;
    }

    state_cache_forget(store, root);
    cache->roots[cache->length++] = *root;
}

static void state_cache_make_room(
    const LanternStore *store, const LanternRoot *root, const LanternState *state)
{
    struct lantern_post_state_cache *cache = store->state_cache;
    if (!cache)
    {
        return;
    }

    for (;;)
    {
        size_t bytes = post_state_bytes(state);
        size_t count = 1u;
        size_t victim = SIZE_MAX;
        size_t victim_index = 0u;
        for (size_t i = 0; i < cache->length; ++i)
        {
            if (root_compare(&cache->roots[i], root) == 0)
            {
                continue;
            }

            size_t index = 0u;
            if (!find_block_index(store, &cache->roots[i], &index))
            {
                continue;
            }

            size_t entry_bytes = post_state_bytes(&store->blocks[index].state);
            bytes = entry_bytes > SIZE_MAX - bytes ? SIZE_MAX : bytes + entry_bytes;
            ++count;
            if (victim == SIZE_MAX && root_compare(&cache->roots[i], &store->head) != 0)
            {
                victim = i;
                victim_index = index;
            }
        }

        if ((count <= sizeof(cache->roots) / sizeof(*cache->roots)
                && bytes <= s_post_state_cache_bytes)
            || victim == SIZE_MAX)
        {
            return;
        }

        LanternRoot victim_root = cache->roots[victim];
        state_cache_forget(store, &victim_root);
        lantern_state_reset(&store->blocks[victim_index].state);
    }
}

static int state_cache_prepare(
    const LanternStore *store, const LanternRoot *root, const LanternState *state)
{
    if (store->state_cache
        && store->state_cache->storage.save(
            store->state_cache->storage.context, root, state) != 0)
    {
        return -1;
    }

    state_cache_make_room(store, root, state);
    return 0;
}

int lantern_fork_choice_set_state_storage(
    LanternStore *store, const struct lantern_state_storage *storage)
{
    if (!store || !storage || !storage->load || !storage->save
        || store->block_len != 0u || store->state_cache)
    {
        return -1;
    }

    struct lantern_post_state_cache *cache = calloc(1u, sizeof(*cache));
    if (!cache)
    {
        return -1;
    }

    cache->storage = *storage;
    store->state_cache = cache;
    return 0;
}

static void block_states_reset(LanternStore *store) {
    if (!store || !store->blocks) {
        return;
    }
    for (size_t i = 0; i < store->block_len; ++i) {
        struct lantern_fork_choice_block_entry *entry = &store->blocks[i];
        if (entry->state.validator_count == 0u) {
            continue;
        }
        lantern_state_reset(&entry->state);
    }
}

static int ensure_block_capacity(LanternStore *store, size_t required) {
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

    store->block_cap = capacity;
    return 0;
}

static bool parent_index_for_block(const LanternStore *store, size_t block_index, size_t *out_parent) {
    if (!store || !store->blocks || block_index >= store->block_len || !out_parent) {
        return false;
    }
    const LanternRoot *parent_root = &store->blocks[block_index].parent_root;
    if (lantern_root_is_zero(parent_root)) {
        return false;
    }
    if (find_block_index(store, parent_root, out_parent)) {
        return true;
    }
    return false;
}

static const LanternState *state_for_block_index(
    const LanternStore *store,
    size_t index) {
    if (!store || !store->blocks || index >= store->block_len) {
        return NULL;
    }
    const struct lantern_fork_choice_block_entry *entry = &store->blocks[index];
    return entry->state.validator_count > 0u ? &entry->state : NULL;
}

static int fork_choice_validator_count(const LanternStore *store, size_t *out_count) {
    size_t head_index = 0u;
    if (!store || store->block_len == 0u
        || !out_count
        || !find_block_index(store, &store->head, &head_index)) {
        return -1;
    }
    const LanternState *state = lantern_fork_choice_block_state(store, &store->head);

    if (!state && !store->state_cache) {
        size_t anchor_index = 0u;
        if (find_block_index(store, &store->anchor.root, &anchor_index)) {
            state = state_for_block_index(store, anchor_index);
        }
    }
    if (!state) {
        return -1;
    }
    *out_count = state->validator_count;
    return 0;
}

static bool block_descends_from(
    const LanternStore *store,
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

void lantern_fork_choice_reset(LanternStore *store) {
    if (!store) {
        return;
    }
    struct lantern_attestation_signature_map attestation_signatures = store->attestation_signatures;
    struct lantern_aggregated_payload_pool new_payloads = store->new_aggregated_payloads;
    struct lantern_aggregated_payload_pool known_payloads = store->known_aggregated_payloads;
    struct lantern_latest_vote_map new_votes = store->new_votes;
    struct lantern_latest_vote_map known_votes = store->known_votes;
    block_states_reset(store);
    free(store->blocks);
    free(store->root_index);
    free(store->state_cache);
    lantern_store_init(store);
    store->attestation_signatures = attestation_signatures;
    store->new_aggregated_payloads = new_payloads;
    store->known_aggregated_payloads = known_payloads;
    store->new_votes = new_votes;
    store->known_votes = known_votes;
}

static int register_block(
    LanternStore *store,
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
    if (ensure_root_index_capacity(store, store->block_len + 1u) != 0
        || ensure_block_capacity(store, store->block_len + 1u) != 0) {
        return -1;
    }
    size_t block_index = store->block_len;
    struct lantern_fork_choice_block_entry *entry = &store->blocks[block_index];
    entry->root = *root;
    if (parent_root) {
        entry->parent_root = *parent_root;
    } else {
        lantern_root_zero(&entry->parent_root);
    }
    entry->slot = slot;
    entry->proposer_index = proposer_index;
    store->block_len += 1;
    root_index_insert(store->root_index, store->root_index_cap, root, block_index);
    return 0;
}

int lantern_fork_choice_set_block_state(
    LanternStore *store,
    const LanternRoot *root,
    const LanternState *state) {
    if (!store || !root || !state) {
        return -1;
    }
    size_t index = 0;
    if (!find_block_index(store, root, &index)) {
        return -1;
    }
    LanternState cloned;
    lantern_state_init(&cloned);
    if (lantern_state_clone(state, &cloned) != 0) {
        lantern_state_reset(&cloned);
        return -1;
    }

    if (state_cache_prepare(store, root, &cloned) != 0)
    {
        lantern_state_reset(&cloned);
        return -1;
    }

    struct lantern_fork_choice_block_entry *entry = &store->blocks[index];
    if (entry->state.validator_count > 0u) {
        lantern_state_reset(&entry->state);
    }
    entry->state = cloned;
    state_cache_touch(store, root);
    return 0;
}

const LanternState *lantern_fork_choice_block_state(
    const LanternStore *store,
    const LanternRoot *root) {
    if (!store || !root) {
        return NULL;
    }
    size_t index = 0;
    if (!find_block_index(store, root, &index)) {
        return NULL;
    }
    struct lantern_fork_choice_block_entry *entry = &store->blocks[index];
    if (entry->state.validator_count == 0u && store->state_cache)
    {
        LanternState loaded;
        lantern_state_init(&loaded);
        struct lantern_state_storage *storage = &store->state_cache->storage;
        if (storage->load(storage->context, root, &loaded) != 0
            || loaded.validator_count == 0u)
        {
            lantern_state_reset(&loaded);
            return NULL;
        }

        state_cache_make_room(store, root, &loaded);
        entry->state = loaded;
    }

    if (entry->state.validator_count == 0u)
    {
        return NULL;
    }

    state_cache_touch(store, root);
    return &entry->state;
}

int lantern_fork_choice_set_anchor_with_state(
    LanternStore *store,
    const LanternBlock *anchor_block,
    const LanternCheckpoint *latest_justified,
    const LanternCheckpoint *latest_finalized,
    const LanternRoot *block_root_hint,
    const LanternState *anchor_state) {
    if (!store || !anchor_block || !anchor_state || anchor_state->validator_count == 0u
        || anchor_block->slot > UINT64_MAX / LANTERN_INTERVALS_PER_SLOT) {
        return -1;
    }
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
    LanternCheckpoint previous_anchor = store->anchor;
    LanternRoot previous_head = store->head;
    LanternRoot previous_safe_target = store->safe_target;
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
    LanternCheckpoint anchor_checkpoint = {
        .root = root,
        .slot = anchor_block->slot,
    };
    store->latest_justified = latest_justified ? *latest_justified : anchor_checkpoint;
    store->latest_finalized = latest_finalized ? *latest_finalized : anchor_checkpoint;
    store->head = root;
    store->safe_target = root;
    store->anchor = anchor_checkpoint;
    store->time_intervals = anchor_block->slot * LANTERN_INTERVALS_PER_SLOT;
    if (lantern_fork_choice_set_block_state(store, &root, anchor_state) != 0) {
        store->latest_justified = previous_latest_justified;
        store->latest_finalized = previous_latest_finalized;
        store->anchor = previous_anchor;
        store->head = previous_head;
        store->safe_target = previous_safe_target;
        store->time_intervals = previous_time_intervals;
        if (existed) {
            store->blocks[existing_index] = previous_entry;
        } else {
            store->block_len = previous_block_len;
            refresh_root_index(store);
        }
        return -1;
    }
    fork_choice_publish_current_checkpoints(store);
    return 0;
}

static bool checkpoint_known_in_store(
    const LanternStore *store,
    const LanternCheckpoint *checkpoint) {
    if (!store || !checkpoint || lantern_root_is_zero(&checkpoint->root)) {
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
    if (!current || !candidate || lantern_root_is_zero(&candidate->root)) {
        return false;
    }
    return candidate->slot > current->slot;
}

static bool derive_finalized_from_head_state(
    const LanternStore *store,
    const LanternRoot *head,
    LanternCheckpoint *out_finalized) {
    if (!store || !head || !out_finalized) {
        return false;
    }

    size_t current = 0;
    if (!find_block_index(store, head, &current)) {
        return false;
    }
    const LanternState *head_state = lantern_fork_choice_block_state(store, head);
    if (!head_state) {
        return false;
    }

    uint64_t finalized_slot = head_state->latest_finalized.slot;
    for (size_t depth = 0; depth < store->block_len && current < store->block_len; ++depth) {
        const struct lantern_fork_choice_block_entry *entry = &store->blocks[current];
        if (entry->slot == finalized_slot) {
            out_finalized->root = entry->root;
            out_finalized->slot = finalized_slot;
            return true;
        }
        if (entry->slot < finalized_slot) {
            return false;
        }

        size_t parent = 0;
        if (!parent_index_for_block(store, current, &parent)) {
            return false;
        }
        current = parent;
    }
    return false;
}

static bool refresh_finalized_from_head_state(LanternStore *store) {
    if (!store || store->block_len == 0u) {
        return false;
    }

    LanternCheckpoint finalized = {0};
    if (!derive_finalized_from_head_state(store, &store->head, &finalized)) {
        return false;
    }
    if (store->latest_finalized.slot == finalized.slot
        && root_compare(&store->latest_finalized.root, &finalized.root) == 0) {
        return false;
    }

    store->latest_finalized = finalized;
    return true;
}

static int update_latest_checkpoints(
    LanternStore *store,
    const LanternCheckpoint *post_justified,
    const LanternCheckpoint *post_finalized,
    bool publish_snapshot) {
    if (!store) {
        return -1;
    }
    LanternCheckpoint latest_justified = store->latest_justified;
    LanternCheckpoint latest_finalized = store->latest_finalized;

    if (post_justified && !lantern_root_is_zero(&post_justified->root)) {
        if (should_replace_checkpoint(&latest_justified, post_justified)) {
            if (!checkpoint_known_in_store(store, post_justified)) {
                return -1;
            }
            latest_justified = *post_justified;
        }
    }
    if (post_finalized && !lantern_root_is_zero(&post_finalized->root)) {
        if (should_replace_checkpoint(&latest_finalized, post_finalized)) {
            if (!checkpoint_known_in_store(store, post_finalized)) {
                return -1;
            }
            latest_finalized = *post_finalized;
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
    LanternStore *store,
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
    LanternStore *store,
    const LanternBlock *block,
    const LanternCheckpoint *post_justified,
    const LanternCheckpoint *post_finalized,
    const LanternRoot *block_root_hint,
    const LanternState *post_state) {
    if (!store || store->block_len == 0u || !block) {
        return -1;
    }
    double metrics_start;
    enum lantern_time_result metrics_start_result =
        lantern_time_now_seconds(&metrics_start);
    LanternRoot block_root;
    if (block_root_hint) {
        block_root = *block_root_hint;
    } else {
        if (lantern_hash_tree_root_block(block, &block_root) != SSZ_SUCCESS) {
            return -1;
        }
    }
    LanternCheckpoint previous_latest_justified = store->latest_justified;
    LanternCheckpoint previous_latest_finalized = store->latest_finalized;
    LanternRoot previous_head = store->head;

    size_t existing_index = 0;
    bool existed = find_block_index(store, &block_root, &existing_index);
    if (!existed && block->slot >= store->anchor.slot
        && !find_block_index(store, &block->parent_root, &existing_index)) {
        return -1;
    }
    struct lantern_fork_choice_block_entry previous_entry;
    memset(&previous_entry, 0, sizeof(previous_entry));
    if (existed) {
        if (!store->blocks || existing_index >= store->block_len) {
            return -1;
        }
        previous_entry = store->blocks[existing_index];
    }

    size_t previous_block_len = store->block_len;
    LanternState staged_state;
    LanternState previous_state;
    lantern_state_init(&staged_state);
    lantern_state_init(&previous_state);
    if (post_state && lantern_state_clone(post_state, &staged_state) != 0) {
        lantern_state_reset(&staged_state);
        return -1;
    }

    if (post_state && state_cache_prepare(store, &block_root, &staged_state) != 0)
    {
        lantern_state_reset(&staged_state);
        return -1;
    }

    if (register_block(
            store,
            &block_root,
            &block->parent_root,
            block->slot,
            block->proposer_index)
        != 0) {
        lantern_state_reset(&staged_state);
        return -1;
    }
    size_t block_index = existed ? existing_index : previous_block_len;
    if (post_state) {
        previous_state = store->blocks[block_index].state;
        store->blocks[block_index].state = staged_state;
        state_cache_touch(store, &block_root);
        lantern_state_init(&staged_state);
    }

    const LanternCheckpoint *effective_post_finalized = post_state ? NULL : post_finalized;
    if (update_latest_checkpoints(store, post_justified, effective_post_finalized, false) != 0) {
        goto rollback;
    }

    if (lantern_fork_choice_recompute_head(store) != 0) {
        goto rollback;
    }
    lantern_state_reset(&previous_state);
    double metrics_end;
    double metrics_elapsed = 0.0;
    if (metrics_start_result != LANTERN_TIME_OK
        || lantern_time_now_seconds(&metrics_end) != LANTERN_TIME_OK
        || lantern_time_elapsed_seconds(
               metrics_start,
               metrics_end,
               &metrics_elapsed)
               != LANTERN_TIME_OK) {
        metrics_elapsed = 0.0;
    }
    lean_metrics_record_fork_choice_block_time(metrics_elapsed);
    fork_choice_publish_current_checkpoints(store);
    return 0;

rollback:
    store->latest_justified = previous_latest_justified;
    store->latest_finalized = previous_latest_finalized;
    store->head = previous_head;

    if (post_state) {
        state_cache_forget(store, &block_root);
        lantern_state_reset(&store->blocks[block_index].state);
        store->blocks[block_index].state = previous_state;
        if (previous_state.validator_count > 0u)
        {
            state_cache_make_room(store, &block_root, &previous_state);
            state_cache_touch(store, &block_root);
        }
        lantern_state_init(&previous_state);
    }

    if (existed) {
        store->blocks[existing_index] = previous_entry;
    } else {
        store->block_len = previous_block_len;
        refresh_root_index(store);
    }

    lantern_state_reset(&staged_state);
    lantern_state_reset(&previous_state);
    return -1;
}

int lantern_fork_choice_update_checkpoints(
    LanternStore *store,
    const LanternCheckpoint *latest_justified,
    const LanternCheckpoint *latest_finalized) {
    if (!store || store->block_len == 0u) {
        return -1;
    }
    return update_latest_checkpoints(store, latest_justified, latest_finalized, true);
}

int lantern_fork_choice_restore_checkpoints(
    LanternStore *store,
    const LanternCheckpoint *latest_justified,
    const LanternCheckpoint *latest_finalized) {
    if (!store || store->block_len == 0u) {
        return -1;
    }
    LanternCheckpoint restored_latest_justified = store->latest_justified;
    LanternCheckpoint restored_latest_finalized = store->latest_finalized;

    if (latest_justified && !lantern_root_is_zero(&latest_justified->root)) {
        if (!checkpoint_known_in_store(store, latest_justified)) {
            return -1;
        }
        restored_latest_justified = *latest_justified;
    }
    if (latest_finalized && !lantern_root_is_zero(&latest_finalized->root)) {
        if (!checkpoint_known_in_store(store, latest_finalized)) {
            return -1;
        }
        restored_latest_finalized = *latest_finalized;
    }
    if (restored_latest_finalized.slot > restored_latest_justified.slot) {
        return -1;
    }

    LanternCheckpoint previous_latest_justified = store->latest_justified;
    LanternCheckpoint previous_latest_finalized = store->latest_finalized;
    LanternRoot previous_head = store->head;

    store->latest_justified = restored_latest_justified;
    store->latest_finalized = restored_latest_finalized;
    if (!lantern_root_is_zero(&restored_latest_justified.root)
        && lantern_fork_choice_recompute_head(store) != 0) {
        store->latest_justified = previous_latest_justified;
        store->latest_finalized = previous_latest_finalized;
        store->head = previous_head;
        return -1;
    }

    fork_choice_publish_current_checkpoints(store);
    return 0;
}

int lantern_fork_choice_prune_states(LanternStore *store) {
    if (!store || store->block_len == 0u) {
        return -1;
    }
    if (lantern_root_is_zero(&store->latest_finalized.root)) {
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
    size_t blocks_kept = 0;
    for (size_t i = 0; i < store->block_len; ++i) {
        old_to_new[i] = SIZE_MAX;
        if (block_descends_from(store, i, finalized_index)) {
            keep_block[i] = 1u;
            old_to_new[i] = blocks_kept++;
        }
    }
    if (!keep_block[head_index]) {
        free(canonical);
        free(keep_block);
        free(old_to_new);
        return -1;
    }
    if (blocks_kept < store->block_len && !lantern_fork_choice_block_state(store, &store->blocks[finalized_index].root)) {
        free(canonical);
        free(keep_block);
        free(old_to_new);
        return -1;
    }

    for (size_t i = 0; i < store->block_len; ++i) {
        struct lantern_fork_choice_block_entry *entry = &store->blocks[i];
        if (entry->state.validator_count == 0u) {
            continue;
        }
        if (i == finalized_index) {
            continue;
        }
        if (canonical[i] && store->blocks[i].slot >= finalized_slot) {
            continue;
        }
        state_cache_forget(store, &entry->root);
        lantern_state_reset(&entry->state);
    }

    if (blocks_kept < store->block_len) {
        struct lantern_fork_choice_block_entry *new_blocks = NULL;
        if (blocks_kept > 0) {
            new_blocks = calloc(blocks_kept, sizeof(*new_blocks));
            if (!new_blocks) {
                free(new_blocks);
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
        }

        for (size_t i = 0; i < store->block_len; ++i) {
            if (keep_block[i]) {
                continue;
            }
            if (store->blocks[i].state.validator_count > 0u) {
                lantern_state_reset(&store->blocks[i].state);
            }
        }

        free(store->blocks);
        store->blocks = new_blocks;
        store->block_len = blocks_kept;
        store->block_cap = blocks_kept;
        store->anchor = store->latest_finalized;
        refresh_root_index(store);

        size_t safe_index = 0;
        if (!find_block_index(store, &store->safe_target, &safe_index)) {
            store->safe_target = store->latest_finalized.root;
        }
        size_t justified_index = 0;
        if (!lantern_root_is_zero(&store->latest_justified.root)
            && !find_block_index(store, &store->latest_justified.root, &justified_index)) {
            store->latest_justified = store->latest_finalized;
        }
    }

    fork_choice_publish_current_checkpoints(store);
    free(old_to_new);
    free(keep_block);
    free(canonical);
    return 0;
}

static int find_start_index(
    const LanternStore *store,
    const LanternRoot *start_root,
    size_t *out_index) {
    if (!store || store->block_len == 0) {
        return -1;
    }
    if (lantern_root_is_zero(start_root)) {
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
    const LanternStore *store,
    const LanternRoot *start_root,
    const LanternCheckpoint *votes,
    size_t vote_count,
    uint64_t min_score,
    LanternRoot *out_head) {
    if (!store || (!votes && vote_count > 0u) || !out_head) {
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
        const LanternCheckpoint *vote = &votes[i];
        if (lantern_root_is_zero(&vote->root)) {
            continue;
        }
        size_t node_index = 0;
        if (!find_block_index(store, &vote->root, &node_index)) {
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

static int collect_latest_votes(
    const LanternStore *store,
    const struct lantern_latest_vote_map *latest_votes,
    LanternCheckpoint **out_votes,
    size_t *out_vote_count) {
    if (!store || !latest_votes || !out_votes || !out_vote_count) {
        return -1;
    }
    *out_votes = NULL;
    *out_vote_count = 0;
    size_t vote_count = 0u;
    if (fork_choice_validator_count(store, &vote_count) != 0) {
        return -1;
    }
    LanternCheckpoint *votes = NULL;
    if (vote_count > 0) {
        votes = calloc(vote_count, sizeof(*votes));
        if (!votes) {
            return -1;
        }
        size_t limit = latest_votes->capacity < vote_count
            ? latest_votes->capacity
            : vote_count;
        for (size_t validator = 0u; validator < limit; ++validator) {
            const struct lantern_latest_vote_entry *entry =
                &latest_votes->entries[validator];
            if (entry->present
                && entry->data.head.slot > store->latest_finalized.slot) {
                votes[validator] = entry->data.head;
            }
        }
    }
    *out_votes = votes;
    *out_vote_count = vote_count;
    return 0;
}

static int collect_known_weight_votes(
    const LanternStore *store,
    LanternCheckpoint **out_votes,
    size_t *out_vote_count) {
    if (!store || !out_votes || !out_vote_count) {
        return -1;
    }
    return collect_latest_votes(
        store,
        &store->known_votes,
        out_votes,
        out_vote_count);
}

static int compute_known_block_weights(
    const LanternStore *store,
    uint64_t *weights,
    size_t weight_count) {
    if (!store || !weights || weight_count < store->block_len) {
        return -1;
    }
    memset(weights, 0, weight_count * sizeof(*weights));
    if (store->block_len == 0) {
        return 0;
    }

    LanternCheckpoint *votes = NULL;
    size_t vote_count = 0;
    if (collect_known_weight_votes(store, &votes, &vote_count) != 0) {
        return -1;
    }

    uint64_t start_slot = store->latest_finalized.slot;
    for (size_t i = 0; i < vote_count; ++i) {
        const LanternCheckpoint *vote = &votes[i];
        if (lantern_root_is_zero(&vote->root)) {
            continue;
        }
        size_t node_index = 0;
        if (!find_block_index(store, &vote->root, &node_index)) {
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
    const LanternStore *store,
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

int lantern_fork_choice_recompute_head(LanternStore *store) {
    if (!store || store->block_len == 0u) {
        return -1;
    }
    LanternRoot previous_head = store->head;
    LanternRoot head;
    LanternCheckpoint *votes = NULL;
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
    if (store->state_cache && !lantern_fork_choice_block_state(store, &head))
    {
        return -1;
    }

    store->head = head;
    bool finalized_changed = refresh_finalized_from_head_state(store);

    if (root_compare(&previous_head, &head) != 0) {
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

    if (finalized_changed) {
        fork_choice_publish_current_checkpoints(store);
    }
    return 0;
}

int lantern_fork_choice_accept_new_aggregated_payloads(LanternStore *store) {
    return lantern_fork_choice_recompute_head(store);
}

int lantern_fork_choice_update_safe_target(LanternStore *store) {
    if (!store || store->block_len == 0u) {
        return -1;
    }
    size_t validator_count = 0u;
    if (fork_choice_validator_count(store, &validator_count) != 0) {
        return -1;
    }
    uint64_t threshold = lantern_consensus_quorum_threshold(validator_count);
    LanternCheckpoint *safe_votes = NULL;
    size_t safe_vote_count = 0;
    if (collect_latest_votes(
            store,
            &store->new_votes,
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
    return 0;
}

static int tick_interval(LanternStore *store, bool has_proposal) {
    if (!store) {
        return -1;
    }
    store->time_intervals += 1;
    uint64_t current_interval = store->time_intervals % LANTERN_INTERVALS_PER_SLOT;
    switch (current_interval) {
    case LANTERN_DUTY_PHASE_PROPOSAL:
        if (has_proposal) {
            (void)lantern_store_promote_new_aggregated_payloads(store);
            return lantern_fork_choice_accept_new_aggregated_payloads(store);
        }
        return 0;
    case LANTERN_DUTY_PHASE_VOTE:
        /* Interval 1: collect new votes, no store mutation. */
        return 0;
    case LANTERN_DUTY_PHASE_AGGREGATE:
        /* Interval 2: committee aggregation handled at validator layer. */
        return 0;
    case LANTERN_DUTY_PHASE_SAFE_TARGET:
        return lantern_fork_choice_update_safe_target(store);
    case LANTERN_DUTY_PHASE_VOTE_ACCEPT:
        (void)lantern_store_promote_new_aggregated_payloads(store);
        return lantern_fork_choice_accept_new_aggregated_payloads(store);
    default:
        return 0;
    }
}

int lantern_fork_choice_advance_to(
    LanternStore *store,
    uint64_t target_interval,
    bool has_proposal) {
    if (!store || store->block_len == 0u) {
        return -1;
    }
    while (store->time_intervals < target_interval) {
        bool will_propose = has_proposal && (store->time_intervals + 1 == target_interval);
        if (tick_interval(store, will_propose) != 0) {
            return -1;
        }
    }
    return 0;
}

int lantern_fork_choice_block_info(
    const LanternStore *store,
    const LanternRoot *root,
    uint64_t *out_slot,
    LanternRoot *out_parent_root,
    bool *out_has_parent) {
    if (!store || !root) {
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

bool lantern_fork_choice_read_checkpoint_snapshot(
    const LanternStore *store,
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

void lantern_fork_choice_tree_snapshot_reset(struct lantern_fork_choice_tree_snapshot *snapshot) {
    if (!snapshot) {
        return;
    }
    free(snapshot->nodes);
    memset(snapshot, 0, sizeof(*snapshot));
}

int lantern_fork_choice_snapshot_tree(
    const LanternStore *store,
    struct lantern_fork_choice_tree_snapshot *out_snapshot) {
    if (!store || !out_snapshot || store->block_len == 0u) {
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
    out_snapshot->safe_target = store->safe_target;
    size_t validator_count = 0u;
    if (fork_choice_validator_count(store, &validator_count) != 0) {
        lantern_fork_choice_tree_snapshot_reset(out_snapshot);
        free(weights);
        return -1;
    }
    out_snapshot->validator_count = (uint64_t)validator_count;

    free(weights);
    return 0;
}
