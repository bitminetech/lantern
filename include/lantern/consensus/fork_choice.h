#ifndef LANTERN_CONSENSUS_FORK_CHOICE_H
#define LANTERN_CONSENSUS_FORK_CHOICE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdatomic.h>

#include "lantern/consensus/containers.h"
#include "lantern/consensus/state.h"

#ifdef __cplusplus
extern "C" {
#endif

struct lantern_aggregated_payload_pool;
struct lantern_attestation_data_by_root;

struct lantern_fork_choice_block_entry {
    LanternRoot root;
    LanternRoot parent_root;
    uint64_t slot;
    LanternValidatorIndex proposer_index;
    bool has_validator_count;
    uint64_t validator_count;
};

struct lantern_fork_choice_state_entry {
    bool has_state;
    LanternState state;
};

struct lantern_fork_choice_checkpoint_snapshot {
    atomic_uint_fast64_t sequence;
    atomic_uint_fast64_t justified_slot;
    atomic_uchar justified_root[LANTERN_ROOT_SIZE];
    atomic_uint_fast64_t finalized_slot;
    atomic_uchar finalized_root[LANTERN_ROOT_SIZE];
};

typedef struct lantern_fork_choice {
    bool initialized;
    bool has_anchor;
    LanternRoot anchor_root;
    uint64_t anchor_slot;
    LanternConfig config;
    uint32_t seconds_per_slot;
    uint32_t intervals_per_slot;
    uint64_t milliseconds_per_interval;
    uint64_t time_intervals;
    LanternCheckpoint latest_justified;
    LanternCheckpoint latest_finalized;
    struct lantern_fork_choice_checkpoint_snapshot checkpoint_snapshot;
    LanternRoot head;
    bool has_head;
    LanternRoot safe_target;
    bool has_safe_target;

    struct lantern_fork_choice_block_entry *blocks;
    size_t block_len;
    size_t block_cap;

    struct lantern_fork_choice_state_entry *states;
    size_t state_cap;

    size_t validator_count;

    /*
     * Attached views into store-owned attestation material.
     *
     * Aggregated gossip updates the shared store first. Fork-choice consumers
     * read these pointers to observe the same proof pools and attestation-data
     * map without maintaining a duplicate cache.
     */
    const struct lantern_aggregated_payload_pool *new_aggregated_payloads;
    const struct lantern_aggregated_payload_pool *known_aggregated_payloads;
    const struct lantern_attestation_data_by_root *attestation_data_by_root;
} LanternForkChoice;

struct lantern_fork_choice_tree_node {
    LanternRoot root;
    LanternRoot parent_root;
    uint64_t slot;
    uint64_t proposer_index;
    uint64_t weight;
};

struct lantern_fork_choice_tree_snapshot {
    struct lantern_fork_choice_tree_node *nodes;
    size_t node_count;
    LanternRoot head;
    LanternCheckpoint justified;
    LanternCheckpoint finalized;
    LanternRoot safe_target;
};

void lantern_fork_choice_init(LanternForkChoice *store);
void lantern_fork_choice_reset(LanternForkChoice *store);

int lantern_fork_choice_configure(LanternForkChoice *store, const LanternConfig *config);

int lantern_fork_choice_set_anchor(
    LanternForkChoice *store,
    const LanternBlock *anchor_block,
    const LanternCheckpoint *latest_justified,
    const LanternCheckpoint *latest_finalized,
    const LanternRoot *block_root_hint);
int lantern_fork_choice_set_anchor_with_state(
    LanternForkChoice *store,
    const LanternBlock *anchor_block,
    const LanternCheckpoint *latest_justified,
    const LanternCheckpoint *latest_finalized,
    const LanternRoot *block_root_hint,
    const LanternState *anchor_state);

int lantern_fork_choice_add_block(
    LanternForkChoice *store,
    const LanternBlock *block,
    const LanternCheckpoint *post_justified,
    const LanternCheckpoint *post_finalized,
    const LanternRoot *block_root_hint);
int lantern_fork_choice_add_block_with_state(
    LanternForkChoice *store,
    const LanternBlock *block,
    const LanternCheckpoint *post_justified,
    const LanternCheckpoint *post_finalized,
    const LanternRoot *block_root_hint,
    const LanternState *post_state);

int lantern_fork_choice_update_checkpoints(
    LanternForkChoice *store,
    const LanternCheckpoint *latest_justified,
    const LanternCheckpoint *latest_finalized);

/**
 * Restore fork-choice checkpoints from persisted state.
 *
 * Unlike lantern_fork_choice_update_checkpoints(), this API is intended for
 * startup restoration and may move checkpoints backwards when the persisted
 * state is behind the temporary anchor checkpoints used during init.
 *
 * Restored checkpoints must refer to blocks already materialized in the local
 * fork-choice tree.
 */
int lantern_fork_choice_restore_checkpoints(
    LanternForkChoice *store,
    const LanternCheckpoint *latest_justified,
    const LanternCheckpoint *latest_finalized);
int lantern_fork_choice_prune_states(LanternForkChoice *store);

int lantern_fork_choice_accept_new_aggregated_payloads(LanternForkChoice *store);
int lantern_fork_choice_update_safe_target(LanternForkChoice *store);
int lantern_fork_choice_recompute_head(LanternForkChoice *store);

int lantern_fork_choice_advance_time(
    LanternForkChoice *store,
    uint64_t now_milliseconds,
    bool has_proposal);

int lantern_fork_choice_current_head(const LanternForkChoice *store, LanternRoot *out_head);
int lantern_fork_choice_block_info(
    const LanternForkChoice *store,
    const LanternRoot *root,
    uint64_t *out_slot,
    LanternRoot *out_parent_root,
    bool *out_has_parent);
int lantern_fork_choice_set_block_validator_count(
    LanternForkChoice *store,
    const LanternRoot *root,
    uint64_t validator_count);
int lantern_fork_choice_set_block_state(
    LanternForkChoice *store,
    const LanternRoot *root,
    const LanternState *state);
const LanternState *lantern_fork_choice_block_state(
    const LanternForkChoice *store,
    const LanternRoot *root);
const LanternRoot *lantern_fork_choice_anchor_root(const LanternForkChoice *store);
int lantern_fork_choice_anchor_slot(const LanternForkChoice *store, uint64_t *out_slot);
const LanternCheckpoint *lantern_fork_choice_latest_justified(const LanternForkChoice *store);
const LanternCheckpoint *lantern_fork_choice_latest_finalized(const LanternForkChoice *store);
bool lantern_fork_choice_read_checkpoint_snapshot(
    const LanternForkChoice *store,
    LanternCheckpoint *out_justified,
    LanternCheckpoint *out_finalized);
const LanternRoot *lantern_fork_choice_safe_target(const LanternForkChoice *store);
void lantern_fork_choice_tree_snapshot_reset(struct lantern_fork_choice_tree_snapshot *snapshot);
int lantern_fork_choice_snapshot_tree(
    const LanternForkChoice *store,
    struct lantern_fork_choice_tree_snapshot *out_snapshot);

#ifdef __cplusplus
}
#endif

#endif /* LANTERN_CONSENSUS_FORK_CHOICE_H */
