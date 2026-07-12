#include "lantern/networking/enr.h"

#include "lantern/support/log.h"
#include "lantern/support/strings.h"

#include <ctype.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#include <winsock2.h>
#include <ws2tcpip.h>
#else
#include <arpa/inet.h>
#endif

#include "secp256k1.h"
#include "multiformats/multibase/multibase.h"

#define LANTERN_ENR_SIGNATURE_SIZE 64u
#define LANTERN_ENR_MAX_SIZE 300u
#define LANTERN_ENR_MAX_PAYLOAD_SIZE (((LANTERN_ENR_MAX_SIZE * 4u) + 2u) / 3u)

static uint64_t load_u64_le(const uint8_t in[8]) {
    uint64_t value = 0;
    for (size_t i = 0; i < 8; i++) {
        value |= ((uint64_t)in[i]) << (8u * i);
    }
    return value;
}

static void store_u64_le(uint64_t value, uint8_t out[8]) {
    for (size_t i = 0; i < 8; i++) {
        out[i] = (uint8_t)((value >> (8u * i)) & 0xffu);
    }
}

static uint64_t rotl64(uint64_t value, unsigned shift) {
    return (value << shift) | (value >> (64u - shift));
}

static void keccakf1600(uint64_t state[25]) {
    static const uint64_t round_constants[24] = {
        UINT64_C(0x0000000000000001), UINT64_C(0x0000000000008082),
        UINT64_C(0x800000000000808a), UINT64_C(0x8000000080008000),
        UINT64_C(0x000000000000808b), UINT64_C(0x0000000080000001),
        UINT64_C(0x8000000080008081), UINT64_C(0x8000000000008009),
        UINT64_C(0x000000000000008a), UINT64_C(0x0000000000000088),
        UINT64_C(0x0000000080008009), UINT64_C(0x000000008000000a),
        UINT64_C(0x000000008000808b), UINT64_C(0x800000000000008b),
        UINT64_C(0x8000000000008089), UINT64_C(0x8000000000008003),
        UINT64_C(0x8000000000008002), UINT64_C(0x8000000000000080),
        UINT64_C(0x000000000000800a), UINT64_C(0x800000008000000a),
        UINT64_C(0x8000000080008081), UINT64_C(0x8000000000008080),
        UINT64_C(0x0000000080000001), UINT64_C(0x8000000080008008),
    };
    static const unsigned rotation_constants[24] = {
        1, 3, 6, 10, 15, 21, 28, 36, 45, 55, 2, 14,
        27, 41, 56, 8, 25, 43, 62, 18, 39, 61, 20, 44,
    };
    static const unsigned pi_lanes[24] = {
        10, 7, 11, 17, 18, 3, 5, 16, 8, 21, 24, 4,
        15, 23, 19, 13, 12, 2, 20, 14, 22, 9, 6, 1,
    };

    for (size_t round = 0; round < 24; round++) {
        uint64_t column[5];
        for (size_t x = 0; x < 5; x++) {
            column[x] = state[x] ^ state[x + 5] ^ state[x + 10] ^ state[x + 15] ^ state[x + 20];
        }
        for (size_t x = 0; x < 5; x++) {
            uint64_t t = column[(x + 4) % 5] ^ rotl64(column[(x + 1) % 5], 1);
            for (size_t y = 0; y < 25; y += 5) {
                state[y + x] ^= t;
            }
        }

        uint64_t t = state[1];
        for (size_t i = 0; i < 24; i++) {
            unsigned lane = pi_lanes[i];
            uint64_t saved = state[lane];
            state[lane] = rotl64(t, rotation_constants[i]);
            t = saved;
        }

        for (size_t y = 0; y < 25; y += 5) {
            for (size_t x = 0; x < 5; x++) {
                column[x] = state[y + x];
            }
            for (size_t x = 0; x < 5; x++) {
                state[y + x] ^= (~column[(x + 1) % 5]) & column[(x + 2) % 5];
            }
        }

        state[0] ^= round_constants[round];
    }
}

static int keccak256_bytes(const uint8_t *data, size_t data_len, uint8_t out_hash[32]) {
    enum { KECCAK256_RATE = 136 };
    if ((!data && data_len > 0u) || !out_hash) {
        return -1;
    }

    uint64_t state[25] = {0};
    while (data_len >= KECCAK256_RATE) {
        for (size_t i = 0; i < KECCAK256_RATE / 8u; i++) {
            state[i] ^= load_u64_le(data + (i * 8u));
        }
        keccakf1600(state);
        data += KECCAK256_RATE;
        data_len -= KECCAK256_RATE;
    }

    uint8_t block[KECCAK256_RATE];
    memset(block, 0, sizeof(block));
    if (data_len > 0u) {
        memcpy(block, data, data_len);
    }
    block[data_len] ^= 0x01u;
    block[KECCAK256_RATE - 1u] ^= 0x80u;
    for (size_t i = 0; i < KECCAK256_RATE / 8u; i++) {
        state[i] ^= load_u64_le(block + (i * 8u));
    }
    keccakf1600(state);

    for (size_t i = 0; i < 4; i++) {
        store_u64_le(state[i], out_hash + (i * 8u));
    }
    return 0;
}

struct enr_rlp_slice {
    const uint8_t *data;
    size_t length;
};

struct enr_rlp_cursor {
    const uint8_t *data;
    size_t length;
    size_t offset;
};

struct enr_rlp_writer {
    uint8_t *data;
    size_t capacity;
    size_t offset;
};

static size_t rlp_be_size(size_t value) {
    size_t size = 1u;
    while (value > 0xffu) {
        value >>= 8u;
        ++size;
    }
    return size;
}

static size_t rlp_prefix_size(size_t length) {
    return length <= 55u ? 1u : 1u + rlp_be_size(length);
}

static int rlp_read_length(
    struct enr_rlp_cursor *cursor,
    size_t length_bytes,
    size_t *out_length) {
    if (!cursor || !out_length || length_bytes == 0u || length_bytes > sizeof(size_t)
        || cursor->offset > cursor->length
        || length_bytes > cursor->length - cursor->offset
        || cursor->data[cursor->offset] == 0u) {
        return -1;
    }
    size_t length = 0u;
    for (size_t i = 0; i < length_bytes; ++i) {
        if (length > (SIZE_MAX >> 8u)) {
            return -1;
        }
        length = (length << 8u) | cursor->data[cursor->offset + i];
    }
    cursor->offset += length_bytes;
    *out_length = length;
    return 0;
}

static int rlp_read_item(
    struct enr_rlp_cursor *cursor,
    bool expect_list,
    struct enr_rlp_slice *out) {
    if (!cursor || !out || cursor->offset >= cursor->length) {
        return -1;
    }

    uint8_t prefix = cursor->data[cursor->offset++];
    if (prefix <= 0x7fu) {
        if (expect_list) {
            return -1;
        }
        out->data = &cursor->data[cursor->offset - 1u];
        out->length = 1u;
        return 0;
    }

    bool is_list = prefix >= 0xc0u;
    if (is_list != expect_list) {
        return -1;
    }

    size_t payload_length = 0u;
    if (prefix <= 0xb7u) {
        payload_length = (size_t)(prefix - 0x80u);
    } else if (prefix <= 0xbfu) {
        if (rlp_read_length(cursor, (size_t)(prefix - 0xb7u), &payload_length) != 0
            || payload_length <= 55u) {
            return -1;
        }
    } else if (prefix <= 0xf7u) {
        payload_length = (size_t)(prefix - 0xc0u);
    } else if (rlp_read_length(cursor, (size_t)(prefix - 0xf7u), &payload_length) != 0
               || payload_length <= 55u) {
        return -1;
    }

    if (cursor->offset > cursor->length
        || payload_length > cursor->length - cursor->offset
        || (!is_list && payload_length == 1u && cursor->data[cursor->offset] <= 0x7fu)) {
        return -1;
    }
    out->data = cursor->data + cursor->offset;
    out->length = payload_length;
    cursor->offset += payload_length;
    return 0;
}

static int enr_key_compare(
    const uint8_t *left,
    size_t left_len,
    const uint8_t *right,
    size_t right_len) {
    size_t shared = left_len < right_len ? left_len : right_len;
    int order = shared > 0u ? memcmp(left, right, shared) : 0;
    if (order != 0) {
        return order;
    }
    return left_len < right_len ? -1 : left_len > right_len;
}

static size_t rlp_bytes_size(const uint8_t *data, size_t length) {
    if (length == 1u && data && data[0] <= 0x7fu) {
        return 1u;
    }
    size_t prefix = rlp_prefix_size(length);
    return length <= SIZE_MAX - prefix ? prefix + length : 0u;
}

static size_t uint64_to_be(uint64_t value, uint8_t out[8]) {
    if (value == 0u) {
        return 0u;
    }
    size_t length = 0u;
    while (value != 0u) {
        out[7u - length] = (uint8_t)value;
        value >>= 8u;
        ++length;
    }
    memmove(out, out + 8u - length, length);
    return length;
}

static int rlp_writer_append(
    struct enr_rlp_writer *writer,
    const uint8_t *data,
    size_t length) {
    if (!writer || (!data && length > 0u) || writer->offset > writer->capacity
        || length > writer->capacity - writer->offset) {
        return -1;
    }
    if (length > 0u) {
        memcpy(writer->data + writer->offset, data, length);
    }
    writer->offset += length;
    return 0;
}

static int rlp_writer_prefix(
    struct enr_rlp_writer *writer,
    size_t length,
    uint8_t short_base,
    uint8_t long_base) {
    uint8_t prefix[1u + sizeof(size_t)];
    size_t prefix_len = 1u;
    if (length <= 55u) {
        prefix[0] = (uint8_t)(short_base + length);
    } else {
        size_t length_bytes = rlp_be_size(length);
        prefix[0] = (uint8_t)(long_base + length_bytes);
        for (size_t i = 0; i < length_bytes; ++i) {
            prefix[1u + i] = (uint8_t)(length >> (8u * (length_bytes - i - 1u)));
        }
        prefix_len += length_bytes;
    }
    return rlp_writer_append(writer, prefix, prefix_len);
}

static int rlp_writer_bytes(
    struct enr_rlp_writer *writer,
    const uint8_t *data,
    size_t length) {
    if (length == 1u && data && data[0] <= 0x7fu) {
        return rlp_writer_append(writer, data, 1u);
    }
    return rlp_writer_prefix(writer, length, 0x80u, 0xb7u) == 0
        ? rlp_writer_append(writer, data, length)
        : -1;
}

static int add_rlp_bytes_size(
    size_t *total,
    const uint8_t *data,
    size_t length) {
    size_t encoded = rlp_bytes_size(data, length);
    if (!total || encoded == 0u || *total > SIZE_MAX - encoded) {
        return -1;
    }
    *total += encoded;
    return 0;
}

static int encode_record_rlp(
    const struct lantern_enr_record *record,
    const uint8_t *signature,
    size_t signature_len,
    uint8_t *out,
    size_t out_capacity,
    size_t *out_length) {
    if (!record || !out || !out_length || (!signature && signature_len > 0u)) {
        return -1;
    }

    uint8_t sequence[8];
    size_t sequence_len = uint64_to_be(record->sequence, sequence);
    size_t payload_len = 0u;
    if ((signature && add_rlp_bytes_size(&payload_len, signature, signature_len) != 0)
        || add_rlp_bytes_size(&payload_len, sequence, sequence_len) != 0) {
        return -1;
    }
    for (size_t i = 0; i < record->pair_count; ++i) {
        const struct lantern_enr_key_value *pair = &record->pairs[i];
        if (!pair->key || pair->key_len == 0u || (!pair->value && pair->value_len > 0u)
            || add_rlp_bytes_size(&payload_len, pair->key, pair->key_len) != 0
            || add_rlp_bytes_size(&payload_len, pair->value, pair->value_len) != 0) {
            return -1;
        }
    }

    size_t prefix_len = rlp_prefix_size(payload_len);
    if (payload_len > out_capacity || prefix_len > out_capacity - payload_len) {
        return -1;
    }
    struct enr_rlp_writer writer = {.data = out, .capacity = out_capacity, .offset = 0u};
    if (rlp_writer_prefix(&writer, payload_len, 0xc0u, 0xf7u) != 0
        || (signature && rlp_writer_bytes(&writer, signature, signature_len) != 0)
        || rlp_writer_bytes(&writer, sequence, sequence_len) != 0) {
        return -1;
    }
    for (size_t i = 0; i < record->pair_count; ++i) {
        const struct lantern_enr_key_value *pair = &record->pairs[i];
        if (rlp_writer_bytes(&writer, pair->key, pair->key_len) != 0
            || rlp_writer_bytes(&writer, pair->value, pair->value_len) != 0) {
            return -1;
        }
    }
    *out_length = writer.offset;
    return 0;
}

static int parse_record_rlp(struct lantern_enr_record *record) {
    if (!record || !record->rlp_bytes || record->rlp_len == 0u) {
        return -1;
    }
    struct enr_rlp_cursor root_cursor = {
        .data = record->rlp_bytes,
        .length = record->rlp_len,
        .offset = 0u,
    };
    struct enr_rlp_slice root;
    if (rlp_read_item(&root_cursor, true, &root) != 0
        || root_cursor.offset != root_cursor.length) {
        return -1;
    }

    struct enr_rlp_cursor items = {.data = root.data, .length = root.length, .offset = 0u};
    struct enr_rlp_slice item;
    size_t item_count = 0u;
    while (items.offset < items.length) {
        if (rlp_read_item(&items, false, &item) != 0) {
            return -1;
        }
        ++item_count;
    }
    if (item_count < 2u || ((item_count - 2u) % 2u) != 0u) {
        return -1;
    }

    items.offset = 0u;
    if (rlp_read_item(&items, false, &item) != 0
        || item.length != LANTERN_ENR_SIGNATURE_SIZE) {
        return -1;
    }
    record->signature = item.data;
    record->signature_len = item.length;

    if (rlp_read_item(&items, false, &item) != 0 || item.length > sizeof(uint64_t)) {
        return -1;
    }
    record->sequence = 0u;
    for (size_t i = 0; i < item.length; ++i) {
        record->sequence = (record->sequence << 8u) | item.data[i];
    }

    record->pair_count = (item_count - 2u) / 2u;
    if (record->pair_count > 0u) {
        record->pairs = calloc(record->pair_count, sizeof(*record->pairs));
        if (!record->pairs) {
            return -1;
        }
    }
    for (size_t i = 0; i < record->pair_count; ++i) {
        struct enr_rlp_slice key;
        struct enr_rlp_slice value;
        if (rlp_read_item(&items, false, &key) != 0 || key.length == 0u
            || rlp_read_item(&items, false, &value) != 0
            || (i > 0u
                && enr_key_compare(
                       record->pairs[i - 1u].key,
                       record->pairs[i - 1u].key_len,
                       key.data,
                       key.length)
                       >= 0)) {
            return -1;
        }
        record->pairs[i].key = key.data;
        record->pairs[i].key_len = key.length;
        record->pairs[i].value = value.length > 0u ? value.data : NULL;
        record->pairs[i].value_len = value.length;
    }
    return items.offset == items.length ? 0 : -1;
}

void lantern_enr_record_init(struct lantern_enr_record *record) {
    if (!record) {
        return;
    }
    *record = (struct lantern_enr_record){0};
}

void lantern_enr_record_reset(struct lantern_enr_record *record) {
    if (!record) {
        return;
    }
    free(record->encoded);
    free(record->rlp_bytes);
    free(record->pairs);
    *record = (struct lantern_enr_record){0};
}

void lantern_enr_record_list_init(struct lantern_enr_record_list *list) {
    if (!list) {
        return;
    }
    *list = (struct lantern_enr_record_list){0};
}

void lantern_enr_record_list_reset(struct lantern_enr_record_list *list) {
    if (!list) {
        return;
    }
    for (size_t i = 0; i < list->count; ++i) {
        lantern_enr_record_reset(&list->records[i]);
    }
    free(list->records);
    *list = (struct lantern_enr_record_list){0};
}

static int lantern_enr_record_list_reserve(struct lantern_enr_record_list *list, size_t new_capacity) {
    if (!list) {
        return -1;
    }
    if (new_capacity <= list->capacity) {
        return 0;
    }
    size_t adjusted = list->capacity == 0 ? 4 : list->capacity;
    while (adjusted < new_capacity) {
        adjusted *= 2;
    }

    struct lantern_enr_record *records = realloc(list->records, adjusted * sizeof(*records));
    if (!records) {
        return -1;
    }
    for (size_t i = list->capacity; i < adjusted; ++i) {
        lantern_enr_record_init(&records[i]);
    }
    list->records = records;
    list->capacity = adjusted;
    return 0;
}

int lantern_enr_record_decode(const char *enr_text, struct lantern_enr_record *record) {
    if (!enr_text || !record) {
        return -1;
    }

    struct lantern_enr_record temp;
    lantern_enr_record_init(&temp);

    while (isspace((unsigned char)*enr_text)) {
        ++enr_text;
    }

    if (strncmp(enr_text, "enr:", 4) != 0) {
        return -1;
    }
    const char *payload = enr_text + 4;
    size_t payload_len = strlen(payload);
    if (payload_len == 0u || payload_len > LANTERN_ENR_MAX_PAYLOAD_SIZE) {
        return -1;
    }

    temp.encoded = lantern_string_duplicate(enr_text);
    if (!temp.encoded) {
        return -1;
    }

    char prefixed[1u + LANTERN_ENR_MAX_PAYLOAD_SIZE];
    prefixed[0] = 'u';
    memcpy(prefixed + 1u, payload, payload_len);
    temp.rlp_bytes = malloc(LANTERN_ENR_MAX_SIZE);
    if (!temp.rlp_bytes) {
        goto error;
    }
    libp2p_multibase_t base = LIBP2P_MULTIBASE_BASE64URL;
    if (libp2p_multibase_decode(
            prefixed,
            payload_len + 1u,
            &base,
            temp.rlp_bytes,
            LANTERN_ENR_MAX_SIZE,
            &temp.rlp_len)
            != LIBP2P_MULTIBASE_OK
        || base != LIBP2P_MULTIBASE_BASE64URL
        || temp.rlp_len == 0u
        || parse_record_rlp(&temp) != 0) {
        goto error;
    }

    lantern_enr_record_reset(record);
    *record = temp;
    return 0;

error:
    lantern_enr_record_reset(&temp);
    return -1;
}

const struct lantern_enr_key_value *lantern_enr_record_find(const struct lantern_enr_record *record, const char *key) {
    if (!record || !key) {
        return NULL;
    }
    size_t key_len = strlen(key);
    for (size_t i = 0; i < record->pair_count; ++i) {
        if (record->pairs[i].key
            && record->pairs[i].key_len == key_len
            && memcmp(record->pairs[i].key, key, key_len) == 0) {
            return &record->pairs[i];
        }
    }
    return NULL;
}

static int parse_port_value(const struct lantern_enr_key_value *pair, uint16_t *out_port) {
    if (!pair || !out_port || !pair->value || pair->value_len != 2u) {
        return -1;
    }
    *out_port = (uint16_t)(((uint16_t)pair->value[0] << 8u) | (uint16_t)pair->value[1]);
    return 0;
}

static int parse_record_pubkey(
    const struct lantern_enr_record *record,
    secp256k1_context *ctx,
    secp256k1_pubkey *out_pubkey) {
    const struct lantern_enr_key_value *pubkey = lantern_enr_record_find(record, "secp256k1");
    if (!record || !ctx || !out_pubkey || !pubkey || !pubkey->value || pubkey->value_len != 33u) {
        return -1;
    }
    return secp256k1_ec_pubkey_parse(ctx, out_pubkey, pubkey->value, pubkey->value_len) ? 0 : -1;
}

int lantern_enr_record_signature_valid(const struct lantern_enr_record *record, bool *out_valid) {
    if (!record || !out_valid) {
        return -1;
    }
    *out_valid = false;
    if (!record->signature || record->signature_len != LANTERN_ENR_SIGNATURE_SIZE) {
        return 0;
    }

    uint8_t content[LANTERN_ENR_MAX_SIZE];
    size_t content_len = 0u;
    if (encode_record_rlp(record, NULL, 0u, content, sizeof(content), &content_len) != 0) {
        return -1;
    }

    uint8_t message_hash[32];
    if (keccak256_bytes(content, content_len, message_hash) != 0) {
        return -1;
    }

    secp256k1_context *ctx = secp256k1_context_create(SECP256K1_CONTEXT_VERIFY);
    if (!ctx) {
        return -1;
    }

    secp256k1_pubkey pubkey;
    secp256k1_ecdsa_signature signature;
    int rc = -1;
    if (parse_record_pubkey(record, ctx, &pubkey) == 0
        && secp256k1_ecdsa_signature_parse_compact(ctx, &signature, record->signature)) {
        secp256k1_ecdsa_signature normalized;
        secp256k1_ecdsa_signature_normalize(ctx, &normalized, &signature);
        *out_valid = secp256k1_ecdsa_verify(ctx, &normalized, message_hash, &pubkey) == 1;
        rc = 0;
    }

    secp256k1_context_destroy(ctx);
    return rc;
}

static bool key_pairs_are_sorted(const struct lantern_enr_record *record) {
    if (!record) {
        return false;
    }
    for (size_t i = 1u; i < record->pair_count; ++i) {
        if (!record->pairs[i - 1u].key || !record->pairs[i].key
            || enr_key_compare(
                   record->pairs[i - 1u].key,
                   record->pairs[i - 1u].key_len,
                   record->pairs[i].key,
                   record->pairs[i].key_len)
                   >= 0) {
            return false;
        }
    }
    return true;
}

bool lantern_enr_record_is_valid(const struct lantern_enr_record *record) {
    const struct lantern_enr_key_value *id = lantern_enr_record_find(record, "id");
    const struct lantern_enr_key_value *pubkey = lantern_enr_record_find(record, "secp256k1");
    return record
        && record->rlp_bytes
        && record->rlp_len > 0u
        && record->rlp_len <= LANTERN_ENR_MAX_SIZE
        && record->signature
        && record->signature_len == LANTERN_ENR_SIGNATURE_SIZE
        && id
        && id->value
        && id->value_len == 2u
        && memcmp(id->value, "v4", 2u) == 0
        && pubkey
        && pubkey->value
        && pubkey->value_len == 33u
        && key_pairs_are_sorted(record);
}

int lantern_enr_record_node_id(const struct lantern_enr_record *record, uint8_t out_node_id[32]) {
    if (!record || !out_node_id) {
        return -1;
    }

    secp256k1_context *ctx = secp256k1_context_create(SECP256K1_CONTEXT_VERIFY);
    if (!ctx) {
        return -1;
    }

    secp256k1_pubkey pubkey;
    unsigned char uncompressed[65];
    size_t uncompressed_len = sizeof(uncompressed);
    int rc = -1;
    if (parse_record_pubkey(record, ctx, &pubkey) == 0
        && secp256k1_ec_pubkey_serialize(
               ctx,
               uncompressed,
               &uncompressed_len,
               &pubkey,
               SECP256K1_EC_UNCOMPRESSED)
               && uncompressed_len == sizeof(uncompressed)
        && keccak256_bytes(uncompressed + 1u, sizeof(uncompressed) - 1u, out_node_id) == 0) {
        rc = 0;
    }

    secp256k1_context_destroy(ctx);
    return rc;
}

int lantern_enr_record_ip4(const struct lantern_enr_record *record, char *buffer, size_t buffer_len) {
    const struct lantern_enr_key_value *ip = lantern_enr_record_find(record, "ip");
    if (!record || !buffer || buffer_len == 0u || !ip || !ip->value || ip->value_len != 4u) {
        return -1;
    }

    return inet_ntop(AF_INET, ip->value, buffer, buffer_len) ? 0 : -1;
}

int lantern_enr_record_ip6(const struct lantern_enr_record *record, char *buffer, size_t buffer_len) {
    const struct lantern_enr_key_value *ip = lantern_enr_record_find(record, "ip6");
    if (!record || !buffer || buffer_len == 0u || !ip || !ip->value || ip->value_len != 16u) {
        return -1;
    }

    int written = snprintf(
        buffer,
        buffer_len,
        "%02x%02x:%02x%02x:%02x%02x:%02x%02x:%02x%02x:%02x%02x:%02x%02x:%02x%02x",
        ip->value[0],
        ip->value[1],
        ip->value[2],
        ip->value[3],
        ip->value[4],
        ip->value[5],
        ip->value[6],
        ip->value[7],
        ip->value[8],
        ip->value[9],
        ip->value[10],
        ip->value[11],
        ip->value[12],
        ip->value[13],
        ip->value[14],
        ip->value[15]);
    return written > 0 && (size_t)written < buffer_len ? 0 : -1;
}

int lantern_enr_record_multiaddr(const struct lantern_enr_record *record, char *buffer, size_t buffer_len) {
    if (!record || !buffer || buffer_len == 0u) {
        return -1;
    }

    const struct lantern_enr_key_value *ip4 = lantern_enr_record_find(record, "ip");
    const struct lantern_enr_key_value *ip6 = lantern_enr_record_find(record, "ip6");
    const struct lantern_enr_key_value *port = NULL;
    char ip_text[64];
    const char *prefix = NULL;

    if (ip4 && ip4->value && ip4->value_len == 4u) {
        port = lantern_enr_record_find(record, "quic");
        if (!port) {
            port = lantern_enr_record_find(record, "udp");
        }
        if (!port || lantern_enr_record_ip4(record, ip_text, sizeof(ip_text)) != 0) {
            return -1;
        }
        prefix = "/ip4";
    } else if (ip6 && ip6->value && ip6->value_len == 16u) {
        port = lantern_enr_record_find(record, "quic6");
        if (!port) {
            port = lantern_enr_record_find(record, "udp6");
        }
        if (!port) {
            port = lantern_enr_record_find(record, "quic");
        }
        if (!port) {
            port = lantern_enr_record_find(record, "udp");
        }
        if (!port || lantern_enr_record_ip6(record, ip_text, sizeof(ip_text)) != 0) {
            return -1;
        }
        prefix = "/ip6";
    } else {
        return -1;
    }

    uint16_t parsed_port = 0u;
    if (parse_port_value(port, &parsed_port) != 0) {
        return -1;
    }

    int written = snprintf(buffer, buffer_len, "%s/%s/udp/%u/quic-v1", prefix, ip_text, (unsigned)parsed_port);
    return written > 0 && (size_t)written < buffer_len ? 0 : -1;
}

int lantern_enr_record_eth2(const struct lantern_enr_record *record, struct lantern_enr_eth2_data *out_eth2) {
    const struct lantern_enr_key_value *eth2 = lantern_enr_record_find(record, "eth2");
    if (!record || !out_eth2 || !eth2 || !eth2->value || eth2->value_len < 16u) {
        return -1;
    }

    memcpy(out_eth2->fork_digest, eth2->value, 4u);
    memcpy(out_eth2->next_fork_version, eth2->value + 4u, 4u);
    out_eth2->next_fork_epoch =
        (uint64_t)eth2->value[8]
        | ((uint64_t)eth2->value[9] << 8u)
        | ((uint64_t)eth2->value[10] << 16u)
        | ((uint64_t)eth2->value[11] << 24u)
        | ((uint64_t)eth2->value[12] << 32u)
        | ((uint64_t)eth2->value[13] << 40u)
        | ((uint64_t)eth2->value[14] << 48u)
        | ((uint64_t)eth2->value[15] << 56u);
    return 0;
}

bool lantern_enr_record_is_aggregator(const struct lantern_enr_record *record) {
    const struct lantern_enr_key_value *pair = lantern_enr_record_find(record, "is_aggregator");
    return pair && pair->value && pair->value_len == 1u && pair->value[0] == 0x01u;
}

int lantern_enr_record_list_append(struct lantern_enr_record_list *list, const char *enr_text) {
    if (!list || !enr_text) {
        return -1;
    }
    if (lantern_enr_record_list_reserve(list, list->count + 1) != 0) {
        return -1;
    }

    struct lantern_enr_record *record = &list->records[list->count];
    if (lantern_enr_record_decode(enr_text, record) != 0) {
        lantern_enr_record_reset(record);
        return -1;
    }
    list->count++;
    return 0;
}

static int parse_ipv4_address(const char *ip_string, uint8_t out[4]) {
    if (!ip_string || !out) {
        return -1;
    }

#if defined(_WIN32)
    struct in_addr addr;
    if (InetPtonA(AF_INET, ip_string, &addr) != 1) {
        return -1;
    }
#else
    struct in_addr addr;
    if (inet_pton(AF_INET, ip_string, &addr) != 1) {
        return -1;
    }
#endif

    memcpy(out, &addr, sizeof(addr));
    return 0;
}

int lantern_enr_record_build_v4(
    struct lantern_enr_record *record,
    const uint8_t private_key[32],
    const char *ip_string,
    uint16_t udp_port,
    uint64_t sequence,
    bool is_aggregator) {
    if (!record || !private_key || !ip_string) {
        lantern_log_error("enr", NULL, "ENR build missing inputs");
        return -1;
    }

    const char *error_reason = NULL;
    secp256k1_context *ctx = NULL;
    char *enr_text = NULL;

    uint8_t ip_bytes[4];
    if (parse_ipv4_address(ip_string, ip_bytes) != 0) {
        error_reason = "invalid IPv4 address";
        goto error;
    }

    ctx = secp256k1_context_create(SECP256K1_CONTEXT_SIGN);
    if (!ctx) {
        error_reason = "secp256k1 context create failed";
        goto error;
    }

    secp256k1_pubkey pubkey;
    if (!secp256k1_ec_pubkey_create(ctx, &pubkey, private_key)) {
        error_reason = "secp256k1 pubkey create failed";
        goto error;
    }

    unsigned char pubkey_compressed[33];
    size_t pubkey_len = sizeof(pubkey_compressed);
    if (!secp256k1_ec_pubkey_serialize(
            ctx,
            pubkey_compressed,
            &pubkey_len,
            &pubkey,
            SECP256K1_EC_COMPRESSED)) {
        error_reason = "secp256k1 pubkey serialize failed";
        goto error;
    }

    static const uint8_t id_key[] = "id";
    static const uint8_t id_value[] = "v4";
    static const uint8_t ip_key[] = "ip";
    static const uint8_t aggregator_key[] = "is_aggregator";
    static const uint8_t aggregator_value[] = {0x01u};
    static const uint8_t secp_key[] = "secp256k1";
    static const uint8_t udp_key[] = "udp";
    uint8_t udp_bytes[2] = {(uint8_t)(udp_port >> 8u), (uint8_t)udp_port};
    struct lantern_enr_key_value pairs[5];
    size_t pair_count = 0u;
    pairs[pair_count++] = (struct lantern_enr_key_value){
        .key = id_key,
        .key_len = sizeof(id_key) - 1u,
        .value = id_value,
        .value_len = sizeof(id_value) - 1u,
    };
    pairs[pair_count++] = (struct lantern_enr_key_value){
        .key = ip_key,
        .key_len = sizeof(ip_key) - 1u,
        .value = ip_bytes,
        .value_len = sizeof(ip_bytes),
    };
    if (is_aggregator) {
        pairs[pair_count++] = (struct lantern_enr_key_value){
            .key = aggregator_key,
            .key_len = sizeof(aggregator_key) - 1u,
            .value = aggregator_value,
            .value_len = sizeof(aggregator_value),
        };
    }
    pairs[pair_count++] = (struct lantern_enr_key_value){
        .key = secp_key,
        .key_len = sizeof(secp_key) - 1u,
        .value = pubkey_compressed,
        .value_len = pubkey_len,
    };
    pairs[pair_count++] = (struct lantern_enr_key_value){
        .key = udp_key,
        .key_len = sizeof(udp_key) - 1u,
        .value = udp_bytes,
        .value_len = sizeof(udp_bytes),
    };
    struct lantern_enr_record unsigned_record = {
        .sequence = sequence,
        .pairs = pairs,
        .pair_count = pair_count,
    };
    uint8_t content[LANTERN_ENR_MAX_SIZE];
    size_t content_len = 0u;
    if (encode_record_rlp(
            &unsigned_record,
            NULL,
            0u,
            content,
            sizeof(content),
            &content_len)
        != 0) {
        error_reason = "rlp encode content failed";
        goto error;
    }

    uint8_t message_hash[32];
    if (keccak256_bytes(content, content_len, message_hash) != 0) {
        error_reason = "keccak failed";
        goto error;
    }

    secp256k1_ecdsa_signature signature;
    if (!secp256k1_ecdsa_sign(ctx, &signature, message_hash, private_key, NULL, NULL)) {
        error_reason = "secp256k1 sign failed";
        goto error;
    }
    unsigned char sig_bytes[64];
    if (!secp256k1_ecdsa_signature_serialize_compact(ctx, sig_bytes, &signature)) {
        error_reason = "secp256k1 signature serialize failed";
        goto error;
    }

    uint8_t signed_record[LANTERN_ENR_MAX_SIZE];
    size_t signed_len = 0u;
    if (encode_record_rlp(
            &unsigned_record,
            sig_bytes,
            sizeof(sig_bytes),
            signed_record,
            sizeof(signed_record),
            &signed_len)
        != 0) {
        error_reason = "rlp encode signed record failed";
        goto error;
    }

    size_t encoded_capacity = 0u;
    if (libp2p_multibase_encoded_size(
            LIBP2P_MULTIBASE_BASE64URL,
            signed_len,
            &encoded_capacity)
        != LIBP2P_MULTIBASE_OK) {
        error_reason = "base64url size failed";
        goto error;
    }
    enr_text = malloc(3u + encoded_capacity + 1u);
    if (!enr_text) {
        error_reason = "enr text alloc failed";
        goto error;
    }
    size_t written = 0;
    if (libp2p_multibase_encode(
            LIBP2P_MULTIBASE_BASE64URL,
            signed_record,
            signed_len,
            enr_text + 3u,
            encoded_capacity,
            &written)
            != LIBP2P_MULTIBASE_OK
        || written == 0u
        || enr_text[3] != 'u') {
        error_reason = "base64url encode failed";
        goto error;
    }
    memcpy(enr_text, "enr:", 4);
    enr_text[3u + written] = '\0';

    if (lantern_enr_record_decode(enr_text, record) != 0) {
        error_reason = "decode sanity check failed";
        goto error;
    }
    free(enr_text);
    secp256k1_context_destroy(ctx);
    return 0;

error:
    free(enr_text);
    if (ctx) {
        secp256k1_context_destroy(ctx);
    }
    if (error_reason) {
        lantern_log_error("enr", NULL, "ENR build error: %s", error_reason);
    }
    return -1;
}
