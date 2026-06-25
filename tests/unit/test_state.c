#include <assert.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <inttypes.h>

#include "lantern/consensus/duties.h"
#include "lantern/consensus/hash.h"
#include "lantern/consensus/fork_choice.h"
#include "lantern/consensus/quorum.h"
#include "lantern/consensus/signature.h"
#include "lantern/consensus/state.h"
#include "lantern/metrics/lean_metrics.h"
#include "pq-bindings-c-rust.h"
#include "../support/state_store_adapter.h"

static void expect_zero(int rc, const char *label) {
    if (rc != 0) {
        fprintf(stderr, "%s failed (rc=%d)\n", label, rc);
        exit(EXIT_FAILURE);
    }
}

static void expect_ssz_success(ssz_error_t err, const char *label) {
    if (err != SSZ_SUCCESS) {
        fprintf(stderr, "%s failed (ssz_error=%d)\n", label, (int)err);
        exit(EXIT_FAILURE);
    }
}

static void fill_root(LanternRoot *root, uint8_t value) {
    if (!root) {
        return;
    }
    memset(root->bytes, value, LANTERN_ROOT_SIZE);
}

static void fill_signature(LanternSignature *signature, uint8_t value) {
    if (!signature) {
        return;
    }
    memset(signature->bytes, value, LANTERN_SIGNATURE_SIZE);
}

static int generate_test_keypair(
    struct PQSignatureSchemePublicKey **out_pub,
    struct PQSignatureSchemeSecretKey **out_secret) {
    if (!out_pub || !out_secret) {
        return -1;
    }
    *out_pub = NULL;
    *out_secret = NULL;
    enum PQSigningError err = pq_key_gen(0, 4u, out_pub, out_secret);
    if (err != Success || !*out_pub || !*out_secret) {
        if (*out_pub) {
            pq_public_key_free(*out_pub);
            *out_pub = NULL;
        }
        if (*out_secret) {
            pq_secret_key_free(*out_secret);
            *out_secret = NULL;
        }
        return -1;
    }
    return 0;
}

static int set_test_validator_pubkey(
    LanternState *state,
    size_t validator_count,
    size_t validator_index,
    struct PQSignatureSchemePublicKey *pubkey) {
    if (!state || !pubkey || validator_count == 0 || validator_index >= validator_count) {
        return -1;
    }

    uint8_t serialized_pubkey[LANTERN_VALIDATOR_PUBKEY_SIZE];
    uintptr_t written = 0;
    enum PQSigningError err = pq_public_key_serialize(
        pubkey,
        serialized_pubkey,
        sizeof(serialized_pubkey),
        &written);
    if (err != Success || written != LANTERN_VALIDATOR_PUBKEY_SIZE) {
        return -1;
    }

    uint8_t *pubkeys = calloc(validator_count, LANTERN_VALIDATOR_PUBKEY_SIZE);
    if (!pubkeys) {
        return -1;
    }
    memcpy(
        pubkeys + (validator_index * LANTERN_VALIDATOR_PUBKEY_SIZE),
        serialized_pubkey,
        LANTERN_VALIDATOR_PUBKEY_SIZE);
    int rc = lantern_state_set_validator_pubkeys(state, pubkeys, validator_count);
    free(pubkeys);
    return rc;
}

static int build_proposer_only_block_proof(
    const LanternState *state,
    const LanternBlock *block,
    const LanternRoot *block_root,
    const LanternSignature *proposer_signature,
    LanternByteList *out_proof) {
    if (!state || !block || !block_root || !proposer_signature || !out_proof) {
        return -1;
    }

    int rc = -1;
    LanternAggregatedSignatureProof proposer_proof;
    LanternAttestationSignatures attestation_proofs;
    struct lantern_bitlist proposer_participants;
    lantern_aggregated_signature_proof_init(&proposer_proof);
    lantern_attestation_signatures_init(&attestation_proofs);
    lantern_bitlist_init(&proposer_participants);

    size_t proposer_index = (size_t)block->proposer_index;
    const uint8_t *proposer_pubkey = lantern_state_validator_proposal_pubkey(state, proposer_index);
    if (!proposer_pubkey) {
        goto cleanup;
    }
    if (lantern_bitlist_resize(&proposer_participants, proposer_index + 1u) != 0
        || lantern_bitlist_set(&proposer_participants, proposer_index, true) != 0) {
        goto cleanup;
    }

    LanternRawXmssSignature raw_proposer = {
        .pubkey = proposer_pubkey,
        .signature = proposer_signature,
    };
    if (!lantern_aggregated_signature_proof_aggregate(
            state,
            &proposer_participants,
            NULL,
            0u,
            &raw_proposer,
            1u,
            block_root,
            block->slot,
            &proposer_proof)) {
        goto cleanup;
    }
    if (!lantern_signature_merge_block_type2_proof(
            state,
            block,
            &attestation_proofs,
            &proposer_proof,
            out_proof)) {
        goto cleanup;
    }

    rc = 0;

cleanup:
    lantern_bitlist_reset(&proposer_participants);
    lantern_attestation_signatures_reset(&attestation_proofs);
    lantern_aggregated_signature_proof_reset(&proposer_proof);
    return rc;
}

static int serialize_test_pubkey(
    struct PQSignatureSchemePublicKey *pubkey,
    uint8_t out_bytes[LANTERN_VALIDATOR_PUBKEY_SIZE]) {
    if (!pubkey || !out_bytes) {
        return -1;
    }

    uintptr_t written = 0;
    enum PQSigningError err = pq_public_key_serialize(
        pubkey,
        out_bytes,
        LANTERN_VALIDATOR_PUBKEY_SIZE,
        &written);
    if (err != Success || written != LANTERN_VALIDATOR_PUBKEY_SIZE) {
        return -1;
    }
    return 0;
}

static int set_test_validator_pubkeys(
    LanternState *state,
    struct PQSignatureSchemePublicKey **pubkeys,
    size_t validator_count) {
    if (!state || !pubkeys || validator_count == 0u) {
        return -1;
    }

    uint8_t *attestation_pubkeys =
        calloc(validator_count, LANTERN_VALIDATOR_PUBKEY_SIZE);
    uint8_t *proposal_pubkeys =
        calloc(validator_count, LANTERN_VALIDATOR_PUBKEY_SIZE);
    if (!attestation_pubkeys || !proposal_pubkeys) {
        free(attestation_pubkeys);
        free(proposal_pubkeys);
        return -1;
    }

    for (size_t i = 0; i < validator_count; ++i) {
        if (!pubkeys[i]
            || serialize_test_pubkey(
                   pubkeys[i],
                   attestation_pubkeys + (i * LANTERN_VALIDATOR_PUBKEY_SIZE))
                != 0) {
            free(attestation_pubkeys);
            free(proposal_pubkeys);
            return -1;
        }
        memcpy(
            proposal_pubkeys + (i * LANTERN_VALIDATOR_PUBKEY_SIZE),
            attestation_pubkeys + (i * LANTERN_VALIDATOR_PUBKEY_SIZE),
            LANTERN_VALIDATOR_PUBKEY_SIZE);
    }

    int rc = lantern_state_set_validator_pubkeys_dual(
        state,
        attestation_pubkeys,
        proposal_pubkeys,
        validator_count);
    free(attestation_pubkeys);
    free(proposal_pubkeys);
    return rc;
}

static int sign_vote_with_secret(
    LanternSignedVote *vote,
    struct PQSignatureSchemeSecretKey *secret) {
    if (!vote || !secret) {
        return -1;
    }
    LanternRoot vote_root;
    if (lantern_hash_tree_root_attestation_data(&vote->data.data, &vote_root) != SSZ_SUCCESS) {
        return -1;
    }
    if (!lantern_signature_sign(secret, vote->data.slot, &vote_root, &vote->signature)) {
        return -1;
    }
    return 0;
}

static void build_vote(
    LanternVote *out_vote,
    LanternSignature *out_signature,
    uint64_t validator_id,
    uint64_t slot,
    const LanternCheckpoint *source,
    const LanternCheckpoint *target_template,
    uint8_t signature_marker);

static void zero_root(LanternRoot *root) {
    if (!root) {
        return;
    }
    memset(root->bytes, 0, sizeof(root->bytes));
}

static bool bitlist_test_bit(const struct lantern_bitlist *bitlist, size_t index) {
    assert(bitlist != NULL);
    assert(bitlist->bytes != NULL);
    assert(index < bitlist->bit_length);
    size_t byte_index = index / 8;
    assert(byte_index < bitlist->capacity);
    size_t bit_index = index % 8;
    return (bitlist->bytes[byte_index] & (uint8_t)(1u << bit_index)) != 0;
}

static int single_participant_from_bits(const struct lantern_bitlist *bitlist, uint64_t *out_validator_id) {
    if (!bitlist || !out_validator_id || bitlist->bit_length == 0u || !bitlist->bytes) {
        return -1;
    }
    bool found = false;
    uint64_t validator_id = 0u;
    for (size_t i = 0; i < bitlist->bit_length; ++i) {
        if (!bitlist_test_bit(bitlist, i)) {
            continue;
        }
        if (found) {
            return -1;
        }
        validator_id = (uint64_t)i;
        found = true;
    }
    if (!found) {
        return -1;
    }
    *out_validator_id = validator_id;
    return 0;
}

static uint64_t justified_slots_anchor_for_tests(const LanternState *state) {
    assert(state != NULL);
    assert(state->latest_finalized.slot != UINT64_MAX);
    return state->latest_finalized.slot + 1u;
}

static void mark_slot_justified_for_tests(LanternState *state, uint64_t slot) {
    if (!state) {
        return;
    }
    uint64_t anchor = justified_slots_anchor_for_tests(state);
    /* Slots before the anchor are already considered finalized/justified. */
    if (slot < anchor) {
        return;
    }
    /* Calculate the relative index from the finalized-slot anchor. */
    size_t index = (size_t)(slot - anchor);
    expect_zero(
        lantern_bitlist_resize(&state->justified_slots, index + 1),
        "resize justified slots for test");
    assert(state->justified_slots.bytes != NULL);
    size_t byte_index = index / 8u;
    assert(byte_index < state->justified_slots.capacity);
    size_t bit_index = index % 8u;
    state->justified_slots.bytes[byte_index] |= (uint8_t)(1u << bit_index);
}

/* Helper to populate historical_block_hashes up to the target slot.
 * Entries are filled with synthetic roots based on the slot index.
 * This is required because leanSpec attestation validation checks that
 * source, target, and head roots match the historical_block_hashes. */
static void populate_historical_hashes_for_tests(LanternState *state, uint64_t up_to_slot) {
    if (!state) {
        return;
    }
    size_t target_len = (size_t)(up_to_slot + 1);
    expect_zero(
        lantern_root_list_resize(&state->historical_block_hashes, target_len),
        "resize historical hashes for test");
    for (size_t i = 0; i < target_len; ++i) {
        /* Fill each slot's hash with a deterministic pattern based on slot index */
        fill_root(&state->historical_block_hashes.items[i], (uint8_t)(0x10u + i));
    }
}

/* Get the root from historical_block_hashes for a given slot */
static LanternRoot get_historical_root_for_tests(const LanternState *state, uint64_t slot) {
    LanternRoot result;
    memset(&result, 0, sizeof(result));
    if (!state || slot >= state->historical_block_hashes.length) {
        return result;
    }
    return state->historical_block_hashes.items[(size_t)slot];
}

static bool slot_is_justifiable_for_tests(uint64_t candidate_slot, uint64_t finalized_slot) {
    if (candidate_slot < finalized_slot) {
        return false;
    }
    uint64_t delta = candidate_slot - finalized_slot;
    if (delta <= 5) {
        return true;
    }
    for (uint64_t i = 1; i <= delta; ++i) {
        if (i > delta / i) {
            break;
        }
        if (i * i == delta) {
            return true;
        }
    }
    for (uint64_t a = 1; a < delta; ++a) {
        uint64_t b = a + 1;
        if (a > delta / b) {
            break;
        }
        if (a * b == delta) {
            return true;
        }
    }
    return false;
}

static bool checkpoints_equal(const LanternCheckpoint *a, const LanternCheckpoint *b) {
    if (!a || !b) {
        return false;
    }
    if (a->slot != b->slot) {
        return false;
    }
    return memcmp(a->root.bytes, b->root.bytes, LANTERN_ROOT_SIZE) == 0;
}

static void setup_state_and_fork_choice(
    LanternState *state,
    LanternForkChoice *fork_choice,
    uint64_t genesis_time,
    uint64_t validator_count,
    LanternRoot *out_anchor_root) {
    lantern_state_init(state);
    expect_zero(lantern_state_generate_genesis(state, genesis_time, validator_count), "generate genesis for setup");

    lantern_fork_choice_init(fork_choice);
    lantern_state_attach_fork_choice(state, fork_choice);
    expect_zero(lantern_fork_choice_configure(fork_choice, &state->config), "configure fork choice for setup");

    LanternRoot state_root;
    expect_ssz_success(lantern_hash_tree_root_state(state, &state_root), "hash state for anchor setup");
    state->latest_block_header.state_root = state_root;
    LanternRoot header_root;
    expect_ssz_success(
        lantern_hash_tree_root_block_header(&state->latest_block_header, &header_root),
        "hash header for anchor setup");
    state->latest_justified.root = header_root;
    state->latest_finalized.root = header_root;

    LanternBlock anchor;
    memset(&anchor, 0, sizeof(anchor));
    anchor.slot = state->latest_block_header.slot;
    anchor.proposer_index = state->latest_block_header.proposer_index;
    anchor.parent_root = state->latest_block_header.parent_root;
    anchor.state_root = state_root;
    lantern_block_body_init(&anchor.body);

    expect_ssz_success(lantern_hash_tree_root_block(&anchor, out_anchor_root), "hash anchor block");

    expect_zero(
        lantern_fork_choice_set_anchor(
            fork_choice,
            &anchor,
            &state->latest_justified,
            &state->latest_finalized,
            out_anchor_root),
        "set fork choice anchor");

    lantern_state_attach_fork_choice(state, fork_choice);
    lantern_block_body_reset(&anchor.body);
}

static void make_block(
    const LanternState *state,
    uint64_t slot,
    const LanternRoot *parent_root,
    LanternBlock *out_block,
    LanternRoot *out_root) {
    memset(out_block, 0, sizeof(*out_block));
    out_block->slot = slot;
    expect_zero(
        lantern_proposer_for_slot(slot, state->config.num_validators, &out_block->proposer_index),
        "compute proposer for block");
    out_block->parent_root = *parent_root;
    memset(out_block->state_root.bytes, 0, sizeof(out_block->state_root.bytes));
    lantern_block_body_init(&out_block->body);
    expect_ssz_success(lantern_hash_tree_root_block(out_block, out_root), "hash block");
}

static int test_genesis_state(void) {
    LanternState state;
    lantern_state_init(&state);
    expect_zero(lantern_state_generate_genesis(&state, 1234, 8), "generate genesis");

    assert(state.justified_slots.bit_length == 0);

    assert(state.config.genesis_time == 1234);
    assert(state.config.num_validators == 8);
    assert(state.slot == 0);

    LanternBlockBody empty_body;
    lantern_block_body_init(&empty_body);
    LanternRoot expected_body_root;
    expect_ssz_success(lantern_hash_tree_root_block_body(&empty_body, &expected_body_root), "hash empty body");
    lantern_block_body_reset(&empty_body);
    assert(memcmp(state.latest_block_header.body_root.bytes, expected_body_root.bytes, LANTERN_ROOT_SIZE) == 0);
    for (size_t i = 0; i < LANTERN_ROOT_SIZE; ++i) {
        assert(state.latest_block_header.state_root.bytes[i] == 0);
    }

    lantern_state_reset(&state);
    return 0;
}

static int test_genesis_justification_bits(void) {
    const uint64_t genesis_time = 4321;
    const uint64_t validator_count = 6;
    LanternState state;
    lantern_state_init(&state);
    expect_zero(lantern_state_generate_genesis(&state, genesis_time, validator_count), "generate genesis for bits");
    assert(state.justified_slots.bit_length == 0);

    LanternBlock block;
    memset(&block, 0, sizeof(block));
    block.slot = 1;
    expect_zero(
        lantern_proposer_for_slot(block.slot, validator_count, &block.proposer_index),
        "compute proposer for first block");
    lantern_block_body_init(&block.body);

    expect_zero(lantern_state_process_slots(&state, block.slot), "advance slots for first block");
    LanternRoot parent_root;
    expect_ssz_success(lantern_hash_tree_root_block_header(&state.latest_block_header, &parent_root), "hash genesis header");
    block.parent_root = parent_root;

    expect_zero(lantern_state_process_block(&state, &block), "process first block");
    /* Finalized boundary (slot 0) is implicit; bitlist starts at slot 1. */
    assert(state.justified_slots.bit_length == 0);

    lantern_block_body_reset(&block.body);
    lantern_state_reset(&state);
    return 0;
}

static int test_validator_registry_limit_enforced(void) {
    LanternState state;
    lantern_state_init(&state);
    const uint64_t limit = (uint64_t)LANTERN_VALIDATOR_REGISTRY_LIMIT;

    expect_zero(lantern_state_generate_genesis(&state, 999u, limit), "genesis at limit");
    lantern_state_reset(&state);

    if (lantern_state_generate_genesis(&state, 999u, limit + 1u) == 0) {
        fprintf(stderr, "expected genesis to reject validator counts above limit\n");
        lantern_state_reset(&state);
        return 1;
    }

    expect_zero(lantern_state_prepare_validator_votes(&state, limit), "prepare votes at limit");
    lantern_state_reset(&state);
    if (lantern_state_prepare_validator_votes(&state, limit + 1u) == 0) {
        fprintf(stderr, "expected prepare_validator_votes to reject counts above limit\n");
        lantern_state_reset(&state);
        return 1;
    }

    size_t pubkey_count = (size_t)limit;
    size_t max_pubkey_count = pubkey_count + 1u;
    uint8_t *pubkeys = calloc(max_pubkey_count, LANTERN_VALIDATOR_PUBKEY_SIZE);
    assert(pubkeys != NULL);

    expect_zero(lantern_state_set_validator_pubkeys(&state, pubkeys, pubkey_count), "set pubkeys at limit");
    if (lantern_state_set_validator_pubkeys(&state, pubkeys, max_pubkey_count) == 0) {
        fprintf(stderr, "expected pubkey setter to reject counts above limit\n");
        free(pubkeys);
        lantern_state_reset(&state);
        return 1;
    }

    free(pubkeys);
    lantern_state_reset(&state);
    return 0;
}

static int test_block_header_rejects_duplicate_slot(void) {
    LanternState state;
    lantern_state_init(&state);
    expect_zero(lantern_state_generate_genesis(&state, 1111, 4), "genesis for duplicate slot test");

    expect_zero(lantern_state_process_slots(&state, 1), "advance slots for duplicate slot test");
    LanternRoot genesis_header_root;
    expect_ssz_success(
        lantern_hash_tree_root_block_header(&state.latest_block_header, &genesis_header_root),
        "hash genesis header for duplicate slot test");

    LanternBlock first_block;
    LanternRoot first_block_root;
    make_block(&state, 1, &genesis_header_root, &first_block, &first_block_root);
    (void)first_block_root;

    if (lantern_state_process_block(&state, &first_block) != 0) {
        fprintf(stderr, "failed to process first block in duplicate slot test\n");
        lantern_block_body_reset(&first_block.body);
        lantern_state_reset(&state);
        return 1;
    }

    LanternRoot latest_header_root;
    expect_ssz_success(
        lantern_hash_tree_root_block_header(&state.latest_block_header, &latest_header_root),
        "hash latest header for duplicate slot test");

    LanternBlock duplicate_block;
    LanternRoot duplicate_block_root;
    make_block(&state, first_block.slot, &latest_header_root, &duplicate_block, &duplicate_block_root);
    (void)duplicate_block_root;

    if (lantern_state_process_block(&state, &duplicate_block) == 0) {
        fprintf(stderr, "duplicate slot block was incorrectly accepted\n");
        lantern_block_body_reset(&duplicate_block.body);
        lantern_block_body_reset(&first_block.body);
        lantern_state_reset(&state);
        return 1;
    }

    lantern_block_body_reset(&duplicate_block.body);
    lantern_block_body_reset(&first_block.body);
    lantern_state_reset(&state);
    return 0;
}

static int test_block_header_rejects_zero_parent_root(void) {
    LanternState state;
    lantern_state_init(&state);
    expect_zero(lantern_state_generate_genesis(&state, 1222, 5), "genesis for zero parent root test");

    expect_zero(lantern_state_process_slots(&state, 1), "advance slot for zero parent root test");

    LanternRoot zero_parent;
    zero_root(&zero_parent);

    LanternBlock block;
    LanternRoot block_root;
    make_block(&state, 1, &zero_parent, &block, &block_root);
    (void)block_root;

    if (lantern_state_process_block(&state, &block) == 0) {
        fprintf(stderr, "zero parent root block was incorrectly accepted\n");
        lantern_block_body_reset(&block.body);
        lantern_state_reset(&state);
        return 1;
    }

    lantern_block_body_reset(&block.body);
    lantern_state_reset(&state);
    return 0;
}

static int test_process_slots_sets_state_root(void) {
    LanternState state;
    lantern_state_init(&state);
    expect_zero(lantern_state_generate_genesis(&state, 50, 4), "generate genesis");

    LanternRoot pre_root;
    expect_ssz_success(lantern_hash_tree_root_state(&state, &pre_root), "hash state pre-slot");

    expect_zero(lantern_state_process_slots(&state, 1), "process slot 1");
    assert(state.slot == 1);
    assert(memcmp(state.latest_block_header.state_root.bytes, pre_root.bytes, LANTERN_ROOT_SIZE) == 0);

    lantern_state_reset(&state);
    return 0;
}

static int test_process_slots_rejects_non_future_target(void) {
    LanternState state;
    lantern_state_init(&state);
    expect_zero(lantern_state_generate_genesis(&state, 1337, 4), "genesis for process-slots guard");

    expect_zero(lantern_state_process_slots(&state, 1), "advance to slot 1 for guard test");

    if (lantern_state_process_slots(&state, state.slot) == 0) {
        fprintf(stderr, "process_slots should reject target equal to current slot\n");
        lantern_state_reset(&state);
        return 1;
    }
    if (lantern_state_process_slots(&state, state.slot - 1) == 0) {
        fprintf(stderr, "process_slots should reject target behind current slot\n");
        lantern_state_reset(&state);
        return 1;
    }

    lantern_state_reset(&state);
    return 0;
}

static int test_state_transition_applies_block(void) {
    const uint64_t genesis_time = 500;
    const uint64_t validator_count = 1;

    LanternState state;
    lantern_state_init(&state);
    expect_zero(lantern_state_generate_genesis(&state, genesis_time, validator_count), "generate genesis state");

    LanternState expected;
    lantern_state_init(&expected);
    expect_zero(lantern_state_generate_genesis(&expected, genesis_time, validator_count), "generate expected state");

    struct PQSignatureSchemePublicKey *proposer_pub = NULL;
    struct PQSignatureSchemeSecretKey *proposer_secret = NULL;
    expect_zero(generate_test_keypair(&proposer_pub, &proposer_secret), "generate proposer keypair");
    expect_zero(
        set_test_validator_pubkey(&state, (size_t)validator_count, 0u, proposer_pub),
        "set proposer pubkey on state");
    expect_zero(
        set_test_validator_pubkey(&expected, (size_t)validator_count, 0u, proposer_pub),
        "set proposer pubkey on expected state");

    LanternBlock block;
    memset(&block, 0, sizeof(block));
    block.slot = 1;
    expect_zero(lantern_proposer_for_slot(block.slot, validator_count, &block.proposer_index), "compute proposer");
    lantern_block_body_init(&block.body);

    expect_zero(lantern_state_process_slots(&expected, block.slot), "expected process slots");
    LanternRoot parent_root;
    expect_ssz_success(lantern_hash_tree_root_block_header(&expected.latest_block_header, &parent_root), "hash parent header");
    block.parent_root = parent_root;
    expect_zero(lantern_state_process_block(&expected, &block), "expected process block");
    LanternRoot expected_state_root;
    expect_ssz_success(lantern_hash_tree_root_state(&expected, &expected_state_root), "hash expected state");
    block.state_root = expected_state_root;

    LanternSignedBlock signed_block;
    memset(&signed_block, 0, sizeof(signed_block));
    signed_block.block = block;
    LanternRoot proposer_block_root;
    expect_ssz_success(
        lantern_hash_tree_root_block(&signed_block.block, &proposer_block_root),
        "hash proposer block");
    LanternSignature proposer_signature;
    memset(&proposer_signature, 0, sizeof(proposer_signature));
    if (!lantern_signature_sign(
            proposer_secret,
            signed_block.block.slot,
            &proposer_block_root,
            &proposer_signature)) {
        fprintf(stderr, "sign proposer block failed\n");
        lantern_block_body_reset(&block.body);
        pq_secret_key_free(proposer_secret);
        pq_public_key_free(proposer_pub);
        lantern_state_reset(&state);
        lantern_state_reset(&expected);
        return 1;
    }
    if (build_proposer_only_block_proof(
            &state,
            &signed_block.block,
            &proposer_block_root,
            &proposer_signature,
            &signed_block.proof)
        != 0) {
        fprintf(stderr, "build proposer block proof failed\n");
        lantern_byte_list_reset(&signed_block.proof);
        lantern_block_body_reset(&block.body);
        pq_secret_key_free(proposer_secret);
        pq_public_key_free(proposer_pub);
        lantern_state_reset(&state);
        lantern_state_reset(&expected);
        return 1;
    }

    expect_zero(lantern_state_transition(&state, &signed_block), "state transition");
    LanternRoot post_root;
    expect_ssz_success(lantern_hash_tree_root_state(&state, &post_root), "hash post state");
    assert(memcmp(post_root.bytes, expected_state_root.bytes, LANTERN_ROOT_SIZE) == 0);
    uint8_t zero_root[LANTERN_ROOT_SIZE] = {0};
    assert(memcmp(state.latest_block_header.state_root.bytes, zero_root, LANTERN_ROOT_SIZE) == 0);
    assert(state.slot == expected.slot);
    assert(state.historical_block_hashes.length == expected.historical_block_hashes.length);

    lantern_byte_list_reset(&signed_block.proof);
    lantern_block_body_reset(&block.body);
    pq_secret_key_free(proposer_secret);
    pq_public_key_free(proposer_pub);
    lantern_state_reset(&state);
    lantern_state_reset(&expected);
    return 0;
}

static int test_state_transition_rejects_missing_block_proof(void) {
    const uint64_t genesis_time = 501;
    const uint64_t validator_count = 1;

    LanternState state;
    lantern_state_init(&state);
    expect_zero(lantern_state_generate_genesis(&state, genesis_time, validator_count), "generate signed state");

    struct PQSignatureSchemePublicKey *proposer_pub = NULL;
    struct PQSignatureSchemeSecretKey *proposer_secret = NULL;
    expect_zero(generate_test_keypair(&proposer_pub, &proposer_secret), "generate missing-proof keypair");
    expect_zero(
        set_test_validator_pubkey(&state, (size_t)validator_count, 0u, proposer_pub),
        "set missing-proof pubkey");

    LanternState expected;
    lantern_state_init(&expected);
    expect_zero(lantern_state_generate_genesis(&expected, genesis_time, validator_count), "generate expected signed state");
    expect_zero(
        set_test_validator_pubkey(&expected, (size_t)validator_count, 0u, proposer_pub),
        "set expected missing-proof pubkey");

    LanternBlock block;
    memset(&block, 0, sizeof(block));
    block.slot = 1;
    expect_zero(lantern_proposer_for_slot(block.slot, validator_count, &block.proposer_index), "compute missing-proof proposer");
    lantern_block_body_init(&block.body);

    expect_zero(lantern_state_process_slots(&expected, block.slot), "advance expected signed slots");
    LanternRoot parent_root;
    expect_ssz_success(
        lantern_hash_tree_root_block_header(&expected.latest_block_header, &parent_root),
        "hash missing-proof parent");
    block.parent_root = parent_root;
    LanternRoot expected_state_root;
    expect_zero(lantern_state_process_block(&expected, &block), "apply expected unsigned block");
    expect_ssz_success(lantern_hash_tree_root_state(&expected, &expected_state_root), "hash expected unsigned post state");
    block.state_root = expected_state_root;

    LanternSignedBlock signed_block;
    memset(&signed_block, 0, sizeof(signed_block));
    signed_block.block = block;

    if (lantern_state_transition(&state, &signed_block) == 0) {
        fprintf(stderr, "state transition accepted block without block proof\n");
        lantern_block_body_reset(&block.body);
        pq_secret_key_free(proposer_secret);
        pq_public_key_free(proposer_pub);
        lantern_state_reset(&expected);
        lantern_state_reset(&state);
        return 1;
    }
    if (state.slot != 0u) {
        fprintf(stderr, "state transition mutated slot on proof failure (slot=%" PRIu64 ")\n", state.slot);
        lantern_block_body_reset(&block.body);
        pq_secret_key_free(proposer_secret);
        pq_public_key_free(proposer_pub);
        lantern_state_reset(&expected);
        lantern_state_reset(&state);
        return 1;
    }

    lantern_block_body_reset(&block.body);
    pq_secret_key_free(proposer_secret);
    pq_public_key_free(proposer_pub);
    lantern_state_reset(&expected);
    lantern_state_reset(&state);
    return 0;
}

static int test_state_transition_rejects_genesis_state_root_mismatch(void) {
    const uint64_t genesis_time = 600;
    const uint64_t validator_count = 4;

    LanternState state;
    lantern_state_init(&state);
    expect_zero(
        lantern_state_generate_genesis(&state, genesis_time, validator_count),
        "generate genesis state for mismatch test");

    LanternRoot parent_root;
    expect_ssz_success(
        lantern_hash_tree_root_block_header(&state.latest_block_header, &parent_root),
        "hash genesis header for mismatch test");

    LanternBlock block;
    memset(&block, 0, sizeof(block));
    block.slot = 0;
    expect_zero(lantern_proposer_for_slot(block.slot, validator_count, &block.proposer_index), "compute proposer");
    block.parent_root = parent_root;
    lantern_block_body_init(&block.body);

    LanternRoot expected_state_root;
    expect_ssz_success(lantern_hash_tree_root_state(&state, &expected_state_root), "hash expected state root");
    block.state_root = expected_state_root;
    block.state_root.bytes[0] ^= 0xFF;

    LanternSignedBlock signed_block;
    memset(&signed_block, 0, sizeof(signed_block));
    signed_block.block = block;

    if (lantern_state_transition(&state, &signed_block) == 0) {
        fprintf(stderr, "genesis state mismatch block was incorrectly accepted\n");
        lantern_block_body_reset(&block.body);
        lantern_state_reset(&state);
        return 1;
    }

    lantern_block_body_reset(&block.body);
    lantern_state_reset(&state);
    return 0;
}

static void build_vote(
    LanternVote *out_vote,
    LanternSignature *out_signature,
    uint64_t validator_id,
    uint64_t slot,
    const LanternCheckpoint *source,
    const LanternCheckpoint *target_template,
    uint8_t signature_marker) {
    if (!out_vote) {
        return;
    }
    memset(out_vote, 0, sizeof(*out_vote));
    out_vote->validator_id = validator_id;
    out_vote->slot = slot;
    out_vote->source = *source;
    out_vote->target = *target_template;
    out_vote->head = out_vote->target;
    uint8_t sig_marker = signature_marker ? signature_marker : (uint8_t)(validator_id + slot);
    if (out_signature) {
        fill_signature(out_signature, sig_marker);
    }
}

static int append_aggregated_attestation_from_vote(
    LanternAggregatedAttestations *list,
    const LanternVote *vote) {
    if (!list || !vote) {
        return -1;
    }
    LanternAggregatedAttestation attestation;
    lantern_aggregated_attestation_init(&attestation);
    attestation.data.slot = vote->slot;
    attestation.data.head = vote->head;
    attestation.data.target = vote->target;
    attestation.data.source = vote->source;
    size_t bit_length = (size_t)vote->validator_id + 1u;
    if (lantern_bitlist_resize(&attestation.aggregation_bits, bit_length) != 0) {
        lantern_aggregated_attestation_reset(&attestation);
        return -1;
    }
    if (lantern_bitlist_set(&attestation.aggregation_bits, (size_t)vote->validator_id, true) != 0) {
        lantern_aggregated_attestation_reset(&attestation);
        return -1;
    }
    int rc = lantern_aggregated_attestations_append(list, &attestation);
    lantern_aggregated_attestation_reset(&attestation);
    return rc;
}

static int build_cached_proof_for_vote(
    LanternAggregatedSignatureProof *out_proof,
    uint64_t validator_id,
    uint8_t marker) {
    if (!out_proof || validator_id >= LANTERN_VALIDATOR_REGISTRY_LIMIT) {
        return -1;
    }
    lantern_aggregated_signature_proof_init(out_proof);
    size_t bit_length = (size_t)validator_id + 1u;
    if (lantern_bitlist_resize(&out_proof->participants, bit_length) != 0) {
        lantern_aggregated_signature_proof_reset(out_proof);
        return -1;
    }
    if (lantern_bitlist_set(&out_proof->participants, (size_t)validator_id, true) != 0) {
        lantern_aggregated_signature_proof_reset(out_proof);
        return -1;
    }
    if (lantern_byte_list_resize(&out_proof->proof_data, 8u) != 0) {
        lantern_aggregated_signature_proof_reset(out_proof);
        return -1;
    }
    for (size_t i = 0; i < out_proof->proof_data.length; ++i) {
        out_proof->proof_data.data[i] = (uint8_t)(marker + (uint8_t)i);
    }
    return 0;
}

static int build_single_participant_cached_proof(
    LanternAggregatedSignatureProof *out_proof,
    uint64_t validator_id,
    const uint8_t *pubkey,
    const LanternSignature *signature,
    const LanternRoot *data_root,
    uint64_t epoch) {
    if (!out_proof || !pubkey || !signature || !data_root || validator_id >= LANTERN_VALIDATOR_REGISTRY_LIMIT) {
        return -1;
    }

    lantern_aggregated_signature_proof_init(out_proof);
    size_t bit_length = (size_t)validator_id + 1u;
    if (lantern_bitlist_resize(&out_proof->participants, bit_length) != 0) {
        lantern_aggregated_signature_proof_reset(out_proof);
        return -1;
    }
    if (lantern_bitlist_set(&out_proof->participants, (size_t)validator_id, true) != 0) {
        lantern_aggregated_signature_proof_reset(out_proof);
        return -1;
    }

    const uint8_t *pubkey_refs[1] = {pubkey};
    if (!lantern_signature_aggregate(
            pubkey_refs,
            signature,
            1u,
            data_root,
            epoch,
            &out_proof->proof_data)) {
        lantern_aggregated_signature_proof_reset(out_proof);
        return -1;
    }
    return 0;
}

static int build_multi_participant_cached_proof(
    LanternAggregatedSignatureProof *out_proof,
    const uint64_t *validator_ids,
    const uint8_t *const *pubkeys,
    const LanternSignature *signatures,
    size_t count,
    const LanternRoot *data_root,
    uint64_t epoch) {
    if (!out_proof || !validator_ids || !pubkeys || !signatures || count == 0u || !data_root) {
        return -1;
    }

    lantern_aggregated_signature_proof_init(out_proof);

    size_t bit_length = 0u;
    for (size_t i = 0; i < count; ++i) {
        if (!pubkeys[i] || validator_ids[i] >= LANTERN_VALIDATOR_REGISTRY_LIMIT) {
            lantern_aggregated_signature_proof_reset(out_proof);
            return -1;
        }
        size_t candidate_length = (size_t)validator_ids[i] + 1u;
        if (candidate_length > bit_length) {
            bit_length = candidate_length;
        }
    }
    if (lantern_bitlist_resize(&out_proof->participants, bit_length) != 0) {
        lantern_aggregated_signature_proof_reset(out_proof);
        return -1;
    }
    for (size_t i = 0; i < count; ++i) {
        if (lantern_bitlist_set(&out_proof->participants, (size_t)validator_ids[i], true) != 0) {
            lantern_aggregated_signature_proof_reset(out_proof);
            return -1;
        }
    }

    if (!lantern_signature_aggregate(
            pubkeys,
            signatures,
            count,
            data_root,
            epoch,
            &out_proof->proof_data)) {
        lantern_aggregated_signature_proof_reset(out_proof);
        return -1;
    }
    return 0;
}

static int seed_known_payload_for_vote(
    LanternState *state,
    const LanternVote *vote,
    uint8_t marker) {
    (void)marker;
    if (!state || !vote) {
        return -1;
    }
    LanternStore *store = lantern_test_state_store_ensure(state);
    if (!store) {
        return -1;
    }

    LanternRoot data_root;
    if (lantern_hash_tree_root_attestation_data(&vote->data, &data_root) != SSZ_SUCCESS) {
        return -1;
    }

    struct PQSignatureSchemePublicKey *pubkey = NULL;
    struct PQSignatureSchemeSecretKey *secret = NULL;
    uint8_t serialized_pubkey[LANTERN_VALIDATOR_PUBKEY_SIZE];
    LanternSignature signature;
    memset(&signature, 0, sizeof(signature));
    if (generate_test_keypair(&pubkey, &secret) != 0) {
        return -1;
    }
    if (serialize_test_pubkey(pubkey, serialized_pubkey) != 0) {
        pq_secret_key_free(secret);
        pq_public_key_free(pubkey);
        return -1;
    }
    size_t validator_count = (size_t)state->config.num_validators;
    size_t validator_index = (size_t)vote->validator_id;
    if (validator_count == 0u || validator_index >= validator_count) {
        pq_secret_key_free(secret);
        pq_public_key_free(pubkey);
        return -1;
    }
    if (!state->validators || state->validator_count != validator_count) {
        uint8_t *attestation_pubkeys =
            calloc(validator_count, LANTERN_VALIDATOR_PUBKEY_SIZE);
        uint8_t *proposal_pubkeys =
            calloc(validator_count, LANTERN_VALIDATOR_PUBKEY_SIZE);
        if (!attestation_pubkeys || !proposal_pubkeys) {
            free(attestation_pubkeys);
            free(proposal_pubkeys);
            pq_secret_key_free(secret);
            pq_public_key_free(pubkey);
            return -1;
        }
        if (state->validators) {
            size_t copy_count = state->validator_count;
            if (copy_count > validator_count) {
                copy_count = validator_count;
            }
            for (size_t i = 0; i < copy_count; ++i) {
                memcpy(
                    attestation_pubkeys + (i * LANTERN_VALIDATOR_PUBKEY_SIZE),
                    state->validators[i].attestation_pubkey,
                    LANTERN_VALIDATOR_PUBKEY_SIZE);
                memcpy(
                    proposal_pubkeys + (i * LANTERN_VALIDATOR_PUBKEY_SIZE),
                    state->validators[i].proposal_pubkey,
                    LANTERN_VALIDATOR_PUBKEY_SIZE);
            }
        }
        if (lantern_state_set_validator_pubkeys_dual(
                state,
                attestation_pubkeys,
                proposal_pubkeys,
                validator_count)
            != 0) {
            free(attestation_pubkeys);
            free(proposal_pubkeys);
            pq_secret_key_free(secret);
            pq_public_key_free(pubkey);
            return -1;
        }
        free(attestation_pubkeys);
        free(proposal_pubkeys);
    }
    memcpy(
        state->validators[validator_index].attestation_pubkey,
        serialized_pubkey,
        LANTERN_VALIDATOR_PUBKEY_SIZE);
    memcpy(
        state->validators[validator_index].proposal_pubkey,
        serialized_pubkey,
        LANTERN_VALIDATOR_PUBKEY_SIZE);
    if (!lantern_signature_sign(secret, vote->slot, &data_root, &signature)) {
        pq_secret_key_free(secret);
        pq_public_key_free(pubkey);
        return -1;
    }

    LanternAggregatedSignatureProof proof;
    if (build_single_participant_cached_proof(
            &proof,
            vote->validator_id,
            serialized_pubkey,
            &signature,
            &data_root,
            vote->slot)
        != 0) {
        pq_secret_key_free(secret);
        pq_public_key_free(pubkey);
        return -1;
    }
    int rc = lantern_store_add_known_aggregated_payload(
        store,
        &data_root,
        &vote->data,
        &proof,
        vote->target.slot);
    lantern_aggregated_signature_proof_reset(&proof);
    pq_secret_key_free(secret);
    pq_public_key_free(pubkey);
    return rc;
}

static int test_attestations_single_vote_justifies(void) {
    LanternState state;
    lantern_state_init(&state);
    const uint64_t genesis_time = 500;
    const uint64_t validator_count = 1;
    expect_zero(
        lantern_state_generate_genesis(&state, genesis_time, validator_count),
        "genesis for single-vote justification test");
    mark_slot_justified_for_tests(&state, state.latest_justified.slot);
    populate_historical_hashes_for_tests(&state, 1);

    LanternAttestations attestations;
    lantern_attestations_init(&attestations);
    LanternSignatureList signatures;
    lantern_signature_list_init(&signatures);

    LanternCheckpoint source_checkpoint = state.latest_justified;
    source_checkpoint.root = get_historical_root_for_tests(&state, source_checkpoint.slot);
    LanternCheckpoint target_checkpoint = source_checkpoint;
    target_checkpoint.slot = source_checkpoint.slot + 1u;
    target_checkpoint.root = get_historical_root_for_tests(&state, target_checkpoint.slot);

    expect_zero(lantern_attestations_resize(&attestations, 1), "resize single attestation");
    expect_zero(lantern_signature_list_resize(&signatures, 1), "resize single signature");
    build_vote(
        &attestations.data[0],
        &signatures.data[0],
        0,
        target_checkpoint.slot,
        &source_checkpoint,
        &target_checkpoint,
        0x20);

    expect_zero(
        lantern_state_process_attestations(&state, &attestations, &signatures),
        "process single attestation");
    assert(state.latest_justified.slot == target_checkpoint.slot);
    assert(state.latest_finalized.slot == source_checkpoint.slot);

    lantern_attestations_reset(&attestations);
    lantern_signature_list_reset(&signatures);
    lantern_state_reset(&state);
    return 0;
}

static int test_attestations_require_justified_source(void) {
    LanternState state;
    lantern_state_init(&state);
    expect_zero(lantern_state_generate_genesis(&state, 600, 4), "genesis for justified source test");
    mark_slot_justified_for_tests(&state, state.latest_justified.slot);

    LanternAttestations attestations;
    lantern_attestations_init(&attestations);
    LanternSignatureList signatures;
    lantern_signature_list_init(&signatures);

    LanternCheckpoint source_checkpoint = state.latest_justified;
    source_checkpoint.slot = state.latest_justified.slot + 2;
    LanternCheckpoint target_checkpoint = source_checkpoint;
    target_checkpoint.slot = source_checkpoint.slot + 1;
    populate_historical_hashes_for_tests(&state, target_checkpoint.slot);
    source_checkpoint.root = get_historical_root_for_tests(&state, source_checkpoint.slot);
    target_checkpoint.root = get_historical_root_for_tests(&state, target_checkpoint.slot);

    size_t quorum = (size_t)lantern_consensus_quorum_threshold(state.config.num_validators);
    expect_zero(
        lantern_attestations_resize(&attestations, quorum),
        "resize unjustified source attestations");
    expect_zero(
        lantern_signature_list_resize(&signatures, quorum),
        "resize unjustified source signatures");
    for (size_t i = 0; i < quorum; ++i) {
        build_vote(
            &attestations.data[i],
            &signatures.data[i],
            (uint64_t)i,
            target_checkpoint.slot,
            &source_checkpoint,
            &target_checkpoint,
            (uint8_t)(0x30u + i));
    }

    expect_zero(
        lantern_state_process_attestations(&state, &attestations, &signatures),
        "process unjustified source attestation");
    assert(state.latest_justified.slot == 0);
    assert(state.latest_finalized.slot == 0);

    lantern_attestations_reset(&attestations);
    lantern_signature_list_reset(&signatures);
    lantern_state_reset(&state);
    return 0;
}

static int test_attestations_accept_duplicate_votes(void) {
    LanternState state;
    lantern_state_init(&state);
    expect_zero(lantern_state_generate_genesis(&state, 700, 3), "genesis for duplicate vote test");
    mark_slot_justified_for_tests(&state, state.latest_justified.slot);

    LanternAttestations attestations;
    lantern_attestations_init(&attestations);
    LanternSignatureList signatures;
    lantern_signature_list_init(&signatures);
    expect_zero(lantern_attestations_resize(&attestations, 2), "double vote resize");
    expect_zero(lantern_signature_list_resize(&signatures, 2), "double vote signature resize");

    populate_historical_hashes_for_tests(&state, 1);
    LanternCheckpoint source_checkpoint = state.latest_justified;
    source_checkpoint.root = get_historical_root_for_tests(&state, source_checkpoint.slot);
    LanternCheckpoint target_checkpoint = source_checkpoint;
    target_checkpoint.slot = 1;
    target_checkpoint.root = get_historical_root_for_tests(&state, target_checkpoint.slot);

    build_vote(&attestations.data[0], &signatures.data[0], 0, 1, &source_checkpoint, &target_checkpoint, 0x11);
    build_vote(&attestations.data[1], &signatures.data[1], 0, 1, &source_checkpoint, &target_checkpoint, 0x22);

    expect_zero(
        lantern_state_process_attestations(&state, &attestations, &signatures),
        "process duplicate votes");
    assert(state.latest_justified.slot == 0);
    assert(state.latest_finalized.slot == 0);

    lantern_attestations_reset(&attestations);
    lantern_signature_list_reset(&signatures);
    lantern_state_reset(&state);
    return 0;
}

static void setup_prejustified_consecutive_source(
    LanternState *state,
    LanternCheckpoint *out_source,
    LanternCheckpoint *out_target,
    LanternCheckpoint *out_alt_source,
    uint8_t source_marker,
    uint8_t target_marker,
    uint8_t alt_marker) {
    assert(state != NULL);
    assert(out_source != NULL);
    assert(out_target != NULL);
    assert(out_alt_source != NULL);

    mark_slot_justified_for_tests(state, state->latest_justified.slot);
    uint64_t slot_one = state->latest_justified.slot + 1u;
    mark_slot_justified_for_tests(state, slot_one);
    state->latest_justified.slot = slot_one;
    fill_root(&state->latest_justified.root, source_marker);

    uint64_t target_slot = slot_one + 1u;
    expect_zero(
        lantern_root_list_resize(&state->historical_block_hashes, (size_t)(target_slot + 1u)),
        "resize historical hashes for consecutive attestation test");
    fill_root(&state->historical_block_hashes.items[slot_one - 1u], alt_marker);
    fill_root(&state->historical_block_hashes.items[slot_one], source_marker);
    fill_root(&state->historical_block_hashes.items[target_slot], target_marker);

    *out_source = state->latest_justified;
    *out_target = *out_source;
    out_target->slot = target_slot;
    fill_root(&out_target->root, target_marker);

    *out_alt_source = *out_source;
    out_alt_source->slot = out_source->slot - 1u;
    fill_root(&out_alt_source->root, alt_marker);
}

static int test_attestations_nonconsecutive_followup_does_not_finalize(void) {
    LanternState state;
    lantern_state_init(&state);
    expect_zero(lantern_state_generate_genesis(&state, 730, 2), "genesis for nonconsecutive attestation test");

    LanternCheckpoint consecutive_source;
    LanternCheckpoint target_checkpoint;
    LanternCheckpoint non_consecutive_source;
    setup_prejustified_consecutive_source(
        &state,
        &consecutive_source,
        &target_checkpoint,
        &non_consecutive_source,
        0xA1,
        0xA2,
        0xA3);

    LanternAttestations attestations;
    lantern_attestations_init(&attestations);
    LanternSignatureList signatures;
    lantern_signature_list_init(&signatures);
    expect_zero(lantern_attestations_resize(&attestations, 2), "resize nonconsecutive attestations");
    expect_zero(lantern_signature_list_resize(&signatures, 2), "resize nonconsecutive signatures");

    build_vote(
        &attestations.data[0],
        &signatures.data[0],
        0,
        target_checkpoint.slot,
        &consecutive_source,
        &target_checkpoint,
        0x51);
    build_vote(
        &attestations.data[1],
        &signatures.data[1],
        1,
        target_checkpoint.slot,
        &non_consecutive_source,
        &target_checkpoint,
        0x52);

    uint64_t expected_finalized_slot = state.latest_finalized.slot;
    expect_zero(
        lantern_state_process_attestations(&state, &attestations, &signatures),
        "process nonconsecutive attestations");
    assert(state.latest_justified.slot == target_checkpoint.slot);
    assert(state.latest_finalized.slot == expected_finalized_slot);

    lantern_attestations_reset(&attestations);
    lantern_signature_list_reset(&signatures);
    lantern_state_reset(&state);
    return 0;
}

static int test_attestations_finalize_after_second_consecutive_vote(void) {
    LanternState state;
    lantern_state_init(&state);
    expect_zero(lantern_state_generate_genesis(&state, 740, 2), "genesis for consecutive attestation test");

    LanternCheckpoint consecutive_source;
    LanternCheckpoint target_checkpoint;
    LanternCheckpoint unused_alt_source;
    setup_prejustified_consecutive_source(
        &state,
        &consecutive_source,
        &target_checkpoint,
        &unused_alt_source,
        0xB1,
        0xB2,
        0xB3);

    LanternAttestations single_vote;
    lantern_attestations_init(&single_vote);
    LanternSignatureList single_sig;
    lantern_signature_list_init(&single_sig);
    expect_zero(lantern_attestations_resize(&single_vote, 1), "resize single vote for pre-finalization");
    expect_zero(lantern_signature_list_resize(&single_sig, 1), "resize single signature for pre-finalization");
    build_vote(
        &single_vote.data[0],
        &single_sig.data[0],
        0,
        target_checkpoint.slot,
        &consecutive_source,
        &target_checkpoint,
        0x61);

    expect_zero(
        lantern_state_process_attestations(&state, &single_vote, &single_sig),
        "process initial consecutive attestation");
    assert(state.latest_finalized.slot != consecutive_source.slot);

    LanternAttestations second_vote;
    lantern_attestations_init(&second_vote);
    LanternSignatureList second_sig;
    lantern_signature_list_init(&second_sig);
    expect_zero(lantern_attestations_resize(&second_vote, 1), "resize follow-up attestation");
    expect_zero(lantern_signature_list_resize(&second_sig, 1), "resize follow-up signature");
    build_vote(
        &second_vote.data[0],
        &second_sig.data[0],
        1,
        target_checkpoint.slot,
        &consecutive_source,
        &target_checkpoint,
        0x62);

    expect_zero(
        lantern_state_process_attestations(&state, &second_vote, &second_sig),
        "process finalizing consecutive attestation");
    assert(state.latest_finalized.slot == consecutive_source.slot);

    lantern_attestations_reset(&single_vote);
    lantern_signature_list_reset(&single_sig);
    lantern_attestations_reset(&second_vote);
    lantern_signature_list_reset(&second_sig);
    lantern_state_reset(&state);
    return 0;
}

static int test_attestations_finalize_across_gap(void) {
    LanternState state;
    lantern_state_init(&state);
    expect_zero(lantern_state_generate_genesis(&state, 745, 4), "genesis for gap finalization test");

    mark_slot_justified_for_tests(&state, state.latest_justified.slot);
    uint64_t source_slot = state.latest_justified.slot + 1u;
    mark_slot_justified_for_tests(&state, source_slot);
    state.latest_justified.slot = source_slot;

    LanternCheckpoint source = state.latest_justified;
    LanternCheckpoint target = source;
    target.slot = source.slot + 3u;
    populate_historical_hashes_for_tests(&state, target.slot);
    state.latest_justified.root = get_historical_root_for_tests(&state, source.slot);
    source.root = state.latest_justified.root;
    target.root = get_historical_root_for_tests(&state, target.slot);

    LanternAttestations first_vote;
    lantern_attestations_init(&first_vote);
    LanternSignatureList first_sig;
    lantern_signature_list_init(&first_sig);
    size_t quorum = (size_t)lantern_consensus_quorum_threshold(state.config.num_validators);
    expect_zero(lantern_attestations_resize(&first_vote, quorum), "resize first gap vote");
    expect_zero(lantern_signature_list_resize(&first_sig, quorum), "resize first gap signature");
    for (size_t i = 0; i < quorum; ++i) {
        build_vote(
            &first_vote.data[i],
            &first_sig.data[i],
            (uint64_t)i,
            target.slot,
            &source,
            &target,
            (uint8_t)(0x71u + i));
    }

    expect_zero(lantern_state_process_attestations(&state, &first_vote, &first_sig), "process first gap vote");
    assert(state.latest_finalized.slot != source.slot);
    assert(state.latest_justified.slot == target.slot);

    LanternAttestations second_vote;
    lantern_attestations_init(&second_vote);
    LanternSignatureList second_sig;
    lantern_signature_list_init(&second_sig);
    expect_zero(lantern_attestations_resize(&second_vote, 1), "resize second gap vote");
    expect_zero(lantern_signature_list_resize(&second_sig, 1), "resize second gap signature");
    build_vote(&second_vote.data[0], &second_sig.data[0], 1, target.slot, &source, &target, 0x72);

    expect_zero(lantern_state_process_attestations(&state, &second_vote, &second_sig), "process second gap vote");
    assert(state.latest_finalized.slot != source.slot);

    lantern_attestations_reset(&first_vote);
    lantern_signature_list_reset(&first_sig);
    lantern_attestations_reset(&second_vote);
    lantern_signature_list_reset(&second_sig);
    lantern_state_reset(&state);
    return 0;
}

static int test_attestations_use_updated_finalized_slot_for_target_justifiability(void) {
    LanternState state;
    lantern_state_init(&state);
    expect_zero(
        lantern_state_generate_genesis(&state, 748, 3),
        "genesis for updated finalized target-justifiability test");

    populate_historical_hashes_for_tests(&state, 9);

    state.latest_finalized.slot = 0;
    state.latest_finalized.root = get_historical_root_for_tests(&state, 0);
    state.latest_justified.slot = 1;
    state.latest_justified.root = get_historical_root_for_tests(&state, 1);
    mark_slot_justified_for_tests(&state, 1);

    LanternCheckpoint first_source = state.latest_justified;
    LanternCheckpoint first_target = first_source;
    first_target.slot = 2;
    first_target.root = get_historical_root_for_tests(&state, first_target.slot);

    LanternCheckpoint second_source = first_target;
    LanternCheckpoint second_target = second_source;
    second_target.slot = 9;
    second_target.root = get_historical_root_for_tests(&state, second_target.slot);

    LanternAttestations attestations;
    lantern_attestations_init(&attestations);
    LanternSignatureList signatures;
    lantern_signature_list_init(&signatures);
    expect_zero(
        lantern_attestations_resize(&attestations, 4),
        "resize updated finalized target-justifiability attestations");
    expect_zero(
        lantern_signature_list_resize(&signatures, 4),
        "resize updated finalized target-justifiability signatures");

    build_vote(
        &attestations.data[0],
        &signatures.data[0],
        0,
        first_target.slot,
        &first_source,
        &first_target,
        0xA8);
    build_vote(
        &attestations.data[1],
        &signatures.data[1],
        1,
        first_target.slot,
        &first_source,
        &first_target,
        0xA9);
    build_vote(
        &attestations.data[2],
        &signatures.data[2],
        0,
        second_target.slot,
        &second_source,
        &second_target,
        0xAA);
    build_vote(
        &attestations.data[3],
        &signatures.data[3],
        1,
        second_target.slot,
        &second_source,
        &second_target,
        0xAB);

    expect_zero(
        lantern_state_process_attestations(&state, &attestations, &signatures),
        "process updated finalized target-justifiability attestations");

    assert(state.latest_finalized.slot == first_source.slot);
    assert(state.latest_justified.slot == first_target.slot);
    assert(state.justification_roots.length == 0);

    bool target_justified = true;
    expect_zero(
        lantern_state_get_justified_slot_bit(&state, second_target.slot, &target_justified),
        "read skipped target justification bit");
    assert(!target_justified);

    lantern_attestations_reset(&attestations);
    lantern_signature_list_reset(&signatures);
    lantern_state_reset(&state);
    return 0;
}

static int test_attestations_use_updated_finalized_slot_for_gap_check(void) {
    LanternState state;
    lantern_state_init(&state);
    expect_zero(
        lantern_state_generate_genesis(&state, 749, 3),
        "genesis for updated finalized gap-check test");

    populate_historical_hashes_for_tests(&state, 9);

    state.latest_finalized.slot = 0;
    state.latest_finalized.root = get_historical_root_for_tests(&state, 0);
    state.latest_justified.slot = 3;
    state.latest_justified.root = get_historical_root_for_tests(&state, 3);

    expect_zero(
        lantern_bitlist_resize(&state.justified_slots, 6),
        "resize justified slots for updated finalized gap-check test");
    assert(state.justified_slots.bytes != NULL);
    memset(state.justified_slots.bytes, 0, state.justified_slots.capacity);
    mark_slot_justified_for_tests(&state, 3);
    mark_slot_justified_for_tests(&state, 6);

    LanternCheckpoint first_source = state.latest_justified;
    LanternCheckpoint first_target = first_source;
    first_target.slot = 4;
    first_target.root = get_historical_root_for_tests(&state, first_target.slot);

    LanternCheckpoint second_source = first_source;
    second_source.slot = 6;
    second_source.root = get_historical_root_for_tests(&state, second_source.slot);

    LanternCheckpoint second_target = second_source;
    second_target.slot = 9;
    second_target.root = get_historical_root_for_tests(&state, second_target.slot);

    LanternAttestations attestations;
    lantern_attestations_init(&attestations);
    LanternSignatureList signatures;
    lantern_signature_list_init(&signatures);
    expect_zero(
        lantern_attestations_resize(&attestations, 4),
        "resize updated finalized gap-check attestations");
    expect_zero(
        lantern_signature_list_resize(&signatures, 4),
        "resize updated finalized gap-check signatures");

    build_vote(
        &attestations.data[0],
        &signatures.data[0],
        0,
        first_target.slot,
        &first_source,
        &first_target,
        0xAC);
    build_vote(
        &attestations.data[1],
        &signatures.data[1],
        1,
        first_target.slot,
        &first_source,
        &first_target,
        0xAD);
    build_vote(
        &attestations.data[2],
        &signatures.data[2],
        0,
        second_target.slot,
        &second_source,
        &second_target,
        0xAE);
    build_vote(
        &attestations.data[3],
        &signatures.data[3],
        1,
        second_target.slot,
        &second_source,
        &second_target,
        0xAF);

    expect_zero(
        lantern_state_process_attestations(&state, &attestations, &signatures),
        "process updated finalized gap-check attestations");

    assert(state.latest_finalized.slot == first_source.slot);
    assert(state.latest_justified.slot == second_target.slot);

    lantern_attestations_reset(&attestations);
    lantern_signature_list_reset(&signatures);
    lantern_state_reset(&state);
    return 0;
}

static int test_attestations_do_not_refinalize_source_at_finalized_boundary(void) {
    LanternState state;
    lantern_state_init(&state);
    const uint64_t validator_count = 3;
    expect_zero(
        lantern_state_generate_genesis(&state, 751, validator_count),
        "genesis for no refinalize boundary test");
    populate_historical_hashes_for_tests(&state, 2);

    state.latest_finalized.slot = 1;
    state.latest_finalized.root = get_historical_root_for_tests(&state, 1);
    state.latest_justified = state.latest_finalized;

    LanternCheckpoint source = state.latest_finalized;
    LanternCheckpoint target = source;
    target.slot = 2;
    target.root = get_historical_root_for_tests(&state, target.slot);

    LanternAttestations attestations;
    lantern_attestations_init(&attestations);
    LanternSignatureList signatures;
    lantern_signature_list_init(&signatures);
    size_t quorum = (size_t)lantern_consensus_quorum_threshold(validator_count);
    expect_zero(
        lantern_attestations_resize(&attestations, quorum),
        "resize no refinalize boundary attestations");
    expect_zero(
        lantern_signature_list_resize(&signatures, quorum),
        "resize no refinalize boundary signatures");
    for (size_t i = 0; i < quorum; ++i) {
        build_vote(
            &attestations.data[i],
            &signatures.data[i],
            (uint64_t)i,
            target.slot,
            &source,
            &target,
            (uint8_t)(0xB0u + i));
    }

    lean_metrics_reset();
    expect_zero(
        lantern_state_process_attestations(&state, &attestations, &signatures),
        "process no refinalize boundary attestations");

    assert(state.latest_finalized.slot == source.slot);
    assert(checkpoints_equal(&state.latest_finalized, &source));
    assert(state.latest_justified.slot == target.slot);

    struct lean_metrics_snapshot metrics;
    lean_metrics_snapshot(&metrics);
    assert(metrics.finalizations_success_total == 0);
    assert(metrics.finalizations_error_total == 0);
    lean_metrics_reset();

    lantern_attestations_reset(&attestations);
    lantern_signature_list_reset(&signatures);
    lantern_state_reset(&state);
    return 0;
}

static int test_attestations_do_not_regress_latest_justified(void) {
    LanternState state;
    lantern_state_init(&state);
    const uint64_t validator_count = 6;
    expect_zero(
        lantern_state_generate_genesis(&state, 750, validator_count),
        "genesis for latest justified regression test");
    populate_historical_hashes_for_tests(&state, 22);

    state.latest_finalized.slot = 16;
    state.latest_finalized.root = get_historical_root_for_tests(&state, 16);
    state.latest_justified.slot = 22;
    state.latest_justified.root = get_historical_root_for_tests(&state, 22);
    expect_zero(
        lantern_bitlist_resize(&state.justified_slots, 6),
        "resize justified slots for latest justified regression test");
    assert(state.justified_slots.bytes != NULL);
    memset(state.justified_slots.bytes, 0, state.justified_slots.capacity);
    mark_slot_justified_for_tests(&state, 19);
    mark_slot_justified_for_tests(&state, state.latest_justified.slot);

    LanternCheckpoint source = {
        .slot = 19,
        .root = get_historical_root_for_tests(&state, 19),
    };
    LanternCheckpoint stale_target = {
        .slot = 20,
        .root = get_historical_root_for_tests(&state, 20),
    };
    LanternCheckpoint original_latest = state.latest_justified;

    LanternAttestations attestations;
    lantern_attestations_init(&attestations);
    LanternSignatureList signatures;
    lantern_signature_list_init(&signatures);
    size_t quorum = (size_t)lantern_consensus_quorum_threshold(validator_count);
    expect_zero(
        lantern_attestations_resize(&attestations, quorum),
        "resize stale target attestations");
    expect_zero(
        lantern_signature_list_resize(&signatures, quorum),
        "resize stale target signatures");
    for (size_t i = 0; i < quorum; ++i) {
        build_vote(
            &attestations.data[i],
            &signatures.data[i],
            (uint64_t)i,
            stale_target.slot,
            &source,
            &stale_target,
            (uint8_t)(0xD0u + i));
    }

    expect_zero(
        lantern_state_process_attestations(&state, &attestations, &signatures),
        "process stale target quorum");

    assert(checkpoints_equal(&state.latest_justified, &original_latest));
    assert(state.latest_finalized.slot == source.slot);

    bool stale_target_justified = false;
    expect_zero(
        lantern_state_get_justified_slot_bit(&state, stale_target.slot, &stale_target_justified),
        "read stale target justified bit");
    assert(stale_target_justified);

    lantern_attestations_reset(&attestations);
    lantern_signature_list_reset(&signatures);
    lantern_state_reset(&state);
    return 0;
}

static int test_pruning_keeps_pending_justifications(void) {
    LanternState state;
    lantern_state_init(&state);
    const uint64_t validator_count = 3;
    expect_zero(lantern_state_generate_genesis(&state, 760, validator_count), "genesis for pruning test");
    mark_slot_justified_for_tests(&state, state.latest_justified.slot);
    populate_historical_hashes_for_tests(&state, 5);

    size_t quorum = (size_t)lantern_consensus_quorum_threshold(state.config.num_validators);
    LanternAttestations attestations;
    lantern_attestations_init(&attestations);
    LanternSignatureList signatures;
    lantern_signature_list_init(&signatures);
    expect_zero(lantern_attestations_resize(&attestations, quorum), "resize pruning attestations");
    expect_zero(lantern_signature_list_resize(&signatures, quorum), "resize pruning signatures");

    LanternCheckpoint source_0 = state.latest_justified;
    source_0.root = get_historical_root_for_tests(&state, source_0.slot);
    LanternCheckpoint target_1 = source_0;
    target_1.slot = source_0.slot + 1u;
    target_1.root = get_historical_root_for_tests(&state, target_1.slot);

    for (size_t i = 0; i < quorum; ++i) {
        build_vote(
            &attestations.data[i],
            &signatures.data[i],
            (uint64_t)i,
            target_1.slot,
            &source_0,
            &target_1,
            (uint8_t)(0x81u + i));
    }

    expect_zero(
        lantern_state_process_attestations(&state, &attestations, &signatures),
        "justify slot 1 for pruning test");
    assert(state.latest_justified.slot == target_1.slot);
    assert(state.latest_finalized.slot == source_0.slot);

    expect_zero(lantern_root_list_resize(&state.justification_roots, 1), "resize pending roots");
    state.justification_roots.items[0] = get_historical_root_for_tests(&state, 3);
    expect_zero(
        lantern_bitlist_resize(&state.justification_validators, validator_count),
        "resize pending validators");
    expect_zero(
        lantern_bitlist_set(&state.justification_validators, 0, true),
        "mark pending validator vote");

    LanternCheckpoint source_1 = target_1;
    LanternCheckpoint target_2 = source_1;
    target_2.slot = source_1.slot + 1u;
    target_2.root = get_historical_root_for_tests(&state, target_2.slot);

    expect_zero(lantern_attestations_resize(&attestations, quorum), "resize finalization attestations");
    expect_zero(lantern_signature_list_resize(&signatures, quorum), "resize finalization signatures");
    for (size_t i = 0; i < quorum; ++i) {
        build_vote(
            &attestations.data[i],
            &signatures.data[i],
            (uint64_t)i,
            target_2.slot,
            &source_1,
            &target_2,
            (uint8_t)(0x91u + i));
    }

    expect_zero(
        lantern_state_process_attestations(&state, &attestations, &signatures),
        "finalize slot 1 for pruning test");
    assert(state.latest_finalized.slot == source_1.slot);
    assert(state.latest_justified.slot == target_2.slot);
    assert(state.justification_roots.length == 1);
    assert(memcmp(
               state.justification_roots.items[0].bytes,
               get_historical_root_for_tests(&state, 3).bytes,
               LANTERN_ROOT_SIZE)
           == 0);

    lantern_attestations_reset(&attestations);
    lantern_signature_list_reset(&signatures);
    lantern_state_reset(&state);
    return 0;
}

static int test_pending_votes_survive_interleaved_justification_and_finalization(void) {
    LanternState state;
    lantern_state_init(&state);
    const uint64_t validator_count = 5;
    expect_zero(
        lantern_state_generate_genesis(&state, 780, validator_count),
        "genesis for interleaved pending votes test");

    const uint64_t finalized_slot = 334u;
    const uint64_t justified_slot = 340u;
    const uint64_t target_justified_slot = 343u;
    const uint64_t target_pending_slot = 346u;
    const uint64_t block_slot = 354u;
    const uint64_t anchor = finalized_slot + 1u;
    const size_t validator_count_sz = (size_t)validator_count;

    populate_historical_hashes_for_tests(&state, target_pending_slot);

    state.latest_finalized.slot = finalized_slot;
    state.latest_finalized.root = get_historical_root_for_tests(&state, finalized_slot);
    state.latest_justified.slot = justified_slot;
    state.latest_justified.root = get_historical_root_for_tests(&state, justified_slot);

    expect_zero(
        lantern_bitlist_resize(&state.justified_slots, (size_t)(target_pending_slot - anchor + 1u)),
        "resize justified slots for interleaved pending votes test");
    assert(state.justified_slots.bytes != NULL);
    memset(state.justified_slots.bytes, 0, state.justified_slots.capacity);
    mark_slot_justified_for_tests(&state, justified_slot);

    LanternCheckpoint source = state.latest_justified;

    LanternCheckpoint target_justified = source;
    target_justified.slot = target_justified_slot;
    target_justified.root = get_historical_root_for_tests(&state, target_justified.slot);

    LanternCheckpoint target_pending = source;
    target_pending.slot = target_pending_slot;
    target_pending.root = get_historical_root_for_tests(&state, target_pending.slot);

    expect_zero(
        lantern_root_list_resize(&state.justification_roots, 2),
        "resize pending roots for interleaved pending votes test");
    state.justification_roots.items[0] = target_justified.root;
    state.justification_roots.items[1] = target_pending.root;

    expect_zero(
        lantern_bitlist_resize(&state.justification_validators, 2u * validator_count_sz),
        "resize pending validator bits for interleaved pending votes test");
    assert(state.justification_validators.bytes != NULL);
    memset(state.justification_validators.bytes, 0, state.justification_validators.capacity);

    /* Pre-slot-354 pending votes:
     *   root@343 -> validators {0,2,4}
     *   root@346 -> validators {0,3}
     */
    expect_zero(
        lantern_bitlist_set(&state.justification_validators, 0, true),
        "seed root@343 vote for validator 0");
    expect_zero(
        lantern_bitlist_set(&state.justification_validators, 2, true),
        "seed root@343 vote for validator 2");
    expect_zero(
        lantern_bitlist_set(&state.justification_validators, 4, true),
        "seed root@343 vote for validator 4");
    expect_zero(
        lantern_bitlist_set(&state.justification_validators, validator_count_sz + 0u, true),
        "seed root@346 vote for validator 0");
    expect_zero(
        lantern_bitlist_set(&state.justification_validators, validator_count_sz + 3u, true),
        "seed root@346 vote for validator 3");

    LanternAttestations attestations;
    lantern_attestations_init(&attestations);
    LanternSignatureList signatures;
    lantern_signature_list_init(&signatures);
    expect_zero(
        lantern_attestations_resize(&attestations, 4),
        "resize attestations for interleaved pending votes test");
    expect_zero(
        lantern_signature_list_resize(&signatures, 4),
        "resize signatures for interleaved pending votes test");

    build_vote(
        &attestations.data[0],
        &signatures.data[0],
        2,
        block_slot,
        &source,
        &target_justified,
        0xA1);
    build_vote(
        &attestations.data[1],
        &signatures.data[1],
        3,
        block_slot,
        &source,
        &target_justified,
        0xA2);
    build_vote(
        &attestations.data[2],
        &signatures.data[2],
        0,
        block_slot,
        &source,
        &target_pending,
        0xA3);
    build_vote(
        &attestations.data[3],
        &signatures.data[3],
        4,
        block_slot,
        &source,
        &target_pending,
        0xA4);

    expect_zero(
        lantern_state_process_attestations(&state, &attestations, &signatures),
        "process interleaved pending votes");

    assert(state.latest_justified.slot == target_justified.slot);
    assert(state.latest_finalized.slot == source.slot);
    assert(state.justification_roots.length == 1);
    assert(memcmp(
               state.justification_roots.items[0].bytes,
               target_pending.root.bytes,
               LANTERN_ROOT_SIZE)
           == 0);
    assert(state.justification_validators.bit_length == validator_count_sz);

    const bool expected_votes[5] = {true, false, false, true, true};
    for (size_t i = 0; i < validator_count_sz; ++i) {
        bool voted = bitlist_test_bit(&state.justification_validators, i);
        if (voted != expected_votes[i]) {
            fprintf(
                stderr,
                "unexpected vote bit for validator %zu: expected=%d got=%d\n",
                i,
                expected_votes[i] ? 1 : 0,
                voted ? 1 : 0);
            lantern_attestations_reset(&attestations);
            lantern_signature_list_reset(&signatures);
            lantern_state_reset(&state);
            return 1;
        }
    }

    lantern_attestations_reset(&attestations);
    lantern_signature_list_reset(&signatures);
    lantern_state_reset(&state);
    return 0;
}

static int test_pending_votes_preserved_when_new_root_inserts_before_existing_root(void) {
    LanternState state;
    lantern_state_init(&state);
    const uint64_t validator_count = 5;
    expect_zero(
        lantern_state_generate_genesis(&state, 790, validator_count),
        "genesis for insertion-order pending votes test");

    const uint64_t finalized_slot = 334u;
    const uint64_t justified_slot = 340u;
    const uint64_t target_justified_slot = 343u;
    const uint64_t target_pending_slot = 346u;
    const uint64_t anchor = finalized_slot + 1u;
    const size_t validator_count_sz = (size_t)validator_count;

    populate_historical_hashes_for_tests(&state, target_pending_slot);

    state.latest_finalized.slot = finalized_slot;
    state.latest_finalized.root = get_historical_root_for_tests(&state, finalized_slot);
    state.latest_justified.slot = justified_slot;
    state.latest_justified.root = get_historical_root_for_tests(&state, justified_slot);

    expect_zero(
        lantern_bitlist_resize(&state.justified_slots, (size_t)(target_pending_slot - anchor + 1u)),
        "resize justified slots for insertion-order pending votes test");
    assert(state.justified_slots.bytes != NULL);
    memset(state.justified_slots.bytes, 0, state.justified_slots.capacity);
    mark_slot_justified_for_tests(&state, justified_slot);

    LanternCheckpoint source = state.latest_justified;

    LanternCheckpoint target_justified = source;
    target_justified.slot = target_justified_slot;
    target_justified.root = get_historical_root_for_tests(&state, target_justified.slot);

    LanternCheckpoint target_pending = source;
    target_pending.slot = target_pending_slot;
    target_pending.root = get_historical_root_for_tests(&state, target_pending.slot);

    LanternAttestations attestations;
    lantern_attestations_init(&attestations);
    LanternSignatureList signatures;
    lantern_signature_list_init(&signatures);

    /* Step 1: create pending root@346 with votes {0,3}. */
    expect_zero(lantern_attestations_resize(&attestations, 2), "resize step1 attestations");
    expect_zero(lantern_signature_list_resize(&signatures, 2), "resize step1 signatures");
    build_vote(
        &attestations.data[0],
        &signatures.data[0],
        0,
        352,
        &source,
        &target_pending,
        0xB1);
    build_vote(
        &attestations.data[1],
        &signatures.data[1],
        3,
        352,
        &source,
        &target_pending,
        0xB2);
    expect_zero(
        lantern_state_process_attestations(&state, &attestations, &signatures),
        "process insertion-order step1");

    /* Step 2: add root@343 with votes {0,2,4}. This must insert before root@346. */
    expect_zero(lantern_attestations_resize(&attestations, 3), "resize step2 attestations");
    expect_zero(lantern_signature_list_resize(&signatures, 3), "resize step2 signatures");
    build_vote(
        &attestations.data[0],
        &signatures.data[0],
        0,
        353,
        &source,
        &target_justified,
        0xB3);
    build_vote(
        &attestations.data[1],
        &signatures.data[1],
        2,
        353,
        &source,
        &target_justified,
        0xB4);
    build_vote(
        &attestations.data[2],
        &signatures.data[2],
        4,
        353,
        &source,
        &target_justified,
        0xB5);
    expect_zero(
        lantern_state_process_attestations(&state, &attestations, &signatures),
        "process insertion-order step2");

    /* Step 3: justify root@343 and add one more vote to root@346. */
    expect_zero(lantern_attestations_resize(&attestations, 2), "resize step3 attestations");
    expect_zero(lantern_signature_list_resize(&signatures, 2), "resize step3 signatures");
    build_vote(
        &attestations.data[0],
        &signatures.data[0],
        3,
        354,
        &source,
        &target_justified,
        0xB6);
    build_vote(
        &attestations.data[1],
        &signatures.data[1],
        4,
        354,
        &source,
        &target_pending,
        0xB7);
    expect_zero(
        lantern_state_process_attestations(&state, &attestations, &signatures),
        "process insertion-order step3");

    assert(state.latest_justified.slot == target_justified.slot);
    assert(state.latest_finalized.slot == source.slot);
    assert(state.justification_roots.length == 1);
    assert(memcmp(
               state.justification_roots.items[0].bytes,
               target_pending.root.bytes,
               LANTERN_ROOT_SIZE)
           == 0);
    assert(state.justification_validators.bit_length == validator_count_sz);

    const bool expected_votes[5] = {true, false, false, true, true};
    for (size_t i = 0; i < validator_count_sz; ++i) {
        bool voted = bitlist_test_bit(&state.justification_validators, i);
        if (voted != expected_votes[i]) {
            fprintf(
                stderr,
                "unexpected insertion-order vote bit for validator %zu: expected=%d got=%d\n",
                i,
                expected_votes[i] ? 1 : 0,
                voted ? 1 : 0);
            lantern_attestations_reset(&attestations);
            lantern_signature_list_reset(&signatures);
            lantern_state_reset(&state);
            return 1;
        }
    }

    lantern_attestations_reset(&attestations);
    lantern_signature_list_reset(&signatures);
    lantern_state_reset(&state);
    return 0;
}

static int test_attestations_ignore_zero_hash_votes(void) {
    LanternState state;
    lantern_state_init(&state);
    const uint64_t validator_count = 3;
    expect_zero(
        lantern_state_generate_genesis(&state, 765, validator_count),
        "genesis for zero-hash vote test");
    mark_slot_justified_for_tests(&state, state.latest_justified.slot);
    populate_historical_hashes_for_tests(&state, 1);

    LanternAttestations attestations;
    lantern_attestations_init(&attestations);
    LanternSignatureList signatures;
    lantern_signature_list_init(&signatures);
    expect_zero(lantern_attestations_resize(&attestations, 2), "resize zero-hash attestations");
    expect_zero(lantern_signature_list_resize(&signatures, 2), "resize zero-hash signatures");

    LanternCheckpoint source_zero = state.latest_justified;
    zero_root(&source_zero.root);
    LanternCheckpoint target_nonzero = source_zero;
    target_nonzero.slot = source_zero.slot + 1u;
    target_nonzero.root = get_historical_root_for_tests(&state, target_nonzero.slot);

    LanternCheckpoint source_nonzero = state.latest_justified;
    source_nonzero.root = get_historical_root_for_tests(&state, source_nonzero.slot);
    LanternCheckpoint target_zero = source_nonzero;
    target_zero.slot = source_nonzero.slot + 1u;
    zero_root(&target_zero.root);

    build_vote(
        &attestations.data[0],
        &signatures.data[0],
        0,
        target_nonzero.slot,
        &source_zero,
        &target_nonzero,
        0xA1);
    build_vote(
        &attestations.data[1],
        &signatures.data[1],
        1,
        target_zero.slot,
        &source_nonzero,
        &target_zero,
        0xA2);

    expect_zero(
        lantern_state_process_attestations(&state, &attestations, &signatures),
        "process zero-hash votes");
    assert(state.latest_justified.slot == 0);
    assert(state.latest_finalized.slot == 0);
    assert(state.justification_roots.length == 0);

    lantern_attestations_reset(&attestations);
    lantern_signature_list_reset(&signatures);
    lantern_state_reset(&state);
    return 0;
}

static int test_attestations_ignore_head_root_mismatch(void) {
    LanternState state;
    lantern_state_init(&state);
    const uint64_t validator_count = 3;
    expect_zero(
        lantern_state_generate_genesis(&state, 766, validator_count),
        "genesis for head-root mismatch vote test");
    mark_slot_justified_for_tests(&state, state.latest_justified.slot);
    populate_historical_hashes_for_tests(&state, 1);

    LanternCheckpoint source = state.latest_justified;
    source.root = get_historical_root_for_tests(&state, source.slot);
    LanternCheckpoint target = source;
    target.slot = source.slot + 1u;
    target.root = get_historical_root_for_tests(&state, target.slot);

    LanternAttestations attestations;
    lantern_attestations_init(&attestations);
    LanternSignatureList signatures;
    lantern_signature_list_init(&signatures);
    size_t quorum = (size_t)lantern_consensus_quorum_threshold(state.config.num_validators);
    expect_zero(lantern_attestations_resize(&attestations, quorum), "resize head-mismatch attestations");
    expect_zero(lantern_signature_list_resize(&signatures, quorum), "resize head-mismatch signatures");

    for (size_t i = 0; i < quorum; ++i) {
        build_vote(
            &attestations.data[i],
            &signatures.data[i],
            (uint64_t)i,
            target.slot,
            &source,
            &target,
            (uint8_t)(0xB0u + i));
        fill_root(&attestations.data[i].head.root, (uint8_t)(0xD0u + i));
    }

    expect_zero(
        lantern_state_process_attestations(&state, &attestations, &signatures),
        "process head-root mismatch votes");
    assert(state.latest_justified.slot == 0);
    assert(state.latest_finalized.slot == 0);
    assert(state.justification_roots.length == 0);

    lantern_attestations_reset(&attestations);
    lantern_signature_list_reset(&signatures);
    lantern_state_reset(&state);
    return 0;
}

static int test_attestations_ignore_out_of_range_validator(void) {
    LanternState state;
    lantern_state_init(&state);
    expect_zero(
        lantern_state_generate_genesis(&state, 710, 3),
        "genesis for out-of-range attestation test");
    mark_slot_justified_for_tests(&state, state.latest_justified.slot);

    LanternAttestations attestations;
    lantern_attestations_init(&attestations);
    LanternSignatureList signatures;
    lantern_signature_list_init(&signatures);

    size_t quorum = (size_t)lantern_consensus_quorum_threshold(state.config.num_validators);
    size_t att_count = quorum + 1u;
    expect_zero(lantern_attestations_resize(&attestations, att_count), "resize mixed attestations");
    expect_zero(
        lantern_signature_list_resize(&signatures, att_count),
        "resize mixed attestation signatures");

    LanternCheckpoint source_checkpoint = state.latest_justified;
    LanternCheckpoint target_checkpoint = source_checkpoint;
    target_checkpoint.slot = source_checkpoint.slot + 1u;
    populate_historical_hashes_for_tests(&state, target_checkpoint.slot);
    source_checkpoint.root = get_historical_root_for_tests(&state, source_checkpoint.slot);
    target_checkpoint.root = get_historical_root_for_tests(&state, target_checkpoint.slot);

    uint64_t invalid_validator = state.config.num_validators;
    build_vote(
        &attestations.data[0],
        &signatures.data[0],
        invalid_validator,
        target_checkpoint.slot,
        &source_checkpoint,
        &target_checkpoint,
        0x31);
    for (size_t i = 1; i <= quorum; ++i) {
        uint64_t validator_id = (uint64_t)(i - 1u);
        build_vote(
            &attestations.data[i],
            &signatures.data[i],
            validator_id,
            target_checkpoint.slot,
            &source_checkpoint,
            &target_checkpoint,
            (uint8_t)(0x32u + i));
    }

    expect_zero(
        lantern_state_process_attestations(&state, &attestations, &signatures),
        "process attestations with invalid validator entry");
    assert(state.latest_justified.slot == target_checkpoint.slot);

    lantern_attestations_reset(&attestations);
    lantern_signature_list_reset(&signatures);
    lantern_state_reset(&state);
    return 0;
}

static int test_process_block_accepts_mixed_attestations(void) {
    LanternState state;
    lantern_state_init(&state);
    const uint64_t genesis_time = 720;
    const uint64_t validator_count = 4;
    expect_zero(
        lantern_state_generate_genesis(&state, genesis_time, validator_count),
        "genesis for mixed attestation block test");
    mark_slot_justified_for_tests(&state, state.latest_justified.slot);

    LanternBlock block;
    memset(&block, 0, sizeof(block));
    block.slot = state.slot + 1u;
    expect_zero(
        lantern_proposer_for_slot(block.slot, validator_count, &block.proposer_index),
        "proposer for mixed attestation block");
    expect_zero(lantern_state_select_block_parent(&state, &block.parent_root), "parent root for mixed block");
    lantern_block_body_init(&block.body);

    size_t quorum = (size_t)lantern_consensus_quorum_threshold(validator_count);
    size_t att_count = quorum + 1u;
    LanternAttestations votes;
    lantern_attestations_init(&votes);
    expect_zero(
        lantern_attestations_resize(&votes, att_count),
        "resize mixed block attestations");

    LanternCheckpoint source_checkpoint = state.latest_justified;
    LanternCheckpoint target_checkpoint = source_checkpoint;
    target_checkpoint.slot = source_checkpoint.slot + 1u;
    populate_historical_hashes_for_tests(&state, target_checkpoint.slot);
    source_checkpoint.root = get_historical_root_for_tests(&state, source_checkpoint.slot);
    target_checkpoint.root = get_historical_root_for_tests(&state, target_checkpoint.slot);

    uint64_t invalid_validator = state.config.num_validators;
    build_vote(
        &votes.data[0],
        NULL,
        invalid_validator,
        target_checkpoint.slot,
        &source_checkpoint,
        &target_checkpoint,
        0x41);
    for (size_t i = 1; i <= quorum; ++i) {
        uint64_t validator_id = (uint64_t)(i - 1u);
        build_vote(
            &votes.data[i],
            NULL,
            validator_id,
            target_checkpoint.slot,
            &source_checkpoint,
            &target_checkpoint,
            (uint8_t)(0x41u + i));
    }

    for (size_t i = 0; i < att_count; ++i) {
        expect_zero(
            append_aggregated_attestation_from_vote(&block.body.attestations, &votes.data[i]),
            "append aggregated attestation");
    }

    expect_zero(lantern_state_process_slots(&state, block.slot), "advance slots for mixed attestation block");
    int process_rc = lantern_state_process_block(&state, &block);
    if (process_rc == 0) {
        fprintf(stderr, "expected mixed aggregated attestations to be rejected\n");
        lantern_attestations_reset(&votes);
        lantern_block_body_reset(&block.body);
        lantern_state_reset(&state);
        return 1;
    }

    lantern_attestations_reset(&votes);
    lantern_block_body_reset(&block.body);
    lantern_state_reset(&state);
    return 0;
}

static int test_collect_attestations_for_block(void) {
    LanternState state;
    LanternRoot parent_root;
    struct PQSignatureSchemePublicKey *pubkeys[3] = {NULL, NULL, NULL};
    struct PQSignatureSchemeSecretKey *secrets[3] = {NULL, NULL, NULL};
    uint8_t serialized_pubkeys[3][LANTERN_VALIDATOR_PUBKEY_SIZE];
    lantern_state_init(&state);
    expect_zero(lantern_state_generate_genesis(&state, 900, 3), "genesis for collection test");
    mark_slot_justified_for_tests(&state, state.latest_justified.slot);
    expect_zero(lantern_state_select_block_parent(&state, &parent_root), "collection parent root");
    populate_historical_hashes_for_tests(&state, 1u);
    state.historical_block_hashes.items[0] = parent_root;
    memset(serialized_pubkeys, 0, sizeof(serialized_pubkeys));

    for (size_t i = 0; i < 3u; ++i) {
        if (generate_test_keypair(&pubkeys[i], &secrets[i]) != 0) {
            fprintf(stderr, "failed to generate keypair for collection test index=%zu\n", i);
            goto fail;
        }
        if (serialize_test_pubkey(pubkeys[i], serialized_pubkeys[i]) != 0) {
            fprintf(stderr, "failed to serialize pubkey for collection test index=%zu\n", i);
            goto fail;
        }
    }
    expect_zero(
        set_test_validator_pubkeys(&state, pubkeys, 3u),
        "set validator pubkeys for collection test");

    LanternCheckpoint justified = state.latest_justified;
    justified.root = parent_root;
    LanternCheckpoint target = justified;
    target.slot = justified.slot + 1;
    target.root = state.historical_block_hashes.items[target.slot];

    LanternSignedVote signed_votes[3];
    memset(signed_votes, 0, sizeof(signed_votes));
    for (size_t i = 0; i < 3u; ++i) {
        build_vote(
            &signed_votes[i].data,
            &signed_votes[i].signature,
            (uint64_t)i,
            target.slot,
            &justified,
            &target,
            0u);
        if (sign_vote_with_secret(&signed_votes[i], secrets[i]) != 0) {
            fprintf(stderr, "failed to sign vote for collection test index=%zu\n", i);
            goto fail;
        }
    }

    LanternRoot data_root;
    expect_ssz_success(
        lantern_hash_tree_root_attestation_data(&signed_votes[0].data.data, &data_root),
        "hash collection attestation data");

    for (size_t i = 0; i < 2u; ++i) {
        LanternAggregatedSignatureProof proof;
        if (build_single_participant_cached_proof(
                &proof,
                signed_votes[i].data.validator_id,
                serialized_pubkeys[i],
                &signed_votes[i].signature,
                &data_root,
                signed_votes[i].data.slot)
            != 0) {
            fprintf(stderr, "failed to build cached proof for collection test index=%zu\n", i);
            goto fail;
        }
        int add_rc = lantern_store_add_known_aggregated_payload(
            lantern_test_state_store_ensure(&state),
            &data_root,
            &signed_votes[i].data.data,
            &proof,
            signed_votes[i].data.target.slot);
        lantern_aggregated_signature_proof_reset(&proof);
        if (add_rc != 0) {
            fprintf(stderr, "failed to seed known payload for collection test index=%zu\n", i);
            goto fail;
        }
    }

    uint64_t block_slot = state.slot + 1u;
    uint64_t proposer_index = 0;
    expect_zero(
        lantern_proposer_for_slot(block_slot, state.config.num_validators, &proposer_index),
        "collection proposer lookup");

    LanternAggregatedAttestations collected;
    lantern_aggregated_attestations_init(&collected);
    LanternAttestationSignatures collected_signatures;
    lantern_attestation_signatures_init(&collected_signatures);
    expect_zero(
        lantern_state_collect_attestations_for_block(
            &state,
            block_slot,
            proposer_index,
            &parent_root,
            &collected,
            &collected_signatures),
        "collect attestations");

    if (collected.length != 1u) {
        fprintf(stderr, "Expected one merged aggregated attestation, got %zu\n", collected.length);
        goto fail_after_collect;
    }
    if (collected_signatures.length != collected.length) {
        fprintf(stderr, "Expected signatures for each collected attestation\n");
        goto fail_after_collect;
    }

    const LanternAggregatedAttestation *attestation = &collected.data[0];
    const LanternAggregatedSignatureProof *proof = &collected_signatures.data[0];
    if (attestation->data.slot != signed_votes[0].data.slot
        || !checkpoints_equal(&attestation->data.source, &justified)
        || !checkpoints_equal(&attestation->data.target, &target)
        || !checkpoints_equal(&attestation->data.head, &target)) {
        fprintf(stderr, "Collected attestation data did not match expected vote data\n");
        goto fail_after_collect;
    }
    if (attestation->aggregation_bits.bit_length < 2u
        || !bitlist_test_bit(&attestation->aggregation_bits, 0u)
        || !bitlist_test_bit(&attestation->aggregation_bits, 1u)
        || (attestation->aggregation_bits.bit_length > 2u
            && bitlist_test_bit(&attestation->aggregation_bits, 2u))) {
        fprintf(stderr, "Collected attestation aggregation bits did not merge validators 0 and 1\n");
        goto fail_after_collect;
    }
    if (proof->participants.bit_length < 2u
        || !bitlist_test_bit(&proof->participants, 0u)
        || !bitlist_test_bit(&proof->participants, 1u)
        || (proof->participants.bit_length > 2u
            && bitlist_test_bit(&proof->participants, 2u))) {
        fprintf(stderr, "Collected proof participants did not merge validators 0 and 1\n");
        goto fail_after_collect;
    }

    const uint8_t *pubkey_refs[2] = {
        serialized_pubkeys[0],
        serialized_pubkeys[1],
    };
    if (!lantern_signature_verify_aggregated(
            pubkey_refs,
            2u,
            &data_root,
            &proof->proof_data,
            attestation->data.slot)) {
        fprintf(stderr, "Merged collection proof verification failed\n");
        goto fail_after_collect;
    }

    lantern_aggregated_attestations_reset(&collected);
    lantern_attestation_signatures_reset(&collected_signatures);
    for (size_t i = 0; i < 3u; ++i) {
        pq_secret_key_free(secrets[i]);
        pq_public_key_free(pubkeys[i]);
    }
    lantern_state_reset(&state);
    return 0;

fail_after_collect:
    lantern_aggregated_attestations_reset(&collected);
    lantern_attestation_signatures_reset(&collected_signatures);

fail:
    for (size_t i = 0; i < 3u; ++i) {
        if (secrets[i]) {
            pq_secret_key_free(secrets[i]);
        }
        if (pubkeys[i]) {
            pq_public_key_free(pubkeys[i]);
        }
    }
    lantern_state_reset(&state);
    return 1;
}

static int test_process_block_rejects_duplicate_attestation_data(void) {
    LanternState state;
    LanternRoot parent_root;
    LanternBlock block;
    LanternRoot block_root;
    LanternVote vote0;
    LanternVote vote1;

    lantern_state_init(&state);
    memset(&block, 0, sizeof(block));
    memset(&vote0, 0, sizeof(vote0));
    memset(&vote1, 0, sizeof(vote1));

    expect_zero(
        lantern_state_generate_genesis(&state, 905u, 4u),
        "genesis for duplicate attestation-data block test");
    expect_zero(
        lantern_state_process_slots(&state, 2u),
        "advance slots for duplicate attestation-data block test");
    mark_slot_justified_for_tests(&state, 1u);
    expect_zero(
        lantern_state_select_block_parent(&state, &parent_root),
        "select block parent for duplicate attestation-data block test");

    populate_historical_hashes_for_tests(&state, 2u);
    state.historical_block_hashes.items[0] = parent_root;

    LanternCheckpoint source;
    source.slot = 1u;
    source.root = state.historical_block_hashes.items[source.slot];
    LanternCheckpoint target = source;
    target.slot = 2u;
    target.root = state.historical_block_hashes.items[target.slot];

    build_vote(&vote0, NULL, 0u, target.slot, &source, &target, 0u);
    build_vote(&vote1, NULL, 1u, target.slot, &source, &target, 0u);

    make_block(&state, 2u, &parent_root, &block, &block_root);
    if (append_aggregated_attestation_from_vote(&block.body.attestations, &vote0) != 0
        || append_aggregated_attestation_from_vote(&block.body.attestations, &vote1) != 0) {
        fprintf(stderr, "failed to build duplicate attestation-data block body\n");
        lantern_block_body_reset(&block.body);
        lantern_state_reset(&state);
        return 1;
    }

    if (lantern_state_process_block(&state, &block) == 0) {
        fprintf(stderr, "duplicate attestation data block was incorrectly accepted\n");
        lantern_block_body_reset(&block.body);
        lantern_state_reset(&state);
        return 1;
    }

    lantern_block_body_reset(&block.body);
    lantern_state_reset(&state);
    return 0;
}

static int test_process_block_rejects_too_many_attestation_data_entries(void) {
    LanternState state;
    LanternRoot parent_root;
    LanternBlock block;

    lantern_state_init(&state);
    memset(&block, 0, sizeof(block));

    expect_zero(
        lantern_state_generate_genesis(&state, 906u, 1u),
        "genesis for max attestation-data block test");
    expect_zero(
        lantern_state_select_block_parent(&state, &parent_root),
        "select block parent for max attestation-data block test");

    lantern_block_body_init(&block.body);
    block.slot = 1u;
    block.proposer_index = 0u;
    block.parent_root = parent_root;

    for (size_t i = 0; i <= (size_t)LANTERN_MAX_ATTESTATIONS_DATA; ++i) {
        LanternVote vote;
        LanternCheckpoint source;
        LanternCheckpoint target;

        memset(&vote, 0, sizeof(vote));
        memset(&source, 0, sizeof(source));
        memset(&target, 0, sizeof(target));
        source.slot = 0u;
        target.slot = (uint64_t)i + 1u;
        fill_root(&source.root, 0x10u);
        fill_root(&target.root, (uint8_t)(0x20u + i));
        build_vote(&vote, NULL, 0u, target.slot, &source, &target, (uint8_t)(0x40u + i));
        expect_zero(
            append_aggregated_attestation_from_vote(&block.body.attestations, &vote),
            "append max attestation-data block vote");
    }

    if (lantern_state_process_block(&state, &block) == 0) {
        fprintf(stderr, "block with too many distinct attestation data entries was incorrectly accepted\n");
        lantern_block_body_reset(&block.body);
        lantern_state_reset(&state);
        return 1;
    }

    lantern_block_body_reset(&block.body);
    lantern_state_reset(&state);
    return 0;
}

static int test_process_attestations_preserves_signed_votes(void) {
    LanternState state;
    lantern_state_init(&state);
    expect_zero(lantern_state_generate_genesis(&state, 901, 4), "genesis for signed vote preservation");
    mark_slot_justified_for_tests(&state, state.latest_justified.slot);

    /* Populate historical hashes so attestation validation can verify roots */
    populate_historical_hashes_for_tests(&state, 1);

    LanternAttestations attestations;
    lantern_attestations_init(&attestations);
    LanternSignatureList signatures;
    lantern_signature_list_init(&signatures);

    size_t quorum = (size_t)lantern_consensus_quorum_threshold(state.config.num_validators);
    expect_zero(
        lantern_attestations_resize(&attestations, quorum),
        "resize attestation input");
    expect_zero(
        lantern_signature_list_resize(&signatures, quorum),
        "resize attestation signatures");

    /* Use roots from historical_block_hashes so attestations pass validation */
    LanternCheckpoint source = state.latest_justified;
    source.root = get_historical_root_for_tests(&state, source.slot);
    LanternCheckpoint target = source;
    target.slot = source.slot + 1u;
    target.root = get_historical_root_for_tests(&state, target.slot);

    for (size_t i = 0; i < quorum; ++i) {
        build_vote(
            &attestations.data[i],
            &signatures.data[i],
            (uint64_t)i,
            target.slot,
            &source,
            &target,
            (uint8_t)(0xD1u + i));
    }

    LanternSignedVote expected_signed;
    memset(&expected_signed, 0, sizeof(expected_signed));
    expected_signed.data = attestations.data[0];
    expected_signed.signature = signatures.data[0];

    int rc = 0;
    if (lantern_state_process_attestations(&state, &attestations, &signatures) != 0) {
        fprintf(stderr, "processing attestations failed\n");
        rc = 1;
        goto cleanup;
    }
    if (state.latest_justified.slot != target.slot) {
        fprintf(
            stderr,
            "expected latest justified slot %" PRIu64 " got %" PRIu64 "\n",
            target.slot,
            state.latest_justified.slot);
        rc = 1;
        goto cleanup;
    }

    LanternSignedVote stored;
    memset(&stored, 0, sizeof(stored));
    if (lantern_state_get_signed_validator_vote(&state, 0, &stored) != 0) {
        fprintf(stderr, "stored vote missing after processing attestations\n");
        rc = 1;
        goto cleanup;
    }
    if (memcmp(&stored.data, &expected_signed.data, sizeof(LanternVote)) != 0) {
        fprintf(stderr, "stored vote payload was mutated\n");
        rc = 1;
        goto cleanup;
    }
    if (memcmp(stored.signature.bytes, expected_signed.signature.bytes, LANTERN_SIGNATURE_SIZE) != 0) {
        fprintf(stderr, "stored vote signature was mutated\n");
        rc = 1;
        goto cleanup;
    }

cleanup:
    lantern_attestations_reset(&attestations);
    lantern_signature_list_reset(&signatures);
    lantern_state_reset(&state);
    return rc;
}

static int test_process_block_defers_proposer_attestation(void) {
    LanternState state;
    LanternForkChoice fork_choice;
    LanternRoot anchor_root;
    lantern_state_init(&state);
    lantern_fork_choice_init(&fork_choice);
    const uint64_t genesis_time = 777;
    const uint64_t validator_count = 1;
    setup_state_and_fork_choice(&state, &fork_choice, genesis_time, validator_count, &anchor_root);

    struct PQSignatureSchemePublicKey *proposer_pub = NULL;
    struct PQSignatureSchemeSecretKey *proposer_secret = NULL;
    expect_zero(generate_test_keypair(&proposer_pub, &proposer_secret), "generate proposer vote keypair");
    expect_zero(
        set_test_validator_pubkey(&state, (size_t)validator_count, 0u, proposer_pub),
        "set proposer pubkey");
    mark_slot_justified_for_tests(&state, state.latest_justified.slot);

    /* Populate historical hashes so proposer attestation validation passes */
    populate_historical_hashes_for_tests(&state, 1);

    LanternSignedBlock signed_block;
    memset(&signed_block, 0, sizeof(signed_block));
    LanternBlock *block = &signed_block.block;
    block->slot = state.slot + 1u;
    expect_zero(
        lantern_proposer_for_slot(block->slot, validator_count, &block->proposer_index),
        "proposer for proposer vote test");
    expect_zero(
        lantern_state_select_block_parent(&state, &block->parent_root),
        "parent root for proposer vote test");
    lantern_block_body_init(&block->body);

    LanternCheckpoint base = state.latest_justified;
    base.root = get_historical_root_for_tests(&state, base.slot);

    LanternRoot expected_state_root;
    expect_zero(
        lantern_state_preview_post_state_root(&state, &signed_block, &expected_state_root),
        "preview proposer block state root");
    block->state_root = expected_state_root;
    LanternRoot proposer_block_root;
    expect_ssz_success(
        lantern_hash_tree_root_block(block, &proposer_block_root),
        "hash proposer block root");
    LanternSignature proposer_signature;
    memset(&proposer_signature, 0, sizeof(proposer_signature));
    if (!lantern_signature_sign(
            proposer_secret,
            block->slot,
            &proposer_block_root,
            &proposer_signature)) {
        fprintf(stderr, "sign proposer block failed\n");
        lantern_block_body_reset(&block->body);
        pq_secret_key_free(proposer_secret);
        pq_public_key_free(proposer_pub);
        lantern_state_reset(&state);
        return 1;
    }
    if (build_proposer_only_block_proof(
            &state,
            block,
            &proposer_block_root,
            &proposer_signature,
            &signed_block.proof)
        != 0) {
        fprintf(stderr, "build proposer block proof failed\n");
        lantern_byte_list_reset(&signed_block.proof);
        lantern_block_body_reset(&block->body);
        pq_secret_key_free(proposer_secret);
        pq_public_key_free(proposer_pub);
        lantern_state_reset(&state);
        return 1;
    }

    expect_zero(lantern_state_transition(&state, &signed_block), "import block with proposer proof");
    assert(state.latest_justified.slot == base.slot);

    if (lantern_state_validator_has_vote(&state, (size_t)block->proposer_index)) {
        fprintf(stderr, "proposer proof should not stage a validator vote\n");
        lantern_byte_list_reset(&signed_block.proof);
        lantern_block_body_reset(&block->body);
        pq_secret_key_free(proposer_secret);
        pq_public_key_free(proposer_pub);
        lantern_state_reset(&state);
        lantern_fork_choice_reset(&fork_choice);
        return 1;
    }

    LanternStore *store = lantern_test_state_store_ensure(&state);
    if (!store) {
        fprintf(stderr, "state store missing after proposer import\n");
        lantern_byte_list_reset(&signed_block.proof);
        lantern_block_body_reset(&block->body);
        pq_secret_key_free(proposer_secret);
        pq_public_key_free(proposer_pub);
        lantern_state_reset(&state);
        lantern_fork_choice_reset(&fork_choice);
        return 1;
    }

    assert(store->attestation_signatures.length == 0u);
    assert(store->attestation_data_by_root.length == 0u);

    LanternRoot head;
    expect_zero(lantern_fork_choice_current_head(&fork_choice, &head), "fork choice head after proposer import");
    assert(memcmp(head.bytes, proposer_block_root.bytes, LANTERN_ROOT_SIZE) == 0);

    lantern_byte_list_reset(&signed_block.proof);
    lantern_block_body_reset(&block->body);
    pq_secret_key_free(proposer_secret);
    pq_public_key_free(proposer_pub);
    lantern_state_reset(&state);
    lantern_fork_choice_reset(&fork_choice);
    return 0;
}

static int test_collect_attestations_fixed_point(void) {
    LanternState state;
    LanternRoot parent_root;
    lantern_state_init(&state);
    /* Use 4 validators. Quorum is ceil(2/3 * 4) = 3 votes needed to justify. */
    expect_zero(lantern_state_generate_genesis(&state, 950, 4), "genesis for fixed-point test");
    mark_slot_justified_for_tests(&state, state.latest_justified.slot);

    /* Populate historical hashes so attestation validation passes during collection.
     * Slot 0 must match the genesis latest_justified.root (which is zero after genesis).
     * We need entries for slots 0, 1, and 2. */
    expect_zero(
        lantern_root_list_resize(&state.historical_block_hashes, 3),
        "resize historical hashes for fixed-point test");
    expect_zero(lantern_state_select_block_parent(&state, &parent_root), "fixed-point parent root precompute");
    /* Slot 0: set to match the aliased genesis parent root used during block production */
    state.historical_block_hashes.items[0] = parent_root;
    /* Slots 1 and 2: synthetic roots for mid and tip */
    fill_root(&state.historical_block_hashes.items[1], 0xE1);
    fill_root(&state.historical_block_hashes.items[2], 0xE2);

    /* Slot 1 is intentionally not pre-marked as justified: the fixed-point
     * iteration must justify it via the base→mid quorum before the mid→tip
     * vote becomes collectable. */

    /* Use roots from historical_block_hashes so attestations pass validation */
    LanternCheckpoint base = state.latest_justified;
    base.root = parent_root;
    LanternCheckpoint mid = base;
    mid.slot = base.slot + 1u;
    mid.root = state.historical_block_hashes.items[1];
    LanternCheckpoint tip = mid;
    tip.slot = mid.slot + 1u;
    tip.root = state.historical_block_hashes.items[2];

    /* Set up votes to ensure quorum is reached for each transition.
     * Need 3 votes (out of 4 validators) to reach quorum.
     * Validators 0,1,2 vote for base→mid transition (3 votes = quorum)
     * Validator 3 votes for mid→tip transition (but won't reach quorum with just 1 vote)
     * After mid is justified, validators 0,1,2 votes still count (their source was base→mid).
     * Actually for the second round, we need votes with source=mid.
     * Let's have validators 0,1,2 vote base→mid and validator 3 vote mid→tip.
     * When base→mid reaches quorum, mid gets justified.
     * Then we need votes for mid→tip to also reach quorum.
     * Since we have 4 validators, let's use 3 for base→mid and 3 for mid→tip (overlap validator 2). */
    LanternSignedVote vote;
    memset(&vote, 0, sizeof(vote));
    /* Validators 0,1,2 vote for base→mid */
    build_vote(&vote.data, &vote.signature, 0, mid.slot, &base, &mid, 0);
    expect_zero(lantern_state_set_signed_validator_vote(&state, 0, &vote), "store fixed vote 0");
    expect_zero(seed_known_payload_for_vote(&state, &vote.data, 0x61), "seed fixed payload 0");
    build_vote(&vote.data, &vote.signature, 1, mid.slot, &base, &mid, 0);
    expect_zero(lantern_state_set_signed_validator_vote(&state, 1, &vote), "store fixed vote 1");
    expect_zero(seed_known_payload_for_vote(&state, &vote.data, 0x62), "seed fixed payload 1");
    build_vote(&vote.data, &vote.signature, 2, mid.slot, &base, &mid, 0);
    expect_zero(lantern_state_set_signed_validator_vote(&state, 2, &vote), "store fixed vote 2");
    expect_zero(seed_known_payload_for_vote(&state, &vote.data, 0x63), "seed fixed payload 2");
    /* Validator 3 votes for mid→tip (this won't reach quorum alone, but tests the fixed-point logic) */
    build_vote(&vote.data, &vote.signature, 3, tip.slot, &mid, &tip, 0);
    expect_zero(lantern_state_set_signed_validator_vote(&state, 3, &vote), "store fixed vote 3");
    expect_zero(seed_known_payload_for_vote(&state, &vote.data, 0x64), "seed fixed payload 3");

    uint64_t block_slot = state.slot + 1u;
    uint64_t proposer_index = 0;
    expect_zero(
        lantern_proposer_for_slot(block_slot, state.config.num_validators, &proposer_index),
        "fixed-point proposer lookup");
    expect_zero(lantern_state_select_block_parent(&state, &parent_root), "fixed-point parent root");

    LanternAggregatedAttestations collected;
    lantern_aggregated_attestations_init(&collected);
    LanternAttestationSignatures collected_signatures;
    lantern_attestation_signatures_init(&collected_signatures);

    int rc = 0;
    if (lantern_state_collect_attestations_for_block(
            &state,
            block_slot,
            proposer_index,
            &parent_root,
            &collected,
            &collected_signatures)
        != 0) {
        fprintf(stderr, "fixed-point collection failed\n");
        rc = 1;
        goto cleanup;
    }

    /* With the single-AttestationData-per-block rule, the 3 base→mid proofs are merged
     * into one attestation. A second attestation for mid→tip may or may not be added,
     * depending on whether the fixed-point iteration reaches that checkpoint. */
    if (collected.length == 0u || collected.length > 2u || collected_signatures.length != collected.length) {
        fprintf(stderr, "expected 1 or 2 aggregated attestations after fixed-point collection, got %zu\n", collected.length);
        rc = 1;
        goto cleanup;
    }

    bool saw_base_group = false;
    bool saw_mid_group = false;
    for (size_t i = 0; i < collected.length; ++i) {
        const LanternAggregatedAttestation *attestation = &collected.data[i];
        const LanternAggregatedSignatureProof *proof = &collected_signatures.data[i];
        if (checkpoints_equal(&attestation->data.source, &base)) {
            saw_base_group = true;
            for (size_t validator_index = 0; validator_index < 3u; ++validator_index) {
                if (attestation->aggregation_bits.bit_length <= validator_index
                    || !bitlist_test_bit(&attestation->aggregation_bits, validator_index)
                    || proof->participants.bit_length <= validator_index
                    || !bitlist_test_bit(&proof->participants, validator_index)) {
                    fprintf(stderr, "missing base-group validator %zu after fixed-point collection\n", validator_index);
                    rc = 1;
                    goto cleanup;
                }
            }
            if ((attestation->aggregation_bits.bit_length > 3u
                    && bitlist_test_bit(&attestation->aggregation_bits, 3u))
                || (proof->participants.bit_length > 3u
                    && bitlist_test_bit(&proof->participants, 3u))) {
                fprintf(stderr, "base-group collection incorrectly included validator 3\n");
                rc = 1;
                goto cleanup;
            }
        } else if (checkpoints_equal(&attestation->data.source, &mid)) {
            uint64_t validator_id = UINT64_MAX;
            saw_mid_group = true;
            if (single_participant_from_bits(&attestation->aggregation_bits, &validator_id) != 0
                || validator_id != 3u
                || proof->participants.bit_length <= 3u
                || !bitlist_test_bit(&proof->participants, 3u)) {
                fprintf(stderr, "mid-group collection did not preserve validator 3\n");
                rc = 1;
                goto cleanup;
            }
        } else {
            fprintf(stderr, "unexpected checkpoint source in fixed-point collection\n");
            rc = 1;
            goto cleanup;
        }
    }

    if (!saw_base_group) {
        fprintf(stderr, "expected merged base-group attestation after fixed-point collection\n");
        rc = 1;
        goto cleanup;
    }
    if (collected.length == 2u && !saw_mid_group) {
        fprintf(stderr, "expected mid-group attestation when two groups were collected\n");
        rc = 1;
        goto cleanup;
    }

cleanup:
    lantern_aggregated_attestations_reset(&collected);
    lantern_attestation_signatures_reset(&collected_signatures);
    lantern_state_reset(&state);
    return rc;
}

static int test_collect_attestations_respects_max_attestation_data(void) {
    LanternState state;
    LanternRoot parent_root;
    LanternAggregatedAttestations collected;
    LanternAttestationSignatures collected_signatures;

    lantern_state_init(&state);
    lantern_aggregated_attestations_init(&collected);
    lantern_attestation_signatures_init(&collected_signatures);

    expect_zero(
        lantern_state_generate_genesis(&state, 907u, 1u),
        "genesis for max attestation-data collection test");
    mark_slot_justified_for_tests(&state, state.latest_justified.slot);
    expect_zero(
        lantern_state_select_block_parent(&state, &parent_root),
        "select block parent for max attestation-data collection test");
    populate_historical_hashes_for_tests(&state, (uint64_t)LANTERN_MAX_ATTESTATIONS_DATA + 1u);
    state.historical_block_hashes.items[0] = parent_root;

    for (size_t i = 0; i <= (size_t)LANTERN_MAX_ATTESTATIONS_DATA; ++i) {
        LanternVote vote;
        LanternCheckpoint source;
        LanternCheckpoint target;

        memset(&vote, 0, sizeof(vote));
        source.slot = 0u;
        source.root = parent_root;
        target.slot = (uint64_t)i + 1u;
        target.root = state.historical_block_hashes.items[target.slot];
        build_vote(&vote, NULL, 0u, target.slot, &source, &target, 0u);
        expect_zero(
            seed_known_payload_for_vote(&state, &vote, (uint8_t)(0x50u + i)),
            "seed max attestation-data payload");
    }

    uint64_t block_slot = (uint64_t)LANTERN_MAX_ATTESTATIONS_DATA + 2u;
    uint64_t proposer_index = 0u;
    expect_zero(
        lantern_proposer_for_slot(block_slot, state.config.num_validators, &proposer_index),
        "max attestation-data proposer lookup");

    expect_zero(
        lantern_state_collect_attestations_for_block(
            &state,
            block_slot,
            proposer_index,
            &parent_root,
            &collected,
            &collected_signatures),
        "collect max attestation-data block");

    if (collected.length != (size_t)LANTERN_MAX_ATTESTATIONS_DATA
        || collected_signatures.length != collected.length) {
        fprintf(
            stderr,
            "expected %u collected attestation-data entries, got %zu\n",
            (unsigned)LANTERN_MAX_ATTESTATIONS_DATA,
            collected.length);
        goto fail;
    }

    for (size_t i = 0; i < collected.length; ++i) {
        uint64_t expected_target_slot = (uint64_t)i + 1u;
        if (collected.data[i].data.target.slot != expected_target_slot) {
            fprintf(
                stderr,
                "collected attestation target slot mismatch index=%zu expected=%" PRIu64 " actual=%" PRIu64 "\n",
                i,
                expected_target_slot,
                collected.data[i].data.target.slot);
            goto fail;
        }
    }

    lantern_aggregated_attestations_reset(&collected);
    lantern_attestation_signatures_reset(&collected_signatures);
    lantern_state_reset(&state);
    return 0;

fail:
    lantern_aggregated_attestations_reset(&collected);
    lantern_attestation_signatures_reset(&collected_signatures);
    lantern_state_reset(&state);
    return 1;
}

static int test_collect_attestations_fixed_point_deep_chain(void) {
    LanternState state;
    LanternRoot parent_root;
    enum {
        validator_count = 64,
        cached_group_size = 16,
        cached_group_count = validator_count / cached_group_size,
    };
    struct PQSignatureSchemePublicKey *pubkeys[validator_count];
    struct PQSignatureSchemeSecretKey *secrets[validator_count];
    uint8_t serialized_pubkeys[validator_count][LANTERN_VALIDATOR_PUBKEY_SIZE];
    LanternSignedVote signed_votes[validator_count];
    LanternAggregatedAttestations collected;
    LanternAttestationSignatures collected_signatures;
    int rc = 0;
    lantern_state_init(&state);
    lantern_aggregated_attestations_init(&collected);
    lantern_attestation_signatures_init(&collected_signatures);
    memset(pubkeys, 0, sizeof(pubkeys));
    memset(secrets, 0, sizeof(secrets));
    memset(serialized_pubkeys, 0, sizeof(serialized_pubkeys));
    memset(signed_votes, 0, sizeof(signed_votes));

    /* Use 64 validators. To reach quorum (2/3), we need 43 votes per transition.
     * This keeps the deep-chain test at full quorum while still checking that one
     * AttestationData is deduplicated into one merged aggregate. */
    expect_zero(
        lantern_state_generate_genesis(&state, 975, validator_count),
        "genesis for deep fixed-point test");
    mark_slot_justified_for_tests(&state, state.latest_justified.slot);

    /* Populate historical hashes for the slots we'll use (0 and 1). */
    expect_zero(
        lantern_root_list_resize(&state.historical_block_hashes, 2),
        "resize historical hashes for deep fixed-point test");
    expect_zero(lantern_state_select_block_parent(&state, &parent_root), "deep fixed parent root precompute");
    state.historical_block_hashes.items[0] = parent_root;
    fill_root(&state.historical_block_hashes.items[1], 0x40);

    LanternCheckpoint base = state.latest_justified;
    base.root = parent_root;
    LanternCheckpoint target = base;
    target.slot = base.slot + 1u;
    target.root = state.historical_block_hashes.items[target.slot];

    for (size_t validator_index = 0; validator_index < validator_count; ++validator_index) {
        if (generate_test_keypair(&pubkeys[validator_index], &secrets[validator_index]) != 0) {
            fprintf(stderr, "failed to generate keypair for deep fixed-point test index=%zu\n", validator_index);
            rc = 1;
            goto cleanup;
        }
        if (serialize_test_pubkey(pubkeys[validator_index], serialized_pubkeys[validator_index]) != 0) {
            fprintf(stderr, "failed to serialize pubkey for deep fixed-point test index=%zu\n", validator_index);
            rc = 1;
            goto cleanup;
        }
    }
    expect_zero(
        set_test_validator_pubkeys(&state, pubkeys, validator_count),
        "set validator pubkeys for deep fixed-point test");

    /* All validators vote for base→target. */
    for (size_t i = 0; i < validator_count; ++i) {
        build_vote(&signed_votes[i].data, &signed_votes[i].signature, i, target.slot, &base, &target, 0u);
        if (sign_vote_with_secret(&signed_votes[i], secrets[i]) != 0) {
            fprintf(stderr, "failed to sign deep fixed-point vote index=%zu\n", i);
            rc = 1;
            goto cleanup;
        }
        expect_zero(
            lantern_state_set_signed_validator_vote(&state, i, &signed_votes[i]),
            "store deep fixed vote");
    }

    LanternRoot data_root;
    expect_ssz_success(
        lantern_hash_tree_root_attestation_data(&signed_votes[0].data.data, &data_root),
        "hash deep fixed attestation data");

    /* Devnet-4 interval-2 aggregation means the block-builder cache should already
     * hold a small number of multi-validator proofs per AttestationData. Seed four
     * cached children of 16 validators each so the merge still exercises the deep
     * fixed-point path without exceeding leanMultisig rec_aggregation
     * MAX_RECURSIONS=16 child proofs for one AttestationData. */
    for (size_t group_index = 0; group_index < cached_group_count; ++group_index) {
        const size_t group_start = group_index * cached_group_size;
        const uint8_t *group_pubkeys[cached_group_size];
        LanternSignature group_signatures[cached_group_size];
        uint64_t group_validator_ids[cached_group_size];
        LanternAggregatedSignatureProof proof;

        for (size_t offset = 0; offset < cached_group_size; ++offset) {
            const size_t validator_index = group_start + offset;
            group_pubkeys[offset] = serialized_pubkeys[validator_index];
            group_signatures[offset] = signed_votes[validator_index].signature;
            group_validator_ids[offset] = (uint64_t)validator_index;
        }

        if (build_multi_participant_cached_proof(
                &proof,
                group_validator_ids,
                group_pubkeys,
                group_signatures,
                cached_group_size,
                &data_root,
                signed_votes[group_start].data.slot)
            != 0) {
            fprintf(stderr, "failed to build cached group proof for deep fixed-point test group=%zu\n", group_index);
            rc = 1;
            goto cleanup;
        }
        int add_rc = lantern_store_add_known_aggregated_payload(
            lantern_test_state_store_ensure(&state),
            &data_root,
            &signed_votes[group_start].data.data,
            &proof,
            signed_votes[group_start].data.target.slot);
        lantern_aggregated_signature_proof_reset(&proof);
        if (add_rc != 0) {
            fprintf(stderr, "failed to seed cached group proof for deep fixed-point test group=%zu\n", group_index);
            rc = 1;
            goto cleanup;
        }
    }

    uint64_t block_slot = state.slot + 1u;
    uint64_t proposer_index = 0;
    expect_zero(
        lantern_proposer_for_slot(block_slot, state.config.num_validators, &proposer_index),
        "deep fixed proposer lookup");
    expect_zero(lantern_state_select_block_parent(&state, &parent_root), "deep fixed parent root");

    if (lantern_state_collect_attestations_for_block(
            &state,
            block_slot,
            proposer_index,
            &parent_root,
            &collected,
            &collected_signatures)
        != 0) {
        fprintf(stderr, "deep fixed-point collection failed\n");
        rc = 1;
        goto cleanup;
    }

    /* All 64 validators share the same AttestationData, so collection should emit one
     * merged aggregate covering the full validator set. */
    if (collected.length != 1u || collected_signatures.length != 1u) {
        fprintf(stderr, "expected one merged attestation, got %zu\n", collected.length);
        rc = 1;
        goto cleanup;
    }

    const LanternAggregatedAttestation *attestation = &collected.data[0];
    const LanternAggregatedSignatureProof *proof = &collected_signatures.data[0];
    if (!checkpoints_equal(&attestation->data.source, &base)) {
        fprintf(stderr, "deep-chain source mismatch\n");
        rc = 1;
        goto cleanup;
    }
    if (!checkpoints_equal(&attestation->data.target, &target)) {
        fprintf(stderr, "deep-chain target mismatch\n");
        rc = 1;
        goto cleanup;
    }
    for (size_t validator_index = 0; validator_index < validator_count; ++validator_index) {
        if (attestation->aggregation_bits.bit_length <= validator_index
            || !bitlist_test_bit(&attestation->aggregation_bits, validator_index)) {
            fprintf(stderr, "missing validator %zu in deep fixed-point attestation bits\n", validator_index);
            rc = 1;
            goto cleanup;
        }
        if (proof->participants.bit_length <= validator_index
            || !bitlist_test_bit(&proof->participants, validator_index)) {
            fprintf(stderr, "missing validator %zu in deep fixed-point proof bits\n", validator_index);
            rc = 1;
            goto cleanup;
        }
    }
    {
        const uint8_t *pubkey_refs[validator_count];
        for (size_t validator_index = 0; validator_index < validator_count; ++validator_index) {
            pubkey_refs[validator_index] = serialized_pubkeys[validator_index];
        }
        if (!lantern_signature_verify_aggregated(
                pubkey_refs,
                validator_count,
                &data_root,
                &proof->proof_data,
                attestation->data.slot)) {
            fprintf(stderr, "deep fixed-point merged proof verification failed\n");
            rc = 1;
            goto cleanup;
        }
    }

cleanup:
    lantern_aggregated_attestations_reset(&collected);
    lantern_attestation_signatures_reset(&collected_signatures);
    for (size_t validator_index = 0; validator_index < validator_count; ++validator_index) {
        if (secrets[validator_index]) {
            pq_secret_key_free(secrets[validator_index]);
        }
        if (pubkeys[validator_index]) {
            pq_public_key_free(pubkeys[validator_index]);
        }
    }
    lantern_state_reset(&state);
    return rc;
}

static int test_collect_attestations_ignores_store_justified_when_parent_state_lags(void) {
    LanternState state;
    LanternState parent_state;
    LanternForkChoice fork_choice;
    LanternRoot genesis_root;
    LanternRoot block_one_root;
    LanternRoot block_one_state_root;
    LanternRoot block_two_root;
    LanternBlock block_one;
    LanternBlock block_two;
    LanternCheckpoint store_justified;
    LanternCheckpoint target;
    LanternVote vote;
    LanternAggregatedAttestations collected;
    LanternAttestationSignatures collected_signatures;
    uint64_t proposer_index = 0;
    int rc = 1;

    lantern_state_init(&parent_state);
    lantern_aggregated_attestations_init(&collected);
    lantern_attestation_signatures_init(&collected_signatures);
    memset(&block_one, 0, sizeof(block_one));
    memset(&block_two, 0, sizeof(block_two));
    memset(&vote, 0, sizeof(vote));

    setup_state_and_fork_choice(&state, &fork_choice, 985, 4, &genesis_root);
    expect_zero(
        lantern_state_prepare_validator_votes(&state, state.config.num_validators),
        "prepare validator votes for store-justified collection test");

    make_block(&state, 1u, &genesis_root, &block_one, &block_one_root);
    expect_zero(lantern_state_clone(&state, &parent_state), "clone lagging parent state");
    expect_zero(lantern_state_process_slots(&parent_state, block_one.slot), "advance lagging parent state");
    expect_zero(
        lantern_state_process_block(&parent_state, &block_one),
        "process lagging parent block");
    expect_ssz_success(lantern_hash_tree_root_state(&parent_state, &block_one_state_root), "hash lagging parent state");
    block_one.state_root = block_one_state_root;
    parent_state.latest_block_header.state_root = block_one_state_root;
    expect_ssz_success(lantern_hash_tree_root_block(&block_one, &block_one_root), "rehash lagging parent block");
    expect_zero(
        lantern_root_list_resize(&parent_state.historical_block_hashes, 3u),
        "resize lagging parent history");
    parent_state.historical_block_hashes.items[0] = genesis_root;
    parent_state.historical_block_hashes.items[1] = block_one_root;

    make_block(&parent_state, 2u, &block_one_root, &block_two, &block_two_root);
    parent_state.historical_block_hashes.items[2] = block_two_root;

    expect_zero(
        lantern_fork_choice_add_block_with_state(
            &fork_choice,
            &block_one,
            &parent_state.latest_justified,
            &parent_state.latest_finalized,
            &block_one_root,
            &parent_state),
        "add lagging parent block with state");

    store_justified.slot = 1u;
    store_justified.root = block_one_root;
    const LanternCheckpoint *store_finalized = lantern_fork_choice_latest_finalized(&fork_choice);
    expect_zero(
        lantern_fork_choice_update_checkpoints(&fork_choice, &store_justified, store_finalized),
        "advance store justified for collection test");

    target.slot = 2u;
    target.root = block_two_root;
    build_vote(&vote, NULL, 0u, target.slot, &store_justified, &target, 0u);
    expect_zero(seed_known_payload_for_vote(&state, &vote, 0x88u), "seed store-source payload");

    expect_zero(
        lantern_proposer_for_slot(2u, state.config.num_validators, &proposer_index),
        "compute proposer for store-source block");
    expect_zero(
        lantern_state_collect_attestations_for_block(
            &state,
            2u,
            proposer_index,
            &block_one_root,
            &collected,
            &collected_signatures),
        "collect store-source attestations");

    if (collected.length != 0u || collected_signatures.length != 0u) {
        fprintf(stderr, "selected store-source attestation from lagging parent state\n");
        goto cleanup;
    }

    rc = 0;

cleanup:
    lantern_attestation_signatures_reset(&collected_signatures);
    lantern_aggregated_attestations_reset(&collected);
    lantern_block_body_reset(&block_two.body);
    lantern_block_body_reset(&block_one.body);
    lantern_state_reset(&parent_state);
    lantern_state_reset(&state);
    lantern_fork_choice_reset(&fork_choice);
    return rc;
}

static int test_select_block_parent_uses_fork_choice(void) {
    LanternState state;
    lantern_state_init(&state);
    expect_zero(lantern_state_generate_genesis(&state, 1200, 4), "genesis for parent selection");

    LanternForkChoice fork_choice;
    lantern_fork_choice_init(&fork_choice);
    lantern_state_attach_fork_choice(&state, &fork_choice);
    expect_zero(lantern_fork_choice_configure(&fork_choice, &state.config), "configure fork choice");
    LanternRoot genesis_state_root;
    expect_ssz_success(lantern_hash_tree_root_state(&state, &genesis_state_root), "hash genesis state root");
    state.latest_block_header.state_root = genesis_state_root;

    LanternBlock genesis_block;
    memset(&genesis_block, 0, sizeof(genesis_block));
    genesis_block.slot = 0;
    genesis_block.proposer_index = 0;
    lantern_block_body_init(&genesis_block.body);
    genesis_block.parent_root = state.latest_block_header.parent_root;
    genesis_block.state_root = state.latest_block_header.state_root;

    LanternRoot genesis_root;
    expect_ssz_success(lantern_hash_tree_root_block(&genesis_block, &genesis_root), "genesis block root");
    LanternCheckpoint genesis_cp = {.root = genesis_root, .slot = genesis_block.slot};
    expect_zero(
        lantern_fork_choice_set_anchor(&fork_choice, &genesis_block, &genesis_cp, &genesis_cp, &genesis_root),
        "set anchor");

    lantern_state_attach_fork_choice(&state, &fork_choice);

    LanternRoot parent_root;
    expect_zero(lantern_state_select_block_parent(&state, &parent_root), "select parent at genesis");
    assert(memcmp(parent_root.bytes, genesis_root.bytes, LANTERN_ROOT_SIZE) == 0);

    LanternBlock block_one;
    memset(&block_one, 0, sizeof(block_one));
    block_one.slot = 1;
    expect_zero(
        lantern_proposer_for_slot(block_one.slot, state.config.num_validators, &block_one.proposer_index),
        "proposer slot1");
    lantern_block_body_init(&block_one.body);
    block_one.parent_root = genesis_root;
    LanternRoot block_one_state_root;
    fill_root(&block_one_state_root, 0x11);
    block_one.state_root = block_one_state_root;

    LanternRoot body_root_one;
    expect_ssz_success(lantern_hash_tree_root_block_body(&block_one.body, &body_root_one), "block one body root");
    state.slot = block_one.slot;
    state.latest_block_header.slot = block_one.slot;
    state.latest_block_header.proposer_index = block_one.proposer_index;
    state.latest_block_header.parent_root = block_one.parent_root;
    state.latest_block_header.body_root = body_root_one;
    state.latest_block_header.state_root = block_one_state_root;
    LanternRoot block_one_root;
    expect_ssz_success(lantern_hash_tree_root_block(&block_one, &block_one_root), "block one root");
    expect_zero(
        lantern_fork_choice_add_block(
            &fork_choice,
            &block_one,
            &state.latest_justified,
            &state.latest_finalized,
            &block_one_root),
        "add block one to fork choice");

    expect_zero(lantern_state_select_block_parent(&state, &parent_root), "select parent after block one");
    assert(memcmp(parent_root.bytes, block_one_root.bytes, LANTERN_ROOT_SIZE) == 0);

    LanternBlock block_two;
    memset(&block_two, 0, sizeof(block_two));
    block_two.slot = 2;
    expect_zero(
        lantern_proposer_for_slot(block_two.slot, state.config.num_validators, &block_two.proposer_index),
        "proposer slot2");
    block_two.parent_root = block_one_root;
    lantern_block_body_init(&block_two.body);
    memset(block_two.state_root.bytes, 0x7Au, sizeof(block_two.state_root.bytes));
    LanternRoot block_two_root;
    expect_ssz_success(lantern_hash_tree_root_block(&block_two, &block_two_root), "block two root");
    expect_zero(
        lantern_fork_choice_add_block(&fork_choice, &block_two, NULL, NULL, &block_two_root),
        "add block two");

    if (lantern_state_select_block_parent(&state, &parent_root) == 0) {
        fprintf(stderr, "Expected parent mismatch detection to fail\n");
        lantern_block_body_reset(&block_two.body);
        lantern_block_body_reset(&block_one.body);
        lantern_block_body_reset(&genesis_block.body);
        lantern_state_reset(&state);
        lantern_fork_choice_reset(&fork_choice);
        return 1;
    }

    lantern_block_body_reset(&block_two.body);
    lantern_block_body_reset(&block_one.body);
    lantern_block_body_reset(&genesis_block.body);
    lantern_state_reset(&state);
    lantern_fork_choice_reset(&fork_choice);
    return 0;
}

static int test_validator_helpers_use_cached_fork_choice_head_state(void) {
    LanternState state;
    LanternState block_one_state;
    LanternState expected_state;
    LanternForkChoice fork_choice;
    LanternRoot genesis_root;
    LanternRoot parent_root;
    LanternRoot preview_state_root;
    LanternRoot expected_state_root;
    LanternAggregatedAttestations collected;
    LanternAttestationSignatures collected_signatures;
    LanternSignedBlock signed_block;
    LanternBlock block_one;
    LanternRoot block_one_root;
    LanternRoot block_one_state_root;
    uint64_t proposer_index = 0;
    int result = 1;

    lantern_aggregated_attestations_init(&collected);
    lantern_attestation_signatures_init(&collected_signatures);
    lantern_signed_block_with_attestation_init(&signed_block);
    lantern_state_init(&block_one_state);
    lantern_state_init(&expected_state);

    setup_state_and_fork_choice(&state, &fork_choice, 1525, 4, &genesis_root);
    expect_zero(
        lantern_state_prepare_validator_votes(&state, state.config.num_validators),
        "prepare validator votes for cached head helper test");

    make_block(&state, 1, &genesis_root, &block_one, &block_one_root);
    expect_zero(lantern_state_clone(&state, &block_one_state), "clone block one state");
    expect_zero(
        lantern_state_prepare_validator_votes(&block_one_state, block_one_state.config.num_validators),
        "prepare block one validator votes");
    expect_zero(lantern_state_process_slots(&block_one_state, block_one.slot), "advance block one state");
    expect_zero(
        lantern_state_process_block(&block_one_state, &block_one),
        "process block one state");
    expect_ssz_success(lantern_hash_tree_root_state(&block_one_state, &block_one_state_root), "hash block one state");
    block_one.state_root = block_one_state_root;
    expect_ssz_success(lantern_hash_tree_root_block(&block_one, &block_one_root), "rehash block one with state root");
    expect_zero(
        lantern_fork_choice_add_block_with_state(
            &fork_choice,
            &block_one,
            &block_one_state.latest_justified,
            &block_one_state.latest_finalized,
            &block_one_root,
            &block_one_state),
        "add block one with cached state");

    if (lantern_state_select_block_parent(&state, &parent_root) != 0) {
        fprintf(stderr, "failed to select cached fork-choice parent root\n");
        goto cleanup;
    }
    if (memcmp(parent_root.bytes, block_one_root.bytes, LANTERN_ROOT_SIZE) != 0) {
        fprintf(stderr, "selected parent root did not follow cached fork-choice head\n");
        goto cleanup;
    }

    expect_zero(
        lantern_proposer_for_slot(2u, state.config.num_validators, &proposer_index),
        "compute proposer for preview block");
    if (lantern_state_collect_attestations_for_block(
            &state,
            2u,
            proposer_index,
            &parent_root,
            &collected,
            &collected_signatures)
        != 0) {
        fprintf(stderr, "failed to collect attestations from cached fork-choice head state\n");
        goto cleanup;
    }
    if (collected.length != 0u || collected_signatures.length != 0u) {
        fprintf(stderr, "expected no collected attestations for empty cached-head test\n");
        goto cleanup;
    }

    signed_block.block.slot = 2u;
    signed_block.block.proposer_index = proposer_index;
    signed_block.block.parent_root = parent_root;
    if (lantern_state_preview_post_state_root(
            &state,
            &signed_block,
            &preview_state_root)
        != 0) {
        fprintf(stderr, "failed to preview post-state root from cached fork-choice head state\n");
        goto cleanup;
    }

    expect_zero(lantern_state_clone(&block_one_state, &expected_state), "clone expected state");
    expect_zero(
        lantern_state_prepare_validator_votes(&expected_state, expected_state.config.num_validators),
        "prepare expected-state validator votes");
    expect_zero(lantern_state_process_slots(&expected_state, signed_block.block.slot), "advance expected state");
    expect_zero(
        lantern_state_process_block(&expected_state, &signed_block.block),
        "process preview block on cached head state");
    expect_ssz_success(lantern_hash_tree_root_state(&expected_state, &expected_state_root), "hash expected preview state");

    if (memcmp(preview_state_root.bytes, expected_state_root.bytes, LANTERN_ROOT_SIZE) != 0) {
        fprintf(stderr, "preview post-state root did not use cached fork-choice head state\n");
        goto cleanup;
    }

    result = 0;

cleanup:
    lantern_state_reset(&expected_state);
    lantern_state_reset(&block_one_state);
    lantern_signed_block_with_attestation_reset(&signed_block);
    lantern_attestation_signatures_reset(&collected_signatures);
    lantern_aggregated_attestations_reset(&collected);
    lantern_block_body_reset(&block_one.body);
    lantern_state_reset(&state);
    lantern_fork_choice_reset(&fork_choice);
    return result;
}

static int test_compute_post_state_matches_process_block_and_votes(void) {
    LanternState state;
    LanternState expected_state;
    LanternState preview_state;
    LanternBlock block;
    LanternSignedBlock signed_block;
    LanternRoot parent_root;
    LanternRoot preview_state_root;
    LanternRoot expected_state_root;
    LanternStore preview_store;
    LanternCheckpoint checkpoint;
    LanternSignedVote seeded_vote;
    int result = 1;

    lantern_state_init(&state);
    lantern_state_init(&expected_state);
    lantern_state_init(&preview_state);
    lantern_store_init(&preview_store);
    memset(&block, 0, sizeof(block));
    memset(&signed_block, 0, sizeof(signed_block));
    memset(&seeded_vote, 0, sizeof(seeded_vote));

    expect_zero(lantern_state_generate_genesis(&state, 975u, 4u), "genesis for compute-post-state test");
    expect_zero(
        lantern_state_select_block_parent(&state, &parent_root),
        "select parent for compute-post-state test");
    checkpoint.slot = 0u;
    checkpoint.root = parent_root;
    build_vote(&seeded_vote.data, &seeded_vote.signature, 1u, 0u, &checkpoint, &checkpoint, 0x44u);
    expect_zero(
        lantern_state_set_signed_validator_vote(&state, 1u, &seeded_vote),
        "seed validator vote before compute-post-state test");

    make_block(&state, 1u, &parent_root, &block, &expected_state_root);
    signed_block.block = block;

    expect_zero(
        lantern_state_compute_post_state(
            &state,
            &signed_block,
            &preview_state,
            &preview_store,
            &preview_state_root),
        "compute post-state for proposal fast path");

    expect_zero(lantern_state_clone(&state, &expected_state), "clone expected state");
    expect_zero(lantern_state_process_slots(&expected_state, signed_block.block.slot), "advance expected state");
    expect_zero(
        lantern_state_process_block(&expected_state, &signed_block.block),
        "process block for expected post-state");
    expect_ssz_success(lantern_hash_tree_root_state(&expected_state, &expected_state_root), "hash expected post-state");

    if (memcmp(preview_state_root.bytes, expected_state_root.bytes, LANTERN_ROOT_SIZE) != 0) {
        fprintf(stderr, "compute_post_state root mismatch\n");
        goto cleanup;
    }
    LanternStore *expected_store = lantern_test_state_store_ensure(&expected_state);
    if (!expected_store) {
        fprintf(stderr, "expected-state store missing after compute_post_state\n");
        goto cleanup;
    }
    if (preview_store.validator_votes_len != expected_store->validator_votes_len
        || !preview_store.validator_votes
        || !expected_store->validator_votes) {
        fprintf(stderr, "compute_post_state validator vote capacity mismatch\n");
        goto cleanup;
    }
    if (memcmp(
            &preview_store.validator_votes[1u],
            &expected_store->validator_votes[1u],
            sizeof(preview_store.validator_votes[1u]))
        != 0) {
        fprintf(stderr, "compute_post_state vote cache mismatch\n");
        goto cleanup;
    }

    result = 0;

cleanup:
    lantern_store_reset(&preview_store);
    lantern_state_reset(&preview_state);
    lantern_state_reset(&expected_state);
    lantern_block_body_reset(&block.body);
    lantern_state_reset(&state);
    return result;
}

static int test_compute_post_state_ignores_store_justified_for_hash(void) {
    LanternState state;
    LanternState block_one_state;
    LanternState expected_state;
    LanternState post_state;
    LanternStore post_store;
    LanternForkChoice fork_choice;
    LanternRoot genesis_root;
    LanternRoot block_one_root;
    LanternRoot block_one_state_root;
    LanternRoot expected_state_root;
    LanternRoot post_state_root;
    LanternBlock block_one;
    LanternSignedBlock signed_block;
    LanternCheckpoint store_justified;
    int result = 1;

    lantern_state_init(&state);
    lantern_state_init(&block_one_state);
    lantern_state_init(&expected_state);
    lantern_state_init(&post_state);
    lantern_store_init(&post_store);
    lantern_signed_block_init(&signed_block);
    memset(&block_one, 0, sizeof(block_one));

    setup_state_and_fork_choice(&state, &fork_choice, 1625, 4, &genesis_root);
    expect_zero(
        lantern_state_prepare_validator_votes(&state, state.config.num_validators),
        "prepare validator votes for cached parent seal test");

    make_block(&state, 1u, &genesis_root, &block_one, &block_one_root);
    expect_zero(lantern_state_clone(&state, &block_one_state), "clone cached parent seal state");
    expect_zero(lantern_state_process_slots(&block_one_state, block_one.slot), "advance cached parent seal state");
    expect_zero(
        lantern_state_process_block(&block_one_state, &block_one),
        "process cached parent seal block");
    expect_ssz_success(
        lantern_hash_tree_root_state(&block_one_state, &block_one_state_root),
        "hash cached parent seal state");
    block_one.state_root = block_one_state_root;
    expect_ssz_success(lantern_hash_tree_root_block(&block_one, &block_one_root), "rehash cached parent seal block");
    expect_zero(
        lantern_fork_choice_add_block_with_state(
            &fork_choice,
            &block_one,
            &block_one_state.latest_justified,
            &block_one_state.latest_finalized,
            &block_one_root,
            &block_one_state),
        "add cached parent seal block");

    store_justified.slot = 1u;
    store_justified.root = block_one_root;
    const LanternCheckpoint *store_finalized = lantern_fork_choice_latest_finalized(&fork_choice);
    expect_zero(
        lantern_fork_choice_update_checkpoints(&fork_choice, &store_justified, store_finalized),
        "advance cached parent seal justified");

    signed_block.block.slot = 2u;
    expect_zero(
        lantern_proposer_for_slot(2u, state.config.num_validators, &signed_block.block.proposer_index),
        "compute cached parent seal proposer");
    signed_block.block.parent_root = block_one_root;

    if (lantern_state_compute_post_state(
            &state,
            &signed_block,
            &post_state,
            &post_store,
            &post_state_root)
        != 0) {
        fprintf(stderr, "compute_post_state rejected cached parent after store justified advanced\n");
        goto cleanup;
    }

    expect_zero(lantern_state_clone(&block_one_state, &expected_state), "clone expected cached parent state");
    expect_zero(lantern_state_process_slots(&expected_state, signed_block.block.slot), "advance expected cached parent state");
    expect_zero(
        lantern_state_process_block(&expected_state, &signed_block.block),
        "process expected cached parent block");
    expect_ssz_success(lantern_hash_tree_root_state(&expected_state, &expected_state_root), "hash expected cached parent state");

    if (memcmp(post_state_root.bytes, expected_state_root.bytes, LANTERN_ROOT_SIZE) != 0) {
        fprintf(stderr, "compute_post_state root used store justified checkpoint\n");
        goto cleanup;
    }
    if (!checkpoints_equal(&post_state.latest_justified, &expected_state.latest_justified)) {
        fprintf(stderr, "compute_post_state checkpoint diverged from spec transition\n");
        goto cleanup;
    }
    if (checkpoints_equal(&post_state.latest_justified, &store_justified)) {
        fprintf(stderr, "compute_post_state retained store justified checkpoint\n");
        goto cleanup;
    }

    result = 0;

cleanup:
    lantern_signed_block_reset(&signed_block);
    lantern_store_reset(&post_store);
    lantern_state_reset(&post_state);
    lantern_state_reset(&expected_state);
    lantern_block_body_reset(&block_one.body);
    lantern_state_reset(&block_one_state);
    lantern_state_reset(&state);
    lantern_fork_choice_reset(&fork_choice);
    return result;
}

static int test_compute_vote_checkpoints_basic(void) {
    LanternState state;
    LanternForkChoice fork_choice;
    LanternRoot genesis_root;
    setup_state_and_fork_choice(&state, &fork_choice, 1500, 4, &genesis_root);

    LanternBlock block1;
    LanternRoot block1_root;
    make_block(&state, 1, &genesis_root, &block1, &block1_root);
    expect_zero(
        lantern_fork_choice_add_block(&fork_choice, &block1, NULL, NULL, &block1_root),
        "add block1");
    fork_choice.head = block1_root;
    fork_choice.has_head = true;
    fork_choice.safe_target = block1_root;
    fork_choice.has_safe_target = true;

    LanternCheckpoint head;
    LanternCheckpoint target;
    LanternCheckpoint source;
    int rc = lantern_state_compute_vote_checkpoints(&state, &head, &target, &source);
    if (rc != 0) {
        fprintf(stderr, "compute vote checkpoints basic failed (rc=%d)\n", rc);
        lantern_block_body_reset(&block1.body);
        lantern_state_reset(&state);
        lantern_fork_choice_reset(&fork_choice);
        return 1;
    }
    if (head.slot != block1.slot || memcmp(head.root.bytes, block1_root.bytes, LANTERN_ROOT_SIZE) != 0) {
        fprintf(stderr, "unexpected head checkpoint in basic test\n");
        lantern_block_body_reset(&block1.body);
        lantern_state_reset(&state);
        lantern_fork_choice_reset(&fork_choice);
        return 1;
    }
    if (!checkpoints_equal(&target, &head)) {
        fprintf(stderr, "target mismatch in basic checkpoint computation\n");
        lantern_block_body_reset(&block1.body);
        lantern_state_reset(&state);
        lantern_fork_choice_reset(&fork_choice);
        return 1;
    }
    if (!checkpoints_equal(&source, &state.latest_justified)) {
        fprintf(stderr, "source checkpoint mismatch in basic test\n");
        lantern_block_body_reset(&block1.body);
        lantern_state_reset(&state);
        lantern_fork_choice_reset(&fork_choice);
        return 1;
    }

    lantern_block_body_reset(&block1.body);
    lantern_state_reset(&state);
    lantern_fork_choice_reset(&fork_choice);
    return 0;
}

static int test_compute_vote_checkpoints_genesis_source_uses_head_root(void) {
    LanternState state;
    LanternForkChoice fork_choice;
    LanternRoot genesis_root;
    setup_state_and_fork_choice(&state, &fork_choice, 1525, 4, &genesis_root);

    memset(state.latest_justified.root.bytes, 0, sizeof(state.latest_justified.root.bytes));
    state.latest_justified.slot = 0;
    fork_choice.head = genesis_root;
    fork_choice.has_head = true;
    fork_choice.safe_target = genesis_root;
    fork_choice.has_safe_target = true;

    LanternCheckpoint head;
    LanternCheckpoint target;
    LanternCheckpoint source;
    int rc = lantern_state_compute_vote_checkpoints(&state, &head, &target, &source);
    if (rc != 0) {
        fprintf(stderr, "compute vote checkpoints genesis source failed (rc=%d)\n", rc);
        lantern_state_reset(&state);
        lantern_fork_choice_reset(&fork_choice);
        return 1;
    }
    if (head.slot != 0u || memcmp(head.root.bytes, genesis_root.bytes, LANTERN_ROOT_SIZE) != 0) {
        fprintf(stderr, "unexpected head checkpoint in genesis source test\n");
        lantern_state_reset(&state);
        lantern_fork_choice_reset(&fork_choice);
        return 1;
    }
    if (!checkpoints_equal(&target, &head)) {
        fprintf(stderr, "target mismatch in genesis source test\n");
        lantern_state_reset(&state);
        lantern_fork_choice_reset(&fork_choice);
        return 1;
    }
    if (source.slot != 0u || memcmp(source.root.bytes, genesis_root.bytes, LANTERN_ROOT_SIZE) != 0) {
        fprintf(stderr, "source checkpoint should use head root at genesis\n");
        lantern_state_reset(&state);
        lantern_fork_choice_reset(&fork_choice);
        return 1;
    }

    lantern_state_reset(&state);
    lantern_fork_choice_reset(&fork_choice);
    return 0;
}

static int test_compute_vote_checkpoints_can_match_source(void) {
    LanternState state;
    LanternForkChoice fork_choice;
    LanternRoot genesis_root;
    setup_state_and_fork_choice(&state, &fork_choice, 1550, 4, &genesis_root);

    LanternBlock block1;
    LanternRoot block1_root;
    make_block(&state, 1, &genesis_root, &block1, &block1_root);
    expect_zero(
        lantern_fork_choice_add_block(&fork_choice, &block1, NULL, NULL, &block1_root),
        "add block1 source-match test");
    fork_choice.head = block1_root;
    fork_choice.has_head = true;
    fork_choice.safe_target = genesis_root;
    fork_choice.has_safe_target = true;

    LanternCheckpoint head;
    LanternCheckpoint target;
    LanternCheckpoint source;
    int rc = lantern_state_compute_vote_checkpoints(&state, &head, &target, &source);
    if (rc != 0) {
        fprintf(stderr, "compute vote checkpoints source-match failed (rc=%d)\n", rc);
        lantern_block_body_reset(&block1.body);
        lantern_state_reset(&state);
        lantern_fork_choice_reset(&fork_choice);
        return 1;
    }
    if (head.slot != block1.slot || memcmp(head.root.bytes, block1_root.bytes, LANTERN_ROOT_SIZE) != 0) {
        fprintf(stderr, "unexpected head checkpoint in source-match test\n");
        lantern_block_body_reset(&block1.body);
        lantern_state_reset(&state);
        lantern_fork_choice_reset(&fork_choice);
        return 1;
    }
    if (!checkpoints_equal(&target, &state.latest_justified)) {
        fprintf(stderr, "target should match source/latest_justified when safe target lags at genesis\n");
        lantern_block_body_reset(&block1.body);
        lantern_state_reset(&state);
        lantern_fork_choice_reset(&fork_choice);
        return 1;
    }
    if (!checkpoints_equal(&source, &state.latest_justified)) {
        fprintf(stderr, "source checkpoint mismatch in source-match test\n");
        lantern_block_body_reset(&block1.body);
        lantern_state_reset(&state);
        lantern_fork_choice_reset(&fork_choice);
        return 1;
    }

    lantern_block_body_reset(&block1.body);
    lantern_state_reset(&state);
    lantern_fork_choice_reset(&fork_choice);
    return 0;
}

static int test_compute_vote_checkpoints_respects_safe_target(void) {
    LanternState state;
    LanternForkChoice fork_choice;
    LanternRoot genesis_root;
    setup_state_and_fork_choice(&state, &fork_choice, 1600, 6, &genesis_root);

    LanternBlock block1;
    LanternRoot block1_root;
    make_block(&state, 1, &genesis_root, &block1, &block1_root);
    expect_zero(
        lantern_fork_choice_add_block(&fork_choice, &block1, NULL, NULL, &block1_root),
        "add block1 safe target test");

    LanternBlock block2;
    LanternRoot block2_root;
    make_block(&state, 2, &block1_root, &block2, &block2_root);
    expect_zero(
        lantern_fork_choice_add_block(&fork_choice, &block2, NULL, NULL, &block2_root),
        "add block2 safe target test");

    fork_choice.head = block2_root;
    fork_choice.has_head = true;
    fork_choice.safe_target = block1_root;
    fork_choice.has_safe_target = true;

    state.latest_finalized.slot = 0;
    state.latest_finalized.root = genesis_root;
    state.latest_justified = state.latest_finalized;
    expect_zero(
        lantern_fork_choice_update_checkpoints(&fork_choice, &state.latest_justified, &state.latest_finalized),
        "sync fork choice checkpoints for safe target test");

    LanternCheckpoint head;
    LanternCheckpoint target;
    LanternCheckpoint source;
    int rc = lantern_state_compute_vote_checkpoints(&state, &head, &target, &source);
    if (rc != 0) {
        fprintf(stderr, "compute vote checkpoints safe target failed (rc=%d)\n", rc);
        lantern_block_body_reset(&block2.body);
        lantern_block_body_reset(&block1.body);
        lantern_state_reset(&state);
        lantern_fork_choice_reset(&fork_choice);
        return 1;
    }
    if (head.slot != block2.slot || memcmp(head.root.bytes, block2_root.bytes, LANTERN_ROOT_SIZE) != 0) {
        fprintf(stderr, "unexpected head checkpoint in safe target test\n");
        lantern_block_body_reset(&block2.body);
        lantern_block_body_reset(&block1.body);
        lantern_state_reset(&state);
        lantern_fork_choice_reset(&fork_choice);
        return 1;
    }
    if (target.slot != block1.slot || memcmp(target.root.bytes, block1_root.bytes, LANTERN_ROOT_SIZE) != 0) {
        fprintf(stderr, "target checkpoint not aligned with safe target\n");
        lantern_block_body_reset(&block2.body);
        lantern_block_body_reset(&block1.body);
        lantern_state_reset(&state);
        lantern_fork_choice_reset(&fork_choice);
        return 1;
    }
    if (!checkpoints_equal(&source, &state.latest_justified)) {
        fprintf(stderr, "source checkpoint mismatch in safe target test\n");
        lantern_block_body_reset(&block2.body);
        lantern_block_body_reset(&block1.body);
        lantern_state_reset(&state);
        lantern_fork_choice_reset(&fork_choice);
        return 1;
    }

    lantern_block_body_reset(&block2.body);
    lantern_block_body_reset(&block1.body);
    lantern_state_reset(&state);
    lantern_fork_choice_reset(&fork_choice);
    return 0;
}

static int test_compute_vote_checkpoints_uses_head_state_source_when_store_justified_advances(void) {
    LanternState state;
    LanternForkChoice fork_choice;
    LanternRoot genesis_root;
    setup_state_and_fork_choice(&state, &fork_choice, 1650, 8, &genesis_root);

    LanternRoot block_roots[5];
    block_roots[0] = genesis_root;
    LanternRoot parent_root = genesis_root;
    for (uint64_t slot = 1; slot <= 3; ++slot) {
        LanternBlock block;
        LanternRoot block_root;
        make_block(&state, slot, &parent_root, &block, &block_root);
        expect_zero(
            lantern_fork_choice_add_block(&fork_choice, &block, NULL, NULL, &block_root),
            "add block for head-state source test");
        block_roots[slot] = block_root;
        parent_root = block_root;
        lantern_block_body_reset(&block.body);
    }

    state.latest_finalized.slot = 0;
    state.latest_finalized.root = block_roots[0];
    state.latest_justified.slot = 2;
    state.latest_justified.root = block_roots[2];

    LanternState cached_head_state;
    lantern_state_init(&cached_head_state);
    expect_zero(lantern_state_clone(&state, &cached_head_state), "clone cached head state");

    LanternBlock head_block;
    make_block(&state, 4, &parent_root, &head_block, &block_roots[4]);
    expect_zero(
        lantern_fork_choice_add_block_with_state(
            &fork_choice,
            &head_block,
            NULL,
            NULL,
            &block_roots[4],
            &cached_head_state),
        "add head block with cached state");
    lantern_block_body_reset(&head_block.body);

    fork_choice.head = block_roots[4];
    fork_choice.has_head = true;
    fork_choice.safe_target = block_roots[4];
    fork_choice.has_safe_target = true;

    LanternCheckpoint store_justified;
    store_justified.slot = 3;
    store_justified.root = block_roots[3];
    expect_zero(
        lantern_fork_choice_update_checkpoints(&fork_choice, &store_justified, &state.latest_finalized),
        "advance fork-choice justified beyond head-state justified");

    LanternCheckpoint head;
    LanternCheckpoint target;
    LanternCheckpoint source;
    int rc = lantern_state_compute_vote_checkpoints(&state, &head, &target, &source);
    if (rc != 0) {
        fprintf(stderr, "compute vote checkpoints head-state source failed (rc=%d)\n", rc);
        lantern_state_reset(&cached_head_state);
        lantern_state_reset(&state);
        lantern_fork_choice_reset(&fork_choice);
        return 1;
    }
    if (!checkpoints_equal(&source, &cached_head_state.latest_justified)) {
        fprintf(stderr, "source checkpoint should use head state's latest_justified\n");
        lantern_state_reset(&cached_head_state);
        lantern_state_reset(&state);
        lantern_fork_choice_reset(&fork_choice);
        return 1;
    }
    if (checkpoints_equal(&source, &store_justified)) {
        fprintf(stderr, "source checkpoint incorrectly used store latest_justified\n");
        lantern_state_reset(&cached_head_state);
        lantern_state_reset(&state);
        lantern_fork_choice_reset(&fork_choice);
        return 1;
    }

    lantern_state_reset(&cached_head_state);
    lantern_state_reset(&state);
    lantern_fork_choice_reset(&fork_choice);
    return 0;
}

static int test_compute_vote_checkpoints_justifiable(void) {
    LanternState state;
    LanternForkChoice fork_choice;
    LanternRoot genesis_root;
    setup_state_and_fork_choice(&state, &fork_choice, 1700, 8, &genesis_root);

    LanternRoot parent_root = genesis_root;
    LanternRoot block_roots[8];
    block_roots[0] = genesis_root;
    for (uint64_t slot = 1; slot <= 7; ++slot) {
        LanternBlock block;
        LanternRoot block_root;
        make_block(&state, slot, &parent_root, &block, &block_root);
        expect_zero(
            lantern_fork_choice_add_block(&fork_choice, &block, NULL, NULL, &block_root),
            "add block for justifiable test");
        block_roots[slot] = block_root;
        parent_root = block_root;
        lantern_block_body_reset(&block.body);
    }

    fork_choice.head = block_roots[7];
    fork_choice.has_head = true;
    fork_choice.safe_target = block_roots[7];
    fork_choice.has_safe_target = true;

    state.latest_finalized.slot = 0;
    state.latest_finalized.root = genesis_root;
    state.latest_justified = state.latest_finalized;
    expect_zero(
        lantern_fork_choice_update_checkpoints(&fork_choice, &state.latest_justified, &state.latest_finalized),
        "sync fork choice checkpoints for justifiable test");

    LanternCheckpoint head;
    LanternCheckpoint target;
    LanternCheckpoint source;
    int rc = lantern_state_compute_vote_checkpoints(&state, &head, &target, &source);
    if (rc != 0) {
        fprintf(stderr, "compute vote checkpoints justifiable failed (rc=%d)\n", rc);
        lantern_state_reset(&state);
        lantern_fork_choice_reset(&fork_choice);
        return 1;
    }
    if (head.slot != 7 || memcmp(head.root.bytes, block_roots[7].bytes, LANTERN_ROOT_SIZE) != 0) {
        fprintf(stderr, "unexpected head checkpoint in justifiable test\n");
        lantern_state_reset(&state);
        lantern_fork_choice_reset(&fork_choice);
        return 1;
    }
    uint64_t expected_target_slot = head.slot;
    while (!slot_is_justifiable_for_tests(expected_target_slot, state.latest_finalized.slot)) {
        if (expected_target_slot == 0) {
            break;
        }
        expected_target_slot -= 1u;
    }
    if (target.slot != expected_target_slot
        || memcmp(target.root.bytes, block_roots[expected_target_slot].bytes, LANTERN_ROOT_SIZE) != 0) {
        fprintf(stderr, "target checkpoint not adjusted for justifiability\n");
        lantern_state_reset(&state);
        lantern_fork_choice_reset(&fork_choice);
        return 1;
    }
    if (!checkpoints_equal(&source, &state.latest_justified)) {
        fprintf(stderr, "source checkpoint mismatch in justifiable test\n");
        lantern_state_reset(&state);
        lantern_fork_choice_reset(&fork_choice);
        return 1;
    }

    lantern_state_reset(&state);
    lantern_fork_choice_reset(&fork_choice);
    return 0;
}

static int test_compute_vote_checkpoints_consecutive_target(void) {
    LanternState state;
    LanternForkChoice fork_choice;
    LanternRoot genesis_root;
    setup_state_and_fork_choice(&state, &fork_choice, 1750, 6, &genesis_root);

    LanternRoot block_roots[6];
    block_roots[0] = genesis_root;
    LanternRoot parent_root = genesis_root;
    for (uint64_t slot = 1; slot <= 5; ++slot) {
        LanternBlock block;
        LanternRoot block_root;
        make_block(&state, slot, &parent_root, &block, &block_root);
        expect_zero(
            lantern_fork_choice_add_block(&fork_choice, &block, NULL, NULL, &block_root),
            "add block for consecutive target test");
        block_roots[slot] = block_root;
        parent_root = block_root;
        lantern_block_body_reset(&block.body);
    }

    fork_choice.head = block_roots[5];
    fork_choice.has_head = true;
    fork_choice.safe_target = block_roots[5];
    fork_choice.has_safe_target = true;

    state.latest_finalized.slot = 3;
    state.latest_finalized.root = block_roots[3];
    state.latest_justified.slot = 4;
    state.latest_justified.root = block_roots[4];
    expect_zero(
        lantern_fork_choice_update_checkpoints(&fork_choice, &state.latest_justified, &state.latest_finalized),
        "sync fork choice checkpoints for consecutive target test");

    LanternCheckpoint head;
    LanternCheckpoint target;
    LanternCheckpoint source;
    if (lantern_state_compute_vote_checkpoints(&state, &head, &target, &source) != 0) {
        fprintf(stderr, "compute vote checkpoints consecutive target failed\n");
        lantern_state_reset(&state);
        lantern_fork_choice_reset(&fork_choice);
        return 1;
    }
    if (target.slot != head.slot || memcmp(target.root.bytes, block_roots[5].bytes, LANTERN_ROOT_SIZE) != 0) {
        fprintf(stderr, "target checkpoint not aligned with head in consecutive target test\n");
        lantern_state_reset(&state);
        lantern_fork_choice_reset(&fork_choice);
        return 1;
    }
    if (target.slot <= source.slot) {
        fprintf(stderr, "target did not advance beyond source in consecutive target test\n");
        lantern_state_reset(&state);
        lantern_fork_choice_reset(&fork_choice);
        return 1;
    }
    if (!checkpoints_equal(&source, &state.latest_justified)) {
        fprintf(stderr, "source checkpoint mismatch in consecutive target test\n");
        lantern_state_reset(&state);
        lantern_fork_choice_reset(&fork_choice);
        return 1;
    }

    lantern_state_reset(&state);
    lantern_fork_choice_reset(&fork_choice);
    return 0;
}

static int test_compute_vote_checkpoints_advances_beyond_source(void) {
    LanternState state;
    LanternForkChoice fork_choice;
    LanternRoot genesis_root;
    setup_state_and_fork_choice(&state, &fork_choice, 1800, 8, &genesis_root);

    LanternRoot block_roots[11];
    block_roots[0] = genesis_root;
    LanternRoot parent_root = genesis_root;
    for (uint64_t slot = 1; slot <= 10; ++slot) {
        LanternBlock block;
        LanternRoot block_root;
        make_block(&state, slot, &parent_root, &block, &block_root);
        expect_zero(
            lantern_fork_choice_add_block(&fork_choice, &block, NULL, NULL, &block_root),
            "add block for advance target test");
        block_roots[slot] = block_root;
        parent_root = block_root;
        lantern_block_body_reset(&block.body);
    }

    fork_choice.head = block_roots[10];
    fork_choice.has_head = true;
    fork_choice.safe_target = block_roots[10];
    fork_choice.has_safe_target = true;

    for (uint64_t slot = 0; slot <= 6; ++slot) {
        mark_slot_justified_for_tests(&state, slot);
    }
    state.latest_finalized.slot = 0;
    state.latest_finalized.root = block_roots[0];
    state.latest_justified.slot = 6;
    state.latest_justified.root = block_roots[6];
    expect_zero(
        lantern_fork_choice_update_checkpoints(&fork_choice, &state.latest_justified, &state.latest_finalized),
        "sync fork choice checkpoints for advance target test");

    LanternCheckpoint head;
    LanternCheckpoint target;
    LanternCheckpoint source;
    if (lantern_state_compute_vote_checkpoints(&state, &head, &target, &source) != 0) {
        fprintf(stderr, "compute vote checkpoints advance test failed\n");
        lantern_state_reset(&state);
        lantern_fork_choice_reset(&fork_choice);
        return 1;
    }
    if (head.slot != 10 || memcmp(head.root.bytes, block_roots[10].bytes, LANTERN_ROOT_SIZE) != 0) {
        fprintf(stderr, "head checkpoint mismatch in advance test\n");
        lantern_state_reset(&state);
        lantern_fork_choice_reset(&fork_choice);
        return 1;
    }
    uint64_t expected_slot = head.slot;
    while (!slot_is_justifiable_for_tests(expected_slot, state.latest_finalized.slot)) {
        if (expected_slot == 0) {
            break;
        }
        expected_slot -= 1u;
    }
    if (expected_slot <= state.latest_justified.slot) {
        fprintf(stderr, "expected slot did not advance beyond source in advance test\n");
        lantern_state_reset(&state);
        lantern_fork_choice_reset(&fork_choice);
        return 1;
    }
    if (target.slot != expected_slot
        || memcmp(target.root.bytes, block_roots[expected_slot].bytes, LANTERN_ROOT_SIZE) != 0) {
        fprintf(stderr, "target checkpoint mismatch in advance test\n");
        lantern_state_reset(&state);
        lantern_fork_choice_reset(&fork_choice);
        return 1;
    }
    if (!checkpoints_equal(&source, &state.latest_justified)) {
        fprintf(stderr, "source checkpoint mismatch in advance test\n");
        lantern_state_reset(&state);
        lantern_fork_choice_reset(&fork_choice);
        return 1;
    }

    lantern_state_reset(&state);
    lantern_fork_choice_reset(&fork_choice);
    return 0;
}

static int test_compute_vote_checkpoints_uses_finalized_lower_bound_when_safe_stale(void) {
    LanternState state;
    LanternForkChoice fork_choice;
    LanternRoot genesis_root;
    setup_state_and_fork_choice(&state, &fork_choice, 1850, 6, &genesis_root);

    LanternRoot block_roots[6];
    block_roots[0] = genesis_root;
    LanternRoot parent_root = genesis_root;
    for (uint64_t slot = 1; slot <= 5; ++slot) {
        LanternBlock block;
        LanternRoot block_root;
        make_block(&state, slot, &parent_root, &block, &block_root);
        expect_zero(
            lantern_fork_choice_add_block(&fork_choice, &block, NULL, NULL, &block_root),
            "add block for stale safe target lower-bound test");
        block_roots[slot] = block_root;
        parent_root = block_root;
        lantern_block_body_reset(&block.body);
    }

    fork_choice.head = block_roots[5];
    fork_choice.has_head = true;
    fork_choice.safe_target = block_roots[1];
    fork_choice.has_safe_target = true;

    state.latest_finalized.slot = 4;
    state.latest_finalized.root = block_roots[4];
    state.latest_justified = state.latest_finalized;
    expect_zero(
        lantern_fork_choice_update_checkpoints(&fork_choice, &state.latest_justified, &state.latest_finalized),
        "sync fork choice checkpoints for stale safe target lower-bound test");

    LanternCheckpoint head;
    LanternCheckpoint target;
    LanternCheckpoint source;
    if (lantern_state_compute_vote_checkpoints(&state, &head, &target, &source) != 0) {
        fprintf(stderr, "compute vote checkpoints stale safe target lower-bound test failed\n");
        lantern_state_reset(&state);
        lantern_fork_choice_reset(&fork_choice);
        return 1;
    }
    if (head.slot != 5 || memcmp(head.root.bytes, block_roots[5].bytes, LANTERN_ROOT_SIZE) != 0) {
        fprintf(stderr, "head checkpoint mismatch in stale safe target lower-bound test\n");
        lantern_state_reset(&state);
        lantern_fork_choice_reset(&fork_choice);
        return 1;
    }
    if (target.slot != state.latest_finalized.slot
        || memcmp(target.root.bytes, block_roots[4].bytes, LANTERN_ROOT_SIZE) != 0) {
        fprintf(stderr, "target walked below finalized lower bound when safe target was stale\n");
        lantern_state_reset(&state);
        lantern_fork_choice_reset(&fork_choice);
        return 1;
    }
    if (!checkpoints_equal(&source, &state.latest_justified)) {
        fprintf(stderr, "source checkpoint mismatch in stale safe target lower-bound test\n");
        lantern_state_reset(&state);
        lantern_fork_choice_reset(&fork_choice);
        return 1;
    }

    lantern_state_reset(&state);
    lantern_fork_choice_reset(&fork_choice);
    return 0;
}

static int test_history_limits_enforced(void) {
    const uint64_t genesis_time = 999;
    const uint64_t validator_count = 8;
    LanternState state;
    lantern_state_init(&state);
    expect_zero(lantern_state_generate_genesis(&state, genesis_time, validator_count), "genesis for history test");

    expect_zero(
        lantern_root_list_resize(&state.historical_block_hashes, LANTERN_HISTORICAL_ROOTS_LIMIT),
        "prep historical roots");
    fill_root(&state.historical_block_hashes.items[0], 0x5Au);
    expect_zero(
        lantern_bitlist_resize(&state.justified_slots, LANTERN_HISTORICAL_ROOTS_LIMIT),
        "prep justified slots");

    state.latest_block_header.slot = LANTERN_HISTORICAL_ROOTS_LIMIT;
    state.slot = state.latest_block_header.slot + 1;

    LanternBlock block;
    memset(&block, 0, sizeof(block));
    block.slot = state.slot;
    expect_zero(
        lantern_proposer_for_slot(block.slot, validator_count, &block.proposer_index),
        "proposer for history limit block");
    expect_ssz_success(
        lantern_hash_tree_root_block_header(&state.latest_block_header, &block.parent_root),
        "hash parent header for history limit block");
    lantern_block_body_init(&block.body);

    expect_zero(lantern_state_process_block_header(&state, &block), "process history limit block");
    assert(state.historical_block_hashes.length == LANTERN_HISTORICAL_ROOTS_LIMIT);
    assert(state.historical_block_hashes.items[0].bytes[0] == 0x5Au);
    assert(state.justified_slots.bit_length == LANTERN_HISTORICAL_ROOTS_LIMIT);

    lantern_block_body_reset(&block.body);
    lantern_state_reset(&state);
    return 0;
}

static int test_justified_slot_window_helpers(void) {
    LanternState state;
    lantern_state_init(&state);
    expect_zero(lantern_state_generate_genesis(&state, 111, 4), "genesis for slot window test");

    state.latest_finalized.slot = 9u;
    expect_zero(lantern_bitlist_resize(&state.justified_slots, 4), "initialize bitlist window");
    state.justified_slots.bytes[0] = 0;
    state.justified_slots.bytes[0] |= (uint8_t)(1u << 1u); /* slot anchor + 1 */

    assert(lantern_state_slot_in_justified_window(&state, 9u));
    assert(lantern_state_slot_in_justified_window(&state, 10u));
    assert(!lantern_state_slot_in_justified_window(&state, 14u));

    bool bit = false;
    expect_zero(lantern_state_get_justified_slot_bit(&state, 11u, &bit), "read window bit");
    assert(bit);

    expect_zero(lantern_state_mark_justified_slot(&state, 9u), "mark finalized slot");
    assert(state.justified_slots.bit_length == 4u);

    expect_zero(lantern_state_mark_justified_slot(&state, 14u), "mark new slot past window");
    assert(state.justified_slots.bit_length == 5u);
    assert(lantern_state_slot_in_justified_window(&state, 14u));
    assert(lantern_state_slot_in_justified_window(&state, 10u));

    bool latest_bit = false;
    expect_zero(lantern_state_get_justified_slot_bit(&state, 14u, &latest_bit), "read latest bit");
    assert(latest_bit);

    lantern_state_reset(&state);
    return 0;
}

static int test_state_aggregate_skips_single_child_group(void) {
    LanternState state;
    LanternAggregatedAttestations aggregated_attestations;
    LanternAttestationSignatures aggregated_signatures;
    LanternAggregatedSignatureProof child_proof;
    LanternStore *store = NULL;
    LanternVote vote;
    LanternSignature signature;
    int rc = 1;

    lantern_state_init(&state);
    lantern_aggregated_attestations_init(&aggregated_attestations);
    lantern_attestation_signatures_init(&aggregated_signatures);
    lantern_aggregated_signature_proof_init(&child_proof);
    memset(&vote, 0, sizeof(vote));
    memset(&signature, 0, sizeof(signature));

    expect_zero(
        lantern_state_generate_genesis(&state, 3000u, 1u),
        "genesis for recursive single-child state aggregate test");
    store = lantern_test_state_store_ensure(&state);
    if (!store) {
        fprintf(stderr, "state store missing for recursive single-child state aggregate test\n");
        goto cleanup;
    }

    LanternCheckpoint source = state.latest_justified;
    LanternCheckpoint target = source;
    target.slot = source.slot + 1u;
    fill_root(&target.root, 0x71u);
    build_vote(&vote, &signature, 0u, target.slot, &source, &target, 0x72u);

    LanternRoot data_root;
    expect_ssz_success(
        lantern_hash_tree_root_attestation_data(&vote.data, &data_root),
        "hash attestation data for recursive single-child state aggregate test");
    if (build_cached_proof_for_vote(&child_proof, 0u, 0xC3u) != 0) {
        fprintf(stderr, "build child proof failed for recursive single-child state aggregate test\n");
        goto cleanup;
    }
    expect_zero(
        lantern_store_add_new_aggregated_payload(
            store,
            &data_root,
            &vote.data,
            &child_proof,
            vote.target.slot),
        "seed new payload for recursive single-child state aggregate test");

    if (lantern_state_aggregate(
            &state,
            store,
            NULL,
            &store->new_aggregated_payloads,
            &store->known_aggregated_payloads,
            &aggregated_attestations,
            &aggregated_signatures)
        != LANTERN_STATE_AGGREGATE_OK) {
        fprintf(stderr, "state aggregate single-child case failed\n");
        goto cleanup;
    }
    if (aggregated_attestations.length != 0u || aggregated_signatures.length != 0u) {
        fprintf(stderr, "state aggregate should skip single-child-only groups\n");
        goto cleanup;
    }

    rc = 0;

cleanup:
    lantern_aggregated_signature_proof_reset(&child_proof);
    lantern_attestation_signatures_reset(&aggregated_signatures);
    lantern_aggregated_attestations_reset(&aggregated_attestations);
    lantern_state_reset(&state);
    return rc;
}

int main(void) {
    if (test_genesis_state() != 0) {
        return 1;
    }
    if (test_genesis_justification_bits() != 0) {
        return 1;
    }
    if (test_validator_registry_limit_enforced() != 0) {
        return 1;
    }
    if (test_block_header_rejects_duplicate_slot() != 0) {
        return 1;
    }
    if (test_block_header_rejects_zero_parent_root() != 0) {
        return 1;
    }
    if (test_process_block_rejects_duplicate_attestation_data() != 0) {
        return 1;
    }
    if (test_process_slots_sets_state_root() != 0) {
        return 1;
    }
    if (test_process_slots_rejects_non_future_target() != 0) {
        return 1;
    }
    if (test_state_transition_applies_block() != 0) {
        return 1;
    }
    if (test_state_transition_rejects_missing_block_proof() != 0) {
        return 1;
    }
    if (test_state_transition_rejects_genesis_state_root_mismatch() != 0) {
        return 1;
    }
    if (test_compute_post_state_matches_process_block_and_votes() != 0) {
        return 1;
    }
    if (test_compute_post_state_ignores_store_justified_for_hash() != 0) {
        return 1;
    }
    if (test_attestations_single_vote_justifies() != 0) {
        return 1;
    }
    if (test_attestations_require_justified_source() != 0) {
        return 1;
    }
    if (test_attestations_accept_duplicate_votes() != 0) {
        return 1;
    }
    if (test_attestations_nonconsecutive_followup_does_not_finalize() != 0) {
        return 1;
    }
    if (test_attestations_finalize_after_second_consecutive_vote() != 0) {
        return 1;
    }
    if (test_attestations_finalize_across_gap() != 0) {
        return 1;
    }
    if (test_attestations_use_updated_finalized_slot_for_target_justifiability() != 0) {
        return 1;
    }
    if (test_attestations_use_updated_finalized_slot_for_gap_check() != 0) {
        return 1;
    }
    if (test_attestations_do_not_refinalize_source_at_finalized_boundary() != 0) {
        return 1;
    }
    if (test_attestations_do_not_regress_latest_justified() != 0) {
        return 1;
    }
    if (test_pruning_keeps_pending_justifications() != 0) {
        return 1;
    }
    if (test_pending_votes_survive_interleaved_justification_and_finalization() != 0) {
        return 1;
    }
    if (test_pending_votes_preserved_when_new_root_inserts_before_existing_root() != 0) {
        return 1;
    }
    if (test_attestations_ignore_zero_hash_votes() != 0) {
        return 1;
    }
    if (test_attestations_ignore_head_root_mismatch() != 0) {
        return 1;
    }
    if (test_attestations_ignore_out_of_range_validator() != 0) {
        return 1;
    }
    if (test_process_block_accepts_mixed_attestations() != 0) {
        return 1;
    }
    if (test_collect_attestations_for_block() != 0) {
        return 1;
    }
    if (test_process_block_rejects_too_many_attestation_data_entries() != 0) {
        return 1;
    }
    if (test_process_attestations_preserves_signed_votes() != 0) {
        return 1;
    }
    if (test_process_block_defers_proposer_attestation() != 0) {
        return 1;
    }
    if (test_collect_attestations_fixed_point() != 0) {
        return 1;
    }
    if (test_collect_attestations_respects_max_attestation_data() != 0) {
        return 1;
    }
    if (test_collect_attestations_fixed_point_deep_chain() != 0) {
        return 1;
    }
    if (test_collect_attestations_ignores_store_justified_when_parent_state_lags() != 0) {
        return 1;
    }
    if (test_select_block_parent_uses_fork_choice() != 0) {
        return 1;
    }
    if (test_validator_helpers_use_cached_fork_choice_head_state() != 0) {
        return 1;
    }
    if (test_compute_vote_checkpoints_basic() != 0) {
        return 1;
    }
    if (test_compute_vote_checkpoints_genesis_source_uses_head_root() != 0) {
        return 1;
    }
    if (test_compute_vote_checkpoints_can_match_source() != 0) {
        return 1;
    }
    if (test_compute_vote_checkpoints_uses_head_state_source_when_store_justified_advances() != 0) {
        return 1;
    }
    if (test_compute_vote_checkpoints_respects_safe_target() != 0) {
        return 1;
    }
    if (test_compute_vote_checkpoints_justifiable() != 0) {
        return 1;
    }
    if (test_compute_vote_checkpoints_consecutive_target() != 0) {
        return 1;
    }
    if (test_compute_vote_checkpoints_advances_beyond_source() != 0) {
        return 1;
    }
    if (test_compute_vote_checkpoints_uses_finalized_lower_bound_when_safe_stale() != 0) {
        return 1;
    }
    if (test_history_limits_enforced() != 0) {
        return 1;
    }
    if (test_justified_slot_window_helpers() != 0) {
        return 1;
    }
    if (test_state_aggregate_skips_single_child_group() != 0) {
        return 1;
    }
    puts("lantern_state_test OK");
    return 0;
}
