#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>

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

static void test_gossip_helpers(void) {
    char topic[128];
    char digest_hex[LANTERN_GOSSIP_FORK_DIGEST_HEX_LEN + 1u];
    static const uint8_t fork_digest[4] = {0x12, 0x34, 0x56, 0x78};
    check_zero(lantern_gossip_fork_digest_to_hex(fork_digest, digest_hex), "fork digest hex");
    CHECK(strcmp(digest_hex, "12345678") == 0);

    check_zero(lantern_gossip_topic_format(LANTERN_GOSSIP_TOPIC_BLOCK, "devnet0", topic, sizeof(topic)), "topic format");
    CHECK(strcmp(topic, "/leanconsensus/devnet0/block/ssz_snappy") == 0);

    check_zero(
        lantern_gossip_topic_format_subnet(
            LANTERN_GOSSIP_TOPIC_VOTE_SUBNET,
            "devnet0",
            7u,
            topic,
            sizeof(topic)),
        "topic format subnet");
    CHECK(strcmp(topic, "/leanconsensus/devnet0/attestation_7/ssz_snappy") == 0);

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
    test_blocks_by_root_request();
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
