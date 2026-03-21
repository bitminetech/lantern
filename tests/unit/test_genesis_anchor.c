#include <errno.h>
#include <inttypes.h>
#include <limits.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "lantern/consensus/hash.h"
#include "lantern/consensus/state.h"
#include "lantern/core/client.h"
#include "lantern/storage/storage.h"
#include "lantern/support/strings.h"

#include "client_test_helpers.h"
#include "../../src/core/client_internal.h"
#include "../../src/core/client_services_internal.h"
#include "../../src/core/client_sync_internal.h"

static void fill_pubkeys(uint8_t *pubkeys, size_t count)
{
    if (!pubkeys)
    {
        return;
    }
    for (size_t i = 0; i < count; ++i)
    {
        for (size_t j = 0; j < LANTERN_VALIDATOR_PUBKEY_SIZE; ++j)
        {
            pubkeys[(i * LANTERN_VALIDATOR_PUBKEY_SIZE) + j] = (uint8_t)(((i + 1u) * 31u) + j);
        }
    }
}

static int roots_equal(const LanternRoot *left, const LanternRoot *right)
{
    if (!left || !right)
    {
        return 0;
    }
    return memcmp(left->bytes, right->bytes, LANTERN_ROOT_SIZE) == 0;
}

static void fill_root(LanternRoot *root, uint8_t value)
{
    if (!root)
    {
        return;
    }
    memset(root->bytes, value, LANTERN_ROOT_SIZE);
}

static void cleanup_path(const char *path)
{
    if (!path)
    {
        return;
    }
    if (unlink(path) != 0 && errno != ENOENT)
    {
        fprintf(stderr, "failed to remove %s: %s\n", path, strerror(errno));
    }
}

static void cleanup_dir(const char *path)
{
    if (!path)
    {
        return;
    }
    if (rmdir(path) != 0 && errno != ENOENT && errno != ENOTEMPTY && errno != EEXIST)
    {
        fprintf(stderr, "failed to remove dir %s: %s\n", path, strerror(errno));
    }
}

static void cleanup_storage_root_file(
    const char *data_dir,
    const char *subdir,
    const LanternRoot *root,
    const char *ext)
{
    if (!data_dir || !subdir || !root || !ext)
    {
        return;
    }

    char root_hex[(2u * LANTERN_ROOT_SIZE) + 1u];
    if (lantern_bytes_to_hex(root->bytes, LANTERN_ROOT_SIZE, root_hex, sizeof(root_hex), 0) != 0)
    {
        return;
    }

    char path[PATH_MAX];
    int written = snprintf(path, sizeof(path), "%s/%s/%s.%s", data_dir, subdir, root_hex, ext);
    if (written <= 0 || (size_t)written >= sizeof(path))
    {
        return;
    }
    cleanup_path(path);
}

static int build_signed_head_block(
    struct lantern_client *client,
    struct PQSignatureSchemeSecretKey *secret,
    LanternSignedBlock *out_block,
    LanternRoot *out_root)
{
    if (!client || !secret || !out_block || !out_root)
    {
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
        != 0)
    {
        goto cleanup;
    }
    if (lantern_state_select_block_parent(
            &client->state,
            &client->store,
            &out_block->message.block.parent_root)
        != 0)
    {
        goto cleanup;
    }
    if (lantern_state_compute_vote_checkpoints(
            &client->state,
            &client->store,
            &head,
            &target,
            &source)
        != 0)
    {
        goto cleanup;
    }

    proposer_vote.data.validator_id = out_block->message.block.proposer_index;
    proposer_vote.data.slot = out_block->message.block.slot;
    proposer_vote.data.head = head;
    proposer_vote.data.target = target;
    proposer_vote.data.source = source;
    if (client_test_sign_vote_with_secret(&proposer_vote, secret) != 0)
    {
        goto cleanup;
    }

    out_block->message.proposer_attestation = proposer_vote.data;
    out_block->signatures.proposer_signature = proposer_vote.signature;

    if (lantern_state_preview_post_state_root(
            &client->state,
            &client->store,
            out_block,
            &out_block->message.block.state_root)
        != 0)
    {
        goto cleanup;
    }
    if (lantern_hash_tree_root_block(&out_block->message.block, out_root) != 0)
    {
        goto cleanup;
    }

    rc = 0;

cleanup:
    if (rc != 0)
    {
        lantern_signed_block_with_attestation_reset(out_block);
    }
    return rc;
}

static int test_checkpoint_consumers_use_fork_choice_store(void)
{
    struct lantern_client client;
    memset(&client, 0, sizeof(client));

    struct PQSignatureSchemePublicKey *pub = NULL;
    struct PQSignatureSchemeSecretKey *secret = NULL;
    LanternRoot anchor_root = {0};
    LanternRoot child_root = {0};
    LanternRoot grandchild_root = {0};
    LanternSignedBlock grandchild_block;
    bool grandchild_block_ready = false;
    bool state_locked = false;
    bool state_lock_held = false;
    LanternState scratch;
    lantern_state_init(&scratch);

    char dir_template[] = "/tmp/lantern_checkpoint_consumersXXXXXX";
    char *data_dir = NULL;
    uint8_t *http_bytes = NULL;
    size_t http_len = 0;
    uint8_t *expected_bytes = NULL;
    size_t expected_len = 0;
    int rc = 1;

    if (client_test_setup_vote_validation_client(
            &client,
            "checkpoint_consumer_regression",
            &pub,
            &secret,
            &anchor_root,
            &child_root)
        != 0)
    {
        fprintf(stderr, "failed to set up checkpoint consumer regression client\n");
        goto cleanup;
    }
    (void)anchor_root;

    if (build_signed_head_block(&client, secret, &grandchild_block, &grandchild_root) != 0)
    {
        fprintf(stderr, "failed to build grandchild block for checkpoint consumer regression\n");
        goto cleanup;
    }
    grandchild_block_ready = true;

    char *temp_dir = mkdtemp(dir_template);
    if (!temp_dir)
    {
        fprintf(stderr, "failed to create temp data dir for checkpoint consumer regression\n");
        goto cleanup;
    }
    data_dir = strdup(temp_dir);
    if (!data_dir)
    {
        fprintf(stderr, "failed to create temp data dir for checkpoint consumer regression\n");
        goto cleanup;
    }
    client.data_dir = data_dir;

    if (lantern_storage_store_state_for_root(data_dir, &child_root, &client.state) != 0)
    {
        fprintf(stderr, "failed to store child state snapshot for checkpoint consumer regression\n");
        goto cleanup;
    }
    if (lantern_storage_store_block_for_root(data_dir, &grandchild_root, &grandchild_block) != 0)
    {
        fprintf(stderr, "failed to store grandchild block for checkpoint consumer regression\n");
        goto cleanup;
    }

    if (lantern_fork_choice_add_block(
            &client.fork_choice,
            &grandchild_block.message.block,
            NULL,
            &client.state.latest_justified,
            &client.state.latest_finalized,
            &grandchild_root)
        != 0)
    {
        fprintf(stderr, "failed to add grandchild to fork choice for checkpoint consumer regression\n");
        goto cleanup;
    }

    LanternCheckpoint child_checkpoint = {
        .slot = client.state.slot,
        .root = child_root,
    };
    if (lantern_fork_choice_update_checkpoints(
            &client.fork_choice,
            &child_checkpoint,
            &child_checkpoint)
        != 0)
    {
        fprintf(stderr, "failed to move fork-choice checkpoints to child root\n");
        goto cleanup;
    }

    LanternCheckpoint remote_finalized = client.state.latest_finalized;
    fill_root(&remote_finalized.root, 0xA5u);
    remote_finalized.slot = child_checkpoint.slot;
    if (roots_equal(&remote_finalized.root, &child_root))
    {
        remote_finalized.root.bytes[0] ^= 0x01u;
    }
    client.state.latest_finalized = remote_finalized;

    LanternStatusMessage status;
    memset(&status, 0, sizeof(status));
    if (reqresp_build_status(&client, &status) != LANTERN_CLIENT_OK)
    {
        fprintf(stderr, "reqresp_build_status failed for checkpoint consumer regression\n");
        goto cleanup;
    }
    if (status.finalized.slot != child_checkpoint.slot
        || !roots_equal(&status.finalized.root, &child_root))
    {
        fprintf(stderr, "status finalized checkpoint did not follow fork choice store\n");
        goto cleanup;
    }
    if (roots_equal(&status.finalized.root, &client.state.latest_finalized.root))
    {
        fprintf(stderr, "status finalized checkpoint incorrectly used client state root\n");
        goto cleanup;
    }

    if (http_finalized_state_ssz_cb(&client, &http_bytes, &http_len) != LANTERN_HTTP_CB_OK)
    {
        fprintf(stderr, "http_finalized_state_ssz_cb failed for checkpoint consumer regression\n");
        goto cleanup;
    }
    if (lantern_storage_load_state_bytes_for_root(
            data_dir,
            &child_root,
            &expected_bytes,
            &expected_len)
        != 0)
    {
        fprintf(stderr, "failed to load expected child state bytes for checkpoint consumer regression\n");
        goto cleanup;
    }
    if (http_len != expected_len || memcmp(http_bytes, expected_bytes, expected_len) != 0)
    {
        fprintf(stderr, "finalized HTTP endpoint did not load bytes for fork-choice finalized root\n");
        goto cleanup;
    }

    state_locked = lantern_client_lock_state(&client);
    if (client.state_lock_initialized && !state_locked)
    {
        fprintf(stderr, "failed to lock state for checkpoint consumer regression\n");
        goto cleanup;
    }
    state_lock_held = state_locked;

    bool used_scratch = false;
    const LanternState *rebuilt =
        lantern_client_state_for_root_locked(&client, &grandchild_root, &scratch, &used_scratch);
    if (!rebuilt || !used_scratch)
    {
        fprintf(stderr, "grandchild state rebuild did not use finalized shortcut from fork choice\n");
        goto cleanup;
    }
    if (rebuilt->slot != grandchild_block.message.block.slot)
    {
        fprintf(stderr, "grandchild state rebuild returned wrong slot\n");
        goto cleanup;
    }
    if (!roots_equal(&client.state.latest_finalized.root, &remote_finalized.root))
    {
        fprintf(stderr, "checkpoint consumer regression mutated client state\n");
        goto cleanup;
    }

    rc = 0;

cleanup:
    if (state_lock_held)
    {
        lantern_client_unlock_state(&client, state_locked);
    }
    free(http_bytes);
    free(expected_bytes);
    lantern_state_reset(&scratch);
    if (grandchild_block_ready)
    {
        lantern_signed_block_with_attestation_reset(&grandchild_block);
    }
    if (data_dir)
    {
        cleanup_storage_root_file(data_dir, "states", &child_root, "ssz");
        cleanup_storage_root_file(data_dir, "states", &child_root, "meta");
        cleanup_storage_root_file(data_dir, "states", &grandchild_root, "ssz");
        cleanup_storage_root_file(data_dir, "states", &grandchild_root, "meta");
        cleanup_storage_root_file(data_dir, "blocks", &grandchild_root, "ssz");
        char states_dir[PATH_MAX];
        char blocks_dir[PATH_MAX];
        int states_written = snprintf(states_dir, sizeof(states_dir), "%s/states", data_dir);
        int blocks_written = snprintf(blocks_dir, sizeof(blocks_dir), "%s/blocks", data_dir);
        if (states_written > 0 && (size_t)states_written < sizeof(states_dir))
        {
            cleanup_dir(states_dir);
        }
        if (blocks_written > 0 && (size_t)blocks_written < sizeof(blocks_dir))
        {
            cleanup_dir(blocks_dir);
        }
        client.data_dir = NULL;
        cleanup_dir(data_dir);
        free(data_dir);
    }
    client_test_teardown_vote_validation_client(&client, pub, secret);
    return rc;
}

int main(void)
{
    struct lantern_client client;
    memset(&client, 0, sizeof(client));
    client.node_id = "genesis_anchor_regression";
    client.has_state = true;
    lantern_state_init(&client.state);

    if (lantern_state_generate_genesis(&client.state, UINT64_C(1761717362), 3u) != 0)
    {
        fprintf(stderr, "failed to generate genesis state\n");
        return 1;
    }

    uint8_t pubkeys[3u * LANTERN_VALIDATOR_PUBKEY_SIZE];
    fill_pubkeys(pubkeys, 3u);
    if (lantern_state_set_validator_pubkeys(&client.state, pubkeys, 3u) != 0)
    {
        fprintf(stderr, "failed to set validator pubkeys\n");
        lantern_state_reset(&client.state);
        return 1;
    }

    LanternRoot canonical_state_root;
    if (lantern_hash_tree_root_state(&client.state, &canonical_state_root) != 0)
    {
        fprintf(stderr, "failed to hash canonical genesis state\n");
        lantern_state_reset(&client.state);
        return 1;
    }

    LanternBlockHeader expected_anchor_header = client.state.latest_block_header;
    expected_anchor_header.state_root = canonical_state_root;

    LanternRoot expected_anchor_root;
    if (lantern_hash_tree_root_block_header(&expected_anchor_header, &expected_anchor_root) != 0)
    {
        fprintf(stderr, "failed to hash expected anchor header\n");
        lantern_state_reset(&client.state);
        return 1;
    }

    /*
     * Simulate previously persisted bootstrap snapshots where genesis header
     * state_root was eagerly populated before restart.
     */
    client.state.latest_block_header.state_root = canonical_state_root;

    if (initialize_fork_choice(&client) != LANTERN_CLIENT_OK)
    {
        fprintf(stderr, "initialize_fork_choice failed\n");
        lantern_state_reset(&client.state);
        lantern_fork_choice_reset(&client.fork_choice);
        return 1;
    }

    LanternRoot actual_head;
    if (lantern_fork_choice_current_head(&client.fork_choice, &actual_head) != 0)
    {
        fprintf(stderr, "failed to read fork choice head\n");
        lantern_state_reset(&client.state);
        lantern_fork_choice_reset(&client.fork_choice);
        return 1;
    }

    if (!roots_equal(&actual_head, &expected_anchor_root))
    {
        fprintf(stderr, "fork choice anchor mismatch for persisted genesis snapshot\n");
        lantern_state_reset(&client.state);
        lantern_fork_choice_reset(&client.fork_choice);
        return 1;
    }

    if (!roots_equal(&client.state.latest_block_header.state_root, &canonical_state_root))
    {
        fprintf(stderr, "initialize_fork_choice unexpectedly rewrote genesis header state_root\n");
        lantern_state_reset(&client.state);
        lantern_fork_choice_reset(&client.fork_choice);
        return 1;
    }

    lantern_state_reset(&client.state);
    lantern_fork_choice_reset(&client.fork_choice);

    /*
     * Restart regression: initialize_fork_choice must preserve persisted
     * justified/finalized checkpoints for non-genesis snapshots.
     */
    memset(&client, 0, sizeof(client));
    client.node_id = "fork_choice_checkpoint_restore";
    client.has_state = true;
    lantern_state_init(&client.state);

    if (lantern_state_generate_genesis(&client.state, UINT64_C(1761717362), 4u) != 0)
    {
        fprintf(stderr, "failed to generate restart regression state\n");
        return 1;
    }

    uint8_t restart_pubkeys[4u * LANTERN_VALIDATOR_PUBKEY_SIZE];
    fill_pubkeys(restart_pubkeys, 4u);
    if (lantern_state_set_validator_pubkeys(&client.state, restart_pubkeys, 4u) != 0)
    {
        fprintf(stderr, "failed to set validator pubkeys for restart regression\n");
        lantern_state_reset(&client.state);
        return 1;
    }

    client.state.slot = 447u;
    client.state.latest_block_header.slot = 443u;
    client.state.latest_block_header.proposer_index = 1u;
    fill_root(&client.state.latest_block_header.parent_root, 0x55u);

    LanternCheckpoint expected_justified;
    LanternCheckpoint expected_finalized;
    fill_root(&expected_justified.root, 0x39u);
    expected_justified.slot = 439u;
    fill_root(&expected_finalized.root, 0x34u);
    expected_finalized.slot = 434u;
    client.state.latest_justified = expected_justified;
    client.state.latest_finalized = expected_finalized;

    LanternRoot restart_state_root;
    if (lantern_hash_tree_root_state(&client.state, &restart_state_root) != 0)
    {
        fprintf(stderr, "failed to hash restart regression state\n");
        lantern_state_reset(&client.state);
        return 1;
    }
    LanternBlockHeader restart_anchor_header = client.state.latest_block_header;
    restart_anchor_header.state_root = restart_state_root;
    LanternRoot expected_restart_anchor_root;
    if (lantern_hash_tree_root_block_header(&restart_anchor_header, &expected_restart_anchor_root) != 0)
    {
        fprintf(stderr, "failed to hash restart regression anchor header\n");
        lantern_state_reset(&client.state);
        return 1;
    }

    if (initialize_fork_choice(&client) != LANTERN_CLIENT_OK)
    {
        fprintf(stderr, "initialize_fork_choice failed for restart regression\n");
        lantern_state_reset(&client.state);
        lantern_fork_choice_reset(&client.fork_choice);
        return 1;
    }

    LanternRoot restart_head;
    if (lantern_fork_choice_current_head(&client.fork_choice, &restart_head) != 0)
    {
        fprintf(stderr, "failed to read restart regression fork choice head\n");
        lantern_state_reset(&client.state);
        lantern_fork_choice_reset(&client.fork_choice);
        return 1;
    }
    if (!roots_equal(&restart_head, &expected_restart_anchor_root))
    {
        fprintf(stderr, "restart regression head mismatch\n");
        lantern_state_reset(&client.state);
        lantern_fork_choice_reset(&client.fork_choice);
        return 1;
    }

    /*
     * After initialize_fork_choice the store checkpoints match the anchor
     * (not the persisted state checkpoints).  Real persisted checkpoints are
     * synced later by restore_persisted_blocks → restore_checkpoints.
     */
    const LanternCheckpoint *store_justified =
        lantern_fork_choice_latest_justified(&client.fork_choice);
    const LanternCheckpoint *store_finalized =
        lantern_fork_choice_latest_finalized(&client.fork_choice);
    if (!store_justified || !store_finalized)
    {
        fprintf(stderr, "missing fork-choice checkpoints after restart init\n");
        lantern_state_reset(&client.state);
        lantern_fork_choice_reset(&client.fork_choice);
        return 1;
    }
    if (store_justified->slot != restart_anchor_header.slot
        || !roots_equal(&store_justified->root, &expected_restart_anchor_root))
    {
        fprintf(stderr,
            "justified checkpoint should match anchor after init "
            "(got slot=%" PRIu64 " expected slot=%" PRIu64 ")\n",
            store_justified->slot, (uint64_t)restart_anchor_header.slot);
        lantern_state_reset(&client.state);
        lantern_fork_choice_reset(&client.fork_choice);
        return 1;
    }
    if (store_finalized->slot != restart_anchor_header.slot
        || !roots_equal(&store_finalized->root, &expected_restart_anchor_root))
    {
        fprintf(stderr,
            "finalized checkpoint should match anchor after init "
            "(got slot=%" PRIu64 " expected slot=%" PRIu64 ")\n",
            store_finalized->slot, (uint64_t)restart_anchor_header.slot);
        lantern_state_reset(&client.state);
        lantern_fork_choice_reset(&client.fork_choice);
        return 1;
    }

    if (test_checkpoint_consumers_use_fork_choice_store() != 0)
    {
        lantern_state_reset(&client.state);
        lantern_fork_choice_reset(&client.fork_choice);
        return 1;
    }

    lantern_state_reset(&client.state);
    lantern_fork_choice_reset(&client.fork_choice);
    return 0;
}
