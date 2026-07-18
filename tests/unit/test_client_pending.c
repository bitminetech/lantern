#include <pthread.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "client_test_helpers.h"
#include "../../src/core/client_network_internal.h"
#include "../../src/core/client_services_internal.h"
#include "../../src/core/client_sync_internal.h"
#include "lantern/consensus/hash.h"
#include "lantern/consensus/signature.h"
#include "lantern/consensus/state.h"
#include "lantern/consensus/ssz.h"
#include "lantern/genesis/genesis.h"
#include "lantern/storage/storage.h"
#include "lantern/support/string_list.h"

enum {
    TEST_TEMP_PATH_CAPACITY = 1024
};

struct block_signature_fixture {
    struct lantern_client client;
    struct PQSignatureSchemePublicKey *pub;
    struct PQSignatureSchemeSecretKey *secret;
    LanternValidator *validators;
    char data_dir_template[TEST_TEMP_PATH_CAPACITY];
};

static int enable_signature_verification_keys(
    struct lantern_client *client,
    LanternValidator **out_validators)
{
    if (!client || !out_validators) {
        return -1;
    }
    size_t validator_count = client->state.validators ? client->state.validator_count : 0u;
    if (validator_count == 0) {
        return -1;
    }
    if (validator_count > SIZE_MAX / sizeof(LanternValidator)) {
        return -1;
    }
    LanternValidator *validators = malloc(validator_count * sizeof(*validators));
    if (!validators) {
        return -1;
    }
    for (size_t i = 0; i < validator_count; ++i) {
        const uint8_t *attestation = client->state.validators[i].attestation_pubkey;
        const uint8_t *proposal = client->state.validators[i].proposal_pubkey;
        memcpy(validators[i].attestation_pubkey, attestation, LANTERN_VALIDATOR_PUBKEY_SIZE);
        memcpy(validators[i].proposal_pubkey, proposal, LANTERN_VALIDATOR_PUBKEY_SIZE);
        validators[i].index = i;
    }
    client->genesis.chain_config.validator_count = validator_count;
    client->genesis.chain_config.validators = validators;
    *out_validators = validators;
    return 0;
}

static void disable_signature_verification_keys(
    struct lantern_client *client,
    LanternValidator **validators)
{
    if (!client || !validators) {
        return;
    }
    free(*validators);
    *validators = NULL;
    client->genesis.chain_config.validator_count = 0;
    client->genesis.chain_config.validators = NULL;
}

static int build_devnet5_block_proof(
    struct block_signature_fixture *fixture,
    const LanternState *state,
    LanternSignedBlock *block,
    const LanternRoot *block_root,
    const struct lantern_aggregated_payload_pool *attestation_payloads,
    const LanternSignature *proposer_signature)
{
    if (!fixture || !state || !block || !block_root || !attestation_payloads
        || !proposer_signature) {
        return -1;
    }

    int rc = -1;
    LanternAggregatedSignatureProof proposer_proof;
    struct lantern_bitlist proposer_participants;
    lantern_aggregated_signature_proof_init(&proposer_proof);
    lantern_bitlist_init(&proposer_participants);

    size_t proposer_index = (size_t)block->block.proposer_index;
    if (!state->validators || proposer_index >= state->validator_count) {
        goto cleanup;
    }
    const uint8_t *proposer_pubkey = state->validators[proposer_index].proposal_pubkey;
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
            block->block.slot,
            &proposer_proof)) {
        goto cleanup;
    }
    if (!lantern_signature_merge_block_type2_proof(
            state,
            &block->block,
            attestation_payloads,
            &proposer_proof,
            &block->proof)) {
        goto cleanup;
    }

    rc = 0;

cleanup:
    lantern_bitlist_reset(&proposer_participants);
    lantern_aggregated_signature_proof_reset(&proposer_proof);
    return rc;
}

static int setup_block_signature_fixture(
    struct block_signature_fixture *fixture,
    const char *node_id)
{
    if (!fixture) {
        return -1;
    }
    memset(fixture, 0, sizeof(*fixture));
    if (client_test_setup_vote_validation_client(
            &fixture->client,
            node_id,
            &fixture->pub,
            &fixture->secret,
            NULL,
            NULL)
        != 0) {
        return -1;
    }
    if (enable_signature_verification_keys(&fixture->client, &fixture->validators) != 0) {
        client_test_teardown_vote_validation_client(&fixture->client, fixture->pub, fixture->secret);
        fixture->pub = NULL;
        fixture->secret = NULL;
        return -1;
    }
    snprintf(
        fixture->data_dir_template,
        sizeof(fixture->data_dir_template),
        "/tmp/lantern_block_sig_XXXXXX");
    fixture->client.data_dir = mkdtemp(fixture->data_dir_template);
    if (!fixture->client.data_dir
        || lantern_storage_open(&fixture->client.storage, fixture->client.data_dir) != 0) {
        disable_signature_verification_keys(&fixture->client, &fixture->validators);
        client_test_teardown_vote_validation_client(&fixture->client, fixture->pub, fixture->secret);
        fixture->pub = NULL;
        fixture->secret = NULL;
        return -1;
    }
    return 0;
}

static void teardown_block_signature_fixture(struct block_signature_fixture *fixture)
{
    if (!fixture) {
        return;
    }
    disable_signature_verification_keys(&fixture->client, &fixture->validators);
    lantern_storage_close(&fixture->client.storage);
    if (fixture->client.data_dir && fixture->client.data_dir[0] != '\0') {
        char cleanup_cmd[TEST_TEMP_PATH_CAPACITY + 16];
        int written = snprintf(cleanup_cmd, sizeof(cleanup_cmd), "rm -rf %s", fixture->client.data_dir);
        if (written > 0 && (size_t)written < sizeof(cleanup_cmd)) {
            if (system(cleanup_cmd) == -1) {
                fprintf(stderr, "failed to remove temp data dir %s\n", fixture->client.data_dir);
            }
        }
    }
    fixture->client.data_dir = NULL;
    client_test_teardown_vote_validation_client(&fixture->client, fixture->pub, fixture->secret);
    fixture->pub = NULL;
    fixture->secret = NULL;
}

static int enable_sync_test_peer(struct lantern_client *client, const char *peer_id)
{
    if (!client || !peer_id) {
        return -1;
    }
    if (pthread_mutex_init(&client->pending_lock, NULL) != 0) {
        return -1;
    }
    client->pending_lock_initialized = true;
    lantern_client_debug_pending_reset(client);
    if (pthread_mutex_init(&client->status_lock, NULL) != 0) {
        pthread_mutex_destroy(&client->pending_lock);
        client->pending_lock_initialized = false;
        return -1;
    }
    client->status_lock_initialized = true;
    if (pthread_mutex_init(&client->connection_lock, NULL) != 0) {
        pthread_mutex_destroy(&client->status_lock);
        client->status_lock_initialized = false;
        pthread_mutex_destroy(&client->pending_lock);
        client->pending_lock_initialized = false;
        return -1;
    }
    client->connection_lock_initialized = true;
    if (client_test_set_connected_peer(client, peer_id) != 0) {
        pthread_mutex_destroy(&client->connection_lock);
        client->connection_lock_initialized = false;
        pthread_mutex_destroy(&client->status_lock);
        client->status_lock_initialized = false;
        pthread_mutex_destroy(&client->pending_lock);
        client->pending_lock_initialized = false;
        return -1;
    }
    return 0;
}

static int test_state_latest_block_root(const LanternState *state, LanternRoot *out_root)
{
    if (!state || !out_root) {
        return -1;
    }
    LanternRoot state_root;
    if (lantern_hash_tree_root_state(state, &state_root) != SSZ_SUCCESS) {
        return -1;
    }
    LanternBlockHeader header = state->latest_block_header;
    header.state_root = state_root;
    return lantern_hash_tree_root_block_header(&header, out_root) == SSZ_SUCCESS ? 0 : -1;
}

static bool test_state_matches_root(const LanternState *state, const LanternRoot *root)
{
    if (!state || !root) {
        return false;
    }
    LanternRoot computed;
    if (test_state_latest_block_root(state, &computed) != 0) {
        return false;
    }
    return memcmp(computed.bytes, root->bytes, LANTERN_ROOT_SIZE) == 0;
}

static void disable_sync_test_peer(struct lantern_client *client)
{
    if (!client) {
        return;
    }
    free(client->peer_status_entries);
    client->peer_status_entries = NULL;
    client->peer_status_count = 0u;
    client->peer_status_capacity = 0u;
    for (size_t i = 0; i < client->active_blocks_request_count; ++i) {
        free(client->active_blocks_requests[i].roots);
    }
    free(client->active_blocks_requests);
    client->active_blocks_requests = NULL;
    client->active_blocks_request_count = 0u;
    client->active_blocks_request_capacity = 0u;
    free(client->block_fetches);
    client->block_fetches = NULL;
    client->block_fetch_count = 0u;
    client->block_fetch_capacity = 0u;
    client->next_blocks_request_id = 0u;
    lantern_client_debug_pending_reset(client);
    if (client->connection_lock_initialized) {
        pthread_mutex_destroy(&client->connection_lock);
        client->connection_lock_initialized = false;
    }
    client_test_clear_connected_peers(client);
    if (client->status_lock_initialized) {
        pthread_mutex_destroy(&client->status_lock);
        client->status_lock_initialized = false;
    }
    if (client->pending_lock_initialized) {
        pthread_mutex_destroy(&client->pending_lock);
        client->pending_lock_initialized = false;
    }
}

static int set_single_active_blocks_request_for_test(
    struct lantern_client *client,
    uint64_t request_id,
    const char *peer_id,
    const LanternRoot *root,
    const LanternRoot *backfill_session_head)
{
    if (!client || !peer_id || !root || client->active_blocks_request_count != 0u) {
        return -1;
    }
    if (!client->active_blocks_requests) {
        client->active_blocks_requests = calloc(1u, sizeof(*client->active_blocks_requests));
        if (!client->active_blocks_requests) {
            return -1;
        }
        client->active_blocks_request_capacity = 1u;
    } else if (client->active_blocks_request_capacity == 0u) {
        return -1;
    }
    struct lantern_active_blocks_request *request = &client->active_blocks_requests[0];
    memset(request, 0, sizeof(*request));
    request->roots = malloc(sizeof(*request->roots));
    if (!request->roots) {
        return -1;
    }
    request->roots[0] = *root;
    request->root_count = 1u;
    request->request_id = request_id;
    if (backfill_session_head) {
        request->backfill_session_head = *backfill_session_head;
    }
    (void)snprintf(request->peer_id, sizeof(request->peer_id), "%s", peer_id);
    client->active_blocks_request_count = 1u;
    return 0;
}

static int set_single_block_fetch_for_test(
    struct lantern_client *client,
    const LanternRoot *root,
    const LanternRoot *backfill_session_head,
    uint32_t attempts)
{
    if (!client || !root || client->block_fetch_count != 0u) {
        return -1;
    }
    if (!client->block_fetches) {
        client->block_fetches = calloc(1u, sizeof(*client->block_fetches));
        if (!client->block_fetches) {
            return -1;
        }
        client->block_fetch_capacity = 1u;
    } else if (client->block_fetch_capacity == 0u) {
        return -1;
    }
    struct lantern_block_fetch *fetch = &client->block_fetches[0];
    memset(fetch, 0, sizeof(*fetch));
    fetch->root = *root;
    fetch->attempts = attempts;
    if (backfill_session_head) {
        fetch->backfill_session_head = *backfill_session_head;
    }
    client->block_fetch_count = 1u;
    return 0;
}

static int set_sync_test_connected_peers(
    struct lantern_client *client,
    const char *peer_a,
    const char *peer_b)
{
    if (!client || !peer_a || !peer_b) {
        return -1;
    }
    struct lantern_connection_peer_ref *refs = calloc(2u, sizeof(*refs));
    if (!refs
        || lantern_peer_id_from_text(peer_a, &refs[0].peer) != 0
        || lantern_peer_id_from_text(peer_b, &refs[1].peer) != 0) {
        free(refs);
        return -1;
    }
    refs[0].conn = &refs[0];
    refs[1].conn = &refs[1];
    free(client->connection_peer_refs);
    client->connection_peer_refs = refs;
    client->connection_peer_ref_count = 2u;
    client->connection_peer_ref_capacity = 2u;
    client->connected_peers = 2u;
    return 0;
}

static int build_signed_block_for_import(
    struct block_signature_fixture *fixture,
    bool include_attestation_proof,
    bool include_block_proof,
    LanternSignedBlock *out_block,
    LanternRoot *out_root)
{
    if (!fixture || !fixture->secret || !out_block || !out_root) {
        return -1;
    }

    int rc = -1;
    struct lantern_aggregated_payload_pool attestation_payloads = {0};
    LanternAggregatedSignatureProof attestation_proof;
    lantern_aggregated_signature_proof_init(&attestation_proof);

    lantern_signed_block_init(out_block);

    uint64_t block_slot = fixture->client.state.slot + 1u;
    out_block->block.slot = block_slot;
    if (lantern_proposer_for_slot(
            block_slot,
            fixture->client.state.validator_count,
            &out_block->block.proposer_index)
        != 0) {
        goto cleanup;
    }
    if (lantern_state_select_block_parent(
            &fixture->client.state,
            &fixture->client.store,
            &out_block->block.parent_root)
        != 0) {
        goto cleanup;
    }
    if (lantern_storage_store_state_for_root(
            &fixture->client.storage,
            &out_block->block.parent_root,
            &fixture->client.state)
        != 0) {
        goto cleanup;
    }

    LanternCheckpoint head = {0};
    LanternCheckpoint target = {0};
    LanternCheckpoint source = {0};
    if (lantern_state_compute_vote_checkpoints(
            &fixture->client.state,
            &fixture->client.store,
            &head,
            &target,
               &source)
        != 0) {
        goto cleanup;
    }

    LanternSignedVote proposer_vote;
    memset(&proposer_vote, 0, sizeof(proposer_vote));
    proposer_vote.data.validator_id = out_block->block.proposer_index;
    proposer_vote.data.slot = block_slot;
    proposer_vote.data.head = head;
    proposer_vote.data.target = target;
    proposer_vote.data.source = source;
    if (client_test_sign_vote_with_secret(&proposer_vote, fixture->secret) != 0) {
        goto cleanup;
    }

    if (lantern_aggregated_attestations_resize(&out_block->block.body.attestations, 1u) != 0) {
        goto cleanup;
    }
    LanternAggregatedAttestation *attestation = &out_block->block.body.attestations.data[0];
    attestation->data = proposer_vote.data.data;
    if (lantern_bitlist_resize(&attestation->aggregation_bits, 1u) != 0
        || lantern_bitlist_set(&attestation->aggregation_bits, 0u, true) != 0) {
        goto cleanup;
    }

    if (include_block_proof) {
        if (!include_attestation_proof) {
            goto cleanup;
        }
        LanternAggregatedSignatureProof *proof = &attestation_proof;
        if (lantern_bitlist_resize(&proof->participants, 1u) != 0
            || lantern_bitlist_set(&proof->participants, 0u, true) != 0) {
            goto cleanup;
        }
        if (!fixture->client.state.validators) {
            goto cleanup;
        }
        const uint8_t *pubkey = fixture->client.state.validators[0].attestation_pubkey;
        LanternRoot attestation_root;
        if (lantern_hash_tree_root_attestation_data(&attestation->data, &attestation_root) != SSZ_SUCCESS) {
            goto cleanup;
        }
        LanternRawXmssSignature raw_signature = {
            .pubkey = pubkey,
            .signature = &proposer_vote.signature,
        };
        if (!lantern_aggregated_signature_proof_aggregate(
                &fixture->client.state,
                &attestation->aggregation_bits,
                NULL,
                0u,
                &raw_signature,
                1u,
                &attestation_root,
                attestation->data.slot,
                proof)) {
            goto cleanup;
        }
        if (lantern_aggregated_payload_pool_add(
                &attestation_payloads,
                &attestation_root,
                &attestation->data,
                proof)
            != 0) {
            goto cleanup;
        }
    }

    if (lantern_state_preview_post_state_root(
            &fixture->client.state,
            &fixture->client.store,
            out_block,
            &out_block->block.state_root)
        != 0) {
        goto cleanup;
    }

    if (include_block_proof) {
        LanternRoot block_signature_root;
        if (lantern_hash_tree_root_block(&out_block->block, &block_signature_root) != SSZ_SUCCESS) {
            goto cleanup;
        }
        LanternSignature proposer_signature;
        memset(&proposer_signature, 0, sizeof(proposer_signature));
        if (!lantern_signature_sign(
                fixture->secret,
                out_block->block.slot,
                &block_signature_root,
                &proposer_signature)) {
            goto cleanup;
        }
        if (build_devnet5_block_proof(
                fixture,
                &fixture->client.state,
                out_block,
                &block_signature_root,
                &attestation_payloads,
                &proposer_signature)
            != 0) {
            goto cleanup;
        }
    }

    rc = lantern_hash_tree_root_block(&out_block->block, out_root) == SSZ_SUCCESS ? 0 : -1;

cleanup:
    lantern_aggregated_signature_proof_reset(&attestation_proof);
    lantern_aggregated_payload_pool_reset(&attestation_payloads);
    return rc;
}

static int persist_post_state_for_block(
    const struct block_signature_fixture *fixture,
    const LanternSignedBlock *block,
    const LanternRoot *block_root)
{
    LanternState post_state;
    lantern_state_init(&post_state);

    int rc = -1;
    if (lantern_state_clone(&fixture->client.state, &post_state) == 0
        && lantern_state_transition(&post_state, block) == 0
        && lantern_storage_store_state_for_root(
               &fixture->client.storage,
               block_root,
               &post_state)
            == 0) {
        rc = 0;
    }

    lantern_state_reset(&post_state);
    return rc;
}

static int build_proposer_only_block_for_parent(
    struct block_signature_fixture *fixture,
    const LanternState *parent_state,
    const LanternRoot *parent_root,
    uint64_t slot,
    LanternSignedBlock *out_block,
    LanternRoot *out_root,
    LanternState *out_post_state)
{
    if (!fixture || !fixture->secret || !parent_state || !parent_root || !out_block
        || !out_root || !out_post_state || slot <= parent_state->slot) {
        return -1;
    }

    int rc = -1;
    struct lantern_aggregated_payload_pool empty_attestation_payloads = {0};
    lantern_signed_block_init(out_block);
    lantern_state_init(out_post_state);

    out_block->block.slot = slot;
    if (lantern_proposer_for_slot(
            slot,
            parent_state->validator_count,
            &out_block->block.proposer_index)
            != 0) {
        goto cleanup;
    }
    out_block->block.parent_root = *parent_root;
    if (lantern_state_preview_post_state_root(
            parent_state,
            &fixture->client.store,
            out_block,
            &out_block->block.state_root)
            != 0
        || lantern_hash_tree_root_block(&out_block->block, out_root) != SSZ_SUCCESS) {
        goto cleanup;
    }

    LanternSignature proposer_signature;
    memset(&proposer_signature, 0, sizeof(proposer_signature));
    if (!lantern_signature_sign(fixture->secret, slot, out_root, &proposer_signature)
        || build_devnet5_block_proof(
               fixture,
               parent_state,
               out_block,
               out_root,
               &empty_attestation_payloads,
               &proposer_signature)
               != 0
        || lantern_state_clone(parent_state, out_post_state) != 0
        || lantern_state_transition(out_post_state, out_block) != 0) {
        goto cleanup;
    }

    rc = 0;

cleanup:
    lantern_aggregated_payload_pool_reset(&empty_attestation_payloads);
    if (rc != 0) {
        lantern_signed_block_reset(out_block);
        lantern_state_reset(out_post_state);
    }
    return rc;
}

static int resign_matching_block_attestations(
    struct block_signature_fixture *fixture,
    LanternSignedBlock *block,
    LanternRoot *out_root)
{
    if (!fixture || !fixture->secret || !block || !out_root) {
        return -1;
    }
    if (block->block.body.attestations.length == 0
        || !block->block.body.attestations.data) {
        return -1;
    }

    int rc = -1;
    struct lantern_aggregated_payload_pool attestation_payloads = {0};
    LanternAggregatedSignatureProof attestation_proof;
    lantern_aggregated_signature_proof_init(&attestation_proof);

    LanternAggregatedAttestation *attestation = &block->block.body.attestations.data[0];
    LanternAggregatedSignatureProof *proof = &attestation_proof;

    LanternSignedVote signed_vote;
    memset(&signed_vote, 0, sizeof(signed_vote));
    signed_vote.data.validator_id = 0u;
    signed_vote.data.slot = attestation->data.slot;
    signed_vote.data.data = attestation->data;
    if (client_test_sign_vote_with_secret(&signed_vote, fixture->secret) != 0) {
        goto cleanup;
    }

    if (lantern_bitlist_resize(&attestation->aggregation_bits, 1u) != 0
        || lantern_bitlist_set(&attestation->aggregation_bits, 0u, true) != 0) {
        goto cleanup;
    }
    if (lantern_bitlist_resize(&proof->participants, 1u) != 0
        || lantern_bitlist_set(&proof->participants, 0u, true) != 0) {
        goto cleanup;
    }

    if (!fixture->client.state.validators) {
        goto cleanup;
    }
    const uint8_t *pubkey = fixture->client.state.validators[0].attestation_pubkey;
    LanternRoot attestation_root;
    if (lantern_hash_tree_root_attestation_data(&attestation->data, &attestation_root) != SSZ_SUCCESS) {
        goto cleanup;
    }
    LanternRawXmssSignature raw_signature = {
        .pubkey = pubkey,
        .signature = &signed_vote.signature,
    };
    if (!lantern_aggregated_signature_proof_aggregate(
            &fixture->client.state,
            &attestation->aggregation_bits,
            NULL,
            0u,
            &raw_signature,
            1u,
            &attestation_root,
            attestation->data.slot,
            proof)) {
        goto cleanup;
    }
    size_t attestation_count = block->block.body.attestations.length;
    attestation_payloads.entries = calloc(attestation_count, sizeof(*attestation_payloads.entries));
    if (!attestation_payloads.entries) {
        goto cleanup;
    }
    attestation_payloads.capacity = attestation_count;
    for (size_t i = 0; i < attestation_count; ++i) {
        LanternAggregatedAttestation *candidate = &block->block.body.attestations.data[i];
        struct lantern_aggregated_payload_entry *entry = &attestation_payloads.entries[i];
        LanternRoot candidate_root;
        if (lantern_hash_tree_root_attestation_data(&candidate->data, &candidate_root) != SSZ_SUCCESS
            || memcmp(candidate_root.bytes, attestation_root.bytes, LANTERN_ROOT_SIZE) != 0) {
            goto cleanup;
        }
        entry->data_root = candidate_root;
        entry->data = candidate->data;
        lantern_aggregated_signature_proof_init(&entry->proof);
        attestation_payloads.length = i + 1u;
        if (lantern_aggregated_signature_proof_copy(&entry->proof, proof) != 0) {
            goto cleanup;
        }
    }

    if (lantern_state_preview_post_state_root(
            &fixture->client.state,
            &fixture->client.store,
            block,
            &block->block.state_root)
        != 0) {
        goto cleanup;
    }
    if (lantern_hash_tree_root_block(&block->block, out_root) != SSZ_SUCCESS) {
        goto cleanup;
    }
    LanternSignature proposer_signature;
    memset(&proposer_signature, 0, sizeof(proposer_signature));
    if (!lantern_signature_sign(
            fixture->secret,
            block->block.slot,
            out_root,
            &proposer_signature)) {
        goto cleanup;
    }
    if (build_devnet5_block_proof(
            fixture,
            &fixture->client.state,
            block,
            out_root,
            &attestation_payloads,
            &proposer_signature)
        != 0) {
        goto cleanup;
    }

    rc = 0;

cleanup:
    lantern_aggregated_signature_proof_reset(&attestation_proof);
    lantern_aggregated_payload_pool_reset(&attestation_payloads);
    return rc;
}

static int expect_recovered_block_payload(
    const LanternStore *store,
    const LanternSignedBlock *block,
    bool may_be_known,
    const char *context)
{
    if (!store || !block || block->block.body.attestations.length == 0u
        || !block->block.body.attestations.data) {
        return -1;
    }
    const struct lantern_aggregated_payload_entry *payload = NULL;
    if (may_be_known) {
        size_t count =
            store->new_aggregated_payloads.length + store->known_aggregated_payloads.length;
        if (count != 1u) {
            fprintf(stderr, "%s should recover one block-body proof into payload pools\n", context);
            return -1;
        }
        payload = store->new_aggregated_payloads.length != 0u
            ? &store->new_aggregated_payloads.entries[0]
            : &store->known_aggregated_payloads.entries[0];
    } else {
        if (store->new_aggregated_payloads.length != 1u
            || store->known_aggregated_payloads.length != 0u) {
            fprintf(stderr, "%s should stage one recovered block-body proof in new payloads\n", context);
            return -1;
        }
        payload = &store->new_aggregated_payloads.entries[0];
    }

    LanternRoot data_root;
    if (lantern_hash_tree_root_attestation_data(
            &block->block.body.attestations.data[0].data,
            &data_root)
        != SSZ_SUCCESS) {
        return -1;
    }
    if (memcmp(payload->data_root.bytes, data_root.bytes, LANTERN_ROOT_SIZE) != 0
        || memcmp(
               &payload->data,
               &block->block.body.attestations.data[0].data,
               sizeof(payload->data))
            != 0
        || !lantern_bitlist_get(&payload->proof.participants, 0u)) {
        fprintf(stderr, "%s recovered payload does not match block attestation\n", context);
        return -1;
    }
    return 0;
}

static int test_pending_block_queue(void) {
    struct lantern_client client;
    memset(&client, 0, sizeof(client));
    client.node_id = "test_pending_queue";

    if (pthread_mutex_init(&client.pending_lock, NULL) != 0) {
        fprintf(stderr, "failed to initialize pending mutex\n");
        return 1;
    }
    client.pending_lock_initialized = true;
    lantern_client_debug_pending_reset(&client);

    if (pthread_mutex_init(&client.status_lock, NULL) != 0) {
        fprintf(stderr, "failed to initialize status mutex\n");
        pthread_mutex_destroy(&client.pending_lock);
        client.pending_lock_initialized = false;
        return 1;
    }
    client.status_lock_initialized = true;

    LanternSignedBlock child;
    memset(&child, 0, sizeof(child));
    lantern_block_body_init(&child.block.body);
    child.block.slot = 10;

    LanternRoot child_root;
    LanternRoot parent_root;
    client_test_fill_root(&child_root, 0x10);
    client_test_fill_root(&parent_root, 0x20);

    const char *peer_a = "12D3KooWpeerA";
    const char *peer_b = "12D3KooWpeerB";
    LanternRoot fetched_root;
    LanternRoot fetched_parent;
    char peer_text[128];
    LanternRoot last_root;
    client_test_fill_root_with_index(&last_root, 0);
    int rc = 0;

    if (lantern_client_debug_enqueue_pending_block(
            &client,
            &child,
            &child_root,
            &parent_root,
            peer_a)
        != 0) {
        fprintf(stderr, "failed to enqueue initial pending block\n");
        rc = 1;
        goto cleanup;
    }

    if (lantern_client_pending_block_count(&client) != 1) {
        fprintf(stderr, "pending queue count mismatch after first enqueue\n");
        rc = 1;
        goto cleanup;
    }

    if (lantern_client_debug_pending_entry(
            &client,
            0,
            &fetched_root,
            &fetched_parent,
            peer_text,
            sizeof(peer_text))
        != 0) {
        fprintf(stderr, "failed to fetch pending entry\n");
        rc = 1;
        goto cleanup;
    }
    if (memcmp(fetched_root.bytes, child_root.bytes, LANTERN_ROOT_SIZE) != 0) {
        fprintf(stderr, "pending root mismatch after first enqueue\n");
        rc = 1;
        goto cleanup;
    }
    if (memcmp(fetched_parent.bytes, parent_root.bytes, LANTERN_ROOT_SIZE) != 0) {
        fprintf(stderr, "pending parent mismatch after first enqueue\n");
        rc = 1;
        goto cleanup;
    }
    if (strcmp(peer_text, peer_a) != 0) {
        fprintf(stderr, "pending peer mismatch after first enqueue\n");
        rc = 1;
        goto cleanup;
    }
    if (lantern_client_debug_enqueue_pending_block(
            &client,
            &child,
            &child_root,
            &parent_root,
            peer_b)
        != 0) {
        fprintf(stderr, "failed to enqueue duplicate pending block\n");
        rc = 1;
        goto cleanup;
    }

    if (lantern_client_pending_block_count(&client) != 1) {
        fprintf(stderr, "pending queue count changed after duplicate enqueue\n");
        rc = 1;
        goto cleanup;
    }

    if (lantern_client_debug_pending_entry(
            &client,
            0,
            &fetched_root,
            &fetched_parent,
            peer_text,
            sizeof(peer_text))
        != 0) {
        fprintf(stderr, "failed to fetch pending entry after duplicate enqueue\n");
        rc = 1;
        goto cleanup;
    }
    if (strcmp(peer_text, peer_b) != 0) {
        fprintf(stderr, "pending peer did not update after duplicate enqueue\n");
        rc = 1;
        goto cleanup;
    }

    size_t extra_count = LANTERN_PENDING_BLOCK_LIMIT + 50u;
    for (size_t i = 0; i < extra_count; ++i) {
        LanternSignedBlock extra;
        memset(&extra, 0, sizeof(extra));
        lantern_block_body_init(&extra.block.body);
        extra.block.slot = 20 + i;
        LanternRoot extra_root;
        LanternRoot extra_parent;
        client_test_fill_root_with_index(&extra_root, 1000u + (uint32_t)i);
        client_test_fill_root_with_index(&extra_parent, 2000u + (uint32_t)i);
        if (i == 299) {
            last_root = extra_root;
        }
        if (lantern_client_debug_enqueue_pending_block(
                &client,
                &extra,
                &extra_root,
                &extra_parent,
                NULL)
            != 0) {
            fprintf(stderr, "failed to enqueue additional pending block %zu\n", i);
            lantern_block_body_reset(&extra.block.body);
            rc = 1;
            goto cleanup;
        }
        lantern_block_body_reset(&extra.block.body);
    }

    size_t count = lantern_client_pending_block_count(&client);
    if (count > LANTERN_PENDING_BLOCK_LIMIT) {
        fprintf(stderr, "pending queue exceeded expected limit: %zu\n", count);
        rc = 1;
        goto cleanup;
    }

    if (client_test_pending_contains_root(&client, &child_root)) {
        fprintf(stderr, "oldest pending block was not evicted at capacity\n");
        rc = 1;
        goto cleanup;
    }

    if (!client_test_pending_contains_root(&client, &last_root)) {
        fprintf(stderr, "latest pending block missing after enqueues\n");
        rc = 1;
        goto cleanup;
    }

cleanup:
    lantern_client_debug_pending_reset(&client);
    lantern_block_body_reset(&child.block.body);
    if (client.status_lock_initialized) {
        pthread_mutex_destroy(&client.status_lock);
        client.status_lock_initialized = false;
    }
    if (client.pending_lock_initialized) {
        pthread_mutex_destroy(&client.pending_lock);
        client.pending_lock_initialized = false;
    }
    return rc;
}

static int test_pending_block_queue_sync_drops_incoming(void) {
    struct lantern_client client;
    memset(&client, 0, sizeof(client));
    client.node_id = "test_pending_sync_queue";
    client.sync_state = LANTERN_SYNC_STATE_SYNCING;
    client.sync_started_ms = 1u;

    if (pthread_mutex_init(&client.pending_lock, NULL) != 0) {
        fprintf(stderr, "failed to initialize pending mutex\n");
        return 1;
    }
    client.pending_lock_initialized = true;
    lantern_client_debug_pending_reset(&client);

    LanternRoot oldest_root;
    LanternRoot latest_root;
    LanternRoot extra_root;
    LanternRoot parent_root;
    client_test_fill_root_with_index(&oldest_root, 0);
    client_test_fill_root_with_index(&latest_root, 0);

    int rc = 0;
    for (size_t i = 0; i < LANTERN_PENDING_BLOCK_LIMIT; ++i) {
        LanternSignedBlock block;
        memset(&block, 0, sizeof(block));
        lantern_block_body_init(&block.block.body);
        block.block.slot = 100 + i;

        LanternRoot block_root;
        client_test_fill_root_with_index(&block_root, 10000u + (uint32_t)i);
        client_test_fill_root_with_index(&parent_root, 20000u + (uint32_t)i);
        if (i == 0) {
            oldest_root = block_root;
        }
        if (i + 1u == LANTERN_PENDING_BLOCK_LIMIT) {
            latest_root = block_root;
        }

        if (lantern_client_debug_enqueue_pending_block(
                &client,
                &block,
                &block_root,
                &parent_root,
                NULL)
            != 0) {
            fprintf(stderr, "failed to enqueue pending block %zu\n", i);
            lantern_block_body_reset(&block.block.body);
            rc = 1;
            goto cleanup;
        }

        lantern_block_body_reset(&block.block.body);
    }

    if (lantern_client_pending_block_count(&client) != LANTERN_PENDING_BLOCK_LIMIT) {
        fprintf(stderr, "pending queue count mismatch after fill in sync mode\n");
        rc = 1;
        goto cleanup;
    }

    LanternSignedBlock extra_block;
    memset(&extra_block, 0, sizeof(extra_block));
    lantern_block_body_init(&extra_block.block.body);
    extra_block.block.slot = 999999;
    client_test_fill_root_with_index(&extra_root, 900000u);
    client_test_fill_root_with_index(&parent_root, 910000u);

    if (lantern_client_debug_enqueue_pending_block(
            &client,
            &extra_block,
            &extra_root,
            &parent_root,
            NULL)
        != 0) {
        fprintf(stderr, "failed to enqueue overflow pending block in sync mode\n");
        lantern_block_body_reset(&extra_block.block.body);
        rc = 1;
        goto cleanup;
    }
    lantern_block_body_reset(&extra_block.block.body);

    if (lantern_client_pending_block_count(&client) != LANTERN_PENDING_BLOCK_LIMIT) {
        fprintf(stderr, "pending queue count changed after overflow enqueue in sync mode\n");
        rc = 1;
        goto cleanup;
    }

    if (!client_test_pending_contains_root(&client, &oldest_root)) {
        fprintf(stderr, "oldest pending block was unexpectedly evicted in sync mode\n");
        rc = 1;
        goto cleanup;
    }
    if (!client_test_pending_contains_root(&client, &latest_root)) {
        fprintf(stderr, "latest accepted pending block missing in sync mode\n");
        rc = 1;
        goto cleanup;
    }
    if (client_test_pending_contains_root(&client, &extra_root)) {
        fprintf(stderr, "overflow pending block should have been dropped in sync mode\n");
        rc = 1;
        goto cleanup;
    }

cleanup:
    lantern_client_debug_pending_reset(&client);
    if (client.pending_lock_initialized) {
        pthread_mutex_destroy(&client.pending_lock);
        client.pending_lock_initialized = false;
    }
    return rc;
}

static int test_sync_completion_uses_network_finalized_threshold(void)
{
    struct lantern_client client;
    struct PQSignatureSchemePublicKey *pub = NULL;
    struct PQSignatureSchemeSecretKey *secret = NULL;
    int rc = 1;

    if (client_test_setup_vote_validation_client(
            &client,
            "sync_completion_threshold",
            &pub,
            &secret,
            NULL,
            NULL)
        != 0) {
        return 1;
    }

    if (pthread_mutex_init(&client.status_lock, NULL) != 0) {
        fprintf(stderr, "failed to initialize status mutex for sync threshold test\n");
        goto cleanup;
    }
    client.status_lock_initialized = true;

    if (pthread_mutex_init(&client.pending_lock, NULL) != 0) {
        fprintf(stderr, "failed to initialize pending mutex for sync threshold test\n");
        goto cleanup;
    }
    client.pending_lock_initialized = true;
    lantern_client_debug_pending_reset(&client);

    uint64_t local_head_slot = client.state.slot;
    client.sync_state = LANTERN_SYNC_STATE_SYNCING;
    lantern_client_update_sync_progress(&client, local_head_slot);
    if (client.sync_state == LANTERN_SYNC_STATE_SYNCED) {
        fprintf(stderr, "sync should not complete without a network finalized view\n");
        goto cleanup;
    }

    client.network_view.head = (LanternCheckpoint){
        .root = client.store.head,
        .slot = local_head_slot + 128u,
    };
    client.network_view.finalized = client.store.latest_finalized;

    LanternSignedBlock pending_block;
    memset(&pending_block, 0, sizeof(pending_block));
    lantern_block_body_init(&pending_block.block.body);
    pending_block.block.slot = local_head_slot + 10u;
    LanternRoot pending_root;
    LanternRoot missing_parent;
    client_test_fill_root(&pending_root, 0x60u);
    client_test_fill_root(&missing_parent, 0x70u);
    if (lantern_client_debug_enqueue_pending_block(
            &client,
            &pending_block,
            &pending_root,
            &missing_parent,
            NULL)
        != 0) {
        fprintf(stderr, "failed to enqueue orphan block for sync threshold test\n");
        lantern_block_body_reset(&pending_block.block.body);
        goto cleanup;
    }
    lantern_block_body_reset(&pending_block.block.body);

    client.sync_state = LANTERN_SYNC_STATE_SYNCING;
    lantern_client_update_sync_progress(&client, local_head_slot);
    if (client.sync_state == LANTERN_SYNC_STATE_SYNCED) {
        fprintf(stderr, "sync should not complete while orphan parents are pending\n");
        goto cleanup;
    }

    lantern_client_debug_pending_reset(&client);
    client.network_view.finalized.slot = local_head_slot + 1u;
    client.sync_state = LANTERN_SYNC_STATE_SYNCING;
    lantern_client_update_sync_progress(&client, local_head_slot);
    if (client.sync_state == LANTERN_SYNC_STATE_SYNCED) {
        fprintf(stderr, "sync should not complete below network finalized slot\n");
        goto cleanup;
    }

    client.network_view.head.slot = local_head_slot + 1024u;
    client.network_view.finalized.slot = local_head_slot + 1u;
    client.sync_state = LANTERN_SYNC_STATE_SYNCING;
    lantern_client_update_sync_progress(&client, local_head_slot + 1024u);
    if (client.sync_state == LANTERN_SYNC_STATE_SYNCED) {
        fprintf(stderr, "sync should not complete from high local head with stale finality\n");
        goto cleanup;
    }

    client.network_view.head.slot = local_head_slot + 1024u;
    client.network_view.finalized.slot = client.state.latest_finalized.slot;
    client.sync_state = LANTERN_SYNC_STATE_SYNCING;
    lantern_client_update_sync_progress(&client, local_head_slot);
    if (client.sync_state != LANTERN_SYNC_STATE_SYNCED) {
        fprintf(stderr, "sync should complete at network finalized threshold\n");
        goto cleanup;
    }

    rc = 0;

cleanup:
    if (client.pending_lock_initialized) {
        lantern_client_debug_pending_reset(&client);
        pthread_mutex_destroy(&client.pending_lock);
        client.pending_lock_initialized = false;
    }
    if (client.status_lock_initialized) {
        pthread_mutex_destroy(&client.status_lock);
        client.status_lock_initialized = false;
    }
    client_test_teardown_vote_validation_client(&client, pub, secret);
    return rc;
}

static int test_idle_status_triggers_syncing_before_gossip_backfill(void)
{
    struct lantern_client client;
    struct PQSignatureSchemePublicKey *pub = NULL;
    struct PQSignatureSchemeSecretKey *secret = NULL;
    LanternRoot child_root;
    LanternSignedBlock orphan_block;
    const char *peer_id = "16Uiu2HAmQj1RDNAxopeeeCFPRr3zhJYmH6DEPHYKmxLViLahWcFE";
    int rc = 1;

    memset(&orphan_block, 0, sizeof(orphan_block));
    if (client_test_setup_vote_validation_client(
            &client,
            "sync_idle_gossip_backfill",
            &pub,
            &secret,
            NULL,
            &child_root)
        != 0) {
        return 1;
    }
    if (enable_sync_test_peer(&client, peer_id) != 0) {
        fprintf(stderr, "failed to enable sync test peer\n");
        goto cleanup;
    }

    lantern_block_body_init(&orphan_block.block.body);
    orphan_block.block.slot = client.state.slot + 8u;
    orphan_block.block.proposer_index = 0u;
    client_test_fill_root(&orphan_block.block.parent_root, 0x91u);
    client_test_fill_root(&orphan_block.block.state_root, 0x92u);

    client.sync_state = LANTERN_SYNC_STATE_IDLE;
    if (lantern_client_debug_gossip_block(&client, &orphan_block) != LANTERN_CLIENT_ERR_IGNORED) {
        fprintf(stderr, "IDLE gossip block should be ignored\n");
        goto cleanup;
    }
    if (lantern_client_pending_block_count(&client) != 0u) {
        fprintf(stderr, "IDLE gossip block should not enter pending queue\n");
        goto cleanup;
    }
    if (client.next_blocks_request_id != 0u) {
        fprintf(stderr, "IDLE gossip block should not schedule parent requests\n");
        goto cleanup;
    }

    LanternStatusMessage status;
    memset(&status, 0, sizeof(status));
    status.head.root = child_root;
    status.head.slot = client.state.slot;
    status.finalized = client.state.latest_finalized;
    status.finalized.slot = client.state.slot + 1u;
    client_test_fill_root(&status.finalized.root, 0x55u);
    if (reqresp_handle_status(&client, &status, peer_id) != LANTERN_CLIENT_OK) {
        fprintf(stderr, "peer status update failed\n");
        goto cleanup;
    }
    if (client.sync_state != LANTERN_SYNC_STATE_SYNCING) {
        fprintf(stderr, "peer status finalized ahead should keep sync incomplete\n");
        goto cleanup;
    }

    uint64_t request_id_before = client.next_blocks_request_id;
    if (lantern_client_debug_gossip_block(&client, &orphan_block) != LANTERN_CLIENT_OK) {
        fprintf(stderr, "SYNCING gossip block should be accepted into pending flow\n");
        goto cleanup;
    }
    if (lantern_client_pending_block_count(&client) != 1u) {
        fprintf(stderr, "SYNCING unknown-parent gossip block should be pending\n");
        goto cleanup;
    }
    if (client.next_blocks_request_id == request_id_before) {
        fprintf(stderr, "SYNCING unknown-parent gossip block should trigger blocks_by_root\n");
        goto cleanup;
    }

    rc = 0;

cleanup:
    lantern_block_body_reset(&orphan_block.block.body);
    disable_sync_test_peer(&client);
    client_test_teardown_vote_validation_client(&client, pub, secret);
    return rc;
}

static int test_active_parent_requests_deduplicate_and_release(void)
{
    struct lantern_client client;
    LanternSignedBlock block;
    LanternRoot block_root;
    LanternRoot parent_root;
    const char *peer_id = "16Uiu2HAmQj1RDNAxopeeeCFPRr3zhJYmH6DEPHYKmxLViLahWcFE";
    int rc = 1;

    memset(&client, 0, sizeof(client));
    memset(&block, 0, sizeof(block));
    client.node_id = "active_parent_request";
    if (enable_sync_test_peer(&client, peer_id) != 0) {
        return 1;
    }
    if (pthread_mutex_lock(&client.status_lock) != 0) {
        goto cleanup;
    }
    struct lantern_peer_status_entry *peer_status =
        lantern_client_ensure_status_entry_locked(&client, peer_id);
    pthread_mutex_unlock(&client.status_lock);
    if (!peer_status) {
        goto cleanup;
    }

    lantern_block_body_init(&block.block.body);
    block.block.slot = 10u;
    client_test_fill_root(&block_root, 0x81u);
    client_test_fill_root(&parent_root, 0x82u);
    client.sync_state = LANTERN_SYNC_STATE_IDLE;
    if (lantern_client_debug_enqueue_pending_block(
            &client,
            &block,
            &block_root,
            &parent_root,
            peer_id)
        != LANTERN_CLIENT_OK) {
        fprintf(stderr, "failed to enqueue active-request test block\n");
        goto cleanup;
    }

    if (set_single_active_blocks_request_for_test(
            &client,
            7u,
            peer_id,
            &parent_root,
            NULL)
            != 0
        || set_single_block_fetch_for_test(&client, &parent_root, NULL, 1u) != 0) {
        goto cleanup;
    }
    client.next_blocks_request_id = 8u;
    client.sync_state = LANTERN_SYNC_STATE_SYNCING;

    lantern_client_request_pending_parent_after_blocks(&client, peer_id, NULL);
    if (client.active_blocks_request_count != 1u || client.next_blocks_request_id != 8u) {
        fprintf(stderr, "duplicate parent root scheduled while already active\n");
        goto cleanup;
    }

    lantern_client_on_blocks_request_complete_batch_with_id(
        &client,
        7u,
        peer_id,
        LANTERN_BLOCKS_REQUEST_FAILED);
    if (client.next_blocks_request_id != 8u || client.active_blocks_request_count != 0u
        || client.block_fetch_count != 1u || client.block_fetches[0].retry_at_us == 0u) {
        fprintf(stderr, "failed parent request did not enter delayed retry\n");
        goto cleanup;
    }
    lantern_client_drive_block_fetch_retries(&client, client.block_fetches[0].retry_at_us);
    if (client.next_blocks_request_id != 9u || client.active_blocks_request_count != 0u
        || client.block_fetch_count != 0u) {
        fprintf(stderr, "delayed parent retry did not run and clean up after send failure\n");
        goto cleanup;
    }

    rc = 0;

cleanup:
    lantern_block_body_reset(&block.block.body);
    disable_sync_test_peer(&client);
    return rc;
}

static int test_idle_status_at_known_head_completes_sync(void)
{
    struct lantern_client client;
    struct PQSignatureSchemePublicKey *pub = NULL;
    struct PQSignatureSchemeSecretKey *secret = NULL;
    LanternRoot child_root;
    const char *peer_id = "16Uiu2HAmQj1RDNAxopeeeCFPRr3zhJYmH6DEPHYKmxLViLahWcFE";
    int rc = 1;

    if (client_test_setup_vote_validation_client(
            &client,
            "sync_idle_status_caught_up",
            &pub,
            &secret,
            NULL,
            &child_root)
        != 0) {
        return 1;
    }
    if (enable_sync_test_peer(&client, peer_id) != 0) {
        fprintf(stderr, "failed to enable sync test peer\n");
        goto cleanup;
    }

    client.sync_state = LANTERN_SYNC_STATE_IDLE;

    LanternStatusMessage status;
    memset(&status, 0, sizeof(status));
    status.head.root = child_root;
    status.head.slot = client.state.slot;
    status.finalized = client.state.latest_finalized;
    if (reqresp_handle_status(&client, &status, peer_id) != LANTERN_CLIENT_OK) {
        fprintf(stderr, "caught-up peer status update failed\n");
        goto cleanup;
    }
    if (client.sync_state != LANTERN_SYNC_STATE_SYNCED) {
        fprintf(stderr, "caught-up peer status should complete sync from IDLE\n");
        goto cleanup;
    }

    rc = 0;

cleanup:
    disable_sync_test_peer(&client);
    client_test_teardown_vote_validation_client(&client, pub, secret);
    return rc;
}

static int test_peer_status_updates_sync_network_view(void)
{
    struct lantern_client client;
    struct PQSignatureSchemePublicKey *pub = NULL;
    struct PQSignatureSchemeSecretKey *secret = NULL;
    LanternRoot child_root;
    LanternRoot finalized_root;
    const char *peer_id = "16Uiu2HAmQj1RDNAxopeeeCFPRr3zhJYmH6DEPHYKmxLViLahWcFE";
    int rc = 1;

    if (client_test_setup_vote_validation_client(
            &client,
            "sync_peer_status_network_view",
            &pub,
            &secret,
            NULL,
            &child_root)
        != 0) {
        return 1;
    }
    if (enable_sync_test_peer(&client, peer_id) != 0) {
        fprintf(stderr, "failed to enable sync test peer\n");
        goto cleanup;
    }

    client_test_fill_root(&finalized_root, 0x66u);
    client.sync_state = LANTERN_SYNC_STATE_IDLE;

    LanternStatusMessage status;
    memset(&status, 0, sizeof(status));
    status.head.root = child_root;
    status.head.slot = client.state.slot + 16u;
    status.finalized.root = finalized_root;
    status.finalized.slot = client.state.slot + 8u;
    if (reqresp_handle_status(&client, &status, peer_id) != LANTERN_CLIENT_OK) {
        fprintf(stderr, "peer status network view update failed\n");
        goto cleanup;
    }

    if (memcmp(
            client.network_view.head.root.bytes,
            status.head.root.bytes,
            LANTERN_ROOT_SIZE)
            != 0
        || client.network_view.head.slot != status.head.slot) {
        fprintf(stderr, "peer status did not update observed network head\n");
        goto cleanup;
    }
    if (memcmp(
            client.network_view.finalized.root.bytes,
            status.finalized.root.bytes,
            LANTERN_ROOT_SIZE)
            != 0
        || client.network_view.finalized.slot != status.finalized.slot) {
        fprintf(stderr, "peer status did not update observed network finalized slot\n");
        goto cleanup;
    }
    if (client.sync_state != LANTERN_SYNC_STATE_SYNCING) {
        fprintf(stderr, "peer finalized ahead should keep sync incomplete\n");
        goto cleanup;
    }

    rc = 0;

cleanup:
    disable_sync_test_peer(&client);
    client_test_teardown_vote_validation_client(&client, pub, secret);
    return rc;
}

static int test_imported_blocks_update_sync_network_view(void)
{
    struct block_signature_fixture fixture;
    LanternSignedBlock first_block;
    LanternSignedBlock second_block;
    LanternRoot first_root;
    LanternRoot second_root;
    int rc = 1;

    memset(&first_block, 0, sizeof(first_block));
    memset(&second_block, 0, sizeof(second_block));
    if (setup_block_signature_fixture(&fixture, "test_imported_network_view") != 0) {
        fprintf(stderr, "failed to set up network view import fixture\n");
        return 1;
    }

    if (pthread_mutex_init(&fixture.client.status_lock, NULL) != 0) {
        fprintf(stderr, "failed to initialize status mutex for network view import test\n");
        goto cleanup;
    }
    fixture.client.status_lock_initialized = true;
    fixture.client.sync_state = LANTERN_SYNC_STATE_SYNCING;

    if (build_signed_block_for_import(&fixture, true, true, &first_block, &first_root) != 0) {
        fprintf(stderr, "failed to build first network view block\n");
        goto cleanup;
    }
    if (lantern_client_debug_import_block(&fixture.client, &first_block, &first_root, "12D3KooWview") != 1) {
        fprintf(stderr, "failed to import first network view block\n");
        goto cleanup;
    }
    if (memcmp(
            fixture.client.network_view.head.root.bytes,
            first_root.bytes,
            LANTERN_ROOT_SIZE)
            != 0
        || fixture.client.network_view.head.slot != first_block.block.slot) {
        fprintf(stderr, "network view head slot did not track first imported block\n");
        goto cleanup;
    }
    if (!lantern_root_is_zero(&fixture.client.network_view.finalized.root)) {
        fprintf(stderr, "imported block should not seed network finalized from local post-state\n");
        goto cleanup;
    }
    if (fixture.client.sync_state == LANTERN_SYNC_STATE_SYNCED) {
        fprintf(stderr, "sync should not complete without a peer finalized view\n");
        goto cleanup;
    }

    fixture.client.sync_state = LANTERN_SYNC_STATE_SYNCING;
    if (build_signed_block_for_import(&fixture, true, true, &second_block, &second_root) != 0) {
        fprintf(stderr, "failed to build second network view block\n");
        goto cleanup;
    }
    if (lantern_client_debug_import_block(&fixture.client, &second_block, &second_root, "12D3KooWview") != 1) {
        fprintf(stderr, "failed to import second network view block\n");
        goto cleanup;
    }
    if (fixture.client.network_view.head.slot != second_block.block.slot) {
        fprintf(stderr, "network view head slot did not update for newer imported block\n");
        goto cleanup;
    }
    if (!lantern_root_is_zero(&fixture.client.network_view.finalized.root)) {
        fprintf(stderr, "newer imported block should still not seed network finalized\n");
        goto cleanup;
    }

    rc = 0;

cleanup:
    lantern_signed_block_reset(&second_block);
    lantern_signed_block_reset(&first_block);
    if (fixture.client.status_lock_initialized) {
        pthread_mutex_destroy(&fixture.client.status_lock);
        fixture.client.status_lock_initialized = false;
    }
    teardown_block_signature_fixture(&fixture);
    return rc;
}

static int test_reqresp_block_response_accepts_missing_parent(void) {
    struct lantern_client client;
    memset(&client, 0, sizeof(client));
    client.node_id = "test_reqresp_missing_parent";

    int rc = 0;
    LanternSignedBlock block;
    LanternRoot block_root;
    LanternRoot parent_root;
    LanternRoot head_root;
    LanternRoot finalized_root;
    LanternRoot pending_root;
    LanternRoot pending_parent;
    char peer_text[128];
    const uint64_t anchor_slot = 8u;
    const uint64_t finalized_slot = 4u;
    memset(&block, 0, sizeof(block));

    if (pthread_mutex_init(&client.state_lock, NULL) != 0) {
        fprintf(stderr, "failed to initialize state mutex\n");
        return 1;
    }
    client.state_lock_initialized = true;

    if (pthread_mutex_init(&client.pending_lock, NULL) != 0) {
        fprintf(stderr, "failed to initialize pending mutex\n");
        pthread_mutex_destroy(&client.state_lock);
        client.state_lock_initialized = false;
        return 1;
    }
    client.pending_lock_initialized = true;

    lantern_client_debug_pending_reset(&client);

    lantern_state_init(&client.state);
    if (lantern_state_generate_genesis(&client.state, 0u, 8u) != 0) {
        fprintf(stderr, "failed to generate state for missing-parent response test\n");
        rc = 1;
        goto cleanup;
    }
    client.state.slot = anchor_slot;
    lantern_store_init(&client.store);

    memset(&client.state.latest_block_header, 0, sizeof(client.state.latest_block_header));
    client_test_fill_root(&client.state.latest_block_header.state_root, 0x10);
    client_test_fill_root(&client.state.latest_block_header.body_root, 0x11);
    client_test_fill_root(&client.state.latest_block_header.parent_root, 0x12);
    client.state.latest_block_header.slot = anchor_slot;
    client.state.latest_block_header.proposer_index = 0;

    if (lantern_hash_tree_root_block_header(&client.state.latest_block_header, &head_root) != SSZ_SUCCESS) {
        fprintf(stderr, "failed to hash latest block header\n");
        rc = 1;
        goto cleanup;
    }


    LanternCheckpoint anchor_checkpoint = {
        .root = head_root,
        .slot = anchor_slot,
    };
    client.state.latest_justified = anchor_checkpoint;
    memset(&client.state.latest_finalized, 0, sizeof(client.state.latest_finalized));

    LanternBlock anchor_block;
    memset(&anchor_block, 0, sizeof(anchor_block));
    lantern_block_body_init(&anchor_block.body);
    anchor_block.slot = anchor_slot;
    anchor_block.proposer_index = 0;
    anchor_block.parent_root = client.state.latest_block_header.parent_root;
    anchor_block.state_root = client.state.latest_block_header.state_root;

    if (lantern_fork_choice_set_anchor_with_state(
            &client.store,
            &anchor_block,
            &anchor_checkpoint,
            &anchor_checkpoint,
            &head_root,
            &client.state)
        != 0) {
        fprintf(stderr, "failed to set fork choice anchor\n");
        lantern_block_body_reset(&anchor_block.body);
        rc = 1;
        goto cleanup;
    }

    LanternBlock finalized_block;
    memset(&finalized_block, 0, sizeof(finalized_block));
    lantern_block_body_init(&finalized_block.body);
    finalized_block.slot = finalized_slot;
    finalized_block.proposer_index = 0;
    client_test_fill_root(&finalized_block.parent_root, 0x43);
    client_test_fill_root(&finalized_block.state_root, 0x44);

    if (lantern_hash_tree_root_block(&finalized_block, &finalized_root) != SSZ_SUCCESS)
    {
        fprintf(stderr, "failed to hash finalized floor block\n");
        lantern_block_body_reset(&finalized_block.body);
        lantern_block_body_reset(&anchor_block.body);
        rc = 1;
        goto cleanup;
    }

    if (lantern_fork_choice_add_block(
            &client.store,
            &finalized_block,
            NULL,
            NULL,
            &finalized_root)
        != 0)
    {
        fprintf(stderr, "failed to add finalized floor block to fork choice\n");
        lantern_block_body_reset(&finalized_block.body);
        lantern_block_body_reset(&anchor_block.body);
        rc = 1;
        goto cleanup;
    }

    LanternCheckpoint finalized_checkpoint = {
        .root = finalized_root,
        .slot = finalized_slot,
    };
    if (lantern_fork_choice_restore_checkpoints(
            &client.store,
            &anchor_checkpoint,
            &finalized_checkpoint)
        != 0)
    {
        fprintf(stderr, "failed to restore finalized floor checkpoint\n");
        lantern_block_body_reset(&finalized_block.body);
        lantern_block_body_reset(&anchor_block.body);
        rc = 1;
        goto cleanup;
    }
    client.state.latest_justified = anchor_checkpoint;
    client.state.latest_finalized = finalized_checkpoint;
    lantern_block_body_reset(&finalized_block.body);
    lantern_block_body_reset(&anchor_block.body);

    lantern_block_body_init(&block.block.body);
    block.block.slot = finalized_slot + 1u;
    block.block.proposer_index = 0;
    client_test_fill_root(&parent_root, 0x20);
    if (memcmp(parent_root.bytes, head_root.bytes, LANTERN_ROOT_SIZE) == 0) {
        parent_root.bytes[0] ^= 0xFFu;
    }
    block.block.parent_root = parent_root;
    client_test_fill_root(&block.block.state_root, 0x30);
    if (lantern_hash_tree_root_block(&block.block, &block_root) != SSZ_SUCCESS) {
        fprintf(stderr, "failed to hash block with missing parent\n");
        rc = 1;
        goto cleanup;
    }

    if (lantern_client_pending_block_count(&client) != 0) {
        rc = 1;
        fprintf(stderr, "pending queue not empty at test start\n");
        goto cleanup;
    }

    if (reqresp_handle_block_response(
            &client,
            &block,
            "12D3KooWparent",
            0u)
        != LANTERN_CLIENT_OK) {
        fprintf(stderr, "reqresp rejected block accepted into pending queue\n");
        rc = 1;
        goto cleanup;
    }

    if (lantern_client_pending_block_count(&client) != 1) {
        fprintf(stderr, "pending queue count mismatch after missing parent response\n");
        rc = 1;
        goto cleanup;
    }

    memset(peer_text, 0, sizeof(peer_text));
    if (lantern_client_debug_pending_entry(
            &client,
            0,
            &pending_root,
            &pending_parent,
            peer_text,
            sizeof(peer_text))
        != 0) {
        fprintf(stderr, "failed to inspect pending entry after missing parent response\n");
        rc = 1;
        goto cleanup;
    }

    if (memcmp(pending_root.bytes, block_root.bytes, LANTERN_ROOT_SIZE) != 0) {
        fprintf(stderr, "pending root mismatch after missing parent response\n");
        rc = 1;
        goto cleanup;
    }
    if (memcmp(pending_parent.bytes, parent_root.bytes, LANTERN_ROOT_SIZE) != 0) {
        fprintf(stderr, "pending parent root mismatch after missing parent response\n");
        rc = 1;
        goto cleanup;
    }
    lantern_client_debug_pending_reset(&client);
    block.block.slot = finalized_slot;
    client_test_fill_root(&parent_root, 0x21);
    block.block.parent_root = parent_root;
    client_test_fill_root(&block.block.state_root, 0x31);
    if (lantern_hash_tree_root_block(&block.block, &block_root) != SSZ_SUCCESS) {
        fprintf(stderr, "failed to hash finalized floor block response\n");
        rc = 1;
        goto cleanup;
    }
    if (reqresp_handle_block_response(
            &client,
            &block,
            "12D3KooWparent",
            0u)
        == LANTERN_CLIENT_OK) {
        fprintf(stderr, "reqresp accepted block at finalized floor\n");
        rc = 1;
        goto cleanup;
    }
    if (lantern_client_pending_block_count(&client) != 0) {
        fprintf(stderr, "finalized floor block should not enter pending queue\n");
        rc = 1;
        goto cleanup;
    }

cleanup:
    lantern_client_debug_pending_reset(&client);
    lantern_block_body_reset(&block.block.body);
    if (client.store.block_len > 0u) {
        lantern_fork_choice_reset(&client.store);
    }
    if (client.pending_lock_initialized) {
        pthread_mutex_destroy(&client.pending_lock);
        client.pending_lock_initialized = false;
    }
    if (client.state_lock_initialized) {
        pthread_mutex_destroy(&client.state_lock);
        client.state_lock_initialized = false;
    }
    if (client.state.validator_count > 0u) {
        lantern_state_reset(&client.state);
    }
    lantern_store_reset(&client.store);
    return rc;
}

static int test_reqresp_collect_blocks_pending_fallback(void) {
    struct lantern_client client;
    memset(&client, 0, sizeof(client));
    client.node_id = "test_reqresp_collect_pending";

    int rc = 0;
    char data_dir_template[] = "/tmp/lantern_reqresp_collect_XXXXXX";
    char *data_dir = mkdtemp(data_dir_template);
    if (!data_dir) {
        fprintf(stderr, "failed to create temporary data dir for reqresp collect test\n");
        return 1;
    }
    client.data_dir = data_dir;

    if (pthread_mutex_init(&client.pending_lock, NULL) != 0) {
        fprintf(stderr, "failed to initialize pending mutex for reqresp collect test\n");
        return 1;
    }
    client.pending_lock_initialized = true;
    lantern_client_debug_pending_reset(&client);

    LanternSignedBlock pending_block;
    memset(&pending_block, 0, sizeof(pending_block));
    lantern_block_body_init(&pending_block.block.body);
    pending_block.block.slot = 42;
    pending_block.block.proposer_index = 1;
    client_test_fill_root(&pending_block.block.parent_root, 0x44);
    client_test_fill_root(&pending_block.block.state_root, 0x55);

    LanternRoot pending_root;
    if (lantern_hash_tree_root_block(&pending_block.block, &pending_root) != SSZ_SUCCESS) {
        fprintf(stderr, "failed to hash pending block root for reqresp collect test\n");
        rc = 1;
        goto cleanup;
    }

    LanternRoot parent_root = pending_block.block.parent_root;
    if (lantern_client_debug_enqueue_pending_block(
            &client,
            &pending_block,
            &pending_root,
            &parent_root,
            NULL)
        != 0) {
        fprintf(stderr, "failed to enqueue pending block for reqresp collect test\n");
        rc = 1;
        goto cleanup;
    }

    LanternSignedBlockList collected = {0};
    int collect_rc = reqresp_collect_blocks(
        &client,
        &pending_root,
        1u,
        &collected);
    if (collect_rc != LANTERN_CLIENT_OK) {
        fprintf(stderr, "reqresp_collect_blocks failed for pending fallback rc=%d\n", collect_rc);
        lantern_signed_block_list_reset(&collected);
        rc = 1;
        goto cleanup;
    }
    if (collected.length != 1u) {
        fprintf(stderr, "reqresp_collect_blocks pending fallback returned %zu blocks (expected 1)\n", collected.length);
        lantern_signed_block_list_reset(&collected);
        rc = 1;
        goto cleanup;
    }

    LanternRoot collected_root;
    if (lantern_hash_tree_root_block(&collected.blocks[0].block, &collected_root) != SSZ_SUCCESS) {
        fprintf(stderr, "failed to hash collected block for reqresp fallback test\n");
        lantern_signed_block_list_reset(&collected);
        rc = 1;
        goto cleanup;
    }
    if (memcmp(collected_root.bytes, pending_root.bytes, LANTERN_ROOT_SIZE) != 0) {
        fprintf(stderr, "reqresp fallback returned wrong root\n");
        lantern_signed_block_list_reset(&collected);
        rc = 1;
        goto cleanup;
    }
    if (collected.blocks[0].block.slot != pending_block.block.slot) {
        fprintf(stderr, "reqresp fallback returned wrong slot\n");
        lantern_signed_block_list_reset(&collected);
        rc = 1;
        goto cleanup;
    }
    lantern_signed_block_list_reset(&collected);

cleanup:
    lantern_block_body_reset(&pending_block.block.body);
    lantern_client_debug_pending_reset(&client);
    if (client.pending_lock_initialized) {
        pthread_mutex_destroy(&client.pending_lock);
        client.pending_lock_initialized = false;
    }
    (void)rmdir(data_dir);
    return rc;
}

static int test_import_block_accepts_complete_proof(void)
{
    struct block_signature_fixture fixture;
    LanternSignedBlock block;
    LanternRoot block_root;
    uint64_t initial_slot = 0;
    int rc = 1;

    memset(&block, 0, sizeof(block));
    if (setup_block_signature_fixture(&fixture, "test_import_complete_proof") != 0) {
        fprintf(stderr, "failed to set up block proof fixture\n");
        return 1;
    }

    initial_slot = fixture.client.state.slot;
    if (build_signed_block_for_import(&fixture, true, true, &block, &block_root) != 0) {
        fprintf(stderr, "failed to build block proof fixture\n");
        goto cleanup;
    }

    if (lantern_client_debug_import_block(&fixture.client, &block, &block_root, "12D3KooWsig") != 1) {
        fprintf(stderr, "import rejected block with complete proof\n");
        goto cleanup;
    }
    if (fixture.client.state.slot != block.block.slot || fixture.client.state.slot == initial_slot) {
        fprintf(stderr, "state slot did not advance after importing block with complete proof\n");
        goto cleanup;
    }
    if (expect_recovered_block_payload(&fixture.client.store, &block, false, "canonical import")
        != 0) {
        goto cleanup;
    }
    rc = 0;

cleanup:
    lantern_signed_block_reset(&block);
    teardown_block_signature_fixture(&fixture);
    return rc;
}

static int test_import_block_rejects_duplicate_attestation_data(void)
{
    struct block_signature_fixture fixture;
    LanternSignedBlock block;
    LanternState transition_state;
    LanternRoot block_root;
    uint64_t initial_slot = 0;
    int rc = 1;

    memset(&block, 0, sizeof(block));
    lantern_state_init(&transition_state);
    if (setup_block_signature_fixture(&fixture, "test_import_duplicate_attestation_data") != 0) {
        fprintf(stderr, "failed to set up duplicate attestation data fixture\n");
        return 1;
    }

    initial_slot = fixture.client.state.slot;
    if (build_signed_block_for_import(&fixture, true, true, &block, &block_root) != 0
        || lantern_aggregated_attestations_resize(&block.block.body.attestations, 2u) != 0) {
        fprintf(stderr, "failed to build duplicate attestation data block\n");
        goto cleanup;
    }

    LanternAggregatedAttestation *first = &block.block.body.attestations.data[0];
    LanternAggregatedAttestation *duplicate = &block.block.body.attestations.data[1];
    duplicate->data = first->data;
    if (lantern_bitlist_resize(&duplicate->aggregation_bits, first->aggregation_bits.bit_length) != 0
        || lantern_bitlist_set(&duplicate->aggregation_bits, 0u, true) != 0
        || resign_matching_block_attestations(&fixture, &block, &block_root) != 0) {
        fprintf(stderr, "failed to sign duplicate attestation data block\n");
        goto cleanup;
    }

    if (lantern_state_clone(&fixture.client.state, &transition_state) != 0
        || lantern_state_transition(&transition_state, &block) != 0) {
        fprintf(stderr, "state transition rejected valid split aggregates\n");
        goto cleanup;
    }
    if (lantern_client_debug_import_block(&fixture.client, &block, &block_root, "12D3KooWsig") != 0) {
        fprintf(stderr, "import accepted duplicate attestation data\n");
        goto cleanup;
    }
    if (fixture.client.state.slot != initial_slot) {
        fprintf(stderr, "state slot advanced after rejecting duplicate attestation data\n");
        goto cleanup;
    }

    rc = 0;

cleanup:
    lantern_state_reset(&transition_state);
    lantern_signed_block_reset(&block);
    teardown_block_signature_fixture(&fixture);
    return rc;
}

static int test_import_persists_finalized_post_state(void)
{
    struct block_signature_fixture fixture;
    LanternCheckpoint initial_finalized;
    LanternCheckpoint advanced_finalized = {0};
    bool finalized_advanced = false;
    int rc = 1;

    if (setup_block_signature_fixture(&fixture, "test_finalized_post_state") != 0) {
        fprintf(stderr, "failed to set up finalized post-state fixture\n");
        return 1;
    }

    initial_finalized = fixture.client.state.latest_finalized;
    fixture.client.network_view.finalized = initial_finalized;

    LanternRoot initial_head_root;
    if (test_state_latest_block_root(&fixture.client.state, &initial_head_root) != 0) {
        fprintf(stderr, "failed to compute initial head root for post-state test\n");
        goto cleanup;
    }
    if (fixture.client.store.block_len > 0u
        && lantern_fork_choice_set_block_state(
               &fixture.client.store,
               &initial_head_root,
               &fixture.client.state)
            != 0) {
        fprintf(stderr, "failed to seed initial head state for post-state test\n");
        goto cleanup;
    }
    if (lantern_storage_store_state_for_root(
            &fixture.client.storage,
            &initial_head_root,
            &fixture.client.state)
        != 0) {
        fprintf(stderr, "failed to persist initial head state for post-state test\n");
        goto cleanup;
    }

    for (size_t i = 0; i < 12u && !finalized_advanced; ++i) {
        LanternSignedBlock block;
        LanternRoot block_root;
        memset(&block, 0, sizeof(block));
        if (build_signed_block_for_import(&fixture, true, true, &block, &block_root) != 0) {
            fprintf(stderr, "failed to build block for finalized post-state test\n");
            lantern_signed_block_reset(&block);
            goto cleanup;
        }
        if (lantern_client_debug_import_block(&fixture.client, &block, &block_root, "12D3KooWbase") != 1) {
            fprintf(stderr, "failed to import block for finalized post-state test\n");
            lantern_signed_block_reset(&block);
            goto cleanup;
        }
        lantern_signed_block_reset(&block);
        if (fixture.client.state.latest_finalized.slot > initial_finalized.slot) {
            advanced_finalized = fixture.client.state.latest_finalized;
            finalized_advanced = true;
        }
    }

    if (!finalized_advanced) {
        fprintf(stderr, "finalized checkpoint did not advance in post-state test\n");
        goto cleanup;
    }
    if (fixture.client.network_view.finalized.slot != advanced_finalized.slot
        || memcmp(
               fixture.client.network_view.finalized.root.bytes,
               advanced_finalized.root.bytes,
               LANTERN_ROOT_SIZE)
            != 0) {
        fprintf(stderr, "network finalized view did not refresh after finalized import\n");
        goto cleanup;
    }

    uint8_t *state_bytes = NULL;
    size_t state_len = 0u;
    if (lantern_storage_load_state_bytes_for_root(
            &fixture.client.storage,
            &advanced_finalized.root,
            &state_bytes,
            &state_len)
        != 0) {
        fprintf(stderr, "finalized root state snapshot missing after prune\n");
        free(state_bytes);
        goto cleanup;
    }

    LanternState keyed_state;
    lantern_state_init(&keyed_state);
    if (lantern_ssz_decode_state(&keyed_state, state_bytes, state_len) != SSZ_SUCCESS) {
        fprintf(stderr, "failed to decode finalized root state snapshot\n");
        free(state_bytes);
        lantern_state_reset(&keyed_state);
        goto cleanup;
    }
    free(state_bytes);
    if (!test_state_matches_root(&keyed_state, &advanced_finalized.root)) {
        fprintf(stderr, "finalized root state snapshot does not match finalized root\n");
        lantern_state_reset(&keyed_state);
        goto cleanup;
    }
    lantern_state_reset(&keyed_state);

    rc = 0;

cleanup:
    teardown_block_signature_fixture(&fixture);
    return rc;
}

static int test_retained_side_branch_reloads_evicted_parent_state(void)
{
    struct block_signature_fixture fixture;
    LanternSignedBlock branch_a;
    LanternSignedBlock branch_b;
    LanternSignedBlock side_child;
    LanternState branch_a_state;
    LanternState branch_b_state;
    LanternState side_child_state;
    LanternRoot parent_root = {0};
    LanternRoot branch_a_root = {0};
    LanternRoot branch_b_root = {0};
    LanternRoot side_child_root = {0};
    int rc = 1;

    memset(&branch_a, 0, sizeof(branch_a));
    memset(&branch_b, 0, sizeof(branch_b));
    memset(&side_child, 0, sizeof(side_child));
    lantern_state_init(&branch_a_state);
    lantern_state_init(&branch_b_state);
    lantern_state_init(&side_child_state);

    if (setup_block_signature_fixture(&fixture, "test_retained_side_branch_state") != 0) {
        fprintf(stderr, "failed to set up retained side-branch fixture\n");
        return 1;
    }

    LanternState parent_state;
    lantern_state_init(&parent_state);
    if (lantern_state_clone(&fixture.client.state, &parent_state) != 0
        || test_state_latest_block_root(&parent_state, &parent_root) != 0) {
        fprintf(stderr, "failed to capture retained side-branch parent state\n");
        goto cleanup_parent;
    }

    if (build_proposer_only_block_for_parent(
            &fixture,
            &parent_state,
            &parent_root,
            parent_state.slot + 1u,
            &branch_a,
            &branch_a_root,
            &branch_a_state)
            != 0
        || build_proposer_only_block_for_parent(
               &fixture,
               &parent_state,
               &parent_root,
               parent_state.slot + 2u,
               &branch_b,
               &branch_b_root,
               &branch_b_state)
               != 0) {
        fprintf(stderr, "failed to build retained sibling branches\n");
        goto cleanup_parent;
    }

    if (lantern_fork_choice_add_block_with_state(
            &fixture.client.store,
            &branch_a.block,
            &branch_a_state.latest_justified,
            &branch_a_state.latest_finalized,
            &branch_a_root,
            &branch_a_state)
            != 0
        || lantern_fork_choice_add_block_with_state(
               &fixture.client.store,
               &branch_b.block,
               &branch_b_state.latest_justified,
               &branch_b_state.latest_finalized,
               &branch_b_root,
               &branch_b_state)
               != 0
        || lantern_storage_store_state_for_root(
               &fixture.client.storage,
               &branch_a_root,
               &branch_a_state)
               != 0
        || lantern_storage_store_state_for_root(
               &fixture.client.storage,
               &branch_b_root,
               &branch_b_state)
               != 0) {
        fprintf(stderr, "failed to seed retained sibling branch states\n");
        goto cleanup_parent;
    }

    LanternCheckpoint parent_checkpoint = {
        .root = parent_root,
        .slot = parent_state.slot,
    };
    if (lantern_fork_choice_update_checkpoints(
            &fixture.client.store,
            &parent_checkpoint,
            &parent_checkpoint)
            != 0) {
        fprintf(stderr, "failed to advance retained side-branch finalization\n");
        goto cleanup_parent;
    }

    LanternRoot selected_head = fixture.client.store.head;

    const LanternRoot *side_root = NULL;
    const LanternState *side_state = NULL;
    if (memcmp(selected_head.bytes, branch_a_root.bytes, LANTERN_ROOT_SIZE) == 0) {
        side_root = &branch_b_root;
        side_state = &branch_b_state;
    } else if (memcmp(selected_head.bytes, branch_b_root.bytes, LANTERN_ROOT_SIZE) == 0) {
        side_root = &branch_a_root;
        side_state = &branch_a_state;
    } else {
        fprintf(stderr, "fork choice did not select either retained sibling branch\n");
        goto cleanup_parent;
    }

    if (lantern_fork_choice_prune_states(&fixture.client.store) != 0
        || lantern_fork_choice_block_info(
               &fixture.client.store,
               side_root,
               NULL,
               NULL,
               NULL)
               != 0) {
        fprintf(stderr, "retained side branch was removed during state pruning\n");
        goto cleanup_parent;
    }
    if (lantern_fork_choice_block_state(&fixture.client.store, side_root) != NULL) {
        fprintf(stderr, "retained side-branch state was not evicted by pruning\n");
        goto cleanup_parent;
    }

    uint8_t *persisted_bytes = NULL;
    size_t persisted_len = 0u;
    if (lantern_storage_load_state_bytes_for_root(
            &fixture.client.storage,
            side_root,
            &persisted_bytes,
            &persisted_len)
            != 0
        || !persisted_bytes
        || persisted_len == 0u) {
        free(persisted_bytes);
        fprintf(stderr, "retained side-branch state was not available on disk\n");
        goto cleanup_parent;
    }
    free(persisted_bytes);

    if (build_proposer_only_block_for_parent(
            &fixture,
            side_state,
            side_root,
            side_state->slot + 1u,
            &side_child,
            &side_child_root,
            &side_child_state)
            != 0) {
        fprintf(stderr, "failed to build valid retained side-branch child\n");
        goto cleanup_parent;
    }
    (void)lantern_client_debug_import_block(
        &fixture.client,
        &side_child,
        &side_child_root,
        "12D3KooWretained");
    if (lantern_fork_choice_block_info(
            &fixture.client.store,
            &side_child_root,
            NULL,
            NULL,
            NULL)
            != 0
        || !lantern_fork_choice_block_state(&fixture.client.store, side_root)
        || !lantern_fork_choice_block_state(&fixture.client.store, &side_child_root)) {
        fprintf(stderr, "valid retained side-branch child or its post-state was not imported\n");
        goto cleanup_parent;
    }

    rc = 0;

cleanup_parent:
    lantern_state_reset(&parent_state);
    lantern_state_reset(&side_child_state);
    lantern_state_reset(&branch_b_state);
    lantern_state_reset(&branch_a_state);
    lantern_signed_block_reset(&side_child);
    lantern_signed_block_reset(&branch_b);
    lantern_signed_block_reset(&branch_a);
    teardown_block_signature_fixture(&fixture);
    return rc;
}

static int test_historical_backfill_imports_after_large_gap_connects(void)
{
    struct block_signature_fixture target;
    LanternSignedBlock block;
    LanternRoot root;
    bool target_ready = false;
    int rc = 1;

    memset(&block, 0, sizeof(block));
    if (setup_block_signature_fixture(&target, "test_backfill_target") != 0) {
        fprintf(stderr, "failed to set up target fixture\n");
        goto cleanup;
    }
    target_ready = true;
    if (pthread_mutex_init(&target.client.pending_lock, NULL) != 0) {
        fprintf(stderr, "failed to initialize target pending mutex\n");
        goto cleanup;
    }
    target.client.pending_lock_initialized = true;
    if (pthread_mutex_init(&target.client.status_lock, NULL) != 0) {
        fprintf(stderr, "failed to initialize target status mutex\n");
        goto cleanup;
    }
    target.client.status_lock_initialized = true;

    if (build_signed_block_for_import(&target, true, true, &block, &root) != 0) {
        fprintf(stderr, "failed to build backfill block\n");
        goto cleanup;
    }

    uint64_t local_head_slot = target.client.state.slot;
    uint64_t anchor_slot = target.client.store.block_len > 0u
        ? target.client.store.anchor.slot
        : local_head_slot;
    uint64_t peer_reported_head_slot = anchor_slot + LANTERN_PENDING_BLOCK_LIMIT + 1u;
    if (!lantern_client_ensure_historical_backfill(
            &target.client,
            "12D3KooWbackfill",
            &root,
            peer_reported_head_slot,
            local_head_slot)) {
        fprintf(stderr, "large-gap backfill session did not start\n");
        goto cleanup;
    }
    if (set_single_active_blocks_request_for_test(
            &target.client,
            1u,
            "12D3KooWbackfill",
            &root,
            &root)
        != 0) {
        goto cleanup;
    }

    if (reqresp_handle_block_response(
            &target.client,
            &block,
            "12D3KooWbackfill",
            1u) != LANTERN_CLIENT_OK) {
        fprintf(stderr, "reqresp backfill did not accept fetched head block\n");
        goto cleanup;
    }

    if (target.client.state.slot != block.block.slot) {
        fprintf(
            stderr,
            "backfill did not import connected chain: got slot %" PRIu64 " want %" PRIu64 "\n",
            target.client.state.slot,
            block.block.slot);
        goto cleanup;
    }
    if (!lantern_root_is_zero(&target.client.backfill.head.root)) {
        fprintf(stderr, "backfill session remained active after importing head\n");
        goto cleanup;
    }
    if (lantern_client_pending_block_count(&target.client) != 0) {
        fprintf(stderr, "backfill should not populate pending block queue\n");
        goto cleanup;
    }

    rc = 0;

cleanup:
    lantern_signed_block_reset(&block);
    if (target_ready) {
        free(target.client.backfill.roots);
        target.client.backfill = (struct lantern_backfill_session){0};
        disable_sync_test_peer(&target.client);
        teardown_block_signature_fixture(&target);
    }
    return rc;
}

static int run_historical_backfill_retry_completion(
    enum lantern_blocks_request_outcome outcome)
{
    struct lantern_client client;
    const char *peer_id = "16Uiu2HAmQj1RDNAxopeeeCFPRr3zhJYmH6DEPHYKmxLViLahWcFE";
    LanternRoot session_head;
    LanternRoot observed_frontier;
    LanternRoot observed_session_head;
    int rc = 1;

    memset(&client, 0, sizeof(client));
    client.node_id = "historical_backfill_retry";
    if (enable_sync_test_peer(&client, peer_id) != 0) {
        return 1;
    }

    if (pthread_mutex_lock(&client.status_lock) != 0) {
        goto cleanup;
    }
    struct lantern_peer_status_entry *peer =
        lantern_client_ensure_status_entry_locked(&client, peer_id);
    pthread_mutex_unlock(&client.status_lock);
    if (!peer) {
        goto cleanup;
    }

    client_test_fill_root(&session_head, 0xF1u);
    uint64_t anchor_slot = client.store.block_len > 0u
        ? client.store.anchor.slot
        : client.state.slot;
    if (!lantern_client_ensure_historical_backfill(
            &client,
            peer_id,
            &session_head,
            anchor_slot + LANTERN_PENDING_BLOCK_LIMIT + 1u,
            client.state.slot)
        || set_single_active_blocks_request_for_test(
               &client,
               21u,
               peer_id,
               &session_head,
               &session_head)
               != 0
        || set_single_block_fetch_for_test(&client, &session_head, &session_head, 1u) != 0) {
        goto cleanup;
    }
    client.next_blocks_request_id = 22u;

    libp2p_host_time_us_t before_us = lantern_libp2p_now_us();
    lantern_client_on_blocks_request_complete_batch_with_id(
        &client,
        21u,
        peer_id,
        outcome);
    libp2p_host_time_us_t after_us = lantern_libp2p_now_us();

    if (client.next_blocks_request_id != 22u || client.active_blocks_request_count != 0u) {
        fprintf(stderr, "historical failure retried before its backoff elapsed\n");
        goto cleanup;
    }
    if (client.block_fetch_count != 1u || client.block_fetches[0].attempts != 1u
        || client.block_fetches[0].failed_peer_count != 1u
        || strcmp(client.block_fetches[0].failed_peers[0], peer_id) != 0) {
        fprintf(stderr, "historical failure did not update its root-scoped lifecycle\n");
        goto cleanup;
    }
    libp2p_host_time_us_t retry_at_us = client.block_fetches[0].retry_at_us;
    if (retry_at_us < before_us + LANTERN_BLOCK_FETCH_INITIAL_BACKOFF_US
        || retry_at_us > after_us + LANTERN_BLOCK_FETCH_INITIAL_BACKOFF_US) {
        fprintf(stderr, "historical failure used the wrong initial backoff\n");
        goto cleanup;
    }
    if (!lantern_client_historical_backfill_snapshot(
            &client,
            &observed_frontier,
            &observed_session_head)
        || memcmp(observed_frontier.bytes, session_head.bytes, LANTERN_ROOT_SIZE) != 0
        || memcmp(observed_session_head.bytes, session_head.bytes, LANTERN_ROOT_SIZE) != 0) {
        fprintf(stderr, "historical retry changed the active frontier\n");
        goto cleanup;
    }
    rc = 0;

cleanup:
    free(client.backfill.roots);
    client.backfill = (struct lantern_backfill_session){0};
    disable_sync_test_peer(&client);
    return rc;
}

static int test_historical_backfill_failed_and_empty_completions_retry(void)
{
    if (run_historical_backfill_retry_completion(LANTERN_BLOCKS_REQUEST_FAILED) != 0) {
        return 1;
    }
    return run_historical_backfill_retry_completion(LANTERN_BLOCKS_REQUEST_EMPTY);
}

static int test_block_fetch_retry_rotates_root_scoped_failed_peers(void)
{
    struct lantern_client client;
    const char *peer_a = "16Uiu2HAmQj1RDNAxopeeeCFPRr3zhJYmH6DEPHYKmxLViLahWcFE";
    const char *peer_b = "16Uiu2HAkutTMoTzDw1tCvSRtu6YoixJwS46S1ZFxW8hSx9fWHiPs";
    LanternRoot root;
    char selected[128];
    int rc = 1;

    memset(&client, 0, sizeof(client));
    client.node_id = "root_scoped_peer_rotation";
    if (enable_sync_test_peer(&client, peer_a) != 0
        || set_sync_test_connected_peers(&client, peer_a, peer_b) != 0) {
        goto cleanup;
    }
    client_test_fill_root(&root, 0x71u);
    if (set_single_block_fetch_for_test(&client, &root, NULL, 1u) != 0) {
        goto cleanup;
    }
    (void)snprintf(
        client.block_fetches[0].failed_peers[0],
        sizeof(client.block_fetches[0].failed_peers[0]),
        "%s",
        peer_a);
    client.block_fetches[0].failed_peer_count = 1u;

    if (pthread_mutex_lock(&client.status_lock) != 0) {
        goto cleanup;
    }
    struct lantern_peer_status_entry *status_a =
        lantern_client_ensure_status_entry_locked(&client, peer_a);
    struct lantern_peer_status_entry *status_b =
        lantern_client_ensure_status_entry_locked(&client, peer_b);
    if (status_a) {
        status_a->last_status_ms = 200u;
    }
    if (status_b) {
        status_b->last_status_ms = 100u;
    }
    bool selected_ok = status_a && status_b
        && lantern_client_select_blocks_request_peer_locked(
            &client,
            peer_a,
            &root,
            1000u,
            selected,
            sizeof(selected));
    pthread_mutex_unlock(&client.status_lock);
    if (!selected_ok || strcmp(selected, peer_b) != 0) {
        fprintf(stderr, "retry did not exclude the peer that failed this root\n");
        goto cleanup;
    }

    (void)snprintf(
        client.block_fetches[0].failed_peers[1],
        sizeof(client.block_fetches[0].failed_peers[1]),
        "%s",
        peer_b);
    client.block_fetches[0].failed_peer_count = 2u;
    if (pthread_mutex_lock(&client.status_lock) != 0) {
        goto cleanup;
    }
    selected_ok = lantern_client_select_blocks_request_peer_locked(
        &client,
        peer_a,
        &root,
        1000u,
        selected,
        sizeof(selected));
    pthread_mutex_unlock(&client.status_lock);
    if (!selected_ok || strcmp(selected, peer_a) != 0
        || client.block_fetches[0].failed_peer_count != 0u) {
        fprintf(stderr, "retry did not reset exclusions after all peers failed\n");
        goto cleanup;
    }
    rc = 0;

cleanup:
    disable_sync_test_peer(&client);
    return rc;
}

static int test_block_fetch_exponential_backoff_and_attempt_exhaustion(void)
{
    static const libp2p_host_time_us_t expected_backoffs_us[] = {
        5000u,
        10000u,
        20000u,
        40000u,
        80000u,
        160000u,
        320000u,
        640000u,
        1280000u,
    };
    struct lantern_client client;
    const char *peer_id = "16Uiu2HAmQj1RDNAxopeeeCFPRr3zhJYmH6DEPHYKmxLViLahWcFE";
    LanternRoot root;
    int rc = 1;

    memset(&client, 0, sizeof(client));
    client.node_id = "root_fetch_attempts";
    if (LANTERN_BLOCK_FETCH_MAX_ATTEMPTS != 10u) {
        fprintf(stderr, "root fetch lifecycle must stop after ten attempts\n");
        return 1;
    }
    if (enable_sync_test_peer(&client, peer_id) != 0) {
        return 1;
    }
    client_test_fill_root(&root, 0x72u);
    if (set_single_block_fetch_for_test(&client, &root, NULL, 1u) != 0) {
        goto cleanup;
    }

    for (uint32_t attempt = 1u; attempt <= LANTERN_BLOCK_FETCH_MAX_ATTEMPTS; ++attempt) {
        uint64_t request_id = 100u + attempt;
        client.block_fetches[0].attempts = attempt;
        client.block_fetches[0].retry_at_us = 0u;
        if (set_single_active_blocks_request_for_test(
                &client,
                request_id,
                peer_id,
                &root,
                NULL)
            != 0) {
            goto cleanup;
        }

        libp2p_host_time_us_t before_us = lantern_libp2p_now_us();
        lantern_client_on_blocks_request_complete_batch_with_id(
            &client,
            request_id,
            peer_id,
            LANTERN_BLOCKS_REQUEST_FAILED);
        libp2p_host_time_us_t after_us = lantern_libp2p_now_us();
        if (client.active_blocks_request_count != 0u) {
            fprintf(stderr, "completed retry attempt remained active\n");
            goto cleanup;
        }
        if (attempt == LANTERN_BLOCK_FETCH_MAX_ATTEMPTS) {
            if (client.block_fetch_count != 0u) {
                fprintf(stderr, "exhausted root lifecycle was not removed\n");
                goto cleanup;
            }
            break;
        }
        libp2p_host_time_us_t expected_delay = expected_backoffs_us[attempt - 1u];
        if (client.block_fetch_count != 1u
            || client.block_fetches[0].retry_at_us < before_us + expected_delay
            || client.block_fetches[0].retry_at_us > after_us + expected_delay) {
            fprintf(stderr, "attempt %u used the wrong exponential backoff\n", attempt);
            goto cleanup;
        }
    }
    rc = 0;

cleanup:
    disable_sync_test_peer(&client);
    return rc;
}

static int test_block_fetch_lifecycle_cleans_up_on_success_and_session_replacement(void)
{
    struct lantern_client client;
    const char *peer_id = "16Uiu2HAmQj1RDNAxopeeeCFPRr3zhJYmH6DEPHYKmxLViLahWcFE";
    LanternRoot root;
    LanternRoot old_session;
    LanternRoot replacement;
    int rc = 1;

    memset(&client, 0, sizeof(client));
    client.node_id = "root_fetch_cleanup";
    if (enable_sync_test_peer(&client, peer_id) != 0) {
        return 1;
    }
    client_test_fill_root(&root, 0x73u);
    if (set_single_block_fetch_for_test(&client, &root, NULL, 2u) != 0
        || set_single_active_blocks_request_for_test(
               &client,
               201u,
               peer_id,
               &root,
               NULL)
            != 0) {
        goto cleanup;
    }
    lantern_client_on_blocks_request_complete_batch_with_id(
        &client,
        201u,
        peer_id,
        LANTERN_BLOCKS_REQUEST_SUCCESS);
    if (client.block_fetch_count != 0u || client.active_blocks_request_count != 0u) {
        fprintf(stderr, "successful root fetch did not clear its lifecycle\n");
        goto cleanup;
    }

    client_test_fill_root(&old_session, 0x74u);
    client_test_fill_root(&replacement, 0x75u);
    if (set_single_block_fetch_for_test(&client, &old_session, &old_session, 1u) != 0) {
        goto cleanup;
    }
    client.block_fetches[0].retry_at_us = 1u;
    if (pthread_mutex_lock(&client.pending_lock) != 0) {
        goto cleanup;
    }
    client.backfill = (struct lantern_backfill_session){
        .head = {.root = replacement, .slot = LANTERN_PENDING_BLOCK_LIMIT + 2u},
        .frontier_root = replacement,
    };
    pthread_mutex_unlock(&client.pending_lock);
    client.next_blocks_request_id = 202u;
    lantern_client_drive_block_fetch_retries(&client, 1u);
    if (client.block_fetch_count != 0u || client.next_blocks_request_id != 202u) {
        fprintf(stderr, "stale historical lifecycle survived session replacement\n");
        goto cleanup;
    }

    if (set_single_block_fetch_for_test(&client, &replacement, &replacement, 1u) != 0
        || set_single_active_blocks_request_for_test(
               &client,
               203u,
               peer_id,
               &replacement,
               &replacement)
            != 0) {
        goto cleanup;
    }
    lantern_client_on_blocks_request_complete_batch_with_id(
        &client,
        201u,
        peer_id,
        LANTERN_BLOCKS_REQUEST_FAILED);
    if (client.block_fetch_count != 1u || client.block_fetches[0].attempts != 1u
        || client.block_fetches[0].failed_peer_count != 0u
        || client.block_fetches[0].retry_at_us != 0u
        || client.active_blocks_request_count != 1u) {
        fprintf(stderr, "stale completion mutated the replacement root lifecycle\n");
        goto cleanup;
    }
    rc = 0;

cleanup:
    free(client.backfill.roots);
    client.backfill = (struct lantern_backfill_session){0};
    disable_sync_test_peer(&client);
    return rc;
}

static int test_advancing_status_preserves_historical_backfill_frontier(void)
{
    struct lantern_client client;
    const char *peer_id = "16Uiu2HAmQj1RDNAxopeeeCFPRr3zhJYmH6DEPHYKmxLViLahWcFE";
    LanternRoot initial_head;
    LanternRoot frontier;
    LanternRoot latest_status_head = {0};
    uint64_t anchor_slot = 0u;
    uint64_t initial_head_slot = 0u;
    int rc = 1;

    memset(&client, 0, sizeof(client));
    client.node_id = "advancing_status_backfill";
    if (enable_sync_test_peer(&client, peer_id) != 0) {
        fprintf(stderr, "failed to enable advancing-status peer\n");
        goto cleanup;
    }

    client_test_fill_root(&initial_head, 0xA1u);
    client_test_fill_root(&frontier, 0xB1u);
    anchor_slot = client.store.block_len > 0u ? client.store.anchor.slot : client.state.slot;
    initial_head_slot = anchor_slot + LANTERN_PENDING_BLOCK_LIMIT + 32u;
    if (!lantern_client_ensure_historical_backfill(
            &client,
            peer_id,
            &initial_head,
            initial_head_slot,
            client.state.slot)) {
        fprintf(stderr, "failed to start advancing-status backfill\n");
        goto cleanup;
    }

    if (pthread_mutex_lock(&client.pending_lock) != 0) {
        fprintf(stderr, "failed to lock advancing-status backfill\n");
        goto cleanup;
    }
    client.backfill.roots = calloc(3u, sizeof(*client.backfill.roots));
    if (!client.backfill.roots) {
        pthread_mutex_unlock(&client.pending_lock);
        goto cleanup;
    }
    client.backfill.roots[0] = initial_head;
    client_test_fill_root(&client.backfill.roots[1], 0xA2u);
    client_test_fill_root(&client.backfill.roots[2], 0xA3u);
    client.backfill.length = 3u;
    client.backfill.capacity = 3u;
    client.backfill.frontier_root = frontier;
    client.backfill.frontier_depth = 3u;
    pthread_mutex_unlock(&client.pending_lock);

    if (set_single_active_blocks_request_for_test(
            &client,
            40u,
            "12D3KooWother",
            &frontier,
            &initial_head)
        != 0) {
        goto cleanup;
    }
    client.next_blocks_request_id = 41u;

    for (uint32_t step = 1u; step <= 3u; ++step) {
        LanternStatusMessage status = {0};
        client_test_fill_root_with_index(&latest_status_head, 0xC000u + step);
        status.head.root = latest_status_head;
        status.head.slot = initial_head_slot + step;
        status.finalized = client.store.latest_finalized;
        if (reqresp_handle_status(&client, &status, peer_id) != LANTERN_CLIENT_OK) {
            fprintf(stderr, "advancing peer status update failed\n");
            goto cleanup;
        }

        LanternRoot observed_frontier;
        LanternRoot observed_session_head;
        if (!lantern_client_historical_backfill_snapshot(
                &client,
                &observed_frontier,
                &observed_session_head)
            || memcmp(observed_frontier.bytes, frontier.bytes, LANTERN_ROOT_SIZE) != 0
            || client.backfill.frontier_depth != 3u
            || memcmp(observed_session_head.bytes, initial_head.bytes, LANTERN_ROOT_SIZE) != 0
            || memcmp(client.backfill.head.root.bytes, initial_head.bytes, LANTERN_ROOT_SIZE) != 0
            || client.backfill.head.slot != initial_head_slot
            || client.backfill.length != 3u) {
            fprintf(stderr, "advancing status replaced historical backfill progress\n");
            goto cleanup;
        }
        if (client.next_blocks_request_id != 41u) {
            fprintf(stderr, "advancing status requested a new tip instead of the active frontier\n");
            goto cleanup;
        }
    }

    if (memcmp(client.network_view.head.root.bytes, latest_status_head.bytes, LANTERN_ROOT_SIZE) != 0
        || client.network_view.head.slot != initial_head_slot + 3u) {
        fprintf(stderr, "advancing statuses did not extend the network target\n");
        goto cleanup;
    }
    rc = 0;

cleanup:
    free(client.backfill.roots);
    client.backfill.roots = NULL;
    client.backfill.length = 0u;
    client.backfill.capacity = 0u;
    disable_sync_test_peer(&client);
    return rc;
}

static int test_stale_async_backfill_completion_is_discarded(void)
{
    struct block_signature_fixture fixture;
    LanternSignedBlock stale_block;
    LanternRoot stale_root;
    LanternRoot stale_frontier;
    LanternRoot stale_session_head = {0};
    LanternRoot replacement_root;
    LanternSignedBlockList stored = {0};
    const char *peer_id = "16Uiu2HAmQj1RDNAxopeeeCFPRr3zhJYmH6DEPHYKmxLViLahWcFE";
    bool fixture_ready = false;
    bool peer_ready = false;
    bool importer_started = false;
    int rc = 1;

    memset(&stale_block, 0, sizeof(stale_block));
    if (setup_block_signature_fixture(&fixture, "stale_async_backfill") != 0) {
        fprintf(stderr, "failed to set up stale async fixture\n");
        return 1;
    }
    fixture_ready = true;
    if (enable_sync_test_peer(&fixture.client, peer_id) != 0) {
        fprintf(stderr, "failed to enable stale async peer\n");
        goto cleanup;
    }
    peer_ready = true;

    lantern_block_body_init(&stale_block.block.body);
    stale_block.block.slot = fixture.client.state.slot + 1u;
    stale_block.block.proposer_index = 0u;
    stale_block.block.parent_root = fixture.client.store.head;
    client_test_fill_root(&stale_block.block.state_root, 0xD1u);
    if (lantern_hash_tree_root_block(&stale_block.block, &stale_root) != SSZ_SUCCESS) {
        fprintf(stderr, "failed to hash stale async block\n");
        goto cleanup;
    }

    uint64_t anchor_slot = fixture.client.store.block_len > 0u
        ? fixture.client.store.anchor.slot
        : fixture.client.state.slot;
    if (!lantern_client_ensure_historical_backfill(
            &fixture.client,
            peer_id,
            &stale_root,
            anchor_slot + LANTERN_PENDING_BLOCK_LIMIT + 1u,
            fixture.client.state.slot)
        || !lantern_client_historical_backfill_snapshot(
            &fixture.client,
            &stale_frontier,
            &stale_session_head)) {
        fprintf(stderr, "failed to start stale async backfill\n");
        goto cleanup;
    }
    if (memcmp(stale_frontier.bytes, stale_root.bytes, LANTERN_ROOT_SIZE) != 0) {
        fprintf(stderr, "stale async request did not capture the active frontier\n");
        goto cleanup;
    }

    if (set_single_active_blocks_request_for_test(
            &fixture.client,
            1u,
            peer_id,
            &stale_root,
            &stale_session_head)
        != 0) {
        goto cleanup;
    }

    if (lantern_client_block_importer_start(&fixture.client) != LANTERN_CLIENT_OK) {
        fprintf(stderr, "failed to start async block importer\n");
        goto cleanup;
    }
    importer_started = true;
    if (pthread_mutex_lock(&fixture.client.pending_lock) != 0) {
        fprintf(stderr, "failed to lock stale async session\n");
        goto cleanup;
    }
    client_test_fill_root(&replacement_root, 0xE1u);
    free(fixture.client.backfill.roots);
    fixture.client.backfill = (struct lantern_backfill_session){
        .head = {.root = replacement_root, .slot = anchor_slot + LANTERN_PENDING_BLOCK_LIMIT + 2u},
        .frontier_root = replacement_root,
        .anchor_slot = anchor_slot,
    };
    pthread_mutex_unlock(&fixture.client.pending_lock);
    if (reqresp_handle_block_response(&fixture.client, &stale_block, peer_id, 1u)
        != LANTERN_CLIENT_OK) {
        fprintf(stderr, "failed to enqueue stale async response\n");
        goto cleanup;
    }
    lantern_client_block_importer_stop(&fixture.client);
    importer_started = false;

    if (memcmp(fixture.client.backfill.head.root.bytes, replacement_root.bytes, LANTERN_ROOT_SIZE)
            != 0
        || memcmp(
               fixture.client.backfill.frontier_root.bytes,
               replacement_root.bytes,
               LANTERN_ROOT_SIZE)
            != 0
        || fixture.client.backfill.length != 0u
        || lantern_client_pending_block_count(&fixture.client) != 0u) {
        fprintf(stderr, "stale async response mutated the replacement session\n");
        goto cleanup;
    }
    if (lantern_storage_collect_blocks(&fixture.client.storage, &stale_root, 1u, &stored) != 0
        || stored.length != 0u) {
        fprintf(stderr, "stale async response was persisted after cancellation\n");
        goto cleanup;
    }
    lantern_client_on_blocks_request_complete_batch_with_id(
        &fixture.client,
        1u,
        peer_id,
        LANTERN_BLOCKS_REQUEST_SUCCESS);
    if (fixture.client.active_blocks_request_count != 0u
        || reqresp_handle_block_response(&fixture.client, &stale_block, peer_id, 1u)
            != LANTERN_CLIENT_OK) {
        fprintf(stderr, "response for a completed historical request was not discarded\n");
        goto cleanup;
    }
    rc = 0;

cleanup:
    if (importer_started) {
        lantern_client_block_importer_stop(&fixture.client);
    }
    lantern_signed_block_list_reset(&stored);
    lantern_signed_block_reset(&stale_block);
    if (fixture_ready) {
        free(fixture.client.backfill.roots);
        fixture.client.backfill = (struct lantern_backfill_session){0};
    }
    if (peer_ready) {
        disable_sync_test_peer(&fixture.client);
    }
    if (fixture_ready) {
        teardown_block_signature_fixture(&fixture);
    }
    return rc;
}

static int test_reqresp_parent_response_preserves_backfill_depth(void)
{
    struct lantern_client client;
    LanternSignedBlock child;
    LanternSignedBlock parent;
    LanternRoot child_root;
    LanternRoot parent_root;
    LanternRoot grandparent_root;
    uint32_t observed_depth = 0u;
    bool found_parent = false;
    int rc = 1;

    memset(&client, 0, sizeof(client));
    memset(&child, 0, sizeof(child));
    memset(&parent, 0, sizeof(parent));
    client.node_id = "test_reqresp_parent_depth";

    if (pthread_mutex_init(&client.state_lock, NULL) != 0) {
        fprintf(stderr, "failed to initialize state mutex for depth test\n");
        return 1;
    }
    client.state_lock_initialized = true;
    if (pthread_mutex_init(&client.pending_lock, NULL) != 0) {
        fprintf(stderr, "failed to initialize pending mutex for depth test\n");
        pthread_mutex_destroy(&client.state_lock);
        client.state_lock_initialized = false;
        return 1;
    }
    client.pending_lock_initialized = true;

    lantern_state_init(&client.state);
    lantern_store_init(&client.store);
    if (lantern_state_generate_genesis(&client.state, 0u, 1u) != 0) {
        fprintf(stderr, "failed to generate state for depth test\n");
        goto cleanup;
    }

    lantern_block_body_init(&parent.block.body);
    parent.block.slot = 41u;
    parent.block.proposer_index = 0u;
    client_test_fill_root(&grandparent_root, 0xA1u);
    parent.block.parent_root = grandparent_root;
    client_test_fill_root(&parent.block.state_root, 0xA2u);
    if (lantern_hash_tree_root_block(&parent.block, &parent_root) != SSZ_SUCCESS) {
        fprintf(stderr, "failed to hash parent block for depth test\n");
        goto cleanup;
    }

    lantern_block_body_init(&child.block.body);
    child.block.slot = 42u;
    child.block.proposer_index = 0u;
    child.block.parent_root = parent_root;
    client_test_fill_root(&child.block.state_root, 0xA3u);
    if (lantern_hash_tree_root_block(&child.block, &child_root) != SSZ_SUCCESS) {
        fprintf(stderr, "failed to hash child block for depth test\n");
        goto cleanup;
    }

    if (!lantern_client_enqueue_pending_block(
            &client,
            &child,
            &child_root,
            &parent_root,
            "12D3KooWdepth",
            12u,
            false)) {
        fprintf(stderr, "failed to enqueue child pending block for depth test\n");
        goto cleanup;
    }
    if (!lantern_client_enqueue_pending_block(
            &client,
            &parent,
            &parent_root,
            &grandparent_root,
            "12D3KooWdepth",
            0u,
            false)) {
        fprintf(stderr, "failed to enqueue shallow parent pending block for depth test\n");
        goto cleanup;
    }

    if (reqresp_handle_block_response(
            &client,
            &parent,
            "12D3KooWdepth",
            0u) != LANTERN_CLIENT_OK) {
        fprintf(stderr, "reqresp rejected parent response for depth test\n");
        goto cleanup;
    }

    if (pthread_mutex_lock(&client.pending_lock) != 0) {
        fprintf(stderr, "failed to lock pending queue for depth inspection\n");
        goto cleanup;
    }
    for (size_t i = 0; i < client.pending_blocks.length; ++i) {
        const struct lantern_pending_block *entry = &client.pending_blocks.items[i];
        if (memcmp(entry->root.bytes, parent_root.bytes, LANTERN_ROOT_SIZE) == 0) {
            found_parent = true;
            observed_depth = entry->backfill_depth;
            break;
        }
    }
    pthread_mutex_unlock(&client.pending_lock);

    if (!found_parent) {
        fprintf(stderr, "parent response was not retained in pending queue\n");
        goto cleanup;
    }
    if (observed_depth != 13u) {
        fprintf(
            stderr,
            "parent response depth mismatch: got %" PRIu32 " want 13\n",
            observed_depth);
        goto cleanup;
    }

    rc = 0;

cleanup:
    lantern_client_debug_pending_reset(&client);
    lantern_signed_block_reset(&child);
    lantern_signed_block_reset(&parent);
    lantern_store_reset(&client.store);
    lantern_state_reset(&client.state);
    if (client.pending_lock_initialized) {
        pthread_mutex_destroy(&client.pending_lock);
        client.pending_lock_initialized = false;
    }
    if (client.state_lock_initialized) {
        pthread_mutex_destroy(&client.state_lock);
        client.state_lock_initialized = false;
    }
    return rc;
}

static int test_import_block_rejects_missing_block_proof(void)
{
    struct block_signature_fixture fixture;
    LanternSignedBlock block;
    LanternRoot block_root;
    uint64_t initial_slot = 0;
    int rc = 1;

    memset(&block, 0, sizeof(block));
    if (setup_block_signature_fixture(&fixture, "test_import_missing_block_proof") != 0) {
        fprintf(stderr, "failed to set up missing block proof fixture\n");
        return 1;
    }

    initial_slot = fixture.client.state.slot;
    if (build_signed_block_for_import(&fixture, true, false, &block, &block_root) != 0) {
        fprintf(stderr, "failed to build block fixture without block proof\n");
        goto cleanup;
    }

    if (lantern_client_debug_import_block(&fixture.client, &block, &block_root, "12D3KooWsig") != 0) {
        fprintf(stderr, "import unexpectedly accepted block missing block proof\n");
        goto cleanup;
    }
    if (fixture.client.state.slot != initial_slot) {
        fprintf(stderr, "state slot advanced after rejecting missing block proof\n");
        goto cleanup;
    }

    rc = 0;

cleanup:
    lantern_signed_block_reset(&block);
    teardown_block_signature_fixture(&fixture);
    return rc;
}

static int test_import_block_rejects_malformed_block_proof(void)
{
    struct block_signature_fixture fixture;
    LanternSignedBlock block;
    LanternRoot block_root;
    uint64_t initial_slot = 0;
    int rc = 1;

    memset(&block, 0, sizeof(block));
    if (setup_block_signature_fixture(&fixture, "test_import_bad_block_proof") != 0) {
        fprintf(stderr, "failed to set up malformed block proof fixture\n");
        return 1;
    }

    initial_slot = fixture.client.state.slot;
    if (build_signed_block_for_import(&fixture, true, true, &block, &block_root) != 0) {
        fprintf(stderr, "failed to build block fixture for malformed block proof\n");
        goto cleanup;
    }
    if (block.proof.length == 0 || !block.proof.data) {
        fprintf(stderr, "block fixture did not contain an aggregated proof to corrupt\n");
        goto cleanup;
    }

    block.proof.data[block.proof.length - 1u] ^= 0x5Au;

    if (lantern_client_debug_import_block(&fixture.client, &block, &block_root, "12D3KooWsig") != 0) {
        fprintf(stderr, "import unexpectedly accepted malformed block proof\n");
        goto cleanup;
    }
    if (fixture.client.state.slot != initial_slot) {
        fprintf(stderr, "state slot advanced after rejecting malformed block proof\n");
        goto cleanup;
    }

    rc = 0;

cleanup:
    lantern_signed_block_reset(&block);
    teardown_block_signature_fixture(&fixture);
    return rc;
}

static int test_import_block_skips_unknown_attestation_head_root(void)
{
    struct block_signature_fixture fixture;
    LanternSignedBlock block;
    LanternRoot block_root;
    LanternRoot unknown_root;
    uint64_t initial_slot = 0;
    int rc = 1;

    memset(&block, 0, sizeof(block));
    if (setup_block_signature_fixture(&fixture, "test_import_unknown_att_head") != 0) {
        fprintf(stderr, "failed to set up unknown attestation head fixture\n");
        return 1;
    }

    if (build_signed_block_for_import(&fixture, true, true, &block, &block_root) != 0) {
        fprintf(stderr, "failed to build block fixture for unknown attestation head test\n");
        goto cleanup;
    }
    initial_slot = fixture.client.state.slot;

    client_test_fill_root(&unknown_root, 0xD4);
    if (memcmp(
            unknown_root.bytes,
            block.block.body.attestations.data[0].data.head.root.bytes,
            LANTERN_ROOT_SIZE)
        == 0) {
        unknown_root.bytes[0] ^= 0xFFu;
    }
    block.block.body.attestations.data[0].data.head.root = unknown_root;
    if (resign_matching_block_attestations(&fixture, &block, &block_root) != 0) {
        fprintf(stderr, "failed to resign block fixture with unknown attestation head\n");
        goto cleanup;
    }

    if (lantern_client_debug_import_block(&fixture.client, &block, &block_root, "12D3KooWsig") != 1) {
        fprintf(stderr, "import rejected block with unknown attestation head root\n");
        goto cleanup;
    }
    if (fixture.client.state.slot != block.block.slot || fixture.client.state.slot == initial_slot) {
        fprintf(stderr, "state slot did not advance after skipping unknown attestation head root\n");
        goto cleanup;
    }

    rc = 0;

cleanup:
    lantern_signed_block_reset(&block);
    teardown_block_signature_fixture(&fixture);
    return rc;
}

static int test_restore_persisted_blocks_caches_known_attestation_proofs(void)
{
    struct block_signature_fixture fixture;
    LanternSignedBlock block;
    LanternRoot block_root;
    int rc = 1;

    memset(&block, 0, sizeof(block));
    if (setup_block_signature_fixture(&fixture, "test_restore_known_proofs") != 0) {
        fprintf(stderr, "failed to set up restore known proofs fixture\n");
        return 1;
    }

    if (build_signed_block_for_import(&fixture, true, true, &block, &block_root) != 0) {
        fprintf(stderr, "failed to build block fixture for restore known proofs test\n");
        goto cleanup;
    }
    if (lantern_storage_store_block(&fixture.client.storage, &block) != 0) {
        fprintf(stderr, "failed to persist block fixture for restore known proofs test\n");
        goto cleanup;
    }
    if (persist_post_state_for_block(&fixture, &block, &block_root) != 0) {
        fprintf(stderr, "failed to persist post-state fixture for restore known proofs test\n");
        goto cleanup;
    }

    if (restore_persisted_blocks(&fixture.client) != LANTERN_CLIENT_OK) {
        fprintf(stderr, "restore_persisted_blocks failed for known proofs test\n");
        goto cleanup;
    }
    if (expect_recovered_block_payload(&fixture.client.store, &block, true, "restored blocks")
        != 0) {
        goto cleanup;
    }
    rc = 0;

cleanup:
    lantern_signed_block_reset(&block);
    teardown_block_signature_fixture(&fixture);
    return rc;
}

static int test_restore_persisted_blocks_skips_proposer_attestation_cache(void)
{
    struct block_signature_fixture fixture;
    struct lantern_validator_config_entry assigned;
    LanternSignedBlock block;
    LanternRoot block_root;
    int rc = 1;

    memset(&assigned, 0, sizeof(assigned));
    memset(&block, 0, sizeof(block));

    if (setup_block_signature_fixture(&fixture, "test_restore_proposer_cache") != 0) {
        fprintf(stderr, "failed to set up restore proposer cache fixture\n");
        return 1;
    }

    assigned.enr.is_aggregator = true;
    fixture.client.assigned_validators = &assigned;
    fixture.client.gossip.attestation_subnet_id = 0u;

    if (build_signed_block_for_import(&fixture, true, true, &block, &block_root) != 0) {
        fprintf(stderr, "failed to build block fixture for restore proposer cache test\n");
        goto cleanup;
    }
    if (lantern_aggregated_attestations_resize(&block.block.body.attestations, 0u) != 0) {
        fprintf(stderr, "failed to clear block-body attestations for restore proposer cache test\n");
        goto cleanup;
    }
    if (lantern_state_preview_post_state_root(
            &fixture.client.state,
            &fixture.client.store,
            &block,
            &block.block.state_root)
        != 0) {
        fprintf(stderr, "failed to preview state root for proposer-only restore test\n");
        goto cleanup;
    }
    if (lantern_hash_tree_root_block(&block.block, &block_root) != SSZ_SUCCESS) {
        fprintf(stderr, "failed to hash proposer-only restore block\n");
        goto cleanup;
    }
    struct lantern_aggregated_payload_pool empty_attestation_payloads = {0};
    LanternSignature proposer_signature;
    memset(&proposer_signature, 0, sizeof(proposer_signature));
    if (!lantern_signature_sign(
            fixture.secret,
            block.block.slot,
            &block_root,
            &proposer_signature)
        || build_devnet5_block_proof(
               &fixture,
               &fixture.client.state,
               &block,
               &block_root,
               &empty_attestation_payloads,
               &proposer_signature)
               != 0) {
        lantern_aggregated_payload_pool_reset(&empty_attestation_payloads);
        fprintf(stderr, "failed to rebuild proposer-only block proof for restore test\n");
        goto cleanup;
    }
    lantern_aggregated_payload_pool_reset(&empty_attestation_payloads);
    if (lantern_storage_store_block(&fixture.client.storage, &block) != 0) {
        fprintf(stderr, "failed to persist proposer-only block fixture for restore test\n");
        goto cleanup;
    }
    if (persist_post_state_for_block(&fixture, &block, &block_root) != 0) {
        fprintf(stderr, "failed to persist proposer-only post-state for restore test\n");
        goto cleanup;
    }

    if (restore_persisted_blocks(&fixture.client) != LANTERN_CLIENT_OK) {
        fprintf(stderr, "restore_persisted_blocks failed for proposer cache test\n");
        goto cleanup;
    }
    if (fixture.client.store.new_aggregated_payloads.length != 0u
        || fixture.client.store.known_aggregated_payloads.length != 0u) {
        fprintf(stderr, "proposer-only restored block should not create known block-body proofs\n");
        goto cleanup;
    }
    if (fixture.client.store.attestation_signatures.length != 0u) {
        fprintf(stderr, "proposer-only restored block should not cache proposer gossip signatures\n");
        goto cleanup;
    }

    rc = 0;

cleanup:
    lantern_signed_block_reset(&block);
    teardown_block_signature_fixture(&fixture);
    return rc;
}

int main(void) {
    if (test_pending_block_queue() != 0) {
        return 1;
    }
    if (test_pending_block_queue_sync_drops_incoming() != 0) {
        return 1;
    }
    if (test_sync_completion_uses_network_finalized_threshold() != 0) {
        return 1;
    }
    if (test_idle_status_triggers_syncing_before_gossip_backfill() != 0) {
        return 1;
    }
    if (test_active_parent_requests_deduplicate_and_release() != 0) {
        return 1;
    }
    if (test_idle_status_at_known_head_completes_sync() != 0) {
        return 1;
    }
    if (test_peer_status_updates_sync_network_view() != 0) {
        return 1;
    }
    if (test_reqresp_block_response_accepts_missing_parent() != 0) {
        return 1;
    }
    if (test_reqresp_collect_blocks_pending_fallback() != 0) {
        return 1;
    }
    if (test_import_block_accepts_complete_proof() != 0) {
        return 1;
    }
    if (test_import_block_rejects_duplicate_attestation_data() != 0) {
        return 1;
    }
    if (test_import_persists_finalized_post_state() != 0) {
        return 1;
    }
    if (test_retained_side_branch_reloads_evicted_parent_state() != 0) {
        return 1;
    }
    if (test_imported_blocks_update_sync_network_view() != 0) {
        return 1;
    }
    if (test_historical_backfill_imports_after_large_gap_connects() != 0) {
        return 1;
    }
    if (test_historical_backfill_failed_and_empty_completions_retry() != 0) {
        return 1;
    }
    if (test_block_fetch_retry_rotates_root_scoped_failed_peers() != 0) {
        return 1;
    }
    if (test_block_fetch_exponential_backoff_and_attempt_exhaustion() != 0) {
        return 1;
    }
    if (test_block_fetch_lifecycle_cleans_up_on_success_and_session_replacement() != 0) {
        return 1;
    }
    if (test_advancing_status_preserves_historical_backfill_frontier() != 0) {
        return 1;
    }
    if (test_stale_async_backfill_completion_is_discarded() != 0) {
        return 1;
    }
    if (test_reqresp_parent_response_preserves_backfill_depth() != 0) {
        return 1;
    }
    if (test_import_block_rejects_missing_block_proof() != 0) {
        return 1;
    }
    if (test_import_block_rejects_malformed_block_proof() != 0) {
        return 1;
    }
    if (test_import_block_skips_unknown_attestation_head_root() != 0) {
        return 1;
    }
    if (test_restore_persisted_blocks_caches_known_attestation_proofs() != 0) {
        return 1;
    }
    if (test_restore_persisted_blocks_skips_proposer_attestation_cache() != 0) {
        return 1;
    }
    puts("lantern_client_pending_test OK");
    return 0;
}
