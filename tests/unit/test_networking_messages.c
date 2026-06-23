#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <errno.h>

#include "lantern/consensus/containers.h"
#include "lantern/consensus/hash.h"
#include "lantern/consensus/signature.h"
#include "lantern/consensus/ssz.h"
#include "lantern/core/client.h"
#include "lantern/networking/gossip.h"
#include "lantern/networking/gossipsub_service.h"
#include "lantern/networking/messages.h"
#include "lantern/networking/gossip_payloads.h"
#include "lantern/networking/reqresp_service.h"
#include "lantern/encoding/snappy.h"
#include "lantern/support/strings.h"
#include "multiformats/unsigned_varint/unsigned_varint.h"
#include "tests/support/fixture_loader.h"
#include "ssz.h"

#define CHECK(cond)                                                                 \
    do {                                                                            \
        if (!(cond)) {                                                              \
            fprintf(stderr, "check failed: %s (%s:%d)\n", #cond, __FILE__, __LINE__); \
            abort();                                                                \
        }                                                                           \
    } while (0)

static void check_zero(int rc, const char *context) {
    if (rc != 0) {
        fprintf(stderr, "%s failed (rc=%d)\n", context, rc);
        abort();
    }
}

static void fill_bytes(uint8_t *dst, size_t len, uint8_t seed) {
    for (size_t i = 0; i < len; ++i) {
        dst[i] = (uint8_t)(seed + i);
    }
}

static void fill_signature(LanternSignature *signature, uint8_t seed) {
    if (!signature) {
        return;
    }
    fill_bytes(signature->bytes, LANTERN_SIGNATURE_SIZE, seed);
}

static void expect_root_seed(const LanternRoot *root, uint8_t seed) {
    CHECK(root != NULL);
    uint8_t expected[LANTERN_ROOT_SIZE];
    fill_bytes(expected, sizeof(expected), seed);
    CHECK(memcmp(root->bytes, expected, sizeof(expected)) == 0);
}

static void expect_checkpoint_seed(const LanternCheckpoint *checkpoint, uint64_t slot, uint8_t seed) {
    CHECK(checkpoint != NULL);
    CHECK(checkpoint->slot == slot);
    expect_root_seed(&checkpoint->root, seed);
}

static bool build_consensus_fixture_path(const char *relative_path, char *path, size_t path_len) {
    if (!relative_path || !path || path_len == 0) {
        return false;
    }
    const char *trimmed = relative_path;
    static const char consensus_prefix[] = "consensus/";
    if (strncmp(relative_path, consensus_prefix, sizeof(consensus_prefix) - 1u) == 0) {
        trimmed = relative_path + (sizeof(consensus_prefix) - 1u);
    }
    int written = snprintf(path, path_len, "%s/%s", LANTERN_CONSENSUS_FIXTURE_DIR, trimmed);
    return written > 0 && (size_t)written < path_len;
}

static bool consensus_fixture_exists(const char *relative_path) {
    char path[PATH_MAX];
    if (!build_consensus_fixture_path(relative_path, path, sizeof(path))) {
        return false;
    }

    FILE *fp = fopen(path, "rb");
    if (!fp) {
        return false;
    }
    fclose(fp);
    return true;
}

struct mock_stream_ctx {
    uint8_t *data;
    size_t length;
    size_t position;
};

static ssize_t mock_stream_read(void *io_ctx, void *buf, size_t len) {
    struct mock_stream_ctx *ctx = (struct mock_stream_ctx *)io_ctx;
    if (!ctx || !buf || len == 0) {
        return -EINVAL;
    }
    if (ctx->position >= ctx->length) {
        return 0;
    }
    size_t remaining = ctx->length - ctx->position;
    size_t to_copy = remaining < len ? remaining : len;
    memcpy(buf, ctx->data + ctx->position, to_copy);
    ctx->position += to_copy;
    return (ssize_t)to_copy;
}

static ssize_t mock_stream_write(void *io_ctx, const void *buf, size_t len) {
    (void)io_ctx;
    (void)buf;
    (void)len;
    return -ENOTSUP;
}

static int mock_stream_close(void *io_ctx) {
    (void)io_ctx;
    return 0;
}

static int mock_stream_reset(void *io_ctx) {
    (void)io_ctx;
    return 0;
}

static int mock_stream_set_deadline(void *io_ctx, uint64_t ms) {
    (void)io_ctx;
    (void)ms;
    return 0;
}

static void mock_stream_free_ctx(void *io_ctx) {
    struct mock_stream_ctx *ctx = (struct mock_stream_ctx *)io_ctx;
    if (!ctx) {
        return;
    }
    free(ctx->data);
    free(ctx);
}

static void check_checkpoint_equal(const LanternCheckpoint *expected, const LanternCheckpoint *actual) {
    CHECK(expected != NULL);
    CHECK(actual != NULL);
    CHECK(expected->slot == actual->slot);
    CHECK(memcmp(expected->root.bytes, actual->root.bytes, LANTERN_ROOT_SIZE) == 0);
}

static void check_attestation_data_equal(
    const LanternAttestationData *expected,
    const LanternAttestationData *actual) {
    CHECK(expected != NULL);
    CHECK(actual != NULL);
    CHECK(expected->slot == actual->slot);
    check_checkpoint_equal(&expected->head, &actual->head);
    check_checkpoint_equal(&expected->target, &actual->target);
    check_checkpoint_equal(&expected->source, &actual->source);
}

static void check_bitlist_equal(const struct lantern_bitlist *expected, const struct lantern_bitlist *actual) {
    CHECK(expected != NULL);
    CHECK(actual != NULL);
    CHECK(expected->bit_length == actual->bit_length);
    size_t byte_len = (expected->bit_length + 7u) / 8u;
    if (byte_len == 0) {
        return;
    }
    CHECK(expected->bytes != NULL);
    CHECK(actual->bytes != NULL);
    CHECK(memcmp(expected->bytes, actual->bytes, byte_len) == 0);
}

static void check_aggregated_attestation_equal(
    const LanternAggregatedAttestation *expected,
    const LanternAggregatedAttestation *actual) {
    CHECK(expected != NULL);
    CHECK(actual != NULL);
    check_attestation_data_equal(&expected->data, &actual->data);
    check_bitlist_equal(&expected->aggregation_bits, &actual->aggregation_bits);
}

static void check_byte_list_equal(
    const LanternByteList *expected,
    const LanternByteList *actual) {
    CHECK(expected != NULL);
    CHECK(actual != NULL);
    CHECK(expected->length == actual->length);
    if (expected->length == 0) {
        return;
    }
    CHECK(expected->data != NULL);
    CHECK(actual->data != NULL);
    CHECK(memcmp(expected->data, actual->data, expected->length) == 0);
}

static uint32_t rng_state = UINT32_C(0x6ac1e39d);

static uint32_t rng_next(void) {
    uint32_t x = rng_state;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    rng_state = x;
    return x;
}

static uint64_t rng_next_u64(void) {
    uint64_t hi = (uint64_t)rng_next();
    uint64_t lo = (uint64_t)rng_next();
    return (hi << 32) | lo;
}

static uint64_t rng_uniform(uint64_t max_inclusive) {
    if (max_inclusive == 0) {
        return 0;
    }
    return rng_next_u64() % (max_inclusive + 1);
}

static void rng_fill_bytes(uint8_t *dst, size_t len) {
    if (!dst) {
        return;
    }
    for (size_t i = 0; i < len; ++i) {
        dst[i] = (uint8_t)(rng_next() & 0xFFu);
    }
}

static void populate_signed_block_proof(LanternByteList *proof, size_t raw_len, uint8_t seed) {
    LanternByteList raw_proof;
    lantern_byte_list_init(&raw_proof);
    check_zero(lantern_byte_list_resize(&raw_proof, raw_len), "raw signed block proof resize");
    fill_bytes(raw_proof.data, raw_proof.length, seed);
    CHECK(lantern_signature_wrap_type2_proof(&raw_proof, proof));
    lantern_byte_list_reset(&raw_proof);
}

static void populate_random_signed_block_proof(LanternByteList *proof, size_t raw_len) {
    LanternByteList raw_proof;
    lantern_byte_list_init(&raw_proof);
    CHECK(lantern_byte_list_resize(&raw_proof, raw_len) == 0);
    rng_fill_bytes(raw_proof.data, raw_proof.length);
    CHECK(lantern_signature_wrap_type2_proof(&raw_proof, proof));
    lantern_byte_list_reset(&raw_proof);
}

static size_t signed_block_min_capacity_for_test(const LanternSignedBlock *block) {
    (void)block;
    return 1u << 20; /* generous upper bound for unit tests */
}

static LanternCheckpoint build_checkpoint(uint8_t seed, uint64_t slot) {
    LanternCheckpoint checkpoint;
    fill_bytes(checkpoint.root.bytes, sizeof(checkpoint.root.bytes), seed);
    checkpoint.slot = slot;
    return checkpoint;
}

static LanternVote build_vote(void) {
    LanternVote vote;
    vote.validator_id = 0;
    vote.slot = 9;
    vote.head = build_checkpoint(0xAB, 10);
    vote.target = build_checkpoint(0xCD, 11);
    vote.source = build_checkpoint(0xEF, 12);
    return vote;
}

static LanternSignedVote build_signed_vote(uint64_t validator_id, uint64_t slot, uint8_t seed) {
    LanternSignedVote signed_vote;
    memset(&signed_vote, 0, sizeof(signed_vote));
    signed_vote.data = build_vote();
    signed_vote.data.validator_id = validator_id;
    signed_vote.data.slot = slot;
    signed_vote.data.head = build_checkpoint(seed, slot);
    signed_vote.data.target = build_checkpoint(seed + 1, slot);
    signed_vote.data.source = build_checkpoint(seed + 2, slot > 0 ? slot - 1 : slot);
    fill_signature(&signed_vote.signature, (uint8_t)(seed + 3));
    return signed_vote;
}

static void build_aggregated_attestation_from_vote(
    const LanternVote *vote,
    LanternAggregatedAttestation *out_attestation) {
    lantern_aggregated_attestation_init(out_attestation);
    out_attestation->data.slot = vote->slot;
    out_attestation->data.head = vote->head;
    out_attestation->data.target = vote->target;
    out_attestation->data.source = vote->source;
    size_t bit_length = (size_t)vote->validator_id + 1u;
    check_zero(lantern_bitlist_resize(&out_attestation->aggregation_bits, bit_length), "agg bits resize");
    check_zero(lantern_bitlist_set(&out_attestation->aggregation_bits, (size_t)vote->validator_id, true), "agg bits set");
}

static void populate_block(LanternSignedBlock *signed_block, uint8_t seed) {
    lantern_signed_block_init(signed_block);
    signed_block->block.slot = 100 + seed;
    signed_block->block.proposer_index = 3 + seed;
    fill_bytes(signed_block->block.parent_root.bytes, LANTERN_ROOT_SIZE, (uint8_t)(0x10 + seed));
    fill_bytes(signed_block->block.state_root.bytes, LANTERN_ROOT_SIZE, (uint8_t)(0x20 + seed));
    LanternSignedVote vote = build_signed_vote(1 + seed, 50 + seed, (uint8_t)(0x30 + seed));
    LanternAggregatedAttestation agg;
    build_aggregated_attestation_from_vote(&vote.data, &agg);
    check_zero(
        lantern_aggregated_attestations_append(&signed_block->block.body.attestations, &agg),
        "attestation append");
    lantern_aggregated_attestation_reset(&agg);
    populate_signed_block_proof(&signed_block->proof, 12u, (uint8_t)(0xE0 + seed));
}

struct block_hook_ctx {
    const LanternSignedBlock *expected;
    const char *expected_topic;
    int called;
};

static int block_publish_hook(
    const char *topic,
    const uint8_t *payload,
    size_t payload_len,
    void *user_data) {
    struct block_hook_ctx *ctx = (struct block_hook_ctx *)user_data;
    CHECK(ctx);
    CHECK(topic);
    CHECK(payload);
    CHECK(payload_len > 0);
    if (ctx->expected_topic) {
        CHECK(strcmp(topic, ctx->expected_topic) == 0);
    }

    LanternSignedBlock decoded;
    lantern_signed_block_init(&decoded);
    int rc = lantern_gossip_decode_signed_block_snappy(&decoded, payload, payload_len, NULL, NULL);
    if (rc != 0) {
        lantern_signed_block_reset(&decoded);
        return -1;
    }

    const LanternSignedBlock *expected = ctx->expected;
    CHECK(expected != NULL);
    CHECK(decoded.block.slot == expected->block.slot);
    CHECK(decoded.block.proposer_index == expected->block.proposer_index);
    CHECK(decoded.block.body.attestations.length == expected->block.body.attestations.length);
    check_byte_list_equal(&decoded.proof, &expected->proof);
    lantern_signed_block_reset(&decoded);
    ctx->called += 1;
    return 0;
}

enum block_fixture_kind {
    BLOCK_FIXTURE_STATE_TRANSITION,
    BLOCK_FIXTURE_FORK_CHOICE_STEP,
};

struct block_fixture_case {
    const char *fixture;
    enum block_fixture_kind kind;
    size_t index;
};

static int load_signed_block_fixture(const struct block_fixture_case *spec, LanternSignedBlock *out_block) {
    if (!spec || !out_block) {
        return -1;
    }
    char path[PATH_MAX];
    if (!build_consensus_fixture_path(spec->fixture, path, sizeof(path))) {
        return -1;
    }

    struct lantern_fixture_document doc;
    memset(&doc, 0, sizeof(doc));

    char *text = NULL;
    if (lantern_fixture_read_text_file(path, &text) != 0) {
        return -1;
    }
    if (lantern_fixture_document_init(&doc, text) != 0) {
        lantern_fixture_document_reset(&doc);
        return -1;
    }

    int status = -1;
    int case_idx = lantern_fixture_object_get_value_at(&doc, 0, 0);
    if (case_idx < 0) {
        goto cleanup;
    }

    int block_idx = -1;
    if (spec->kind == BLOCK_FIXTURE_STATE_TRANSITION) {
        int blocks_idx = lantern_fixture_object_get_field(&doc, case_idx, "blocks");
        if (blocks_idx < 0) {
            goto cleanup;
        }
        block_idx = lantern_fixture_array_get_element(&doc, blocks_idx, (int)spec->index);
    } else if (spec->kind == BLOCK_FIXTURE_FORK_CHOICE_STEP) {
        int steps_idx = lantern_fixture_object_get_field(&doc, case_idx, "steps");
        if (steps_idx < 0) {
            goto cleanup;
        }
        int step_idx = lantern_fixture_array_get_element(&doc, steps_idx, (int)spec->index);
        if (step_idx < 0) {
            goto cleanup;
        }
        block_idx = lantern_fixture_object_get_field(&doc, step_idx, "block");
    }

    if (block_idx < 0) {
        goto cleanup;
    }

    memset(out_block, 0, sizeof(*out_block));
    status = lantern_fixture_parse_signed_block(&doc, block_idx, out_block);

cleanup:
    lantern_fixture_document_reset(&doc);
    return status;
}

static void normalize_attestation_data_for_gossip_sanity(LanternAttestationData *data) {
    if (!data) {
        return;
    }
    if (data->target.slot < data->source.slot) {
        data->target.slot = data->source.slot;
    }
    if (data->slot < data->target.slot) {
        data->slot = data->target.slot;
    }
}

static void normalize_signed_block_for_gossip_sanity(LanternSignedBlock *block) {
    if (!block) {
        return;
    }
    for (size_t i = 0; i < block->block.body.attestations.length; ++i) {
        LanternAggregatedAttestation *att = &block->block.body.attestations.data[i];
        normalize_attestation_data_for_gossip_sanity(&att->data);
    }
}

static void test_replay_devnet_block_payloads(void) {
    struct block_fixture_case cases[] = {
        {
            .fixture =
                "consensus/fork_choice/devnet/fc/test_fork_choice_reorgs/test_reorg_on_newly_justified_slot.json",
            .kind = BLOCK_FIXTURE_FORK_CHOICE_STEP,
            .index = 4,
        },
        {
            .fixture =
                "consensus/state_transition/devnet/state_transition/test_block_processing/test_linear_chain_multiple_blocks.json",
            .kind = BLOCK_FIXTURE_STATE_TRANSITION,
            .index = 1,
        },
    };

    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); ++i) {
        LanternSignedBlock original;
        lantern_signed_block_init(&original);
        CHECK(load_signed_block_fixture(&cases[i], &original) == 0);
        normalize_signed_block_for_gossip_sanity(&original);
        LanternRoot original_block_root;
        memset(&original_block_root, 0, sizeof(original_block_root));
        CHECK(lantern_hash_tree_root_block(&original.block, &original_block_root) == SSZ_SUCCESS);

        size_t ssz_capacity = signed_block_min_capacity_for_test(&original);
        CHECK(ssz_capacity > 0);
        uint8_t *ssz_encoded = (uint8_t *)malloc(ssz_capacity);
        CHECK(ssz_encoded != NULL);
        size_t ssz_written = ssz_capacity;
        CHECK(lantern_ssz_encode_signed_block(&original, ssz_encoded, ssz_capacity, &ssz_written) == SSZ_SUCCESS);

        size_t max_compressed = 0;
        CHECK(lantern_snappy_max_compressed_size_raw(ssz_written, &max_compressed) == LANTERN_SNAPPY_OK);
        uint8_t *compressed = (uint8_t *)malloc(max_compressed);
        CHECK(compressed != NULL);
        size_t compressed_len = max_compressed;
        CHECK(lantern_gossip_encode_signed_block_snappy(&original, compressed, max_compressed, &compressed_len) == 0);

        LanternSignedBlock decoded;
        lantern_signed_block_init(&decoded);
        CHECK(lantern_gossip_decode_signed_block_snappy(&decoded, compressed, compressed_len, NULL, NULL) == 0);

        CHECK(decoded.block.slot == original.block.slot);
        CHECK(decoded.block.proposer_index == original.block.proposer_index);
        CHECK(memcmp(decoded.block.parent_root.bytes, original.block.parent_root.bytes, LANTERN_ROOT_SIZE) == 0);
        CHECK(memcmp(decoded.block.state_root.bytes, original.block.state_root.bytes, LANTERN_ROOT_SIZE) == 0);

        check_byte_list_equal(&decoded.proof, &original.proof);
        CHECK(decoded.block.body.attestations.length == original.block.body.attestations.length);
        if (decoded.block.body.attestations.length > 0) {
            CHECK(decoded.block.body.attestations.data != NULL);
            CHECK(original.block.body.attestations.data != NULL);
        }
        for (size_t att_idx = 0; att_idx < decoded.block.body.attestations.length; ++att_idx) {
            const LanternAggregatedAttestation *expected_att = &original.block.body.attestations.data[att_idx];
            const LanternAggregatedAttestation *decoded_att = &decoded.block.body.attestations.data[att_idx];
            check_aggregated_attestation_equal(expected_att, decoded_att);
        }

        LanternRoot decoded_block_root;
        memset(&decoded_block_root, 0, sizeof(decoded_block_root));
        CHECK(lantern_hash_tree_root_block(&decoded.block, &decoded_block_root) == SSZ_SUCCESS);
        CHECK(memcmp(decoded_block_root.bytes, original_block_root.bytes, LANTERN_ROOT_SIZE) == 0);

        uint8_t *roundtrip = (uint8_t *)malloc(ssz_written);
        CHECK(roundtrip != NULL);
        size_t roundtrip_written = ssz_written;
        CHECK(
            lantern_snappy_decompress_raw(
                compressed,
                compressed_len,
                roundtrip,
                ssz_written,
                &roundtrip_written)
            == LANTERN_SNAPPY_OK);
        CHECK(roundtrip_written == ssz_written);
        CHECK(memcmp(roundtrip, ssz_encoded, ssz_written) == 0);

        free(roundtrip);
        free(compressed);
        free(ssz_encoded);
        lantern_signed_block_reset(&original);
        lantern_signed_block_reset(&decoded);
    }
}

static void test_status_message(void) {
    LanternStatusMessage status = {
        .finalized = build_checkpoint(0xAA, 42),
        .head = build_checkpoint(0xBB, 64),
    };

    uint8_t encoded[128];
    size_t written = 0;
    check_zero(lantern_network_status_encode(&status, encoded, sizeof(encoded), &written), "status encode");
    CHECK(written == 2u * LANTERN_CHECKPOINT_SSZ_SIZE);

    LanternStatusMessage decoded = {0};
    check_zero(lantern_network_status_decode(&decoded, encoded, written), "status decode");
    CHECK(memcmp(decoded.finalized.root.bytes, status.finalized.root.bytes, LANTERN_ROOT_SIZE) == 0);
    CHECK(decoded.head.slot == status.head.slot);

}

static void test_status_decode_rejects_truncated_payloads(void) {
    LanternStatusMessage decoded = {0};
    uint8_t zero_payload[2u * LANTERN_CHECKPOINT_SSZ_SIZE] = {0};
    CHECK(lantern_network_status_decode(&decoded, zero_payload, 0) != 0);
    CHECK(lantern_network_status_decode(&decoded, zero_payload, LANTERN_CHECKPOINT_SSZ_SIZE) != 0);
    CHECK(
        lantern_network_status_decode(
            &decoded,
            zero_payload,
            (2u * LANTERN_CHECKPOINT_SSZ_SIZE) - 1)
        != 0);

    uint8_t extra_payload[(2u * LANTERN_CHECKPOINT_SSZ_SIZE) + 4u];
    memset(extra_payload, 0, sizeof(extra_payload));
    CHECK(lantern_network_status_decode(&decoded, extra_payload, sizeof(extra_payload)) != 0);
}

static void test_status_reqresp_snappy_fixture(void) {
    /* Build status message with same values as the fixture */
    LanternStatusMessage status = {
        .finalized = build_checkpoint(0x11, 42),
        .head = build_checkpoint(0x41, 96),
    };

    /* Encode to raw SSZ then compress with framed snappy */
    uint8_t raw_ssz[2u * LANTERN_CHECKPOINT_SSZ_SIZE];
    size_t raw_ssz_len = 0;
    check_zero(
        lantern_network_status_encode(&status, raw_ssz, sizeof(raw_ssz), &raw_ssz_len),
        "status encode");
    CHECK(raw_ssz_len == 2u * LANTERN_CHECKPOINT_SSZ_SIZE);

    size_t max_compressed = 0;
    CHECK(lantern_snappy_max_compressed_size(raw_ssz_len, &max_compressed) == LANTERN_SNAPPY_OK);
    uint8_t *snappy_payload = (uint8_t *)malloc(max_compressed);
    CHECK(snappy_payload != NULL);
    size_t snappy_len = 0;
    CHECK(
        lantern_snappy_compress(raw_ssz, raw_ssz_len, snappy_payload, max_compressed, &snappy_len)
        == LANTERN_SNAPPY_OK);

    /* Build reqresp frame - varint encodes the uncompressed SSZ payload size */
    uint8_t header[LANTERN_REQRESP_HEADER_MAX_BYTES];
    size_t header_len = 0;
    CHECK(libp2p_uvarint_encode(raw_ssz_len, header, sizeof(header), &header_len) == LIBP2P_UVARINT_OK);

    size_t framed_len = 1u + header_len + snappy_len;
    uint8_t *framed = (uint8_t *)malloc(framed_len);
    CHECK(framed != NULL);
    framed[0] = LANTERN_REQRESP_RESPONSE_SUCCESS;
    memcpy(framed + 1, header, header_len);
    memcpy(framed + 1 + header_len, snappy_payload, snappy_len);

    struct mock_stream_ctx *ctx = (struct mock_stream_ctx *)malloc(sizeof(*ctx));
    CHECK(ctx != NULL);
    ctx->data = framed;
    ctx->length = framed_len;
    ctx->position = 0;

    struct lantern_reqresp_stream_ops ops = {
        .read = mock_stream_read,
        .write = mock_stream_write,
        .close = mock_stream_close,
        .reset = mock_stream_reset,
        .set_deadline = mock_stream_set_deadline,
        .free_ctx = mock_stream_free_ctx,
    };
    struct lantern_reqresp_stream *stream = lantern_reqresp_stream_from_ops(ctx, &ops, NULL);
    CHECK(stream != NULL);

    uint8_t *response = NULL;
    size_t response_len = 0;
    ssize_t read_err = 0;
    uint8_t response_code = 0;
    check_zero(
        lantern_reqresp_read_response_chunk(
            NULL,
            stream,
            LANTERN_REQRESP_PROTOCOL_STATUS,
            &response,
            &response_len,
            &read_err,
            &response_code,
            NULL),
        "reqresp read status response");
    CHECK(response_code == LANTERN_REQRESP_RESPONSE_SUCCESS);
    CHECK(response_len == snappy_len);
    CHECK(memcmp(response, snappy_payload, snappy_len) == 0);

    LanternStatusMessage decoded = {0};
    uint8_t decoded_raw[2u * LANTERN_CHECKPOINT_SSZ_SIZE];
    size_t decoded_raw_len = sizeof(decoded_raw);
    CHECK(
        lantern_snappy_decompress(response, response_len, decoded_raw, sizeof(decoded_raw), &decoded_raw_len)
        == LANTERN_SNAPPY_OK);
    check_zero(
        lantern_network_status_decode(&decoded, decoded_raw, decoded_raw_len),
        "reqresp status decode");
    expect_checkpoint_seed(&decoded.finalized, 42, 0x11);
    expect_checkpoint_seed(&decoded.head, 96, 0x41);

    free(response);
    lantern_reqresp_stream_free(stream);
    free(snappy_payload);
}

static uint8_t *build_reqresp_frame(
    uint8_t response_code,
    const uint8_t *payload,
    size_t payload_len,
    size_t raw_len,
    size_t *out_len) {
    /* Varint encodes the uncompressed payload size (SSZ length). */
    uint8_t header[LANTERN_REQRESP_HEADER_MAX_BYTES];
    size_t header_len = 0;
    CHECK(libp2p_uvarint_encode(raw_len, header, sizeof(header), &header_len) == LIBP2P_UVARINT_OK);

    size_t frame_len = 1u + header_len + payload_len;
    uint8_t *frame = (uint8_t *)malloc(frame_len);
    CHECK(frame != NULL);
    frame[0] = response_code;
    memcpy(frame + 1u, header, header_len);
    if (payload_len > 0) {
        memcpy(frame + 1u + header_len, payload, payload_len);
    }
    if (out_len) {
        *out_len = frame_len;
    }
    return frame;
}

static void test_reqresp_response_code_mapping(void) {
    const uint8_t status_payload[] = {0x01, 0x02, 0x03, 0x04};
    size_t raw_len = sizeof(status_payload);
    size_t max_compressed = 0;
    CHECK(lantern_snappy_max_compressed_size(raw_len, &max_compressed) == LANTERN_SNAPPY_OK);
    uint8_t *fixture = (uint8_t *)malloc(max_compressed);
    CHECK(fixture != NULL);
    size_t fixture_len = 0;
    CHECK(
        lantern_snappy_compress(
            status_payload,
            raw_len,
            fixture,
            max_compressed,
            &fixture_len)
        == LANTERN_SNAPPY_OK);
    CHECK(fixture_len > 0);

    struct {
        uint8_t wire_code;
        uint8_t expected_code;
    } cases[] = {
        {LANTERN_REQRESP_RESPONSE_RESOURCE_UNAVAILABLE, LANTERN_REQRESP_RESPONSE_RESOURCE_UNAVAILABLE},
        {4u, LANTERN_REQRESP_RESPONSE_SERVER_ERROR},
        {127u, LANTERN_REQRESP_RESPONSE_SERVER_ERROR},
        {128u, LANTERN_REQRESP_RESPONSE_INVALID_REQUEST},
        {200u, LANTERN_REQRESP_RESPONSE_INVALID_REQUEST},
    };

    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); ++i) {
        size_t frame_len = 0;
        uint8_t *frame = build_reqresp_frame(
            cases[i].wire_code,
            fixture,
            fixture_len,
            raw_len,
            &frame_len);

        struct mock_stream_ctx *ctx = (struct mock_stream_ctx *)malloc(sizeof(*ctx));
        CHECK(ctx != NULL);
        ctx->data = frame;
        ctx->length = frame_len;
        ctx->position = 0;

        struct lantern_reqresp_stream_ops ops = {
            .read = mock_stream_read,
            .write = mock_stream_write,
            .close = mock_stream_close,
            .reset = mock_stream_reset,
            .set_deadline = mock_stream_set_deadline,
            .free_ctx = mock_stream_free_ctx,
        };
        struct lantern_reqresp_stream *stream = lantern_reqresp_stream_from_ops(ctx, &ops, NULL);
        CHECK(stream != NULL);

        uint8_t *response = NULL;
        size_t response_len = 0;
        ssize_t read_err = 0;
        uint8_t response_code = 0;
        check_zero(
            lantern_reqresp_read_response_chunk(
                NULL,
                stream,
                LANTERN_REQRESP_PROTOCOL_STATUS,
                &response,
                &response_len,
                &read_err,
                &response_code,
                NULL),
            "reqresp read response (mapping)");
        CHECK(response_code == cases[i].expected_code);
        CHECK(response_len == fixture_len);
        CHECK(memcmp(response, fixture, fixture_len) == 0);

        free(response);
        lantern_reqresp_stream_free(stream);
    }

    free(fixture);
}

static void test_blocks_by_root_per_chunk_framing(void) {
    const uint8_t raw_one[] = {0x01, 0x02, 0x03, 0x04};
    const uint8_t raw_two[] = {0x10, 0x20, 0x30, 0x40, 0x50};

    size_t max_one = 0;
    CHECK(lantern_snappy_max_compressed_size(sizeof(raw_one), &max_one) == LANTERN_SNAPPY_OK);
    uint8_t *snappy_one = (uint8_t *)malloc(max_one);
    CHECK(snappy_one != NULL);
    size_t snappy_one_len = 0;
    CHECK(
        lantern_snappy_compress(
            raw_one,
            sizeof(raw_one),
            snappy_one,
            max_one,
            &snappy_one_len)
        == LANTERN_SNAPPY_OK);

    size_t max_two = 0;
    CHECK(lantern_snappy_max_compressed_size(sizeof(raw_two), &max_two) == LANTERN_SNAPPY_OK);
    uint8_t *snappy_two = (uint8_t *)malloc(max_two);
    CHECK(snappy_two != NULL);
    size_t snappy_two_len = 0;
    CHECK(
        lantern_snappy_compress(
            raw_two,
            sizeof(raw_two),
            snappy_two,
            max_two,
            &snappy_two_len)
        == LANTERN_SNAPPY_OK);

    size_t frame_one_len = 0;
    uint8_t *frame_one = build_reqresp_frame(
        LANTERN_REQRESP_RESPONSE_SUCCESS,
        snappy_one,
        snappy_one_len,
        sizeof(raw_one),
        &frame_one_len);
    size_t frame_two_len = 0;
    uint8_t *frame_two = build_reqresp_frame(
        LANTERN_REQRESP_RESPONSE_SUCCESS,
        snappy_two,
        snappy_two_len,
        sizeof(raw_two),
        &frame_two_len);

    size_t stream_len = frame_one_len + frame_two_len;
    uint8_t *stream_bytes = (uint8_t *)malloc(stream_len);
    CHECK(stream_bytes != NULL);
    memcpy(stream_bytes, frame_one, frame_one_len);
    memcpy(stream_bytes + frame_one_len, frame_two, frame_two_len);
    free(frame_one);
    free(frame_two);

    struct mock_stream_ctx *ctx = (struct mock_stream_ctx *)malloc(sizeof(*ctx));
    CHECK(ctx != NULL);
    ctx->data = stream_bytes;
    ctx->length = stream_len;
    ctx->position = 0;

    struct lantern_reqresp_stream_ops ops = {
        .read = mock_stream_read,
        .write = mock_stream_write,
        .close = mock_stream_close,
        .reset = mock_stream_reset,
        .set_deadline = mock_stream_set_deadline,
        .free_ctx = mock_stream_free_ctx,
    };
    struct lantern_reqresp_stream *stream = lantern_reqresp_stream_from_ops(ctx, &ops, NULL);
    CHECK(stream != NULL);

    uint8_t *response = NULL;
    size_t response_len = 0;
    ssize_t read_err = 0;
    uint8_t response_code = 0;
    check_zero(
        lantern_reqresp_read_response_chunk(
            NULL,
            stream,
            LANTERN_REQRESP_PROTOCOL_BLOCKS_BY_ROOT,
            &response,
            &response_len,
            &read_err,
            &response_code,
            NULL),
        "reqresp read blocks_by_root chunk 1");
    CHECK(response_code == LANTERN_REQRESP_RESPONSE_SUCCESS);
    CHECK(response_len == snappy_one_len);
    CHECK(memcmp(response, snappy_one, snappy_one_len) == 0);
    free(response);

    response = NULL;
    response_len = 0;
    response_code = 0;
    check_zero(
        lantern_reqresp_read_response_chunk(
            NULL,
            stream,
            LANTERN_REQRESP_PROTOCOL_BLOCKS_BY_ROOT,
            &response,
            &response_len,
            &read_err,
            &response_code,
            NULL),
        "reqresp read blocks_by_root chunk 2");
    CHECK(response_code == LANTERN_REQRESP_RESPONSE_SUCCESS);
    CHECK(response_len == snappy_two_len);
    CHECK(memcmp(response, snappy_two, snappy_two_len) == 0);
    free(response);

    lantern_reqresp_stream_free(stream);
    free(snappy_one);
    free(snappy_two);
}

static void test_blocks_by_root_request(void) {
    LanternBlocksByRootRequest req;
    lantern_blocks_by_root_request_init(&req);
    check_zero(lantern_root_list_resize(&req.roots, 2), "request roots resize");
    fill_bytes(req.roots.items[0].bytes, LANTERN_ROOT_SIZE, 0x11);
    fill_bytes(req.roots.items[1].bytes, LANTERN_ROOT_SIZE, 0x22);

    uint8_t encoded[128];
    size_t written = 0;
    check_zero(lantern_network_blocks_by_root_request_encode(&req, encoded, sizeof(encoded), &written), "request encode");
    size_t expected_written = sizeof(uint32_t) + (req.roots.length * LANTERN_ROOT_SIZE);
    CHECK(written == expected_written);
    CHECK(encoded[0] == 4u);
    CHECK(encoded[1] == 0u);
    CHECK(encoded[2] == 0u);
    CHECK(encoded[3] == 0u);
    CHECK(memcmp(
              encoded + sizeof(uint32_t),
              req.roots.items,
              req.roots.length * LANTERN_ROOT_SIZE)
          == 0);

    LanternBlocksByRootRequest decoded;
    lantern_blocks_by_root_request_init(&decoded);
    check_zero(lantern_network_blocks_by_root_request_decode(&decoded, encoded, written), "request decode");
    CHECK(decoded.roots.length == req.roots.length);
    CHECK(memcmp(decoded.roots.items[1].bytes, req.roots.items[1].bytes, LANTERN_ROOT_SIZE) == 0);

    lantern_blocks_by_root_request_reset(&req);
    lantern_blocks_by_root_request_reset(&decoded);
}

static void test_signed_block_list(void) {
    LanternSignedBlockList resp;
    lantern_signed_block_list_init(&resp);
    check_zero(lantern_signed_block_list_resize(&resp, 2), "response resize");
    populate_block(&resp.blocks[0], 1);
    populate_block(&resp.blocks[1], 2);

    size_t encoded_capacity = 1u << 20;
    uint8_t *encoded = (uint8_t *)malloc(encoded_capacity);
    CHECK(encoded != NULL);
    for (size_t i = 0; i < resp.length; ++i) {
        size_t tmp_written = 0;
        CHECK(lantern_ssz_encode_signed_block(&resp.blocks[i], encoded, encoded_capacity, &tmp_written) == SSZ_SUCCESS);
        CHECK(tmp_written > 0);
    }
    size_t written = 0;
    check_zero(
        lantern_network_signed_block_list_encode(&resp, encoded, encoded_capacity, &written),
        "response encode");
    CHECK(written >= resp.length * sizeof(uint32_t));
    uint32_t first_offset = (uint32_t)encoded[0]
        | ((uint32_t)encoded[1] << 8)
        | ((uint32_t)encoded[2] << 16)
        | ((uint32_t)encoded[3] << 24);
    CHECK(first_offset == resp.length * sizeof(uint32_t));
    for (size_t i = 0; i < resp.length; ++i) {
        size_t idx = i * sizeof(uint32_t);
        uint32_t offset_value = (uint32_t)encoded[idx]
            | ((uint32_t)encoded[idx + 1] << 8)
            | ((uint32_t)encoded[idx + 2] << 16)
            | ((uint32_t)encoded[idx + 3] << 24);
        CHECK(offset_value >= first_offset);
        CHECK(offset_value < written);
        if (i + 1 < resp.length) {
            size_t next_idx = (i + 1) * sizeof(uint32_t);
            uint32_t next_value = (uint32_t)encoded[next_idx]
                | ((uint32_t)encoded[next_idx + 1] << 8)
                | ((uint32_t)encoded[next_idx + 2] << 16)
                | ((uint32_t)encoded[next_idx + 3] << 24);
            CHECK(next_value > offset_value);
        }
    }

    LanternSignedBlockList decoded;
    lantern_signed_block_list_init(&decoded);
    check_zero(lantern_network_signed_block_list_decode(&decoded, encoded, written), "response decode");
    CHECK(decoded.length == resp.length);
    check_byte_list_equal(&decoded.blocks[1].proof, &resp.blocks[1].proof);

    lantern_signed_block_list_reset(&resp);
    lantern_signed_block_list_reset(&decoded);
    free(encoded);
}

static void test_gossip_helpers(void) {
    char topic[128];
    uint8_t parsed_digest[4];
    char digest_hex[LANTERN_GOSSIP_FORK_DIGEST_HEX_LEN + 1u];
    static const uint8_t fork_digest[4] = {0x12, 0x34, 0x56, 0x78};
    check_zero(lantern_gossip_fork_digest_to_hex(fork_digest, digest_hex), "fork digest hex");
    CHECK(strcmp(digest_hex, "12345678") == 0);
    check_zero(lantern_gossip_fork_digest_from_hex("12345678", parsed_digest), "fork digest parse");
    CHECK(memcmp(parsed_digest, fork_digest, sizeof(parsed_digest)) == 0);
    CHECK(lantern_gossip_fork_digest_from_hex("0x12345678", parsed_digest) != 0);
    CHECK(lantern_gossip_fork_digest_from_hex("1234567", parsed_digest) != 0);
    CHECK(lantern_gossip_fork_digest_from_hex("1234567G", parsed_digest) != 0);

    check_zero(lantern_gossip_topic_format(LANTERN_GOSSIP_TOPIC_BLOCK, "devnet0", topic, sizeof(topic)), "topic format");
    CHECK(strcmp(topic, "/leanconsensus/devnet0/block/ssz_snappy") == 0);

    struct lantern_gossip_parsed_topic parsed_topic;
    check_zero(lantern_gossip_topic_parse(topic, &parsed_topic), "topic parse block");
    CHECK(parsed_topic.kind == LANTERN_GOSSIP_TOPIC_BLOCK);
    CHECK(strcmp(parsed_topic.network_name, "devnet0") == 0);

    check_zero(
        lantern_gossip_topic_format_subnet(
            LANTERN_GOSSIP_TOPIC_VOTE_SUBNET,
            "devnet0",
            7u,
            topic,
            sizeof(topic)),
        "topic format subnet");
    CHECK(strcmp(topic, "/leanconsensus/devnet0/attestation_7/ssz_snappy") == 0);
    check_zero(lantern_gossip_topic_parse(topic, &parsed_topic), "topic parse subnet");
    CHECK(parsed_topic.kind == LANTERN_GOSSIP_TOPIC_VOTE_SUBNET);
    CHECK(strcmp(parsed_topic.network_name, "devnet0") == 0);
    CHECK(parsed_topic.subnet_id == 7u);

    check_zero(lantern_gossip_topic_parse("/leanconsensus/0x12345678/block/ssz_snappy", &parsed_topic), "topic parse 0x");
    CHECK(strcmp(parsed_topic.network_name, "0x12345678") == 0);
    check_zero(lantern_gossip_topic_parse("/leanconsensus/12345678/block/ssz_snappy", &parsed_topic), "topic parse hex");
    CHECK(strcmp(parsed_topic.network_name, "12345678") == 0);
    check_zero(lantern_gossip_topic_parse("/leanconsensus/1234567/block/ssz_snappy", &parsed_topic), "topic parse short");
    CHECK(strcmp(parsed_topic.network_name, "1234567") == 0);
    check_zero(lantern_gossip_topic_parse("/leanconsensus/not-hex/block/ssz_snappy", &parsed_topic), "topic parse opaque");
    CHECK(strcmp(parsed_topic.network_name, "not-hex") == 0);
    CHECK(lantern_gossip_topic_parse("/leanconsensus//block/ssz_snappy", &parsed_topic) != 0);

    uint8_t payload[64];
    fill_bytes(payload, sizeof(payload), 0x5A);
    size_t max_compressed = 0;
    CHECK(lantern_snappy_max_compressed_size_raw(sizeof(payload), &max_compressed) == LANTERN_SNAPPY_OK);
    uint8_t *compressed = malloc(max_compressed);
    CHECK(compressed);
    size_t compressed_len = 0;
    CHECK(
        lantern_snappy_compress_raw(
            payload,
            sizeof(payload),
            compressed,
            max_compressed,
            &compressed_len)
        == LANTERN_SNAPPY_OK);

    LanternGossipMessageId valid_id;
    uint8_t scratch[sizeof(payload)];
    size_t required = 0;
    check_zero(lantern_gossip_compute_message_id(&valid_id,
                                                 (const uint8_t *)topic,
                                                 strlen(topic),
                                                 compressed,
                                                 compressed_len,
                                                 scratch,
                                                 sizeof(scratch),
                                                 &required),
               "message id valid");
    CHECK(required == 0);

    LanternGossipMessageId invalid_id;
    required = 0;
    check_zero(lantern_gossip_compute_message_id(&invalid_id,
                                                 (const uint8_t *)topic,
                                                 strlen(topic),
                                                 compressed,
                                                 compressed_len,
                                                 scratch,
                                                 8,
                                                 &required),
               "message id insufficient scratch");
    CHECK(required == sizeof(payload));
    CHECK(memcmp(valid_id.bytes, invalid_id.bytes, LANTERN_GOSSIP_MESSAGE_ID_SIZE) != 0);

    LanternGossipMessageId raw_id;
    const uint8_t raw_payload[] = {0x01, 0x02, 0x03};
    check_zero(lantern_gossip_compute_message_id(&raw_id,
                                                 (const uint8_t *)topic,
                                                 strlen(topic),
                                                 raw_payload,
                                                 sizeof(raw_payload),
                                                 NULL,
                                                 0,
                                                 &required),
               "message id raw payload");
    CHECK(required == 0);

    free(compressed);
}

static void test_gossip_signed_vote_payload(void) {
    LanternSignedVote vote = build_signed_vote(3, 12, 0x44);

    uint8_t raw_buf[8192];
    size_t raw_written = 0;
    CHECK(lantern_ssz_encode_signed_vote(&vote, raw_buf, sizeof(raw_buf), &raw_written) == SSZ_SUCCESS);

    size_t max_compressed = 0;
    CHECK(lantern_snappy_max_compressed_size(raw_written, &max_compressed) == LANTERN_SNAPPY_OK);
    uint8_t *compressed = malloc(max_compressed);
    CHECK(compressed);

    size_t compressed_len = 0;
    check_zero(
        lantern_gossip_encode_signed_vote_snappy(&vote, compressed, max_compressed, &compressed_len),
        "encode signed vote gossip");
    CHECK(compressed_len > 0);

    LanternSignedVote decoded = {0};
    check_zero(
        lantern_gossip_decode_signed_vote_snappy(&decoded, compressed, compressed_len),
        "decode signed vote gossip");
    CHECK(decoded.data.validator_id == vote.data.validator_id);
    CHECK(decoded.data.target.slot == vote.data.target.slot);

    uint8_t invalid_payload[] = {0x01, 0x02, 0x03};
    CHECK(lantern_gossip_decode_signed_vote_snappy(&decoded, invalid_payload, sizeof(invalid_payload)) != 0);

    free(compressed);
}

static void test_gossip_signed_block_payload(void) {
    LanternSignedBlock block;
    lantern_signed_block_init(&block);
    populate_block(&block, 5);

   size_t raw_upper = signed_block_min_capacity_for_test(&block);
   size_t max_compressed = 0;
    CHECK(lantern_snappy_max_compressed_size(raw_upper, &max_compressed) == LANTERN_SNAPPY_OK);
    uint8_t *compressed = malloc(max_compressed);
    CHECK(compressed);

    size_t compressed_len = 0;
    check_zero(
        lantern_gossip_encode_signed_block_snappy(&block, compressed, max_compressed, &compressed_len),
        "encode signed block gossip");
    CHECK(compressed_len > 0);

    LanternSignedBlock decoded;
    lantern_signed_block_init(&decoded);
    check_zero(
        lantern_gossip_decode_signed_block_snappy(&decoded, compressed, compressed_len, NULL, NULL),
        "decode signed block gossip");
    CHECK(decoded.block.slot == block.block.slot);
    CHECK(decoded.block.body.attestations.length == block.block.body.attestations.length);
    check_byte_list_equal(&decoded.proof, &block.proof);

    uint8_t invalid_payload[] = {0xFF};
    CHECK(lantern_gossip_decode_signed_block_snappy(&decoded, invalid_payload, sizeof(invalid_payload), NULL, NULL) != 0);

    lantern_signed_block_reset(&decoded);
    lantern_signed_block_reset(&block);
    free(compressed);
}

static void test_gossip_signed_block_accepts_future_attestation_slot(void) {
    LanternSignedBlock block;
    lantern_signed_block_init(&block);
    populate_block(&block, 7);

    CHECK(block.block.body.attestations.length > 0);
    LanternAggregatedAttestation *attestation = &block.block.body.attestations.data[0];
    attestation->data.slot = block.block.slot + 1u;
    attestation->data.head.slot = attestation->data.slot;
    attestation->data.target.slot = attestation->data.slot;
    attestation->data.source.slot = block.block.slot;

    size_t raw_upper = signed_block_min_capacity_for_test(&block);
    size_t max_compressed = 0;
    CHECK(lantern_snappy_max_compressed_size(raw_upper, &max_compressed) == LANTERN_SNAPPY_OK);
    uint8_t *compressed = malloc(max_compressed);
    CHECK(compressed);

    size_t compressed_len = 0;
    check_zero(
        lantern_gossip_encode_signed_block_snappy(&block, compressed, max_compressed, &compressed_len),
        "encode future-slot attestation block gossip");
    CHECK(compressed_len > 0);

    LanternSignedBlock decoded;
    lantern_signed_block_init(&decoded);
    check_zero(
        lantern_gossip_decode_signed_block_snappy(&decoded, compressed, compressed_len, NULL, NULL),
        "decode future-slot attestation block gossip");
    CHECK(decoded.block.slot == block.block.slot);
    CHECK(decoded.block.body.attestations.length == block.block.body.attestations.length);
    CHECK(decoded.block.body.attestations.data[0].data.slot == block.block.slot + 1u);
    CHECK(decoded.block.body.attestations.data[0].data.target.slot == block.block.slot + 1u);
    CHECK(decoded.block.body.attestations.data[0].data.source.slot == block.block.slot);

    lantern_signed_block_reset(&decoded);
    lantern_signed_block_reset(&block);
    free(compressed);
}

static void test_gossip_block_snappy_roundtrip_random(void) {
    const size_t iterations = 64;
    for (size_t i = 0; i < iterations; ++i) {
        LanternSignedBlock original;
        lantern_signed_block_init(&original);
        original.block.slot = 1 + rng_uniform(2047);
        original.block.proposer_index = rng_uniform(63);
        rng_fill_bytes(original.block.parent_root.bytes, LANTERN_ROOT_SIZE);
        rng_fill_bytes(original.block.state_root.bytes, LANTERN_ROOT_SIZE);

        size_t att_count = rng_uniform(4);
        for (size_t j = 0; j < att_count; ++j) {
            LanternSignedVote vote;
            memset(&vote, 0, sizeof(vote));
            vote.data.validator_id = rng_uniform(255);
            vote.data.slot = rng_uniform(original.block.slot);
            vote.data.source.slot = vote.data.slot > 0 ? rng_uniform(vote.data.slot) : 0;
            if (vote.data.source.slot > vote.data.slot) {
                vote.data.source.slot = vote.data.slot;
            }
            vote.data.target.slot = vote.data.slot;
            vote.data.head.slot = vote.data.slot;
            rng_fill_bytes(vote.data.head.root.bytes, LANTERN_ROOT_SIZE);
            rng_fill_bytes(vote.data.target.root.bytes, LANTERN_ROOT_SIZE);
            rng_fill_bytes(vote.data.source.root.bytes, LANTERN_ROOT_SIZE);
            rng_fill_bytes(vote.signature.bytes, LANTERN_SIGNATURE_SIZE);
            LanternAggregatedAttestation agg;
            build_aggregated_attestation_from_vote(&vote.data, &agg);
            CHECK(lantern_aggregated_attestations_append(&original.block.body.attestations, &agg) == 0);
            lantern_aggregated_attestation_reset(&agg);
        }

        populate_random_signed_block_proof(&original.proof, 8u + rng_uniform(32));

        size_t raw_estimate = signed_block_min_capacity_for_test(&original);
        CHECK(raw_estimate > 0);
        size_t max_compressed = 0;
        CHECK(lantern_snappy_max_compressed_size(raw_estimate, &max_compressed) == LANTERN_SNAPPY_OK);
        uint8_t *compressed = malloc(max_compressed);
        CHECK(compressed != NULL);

        size_t written = 0;
        check_zero(
            lantern_gossip_encode_signed_block_snappy(&original, compressed, max_compressed, &written),
            "random block encode");
        CHECK(written > 0);

        LanternSignedBlock decoded;
        lantern_signed_block_init(&decoded);
        check_zero(
            lantern_gossip_decode_signed_block_snappy(&decoded, compressed, written, NULL, NULL),
            "random block decode");

        CHECK(decoded.block.slot == original.block.slot);
        CHECK(decoded.block.proposer_index == original.block.proposer_index);
        CHECK(memcmp(decoded.block.parent_root.bytes, original.block.parent_root.bytes, LANTERN_ROOT_SIZE) == 0);
        CHECK(memcmp(decoded.block.state_root.bytes, original.block.state_root.bytes, LANTERN_ROOT_SIZE) == 0);
        CHECK(decoded.block.body.attestations.length == original.block.body.attestations.length);
        for (size_t j = 0; j < decoded.block.body.attestations.length; ++j) {
            const LanternAggregatedAttestation *expected = &original.block.body.attestations.data[j];
            const LanternAggregatedAttestation *actual = &decoded.block.body.attestations.data[j];
            check_aggregated_attestation_equal(expected, actual);
        }
        check_byte_list_equal(&decoded.proof, &original.proof);

        free(compressed);
        lantern_signed_block_reset(&original);
        lantern_signed_block_reset(&decoded);
    }
}

static void test_gossipsub_service_loopback(void) {
    struct lantern_gossipsub_service service;
    lantern_gossipsub_service_init(&service);
    snprintf(service.block_topic, sizeof(service.block_topic), "/leanconsensus/devnet0/block/ssz_snappy");
    lantern_gossipsub_service_set_loopback_only(&service, 1);

    LanternSignedBlock block;
    lantern_signed_block_init(&block);
    populate_block(&block, 9);

    struct block_hook_ctx ctx = {
        .expected = &block,
        .expected_topic = service.block_topic,
        .called = 0,
    };
    lantern_gossipsub_service_set_publish_hook(&service, block_publish_hook, &ctx);

    CHECK(lantern_gossipsub_service_publish_block(&service, &block) == 0);
    CHECK(ctx.called == 1);

    lantern_signed_block_reset(&block);
    lantern_gossipsub_service_reset(&service);
}

static void test_gossipsub_service_remembers_extra_attestation_subnets(void) {
    struct lantern_gossipsub_service service;
    lantern_gossipsub_service_init(&service);
    snprintf(service.topic_network_name, sizeof(service.topic_network_name), "devnet0");
    service.attestation_subnet_id = 0u;

    CHECK(lantern_gossipsub_service_subscribe_attestation_subnet(&service, 1u) == 0);
    CHECK(service.extra_vote_subnet_topic_count == 1u);
    CHECK(strcmp(
        service.extra_vote_subnet_topics[0],
        "/leanconsensus/devnet0/attestation_1/ssz_snappy") == 0);

    CHECK(lantern_gossipsub_service_subscribe_attestation_subnet(&service, 1u) == 0);
    CHECK(service.extra_vote_subnet_topic_count == 1u);

    CHECK(lantern_gossipsub_service_subscribe_attestation_subnet(&service, 0u) == 0);
    CHECK(strcmp(
        service.vote_subnet_topic,
        "/leanconsensus/devnet0/attestation_0/ssz_snappy") == 0);
    CHECK(service.extra_vote_subnet_topic_count == 1u);

    lantern_gossipsub_service_reset(&service);
}

static void test_client_publish_block_loopback(void) {
    struct lantern_client client;
    memset(&client, 0, sizeof(client));
    lantern_gossipsub_service_init(&client.gossip);
    snprintf(client.gossip.block_topic, sizeof(client.gossip.block_topic), "/leanconsensus/devnet0/block/ssz_snappy");
    lantern_gossipsub_service_set_loopback_only(&client.gossip, 1);

    LanternSignedBlock block;
    lantern_signed_block_init(&block);
    populate_block(&block, 4);

    struct block_hook_ctx ctx = {
        .expected = &block,
        .expected_topic = client.gossip.block_topic,
        .called = 0,
    };
    lantern_gossipsub_service_set_publish_hook(&client.gossip, block_publish_hook, &ctx);

    client.gossip_running = true;
    client.node_id = "loopback";

    CHECK(lantern_client_publish_block(&client, &block) == 0);
    CHECK(ctx.called == 1);

    lantern_signed_block_reset(&block);
    lantern_gossipsub_service_reset(&client.gossip);
}

int main(void) {
    test_status_message();
    test_status_decode_rejects_truncated_payloads();
    test_status_reqresp_snappy_fixture();
    test_reqresp_response_code_mapping();
    test_blocks_by_root_per_chunk_framing();
    test_blocks_by_root_request();
    test_signed_block_list();
    test_gossip_signed_vote_payload();
    test_gossip_signed_block_payload();
    test_gossip_signed_block_accepts_future_attestation_slot();
    test_gossip_block_snappy_roundtrip_random();
    if (consensus_fixture_exists(
            "fork_choice/devnet/fc/test_fork_choice_reorgs/test_reorg_on_newly_justified_slot.json")
        && consensus_fixture_exists(
            "state_transition/devnet/state_transition/test_block_processing/test_linear_chain_multiple_blocks.json")) {
        test_replay_devnet_block_payloads();
    } else {
        puts("skipping test_replay_devnet_block_payloads (consensus fixtures not present)");
    }
    test_gossipsub_service_loopback();
    test_gossipsub_service_remembers_extra_attestation_subnets();
    test_client_publish_block_loopback();
    test_gossip_helpers();
    puts("lantern_networking_messages_test OK");
    return 0;
}
