#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../../src/core/client_services_internal.h"
#include "client_test_helpers.h"
#include "lantern/consensus/hash.h"
#include "lantern/consensus/signature.h"
#include "lantern/core/client.h"
#include "lantern/support/string_list.h"
#include "src/protocol/gossipsub/core/gossipsub_internal.h"

static void reset_agg_cache(struct lantern_client *client)
{
    if (!client) {
        return;
    }
    lantern_store_reset(&client->store);
}

static peer_id_t *test_peer_id_from_text(const char *text)
{
    peer_id_t *peer = NULL;
    if (peer_id_new_from_text(text, &peer) != PEER_ID_OK) {
        return NULL;
    }
    return peer;
}

static int test_gossipsub_mesh_peer_count_includes_effective_peers(void)
{
    static const char topic_name[] = "/lean/test/beacon_block/ssz_snappy";
    peer_id_t *explicit_peer = test_peer_id_from_text(
        "12D3KooWL9qw9QdCsiPUQXGWxZhwivKar35CFYuU9B9kavHuV2XZ");
    peer_id_t *subscribed_peer = test_peer_id_from_text(
        "12D3KooWQ7W3zfBDSSY5YTbSsfXCMVvjJAnYXhYzu3PV6PvJkU8E");
    if (!explicit_peer || !subscribed_peer) {
        fprintf(stderr, "failed to build peer ids for mesh metric test\n");
        peer_id_free(explicit_peer);
        peer_id_free(subscribed_peer);
        return 1;
    }

    libp2p_gossipsub_t gs;
    memset(&gs, 0, sizeof(gs));
    if (pthread_mutex_init(&gs.lock, NULL) != 0) {
        peer_id_free(explicit_peer);
        peer_id_free(subscribed_peer);
        return 1;
    }

    gossipsub_topic_state_t topic;
    memset(&topic, 0, sizeof(topic));
    topic.name = (char *)topic_name;
    topic.subscribed = 1;
    gs.topics = &topic;

    gossipsub_peer_topic_t peer_topic;
    memset(&peer_topic, 0, sizeof(peer_topic));
    peer_topic.name = (char *)topic_name;

    gossipsub_peer_entry_t explicit_entry;
    memset(&explicit_entry, 0, sizeof(explicit_entry));
    explicit_entry.peer = explicit_peer;
    explicit_entry.connected = 1;
    explicit_entry.explicit_peering = 1;

    gossipsub_peer_entry_t subscribed_entry;
    memset(&subscribed_entry, 0, sizeof(subscribed_entry));
    subscribed_entry.peer = subscribed_peer;
    subscribed_entry.connected = 1;
    subscribed_entry.topics = &peer_topic;
    explicit_entry.next = &subscribed_entry;
    gs.peers = &explicit_entry;

    gossipsub_mesh_member_t duplicate_mesh_member;
    memset(&duplicate_mesh_member, 0, sizeof(duplicate_mesh_member));
    duplicate_mesh_member.peer = subscribed_peer;
    duplicate_mesh_member.peer_entry = &subscribed_entry;
    topic.mesh = &duplicate_mesh_member;
    topic.mesh_size = 1u;

    struct lantern_gossipsub_service service;
    memset(&service, 0, sizeof(service));
    service.gossipsub = &gs;

    size_t count = lantern_gossipsub_service_mesh_peer_count(&service);
    pthread_mutex_destroy(&gs.lock);
    peer_id_free(explicit_peer);
    peer_id_free(subscribed_peer);

    if (count != 2u) {
        fprintf(stderr, "expected effective mesh peer count 2, got %zu\n", count);
        return 1;
    }
    return 0;
}

static int test_enable_blocks_request_peer(
    struct lantern_client *client,
    const char *peer_id)
{
    if (!client || !peer_id || peer_id[0] == '\0') {
        return -1;
    }

    lantern_string_list_init(&client->connected_peer_ids);
    if (pthread_mutex_init(&client->connection_lock, NULL) != 0) {
        return -1;
    }
    client->connection_lock_initialized = true;

    if (pthread_mutex_init(&client->status_lock, NULL) != 0) {
        pthread_mutex_destroy(&client->connection_lock);
        client->connection_lock_initialized = false;
        lantern_string_list_reset(&client->connected_peer_ids);
        return -1;
    }
    client->status_lock_initialized = true;

    if (lantern_string_list_append(&client->connected_peer_ids, peer_id) != 0) {
        pthread_mutex_destroy(&client->status_lock);
        client->status_lock_initialized = false;
        pthread_mutex_destroy(&client->connection_lock);
        client->connection_lock_initialized = false;
        lantern_string_list_reset(&client->connected_peer_ids);
        return -1;
    }
    client->connected_peers = 1u;

    client->peer_status_entries = calloc(1u, sizeof(*client->peer_status_entries));
    if (!client->peer_status_entries) {
        client->connected_peers = 0u;
        lantern_string_list_reset(&client->connected_peer_ids);
        pthread_mutex_destroy(&client->status_lock);
        client->status_lock_initialized = false;
        pthread_mutex_destroy(&client->connection_lock);
        client->connection_lock_initialized = false;
        return -1;
    }
    client->peer_status_count = 1u;
    client->peer_status_capacity = 1u;
    strncpy(
        client->peer_status_entries[0].peer_id,
        peer_id,
        sizeof(client->peer_status_entries[0].peer_id) - 1u);
    client->peer_status_entries[0].peer_id[sizeof(client->peer_status_entries[0].peer_id) - 1u] =
        '\0';

    return 0;
}

static void test_disable_blocks_request_peer(struct lantern_client *client)
{
    if (!client) {
        return;
    }

    free(client->peer_status_entries);
    client->peer_status_entries = NULL;
    client->peer_status_count = 0u;
    client->peer_status_capacity = 0u;

    free(client->active_blocks_requests);
    client->active_blocks_requests = NULL;
    client->active_blocks_request_count = 0u;
    client->active_blocks_request_capacity = 0u;
    client->next_blocks_request_id = 0u;

    if (client->status_lock_initialized) {
        pthread_mutex_destroy(&client->status_lock);
        client->status_lock_initialized = false;
    }

    if (client->connection_lock_initialized) {
        pthread_mutex_destroy(&client->connection_lock);
        client->connection_lock_initialized = false;
    }

    lantern_string_list_reset(&client->connected_peer_ids);
    client->connected_peers = 0u;
}

static int sign_single_participant_aggregated_attestation(
    struct lantern_client *client,
    struct PQSignatureSchemeSecretKey *secret,
    const LanternAttestationData *data,
    LanternSignedAggregatedAttestation *out_attestation)
{
    if (!client || !secret || !data || !out_attestation) {
        return -1;
    }

    LanternSignedVote vote;
    memset(&vote, 0, sizeof(vote));
    vote.data.validator_id = 0u;
    vote.data.data = *data;
    if (client_test_sign_vote_with_secret(&vote, secret) != 0) {
        return -1;
    }

    lantern_signed_aggregated_attestation_init(out_attestation);
    out_attestation->data = *data;
    if (lantern_bitlist_resize(&out_attestation->proof.participants, 1u) != 0
        || lantern_bitlist_set(&out_attestation->proof.participants, 0u, true) != 0) {
        lantern_signed_aggregated_attestation_reset(out_attestation);
        return -1;
    }

    const uint8_t *validator_pubkey = lantern_state_validator_attestation_pubkey(&client->state, 0u);
    if (!validator_pubkey) {
        lantern_signed_aggregated_attestation_reset(out_attestation);
        return -1;
    }

    LanternRoot data_root;
    if (lantern_hash_tree_root_attestation_data(&out_attestation->data, &data_root) != SSZ_SUCCESS) {
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

    LanternAttestationData data;
    memset(&data, 0, sizeof(data));
    uint64_t child_slot = 0;
    if (client_test_slot_for_root(client, child_root, &child_slot) != 0) {
        return -1;
    }

    data.slot = child_slot;
    data.head.slot = child_slot;
    data.head.root = *child_root;
    LanternRoot state_root;
    if (lantern_hash_tree_root_state(&client->state, &state_root) != SSZ_SUCCESS) {
        return -1;
    }
    LanternBlockHeader checkpoint_header = client->state.latest_block_header;
    checkpoint_header.state_root = state_root;
    LanternRoot checkpoint_root;
    if (lantern_hash_tree_root_block_header(&checkpoint_header, &checkpoint_root) != SSZ_SUCCESS) {
        return -1;
    }
    /*
     * Gossip verification resolves pubkeys via state lookup by target root.
     * Use the client's current state header root so the lookup path is valid.
     */
    data.target.slot = checkpoint_header.slot;
    data.target.root = checkpoint_root;
    data.source.slot = checkpoint_header.slot;
    data.source.root = checkpoint_root;

    return sign_single_participant_aggregated_attestation(client, secret, &data, out_attestation);
}

static bool make_aggregated_proof_invalid(
    const uint8_t *const *pubkeys,
    size_t count,
    const LanternRoot *message,
    LanternByteList *proof,
    uint64_t epoch)
{
    LanternByteList tampered;
    size_t candidate_count = 0u;
    size_t candidates[4];

    if (!pubkeys || !message || !proof || proof->length == 0u || !proof->data) {
        return false;
    }

    lantern_byte_list_init(&tampered);
    if (lantern_byte_list_copy(&tampered, proof) != 0 || tampered.length == 0u || !tampered.data) {
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
            lantern_byte_list_reset(proof);
            *proof = tampered;
            return true;
        }
        tampered.data[offset] ^= 0xFFu;
    }

    if (tampered.length > 1u
        && lantern_byte_list_resize(&tampered, tampered.length - 1u) == 0
        && !lantern_signature_verify_aggregated(pubkeys, count, message, &tampered, epoch)) {
        lantern_byte_list_reset(proof);
        *proof = tampered;
        return true;
    }

    lantern_byte_list_reset(&tampered);
    return false;
}

static int test_idle_gossip_not_ignored(void)
{
    struct lantern_client client;
    memset(&client, 0, sizeof(client));
    client.node_id = "test_idle_gossip";
    client.sync_state = LANTERN_SYNC_STATE_IDLE;

    LanternSignedBlock block;
    memset(&block, 0, sizeof(block));
    lantern_block_body_init(&block.block.body);
    block.block.slot = 1;

    int block_rc = lantern_client_debug_gossip_block(&client, &block);
    lantern_block_body_reset(&block.block.body);
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
    if (lantern_hash_tree_root_attestation_data(&attestation.data, &data_root) != SSZ_SUCCESS) {
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
    LanternRoot data_root;
    const uint8_t *validator_pubkey = NULL;
    const uint8_t *pubkeys[1] = {0};
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
    validator_pubkey = lantern_state_validator_attestation_pubkey(&client.state, 0u);
    if (!validator_pubkey) {
        fprintf(stderr, "aggregated attestation validator pubkey missing\n");
        goto cleanup_attestation;
    }
    if (lantern_hash_tree_root_attestation_data(&attestation.data, &data_root) != SSZ_SUCCESS) {
        fprintf(stderr, "failed to hash aggregated attestation data root\n");
        goto cleanup_attestation;
    }
    pubkeys[0] = validator_pubkey;
    if (!make_aggregated_proof_invalid(
            pubkeys,
            1u,
            &data_root,
            &attestation.proof.proof_data,
            attestation.data.slot)) {
        fprintf(stderr, "failed to invalidate aggregated attestation proof fixture\n");
        goto cleanup_attestation;
    }
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
    if (test_enable_blocks_request_peer(
            &client,
            "12D3KooWQH2VQK1kF2L8a7T4AtestAggUnknownTarget111111111111")
        != 0) {
        fprintf(stderr, "failed to set up schedulable peer for aggregated gossip test\n");
        goto cleanup;
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
    if (client.next_blocks_request_id != 0u) {
        fprintf(stderr, "unknown-target aggregated attestation should not schedule block requests\n");
        goto cleanup_attestation;
    }

    rc = 0;

cleanup_attestation:
    lantern_signed_aggregated_attestation_reset(&attestation);
cleanup:
    test_disable_blocks_request_peer(&client);
    reset_agg_cache(&client);
    client_test_teardown_vote_validation_client(&client, pub, secret);
    return rc;
}

static int test_gossip_aggregated_attestation_rejects_invalid_topology(void)
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
            "gossip_agg_invalid_topology",
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
        fprintf(stderr, "failed to build base aggregated attestation fixture\n");
        goto cleanup;
    }

    LanternAttestationData invalid_data = attestation.data;
    lantern_signed_aggregated_attestation_reset(&attestation);
    memset(&attestation, 0, sizeof(attestation));
    invalid_data.head.slot = 0u;
    invalid_data.head.root = anchor_root;

    if (sign_single_participant_aggregated_attestation(
            &client,
            secret,
            &invalid_data,
            &attestation)
        != 0) {
        fprintf(stderr, "failed to build invalid-topology aggregated attestation fixture\n");
        goto cleanup;
    }

    if (lantern_client_debug_gossip_aggregated_attestation(&client, &attestation) != LANTERN_CLIENT_ERR_IGNORED) {
        fprintf(stderr, "invalid-topology aggregated attestation gossip should be ignored\n");
        goto cleanup_attestation;
    }
    if (client.store.new_aggregated_payloads.length != 0
        || client.store.known_aggregated_payloads.length != 0) {
        fprintf(stderr, "invalid-topology aggregated attestation should not be cached\n");
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
    if (test_gossipsub_mesh_peer_count_includes_effective_peers() != 0)
    {
        return 1;
    }
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
    if (test_gossip_aggregated_attestation_rejects_invalid_topology() != 0)
    {
        return 1;
    }

    puts("lantern_client_gossip_test OK");
    return 0;
}
