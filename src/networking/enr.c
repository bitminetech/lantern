#include "lantern/networking/enr.h"

#include "lantern/encoding/rlp.h"
#include "lantern/support/log.h"
#include "lantern/support/strings.h"
#include "multiformats/multibase/encoding/base64_url.h"
#include "tomcrypt.h"

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

void lantern_enr_record_init(struct lantern_enr_record *record) {
    if (!record) {
        return;
    }
    record->encoded = NULL;
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

    uint8_t *decoded = malloc(input_len);
    if (!decoded) {
        return -1;
    }

    int written = multibase_base64_url_decode(input, input_len, decoded, input_len);
    if (written < 0) {
        free(decoded);
        return -1;
    }

    *out_bytes = decoded;
    *out_len = (size_t)written;
    return 0;
}

static int copy_signature(struct lantern_enr_record *record, const struct lantern_rlp_view *signature) {
    if (!record || !signature || signature->kind != LANTERN_RLP_KIND_BYTES || signature->length == 0) {
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
        if (key_view->kind != LANTERN_RLP_KIND_BYTES || key_view->length == 0) {
            goto error;
        }
        char *key = lantern_string_duplicate_len((const char *)key_view->data, key_view->length);
        if (!key) {
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

    uint8_t *encoded_bytes = NULL;
    size_t encoded_len = 0;
    if (lantern_base64url_decode(payload, &encoded_bytes, &encoded_len) != 0) {
        goto error;
    }

    struct lantern_rlp_view root;
    memset(&root, 0, sizeof(root));
    int root_ready = 0;
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
    uint64_t sequence) {
    if (!record || !private_key || !ip_string) {
        lantern_log_error("enr", NULL, "ENR build missing inputs");
        return -1;
    }

    const char *error_reason = NULL;

    struct lantern_rlp_buffer items[9];
    memset(items, 0, sizeof(items));
    struct lantern_rlp_buffer signed_record = {0};
    struct lantern_rlp_buffer content = {0};
    struct lantern_rlp_buffer signature_buf = {0};

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

    size_t idx = 0;
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
    const struct ltc_hash_descriptor *keccak_desc = &keccak_256_desc;
    hash_state keccak_state;
    int hash_rc = keccak_desc->init(&keccak_state);
    if (hash_rc != CRYPT_OK) {
        lantern_log_error("enr", NULL, "keccak init rc=%d", hash_rc);
        error_reason = "keccak init failed";
        goto error;
    }
    if (content.length > 0
        && keccak_desc->process(&keccak_state, content.data, (unsigned long)content.length) != CRYPT_OK) {
        error_reason = "keccak absorb failed";
        goto error;
    }
    if (keccak_desc->done(&keccak_state, message_hash) != CRYPT_OK) {
        error_reason = "keccak finalize failed";
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

    struct lantern_rlp_buffer record_items[10];
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
    int written = multibase_base64_url_encode(
        signed_record.data,
        signed_record.length,
        payload,
        encoded_capacity);
    if (written < 0) {
        free(payload);
        error_reason = "base64url encode failed";
        goto error;
    }
    payload[written] = '\0';

    size_t enr_len = (size_t)written + 5;
    char *enr_text = malloc(enr_len);
    if (!enr_text) {
        free(payload);
        error_reason = "enr text alloc failed";
        goto error;
    }
    memcpy(enr_text, "enr:", 4);
    memcpy(enr_text + 4, payload, (size_t)written + 1);
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
