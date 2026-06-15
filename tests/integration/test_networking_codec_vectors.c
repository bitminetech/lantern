#include "tests/support/fixture_loader.h"

#include <dirent.h>
#include <errno.h>
#include <inttypes.h>
#include <limits.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#include "lantern/encoding/snappy.h"
#include "lantern/networking/enr.h"
#include "lantern/networking/gossip.h"
#include "lantern/networking/libp2p.h"
#include "lantern/networking/messages.h"
#include "multiformats/multibase/multibase.h"
#include "multiformats/unsigned_varint/unsigned_varint.h"
#include "peer_id/peer_id.h"
#include "protocol/gossipsub/gossipsub.h"

#ifndef LANTERN_CONSENSUS_FIXTURE_DIR
#define LANTERN_CONSENSUS_FIXTURE_DIR "tools/leanSpec/fixtures/consensus"
#endif

#define NETWORKING_CODEC_FIXTURE_SUBDIR "networking_codec/lstar/networking"
#define BUFFER_PREVIEW_BYTES 32u
#define FIXTURE_SKIPPED 1

struct fixture_stats {
    size_t total;
    size_t passed;
    size_t failed;
    size_t unsupported;
};

struct byte_buffer {
    uint8_t *data;
    size_t len;
};

static void byte_buffer_reset(struct byte_buffer *buffer) {
    if (!buffer) {
        return;
    }
    free(buffer->data);
    buffer->data = NULL;
    buffer->len = 0;
}

static int byte_buffer_append(struct byte_buffer *buffer, const uint8_t *data, size_t len) {
    if (!buffer || (!data && len > 0u)) {
        return -1;
    }
    if (len == 0u) {
        return 0;
    }
    if (buffer->len > SIZE_MAX - len) {
        return -1;
    }
    uint8_t *expanded = (uint8_t *)realloc(buffer->data, buffer->len + len);
    if (!expanded) {
        return -1;
    }
    memcpy(expanded + buffer->len, data, len);
    buffer->data = expanded;
    buffer->len += len;
    return 0;
}

static int lean_uvarint_encode(uint64_t value, uint8_t *out, size_t out_len, size_t *written) {
    if (!out || !written) {
        return -1;
    }

    uint8_t encoded[10];
    size_t len = 0u;
    do {
        uint8_t byte = (uint8_t)(value & 0x7fu);
        value >>= 7u;
        if (value != 0u) {
            byte |= 0x80u;
        }
        encoded[len++] = byte;
    } while (value != 0u && len < sizeof(encoded));

    if (value != 0u) {
        return -1;
    }
    if (out_len < len) {
        *written = len;
        return -1;
    }

    memcpy(out, encoded, len);
    *written = len;
    return 0;
}

static int lean_uvarint_decode(const uint8_t *data, size_t data_len, uint64_t *out_value, size_t *consumed) {
    if (!data || !out_value || !consumed) {
        return -1;
    }

    uint64_t value = 0u;
    size_t index = 0u;
    for (; index < data_len && index < 10u; ++index) {
        uint8_t byte = data[index];
        if (index == 9u && (byte & 0xfeu) != 0u) {
            return -1;
        }
        if (index == 9u) {
            value |= (uint64_t)byte << 63u;
        } else {
            value |= (uint64_t)(byte & 0x7fu) << (7u * index);
        }

        if ((byte & 0x80u) == 0u) {
            uint8_t canonical[10];
            size_t canonical_len = 0u;
            if (lean_uvarint_encode(value, canonical, sizeof(canonical), &canonical_len) != 0
                || canonical_len != index + 1u) {
                return -1;
            }
            *out_value = value;
            *consumed = index + 1u;
            return 0;
        }
    }

    return -1;
}

static int record_failure(
    const char *path,
    const char *codec_name,
    const char *format,
    ...) {
    va_list args;
    fprintf(stderr, "[networking-codec] %s", path ? path : "(unknown)");
    if (codec_name && codec_name[0] != '\0') {
        fprintf(stderr, " [%s]", codec_name);
    }
    fprintf(stderr, ": ");
    va_start(args, format);
    vfprintf(stderr, format, args);
    va_end(args);
    fputc('\n', stderr);
    return -1;
}

static int record_info(
    const char *path,
    const char *codec_name,
    const char *format,
    ...) {
    va_list args;
    fprintf(stderr, "[networking-codec] %s", path ? path : "(unknown)");
    if (codec_name && codec_name[0] != '\0') {
        fprintf(stderr, " [%s]", codec_name);
    }
    fprintf(stderr, ": ");
    va_start(args, format);
    vfprintf(stderr, format, args);
    va_end(args);
    fputc('\n', stderr);
    return FIXTURE_SKIPPED;
}

static int fixture_token_to_bool(
    const struct lantern_fixture_document *doc,
    int index,
    bool *out_value) {
    if (!doc || !out_value) {
        return -1;
    }
    const jsmntok_t *tok = lantern_fixture_token(doc, index);
    if (!tok || tok->type != JSMN_PRIMITIVE) {
        return -1;
    }
    size_t length = (size_t)(tok->end - tok->start);
    const char *text = doc->text + tok->start;
    if (length == 4u && strncmp(text, "true", 4u) == 0) {
        *out_value = true;
        return 0;
    }
    if (length == 5u && strncmp(text, "false", 5u) == 0) {
        *out_value = false;
        return 0;
    }
    return -1;
}

static int fixture_token_to_c_string(
    const struct lantern_fixture_document *doc,
    int index,
    char **out_string) {
    if (!doc || !out_string) {
        return -1;
    }
    *out_string = NULL;
    size_t length = 0;
    const char *value = lantern_fixture_token_string(doc, index, &length);
    if (!value) {
        return -1;
    }
    char *copy = (char *)malloc(length + 1u);
    if (!copy) {
        return -1;
    }
    if (length > 0) {
        memcpy(copy, value, length);
    }
    copy[length] = '\0';
    *out_string = copy;
    return 0;
}

static int hex_nibble(char ch) {
    if (ch >= '0' && ch <= '9') {
        return ch - '0';
    }
    if (ch >= 'a' && ch <= 'f') {
        return 10 + (ch - 'a');
    }
    if (ch >= 'A' && ch <= 'F') {
        return 10 + (ch - 'A');
    }
    return -1;
}

static int fixture_token_to_bytes(
    const struct lantern_fixture_document *doc,
    int index,
    struct byte_buffer *out_bytes) {
    if (!doc || !out_bytes) {
        return -1;
    }
    byte_buffer_reset(out_bytes);

    size_t length = 0;
    const char *value = lantern_fixture_token_string(doc, index, &length);
    if (!value || length < 2u || value[0] != '0' || value[1] != 'x') {
        return -1;
    }
    size_t hex_length = length - 2u;
    if ((hex_length % 2u) != 0u) {
        return -1;
    }

    size_t byte_length = hex_length / 2u;
    if (byte_length == 0u) {
        return 0;
    }

    uint8_t *bytes = (uint8_t *)malloc(byte_length);
    if (!bytes) {
        return -1;
    }
    for (size_t i = 0; i < byte_length; ++i) {
        int hi = hex_nibble(value[2u + (i * 2u)]);
        int lo = hex_nibble(value[3u + (i * 2u)]);
        if (hi < 0 || lo < 0) {
            free(bytes);
            return -1;
        }
        bytes[i] = (uint8_t)((hi << 4) | lo);
    }

    out_bytes->data = bytes;
    out_bytes->len = byte_length;
    return 0;
}

static int fixture_token_to_uint256_be(
    const struct lantern_fixture_document *doc,
    int index,
    uint8_t out_value[32]) {
    if (!doc || !out_value) {
        return -1;
    }
    size_t length = 0;
    const char *value = lantern_fixture_token_string(doc, index, &length);
    if (!value || length < 2u || value[0] != '0' || value[1] != 'x') {
        return -1;
    }
    size_t hex_length = length - 2u;
    if (hex_length > 64u) {
        return -1;
    }
    memset(out_value, 0, 32u);
    size_t out_index = 32u - ((hex_length + 1u) / 2u);
    size_t input_index = 2u;
    if ((hex_length % 2u) != 0u) {
        int nibble = hex_nibble(value[input_index++]);
        if (nibble < 0) {
            return -1;
        }
        out_value[out_index++] = (uint8_t)nibble;
    }
    while (input_index < length) {
        int hi = hex_nibble(value[input_index++]);
        int lo = hex_nibble(value[input_index++]);
        if (hi < 0 || lo < 0 || out_index >= 32u) {
            return -1;
        }
        out_value[out_index++] = (uint8_t)((hi << 4) | lo);
    }
    return 0;
}

static void print_hex_preview(const uint8_t *bytes, size_t len) {
    size_t preview = len < BUFFER_PREVIEW_BYTES ? len : BUFFER_PREVIEW_BYTES;
    fprintf(stderr, "0x");
    for (size_t i = 0; i < preview; ++i) {
        fprintf(stderr, "%02x", bytes[i]);
    }
    if (preview < len) {
        fprintf(stderr, "...");
    }
}

static int expect_bytes_equal(
    const char *path,
    const char *codec_name,
    const char *label,
    const uint8_t *expected,
    size_t expected_len,
    const uint8_t *actual,
    size_t actual_len) {
    if (expected_len == actual_len && (expected_len == 0u || memcmp(expected, actual, expected_len) == 0)) {
        return 0;
    }

    fprintf(stderr, "[networking-codec] %s [%s]: %s mismatch\n", path, codec_name, label);
    fprintf(stderr, "  expected (%zu bytes): ", expected_len);
    if (expected_len > 0u) {
        print_hex_preview(expected, expected_len);
    } else {
        fprintf(stderr, "0x");
    }
    fprintf(stderr, "\n  actual   (%zu bytes): ", actual_len);
    if (actual_len > 0u) {
        print_hex_preview(actual, actual_len);
    } else {
        fprintf(stderr, "0x");
    }
    fputc('\n', stderr);
    return -1;
}

static int build_fixture_root(char *path, size_t path_len) {
    if (!path || path_len == 0u) {
        return -1;
    }
    int written = snprintf(
        path,
        path_len,
        "%s/%s",
        LANTERN_CONSENSUS_FIXTURE_DIR,
        NETWORKING_CODEC_FIXTURE_SUBDIR);
    return (written > 0 && (size_t)written < path_len) ? 0 : -1;
}

static int for_each_json(
    const char *root,
    int (*callback)(const char *path, void *user_data),
    void *user_data) {
    if (!root || !callback) {
        return -1;
    }

    DIR *dir = opendir(root);
    if (!dir) {
        perror("opendir");
        return -1;
    }

    int status = 0;
    struct dirent *entry = NULL;
    while ((entry = readdir(dir)) != NULL) {
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) {
            continue;
        }

        char child_path[PATH_MAX];
        int written = snprintf(child_path, sizeof(child_path), "%s/%s", root, entry->d_name);
        if (written <= 0 || (size_t)written >= sizeof(child_path)) {
            status = -1;
            break;
        }

        struct stat st;
        if (stat(child_path, &st) != 0) {
            perror("stat");
            status = -1;
            break;
        }

        if (S_ISDIR(st.st_mode)) {
            if (for_each_json(child_path, callback, user_data) != 0) {
                status = -1;
                break;
            }
            continue;
        }

        size_t name_len = strlen(entry->d_name);
        if (name_len < 5u || strcmp(entry->d_name + name_len - 5u, ".json") != 0) {
            continue;
        }
        if (callback(child_path, user_data) != 0) {
            status = -1;
            break;
        }
    }

    closedir(dir);
    return status;
}

static int encode_reqresp_frame(
    const uint8_t *payload,
    size_t payload_len,
    uint8_t response_code,
    bool include_response_code,
    struct byte_buffer *out_frame) {
    if (!out_frame || (!payload && payload_len > 0u)) {
        return -1;
    }
    byte_buffer_reset(out_frame);

    size_t max_compressed = 0u;
    if (lantern_snappy_max_compressed_size(payload_len, &max_compressed) != LANTERN_SNAPPY_OK) {
        return -1;
    }
    uint8_t *compressed = (uint8_t *)malloc(max_compressed > 0u ? max_compressed : 1u);
    if (!compressed) {
        return -1;
    }
    size_t compressed_len = 0u;
    if (lantern_snappy_compress(payload, payload_len, compressed, max_compressed, &compressed_len) != LANTERN_SNAPPY_OK) {
        free(compressed);
        return -1;
    }

    uint8_t header[16];
    size_t header_len = 0u;
    if (libp2p_uvarint_encode(payload_len, header, sizeof(header), &header_len) != LIBP2P_UVARINT_OK) {
        free(compressed);
        return -1;
    }

    size_t prefix_len = include_response_code ? 1u : 0u;
    size_t total_len = prefix_len + header_len + compressed_len;
    uint8_t *frame = NULL;
    if (total_len > 0u) {
        frame = (uint8_t *)malloc(total_len);
        if (!frame) {
            free(compressed);
            return -1;
        }
    }

    size_t offset = 0u;
    if (include_response_code) {
        frame[offset++] = response_code;
    }
    if (header_len > 0u) {
        memcpy(frame + offset, header, header_len);
        offset += header_len;
    }
    if (compressed_len > 0u) {
        memcpy(frame + offset, compressed, compressed_len);
        offset += compressed_len;
    }

    free(compressed);
    out_frame->data = frame;
    out_frame->len = offset;
    return 0;
}

static int decode_reqresp_request(
    const uint8_t *frame,
    size_t frame_len,
    struct byte_buffer *out_payload) {
    if (!out_payload || (!frame && frame_len > 0u)) {
        return -1;
    }
    byte_buffer_reset(out_payload);
    if (frame_len == 0u) {
        return -1;
    }

    uint64_t declared_len = 0u;
    size_t consumed = 0u;
    if (libp2p_uvarint_decode(frame, frame_len, &declared_len, &consumed) != LIBP2P_UVARINT_OK) {
        return -1;
    }
    if (declared_len > SIZE_MAX || consumed > frame_len) {
        return -1;
    }

    uint8_t *payload = NULL;
    size_t payload_len = (size_t)declared_len;
    if (payload_len > 0u) {
        payload = (uint8_t *)malloc(payload_len);
        if (!payload) {
            return -1;
        }
    }
    size_t written = payload_len;
    if (lantern_snappy_decompress(
            frame + consumed,
            frame_len - consumed,
            payload,
            payload_len,
            &written)
        != LANTERN_SNAPPY_OK) {
        free(payload);
        return -1;
    }
    if (written != payload_len) {
        free(payload);
        return -1;
    }

    out_payload->data = payload;
    out_payload->len = written;
    return 0;
}

static int decode_reqresp_response(
    const uint8_t *frame,
    size_t frame_len,
    uint8_t *out_response_code,
    struct byte_buffer *out_payload) {
    if (!frame || frame_len == 0u || !out_response_code || !out_payload) {
        return -1;
    }
    *out_response_code = 0u;
    byte_buffer_reset(out_payload);

    *out_response_code = frame[0];
    return decode_reqresp_request(frame + 1u, frame_len - 1u, out_payload);
}

static int encode_gossipsub_rpc(
    const libp2p_gossipsub_rpc_t *rpc,
    struct byte_buffer *out_bytes) {
    if (!rpc || !out_bytes) {
        return -1;
    }
    byte_buffer_reset(out_bytes);

    libp2p_gossipsub_config_t config;
    if (libp2p_gossipsub_config_default(&config) != LIBP2P_GOSSIPSUB_OK) {
        return -1;
    }

    size_t required = 0u;
    libp2p_gossipsub_err_t err =
        libp2p_gossipsub_rpc_body_size(LIBP2P_GOSSIPSUB_VERSION_12, &config.limits, rpc, &required);
    if (err != LIBP2P_GOSSIPSUB_OK) {
        return err == LIBP2P_GOSSIPSUB_ERR_LIMIT ? FIXTURE_SKIPPED : -1;
    }

    uint8_t *bytes = (uint8_t *)malloc(required > 0u ? required : 1u);
    if (!bytes) {
        return -1;
    }
    size_t written = 0u;
    err = libp2p_gossipsub_rpc_body_encode(
        LIBP2P_GOSSIPSUB_VERSION_12,
        &config.limits,
        rpc,
        bytes,
        required,
        &written);
    if (err != LIBP2P_GOSSIPSUB_OK || written != required) {
        free(bytes);
        return err == LIBP2P_GOSSIPSUB_ERR_LIMIT ? FIXTURE_SKIPPED : -1;
    }

    out_bytes->data = bytes;
    out_bytes->len = written;
    return 0;
}

static int decode_enr_string(const char *enr_text, struct byte_buffer *out_rlp) {
    if (!enr_text || !out_rlp || strncmp(enr_text, "enr:", 4) != 0) {
        return -1;
    }
    byte_buffer_reset(out_rlp);
    const char *payload = enr_text + 4;
    size_t payload_len = strlen(payload);
    if (payload_len == 0u) {
        return -1;
    }

    char *prefixed = (char *)malloc(payload_len + 1u);
    if (!prefixed) {
        return -1;
    }
    prefixed[0] = 'u';
    memcpy(prefixed + 1u, payload, payload_len);

    size_t decoded_capacity = 0u;
    if (libp2p_multibase_max_decoded_size(LIBP2P_MULTIBASE_BASE64URL, payload_len, &decoded_capacity)
        != LIBP2P_MULTIBASE_OK) {
        free(prefixed);
        return -1;
    }
    uint8_t *decoded = (uint8_t *)malloc(decoded_capacity > 0u ? decoded_capacity : 1u);
    if (!decoded) {
        free(prefixed);
        return -1;
    }
    libp2p_multibase_t base = LIBP2P_MULTIBASE_BASE64URL;
    size_t written = 0u;
    if (libp2p_multibase_decode(prefixed, payload_len + 1u, &base, decoded, decoded_capacity, &written)
            != LIBP2P_MULTIBASE_OK
        || base != LIBP2P_MULTIBASE_BASE64URL) {
        free(prefixed);
        free(decoded);
        return -1;
    }
    free(prefixed);
    out_rlp->data = decoded;
    out_rlp->len = written;
    return 0;
}

static int build_enr_text_from_rlp(const uint8_t *rlp, size_t rlp_len, char **out_text) {
    if ((!rlp && rlp_len > 0u) || !out_text) {
        return -1;
    }
    *out_text = NULL;
    size_t encoded_capacity = 0u;
    if (libp2p_multibase_encoded_size(LIBP2P_MULTIBASE_BASE64URL, rlp_len, &encoded_capacity)
        != LIBP2P_MULTIBASE_OK) {
        return -1;
    }
    char *payload = (char *)malloc(encoded_capacity);
    if (!payload) {
        return -1;
    }
    size_t written = 0u;
    if (libp2p_multibase_encode(LIBP2P_MULTIBASE_BASE64URL, rlp, rlp_len, payload, encoded_capacity, &written)
            != LIBP2P_MULTIBASE_OK
        || written == 0u
        || payload[0] != 'u') {
        free(payload);
        return -1;
    }

    char *text = (char *)malloc(written + 4u);
    if (!text) {
        free(payload);
        return -1;
    }
    memcpy(text, "enr:", 4u);
    memcpy(text + 4u, payload + 1u, written - 1u);
    text[4u + written - 1u] = '\0';
    free(payload);
    *out_text = text;
    return 0;
}

static int expect_uint64_equal(
    const char *path,
    const char *codec_name,
    const char *label,
    uint64_t expected,
    uint64_t actual) {
    if (expected == actual) {
        return 0;
    }
    return record_failure(
        path,
        codec_name,
        "%s mismatch actual=%" PRIu64 " expected=%" PRIu64,
        label,
        actual,
        expected);
}

static int expect_bool_equal(
    const char *path,
    const char *codec_name,
    const char *label,
    bool expected,
    bool actual) {
    if (expected == actual) {
        return 0;
    }
    return record_failure(
        path,
        codec_name,
        "%s mismatch actual=%s expected=%s",
        label,
        actual ? "true" : "false",
        expected ? "true" : "false");
}

static int parse_port_pair(const struct lantern_enr_record *record, const char *key, uint64_t *out_port) {
    const struct lantern_enr_key_value *pair = lantern_enr_record_find(record, key);
    if (!record || !key || !out_port || !pair || !pair->value || pair->value_len != 2u) {
        return -1;
    }
    *out_port = (uint64_t)(((uint16_t)pair->value[0] << 8u) | (uint16_t)pair->value[1]);
    return 0;
}

static int parse_enabled_subnets(
    const uint8_t *bytes,
    size_t byte_len,
    uint64_t *out_indices,
    size_t max_indices,
    size_t *out_count) {
    if ((!bytes && byte_len > 0u) || (!out_indices && max_indices > 0u) || !out_count) {
        return -1;
    }
    size_t count = 0u;
    for (size_t i = 0; i < (byte_len * 8u); ++i) {
        if (((bytes[i / 8u] >> (i % 8u)) & 1u) == 0u) {
            continue;
        }
        if (count >= max_indices) {
            return -1;
        }
        out_indices[count++] = (uint64_t)i;
    }
    *out_count = count;
    return 0;
}

static int expect_uint64_array_equal(
    const char *path,
    const char *codec_name,
    const char *label,
    const uint64_t *expected,
    size_t expected_count,
    const uint64_t *actual,
    size_t actual_count) {
    if (expected_count == actual_count
        && (expected_count == 0u || memcmp(expected, actual, expected_count * sizeof(uint64_t)) == 0)) {
        return 0;
    }

    fprintf(stderr, "[networking-codec] %s [%s]: %s mismatch\n", path, codec_name, label);
    fprintf(stderr, "  expected (%zu items):", expected_count);
    for (size_t i = 0; i < expected_count; ++i) {
        fprintf(stderr, " %" PRIu64, expected[i]);
    }
    fprintf(stderr, "\n  actual   (%zu items):", actual_count);
    for (size_t i = 0; i < actual_count; ++i) {
        fprintf(stderr, " %" PRIu64, actual[i]);
    }
    fputc('\n', stderr);
    return -1;
}

static int run_enr_fixture(
    const char *path,
    const struct lantern_fixture_document *doc,
    int input_idx,
    int output_idx,
    const char *codec_name) {
    int enr_idx = lantern_fixture_object_get_field(doc, input_idx, "enrString");
    char *enr_text = NULL;
    struct byte_buffer expected_rlp = {0};
    struct byte_buffer actual_bytes = {0};
    struct byte_buffer expected_bytes = {0};
    struct lantern_enr_record record;
    bool record_ready = false;
    int rc = -1;

    lantern_enr_record_init(&record);
    if (enr_idx < 0 || fixture_token_to_c_string(doc, enr_idx, &enr_text) != 0
        || decode_enr_string(enr_text, &actual_bytes) != 0
        || lantern_enr_record_decode(enr_text, &record) != 0) {
        goto cleanup;
    }
    record_ready = true;

    int rlp_idx = lantern_fixture_object_get_field(doc, output_idx, "rlp");
    if (rlp_idx >= 0) {
        if (fixture_token_to_bytes(doc, rlp_idx, &expected_rlp) != 0
            || expect_bytes_equal(path, codec_name, "rlp", expected_rlp.data, expected_rlp.len, actual_bytes.data, actual_bytes.len)
                   != 0) {
            goto cleanup;
        }
    }

    int seq_idx = lantern_fixture_object_get_field(doc, output_idx, "seq");
    if (seq_idx >= 0) {
        uint64_t expected_seq = 0u;
        if (lantern_fixture_token_to_uint64(doc, seq_idx, &expected_seq) != 0
            || expect_uint64_equal(path, codec_name, "seq", expected_seq, record.sequence) != 0) {
            goto cleanup;
        }
    }

    int identity_idx = lantern_fixture_object_get_field(doc, output_idx, "identityScheme");
    if (identity_idx >= 0) {
        char *expected_identity = NULL;
        const struct lantern_enr_key_value *id_pair = lantern_enr_record_find(&record, "id");
        if (fixture_token_to_c_string(doc, identity_idx, &expected_identity) != 0
            || !id_pair
            || !id_pair->key
            || !id_pair->value
            || id_pair->value_len != strlen(expected_identity)
            || memcmp(id_pair->value, expected_identity, id_pair->value_len) != 0) {
            record_failure(path, codec_name, "identityScheme mismatch");
            free(expected_identity);
            goto cleanup;
        }
        free(expected_identity);
    }

    int public_key_idx = lantern_fixture_object_get_field(doc, output_idx, "publicKey");
    if (public_key_idx >= 0) {
        const struct lantern_enr_key_value *public_key = lantern_enr_record_find(&record, "secp256k1");
        if (!public_key || fixture_token_to_bytes(doc, public_key_idx, &expected_bytes) != 0
            || expect_bytes_equal(
                   path,
                   codec_name,
                   "publicKey",
                   expected_bytes.data,
                   expected_bytes.len,
                   public_key->value,
                   public_key->value_len)
                   != 0) {
            goto cleanup;
        }
        byte_buffer_reset(&expected_bytes);
    }

    int node_id_idx = lantern_fixture_object_get_field(doc, output_idx, "nodeId");
    if (node_id_idx >= 0) {
        uint8_t node_id[32];
        if (fixture_token_to_bytes(doc, node_id_idx, &expected_bytes) != 0
            || expected_bytes.len != sizeof(node_id)
            || lantern_enr_record_node_id(&record, node_id) != 0
            || expect_bytes_equal(path, codec_name, "nodeId", expected_bytes.data, expected_bytes.len, node_id, sizeof(node_id))
                   != 0) {
            goto cleanup;
        }
        byte_buffer_reset(&expected_bytes);
    }

    int signature_valid_idx = lantern_fixture_object_get_field(doc, output_idx, "signatureValid");
    if (signature_valid_idx >= 0) {
        bool expected_valid = false;
        bool actual_valid = false;
        if (fixture_token_to_bool(doc, signature_valid_idx, &expected_valid) != 0
            || lantern_enr_record_signature_valid(&record, &actual_valid) != 0
            || expect_bool_equal(path, codec_name, "signatureValid", expected_valid, actual_valid) != 0) {
            goto cleanup;
        }
    }

    int is_valid_idx = lantern_fixture_object_get_field(doc, output_idx, "isValid");
    if (is_valid_idx >= 0) {
        bool expected_valid = false;
        bool actual_valid = lantern_enr_record_is_valid(&record);
        if (fixture_token_to_bool(doc, is_valid_idx, &expected_valid) != 0
            || expect_bool_equal(path, codec_name, "isValid", expected_valid, actual_valid) != 0) {
            goto cleanup;
        }
    }

    int ip4_idx = lantern_fixture_object_get_field(doc, output_idx, "ip4");
    if (ip4_idx >= 0) {
        char *expected_ip4 = NULL;
        char actual_ip4[64];
        if (fixture_token_to_c_string(doc, ip4_idx, &expected_ip4) != 0
            || lantern_enr_record_ip4(&record, actual_ip4, sizeof(actual_ip4)) != 0
            || strcmp(actual_ip4, expected_ip4) != 0) {
            record_failure(path, codec_name, "ip4 mismatch");
            free(expected_ip4);
            goto cleanup;
        }
        free(expected_ip4);
    }

    int ip6_idx = lantern_fixture_object_get_field(doc, output_idx, "ip6");
    if (ip6_idx >= 0) {
        char *expected_ip6 = NULL;
        char actual_ip6[64];
        if (fixture_token_to_c_string(doc, ip6_idx, &expected_ip6) != 0
            || lantern_enr_record_ip6(&record, actual_ip6, sizeof(actual_ip6)) != 0
            || strcmp(actual_ip6, expected_ip6) != 0) {
            record_failure(path, codec_name, "ip6 mismatch");
            free(expected_ip6);
            goto cleanup;
        }
        free(expected_ip6);
    }

    const struct {
        const char *field;
        const char *key;
    } port_fields[] = {
        {"udpPort", "udp"},
        {"udp6Port", "udp6"},
        {"quicPort", "quic"},
        {"quic6Port", "quic6"},
    };
    for (size_t i = 0; i < sizeof(port_fields) / sizeof(port_fields[0]); ++i) {
        int field_idx = lantern_fixture_object_get_field(doc, output_idx, port_fields[i].field);
        if (field_idx < 0) {
            continue;
        }
        uint64_t expected_port = 0u;
        uint64_t actual_port = 0u;
        if (lantern_fixture_token_to_uint64(doc, field_idx, &expected_port) != 0
            || parse_port_pair(&record, port_fields[i].key, &actual_port) != 0
            || expect_uint64_equal(path, codec_name, port_fields[i].field, expected_port, actual_port) != 0) {
            if (parse_port_pair(&record, port_fields[i].key, &actual_port) != 0) {
                record_failure(path, codec_name, "%s missing from ENR", port_fields[i].field);
            }
            goto cleanup;
        }
    }

    int multiaddr_idx = lantern_fixture_object_get_field(doc, output_idx, "multiaddr");
    if (multiaddr_idx >= 0) {
        char *expected_multiaddr = NULL;
        char actual_multiaddr[256];
        if (fixture_token_to_c_string(doc, multiaddr_idx, &expected_multiaddr) != 0
            || lantern_enr_record_multiaddr(&record, actual_multiaddr, sizeof(actual_multiaddr)) != 0
            || strcmp(actual_multiaddr, expected_multiaddr) != 0) {
            record_failure(path, codec_name, "multiaddr mismatch");
            free(expected_multiaddr);
            goto cleanup;
        }
        free(expected_multiaddr);
    }

    int eth2_idx = lantern_fixture_object_get_field(doc, output_idx, "eth2Data");
    if (eth2_idx >= 0) {
        struct lantern_enr_eth2_data actual_eth2;
        if (lantern_enr_record_eth2(&record, &actual_eth2) != 0) {
            record_failure(path, codec_name, "eth2Data missing from ENR");
            goto cleanup;
        }

        int fork_idx = lantern_fixture_object_get_field(doc, eth2_idx, "forkDigest");
        int version_idx = lantern_fixture_object_get_field(doc, eth2_idx, "nextForkVersion");
        int epoch_idx = lantern_fixture_object_get_field(doc, eth2_idx, "nextForkEpoch");
        uint64_t expected_epoch = 0u;
        if (fork_idx < 0 || version_idx < 0 || epoch_idx < 0
            || fixture_token_to_bytes(doc, fork_idx, &expected_bytes) != 0
            || expect_bytes_equal(path, codec_name, "eth2Data.forkDigest", expected_bytes.data, expected_bytes.len, actual_eth2.fork_digest, 4u)
                   != 0) {
            goto cleanup;
        }
        byte_buffer_reset(&expected_bytes);
        if (fixture_token_to_bytes(doc, version_idx, &expected_bytes) != 0
            || expect_bytes_equal(
                   path,
                   codec_name,
                   "eth2Data.nextForkVersion",
                   expected_bytes.data,
                   expected_bytes.len,
                   actual_eth2.next_fork_version,
                   4u)
                   != 0
            || lantern_fixture_token_to_uint64(doc, epoch_idx, &expected_epoch) != 0
            || expect_uint64_equal(
                   path,
                   codec_name,
                   "eth2Data.nextForkEpoch",
                   expected_epoch,
                   actual_eth2.next_fork_epoch)
                   != 0) {
            goto cleanup;
        }
        byte_buffer_reset(&expected_bytes);
    }

    const struct {
        const char *field;
        const char *key;
        size_t byte_len;
    } subnet_fields[] = {
        {"attestationSubnets", "attnets", 8u},
        {"syncCommitteeSubnets", "syncnets", 1u},
    };
    for (size_t i = 0; i < sizeof(subnet_fields) / sizeof(subnet_fields[0]); ++i) {
        int field_idx = lantern_fixture_object_get_field(doc, output_idx, subnet_fields[i].field);
        if (field_idx < 0) {
            continue;
        }
        const struct lantern_enr_key_value *pair = lantern_enr_record_find(&record, subnet_fields[i].key);
        int expected_count = lantern_fixture_array_get_length(doc, field_idx);
        uint64_t expected_indices[64];
        uint64_t actual_indices[64];
        size_t actual_count = 0u;
        if (!pair || !pair->value || pair->value_len != subnet_fields[i].byte_len || expected_count < 0) {
            record_failure(path, codec_name, "%s missing from ENR", subnet_fields[i].field);
            goto cleanup;
        }
        for (int array_i = 0; array_i < expected_count; ++array_i) {
            int element_idx = lantern_fixture_array_get_element(doc, field_idx, array_i);
            if (element_idx < 0
                || lantern_fixture_token_to_uint64(doc, element_idx, &expected_indices[array_i]) != 0) {
                goto cleanup;
            }
        }
        if (parse_enabled_subnets(pair->value, pair->value_len, actual_indices, 64u, &actual_count) != 0
            || expect_uint64_array_equal(
                   path,
                   codec_name,
                   subnet_fields[i].field,
                   expected_indices,
                   (size_t)expected_count,
                   actual_indices,
                   actual_count)
                   != 0) {
            if (parse_enabled_subnets(pair->value, pair->value_len, actual_indices, 64u, &actual_count) != 0) {
                record_failure(path, codec_name, "failed to parse %s bitfield", subnet_fields[i].field);
            }
            goto cleanup;
        }
    }

    int aggregator_idx = lantern_fixture_object_get_field(doc, output_idx, "isAggregator");
    if (aggregator_idx >= 0) {
        bool expected_aggregator = false;
        if (fixture_token_to_bool(doc, aggregator_idx, &expected_aggregator) != 0
            || expect_bool_equal(
                   path,
                   codec_name,
                   "isAggregator",
                   expected_aggregator,
                   lantern_enr_record_is_aggregator(&record))
                   != 0) {
            goto cleanup;
        }
    }

    rc = 0;

cleanup:
    free(enr_text);
    byte_buffer_reset(&expected_rlp);
    byte_buffer_reset(&actual_bytes);
    byte_buffer_reset(&expected_bytes);
    if (record_ready) {
        lantern_enr_record_reset(&record);
    }
    if (rc != 0 && !record_ready) {
        return record_failure(path, codec_name, "failed to decode ENR fixture");
    }
    return rc;
}

struct gossipsub_rpc_fixture {
    libp2p_gossipsub_rpc_t rpc;
    libp2p_gossipsub_rpc_subscription_t *subscriptions;
    libp2p_gossipsub_message_t *publish;
    libp2p_gossipsub_control_ihave_t *ihave;
    libp2p_gossipsub_control_iwant_t *iwant;
    libp2p_gossipsub_control_graft_t *graft;
    libp2p_gossipsub_control_prune_t *prune;
    libp2p_gossipsub_control_idontwant_t *idontwant;
    void **owned;
    size_t owned_count;
    size_t owned_capacity;
    bool c_lean_unsupported_shape;
};

static void gossipsub_rpc_fixture_reset(struct gossipsub_rpc_fixture *fixture) {
    if (!fixture) {
        return;
    }
    for (size_t i = 0; i < fixture->owned_count; ++i) {
        free(fixture->owned[i]);
    }
    free(fixture->owned);
    memset(fixture, 0, sizeof(*fixture));
}

static void *gossipsub_fixture_alloc(struct gossipsub_rpc_fixture *fixture, size_t count, size_t size) {
    if (!fixture || size == 0u || count > SIZE_MAX / size) {
        return NULL;
    }
    void *ptr = calloc(count, size);
    if (!ptr) {
        return NULL;
    }
    if (fixture->owned_count == fixture->owned_capacity) {
        size_t next_capacity = fixture->owned_capacity == 0u ? 16u : fixture->owned_capacity * 2u;
        void **next = (void **)realloc(fixture->owned, next_capacity * sizeof(*next));
        if (!next) {
            free(ptr);
            return NULL;
        }
        fixture->owned = next;
        fixture->owned_capacity = next_capacity;
    }
    fixture->owned[fixture->owned_count++] = ptr;
    return ptr;
}

static int gossipsub_fixture_take_bytes(
    struct gossipsub_rpc_fixture *fixture,
    struct byte_buffer *buffer,
    libp2p_gossipsub_bytes_t *out_span) {
    if (!fixture || !buffer || !out_span) {
        return -1;
    }
    if (buffer->len == 0u) {
        out_span->data = NULL;
        out_span->len = 0u;
        free(buffer->data);
        buffer->data = NULL;
        return 0;
    }
    if (fixture->owned_count == fixture->owned_capacity) {
        size_t next_capacity = fixture->owned_capacity == 0u ? 16u : fixture->owned_capacity * 2u;
        void **next = (void **)realloc(fixture->owned, next_capacity * sizeof(*next));
        if (!next) {
            return -1;
        }
        fixture->owned = next;
        fixture->owned_capacity = next_capacity;
    }
    fixture->owned[fixture->owned_count++] = buffer->data;
    out_span->data = buffer->data;
    out_span->len = buffer->len;
    buffer->data = NULL;
    buffer->len = 0u;
    return 0;
}

static int gossipsub_fixture_span_from_bytes(
    struct gossipsub_rpc_fixture *fixture,
    const struct lantern_fixture_document *doc,
    int token_idx,
    libp2p_gossipsub_bytes_t *out_span) {
    struct byte_buffer bytes = {0};
    if (fixture_token_to_bytes(doc, token_idx, &bytes) != 0
        || gossipsub_fixture_take_bytes(fixture, &bytes, out_span) != 0) {
        byte_buffer_reset(&bytes);
        return -1;
    }
    return 0;
}

static int gossipsub_fixture_span_from_string(
    struct gossipsub_rpc_fixture *fixture,
    const struct lantern_fixture_document *doc,
    int token_idx,
    libp2p_gossipsub_bytes_t *out_span,
    bool required_by_c_lean) {
    char *text = NULL;
    if (!fixture || !doc || token_idx < 0 || !out_span || fixture_token_to_c_string(doc, token_idx, &text) != 0) {
        free(text);
        return -1;
    }
    size_t len = strlen(text);
    if (len == 0u && required_by_c_lean) {
        fixture->c_lean_unsupported_shape = true;
    }
    struct byte_buffer buffer = {
        .data = (uint8_t *)text,
        .len = len,
    };
    return gossipsub_fixture_take_bytes(fixture, &buffer, out_span);
}

static int parse_message_id_array(
    const struct lantern_fixture_document *doc,
    int array_index,
    struct gossipsub_rpc_fixture *fixture,
    const libp2p_gossipsub_bytes_t **out_ids,
    size_t *out_count) {
    if (!doc || array_index < 0 || !fixture || !out_ids || !out_count) {
        return -1;
    }
    *out_ids = NULL;
    *out_count = 0u;
    int count = lantern_fixture_array_get_length(doc, array_index);
    if (count < 0) {
        return -1;
    }
    if (count == 0) {
        return 0;
    }
    libp2p_gossipsub_bytes_t *ids =
        (libp2p_gossipsub_bytes_t *)gossipsub_fixture_alloc(fixture, (size_t)count, sizeof(*ids));
    if (!ids) {
        return -1;
    }
    for (int i = 0; i < count; ++i) {
        int element_idx = lantern_fixture_array_get_element(doc, array_index, i);
        if (element_idx < 0 || gossipsub_fixture_span_from_bytes(fixture, doc, element_idx, &ids[i]) != 0) {
            return -1;
        }
    }
    *out_ids = ids;
    *out_count = (size_t)count;
    return 0;
}

static int build_gossipsub_rpc(
    const struct lantern_fixture_document *doc,
    int input_idx,
    struct gossipsub_rpc_fixture *fixture) {
    if (!doc || input_idx < 0 || !fixture) {
        return -1;
    }
    memset(fixture, 0, sizeof(*fixture));

    int subscriptions_idx = lantern_fixture_object_get_field(doc, input_idx, "subscriptions");
    if (subscriptions_idx >= 0) {
        int count = lantern_fixture_array_get_length(doc, subscriptions_idx);
        if (count < 0) {
            return -1;
        }
        if (count > 0) {
            fixture->subscriptions = (libp2p_gossipsub_rpc_subscription_t *)gossipsub_fixture_alloc(
                fixture,
                (size_t)count,
                sizeof(*fixture->subscriptions));
            if (!fixture->subscriptions) {
                return -1;
            }
            fixture->rpc.subscriptions = fixture->subscriptions;
            fixture->rpc.subscription_count = (size_t)count;
        }
        for (int i = 0; i < count; ++i) {
            int sub_idx = lantern_fixture_array_get_element(doc, subscriptions_idx, i);
            int subscribe_idx = lantern_fixture_object_get_field(doc, sub_idx, "subscribe");
            int topic_idx = lantern_fixture_object_get_field(doc, sub_idx, "topicId");
            bool subscribe = false;
            if (sub_idx < 0 || subscribe_idx < 0 || topic_idx < 0
                || fixture_token_to_bool(doc, subscribe_idx, &subscribe) != 0
                || gossipsub_fixture_span_from_string(
                       fixture,
                       doc,
                       topic_idx,
                       &fixture->subscriptions[i].topic,
                       true)
                       != 0) {
                return -1;
            }
            fixture->subscriptions[i].subscribe = subscribe ? 1u : 0u;
        }
    }

    int publish_idx = lantern_fixture_object_get_field(doc, input_idx, "publish");
    if (publish_idx >= 0) {
        int count = lantern_fixture_array_get_length(doc, publish_idx);
        if (count < 0) {
            return -1;
        }
        if (count > 0) {
            fixture->publish =
                (libp2p_gossipsub_message_t *)gossipsub_fixture_alloc(fixture, (size_t)count, sizeof(*fixture->publish));
            if (!fixture->publish) {
                return -1;
            }
            fixture->rpc.publish = fixture->publish;
            fixture->rpc.publish_count = (size_t)count;
        }
        for (int i = 0; i < count; ++i) {
            int message_idx = lantern_fixture_array_get_element(doc, publish_idx, i);
            if (message_idx < 0) {
                return -1;
            }
            const struct {
                const char *field;
                libp2p_gossipsub_bytes_t *span;
            } byte_fields[] = {
                {"fromPeer", &fixture->publish[i].from},
                {"data", &fixture->publish[i].data},
                {"seqno", &fixture->publish[i].seqno},
                {"signature", &fixture->publish[i].signature},
                {"key", &fixture->publish[i].key},
            };
            for (size_t field = 0u; field < sizeof(byte_fields) / sizeof(byte_fields[0]); ++field) {
                int field_idx = lantern_fixture_object_get_field(doc, message_idx, byte_fields[field].field);
                if (field_idx >= 0
                    && gossipsub_fixture_span_from_bytes(fixture, doc, field_idx, byte_fields[field].span) != 0) {
                    return -1;
                }
            }
            int topic_idx = lantern_fixture_object_get_field(doc, message_idx, "topic");
            if (topic_idx < 0) {
                fixture->c_lean_unsupported_shape = true;
            } else if (gossipsub_fixture_span_from_string(
                           fixture,
                           doc,
                           topic_idx,
                           &fixture->publish[i].topic,
                           true)
                       != 0) {
                return -1;
            }
        }
    }

    int control_idx = lantern_fixture_object_get_field(doc, input_idx, "control");
    if (control_idx >= 0) {
        int ihave_idx = lantern_fixture_object_get_field(doc, control_idx, "ihave");
        if (ihave_idx >= 0) {
            int count = lantern_fixture_array_get_length(doc, ihave_idx);
            if (count < 0) {
                return -1;
            }
            if (count > 0) {
                fixture->ihave =
                    (libp2p_gossipsub_control_ihave_t *)gossipsub_fixture_alloc(fixture, (size_t)count, sizeof(*fixture->ihave));
                if (!fixture->ihave) {
                    return -1;
                }
                fixture->rpc.control.ihave = fixture->ihave;
                fixture->rpc.control.ihave_count = (size_t)count;
            }
            for (int i = 0; i < count; ++i) {
                int entry_idx = lantern_fixture_array_get_element(doc, ihave_idx, i);
                int topic_idx = lantern_fixture_object_get_field(doc, entry_idx, "topicId");
                int ids_idx = lantern_fixture_object_get_field(doc, entry_idx, "messageIds");
                if (entry_idx < 0 || topic_idx < 0 || ids_idx < 0
                    || gossipsub_fixture_span_from_string(fixture, doc, topic_idx, &fixture->ihave[i].topic, true)
                           != 0
                    || parse_message_id_array(
                           doc,
                           ids_idx,
                           fixture,
                           &fixture->ihave[i].message_ids,
                           &fixture->ihave[i].message_id_count)
                           != 0) {
                    return -1;
                }
            }
        }

        int iwant_idx = lantern_fixture_object_get_field(doc, control_idx, "iwant");
        if (iwant_idx >= 0) {
            int count = lantern_fixture_array_get_length(doc, iwant_idx);
            if (count < 0) {
                return -1;
            }
            if (count > 0) {
                fixture->iwant =
                    (libp2p_gossipsub_control_iwant_t *)gossipsub_fixture_alloc(fixture, (size_t)count, sizeof(*fixture->iwant));
                if (!fixture->iwant) {
                    return -1;
                }
                fixture->rpc.control.iwant = fixture->iwant;
                fixture->rpc.control.iwant_count = (size_t)count;
            }
            for (int i = 0; i < count; ++i) {
                int entry_idx = lantern_fixture_array_get_element(doc, iwant_idx, i);
                int ids_idx = lantern_fixture_object_get_field(doc, entry_idx, "messageIds");
                if (entry_idx < 0 || ids_idx < 0
                    || parse_message_id_array(
                           doc,
                           ids_idx,
                           fixture,
                           &fixture->iwant[i].message_ids,
                           &fixture->iwant[i].message_id_count)
                           != 0) {
                    return -1;
                }
            }
        }

        int graft_idx = lantern_fixture_object_get_field(doc, control_idx, "graft");
        if (graft_idx >= 0) {
            int count = lantern_fixture_array_get_length(doc, graft_idx);
            if (count < 0) {
                return -1;
            }
            if (count > 0) {
                fixture->graft =
                    (libp2p_gossipsub_control_graft_t *)gossipsub_fixture_alloc(fixture, (size_t)count, sizeof(*fixture->graft));
                if (!fixture->graft) {
                    return -1;
                }
                fixture->rpc.control.graft = fixture->graft;
                fixture->rpc.control.graft_count = (size_t)count;
            }
            for (int i = 0; i < count; ++i) {
                int entry_idx = lantern_fixture_array_get_element(doc, graft_idx, i);
                int topic_idx = lantern_fixture_object_get_field(doc, entry_idx, "topicId");
                if (entry_idx < 0 || topic_idx < 0
                    || gossipsub_fixture_span_from_string(fixture, doc, topic_idx, &fixture->graft[i].topic, true)
                           != 0) {
                    return -1;
                }
            }
        }

        int prune_idx = lantern_fixture_object_get_field(doc, control_idx, "prune");
        if (prune_idx >= 0) {
            int count = lantern_fixture_array_get_length(doc, prune_idx);
            if (count < 0) {
                return -1;
            }
            if (count > 0) {
                fixture->prune =
                    (libp2p_gossipsub_control_prune_t *)gossipsub_fixture_alloc(fixture, (size_t)count, sizeof(*fixture->prune));
                if (!fixture->prune) {
                    return -1;
                }
                fixture->rpc.control.prune = fixture->prune;
                fixture->rpc.control.prune_count = (size_t)count;
            }
            for (int i = 0; i < count; ++i) {
                int entry_idx = lantern_fixture_array_get_element(doc, prune_idx, i);
                int topic_idx = lantern_fixture_object_get_field(doc, entry_idx, "topicId");
                int backoff_idx = lantern_fixture_object_get_field(doc, entry_idx, "backoff");
                int peers_idx = lantern_fixture_object_get_field(doc, entry_idx, "peers");
                if (entry_idx < 0 || topic_idx < 0
                    || gossipsub_fixture_span_from_string(fixture, doc, topic_idx, &fixture->prune[i].topic, true)
                           != 0) {
                    return -1;
                }
                if (backoff_idx >= 0
                    && lantern_fixture_token_to_uint64(doc, backoff_idx, &fixture->prune[i].backoff_seconds) != 0) {
                    return -1;
                }
                if (peers_idx >= 0) {
                    int peer_count = lantern_fixture_array_get_length(doc, peers_idx);
                    if (peer_count < 0) {
                        return -1;
                    }
                    if (peer_count > 0) {
                        fixture->c_lean_unsupported_shape = true;
                        libp2p_gossipsub_peer_info_t *peers = (libp2p_gossipsub_peer_info_t *)gossipsub_fixture_alloc(
                            fixture,
                            (size_t)peer_count,
                            sizeof(*peers));
                        if (!peers) {
                            return -1;
                        }
                        fixture->prune[i].peers = peers;
                        fixture->prune[i].peer_count = (size_t)peer_count;
                    }
                    for (int peer_i = 0; peer_i < peer_count; ++peer_i) {
                        int peer_idx = lantern_fixture_array_get_element(doc, peers_idx, peer_i);
                        int peer_id_idx = lantern_fixture_object_get_field(doc, peer_idx, "peerId");
                        int record_idx = lantern_fixture_object_get_field(doc, peer_idx, "signedPeerRecord");
                        if (peer_idx < 0 || peer_id_idx < 0
                            || gossipsub_fixture_span_from_bytes(
                                   fixture,
                                   doc,
                                   peer_id_idx,
                                   (libp2p_gossipsub_bytes_t *)&fixture->prune[i].peers[peer_i].peer_id)
                                   != 0) {
                            return -1;
                        }
                        if (record_idx >= 0
                            && gossipsub_fixture_span_from_bytes(
                                   fixture,
                                   doc,
                                   record_idx,
                                   (libp2p_gossipsub_bytes_t *)&fixture->prune[i].peers[peer_i].signed_peer_record)
                                   != 0) {
                            return -1;
                        }
                    }
                }
            }
        }

        int idontwant_idx = lantern_fixture_object_get_field(doc, control_idx, "idontwant");
        if (idontwant_idx >= 0) {
            int count = lantern_fixture_array_get_length(doc, idontwant_idx);
            if (count < 0) {
                return -1;
            }
            if (count > 0) {
                fixture->idontwant = (libp2p_gossipsub_control_idontwant_t *)gossipsub_fixture_alloc(
                    fixture,
                    (size_t)count,
                    sizeof(*fixture->idontwant));
                if (!fixture->idontwant) {
                    return -1;
                }
                fixture->rpc.control.idontwant = fixture->idontwant;
                fixture->rpc.control.idontwant_count = (size_t)count;
            }
            for (int i = 0; i < count; ++i) {
                int entry_idx = lantern_fixture_array_get_element(doc, idontwant_idx, i);
                int ids_idx = lantern_fixture_object_get_field(doc, entry_idx, "messageIds");
                if (entry_idx < 0 || ids_idx < 0
                    || parse_message_id_array(
                           doc,
                           ids_idx,
                           fixture,
                           &fixture->idontwant[i].message_ids,
                           &fixture->idontwant[i].message_id_count)
                           != 0) {
                    return -1;
                }
            }
        }
    }

    return 0;
}

static int run_varint_fixture(
    const char *path,
    const struct lantern_fixture_document *doc,
    int input_idx,
    int output_idx,
    const char *codec_name) {
    int value_idx = lantern_fixture_object_get_field(doc, input_idx, "value");
    int encoded_idx = lantern_fixture_object_get_field(doc, output_idx, "encoded");
    int byte_length_idx = lantern_fixture_object_get_field(doc, output_idx, "byteLength");
    uint64_t value = 0u;
    uint64_t expected_length = 0u;
    struct byte_buffer expected = {0};

    if (value_idx < 0 || encoded_idx < 0 || byte_length_idx < 0
        || lantern_fixture_token_to_uint64(doc, value_idx, &value) != 0
        || lantern_fixture_token_to_uint64(doc, byte_length_idx, &expected_length) != 0
        || fixture_token_to_bytes(doc, encoded_idx, &expected) != 0) {
        byte_buffer_reset(&expected);
        return record_failure(path, codec_name, "invalid varint fixture payload");
    }

    uint8_t encoded[16];
    size_t encoded_len = 0u;
    if (lean_uvarint_encode(value, encoded, sizeof(encoded), &encoded_len) != 0) {
        byte_buffer_reset(&expected);
        return record_failure(path, codec_name, "uvarint encode failed for value=%" PRIu64, value);
    }
    if (encoded_len != expected_length
        || expect_bytes_equal(path, codec_name, "encoded", expected.data, expected.len, encoded, encoded_len) != 0) {
        byte_buffer_reset(&expected);
        return -1;
    }

    uint64_t decoded = 0u;
    size_t consumed = 0u;
    if (lean_uvarint_decode(encoded, encoded_len, &decoded, &consumed) != 0) {
        byte_buffer_reset(&expected);
        return record_failure(path, codec_name, "uvarint decode failed");
    }
    if (decoded != value || consumed != encoded_len) {
        byte_buffer_reset(&expected);
        return record_failure(
            path,
            codec_name,
            "decoded varint mismatch value=%" PRIu64 "/%" PRIu64 " consumed=%zu/%zu",
            decoded,
            value,
            consumed,
            encoded_len);
    }

    byte_buffer_reset(&expected);
    return 0;
}

static int run_reqresp_request_fixture(
    const char *path,
    const struct lantern_fixture_document *doc,
    int input_idx,
    int output_idx,
    const char *codec_name) {
    int payload_idx = lantern_fixture_object_get_field(doc, input_idx, "sszData");
    int encoded_idx = lantern_fixture_object_get_field(doc, output_idx, "encoded");
    struct byte_buffer payload = {0};
    struct byte_buffer expected = {0};
    struct byte_buffer actual = {0};
    struct byte_buffer decoded = {0};

    if (payload_idx < 0 || encoded_idx < 0
        || fixture_token_to_bytes(doc, payload_idx, &payload) != 0
        || fixture_token_to_bytes(doc, encoded_idx, &expected) != 0
        || encode_reqresp_frame(payload.data, payload.len, 0u, false, &actual) != 0) {
        byte_buffer_reset(&payload);
        byte_buffer_reset(&expected);
        byte_buffer_reset(&actual);
        return record_failure(path, codec_name, "failed to encode request fixture");
    }

    if (expect_bytes_equal(path, codec_name, "encoded", expected.data, expected.len, actual.data, actual.len) != 0) {
        byte_buffer_reset(&payload);
        byte_buffer_reset(&expected);
        byte_buffer_reset(&actual);
        return -1;
    }

    if (decode_reqresp_request(actual.data, actual.len, &decoded) != 0) {
        byte_buffer_reset(&payload);
        byte_buffer_reset(&expected);
        byte_buffer_reset(&actual);
        byte_buffer_reset(&decoded);
        return record_failure(path, codec_name, "failed to decode request frame");
    }
    if (expect_bytes_equal(path, codec_name, "decoded payload", payload.data, payload.len, decoded.data, decoded.len) != 0) {
        byte_buffer_reset(&payload);
        byte_buffer_reset(&expected);
        byte_buffer_reset(&actual);
        byte_buffer_reset(&decoded);
        return -1;
    }

    byte_buffer_reset(&payload);
    byte_buffer_reset(&expected);
    byte_buffer_reset(&actual);
    byte_buffer_reset(&decoded);
    return 0;
}

static int run_reqresp_response_fixture(
    const char *path,
    const struct lantern_fixture_document *doc,
    int input_idx,
    int output_idx,
    const char *codec_name) {
    int code_idx = lantern_fixture_object_get_field(doc, input_idx, "responseCode");
    int payload_idx = lantern_fixture_object_get_field(doc, input_idx, "sszData");
    int encoded_idx = lantern_fixture_object_get_field(doc, output_idx, "encoded");
    uint64_t response_code_u64 = 0u;
    struct byte_buffer payload = {0};
    struct byte_buffer expected = {0};
    struct byte_buffer actual = {0};
    struct byte_buffer decoded = {0};
    uint8_t decoded_code = 0u;

    if (code_idx < 0 || payload_idx < 0 || encoded_idx < 0
        || lantern_fixture_token_to_uint64(doc, code_idx, &response_code_u64) != 0
        || response_code_u64 > UINT8_MAX
        || fixture_token_to_bytes(doc, payload_idx, &payload) != 0
        || fixture_token_to_bytes(doc, encoded_idx, &expected) != 0
        || encode_reqresp_frame(payload.data, payload.len, (uint8_t)response_code_u64, true, &actual) != 0) {
        byte_buffer_reset(&payload);
        byte_buffer_reset(&expected);
        byte_buffer_reset(&actual);
        return record_failure(path, codec_name, "failed to encode response fixture");
    }

    if (expect_bytes_equal(path, codec_name, "encoded", expected.data, expected.len, actual.data, actual.len) != 0) {
        byte_buffer_reset(&payload);
        byte_buffer_reset(&expected);
        byte_buffer_reset(&actual);
        return -1;
    }

    if (decode_reqresp_response(actual.data, actual.len, &decoded_code, &decoded) != 0) {
        byte_buffer_reset(&payload);
        byte_buffer_reset(&expected);
        byte_buffer_reset(&actual);
        byte_buffer_reset(&decoded);
        return record_failure(path, codec_name, "failed to decode response frame");
    }
    if (decoded_code != (uint8_t)response_code_u64) {
        byte_buffer_reset(&payload);
        byte_buffer_reset(&expected);
        byte_buffer_reset(&actual);
        byte_buffer_reset(&decoded);
        return record_failure(
            path,
            codec_name,
            "decoded response code mismatch got=%u expected=%" PRIu64,
            (unsigned)decoded_code,
            response_code_u64);
    }
    if (expect_bytes_equal(path, codec_name, "decoded payload", payload.data, payload.len, decoded.data, decoded.len) != 0) {
        byte_buffer_reset(&payload);
        byte_buffer_reset(&expected);
        byte_buffer_reset(&actual);
        byte_buffer_reset(&decoded);
        return -1;
    }

    byte_buffer_reset(&payload);
    byte_buffer_reset(&expected);
    byte_buffer_reset(&actual);
    byte_buffer_reset(&decoded);
    return 0;
}

static int run_gossip_topic_fixture(
    const char *path,
    const struct lantern_fixture_document *doc,
    int input_idx,
    int output_idx,
    const char *codec_name) {
    int kind_idx = lantern_fixture_object_get_field(doc, input_idx, "topicKind");
    if (kind_idx < 0) {
        kind_idx = lantern_fixture_object_get_field(doc, input_idx, "kind");
    }
    int digest_idx = lantern_fixture_object_get_field(doc, input_idx, "forkDigest");
    if (digest_idx < 0) {
        digest_idx = lantern_fixture_object_get_field(doc, input_idx, "networkName");
    }
    int subnet_idx = lantern_fixture_object_get_field(doc, input_idx, "subnetId");
    int topic_idx = lantern_fixture_object_get_field(doc, output_idx, "topicString");
    char *kind = NULL;
    char *fork_digest = NULL;
    char *expected_topic = NULL;
    char actual_topic[256];
    int rc = -1;

    if (kind_idx < 0 || digest_idx < 0 || topic_idx < 0
        || fixture_token_to_c_string(doc, kind_idx, &kind) != 0
        || fixture_token_to_c_string(doc, digest_idx, &fork_digest) != 0
        || fixture_token_to_c_string(doc, topic_idx, &expected_topic) != 0) {
        goto cleanup;
    }

    if (strcmp(kind, "block") == 0) {
        rc = lantern_gossip_topic_format(
            LANTERN_GOSSIP_TOPIC_BLOCK,
            fork_digest,
            actual_topic,
            sizeof(actual_topic));
    } else if (strcmp(kind, "aggregation") == 0) {
        rc = lantern_gossip_topic_format(
            LANTERN_GOSSIP_TOPIC_AGGREGATED_ATTESTATION,
            fork_digest,
            actual_topic,
            sizeof(actual_topic));
    } else if (strcmp(kind, "attestation") == 0 && subnet_idx >= 0) {
        uint64_t subnet_id = 0u;
        if (lantern_fixture_token_to_uint64(doc, subnet_idx, &subnet_id) != 0) {
            rc = -1;
        } else {
            rc = lantern_gossip_topic_format_subnet(
                LANTERN_GOSSIP_TOPIC_VOTE_SUBNET,
                fork_digest,
                (size_t)subnet_id,
                actual_topic,
                sizeof(actual_topic));
        }
    } else {
        rc = -1;
    }

    if (rc != 0) {
        record_failure(path, codec_name, "failed to format topic kind=%s", kind ? kind : "(null)");
        rc = -1;
        goto cleanup;
    }
    if (strcmp(actual_topic, expected_topic) != 0) {
        record_failure(
            path,
            codec_name,
            "topic mismatch actual=%s expected=%s",
            actual_topic,
            expected_topic);
        rc = -1;
        goto cleanup;
    }

    rc = 0;

cleanup:
    free(kind);
    free(fork_digest);
    free(expected_topic);
    if (rc != 0 && !kind) {
        return record_failure(path, codec_name, "invalid gossip topic fixture");
    }
    return rc;
}

static int run_gossip_message_id_fixture(
    const char *path,
    const struct lantern_fixture_document *doc,
    int input_idx,
    int output_idx,
    const char *codec_name) {
    int topic_idx = lantern_fixture_object_get_field(doc, input_idx, "topic");
    int data_idx = lantern_fixture_object_get_field(doc, input_idx, "data");
    int domain_idx = lantern_fixture_object_get_field(doc, input_idx, "domain");
    int output_message_idx = lantern_fixture_object_get_field(doc, output_idx, "messageId");
    struct byte_buffer topic = {0};
    struct byte_buffer data = {0};
    struct byte_buffer domain = {0};
    struct byte_buffer expected = {0};
    struct byte_buffer raw_snappy = {0};
    struct byte_buffer scratch_buffer = {0};
    LanternGossipMessageId actual;
    size_t required_scratch = 0u;
    int rc = -1;
    bool fixture_valid = false;

    if (topic_idx < 0 || data_idx < 0 || domain_idx < 0 || output_message_idx < 0
        || fixture_token_to_bytes(doc, topic_idx, &topic) != 0
        || fixture_token_to_bytes(doc, data_idx, &data) != 0
        || fixture_token_to_bytes(doc, domain_idx, &domain) != 0
        || fixture_token_to_bytes(doc, output_message_idx, &expected) != 0
        || domain.len != LANTERN_GOSSIP_DOMAIN_SIZE
        || expected.len != LANTERN_GOSSIP_MESSAGE_ID_SIZE) {
        goto cleanup;
    }
    fixture_valid = true;

    const uint8_t *payload = data.data;
    size_t payload_len = data.len;
    uint8_t *scratch = NULL;
    size_t scratch_len = 0u;

    if (memcmp(domain.data, LANTERN_GOSSIP_DOMAIN_VALID, LANTERN_GOSSIP_DOMAIN_SIZE) == 0) {
        size_t max_compressed = 0u;
        if (lantern_snappy_max_compressed_size_raw(data.len, &max_compressed) != LANTERN_SNAPPY_OK) {
            goto cleanup;
        }
        raw_snappy.data = (uint8_t *)malloc(max_compressed > 0u ? max_compressed : 1u);
        if (!raw_snappy.data) {
            goto cleanup;
        }
        raw_snappy.len = max_compressed;
        if (lantern_snappy_compress_raw(data.data, data.len, raw_snappy.data, max_compressed, &raw_snappy.len)
            != LANTERN_SNAPPY_OK) {
            goto cleanup;
        }
        payload = raw_snappy.data;
        payload_len = raw_snappy.len;
        scratch_buffer.data = (uint8_t *)malloc(data.len > 0u ? data.len : 1u);
        if (!scratch_buffer.data) {
            goto cleanup;
        }
        scratch_buffer.len = data.len;
        scratch = scratch_buffer.data;
        scratch_len = data.len;
    } else if (memcmp(domain.data, LANTERN_GOSSIP_DOMAIN_INVALID, LANTERN_GOSSIP_DOMAIN_SIZE) != 0) {
        record_failure(path, codec_name, "unsupported explicit message-id domain");
        rc = -1;
        goto cleanup;
    }

    memset(&actual, 0, sizeof(actual));
    if (lantern_gossip_compute_message_id(
            &actual,
            topic.data,
            topic.len,
            payload,
            payload_len,
            scratch,
            scratch_len,
            &required_scratch)
        != 0) {
        record_failure(
            path,
            codec_name,
            "lantern_gossip_compute_message_id failed required_scratch=%zu",
            required_scratch);
        rc = -1;
        goto cleanup;
    }

    rc = expect_bytes_equal(
        path,
        codec_name,
        "messageId",
        expected.data,
        expected.len,
        actual.bytes,
        sizeof(actual.bytes));

cleanup:
    byte_buffer_reset(&topic);
    byte_buffer_reset(&data);
    byte_buffer_reset(&domain);
    byte_buffer_reset(&expected);
    byte_buffer_reset(&raw_snappy);
    byte_buffer_reset(&scratch_buffer);
    if (rc != 0 && !fixture_valid) {
        return record_failure(path, codec_name, "invalid gossip message-id fixture");
    }
    return rc;
}

static int run_gossipsub_rpc_fixture(
    const char *path,
    const struct lantern_fixture_document *doc,
    int input_idx,
    int output_idx,
    const char *codec_name) {
    int encoded_idx = lantern_fixture_object_get_field(doc, output_idx, "encoded");
    struct gossipsub_rpc_fixture fixture;
    struct gossipsub_rpc_fixture decoded_fixture;
    struct byte_buffer expected = {0};
    struct byte_buffer actual = {0};
    struct byte_buffer roundtrip = {0};
    bool built_ok = false;
    int rc = -1;

    memset(&fixture, 0, sizeof(fixture));
    memset(&decoded_fixture, 0, sizeof(decoded_fixture));

    if (encoded_idx < 0
        || fixture_token_to_bytes(doc, encoded_idx, &expected) != 0
        || build_gossipsub_rpc(doc, input_idx, &fixture) != 0) {
        goto cleanup;
    }
    built_ok = true;
    if (fixture.c_lean_unsupported_shape) {
        rc = record_info(path, codec_name, "c-lean-libp2p public gossipsub codec does not cover this fixture shape");
        goto cleanup;
    }
    rc = encode_gossipsub_rpc(&fixture.rpc, &actual);
    if (rc == FIXTURE_SKIPPED) {
        rc = record_info(path, codec_name, "c-lean-libp2p rejects this noncanonical gossipsub shape");
        goto cleanup;
    }
    if (rc != 0) {
        goto cleanup;
    }

    if (expect_bytes_equal(path, codec_name, "encoded", expected.data, expected.len, actual.data, actual.len) != 0) {
        rc = -1;
        goto cleanup;
    }

    if (expected.len == 0u) {
        rc = 0;
        goto cleanup;
    }

    libp2p_gossipsub_config_t config;
    libp2p_gossipsub_rpc_subscription_t decoded_subs[64];
    libp2p_gossipsub_message_t decoded_publish[16];
    libp2p_gossipsub_control_ihave_t decoded_ihave[32];
    libp2p_gossipsub_control_iwant_t decoded_iwant[32];
    libp2p_gossipsub_control_graft_t decoded_graft[32];
    libp2p_gossipsub_control_prune_t decoded_prune[32];
    libp2p_gossipsub_control_idontwant_t decoded_idontwant[32];
    libp2p_gossipsub_bytes_t decoded_ids[1024];
    libp2p_gossipsub_peer_info_t decoded_peers[32];
    libp2p_gossipsub_rpc_decode_storage_t decode_storage = {
        .subscriptions = decoded_subs,
        .subscription_capacity = sizeof(decoded_subs) / sizeof(decoded_subs[0]),
        .publish = decoded_publish,
        .publish_capacity = sizeof(decoded_publish) / sizeof(decoded_publish[0]),
        .ihave = decoded_ihave,
        .ihave_capacity = sizeof(decoded_ihave) / sizeof(decoded_ihave[0]),
        .iwant = decoded_iwant,
        .iwant_capacity = sizeof(decoded_iwant) / sizeof(decoded_iwant[0]),
        .graft = decoded_graft,
        .graft_capacity = sizeof(decoded_graft) / sizeof(decoded_graft[0]),
        .prune = decoded_prune,
        .prune_capacity = sizeof(decoded_prune) / sizeof(decoded_prune[0]),
        .idontwant = decoded_idontwant,
        .idontwant_capacity = sizeof(decoded_idontwant) / sizeof(decoded_idontwant[0]),
        .message_ids = decoded_ids,
        .message_id_capacity = sizeof(decoded_ids) / sizeof(decoded_ids[0]),
        .peer_infos = decoded_peers,
        .peer_info_capacity = sizeof(decoded_peers) / sizeof(decoded_peers[0]),
    };
    if (libp2p_gossipsub_config_default(&config) != LIBP2P_GOSSIPSUB_OK
        || libp2p_gossipsub_rpc_body_decode(
               LIBP2P_GOSSIPSUB_VERSION_12,
               &config.limits,
               expected.data,
               expected.len,
               &decode_storage,
               &decoded_fixture.rpc)
               != LIBP2P_GOSSIPSUB_OK) {
        rc = record_info(path, codec_name, "c-lean-libp2p rejects this decoded gossipsub shape");
        goto cleanup;
    }

    rc = encode_gossipsub_rpc(&decoded_fixture.rpc, &roundtrip);
    if (rc == FIXTURE_SKIPPED) {
        rc = record_info(path, codec_name, "c-lean-libp2p rejects this decoded gossipsub shape");
        goto cleanup;
    }
    if (rc != 0) {
        record_failure(path, codec_name, "failed to re-encode decoded RPC");
        rc = -1;
        goto cleanup;
    }

    rc = expect_bytes_equal(
        path,
        codec_name,
        "roundtrip",
        expected.data,
        expected.len,
        roundtrip.data,
        roundtrip.len);

cleanup:
    gossipsub_rpc_fixture_reset(&fixture);
    gossipsub_rpc_fixture_reset(&decoded_fixture);
    byte_buffer_reset(&expected);
    byte_buffer_reset(&actual);
    byte_buffer_reset(&roundtrip);
    if (rc != 0) {
        if (rc == FIXTURE_SKIPPED) {
            return rc;
        }
        if (!built_ok) {
            return record_failure(path, codec_name, "failed to build gossipsub RPC fixture");
        }
        return record_failure(path, codec_name, "gossipsub RPC fixture failed");
    }
    return rc;
}

static bool peer_id_key_type_is_secp256k1(const char *key_type) {
    return key_type && strcmp(key_type, "secp256k1") == 0;
}

static int run_peer_id_fixture(
    const char *path,
    const struct lantern_fixture_document *doc,
    int input_idx,
    int output_idx,
    const char *codec_name) {
    int key_type_idx = lantern_fixture_object_get_field(doc, input_idx, "keyType");
    int public_key_idx = lantern_fixture_object_get_field(doc, input_idx, "publicKey");
    int protobuf_idx = lantern_fixture_object_get_field(doc, output_idx, "protobufEncoded");
    int peer_id_idx = lantern_fixture_object_get_field(doc, output_idx, "peerId");
    char *key_type = NULL;
    char *expected_peer_id = NULL;
    struct byte_buffer public_key = {0};
    struct byte_buffer expected_pb = {0};
    uint8_t protobuf[LIBP2P_PEER_ID_SECP256K1_PUBLIC_KEY_MESSAGE_MAX_BYTES];
    size_t protobuf_len = 0u;
    struct lantern_peer_id peer = {0};
    struct lantern_peer_id roundtrip_peer = {0};
    char peer_id_text[256];
    int rc = -1;

    if (key_type_idx < 0 || public_key_idx < 0 || protobuf_idx < 0 || peer_id_idx < 0
        || fixture_token_to_c_string(doc, key_type_idx, &key_type) != 0
        || fixture_token_to_bytes(doc, public_key_idx, &public_key) != 0
        || fixture_token_to_bytes(doc, protobuf_idx, &expected_pb) != 0
        || fixture_token_to_c_string(doc, peer_id_idx, &expected_peer_id) != 0) {
        goto cleanup;
    }
    if (!peer_id_key_type_is_secp256k1(key_type)) {
        rc = record_info(path, codec_name, "c-lean-libp2p peer IDs are secp256k1-only");
        goto cleanup;
    }

    if (libp2p_peer_id_public_key_encode(
            public_key.data,
            public_key.len,
            protobuf,
            sizeof(protobuf),
            &protobuf_len)
        != LIBP2P_PEER_ID_OK) {
        record_failure(path, codec_name, "libp2p_peer_id_public_key_encode failed");
        rc = -1;
        goto cleanup;
    }
    if (expect_bytes_equal(path, codec_name, "protobuf", expected_pb.data, expected_pb.len, protobuf, protobuf_len) != 0) {
        rc = -1;
        goto cleanup;
    }

    if (libp2p_peer_id_from_secp256k1_public_key(
            public_key.data,
            public_key.len,
            peer.bytes,
            sizeof(peer.bytes),
            &peer.len)
        != LIBP2P_PEER_ID_OK) {
        record_failure(path, codec_name, "libp2p_peer_id_from_secp256k1_public_key failed");
        rc = -1;
        goto cleanup;
    }
    size_t peer_id_len = 0u;
    if (libp2p_peer_id_to_string(peer.bytes, peer.len, peer_id_text, sizeof(peer_id_text) - 1u, &peer_id_len)
        != LIBP2P_PEER_ID_OK) {
        record_failure(path, codec_name, "libp2p_peer_id_to_string failed");
        rc = -1;
        goto cleanup;
    }
    peer_id_text[peer_id_len] = '\0';
    if (strcmp(peer_id_text, expected_peer_id) != 0) {
        record_failure(
            path,
            codec_name,
            "peer ID mismatch actual=%s expected=%s",
            peer_id_text,
            expected_peer_id);
        rc = -1;
        goto cleanup;
    }

    if (libp2p_peer_id_from_string(
            expected_peer_id,
            strlen(expected_peer_id),
            roundtrip_peer.bytes,
            sizeof(roundtrip_peer.bytes),
            &roundtrip_peer.len)
        != LIBP2P_PEER_ID_OK) {
        record_failure(path, codec_name, "libp2p_peer_id_from_string failed");
        rc = -1;
        goto cleanup;
    }
    if (peer.len != roundtrip_peer.len || memcmp(peer.bytes, roundtrip_peer.bytes, peer.len) != 0) {
        record_failure(path, codec_name, "PeerId text roundtrip mismatch");
        rc = -1;
        goto cleanup;
    }

    rc = 0;

cleanup:
    free(key_type);
    free(expected_peer_id);
    byte_buffer_reset(&public_key);
    byte_buffer_reset(&expected_pb);
    if (rc != 0 && !key_type) {
        return record_failure(path, codec_name, "invalid peer_id fixture");
    }
    return rc;
}

static int run_snappy_block_fixture(
    const char *path,
    const struct lantern_fixture_document *doc,
    int input_idx,
    int output_idx,
    const char *codec_name) {
    int data_idx = lantern_fixture_object_get_field(doc, input_idx, "data");
    int compressed_idx = lantern_fixture_object_get_field(doc, output_idx, "compressed");
    int compressed_length_idx = lantern_fixture_object_get_field(doc, output_idx, "compressedLength");
    int uncompressed_length_idx = lantern_fixture_object_get_field(doc, output_idx, "uncompressedLength");

    struct byte_buffer data = {0};
    struct byte_buffer expected_compressed = {0};
    struct byte_buffer actual_compressed = {0};
    struct byte_buffer roundtrip = {0};
    uint64_t expected_compressed_length = 0u;
    uint64_t expected_uncompressed_length = 0u;
    int rc = -1;

    if (data_idx < 0 || compressed_idx < 0
        || compressed_length_idx < 0 || uncompressed_length_idx < 0
        || fixture_token_to_bytes(doc, data_idx, &data) != 0
        || fixture_token_to_bytes(doc, compressed_idx, &expected_compressed) != 0
        || lantern_fixture_token_to_uint64(doc, compressed_length_idx, &expected_compressed_length) != 0
        || lantern_fixture_token_to_uint64(doc, uncompressed_length_idx, &expected_uncompressed_length) != 0) {
        (void)record_failure(path, codec_name, "invalid snappy_block fixture payload");
        goto cleanup;
    }

    if (expect_uint64_equal(path, codec_name, "uncompressedLength",
            expected_uncompressed_length, (uint64_t)data.len) != 0) {
        goto cleanup;
    }
    if (expect_uint64_equal(path, codec_name, "compressedLength",
            expected_compressed_length, (uint64_t)expected_compressed.len) != 0) {
        goto cleanup;
    }

    size_t max_compressed = 0u;
    if (lantern_snappy_max_compressed_size_raw(data.len, &max_compressed) != LANTERN_SNAPPY_OK) {
        (void)record_failure(path, codec_name, "lantern_snappy_max_compressed_size_raw failed");
        goto cleanup;
    }
    actual_compressed.data = (uint8_t *)malloc(max_compressed > 0u ? max_compressed : 1u);
    if (!actual_compressed.data) {
        (void)record_failure(path, codec_name, "out of memory");
        goto cleanup;
    }
    size_t written = 0u;
    if (lantern_snappy_compress_raw(
            data.data, data.len, actual_compressed.data, max_compressed, &written)
        != LANTERN_SNAPPY_OK) {
        (void)record_failure(path, codec_name, "lantern_snappy_compress_raw failed");
        goto cleanup;
    }
    actual_compressed.len = written;

    if (expect_bytes_equal(path, codec_name, "compressed",
            expected_compressed.data, expected_compressed.len,
            actual_compressed.data, actual_compressed.len) != 0) {
        goto cleanup;
    }

    size_t decoded_length = 0u;
    if (lantern_snappy_uncompressed_length_raw(
            expected_compressed.data, expected_compressed.len, &decoded_length)
        != LANTERN_SNAPPY_OK) {
        (void)record_failure(path, codec_name, "lantern_snappy_uncompressed_length_raw failed");
        goto cleanup;
    }
    if (expect_uint64_equal(path, codec_name, "decoded uncompressedLength",
            (uint64_t)data.len, (uint64_t)decoded_length) != 0) {
        goto cleanup;
    }

    roundtrip.data = (uint8_t *)malloc(decoded_length > 0u ? decoded_length : 1u);
    if (!roundtrip.data) {
        (void)record_failure(path, codec_name, "out of memory");
        goto cleanup;
    }
    size_t decoded_written = 0u;
    if (lantern_snappy_decompress_raw(
            expected_compressed.data, expected_compressed.len,
            roundtrip.data, decoded_length, &decoded_written)
        != LANTERN_SNAPPY_OK) {
        (void)record_failure(path, codec_name, "lantern_snappy_decompress_raw failed");
        goto cleanup;
    }
    roundtrip.len = decoded_written;

    if (expect_bytes_equal(path, codec_name, "decoded payload",
            data.data, data.len, roundtrip.data, roundtrip.len) != 0) {
        goto cleanup;
    }

    rc = 0;

cleanup:
    byte_buffer_reset(&data);
    byte_buffer_reset(&expected_compressed);
    byte_buffer_reset(&actual_compressed);
    byte_buffer_reset(&roundtrip);
    return rc;
}

static int run_snappy_frame_fixture(
    const char *path,
    const struct lantern_fixture_document *doc,
    int input_idx,
    int output_idx,
    const char *codec_name) {
    int data_idx = lantern_fixture_object_get_field(doc, input_idx, "data");
    int framed_idx = lantern_fixture_object_get_field(doc, output_idx, "framed");
    int framed_length_idx = lantern_fixture_object_get_field(doc, output_idx, "framedLength");
    int uncompressed_length_idx = lantern_fixture_object_get_field(doc, output_idx, "uncompressedLength");

    struct byte_buffer data = {0};
    struct byte_buffer expected_framed = {0};
    struct byte_buffer actual_framed = {0};
    struct byte_buffer roundtrip = {0};
    uint64_t expected_framed_length = 0u;
    uint64_t expected_uncompressed_length = 0u;
    int rc = -1;

    if (data_idx < 0 || framed_idx < 0
        || framed_length_idx < 0 || uncompressed_length_idx < 0
        || fixture_token_to_bytes(doc, data_idx, &data) != 0
        || fixture_token_to_bytes(doc, framed_idx, &expected_framed) != 0
        || lantern_fixture_token_to_uint64(doc, framed_length_idx, &expected_framed_length) != 0
        || lantern_fixture_token_to_uint64(doc, uncompressed_length_idx, &expected_uncompressed_length) != 0) {
        (void)record_failure(path, codec_name, "invalid snappy_frame fixture payload");
        goto cleanup;
    }

    if (expect_uint64_equal(path, codec_name, "uncompressedLength",
            expected_uncompressed_length, (uint64_t)data.len) != 0) {
        goto cleanup;
    }
    if (expect_uint64_equal(path, codec_name, "framedLength",
            expected_framed_length, (uint64_t)expected_framed.len) != 0) {
        goto cleanup;
    }

    size_t max_framed = 0u;
    if (lantern_snappy_max_compressed_size(data.len, &max_framed) != LANTERN_SNAPPY_OK) {
        (void)record_failure(path, codec_name, "lantern_snappy_max_compressed_size failed");
        goto cleanup;
    }
    actual_framed.data = (uint8_t *)malloc(max_framed > 0u ? max_framed : 1u);
    if (!actual_framed.data) {
        (void)record_failure(path, codec_name, "out of memory");
        goto cleanup;
    }
    size_t written = 0u;
    if (lantern_snappy_compress(
            data.data, data.len, actual_framed.data, max_framed, &written)
        != LANTERN_SNAPPY_OK) {
        (void)record_failure(path, codec_name, "lantern_snappy_compress failed");
        goto cleanup;
    }
    actual_framed.len = written;

    if (expect_bytes_equal(path, codec_name, "framed",
            expected_framed.data, expected_framed.len,
            actual_framed.data, actual_framed.len) != 0) {
        goto cleanup;
    }

    size_t decoded_length = 0u;
    if (lantern_snappy_uncompressed_length(
            expected_framed.data, expected_framed.len, &decoded_length)
        != LANTERN_SNAPPY_OK) {
        (void)record_failure(path, codec_name, "lantern_snappy_uncompressed_length failed");
        goto cleanup;
    }
    if (expect_uint64_equal(path, codec_name, "decoded uncompressedLength",
            (uint64_t)data.len, (uint64_t)decoded_length) != 0) {
        goto cleanup;
    }

    roundtrip.data = (uint8_t *)malloc(decoded_length > 0u ? decoded_length : 1u);
    if (!roundtrip.data) {
        (void)record_failure(path, codec_name, "out of memory");
        goto cleanup;
    }
    size_t decoded_written = 0u;
    if (lantern_snappy_decompress(
            expected_framed.data, expected_framed.len,
            roundtrip.data, decoded_length, &decoded_written)
        != LANTERN_SNAPPY_OK) {
        (void)record_failure(path, codec_name, "lantern_snappy_decompress failed");
        goto cleanup;
    }
    roundtrip.len = decoded_written;

    if (expect_bytes_equal(path, codec_name, "decoded payload",
            data.data, data.len, roundtrip.data, roundtrip.len) != 0) {
        goto cleanup;
    }

    rc = 0;

cleanup:
    byte_buffer_reset(&data);
    byte_buffer_reset(&expected_framed);
    byte_buffer_reset(&actual_framed);
    byte_buffer_reset(&roundtrip);
    return rc;
}

static int run_unsupported_fixture(
    const char *path,
    const char *codec_name,
    struct fixture_stats *stats,
    const char *reason) {
    if (stats) {
        stats->unsupported += 1u;
    }
    return record_failure(path, codec_name, "%s", reason ? reason : "unsupported codec");
}

static int run_skipped_fixture(
    const char *path,
    const char *codec_name,
    struct fixture_stats *stats,
    const char *reason) {
    if (stats) {
        stats->unsupported += 1u;
    }
    return record_info(path, codec_name, "%s", reason ? reason : "skipped");
}

static uint32_t read_le24_local(const uint8_t *data) {
    return (uint32_t)data[0] | ((uint32_t)data[1] << 8u) | ((uint32_t)data[2] << 16u);
}

static bool snappy_frame_structure_valid(const uint8_t *input, size_t input_len) {
    static const uint8_t stream_identifier[] = {'s', 'N', 'a', 'P', 'p', 'Y'};
    if (!input || input_len < 4u) {
        return false;
    }

    size_t offset = 0u;
    uint8_t chunk_type = input[offset];
    uint32_t chunk_len = read_le24_local(input + offset + 1u);
    offset += 4u;
    if (chunk_type != 0xffu
        || chunk_len != sizeof(stream_identifier)
        || chunk_len > input_len - offset
        || memcmp(input + offset, stream_identifier, sizeof(stream_identifier)) != 0) {
        return false;
    }
    offset += chunk_len;

    while (offset < input_len) {
        if (input_len - offset < 4u) {
            return false;
        }
        chunk_type = input[offset];
        chunk_len = read_le24_local(input + offset + 1u);
        offset += 4u;
        if (chunk_len > input_len - offset) {
            return false;
        }

        if (chunk_type == 0xffu) {
            if (chunk_len != sizeof(stream_identifier)
                || memcmp(input + offset, stream_identifier, sizeof(stream_identifier)) != 0) {
                return false;
            }
        } else if (chunk_type >= 0x80u && chunk_type <= 0xfeu) {
            /* Skippable padding or extension chunk. */
        } else if (chunk_type == 0x00u || chunk_type == 0x01u) {
            if (chunk_len < 4u) {
                return false;
            }
        } else {
            return false;
        }
        offset += chunk_len;
    }

    return true;
}

static int run_decode_failure_fixture(
    const char *path,
    const struct lantern_fixture_document *doc,
    int input_idx,
    const char *codec_name,
    struct fixture_stats *stats) {
    int decoder_idx = lantern_fixture_object_get_field(doc, input_idx, "decoder");
    int bytes_idx = lantern_fixture_object_get_field(doc, input_idx, "bytes");
    if (bytes_idx < 0) {
        bytes_idx = lantern_fixture_object_get_field(doc, input_idx, "rawBytes");
    }
    char *decoder = NULL;
    struct byte_buffer bytes = {0};
    bool rejected = false;
    int rc = -1;

    if (decoder_idx < 0 || bytes_idx < 0
        || fixture_token_to_c_string(doc, decoder_idx, &decoder) != 0
        || fixture_token_to_bytes(doc, bytes_idx, &bytes) != 0) {
        rc = record_failure(path, codec_name, "invalid decode_failure fixture");
        goto cleanup;
    }

    if (strcmp(decoder, "discv5_message") == 0 || strcmp(decoder, "discv5_packet") == 0) {
        rc = run_skipped_fixture(path, codec_name, stats, "discv5 not implemented");
        goto cleanup;
    }

    if (strcmp(decoder, "varint") == 0) {
        uint64_t value = 0u;
        size_t consumed = 0u;
        rejected = lean_uvarint_decode(bytes.data, bytes.len, &value, &consumed) != 0;
    } else if (strcmp(decoder, "reqresp_request") == 0) {
        struct byte_buffer payload = {0};
        rejected = decode_reqresp_request(bytes.data, bytes.len, &payload) != 0;
        byte_buffer_reset(&payload);
    } else if (strcmp(decoder, "reqresp_response") == 0) {
        struct byte_buffer payload = {0};
        uint8_t response_code = 0u;
        rejected = decode_reqresp_response(bytes.data, bytes.len, &response_code, &payload) != 0;
        byte_buffer_reset(&payload);
    } else if (strcmp(decoder, "snappy_frame") == 0) {
        size_t decoded_length = 0u;
        if (!snappy_frame_structure_valid(bytes.data, bytes.len)) {
            rejected = true;
        } else if (lantern_snappy_uncompressed_length(bytes.data, bytes.len, &decoded_length) != LANTERN_SNAPPY_OK) {
            rejected = true;
        } else {
            uint8_t *decoded = (uint8_t *)malloc(decoded_length > 0u ? decoded_length : 1u);
            size_t written = 0u;
            rejected = !decoded
                || lantern_snappy_decompress(bytes.data, bytes.len, decoded, decoded_length, &written) != LANTERN_SNAPPY_OK;
            free(decoded);
        }
    } else if (strcmp(decoder, "gossipsub_rpc") == 0) {
        libp2p_gossipsub_config_t config;
        libp2p_gossipsub_rpc_subscription_t decoded_subs[4];
        libp2p_gossipsub_message_t decoded_publish[4];
        libp2p_gossipsub_control_ihave_t decoded_ihave[4];
        libp2p_gossipsub_control_iwant_t decoded_iwant[4];
        libp2p_gossipsub_control_graft_t decoded_graft[4];
        libp2p_gossipsub_control_prune_t decoded_prune[4];
        libp2p_gossipsub_control_idontwant_t decoded_idontwant[4];
        libp2p_gossipsub_bytes_t decoded_ids[16];
        libp2p_gossipsub_peer_info_t decoded_peers[4];
        libp2p_gossipsub_rpc_t rpc = {0};
        libp2p_gossipsub_rpc_decode_storage_t decode_storage = {
            .subscriptions = decoded_subs,
            .subscription_capacity = sizeof(decoded_subs) / sizeof(decoded_subs[0]),
            .publish = decoded_publish,
            .publish_capacity = sizeof(decoded_publish) / sizeof(decoded_publish[0]),
            .ihave = decoded_ihave,
            .ihave_capacity = sizeof(decoded_ihave) / sizeof(decoded_ihave[0]),
            .iwant = decoded_iwant,
            .iwant_capacity = sizeof(decoded_iwant) / sizeof(decoded_iwant[0]),
            .graft = decoded_graft,
            .graft_capacity = sizeof(decoded_graft) / sizeof(decoded_graft[0]),
            .prune = decoded_prune,
            .prune_capacity = sizeof(decoded_prune) / sizeof(decoded_prune[0]),
            .idontwant = decoded_idontwant,
            .idontwant_capacity = sizeof(decoded_idontwant) / sizeof(decoded_idontwant[0]),
            .message_ids = decoded_ids,
            .message_id_capacity = sizeof(decoded_ids) / sizeof(decoded_ids[0]),
            .peer_infos = decoded_peers,
            .peer_info_capacity = sizeof(decoded_peers) / sizeof(decoded_peers[0]),
        };
        rejected = libp2p_gossipsub_config_default(&config) != LIBP2P_GOSSIPSUB_OK
            || libp2p_gossipsub_rpc_body_decode(
                   LIBP2P_GOSSIPSUB_VERSION_12,
                   &config.limits,
                   bytes.data,
                   bytes.len,
                   &decode_storage,
                   &rpc)
                   != LIBP2P_GOSSIPSUB_OK;
    } else if (strcmp(decoder, "enr") == 0) {
        char *enr_text = NULL;
        struct lantern_enr_record record;
        bool record_ready = false;
        lantern_enr_record_init(&record);
        if (build_enr_text_from_rlp(bytes.data, bytes.len, &enr_text) != 0) {
            free(decoder);
            byte_buffer_reset(&bytes);
            return record_failure(path, codec_name, "failed to wrap ENR bytes");
        }
        if (lantern_enr_record_decode(enr_text, &record) != 0) {
            rejected = true;
        } else {
            record_ready = true;
        }
        if (record_ready) {
            lantern_enr_record_reset(&record);
        }
        free(enr_text);
    } else {
        rc = run_unsupported_fixture(path, codec_name, stats, "unknown decode_failure decoder");
        goto cleanup;
    }

    rc = rejected ? 0 : record_failure(path, codec_name, "decode unexpectedly succeeded for %s", decoder);

cleanup:
    free(decoder);
    byte_buffer_reset(&bytes);
    return rc;
}

static int run_reqresp_response_stream_fixture(
    const char *path,
    const struct lantern_fixture_document *doc,
    int input_idx,
    int output_idx,
    const char *codec_name) {
    int chunks_idx = lantern_fixture_object_get_field(doc, input_idx, "chunks");
    int encoded_idx = lantern_fixture_object_get_field(doc, output_idx, "encoded");
    int chunk_count_idx = lantern_fixture_object_get_field(doc, output_idx, "chunkCount");
    int chunk_count = chunks_idx >= 0 ? lantern_fixture_array_get_length(doc, chunks_idx) : -1;
    struct byte_buffer expected = {0};
    struct byte_buffer actual = {0};
    uint64_t expected_chunk_count = 0u;
    int rc = -1;

    if (chunks_idx < 0 || encoded_idx < 0 || chunk_count_idx < 0 || chunk_count < 0
        || fixture_token_to_bytes(doc, encoded_idx, &expected) != 0
        || lantern_fixture_token_to_uint64(doc, chunk_count_idx, &expected_chunk_count) != 0
        || expected_chunk_count != (uint64_t)chunk_count) {
        rc = record_failure(path, codec_name, "invalid reqresp_response_stream fixture");
        goto cleanup;
    }

    for (int i = 0; i < chunk_count; ++i) {
        int chunk_idx = lantern_fixture_array_get_element(doc, chunks_idx, i);
        int response_code_idx = chunk_idx >= 0 ? lantern_fixture_object_get_field(doc, chunk_idx, "responseCode") : -1;
        int ssz_data_idx = chunk_idx >= 0 ? lantern_fixture_object_get_field(doc, chunk_idx, "sszData") : -1;
        uint64_t response_code = 0u;
        struct byte_buffer payload = {0};
        struct byte_buffer frame = {0};
        int chunk_rc = response_code_idx >= 0
            && ssz_data_idx >= 0
            && lantern_fixture_token_to_uint64(doc, response_code_idx, &response_code) == 0
            && response_code <= UINT8_MAX
            && fixture_token_to_bytes(doc, ssz_data_idx, &payload) == 0
            && encode_reqresp_frame(payload.data, payload.len, (uint8_t)response_code, true, &frame) == 0
            && byte_buffer_append(&actual, frame.data, frame.len) == 0
            ? 0
            : -1;
        byte_buffer_reset(&payload);
        byte_buffer_reset(&frame);
        if (chunk_rc != 0) {
            rc = record_failure(path, codec_name, "failed to encode stream chunk");
            goto cleanup;
        }
    }

    rc = expect_bytes_equal(path, codec_name, "encoded", expected.data, expected.len, actual.data, actual.len);

cleanup:
    byte_buffer_reset(&expected);
    byte_buffer_reset(&actual);
    return rc;
}

static int run_xor_distance_fixture(
    const char *path,
    const struct lantern_fixture_document *doc,
    int input_idx,
    int output_idx,
    const char *codec_name) {
    int node_a_idx = lantern_fixture_object_get_field(doc, input_idx, "nodeA");
    int node_b_idx = lantern_fixture_object_get_field(doc, input_idx, "nodeB");
    int distance_idx = lantern_fixture_object_get_field(doc, output_idx, "distance");
    uint8_t node_a[32];
    uint8_t node_b[32];
    uint8_t expected[32];
    uint8_t actual[32];

    if (node_a_idx < 0 || node_b_idx < 0 || distance_idx < 0
        || fixture_token_to_uint256_be(doc, node_a_idx, node_a) != 0
        || fixture_token_to_uint256_be(doc, node_b_idx, node_b) != 0
        || fixture_token_to_uint256_be(doc, distance_idx, expected) != 0) {
        return record_failure(path, codec_name, "invalid xor_distance fixture");
    }
    for (size_t i = 0; i < sizeof(actual); ++i) {
        actual[i] = (uint8_t)(node_a[i] ^ node_b[i]);
    }
    return expect_bytes_equal(path, codec_name, "distance", expected, sizeof(expected), actual, sizeof(actual));
}

static int run_log2_distance_fixture(
    const char *path,
    const struct lantern_fixture_document *doc,
    int input_idx,
    int output_idx,
    const char *codec_name) {
    int node_a_idx = lantern_fixture_object_get_field(doc, input_idx, "nodeA");
    int node_b_idx = lantern_fixture_object_get_field(doc, input_idx, "nodeB");
    int distance_idx = lantern_fixture_object_get_field(doc, output_idx, "distance");
    uint8_t node_a[32];
    uint8_t node_b[32];
    uint64_t expected = 0u;
    uint64_t actual = 0u;

    if (node_a_idx < 0 || node_b_idx < 0 || distance_idx < 0
        || fixture_token_to_uint256_be(doc, node_a_idx, node_a) != 0
        || fixture_token_to_uint256_be(doc, node_b_idx, node_b) != 0
        || lantern_fixture_token_to_uint64(doc, distance_idx, &expected) != 0) {
        return record_failure(path, codec_name, "invalid log2_distance fixture");
    }

    for (size_t i = 0; i < sizeof(node_a); ++i) {
        uint8_t distance_byte = (uint8_t)(node_a[i] ^ node_b[i]);
        if (distance_byte == 0u) {
            continue;
        }
        unsigned int highest_bit = 0u;
        while (distance_byte != 0u) {
            ++highest_bit;
            distance_byte >>= 1u;
        }
        actual = (uint64_t)((31u - i) * 8u + highest_bit);
        break;
    }
    return expect_uint64_equal(path, codec_name, "distance", expected, actual);
}

static int run_fixture_file(const char *path, void *user_data) {
    struct fixture_stats *stats = (struct fixture_stats *)user_data;
    struct lantern_fixture_document doc;
    memset(&doc, 0, sizeof(doc));

    char *text = NULL;
    if (lantern_fixture_read_text_file(path, &text) != 0) {
        if (stats) {
            stats->total += 1u;
            stats->failed += 1u;
        }
        (void)record_failure(path, NULL, "failed to read fixture");
        return 0;
    }
    if (lantern_fixture_document_init(&doc, text) != 0) {
        if (stats) {
            stats->total += 1u;
            stats->failed += 1u;
        }
        lantern_fixture_document_reset(&doc);
        (void)record_failure(path, NULL, "failed to parse JSON fixture");
        return 0;
    }

    int case_idx = lantern_fixture_object_get_value_at(&doc, 0, 0);
    int codec_name_idx = case_idx >= 0 ? lantern_fixture_object_get_field(&doc, case_idx, "codecName") : -1;
    int codec_object_idx = case_idx >= 0 ? lantern_fixture_object_get_field(&doc, case_idx, "codec") : -1;
    int input_idx = case_idx >= 0 ? lantern_fixture_object_get_field(&doc, case_idx, "input") : -1;
    int output_idx = case_idx >= 0 ? lantern_fixture_object_get_field(&doc, case_idx, "output") : -1;

    char *codec_name = NULL;
    int rc = -1;
    if (codec_name_idx < 0 && codec_object_idx >= 0) {
        codec_name_idx = lantern_fixture_object_get_field(&doc, codec_object_idx, "kind");
        input_idx = codec_object_idx;
    }

    if (case_idx < 0 || codec_name_idx < 0 || input_idx < 0 || output_idx < 0
        || fixture_token_to_c_string(&doc, codec_name_idx, &codec_name) != 0) {
        if (stats) {
            stats->total += 1u;
            stats->failed += 1u;
        }
        lantern_fixture_document_reset(&doc);
        free(codec_name);
        (void)record_failure(path, NULL, "fixture missing codecName/input/output");
        return 0;
    }

    if (stats) {
        stats->total += 1u;
    }

    if (strcmp(codec_name, "varint") == 0) {
        rc = run_varint_fixture(path, &doc, input_idx, output_idx, codec_name);
    } else if (strcmp(codec_name, "decode_failure") == 0) {
        rc = run_decode_failure_fixture(path, &doc, input_idx, codec_name, stats);
    } else if (strcmp(codec_name, "reqresp_request") == 0) {
        rc = run_reqresp_request_fixture(path, &doc, input_idx, output_idx, codec_name);
    } else if (strcmp(codec_name, "reqresp_response") == 0) {
        rc = run_reqresp_response_fixture(path, &doc, input_idx, output_idx, codec_name);
    } else if (strcmp(codec_name, "reqresp_response_stream") == 0) {
        rc = run_reqresp_response_stream_fixture(path, &doc, input_idx, output_idx, codec_name);
    } else if (strcmp(codec_name, "gossip_topic") == 0) {
        rc = run_gossip_topic_fixture(path, &doc, input_idx, output_idx, codec_name);
    } else if (strcmp(codec_name, "gossip_message_id") == 0) {
        rc = run_gossip_message_id_fixture(path, &doc, input_idx, output_idx, codec_name);
    } else if (strcmp(codec_name, "gossipsub_rpc") == 0) {
        rc = run_gossipsub_rpc_fixture(path, &doc, input_idx, output_idx, codec_name);
    } else if (strcmp(codec_name, "peer_id") == 0) {
        rc = run_peer_id_fixture(path, &doc, input_idx, output_idx, codec_name);
    } else if (strcmp(codec_name, "enr") == 0) {
        rc = run_enr_fixture(path, &doc, input_idx, output_idx, codec_name);
    } else if (strcmp(codec_name, "snappy_block") == 0) {
        rc = run_snappy_block_fixture(path, &doc, input_idx, output_idx, codec_name);
    } else if (strcmp(codec_name, "snappy_frame") == 0) {
        rc = run_snappy_frame_fixture(path, &doc, input_idx, output_idx, codec_name);
    } else if (strcmp(codec_name, "xor_distance") == 0) {
        rc = run_xor_distance_fixture(path, &doc, input_idx, output_idx, codec_name);
    } else if (strcmp(codec_name, "log2_distance") == 0) {
        rc = run_log2_distance_fixture(path, &doc, input_idx, output_idx, codec_name);
    } else if (strcmp(codec_name, "discv5_message") == 0 || strcmp(codec_name, "discv5_packet") == 0) {
        rc = run_skipped_fixture(
            path,
            codec_name,
            stats,
            "discv5 not implemented");
    } else {
        rc = run_unsupported_fixture(path, codec_name, stats, "unknown codecName");
    }

    if (stats) {
        if (rc == 0) {
            stats->passed += 1u;
        } else if (rc < 0) {
            stats->failed += 1u;
        }
    }

    lantern_fixture_document_reset(&doc);
    free(codec_name);
    return 0;
}

int main(void) {
    char fixture_root[PATH_MAX];
    if (build_fixture_root(fixture_root, sizeof(fixture_root)) != 0) {
        fprintf(stderr, "networking codec fixture path too long\n");
        return 1;
    }

    struct fixture_stats stats = {0};
    if (for_each_json(fixture_root, run_fixture_file, &stats) != 0) {
        fprintf(stderr, "networking codec fixture walk failed\n");
        return 1;
    }

    fprintf(
        stderr,
        "lantern_networking_codec_vectors: total=%zu passed=%zu failed=%zu unsupported=%zu\n",
        stats.total,
        stats.passed,
        stats.failed,
        stats.unsupported);
    fflush(stderr);
    return stats.failed == 0u ? 0 : 1;
}
