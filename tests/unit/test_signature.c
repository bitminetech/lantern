#include "lantern/consensus/containers.h"
#include "lantern/consensus/hash.h"
#include "lantern/consensus/signature.h"
#include "lantern/consensus/state.h"
#include "lantern/metrics/lean_metrics.h"

#include "pq-bindings-c-rust.h"

#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const size_t kTestActiveEpochs = 4;

static void fill_root(LanternRoot *root, uint8_t seed) {
    assert(root);
    for (size_t i = 0; i < sizeof(root->bytes); ++i) {
        root->bytes[i] = (uint8_t)(seed + (uint8_t)i);
    }
}

static void init_checkpoint(LanternCheckpoint *cp, uint64_t slot, uint8_t seed) {
    assert(cp);
    cp->slot = slot;
    fill_root(&cp->root, seed);
}

static void build_proposer_vote(LanternVote *vote, uint64_t validator_id, uint64_t slot) {
    assert(vote);
    memset(vote, 0, sizeof(*vote));
    vote->validator_id = validator_id;
    vote->slot = slot;
    init_checkpoint(&vote->head, slot, 0x11);
    init_checkpoint(&vote->target, slot, 0x33);
    init_checkpoint(&vote->source, slot > 0 ? slot - 1 : 0, 0x55);
}

static int generate_test_keypair(
    struct PQSignatureSchemePublicKey **out_pub,
    struct PQSignatureSchemeSecretKey **out_secret) {
    if (!out_pub || !out_secret) {
        return -1;
    }
    *out_pub = NULL;
    *out_secret = NULL;
    enum PQSigningError err = pq_key_gen(0, kTestActiveEpochs, out_pub, out_secret);
    if (err != Success || !*out_pub || !*out_secret) {
        if (*out_pub) {
            pq_public_key_free(*out_pub);
            *out_pub = NULL;
        }
        if (*out_secret) {
            pq_secret_key_free(*out_secret);
            *out_secret = NULL;
        }
        fprintf(stderr, "pq_key_gen failed (%d)\n", (int)err);
        return -1;
    }
    return 0;
}

static bool sign_proposer_vote(
    struct PQSignatureSchemeSecretKey *secret,
    LanternSignedVote *signed_vote,
    LanternRoot *out_vote_root) {
    if (!secret || !signed_vote || !out_vote_root) {
        return false;
    }
    if (lantern_hash_tree_root_vote(&signed_vote->data, out_vote_root) != SSZ_SUCCESS) {
        fprintf(stderr, "hash_tree_root_vote failed\n");
        return false;
    }
    if (!lantern_signature_sign(
            secret,
            signed_vote->data.slot,
            out_vote_root,
            &signed_vote->signature)) {
        fprintf(stderr, "lantern_signature_sign failed\n");
        return false;
    }
    return true;
}

static bool aggregated_proof_tamper_is_rejected(
    const uint8_t *const *pubkeys,
    size_t count,
    const LanternRoot *message,
    const LanternByteList *proof,
    uint64_t epoch) {
    LanternByteList tampered;
    size_t candidate_count = 0;
    size_t candidates[4];

    if (!pubkeys || !message || !proof || proof->length == 0 || !proof->data) {
        return false;
    }

    lantern_byte_list_init(&tampered);
    if (lantern_byte_list_copy(&tampered, proof) != 0 || tampered.length == 0 || !tampered.data) {
        lantern_byte_list_reset(&tampered);
        return false;
    }

    candidates[candidate_count++] = 0u;
    candidates[candidate_count++] = tampered.length / 4u;
    candidates[candidate_count++] = tampered.length / 2u;
    candidates[candidate_count++] = tampered.length - 1u;

    for (size_t i = 0; i < candidate_count; ++i) {
        size_t offset = candidates[i];
        bool seen = false;
        for (size_t j = 0; j < i; ++j) {
            if (candidates[j] == offset) {
                seen = true;
                break;
            }
        }
        if (seen) {
            continue;
        }

        tampered.data[offset] ^= 0xFFu;
        if (!lantern_signature_verify_aggregated(pubkeys, count, message, &tampered, epoch)) {
            lantern_byte_list_reset(&tampered);
            return true;
        }
        tampered.data[offset] ^= 0xFFu;
    }

    if (tampered.length > 1u
        && lantern_byte_list_resize(&tampered, tampered.length - 1u) == 0
        && !lantern_signature_verify_aggregated(pubkeys, count, message, &tampered, epoch)) {
        lantern_byte_list_reset(&tampered);
        return true;
    }

    lantern_byte_list_reset(&tampered);
    return false;
}

static bool set_participants(
    struct lantern_bitlist *participants,
    size_t bit_length,
    const size_t *indices,
    size_t count) {
    if (!participants || !indices) {
        return false;
    }
    if (lantern_bitlist_resize(participants, bit_length) != 0) {
        return false;
    }
    for (size_t i = 0; i < count; ++i) {
        if (lantern_bitlist_set(participants, indices[i], true) != 0) {
            return false;
        }
    }
    return true;
}

static bool expect_aggregated_build_metrics(
    uint64_t total,
    uint64_t attestations,
    const char *context) {
    struct lean_metrics_snapshot metrics_snapshot;
    memset(&metrics_snapshot, 0, sizeof(metrics_snapshot));
    lean_metrics_snapshot(&metrics_snapshot);
    if (metrics_snapshot.pq_sig_aggregated_signatures_total != total
        || metrics_snapshot.pq_sig_attestations_in_aggregated_signatures_total != attestations
        || metrics_snapshot.pq_sig_aggregated_signatures_building_time.total != total) {
        fprintf(stderr, "recursive aggregate: %s metrics mismatch\n", context);
        return false;
    }
    return true;
}

static int test_proposer_vote_signature_roundtrip(void) {
    struct PQSignatureSchemePublicKey *pubkey = NULL;
    struct PQSignatureSchemeSecretKey *secret = NULL;
    if (generate_test_keypair(&pubkey, &secret) != 0) {
        return 1;
    }

    LanternSignedVote signed_vote;
    memset(&signed_vote, 0, sizeof(signed_vote));
    build_proposer_vote(&signed_vote.data, 5, 12);

    LanternRoot vote_root;
    if (!sign_proposer_vote(secret, &signed_vote, &vote_root)) {
        pq_secret_key_free(secret);
        pq_public_key_free(pubkey);
        return 1;
    }

    if (!lantern_signature_verify_pk(
            pubkey,
            signed_vote.data.slot,
            &signed_vote.signature,
            &vote_root)) {
        fprintf(stderr, "verify_pk rejected valid proposer vote\n");
        pq_secret_key_free(secret);
        pq_public_key_free(pubkey);
        return 1;
    }

    uint8_t serialized_pubkey[LANTERN_VALIDATOR_PUBKEY_SIZE];
    uintptr_t written = 0;
    enum PQSigningError serr = pq_public_key_serialize(
        pubkey,
        serialized_pubkey,
        sizeof(serialized_pubkey),
        &written);
    if (serr != Success || written == 0 || written > sizeof(serialized_pubkey)) {
        fprintf(stderr, "failed to serialize public key (%d)\n", (int)serr);
        pq_secret_key_free(secret);
        pq_public_key_free(pubkey);
        return 1;
    }

    if (!lantern_signature_verify(
            serialized_pubkey,
            (size_t)written,
            signed_vote.data.slot,
            &signed_vote.signature,
            &vote_root)) {
        fprintf(stderr, "verify(bytes) rejected valid proposer vote\n");
        pq_secret_key_free(secret);
        pq_public_key_free(pubkey);
        return 1;
    }

    pq_secret_key_free(secret);
    pq_public_key_free(pubkey);
    return 0;
}

static int test_proposer_vote_signature_rejects_tampering(void) {
    struct PQSignatureSchemePublicKey *pubkey = NULL;
    struct PQSignatureSchemeSecretKey *secret = NULL;
    if (generate_test_keypair(&pubkey, &secret) != 0) {
        return 1;
    }

    LanternSignedVote signed_vote;
    memset(&signed_vote, 0, sizeof(signed_vote));
    build_proposer_vote(&signed_vote.data, 9, 3);

    LanternRoot vote_root;
    if (!sign_proposer_vote(secret, &signed_vote, &vote_root)) {
        pq_secret_key_free(secret);
        pq_public_key_free(pubkey);
        return 1;
    }

    LanternVote tampered_vote = signed_vote.data;
    tampered_vote.head.root.bytes[0] ^= 0xFF;
    LanternRoot tampered_root;
    if (lantern_hash_tree_root_vote(&tampered_vote, &tampered_root) != SSZ_SUCCESS) {
        fprintf(stderr, "tampered root calculation failed\n");
        pq_secret_key_free(secret);
        pq_public_key_free(pubkey);
        return 1;
    }

    if (lantern_signature_verify_pk(
            pubkey,
            signed_vote.data.slot,
            &signed_vote.signature,
            &tampered_root)) {
        fprintf(stderr, "verify_pk accepted tampered proposer vote\n");
        pq_secret_key_free(secret);
        pq_public_key_free(pubkey);
        return 1;
    }

    pq_secret_key_free(secret);
    pq_public_key_free(pubkey);
    return 0;
}

static int test_aggregated_signature_roundtrip(void) {
    enum { kSignerCount = 2 };
    struct PQSignatureSchemePublicKey *pubkeys[kSignerCount];
    struct PQSignatureSchemeSecretKey *secrets[kSignerCount];
    uint8_t serialized_pubkeys[kSignerCount][LANTERN_VALIDATOR_PUBKEY_SIZE];
    const uint8_t *pubkey_ptrs[kSignerCount];
    LanternSignature signatures[kSignerCount];
    LanternByteList proof;
    LanternRoot message;
    uint64_t epoch = 1;

    memset(pubkeys, 0, sizeof(pubkeys));
    memset(secrets, 0, sizeof(secrets));
    memset(serialized_pubkeys, 0, sizeof(serialized_pubkeys));
    memset(signatures, 0, sizeof(signatures));
    lantern_byte_list_init(&proof);
    fill_root(&message, 0xA1);

    for (size_t i = 0; i < kSignerCount; ++i) {
        if (generate_test_keypair(&pubkeys[i], &secrets[i]) != 0) {
            fprintf(stderr, "aggregate: keygen failed index=%zu\n", i);
            goto fail;
        }
        uintptr_t written = 0;
        enum PQSigningError serr = pq_public_key_serialize(
            pubkeys[i],
            serialized_pubkeys[i],
            sizeof(serialized_pubkeys[i]),
            &written);
        if (serr != Success || written != sizeof(serialized_pubkeys[i])) {
            fprintf(stderr, "aggregate: pubkey serialize failed index=%zu err=%d written=%zu\n", i, (int)serr, (size_t)written);
            goto fail;
        }
        pubkey_ptrs[i] = serialized_pubkeys[i];
        if (!lantern_signature_sign(
                secrets[i],
                epoch,
                &message,
                &signatures[i])) {
            fprintf(stderr, "aggregate: sign failed index=%zu\n", i);
            goto fail;
        }
    }

    if (!lantern_signature_aggregate(
            pubkey_ptrs,
            signatures,
            kSignerCount,
            &message,
            epoch,
            &proof)) {
        fprintf(stderr, "aggregate: lantern_signature_aggregate failed\n");
        goto fail;
    }
    if (proof.length == 0 || !proof.data) {
        fprintf(stderr, "aggregate: empty proof\n");
        goto fail;
    }
    if (!lantern_signature_verify_aggregated(
            pubkey_ptrs,
            kSignerCount,
            &message,
            &proof,
            epoch)) {
        fprintf(stderr, "aggregate: verify_aggregated failed\n");
        goto fail;
    }

    if (!aggregated_proof_tamper_is_rejected(
            pubkey_ptrs,
            kSignerCount,
            &message,
            &proof,
            epoch)) {
        fprintf(stderr, "aggregate: tampered proof unexpectedly verified\n");
        goto fail;
    }

    for (size_t i = 0; i < kSignerCount; ++i) {
        pq_secret_key_free(secrets[i]);
        pq_public_key_free(pubkeys[i]);
    }
    lantern_byte_list_reset(&proof);
    return 0;

fail:
    for (size_t i = 0; i < kSignerCount; ++i) {
        if (secrets[i]) {
            pq_secret_key_free(secrets[i]);
        }
        if (pubkeys[i]) {
            pq_public_key_free(pubkeys[i]);
        }
    }
    lantern_byte_list_reset(&proof);
    return 1;
}

static int test_recursive_aggregated_signature_roundtrip(void) {
    enum { kSignerCount = 3 };
    struct PQSignatureSchemePublicKey *pubkeys[kSignerCount];
    struct PQSignatureSchemeSecretKey *secrets[kSignerCount];
    uint8_t serialized_pubkeys[kSignerCount][LANTERN_VALIDATOR_PUBKEY_SIZE];
    uint8_t flattened_pubkeys[kSignerCount * LANTERN_VALIDATOR_PUBKEY_SIZE];
    const uint8_t *pubkey_ptrs[kSignerCount];
    const uint8_t *child_pubkey_ptrs[2];
    const uint8_t *leaf_pubkey_ptrs[1];
    LanternSignature signatures[kSignerCount];
    LanternRoot message;
    LanternState state;
    struct lantern_bitlist child_participants;
    struct lantern_bitlist raw_participants;
    LanternAggregatedSignatureProof child_proof;
    LanternAggregatedSignatureProof child_leaf_proof;
    LanternAggregatedSignatureProof children_only_proof;
    LanternAggregatedSignatureProof single_child_rollup;
    LanternAggregatedSignatureProof mixed_proof;
    uint64_t epoch = 2;

    memset(pubkeys, 0, sizeof(pubkeys));
    memset(secrets, 0, sizeof(secrets));
    memset(serialized_pubkeys, 0, sizeof(serialized_pubkeys));
    memset(flattened_pubkeys, 0, sizeof(flattened_pubkeys));
    memset(signatures, 0, sizeof(signatures));
    fill_root(&message, 0xC4);

    lantern_state_init(&state);
    lantern_bitlist_init(&child_participants);
    lantern_bitlist_init(&raw_participants);
    lantern_aggregated_signature_proof_init(&child_proof);
    lantern_aggregated_signature_proof_init(&child_leaf_proof);
    lantern_aggregated_signature_proof_init(&children_only_proof);
    lantern_aggregated_signature_proof_init(&single_child_rollup);
    lantern_aggregated_signature_proof_init(&mixed_proof);

    for (size_t i = 0; i < kSignerCount; ++i) {
        if (generate_test_keypair(&pubkeys[i], &secrets[i]) != 0) {
            fprintf(stderr, "recursive aggregate: keygen failed index=%zu\n", i);
            goto fail;
        }

        uintptr_t written = 0;
        enum PQSigningError serr = pq_public_key_serialize(
            pubkeys[i],
            serialized_pubkeys[i],
            sizeof(serialized_pubkeys[i]),
            &written);
        if (serr != Success || written != sizeof(serialized_pubkeys[i])) {
            fprintf(
                stderr,
                "recursive aggregate: pubkey serialize failed index=%zu err=%d written=%zu\n",
                i,
                (int)serr,
                (size_t)written);
            goto fail;
        }

        memcpy(
            flattened_pubkeys + (i * LANTERN_VALIDATOR_PUBKEY_SIZE),
            serialized_pubkeys[i],
            LANTERN_VALIDATOR_PUBKEY_SIZE);
        pubkey_ptrs[i] = serialized_pubkeys[i];

        if (!lantern_signature_sign(
                secrets[i],
                epoch,
                &message,
                &signatures[i])) {
            fprintf(stderr, "recursive aggregate: sign failed index=%zu\n", i);
            goto fail;
        }
    }

    if (lantern_state_set_validator_pubkeys(&state, flattened_pubkeys, kSignerCount) != 0) {
        fprintf(stderr, "recursive aggregate: state pubkey setup failed\n");
        goto fail;
    }

    {
        const size_t child_indices[2] = {0u, 1u};
        LanternRawXmssSignature child_inputs[2] = {
            {.pubkey = serialized_pubkeys[0], .signature = &signatures[0]},
            {.pubkey = serialized_pubkeys[1], .signature = &signatures[1]},
        };

        if (!set_participants(&child_participants, 2u, child_indices, 2u)) {
            fprintf(stderr, "recursive aggregate: child participants setup failed\n");
            goto fail;
        }
        if (!lantern_aggregated_signature_proof_aggregate(
                NULL,
                &child_participants,
                NULL,
                0u,
                child_inputs,
                2u,
                &message,
                epoch,
                &child_proof)) {
            fprintf(stderr, "recursive aggregate: child proof build failed\n");
            goto fail;
        }
    }

    child_pubkey_ptrs[0] = pubkey_ptrs[0];
    child_pubkey_ptrs[1] = pubkey_ptrs[1];
    if (!lantern_signature_verify_aggregated(
            child_pubkey_ptrs,
            2u,
            &message,
            &child_proof.proof_data,
            epoch)) {
        fprintf(stderr, "recursive aggregate: child proof verification failed\n");
        goto fail;
    }

    {
        const size_t raw_indices[1] = {2u};
        LanternRawXmssSignature leaf_inputs[1] = {
            {.pubkey = serialized_pubkeys[2], .signature = &signatures[2]},
        };

        if (!set_participants(&raw_participants, 3u, raw_indices, 1u)) {
            fprintf(stderr, "recursive aggregate: raw participants setup failed\n");
            goto fail;
        }
        if (!lantern_aggregated_signature_proof_aggregate(
                NULL,
                &raw_participants,
                NULL,
                0u,
                leaf_inputs,
                1u,
                &message,
                epoch,
                &child_leaf_proof)) {
            fprintf(stderr, "recursive aggregate: leaf child proof build failed\n");
            goto fail;
        }
    }
    leaf_pubkey_ptrs[0] = pubkey_ptrs[2];
    if (!lantern_signature_verify_aggregated(
            leaf_pubkey_ptrs,
            1u,
            &message,
            &child_leaf_proof.proof_data,
            epoch)) {
        fprintf(stderr, "recursive aggregate: leaf child proof verification failed\n");
        goto fail;
    }
    if (child_leaf_proof.proof_data.length == LANTERN_SIGNATURE_SIZE) {
        fprintf(stderr, "recursive aggregate: leaf child proof was not canonicalized\n");
        goto fail;
    }

    lean_metrics_reset();

    {
        LanternAggregatedSignatureProof children_only_inputs[2] = {
            child_proof,
            child_leaf_proof,
        };

        if (!lantern_aggregated_signature_proof_aggregate(
                &state,
                NULL,
                children_only_inputs,
                2u,
                NULL,
                0u,
                &message,
                epoch,
                &children_only_proof)) {
            fprintf(stderr, "recursive aggregate: children-only proof build failed\n");
            goto fail;
        }
    }
    if (!expect_aggregated_build_metrics(1u, 3u, "children-only")) {
        goto fail;
    }
    if (children_only_proof.participants.bit_length < 3u
        || !lantern_bitlist_get(&children_only_proof.participants, 0u)
        || !lantern_bitlist_get(&children_only_proof.participants, 1u)
        || !lantern_bitlist_get(&children_only_proof.participants, 2u)) {
        fprintf(stderr, "recursive aggregate: children-only proof participants missing contributors\n");
        goto fail;
    }
    if (!lantern_signature_verify_aggregated(
            pubkey_ptrs,
            kSignerCount,
            &message,
            &children_only_proof.proof_data,
            epoch)) {
        fprintf(stderr, "recursive aggregate: children-only proof verification failed\n");
        goto fail;
    }

    if (!lantern_aggregated_signature_proof_aggregate(
            &state,
            NULL,
            &child_proof,
            1u,
            NULL,
            0u,
            &message,
            epoch,
            &single_child_rollup)) {
        fprintf(stderr, "recursive aggregate: single-child rollup failed\n");
        goto fail;
    }
    if (!expect_aggregated_build_metrics(1u, 3u, "single-child rollup")) {
        goto fail;
    }
    if (single_child_rollup.proof_data.length != child_proof.proof_data.length
        || !single_child_rollup.proof_data.data
        || memcmp(
               single_child_rollup.proof_data.data,
               child_proof.proof_data.data,
               child_proof.proof_data.length)
            != 0) {
        fprintf(stderr, "recursive aggregate: single-child rollup did not preserve proof bytes\n");
        goto fail;
    }
    if (!lantern_signature_verify_aggregated(
            child_pubkey_ptrs,
            2u,
            &message,
            &single_child_rollup.proof_data,
            epoch)) {
        fprintf(stderr, "recursive aggregate: single-child rollup verification failed\n");
        goto fail;
    }

    {
        LanternRawXmssSignature mixed_inputs[1] = {
            {.pubkey = serialized_pubkeys[2], .signature = &signatures[2]},
        };

        if (!lantern_aggregated_signature_proof_aggregate(
                &state,
                &raw_participants,
                &child_proof,
                1u,
                mixed_inputs,
                1u,
                &message,
                epoch,
                &mixed_proof)) {
            fprintf(stderr, "recursive aggregate: mixed proof build failed\n");
            goto fail;
        }
    }
    if (!expect_aggregated_build_metrics(2u, 6u, "mixed")) {
        goto fail;
    }

    if (mixed_proof.participants.bit_length < 3u
        || !lantern_bitlist_get(&mixed_proof.participants, 0u)
        || !lantern_bitlist_get(&mixed_proof.participants, 1u)
        || !lantern_bitlist_get(&mixed_proof.participants, 2u)) {
        fprintf(stderr, "recursive aggregate: mixed proof participants missing contributors\n");
        goto fail;
    }
    if (!lantern_signature_verify_aggregated(
            pubkey_ptrs,
            kSignerCount,
            &message,
            &mixed_proof.proof_data,
            epoch)) {
        fprintf(stderr, "recursive aggregate: mixed proof verification failed\n");
        goto fail;
    }

    for (size_t i = 0; i < kSignerCount; ++i) {
        pq_secret_key_free(secrets[i]);
        pq_public_key_free(pubkeys[i]);
    }
    lantern_aggregated_signature_proof_reset(&mixed_proof);
    lantern_aggregated_signature_proof_reset(&single_child_rollup);
    lantern_aggregated_signature_proof_reset(&children_only_proof);
    lantern_aggregated_signature_proof_reset(&child_leaf_proof);
    lantern_aggregated_signature_proof_reset(&child_proof);
    lantern_bitlist_reset(&raw_participants);
    lantern_bitlist_reset(&child_participants);
    lantern_state_reset(&state);
    return 0;

fail:
    for (size_t i = 0; i < kSignerCount; ++i) {
        if (secrets[i]) {
            pq_secret_key_free(secrets[i]);
        }
        if (pubkeys[i]) {
            pq_public_key_free(pubkeys[i]);
        }
    }
    lantern_aggregated_signature_proof_reset(&mixed_proof);
    lantern_aggregated_signature_proof_reset(&single_child_rollup);
    lantern_aggregated_signature_proof_reset(&children_only_proof);
    lantern_aggregated_signature_proof_reset(&child_leaf_proof);
    lantern_aggregated_signature_proof_reset(&child_proof);
    lantern_bitlist_reset(&raw_participants);
    lantern_bitlist_reset(&child_participants);
    lantern_state_reset(&state);
    return 1;
}

static int test_signature_helpers(void) {
    LanternSignature signature;
    memset(&signature, 0xA5, sizeof(signature));
    if (lantern_signature_is_zero(&signature)) {
        fprintf(stderr, "signature helper test expected non-zero signature\n");
        return 1;
    }
    lantern_signature_zero(&signature);
    if (!lantern_signature_is_zero(&signature)) {
        fprintf(stderr, "signature helper test expected zero signature\n");
        return 1;
    }
    return 0;
}

int main(void) {
    if (test_signature_helpers() != 0) {
        return 1;
    }
    if (test_proposer_vote_signature_roundtrip() != 0) {
        return 1;
    }
    if (test_proposer_vote_signature_rejects_tampering() != 0) {
        return 1;
    }
    if (test_aggregated_signature_roundtrip() != 0) {
        return 1;
    }
    if (test_recursive_aggregated_signature_roundtrip() != 0) {
        return 1;
    }
    puts("lantern_signature_test OK");
    return 0;
}
