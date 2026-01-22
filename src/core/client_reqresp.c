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

#include <inttypes.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "libp2p/errors.h"
#include "peer_id/peer_id.h"

#include "lantern/consensus/hash.h"
#include "lantern/networking/messages.h"
#include "lantern/networking/reqresp_service.h"
#include "lantern/storage/storage.h"
#include "lantern/support/log.h"
#include "lantern/support/strings.h"


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
static void lantern_client_adopt_peer_genesis(
    struct lantern_client *client,
    const LanternStatusMessage *peer_status,
    const char *peer_id_text);

static void copy_peer_id_text(const char *peer_id, char *out, size_t out_len);
static bool record_status_failure_peer_id(struct lantern_client *client, const char *peer_id_text);
static void log_status_failure(
    const struct lantern_client *client,
    const char *peer_id_text,
    int error,
    bool first_failure);
static void peer_status_local_view(
    struct lantern_client *client,
    const LanternRoot *head_root,
    uint64_t *out_local_slot,
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
    uint64_t local_slot);
static bool lantern_client_update_blocks_request_tracking(
    struct lantern_client *client,
    const char *peer_id,
    enum lantern_blocks_request_outcome outcome,
    uint32_t *out_failure_count,
    bool *out_entry_found);
static const char *lantern_blocks_request_outcome_text(enum lantern_blocks_request_outcome outcome);
static void lantern_client_clear_pending_parent_requested(
    struct lantern_client *client,
    const LanternRoot *request_root);
static void lantern_client_request_status_after_blocks_success(
    struct lantern_client *client,
    const char *peer_id);


/* ============================================================================
 * Reqresp Callbacks
 * ============================================================================ */

/**
 * @brief Copies a peer ID string into a fixed-size buffer.
 *
 * @param peer_id  Peer ID string (may be NULL)
 * @param out      Output buffer
 * @param out_len  Output buffer length
 */
static void copy_peer_id_text(const char *peer_id, char *out, size_t out_len)
{
    if (!out || out_len == 0)
    {
        return;
    }

    out[0] = '\0';
    if (!peer_id || peer_id[0] == '\0')
    {
        return;
    }

    strncpy(out, peer_id, out_len - 1);
    out[out_len - 1] = '\0';
}


/**
 * @brief Record the peer for failure log throttling.
 *
 * @param client        Client instance
 * @param peer_id_text  Peer ID string (may be empty)
 * @return true if this is the first recorded failure, false otherwise
 *
 * @note Thread safety: This function acquires status_lock
 */
static bool record_status_failure_peer_id(struct lantern_client *client, const char *peer_id_text)
{
    if (!client || !peer_id_text || peer_id_text[0] == '\0')
    {
        return true;
    }

    if (!client->status_lock_initialized)
    {
        return true;
    }

    bool first_failure = true;
    if (pthread_mutex_lock(&client->status_lock) != 0)
    {
        return true;
    }

    if (string_list_contains(&client->status_failure_peer_ids, peer_id_text))
    {
        first_failure = false;
    }
    else if (lantern_string_list_append(&client->status_failure_peer_ids, peer_id_text) != 0)
    {
        first_failure = true;
    }

    pthread_mutex_unlock(&client->status_lock);
    return first_failure;
}


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
 * @brief Determine local slot and whether a head root is known.
 *
 * @param client         Client instance
 * @param head_root      Head root to check
 * @param out_local_slot Output local slot snapshot
 * @param out_head_known Output true if head is known locally
 *
 * @note Thread safety: This function may acquire state_lock
 */
static void peer_status_local_view(
    struct lantern_client *client,
    const LanternRoot *head_root,
    uint64_t *out_local_slot,
    bool *out_head_known)
{
    if (out_local_slot)
    {
        *out_local_slot = 0;
    }
    if (out_head_known)
    {
        *out_head_known = false;
    }

    if (!client || !head_root || !out_local_slot || !out_head_known)
    {
        return;
    }

    uint64_t local_slot = 0;
    bool head_known = false;
    bool state_locked = lantern_client_lock_state(client);
    if (state_locked)
    {
        local_slot = client->state.latest_block_header.slot;
        if (client->has_fork_choice)
        {
            LanternRoot fork_head = {0};
            if (lantern_fork_choice_current_head(&client->fork_choice, &fork_head) == 0)
            {
                uint64_t fork_slot = 0;
                if (lantern_fork_choice_block_info(
                        &client->fork_choice,
                        &fork_head,
                        &fork_slot,
                        NULL,
                        NULL)
                    == 0)
                {
                    local_slot = fork_slot;
                }
            }
        }
        head_known = lantern_client_block_known_locked(client, head_root, NULL);
    }
    else if (client->has_state)
    {
        local_slot = client->state.latest_block_header.slot;
        if (client->has_fork_choice)
        {
            LanternRoot fork_head = {0};
            if (lantern_fork_choice_current_head(&client->fork_choice, &fork_head) == 0)
            {
                uint64_t fork_slot = 0;
                if (lantern_fork_choice_block_info(
                        &client->fork_choice,
                        &fork_head,
                        &fork_slot,
                        NULL,
                        NULL)
                    == 0)
                {
                    local_slot = fork_slot;
                }
            }
            uint64_t fork_slot = 0;
            if (lantern_fork_choice_block_info(
                    &client->fork_choice,
                    head_root,
                    &fork_slot,
                    NULL,
                    NULL)
                == 0)
            {
                head_known = true;
            }
        }
    }
    lantern_client_unlock_state(client, state_locked);

    *out_local_slot = local_slot;
    *out_head_known = head_known;

}

static bool peer_status_is_eligible(
    struct lantern_client *client,
    const struct lantern_peer_status_entry *entry,
    uint64_t now_ms)
{
    if (!client || !entry || !entry->has_status)
    {
        return false;
    }
    if (entry->last_status_ms == 0 || now_ms < entry->last_status_ms)
    {
        return false;
    }
    if (!client->connection_lock_initialized)
    {
        return true;
    }
    return lantern_client_is_peer_connected(client, entry->peer_id);
}

static bool network_finalized_slot_locked(
    struct lantern_client *client,
    uint64_t now_ms,
    uint64_t *out_slot)
{
    if (!client || !out_slot)
    {
        return false;
    }

    bool found = false;
    uint64_t mode_slot = 0;
    size_t mode_count = 0;

    for (size_t i = 0; i < client->peer_status_count; ++i)
    {
        const struct lantern_peer_status_entry *entry = &client->peer_status_entries[i];
        if (!peer_status_is_eligible(client, entry, now_ms))
        {
            continue;
        }

        uint64_t slot = entry->status.finalized.slot;
        size_t count = 0;
        for (size_t j = 0; j < client->peer_status_count; ++j)
        {
            const struct lantern_peer_status_entry *other = &client->peer_status_entries[j];
            if (!peer_status_is_eligible(client, other, now_ms))
            {
                continue;
            }
            if (other->status.finalized.slot == slot)
            {
                count += 1u;
            }
        }

        if (!found || count > mode_count)
        {
            mode_slot = slot;
            mode_count = count;
            found = true;
        }
    }

    if (found)
    {
        *out_slot = mode_slot;
    }

    return found;
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
    uint64_t network_finalized,
    bool has_network_finalized,
    bool allow_sync_complete)
{
    if (!client)
    {
        return;
    }

    if (!has_network_finalized)
    {
        return;
    }

    bool was_idle = client->sync_state == LANTERN_SYNC_STATE_IDLE;
    if (was_idle)
    {
        client->sync_state = LANTERN_SYNC_STATE_SYNCING;
    }

    size_t pending = 0;
    size_t orphan_count = 0;
    char pending_peer[sizeof(((struct lantern_pending_block *)0)->peer_text)];
    pending_peer[0] = '\0';
    char orphan_peer[sizeof(((struct lantern_pending_block *)0)->peer_text)];
    orphan_peer[0] = '\0';
    {
        bool state_locked = lantern_client_lock_state(client);
        bool pending_locked = lantern_client_lock_pending(client);
        if (pending_locked)
        {
            pending = client->pending_blocks.length;
            for (size_t i = 0; i < client->pending_blocks.length; ++i)
            {
                const struct lantern_pending_block *entry = &client->pending_blocks.items[i];
                if (pending_peer[0] == '\0' && entry->peer_text[0] != '\0')
                {
                    strncpy(pending_peer, entry->peer_text, sizeof(pending_peer) - 1u);
                    pending_peer[sizeof(pending_peer) - 1u] = '\0';
                }
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
                    orphan_count += 1u;
                    if (orphan_peer[0] == '\0' && entry->peer_text[0] != '\0')
                    {
                        strncpy(orphan_peer, entry->peer_text, sizeof(orphan_peer) - 1u);
                        orphan_peer[sizeof(orphan_peer) - 1u] = '\0';
                    }
                }
            }
        }
        lantern_client_unlock_pending(client, pending_locked);
        lantern_client_unlock_state(client, state_locked);
    }
    bool has_orphans = orphan_count > 0;
    bool behind_finalized = local_slot < network_finalized;
    bool syncing = behind_finalized || has_orphans;

    uint64_t now_ms = monotonic_millis();
    struct lantern_log_metadata meta = {.validator = client->node_id};
    bool should_request_parent = false;
    const char *request_peer = orphan_peer[0] ? orphan_peer : pending_peer;
    if (has_orphans && request_peer && request_peer[0] != '\0')
    {
        should_request_parent = true;
    }

    bool allow_complete = allow_sync_complete && client->sync_state == LANTERN_SYNC_STATE_SYNCING;
    if (!syncing)
    {
        if (was_idle)
        {
            /* Hold SYNCING for one status update to honor IDLE -> SYNCING transition. */
            return;
        }
        if (!allow_complete)
        {
            return;
        }
        client->sync_state = LANTERN_SYNC_STATE_SYNCED;
        if (client->sync_in_progress)
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
                "sync complete local_slot=%" PRIu64 " target_slot=%" PRIu64 " duration=%s imported=%" PRIu64,
                local_slot,
                target_slot,
                duration,
                client->sync_imported_blocks);
            client->sync_in_progress = false;
            client->sync_started_ms = 0;
            client->sync_last_log_ms = 0;
            client->sync_last_imported_blocks = 0;
            client->sync_target_slot = 0;
        }
        return;
    }

    client->sync_state = LANTERN_SYNC_STATE_SYNCING;
    if (!client->sync_in_progress)
    {
        client->sync_in_progress = true;
        client->sync_started_ms = now_ms;
        client->sync_last_log_ms = 0;
        client->sync_last_imported_blocks = 0;
        client->sync_imported_blocks = 0;
        client->sync_target_slot = network_finalized;
        lantern_log_info(
            "sync",
            &meta,
            "sync starting local_slot=%" PRIu64 " target_slot=%" PRIu64 " pending=%zu",
            local_slot,
            network_finalized,
            pending);
    }

    if (client->sync_last_log_ms != 0
        && now_ms < client->sync_last_log_ms + SYNC_PROGRESS_LOG_INTERVAL_MS)
    {
        return;
    }

    uint64_t target_slot =
        client->sync_target_slot != 0 ? client->sync_target_slot : network_finalized;
    uint64_t remaining = (target_slot > local_slot) ? (target_slot - local_slot) : 0;

    if (pending > 0)
    {
        lantern_log_info(
            "sync",
            &meta,
            "sync progress local_slot=%" PRIu64 " target_slot=%" PRIu64
            " remaining=%" PRIu64 " pending=%zu",
            local_slot,
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
            local_slot,
            target_slot,
            remaining);
    }

    client->sync_last_log_ms = now_ms;
    client->sync_last_imported_blocks = client->sync_imported_blocks;

    if (should_request_parent)
    {
        lantern_log_info(
            "sync",
            &meta,
            "sync requesting orphan parent pending=%zu orphans=%zu",
            pending,
            orphan_count);
        lantern_client_request_pending_parent_after_blocks(client, request_peer, NULL);
    }
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

    uint64_t network_finalized = 0;
    bool has_network_finalized = network_finalized_slot_locked(
        client,
        monotonic_millis(),
        &network_finalized);

    pthread_mutex_unlock(&client->status_lock);

    maybe_log_sync_progress(client, local_slot, network_finalized, has_network_finalized, true);
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
    lantern_client_status_request_update_locked(client, entry, peer_id_text, -1, "complete");

    string_list_remove(&client->status_failure_peer_ids, peer_id_text);

    bool head_changed = !entry->has_status
        || entry->status.head.slot != peer_status->head.slot
        || memcmp(
            entry->status.head.root.bytes,
            peer_status->head.root.bytes,
            LANTERN_ROOT_SIZE)
            != 0;

    entry->status = *peer_status;
    entry->has_status = true;
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
 * @param local_slot   Local slot snapshot
 *
 * @note Thread safety: This function acquires status_lock
 */
static void lantern_client_peer_status_update(
    struct lantern_client *client,
    const LanternStatusMessage *peer_status,
    const char *peer_id_text,
    uint64_t local_slot)
{
    if (!client || !peer_status || !peer_id_text)
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

    uint64_t network_finalized = 0;
    bool has_network_finalized = network_finalized_slot_locked(
        client,
        monotonic_millis(),
        &network_finalized);

    pthread_mutex_unlock(&client->status_lock);

    maybe_log_sync_progress(client, local_slot, network_finalized, has_network_finalized, false);
}


/**
 * @brief Update blocks request tracking state for a peer.
 *
 * @param client            Client instance
 * @param peer_id           Peer ID string
 * @param outcome           Request outcome
 * @param out_failure_count Output consecutive failure count
 * @param out_entry_found   Output whether peer entry was found
 * @return true if tracking was updated (status_lock acquired), false otherwise
 *
 * @note Thread safety: This function acquires status_lock
 */
static bool lantern_client_update_blocks_request_tracking(
    struct lantern_client *client,
    const char *peer_id,
    enum lantern_blocks_request_outcome outcome,
    uint32_t *out_failure_count,
    bool *out_entry_found)
{
    if (!client || !peer_id || !out_failure_count || !out_entry_found)
    {
        return false;
    }

    *out_failure_count = 0;
    *out_entry_found = false;

    const size_t peer_cap = sizeof(((struct lantern_peer_status_entry *)0)->peer_id);
    if (pthread_mutex_lock(&client->status_lock) != 0)
    {
        return false;
    }

    for (size_t i = 0; i < client->peer_status_count; ++i)
    {
        struct lantern_peer_status_entry *entry = &client->peer_status_entries[i];
        if (strncmp(entry->peer_id, peer_id, peer_cap) == 0)
        {
            if (entry->blocks_requests_inflight > 0)
            {
                entry->blocks_requests_inflight -= 1u;
            }
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
            case LANTERN_BLOCKS_REQUEST_EMPTY:
                if (entry->consecutive_blocks_failures < UINT32_MAX)
                {
                    entry->consecutive_blocks_failures += 1;
                }
                break;
            case LANTERN_BLOCKS_REQUEST_ABORTED:
                if (entry->blocks_requests_inflight == 0)
                {
                    entry->last_blocks_request_ms = 0;
                }
                break;
            default:
                break;
            }
            if (outcome != LANTERN_BLOCKS_REQUEST_ABORTED && entry->last_blocks_request_ms == 0)
            {
                entry->last_blocks_request_ms = monotonic_millis();
            }
            *out_failure_count = entry->consecutive_blocks_failures;
            *out_entry_found = true;
            break;
        }
    }

    pthread_mutex_unlock(&client->status_lock);
    return true;
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
 * @brief Clear parent_requested flags for pending blocks matching requested roots.
 *
 * @param client         Client instance
 * @param request_roots  Requested parent roots
 * @param root_count     Number of requested roots
 *
 * @note Thread safety: This function acquires pending_lock
 */
static void lantern_client_clear_pending_parent_requested_roots(
    struct lantern_client *client,
    const LanternRoot *request_roots,
    size_t root_count)
{
    if (!client || !request_roots || root_count == 0)
    {
        return;
    }

    bool locked = lantern_client_lock_pending(client);
    if (!locked)
    {
        return;
    }

    for (size_t i = 0; i < client->pending_blocks.length; ++i)
    {
        struct lantern_pending_block *entry = &client->pending_blocks.items[i];
        for (size_t j = 0; j < root_count; ++j)
        {
            if (lantern_root_is_zero(&request_roots[j]))
            {
                continue;
            }
            if (memcmp(entry->parent_root.bytes, request_roots[j].bytes, LANTERN_ROOT_SIZE) == 0)
            {
                entry->parent_requested = false;
                break;
            }
        }
    }

    lantern_client_unlock_pending(client, locked);
}

/**
 * @brief Clear parent_requested flags for pending blocks matching request_root.
 *
 * @param client       Client instance
 * @param request_root Requested parent root
 *
 * @note Thread safety: This function acquires pending_lock
 */
static void lantern_client_clear_pending_parent_requested(
    struct lantern_client *client,
    const LanternRoot *request_root)
{
    if (!request_root)
    {
        return;
    }
    lantern_client_clear_pending_parent_requested_roots(client, request_root, 1u);
}


/**
 * @brief Issue a follow-up status request after successful blocks fetch.
 *
 * @param client   Client instance
 * @param peer_id  Peer ID string
 *
 * @note Thread safety: This function is thread-safe
 */
static void lantern_client_request_status_after_blocks_success(
    struct lantern_client *client,
    const char *peer_id)
{
    if (!client || !peer_id || peer_id[0] == '\0')
    {
        return;
    }

    peer_id_t parsed_peer = {0};
    bool parsed = peer_id_create_from_string(peer_id, &parsed_peer) == PEER_ID_SUCCESS;

    request_status_now(client, parsed ? &parsed_peer : NULL, peer_id);

    if (parsed)
    {
        peer_id_destroy(&parsed_peer);
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
    if (!client->has_state)
    {
        return LANTERN_CLIENT_OK;
    }

    out_status->finalized = client->state.latest_finalized;

    bool head_set = false;
    if (client->has_fork_choice)
    {
        LanternRoot fork_head = {{0}};
        uint64_t fork_slot = 0;
        if (lantern_fork_choice_current_head(&client->fork_choice, &fork_head) == 0
            && lantern_fork_choice_block_info(
                   &client->fork_choice,
                   &fork_head,
                   &fork_slot,
                   NULL,
                   NULL)
                == 0)
        {
            out_status->head.root = fork_head;
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
            != 0)
        {
            memset(&out_status->head.root, 0, sizeof(out_status->head.root));
        }
    }
    return LANTERN_CLIENT_OK;
}


/**
 * Handle an incoming status message from a peer.
 *
 * @spec subspecs/networking/reqresp/message.py - Status protocol
 *
 * Processes a peer's status message, updates peer tracking, and records
 * sync progress. Peer status does not proactively trigger block requests.
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
    copy_peer_id_text(peer_id, peer_copy, sizeof(peer_copy));
    if (error == 0)
    {
        error = LIBP2P_ERR_INTERNAL;
    }

    if (peer_copy[0] != '\0')
    {
        lantern_client_status_request_failed(client, peer_copy);
    }

    bool first_failure = record_status_failure_peer_id(client, peer_copy);
    log_status_failure(client, peer_copy, error, first_failure);
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
    LanternBlocksByRootResponse *out_blocks)
{
    if (!context || !out_blocks)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    struct lantern_client *client = context;
    if (!client->data_dir)
    {
        if (lantern_blocks_by_root_response_resize(out_blocks, 0) != 0)
        {
            return LANTERN_CLIENT_ERR_ALLOC;
        }
        return LANTERN_CLIENT_OK;
    }
    if (lantern_storage_collect_blocks(client->data_dir, roots, root_count, out_blocks) != 0)
    {
        lantern_log_error(
            "reqresp",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to collect blocks from storage");
        return LANTERN_CLIENT_ERR_STORAGE;
    }
    return LANTERN_CLIENT_OK;
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
 * status message. Block requests are initiated only by reactive sync
 * paths (gossip backfill or missing parents), not by status alone.
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
    copy_peer_id_text(peer_id, peer_copy, sizeof(peer_copy));

    uint64_t local_slot = 0;
    bool head_known = false;
    peer_status_local_view(client, &peer_status->head.root, &local_slot, &head_known);

    /* If we bootstrapped via genesis fallback and the peer advertises the genesis head,
       adopt the peer's head root as our anchor so that subsequent block requests use
       the correct root. */
    if (client->genesis_fallback_used && client->has_fork_choice && client->has_state
        && peer_status->head.slot == 0 && local_slot == 0 && !head_known)
    {
        lantern_client_adopt_peer_genesis(client, peer_status, peer_copy);
    }

    lantern_client_peer_status_update(
        client,
        peer_status,
        peer_copy,
        local_slot);
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
            &(const struct lantern_log_metadata){
                .validator = client->node_id,
                .peer = peer_id_text},
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
        &(const struct lantern_log_metadata){
            .validator = client->node_id,
            .peer = peer_id_text},
        "adopted peer genesis head_slot=0 root=%s",
        head_hex);
}


/**
 * Handle completion of a blocks request batch.
 *
 * @spec subspecs/networking/reqresp - Request lifecycle
 *
 * Updates peer tracking state after a blocks_by_root request completes:
 * - Decrements request-in-flight counter
 * - Updates consecutive failure counter
 * - Clears parent_requested flag on pending blocks
 * - Triggers follow-up status request on success
 *
 * @param client        Client instance
 * @param peer_id       Peer ID string
 * @param request_roots Roots that were requested
 * @param root_count    Number of requested roots
 * @param outcome       Request outcome
 *
 * @note Thread safety: This function acquires status_lock and pending_lock
 */
void lantern_client_on_blocks_request_complete_batch(
    struct lantern_client *client,
    const char *peer_id,
    const LanternRoot *request_roots,
    size_t root_count,
    enum lantern_blocks_request_outcome outcome)
{
    if (!client || !peer_id || !client->status_lock_initialized)
    {
        return;
    }
    uint32_t failure_count = 0;
    bool entry_found = false;
    if (!lantern_client_update_blocks_request_tracking(
            client,
            peer_id,
            outcome,
            &failure_count,
            &entry_found))
    {
        return;
    }

    const LanternRoot *first_root = NULL;
    if (request_roots && root_count > 0)
    {
        first_root = &request_roots[0];
    }

    char root_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    root_hex[0] = '\0';
    if (first_root)
    {
        format_root_hex(first_root, root_hex, sizeof(root_hex));
    }
    const char *outcome_text = lantern_blocks_request_outcome_text(outcome);
    if (outcome == LANTERN_BLOCKS_REQUEST_SUCCESS && client->sync_in_progress)
    {
        lantern_log_debug(
            "reqresp",
            &(const struct lantern_log_metadata){
                .validator = client->node_id,
                .peer = peer_id},
            "blocks_by_root complete outcome=%s roots=%zu first_root=%s entry_found=%s "
            "consecutive_failures=%" PRIu32,
            outcome_text,
            root_count,
            root_hex[0] ? root_hex : "0x0",
            entry_found ? "true" : "false",
            failure_count);
    }
    else
    {
        lantern_log_info(
            "reqresp",
            &(const struct lantern_log_metadata){
                .validator = client->node_id,
                .peer = peer_id},
            "blocks_by_root complete outcome=%s roots=%zu first_root=%s entry_found=%s "
            "consecutive_failures=%" PRIu32,
            outcome_text,
            root_count,
            root_hex[0] ? root_hex : "0x0",
            entry_found ? "true" : "false",
            failure_count);
    }

    lantern_client_clear_pending_parent_requested_roots(client, request_roots, root_count);

    if (outcome == LANTERN_BLOCKS_REQUEST_SUCCESS && peer_id && peer_id[0] != '\0')
    {
        lantern_client_request_pending_parent_after_blocks(
            client,
            peer_id,
            first_root);
        lantern_client_request_status_after_blocks_success(client, peer_id);
    }
}

/**
 * Handle completion of a blocks request (single root).
 *
 * @spec subspecs/networking/reqresp - Request lifecycle
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
    if (!request_root)
    {
        lantern_client_on_blocks_request_complete_batch(
            client,
            peer_id,
            NULL,
            0u,
            outcome);
        return;
    }
    lantern_client_on_blocks_request_complete_batch(
        client,
        peer_id,
        request_root,
        1u,
        outcome);
}
