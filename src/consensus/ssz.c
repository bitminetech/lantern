#include "lantern/consensus/ssz.h"

#include <inttypes.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>

#include "ssz_constants.h"
#include "ssz_deserialize.h"
#include "ssz_serialize.h"

#include "lantern/consensus/state.h"

static int write_u32(uint8_t *out, size_t remaining, uint32_t value) {
    if (!out || remaining < SSZ_BYTE_SIZE_OF_UINT32) {
        return -1;
    }
    size_t written = SSZ_BYTE_SIZE_OF_UINT32;
    ssz_error_t err = ssz_serialize_uint32(&value, out, &written);
    if (err != SSZ_SUCCESS || written != SSZ_BYTE_SIZE_OF_UINT32) {
        return -1;
    }
    return 0;
}

static int read_u32(const uint8_t *data, size_t remaining, uint32_t *value) {
    if (!data || !value || remaining < SSZ_BYTE_SIZE_OF_UINT32) {
        return -1;
    }
    ssz_error_t err = ssz_deserialize_uint32(data, SSZ_BYTE_SIZE_OF_UINT32, value);
    return err == SSZ_SUCCESS ? 0 : -1;
}

static int write_u64(uint8_t *out, size_t remaining, uint64_t value) {
    if (!out || remaining < SSZ_BYTE_SIZE_OF_UINT64) {
        return -1;
    }
    size_t written = SSZ_BYTE_SIZE_OF_UINT64;
    ssz_error_t err = ssz_serialize_uint64(&value, out, &written);
    if (err != SSZ_SUCCESS || written != SSZ_BYTE_SIZE_OF_UINT64) {
        return -1;
    }
    return 0;
}

static int read_u64(const uint8_t *data, size_t remaining, uint64_t *value) {
    if (!data || !value || remaining < SSZ_BYTE_SIZE_OF_UINT64) {
        return -1;
    }
    ssz_error_t err = ssz_deserialize_uint64(data, SSZ_BYTE_SIZE_OF_UINT64, value);
    return err == SSZ_SUCCESS ? 0 : -1;
}

static int write_root(uint8_t *out, size_t remaining, const LanternRoot *root) {
    if (!out || !root || remaining < LANTERN_ROOT_SIZE) {
        return -1;
    }
    memcpy(out, root->bytes, LANTERN_ROOT_SIZE);
    return 0;
}

static int read_root(const uint8_t *data, size_t remaining, LanternRoot *root) {
    if (!data || !root || remaining < LANTERN_ROOT_SIZE) {
        return -1;
    }
    memcpy(root->bytes, data, LANTERN_ROOT_SIZE);
    return 0;
}

static void set_written(size_t *written, size_t value) {
    if (written) {
        *written = value;
    }
}

static int encode_aggregated_attestations(
    const LanternAggregatedAttestations *attestations,
    uint8_t *out,
    size_t remaining,
    size_t *written);
static int decode_aggregated_attestations(
    LanternAggregatedAttestations *attestations,
    const uint8_t *data,
    size_t data_len);
static int encode_attestation_signatures(
    const LanternAttestationSignatures *signatures,
    uint8_t *out,
    size_t remaining,
    size_t *written);
static int decode_attestation_signatures(
    LanternAttestationSignatures *signatures,
    const uint8_t *data,
    size_t data_len);

static size_t bitlist_encoded_size(size_t bit_length) {
    if (bit_length == 0) {
        return 1;
    }
    size_t byte_len = (bit_length + 7u) / 8u;
    if ((bit_length % 8u) == 0) {
        return byte_len + 1u;
    }
    return byte_len;
}

static int encode_block_signatures(
    const LanternBlockSignatures *signatures,
    uint8_t *out,
    size_t remaining,
    size_t *written) {
    if (!signatures || !out) {
        return -1;
    }
    const size_t fixed_section = SSZ_BYTE_SIZE_OF_UINT32 * 2u;
    if (fixed_section > UINT32_MAX || remaining < fixed_section) {
        return -1;
    }

    size_t att_written = 0;
    if (encode_attestation_signatures(
            &signatures->attestation_signatures,
            out + fixed_section,
            remaining - fixed_section,
            &att_written)
        != 0) {
        return -1;
    }
    size_t sig_offset = fixed_section + att_written;
    if (sig_offset > UINT32_MAX || sig_offset > remaining) {
        return -1;
    }
    if (remaining - sig_offset < LANTERN_SIGNATURE_SIZE) {
        return -1;
    }

    if (write_u32(out, remaining, (uint32_t)fixed_section) != 0) {
        return -1;
    }
    if (write_u32(out + SSZ_BYTE_SIZE_OF_UINT32, remaining - SSZ_BYTE_SIZE_OF_UINT32, (uint32_t)sig_offset) != 0) {
        return -1;
    }
    memcpy(out + sig_offset, signatures->proposer_signature.bytes, LANTERN_SIGNATURE_SIZE);

    size_t total = sig_offset + LANTERN_SIGNATURE_SIZE;
    if (total > remaining) {
        return -1;
    }
    set_written(written, total);
    return 0;
}

static int decode_block_signatures(
    LanternBlockSignatures *signatures,
    const uint8_t *data,
    size_t data_len) {
    if (!signatures || !data) {
        return -1;
    }
    const size_t fixed_section = SSZ_BYTE_SIZE_OF_UINT32 * 2u;
    if (data_len < fixed_section) {
        return -1;
    }
    uint32_t att_offset = 0;
    uint32_t sig_offset = 0;
    if (read_u32(data, data_len, &att_offset) != 0) {
        return -1;
    }
    if (read_u32(data + SSZ_BYTE_SIZE_OF_UINT32, data_len - SSZ_BYTE_SIZE_OF_UINT32, &sig_offset) != 0) {
        return -1;
    }
    if (att_offset < fixed_section || sig_offset < att_offset) {
        return -1;
    }
    if (sig_offset > data_len) {
        return -1;
    }
    size_t att_size = sig_offset - att_offset;
    if (decode_attestation_signatures(&signatures->attestation_signatures, data + att_offset, att_size) != 0) {
        return -1;
    }
    if (data_len - sig_offset != LANTERN_SIGNATURE_SIZE) {
        return -1;
    }
    memcpy(signatures->proposer_signature.bytes, data + sig_offset, LANTERN_SIGNATURE_SIZE);
    return 0;
}

static int encode_root_list(const struct lantern_root_list *list, uint8_t *out, size_t remaining, size_t *written) {
    if (!list || !out) {
        return -1;
    }
    size_t root_bytes = list->length * LANTERN_ROOT_SIZE;
    if (root_bytes > remaining) {
        return -1;
    }
    if (root_bytes > 0 && !list->items) {
        return -1;
    }
    if (root_bytes > 0) {
        memcpy(out, list->items, root_bytes);
    }
    set_written(written, root_bytes);
    return 0;
}

static int decode_root_list(struct lantern_root_list *list, const uint8_t *data, size_t data_len) {
    if (!list) {
        return -1;
    }
    if (data_len == 0) {
        return lantern_root_list_resize(list, 0);
    }
    if (!data || data_len % LANTERN_ROOT_SIZE != 0) {
        return -1;
    }
    size_t count = data_len / LANTERN_ROOT_SIZE;
    if (lantern_root_list_resize(list, count) != 0) {
        return -1;
    }
    memcpy(list->items, data, data_len);
    return 0;
}

static int encode_validators_list(
    const LanternValidator *validators,
    size_t count,
    uint8_t *out,
    size_t remaining,
    size_t *written) {
    if (!out) {
        return -1;
    }
    if (count == 0) {
        set_written(written, 0);
        return 0;
    }
    if (!validators) {
        return -1;
    }
    if (count > SIZE_MAX / LANTERN_VALIDATOR_PUBKEY_SIZE) {
        return -1;
    }
    size_t total = count * LANTERN_VALIDATOR_PUBKEY_SIZE;
    if (total > remaining) {
        return -1;
    }
    for (size_t i = 0; i < count; ++i) {
        memcpy(out + (i * LANTERN_VALIDATOR_PUBKEY_SIZE), validators[i].pubkey, LANTERN_VALIDATOR_PUBKEY_SIZE);
    }
    set_written(written, total);
    return 0;
}

static int decode_validators_list(
    LanternState *state,
    const uint8_t *data,
    size_t data_len) {
    if (!state) {
        return -1;
    }
    size_t count = 0;
    if (state->config.num_validators != 0) {
        count = (size_t)state->config.num_validators;
        size_t expected_size = count * LANTERN_VALIDATOR_PUBKEY_SIZE;
        if (data_len != expected_size) {
            return -1;
        }
    } else {
        if (data_len == 0) {
            state->config.num_validators = 0;
            return lantern_state_set_validator_pubkeys(state, NULL, 0);
        }
        if (data_len % LANTERN_VALIDATOR_PUBKEY_SIZE != 0) {
            return -1;
        }
        count = data_len / LANTERN_VALIDATOR_PUBKEY_SIZE;
    }
    if (count == 0) {
        state->config.num_validators = 0;
        return lantern_state_set_validator_pubkeys(state, NULL, 0);
    }
    if (!data) {
        return -1;
    }
    if (lantern_state_set_validator_pubkeys(state, data, count) != 0) {
        return -1;
    }
    state->config.num_validators = count;
    return 0;
}

static int encode_bitlist(const struct lantern_bitlist *list, uint8_t *out, size_t remaining, size_t *written) {
    if (!list || !out) {
        return -1;
    }
    if (list->bit_length == 0) {
        if (remaining < 1) {
            return -1;
        }
        out[0] = 0x01;
        set_written(written, 1);
        return 0;
    }
    size_t byte_len = (list->bit_length + 7u) / 8u;
    bool needs_extra = (list->bit_length % 8u) == 0;
    size_t total = bitlist_encoded_size(list->bit_length);
    if (total > remaining) {
        return -1;
    }
    if (!list->bytes) {
        return -1;
    }
    if (byte_len > 0) {
        memcpy(out, list->bytes, byte_len);
    }
    uint8_t length_bit_index = (uint8_t)(list->bit_length % 8);
    if (needs_extra) {
        out[total - 1] = (uint8_t)(1u << length_bit_index);
    } else {
        out[byte_len - 1] |= (uint8_t)(1u << length_bit_index);
    }
    set_written(written, total);
    return 0;
}

static int decode_bitlist(struct lantern_bitlist *list, const uint8_t *data, size_t data_len) {
    if (!list) {
        return -1;
    }
    if (data_len == 0) {
        return lantern_bitlist_resize(list, 0);
    }
    if (!data) {
        return -1;
    }
    uint8_t last = data[data_len - 1];
    if (last == 0) {
        return -1;
    }
    int msb = -1;
    for (int i = 7; i >= 0; --i) {
        if ((last >> i) & 1) {
            msb = i;
            break;
        }
    }
    if (msb < 0) {
        return -1;
    }
    size_t bit_length = (data_len - 1) * 8 + (size_t)msb;
    if (lantern_bitlist_resize(list, bit_length) != 0) {
        return -1;
    }
    size_t byte_len = (bit_length + 7) / 8;
    if (byte_len > 0) {
        memcpy(list->bytes, data, byte_len);
        uint8_t remainder = (uint8_t)(bit_length % 8);
        if (remainder != 0) {
            uint8_t mask = (uint8_t)((1u << remainder) - 1u);
            list->bytes[byte_len - 1] &= mask;
        }
    }
    return 0;
}

static int decode_bitlist_with_limit(
    struct lantern_bitlist *list,
    const uint8_t *data,
    size_t data_len,
    size_t max_bits) {
    if (decode_bitlist(list, data, data_len) != 0) {
        return -1;
    }
    if (list->bit_length > max_bits) {
        return -1;
    }
    return 0;
}

static int encode_byte_list(const LanternByteList *list, uint8_t *out, size_t remaining, size_t *written) {
    if (!list || !out) {
        return -1;
    }
    if (list->length > LANTERN_AGG_PROOF_MAX_BYTES) {
        return -1;
    }
    if (list->length > remaining) {
        return -1;
    }
    if (list->length > 0 && !list->data) {
        return -1;
    }
    if (list->length > 0) {
        memcpy(out, list->data, list->length);
    }
    set_written(written, list->length);
    return 0;
}

static int decode_byte_list(LanternByteList *list, const uint8_t *data, size_t data_len) {
    if (!list) {
        return -1;
    }
    if (data_len == 0) {
        return lantern_byte_list_resize(list, 0);
    }
    if (!data) {
        return -1;
    }
    if (data_len > LANTERN_AGG_PROOF_MAX_BYTES) {
        return -1;
    }
    if (lantern_byte_list_resize(list, data_len) != 0) {
        return -1;
    }
    memcpy(list->data, data, data_len);
    return 0;
}

int lantern_ssz_encode_config(const LanternConfig *config, uint8_t *out, size_t out_len, size_t *written) {
    if (!config || !out || out_len < LANTERN_CONFIG_SSZ_SIZE) {
        return -1;
    }
    /* SSZ config only contains genesis_time to match Zeam/Ream's BeamStateConfig.
     * num_validators is derived from the validators list, not stored in config. */
    if (write_u64(out, out_len, config->genesis_time) != 0) {
        return -1;
    }
    set_written(written, SSZ_BYTE_SIZE_OF_UINT64);
    return 0;
}

int lantern_ssz_decode_config(LanternConfig *config, const uint8_t *data, size_t data_len) {
    if (!config || !data || data_len < LANTERN_CONFIG_SSZ_SIZE) {
        return -1;
    }
    /* SSZ config only contains genesis_time to match Zeam/Ream's BeamStateConfig.
     * num_validators is derived from the validators list, not stored in config. */
    if (read_u64(data, data_len, &config->genesis_time) != 0) {
        return -1;
    }
    return 0;
}

int lantern_ssz_encode_checkpoint(const LanternCheckpoint *checkpoint, uint8_t *out, size_t out_len, size_t *written) {
    if (!checkpoint || !out || out_len < LANTERN_CHECKPOINT_SSZ_SIZE) {
        return -1;
    }
    size_t offset = 0;
    if (write_root(out + offset, out_len - offset, &checkpoint->root) != 0) {
        return -1;
    }
    offset += LANTERN_ROOT_SIZE;
    if (write_u64(out + offset, out_len - offset, checkpoint->slot) != 0) {
        return -1;
    }
    offset += SSZ_BYTE_SIZE_OF_UINT64;
    set_written(written, offset);
    return 0;
}

int lantern_ssz_decode_checkpoint(LanternCheckpoint *checkpoint, const uint8_t *data, size_t data_len) {
    if (!checkpoint || !data || data_len != LANTERN_CHECKPOINT_SSZ_SIZE) {
        return -1;
    }
    size_t offset = 0;
    if (read_root(data + offset, data_len - offset, &checkpoint->root) != 0) {
        return -1;
    }
    offset += LANTERN_ROOT_SIZE;
    if (read_u64(data + offset, data_len - offset, &checkpoint->slot) != 0) {
        return -1;
    }
    return 0;
}

static int encode_attestation_data(
    const LanternAttestationData *data,
    uint8_t *out,
    size_t out_len,
    size_t *written) {
    if (!data || !out || out_len < LANTERN_ATTESTATION_DATA_SSZ_SIZE) {
        return -1;
    }
    size_t offset = 0;
    if (write_u64(out + offset, out_len - offset, data->slot) != 0) {
        return -1;
    }
    offset += SSZ_BYTE_SIZE_OF_UINT64;
    size_t tmp_written = 0;
    if (lantern_ssz_encode_checkpoint(&data->head, out + offset, out_len - offset, &tmp_written) != 0) {
        return -1;
    }
    offset += tmp_written;
    if (lantern_ssz_encode_checkpoint(&data->target, out + offset, out_len - offset, &tmp_written) != 0) {
        return -1;
    }
    offset += tmp_written;
    if (lantern_ssz_encode_checkpoint(&data->source, out + offset, out_len - offset, &tmp_written) != 0) {
        return -1;
    }
    offset += tmp_written;
    set_written(written, offset);
    return 0;
}

static int decode_attestation_data(LanternAttestationData *data, const uint8_t *raw, size_t raw_len) {
    if (!data || !raw || raw_len < LANTERN_ATTESTATION_DATA_SSZ_SIZE) {
        return -1;
    }
    size_t offset = 0;
    if (read_u64(raw + offset, raw_len - offset, &data->slot) != 0) {
        return -1;
    }
    offset += SSZ_BYTE_SIZE_OF_UINT64;
    if (lantern_ssz_decode_checkpoint(&data->head, raw + offset, LANTERN_CHECKPOINT_SSZ_SIZE) != 0) {
        return -1;
    }
    offset += LANTERN_CHECKPOINT_SSZ_SIZE;
    if (lantern_ssz_decode_checkpoint(&data->target, raw + offset, LANTERN_CHECKPOINT_SSZ_SIZE) != 0) {
        return -1;
    }
    offset += LANTERN_CHECKPOINT_SSZ_SIZE;
    if (lantern_ssz_decode_checkpoint(&data->source, raw + offset, LANTERN_CHECKPOINT_SSZ_SIZE) != 0) {
        return -1;
    }
    return 0;
}

static int encode_vote_internal(const LanternVote *vote, uint8_t *out, size_t out_len, size_t *written) {
    if (!vote || !out || out_len < LANTERN_VOTE_SSZ_SIZE) {
        return -1;
    }
    size_t offset = 0;
    if (write_u64(out + offset, out_len - offset, vote->validator_id) != 0) {
        return -1;
    }
    offset += SSZ_BYTE_SIZE_OF_UINT64;
    size_t data_written = 0;
    if (encode_attestation_data(&vote->data, out + offset, out_len - offset, &data_written) != 0) {
        return -1;
    }
    offset += data_written;

    set_written(written, offset);
    return 0;
}

static int decode_vote_internal(LanternVote *vote, const uint8_t *data, size_t data_len) {
    if (!vote || !data || data_len != LANTERN_VOTE_SSZ_SIZE) {
        return -1;
    }
    size_t offset = 0;
    if (read_u64(data + offset, data_len - offset, &vote->validator_id) != 0) {
        return -1;
    }
    offset += SSZ_BYTE_SIZE_OF_UINT64;
    if (decode_attestation_data(&vote->data, data + offset, data_len - offset) != 0) {
        return -1;
    }
    return 0;
}

int lantern_ssz_encode_vote(const LanternVote *vote, uint8_t *out, size_t out_len, size_t *written) {
    return encode_vote_internal(vote, out, out_len, written);
}

int lantern_ssz_decode_vote(LanternVote *vote, const uint8_t *data, size_t data_len) {
    return decode_vote_internal(vote, data, data_len);
}

int lantern_ssz_encode_signed_vote(const LanternSignedVote *vote, uint8_t *out, size_t out_len, size_t *written) {
    if (!vote || !out || out_len < LANTERN_SIGNED_VOTE_SSZ_SIZE) {
        return -1;
    }
    size_t offset = 0;
    if (encode_vote_internal(&vote->data, out + offset, out_len - offset, NULL) != 0) {
        return -1;
    }
    offset += LANTERN_VOTE_SSZ_SIZE;
    const size_t fixed_section = LANTERN_VOTE_SSZ_SIZE + SSZ_BYTE_SIZE_OF_UINT32;
    if (fixed_section > UINT32_MAX) {
        return -1;
    }
    if (write_u32(out + offset, out_len - offset, (uint32_t)fixed_section) != 0) {
        return -1;
    }
    offset += SSZ_BYTE_SIZE_OF_UINT32;
    memcpy(out + offset, vote->signature.bytes, LANTERN_SIGNATURE_SIZE);
    offset += LANTERN_SIGNATURE_SIZE;
    set_written(written, offset);
    return 0;
}

int lantern_ssz_decode_signed_vote(LanternSignedVote *vote, const uint8_t *data, size_t data_len) {
    if (!vote || !data || data_len != LANTERN_SIGNED_VOTE_SSZ_SIZE) {
        return -1;
    }
    size_t offset = 0;
    if (decode_vote_internal(&vote->data, data + offset, LANTERN_VOTE_SSZ_SIZE) != 0) {
        return -1;
    }
    offset += LANTERN_VOTE_SSZ_SIZE;
    uint32_t signature_offset = 0;
    if (read_u32(data + offset, data_len - offset, &signature_offset) != 0) {
        return -1;
    }
    const size_t fixed_section = LANTERN_VOTE_SSZ_SIZE + SSZ_BYTE_SIZE_OF_UINT32;
    if (signature_offset != fixed_section) {
        return -1;
    }
    if (signature_offset > data_len) {
        return -1;
    }
    size_t signature_len = data_len - signature_offset;
    if (signature_len != LANTERN_SIGNATURE_SIZE) {
        return -1;
    }
    memcpy(vote->signature.bytes, data + signature_offset, LANTERN_SIGNATURE_SIZE);
    return 0;
}

static int aggregated_attestation_encoded_size(
    const LanternAggregatedAttestation *attestation,
    size_t *out_size) {
    if (!attestation || !out_size) {
        return -1;
    }
    if (attestation->aggregation_bits.bit_length > LANTERN_VALIDATOR_REGISTRY_LIMIT) {
        return -1;
    }
    size_t bits_size = bitlist_encoded_size(attestation->aggregation_bits.bit_length);
    size_t fixed_section = SSZ_BYTE_SIZE_OF_UINT32 + LANTERN_ATTESTATION_DATA_SSZ_SIZE;
    if (fixed_section > SIZE_MAX - bits_size) {
        return -1;
    }
    *out_size = fixed_section + bits_size;
    return 0;
}

static int encode_aggregated_attestation(
    const LanternAggregatedAttestation *attestation,
    uint8_t *out,
    size_t remaining,
    size_t *written) {
    if (!attestation || !out) {
        return -1;
    }
    if (attestation->aggregation_bits.bit_length > LANTERN_VALIDATOR_REGISTRY_LIMIT) {
        return -1;
    }
    size_t fixed_section = SSZ_BYTE_SIZE_OF_UINT32 + LANTERN_ATTESTATION_DATA_SSZ_SIZE;
    if (fixed_section > UINT32_MAX) {
        return -1;
    }
    if (remaining < fixed_section) {
        return -1;
    }
    uint32_t bits_offset = (uint32_t)fixed_section;
    if (write_u32(out, remaining, bits_offset) != 0) {
        return -1;
    }
    size_t data_written = 0;
    if (encode_attestation_data(
            &attestation->data,
            out + SSZ_BYTE_SIZE_OF_UINT32,
            remaining - SSZ_BYTE_SIZE_OF_UINT32,
            &data_written)
        != 0) {
        return -1;
    }
    if (data_written != LANTERN_ATTESTATION_DATA_SSZ_SIZE) {
        return -1;
    }
    size_t bits_written = 0;
    if (encode_bitlist(
            &attestation->aggregation_bits,
            out + bits_offset,
            remaining - bits_offset,
            &bits_written)
        != 0) {
        return -1;
    }
    size_t total = bits_offset + bits_written;
    if (total > remaining) {
        return -1;
    }
    set_written(written, total);
    return 0;
}

static int decode_aggregated_attestation(
    LanternAggregatedAttestation *attestation,
    const uint8_t *data,
    size_t data_len) {
    if (!attestation || !data) {
        return -1;
    }
    const size_t fixed_section = SSZ_BYTE_SIZE_OF_UINT32 + LANTERN_ATTESTATION_DATA_SSZ_SIZE;
    if (data_len < fixed_section) {
        return -1;
    }
    uint32_t bits_offset = 0;
    if (read_u32(data, data_len, &bits_offset) != 0) {
        return -1;
    }
    if (bits_offset < fixed_section || bits_offset > data_len) {
        return -1;
    }
    if (decode_attestation_data(
            &attestation->data,
            data + SSZ_BYTE_SIZE_OF_UINT32,
            LANTERN_ATTESTATION_DATA_SSZ_SIZE)
        != 0) {
        return -1;
    }
    size_t bits_size = data_len - bits_offset;
    if (decode_bitlist_with_limit(
            &attestation->aggregation_bits,
            data + bits_offset,
            bits_size,
            LANTERN_VALIDATOR_REGISTRY_LIMIT)
        != 0) {
        return -1;
    }
    return 0;
}

static int encode_aggregated_attestations(
    const LanternAggregatedAttestations *attestations,
    uint8_t *out,
    size_t remaining,
    size_t *written) {
    if (!attestations || !out) {
        return -1;
    }
    if (attestations->length > LANTERN_MAX_ATTESTATIONS) {
        return -1;
    }
    if (attestations->length == 0) {
        set_written(written, 0);
        return 0;
    }
    if (!attestations->data) {
        return -1;
    }
    size_t offset_table = attestations->length * SSZ_BYTE_SIZE_OF_UINT32;
    if (offset_table > remaining) {
        return -1;
    }
    size_t cursor = offset_table;
    for (size_t i = 0; i < attestations->length; ++i) {
        size_t element_size = 0;
        if (aggregated_attestation_encoded_size(&attestations->data[i], &element_size) != 0) {
            return -1;
        }
        if (cursor > UINT32_MAX) {
            return -1;
        }
        if (write_u32(out + (i * SSZ_BYTE_SIZE_OF_UINT32), remaining - (i * SSZ_BYTE_SIZE_OF_UINT32), (uint32_t)cursor) != 0) {
            return -1;
        }
        if (cursor > remaining || element_size > remaining - cursor) {
            return -1;
        }
        if (encode_aggregated_attestation(
                &attestations->data[i],
                out + cursor,
                remaining - cursor,
                NULL)
            != 0) {
            return -1;
        }
        cursor += element_size;
    }
    set_written(written, cursor);
    return 0;
}

static int decode_aggregated_attestations(
    LanternAggregatedAttestations *attestations,
    const uint8_t *data,
    size_t data_len) {
    if (!attestations) {
        return -1;
    }
    if (data_len == 0) {
        return lantern_aggregated_attestations_resize(attestations, 0);
    }
    if (!data || data_len < SSZ_BYTE_SIZE_OF_UINT32) {
        return -1;
    }
    uint32_t first_offset = 0;
    if (read_u32(data, data_len, &first_offset) != 0) {
        return -1;
    }
    if (first_offset < SSZ_BYTE_SIZE_OF_UINT32 || first_offset > data_len || (first_offset % SSZ_BYTE_SIZE_OF_UINT32) != 0) {
        return -1;
    }
    size_t count = first_offset / SSZ_BYTE_SIZE_OF_UINT32;
    if (count > LANTERN_MAX_ATTESTATIONS) {
        return -1;
    }
    if (count == 0) {
        return lantern_aggregated_attestations_resize(attestations, 0);
    }
    if (lantern_aggregated_attestations_resize(attestations, count) != 0) {
        return -1;
    }
    size_t offset_table = count * SSZ_BYTE_SIZE_OF_UINT32;
    if (offset_table != first_offset || offset_table > data_len) {
        return -1;
    }
    size_t *offsets = calloc(count, sizeof(*offsets));
    if (!offsets) {
        return -1;
    }
    for (size_t i = 0; i < count; ++i) {
        uint32_t value = 0;
        if (read_u32(data + (i * SSZ_BYTE_SIZE_OF_UINT32), data_len - (i * SSZ_BYTE_SIZE_OF_UINT32), &value) != 0) {
            free(offsets);
            return -1;
        }
        offsets[i] = value;
    }
    for (size_t i = 0; i < count; ++i) {
        if (offsets[i] < offset_table || offsets[i] > data_len) {
            free(offsets);
            return -1;
        }
        if (i > 0 && offsets[i] < offsets[i - 1]) {
            free(offsets);
            return -1;
        }
    }
    for (size_t i = 0; i < count; ++i) {
        size_t chunk_end = (i + 1 < count) ? offsets[i + 1] : data_len;
        if (chunk_end < offsets[i] || chunk_end > data_len) {
            free(offsets);
            return -1;
        }
        size_t chunk_size = chunk_end - offsets[i];
        if (decode_aggregated_attestation(&attestations->data[i], data + offsets[i], chunk_size) != 0) {
            free(offsets);
            return -1;
        }
    }
    free(offsets);
    return 0;
}

static int aggregated_signature_proof_encoded_size(
    const LanternAggregatedSignatureProof *proof,
    size_t *out_size) {
    if (!proof || !out_size) {
        return -1;
    }
    if (proof->participants.bit_length > LANTERN_VALIDATOR_REGISTRY_LIMIT) {
        return -1;
    }
    if (proof->proof_data.length > LANTERN_AGG_PROOF_MAX_BYTES) {
        return -1;
    }
    size_t participants_size = bitlist_encoded_size(proof->participants.bit_length);
    size_t fixed_section = SSZ_BYTE_SIZE_OF_UINT32 * 2u;
    if (fixed_section > SIZE_MAX - participants_size) {
        return -1;
    }
    if (fixed_section + participants_size > SIZE_MAX - proof->proof_data.length) {
        return -1;
    }
    *out_size = fixed_section + participants_size + proof->proof_data.length;
    return 0;
}

static int encode_aggregated_signature_proof(
    const LanternAggregatedSignatureProof *proof,
    uint8_t *out,
    size_t remaining,
    size_t *written) {
    if (!proof || !out) {
        return -1;
    }
    if (proof->participants.bit_length > LANTERN_VALIDATOR_REGISTRY_LIMIT) {
        return -1;
    }
    if (proof->proof_data.length > LANTERN_AGG_PROOF_MAX_BYTES) {
        return -1;
    }
    size_t participants_size = bitlist_encoded_size(proof->participants.bit_length);
    size_t fixed_section = SSZ_BYTE_SIZE_OF_UINT32 * 2u;
    if (fixed_section > UINT32_MAX) {
        return -1;
    }
    if (fixed_section > remaining) {
        return -1;
    }
    size_t proof_offset = fixed_section + participants_size;
    if (proof_offset > UINT32_MAX) {
        return -1;
    }
    if (proof_offset > remaining) {
        return -1;
    }
    uint32_t participants_offset_u32 = (uint32_t)fixed_section;
    uint32_t proof_offset_u32 = (uint32_t)proof_offset;
    if (write_u32(out, remaining, participants_offset_u32) != 0) {
        return -1;
    }
    if (write_u32(out + SSZ_BYTE_SIZE_OF_UINT32, remaining - SSZ_BYTE_SIZE_OF_UINT32, proof_offset_u32) != 0) {
        return -1;
    }
    size_t participants_written = 0;
    if (encode_bitlist(
            &proof->participants,
            out + participants_offset_u32,
            remaining - participants_offset_u32,
            &participants_written)
        != 0) {
        return -1;
    }
    if (participants_written != participants_size) {
        return -1;
    }
    size_t proof_written = 0;
    if (encode_byte_list(
            &proof->proof_data,
            out + proof_offset_u32,
            remaining - proof_offset_u32,
            &proof_written)
        != 0) {
        return -1;
    }
    if (proof_written != proof->proof_data.length) {
        return -1;
    }
    size_t total = proof_offset + proof_written;
    if (total > remaining) {
        return -1;
    }
    set_written(written, total);
    return 0;
}

static int decode_aggregated_signature_proof(
    LanternAggregatedSignatureProof *proof,
    const uint8_t *data,
    size_t data_len) {
    if (!proof || !data) {
        return -1;
    }
    const size_t fixed_section = SSZ_BYTE_SIZE_OF_UINT32 * 2u;
    if (data_len < fixed_section) {
        return -1;
    }
    uint32_t participants_offset = 0;
    uint32_t proof_offset = 0;
    if (read_u32(data, data_len, &participants_offset) != 0) {
        return -1;
    }
    if (read_u32(data + SSZ_BYTE_SIZE_OF_UINT32, data_len - SSZ_BYTE_SIZE_OF_UINT32, &proof_offset) != 0) {
        return -1;
    }
    if (participants_offset < fixed_section || proof_offset < participants_offset) {
        return -1;
    }
    if (proof_offset > data_len) {
        return -1;
    }
    size_t participants_size = proof_offset - participants_offset;
    size_t proof_size = data_len - proof_offset;
    if (decode_bitlist_with_limit(
            &proof->participants,
            data + participants_offset,
            participants_size,
            LANTERN_VALIDATOR_REGISTRY_LIMIT)
        != 0) {
        return -1;
    }
    if (decode_byte_list(&proof->proof_data, data + proof_offset, proof_size) != 0) {
        return -1;
    }
    return 0;
}

static int encode_attestation_signatures(
    const LanternAttestationSignatures *signatures,
    uint8_t *out,
    size_t remaining,
    size_t *written) {
    if (!signatures || !out) {
        return -1;
    }
    if (signatures->length > LANTERN_MAX_BLOCK_SIGNATURES) {
        return -1;
    }
    if (signatures->length == 0) {
        set_written(written, 0);
        return 0;
    }
    if (!signatures->data) {
        return -1;
    }
    size_t offset_table = signatures->length * SSZ_BYTE_SIZE_OF_UINT32;
    if (offset_table > remaining) {
        return -1;
    }
    size_t cursor = offset_table;
    for (size_t i = 0; i < signatures->length; ++i) {
        size_t element_size = 0;
        if (aggregated_signature_proof_encoded_size(&signatures->data[i], &element_size) != 0) {
            return -1;
        }
        if (cursor > UINT32_MAX) {
            return -1;
        }
        if (write_u32(out + (i * SSZ_BYTE_SIZE_OF_UINT32), remaining - (i * SSZ_BYTE_SIZE_OF_UINT32), (uint32_t)cursor) != 0) {
            return -1;
        }
        if (cursor > remaining || element_size > remaining - cursor) {
            return -1;
        }
        if (encode_aggregated_signature_proof(&signatures->data[i], out + cursor, remaining - cursor, NULL) != 0) {
            return -1;
        }
        cursor += element_size;
    }
    set_written(written, cursor);
    return 0;
}

static int decode_attestation_signatures(
    LanternAttestationSignatures *signatures,
    const uint8_t *data,
    size_t data_len) {
    if (!signatures) {
        return -1;
    }
    if (data_len == 0) {
        return lantern_attestation_signatures_resize(signatures, 0);
    }
    if (!data || data_len < SSZ_BYTE_SIZE_OF_UINT32) {
        return -1;
    }
    uint32_t first_offset = 0;
    if (read_u32(data, data_len, &first_offset) != 0) {
        return -1;
    }
    if (first_offset < SSZ_BYTE_SIZE_OF_UINT32 || first_offset > data_len || (first_offset % SSZ_BYTE_SIZE_OF_UINT32) != 0) {
        return -1;
    }
    size_t count = first_offset / SSZ_BYTE_SIZE_OF_UINT32;
    if (count > LANTERN_MAX_BLOCK_SIGNATURES) {
        return -1;
    }
    if (count == 0) {
        return lantern_attestation_signatures_resize(signatures, 0);
    }
    if (lantern_attestation_signatures_resize(signatures, count) != 0) {
        return -1;
    }
    size_t offset_table = count * SSZ_BYTE_SIZE_OF_UINT32;
    if (offset_table != first_offset || offset_table > data_len) {
        return -1;
    }
    size_t *offsets = calloc(count, sizeof(*offsets));
    if (!offsets) {
        return -1;
    }
    for (size_t i = 0; i < count; ++i) {
        uint32_t value = 0;
        if (read_u32(data + (i * SSZ_BYTE_SIZE_OF_UINT32), data_len - (i * SSZ_BYTE_SIZE_OF_UINT32), &value) != 0) {
            free(offsets);
            return -1;
        }
        offsets[i] = value;
    }
    for (size_t i = 0; i < count; ++i) {
        if (offsets[i] < offset_table || offsets[i] > data_len) {
            free(offsets);
            return -1;
        }
        if (i > 0 && offsets[i] < offsets[i - 1]) {
            free(offsets);
            return -1;
        }
    }
    for (size_t i = 0; i < count; ++i) {
        size_t chunk_end = (i + 1 < count) ? offsets[i + 1] : data_len;
        if (chunk_end < offsets[i] || chunk_end > data_len) {
            free(offsets);
            return -1;
        }
        size_t chunk_size = chunk_end - offsets[i];
        if (decode_aggregated_signature_proof(&signatures->data[i], data + offsets[i], chunk_size) != 0) {
            free(offsets);
            return -1;
        }
    }
    free(offsets);
    return 0;
}

int lantern_ssz_encode_block_header(const LanternBlockHeader *header, uint8_t *out, size_t out_len, size_t *written) {
    if (!header || !out || out_len < LANTERN_BLOCK_HEADER_SSZ_SIZE) {
        return -1;
    }
    size_t offset = 0;
    if (write_u64(out + offset, out_len - offset, header->slot) != 0) {
        return -1;
    }
    offset += SSZ_BYTE_SIZE_OF_UINT64;
    if (write_u64(out + offset, out_len - offset, header->proposer_index) != 0) {
        return -1;
    }
    offset += SSZ_BYTE_SIZE_OF_UINT64;
    if (write_root(out + offset, out_len - offset, &header->parent_root) != 0) {
        return -1;
    }
    offset += LANTERN_ROOT_SIZE;
    if (write_root(out + offset, out_len - offset, &header->state_root) != 0) {
        return -1;
    }
    offset += LANTERN_ROOT_SIZE;
    if (write_root(out + offset, out_len - offset, &header->body_root) != 0) {
        return -1;
    }
    offset += LANTERN_ROOT_SIZE;
    set_written(written, offset);
    return 0;
}

int lantern_ssz_decode_block_header(LanternBlockHeader *header, const uint8_t *data, size_t data_len) {
    if (!header || !data || data_len != LANTERN_BLOCK_HEADER_SSZ_SIZE) {
        return -1;
    }
    size_t offset = 0;
    if (read_u64(data + offset, data_len - offset, &header->slot) != 0) {
        return -1;
    }
    offset += SSZ_BYTE_SIZE_OF_UINT64;
    if (read_u64(data + offset, data_len - offset, &header->proposer_index) != 0) {
        return -1;
    }
    offset += SSZ_BYTE_SIZE_OF_UINT64;
    if (read_root(data + offset, data_len - offset, &header->parent_root) != 0) {
        return -1;
    }
    offset += LANTERN_ROOT_SIZE;
    if (read_root(data + offset, data_len - offset, &header->state_root) != 0) {
        return -1;
    }
    offset += LANTERN_ROOT_SIZE;
    if (read_root(data + offset, data_len - offset, &header->body_root) != 0) {
        return -1;
    }
    return 0;
}

int lantern_ssz_encode_block_body(const LanternBlockBody *body, uint8_t *out, size_t out_len, size_t *written) {
    if (!body || !out) {
        return -1;
    }

    uint32_t att_offset = SSZ_BYTE_SIZE_OF_UINT32;
    if (out_len < att_offset) {
        return -1;
    }
    if (write_u32(out, out_len, att_offset) != 0) {
        return -1;
    }
    size_t att_written = 0;
    if (encode_aggregated_attestations(
            &body->attestations,
            out + att_offset,
            out_len - att_offset,
            &att_written)
        != 0) {
        return -1;
    }
    size_t total = att_offset + att_written;
    if (total > out_len) {
        return -1;
    }
    set_written(written, total);
    return 0;
}

int lantern_ssz_decode_block_body(LanternBlockBody *body, const uint8_t *data, size_t data_len) {
    if (!body || !data || data_len < SSZ_BYTE_SIZE_OF_UINT32) {
        return -1;
    }

    uint32_t att_offset = 0;
    if (read_u32(data, data_len, &att_offset) != 0) {
        return -1;
    }
    if (att_offset > data_len || att_offset < SSZ_BYTE_SIZE_OF_UINT32) {
        return -1;
    }

    size_t att_size = data_len - att_offset;
    if (decode_aggregated_attestations(&body->attestations, data + att_offset, att_size) != 0) {
        return -1;
    }
    return 0;
}

int lantern_ssz_encode_block(const LanternBlock *block, uint8_t *out, size_t out_len, size_t *written) {
    if (!block || !out) {
        return -1;
    }

    const size_t fixed_fields = (SSZ_BYTE_SIZE_OF_UINT64 * 2) + (LANTERN_ROOT_SIZE * 2);
    const size_t fixed_section = fixed_fields + SSZ_BYTE_SIZE_OF_UINT32; /* single variable field offset */
    if (fixed_section > UINT32_MAX) {
        return -1;
    }
    if (out_len < fixed_section) {
        return -1;
    }

    size_t offset = 0;
    if (write_u64(out + offset, out_len - offset, block->slot) != 0) {
        return -1;
    }
    offset += SSZ_BYTE_SIZE_OF_UINT64;
    if (write_u64(out + offset, out_len - offset, block->proposer_index) != 0) {
        return -1;
    }
    offset += SSZ_BYTE_SIZE_OF_UINT64;
    if (write_root(out + offset, out_len - offset, &block->parent_root) != 0) {
        return -1;
    }
    offset += LANTERN_ROOT_SIZE;
    if (write_root(out + offset, out_len - offset, &block->state_root) != 0) {
        return -1;
    }
    offset += LANTERN_ROOT_SIZE;

    uint32_t body_offset = (uint32_t)fixed_section;
    if (write_u32(out + offset, out_len - offset, body_offset) != 0) {
        return -1;
    }
    offset += SSZ_BYTE_SIZE_OF_UINT32;

    size_t body_written = 0;
    if (lantern_ssz_encode_block_body(&block->body, out + body_offset, out_len - body_offset, &body_written) != 0) {
        return -1;
    }

    size_t total = body_offset + body_written;
    if (total > UINT32_MAX) {
        return -1;
    }
    set_written(written, total);
    return 0;
}

int lantern_ssz_decode_block(LanternBlock *block, const uint8_t *data, size_t data_len) {
    if (!block || !data) {
        return -1;
    }

    const size_t fixed_fields = (SSZ_BYTE_SIZE_OF_UINT64 * 2) + (LANTERN_ROOT_SIZE * 2);
    const size_t min_size = fixed_fields + SSZ_BYTE_SIZE_OF_UINT32;
    if (data_len < min_size) {
        return -1;
    }

    size_t offset = 0;
    if (read_u64(data + offset, data_len - offset, &block->slot) != 0) {
        return -1;
    }
    offset += SSZ_BYTE_SIZE_OF_UINT64;
    if (read_u64(data + offset, data_len - offset, &block->proposer_index) != 0) {
        return -1;
    }
    offset += SSZ_BYTE_SIZE_OF_UINT64;
    if (read_root(data + offset, data_len - offset, &block->parent_root) != 0) {
        return -1;
    }
    offset += LANTERN_ROOT_SIZE;
    if (read_root(data + offset, data_len - offset, &block->state_root) != 0) {
        return -1;
    }
    offset += LANTERN_ROOT_SIZE;

    uint32_t body_offset = 0;
    if (read_u32(data + offset, data_len - offset, &body_offset) != 0) {
        return -1;
    }
    offset += SSZ_BYTE_SIZE_OF_UINT32;

    if (body_offset > data_len || body_offset < min_size) {
        return -1;
    }

    size_t body_len = data_len - body_offset;
    if (lantern_ssz_decode_block_body(&block->body, data + body_offset, body_len) != 0) {
        return -1;
    }
    return 0;
}

int lantern_ssz_encode_block_with_attestation(
    const LanternBlockWithAttestation *block,
    uint8_t *out,
    size_t out_len,
    size_t *written) {
    if (!block || !out) {
        return -1;
    }

    const size_t fixed_section = SSZ_BYTE_SIZE_OF_UINT32 + LANTERN_VOTE_SSZ_SIZE;
    if (fixed_section > UINT32_MAX) {
        return -1;
    }
    if (out_len < fixed_section) {
        return -1;
    }

    uint32_t block_offset = (uint32_t)fixed_section;
    if (write_u32(out, out_len, block_offset) != 0) {
        return -1;
    }

    size_t proposer_written = 0;
    if (lantern_ssz_encode_vote(
            &block->proposer_attestation,
            out + SSZ_BYTE_SIZE_OF_UINT32,
            out_len - SSZ_BYTE_SIZE_OF_UINT32,
            &proposer_written)
        != 0) {
        return -1;
    }
    if (proposer_written != LANTERN_VOTE_SSZ_SIZE) {
        return -1;
    }

    size_t block_written = 0;
    if (lantern_ssz_encode_block(&block->block, out + block_offset, out_len - block_offset, &block_written) != 0) {
        return -1;
    }

    size_t total = block_offset + block_written;
    if (total > UINT32_MAX) {
        return -1;
    }
    set_written(written, total);
    return 0;
}

int lantern_ssz_decode_block_with_attestation(
    LanternBlockWithAttestation *block,
    const uint8_t *data,
    size_t data_len) {
    if (!block || !data) {
        return -1;
    }

    const size_t min_size = SSZ_BYTE_SIZE_OF_UINT32 + LANTERN_VOTE_SSZ_SIZE;
    if (data_len < min_size) {
        return -1;
    }

    uint32_t block_offset = 0;
    if (read_u32(data, data_len, &block_offset) != 0) {
        return -1;
    }
    if (block_offset < min_size || block_offset > data_len) {
        return -1;
    }

    if (lantern_ssz_decode_vote(
            &block->proposer_attestation,
            data + SSZ_BYTE_SIZE_OF_UINT32,
            LANTERN_VOTE_SSZ_SIZE)
        != 0) {
        return -1;
    }

    size_t block_len = data_len - block_offset;
    if (block_len == 0) {
        return -1;
    }
    if (lantern_ssz_decode_block(&block->block, data + block_offset, block_len) != 0) {
        return -1;
    }
    return 0;
}

int lantern_ssz_encode_signed_block_with_attestation(
    const LanternSignedBlockWithAttestation *block,
    uint8_t *out,
    size_t out_len,
    size_t *written) {
    if (!block || !out) {
        return -1;
    }

    const size_t offset_section = SSZ_BYTE_SIZE_OF_UINT32 * 2u;
    if (offset_section > UINT32_MAX) {
        return -1;
    }
    if (out_len < offset_section) {
        return -1;
    }

    size_t payload_offset = offset_section;
    size_t message_written = 0;
    if (lantern_ssz_encode_block_with_attestation(
            &block->message,
            out + payload_offset,
            out_len - payload_offset,
            &message_written)
        != 0) {
        return -1;
    }

    size_t message_region_end = payload_offset + message_written;
    if (message_region_end < payload_offset || message_region_end > out_len) {
        return -1;
    }

    size_t signatures_written = 0;
    if (encode_block_signatures(
            &block->signatures,
            out + message_region_end,
            out_len - message_region_end,
            &signatures_written)
        != 0) {
        return -1;
    }

    size_t total = message_region_end + signatures_written;
    if (total < message_region_end || total > UINT32_MAX) {
        return -1;
    }

    if (payload_offset > UINT32_MAX || message_region_end > UINT32_MAX) {
        return -1;
    }
    uint32_t message_offset = (uint32_t)payload_offset;
    uint32_t signatures_offset = (uint32_t)message_region_end;

    if (write_u32(out, out_len, message_offset) != 0) {
        return -1;
    }
    if (write_u32(out + SSZ_BYTE_SIZE_OF_UINT32, out_len - SSZ_BYTE_SIZE_OF_UINT32, signatures_offset) != 0) {
        return -1;
    }

    set_written(written, total);
    return 0;
}

int lantern_ssz_decode_signed_block_with_attestation(
    LanternSignedBlockWithAttestation *block,
    const uint8_t *data,
    size_t data_len) {
    if (!block || !data) {
        return -1;
    }

    const size_t offset_section = SSZ_BYTE_SIZE_OF_UINT32 * 2u;
    if (data_len < offset_section) {
        return -1;
    }

    uint32_t message_offset = 0;
    if (read_u32(data, data_len, &message_offset) != 0) {
        return -1;
    }
    uint32_t signatures_offset = 0;
    if (read_u32(data + SSZ_BYTE_SIZE_OF_UINT32, data_len - SSZ_BYTE_SIZE_OF_UINT32, &signatures_offset) != 0) {
        return -1;
    }

    if (message_offset < offset_section || signatures_offset < offset_section) {
        return -1;
    }
    if (message_offset > data_len || signatures_offset > data_len) {
        return -1;
    }
    if (signatures_offset < message_offset) {
        return -1;
    }

    size_t message_len = signatures_offset - message_offset;
    if (message_len == 0 || message_len > data_len - message_offset) {
        return -1;
    }

    if (lantern_ssz_decode_block_with_attestation(
            &block->message,
            data + message_offset,
            message_len)
        != 0) {
        return -1;
    }

    size_t signatures_len = data_len - signatures_offset;
    if (decode_block_signatures(&block->signatures, data + signatures_offset, signatures_len) != 0) {
        return -1;
    }
    return 0;
}

int lantern_ssz_encode_signed_block(const LanternSignedBlock *block, uint8_t *out, size_t out_len, size_t *written) {
    return lantern_ssz_encode_signed_block_with_attestation(block, out, out_len, written);
}

int lantern_ssz_decode_signed_block(LanternSignedBlock *block, const uint8_t *data, size_t data_len) {
    return lantern_ssz_decode_signed_block_with_attestation(block, data, data_len);
}

int lantern_ssz_encode_state(const LanternState *state, uint8_t *out, size_t out_len, size_t *written) {
    if (!state || !out) {
        return -1;
    }

    if (state->config.num_validators != (uint64_t)state->validator_count) {
        return -1;
    }
    const size_t var_field_count = 5;
    size_t offset = 0;
    size_t tmp = 0;

    if (lantern_ssz_encode_config(&state->config, out + offset, out_len - offset, &tmp) != 0) {
        return -1;
    }
    offset += tmp;

    if (write_u64(out + offset, out_len - offset, state->slot) != 0) {
        return -1;
    }
    offset += SSZ_BYTE_SIZE_OF_UINT64;

    if (lantern_ssz_encode_block_header(&state->latest_block_header, out + offset, out_len - offset, &tmp) != 0) {
        return -1;
    }
    offset += tmp;

    if (lantern_ssz_encode_checkpoint(&state->latest_justified, out + offset, out_len - offset, &tmp) != 0) {
        return -1;
    }
    offset += tmp;

    if (lantern_ssz_encode_checkpoint(&state->latest_finalized, out + offset, out_len - offset, &tmp) != 0) {
        return -1;
    }
    offset += tmp;

    if (out_len < offset + (var_field_count * SSZ_BYTE_SIZE_OF_UINT32)) {
        return -1;
    }

    size_t variable_offset = offset + (var_field_count * SSZ_BYTE_SIZE_OF_UINT32);
    if (variable_offset > UINT32_MAX) {
        return -1;
    }

    // Historical block hashes
    if (write_u32(out + offset, out_len - offset, (uint32_t)variable_offset) != 0) {
        return -1;
    }
    offset += SSZ_BYTE_SIZE_OF_UINT32;
    if (encode_root_list(&state->historical_block_hashes, out + variable_offset, out_len - variable_offset, &tmp) != 0) {
        return -1;
    }
    variable_offset += tmp;
    if (variable_offset > UINT32_MAX) {
        return -1;
    }

    // Justified slots bitlist
    if (write_u32(out + offset, out_len - offset, (uint32_t)variable_offset) != 0) {
        return -1;
    }
    offset += SSZ_BYTE_SIZE_OF_UINT32;
    if (encode_bitlist(&state->justified_slots, out + variable_offset, out_len - variable_offset, &tmp) != 0) {
        return -1;
    }
    variable_offset += tmp;
    if (variable_offset > UINT32_MAX) {
        return -1;
    }

    // Validators list
    if (write_u32(out + offset, out_len - offset, (uint32_t)variable_offset) != 0) {
        return -1;
    }
    offset += SSZ_BYTE_SIZE_OF_UINT32;
    if (state->validator_count > 0 && state->validator_count > SIZE_MAX / LANTERN_VALIDATOR_PUBKEY_SIZE) {
        return -1;
    }
    size_t validator_bytes = state->validator_count * LANTERN_VALIDATOR_PUBKEY_SIZE;
    if (validator_bytes > out_len - variable_offset) {
        return -1;
    }
    if (encode_validators_list(state->validators, state->validator_count, out + variable_offset, out_len - variable_offset, &tmp)
        != 0) {
        return -1;
    }
    variable_offset += tmp;
    if (variable_offset > UINT32_MAX) {
        return -1;
    }

    // Justification roots
    if (write_u32(out + offset, out_len - offset, (uint32_t)variable_offset) != 0) {
        return -1;
    }
    offset += SSZ_BYTE_SIZE_OF_UINT32;
    if (encode_root_list(&state->justification_roots, out + variable_offset, out_len - variable_offset, &tmp) != 0) {
        return -1;
    }
    variable_offset += tmp;
    if (variable_offset > UINT32_MAX) {
        return -1;
    }

    // Justification validators bitlist
    if (write_u32(out + offset, out_len - offset, (uint32_t)variable_offset) != 0) {
        return -1;
    }
    offset += SSZ_BYTE_SIZE_OF_UINT32;
    if (encode_bitlist(&state->justification_validators, out + variable_offset, out_len - variable_offset, &tmp) != 0) {
        return -1;
    }
    variable_offset += tmp;

    set_written(written, variable_offset);
    return 0;
}

int lantern_ssz_decode_state(LanternState *state, const uint8_t *data, size_t data_len) {
    if (!state || !data) {
        return -1;
    }

    const size_t var_field_count = 5;
    size_t offset = 0;
    const size_t offsets_size = var_field_count * SSZ_BYTE_SIZE_OF_UINT32;
    const size_t min_full_size = LANTERN_CONFIG_SSZ_SIZE + SSZ_BYTE_SIZE_OF_UINT64 + LANTERN_BLOCK_HEADER_SSZ_SIZE
        + (2 * LANTERN_CHECKPOINT_SSZ_SIZE) + offsets_size;
    if (data_len < min_full_size) {
        return -1;
    }
    if (lantern_ssz_decode_config(&state->config, data + offset, LANTERN_CONFIG_SSZ_SIZE) != 0) {
        return -1;
    }
    offset += LANTERN_CONFIG_SSZ_SIZE;
    if (read_u64(data + offset, data_len - offset, &state->slot) != 0) {
        return -1;
    }
    offset += SSZ_BYTE_SIZE_OF_UINT64;

    if (data_len - offset < LANTERN_BLOCK_HEADER_SSZ_SIZE) {
        return -1;
    }
    if (lantern_ssz_decode_block_header(&state->latest_block_header, data + offset, LANTERN_BLOCK_HEADER_SSZ_SIZE) != 0) {
        return -1;
    }
    offset += LANTERN_BLOCK_HEADER_SSZ_SIZE;
    if (data_len - offset < LANTERN_CHECKPOINT_SSZ_SIZE) {
        return -1;
    }
    if (lantern_ssz_decode_checkpoint(&state->latest_justified, data + offset, LANTERN_CHECKPOINT_SSZ_SIZE) != 0) {
        return -1;
    }
    offset += LANTERN_CHECKPOINT_SSZ_SIZE;
    if (data_len - offset < LANTERN_CHECKPOINT_SSZ_SIZE) {
        return -1;
    }
    if (lantern_ssz_decode_checkpoint(&state->latest_finalized, data + offset, LANTERN_CHECKPOINT_SSZ_SIZE) != 0) {
        return -1;
    }
    offset += LANTERN_CHECKPOINT_SSZ_SIZE;
    if (data_len - offset < offsets_size) {
        return -1;
    }

    size_t offsets_start = offset;
    size_t offsets[var_field_count];
    size_t read_pos = offsets_start;
    for (size_t i = 0; i < var_field_count; ++i) {
        uint32_t value = 0;
        if (read_u32(data + read_pos, data_len - read_pos, &value) != 0) {
            return -1;
        }
        offsets[i] = value;
        read_pos += SSZ_BYTE_SIZE_OF_UINT32;
    }
    size_t table_end = offsets_start + offsets_size;
    for (size_t i = 0; i < var_field_count; ++i) {
        if (offsets[i] < table_end || offsets[i] > data_len) {
            return -1;
        }
        if (i > 0 && offsets[i] < offsets[i - 1]) {
            return -1;
        }
    }
    offset = table_end;
    size_t payload_start = offsets[0];
    if (payload_start < offset || payload_start > data_len) {
        return -1;
    }

    for (size_t i = 0; i < var_field_count; ++i) {
        if (offsets[i] < offset || offsets[i] > data_len) {
            return -1;
        }
        if (i > 0 && offsets[i] < offsets[i - 1]) {
            return -1;
        }
    }

    size_t chunk_sizes[var_field_count];
    for (size_t i = 0; i < var_field_count; ++i) {
        size_t chunk_end = (i + 1 < var_field_count) ? offsets[i + 1] : data_len;
        if (chunk_end < offsets[i] || chunk_end > data_len) {
            return -1;
        }
        chunk_sizes[i] = chunk_end - offsets[i];
    }

    if (decode_root_list(&state->historical_block_hashes, data + offsets[0], chunk_sizes[0]) != 0) {
        return -1;
    }
    if (decode_bitlist(&state->justified_slots, data + offsets[1], chunk_sizes[1]) != 0) {
        return -1;
    }
    if (decode_validators_list(state, data + offsets[2], chunk_sizes[2]) != 0) {
        return -1;
    }
    if (decode_root_list(&state->justification_roots, data + offsets[3], chunk_sizes[3]) != 0) {
        return -1;
    }
    if (decode_bitlist(&state->justification_validators, data + offsets[4], chunk_sizes[4]) != 0) {
        return -1;
    }

    state->config.num_validators = (uint64_t)state->validator_count;
    return 0;
}
