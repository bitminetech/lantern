#include <errno.h>
#include <inttypes.h>
#include <limits.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "lantern/consensus/hash.h"
#include "lantern/consensus/signature.h"
#include "lantern/consensus/state.h"
#include "lantern/core/client.h"
#include "lantern/http/client.h"
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

static void build_fixture_path(char *buffer, size_t length, const char *relative)
{
    if (!buffer || length == 0u || !relative)
    {
        return;
    }
    int written = snprintf(buffer, length, "%s/%s", LANTERN_TEST_FIXTURE_DIR, relative);
    if (written <= 0 || (size_t)written >= length)
    {
        buffer[0] = '\0';
    }
}

static int write_empty_temp_file(char *buffer, size_t length, const char *prefix)
{
    if (!buffer || length == 0u || !prefix)
    {
        return -1;
    }
    int written = snprintf(buffer, length, "/tmp/%s_%ld.yaml", prefix, (long)getpid());
    if (written <= 0 || (size_t)written >= length)
    {
        buffer[0] = '\0';
        return -1;
    }

    FILE *fp = fopen(buffer, "w");
    if (!fp)
    {
        buffer[0] = '\0';
        return -1;
    }
    fclose(fp);
    return 0;
}

static void cleanup_init_data_dir(const char *data_dir)
{
    if (!data_dir)
    {
        return;
    }

    static const char *const files[] = {
        "state.ssz",
        "finalized_state.ssz",
        "votes.bin",
        "head.bin",
        "checkpoints.bin",
    };
    for (size_t i = 0; i < sizeof(files) / sizeof(files[0]); ++i)
    {
        char path[PATH_MAX];
        int written = snprintf(path, sizeof(path), "%s/%s", data_dir, files[i]);
        if (written > 0 && (size_t)written < sizeof(path))
        {
            cleanup_path(path);
        }
    }

    char path[PATH_MAX];
    int written = snprintf(path, sizeof(path), "%s/indices/slots", data_dir);
    if (written > 0 && (size_t)written < sizeof(path))
    {
        cleanup_dir(path);
    }

    static const char *const dirs[] = {
        "blocks",
        "invalid_blocks",
        "states",
        "indices",
    };
    for (size_t i = 0; i < sizeof(dirs) / sizeof(dirs[0]); ++i)
    {
        written = snprintf(path, sizeof(path), "%s/%s", data_dir, dirs[i]);
        if (written > 0 && (size_t)written < sizeof(path))
        {
            cleanup_dir(path);
        }
    }
    cleanup_dir(data_dir);
}

static int build_proposer_only_block_proof(
    const LanternState *state,
    LanternSignedBlock *block,
    const LanternRoot *block_root,
    const LanternSignature *proposer_signature)
{
    if (!state || !block || !block_root || !proposer_signature)
    {
        return -1;
    }

    int rc = -1;
    LanternAggregatedSignatureProof proposer_proof;
    LanternAttestationSignatures attestation_proofs;
    struct lantern_bitlist proposer_participants;
    lantern_aggregated_signature_proof_init(&proposer_proof);
    lantern_attestation_signatures_init(&attestation_proofs);
    lantern_bitlist_init(&proposer_participants);

    size_t proposer_index = (size_t)block->block.proposer_index;
    const uint8_t *proposer_pubkey = lantern_state_validator_proposal_pubkey(state, proposer_index);
    if (!proposer_pubkey)
    {
        goto cleanup;
    }
    if (lantern_bitlist_resize(&proposer_participants, proposer_index + 1u) != 0
        || lantern_bitlist_set(&proposer_participants, proposer_index, true) != 0)
    {
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
            &proposer_proof))
    {
        goto cleanup;
    }
    if (!lantern_signature_merge_block_type2_proof(
            state,
            &block->block,
            &attestation_proofs,
            &proposer_proof,
            &block->proof))
    {
        goto cleanup;
    }

    rc = 0;

cleanup:
    lantern_bitlist_reset(&proposer_participants);
    lantern_attestation_signatures_reset(&attestation_proofs);
    lantern_aggregated_signature_proof_reset(&proposer_proof);
    return rc;
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
    lantern_signed_block_init(out_block);
    out_block->block.slot = client->state.slot + 1u;
    if (lantern_proposer_for_slot(
            out_block->block.slot,
            client->state.config.num_validators,
            &out_block->block.proposer_index)
        != 0)
    {
        goto cleanup;
    }
    if (lantern_state_select_block_parent(
            &client->state,
            &client->store,
            &out_block->block.parent_root)
        != 0)
    {
        goto cleanup;
    }

    if (lantern_state_preview_post_state_root(
            &client->state,
            &client->store,
            out_block,
            &out_block->block.state_root)
        != 0)
    {
        goto cleanup;
    }
    if (lantern_hash_tree_root_block(&out_block->block, out_root) != SSZ_SUCCESS)
    {
        goto cleanup;
    }
    LanternSignature proposer_signature;
    memset(&proposer_signature, 0, sizeof(proposer_signature));
    if (!lantern_signature_sign(
            secret,
            out_block->block.slot,
            out_root,
            &proposer_signature))
    {
        goto cleanup;
    }
    if (build_proposer_only_block_proof(
            &client->state,
            out_block,
            out_root,
            &proposer_signature)
        != 0)
    {
        goto cleanup;
    }

    rc = 0;

cleanup:
    if (rc != 0)
    {
        lantern_signed_block_reset(out_block);
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
            &grandchild_block.block,
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
    if (rebuilt->slot != grandchild_block.block.slot)
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
        lantern_signed_block_reset(&grandchild_block);
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

static int test_http_checkpoint_callbacks_do_not_take_state_lock(void)
{
    struct lantern_client client;
    memset(&client, 0, sizeof(client));

    struct PQSignatureSchemePublicKey *pub = NULL;
    struct PQSignatureSchemeSecretKey *secret = NULL;
    LanternRoot anchor_root = {0};
    LanternRoot child_root = {0};
    char dir_template[] = "/tmp/lantern_http_checkpoint_snapshotXXXXXX";
    char *data_dir = NULL;
    uint8_t *state_bytes = NULL;
    size_t state_len = 0;
    bool state_locked = false;
    int rc = 1;

    if (client_test_setup_vote_validation_client(
            &client,
            "http_checkpoint_snapshot_regression",
            &pub,
            &secret,
            &anchor_root,
            &child_root)
        != 0)
    {
        fprintf(stderr, "failed to set up HTTP checkpoint snapshot regression client\n");
        goto cleanup;
    }

    LanternCheckpoint justified;
    LanternCheckpoint finalized;
    memset(&justified, 0, sizeof(justified));
    memset(&finalized, 0, sizeof(finalized));
    if (!lantern_fork_choice_read_checkpoint_snapshot(
            &client.fork_choice,
            &justified,
            &finalized))
    {
        fprintf(stderr, "checkpoint snapshot was not initialized by fork choice setup\n");
        goto cleanup;
    }

    char *temp_dir = mkdtemp(dir_template);
    if (!temp_dir)
    {
        fprintf(stderr, "failed to create temp data dir for HTTP checkpoint snapshot regression\n");
        goto cleanup;
    }
    data_dir = strdup(temp_dir);
    if (!data_dir)
    {
        fprintf(stderr, "failed to copy temp data dir for HTTP checkpoint snapshot regression\n");
        goto cleanup;
    }
    client.data_dir = data_dir;

    if (lantern_storage_store_state_for_root(data_dir, &finalized.root, &client.state) != 0)
    {
        fprintf(stderr, "failed to store finalized state for HTTP checkpoint snapshot regression\n");
        goto cleanup;
    }

    state_locked = lantern_client_lock_state(&client);
    if (!state_locked)
    {
        fprintf(stderr, "failed to lock state for HTTP checkpoint snapshot regression\n");
        goto cleanup;
    }

    struct lantern_http_head_snapshot head_snapshot;
    memset(&head_snapshot, 0, sizeof(head_snapshot));
    if (http_snapshot_head(&client, &head_snapshot) != LANTERN_HTTP_CB_OK)
    {
        fprintf(stderr, "http_snapshot_head should not need state_lock\n");
        goto cleanup;
    }
    if (!roots_equal(&head_snapshot.justified.root, &justified.root)
        || head_snapshot.justified.slot != justified.slot)
    {
        fprintf(stderr, "http_snapshot_head did not read the justified checkpoint snapshot\n");
        goto cleanup;
    }

    if (http_finalized_state_ssz_cb(&client, &state_bytes, &state_len) != LANTERN_HTTP_CB_OK)
    {
        fprintf(stderr, "http_finalized_state_ssz_cb should not need state_lock\n");
        goto cleanup;
    }
    if (!state_bytes || state_len == 0)
    {
        fprintf(stderr, "http finalized state callback returned empty state bytes\n");
        goto cleanup;
    }

    rc = 0;

cleanup:
    if (state_locked)
    {
        lantern_client_unlock_state(&client, state_locked);
    }
    free(state_bytes);
    if (data_dir)
    {
        cleanup_storage_root_file(data_dir, "states", &finalized.root, "ssz");
        cleanup_storage_root_file(data_dir, "states", &finalized.root, "meta");
        char states_dir[PATH_MAX];
        int states_written = snprintf(states_dir, sizeof(states_dir), "%s/states", data_dir);
        if (states_written > 0 && (size_t)states_written < sizeof(states_dir))
        {
            cleanup_dir(states_dir);
        }
        cleanup_dir(data_dir);
    }
    client.data_dir = NULL;
    free(data_dir);
    client_test_teardown_vote_validation_client(&client, pub, secret);
    return rc;
}

static int test_checkpoint_sync_parse_url_scheme_handling(void)
{
    struct lantern_http_url url = {0};

    if (lantern_http_url_parse(
            "http://checkpoint.example:5052/lean/v0/states/finalized",
            &url)
        != 0)
    {
        fprintf(stderr, "failed to parse http checkpoint sync url\n");
        goto fail;
    }
    if (!url.host || strcmp(url.host, "checkpoint.example") != 0)
    {
        fprintf(stderr, "unexpected checkpoint sync host\n");
        goto fail;
    }
    if (url.port != 5052u)
    {
        fprintf(stderr, "unexpected checkpoint sync port\n");
        goto fail;
    }
    if (!url.path || strcmp(url.path, "/lean/v0/states/finalized") != 0)
    {
        fprintf(stderr, "unexpected checkpoint sync base path\n");
        goto fail;
    }

    lantern_http_url_reset(&url);

    if (lantern_http_url_parse(
            "http://127.0.0.1:/lean/v0/states/finalized",
            &url)
        == 0)
    {
        fprintf(stderr, "checkpoint sync URL with empty port should be rejected\n");
        goto fail;
    }
    if (url.host || url.path || url.port != 0)
    {
        fprintf(stderr, "empty-port checkpoint sync parse should not return partial output\n");
        goto fail;
    }

    if (lantern_http_url_parse(
            "https://checkpoint.example/lean/v0/states/finalized",
            &url)
        != 0)
    {
        fprintf(stderr, "failed to parse https checkpoint sync url for downgrade\n");
        goto fail;
    }
    if (!url.host || strcmp(url.host, "checkpoint.example") != 0)
    {
        fprintf(stderr, "unexpected downgraded checkpoint sync host\n");
        goto fail;
    }
    if (url.port != 80u)
    {
        fprintf(stderr, "unexpected downgraded checkpoint sync port\n");
        goto fail;
    }
    if (!url.path || strcmp(url.path, "/lean/v0/states/finalized") != 0)
    {
        fprintf(stderr, "unexpected downgraded checkpoint sync base path\n");
        goto fail;
    }

    lantern_http_url_reset(&url);
    return 0;

fail:
    lantern_http_url_reset(&url);
    return 1;
}

static int test_pre_anchor_block_is_rejected_below_anchor_finalization(void)
{
    struct lantern_client client;
    memset(&client, 0, sizeof(client));
    client.node_id = "pre_anchor_floor_regression";
    client.has_state = true;
    lantern_state_init(&client.state);
    lantern_store_init(&client.store);

    if (pthread_mutex_init(&client.state_lock, NULL) != 0)
    {
        fprintf(stderr, "failed to initialize state lock for pre-anchor regression\n");
        lantern_store_reset(&client.store);
        lantern_state_reset(&client.state);
        return 1;
    }
    client.state_lock_initialized = true;

    if (pthread_mutex_init(&client.pending_lock, NULL) != 0)
    {
        fprintf(stderr, "failed to initialize pending lock for pre-anchor regression\n");
        pthread_mutex_destroy(&client.state_lock);
        client.state_lock_initialized = false;
        lantern_store_reset(&client.store);
        lantern_state_reset(&client.state);
        return 1;
    }
    client.pending_lock_initialized = true;

    if (lantern_state_generate_genesis(&client.state, UINT64_C(1761717362), 4u) != 0)
    {
        fprintf(stderr, "failed to generate state for pre-anchor regression\n");
        goto cleanup;
    }

    uint8_t pubkeys[4u * LANTERN_VALIDATOR_PUBKEY_SIZE];
    fill_pubkeys(pubkeys, 4u);
    if (lantern_state_set_validator_pubkeys(&client.state, pubkeys, 4u) != 0)
    {
        fprintf(stderr, "failed to set validator pubkeys for pre-anchor regression\n");
        goto cleanup;
    }

    client.state.slot = 447u;
    client.state.latest_block_header.slot = 443u;
    client.state.latest_block_header.proposer_index = 1u;
    fill_root(&client.state.latest_block_header.parent_root, 0x55u);
    fill_root(&client.state.latest_justified.root, 0x39u);
    client.state.latest_justified.slot = 439u;
    fill_root(&client.state.latest_finalized.root, 0x34u);
    client.state.latest_finalized.slot = 434u;

    if (initialize_fork_choice(&client) != LANTERN_CLIENT_OK)
    {
        fprintf(stderr, "initialize_fork_choice failed for pre-anchor regression\n");
        goto cleanup;
    }

    LanternSignedBlock historical;
    lantern_signed_block_init(&historical);
    historical.block.slot = 440u;
    historical.block.proposer_index = 0u;
    fill_root(&historical.block.parent_root, 0x91u);
    fill_root(&historical.block.state_root, 0x92u);

    LanternRoot historical_root;
    if (lantern_hash_tree_root_block(&historical.block, &historical_root) != SSZ_SUCCESS)
    {
        fprintf(stderr, "failed to hash historical block for pre-anchor regression\n");
        lantern_signed_block_reset(&historical);
        goto cleanup;
    }

    bool imported = lantern_client_import_block(
        &client,
        &historical,
        &historical_root,
        &(const struct lantern_log_metadata){.validator = client.node_id},
        0,
        true,
        NULL,
        0);
    lantern_signed_block_reset(&historical);

    if (imported)
    {
        fprintf(stderr, "pre-anchor historical block should not import\n");
        goto cleanup;
    }
    if (client.pending_blocks.length != 0u)
    {
        fprintf(stderr, "pre-anchor block below the anchor finalized slot should not be queued\n");
        goto cleanup;
    }

    pending_block_list_reset(&client.pending_blocks);
    lantern_fork_choice_reset(&client.fork_choice);
    lantern_store_reset(&client.store);
    lantern_state_reset(&client.state);
    pthread_mutex_destroy(&client.pending_lock);
    pthread_mutex_destroy(&client.state_lock);
    return 0;

cleanup:
    pending_block_list_reset(&client.pending_blocks);
    lantern_fork_choice_reset(&client.fork_choice);
    lantern_store_reset(&client.store);
    lantern_state_reset(&client.state);
    if (client.pending_lock_initialized)
    {
        pthread_mutex_destroy(&client.pending_lock);
        client.pending_lock_initialized = false;
    }
    if (client.state_lock_initialized)
    {
        pthread_mutex_destroy(&client.state_lock);
        client.state_lock_initialized = false;
    }
    return 1;
}

static int test_checkpoint_sync_anchor_checkpoint_restores(void)
{
    struct lantern_client client;
    char dir_template[] = "/tmp/lantern_checkpoint_anchor_restoreXXXXXX";
    char *data_dir = NULL;
    LanternCheckpoint remote_justified = {0};
    LanternCheckpoint remote_finalized = {0};
    LanternRoot canonical_state_root = {0};
    LanternRoot expected_anchor_root = {0};
    LanternRoot actual_head = {0};
    LanternSignedBlock persisted_anchor;
    int rc = 1;

    memset(&client, 0, sizeof(client));
    client.node_id = "checkpoint_anchor_restore";
    client.has_state = true;
    lantern_state_init(&client.state);
    lantern_store_init(&client.store);
    lantern_signed_block_with_attestation_init(&persisted_anchor);

    if (lantern_state_generate_genesis(&client.state, UINT64_C(1761717362), 5u) != 0)
    {
        fprintf(stderr, "failed to generate state for checkpoint anchor restore regression\n");
        goto cleanup;
    }

    uint8_t pubkeys[5u * LANTERN_VALIDATOR_PUBKEY_SIZE];
    fill_pubkeys(pubkeys, 5u);
    if (lantern_state_set_validator_pubkeys(&client.state, pubkeys, 5u) != 0)
    {
        fprintf(stderr, "failed to set validator pubkeys for checkpoint anchor restore regression\n");
        goto cleanup;
    }

    client.state.slot = 4612u;
    client.state.latest_block_header.slot = 4612u;
    client.state.latest_block_header.proposer_index = 2u;
    fill_root(&client.state.latest_block_header.parent_root, 0xF1u);

    fill_root(&remote_justified.root, 0xE5u);
    remote_justified.slot = 4597u;
    fill_root(&remote_finalized.root, 0x28u);
    remote_finalized.slot = 4592u;
    if (roots_equal(&remote_justified.root, &remote_finalized.root))
    {
        remote_finalized.root.bytes[0] ^= 0x01u;
    }
    client.state.latest_justified = remote_justified;
    client.state.latest_finalized = remote_finalized;

    char *temp_dir = mkdtemp(dir_template);
    if (!temp_dir)
    {
        fprintf(stderr, "failed to create temp data dir for checkpoint anchor restore regression\n");
        goto cleanup;
    }
    data_dir = strdup(temp_dir);
    if (!data_dir)
    {
        fprintf(stderr, "failed to duplicate temp data dir for checkpoint anchor restore regression\n");
        goto cleanup;
    }
    client.data_dir = data_dir;

    persisted_anchor.block.slot = client.state.latest_block_header.slot;
    persisted_anchor.block.proposer_index = client.state.latest_block_header.proposer_index;
    persisted_anchor.block.parent_root = client.state.latest_block_header.parent_root;
    if (lantern_aggregated_attestations_resize(
            &persisted_anchor.block.body.attestations,
            1u)
        != 0)
    {
        fprintf(stderr, "failed to build checkpoint anchor block body\n");
        goto cleanup;
    }
    LanternAggregatedAttestation *anchor_attestation =
        &persisted_anchor.block.body.attestations.data[0];
    if (lantern_bitlist_resize(&anchor_attestation->aggregation_bits, 5u) != 0
        || lantern_bitlist_set(&anchor_attestation->aggregation_bits, 2u, true) != 0)
    {
        fprintf(stderr, "failed to build checkpoint anchor aggregation bits\n");
        goto cleanup;
    }
    anchor_attestation->data.slot = client.state.latest_block_header.slot - 1u;
    anchor_attestation->data.head = remote_justified;
    anchor_attestation->data.target = remote_justified;
    anchor_attestation->data.source = remote_finalized;

    LanternRoot anchor_body_root = {0};
    if (lantern_hash_tree_root_block_body(&persisted_anchor.block.body, &anchor_body_root)
        != SSZ_SUCCESS)
    {
        fprintf(stderr, "failed to hash checkpoint anchor block body\n");
        goto cleanup;
    }
    client.state.latest_block_header.body_root = anchor_body_root;

    if (lantern_hash_tree_root_state(&client.state, &canonical_state_root) != SSZ_SUCCESS)
    {
        fprintf(stderr, "failed to hash checkpoint anchor restore regression state\n");
        goto cleanup;
    }
    persisted_anchor.block.state_root = canonical_state_root;

    if (lantern_hash_tree_root_block(&persisted_anchor.block, &expected_anchor_root)
        != SSZ_SUCCESS)
    {
        fprintf(stderr, "failed to hash checkpoint anchor restore regression anchor block\n");
        goto cleanup;
    }
    LanternBlockHeader expected_anchor_header = client.state.latest_block_header;
    expected_anchor_header.state_root = canonical_state_root;
    LanternRoot expected_header_root = {0};
    if (lantern_hash_tree_root_block_header(&expected_anchor_header, &expected_header_root)
        != SSZ_SUCCESS)
    {
        fprintf(stderr, "failed to hash checkpoint anchor restore regression header\n");
        goto cleanup;
    }
    if (!roots_equal(&expected_anchor_root, &expected_header_root))
    {
        fprintf(stderr, "checkpoint anchor block/header root mismatch in test setup\n");
        goto cleanup;
    }
    if (roots_equal(&expected_anchor_root, &remote_finalized.root))
    {
        fprintf(stderr, "test setup failed to create distinct checkpoint anchor root\n");
        goto cleanup;
    }
    if (lantern_storage_store_block_for_root(
            client.data_dir,
            &expected_anchor_root,
            &persisted_anchor)
        != 0)
    {
        fprintf(stderr, "failed to persist checkpoint anchor block for restore regression\n");
        goto cleanup;
    }

    if (initialize_fork_choice(&client) != LANTERN_CLIENT_OK)
    {
        fprintf(stderr, "initialize_fork_choice failed for checkpoint anchor restore regression\n");
        goto cleanup;
    }

    if (!roots_equal(&client.state.latest_justified.root, &remote_justified.root)
        || !roots_equal(&client.state.latest_finalized.root, &remote_finalized.root))
    {
        fprintf(stderr, "checkpoint anchor restore regression unexpectedly rewrote client state checkpoints\n");
        goto cleanup;
    }

    if (restore_persisted_blocks(&client) != LANTERN_CLIENT_OK)
    {
        fprintf(stderr, "restore_persisted_blocks failed for checkpoint anchor restore regression\n");
        goto cleanup;
    }

    if (lantern_fork_choice_current_head(&client.fork_choice, &actual_head) != 0)
    {
        fprintf(stderr, "failed to read fork choice head for checkpoint anchor restore regression\n");
        goto cleanup;
    }
    if (!roots_equal(&actual_head, &expected_anchor_root))
    {
        fprintf(stderr, "checkpoint anchor restore regression head mismatch\n");
        goto cleanup;
    }

    const LanternCheckpoint *store_justified =
        lantern_fork_choice_latest_justified(&client.fork_choice);
    const LanternCheckpoint *store_finalized =
        lantern_fork_choice_latest_finalized(&client.fork_choice);
    if (!store_justified || !store_finalized)
    {
        fprintf(stderr, "missing fork-choice checkpoints for checkpoint anchor restore regression\n");
        goto cleanup;
    }
    if (store_justified->slot != client.state.latest_block_header.slot
        || !roots_equal(&store_justified->root, &expected_anchor_root))
    {
        fprintf(stderr, "checkpoint anchor restore regression justified checkpoint mismatch\n");
        goto cleanup;
    }
    if (store_finalized->slot != client.state.latest_block_header.slot
        || !roots_equal(&store_finalized->root, &expected_anchor_root))
    {
        fprintf(stderr, "checkpoint anchor restore regression finalized checkpoint mismatch\n");
        goto cleanup;
    }

    LanternBlock child_block;
    memset(&child_block, 0, sizeof(child_block));
    child_block.slot = client.state.slot + 1u;
    if (lantern_proposer_for_slot(
            child_block.slot,
            client.state.config.num_validators,
            &child_block.proposer_index)
        != 0)
    {
        fprintf(stderr, "failed to compute child proposer for checkpoint anchor restore regression\n");
        goto cleanup;
    }
    child_block.parent_root = expected_anchor_root;
    lantern_block_body_init(&child_block.body);
    LanternRoot child_root = {0};
    if (lantern_hash_tree_root_block(&child_block, &child_root) != SSZ_SUCCESS)
    {
        fprintf(stderr, "failed to hash child block for checkpoint anchor restore regression\n");
        lantern_block_body_reset(&child_block.body);
        goto cleanup;
    }
    if (lantern_fork_choice_add_block_with_state(
            &client.fork_choice,
            &child_block,
            &remote_justified,
            &remote_finalized,
            &child_root,
            NULL)
        != 0)
    {
        fprintf(stderr, "fork choice rejected first post-anchor block for checkpoint anchor restore regression\n");
        lantern_block_body_reset(&child_block.body);
        goto cleanup;
    }
    lantern_block_body_reset(&child_block.body);

    const LanternState *cached_anchor_state =
        lantern_fork_choice_block_state(&client.fork_choice, &expected_anchor_root);
    if (!cached_anchor_state)
    {
        fprintf(stderr, "missing cached anchor state for checkpoint anchor restore regression\n");
        goto cleanup;
    }

    LanternState cached_anchor_clone;
    lantern_state_init(&cached_anchor_clone);
    if (lantern_state_clone(cached_anchor_state, &cached_anchor_clone) != 0)
    {
        fprintf(stderr, "failed to clone cached anchor state for checkpoint anchor restore regression\n");
        lantern_state_reset(&cached_anchor_clone);
        goto cleanup;
    }
    if (lantern_state_process_slot(&cached_anchor_clone) != 0)
    {
        fprintf(stderr, "failed to process cached anchor state slot for checkpoint anchor restore regression\n");
        lantern_state_reset(&cached_anchor_clone);
        goto cleanup;
    }
    LanternRoot cached_anchor_header_root = {0};
    if (lantern_hash_tree_root_block_header(
            &cached_anchor_clone.latest_block_header,
            &cached_anchor_header_root)
        != SSZ_SUCCESS)
    {
        fprintf(stderr, "failed to hash cached anchor header for checkpoint anchor restore regression\n");
        lantern_state_reset(&cached_anchor_clone);
        goto cleanup;
    }
    lantern_state_reset(&cached_anchor_clone);
    if (!roots_equal(&cached_anchor_header_root, &expected_anchor_root))
    {
        fprintf(stderr, "checkpoint anchor restore regression cached anchor state drifted\n");
        goto cleanup;
    }

    rc = 0;

cleanup:
    if (data_dir)
    {
        cleanup_storage_root_file(data_dir, "states", &expected_anchor_root, "ssz");
        cleanup_storage_root_file(data_dir, "states", &expected_anchor_root, "meta");
        cleanup_storage_root_file(data_dir, "blocks", &expected_anchor_root, "ssz");
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
    lantern_fork_choice_reset(&client.fork_choice);
    lantern_store_reset(&client.store);
    lantern_state_reset(&client.state);
    lantern_signed_block_with_attestation_reset(&persisted_anchor);
    return rc;
}

static int test_reqresp_status_uses_genesis_anchor_before_genesis(void)
{
    struct lantern_client client;
    memset(&client, 0, sizeof(client));
    client.node_id = "status_genesis_anchor_regression";
    client.has_state = true;
    lantern_state_init(&client.state);
    lantern_store_init(&client.store);
    lantern_fork_choice_init(&client.fork_choice);
    lantern_store_attach_fork_choice(&client.store, &client.fork_choice);

    int rc = 1;
    if (lantern_state_generate_genesis(&client.state, UINT64_C(4102444800), 4u) != 0)
    {
        fprintf(stderr, "failed to generate future-genesis state for status regression\n");
        goto cleanup;
    }

    uint8_t pubkeys[4u * LANTERN_VALIDATOR_PUBKEY_SIZE];
    fill_pubkeys(pubkeys, 4u);
    if (lantern_state_set_validator_pubkeys(&client.state, pubkeys, 4u) != 0)
    {
        fprintf(stderr, "failed to set validator pubkeys for status regression\n");
        goto cleanup;
    }

    if (lantern_store_prepare_validator_votes(&client.store, client.state.config.num_validators) != 0)
    {
        fprintf(stderr, "failed to prepare validator votes for status regression\n");
        goto cleanup;
    }

    if (initialize_fork_choice(&client) != LANTERN_CLIENT_OK)
    {
        fprintf(stderr, "initialize_fork_choice failed for status regression\n");
        goto cleanup;
    }

    const LanternRoot *anchor_root = lantern_fork_choice_anchor_root(&client.fork_choice);
    const LanternCheckpoint *store_finalized =
        lantern_fork_choice_latest_finalized(&client.fork_choice);
    if (!anchor_root || !store_finalized)
    {
        fprintf(stderr, "missing fork-choice anchor checkpoints for status regression\n");
        goto cleanup;
    }

    LanternStatusMessage status;
    memset(&status, 0, sizeof(status));
    if (reqresp_build_status(&client, &status) != LANTERN_CLIENT_OK)
    {
        fprintf(stderr, "reqresp_build_status failed for status regression\n");
        goto cleanup;
    }

    if (status.head.slot != 0u || status.finalized.slot != 0u)
    {
        fprintf(stderr, "genesis status should advertise slot zero checkpoints\n");
        goto cleanup;
    }
    if (lantern_root_is_zero(&status.head.root)
        || lantern_root_is_zero(&status.finalized.root))
    {
        fprintf(stderr, "genesis status should advertise the anchor root, not zero roots\n");
        goto cleanup;
    }
    if (!roots_equal(&status.head.root, anchor_root)
        || !roots_equal(&status.finalized.root, anchor_root))
    {
        fprintf(stderr, "genesis status roots did not follow fork-choice anchor\n");
        goto cleanup;
    }
    if (roots_equal(&status.finalized.root, &client.state.latest_finalized.root))
    {
        fprintf(stderr, "status finalized checkpoint incorrectly used zero state root\n");
        goto cleanup;
    }

    rc = 0;

cleanup:
    lantern_fork_choice_reset(&client.fork_choice);
    lantern_store_reset(&client.store);
    lantern_state_reset(&client.state);
    return rc;
}

static int test_checkpoint_validator_pubkeys_checked_and_preserved(void)
{
    enum { validator_count = 2u };
    struct lantern_client client;
    memset(&client, 0, sizeof(client));
    client.node_id = "checkpoint_pubkeys_checked";
    client.has_state = true;
    lantern_state_init(&client.state);

    uint8_t attestation_pubkeys[validator_count * LANTERN_VALIDATOR_PUBKEY_SIZE];
    uint8_t proposal_pubkeys[validator_count * LANTERN_VALIDATOR_PUBKEY_SIZE];
    fill_pubkeys(attestation_pubkeys, validator_count);
    memcpy(proposal_pubkeys, attestation_pubkeys, sizeof(proposal_pubkeys));
    for (size_t i = 0; i < sizeof(proposal_pubkeys); ++i)
    {
        proposal_pubkeys[i] ^= 0x80u;
    }

    client.genesis.chain_config.validator_count = validator_count;
    client.genesis.chain_config.validator_attestation_pubkeys = attestation_pubkeys;
    client.genesis.chain_config.validator_proposal_pubkeys = proposal_pubkeys;

    int rc = 1;
    LanternRoot root_before;
    LanternRoot root_after;
    if (lantern_state_generate_genesis(&client.state, UINT64_C(1761717362), validator_count) != 0
        || lantern_state_set_validator_pubkeys_dual(
               &client.state,
               attestation_pubkeys,
               proposal_pubkeys,
               validator_count)
               != 0
        || lantern_hash_tree_root_state(&client.state, &root_before) != SSZ_SUCCESS)
    {
        fprintf(stderr, "failed to build checkpoint pubkey regression state\n");
        goto cleanup;
    }

    if (lantern_client_validate_state_validator_pubkeys(&client, &client.state, "test")
        != LANTERN_CLIENT_OK)
    {
        fprintf(stderr, "matching checkpoint validator pubkeys were rejected\n");
        goto cleanup;
    }

    client.state.validators[1].proposal_pubkey[0] ^= 0x01u;
    if (lantern_client_validate_state_validator_pubkeys(&client, &client.state, "test")
        == LANTERN_CLIENT_OK)
    {
        fprintf(stderr, "checkpoint validator pubkey mismatch was accepted\n");
        goto cleanup;
    }
    client.state.validators[1].proposal_pubkey[0] ^= 0x01u;

    if (lantern_client_validate_state_validator_pubkeys(&client, &client.state, "test")
        != LANTERN_CLIENT_OK)
    {
        fprintf(stderr, "refresh rejected matching verified state pubkeys\n");
        goto cleanup;
    }

    if (lantern_hash_tree_root_state(&client.state, &root_after) != SSZ_SUCCESS
        || !roots_equal(&root_before, &root_after))
    {
        fprintf(stderr, "refresh changed verified state root\n");
        goto cleanup;
    }

    rc = 0;

cleanup:
    lantern_state_reset(&client.state);
    return rc;
}

static int test_checkpoint_sync_failure_aborts_without_genesis_fallback(void)
{
    char config_path[PATH_MAX] = {0};
    char validator_config_dir[PATH_MAX] = {0};
    char nodes_path[PATH_MAX] = {0};
    char data_template[] = "/tmp/lantern_checkpoint_abortXXXXXX";
    char *data_dir = NULL;
    int rc = 1;

    build_fixture_path(config_path, sizeof(config_path), "genesis/config.yaml");
    build_fixture_path(validator_config_dir, sizeof(validator_config_dir), "genesis");
    if (config_path[0] == '\0' || validator_config_dir[0] == '\0')
    {
        fprintf(stderr, "failed to build fixture paths for checkpoint abort regression\n");
        return 1;
    }

    if (write_empty_temp_file(
            nodes_path,
            sizeof(nodes_path),
            "lantern_checkpoint_abort_nodes")
        != 0)
    {
        fprintf(stderr, "failed to write nodes file for checkpoint abort regression\n");
        return 1;
    }

    data_dir = mkdtemp(data_template);
    if (!data_dir)
    {
        fprintf(stderr, "failed to create data dir for checkpoint abort regression\n");
        goto cleanup;
    }

    struct lantern_client_options options;
    lantern_client_options_init(&options);
    options.data_dir = data_dir;
    options.genesis_config_path = config_path;
    options.validator_config_dir = validator_config_dir;
    options.nodes_path = nodes_path;
    options.node_id = "checkpoint_abort_missing_validator";
    options.checkpoint_sync_url = "http://127.0.0.1:";

    struct lantern_client client;
    memset(&client, 0, sizeof(client));
    lantern_client_error init_rc = lantern_init(&client, &options);
    if (init_rc == LANTERN_CLIENT_OK)
    {
        fprintf(stderr, "checkpoint sync failure unexpectedly allowed startup\n");
        lantern_shutdown(&client);
        goto cleanup_options;
    }
    if (init_rc != LANTERN_CLIENT_ERR_NETWORK)
    {
        fprintf(
            stderr,
            "checkpoint sync failure returned %d, expected %d\n",
            (int)init_rc,
            (int)LANTERN_CLIENT_ERR_NETWORK);
        goto cleanup_options;
    }

    rc = 0;

cleanup_options:
    lantern_client_options_free(&options);
cleanup:
    if (nodes_path[0] != '\0')
    {
        cleanup_path(nodes_path);
    }
    cleanup_init_data_dir(data_dir);
    return rc;
}

int main(void)
{
    if (test_checkpoint_validator_pubkeys_checked_and_preserved() != 0)
    {
        return 1;
    }

    if (test_checkpoint_sync_failure_aborts_without_genesis_fallback() != 0)
    {
        return 1;
    }

    if (test_reqresp_status_uses_genesis_anchor_before_genesis() != 0)
    {
        return 1;
    }

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
    if (lantern_hash_tree_root_state(&client.state, &canonical_state_root) != SSZ_SUCCESS)
    {
        fprintf(stderr, "failed to hash canonical genesis state\n");
        lantern_state_reset(&client.state);
        return 1;
    }

    LanternBlockHeader expected_anchor_header = client.state.latest_block_header;
    expected_anchor_header.state_root = canonical_state_root;

    LanternRoot expected_anchor_root;
    if (lantern_hash_tree_root_block_header(&expected_anchor_header, &expected_anchor_root) != SSZ_SUCCESS)
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
     * Restart regression: initialize_fork_choice must seed checkpoint-synced
     * snapshots from the anchor block, not from embedded state checkpoints.
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
    if (lantern_hash_tree_root_state(&client.state, &restart_state_root) != SSZ_SUCCESS)
    {
        fprintf(stderr, "failed to hash restart regression state\n");
        lantern_state_reset(&client.state);
        return 1;
    }
    LanternBlockHeader restart_anchor_header = client.state.latest_block_header;
    restart_anchor_header.state_root = restart_state_root;
    LanternRoot expected_restart_anchor_root;
    if (lantern_hash_tree_root_block_header(&restart_anchor_header, &expected_restart_anchor_root) != SSZ_SUCCESS)
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
    if (store_justified->slot != client.state.latest_block_header.slot
        || !roots_equal(&store_justified->root, &expected_restart_anchor_root))
    {
        fprintf(stderr,
            "justified checkpoint should use the anchor root and anchor slot "
            "(got slot=%" PRIu64 " expected slot=%" PRIu64 ")\n",
            store_justified->slot, client.state.latest_block_header.slot);
        lantern_state_reset(&client.state);
        lantern_fork_choice_reset(&client.fork_choice);
        return 1;
    }
    if (store_finalized->slot != client.state.latest_block_header.slot
        || !roots_equal(&store_finalized->root, &expected_restart_anchor_root))
    {
        fprintf(stderr,
            "finalized checkpoint should use the anchor root and anchor slot "
            "(got slot=%" PRIu64 " expected slot=%" PRIu64 ")\n",
            store_finalized->slot, client.state.latest_block_header.slot);
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
    if (test_http_checkpoint_callbacks_do_not_take_state_lock() != 0)
    {
        lantern_state_reset(&client.state);
        lantern_fork_choice_reset(&client.fork_choice);
        return 1;
    }
    if (test_checkpoint_sync_parse_url_scheme_handling() != 0)
    {
        lantern_state_reset(&client.state);
        lantern_fork_choice_reset(&client.fork_choice);
        return 1;
    }
    if (test_pre_anchor_block_is_rejected_below_anchor_finalization() != 0)
    {
        lantern_state_reset(&client.state);
        lantern_fork_choice_reset(&client.fork_choice);
        return 1;
    }
    if (test_checkpoint_sync_anchor_checkpoint_restores() != 0)
    {
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
