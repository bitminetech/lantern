#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "lantern/consensus/containers.h"
#include "lantern/consensus/hash.h"
#include "lantern/consensus/state.h"
#include "lantern/consensus/ssz.h"

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
    assert(lantern_ssz_encode_checkpoint(&input, buffer, sizeof(buffer), &written) == SSZ_SUCCESS);
    assert(written == sizeof(buffer));

    LanternCheckpoint decoded;
    memset(&decoded, 0, sizeof(decoded));
    assert(lantern_ssz_decode_checkpoint(&decoded, buffer, sizeof(buffer)) == SSZ_SUCCESS);
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

static void test_validator_index_helpers(void) {
    assert(lantern_validator_index_is_valid((LanternValidatorIndex)0, 8));
    assert(lantern_validator_index_is_valid((LanternValidatorIndex)7, 8));
    assert(!lantern_validator_index_is_valid((LanternValidatorIndex)8, 8));

    assert(lantern_validator_index_is_proposer_for((LanternValidatorIndex)3, 11, 8));
    assert(!lantern_validator_index_is_proposer_for((LanternValidatorIndex)2, 11, 8));
    assert(!lantern_validator_index_is_proposer_for((LanternValidatorIndex)0, 1, 0));

    size_t subnet_id = SIZE_MAX;
    assert(lantern_validator_index_compute_subnet_id((LanternValidatorIndex)9, 4, &subnet_id) == 0);
    assert(subnet_id == 1);
    assert(lantern_validator_index_compute_subnet_id((LanternValidatorIndex)3, 0, &subnet_id) != 0);
}

static void test_validator_indices_bitlist_roundtrip(void) {
    LanternValidatorIndices indices;
    lantern_validator_indices_init(&indices);
    assert(lantern_validator_indices_append(&indices, (LanternValidatorIndex)1) == 0);
    assert(lantern_validator_indices_append(&indices, (LanternValidatorIndex)3) == 0);
    assert(lantern_validator_indices_append(&indices, (LanternValidatorIndex)3) == 0);
    assert(lantern_validator_indices_append(&indices, (LanternValidatorIndex)9) == 0);

    struct lantern_bitlist bits;
    lantern_bitlist_init(&bits);
    assert(lantern_aggregation_bits_from_validator_indices(&bits, &indices) == 0);
    assert(bits.bit_length == 10);
    assert(lantern_bitlist_get(&bits, 1));
    assert(lantern_bitlist_get(&bits, 3));
    assert(lantern_bitlist_get(&bits, 9));
    assert(!lantern_bitlist_get(&bits, 2));

    LanternValidatorIndices restored;
    lantern_validator_indices_init(&restored);
    assert(lantern_aggregation_bits_to_validator_indices(&bits, &restored) == 0);
    assert(restored.length == 3);
    assert(restored.data[0] == 1);
    assert(restored.data[1] == 3);
    assert(restored.data[2] == 9);

    LanternValidatorIndices empty_indices;
    lantern_validator_indices_init(&empty_indices);
    assert(lantern_aggregation_bits_from_validator_indices(&bits, &empty_indices) != 0);

    struct lantern_bitlist empty_bits;
    lantern_bitlist_init(&empty_bits);
    assert(lantern_aggregation_bits_to_validator_indices(&empty_bits, &restored) != 0);

    lantern_bitlist_reset(&empty_bits);
    lantern_validator_indices_reset(&empty_indices);
    lantern_validator_indices_reset(&restored);
    lantern_bitlist_reset(&bits);
    lantern_validator_indices_reset(&indices);
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
    assert(lantern_ssz_encode_vote(&input, buffer, sizeof(buffer), &written) == SSZ_SUCCESS);
    assert(written == sizeof(buffer));

    LanternVote decoded;
    memset(&decoded, 0, sizeof(decoded));
    assert(lantern_ssz_decode_vote(&decoded, buffer, sizeof(buffer)) == SSZ_SUCCESS);
    assert(decoded.slot == input.slot);
    assert(memcmp(decoded.head.root.bytes, input.head.root.bytes, LANTERN_ROOT_SIZE) == 0);
    assert(memcmp(decoded.target.root.bytes, input.target.root.bytes, LANTERN_ROOT_SIZE) == 0);
    assert(memcmp(decoded.source.root.bytes, input.source.root.bytes, LANTERN_ROOT_SIZE) == 0);
}

static void test_signed_vote_roundtrip(void) {
    LanternSignedVote signed_vote = build_signed_vote(42, 9, 0x21);

    uint8_t buffer[LANTERN_SIGNED_VOTE_SSZ_SIZE];
    size_t written = 0;
    assert(lantern_ssz_encode_signed_vote(&signed_vote, buffer, sizeof(buffer), &written) == SSZ_SUCCESS);
    assert(written == sizeof(buffer));

    LanternSignedVote decoded;
    memset(&decoded, 0, sizeof(decoded));
    assert(lantern_ssz_decode_signed_vote(&decoded, buffer, sizeof(buffer)) == SSZ_SUCCESS);
    assert(decoded.data.validator_id == signed_vote.data.validator_id);
    assert(decoded.data.slot == signed_vote.data.slot);
    assert(memcmp(decoded.signature.bytes, signed_vote.signature.bytes, LANTERN_SIGNATURE_SIZE) == 0);
}

static void test_signed_vote_signature_validation(void) {
    LanternSignedVote signed_vote = build_signed_vote(3, 5, 0x33);
    uint8_t buffer[LANTERN_SIGNED_VOTE_SSZ_SIZE];
    size_t written = 0;
    assert(lantern_ssz_encode_signed_vote(&signed_vote, buffer, sizeof(buffer), &written) == SSZ_SUCCESS);

    LanternSignedVote decoded;
    memset(&decoded, 0, sizeof(decoded));
    const size_t signature_offset = LANTERN_VOTE_SSZ_SIZE;
    buffer[signature_offset] ^= 0xAA;
    assert(lantern_ssz_decode_signed_vote(&decoded, buffer, sizeof(buffer)) == SSZ_SUCCESS);
    assert(memcmp(&buffer[signature_offset], decoded.signature.bytes, LANTERN_SIGNATURE_SIZE) == 0);
    assert(decoded.signature.bytes[0] == (uint8_t)(signed_vote.signature.bytes[0] ^ 0xAA));

    assert(lantern_ssz_encode_signed_vote(&signed_vote, buffer, sizeof(buffer), &written) == SSZ_SUCCESS);
    buffer[0] ^= 0xFF;
    assert(lantern_ssz_decode_signed_vote(&decoded, buffer, sizeof(buffer)) != SSZ_SUCCESS);
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
    assert(lantern_ssz_encode_block_header(&header, buffer, sizeof(buffer), &written) == SSZ_SUCCESS);
    assert(written == sizeof(buffer));

    LanternBlockHeader decoded;
    memset(&decoded, 0, sizeof(decoded));
    assert(lantern_ssz_decode_block_header(&decoded, buffer, sizeof(buffer)) == SSZ_SUCCESS);
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
    assert(lantern_ssz_encode_block_body(&body, buffer, sizeof(buffer), &written) == SSZ_SUCCESS);
    maybe_dump_vector("LANTERN_DUMP_SSZ_BLOCK_BODY", "LANTERN_SSZ_VECTOR_BLOCK_BODY", buffer, written);

    LanternBlockBody decoded;
    lantern_block_body_init(&decoded);
    assert(lantern_ssz_decode_block_body(&decoded, buffer, written) == SSZ_SUCCESS);
    assert(decoded.attestations.length == body.attestations.length);

    for (size_t i = 0; i < body.attestations.length; ++i) {
        assert_aggregated_attestation_equal(&decoded.attestations.data[i], &body.attestations.data[i]);
    }

    lantern_block_body_reset(&body);
    lantern_block_body_reset(&decoded);
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

static void populate_signed_block_with_signatures(LanternSignedBlock *signed_block) {
    lantern_signed_block_with_attestation_init(signed_block);
    populate_block(&signed_block->block);

    size_t attestation_count = signed_block->block.body.attestations.length;
    expect_ok(
        lantern_attestation_signatures_resize(
            &signed_block->signatures.attestation_signatures,
            attestation_count),
        "resize block signatures");
    for (size_t i = 0; i < attestation_count; ++i) {
        LanternAggregatedSignatureProof *proof = &signed_block->signatures.attestation_signatures.data[i];
        const LanternAggregatedAttestation *attestation = &signed_block->block.body.attestations.data[i];
        expect_ok(
            lantern_bitlist_resize(&proof->participants, attestation->aggregation_bits.bit_length),
            "resize proof participants");
        size_t byte_len = (attestation->aggregation_bits.bit_length + 7u) / 8u;
        if (byte_len > 0) {
            memcpy(proof->participants.bytes, attestation->aggregation_bits.bytes, byte_len);
        }
        fill_proof_data(proof, (uint8_t)(0xC0u + (i * 0x10u)), 4u + i);
    }
    fill_signature(&signed_block->signatures.proposer_signature, 0xA5);
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

static void test_block_roundtrip(void) {
    LanternBlock block;
    populate_block(&block);

    uint8_t buffer[SIGNED_BLOCK_TEST_BUFFER_SIZE];
    size_t written = 0;
    assert(lantern_ssz_encode_block(&block, buffer, sizeof(buffer), &written) == SSZ_SUCCESS);
    maybe_dump_vector("LANTERN_DUMP_SSZ_BLOCK", "LANTERN_SSZ_VECTOR_BLOCK", buffer, written);

    LanternBlock decoded;
    memset(&decoded, 0, sizeof(decoded));
    lantern_block_body_init(&decoded.body);
    assert(lantern_ssz_decode_block(&decoded, buffer, written) == SSZ_SUCCESS);

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
    populate_block(&signed_block.block);

    uint8_t buffer[SIGNED_BLOCK_TEST_BUFFER_SIZE];
    size_t written = 0;
    assert(lantern_ssz_encode_signed_block(&signed_block, buffer, sizeof(buffer), &written) == SSZ_SUCCESS);

    LanternSignedBlock decoded;
    lantern_signed_block_with_attestation_init(&decoded);
    assert(lantern_ssz_decode_signed_block(&decoded, buffer, written) == SSZ_SUCCESS);

    assert(decoded.block.slot == signed_block.block.slot);
    expect_block_signatures_equal(&signed_block.signatures, &decoded.signatures);
    assert(decoded.block.body.attestations.length
           == signed_block.block.body.attestations.length);

    reset_signed_block(&signed_block);
    reset_signed_block(&decoded);
}

static void test_signed_block_signature_validation(void) {
    LanternSignedBlock signed_block;
    lantern_signed_block_with_attestation_init(&signed_block);
    populate_block(&signed_block.block);

    uint8_t buffer[SIGNED_BLOCK_TEST_BUFFER_SIZE];
    size_t written = 0;
    assert(lantern_ssz_encode_signed_block(&signed_block, buffer, sizeof(buffer), &written) == SSZ_SUCCESS);

    LanternSignedBlock decoded;
    lantern_signed_block_with_attestation_init(&decoded);
    buffer[sizeof(uint32_t)] = 0x5A; /* corrupt message offset */
    assert(lantern_ssz_decode_signed_block(&decoded, buffer, written) != SSZ_SUCCESS);
    reset_signed_block(&decoded);

    signed_block.signatures.attestation_signatures.length = LANTERN_MAX_BLOCK_SIGNATURES + 2;
    signed_block.signatures.attestation_signatures.data = NULL;
    assert(lantern_ssz_encode_signed_block(&signed_block, buffer, sizeof(buffer), &written) != SSZ_SUCCESS);

    reset_signed_block(&signed_block);
}

static void test_signed_block_decode_without_signature_section(void) {
    LanternSignedBlock signed_block;
    lantern_signed_block_with_attestation_init(&signed_block);
    populate_block(&signed_block.block);

    uint8_t message_buf[SIGNED_BLOCK_TEST_BUFFER_SIZE];
    size_t message_written = 0;
    assert(lantern_ssz_encode_block(
               &signed_block.block,
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
    assert(lantern_ssz_decode_signed_block(&decoded, encoded, encoded_len) != SSZ_SUCCESS);

    reset_signed_block(&signed_block);
    reset_signed_block(&decoded);
    free(encoded);
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
    assert(lantern_ssz_encode_state(&state, buffer, sizeof(buffer), &written) == SSZ_SUCCESS);

    LanternState decoded;
    lantern_state_init(&decoded);
    assert(lantern_ssz_decode_state(&decoded, buffer, written) == SSZ_SUCCESS);

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

static void test_state_rejects_truncated_state_payload(void) {
    LanternState genesis_state;
    lantern_state_init(&genesis_state);
    expect_ok(lantern_state_generate_genesis(&genesis_state, 1234, 7), "genesis state");
    size_t genesis_validator_count = (size_t)genesis_state.config.num_validators;
    uint8_t *genesis_attestation_pubkeys = calloc(
        genesis_validator_count,
        LANTERN_VALIDATOR_PUBKEY_SIZE);
    uint8_t *genesis_proposal_pubkeys = calloc(
        genesis_validator_count,
        LANTERN_VALIDATOR_PUBKEY_SIZE);
    assert(genesis_attestation_pubkeys != NULL);
    assert(genesis_proposal_pubkeys != NULL);
    expect_ok(
        lantern_state_set_validator_pubkeys_dual(
            &genesis_state,
            genesis_attestation_pubkeys,
            genesis_proposal_pubkeys,
            genesis_validator_count),
        "genesis validators");
    free(genesis_attestation_pubkeys);
    free(genesis_proposal_pubkeys);

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
    ssz_error_t truncated_rc = lantern_ssz_decode_state(&truncated_state, encoded, truncated_len);
    assert(truncated_rc != 0);

    lantern_state_reset(&truncated_state);
    lantern_state_reset(&genesis_state);
}

int main(void) {
    test_validator_index_helpers();
    test_validator_indices_bitlist_roundtrip();
    test_checkpoint_roundtrip();
    test_vote_roundtrip();
    test_signed_vote_roundtrip();
    test_signed_vote_signature_validation();
    test_block_header_roundtrip();
    test_block_body_roundtrip();
    test_block_roundtrip();
    test_signed_block_roundtrip();
    test_signed_block_signature_validation();
    test_signed_block_decode_without_signature_section();
    test_state_roundtrip();
    test_state_rejects_truncated_state_payload();
    puts("lantern_ssz_test OK");
    return 0;
}
