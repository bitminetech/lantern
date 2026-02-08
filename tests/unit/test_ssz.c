#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "lantern/consensus/containers.h"
#include "lantern/consensus/hash.h"
#include "lantern/consensus/state.h"
#include "lantern/consensus/ssz.h"
#include "../fixtures/ssz_vectors.h"

#define SIGNED_BLOCK_TEST_BUFFER_SIZE 32768

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

static void expect_ok(int rc, const char *context);

static void copy_root(LanternRoot *dst, const uint8_t *bytes) {
    memcpy(dst->bytes, bytes, LANTERN_ROOT_SIZE);
}

static const char *g_current_test = "unknown";
static void expect_bytes_equal(
    const uint8_t *expected,
    size_t expected_len,
    const uint8_t *actual,
    size_t actual_len) {
    size_t min_len = expected_len < actual_len ? expected_len : actual_len;
    for (size_t i = 0; i < min_len; ++i) {
        if (expected[i] != actual[i]) {
            fprintf(stderr, "[%s] byte mismatch at %zu (expected 0x%02X got 0x%02X)\n", g_current_test, i, expected[i], actual[i]);
            abort();
        }
    }
    if (expected_len != actual_len) {
        if (actual_len > expected_len) {
            fprintf(stderr, "extra actual bytes:");
            for (size_t i = expected_len; i < actual_len; ++i) {
                fprintf(stderr, " [%zu]=0x%02X", i, actual[i]);
                if (i - expected_len >= 15) {
                    break;
                }
            }
            fprintf(stderr, "\n");
        }
        fprintf(stderr, "byte length mismatch (%zu != %zu)\n", expected_len, actual_len);
        abort();
    }
}

static void expect_bytes_equal_or_legacy(
    const uint8_t *expected,
    size_t expected_len,
    const uint8_t *actual,
    size_t actual_len,
    const uint8_t *legacy,
    size_t legacy_len) {
    if (expected_len == actual_len && memcmp(expected, actual, expected_len) == 0) {
        return;
    }
    if (expected_len == legacy_len && memcmp(expected, legacy, expected_len) == 0) {
        return;
    }
    expect_bytes_equal(expected, expected_len, actual, actual_len);
}

static void maybe_dump_vector(
    const char *env_var,
    const char *label,
    const uint8_t *data,
    size_t len) {
    const char *dump_env = getenv(env_var);
    if (!dump_env || dump_env[0] == '\0') {
        return;
    }
    printf("// %s length=%zu\n", label, len);
    printf("static const uint8_t %s[] = {\n", label);
    for (size_t i = 0; i < len; ++i) {
        if (i % 12 == 0) {
            printf("    ");
        }
        printf("0x%02X", data[i]);
        if (i + 1 < len) {
            printf(", ");
        }
        if ((i + 1) % 12 == 0 || i + 1 == len) {
            printf("\n");
        }
    }
    printf("};\n");
    fflush(stdout);
    exit(0);
}

static void maybe_dump_state_vector(const uint8_t *data, size_t len) {
    maybe_dump_vector("LANTERN_DUMP_SSZ_STATE", "LANTERN_SSZ_VECTOR_STATE", data, len);
}

static LanternCheckpoint checkpoint_from_vector(const uint8_t *root_bytes, uint64_t slot) {
    LanternCheckpoint checkpoint;
    copy_root(&checkpoint.root, root_bytes);
    checkpoint.slot = slot;
    return checkpoint;
}

static void assert_checkpoint_equal(const LanternCheckpoint *lhs, const LanternCheckpoint *rhs) {
    if (lhs->slot != rhs->slot
        || memcmp(lhs->root.bytes, rhs->root.bytes, LANTERN_ROOT_SIZE) != 0) {
        fprintf(stderr, "checkpoint mismatch\n");
        abort();
    }
}

static void assert_vote_equal(const LanternVote *lhs, const LanternVote *rhs) {
    if (lhs->validator_id != rhs->validator_id || lhs->slot != rhs->slot) {
        fprintf(stderr, "vote slot mismatch\n");
        abort();
    }
    assert_checkpoint_equal(&lhs->head, &rhs->head);
    assert_checkpoint_equal(&lhs->target, &rhs->target);
    assert_checkpoint_equal(&lhs->source, &rhs->source);
}

static void assert_signed_vote_equal(const LanternSignedVote *lhs, const LanternSignedVote *rhs) {
    assert_vote_equal(&lhs->data, &rhs->data);
    if (memcmp(lhs->signature.bytes, rhs->signature.bytes, LANTERN_SIGNATURE_SIZE) != 0) {
        fprintf(stderr, "vote signature mismatch\n");
        abort();
    }
}

static void assert_attestation_data_equal(const LanternAttestationData *lhs, const LanternAttestationData *rhs) {
    if (lhs->slot != rhs->slot) {
        fprintf(stderr, "attestation data slot mismatch\n");
        abort();
    }
    assert_checkpoint_equal(&lhs->head, &rhs->head);
    assert_checkpoint_equal(&lhs->target, &rhs->target);
    assert_checkpoint_equal(&lhs->source, &rhs->source);
}

static void assert_bitlist_equal(const struct lantern_bitlist *lhs, const struct lantern_bitlist *rhs) {
    if (lhs->bit_length != rhs->bit_length) {
        fprintf(stderr, "bitlist length mismatch\n");
        abort();
    }
    size_t byte_len = (lhs->bit_length + 7u) / 8u;
    if (byte_len == 0) {
        return;
    }
    if (!lhs->bytes || !rhs->bytes) {
        fprintf(stderr, "bitlist bytes missing\n");
        abort();
    }
    if (memcmp(lhs->bytes, rhs->bytes, byte_len) != 0) {
        fprintf(stderr, "bitlist bytes mismatch\n");
        abort();
    }
}

static void assert_aggregated_attestation_equal(
    const LanternAggregatedAttestation *lhs,
    const LanternAggregatedAttestation *rhs) {
    assert_attestation_data_equal(&lhs->data, &rhs->data);
    assert_bitlist_equal(&lhs->aggregation_bits, &rhs->aggregation_bits);
}

static void assert_signature_proof_equal(
    const LanternAggregatedSignatureProof *lhs,
    const LanternAggregatedSignatureProof *rhs) {
    assert_bitlist_equal(&lhs->participants, &rhs->participants);
    if (lhs->proof_data.length != rhs->proof_data.length) {
        fprintf(stderr, "signature proof length mismatch\n");
        abort();
    }
    if (lhs->proof_data.length == 0) {
        return;
    }
    if (!lhs->proof_data.data || !rhs->proof_data.data) {
        fprintf(stderr, "signature proof bytes missing\n");
        abort();
    }
    if (memcmp(lhs->proof_data.data, rhs->proof_data.data, lhs->proof_data.length) != 0) {
        fprintf(stderr, "signature proof bytes mismatch\n");
        abort();
    }
}

static LanternCheckpoint build_checkpoint(uint8_t seed, uint64_t slot) {
    LanternCheckpoint checkpoint;
    fill_bytes(checkpoint.root.bytes, sizeof(checkpoint.root.bytes), seed);
    checkpoint.slot = slot;
    return checkpoint;
}

static void test_checkpoint_roundtrip(void) {
    LanternCheckpoint input = build_checkpoint(0x11, 42);
    uint8_t buffer[LANTERN_CHECKPOINT_SSZ_SIZE];
    size_t written = 0;
    assert(lantern_ssz_encode_checkpoint(&input, buffer, sizeof(buffer), &written) == 0);
    assert(written == sizeof(buffer));

    LanternCheckpoint decoded;
    memset(&decoded, 0, sizeof(decoded));
    assert(lantern_ssz_decode_checkpoint(&decoded, buffer, sizeof(buffer)) == 0);
    assert(decoded.slot == input.slot);
    assert(memcmp(decoded.root.bytes, input.root.bytes, LANTERN_ROOT_SIZE) == 0);
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
    signed_vote.data.target = build_checkpoint(seed + 1, slot + 1);
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
    expect_ok(lantern_bitlist_resize(&out_attestation->aggregation_bits, bit_length), "agg bitlist resize");
    expect_ok(lantern_bitlist_set(&out_attestation->aggregation_bits, (size_t)vote->validator_id, true),
              "agg bitlist set");
}

static int encode_legacy_plain_attestation_body(
    const LanternAttestations *attestations,
    uint8_t *out,
    size_t out_len,
    size_t *written) {
    if (!attestations || !out || !written) {
        return -1;
    }
    if (attestations->length > 0 && !attestations->data) {
        return -1;
    }

    size_t required = sizeof(uint32_t) + (attestations->length * LANTERN_VOTE_SSZ_SIZE);
    if (out_len < required || required > UINT32_MAX) {
        return -1;
    }

    uint32_t att_offset = (uint32_t)sizeof(uint32_t);
    memcpy(out, &att_offset, sizeof(att_offset));

    size_t cursor = sizeof(uint32_t);
    for (size_t i = 0; i < attestations->length; ++i) {
        size_t vote_written = 0;
        if (lantern_ssz_encode_vote(
                &attestations->data[i],
                out + cursor,
                out_len - cursor,
                &vote_written)
            != 0) {
            return -1;
        }
        if (vote_written != LANTERN_VOTE_SSZ_SIZE) {
            return -1;
        }
        cursor += vote_written;
    }
    *written = cursor;
    return 0;
}

static void fill_proof_data(LanternAggregatedSignatureProof *proof, uint8_t seed, size_t len) {
    if (!proof) {
        return;
    }
    expect_ok(lantern_byte_list_resize(&proof->proof_data, len), "proof data resize");
    if (len > 0 && proof->proof_data.data) {
        fill_bytes(proof->proof_data.data, len, seed);
    }
}

static void bitlist_set(struct lantern_bitlist *bitlist, size_t index, bool value) {
    size_t byte_index = index / 8;
    size_t bit_index = index % 8;
    if (!bitlist->bytes || byte_index >= bitlist->capacity) {
        fprintf(stderr, "bitlist_set: invalid access\n");
        abort();
    }
    if (value) {
        bitlist->bytes[byte_index] |= (uint8_t)(1u << bit_index);
    } else {
        bitlist->bytes[byte_index] &= (uint8_t)~(1u << bit_index);
    }
}

static void expect_ok(int rc, const char *context) {
    if (rc != 0) {
        fprintf(stderr, "%s failed (rc=%d)\n", context, rc);
        abort();
    }
}

static void test_vote_roundtrip(void) {
    LanternVote input = build_vote();
    uint8_t buffer[LANTERN_VOTE_SSZ_SIZE];
    size_t written = 0;
    assert(lantern_ssz_encode_vote(&input, buffer, sizeof(buffer), &written) == 0);
    assert(written == sizeof(buffer));

    LanternVote decoded;
    memset(&decoded, 0, sizeof(decoded));
    assert(lantern_ssz_decode_vote(&decoded, buffer, sizeof(buffer)) == 0);
    assert(decoded.slot == input.slot);
    assert(memcmp(decoded.head.root.bytes, input.head.root.bytes, LANTERN_ROOT_SIZE) == 0);
    assert(memcmp(decoded.target.root.bytes, input.target.root.bytes, LANTERN_ROOT_SIZE) == 0);
    assert(memcmp(decoded.source.root.bytes, input.source.root.bytes, LANTERN_ROOT_SIZE) == 0);
}

static void test_signed_vote_roundtrip(void) {
    LanternSignedVote signed_vote = build_signed_vote(42, 9, 0x21);

    uint8_t buffer[LANTERN_SIGNED_VOTE_SSZ_SIZE];
    size_t written = 0;
    assert(lantern_ssz_encode_signed_vote(&signed_vote, buffer, sizeof(buffer), &written) == 0);
    assert(written == sizeof(buffer));

    LanternSignedVote decoded;
    memset(&decoded, 0, sizeof(decoded));
    assert(lantern_ssz_decode_signed_vote(&decoded, buffer, sizeof(buffer)) == 0);
    assert(decoded.data.validator_id == signed_vote.data.validator_id);
    assert(decoded.data.slot == signed_vote.data.slot);
    assert(memcmp(decoded.signature.bytes, signed_vote.signature.bytes, LANTERN_SIGNATURE_SIZE) == 0);
}

static void test_signed_vote_signature_validation(void) {
    LanternSignedVote signed_vote = build_signed_vote(3, 5, 0x33);
    uint8_t buffer[LANTERN_SIGNED_VOTE_SSZ_SIZE];
    size_t written = 0;
    assert(lantern_ssz_encode_signed_vote(&signed_vote, buffer, sizeof(buffer), &written) == 0);

    LanternSignedVote decoded;
    memset(&decoded, 0, sizeof(decoded));
    const size_t signature_offset = LANTERN_VOTE_SSZ_SIZE + sizeof(uint32_t);
    buffer[signature_offset] ^= 0xAA;
    assert(lantern_ssz_decode_signed_vote(&decoded, buffer, sizeof(buffer)) == 0);
    assert(memcmp(&buffer[signature_offset], decoded.signature.bytes, LANTERN_SIGNATURE_SIZE) == 0);
    assert(decoded.signature.bytes[0] == (uint8_t)(signed_vote.signature.bytes[0] ^ 0xAA));

    assert(lantern_ssz_encode_signed_vote(&signed_vote, buffer, sizeof(buffer), &written) == 0);
    buffer[0] ^= 0xFF;
    assert(lantern_ssz_decode_signed_vote(&decoded, buffer, sizeof(buffer)) != 0);
}

static void test_block_header_roundtrip(void) {
    LanternBlockHeader header;
    header.slot = 64;
    header.proposer_index = 5;
    fill_bytes(header.parent_root.bytes, sizeof(header.parent_root.bytes), 0x10);
    fill_bytes(header.state_root.bytes, sizeof(header.state_root.bytes), 0x20);
    fill_bytes(header.body_root.bytes, sizeof(header.body_root.bytes), 0x30);

    uint8_t buffer[LANTERN_BLOCK_HEADER_SSZ_SIZE];
    size_t written = 0;
    assert(lantern_ssz_encode_block_header(&header, buffer, sizeof(buffer), &written) == 0);
    assert(written == sizeof(buffer));

    LanternBlockHeader decoded;
    memset(&decoded, 0, sizeof(decoded));
    assert(lantern_ssz_decode_block_header(&decoded, buffer, sizeof(buffer)) == 0);
    assert(decoded.slot == header.slot);
    assert(decoded.proposer_index == header.proposer_index);
    assert(memcmp(decoded.parent_root.bytes, header.parent_root.bytes, LANTERN_ROOT_SIZE) == 0);
    assert(memcmp(decoded.state_root.bytes, header.state_root.bytes, LANTERN_ROOT_SIZE) == 0);
    assert(memcmp(decoded.body_root.bytes, header.body_root.bytes, LANTERN_ROOT_SIZE) == 0);
}

static void test_block_body_roundtrip(void) {
    LanternBlockBody body;
    lantern_block_body_init(&body);

    LanternSignedVote vote_a = build_signed_vote(1, 5, 0x50);
    LanternSignedVote vote_b = build_signed_vote(2, 6, 0x60);
    LanternAggregatedAttestation agg_a;
    LanternAggregatedAttestation agg_b;
    build_aggregated_attestation_from_vote(&vote_a.data, &agg_a);
    build_aggregated_attestation_from_vote(&vote_b.data, &agg_b);
    assert(lantern_aggregated_attestations_append(&body.attestations, &agg_a) == 0);
    assert(lantern_aggregated_attestations_append(&body.attestations, &agg_b) == 0);
    lantern_aggregated_attestation_reset(&agg_a);
    lantern_aggregated_attestation_reset(&agg_b);

    uint8_t buffer[1024];
    size_t written = 0;
    assert(lantern_ssz_encode_block_body(&body, buffer, sizeof(buffer), &written) == 0);
    maybe_dump_vector("LANTERN_DUMP_SSZ_BLOCK_BODY", "LANTERN_SSZ_VECTOR_BLOCK_BODY", buffer, written);

    LanternBlockBody decoded;
    lantern_block_body_init(&decoded);
    assert(lantern_ssz_decode_block_body(&decoded, buffer, written) == 0);
    assert(decoded.attestations.length == body.attestations.length);

    for (size_t i = 0; i < body.attestations.length; ++i) {
        assert_aggregated_attestation_equal(&decoded.attestations.data[i], &body.attestations.data[i]);
    }

    lantern_block_body_reset(&body);
    lantern_block_body_reset(&decoded);
}

static void test_block_body_decode_legacy_plain_attestations(void) {
    LanternAttestations legacy_attestations;
    lantern_attestations_init(&legacy_attestations);

    expect_ok(lantern_attestations_resize(&legacy_attestations, 3), "legacy attestation resize");
    legacy_attestations.data[0] = build_signed_vote(2, 5, 0x21).data;
    legacy_attestations.data[1] = build_signed_vote(0, 5, 0x31).data;
    legacy_attestations.data[2] = build_signed_vote(3, 6, 0x41).data;

    uint8_t encoded[1024];
    size_t encoded_len = 0;
    expect_ok(
        encode_legacy_plain_attestation_body(
            &legacy_attestations,
            encoded,
            sizeof(encoded),
            &encoded_len),
        "encode legacy body");

    LanternBlockBody decoded;
    lantern_block_body_init(&decoded);
    expect_ok(lantern_ssz_decode_block_body(&decoded, encoded, encoded_len), "decode legacy body");
    if (decoded.attestations.length != legacy_attestations.length) {
        fprintf(
            stderr,
            "decoded attestation length mismatch (%zu != %zu)\n",
            decoded.attestations.length,
            legacy_attestations.length);
        abort();
    }
    if (decoded.attestations.length > 0 && decoded.attestations.data == NULL) {
        fprintf(stderr, "decoded attestation data missing\n");
        abort();
    }

    for (size_t i = 0; i < legacy_attestations.length; ++i) {
        LanternAggregatedAttestation expected;
        build_aggregated_attestation_from_vote(&legacy_attestations.data[i], &expected);
        assert_aggregated_attestation_equal(&decoded.attestations.data[i], &expected);
        lantern_aggregated_attestation_reset(&expected);
    }

    lantern_attestations_reset(&legacy_attestations);
    lantern_block_body_reset(&decoded);
}

static void test_block_body_hash_mode_is_per_body_decode_layout(void) {
    LanternBlockBody spec_body;
    lantern_block_body_init(&spec_body);

    LanternSignedVote spec_vote = build_signed_vote(1, 9, 0x51);
    LanternAggregatedAttestation spec_agg;
    build_aggregated_attestation_from_vote(&spec_vote.data, &spec_agg);
    expect_ok(
        lantern_aggregated_attestations_append(&spec_body.attestations, &spec_agg),
        "append spec aggregated attestation");
    lantern_aggregated_attestation_reset(&spec_agg);
    assert(spec_body.legacy_plain_attestation_layout == false);

    LanternRoot spec_root_before;
    expect_ok(
        lantern_hash_tree_root_block_body(&spec_body, &spec_root_before),
        "hash spec block body before legacy decode");

    LanternAttestations legacy_attestations;
    lantern_attestations_init(&legacy_attestations);
    expect_ok(lantern_attestations_resize(&legacy_attestations, 1), "legacy attestation resize");
    legacy_attestations.data[0] = build_signed_vote(2, 10, 0x61).data;

    uint8_t legacy_encoded[512];
    size_t legacy_encoded_len = 0;
    expect_ok(
        encode_legacy_plain_attestation_body(
            &legacy_attestations,
            legacy_encoded,
            sizeof(legacy_encoded),
            &legacy_encoded_len),
        "encode legacy body");

    LanternBlockBody legacy_decoded;
    lantern_block_body_init(&legacy_decoded);
    expect_ok(
        lantern_ssz_decode_block_body(&legacy_decoded, legacy_encoded, legacy_encoded_len),
        "decode legacy body");
    assert(legacy_decoded.legacy_plain_attestation_layout == true);

    LanternRoot spec_root_after;
    expect_ok(
        lantern_hash_tree_root_block_body(&spec_body, &spec_root_after),
        "hash spec block body after legacy decode");
    assert(memcmp(spec_root_before.bytes, spec_root_after.bytes, LANTERN_ROOT_SIZE) == 0);

    lantern_block_body_reset(&legacy_decoded);
    lantern_attestations_reset(&legacy_attestations);
    lantern_block_body_reset(&spec_body);
}

static void test_block_roundtrip_preserves_legacy_plain_body_layout(void) {
    LanternAttestations legacy_attestations;
    lantern_attestations_init(&legacy_attestations);
    expect_ok(lantern_attestations_resize(&legacy_attestations, 2), "legacy attestation resize");
    legacy_attestations.data[0] = build_signed_vote(1, 12, 0x71).data;
    legacy_attestations.data[1] = build_signed_vote(3, 13, 0x81).data;

    uint8_t legacy_body_encoded[1024];
    size_t legacy_body_len = 0;
    expect_ok(
        encode_legacy_plain_attestation_body(
            &legacy_attestations,
            legacy_body_encoded,
            sizeof(legacy_body_encoded),
            &legacy_body_len),
        "encode legacy body");

    LanternBlock block;
    memset(&block, 0, sizeof(block));
    block.slot = 77;
    block.proposer_index = 5;
    fill_bytes(block.parent_root.bytes, sizeof(block.parent_root.bytes), 0x11);
    fill_bytes(block.state_root.bytes, sizeof(block.state_root.bytes), 0x22);
    lantern_block_body_init(&block.body);
    expect_ok(
        lantern_ssz_decode_block_body(&block.body, legacy_body_encoded, legacy_body_len),
        "decode legacy body into block");
    assert(block.body.legacy_plain_attestation_layout == true);

    LanternRoot root_before;
    expect_ok(
        lantern_hash_tree_root_block(&block, &root_before),
        "hash block before roundtrip");

    uint8_t encoded_block[2048];
    size_t encoded_block_len = 0;
    expect_ok(
        lantern_ssz_encode_block(&block, encoded_block, sizeof(encoded_block), &encoded_block_len),
        "encode block with legacy body");

    LanternBlock decoded;
    memset(&decoded, 0, sizeof(decoded));
    lantern_block_body_init(&decoded.body);
    expect_ok(
        lantern_ssz_decode_block(&decoded, encoded_block, encoded_block_len),
        "decode block with legacy body");
    assert(decoded.body.legacy_plain_attestation_layout == true);

    LanternRoot root_after;
    expect_ok(
        lantern_hash_tree_root_block(&decoded, &root_after),
        "hash block after roundtrip");
    assert(memcmp(root_before.bytes, root_after.bytes, LANTERN_ROOT_SIZE) == 0);

    lantern_block_body_reset(&decoded.body);
    lantern_block_body_reset(&block.body);
    lantern_attestations_reset(&legacy_attestations);
}

static void populate_block(LanternBlock *block) {
    memset(block, 0, sizeof(*block));
    block->slot = 88;
    block->proposer_index = 12;
    fill_bytes(block->parent_root.bytes, sizeof(block->parent_root.bytes), 0xAA);
    fill_bytes(block->state_root.bytes, sizeof(block->state_root.bytes), 0xBB);
    lantern_block_body_init(&block->body);

    LanternSignedVote vote_a = build_signed_vote(11, 15, 0x70);
    LanternSignedVote vote_b = build_signed_vote(22, 16, 0x80);
    LanternAggregatedAttestation agg_a;
    LanternAggregatedAttestation agg_b;
    build_aggregated_attestation_from_vote(&vote_a.data, &agg_a);
    build_aggregated_attestation_from_vote(&vote_b.data, &agg_b);
    assert(lantern_aggregated_attestations_append(&block->body.attestations, &agg_a) == 0);
    assert(lantern_aggregated_attestations_append(&block->body.attestations, &agg_b) == 0);
    lantern_aggregated_attestation_reset(&agg_a);
    lantern_aggregated_attestation_reset(&agg_b);
}

static void reset_block(LanternBlock *block) {
    lantern_block_body_reset(&block->body);
}

static void reset_signed_block(LanternSignedBlock *block) {
    if (!block) {
        return;
    }
    lantern_signed_block_with_attestation_reset(block);
}

static void expect_block_signatures_equal(
    const LanternBlockSignatures *expected,
    const LanternBlockSignatures *actual) {
    assert(expected->attestation_signatures.length == actual->attestation_signatures.length);
    if (expected->attestation_signatures.length > 0) {
        assert(expected->attestation_signatures.data != NULL);
        assert(actual->attestation_signatures.data != NULL);
        for (size_t i = 0; i < expected->attestation_signatures.length; ++i) {
            assert_signature_proof_equal(
                &expected->attestation_signatures.data[i],
                &actual->attestation_signatures.data[i]);
        }
    }
    assert(memcmp(
               expected->proposer_signature.bytes,
               actual->proposer_signature.bytes,
               LANTERN_SIGNATURE_SIZE)
           == 0);
}

static void build_vote_vector_a(LanternVote *vote) {
    memset(vote, 0, sizeof(*vote));
    vote->validator_id = LANTERN_VECTOR_VOTE_A_VALIDATOR_ID;
    vote->slot = LANTERN_VECTOR_VOTE_A_SLOT;
    vote->head = checkpoint_from_vector(LANTERN_VECTOR_VOTE_A_HEAD_ROOT, LANTERN_VECTOR_VOTE_A_HEAD_SLOT);
    vote->target = checkpoint_from_vector(LANTERN_VECTOR_VOTE_A_TARGET_ROOT, LANTERN_VECTOR_VOTE_A_TARGET_SLOT);
    vote->source = checkpoint_from_vector(LANTERN_VECTOR_VOTE_A_SOURCE_ROOT, LANTERN_VECTOR_VOTE_A_SOURCE_SLOT);
}

static void build_vote_vector_b(LanternVote *vote) {
    memset(vote, 0, sizeof(*vote));
    vote->validator_id = LANTERN_VECTOR_VOTE_B_VALIDATOR_ID;
    vote->slot = LANTERN_VECTOR_VOTE_B_SLOT;
    vote->head = checkpoint_from_vector(LANTERN_VECTOR_VOTE_B_HEAD_ROOT, LANTERN_VECTOR_VOTE_B_HEAD_SLOT);
    vote->target = checkpoint_from_vector(LANTERN_VECTOR_VOTE_B_TARGET_ROOT, LANTERN_VECTOR_VOTE_B_TARGET_SLOT);
    vote->source = checkpoint_from_vector(LANTERN_VECTOR_VOTE_B_SOURCE_ROOT, LANTERN_VECTOR_VOTE_B_SOURCE_SLOT);
}

static void build_signed_vote_vector_a(LanternSignedVote *signed_vote) {
    memset(signed_vote, 0, sizeof(*signed_vote));
    build_vote_vector_a(&signed_vote->data);
    signed_vote->data.validator_id = LANTERN_VECTOR_VOTE_A_VALIDATOR_ID;
    fill_signature(&signed_vote->signature, 0xA5);
}

static void build_signed_vote_vector_b(LanternSignedVote *signed_vote) {
    memset(signed_vote, 0, sizeof(*signed_vote));
    build_vote_vector_b(&signed_vote->data);
    signed_vote->data.validator_id = LANTERN_VECTOR_VOTE_B_VALIDATOR_ID;
    fill_signature(&signed_vote->signature, 0xB5);
}

static void build_block_header_vector(LanternBlockHeader *header) {
    memset(header, 0, sizeof(*header));
    header->slot = LANTERN_VECTOR_BLOCK_HEADER_SLOT;
    header->proposer_index = LANTERN_VECTOR_BLOCK_HEADER_PROPOSER;
    copy_root(&header->parent_root, LANTERN_VECTOR_BLOCK_HEADER_PARENT_ROOT);
    copy_root(&header->state_root, LANTERN_VECTOR_BLOCK_HEADER_STATE_ROOT);
    copy_root(&header->body_root, LANTERN_VECTOR_BLOCK_HEADER_BODY_ROOT);
}

static void build_block_body_vector(LanternBlockBody *body) {
    lantern_block_body_init(body);
    LanternSignedVote vote_a;
    build_signed_vote_vector_a(&vote_a);
    LanternAggregatedAttestation agg_a;
    build_aggregated_attestation_from_vote(&vote_a.data, &agg_a);
    expect_ok(lantern_aggregated_attestations_append(&body->attestations, &agg_a), "append vote A");
    lantern_aggregated_attestation_reset(&agg_a);

    LanternSignedVote vote_b;
    build_signed_vote_vector_b(&vote_b);
    LanternAggregatedAttestation agg_b;
    build_aggregated_attestation_from_vote(&vote_b.data, &agg_b);
    expect_ok(lantern_aggregated_attestations_append(&body->attestations, &agg_b), "append vote B");
    lantern_aggregated_attestation_reset(&agg_b);
}

static void build_block_vector(LanternBlock *block) {
    memset(block, 0, sizeof(*block));
    block->slot = LANTERN_VECTOR_BLOCK_HEADER_SLOT;
    block->proposer_index = LANTERN_VECTOR_BLOCK_HEADER_PROPOSER;
    copy_root(&block->parent_root, LANTERN_VECTOR_BLOCK_HEADER_PARENT_ROOT);
    copy_root(&block->state_root, LANTERN_VECTOR_BLOCK_HEADER_STATE_ROOT);
    lantern_block_body_init(&block->body);
    build_block_body_vector(&block->body);
}

static void build_signed_block_vector(LanternSignedBlock *signed_block) {
    lantern_signed_block_with_attestation_init(signed_block);
    build_block_vector(&signed_block->message.block);

    LanternSignedVote proposer;
    build_signed_vote_vector_a(&proposer);
    signed_block->message.proposer_attestation = proposer.data;

    size_t attestation_count = signed_block->message.block.body.attestations.length;
    expect_ok(
        lantern_attestation_signatures_resize(&signed_block->signatures.attestation_signatures, attestation_count),
        "resize block signatures");
    for (size_t i = 0; i < attestation_count; ++i) {
        LanternAggregatedSignatureProof *proof = &signed_block->signatures.attestation_signatures.data[i];
        const LanternAggregatedAttestation *attestation = &signed_block->message.block.body.attestations.data[i];
        expect_ok(
            lantern_bitlist_resize(&proof->participants, attestation->aggregation_bits.bit_length),
            "resize proof participants");
        size_t byte_len = (attestation->aggregation_bits.bit_length + 7u) / 8u;
        if (byte_len > 0) {
            memcpy(proof->participants.bytes, attestation->aggregation_bits.bytes, byte_len);
        }
        size_t proof_len = 4u + i;
        fill_proof_data(proof, (uint8_t)(0xC0u + (i * 0x10u)), proof_len);
    }
    signed_block->signatures.proposer_signature = proposer.signature;
}

static void build_state_vector(LanternState *state) {
    lantern_state_init(state);
    state->config.num_validators = LANTERN_VECTOR_CONFIG_NUM_VALIDATORS;
    state->config.genesis_time = LANTERN_VECTOR_CONFIG_GENESIS_TIME;
    state->slot = LANTERN_VECTOR_STATE_SLOT;
    build_block_header_vector(&state->latest_block_header);
    state->latest_justified = checkpoint_from_vector(
        LANTERN_VECTOR_CHECKPOINT_JUSTIFIED_ROOT,
        LANTERN_VECTOR_CHECKPOINT_JUSTIFIED_SLOT);
    state->latest_finalized = checkpoint_from_vector(
        LANTERN_VECTOR_CHECKPOINT_FINALIZED_ROOT,
        LANTERN_VECTOR_CHECKPOINT_FINALIZED_SLOT);

    expect_ok(lantern_root_list_resize(&state->historical_block_hashes, LANTERN_VECTOR_STATE_HISTORICAL_ROOTS_COUNT),
              "historical roots resize");
    if (state->historical_block_hashes.length >= 2) {
        copy_root(&state->historical_block_hashes.items[0], LANTERN_VECTOR_STATE_HISTORICAL_ROOT_0);
        copy_root(&state->historical_block_hashes.items[1], LANTERN_VECTOR_STATE_HISTORICAL_ROOT_1);
    }

    expect_ok(lantern_bitlist_resize(&state->justified_slots, LANTERN_VECTOR_STATE_JUSTIFIED_SLOTS_BITS),
              "justified slots resize");
    size_t justified_bytes = (LANTERN_VECTOR_STATE_JUSTIFIED_SLOTS_BITS + 7) / 8;
    memcpy(state->justified_slots.bytes, LANTERN_VECTOR_STATE_JUSTIFIED_SLOTS_BYTES, justified_bytes);

    expect_ok(lantern_root_list_resize(&state->justification_roots, LANTERN_VECTOR_STATE_JUSTIFICATION_ROOTS_COUNT),
              "justification roots resize");
    copy_root(&state->justification_roots.items[0], LANTERN_VECTOR_STATE_JUSTIFICATION_ROOT_0);

    expect_ok(lantern_bitlist_resize(
                  &state->justification_validators,
                  LANTERN_VECTOR_STATE_JUSTIFICATION_VALIDATORS_BITS),
              "justification validators resize");
    size_t validators_bytes = (LANTERN_VECTOR_STATE_JUSTIFICATION_VALIDATORS_BITS + 7) / 8;
    memcpy(state->justification_validators.bytes,
           LANTERN_VECTOR_STATE_JUSTIFICATION_VALIDATORS_BYTES,
           validators_bytes);

    size_t validator_count = (size_t)LANTERN_VECTOR_CONFIG_NUM_VALIDATORS;
    uint8_t validator_pubkeys[LANTERN_VALIDATOR_PUBKEY_SIZE * LANTERN_VECTOR_CONFIG_NUM_VALIDATORS];
    for (size_t i = 0; i < validator_count; ++i) {
        uint8_t seed = (uint8_t)(0x90 + (i * 0x10));
        fill_bytes(
            validator_pubkeys + (i * LANTERN_VALIDATOR_PUBKEY_SIZE),
            LANTERN_VALIDATOR_PUBKEY_SIZE,
            seed);
    }
    expect_ok(
        lantern_state_set_validator_pubkeys(state, validator_pubkeys, validator_count),
        "set validator pubkeys");
}
static void test_block_roundtrip(void) {
    LanternBlock block;
    populate_block(&block);

    uint8_t buffer[SIGNED_BLOCK_TEST_BUFFER_SIZE];
    size_t written = 0;
    assert(lantern_ssz_encode_block(&block, buffer, sizeof(buffer), &written) == 0);
    maybe_dump_vector("LANTERN_DUMP_SSZ_BLOCK", "LANTERN_SSZ_VECTOR_BLOCK", buffer, written);

    LanternBlock decoded;
    memset(&decoded, 0, sizeof(decoded));
    lantern_block_body_init(&decoded.body);
    assert(lantern_ssz_decode_block(&decoded, buffer, written) == 0);

    assert(decoded.slot == block.slot);
    assert(decoded.proposer_index == block.proposer_index);
    assert(memcmp(decoded.parent_root.bytes, block.parent_root.bytes, LANTERN_ROOT_SIZE) == 0);
    assert(memcmp(decoded.state_root.bytes, block.state_root.bytes, LANTERN_ROOT_SIZE) == 0);
    assert(decoded.body.attestations.length == block.body.attestations.length);

    for (size_t i = 0; i < block.body.attestations.length; ++i) {
        assert_aggregated_attestation_equal(&decoded.body.attestations.data[i], &block.body.attestations.data[i]);
    }

    reset_block(&block);
    reset_block(&decoded);
}

static void test_signed_block_roundtrip(void) {
    LanternSignedBlock signed_block;
    lantern_signed_block_with_attestation_init(&signed_block);
    populate_block(&signed_block.message.block);

    uint8_t buffer[SIGNED_BLOCK_TEST_BUFFER_SIZE];
    size_t written = 0;
    assert(lantern_ssz_encode_signed_block(&signed_block, buffer, sizeof(buffer), &written) == 0);

    LanternSignedBlock decoded;
    lantern_signed_block_with_attestation_init(&decoded);
    assert(lantern_ssz_decode_signed_block(&decoded, buffer, written) == 0);

    assert(decoded.message.block.slot == signed_block.message.block.slot);
    expect_block_signatures_equal(&signed_block.signatures, &decoded.signatures);
    assert(decoded.message.block.body.attestations.length
           == signed_block.message.block.body.attestations.length);

    reset_signed_block(&signed_block);
    reset_signed_block(&decoded);
}

static void test_signed_block_signature_validation(void) {
    LanternSignedBlock signed_block;
    lantern_signed_block_with_attestation_init(&signed_block);
    populate_block(&signed_block.message.block);

    uint8_t buffer[SIGNED_BLOCK_TEST_BUFFER_SIZE];
    size_t written = 0;
    assert(lantern_ssz_encode_signed_block(&signed_block, buffer, sizeof(buffer), &written) == 0);

    LanternSignedBlock decoded;
    lantern_signed_block_with_attestation_init(&decoded);
    buffer[sizeof(uint32_t)] = 0x5A; /* corrupt message offset */
    assert(lantern_ssz_decode_signed_block(&decoded, buffer, written) != 0);
    reset_signed_block(&decoded);

    signed_block.signatures.attestation_signatures.length = LANTERN_MAX_BLOCK_SIGNATURES + 2;
    signed_block.signatures.attestation_signatures.data = NULL;
    assert(lantern_ssz_encode_signed_block(&signed_block, buffer, sizeof(buffer), &written) != 0);

    reset_signed_block(&signed_block);
}

static void test_signed_block_decode_without_signature_section(void) {
    LanternSignedBlock signed_block;
    lantern_signed_block_with_attestation_init(&signed_block);
    populate_block(&signed_block.message.block);

    uint8_t message_buf[SIGNED_BLOCK_TEST_BUFFER_SIZE];
    size_t message_written = 0;
    assert(lantern_ssz_encode_block(
               &signed_block.message.block,
               message_buf,
               sizeof(message_buf),
               &message_written)
           == 0);

    size_t encoded_len = (sizeof(uint32_t) * 2u) + message_written;
    uint8_t *encoded = malloc(encoded_len);
    assert(encoded != NULL);

    uint32_t message_offset = (uint32_t)(sizeof(uint32_t) * 2u);
    memcpy(encoded, &message_offset, sizeof(message_offset));
    uint32_t signatures_offset = message_offset + (uint32_t)message_written;
    memcpy(encoded + sizeof(uint32_t), &signatures_offset, sizeof(signatures_offset));
    memcpy(encoded + (sizeof(uint32_t) * 2u), message_buf, message_written);

    LanternSignedBlock decoded;
    lantern_signed_block_with_attestation_init(&decoded);
    assert(lantern_ssz_decode_signed_block(&decoded, encoded, encoded_len) != 0);

    reset_signed_block(&signed_block);
    reset_signed_block(&decoded);
    free(encoded);
}

static uint32_t read_u32_le_test(const uint8_t *data) {
    return ((uint32_t)data[0])
        | ((uint32_t)data[1] << 8u)
        | ((uint32_t)data[2] << 16u)
        | ((uint32_t)data[3] << 24u);
}

static void test_signed_block_decode_attestation_signatures_only(void) {
    LanternSignedBlock signed_block;
    build_signed_block_vector(&signed_block);

    uint8_t encoded[SIGNED_BLOCK_TEST_BUFFER_SIZE];
    size_t encoded_len = 0;
    expect_ok(
        lantern_ssz_encode_signed_block(&signed_block, encoded, sizeof(encoded), &encoded_len),
        "encode signed block");

    uint32_t message_offset = read_u32_le_test(encoded);
    uint32_t signatures_offset = read_u32_le_test(encoded + sizeof(uint32_t));
    if (message_offset < (sizeof(uint32_t) * 2u) || signatures_offset < message_offset || signatures_offset > encoded_len) {
        fprintf(stderr, "invalid signed block offsets in test fixture\n");
        abort();
    }

    const uint8_t *signatures = encoded + signatures_offset;
    size_t signatures_len = encoded_len - signatures_offset;
    if (signatures_len < (sizeof(uint32_t) * 2u)) {
        fprintf(stderr, "signature section too short in test fixture\n");
        abort();
    }
    uint32_t att_offset = read_u32_le_test(signatures);
    uint32_t proposer_offset = read_u32_le_test(signatures + sizeof(uint32_t));
    if (att_offset != (sizeof(uint32_t) * 2u) || proposer_offset < att_offset || proposer_offset > signatures_len) {
        fprintf(stderr, "invalid signature subsection offsets in test fixture\n");
        abort();
    }

    size_t attestation_sigs_len = proposer_offset - att_offset;
    size_t attestation_only_len = signatures_offset + attestation_sigs_len;
    uint8_t *attestation_only = malloc(attestation_only_len);
    if (!attestation_only) {
        fprintf(stderr, "allocation failed in attestation-only decode test\n");
        abort();
    }
    memcpy(attestation_only, encoded, signatures_offset);
    if (attestation_sigs_len > 0) {
        memcpy(attestation_only + signatures_offset, signatures + att_offset, attestation_sigs_len);
    }

    LanternSignedBlock decoded;
    lantern_signed_block_with_attestation_init(&decoded);
    expect_ok(
        lantern_ssz_decode_signed_block(&decoded, attestation_only, attestation_only_len),
        "decode attestation-only signed block");

    if (decoded.signatures.attestation_signatures.length != signed_block.signatures.attestation_signatures.length) {
        fprintf(
            stderr,
            "attestation signature count mismatch (%zu != %zu)\n",
            decoded.signatures.attestation_signatures.length,
            signed_block.signatures.attestation_signatures.length);
        abort();
    }
    for (size_t i = 0; i < signed_block.signatures.attestation_signatures.length; ++i) {
        assert_signature_proof_equal(
            &decoded.signatures.attestation_signatures.data[i],
            &signed_block.signatures.attestation_signatures.data[i]);
    }

    for (size_t i = 0; i < LANTERN_SIGNATURE_SIZE; ++i) {
        if (decoded.signatures.proposer_signature.bytes[i] != 0) {
            fprintf(stderr, "expected zero proposer signature byte at %zu\n", i);
            abort();
        }
    }

    reset_signed_block(&decoded);
    reset_signed_block(&signed_block);
    free(attestation_only);
}

static void test_signed_block_decode_attestation_signatures_only_empty(void) {
    LanternSignedBlock signed_block;
    lantern_signed_block_with_attestation_init(&signed_block);
    signed_block.message.block.slot = 7;
    signed_block.message.block.proposer_index = 1;
    fill_bytes(signed_block.message.block.parent_root.bytes, LANTERN_ROOT_SIZE, 0x11);
    fill_bytes(signed_block.message.block.state_root.bytes, LANTERN_ROOT_SIZE, 0x22);

    uint8_t encoded[SIGNED_BLOCK_TEST_BUFFER_SIZE];
    size_t encoded_len = 0;
    expect_ok(
        lantern_ssz_encode_signed_block(&signed_block, encoded, sizeof(encoded), &encoded_len),
        "encode signed block empty signatures");

    uint32_t signatures_offset = read_u32_le_test(encoded + sizeof(uint32_t));
    if (signatures_offset > encoded_len) {
        fprintf(stderr, "invalid signatures offset for empty signatures test\n");
        abort();
    }

    /* Old layout: signatures section is an empty attestation_signatures list. */
    size_t attestation_only_len = signatures_offset;

    LanternSignedBlock decoded;
    lantern_signed_block_with_attestation_init(&decoded);
    expect_ok(
        lantern_ssz_decode_signed_block(&decoded, encoded, attestation_only_len),
        "decode attestation-only empty signature section");

    if (decoded.signatures.attestation_signatures.length != 0) {
        fprintf(stderr, "expected no attestation signatures in empty layout decode\n");
        abort();
    }
    for (size_t i = 0; i < LANTERN_SIGNATURE_SIZE; ++i) {
        if (decoded.signatures.proposer_signature.bytes[i] != 0) {
            fprintf(stderr, "expected zero proposer signature for empty layout decode\n");
            abort();
        }
    }

    reset_signed_block(&decoded);
    reset_signed_block(&signed_block);
}

static void test_state_roundtrip(void) {
    LanternState state;
    lantern_state_init(&state);
    state.config.num_validators = 64;
    state.config.genesis_time = 123456789;
    state.slot = 42;
    state.latest_block_header.slot = 41;
    state.latest_block_header.proposer_index = 3;
    fill_bytes(state.latest_block_header.parent_root.bytes, sizeof(state.latest_block_header.parent_root.bytes), 0xA1);
    fill_bytes(state.latest_block_header.state_root.bytes, sizeof(state.latest_block_header.state_root.bytes), 0xA2);
    fill_bytes(state.latest_block_header.body_root.bytes, sizeof(state.latest_block_header.body_root.bytes), 0xA3);
    state.latest_justified = build_checkpoint(0xB1, 30);
    state.latest_finalized = build_checkpoint(0xC1, 28);

    expect_ok(lantern_root_list_resize(&state.historical_block_hashes, 2), "historical hashes resize");
    fill_bytes(state.historical_block_hashes.items[0].bytes, LANTERN_ROOT_SIZE, 0xD1);
    fill_bytes(state.historical_block_hashes.items[1].bytes, LANTERN_ROOT_SIZE, 0xD2);

    expect_ok(lantern_bitlist_resize(&state.justified_slots, 6), "justified slots resize");
    bitlist_set(&state.justified_slots, 1, true);
    bitlist_set(&state.justified_slots, 4, true);

    expect_ok(lantern_root_list_resize(&state.justification_roots, 1), "justification roots resize");
    fill_bytes(state.justification_roots.items[0].bytes, LANTERN_ROOT_SIZE, 0xE1);

    expect_ok(lantern_bitlist_resize(&state.justification_validators, 10), "justification validators resize");
    bitlist_set(&state.justification_validators, 0, true);
    bitlist_set(&state.justification_validators, 9, true);

    uint8_t buffer[8192];
    size_t written = 0;
    assert(lantern_ssz_encode_state(&state, buffer, sizeof(buffer), &written) == 0);

    LanternState decoded;
    lantern_state_init(&decoded);
    assert(lantern_ssz_decode_state(&decoded, buffer, written) == 0);

    assert(decoded.config.num_validators == state.config.num_validators);
    assert(decoded.config.genesis_time == state.config.genesis_time);
    assert(decoded.slot == state.slot);
    assert(decoded.latest_block_header.proposer_index == state.latest_block_header.proposer_index);
    assert(memcmp(decoded.latest_block_header.parent_root.bytes,
                  state.latest_block_header.parent_root.bytes,
                  LANTERN_ROOT_SIZE)
           == 0);
    assert(decoded.latest_justified.slot == state.latest_justified.slot);
    assert(decoded.latest_finalized.slot == state.latest_finalized.slot);
    assert(decoded.historical_block_hashes.length == state.historical_block_hashes.length);
    assert(memcmp(decoded.historical_block_hashes.items[1].bytes,
                  state.historical_block_hashes.items[1].bytes,
                  LANTERN_ROOT_SIZE)
           == 0);
    assert(decoded.justified_slots.bit_length == state.justified_slots.bit_length);
    assert(decoded.justification_roots.length == state.justification_roots.length);
    assert(decoded.justification_validators.bit_length == state.justification_validators.bit_length);

    lantern_state_reset(&state);
    lantern_state_reset(&decoded);
}

static void test_leanspec_vectors(void) {
    /* Config */
    LanternConfig cfg_expected = {
        .num_validators = LANTERN_VECTOR_CONFIG_NUM_VALIDATORS,
        .genesis_time = LANTERN_VECTOR_CONFIG_GENESIS_TIME,
    };

    uint8_t cfg_encoded[sizeof(LANTERN_SSZ_VECTOR_CONFIG)];
    size_t written = 0;
    expect_ok(lantern_ssz_encode_config(&cfg_expected, cfg_encoded, sizeof(cfg_encoded), &written), "config encode");
    g_current_test = "leanspec_config";
    expect_bytes_equal(LANTERN_SSZ_VECTOR_CONFIG, sizeof(LANTERN_SSZ_VECTOR_CONFIG), cfg_encoded, written);

    LanternConfig cfg_decoded = {0};
    expect_ok(lantern_ssz_decode_config(&cfg_decoded,
                                        LANTERN_SSZ_VECTOR_CONFIG,
                                        sizeof(LANTERN_SSZ_VECTOR_CONFIG)),
              "config decode");
    assert(cfg_decoded.genesis_time == cfg_expected.genesis_time);
    /* num_validators is not part of SSZ config - derived from validators list */

    /* Checkpoint */
    LanternCheckpoint checkpoint_expected = checkpoint_from_vector(
        LANTERN_VECTOR_CHECKPOINT_JUSTIFIED_ROOT,
        LANTERN_VECTOR_CHECKPOINT_JUSTIFIED_SLOT);
    uint8_t checkpoint_encoded[LANTERN_CHECKPOINT_SSZ_SIZE];
    written = 0;
    expect_ok(lantern_ssz_encode_checkpoint(&checkpoint_expected,
                                            checkpoint_encoded,
                                            sizeof(checkpoint_encoded),
                                            &written),
              "checkpoint encode");
    g_current_test = "leanspec_checkpoint";
    expect_bytes_equal(LANTERN_SSZ_VECTOR_CHECKPOINT_JUSTIFIED,
                       sizeof(LANTERN_SSZ_VECTOR_CHECKPOINT_JUSTIFIED),
                       checkpoint_encoded,
                       written);
    LanternCheckpoint checkpoint_decoded = {0};
    expect_ok(lantern_ssz_decode_checkpoint(&checkpoint_decoded,
                                            LANTERN_SSZ_VECTOR_CHECKPOINT_JUSTIFIED,
                                            sizeof(LANTERN_SSZ_VECTOR_CHECKPOINT_JUSTIFIED)),
              "checkpoint decode");
    assert_checkpoint_equal(&checkpoint_decoded, &checkpoint_expected);

    /* Votes */
    LanternVote vote_a_expected;
    build_vote_vector_a(&vote_a_expected);
    uint8_t vote_a_encoded[sizeof(LANTERN_SSZ_VECTOR_VOTE_A)];
    written = 0;
    expect_ok(lantern_ssz_encode_vote(&vote_a_expected, vote_a_encoded, sizeof(vote_a_encoded), &written),
              "vote A encode");
    g_current_test = "leanspec_vote_a";
    expect_bytes_equal(LANTERN_SSZ_VECTOR_VOTE_A,
                       sizeof(LANTERN_SSZ_VECTOR_VOTE_A),
                       vote_a_encoded,
                       written);
    LanternVote vote_a_decoded = {0};
    expect_ok(lantern_ssz_decode_vote(&vote_a_decoded,
                                      LANTERN_SSZ_VECTOR_VOTE_A,
                                      sizeof(LANTERN_SSZ_VECTOR_VOTE_A)),
              "vote A decode");
    assert_vote_equal(&vote_a_decoded, &vote_a_expected);

    LanternVote vote_b_expected;
    build_vote_vector_b(&vote_b_expected);
    uint8_t vote_b_encoded[sizeof(LANTERN_SSZ_VECTOR_VOTE_B)];
    written = 0;
    expect_ok(lantern_ssz_encode_vote(&vote_b_expected, vote_b_encoded, sizeof(vote_b_encoded), &written),
              "vote B encode");
    g_current_test = "leanspec_vote_b";
    expect_bytes_equal(LANTERN_SSZ_VECTOR_VOTE_B,
                       sizeof(LANTERN_SSZ_VECTOR_VOTE_B),
                       vote_b_encoded,
                       written);
    LanternVote vote_b_decoded = {0};
    expect_ok(lantern_ssz_decode_vote(&vote_b_decoded,
                                      LANTERN_SSZ_VECTOR_VOTE_B,
                                      sizeof(LANTERN_SSZ_VECTOR_VOTE_B)),
              "vote B decode");
    assert_vote_equal(&vote_b_decoded, &vote_b_expected);

    /* Signed votes */
    LanternSignedVote signed_vote_a_expected;
    build_signed_vote_vector_a(&signed_vote_a_expected);
    uint8_t signed_vote_a_encoded[LANTERN_SIGNED_VOTE_SSZ_SIZE];
    uint8_t signed_vote_a_encoded_legacy[LANTERN_SIGNED_VOTE_SSZ_SIZE_LEGACY];
    written = 0;
    expect_ok(lantern_ssz_encode_signed_vote(&signed_vote_a_expected,
                                             signed_vote_a_encoded,
                                             sizeof(signed_vote_a_encoded),
                                             &written),
              "signed vote A encode");
    size_t legacy_written = 0;
    expect_ok(lantern_ssz_encode_signed_vote_legacy(
                  &signed_vote_a_expected,
                  signed_vote_a_encoded_legacy,
                  sizeof(signed_vote_a_encoded_legacy),
                  &legacy_written),
              "signed vote A legacy encode");
    maybe_dump_vector("LANTERN_DUMP_SSZ_SIGNED_VOTE_A", "LANTERN_SSZ_VECTOR_SIGNED_VOTE_A", signed_vote_a_encoded, written);
    g_current_test = "leanspec_signed_vote_a";
    expect_bytes_equal_or_legacy(LANTERN_SSZ_VECTOR_SIGNED_VOTE_A,
                                 sizeof(LANTERN_SSZ_VECTOR_SIGNED_VOTE_A),
                                 signed_vote_a_encoded,
                                 written,
                                 signed_vote_a_encoded_legacy,
                                 legacy_written);
    LanternSignedVote signed_vote_a_decoded = {0};
    expect_ok(lantern_ssz_decode_signed_vote(&signed_vote_a_decoded,
                                             LANTERN_SSZ_VECTOR_SIGNED_VOTE_A,
                                             sizeof(LANTERN_SSZ_VECTOR_SIGNED_VOTE_A)),
              "signed vote A decode");
    assert_signed_vote_equal(&signed_vote_a_decoded, &signed_vote_a_expected);

    LanternSignedVote signed_vote_b_expected;
    build_signed_vote_vector_b(&signed_vote_b_expected);
    uint8_t signed_vote_b_encoded[LANTERN_SIGNED_VOTE_SSZ_SIZE];
    uint8_t signed_vote_b_encoded_legacy[LANTERN_SIGNED_VOTE_SSZ_SIZE_LEGACY];
    written = 0;
    expect_ok(lantern_ssz_encode_signed_vote(&signed_vote_b_expected,
                                             signed_vote_b_encoded,
                                             sizeof(signed_vote_b_encoded),
                                             &written),
              "signed vote B encode");
    legacy_written = 0;
    expect_ok(lantern_ssz_encode_signed_vote_legacy(
                  &signed_vote_b_expected,
                  signed_vote_b_encoded_legacy,
                  sizeof(signed_vote_b_encoded_legacy),
                  &legacy_written),
              "signed vote B legacy encode");
    maybe_dump_vector("LANTERN_DUMP_SSZ_SIGNED_VOTE_B", "LANTERN_SSZ_VECTOR_SIGNED_VOTE_B", signed_vote_b_encoded, written);
    g_current_test = "leanspec_signed_vote_b";
    expect_bytes_equal_or_legacy(LANTERN_SSZ_VECTOR_SIGNED_VOTE_B,
                                 sizeof(LANTERN_SSZ_VECTOR_SIGNED_VOTE_B),
                                 signed_vote_b_encoded,
                                 written,
                                 signed_vote_b_encoded_legacy,
                                 legacy_written);
    LanternSignedVote signed_vote_b_decoded = {0};
    expect_ok(lantern_ssz_decode_signed_vote(&signed_vote_b_decoded,
                                             LANTERN_SSZ_VECTOR_SIGNED_VOTE_B,
                                             sizeof(LANTERN_SSZ_VECTOR_SIGNED_VOTE_B)),
              "signed vote B decode");
    assert_signed_vote_equal(&signed_vote_b_decoded, &signed_vote_b_expected);

    /* Block header */
    LanternBlockHeader header_expected;
    build_block_header_vector(&header_expected);
    uint8_t header_encoded[sizeof(LANTERN_SSZ_VECTOR_BLOCK_HEADER)];
    written = 0;
    expect_ok(lantern_ssz_encode_block_header(&header_expected,
                                              header_encoded,
                                              sizeof(header_encoded),
                                              &written),
              "block header encode");
    maybe_dump_vector(
        "LANTERN_DUMP_SSZ_BLOCK_HEADER_ACTUAL",
        "LANTERN_SSZ_VECTOR_BLOCK_HEADER",
        header_encoded,
        written);
    g_current_test = "leanspec_block_header";
    expect_bytes_equal(LANTERN_SSZ_VECTOR_BLOCK_HEADER,
                       sizeof(LANTERN_SSZ_VECTOR_BLOCK_HEADER),
                       header_encoded,
                       written);
    LanternBlockHeader header_decoded = {0};
    expect_ok(lantern_ssz_decode_block_header(&header_decoded,
                                              LANTERN_SSZ_VECTOR_BLOCK_HEADER,
                                              sizeof(LANTERN_SSZ_VECTOR_BLOCK_HEADER)),
              "block header decode");
    assert(header_decoded.slot == header_expected.slot);
    assert(header_decoded.proposer_index == header_expected.proposer_index);
    assert(memcmp(header_decoded.parent_root.bytes, header_expected.parent_root.bytes, LANTERN_ROOT_SIZE) == 0);
    assert(memcmp(header_decoded.state_root.bytes, header_expected.state_root.bytes, LANTERN_ROOT_SIZE) == 0);
    assert(memcmp(header_decoded.body_root.bytes, header_expected.body_root.bytes, LANTERN_ROOT_SIZE) == 0);

    /* Block body */
    LanternBlockBody body_expected;
    build_block_body_vector(&body_expected);
    uint8_t body_encoded[sizeof(LANTERN_SSZ_VECTOR_BLOCK_BODY)];
    written = 0;
    expect_ok(lantern_ssz_encode_block_body(&body_expected, body_encoded, sizeof(body_encoded), &written),
              "block body encode");
    maybe_dump_vector(
        "LANTERN_DUMP_SSZ_BLOCK_BODY_ACTUAL",
        "LANTERN_SSZ_VECTOR_BLOCK_BODY",
        body_encoded,
        written);
    g_current_test = "leanspec_block_body";
    expect_bytes_equal(LANTERN_SSZ_VECTOR_BLOCK_BODY,
                       sizeof(LANTERN_SSZ_VECTOR_BLOCK_BODY),
                       body_encoded,
                       written);
    LanternBlockBody body_decoded;
    lantern_block_body_init(&body_decoded);
    expect_ok(lantern_ssz_decode_block_body(&body_decoded,
                                            LANTERN_SSZ_VECTOR_BLOCK_BODY,
                                            sizeof(LANTERN_SSZ_VECTOR_BLOCK_BODY)),
              "block body decode");
    assert(body_decoded.attestations.length == LANTERN_VECTOR_BLOCK_BODY_ATTESTATION_COUNT);
    LanternAggregatedAttestation agg_a_expected;
    LanternAggregatedAttestation agg_b_expected;
    build_aggregated_attestation_from_vote(&signed_vote_a_expected.data, &agg_a_expected);
    build_aggregated_attestation_from_vote(&signed_vote_b_expected.data, &agg_b_expected);
    assert_aggregated_attestation_equal(&body_decoded.attestations.data[0], &agg_a_expected);
    assert_aggregated_attestation_equal(&body_decoded.attestations.data[1], &agg_b_expected);

    /* Block */
    LanternBlock block_expected;
    build_block_vector(&block_expected);
    uint8_t block_encoded[sizeof(LANTERN_SSZ_VECTOR_BLOCK)];
    written = 0;
    expect_ok(lantern_ssz_encode_block(&block_expected, block_encoded, sizeof(block_encoded), &written), "block encode");
    maybe_dump_vector(
        "LANTERN_DUMP_SSZ_BLOCK_ACTUAL",
        "LANTERN_SSZ_VECTOR_BLOCK",
        block_encoded,
        written);
    g_current_test = "leanspec_block";
    expect_bytes_equal(LANTERN_SSZ_VECTOR_BLOCK, sizeof(LANTERN_SSZ_VECTOR_BLOCK), block_encoded, written);
    LanternBlock block_decoded;
    memset(&block_decoded, 0, sizeof(block_decoded));
    lantern_block_body_init(&block_decoded.body);
    expect_ok(lantern_ssz_decode_block(&block_decoded,
                                       LANTERN_SSZ_VECTOR_BLOCK,
                                       sizeof(LANTERN_SSZ_VECTOR_BLOCK)),
              "block decode");
    assert(block_decoded.slot == block_expected.slot);
    assert(block_decoded.proposer_index == block_expected.proposer_index);
    assert(memcmp(block_decoded.parent_root.bytes, block_expected.parent_root.bytes, LANTERN_ROOT_SIZE) == 0);
    assert(memcmp(block_decoded.state_root.bytes, block_expected.state_root.bytes, LANTERN_ROOT_SIZE) == 0);
    assert(block_decoded.body.attestations.length == block_expected.body.attestations.length);
    assert_aggregated_attestation_equal(&block_decoded.body.attestations.data[0], &agg_a_expected);
    assert_aggregated_attestation_equal(&block_decoded.body.attestations.data[1], &agg_b_expected);

    /* Signed block */
    LanternSignedBlock signed_block_expected;
    build_signed_block_vector(&signed_block_expected);
    uint8_t signed_block_encoded[SIGNED_BLOCK_TEST_BUFFER_SIZE];
    written = 0;
    expect_ok(lantern_ssz_encode_signed_block(&signed_block_expected,
                                              signed_block_encoded,
                                              sizeof(signed_block_encoded),
                                              &written),
              "signed block encode");
    uint8_t signed_block_encoded_legacy[SIGNED_BLOCK_TEST_BUFFER_SIZE];
    size_t legacy_block_written = 0;
    expect_ok(lantern_ssz_encode_signed_block_legacy(
                  &signed_block_expected,
                  signed_block_encoded_legacy,
                  sizeof(signed_block_encoded_legacy),
                  &legacy_block_written),
              "signed block legacy encode");
    maybe_dump_vector(
        "LANTERN_DUMP_SSZ_SIGNED_BLOCK",
        "LANTERN_SSZ_VECTOR_SIGNED_BLOCK",
        signed_block_encoded,
        written);
    g_current_test = "leanspec_signed_block";
    expect_bytes_equal_or_legacy(LANTERN_SSZ_VECTOR_SIGNED_BLOCK,
                                 sizeof(LANTERN_SSZ_VECTOR_SIGNED_BLOCK),
                                 signed_block_encoded,
                                 written,
                                 signed_block_encoded_legacy,
                                 legacy_block_written);
    LanternSignedBlock signed_block_decoded;
    lantern_signed_block_with_attestation_init(&signed_block_decoded);
    expect_ok(lantern_ssz_decode_signed_block(&signed_block_decoded,
                                              LANTERN_SSZ_VECTOR_SIGNED_BLOCK,
                                              sizeof(LANTERN_SSZ_VECTOR_SIGNED_BLOCK)),
              "signed block decode");
    expect_block_signatures_equal(&signed_block_expected.signatures, &signed_block_decoded.signatures);
    assert(signed_block_decoded.message.block.body.attestations.length
           == signed_block_expected.message.block.body.attestations.length);
    assert_aggregated_attestation_equal(
        &signed_block_decoded.message.block.body.attestations.data[0],
        &agg_a_expected);
    assert_aggregated_attestation_equal(
        &signed_block_decoded.message.block.body.attestations.data[1],
        &agg_b_expected);

    /* State */
    g_current_test = "state_encode";
    LanternState state_expected;
    build_state_vector(&state_expected);
    uint8_t state_encoded[sizeof(LANTERN_SSZ_VECTOR_STATE)];
    written = 0;
    expect_ok(lantern_ssz_encode_state(&state_expected, state_encoded, sizeof(state_encoded), &written), "state encode");
    maybe_dump_state_vector(state_encoded, written);
    assert(written == sizeof(LANTERN_SSZ_VECTOR_STATE));
    g_current_test = "leanspec_state";
    expect_bytes_equal(LANTERN_SSZ_VECTOR_STATE, sizeof(LANTERN_SSZ_VECTOR_STATE), state_encoded, written);

    LanternState state_decoded;
    lantern_state_init(&state_decoded);
    expect_ok(lantern_ssz_decode_state(&state_decoded,
                                       LANTERN_SSZ_VECTOR_STATE,
                                       sizeof(LANTERN_SSZ_VECTOR_STATE)),
              "state decode");
    assert(state_decoded.config.num_validators == state_expected.config.num_validators);
    assert(state_decoded.config.genesis_time == state_expected.config.genesis_time);
    assert(state_decoded.slot == state_expected.slot);
    assert_checkpoint_equal(&state_decoded.latest_justified, &state_expected.latest_justified);
    assert_checkpoint_equal(&state_decoded.latest_finalized, &state_expected.latest_finalized);
    assert(state_decoded.historical_block_hashes.length == state_expected.historical_block_hashes.length);
    for (size_t i = 0; i < state_expected.historical_block_hashes.length; ++i) {
        assert(memcmp(state_decoded.historical_block_hashes.items[i].bytes,
                      state_expected.historical_block_hashes.items[i].bytes,
                      LANTERN_ROOT_SIZE)
               == 0);
    }
    assert(state_decoded.justified_slots.bit_length == state_expected.justified_slots.bit_length);
    assert(memcmp(state_decoded.justified_slots.bytes,
                  state_expected.justified_slots.bytes,
                  (state_expected.justified_slots.bit_length + 7) / 8)
           == 0);
    assert(state_decoded.justification_roots.length == state_expected.justification_roots.length);
    assert(memcmp(state_decoded.justification_roots.items[0].bytes,
                  state_expected.justification_roots.items[0].bytes,
                  LANTERN_ROOT_SIZE)
           == 0);
    assert(state_decoded.justification_validators.bit_length
           == state_expected.justification_validators.bit_length);
    assert(memcmp(state_decoded.justification_validators.bytes,
                  state_expected.justification_validators.bytes,
                  (state_expected.justification_validators.bit_length + 7) / 8)
           == 0);
    assert(state_decoded.validator_count == state_expected.validator_count);
    assert(memcmp(
               state_decoded.validator_registry_root.bytes,
               state_expected.validator_registry_root.bytes,
               LANTERN_ROOT_SIZE)
           == 0);
    g_current_test = "state_validators";
    for (size_t i = 0; i < state_expected.validator_count; ++i) {
        expect_bytes_equal(
            state_expected.validators[i].pubkey,
            LANTERN_VALIDATOR_PUBKEY_SIZE,
            state_decoded.validators[i].pubkey,
            LANTERN_VALIDATOR_PUBKEY_SIZE);
    }

    /* Cleanup */
    lantern_aggregated_attestation_reset(&agg_a_expected);
    lantern_aggregated_attestation_reset(&agg_b_expected);
    lantern_block_body_reset(&body_expected);
    lantern_block_body_reset(&body_decoded);
    lantern_block_body_reset(&block_expected.body);
    lantern_block_body_reset(&block_decoded.body);
    reset_signed_block(&signed_block_expected);
    reset_signed_block(&signed_block_decoded);
    lantern_state_reset(&state_expected);
    lantern_state_reset(&state_decoded);
}

static void test_state_rejects_truncated_state_payload(void) {
    LanternState genesis_state;
    lantern_state_init(&genesis_state);
    expect_ok(lantern_state_generate_genesis(&genesis_state, 1234, 7), "genesis state");
    size_t genesis_validator_count = (size_t)genesis_state.config.num_validators;
    uint8_t *genesis_validator_pubkeys = calloc(
        genesis_validator_count,
        LANTERN_VALIDATOR_PUBKEY_SIZE);
    assert(genesis_validator_pubkeys != NULL);
    expect_ok(
        lantern_state_set_validator_pubkeys(
            &genesis_state,
            genesis_validator_pubkeys,
            genesis_validator_count),
        "genesis validators");
    free(genesis_validator_pubkeys);

    uint8_t encoded[2048];
    size_t written = 0;
    expect_ok(
        lantern_ssz_encode_state(&genesis_state, encoded, sizeof(encoded), &written),
        "encode genesis state");

    LanternState decoded_full;
    lantern_state_init(&decoded_full);
    expect_ok(
        lantern_ssz_decode_state(&decoded_full, encoded, written),
        "decode full state");
    assert(decoded_full.justification_validators.bit_length == 0);
    assert(decoded_full.config.num_validators == genesis_state.config.num_validators);
    assert(decoded_full.justified_slots.bit_length == genesis_state.justified_slots.bit_length);
    lantern_state_reset(&decoded_full);

    /*
     * The offsets table for the State container begins immediately after the
     * fixed-size fields (config, slot, latest_block_header, latest_justified,
     * latest_finalized). Do not skip any additional bytes here or the computed
     * offsets will be garbage.
     */
    size_t offsets_offset = LANTERN_CONFIG_SSZ_SIZE + sizeof(uint64_t) + LANTERN_BLOCK_HEADER_SSZ_SIZE
        + (2 * LANTERN_CHECKPOINT_SSZ_SIZE);
    uint32_t offsets[5];
    memcpy(offsets, encoded + offsets_offset, sizeof(offsets));

    size_t truncated_len = offsets[4];
    assert(truncated_len < written);

    LanternState truncated_state;
    lantern_state_init(&truncated_state);
    int truncated_rc = lantern_ssz_decode_state(&truncated_state, encoded, truncated_len);
    assert(truncated_rc != 0);

    lantern_state_reset(&truncated_state);
    lantern_state_reset(&genesis_state);
}

int main(void) {
    test_checkpoint_roundtrip();
    test_vote_roundtrip();
    test_signed_vote_roundtrip();
    test_signed_vote_signature_validation();
    test_block_header_roundtrip();
    test_block_body_roundtrip();
    test_block_body_decode_legacy_plain_attestations();
    test_block_body_hash_mode_is_per_body_decode_layout();
    test_block_roundtrip_preserves_legacy_plain_body_layout();
    test_block_roundtrip();
    test_signed_block_roundtrip();
    test_signed_block_signature_validation();
    test_signed_block_decode_without_signature_section();
    test_signed_block_decode_attestation_signatures_only();
    test_signed_block_decode_attestation_signatures_only_empty();
    test_state_roundtrip();
    test_state_rejects_truncated_state_payload();
    test_leanspec_vectors();
    puts("lantern_ssz_test OK");
    return 0;
}
