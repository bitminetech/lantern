#ifndef LANTERN_CONSENSUS_FORK_CHOICE_H
#define LANTERN_CONSENSUS_FORK_CHOICE_H

#include "lantern/consensus/store.h"

#ifdef __cplusplus
extern "C" {
#endif

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
    uint64_t validator_count;
};

void lantern_fork_choice_reset(LanternStore *store);

int lantern_fork_choice_set_anchor_with_state(
    LanternStore *store,
    const LanternBlock *anchor_block,
    const LanternCheckpoint *latest_justified,
    const LanternCheckpoint *latest_finalized,
    const LanternRoot *block_root_hint,
    const LanternState *anchor_state);

int lantern_fork_choice_add_block(
    LanternStore *store,
    const LanternBlock *block,
    const LanternCheckpoint *post_justified,
    const LanternCheckpoint *post_finalized,
    const LanternRoot *block_root_hint);
int lantern_fork_choice_add_block_with_state(
    LanternStore *store,
    const LanternBlock *block,
    const LanternCheckpoint *post_justified,
    const LanternCheckpoint *post_finalized,
    const LanternRoot *block_root_hint,
    const LanternState *post_state);

int lantern_fork_choice_update_checkpoints(
    LanternStore *store,
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
    LanternStore *store,
    const LanternCheckpoint *latest_justified,
    const LanternCheckpoint *latest_finalized);
int lantern_fork_choice_prune_states(LanternStore *store);

int lantern_fork_choice_accept_new_aggregated_payloads(LanternStore *store);
int lantern_fork_choice_update_safe_target(LanternStore *store);
int lantern_fork_choice_recompute_head(LanternStore *store);

int lantern_fork_choice_advance_to(
    LanternStore *store,
    uint64_t target_interval,
    bool has_proposal);

int lantern_fork_choice_block_info(
    const LanternStore *store,
    const LanternRoot *root,
    uint64_t *out_slot,
    LanternRoot *out_parent_root,
    bool *out_has_parent);
int lantern_fork_choice_set_block_state(
    LanternStore *store,
    const LanternRoot *root,
    const LanternState *state);
const LanternState *lantern_fork_choice_block_state(
    const LanternStore *store,
    const LanternRoot *root);
bool lantern_fork_choice_read_checkpoint_snapshot(
    const LanternStore *store,
    LanternCheckpoint *out_justified,
    LanternCheckpoint *out_finalized);
void lantern_fork_choice_tree_snapshot_reset(struct lantern_fork_choice_tree_snapshot *snapshot);
int lantern_fork_choice_snapshot_tree(
    const LanternStore *store,
    struct lantern_fork_choice_tree_snapshot *out_snapshot);

#ifdef __cplusplus
}
#endif

#endif /* LANTERN_CONSENSUS_FORK_CHOICE_H */
