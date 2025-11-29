#ifndef LANTERN_CONSENSUS_SSZ_H
#define LANTERN_CONSENSUS_SSZ_H

#include <stddef.h>
#include <stdint.h>

#include "lantern/consensus/containers.h"
#include "lantern/consensus/state.h"

#define LANTERN_CONFIG_SSZ_SIZE (sizeof(uint64_t))
#define LANTERN_CHECKPOINT_SSZ_SIZE (LANTERN_ROOT_SIZE + sizeof(uint64_t))
#define LANTERN_VOTE_SSZ_SIZE ((sizeof(uint64_t) * 2) + 3 * LANTERN_CHECKPOINT_SSZ_SIZE)
#define LANTERN_SIGNED_VOTE_SSZ_SIZE (LANTERN_VOTE_SSZ_SIZE + LANTERN_SIGNATURE_SIZE)
#define LANTERN_BLOCK_HEADER_SSZ_SIZE (sizeof(uint64_t) * 2 + 3 * LANTERN_ROOT_SIZE)

int lantern_ssz_encode_config(const LanternConfig *config, uint8_t *out, size_t out_len, size_t *written);
int lantern_ssz_decode_config(LanternConfig *config, const uint8_t *data, size_t data_len);

int lantern_ssz_encode_checkpoint(const LanternCheckpoint *checkpoint, uint8_t *out, size_t out_len, size_t *written);
int lantern_ssz_decode_checkpoint(LanternCheckpoint *checkpoint, const uint8_t *data, size_t data_len);

int lantern_ssz_encode_vote(const LanternVote *vote, uint8_t *out, size_t out_len, size_t *written);
int lantern_ssz_decode_vote(LanternVote *vote, const uint8_t *data, size_t data_len);

int lantern_ssz_encode_signed_vote(const LanternSignedVote *vote, uint8_t *out, size_t out_len, size_t *written);
int lantern_ssz_decode_signed_vote(LanternSignedVote *vote, const uint8_t *data, size_t data_len);

int lantern_ssz_encode_block_header(const LanternBlockHeader *header, uint8_t *out, size_t out_len, size_t *written);
int lantern_ssz_decode_block_header(LanternBlockHeader *header, const uint8_t *data, size_t data_len);

int lantern_ssz_encode_block_body(const LanternBlockBody *body, uint8_t *out, size_t out_len, size_t *written);
int lantern_ssz_decode_block_body(LanternBlockBody *body, const uint8_t *data, size_t data_len);

int lantern_ssz_encode_block(const LanternBlock *block, uint8_t *out, size_t out_len, size_t *written);
int lantern_ssz_decode_block(LanternBlock *block, const uint8_t *data, size_t data_len);

int lantern_ssz_encode_block_with_attestation(
    const LanternBlockWithAttestation *block,
    uint8_t *out,
    size_t out_len,
    size_t *written);
int lantern_ssz_decode_block_with_attestation(
    LanternBlockWithAttestation *block,
    const uint8_t *data,
    size_t data_len);

int lantern_ssz_encode_signed_block_with_attestation(
    const LanternSignedBlockWithAttestation *block,
    uint8_t *out,
    size_t out_len,
    size_t *written);
int lantern_ssz_decode_signed_block_with_attestation(
    LanternSignedBlockWithAttestation *block,
    const uint8_t *data,
    size_t data_len);

int lantern_ssz_encode_signed_block(const LanternSignedBlock *block, uint8_t *out, size_t out_len, size_t *written);
int lantern_ssz_decode_signed_block(LanternSignedBlock *block, const uint8_t *data, size_t data_len);

int lantern_ssz_encode_state(const LanternState *state, uint8_t *out, size_t out_len, size_t *written);
int lantern_ssz_decode_state(LanternState *state, const uint8_t *data, size_t data_len);

#endif /* LANTERN_CONSENSUS_SSZ_H */
