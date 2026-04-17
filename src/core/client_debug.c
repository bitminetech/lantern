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

#include <string.h>

#include "lantern/support/log.h"

/* ============================================================================
 * Debug Vote/Block Recording
 * ============================================================================ */

/**
 * Debug API: Record a vote for testing.
 *
 * @param client       Client instance
 * @param vote         Vote to record
 * @param peer_id_text Peer ID text (may be NULL)
 * @return 0 on success
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM on NULL inputs
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
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    lantern_client_record_vote(client, vote, peer_id_text);
    return LANTERN_CLIENT_OK;
}

int lantern_client_debug_gossip_block(
    struct lantern_client *client,
    const LanternSignedBlock *block)
{
    if (!client || !block)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    return gossip_block_handler(block, NULL, NULL, 0, client);
}

int lantern_client_debug_gossip_vote(
    struct lantern_client *client,
    const LanternSignedVote *vote)
{
    if (!client || !vote)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    return gossip_vote_handler(vote, NULL, NULL, 0, client);
}

int lantern_client_debug_gossip_aggregated_attestation(
    struct lantern_client *client,
    const LanternSignedAggregatedAttestation *attestation)
{
    if (!client || !attestation)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    return gossip_aggregated_attestation_handler(attestation, NULL, NULL, 0, client);
}


/**
 * Debug API: Import a block for testing.
 *
 * @param client       Client instance
 * @param block        Block to import
 * @param block_root   Block root hash
 * @param peer_id_text Peer ID text (may be NULL)
 * @return 1 if imported
 * @return 0 if not imported
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM on NULL inputs
 *
 * @note Thread safety: Acquires appropriate locks internally
 */
int lantern_client_debug_import_block(
    struct lantern_client *client,
    const LanternSignedBlock *block,
    const LanternRoot *block_root,
    const char *peer_id_text)
{
    if (!client || !block || !block_root)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    return lantern_client_import_block(
               client,
               block,
               block_root,
               &(const struct lantern_log_metadata){
                   .validator = client->node_id,
                   .peer = peer_id_text},
               0,
               true,
               NULL,
               0)
        ? 1
        : 0;
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
    lantern_client_unlock_pending(mutable_client, locked);
    return count;
}


size_t lantern_client_pending_vote_count(const struct lantern_client *client)
{
    if (!client)
    {
        return 0;
    }
    struct lantern_client *mutable_client = (struct lantern_client *)client;
    bool locked = lantern_client_lock_state(mutable_client);
    size_t count = client->pending_gossip_votes.length;
    lantern_client_unlock_state(mutable_client, locked);
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
 * @return 0 on success
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM on NULL inputs
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
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    lantern_client_enqueue_pending_block(
        client,
        block,
        block_root,
        parent_root,
        peer_id_text,
        0,
        false);
    return LANTERN_CLIENT_OK;
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
 * @return 0 on success
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM on invalid inputs
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
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    if (out_peer_text && peer_text_len == 0)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    struct lantern_client *mutable_client = (struct lantern_client *)client;
    bool locked = lantern_client_lock_pending(mutable_client);
    if (index >= client->pending_blocks.length)
    {
        lantern_client_unlock_pending(mutable_client, locked);
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    LanternRoot root_copy;
    LanternRoot parent_copy;
    bool requested = false;
    char peer_copy[sizeof(((struct lantern_pending_block){0}).peer_text)];
    peer_copy[0] = '\0';

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
        out_peer_text[0] = '\0';
        if (peer_text_len > 1 && peer_copy[0])
        {
            strncpy(out_peer_text, peer_copy, peer_text_len - 1u);
            out_peer_text[peer_text_len - 1u] = '\0';
        }
    }
    return LANTERN_CLIENT_OK;
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
    pending_block_list_reset(&client->pending_blocks);
    lantern_client_unlock_pending(client, locked);
}


/**
 * Debug API: Set parent_requested flag on a pending block entry.
 *
 * @param client    Client instance
 * @param root      Block root to find
 * @param requested New value for parent_requested flag
 * @return 0 on success
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM on invalid inputs or when root is not found
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
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    bool locked = lantern_client_lock_pending(client);
    struct lantern_pending_block *entry = pending_block_list_find(&client->pending_blocks, root);
    if (entry)
    {
        entry->parent_requested = requested;
    }
    lantern_client_unlock_pending(client, locked);
    return entry ? LANTERN_CLIENT_OK : LANTERN_CLIENT_ERR_INVALID_PARAM;
}


/* ============================================================================
 * Debug Block Request APIs
 * ============================================================================ */

/**
 * Debug API: Simulate block request completion for testing.
 *
 * @param client       Client instance
 * @param peer_id      Peer ID text
 * @param request_root Root that was requested
 * @param outcome_code Outcome code (LANTERN_TEST_BLOCKS_REQUEST_*)
 * @return 0 on success
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM on invalid inputs
 *
 * @note Thread safety: Acquires appropriate locks internally
 */
int lantern_client_debug_on_blocks_request_complete(
    struct lantern_client *client,
    const char *peer_id,
    const LanternRoot *request_root,
    int outcome_code)
{
    if (!client || !peer_id || peer_id[0] == '\0' || !request_root)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    enum lantern_blocks_request_outcome outcome;
    switch (outcome_code)
    {
        case LANTERN_TEST_BLOCKS_REQUEST_SUCCESS:
            outcome = LANTERN_BLOCKS_REQUEST_SUCCESS;
            break;

        case LANTERN_TEST_BLOCKS_REQUEST_FAILED:
            outcome = LANTERN_BLOCKS_REQUEST_FAILED;
            break;

        case LANTERN_TEST_BLOCKS_REQUEST_ABORTED:
            outcome = LANTERN_BLOCKS_REQUEST_ABORTED;
            break;

        default:
            return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    lantern_client_on_blocks_request_complete(client, peer_id, request_root, outcome);
    return LANTERN_CLIENT_OK;
}
