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
#define LANTERN_FORK_CHOICE_MAP_MIN_CAPACITY 16u
#define LANTERN_FORK_CHOICE_LOAD_NUMERATOR 7u
#define LANTERN_FORK_CHOICE_LOAD_DENOMINATOR 10u

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

static int root_compare(const LanternRoot *a, const LanternRoot *b) {
    return memcmp(a->bytes, b->bytes, sizeof(a->bytes));
}

static uint64_t root_hash(const LanternRoot *root) {
    /* 64-bit FNV-1a */
    const uint8_t *data = root->bytes;
    uint64_t hash = 1469598103934665603ULL;
    for (size_t i = 0; i < LANTERN_ROOT_SIZE; ++i) {
        hash ^= data[i];
        hash *= 1099511628211ULL;
    }
    return hash;
}

static bool finalization_trace_enabled(void) {
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

static void map_reset(LanternForkChoice *store) {
    free(store->index_entries);
    store->index_entries = NULL;
    store->index_cap = 0;
    store->index_len = 0;
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

static int map_reserve(LanternForkChoice *store, size_t desired) {
    if (!store) {
        return -1;
    }
    if (store->index_cap >= desired) {
        return 0;
    }
    size_t capacity = store->index_cap == 0 ? LANTERN_FORK_CHOICE_MAP_MIN_CAPACITY : store->index_cap;
    while (capacity < desired) {
        if (capacity > (SIZE_MAX / 2)) {
            return -1;
        }
        capacity *= 2;
    }
    struct lantern_fork_choice_root_index_entry *entries = calloc(capacity, sizeof(*entries));
    if (!entries) {
        return -1;
    }

    size_t new_len = 0;
    if (store->index_entries) {
        for (size_t i = 0; i < store->index_cap; ++i) {
            struct lantern_fork_choice_root_index_entry *old = &store->index_entries[i];
            if (!old->occupied || old->tombstone) {
                continue;
            }
            uint64_t hash = root_hash(&old->root);
            size_t mask = capacity - 1;
            size_t pos = (size_t)(hash & mask);
            while (entries[pos].occupied) {
                pos = (pos + 1) & mask;
            }
            entries[pos] = *old;
            entries[pos].tombstone = false;
            entries[pos].occupied = true;
            new_len += 1;
        }
        free(store->index_entries);
    }

    store->index_entries = entries;
    store->index_cap = capacity;
    store->index_len = new_len;
    return 0;
}

static bool map_lookup(const LanternForkChoice *store, const LanternRoot *root, size_t *out_value) {
    if (!store || !root || store->index_cap == 0 || !store->index_entries) {
        return false;
    }
    uint64_t hash = root_hash(root);
    size_t mask = store->index_cap - 1;
    size_t pos = (size_t)(hash & mask);
    size_t start = pos;
    while (true) {
        const struct lantern_fork_choice_root_index_entry *entry = &store->index_entries[pos];
        if (!entry->occupied) {
            return false;
        }
        if (!entry->tombstone && root_compare(&entry->root, root) == 0) {
            if (out_value) {
                *out_value = entry->value;
            }
            return true;
        }
        pos = (pos + 1) & mask;
        if (pos == start) {
            return false;
        }
    }
}

static int map_insert(LanternForkChoice *store, const LanternRoot *root, size_t value) {
    if (!store || !root) {
        return -1;
    }
    if (store->index_cap == 0) {
        if (map_reserve(store, LANTERN_FORK_CHOICE_MAP_MIN_CAPACITY) != 0) {
            return -1;
        }
    }
    if (store->index_len * LANTERN_FORK_CHOICE_LOAD_DENOMINATOR
        >= store->index_cap * LANTERN_FORK_CHOICE_LOAD_NUMERATOR) {
        size_t desired = store->index_cap * 2;
        if (desired < store->index_cap) {
            return -1;
        }
        if (map_reserve(store, desired) != 0) {
            return -1;
        }
    }
    uint64_t hash = root_hash(root);
    size_t mask = store->index_cap - 1;
    size_t pos = (size_t)(hash & mask);
    size_t first_tombstone = SIZE_MAX;
    while (true) {
        struct lantern_fork_choice_root_index_entry *entry = &store->index_entries[pos];
        if (!entry->occupied) {
            size_t target = (first_tombstone != SIZE_MAX) ? first_tombstone : pos;
            entry = &store->index_entries[target];
            entry->root = *root;
            entry->value = value;
            entry->occupied = true;
            entry->tombstone = false;
            store->index_len += 1;
            return 0;
        }
        if (!entry->tombstone && root_compare(&entry->root, root) == 0) {
            entry->value = value;
            return 0;
        }
        if (entry->tombstone && first_tombstone == SIZE_MAX) {
            first_tombstone = pos;
        }
        pos = (pos + 1) & mask;
    }
}

static bool map_remove(LanternForkChoice *store, const LanternRoot *root) {
    if (!store || !root || store->index_cap == 0 || !store->index_entries) {
        return false;
    }
    uint64_t hash = root_hash(root);
    size_t mask = store->index_cap - 1;
    size_t pos = (size_t)(hash & mask);
    size_t start = pos;
    while (true) {
        struct lantern_fork_choice_root_index_entry *entry = &store->index_entries[pos];
        if (!entry->occupied) {
            return false;
        }
        if (!entry->tombstone && root_compare(&entry->root, root) == 0) {
            entry->tombstone = true;
            if (store->index_len > 0) {
                store->index_len -= 1;
            }
            return true;
        }
        pos = (pos + 1) & mask;
        if (pos == start) {
            return false;
        }
    }
}

static void votes_reset(struct lantern_fork_choice_vote_entry *entries, size_t count) {
    if (!entries) {
        return;
    }
    for (size_t i = 0; i < count; ++i) {
        entries[i].has_checkpoint = false;
        memset(&entries[i].checkpoint, 0, sizeof(entries[i].checkpoint));
    }
}

/*
 * Defensive copy-on-write guard for vote staging arrays.
 *
 * The forkchoice flow expects `known_votes` and `new_votes` to be independent
 * tables. If they alias, a gossip vote update can accidentally mutate known
 * votes in-place. Split the tables before mutating either one.
 */
static int ensure_vote_tables_disjoint(LanternForkChoice *store) {
    if (!store || !store->known_votes || !store->new_votes) {
        return -1;
    }
    return store->known_votes != store->new_votes ? 0 : -1;
}

struct vote_undo_entry {
    size_t validator_index;
    struct lantern_fork_choice_vote_entry previous_known;
    struct lantern_fork_choice_vote_entry previous_new;
};

struct vote_undo_list {
    struct vote_undo_entry *entries;
    size_t length;
    size_t capacity;
};

static void vote_undo_reset(struct vote_undo_list *undo) {
    if (!undo) {
        return;
    }
    free(undo->entries);
    undo->entries = NULL;
    undo->length = 0;
    undo->capacity = 0;
}

static int vote_undo_save(
    struct vote_undo_list *undo,
    uint8_t *touched,
    size_t touched_bytes,
    LanternForkChoice *store,
    size_t validator_index) {
    if (!undo || !store) {
        return -1;
    }
    if (!touched || touched_bytes == 0) {
        return 0;
    }
    if (validator_index >= store->validator_count) {
        return 0;
    }
    size_t byte = validator_index / 8u;
    if (byte >= touched_bytes) {
        return -1;
    }
    uint8_t bit = (uint8_t)(1u << (validator_index % 8u));
    if ((touched[byte] & bit) != 0) {
        return 0;
    }
    touched[byte] |= bit;

    if (undo->length == undo->capacity) {
        size_t next = undo->capacity == 0 ? 8u : (undo->capacity + (undo->capacity / 2u));
        if (next < undo->capacity) {
            return -1;
        }
        struct vote_undo_entry *expanded = realloc(undo->entries, next * sizeof(*expanded));
        if (!expanded) {
            return -1;
        }
        undo->entries = expanded;
        undo->capacity = next;
    }
    undo->entries[undo->length].validator_index = validator_index;
    undo->entries[undo->length].previous_known = store->known_votes[validator_index];
    undo->entries[undo->length].previous_new = store->new_votes[validator_index];
    undo->length += 1;
    return 0;
}

static void vote_undo_restore(const struct vote_undo_list *undo, LanternForkChoice *store) {
    if (!undo || !store) {
        return;
    }
    for (size_t i = 0; i < undo->length; ++i) {
        size_t validator_index = undo->entries[i].validator_index;
        if (validator_index >= store->validator_count) {
            continue;
        }
        store->known_votes[validator_index] = undo->entries[i].previous_known;
        store->new_votes[validator_index] = undo->entries[i].previous_new;
    }
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

static size_t parent_index_for_block(const LanternForkChoice *store, const LanternRoot *parent_root) {
    size_t parent_index = SIZE_MAX;
    if (!root_is_zero(parent_root)) {
        if (!map_lookup(store, parent_root, &parent_index)) {
            parent_index = SIZE_MAX;
        }
    }
    return parent_index;
}

static void update_children_parent_index(
    LanternForkChoice *store,
    const LanternRoot *parent_root,
    size_t parent_index) {
    if (!store || !store->blocks || !parent_root) {
        return;
    }
    if (root_is_zero(parent_root)) {
        return;
    }
    for (size_t i = 0; i < store->block_len; ++i) {
        if (i == parent_index) {
            continue;
        }
        struct lantern_fork_choice_block_entry *entry = &store->blocks[i];
        if (entry->parent_index != SIZE_MAX) {
            continue;
        }
        if (root_is_zero(&entry->parent_root)) {
            continue;
        }
        if (root_compare(&entry->parent_root, parent_root) == 0) {
            entry->parent_index = parent_index;
        }
    }
}

void lantern_fork_choice_init(LanternForkChoice *store) {
    if (!store) {
        return;
    }
    memset(store, 0, sizeof(*store));
    store->seconds_per_slot = LANTERN_FORK_CHOICE_DEFAULT_SECONDS_PER_SLOT;
    store->intervals_per_slot = LANTERN_FORK_CHOICE_DEFAULT_INTERVALS_PER_SLOT;
    store->milliseconds_per_interval =
        ((uint64_t)store->seconds_per_slot * LANTERN_FORK_CHOICE_MILLISECONDS_PER_SECOND) / store->intervals_per_slot;
}

void lantern_fork_choice_reset(LanternForkChoice *store) {
    if (!store) {
        return;
    }
    struct lantern_fork_choice_vote_entry *known_votes = store->known_votes;
    struct lantern_fork_choice_vote_entry *new_votes = store->new_votes;
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

    map_reset(store);

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
    store->time_intervals = 0;
    store->seconds_per_slot = LANTERN_FORK_CHOICE_DEFAULT_SECONDS_PER_SLOT;
    store->intervals_per_slot = LANTERN_FORK_CHOICE_DEFAULT_INTERVALS_PER_SLOT;
    store->milliseconds_per_interval =
        ((uint64_t)store->seconds_per_slot * LANTERN_FORK_CHOICE_MILLISECONDS_PER_SECOND) / store->intervals_per_slot;
    store->known_votes = known_votes;
    store->new_votes = new_votes;
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
    if (!store->known_votes || !store->new_votes) {
        return -1;
    }
    if (store->known_votes == store->new_votes) {
        return -1;
    }
    store->seconds_per_slot = LANTERN_FORK_CHOICE_DEFAULT_SECONDS_PER_SLOT;
    store->intervals_per_slot = LANTERN_FORK_CHOICE_DEFAULT_INTERVALS_PER_SLOT;
    store->milliseconds_per_interval =
        ((uint64_t)store->seconds_per_slot * LANTERN_FORK_CHOICE_MILLISECONDS_PER_SECOND) / store->intervals_per_slot;
    store->initialized = true;
    votes_reset(store->known_votes, store->validator_count);
    votes_reset(store->new_votes, store->validator_count);
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
    if (map_lookup(store, root, &existing_index)) {
        struct lantern_fork_choice_block_entry *entry = &store->blocks[existing_index];
        entry->slot = slot;
        entry->proposer_index = proposer_index;
        if (parent_root) {
            entry->parent_root = *parent_root;
            entry->parent_index = parent_index_for_block(store, parent_root);
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
    entry->parent_index = parent_index_for_block(store, &entry->parent_root);
    entry->slot = slot;
    entry->proposer_index = proposer_index;
    entry->has_validator_count = false;
    entry->validator_count = 0;
    size_t new_index = store->block_len;
    store->block_len += 1;
    if (map_insert(store, root, new_index) != 0) {
        store->block_len -= 1;
        return -1;
    }
    update_children_parent_index(store, root, new_index);
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
    if (!map_lookup(store, root, &index)) {
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
    if (!map_lookup(store, root, &index)) {
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
    if (!map_lookup(store, root, &index)) {
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
        if (lantern_hash_tree_root_block(anchor_block, &root) != 0) {
            return -1;
        }
    }
    size_t existing_index = 0;
    bool existed = map_lookup(store, &root, &existing_index);
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
    if (latest_justified) {
        store->latest_justified = *latest_justified;
    } else {
        memset(&store->latest_justified, 0, sizeof(store->latest_justified));
    }
    if (latest_finalized) {
        store->latest_finalized = *latest_finalized;
    } else {
        memset(&store->latest_finalized, 0, sizeof(store->latest_finalized));
    }
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
            size_t new_index = store->block_len > 0 ? (store->block_len - 1u) : 0u;
            for (size_t i = 0; i + 1u < store->block_len; ++i) {
                struct lantern_fork_choice_block_entry *entry = &store->blocks[i];
                if (entry->parent_index == new_index && root_compare(&entry->parent_root, &root) == 0) {
                    entry->parent_index = SIZE_MAX;
                }
            }
            map_remove(store, &root);
            store->block_len = previous_block_len;
        }
        return -1;
    }
    return 0;
}

static bool checkpoint_known_in_store(
    const LanternForkChoice *store,
    const LanternCheckpoint *checkpoint) {
    if (!store || !checkpoint || root_is_zero(&checkpoint->root)) {
        return false;
    }
    size_t checkpoint_index = 0;
    if (!map_lookup(store, &checkpoint->root, &checkpoint_index)) {
        return false;
    }
    if (!store->blocks || checkpoint_index >= store->block_len) {
        return false;
    }
    if (store->has_anchor && root_compare(&checkpoint->root, &store->anchor_root) == 0) {
        return true;
    }
    return store->blocks[checkpoint_index].slot == checkpoint->slot;
}

static bool checkpoint_root_present_in_store(
    const LanternForkChoice *store,
    const LanternCheckpoint *checkpoint) {
    if (!store || !checkpoint || root_is_zero(&checkpoint->root)) {
        return false;
    }
    size_t checkpoint_index = 0;
    if (!map_lookup(store, &checkpoint->root, &checkpoint_index)) {
        return false;
    }
    return store->blocks && checkpoint_index < store->block_len;
}

static void normalize_checkpoint_for_anchor_alias(
    const LanternForkChoice *store,
    const LanternCheckpoint *checkpoint,
    LanternCheckpoint *out_checkpoint,
    const char *label) {
    if (!out_checkpoint) {
        return;
    }
    memset(out_checkpoint, 0, sizeof(*out_checkpoint));
    if (!checkpoint) {
        return;
    }
    *out_checkpoint = *checkpoint;
    if (!store || !store->has_anchor || root_is_zero(&checkpoint->root)) {
        return;
    }
    if (checkpoint_root_present_in_store(store, checkpoint)) {
        return;
    }
    if (checkpoint->slot > store->anchor_slot) {
        return;
    }

    char original_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    char anchor_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    format_root_hex(&checkpoint->root, original_hex, sizeof(original_hex));
    format_root_hex(&store->anchor_root, anchor_hex, sizeof(anchor_hex));
    lantern_log_info(
        "forkchoice",
        &(const struct lantern_log_metadata){0},
        "aliasing %s checkpoint slot=%" PRIu64 " original_root=%s"
        " anchor_slot=%" PRIu64 " anchor_root=%s",
        label ? label : "post-state",
        checkpoint->slot,
        original_hex[0] ? original_hex : "0x0",
        store->anchor_slot,
        anchor_hex[0] ? anchor_hex : "0x0");
    out_checkpoint->root = store->anchor_root;
}

static bool should_replace_checkpoint(
    const LanternCheckpoint *current,
    const LanternCheckpoint *candidate) {
    if (!current || !candidate || root_is_zero(&candidate->root)) {
        return false;
    }
    if (candidate->slot > current->slot) {
        return true;
    }
    if (candidate->slot == current->slot
        && root_compare(&candidate->root, &current->root) != 0) {
        return true;
    }
    return false;
}

static int update_latest_checkpoints(
    LanternForkChoice *store,
    const LanternCheckpoint *post_justified,
    const LanternCheckpoint *post_finalized) {
    if (!store) {
        return -1;
    }
    LanternCheckpoint latest_justified = store->latest_justified;
    LanternCheckpoint latest_finalized = store->latest_finalized;
    LanternCheckpoint normalized_post_justified;
    LanternCheckpoint normalized_post_finalized;
    const LanternCheckpoint *effective_post_justified = post_justified;
    const LanternCheckpoint *effective_post_finalized = post_finalized;

    if (post_justified) {
        normalize_checkpoint_for_anchor_alias(
            store,
            post_justified,
            &normalized_post_justified,
            "justified");
        effective_post_justified = &normalized_post_justified;
    }
    if (post_finalized) {
        normalize_checkpoint_for_anchor_alias(
            store,
            post_finalized,
            &normalized_post_finalized,
            "finalized");
        effective_post_finalized = &normalized_post_finalized;
    }

    if (effective_post_justified && !root_is_zero(&effective_post_justified->root)) {
        if (!checkpoint_known_in_store(store, effective_post_justified)) {
            return -1;
        }
        if (should_replace_checkpoint(&latest_justified, effective_post_justified)) {
            latest_justified = *effective_post_justified;
        }
    }
    if (effective_post_finalized && !root_is_zero(&effective_post_finalized->root)) {
        if (!checkpoint_known_in_store(store, effective_post_finalized)) {
            return -1;
        }
        if (should_replace_checkpoint(&latest_finalized, effective_post_finalized)) {
            latest_finalized = *effective_post_finalized;
        }
    }

    if (latest_finalized.slot > latest_justified.slot) {
        return -1;
    }

    store->latest_justified = latest_justified;
    store->latest_finalized = latest_finalized;
    return 0;
}

int lantern_fork_choice_add_block(
    LanternForkChoice *store,
    const LanternBlock *block,
    const LanternSignedVote *proposer_attestation,
    const LanternCheckpoint *post_justified,
    const LanternCheckpoint *post_finalized,
    const LanternRoot *block_root_hint) {
    return lantern_fork_choice_add_block_with_state(
        store,
        block,
        proposer_attestation,
        post_justified,
        post_finalized,
        block_root_hint,
        NULL);
}

int lantern_fork_choice_add_block_with_state(
    LanternForkChoice *store,
    const LanternBlock *block,
    const LanternSignedVote *proposer_attestation,
    const LanternCheckpoint *post_justified,
    const LanternCheckpoint *post_finalized,
    const LanternRoot *block_root_hint,
    const LanternState *post_state) {
    if (!store || !store->initialized || !store->has_anchor || !block) {
        return -1;
    }
    /* Proposer attestations are cached by the caller after head recomputation. */
    (void)proposer_attestation;
    bool trace_finalization = finalization_trace_enabled();
    struct lantern_log_metadata trace_meta = {.has_slot = true, .slot = block->slot};
    struct lantern_log_metadata diag_meta = {.has_slot = true, .slot = block->slot};
    char block_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    char parent_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    uint64_t parent_slot = 0;
    bool parent_known = false;
    double metrics_start = lantern_time_now_seconds();
    LanternRoot block_root;
    if (block_root_hint) {
        block_root = *block_root_hint;
    } else {
        if (lantern_hash_tree_root_block(block, &block_root) != 0) {
            return -1;
        }
    }
    LanternRoot hashed_block_root = {0};
    bool have_hashed_block_root = lantern_hash_tree_root_block(block, &hashed_block_root) == 0;
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
    bool existed = map_lookup(store, &block_root, &existing_index);
    struct lantern_fork_choice_block_entry previous_entry;
    memset(&previous_entry, 0, sizeof(previous_entry));
    if (existed) {
        if (!store->blocks || existing_index >= store->block_len) {
            return -1;
        }
        previous_entry = store->blocks[existing_index];
    }

    size_t previous_block_len = store->block_len;

    size_t validator_count = store->validator_count;
    size_t touched_bytes = validator_count / 8u + (validator_count % 8u != 0 ? 1u : 0u);
    uint8_t *touched = NULL;
    if (touched_bytes > 0) {
        touched = calloc(touched_bytes, 1);
        if (!touched) {
            return -1;
        }
    }

    struct vote_undo_list undo = {0};

    if (trace_finalization) {
        format_root_hex(&block_root, block_hex, sizeof(block_hex));
        format_root_hex(&block->parent_root, parent_hex, sizeof(parent_hex));
        if (!root_is_zero(&block->parent_root)) {
            parent_known =
                (lantern_fork_choice_block_info(store, &block->parent_root, &parent_slot, NULL, NULL) == 0);
        }
    }
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
        free(touched);
        vote_undo_reset(&undo);
        return -1;
    }
    if (update_latest_checkpoints(store, post_justified, post_finalized) != 0) {
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

    LanternAttestations expanded;
    lantern_attestations_init(&expanded);
    if (lantern_expand_aggregated_attestations(
            &block->body.attestations,
            store->validator_count,
            &expanded)
        != 0) {
        format_root_hex(&block_root, block_hex, sizeof(block_hex));
        lantern_log_warn(
            "forkchoice",
            &diag_meta,
            "add_block attestation expansion failed slot=%" PRIu64 " root=%s attestations=%zu",
            block->slot,
            block_hex[0] ? block_hex : "0x0",
            block->body.attestations.length);
        goto rollback_attestations;
    }
    for (size_t i = 0; i < expanded.length; ++i) {
        size_t validator_index = (size_t)expanded.data[i].validator_id;
        if (vote_undo_save(&undo, touched, touched_bytes, store, validator_index) != 0) {
            lantern_attestations_reset(&expanded);
            goto rollback;
        }
        LanternSignedVote wrapped_vote;
        memset(&wrapped_vote, 0, sizeof(wrapped_vote));
        wrapped_vote.data = expanded.data[i];
        if (lantern_fork_choice_add_vote(store, &wrapped_vote, true) != 0) {
            continue;
        }
    }
    lantern_attestations_reset(&expanded);
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
    if (trace_finalization) {
        lantern_log_debug(
            "fork_choice",
            &trace_meta,
            "finalization trace add_block slot=%" PRIu64 " root=%s parent_root=%s parent_known=%s"
            " parent_slot=%" PRIu64 " attestations=%zu post_justified=%" PRIu64
            " post_finalized=%" PRIu64,
            block->slot,
            block_hex[0] ? block_hex : "0x0",
            parent_hex[0] ? parent_hex : "0x0",
            parent_known ? "true" : "false",
            parent_known ? parent_slot : 0u,
            block->body.attestations.length,
            post_justified ? post_justified->slot : 0u,
            post_finalized ? post_finalized->slot : 0u);
    }
    free(touched);
    vote_undo_reset(&undo);
    return 0;

rollback_attestations:
    lantern_attestations_reset(&expanded);

rollback:
    store->latest_justified = previous_latest_justified;
    store->latest_finalized = previous_latest_finalized;
    store->head = previous_head;
    store->has_head = had_head;

    vote_undo_restore(&undo, store);

    if (existed) {
        store->blocks[existing_index] = previous_entry;
    } else {
        size_t new_index = store->block_len > 0 ? (store->block_len - 1u) : 0u;
        for (size_t i = 0; i + 1u < store->block_len; ++i) {
            struct lantern_fork_choice_block_entry *entry = &store->blocks[i];
            if (entry->parent_index == new_index && root_compare(&entry->parent_root, &block_root) == 0) {
                entry->parent_index = SIZE_MAX;
            }
        }
        map_remove(store, &block_root);
        store->block_len = previous_block_len;
    }

    free(touched);
    vote_undo_reset(&undo);
    return -1;
}

int lantern_fork_choice_add_vote(
    LanternForkChoice *store,
    const LanternSignedVote *vote,
    bool from_block) {
    if (!store || !vote || !store->initialized) {
        return -1;
    }
    if (vote->data.validator_id >= store->validator_count) {
        return -1;
    }
    /* LMD GHOST weights by head, not target (per leanSpec store.py:703
     * and ethereum/research 3sf-mini consensus.py get_fork_choice_head). */
    const LanternCheckpoint *head = &vote->data.head;
    size_t block_index = 0;
    if (!map_lookup(store, &head->root, &block_index)) {
        return 0;
    }
    struct lantern_fork_choice_block_entry *head_block = &store->blocks[block_index];
    if (head_block->slot != head->slot) {
        return -1;
    }
    if (ensure_vote_tables_disjoint(store) != 0) {
        return -1;
    }

    size_t validator = (size_t)vote->data.validator_id;
    struct lantern_fork_choice_vote_entry *table = from_block ? store->known_votes : store->new_votes;
    struct lantern_fork_choice_vote_entry *entry = &table[validator];
    if (!entry->has_checkpoint || vote->data.slot > entry->slot) {
        entry->checkpoint = *head;
        entry->slot = vote->data.slot;
        entry->has_checkpoint = true;
    } else if (vote->data.slot == entry->slot) {
        if (root_compare(&entry->checkpoint.root, &head->root) != 0) {
            return -1;
        }
    }

    if (from_block) {
        struct lantern_fork_choice_vote_entry *pending = &store->new_votes[validator];
        if (pending->has_checkpoint && pending->slot <= entry->slot) {
            pending->has_checkpoint = false;
        }
    }
    return 0;
}

int lantern_fork_choice_update_checkpoints(
    LanternForkChoice *store,
    const LanternCheckpoint *latest_justified,
    const LanternCheckpoint *latest_finalized) {
    if (!store || !store->initialized) {
        return -1;
    }
    return update_latest_checkpoints(store, latest_justified, latest_finalized);
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
    if (!map_lookup(store, &store->head, &head_index)
        || !map_lookup(store, &store->latest_finalized.root, &finalized_index)) {
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
        size_t parent_index = store->blocks[current].parent_index;
        if (parent_index == SIZE_MAX || parent_index >= store->block_len) {
            break;
        }
        current = parent_index;
    }

    if (!found_finalized) {
        free(canonical);
        return -1;
    }

    uint64_t finalized_slot = store->blocks[finalized_index].slot;
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

    lantern_log_info(
        "forkchoice",
        NULL,
        "prune_states finalized_slot=%" PRIu64 " blocks=%zu states_before=%zu evicted=%zu kept=%zu",
        finalized_slot,
        store->block_len,
        total_with_state,
        evicted,
        kept);

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
    if (map_lookup(store, start_root, out_index)) {
        return 0;
    }
    return -1;
}

static int lmd_ghost_compute(
    const LanternForkChoice *store,
    const LanternRoot *start_root,
    const struct lantern_fork_choice_vote_entry *votes,
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
        const struct lantern_fork_choice_vote_entry *vote = &votes[i];
        if (!vote->has_checkpoint) {
            continue;
        }
        size_t node_index = 0;
        if (!map_lookup(store, &vote->checkpoint.root, &node_index)) {
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
            if (node->parent_index == SIZE_MAX) {
                break;
            }
            node_index = node->parent_index;
        }
    }

    size_t current = start_index;
    while (true) {
        size_t best_child = SIZE_MAX;
        uint64_t best_weight = 0;
        bool found = false;
        for (size_t i = 0; i < store->block_len; ++i) {
            if (blocks[i].parent_index != current) {
                continue;
            }
            uint64_t candidate_weight = weights[i];
            if (candidate_weight < min_score) {
                continue;
            }
            bool better = false;
            if (!found) {
                better = true;
            } else if (candidate_weight > best_weight) {
                better = true;
            } else if (candidate_weight == best_weight) {
                int cmp = root_compare(&blocks[i].root, &blocks[best_child].root);
                if (cmp > 0) {
                    better = true;
                }
            }
            if (better) {
                found = true;
                best_child = i;
                best_weight = candidate_weight;
            }
        }
        if (!found) {
            *out_head = blocks[current].root;
            free(weights);
            return 0;
        }
        current = best_child;
    }
}

static void safe_target_consider_vote(
    struct lantern_fork_choice_vote_entry *merged_votes,
    uint64_t *latest_slots,
    size_t vote_count,
    size_t validator_index,
    const LanternCheckpoint *head,
    uint64_t attestation_slot) {
    if (!merged_votes || !latest_slots || !head || validator_index >= vote_count) {
        return;
    }
    struct lantern_fork_choice_vote_entry *merged = &merged_votes[validator_index];
    if (!merged->has_checkpoint || attestation_slot > latest_slots[validator_index]) {
        merged->checkpoint = *head;
        merged->has_checkpoint = true;
        latest_slots[validator_index] = attestation_slot;
    }
}

static void safe_target_merge_vote_table(
    const struct lantern_fork_choice_vote_entry *source_votes,
    size_t vote_count,
    struct lantern_fork_choice_vote_entry *merged_votes,
    uint64_t *latest_slots) {
    if (!source_votes || !merged_votes || !latest_slots) {
        return;
    }
    for (size_t i = 0; i < vote_count; ++i) {
        const struct lantern_fork_choice_vote_entry *vote = &source_votes[i];
        if (!vote->has_checkpoint) {
            continue;
        }
        safe_target_consider_vote(
            merged_votes,
            latest_slots,
            vote_count,
            i,
            &vote->checkpoint,
            vote->checkpoint.slot);
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
    struct lantern_fork_choice_vote_entry *merged_votes,
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

static bool fork_choice_has_attached_payload_views(const LanternForkChoice *store) {
    return store
        && store->new_aggregated_payloads
        && store->known_aggregated_payloads
        && store->attestation_data_by_root;
}

static int collect_known_weight_votes(
    const LanternForkChoice *store,
    struct lantern_fork_choice_vote_entry **out_votes,
    size_t *out_vote_count) {
    if (!store || !out_votes || !out_vote_count) {
        return -1;
    }
    *out_votes = NULL;
    *out_vote_count = 0;

    size_t vote_count = store->validator_count;
    struct lantern_fork_choice_vote_entry *votes = NULL;
    if (vote_count > 0) {
        votes = calloc(vote_count, sizeof(*votes));
        if (!votes) {
            return -1;
        }
    }

    if (fork_choice_has_attached_payload_views(store)) {
        uint64_t *latest_slots = NULL;
        if (vote_count > 0) {
            latest_slots = calloc(vote_count, sizeof(*latest_slots));
            if (!latest_slots) {
                free(votes);
                return -1;
            }
        }

        safe_target_merge_payload_pool(
            store,
            store->known_aggregated_payloads,
            votes,
            latest_slots,
            vote_count);
        free(latest_slots);
    } else if (votes && store->known_votes) {
        memcpy(votes, store->known_votes, vote_count * sizeof(*votes));
    }

    *out_votes = votes;
    *out_vote_count = vote_count;
    return 0;
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

    struct lantern_fork_choice_vote_entry *votes = NULL;
    size_t vote_count = 0;
    if (collect_known_weight_votes(store, &votes, &vote_count) != 0) {
        return -1;
    }

    uint64_t start_slot = store->latest_finalized.slot;
    for (size_t i = 0; i < vote_count; ++i) {
        const struct lantern_fork_choice_vote_entry *vote = &votes[i];
        if (!vote->has_checkpoint) {
            continue;
        }
        size_t node_index = 0;
        if (!map_lookup(store, &vote->checkpoint.root, &node_index)) {
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
            if (node->parent_index == SIZE_MAX) {
                break;
            }
            node_index = node->parent_index;
        }
    }

    free(votes);
    return 0;
}

static int materialize_attached_payload_votes(LanternForkChoice *store) {
    if (!store || !fork_choice_has_attached_payload_views(store)) {
        return 0;
    }

    uint64_t *latest_slots = calloc(store->validator_count, sizeof(*latest_slots));
    if (!latest_slots) {
        return -1;
    }

    for (size_t i = 0; i < store->validator_count; ++i) {
        if (!store->known_votes[i].has_checkpoint) {
            continue;
        }
        latest_slots[i] = store->known_votes[i].slot;
    }

    safe_target_merge_payload_pool(
        store,
        store->known_aggregated_payloads,
        store->known_votes,
        latest_slots,
        store->validator_count);
    safe_target_merge_payload_pool(
        store,
        store->new_aggregated_payloads,
        store->known_votes,
        latest_slots,
        store->validator_count);

    free(latest_slots);
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
            size_t parent = store->blocks[old_index].parent_index;
            if (parent == SIZE_MAX || parent >= store->block_len) {
                return 0;
            }
            old_index = parent;
            old_slot = store->blocks[old_index].slot;
            depth += 1;
            continue;
        }
        if (new_slot > old_slot) {
            size_t parent = store->blocks[new_index].parent_index;
            if (parent == SIZE_MAX || parent >= store->block_len) {
                return 0;
            }
            new_index = parent;
            new_slot = store->blocks[new_index].slot;
            continue;
        }

        size_t old_parent = store->blocks[old_index].parent_index;
        size_t new_parent = store->blocks[new_index].parent_index;
        if (old_parent == SIZE_MAX || new_parent == SIZE_MAX
            || old_parent >= store->block_len || new_parent >= store->block_len) {
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
    if (lmd_ghost_compute(
            store,
            &store->latest_justified.root,
            store->known_votes,
            store->validator_count,
            0,
            &head)
        != 0) {
        return -1;
    }
    store->head = head;
    store->has_head = true;

    if (had_head && root_compare(&previous_head, &head) != 0) {
        size_t old_index = 0;
        size_t new_index = 0;
        if (map_lookup(store, &previous_head, &old_index)
            && map_lookup(store, &head, &new_index)) {
            size_t depth = fork_choice_reorg_depth(store, old_index, new_index);
            if (depth > 0) {
                lean_metrics_record_fork_choice_reorg(depth);
            }
        }
    }

    return 0;
}

int lantern_fork_choice_accept_new_votes(LanternForkChoice *store) {
    if (!store || !store->initialized) {
        return -1;
    }
    if (ensure_vote_tables_disjoint(store) != 0) {
        return -1;
    }
    for (size_t i = 0; i < store->validator_count; ++i) {
        struct lantern_fork_choice_vote_entry *pending = &store->new_votes[i];
        if (!pending->has_checkpoint) {
            continue;
        }
        struct lantern_fork_choice_vote_entry *known = &store->known_votes[i];
        if (!known->has_checkpoint || pending->checkpoint.slot >= known->checkpoint.slot) {
            *known = *pending;
        }
        pending->has_checkpoint = false;
    }
    if (materialize_attached_payload_votes(store) != 0) {
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
        if (map_lookup(store, &store->head, &head_index) && head_index < store->block_len) {
            const struct lantern_fork_choice_block_entry *head_entry = &store->blocks[head_index];
            if (head_entry->has_validator_count && head_entry->validator_count > 0) {
                validator_count = head_entry->validator_count;
            }
        }
    }
    uint64_t threshold = lantern_consensus_quorum_threshold(validator_count);
    struct lantern_fork_choice_vote_entry *merged_votes =
        calloc(store->validator_count, sizeof(*merged_votes));
    uint64_t *latest_slots = calloc(store->validator_count, sizeof(*latest_slots));
    if (!merged_votes || !latest_slots) {
        free(merged_votes);
        free(latest_slots);
        return -1;
    }
    if (fork_choice_has_attached_payload_views(store)) {
        safe_target_merge_payload_pool(
            store,
            store->known_aggregated_payloads,
            merged_votes,
            latest_slots,
            store->validator_count);
        safe_target_merge_payload_pool(
            store,
            store->new_aggregated_payloads,
            merged_votes,
            latest_slots,
            store->validator_count);
    } else {
        safe_target_merge_vote_table(store->known_votes, store->validator_count, merged_votes, latest_slots);
        safe_target_merge_vote_table(store->new_votes, store->validator_count, merged_votes, latest_slots);
    }
    LanternRoot safe;
    if (lmd_ghost_compute(
            store,
            &store->latest_justified.root,
            merged_votes,
            store->validator_count,
            threshold,
            &safe)
        != 0) {
        free(merged_votes);
        free(latest_slots);
        return -1;
    }
    free(merged_votes);
    free(latest_slots);
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
            return lantern_fork_choice_accept_new_votes(store);
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
        return lantern_fork_choice_accept_new_votes(store);
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
    bool trace_finalization = finalization_trace_enabled();
    char root_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    if (trace_finalization) {
        format_root_hex(root, root_hex, sizeof(root_hex));
    }
    const struct lantern_fork_choice_block_entry *entry = NULL;
    const char *fail_reason = NULL;
    int rc = -1;
    if (!store || !store->initialized || !root) {
        fail_reason = "invalid_args";
        goto done;
    }
    size_t index = 0;
    if (!map_lookup(store, root, &index)) {
        fail_reason = "lookup_miss";
        goto done;
    }
    if (!store->blocks || index >= store->block_len) {
        fail_reason = "entry_oob";
        goto done;
    }
    entry = &store->blocks[index];
    if (out_slot) {
        *out_slot = entry->slot;
    }
    if (out_parent_root) {
        *out_parent_root = entry->parent_root;
    }
    if (out_has_parent) {
        bool has_parent = entry->parent_index != SIZE_MAX && !root_is_zero(&entry->parent_root);
        *out_has_parent = has_parent;
    }
    rc = 0;

done:
    if (trace_finalization) {
        if (rc == 0 && entry) {
            struct lantern_log_metadata meta = {.has_slot = true, .slot = entry->slot};
            bool has_parent = entry->parent_index != SIZE_MAX && !root_is_zero(&entry->parent_root);
            uint64_t parent_slot = 0;
            if (has_parent && store->blocks && entry->parent_index < store->block_len) {
                parent_slot = store->blocks[entry->parent_index].slot;
            }
            char parent_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
            format_root_hex(&entry->parent_root, parent_hex, sizeof(parent_hex));
            lantern_log_debug(
                "fork_choice",
                &meta,
                "finalization trace block_info slot=%" PRIu64 " root=%s has_parent=%s parent_slot=%" PRIu64
                " parent_root=%s",
                entry->slot,
                root_hex[0] ? root_hex : "0x0",
                has_parent ? "true" : "false",
                has_parent ? parent_slot : 0u,
                parent_hex[0] ? parent_hex : "0x0");
        } else {
            lantern_log_debug(
                "fork_choice",
                NULL,
                "finalization trace block_info miss root=%s reason=%s",
                root_hex[0] ? root_hex : "0x0",
                fail_reason ? fail_reason : "error");
        }
    }
    return rc;
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

const LanternRoot *lantern_fork_choice_safe_target(const LanternForkChoice *store) {
    if (!store || !store->has_safe_target) {
        return NULL;
    }
    return &store->safe_target;
}

static size_t count_vote_entries(
    const struct lantern_fork_choice_vote_entry *entries,
    size_t count) {
    if (!entries) {
        return 0;
    }
    size_t total = 0;
    for (size_t i = 0; i < count; ++i) {
        if (entries[i].has_checkpoint) {
            total += 1;
        }
    }
    return total;
}

size_t lantern_fork_choice_new_votes_count(const LanternForkChoice *store) {
    if (!store || !store->initialized) {
        return 0;
    }
    return count_vote_entries(store->new_votes, store->validator_count);
}

size_t lantern_fork_choice_known_votes_count(const LanternForkChoice *store) {
    if (!store || !store->initialized) {
        return 0;
    }
    return count_vote_entries(store->known_votes, store->validator_count);
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
