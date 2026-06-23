#ifndef LANTERN_CONSENSUS_SIGNATURE_H
#define LANTERN_CONSENSUS_SIGNATURE_H

#include <stdbool.h>
#include <stddef.h>

#include "lantern/consensus/containers.h"
#include "lantern/consensus/state.h"

struct PQSignatureSchemeSecretKey;
struct PQSignatureSchemePublicKey;

typedef struct {
    const uint8_t *pubkey;
    const LanternSignature *signature;
} LanternRawXmssSignature;

bool lantern_signature_is_zero(const LanternSignature *signature);
void lantern_signature_zero(LanternSignature *signature);
void lantern_signature_prewarm_prover(void);
bool lantern_signature_verify(
    const uint8_t *pubkey_bytes,
    size_t pubkey_len,
    uint64_t epoch,
    const LanternSignature *signature,
    const LanternRoot *message);
bool lantern_signature_verify_pk(
    const struct PQSignatureSchemePublicKey *pubkey,
    uint64_t epoch,
    const LanternSignature *signature,
    const LanternRoot *message);
bool lantern_signature_sign(
    const struct PQSignatureSchemeSecretKey *secret_key,
    uint64_t epoch,
    const LanternRoot *message,
    LanternSignature *out_signature);
bool lantern_signature_aggregate(
    const uint8_t *const *pubkeys,
    const LanternSignature *signatures,
    size_t count,
    const LanternRoot *message,
    uint64_t epoch,
    LanternByteList *out_proof);
bool lantern_aggregated_signature_proof_aggregate(
    const LanternState *state,
    const struct lantern_bitlist *xmss_participants,
    const LanternAggregatedSignatureProof *children,
    size_t child_count,
    const LanternRawXmssSignature *raw_xmss,
    size_t raw_xmss_count,
    const LanternRoot *message,
    uint64_t epoch,
    LanternAggregatedSignatureProof *out_proof);
bool lantern_signature_verify_aggregated(
    const uint8_t *const *pubkeys,
    size_t count,
    const LanternRoot *message,
    const LanternByteList *proof,
    uint64_t epoch);
bool lantern_signature_wrap_type2_proof(
    const LanternByteList *raw_proof,
    LanternByteList *out_encoded);
bool lantern_signature_unwrap_type2_proof(
    const LanternByteList *encoded_proof,
    LanternByteList *out_raw);
bool lantern_signature_merge_block_type2_proof(
    const LanternState *state,
    const LanternBlock *block,
    const LanternAttestationSignatures *attestation_proofs,
    const LanternAggregatedSignatureProof *proposer_proof,
    LanternByteList *out_encoded_proof);
bool lantern_signature_verify_block_type2_proof(
    const LanternState *state,
    const LanternBlock *block,
    const LanternByteList *encoded_proof);
#endif /* LANTERN_CONSENSUS_SIGNATURE_H */
