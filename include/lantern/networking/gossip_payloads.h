#ifndef LANTERN_NETWORKING_GOSSIP_PAYLOADS_H
#define LANTERN_NETWORKING_GOSSIP_PAYLOADS_H

#include <stddef.h>
#include <stdint.h>

#include "lantern/consensus/containers.h"

int lantern_gossip_encode_signed_block_snappy(
    const LanternSignedBlock *block,
    uint8_t *out,
    size_t out_len,
    size_t *written);

int lantern_gossip_decode_signed_block_snappy(
    LanternSignedBlock *block,
    const uint8_t *data,
    size_t data_len);

int lantern_gossip_encode_signed_vote_snappy(
    const LanternSignedVote *vote,
    uint8_t *out,
    size_t out_len,
    size_t *written);

int lantern_gossip_decode_signed_vote_snappy(
    LanternSignedVote *vote,
    const uint8_t *data,
    size_t data_len);

int lantern_gossip_encode_signed_aggregated_attestation_snappy(
    const LanternSignedAggregatedAttestation *attestation,
    uint8_t *out,
    size_t out_len,
    size_t *written);

int lantern_gossip_decode_signed_aggregated_attestation_snappy(
    LanternSignedAggregatedAttestation *attestation,
    const uint8_t *data,
    size_t data_len);

#endif /* LANTERN_NETWORKING_GOSSIP_PAYLOADS_H */
