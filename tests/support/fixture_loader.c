#include "tests/support/fixture_loader.h"

#include <errno.h>
#include <limits.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "lantern/consensus/hash.h"
#include "lantern/support/strings.h"
#include "external/c-leanvm-xmss/include/pq-bindings-c-rust.h"
#include "state_store_adapter.h"

#define JSON_INITIAL_TOKENS 256
#define LANTERN_XMSS_FP_BYTES 4u
#define LANTERN_XMSS_HASH_LEN_FE 8u
#define LANTERN_XMSS_RAND_LEN_FE 7u
#define LANTERN_XMSS_HASH_DIGEST_BYTES (LANTERN_XMSS_HASH_LEN_FE * LANTERN_XMSS_FP_BYTES)
#define LANTERN_XMSS_RHO_BYTES (LANTERN_XMSS_RAND_LEN_FE * LANTERN_XMSS_FP_BYTES)
#define LANTERN_SSZ_U32_SIZE 4u
#define LANTERN_XMSS_SIGNATURE_FIXED_SECTION \
    (LANTERN_SSZ_U32_SIZE + LANTERN_XMSS_RHO_BYTES + LANTERN_SSZ_U32_SIZE)

static int lantern_fixture_token_to_signature(
    const struct lantern_fixture_document *doc,
    int index,
    LanternSignature *signature);

int lantern_fixture_read_text_file(const char *path, char **out_buf) {
    if (!path || !out_buf) {
        return -1;
    }
    FILE *file = fopen(path, "rb");
    if (!file) {
        perror("fopen");
        return -1;
    }
    if (fseek(file, 0, SEEK_END) != 0) {
        fclose(file);
        return -1;
    }
    long size = ftell(file);
    if (size < 0) {
        fclose(file);
        return -1;
    }
    if (fseek(file, 0, SEEK_SET) != 0) {
        fclose(file);
        return -1;
    }
    char *buffer = (char *)malloc((size_t)size + 1u);
    if (!buffer) {
        fclose(file);
        return -1;
    }
    size_t read_len = fread(buffer, 1u, (size_t)size, file);
    fclose(file);
    if (read_len != (size_t)size) {
        free(buffer);
        return -1;
    }
    buffer[size] = '\0';
    *out_buf = buffer;
    return 0;
}

void lantern_fixture_document_reset(struct lantern_fixture_document *doc) {
    if (!doc) {
        return;
    }
    free(doc->tokens);
    doc->tokens = NULL;
    doc->token_count = 0;
    doc->length = 0;
    free(doc->text);
    doc->text = NULL;
}

int lantern_fixture_document_init(struct lantern_fixture_document *doc, char *text) {
    if (!doc || !text) {
        free(text);
        return -1;
    }
    doc->text = text;
    doc->length = strlen(text);
    doc->tokens = NULL;
    doc->token_count = 0;

    int capacity = JSON_INITIAL_TOKENS;
    while (capacity <= 32768) {
        jsmntok_t *tokens = (jsmntok_t *)malloc((size_t)capacity * sizeof(jsmntok_t));
        if (!tokens) {
            lantern_fixture_document_reset(doc);
            return -1;
        }

        jsmn_parser parser;
        jsmn_init(&parser);
        int result = jsmn_parse(&parser, doc->text, doc->length, tokens, capacity);
        if (result >= 0) {
            doc->tokens = tokens;
            doc->token_count = result;
            return 0;
        }
        free(tokens);
        if (result == JSMN_ERROR_NOMEM) {
            capacity *= 2;
            continue;
        }
        lantern_fixture_document_reset(doc);
        return -1;
    }

    lantern_fixture_document_reset(doc);
    return -1;
}

const jsmntok_t *lantern_fixture_token(const struct lantern_fixture_document *doc, int index) {
    if (!doc || index < 0 || index >= doc->token_count) {
        return NULL;
    }
    return &doc->tokens[index];
}

static int lantern_fixture_skip_token(const struct lantern_fixture_document *doc, int index) {
    const jsmntok_t *tok = lantern_fixture_token(doc, index);
    if (!tok) {
        return -1;
    }
    index += 1;
    if (tok->type == JSMN_ARRAY) {
        for (int i = 0; i < tok->size; ++i) {
            index = lantern_fixture_skip_token(doc, index);
            if (index < 0) {
                return -1;
            }
        }
    } else if (tok->type == JSMN_OBJECT) {
        for (int i = 0; i < tok->size; ++i) {
            index = lantern_fixture_skip_token(doc, index);
            if (index < 0) {
                return -1;
            }
            index = lantern_fixture_skip_token(doc, index);
            if (index < 0) {
                return -1;
            }
        }
    }
    return index;
}

static bool lantern_fixture_token_equals(
    const struct lantern_fixture_document *doc,
    int index,
    const char *value) {
    const jsmntok_t *tok = lantern_fixture_token(doc, index);
    if (!tok || tok->type != JSMN_STRING || !value) {
        return false;
    }
    size_t len = strlen(value);
    size_t tok_len = (size_t)(tok->end - tok->start);
    if (tok_len != len) {
        return false;
    }
    return strncmp(doc->text + tok->start, value, len) == 0;
}

int lantern_fixture_object_get_field(
    const struct lantern_fixture_document *doc,
    int object_index,
    const char *field) {
    const jsmntok_t *obj = lantern_fixture_token(doc, object_index);
    if (!obj || obj->type != JSMN_OBJECT) {
        return -1;
    }
    int index = object_index + 1;
    for (int i = 0; i < obj->size; ++i) {
        int key_index = index;
        int value_index = lantern_fixture_skip_token(doc, key_index);
        if (value_index < 0) {
            return -1;
        }
        if (lantern_fixture_token_equals(doc, key_index, field)) {
            return value_index;
        }
        index = lantern_fixture_skip_token(doc, value_index);
        if (index < 0) {
            return -1;
        }
    }
    return -1;
}

int lantern_fixture_array_get_length(
    const struct lantern_fixture_document *doc,
    int array_index) {
    const jsmntok_t *arr = lantern_fixture_token(doc, array_index);
    if (!arr || arr->type != JSMN_ARRAY) {
        return -1;
    }
    return arr->size;
}

int lantern_fixture_array_get_element(
    const struct lantern_fixture_document *doc,
    int array_index,
    int position) {
    const jsmntok_t *arr = lantern_fixture_token(doc, array_index);
    if (!arr || arr->type != JSMN_ARRAY || position < 0 || position >= arr->size) {
        return -1;
    }
    int index = array_index + 1;
    for (int i = 0; i < arr->size; ++i) {
        if (i == position) {
            return index;
        }
        index = lantern_fixture_skip_token(doc, index);
        if (index < 0) {
            return -1;
        }
    }
    return -1;
}

int lantern_fixture_object_get_value_at(
    const struct lantern_fixture_document *doc,
    int object_index,
    int position) {
    const jsmntok_t *obj = lantern_fixture_token(doc, object_index);
    if (!obj || obj->type != JSMN_OBJECT || position < 0 || position >= obj->size) {
        return -1;
    }
    int index = object_index + 1;
    for (int i = 0; i < obj->size; ++i) {
        int key_index = index;
        index = lantern_fixture_skip_token(doc, key_index);
        if (index < 0) {
            return -1;
        }
        if (i == position) {
            return index;
        }
        index = lantern_fixture_skip_token(doc, index);
        if (index < 0) {
            return -1;
        }
    }
    return -1;
}

int lantern_fixture_token_to_uint64(
    const struct lantern_fixture_document *doc,
    int index,
    uint64_t *out_value) {
    if (!out_value) {
        return -1;
    }
    const jsmntok_t *tok = lantern_fixture_token(doc, index);
    if (!tok || (tok->type != JSMN_PRIMITIVE && tok->type != JSMN_STRING)) {
        return -1;
    }
    size_t len = (size_t)(tok->end - tok->start);
    char buffer[64];
    if (len >= sizeof(buffer)) {
        return -1;
    }
    memcpy(buffer, doc->text + tok->start, len);
    buffer[len] = '\0';
    char *endptr = NULL;
    errno = 0;
    unsigned long long value = strtoull(buffer, &endptr, 10);
    if (errno != 0 || endptr == buffer || *endptr != '\0') {
        return -1;
    }
    *out_value = (uint64_t)value;
    return 0;
}

static int lantern_fixture_token_to_bit(
    const struct lantern_fixture_document *doc,
    int index,
    bool *out_value) {
    if (!out_value) {
        return -1;
    }
    const jsmntok_t *tok = lantern_fixture_token(doc, index);
    if (!tok || (tok->type != JSMN_PRIMITIVE && tok->type != JSMN_STRING)) {
        return -1;
    }
    size_t len = (size_t)(tok->end - tok->start);
    if (len == 0) {
        return -1;
    }
    char buffer[16];
    if (len >= sizeof(buffer)) {
        return -1;
    }
    memcpy(buffer, doc->text + tok->start, len);
    buffer[len] = '\0';
    if (strcmp(buffer, "true") == 0) {
        *out_value = true;
        return 0;
    }
    if (strcmp(buffer, "false") == 0) {
        *out_value = false;
        return 0;
    }
    char *endptr = NULL;
    errno = 0;
    unsigned long long value = strtoull(buffer, &endptr, 10);
    if (errno != 0 || endptr == buffer || *endptr != '\0') {
        return -1;
    }
    if (value > 1u) {
        return -1;
    }
    *out_value = (value != 0u);
    return 0;
}

const char *lantern_fixture_token_string(
    const struct lantern_fixture_document *doc,
    int index,
    size_t *out_length) {
    if (out_length) {
        *out_length = 0;
    }
    const jsmntok_t *tok = lantern_fixture_token(doc, index);
    if (!tok || tok->type != JSMN_STRING) {
        return NULL;
    }
    if (out_length) {
        *out_length = (size_t)(tok->end - tok->start);
    }
    return doc->text + tok->start;
}

static int lantern_fixture_parse_hex_bytes(
    const char *hex,
    size_t len,
    uint8_t *out,
    size_t out_len) {
    if (!hex || !out) {
        return -1;
    }
    if (len < 2 || hex[0] != '0' || (hex[1] != 'x' && hex[1] != 'X')) {
        return -1;
    }
    hex += 2;
    len -= 2;
    if (len != out_len * 2) {
        return -1;
    }
    for (size_t i = 0; i < out_len; ++i) {
        char buf[3];
        buf[0] = hex[i * 2];
        buf[1] = hex[(i * 2) + 1];
        buf[2] = '\0';
        char *endptr = NULL;
        errno = 0;
        unsigned long value = strtoul(buf, &endptr, 16);
        if (errno != 0 || !endptr || *endptr != '\0') {
            return -1;
        }
        out[i] = (uint8_t)value;
    }
    return 0;
}

int lantern_fixture_token_to_root(
    const struct lantern_fixture_document *doc,
    int index,
    LanternRoot *root) {
    if (!root) {
        return -1;
    }
    size_t len = 0;
    const char *str = lantern_fixture_token_string(doc, index, &len);
    if (!str) {
        return -1;
    }
    return lantern_fixture_parse_hex_bytes(str, len, root->bytes, sizeof(root->bytes));
}

static int lantern_fixture_parse_root_array_field(
    const struct lantern_fixture_document *doc,
    int parent_idx,
    const char *field_name,
    struct lantern_root_list *list) {
    if (!doc || !list) {
        return -1;
    }
    int container_idx = lantern_fixture_object_get_field(doc, parent_idx, field_name);
    if (container_idx < 0) {
        return lantern_root_list_resize(list, 0);
    }
    int data_idx = lantern_fixture_object_get_field(doc, container_idx, "data");
    if (data_idx < 0) {
        return lantern_root_list_resize(list, 0);
    }
    int length = lantern_fixture_array_get_length(doc, data_idx);
    if (length < 0) {
        return -1;
    }
    if (lantern_root_list_resize(list, (size_t)length) != 0) {
        return -1;
    }
    for (int i = 0; i < length; ++i) {
        int entry_idx = lantern_fixture_array_get_element(doc, data_idx, i);
        if (entry_idx < 0) {
            return -1;
        }
        if (lantern_fixture_token_to_root(doc, entry_idx, &list->items[i]) != 0) {
            return -1;
        }
    }
    return 0;
}

static int lantern_fixture_parse_bitlist_field(
    const struct lantern_fixture_document *doc,
    int parent_idx,
    const char *field_name,
    struct lantern_bitlist *list) {
    if (!doc || !list) {
        return -1;
    }
    int container_idx = lantern_fixture_object_get_field(doc, parent_idx, field_name);
    if (container_idx < 0) {
        return lantern_bitlist_resize(list, 0);
    }
    int data_idx = lantern_fixture_object_get_field(doc, container_idx, "data");
    if (data_idx < 0) {
        return lantern_bitlist_resize(list, 0);
    }
    int length = lantern_fixture_array_get_length(doc, data_idx);
    if (length < 0) {
        return -1;
    }
    if (lantern_bitlist_resize(list, (size_t)length) != 0) {
        return -1;
    }
    if (length == 0) {
        return 0;
    }
    if (!list->bytes) {
        return -1;
    }
    size_t required_bytes = (size_t)((length + 7) / 8);
    memset(list->bytes, 0, required_bytes);
    for (int i = 0; i < length; ++i) {
        int bit_idx = lantern_fixture_array_get_element(doc, data_idx, i);
        if (bit_idx < 0) {
            return -1;
        }
        bool bit_value = false;
        if (lantern_fixture_token_to_bit(doc, bit_idx, &bit_value) != 0) {
            return -1;
        }
        if (!bit_value) {
            continue;
        }
        size_t byte_index = (size_t)i / 8u;
        size_t bit_offset = (size_t)i % 8u;
        if (byte_index >= required_bytes) {
            return -1;
        }
        list->bytes[byte_index] |= (uint8_t)(1u << bit_offset);
    }
    return 0;
}

static int lantern_fixture_parse_bitlist_object(
    const struct lantern_fixture_document *doc,
    int container_idx,
    struct lantern_bitlist *list) {
    if (!doc || !list) {
        return -1;
    }
    if (container_idx < 0) {
        return lantern_bitlist_resize(list, 0);
    }
    int data_idx = lantern_fixture_object_get_field(doc, container_idx, "data");
    if (data_idx < 0) {
        return lantern_bitlist_resize(list, 0);
    }
    int length = lantern_fixture_array_get_length(doc, data_idx);
    if (length < 0) {
        return -1;
    }
    if (lantern_bitlist_resize(list, (size_t)length) != 0) {
        return -1;
    }
    if (length == 0) {
        return 0;
    }
    if (!list->bytes) {
        return -1;
    }
    size_t required_bytes = (size_t)((length + 7) / 8);
    memset(list->bytes, 0, required_bytes);
    for (int i = 0; i < length; ++i) {
        int bit_idx = lantern_fixture_array_get_element(doc, data_idx, i);
        if (bit_idx < 0) {
            return -1;
        }
        bool bit_value = false;
        if (lantern_fixture_token_to_bit(doc, bit_idx, &bit_value) != 0) {
            return -1;
        }
        if (!bit_value) {
            continue;
        }
        size_t byte_index = (size_t)i / 8u;
        size_t bit_offset = (size_t)i % 8u;
        if (byte_index >= required_bytes) {
            return -1;
        }
        list->bytes[byte_index] |= (uint8_t)(1u << bit_offset);
    }
    return 0;
}

static int lantern_fixture_parse_attestation_data(
    const struct lantern_fixture_document *doc,
    int data_obj_idx,
    LanternAttestationData *out_data) {
    if (!doc || !out_data || data_obj_idx < 0) {
        return -1;
    }
    memset(out_data, 0, sizeof(*out_data));

    int field_idx = lantern_fixture_object_get_field(doc, data_obj_idx, "slot");
    if (lantern_fixture_token_to_uint64(doc, field_idx, &out_data->slot) != 0) {
        return -1;
    }

    field_idx = lantern_fixture_object_get_field(doc, data_obj_idx, "head");
    if (field_idx < 0) {
        return -1;
    }
    int root_idx = lantern_fixture_object_get_field(doc, field_idx, "root");
    if (lantern_fixture_token_to_root(doc, root_idx, &out_data->head.root) != 0) {
        return -1;
    }
    root_idx = lantern_fixture_object_get_field(doc, field_idx, "slot");
    if (lantern_fixture_token_to_uint64(doc, root_idx, &out_data->head.slot) != 0) {
        return -1;
    }

    field_idx = lantern_fixture_object_get_field(doc, data_obj_idx, "target");
    if (field_idx < 0) {
        return -1;
    }
    root_idx = lantern_fixture_object_get_field(doc, field_idx, "root");
    if (lantern_fixture_token_to_root(doc, root_idx, &out_data->target.root) != 0) {
        return -1;
    }
    root_idx = lantern_fixture_object_get_field(doc, field_idx, "slot");
    if (lantern_fixture_token_to_uint64(doc, root_idx, &out_data->target.slot) != 0) {
        return -1;
    }

    field_idx = lantern_fixture_object_get_field(doc, data_obj_idx, "source");
    if (field_idx < 0) {
        return -1;
    }
    root_idx = lantern_fixture_object_get_field(doc, field_idx, "root");
    if (lantern_fixture_token_to_root(doc, root_idx, &out_data->source.root) != 0) {
        return -1;
    }
    root_idx = lantern_fixture_object_get_field(doc, field_idx, "slot");
    if (lantern_fixture_token_to_uint64(doc, root_idx, &out_data->source.slot) != 0) {
        return -1;
    }
    return 0;
}

static int lantern_fixture_parse_attestation_message(
    const struct lantern_fixture_document *doc,
    int attestation_idx,
    LanternSignedVote *vote) {
    if (!doc || !vote) {
        return -1;
    }
    memset(vote, 0, sizeof(*vote));

    int validator_idx = lantern_fixture_object_get_field(doc, attestation_idx, "validatorId");
    if (validator_idx < 0) {
        /* Try snake_case fallback for legacy fixtures */
        validator_idx = lantern_fixture_object_get_field(doc, attestation_idx, "validator_id");
        if (validator_idx < 0) {
            return -1;
        }
    }
    if (lantern_fixture_token_to_uint64(doc, validator_idx, &vote->data.validator_id) != 0) {
        return -1;
    }

    int data_obj_idx = lantern_fixture_object_get_field(doc, attestation_idx, "data");
    if (data_obj_idx < 0) {
        return -1;
    }
    if (lantern_fixture_parse_attestation_data(doc, data_obj_idx, &vote->data.data) != 0) {
        return -1;
    }

    memset(vote->signature.bytes, 0, sizeof(vote->signature.bytes));
    return 0;
}

static bool lantern_fixture_attestation_data_equal(
    const LanternAttestationData *a,
    const LanternAttestationData *b) {
    if (!a || !b) {
        return false;
    }
    if (a->slot != b->slot) {
        return false;
    }
    if (a->head.slot != b->head.slot || a->target.slot != b->target.slot || a->source.slot != b->source.slot) {
        return false;
    }
    if (memcmp(a->head.root.bytes, b->head.root.bytes, LANTERN_ROOT_SIZE) != 0) {
        return false;
    }
    if (memcmp(a->target.root.bytes, b->target.root.bytes, LANTERN_ROOT_SIZE) != 0) {
        return false;
    }
    if (memcmp(a->source.root.bytes, b->source.root.bytes, LANTERN_ROOT_SIZE) != 0) {
        return false;
    }
    return true;
}

static int lantern_fixture_aggregate_votes(
    const LanternAttestations *votes,
    LanternAggregatedAttestations *out_attestations) {
    if (!votes || !out_attestations) {
        return -1;
    }
    if (lantern_aggregated_attestations_resize(out_attestations, 0) != 0) {
        return -1;
    }
    for (size_t i = 0; i < votes->length; ++i) {
        const LanternVote *vote = &votes->data[i];
        if (vote->validator_id >= LANTERN_VALIDATOR_REGISTRY_LIMIT) {
            return -1;
        }
        size_t match_idx = out_attestations->length;
        for (size_t j = 0; j < out_attestations->length; ++j) {
            if (lantern_fixture_attestation_data_equal(&out_attestations->data[j].data, &vote->data)) {
                match_idx = j;
                break;
            }
        }
        if (match_idx == out_attestations->length) {
            LanternAggregatedAttestation aggregated;
            lantern_aggregated_attestation_init(&aggregated);
            aggregated.data = vote->data;
            size_t bit_length = (size_t)vote->validator_id + 1u;
            if (lantern_bitlist_resize(&aggregated.aggregation_bits, bit_length) != 0) {
                lantern_aggregated_attestation_reset(&aggregated);
                return -1;
            }
            if (lantern_bitlist_set(&aggregated.aggregation_bits, (size_t)vote->validator_id, true) != 0) {
                lantern_aggregated_attestation_reset(&aggregated);
                return -1;
            }
            if (lantern_aggregated_attestations_append(out_attestations, &aggregated) != 0) {
                lantern_aggregated_attestation_reset(&aggregated);
                return -1;
            }
            lantern_aggregated_attestation_reset(&aggregated);
            continue;
        }

        LanternAggregatedAttestation *existing = &out_attestations->data[match_idx];
        size_t needed_length = (size_t)vote->validator_id + 1u;
        if (needed_length > existing->aggregation_bits.bit_length) {
            if (lantern_bitlist_resize(&existing->aggregation_bits, needed_length) != 0) {
                return -1;
            }
        }
        if (lantern_bitlist_set(&existing->aggregation_bits, (size_t)vote->validator_id, true) != 0) {
            return -1;
        }
    }
    return 0;
}

static int lantern_fixture_parse_byte_list_object(
    const struct lantern_fixture_document *doc,
    int container_idx,
    LanternByteList *list) {
    if (!doc || !list) {
        return -1;
    }
    if (container_idx < 0) {
        return lantern_byte_list_resize(list, 0);
    }
    int data_idx = container_idx;
    const jsmntok_t *container_tok = lantern_fixture_token(doc, container_idx);
    if (!container_tok) {
        return -1;
    }
    if (container_tok->type == JSMN_OBJECT) {
        data_idx = lantern_fixture_object_get_field(doc, container_idx, "data");
        if (data_idx < 0) {
            return lantern_byte_list_resize(list, 0);
        }
    }
    size_t len = 0;
    const char *str = lantern_fixture_token_string(doc, data_idx, &len);
    if (!str) {
        return -1;
    }
    if (len < 2 || str[0] != '0' || (str[1] != 'x' && str[1] != 'X')) {
        return -1;
    }
    size_t hex_len = len - 2u;
    if ((hex_len % 2u) != 0) {
        return -1;
    }
    size_t byte_len = hex_len / 2u;
    if (byte_len > LANTERN_AGG_PROOF_MAX_BYTES) {
        return -1;
    }
    if (lantern_byte_list_resize(list, byte_len) != 0) {
        return -1;
    }
    if (byte_len == 0) {
        return 0;
    }
    if (lantern_fixture_parse_hex_bytes(str, len, list->data, byte_len) != 0) {
        return -1;
    }
    return 0;
}

static int lantern_fixture_parse_aggregated_attestation(
    const struct lantern_fixture_document *doc,
    int entry_idx,
    LanternAggregatedAttestation *out_attestation) {
    if (!doc || !out_attestation) {
        return -1;
    }
    int bits_idx = lantern_fixture_object_get_field(doc, entry_idx, "aggregationBits");
    if (bits_idx < 0) {
        bits_idx = lantern_fixture_object_get_field(doc, entry_idx, "aggregation_bits");
    }
    if (bits_idx < 0) {
        return -1;
    }
    if (lantern_fixture_parse_bitlist_object(doc, bits_idx, &out_attestation->aggregation_bits) != 0) {
        return -1;
    }
    int data_idx = lantern_fixture_object_get_field(doc, entry_idx, "data");
    if (data_idx < 0) {
        return -1;
    }
    if (lantern_fixture_parse_attestation_data(doc, data_idx, &out_attestation->data) != 0) {
        return -1;
    }
    return 0;
}

static int lantern_fixture_wrap_vote_as_aggregated(
    const LanternSignedVote *vote,
    LanternAggregatedAttestation *out_attestation) {
    if (!vote || !out_attestation) {
        return -1;
    }
    uint64_t validator_id = vote->data.validator_id;
    if (validator_id >= LANTERN_VALIDATOR_REGISTRY_LIMIT) {
        return -1;
    }
    if (lantern_bitlist_resize(&out_attestation->aggregation_bits, (size_t)validator_id + 1u) != 0) {
        return -1;
    }
    size_t byte_len = ((size_t)validator_id + 1u + 7u) / 8u;
    if (byte_len > 0 && out_attestation->aggregation_bits.bytes) {
        memset(out_attestation->aggregation_bits.bytes, 0, byte_len);
        size_t byte_index = (size_t)validator_id / 8u;
        size_t bit_index = (size_t)validator_id % 8u;
        out_attestation->aggregation_bits.bytes[byte_index] |= (uint8_t)(1u << bit_index);
    }
    out_attestation->data = vote->data.data;
    return 0;
}

static int lantern_fixture_parse_signature_proof(
    const struct lantern_fixture_document *doc,
    int proof_idx,
    LanternAggregatedSignatureProof *out_proof) {
    if (!doc || !out_proof) {
        return -1;
    }
    int participants_idx = lantern_fixture_object_get_field(doc, proof_idx, "participants");
    if (participants_idx < 0) {
        participants_idx = lantern_fixture_object_get_field(doc, proof_idx, "aggregationBits");
        if (participants_idx < 0) {
            participants_idx = lantern_fixture_object_get_field(doc, proof_idx, "aggregation_bits");
        }
    }
    if (participants_idx < 0) {
        return -1;
    }
    if (lantern_fixture_parse_bitlist_object(doc, participants_idx, &out_proof->participants) != 0) {
        return -1;
    }
    int proof_data_idx = lantern_fixture_object_get_field(doc, proof_idx, "proofData");
    if (proof_data_idx < 0) {
        proof_data_idx = lantern_fixture_object_get_field(doc, proof_idx, "proof_data");
    }
    if (proof_data_idx < 0) {
        return -1;
    }
    if (lantern_fixture_parse_byte_list_object(doc, proof_data_idx, &out_proof->proof_data) != 0) {
        return -1;
    }
    return 0;
}

static int lantern_fixture_copy_bitlist(
    const struct lantern_bitlist *src,
    struct lantern_bitlist *dst) {
    if (!src || !dst) {
        return -1;
    }
    if (lantern_bitlist_resize(dst, src->bit_length) != 0) {
        return -1;
    }
    size_t byte_len = (src->bit_length + 7u) / 8u;
    if (byte_len > 0) {
        if (!src->bytes || !dst->bytes) {
            return -1;
        }
        memcpy(dst->bytes, src->bytes, byte_len);
    }
    return 0;
}

static int lantern_fixture_synthesize_signature_proof(
    const LanternAggregatedAttestation *attestation,
    const LanternSignature *signature,
    LanternAggregatedSignatureProof *out_proof) {
    if (!attestation || !out_proof) {
        return -1;
    }
    if (lantern_fixture_copy_bitlist(&attestation->aggregation_bits, &out_proof->participants) != 0) {
        return -1;
    }
    size_t proof_len = signature ? LANTERN_SIGNATURE_SIZE : 0;
    if (lantern_byte_list_resize(&out_proof->proof_data, proof_len) != 0) {
        return -1;
    }
    if (proof_len > 0 && out_proof->proof_data.data && signature) {
        memcpy(out_proof->proof_data.data, signature->bytes, proof_len);
    }
    return 0;
}

static int lantern_fixture_parse_attestation_signatures(
    const struct lantern_fixture_document *doc,
    int signatures_idx,
    LanternAttestationSignatures *signatures,
    size_t expected_count) {
    if (!doc || !signatures) {
        return -1;
    }
    int data_idx = lantern_fixture_object_get_field(doc, signatures_idx, "data");
    if (data_idx < 0) {
        return -1;
    }
    int length = lantern_fixture_array_get_length(doc, data_idx);
    if (length < 0) {
        return -1;
    }
    if ((size_t)length != expected_count) {
        return -1;
    }
    if (lantern_attestation_signatures_resize(signatures, (size_t)length) != 0) {
        return -1;
    }
    for (int i = 0; i < length; ++i) {
        int entry_idx = lantern_fixture_array_get_element(doc, data_idx, i);
        if (entry_idx < 0) {
            return -1;
        }
        if (lantern_fixture_parse_signature_proof(doc, entry_idx, &signatures->data[i]) != 0) {
            return -1;
        }
    }
    return 0;
}

static int lantern_fixture_parse_signature_array(
    const struct lantern_fixture_document *doc,
    int signatures_idx,
    LanternSignatureList *signatures) {
    if (!doc || !signatures) {
        return -1;
    }
    int data_idx = signatures_idx;
    const jsmntok_t *tok = lantern_fixture_token(doc, signatures_idx);
    if (!tok) {
        return -1;
    }
    if (tok->type == JSMN_OBJECT) {
        data_idx = lantern_fixture_object_get_field(doc, signatures_idx, "data");
        if (data_idx < 0) {
            return -1;
        }
        tok = lantern_fixture_token(doc, data_idx);
    }
    if (!tok || tok->type != JSMN_ARRAY) {
        return -1;
    }
    int length = lantern_fixture_array_get_length(doc, data_idx);
    if (length < 0) {
        return -1;
    }
    if (lantern_signature_list_resize(signatures, (size_t)length) != 0) {
        return -1;
    }
    for (int i = 0; i < length; ++i) {
        int entry_idx = lantern_fixture_array_get_element(doc, data_idx, i);
        if (entry_idx < 0) {
            return -1;
        }
        if (lantern_fixture_token_to_signature(doc, entry_idx, &signatures->data[i]) != 0) {
            return -1;
        }
    }
    return 0;
}

static int lantern_fixture_apply_signature_list_to_block_signatures(
    const LanternSignatureList *signature_list,
    const LanternAggregatedAttestations *attestations,
    LanternBlockSignatures *signatures) {
    if (!signatures) {
        return -1;
    }
    size_t att_count = attestations ? attestations->length : 0;
    size_t sig_count = signature_list ? signature_list->length : 0;
    if (lantern_attestation_signatures_resize(&signatures->attestation_signatures, att_count) != 0) {
        return -1;
    }
    for (size_t i = 0; i < att_count; ++i) {
        LanternAggregatedSignatureProof *proof = &signatures->attestation_signatures.data[i];
        const LanternSignature *sig = NULL;
        if (signature_list && i < signature_list->length) {
            sig = &signature_list->data[i];
        }
        const LanternAggregatedAttestation *att = attestations ? &attestations->data[i] : NULL;
        if (att) {
            if (lantern_fixture_synthesize_signature_proof(att, sig, proof) != 0) {
                return -1;
            }
        } else {
            if (lantern_byte_list_resize(&proof->proof_data, 0) != 0) {
                return -1;
            }
        }
    }
    if (sig_count > att_count) {
        signatures->proposer_signature = signature_list->data[att_count];
    } else {
        memset(signatures->proposer_signature.bytes, 0, sizeof(signatures->proposer_signature.bytes));
    }
    return 0;
}

static int lantern_fixture_parse_block_signatures(
    const struct lantern_fixture_document *doc,
    int signatures_idx,
    const LanternAggregatedAttestations *attestations,
    LanternBlockSignatures *signatures) {
    if (!doc || !signatures) {
        return -1;
    }
    int att_idx = lantern_fixture_object_get_field(doc, signatures_idx, "attestationSignatures");
    if (att_idx < 0) {
        att_idx = lantern_fixture_object_get_field(doc, signatures_idx, "attestation_signatures");
    }
    int proposer_idx = lantern_fixture_object_get_field(doc, signatures_idx, "proposerSignature");
    if (proposer_idx < 0) {
        proposer_idx = lantern_fixture_object_get_field(doc, signatures_idx, "proposer_signature");
    }

    if (att_idx >= 0) {
        size_t expected = attestations ? attestations->length : 0;
        if (lantern_fixture_parse_attestation_signatures(doc, att_idx, &signatures->attestation_signatures, expected)
            != 0) {
            return -1;
        }
        if (proposer_idx >= 0) {
            if (lantern_fixture_token_to_signature(doc, proposer_idx, &signatures->proposer_signature) != 0) {
                return -1;
            }
        } else {
            memset(signatures->proposer_signature.bytes, 0, sizeof(signatures->proposer_signature.bytes));
        }
        return 0;
    }

    const jsmntok_t *sig_tok = lantern_fixture_token(doc, signatures_idx);
    if (sig_tok && (sig_tok->type == JSMN_ARRAY || sig_tok->type == JSMN_OBJECT)) {
        LanternSignatureList signature_list;
        lantern_signature_list_init(&signature_list);
        if (lantern_fixture_parse_signature_array(doc, signatures_idx, &signature_list) != 0) {
            lantern_signature_list_reset(&signature_list);
            return -1;
        }
        int rc = lantern_fixture_apply_signature_list_to_block_signatures(
            &signature_list,
            attestations,
            signatures);
        lantern_signature_list_reset(&signature_list);
        return rc;
    }

    return -1;
}

static int lantern_fixture_synthesize_block_signatures(
    const LanternAggregatedAttestations *attestations,
    LanternBlockSignatures *signatures) {
    if (!signatures) {
        return -1;
    }
    size_t att_count = attestations ? attestations->length : 0;
    if (lantern_attestation_signatures_resize(&signatures->attestation_signatures, att_count) != 0) {
        return -1;
    }
    for (size_t i = 0; i < att_count; ++i) {
        LanternAggregatedSignatureProof *proof = &signatures->attestation_signatures.data[i];
        if (lantern_fixture_synthesize_signature_proof(&attestations->data[i], NULL, proof) != 0) {
            return -1;
        }
    }
    memset(signatures->proposer_signature.bytes, 0, sizeof(signatures->proposer_signature.bytes));
    return 0;
}

static int lantern_fixture_parse_attestations(
    const struct lantern_fixture_document *doc,
    int body_idx,
    LanternBlockBody *body) {
    if (!body) {
        return -1;
    }
    lantern_block_body_init(body);
    int att_idx = lantern_fixture_object_get_field(doc, body_idx, "attestations");
    if (att_idx < 0) {
        return 0;
    }
    int data_idx = lantern_fixture_object_get_field(doc, att_idx, "data");
    if (data_idx < 0) {
        return 0;
    }
    int length = lantern_fixture_array_get_length(doc, data_idx);
    if (length < 0) {
        return -1;
    }
    bool has_aggregated = false;
    bool has_individual = false;
    for (int i = 0; i < length; ++i) {
        int entry_idx = lantern_fixture_array_get_element(doc, data_idx, i);
        if (entry_idx < 0) {
            return -1;
        }
        int bits_idx = lantern_fixture_object_get_field(doc, entry_idx, "aggregationBits");
        if (bits_idx < 0) {
            bits_idx = lantern_fixture_object_get_field(doc, entry_idx, "aggregation_bits");
        }
        if (bits_idx >= 0) {
            has_aggregated = true;
        } else {
            has_individual = true;
        }
    }
    if (has_aggregated && has_individual) {
        return -1;
    }
    if (has_aggregated) {
        if (lantern_aggregated_attestations_resize(&body->attestations, (size_t)length) != 0) {
            return -1;
        }
        for (int i = 0; i < length; ++i) {
            int entry_idx = lantern_fixture_array_get_element(doc, data_idx, i);
            if (entry_idx < 0) {
                return -1;
            }
            if (lantern_fixture_parse_aggregated_attestation(doc, entry_idx, &body->attestations.data[i]) != 0) {
                return -1;
            }
        }
        return 0;
    }

    LanternAttestations votes;
    lantern_attestations_init(&votes);
    if (lantern_attestations_resize(&votes, (size_t)length) != 0) {
        lantern_attestations_reset(&votes);
        return -1;
    }
    for (int i = 0; i < length; ++i) {
        int entry_idx = lantern_fixture_array_get_element(doc, data_idx, i);
        if (entry_idx < 0) {
            lantern_attestations_reset(&votes);
            return -1;
        }
        LanternSignedVote vote;
        if (lantern_fixture_parse_attestation_message(doc, entry_idx, &vote) != 0) {
            lantern_attestations_reset(&votes);
            return -1;
        }
        votes.data[i] = vote.data;
    }
    int rc = lantern_fixture_aggregate_votes(&votes, &body->attestations);
    lantern_attestations_reset(&votes);
    return rc;
}

static void lantern_fixture_write_u32_le(uint8_t *out, uint32_t value) {
    out[0] = (uint8_t)(value & 0xffu);
    out[1] = (uint8_t)((value >> 8) & 0xffu);
    out[2] = (uint8_t)((value >> 16) & 0xffu);
    out[3] = (uint8_t)((value >> 24) & 0xffu);
}

static int lantern_fixture_parse_fp_vector(
    const struct lantern_fixture_document *doc,
    int vector_idx,
    uint8_t *out,
    size_t expected_len) {
    if (!doc || !out) {
        return -1;
    }
    int data_idx = lantern_fixture_object_get_field(doc, vector_idx, "data");
    if (data_idx < 0) {
        return -1;
    }
    int length = lantern_fixture_array_get_length(doc, data_idx);
    if (length < 0 || (size_t)length != expected_len) {
        return -1;
    }
    for (int i = 0; i < length; ++i) {
        int entry_idx = lantern_fixture_array_get_element(doc, data_idx, i);
        if (entry_idx < 0) {
            return -1;
        }
        uint64_t value = 0;
        if (lantern_fixture_token_to_uint64(doc, entry_idx, &value) != 0) {
            return -1;
        }
        if (value > UINT32_MAX) {
            return -1;
        }
        lantern_fixture_write_u32_le(out + (i * LANTERN_XMSS_FP_BYTES), (uint32_t)value);
    }
    return 0;
}

static int lantern_fixture_parse_hash_digest_list(
    const struct lantern_fixture_document *doc,
    int list_idx,
    uint8_t **out_bytes,
    size_t *out_count) {
    if (!doc || !out_bytes || !out_count) {
        return -1;
    }
    *out_bytes = NULL;
    *out_count = 0;
    int data_idx = lantern_fixture_object_get_field(doc, list_idx, "data");
    if (data_idx < 0) {
        return -1;
    }
    int length = lantern_fixture_array_get_length(doc, data_idx);
    if (length < 0) {
        return -1;
    }
    if (length == 0) {
        return 0;
    }
    if ((size_t)length > SIZE_MAX / LANTERN_XMSS_HASH_DIGEST_BYTES) {
        return -1;
    }
    size_t total_bytes = (size_t)length * LANTERN_XMSS_HASH_DIGEST_BYTES;
    uint8_t *buffer = malloc(total_bytes);
    if (!buffer) {
        return -1;
    }
    for (int i = 0; i < length; ++i) {
        int entry_idx = lantern_fixture_array_get_element(doc, data_idx, i);
        if (entry_idx < 0) {
            free(buffer);
            return -1;
        }
        if (lantern_fixture_parse_fp_vector(
                doc,
                entry_idx,
                buffer + ((size_t)i * LANTERN_XMSS_HASH_DIGEST_BYTES),
                LANTERN_XMSS_HASH_LEN_FE)
            != 0) {
            free(buffer);
            return -1;
        }
    }
    *out_bytes = buffer;
    *out_count = (size_t)length;
    return 0;
}

static int lantern_fixture_parse_signature_object_with_bindings(
    const struct lantern_fixture_document *doc,
    int signature_idx,
    LanternSignature *signature) {
    if (!doc || !signature) {
        return -1;
    }
    const jsmntok_t *signature_tok = lantern_fixture_token(doc, signature_idx);
    if (!signature_tok || signature_tok->type != JSMN_OBJECT) {
        return -1;
    }
    if (signature_tok->start < 0 || signature_tok->end < signature_tok->start) {
        return -1;
    }

    const uint8_t *json = (const uint8_t *)(doc->text + signature_tok->start);
    size_t json_len = (size_t)(signature_tok->end - signature_tok->start);
    if (!json || json_len == 0) {
        return -1;
    }

    struct PQSignature *pq_signature = NULL;
    enum PQSigningError rc = pq_signature_from_json(json, (uintptr_t)json_len, &pq_signature);
    if (rc != Success || !pq_signature) {
        return -1;
    }

    memset(signature->bytes, 0, sizeof(signature->bytes));
    uintptr_t written_len = 0;
    rc = pq_signature_serialize(
        pq_signature,
        signature->bytes,
        (uintptr_t)sizeof(signature->bytes),
        &written_len);
    pq_signature_free(pq_signature);
    if (rc != Success || written_len == 0 || written_len > sizeof(signature->bytes)) {
        return -1;
    }
    return 0;
}

static int lantern_fixture_parse_signature_object_legacy(
    const struct lantern_fixture_document *doc,
    int signature_idx,
    LanternSignature *signature) {
    if (!doc || !signature) {
        return -1;
    }
    int path_idx = lantern_fixture_object_get_field(doc, signature_idx, "path");
    int rho_idx = lantern_fixture_object_get_field(doc, signature_idx, "rho");
    int hashes_idx = lantern_fixture_object_get_field(doc, signature_idx, "hashes");
    if (path_idx < 0 || rho_idx < 0 || hashes_idx < 0) {
        return -1;
    }
    int siblings_idx = lantern_fixture_object_get_field(doc, path_idx, "siblings");
    if (siblings_idx < 0) {
        return -1;
    }
    uint8_t *siblings_bytes = NULL;
    size_t siblings_count = 0;
    if (lantern_fixture_parse_hash_digest_list(doc, siblings_idx, &siblings_bytes, &siblings_count) != 0) {
        return -1;
    }
    uint8_t rho_bytes[LANTERN_XMSS_RHO_BYTES];
    if (lantern_fixture_parse_fp_vector(doc, rho_idx, rho_bytes, LANTERN_XMSS_RAND_LEN_FE) != 0) {
        free(siblings_bytes);
        return -1;
    }
    uint8_t *hashes_bytes = NULL;
    size_t hashes_count = 0;
    if (lantern_fixture_parse_hash_digest_list(doc, hashes_idx, &hashes_bytes, &hashes_count) != 0) {
        free(siblings_bytes);
        return -1;
    }

    size_t siblings_len = siblings_count * LANTERN_XMSS_HASH_DIGEST_BYTES;
    size_t hashes_len = hashes_count * LANTERN_XMSS_HASH_DIGEST_BYTES;
    size_t path_offset = LANTERN_XMSS_SIGNATURE_FIXED_SECTION;
    size_t hashes_offset = path_offset + LANTERN_SSZ_U32_SIZE + siblings_len;
    size_t total_len = hashes_offset + hashes_len;
    if (path_offset > UINT32_MAX || hashes_offset > UINT32_MAX || total_len > LANTERN_SIGNATURE_SIZE) {
        free(siblings_bytes);
        free(hashes_bytes);
        return -1;
    }

    memset(signature->bytes, 0, sizeof(signature->bytes));
    lantern_fixture_write_u32_le(signature->bytes, (uint32_t)path_offset);
    memcpy(signature->bytes + LANTERN_SSZ_U32_SIZE, rho_bytes, sizeof(rho_bytes));
    lantern_fixture_write_u32_le(
        signature->bytes + LANTERN_SSZ_U32_SIZE + LANTERN_XMSS_RHO_BYTES,
        (uint32_t)hashes_offset);
    lantern_fixture_write_u32_le(signature->bytes + path_offset, LANTERN_SSZ_U32_SIZE);
    if (siblings_len > 0) {
        memcpy(signature->bytes + path_offset + LANTERN_SSZ_U32_SIZE, siblings_bytes, siblings_len);
    }
    if (hashes_len > 0) {
        memcpy(signature->bytes + hashes_offset, hashes_bytes, hashes_len);
    }

    free(siblings_bytes);
    free(hashes_bytes);
    return 0;
}

static int lantern_fixture_token_to_signature(
    const struct lantern_fixture_document *doc,
    int index,
    LanternSignature *signature) {
    if (!signature) {
        return -1;
    }
    const jsmntok_t *tok = lantern_fixture_token(doc, index);
    if (!tok) {
        return -1;
    }
    if (tok->type == JSMN_OBJECT) {
        if (lantern_fixture_parse_signature_object_with_bindings(doc, index, signature) == 0) {
            return 0;
        }
        return lantern_fixture_parse_signature_object_legacy(doc, index, signature);
    }
    size_t len = 0;
    const char *str = lantern_fixture_token_string(doc, index, &len);
    if (!str) {
        return -1;
    }
    if (len < 2 || str[0] != '0' || (str[1] != 'x' && str[1] != 'X')) {
        return -1;
    }
    size_t hex_len = len - 2u;
    if ((hex_len % 2u) != 0) {
        return -1;
    }
    size_t byte_len = hex_len / 2u;
    if (byte_len > LANTERN_SIGNATURE_SIZE) {
        return -1;
    }
    uint8_t buffer[LANTERN_SIGNATURE_SIZE];
    if (byte_len > 0) {
        if (lantern_fixture_parse_hex_bytes(str, len, buffer, byte_len) != 0) {
            return -1;
        }
    }

    if (byte_len > 0) {
        struct PQSignature *pq_signature = NULL;
        enum PQSigningError sig_err = pq_signature_deserialize(buffer, byte_len, &pq_signature);
        if (sig_err == Success && pq_signature) {
            uintptr_t written_len = 0;
            enum PQSigningError serialize_err = pq_signature_serialize(
                pq_signature,
                signature->bytes,
                sizeof(signature->bytes),
                &written_len);
            pq_signature_free(pq_signature);
            if (serialize_err == Success && written_len > 0 && written_len <= sizeof(signature->bytes)) {
                return 0;
            }
        } else if (pq_signature) {
            pq_signature_free(pq_signature);
        }
    }

    memset(signature->bytes, 0, sizeof(signature->bytes));
    if (byte_len > 0) {
        memcpy(signature->bytes, buffer, byte_len);
    }
    return 0;
}

static int lantern_fixture_parse_signature_list(
    const struct lantern_fixture_document *doc,
    int signatures_idx,
    LanternSignatureList *signatures,
    size_t expected_count) {
    if (!doc || !signatures) {
        return -1;
    }
    int data_idx = signatures_idx;
    const jsmntok_t *tok = lantern_fixture_token(doc, signatures_idx);
    if (!tok) {
        return -1;
    }
    if (tok->type == JSMN_OBJECT) {
        data_idx = lantern_fixture_object_get_field(doc, signatures_idx, "data");
        if (data_idx < 0) {
            return -1;
        }
    }
    int length = lantern_fixture_array_get_length(doc, data_idx);
    if (length < 0) {
        return -1;
    }
    if ((size_t)length != expected_count) {
        return -1;
    }
    if (lantern_signature_list_resize(signatures, (size_t)length) != 0) {
        return -1;
    }
    for (int i = 0; i < length; ++i) {
        int entry_idx = lantern_fixture_array_get_element(doc, data_idx, i);
        if (entry_idx < 0) {
            return -1;
        }
        if (lantern_fixture_token_to_signature(doc, entry_idx, &signatures->data[i]) != 0) {
            return -1;
        }
    }
    return 0;
}

int lantern_fixture_parse_block(
    const struct lantern_fixture_document *doc,
    int object_index,
    LanternBlock *block) {
    if (!doc || !block) {
        return -1;
    }
    memset(block, 0, sizeof(*block));
    lantern_block_body_init(&block->body);

    int idx = lantern_fixture_object_get_field(doc, object_index, "slot");
    if (lantern_fixture_token_to_uint64(doc, idx, &block->slot) != 0) {
        return -1;
    }

    idx = lantern_fixture_object_get_field(doc, object_index, "proposer_index");
    if (idx < 0) {
        idx = lantern_fixture_object_get_field(doc, object_index, "proposerIndex");
    }
    if (lantern_fixture_token_to_uint64(doc, idx, &block->proposer_index) != 0) {
        return -1;
    }

    idx = lantern_fixture_object_get_field(doc, object_index, "parent_root");
    if (idx < 0) {
        idx = lantern_fixture_object_get_field(doc, object_index, "parentRoot");
    }
    if (lantern_fixture_token_to_root(doc, idx, &block->parent_root) != 0) {
        return -1;
    }

    idx = lantern_fixture_object_get_field(doc, object_index, "state_root");
    if (idx < 0) {
        idx = lantern_fixture_object_get_field(doc, object_index, "stateRoot");
    }
    if (lantern_fixture_token_to_root(doc, idx, &block->state_root) != 0) {
        return -1;
    }

    int body_idx = lantern_fixture_object_get_field(doc, object_index, "body");
    if (body_idx >= 0) {
        if (lantern_fixture_parse_attestations(doc, body_idx, &block->body) != 0) {
            return -1;
        }
    }

    return 0;
}

int lantern_fixture_parse_signed_block(
    const struct lantern_fixture_document *doc,
    int object_index,
    LanternSignedBlock *signed_block) {
    if (!doc || !signed_block) {
        return -1;
    }
    lantern_signed_block_with_attestation_init(signed_block);

    /* Try new leanSpec format: { "block": {...}, "proposerAttestation": {...}, "signature": {...} } */
    int block_idx = lantern_fixture_object_get_field(doc, object_index, "block");
    int proposer_idx = lantern_fixture_object_get_field(doc, object_index, "proposerAttestation");
    int signatures_idx = lantern_fixture_object_get_field(doc, object_index, "signature");
    if (proposer_idx < 0) {
        /* Try snake_case fallback for legacy fixtures */
        proposer_idx = lantern_fixture_object_get_field(doc, object_index, "proposer_attestation");
    }
    if (block_idx >= 0 && proposer_idx >= 0) {
        if (lantern_fixture_parse_block(doc, block_idx, &signed_block->message.block) != 0) {
            goto error;
        }
        LanternSignedVote proposer_vote;
        if (lantern_fixture_parse_attestation_message(doc, proposer_idx, &proposer_vote) != 0) {
            goto error;
        }
        signed_block->message.proposer_attestation = proposer_vote.data;

        if (signatures_idx >= 0) {
            if (lantern_fixture_parse_block_signatures(
                    doc,
                    signatures_idx,
                    &signed_block->message.block.body.attestations,
                    &signed_block->signatures)
                != 0) {
                if (lantern_fixture_synthesize_block_signatures(
                        &signed_block->message.block.body.attestations,
                        &signed_block->signatures)
                    != 0) {
                    goto error;
                }
            }
        } else {
            if (lantern_fixture_synthesize_block_signatures(
                    &signed_block->message.block.body.attestations,
                    &signed_block->signatures)
                != 0) {
                goto error;
            }
        }
        return 0;
    }

    /* Try legacy format: { "message": { "block": {...}, "proposer_attestation": {...} }, "signature": ... } */
    int message_idx = lantern_fixture_object_get_field(doc, object_index, "message");
    if (message_idx >= 0) {
        block_idx = lantern_fixture_object_get_field(doc, message_idx, "block");
        if (block_idx < 0) {
            goto error;
        }
        if (lantern_fixture_parse_block(doc, block_idx, &signed_block->message.block) != 0) {
            goto error;
        }

        proposer_idx = lantern_fixture_object_get_field(doc, message_idx, "proposerAttestation");
        if (proposer_idx < 0) {
            /* Try snake_case fallback for legacy fixtures */
            proposer_idx = lantern_fixture_object_get_field(doc, message_idx, "proposer_attestation");
            if (proposer_idx < 0) {
                goto error;
            }
        }
        LanternSignedVote proposer_vote;
        if (lantern_fixture_parse_attestation_message(doc, proposer_idx, &proposer_vote) != 0) {
            goto error;
        }
        signed_block->message.proposer_attestation = proposer_vote.data;

        signatures_idx = lantern_fixture_object_get_field(doc, object_index, "signature");
        if (signatures_idx >= 0) {
            if (lantern_fixture_parse_block_signatures(
                    doc,
                    signatures_idx,
                    &signed_block->message.block.body.attestations,
                    &signed_block->signatures)
                != 0) {
                LanternSignatureList legacy_list;
                lantern_signature_list_init(&legacy_list);
                size_t expected_signatures = signed_block->message.block.body.attestations.length + 1u;
                if (expected_signatures == 0) {
                    lantern_signature_list_reset(&legacy_list);
                    goto error;
                }
                if (lantern_fixture_parse_signature_list(doc, signatures_idx, &legacy_list, expected_signatures) == 0) {
                    if (lantern_fixture_apply_signature_list_to_block_signatures(
                            &legacy_list,
                            &signed_block->message.block.body.attestations,
                            &signed_block->signatures)
                        != 0) {
                        lantern_signature_list_reset(&legacy_list);
                        goto error;
                    }
                } else {
                    if (lantern_fixture_synthesize_block_signatures(
                            &signed_block->message.block.body.attestations,
                            &signed_block->signatures)
                        != 0) {
                        lantern_signature_list_reset(&legacy_list);
                        goto error;
                    }
                }
                lantern_signature_list_reset(&legacy_list);
            }
        } else {
            if (lantern_fixture_synthesize_block_signatures(
                    &signed_block->message.block.body.attestations,
                    &signed_block->signatures)
                != 0) {
                goto error;
            }
        }
        return 0;
    }

    /* Handle leanSpec fixtures that emit bare Block containers without signatures */
    if (lantern_fixture_parse_block(doc, object_index, &signed_block->message.block) != 0) {
        goto error;
    }
    LanternVote *proposer = &signed_block->message.proposer_attestation;
    memset(proposer, 0, sizeof(*proposer));
    proposer->validator_id = signed_block->message.block.proposer_index;
    proposer->slot = signed_block->message.block.slot;
    proposer->head.slot = signed_block->message.block.slot;
    proposer->target.slot = signed_block->message.block.slot;
    proposer->source.slot = signed_block->message.block.slot;

    if (lantern_fixture_synthesize_block_signatures(
            &signed_block->message.block.body.attestations,
            &signed_block->signatures)
        != 0) {
        goto error;
    }
    return 0;

error:
    lantern_signed_block_with_attestation_reset(signed_block);
    return -1;
}

int lantern_fixture_parse_anchor_state(
    const struct lantern_fixture_document *doc,
    int anchor_state_index,
    LanternState *state,
    LanternCheckpoint *latest_justified,
    LanternCheckpoint *latest_finalized,
    uint64_t *genesis_time,
    uint64_t *validator_count) {
    if (!doc || !state || !latest_justified || !latest_finalized || !genesis_time || !validator_count) {
        return -1;
    }

    int config_idx = lantern_fixture_object_get_field(doc, anchor_state_index, "config");
    if (config_idx < 0) {
        return -1;
    }
    int genesis_idx = lantern_fixture_object_get_field(doc, config_idx, "genesisTime");
    if (genesis_idx < 0) {
        return -1;
    }
    if (lantern_fixture_token_to_uint64(doc, genesis_idx, genesis_time) != 0) {
        return -1;
    }

    int validators_idx = lantern_fixture_object_get_field(doc, anchor_state_index, "validators");
    if (validators_idx < 0) {
        return -1;
    }
    int data_idx = lantern_fixture_object_get_field(doc, validators_idx, "data");
    if (data_idx < 0) {
        return -1;
    }
    int count = lantern_fixture_array_get_length(doc, data_idx);
    if (count < 0) {
        return -1;
    }
    uint8_t *validator_pubkeys = NULL;
    if (count > 0) {
        size_t total_bytes = (size_t)count * LANTERN_VALIDATOR_PUBKEY_SIZE;
        validator_pubkeys = (uint8_t *)malloc(total_bytes);
        if (!validator_pubkeys) {
            return -1;
        }
        memset(validator_pubkeys, 0, total_bytes);
        for (int i = 0; i < count; ++i) {
            int entry_idx = lantern_fixture_array_get_element(doc, data_idx, i);
            if (entry_idx < 0) {
                free(validator_pubkeys);
                return -1;
            }
            int pubkey_idx = lantern_fixture_object_get_field(doc, entry_idx, "pubkey");
            if (pubkey_idx < 0) {
                free(validator_pubkeys);
                return -1;
            }
            size_t pk_len = 0;
            const char *pk_str = lantern_fixture_token_string(doc, pubkey_idx, &pk_len);
            if (!pk_str) {
                free(validator_pubkeys);
                return -1;
            }
            if (lantern_fixture_parse_hex_bytes(
                    pk_str,
                    pk_len,
                    validator_pubkeys + (i * LANTERN_VALIDATOR_PUBKEY_SIZE),
                    LANTERN_VALIDATOR_PUBKEY_SIZE)
                != 0) {
                free(validator_pubkeys);
                return -1;
            }
        }
    }
    *validator_count = (uint64_t)count;

    lantern_state_init(state);
    if (lantern_state_generate_genesis(state, *genesis_time, *validator_count) != 0) {
        free(validator_pubkeys);
        return -1;
    }
    if (lantern_state_prepare_validator_votes(state, *validator_count) != 0) {
        free(validator_pubkeys);
        return -1;
    }
    if (lantern_state_set_validator_pubkeys(state, validator_pubkeys, (size_t)count) != 0) {
        free(validator_pubkeys);
        return -1;
    }
    free(validator_pubkeys);

    int slot_idx = lantern_fixture_object_get_field(doc, anchor_state_index, "slot");
    if (slot_idx >= 0) {
        uint64_t slot = 0;
        if (lantern_fixture_token_to_uint64(doc, slot_idx, &slot) != 0) {
            return -1;
        }
        state->slot = slot;
    }

    int justified_idx = lantern_fixture_object_get_field(doc, anchor_state_index, "latestJustified");
    int finalized_idx = lantern_fixture_object_get_field(doc, anchor_state_index, "latestFinalized");
    if (justified_idx < 0 || finalized_idx < 0) {
        return -1;
    }
    int root_idx = lantern_fixture_object_get_field(doc, justified_idx, "root");
    int root_slot_idx = lantern_fixture_object_get_field(doc, justified_idx, "slot");
    if (lantern_fixture_token_to_root(doc, root_idx, &latest_justified->root) != 0) {
        return -1;
    }
    if (lantern_fixture_token_to_uint64(doc, root_slot_idx, &latest_justified->slot) != 0) {
        return -1;
    }
    root_idx = lantern_fixture_object_get_field(doc, finalized_idx, "root");
    root_slot_idx = lantern_fixture_object_get_field(doc, finalized_idx, "slot");
    if (lantern_fixture_token_to_root(doc, root_idx, &latest_finalized->root) != 0) {
        return -1;
    }
    if (lantern_fixture_token_to_uint64(doc, root_slot_idx, &latest_finalized->slot) != 0) {
        return -1;
    }
    state->latest_justified = *latest_justified;
    state->latest_finalized = *latest_finalized;

    int header_idx = lantern_fixture_object_get_field(doc, anchor_state_index, "latestBlockHeader");
    if (header_idx < 0) {
        return -1;
    }
    uint64_t header_slot = 0;
    int field_idx = lantern_fixture_object_get_field(doc, header_idx, "slot");
    if (lantern_fixture_token_to_uint64(doc, field_idx, &header_slot) != 0) {
        return -1;
    }
    state->latest_block_header.slot = header_slot;

    field_idx = lantern_fixture_object_get_field(doc, header_idx, "proposerIndex");
    if (lantern_fixture_token_to_uint64(doc, field_idx, &state->latest_block_header.proposer_index) != 0) {
        return -1;
    }

    field_idx = lantern_fixture_object_get_field(doc, header_idx, "parentRoot");
    if (lantern_fixture_token_to_root(doc, field_idx, &state->latest_block_header.parent_root) != 0) {
        return -1;
    }

    field_idx = lantern_fixture_object_get_field(doc, header_idx, "stateRoot");
    if (lantern_fixture_token_to_root(doc, field_idx, &state->latest_block_header.state_root) != 0) {
        return -1;
    }

    field_idx = lantern_fixture_object_get_field(doc, header_idx, "bodyRoot");
    if (lantern_fixture_token_to_root(doc, field_idx, &state->latest_block_header.body_root) != 0) {
        return -1;
    }

    if (lantern_fixture_parse_root_array_field(
            doc,
            anchor_state_index,
            "historicalBlockHashes",
            &state->historical_block_hashes)
        != 0) {
        return -1;
    }
    if (lantern_fixture_parse_bitlist_field(doc, anchor_state_index, "justifiedSlots", &state->justified_slots) != 0) {
        return -1;
    }
    if (lantern_fixture_parse_root_array_field(
            doc,
            anchor_state_index,
            "justificationsRoots",
            &state->justification_roots)
        != 0) {
        return -1;
    }
    if (lantern_fixture_parse_bitlist_field(
            doc,
            anchor_state_index,
            "justificationsValidators",
            &state->justification_validators)
        != 0) {
        return -1;
    }

    return 0;
}
