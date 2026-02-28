#ifndef LANTERN_CONSENSUS_HASH_H
#define LANTERN_CONSENSUS_HASH_H

#include <stddef.h>

#include "lantern/consensus/containers.h"
#include "lantern/consensus/state.h"

int lantern_hash_tree_root_config(const LanternConfig *config, LanternRoot *out_root);
int lantern_hash_tree_root_checkpoint(const LanternCheckpoint *checkpoint, LanternRoot *out_root);
int lantern_hash_tree_root_attestation_data(const LanternAttestationData *data, LanternRoot *out_root);
int lantern_hash_tree_root_vote(const LanternVote *vote, LanternRoot *out_root);
int lantern_hash_tree_root_aggregated_attestation(const LanternAggregatedAttestation *attestation, LanternRoot *out_root);
int lantern_hash_tree_root_aggregated_signature_proof(
    const LanternAggregatedSignatureProof *proof,
    LanternRoot *out_root);
int lantern_hash_tree_root_block_body(const LanternBlockBody *body, LanternRoot *out_root);
int lantern_hash_tree_root_block_header(const LanternBlockHeader *header, LanternRoot *out_root);
int lantern_hash_tree_root_block(const LanternBlock *block, LanternRoot *out_root);
int lantern_hash_tree_root_block_with_attestation(const LanternBlockWithAttestation *block, LanternRoot *out_root);
int lantern_hash_tree_root_signed_block(const LanternSignedBlock *block, LanternRoot *out_root);
int lantern_hash_tree_root_state(const LanternState *state, LanternRoot *out_root);
int lantern_hash_tree_root_validators(const uint8_t *pubkeys, size_t count, LanternRoot *out_root);

int lantern_merkleize_root_list(
    const struct lantern_root_list *list,
    size_t limit,
    LanternRoot *out_root);
int lantern_merkleize_bitlist(
    const struct lantern_bitlist *bitlist,
    size_t limit,
    LanternRoot *out_root);

#endif /* LANTERN_CONSENSUS_HASH_H */
