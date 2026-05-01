#include <inttypes.h>
#include <limits.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "../../src/core/client_services_internal.h"
#include "lantern/consensus/duties.h"
#include "client_test_helpers.h"
#include "lantern/consensus/hash.h"
#include "lantern/consensus/signature.h"
#include "lantern/crypto/xmss.h"
#include "lantern/networking/gossip_payloads.h"
#include "lantern/support/string_list.h"
#include "lantern/storage/storage.h"
#include "lantern/support/time.h"

/* Internal core APIs used for targeted cache and block-build regression tests. */
int lantern_client_set_attestation_signature(
    struct lantern_client *client,
    const LanternSignatureKey *key,
    const LanternAttestationData *data,
    const LanternSignature *signature,
    uint64_t target_slot);
int lantern_client_add_new_aggregated_payload(
    struct lantern_client *client,
    const LanternRoot *data_root,
    const LanternAttestationData *data,
    const LanternAggregatedSignatureProof *proof,
    uint64_t target_slot);
int lantern_client_add_known_aggregated_payload(
    struct lantern_client *client,
    const LanternRoot *data_root,
    const LanternAttestationData *data,
    const LanternAggregatedSignatureProof *proof,
    uint64_t target_slot);
int lantern_client_commit_and_publish_local_block(
    struct lantern_client *client,
    const LanternSignedBlock *block,
    const LanternRoot *block_root,
    LanternState *post_state,
    LanternStore *post_store);
size_t lantern_client_promote_new_aggregated_payloads(
    struct lantern_client *client);
size_t lantern_client_prune_finalized_attestation_material(
    struct lantern_client *client,
    uint64_t finalized_slot);
int lantern_client_chain_service_tick_to(
    struct lantern_client *client,
    uint64_t target_interval,
    bool has_proposal,
    uint64_t *out_skipped_to_interval,
    uint64_t *out_ticked_intervals);
int lantern_client_skip_fork_choice_intervals_locked(
    struct lantern_client *client,
    uint64_t target_interval);
int lantern_client_advance_fork_choice_time_locked(
    struct lantern_client *client,
    uint64_t now_milliseconds,
    bool has_proposal);
void lantern_client_reset_local_validators(struct lantern_client *client);
int lantern_client_load_xmss_keys(struct lantern_client *client);
int validator_sign_with_key(
    struct lantern_local_validator *validator,
    uint64_t slot,
    const LanternRoot *message,
    bool use_proposal_key,
    LanternSignature *out_signature);
int validator_build_block(
    struct lantern_client *client,
    uint64_t slot,
    size_t local_index,
    LanternSignedBlock *out_block);
lantern_client_error lantern_client_aggregate_attestations_for_block(
    struct lantern_client *client,
    const LanternAttestations *att_list,
    const LanternSignatureList *att_signatures,
    LanternAggregatedAttestations *out_attestations,
    LanternAttestationSignatures *out_signatures);
lantern_client_error lantern_client_debug_aggregate_attestation_signatures(
    struct lantern_client *client,
    LanternAggregatedAttestations *out_attestations,
    LanternAttestationSignatures *out_signatures);
int validator_publish_attestations(struct lantern_client *client, uint64_t slot);

static void test_reset_agg_cache(struct lantern_client *client) {
    if (!client) {
        return;
    }
    lantern_store_reset(&client->store);
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

static int test_make_dummy_proof(
    LanternAggregatedSignatureProof *out_proof,
    uint64_t validator_id,
    uint8_t seed) {
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
        out_proof->proof_data.data[i] = (uint8_t)(seed + (uint8_t)i);
    }
    return 0;
}

static LanternAttestationData test_make_attestation_data(uint64_t slot, uint8_t marker) {
    LanternAttestationData data;
    memset(&data, 0, sizeof(data));
    data.slot = slot;
    data.head.slot = slot;
    data.target.slot = slot;
    data.source.slot = slot == 0 ? 0 : slot - 1u;
    memset(data.head.root.bytes, marker, LANTERN_ROOT_SIZE);
    memset(data.target.root.bytes, (int)(marker + 1u), LANTERN_ROOT_SIZE);
    memset(data.source.root.bytes, (int)(marker + 2u), LANTERN_ROOT_SIZE);
    return data;
}

static bool aggregated_pool_contains_root(
    const struct lantern_aggregated_payload_pool *pool,
    const LanternRoot *data_root) {
    if (!pool || !data_root || !pool->entries) {
        return false;
    }
    for (size_t i = 0; i < pool->length; ++i) {
        if (memcmp(pool->entries[i].data_root.bytes, data_root->bytes, LANTERN_ROOT_SIZE) == 0) {
            return true;
        }
    }
    return false;
}

static bool pq_range_contains_slot(struct PQRange range, uint64_t slot) {
    return range.start <= slot && slot < range.end;
}

static int test_fixture_secret_key_path(
    size_t validator_index,
    char *out_path,
    size_t out_path_len) {
    if (!out_path || out_path_len == 0) {
        return -1;
    }
    int written = snprintf(
        out_path,
        out_path_len,
        "%s/genesis/xmss-keys/validator_%zu_sk.json",
        LANTERN_TEST_FIXTURE_DIR,
        validator_index);
    if (written <= 0 || (size_t)written >= out_path_len) {
        return -1;
    }
    return 0;
}

static int test_copy_file(const char *src_path, const char *dst_path) {
    if (!src_path || !dst_path) {
        return -1;
    }

    FILE *src = fopen(src_path, "rb");
    if (!src) {
        perror("fopen copy src");
        return -1;
    }

    FILE *dst = fopen(dst_path, "wb");
    if (!dst) {
        perror("fopen copy dst");
        fclose(src);
        return -1;
    }

    int rc = 0;
    unsigned char buffer[4096];
    while (1) {
        size_t read_len = fread(buffer, 1u, sizeof(buffer), src);
        if (read_len > 0 && fwrite(buffer, 1u, read_len, dst) != read_len) {
            perror("fwrite copy");
            rc = -1;
            break;
        }
        if (read_len < sizeof(buffer)) {
            if (ferror(src)) {
                perror("fread copy");
                rc = -1;
            }
            break;
        }
    }

    fclose(dst);
    fclose(src);
    return rc;
}

static bool proof_payload_equals(
    const LanternAggregatedSignatureProof *lhs,
    const LanternAggregatedSignatureProof *rhs) {
    if (!lhs || !rhs) {
        return false;
    }
    if (lhs->participants.bit_length != rhs->participants.bit_length) {
        return false;
    }
    size_t bits = lhs->participants.bit_length;
    size_t bytes = (bits + 7u) / 8u;
    if (bytes > 0) {
        if (!lhs->participants.bytes || !rhs->participants.bytes) {
            return false;
        }
        if (memcmp(lhs->participants.bytes, rhs->participants.bytes, bytes) != 0) {
            return false;
        }
    }
    if (lhs->proof_data.length != rhs->proof_data.length) {
        return false;
    }
    if (lhs->proof_data.length > 0) {
        if (!lhs->proof_data.data || !rhs->proof_data.data) {
            return false;
        }
        if (memcmp(lhs->proof_data.data, rhs->proof_data.data, lhs->proof_data.length) != 0) {
            return false;
        }
    }
    return true;
}

struct publish_capture {
    size_t calls;
    char topic[128];
    uint8_t *payload;
    size_t payload_len;
    size_t payload_capacity;
};

static int publish_capture_hook(
    const char *topic,
    const uint8_t *payload,
    size_t payload_len,
    void *user_data) {
    struct publish_capture *capture = user_data;
    if (!capture || !topic || !payload || payload_len == 0) {
        return -1;
    }
    if (payload_len > capture->payload_capacity) {
        uint8_t *resized = realloc(capture->payload, payload_len);
        if (!resized) {
            return -1;
        }
        capture->payload = resized;
        capture->payload_capacity = payload_len;
    }
    capture->calls += 1u;
    snprintf(capture->topic, sizeof(capture->topic), "%s", topic);
    memcpy(capture->payload, payload, payload_len);
    capture->payload_len = payload_len;
    return 0;
}

static void publish_capture_reset(struct publish_capture *capture) {
    if (!capture) {
        return;
    }
    free(capture->payload);
    memset(capture, 0, sizeof(*capture));
}

struct local_block_publish_observer {
    struct lantern_client *client;
    uint64_t expected_slot;
    LanternRoot expected_root;
    size_t calls;
    bool saw_state_slot;
    bool saw_head_root;
};

static int local_block_publish_observer_hook(
    const char *topic,
    const uint8_t *payload,
    size_t payload_len,
    void *user_data) {
    struct local_block_publish_observer *observer = user_data;
    if (!observer || !topic || !payload || payload_len == 0u) {
        return -1;
    }
    observer->calls += 1u;
    if (!observer->client) {
        return 0;
    }
    if (observer->client->state.slot == observer->expected_slot) {
        observer->saw_state_slot = true;
    }
    LanternRoot head_root;
    memset(&head_root, 0, sizeof(head_root));
    if (observer->client->has_fork_choice
        && lantern_fork_choice_current_head(&observer->client->fork_choice, &head_root) == 0
        && memcmp(head_root.bytes, observer->expected_root.bytes, LANTERN_ROOT_SIZE) == 0) {
        observer->saw_head_root = true;
    }
    return 0;
}

static int advance_client_fork_choice_intervals(
    struct lantern_client *client,
    size_t count,
    bool has_proposal) {
    if (!client || !client->has_fork_choice || client->fork_choice.milliseconds_per_interval == 0) {
        return -1;
    }
    for (size_t i = 0; i < count; ++i) {
        uint64_t next_interval = client->fork_choice.time_intervals + 1u;
        uint64_t now =
            (client->fork_choice.config.genesis_time * 1000u)
            + (next_interval * client->fork_choice.milliseconds_per_interval);
        if (lantern_client_advance_fork_choice_time_locked(client, now, has_proposal) != 0) {
            return -1;
        }
    }
    return 0;
}

static int make_signed_vote_for_validator(
    struct lantern_client *client,
    struct PQSignatureSchemeSecretKey *secret,
    uint64_t validator_id,
    const LanternRoot *anchor_root,
    const LanternRoot *child_root,
    LanternSignedVote *out_vote) {
    if (!client || !secret || !anchor_root || !child_root || !out_vote) {
        return -1;
    }
    uint64_t child_slot = 0;
    if (client_test_slot_for_root(client, child_root, &child_slot) != 0) {
        return -1;
    }
    memset(out_vote, 0, sizeof(*out_vote));
    out_vote->data.validator_id = validator_id;
    out_vote->data.slot = child_slot;
    out_vote->data.head.slot = child_slot;
    out_vote->data.head.root = *child_root;
    out_vote->data.target.slot = child_slot;
    out_vote->data.target.root = *child_root;
    out_vote->data.source.slot = 0u;
    out_vote->data.source.root = *anchor_root;
    return client_test_sign_vote_with_secret(out_vote, secret);
}

static int build_signed_head_block(
    struct lantern_client *client,
    struct PQSignatureSchemeSecretKey *secret,
    LanternSignedBlock *out_block,
    LanternRoot *out_root) {
    if (!client || !secret || !out_block || !out_root) {
        return -1;
    }

    int rc = -1;

    lantern_signed_block_with_attestation_init(out_block);
    out_block->block.slot = client->state.slot + 1u;
    if (lantern_proposer_for_slot(
            out_block->block.slot,
            client->state.config.num_validators,
            &out_block->block.proposer_index)
        != 0) {
        goto cleanup;
    }
    if (lantern_state_select_block_parent(
            &client->state,
            &client->store,
            &out_block->block.parent_root)
        != 0) {
        goto cleanup;
    }

    if (lantern_state_preview_post_state_root(
            &client->state,
            &client->store,
            out_block,
            &out_block->block.state_root)
        != 0) {
        goto cleanup;
    }
    LanternRoot block_signature_root;
    if (lantern_hash_tree_root_block(&out_block->block, &block_signature_root) != 0) {
        goto cleanup;
    }
    if (!lantern_signature_sign(
            secret,
            out_block->block.slot,
            &block_signature_root,
            &out_block->signatures.proposer_signature)) {
        goto cleanup;
    }
    if (lantern_hash_tree_root_block(&out_block->block, out_root) != 0) {
        goto cleanup;
    }

    rc = 0;

cleanup:
    if (rc != 0) {
        lantern_signed_block_with_attestation_reset(out_block);
    }
    return rc;
}

static int test_record_vote_accepts_known_roots(void) {
    struct lantern_client client;
    struct PQSignatureSchemePublicKey *pub = NULL;
    struct PQSignatureSchemeSecretKey *secret = NULL;
    LanternRoot anchor_root;
    LanternRoot child_root;
    int rc = 1;

    if (client_test_setup_vote_validation_client(&client, "vote_known", &pub, &secret, &anchor_root, &child_root) != 0) {
        return 1;
    }

    LanternSignedVote vote;
    memset(&vote, 0, sizeof(vote));
    uint64_t child_slot = 0;
    if (client_test_slot_for_root(&client, &child_root, &child_slot) != 0) {
        fprintf(stderr, "failed to resolve child slot for known roots test\n");
        goto cleanup;
    }
    vote.data.validator_id = 0;
    vote.data.slot = 2;
    vote.data.head.slot = child_slot;
    vote.data.head.root = child_root;
    vote.data.target.slot = child_slot;
    vote.data.target.root = child_root;
    vote.data.source.slot = 0;
    vote.data.source.root = anchor_root;

    if (client_test_sign_vote_with_secret(&vote, secret) != 0) {
        fprintf(stderr, "failed to sign vote with known roots\n");
        goto cleanup;
    }

    if (lantern_client_debug_record_vote(&client, &vote, "vote_known_peer") != 0) {
        fprintf(stderr, "lantern_client_debug_record_vote failed for known roots\n");
        goto cleanup;
    }

    if (!lantern_store_validator_has_vote(&client.store, 0)) {
        fprintf(stderr, "known root vote was not stored\n");
        goto cleanup;
    }

    LanternSignedVote stored;
    memset(&stored, 0, sizeof(stored));
    if (lantern_store_get_signed_validator_vote(&client.store, 0, &stored) != 0) {
        fprintf(stderr, "failed to fetch stored vote\n");
        goto cleanup;
    }
    if (memcmp(&stored.data, &vote.data, sizeof(vote.data)) != 0) {
        fprintf(stderr, "stored vote data mismatch\n");
        goto cleanup;
    }
    if (memcmp(&stored.signature, &vote.signature, sizeof(vote.signature)) != 0) {
        fprintf(stderr, "stored vote signature mismatch\n");
        goto cleanup;
    }

    LanternRoot data_root;
    if (lantern_hash_tree_root_attestation_data(&vote.data.data, &data_root) != 0) {
        fprintf(stderr, "failed to hash vote data for gossip signature cache\n");
        goto cleanup;
    }
    LanternSignatureKey key = {
        .validator_index = vote.data.validator_id,
        .data_root = data_root,
    };
    LanternAttestationData cached_data;
    LanternSignature cached_signature;
    memset(&cached_data, 0, sizeof(cached_data));
    memset(&cached_signature, 0, sizeof(cached_signature));
    if (lantern_store_get_attestation_data(&client.store, &data_root, &cached_data) != 0) {
        fprintf(stderr, "attestation data cache missing accepted vote\n");
        goto cleanup;
    }
    if (memcmp(&cached_data, &vote.data.data, sizeof(vote.data.data)) != 0) {
        fprintf(stderr, "cached attestation data mismatch\n");
        goto cleanup;
    }
    if (lantern_store_get_attestation_signature(&client.store, &key, &cached_signature) == 0) {
        fprintf(stderr, "non-aggregator vote should not populate gossip signature cache\n");
        goto cleanup;
    }

    rc = 0;

cleanup:
    client_test_teardown_vote_validation_client(&client, pub, secret);
    return rc;
}

static int test_record_vote_buffers_missing_target_state(void) {
    struct lantern_client client;
    struct PQSignatureSchemePublicKey *pub = NULL;
    struct PQSignatureSchemeSecretKey *secret = NULL;
    LanternRoot anchor_root;
    LanternRoot child_root;
    LanternBlock grandchild;
    LanternRoot grandchild_root;
    int rc = 1;

    memset(&grandchild, 0, sizeof(grandchild));
    memset(&grandchild_root, 0, sizeof(grandchild_root));

    if (client_test_setup_vote_validation_client(
            &client,
            "vote_missing_target_state",
            &pub,
            &secret,
            &anchor_root,
            &child_root)
        != 0) {
        return 1;
    }
    if (test_enable_blocks_request_peer(
            &client,
            "12D3KooWLU9zbm4c9KTL3f6bAtestVoteMissingTarget111111111111")
        != 0) {
        fprintf(stderr, "failed to set up schedulable peer for missing target state test\n");
        goto cleanup;
    }

    lantern_block_body_init(&grandchild.body);
    uint64_t child_slot = 0;
    if (client_test_slot_for_root(&client, &child_root, &child_slot) != 0) {
        fprintf(stderr, "failed to resolve child slot for missing target state test\n");
        goto cleanup;
    }
    grandchild.slot = child_slot + 1u;
    grandchild.proposer_index = 0u;
    grandchild.parent_root = child_root;
    client_test_fill_root(&grandchild.state_root, 0xC3u);
    if (lantern_hash_tree_root_block(&grandchild, &grandchild_root) != 0) {
        fprintf(stderr, "failed to hash grandchild block for missing target state test\n");
        goto cleanup;
    }
    if (lantern_fork_choice_add_block(
            &client.fork_choice,
            &grandchild,
            NULL,
            &client.state.latest_justified,
            &client.state.latest_finalized,
            &grandchild_root)
        != 0) {
        fprintf(stderr, "failed to add grandchild block for missing target state test\n");
        goto cleanup;
    }

    LanternSignedVote vote;
    if (make_signed_vote_for_validator(&client, secret, 0u, &anchor_root, &grandchild_root, &vote) != 0) {
        fprintf(stderr, "failed to build signed vote for missing target state test\n");
        goto cleanup;
    }

    if (lantern_client_debug_record_vote(&client, &vote, "vote_missing_state_peer") != 0) {
        fprintf(stderr, "lantern_client_debug_record_vote failed for missing target state test\n");
        goto cleanup;
    }
    if (lantern_store_validator_has_vote(&client.store, 0u)) {
        fprintf(stderr, "vote with missing target state should not be stored\n");
        goto cleanup;
    }
    if (lantern_client_pending_vote_count(&client) != 1u) {
        fprintf(stderr, "vote with missing target state should be buffered\n");
        goto cleanup;
    }
    if (client.next_blocks_request_id != 0u) {
        fprintf(stderr, "missing target state vote should not schedule block requests\n");
        goto cleanup;
    }

    rc = 0;

cleanup:
    test_disable_blocks_request_peer(&client);
    lantern_block_body_reset(&grandchild.body);
    client_test_teardown_vote_validation_client(&client, pub, secret);
    return rc;
}

static int test_record_vote_buffers_source_root_known_only_via_historical_hashes(void) {
    struct lantern_client client;
    struct PQSignatureSchemePublicKey *pub = NULL;
    struct PQSignatureSchemeSecretKey *secret = NULL;
    LanternRoot anchor_root;
    LanternRoot child_root;
    LanternRoot historical_source_root;
    int rc = 1;

    memset(&historical_source_root, 0, sizeof(historical_source_root));

    if (client_test_setup_vote_validation_client(
            &client,
            "vote_historical_source_only",
            &pub,
            &secret,
            &anchor_root,
            &child_root)
        != 0) {
        return 1;
    }

    if (lantern_fork_choice_set_block_state(&client.fork_choice, &child_root, &client.state) != 0) {
        fprintf(stderr, "failed to cache child state for historical source test\n");
        goto cleanup;
    }

    if (lantern_root_list_resize(&client.state.historical_block_hashes, 1u) != 0) {
        fprintf(stderr, "failed to resize historical block hashes for source fallback test\n");
        goto cleanup;
    }
    client_test_fill_root(&historical_source_root, 0xA5u);
    client.state.historical_block_hashes.items[0] = historical_source_root;

    {
        uint64_t unexpected_slot = 0;
        if (client_test_slot_for_root(&client, &historical_source_root, &unexpected_slot) == 0) {
            fprintf(stderr, "historical-only source root unexpectedly exists in fork choice\n");
            goto cleanup;
        }
    }

    LanternSignedVote vote;
    memset(&vote, 0, sizeof(vote));
    uint64_t child_slot = 0;
    if (client_test_slot_for_root(&client, &child_root, &child_slot) != 0) {
        fprintf(stderr, "failed to resolve child slot for historical source test\n");
        goto cleanup;
    }
    vote.data.validator_id = 0u;
    vote.data.slot = 2u;
    vote.data.head.slot = child_slot;
    vote.data.head.root = child_root;
    vote.data.target.slot = child_slot;
    vote.data.target.root = child_root;
    vote.data.source.slot = 0u;
    vote.data.source.root = historical_source_root;

    if (client_test_sign_vote_with_secret(&vote, secret) != 0) {
        fprintf(stderr, "failed to sign vote with historical-only source root\n");
        goto cleanup;
    }

    if (lantern_client_debug_record_vote(&client, &vote, "vote_historical_source_peer") != 0) {
        fprintf(stderr, "lantern_client_debug_record_vote failed for historical source test\n");
        goto cleanup;
    }

    if (lantern_store_validator_has_vote(&client.store, 0u)) {
        fprintf(stderr, "historical-only source root vote should not be stored\n");
        goto cleanup;
    }
    if (lantern_client_pending_vote_count(&client) != 1u) {
        fprintf(stderr, "historical-only source root vote should be buffered\n");
        goto cleanup;
    }

    rc = 0;

cleanup:
    client_test_teardown_vote_validation_client(&client, pub, secret);
    return rc;
}

static int test_record_vote_buffers_unknown_head(void) {
    struct lantern_client client;
    struct PQSignatureSchemePublicKey *pub = NULL;
    struct PQSignatureSchemeSecretKey *secret = NULL;
    LanternRoot anchor_root;
    LanternRoot child_root;
    int rc = 1;

    if (client_test_setup_vote_validation_client(&client, "vote_unknown", &pub, &secret, &anchor_root, &child_root) != 0) {
        return 1;
    }

    LanternSignedVote vote;
    memset(&vote, 0, sizeof(vote));
    uint64_t child_slot = 0;
    if (client_test_slot_for_root(&client, &child_root, &child_slot) != 0) {
        fprintf(stderr, "failed to resolve child slot for unknown head test\n");
        goto cleanup;
    }
    vote.data.validator_id = 0;
    vote.data.slot = 2;
    vote.data.head.slot = child_slot;
    client_test_fill_root(&vote.data.head.root, 0xEE);
    vote.data.target.slot = child_slot;
    vote.data.target.root = child_root;
    vote.data.source.slot = 0;
    vote.data.source.root = anchor_root;

    if (client_test_sign_vote_with_secret(&vote, secret) != 0) {
        fprintf(stderr, "failed to sign vote with unknown head\n");
        goto cleanup;
    }

    if (lantern_store_validator_has_vote(&client.store, 0)) {
        fprintf(stderr, "validator unexpectedly had a stored vote before test\n");
        goto cleanup;
    }

    if (lantern_client_debug_record_vote(&client, &vote, "vote_unknown_peer") != 0) {
        fprintf(stderr, "lantern_client_debug_record_vote failed for unknown head\n");
        goto cleanup;
    }

    if (lantern_store_validator_has_vote(&client.store, 0)) {
        fprintf(stderr, "unknown head vote should not be stored\n");
        goto cleanup;
    }
    if (lantern_client_pending_vote_count(&client) != 1u) {
        fprintf(stderr, "unknown head vote should be buffered\n");
        goto cleanup;
    }

    rc = 0;

cleanup:
    client_test_teardown_vote_validation_client(&client, pub, secret);
    return rc;
}

static int test_record_vote_replays_buffered_vote_after_block_import(void) {
    struct lantern_client client;
    struct PQSignatureSchemePublicKey *pub = NULL;
    struct PQSignatureSchemeSecretKey *secret = NULL;
    LanternRoot anchor_root;
    LanternRoot child_root;
    LanternSignedBlock grandchild_block;
    LanternRoot grandchild_root;
    LanternSignedVote vote;
    char data_dir_template[256];
    int rc = 1;

    memset(&grandchild_block, 0, sizeof(grandchild_block));
    memset(&grandchild_root, 0, sizeof(grandchild_root));
    memset(&vote, 0, sizeof(vote));
    memset(data_dir_template, 0, sizeof(data_dir_template));

    if (client_test_setup_vote_validation_client(
            &client,
            "vote_replay_after_import",
            &pub,
            &secret,
            &anchor_root,
            &child_root)
        != 0) {
        return 1;
    }

    if (build_signed_head_block(&client, secret, &grandchild_block, &grandchild_root) != 0) {
        fprintf(stderr, "failed to build grandchild block for buffered vote replay test\n");
        goto cleanup;
    }
    if (lantern_fork_choice_set_block_state(
            &client.fork_choice,
            &grandchild_block.block.parent_root,
            &client.state)
        != 0) {
        fprintf(stderr, "failed to cache parent state for buffered vote replay test\n");
        goto cleanup;
    }
    if (snprintf(
            data_dir_template,
            sizeof(data_dir_template),
            "/tmp/lantern_vote_replay_%02x%02x%02x%02x_%d",
            child_root.bytes[0],
            child_root.bytes[1],
            child_root.bytes[2],
            child_root.bytes[3],
            (int)getpid())
        <= 0) {
        fprintf(stderr, "failed to format temp dir for buffered vote replay test\n");
        goto cleanup;
    }
    client.data_dir = data_dir_template;
    if (mkdir(client.data_dir, 0700) != 0) {
        fprintf(stderr, "failed to create temp dir for buffered vote replay test\n");
        goto cleanup;
    }
    if (lantern_storage_store_state_for_root(
            client.data_dir,
            &grandchild_block.block.parent_root,
            &client.state)
        != 0) {
        fprintf(stderr, "failed to persist parent state for buffered vote replay test\n");
        goto cleanup;
    }

    vote.data.validator_id = 0u;
    vote.data.slot = grandchild_block.block.slot;
    vote.data.head.slot = grandchild_block.block.slot;
    vote.data.head.root = grandchild_root;
    vote.data.target.slot = grandchild_block.block.slot;
    vote.data.target.root = grandchild_root;
    vote.data.source.slot = 0u;
    vote.data.source.root = anchor_root;
    if (client_test_sign_vote_with_secret(&vote, secret) != 0) {
        fprintf(stderr, "failed to sign buffered vote replay test fixture\n");
        goto cleanup;
    }

    if (lantern_client_debug_record_vote(&client, &vote, "vote_replay_peer") != 0) {
        fprintf(stderr, "failed to stage buffered vote for replay test\n");
        goto cleanup;
    }
    if (lantern_client_pending_vote_count(&client) != 1u) {
        fprintf(stderr, "buffered replay test vote should be queued before import\n");
        goto cleanup;
    }
    if (lantern_store_validator_has_vote(&client.store, 0u)) {
        fprintf(stderr, "buffered replay test vote should not be stored before import\n");
        goto cleanup;
    }

    if (lantern_client_debug_import_block(
            &client,
            &grandchild_block,
            &grandchild_root,
            "vote_replay_peer")
        != 1) {
        fprintf(stderr, "failed to import grandchild block for buffered vote replay test\n");
        goto cleanup;
    }

    if (lantern_client_pending_vote_count(&client) != 0u) {
        fprintf(stderr, "buffered vote replay queue should be empty after import\n");
        goto cleanup;
    }
    if (!lantern_store_validator_has_vote(&client.store, 0u)) {
        fprintf(stderr, "buffered vote should replay into store after import\n");
        goto cleanup;
    }

    LanternSignedVote stored;
    memset(&stored, 0, sizeof(stored));
    if (lantern_store_get_signed_validator_vote(&client.store, 0u, &stored) != 0) {
        fprintf(stderr, "failed to fetch replayed buffered vote from store\n");
        goto cleanup;
    }
    if (memcmp(&stored.data, &vote.data, sizeof(vote.data)) != 0
        || memcmp(&stored.signature, &vote.signature, sizeof(vote.signature)) != 0) {
        fprintf(stderr, "replayed buffered vote mismatch\n");
        goto cleanup;
    }

    rc = 0;

cleanup:
    if (client.data_dir && client.data_dir[0] != '\0') {
        char cleanup_cmd[320];
        int written = snprintf(cleanup_cmd, sizeof(cleanup_cmd), "rm -rf %s", client.data_dir);
        if (written > 0 && (size_t)written < sizeof(cleanup_cmd)) {
            (void)system(cleanup_cmd);
        }
        client.data_dir = NULL;
    }
    lantern_signed_block_with_attestation_reset(&grandchild_block);
    client_test_teardown_vote_validation_client(&client, pub, secret);
    return rc;
}

static int test_record_vote_rejects_slot_mismatch(void) {
    struct lantern_client client;
    struct PQSignatureSchemePublicKey *pub = NULL;
    struct PQSignatureSchemeSecretKey *secret = NULL;
    LanternRoot anchor_root;
    LanternRoot child_root;
    int rc = 1;

    if (client_test_setup_vote_validation_client(&client, "vote_slot_mismatch", &pub, &secret, &anchor_root, &child_root) != 0) {
        return 1;
    }

    LanternSignedVote vote;
    memset(&vote, 0, sizeof(vote));
    uint64_t child_slot = 0;
    if (client_test_slot_for_root(&client, &child_root, &child_slot) != 0) {
        fprintf(stderr, "failed to resolve child slot for slot mismatch test\n");
        goto cleanup;
    }
    vote.data.validator_id = 0;
    vote.data.slot = 2;
    uint64_t mismatch_slot = child_slot >= UINT64_MAX - 5u ? UINT64_MAX : child_slot + 5u;
    vote.data.head.slot = mismatch_slot;
    vote.data.head.root = child_root;
    vote.data.target.slot = child_slot;
    vote.data.target.root = child_root;
    vote.data.source.slot = 0;
    vote.data.source.root = anchor_root;

    if (client_test_sign_vote_with_secret(&vote, secret) != 0) {
        fprintf(stderr, "failed to sign slot mismatch vote\n");
        goto cleanup;
    }

    lantern_client_debug_record_vote(&client, &vote, "slot_mismatch_peer");

    if (lantern_store_validator_has_vote(&client.store, 0)) {
        fprintf(stderr, "slot mismatch vote should have been rejected\n");
        goto cleanup;
    }

    rc = 0;

cleanup:
    client_test_teardown_vote_validation_client(&client, pub, secret);
    return rc;
}

static int test_record_vote_rejects_head_older_than_target(void) {
    struct lantern_client client;
    struct PQSignatureSchemePublicKey *pub = NULL;
    struct PQSignatureSchemeSecretKey *secret = NULL;
    LanternRoot anchor_root;
    LanternRoot child_root;
    int rc = 1;

    if (client_test_setup_vote_validation_client(
            &client,
            "vote_head_older",
            &pub,
            &secret,
            &anchor_root,
            &child_root)
        != 0) {
        return 1;
    }

    LanternSignedVote vote;
    memset(&vote, 0, sizeof(vote));
    uint64_t child_slot = 0;
    if (client_test_slot_for_root(&client, &child_root, &child_slot) != 0) {
        fprintf(stderr, "failed to resolve child slot for head older than target test\n");
        goto cleanup;
    }
    vote.data.validator_id = 0;
    vote.data.slot = 2;
    vote.data.head.slot = 0;
    vote.data.head.root = anchor_root;
    vote.data.target.slot = child_slot;
    vote.data.target.root = child_root;
    vote.data.source.slot = 0;
    vote.data.source.root = anchor_root;

    if (client_test_sign_vote_with_secret(&vote, secret) != 0) {
        fprintf(stderr, "failed to sign head older than target vote\n");
        goto cleanup;
    }

    lantern_client_debug_record_vote(&client, &vote, "head_older_peer");

    if (lantern_store_validator_has_vote(&client.store, 0)) {
        fprintf(stderr, "head older than target vote should have been rejected\n");
        goto cleanup;
    }

    rc = 0;

cleanup:
    client_test_teardown_vote_validation_client(&client, pub, secret);
    return rc;
}

static int test_record_vote_rejects_future_slot(void) {
    struct lantern_client client;
    struct PQSignatureSchemePublicKey *pub = NULL;
    struct PQSignatureSchemeSecretKey *secret = NULL;
    LanternRoot anchor_root;
    LanternRoot child_root;
    int rc = 1;

    if (client_test_setup_vote_validation_client(&client, "vote_future_slot", &pub, &secret, &anchor_root, &child_root) != 0) {
        return 1;
    }

    uint64_t current_slot = 0;
    double now_seconds = lantern_time_now_seconds();
    if (now_seconds < 0.0) {
        now_seconds = 0.0;
    }
    uint32_t seconds_per_slot = client.fork_choice.seconds_per_slot == 0 ? 1u : client.fork_choice.seconds_per_slot;
    uint64_t now = (uint64_t)now_seconds;
    if (now >= client.fork_choice.config.genesis_time) {
        current_slot = (now - client.fork_choice.config.genesis_time) / seconds_per_slot;
    }
    uint64_t allowed_slot = current_slot == UINT64_MAX ? UINT64_MAX : current_slot + 1u;
    uint64_t future_slot = allowed_slot == UINT64_MAX ? UINT64_MAX : allowed_slot + 8u;
    if (future_slot <= allowed_slot) {
        future_slot = allowed_slot + 1u;
    }

    LanternSignedVote vote;
    memset(&vote, 0, sizeof(vote));
    uint64_t child_slot = 0;
    if (client_test_slot_for_root(&client, &child_root, &child_slot) != 0) {
        fprintf(stderr, "failed to resolve child slot for future slot test\n");
        goto cleanup;
    }
    vote.data.validator_id = 0;
    vote.data.slot = future_slot;
    vote.data.head.slot = child_slot;
    vote.data.head.root = child_root;
    vote.data.target.slot = child_slot;
    vote.data.target.root = child_root;
    vote.data.source.slot = 0;
    vote.data.source.root = anchor_root;

    lantern_client_debug_record_vote(&client, &vote, "future_slot_peer");

    if (lantern_store_validator_has_vote(&client.store, 0)) {
        fprintf(stderr, "future slot vote should have been dropped\n");
        goto cleanup;
    }

    rc = 0;

cleanup:
    client_test_teardown_vote_validation_client(&client, pub, secret);
    return rc;
}

static int test_validator_refresh_cached_vote_updates_source(void) {
    struct lantern_client client;
    struct PQSignatureSchemePublicKey *pub = NULL;
    struct PQSignatureSchemeSecretKey *secret = NULL;
    LanternRoot anchor_root;
    LanternRoot child_root;
    int rc = 1;

    if (client_test_setup_vote_validation_client(
            &client,
            "vote_refresh",
            &pub,
            &secret,
            &anchor_root,
            &child_root)
        != 0) {
        return 1;
    }

    struct lantern_local_validator validator;
    memset(&validator, 0, sizeof(validator));
    validator.global_index = 0;
    validator.attestation_secret_key = secret;
    validator.has_attestation_secret_handle = true;

    LanternSignedVote stale;
    memset(&stale, 0, sizeof(stale));
    stale.data.validator_id = validator.global_index;
    stale.data.slot = 4;
    client_test_fill_root_with_index(&stale.data.head.root, 0x10u);
    stale.data.head.slot = 4;
    stale.data.target.slot = 8;
    client_test_fill_root_with_index(&stale.data.target.root, 0x20u);
    stale.data.source.slot = 0;
    stale.data.source.root = anchor_root;

    if (client_test_sign_vote_with_secret(&stale, secret) != 0) {
        fprintf(stderr, "failed to sign stale vote for refresh test\n");
        goto cleanup;
    }

    LanternSignedVote refreshed = stale;
    LanternCheckpoint new_head = stale.data.head;
    new_head.slot += 2u;
    client_test_fill_root_with_index(&new_head.root, 0x30u);
    LanternCheckpoint new_target = stale.data.target;
    new_target.slot += 2u;
    client_test_fill_root_with_index(&new_target.root, 0x40u);
    LanternCheckpoint new_source = stale.data.source;
    new_source.slot = 1u;
    client_test_fill_root_with_index(&new_source.root, 0x50u);

    bool refreshed_flag = false;
    int refresh_rc = lantern_validator_refresh_cached_vote(
        &validator,
        stale.data.slot,
        &new_head,
        &new_target,
        &new_source,
        &refreshed,
        &refreshed_flag);
    if (refresh_rc != LANTERN_CLIENT_OK || !refreshed_flag) {
        fprintf(stderr, "expected cached vote refresh to occur\n");
        goto cleanup;
    }
    if (refreshed.data.source.slot != new_source.slot
        || memcmp(refreshed.data.source.root.bytes, new_source.root.bytes, LANTERN_ROOT_SIZE) != 0) {
        fprintf(stderr, "cached vote source was not updated\n");
        goto cleanup;
    }
    if (memcmp(refreshed.signature.bytes, stale.signature.bytes, LANTERN_SIGNATURE_SIZE) == 0) {
        fprintf(stderr, "cached vote signature did not change after refresh\n");
        goto cleanup;
    }

    LanternSignedVote second = refreshed;
    refreshed_flag = true;
    if (lantern_validator_refresh_cached_vote(
            &validator,
            stale.data.slot,
            &new_head,
            &new_target,
            &new_source,
            &second,
            &refreshed_flag)
        != LANTERN_CLIENT_OK) {
        fprintf(stderr, "expected cached vote refresh to be a no-op\n");
        goto cleanup;
    }
    if (refreshed_flag) {
        fprintf(stderr, "no-op refresh should not set refreshed flag\n");
        goto cleanup;
    }
    if (memcmp(second.signature.bytes, refreshed.signature.bytes, LANTERN_SIGNATURE_SIZE) != 0) {
        fprintf(stderr, "cached vote signature changed during no-op refresh\n");
        goto cleanup;
    }

    rc = 0;

cleanup:
    client_test_teardown_vote_validation_client(&client, pub, secret);
    return rc;
}

static int test_validator_sign_with_key_advances_only_selected_secret(void) {
    struct PQSignatureSchemePublicKey *pub = NULL;
    struct PQSignatureSchemePublicKey *unused_pub = NULL;
    struct PQSignatureSchemeSecretKey *attestation_secret = NULL;
    struct PQSignatureSchemeSecretKey *proposal_secret = NULL;
    struct lantern_local_validator validator;
    LanternRoot message;
    LanternSignature signature;
    int rc = 1;

    memset(&validator, 0, sizeof(validator));
    memset(&message, 0, sizeof(message));
    memset(&signature, 0, sizeof(signature));

    if (client_test_load_precomputed_keypair(0u, &pub, &attestation_secret) != 0) {
        fprintf(stderr, "failed to load attestation keypair for key-advance test\n");
        goto cleanup;
    }
    if (client_test_load_precomputed_keypair(0u, &unused_pub, &proposal_secret) != 0) {
        fprintf(stderr, "failed to load proposal keypair for key-advance test\n");
        goto cleanup;
    }

    validator.global_index = 0u;
    validator.attestation_secret_key = attestation_secret;
    validator.proposal_secret_key = proposal_secret;
    validator.has_attestation_secret_handle = true;
    validator.has_proposal_secret_handle = true;

    struct PQRange initial_attestation = pq_get_prepared_interval(validator.attestation_secret_key);
    struct PQRange initial_proposal = pq_get_prepared_interval(validator.proposal_secret_key);
    if (initial_attestation.end <= initial_attestation.start
        || initial_proposal.end <= initial_proposal.start) {
        fprintf(stderr, "prepared interval unavailable for key-advance test\n");
        goto cleanup;
    }

    uint64_t slot = initial_proposal.end;
    if (slot == 0u) {
        fprintf(stderr, "invalid proposal slot selection in key-advance test\n");
        goto cleanup;
    }

    client_test_fill_root_with_index(&message, 0xAA55u);
    if (validator_sign_with_key(&validator, slot, &message, true, &signature) != LANTERN_CLIENT_OK) {
        fprintf(stderr, "validator_sign_with_key failed for proposal key advance test\n");
        goto cleanup;
    }

    struct PQRange updated_attestation = pq_get_prepared_interval(validator.attestation_secret_key);
    struct PQRange updated_proposal = pq_get_prepared_interval(validator.proposal_secret_key);
    if (updated_attestation.start != initial_attestation.start
        || updated_attestation.end != initial_attestation.end) {
        fprintf(stderr, "attestation key should not advance during proposal signing\n");
        goto cleanup;
    }
    if (!pq_range_contains_slot(updated_proposal, slot)) {
        fprintf(stderr, "proposal key was not advanced to cover slot %" PRIu64 "\n", slot);
        goto cleanup;
    }
    if (updated_proposal.start == initial_proposal.start
        && updated_proposal.end == initial_proposal.end) {
        fprintf(stderr, "proposal key interval did not change after signing future slot\n");
        goto cleanup;
    }
    if (!lantern_signature_verify_pk(pub, slot, &signature, &message)) {
        fprintf(stderr, "proposal signature failed verification after key advance\n");
        goto cleanup;
    }

    rc = 0;

cleanup:
    if (unused_pub) {
        pq_public_key_free(unused_pub);
    }
    if (proposal_secret) {
        pq_secret_key_free(proposal_secret);
    }
    if (attestation_secret) {
        pq_secret_key_free(attestation_secret);
    }
    if (pub) {
        pq_public_key_free(pub);
    }
    return rc;
}

static int test_validator_build_block_leaves_attestation_key_untouched(void) {
    struct lantern_client client;
    struct PQSignatureSchemePublicKey *attestation_pub = NULL;
    struct PQSignatureSchemeSecretKey *attestation_secret = NULL;
    struct PQSignatureSchemePublicKey *proposal_pub = NULL;
    struct PQSignatureSchemeSecretKey *proposal_secret = NULL;
    struct lantern_local_validator validator;
    LanternSignedBlock block;
    LanternRoot block_root;
    int rc = 1;

    memset(&validator, 0, sizeof(validator));
    memset(&block_root, 0, sizeof(block_root));
    lantern_signed_block_init(&block);

    if (client_test_setup_vote_validation_client(
            &client,
            "build_block_dual_key",
            &attestation_pub,
            &attestation_secret,
            NULL,
            NULL)
        != 0) {
        goto cleanup;
    }
    if (client_test_load_precomputed_keypair(0u, &proposal_pub, &proposal_secret) != 0) {
        fprintf(stderr, "failed to load proposal keypair for block build key-isolation test\n");
        goto cleanup;
    }

    validator.global_index = 0u;
    validator.attestation_secret_key = attestation_secret;
    validator.proposal_secret_key = proposal_secret;
    client.local_validators = &validator;
    client.local_validator_count = 1u;

    struct PQRange initial_attestation = pq_get_prepared_interval(validator.attestation_secret_key);
    struct PQRange initial_proposal = pq_get_prepared_interval(validator.proposal_secret_key);
    if (initial_attestation.end <= initial_attestation.start
        || initial_proposal.end <= initial_proposal.start) {
        fprintf(stderr, "prepared interval unavailable for block build key-isolation test\n");
        goto cleanup;
    }

    uint64_t slot = client.state.slot + 1u;

    if (validator_build_block(&client, slot, 0u, &block) != LANTERN_CLIENT_OK) {
        fprintf(stderr, "validator_build_block failed for key-isolation test\n");
        goto cleanup;
    }
    if (lantern_hash_tree_root_block(&block.block, &block_root) != 0) {
        fprintf(stderr, "failed to hash built block for key-isolation test\n");
        goto cleanup;
    }

    struct PQRange updated_attestation = pq_get_prepared_interval(validator.attestation_secret_key);
    struct PQRange updated_proposal = pq_get_prepared_interval(validator.proposal_secret_key);
    if (updated_attestation.start != initial_attestation.start
        || updated_attestation.end != initial_attestation.end) {
        fprintf(stderr, "attestation key should remain unchanged during block production\n");
        goto cleanup;
    }
    if (!pq_range_contains_slot(updated_proposal, slot)) {
        fprintf(stderr, "proposal key was not prepared for block slot %" PRIu64 "\n", slot);
        goto cleanup;
    }
    if (!lantern_signature_verify_pk(
            proposal_pub,
            slot,
            &block.signatures.proposer_signature,
            &block_root)) {
        fprintf(stderr, "block proposer signature did not verify with the proposal key\n");
        goto cleanup;
    }

    rc = 0;

cleanup:
    lantern_signed_block_reset(&block);
    if (proposal_secret) {
        pq_secret_key_free(proposal_secret);
    }
    if (proposal_pub) {
        pq_public_key_free(proposal_pub);
    }
    client_test_teardown_vote_validation_client(&client, attestation_pub, attestation_secret);
    return rc;
}

static int test_client_load_xmss_keys_reads_annotated_validators(void) {
    struct lantern_client client;
    char temp_dir_template[] = "/tmp/lantern-annotated-xmss-XXXXXX";
    char *temp_dir = NULL;
    char annotated_path[PATH_MAX];
    char attester_src[PATH_MAX];
    char proposer_src[PATH_MAX];
    char attester_dst[PATH_MAX];
    char proposer_dst[PATH_MAX];
    int rc = 1;

    memset(&client, 0, sizeof(client));
    memset(annotated_path, 0, sizeof(annotated_path));
    memset(attester_src, 0, sizeof(attester_src));
    memset(proposer_src, 0, sizeof(proposer_src));
    memset(attester_dst, 0, sizeof(attester_dst));
    memset(proposer_dst, 0, sizeof(proposer_dst));

    temp_dir = mkdtemp(temp_dir_template);
    if (!temp_dir) {
        perror("mkdtemp annotated");
        return 1;
    }
    if (test_fixture_secret_key_path(0u, attester_src, sizeof(attester_src)) != 0
        || test_fixture_secret_key_path(1u, proposer_src, sizeof(proposer_src)) != 0) {
        fprintf(stderr, "failed to resolve fixture secret key paths for annotated test\n");
        goto cleanup;
    }
    if (snprintf(annotated_path, sizeof(annotated_path), "%s/annotated_validators.yaml", temp_dir) <= 0
        || snprintf(
               attester_dst,
               sizeof(attester_dst),
               "%s/validator_0_attester_key_sk.json",
               temp_dir)
               <= 0
        || snprintf(
               proposer_dst,
               sizeof(proposer_dst),
               "%s/validator_0_proposer_key_sk.json",
               temp_dir)
               <= 0) {
        fprintf(stderr, "failed to build annotated fixture paths\n");
        goto cleanup;
    }
    if (test_copy_file(attester_src, attester_dst) != 0
        || test_copy_file(proposer_src, proposer_dst) != 0) {
        fprintf(stderr, "failed to copy annotated fixture secret keys\n");
        goto cleanup;
    }

    FILE *annotated = fopen(annotated_path, "w");
    if (!annotated) {
        perror("fopen annotated");
        goto cleanup;
    }
    fputs(
        "manifest_loader:\n"
        "  - index: 0\n"
        "    pubkey_hex: 00\n"
        "    privkey_file: validator_0_attester_key_sk.json\n"
        "  - index: 0\n"
        "    pubkey_hex: 11\n"
        "    privkey_file: validator_0_proposer_key_sk.json\n"
        "other_node:\n"
        "  - index: 1\n"
        "    pubkey_hex: 22\n"
        "    privkey_file: validator_1_attester_key_sk.json\n"
        "  - index: 1\n"
        "    pubkey_hex: 33\n"
        "    privkey_file: validator_1_proposer_key_sk.json\n",
        annotated);
    fclose(annotated);

    client.node_id = (char *)"manifest_loader";
    client.genesis.chain_config.validator_count = 1u;
    client.local_validators = calloc(1u, sizeof(*client.local_validators));
    if (!client.local_validators) {
        fprintf(stderr, "failed to allocate local validator for annotated test\n");
        goto cleanup;
    }
    client.local_validator_count = 1u;
    client.local_validators[0].global_index = 0u;
    client.xmss_key_dir = strdup(temp_dir);
    client.genesis_paths.validator_registry_path = strdup(annotated_path);
    if (!client.xmss_key_dir || !client.genesis_paths.validator_registry_path) {
        fprintf(stderr, "failed to copy annotated fixture paths\n");
        goto cleanup;
    }

    if (lantern_client_load_xmss_keys(&client) != LANTERN_CLIENT_OK) {
        fprintf(stderr, "lantern_client_load_xmss_keys failed for annotated validators test\n");
        goto cleanup;
    }
    if (!client.local_validators[0].attestation_secret_key
        || !client.local_validators[0].proposal_secret_path) {
        fprintf(stderr, "annotated validators did not populate attestation handle and proposal path\n");
        goto cleanup;
    }
    if (client.local_validators[0].proposal_secret_key) {
        fprintf(stderr, "annotated validators should defer loading proposal secret handles\n");
        goto cleanup;
    }
    LanternRoot message;
    LanternSignature signature;
    memset(&message, 0, sizeof(message));
    memset(&signature, 0, sizeof(signature));
    if (validator_sign_with_key(
            &client.local_validators[0],
            0u,
            &message,
            true,
            &signature)
        != LANTERN_CLIENT_OK) {
        fprintf(stderr, "deferred proposal secret path failed to sign\n");
        goto cleanup;
    }
    if (client.local_validators[0].proposal_secret_key) {
        fprintf(stderr, "deferred proposal signing should not retain the proposal handle\n");
        goto cleanup;
    }

    rc = 0;

cleanup:
    free(client.genesis_paths.validator_registry_path);
    client.genesis_paths.validator_registry_path = NULL;
    free(client.xmss_key_dir);
    client.xmss_key_dir = NULL;
    lantern_client_reset_local_validators(&client);
    if (annotated_path[0] != '\0') {
        unlink(annotated_path);
    }
    if (attester_dst[0] != '\0') {
        unlink(attester_dst);
    }
    if (proposer_dst[0] != '\0') {
        unlink(proposer_dst);
    }
    if (temp_dir) {
        rmdir(temp_dir);
    }
    return rc;
}

static int test_client_load_xmss_keys_rejects_incomplete_annotated_validator(void) {
    struct lantern_client client;
    char temp_dir_template[] = "/tmp/lantern-annotated-xmss-XXXXXX";
    char *temp_dir = NULL;
    char annotated_path[PATH_MAX];
    char attester_src[PATH_MAX];
    char attester_dst[PATH_MAX];
    int rc = 1;

    memset(&client, 0, sizeof(client));
    memset(annotated_path, 0, sizeof(annotated_path));
    memset(attester_src, 0, sizeof(attester_src));
    memset(attester_dst, 0, sizeof(attester_dst));

    temp_dir = mkdtemp(temp_dir_template);
    if (!temp_dir) {
        perror("mkdtemp incomplete annotated");
        return 1;
    }
    if (test_fixture_secret_key_path(0u, attester_src, sizeof(attester_src)) != 0) {
        fprintf(stderr, "failed to resolve fixture secret key path for incomplete annotated test\n");
        goto cleanup;
    }
    if (snprintf(annotated_path, sizeof(annotated_path), "%s/annotated_validators.yaml", temp_dir) <= 0
        || snprintf(
               attester_dst,
               sizeof(attester_dst),
               "%s/validator_0_attester_key_sk.json",
               temp_dir)
               <= 0) {
        fprintf(stderr, "failed to build incomplete annotated fixture paths\n");
        goto cleanup;
    }
    if (test_copy_file(attester_src, attester_dst) != 0) {
        fprintf(stderr, "failed to copy incomplete annotated fixture secret key\n");
        goto cleanup;
    }

    FILE *annotated = fopen(annotated_path, "w");
    if (!annotated) {
        perror("fopen incomplete annotated");
        goto cleanup;
    }
    fputs(
        "manifest_loader:\n"
        "  - index: 0\n"
        "    pubkey_hex: 00\n"
        "    privkey_file: validator_0_attester_key_sk.json\n",
        annotated);
    fclose(annotated);

    client.node_id = (char *)"manifest_loader";
    client.genesis.chain_config.validator_count = 1u;
    client.local_validators = calloc(1u, sizeof(*client.local_validators));
    if (!client.local_validators) {
        fprintf(stderr, "failed to allocate local validator for incomplete annotated test\n");
        goto cleanup;
    }
    client.local_validator_count = 1u;
    client.local_validators[0].global_index = 0u;
    client.xmss_key_dir = strdup(temp_dir);
    client.genesis_paths.validator_registry_path = strdup(annotated_path);
    if (!client.xmss_key_dir || !client.genesis_paths.validator_registry_path) {
        fprintf(stderr, "failed to copy incomplete annotated fixture paths\n");
        goto cleanup;
    }

    if (lantern_client_load_xmss_keys(&client) == LANTERN_CLIENT_OK) {
        fprintf(stderr, "incomplete annotated validators should be rejected\n");
        goto cleanup;
    }

    rc = 0;

cleanup:
    free(client.genesis_paths.validator_registry_path);
    client.genesis_paths.validator_registry_path = NULL;
    free(client.xmss_key_dir);
    client.xmss_key_dir = NULL;
    lantern_client_reset_local_validators(&client);
    if (annotated_path[0] != '\0') {
        unlink(annotated_path);
    }
    if (attester_dst[0] != '\0') {
        unlink(attester_dst);
    }
    if (temp_dir) {
        rmdir(temp_dir);
    }
    return rc;
}

static int test_record_vote_preserves_state_root(void) {
    struct lantern_client client;
    struct PQSignatureSchemePublicKey *pub = NULL;
    struct PQSignatureSchemeSecretKey *secret = NULL;
    LanternRoot anchor_root;
    LanternRoot child_root;
    int rc = 1;

    if (client_test_setup_vote_validation_client(&client, "vote_root", &pub, &secret, &anchor_root, &child_root) != 0) {
        return 1;
    }

    LanternCheckpoint pre_justified = client.state.latest_justified;
    LanternCheckpoint pre_finalized = client.state.latest_finalized;
    LanternRoot pre_state_root;
    if (lantern_hash_tree_root_state(&client.state, &pre_state_root) != 0) {
        fprintf(stderr, "failed to hash pre-vote state\n");
        goto cleanup;
    }

    LanternSignedVote vote;
    memset(&vote, 0, sizeof(vote));
    uint64_t child_slot = 0;
    if (client_test_slot_for_root(&client, &child_root, &child_slot) != 0) {
        fprintf(stderr, "failed to resolve child slot for root preservation test\n");
        goto cleanup;
    }
    vote.data.validator_id = 0;
    vote.data.slot = 2;
    vote.data.head.slot = child_slot;
    vote.data.head.root = child_root;
    vote.data.target.slot = child_slot;
    vote.data.target.root = child_root;
    vote.data.source.slot = 0;
    vote.data.source.root = anchor_root;

    if (client_test_sign_vote_with_secret(&vote, secret) != 0) {
        fprintf(stderr, "failed to sign vote for root preservation test\n");
        goto cleanup;
    }

    if (lantern_client_debug_record_vote(&client, &vote, "vote_root_peer") != 0) {
        fprintf(stderr, "lantern_client_debug_record_vote failed for root preservation test\n");
        goto cleanup;
    }

    LanternRoot post_state_root;
    if (lantern_hash_tree_root_state(&client.state, &post_state_root) != 0) {
        fprintf(stderr, "failed to hash post-vote state\n");
        goto cleanup;
    }

    if (memcmp(pre_state_root.bytes, post_state_root.bytes, LANTERN_ROOT_SIZE) != 0) {
        fprintf(stderr, "state root changed after gossip vote\n");
        goto cleanup;
    }
    if (client.state.latest_justified.slot != pre_justified.slot
        || memcmp(client.state.latest_justified.root.bytes, pre_justified.root.bytes, LANTERN_ROOT_SIZE) != 0) {
        fprintf(stderr, "latest_justified changed after gossip vote\n");
        goto cleanup;
    }
    if (client.state.latest_finalized.slot != pre_finalized.slot
        || memcmp(client.state.latest_finalized.root.bytes, pre_finalized.root.bytes, LANTERN_ROOT_SIZE) != 0) {
        fprintf(stderr, "latest_finalized changed after gossip vote\n");
        goto cleanup;
    }

    rc = 0;

cleanup:
    client_test_teardown_vote_validation_client(&client, pub, secret);
    return rc;
}

static int test_record_vote_defers_interval_pipeline(void) {
    struct lantern_client client;
    struct PQSignatureSchemePublicKey *pub = NULL;
    struct PQSignatureSchemeSecretKey *secret = NULL;
    LanternRoot anchor_root;
    LanternRoot child_root;
    struct lantern_validator_config_entry assigned;
    int rc = 1;

    memset(&assigned, 0, sizeof(assigned));

    if (client_test_setup_vote_validation_client(&client, "vote_interval", &pub, &secret, &anchor_root, &child_root) != 0) {
        return 1;
    }

    assigned.enr.is_aggregator = true;
    client.assigned_validators = &assigned;
    client.gossip.attestation_subnet_id = 0u;
    snprintf(
        client.gossip.aggregated_attestation_topic,
        sizeof(client.gossip.aggregated_attestation_topic),
        "test/vote_interval_aggregation");
    lantern_gossipsub_service_set_loopback_only(&client.gossip, 1);

    LanternSignedVote vote;
    memset(&vote, 0, sizeof(vote));
    uint64_t child_slot = 0;
    if (client_test_slot_for_root(&client, &child_root, &child_slot) != 0) {
        fprintf(stderr, "failed to resolve child slot for interval pipeline test\n");
        goto cleanup;
    }
    vote.data.validator_id = 0;
    vote.data.slot = child_slot;
    vote.data.head.slot = child_slot;
    vote.data.head.root = child_root;
    vote.data.target.slot = child_slot;
    vote.data.target.root = child_root;
    vote.data.source.slot = 0;
    vote.data.source.root = anchor_root;

    if (client_test_sign_vote_with_secret(&vote, secret) != 0) {
        fprintf(stderr, "failed to sign vote for interval pipeline test\n");
        goto cleanup;
    }

    LanternRoot safe_before = client.fork_choice.safe_target;
    bool had_safe_before = client.fork_choice.has_safe_target;

    if (lantern_client_debug_record_vote(&client, &vote, "vote_interval_peer") != 0) {
        fprintf(stderr, "lantern_client_debug_record_vote failed for interval pipeline test\n");
        goto cleanup;
    }

    LanternRoot data_root;
    if (lantern_hash_tree_root_attestation_data(&vote.data.data, &data_root) != 0) {
        fprintf(stderr, "failed to hash vote data for interval pipeline test\n");
        goto cleanup;
    }
    LanternSignatureKey key = {
        .validator_index = vote.data.validator_id,
        .data_root = data_root,
    };
    LanternSignature cached_signature;
    memset(&cached_signature, 0, sizeof(cached_signature));
    if (lantern_store_get_attestation_signature(&client.store, &key, &cached_signature) != 0) {
        fprintf(stderr, "gossip signature cache missing vote before aggregation\n");
        goto cleanup;
    }
    if (memcmp(&cached_signature, &vote.signature, sizeof(vote.signature)) != 0) {
        fprintf(stderr, "cached gossip signature mismatch before aggregation\n");
        goto cleanup;
    }

    if (client.store.new_aggregated_payloads.length != 0
        || client.store.known_aggregated_payloads.length != 0) {
        fprintf(stderr, "aggregated payload pools should be empty before interval 2 aggregation\n");
        goto cleanup;
    }
    if (had_safe_before) {
        if (memcmp(client.fork_choice.safe_target.bytes, safe_before.bytes, LANTERN_ROOT_SIZE) != 0) {
            fprintf(stderr, "safe target changed before interval 2\n");
            goto cleanup;
        }
    }

    if (advance_client_fork_choice_intervals(&client, 1, false) != 0) {
        fprintf(stderr, "failed to advance fork choice to interval 1\n");
        goto cleanup;
    }
    if (had_safe_before) {
        if (memcmp(client.fork_choice.safe_target.bytes, safe_before.bytes, LANTERN_ROOT_SIZE) != 0) {
            fprintf(stderr, "safe target changed during interval 1\n");
            goto cleanup;
        }
    }

    if (advance_client_fork_choice_intervals(&client, 1, false) != 0) {
        fprintf(stderr, "failed to advance fork choice to interval 2\n");
        goto cleanup;
    }
    client.validator_duty.slot_attested = true;
    client.validator_duty.slot_aggregated = false;
    if (lantern_client_debug_run_interval_aggregation(&client, vote.data.slot) != LANTERN_CLIENT_OK) {
        fprintf(stderr, "interval 2 aggregation failed for staged gossip vote\n");
        goto cleanup;
    }
    if (client.store.new_aggregated_payloads.length != 1
        || client.store.known_aggregated_payloads.length != 0) {
        fprintf(stderr, "interval 2 aggregation did not publish the local proof into the new payload pool\n");
        goto cleanup;
    }
    if (had_safe_before) {
        if (memcmp(client.fork_choice.safe_target.bytes, safe_before.bytes, LANTERN_ROOT_SIZE) != 0) {
            fprintf(stderr, "safe target changed during interval 2\n");
            goto cleanup;
        }
    }

    if (advance_client_fork_choice_intervals(&client, 1, false) != 0) {
        fprintf(stderr, "failed to advance fork choice to interval 3\n");
        goto cleanup;
    }
    if (!client.fork_choice.has_safe_target) {
        fprintf(stderr, "safe target unavailable after interval 3\n");
        goto cleanup;
    }
    if (memcmp(client.fork_choice.safe_target.bytes, child_root.bytes, LANTERN_ROOT_SIZE) != 0) {
        fprintf(stderr, "safe target did not reflect gossip vote after interval 3\n");
        goto cleanup;
    }

    if (advance_client_fork_choice_intervals(&client, 1, false) != 0) {
        fprintf(stderr, "failed to advance fork choice to interval 4\n");
        goto cleanup;
    }
    if (client.store.new_aggregated_payloads.length != 0
        || client.store.known_aggregated_payloads.length != 1) {
        fprintf(stderr, "aggregated payload pools diverged after interval 4\n");
        goto cleanup;
    }
    LanternRoot head_after_accept;
    if (lantern_fork_choice_current_head(&client.fork_choice, &head_after_accept) != 0
        || memcmp(head_after_accept.bytes, child_root.bytes, LANTERN_ROOT_SIZE) != 0) {
        fprintf(stderr, "head did not update from known aggregated payloads after interval 4\n");
        goto cleanup;
    }

    rc = 0;

cleanup:
    client_test_teardown_vote_validation_client(&client, pub, secret);
    return rc;
}

static int test_chain_service_tick_to_skips_stale_intervals(void) {
    struct lantern_client client;
    struct PQSignatureSchemePublicKey *pub = NULL;
    struct PQSignatureSchemeSecretKey *secret = NULL;
    LanternRoot anchor_root;
    LanternRoot child_root;
    int rc = 1;

    if (client_test_setup_vote_validation_client(&client, "chain_service_skip", &pub, &secret, &anchor_root, &child_root) != 0) {
        return 1;
    }

    uint64_t intervals_per_slot = client.fork_choice.intervals_per_slot;
    uint64_t target_interval = intervals_per_slot * 2u;
    uint64_t skipped_to_interval = UINT64_MAX;
    uint64_t ticked_intervals = 0u;

    if (intervals_per_slot == 0u) {
        fprintf(stderr, "intervals_per_slot unavailable for chain service skip test\n");
        goto cleanup;
    }
    if (lantern_client_chain_service_tick_to(
            &client,
            target_interval,
            false,
            &skipped_to_interval,
            &ticked_intervals)
        != 0) {
        fprintf(stderr, "chain service catch-up failed\n");
        goto cleanup;
    }
    if (skipped_to_interval != target_interval - intervals_per_slot) {
        fprintf(stderr,
            "chain service did not skip stale intervals correctly: expected %" PRIu64 " got %" PRIu64 "\n",
            target_interval - intervals_per_slot,
            skipped_to_interval);
        goto cleanup;
    }
    if (ticked_intervals != intervals_per_slot) {
        fprintf(stderr,
            "chain service tick count mismatch after skip: expected %" PRIu64 " got %" PRIu64 "\n",
            intervals_per_slot,
            ticked_intervals);
        goto cleanup;
    }
    if (client.fork_choice.time_intervals != target_interval) {
        fprintf(stderr,
            "fork choice time mismatch after chain service catch-up: expected %" PRIu64 " got %" PRIu64 "\n",
            target_interval,
            client.fork_choice.time_intervals);
        goto cleanup;
    }

    rc = 0;

cleanup:
    client_test_teardown_vote_validation_client(&client, pub, secret);
    return rc;
}

static int test_skip_fork_choice_intervals_replays_interval_side_effects(void) {
    struct lantern_client client;
    struct PQSignatureSchemePublicKey *pub = NULL;
    struct PQSignatureSchemeSecretKey *secret = NULL;
    LanternRoot anchor_root;
    LanternRoot child_root;
    int rc = 1;

    if (client_test_setup_vote_validation_client(&client, "skip_interval_effects", &pub, &secret, &anchor_root, &child_root) != 0) {
        return 1;
    }

    if (client.fork_choice.time_intervals != 0u) {
        fprintf(stderr, "unexpected initial interval %" PRIu64 " for skip replay test\n", client.fork_choice.time_intervals);
        goto cleanup;
    }
    LanternSignedVote vote;
    memset(&vote, 0, sizeof(vote));
    if (make_signed_vote_for_validator(&client, secret, 0u, &anchor_root, &child_root, &vote) != 0) {
        fprintf(stderr, "failed to build signed vote for skip replay test\n");
        goto cleanup;
    }
    LanternRoot data_root;
    if (lantern_hash_tree_root_attestation_data(&vote.data.data, &data_root) != 0) {
        fprintf(stderr, "failed to hash skip replay vote data\n");
        goto cleanup;
    }
    LanternAggregatedSignatureProof proof;
    if (test_make_dummy_proof(&proof, vote.data.validator_id, 0xA6) != 0) {
        fprintf(stderr, "failed to build skip replay proof\n");
        goto cleanup;
    }
    if (lantern_client_add_new_aggregated_payload(
            &client,
            &data_root,
            &vote.data.data,
            &proof,
            vote.data.target.slot)
        != 0) {
        lantern_aggregated_signature_proof_reset(&proof);
        fprintf(stderr, "failed to stage skip replay aggregated payload\n");
        goto cleanup;
    }
    lantern_aggregated_signature_proof_reset(&proof);

    if (lantern_client_skip_fork_choice_intervals_locked(&client, 4u) != 0) {
        fprintf(stderr, "skip replay helper failed to advance intervals\n");
        goto cleanup;
    }

    if (client.fork_choice.time_intervals != 4u) {
        fprintf(stderr, "skip replay helper ended at wrong interval: %" PRIu64 "\n", client.fork_choice.time_intervals);
        goto cleanup;
    }
    if (!client.fork_choice.has_safe_target
        || memcmp(client.fork_choice.safe_target.bytes, child_root.bytes, LANTERN_ROOT_SIZE) != 0) {
        fprintf(stderr, "skip replay helper did not update safe target at skipped interval 3\n");
        goto cleanup;
    }
    if (client.store.new_aggregated_payloads.length != 0
        || client.store.known_aggregated_payloads.length != 1) {
        fprintf(stderr, "skip replay helper did not promote payload at skipped interval 4\n");
        goto cleanup;
    }

    LanternRoot head;
    if (lantern_fork_choice_current_head(&client.fork_choice, &head) != 0
        || memcmp(head.bytes, child_root.bytes, LANTERN_ROOT_SIZE) != 0) {
        fprintf(stderr, "skip replay helper did not recompute head from skipped interval 4\n");
        goto cleanup;
    }

    rc = 0;

cleanup:
    client_test_teardown_vote_validation_client(&client, pub, secret);
    return rc;
}

static int test_safe_target_uses_only_new_attached_aggregated_payloads(void) {
    struct lantern_client client;
    struct PQSignatureSchemePublicKey *pub = NULL;
    struct PQSignatureSchemeSecretKey *secret = NULL;
    LanternRoot anchor_root;
    LanternRoot child_root;
    int rc = 1;

    if (client_test_setup_vote_validation_client_with_validator_count(
            &client,
            "safe_target_aggregated",
            3u,
            &pub,
            &secret,
            &anchor_root,
            &child_root)
        != 0) {
        return 1;
    }

    uint64_t child_slot = 0u;
    if (client_test_slot_for_root(&client, &child_root, &child_slot) != 0) {
        fprintf(stderr, "failed to resolve child slot for aggregated safe-target test\n");
        goto cleanup;
    }

    LanternAttestationData data;
    memset(&data, 0, sizeof(data));
    data.slot = child_slot;
    data.head.slot = child_slot;
    data.head.root = child_root;
    data.target.slot = child_slot;
    data.target.root = child_root;
    data.source.slot = 0u;
    data.source.root = anchor_root;

    LanternRoot data_root;
    if (lantern_hash_tree_root_attestation_data(&data, &data_root) != 0) {
        fprintf(stderr, "failed to hash attestation data for aggregated safe-target test\n");
        goto cleanup;
    }

    LanternAggregatedSignatureProof known_proof;
    LanternAggregatedSignatureProof new_proof;
    if (test_make_dummy_proof(&known_proof, 0u, 0x51) != 0) {
        fprintf(stderr, "failed to build known aggregated proof for safe-target test\n");
        goto cleanup;
    }
    if (test_make_dummy_proof(&new_proof, 1u, 0x61) != 0) {
        fprintf(stderr, "failed to build new aggregated proof for safe-target test\n");
        lantern_aggregated_signature_proof_reset(&known_proof);
        goto cleanup;
    }

    if (lantern_client_add_known_aggregated_payload(&client, &data_root, &data, &known_proof, data.target.slot) != 0) {
        fprintf(stderr, "failed to add known aggregated payload for safe-target test\n");
        lantern_aggregated_signature_proof_reset(&new_proof);
        lantern_aggregated_signature_proof_reset(&known_proof);
        goto cleanup;
    }
    if (lantern_client_add_new_aggregated_payload(&client, &data_root, &data, &new_proof, data.target.slot) != 0) {
        fprintf(stderr, "failed to add new aggregated payload for safe-target test\n");
        lantern_aggregated_signature_proof_reset(&new_proof);
        lantern_aggregated_signature_proof_reset(&known_proof);
        goto cleanup;
    }
    lantern_aggregated_signature_proof_reset(&new_proof);
    lantern_aggregated_signature_proof_reset(&known_proof);

    if (lantern_fork_choice_update_safe_target(&client.fork_choice) != 0) {
        fprintf(stderr, "failed to update safe target from attached aggregated payloads\n");
        goto cleanup;
    }
    if (!client.fork_choice.has_safe_target) {
        fprintf(stderr, "safe target missing after aggregated payload update\n");
        goto cleanup;
    }
    if (memcmp(client.fork_choice.safe_target.bytes, anchor_root.bytes, LANTERN_ROOT_SIZE) != 0) {
        fprintf(stderr, "safe target counted known attached aggregated payload support\n");
        goto cleanup;
    }

    LanternAggregatedSignatureProof second_new_proof;
    if (test_make_dummy_proof(&second_new_proof, 2u, 0x71) != 0) {
        fprintf(stderr, "failed to build second new aggregated proof for safe-target test\n");
        goto cleanup;
    }
    if (lantern_client_add_new_aggregated_payload(
            &client,
            &data_root,
            &data,
            &second_new_proof,
            data.target.slot)
        != 0) {
        fprintf(stderr, "failed to add second new aggregated payload for safe-target test\n");
        lantern_aggregated_signature_proof_reset(&second_new_proof);
        goto cleanup;
    }
    lantern_aggregated_signature_proof_reset(&second_new_proof);

    if (lantern_fork_choice_update_safe_target(&client.fork_choice) != 0) {
        fprintf(stderr, "failed to update safe target from new attached aggregated payloads\n");
        goto cleanup;
    }
    if (memcmp(client.fork_choice.safe_target.bytes, child_root.bytes, LANTERN_ROOT_SIZE) != 0) {
        fprintf(stderr, "safe target did not count new attached aggregated payload support\n");
        goto cleanup;
    }

    rc = 0;

cleanup:
    test_reset_agg_cache(&client);
    client_test_teardown_vote_validation_client(&client, pub, secret);
    return rc;
}

static int test_new_aggregated_payloads_promote_to_known(void) {
    struct lantern_client client;
    memset(&client, 0, sizeof(client));
    lantern_store_init(&client.store);

    LanternRoot data_root;
    client_test_fill_root_with_index(&data_root, 0x303u);

    LanternAggregatedSignatureProof proof;
    if (test_make_dummy_proof(&proof, 0, 0x33) != 0) {
        return 1;
    }

    LanternAttestationData data = test_make_attestation_data(6u, 0x44u);
    int rc = 1;
    if (lantern_client_add_new_aggregated_payload(
            &client,
            &data_root,
            &data,
            &proof,
            data.target.slot)
        != 0) {
        fprintf(stderr, "failed to add pending aggregated payload\n");
        goto cleanup;
    }
    if (client.store.new_aggregated_payloads.length != 1
        || client.store.known_aggregated_payloads.length != 0) {
        fprintf(stderr, "unexpected payload pool lengths before promotion\n");
        goto cleanup;
    }

    size_t moved = lantern_client_promote_new_aggregated_payloads(&client);
    if (moved != 1) {
        fprintf(stderr, "expected one payload to migrate to known pool, got=%zu\n", moved);
        goto cleanup;
    }
    if (client.store.new_aggregated_payloads.length != 0
        || client.store.known_aggregated_payloads.length != 1) {
        fprintf(stderr, "unexpected payload pool lengths after promotion\n");
        goto cleanup;
    }
    if (memcmp(
            client.store.known_aggregated_payloads.entries[0].data_root.bytes,
            data_root.bytes,
            LANTERN_ROOT_SIZE)
        != 0) {
        fprintf(stderr, "known payload root mismatch after promotion\n");
        goto cleanup;
    }
    if (client.store.known_aggregated_payloads.entries[0].target_slot != data.target.slot) {
        fprintf(stderr, "known payload target slot mismatch after promotion\n");
        goto cleanup;
    }

    rc = 0;

cleanup:
    lantern_aggregated_signature_proof_reset(&proof);
    test_reset_agg_cache(&client);
    return rc;
}

static int test_debug_aggregate_attestation_signatures_rebuilds_new_payloads(void) {
    struct lantern_client client;
    struct PQSignatureSchemePublicKey *pub = NULL;
    struct PQSignatureSchemeSecretKey *secret = NULL;
    LanternRoot anchor_root;
    LanternRoot child_root;
    struct lantern_validator_config_entry assigned;
    LanternSignedVote vote;
    LanternRoot stale_root;
    LanternRoot fresh_root;
    LanternAggregatedSignatureProof stale_proof;
    LanternAggregatedAttestations aggregated_attestations;
    LanternAttestationSignatures aggregated_signatures;
    int rc = 1;

    memset(&assigned, 0, sizeof(assigned));
    memset(&vote, 0, sizeof(vote));
    memset(&stale_root, 0, sizeof(stale_root));
    memset(&fresh_root, 0, sizeof(fresh_root));
    lantern_aggregated_signature_proof_init(&stale_proof);
    lantern_aggregated_attestations_init(&aggregated_attestations);
    lantern_attestation_signatures_init(&aggregated_signatures);

    if (client_test_setup_vote_validation_client(
            &client,
            "aggregate_recursive_rebuild",
            &pub,
            &secret,
            &anchor_root,
            &child_root)
        != 0) {
        return 1;
    }

    assigned.enr.is_aggregator = true;
    client.assigned_validators = &assigned;
    client.debug_attestation_committee_count = 1u;
    client.gossip.attestation_subnet_id = 0u;

    LanternAttestationData stale_data = test_make_attestation_data(9u, 0x77u);
    client_test_fill_root_with_index(&stale_root, 0x909u);
    if (test_make_dummy_proof(&stale_proof, 1u, 0x66u) != 0) {
        fprintf(stderr, "failed to build stale proof for recursive aggregation test\n");
        goto cleanup;
    }
    if (lantern_client_add_new_aggregated_payload(
            &client,
            &stale_root,
            &stale_data,
            &stale_proof,
            stale_data.target.slot)
        != 0) {
        fprintf(stderr, "failed to seed stale new payload for recursive aggregation test\n");
        goto cleanup;
    }

    if (make_signed_vote_for_validator(&client, secret, 0u, &anchor_root, &child_root, &vote) != 0) {
        fprintf(stderr, "failed to build signed vote for recursive aggregation test\n");
        goto cleanup;
    }
    if (lantern_client_debug_record_vote(&client, &vote, "aggregate_recursive") != 0) {
        fprintf(stderr, "failed to record vote for recursive aggregation test\n");
        goto cleanup;
    }
    if (client.store.attestation_signatures.length != 1u) {
        fprintf(stderr, "expected one cached attestation signature before recursive aggregation\n");
        goto cleanup;
    }

    if (lantern_hash_tree_root_attestation_data(&vote.data.data, &fresh_root) != 0) {
        fprintf(stderr, "failed to hash fresh attestation data for recursive aggregation test\n");
        goto cleanup;
    }

    lantern_client_error agg_rc = lantern_client_debug_aggregate_attestation_signatures(
        &client,
        &aggregated_attestations,
        &aggregated_signatures);
    if (agg_rc != LANTERN_CLIENT_OK) {
        fprintf(stderr, "aggregation failed rc=%d\n", (int)agg_rc);
        goto cleanup;
    }
    if (aggregated_attestations.length != 1u || aggregated_signatures.length != 1u) {
        fprintf(stderr, "expected one fresh aggregate from aggregation\n");
        goto cleanup;
    }
    if (client.store.new_aggregated_payloads.length != 1u) {
        fprintf(stderr, "aggregation should rebuild the new payload pool from fresh results only\n");
        goto cleanup;
    }
    if (!aggregated_pool_contains_root(&client.store.new_aggregated_payloads, &fresh_root)
        || aggregated_pool_contains_root(&client.store.new_aggregated_payloads, &stale_root)) {
        fprintf(stderr, "aggregation did not rebuild the new payload pool correctly\n");
        goto cleanup;
    }
    if (client.store.attestation_signatures.length != 0u) {
        fprintf(stderr, "aggregation should prune raw attestation signatures for aggregated data\n");
        goto cleanup;
    }

    rc = 0;

cleanup:
    lantern_attestation_signatures_reset(&aggregated_signatures);
    lantern_aggregated_attestations_reset(&aggregated_attestations);
    lantern_aggregated_signature_proof_reset(&stale_proof);
    test_reset_agg_cache(&client);
    client_test_teardown_vote_validation_client(&client, pub, secret);
    return rc;
}

static int test_attestation_material_prunes_finalized_entries(void) {
    struct lantern_client client;
    memset(&client, 0, sizeof(client));
    lantern_store_init(&client.store);

    LanternRoot stale_new_root;
    LanternRoot stale_known_root;
    LanternRoot fresh_new_root;
    LanternRoot fresh_known_root;
    client_test_fill_root_with_index(&stale_new_root, 0x101u);
    client_test_fill_root_with_index(&stale_known_root, 0x202u);
    client_test_fill_root_with_index(&fresh_new_root, 0x303u);
    client_test_fill_root_with_index(&fresh_known_root, 0x404u);

    LanternAggregatedSignatureProof stale_new_proof;
    LanternAggregatedSignatureProof stale_known_proof;
    LanternAggregatedSignatureProof fresh_new_proof;
    LanternAggregatedSignatureProof fresh_known_proof;
    if (test_make_dummy_proof(&stale_new_proof, 0, 0x11) != 0) {
        return 1;
    }
    if (test_make_dummy_proof(&stale_known_proof, 1, 0x22) != 0
        || test_make_dummy_proof(&fresh_new_proof, 2, 0x77) != 0
        || test_make_dummy_proof(&fresh_known_proof, 3, 0x88) != 0) {
        lantern_aggregated_signature_proof_reset(&stale_new_proof);
        lantern_aggregated_signature_proof_reset(&stale_known_proof);
        lantern_aggregated_signature_proof_reset(&fresh_new_proof);
        return 1;
    }

    LanternAttestationData stale_new_data = test_make_attestation_data(3u, 0x10u);
    LanternAttestationData stale_known_data = test_make_attestation_data(4u, 0x20u);
    LanternAttestationData fresh_new_data = test_make_attestation_data(8u, 0x30u);
    LanternAttestationData fresh_known_data = test_make_attestation_data(9u, 0x40u);
    LanternSignature stale_signature;
    LanternSignature fresh_signature;
    memset(&stale_signature, 0x55, sizeof(stale_signature));
    memset(&fresh_signature, 0x66, sizeof(fresh_signature));

    int rc = 1;
    if (lantern_client_add_new_aggregated_payload(
            &client,
            &stale_new_root,
            &stale_new_data,
            &stale_new_proof,
            stale_new_data.target.slot)
        != 0) {
        fprintf(stderr, "failed to add stale pending payload\n");
        goto cleanup;
    }
    if (lantern_client_add_known_aggregated_payload(
            &client,
            &stale_known_root,
            &stale_known_data,
            &stale_known_proof,
            stale_known_data.target.slot)
        != 0) {
        fprintf(stderr, "failed to add stale known payload\n");
        goto cleanup;
    }
    if (lantern_client_add_new_aggregated_payload(
            &client,
            &fresh_new_root,
            &fresh_new_data,
            &fresh_new_proof,
            fresh_new_data.target.slot)
        != 0) {
        fprintf(stderr, "failed to add fresh pending payload\n");
        goto cleanup;
    }
    if (lantern_client_add_known_aggregated_payload(
            &client,
            &fresh_known_root,
            &fresh_known_data,
            &fresh_known_proof,
            fresh_known_data.target.slot)
        != 0) {
        fprintf(stderr, "failed to add fresh known payload\n");
        goto cleanup;
    }

    LanternSignatureKey stale_key = {
        .validator_index = 0u,
        .data_root = stale_new_root,
    };
    LanternSignatureKey fresh_key = {
        .validator_index = 1u,
        .data_root = fresh_known_root,
    };
    if (lantern_client_set_attestation_signature(
            &client,
            &stale_key,
            &stale_new_data,
            &stale_signature,
            stale_new_data.target.slot)
        != 0
        || lantern_client_set_attestation_signature(
               &client,
               &fresh_key,
               &fresh_known_data,
               &fresh_signature,
               fresh_known_data.target.slot)
            != 0) {
        fprintf(stderr, "failed to seed gossip signature cache\n");
        goto cleanup;
    }

    if (client.store.new_aggregated_payloads.length != 2
        || client.store.known_aggregated_payloads.length != 2
        || client.store.attestation_signatures.length != 2) {
        fprintf(stderr, "unexpected attestation material lengths before prune\n");
        goto cleanup;
    }

    size_t removed = lantern_client_prune_finalized_attestation_material(&client, 5);
    if (removed != 2) {
        fprintf(stderr, "expected two stale payloads to be pruned, got=%zu\n", removed);
        goto cleanup;
    }
    if (client.store.new_aggregated_payloads.length != 1
        || client.store.known_aggregated_payloads.length != 1
        || client.store.attestation_signatures.length != 1) {
        fprintf(stderr, "unexpected attestation material lengths after prune\n");
        goto cleanup;
    }
    if (memcmp(
            client.store.new_aggregated_payloads.entries[0].data_root.bytes,
            fresh_new_root.bytes,
            LANTERN_ROOT_SIZE)
        != 0) {
        fprintf(stderr, "fresh pending payload root mismatch after prune\n");
        goto cleanup;
    }
    if (memcmp(
            client.store.known_aggregated_payloads.entries[0].data_root.bytes,
            fresh_known_root.bytes,
            LANTERN_ROOT_SIZE)
        != 0) {
        fprintf(stderr, "fresh known payload root mismatch after prune\n");
        goto cleanup;
    }
    if (client.store.new_aggregated_payloads.entries[0].target_slot != 8
        || client.store.known_aggregated_payloads.entries[0].target_slot != 9) {
        fprintf(stderr, "fresh payload target slot mismatch after prune\n");
        goto cleanup;
    }
    if (client.store.attestation_signatures.entries[0].key.validator_index != fresh_key.validator_index
        || memcmp(
               client.store.attestation_signatures.entries[0].key.data_root.bytes,
               fresh_key.data_root.bytes,
               LANTERN_ROOT_SIZE)
            != 0) {
        fprintf(stderr, "fresh gossip signature key mismatch after prune\n");
        goto cleanup;
    }
    LanternAttestationData pruned_data;
    if (lantern_store_get_attestation_data(&client.store, &stale_new_root, &pruned_data) == 0) {
        fprintf(stderr, "stale attestation data should have been pruned\n");
        goto cleanup;
    }
    if (lantern_store_get_attestation_data(&client.store, &fresh_known_root, &pruned_data) != 0) {
        fprintf(stderr, "fresh attestation data missing after prune\n");
        goto cleanup;
    }

    rc = 0;

cleanup:
    lantern_aggregated_signature_proof_reset(&stale_new_proof);
    lantern_aggregated_signature_proof_reset(&stale_known_proof);
    lantern_aggregated_signature_proof_reset(&fresh_new_proof);
    lantern_aggregated_signature_proof_reset(&fresh_known_proof);
    test_reset_agg_cache(&client);
    return rc;
}

static int test_attestation_material_prune_tracks_stale_data_roots(void) {
    struct lantern_client client;
    memset(&client, 0, sizeof(client));
    lantern_store_init(&client.store);

    LanternRoot stale_root;
    LanternRoot orphan_root;
    client_test_fill_root_with_index(&stale_root, 0x505u);
    client_test_fill_root_with_index(&orphan_root, 0x606u);

    LanternAggregatedSignatureProof stale_proof;
    LanternAggregatedSignatureProof orphan_proof;
    if (test_make_dummy_proof(&stale_proof, 0u, 0x31) != 0) {
        return 1;
    }
    if (test_make_dummy_proof(&orphan_proof, 1u, 0x41) != 0) {
        lantern_aggregated_signature_proof_reset(&stale_proof);
        return 1;
    }

    LanternAttestationData stale_data = test_make_attestation_data(3u, 0x51u);
    LanternSignature stale_signature;
    LanternSignature orphan_signature;
    memset(&stale_signature, 0x71, sizeof(stale_signature));
    memset(&orphan_signature, 0x81, sizeof(orphan_signature));

    LanternSignatureKey stale_key = {
        .validator_index = 0u,
        .data_root = stale_root,
    };
    LanternSignatureKey orphan_key = {
        .validator_index = 1u,
        .data_root = orphan_root,
    };

    int rc = 1;
    if (lantern_client_add_new_aggregated_payload(
            &client,
            &stale_root,
            &stale_data,
            &stale_proof,
            stale_data.target.slot)
        != 0) {
        fprintf(stderr, "failed to add stale payload for root-tracking prune test\n");
        goto cleanup;
    }
    if (lantern_client_add_known_aggregated_payload(
            &client,
            &orphan_root,
            NULL,
            &orphan_proof,
            2u)
        != 0) {
        fprintf(stderr, "failed to add orphan payload for root-tracking prune test\n");
        goto cleanup;
    }
    if (lantern_client_set_attestation_signature(
            &client,
            &stale_key,
            &stale_data,
            &stale_signature,
            stale_data.target.slot)
        != 0
        || lantern_client_set_attestation_signature(
               &client,
               &orphan_key,
               NULL,
               &orphan_signature,
               2u)
            != 0) {
        fprintf(stderr, "failed to seed gossip signatures for root-tracking prune test\n");
        goto cleanup;
    }

    if (client.store.attestation_data_by_root.length != 1
        || client.store.new_aggregated_payloads.length != 1
        || client.store.known_aggregated_payloads.length != 1
        || client.store.attestation_signatures.length != 2) {
        fprintf(stderr, "unexpected cache lengths before root-tracking prune test\n");
        goto cleanup;
    }

    size_t removed = lantern_client_prune_finalized_attestation_material(&client, 5u);
    if (removed != 1u) {
        fprintf(stderr, "expected one stale data root to be pruned, got=%zu\n", removed);
        goto cleanup;
    }
    if (client.store.attestation_data_by_root.length != 0
        || client.store.new_aggregated_payloads.length != 0
        || client.store.known_aggregated_payloads.length != 1
        || client.store.attestation_signatures.length != 1) {
        fprintf(stderr, "unexpected cache lengths after root-tracking prune test\n");
        goto cleanup;
    }
    if (memcmp(
            client.store.known_aggregated_payloads.entries[0].data_root.bytes,
            orphan_root.bytes,
            LANTERN_ROOT_SIZE)
        != 0) {
        fprintf(stderr, "orphan payload root mismatch after root-tracking prune test\n");
        goto cleanup;
    }

    LanternSignature cached_signature;
    memset(&cached_signature, 0, sizeof(cached_signature));
    if (lantern_store_get_attestation_signature(&client.store, &orphan_key, &cached_signature) != 0) {
        fprintf(stderr, "orphan gossip signature should remain after root-tracking prune test\n");
        goto cleanup;
    }
    if (memcmp(&cached_signature, &orphan_signature, sizeof(cached_signature)) != 0) {
        fprintf(stderr, "orphan gossip signature mismatch after root-tracking prune test\n");
        goto cleanup;
    }
    if (lantern_store_get_attestation_signature(&client.store, &stale_key, &cached_signature) == 0) {
        fprintf(stderr, "stale gossip signature should have been pruned by root-tracking test\n");
        goto cleanup;
    }

    LanternAttestationData cached_data;
    if (lantern_store_get_attestation_data(&client.store, &stale_root, &cached_data) == 0) {
        fprintf(stderr, "stale attestation data should have been pruned in root-tracking test\n");
        goto cleanup;
    }
    if (lantern_store_get_attestation_data(&client.store, &orphan_root, &cached_data) == 0) {
        fprintf(stderr, "orphan payload should not synthesize attestation data in root-tracking test\n");
        goto cleanup;
    }

    rc = 0;

cleanup:
    lantern_aggregated_signature_proof_reset(&stale_proof);
    lantern_aggregated_signature_proof_reset(&orphan_proof);
    test_reset_agg_cache(&client);
    return rc;
}

static int test_validator_build_reuses_cached_group_proof(void) {
    struct lantern_client client;
    struct PQSignatureSchemePublicKey *pub = NULL;
    struct PQSignatureSchemeSecretKey *secret = NULL;
    LanternRoot anchor_root;
    LanternRoot child_root;
    LanternAggregatedSignatureProof cached_proof;
    LanternAttestations att_list;
    LanternSignatureList att_signatures;
    LanternAggregatedAttestations out_attestations;
    LanternAttestationSignatures out_signatures;
    int rc = 1;

    lantern_aggregated_signature_proof_init(&cached_proof);
    lantern_attestations_init(&att_list);
    lantern_signature_list_init(&att_signatures);
    lantern_aggregated_attestations_init(&out_attestations);
    lantern_attestation_signatures_init(&out_signatures);

    if (client_test_setup_vote_validation_client(
            &client,
            "vote_cached_group",
            &pub,
            &secret,
            &anchor_root,
            &child_root)
        != 0) {
        return 1;
    }

    uint64_t child_slot = 0;
    if (client_test_slot_for_root(&client, &child_root, &child_slot) != 0) {
        fprintf(stderr, "failed to resolve child slot for cached proof reuse test\n");
        goto cleanup;
    }

    LanternSignedVote valid_vote;
    memset(&valid_vote, 0, sizeof(valid_vote));
    valid_vote.data.validator_id = 0u;
    valid_vote.data.slot = child_slot;
    valid_vote.data.head.slot = child_slot;
    valid_vote.data.head.root = child_root;
    valid_vote.data.target.slot = child_slot;
    valid_vote.data.target.root = child_root;
    valid_vote.data.source.slot = 0u;
    valid_vote.data.source.root = anchor_root;
    if (client_test_sign_vote_with_secret(&valid_vote, secret) != 0) {
        fprintf(stderr, "failed to sign valid vote for cached proof reuse test\n");
        goto cleanup;
    }

    LanternRoot data_root;
    if (lantern_hash_tree_root_attestation_data(&valid_vote.data.data, &data_root) != 0) {
        fprintf(stderr, "failed to hash vote data for cached proof reuse test\n");
        goto cleanup;
    }
    const uint8_t *validator_pubkey = lantern_state_validator_attestation_pubkey(&client.state, 0u);
    if (!validator_pubkey) {
        fprintf(stderr, "missing validator pubkey for cached proof reuse test\n");
        goto cleanup;
    }

    const uint8_t *pubkeys[1] = {validator_pubkey};
    LanternSignature signatures[1] = {valid_vote.signature};
    LanternByteList aggregated_proof_bytes;
    lantern_byte_list_init(&aggregated_proof_bytes);
    if (!lantern_signature_aggregate(
            pubkeys,
            signatures,
            1u,
            &data_root,
            valid_vote.data.slot,
            &aggregated_proof_bytes)) {
        lantern_byte_list_reset(&aggregated_proof_bytes);
        fprintf(stderr, "failed to aggregate valid signature for cache seed\n");
        goto cleanup;
    }
    if (lantern_bitlist_resize(&cached_proof.participants, 1u) != 0
        || lantern_bitlist_set(&cached_proof.participants, 0u, true) != 0
        || lantern_byte_list_copy(&cached_proof.proof_data, &aggregated_proof_bytes) != 0) {
        lantern_byte_list_reset(&aggregated_proof_bytes);
        fprintf(stderr, "failed to build cached proof container\n");
        goto cleanup;
    }
    lantern_byte_list_reset(&aggregated_proof_bytes);

    if (lantern_client_add_known_aggregated_payload(
            &client,
            &data_root,
            &valid_vote.data.data,
            &cached_proof,
            valid_vote.data.target.slot)
        != 0) {
        fprintf(stderr, "failed to seed proof cache\n");
        goto cleanup;
    }

    LanternSignature corrupted_signature = valid_vote.signature;
    memset(corrupted_signature.bytes, 0, sizeof(corrupted_signature.bytes));
    corrupted_signature.bytes[0] = 0xFFu;
    corrupted_signature.bytes[1] = 0xFFu;
    corrupted_signature.bytes[2] = 0xFFu;
    corrupted_signature.bytes[3] = 0xFFu;

    if (lantern_attestations_append(&att_list, &valid_vote.data) != 0
        || lantern_signature_list_append(&att_signatures, &corrupted_signature) != 0) {
        fprintf(stderr, "failed to prepare attestation input for cache reuse test\n");
        goto cleanup;
    }

    lantern_client_error agg_rc = lantern_client_aggregate_attestations_for_block(
        &client,
        &att_list,
        &att_signatures,
        &out_attestations,
        &out_signatures);
    if (agg_rc != LANTERN_CLIENT_OK) {
        fprintf(stderr, "aggregation failed; expected cached proof reuse path rc=%d\n", (int)agg_rc);
        goto cleanup;
    }
    if (out_attestations.length == 0
        || !out_attestations.data
        || out_signatures.length == 0
        || !out_signatures.data) {
        fprintf(stderr, "expected aggregated attestation signature in aggregation output\n");
        goto cleanup;
    }
    if (!proof_payload_equals(&out_signatures.data[0], &cached_proof)) {
        fprintf(stderr, "aggregation did not reuse cached aggregated proof payload\n");
        goto cleanup;
    }

    rc = 0;

cleanup:
    lantern_attestation_signatures_reset(&out_signatures);
    lantern_aggregated_attestations_reset(&out_attestations);
    lantern_signature_list_reset(&att_signatures);
    lantern_attestations_reset(&att_list);
    lantern_aggregated_signature_proof_reset(&cached_proof);
    test_reset_agg_cache(&client);
    client_test_teardown_vote_validation_client(&client, pub, secret);
    return rc;
}

static int test_validator_build_skips_raw_signatures_without_cached_proof(void) {
    struct lantern_client client;
    struct PQSignatureSchemePublicKey *pub = NULL;
    struct PQSignatureSchemeSecretKey *secret = NULL;
    LanternRoot anchor_root;
    LanternRoot child_root;
    LanternSignedVote vote;
    LanternAttestations att_list;
    LanternSignatureList att_signatures;
    LanternAggregatedAttestations out_attestations;
    LanternAttestationSignatures out_signatures;
    int rc = 1;

    memset(&vote, 0, sizeof(vote));
    lantern_attestations_init(&att_list);
    lantern_signature_list_init(&att_signatures);
    lantern_aggregated_attestations_init(&out_attestations);
    lantern_attestation_signatures_init(&out_signatures);

    if (client_test_setup_vote_validation_client(
            &client,
            "vote_raw_signature_skip",
            &pub,
            &secret,
            &anchor_root,
            &child_root)
        != 0) {
        return 1;
    }

    if (make_signed_vote_for_validator(&client, secret, 0u, &anchor_root, &child_root, &vote) != 0) {
        fprintf(stderr, "failed to build signed vote for raw-signature skip test\n");
        goto cleanup;
    }

    if (lantern_attestations_append(&att_list, &vote.data) != 0
        || lantern_signature_list_append(&att_signatures, &vote.signature) != 0) {
        fprintf(stderr, "failed to prepare attestation input for raw-signature skip test\n");
        goto cleanup;
    }

    lantern_client_error agg_rc = lantern_client_aggregate_attestations_for_block(
        &client,
        &att_list,
        &att_signatures,
        &out_attestations,
        &out_signatures);
    if (agg_rc != LANTERN_CLIENT_OK) {
        fprintf(stderr, "cache-only aggregation failed rc=%d\n", (int)agg_rc);
        goto cleanup;
    }
    if (out_attestations.length != 0 || out_signatures.length != 0) {
        fprintf(stderr, "block aggregation should ignore uncached raw signatures\n");
        goto cleanup;
    }

    rc = 0;

cleanup:
    lantern_attestation_signatures_reset(&out_signatures);
    lantern_aggregated_attestations_reset(&out_attestations);
    lantern_signature_list_reset(&att_signatures);
    lantern_attestations_reset(&att_list);
    test_reset_agg_cache(&client);
    client_test_teardown_vote_validation_client(&client, pub, secret);
    return rc;
}

static int test_block_build_keeps_known_payload_after_newer_raw_vote(void) {
    struct lantern_client client;
    struct PQSignatureSchemePublicKey *pub = NULL;
    struct PQSignatureSchemeSecretKey *secret = NULL;
    LanternRoot anchor_root;
    LanternRoot child_root;
    LanternRoot parent_root;
    LanternRoot proof_root;
    LanternRoot raw_root;
    LanternSignatureKey proof_key;
    LanternSignedVote proof_vote;
    LanternSignedVote raw_vote;
    LanternAggregatedSignatureProof cached_proof;
    LanternAggregatedAttestations collected;
    LanternAttestationSignatures collected_signatures;
    int rc = 1;

    memset(&parent_root, 0, sizeof(parent_root));
    memset(&proof_root, 0, sizeof(proof_root));
    memset(&raw_root, 0, sizeof(raw_root));
    memset(&proof_key, 0, sizeof(proof_key));
    memset(&proof_vote, 0, sizeof(proof_vote));
    memset(&raw_vote, 0, sizeof(raw_vote));
    lantern_aggregated_signature_proof_init(&cached_proof);
    lantern_aggregated_attestations_init(&collected);
    lantern_attestation_signatures_init(&collected_signatures);

    if (client_test_setup_vote_validation_client_with_validator_count(
            &client,
            "vote_shadowed_known_payload",
            2u,
            &pub,
            &secret,
            &anchor_root,
            &child_root)
        != 0) {
        return 1;
    }

    uint64_t block_slot = client.state.slot + 1u;
    uint64_t proposer_index = 0u;
    if (lantern_proposer_for_slot(block_slot, client.state.config.num_validators, &proposer_index) != 0) {
        fprintf(stderr, "failed to resolve proposer for block-build shadow test\n");
        goto cleanup;
    }

    uint64_t validator_id = proposer_index == 0u ? 1u : 0u;
    if (make_signed_vote_for_validator(
            &client,
            secret,
            validator_id,
            &anchor_root,
            &child_root,
            &proof_vote)
        != 0) {
        fprintf(stderr, "failed to build proof-backed vote for block-build shadow test\n");
        goto cleanup;
    }
    if (lantern_hash_tree_root_attestation_data(&proof_vote.data.data, &proof_root) != 0) {
        fprintf(stderr, "failed to hash proof-backed vote for block-build shadow test\n");
        goto cleanup;
    }

    proof_key.validator_index = validator_id;
    proof_key.data_root = proof_root;
    if (lantern_client_set_attestation_signature(
            &client,
            &proof_key,
            &proof_vote.data.data,
            &proof_vote.signature,
            proof_vote.data.target.slot)
        != 0) {
        fprintf(stderr, "failed to seed gossip signature for proof-backed vote\n");
        goto cleanup;
    }
    if (test_make_dummy_proof(&cached_proof, validator_id, 0x5Au) != 0) {
        fprintf(stderr, "failed to build cached proof for block-build shadow test\n");
        goto cleanup;
    }
    if (lantern_client_add_known_aggregated_payload(
            &client,
            &proof_root,
            &proof_vote.data.data,
            &cached_proof,
            proof_vote.data.target.slot)
        != 0) {
        fprintf(stderr, "failed to seed known payload for block-build shadow test\n");
        goto cleanup;
    }
    if (lantern_store_set_signed_validator_vote(&client.store, (size_t)validator_id, &proof_vote) != 0) {
        fprintf(stderr, "failed to seed initial validator vote for block-build shadow test\n");
        goto cleanup;
    }

    raw_vote = proof_vote;
    raw_vote.data.slot = proof_vote.data.slot + 1u;
    raw_vote.data.head.slot = raw_vote.data.slot;
    raw_vote.data.target.slot = raw_vote.data.slot;
    client_test_fill_root(&raw_vote.data.head.root, 0xD1u);
    raw_vote.data.target.root = raw_vote.data.head.root;
    if (client_test_sign_vote_with_secret(&raw_vote, secret) != 0) {
        fprintf(stderr, "failed to sign newer raw vote for block-build shadow test\n");
        goto cleanup;
    }
    if (lantern_hash_tree_root_attestation_data(&raw_vote.data.data, &raw_root) != 0) {
        fprintf(stderr, "failed to hash newer raw vote for block-build shadow test\n");
        goto cleanup;
    }
    if (memcmp(raw_root.bytes, proof_root.bytes, LANTERN_ROOT_SIZE) == 0) {
        fprintf(stderr, "newer raw vote should have a distinct data root in block-build shadow test\n");
        goto cleanup;
    }
    if (lantern_store_set_signed_validator_vote(&client.store, (size_t)validator_id, &raw_vote) != 0) {
        fprintf(stderr, "failed to overwrite validator vote with newer raw vote\n");
        goto cleanup;
    }

    if (lantern_state_select_block_parent(&client.state, &client.store, &parent_root) != 0) {
        fprintf(stderr, "failed to select block parent for block-build shadow test\n");
        goto cleanup;
    }
    if (lantern_state_collect_attestations_for_block(
            &client.state,
            &client.store,
            block_slot,
            proposer_index,
            &parent_root,
            &collected,
            &collected_signatures)
        != 0) {
        fprintf(stderr, "failed to collect attestations for block-build shadow test\n");
        goto cleanup;
    }
    if (collected.length != 1u || collected_signatures.length != 1u) {
        fprintf(
            stderr,
            "expected exactly one collected attestation after raw-vote shadow test, got votes=%zu sigs=%zu\n",
            collected.length,
            collected_signatures.length);
        goto cleanup;
    }
    if (memcmp(&collected.data[0].data, &proof_vote.data.data, sizeof(proof_vote.data.data)) != 0) {
        fprintf(stderr, "block collection did not keep the proof-backed attestation\n");
        goto cleanup;
    }
    if (!proof_payload_equals(&collected_signatures.data[0], &cached_proof)) {
        fprintf(stderr, "block collection did not reuse the known cached proof\n");
        goto cleanup;
    }
    if (!lantern_bitlist_get(&collected.data[0].aggregation_bits, (size_t)validator_id)) {
        fprintf(stderr, "block collection did not preserve cached proof participants\n");
        goto cleanup;
    }

    rc = 0;

cleanup:
    lantern_attestation_signatures_reset(&collected_signatures);
    lantern_aggregated_attestations_reset(&collected);
    lantern_aggregated_signature_proof_reset(&cached_proof);
    test_reset_agg_cache(&client);
    client_test_teardown_vote_validation_client(&client, pub, secret);
    return rc;
}

static int test_publish_aggregated_attestations_collects_any_slot_and_prunes_gossip(void) {
    struct lantern_client client;
    struct PQSignatureSchemePublicKey *pub = NULL;
    struct PQSignatureSchemeSecretKey *secret = NULL;
    LanternRoot anchor_root;
    LanternRoot child_root;
    struct lantern_validator_config_entry assigned;
    struct publish_capture capture;
    LanternSignedVote vote0;
    LanternSignedVote vote1;
    LanternSignedVote vote4;
    LanternRoot data_root;
    LanternSignatureKey vote0_key;
    LanternSignatureKey vote1_key;
    LanternSignatureKey vote4_key;
    LanternSignature cached_signature;
    LanternSignedAggregatedAttestation decoded;
    int rc = 1;

    memset(&capture, 0, sizeof(capture));
    memset(&assigned, 0, sizeof(assigned));
    memset(&data_root, 0, sizeof(data_root));
    memset(&vote0_key, 0, sizeof(vote0_key));
    memset(&vote1_key, 0, sizeof(vote1_key));
    memset(&vote4_key, 0, sizeof(vote4_key));
    memset(&cached_signature, 0, sizeof(cached_signature));
    lantern_signed_aggregated_attestation_init(&decoded);

    if (client_test_setup_vote_validation_client_with_validator_count(
            &client,
            "vote_subnet_filter",
            8u,
            &pub,
            &secret,
            &anchor_root,
            &child_root)
        != 0) {
        goto cleanup;
    }

    assigned.enr.is_aggregator = true;
    client.assigned_validators = &assigned;
    client.debug_attestation_committee_count = 4u;
    client.gossip.attestation_subnet_id = 0u;
    snprintf(
        client.gossip.aggregated_attestation_topic,
        sizeof(client.gossip.aggregated_attestation_topic),
        "test/aggregated_attestation");
    lantern_gossipsub_service_set_publish_hook(&client.gossip, publish_capture_hook, &capture);
    lantern_gossipsub_service_set_loopback_only(&client.gossip, 1);

    if (make_signed_vote_for_validator(&client, secret, 0u, &anchor_root, &child_root, &vote0) != 0
        || make_signed_vote_for_validator(&client, secret, 1u, &anchor_root, &child_root, &vote1) != 0
        || make_signed_vote_for_validator(&client, secret, 4u, &anchor_root, &child_root, &vote4) != 0) {
        fprintf(stderr, "failed to build signed votes for subnet filter test\n");
        goto cleanup;
    }

    if (lantern_client_debug_record_vote(&client, &vote0, "subnet_vote_0") != 0
        || lantern_client_debug_record_vote(&client, &vote1, "subnet_vote_1") != 0
        || lantern_client_debug_record_vote(&client, &vote4, "subnet_vote_4") != 0) {
        fprintf(stderr, "failed to record votes for subnet filter test\n");
        goto cleanup;
    }
    if (client.store.attestation_signatures.length != 3u) {
        fprintf(stderr, "expected all gossip signatures to be cached before subnet filtering\n");
        goto cleanup;
    }
    if (lantern_hash_tree_root_attestation_data(&vote0.data.data, &data_root) != 0) {
        fprintf(stderr, "failed to hash attestation data for prune test\n");
        goto cleanup;
    }
    vote0_key.validator_index = vote0.data.validator_id;
    vote0_key.data_root = data_root;
    vote1_key.validator_index = vote1.data.validator_id;
    vote1_key.data_root = data_root;
    vote4_key.validator_index = vote4.data.validator_id;
    vote4_key.data_root = data_root;

    if (lantern_client_debug_publish_aggregated_attestations(&client, vote0.data.slot + 1u) != LANTERN_CLIENT_OK) {
        fprintf(stderr, "aggregated attestation publish should succeed for any-slot gossip vote\n");
        goto cleanup;
    }
    if (capture.calls != 1u || capture.payload_len == 0 || !capture.payload) {
        fprintf(stderr, "expected one aggregated attestation publish in any-slot test\n");
        goto cleanup;
    }

    if (lantern_gossip_decode_signed_aggregated_attestation_snappy(&decoded, capture.payload, capture.payload_len) != 0) {
        fprintf(stderr, "failed to decode published aggregated attestation payload\n");
        goto cleanup;
    }
    if (!lantern_bitlist_get(&decoded.proof.participants, 0u)
        || !lantern_bitlist_get(&decoded.proof.participants, 4u)
        || lantern_bitlist_get(&decoded.proof.participants, 1u)) {
        fprintf(stderr, "published aggregated proof participants should still match the local subnet\n");
        goto cleanup;
    }
    if (client.store.attestation_signatures.length != 0u) {
        fprintf(stderr, "expected aggregated gossip signatures to be fully pruned after publish\n");
        goto cleanup;
    }
    if (lantern_store_get_attestation_signature(&client.store, &vote0_key, &cached_signature) == 0
        || lantern_store_get_attestation_signature(&client.store, &vote4_key, &cached_signature) == 0) {
        fprintf(stderr, "aggregated subnet votes should have been removed from gossip cache\n");
        goto cleanup;
    }
    if (lantern_store_get_attestation_signature(&client.store, &vote1_key, &cached_signature) == 0) {
        fprintf(stderr, "cross-subnet gossip vote should never enter the gossip signature cache\n");
        goto cleanup;
    }

    LanternAttestationData cached_vote1_data;
    memset(&cached_vote1_data, 0, sizeof(cached_vote1_data));
    if (lantern_store_get_attestation_data(&client.store, &data_root, &cached_vote1_data) != 0) {
        fprintf(stderr, "cross-subnet gossip vote should still retain attestation data\n");
        goto cleanup;
    }
    if (memcmp(&cached_vote1_data, &vote1.data.data, sizeof(cached_vote1_data)) != 0) {
        fprintf(stderr, "cross-subnet attestation data mismatch after publish\n");
        goto cleanup;
    }

    rc = 0;

cleanup:
    lantern_signed_aggregated_attestation_reset(&decoded);
    publish_capture_reset(&capture);
    test_reset_agg_cache(&client);
    client_test_teardown_vote_validation_client(&client, pub, secret);
    return rc;
}

static int test_publish_attestations_includes_proposer(void) {
    struct lantern_client client;
    struct PQSignatureSchemePublicKey *pub = NULL;
    struct PQSignatureSchemeSecretKey *secret = NULL;
    struct publish_capture capture;
    struct lantern_local_validator validator;
    bool validator_enabled = true;
    LanternSignedVote published_vote;
    int rc = 1;

    memset(&capture, 0, sizeof(capture));
    memset(&validator, 0, sizeof(validator));
    memset(&published_vote, 0, sizeof(published_vote));

    if (client_test_setup_vote_validation_client(
            &client,
            "vote_publish_proposer",
            &pub,
            &secret,
            NULL,
            NULL)
        != 0) {
        goto cleanup;
    }

    validator.global_index = 0u;
    validator.last_attested_slot = UINT64_MAX;
    validator.attestation_secret_key = secret;
    validator.proposal_secret_key = secret;

    client.local_validators = &validator;
    client.local_validator_count = 1u;
    client.validator_enabled = &validator_enabled;
    client.has_runtime = true;
    client.gossip_running = true;
    client.gossip.attestation_subnet_id = 0u;
    snprintf(client.gossip.vote_topic, sizeof(client.gossip.vote_topic), "test/proposer_vote");
    snprintf(
        client.gossip.vote_subnet_topic,
        sizeof(client.gossip.vote_subnet_topic),
        "test/proposer_vote_subnet");
    lantern_gossipsub_service_set_publish_hook(&client.gossip, publish_capture_hook, &capture);
    lantern_gossipsub_service_set_loopback_only(&client.gossip, 1);

    uint64_t slot = client.state.slot + 1u;
    if (lantern_store_validator_has_vote(&client.store, validator.global_index)) {
        fprintf(stderr, "validator vote cache unexpectedly populated before proposer publish test\n");
        goto cleanup;
    }

    if (validator_publish_attestations(&client, slot) != LANTERN_CLIENT_OK) {
        fprintf(stderr, "validator_publish_attestations failed for proposer publish test\n");
        goto cleanup;
    }
    if (capture.calls != 1u || capture.payload_len == 0u || !capture.payload) {
        fprintf(stderr, "expected proposer attestation to publish on the attestation subnet topic\n");
        goto cleanup;
    }
    if (lantern_gossip_decode_signed_vote_snappy(&published_vote, capture.payload, capture.payload_len) != 0) {
        fprintf(stderr, "failed to decode proposer attestation publish payload\n");
        goto cleanup;
    }
    if (published_vote.data.validator_id != validator.global_index || published_vote.data.slot != slot) {
        fprintf(stderr, "published proposer attestation had unexpected validator or slot\n");
        goto cleanup;
    }
    if (!lantern_store_validator_has_vote(&client.store, validator.global_index)) {
        fprintf(stderr, "proposer attestation should be staged into the validator vote cache\n");
        goto cleanup;
    }
    if (validator.last_attested_slot != slot) {
        fprintf(stderr, "proposer attestation path did not mark slot %" PRIu64 " as attested\n", slot);
        goto cleanup;
    }

    rc = 0;

cleanup:
    publish_capture_reset(&capture);
    test_reset_agg_cache(&client);
    client_test_teardown_vote_validation_client(&client, pub, secret);
    return rc;
}

static int test_local_block_commit_updates_state_before_publish(void) {
    struct lantern_client client;
    struct PQSignatureSchemePublicKey *pub = NULL;
    struct PQSignatureSchemeSecretKey *secret = NULL;
    struct lantern_local_validator validator;
    bool validator_enabled = true;
    struct local_block_publish_observer observer;
    LanternSignedBlock block;
    LanternState post_state;
    LanternStore post_store;
    LanternRoot block_root;
    int rc = 1;

    memset(&validator, 0, sizeof(validator));
    memset(&observer, 0, sizeof(observer));
    memset(&block_root, 0, sizeof(block_root));
    lantern_signed_block_init(&block);
    lantern_state_init(&post_state);
    lantern_store_init(&post_store);

    if (client_test_setup_vote_validation_client(
            &client,
            "local_block_publish_fast_path",
            &pub,
            &secret,
            NULL,
            NULL)
        != 0) {
        goto cleanup;
    }

    validator.global_index = 0u;
    validator.attestation_secret_key = secret;
    validator.proposal_secret_key = secret;
    client.local_validators = &validator;
    client.local_validator_count = 1u;
    client.validator_enabled = &validator_enabled;
    client.gossip_running = true;
    snprintf(client.gossip.block_topic, sizeof(client.gossip.block_topic), "test/local_block");
    lantern_gossipsub_service_set_publish_hook(
        &client.gossip,
        local_block_publish_observer_hook,
        &observer);
    lantern_gossipsub_service_set_loopback_only(&client.gossip, 1);

    uint64_t slot = client.state.slot + 1u;
    if (validator_build_block(&client, slot, 0u, &block) != LANTERN_CLIENT_OK) {
        fprintf(stderr, "validator_build_block failed for local block publish test\n");
        goto cleanup;
    }
    if (lantern_hash_tree_root_block(&block.block, &block_root) != 0) {
        fprintf(stderr, "failed to hash built block for local block publish test\n");
        goto cleanup;
    }
    if (lantern_state_compute_post_state(
            &client.state,
            &client.store,
            &block,
            &post_state,
            &post_store,
            NULL)
        != 0) {
        fprintf(stderr, "failed to compute post-state for local block publish test\n");
        goto cleanup;
    }

    observer.client = &client;
    observer.expected_slot = slot;
    observer.expected_root = block_root;

    if (lantern_client_commit_and_publish_local_block(
            &client,
            &block,
            &block_root,
            &post_state,
            &post_store)
        != LANTERN_CLIENT_OK) {
        fprintf(stderr, "local block fast-path commit/publish failed\n");
        goto cleanup;
    }
    if (observer.calls != 1u || !observer.saw_state_slot || !observer.saw_head_root) {
        fprintf(stderr, "local block state/head were not committed before publish\n");
        goto cleanup;
    }
    if (client.state.slot != slot) {
        fprintf(stderr, "client state did not advance during local block fast-path publish\n");
        goto cleanup;
    }
    LanternRoot head_root;
    memset(&head_root, 0, sizeof(head_root));
    if (lantern_fork_choice_current_head(&client.fork_choice, &head_root) != 0
        || memcmp(head_root.bytes, block_root.bytes, LANTERN_ROOT_SIZE) != 0) {
        fprintf(stderr, "fork choice head did not advance to the published local block\n");
        goto cleanup;
    }

    rc = 0;

cleanup:
    lantern_store_reset(&post_store);
    lantern_state_reset(&post_state);
    lantern_signed_block_reset(&block);
    client_test_teardown_vote_validation_client(&client, pub, secret);
    return rc;
}

static int test_interval_2_aggregation_trigger_respects_aggregator_role(void) {
    struct lantern_client client;
    struct PQSignatureSchemePublicKey *pub = NULL;
    struct PQSignatureSchemeSecretKey *secret = NULL;
    LanternRoot anchor_root;
    LanternRoot child_root;
    struct lantern_validator_config_entry assigned;
    struct publish_capture capture;
    LanternSignedVote vote0;
    int rc = 1;

    memset(&assigned, 0, sizeof(assigned));
    memset(&capture, 0, sizeof(capture));

    if (client_test_setup_vote_validation_client_with_validator_count(
            &client,
            "vote_interval_aggregation",
            4u,
            &pub,
            &secret,
            &anchor_root,
            &child_root)
        != 0) {
        goto cleanup;
    }

    assigned.enr.is_aggregator = true;
    client.assigned_validators = &assigned;
    client.gossip.attestation_subnet_id = 0u;
    snprintf(
        client.gossip.aggregated_attestation_topic,
        sizeof(client.gossip.aggregated_attestation_topic),
        "test/interval_aggregation");
    lantern_gossipsub_service_set_publish_hook(&client.gossip, publish_capture_hook, &capture);
    lantern_gossipsub_service_set_loopback_only(&client.gossip, 1);

    if (make_signed_vote_for_validator(&client, secret, 0u, &anchor_root, &child_root, &vote0) != 0) {
        fprintf(stderr, "failed to build signed vote for interval aggregation test\n");
        goto cleanup;
    }
    if (lantern_client_debug_record_vote(&client, &vote0, "interval_agg_vote") != 0) {
        fprintf(stderr, "failed to record vote for interval aggregation test\n");
        goto cleanup;
    }

    client.validator_duty.slot_attested = true;
    client.validator_duty.slot_aggregated = false;
    if (lantern_client_debug_run_interval_aggregation(&client, vote0.data.slot) != LANTERN_CLIENT_OK) {
        fprintf(stderr, "interval 2 aggregation should succeed for aggregator\n");
        goto cleanup;
    }
    if (!client.validator_duty.slot_aggregated || capture.calls != 1u) {
        fprintf(stderr, "interval 2 aggregation did not mark duty or publish for aggregator\n");
        goto cleanup;
    }

    client.validator_duty.slot_attested = true;
    client.validator_duty.slot_aggregated = false;
    assigned.enr.is_aggregator = false;
    capture.calls = 0;
    capture.payload_len = 0;
    if (lantern_client_debug_run_interval_aggregation(&client, vote0.data.slot) != LANTERN_CLIENT_ERR_RUNTIME) {
        fprintf(stderr, "non-aggregator should not run interval 2 aggregation\n");
        goto cleanup;
    }
    if (client.validator_duty.slot_aggregated || capture.calls != 0u) {
        fprintf(stderr, "non-aggregator interval 2 path should not publish or mark aggregated\n");
        goto cleanup;
    }

    rc = 0;

cleanup:
    publish_capture_reset(&capture);
    test_reset_agg_cache(&client);
    client_test_teardown_vote_validation_client(&client, pub, secret);
    return rc;
}

int main(void) {
    if (test_record_vote_accepts_known_roots() != 0) {
        return 1;
    }
    if (test_record_vote_buffers_missing_target_state() != 0) {
        return 1;
    }
    if (test_record_vote_buffers_source_root_known_only_via_historical_hashes() != 0) {
        return 1;
    }
    if (test_record_vote_buffers_unknown_head() != 0) {
        return 1;
    }
    if (test_record_vote_replays_buffered_vote_after_block_import() != 0) {
        return 1;
    }
    if (test_record_vote_rejects_slot_mismatch() != 0) {
        return 1;
    }
    if (test_record_vote_rejects_head_older_than_target() != 0) {
        return 1;
    }
    if (test_record_vote_rejects_future_slot() != 0) {
        return 1;
    }
    if (test_validator_refresh_cached_vote_updates_source() != 0) {
        return 1;
    }
    if (test_validator_sign_with_key_advances_only_selected_secret() != 0) {
        return 1;
    }
    if (test_validator_build_block_leaves_attestation_key_untouched() != 0) {
        return 1;
    }
    if (test_local_block_commit_updates_state_before_publish() != 0) {
        return 1;
    }
    if (test_client_load_xmss_keys_reads_annotated_validators() != 0) {
        return 1;
    }
    if (test_client_load_xmss_keys_rejects_incomplete_annotated_validator() != 0) {
        return 1;
    }
    if (test_record_vote_preserves_state_root() != 0) {
        return 1;
    }
    if (test_record_vote_defers_interval_pipeline() != 0) {
        return 1;
    }
    if (test_skip_fork_choice_intervals_replays_interval_side_effects() != 0) {
        return 1;
    }
    if (test_chain_service_tick_to_skips_stale_intervals() != 0) {
        return 1;
    }
    if (test_safe_target_uses_only_new_attached_aggregated_payloads() != 0) {
        return 1;
    }
    if (test_new_aggregated_payloads_promote_to_known() != 0) {
        return 1;
    }
    if (test_debug_aggregate_attestation_signatures_rebuilds_new_payloads() != 0) {
        return 1;
    }
    if (test_attestation_material_prunes_finalized_entries() != 0) {
        return 1;
    }
    if (test_attestation_material_prune_tracks_stale_data_roots() != 0) {
        return 1;
    }
    if (test_validator_build_skips_raw_signatures_without_cached_proof() != 0) {
        return 1;
    }
    if (test_block_build_keeps_known_payload_after_newer_raw_vote() != 0) {
        return 1;
    }
    if (test_validator_build_reuses_cached_group_proof() != 0) {
        return 1;
    }
    if (test_publish_attestations_includes_proposer() != 0) {
        return 1;
    }
    if (test_publish_aggregated_attestations_collects_any_slot_and_prunes_gossip() != 0) {
        return 1;
    }
    if (test_interval_2_aggregation_trigger_respects_aggregator_role() != 0) {
        return 1;
    }
    puts("lantern_client_vote_test OK");
    return 0;
}
