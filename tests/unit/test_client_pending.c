#include <pthread.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "client_test_helpers.h"
#include "../../src/core/client_services_internal.h"
#include "../../src/core/client_sync_internal.h"
#include "lantern/consensus/duties.h"
#include "lantern/consensus/hash.h"
#include "lantern/consensus/signature.h"
#include "lantern/consensus/state.h"
#include "lantern/genesis/genesis.h"
#include "lantern/storage/storage.h"

enum {
    TEST_TEMP_PATH_CAPACITY = 1024
};

struct block_signature_fixture {
    struct lantern_client client;
    struct PQSignatureSchemePublicKey *pub;
    struct PQSignatureSchemeSecretKey *secret;
    struct lantern_validator_record *registry_records;
    char data_dir_template[TEST_TEMP_PATH_CAPACITY];
};

static int enable_signature_verification_registry(
    struct lantern_client *client,
    struct lantern_validator_record **out_records)
{
    if (!client || !out_records) {
        return -1;
    }
    size_t validator_count = lantern_state_validator_count(&client->state);
    if (validator_count == 0) {
        return -1;
    }
    struct lantern_validator_record *records = calloc(validator_count, sizeof(*records));
    if (!records) {
        return -1;
    }
    for (size_t i = 0; i < validator_count; ++i) {
        records[i].index = (uint64_t)i;
        const uint8_t *pubkey = lantern_state_validator_attestation_pubkey(&client->state, i);
        if (!pubkey) {
            free(records);
            return -1;
        }
        memcpy(records[i].pubkey_bytes, pubkey, LANTERN_VALIDATOR_PUBKEY_SIZE);
        records[i].has_pubkey_bytes = true;
    }
    client->genesis.validator_registry.records = records;
    client->genesis.validator_registry.count = validator_count;
    *out_records = records;
    return 0;
}

static void disable_signature_verification_registry(
    struct lantern_client *client,
    struct lantern_validator_record **records)
{
    if (!client || !records) {
        return;
    }
    free(*records);
    *records = NULL;
    client->genesis.validator_registry.records = NULL;
    client->genesis.validator_registry.count = 0;
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
    if (enable_signature_verification_registry(&fixture->client, &fixture->registry_records) != 0) {
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
    if (!fixture->client.data_dir) {
        disable_signature_verification_registry(&fixture->client, &fixture->registry_records);
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
    disable_signature_verification_registry(&fixture->client, &fixture->registry_records);
    if (fixture->client.data_dir && fixture->client.data_dir[0] != '\0') {
        char cleanup_cmd[TEST_TEMP_PATH_CAPACITY + 16];
        int written = snprintf(cleanup_cmd, sizeof(cleanup_cmd), "rm -rf %s", fixture->client.data_dir);
        if (written > 0 && (size_t)written < sizeof(cleanup_cmd)) {
            (void)system(cleanup_cmd);
        }
    }
    fixture->client.data_dir = NULL;
    client_test_teardown_vote_validation_client(&fixture->client, fixture->pub, fixture->secret);
    fixture->pub = NULL;
    fixture->secret = NULL;
}

static int build_signed_block_for_import(
    struct block_signature_fixture *fixture,
    bool include_attestation_signature,
    bool include_proposer_signature,
    LanternSignedBlock *out_block,
    LanternRoot *out_root)
{
    if (!fixture || !fixture->secret || !out_block || !out_root) {
        return -1;
    }

    lantern_signed_block_with_attestation_init(out_block);

    uint64_t block_slot = fixture->client.state.slot + 1u;
    out_block->block.slot = block_slot;
    if (lantern_proposer_for_slot(
            block_slot,
            fixture->client.state.config.num_validators,
            &out_block->block.proposer_index)
        != 0) {
        return -1;
    }
    if (lantern_state_select_block_parent(
            &fixture->client.state,
            &fixture->client.store,
            &out_block->block.parent_root)
        != 0) {
        return -1;
    }
    if (lantern_storage_store_state_for_root(
            fixture->client.data_dir,
            &out_block->block.parent_root,
            &fixture->client.state)
        != 0) {
        return -1;
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
        return -1;
    }

    LanternSignedVote proposer_vote;
    memset(&proposer_vote, 0, sizeof(proposer_vote));
    proposer_vote.data.validator_id = out_block->block.proposer_index;
    proposer_vote.data.slot = block_slot;
    proposer_vote.data.head = head;
    proposer_vote.data.target = target;
    proposer_vote.data.source = source;
    if (client_test_sign_vote_with_secret(&proposer_vote, fixture->secret) != 0) {
        return -1;
    }

    if (lantern_aggregated_attestations_resize(&out_block->block.body.attestations, 1u) != 0) {
        return -1;
    }
    LanternAggregatedAttestation *attestation = &out_block->block.body.attestations.data[0];
    attestation->data = proposer_vote.data.data;
    if (lantern_bitlist_resize(&attestation->aggregation_bits, 1u) != 0
        || lantern_bitlist_set(&attestation->aggregation_bits, 0u, true) != 0) {
        return -1;
    }

    if (include_attestation_signature) {
        if (lantern_attestation_signatures_resize(&out_block->signatures.attestation_signatures, 1u) != 0) {
            return -1;
        }
        LanternAggregatedSignatureProof *proof = &out_block->signatures.attestation_signatures.data[0];
        if (lantern_bitlist_resize(&proof->participants, 1u) != 0
            || lantern_bitlist_set(&proof->participants, 0u, true) != 0) {
            return -1;
        }
        const uint8_t *pubkey = lantern_state_validator_attestation_pubkey(&fixture->client.state, 0u);
        if (!pubkey) {
            return -1;
        }
        LanternRoot attestation_root;
        if (lantern_hash_tree_root_attestation_data(&attestation->data, &attestation_root) != 0) {
            return -1;
        }
        const uint8_t *pubkeys[1] = {pubkey};
        LanternSignature signatures[1] = {proposer_vote.signature};
        if (!lantern_signature_aggregate(
                pubkeys,
                signatures,
                1u,
                &attestation_root,
                attestation->data.slot,
                &proof->proof_data)) {
            return -1;
        }
    }

    if (lantern_state_preview_post_state_root(
            &fixture->client.state,
            &fixture->client.store,
            out_block,
            &out_block->block.state_root)
        != 0) {
        return -1;
    }

    if (include_proposer_signature) {
        LanternRoot block_signature_root;
        if (lantern_hash_tree_root_block(&out_block->block, &block_signature_root) != 0) {
            return -1;
        }
        if (!lantern_signature_sign(
                fixture->secret,
                out_block->block.slot,
                &block_signature_root,
                &out_block->signatures.proposer_signature)) {
            return -1;
        }
    } else {
        lantern_signature_zero(&out_block->signatures.proposer_signature);
    }

    return lantern_hash_tree_root_block(&out_block->block, out_root);
}

static int resign_first_block_attestation(
    struct block_signature_fixture *fixture,
    LanternSignedBlock *block,
    LanternRoot *out_root)
{
    if (!fixture || !fixture->secret || !block || !out_root) {
        return -1;
    }
    if (block->block.body.attestations.length == 0
        || !block->block.body.attestations.data
        || block->signatures.attestation_signatures.length == 0
        || !block->signatures.attestation_signatures.data) {
        return -1;
    }

    LanternAggregatedAttestation *attestation = &block->block.body.attestations.data[0];
    LanternAggregatedSignatureProof *proof = &block->signatures.attestation_signatures.data[0];

    LanternSignedVote signed_vote;
    memset(&signed_vote, 0, sizeof(signed_vote));
    signed_vote.data.validator_id = 0u;
    signed_vote.data.slot = attestation->data.slot;
    signed_vote.data.data = attestation->data;
    if (client_test_sign_vote_with_secret(&signed_vote, fixture->secret) != 0) {
        return -1;
    }

    if (lantern_bitlist_resize(&attestation->aggregation_bits, 1u) != 0
        || lantern_bitlist_set(&attestation->aggregation_bits, 0u, true) != 0) {
        return -1;
    }
    if (lantern_bitlist_resize(&proof->participants, 1u) != 0
        || lantern_bitlist_set(&proof->participants, 0u, true) != 0) {
        return -1;
    }

    const uint8_t *pubkey = lantern_state_validator_attestation_pubkey(&fixture->client.state, 0u);
    if (!pubkey) {
        return -1;
    }
    LanternRoot attestation_root;
    if (lantern_hash_tree_root_attestation_data(&attestation->data, &attestation_root) != 0) {
        return -1;
    }
    const uint8_t *pubkeys[1] = {pubkey};
    LanternSignature signatures[1] = {signed_vote.signature};
    if (!lantern_signature_aggregate(
            pubkeys,
            signatures,
            1u,
            &attestation_root,
            attestation->data.slot,
            &proof->proof_data)) {
        return -1;
    }

    if (lantern_state_preview_post_state_root(
            &fixture->client.state,
            &fixture->client.store,
            block,
            &block->block.state_root)
        != 0) {
        return -1;
    }
    if (lantern_hash_tree_root_block(&block->block, out_root) != 0) {
        return -1;
    }
    if (!lantern_signature_sign(
            fixture->secret,
            block->block.slot,
            out_root,
            &block->signatures.proposer_signature)) {
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
    bool parent_requested = true;
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
            &parent_requested,
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
    if (parent_requested) {
        fprintf(stderr, "parent_requested unexpectedly set after schedule failure\n");
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

    parent_requested = true;
    if (lantern_client_debug_pending_entry(
            &client,
            0,
            &fetched_root,
            &fetched_parent,
            &parent_requested,
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

    if (lantern_client_debug_set_parent_requested(&client, &child_root, true) != 0) {
        fprintf(stderr, "failed to mark parent_requested for pending block\n");
        rc = 1;
        goto cleanup;
    }

    parent_requested = false;
    if (lantern_client_debug_pending_entry(
            &client,
            0,
            NULL,
            NULL,
            &parent_requested,
            NULL,
            0)
        != 0
        || !parent_requested) {
        fprintf(stderr, "parent_requested flag did not persist after manual set\n");
        rc = 1;
        goto cleanup;
    }

    if (lantern_client_debug_on_blocks_request_complete(
            &client,
            peer_b,
            &parent_root,
            LANTERN_TEST_BLOCKS_REQUEST_SUCCESS)
        != 0) {
        fprintf(stderr, "blocks_request_complete debug wrapper failed\n");
        rc = 1;
        goto cleanup;
    }

    parent_requested = true;
    if (lantern_client_debug_pending_entry(
            &client,
            0,
            NULL,
            NULL,
            &parent_requested,
            NULL,
            0)
        != 0) {
        fprintf(stderr, "failed to inspect parent_requested after completion\n");
        rc = 1;
        goto cleanup;
    }
    if (parent_requested) {
        fprintf(stderr, "parent_requested not cleared after completion\n");
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
    client.sync_in_progress = true;
    client.debug_disable_block_requests = true;

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

static int test_import_block_parent_mismatch(void) {
    struct lantern_client client;
    memset(&client, 0, sizeof(client));
    client.node_id = "test_parent_mismatch";

    int rc = 0;
    LanternSignedBlock block;
    LanternRoot block_root;
    LanternRoot parent_root;
    LanternRoot head_root;
    LanternRoot parent_block_root;
    LanternRoot pending_root;
    LanternRoot pending_parent;
    bool parent_requested = true;
    char peer_text[128];

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
    client.has_state = true;
    client.state.slot = 0;
    lantern_store_init(&client.store);

    memset(&client.state.latest_block_header, 0, sizeof(client.state.latest_block_header));
    client_test_fill_root(&client.state.latest_block_header.state_root, 0x10);
    client_test_fill_root(&client.state.latest_block_header.body_root, 0x11);
    client_test_fill_root(&client.state.latest_block_header.parent_root, 0x12);
    client.state.latest_block_header.slot = 0;
    client.state.latest_block_header.proposer_index = 0;

    if (lantern_hash_tree_root_block_header(&client.state.latest_block_header, &head_root) != 0) {
        fprintf(stderr, "failed to hash latest block header\n");
        rc = 1;
        goto cleanup;
    }

    lantern_fork_choice_init(&client.fork_choice);
    lantern_store_attach_fork_choice(&client.store, &client.fork_choice);
    LanternConfig fork_cfg = {
        .num_validators = 8,
        .genesis_time = 0,
    };
    if (lantern_fork_choice_configure(&client.fork_choice, &fork_cfg) != 0) {
        fprintf(stderr, "failed to configure fork choice\n");
        rc = 1;
        goto cleanup;
    }
    client.has_fork_choice = true;

    LanternCheckpoint anchor_checkpoint = {
        .root = head_root,
        .slot = 0,
    };
    client.state.latest_justified = anchor_checkpoint;
    client.state.latest_finalized = anchor_checkpoint;

    LanternBlock anchor_block;
    memset(&anchor_block, 0, sizeof(anchor_block));
    lantern_block_body_init(&anchor_block.body);
    anchor_block.slot = 0;
    anchor_block.proposer_index = 0;
    anchor_block.parent_root = client.state.latest_block_header.parent_root;
    anchor_block.state_root = client.state.latest_block_header.state_root;

    if (lantern_fork_choice_set_anchor(
            &client.fork_choice,
            &anchor_block,
            &client.state.latest_justified,
            &client.state.latest_finalized,
            &head_root)
        != 0) {
        fprintf(stderr, "failed to set fork choice anchor\n");
        lantern_block_body_reset(&anchor_block.body);
        rc = 1;
        goto cleanup;
    }

    LanternBlock parent_block;
    memset(&parent_block, 0, sizeof(parent_block));
    lantern_block_body_init(&parent_block.body);
    parent_block.slot = 1;
    parent_block.proposer_index = 0;
    parent_block.parent_root = head_root;
    client_test_fill_root(&parent_block.state_root, 0x44);

    if (lantern_hash_tree_root_block(&parent_block, &parent_block_root) != 0)
    {
        fprintf(stderr, "failed to hash parent block\n");
        lantern_block_body_reset(&parent_block.body);
        lantern_block_body_reset(&anchor_block.body);
        rc = 1;
        goto cleanup;
    }

    if (lantern_fork_choice_add_block(
            &client.fork_choice,
            &parent_block,
            NULL,
            &client.state.latest_justified,
            &client.state.latest_finalized,
            &parent_block_root)
        != 0)
    {
        fprintf(stderr, "failed to add parent block to fork choice\n");
        lantern_block_body_reset(&parent_block.body);
        lantern_block_body_reset(&anchor_block.body);
        rc = 1;
        goto cleanup;
    }
    lantern_block_body_reset(&parent_block.body);
    lantern_block_body_reset(&anchor_block.body);

    memset(&block, 0, sizeof(block));
    lantern_block_body_init(&block.block.body);
    block.block.slot = 5;
    block.block.proposer_index = 0;
    client_test_fill_root(&block_root, 0x90);
    client_test_fill_root(&parent_root, 0x20);
    if (memcmp(parent_root.bytes, head_root.bytes, LANTERN_ROOT_SIZE) == 0) {
        parent_root.bytes[0] ^= 0xFFu;
    }
    block.block.parent_root = parent_root;
    client_test_fill_root(&block.block.state_root, 0x30);

    if (lantern_client_pending_block_count(&client) != 0) {
        rc = 1;
        fprintf(stderr, "pending queue not empty at test start\n");
        goto cleanup;
    }

    if (lantern_client_debug_import_block(&client, &block, &block_root, "12D3KooWparent") != 0) {
        fprintf(stderr, "import unexpectedly succeeded for mismatched parent\n");
        rc = 1;
        goto cleanup;
    }

    if (lantern_client_pending_block_count(&client) != 1) {
        fprintf(stderr, "pending queue count mismatch after mismatched parent\n");
        rc = 1;
        goto cleanup;
    }

    memset(peer_text, 0, sizeof(peer_text));
    parent_requested = true;
    if (lantern_client_debug_pending_entry(
            &client,
            0,
            &pending_root,
            &pending_parent,
            &parent_requested,
            peer_text,
            sizeof(peer_text))
        != 0) {
        fprintf(stderr, "failed to inspect pending entry after mismatched parent\n");
        rc = 1;
        goto cleanup;
    }

    if (memcmp(pending_root.bytes, block_root.bytes, LANTERN_ROOT_SIZE) != 0) {
        fprintf(stderr, "pending root mismatch after mismatched parent\n");
        rc = 1;
        goto cleanup;
    }
    if (memcmp(pending_parent.bytes, parent_root.bytes, LANTERN_ROOT_SIZE) != 0) {
        fprintf(stderr, "pending parent root mismatch after mismatched parent\n");
        rc = 1;
        goto cleanup;
    }
    if (parent_requested) {
        fprintf(stderr, "parent_requested flag unexpectedly set after scheduling failure\n");
        rc = 1;
        goto cleanup;
    }

cleanup:
    lantern_client_debug_pending_reset(&client);
    lantern_block_body_reset(&block.block.body);
    if (client.has_fork_choice) {
        lantern_fork_choice_reset(&client.fork_choice);
        client.has_fork_choice = false;
    }
    if (client.pending_lock_initialized) {
        pthread_mutex_destroy(&client.pending_lock);
        client.pending_lock_initialized = false;
    }
    if (client.state_lock_initialized) {
        pthread_mutex_destroy(&client.state_lock);
        client.state_lock_initialized = false;
    }
    if (client.has_state) {
        lantern_state_reset(&client.state);
        client.has_state = false;
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
    if (lantern_hash_tree_root_block(&pending_block.block, &pending_root) != 0) {
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

    LanternSignedBlockList collected;
    lantern_signed_block_list_init(&collected);
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
    if (lantern_hash_tree_root_block(&collected.blocks[0].block, &collected_root) != 0) {
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

static int test_import_block_accepts_complete_signatures(void)
{
    struct block_signature_fixture fixture;
    LanternSignedBlock block;
    LanternRoot block_root;
    uint64_t initial_slot = 0;
    int rc = 1;

    memset(&block, 0, sizeof(block));
    if (setup_block_signature_fixture(&fixture, "test_import_complete_signatures") != 0) {
        fprintf(stderr, "failed to set up block signature fixture\n");
        return 1;
    }

    initial_slot = fixture.client.state.slot;
    if (build_signed_block_for_import(&fixture, true, true, &block, &block_root) != 0) {
        fprintf(stderr, "failed to build fully signed block fixture\n");
        goto cleanup;
    }

    if (lantern_client_debug_import_block(&fixture.client, &block, &block_root, "12D3KooWsig") != 1) {
        fprintf(stderr, "import rejected block with complete signatures\n");
        goto cleanup;
    }
    if (fixture.client.state.slot != block.block.slot || fixture.client.state.slot == initial_slot) {
        fprintf(stderr, "state slot did not advance after importing fully signed block\n");
        goto cleanup;
    }
    if (fixture.client.store.new_aggregated_payloads.length != 0u) {
        fprintf(stderr, "canonical import should not stage block-body proofs in new payloads\n");
        goto cleanup;
    }
    if (fixture.client.store.known_aggregated_payloads.length != 1u) {
        fprintf(stderr, "canonical import should cache block-body proofs directly in known payloads\n");
        goto cleanup;
    }
    if (fixture.client.store.attestation_data_by_root.length == 0u) {
        fprintf(stderr, "canonical import should retain attestation data for cached block proofs\n");
        goto cleanup;
    }

    rc = 0;

cleanup:
    lantern_signed_block_with_attestation_reset(&block);
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
    target.client.debug_disable_block_requests = true;
    if (pthread_mutex_init(&target.client.pending_lock, NULL) != 0) {
        fprintf(stderr, "failed to initialize target pending mutex\n");
        goto cleanup;
    }
    target.client.pending_lock_initialized = true;

    if (build_signed_block_for_import(&target, true, true, &block, &root) != 0) {
        fprintf(stderr, "failed to build backfill block\n");
        goto cleanup;
    }

    uint64_t local_head_slot = target.client.state.slot;
    uint64_t anchor_slot = local_head_slot;
    if (target.client.has_fork_choice) {
        (void)lantern_fork_choice_anchor_slot(&target.client.fork_choice, &anchor_slot);
    }
    uint64_t peer_reported_head_slot = anchor_slot + LANTERN_PENDING_BLOCK_LIMIT + 1u;
    if (!lantern_client_maybe_start_historical_backfill(
            &target.client,
            "12D3KooWbackfill",
            &root,
            peer_reported_head_slot,
            local_head_slot)) {
        fprintf(stderr, "large-gap backfill session did not start\n");
        goto cleanup;
    }

    if (!lantern_client_backfill_process_block(
            &target.client,
            &block,
            &root,
            "12D3KooWbackfill",
            0u)) {
        fprintf(stderr, "backfill did not accept fetched head block\n");
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
    if (target.client.backfill.active) {
        fprintf(stderr, "backfill session remained active after importing head\n");
        goto cleanup;
    }
    if (lantern_client_pending_block_count(&target.client) != 0) {
        fprintf(stderr, "backfill should not populate pending block queue\n");
        goto cleanup;
    }

    rc = 0;

cleanup:
    lantern_signed_block_with_attestation_reset(&block);
    if (target_ready) {
        lantern_client_backfill_reset(&target.client);
        if (target.client.pending_lock_initialized) {
            pthread_mutex_destroy(&target.client.pending_lock);
            target.client.pending_lock_initialized = false;
        }
        teardown_block_signature_fixture(&target);
    }
    return rc;
}

static int test_import_block_rejects_missing_attestation_signature_groups(void)
{
    struct block_signature_fixture fixture;
    LanternSignedBlock block;
    LanternRoot block_root;
    uint64_t initial_slot = 0;
    int rc = 1;

    memset(&block, 0, sizeof(block));
    if (setup_block_signature_fixture(&fixture, "test_import_missing_att_sigs") != 0) {
        fprintf(stderr, "failed to set up missing attestation signature fixture\n");
        return 1;
    }

    initial_slot = fixture.client.state.slot;
    if (build_signed_block_for_import(&fixture, false, true, &block, &block_root) != 0) {
        fprintf(stderr, "failed to build block fixture without attestation signatures\n");
        goto cleanup;
    }

    if (lantern_client_debug_import_block(&fixture.client, &block, &block_root, "12D3KooWsig") != 0) {
        fprintf(stderr, "import unexpectedly accepted block missing attestation signatures\n");
        goto cleanup;
    }
    if (fixture.client.state.slot != initial_slot) {
        fprintf(stderr, "state slot advanced after rejecting missing attestation signatures\n");
        goto cleanup;
    }

    rc = 0;

cleanup:
    lantern_signed_block_with_attestation_reset(&block);
    teardown_block_signature_fixture(&fixture);
    return rc;
}

static int test_import_block_rejects_missing_proposer_signature(void)
{
    struct block_signature_fixture fixture;
    LanternSignedBlock block;
    LanternRoot block_root;
    uint64_t initial_slot = 0;
    int rc = 1;

    memset(&block, 0, sizeof(block));
    if (setup_block_signature_fixture(&fixture, "test_import_missing_prop_sig") != 0) {
        fprintf(stderr, "failed to set up missing proposer signature fixture\n");
        return 1;
    }

    initial_slot = fixture.client.state.slot;
    if (build_signed_block_for_import(&fixture, true, false, &block, &block_root) != 0) {
        fprintf(stderr, "failed to build block fixture without proposer signature\n");
        goto cleanup;
    }

    if (lantern_client_debug_import_block(&fixture.client, &block, &block_root, "12D3KooWsig") != 0) {
        fprintf(stderr, "import unexpectedly accepted block missing proposer signature\n");
        goto cleanup;
    }
    if (fixture.client.state.slot != initial_slot) {
        fprintf(stderr, "state slot advanced after rejecting missing proposer signature\n");
        goto cleanup;
    }

    rc = 0;

cleanup:
    lantern_signed_block_with_attestation_reset(&block);
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
    if (resign_first_block_attestation(&fixture, &block, &block_root) != 0) {
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
    lantern_signed_block_with_attestation_reset(&block);
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
    if (lantern_storage_store_block(fixture.client.data_dir, &block) != 0) {
        fprintf(stderr, "failed to persist block fixture for restore known proofs test\n");
        goto cleanup;
    }

    if (restore_persisted_blocks(&fixture.client) != LANTERN_CLIENT_OK) {
        fprintf(stderr, "restore_persisted_blocks failed for known proofs test\n");
        goto cleanup;
    }
    if (fixture.client.store.new_aggregated_payloads.length != 0u) {
        fprintf(stderr, "restored blocks should not stage block-body proofs in new payloads\n");
        goto cleanup;
    }
    if (fixture.client.store.known_aggregated_payloads.length != 1u) {
        fprintf(stderr, "restored blocks should cache block-body proofs directly in known payloads\n");
        goto cleanup;
    }
    if (fixture.client.store.attestation_data_by_root.length == 0u) {
        fprintf(stderr, "restored blocks should retain attestation data for cached proofs\n");
        goto cleanup;
    }

    rc = 0;

cleanup:
    lantern_signed_block_with_attestation_reset(&block);
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
    if (lantern_aggregated_attestations_resize(&block.block.body.attestations, 0u) != 0
        || lantern_attestation_signatures_resize(&block.signatures.attestation_signatures, 0u) != 0) {
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
    if (lantern_hash_tree_root_block(&block.block, &block_root) != 0) {
        fprintf(stderr, "failed to hash proposer-only restore block\n");
        goto cleanup;
    }
    if (lantern_storage_store_block(fixture.client.data_dir, &block) != 0) {
        fprintf(stderr, "failed to persist proposer-only block fixture for restore test\n");
        goto cleanup;
    }

    if (restore_persisted_blocks(&fixture.client) != LANTERN_CLIENT_OK) {
        fprintf(stderr, "restore_persisted_blocks failed for proposer cache test\n");
        goto cleanup;
    }
    if (fixture.client.store.known_aggregated_payloads.length != 0u) {
        fprintf(stderr, "proposer-only restored block should not create known block-body proofs\n");
        goto cleanup;
    }
    if (fixture.client.store.attestation_data_by_root.length != 0u) {
        fprintf(stderr, "proposer-only restored block should not cache proposer attestation data\n");
        goto cleanup;
    }
    if (fixture.client.store.attestation_signatures.length != 0u) {
        fprintf(stderr, "proposer-only restored block should not cache proposer gossip signatures\n");
        goto cleanup;
    }

    rc = 0;

cleanup:
    lantern_signed_block_with_attestation_reset(&block);
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
    if (test_import_block_parent_mismatch() != 0) {
        return 1;
    }
    if (test_reqresp_collect_blocks_pending_fallback() != 0) {
        return 1;
    }
    if (test_import_block_accepts_complete_signatures() != 0) {
        return 1;
    }
    if (test_historical_backfill_imports_after_large_gap_connects() != 0) {
        return 1;
    }
    if (test_import_block_rejects_missing_attestation_signature_groups() != 0) {
        return 1;
    }
    if (test_import_block_rejects_missing_proposer_signature() != 0) {
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
