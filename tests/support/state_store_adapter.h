#ifndef LANTERN_TESTS_STATE_STORE_ADAPTER_H
#define LANTERN_TESTS_STATE_STORE_ADAPTER_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include "lantern/consensus/state.h"
#include "lantern/consensus/store.h"

#define lantern_state_init_explicit lantern_state_init
#define lantern_state_reset_explicit lantern_state_reset
#define lantern_state_clone_explicit lantern_state_clone
#define lantern_state_generate_genesis_explicit lantern_state_generate_genesis
#define lantern_state_process_attestations_explicit lantern_state_process_attestations
#define lantern_state_process_block_explicit lantern_state_process_block
#define lantern_state_transition_explicit lantern_state_transition
#define lantern_state_select_block_parent_explicit lantern_state_select_block_parent
#define lantern_state_collect_attestations_for_block_explicit lantern_state_collect_attestations_for_block
#define lantern_state_compute_vote_checkpoints_explicit lantern_state_compute_vote_checkpoints
#define lantern_state_preview_post_state_root_explicit lantern_state_preview_post_state_root

enum { LANTERN_TEST_STATE_STORE_SLOT_CAP = 64 };

struct lantern_test_state_store_slot {
    LanternState *state;
    LanternStore store;
    bool in_use;
};

struct lantern_test_state_store_slot *lantern_test_state_store_slots(void);
struct lantern_test_state_store_slot *lantern_test_state_store_find_slot(const LanternState *state);
LanternStore *lantern_test_state_store_ensure(LanternState *state);
const LanternStore *lantern_test_state_store_find(const LanternState *state);
void lantern_test_state_store_release(LanternState *state);

static inline void lantern_test_state_init(LanternState *state) {
    lantern_test_state_store_release(state);
    lantern_state_init_explicit(state);
}

static inline void lantern_test_state_reset(LanternState *state) {
    lantern_test_state_store_release(state);
    lantern_state_reset_explicit(state);
}

static inline int lantern_test_state_clone(const LanternState *source, LanternState *dest) {
    int rc = lantern_state_clone_explicit(source, dest);
    if (rc != 0) {
        return rc;
    }
    const LanternStore *source_store = lantern_test_state_store_find(source);
    if (!source_store) {
        return 0;
    }
    LanternStore *dest_store = lantern_test_state_store_ensure(dest);
    if (!dest_store) {
        lantern_state_reset_explicit(dest);
        return -1;
    }
    if (lantern_store_clone_validator_votes(source_store, dest_store) != 0) {
        lantern_test_state_reset(dest);
        return -1;
    }
    return 0;
}

static inline int lantern_test_state_generate_genesis(
    LanternState *state,
    uint64_t genesis_time,
    uint64_t num_validators) {
    int rc = lantern_state_generate_genesis_explicit(state, genesis_time, num_validators);
    if (rc != 0) {
        return rc;
    }
    LanternStore *store = lantern_test_state_store_ensure(state);
    if (!store) {
        return -1;
    }
    return lantern_store_prepare_validator_votes(store, num_validators);
}

static inline int lantern_test_state_prepare_validator_votes(LanternState *state, uint64_t validator_count) {
    LanternStore *store = lantern_test_state_store_ensure(state);
    return store ? lantern_store_prepare_validator_votes(store, validator_count) : -1;
}

static inline size_t lantern_test_state_validator_capacity(const LanternState *state) {
    const LanternStore *store = lantern_test_state_store_find(state);
    return store ? lantern_store_validator_capacity(store) : 0u;
}

static inline bool lantern_test_state_validator_has_vote(const LanternState *state, size_t index) {
    const LanternStore *store = lantern_test_state_store_find(state);
    return store ? lantern_store_validator_has_vote(store, index) : false;
}

static inline int lantern_test_state_get_signed_validator_vote(
    const LanternState *state,
    size_t index,
    LanternSignedVote *out_vote) {
    const LanternStore *store = lantern_test_state_store_find(state);
    return store ? lantern_store_get_signed_validator_vote(store, index, out_vote) : -1;
}

static inline int lantern_test_state_get_validator_vote(
    const LanternState *state,
    size_t index,
    LanternVote *out_vote) {
    const LanternStore *store = lantern_test_state_store_find(state);
    return store ? lantern_store_get_validator_vote(store, index, out_vote) : -1;
}

static inline int lantern_test_state_set_signed_validator_vote(
    LanternState *state,
    size_t index,
    const LanternSignedVote *vote) {
    LanternStore *store = lantern_test_state_store_ensure(state);
    return store ? lantern_store_set_signed_validator_vote(store, index, vote) : -1;
}

static inline int lantern_test_state_set_validator_vote(
    LanternState *state,
    size_t index,
    const LanternVote *vote) {
    LanternStore *store = lantern_test_state_store_ensure(state);
    return store ? lantern_store_set_validator_vote(store, index, vote) : -1;
}

static inline void lantern_test_state_clear_validator_vote(LanternState *state, size_t index) {
    LanternStore *store = lantern_test_state_store_ensure(state);
    if (store) {
        lantern_store_clear_validator_vote(store, index);
    }
}

static inline void lantern_test_state_attach_fork_choice(
    LanternState *state,
    struct lantern_fork_choice *fork_choice) {
    LanternStore *store = lantern_test_state_store_ensure(state);
    if (store) {
        lantern_store_attach_fork_choice(store, fork_choice);
    }
}

#define lantern_state_init(state) lantern_test_state_init((state))
#define lantern_state_reset(state) lantern_test_state_reset((state))
#define lantern_state_clone(source, dest) lantern_test_state_clone((source), (dest))
#define lantern_state_generate_genesis(state, genesis_time, num_validators) \
    lantern_test_state_generate_genesis((state), (genesis_time), (num_validators))
#define lantern_state_prepare_validator_votes(state, validator_count) \
    lantern_test_state_prepare_validator_votes((state), (validator_count))
#define lantern_state_validator_capacity(state) lantern_test_state_validator_capacity((state))
#define lantern_state_validator_has_vote(state, index) \
    lantern_test_state_validator_has_vote((state), (index))
#define lantern_state_get_signed_validator_vote(state, index, out_vote) \
    lantern_test_state_get_signed_validator_vote((state), (index), (out_vote))
#define lantern_state_get_validator_vote(state, index, out_vote) \
    lantern_test_state_get_validator_vote((state), (index), (out_vote))
#define lantern_state_set_signed_validator_vote(state, index, vote) \
    lantern_test_state_set_signed_validator_vote((state), (index), (vote))
#define lantern_state_set_validator_vote(state, index, vote) \
    lantern_test_state_set_validator_vote((state), (index), (vote))
#define lantern_state_clear_validator_vote(state, index) \
    lantern_test_state_clear_validator_vote((state), (index))
#define lantern_state_attach_fork_choice(state, fork_choice) \
    lantern_test_state_attach_fork_choice((state), (fork_choice))
#define lantern_state_process_attestations(state, attestations, signatures) \
    lantern_state_process_attestations_explicit( \
        (state), \
        lantern_test_state_store_ensure((state)), \
        (attestations), \
        (signatures))
#define lantern_state_process_block(state, block, signatures, proposer_attestation) \
    lantern_state_process_block_explicit( \
        (state), \
        lantern_test_state_store_ensure((state)), \
        (block), \
        (signatures), \
        (proposer_attestation))
#define lantern_state_transition(state, signed_block) \
    lantern_state_transition_explicit( \
        (state), \
        lantern_test_state_store_ensure((state)), \
        (signed_block))
#define lantern_state_select_block_parent(state, out_parent_root) \
    lantern_state_select_block_parent_explicit( \
        (state), \
        lantern_test_state_store_ensure((state)), \
        (out_parent_root))
#define lantern_state_collect_attestations_for_block( \
    state, block_slot, proposer_index, parent_root, proposer_attestation, out_attestations, out_signatures) \
    lantern_state_collect_attestations_for_block_explicit( \
        (state), \
        lantern_test_state_store_ensure((LanternState *)(state)), \
        (block_slot), \
        (proposer_index), \
        (parent_root), \
        (proposer_attestation), \
        (out_attestations), \
        (out_signatures))
#define lantern_state_compute_vote_checkpoints(state, out_head, out_target, out_source) \
    lantern_state_compute_vote_checkpoints_explicit( \
        (state), \
        lantern_test_state_store_ensure((LanternState *)(state)), \
        (out_head), \
        (out_target), \
        (out_source))
#define lantern_state_preview_post_state_root(state, block, out_state_root) \
    lantern_state_preview_post_state_root_explicit( \
        (state), \
        lantern_test_state_store_ensure((LanternState *)(state)), \
        (block), \
        (out_state_root))

#endif /* LANTERN_TESTS_STATE_STORE_ADAPTER_H */
