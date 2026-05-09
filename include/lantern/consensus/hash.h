#ifndef LANTERN_CONSENSUS_HASH_H
#define LANTERN_CONSENSUS_HASH_H

#include <stddef.h>

#include "ssz_types.h"

#include "lantern/consensus/containers.h"
#include "lantern/consensus/state.h"

ssz_error_t lantern_hash_tree_root_config(const LanternConfig *config, LanternRoot *out_root);
ssz_error_t lantern_hash_tree_root_checkpoint(const LanternCheckpoint *checkpoint, LanternRoot *out_root);
ssz_error_t lantern_hash_tree_root_attestation_data(const LanternAttestationData *data, LanternRoot *out_root);
ssz_error_t lantern_hash_tree_root_vote(const LanternVote *vote, LanternRoot *out_root);
ssz_error_t lantern_hash_tree_root_signed_vote(const LanternSignedVote *vote, LanternRoot *out_root);
ssz_error_t lantern_hash_tree_root_signature(const LanternSignature *signature, LanternRoot *out_root);
ssz_error_t lantern_hash_tree_root_validator(const LanternValidator *validator, LanternRoot *out_root);
ssz_error_t lantern_hash_tree_root_aggregated_attestation(const LanternAggregatedAttestation *attestation, LanternRoot *out_root);
ssz_error_t lantern_hash_tree_root_aggregated_signature_proof(
    const LanternAggregatedSignatureProof *proof,
    LanternRoot *out_root);
ssz_error_t lantern_hash_tree_root_signed_aggregated_attestation(
    const LanternSignedAggregatedAttestation *attestation,
    LanternRoot *out_root);
ssz_error_t lantern_hash_tree_root_block_signatures(
    const LanternBlockSignatures *signatures,
    LanternRoot *out_root);
ssz_error_t lantern_hash_tree_root_block_body(const LanternBlockBody *body, LanternRoot *out_root);
ssz_error_t lantern_hash_tree_root_block_header(const LanternBlockHeader *header, LanternRoot *out_root);
ssz_error_t lantern_hash_tree_root_block(const LanternBlock *block, LanternRoot *out_root);
ssz_error_t lantern_hash_tree_root_signed_block(const LanternSignedBlock *block, LanternRoot *out_root);
ssz_error_t lantern_hash_tree_root_state(const LanternState *state, LanternRoot *out_root);
ssz_error_t lantern_hash_tree_root_state_cached(LanternState *state, LanternRoot *out_root);
ssz_error_t lantern_hash_tree_root_validators(const uint8_t *pubkeys, size_t count, LanternRoot *out_root);
ssz_error_t lantern_hash_tree_root_validators_dual(
    const uint8_t *attestation_pubkeys,
    const uint8_t *proposal_pubkeys,
    size_t count,
    LanternRoot *out_root);
void lantern_state_hash_cache_reset(LanternState *state);

ssz_error_t lantern_merkleize_root_list(
    const struct lantern_root_list *list,
    size_t limit,
    LanternRoot *out_root);
ssz_error_t lantern_merkleize_bitlist(
    const struct lantern_bitlist *bitlist,
    size_t limit,
    LanternRoot *out_root);

#endif /* LANTERN_CONSENSUS_HASH_H */
