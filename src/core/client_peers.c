/**
 * @file client_peers.c
 * @brief Peer status and vote metric tracking
 *
 * Implements peer status entry management and vote metrics tracking
 * for connected peers.
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

#include <pthread.h>
#include <stdlib.h>
#include <string.h>

#include "lantern/support/strings.h"


/* ============================================================================
 * Peer ID Utilities
 * ============================================================================ */

/**
 * Get the capacity for peer ID strings.
 *
 * @return Size of peer_id buffer in lantern_peer_status_entry
 *
 * @note Thread safety: This function is thread-safe
 */
size_t lantern_peer_id_capacity(void)
{
    return sizeof(((struct lantern_peer_status_entry *)0)->peer_id);
}


/* ============================================================================
 * Peer Status Entry Management
 * ============================================================================ */

/**
 * Find a peer status entry by peer ID.
 *
 * @param client   Client instance
 * @param peer_id  Peer ID to find
 * @return Pointer to entry if found, NULL otherwise
 *
 * @note Thread safety: Caller must hold status_lock
 */
struct lantern_peer_status_entry *lantern_client_find_status_entry_locked(
    struct lantern_client *client,
    const char *peer_id)
{
    if (!client || !peer_id || !peer_id[0])
    {
        return NULL;
    }

    const size_t peer_cap = lantern_peer_id_capacity();
    for (size_t i = 0; i < client->peer_status_count; ++i)
    {
        struct lantern_peer_status_entry *entry = &client->peer_status_entries[i];
        if (strncmp(entry->peer_id, peer_id, peer_cap) == 0)
        {
            return entry;
        }
    }

    return NULL;
}


/**
 * Find or create a peer status entry.
 *
 * @param client   Client instance
 * @param peer_id  Peer ID to find or create
 * @return Pointer to entry, NULL on failure
 *
 * @note Thread safety: Caller must hold status_lock
 */
struct lantern_peer_status_entry *lantern_client_ensure_status_entry_locked(
    struct lantern_client *client,
    const char *peer_id)
{
    if (!client || !peer_id || !peer_id[0])
    {
        return NULL;
    }

    struct lantern_peer_status_entry *entry =
        lantern_client_find_status_entry_locked(client, peer_id);
    if (entry)
    {
        return entry;
    }

    if (client->peer_status_count == client->peer_status_capacity)
    {
        size_t new_capacity = client->peer_status_capacity == 0
            ? 4u
            : client->peer_status_capacity * 2u;

        if (new_capacity > (SIZE_MAX / sizeof(*client->peer_status_entries)))
        {
            return NULL;
        }

        struct lantern_peer_status_entry *grown = realloc(
            client->peer_status_entries,
            new_capacity * sizeof(*client->peer_status_entries));
        if (!grown)
        {
            return NULL;
        }

        memset(
            grown + client->peer_status_capacity,
            0,
            (new_capacity - client->peer_status_capacity) * sizeof(*grown));

        client->peer_status_entries = grown;
        client->peer_status_capacity = new_capacity;
    }

    entry = &client->peer_status_entries[client->peer_status_count++];
    memset(entry, 0, sizeof(*entry));

    const size_t peer_cap = lantern_peer_id_capacity();
    (void)lantern_string_copy(entry->peer_id, peer_cap, peer_id);

    lantern_client_register_vote_peer(client, peer_id);

    return entry;
}


/* ============================================================================
 * Vote Metric Management
 * ============================================================================ */

/**
 * Find or create a peer vote metric entry.
 *
 * @param client   Client instance
 * @param peer_id  Peer ID to find or create
 * @return Pointer to entry, NULL on failure
 *
 * @note Thread safety: Caller must hold peer_vote_lock
 */
struct lantern_peer_vote_metric *lantern_client_ensure_vote_metric_locked(
    struct lantern_client *client,
    const char *peer_id)
{
    if (!client || !peer_id || !peer_id[0])
    {
        return NULL;
    }

    struct lantern_peer_vote_metric *entry = NULL;
    const size_t peer_cap = sizeof(((struct lantern_peer_vote_metric *)0)->peer_id);
    for (size_t i = 0; i < client->peer_vote_stats_len; ++i)
    {
        entry = &client->peer_vote_stats[i];
        if (strncmp(entry->peer_id, peer_id, peer_cap) == 0)
        {
            return entry;
        }
    }

    size_t new_capacity = client->peer_vote_stats_cap == 0
        ? 4u
        : client->peer_vote_stats_cap * 2u;

    if (new_capacity < client->peer_vote_stats_cap
        || new_capacity > (SIZE_MAX / sizeof(*client->peer_vote_stats)))
    {
        return NULL;
    }

    if (client->peer_vote_stats_len == client->peer_vote_stats_cap)
    {
        struct lantern_peer_vote_metric *grown = realloc(
            client->peer_vote_stats,
            new_capacity * sizeof(*client->peer_vote_stats));
        if (!grown)
        {
            return NULL;
        }

        memset(
            grown + client->peer_vote_stats_cap,
            0,
            (new_capacity - client->peer_vote_stats_cap) * sizeof(*grown));

        client->peer_vote_stats = grown;
        client->peer_vote_stats_cap = new_capacity;
    }

    entry = &client->peer_vote_stats[client->peer_vote_stats_len++];
    memset(entry, 0, sizeof(*entry));

    (void)lantern_string_copy(entry->peer_id, peer_cap, peer_id);

    return entry;
}


/**
 * Register a peer for vote tracking.
 *
 * @param client   Client instance
 * @param peer_id  Peer ID to register
 *
 * @note Thread safety: This function acquires peer_vote_lock
 */
void lantern_client_register_vote_peer(
    struct lantern_client *client,
    const char *peer_id)
{
    if (!client || !peer_id || !peer_id[0] || !client->peer_vote_lock_initialized)
    {
        return;
    }

    if (pthread_mutex_lock(&client->peer_vote_lock) != 0)
    {
        return;
    }

    (void)lantern_client_ensure_vote_metric_locked(client, peer_id);

    pthread_mutex_unlock(&client->peer_vote_lock);
}


/**
 * Record a vote delivery from a peer.
 *
 * @param client   Client instance
 * @param peer_id  Peer ID that sent the vote
 * @param vote     Vote that was received (may be NULL)
 *
 * @note Thread safety: This function acquires peer_vote_lock
 */
void lantern_client_note_vote_delivery(
    struct lantern_client *client,
    const char *peer_id,
    const LanternSignedVote *vote)
{
    if (!client || !peer_id || !peer_id[0] || !client->peer_vote_lock_initialized)
    {
        return;
    }

    if (pthread_mutex_lock(&client->peer_vote_lock) != 0)
    {
        return;
    }

    struct lantern_peer_vote_metric *metrics =
        lantern_client_ensure_vote_metric_locked(client, peer_id);

    if (metrics)
    {
        if (metrics->received_total < UINT64_MAX)
        {
            metrics->received_total += 1u;
        }
        if (vote)
        {
            metrics->last_validator_id = vote->data.validator_id;
            metrics->last_slot = vote->data.slot;
        }
    }

    pthread_mutex_unlock(&client->peer_vote_lock);
}


/**
 * Record the outcome of processing a vote from a peer.
 *
 * @param client    Client instance
 * @param peer_id   Peer ID that sent the vote
 * @param vote      Vote that was processed (may be NULL)
 * @param accepted  True if vote was accepted, false if rejected
 *
 * @note Thread safety: This function acquires peer_vote_lock
 */
void lantern_client_note_vote_outcome(
    struct lantern_client *client,
    const char *peer_id,
    const LanternSignedVote *vote,
    bool accepted)
{
    if (!client || !peer_id || !peer_id[0] || !client->peer_vote_lock_initialized)
    {
        return;
    }

    if (pthread_mutex_lock(&client->peer_vote_lock) != 0)
    {
        return;
    }

    struct lantern_peer_vote_metric *metrics =
        lantern_client_ensure_vote_metric_locked(client, peer_id);

    if (metrics)
    {
        if (accepted)
        {
            if (metrics->accepted_total < UINT64_MAX)
            {
                metrics->accepted_total += 1u;
            }
        }
        else
        {
            if (metrics->rejected_total < UINT64_MAX)
            {
                metrics->rejected_total += 1u;
            }
        }

        if (vote)
        {
            metrics->last_validator_id = vote->data.validator_id;
            metrics->last_slot = vote->data.slot;
        }
    }

    pthread_mutex_unlock(&client->peer_vote_lock);
}


/* ============================================================================
 * Status Request Tracking
 * ============================================================================ */

/**
 * Try to begin a status request to a peer.
 *
 * @param client   Client instance
 * @param peer_id  Peer ID to request status from
 * @return true if request can proceed
 * @return false if request already in flight or parameters are invalid
 *
 * @note Thread safety: This function acquires status_lock
 */
bool lantern_client_try_begin_status_request(
    struct lantern_client *client,
    const char *peer_id)
{
    if (!client || !peer_id || !peer_id[0])
    {
        return false;
    }

    if (!client->status_lock_initialized)
    {
        return true;
    }

    if (pthread_mutex_lock(&client->status_lock) != 0)
    {
        return false;
    }

    bool allowed = false;
    struct lantern_peer_status_entry *entry =
        lantern_client_ensure_status_entry_locked(client, peer_id);

    if (entry && !entry->status_request_inflight)
    {
        entry->status_request_inflight = true;
        allowed = true;
    }

    pthread_mutex_unlock(&client->status_lock);
    return allowed;
}


/**
 * Note that a status request has started.
 *
 * @param client   Client instance
 * @param peer_id  Peer ID the request is for
 *
 * @note Thread safety: This function acquires status_lock
 */
void lantern_client_note_status_request_start(
    struct lantern_client *client,
    const char *peer_id)
{
    if (!client || !peer_id || !peer_id[0] || !client->status_lock_initialized)
    {
        return;
    }

    if (pthread_mutex_lock(&client->status_lock) != 0)
    {
        return;
    }

    struct lantern_peer_status_entry *entry =
        lantern_client_find_status_entry_locked(client, peer_id);

    if (entry)
    {
        lantern_client_status_request_update_locked(client, entry, peer_id, 1, "dispatch");
    }

    pthread_mutex_unlock(&client->status_lock);
}


/**
 * Note that a status request has failed.
 *
 * @param client   Client instance
 * @param peer_id  Peer ID the request was for
 *
 * @note Thread safety: This function acquires status_lock
 */
void lantern_client_status_request_failed(
    struct lantern_client *client,
    const char *peer_id)
{
    if (!client || !peer_id || !peer_id[0] || !client->status_lock_initialized)
    {
        return;
    }

    if (pthread_mutex_lock(&client->status_lock) != 0)
    {
        return;
    }

    struct lantern_peer_status_entry *entry =
        lantern_client_find_status_entry_locked(client, peer_id);

    if (entry)
    {
        entry->status_request_inflight = false;
        lantern_client_status_request_update_locked(client, entry, peer_id, -1, "failure");
    }

    pthread_mutex_unlock(&client->status_lock);
}

/**
 * Update status request tracking counters.
 *
 * @param client   Client instance
 * @param entry    Peer status entry to update
 * @param peer_id  Peer ID for logging
 * @param delta    Change to apply (+1 for start, -1 for complete)
 * @param phase    Phase name for logging
 *
 * @note Thread safety: Caller must hold status_lock
 */
void lantern_client_status_request_update_locked(
    struct lantern_client *client,
    struct lantern_peer_status_entry *entry,
    const char *peer_id,
    int delta,
    const char *phase)
{
    if (!client || !entry || delta == 0)
    {
        return;
    }

    if (delta > 0)
    {
        uint32_t increase = (uint32_t)delta;
        if (UINT32_MAX - entry->outstanding_status_requests < increase)
        {
            entry->outstanding_status_requests = UINT32_MAX;
        }
        else
        {
            entry->outstanding_status_requests += increase;
        }

        const size_t increase_size = (size_t)increase;
        if (client->status_requests_inflight_total > SIZE_MAX - increase_size)
        {
            client->status_requests_inflight_total = SIZE_MAX;
        }
        else
        {
            client->status_requests_inflight_total += increase_size;
        }

        if (client->status_requests_inflight_total > client->status_requests_peak)
        {
            client->status_requests_peak = client->status_requests_inflight_total;
        }
    }
    else
    {
        uint32_t decrease = (uint32_t)(-(int64_t)delta);
        if (entry->outstanding_status_requests > decrease)
        {
            entry->outstanding_status_requests -= decrease;
        }
        else
        {
            entry->outstanding_status_requests = 0;
        }

        if (client->status_requests_inflight_total > (size_t)decrease)
        {
            client->status_requests_inflight_total -= (size_t)decrease;
        }
        else
        {
            client->status_requests_inflight_total = 0;
        }
    }

    lantern_log_debug(
        "reqresp",
        &(const struct lantern_log_metadata){
            .validator = client->node_id,
            .peer = (peer_id && peer_id[0]) ? peer_id : NULL,
        },
        "status guard %s delta=%d peer_outstanding=%u total_outstanding=%zu "
        "peak=%zu guard_disabled=%s",
        phase ? phase : "update",
        delta,
        entry->outstanding_status_requests,
        client->status_requests_inflight_total,
        client->status_requests_peak,
        client->status_guard_disabled ? "true" : "false");
}
