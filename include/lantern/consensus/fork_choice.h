#ifndef LANTERN_CONSENSUS_FORK_CHOICE_H
#define LANTERN_CONSENSUS_FORK_CHOICE_H

/**
 * @file
 * Maintain fork-choice metadata and owned post-states. Callers synchronize all
 * store access, including reads that can populate the optional state cache.
 */

#include "lantern/consensus/store.h"

#ifdef __cplusplus
extern "C"
{
#endif

struct lantern_fork_choice_tree_node
{
    LanternRoot root;
    LanternRoot parent_root;
    uint64_t slot;
    uint64_t proposer_index;
    uint64_t weight;
};

struct lantern_fork_choice_tree_snapshot
{
    struct lantern_fork_choice_tree_node *nodes;
    size_t node_count;
    LanternRoot head;
    LanternCheckpoint justified;
    LanternCheckpoint finalized;
    LanternRoot safe_target;
    uint64_t validator_count;
};

/**
 * Supply durable post-state storage keyed by block root.
 *
 * Both callbacks return zero on success and nonzero on failure. load receives
 * an initialized empty output and transfers its allocations to the caller;
 * the caller resets that output on success and failure. save borrows the
 * state only for the call and must complete persistence before returning zero.
 * context remains caller-owned and must outlive the configured store.
 * Calls run synchronously under the caller's store synchronization; callbacks
 * must not re-enter fork choice or mutate the supplied store/state.
 */
struct lantern_state_storage
{
    int (*load)(void *context, const LanternRoot *root, LanternState *out);
    int (*save)(void *context, const LanternRoot *root, const LanternState *state);
    void *context;
};

/**
 * Enable write-through storage and a ten-entry, 64 MiB LRU post-state cache.
 *
 * The head is protected. If the head plus a demanded state exceed the byte
 * budget, they form the sole retained working-set exception. Block metadata
 * is never evicted by this policy. Stores without storage keep their existing
 * in-memory behavior. Reset removes the storage configuration.
 *
 * @param[in,out] store Initialized empty store; must not be NULL.
 * @param[in] storage Non-NULL callbacks, copied on success; context is borrowed.
 * @return 0 on success; -1 for invalid inputs, a nonempty/already configured
 * store, or allocation failure. On failure the store is unchanged.
 * @note The caller must exclude concurrent store access.
 */
int lantern_fork_choice_set_state_storage(
    LanternStore *store, const struct lantern_state_storage *storage);

void lantern_fork_choice_reset(LanternStore *store);

int lantern_fork_choice_set_anchor_with_state(
    LanternStore *store, const LanternBlock *anchor_block,
    const LanternCheckpoint *latest_justified,
    const LanternCheckpoint *latest_finalized,
    const LanternRoot *block_root_hint, const LanternState *anchor_state);

int lantern_fork_choice_add_block(LanternStore *store,
                                  const LanternBlock *block,
                                  const LanternCheckpoint *post_justified,
                                  const LanternCheckpoint *post_finalized,
                                  const LanternRoot *block_root_hint);
/**
 * Add a block and an owned copy of its post-state, then recompute the head.
 *
 * Configured storage persists the copy before cache admission. Cached copies
 * can be evicted, but block ancestry and persisted states remain available.
 *
 * @param[in,out] store Initialized store. Must not be NULL.
 * @param[in] block Block whose parent is known. Must not be NULL.
 * @param[in] post_justified Optional justified checkpoint to consider.
 * @param[in] post_finalized Optional checkpoint used only without post_state.
 * @param[in] block_root_hint Optional known root; NULL computes the block root.
 * @param[in] post_state Optional initialized state, borrowed for this call.
 * NULL adds metadata only, and a selected head must then be loadable if storage
 * is configured. Non-NULL state may alias a cached state because it is cloned
 * before cache mutation.
 * @return 0 on success; -1 for invalid arguments, allocation/storage failure,
 * or an unavailable required head state. Failed additions leave consensus
 * metadata unchanged. Successful storage writes and cache eviction can remain
 * after a later failure; caller-owned inputs are not modified.
 * @note The caller must exclude concurrent store access.
 */
int lantern_fork_choice_add_block_with_state(
    LanternStore *store, const LanternBlock *block,
    const LanternCheckpoint *post_justified,
    const LanternCheckpoint *post_finalized, const LanternRoot *block_root_hint,
    const LanternState *post_state);

int lantern_fork_choice_update_checkpoints(
    LanternStore *store, const LanternCheckpoint *latest_justified,
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
    LanternStore *store, const LanternCheckpoint *latest_justified,
    const LanternCheckpoint *latest_finalized);
int lantern_fork_choice_prune_states(LanternStore *store);

int lantern_fork_choice_accept_new_aggregated_payloads(LanternStore *store);
int lantern_fork_choice_update_safe_target(LanternStore *store);
int lantern_fork_choice_recompute_head(LanternStore *store);

int lantern_fork_choice_advance_to(LanternStore *store,
                                   uint64_t target_interval, bool has_proposal);

int lantern_fork_choice_block_info(const LanternStore *store,
                                   const LanternRoot *root, uint64_t *out_slot,
                                   LanternRoot *out_parent_root,
                                   bool *out_has_parent);
/**
 * Replace a known block's cached state with an owned copy.
 *
 * @param[in,out] store Initialized store, synchronized by the caller; not NULL.
 * @param[in] root Known block root; not NULL.
 * @param[in] state Initialized state to clone; not NULL. May alias the old copy.
 * @return 0 after optional write-through persistence and cache admission;
 * -1 for invalid inputs, unknown root, allocation or storage failure, leaving
 * the old cached state unchanged. Success can evict another cached state.
 * @note The input remains caller-owned. Borrowed cached pointers can be
 * invalidated by this operation; block metadata and checkpoints are unchanged.
 */
int lantern_fork_choice_set_block_state(LanternStore *store,
                                        const LanternRoot *root,
                                        const LanternState *state);
/**
 * Borrow a known block's post-state, loading it from configured storage if cold.
 *
 * @param[in] store Initialized store; NULL returns NULL. The logical store is
 * unchanged, but a disk-backed read can populate and evict cached allocations.
 * @param[in] root Block root to resolve; NULL returns NULL.
 * @return Borrowed state, or NULL for an unknown root, unavailable/invalid state,
 * or allocation failure. The pointer lasts until the next cache mutation or
 * store mutation; consume or clone it before another state lookup. The head's
 * cached state is protected from eviction while it remains the head.
 * @note Callers synchronize all access, including these reads. A failed load
 * does not evict a cached state or alter consensus metadata.
 */
const LanternState *lantern_fork_choice_block_state(const LanternStore *store,
                                                    const LanternRoot *root);
bool lantern_fork_choice_read_checkpoint_snapshot(
    const LanternStore *store, LanternCheckpoint *out_justified,
    LanternCheckpoint *out_finalized);
void lantern_fork_choice_tree_snapshot_reset(
    struct lantern_fork_choice_tree_snapshot *snapshot);
int lantern_fork_choice_snapshot_tree(
    const LanternStore *store,
    struct lantern_fork_choice_tree_snapshot *out_snapshot);

#ifdef __cplusplus
}
#endif

#endif /* LANTERN_CONSENSUS_FORK_CHOICE_H */
