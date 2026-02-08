#include "lantern/networking/gossip_payloads.h"

#include <limits.h>
#include <stdlib.h>
#include <string.h>

#include "lantern/consensus/containers.h"
#include "lantern/consensus/ssz.h"
#include "lantern/encoding/snappy.h"
#include "lantern/support/log.h"
#include "ssz_constants.h"

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

static size_t aggregated_attestation_encoded_size(const LanternAggregatedAttestation *attestation) {
    if (!attestation) {
        return 0;
    }
    if (attestation->aggregation_bits.bit_length > LANTERN_VALIDATOR_REGISTRY_LIMIT) {
        return 0;
    }
    size_t bits_size = bitlist_encoded_size_bits(attestation->aggregation_bits.bit_length);
    size_t fixed_section = SSZ_BYTE_SIZE_OF_UINT32 + LANTERN_ATTESTATION_DATA_SSZ_SIZE;
    if (fixed_section > SIZE_MAX - bits_size) {
        return 0;
    }
    return fixed_section + bits_size;
}

static size_t aggregated_attestations_encoded_size(const LanternAggregatedAttestations *attestations) {
    if (!attestations) {
        return 0;
    }
    if (attestations->length == 0) {
        return 0;
    }
    if (attestations->length > LANTERN_MAX_ATTESTATIONS || !attestations->data) {
        return 0;
    }
    size_t offset_table = attestations->length * SSZ_BYTE_SIZE_OF_UINT32;
    size_t total = offset_table;
    for (size_t i = 0; i < attestations->length; ++i) {
        size_t entry = aggregated_attestation_encoded_size(&attestations->data[i]);
        if (entry == 0 || entry > SIZE_MAX - total) {
            return 0;
        }
        total += entry;
    }
    return total;
}

static size_t aggregated_signature_proof_encoded_size(const LanternAggregatedSignatureProof *proof) {
    if (!proof) {
        return 0;
    }
    if (proof->participants.bit_length > LANTERN_VALIDATOR_REGISTRY_LIMIT) {
        return 0;
    }
    if (proof->proof_data.length > LANTERN_AGG_PROOF_MAX_BYTES) {
        return 0;
    }
    size_t participants_size = bitlist_encoded_size_bits(proof->participants.bit_length);
    size_t fixed_section = SSZ_BYTE_SIZE_OF_UINT32 * 2u;
    if (fixed_section > SIZE_MAX - participants_size) {
        return 0;
    }
    if (fixed_section + participants_size > SIZE_MAX - proof->proof_data.length) {
        return 0;
    }
    return fixed_section + participants_size + proof->proof_data.length;
}

static size_t attestation_signatures_encoded_size(const LanternAttestationSignatures *signatures) {
    if (!signatures) {
        return 0;
    }
    if (signatures->length == 0) {
        return 0;
    }
    if (signatures->length > LANTERN_MAX_BLOCK_SIGNATURES || !signatures->data) {
        return 0;
    }
    size_t offset_table = signatures->length * SSZ_BYTE_SIZE_OF_UINT32;
    size_t total = offset_table;
    for (size_t i = 0; i < signatures->length; ++i) {
        size_t entry = aggregated_signature_proof_encoded_size(&signatures->data[i]);
        if (entry == 0 || entry > SIZE_MAX - total) {
            return 0;
        }
        total += entry;
    }
    return total;
}

static size_t signed_block_base_ssz_size(void) {
    size_t block_fixed = (SSZ_BYTE_SIZE_OF_UINT64 * 2u)
        + (LANTERN_ROOT_SIZE * 2u)
        + SSZ_BYTE_SIZE_OF_UINT32;
    size_t body_header = SSZ_BYTE_SIZE_OF_UINT32; /* block body attestation offset */
    size_t message_base = SSZ_BYTE_SIZE_OF_UINT32 /* block offset */
        + LANTERN_VOTE_SSZ_SIZE /* proposer attestation */
        + block_fixed
        + body_header;
    size_t offsets = SSZ_BYTE_SIZE_OF_UINT32 * 2u; /* message + signatures */
    return offsets + message_base;
}

static size_t signed_block_max_ssz_size(void) {
    size_t base = signed_block_base_ssz_size();
    size_t att_bits_max = bitlist_encoded_size_bits(LANTERN_VALIDATOR_REGISTRY_LIMIT);
    size_t att_entry_max = SSZ_BYTE_SIZE_OF_UINT32 + LANTERN_ATTESTATION_DATA_SSZ_SIZE + att_bits_max;
    size_t attestations_max = (size_t)LANTERN_MAX_ATTESTATIONS * (SSZ_BYTE_SIZE_OF_UINT32 + att_entry_max);
    if (attestations_max > SIZE_MAX - base) {
        return SIZE_MAX;
    }
    size_t total = base + attestations_max;
    size_t proof_entry_max = (SSZ_BYTE_SIZE_OF_UINT32 * 2u) + att_bits_max + LANTERN_AGG_PROOF_MAX_BYTES;
    size_t signatures_max = (SSZ_BYTE_SIZE_OF_UINT32 * 2u) + LANTERN_SIGNATURE_SIZE
        + ((size_t)LANTERN_MAX_BLOCK_SIGNATURES * (SSZ_BYTE_SIZE_OF_UINT32 + proof_entry_max));
    if (signatures_max > SIZE_MAX - total) {
        return SIZE_MAX;
    }
    return total + signatures_max;
}

static size_t signed_block_min_capacity(const LanternSignedBlock *block) {
    if (!block) {
        return 0;
    }
    size_t base = signed_block_base_ssz_size();
    size_t att_count = block->message.block.body.attestations.length;
    size_t att_bytes = aggregated_attestations_encoded_size(&block->message.block.body.attestations);
    if (att_count > 0 && att_bytes == 0) {
        return 0;
    }
    size_t total = base;
    if (att_bytes > SIZE_MAX - total) {
        return 0;
    }
    total += att_bytes;
    size_t sig_count = block->signatures.attestation_signatures.length;
    size_t sig_list_bytes = attestation_signatures_encoded_size(&block->signatures.attestation_signatures);
    if (sig_count > 0 && sig_list_bytes == 0) {
        return 0;
    }
    size_t signature_bytes = (SSZ_BYTE_SIZE_OF_UINT32 * 2u) + LANTERN_SIGNATURE_SIZE + sig_list_bytes;
    if (signature_bytes > SIZE_MAX - total) {
        return 0;
    }
    return total + signature_bytes;
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
    const LanternBlock *message = &block->message.block;
    for (size_t i = 0; i < message->body.attestations.length; ++i) {
        const LanternAggregatedAttestation *att = &message->body.attestations.data[i];
        if (att->data.slot > message->slot) {
            return -1;
        }
        if (basic_attestation_data_sanity(&att->data) != 0) {
            return -1;
        }
    }
    if (basic_vote_sanity(&block->message.proposer_attestation) != 0) {
        return -1;
    }
    if (block->message.proposer_attestation.slot < message->slot) {
        return -1;
    }
    size_t sig_count = block->signatures.attestation_signatures.length;
    size_t att_count = message->body.attestations.length;
    if (sig_count > LANTERN_MAX_BLOCK_SIGNATURES) {
        return -1;
    }
    /* Compatibility mode: signature payload decoding may intentionally fall back to
     * an empty list for legacy/unknown encodings while still allowing block processing. */
    if (sig_count > 0 && sig_count != att_count) {
        return -1;
    }
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
    size_t raw_capacity = signed_block_min_capacity(block);
    if (raw_capacity == 0) {
        return -1;
    }
    uint8_t *raw = alloc_buffer(raw_capacity);
    if (!raw) {
        return -1;
    }
    size_t raw_written = raw_capacity;
    if (lantern_ssz_encode_signed_block_legacy(block, raw, raw_capacity, &raw_written) != 0) {
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
    size_t data_len) {
    if (!block || !data) {
        return -1;
    }
    size_t raw_len = 0;
    int raw_len_rc = lantern_snappy_uncompressed_length_raw(data, data_len, &raw_len);
    if (raw_len_rc != LANTERN_SNAPPY_OK) {
        bool framed = lantern_snappy_is_framed(data, data_len);
        size_t framed_len = 0;
        int framed_rc = framed ? lantern_snappy_uncompressed_length(data, data_len, &framed_len) : LANTERN_SNAPPY_ERROR_INVALID_INPUT;
        lantern_log_warn(
            "gossip",
            NULL,
            "gossip block snappy length failed raw_rc=%d framed=%s framed_rc=%d framed_len=%zu data_len=%zu",
            raw_len_rc,
            framed ? "true" : "false",
            framed_rc,
            framed_len,
            data_len);
        return -1;
    }
    size_t max_ssz = signed_block_max_ssz_size();
    if (raw_len == 0 || raw_len > max_ssz) {
        bool framed = lantern_snappy_is_framed(data, data_len);
        size_t framed_len = 0;
        int framed_rc = framed ? lantern_snappy_uncompressed_length(data, data_len, &framed_len) : LANTERN_SNAPPY_ERROR_INVALID_INPUT;
        lantern_log_warn(
            "gossip",
            NULL,
            "gossip block snappy length invalid raw_len=%zu max=%zu framed=%s framed_rc=%d framed_len=%zu data_len=%zu",
            raw_len,
            max_ssz,
            framed ? "true" : "false",
            framed_rc,
            framed_len,
            data_len);
        return -1;
    }
    uint8_t *raw = alloc_buffer(raw_len);
    if (!raw) {
        return -1;
    }
    size_t written = raw_len;
    int snappy_rc = lantern_snappy_decompress_raw(data, data_len, raw, raw_len, &written);
    if (snappy_rc != LANTERN_SNAPPY_OK) {
        free(raw);
        return -1;
    }
    int decode_rc = lantern_ssz_decode_signed_block(block, raw, written);
    free(raw);
    if (decode_rc != 0) {
        return -1;
    }
    if (basic_block_sanity(block) != 0) {
        return -1;
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
    if (lantern_ssz_encode_signed_vote_legacy(vote, raw, sizeof(raw), &raw_written) != 0) {
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
    size_t raw_len = 0;
    int raw_len_rc = lantern_snappy_uncompressed_length_raw(data, data_len, &raw_len);
    if (raw_len_rc != LANTERN_SNAPPY_OK) {
        bool framed = lantern_snappy_is_framed(data, data_len);
        size_t framed_len = 0;
        int framed_rc = framed ? lantern_snappy_uncompressed_length(data, data_len, &framed_len) : LANTERN_SNAPPY_ERROR_INVALID_INPUT;
        lantern_log_warn(
            "gossip",
            NULL,
            "gossip vote snappy length failed raw_rc=%d framed=%s framed_rc=%d framed_len=%zu data_len=%zu",
            raw_len_rc,
            framed ? "true" : "false",
            framed_rc,
            framed_len,
            data_len);
        return -1;
    }
    if (raw_len != LANTERN_SIGNED_VOTE_SSZ_SIZE
        && raw_len != LANTERN_SIGNED_VOTE_SSZ_SIZE_LEGACY) {
        bool framed = lantern_snappy_is_framed(data, data_len);
        size_t framed_len = 0;
        int framed_rc = framed ? lantern_snappy_uncompressed_length(data, data_len, &framed_len) : LANTERN_SNAPPY_ERROR_INVALID_INPUT;
        lantern_log_warn(
            "gossip",
            NULL,
            "gossip vote snappy length mismatch raw_len=%zu expected=%zu/%zu framed=%s framed_rc=%d framed_len=%zu data_len=%zu",
            raw_len,
            (size_t)LANTERN_SIGNED_VOTE_SSZ_SIZE,
            (size_t)LANTERN_SIGNED_VOTE_SSZ_SIZE_LEGACY,
            framed ? "true" : "false",
            framed_rc,
            framed_len,
            data_len);
        return -1;
    }
    uint8_t *raw = malloc(raw_len > 0 ? raw_len : 1u);
    if (!raw) {
        return -1;
    }
    size_t written = raw_len;
    int snappy_rc = lantern_snappy_decompress_raw(data, data_len, raw, raw_len, &written);
    if (snappy_rc != LANTERN_SNAPPY_OK) {
        free(raw);
        return -1;
    }
    if (written != raw_len) {
        free(raw);
        return -1;
    }
    if (lantern_ssz_decode_signed_vote(vote, raw, raw_len) != 0) {
        free(raw);
        return -1;
    }
    free(raw);
    if (basic_vote_sanity(&vote->data) != 0) {
        return -1;
    }
    return 0;
}
