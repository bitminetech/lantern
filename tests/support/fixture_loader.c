#include "tests/support/fixture_loader.h"

#include <errno.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "lantern/consensus/hash.h"
#include "lantern/support/strings.h"

#define JSON_INITIAL_TOKENS 256

int lantern_fixture_read_text_file(const char *path, char **out_buf) {
    if (!path || !out_buf) {
        return -1;
    }
    FILE *file = fopen(path, "rb");
    if (!file) {
        const char *debug = getenv("LANTERN_DEBUG_FIXTURES");
        if (debug && debug[0] != '\0') {
            fprintf(stderr, "fixture fopen failed: %s\n", path);
        }
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
        uint64_t bit_value = 0;
        if (lantern_fixture_token_to_uint64(doc, bit_idx, &bit_value) != 0) {
            return -1;
        }
        if (bit_value > 1) {
            return -1;
        }
        if (bit_value == 0) {
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

    int field_idx = lantern_fixture_object_get_field(doc, data_obj_idx, "slot");
    if (lantern_fixture_token_to_uint64(doc, field_idx, &vote->data.slot) != 0) {
        return -1;
    }

    field_idx = lantern_fixture_object_get_field(doc, data_obj_idx, "head");
    if (field_idx < 0) {
        return -1;
    }
    int root_idx = lantern_fixture_object_get_field(doc, field_idx, "root");
    if (lantern_fixture_token_to_root(doc, root_idx, &vote->data.head.root) != 0) {
        return -1;
    }
    root_idx = lantern_fixture_object_get_field(doc, field_idx, "slot");
    if (lantern_fixture_token_to_uint64(doc, root_idx, &vote->data.head.slot) != 0) {
        return -1;
    }

    field_idx = lantern_fixture_object_get_field(doc, data_obj_idx, "target");
    if (field_idx < 0) {
        return -1;
    }
    root_idx = lantern_fixture_object_get_field(doc, field_idx, "root");
    if (lantern_fixture_token_to_root(doc, root_idx, &vote->data.target.root) != 0) {
        return -1;
    }
    root_idx = lantern_fixture_object_get_field(doc, field_idx, "slot");
    if (lantern_fixture_token_to_uint64(doc, root_idx, &vote->data.target.slot) != 0) {
        return -1;
    }

    field_idx = lantern_fixture_object_get_field(doc, data_obj_idx, "source");
    if (field_idx < 0) {
        return -1;
    }
    root_idx = lantern_fixture_object_get_field(doc, field_idx, "root");
    if (lantern_fixture_token_to_root(doc, root_idx, &vote->data.source.root) != 0) {
        return -1;
    }
    root_idx = lantern_fixture_object_get_field(doc, field_idx, "slot");
    if (lantern_fixture_token_to_uint64(doc, root_idx, &vote->data.source.slot) != 0) {
        return -1;
    }

    memset(vote->signature.bytes, 0, sizeof(vote->signature.bytes));
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
    for (int i = 0; i < length; ++i) {
        int entry_idx = lantern_fixture_array_get_element(doc, data_idx, i);
        if (entry_idx < 0) {
            return -1;
        }
        LanternSignedVote vote;
        if (lantern_fixture_parse_attestation_message(doc, entry_idx, &vote) != 0) {
            return -1;
        }

        if (lantern_attestations_append(&body->attestations, &vote.data) != 0) {
            return -1;
        }
    }
    return 0;
}

static int lantern_fixture_token_to_signature(
    const struct lantern_fixture_document *doc,
    int index,
    LanternSignature *signature) {
    if (!signature) {
        return -1;
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
    memset(signature->bytes, 0, sizeof(signature->bytes));
    if (byte_len > 0) {
        memcpy(signature->bytes, buffer, byte_len);
    }
    return 0;
}

static int lantern_fixture_parse_signature_list(
    const struct lantern_fixture_document *doc,
    int signatures_idx,
    LanternBlockSignatures *signatures,
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
    if (lantern_block_signatures_resize(signatures, (size_t)length) != 0) {
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

    /* Try new leanSpec format: { "block": {...}, "proposerAttestation": {...} } */
    int block_idx = lantern_fixture_object_get_field(doc, object_index, "block");
    int proposer_idx = lantern_fixture_object_get_field(doc, object_index, "proposerAttestation");
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

        size_t attestation_count = signed_block->message.block.body.attestations.length;
        size_t expected_signatures = attestation_count + 1u;
        if (expected_signatures == 0) {
            goto error;
        }
        /* leanSpec fixtures may not include signatures - generate synthetic ones */
        if (lantern_block_signatures_resize(&signed_block->signatures, expected_signatures) != 0) {
            goto error;
        }
        for (size_t i = 0; i < signed_block->signatures.length; ++i) {
            memset(signed_block->signatures.data[i].bytes, 0, LANTERN_SIGNATURE_SIZE);
        }
        return 0;
    }

    /* Try legacy format: { "message": { "block": {...}, "proposer_attestation": {...} }, "signature": [...] } */
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

        size_t attestation_count = signed_block->message.block.body.attestations.length;
        size_t expected_signatures = attestation_count + 1u;
        if (expected_signatures == 0) {
            goto error;
        }

        int signatures_idx = lantern_fixture_object_get_field(doc, object_index, "signature");
        if (signatures_idx < 0) {
            goto error;
        }
        if (lantern_fixture_parse_signature_list(
                doc,
                signatures_idx,
                &signed_block->signatures,
                expected_signatures)
            != 0) {
            goto error;
        }
        if (!signed_block->signatures.data) {
            goto error;
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

    size_t attestation_count = signed_block->message.block.body.attestations.length;
    size_t expected_signatures = attestation_count + 1u;
    if (expected_signatures == 0) {
        goto error;
    }
    if (lantern_block_signatures_resize(&signed_block->signatures, expected_signatures) != 0) {
        goto error;
    }
    for (size_t i = 0; i < signed_block->signatures.length; ++i) {
        memset(signed_block->signatures.data[i].bytes, 0, LANTERN_SIGNATURE_SIZE);
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
    const char *debug_hash = getenv("LANTERN_DEBUG_STATE_HASH");
    if (debug_hash && debug_hash[0] != '\0') {
        char validators_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
        if (lantern_bytes_to_hex(
                state->validator_registry_root.bytes,
                LANTERN_ROOT_SIZE,
                validators_hex,
                sizeof(validators_hex),
                1)
            == 0) {
            fprintf(stderr, "fixture validators root: %s\n", validators_hex);
        }
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
