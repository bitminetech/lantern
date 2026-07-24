/**
 * @file client_reqresp.c
 * @brief Request/response protocol callbacks and peer status handling
 *
 * @spec subspecs/networking/reqresp in tools/leanSpec
 *
 * Implements the reqresp protocol callbacks for status exchange,
 * blocks_by_root, and blocks_by_range, plus peer status processing logic.
 *
 * @note Lock ordering (acquire in this order to prevent deadlocks):
 *       1. state_lock
 *       2. status_lock
 *       3. pending_lock
 *       4. validator_lock
 *       5. connection_lock
 */

#include "client_internal.h"
#include "client_network_internal.h"

#include <inttypes.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "lantern/consensus/hash.h"
#include "lantern/networking/messages.h"
#include "lantern/networking/reqresp_service.h"
#include "lantern/storage/storage.h"
#include "lantern/support/log.h"
#include "lantern/support/strings.h"

enum {
    ROOT_HEX_BUFFER_LEN = (LANTERN_ROOT_SIZE * 2u) + 3u,
};

struct lantern_async_block_import_job
{
    bool cache_aggregated_proofs_only;
    LanternSignedBlock block;
    LanternRoot block_root;
    char peer_id[128];
    struct lantern_async_block_import_job *next;
};


/* ============================================================================
 * Sync Logging
 * ============================================================================ */

static const uint64_t SYNC_PROGRESS_LOG_INTERVAL_MS = 5000u;

/* ============================================================================
 * Forward Declarations
 * ============================================================================ */

static void lantern_client_on_peer_status(
    struct lantern_client *client,
    const LanternStatusMessage *peer_status,
    const char *peer_id);

static void log_status_failure(
    const struct lantern_client *client,
    const char *peer_id_text,
    int error,
    bool first_failure);
static void peer_status_local_view(
    struct lantern_client *client,
    const LanternCheckpoint *head,
    LanternCheckpoint *out_local_head,
    bool *out_head_known);
static struct lantern_peer_status_entry *lantern_client_update_peer_status_entry_locked(
    struct lantern_client *client,
    const LanternStatusMessage *peer_status,
    const char *peer_id_text,
    bool *out_head_changed);
static void lantern_client_peer_status_update(
    struct lantern_client *client,
    const LanternStatusMessage *peer_status,
    const char *peer_id_text,
    const LanternCheckpoint *local_head,
    bool head_known);
static const char *lantern_blocks_request_outcome_text(enum lantern_blocks_request_outcome outcome);
static void reqresp_alias_anchor_checkpoint_if_unset(
    struct lantern_client *client,
    LanternStatusMessage *status);


/* ============================================================================
 * Reqresp Callbacks
 * ============================================================================ */

/**
 * @brief Log a status request failure with throttling.
 *
 * @param client         Client instance
 * @param peer_id_text   Peer ID string (may be empty)
 * @param error          Error code
 * @param first_failure  True if this is the first recorded failure
 */
static void log_status_failure(
    const struct lantern_client *client,
    const char *peer_id_text,
    int error,
    bool first_failure)
{
    const char *reason = connection_reason_text(error);
    struct lantern_log_metadata meta = {
        .validator = client ? client->node_id : NULL,
        .peer = peer_id_text && peer_id_text[0] ? peer_id_text : NULL,
    };

    if (error == LIBP2P_HOST_ERR_NEGOTIATION ||
        error == LIBP2P_HOST_ERR_UNSUPPORTED ||
        error == LIBP2P_HOST_ERR_NOT_FOUND)
    {
        if (first_failure)
        {
            lantern_log_info(
                "reqresp",
                &meta,
                "peer does not support %s error=%d (%s)",
                LANTERN_REQRESP_STATUS_PROTOCOL,
                error,
                reason ? reason : "-");
        }
        else
        {
            lantern_log_trace(
                "reqresp",
                &meta,
                "peer still misses %s support error=%d (%s)",
                LANTERN_REQRESP_STATUS_PROTOCOL,
                error,
                reason ? reason : "-");
        }
        return;
    }

    if (error == LIBP2P_HOST_ERR_WOULD_BLOCK)
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
 * @brief Determine local slot and whether a head root is known.
 *
 * @param client         Client instance
 * @param head           Head checkpoint to check
 * @param out_local_head Output local head checkpoint snapshot
 * @param out_head_known Output true if head is known locally
 *
 * @note Thread safety: This function may acquire state_lock
 */
static void peer_status_local_view(
    struct lantern_client *client,
    const LanternCheckpoint *head,
    LanternCheckpoint *out_local_head,
    bool *out_head_known)
{
    if (out_local_head)
    {
        *out_local_head = (LanternCheckpoint){0};
    }
    if (out_head_known)
    {
        *out_head_known = false;
    }

    if (!client || !head || !out_local_head || !out_head_known)
    {
        return;
    }

    bool state_locked = lantern_client_lock_state(client);
    if (client->state_lock_initialized && !state_locked)
    {
        return;
    }

    out_local_head->slot = client->state.validator_count > 0u
        ? client->state.latest_block_header.slot
        : 0u;
    if (client->store.block_len > 0u)
    {
        uint64_t fork_slot = 0;
        if (lantern_fork_choice_block_info(
                   &client->store,
                   &client->store.head,
                   &fork_slot,
                   NULL,
                   NULL)
                == 0)
        {
            out_local_head->root = client->store.head;
            out_local_head->slot = fork_slot;
        }
    }
    uint64_t known_head_slot = 0u;
    bool head_known = lantern_client_block_known_locked(client, &head->root, &known_head_slot)
        && known_head_slot == head->slot;
    lantern_client_unlock_state(client, state_locked);

    *out_head_known = head_known;
}

static void update_network_view_from_peer_status_locked(
    struct lantern_client *client,
    const LanternStatusMessage *peer_status,
    const LanternCheckpoint *local_head,
    bool head_known)
{
    if (!client || !peer_status)
    {
        return;
    }

    /* Advance monotonically by slot. At the same slot, replace the local head
     * once with an unresolved peer head, then keep that peer target stable. */
    bool current_is_local_head = local_head
        && !lantern_root_is_zero(&local_head->root)
        && client->network_view.head.slot == local_head->slot
        && lantern_root_equal(&client->network_view.head.root, &local_head->root);
    bool equal_slot_recovery = !head_known
        && peer_status->head.slot == client->network_view.head.slot
        && current_is_local_head;
    if (lantern_root_is_zero(&client->network_view.head.root)
        || peer_status->head.slot > client->network_view.head.slot
        || equal_slot_recovery)
    {
        client->network_view.head = peer_status->head;
    }

    if (lantern_root_is_zero(&client->network_view.finalized.root)
        || peer_status->finalized.slot > client->network_view.finalized.slot)
    {
        client->network_view.finalized = peer_status->finalized;
    }
}

static void format_duration_seconds(uint64_t seconds, char *out, size_t out_len)
{
    if (!out || out_len == 0)
    {
        return;
    }
    if (seconds == 0)
    {
        snprintf(out, out_len, "0s");
        return;
    }

    uint64_t hours = seconds / 3600u;
    uint64_t minutes = (seconds % 3600u) / 60u;
    uint64_t secs = seconds % 60u;

    if (hours > 0)
    {
        snprintf(out, out_len, "%" PRIu64 "h%02" PRIu64 "m%02" PRIu64 "s", hours, minutes, secs);
        return;
    }
    if (minutes > 0)
    {
        snprintf(out, out_len, "%" PRIu64 "m%02" PRIu64 "s", minutes, secs);
        return;
    }
    snprintf(out, out_len, "%" PRIu64 "s", secs);
}

static void maybe_log_sync_progress(
    struct lantern_client *client,
    uint64_t local_slot,
    const LanternStatusMessage *network_view,
    bool allow_sync_complete)
{
    if (!client || !network_view)
    {
        return;
    }

    bool has_network_head = !lantern_root_is_zero(&network_view->head.root);
    bool has_network_finalized = !lantern_root_is_zero(&network_view->finalized.root);
    uint64_t network_head_slot = network_view->head.slot;
    uint64_t network_finalized = network_view->finalized.slot;

    uint64_t now_ms = monotonic_millis();

    size_t pending = 0;
    bool has_orphans = false;
    uint64_t local_head_slot = local_slot;
    uint64_t local_finalized_slot = 0;
    bool network_head_known = false;
    {
        bool state_locked = lantern_client_lock_state(client);
        bool pending_locked = lantern_client_lock_pending(client);
        if (pending_locked)
        {
            pending = client->pending_blocks.length;
            for (size_t i = 0; i < client->pending_blocks.length; ++i)
            {
                const struct lantern_pending_block *entry = &client->pending_blocks.items[i];
                if (lantern_root_is_zero(&entry->parent_root))
                {
                    continue;
                }
                bool parent_cached = pending_block_list_find(
                    &client->pending_blocks,
                    &entry->parent_root)
                    != NULL;
                bool parent_known = false;
                if (!parent_cached && state_locked)
                {
                    parent_known = lantern_client_block_known_locked(
                        client,
                        &entry->parent_root,
                        NULL);
                }
                if (!parent_cached && !parent_known)
                {
                    has_orphans = true;
                    break;
                }
            }
        }
        if (state_locked && client->store.block_len > 0u)
        {
            uint64_t fork_slot = 0;
            if (lantern_fork_choice_block_info(
                    &client->store,
                    &client->store.head,
                    &fork_slot,
                    NULL,
                    NULL)
                == 0)
            {
                local_head_slot = fork_slot;
            }
            local_finalized_slot = client->store.latest_finalized.slot;
            uint64_t known_head_slot = 0u;
            network_head_known = has_network_head
                && lantern_client_block_known_locked(
                    client,
                    &network_view->head.root,
                    &known_head_slot)
                && known_head_slot == network_head_slot;
        }
        else if (state_locked && client->state.validator_count > 0u)
        {
            local_finalized_slot = client->state.latest_finalized.slot;
        }
        lantern_client_unlock_pending(client, pending_locked);
        lantern_client_unlock_state(client, state_locked);
    }

    if (!has_network_finalized && !has_network_head)
    {
        return;
    }

    bool was_idle = client->sync_state == LANTERN_SYNC_STATE_IDLE;
    if (was_idle)
    {
        lantern_client_set_sync_state_logged(client, LANTERN_SYNC_STATE_SYNCING, "first peer status");
    }

    bool behind_finalized = has_network_finalized && network_finalized > local_head_slot;
    bool finalized_caught_up =
        has_network_finalized && local_finalized_slot >= network_finalized;
    bool head_resolved = has_network_head
        && (network_head_slot <= local_finalized_slot || network_head_known);
    bool synced = has_network_finalized
        && !behind_finalized
        && finalized_caught_up
        && head_resolved
        && !has_orphans;
    bool syncing = !synced;

    struct lantern_log_metadata meta = {.validator = client->node_id};

    bool allow_complete = allow_sync_complete && client->sync_state == LANTERN_SYNC_STATE_SYNCING;
    if (!syncing)
    {
        if (!allow_complete)
        {
            return;
        }
        lantern_client_set_sync_state_logged(client, LANTERN_SYNC_STATE_SYNCED, "head ancestry resolved");
        if (client->sync_started_ms != 0u)
        {
            uint64_t target_slot =
                client->sync_target_slot != 0 ? client->sync_target_slot : network_finalized;
            uint64_t elapsed_s = 0;
            if (client->sync_started_ms != 0 && now_ms > client->sync_started_ms)
            {
                elapsed_s = (now_ms - client->sync_started_ms) / 1000u;
            }
            char duration[32];
            format_duration_seconds(elapsed_s, duration, sizeof(duration));
            lantern_log_info(
                "sync",
                &meta,
                "sync complete local_slot=%" PRIu64 " target_slot=%" PRIu64 " duration=%s",
                local_head_slot,
                target_slot,
                duration);
            client->sync_started_ms = 0;
            client->sync_last_log_ms = 0;
            client->sync_target_slot = 0;
        }
        return;
    }

    lantern_client_set_sync_state_logged(client, LANTERN_SYNC_STATE_SYNCING, "sync incomplete");
    if (client->sync_started_ms == 0u)
    {
        client->sync_started_ms = now_ms ? now_ms : 1u;
        client->sync_last_log_ms = 0;
        client->sync_target_slot = has_network_head ? network_head_slot : network_finalized;
        lantern_log_info(
            "sync",
            &meta,
            "sync starting local_slot=%" PRIu64 " target_slot=%" PRIu64 " pending=%zu",
            local_head_slot,
            client->sync_target_slot,
            pending);
    }

    if (client->sync_last_log_ms != 0
        && now_ms < client->sync_last_log_ms + SYNC_PROGRESS_LOG_INTERVAL_MS)
    {
        return;
    }

    uint64_t target_slot =
        client->sync_target_slot != 0
            ? client->sync_target_slot
            : (has_network_head ? network_head_slot : network_finalized);
    uint64_t remaining = (target_slot > local_head_slot) ? (target_slot - local_head_slot) : 0;

    if (pending > 0)
    {
        lantern_log_info(
            "sync",
            &meta,
            "sync progress local_slot=%" PRIu64 " target_slot=%" PRIu64
            " remaining=%" PRIu64 " pending=%zu",
            local_head_slot,
            target_slot,
            remaining,
            pending);
    }
    else
    {
        lantern_log_info(
            "sync",
            &meta,
            "sync progress local_slot=%" PRIu64 " target_slot=%" PRIu64 " remaining=%" PRIu64,
            local_head_slot,
            target_slot,
            remaining);
    }

    client->sync_last_log_ms = now_ms;
}

/**
 * @brief Update sync progress using latest peer status and local slot snapshot.
 *
 * @param client     Client instance
 * @param local_slot Local slot snapshot
 *
 * @note Thread safety: This function acquires status_lock.
 */
void lantern_client_update_sync_progress(
    struct lantern_client *client,
    uint64_t local_slot)
{
    if (!client || !client->status_lock_initialized)
    {
        return;
    }

    if (pthread_mutex_lock(&client->status_lock) != 0)
    {
        return;
    }

    LanternStatusMessage network_view = client->network_view;

    pthread_mutex_unlock(&client->status_lock);

    maybe_log_sync_progress(
        client,
        local_slot,
        &network_view,
        true);
}


/**
 * @brief Update stored peer status and mark status request complete.
 *
 * @param client           Client instance
 * @param peer_status      Peer status message
 * @param peer_id_text     Peer ID string for tracking/logging
 * @param out_head_changed Output whether the head changed since last status
 * @return Peer status entry on success, NULL on failure
 *
 * @note Thread safety: Caller must hold status_lock
 */
static struct lantern_peer_status_entry *lantern_client_update_peer_status_entry_locked(
    struct lantern_client *client,
    const LanternStatusMessage *peer_status,
    const char *peer_id_text,
    bool *out_head_changed)
{
    if (out_head_changed)
    {
        *out_head_changed = false;
    }

    if (!client || !peer_status || !peer_id_text)
    {
        return NULL;
    }

    struct lantern_peer_status_entry *entry =
        lantern_client_ensure_status_entry_locked(client, peer_id_text);
    if (!entry)
    {
        return NULL;
    }

    entry->status_request_inflight = false;
    entry->status_request_failed = false;

    bool head_changed = entry->last_status_ms == 0u
        || entry->status.head.slot != peer_status->head.slot
        || memcmp(
            entry->status.head.root.bytes,
            peer_status->head.root.bytes,
            LANTERN_ROOT_SIZE)
            != 0;

    entry->status = *peer_status;
    entry->last_status_ms = monotonic_millis();

    if (out_head_changed)
    {
        *out_head_changed = head_changed;
    }

    return entry;
}


/**
 * @brief Process peer status under status_lock and update sync progress.
 *
 * @param client       Client instance
 * @param peer_status  Peer status message
 * @param peer_id_text Peer ID string for tracking/logging
 * @param local_head   Local head checkpoint snapshot
 *
 * @note Thread safety: This function acquires status_lock
 */
static void lantern_client_peer_status_update(
    struct lantern_client *client,
    const LanternStatusMessage *peer_status,
    const char *peer_id_text,
    const LanternCheckpoint *local_head,
    bool head_known)
{
    if (!client || !peer_status || !peer_id_text || !local_head)
    {
        return;
    }

    if (pthread_mutex_lock(&client->status_lock) != 0)
    {
        return;
    }

    if (!lantern_client_update_peer_status_entry_locked(
            client,
            peer_status,
            peer_id_text,
            NULL))
    {
        pthread_mutex_unlock(&client->status_lock);
        return;
    }

    update_network_view_from_peer_status_locked(client, peer_status, local_head, head_known);
    LanternStatusMessage network_view = client->network_view;

    pthread_mutex_unlock(&client->status_lock);

    maybe_log_sync_progress(
        client,
        local_head->slot,
        &network_view,
        true);
}


/**
 * @brief Convert blocks request outcome to text.
 *
 * @param outcome Request outcome
 * @return Static string label
 */
static const char *lantern_blocks_request_outcome_text(enum lantern_blocks_request_outcome outcome)
{
    switch (outcome)
    {
    case LANTERN_BLOCKS_REQUEST_SUCCESS:
        return "success";
    case LANTERN_BLOCKS_REQUEST_FAILED:
        return "failed";
    case LANTERN_BLOCKS_REQUEST_EMPTY:
        return "empty";
    case LANTERN_BLOCKS_REQUEST_ABORTED:
        return "aborted";
    default:
        return "unknown";
    }
}


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
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM on NULL inputs
 *
 * @note Thread safety: This function is thread-safe
 */
int reqresp_build_status(void *context, LanternStatusMessage *out_status)
{
    if (!context || !out_status)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    struct lantern_client *client = context;
    memset(out_status, 0, sizeof(*out_status));
    if (client->state.validator_count == 0u)
    {
        return LANTERN_CLIENT_ERR_GENESIS;
    }

    out_status->finalized = client->state.latest_finalized;
    if (client->store.block_len > 0u
        && !lantern_root_is_zero(&client->store.latest_finalized.root))
    {
        out_status->finalized = client->store.latest_finalized;
    }

    bool head_set = false;
    if (client->store.block_len > 0u)
    {
        uint64_t fork_slot = 0;
        if (lantern_fork_choice_block_info(
                   &client->store,
                   &client->store.head,
                   &fork_slot,
                   NULL,
                   NULL)
                == 0)
        {
            out_status->head.root = client->store.head;
            out_status->head.slot = fork_slot;
            head_set = true;
        }
    }

    if (!head_set)
    {
        out_status->head.slot = client->state.latest_block_header.slot;
        if (lantern_hash_tree_root_block_header(
                &client->state.latest_block_header,
                &out_status->head.root)
            != SSZ_SUCCESS)
        {
            memset(&out_status->head.root, 0, sizeof(out_status->head.root));
        }
    }
    reqresp_alias_anchor_checkpoint_if_unset(client, out_status);
    return LANTERN_CLIENT_OK;
}


static void reqresp_alias_anchor_checkpoint_if_unset(
    struct lantern_client *client,
    LanternStatusMessage *status)
{
    if (!client || !status || client->store.block_len == 0u)
    {
        return;
    }

    if (status->head.slot == client->store.anchor.slot
        && lantern_root_is_zero(&status->head.root))
    {
        status->head.root = client->store.anchor.root;
    }
    if (status->finalized.slot == client->store.anchor.slot
        && lantern_root_is_zero(&status->finalized.root))
    {
        status->finalized.root = client->store.anchor.root;
    }
}


/**
 * Handle an incoming status message from a peer.
 *
 * @spec subspecs/networking/reqresp/message.py - Status protocol
 *
 * Processes a peer's status message, updates peer tracking, records
 * sync progress, and routes ahead peers into forward range catch-up.
 *
 * @param context      Client instance
 * @param peer_status  Status message from peer
 * @param peer_id      Peer ID string
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM on NULL inputs
 *
 * @note Thread safety: This function acquires status_lock
 */
int reqresp_handle_status(
    void *context,
    const LanternStatusMessage *peer_status,
    const char *peer_id)
{
    if (!context || !peer_status)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    struct lantern_client *client = context;
    char head_hex[2 * LANTERN_ROOT_SIZE + 3];
    char finalized_hex[2 * LANTERN_ROOT_SIZE + 3];
    format_root_hex(&peer_status->head.root, head_hex, sizeof(head_hex));
    format_root_hex(&peer_status->finalized.root, finalized_hex, sizeof(finalized_hex));

    lantern_log_debug(
        "network",
        &(const struct lantern_log_metadata){
            .validator = client->node_id,
            .peer = peer_id},
        "peer status head_slot=%" PRIu64 " head_root=%s "
        "finalized_slot=%" PRIu64 " finalized_root=%s",
        peer_status->head.slot,
        head_hex[0] ? head_hex : "0x0",
        peer_status->finalized.slot,
        finalized_hex[0] ? finalized_hex : "0x0");
    lantern_client_on_peer_status(client, peer_status, peer_id);
    return LANTERN_CLIENT_OK;
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
    (void)lantern_string_copy(peer_copy, sizeof(peer_copy), peer_id);
    if (error == 0)
    {
        error = LIBP2P_HOST_ERR_INTERNAL;
    }

    bool first_failure = peer_copy[0] == '\0'
        || lantern_client_status_request_failed(client, peer_copy);
    log_status_failure(client, peer_copy, error, first_failure);

    if (peer_copy[0] != '\0' && error == LANTERN_REQRESP_ERR_STREAM_WRITE
        && !lantern_client_is_peer_connected(client, peer_copy))
    {
        struct lantern_peer_id peer;
        if (lantern_peer_id_from_text(peer_copy, &peer) == 0)
        {
            redial_peer(client, &peer);
        }
    }

    if (peer_copy[0] != '\0' && first_failure
        && lantern_client_is_peer_connected(client, peer_copy))
    {
        request_status_now(client, NULL, peer_copy);
    }
}


static bool signed_block_matches_root(
    const LanternSignedBlock *block,
    const LanternRoot *root)
{
    if (!block || !root)
    {
        return false;
    }
    LanternRoot block_root = {0};
    if (lantern_hash_tree_root_block(&block->block, &block_root) != SSZ_SUCCESS)
    {
        return false;
    }
    return memcmp(block_root.bytes, root->bytes, LANTERN_ROOT_SIZE) == 0;
}

static int signed_block_list_append_copy(
    LanternSignedBlockList *list,
    const LanternSignedBlock *block)
{
    if (!list || !block)
    {
        return -1;
    }

    size_t previous_len = list->length;
    if (lantern_signed_block_list_resize(list, previous_len + 1u) != 0)
    {
        return -1;
    }

    LanternSignedBlock *dst = &list->blocks[previous_len];
    if (clone_signed_block(block, dst) != 0)
    {
        lantern_signed_block_reset(dst);
        (void)lantern_signed_block_list_resize(list, previous_len);
        return -1;
    }

    return 0;
}

static const LanternSignedBlock *find_block_by_root(
    const LanternSignedBlockList *list,
    const LanternRoot *root)
{
    if (!list || !root)
    {
        return NULL;
    }

    for (size_t i = 0; i < list->length; ++i)
    {
        if (signed_block_matches_root(&list->blocks[i], root))
        {
            return &list->blocks[i];
        }
    }

    return NULL;
}

static bool append_pending_block_for_root(
    struct lantern_client *client,
    const LanternRoot *root,
    LanternSignedBlockList *out_blocks)
{
    if (!client || !root || !out_blocks)
    {
        return false;
    }

    bool appended = false;
    bool pending_locked = lantern_client_lock_pending(client);
    if (!pending_locked)
    {
        return false;
    }

    struct lantern_pending_block *pending = pending_block_list_find(
        &client->pending_blocks,
        root);
    if (pending)
    {
        appended = signed_block_list_append_copy(out_blocks, &pending->block) == 0;
    }

    lantern_client_unlock_pending(client, pending_locked);
    return appended;
}

static bool block_response_was_accepted(
    struct lantern_client *client,
    const LanternRoot *block_root,
    bool *out_pending,
    bool *out_known)
{
    if (out_pending)
    {
        *out_pending = false;
    }
    if (out_known)
    {
        *out_known = false;
    }
    if (!client || !block_root)
    {
        return false;
    }

    bool pending_locked = lantern_client_lock_pending(client);
    if (pending_locked)
    {
        bool pending = pending_block_list_find(&client->pending_blocks, block_root) != NULL;
        lantern_client_unlock_pending(client, pending_locked);
        if (pending)
        {
            if (out_pending)
            {
                *out_pending = true;
            }
            return true;
        }
    }

    bool state_locked = lantern_client_lock_state(client);
    if (!state_locked)
    {
        return false;
    }
    bool known = lantern_client_block_known_locked(client, block_root, NULL);
    lantern_client_unlock_state(client, state_locked);
    if (known && out_known)
    {
        *out_known = true;
    }
    return known;
}

static bool block_response_is_pre_finalized(
    struct lantern_client *client,
    uint64_t block_slot)
{
    bool state_locked = lantern_client_lock_state(client);
    if (!state_locked)
    {
        return false;
    }
    bool pre_finalized = client->store.block_len > 0u
        && block_slot <= client->store.latest_finalized.slot;
    lantern_client_unlock_state(client, state_locked);
    return pre_finalized;
}

/* Request ID zero is the synchronous/untracked path used by local callers.
 * Network responses must still belong to the exact active request and root. */
static bool block_response_request_context(
    struct lantern_client *client,
    const LanternRoot *block_root,
    uint64_t block_slot,
    uint64_t request_id,
    bool *out_active)
{
    if (!client || !block_root || !out_active)
    {
        return false;
    }
    *out_active = request_id == 0u;
    if (request_id == 0u)
    {
        return true;
    }
    if (!client->status_lock_initialized || pthread_mutex_lock(&client->status_lock) != 0)
    {
        return false;
    }
    for (size_t i = 0; i < client->active_blocks_request_count; ++i)
    {
        const struct lantern_active_blocks_request *request =
            &client->active_blocks_requests[i];
        if (request->request_id != request_id)
        {
            continue;
        }
        for (size_t j = 0; j < request->root_count; ++j)
        {
            if (memcmp(request->roots[j].bytes, block_root->bytes, LANTERN_ROOT_SIZE) == 0)
            {
                *out_active = true;
                break;
            }
        }
        break;
    }
    if (!*out_active && client->range_sync.request_id == request_id)
    {
        if (block_slot < client->range_sync.request_start_slot
            || block_slot - client->range_sync.request_start_slot
                >= client->range_sync.request_count)
        {
            pthread_mutex_unlock(&client->status_lock);
            return false;
        }
        *out_active = true;
    }
    pthread_mutex_unlock(&client->status_lock);
    return true;
}

static uint32_t block_response_backfill_depth(
    struct lantern_client *client,
    const LanternRoot *block_root)
{
    if (!client || !block_root)
    {
        return 0u;
    }

    uint32_t depth = 0u;
    bool locked = lantern_client_lock_pending(client);
    if (!locked)
    {
        return depth;
    }
    for (size_t i = 0; i < client->pending_blocks.length; ++i)
    {
        const struct lantern_pending_block *entry = &client->pending_blocks.items[i];
        if (memcmp(entry->parent_root.bytes, block_root->bytes, LANTERN_ROOT_SIZE) != 0)
        {
            continue;
        }
        uint32_t parent_depth = entry->backfill_depth < LANTERN_MAX_BACKFILL_DEPTH
            ? entry->backfill_depth + 1u
            : LANTERN_MAX_BACKFILL_DEPTH;
        if (parent_depth > depth)
        {
            depth = parent_depth;
        }
    }

    lantern_client_unlock_pending(client, locked);
    return depth;
}


static int import_block_response_now(
    struct lantern_client *client,
    const LanternSignedBlock *block,
    const LanternRoot *block_root,
    const char *peer_id)
{
    struct lantern_log_metadata meta = {
        .validator = client ? client->node_id : NULL,
        .peer = peer_id && peer_id[0] ? peer_id : NULL,
        .has_slot = block != NULL,
        .slot = block ? block->block.slot : 0u,
    };
    if (!client || !block || !block_root)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    char root_hex[ROOT_HEX_BUFFER_LEN];
    format_root_hex(block_root, root_hex, sizeof(root_hex));
    uint32_t backfill_depth = block_response_backfill_depth(client, block_root);
    bool imported = lantern_client_import_block(
        client,
        block,
        block_root,
        &meta,
        backfill_depth,
        true);
    bool pending = false;
    bool known = false;
    bool accepted = imported || block_response_was_accepted(client, block_root, &pending, &known);
    if (accepted)
    {
        if (known && !imported)
        {
            lantern_log_debug(
                "backfill",
                &meta,
                "slot %" PRIu64 ", %s, response duplicate",
                block->block.slot,
                root_hex[0] ? root_hex : "0x0");
        }
        else
        {
            lantern_log_info(
                "backfill",
                &meta,
                "slot %" PRIu64 ", %s, response %s",
                block->block.slot,
                root_hex[0] ? root_hex : "0x0",
                imported ? "imported" : (pending ? "queued" : "accepted"));
        }
        return LANTERN_CLIENT_OK;
    }
    if (block_response_is_pre_finalized(client, block->block.slot))
    {
        lantern_log_debug(
            "backfill",
            &meta,
            "slot %" PRIu64 ", %s, response pre-finalized",
            block->block.slot,
            root_hex[0] ? root_hex : "0x0");
        return LANTERN_CLIENT_OK;
    }

    lantern_log_warn(
        "backfill",
        &meta,
        "slot %" PRIu64 ", %s, response rejected",
        block->block.slot,
        root_hex[0] ? root_hex : "0x0");
    return LANTERN_CLIENT_ERR_RUNTIME;
}

static void block_import_job_free(struct lantern_async_block_import_job *job)
{
    if (!job)
    {
        return;
    }
    lantern_signed_block_reset(&job->block);
    free(job);
}

static void *block_import_worker_main(void *arg)
{
    struct lantern_client *client = (struct lantern_client *)arg;
    if (!client)
    {
        return NULL;
    }

    for (;;)
    {
        if (pthread_mutex_lock(&client->block_import_lock) != 0)
        {
            break;
        }
        while (!client->block_import_stop && !client->block_import_head)
        {
            (void)pthread_cond_wait(&client->block_import_cond, &client->block_import_lock);
        }
        struct lantern_async_block_import_job *job = client->block_import_head;
        if (!job)
        {
            pthread_mutex_unlock(&client->block_import_lock);
            break;
        }
        client->block_import_head = job->next;
        if (!client->block_import_head)
        {
            client->block_import_tail = NULL;
        }
        bool stopping = client->block_import_stop;
        pthread_mutex_unlock(&client->block_import_lock);

        int rc = LANTERN_CLIENT_OK;
        if (job->cache_aggregated_proofs_only)
        {
            if (!stopping)
            {
                lantern_client_cache_block_aggregated_proofs(client, &job->block);
            }
        }
        else
        {
            rc = import_block_response_now(
                client,
                &job->block,
                &job->block_root,
                job->peer_id);
        }
        if (rc != LANTERN_CLIENT_OK)
        {
            lantern_log_warn(
                "reqresp",
                &(const struct lantern_log_metadata){
                    .validator = client->node_id,
                    .peer = job->peer_id[0] ? job->peer_id : NULL,
                    .has_slot = true,
                    .slot = job->block.block.slot,
                },
                "async blocks_by_root import rejected");
        }
        block_import_job_free(job);
    }

    return NULL;
}

lantern_client_error lantern_client_block_importer_start(struct lantern_client *client)
{
    if (!client)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    if (client->block_import_sync_initialized)
    {
        return LANTERN_CLIENT_OK;
    }
    if (pthread_mutex_init(&client->block_import_lock, NULL) != 0)
    {
        return LANTERN_CLIENT_ERR_RUNTIME;
    }
    if (pthread_cond_init(&client->block_import_cond, NULL) != 0)
    {
        pthread_mutex_destroy(&client->block_import_lock);
        return LANTERN_CLIENT_ERR_RUNTIME;
    }
    client->block_import_sync_initialized = true;
    client->block_import_stop = false;
    if (pthread_create(&client->block_import_thread, NULL, block_import_worker_main, client) != 0)
    {
        client->block_import_stop = true;
        pthread_cond_destroy(&client->block_import_cond);
        pthread_mutex_destroy(&client->block_import_lock);
        client->block_import_sync_initialized = false;
        return LANTERN_CLIENT_ERR_RUNTIME;
    }
    return LANTERN_CLIENT_OK;
}

void lantern_client_block_importer_stop(struct lantern_client *client)
{
    if (!client || !client->block_import_sync_initialized)
    {
        return;
    }
    if (pthread_mutex_lock(&client->block_import_lock) == 0)
    {
        client->block_import_stop = true;
        pthread_cond_broadcast(&client->block_import_cond);
        pthread_mutex_unlock(&client->block_import_lock);
    }
    pthread_join(client->block_import_thread, NULL);

    struct lantern_async_block_import_job *job = client->block_import_head;
    while (job)
    {
        struct lantern_async_block_import_job *next = job->next;
        block_import_job_free(job);
        job = next;
    }
    client->block_import_head = NULL;
    client->block_import_tail = NULL;

    pthread_cond_destroy(&client->block_import_cond);
    pthread_mutex_destroy(&client->block_import_lock);
    client->block_import_sync_initialized = false;
    client->block_import_stop = true;
}

static int enqueue_block_import_job(
    struct lantern_client *client,
    struct lantern_async_block_import_job *job)
{
    if (!client || !job || !client->block_import_sync_initialized)
    {
        return -1;
    }
    if (pthread_mutex_lock(&client->block_import_lock) != 0)
    {
        return -1;
    }
    if (client->block_import_stop)
    {
        pthread_mutex_unlock(&client->block_import_lock);
        return -1;
    }

    /* Keep required req/resp imports ahead of optional proof-recovery work. */
    job->next = NULL;
    if (!job->cache_aggregated_proofs_only && client->block_import_head)
    {
        struct lantern_async_block_import_job *previous = NULL;
        struct lantern_async_block_import_job *queued = client->block_import_head;
        while (queued && !queued->cache_aggregated_proofs_only)
        {
            previous = queued;
            queued = queued->next;
        }
        if (queued)
        {
            job->next = queued;
            if (previous)
            {
                previous->next = job;
            }
            else
            {
                client->block_import_head = job;
            }
        }
        else
        {
            client->block_import_tail->next = job;
            client->block_import_tail = job;
        }
    }
    else if (client->block_import_tail)
    {
        client->block_import_tail->next = job;
        client->block_import_tail = job;
    }
    else
    {
        client->block_import_head = job;
        client->block_import_tail = job;
    }
    pthread_cond_signal(&client->block_import_cond);
    pthread_mutex_unlock(&client->block_import_lock);
    return 0;
}

int lantern_client_enqueue_block_aggregated_proofs(
    struct lantern_client *client,
    const LanternSignedBlock *block)
{
    if (!client || !block)
    {
        return -1;
    }
    struct lantern_async_block_import_job *job = calloc(1u, sizeof(*job));
    if (!job)
    {
        return -1;
    }
    job->cache_aggregated_proofs_only = true;
    if (clone_signed_block(block, &job->block) != 0
        || enqueue_block_import_job(client, job) != 0)
    {
        block_import_job_free(job);
        return -1;
    }
    return 0;
}

/**
 * Collect blocks for a blocks_by_root request.
 *
 * @spec subspecs/networking/reqresp/message.py - BlocksByRoot streamed SignedBlock chunks
 *
 * Retrieves blocks from storage matching the requested roots.
 * Returns blocks in the same order as the requested roots.
 *
 * @param context     Client instance
 * @param roots       Array of block roots to collect
 * @param root_count  Number of roots
 * @param out_blocks  Output response structure
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM on NULL inputs
 * @return LANTERN_CLIENT_ERR_ALLOC on response allocation failure
 * @return LANTERN_CLIENT_ERR_STORAGE on storage retrieval failure
 *
 * @note Thread safety: This function is thread-safe
 */
int reqresp_collect_blocks(
    void *context,
    const LanternRoot *roots,
    size_t root_count,
    LanternSignedBlockList *out_blocks)
{
    if (!context || !out_blocks || (!roots && root_count > 0))
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    struct lantern_client *client = context;
    if (lantern_signed_block_list_resize(out_blocks, 0) != 0)
    {
        return LANTERN_CLIENT_ERR_ALLOC;
    }
    if (root_count == 0)
    {
        return LANTERN_CLIENT_OK;
    }

    LanternSignedBlockList storage_blocks = {0};
    if (client->storage.backend)
    {
        if (lantern_storage_collect_blocks(
                &client->storage,
                roots,
                root_count,
                &storage_blocks)
            != 0)
        {
            lantern_signed_block_list_reset(&storage_blocks);
            lantern_log_error(
                "reqresp",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "failed to collect blocks from storage");
            return LANTERN_CLIENT_ERR_STORAGE;
        }
    }

    size_t storage_hits = 0;
    size_t pending_hits = 0;
    for (size_t i = 0; i < root_count; ++i)
    {
        const LanternSignedBlock *stored = find_block_by_root(&storage_blocks, &roots[i]);
        if (stored)
        {
            if (signed_block_list_append_copy(out_blocks, stored) != 0)
            {
                lantern_signed_block_list_reset(&storage_blocks);
                return LANTERN_CLIENT_ERR_ALLOC;
            }
            storage_hits += 1u;
            continue;
        }

        if (append_pending_block_for_root(client, &roots[i], out_blocks))
        {
            pending_hits += 1u;
        }
    }

    lantern_signed_block_list_reset(&storage_blocks);
    lantern_log_debug(
        "reqresp",
        &(const struct lantern_log_metadata){.validator = client->node_id},
        "blocks_by_root collect roots=%zu served=%zu storage_hits=%zu pending_hits=%zu",
        root_count,
        out_blocks->length,
        storage_hits,
        pending_hits);

    return LANTERN_CLIENT_OK;
}

/**
 * Collect canonical blocks for a BlocksByRange request.
 *
 * @spec tools/leanSpec/src/lean_spec/node/networking/reqresp/handler.py
 *       handle_blocks_by_range: stream canonical blocks by slot; empty slots
 *       are skipped.
 *
 * Walks the current fork-choice head's parent chain, then loads the matching
 * signed blocks in increasing slot order. This avoids returning side branches
 * or same-slot roots that are not on the canonical chain.
 */
int reqresp_collect_blocks_by_range(
    void *context,
    uint64_t start_slot,
    uint64_t count,
    LanternSignedBlockList *out_blocks)
{
    if (!context || !out_blocks || count == 0u || count > LANTERN_MAX_REQUEST_BLOCKS)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    if (lantern_signed_block_list_resize(out_blocks, 0) != 0)
    {
        return LANTERN_CLIENT_ERR_ALLOC;
    }

    struct lantern_client *client = context;
    LanternRoot descending[LANTERN_MAX_REQUEST_BLOCKS];
    size_t descending_count = 0;

    bool state_locked = lantern_client_lock_state(client);
    if (state_locked && client->store.block_len > 0u)
    {
        LanternRoot root = client->store.head;
        uint64_t previous_slot = 0;
        bool have_previous = false;
        for (;;)
        {
            uint64_t slot = 0;
            LanternRoot parent_root = {0};
            bool has_parent = false;
            if (lantern_fork_choice_block_info(
                    &client->store,
                    &root,
                    &slot,
                    &parent_root,
                    &has_parent)
                != 0
                || (have_previous && slot >= previous_slot)
                || slot < start_slot)
            {
                break;
            }
            if ((slot - start_slot) < count && !lantern_root_is_zero(&root))
            {
                descending[descending_count] = root;
                descending_count += 1u;
            }
            if (!has_parent || lantern_root_is_zero(&parent_root))
            {
                break;
            }
            previous_slot = slot;
            have_previous = true;
            root = parent_root;
        }
    }
    lantern_client_unlock_state(client, state_locked);

    if (descending_count == 0u)
    {
        return LANTERN_CLIENT_OK;
    }

    LanternRoot ascending[LANTERN_MAX_REQUEST_BLOCKS];
    size_t root_count = 0;
    for (size_t i = descending_count; i > 0u; --i)
    {
        ascending[root_count++] = descending[i - 1u];
    }

    LanternSignedBlockList collected = {0};
    int rc = reqresp_collect_blocks(context, ascending, root_count, &collected);
    if (rc != LANTERN_CLIENT_OK)
    {
        lantern_signed_block_list_reset(&collected);
        return rc;
    }

    bool have_previous = false;
    uint64_t previous_slot = 0;
    LanternRoot previous_root = {0};
    size_t valid_count = 0;
    for (size_t i = 0; i < root_count && i < collected.length; ++i)
    {
        const LanternSignedBlock *block = &collected.blocks[i];
        if (!signed_block_matches_root(block, &ascending[i])
            || block->block.slot < start_slot
            || (block->block.slot - start_slot) >= count
            || (have_previous && block->block.slot <= previous_slot))
        {
            break;
        }
        if (have_previous
            && memcmp(block->block.parent_root.bytes, previous_root.bytes, LANTERN_ROOT_SIZE) != 0)
        {
            break;
        }
        previous_slot = block->block.slot;
        previous_root = ascending[i];
        have_previous = true;
        valid_count += 1u;
    }

    if (valid_count > 0u)
    {
        if (lantern_signed_block_list_resize(&collected, valid_count) != 0)
        {
            lantern_signed_block_list_reset(&collected);
            return LANTERN_CLIENT_ERR_ALLOC;
        }
        lantern_signed_block_list_reset(out_blocks);
        *out_blocks = collected;
    }
    else
    {
        lantern_signed_block_list_reset(&collected);
    }

    return LANTERN_CLIENT_OK;
}

int reqresp_current_slot(void *context, uint64_t *out_slot)
{
    if (!context || !out_slot)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    return lantern_client_current_slot((const struct lantern_client *)context, out_slot)
        ? LANTERN_CLIENT_OK
        : LANTERN_CLIENT_ERR_RUNTIME;
}

int reqresp_handle_block_response(
    void *context,
    const LanternSignedBlock *block,
    const char *peer_id,
    uint64_t request_id)
{
    if (!context || !block)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    struct lantern_client *client = context;
    LanternRoot block_root;
    if (lantern_hash_tree_root_block(&block->block, &block_root) != SSZ_SUCCESS)
    {
        return LANTERN_CLIENT_ERR_RUNTIME;
    }
    bool request_active = false;
    if (!block_response_request_context(
            client,
            &block_root,
            block->block.slot,
            request_id,
            &request_active))
    {
        return LANTERN_CLIENT_ERR_RUNTIME;
    }
    if (!request_active)
    {
        return LANTERN_CLIENT_OK;
    }
    if (!client->block_import_sync_initialized)
    {
        if (client->block_import_stop)
        {
            return LANTERN_CLIENT_ERR_RUNTIME;
        }
        return import_block_response_now(
            client,
            block,
            &block_root,
            peer_id);
    }

    struct lantern_async_block_import_job *job = calloc(1u, sizeof(*job));
    if (!job)
    {
        return LANTERN_CLIENT_ERR_ALLOC;
    }
    job->block_root = block_root;
    snprintf(job->peer_id, sizeof(job->peer_id), "%s", peer_id ? peer_id : "");
    if (clone_signed_block(block, &job->block) != 0)
    {
        block_import_job_free(job);
        return LANTERN_CLIENT_ERR_ALLOC;
    }
    if (enqueue_block_import_job(client, job) == 0)
    {
        return LANTERN_CLIENT_OK;
    }
    block_import_job_free(job);
    return LANTERN_CLIENT_ERR_RUNTIME;
}

void reqresp_blocks_request_complete(
    void *context,
    uint64_t request_id,
    enum lantern_reqresp_blocks_request_result result)
{
    if (!context)
    {
        return;
    }
    enum lantern_blocks_request_outcome outcome = LANTERN_BLOCKS_REQUEST_FAILED;
    switch (result)
    {
    case LANTERN_REQRESP_BLOCKS_REQUEST_RESULT_SUCCESS:
        outcome = LANTERN_BLOCKS_REQUEST_SUCCESS;
        break;
    case LANTERN_REQRESP_BLOCKS_REQUEST_RESULT_EMPTY:
        outcome = LANTERN_BLOCKS_REQUEST_EMPTY;
        break;
    case LANTERN_REQRESP_BLOCKS_REQUEST_RESULT_FAILED:
    default:
        break;
    }
    struct lantern_client *client = context;
    if (lantern_client_complete_range_request(client, request_id, outcome))
    {
        return;
    }
    lantern_client_on_blocks_request_complete_batch_with_id(
        client,
        request_id,
        outcome);
}


/* ============================================================================
 * Peer Status Processing
 * ============================================================================ */

/**
 * Process a peer status message internally.
 *
 * @spec subspecs/forkchoice/store.py - Sync decision logic
 *
 * Updates peer status tracking and sync progress based on the received
 * status message. Ahead peer heads route forward range catch-up.
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

    char peer_copy[sizeof(((struct lantern_peer_status_entry *)0)->peer_id)];
    (void)lantern_string_copy(peer_copy, sizeof(peer_copy), peer_id);

    LanternCheckpoint local_head = {0};
    bool head_known = false;
    peer_status_local_view(
        client,
        &peer_status->head,
        &local_head,
        &head_known);

    struct lantern_log_metadata meta = {
        .validator = client->node_id,
        .peer = peer_copy[0] ? peer_copy : NULL,
    };
    lantern_log_debug(
        "sync",
        &meta,
        "peer status view head_slot=%" PRIu64 " finalized_slot=%" PRIu64 " head_known=%s local_slot=%" PRIu64,
        peer_status->head.slot,
        peer_status->finalized.slot,
        head_known ? "true" : "false",
        local_head.slot);

    lantern_client_peer_status_update(
        client,
        peer_status,
        peer_copy,
        &local_head,
        head_known);
    if (peer_status->head.slot > local_head.slot)
    {
        lantern_client_update_range_sync_target(
            client,
            peer_copy,
            local_head.slot,
            peer_status->head.slot);
    }
}


/**
 * Handle completion of a blocks request batch.
 *
 * @spec subspecs/networking/reqresp - Request lifecycle
 *
 * Finalizes the active attempt and advances its root-scoped retry lifecycle.
 *
 * @param client        Client instance
 * @param request_id    Internal request tracking ID; stale or unknown IDs are ignored
 * @param outcome       Request outcome
 *
 * @note Thread safety: Acquires status_lock; successful responses may then
 * acquire pending_lock while scheduling a newly discovered parent.
 */
void lantern_client_on_blocks_request_complete_batch_with_id(
    struct lantern_client *client,
    uint64_t request_id,
    enum lantern_blocks_request_outcome outcome)
{
    if (!client || !client->status_lock_initialized)
    {
        return;
    }
    struct lantern_blocks_request_completion completion;
    if (!lantern_client_complete_blocks_request(
            client,
            request_id,
            outcome,
            &completion))
    {
        return;
    }

    const char *peer_for_logs = completion.peer_id;
    const LanternRoot *first_root = &completion.first_root;

    char root_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    format_root_hex(first_root, root_hex, sizeof(root_hex));
    const char *outcome_text = lantern_blocks_request_outcome_text(outcome);
    if (outcome == LANTERN_BLOCKS_REQUEST_SUCCESS && client->sync_started_ms != 0u)
    {
        lantern_log_debug(
            "backfill",
            &(const struct lantern_log_metadata){
                .validator = client->node_id,
                .peer = peer_for_logs && peer_for_logs[0] ? peer_for_logs : NULL},
            "response %s, roots %zu, first_root %s, attempt %" PRIu32,
            outcome_text,
            completion.root_count,
            root_hex[0] ? root_hex : "0x0",
            completion.attempts);
    }
    else
    {
        if (outcome == LANTERN_BLOCKS_REQUEST_SUCCESS)
        {
            lantern_log_info(
                "backfill",
                &(const struct lantern_log_metadata){
                    .validator = client->node_id,
                    .peer = peer_for_logs && peer_for_logs[0] ? peer_for_logs : NULL},
                "response %s, roots %zu, first_root %s, attempt %" PRIu32,
                outcome_text,
                completion.root_count,
                root_hex[0] ? root_hex : "0x0",
                completion.attempts);
        }
        else
        {
            lantern_log_warn(
                "backfill",
                &(const struct lantern_log_metadata){
                    .validator = client->node_id,
                    .peer = peer_for_logs && peer_for_logs[0] ? peer_for_logs : NULL},
                "request failed, peer %s, reason: %s, roots %zu, first_root %s"
                ", attempt %" PRIu32 ", retry_scheduled %s, exhausted %s",
                peer_for_logs && peer_for_logs[0] ? peer_for_logs : "-",
                outcome_text,
                completion.root_count,
                root_hex[0] ? root_hex : "0x0",
                completion.attempts,
                completion.retry_scheduled ? "true" : "false",
                completion.exhausted ? "true" : "false");
        }
    }

    if (outcome == LANTERN_BLOCKS_REQUEST_SUCCESS)
    {
        lantern_client_request_pending_parent_after_blocks(
            client,
            peer_for_logs,
            first_root);
        return;
    }
}
