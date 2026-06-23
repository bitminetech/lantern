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
    ASYNC_BLOCK_IMPORT_QUEUE_LIMIT = 128u,
};

struct lantern_async_block_import_job
{
    struct lantern_client *client;
    LanternSignedBlock block;
    LanternRoot block_root;
    char peer_id[128];
    uint8_t *raw_block_ssz;
    size_t raw_block_ssz_len;
    struct lantern_async_block_import_job *next;
};


/* ============================================================================
 * Sync Logging
 * ============================================================================ */

static const uint64_t SYNC_PROGRESS_LOG_INTERVAL_MS = 5000u;

static void maybe_retry_orphan_parent_request(
    struct lantern_client *client,
    uint64_t now_ms,
    bool should_request_parent,
    const char *request_peer,
    size_t pending,
    size_t orphan_count,
    const struct lantern_log_metadata *meta)
{
    if (!client || !meta)
    {
        return;
    }
    if (!should_request_parent || !request_peer || request_peer[0] == '\0')
    {
        return;
    }
    if (client->sync_last_log_ms != 0
        && now_ms < client->sync_last_log_ms + SYNC_PROGRESS_LOG_INTERVAL_MS)
    {
        return;
    }
    lantern_log_info(
        "sync",
        meta,
        "orphan recovery requesting parent pending=%zu orphans=%zu",
        pending,
        orphan_count);
    lantern_client_request_pending_parent_after_blocks(client, request_peer, NULL);
    client->sync_last_log_ms = now_ms;
}


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
    uint64_t *out_local_finalized_slot,
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
    uint64_t request_id,
    const char *peer_id,
    enum lantern_blocks_request_outcome outcome,
    uint32_t *out_failure_count,
    bool *out_entry_found,
    char *out_effective_peer_id,
    size_t out_effective_peer_id_len);
static const char *lantern_blocks_request_outcome_text(enum lantern_blocks_request_outcome outcome);
static void lantern_client_handle_pending_parent_request_result(
    struct lantern_client *client,
    const LanternRoot *request_roots,
    size_t root_count,
    enum lantern_blocks_request_outcome outcome);
static void reqresp_alias_anchor_checkpoint_if_unset(
    struct lantern_client *client,
    LanternStatusMessage *status);


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

    (void)lantern_string_copy(out, out_len, peer_id);
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
    uint64_t *out_local_finalized_slot,
    bool *out_head_known)
{
    if (out_local_slot)
    {
        *out_local_slot = 0;
    }
    if (out_local_finalized_slot)
    {
        *out_local_finalized_slot = 0;
    }
    if (out_head_known)
    {
        *out_head_known = false;
    }

    if (!client || !head_root || !out_local_slot || !out_local_finalized_slot || !out_head_known)
    {
        return;
    }

    uint64_t local_slot = 0;
    uint64_t local_finalized_slot = 0;
    bool head_known = false;
    bool state_locked = lantern_client_lock_state(client);
    if (state_locked)
    {
        local_slot = client->state.latest_block_header.slot;
        local_finalized_slot = client->state.latest_finalized.slot;
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
            const LanternCheckpoint *fork_finalized =
                lantern_fork_choice_latest_finalized(&client->fork_choice);
            if (fork_finalized && !lantern_root_is_zero(&fork_finalized->root))
            {
                local_finalized_slot = fork_finalized->slot;
            }
        }
        head_known = lantern_client_block_known_locked(client, head_root, NULL);
    }
    else if (client->has_state)
    {
        local_slot = client->state.latest_block_header.slot;
        local_finalized_slot = client->state.latest_finalized.slot;
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
            const LanternCheckpoint *fork_finalized =
                lantern_fork_choice_latest_finalized(&client->fork_choice);
            if (fork_finalized && !lantern_root_is_zero(&fork_finalized->root))
            {
                local_finalized_slot = fork_finalized->slot;
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
    *out_local_finalized_slot = local_finalized_slot;
    *out_head_known = head_known;

}

static void maybe_seed_head_request_from_status(
    struct lantern_client *client,
    const LanternStatusMessage *peer_status,
    const char *peer_id_text,
    uint64_t local_head_slot,
    uint64_t local_finalized_slot,
    bool head_known)
{
    if (!client || !peer_status || !peer_id_text || peer_id_text[0] == '\0')
    {
        return;
    }
    if (head_known || lantern_root_is_zero(&peer_status->head.root))
    {
        return;
    }

    const bool peer_finalized_ahead = peer_status->finalized.slot > local_finalized_slot;
    const bool peer_head_ahead = peer_status->head.slot > local_head_slot;
    if (!peer_finalized_ahead && !peer_head_ahead)
    {
        return;
    }

    bool historical_backfill_started = false;
    if (peer_head_ahead)
    {
        historical_backfill_started = lantern_client_maybe_start_historical_backfill(
            client,
            peer_id_text,
            &peer_status->head.root,
            peer_status->head.slot,
            local_head_slot);
    }

    bool has_pending_blocks = false;
    bool pending_locked = lantern_client_lock_pending(client);
    if (pending_locked)
    {
        has_pending_blocks = client->pending_blocks.length > 0;
    }
    lantern_client_unlock_pending(client, pending_locked);
    if (has_pending_blocks && !historical_backfill_started)
    {
        return;
    }

    uint64_t now_ms = monotonic_millis();
    bool recently_requested = false;
    if (client->status_lock_initialized && pthread_mutex_lock(&client->status_lock) == 0)
    {
        if (!lantern_root_is_zero(&client->sync_last_requested_root)
            && memcmp(
                   client->sync_last_requested_root.bytes,
                   peer_status->head.root.bytes,
                   LANTERN_ROOT_SIZE)
                == 0
            && client->sync_last_requested_root_ms != 0
            && now_ms >= client->sync_last_requested_root_ms
            && (now_ms - client->sync_last_requested_root_ms) < LANTERN_BLOCKS_REQUEST_TIMEOUT_MS)
        {
            recently_requested = true;
        }
        pthread_mutex_unlock(&client->status_lock);
    }
    if (recently_requested)
    {
        return;
    }

    const LanternRoot roots[1] = {peer_status->head.root};
    const uint32_t depths[1] = {0u};
    if (!lantern_client_try_schedule_blocks_request_batch(
            client,
            peer_id_text,
            roots,
            depths,
            1u))
    {
        return;
    }

    if (client->status_lock_initialized && pthread_mutex_lock(&client->status_lock) == 0)
    {
        client->sync_last_requested_root = peer_status->head.root;
        client->sync_last_requested_root_ms = now_ms;
        pthread_mutex_unlock(&client->status_lock);
    }

    char head_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    format_root_hex(&peer_status->head.root, head_hex, sizeof(head_hex));
    lantern_log_info(
        "sync",
        &(const struct lantern_log_metadata){
            .validator = client->node_id,
            .peer = peer_id_text},
        "peer is ahead; requesting head block root=%s peer_head_slot=%" PRIu64
        " peer_finalized_slot=%" PRIu64 " local_head_slot=%" PRIu64 " local_finalized_slot=%" PRIu64,
        head_hex[0] ? head_hex : "0x0",
        peer_status->head.slot,
        peer_status->finalized.slot,
        local_head_slot,
        local_finalized_slot);
}

static void network_view_snapshot_locked(
    struct lantern_client *client,
    uint64_t *out_head_slot,
    bool *out_has_head_slot,
    uint64_t *out_finalized_slot,
    bool *out_has_finalized_slot)
{
    if (out_head_slot)
    {
        *out_head_slot = client ? client->network_view.latest_observed_head_slot : 0u;
    }
    if (out_has_head_slot)
    {
        *out_has_head_slot = client && client->network_view.has_latest_observed_head_slot;
    }
    if (out_finalized_slot)
    {
        *out_finalized_slot = client ? client->network_view.network_finalized_slot : 0u;
    }
    if (out_has_finalized_slot)
    {
        *out_has_finalized_slot = client && client->network_view.has_network_finalized_slot;
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
    uint64_t network_head_slot,
    bool has_network_head,
    uint64_t network_finalized,
    bool has_network_finalized,
    bool allow_sync_complete)
{
    if (!client)
    {
        return;
    }

    uint64_t now_ms = monotonic_millis();

    size_t pending = 0;
    size_t orphan_count = 0;
    uint64_t local_head_slot = local_slot;
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
                    (void)lantern_string_copy(pending_peer, sizeof(pending_peer), entry->peer_text);
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
                        (void)lantern_string_copy(orphan_peer, sizeof(orphan_peer), entry->peer_text);
                    }
                }
            }
        }
        if (state_locked && client->has_fork_choice)
        {
            LanternRoot local_head_root = {0};
            if (lantern_fork_choice_current_head(&client->fork_choice, &local_head_root) == 0)
            {
                uint64_t fork_slot = 0;
                if (lantern_fork_choice_block_info(
                        &client->fork_choice,
                        &local_head_root,
                        &fork_slot,
                        NULL,
                        NULL)
                    == 0)
                {
                    local_head_slot = fork_slot;
                }
            }
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

    bool has_orphans = orphan_count > 0;
    bool behind_finalized = has_network_finalized && network_finalized > local_head_slot;
    bool synced = has_network_finalized && !behind_finalized && !has_orphans;
    bool syncing = !synced;

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
        if (!allow_complete)
        {
            maybe_retry_orphan_parent_request(
                client,
                now_ms,
                should_request_parent,
                request_peer,
                pending,
                orphan_count,
                &meta);
            return;
        }
        lantern_client_set_sync_state_logged(client, LANTERN_SYNC_STATE_SYNCED, "head caught finalized");
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
                local_head_slot,
                target_slot,
                duration,
                client->sync_imported_blocks);
            client->sync_in_progress = false;
            client->sync_started_ms = 0;
            client->sync_last_log_ms = 0;
            client->sync_last_imported_blocks = 0;
            client->sync_target_slot = 0;
        }
        maybe_retry_orphan_parent_request(
            client,
            now_ms,
            should_request_parent,
            request_peer,
            pending,
            orphan_count,
            &meta);
        return;
    }

    lantern_client_set_sync_state_logged(client, LANTERN_SYNC_STATE_SYNCING, "sync incomplete");
    if (!client->sync_in_progress)
    {
        client->sync_in_progress = true;
        client->sync_started_ms = now_ms;
        client->sync_last_log_ms = 0;
        client->sync_last_imported_blocks = 0;
        client->sync_imported_blocks = 0;
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

    uint64_t network_head = 0;
    bool has_network_head = false;
    uint64_t network_finalized = 0;
    bool has_network_finalized = false;
    network_view_snapshot_locked(
        client,
        &network_head,
        &has_network_head,
        &network_finalized,
        &has_network_finalized);

    pthread_mutex_unlock(&client->status_lock);

    maybe_log_sync_progress(
        client,
        local_slot,
        network_head,
        has_network_head,
        network_finalized,
        has_network_finalized,
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

    uint64_t network_head_slot = peer_status->head.slot;
    uint64_t network_finalized_slot = peer_status->finalized.slot;

    pthread_mutex_unlock(&client->status_lock);

    maybe_log_sync_progress(
        client,
        local_slot,
        network_head_slot,
        true,
        network_finalized_slot,
        true,
        true);
}


/**
 * @brief Update blocks request tracking state for a peer.
 *
 * @param client            Client instance
 * @param request_id        Internal request tracking ID (0 for untracked)
 * @param peer_id           Peer ID string
 * @param outcome           Request outcome
 * @param out_failure_count Output consecutive failure count
 * @param out_entry_found   Output whether peer entry was found
 * @param out_effective_peer_id Output peer ID used for logging/follow-up
 * @param out_effective_peer_id_len Output buffer length
 * @return true if tracking was updated (status_lock acquired), false otherwise
 *
 * @note Thread safety: This function acquires status_lock
 */
static bool lantern_client_update_blocks_request_tracking(
    struct lantern_client *client,
    uint64_t request_id,
    const char *peer_id,
    enum lantern_blocks_request_outcome outcome,
    uint32_t *out_failure_count,
    bool *out_entry_found,
    char *out_effective_peer_id,
    size_t out_effective_peer_id_len)
{
    if (!client || !out_failure_count || !out_entry_found || !out_effective_peer_id
        || out_effective_peer_id_len == 0)
    {
        return false;
    }

    *out_failure_count = 0;
    *out_entry_found = false;
    out_effective_peer_id[0] = '\0';

    const size_t peer_cap = sizeof(((struct lantern_peer_status_entry *)0)->peer_id);
    if (pthread_mutex_lock(&client->status_lock) != 0)
    {
        return false;
    }

    bool tracking_matched = request_id == 0u;
    if (request_id != 0u && client->active_blocks_request_count > 0)
    {
        for (size_t i = 0; i < client->active_blocks_request_count; ++i)
        {
            struct lantern_active_blocks_request *request = &client->active_blocks_requests[i];
            if (request->request_id != request_id)
            {
                continue;
            }
            copy_peer_id_text(request->peer_id, out_effective_peer_id, out_effective_peer_id_len);
            size_t last = client->active_blocks_request_count - 1u;
            if (i != last)
            {
                client->active_blocks_requests[i] = client->active_blocks_requests[last];
            }
            client->active_blocks_request_count = last;
            tracking_matched = true;
            break;
        }
    }

    if (out_effective_peer_id[0] == '\0')
    {
        copy_peer_id_text(peer_id, out_effective_peer_id, out_effective_peer_id_len);
    }

    if (out_effective_peer_id[0] == '\0')
    {
        pthread_mutex_unlock(&client->status_lock);
        return true;
    }

    if (!tracking_matched)
    {
        pthread_mutex_unlock(&client->status_lock);
        return true;
    }

    for (size_t i = 0; i < client->peer_status_count; ++i)
    {
        struct lantern_peer_status_entry *entry = &client->peer_status_entries[i];
        if (strncmp(entry->peer_id, out_effective_peer_id, peer_cap) == 0)
        {
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
                break;
            default:
                break;
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
static void lantern_client_handle_pending_parent_request_result(
    struct lantern_client *client,
    const LanternRoot *request_roots,
    size_t root_count,
    enum lantern_blocks_request_outcome outcome)
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

    struct lantern_pending_block_list *list = &client->pending_blocks;
    bool retry_later =
        outcome == LANTERN_BLOCKS_REQUEST_FAILED || outcome == LANTERN_BLOCKS_REQUEST_EMPTY;
    uint64_t retry_after_ms = retry_later ? monotonic_millis() : 0u;

    for (size_t i = 0; i < list->length; ++i)
    {
        struct lantern_pending_block *entry = &list->items[i];
        bool matches = false;
        for (size_t j = 0; j < root_count; ++j)
        {
            if (lantern_root_is_zero(&request_roots[j]))
            {
                continue;
            }
            if (memcmp(entry->parent_root.bytes, request_roots[j].bytes, LANTERN_ROOT_SIZE) == 0)
            {
                matches = true;
                break;
            }
        }
        if (!matches)
        {
            continue;
        }

        if (retry_later)
        {
            entry->parent_requested = true;
            entry->parent_requested_ms = retry_after_ms;
        }
        else
        {
            entry->parent_requested = false;
            entry->parent_requested_ms = 0;
        }
    }

    lantern_client_unlock_pending(client, locked);
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
        return LANTERN_CLIENT_ERR_GENESIS;
    }

    out_status->finalized = client->state.latest_finalized;
    if (client->has_fork_choice)
    {
        const LanternCheckpoint *fork_finalized =
            lantern_fork_choice_latest_finalized(&client->fork_choice);
        if (fork_finalized && !lantern_root_is_zero(&fork_finalized->root))
        {
            out_status->finalized = *fork_finalized;
        }
    }

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
    if (!client || !status || !client->has_fork_choice)
    {
        return;
    }

    const LanternRoot *anchor_root = lantern_fork_choice_anchor_root(&client->fork_choice);
    uint64_t anchor_slot = 0;
    if (!anchor_root
        || lantern_fork_choice_anchor_slot(&client->fork_choice, &anchor_slot) != 0)
    {
        return;
    }

    if (status->head.slot == anchor_slot && lantern_root_is_zero(&status->head.root))
    {
        status->head.root = *anchor_root;
    }
    if (status->finalized.slot == anchor_slot
        && lantern_root_is_zero(&status->finalized.root))
    {
        status->finalized.root = *anchor_root;
    }
}


/**
 * Handle an incoming status message from a peer.
 *
 * @spec subspecs/networking/reqresp/message.py - Status protocol
 *
 * Processes a peer's status message, updates peer tracking, records
 * sync progress, and may proactively seed backfill for an ahead peer's head.
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
        error = LIBP2P_HOST_ERR_INTERNAL;
    }

    if (peer_copy[0] != '\0')
    {
        lantern_client_status_request_failed(client, peer_copy);
    }

    bool first_failure = record_status_failure_peer_id(client, peer_copy);
    log_status_failure(client, peer_copy, error, first_failure);

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

static int signed_block_copy(
    LanternSignedBlock *dst,
    const LanternSignedBlock *src)
{
    if (!dst || !src)
    {
        return -1;
    }

    lantern_signed_block_reset(dst);
    lantern_signed_block_init(dst);

    dst->block.slot = src->block.slot;
    dst->block.proposer_index = src->block.proposer_index;
    dst->block.parent_root = src->block.parent_root;
    dst->block.state_root = src->block.state_root;
    if (lantern_aggregated_attestations_copy(
            &dst->block.body.attestations,
            &src->block.body.attestations)
        != 0)
    {
        lantern_signed_block_reset(dst);
        lantern_signed_block_init(dst);
        return -1;
    }

    if (lantern_byte_list_copy(&dst->proof, &src->proof) != 0)
    {
        lantern_signed_block_reset(dst);
        lantern_signed_block_init(dst);
        return -1;
    }

    return 0;
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
    if (signed_block_copy(dst, block) != 0)
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

struct reqresp_range_root {
    uint64_t slot;
    LanternRoot root;
};

static size_t fork_choice_find_root_index(
    const LanternForkChoice *fork_choice,
    const LanternRoot *root)
{
    if (!fork_choice || !root || !fork_choice->blocks)
    {
        return SIZE_MAX;
    }
    for (size_t i = 0; i < fork_choice->block_len; ++i)
    {
        if (memcmp(fork_choice->blocks[i].root.bytes, root->bytes, LANTERN_ROOT_SIZE) == 0)
        {
            return i;
        }
    }
    return SIZE_MAX;
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


static int import_block_response_now(
    struct lantern_client *client,
    const LanternSignedBlock *block,
    const LanternRoot *block_root,
    const uint8_t *raw_block_ssz,
    size_t raw_block_ssz_len,
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
    bool imported = lantern_client_import_block(
        client,
        block,
        block_root,
        &meta,
        0u,
        true,
        raw_block_ssz,
        raw_block_ssz_len);
    bool pending = false;
    bool known = false;
    bool accepted = imported || block_response_was_accepted(client, block_root, &pending, &known);
    if (accepted)
    {
        lantern_log_info(
            "backfill",
            &meta,
            "slot %" PRIu64 ", %s, response %s",
            block->block.slot,
            root_hex[0] ? root_hex : "0x0",
            imported ? "imported" : (pending ? "queued" : (known ? "duplicate" : "accepted")));
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
    free(job->raw_block_ssz);
    free(job);
}

static struct lantern_async_block_import_job *block_import_job_new(
    struct lantern_client *client,
    const LanternSignedBlock *block,
    const LanternRoot *block_root,
    const uint8_t *raw_block_ssz,
    size_t raw_block_ssz_len,
    const char *peer_id)
{
    if (!client || !block || !block_root || (!raw_block_ssz && raw_block_ssz_len > 0u))
    {
        return NULL;
    }

    struct lantern_async_block_import_job *job = calloc(1u, sizeof(*job));
    if (!job)
    {
        return NULL;
    }
    job->client = client;
    job->block_root = *block_root;
    snprintf(job->peer_id, sizeof(job->peer_id), "%s", peer_id ? peer_id : "");
    if (signed_block_copy(&job->block, block) != 0)
    {
        block_import_job_free(job);
        return NULL;
    }
    if (raw_block_ssz_len > 0u)
    {
        job->raw_block_ssz = malloc(raw_block_ssz_len);
        if (!job->raw_block_ssz)
        {
            block_import_job_free(job);
            return NULL;
        }
        memcpy(job->raw_block_ssz, raw_block_ssz, raw_block_ssz_len);
        job->raw_block_ssz_len = raw_block_ssz_len;
    }
    return job;
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
        if (client->block_import_queue_len > 0u)
        {
            client->block_import_queue_len -= 1u;
        }
        pthread_mutex_unlock(&client->block_import_lock);

        int rc = import_block_response_now(
            job->client,
            &job->block,
            &job->block_root,
            job->raw_block_ssz,
            job->raw_block_ssz_len,
            job->peer_id);
        if (rc != LANTERN_CLIENT_OK)
        {
            lantern_log_warn(
                "reqresp",
                &(const struct lantern_log_metadata){
                    .validator = job->client ? job->client->node_id : NULL,
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
    if (client->block_import_thread_started)
    {
        return LANTERN_CLIENT_OK;
    }
    if (pthread_mutex_init(&client->block_import_lock, NULL) != 0)
    {
        return LANTERN_CLIENT_ERR_RUNTIME;
    }
    client->block_import_lock_initialized = true;
    if (pthread_cond_init(&client->block_import_cond, NULL) != 0)
    {
        pthread_mutex_destroy(&client->block_import_lock);
        client->block_import_lock_initialized = false;
        return LANTERN_CLIENT_ERR_RUNTIME;
    }
    client->block_import_cond_initialized = true;
    client->block_import_stop = false;
    if (pthread_create(&client->block_import_thread, NULL, block_import_worker_main, client) != 0)
    {
        client->block_import_stop = true;
        pthread_cond_destroy(&client->block_import_cond);
        pthread_mutex_destroy(&client->block_import_lock);
        client->block_import_cond_initialized = false;
        client->block_import_lock_initialized = false;
        return LANTERN_CLIENT_ERR_RUNTIME;
    }
    client->block_import_thread_started = true;
    return LANTERN_CLIENT_OK;
}

void lantern_client_block_importer_stop(struct lantern_client *client)
{
    if (!client)
    {
        return;
    }
    if (client->block_import_lock_initialized
        && pthread_mutex_lock(&client->block_import_lock) == 0)
    {
        client->block_import_stop = true;
        if (client->block_import_cond_initialized)
        {
            pthread_cond_broadcast(&client->block_import_cond);
        }
        pthread_mutex_unlock(&client->block_import_lock);
    }
    if (client->block_import_thread_started)
    {
        pthread_join(client->block_import_thread, NULL);
        client->block_import_thread_started = false;
    }

    struct lantern_async_block_import_job *job = client->block_import_head;
    while (job)
    {
        struct lantern_async_block_import_job *next = job->next;
        block_import_job_free(job);
        job = next;
    }
    client->block_import_head = NULL;
    client->block_import_tail = NULL;
    client->block_import_queue_len = 0u;

    if (client->block_import_cond_initialized)
    {
        pthread_cond_destroy(&client->block_import_cond);
        client->block_import_cond_initialized = false;
    }
    if (client->block_import_lock_initialized)
    {
        pthread_mutex_destroy(&client->block_import_lock);
        client->block_import_lock_initialized = false;
    }
    client->block_import_stop = true;
}

static int enqueue_block_import_job(
    struct lantern_client *client,
    struct lantern_async_block_import_job *job)
{
    if (!client || !job || !client->block_import_thread_started)
    {
        return -1;
    }
    if (pthread_mutex_lock(&client->block_import_lock) != 0)
    {
        return -1;
    }
    if (client->block_import_stop
        || client->block_import_queue_len >= ASYNC_BLOCK_IMPORT_QUEUE_LIMIT)
    {
        pthread_mutex_unlock(&client->block_import_lock);
        return -1;
    }
    job->next = NULL;
    if (client->block_import_tail)
    {
        client->block_import_tail->next = job;
    }
    else
    {
        client->block_import_head = job;
    }
    client->block_import_tail = job;
    client->block_import_queue_len += 1u;
    pthread_cond_signal(&client->block_import_cond);
    pthread_mutex_unlock(&client->block_import_lock);
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

    LanternSignedBlockList storage_blocks;
    lantern_signed_block_list_init(&storage_blocks);
    if (client->data_dir && client->data_dir[0] != '\0')
    {
        if (lantern_storage_collect_blocks(
                client->data_dir,
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
    struct reqresp_range_root descending[LANTERN_MAX_REQUEST_BLOCKS];
    size_t descending_count = 0;

    bool state_locked = lantern_client_lock_state(client);
    if (state_locked && client->has_fork_choice)
    {
        LanternRoot head_root = {0};
        if (lantern_fork_choice_current_head(&client->fork_choice, &head_root) == 0)
        {
            size_t index = fork_choice_find_root_index(&client->fork_choice, &head_root);
            for (size_t depth = 0;
                 index != SIZE_MAX
                 && index < client->fork_choice.block_len
                 && depth < client->fork_choice.block_len
                 && descending_count < LANTERN_MAX_REQUEST_BLOCKS;
                 ++depth)
            {
                const struct lantern_fork_choice_block_entry *entry = &client->fork_choice.blocks[index];
                if (entry->slot < start_slot)
                {
                    break;
                }
                if ((entry->slot - start_slot) < count && !lantern_root_is_zero(&entry->root))
                {
                    descending[descending_count].slot = entry->slot;
                    descending[descending_count].root = entry->root;
                    descending_count += 1u;
                }
                index = fork_choice_find_root_index(&client->fork_choice, &entry->parent_root);
            }
        }
    }
    lantern_client_unlock_state(client, state_locked);

    if (descending_count == 0u)
    {
        return LANTERN_CLIENT_OK;
    }

    struct reqresp_range_root ascending[LANTERN_MAX_REQUEST_BLOCKS];
    size_t root_count = 0;
    for (size_t i = descending_count; i > 0u; --i)
    {
        ascending[root_count++] = descending[i - 1u];
    }

    bool have_previous = false;
    uint64_t previous_slot = 0;
    LanternRoot previous_root = {0};
    for (size_t i = 0; i < root_count; ++i)
    {
        LanternSignedBlockList one;
        lantern_signed_block_list_init(&one);
        int rc = reqresp_collect_blocks(context, &ascending[i].root, 1u, &one);
        if (rc != LANTERN_CLIENT_OK)
        {
            lantern_signed_block_list_reset(&one);
            return rc;
        }
        if (one.length == 0u)
        {
            lantern_signed_block_list_reset(&one);
            break;
        }

        const LanternSignedBlock *block = &one.blocks[0];
        if (block->block.slot < start_slot || (block->block.slot - start_slot) >= count)
        {
            lantern_signed_block_list_reset(&one);
            break;
        }
        if (have_previous && block->block.slot <= previous_slot)
        {
            lantern_signed_block_list_reset(&one);
            break;
        }
        if (have_previous
            && memcmp(block->block.parent_root.bytes, previous_root.bytes, LANTERN_ROOT_SIZE) != 0)
        {
            lantern_signed_block_list_reset(&one);
            break;
        }
        if (signed_block_list_append_copy(out_blocks, block) != 0)
        {
            lantern_signed_block_list_reset(&one);
            return LANTERN_CLIENT_ERR_ALLOC;
        }
        previous_slot = block->block.slot;
        previous_root = ascending[i].root;
        have_previous = true;
        lantern_signed_block_list_reset(&one);
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
    const uint8_t *raw_block_ssz,
    size_t raw_block_ssz_len,
    const char *peer_id)
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
    if (!client->block_import_thread_started)
    {
        if (client->block_import_stop)
        {
            return LANTERN_CLIENT_ERR_RUNTIME;
        }
        return import_block_response_now(
            client,
            block,
            &block_root,
            raw_block_ssz,
            raw_block_ssz_len,
            peer_id);
    }

    struct lantern_async_block_import_job *job = block_import_job_new(
        client,
        block,
        &block_root,
        raw_block_ssz,
        raw_block_ssz_len,
        peer_id);
    if (!job)
    {
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
    const char *peer_id,
    const LanternRoot *roots,
    size_t root_count,
    uint64_t request_id,
    int success)
{
    if (!context)
    {
        return;
    }
    lantern_client_on_blocks_request_complete_batch_with_id(
        (struct lantern_client *)context,
        request_id,
        peer_id,
        roots,
        root_count,
        success ? LANTERN_BLOCKS_REQUEST_SUCCESS : LANTERN_BLOCKS_REQUEST_FAILED);
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
 * status message. When a materially ahead peer advertises an unknown head,
 * this path may also seed backfill by requesting that head block.
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
    uint64_t local_finalized_slot = 0;
    bool head_known = false;
    peer_status_local_view(
        client,
        &peer_status->head.root,
        &local_slot,
        &local_finalized_slot,
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
        local_slot);

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
    maybe_seed_head_request_from_status(
        client,
        peer_status,
        peer_copy,
        local_slot,
        local_finalized_slot,
        head_known);
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
    LanternCheckpoint anchor_checkpoint = peer_status->finalized;
    anchor_checkpoint.root = peer_status->head.root;

    if (lantern_fork_choice_set_anchor(
            &client->fork_choice,
            &anchor,
            &anchor_checkpoint,
            &anchor_checkpoint,
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
 * - Finalizes active request registry entry (when tracked)
 * - Updates consecutive failure counter
 * - Clears parent_requested flag on pending blocks
 *
 * @param client        Client instance
 * @param request_id    Internal request tracking ID (0 for untracked completion)
 * @param peer_id       Peer ID string
 * @param request_roots Roots that were requested
 * @param root_count    Number of requested roots
 * @param outcome       Request outcome
 *
 * @note Thread safety: This function acquires status_lock and pending_lock
 */
void lantern_client_on_blocks_request_complete_batch_with_id(
    struct lantern_client *client,
    uint64_t request_id,
    const char *peer_id,
    const LanternRoot *request_roots,
    size_t root_count,
    enum lantern_blocks_request_outcome outcome)
{
    if (!client || !client->status_lock_initialized)
    {
        return;
    }
    uint32_t failure_count = 0;
    bool entry_found = false;
    char effective_peer[sizeof(((struct lantern_peer_status_entry *)0)->peer_id)];
    effective_peer[0] = '\0';
    if (!lantern_client_update_blocks_request_tracking(
            client,
            request_id,
            peer_id,
            outcome,
            &failure_count,
            &entry_found,
            effective_peer,
            sizeof(effective_peer)))
    {
        return;
    }

    const char *peer_for_logs = effective_peer[0] ? effective_peer : peer_id;

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
            "backfill",
            &(const struct lantern_log_metadata){
                .validator = client->node_id,
                .peer = peer_for_logs && peer_for_logs[0] ? peer_for_logs : NULL},
            "response %s, roots %zu, first_root %s, entry_found %s, consecutive_failures %" PRIu32,
            outcome_text,
            root_count,
            root_hex[0] ? root_hex : "0x0",
            entry_found ? "true" : "false",
            failure_count);
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
                "response %s, roots %zu, first_root %s, entry_found %s, consecutive_failures %" PRIu32,
                outcome_text,
                root_count,
                root_hex[0] ? root_hex : "0x0",
                entry_found ? "true" : "false",
                failure_count);
        }
        else
        {
            lantern_log_warn(
                "backfill",
                &(const struct lantern_log_metadata){
                    .validator = client->node_id,
                    .peer = peer_for_logs && peer_for_logs[0] ? peer_for_logs : NULL},
                "request failed, peer %s, reason: %s, roots %zu, first_root %s"
                ", consecutive_failures %" PRIu32,
                peer_for_logs && peer_for_logs[0] ? peer_for_logs : "-",
                outcome_text,
                root_count,
                root_hex[0] ? root_hex : "0x0",
                failure_count);
        }
    }

    lantern_client_handle_pending_parent_request_result(
        client,
        request_roots,
        root_count,
        outcome);

    if (outcome == LANTERN_BLOCKS_REQUEST_SUCCESS && peer_for_logs && peer_for_logs[0] != '\0')
    {
        lantern_client_request_pending_parent_after_blocks(
            client,
            peer_for_logs,
            first_root);
    }
    else if (first_root && outcome != LANTERN_BLOCKS_REQUEST_SUCCESS)
    {
        /*
         * On failures, immediately rescan pending parents without pinning to
         * the previous peer. This lets peer selection rotate away from a peer
         * that repeatedly times out or lacks the requested branch.
         */
        lantern_client_request_pending_parent_after_blocks(
            client,
            NULL,
            first_root);
    }
}

void lantern_client_on_blocks_request_complete_batch(
    struct lantern_client *client,
    const char *peer_id,
    const LanternRoot *request_roots,
    size_t root_count,
    enum lantern_blocks_request_outcome outcome)
{
    lantern_client_on_blocks_request_complete_batch_with_id(
        client,
        0u,
        peer_id,
        request_roots,
        root_count,
        outcome);
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
