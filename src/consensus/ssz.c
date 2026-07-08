#include "lantern/consensus/ssz.h"

#include <limits.h>
#include <stdlib.h>
#include <string.h>

#include "ssz.h"

#include "lantern/consensus/state.h"

static const size_t CONFIG_FIELDS[] = {
    sizeof(uint64_t),
};
static const ssz_container_schema_t CONFIG_SCHEMA = SSZ_CONTAINER_SCHEMA_FROM_ARRAY(CONFIG_FIELDS);

static const size_t CHECKPOINT_FIELDS[] = {
    LANTERN_ROOT_SIZE,
    sizeof(uint64_t),
};
static const ssz_container_schema_t CHECKPOINT_SCHEMA = SSZ_CONTAINER_SCHEMA_FROM_ARRAY(CHECKPOINT_FIELDS);

static const size_t ATTESTATION_DATA_FIELDS[] = {
    sizeof(uint64_t),
    LANTERN_CHECKPOINT_SSZ_SIZE,
    LANTERN_CHECKPOINT_SSZ_SIZE,
    LANTERN_CHECKPOINT_SSZ_SIZE,
};
static const ssz_container_schema_t ATTESTATION_DATA_SCHEMA =
    SSZ_CONTAINER_SCHEMA_FROM_ARRAY(ATTESTATION_DATA_FIELDS);

static const size_t VOTE_FIELDS[] = {
    sizeof(uint64_t),
    LANTERN_ATTESTATION_DATA_SSZ_SIZE,
};
static const ssz_container_schema_t VOTE_SCHEMA = SSZ_CONTAINER_SCHEMA_FROM_ARRAY(VOTE_FIELDS);

static const size_t SIGNED_VOTE_FIELDS[] = {
    LANTERN_VOTE_SSZ_SIZE,
    LANTERN_SIGNATURE_SIZE,
};
static const ssz_container_schema_t SIGNED_VOTE_SCHEMA = SSZ_CONTAINER_SCHEMA_FROM_ARRAY(SIGNED_VOTE_FIELDS);

static const size_t VALIDATOR_FIELDS[] = {
    LANTERN_VALIDATOR_PUBKEY_SIZE,
    LANTERN_VALIDATOR_PUBKEY_SIZE,
    sizeof(uint64_t),
};
static const ssz_container_schema_t VALIDATOR_SCHEMA = SSZ_CONTAINER_SCHEMA_FROM_ARRAY(VALIDATOR_FIELDS);

static const size_t AGGREGATED_ATTESTATION_FIELDS[] = {
    0u,
    LANTERN_ATTESTATION_DATA_SSZ_SIZE,
};
static const ssz_container_schema_t AGGREGATED_ATTESTATION_SCHEMA =
    SSZ_CONTAINER_SCHEMA_FROM_ARRAY(AGGREGATED_ATTESTATION_FIELDS);

static const size_t AGGREGATED_SIGNATURE_PROOF_FIELDS[] = {
    0u,
    0u,
};
static const ssz_container_schema_t AGGREGATED_SIGNATURE_PROOF_SCHEMA =
    SSZ_CONTAINER_SCHEMA_FROM_ARRAY(AGGREGATED_SIGNATURE_PROOF_FIELDS);

static const size_t MULTI_MESSAGE_AGGREGATE_FIELDS[] = {
    0u,
};
static const ssz_container_schema_t MULTI_MESSAGE_AGGREGATE_SCHEMA =
    SSZ_CONTAINER_SCHEMA_FROM_ARRAY(MULTI_MESSAGE_AGGREGATE_FIELDS);

static const size_t SIGNED_AGGREGATED_ATTESTATION_FIELDS[] = {
    LANTERN_ATTESTATION_DATA_SSZ_SIZE,
    0u,
};
static const ssz_container_schema_t SIGNED_AGGREGATED_ATTESTATION_SCHEMA =
    SSZ_CONTAINER_SCHEMA_FROM_ARRAY(SIGNED_AGGREGATED_ATTESTATION_FIELDS);

static const size_t BLOCK_BODY_FIELDS[] = {
    0u,
};
static const ssz_container_schema_t BLOCK_BODY_SCHEMA = SSZ_CONTAINER_SCHEMA_FROM_ARRAY(BLOCK_BODY_FIELDS);

static const size_t BLOCK_HEADER_FIELDS[] = {
    sizeof(uint64_t),
    sizeof(uint64_t),
    LANTERN_ROOT_SIZE,
    LANTERN_ROOT_SIZE,
    LANTERN_ROOT_SIZE,
};
static const ssz_container_schema_t BLOCK_HEADER_SCHEMA = SSZ_CONTAINER_SCHEMA_FROM_ARRAY(BLOCK_HEADER_FIELDS);

static const size_t BLOCK_FIELDS[] = {
    sizeof(uint64_t),
    sizeof(uint64_t),
    LANTERN_ROOT_SIZE,
    LANTERN_ROOT_SIZE,
    0u,
};
static const ssz_container_schema_t BLOCK_SCHEMA = SSZ_CONTAINER_SCHEMA_FROM_ARRAY(BLOCK_FIELDS);

static const size_t SIGNED_BLOCK_FIELDS[] = {
    0u,
    0u,
};
static const ssz_container_schema_t SIGNED_BLOCK_SCHEMA = SSZ_CONTAINER_SCHEMA_FROM_ARRAY(SIGNED_BLOCK_FIELDS);

static const size_t STATE_FIELDS[] = {
    LANTERN_CONFIG_SSZ_SIZE,
    sizeof(uint64_t),
    LANTERN_BLOCK_HEADER_SSZ_SIZE,
    LANTERN_CHECKPOINT_SSZ_SIZE,
    LANTERN_CHECKPOINT_SSZ_SIZE,
    0u,
    0u,
    0u,
    0u,
    0u,
};
static const ssz_container_schema_t STATE_SCHEMA = SSZ_CONTAINER_SCHEMA_FROM_ARRAY(STATE_FIELDS);

#define DEFINE_STATIC_CONTAINER_CODEC(ENCODE_NAME, DECODE_NAME, TYPE, CTX_TYPE, SCHEMA, WRITE_FN, READ_FN) \
static ssz_error_t ENCODE_NAME( \
    const TYPE *value, \
    uint8_t *out, \
    size_t out_len, \
    size_t *written) { \
    struct CTX_TYPE ctx = {.write = value}; \
    ssz_member_codec_t codec = {.ctx = &ctx, .write = WRITE_FN}; \
    return ssz_serialize_container(&SCHEMA, &codec, out, out_len, written); \
} \
static ssz_error_t DECODE_NAME(TYPE *value, const uint8_t *data, size_t data_len) { \
    struct CTX_TYPE ctx = {.read = value}; \
    ssz_member_codec_t codec = {.ctx = &ctx, .read = READ_FN}; \
    return ssz_deserialize_container(data, data_len, &SCHEMA, &codec); \
}

#define DEFINE_PUBLIC_CONTAINER_CODEC(ENCODE_NAME, DECODE_NAME, TYPE, CTX_TYPE, SCHEMA, WRITE_FN, READ_FN) \
ssz_error_t ENCODE_NAME( \
    const TYPE *value, \
    uint8_t *out, \
    size_t out_len, \
    size_t *written) { \
    struct CTX_TYPE ctx = {.write = value}; \
    ssz_member_codec_t codec = {.ctx = &ctx, .write = WRITE_FN}; \
    return ssz_serialize_container(&SCHEMA, &codec, out, out_len, written); \
} \
ssz_error_t DECODE_NAME(TYPE *value, const uint8_t *data, size_t data_len) { \
    struct CTX_TYPE ctx = {.read = value}; \
    ssz_member_codec_t codec = {.ctx = &ctx, .read = READ_FN}; \
    return ssz_deserialize_container(data, data_len, &SCHEMA, &codec); \
}

static ssz_error_t lantern_rc_to_ssz(int rc) {
    return rc == 0 ? SSZ_SUCCESS : SSZ_ERR_INVALID_ARGUMENT;
}

static ssz_error_t prepare_output(size_t required, uint8_t *out, size_t out_len, size_t *written) {
    if (!out && !written) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    if (out && out_len < required) {
        return SSZ_ERR_BUFFER_TOO_SMALL;
    }
    if (written) {
        *written = required;
    }
    return SSZ_SUCCESS;
}

static ssz_error_t write_bytes(
    const uint8_t *src,
    size_t src_len,
    uint8_t *out,
    size_t out_len,
    size_t *written) {
    ssz_error_t err = SSZ_SUCCESS;
    if (src_len > 0u && !src) {
        err = SSZ_ERR_INVALID_ARGUMENT;
    } else {
        err = prepare_output(src_len, out, out_len, written);
        if (err == SSZ_SUCCESS && out && src_len > 0u) {
            memcpy(out, src, src_len);
        }
    }
    return err;
}

static ssz_error_t read_bytes(uint8_t *dst, size_t dst_len, const uint8_t *data, size_t data_len) {
    if (!dst || (!data && data_len > 0u)) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    if (data_len != dst_len) {
        return SSZ_ERR_ENCODING_INVALID;
    }
    if (dst_len > 0u) {
        memcpy(dst, data, dst_len);
    }
    return SSZ_SUCCESS;
}

static ssz_error_t write_u64(uint64_t value, uint8_t *out, size_t out_len, size_t *written) {
    ssz_error_t err = prepare_output(sizeof(uint64_t), out, out_len, written);
    if (err == SSZ_SUCCESS && out) {
        err = ssz_serialize_uint64(value, out);
    }
    return err;
}

static ssz_error_t read_u64(const uint8_t *data, size_t data_len, uint64_t *value) {
    return ssz_deserialize_uint64(data, data_len, value);
}

static uint32_t read_u32_le_local(const uint8_t data[4]) {
    return (uint32_t)data[0]
        | ((uint32_t)data[1] << 8u)
        | ((uint32_t)data[2] << 16u)
        | ((uint32_t)data[3] << 24u);
}

static ssz_error_t write_root(const LanternRoot *root, uint8_t *out, size_t out_len, size_t *written) {
    return write_bytes(root ? root->bytes : NULL, LANTERN_ROOT_SIZE, out, out_len, written);
}

static ssz_error_t read_root(const uint8_t *data, size_t data_len, LanternRoot *root) {
    return read_bytes(root ? root->bytes : NULL, LANTERN_ROOT_SIZE, data, data_len);
}

static ssz_error_t write_signature(
    const LanternSignature *signature,
    uint8_t *out,
    size_t out_len,
    size_t *written) {
    return write_bytes(signature ? signature->bytes : NULL, LANTERN_SIGNATURE_SIZE, out, out_len, written);
}

static ssz_error_t read_signature(const uint8_t *data, size_t data_len, LanternSignature *signature) {
    return read_bytes(signature ? signature->bytes : NULL, LANTERN_SIGNATURE_SIZE, data, data_len);
}

static ssz_error_t encode_bitlist(
    const struct lantern_bitlist *list,
    uint8_t *out,
    size_t out_len,
    size_t *written) {
    if (!list) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    size_t byte_len = (list->bit_length + 7u) / 8u;
    return ssz_serialize_bitlist(
        list->bytes,
        byte_len,
        list->bit_length,
        SSZ_NO_LIMIT,
        out,
        out_len,
        written);
}

static ssz_error_t decode_bitlist_with_limit(
    struct lantern_bitlist *list,
    const uint8_t *data,
    size_t data_len,
    uint64_t max_bits) {
    if (!list) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    size_t scratch_len = data_len == 0u ? 1u : data_len;
    uint8_t *decoded = calloc(scratch_len, sizeof(*decoded));
    if (!decoded) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    uint64_t bit_length = 0u;
    ssz_error_t err = ssz_deserialize_bitlist(
        data,
        data_len,
        max_bits,
        decoded,
        scratch_len,
        &bit_length);
    if (err == SSZ_SUCCESS && bit_length > SIZE_MAX) {
        err = SSZ_ERR_OVERFLOW;
    }
    if (err == SSZ_SUCCESS) {
        err = lantern_rc_to_ssz(lantern_bitlist_resize(list, (size_t)bit_length));
    }
    if (err == SSZ_SUCCESS) {
        size_t byte_len = ((size_t)bit_length + 7u) / 8u;
        if (byte_len > 0u) {
            memcpy(list->bytes, decoded, byte_len);
        }
    }
    free(decoded);
    return err;
}

static ssz_error_t decode_bitlist(struct lantern_bitlist *list, const uint8_t *data, size_t data_len) {
    return decode_bitlist_with_limit(list, data, data_len, SSZ_NO_LIMIT);
}

static ssz_error_t encode_byte_list(
    const LanternByteList *list,
    uint8_t *out,
    size_t out_len,
    size_t *written) {
    if (!list) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    return ssz_serialize_list_fixed(
        list->data,
        list->length,
        LANTERN_AGG_PROOF_MAX_BYTES,
        sizeof(uint8_t),
        out,
        out_len,
        written);
}

static ssz_error_t decode_byte_list(LanternByteList *list, const uint8_t *data, size_t data_len) {
    if (!list) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    if (data_len > LANTERN_AGG_PROOF_MAX_BYTES) {
        return SSZ_ERR_LIMIT_EXCEEDED;
    }
    ssz_error_t err = lantern_rc_to_ssz(lantern_byte_list_resize(list, data_len));
    if (err != SSZ_SUCCESS) {
        return err;
    }
    uint64_t decoded_count = 0u;
    err = ssz_deserialize_list_fixed(
        data,
        data_len,
        LANTERN_AGG_PROOF_MAX_BYTES,
        sizeof(uint8_t),
        list->data,
        list->capacity,
        &decoded_count);
    if (err == SSZ_SUCCESS && decoded_count != data_len) {
        err = SSZ_ERR_ENCODING_INVALID;
    }
    return err;
}

static ssz_error_t multi_message_aggregate_raw_span(
    const LanternByteList *aggregate,
    const uint8_t **out_raw,
    size_t *out_raw_len) {
    if (!aggregate || !out_raw || !out_raw_len) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    if (aggregate->length == 0u) {
        *out_raw = NULL;
        *out_raw_len = 0u;
        return SSZ_SUCCESS;
    }
    if (!aggregate->data || aggregate->length < SSZ_BYTES_PER_LENGTH_OFFSET) {
        return SSZ_ERR_ENCODING_INVALID;
    }
    uint32_t offset = read_u32_le_local(aggregate->data);
    if (offset != SSZ_BYTES_PER_LENGTH_OFFSET || (size_t)offset > aggregate->length) {
        return SSZ_ERR_OFFSET_INVALID;
    }
    size_t raw_len = aggregate->length - (size_t)offset;
    if (raw_len > LANTERN_AGG_PROOF_MAX_BYTES) {
        return SSZ_ERR_LIMIT_EXCEEDED;
    }
    *out_raw = raw_len > 0u ? aggregate->data + offset : NULL;
    *out_raw_len = raw_len;
    return SSZ_SUCCESS;
}

struct multi_message_aggregate_codec_ctx {
    const LanternByteList *write;
    LanternByteList *read;
};

static ssz_error_t multi_message_aggregate_write(
    const void *ctx,
    uint64_t member_id,
    uint8_t *out,
    size_t out_len,
    size_t *written) {
    const struct multi_message_aggregate_codec_ctx *aggregate_ctx = ctx;
    if (!aggregate_ctx || !aggregate_ctx->write || member_id != 0u) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    const uint8_t *raw = NULL;
    size_t raw_len = 0u;
    ssz_error_t err = multi_message_aggregate_raw_span(aggregate_ctx->write, &raw, &raw_len);
    if (err != SSZ_SUCCESS) {
        return err;
    }
    return ssz_serialize_list_fixed(
        raw,
        raw_len,
        LANTERN_AGG_PROOF_MAX_BYTES,
        sizeof(uint8_t),
        out,
        out_len,
        written);
}

static ssz_error_t multi_message_aggregate_read(
    void *ctx,
    uint64_t member_id,
    const uint8_t *data,
    size_t data_len) {
    struct multi_message_aggregate_codec_ctx *aggregate_ctx = ctx;
    if (!aggregate_ctx || !aggregate_ctx->read || member_id != 0u) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    if (data_len > LANTERN_AGG_PROOF_MAX_BYTES) {
        return SSZ_ERR_LIMIT_EXCEEDED;
    }
    ssz_error_t err = lantern_rc_to_ssz(lantern_byte_list_resize(aggregate_ctx->read, data_len + SSZ_BYTES_PER_LENGTH_OFFSET));
    if (err != SSZ_SUCCESS) {
        return err;
    }
    aggregate_ctx->read->data[0] = SSZ_BYTES_PER_LENGTH_OFFSET;
    aggregate_ctx->read->data[1] = 0u;
    aggregate_ctx->read->data[2] = 0u;
    aggregate_ctx->read->data[3] = 0u;
    if (data_len > 0u) {
        memcpy(aggregate_ctx->read->data + SSZ_BYTES_PER_LENGTH_OFFSET, data, data_len);
    }
    return SSZ_SUCCESS;
}

DEFINE_STATIC_CONTAINER_CODEC(
    encode_multi_message_aggregate,
    decode_multi_message_aggregate,
    LanternByteList,
    multi_message_aggregate_codec_ctx,
    MULTI_MESSAGE_AGGREGATE_SCHEMA,
    multi_message_aggregate_write,
    multi_message_aggregate_read)

static ssz_error_t encode_root_list(
    const struct lantern_root_list *list,
    uint8_t *out,
    size_t out_len,
    size_t *written) {
    if (!list) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    return ssz_serialize_list_fixed(
        (const uint8_t *)list->items,
        list->length,
        SSZ_NO_LIMIT,
        LANTERN_ROOT_SIZE,
        out,
        out_len,
        written);
}

static ssz_error_t decode_root_list(struct lantern_root_list *list, const uint8_t *data, size_t data_len) {
    if (!list) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    if (data_len % LANTERN_ROOT_SIZE != 0u) {
        return SSZ_ERR_ENCODING_INVALID;
    }
    size_t count = data_len / LANTERN_ROOT_SIZE;
    ssz_error_t err = lantern_rc_to_ssz(lantern_root_list_resize(list, count));
    if (err != SSZ_SUCCESS) {
        return err;
    }
    uint64_t decoded_count = 0u;
    err = ssz_deserialize_list_fixed(
        data,
        data_len,
        SSZ_NO_LIMIT,
        LANTERN_ROOT_SIZE,
        (uint8_t *)list->items,
        count * sizeof(*list->items),
        &decoded_count);
    if (err == SSZ_SUCCESS && decoded_count != count) {
        err = SSZ_ERR_ENCODING_INVALID;
    }
    return err;
}

struct config_codec_ctx {
    const LanternConfig *write;
    LanternConfig *read;
};

static ssz_error_t config_write(
    const void *ctx,
    uint64_t member_id,
    uint8_t *out,
    size_t out_len,
    size_t *written) {
    const struct config_codec_ctx *config_ctx = ctx;
    if (!config_ctx || !config_ctx->write || member_id != 0u) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    return write_u64(config_ctx->write->genesis_time, out, out_len, written);
}

static ssz_error_t config_read(void *ctx, uint64_t member_id, const uint8_t *data, size_t data_len) {
    struct config_codec_ctx *config_ctx = ctx;
    if (!config_ctx || !config_ctx->read || member_id != 0u) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    config_ctx->read->num_validators = 0u;
    return read_u64(data, data_len, &config_ctx->read->genesis_time);
}

DEFINE_PUBLIC_CONTAINER_CODEC(
    lantern_ssz_encode_config,
    lantern_ssz_decode_config,
    LanternConfig,
    config_codec_ctx,
    CONFIG_SCHEMA,
    config_write,
    config_read)

struct checkpoint_codec_ctx {
    const LanternCheckpoint *write;
    LanternCheckpoint *read;
};

static ssz_error_t checkpoint_write(
    const void *ctx,
    uint64_t member_id,
    uint8_t *out,
    size_t out_len,
    size_t *written) {
    const struct checkpoint_codec_ctx *checkpoint_ctx = ctx;
    if (!checkpoint_ctx || !checkpoint_ctx->write) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    switch (member_id) {
    case 0:
        return write_root(&checkpoint_ctx->write->root, out, out_len, written);
    case 1:
        return write_u64(checkpoint_ctx->write->slot, out, out_len, written);
    default:
        return SSZ_ERR_INVALID_ARGUMENT;
    }
}

static ssz_error_t checkpoint_read(void *ctx, uint64_t member_id, const uint8_t *data, size_t data_len) {
    struct checkpoint_codec_ctx *checkpoint_ctx = ctx;
    if (!checkpoint_ctx || !checkpoint_ctx->read) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    switch (member_id) {
    case 0:
        return read_root(data, data_len, &checkpoint_ctx->read->root);
    case 1:
        return read_u64(data, data_len, &checkpoint_ctx->read->slot);
    default:
        return SSZ_ERR_INVALID_ARGUMENT;
    }
}

DEFINE_PUBLIC_CONTAINER_CODEC(
    lantern_ssz_encode_checkpoint,
    lantern_ssz_decode_checkpoint,
    LanternCheckpoint,
    checkpoint_codec_ctx,
    CHECKPOINT_SCHEMA,
    checkpoint_write,
    checkpoint_read)

struct attestation_data_codec_ctx {
    const LanternAttestationData *write;
    LanternAttestationData *read;
};

static ssz_error_t attestation_data_write(
    const void *ctx,
    uint64_t member_id,
    uint8_t *out,
    size_t out_len,
    size_t *written) {
    const struct attestation_data_codec_ctx *data_ctx = ctx;
    if (!data_ctx || !data_ctx->write) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    switch (member_id) {
    case 0:
        return write_u64(data_ctx->write->slot, out, out_len, written);
    case 1:
        return lantern_ssz_encode_checkpoint(&data_ctx->write->head, out, out_len, written);
    case 2:
        return lantern_ssz_encode_checkpoint(&data_ctx->write->target, out, out_len, written);
    case 3:
        return lantern_ssz_encode_checkpoint(&data_ctx->write->source, out, out_len, written);
    default:
        return SSZ_ERR_INVALID_ARGUMENT;
    }
}

static ssz_error_t attestation_data_read(void *ctx, uint64_t member_id, const uint8_t *data, size_t data_len) {
    struct attestation_data_codec_ctx *data_ctx = ctx;
    if (!data_ctx || !data_ctx->read) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    switch (member_id) {
    case 0:
        return read_u64(data, data_len, &data_ctx->read->slot);
    case 1:
        return lantern_ssz_decode_checkpoint(&data_ctx->read->head, data, data_len);
    case 2:
        return lantern_ssz_decode_checkpoint(&data_ctx->read->target, data, data_len);
    case 3:
        return lantern_ssz_decode_checkpoint(&data_ctx->read->source, data, data_len);
    default:
        return SSZ_ERR_INVALID_ARGUMENT;
    }
}

DEFINE_STATIC_CONTAINER_CODEC(
    encode_attestation_data,
    decode_attestation_data,
    LanternAttestationData,
    attestation_data_codec_ctx,
    ATTESTATION_DATA_SCHEMA,
    attestation_data_write,
    attestation_data_read)

ssz_error_t lantern_ssz_encode_attestation_data(
    const LanternAttestationData *data,
    uint8_t *out,
    size_t out_len,
    size_t *written) {
    return encode_attestation_data(data, out, out_len, written);
}

ssz_error_t lantern_ssz_decode_attestation_data(
    LanternAttestationData *data,
    const uint8_t *raw,
    size_t raw_len) {
    return decode_attestation_data(data, raw, raw_len);
}

struct vote_codec_ctx {
    const LanternVote *write;
    LanternVote *read;
};

static ssz_error_t vote_write(
    const void *ctx,
    uint64_t member_id,
    uint8_t *out,
    size_t out_len,
    size_t *written) {
    const struct vote_codec_ctx *vote_ctx = ctx;
    if (!vote_ctx || !vote_ctx->write) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    switch (member_id) {
    case 0:
        return write_u64(vote_ctx->write->validator_id, out, out_len, written);
    case 1:
        return encode_attestation_data(&vote_ctx->write->data, out, out_len, written);
    default:
        return SSZ_ERR_INVALID_ARGUMENT;
    }
}

static ssz_error_t vote_read(void *ctx, uint64_t member_id, const uint8_t *data, size_t data_len) {
    struct vote_codec_ctx *vote_ctx = ctx;
    if (!vote_ctx || !vote_ctx->read) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    switch (member_id) {
    case 0:
        return read_u64(data, data_len, &vote_ctx->read->validator_id);
    case 1:
        return decode_attestation_data(&vote_ctx->read->data, data, data_len);
    default:
        return SSZ_ERR_INVALID_ARGUMENT;
    }
}

DEFINE_STATIC_CONTAINER_CODEC(
    encode_vote_internal,
    decode_vote_internal,
    LanternVote,
    vote_codec_ctx,
    VOTE_SCHEMA,
    vote_write,
    vote_read)

ssz_error_t lantern_ssz_encode_vote(
    const LanternVote *vote,
    uint8_t *out,
    size_t out_len,
    size_t *written) {
    return encode_vote_internal(vote, out, out_len, written);
}

ssz_error_t lantern_ssz_decode_vote(LanternVote *vote, const uint8_t *data, size_t data_len) {
    return decode_vote_internal(vote, data, data_len);
}

struct signed_vote_codec_ctx {
    const LanternSignedVote *write;
    LanternSignedVote *read;
};

static ssz_error_t signed_vote_write(
    const void *ctx,
    uint64_t member_id,
    uint8_t *out,
    size_t out_len,
    size_t *written) {
    const struct signed_vote_codec_ctx *vote_ctx = ctx;
    if (!vote_ctx || !vote_ctx->write) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    switch (member_id) {
    case 0:
        return encode_vote_internal(&vote_ctx->write->data, out, out_len, written);
    case 1:
        return write_signature(&vote_ctx->write->signature, out, out_len, written);
    default:
        return SSZ_ERR_INVALID_ARGUMENT;
    }
}

static ssz_error_t signed_vote_read(void *ctx, uint64_t member_id, const uint8_t *data, size_t data_len) {
    struct signed_vote_codec_ctx *vote_ctx = ctx;
    if (!vote_ctx || !vote_ctx->read) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    switch (member_id) {
    case 0:
        return decode_vote_internal(&vote_ctx->read->data, data, data_len);
    case 1:
        return read_signature(data, data_len, &vote_ctx->read->signature);
    default:
        return SSZ_ERR_INVALID_ARGUMENT;
    }
}

DEFINE_PUBLIC_CONTAINER_CODEC(
    lantern_ssz_encode_signed_vote,
    lantern_ssz_decode_signed_vote,
    LanternSignedVote,
    signed_vote_codec_ctx,
    SIGNED_VOTE_SCHEMA,
    signed_vote_write,
    signed_vote_read)

struct validator_codec_ctx {
    const LanternValidator *write;
    LanternValidator *read;
};

static ssz_error_t validator_write(
    const void *ctx,
    uint64_t member_id,
    uint8_t *out,
    size_t out_len,
    size_t *written) {
    const struct validator_codec_ctx *validator_ctx = ctx;
    if (!validator_ctx || !validator_ctx->write) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    switch (member_id) {
    case 0:
        return write_bytes(validator_ctx->write->attestation_pubkey, LANTERN_VALIDATOR_PUBKEY_SIZE, out, out_len, written);
    case 1:
        return write_bytes(validator_ctx->write->proposal_pubkey, LANTERN_VALIDATOR_PUBKEY_SIZE, out, out_len, written);
    case 2:
        return write_u64(validator_ctx->write->index, out, out_len, written);
    default:
        return SSZ_ERR_INVALID_ARGUMENT;
    }
}

static ssz_error_t validator_read(void *ctx, uint64_t member_id, const uint8_t *data, size_t data_len) {
    struct validator_codec_ctx *validator_ctx = ctx;
    if (!validator_ctx || !validator_ctx->read) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    switch (member_id) {
    case 0:
        return read_bytes(validator_ctx->read->attestation_pubkey, LANTERN_VALIDATOR_PUBKEY_SIZE, data, data_len);
    case 1:
        return read_bytes(validator_ctx->read->proposal_pubkey, LANTERN_VALIDATOR_PUBKEY_SIZE, data, data_len);
    case 2:
        return read_u64(data, data_len, &validator_ctx->read->index);
    default:
        return SSZ_ERR_INVALID_ARGUMENT;
    }
}

DEFINE_PUBLIC_CONTAINER_CODEC(
    lantern_ssz_encode_validator,
    lantern_ssz_decode_validator,
    LanternValidator,
    validator_codec_ctx,
    VALIDATOR_SCHEMA,
    validator_write,
    validator_read)

static ssz_error_t encode_validators_list(
    const LanternValidator *validators,
    size_t count,
    uint8_t *out,
    size_t out_len,
    size_t *written) {
    if (count > SIZE_MAX / LANTERN_VALIDATOR_SSZ_SIZE) {
        return SSZ_ERR_OVERFLOW;
    }
    size_t total = count * LANTERN_VALIDATOR_SSZ_SIZE;
    ssz_error_t err = prepare_output(total, out, out_len, written);
    if (err != SSZ_SUCCESS || !out || count == 0u) {
        return err;
    }
    if (!validators) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    size_t cursor = 0u;
    for (size_t i = 0u; i < count; ++i) {
        size_t item_written = 0u;
        err = lantern_ssz_encode_validator(&validators[i], out + cursor, out_len - cursor, &item_written);
        if (err != SSZ_SUCCESS) {
            return err;
        }
        if (item_written != LANTERN_VALIDATOR_SSZ_SIZE) {
            return SSZ_ERR_TYPE_MISMATCH;
        }
        cursor += item_written;
    }
    return SSZ_SUCCESS;
}

static ssz_error_t decode_validators_list(
    LanternState *state,
    const uint8_t *data,
    size_t data_len) {
    if (!state) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    if (data_len % LANTERN_VALIDATOR_SSZ_SIZE != 0u) {
        return SSZ_ERR_ENCODING_INVALID;
    }
    size_t count = data_len / LANTERN_VALIDATOR_SSZ_SIZE;
    if (count > LANTERN_VALIDATOR_REGISTRY_LIMIT) {
        return SSZ_ERR_LIMIT_EXCEEDED;
    }
    if (count == 0u) {
        state->config.num_validators = 0u;
        return lantern_rc_to_ssz(lantern_state_set_validator_pubkeys(state, NULL, 0u));
    }
    if (!data) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    if (count > SIZE_MAX / LANTERN_VALIDATOR_PUBKEY_SIZE) {
        return SSZ_ERR_OVERFLOW;
    }
    uint8_t *attestation_pubkeys = malloc(count * LANTERN_VALIDATOR_PUBKEY_SIZE);
    uint8_t *proposal_pubkeys = malloc(count * LANTERN_VALIDATOR_PUBKEY_SIZE);
    if (!attestation_pubkeys || !proposal_pubkeys) {
        free(attestation_pubkeys);
        free(proposal_pubkeys);
        return SSZ_ERR_INVALID_ARGUMENT;
    }

    ssz_error_t err = SSZ_SUCCESS;
    LanternValidator decoded;
    for (size_t i = 0u; i < count && err == SSZ_SUCCESS; ++i) {
        memset(&decoded, 0, sizeof(decoded));
        err = lantern_ssz_decode_validator(
            &decoded,
            data + (i * LANTERN_VALIDATOR_SSZ_SIZE),
            LANTERN_VALIDATOR_SSZ_SIZE);
        if (err == SSZ_SUCCESS) {
            if (decoded.index != (uint64_t)i) {
                err = SSZ_ERR_ENCODING_INVALID;
                break;
            }
            memcpy(attestation_pubkeys + (i * LANTERN_VALIDATOR_PUBKEY_SIZE),
                   decoded.attestation_pubkey,
                   LANTERN_VALIDATOR_PUBKEY_SIZE);
            memcpy(proposal_pubkeys + (i * LANTERN_VALIDATOR_PUBKEY_SIZE),
                   decoded.proposal_pubkey,
                   LANTERN_VALIDATOR_PUBKEY_SIZE);
        }
    }

    if (err == SSZ_SUCCESS) {
        err = lantern_rc_to_ssz(lantern_state_set_validator_pubkeys_dual(
            state,
            attestation_pubkeys,
            proposal_pubkeys,
            count));
    }
    if (err == SSZ_SUCCESS) {
        state->config.num_validators = count;
    }
    free(attestation_pubkeys);
    free(proposal_pubkeys);
    return err;
}

struct aggregated_attestation_codec_ctx {
    const LanternAggregatedAttestation *write;
    LanternAggregatedAttestation *read;
};

static ssz_error_t aggregated_attestation_write(
    const void *ctx,
    uint64_t member_id,
    uint8_t *out,
    size_t out_len,
    size_t *written) {
    const struct aggregated_attestation_codec_ctx *att_ctx = ctx;
    if (!att_ctx || !att_ctx->write) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    switch (member_id) {
    case 0:
        if (att_ctx->write->aggregation_bits.bit_length > LANTERN_VALIDATOR_REGISTRY_LIMIT) {
            return SSZ_ERR_LIMIT_EXCEEDED;
        }
        return encode_bitlist(&att_ctx->write->aggregation_bits, out, out_len, written);
    case 1:
        return encode_attestation_data(&att_ctx->write->data, out, out_len, written);
    default:
        return SSZ_ERR_INVALID_ARGUMENT;
    }
}

static ssz_error_t aggregated_attestation_read(void *ctx, uint64_t member_id, const uint8_t *data, size_t data_len) {
    struct aggregated_attestation_codec_ctx *att_ctx = ctx;
    if (!att_ctx || !att_ctx->read) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    switch (member_id) {
    case 0:
        return decode_bitlist_with_limit(
            &att_ctx->read->aggregation_bits,
            data,
            data_len,
            LANTERN_VALIDATOR_REGISTRY_LIMIT);
    case 1:
        return decode_attestation_data(&att_ctx->read->data, data, data_len);
    default:
        return SSZ_ERR_INVALID_ARGUMENT;
    }
}

DEFINE_STATIC_CONTAINER_CODEC(
    encode_aggregated_attestation,
    decode_aggregated_attestation,
    LanternAggregatedAttestation,
    aggregated_attestation_codec_ctx,
    AGGREGATED_ATTESTATION_SCHEMA,
    aggregated_attestation_write,
    aggregated_attestation_read)

struct aggregated_attestations_codec_ctx {
    const LanternAggregatedAttestations *write;
    LanternAggregatedAttestations *read;
};

static ssz_error_t aggregated_attestations_write(
    const void *ctx,
    uint64_t member_id,
    uint8_t *out,
    size_t out_len,
    size_t *written) {
    const struct aggregated_attestations_codec_ctx *list_ctx = ctx;
    if (!list_ctx || !list_ctx->write || member_id >= list_ctx->write->length) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    return encode_aggregated_attestation(&list_ctx->write->data[member_id], out, out_len, written);
}

static ssz_error_t aggregated_attestations_read(void *ctx, uint64_t member_id, const uint8_t *data, size_t data_len) {
    struct aggregated_attestations_codec_ctx *list_ctx = ctx;
    if (!list_ctx || !list_ctx->read || member_id != list_ctx->read->length) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    LanternAggregatedAttestation attestation;
    lantern_aggregated_attestation_init(&attestation);
    ssz_error_t err = decode_aggregated_attestation(&attestation, data, data_len);
    if (err == SSZ_SUCCESS) {
        err = lantern_rc_to_ssz(lantern_aggregated_attestations_append(list_ctx->read, &attestation));
    }
    lantern_aggregated_attestation_reset(&attestation);
    return err;
}

static ssz_error_t encode_aggregated_attestations(
    const LanternAggregatedAttestations *attestations,
    uint8_t *out,
    size_t out_len,
    size_t *written) {
    if (!attestations) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    if (attestations->length > LANTERN_MAX_ATTESTATIONS) {
        return SSZ_ERR_LIMIT_EXCEEDED;
    }
    if (attestations->length > 0u && !attestations->data) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    struct aggregated_attestations_codec_ctx ctx = {.write = attestations};
    ssz_member_codec_t codec = {.ctx = &ctx, .write = aggregated_attestations_write};
    return ssz_serialize_list_variable(
        attestations->length,
        LANTERN_MAX_ATTESTATIONS,
        &codec,
        out,
        out_len,
        written);
}

static ssz_error_t decode_aggregated_attestations(
    LanternAggregatedAttestations *attestations,
    const uint8_t *data,
    size_t data_len) {
    if (!attestations) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    ssz_error_t err = lantern_rc_to_ssz(lantern_aggregated_attestations_resize(attestations, 0u));
    if (err != SSZ_SUCCESS) {
        return err;
    }
    struct aggregated_attestations_codec_ctx ctx = {.read = attestations};
    ssz_member_codec_t codec = {.ctx = &ctx, .read = aggregated_attestations_read};
    uint64_t count = 0u;
    err = ssz_deserialize_list_variable(
        data,
        data_len,
        LANTERN_MAX_ATTESTATIONS,
        SSZ_BYTES_PER_LENGTH_OFFSET + LANTERN_ATTESTATION_DATA_SSZ_SIZE + 1u,
        &codec,
        &count);
    if (err == SSZ_SUCCESS && count != attestations->length) {
        err = SSZ_ERR_ENCODING_INVALID;
    }
    return err;
}

struct signature_proof_codec_ctx {
    const LanternAggregatedSignatureProof *write;
    LanternAggregatedSignatureProof *read;
};

static ssz_error_t signature_proof_write(
    const void *ctx,
    uint64_t member_id,
    uint8_t *out,
    size_t out_len,
    size_t *written) {
    const struct signature_proof_codec_ctx *proof_ctx = ctx;
    if (!proof_ctx || !proof_ctx->write) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    switch (member_id) {
    case 0:
        if (proof_ctx->write->participants.bit_length > LANTERN_VALIDATOR_REGISTRY_LIMIT) {
            return SSZ_ERR_LIMIT_EXCEEDED;
        }
        return encode_bitlist(&proof_ctx->write->participants, out, out_len, written);
    case 1:
        return encode_byte_list(&proof_ctx->write->proof_data, out, out_len, written);
    default:
        return SSZ_ERR_INVALID_ARGUMENT;
    }
}

static ssz_error_t signature_proof_read(void *ctx, uint64_t member_id, const uint8_t *data, size_t data_len) {
    struct signature_proof_codec_ctx *proof_ctx = ctx;
    if (!proof_ctx || !proof_ctx->read) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    switch (member_id) {
    case 0:
        return decode_bitlist_with_limit(
            &proof_ctx->read->participants,
            data,
            data_len,
            LANTERN_VALIDATOR_REGISTRY_LIMIT);
    case 1:
        return decode_byte_list(&proof_ctx->read->proof_data, data, data_len);
    default:
        return SSZ_ERR_INVALID_ARGUMENT;
    }
}

DEFINE_STATIC_CONTAINER_CODEC(
    encode_aggregated_signature_proof,
    decode_aggregated_signature_proof,
    LanternAggregatedSignatureProof,
    signature_proof_codec_ctx,
    AGGREGATED_SIGNATURE_PROOF_SCHEMA,
    signature_proof_write,
    signature_proof_read)

struct signed_aggregated_attestation_codec_ctx {
    const LanternSignedAggregatedAttestation *write;
    LanternSignedAggregatedAttestation *read;
};

static ssz_error_t signed_aggregated_attestation_write(
    const void *ctx,
    uint64_t member_id,
    uint8_t *out,
    size_t out_len,
    size_t *written) {
    const struct signed_aggregated_attestation_codec_ctx *att_ctx = ctx;
    if (!att_ctx || !att_ctx->write) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    switch (member_id) {
    case 0:
        return encode_attestation_data(&att_ctx->write->data, out, out_len, written);
    case 1:
        return encode_aggregated_signature_proof(&att_ctx->write->proof, out, out_len, written);
    default:
        return SSZ_ERR_INVALID_ARGUMENT;
    }
}

static ssz_error_t signed_aggregated_attestation_read(
    void *ctx,
    uint64_t member_id,
    const uint8_t *data,
    size_t data_len) {
    struct signed_aggregated_attestation_codec_ctx *att_ctx = ctx;
    if (!att_ctx || !att_ctx->read) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    switch (member_id) {
    case 0:
        return decode_attestation_data(&att_ctx->read->data, data, data_len);
    case 1:
        return decode_aggregated_signature_proof(&att_ctx->read->proof, data, data_len);
    default:
        return SSZ_ERR_INVALID_ARGUMENT;
    }
}

DEFINE_PUBLIC_CONTAINER_CODEC(
    lantern_ssz_encode_signed_aggregated_attestation,
    lantern_ssz_decode_signed_aggregated_attestation,
    LanternSignedAggregatedAttestation,
    signed_aggregated_attestation_codec_ctx,
    SIGNED_AGGREGATED_ATTESTATION_SCHEMA,
    signed_aggregated_attestation_write,
    signed_aggregated_attestation_read)

ssz_error_t lantern_ssz_encode_aggregated_attestation(
    const LanternAggregatedAttestation *attestation,
    uint8_t *out,
    size_t out_len,
    size_t *written) {
    return encode_aggregated_attestation(attestation, out, out_len, written);
}

ssz_error_t lantern_ssz_decode_aggregated_attestation(
    LanternAggregatedAttestation *attestation,
    const uint8_t *data,
    size_t data_len) {
    return decode_aggregated_attestation(attestation, data, data_len);
}

ssz_error_t lantern_ssz_encode_aggregated_signature_proof(
    const LanternAggregatedSignatureProof *proof,
    uint8_t *out,
    size_t out_len,
    size_t *written) {
    return encode_aggregated_signature_proof(proof, out, out_len, written);
}

ssz_error_t lantern_ssz_decode_aggregated_signature_proof(
    LanternAggregatedSignatureProof *proof,
    const uint8_t *data,
    size_t data_len) {
    return decode_aggregated_signature_proof(proof, data, data_len);
}

ssz_error_t lantern_ssz_encode_multi_message_aggregate(
    const LanternByteList *aggregate,
    uint8_t *out,
    size_t out_len,
    size_t *written) {
    return encode_multi_message_aggregate(aggregate, out, out_len, written);
}

ssz_error_t lantern_ssz_decode_multi_message_aggregate(
    LanternByteList *aggregate,
    const uint8_t *data,
    size_t data_len) {
    return decode_multi_message_aggregate(aggregate, data, data_len);
}

struct block_header_codec_ctx {
    const LanternBlockHeader *write;
    LanternBlockHeader *read;
};

static ssz_error_t block_header_write(
    const void *ctx,
    uint64_t member_id,
    uint8_t *out,
    size_t out_len,
    size_t *written) {
    const struct block_header_codec_ctx *header_ctx = ctx;
    if (!header_ctx || !header_ctx->write) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    switch (member_id) {
    case 0:
        return write_u64(header_ctx->write->slot, out, out_len, written);
    case 1:
        return write_u64(header_ctx->write->proposer_index, out, out_len, written);
    case 2:
        return write_root(&header_ctx->write->parent_root, out, out_len, written);
    case 3:
        return write_root(&header_ctx->write->state_root, out, out_len, written);
    case 4:
        return write_root(&header_ctx->write->body_root, out, out_len, written);
    default:
        return SSZ_ERR_INVALID_ARGUMENT;
    }
}

static ssz_error_t block_header_read(void *ctx, uint64_t member_id, const uint8_t *data, size_t data_len) {
    struct block_header_codec_ctx *header_ctx = ctx;
    if (!header_ctx || !header_ctx->read) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    switch (member_id) {
    case 0:
        return read_u64(data, data_len, &header_ctx->read->slot);
    case 1:
        return read_u64(data, data_len, &header_ctx->read->proposer_index);
    case 2:
        return read_root(data, data_len, &header_ctx->read->parent_root);
    case 3:
        return read_root(data, data_len, &header_ctx->read->state_root);
    case 4:
        return read_root(data, data_len, &header_ctx->read->body_root);
    default:
        return SSZ_ERR_INVALID_ARGUMENT;
    }
}

DEFINE_PUBLIC_CONTAINER_CODEC(
    lantern_ssz_encode_block_header,
    lantern_ssz_decode_block_header,
    LanternBlockHeader,
    block_header_codec_ctx,
    BLOCK_HEADER_SCHEMA,
    block_header_write,
    block_header_read)

struct block_body_codec_ctx {
    const LanternBlockBody *write;
    LanternBlockBody *read;
};

static ssz_error_t block_body_write(
    const void *ctx,
    uint64_t member_id,
    uint8_t *out,
    size_t out_len,
    size_t *written) {
    const struct block_body_codec_ctx *body_ctx = ctx;
    if (!body_ctx || !body_ctx->write || member_id != 0u) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    return encode_aggregated_attestations(&body_ctx->write->attestations, out, out_len, written);
}

static ssz_error_t block_body_read(void *ctx, uint64_t member_id, const uint8_t *data, size_t data_len) {
    struct block_body_codec_ctx *body_ctx = ctx;
    if (!body_ctx || !body_ctx->read || member_id != 0u) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    return decode_aggregated_attestations(&body_ctx->read->attestations, data, data_len);
}

DEFINE_PUBLIC_CONTAINER_CODEC(
    lantern_ssz_encode_block_body,
    lantern_ssz_decode_block_body,
    LanternBlockBody,
    block_body_codec_ctx,
    BLOCK_BODY_SCHEMA,
    block_body_write,
    block_body_read)

struct block_codec_ctx {
    const LanternBlock *write;
    LanternBlock *read;
};

static ssz_error_t block_write(
    const void *ctx,
    uint64_t member_id,
    uint8_t *out,
    size_t out_len,
    size_t *written) {
    const struct block_codec_ctx *block_ctx = ctx;
    if (!block_ctx || !block_ctx->write) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    switch (member_id) {
    case 0:
        return write_u64(block_ctx->write->slot, out, out_len, written);
    case 1:
        return write_u64(block_ctx->write->proposer_index, out, out_len, written);
    case 2:
        return write_root(&block_ctx->write->parent_root, out, out_len, written);
    case 3:
        return write_root(&block_ctx->write->state_root, out, out_len, written);
    case 4:
        return lantern_ssz_encode_block_body(&block_ctx->write->body, out, out_len, written);
    default:
        return SSZ_ERR_INVALID_ARGUMENT;
    }
}

static ssz_error_t block_read(void *ctx, uint64_t member_id, const uint8_t *data, size_t data_len) {
    struct block_codec_ctx *block_ctx = ctx;
    if (!block_ctx || !block_ctx->read) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    switch (member_id) {
    case 0:
        return read_u64(data, data_len, &block_ctx->read->slot);
    case 1:
        return read_u64(data, data_len, &block_ctx->read->proposer_index);
    case 2:
        return read_root(data, data_len, &block_ctx->read->parent_root);
    case 3:
        return read_root(data, data_len, &block_ctx->read->state_root);
    case 4:
        return lantern_ssz_decode_block_body(&block_ctx->read->body, data, data_len);
    default:
        return SSZ_ERR_INVALID_ARGUMENT;
    }
}

DEFINE_PUBLIC_CONTAINER_CODEC(
    lantern_ssz_encode_block,
    lantern_ssz_decode_block,
    LanternBlock,
    block_codec_ctx,
    BLOCK_SCHEMA,
    block_write,
    block_read)

struct signed_block_codec_ctx {
    const LanternSignedBlock *write;
    LanternSignedBlock *read;
};

static ssz_error_t signed_block_write(
    const void *ctx,
    uint64_t member_id,
    uint8_t *out,
    size_t out_len,
    size_t *written) {
    const struct signed_block_codec_ctx *block_ctx = ctx;
    if (!block_ctx || !block_ctx->write) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    switch (member_id) {
    case 0:
        return lantern_ssz_encode_block(&block_ctx->write->block, out, out_len, written);
    case 1:
        return encode_multi_message_aggregate(&block_ctx->write->proof, out, out_len, written);
    default:
        return SSZ_ERR_INVALID_ARGUMENT;
    }
}

static ssz_error_t signed_block_read(void *ctx, uint64_t member_id, const uint8_t *data, size_t data_len) {
    struct signed_block_codec_ctx *block_ctx = ctx;
    if (!block_ctx || !block_ctx->read) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    switch (member_id) {
    case 0:
        return lantern_ssz_decode_block(&block_ctx->read->block, data, data_len);
    case 1:
        return decode_multi_message_aggregate(&block_ctx->read->proof, data, data_len);
    default:
        return SSZ_ERR_INVALID_ARGUMENT;
    }
}

DEFINE_PUBLIC_CONTAINER_CODEC(
    lantern_ssz_encode_signed_block,
    lantern_ssz_decode_signed_block,
    LanternSignedBlock,
    signed_block_codec_ctx,
    SIGNED_BLOCK_SCHEMA,
    signed_block_write,
    signed_block_read)

struct state_codec_ctx {
    const LanternState *write;
    LanternState *read;
};

static ssz_error_t state_write(
    const void *ctx,
    uint64_t member_id,
    uint8_t *out,
    size_t out_len,
    size_t *written) {
    const struct state_codec_ctx *state_ctx = ctx;
    if (!state_ctx || !state_ctx->write) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    const LanternState *state = state_ctx->write;
    switch (member_id) {
    case 0:
        return lantern_ssz_encode_config(&state->config, out, out_len, written);
    case 1:
        return write_u64(state->slot, out, out_len, written);
    case 2:
        return lantern_ssz_encode_block_header(&state->latest_block_header, out, out_len, written);
    case 3:
        return lantern_ssz_encode_checkpoint(&state->latest_justified, out, out_len, written);
    case 4:
        return lantern_ssz_encode_checkpoint(&state->latest_finalized, out, out_len, written);
    case 5:
        return encode_root_list(&state->historical_block_hashes, out, out_len, written);
    case 6:
        return encode_bitlist(&state->justified_slots, out, out_len, written);
    case 7:
        return encode_validators_list(state->validators, state->validator_count, out, out_len, written);
    case 8:
        return encode_root_list(&state->justification_roots, out, out_len, written);
    case 9:
        return encode_bitlist(&state->justification_validators, out, out_len, written);
    default:
        return SSZ_ERR_INVALID_ARGUMENT;
    }
}

static ssz_error_t state_read(void *ctx, uint64_t member_id, const uint8_t *data, size_t data_len) {
    struct state_codec_ctx *state_ctx = ctx;
    if (!state_ctx || !state_ctx->read) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    LanternState *state = state_ctx->read;
    switch (member_id) {
    case 0:
        return lantern_ssz_decode_config(&state->config, data, data_len);
    case 1:
        return read_u64(data, data_len, &state->slot);
    case 2:
        return lantern_ssz_decode_block_header(&state->latest_block_header, data, data_len);
    case 3:
        return lantern_ssz_decode_checkpoint(&state->latest_justified, data, data_len);
    case 4:
        return lantern_ssz_decode_checkpoint(&state->latest_finalized, data, data_len);
    case 5:
        return decode_root_list(&state->historical_block_hashes, data, data_len);
    case 6:
        return decode_bitlist(&state->justified_slots, data, data_len);
    case 7:
        return decode_validators_list(state, data, data_len);
    case 8:
        return decode_root_list(&state->justification_roots, data, data_len);
    case 9:
        return decode_bitlist(&state->justification_validators, data, data_len);
    default:
        return SSZ_ERR_INVALID_ARGUMENT;
    }
}

ssz_error_t lantern_ssz_encode_state(
    const LanternState *state,
    uint8_t *out,
    size_t out_len,
    size_t *written) {
    if (!state) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    if (state->config.num_validators != (uint64_t)state->validator_count) {
        return SSZ_ERR_ENCODING_INVALID;
    }
    struct state_codec_ctx ctx = {.write = state};
    ssz_member_codec_t codec = {.ctx = &ctx, .write = state_write};
    return ssz_serialize_container(&STATE_SCHEMA, &codec, out, out_len, written);
}

ssz_error_t lantern_ssz_decode_state(
    LanternState *state,
    const uint8_t *data,
    size_t data_len) {
    struct state_codec_ctx ctx = {.read = state};
    ssz_member_codec_t codec = {.ctx = &ctx, .read = state_read};
    ssz_error_t err = ssz_deserialize_container(data, data_len, &STATE_SCHEMA, &codec);
    if (err == SSZ_SUCCESS) {
        state->config.num_validators = (uint64_t)state->validator_count;
    }
    return err;
}
