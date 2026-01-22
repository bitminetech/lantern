#include <pthread.h>
#include <stdio.h>
#include <string.h>

#include "client_test_helpers.h"
#include "lantern/consensus/hash.h"

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
    lantern_block_body_init(&child.message.body);
    child.message.slot = 10;

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
        lantern_block_body_init(&extra.message.body);
        extra.message.slot = 20 + i;
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
            lantern_block_body_reset(&extra.message.body);
            rc = 1;
            goto cleanup;
        }
        lantern_block_body_reset(&extra.message.body);
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
    lantern_block_body_reset(&child.message.body);
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
    lantern_state_attach_fork_choice(&client.state, &client.fork_choice);

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
    lantern_block_body_init(&block.message.body);
    block.message.slot = 5;
    block.message.proposer_index = 0;
    client_test_fill_root(&block_root, 0x90);
    client_test_fill_root(&parent_root, 0x20);
    if (memcmp(parent_root.bytes, head_root.bytes, LANTERN_ROOT_SIZE) == 0) {
        parent_root.bytes[0] ^= 0xFFu;
    }
    block.message.parent_root = parent_root;
    client_test_fill_root(&block.message.state_root, 0x30);

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
    lantern_block_body_reset(&block.message.body);
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
    return rc;
}

int main(void) {
    if (test_pending_block_queue() != 0) {
        return 1;
    }
    if (test_import_block_parent_mismatch() != 0) {
        return 1;
    }
    puts("lantern_client_pending_test OK");
    return 0;
}
