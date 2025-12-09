/**
 * @file client_reqresp.c
 * @brief Request/response protocol callbacks and peer status handling
 *
 * @spec subspecs/networking/reqresp in tools/leanSpec
 *
 * Implements the reqresp protocol callbacks for status exchange and
 * blocks_by_root requests, plus peer status processing logic.
 *
 * Related files:
 * - client_reqresp_stream.c: Low-level stream I/O utilities
 * - client_reqresp_blocks.c: Block request operations
 *
 * @note Lock ordering (acquire in this order to prevent deadlocks):
 *       1. state_lock
 *       2. status_lock
 *       3. pending_lock
 *       4. validator_lock
 *       5. connection_lock
 *       6. peer_vote_lock
 */

#include "client_internal.h"

#include "lantern/consensus/hash.h"
#include "lantern/networking/messages.h"
#include "lantern/networking/reqresp_service.h"
#include "lantern/storage/storage.h"
#include "lantern/support/strings.h"
#include "lantern/support/log.h"

#include "libp2p/errors.h"
#include "peer_id/peer_id.h"

#include <inttypes.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>


/* ============================================================================
 * External Functions (from client_reqresp_blocks.c)
 * ============================================================================ */

extern int lantern_client_schedule_blocks_request(
    struct lantern_client *client,
    const char *peer_id_text,
    const LanternRoot *root,
    bool use_legacy);


/* ============================================================================
 * Forward Declarations
 * ============================================================================ */

static void lantern_client_on_peer_status(
    struct lantern_client *client,
    const LanternStatusMessage *peer_status,
    const char *peer_id);
static void lantern_client_adopt_peer_genesis(
    struct lantern_client *client,
    const LanternStatusMessage *peer_status,
    const char *peer_id_text);


/* ============================================================================
 * Reqresp Callbacks
 * ============================================================================ */

/**
 * Build a status message for reqresp protocol.
 *
 * @spec subspecs/networking/reqresp/message.py - Status message format
 *
 * Constructs a status message containing the client's current view:
 * - Finalized checkpoint (latest justified/finalized slot and root)
 * - Head checkpoint (current fork choice head or latest block header)
 *
 * @param context     Client instance
 * @param out_status  Output status message
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: This function is thread-safe
 */
int reqresp_build_status(void *context, LanternStatusMessage *out_status)
{
    if (!context || !out_status)
    {
        return -1;
    }
    struct lantern_client *client = context;
    memset(out_status, 0, sizeof(*out_status));
    if (!client->has_state)
    {
        return 0;
    }

    out_status->finalized = client->state.latest_finalized;

    bool head_set = false;
    if (client->has_fork_choice)
    {
        LanternRoot fork_head = {{0}};
        uint64_t fork_slot = 0;
        if (lantern_fork_choice_current_head(&client->fork_choice, &fork_head) == 0
            && lantern_fork_choice_block_info(&client->fork_choice, &fork_head, &fork_slot, NULL, NULL) == 0)
        {
            out_status->head.root = fork_head;
            out_status->head.slot = fork_slot;
            head_set = true;
        }
    }

    if (!head_set)
    {
        out_status->head.slot = client->state.latest_block_header.slot;
        if (lantern_hash_tree_root_block_header(&client->state.latest_block_header, &out_status->head.root) != 0)
        {
            memset(&out_status->head.root, 0, sizeof(out_status->head.root));
        }
    }
    return 0;
}


/**
 * Handle an incoming status message from a peer.
 *
 * @spec subspecs/networking/reqresp/message.py - Status protocol
 *
 * Processes a peer's status message and determines if synchronization
 * is needed. Delegates to internal peer status processor.
 *
 * @param context      Client instance
 * @param peer_status  Status message from peer
 * @param peer_id      Peer ID string
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: This function acquires status_lock
 */
int reqresp_handle_status(void *context, const LanternStatusMessage *peer_status, const char *peer_id)
{
    if (!context || !peer_status)
    {
        return -1;
    }
    struct lantern_client *client = context;
    char head_hex[2 * LANTERN_ROOT_SIZE + 3];
    char finalized_hex[2 * LANTERN_ROOT_SIZE + 3];
    format_root_hex(&peer_status->head.root, head_hex, sizeof(head_hex));
    format_root_hex(&peer_status->finalized.root, finalized_hex, sizeof(finalized_hex));

    lantern_log_info(
        "network",
        &(const struct lantern_log_metadata){
            .validator = client->node_id,
            .peer = peer_id},
        "peer status head_slot=%" PRIu64 " head_root=%s finalized_slot=%" PRIu64 " finalized_root=%s",
        peer_status->head.slot,
        head_hex[0] ? head_hex : "0x0",
        peer_status->finalized.slot,
        finalized_hex[0] ? finalized_hex : "0x0");
    lantern_client_on_peer_status(client, peer_status, peer_id);
    return 0;
}


/**
 * Handle a status request failure.
 *
 * @spec subspecs/networking/reqresp - Error handling
 *
 * Processes status request failures, tracking failure counts per peer
 * and adjusting log levels based on repeated failures. Handles specific
 * error types:
 * - Protocol negotiation failures (peer doesn't support protocol)
 * - Timeouts (peer unresponsive)
 * - Generic errors
 *
 * @param context  Client instance
 * @param peer_id  Peer ID string
 * @param error    Error code
 *
 * @note Thread safety: This function acquires status_lock
 */
void reqresp_status_failure(void *context, const char *peer_id, int error)
{
    if (!context)
    {
        return;
    }
    struct lantern_client *client = context;
    char peer_copy[sizeof(((struct lantern_peer_status_entry *)0)->peer_id)];
    memset(peer_copy, 0, sizeof(peer_copy));
    if (peer_id && *peer_id)
    {
        strncpy(peer_copy, peer_id, sizeof(peer_copy) - 1);
        peer_copy[sizeof(peer_copy) - 1] = '\0';
    }
    if (error == 0)
    {
        error = LIBP2P_ERR_INTERNAL;
    }

    if (peer_copy[0] != '\0')
    {
        lantern_client_status_request_failed(client, peer_copy);
    }

    bool first_failure = true;
    if (peer_copy[0] != '\0')
    {
        if (client->status_lock_initialized)
        {
            if (pthread_mutex_lock(&client->status_lock) == 0)
            {
                if (string_list_contains(&client->status_failure_peer_ids, peer_copy))
                {
                    first_failure = false;
                }
                else
                {
                    (void)lantern_string_list_append(&client->status_failure_peer_ids, peer_copy);
                }
                pthread_mutex_unlock(&client->status_lock);
            }
            else
            {
                if (string_list_contains(&client->status_failure_peer_ids, peer_copy))
                {
                    first_failure = false;
                }
                else
                {
                    (void)lantern_string_list_append(&client->status_failure_peer_ids, peer_copy);
                }
            }
        }
        else if (string_list_contains(&client->status_failure_peer_ids, peer_copy))
        {
            first_failure = false;
        }
        else
        {
            (void)lantern_string_list_append(&client->status_failure_peer_ids, peer_copy);
        }
    }

    const char *reason = connection_reason_text(error);
    struct lantern_log_metadata meta = {
        .validator = client->node_id,
        .peer = peer_copy[0] ? peer_copy : NULL,
    };

    if (error == LIBP2P_ERR_PROTO_NEGOTIATION_FAILED || error == LIBP2P_ERR_UNSUPPORTED)
    {
        if (first_failure)
        {
            lantern_log_info(
                "reqresp",
                &meta,
                "peer does not support %s error=%d (%s)",
                LANTERN_STATUS_PROTOCOL_ID,
                error,
                reason ? reason : "-");
        }
        else
        {
            lantern_log_trace(
                "reqresp",
                &meta,
                "peer still misses %s support error=%d (%s)",
                LANTERN_STATUS_PROTOCOL_ID,
                error,
                reason ? reason : "-");
        }
        return;
    }

    if (error == LIBP2P_ERR_TIMEOUT)
    {
        if (first_failure)
        {
            lantern_log_warn(
                "reqresp",
                &meta,
                "status request to peer timed out error=%d (%s)",
                error,
                reason ? reason : "-");
        }
        else
        {
            lantern_log_debug(
                "reqresp",
                &meta,
                "status request still timing out error=%d (%s)",
                error,
                reason ? reason : "-");
        }
        return;
    }

    if (first_failure)
    {
        lantern_log_warn(
            "reqresp",
            &meta,
            "status request failed error=%d (%s)",
            error,
            reason ? reason : "-");
    }
    else
    {
        lantern_log_debug(
            "reqresp",
            &meta,
            "status request still failing error=%d (%s)",
            error,
            reason ? reason : "-");
    }
}


/**
 * Collect blocks for a blocks_by_root request.
 *
 * @spec subspecs/networking/reqresp/message.py - BlocksByRoot response
 *
 * Retrieves blocks from storage matching the requested roots.
 * Returns blocks in the same order as the requested roots.
 *
 * @param context     Client instance
 * @param roots       Array of block roots to collect
 * @param root_count  Number of roots
 * @param out_blocks  Output response structure
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: This function is thread-safe
 */
int reqresp_collect_blocks(
    void *context,
    const LanternRoot *roots,
    size_t root_count,
    LanternBlocksByRootResponse *out_blocks)
{
    if (!context || !out_blocks)
    {
        return -1;
    }
    struct lantern_client *client = context;
    if (!client->data_dir)
    {
        return lantern_blocks_by_root_response_resize(out_blocks, 0);
    }
    int rc = lantern_storage_collect_blocks(client->data_dir, roots, root_count, out_blocks);
    if (rc != 0)
    {
        lantern_log_error(
            "reqresp",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to collect blocks from storage");
        return -1;
    }
    return 0;
}


/* ============================================================================
 * Peer Status Processing
 * ============================================================================ */

/**
 * Process a peer status message internally.
 *
 * @spec subspecs/forkchoice/store.py - Sync decision logic
 *
 * Determines if block synchronization is needed based on peer status:
 * 1. Checks if peer's head is known locally
 * 2. Compares peer's head slot with local slot
 * 3. Schedules blocks_by_root request if needed
 * 4. Implements exponential backoff for failed requests
 *
 * @param client       Client instance
 * @param peer_status  Status message from peer
 * @param peer_id      Peer ID string
 *
 * @note Thread safety: This function acquires status_lock
 */
static void lantern_client_on_peer_status(
    struct lantern_client *client,
    const LanternStatusMessage *peer_status,
    const char *peer_id)
{
    if (!client || !peer_status || !client->status_lock_initialized)
    {
        return;
    }
    if (!peer_id || *peer_id == '\0')
    {
        return;
    }
    if (lantern_root_is_zero(&peer_status->head.root))
    {
        return;
    }

    char head_hex[2 * LANTERN_ROOT_SIZE + 3];
    format_root_hex(&peer_status->head.root, head_hex, sizeof(head_hex));

    const size_t peer_cap = sizeof(((struct lantern_peer_status_entry *)0)->peer_id);
    char peer_copy[sizeof(((struct lantern_peer_status_entry *)0)->peer_id)];
    memset(peer_copy, 0, sizeof(peer_copy));
    strncpy(peer_copy, peer_id, peer_cap - 1);

    LanternRoot request_root = peer_status->head.root;
    uint64_t local_slot = 0;
    bool head_known = false;
    bool state_locked = lantern_client_lock_state(client);
    if (state_locked)
    {
        local_slot = client->state.slot;
        head_known = lantern_client_block_known_locked(client, &peer_status->head.root, NULL);
    }
    else if (client->has_state)
    {
        local_slot = client->state.slot;
        if (client->has_fork_choice)
        {
            uint64_t fork_slot = 0;
            if (lantern_fork_choice_block_info(&client->fork_choice, &peer_status->head.root, &fork_slot, NULL, NULL) == 0)
            {
                head_known = true;
            }
        }
    }
    lantern_client_unlock_state(client, state_locked);

    bool should_request = false;

    /* If we bootstrapped via genesis fallback and the peer advertises the genesis head,
       adopt the peer's head root as our anchor so that subsequent block requests use
       the correct root. */
    if (client->genesis_fallback_used && client->has_fork_choice && client->has_state
        && peer_status->head.slot == 0 && local_slot == 0 && !head_known)
    {
        lantern_client_adopt_peer_genesis(client, peer_status, peer_copy);
        head_known = true;
    }

    if (pthread_mutex_lock(&client->status_lock) != 0)
    {
        return;
    }

    struct lantern_peer_status_entry *entry = lantern_client_ensure_status_entry_locked(client, peer_copy);
    if (!entry)
    {
        pthread_mutex_unlock(&client->status_lock);
        return;
    }
    entry->status_request_inflight = false;
    lantern_client_status_request_update_locked(client, entry, peer_copy, -1, "complete");

    string_list_remove(&client->status_failure_peer_ids, peer_copy);

    bool had_status = entry->has_status;
    LanternStatusMessage previous_status = entry->status;
    bool head_changed = !had_status
        || previous_status.head.slot != peer_status->head.slot
        || memcmp(previous_status.head.root.bytes, peer_status->head.root.bytes, LANTERN_ROOT_SIZE) != 0;

    entry->status = *peer_status;
    entry->has_status = true;
    bool needs_block = !head_known;
    const char *needs_block_reason = NULL;
    if (!head_known)
    {
        needs_block_reason = "head unknown locally";
    }
    if (!needs_block && head_changed && peer_status->head.slot > local_slot)
    {
        needs_block = true;
        needs_block_reason = "remote head ahead of local slot";
    }
    struct lantern_log_metadata status_meta = {
        .validator = client->node_id,
        .peer = peer_copy[0] ? peer_copy : NULL,
    };
    if (needs_block)
    {
        lantern_log_info(
            "reqresp",
            &status_meta,
            "status needs block head_slot=%" PRIu64 " local_slot=%" PRIu64 " head_root=%s reason=%s",
            peer_status->head.slot,
            local_slot,
            head_hex[0] ? head_hex : "0x0",
            needs_block_reason ? needs_block_reason : "unspecified");
    }
    if (needs_block && !entry->requested_head)
    {
        uint64_t now_ms = monotonic_millis();
        uint64_t backoff_ms = blocks_request_backoff_ms(entry->consecutive_blocks_failures);
        if (entry->consecutive_blocks_failures == 0 && backoff_ms < LANTERN_BLOCKS_REQUEST_MIN_POLL_MS)
        {
            backoff_ms = LANTERN_BLOCKS_REQUEST_MIN_POLL_MS;
        }
        bool within_backoff = entry->last_blocks_request_ms != 0
            && now_ms < entry->last_blocks_request_ms + backoff_ms;
        if (!within_backoff)
        {
            entry->requested_head = true;
            entry->last_blocks_request_ms = now_ms;
            should_request = true;
        }
        else
        {
            uint64_t resume_ms = entry->last_blocks_request_ms + backoff_ms;
            uint64_t remaining_ms = resume_ms > now_ms ? (resume_ms - now_ms) : 0;
            lantern_log_debug(
                "reqresp",
                &(const struct lantern_log_metadata){
                    .validator = client->node_id,
                    .peer = peer_copy},
                "backing off blocks_by_root head=%s failures=%u remaining_ms=%" PRIu64,
                head_hex[0] ? head_hex : "0x0",
                entry->consecutive_blocks_failures,
                remaining_ms);
        }
    }
    else if (!needs_block)
    {
        lantern_log_trace(
            "reqresp",
            &(const struct lantern_log_metadata){
                .validator = client->node_id,
                .peer = peer_copy},
            "skipping blocks_by_root for known head slot=%" PRIu64 " root=%s",
            peer_status->head.slot,
            head_hex[0] ? head_hex : "0x0");
    }

    pthread_mutex_unlock(&client->status_lock);

    if (should_request)
    {
        if (lantern_client_schedule_blocks_request(client, peer_copy, &request_root, false) != 0)
        {
            lantern_client_on_blocks_request_complete(
                client,
                peer_copy,
                &request_root,
                LANTERN_BLOCKS_REQUEST_ABORTED);
        }
    }
}


/**
 * Adopt a peer's genesis root as our anchor.
 *
 * @spec subspecs/forkchoice/store.py - Store.get_forkchoice_store()
 *
 * Sets the peer's advertised genesis head as our fork choice anchor.
 * Used during bootstrap with genesis fallback when local genesis
 * state may not match the network's actual genesis block root.
 *
 * @param client        Client instance
 * @param peer_status   Peer status message
 * @param peer_id_text  Peer ID string for logging
 *
 * @note Thread safety: This function is thread-safe
 */
static void lantern_client_adopt_peer_genesis(
    struct lantern_client *client,
    const LanternStatusMessage *peer_status,
    const char *peer_id_text)
{
    if (!client || !peer_status || !client->has_fork_choice)
    {
        return;
    }

    LanternBlock anchor;
    memset(&anchor, 0, sizeof(anchor));
    anchor.slot = 0;
    anchor.proposer_index = 0;
    /* Use the peer's advertised head root as both state_root and hint so our fork-choice
       anchor matches the peer even if we cannot reproduce their SSZ state. */
    anchor.state_root = peer_status->head.root;
    /* empty body / zero attestations */
    LanternCheckpoint zero_cp = {.root = {{0}}, .slot = 0};

    if (lantern_fork_choice_set_anchor(
            &client->fork_choice,
            &anchor,
            &peer_status->finalized,
            &peer_status->finalized,
            &peer_status->head.root)
        != 0)
    {
        lantern_log_warn(
            "fork_choice",
            &(const struct lantern_log_metadata){.validator = client->node_id, .peer = peer_id_text},
            "failed to adopt peer genesis root");
        return;
    }

    (void)lantern_fork_choice_set_block_validator_count(
        &client->fork_choice,
        &peer_status->head.root,
        client->state.config.num_validators);
    client->genesis_fallback_used = false;

    char head_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    format_root_hex(&peer_status->head.root, head_hex, sizeof(head_hex));
    lantern_log_info(
        "fork_choice",
        &(const struct lantern_log_metadata){.validator = client->node_id, .peer = peer_id_text},
        "adopted peer genesis head_slot=0 root=%s",
        head_hex);
}


/**
 * Handle completion of a blocks request.
 *
 * @spec subspecs/networking/reqresp - Request lifecycle
 *
 * Updates peer tracking state after a blocks_by_root request completes:
 * - Resets request-in-flight flag
 * - Updates consecutive failure counter
 * - Clears parent_requested flag on pending blocks
 * - Triggers follow-up status request on success
 *
 * @param client        Client instance
 * @param peer_id       Peer ID string
 * @param request_root  Root that was requested
 * @param outcome       Request outcome
 *
 * @note Thread safety: This function acquires status_lock and pending_lock
 */
void lantern_client_on_blocks_request_complete(
    struct lantern_client *client,
    const char *peer_id,
    const LanternRoot *request_root,
    enum lantern_blocks_request_outcome outcome)
{
    if (!client || !peer_id || !client->status_lock_initialized)
    {
        return;
    }
    const size_t peer_cap = sizeof(((struct lantern_peer_status_entry *)0)->peer_id);
    uint32_t failure_count = 0;
    bool entry_found = false;
    if (pthread_mutex_lock(&client->status_lock) != 0)
    {
        return;
    }
    for (size_t i = 0; i < client->peer_status_count; ++i)
    {
        struct lantern_peer_status_entry *entry = &client->peer_status_entries[i];
        if (strncmp(entry->peer_id, peer_id, peer_cap) == 0)
        {
            entry->requested_head = false;
            switch (outcome)
            {
            case LANTERN_BLOCKS_REQUEST_SUCCESS:
                entry->consecutive_blocks_failures = 0;
                break;
            case LANTERN_BLOCKS_REQUEST_FAILED:
                if (entry->consecutive_blocks_failures < UINT32_MAX)
                {
                    entry->consecutive_blocks_failures += 1;
                }
                break;
            case LANTERN_BLOCKS_REQUEST_ABORTED:
                entry->last_blocks_request_ms = 0;
                break;
            default:
                break;
            }
            if (outcome != LANTERN_BLOCKS_REQUEST_ABORTED && entry->last_blocks_request_ms == 0)
            {
                entry->last_blocks_request_ms = monotonic_millis();
            }
            failure_count = entry->consecutive_blocks_failures;
            entry_found = true;
            break;
        }
    }
    pthread_mutex_unlock(&client->status_lock);

    char root_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    root_hex[0] = '\0';
    if (request_root)
    {
        format_root_hex(request_root, root_hex, sizeof(root_hex));
    }
    const char *outcome_text = "unknown";
    switch (outcome)
    {
    case LANTERN_BLOCKS_REQUEST_SUCCESS:
        outcome_text = "success";
        break;
    case LANTERN_BLOCKS_REQUEST_FAILED:
        outcome_text = "failed";
        break;
    case LANTERN_BLOCKS_REQUEST_ABORTED:
        outcome_text = "aborted";
        break;
    default:
        break;
    }
    lantern_log_info(
        "reqresp",
        &(const struct lantern_log_metadata){
            .validator = client->node_id,
            .peer = peer_id},
        "blocks_by_root complete outcome=%s root=%s entry_found=%s consecutive_failures=%" PRIu32,
        outcome_text,
        root_hex[0] ? root_hex : "0x0",
        entry_found ? "true" : "false",
        failure_count);

    if (request_root && !lantern_root_is_zero(request_root))
    {
        bool locked = lantern_client_lock_pending(client);
        if (locked)
        {
            for (size_t i = 0; i < client->pending_blocks.length; ++i)
            {
                struct lantern_pending_block *entry = &client->pending_blocks.items[i];
                if (memcmp(entry->parent_root.bytes, request_root->bytes, LANTERN_ROOT_SIZE) == 0)
                {
                    entry->parent_requested = false;
                }
            }
            lantern_client_unlock_pending(client, locked);
        }
        else
        {
            for (size_t i = 0; i < client->pending_blocks.length; ++i)
            {
                struct lantern_pending_block *entry = &client->pending_blocks.items[i];
                if (memcmp(entry->parent_root.bytes, request_root->bytes, LANTERN_ROOT_SIZE) == 0)
                {
                    entry->parent_requested = false;
                }
            }
        }
    }

    if (outcome == LANTERN_BLOCKS_REQUEST_SUCCESS && peer_id && peer_id[0] != '\0')
    {
        peer_id_t parsed_peer = {0};
        bool parsed = false;
        if (peer_id_create_from_string(peer_id, &parsed_peer) == PEER_ID_SUCCESS)
        {
            parsed = true;
        }
        request_status_now(client, parsed ? &parsed_peer : NULL, peer_id);
        if (parsed)
        {
            peer_id_destroy(&parsed_peer);
        }
    }
}
