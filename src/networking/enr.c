#include "lantern/networking/enr.h"

#include "lantern/encoding/rlp.h"
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

#define LANTERN_ENR_SIGNATURE_SIZE 64u
#define LANTERN_ENR_MAX_SIZE 300u

static const char LANTERN_BASE64URL_ALPHABET[] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

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

static int base64url_value(char ch) {
    if (ch >= 'A' && ch <= 'Z') {
        return ch - 'A';
    }
    if (ch >= 'a' && ch <= 'z') {
        return 26 + (ch - 'a');
    }
    if (ch >= '0' && ch <= '9') {
        return 52 + (ch - '0');
    }
    if (ch == '-') {
        return 62;
    }
    if (ch == '_') {
        return 63;
    }
    return -1;
}

static int base64url_encode(
    const uint8_t *input,
    size_t input_len,
    char *out,
    size_t out_len,
    size_t *written) {
    if ((!input && input_len > 0u) || !out || !written) {
        return -1;
    }
    size_t full_groups = input_len / 3u;
    size_t remainder = input_len % 3u;
    size_t required = (full_groups * 4u) + (remainder == 0u ? 0u : remainder + 1u);
    if (out_len <= required) {
        return -1;
    }

    size_t in_pos = 0;
    size_t out_pos = 0;
    for (size_t i = 0; i < full_groups; i++) {
        uint32_t value =
            ((uint32_t)input[in_pos] << 16u) |
            ((uint32_t)input[in_pos + 1u] << 8u) |
            (uint32_t)input[in_pos + 2u];
        in_pos += 3u;
        out[out_pos++] = LANTERN_BASE64URL_ALPHABET[(value >> 18u) & 0x3fu];
        out[out_pos++] = LANTERN_BASE64URL_ALPHABET[(value >> 12u) & 0x3fu];
        out[out_pos++] = LANTERN_BASE64URL_ALPHABET[(value >> 6u) & 0x3fu];
        out[out_pos++] = LANTERN_BASE64URL_ALPHABET[value & 0x3fu];
    }
    if (remainder == 1u) {
        uint32_t value = (uint32_t)input[in_pos] << 16u;
        out[out_pos++] = LANTERN_BASE64URL_ALPHABET[(value >> 18u) & 0x3fu];
        out[out_pos++] = LANTERN_BASE64URL_ALPHABET[(value >> 12u) & 0x3fu];
    } else if (remainder == 2u) {
        uint32_t value = ((uint32_t)input[in_pos] << 16u) | ((uint32_t)input[in_pos + 1u] << 8u);
        out[out_pos++] = LANTERN_BASE64URL_ALPHABET[(value >> 18u) & 0x3fu];
        out[out_pos++] = LANTERN_BASE64URL_ALPHABET[(value >> 12u) & 0x3fu];
        out[out_pos++] = LANTERN_BASE64URL_ALPHABET[(value >> 6u) & 0x3fu];
    }
    out[out_pos] = '\0';
    *written = out_pos;
    return 0;
}

static void lantern_enr_key_value_reset(struct lantern_enr_key_value *pair) {
    if (!pair) {
        return;
    }
    free(pair->key);
    pair->key = NULL;
    free(pair->value);
    pair->value = NULL;
    pair->value_len = 0;
}

static void reset_rlp_buffers(struct lantern_rlp_buffer *buffers, size_t count);

void lantern_enr_record_init(struct lantern_enr_record *record) {
    if (!record) {
        return;
    }
    record->encoded = NULL;
    record->rlp_bytes = NULL;
    record->rlp_len = 0u;
    record->signature = NULL;
    record->signature_len = 0;
    record->sequence = 0;
    record->pairs = NULL;
    record->pair_count = 0;
}

void lantern_enr_record_reset(struct lantern_enr_record *record) {
    if (!record) {
        return;
    }
    free(record->encoded);
    record->encoded = NULL;
    free(record->rlp_bytes);
    record->rlp_bytes = NULL;
    record->rlp_len = 0u;
    free(record->signature);
    record->signature = NULL;
    record->signature_len = 0;
    record->sequence = 0;
    if (record->pairs) {
        for (size_t i = 0; i < record->pair_count; ++i) {
            lantern_enr_key_value_reset(&record->pairs[i]);
        }
        free(record->pairs);
    }
    record->pairs = NULL;
    record->pair_count = 0;
}

void lantern_enr_record_list_init(struct lantern_enr_record_list *list) {
    if (!list) {
        return;
    }
    list->records = NULL;
    list->count = 0;
    list->capacity = 0;
}

void lantern_enr_record_list_reset(struct lantern_enr_record_list *list) {
    if (!list) {
        return;
    }
    if (list->records) {
        for (size_t i = 0; i < list->count; ++i) {
            lantern_enr_record_reset(&list->records[i]);
        }
        free(list->records);
    }
    list->records = NULL;
    list->count = 0;
    list->capacity = 0;
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

static int lantern_base64url_decode(const char *input, uint8_t **out_bytes, size_t *out_len) {
    if (!input || !out_bytes || !out_len) {
        return -1;
    }
    size_t input_len = strlen(input);
    if (input_len == 0) {
        return -1;
    }

    if ((input_len % 4u) == 1u) {
        return -1;
    }

    uint8_t *decoded = malloc(input_len);
    if (!decoded) {
        return -1;
    }

    size_t out_pos = 0;
    size_t in_pos = 0;
    while (input_len - in_pos >= 4u) {
        int a = base64url_value(input[in_pos++]);
        int b = base64url_value(input[in_pos++]);
        int c = base64url_value(input[in_pos++]);
        int d = base64url_value(input[in_pos++]);
        if (a < 0 || b < 0 || c < 0 || d < 0) {
            free(decoded);
            return -1;
        }
        uint32_t value =
            ((uint32_t)a << 18u) | ((uint32_t)b << 12u) | ((uint32_t)c << 6u) | (uint32_t)d;
        decoded[out_pos++] = (uint8_t)((value >> 16u) & 0xffu);
        decoded[out_pos++] = (uint8_t)((value >> 8u) & 0xffu);
        decoded[out_pos++] = (uint8_t)(value & 0xffu);
    }

    size_t rem = input_len - in_pos;
    if (rem == 2u) {
        int a = base64url_value(input[in_pos]);
        int b = base64url_value(input[in_pos + 1u]);
        if (a < 0 || b < 0) {
            free(decoded);
            return -1;
        }
        uint32_t value = ((uint32_t)a << 18u) | ((uint32_t)b << 12u);
        decoded[out_pos++] = (uint8_t)((value >> 16u) & 0xffu);
    } else if (rem == 3u) {
        int a = base64url_value(input[in_pos]);
        int b = base64url_value(input[in_pos + 1u]);
        int c = base64url_value(input[in_pos + 2u]);
        if (a < 0 || b < 0 || c < 0) {
            free(decoded);
            return -1;
        }
        uint32_t value = ((uint32_t)a << 18u) | ((uint32_t)b << 12u) | ((uint32_t)c << 6u);
        decoded[out_pos++] = (uint8_t)((value >> 16u) & 0xffu);
        decoded[out_pos++] = (uint8_t)((value >> 8u) & 0xffu);
    }

    *out_bytes = decoded;
    *out_len = out_pos;
    return 0;
}

static int copy_signature(struct lantern_enr_record *record, const struct lantern_rlp_view *signature) {
    if (!record || !signature || signature->kind != LANTERN_RLP_KIND_BYTES
        || signature->length != LANTERN_ENR_SIGNATURE_SIZE) {
        return -1;
    }
    uint8_t *copy = malloc(signature->length);
    if (!copy) {
        return -1;
    }
    memcpy(copy, signature->data, signature->length);
    record->signature = copy;
    record->signature_len = signature->length;
    return 0;
}

static int copy_pairs(struct lantern_enr_record *record, const struct lantern_rlp_view *items, size_t item_count) {
    if (!record || !items || item_count < 2 || ((item_count - 2) % 2) != 0) {
        return -1;
    }

    size_t pair_count = (item_count - 2) / 2;
    if (pair_count == 0) {
        record->pairs = NULL;
        record->pair_count = 0;
        return 0;
    }

    struct lantern_enr_key_value *pairs = calloc(pair_count, sizeof(*pairs));
    if (!pairs) {
        return -1;
    }

    size_t pair_index = 0;
    for (size_t i = 2; i < item_count; i += 2) {
        const struct lantern_rlp_view *key_view = &items[i];
        const struct lantern_rlp_view *value_view = &items[i + 1];
        if (key_view->kind != LANTERN_RLP_KIND_BYTES || key_view->length == 0
            || value_view->kind != LANTERN_RLP_KIND_BYTES) {
            goto error;
        }
        char *key = lantern_string_duplicate_len((const char *)key_view->data, key_view->length);
        if (!key) {
            goto error;
        }
        if (pair_index > 0 && strcmp(pairs[pair_index - 1].key, key) >= 0) {
            free(key);
            goto error;
        }
        uint8_t *value = NULL;
        if (value_view->length > 0) {
            value = malloc(value_view->length);
            if (!value) {
                free(key);
                goto error;
            }
            memcpy(value, value_view->data, value_view->length);
        }

        pairs[pair_index].key = key;
        pairs[pair_index].value = value;
        pairs[pair_index].value_len = value_view->length;
        pair_index++;
    }

    record->pairs = pairs;
    record->pair_count = pair_count;
    return 0;

error:
    for (size_t j = 0; j < pair_count; ++j) {
        lantern_enr_key_value_reset(&pairs[j]);
    }
    free(pairs);
    return -1;
}

static int copy_rlp_bytes(struct lantern_enr_record *record, const uint8_t *encoded_bytes, size_t encoded_len) {
    if (!record) {
        return -1;
    }
    record->rlp_bytes = NULL;
    record->rlp_len = 0u;
    if (encoded_len == 0u) {
        return 0;
    }
    uint8_t *copy = malloc(encoded_len);
    if (!copy) {
        return -1;
    }
    memcpy(copy, encoded_bytes, encoded_len);
    record->rlp_bytes = copy;
    record->rlp_len = encoded_len;
    return 0;
}

static bool key_pairs_are_sorted(const struct lantern_enr_record *record) {
    if (!record) {
        return false;
    }
    for (size_t i = 1; i < record->pair_count; ++i) {
        const char *prev = record->pairs[i - 1u].key;
        const char *curr = record->pairs[i].key;
        if (!prev || !curr || strcmp(prev, curr) >= 0) {
            return false;
        }
    }
    return true;
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
    if (*payload == '\0') {
        return -1;
    }

    temp.encoded = lantern_string_duplicate(enr_text);
    if (!temp.encoded) {
        return -1;
    }

    struct lantern_rlp_view root;
    memset(&root, 0, sizeof(root));
    int root_ready = 0;
    uint8_t *encoded_bytes = NULL;
    size_t encoded_len = 0;
    if (lantern_base64url_decode(payload, &encoded_bytes, &encoded_len) != 0) {
        goto error;
    }
    if (encoded_len > LANTERN_ENR_MAX_SIZE) {
        goto error;
    }
    if (copy_rlp_bytes(&temp, encoded_bytes, encoded_len) != 0) {
        goto error;
    }

    if (lantern_rlp_decode(encoded_bytes, encoded_len, &root) != 0) {
        goto error;
    }
    root_ready = 1;

    if (root.kind != LANTERN_RLP_KIND_LIST || root.item_count < 2 || ((root.item_count - 2) % 2) != 0) {
        goto error;
    }

    if (copy_signature(&temp, &root.items[0]) != 0) {
        goto error;
    }

    if (lantern_rlp_view_as_uint64(&root.items[1], &temp.sequence) != 0) {
        goto error;
    }

    if (copy_pairs(&temp, root.items, root.item_count) != 0) {
        goto error;
    }

    lantern_rlp_view_reset(&root);
    root_ready = 0;
    free(encoded_bytes);
    encoded_bytes = NULL;
    lantern_enr_record_reset(record);
    *record = temp;
    return 0;

error:
    if (root_ready) {
        lantern_rlp_view_reset(&root);
    }
    free(encoded_bytes);
    lantern_enr_record_reset(&temp);
    return -1;
}

const struct lantern_enr_key_value *lantern_enr_record_find(const struct lantern_enr_record *record, const char *key) {
    if (!record || !key) {
        return NULL;
    }
    for (size_t i = 0; i < record->pair_count; ++i) {
        if (record->pairs[i].key && strcmp(record->pairs[i].key, key) == 0) {
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

static int encode_record_content(
    const struct lantern_enr_record *record,
    struct lantern_rlp_buffer *out_content) {
    if (!record || !out_content) {
        return -1;
    }
    memset(out_content, 0, sizeof(*out_content));

    size_t item_count = 1u + (record->pair_count * 2u);
    struct lantern_rlp_buffer *items = calloc(item_count, sizeof(*items));
    if (!items) {
        return -1;
    }

    int rc = -1;
    size_t idx = 0u;
    if (lantern_rlp_encode_uint64(&items[idx++], record->sequence) != 0) {
        goto cleanup;
    }
    for (size_t i = 0; i < record->pair_count; ++i) {
        const struct lantern_enr_key_value *pair = &record->pairs[i];
        static const uint8_t kEmptyValue = 0u;
        const uint8_t *value = pair->value_len > 0u ? pair->value : &kEmptyValue;
        if (!pair->key
            || lantern_rlp_encode_bytes(&items[idx++], (const uint8_t *)pair->key, strlen(pair->key)) != 0
            || lantern_rlp_encode_bytes(&items[idx++], value, pair->value_len) != 0) {
            goto cleanup;
        }
    }

    rc = lantern_rlp_encode_list(out_content, items, idx);

cleanup:
    reset_rlp_buffers(items, item_count);
    free(items);
    return rc;
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

int lantern_enr_record_verify_signature(const struct lantern_enr_record *record, bool *out_valid) {
    if (!record || !out_valid) {
        return -1;
    }
    *out_valid = false;
    if (!record->signature || record->signature_len != LANTERN_ENR_SIGNATURE_SIZE) {
        return 0;
    }

    struct lantern_rlp_buffer content = {0};
    if (encode_record_content(record, &content) != 0) {
        lantern_rlp_buffer_reset(&content);
        return -1;
    }

    uint8_t message_hash[32];
    if (keccak256_bytes(content.data, content.length, message_hash) != 0) {
        lantern_rlp_buffer_reset(&content);
        return -1;
    }
    lantern_rlp_buffer_reset(&content);

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

int lantern_enr_record_signature_valid(const struct lantern_enr_record *record, bool *out_valid) {
    return lantern_enr_record_verify_signature(record, out_valid);
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

static void reset_rlp_buffers(struct lantern_rlp_buffer *buffers, size_t count) {
    if (!buffers) {
        return;
    }
    for (size_t i = 0; i < count; ++i) {
        lantern_rlp_buffer_reset(&buffers[i]);
    }
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

    struct lantern_rlp_buffer items[11];
    memset(items, 0, sizeof(items));
    struct lantern_rlp_buffer signed_record = {0};
    struct lantern_rlp_buffer content = {0};
    struct lantern_rlp_buffer signature_buf = {0};
    size_t idx = 0;

    uint8_t ip_bytes[4];
    if (parse_ipv4_address(ip_string, ip_bytes) != 0) {
        error_reason = "invalid IPv4 address";
        goto error;
    }

    secp256k1_context *ctx = secp256k1_context_create(SECP256K1_CONTEXT_SIGN);
    if (!ctx) {
        error_reason = "secp256k1 context create failed";
        goto error;
    }

    secp256k1_pubkey pubkey;
    if (!secp256k1_ec_pubkey_create(ctx, &pubkey, private_key)) {
        secp256k1_context_destroy(ctx);
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
        secp256k1_context_destroy(ctx);
        error_reason = "secp256k1 pubkey serialize failed";
        goto error;
    }
    secp256k1_context_destroy(ctx);

    if (lantern_rlp_encode_uint64(&items[idx++], sequence) != 0) {
        error_reason = "rlp encode sequence failed";
        goto error;
    }
    if (lantern_rlp_encode_bytes(&items[idx++], (const uint8_t *)"id", 2) != 0) {
        error_reason = "rlp encode id key failed";
        goto error;
    }
    if (lantern_rlp_encode_bytes(&items[idx++], (const uint8_t *)"v4", 2) != 0) {
        error_reason = "rlp encode id value failed";
        goto error;
    }
    if (lantern_rlp_encode_bytes(&items[idx++], (const uint8_t *)"ip", 2) != 0) {
        error_reason = "rlp encode ip key failed";
        goto error;
    }
    if (lantern_rlp_encode_bytes(&items[idx++], ip_bytes, sizeof(ip_bytes)) != 0) {
        error_reason = "rlp encode ip value failed";
        goto error;
    }
    if (is_aggregator) {
        static const uint8_t aggregator_key[] = "is_aggregator";
        static const uint8_t aggregator_value[] = {0x01};
        if (lantern_rlp_encode_bytes(&items[idx++], aggregator_key, sizeof(aggregator_key) - 1u) != 0) {
            error_reason = "rlp encode is_aggregator key failed";
            goto error;
        }
        if (lantern_rlp_encode_bytes(&items[idx++], aggregator_value, sizeof(aggregator_value)) != 0) {
            error_reason = "rlp encode is_aggregator value failed";
            goto error;
        }
    }
    if (lantern_rlp_encode_bytes(&items[idx++], (const uint8_t *)"secp256k1", 9) != 0) {
        error_reason = "rlp encode key type failed";
        goto error;
    }
    if (lantern_rlp_encode_bytes(&items[idx++], pubkey_compressed, pubkey_len) != 0) {
        error_reason = "rlp encode pubkey failed";
        goto error;
    }
    if (lantern_rlp_encode_bytes(&items[idx++], (const uint8_t *)"udp", 3) != 0) {
        error_reason = "rlp encode udp key failed";
        goto error;
    }
    uint8_t udp_bytes[2] = {(uint8_t)(udp_port >> 8), (uint8_t)(udp_port & 0xFF)};
    if (lantern_rlp_encode_bytes(&items[idx++], udp_bytes, sizeof(udp_bytes)) != 0) {
        error_reason = "rlp encode udp value failed";
        goto error;
    }
    if (lantern_rlp_encode_list(&content, items, idx) != 0) {
        error_reason = "rlp encode content failed";
        goto error;
    }

    uint8_t message_hash[32];
    if (keccak256_bytes(content.data, content.length, message_hash) != 0) {
        error_reason = "keccak failed";
        goto error;
    }

    secp256k1_context *sign_ctx = secp256k1_context_create(SECP256K1_CONTEXT_SIGN);
    if (!sign_ctx) {
        error_reason = "secp256k1 sign context failed";
        goto error;
    }
    secp256k1_ecdsa_signature signature;
    if (!secp256k1_ecdsa_sign(sign_ctx, &signature, message_hash, private_key, NULL, NULL)) {
        secp256k1_context_destroy(sign_ctx);
        error_reason = "secp256k1 sign failed";
        goto error;
    }
    unsigned char sig_bytes[64];
    if (!secp256k1_ecdsa_signature_serialize_compact(sign_ctx, sig_bytes, &signature)) {
        secp256k1_context_destroy(sign_ctx);
        error_reason = "secp256k1 signature serialize failed";
        goto error;
    }
    secp256k1_context_destroy(sign_ctx);

    if (lantern_rlp_encode_bytes(&signature_buf, sig_bytes, sizeof(sig_bytes)) != 0) {
        error_reason = "rlp encode signature failed";
        goto error;
    }

    struct lantern_rlp_buffer record_items[12];
    record_items[0] = signature_buf;
    for (size_t i = 0; i < idx; ++i) {
        record_items[i + 1] = items[i];
    }
    if (lantern_rlp_encode_list(&signed_record, record_items, idx + 1) != 0) {
        error_reason = "rlp encode signed record failed";
        goto error;
    }

    size_t encoded_capacity = ((signed_record.length * 4) + 2) / 3 + 1;
    char *payload = malloc(encoded_capacity);
    if (!payload) {
        error_reason = "payload alloc failed";
        goto error;
    }
    size_t written = 0;
    if (base64url_encode(
        signed_record.data,
        signed_record.length,
        payload,
        encoded_capacity,
        &written) != 0) {
        free(payload);
        error_reason = "base64url encode failed";
        goto error;
    }

    size_t enr_len = written + 5;
    char *enr_text = malloc(enr_len);
    if (!enr_text) {
        free(payload);
        error_reason = "enr text alloc failed";
        goto error;
    }
    memcpy(enr_text, "enr:", 4);
    memcpy(enr_text + 4, payload, written + 1u);
    free(payload);

    if (lantern_enr_record_decode(enr_text, record) != 0) {
        free(enr_text);
        error_reason = "decode sanity check failed";
        goto error;
    }
    free(enr_text);

    reset_rlp_buffers(items, idx);
    lantern_rlp_buffer_reset(&signature_buf);
    lantern_rlp_buffer_reset(&content);
    lantern_rlp_buffer_reset(&signed_record);
    return 0;

error:
    reset_rlp_buffers(items, idx);
    lantern_rlp_buffer_reset(&signature_buf);
    lantern_rlp_buffer_reset(&content);
    lantern_rlp_buffer_reset(&signed_record);
    if (error_reason) {
        lantern_log_error("enr", NULL, "ENR build error: %s", error_reason);
    }
    return -1;
}
