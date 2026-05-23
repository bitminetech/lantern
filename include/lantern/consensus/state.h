#ifndef LANTERN_CONSENSUS_STATE_H
#define LANTERN_CONSENSUS_STATE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "lantern/consensus/containers.h"

typedef struct lantern_store LanternStore;
struct lantern_attestation_signature_map;
struct lantern_aggregated_payload_pool;
struct lantern_state_hash_cache;

typedef struct {
    const LanternAttestations *attestations;
    const LanternSignatureList *signatures;
} LanternAttestationSignatureInputs;

typedef enum {
    LANTERN_STATE_AGGREGATE_OK = 0,
    LANTERN_STATE_AGGREGATE_INVALID_PARAM = -1,
    LANTERN_STATE_AGGREGATE_ALLOC = -2,
    LANTERN_STATE_AGGREGATE_VALIDATOR = -3,
    LANTERN_STATE_AGGREGATE_RUNTIME = -4
} lantern_state_aggregate_result;

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
    struct lantern_bitlist justified_slots;
    struct lantern_root_list justification_roots;
    struct lantern_bitlist justification_validators;
    LanternValidator *validators;
    size_t validator_count;
    size_t validator_capacity;
    struct lantern_state_hash_cache *hash_cache;
} LanternState;

void lantern_root_list_init(struct lantern_root_list *list);
void lantern_root_list_reset(struct lantern_root_list *list);
int lantern_root_list_resize(struct lantern_root_list *list, size_t new_length);

void lantern_state_init(LanternState *state);
void lantern_state_reset(LanternState *state);
int lantern_state_clone(const LanternState *source, LanternState *dest);
int lantern_state_generate_genesis(LanternState *state, uint64_t genesis_time, uint64_t num_validators);
int lantern_state_process_slot(LanternState *state);
int lantern_state_process_slots(LanternState *state, uint64_t target_slot);
int lantern_state_process_block_header(LanternState *state, const LanternBlock *block);
int lantern_state_process_attestations(
    LanternState *state,
    LanternStore *store,
    const LanternAttestations *attestations,
    const LanternSignatureList *signatures);
int lantern_state_process_block(
    LanternState *state,
    LanternStore *store,
    const LanternBlock *block,
    const LanternBlockSignatures *signatures);
bool lantern_state_slot_in_justified_window(const LanternState *state, uint64_t slot);
int lantern_state_get_justified_slot_bit(const LanternState *state, uint64_t slot, bool *out_value);
int lantern_state_mark_justified_slot(LanternState *state, uint64_t slot);
int lantern_state_transition(LanternState *state, LanternStore *store, const LanternSignedBlock *signed_block);
int lantern_state_set_validator_pubkeys(LanternState *state, const uint8_t *pubkeys, size_t count);
int lantern_state_set_validator_pubkeys_dual(
    LanternState *state,
    const uint8_t *attestation_pubkeys,
    const uint8_t *proposal_pubkeys,
    size_t count);
size_t lantern_state_validator_count(const LanternState *state);
const uint8_t *lantern_state_validator_pubkey(const LanternState *state, size_t index);
const uint8_t *lantern_state_validator_attestation_pubkey(const LanternState *state, size_t index);
const uint8_t *lantern_state_validator_proposal_pubkey(const LanternState *state, size_t index);
int lantern_state_select_block_parent(
    LanternState *state,
    const LanternStore *store,
    LanternRoot *out_parent_root);
int lantern_state_collect_attestations_for_block(
    const LanternState *state,
    const LanternStore *store,
    uint64_t block_slot,
    uint64_t proposer_index,
    const LanternRoot *parent_root,
    LanternAggregatedAttestations *out_attestations,
    LanternAttestationSignatures *out_signatures);
int lantern_state_compute_vote_checkpoints(
    const LanternState *state,
    const LanternStore *store,
    LanternCheckpoint *out_head,
    LanternCheckpoint *out_target,
    LanternCheckpoint *out_source);
int lantern_state_compute_post_state(
    const LanternState *state,
    const LanternStore *store,
    const LanternSignedBlock *block,
    LanternState *out_post_state,
    LanternStore *out_post_store,
    LanternRoot *out_state_root);
int lantern_state_preview_post_state_root(
    const LanternState *state,
    const LanternStore *store,
    const LanternSignedBlock *block,
    LanternRoot *out_state_root);
lantern_state_aggregate_result lantern_state_aggregate(
    const LanternState *state,
    const LanternStore *store,
    const LanternAttestationSignatureInputs *attestation_signatures,
    const struct lantern_aggregated_payload_pool *new_payloads,
    const struct lantern_aggregated_payload_pool *known_payloads,
    LanternAggregatedAttestations *out_attestations,
    LanternAttestationSignatures *out_signatures);

#endif /* LANTERN_CONSENSUS_STATE_H */
