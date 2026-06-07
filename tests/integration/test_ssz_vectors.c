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

#include "lantern/consensus/hash.h"
#include "lantern/consensus/ssz.h"
#include "lantern/networking/messages.h"
#include "pq-bindings-c-rust.h"
#include "ssz.h"
#include "ssz_deserialize.h"
#include "ssz_merkle.h"
#include "ssz_serialize.h"

#ifndef LANTERN_CONSENSUS_FIXTURE_DIR
#define LANTERN_CONSENSUS_FIXTURE_DIR "tools/leanSpec/fixtures/consensus"
#endif

#define SSZ_FIXTURE_SUBDIR "ssz/lstar/ssz"
#define PREVIEW_BYTES 32u
#define BYTELIST_MIB_LIMIT (1024u * 1024u)
#define BYTELIST_512KIB_LIMIT (512u * 1024u)
#define SAMPLE_UINT32_LIST_LIMIT 16u
#define SAMPLE_BYTES32_LIST_LIMIT 8u
#define SAMPLE_BITLIST_LIMIT_BITS 16u
#define LANTERN_XMSS_FP_BYTES 4u
#define LANTERN_XMSS_HASH_LEN_FE 8u
#define LANTERN_XMSS_RAND_LEN_FE 7u
#define LANTERN_XMSS_HASH_DIGEST_BYTES (LANTERN_XMSS_HASH_LEN_FE * LANTERN_XMSS_FP_BYTES)
#define LANTERN_XMSS_RHO_BYTES (LANTERN_XMSS_RAND_LEN_FE * LANTERN_XMSS_FP_BYTES)
#define LANTERN_XMSS_SIGNATURE_FIXED_SECTION \
    (SSZ_BYTES_PER_LENGTH_OFFSET + LANTERN_XMSS_RHO_BYTES + SSZ_BYTES_PER_LENGTH_OFFSET)
#define LANTERN_KOALABEAR_P UINT32_C(2130706433)

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
    buffer->len = 0u;
}

static int record_failure(
    const char *path,
    const char *type_name,
    const char *format,
    ...) {
    va_list args;
    fprintf(stderr, "[ssz] %s", path ? path : "(unknown)");
    if (type_name && type_name[0] != '\0') {
        fprintf(stderr, " [%s]", type_name);
    }
    fprintf(stderr, ": ");
    va_start(args, format);
    vfprintf(stderr, format, args);
    va_end(args);
    fputc('\n', stderr);
    return -1;
}

static void reset_block(LanternBlock *block) {
    if (!block) {
        return;
    }
    lantern_block_body_reset(&block->body);
    memset(block, 0, sizeof(*block));
}

static void print_hex_preview(const uint8_t *bytes, size_t len) {
    size_t preview = len < PREVIEW_BYTES ? len : PREVIEW_BYTES;
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
    const char *type_name,
    const char *label,
    const uint8_t *expected,
    size_t expected_len,
    const uint8_t *actual,
    size_t actual_len) {
    if (expected_len == actual_len && (expected_len == 0u || memcmp(expected, actual, expected_len) == 0)) {
        return 0;
    }

    fprintf(stderr, "[ssz] %s [%s]: %s mismatch\n", path, type_name, label);
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

static int expect_root_equal(
    const char *path,
    const char *type_name,
    const char *label,
    const LanternRoot *expected,
    const LanternRoot *actual) {
    if (expected && actual && memcmp(expected->bytes, actual->bytes, LANTERN_ROOT_SIZE) == 0) {
        return 0;
    }

    fprintf(stderr, "[ssz] %s [%s]: %s root mismatch\n", path, type_name, label);
    fprintf(stderr, "  expected: ");
    if (expected) {
        print_hex_preview(expected->bytes, LANTERN_ROOT_SIZE);
    } else {
        fprintf(stderr, "(null)");
    }
    fprintf(stderr, "\n  actual  : ");
    if (actual) {
        print_hex_preview(actual->bytes, LANTERN_ROOT_SIZE);
    } else {
        fprintf(stderr, "(null)");
    }
    fputc('\n', stderr);
    return -1;
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

static int parse_hex_string(const char *value, size_t length, struct byte_buffer *out_bytes) {
    if (!value || !out_bytes || length < 2u || value[0] != '0' || value[1] != 'x') {
        return -1;
    }
    byte_buffer_reset(out_bytes);

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

static int fixture_token_to_bytes(
    const struct lantern_fixture_document *doc,
    int index,
    struct byte_buffer *out_bytes) {
    if (!doc || !out_bytes) {
        return -1;
    }
    byte_buffer_reset(out_bytes);
    size_t length = 0u;
    const char *value = lantern_fixture_token_string(doc, index, &length);
    return value ? parse_hex_string(value, length, out_bytes) : -1;
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
    size_t length = 0u;
    const char *value = lantern_fixture_token_string(doc, index, &length);
    if (!value) {
        return -1;
    }
    char *copy = (char *)malloc(length + 1u);
    if (!copy) {
        return -1;
    }
    if (length > 0u) {
        memcpy(copy, value, length);
    }
    copy[length] = '\0';
    *out_string = copy;
    return 0;
}

static int build_fixture_root(char *path, size_t path_len) {
    if (!path || path_len == 0u) {
        return -1;
    }
    int written = snprintf(path, path_len, "%s/%s", LANTERN_CONSENSUS_FIXTURE_DIR, SSZ_FIXTURE_SUBDIR);
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

static int chunk_from_uint64(uint64_t value, ssz_chunk_t *out) {
    return ssz_hash_tree_root_uint64(value, out) == SSZ_SUCCESS ? 0 : -1;
}

static void chunk_from_root(const LanternRoot *root, ssz_chunk_t *out) {
    memcpy(out->bytes, root->bytes, SSZ_BYTES_PER_CHUNK);
}

static void root_from_chunk(const ssz_chunk_t *chunk, LanternRoot *out_root) {
    memcpy(out_root->bytes, chunk->bytes, LANTERN_ROOT_SIZE);
}

static void write_u32_le(uint32_t value, uint8_t out[4]) {
    out[0] = (uint8_t)(value & 0xFFu);
    out[1] = (uint8_t)((value >> 8u) & 0xFFu);
    out[2] = (uint8_t)((value >> 16u) & 0xFFu);
    out[3] = (uint8_t)((value >> 24u) & 0xFFu);
}

static size_t xmss_node_list_limit(void) {
    uint64_t lifetime = pq_get_lifetime();
    if (lifetime == 0u || (lifetime & (lifetime - 1u)) != 0u) {
        return (size_t)1u << 17;
    }

    unsigned int log_lifetime = 0u;
    while (log_lifetime < 63u && (UINT64_C(1) << log_lifetime) < lifetime) {
        ++log_lifetime;
    }

    unsigned int exponent = (log_lifetime / 2u) + 1u;
    if (exponent >= (sizeof(size_t) * 8u)) {
        return 0u;
    }

    return (size_t)1u << exponent;
}

static uint32_t read_u32_le_local(const uint8_t *data) {
    return (uint32_t)data[0]
        | ((uint32_t)data[1] << 8u)
        | ((uint32_t)data[2] << 16u)
        | ((uint32_t)data[3] << 24u);
}

static int merkleize_bytes_with_optional_length(
    const uint8_t *bytes,
    size_t byte_len,
    size_t chunk_limit,
    bool mix_length,
    uint64_t length_value,
    LanternRoot *out_root) {
    if (!out_root || (byte_len > 0u && !bytes)) {
        return -1;
    }

    size_t chunk_count = byte_len == 0u ? 0u : ((byte_len + SSZ_BYTES_PER_CHUNK - 1u) / SSZ_BYTES_PER_CHUNK);
    ssz_chunk_t *chunks = NULL;
    if (chunk_count > 0u) {
        chunks = (ssz_chunk_t *)calloc(chunk_count, sizeof(*chunks));
        if (!chunks) {
            return -1;
        }
        memcpy(chunks, bytes, byte_len);
    }

    uint64_t effective_limit = chunk_limit == 0u ? SSZ_NO_LIMIT : (uint64_t)chunk_limit;
    ssz_chunk_t temp_root;
    ssz_error_t err = ssz_merkleize(chunks, chunk_count, effective_limit, NULL, NULL, &temp_root);
    free(chunks);
    if (err != SSZ_SUCCESS) {
        return -1;
    }

    if (mix_length) {
        ssz_chunk_t mixed;
        err = ssz_mix_in_length_u64(&temp_root, length_value, NULL, &mixed);
        if (err != SSZ_SUCCESS) {
            return -1;
        }
        root_from_chunk(&mixed, out_root);
        return 0;
    }

    root_from_chunk(&temp_root, out_root);
    return 0;
}

static int root_from_fixed_serialized_bytes(
    const uint8_t *bytes,
    size_t byte_len,
    LanternRoot *out_root) {
    return merkleize_bytes_with_optional_length(bytes, byte_len, 0u, false, 0u, out_root);
}

static int pack_bool_bits(const bool *bits, size_t bit_count, uint8_t **out_bytes, size_t *out_len) {
    if (!out_bytes || !out_len || (bit_count > 0u && !bits)) {
        return -1;
    }
    size_t byte_len = (bit_count + 7u) / 8u;
    uint8_t *bytes = (uint8_t *)calloc(byte_len > 0u ? byte_len : 1u, sizeof(*bytes));
    if (!bytes) {
        return -1;
    }
    for (size_t i = 0; i < bit_count; ++i) {
        if (bits[i]) {
            bytes[i / 8u] |= (uint8_t)(1u << (i % 8u));
        }
    }
    *out_bytes = bytes;
    *out_len = byte_len;
    return 0;
}

static bool packed_bit_is_set(const uint8_t *bytes, size_t bit_count, size_t index) {
    if (!bytes || index >= bit_count) {
        return false;
    }
    return (bytes[index / 8u] & (uint8_t)(1u << (index % 8u))) != 0u;
}

static int parse_size_suffix(const char *text, const char *prefix, size_t *out_value) {
    if (!text || !prefix || !out_value) {
        return -1;
    }
    size_t prefix_len = strlen(prefix);
    if (strncmp(text, prefix, prefix_len) != 0 || text[prefix_len] == '\0') {
        return -1;
    }
    errno = 0;
    char *end = NULL;
    unsigned long value = strtoul(text + prefix_len, &end, 10);
    if (errno != 0 || !end || *end != '\0') {
        return -1;
    }
    *out_value = (size_t)value;
    return 0;
}

static int parse_bool_data_array(
    const struct lantern_fixture_document *doc,
    int object_index,
    bool **out_bits,
    size_t *out_count) {
    if (!doc || !out_bits || !out_count) {
        return -1;
    }
    *out_bits = NULL;
    *out_count = 0u;

    int data_idx = lantern_fixture_object_get_field(doc, object_index, "data");
    int count = data_idx >= 0 ? lantern_fixture_array_get_length(doc, data_idx) : -1;
    if (data_idx < 0 || count < 0) {
        return -1;
    }

    if (count == 0) {
        return 0;
    }

    bool *bits = (bool *)calloc((size_t)count, sizeof(*bits));
    if (!bits) {
        return -1;
    }
    for (int i = 0; i < count; ++i) {
        int bit_idx = lantern_fixture_array_get_element(doc, data_idx, i);
        if (bit_idx < 0 || fixture_token_to_bool(doc, bit_idx, &bits[i]) != 0) {
            free(bits);
            return -1;
        }
    }

    *out_bits = bits;
    *out_count = (size_t)count;
    return 0;
}

static int parse_u32_data_array(
    const struct lantern_fixture_document *doc,
    int object_index,
    uint32_t **out_values,
    size_t *out_count) {
    if (!doc || !out_values || !out_count) {
        return -1;
    }
    *out_values = NULL;
    *out_count = 0u;

    int data_idx = lantern_fixture_object_get_field(doc, object_index, "data");
    int count = data_idx >= 0 ? lantern_fixture_array_get_length(doc, data_idx) : -1;
    if (data_idx < 0 || count < 0) {
        return -1;
    }
    if (count == 0) {
        return 0;
    }

    uint32_t *values = (uint32_t *)calloc((size_t)count, sizeof(*values));
    if (!values) {
        return -1;
    }
    for (int i = 0; i < count; ++i) {
        int value_idx = lantern_fixture_array_get_element(doc, data_idx, i);
        uint64_t value = 0u;
        if (value_idx < 0 || lantern_fixture_token_to_uint64(doc, value_idx, &value) != 0 || value > UINT32_MAX) {
            free(values);
            return -1;
        }
        values[i] = (uint32_t)value;
    }

    *out_values = values;
    *out_count = (size_t)count;
    return 0;
}

static int parse_u64_data_array(
    const struct lantern_fixture_document *doc,
    int object_index,
    uint64_t **out_values,
    size_t *out_count) {
    if (!doc || !out_values || !out_count) {
        return -1;
    }
    *out_values = NULL;
    *out_count = 0u;

    int data_idx = lantern_fixture_object_get_field(doc, object_index, "data");
    int count = data_idx >= 0 ? lantern_fixture_array_get_length(doc, data_idx) : -1;
    if (data_idx < 0 || count < 0) {
        return -1;
    }
    if (count == 0) {
        return 0;
    }

    uint64_t *values = (uint64_t *)calloc((size_t)count, sizeof(*values));
    if (!values) {
        return -1;
    }
    for (int i = 0; i < count; ++i) {
        int value_idx = lantern_fixture_array_get_element(doc, data_idx, i);
        if (value_idx < 0 || lantern_fixture_token_to_uint64(doc, value_idx, &values[i]) != 0) {
            free(values);
            return -1;
        }
    }

    *out_values = values;
    *out_count = (size_t)count;
    return 0;
}

static int parse_hex_data_object(
    const struct lantern_fixture_document *doc,
    int object_index,
    struct byte_buffer *out_bytes) {
    if (!doc || !out_bytes) {
        return -1;
    }
    int data_idx = lantern_fixture_object_get_field(doc, object_index, "data");
    return data_idx >= 0 ? fixture_token_to_bytes(doc, data_idx, out_bytes) : -1;
}

static int parse_root_list_object(
    const struct lantern_fixture_document *doc,
    int object_index,
    struct lantern_root_list *out_roots) {
    if (!doc || !out_roots) {
        return -1;
    }
    int data_idx = lantern_fixture_object_get_field(doc, object_index, "data");
    int count = data_idx >= 0 ? lantern_fixture_array_get_length(doc, data_idx) : -1;
    if (data_idx < 0 || count < 0) {
        return -1;
    }
    lantern_root_list_init(out_roots);
    if (lantern_root_list_resize(out_roots, (size_t)count) != 0) {
        lantern_root_list_reset(out_roots);
        return -1;
    }
    for (int i = 0; i < count; ++i) {
        int root_idx = lantern_fixture_array_get_element(doc, data_idx, i);
        if (root_idx < 0 || lantern_fixture_token_to_root(doc, root_idx, &out_roots->items[i]) != 0) {
            lantern_root_list_reset(out_roots);
            return -1;
        }
    }
    return 0;
}

static int parse_checkpoint_object(
    const struct lantern_fixture_document *doc,
    int object_index,
    LanternCheckpoint *out_checkpoint) {
    if (!doc || !out_checkpoint) {
        return -1;
    }
    int root_idx = lantern_fixture_object_get_field(doc, object_index, "root");
    int slot_idx = lantern_fixture_object_get_field(doc, object_index, "slot");
    if (root_idx < 0 || slot_idx < 0
        || lantern_fixture_token_to_root(doc, root_idx, &out_checkpoint->root) != 0
        || lantern_fixture_token_to_uint64(doc, slot_idx, &out_checkpoint->slot) != 0) {
        return -1;
    }
    return 0;
}

static int parse_status_object(
    const struct lantern_fixture_document *doc,
    int object_index,
    LanternStatusMessage *out_status) {
    if (!doc || !out_status) {
        return -1;
    }
    int finalized_idx = lantern_fixture_object_get_field(doc, object_index, "finalized");
    int head_idx = lantern_fixture_object_get_field(doc, object_index, "head");
    if (finalized_idx < 0 || head_idx < 0
        || parse_checkpoint_object(doc, finalized_idx, &out_status->finalized) != 0
        || parse_checkpoint_object(doc, head_idx, &out_status->head) != 0) {
        return -1;
    }
    return 0;
}

static int parse_validator_object(
    const struct lantern_fixture_document *doc,
    int object_index,
    LanternValidator *out_validator) {
    if (!doc || !out_validator) {
        return -1;
    }

    int attestation_idx = lantern_fixture_object_get_field(doc, object_index, "attestationPubkey");
    if (attestation_idx < 0) {
        attestation_idx = lantern_fixture_object_get_field(doc, object_index, "attestationPublicKey");
    }
    if (attestation_idx < 0) {
        attestation_idx = lantern_fixture_object_get_field(doc, object_index, "attestation_pubkey");
    }
    int proposal_idx = lantern_fixture_object_get_field(doc, object_index, "proposalPubkey");
    if (proposal_idx < 0) {
        proposal_idx = lantern_fixture_object_get_field(doc, object_index, "proposalPublicKey");
    }
    if (proposal_idx < 0) {
        proposal_idx = lantern_fixture_object_get_field(doc, object_index, "proposal_pubkey");
    }
    if (attestation_idx < 0) {
        attestation_idx = lantern_fixture_object_get_field(doc, object_index, "pubkey");
    }
    if (proposal_idx < 0) {
        proposal_idx = attestation_idx;
    }
    int index_idx = lantern_fixture_object_get_field(doc, object_index, "index");
    struct byte_buffer attestation = {0};
    struct byte_buffer proposal = {0};

    if (attestation_idx < 0 || proposal_idx < 0 || index_idx < 0
        || fixture_token_to_bytes(doc, attestation_idx, &attestation) != 0
        || fixture_token_to_bytes(doc, proposal_idx, &proposal) != 0
        || attestation.len != LANTERN_VALIDATOR_PUBKEY_SIZE
        || proposal.len != LANTERN_VALIDATOR_PUBKEY_SIZE
        || lantern_fixture_token_to_uint64(doc, index_idx, &out_validator->index) != 0) {
        byte_buffer_reset(&attestation);
        byte_buffer_reset(&proposal);
        return -1;
    }

    memcpy(out_validator->attestation_pubkey, attestation.data, LANTERN_VALIDATOR_PUBKEY_SIZE);
    memcpy(out_validator->proposal_pubkey, proposal.data, LANTERN_VALIDATOR_PUBKEY_SIZE);
    byte_buffer_reset(&attestation);
    byte_buffer_reset(&proposal);
    return 0;
}

static int parse_attestation_vote_object(
    const struct lantern_fixture_document *doc,
    int object_index,
    LanternVote *out_vote) {
    if (!doc || !out_vote) {
        return -1;
    }
    memset(out_vote, 0, sizeof(*out_vote));

    int validator_idx = lantern_fixture_object_get_field(doc, object_index, "validatorId");
    if (validator_idx < 0) {
        validator_idx = lantern_fixture_object_get_field(doc, object_index, "validatorIndex");
    }
    if (validator_idx < 0) {
        validator_idx = lantern_fixture_object_get_field(doc, object_index, "validator_id");
    }
    int data_idx = lantern_fixture_object_get_field(doc, object_index, "data");
    if (validator_idx < 0 || data_idx < 0
        || lantern_fixture_token_to_uint64(doc, validator_idx, &out_vote->validator_id) != 0
        || lantern_fixture_parse_attestation_data(doc, data_idx, &out_vote->data) != 0) {
        return -1;
    }
    return 0;
}

static int parse_block_body_object(
    const struct lantern_fixture_document *doc,
    int object_index,
    LanternBlockBody *out_body) {
    if (!doc || !out_body) {
        return -1;
    }
    lantern_block_body_init(out_body);

    int attestations_idx = lantern_fixture_object_get_field(doc, object_index, "attestations");
    int data_idx = attestations_idx >= 0 ? lantern_fixture_object_get_field(doc, attestations_idx, "data") : -1;
    int count = data_idx >= 0 ? lantern_fixture_array_get_length(doc, data_idx) : -1;
    if (attestations_idx < 0 || data_idx < 0 || count < 0) {
        lantern_block_body_reset(out_body);
        return -1;
    }

    if (lantern_aggregated_attestations_resize(&out_body->attestations, (size_t)count) != 0) {
        lantern_block_body_reset(out_body);
        return -1;
    }

    for (int i = 0; i < count; ++i) {
        int entry_idx = lantern_fixture_array_get_element(doc, data_idx, i);
        if (entry_idx < 0
            || lantern_fixture_parse_aggregated_attestation(doc, entry_idx, &out_body->attestations.data[i]) != 0) {
            lantern_block_body_reset(out_body);
            return -1;
        }
    }

    return 0;
}

static int parse_signed_aggregated_attestation_object(
    const struct lantern_fixture_document *doc,
    int object_index,
    LanternSignedAggregatedAttestation *out_attestation) {
    if (!doc || !out_attestation) {
        return -1;
    }
    lantern_signed_aggregated_attestation_init(out_attestation);

    int data_idx = lantern_fixture_object_get_field(doc, object_index, "data");
    int proof_idx = lantern_fixture_object_get_field(doc, object_index, "proof");
    if (data_idx < 0 || proof_idx < 0
        || lantern_fixture_parse_attestation_data(doc, data_idx, &out_attestation->data) != 0
        || lantern_fixture_parse_signature_proof(doc, proof_idx, &out_attestation->proof) != 0) {
        lantern_signed_aggregated_attestation_reset(out_attestation);
        return -1;
    }

    return 0;
}

static int parse_fp_digest_object(
    const struct lantern_fixture_document *doc,
    int object_index,
    struct byte_buffer *out_bytes) {
    uint32_t *values = NULL;
    size_t count = 0u;
    byte_buffer_reset(out_bytes);
    if (parse_u32_data_array(doc, object_index, &values, &count) != 0 || count == 0u) {
        free(values);
        return -1;
    }

    uint8_t *bytes = (uint8_t *)malloc(count * sizeof(uint32_t));
    if (!bytes) {
        free(values);
        return -1;
    }
    for (size_t i = 0; i < count; ++i) {
        write_u32_le(values[i], bytes + (i * sizeof(uint32_t)));
    }
    free(values);
    out_bytes->data = bytes;
    out_bytes->len = count * sizeof(uint32_t);
    return 0;
}

static int parse_public_key_object(
    const struct lantern_fixture_document *doc,
    int object_index,
    struct byte_buffer *out_serialized) {
    if (!doc || !out_serialized) {
        return -1;
    }
    byte_buffer_reset(out_serialized);

    const jsmntok_t *token = lantern_fixture_token(doc, object_index);
    if (token && token->type == JSMN_STRING) {
        return fixture_token_to_bytes(doc, object_index, out_serialized);
    }

    int root_idx = lantern_fixture_object_get_field(doc, object_index, "root");
    int parameter_idx = lantern_fixture_object_get_field(doc, object_index, "parameter");
    struct byte_buffer root_bytes = {0};
    struct byte_buffer parameter_bytes = {0};
    if (root_idx < 0 || parameter_idx < 0
        || parse_fp_digest_object(doc, root_idx, &root_bytes) != 0
        || parse_fp_digest_object(doc, parameter_idx, &parameter_bytes) != 0) {
        byte_buffer_reset(&root_bytes);
        byte_buffer_reset(&parameter_bytes);
        return -1;
    }

    uint8_t *bytes = (uint8_t *)malloc(root_bytes.len + parameter_bytes.len);
    if (!bytes) {
        byte_buffer_reset(&root_bytes);
        byte_buffer_reset(&parameter_bytes);
        return -1;
    }
    memcpy(bytes, root_bytes.data, root_bytes.len);
    memcpy(bytes + root_bytes.len, parameter_bytes.data, parameter_bytes.len);
    out_serialized->data = bytes;
    out_serialized->len = root_bytes.len + parameter_bytes.len;

    byte_buffer_reset(&root_bytes);
    byte_buffer_reset(&parameter_bytes);
    return 0;
}

static int parse_hash_digest_list_object(
    const struct lantern_fixture_document *doc,
    int object_index,
    struct byte_buffer *out_bytes,
    size_t *out_count) {
    if (!doc || !out_bytes || !out_count) {
        return -1;
    }
    byte_buffer_reset(out_bytes);
    *out_count = 0u;

    int data_idx = lantern_fixture_object_get_field(doc, object_index, "data");
    int count = data_idx >= 0 ? lantern_fixture_array_get_length(doc, data_idx) : -1;
    if (data_idx < 0 || count < 0) {
        return -1;
    }

    if (count == 0) {
        return 0;
    }

    uint8_t *bytes = (uint8_t *)malloc((size_t)count * LANTERN_XMSS_HASH_DIGEST_BYTES);
    if (!bytes) {
        return -1;
    }

    for (int i = 0; i < count; ++i) {
        int digest_idx = lantern_fixture_array_get_element(doc, data_idx, i);
        struct byte_buffer digest = {0};
        if (digest_idx < 0 || parse_fp_digest_object(doc, digest_idx, &digest) != 0
            || digest.len != LANTERN_XMSS_HASH_DIGEST_BYTES) {
            byte_buffer_reset(&digest);
            free(bytes);
            return -1;
        }
        memcpy(bytes + ((size_t)i * LANTERN_XMSS_HASH_DIGEST_BYTES), digest.data, digest.len);
        byte_buffer_reset(&digest);
    }

    out_bytes->data = bytes;
    out_bytes->len = (size_t)count * LANTERN_XMSS_HASH_DIGEST_BYTES;
    *out_count = (size_t)count;
    return 0;
}

static int parse_hash_tree_opening_object(
    const struct lantern_fixture_document *doc,
    int object_index,
    struct byte_buffer *out_serialized,
    size_t *out_sibling_count) {
    if (!doc || !out_serialized || !out_sibling_count) {
        return -1;
    }
    byte_buffer_reset(out_serialized);
    *out_sibling_count = 0u;

    int siblings_idx = lantern_fixture_object_get_field(doc, object_index, "siblings");
    struct byte_buffer siblings_bytes = {0};
    size_t sibling_count = 0u;
    if (siblings_idx < 0
        || parse_hash_digest_list_object(doc, siblings_idx, &siblings_bytes, &sibling_count) != 0) {
        byte_buffer_reset(&siblings_bytes);
        return -1;
    }

    size_t total_len = sizeof(uint32_t) + siblings_bytes.len;
    uint8_t *bytes = (uint8_t *)malloc(total_len);
    if (!bytes) {
        byte_buffer_reset(&siblings_bytes);
        return -1;
    }
    write_u32_le((uint32_t)sizeof(uint32_t), bytes);
    if (siblings_bytes.len > 0u) {
        memcpy(bytes + sizeof(uint32_t), siblings_bytes.data, siblings_bytes.len);
    }

    out_serialized->data = bytes;
    out_serialized->len = total_len;
    *out_sibling_count = sibling_count;
    byte_buffer_reset(&siblings_bytes);
    return 0;
}

static int parse_hash_tree_layer_object(
    const struct lantern_fixture_document *doc,
    int object_index,
    struct byte_buffer *out_serialized,
    uint64_t *out_start_index,
    size_t *out_node_count) {
    if (!doc || !out_serialized || !out_start_index || !out_node_count) {
        return -1;
    }
    byte_buffer_reset(out_serialized);
    *out_start_index = 0u;
    *out_node_count = 0u;

    int start_idx = lantern_fixture_object_get_field(doc, object_index, "startIndex");
    int nodes_idx = lantern_fixture_object_get_field(doc, object_index, "nodes");
    struct byte_buffer nodes_bytes = {0};
    size_t node_count = 0u;
    if (start_idx < 0 || nodes_idx < 0
        || lantern_fixture_token_to_uint64(doc, start_idx, out_start_index) != 0
        || parse_hash_digest_list_object(doc, nodes_idx, &nodes_bytes, &node_count) != 0) {
        byte_buffer_reset(&nodes_bytes);
        return -1;
    }

    size_t total_len = sizeof(uint64_t) + sizeof(uint32_t) + nodes_bytes.len;
    uint8_t *bytes = (uint8_t *)calloc(1u, total_len);
    if (!bytes) {
        byte_buffer_reset(&nodes_bytes);
        return -1;
    }
    for (size_t i = 0; i < sizeof(uint64_t); ++i) {
        bytes[i] = (uint8_t)((*out_start_index >> (8u * i)) & 0xFFu);
    }
    write_u32_le((uint32_t)(sizeof(uint64_t) + sizeof(uint32_t)), bytes + sizeof(uint64_t));
    if (nodes_bytes.len > 0u) {
        memcpy(bytes + sizeof(uint64_t) + sizeof(uint32_t), nodes_bytes.data, nodes_bytes.len);
    }

    out_serialized->data = bytes;
    out_serialized->len = total_len;
    *out_node_count = node_count;
    byte_buffer_reset(&nodes_bytes);
    return 0;
}

static int compute_status_root(const LanternStatusMessage *status, LanternRoot *out_root) {
    if (!status || !out_root) {
        return -1;
    }
    LanternRoot finalized_root;
    LanternRoot head_root;
    if (lantern_hash_tree_root_checkpoint(&status->finalized, &finalized_root) != SSZ_SUCCESS
        || lantern_hash_tree_root_checkpoint(&status->head, &head_root) != SSZ_SUCCESS) {
        return -1;
    }
    ssz_chunk_t chunks[2];
    chunk_from_root(&finalized_root, &chunks[0]);
    chunk_from_root(&head_root, &chunks[1]);
    ssz_chunk_t root;
    if (ssz_merkleize(chunks, 2u, SSZ_NO_LIMIT, NULL, NULL, &root) != SSZ_SUCCESS) {
        return -1;
    }
    root_from_chunk(&root, out_root);
    return 0;
}

static int compute_blocks_by_root_request_root(
    const LanternBlocksByRootRequest *request,
    LanternRoot *out_root) {
    if (!request || !out_root) {
        return -1;
    }
    return lantern_merkleize_root_list(&request->roots, LANTERN_MAX_REQUEST_BLOCKS, out_root) == SSZ_SUCCESS ? 0 : -1;
}

static int compute_hash_tree_opening_root_from_serialized(
    const uint8_t *serialized,
    size_t serialized_len,
    LanternRoot *out_root) {
    if (!serialized || serialized_len < sizeof(uint32_t) || !out_root) {
        return -1;
    }
    uint32_t offset = read_u32_le_local(serialized);
    if (offset != sizeof(uint32_t) || offset > serialized_len) {
        return -1;
    }
    size_t siblings_len = serialized_len - offset;
    if ((siblings_len % LANTERN_XMSS_HASH_DIGEST_BYTES) != 0u) {
        return -1;
    }
    size_t sibling_count = siblings_len / LANTERN_XMSS_HASH_DIGEST_BYTES;
    return merkleize_bytes_with_optional_length(
        serialized + offset,
        siblings_len,
        xmss_node_list_limit(),
        true,
        sibling_count,
        out_root);
}

static int compute_hash_tree_layer_root(
    uint64_t start_index,
    const uint8_t *nodes_bytes,
    size_t node_count,
    LanternRoot *out_root) {
    if (!out_root || (node_count > 0u && !nodes_bytes)) {
        return -1;
    }
    LanternRoot nodes_root;
    if (merkleize_bytes_with_optional_length(
            nodes_bytes,
            node_count * LANTERN_XMSS_HASH_DIGEST_BYTES,
            xmss_node_list_limit(),
            true,
            node_count,
            &nodes_root)
        != 0) {
        return -1;
    }
    ssz_chunk_t chunks[2];
    if (chunk_from_uint64(start_index, &chunks[0]) != 0) {
        return -1;
    }
    chunk_from_root(&nodes_root, &chunks[1]);
    ssz_chunk_t root;
    if (ssz_merkleize(chunks, 2u, SSZ_NO_LIMIT, NULL, NULL, &root) != SSZ_SUCCESS) {
        return -1;
    }
    root_from_chunk(&root, out_root);
    return 0;
}

static int run_unsupported_fixture(
    const char *path,
    const char *type_name,
    struct fixture_stats *stats,
    const char *reason) {
    if (stats) {
        stats->unsupported += 1u;
    }
    return record_failure(path, type_name, "%s", reason ? reason : "unsupported type");
}

static int run_boolean_fixture(
    const char *path,
    const char *type_name,
    const struct lantern_fixture_document *doc,
    int value_idx,
    const struct byte_buffer *expected_serialized,
    const LanternRoot *expected_root) {
    bool value = false;
    uint8_t decoded = 0u;
    uint8_t encoded[1];
    size_t encoded_len = sizeof(encoded);
    if (fixture_token_to_bool(doc, value_idx, &value) != 0
        || ssz_serialize_boolean(value ? 1u : 0u, encoded) != SSZ_SUCCESS
        || expect_bytes_equal(path, type_name, "encode(value)", expected_serialized->data, expected_serialized->len, encoded, encoded_len) != 0
        || ssz_deserialize_boolean(expected_serialized->data, expected_serialized->len, &decoded) != SSZ_SUCCESS
        || (decoded != 0u) != value) {
        return record_failure(path, type_name, "boolean roundtrip failed");
    }
    encoded_len = sizeof(encoded);
    if (ssz_serialize_boolean(decoded, encoded) != SSZ_SUCCESS
        || expect_bytes_equal(path, type_name, "decode(serialized)", expected_serialized->data, expected_serialized->len, encoded, encoded_len) != 0) {
        return -1;
    }
    LanternRoot root;
    if (root_from_fixed_serialized_bytes(expected_serialized->data, expected_serialized->len, &root) != 0) {
        return record_failure(path, type_name, "failed to compute boolean root");
    }
    return expect_root_equal(path, type_name, "hash_tree_root", expected_root, &root);
}

static int run_uint_fixture(
    const char *path,
    const char *type_name,
    const struct lantern_fixture_document *doc,
    int value_idx,
    unsigned bits,
    const struct byte_buffer *expected_serialized,
    const LanternRoot *expected_root) {
    uint64_t value = 0u;
    if (lantern_fixture_token_to_uint64(doc, value_idx, &value) != 0) {
        return record_failure(path, type_name, "invalid integer value");
    }

    uint8_t encoded[32];
    size_t encoded_len = sizeof(encoded);
    ssz_error_t serr = SSZ_ERR_INVALID_ARGUMENT;
    if (bits == 8u) {
        uint8_t v = (uint8_t)value;
        if (value > UINT8_MAX) {
            return record_failure(path, type_name, "value out of range");
        }
        serr = ssz_serialize_uint8(v, encoded);
        encoded_len = sizeof(uint8_t);
        uint8_t decoded = 0u;
        if (serr != SSZ_SUCCESS
            || expect_bytes_equal(path, type_name, "encode(value)", expected_serialized->data, expected_serialized->len, encoded, encoded_len) != 0
            || ssz_deserialize_uint8(expected_serialized->data, expected_serialized->len, &decoded) != SSZ_SUCCESS
            || decoded != v) {
            return record_failure(path, type_name, "uint8 roundtrip failed");
        }
    } else if (bits == 16u) {
        uint16_t v = (uint16_t)value;
        if (value > UINT16_MAX) {
            return record_failure(path, type_name, "value out of range");
        }
        serr = ssz_serialize_uint16(v, encoded);
        encoded_len = sizeof(uint16_t);
        uint16_t decoded = 0u;
        if (serr != SSZ_SUCCESS
            || expect_bytes_equal(path, type_name, "encode(value)", expected_serialized->data, expected_serialized->len, encoded, encoded_len) != 0
            || ssz_deserialize_uint16(expected_serialized->data, expected_serialized->len, &decoded) != SSZ_SUCCESS
            || decoded != v) {
            return record_failure(path, type_name, "uint16 roundtrip failed");
        }
    } else if (bits == 32u) {
        uint32_t v = (uint32_t)value;
        if (value > UINT32_MAX) {
            return record_failure(path, type_name, "value out of range");
        }
        serr = ssz_serialize_uint32(v, encoded);
        encoded_len = sizeof(uint32_t);
        uint32_t decoded = 0u;
        if (serr != SSZ_SUCCESS
            || expect_bytes_equal(path, type_name, "encode(value)", expected_serialized->data, expected_serialized->len, encoded, encoded_len) != 0
            || ssz_deserialize_uint32(expected_serialized->data, expected_serialized->len, &decoded) != SSZ_SUCCESS
            || decoded != v) {
            return record_failure(path, type_name, "uint32 roundtrip failed");
        }
    } else if (bits == 64u) {
        uint64_t decoded = 0u;
        serr = ssz_serialize_uint64(value, encoded);
        encoded_len = sizeof(uint64_t);
        if (serr != SSZ_SUCCESS
            || expect_bytes_equal(path, type_name, "encode(value)", expected_serialized->data, expected_serialized->len, encoded, encoded_len) != 0
            || ssz_deserialize_uint64(expected_serialized->data, expected_serialized->len, &decoded) != SSZ_SUCCESS
            || decoded != value) {
            return record_failure(path, type_name, "uint64 roundtrip failed");
        }
    } else {
        return record_failure(path, type_name, "unsupported integer width");
    }

    LanternRoot root;
    if (root_from_fixed_serialized_bytes(expected_serialized->data, expected_serialized->len, &root) != 0) {
        return record_failure(path, type_name, "failed to compute integer root");
    }
    return expect_root_equal(path, type_name, "hash_tree_root", expected_root, &root);
}

static int fixture_token_to_fp(
    const struct lantern_fixture_document *doc,
    int value_idx,
    uint32_t *out_value) {
    if (!doc || !out_value) {
        return -1;
    }
    uint64_t numeric = 0u;
    if (lantern_fixture_token_to_uint64(doc, value_idx, &numeric) == 0) {
        if (numeric >= LANTERN_KOALABEAR_P) {
            return -1;
        }
        *out_value = (uint32_t)numeric;
        return 0;
    }

    size_t len = 0u;
    const char *text = lantern_fixture_token_string(doc, value_idx, &len);
    const char prefix[] = "Fp(value=";
    const size_t prefix_len = sizeof(prefix) - 1u;
    if (!text || len <= prefix_len + 1u || strncmp(text, prefix, prefix_len) != 0
        || text[len - 1u] != ')') {
        return -1;
    }

    char buffer[32];
    size_t digits_len = len - prefix_len - 1u;
    if (digits_len == 0u || digits_len >= sizeof(buffer)) {
        return -1;
    }
    memcpy(buffer, text + prefix_len, digits_len);
    buffer[digits_len] = '\0';

    char *endptr = NULL;
    errno = 0;
    unsigned long long parsed = strtoull(buffer, &endptr, 10);
    if (errno != 0 || endptr == buffer || *endptr != '\0' || parsed >= LANTERN_KOALABEAR_P) {
        return -1;
    }

    *out_value = (uint32_t)parsed;
    return 0;
}

static int run_fp_fixture(
    const char *path,
    const char *type_name,
    const struct lantern_fixture_document *doc,
    int value_idx,
    const struct byte_buffer *expected_serialized,
    const LanternRoot *expected_root) {
    uint32_t value = 0u;
    if (fixture_token_to_fp(doc, value_idx, &value) != 0) {
        return record_failure(path, type_name, "invalid Fp value");
    }

    uint8_t encoded[sizeof(uint32_t)];
    if (ssz_serialize_uint32(value, encoded) != SSZ_SUCCESS
        || expect_bytes_equal(path, type_name, "encode(value)", expected_serialized->data, expected_serialized->len, encoded, sizeof(encoded)) != 0) {
        return record_failure(path, type_name, "Fp encode failed");
    }

    uint32_t decoded = 0u;
    if (ssz_deserialize_uint32(expected_serialized->data, expected_serialized->len, &decoded) != SSZ_SUCCESS
        || decoded != value
        || decoded >= LANTERN_KOALABEAR_P) {
        return record_failure(path, type_name, "Fp decode failed");
    }
    if (ssz_serialize_uint32(decoded, encoded) != SSZ_SUCCESS
        || expect_bytes_equal(path, type_name, "decode(serialized)", expected_serialized->data, expected_serialized->len, encoded, sizeof(encoded)) != 0) {
        return -1;
    }

    LanternRoot root;
    if (root_from_fixed_serialized_bytes(expected_serialized->data, expected_serialized->len, &root) != 0) {
        return record_failure(path, type_name, "failed to compute Fp root");
    }
    return expect_root_equal(path, type_name, "hash_tree_root", expected_root, &root);
}

static int run_fixed_bytes_fixture(
    const char *path,
    const char *type_name,
    const struct lantern_fixture_document *doc,
    int value_idx,
    size_t byte_len,
    const struct byte_buffer *expected_serialized,
    const LanternRoot *expected_root) {
    struct byte_buffer value = {0};
    if (fixture_token_to_bytes(doc, value_idx, &value) != 0 || value.len != byte_len) {
        byte_buffer_reset(&value);
        return record_failure(path, type_name, "invalid fixed-bytes value");
    }

    uint8_t *decoded = (uint8_t *)calloc(byte_len > 0u ? byte_len : 1u, sizeof(uint8_t));
    size_t encoded_len = expected_serialized->len;
    uint8_t *encoded = (uint8_t *)malloc(encoded_len > 0u ? encoded_len : 1u);
    if (!decoded || !encoded
        || ssz_serialize_vector_fixed(value.data, byte_len, sizeof(uint8_t), encoded, encoded_len, &encoded_len) != SSZ_SUCCESS
        || expect_bytes_equal(path, type_name, "encode(value)", expected_serialized->data, expected_serialized->len, encoded, encoded_len) != 0
        || ssz_deserialize_vector_fixed(
               expected_serialized->data,
               expected_serialized->len,
               byte_len,
               sizeof(uint8_t),
               decoded,
               byte_len)
               != SSZ_SUCCESS
        || memcmp(decoded, value.data, byte_len) != 0) {
        free(decoded);
        free(encoded);
        byte_buffer_reset(&value);
        return record_failure(path, type_name, "fixed-bytes roundtrip failed");
    }

    encoded_len = expected_serialized->len;
    if (ssz_serialize_vector_fixed(decoded, byte_len, sizeof(uint8_t), encoded, encoded_len, &encoded_len) != SSZ_SUCCESS
        || expect_bytes_equal(path, type_name, "decode(serialized)", expected_serialized->data, expected_serialized->len, encoded, encoded_len) != 0) {
        free(decoded);
        free(encoded);
        byte_buffer_reset(&value);
        return -1;
    }

    LanternRoot root;
    if (root_from_fixed_serialized_bytes(expected_serialized->data, expected_serialized->len, &root) != 0) {
        free(decoded);
        free(encoded);
        byte_buffer_reset(&value);
        return record_failure(path, type_name, "failed to compute fixed-bytes root");
    }

    free(decoded);
    free(encoded);
    byte_buffer_reset(&value);
    return expect_root_equal(path, type_name, "hash_tree_root", expected_root, &root);
}

static int run_byte_list_fixture(
    const char *path,
    const char *type_name,
    const struct lantern_fixture_document *doc,
    int value_idx,
    size_t byte_limit,
    const struct byte_buffer *expected_serialized,
    const LanternRoot *expected_root) {
    struct byte_buffer value = {0};
    if (parse_hex_data_object(doc, value_idx, &value) != 0) {
        return record_failure(path, type_name, "invalid byte-list value");
    }

    uint8_t *decoded = (uint8_t *)malloc(byte_limit);
    uint8_t *encoded = (uint8_t *)malloc(value.len > 0u ? value.len : 1u);
    uint64_t actual_count = 0u;
    size_t encoded_len = value.len;
    int serialize_rc = ssz_serialize_list_fixed(
        value.data,
        value.len,
        byte_limit,
        sizeof(uint8_t),
        encoded,
        value.len > 0u ? value.len : 1u,
        &encoded_len);
    int deserialize_rc = ssz_deserialize_list_fixed(
        expected_serialized->data,
        expected_serialized->len,
        byte_limit,
        sizeof(uint8_t),
        decoded,
        byte_limit,
        &actual_count);
    if (!decoded || !encoded
        || serialize_rc != SSZ_SUCCESS
        || expect_bytes_equal(path, type_name, "encode(value)", expected_serialized->data, expected_serialized->len, encoded, encoded_len) != 0
        || deserialize_rc != SSZ_SUCCESS
        || actual_count != (uint64_t)value.len
        || (actual_count > 0u && memcmp(decoded, value.data, actual_count) != 0)) {
        free(decoded);
        free(encoded);
        byte_buffer_reset(&value);
        return record_failure(path, type_name, "byte-list roundtrip failed");
    }

    LanternRoot root;
    if (merkleize_bytes_with_optional_length(
            expected_serialized->data,
            expected_serialized->len,
            byte_limit / SSZ_BYTES_PER_CHUNK,
            true,
            value.len,
            &root)
        != 0) {
        free(decoded);
        free(encoded);
        byte_buffer_reset(&value);
        return record_failure(path, type_name, "failed to compute byte-list root");
    }

    free(decoded);
    free(encoded);
    byte_buffer_reset(&value);
    return expect_root_equal(path, type_name, "hash_tree_root", expected_root, &root);
}

static int run_bool_vector_fixture(
    const char *path,
    const char *type_name,
    const struct lantern_fixture_document *doc,
    int value_idx,
    size_t bit_count,
    const struct byte_buffer *expected_serialized,
    const LanternRoot *expected_root) {
    bool *bits = NULL;
    size_t parsed_count = 0u;
    if (parse_bool_data_array(doc, value_idx, &bits, &parsed_count) != 0 || parsed_count != bit_count) {
        free(bits);
        return record_failure(path, type_name, "invalid bitvector value");
    }

    uint8_t *packed = NULL;
    size_t packed_len = 0u;
    if (pack_bool_bits(bits, bit_count, &packed, &packed_len) != 0) {
        free(bits);
        return record_failure(path, type_name, "failed to pack bitvector");
    }
    uint8_t *decoded = (uint8_t *)calloc(packed_len > 0u ? packed_len : 1u, sizeof(*decoded));
    uint8_t *encoded = (uint8_t *)malloc(expected_serialized->len > 0u ? expected_serialized->len : 1u);
    size_t encoded_len = expected_serialized->len;
    if (!decoded || !encoded
        || ssz_serialize_bitvector(packed, packed_len, bit_count, encoded, expected_serialized->len, &encoded_len) != SSZ_SUCCESS
        || expect_bytes_equal(path, type_name, "encode(value)", expected_serialized->data, expected_serialized->len, encoded, encoded_len) != 0
        || ssz_deserialize_bitvector(expected_serialized->data, expected_serialized->len, bit_count, decoded, packed_len) != SSZ_SUCCESS) {
        free(bits);
        free(packed);
        free(decoded);
        free(encoded);
        return record_failure(path, type_name, "bitvector roundtrip failed");
    }
    for (size_t i = 0; i < bit_count; ++i) {
        if (packed_bit_is_set(decoded, bit_count, i) != bits[i]) {
            free(bits);
            free(packed);
            free(decoded);
            free(encoded);
            return record_failure(path, type_name, "decoded bitvector differs from fixture value");
        }
    }

    LanternRoot root;
    if (root_from_fixed_serialized_bytes(expected_serialized->data, expected_serialized->len, &root) != 0) {
        free(bits);
        free(packed);
        free(decoded);
        free(encoded);
        return record_failure(path, type_name, "failed to compute bitvector root");
    }

    free(bits);
    free(packed);
    free(decoded);
    free(encoded);
    return expect_root_equal(path, type_name, "hash_tree_root", expected_root, &root);
}

static int run_bitlist_fixture(
    const char *path,
    const char *type_name,
    const struct lantern_fixture_document *doc,
    int value_idx,
    size_t max_bits,
    const struct byte_buffer *expected_serialized,
    const LanternRoot *expected_root) {
    bool *bits = NULL;
    size_t bit_count = 0u;
    struct lantern_bitlist bitlist;
    lantern_bitlist_init(&bitlist);

    if (parse_bool_data_array(doc, value_idx, &bits, &bit_count) != 0
        || bit_count > max_bits
        || lantern_bitlist_resize(&bitlist, bit_count) != 0) {
        free(bits);
        lantern_bitlist_reset(&bitlist);
        return record_failure(path, type_name, "invalid bitlist value");
    }
    for (size_t i = 0; i < bit_count; ++i) {
        if (lantern_bitlist_set(&bitlist, i, bits[i]) != 0) {
            free(bits);
            lantern_bitlist_reset(&bitlist);
            return record_failure(path, type_name, "failed to build bitlist");
        }
    }

    uint8_t *encoded = (uint8_t *)malloc(expected_serialized->len > 0u ? expected_serialized->len : 1u);
    size_t encoded_len = expected_serialized->len;
    uint8_t *packed = NULL;
    size_t packed_len = 0u;
    if (pack_bool_bits(bits, bit_count, &packed, &packed_len) != 0) {
        free(bits);
        free(encoded);
        lantern_bitlist_reset(&bitlist);
        return record_failure(path, type_name, "failed to pack bitlist");
    }
    size_t decoded_len = (max_bits + 7u) / 8u;
    uint8_t *decoded = (uint8_t *)calloc(decoded_len > 0u ? decoded_len : 1u, sizeof(*decoded));
    uint64_t actual_bits = 0u;
    int serialize_rc = ssz_serialize_bitlist(
        packed,
        packed_len,
        bit_count,
        max_bits,
        encoded,
        expected_serialized->len > 0u ? expected_serialized->len : 1u,
        &encoded_len);
    int deserialize_rc = ssz_deserialize_bitlist(
        expected_serialized->data,
        expected_serialized->len,
        max_bits,
        decoded,
        decoded_len,
        &actual_bits);
    if (!decoded || !encoded
        || serialize_rc != SSZ_SUCCESS
        || expect_bytes_equal(path, type_name, "encode(value)", expected_serialized->data, expected_serialized->len, encoded, encoded_len) != 0
        || deserialize_rc != SSZ_SUCCESS
        || actual_bits != (uint64_t)bit_count) {
        free(bits);
        free(packed);
        free(decoded);
        free(encoded);
        lantern_bitlist_reset(&bitlist);
        return record_failure(path, type_name, "bitlist roundtrip failed");
    }
    for (size_t i = 0; i < bit_count; ++i) {
        if (packed_bit_is_set(decoded, bit_count, i) != bits[i]) {
            free(bits);
            free(packed);
            free(decoded);
            free(encoded);
            lantern_bitlist_reset(&bitlist);
            return record_failure(path, type_name, "decoded bitlist differs from fixture value");
        }
    }

    LanternRoot root;
    size_t chunk_limit = (max_bits + (SSZ_BYTES_PER_CHUNK * 8u) - 1u) / (SSZ_BYTES_PER_CHUNK * 8u);
    if (lantern_merkleize_bitlist(&bitlist, chunk_limit == 0u ? 1u : chunk_limit, &root) != SSZ_SUCCESS) {
        free(bits);
        free(decoded);
        free(encoded);
        lantern_bitlist_reset(&bitlist);
        return record_failure(path, type_name, "failed to compute bitlist root");
    }

    free(bits);
    free(packed);
    free(decoded);
    free(encoded);
    lantern_bitlist_reset(&bitlist);
    return expect_root_equal(path, type_name, "hash_tree_root", expected_root, &root);
}

static int run_uint_vector_fixture(
    const char *path,
    const char *type_name,
    const struct lantern_fixture_document *doc,
    int value_idx,
    unsigned bits,
    size_t element_count,
    const struct byte_buffer *expected_serialized,
    const LanternRoot *expected_root) {
    int rc = -1;
    if (bits == 16u) {
        uint32_t *parsed = NULL;
        size_t count = 0u;
        uint16_t decoded[8];
        uint8_t encoded[64];
        size_t encoded_len = sizeof(encoded);
        if (parse_u32_data_array(doc, value_idx, &parsed, &count) != 0 || count != element_count) {
            free(parsed);
            return record_failure(path, type_name, "invalid uint16 vector value");
        }
        uint16_t values[8];
        for (size_t i = 0; i < element_count; ++i) {
            if (parsed[i] > UINT16_MAX) {
                free(parsed);
                return record_failure(path, type_name, "uint16 vector value out of range");
            }
            values[i] = (uint16_t)parsed[i];
        }
        if (ssz_serialize_vector_fixed(
                (const uint8_t *)values,
                element_count,
                sizeof(uint16_t),
                encoded,
                sizeof(encoded),
                &encoded_len)
                != SSZ_SUCCESS
            || expect_bytes_equal(path, type_name, "encode(value)", expected_serialized->data, expected_serialized->len, encoded, encoded_len) != 0
            || ssz_deserialize_vector_fixed(
                   expected_serialized->data,
                   expected_serialized->len,
                   element_count,
                   sizeof(uint16_t),
                   (uint8_t *)decoded,
                   sizeof(decoded))
                   != SSZ_SUCCESS) {
            free(parsed);
            return record_failure(path, type_name, "uint16 vector roundtrip failed");
        }
        for (size_t i = 0; i < element_count; ++i) {
            if (decoded[i] != values[i]) {
                free(parsed);
                return record_failure(path, type_name, "decoded uint16 vector differs from fixture value");
            }
        }
        LanternRoot root;
        rc = root_from_fixed_serialized_bytes(expected_serialized->data, expected_serialized->len, &root) == 0
            ? expect_root_equal(path, type_name, "hash_tree_root", expected_root, &root)
            : record_failure(path, type_name, "failed to compute uint16 vector root");
        free(parsed);
        return rc;
    }

    if (bits == 64u) {
        uint64_t *values = NULL;
        size_t count = 0u;
        uint64_t decoded[8];
        uint8_t encoded[128];
        size_t encoded_len = sizeof(encoded);
        if (parse_u64_data_array(doc, value_idx, &values, &count) != 0 || count != element_count) {
            free(values);
            return record_failure(path, type_name, "invalid uint64 vector value");
        }
        if (ssz_serialize_vector_fixed(
                (const uint8_t *)values,
                element_count,
                sizeof(uint64_t),
                encoded,
                sizeof(encoded),
                &encoded_len)
                != SSZ_SUCCESS
            || expect_bytes_equal(path, type_name, "encode(value)", expected_serialized->data, expected_serialized->len, encoded, encoded_len) != 0
            || ssz_deserialize_vector_fixed(
                   expected_serialized->data,
                   expected_serialized->len,
                   element_count,
                   sizeof(uint64_t),
                   (uint8_t *)decoded,
                   sizeof(decoded))
                   != SSZ_SUCCESS) {
            free(values);
            return record_failure(path, type_name, "uint64 vector roundtrip failed");
        }
        for (size_t i = 0; i < element_count; ++i) {
            if (decoded[i] != values[i]) {
                free(values);
                return record_failure(path, type_name, "decoded uint64 vector differs from fixture value");
            }
        }
        LanternRoot root;
        rc = root_from_fixed_serialized_bytes(expected_serialized->data, expected_serialized->len, &root) == 0
            ? expect_root_equal(path, type_name, "hash_tree_root", expected_root, &root)
            : record_failure(path, type_name, "failed to compute uint64 vector root");
        free(values);
        return rc;
    }

    return record_failure(path, type_name, "unsupported uint vector width");
}

static int run_uint32_list_fixture(
    const char *path,
    const char *type_name,
    const struct lantern_fixture_document *doc,
    int value_idx,
    const struct byte_buffer *expected_serialized,
    const LanternRoot *expected_root) {
    uint32_t *values = NULL;
    size_t count = 0u;
    uint32_t decoded[SAMPLE_UINT32_LIST_LIMIT];
    uint64_t actual_count = 0u;
    uint8_t encoded[64];
    size_t encoded_len = sizeof(encoded);
    if (parse_u32_data_array(doc, value_idx, &values, &count) != 0 || count > SAMPLE_UINT32_LIST_LIMIT) {
        free(values);
        return record_failure(path, type_name, "invalid uint32 list value");
    }
    if (count == 0u) {
        encoded_len = 0u;
    }
    int serialize_rc = ssz_serialize_list_fixed(
        (const uint8_t *)values,
        count,
        SAMPLE_UINT32_LIST_LIMIT,
        sizeof(uint32_t),
        encoded,
        sizeof(encoded),
        &encoded_len);
    int deserialize_rc = ssz_deserialize_list_fixed(
        expected_serialized->data,
        expected_serialized->len,
        SAMPLE_UINT32_LIST_LIMIT,
        sizeof(uint32_t),
        (uint8_t *)decoded,
        sizeof(decoded),
        &actual_count);
    if (serialize_rc != SSZ_SUCCESS
        || expect_bytes_equal(path, type_name, "encode(value)", expected_serialized->data, expected_serialized->len, encoded, encoded_len) != 0
        || deserialize_rc != SSZ_SUCCESS
        || actual_count != (uint64_t)count) {
        free(values);
        return record_failure(path, type_name, "uint32 list roundtrip failed");
    }
    for (size_t i = 0; i < count; ++i) {
        if (decoded[i] != values[i]) {
            free(values);
            return record_failure(path, type_name, "decoded uint32 list differs from fixture value");
        }
    }

    LanternRoot root;
    if (merkleize_bytes_with_optional_length(
            expected_serialized->data,
            expected_serialized->len,
            (SAMPLE_UINT32_LIST_LIMIT * sizeof(uint32_t)) / SSZ_BYTES_PER_CHUNK,
            true,
            count,
            &root)
        != 0) {
        free(values);
        return record_failure(path, type_name, "failed to compute uint32 list root");
    }

    free(values);
    return expect_root_equal(path, type_name, "hash_tree_root", expected_root, &root);
}

static int run_uint64_list_fixture(
    const char *path,
    const char *type_name,
    const struct lantern_fixture_document *doc,
    int value_idx,
    size_t max_count,
    const struct byte_buffer *expected_serialized,
    const LanternRoot *expected_root) {
    uint64_t *values = NULL;
    uint64_t *decoded = NULL;
    uint8_t *encoded = NULL;
    size_t count = 0u;
    uint64_t actual_count = 0u;
    int rc = -1;

    if (parse_u64_data_array(doc, value_idx, &values, &count) != 0 || count > max_count) {
        rc = record_failure(path, type_name, "invalid uint64 list value");
        goto cleanup;
    }

    decoded = (uint64_t *)calloc(max_count > 0u ? max_count : 1u, sizeof(*decoded));
    encoded = (uint8_t *)malloc(expected_serialized->len > 0u ? expected_serialized->len : 1u);
    if (!decoded || !encoded) {
        rc = record_failure(path, type_name, "allocation failed");
        goto cleanup;
    }

    size_t encoded_len = expected_serialized->len;
    if (count == 0u) {
        encoded_len = 0u;
    }
    int serialize_rc = ssz_serialize_list_fixed(
        (const uint8_t *)values,
        count,
        max_count,
        sizeof(uint64_t),
        encoded,
        expected_serialized->len > 0u ? expected_serialized->len : 1u,
        &encoded_len);
    int deserialize_rc = ssz_deserialize_list_fixed(
        expected_serialized->data,
        expected_serialized->len,
        max_count,
        sizeof(uint64_t),
        (uint8_t *)decoded,
        max_count * sizeof(uint64_t),
        &actual_count);
    if (serialize_rc != SSZ_SUCCESS
        || expect_bytes_equal(path, type_name, "encode(value)", expected_serialized->data, expected_serialized->len, encoded, encoded_len) != 0
        || deserialize_rc != SSZ_SUCCESS
        || actual_count != (uint64_t)count) {
        rc = record_failure(path, type_name, "uint64 list roundtrip failed");
        goto cleanup;
    }
    for (size_t i = 0; i < count; ++i) {
        if (decoded[i] != values[i]) {
            rc = record_failure(path, type_name, "decoded uint64 list differs from fixture value");
            goto cleanup;
        }
    }

    LanternRoot root;
    size_t chunk_limit = ((max_count * sizeof(uint64_t)) + SSZ_BYTES_PER_CHUNK - 1u) / SSZ_BYTES_PER_CHUNK;
    if (merkleize_bytes_with_optional_length(
            expected_serialized->data,
            expected_serialized->len,
            chunk_limit,
            true,
            count,
            &root)
        != 0) {
        rc = record_failure(path, type_name, "failed to compute uint64 list root");
        goto cleanup;
    }

    rc = expect_root_equal(path, type_name, "hash_tree_root", expected_root, &root);

cleanup:
    free(values);
    free(decoded);
    free(encoded);
    return rc;
}

static int run_bytes32_list_fixture(
    const char *path,
    const char *type_name,
    const struct lantern_fixture_document *doc,
    int value_idx,
    const struct byte_buffer *expected_serialized,
    const LanternRoot *expected_root) {
    struct lantern_root_list roots;
    if (parse_root_list_object(doc, value_idx, &roots) != 0 || roots.length > SAMPLE_BYTES32_LIST_LIMIT) {
        lantern_root_list_reset(&roots);
        return record_failure(path, type_name, "invalid Bytes32 list value");
    }

    size_t expected_len = roots.length * LANTERN_ROOT_SIZE;
    uint8_t *encoded = (uint8_t *)malloc(expected_len > 0u ? expected_len : 1u);
    if (!encoded) {
        lantern_root_list_reset(&roots);
        return record_failure(path, type_name, "allocation failed");
    }
    if (expected_len > 0u) {
        memcpy(encoded, roots.items, expected_len);
    }

    if (expect_bytes_equal(path, type_name, "encode(value)", expected_serialized->data, expected_serialized->len, encoded, expected_len) != 0) {
        free(encoded);
        lantern_root_list_reset(&roots);
        return -1;
    }

    if (expected_serialized->len != expected_len) {
        free(encoded);
        lantern_root_list_reset(&roots);
        return record_failure(path, type_name, "serialized length mismatch");
    }

    LanternRoot root;
    if (merkleize_bytes_with_optional_length(
            expected_serialized->data,
            expected_serialized->len,
            SAMPLE_BYTES32_LIST_LIMIT,
            true,
            roots.length,
            &root)
        != 0) {
        free(encoded);
        lantern_root_list_reset(&roots);
        return record_failure(path, type_name, "failed to compute Bytes32 list root");
    }

    free(encoded);
    lantern_root_list_reset(&roots);
    return expect_root_equal(path, type_name, "hash_tree_root", expected_root, &root);
}

static int run_union_fixture(
    const char *path,
    const char *type_name,
    const struct lantern_fixture_document *doc,
    int value_idx,
    bool none_capable,
    const struct byte_buffer *expected_serialized,
    const LanternRoot *expected_root) {
    int selector_idx = lantern_fixture_object_get_field(doc, value_idx, "selector");
    int inner_value_idx = lantern_fixture_object_get_field(doc, value_idx, "value");
    uint64_t selector = 0u;
    if (selector_idx < 0 || inner_value_idx < 0 || lantern_fixture_token_to_uint64(doc, selector_idx, &selector) != 0) {
        return record_failure(path, type_name, "invalid union value");
    }

    uint8_t encoded[16];
    size_t encoded_len = 1u;
    encoded[0] = (uint8_t)selector;
    LanternRoot value_root;
    memset(&value_root, 0, sizeof(value_root));

    if (none_capable && selector == 0u) {
        const jsmntok_t *tok = lantern_fixture_token(doc, inner_value_idx);
        if (!tok || tok->type != JSMN_PRIMITIVE
            || strncmp(doc->text + tok->start, "null", (size_t)(tok->end - tok->start)) != 0) {
            return record_failure(path, type_name, "expected null union arm");
        }
    } else if (selector == 0u) {
        uint64_t value = 0u;
        size_t one_len = 1u;
        if (lantern_fixture_token_to_uint64(doc, inner_value_idx, &value) != 0 || value > UINT8_MAX
            || ssz_serialize_uint8((uint8_t)value, encoded + 1u) != SSZ_SUCCESS) {
            return record_failure(path, type_name, "invalid uint8 union arm");
        }
        encoded_len += one_len;
        if (root_from_fixed_serialized_bytes(encoded + 1u, one_len, &value_root) != 0) {
            return record_failure(path, type_name, "failed to compute uint8 union arm root");
        }
    } else if (selector == 1u) {
        uint64_t value = 0u;
        uint16_t v16 = 0u;
        size_t two_len = 2u;
        if (lantern_fixture_token_to_uint64(doc, inner_value_idx, &value) != 0 || value > UINT16_MAX) {
            return record_failure(path, type_name, "invalid uint16 union arm");
        }
        v16 = (uint16_t)value;
        if (ssz_serialize_uint16(v16, encoded + 1u) != SSZ_SUCCESS) {
            return record_failure(path, type_name, "failed to encode uint16 union arm");
        }
        encoded_len += two_len;
        if (root_from_fixed_serialized_bytes(encoded + 1u, two_len, &value_root) != 0) {
            return record_failure(path, type_name, "failed to compute uint16 union arm root");
        }
    } else if (selector == 2u && none_capable) {
        uint64_t value = 0u;
        uint32_t v32 = 0u;
        size_t four_len = 4u;
        if (lantern_fixture_token_to_uint64(doc, inner_value_idx, &value) != 0 || value > UINT32_MAX) {
            return record_failure(path, type_name, "invalid uint32 union arm");
        }
        v32 = (uint32_t)value;
        if (ssz_serialize_uint32(v32, encoded + 1u) != SSZ_SUCCESS) {
            return record_failure(path, type_name, "failed to encode uint32 union arm");
        }
        encoded_len += four_len;
        if (root_from_fixed_serialized_bytes(encoded + 1u, four_len, &value_root) != 0) {
            return record_failure(path, type_name, "failed to compute uint32 union arm root");
        }
    } else {
        return run_unsupported_fixture(path, type_name, NULL, "union selector not supported by runner");
    }

    if (expect_bytes_equal(path, type_name, "encode(value)", expected_serialized->data, expected_serialized->len, encoded, encoded_len) != 0) {
        return -1;
    }

    if (expected_serialized->len == 0u || expected_serialized->data[0] != selector) {
        return record_failure(path, type_name, "decoded union selector mismatch");
    }

    ssz_chunk_t value_chunk;
    ssz_chunk_t root_chunk;
    LanternRoot root;
    chunk_from_root(&value_root, &value_chunk);
    if (ssz_mix_in_selector(&value_chunk, (uint8_t)selector, NULL, &root_chunk) != SSZ_SUCCESS) {
        return record_failure(path, type_name, "failed to compute union root");
    }
    root_from_chunk(&root_chunk, &root);
    return expect_root_equal(path, type_name, "hash_tree_root", expected_root, &root);
}

static int run_public_key_fixture(
    const char *path,
    const char *type_name,
    const struct lantern_fixture_document *doc,
    int value_idx,
    const struct byte_buffer *expected_serialized,
    const LanternRoot *expected_root) {
    struct byte_buffer parsed = {0};
    if (parse_public_key_object(doc, value_idx, &parsed) != 0
        || expect_bytes_equal(path, type_name, "encode(value)", expected_serialized->data, expected_serialized->len, parsed.data, parsed.len) != 0) {
        byte_buffer_reset(&parsed);
        return record_failure(path, type_name, "public key roundtrip failed");
    }

    LanternRoot root;
    if (root_from_fixed_serialized_bytes(expected_serialized->data, expected_serialized->len, &root) != 0) {
        byte_buffer_reset(&parsed);
        return record_failure(path, type_name, "failed to compute public key root");
    }
    byte_buffer_reset(&parsed);
    return expect_root_equal(path, type_name, "hash_tree_root", expected_root, &root);
}

static int run_signature_fixture(
    const char *path,
    const char *type_name,
    const struct lantern_fixture_document *doc,
    int value_idx,
    const struct byte_buffer *expected_serialized,
    const LanternRoot *expected_root) {
    struct byte_buffer parsed = {0};
    LanternSignature signature;
    memset(&signature, 0, sizeof(signature));
    if (fixture_token_to_bytes(doc, value_idx, &parsed) != 0 || parsed.len != LANTERN_SIGNATURE_SIZE) {
        byte_buffer_reset(&parsed);
        return record_failure(path, type_name, "invalid signature fixture value");
    }
    if (expect_bytes_equal(path, type_name, "encode(value)", expected_serialized->data, expected_serialized->len, parsed.data, parsed.len) != 0) {
        byte_buffer_reset(&parsed);
        return -1;
    }
    memcpy(signature.bytes, expected_serialized->data, LANTERN_SIGNATURE_SIZE);
    LanternRoot root;
    if (lantern_hash_tree_root_signature(&signature, &root) != SSZ_SUCCESS) {
        byte_buffer_reset(&parsed);
        return record_failure(path, type_name, "failed to compute signature root");
    }
    byte_buffer_reset(&parsed);
    return expect_root_equal(path, type_name, "hash_tree_root", expected_root, &root);
}

static int run_hash_tree_opening_fixture(
    const char *path,
    const char *type_name,
    const struct lantern_fixture_document *doc,
    int value_idx,
    const struct byte_buffer *expected_serialized,
    const LanternRoot *expected_root) {
    struct byte_buffer parsed = {0};
    size_t sibling_count = 0u;
    if (parse_hash_tree_opening_object(doc, value_idx, &parsed, &sibling_count) != 0
        || expect_bytes_equal(path, type_name, "encode(value)", expected_serialized->data, expected_serialized->len, parsed.data, parsed.len) != 0) {
        byte_buffer_reset(&parsed);
        return record_failure(path, type_name, "hash tree opening roundtrip failed");
    }

    LanternRoot root;
    if (compute_hash_tree_opening_root_from_serialized(expected_serialized->data, expected_serialized->len, &root) != 0) {
        byte_buffer_reset(&parsed);
        return record_failure(path, type_name, "failed to compute hash tree opening root");
    }
    byte_buffer_reset(&parsed);
    return expect_root_equal(path, type_name, "hash_tree_root", expected_root, &root);
}

static int run_hash_tree_layer_fixture(
    const char *path,
    const char *type_name,
    const struct lantern_fixture_document *doc,
    int value_idx,
    const struct byte_buffer *expected_serialized,
    const LanternRoot *expected_root) {
    struct byte_buffer parsed = {0};
    uint64_t start_index = 0u;
    size_t node_count = 0u;
    if (parse_hash_tree_layer_object(doc, value_idx, &parsed, &start_index, &node_count) != 0
        || expect_bytes_equal(path, type_name, "encode(value)", expected_serialized->data, expected_serialized->len, parsed.data, parsed.len) != 0) {
        byte_buffer_reset(&parsed);
        return record_failure(path, type_name, "hash tree layer roundtrip failed");
    }

    LanternRoot root;
    const uint8_t *nodes_bytes = expected_serialized->data + sizeof(uint64_t) + sizeof(uint32_t);
    if (compute_hash_tree_layer_root(start_index, nodes_bytes, node_count, &root) != 0) {
        byte_buffer_reset(&parsed);
        return record_failure(path, type_name, "failed to compute hash tree layer root");
    }
    byte_buffer_reset(&parsed);
    return expect_root_equal(path, type_name, "hash_tree_root", expected_root, &root);
}

static int run_config_fixture(
    const char *path,
    const char *type_name,
    const struct lantern_fixture_document *doc,
    int value_idx,
    const struct byte_buffer *expected_serialized,
    const LanternRoot *expected_root) {
    LanternConfig config = {0};
    int genesis_idx = lantern_fixture_object_get_field(doc, value_idx, "genesisTime");
    if (genesis_idx < 0 || lantern_fixture_token_to_uint64(doc, genesis_idx, &config.genesis_time) != 0) {
        return record_failure(path, type_name, "invalid config fixture");
    }
    uint8_t encoded[LANTERN_CONFIG_SSZ_SIZE];
    size_t encoded_len = sizeof(encoded);
    if (lantern_ssz_encode_config(&config, encoded, sizeof(encoded), &encoded_len) != SSZ_SUCCESS
        || expect_bytes_equal(path, type_name, "encode(value)", expected_serialized->data, expected_serialized->len, encoded, encoded_len) != 0) {
        return record_failure(path, type_name, "config encode failed");
    }
    LanternConfig decoded = {0};
    if (lantern_ssz_decode_config(&decoded, expected_serialized->data, expected_serialized->len) != SSZ_SUCCESS
        || lantern_ssz_encode_config(&decoded, encoded, sizeof(encoded), &encoded_len) != SSZ_SUCCESS
        || expect_bytes_equal(path, type_name, "decode(serialized)", expected_serialized->data, expected_serialized->len, encoded, encoded_len) != 0) {
        return record_failure(path, type_name, "config decode failed");
    }
    LanternRoot root;
    if (lantern_hash_tree_root_config(&config, &root) != SSZ_SUCCESS) {
        return record_failure(path, type_name, "config root failed");
    }
    return expect_root_equal(path, type_name, "hash_tree_root", expected_root, &root);
}

static int run_checkpoint_fixture(
    const char *path,
    const char *type_name,
    const struct lantern_fixture_document *doc,
    int value_idx,
    const struct byte_buffer *expected_serialized,
    const LanternRoot *expected_root) {
    LanternCheckpoint checkpoint;
    if (parse_checkpoint_object(doc, value_idx, &checkpoint) != 0) {
        return record_failure(path, type_name, "invalid checkpoint fixture");
    }
    uint8_t encoded[LANTERN_CHECKPOINT_SSZ_SIZE];
    size_t encoded_len = sizeof(encoded);
    if (lantern_ssz_encode_checkpoint(&checkpoint, encoded, sizeof(encoded), &encoded_len) != SSZ_SUCCESS
        || expect_bytes_equal(path, type_name, "encode(value)", expected_serialized->data, expected_serialized->len, encoded, encoded_len) != 0) {
        return record_failure(path, type_name, "checkpoint encode failed");
    }
    LanternCheckpoint decoded;
    if (lantern_ssz_decode_checkpoint(&decoded, expected_serialized->data, expected_serialized->len) != SSZ_SUCCESS
        || lantern_ssz_encode_checkpoint(&decoded, encoded, sizeof(encoded), &encoded_len) != SSZ_SUCCESS
        || expect_bytes_equal(path, type_name, "decode(serialized)", expected_serialized->data, expected_serialized->len, encoded, encoded_len) != 0) {
        return record_failure(path, type_name, "checkpoint decode failed");
    }
    LanternRoot root;
    if (lantern_hash_tree_root_checkpoint(&checkpoint, &root) != SSZ_SUCCESS) {
        return record_failure(path, type_name, "checkpoint root failed");
    }
    return expect_root_equal(path, type_name, "hash_tree_root", expected_root, &root);
}

static int run_attestation_data_fixture(
    const char *path,
    const char *type_name,
    const struct lantern_fixture_document *doc,
    int value_idx,
    const struct byte_buffer *expected_serialized,
    const LanternRoot *expected_root) {
    LanternAttestationData data;
    if (lantern_fixture_parse_attestation_data(doc, value_idx, &data) != 0) {
        return record_failure(path, type_name, "invalid attestation-data fixture");
    }
    uint8_t encoded[LANTERN_ATTESTATION_DATA_SSZ_SIZE];
    size_t encoded_len = sizeof(encoded);
    if (lantern_ssz_encode_attestation_data(&data, encoded, sizeof(encoded), &encoded_len) != SSZ_SUCCESS
        || expect_bytes_equal(path, type_name, "encode(value)", expected_serialized->data, expected_serialized->len, encoded, encoded_len) != 0) {
        return record_failure(path, type_name, "attestation-data encode failed");
    }
    LanternAttestationData decoded;
    if (lantern_ssz_decode_attestation_data(&decoded, expected_serialized->data, expected_serialized->len) != SSZ_SUCCESS
        || lantern_ssz_encode_attestation_data(&decoded, encoded, sizeof(encoded), &encoded_len) != SSZ_SUCCESS
        || expect_bytes_equal(path, type_name, "decode(serialized)", expected_serialized->data, expected_serialized->len, encoded, encoded_len) != 0) {
        return record_failure(path, type_name, "attestation-data decode failed");
    }
    LanternRoot root;
    if (lantern_hash_tree_root_attestation_data(&data, &root) != SSZ_SUCCESS) {
        return record_failure(path, type_name, "attestation-data root failed");
    }
    return expect_root_equal(path, type_name, "hash_tree_root", expected_root, &root);
}

static int run_attestation_fixture(
    const char *path,
    const char *type_name,
    const struct lantern_fixture_document *doc,
    int value_idx,
    const struct byte_buffer *expected_serialized,
    const LanternRoot *expected_root) {
    LanternVote vote;
    if (parse_attestation_vote_object(doc, value_idx, &vote) != 0) {
        return record_failure(path, type_name, "invalid attestation fixture");
    }
    uint8_t encoded[LANTERN_VOTE_SSZ_SIZE];
    size_t encoded_len = sizeof(encoded);
    if (lantern_ssz_encode_vote(&vote, encoded, sizeof(encoded), &encoded_len) != SSZ_SUCCESS
        || expect_bytes_equal(path, type_name, "encode(value)", expected_serialized->data, expected_serialized->len, encoded, encoded_len) != 0) {
        return record_failure(path, type_name, "attestation encode failed");
    }
    LanternVote decoded;
    if (lantern_ssz_decode_vote(&decoded, expected_serialized->data, expected_serialized->len) != SSZ_SUCCESS
        || lantern_ssz_encode_vote(&decoded, encoded, sizeof(encoded), &encoded_len) != SSZ_SUCCESS
        || expect_bytes_equal(path, type_name, "decode(serialized)", expected_serialized->data, expected_serialized->len, encoded, encoded_len) != 0) {
        return record_failure(path, type_name, "attestation decode failed");
    }
    LanternRoot root;
    if (lantern_hash_tree_root_vote(&vote, &root) != SSZ_SUCCESS) {
        return record_failure(path, type_name, "attestation root failed");
    }
    return expect_root_equal(path, type_name, "hash_tree_root", expected_root, &root);
}

static int run_signed_attestation_fixture(
    const char *path,
    const char *type_name,
    const struct lantern_fixture_document *doc,
    int value_idx,
    const struct byte_buffer *expected_serialized,
    const LanternRoot *expected_root) {
    LanternSignedVote vote;
    memset(&vote, 0, sizeof(vote));
    if (lantern_fixture_parse_attestation_message(doc, value_idx, &vote) != 0) {
        return record_failure(path, type_name, "invalid signed-attestation fixture");
    }
    uint8_t encoded[LANTERN_SIGNED_VOTE_SSZ_SIZE];
    size_t encoded_len = sizeof(encoded);
    if (lantern_ssz_encode_signed_vote(&vote, encoded, sizeof(encoded), &encoded_len) != SSZ_SUCCESS
        || expect_bytes_equal(path, type_name, "encode(value)", expected_serialized->data, expected_serialized->len, encoded, encoded_len) != 0) {
        return record_failure(path, type_name, "signed-attestation encode failed");
    }
    LanternSignedVote decoded;
    memset(&decoded, 0, sizeof(decoded));
    if (lantern_ssz_decode_signed_vote(&decoded, expected_serialized->data, expected_serialized->len) != SSZ_SUCCESS
        || lantern_ssz_encode_signed_vote(&decoded, encoded, sizeof(encoded), &encoded_len) != SSZ_SUCCESS
        || expect_bytes_equal(path, type_name, "decode(serialized)", expected_serialized->data, expected_serialized->len, encoded, encoded_len) != 0) {
        return record_failure(path, type_name, "signed-attestation decode failed");
    }
    LanternRoot root;
    if (lantern_hash_tree_root_signed_vote(&vote, &root) != SSZ_SUCCESS) {
        return record_failure(path, type_name, "signed-attestation root failed");
    }
    return expect_root_equal(path, type_name, "hash_tree_root", expected_root, &root);
}

static int run_aggregated_attestation_fixture(
    const char *path,
    const char *type_name,
    const struct lantern_fixture_document *doc,
    int value_idx,
    const struct byte_buffer *expected_serialized,
    const LanternRoot *expected_root) {
    LanternAggregatedAttestation attestation;
    lantern_aggregated_attestation_init(&attestation);
    if (lantern_fixture_parse_aggregated_attestation(doc, value_idx, &attestation) != 0) {
        lantern_aggregated_attestation_reset(&attestation);
        return record_failure(path, type_name, "invalid aggregated-attestation fixture");
    }
    size_t encoded_capacity = expected_serialized->len > 0u ? expected_serialized->len : 1u;
    uint8_t *encoded = (uint8_t *)malloc(encoded_capacity);
    size_t encoded_len = 0u;
    if (!encoded
        || lantern_ssz_encode_aggregated_attestation(&attestation, encoded, encoded_capacity, &encoded_len) != SSZ_SUCCESS
        || expect_bytes_equal(path, type_name, "encode(value)", expected_serialized->data, expected_serialized->len, encoded, encoded_len) != 0) {
        free(encoded);
        lantern_aggregated_attestation_reset(&attestation);
        return record_failure(path, type_name, "aggregated-attestation encode failed");
    }
    LanternAggregatedAttestation decoded;
    lantern_aggregated_attestation_init(&decoded);
    if (lantern_ssz_decode_aggregated_attestation(&decoded, expected_serialized->data, expected_serialized->len) != SSZ_SUCCESS
        || lantern_ssz_encode_aggregated_attestation(&decoded, encoded, encoded_capacity, &encoded_len) != SSZ_SUCCESS
        || expect_bytes_equal(path, type_name, "decode(serialized)", expected_serialized->data, expected_serialized->len, encoded, encoded_len) != 0) {
        free(encoded);
        lantern_aggregated_attestation_reset(&attestation);
        lantern_aggregated_attestation_reset(&decoded);
        return record_failure(path, type_name, "aggregated-attestation decode failed");
    }
    LanternRoot root;
    if (lantern_hash_tree_root_aggregated_attestation(&attestation, &root) != SSZ_SUCCESS) {
        free(encoded);
        lantern_aggregated_attestation_reset(&attestation);
        lantern_aggregated_attestation_reset(&decoded);
        return record_failure(path, type_name, "aggregated-attestation root failed");
    }
    free(encoded);
    lantern_aggregated_attestation_reset(&attestation);
    lantern_aggregated_attestation_reset(&decoded);
    return expect_root_equal(path, type_name, "hash_tree_root", expected_root, &root);
}

static int run_aggregated_signature_proof_fixture(
    const char *path,
    const char *type_name,
    const struct lantern_fixture_document *doc,
    int value_idx,
    const struct byte_buffer *expected_serialized,
    const LanternRoot *expected_root) {
    LanternAggregatedSignatureProof proof;
    lantern_aggregated_signature_proof_init(&proof);
    if (lantern_fixture_parse_signature_proof(doc, value_idx, &proof) != 0) {
        lantern_aggregated_signature_proof_reset(&proof);
        return record_failure(path, type_name, "invalid aggregated-signature-proof fixture");
    }
    size_t encoded_capacity = expected_serialized->len > 0u ? expected_serialized->len : 1u;
    uint8_t *encoded = (uint8_t *)malloc(encoded_capacity);
    size_t encoded_len = 0u;
    if (!encoded
        || lantern_ssz_encode_aggregated_signature_proof(&proof, encoded, encoded_capacity, &encoded_len) != SSZ_SUCCESS
        || expect_bytes_equal(path, type_name, "encode(value)", expected_serialized->data, expected_serialized->len, encoded, encoded_len) != 0) {
        free(encoded);
        lantern_aggregated_signature_proof_reset(&proof);
        return record_failure(path, type_name, "aggregated-signature-proof encode failed");
    }
    LanternAggregatedSignatureProof decoded;
    lantern_aggregated_signature_proof_init(&decoded);
    if (lantern_ssz_decode_aggregated_signature_proof(&decoded, expected_serialized->data, expected_serialized->len) != SSZ_SUCCESS
        || lantern_ssz_encode_aggregated_signature_proof(&decoded, encoded, encoded_capacity, &encoded_len) != SSZ_SUCCESS
        || expect_bytes_equal(path, type_name, "decode(serialized)", expected_serialized->data, expected_serialized->len, encoded, encoded_len) != 0) {
        free(encoded);
        lantern_aggregated_signature_proof_reset(&proof);
        lantern_aggregated_signature_proof_reset(&decoded);
        return record_failure(path, type_name, "aggregated-signature-proof decode failed");
    }
    LanternRoot root;
    if (lantern_hash_tree_root_aggregated_signature_proof(&proof, &root) != SSZ_SUCCESS) {
        free(encoded);
        lantern_aggregated_signature_proof_reset(&proof);
        lantern_aggregated_signature_proof_reset(&decoded);
        return record_failure(path, type_name, "aggregated-signature-proof root failed");
    }
    free(encoded);
    lantern_aggregated_signature_proof_reset(&proof);
    lantern_aggregated_signature_proof_reset(&decoded);
    return expect_root_equal(path, type_name, "hash_tree_root", expected_root, &root);
}

static int parse_multi_message_aggregate_object(
    const struct lantern_fixture_document *doc,
    int value_idx,
    LanternByteList *out_aggregate) {
    if (!doc || !out_aggregate) {
        return -1;
    }
    int proof_idx = lantern_fixture_object_get_field(doc, value_idx, "proof");
    struct byte_buffer proof = {0};
    if (proof_idx < 0 || parse_hex_data_object(doc, proof_idx, &proof) != 0) {
        byte_buffer_reset(&proof);
        return -1;
    }
    if (proof.len > BYTELIST_512KIB_LIMIT
        || lantern_byte_list_resize(out_aggregate, proof.len + SSZ_BYTES_PER_LENGTH_OFFSET) != 0) {
        byte_buffer_reset(&proof);
        return -1;
    }
    write_u32_le((uint32_t)SSZ_BYTES_PER_LENGTH_OFFSET, out_aggregate->data);
    if (proof.len > 0u) {
        memcpy(out_aggregate->data + SSZ_BYTES_PER_LENGTH_OFFSET, proof.data, proof.len);
    }
    byte_buffer_reset(&proof);
    return 0;
}

static int run_multi_message_aggregate_fixture(
    const char *path,
    const char *type_name,
    const struct lantern_fixture_document *doc,
    int value_idx,
    const struct byte_buffer *expected_serialized,
    const LanternRoot *expected_root) {
    LanternByteList aggregate;
    lantern_byte_list_init(&aggregate);
    if (parse_multi_message_aggregate_object(doc, value_idx, &aggregate) != 0) {
        lantern_byte_list_reset(&aggregate);
        return record_failure(path, type_name, "invalid multi-message aggregate fixture");
    }

    size_t encoded_capacity = expected_serialized->len > 0u ? expected_serialized->len : 1u;
    uint8_t *encoded = (uint8_t *)malloc(encoded_capacity);
    size_t encoded_len = 0u;
    if (!encoded
        || lantern_ssz_encode_multi_message_aggregate(&aggregate, encoded, encoded_capacity, &encoded_len) != SSZ_SUCCESS
        || expect_bytes_equal(path, type_name, "encode(value)", expected_serialized->data, expected_serialized->len, encoded, encoded_len) != 0) {
        free(encoded);
        lantern_byte_list_reset(&aggregate);
        return record_failure(path, type_name, "multi-message aggregate encode failed");
    }

    LanternByteList decoded;
    lantern_byte_list_init(&decoded);
    if (lantern_ssz_decode_multi_message_aggregate(&decoded, expected_serialized->data, expected_serialized->len) != SSZ_SUCCESS
        || lantern_ssz_encode_multi_message_aggregate(&decoded, encoded, encoded_capacity, &encoded_len) != SSZ_SUCCESS
        || expect_bytes_equal(path, type_name, "decode(serialized)", expected_serialized->data, expected_serialized->len, encoded, encoded_len) != 0) {
        free(encoded);
        lantern_byte_list_reset(&aggregate);
        lantern_byte_list_reset(&decoded);
        return record_failure(path, type_name, "multi-message aggregate decode failed");
    }

    LanternRoot root;
    if (lantern_hash_tree_root_multi_message_aggregate(&aggregate, &root) != SSZ_SUCCESS) {
        free(encoded);
        lantern_byte_list_reset(&aggregate);
        lantern_byte_list_reset(&decoded);
        return record_failure(path, type_name, "multi-message aggregate root failed");
    }
    free(encoded);
    lantern_byte_list_reset(&aggregate);
    lantern_byte_list_reset(&decoded);
    return expect_root_equal(path, type_name, "hash_tree_root", expected_root, &root);
}

static int run_type_two_multi_signature_fixture(
    const char *path,
    const char *type_name,
    const struct lantern_fixture_document *doc,
    int value_idx,
    const struct byte_buffer *expected_serialized,
    const LanternRoot *expected_root) {
    int proof_idx = lantern_fixture_object_get_field(doc, value_idx, "proof");
    struct byte_buffer proof = {0};
    if (proof_idx < 0 || parse_hex_data_object(doc, proof_idx, &proof) != 0) {
        byte_buffer_reset(&proof);
        return record_failure(path, type_name, "invalid type-two proof fixture");
    }
    if (proof.len > BYTELIST_512KIB_LIMIT) {
        byte_buffer_reset(&proof);
        return record_failure(path, type_name, "type-two proof exceeds limit");
    }

    size_t encoded_len = sizeof(uint32_t) + proof.len;
    uint8_t *encoded = (uint8_t *)malloc(encoded_len > 0u ? encoded_len : 1u);
    if (!encoded) {
        byte_buffer_reset(&proof);
        return record_failure(path, type_name, "type-two encode allocation failed");
    }
    write_u32_le((uint32_t)sizeof(uint32_t), encoded);
    if (proof.len > 0u) {
        memcpy(encoded + sizeof(uint32_t), proof.data, proof.len);
    }
    if (expect_bytes_equal(
            path,
            type_name,
            "encode(value)",
            expected_serialized->data,
            expected_serialized->len,
            encoded,
            encoded_len)
        != 0) {
        free(encoded);
        byte_buffer_reset(&proof);
        return record_failure(path, type_name, "type-two encode failed");
    }

    if (expected_serialized->len < sizeof(uint32_t)
        || read_u32_le_local(expected_serialized->data) != sizeof(uint32_t)
        || expected_serialized->len - sizeof(uint32_t) != proof.len
        || (proof.len > 0u
            && memcmp(expected_serialized->data + sizeof(uint32_t), proof.data, proof.len) != 0)) {
        free(encoded);
        byte_buffer_reset(&proof);
        return record_failure(path, type_name, "type-two decode failed");
    }

    LanternRoot root;
    if (merkleize_bytes_with_optional_length(
            expected_serialized->data + sizeof(uint32_t),
            expected_serialized->len - sizeof(uint32_t),
            BYTELIST_512KIB_LIMIT / SSZ_BYTES_PER_CHUNK,
            true,
            proof.len,
            &root)
        != 0) {
        free(encoded);
        byte_buffer_reset(&proof);
        return record_failure(path, type_name, "type-two root failed");
    }

    free(encoded);
    byte_buffer_reset(&proof);
    return expect_root_equal(path, type_name, "hash_tree_root", expected_root, &root);
}

static int run_signed_aggregated_attestation_fixture(
    const char *path,
    const char *type_name,
    const struct lantern_fixture_document *doc,
    int value_idx,
    const struct byte_buffer *expected_serialized,
    const LanternRoot *expected_root) {
    LanternSignedAggregatedAttestation attestation;
    size_t encoded_capacity = expected_serialized->len > 0u ? expected_serialized->len : 1u;
    uint8_t *encoded = (uint8_t *)malloc(encoded_capacity);
    size_t encoded_len = 0u;
    lantern_signed_aggregated_attestation_init(&attestation);
    if (!encoded
        || parse_signed_aggregated_attestation_object(doc, value_idx, &attestation) != 0
        || lantern_ssz_encode_signed_aggregated_attestation(&attestation, encoded, encoded_capacity, &encoded_len) != SSZ_SUCCESS
        || expect_bytes_equal(path, type_name, "encode(value)", expected_serialized->data, expected_serialized->len, encoded, encoded_len) != 0) {
        free(encoded);
        lantern_signed_aggregated_attestation_reset(&attestation);
        return record_failure(path, type_name, "signed-aggregated-attestation encode failed");
    }
    LanternSignedAggregatedAttestation decoded;
    lantern_signed_aggregated_attestation_init(&decoded);
    if (lantern_ssz_decode_signed_aggregated_attestation(&decoded, expected_serialized->data, expected_serialized->len) != SSZ_SUCCESS
        || lantern_ssz_encode_signed_aggregated_attestation(&decoded, encoded, encoded_capacity, &encoded_len) != SSZ_SUCCESS
        || expect_bytes_equal(path, type_name, "decode(serialized)", expected_serialized->data, expected_serialized->len, encoded, encoded_len) != 0) {
        free(encoded);
        lantern_signed_aggregated_attestation_reset(&attestation);
        lantern_signed_aggregated_attestation_reset(&decoded);
        return record_failure(path, type_name, "signed-aggregated-attestation decode failed");
    }
    LanternRoot root;
    if (lantern_hash_tree_root_signed_aggregated_attestation(&attestation, &root) != SSZ_SUCCESS) {
        free(encoded);
        lantern_signed_aggregated_attestation_reset(&attestation);
        lantern_signed_aggregated_attestation_reset(&decoded);
        return record_failure(path, type_name, "signed-aggregated-attestation root failed");
    }
    free(encoded);
    lantern_signed_aggregated_attestation_reset(&attestation);
    lantern_signed_aggregated_attestation_reset(&decoded);
    return expect_root_equal(path, type_name, "hash_tree_root", expected_root, &root);
}

static int run_block_body_fixture(
    const char *path,
    const char *type_name,
    const struct lantern_fixture_document *doc,
    int value_idx,
    const struct byte_buffer *expected_serialized,
    const LanternRoot *expected_root) {
    LanternBlockBody body;
    size_t encoded_capacity = expected_serialized->len > 0u ? expected_serialized->len : 1u;
    uint8_t *encoded = (uint8_t *)malloc(encoded_capacity);
    size_t encoded_len = 0u;
    if (!encoded || parse_block_body_object(doc, value_idx, &body) != 0) {
        free(encoded);
        return record_failure(path, type_name, "invalid block-body fixture");
    }
    if (lantern_ssz_encode_block_body(&body, encoded, encoded_capacity, &encoded_len) != SSZ_SUCCESS
        || expect_bytes_equal(path, type_name, "encode(value)", expected_serialized->data, expected_serialized->len, encoded, encoded_len) != 0) {
        free(encoded);
        lantern_block_body_reset(&body);
        return record_failure(path, type_name, "block-body encode failed");
    }
    LanternBlockBody decoded;
    lantern_block_body_init(&decoded);
    if (lantern_ssz_decode_block_body(&decoded, expected_serialized->data, expected_serialized->len) != SSZ_SUCCESS
        || lantern_ssz_encode_block_body(&decoded, encoded, encoded_capacity, &encoded_len) != SSZ_SUCCESS
        || expect_bytes_equal(path, type_name, "decode(serialized)", expected_serialized->data, expected_serialized->len, encoded, encoded_len) != 0) {
        free(encoded);
        lantern_block_body_reset(&body);
        lantern_block_body_reset(&decoded);
        return record_failure(path, type_name, "block-body decode failed");
    }
    LanternRoot root;
    if (lantern_hash_tree_root_block_body(&body, &root) != SSZ_SUCCESS) {
        free(encoded);
        lantern_block_body_reset(&body);
        lantern_block_body_reset(&decoded);
        return record_failure(path, type_name, "block-body root failed");
    }
    free(encoded);
    lantern_block_body_reset(&body);
    lantern_block_body_reset(&decoded);
    return expect_root_equal(path, type_name, "hash_tree_root", expected_root, &root);
}

static int run_block_header_fixture(
    const char *path,
    const char *type_name,
    const struct lantern_fixture_document *doc,
    int value_idx,
    const struct byte_buffer *expected_serialized,
    const LanternRoot *expected_root) {
    LanternBlockHeader header = {0};
    int slot_idx = lantern_fixture_object_get_field(doc, value_idx, "slot");
    int proposer_idx = lantern_fixture_object_get_field(doc, value_idx, "proposerIndex");
    int parent_idx = lantern_fixture_object_get_field(doc, value_idx, "parentRoot");
    int state_idx = lantern_fixture_object_get_field(doc, value_idx, "stateRoot");
    int body_idx = lantern_fixture_object_get_field(doc, value_idx, "bodyRoot");
    if (slot_idx < 0 || proposer_idx < 0 || parent_idx < 0 || state_idx < 0 || body_idx < 0
        || lantern_fixture_token_to_uint64(doc, slot_idx, &header.slot) != 0
        || lantern_fixture_token_to_uint64(doc, proposer_idx, &header.proposer_index) != 0
        || lantern_fixture_token_to_root(doc, parent_idx, &header.parent_root) != 0
        || lantern_fixture_token_to_root(doc, state_idx, &header.state_root) != 0
        || lantern_fixture_token_to_root(doc, body_idx, &header.body_root) != 0) {
        return record_failure(path, type_name, "invalid block-header fixture");
    }
    uint8_t encoded[LANTERN_BLOCK_HEADER_SSZ_SIZE];
    size_t encoded_len = sizeof(encoded);
    if (lantern_ssz_encode_block_header(&header, encoded, sizeof(encoded), &encoded_len) != SSZ_SUCCESS
        || expect_bytes_equal(path, type_name, "encode(value)", expected_serialized->data, expected_serialized->len, encoded, encoded_len) != 0) {
        return record_failure(path, type_name, "block-header encode failed");
    }
    LanternBlockHeader decoded;
    if (lantern_ssz_decode_block_header(&decoded, expected_serialized->data, expected_serialized->len) != SSZ_SUCCESS
        || lantern_ssz_encode_block_header(&decoded, encoded, sizeof(encoded), &encoded_len) != SSZ_SUCCESS
        || expect_bytes_equal(path, type_name, "decode(serialized)", expected_serialized->data, expected_serialized->len, encoded, encoded_len) != 0) {
        return record_failure(path, type_name, "block-header decode failed");
    }
    LanternRoot root;
    if (lantern_hash_tree_root_block_header(&header, &root) != SSZ_SUCCESS) {
        return record_failure(path, type_name, "block-header root failed");
    }
    return expect_root_equal(path, type_name, "hash_tree_root", expected_root, &root);
}

static int run_validator_fixture(
    const char *path,
    const char *type_name,
    const struct lantern_fixture_document *doc,
    int value_idx,
    const struct byte_buffer *expected_serialized,
    const LanternRoot *expected_root) {
    LanternValidator validator;
    if (parse_validator_object(doc, value_idx, &validator) != 0) {
        return record_failure(path, type_name, "invalid validator fixture");
    }
    uint8_t encoded[LANTERN_VALIDATOR_SSZ_SIZE];
    size_t encoded_len = sizeof(encoded);
    if (lantern_ssz_encode_validator(&validator, encoded, sizeof(encoded), &encoded_len) != SSZ_SUCCESS
        || expect_bytes_equal(path, type_name, "encode(value)", expected_serialized->data, expected_serialized->len, encoded, encoded_len) != 0) {
        return record_failure(path, type_name, "validator encode failed");
    }
    LanternValidator decoded;
    if (lantern_ssz_decode_validator(&decoded, expected_serialized->data, expected_serialized->len) != SSZ_SUCCESS
        || lantern_ssz_encode_validator(&decoded, encoded, sizeof(encoded), &encoded_len) != SSZ_SUCCESS
        || expect_bytes_equal(path, type_name, "decode(serialized)", expected_serialized->data, expected_serialized->len, encoded, encoded_len) != 0) {
        return record_failure(path, type_name, "validator decode failed");
    }
    LanternRoot root;
    if (lantern_hash_tree_root_validator(&validator, &root) != SSZ_SUCCESS) {
        return record_failure(path, type_name, "validator root failed");
    }
    return expect_root_equal(path, type_name, "hash_tree_root", expected_root, &root);
}

static int run_block_fixture(
    const char *path,
    const char *type_name,
    const struct lantern_fixture_document *doc,
    int value_idx,
    const struct byte_buffer *expected_serialized,
    const LanternRoot *expected_root) {
    LanternBlock block;
    memset(&block, 0, sizeof(block));
    if (lantern_fixture_parse_block(doc, value_idx, &block) != 0) {
        reset_block(&block);
        return record_failure(path, type_name, "invalid block fixture");
    }
    size_t encoded_capacity = expected_serialized->len > 0u ? expected_serialized->len : 1u;
    uint8_t *encoded = (uint8_t *)malloc(encoded_capacity);
    size_t encoded_len = 0u;
    if (!encoded
        || lantern_ssz_encode_block(&block, encoded, encoded_capacity, &encoded_len) != SSZ_SUCCESS
        || expect_bytes_equal(path, type_name, "encode(value)", expected_serialized->data, expected_serialized->len, encoded, encoded_len) != 0) {
        free(encoded);
        reset_block(&block);
        return record_failure(path, type_name, "block encode failed");
    }
    LanternBlock decoded;
    memset(&decoded, 0, sizeof(decoded));
    if (lantern_ssz_decode_block(&decoded, expected_serialized->data, expected_serialized->len) != SSZ_SUCCESS
        || lantern_ssz_encode_block(&decoded, encoded, encoded_capacity, &encoded_len) != SSZ_SUCCESS
        || expect_bytes_equal(path, type_name, "decode(serialized)", expected_serialized->data, expected_serialized->len, encoded, encoded_len) != 0) {
        free(encoded);
        reset_block(&block);
        reset_block(&decoded);
        return record_failure(path, type_name, "block decode failed");
    }
    LanternRoot root;
    if (lantern_hash_tree_root_block(&block, &root) != SSZ_SUCCESS) {
        free(encoded);
        reset_block(&block);
        reset_block(&decoded);
        return record_failure(path, type_name, "block root failed");
    }
    free(encoded);
    reset_block(&block);
    reset_block(&decoded);
    return expect_root_equal(path, type_name, "hash_tree_root", expected_root, &root);
}

static int run_signed_block_fixture(
    const char *path,
    const char *type_name,
    const struct lantern_fixture_document *doc,
    int value_idx,
    const struct byte_buffer *expected_serialized,
    const LanternRoot *expected_root) {
    LanternSignedBlock block;
    lantern_signed_block_init(&block);
    if (lantern_fixture_parse_signed_block(doc, value_idx, &block) != 0) {
        lantern_signed_block_reset(&block);
        return record_failure(path, type_name, "invalid signed-block fixture");
    }
    size_t encoded_capacity = expected_serialized->len > 0u ? expected_serialized->len : 1u;
    uint8_t *encoded = (uint8_t *)malloc(encoded_capacity);
    size_t encoded_len = 0u;
    if (!encoded
        || lantern_ssz_encode_signed_block(&block, encoded, encoded_capacity, &encoded_len) != SSZ_SUCCESS
        || expect_bytes_equal(path, type_name, "encode(value)", expected_serialized->data, expected_serialized->len, encoded, encoded_len) != 0) {
        free(encoded);
        lantern_signed_block_reset(&block);
        return record_failure(path, type_name, "signed-block encode failed");
    }
    LanternSignedBlock decoded;
    lantern_signed_block_init(&decoded);
    if (lantern_ssz_decode_signed_block(&decoded, expected_serialized->data, expected_serialized->len) != SSZ_SUCCESS
        || lantern_ssz_encode_signed_block(&decoded, encoded, encoded_capacity, &encoded_len) != SSZ_SUCCESS
        || expect_bytes_equal(path, type_name, "decode(serialized)", expected_serialized->data, expected_serialized->len, encoded, encoded_len) != 0) {
        free(encoded);
        lantern_signed_block_reset(&block);
        lantern_signed_block_reset(&decoded);
        return record_failure(path, type_name, "signed-block decode failed");
    }
    LanternRoot root;
    if (lantern_hash_tree_root_signed_block(&block, &root) != SSZ_SUCCESS) {
        free(encoded);
        lantern_signed_block_reset(&block);
        lantern_signed_block_reset(&decoded);
        return record_failure(path, type_name, "signed-block root failed");
    }
    free(encoded);
    lantern_signed_block_reset(&block);
    lantern_signed_block_reset(&decoded);
    return expect_root_equal(path, type_name, "hash_tree_root", expected_root, &root);
}

static int run_state_fixture(
    const char *path,
    const char *type_name,
    const struct lantern_fixture_document *doc,
    int value_idx,
    const struct byte_buffer *expected_serialized,
    const LanternRoot *expected_root) {
    LanternState state;
    LanternCheckpoint latest_justified = {0};
    LanternCheckpoint latest_finalized = {0};
    uint64_t genesis_time = 0u;
    uint64_t validator_count = 0u;
    lantern_state_init(&state);
    if (lantern_fixture_parse_anchor_state(
            doc,
            value_idx,
            &state,
            &latest_justified,
            &latest_finalized,
            &genesis_time,
            &validator_count)
        != 0) {
        lantern_state_reset(&state);
        return record_failure(path, type_name, "invalid state fixture");
    }
    size_t encoded_capacity = expected_serialized->len > 0u ? expected_serialized->len : 1u;
    uint8_t *encoded = (uint8_t *)malloc(encoded_capacity);
    size_t encoded_len = 0u;
    if (!encoded
        || lantern_ssz_encode_state(&state, encoded, encoded_capacity, &encoded_len) != SSZ_SUCCESS
        || expect_bytes_equal(path, type_name, "encode(value)", expected_serialized->data, expected_serialized->len, encoded, encoded_len) != 0) {
        free(encoded);
        lantern_state_reset(&state);
        return record_failure(path, type_name, "state encode failed");
    }
    LanternState decoded;
    lantern_state_init(&decoded);
    if (lantern_ssz_decode_state(&decoded, expected_serialized->data, expected_serialized->len) != SSZ_SUCCESS
        || lantern_ssz_encode_state(&decoded, encoded, encoded_capacity, &encoded_len) != SSZ_SUCCESS
        || expect_bytes_equal(path, type_name, "decode(serialized)", expected_serialized->data, expected_serialized->len, encoded, encoded_len) != 0) {
        free(encoded);
        lantern_state_reset(&state);
        lantern_state_reset(&decoded);
        return record_failure(path, type_name, "state decode failed");
    }
    LanternRoot root;
    if (lantern_hash_tree_root_state(&state, &root) != SSZ_SUCCESS) {
        free(encoded);
        lantern_state_reset(&state);
        lantern_state_reset(&decoded);
        return record_failure(path, type_name, "state root failed");
    }
    free(encoded);
    lantern_state_reset(&state);
    lantern_state_reset(&decoded);
    return expect_root_equal(path, type_name, "hash_tree_root", expected_root, &root);
}

static int run_status_fixture(
    const char *path,
    const char *type_name,
    const struct lantern_fixture_document *doc,
    int value_idx,
    const struct byte_buffer *expected_serialized,
    const LanternRoot *expected_root) {
    LanternStatusMessage status = {0};
    uint8_t encoded[2u * LANTERN_CHECKPOINT_SSZ_SIZE];
    size_t encoded_len = 0u;
    if (parse_status_object(doc, value_idx, &status) != 0
        || lantern_network_status_encode(&status, encoded, sizeof(encoded), &encoded_len) != 0
        || expect_bytes_equal(path, type_name, "encode(value)", expected_serialized->data, expected_serialized->len, encoded, encoded_len) != 0) {
        return record_failure(path, type_name, "status encode failed");
    }
    LanternStatusMessage decoded = {0};
    if (lantern_network_status_decode(&decoded, expected_serialized->data, expected_serialized->len) != 0
        || lantern_network_status_encode(&decoded, encoded, sizeof(encoded), &encoded_len) != 0
        || expect_bytes_equal(path, type_name, "decode(serialized)", expected_serialized->data, expected_serialized->len, encoded, encoded_len) != 0) {
        return record_failure(path, type_name, "status decode failed");
    }
    LanternRoot root;
    if (compute_status_root(&status, &root) != 0) {
        return record_failure(path, type_name, "status root failed");
    }
    return expect_root_equal(path, type_name, "hash_tree_root", expected_root, &root);
}

static int run_blocks_by_root_request_fixture(
    const char *path,
    const char *type_name,
    const struct lantern_fixture_document *doc,
    int value_idx,
    const struct byte_buffer *expected_serialized,
    const LanternRoot *expected_root) {
    LanternBlocksByRootRequest request;
    lantern_blocks_by_root_request_init(&request);
    int roots_idx = lantern_fixture_object_get_field(doc, value_idx, "roots");
    if (roots_idx < 0 || parse_root_list_object(doc, roots_idx, &request.roots) != 0) {
        lantern_blocks_by_root_request_reset(&request);
        return record_failure(path, type_name, "invalid blocks-by-root-request fixture");
    }
    size_t encoded_capacity = expected_serialized->len > 0u ? expected_serialized->len : 1u;
    uint8_t *encoded = (uint8_t *)malloc(encoded_capacity);
    size_t encoded_len = 0u;
    if (!encoded
        || lantern_network_blocks_by_root_request_encode(&request, encoded, encoded_capacity, &encoded_len) != 0
        || expect_bytes_equal(path, type_name, "encode(value)", expected_serialized->data, expected_serialized->len, encoded, encoded_len) != 0) {
        free(encoded);
        lantern_blocks_by_root_request_reset(&request);
        return record_failure(path, type_name, "blocks-by-root-request encode failed");
    }
    LanternBlocksByRootRequest decoded;
    lantern_blocks_by_root_request_init(&decoded);
    if (lantern_network_blocks_by_root_request_decode(&decoded, expected_serialized->data, expected_serialized->len) != 0
        || lantern_network_blocks_by_root_request_encode(&decoded, encoded, encoded_capacity, &encoded_len) != 0
        || expect_bytes_equal(path, type_name, "decode(serialized)", expected_serialized->data, expected_serialized->len, encoded, encoded_len) != 0) {
        free(encoded);
        lantern_blocks_by_root_request_reset(&request);
        lantern_blocks_by_root_request_reset(&decoded);
        return record_failure(path, type_name, "blocks-by-root-request decode failed");
    }
    LanternRoot root;
    if (compute_blocks_by_root_request_root(&request, &root) != 0) {
        free(encoded);
        lantern_blocks_by_root_request_reset(&request);
        lantern_blocks_by_root_request_reset(&decoded);
        return record_failure(path, type_name, "blocks-by-root-request root failed");
    }
    free(encoded);
    lantern_blocks_by_root_request_reset(&request);
    lantern_blocks_by_root_request_reset(&decoded);
    return expect_root_equal(path, type_name, "hash_tree_root", expected_root, &root);
}

static int run_decode_rejection_fixture(
    const char *path,
    const char *type_name,
    const struct lantern_fixture_document *doc,
    int case_idx) {
    int raw_idx = lantern_fixture_object_get_field(doc, case_idx, "rawBytes");
    int serialized_idx = lantern_fixture_object_get_field(doc, case_idx, "serialized");
    struct byte_buffer bytes = {0};
    ssz_error_t decode_status = SSZ_ERR_INVALID_ARGUMENT;

    if ((raw_idx < 0 && serialized_idx < 0)
        || fixture_token_to_bytes(doc, raw_idx >= 0 ? raw_idx : serialized_idx, &bytes) != 0) {
        return record_failure(path, type_name, "invalid decode-rejection fixture");
    }

    if (strcmp(type_name, "Uint32") == 0) {
        uint32_t decoded = 0u;
        decode_status = ssz_deserialize_uint32(bytes.data, bytes.len, &decoded);
    } else if (strcmp(type_name, "Bytes4") == 0) {
        uint8_t decoded[4];
        decode_status = ssz_deserialize_vector_fixed(
            bytes.data,
            bytes.len,
            sizeof(decoded),
            sizeof(uint8_t),
            decoded,
            sizeof(decoded));
    } else {
        size_t bit_count = 0u;
        if (parse_size_suffix(type_name, "DecodeBitvector", &bit_count) == 0
            || parse_size_suffix(type_name, "BoundaryBitvector", &bit_count) == 0) {
            size_t decoded_len = (bit_count + 7u) / 8u;
            uint8_t *decoded = (uint8_t *)calloc(decoded_len > 0u ? decoded_len : 1u, sizeof(*decoded));
            if (!decoded) {
                byte_buffer_reset(&bytes);
                return record_failure(path, type_name, "allocation failed");
            }
            decode_status = ssz_deserialize_bitvector(bytes.data, bytes.len, bit_count, decoded, decoded_len);
            free(decoded);
        } else if (parse_size_suffix(type_name, "DecodeBitlist", &bit_count) == 0
            || parse_size_suffix(type_name, "SmokeBitlist", &bit_count) == 0
            || parse_size_suffix(type_name, "BoundaryBitlist", &bit_count) == 0) {
            size_t decoded_len = (bit_count + 7u) / 8u;
            uint8_t *decoded = (uint8_t *)calloc(decoded_len > 0u ? decoded_len : 1u, sizeof(*decoded));
            uint64_t actual_bits = 0u;
            if (!decoded) {
                byte_buffer_reset(&bytes);
                return record_failure(path, type_name, "allocation failed");
            }
            decode_status = ssz_deserialize_bitlist(
                bytes.data,
                bytes.len,
                bit_count,
                decoded,
                decoded_len,
                &actual_bits);
            free(decoded);
        } else {
            byte_buffer_reset(&bytes);
            return record_failure(path, type_name, "decode-rejection type not supported by runner");
        }
    }

    byte_buffer_reset(&bytes);
    if (decode_status == SSZ_SUCCESS) {
        return record_failure(path, type_name, "decode unexpectedly succeeded");
    }
    return 0;
}

static int run_fixture_case(
    const char *path,
    const char *type_name,
    const struct lantern_fixture_document *doc,
    int value_idx,
    const struct byte_buffer *expected_serialized,
    const LanternRoot *expected_root,
    struct fixture_stats *stats) {
    if (strcmp(type_name, "Boolean") == 0) {
        return run_boolean_fixture(path, type_name, doc, value_idx, expected_serialized, expected_root);
    }
    if (strcmp(type_name, "Uint8") == 0) {
        return run_uint_fixture(path, type_name, doc, value_idx, 8u, expected_serialized, expected_root);
    }
    if (strcmp(type_name, "Uint16") == 0) {
        return run_uint_fixture(path, type_name, doc, value_idx, 16u, expected_serialized, expected_root);
    }
    if (strcmp(type_name, "Uint32") == 0) {
        return run_uint_fixture(path, type_name, doc, value_idx, 32u, expected_serialized, expected_root);
    }
    if (strcmp(type_name, "Fp") == 0) {
        return run_fp_fixture(path, type_name, doc, value_idx, expected_serialized, expected_root);
    }
    if (strcmp(type_name, "Uint64") == 0) {
        return run_uint_fixture(path, type_name, doc, value_idx, 64u, expected_serialized, expected_root);
    }
    if (strcmp(type_name, "Bytes4") == 0) {
        return run_fixed_bytes_fixture(path, type_name, doc, value_idx, 4u, expected_serialized, expected_root);
    }
    if (strcmp(type_name, "Bytes32") == 0) {
        return run_fixed_bytes_fixture(path, type_name, doc, value_idx, 32u, expected_serialized, expected_root);
    }
    if (strcmp(type_name, "Bytes52") == 0) {
        return run_fixed_bytes_fixture(path, type_name, doc, value_idx, 52u, expected_serialized, expected_root);
    }
    if (strcmp(type_name, "Bytes64") == 0) {
        return run_fixed_bytes_fixture(path, type_name, doc, value_idx, 64u, expected_serialized, expected_root);
    }
    if (strcmp(type_name, "ByteListMiB") == 0) {
        return run_byte_list_fixture(
            path,
            type_name,
            doc,
            value_idx,
            BYTELIST_MIB_LIMIT,
            expected_serialized,
            expected_root);
    }
    if (strcmp(type_name, "ByteList512KiB") == 0) {
        return run_byte_list_fixture(
            path,
            type_name,
            doc,
            value_idx,
            BYTELIST_512KIB_LIMIT,
            expected_serialized,
            expected_root);
    }
    if (strcmp(type_name, "SampleBitvector8") == 0) {
        return run_bool_vector_fixture(path, type_name, doc, value_idx, 8u, expected_serialized, expected_root);
    }
    if (strcmp(type_name, "SampleBitvector64") == 0) {
        return run_bool_vector_fixture(path, type_name, doc, value_idx, 64u, expected_serialized, expected_root);
    }
    if (strcmp(type_name, "AttestationSubnets") == 0) {
        return run_bool_vector_fixture(path, type_name, doc, value_idx, 64u, expected_serialized, expected_root);
    }
    if (strcmp(type_name, "SyncCommitteeSubnets") == 0) {
        return run_bool_vector_fixture(path, type_name, doc, value_idx, 4u, expected_serialized, expected_root);
    }
    size_t boundary_count = 0u;
    if (parse_size_suffix(type_name, "BoundaryBitvector", &boundary_count) == 0) {
        return run_bool_vector_fixture(path, type_name, doc, value_idx, boundary_count, expected_serialized, expected_root);
    }
    if (strcmp(type_name, "SampleBitlist16") == 0) {
        return run_bitlist_fixture(path, type_name, doc, value_idx, SAMPLE_BITLIST_LIMIT_BITS, expected_serialized, expected_root);
    }
    if (parse_size_suffix(type_name, "BoundaryBitlist", &boundary_count) == 0) {
        return run_bitlist_fixture(path, type_name, doc, value_idx, boundary_count, expected_serialized, expected_root);
    }
    if (strcmp(type_name, "SampleUint16Vector3") == 0) {
        return run_uint_vector_fixture(path, type_name, doc, value_idx, 16u, 3u, expected_serialized, expected_root);
    }
    if (strcmp(type_name, "SampleUint64Vector4") == 0) {
        return run_uint_vector_fixture(path, type_name, doc, value_idx, 64u, 4u, expected_serialized, expected_root);
    }
    if (strcmp(type_name, "SampleUint32List16") == 0) {
        return run_uint32_list_fixture(path, type_name, doc, value_idx, expected_serialized, expected_root);
    }
    if (parse_size_suffix(type_name, "BoundaryUint64List", &boundary_count) == 0) {
        return run_uint64_list_fixture(path, type_name, doc, value_idx, boundary_count, expected_serialized, expected_root);
    }
    if (strcmp(type_name, "SampleBytes32List8") == 0) {
        return run_bytes32_list_fixture(path, type_name, doc, value_idx, expected_serialized, expected_root);
    }
    if (strcmp(type_name, "SampleUnionNone") == 0) {
        return run_union_fixture(path, type_name, doc, value_idx, true, expected_serialized, expected_root);
    }
    if (strcmp(type_name, "SampleUnionTypes") == 0) {
        return run_union_fixture(path, type_name, doc, value_idx, false, expected_serialized, expected_root);
    }
    if (strcmp(type_name, "PublicKey") == 0) {
        return run_public_key_fixture(path, type_name, doc, value_idx, expected_serialized, expected_root);
    }
    if (strcmp(type_name, "Signature") == 0) {
        return run_signature_fixture(path, type_name, doc, value_idx, expected_serialized, expected_root);
    }
    if (strcmp(type_name, "HashTreeOpening") == 0) {
        return run_hash_tree_opening_fixture(path, type_name, doc, value_idx, expected_serialized, expected_root);
    }
    if (strcmp(type_name, "HashTreeLayer") == 0) {
        return run_hash_tree_layer_fixture(path, type_name, doc, value_idx, expected_serialized, expected_root);
    }
    if (strcmp(type_name, "Config") == 0) {
        return run_config_fixture(path, type_name, doc, value_idx, expected_serialized, expected_root);
    }
    if (strcmp(type_name, "Checkpoint") == 0) {
        return run_checkpoint_fixture(path, type_name, doc, value_idx, expected_serialized, expected_root);
    }
    if (strcmp(type_name, "AttestationData") == 0) {
        return run_attestation_data_fixture(path, type_name, doc, value_idx, expected_serialized, expected_root);
    }
    if (strcmp(type_name, "Attestation") == 0) {
        return run_attestation_fixture(path, type_name, doc, value_idx, expected_serialized, expected_root);
    }
    if (strcmp(type_name, "SignedAttestation") == 0) {
        return run_signed_attestation_fixture(path, type_name, doc, value_idx, expected_serialized, expected_root);
    }
    if (strcmp(type_name, "AggregatedAttestation") == 0) {
        return run_aggregated_attestation_fixture(path, type_name, doc, value_idx, expected_serialized, expected_root);
    }
    if (strcmp(type_name, "AggregatedSignatureProof") == 0) {
        return run_aggregated_signature_proof_fixture(path, type_name, doc, value_idx, expected_serialized, expected_root);
    }
    if (strcmp(type_name, "SingleMessageAggregate") == 0) {
        return run_aggregated_signature_proof_fixture(path, type_name, doc, value_idx, expected_serialized, expected_root);
    }
    if (strcmp(type_name, "MultiMessageAggregate") == 0) {
        return run_multi_message_aggregate_fixture(path, type_name, doc, value_idx, expected_serialized, expected_root);
    }
    if (strcmp(type_name, "TypeOneMultiSignature") == 0) {
        return run_aggregated_signature_proof_fixture(path, type_name, doc, value_idx, expected_serialized, expected_root);
    }
    if (strcmp(type_name, "TypeTwoMultiSignature") == 0) {
        return run_type_two_multi_signature_fixture(path, type_name, doc, value_idx, expected_serialized, expected_root);
    }
    if (strcmp(type_name, "SignedAggregatedAttestation") == 0) {
        return run_signed_aggregated_attestation_fixture(path, type_name, doc, value_idx, expected_serialized, expected_root);
    }
    if (strcmp(type_name, "BlockBody") == 0) {
        return run_block_body_fixture(path, type_name, doc, value_idx, expected_serialized, expected_root);
    }
    if (strcmp(type_name, "BlockHeader") == 0) {
        return run_block_header_fixture(path, type_name, doc, value_idx, expected_serialized, expected_root);
    }
    if (strcmp(type_name, "Validator") == 0) {
        return run_validator_fixture(path, type_name, doc, value_idx, expected_serialized, expected_root);
    }
    if (strcmp(type_name, "Block") == 0) {
        return run_block_fixture(path, type_name, doc, value_idx, expected_serialized, expected_root);
    }
    if (strcmp(type_name, "SignedBlock") == 0) {
        return run_signed_block_fixture(path, type_name, doc, value_idx, expected_serialized, expected_root);
    }
    if (strcmp(type_name, "State") == 0) {
        return run_state_fixture(path, type_name, doc, value_idx, expected_serialized, expected_root);
    }
    if (strcmp(type_name, "Status") == 0) {
        return run_status_fixture(path, type_name, doc, value_idx, expected_serialized, expected_root);
    }
    if (strcmp(type_name, "BlocksByRootRequest") == 0) {
        return run_blocks_by_root_request_fixture(path, type_name, doc, value_idx, expected_serialized, expected_root);
    }

    return run_unsupported_fixture(path, type_name, stats, "typeName not yet supported by SSZ runner");
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
    int type_idx = case_idx >= 0 ? lantern_fixture_object_get_field(&doc, case_idx, "typeName") : -1;
    int value_idx = case_idx >= 0 ? lantern_fixture_object_get_field(&doc, case_idx, "value") : -1;
    int serialized_idx = case_idx >= 0 ? lantern_fixture_object_get_field(&doc, case_idx, "serialized") : -1;
    int root_idx = case_idx >= 0 ? lantern_fixture_object_get_field(&doc, case_idx, "root") : -1;
    int expect_exception_idx = case_idx >= 0 ? lantern_fixture_object_get_field(&doc, case_idx, "expectException") : -1;
    char *type_name = NULL;
    struct byte_buffer expected_serialized = {0};
    LanternRoot expected_root;
    memset(&expected_root, 0, sizeof(expected_root));

    if (stats) {
        stats->total += 1u;
    }

    int rc = -1;
    if (type_idx < 0 || fixture_token_to_c_string(&doc, type_idx, &type_name) != 0) {
        rc = record_failure(path, NULL, "fixture missing typeName");
    } else if (expect_exception_idx >= 0) {
        rc = run_decode_rejection_fixture(path, type_name, &doc, case_idx);
    } else if (value_idx < 0 || serialized_idx < 0 || root_idx < 0
        || fixture_token_to_bytes(&doc, serialized_idx, &expected_serialized) != 0
        || lantern_fixture_token_to_root(&doc, root_idx, &expected_root) != 0) {
        rc = record_failure(path, NULL, "fixture missing typeName/value/serialized/root");
    } else {
        rc = run_fixture_case(path, type_name, &doc, value_idx, &expected_serialized, &expected_root, stats);
    }

    if (stats) {
        if (rc == 0) {
            stats->passed += 1u;
        } else {
            stats->failed += 1u;
        }
    }

    byte_buffer_reset(&expected_serialized);
    free(type_name);
    lantern_fixture_document_reset(&doc);
    return 0;
}

int main(void) {
    char fixture_root[PATH_MAX];
    if (build_fixture_root(fixture_root, sizeof(fixture_root)) != 0) {
        fprintf(stderr, "ssz fixture path too long\n");
        return 1;
    }

    struct fixture_stats stats = {0};
    if (for_each_json(fixture_root, run_fixture_file, &stats) != 0) {
        fprintf(stderr, "ssz fixture walk failed\n");
        return 1;
    }

    fprintf(
        stderr,
        "lantern_ssz_vectors: total=%zu passed=%zu failed=%zu unsupported=%zu\n",
        stats.total,
        stats.passed,
        stats.failed,
        stats.unsupported);
    fflush(stderr);
    return stats.failed == 0u ? 0 : 1;
}
