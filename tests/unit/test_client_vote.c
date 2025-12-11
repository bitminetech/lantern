#include <inttypes.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>

#include "client_test_helpers.h"
#include "lantern/consensus/hash.h"
#include "lantern/support/time.h"

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
    if (!client.fork_choice.has_safe_target) {
        fprintf(stderr, "safe target unavailable after interval 2\n");
        goto cleanup;
    }
    if (memcmp(client.fork_choice.safe_target.bytes, child_root.bytes, LANTERN_ROOT_SIZE) != 0) {
        fprintf(stderr, "safe target did not reflect gossip vote after interval 2\n");
        goto cleanup;
    }
    if (!new_entry->has_checkpoint) {
        fprintf(stderr, "new_votes checkpoint missing after interval 2\n");
        goto cleanup;
    }
    if (known_entry->has_checkpoint) {
        fprintf(stderr, "known_votes filled before interval 3\n");
        goto cleanup;
    }

    if (client_test_advance_fork_choice_intervals(&client.fork_choice, 1, false) != 0) {
        fprintf(stderr, "failed to advance fork choice to interval 3\n");
        goto cleanup;
    }
    if (!known_entry->has_checkpoint) {
        fprintf(stderr, "known_votes missing checkpoint after interval 3\n");
        goto cleanup;
    }
    if (known_entry->checkpoint.slot != vote.data.target.slot
        || memcmp(known_entry->checkpoint.root.bytes, child_root.bytes, LANTERN_ROOT_SIZE) != 0) {
        fprintf(stderr, "known_votes checkpoint mismatch after interval 3\n");
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
    puts("lantern_client_vote_test OK");
    return 0;
}
