#include "lantern/networking/gossip_payloads.h"

#include <limits.h>
#include <stdlib.h>

#include "lantern/consensus/containers.h"
#include "lantern/consensus/ssz.h"
#include "lantern/encoding/snappy.h"
#include "ssz.h"

static uint8_t *alloc_buffer(size_t size) {
    if (size == 0) {
        return NULL;
    }
    return (uint8_t *)malloc(size);
}

static size_t bitlist_encoded_size_bits(size_t bit_length) {
    if (bit_length == 0) {
        return 1;
    }
    size_t byte_len = (bit_length + 7u) / 8u;
    if ((bit_length % 8u) == 0) {
        return byte_len + 1u;
    }
    return byte_len;
}

static size_t signed_block_base_ssz_size(void) {
    size_t block_fixed = (sizeof(uint64_t) * 2u)
        + (LANTERN_ROOT_SIZE * 2u)
        + SSZ_BYTES_PER_LENGTH_OFFSET;
    size_t body_header = SSZ_BYTES_PER_LENGTH_OFFSET; /* block body attestation offset */
    size_t message_base = block_fixed + body_header;
    size_t offsets = SSZ_BYTES_PER_LENGTH_OFFSET * 2u; /* message + signatures */
    return offsets + message_base;
}

static size_t signed_block_max_ssz_size(void) {
    size_t base = signed_block_base_ssz_size();
    size_t att_bits_max = bitlist_encoded_size_bits(LANTERN_VALIDATOR_REGISTRY_LIMIT);
    size_t att_entry_max = SSZ_BYTES_PER_LENGTH_OFFSET + LANTERN_ATTESTATION_DATA_SSZ_SIZE + att_bits_max;
    size_t attestations_max = (size_t)LANTERN_MAX_ATTESTATIONS * (SSZ_BYTES_PER_LENGTH_OFFSET + att_entry_max);
    if (attestations_max > SIZE_MAX - base) {
        return SIZE_MAX;
    }
    size_t total = base + attestations_max;
    size_t proof_max = SSZ_BYTES_PER_LENGTH_OFFSET + LANTERN_AGG_PROOF_MAX_BYTES;
    if (proof_max > SIZE_MAX - total) {
        return SIZE_MAX;
    }
    return total + proof_max;
}

static int basic_attestation_data_sanity(const LanternAttestationData *data) {
    if (!data) {
        return -1;
    }
    if (data->target.slot < data->source.slot) {
        return -1;
    }
    if (data->slot < data->target.slot) {
        return -1;
    }
    return 0;
}

static int basic_vote_sanity(const LanternVote *vote) {
    if (!vote) {
        return -1;
    }
    if (basic_attestation_data_sanity(&vote->data) != 0) {
        return -1;
    }
    return 0;
}

static int basic_block_sanity(const LanternSignedBlock *block) {
    if (!block) {
        return -1;
    }
    const LanternBlock *message = &block->block;
    for (size_t i = 0; i < message->body.attestations.length; ++i) {
        const LanternAggregatedAttestation *att = &message->body.attestations.data[i];
        if (basic_attestation_data_sanity(&att->data) != 0) {
            return -1;
        }
    }
    size_t att_count = message->body.attestations.length;
    (void)att_count;
    size_t proof_size = 0;
    if (lantern_ssz_encode_multi_message_aggregate(&block->proof, NULL, 0, &proof_size) != SSZ_SUCCESS) {
        return -1;
    }
    return 0;
}

static int basic_signed_aggregated_attestation_sanity(
    const LanternSignedAggregatedAttestation *attestation) {
    if (!attestation) {
        return -1;
    }
    if (basic_attestation_data_sanity(&attestation->data) != 0) {
        return -1;
    }
    if (attestation->proof.participants.bit_length == 0 || !attestation->proof.participants.bytes) {
        return -1;
    }
    if (attestation->proof.proof_data.length == 0 || !attestation->proof.proof_data.data) {
        return -1;
    }
    return 0;
}

static size_t signed_aggregated_attestation_max_ssz_size(void) {
    size_t bits_max = bitlist_encoded_size_bits(LANTERN_VALIDATOR_REGISTRY_LIMIT);
    size_t proof_max = (SSZ_BYTES_PER_LENGTH_OFFSET * 2u) + bits_max + LANTERN_AGG_PROOF_MAX_BYTES;
    size_t fixed = LANTERN_ATTESTATION_DATA_SSZ_SIZE + SSZ_BYTES_PER_LENGTH_OFFSET;
    if (proof_max > SIZE_MAX - fixed) {
        return SIZE_MAX;
    }
    return fixed + proof_max;
}

static int decode_snappy_payload(
    const uint8_t *data,
    size_t data_len,
    size_t min_raw_len,
    size_t max_raw_len,
    uint8_t **out_raw,
    size_t *out_raw_len) {
    if (!data || !out_raw || !out_raw_len || min_raw_len == 0 || min_raw_len > max_raw_len) {
        return -1;
    }
    *out_raw = NULL;
    *out_raw_len = 0;

    size_t raw_len = 0;
    if (lantern_snappy_uncompressed_length_raw(data, data_len, &raw_len) != LANTERN_SNAPPY_OK
        || raw_len < min_raw_len
        || raw_len > max_raw_len) {
        return -1;
    }
    uint8_t *raw = alloc_buffer(raw_len);
    if (!raw) {
        return -1;
    }
    size_t written = raw_len;
    if (lantern_snappy_decompress_raw(data, data_len, raw, raw_len, &written) != LANTERN_SNAPPY_OK
        || written != raw_len) {
        free(raw);
        return -1;
    }
    *out_raw = raw;
    *out_raw_len = raw_len;
    return 0;
}

int lantern_gossip_encode_signed_block_snappy(
    const LanternSignedBlock *block,
    uint8_t *out,
    size_t out_len,
    size_t *written) {
    if (!block || !out || !written) {
        return -1;
    }
    size_t raw_capacity = 0;
    if (lantern_ssz_encode_signed_block(block, NULL, 0, &raw_capacity) != SSZ_SUCCESS
        || raw_capacity == 0) {
        return -1;
    }
    uint8_t *raw = alloc_buffer(raw_capacity);
    if (!raw) {
        return -1;
    }
    size_t raw_written = raw_capacity;
    if (lantern_ssz_encode_signed_block(block, raw, raw_capacity, &raw_written) != SSZ_SUCCESS) {
        free(raw);
        return -1;
    }
    /* Use raw snappy (no framing) for gossip messages per Eth2 networking spec */
    int snappy_rc = lantern_snappy_compress_raw(raw, raw_written, out, out_len, written);
    free(raw);
    return snappy_rc == LANTERN_SNAPPY_OK ? 0 : -1;
}

int lantern_gossip_decode_signed_block_snappy(
    LanternSignedBlock *block,
    const uint8_t *data,
    size_t data_len,
    uint8_t **out_raw_block_ssz,
    size_t *out_raw_block_ssz_len) {
    if (!block || !data) {
        return -1;
    }
    if ((out_raw_block_ssz && !out_raw_block_ssz_len)
        || (!out_raw_block_ssz && out_raw_block_ssz_len)) {
        return -1;
    }
    if (out_raw_block_ssz) {
        *out_raw_block_ssz = NULL;
    }
    if (out_raw_block_ssz_len) {
        *out_raw_block_ssz_len = 0;
    }
    uint8_t *raw = NULL;
    size_t raw_len = 0;
    size_t max_ssz = signed_block_max_ssz_size();
    if (decode_snappy_payload(data, data_len, 1u, max_ssz, &raw, &raw_len) != 0
        || lantern_ssz_decode_signed_block(block, raw, raw_len) != SSZ_SUCCESS
        || basic_block_sanity(block) != 0) {
        free(raw);
        return -1;
    }
    if (out_raw_block_ssz) {
        *out_raw_block_ssz = raw;
        *out_raw_block_ssz_len = raw_len;
    } else {
        free(raw);
    }
    return 0;
}

int lantern_gossip_encode_signed_vote_snappy(
    const LanternSignedVote *vote,
    uint8_t *out,
    size_t out_len,
    size_t *written) {
    if (!vote || !out || !written) {
        return -1;
    }
    if (basic_vote_sanity(&vote->data) != 0) {
        return -1;
    }
    uint8_t raw[LANTERN_SIGNED_VOTE_SSZ_SIZE];
    size_t raw_written = sizeof(raw);
    if (lantern_ssz_encode_signed_vote(vote, raw, sizeof(raw), &raw_written) != SSZ_SUCCESS) {
        return -1;
    }
    /* Use raw snappy (no framing) for gossip messages per Eth2 networking spec */
    int snappy_rc = lantern_snappy_compress_raw(raw, raw_written, out, out_len, written);
    return snappy_rc == LANTERN_SNAPPY_OK ? 0 : -1;
}

int lantern_gossip_decode_signed_vote_snappy(
    LanternSignedVote *vote,
    const uint8_t *data,
    size_t data_len) {
    if (!vote || !data) {
        return -1;
    }
    uint8_t *raw = NULL;
    size_t raw_len = 0;
    if (decode_snappy_payload(
            data,
            data_len,
            LANTERN_SIGNED_VOTE_SSZ_SIZE,
            LANTERN_SIGNED_VOTE_SSZ_SIZE,
            &raw,
            &raw_len)
        != 0) {
        return -1;
    }
    ssz_error_t decode_rc = lantern_ssz_decode_signed_vote(vote, raw, raw_len);
    free(raw);
    return decode_rc == SSZ_SUCCESS && basic_vote_sanity(&vote->data) == 0 ? 0 : -1;
}

int lantern_gossip_encode_signed_aggregated_attestation_snappy(
    const LanternSignedAggregatedAttestation *attestation,
    uint8_t *out,
    size_t out_len,
    size_t *written) {
    if (!attestation || !out || !written) {
        return -1;
    }
    if (basic_signed_aggregated_attestation_sanity(attestation) != 0) {
        return -1;
    }
    size_t raw_capacity = 0;
    if (lantern_ssz_encode_signed_aggregated_attestation(attestation, NULL, 0, &raw_capacity) != SSZ_SUCCESS
        || raw_capacity == 0) {
        return -1;
    }
    uint8_t *raw = alloc_buffer(raw_capacity);
    if (!raw) {
        return -1;
    }
    size_t raw_written = raw_capacity;
    if (lantern_ssz_encode_signed_aggregated_attestation(attestation, raw, raw_capacity, &raw_written) != SSZ_SUCCESS) {
        free(raw);
        return -1;
    }
    int snappy_rc = lantern_snappy_compress_raw(raw, raw_written, out, out_len, written);
    free(raw);
    return snappy_rc == LANTERN_SNAPPY_OK ? 0 : -1;
}

int lantern_gossip_decode_signed_aggregated_attestation_snappy(
    LanternSignedAggregatedAttestation *attestation,
    const uint8_t *data,
    size_t data_len) {
    if (!attestation || !data) {
        return -1;
    }
    uint8_t *raw = NULL;
    size_t raw_len = 0;
    size_t max_ssz = signed_aggregated_attestation_max_ssz_size();
    size_t min_ssz = LANTERN_ATTESTATION_DATA_SSZ_SIZE + SSZ_BYTES_PER_LENGTH_OFFSET + 1u;
    if (decode_snappy_payload(data, data_len, min_ssz, max_ssz, &raw, &raw_len) != 0) {
        return -1;
    }
    ssz_error_t decode_rc = lantern_ssz_decode_signed_aggregated_attestation(attestation, raw, raw_len);
    free(raw);
    return decode_rc == SSZ_SUCCESS
            && basic_signed_aggregated_attestation_sanity(attestation) == 0
        ? 0
        : -1;
}
