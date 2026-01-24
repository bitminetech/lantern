#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>

#include "lantern/consensus/containers.h"
#include "lantern/consensus/hash.h"
#include "lantern/consensus/ssz.h"
#include "lantern/core/client.h"
#include "lantern/networking/gossip.h"
#include "lantern/networking/gossipsub_service.h"
#include "lantern/networking/messages.h"
#include "lantern/networking/gossip_payloads.h"
#include "lantern/networking/reqresp_service.h"
#include "lantern/encoding/snappy.h"
#include "lantern/support/strings.h"
#include "libp2p/errors.h"
#include "libp2p/stream_internal.h"
#include "multiformats/unsigned_varint/unsigned_varint.h"
#include "tests/support/fixture_loader.h"
#include "ssz_constants.h"

#ifndef LANTERN_TEST_FIXTURE_DIR
#error "LANTERN_TEST_FIXTURE_DIR must be defined"
#endif

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

static uint8_t *read_fixture_bytes(const char *relative_path, size_t *out_len) {
    CHECK(relative_path != NULL);
    char path[PATH_MAX];
    int written = snprintf(path, sizeof(path), "%s/%s", LANTERN_TEST_FIXTURE_DIR, relative_path);
    CHECK(written > 0);
    CHECK((size_t)written < sizeof(path));

    FILE *fp = fopen(path, "rb");
    CHECK(fp != NULL);
    CHECK(fseek(fp, 0, SEEK_END) == 0);
    long length = ftell(fp);
    CHECK(length >= 0);
    CHECK(fseek(fp, 0, SEEK_SET) == 0);

    uint8_t *buffer = (uint8_t *)malloc((size_t)length);
    CHECK(buffer != NULL);
    size_t read = fread(buffer, 1, (size_t)length, fp);
    CHECK(read == (size_t)length);
    fclose(fp);

    if (out_len) {
        *out_len = (size_t)length;
    }
    return buffer;
}

struct mock_stream_ctx {
    uint8_t *data;
    size_t length;
    size_t position;
};

static ssize_t mock_stream_read(void *io_ctx, void *buf, size_t len) {
    struct mock_stream_ctx *ctx = (struct mock_stream_ctx *)io_ctx;
    if (!ctx || !buf || len == 0) {
        return LIBP2P_ERR_NULL_PTR;
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
    return LIBP2P_ERR_UNSUPPORTED;
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

static void check_vote_equal(const LanternVote *expected, const LanternVote *actual) {
    CHECK(expected != NULL);
    CHECK(actual != NULL);
    CHECK(expected->validator_id == actual->validator_id);
    CHECK(expected->slot == actual->slot);
    check_checkpoint_equal(&expected->head, &actual->head);
    check_checkpoint_equal(&expected->target, &actual->target);
    check_checkpoint_equal(&expected->source, &actual->source);
}

static void check_signed_vote_equal(const LanternSignedVote *expected, const LanternSignedVote *actual) {
    CHECK(expected != NULL);
    CHECK(actual != NULL);
    check_vote_equal(&expected->data, &actual->data);
    CHECK(memcmp(expected->signature.bytes, actual->signature.bytes, LANTERN_SIGNATURE_SIZE) == 0);
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

static void check_signature_proof_equal(
    const LanternAggregatedSignatureProof *expected,
    const LanternAggregatedSignatureProof *actual) {
    CHECK(expected != NULL);
    CHECK(actual != NULL);
    check_bitlist_equal(&expected->participants, &actual->participants);
    CHECK(expected->proof_data.length == actual->proof_data.length);
    if (expected->proof_data.length == 0) {
        return;
    }
    CHECK(expected->proof_data.data != NULL);
    CHECK(actual->proof_data.data != NULL);
    CHECK(memcmp(expected->proof_data.data, actual->proof_data.data, expected->proof_data.length) == 0);
}

static void expect_vote_view(
    const LanternVote *vote,
    uint64_t validator_id,
    uint64_t slot,
    uint64_t head_slot,
    uint8_t head_seed,
    uint64_t target_slot,
    uint8_t target_seed,
    uint64_t source_slot,
    uint8_t source_seed) {
    CHECK(vote != NULL);
    CHECK(vote->validator_id == validator_id);
    CHECK(vote->slot == slot);
    expect_checkpoint_seed(&vote->head, head_slot, head_seed);
    expect_checkpoint_seed(&vote->target, target_slot, target_seed);
    expect_checkpoint_seed(&vote->source, source_slot, source_seed);
}

static void expect_aggregated_attestation_view(
    const LanternAggregatedAttestation *attestation,
    uint64_t validator_id,
    uint64_t slot,
    uint64_t head_slot,
    uint8_t head_seed,
    uint64_t target_slot,
    uint8_t target_seed,
    uint64_t source_slot,
    uint8_t source_seed) {
    CHECK(attestation != NULL);
    CHECK(attestation->data.slot == slot);
    expect_checkpoint_seed(&attestation->data.head, head_slot, head_seed);
    expect_checkpoint_seed(&attestation->data.target, target_slot, target_seed);
    expect_checkpoint_seed(&attestation->data.source, source_slot, source_seed);
    CHECK(attestation->aggregation_bits.bit_length == validator_id + 1u);
    CHECK(lantern_bitlist_get(&attestation->aggregation_bits, (size_t)validator_id));
}

static void expect_signature_proof_seed(
    const LanternAggregatedSignatureProof *proof,
    uint64_t validator_id,
    uint8_t seed,
    size_t length) {
    CHECK(proof != NULL);
    CHECK(proof->participants.bit_length == validator_id + 1u);
    CHECK(lantern_bitlist_get(&proof->participants, (size_t)validator_id));
    CHECK(proof->proof_data.length == length);
    if (length == 0) {
        return;
    }
    CHECK(proof->proof_data.data != NULL);
    for (size_t i = 0; i < length; ++i) {
        CHECK(proof->proof_data.data[i] == (uint8_t)(seed + i));
    }
}

static void check_block_signatures_equal(
    const LanternBlockSignatures *expected,
    const LanternBlockSignatures *actual) {
    CHECK(expected != NULL);
    CHECK(actual != NULL);
    CHECK(expected->attestation_signatures.length == actual->attestation_signatures.length);
    if (expected->attestation_signatures.length > 0) {
        CHECK(expected->attestation_signatures.data != NULL);
        CHECK(actual->attestation_signatures.data != NULL);
        for (size_t i = 0; i < expected->attestation_signatures.length; ++i) {
            check_signature_proof_equal(
                &expected->attestation_signatures.data[i],
                &actual->attestation_signatures.data[i]);
        }
    }
    CHECK(memcmp(
              expected->proposer_signature.bytes,
              actual->proposer_signature.bytes,
              LANTERN_SIGNATURE_SIZE)
          == 0);
}

static void check_signed_block_equal(
    const LanternSignedBlock *expected,
    const LanternSignedBlock *actual) {
    CHECK(expected != NULL);
    CHECK(actual != NULL);
    CHECK(actual->message.block.slot == expected->message.block.slot);
    CHECK(actual->message.block.proposer_index == expected->message.block.proposer_index);
    CHECK(memcmp(
        actual->message.block.parent_root.bytes,
        expected->message.block.parent_root.bytes,
        LANTERN_ROOT_SIZE)
        == 0);
    CHECK(memcmp(
        actual->message.block.state_root.bytes,
        expected->message.block.state_root.bytes,
        LANTERN_ROOT_SIZE)
        == 0);
    CHECK(actual->message.block.body.attestations.length == expected->message.block.body.attestations.length);
    CHECK(
        (actual->message.block.body.attestations.length == 0)
        || (actual->message.block.body.attestations.data != NULL && expected->message.block.body.attestations.data != NULL));
    for (size_t i = 0; i < actual->message.block.body.attestations.length; ++i) {
        check_aggregated_attestation_equal(
            &expected->message.block.body.attestations.data[i],
            &actual->message.block.body.attestations.data[i]);
    }
    check_vote_equal(&expected->message.proposer_attestation, &actual->message.proposer_attestation);
    check_block_signatures_equal(&expected->signatures, &actual->signatures);
}

static void expect_signed_vote_fixture(const LanternSignedVote *vote) {
    CHECK(vote != NULL);
    expect_vote_view(
        &vote->data,
        9,
        96,
        97,
        0x33,
        96,
        0x53,
        94,
        0x73);
}

static void expect_signed_block_fixture(const LanternSignedBlock *block) {
    CHECK(block != NULL);
    CHECK(block->message.block.slot == 72);
    CHECK(block->message.block.proposer_index == 5);
    expect_root_seed(&block->message.block.parent_root, 0x24);
    expect_root_seed(&block->message.block.state_root, 0x74);
    CHECK(block->message.block.body.attestations.length == 2);
    CHECK(block->message.block.body.attestations.data != NULL);
    expect_aggregated_attestation_view(
        &block->message.block.body.attestations.data[0],
        9,
        71,
        72,
        0x24,
        71,
        0x44,
        69,
        0x64);
    expect_aggregated_attestation_view(
        &block->message.block.body.attestations.data[1],
        10,
        70,
        71,
        0x29,
        70,
        0x49,
        68,
        0x69);
    expect_vote_view(
        &block->message.proposer_attestation,
        8,
        74,
        75,
        0xA4,
        74,
        0xC4,
        72,
        0xE4);
    CHECK(block->signatures.attestation_signatures.length == 2);
    CHECK(block->signatures.attestation_signatures.data != NULL);
    expect_signature_proof_seed(&block->signatures.attestation_signatures.data[0], 9, 0xC4, 8);
    expect_signature_proof_seed(&block->signatures.attestation_signatures.data[1], 10, 0xC7, 8);
}

static uint64_t le_bytes_to_u64(const uint8_t *src, size_t len) {
    if (!src) {
        return 0;
    }
    if (len > sizeof(uint64_t)) {
        len = sizeof(uint64_t);
    }
    uint64_t value = 0;
    for (size_t i = 0; i < len; ++i) {
        value |= ((uint64_t)src[i]) << (8u * i);
    }
    return value;
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

static void fill_proof_data(LanternAggregatedSignatureProof *proof, uint8_t seed, size_t length) {
    check_zero(lantern_byte_list_resize(&proof->proof_data, length), "proof data resize");
    if (length > 0 && proof->proof_data.data) {
        fill_bytes(proof->proof_data.data, length, seed);
    }
}

static void populate_block(LanternSignedBlock *signed_block, uint8_t seed) {
    lantern_signed_block_with_attestation_init(signed_block);
    signed_block->message.block.slot = 100 + seed;
    signed_block->message.block.proposer_index = 3 + seed;
    fill_bytes(signed_block->message.block.parent_root.bytes, LANTERN_ROOT_SIZE, (uint8_t)(0x10 + seed));
    fill_bytes(signed_block->message.block.state_root.bytes, LANTERN_ROOT_SIZE, (uint8_t)(0x20 + seed));
    LanternSignedVote vote = build_signed_vote(1 + seed, 50 + seed, (uint8_t)(0x30 + seed));
    LanternAggregatedAttestation agg;
    build_aggregated_attestation_from_vote(&vote.data, &agg);
    check_zero(
        lantern_aggregated_attestations_append(&signed_block->message.block.body.attestations, &agg),
        "attestation append");
    lantern_aggregated_attestation_reset(&agg);
    LanternSignedVote proposer_vote =
        build_signed_vote(2 + seed, signed_block->message.block.slot, (uint8_t)(0x35 + seed));
    signed_block->message.proposer_attestation = proposer_vote.data;
    size_t att_count = signed_block->message.block.body.attestations.length;
    check_zero(
        lantern_attestation_signatures_resize(&signed_block->signatures.attestation_signatures, att_count),
        "signature resize");
    for (size_t i = 0; i < att_count; ++i) {
        LanternAggregatedSignatureProof *proof = &signed_block->signatures.attestation_signatures.data[i];
        const LanternAggregatedAttestation *attestation = &signed_block->message.block.body.attestations.data[i];
        check_zero(
            lantern_bitlist_resize(&proof->participants, attestation->aggregation_bits.bit_length),
            "participants resize");
        size_t byte_len = (attestation->aggregation_bits.bit_length + 7u) / 8u;
        if (byte_len > 0) {
            memcpy(proof->participants.bytes, attestation->aggregation_bits.bytes, byte_len);
        }
        fill_proof_data(proof, (uint8_t)(0xC0 + seed), 8);
    }
    signed_block->signatures.proposer_signature = proposer_vote.signature;
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
    lantern_signed_block_with_attestation_init(&decoded);
    int rc = lantern_gossip_decode_signed_block_snappy(&decoded, payload, payload_len);
    if (rc != 0) {
        lantern_signed_block_with_attestation_reset(&decoded);
        return -1;
    }

    const LanternSignedBlock *expected = ctx->expected;
    CHECK(expected != NULL);
    CHECK(decoded.message.block.slot == expected->message.block.slot);
    CHECK(decoded.message.block.proposer_index == expected->message.block.proposer_index);
    CHECK(decoded.message.block.body.attestations.length == expected->message.block.body.attestations.length);
    check_block_signatures_equal(&decoded.signatures, &expected->signatures);
    lantern_signed_block_with_attestation_reset(&decoded);
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
    int written = snprintf(path, sizeof(path), "%s/%s", LANTERN_TEST_FIXTURE_DIR, spec->fixture);
    if (written <= 0 || (size_t)written >= sizeof(path)) {
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

static int parse_hex_bytes(const char *hex, uint8_t *out, size_t expected_len) {
    if (!hex || !out) {
        return -1;
    }
    if (hex[0] == '0' && (hex[1] == 'x' || hex[1] == 'X')) {
        hex += 2;
    }
    size_t hex_len = strlen(hex);
    if (hex_len != expected_len * 2u) {
        return -1;
    }
    for (size_t i = 0; i < expected_len; ++i) {
        char buf[3];
        buf[0] = hex[(i * 2u)];
        buf[1] = hex[(i * 2u) + 1u];
        buf[2] = '\0';
        char *end = NULL;
        unsigned long value = strtoul(buf, &end, 16);
        if (!end || *end != '\0') {
            return -1;
        }
        out[i] = (uint8_t)value;
    }
    return 0;
}

static void test_replay_devnet_block_payloads(void) {
    struct block_fixture_case cases[] = {
        {
            .fixture =
                "consensus/fork_choice/devnet/fc/test_fork_choice_reorgs/test_reorg_on_newly_justified_slot.json",
            .kind = BLOCK_FIXTURE_FORK_CHOICE_STEP,
            .index = 5,
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
        lantern_signed_block_with_attestation_init(&original);
        CHECK(load_signed_block_fixture(&cases[i], &original) == 0);
        size_t sig_count = original.message.block.body.attestations.length;
        CHECK(lantern_attestation_signatures_resize(&original.signatures.attestation_signatures, sig_count) == 0);
        for (size_t sig_idx = 0; sig_idx < sig_count; ++sig_idx) {
            LanternAggregatedSignatureProof *proof = &original.signatures.attestation_signatures.data[sig_idx];
            const LanternAggregatedAttestation *att = &original.message.block.body.attestations.data[sig_idx];
            CHECK(lantern_bitlist_resize(&proof->participants, att->aggregation_bits.bit_length) == 0);
            size_t byte_len = (att->aggregation_bits.bit_length + 7u) / 8u;
            if (byte_len > 0) {
                memcpy(proof->participants.bytes, att->aggregation_bits.bytes, byte_len);
            }
            fill_proof_data(proof, (uint8_t)(0x80 + sig_idx + i), 8);
        }
        fill_signature(&original.signatures.proposer_signature, (uint8_t)(0x80 + sig_count + i));

        LanternRoot original_block_root;
        memset(&original_block_root, 0, sizeof(original_block_root));
        CHECK(lantern_hash_tree_root_block(&original.message.block, &original_block_root) == 0);

        size_t ssz_capacity = signed_block_min_capacity_for_test(&original);
        CHECK(ssz_capacity > 0);
        uint8_t *ssz_encoded = (uint8_t *)malloc(ssz_capacity);
        CHECK(ssz_encoded != NULL);
        size_t ssz_written = ssz_capacity;
        CHECK(lantern_ssz_encode_signed_block(&original, ssz_encoded, ssz_capacity, &ssz_written) == 0);

        size_t max_compressed = 0;
        CHECK(lantern_snappy_max_compressed_size(ssz_written, &max_compressed) == LANTERN_SNAPPY_OK);
        uint8_t *compressed = (uint8_t *)malloc(max_compressed);
        CHECK(compressed != NULL);
        size_t compressed_len = max_compressed;
        CHECK(lantern_gossip_encode_signed_block_snappy(&original, compressed, max_compressed, &compressed_len) == 0);

        LanternSignedBlock decoded;
        lantern_signed_block_with_attestation_init(&decoded);
        CHECK(lantern_gossip_decode_signed_block_snappy(&decoded, compressed, compressed_len) == 0);

        CHECK(decoded.message.block.slot == original.message.block.slot);
        CHECK(decoded.message.block.proposer_index == original.message.block.proposer_index);
        CHECK(memcmp(decoded.message.block.parent_root.bytes, original.message.block.parent_root.bytes, LANTERN_ROOT_SIZE) == 0);
        CHECK(memcmp(decoded.message.block.state_root.bytes, original.message.block.state_root.bytes, LANTERN_ROOT_SIZE) == 0);

        check_block_signatures_equal(&decoded.signatures, &original.signatures);
        CHECK(decoded.message.block.body.attestations.length == original.message.block.body.attestations.length);
        if (decoded.message.block.body.attestations.length > 0) {
            CHECK(decoded.message.block.body.attestations.data != NULL);
            CHECK(original.message.block.body.attestations.data != NULL);
        }
        for (size_t att_idx = 0; att_idx < decoded.message.block.body.attestations.length; ++att_idx) {
            const LanternAggregatedAttestation *expected_att = &original.message.block.body.attestations.data[att_idx];
            const LanternAggregatedAttestation *decoded_att = &decoded.message.block.body.attestations.data[att_idx];
            check_aggregated_attestation_equal(expected_att, decoded_att);
        }

        LanternRoot decoded_block_root;
        memset(&decoded_block_root, 0, sizeof(decoded_block_root));
        CHECK(lantern_hash_tree_root_block(&decoded.message.block, &decoded_block_root) == 0);
        CHECK(memcmp(decoded_block_root.bytes, original_block_root.bytes, LANTERN_ROOT_SIZE) == 0);

        uint8_t *roundtrip = (uint8_t *)malloc(ssz_written);
        CHECK(roundtrip != NULL);
        size_t roundtrip_written = ssz_written;
        CHECK(
            lantern_snappy_decompress(
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
        lantern_signed_block_with_attestation_reset(&original);
        lantern_signed_block_with_attestation_reset(&decoded);
    }
}

static void test_status_fixture_roundtrip(void) {
    size_t fixture_len = 0;
    uint8_t *fixture = read_fixture_bytes("networking/status_leanspec.ssz", &fixture_len);
    size_t snappy_fixture_len = 0;
    uint8_t *snappy_fixture = read_fixture_bytes("networking/status_leanspec.snappy", &snappy_fixture_len);

    LanternStatusMessage decoded = {0};
    check_zero(lantern_network_status_decode(&decoded, fixture, fixture_len), "status fixture decode");
    expect_checkpoint_seed(&decoded.finalized, 42, 0x11);
    expect_checkpoint_seed(&decoded.head, 96, 0x41);

    uint8_t encoded[128];
    size_t written = 0;
    check_zero(
        lantern_network_status_encode(&decoded, encoded, sizeof(encoded), &written),
        "status fixture encode");
    CHECK(written == fixture_len);
    CHECK(memcmp(encoded, fixture, fixture_len) == 0);

    size_t max_compressed = 0;
    CHECK(lantern_snappy_max_compressed_size(fixture_len, &max_compressed) == LANTERN_SNAPPY_OK);
    uint8_t *compressed = (uint8_t *)malloc(max_compressed);
    CHECK(compressed != NULL);
    size_t compressed_len = 0;
    CHECK(
        lantern_snappy_compress(
            fixture,
            fixture_len,
            compressed,
            max_compressed,
            &compressed_len)
        == LANTERN_SNAPPY_OK);

    LanternStatusMessage snappy_decoded = {0};
    check_zero(
        lantern_network_status_decode_snappy(&snappy_decoded, compressed, compressed_len),
        "status fixture decode snappy");
    expect_checkpoint_seed(&snappy_decoded.finalized, 42, 0x11);
    expect_checkpoint_seed(&snappy_decoded.head, 96, 0x41);

    LanternStatusMessage leanspec_snappy = {0};
    check_zero(
        lantern_network_status_decode_snappy(&leanspec_snappy, snappy_fixture, snappy_fixture_len),
        "status fixture decode snappy fixture");
    expect_checkpoint_seed(&leanspec_snappy.finalized, 42, 0x11);
    expect_checkpoint_seed(&leanspec_snappy.head, 96, 0x41);

    uint8_t *snappy_roundtrip = (uint8_t *)malloc(fixture_len);
    CHECK(snappy_roundtrip != NULL);
    size_t snappy_roundtrip_written = fixture_len;
    CHECK(
        lantern_snappy_decompress(
            snappy_fixture,
            snappy_fixture_len,
            snappy_roundtrip,
            fixture_len,
            &snappy_roundtrip_written)
        == LANTERN_SNAPPY_OK);
    CHECK(snappy_roundtrip_written == fixture_len);
    CHECK(memcmp(snappy_roundtrip, fixture, fixture_len) == 0);

    free(snappy_roundtrip);
    free(compressed);
    free(snappy_fixture);
    free(fixture);
}

static void test_blocks_by_root_request_fixture(void) {
    size_t fixture_len = 0;
    uint8_t *fixture = read_fixture_bytes("networking/blocks_by_root_request_leanspec.ssz", &fixture_len);

    LanternBlocksByRootRequest decoded;
    lantern_blocks_by_root_request_init(&decoded);
    check_zero(
        lantern_network_blocks_by_root_request_decode(&decoded, fixture, fixture_len),
        "request fixture decode");
    CHECK(decoded.roots.length == 3);
    expect_root_seed(&decoded.roots.items[0], 0x21);
    expect_root_seed(&decoded.roots.items[1], 0x52);
    expect_root_seed(&decoded.roots.items[2], 0x83);

    uint8_t encoded[128];
    size_t written = 0;
    check_zero(
        lantern_network_blocks_by_root_request_encode(&decoded, encoded, sizeof(encoded), &written),
        "request fixture encode");
    CHECK(written == fixture_len);
    CHECK(memcmp(encoded, fixture, fixture_len) == 0);

    size_t max_compressed = 0;
    CHECK(lantern_snappy_max_compressed_size(fixture_len, &max_compressed) == LANTERN_SNAPPY_OK);
    uint8_t *compressed = (uint8_t *)malloc(max_compressed);
    CHECK(compressed != NULL);
    size_t compressed_len = 0;
    CHECK(
        lantern_snappy_compress(
            fixture,
            fixture_len,
            compressed,
            max_compressed,
            &compressed_len)
        == LANTERN_SNAPPY_OK);

    LanternBlocksByRootRequest snappy_decoded;
    lantern_blocks_by_root_request_init(&snappy_decoded);
    check_zero(
        lantern_network_blocks_by_root_request_decode_snappy(&snappy_decoded, compressed, compressed_len),
        "request fixture decode snappy");
    CHECK(snappy_decoded.roots.length == decoded.roots.length);
    expect_root_seed(&snappy_decoded.roots.items[0], 0x21);
    expect_root_seed(&snappy_decoded.roots.items[1], 0x52);
    expect_root_seed(&snappy_decoded.roots.items[2], 0x83);

    free(compressed);
    free(fixture);
    lantern_blocks_by_root_request_reset(&decoded);
    lantern_blocks_by_root_request_reset(&snappy_decoded);
}

/* Helper to build a block matching the fixture values from Python leanSpec. */
static void build_fixture_block(
    LanternSignedBlock *out,
    uint8_t seed,
    uint64_t base_slot,
    uint64_t proposer_index,
    size_t attestation_count) {
    lantern_signed_block_with_attestation_init(out);
    out->message.block.slot = base_slot;
    out->message.block.proposer_index = proposer_index;
    fill_bytes(out->message.block.parent_root.bytes, LANTERN_ROOT_SIZE, seed);
    fill_bytes(out->message.block.state_root.bytes, LANTERN_ROOT_SIZE, (uint8_t)(seed + 0x50));

    /* Build attestations matching the Python fixture format */
    for (size_t i = 0; i < attestation_count; ++i) {
        LanternAggregatedAttestation agg;
        lantern_aggregated_attestation_init(&agg);
        uint8_t att_seed = (uint8_t)(seed + i * 5);
        uint64_t validator_id = (proposer_index + i + seed) % 16;
        uint64_t att_slot = base_slot + i + 1;
        agg.data.slot = att_slot;
        agg.data.head.slot = att_slot + 1;
        fill_bytes(agg.data.head.root.bytes, LANTERN_ROOT_SIZE, att_seed);
        agg.data.target.slot = att_slot + 2;
        fill_bytes(agg.data.target.root.bytes, LANTERN_ROOT_SIZE, (uint8_t)(att_seed + 0x20));
        agg.data.source.slot = att_slot;
        fill_bytes(agg.data.source.root.bytes, LANTERN_ROOT_SIZE, (uint8_t)(att_seed + 0x40));
        check_zero(lantern_bitlist_resize(&agg.aggregation_bits, (size_t)(validator_id + 1)), "agg bits resize");
        check_zero(lantern_bitlist_set(&agg.aggregation_bits, (size_t)validator_id, true), "agg bits set");
        check_zero(lantern_aggregated_attestations_append(&out->message.block.body.attestations, &agg), "agg append");
        lantern_aggregated_attestation_reset(&agg);
    }

    /* Proposer attestation */
    uint8_t prop_seed = (uint8_t)(seed + 0x80);
    uint64_t prop_validator = (proposer_index + 3) % 16;
    uint64_t prop_slot = base_slot + attestation_count + 4;
    out->message.proposer_attestation.validator_id = prop_validator;
    out->message.proposer_attestation.slot = prop_slot;
    out->message.proposer_attestation.head.slot = prop_slot + 1;
    fill_bytes(out->message.proposer_attestation.head.root.bytes, LANTERN_ROOT_SIZE, prop_seed);
    out->message.proposer_attestation.target.slot = prop_slot + 2;
    fill_bytes(out->message.proposer_attestation.target.root.bytes, LANTERN_ROOT_SIZE, (uint8_t)(prop_seed + 0x20));
    out->message.proposer_attestation.source.slot = prop_slot;
    fill_bytes(out->message.proposer_attestation.source.root.bytes, LANTERN_ROOT_SIZE, (uint8_t)(prop_seed + 0x40));

    /* Signatures */
    size_t att_count = out->message.block.body.attestations.length;
    check_zero(lantern_attestation_signatures_resize(&out->signatures.attestation_signatures, att_count), "sig resize");
    for (size_t i = 0; i < att_count; ++i) {
        LanternAggregatedSignatureProof *proof = &out->signatures.attestation_signatures.data[i];
        const LanternAggregatedAttestation *att = &out->message.block.body.attestations.data[i];
        check_zero(lantern_bitlist_resize(&proof->participants, att->aggregation_bits.bit_length), "part resize");
        size_t byte_len = (att->aggregation_bits.bit_length + 7u) / 8u;
        if (byte_len > 0) {
            memcpy(proof->participants.bytes, att->aggregation_bits.bytes, byte_len);
        }
        uint8_t proof_seed = (uint8_t)(seed + 0xA0 + i * 3);
        check_zero(lantern_byte_list_resize(&proof->proof_data, 8), "proof resize");
        fill_bytes(proof->proof_data.data, 8, proof_seed);
    }
    fill_signature(&out->signatures.proposer_signature, (uint8_t)(seed + 0xA0 + att_count * 3));
}

static void test_blocks_by_root_response_fixture(void) {
    /* Build the response using C encoding (fixed-length signatures) */
    LanternBlocksByRootResponse resp;
    lantern_blocks_by_root_response_init(&resp);
    check_zero(lantern_blocks_by_root_response_resize(&resp, 2), "fixture response resize");
    build_fixture_block(&resp.blocks[0], 0x10, 12, 1, 1);
    build_fixture_block(&resp.blocks[1], 0x30, 18, 3, 2);

    /* Encode using C encoder */
    size_t encoded_capacity = 1u << 20;
    uint8_t *encoded = (uint8_t *)malloc(encoded_capacity);
    CHECK(encoded != NULL);
    size_t written = 0;
    check_zero(
        lantern_network_blocks_by_root_response_encode(&resp, encoded, encoded_capacity, &written),
        "fixture response encode");

    /* Decode back and verify */
    LanternBlocksByRootResponse decoded;
    lantern_blocks_by_root_response_init(&decoded);
    check_zero(
        lantern_network_blocks_by_root_response_decode(&decoded, encoded, written),
        "response fixture decode");
    CHECK(decoded.length == 2);

    const LanternSignedBlock *block0 = &decoded.blocks[0];
    CHECK(block0->message.block.slot == 12);
    CHECK(block0->message.block.proposer_index == 1);
    expect_root_seed(&block0->message.block.parent_root, 0x10);
    expect_root_seed(&block0->message.block.state_root, 0x60);
    CHECK(block0->message.block.body.attestations.length == 1);
    const LanternAggregatedAttestation *block0_att0 = &block0->message.block.body.attestations.data[0];
    expect_aggregated_attestation_view(block0_att0, 1, 13, 14, 0x10, 15, 0x30, 13, 0x50);
    const LanternVote *block0_prop = &block0->message.proposer_attestation;
    CHECK(block0_prop->validator_id == 4);
    CHECK(block0_prop->slot == 17);
    expect_checkpoint_seed(&block0_prop->head, 18, 0x90);
    expect_checkpoint_seed(&block0_prop->target, 19, 0xB0);
    expect_checkpoint_seed(&block0_prop->source, 17, 0xD0);
    CHECK(block0->signatures.attestation_signatures.length == 1);
    CHECK(block0->signatures.attestation_signatures.length == 1);
    expect_signature_proof_seed(&block0->signatures.attestation_signatures.data[0], 1, 0xB0, 8);

    const LanternSignedBlock *block1 = &decoded.blocks[1];
    CHECK(block1->message.block.slot == 18);
    CHECK(block1->message.block.proposer_index == 3);
    expect_root_seed(&block1->message.block.parent_root, 0x30);
    expect_root_seed(&block1->message.block.state_root, 0x80);
    CHECK(block1->message.block.body.attestations.length == 2);
    const LanternVote *block1_prop = &block1->message.proposer_attestation;
    CHECK(block1_prop->validator_id == 6);
    CHECK(block1_prop->slot == 24);
    CHECK(block1->signatures.attestation_signatures.length == 2);

    /* Test snappy roundtrip */
    size_t max_compressed = 0;
    CHECK(lantern_snappy_max_compressed_size(written, &max_compressed) == LANTERN_SNAPPY_OK);
    uint8_t *compressed = (uint8_t *)malloc(max_compressed);
    CHECK(compressed != NULL);
    size_t compressed_len = 0;
    CHECK(
        lantern_snappy_compress(
            encoded,
            written,
            compressed,
            max_compressed,
            &compressed_len)
        == LANTERN_SNAPPY_OK);
    LanternBlocksByRootResponse snappy_decoded;
    lantern_blocks_by_root_response_init(&snappy_decoded);
    check_zero(
        lantern_network_blocks_by_root_response_decode_snappy(&snappy_decoded, compressed, compressed_len),
        "response fixture decode snappy");
    CHECK(snappy_decoded.length == decoded.length);
    CHECK(snappy_decoded.blocks[0].message.block.slot == 12);
    CHECK(snappy_decoded.blocks[1].message.block.slot == 18);

    free(compressed);
    free(encoded);
    lantern_blocks_by_root_response_reset(&resp);
    lantern_blocks_by_root_response_reset(&decoded);
    lantern_blocks_by_root_response_reset(&snappy_decoded);
}

static void test_status_snappy(void) {
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

    uint8_t compressed[256];
    size_t compressed_len = 0;
    size_t status_raw_len = 0;
    check_zero(
        lantern_network_status_encode_snappy(&status, compressed, sizeof(compressed), &compressed_len, &status_raw_len),
        "status encode snappy");
    CHECK(status_raw_len == 2u * LANTERN_CHECKPOINT_SSZ_SIZE);

    LanternStatusMessage snappy_decoded = {0};
    check_zero(lantern_network_status_decode_snappy(&snappy_decoded, compressed, compressed_len), "status decode snappy");
    CHECK(memcmp(snappy_decoded.head.root.bytes, status.head.root.bytes, LANTERN_ROOT_SIZE) == 0);
    CHECK(snappy_decoded.finalized.slot == status.finalized.slot);
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

static void test_status_snappy_rejects_truncated_frames(void) {
    size_t fixture_len = 0;
    uint8_t *fixture = read_fixture_bytes("networking/status_leanspec.snappy", &fixture_len);
    CHECK(fixture_len > 1);
    LanternStatusMessage decoded = {0};
    CHECK(lantern_network_status_decode_snappy(&decoded, fixture, fixture_len - 1) != 0);
    free(fixture);
}

static void test_status_reqresp_snappy_fixture(void) {
    /* Build status message with same values as the fixture */
    LanternStatusMessage status = {
        .finalized = build_checkpoint(0x11, 42),
        .head = build_checkpoint(0x41, 96),
    };

    /* Encode to raw SSZ then compress with raw snappy */
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

    /* Build reqresp frame - varint encodes the compressed payload size */
    uint8_t header[LANTERN_REQRESP_HEADER_MAX_BYTES];
    size_t header_len = 0;
    CHECK(unsigned_varint_encode(snappy_len, header, sizeof(header), &header_len) == UNSIGNED_VARINT_OK);

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

    libp2p_stream_backend_ops_t ops = {
        .read = mock_stream_read,
        .write = mock_stream_write,
        .close = mock_stream_close,
        .reset = mock_stream_reset,
        .set_deadline = mock_stream_set_deadline,
        .free_ctx = mock_stream_free_ctx,
    };
    libp2p_stream_t *stream = libp2p_stream_from_ops(NULL, ctx, &ops, LANTERN_STATUS_PROTOCOL_ID, 0, NULL);
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
    check_zero(
        lantern_network_status_decode_snappy(&decoded, response, response_len),
        "reqresp status decode snappy");
    expect_checkpoint_seed(&decoded.finalized, 42, 0x11);
    expect_checkpoint_seed(&decoded.head, 96, 0x41);

    free(response);
    libp2p_stream_free(stream);
    free(snappy_payload);
}

static uint8_t *build_reqresp_frame(
    uint8_t response_code,
    const uint8_t *payload,
    size_t payload_len,
    size_t raw_len,
    size_t *out_len) {
    (void)raw_len; /* Unused - varint encodes compressed payload size */
    uint8_t header[LANTERN_REQRESP_HEADER_MAX_BYTES];
    size_t header_len = 0;
    CHECK(unsigned_varint_encode(payload_len, header, sizeof(header), &header_len) == UNSIGNED_VARINT_OK);

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
    size_t fixture_len = 0;
    uint8_t *fixture = read_fixture_bytes("networking/status_leanspec.snappy", &fixture_len);
    CHECK(fixture_len > 0);

    size_t raw_len = 0;
    CHECK(lantern_snappy_uncompressed_length(fixture, fixture_len, &raw_len) == LANTERN_SNAPPY_OK);

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

        libp2p_stream_backend_ops_t ops = {
            .read = mock_stream_read,
            .write = mock_stream_write,
            .close = mock_stream_close,
            .reset = mock_stream_reset,
            .set_deadline = mock_stream_set_deadline,
            .free_ctx = mock_stream_free_ctx,
        };
        libp2p_stream_t *stream = libp2p_stream_from_ops(NULL, ctx, &ops, LANTERN_STATUS_PROTOCOL_ID, 0, NULL);
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
        libp2p_stream_free(stream);
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

    libp2p_stream_backend_ops_t ops = {
        .read = mock_stream_read,
        .write = mock_stream_write,
        .close = mock_stream_close,
        .reset = mock_stream_reset,
        .set_deadline = mock_stream_set_deadline,
        .free_ctx = mock_stream_free_ctx,
    };
    libp2p_stream_t *stream = libp2p_stream_from_ops(NULL, ctx, &ops, LANTERN_BLOCKS_BY_ROOT_PROTOCOL_ID, 0, NULL);
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

    libp2p_stream_free(stream);
    free(snappy_one);
    free(snappy_two);
}

static LanternSignedVote build_fixture_signed_vote(void) {
    /* Build signed vote matching the expected fixture values */
    LanternSignedVote vote;
    memset(&vote, 0, sizeof(vote));
    vote.data.validator_id = 9;
    vote.data.slot = 96;
    vote.data.head = build_checkpoint(0x33, 97);
    vote.data.target = build_checkpoint(0x53, 96);
    vote.data.source = build_checkpoint(0x73, 94);
    fill_signature(&vote.signature, 0xE1);
    return vote;
}

static void test_gossip_signed_vote_fixture_roundtrip(void) {
    /* Build the signed vote using C code instead of loading fixtures */
    LanternSignedVote original = build_fixture_signed_vote();
    expect_signed_vote_fixture(&original);

    /* Encode to SSZ */
    uint8_t ssz_bytes[LANTERN_SIGNED_VOTE_SSZ_SIZE];
    size_t ssz_len = 0;
    CHECK(lantern_ssz_encode_signed_vote(&original, ssz_bytes, sizeof(ssz_bytes), &ssz_len) == 0);
    CHECK(ssz_len == LANTERN_SIGNED_VOTE_SSZ_SIZE);

    /* Decode from SSZ and verify */
    LanternSignedVote from_ssz;
    memset(&from_ssz, 0, sizeof(from_ssz));
    CHECK(lantern_ssz_decode_signed_vote(&from_ssz, ssz_bytes, ssz_len) == 0);
    expect_signed_vote_fixture(&from_ssz);
    check_signed_vote_equal(&original, &from_ssz);

    /* Encode to snappy and decode */
    size_t max_compressed = 0;
    CHECK(lantern_snappy_max_compressed_size_raw(ssz_len, &max_compressed) == LANTERN_SNAPPY_OK);
    uint8_t *snappy_bytes = (uint8_t *)malloc(max_compressed);
    CHECK(snappy_bytes != NULL);
    size_t snappy_len = 0;
    CHECK(
        lantern_gossip_encode_signed_vote_snappy(
            &original,
            snappy_bytes,
            max_compressed,
            &snappy_len)
        == 0);
    CHECK(snappy_len > 0);

    LanternSignedVote from_snappy;
    memset(&from_snappy, 0, sizeof(from_snappy));
    CHECK(lantern_gossip_decode_signed_vote_snappy(&from_snappy, snappy_bytes, snappy_len) == 0);
    expect_signed_vote_fixture(&from_snappy);
    check_signed_vote_equal(&original, &from_snappy);

    /* Decompress and verify matches SSZ */
    uint8_t *raw = (uint8_t *)malloc(ssz_len);
    CHECK(raw != NULL);
    size_t raw_written = ssz_len;
    CHECK(
        lantern_snappy_decompress_raw(
            snappy_bytes,
            snappy_len,
            raw,
            ssz_len,
            &raw_written)
        == LANTERN_SNAPPY_OK);
    CHECK(raw_written == ssz_len);
    CHECK(memcmp(raw, ssz_bytes, ssz_len) == 0);

    free(raw);
    free(snappy_bytes);
}

static void build_fixture_aggregated_attestation(
    LanternAggregatedAttestation *agg,
    uint64_t validator_id,
    uint64_t slot,
    uint64_t head_slot,
    uint8_t head_seed,
    uint64_t target_slot,
    uint8_t target_seed,
    uint64_t source_slot,
    uint8_t source_seed) {
    lantern_aggregated_attestation_init(agg);
    agg->data.slot = slot;
    agg->data.head = build_checkpoint(head_seed, head_slot);
    agg->data.target = build_checkpoint(target_seed, target_slot);
    agg->data.source = build_checkpoint(source_seed, source_slot);
    size_t bit_length = (size_t)validator_id + 1u;
    check_zero(lantern_bitlist_resize(&agg->aggregation_bits, bit_length), "agg bits resize");
    check_zero(lantern_bitlist_set(&agg->aggregation_bits, (size_t)validator_id, true), "agg bits set");
}

static void build_fixture_signature_proof(
    LanternAggregatedSignatureProof *proof,
    uint64_t validator_id,
    uint8_t seed,
    size_t length) {
    size_t bit_length = (size_t)validator_id + 1u;
    check_zero(lantern_bitlist_resize(&proof->participants, bit_length), "proof bits resize");
    check_zero(lantern_bitlist_set(&proof->participants, (size_t)validator_id, true), "proof bits set");
    check_zero(lantern_byte_list_resize(&proof->proof_data, length), "proof data resize");
    if (length > 0 && proof->proof_data.data) {
        fill_bytes(proof->proof_data.data, length, seed);
    }
}

static void build_fixture_signed_block(LanternSignedBlock *block) {
    lantern_signed_block_with_attestation_init(block);

    /* Block header */
    block->message.block.slot = 72;
    block->message.block.proposer_index = 5;
    fill_bytes(block->message.block.parent_root.bytes, LANTERN_ROOT_SIZE, 0x24);
    fill_bytes(block->message.block.state_root.bytes, LANTERN_ROOT_SIZE, 0x74);

    /* Attestations */
    check_zero(
        lantern_aggregated_attestations_resize(&block->message.block.body.attestations, 2),
        "attestations resize");
    build_fixture_aggregated_attestation(
        &block->message.block.body.attestations.data[0], 9, 71, 72, 0x24, 71, 0x44, 69, 0x64);
    build_fixture_aggregated_attestation(
        &block->message.block.body.attestations.data[1], 10, 70, 71, 0x29, 70, 0x49, 68, 0x69);

    /* Proposer attestation */
    block->message.proposer_attestation.validator_id = 8;
    block->message.proposer_attestation.slot = 74;
    block->message.proposer_attestation.head = build_checkpoint(0xA4, 75);
    block->message.proposer_attestation.target = build_checkpoint(0xC4, 74);
    block->message.proposer_attestation.source = build_checkpoint(0xE4, 72);

    /* Signatures */
    check_zero(
        lantern_attestation_signatures_resize(&block->signatures.attestation_signatures, 2),
        "signatures resize");
    build_fixture_signature_proof(&block->signatures.attestation_signatures.data[0], 9, 0xC4, 8);
    build_fixture_signature_proof(&block->signatures.attestation_signatures.data[1], 10, 0xC7, 8);
    fill_signature(&block->signatures.proposer_signature, 0xF0);
}

static void test_gossip_signed_block_fixture_roundtrip(void) {
    /* Build the signed block using C code instead of loading fixtures */
    LanternSignedBlock original;
    build_fixture_signed_block(&original);
    expect_signed_block_fixture(&original);

    /* Encode to SSZ */
    size_t max_ssz = 1u << 20;
    uint8_t *ssz_bytes = (uint8_t *)malloc(max_ssz);
    CHECK(ssz_bytes != NULL);
    size_t ssz_len = 0;
    CHECK(lantern_ssz_encode_signed_block(&original, ssz_bytes, max_ssz, &ssz_len) == 0);
    CHECK(ssz_len > 0);

    /* Decode from SSZ and verify */
    LanternSignedBlock from_ssz;
    lantern_signed_block_with_attestation_init(&from_ssz);
    CHECK(lantern_ssz_decode_signed_block(&from_ssz, ssz_bytes, ssz_len) == 0);
    expect_signed_block_fixture(&from_ssz);
    check_signed_block_equal(&original, &from_ssz);

    /* Encode to snappy and decode */
    size_t max_compressed = 0;
    CHECK(lantern_snappy_max_compressed_size_raw(ssz_len, &max_compressed) == LANTERN_SNAPPY_OK);
    uint8_t *snappy_bytes = (uint8_t *)malloc(max_compressed);
    CHECK(snappy_bytes != NULL);
    size_t snappy_len = 0;
    CHECK(
        lantern_gossip_encode_signed_block_snappy(
            &original,
            snappy_bytes,
            max_compressed,
            &snappy_len)
        == 0);
    CHECK(snappy_len > 0);

    LanternSignedBlock from_snappy;
    lantern_signed_block_with_attestation_init(&from_snappy);
    CHECK(lantern_gossip_decode_signed_block_snappy(&from_snappy, snappy_bytes, snappy_len) == 0);
    expect_signed_block_fixture(&from_snappy);
    check_signed_block_equal(&original, &from_snappy);

    /* Decompress and verify matches SSZ */
    uint8_t *raw = (uint8_t *)malloc(ssz_len);
    CHECK(raw != NULL);
    size_t raw_written = ssz_len;
    CHECK(
        lantern_snappy_decompress_raw(
            snappy_bytes,
            snappy_len,
            raw,
            ssz_len,
            &raw_written)
        == LANTERN_SNAPPY_OK);
    CHECK(raw_written == ssz_len);
    CHECK(memcmp(raw, ssz_bytes, ssz_len) == 0);

    free(raw);
    free(snappy_bytes);
    free(ssz_bytes);
    lantern_signed_block_with_attestation_reset(&from_snappy);
    lantern_signed_block_with_attestation_reset(&from_ssz);
    lantern_signed_block_with_attestation_reset(&original);
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
    size_t expected_written = req.roots.length * LANTERN_ROOT_SIZE;
    CHECK(written == expected_written);

    LanternBlocksByRootRequest decoded;
    lantern_blocks_by_root_request_init(&decoded);
    check_zero(lantern_network_blocks_by_root_request_decode(&decoded, encoded, written), "request decode");
    CHECK(decoded.roots.length == req.roots.length);
    CHECK(memcmp(decoded.roots.items[1].bytes, req.roots.items[1].bytes, LANTERN_ROOT_SIZE) == 0);

    uint8_t compressed[256];
    size_t compressed_len = 0;
    size_t request_raw_len = 0;
    check_zero(
        lantern_network_blocks_by_root_request_encode_snappy(
            &req,
            compressed,
            sizeof(compressed),
            &compressed_len,
            &request_raw_len),
        "request encode snappy");
    CHECK(request_raw_len == expected_written);

    LanternBlocksByRootRequest snappy_decoded;
    lantern_blocks_by_root_request_init(&snappy_decoded);
    check_zero(lantern_network_blocks_by_root_request_decode_snappy(&snappy_decoded, compressed, compressed_len), "request decode snappy");
    CHECK(snappy_decoded.roots.length == req.roots.length);
    CHECK(memcmp(snappy_decoded.roots.items[0].bytes, req.roots.items[0].bytes, LANTERN_ROOT_SIZE) == 0);

    lantern_blocks_by_root_request_reset(&req);
    lantern_blocks_by_root_request_reset(&decoded);
    lantern_blocks_by_root_request_reset(&snappy_decoded);
}

static void test_blocks_by_root_response(void) {
    LanternBlocksByRootResponse resp;
    lantern_blocks_by_root_response_init(&resp);
    check_zero(lantern_blocks_by_root_response_resize(&resp, 2), "response resize");
    populate_block(&resp.blocks[0], 1);
    populate_block(&resp.blocks[1], 2);

    size_t encoded_capacity = 1u << 20;
    uint8_t *encoded = (uint8_t *)malloc(encoded_capacity);
    CHECK(encoded != NULL);
    for (size_t i = 0; i < resp.length; ++i) {
        size_t tmp_written = 0;
        CHECK(lantern_ssz_encode_signed_block(&resp.blocks[i], encoded, encoded_capacity, &tmp_written) == 0);
        CHECK(tmp_written > 0);
    }
    size_t written = 0;
    check_zero(
        lantern_network_blocks_by_root_response_encode(&resp, encoded, encoded_capacity, &written),
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

    LanternBlocksByRootResponse decoded;
    lantern_blocks_by_root_response_init(&decoded);
    check_zero(lantern_network_blocks_by_root_response_decode(&decoded, encoded, written), "response decode");
    CHECK(decoded.length == resp.length);
    const LanternVote *decoded_vote0 = &decoded.blocks[0].message.proposer_attestation;
    const LanternVote *expected_vote0 = &resp.blocks[0].message.proposer_attestation;
    CHECK(decoded_vote0->validator_id == expected_vote0->validator_id);
    CHECK(decoded_vote0->slot == expected_vote0->slot);
    CHECK(decoded_vote0->head.slot == expected_vote0->head.slot);
    CHECK(memcmp(decoded_vote0->head.root.bytes, expected_vote0->head.root.bytes, LANTERN_ROOT_SIZE) == 0);
    CHECK(decoded_vote0->target.slot == expected_vote0->target.slot);
    CHECK(memcmp(decoded_vote0->target.root.bytes, expected_vote0->target.root.bytes, LANTERN_ROOT_SIZE) == 0);
    CHECK(decoded_vote0->source.slot == expected_vote0->source.slot);
    CHECK(memcmp(decoded_vote0->source.root.bytes, expected_vote0->source.root.bytes, LANTERN_ROOT_SIZE) == 0);
    const LanternVote *decoded_vote1 = &decoded.blocks[1].message.proposer_attestation;
    const LanternVote *expected_vote1 = &resp.blocks[1].message.proposer_attestation;
    CHECK(decoded_vote1->validator_id == expected_vote1->validator_id);
    CHECK(decoded_vote1->slot == expected_vote1->slot);
    CHECK(decoded_vote1->head.slot == expected_vote1->head.slot);
    CHECK(memcmp(decoded_vote1->head.root.bytes, expected_vote1->head.root.bytes, LANTERN_ROOT_SIZE) == 0);
    CHECK(decoded_vote1->target.slot == expected_vote1->target.slot);
    CHECK(memcmp(decoded_vote1->target.root.bytes, expected_vote1->target.root.bytes, LANTERN_ROOT_SIZE) == 0);
    CHECK(decoded_vote1->source.slot == expected_vote1->source.slot);
    CHECK(memcmp(decoded_vote1->source.root.bytes, expected_vote1->source.root.bytes, LANTERN_ROOT_SIZE) == 0);
    check_block_signatures_equal(&decoded.blocks[1].signatures, &resp.blocks[1].signatures);

    size_t max_compressed = 0;
    CHECK(lantern_snappy_max_compressed_size(written, &max_compressed) == LANTERN_SNAPPY_OK);
    uint8_t *compressed = (uint8_t *)malloc(max_compressed);
    CHECK(compressed != NULL);
    size_t compressed_len = 0;
    size_t response_raw_len = 0;
    check_zero(
        lantern_network_blocks_by_root_response_encode_snappy(
            &resp,
            compressed,
            max_compressed,
            &compressed_len,
            &response_raw_len),
        "response encode snappy");
    CHECK(response_raw_len == written);

    LanternBlocksByRootResponse snappy_decoded;
    lantern_blocks_by_root_response_init(&snappy_decoded);
    check_zero(lantern_network_blocks_by_root_response_decode_snappy(&snappy_decoded, compressed, compressed_len), "response decode snappy");
    CHECK(snappy_decoded.length == resp.length);
    CHECK(snappy_decoded.blocks[0].message.slot == resp.blocks[0].message.slot);
    const LanternVote *snappy_vote = &snappy_decoded.blocks[0].message.proposer_attestation;
    const LanternVote *expected_snappy_vote = &resp.blocks[0].message.proposer_attestation;
    CHECK(snappy_vote->validator_id == expected_snappy_vote->validator_id);
    CHECK(snappy_vote->slot == expected_snappy_vote->slot);
    CHECK(snappy_vote->head.slot == expected_snappy_vote->head.slot);
    CHECK(memcmp(snappy_vote->head.root.bytes, expected_snappy_vote->head.root.bytes, LANTERN_ROOT_SIZE) == 0);
    CHECK(snappy_vote->target.slot == expected_snappy_vote->target.slot);
    CHECK(memcmp(snappy_vote->target.root.bytes, expected_snappy_vote->target.root.bytes, LANTERN_ROOT_SIZE) == 0);
    CHECK(snappy_vote->source.slot == expected_snappy_vote->source.slot);
    CHECK(memcmp(snappy_vote->source.root.bytes, expected_snappy_vote->source.root.bytes, LANTERN_ROOT_SIZE) == 0);

    lantern_blocks_by_root_response_reset(&resp);
    lantern_blocks_by_root_response_reset(&decoded);
    lantern_blocks_by_root_response_reset(&snappy_decoded);
    free(encoded);
    free(compressed);
}

static void test_gossip_helpers(void) {
    char topic[128];
    check_zero(lantern_gossip_topic_format(LANTERN_GOSSIP_TOPIC_BLOCK, "devnet", topic, sizeof(topic)), "topic format");
    CHECK(strcmp(topic, "/leanconsensus/devnet/block/ssz_snappy") == 0);

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
    CHECK(lantern_ssz_encode_signed_vote(&vote, raw_buf, sizeof(raw_buf), &raw_written) == 0);

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
    lantern_signed_block_with_attestation_init(&block);
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
    lantern_signed_block_with_attestation_init(&decoded);
    check_zero(
        lantern_gossip_decode_signed_block_snappy(&decoded, compressed, compressed_len),
        "decode signed block gossip");
    CHECK(decoded.message.block.slot == block.message.block.slot);
    CHECK(decoded.message.block.body.attestations.length == block.message.block.body.attestations.length);
    CHECK(decoded.message.proposer_attestation.validator_id == block.message.proposer_attestation.validator_id);
    CHECK(decoded.message.proposer_attestation.slot == block.message.proposer_attestation.slot);
    CHECK(decoded.message.proposer_attestation.head.slot == block.message.proposer_attestation.head.slot);
    CHECK(memcmp(
              decoded.message.proposer_attestation.head.root.bytes,
              block.message.proposer_attestation.head.root.bytes,
              LANTERN_ROOT_SIZE)
          == 0);
    CHECK(decoded.message.proposer_attestation.target.slot == block.message.proposer_attestation.target.slot);
    CHECK(memcmp(
              decoded.message.proposer_attestation.target.root.bytes,
              block.message.proposer_attestation.target.root.bytes,
              LANTERN_ROOT_SIZE)
          == 0);
    CHECK(decoded.message.proposer_attestation.source.slot == block.message.proposer_attestation.source.slot);
    CHECK(memcmp(
              decoded.message.proposer_attestation.source.root.bytes,
              block.message.proposer_attestation.source.root.bytes,
              LANTERN_ROOT_SIZE)
          == 0);
    check_block_signatures_equal(&decoded.signatures, &block.signatures);

    uint8_t invalid_payload[] = {0xFF};
    CHECK(lantern_gossip_decode_signed_block_snappy(&decoded, invalid_payload, sizeof(invalid_payload)) != 0);

    lantern_signed_block_with_attestation_reset(&decoded);
    lantern_signed_block_with_attestation_reset(&block);
    free(compressed);
}

static void test_gossip_block_snappy_roundtrip_random(void) {
    const size_t iterations = 64;
    for (size_t i = 0; i < iterations; ++i) {
        LanternSignedBlock original;
        lantern_signed_block_with_attestation_init(&original);
        original.message.block.slot = 1 + rng_uniform(2047);
        original.message.block.proposer_index = rng_uniform(63);
        rng_fill_bytes(original.message.block.parent_root.bytes, LANTERN_ROOT_SIZE);
        rng_fill_bytes(original.message.block.state_root.bytes, LANTERN_ROOT_SIZE);

        size_t att_count = rng_uniform(4);
        for (size_t j = 0; j < att_count; ++j) {
            LanternSignedVote vote;
            memset(&vote, 0, sizeof(vote));
            vote.data.validator_id = rng_uniform(255);
            vote.data.slot = rng_uniform(original.message.block.slot);
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
            CHECK(lantern_aggregated_attestations_append(&original.message.block.body.attestations, &agg) == 0);
            lantern_aggregated_attestation_reset(&agg);
        }

        LanternSignedVote proposer_vote = build_signed_vote(700 + i, original.message.block.slot, 0x50);
        original.message.proposer_attestation = proposer_vote.data;
        CHECK(lantern_attestation_signatures_resize(&original.signatures.attestation_signatures, att_count) == 0);
        for (size_t sig_idx = 0; sig_idx < att_count; ++sig_idx) {
            LanternAggregatedSignatureProof *proof = &original.signatures.attestation_signatures.data[sig_idx];
            const LanternAggregatedAttestation *att = &original.message.block.body.attestations.data[sig_idx];
            CHECK(lantern_bitlist_resize(&proof->participants, att->aggregation_bits.bit_length) == 0);
            size_t byte_len = (att->aggregation_bits.bit_length + 7u) / 8u;
            if (byte_len > 0) {
                memcpy(proof->participants.bytes, att->aggregation_bits.bytes, byte_len);
            }
            size_t proof_len = 4u + (sig_idx % 4u);
            CHECK(lantern_byte_list_resize(&proof->proof_data, proof_len) == 0);
            if (proof_len > 0 && proof->proof_data.data) {
                rng_fill_bytes(proof->proof_data.data, proof_len);
            }
        }
        rng_fill_bytes(original.signatures.proposer_signature.bytes, LANTERN_SIGNATURE_SIZE);

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
        lantern_signed_block_with_attestation_init(&decoded);
        check_zero(
            lantern_gossip_decode_signed_block_snappy(&decoded, compressed, written),
            "random block decode");

        CHECK(decoded.message.block.slot == original.message.block.slot);
        CHECK(decoded.message.block.proposer_index == original.message.block.proposer_index);
        CHECK(memcmp(decoded.message.block.parent_root.bytes, original.message.block.parent_root.bytes, LANTERN_ROOT_SIZE) == 0);
        CHECK(memcmp(decoded.message.block.state_root.bytes, original.message.block.state_root.bytes, LANTERN_ROOT_SIZE) == 0);
        CHECK(decoded.message.block.body.attestations.length == original.message.block.body.attestations.length);
        CHECK(decoded.message.proposer_attestation.validator_id == original.message.proposer_attestation.validator_id);
        CHECK(decoded.message.proposer_attestation.slot == original.message.proposer_attestation.slot);
        CHECK(decoded.message.proposer_attestation.head.slot == original.message.proposer_attestation.head.slot);
        CHECK(memcmp(
                  decoded.message.proposer_attestation.head.root.bytes,
                  original.message.proposer_attestation.head.root.bytes,
                  LANTERN_ROOT_SIZE)
              == 0);
        CHECK(decoded.message.proposer_attestation.target.slot == original.message.proposer_attestation.target.slot);
        CHECK(memcmp(
                  decoded.message.proposer_attestation.target.root.bytes,
                  original.message.proposer_attestation.target.root.bytes,
                  LANTERN_ROOT_SIZE)
              == 0);
        CHECK(decoded.message.proposer_attestation.source.slot == original.message.proposer_attestation.source.slot);
        CHECK(memcmp(
                  decoded.message.proposer_attestation.source.root.bytes,
                  original.message.proposer_attestation.source.root.bytes,
                  LANTERN_ROOT_SIZE)
              == 0);
        for (size_t j = 0; j < decoded.message.block.body.attestations.length; ++j) {
            const LanternAggregatedAttestation *expected = &original.message.block.body.attestations.data[j];
            const LanternAggregatedAttestation *actual = &decoded.message.block.body.attestations.data[j];
            check_aggregated_attestation_equal(expected, actual);
        }
        check_block_signatures_equal(&decoded.signatures, &original.signatures);

        free(compressed);
        lantern_signed_block_with_attestation_reset(&original);
        lantern_signed_block_with_attestation_reset(&decoded);
    }
}

static void test_gossipsub_service_loopback(void) {
    struct lantern_gossipsub_service service;
    lantern_gossipsub_service_init(&service);
    snprintf(service.block_topic, sizeof(service.block_topic), "/leanconsensus/devnet0/block/ssz_snappy");
    lantern_gossipsub_service_set_loopback_only(&service, 1);

    LanternSignedBlock block;
    lantern_signed_block_with_attestation_init(&block);
    populate_block(&block, 9);

    struct block_hook_ctx ctx = {
        .expected = &block,
        .expected_topic = service.block_topic,
        .called = 0,
    };
    lantern_gossipsub_service_set_publish_hook(&service, block_publish_hook, &ctx);

    CHECK(lantern_gossipsub_service_publish_block(&service, &block) == 0);
    CHECK(ctx.called == 1);

    lantern_signed_block_with_attestation_reset(&block);
    lantern_gossipsub_service_reset(&service);
}

static void test_client_publish_block_loopback(void) {
    struct lantern_client client;
    memset(&client, 0, sizeof(client));
    lantern_gossipsub_service_init(&client.gossip);
    snprintf(client.gossip.block_topic, sizeof(client.gossip.block_topic), "/leanconsensus/devnet/block/ssz_snappy");
    lantern_gossipsub_service_set_loopback_only(&client.gossip, 1);

    LanternSignedBlock block;
    lantern_signed_block_with_attestation_init(&block);
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

    lantern_signed_block_with_attestation_reset(&block);
    lantern_gossipsub_service_reset(&client.gossip);
}

int main(void) {
    test_status_fixture_roundtrip();
    test_blocks_by_root_request_fixture();
    test_blocks_by_root_response_fixture();
    test_status_snappy();
    test_status_decode_rejects_truncated_payloads();
    test_status_snappy_rejects_truncated_frames();
    test_status_reqresp_snappy_fixture();
    test_reqresp_response_code_mapping();
    test_blocks_by_root_per_chunk_framing();
    test_gossip_signed_vote_fixture_roundtrip();
    test_gossip_signed_block_fixture_roundtrip();
    test_blocks_by_root_request();
    test_blocks_by_root_response();
    test_gossip_signed_vote_payload();
    test_gossip_signed_block_payload();
    test_gossip_block_snappy_roundtrip_random();
    test_replay_devnet_block_payloads();
    test_gossipsub_service_loopback();
    test_client_publish_block_loopback();
    test_gossip_helpers();
    puts("lantern_networking_messages_test OK");
    return 0;
}
