/**
 * @file client_debug.c
 * @brief Debug and test API functions for the Lantern client
 *
 * Provides debug/test APIs for inspecting and manipulating client state
 * during unit and integration testing. These functions expose internal
 * state that should not be accessed in production.
 *
 * Related files:
 * - client.c: Main client initialization and lifecycle
 * - client_pending.c: Pending block management
 * - client_sync.c: Block/vote synchronization
 *
 * @note Thread safety: Functions that access shared state acquire appropriate
 *       locks as documented. See client_internal.h for lock ordering.
 */

#include "client_internal.h"

#include "lantern/support/log.h"

#include <stdlib.h>
#include <string.h>


/* ============================================================================
 * External Functions (from client_sync.c, client_reqresp.c)
 * ============================================================================ */

extern void lantern_client_record_vote(
    struct lantern_client *client,
    const LanternSignedVote *vote,
    const char *peer_id_text);

extern bool lantern_client_import_block(
    struct lantern_client *client,
    const LanternSignedBlock *block,
    const LanternRoot *block_root,
    const struct lantern_log_metadata *meta);

extern void lantern_client_enqueue_pending_block(
    struct lantern_client *client,
    const LanternSignedBlock *block,
    const LanternRoot *block_root,
    const LanternRoot *parent_root,
    const char *peer_id_text);

extern void lantern_client_on_blocks_request_complete(
    struct lantern_client *client,
    const char *peer_id,
    const LanternRoot *request_root,
    enum lantern_blocks_request_outcome outcome);


/* ============================================================================
 * Debug Vote/Block Recording
 * ============================================================================ */

/**
 * Debug API: Record a vote for testing.
 *
 * @param client       Client instance
 * @param vote         Vote to record
 * @param peer_id_text Peer ID text (may be NULL)
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: Acquires appropriate locks internally
 */
int lantern_client_debug_record_vote(
    struct lantern_client *client,
    const LanternSignedVote *vote,
    const char *peer_id_text)
{
    if (!client || !vote)
    {
        return -1;
    }
    lantern_client_record_vote(client, vote, peer_id_text);
    return 0;
}


/**
 * Debug API: Import a block for testing.
 *
 * @param client       Client instance
 * @param block        Block to import
 * @param block_root   Block root hash
 * @param peer_id_text Peer ID text (may be NULL)
 * @return 1 if imported, 0 if not imported, -1 on error
 *
 * @note Thread safety: Acquires appropriate locks internally
 */
int lantern_client_debug_import_block(
    struct lantern_client *client,
    const LanternSignedBlock *block,
    const LanternRoot *block_root,
    const char *peer_id_text)
{
    struct lantern_log_metadata meta = {
        .validator = client ? client->node_id : NULL,
        .peer = peer_id_text,
    };
    return lantern_client_import_block(client, block, block_root, &meta) ? 1 : 0;
}


/* ============================================================================
 * Debug Pending Block APIs
 * ============================================================================ */

/**
 * Get the count of pending blocks.
 *
 * @param client Client instance
 * @return Number of pending blocks
 *
 * @note Thread safety: Acquires pending_lock internally
 */
size_t lantern_client_pending_block_count(const struct lantern_client *client)
{
    if (!client)
    {
        return 0;
    }
    struct lantern_client *mutable_client = (struct lantern_client *)client;
    bool locked = lantern_client_lock_pending(mutable_client);
    size_t count = client->pending_blocks.length;
    if (locked)
    {
        lantern_client_unlock_pending(mutable_client, locked);
    }
    return count;
}


/**
 * Debug API: Enqueue a pending block for testing.
 *
 * @param client       Client instance
 * @param block        Block to enqueue
 * @param block_root   Block root hash
 * @param parent_root  Parent block root hash
 * @param peer_id_text Peer ID text (may be NULL)
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: Acquires pending_lock internally
 */
int lantern_client_debug_enqueue_pending_block(
    struct lantern_client *client,
    const LanternSignedBlock *block,
    const LanternRoot *block_root,
    const LanternRoot *parent_root,
    const char *peer_id_text)
{
    if (!client || !block || !block_root || !parent_root)
    {
        return -1;
    }
    lantern_client_enqueue_pending_block(client, block, block_root, parent_root, peer_id_text);
    return 0;
}


/**
 * Debug API: Get information about a pending block entry.
 *
 * @param client             Client instance
 * @param index              Index of pending block
 * @param out_root           Output: block root (may be NULL)
 * @param out_parent_root    Output: parent root (may be NULL)
 * @param out_parent_requested Output: whether parent was requested (may be NULL)
 * @param out_peer_text      Output: peer text buffer (may be NULL)
 * @param peer_text_len      Size of peer text buffer
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: Acquires pending_lock internally
 */
int lantern_client_debug_pending_entry(
    const struct lantern_client *client,
    size_t index,
    LanternRoot *out_root,
    LanternRoot *out_parent_root,
    bool *out_parent_requested,
    char *out_peer_text,
    size_t peer_text_len)
{
    if (!client)
    {
        return -1;
    }
    struct lantern_client *mutable_client = (struct lantern_client *)client;
    bool locked = lantern_client_lock_pending(mutable_client);
    if (locked && index >= client->pending_blocks.length)
    {
        lantern_client_unlock_pending(mutable_client, locked);
        return -1;
    }
    if (!locked && index >= client->pending_blocks.length)
    {
        return -1;
    }

    LanternRoot root_copy;
    LanternRoot parent_copy;
    bool requested = false;
    char peer_copy[128];
    peer_copy[0] = '\0';

    if (locked)
    {
        const struct lantern_pending_block *entry = &client->pending_blocks.items[index];
        root_copy = entry->root;
        parent_copy = entry->parent_root;
        requested = entry->parent_requested;
        if (entry->peer_text[0])
        {
            strncpy(peer_copy, entry->peer_text, sizeof(peer_copy) - 1u);
            peer_copy[sizeof(peer_copy) - 1u] = '\0';
        }
        lantern_client_unlock_pending(mutable_client, locked);
    }
    else
    {
        const struct lantern_pending_block *entry = &client->pending_blocks.items[index];
        if (!entry)
        {
            return -1;
        }
        root_copy = entry->root;
        parent_copy = entry->parent_root;
        requested = entry->parent_requested;
        if (entry->peer_text[0])
        {
            strncpy(peer_copy, entry->peer_text, sizeof(peer_copy) - 1u);
            peer_copy[sizeof(peer_copy) - 1u] = '\0';
        }
    }

    if (out_root)
    {
        *out_root = root_copy;
    }
    if (out_parent_root)
    {
        *out_parent_root = parent_copy;
    }
    if (out_parent_requested)
    {
        *out_parent_requested = requested;
    }
    if (out_peer_text && peer_text_len > 0)
    {
        if (peer_text_len == 1)
        {
            out_peer_text[0] = '\0';
        }
        else
        {
            if (peer_copy[0])
            {
                strncpy(out_peer_text, peer_copy, peer_text_len - 1u);
                out_peer_text[peer_text_len - 1u] = '\0';
            }
            else
            {
                out_peer_text[0] = '\0';
            }
        }
    }
    return 0;
}


/**
 * Debug API: Reset (clear) all pending blocks.
 *
 * @param client Client instance
 *
 * @note Thread safety: Acquires pending_lock internally
 */
void lantern_client_debug_pending_reset(struct lantern_client *client)
{
    if (!client)
    {
        return;
    }
    bool locked = lantern_client_lock_pending(client);
    if (locked)
    {
        pending_block_list_reset(&client->pending_blocks);
        lantern_client_unlock_pending(client, locked);
    }
    else
    {
        pending_block_list_reset(&client->pending_blocks);
    }
}


/**
 * Debug API: Set parent_requested flag on a pending block entry.
 *
 * @param client    Client instance
 * @param root      Block root to find
 * @param requested New value for parent_requested flag
 * @return 0 on success, -1 if not found or error
 *
 * @note Thread safety: Acquires pending_lock internally
 */
int lantern_client_debug_set_parent_requested(
    struct lantern_client *client,
    const LanternRoot *root,
    bool requested)
{
    if (!client || !root)
    {
        return -1;
    }
    bool locked = lantern_client_lock_pending(client);
    struct lantern_pending_block *entry = NULL;
    if (locked)
    {
        entry = pending_block_list_find(&client->pending_blocks, root);
        if (entry)
        {
            entry->parent_requested = requested;
        }
        lantern_client_unlock_pending(client, locked);
    }
    else
    {
        entry = pending_block_list_find(&client->pending_blocks, root);
        if (entry)
        {
            entry->parent_requested = requested;
        }
    }
    return entry ? 0 : -1;
}


/* ============================================================================
 * Debug Block Request APIs
 * ============================================================================ */

/**
 * Debug API: Enable/disable block requests for testing.
 *
 * @param client  Client instance
 * @param disable true to disable block requests
 *
 * @note Thread safety: No locking required (atomic flag)
 */
void lantern_client_debug_disable_block_requests(struct lantern_client *client, bool disable)
{
    if (!client)
    {
        return;
    }
    client->debug_disable_block_requests = disable ? true : false;
}


/**
 * Debug API: Simulate block request completion for testing.
 *
 * @param client       Client instance
 * @param peer_id      Peer ID text
 * @param request_root Root that was requested
 * @param outcome_code Outcome code (LANTERN_DEBUG_BLOCKS_REQUEST_*)
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: Acquires appropriate locks internally
 */
int lantern_client_debug_on_blocks_request_complete(
    struct lantern_client *client,
    const char *peer_id,
    const LanternRoot *request_root,
    int outcome_code)
{
    if (!client)
    {
        return -1;
    }
    enum lantern_blocks_request_outcome outcome;
    switch (outcome_code)
    {
    case LANTERN_DEBUG_BLOCKS_REQUEST_SUCCESS:
        outcome = LANTERN_BLOCKS_REQUEST_SUCCESS;
        break;
    case LANTERN_DEBUG_BLOCKS_REQUEST_FAILED:
        outcome = LANTERN_BLOCKS_REQUEST_FAILED;
        break;
    case LANTERN_DEBUG_BLOCKS_REQUEST_ABORTED:
        outcome = LANTERN_BLOCKS_REQUEST_ABORTED;
        break;
    default:
        return -1;
    }
    lantern_client_on_blocks_request_complete(client, peer_id, request_root, outcome);
    return 0;
}
