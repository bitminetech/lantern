#ifndef LANTERN_CONSENSUS_SSZ_H
#define LANTERN_CONSENSUS_SSZ_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "lantern/consensus/containers.h"
#include "lantern/consensus/state.h"
#include "ssz_types.h"

#define LANTERN_CONFIG_SSZ_SIZE (sizeof(uint64_t))
#define LANTERN_CHECKPOINT_SSZ_SIZE (LANTERN_ROOT_SIZE + sizeof(uint64_t))
#define LANTERN_ATTESTATION_DATA_SSZ_SIZE (sizeof(uint64_t) + 3u * LANTERN_CHECKPOINT_SSZ_SIZE)
#define LANTERN_VOTE_SSZ_SIZE (sizeof(uint64_t) + LANTERN_ATTESTATION_DATA_SSZ_SIZE)
#define LANTERN_SIGNED_VOTE_SSZ_SIZE (LANTERN_VOTE_SSZ_SIZE + LANTERN_SIGNATURE_SIZE)
#define LANTERN_VALIDATOR_SSZ_SIZE ((2u * LANTERN_VALIDATOR_PUBKEY_SIZE) + sizeof(uint64_t))
#define LANTERN_BLOCK_HEADER_SSZ_SIZE (sizeof(uint64_t) * 2u + 3u * LANTERN_ROOT_SIZE)

ssz_error_t lantern_ssz_encode_config(const LanternConfig *config, uint8_t *out, size_t out_len, size_t *written);
ssz_error_t lantern_ssz_decode_config(LanternConfig *config, const uint8_t *data, size_t data_len);

ssz_error_t lantern_ssz_encode_checkpoint(const LanternCheckpoint *checkpoint, uint8_t *out, size_t out_len, size_t *written);
ssz_error_t lantern_ssz_decode_checkpoint(LanternCheckpoint *checkpoint, const uint8_t *data, size_t data_len);

ssz_error_t lantern_ssz_encode_attestation_data(
    const LanternAttestationData *data,
    uint8_t *out,
    size_t out_len,
    size_t *written);
ssz_error_t lantern_ssz_decode_attestation_data(
    LanternAttestationData *data,
    const uint8_t *raw,
    size_t raw_len);

ssz_error_t lantern_ssz_encode_vote(const LanternVote *vote, uint8_t *out, size_t out_len, size_t *written);
ssz_error_t lantern_ssz_decode_vote(LanternVote *vote, const uint8_t *data, size_t data_len);

ssz_error_t lantern_ssz_encode_signed_vote(const LanternSignedVote *vote, uint8_t *out, size_t out_len, size_t *written);
ssz_error_t lantern_ssz_decode_signed_vote(LanternSignedVote *vote, const uint8_t *data, size_t data_len);

ssz_error_t lantern_ssz_encode_signed_aggregated_attestation(
    const LanternSignedAggregatedAttestation *attestation,
    uint8_t *out,
    size_t out_len,
    size_t *written);
ssz_error_t lantern_ssz_decode_signed_aggregated_attestation(
    LanternSignedAggregatedAttestation *attestation,
    const uint8_t *data,
    size_t data_len);
ssz_error_t lantern_ssz_encode_aggregated_attestation(
    const LanternAggregatedAttestation *attestation,
    uint8_t *out,
    size_t remaining,
    size_t *written);
ssz_error_t lantern_ssz_decode_aggregated_attestation(
    LanternAggregatedAttestation *attestation,
    const uint8_t *data,
    size_t data_len);
ssz_error_t lantern_ssz_encode_aggregated_signature_proof(
    const LanternAggregatedSignatureProof *proof,
    uint8_t *out,
    size_t remaining,
    size_t *written);
ssz_error_t lantern_ssz_decode_aggregated_signature_proof(
    LanternAggregatedSignatureProof *proof,
    const uint8_t *data,
    size_t data_len);
ssz_error_t lantern_ssz_encode_multi_message_aggregate(
    const LanternByteList *aggregate,
    uint8_t *out,
    size_t remaining,
    size_t *written);
ssz_error_t lantern_ssz_decode_multi_message_aggregate(
    LanternByteList *aggregate,
    const uint8_t *data,
    size_t data_len);
ssz_error_t lantern_ssz_multi_message_aggregate_raw_span(
    const LanternByteList *aggregate,
    const uint8_t **out_raw,
    size_t *out_raw_len);
ssz_error_t lantern_ssz_encode_validator(
    const LanternValidator *validator,
    uint8_t *out,
    size_t remaining,
    size_t *written);
ssz_error_t lantern_ssz_decode_validator(
    LanternValidator *validator,
    const uint8_t *data,
    size_t data_len);

ssz_error_t lantern_ssz_encode_block_header(const LanternBlockHeader *header, uint8_t *out, size_t out_len, size_t *written);
ssz_error_t lantern_ssz_decode_block_header(LanternBlockHeader *header, const uint8_t *data, size_t data_len);

ssz_error_t lantern_ssz_encode_block_body(const LanternBlockBody *body, uint8_t *out, size_t out_len, size_t *written);
ssz_error_t lantern_ssz_decode_block_body(LanternBlockBody *body, const uint8_t *data, size_t data_len);

ssz_error_t lantern_ssz_encode_block(const LanternBlock *block, uint8_t *out, size_t out_len, size_t *written);
ssz_error_t lantern_ssz_decode_block(LanternBlock *block, const uint8_t *data, size_t data_len);

ssz_error_t lantern_ssz_encode_signed_block(const LanternSignedBlock *block, uint8_t *out, size_t out_len, size_t *written);
ssz_error_t lantern_ssz_decode_signed_block(LanternSignedBlock *block, const uint8_t *data, size_t data_len);

ssz_error_t lantern_ssz_encode_state(const LanternState *state, uint8_t *out, size_t out_len, size_t *written);
ssz_error_t lantern_ssz_decode_state(LanternState *state, const uint8_t *data, size_t data_len);

#endif /* LANTERN_CONSENSUS_SSZ_H */
