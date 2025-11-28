#include "lantern/consensus/ssz.h"

#include <inttypes.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ssz_constants.h"
#include "ssz_deserialize.h"
#include "ssz_serialize.h"

#include "lantern/consensus/state.h"
#include "lantern/support/log.h"

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

static int encode_attestations(const LanternAttestations *attestations, uint8_t *out, size_t remaining, size_t *written) {
    if (!attestations) {
        return -1;
    }
    if (attestations->length > LANTERN_MAX_ATTESTATIONS) {
        return -1;
    }
    if (attestations->length > 0 && !attestations->data) {
        return -1;
    }

    size_t required = attestations->length * LANTERN_VOTE_SSZ_SIZE;
    if (remaining < required) {
        return -1;
    }

    size_t offset = 0;
    for (size_t i = 0; i < attestations->length; ++i) {
        size_t vote_written = 0;
        if (lantern_ssz_encode_vote(&attestations->data[i], out + offset, remaining - offset, &vote_written) != 0) {
            return -1;
        }
        offset += vote_written;
    }
    set_written(written, offset);
    return 0;
}

static int decode_attestations(LanternAttestations *attestations, const uint8_t *data, size_t data_len) {
    if (!attestations) {
        return -1;
    }
    if (data_len == 0) {
        return lantern_attestations_resize(attestations, 0);
    }
    if (data_len % LANTERN_VOTE_SSZ_SIZE != 0) {
        return -1;
    }
    size_t count = data_len / LANTERN_VOTE_SSZ_SIZE;
    if (count > LANTERN_MAX_ATTESTATIONS) {
        return -1;
    }
    if (lantern_attestations_resize(attestations, count) != 0) {
        return -1;
    }
    for (size_t i = 0; i < count; ++i) {
        if (lantern_ssz_decode_vote(&attestations->data[i], data + (i * LANTERN_VOTE_SSZ_SIZE), LANTERN_VOTE_SSZ_SIZE) != 0) {
            return -1;
        }
    }
    return 0;
}

static int encode_block_signatures(
    const LanternBlockSignatures *signatures,
    uint8_t *out,
    size_t remaining,
    size_t *written) {
    if (!signatures) {
        return -1;
    }
    if (signatures->length > LANTERN_MAX_BLOCK_SIGNATURES) {
        return -1;
    }
    if (signatures->length > 0 && !signatures->data) {
        return -1;
    }

    size_t required = signatures->length * LANTERN_SIGNATURE_SIZE;
    if (remaining < required) {
        return -1;
    }

    size_t offset = 0;
    for (size_t i = 0; i < signatures->length; ++i) {
        memcpy(out + offset, signatures->data[i].bytes, LANTERN_SIGNATURE_SIZE);
        offset += LANTERN_SIGNATURE_SIZE;
    }
    set_written(written, offset);
    return 0;
}

static int decode_block_signatures(
    LanternBlockSignatures *signatures,
    const uint8_t *data,
    size_t data_len) {
    if (!signatures) {
        return -1;
    }
    if (data_len == 0) {
        return lantern_block_signatures_resize(signatures, 0);
    }
    if (!data || data_len % LANTERN_SIGNATURE_SIZE != 0) {
        return -1;
    }
    size_t count = data_len / LANTERN_SIGNATURE_SIZE;
    if (count > LANTERN_MAX_BLOCK_SIGNATURES) {
        return -1;
    }
    if (lantern_block_signatures_resize(signatures, count) != 0) {
        return -1;
    }
    for (size_t i = 0; i < count; ++i) {
        memcpy(signatures->data[i].bytes, data + (i * LANTERN_SIGNATURE_SIZE), LANTERN_SIGNATURE_SIZE);
    }
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
    size_t byte_len = (list->bit_length + 7) / 8;
    bool needs_extra = (list->bit_length % 8) == 0;
    size_t total = byte_len + (needs_extra ? 1 : 0);
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

int lantern_ssz_encode_config(const LanternConfig *config, uint8_t *out, size_t out_len, size_t *written) {
    if (!config || !out || out_len < LANTERN_CONFIG_SSZ_SIZE) {
        return -1;
    }
    size_t offset = 0;
    if (write_u64(out + offset, out_len - offset, config->num_validators) != 0) {
        return -1;
    }
    offset += SSZ_BYTE_SIZE_OF_UINT64;
    if (write_u64(out + offset, out_len - offset, config->genesis_time) != 0) {
        return -1;
    }
    offset += SSZ_BYTE_SIZE_OF_UINT64;
    set_written(written, offset);
    return 0;
}

int lantern_ssz_decode_config(LanternConfig *config, const uint8_t *data, size_t data_len) {
    if (!config || !data || data_len < LANTERN_CONFIG_SSZ_SIZE) {
        return -1;
    }
    size_t offset = 0;
    if (read_u64(data + offset, data_len - offset, &config->num_validators) != 0) {
        return -1;
    }
    offset += SSZ_BYTE_SIZE_OF_UINT64;
    if (read_u64(data + offset, data_len - offset, &config->genesis_time) != 0) {
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

static int encode_vote_internal(const LanternVote *vote, uint8_t *out, size_t out_len, size_t *written) {
    if (!vote || !out || out_len < LANTERN_VOTE_SSZ_SIZE) {
        return -1;
    }
    size_t offset = 0;
    if (write_u64(out + offset, out_len - offset, vote->validator_id) != 0) {
        return -1;
    }
    offset += SSZ_BYTE_SIZE_OF_UINT64;
    if (write_u64(out + offset, out_len - offset, vote->slot) != 0) {
        return -1;
    }
    offset += SSZ_BYTE_SIZE_OF_UINT64;

    size_t tmp_written = 0;
    if (lantern_ssz_encode_checkpoint(&vote->head, out + offset, out_len - offset, &tmp_written) != 0) {
        return -1;
    }
    offset += tmp_written;
    if (lantern_ssz_encode_checkpoint(&vote->target, out + offset, out_len - offset, &tmp_written) != 0) {
        return -1;
    }
    offset += tmp_written;
    if (lantern_ssz_encode_checkpoint(&vote->source, out + offset, out_len - offset, &tmp_written) != 0) {
        return -1;
    }
    offset += tmp_written;

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
    if (read_u64(data + offset, data_len - offset, &vote->slot) != 0) {
        return -1;
    }
    offset += SSZ_BYTE_SIZE_OF_UINT64;

    if (lantern_ssz_decode_checkpoint(&vote->head, data + offset, LANTERN_CHECKPOINT_SSZ_SIZE) != 0) {
        return -1;
    }
    offset += LANTERN_CHECKPOINT_SSZ_SIZE;
    if (lantern_ssz_decode_checkpoint(&vote->target, data + offset, LANTERN_CHECKPOINT_SSZ_SIZE) != 0) {
        return -1;
    }
    offset += LANTERN_CHECKPOINT_SSZ_SIZE;
    if (lantern_ssz_decode_checkpoint(&vote->source, data + offset, LANTERN_CHECKPOINT_SSZ_SIZE) != 0) {
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
    memcpy(vote->signature.bytes, data + offset, LANTERN_SIGNATURE_SIZE);
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
    size_t att_bytes = body->attestations.length * LANTERN_VOTE_SSZ_SIZE;
    if (att_bytes > UINT32_MAX) {
        return -1;
    }
    if ((size_t)att_offset > SIZE_MAX - att_bytes) {
        return -1;
    }
    size_t total = att_offset + att_bytes;
    if (out_len < total) {
        return -1;
    }

    if (write_u32(out, out_len, att_offset) != 0) {
        return -1;
    }

    if (encode_attestations(&body->attestations, out + att_offset, out_len - att_offset, NULL) != 0) {
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
    if (decode_attestations(&body->attestations, data + att_offset, att_size) != 0) {
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
    const char *debug_env = getenv("LANTERN_DEBUG_SSZ");
    bool debug_ssz = debug_env && debug_env[0] != '\0';
    int debug_stage = 0;
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
    const char *debug_env = getenv("LANTERN_DEBUG_SSZ");
    bool debug_ssz = debug_env && debug_env[0] != '\0';
    int debug_stage = 0;
    size_t offset = 0;
    const size_t offsets_size = var_field_count * SSZ_BYTE_SIZE_OF_UINT32;
    const size_t min_full_size = LANTERN_CONFIG_SSZ_SIZE + SSZ_BYTE_SIZE_OF_UINT64 + LANTERN_BLOCK_HEADER_SSZ_SIZE
        + (2 * LANTERN_CHECKPOINT_SSZ_SIZE) + offsets_size;
    if (data_len < min_full_size) {
        return -1;
    }
    if (debug_ssz) {
        lantern_log_debug("ssz", NULL, "ssz decode state: entry data_len=%zu", data_len);
    }

    if (lantern_ssz_decode_config(&state->config, data + offset, LANTERN_CONFIG_SSZ_SIZE) != 0) {
        return -1;
    }
    offset += LANTERN_CONFIG_SSZ_SIZE;
    if (debug_ssz) {
        lantern_log_debug("ssz", NULL, "ssz decode state: stage %d config decoded", debug_stage++);
    }

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
    if (debug_ssz) {
        lantern_log_debug("ssz", NULL, "ssz decode state: stage %d slot=%" PRIu64, debug_stage++, state->slot);
        lantern_log_debug("ssz", NULL, "ssz decode state: stage %d header slot=%" PRIu64, debug_stage++, state->latest_block_header.slot);
    }

    if (data_len - offset < LANTERN_CHECKPOINT_SSZ_SIZE) {
        return -1;
    }
    if (lantern_ssz_decode_checkpoint(&state->latest_justified, data + offset, LANTERN_CHECKPOINT_SSZ_SIZE) != 0) {
        return -1;
    }
    offset += LANTERN_CHECKPOINT_SSZ_SIZE;
    if (debug_ssz) {
        lantern_log_debug(
            "ssz",
            NULL,
            "ssz decode state: stage %d latest_justified slot=%" PRIu64,
            debug_stage++,
            state->latest_justified.slot);
    }

    if (data_len - offset < LANTERN_CHECKPOINT_SSZ_SIZE) {
        return -1;
    }
    if (lantern_ssz_decode_checkpoint(&state->latest_finalized, data + offset, LANTERN_CHECKPOINT_SSZ_SIZE) != 0) {
        return -1;
    }
    offset += LANTERN_CHECKPOINT_SSZ_SIZE;
    if (debug_ssz) {
        lantern_log_debug(
            "ssz",
            NULL,
            "ssz decode state: stage %d latest_finalized slot=%" PRIu64,
            debug_stage++,
            state->latest_finalized.slot);
    }

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
    if (debug_ssz) {
        lantern_log_debug("ssz", NULL, "ssz decode state: stage %d offsets parsed (table_end=%zu)", debug_stage++, offset);
    }

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

    if (debug_ssz) {
        lantern_log_debug(
            "ssz",
            NULL,
            "ssz decode state: offsets_start=%zu table_end=%zu data_len=%zu",
            offsets_start,
            offset,
            data_len);
        lantern_log_debug(
            "ssz",
            NULL,
            "ssz decode state: chunks hist=%zu slots=%zu validators=%zu roots=%zu just_validators=%zu",
            chunk_sizes[0],
            chunk_sizes[1],
            chunk_sizes[2],
            chunk_sizes[3],
            chunk_sizes[4]);
    }

    if (decode_root_list(&state->historical_block_hashes, data + offsets[0], chunk_sizes[0]) != 0) {
        if (debug_ssz) {
            lantern_log_debug("ssz", NULL, "ssz decode state: failed historical_block_hashes len=%zu", chunk_sizes[0]);
        }
        return -1;
    }
    if (decode_bitlist(&state->justified_slots, data + offsets[1], chunk_sizes[1]) != 0) {
        if (debug_ssz) {
            lantern_log_debug("ssz", NULL, "ssz decode state: failed justified_slots len=%zu", chunk_sizes[1]);
        }
        return -1;
    }
    if (decode_validators_list(state, data + offsets[2], chunk_sizes[2]) != 0) {
        if (debug_ssz) {
            lantern_log_debug("ssz", NULL, "ssz decode state: failed validators len=%zu", chunk_sizes[2]);
        }
        return -1;
    }
    if (decode_root_list(&state->justification_roots, data + offsets[3], chunk_sizes[3]) != 0) {
        if (debug_ssz) {
            lantern_log_debug("ssz", NULL, "ssz decode state: failed justification_roots len=%zu", chunk_sizes[3]);
        }
        return -1;
    }
    if (decode_bitlist(&state->justification_validators, data + offsets[4], chunk_sizes[4]) != 0) {
        if (debug_ssz) {
            lantern_log_debug("ssz", NULL, "ssz decode state: failed justification_validators len=%zu", chunk_sizes[4]);
        }
        return -1;
    }

    state->config.num_validators = (uint64_t)state->validator_count;
    return 0;
}
