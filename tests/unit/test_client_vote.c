#include <inttypes.h>
#include <stdbool.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "lantern/consensus/duties.h"
#include "client_test_helpers.h"
#include "lantern/consensus/hash.h"
#include "lantern/consensus/signature.h"
#include "lantern/networking/gossip_payloads.h"
#include "lantern/storage/storage.h"
#include "lantern/support/time.h"

/* Internal core APIs used for targeted cache and block-build regression tests. */
int lantern_client_set_gossip_signature(
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
lantern_client_error lantern_client_aggregate_attestations_for_block(
    struct lantern_client *client,
    const LanternAttestations *att_list,
    const LanternSignatureList *att_signatures,
    LanternAggregatedAttestations *out_attestations,
    LanternAttestationSignatures *out_signatures);
int validator_publish_attestations(struct lantern_client *client, uint64_t slot);

static void test_reset_agg_cache(struct lantern_client *client) {
    if (!client) {
        return;
    }
    lantern_store_reset(&client->store);
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
    LanternCheckpoint head = {0};
    LanternCheckpoint target = {0};
    LanternCheckpoint source = {0};
    LanternSignedVote proposer_vote;
    memset(&proposer_vote, 0, sizeof(proposer_vote));

    lantern_signed_block_with_attestation_init(out_block);
    out_block->message.block.slot = client->state.slot + 1u;
    if (lantern_proposer_for_slot(
            out_block->message.block.slot,
            client->state.config.num_validators,
            &out_block->message.block.proposer_index)
        != 0) {
        goto cleanup;
    }
    if (lantern_state_select_block_parent(
            &client->state,
            &client->store,
            &out_block->message.block.parent_root)
        != 0) {
        goto cleanup;
    }
    if (lantern_state_compute_vote_checkpoints(
            &client->state,
            &client->store,
            &head,
            &target,
            &source)
        != 0) {
        goto cleanup;
    }

    proposer_vote.data.validator_id = out_block->message.block.proposer_index;
    proposer_vote.data.slot = out_block->message.block.slot;
    proposer_vote.data.head = head;
    proposer_vote.data.target = target;
    proposer_vote.data.source = source;
    if (client_test_sign_vote_with_secret(&proposer_vote, secret) != 0) {
        goto cleanup;
    }

    out_block->message.proposer_attestation = proposer_vote.data;
    out_block->signatures.proposer_signature = proposer_vote.signature;

    if (lantern_state_preview_post_state_root(
            &client->state,
            &client->store,
            out_block,
            &out_block->message.block.state_root)
        != 0) {
        goto cleanup;
    }
    if (lantern_hash_tree_root_block(&out_block->message.block, out_root) != 0) {
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
    if (lantern_store_get_gossip_signature(&client.store, &key, &cached_signature) == 0) {
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

    rc = 0;

cleanup:
    lantern_block_body_reset(&grandchild.body);
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

    if (client.fork_choice.new_votes && client.fork_choice.validator_count > 0) {
        for (size_t i = 0; i < client.fork_choice.validator_count; ++i) {
            if (client.fork_choice.new_votes[i].has_checkpoint) {
                fprintf(stderr, "unknown head vote updated fork choice new_votes\n");
                goto cleanup;
            }
        }
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
            &grandchild_block.message.block.parent_root,
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
            &grandchild_block.message.block.parent_root,
            &client.state)
        != 0) {
        fprintf(stderr, "failed to persist parent state for buffered vote replay test\n");
        goto cleanup;
    }

    vote.data.validator_id = 0u;
    vote.data.slot = grandchild_block.message.block.slot;
    vote.data.head.slot = grandchild_block.message.block.slot;
    vote.data.head.root = grandchild_root;
    vote.data.target.slot = grandchild_block.message.block.slot;
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

    if (client.fork_choice.new_votes && client.fork_choice.validator_count > 0) {
        for (size_t i = 0; i < client.fork_choice.validator_count; ++i) {
            if (client.fork_choice.new_votes[i].has_checkpoint) {
                fprintf(stderr, "slot mismatch vote updated fork choice cache\n");
                goto cleanup;
            }
        }
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

    if (client.fork_choice.new_votes && client.fork_choice.validator_count > 0) {
        for (size_t i = 0; i < client.fork_choice.validator_count; ++i) {
            if (client.fork_choice.new_votes[i].has_checkpoint) {
                fprintf(stderr, "head older than target vote updated fork choice cache\n");
                goto cleanup;
            }
        }
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
    validator.secret_key = secret;
    validator.has_secret_handle = true;

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
    if (lantern_store_get_gossip_signature(&client.store, &key, &cached_signature) != 0) {
        fprintf(stderr, "gossip signature cache missing vote before aggregation\n");
        goto cleanup;
    }
    if (memcmp(&cached_signature, &vote.signature, sizeof(vote.signature)) != 0) {
        fprintf(stderr, "cached gossip signature mismatch before aggregation\n");
        goto cleanup;
    }

    struct lantern_fork_choice_vote_entry *new_entry = client.fork_choice.new_votes;
    struct lantern_fork_choice_vote_entry *known_entry = client.fork_choice.known_votes;
    if (!new_entry || !known_entry) {
        fprintf(stderr, "fork choice vote tables unavailable for interval pipeline test\n");
        goto cleanup;
    }
    if (new_entry->has_checkpoint) {
        fprintf(stderr, "gossip vote should not bypass aggregation via new_votes\n");
        goto cleanup;
    }
    if (known_entry->has_checkpoint) {
        fprintf(stderr, "known_votes updated before interval pipeline advanced\n");
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
    if (new_entry->has_checkpoint) {
        fprintf(stderr, "new_votes updated before interval 2 aggregation\n");
        goto cleanup;
    }
    if (known_entry->has_checkpoint) {
        fprintf(stderr, "known_votes filled before interval 2\n");
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
    if (new_entry->has_checkpoint) {
        fprintf(stderr, "new_votes updated before local aggregation proof exists\n");
        goto cleanup;
    }
    if (known_entry->has_checkpoint) {
        fprintf(stderr, "known_votes filled before interval 3\n");
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
        fprintf(stderr, "interval 2 aggregation did not stage proof into new payload pool\n");
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
    if (new_entry->has_checkpoint) {
        fprintf(stderr, "new_votes should stay empty until proof acceptance\n");
        goto cleanup;
    }
    if (known_entry->has_checkpoint) {
        fprintf(stderr, "known_votes filled before interval 4\n");
        goto cleanup;
    }

    if (advance_client_fork_choice_intervals(&client, 1, false) != 0) {
        fprintf(stderr, "failed to advance fork choice to interval 4\n");
        goto cleanup;
    }
    if (!known_entry->has_checkpoint) {
        fprintf(stderr, "known_votes missing checkpoint after interval 4\n");
        goto cleanup;
    }
    if (known_entry->checkpoint.slot != vote.data.target.slot
        || memcmp(known_entry->checkpoint.root.bytes, child_root.bytes, LANTERN_ROOT_SIZE) != 0) {
        fprintf(stderr, "known_votes checkpoint mismatch after interval 4\n");
        goto cleanup;
    }
    if (new_entry->has_checkpoint) {
        fprintf(stderr, "new_votes retained checkpoint after migration\n");
        goto cleanup;
    }
    if (client.store.new_aggregated_payloads.length != 0
        || client.store.known_aggregated_payloads.length != 1) {
        fprintf(stderr, "aggregated payload pools did not migrate after interval 4\n");
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
    if (!client.fork_choice.new_votes || !client.fork_choice.known_votes) {
        fprintf(stderr, "fork choice vote tables unavailable for skip replay test\n");
        goto cleanup;
    }
    client.fork_choice.new_aggregated_payloads = NULL;
    client.fork_choice.known_aggregated_payloads = NULL;
    client.fork_choice.attestation_data_by_root = NULL;

    LanternSignedVote vote;
    memset(&vote, 0, sizeof(vote));
    if (make_signed_vote_for_validator(&client, secret, 0u, &anchor_root, &child_root, &vote) != 0) {
        fprintf(stderr, "failed to build signed vote for skip replay test\n");
        goto cleanup;
    }
    if (lantern_fork_choice_add_vote(&client.fork_choice, &vote, false) != 0) {
        fprintf(stderr, "failed to stage fork choice vote for skip replay test\n");
        goto cleanup;
    }
    if (!client.fork_choice.new_votes[0].has_checkpoint || client.fork_choice.known_votes[0].has_checkpoint) {
        fprintf(stderr, "skip replay test did not stage vote in new_votes as expected\n");
        goto cleanup;
    }

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
    if (!client.fork_choice.known_votes[0].has_checkpoint
        || client.fork_choice.known_votes[0].slot != vote.data.slot
        || memcmp(
               client.fork_choice.known_votes[0].checkpoint.root.bytes,
               child_root.bytes,
               LANTERN_ROOT_SIZE)
            != 0) {
        fprintf(stderr, "skip replay helper did not accept votes at skipped interval 4\n");
        goto cleanup;
    }
    if (client.fork_choice.new_votes[0].has_checkpoint) {
        fprintf(stderr, "skip replay helper left pending vote entries after skipped interval 4\n");
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

static int test_safe_target_uses_attached_aggregated_payloads(void) {
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
    if (memcmp(client.fork_choice.safe_target.bytes, child_root.bytes, LANTERN_ROOT_SIZE) != 0) {
        fprintf(stderr, "safe target did not count attached aggregated payload support\n");
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
    if (lantern_client_set_gossip_signature(
            &client,
            &stale_key,
            &stale_new_data,
            &stale_signature,
            stale_new_data.target.slot)
        != 0
        || lantern_client_set_gossip_signature(
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
        || client.store.gossip_signatures.length != 2) {
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
        || client.store.gossip_signatures.length != 1) {
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
    if (client.store.gossip_signatures.entries[0].key.validator_index != fresh_key.validator_index
        || memcmp(
               client.store.gossip_signatures.entries[0].key.data_root.bytes,
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
    if (lantern_client_set_gossip_signature(
            &client,
            &stale_key,
            &stale_data,
            &stale_signature,
            stale_data.target.slot)
        != 0
        || lantern_client_set_gossip_signature(
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
        || client.store.gossip_signatures.length != 2) {
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
        || client.store.gossip_signatures.length != 1) {
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
    if (lantern_store_get_gossip_signature(&client.store, &orphan_key, &cached_signature) != 0) {
        fprintf(stderr, "orphan gossip signature should remain after root-tracking prune test\n");
        goto cleanup;
    }
    if (memcmp(&cached_signature, &orphan_signature, sizeof(cached_signature)) != 0) {
        fprintf(stderr, "orphan gossip signature mismatch after root-tracking prune test\n");
        goto cleanup;
    }
    if (lantern_store_get_gossip_signature(&client.store, &stale_key, &cached_signature) == 0) {
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
    const uint8_t *validator_pubkey = lantern_state_validator_pubkey(&client.state, 0u);
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
    LanternAttestations collected;
    LanternSignatureList collected_signatures;
    LanternAggregatedAttestations aggregated_attestations;
    LanternAttestationSignatures aggregated_signatures;
    int rc = 1;

    memset(&parent_root, 0, sizeof(parent_root));
    memset(&proof_root, 0, sizeof(proof_root));
    memset(&raw_root, 0, sizeof(raw_root));
    memset(&proof_key, 0, sizeof(proof_key));
    memset(&proof_vote, 0, sizeof(proof_vote));
    memset(&raw_vote, 0, sizeof(raw_vote));
    lantern_aggregated_signature_proof_init(&cached_proof);
    lantern_attestations_init(&collected);
    lantern_signature_list_init(&collected_signatures);
    lantern_aggregated_attestations_init(&aggregated_attestations);
    lantern_attestation_signatures_init(&aggregated_signatures);

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
    if (lantern_client_set_gossip_signature(
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
            NULL,
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
    if (memcmp(&collected.data[0], &proof_vote.data, sizeof(proof_vote.data)) != 0) {
        fprintf(stderr, "block collection did not keep the proof-backed attestation\n");
        goto cleanup;
    }
    if (memcmp(&collected_signatures.data[0], &proof_vote.signature, sizeof(proof_vote.signature)) != 0) {
        fprintf(stderr, "block collection did not recover the proof-backed attestation signature\n");
        goto cleanup;
    }

    lantern_client_error agg_rc = lantern_client_aggregate_attestations_for_block(
        &client,
        &collected,
        &collected_signatures,
        &aggregated_attestations,
        &aggregated_signatures);
    if (agg_rc != LANTERN_CLIENT_OK) {
        fprintf(stderr, "failed to aggregate collected proof-backed attestation rc=%d\n", (int)agg_rc);
        goto cleanup;
    }
    if (aggregated_attestations.length != 1u || aggregated_signatures.length != 1u) {
        fprintf(stderr, "expected cached proof reuse for collected proof-backed attestation\n");
        goto cleanup;
    }
    if (!proof_payload_equals(&aggregated_signatures.data[0], &cached_proof)) {
        fprintf(stderr, "aggregated block attestations did not reuse the known cached proof\n");
        goto cleanup;
    }

    rc = 0;

cleanup:
    lantern_attestation_signatures_reset(&aggregated_signatures);
    lantern_aggregated_attestations_reset(&aggregated_attestations);
    lantern_signature_list_reset(&collected_signatures);
    lantern_attestations_reset(&collected);
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
    if (client.store.gossip_signatures.length != 2u) {
        fprintf(stderr, "expected only matching-subnet gossip signatures before aggregation\n");
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
        fprintf(stderr, "published aggregated proof participants did not enforce subnet filtering\n");
        goto cleanup;
    }
    if (client.store.gossip_signatures.length != 0u) {
        fprintf(stderr, "expected aggregated gossip signatures to be fully pruned after publish\n");
        goto cleanup;
    }
    if (lantern_store_get_gossip_signature(&client.store, &vote0_key, &cached_signature) == 0
        || lantern_store_get_gossip_signature(&client.store, &vote4_key, &cached_signature) == 0) {
        fprintf(stderr, "aggregated subnet votes should have been removed from gossip cache\n");
        goto cleanup;
    }
    if (lantern_store_get_gossip_signature(&client.store, &vote1_key, &cached_signature) == 0) {
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

static int test_publish_attestations_skips_proposer_pending_vote(void) {
    struct lantern_client client;
    struct PQSignatureSchemePublicKey *pub = NULL;
    struct PQSignatureSchemeSecretKey *secret = NULL;
    LanternRoot anchor_root;
    LanternRoot child_root;
    struct publish_capture capture;
    struct lantern_local_validator validator;
    bool validator_enabled = true;
    LanternSignedVote proposer_vote;
    int rc = 1;

    memset(&capture, 0, sizeof(capture));
    memset(&validator, 0, sizeof(validator));
    memset(&proposer_vote, 0, sizeof(proposer_vote));

    if (client_test_setup_vote_validation_client(
            &client,
            "vote_skip_proposer_pending",
            &pub,
            &secret,
            &anchor_root,
            &child_root)
        != 0) {
        goto cleanup;
    }

    if (make_signed_vote_for_validator(&client, secret, 0u, &anchor_root, &child_root, &proposer_vote) != 0) {
        fprintf(stderr, "failed to build proposer pending vote for skip test\n");
        goto cleanup;
    }

    validator.global_index = proposer_vote.data.validator_id;
    validator.last_proposed_slot = proposer_vote.data.slot;
    validator.last_attested_slot = UINT64_MAX;
    validator.pending_attestation = proposer_vote;
    validator.pending_attestation_slot = proposer_vote.data.slot;
    validator.has_pending_attestation = true;

    client.local_validators = &validator;
    client.local_validator_count = 1u;
    client.validator_enabled = &validator_enabled;
    client.has_runtime = true;
    client.gossip_running = true;
    client.gossip.attestation_subnet_id = 0u;
    snprintf(client.gossip.vote_topic, sizeof(client.gossip.vote_topic), "test/skip_proposer_vote");
    snprintf(
        client.gossip.vote_subnet_topic,
        sizeof(client.gossip.vote_subnet_topic),
        "test/skip_proposer_vote_subnet");
    lantern_gossipsub_service_set_publish_hook(&client.gossip, publish_capture_hook, &capture);
    lantern_gossipsub_service_set_loopback_only(&client.gossip, 1);

    if (lantern_store_validator_has_vote(&client.store, proposer_vote.data.validator_id)) {
        fprintf(stderr, "validator vote cache unexpectedly populated before proposer skip test\n");
        goto cleanup;
    }

    if (validator_publish_attestations(&client, proposer_vote.data.slot) != LANTERN_CLIENT_OK) {
        fprintf(stderr, "validator_publish_attestations failed for proposer skip test\n");
        goto cleanup;
    }
    if (capture.calls != 0u) {
        fprintf(stderr, "proposer should not republish a pending attestation at interval 1\n");
        goto cleanup;
    }
    if (lantern_store_validator_has_vote(&client.store, proposer_vote.data.validator_id)) {
        fprintf(stderr, "proposer pending vote should not be staged into the validator vote cache\n");
        goto cleanup;
    }
    if (validator.last_attested_slot != proposer_vote.data.slot) {
        fprintf(stderr, "proposer skip path did not mark slot %" PRIu64 " as attested\n", proposer_vote.data.slot);
        goto cleanup;
    }
    if (validator.has_pending_attestation || validator.pending_attestation_slot != UINT64_MAX) {
        fprintf(stderr, "proposer pending attestation was not cleared after interval-1 skip\n");
        goto cleanup;
    }

    rc = 0;

cleanup:
    publish_capture_reset(&capture);
    test_reset_agg_cache(&client);
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
    if (test_safe_target_uses_attached_aggregated_payloads() != 0) {
        return 1;
    }
    if (test_new_aggregated_payloads_promote_to_known() != 0) {
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
    if (test_publish_attestations_skips_proposer_pending_vote() != 0) {
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
