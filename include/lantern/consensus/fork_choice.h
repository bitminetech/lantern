#ifndef LANTERN_CONSENSUS_FORK_CHOICE_H
#define LANTERN_CONSENSUS_FORK_CHOICE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "lantern/consensus/containers.h"
#include "lantern/consensus/state.h"

#ifdef __cplusplus
extern "C" {
#endif

struct lantern_fork_choice_vote_entry {
    bool has_checkpoint;
    LanternCheckpoint checkpoint;
    uint64_t slot;
};

struct lantern_aggregated_payload_pool;
struct lantern_attestation_data_by_root;

struct lantern_fork_choice_block_entry {
    LanternRoot root;
    LanternRoot parent_root;
    size_t parent_index;
    uint64_t slot;
    bool has_validator_count;
    uint64_t validator_count;
    bool has_justified;
    bool has_finalized;
    LanternCheckpoint latest_justified;
    LanternCheckpoint latest_finalized;
};

struct lantern_fork_choice_state_entry {
    bool has_state;
    LanternState state;
};

struct lantern_fork_choice_root_index_entry {
    LanternRoot root;
    size_t value;
    bool occupied;
    bool tombstone;
};

typedef struct lantern_fork_choice {
    bool initialized;
    bool has_anchor;
    LanternConfig config;
    uint32_t seconds_per_slot;
    uint32_t intervals_per_slot;
    uint64_t milliseconds_per_interval;
    uint64_t time_intervals;
    LanternCheckpoint latest_justified;
    LanternCheckpoint latest_finalized;
    LanternRoot head;
    bool has_head;
    LanternRoot safe_target;
    bool has_safe_target;

    struct lantern_fork_choice_block_entry *blocks;
    size_t block_len;
    size_t block_cap;

    struct lantern_fork_choice_state_entry *states;
    size_t state_cap;

    struct lantern_fork_choice_root_index_entry *index_entries;
    size_t index_cap;
    size_t index_len;

    struct lantern_fork_choice_vote_entry *known_votes;
    struct lantern_fork_choice_vote_entry *new_votes;
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
    const LanternSignedVote *proposer_attestation,
    const LanternCheckpoint *post_justified,
    const LanternCheckpoint *post_finalized,
    const LanternRoot *block_root_hint);
int lantern_fork_choice_add_block_with_state(
    LanternForkChoice *store,
    const LanternBlock *block,
    const LanternSignedVote *proposer_attestation,
    const LanternCheckpoint *post_justified,
    const LanternCheckpoint *post_finalized,
    const LanternRoot *block_root_hint,
    const LanternState *post_state);

int lantern_fork_choice_add_vote(
    LanternForkChoice *store,
    const LanternSignedVote *vote,
    bool from_block);

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
 * Any provided checkpoint root must already exist in the fork-choice store.
 */
int lantern_fork_choice_restore_checkpoints(
    LanternForkChoice *store,
    const LanternCheckpoint *latest_justified,
    const LanternCheckpoint *latest_finalized);

int lantern_fork_choice_accept_new_votes(LanternForkChoice *store);
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
const LanternCheckpoint *lantern_fork_choice_latest_justified(const LanternForkChoice *store);
const LanternCheckpoint *lantern_fork_choice_latest_finalized(const LanternForkChoice *store);
const LanternRoot *lantern_fork_choice_safe_target(const LanternForkChoice *store);
size_t lantern_fork_choice_new_votes_count(const LanternForkChoice *store);
size_t lantern_fork_choice_known_votes_count(const LanternForkChoice *store);

#ifdef __cplusplus
}
#endif

#endif /* LANTERN_CONSENSUS_FORK_CHOICE_H */
