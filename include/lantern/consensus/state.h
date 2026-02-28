#ifndef LANTERN_CONSENSUS_STATE_H
#define LANTERN_CONSENSUS_STATE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "lantern/consensus/containers.h"

struct lantern_vote_record;
struct lantern_fork_choice;

struct lantern_root_list {
    LanternRoot *items;
    size_t length;
    size_t capacity;
};

typedef struct {
    LanternConfig config;
    uint64_t slot;
    LanternBlockHeader latest_block_header;
    LanternCheckpoint latest_justified;
    LanternCheckpoint latest_finalized;
    struct lantern_root_list historical_block_hashes;
    uint64_t historical_roots_offset;
    struct lantern_bitlist justified_slots;
    uint64_t justified_slots_offset;
    struct lantern_root_list justification_roots;
    struct lantern_bitlist justification_validators;
    struct lantern_vote_record *validator_votes;
    size_t validator_votes_len;
    LanternValidator *validators;
    size_t validator_count;
    size_t validator_capacity;
    struct lantern_fork_choice *fork_choice;
    LanternRoot validator_registry_root;
} LanternState;

void lantern_root_list_init(struct lantern_root_list *list);
void lantern_root_list_reset(struct lantern_root_list *list);
int lantern_root_list_resize(struct lantern_root_list *list, size_t new_length);

void lantern_state_init(LanternState *state);
void lantern_state_reset(LanternState *state);
int lantern_state_clone(const LanternState *source, LanternState *dest);
void lantern_state_attach_fork_choice(LanternState *state, struct lantern_fork_choice *fork_choice);
int lantern_state_generate_genesis(LanternState *state, uint64_t genesis_time, uint64_t num_validators);
int lantern_state_process_slot(LanternState *state);
int lantern_state_process_slots(LanternState *state, uint64_t target_slot);
int lantern_state_process_block_header(LanternState *state, const LanternBlock *block);
int lantern_state_process_attestations(
    LanternState *state,
    const LanternAttestations *attestations,
    const LanternSignatureList *signatures);
int lantern_state_process_block(
    LanternState *state,
    const LanternBlock *block,
    const LanternBlockSignatures *signatures,
    const LanternSignedVote *proposer_attestation);
bool lantern_state_slot_in_justified_window(const LanternState *state, uint64_t slot);
int lantern_state_get_justified_slot_bit(const LanternState *state, uint64_t slot, bool *out_value);
int lantern_state_mark_justified_slot(LanternState *state, uint64_t slot);
int lantern_state_transition(LanternState *state, const LanternSignedBlock *signed_block);
int lantern_state_prepare_validator_votes(LanternState *state, uint64_t validator_count);
size_t lantern_state_validator_capacity(const LanternState *state);
bool lantern_state_validator_has_vote(const LanternState *state, size_t index);
int lantern_state_get_signed_validator_vote(
    const LanternState *state,
    size_t index,
    LanternSignedVote *out_vote);
int lantern_state_get_validator_vote(const LanternState *state, size_t index, LanternVote *out_vote);
int lantern_state_set_signed_validator_vote(
    LanternState *state,
    size_t index,
    const LanternSignedVote *vote);
int lantern_state_set_validator_vote(LanternState *state, size_t index, const LanternVote *vote);
void lantern_state_clear_validator_vote(LanternState *state, size_t index);
int lantern_state_set_validator_pubkeys(LanternState *state, const uint8_t *pubkeys, size_t count);
size_t lantern_state_validator_count(const LanternState *state);
const uint8_t *lantern_state_validator_pubkey(const LanternState *state, size_t index);
int lantern_state_select_block_parent(LanternState *state, LanternRoot *out_parent_root);
int lantern_state_collect_attestations_for_block(
    const LanternState *state,
    uint64_t block_slot,
    uint64_t proposer_index,
    const LanternRoot *parent_root,
    const LanternSignedVote *proposer_attestation,
    LanternAttestations *out_attestations,
    LanternSignatureList *out_signatures);
int lantern_state_compute_vote_checkpoints(
    const LanternState *state,
    LanternCheckpoint *out_head,
    LanternCheckpoint *out_target,
    LanternCheckpoint *out_source);
int lantern_state_preview_post_state_root(
    const LanternState *state,
    const LanternSignedBlock *block,
    LanternRoot *out_state_root);

#endif /* LANTERN_CONSENSUS_STATE_H */
