#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "client_test_helpers.h"
#include "lantern/consensus/hash.h"
#include "lantern/consensus/signature.h"
#include "lantern/core/client.h"

static void reset_agg_cache(struct lantern_client *client)
{
    if (!client) {
        return;
    }
    lantern_store_reset(&client->store);
}

static int build_single_participant_aggregated_attestation(
    struct lantern_client *client,
    struct PQSignatureSchemeSecretKey *secret,
    const LanternRoot *anchor_root,
    const LanternRoot *child_root,
    LanternSignedAggregatedAttestation *out_attestation)
{
    if (!client || !secret || !anchor_root || !child_root || !out_attestation) {
        return -1;
    }

    LanternSignedVote vote;
    memset(&vote, 0, sizeof(vote));
    uint64_t child_slot = 0;
    if (client_test_slot_for_root(client, child_root, &child_slot) != 0) {
        return -1;
    }

    vote.data.validator_id = 0u;
    vote.data.slot = child_slot;
    vote.data.head.slot = child_slot;
    vote.data.head.root = *child_root;
    LanternRoot state_root;
    if (lantern_hash_tree_root_state(&client->state, &state_root) != 0) {
        return -1;
    }
    LanternBlockHeader checkpoint_header = client->state.latest_block_header;
    checkpoint_header.state_root = state_root;
    LanternRoot checkpoint_root;
    if (lantern_hash_tree_root_block_header(&checkpoint_header, &checkpoint_root) != 0) {
        return -1;
    }
    /*
     * Gossip verification resolves pubkeys via state lookup by target root.
     * Use the client's current state header root so the lookup path is valid.
     */
    vote.data.target.slot = checkpoint_header.slot;
    vote.data.target.root = checkpoint_root;
    vote.data.source.slot = checkpoint_header.slot;
    vote.data.source.root = checkpoint_root;
    if (client_test_sign_vote_with_secret(&vote, secret) != 0) {
        return -1;
    }

    lantern_signed_aggregated_attestation_init(out_attestation);
    out_attestation->data = vote.data.data;
    if (lantern_bitlist_resize(&out_attestation->proof.participants, 1u) != 0
        || lantern_bitlist_set(&out_attestation->proof.participants, 0u, true) != 0) {
        lantern_signed_aggregated_attestation_reset(out_attestation);
        return -1;
    }

    const uint8_t *validator_pubkey = lantern_state_validator_pubkey(&client->state, 0u);
    if (!validator_pubkey) {
        lantern_signed_aggregated_attestation_reset(out_attestation);
        return -1;
    }

    LanternRoot data_root;
    if (lantern_hash_tree_root_attestation_data(&out_attestation->data, &data_root) != 0) {
        lantern_signed_aggregated_attestation_reset(out_attestation);
        return -1;
    }

    const uint8_t *pubkeys[1] = {validator_pubkey};
    LanternSignature signatures[1] = {vote.signature};
    if (!lantern_signature_aggregate(
            pubkeys,
            signatures,
            1u,
            &data_root,
            out_attestation->data.slot,
            &out_attestation->proof.proof_data)) {
        lantern_signed_aggregated_attestation_reset(out_attestation);
        return -1;
    }
    if (!lantern_signature_verify_aggregated(
            pubkeys,
            1u,
            &data_root,
            &out_attestation->proof.proof_data,
            out_attestation->data.slot)) {
        lantern_signed_aggregated_attestation_reset(out_attestation);
        return -1;
    }

    return 0;
}

static int test_idle_gossip_not_ignored(void)
{
    struct lantern_client client;
    memset(&client, 0, sizeof(client));
    client.node_id = "test_idle_gossip";
    client.sync_state = LANTERN_SYNC_STATE_IDLE;

    LanternSignedBlock block;
    memset(&block, 0, sizeof(block));
    lantern_block_body_init(&block.message.body);
    block.message.slot = 1;

    int block_rc = lantern_client_debug_gossip_block(&client, &block);
    lantern_block_body_reset(&block.message.body);
    if (block_rc != LANTERN_CLIENT_OK)
    {
        fprintf(stderr, "idle block gossip was not accepted rc=%d\n", block_rc);
        return 1;
    }

    LanternSignedVote vote;
    memset(&vote, 0, sizeof(vote));
    vote.data.validator_id = 0;
    vote.data.slot = 1;

    int vote_rc = lantern_client_debug_gossip_vote(&client, &vote);
    if (vote_rc != LANTERN_CLIENT_OK)
    {
        fprintf(stderr, "idle vote gossip was not accepted rc=%d\n", vote_rc);
        return 1;
    }

    return 0;
}

static int test_gossip_aggregated_attestation_caches_valid_proof(void)
{
    struct lantern_client client;
    struct PQSignatureSchemePublicKey *pub = NULL;
    struct PQSignatureSchemeSecretKey *secret = NULL;
    LanternRoot anchor_root;
    LanternRoot child_root;
    LanternSignedAggregatedAttestation attestation;
    int rc = 1;

    if (client_test_setup_vote_validation_client(
            &client,
            "gossip_agg_valid",
            &pub,
            &secret,
            &anchor_root,
            &child_root)
        != 0) {
        return 1;
    }

    if (build_single_participant_aggregated_attestation(
            &client,
            secret,
            &anchor_root,
            &child_root,
            &attestation)
        != 0) {
        fprintf(stderr, "failed to build valid aggregated attestation fixture\n");
        goto cleanup;
    }

    int gossip_rc = lantern_client_debug_gossip_aggregated_attestation(&client, &attestation);
    if (gossip_rc != LANTERN_CLIENT_OK) {
        fprintf(stderr, "valid aggregated attestation gossip should be accepted rc=%d\n", gossip_rc);
        goto cleanup_attestation;
    }
    if (client.store.new_aggregated_payloads.length != 1
        || !client.store.new_aggregated_payloads.entries) {
        fprintf(stderr, "valid aggregated attestation should be cached\n");
        goto cleanup_attestation;
    }
    if (client.store.known_aggregated_payloads.length != 0) {
        fprintf(stderr, "valid aggregated attestation should remain pending until migration\n");
        goto cleanup_attestation;
    }
    if (client.fork_choice.new_aggregated_payloads != &client.store.new_aggregated_payloads
        || client.fork_choice.known_aggregated_payloads != &client.store.known_aggregated_payloads
        || client.fork_choice.attestation_data_by_root != &client.store.attestation_data_by_root) {
        fprintf(stderr, "fork choice should expose attached aggregated attestation store views\n");
        goto cleanup_attestation;
    }

    LanternRoot data_root;
    if (lantern_hash_tree_root_attestation_data(&attestation.data, &data_root) != 0) {
        fprintf(stderr, "failed to hash attestation data root\n");
        goto cleanup_attestation;
    }
    if (memcmp(
            client.store.new_aggregated_payloads.entries[0].data_root.bytes,
            data_root.bytes,
            LANTERN_ROOT_SIZE)
        != 0) {
        fprintf(stderr, "cached aggregated proof root mismatch\n");
        goto cleanup_attestation;
    }
    if (client.store.new_aggregated_payloads.entries[0].target_slot != attestation.data.target.slot) {
        fprintf(stderr, "cached aggregated proof target slot mismatch\n");
        goto cleanup_attestation;
    }
    if (!client.fork_choice.new_aggregated_payloads
        || client.fork_choice.new_aggregated_payloads->length != 1
        || !client.fork_choice.new_aggregated_payloads->entries) {
        fprintf(stderr, "fork choice new aggregated payload pool missing gossip proof\n");
        goto cleanup_attestation;
    }
    if (!client.fork_choice.attestation_data_by_root
        || client.fork_choice.attestation_data_by_root->length != 1
        || !client.fork_choice.attestation_data_by_root->entries) {
        fprintf(stderr, "fork choice attestation data map missing gossip attestation data\n");
        goto cleanup_attestation;
    }
    if (memcmp(
            client.fork_choice.new_aggregated_payloads->entries[0].data_root.bytes,
            data_root.bytes,
            LANTERN_ROOT_SIZE)
        != 0) {
        fprintf(stderr, "fork choice aggregated payload root mismatch\n");
        goto cleanup_attestation;
    }
    if (memcmp(
            client.fork_choice.attestation_data_by_root->entries[0].data_root.bytes,
            data_root.bytes,
            LANTERN_ROOT_SIZE)
        != 0) {
        fprintf(stderr, "fork choice attestation data root mismatch\n");
        goto cleanup_attestation;
    }
    if (client.fork_choice.attestation_data_by_root->entries[0].data.target.slot
        != attestation.data.target.slot) {
        fprintf(stderr, "fork choice attestation data target slot mismatch\n");
        goto cleanup_attestation;
    }

    rc = 0;

cleanup_attestation:
    lantern_signed_aggregated_attestation_reset(&attestation);
cleanup:
    reset_agg_cache(&client);
    client_test_teardown_vote_validation_client(&client, pub, secret);
    return rc;
}

static int test_gossip_aggregated_attestation_rejects_invalid_proof(void)
{
    struct lantern_client client;
    struct PQSignatureSchemePublicKey *pub = NULL;
    struct PQSignatureSchemeSecretKey *secret = NULL;
    LanternRoot anchor_root;
    LanternRoot child_root;
    LanternSignedAggregatedAttestation attestation;
    int rc = 1;

    if (client_test_setup_vote_validation_client(
            &client,
            "gossip_agg_invalid",
            &pub,
            &secret,
            &anchor_root,
            &child_root)
        != 0) {
        return 1;
    }

    if (build_single_participant_aggregated_attestation(
            &client,
            secret,
            &anchor_root,
            &child_root,
            &attestation)
        != 0) {
        fprintf(stderr, "failed to build aggregated attestation fixture\n");
        goto cleanup;
    }

    if (attestation.proof.proof_data.length == 0 || !attestation.proof.proof_data.data) {
        fprintf(stderr, "aggregated attestation proof unexpectedly empty\n");
        goto cleanup_attestation;
    }
    attestation.proof.proof_data.data[0] ^= 0xA5u;
    if (lantern_client_debug_gossip_aggregated_attestation(&client, &attestation) != LANTERN_CLIENT_ERR_IGNORED) {
        fprintf(stderr, "invalid aggregated attestation gossip should be ignored\n");
        goto cleanup_attestation;
    }
    if (client.store.new_aggregated_payloads.length != 0
        || client.store.known_aggregated_payloads.length != 0) {
        fprintf(stderr, "invalid aggregated attestation should not be cached\n");
        goto cleanup_attestation;
    }

    rc = 0;

cleanup_attestation:
    lantern_signed_aggregated_attestation_reset(&attestation);
cleanup:
    reset_agg_cache(&client);
    client_test_teardown_vote_validation_client(&client, pub, secret);
    return rc;
}

static int test_gossip_aggregated_attestation_rejects_unknown_target(void)
{
    struct lantern_client client;
    struct PQSignatureSchemePublicKey *pub = NULL;
    struct PQSignatureSchemeSecretKey *secret = NULL;
    LanternRoot anchor_root;
    LanternRoot child_root;
    LanternSignedAggregatedAttestation attestation;
    int rc = 1;

    if (client_test_setup_vote_validation_client(
            &client,
            "gossip_agg_unknown_target",
            &pub,
            &secret,
            &anchor_root,
            &child_root)
        != 0) {
        return 1;
    }

    if (build_single_participant_aggregated_attestation(
            &client,
            secret,
            &anchor_root,
            &child_root,
            &attestation)
        != 0) {
        fprintf(stderr, "failed to build aggregated attestation fixture\n");
        goto cleanup;
    }

    client_test_fill_root_with_index(&attestation.data.target.root, 0xBEEFu);
    if (lantern_client_debug_gossip_aggregated_attestation(&client, &attestation) != LANTERN_CLIENT_ERR_IGNORED) {
        fprintf(stderr, "aggregated attestation with unknown target should be ignored\n");
        goto cleanup_attestation;
    }
    if (client.store.new_aggregated_payloads.length != 0
        || client.store.known_aggregated_payloads.length != 0) {
        fprintf(stderr, "unknown-target aggregated attestation should not be cached\n");
        goto cleanup_attestation;
    }

    rc = 0;

cleanup_attestation:
    lantern_signed_aggregated_attestation_reset(&attestation);
cleanup:
    reset_agg_cache(&client);
    client_test_teardown_vote_validation_client(&client, pub, secret);
    return rc;
}

int main(void)
{
    if (test_idle_gossip_not_ignored() != 0)
    {
        return 1;
    }
    if (test_gossip_aggregated_attestation_caches_valid_proof() != 0)
    {
        return 1;
    }
    if (test_gossip_aggregated_attestation_rejects_invalid_proof() != 0)
    {
        return 1;
    }
    if (test_gossip_aggregated_attestation_rejects_unknown_target() != 0)
    {
        return 1;
    }

    puts("lantern_client_gossip_test OK");
    return 0;
}
