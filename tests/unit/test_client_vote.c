#include <inttypes.h>
#include <stdbool.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

#include "client_test_helpers.h"
#include "lantern/consensus/hash.h"
#include "lantern/consensus/signature.h"
#include "lantern/networking/gossip_payloads.h"
#include "lantern/support/time.h"

/* Internal core APIs used for targeted cache and block-build regression tests. */
int lantern_client_agg_proof_cache_add(
    struct lantern_client *client,
    const LanternRoot *data_root,
    const LanternAggregatedSignatureProof *proof,
    uint64_t target_slot);
size_t lantern_client_agg_proof_cache_prune_finalized(
    struct lantern_client *client,
    uint64_t finalized_slot);
lantern_client_error lantern_client_aggregate_attestations_for_block(
    struct lantern_client *client,
    const LanternAttestations *att_list,
    const LanternSignatureList *att_signatures,
    LanternAggregatedAttestations *out_attestations,
    LanternAttestationSignatures *out_signatures);

static void test_reset_agg_cache(struct lantern_client *client) {
    if (!client) {
        return;
    }
    if (client->agg_proof_cache.entries) {
        for (size_t i = 0; i < client->agg_proof_cache.length; ++i) {
            lantern_aggregated_signature_proof_reset(&client->agg_proof_cache.entries[i].proof);
        }
    }
    free(client->agg_proof_cache.entries);
    client->agg_proof_cache.entries = NULL;
    client->agg_proof_cache.length = 0;
    client->agg_proof_cache.capacity = 0;
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

    if (!lantern_state_validator_has_vote(&client.state, 0)) {
        fprintf(stderr, "known root vote was not stored\n");
        goto cleanup;
    }

    LanternSignedVote stored;
    memset(&stored, 0, sizeof(stored));
    if (lantern_state_get_signed_validator_vote(&client.state, 0, &stored) != 0) {
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

    rc = 0;

cleanup:
    client_test_teardown_vote_validation_client(&client, pub, secret);
    return rc;
}

static int test_record_vote_rejects_unknown_head(void) {
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

    if (lantern_state_validator_has_vote(&client.state, 0)) {
        fprintf(stderr, "validator unexpectedly had a stored vote before test\n");
        goto cleanup;
    }

    if (lantern_client_debug_record_vote(&client, &vote, "vote_unknown_peer") != 0) {
        fprintf(stderr, "lantern_client_debug_record_vote failed for unknown head\n");
        goto cleanup;
    }

    if (lantern_state_validator_has_vote(&client.state, 0)) {
        fprintf(stderr, "unknown head vote should not be stored\n");
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

    if (lantern_state_validator_has_vote(&client.state, 0)) {
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

    if (lantern_state_validator_has_vote(&client.state, 0)) {
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

    if (lantern_state_validator_has_vote(&client.state, 0)) {
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
    int rc = 1;

    if (client_test_setup_vote_validation_client(&client, "vote_interval", &pub, &secret, &anchor_root, &child_root) != 0) {
        return 1;
    }

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

    struct lantern_fork_choice_vote_entry *new_entry = client.fork_choice.new_votes;
    struct lantern_fork_choice_vote_entry *known_entry = client.fork_choice.known_votes;
    if (!new_entry || !known_entry) {
        fprintf(stderr, "fork choice vote tables unavailable for interval pipeline test\n");
        goto cleanup;
    }
    if (!new_entry->has_checkpoint) {
        fprintf(stderr, "gossip vote missing from new_votes immediately after record\n");
        goto cleanup;
    }
    if (known_entry->has_checkpoint) {
        fprintf(stderr, "known_votes updated before interval pipeline advanced\n");
        goto cleanup;
    }
    if (had_safe_before) {
        if (memcmp(client.fork_choice.safe_target.bytes, safe_before.bytes, LANTERN_ROOT_SIZE) != 0) {
            fprintf(stderr, "safe target changed before interval 2\n");
            goto cleanup;
        }
    }

    if (client_test_advance_fork_choice_intervals(&client.fork_choice, 1, false) != 0) {
        fprintf(stderr, "failed to advance fork choice to interval 1\n");
        goto cleanup;
    }
    if (!new_entry->has_checkpoint) {
        fprintf(stderr, "new_votes lost checkpoint before interval 2\n");
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

    if (client_test_advance_fork_choice_intervals(&client.fork_choice, 1, false) != 0) {
        fprintf(stderr, "failed to advance fork choice to interval 2\n");
        goto cleanup;
    }
    if (!new_entry->has_checkpoint) {
        fprintf(stderr, "new_votes lost checkpoint before interval 3\n");
        goto cleanup;
    }
    if (known_entry->has_checkpoint) {
        fprintf(stderr, "known_votes filled before interval 3\n");
        goto cleanup;
    }
    if (had_safe_before) {
        if (memcmp(client.fork_choice.safe_target.bytes, safe_before.bytes, LANTERN_ROOT_SIZE) != 0) {
            fprintf(stderr, "safe target changed during interval 2\n");
            goto cleanup;
        }
    }

    if (client_test_advance_fork_choice_intervals(&client.fork_choice, 1, false) != 0) {
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
    if (!new_entry->has_checkpoint) {
        fprintf(stderr, "new_votes checkpoint missing after interval 3\n");
        goto cleanup;
    }
    if (known_entry->has_checkpoint) {
        fprintf(stderr, "known_votes filled before interval 4\n");
        goto cleanup;
    }

    if (client_test_advance_fork_choice_intervals(&client.fork_choice, 1, false) != 0) {
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

    rc = 0;

cleanup:
    client_test_teardown_vote_validation_client(&client, pub, secret);
    return rc;
}

static int test_agg_proof_cache_prunes_finalized_entries(void) {
    struct lantern_client client;
    memset(&client, 0, sizeof(client));

    LanternRoot stale_root;
    LanternRoot fresh_root;
    client_test_fill_root_with_index(&stale_root, 0x101u);
    client_test_fill_root_with_index(&fresh_root, 0x202u);

    LanternAggregatedSignatureProof stale_proof;
    LanternAggregatedSignatureProof fresh_proof;
    if (test_make_dummy_proof(&stale_proof, 0, 0x11) != 0) {
        return 1;
    }
    if (test_make_dummy_proof(&fresh_proof, 1, 0x77) != 0) {
        lantern_aggregated_signature_proof_reset(&stale_proof);
        return 1;
    }

    int rc = 1;
    if (lantern_client_agg_proof_cache_add(&client, &stale_root, &stale_proof, 3) != 0) {
        fprintf(stderr, "failed to add stale cache entry\n");
        goto cleanup;
    }
    if (lantern_client_agg_proof_cache_add(&client, &fresh_root, &fresh_proof, 8) != 0) {
        fprintf(stderr, "failed to add fresh cache entry\n");
        goto cleanup;
    }
    if (client.agg_proof_cache.length != 2) {
        fprintf(stderr, "unexpected cache length before prune: %zu\n", client.agg_proof_cache.length);
        goto cleanup;
    }

    size_t removed = lantern_client_agg_proof_cache_prune_finalized(&client, 5);
    if (removed != 1) {
        fprintf(stderr, "expected one stale cache entry to be pruned, got=%zu\n", removed);
        goto cleanup;
    }
    if (client.agg_proof_cache.length != 1) {
        fprintf(stderr, "unexpected cache length after prune: %zu\n", client.agg_proof_cache.length);
        goto cleanup;
    }
    if (memcmp(
            client.agg_proof_cache.entries[0].data_root.bytes,
            fresh_root.bytes,
            LANTERN_ROOT_SIZE)
        != 0) {
        fprintf(stderr, "fresh cache entry root mismatch after prune\n");
        goto cleanup;
    }
    if (client.agg_proof_cache.entries[0].target_slot != 8) {
        fprintf(stderr, "fresh cache entry target slot mismatch after prune\n");
        goto cleanup;
    }

    rc = 0;

cleanup:
    lantern_aggregated_signature_proof_reset(&fresh_proof);
    lantern_aggregated_signature_proof_reset(&stale_proof);
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

    if (lantern_client_agg_proof_cache_add(
            &client,
            &data_root,
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

static int test_publish_aggregated_attestations_filters_cross_subnet_votes(void) {
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
    LanternSignedAggregatedAttestation decoded;
    int rc = 1;

    memset(&capture, 0, sizeof(capture));
    memset(&assigned, 0, sizeof(assigned));
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

    if (lantern_client_debug_publish_aggregated_attestations(&client, vote0.data.slot) != LANTERN_CLIENT_OK) {
        fprintf(stderr, "aggregated attestation publish should succeed for aggregator\n");
        goto cleanup;
    }
    if (capture.calls != 1u || capture.payload_len == 0 || !capture.payload) {
        fprintf(stderr, "expected one aggregated attestation publish in subnet filter test\n");
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

    rc = 0;

cleanup:
    lantern_signed_aggregated_attestation_reset(&decoded);
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
    if (test_record_vote_rejects_unknown_head() != 0) {
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
    if (test_agg_proof_cache_prunes_finalized_entries() != 0) {
        return 1;
    }
    if (test_validator_build_reuses_cached_group_proof() != 0) {
        return 1;
    }
    if (test_publish_aggregated_attestations_filters_cross_subnet_votes() != 0) {
        return 1;
    }
    if (test_interval_2_aggregation_trigger_respects_aggregator_role() != 0) {
        return 1;
    }
    puts("lantern_client_vote_test OK");
    return 0;
}
