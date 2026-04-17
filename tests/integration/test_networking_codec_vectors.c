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

#include "external/c-libp2p/include/multiformats/unsigned_varint/unsigned_varint.h"
#include "external/c-libp2p/include/peer_id/peer_id.h"
#include "external/c-libp2p/include/peer_id/peer_id_proto.h"
#include "external/c-libp2p/src/protocol/gossipsub/core/gossipsub_rpc.h"
#include "external/c-libp2p/src/protocol/gossipsub/proto/gen/gossipsub_rpc.pb.h"
#include "external/c-libp2p/src/protocol/gossipsub/proto/gossipsub_proto.h"
#include "lantern/encoding/snappy.h"
#include "lantern/networking/enr.h"
#include "lantern/networking/gossip.h"
#include "lantern/networking/messages.h"
#include "multiformats/multibase/encoding/base64_url.h"

#include <noise/protobufs.h>

#ifndef LANTERN_CONSENSUS_FIXTURE_DIR
#define LANTERN_CONSENSUS_FIXTURE_DIR "tools/leanSpec/fixtures/consensus"
#endif

#define NETWORKING_CODEC_FIXTURE_SUBDIR "networking_codec/devnet/networking"
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
    if (unsigned_varint_encode(payload_len, header, sizeof(header), &header_len) != UNSIGNED_VARINT_OK) {
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
    if (unsigned_varint_decode(frame, frame_len, &declared_len, &consumed) != UNSIGNED_VARINT_OK) {
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
    const libp2p_gossipsub_RPC *rpc,
    struct byte_buffer *out_bytes) {
    if (!rpc || !out_bytes) {
        return -1;
    }
    byte_buffer_reset(out_bytes);

    gossipsub_rpc_out_t out = {0};
    if (gossipsub_rpc_encode(rpc, &out) != LIBP2P_ERR_OK) {
        gossipsub_rpc_out_clear(&out);
        return -1;
    }

    out_bytes->data = out.frame;
    out_bytes->len = out.frame_len;
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

    uint8_t *decoded = (uint8_t *)malloc(payload_len);
    if (!decoded) {
        return -1;
    }
    int written = multibase_base64_url_decode(payload, payload_len, decoded, payload_len);
    if (written < 0) {
        free(decoded);
        return -1;
    }
    out_rlp->data = decoded;
    out_rlp->len = (size_t)written;
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

static int parse_message_id_array(
    const struct lantern_fixture_document *doc,
    int array_index,
    int (*append_fn)(void *obj, const void *value, size_t size),
    void *obj) {
    if (!doc || array_index < 0 || !append_fn || !obj) {
        return -1;
    }
    int count = lantern_fixture_array_get_length(doc, array_index);
    if (count < 0) {
        return -1;
    }
    for (int i = 0; i < count; ++i) {
        int element_idx = lantern_fixture_array_get_element(doc, array_index, i);
        struct byte_buffer id = {0};
        if (element_idx < 0 || fixture_token_to_bytes(doc, element_idx, &id) != 0) {
            byte_buffer_reset(&id);
            return -1;
        }
        if (append_fn(obj, id.data, id.len) != NOISE_ERROR_NONE) {
            byte_buffer_reset(&id);
            return -1;
        }
        byte_buffer_reset(&id);
    }
    return 0;
}

static int build_gossipsub_rpc(
    const struct lantern_fixture_document *doc,
    int input_idx,
    libp2p_gossipsub_RPC **out_rpc) {
    if (!doc || input_idx < 0 || !out_rpc) {
        return -1;
    }
    *out_rpc = NULL;

    libp2p_gossipsub_RPC *rpc = NULL;
    if (libp2p_gossipsub_RPC_new(&rpc) != NOISE_ERROR_NONE || !rpc) {
        return -1;
    }

    int subscriptions_idx = lantern_fixture_object_get_field(doc, input_idx, "subscriptions");
    if (subscriptions_idx >= 0) {
        int count = lantern_fixture_array_get_length(doc, subscriptions_idx);
        if (count < 0) {
            libp2p_gossipsub_RPC_free(rpc);
            return -1;
        }
        for (int i = 0; i < count; ++i) {
            int sub_idx = lantern_fixture_array_get_element(doc, subscriptions_idx, i);
            libp2p_gossipsub_RPC_SubOpts *sub = NULL;
            bool subscribe = false;
            int subscribe_idx = -1;
            int topic_idx = -1;
            char *topic = NULL;

            if (sub_idx < 0) {
                libp2p_gossipsub_RPC_free(rpc);
                return -1;
            }
            if (libp2p_gossipsub_RPC_add_subscriptions(rpc, &sub) != NOISE_ERROR_NONE || !sub) {
                libp2p_gossipsub_RPC_free(rpc);
                return -1;
            }

            subscribe_idx = lantern_fixture_object_get_field(doc, sub_idx, "subscribe");
            topic_idx = lantern_fixture_object_get_field(doc, sub_idx, "topicId");
            if (subscribe_idx < 0 || topic_idx < 0
                || fixture_token_to_bool(doc, subscribe_idx, &subscribe) != 0
                || fixture_token_to_c_string(doc, topic_idx, &topic) != 0) {
                free(topic);
                libp2p_gossipsub_RPC_free(rpc);
                return -1;
            }

            if (libp2p_gossipsub_RPC_SubOpts_set_subscribe(sub, subscribe ? 1 : 0) != NOISE_ERROR_NONE
                || libp2p_gossipsub_RPC_SubOpts_set_topic(sub, topic, strlen(topic)) != NOISE_ERROR_NONE) {
                free(topic);
                libp2p_gossipsub_RPC_free(rpc);
                return -1;
            }
            free(topic);
        }
    }

    int publish_idx = lantern_fixture_object_get_field(doc, input_idx, "publish");
    if (publish_idx >= 0) {
        int count = lantern_fixture_array_get_length(doc, publish_idx);
        if (count < 0) {
            libp2p_gossipsub_RPC_free(rpc);
            return -1;
        }
        for (int i = 0; i < count; ++i) {
            int message_idx = lantern_fixture_array_get_element(doc, publish_idx, i);
            libp2p_gossipsub_Message *message = NULL;
            if (message_idx < 0
                || libp2p_gossipsub_RPC_add_publish(rpc, &message) != NOISE_ERROR_NONE
                || !message) {
                libp2p_gossipsub_RPC_free(rpc);
                return -1;
            }

            const struct {
                const char *field;
                int (*setter)(libp2p_gossipsub_Message *, const void *, size_t);
                bool hex_bytes;
            } byte_fields[] = {
                {"fromPeer", libp2p_gossipsub_Message_set_from, true},
                {"data", libp2p_gossipsub_Message_set_data, true},
                {"seqno", libp2p_gossipsub_Message_set_seqno, true},
                {"signature", libp2p_gossipsub_Message_set_signature, true},
                {"key", libp2p_gossipsub_Message_set_key, true},
            };

            for (size_t field = 0; field < sizeof(byte_fields) / sizeof(byte_fields[0]); ++field) {
                int field_idx = lantern_fixture_object_get_field(doc, message_idx, byte_fields[field].field);
                if (field_idx < 0) {
                    continue;
                }
                struct byte_buffer data = {0};
                if (fixture_token_to_bytes(doc, field_idx, &data) != 0
                    || byte_fields[field].setter(message, data.data, data.len) != NOISE_ERROR_NONE) {
                    byte_buffer_reset(&data);
                    libp2p_gossipsub_RPC_free(rpc);
                    return -1;
                }
                byte_buffer_reset(&data);
            }

            int topic_idx = lantern_fixture_object_get_field(doc, message_idx, "topic");
            if (topic_idx >= 0) {
                char *topic = NULL;
                if (fixture_token_to_c_string(doc, topic_idx, &topic) != 0
                    || libp2p_gossipsub_Message_set_topic(message, topic, strlen(topic)) != NOISE_ERROR_NONE) {
                    free(topic);
                    libp2p_gossipsub_RPC_free(rpc);
                    return -1;
                }
                free(topic);
            }
        }
    }

    int control_idx = lantern_fixture_object_get_field(doc, input_idx, "control");
    if (control_idx >= 0) {
        struct {
            const char *name;
            int field_idx;
        } control_fields[5] = {
            {"ihave", lantern_fixture_object_get_field(doc, control_idx, "ihave")},
            {"iwant", lantern_fixture_object_get_field(doc, control_idx, "iwant")},
            {"graft", lantern_fixture_object_get_field(doc, control_idx, "graft")},
            {"prune", lantern_fixture_object_get_field(doc, control_idx, "prune")},
            {"idontwant", lantern_fixture_object_get_field(doc, control_idx, "idontwant")},
        };

        bool has_control = false;
        for (size_t i = 0; i < sizeof(control_fields) / sizeof(control_fields[0]); ++i) {
            if (control_fields[i].field_idx >= 0
                && lantern_fixture_array_get_length(doc, control_fields[i].field_idx) > 0) {
                has_control = true;
                break;
            }
        }

        if (has_control) {
            libp2p_gossipsub_ControlMessage *control = NULL;
            if (libp2p_gossipsub_RPC_get_new_control(rpc, &control) != NOISE_ERROR_NONE || !control) {
                libp2p_gossipsub_RPC_free(rpc);
                return -1;
            }

            int ihave_idx = lantern_fixture_object_get_field(doc, control_idx, "ihave");
            if (ihave_idx >= 0) {
                int count = lantern_fixture_array_get_length(doc, ihave_idx);
                if (count < 0) {
                    libp2p_gossipsub_RPC_free(rpc);
                    return -1;
                }
                for (int i = 0; i < count; ++i) {
                    int entry_idx = lantern_fixture_array_get_element(doc, ihave_idx, i);
                    int topic_idx = lantern_fixture_object_get_field(doc, entry_idx, "topicId");
                    int ids_idx = lantern_fixture_object_get_field(doc, entry_idx, "messageIds");
                    libp2p_gossipsub_ControlIHave *ihave = NULL;
                    char *topic = NULL;
                    if (entry_idx < 0 || topic_idx < 0 || ids_idx < 0
                        || libp2p_gossipsub_ControlMessage_add_ihave(control, &ihave) != NOISE_ERROR_NONE
                        || !ihave
                        || fixture_token_to_c_string(doc, topic_idx, &topic) != 0
                        || libp2p_gossipsub_ControlIHave_set_topic(ihave, topic, strlen(topic)) != NOISE_ERROR_NONE
                        || parse_message_id_array(
                               doc,
                               ids_idx,
                               (int (*)(void *, const void *, size_t))libp2p_gossipsub_ControlIHave_add_message_ids,
                               ihave)
                               != 0) {
                        free(topic);
                        libp2p_gossipsub_RPC_free(rpc);
                        return -1;
                    }
                    free(topic);
                }
            }

            int iwant_idx = lantern_fixture_object_get_field(doc, control_idx, "iwant");
            if (iwant_idx >= 0) {
                int count = lantern_fixture_array_get_length(doc, iwant_idx);
                if (count < 0) {
                    libp2p_gossipsub_RPC_free(rpc);
                    return -1;
                }
                for (int i = 0; i < count; ++i) {
                    int entry_idx = lantern_fixture_array_get_element(doc, iwant_idx, i);
                    int ids_idx = lantern_fixture_object_get_field(doc, entry_idx, "messageIds");
                    libp2p_gossipsub_ControlIWant *iwant = NULL;
                    if (entry_idx < 0 || ids_idx < 0
                        || libp2p_gossipsub_ControlMessage_add_iwant(control, &iwant) != NOISE_ERROR_NONE
                        || !iwant
                        || parse_message_id_array(
                               doc,
                               ids_idx,
                               (int (*)(void *, const void *, size_t))libp2p_gossipsub_ControlIWant_add_message_ids,
                               iwant)
                               != 0) {
                        libp2p_gossipsub_RPC_free(rpc);
                        return -1;
                    }
                }
            }

            int graft_idx = lantern_fixture_object_get_field(doc, control_idx, "graft");
            if (graft_idx >= 0) {
                int count = lantern_fixture_array_get_length(doc, graft_idx);
                if (count < 0) {
                    libp2p_gossipsub_RPC_free(rpc);
                    return -1;
                }
                for (int i = 0; i < count; ++i) {
                    int entry_idx = lantern_fixture_array_get_element(doc, graft_idx, i);
                    int topic_idx = lantern_fixture_object_get_field(doc, entry_idx, "topicId");
                    libp2p_gossipsub_ControlGraft *graft = NULL;
                    char *topic = NULL;
                    if (entry_idx < 0 || topic_idx < 0
                        || libp2p_gossipsub_ControlMessage_add_graft(control, &graft) != NOISE_ERROR_NONE
                        || !graft
                        || fixture_token_to_c_string(doc, topic_idx, &topic) != 0
                        || (topic[0] != '\0'
                            && libp2p_gossipsub_ControlGraft_set_topic(graft, topic, strlen(topic))
                                   != NOISE_ERROR_NONE)) {
                        free(topic);
                        libp2p_gossipsub_RPC_free(rpc);
                        return -1;
                    }
                    free(topic);
                }
            }

            int prune_idx = lantern_fixture_object_get_field(doc, control_idx, "prune");
            if (prune_idx >= 0) {
                int count = lantern_fixture_array_get_length(doc, prune_idx);
                if (count < 0) {
                    libp2p_gossipsub_RPC_free(rpc);
                    return -1;
                }
                for (int i = 0; i < count; ++i) {
                    int entry_idx = lantern_fixture_array_get_element(doc, prune_idx, i);
                    int topic_idx = lantern_fixture_object_get_field(doc, entry_idx, "topicId");
                    int backoff_idx = lantern_fixture_object_get_field(doc, entry_idx, "backoff");
                    int peers_idx = lantern_fixture_object_get_field(doc, entry_idx, "peers");
                    libp2p_gossipsub_ControlPrune *prune = NULL;
                    char *topic = NULL;
                    if (entry_idx < 0 || topic_idx < 0
                        || libp2p_gossipsub_ControlMessage_add_prune(control, &prune) != NOISE_ERROR_NONE
                        || !prune
                        || fixture_token_to_c_string(doc, topic_idx, &topic) != 0
                        || libp2p_gossipsub_ControlPrune_set_topic(prune, topic, strlen(topic))
                               != NOISE_ERROR_NONE) {
                        free(topic);
                        libp2p_gossipsub_RPC_free(rpc);
                        return -1;
                    }
                    free(topic);

                    if (backoff_idx >= 0) {
                        uint64_t backoff = 0u;
                        if (lantern_fixture_token_to_uint64(doc, backoff_idx, &backoff) != 0
                            || libp2p_gossipsub_ControlPrune_set_backoff(prune, backoff) != NOISE_ERROR_NONE) {
                            libp2p_gossipsub_RPC_free(rpc);
                            return -1;
                        }
                    }

                    if (peers_idx >= 0) {
                        int peer_count = lantern_fixture_array_get_length(doc, peers_idx);
                        if (peer_count < 0) {
                            libp2p_gossipsub_RPC_free(rpc);
                            return -1;
                        }
                        for (int peer_i = 0; peer_i < peer_count; ++peer_i) {
                            int peer_idx = lantern_fixture_array_get_element(doc, peers_idx, peer_i);
                            int peer_id_idx = lantern_fixture_object_get_field(doc, peer_idx, "peerId");
                            int record_idx = lantern_fixture_object_get_field(doc, peer_idx, "signedPeerRecord");
                            libp2p_gossipsub_PeerInfo *peer = NULL;
                            struct byte_buffer peer_id = {0};
                            struct byte_buffer signed_record = {0};
                            if (peer_idx < 0 || peer_id_idx < 0
                                || libp2p_gossipsub_ControlPrune_add_peers(prune, &peer) != NOISE_ERROR_NONE
                                || !peer
                                || fixture_token_to_bytes(doc, peer_id_idx, &peer_id) != 0
                                || libp2p_gossipsub_PeerInfo_set_peer_id(peer, peer_id.data, peer_id.len)
                                       != NOISE_ERROR_NONE) {
                                byte_buffer_reset(&peer_id);
                                byte_buffer_reset(&signed_record);
                                libp2p_gossipsub_RPC_free(rpc);
                                return -1;
                            }
                            if (record_idx >= 0) {
                                if (fixture_token_to_bytes(doc, record_idx, &signed_record) != 0
                                    || libp2p_gossipsub_PeerInfo_set_signed_peer_record(
                                           peer,
                                           signed_record.data,
                                           signed_record.len)
                                           != NOISE_ERROR_NONE) {
                                    byte_buffer_reset(&peer_id);
                                    byte_buffer_reset(&signed_record);
                                    libp2p_gossipsub_RPC_free(rpc);
                                    return -1;
                                }
                            }
                            byte_buffer_reset(&peer_id);
                            byte_buffer_reset(&signed_record);
                        }
                    }
                }
            }

            int idontwant_idx = lantern_fixture_object_get_field(doc, control_idx, "idontwant");
            if (idontwant_idx >= 0) {
                int count = lantern_fixture_array_get_length(doc, idontwant_idx);
                if (count < 0) {
                    libp2p_gossipsub_RPC_free(rpc);
                    return -1;
                }
                for (int i = 0; i < count; ++i) {
                    int entry_idx = lantern_fixture_array_get_element(doc, idontwant_idx, i);
                    int ids_idx = lantern_fixture_object_get_field(doc, entry_idx, "messageIds");
                    libp2p_gossipsub_ControlIDontWant *idontwant = NULL;
                    if (entry_idx < 0 || ids_idx < 0
                        || libp2p_gossipsub_ControlMessage_add_idontwant(control, &idontwant) != NOISE_ERROR_NONE
                        || !idontwant
                        || parse_message_id_array(
                               doc,
                               ids_idx,
                               (int (*)(void *, const void *, size_t))libp2p_gossipsub_ControlIDontWant_add_message_ids,
                               idontwant)
                               != 0) {
                        libp2p_gossipsub_RPC_free(rpc);
                        return -1;
                    }
                }
            }
        }
    }

    *out_rpc = rpc;
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
    if (unsigned_varint_encode(value, encoded, sizeof(encoded), &encoded_len) != UNSIGNED_VARINT_OK) {
        byte_buffer_reset(&expected);
        return record_failure(path, codec_name, "unsigned_varint_encode failed for value=%" PRIu64, value);
    }
    if (encoded_len != expected_length
        || expect_bytes_equal(path, codec_name, "encoded", expected.data, expected.len, encoded, encoded_len) != 0) {
        byte_buffer_reset(&expected);
        return -1;
    }

    uint64_t decoded = 0u;
    size_t consumed = 0u;
    if (unsigned_varint_decode(encoded, encoded_len, &decoded, &consumed) != UNSIGNED_VARINT_OK) {
        byte_buffer_reset(&expected);
        return record_failure(path, codec_name, "unsigned_varint_decode failed");
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
    int kind_idx = lantern_fixture_object_get_field(doc, input_idx, "kind");
    int digest_idx = lantern_fixture_object_get_field(doc, input_idx, "forkDigest");
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
    libp2p_gossipsub_RPC *rpc = NULL;
    libp2p_gossipsub_RPC *decoded_rpc = NULL;
    struct byte_buffer expected = {0};
    struct byte_buffer actual = {0};
    struct byte_buffer roundtrip = {0};
    int rc = -1;

    if (encoded_idx < 0
        || fixture_token_to_bytes(doc, encoded_idx, &expected) != 0
        || build_gossipsub_rpc(doc, input_idx, &rpc) != 0
        || !rpc
        || encode_gossipsub_rpc(rpc, &actual) != 0) {
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

    if (libp2p_gossipsub_rpc_decode_frame(expected.data, expected.len, &decoded_rpc) != LIBP2P_ERR_OK || !decoded_rpc) {
        record_failure(path, codec_name, "libp2p_gossipsub_rpc_decode_frame failed");
        rc = -1;
        goto cleanup;
    }

    if (encode_gossipsub_rpc(decoded_rpc, &roundtrip) != 0) {
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
    /* Some partially-populated protobuf objects from the vendored libp2p
     * generator currently trip assertions during free on failure paths.
     * This short-lived fixture runner prefers a small leak over aborting and
     * hiding the actual codec mismatch we want to report. */
    byte_buffer_reset(&expected);
    byte_buffer_reset(&actual);
    byte_buffer_reset(&roundtrip);
    if (rc != 0) {
        if (!rpc) {
            return record_failure(path, codec_name, "failed to build gossipsub RPC fixture");
        }
        return record_failure(path, codec_name, "gossipsub RPC fixture failed");
    }
    return rc;
}

static int peer_id_key_type_from_string(const char *key_type, uint64_t *out_key_type) {
    if (!key_type || !out_key_type) {
        return -1;
    }
    if (strcmp(key_type, "rsa") == 0) {
        *out_key_type = PEER_ID_KEY_RSA;
        return 0;
    }
    if (strcmp(key_type, "ed25519") == 0) {
        *out_key_type = PEER_ID_KEY_ED25519;
        return 0;
    }
    if (strcmp(key_type, "secp256k1") == 0) {
        *out_key_type = PEER_ID_KEY_SECP256K1;
        return 0;
    }
    if (strcmp(key_type, "ecdsa") == 0) {
        *out_key_type = PEER_ID_KEY_ECDSA;
        return 0;
    }
    return -1;
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
    uint8_t *protobuf = NULL;
    size_t protobuf_len = 0u;
    uint64_t peer_key_type = 0u;
    peer_id_t *peer = NULL;
    peer_id_t *roundtrip_peer = NULL;
    char peer_id_text[256];
    size_t peer_id_len = 0u;
    int rc = -1;

    if (key_type_idx < 0 || public_key_idx < 0 || protobuf_idx < 0 || peer_id_idx < 0
        || fixture_token_to_c_string(doc, key_type_idx, &key_type) != 0
        || fixture_token_to_bytes(doc, public_key_idx, &public_key) != 0
        || fixture_token_to_bytes(doc, protobuf_idx, &expected_pb) != 0
        || fixture_token_to_c_string(doc, peer_id_idx, &expected_peer_id) != 0
        || peer_id_key_type_from_string(key_type, &peer_key_type) != 0) {
        goto cleanup;
    }

    if (peer_id_build_public_key_protobuf(peer_key_type, public_key.data, public_key.len, &protobuf, &protobuf_len)
        != PEER_ID_OK
        || !protobuf) {
        record_failure(path, codec_name, "peer_id_build_public_key_protobuf failed");
        rc = -1;
        goto cleanup;
    }
    if (expect_bytes_equal(path, codec_name, "protobuf", expected_pb.data, expected_pb.len, protobuf, protobuf_len) != 0) {
        rc = -1;
        goto cleanup;
    }

    if (peer_id_new_from_public_key_pb(protobuf, protobuf_len, &peer) != PEER_ID_OK || !peer) {
        record_failure(path, codec_name, "peer_id_new_from_public_key_pb failed");
        rc = -1;
        goto cleanup;
    }
    if (peer_id_text_write(
            peer,
            PEER_ID_TEXT_LEGACY_BASE58,
            peer_id_text,
            sizeof(peer_id_text),
            &peer_id_len)
        != PEER_ID_OK) {
        record_failure(path, codec_name, "peer_id_text_write failed");
        rc = -1;
        goto cleanup;
    }
    if (strlen(expected_peer_id) != peer_id_len || strcmp(peer_id_text, expected_peer_id) != 0) {
        record_failure(
            path,
            codec_name,
            "peer ID mismatch actual=%s expected=%s",
            peer_id_text,
            expected_peer_id);
        rc = -1;
        goto cleanup;
    }

    if (peer_id_new_from_text(expected_peer_id, &roundtrip_peer) != PEER_ID_OK || !roundtrip_peer) {
        record_failure(path, codec_name, "peer_id_new_from_text failed");
        rc = -1;
        goto cleanup;
    }
    if (!peer_id_equal(peer, roundtrip_peer)) {
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
    free(protobuf);
    peer_id_free(peer);
    peer_id_free(roundtrip_peer);
    if (rc != 0 && !key_type) {
        return record_failure(path, codec_name, "invalid peer_id fixture");
    }
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
    int codec_idx = case_idx >= 0 ? lantern_fixture_object_get_field(&doc, case_idx, "codecName") : -1;
    int input_idx = case_idx >= 0 ? lantern_fixture_object_get_field(&doc, case_idx, "input") : -1;
    int output_idx = case_idx >= 0 ? lantern_fixture_object_get_field(&doc, case_idx, "output") : -1;

    char *codec_name = NULL;
    int rc = -1;

    if (case_idx < 0 || codec_idx < 0 || input_idx < 0 || output_idx < 0
        || fixture_token_to_c_string(&doc, codec_idx, &codec_name) != 0) {
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
    } else if (strcmp(codec_name, "reqresp_request") == 0) {
        rc = run_reqresp_request_fixture(path, &doc, input_idx, output_idx, codec_name);
    } else if (strcmp(codec_name, "reqresp_response") == 0) {
        rc = run_reqresp_response_fixture(path, &doc, input_idx, output_idx, codec_name);
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
    } else if (strcmp(codec_name, "discv5_message") == 0) {
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
