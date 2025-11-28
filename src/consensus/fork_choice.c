#include "lantern/consensus/fork_choice.h"

#include <inttypes.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>

#include "lantern/consensus/hash.h"
#include "lantern/consensus/quorum.h"
#include "lantern/metrics/lean_metrics.h"
#include "lantern/support/log.h"
#include "lantern/support/strings.h"
#include "lantern/support/time.h"

#define LANTERN_FORK_CHOICE_DEFAULT_SECONDS_PER_SLOT 4u
#define LANTERN_FORK_CHOICE_DEFAULT_INTERVALS_PER_SLOT 4u
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
    static bool initialized = false;
    static bool enabled = false;
    if (!initialized) {
        const char *env = getenv("LANTERN_DEBUG_FINALIZATION");
        enabled = env && env[0] != '\0';
        initialized = true;
    }
    return enabled;
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

static void votes_reset(struct lantern_fork_choice_vote_entry *entries, size_t count) {
    if (!entries) {
        return;
    }
    for (size_t i = 0; i < count; ++i) {
        entries[i].has_checkpoint = false;
        memset(&entries[i].checkpoint, 0, sizeof(entries[i].checkpoint));
    }
}

static int ensure_block_capacity(LanternForkChoice *store, size_t required) {
    if (!store) {
        return -1;
    }
    if (store->block_cap >= required) {
        return 0;
    }
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
    store->block_cap = capacity;
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

void lantern_fork_choice_init(LanternForkChoice *store) {
    if (!store) {
        return;
    }
    memset(store, 0, sizeof(*store));
    store->seconds_per_slot = LANTERN_FORK_CHOICE_DEFAULT_SECONDS_PER_SLOT;
    store->intervals_per_slot = LANTERN_FORK_CHOICE_DEFAULT_INTERVALS_PER_SLOT;
    store->seconds_per_interval = store->seconds_per_slot / store->intervals_per_slot;
}

void lantern_fork_choice_reset(LanternForkChoice *store) {
    if (!store) {
        return;
    }
    free(store->blocks);
    store->blocks = NULL;
    store->block_cap = 0;
    store->block_len = 0;

    map_reset(store);

    free(store->known_votes);
    store->known_votes = NULL;
    free(store->new_votes);
    store->new_votes = NULL;
    store->validator_count = 0;

    store->initialized = false;
    store->has_anchor = false;
    store->has_head = false;
    store->has_safe_target = false;
    zero_root(&store->head);
    zero_root(&store->safe_target);
    memset(&store->latest_justified, 0, sizeof(store->latest_justified));
    memset(&store->latest_finalized, 0, sizeof(store->latest_finalized));
    store->time_intervals = 0;
    store->seconds_per_slot = LANTERN_FORK_CHOICE_DEFAULT_SECONDS_PER_SLOT;
    store->intervals_per_slot = LANTERN_FORK_CHOICE_DEFAULT_INTERVALS_PER_SLOT;
    store->seconds_per_interval = store->seconds_per_slot / store->intervals_per_slot;
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
    store->known_votes = calloc(store->validator_count, sizeof(*store->known_votes));
    if (!store->known_votes) {
        lantern_fork_choice_reset(store);
        return -1;
    }
    store->new_votes = calloc(store->validator_count, sizeof(*store->new_votes));
    if (!store->new_votes) {
        lantern_fork_choice_reset(store);
        return -1;
    }
    store->seconds_per_slot = LANTERN_FORK_CHOICE_DEFAULT_SECONDS_PER_SLOT;
    store->intervals_per_slot = LANTERN_FORK_CHOICE_DEFAULT_INTERVALS_PER_SLOT;
    store->seconds_per_interval = store->seconds_per_slot / store->intervals_per_slot;
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
    const LanternCheckpoint *latest_justified,
    const LanternCheckpoint *latest_finalized) {
    if (!store || !root) {
        return -1;
    }
    size_t existing_index = 0;
    if (map_lookup(store, root, &existing_index)) {
        struct lantern_fork_choice_block_entry *entry = &store->blocks[existing_index];
        entry->slot = slot;
        if (latest_justified) {
            entry->latest_justified = *latest_justified;
            entry->has_justified = true;
        }
        if (latest_finalized) {
            entry->latest_finalized = *latest_finalized;
            entry->has_finalized = true;
        }
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
    entry->has_validator_count = false;
    entry->validator_count = 0;
    entry->has_justified = latest_justified != NULL;
    if (latest_justified) {
        entry->latest_justified = *latest_justified;
    } else {
        memset(&entry->latest_justified, 0, sizeof(entry->latest_justified));
    }
    entry->has_finalized = latest_finalized != NULL;
    if (latest_finalized) {
        entry->latest_finalized = *latest_finalized;
    } else {
        memset(&entry->latest_finalized, 0, sizeof(entry->latest_finalized));
    }
    size_t new_index = store->block_len;
    store->block_len += 1;
    if (map_insert(store, root, new_index) != 0) {
        return -1;
    }
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

int lantern_fork_choice_set_anchor(
    LanternForkChoice *store,
    const LanternBlock *anchor_block,
    const LanternCheckpoint *latest_justified,
    const LanternCheckpoint *latest_finalized,
    const LanternRoot *block_root_hint) {
    if (!store || !store->initialized || !anchor_block) {
        return -1;
    }
    LanternRoot root;
    if (block_root_hint) {
        root = *block_root_hint;
    } else {
        if (lantern_hash_tree_root_block(anchor_block, &root) != 0) {
            return -1;
        }
    }
    if (register_block(store, &root, &anchor_block->parent_root, anchor_block->slot, latest_justified, latest_finalized) != 0) {
        return -1;
    }
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
    uint64_t anchor_intervals = anchor_block->slot * store->intervals_per_slot;
    store->time_intervals = anchor_intervals;
    return 0;
}

static int update_global_checkpoints(
    LanternForkChoice *store,
    const LanternCheckpoint *post_justified,
    const LanternCheckpoint *post_finalized) {
    if (!store) {
        return -1;
    }
    if (post_justified && post_justified->slot >= store->latest_justified.slot) {
        store->latest_justified = *post_justified;
    }
    if (post_finalized && post_finalized->slot >= store->latest_finalized.slot) {
        store->latest_finalized = *post_finalized;
    }
    return 0;
}

static int lantern_fork_choice_stage_proposer_vote(
    LanternForkChoice *store,
    const LanternSignedVote *vote,
    uint64_t block_slot,
    uint64_t proposer_index) {
    if (!store) {
        return -1;
    }
    if (!vote) {
        return 0;
    }
    if (vote->data.slot != block_slot) {
        return -1;
    }
    if (vote->data.validator_id != proposer_index) {
        return -1;
    }
    return lantern_fork_choice_add_vote(store, vote, false);
}

int lantern_fork_choice_add_block(
    LanternForkChoice *store,
    const LanternBlock *block,
    const LanternSignedVote *proposer_attestation,
    const LanternCheckpoint *post_justified,
    const LanternCheckpoint *post_finalized,
    const LanternRoot *block_root_hint) {
    if (!store || !store->initialized || !store->has_anchor || !block) {
        return -1;
    }
    bool trace_finalization = finalization_trace_enabled();
    struct lantern_log_metadata trace_meta = {.has_slot = true, .slot = block->slot};
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
    if (trace_finalization) {
        format_root_hex(&block_root, block_hex, sizeof(block_hex));
        format_root_hex(&block->parent_root, parent_hex, sizeof(parent_hex));
        if (!root_is_zero(&block->parent_root)) {
            parent_known =
                (lantern_fork_choice_block_info(store, &block->parent_root, &parent_slot, NULL, NULL) == 0);
        }
    }
    if (register_block(store, &block_root, &block->parent_root, block->slot, post_justified, post_finalized) != 0) {
        return -1;
    }
    if (update_global_checkpoints(store, post_justified, post_finalized) != 0) {
        return -1;
    }

    const LanternAttestations *att = &block->body.attestations;
    for (size_t i = 0; i < att->length; ++i) {
        LanternSignedVote wrapped_vote;
        memset(&wrapped_vote, 0, sizeof(wrapped_vote));
        wrapped_vote.data = att->data[i];
        if (lantern_fork_choice_add_vote(store, &wrapped_vote, true) != 0) {
            return -1;
        }
    }
    if (lantern_fork_choice_recompute_head(store) != 0) {
        return -1;
    }
    if (lantern_fork_choice_stage_proposer_vote(store, proposer_attestation, block->slot, block->proposer_index)
        != 0) {
        return -1;
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
            att->length,
            post_justified ? post_justified->slot : 0u,
            post_finalized ? post_finalized->slot : 0u);
    }
    return 0;
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
    const LanternCheckpoint *target = &vote->data.target;
    size_t block_index = 0;
    if (!map_lookup(store, &target->root, &block_index)) {
        return 0;
    }
    struct lantern_fork_choice_block_entry *target_block = &store->blocks[block_index];
    if (target_block->slot != target->slot) {
        return -1;
    }

    size_t validator = (size_t)vote->data.validator_id;
    struct lantern_fork_choice_vote_entry *table = from_block ? store->known_votes : store->new_votes;
    struct lantern_fork_choice_vote_entry *entry = &table[validator];
    if (!entry->has_checkpoint || vote->data.slot > entry->checkpoint.slot) {
        entry->checkpoint = *target;
        entry->has_checkpoint = true;
    } else if (vote->data.slot == entry->checkpoint.slot) {
        if (root_compare(&entry->checkpoint.root, &target->root) != 0) {
            return -1;
        }
    }

    if (from_block) {
        struct lantern_fork_choice_vote_entry *pending = &store->new_votes[validator];
        if (pending->has_checkpoint && pending->checkpoint.slot <= entry->checkpoint.slot) {
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
    return update_global_checkpoints(store, latest_justified, latest_finalized);
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

int lantern_fork_choice_recompute_head(LanternForkChoice *store) {
    if (!store || !store->initialized || !store->has_anchor) {
        return -1;
    }
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

    size_t head_index = 0;
    if (map_lookup(store, &head, &head_index)) {
        const struct lantern_fork_choice_block_entry *entry = &store->blocks[head_index];
        if (entry->has_finalized) {
            store->latest_finalized = entry->latest_finalized;
        }
    }
    return 0;
}

int lantern_fork_choice_accept_new_votes(LanternForkChoice *store) {
    if (!store || !store->initialized) {
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
    LanternRoot safe;
    if (lmd_ghost_compute(
            store,
            &store->latest_justified.root,
            store->new_votes,
            store->validator_count,
            threshold,
            &safe)
        != 0) {
        return -1;
    }
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
        return 0;
    case 2:
        return lantern_fork_choice_update_safe_target(store);
    default:
        return lantern_fork_choice_accept_new_votes(store);
    }
}

int lantern_fork_choice_advance_time(
    LanternForkChoice *store,
    uint64_t now_seconds,
    bool has_proposal) {
    if (!store || !store->initialized || !store->has_anchor) {
        return -1;
    }
    if (now_seconds < store->config.genesis_time) {
        /* Before genesis - no time to advance yet, but this is not an error */
        return 0;
    }
    if (store->seconds_per_interval == 0) {
        return -1;
    }
    uint64_t elapsed = now_seconds - store->config.genesis_time;
    uint64_t target_interval = elapsed / store->seconds_per_interval;
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
