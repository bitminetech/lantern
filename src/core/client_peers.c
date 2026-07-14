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
 */

#include "client_internal.h"

#include <pthread.h>
#include <stdlib.h>
#include <string.h>

#include "lantern/support/strings.h"


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

    const size_t peer_cap = sizeof(((struct lantern_peer_status_entry *)0)->peer_id);
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

    (void)lantern_string_copy(entry->peer_id, sizeof(entry->peer_id), peer_id);

    return entry;
}


/* ============================================================================
 * Vote Metric Management
 * ============================================================================ */

/**
 * Record a vote delivery from a peer.
 *
 * @param client   Client instance
 * @param peer_id  Peer ID that sent the vote
 * @param vote     Vote that was received (may be NULL)
 *
 * @note Thread safety: This function acquires status_lock
 */
void lantern_client_note_vote_delivery(
    struct lantern_client *client,
    const char *peer_id,
    const LanternSignedVote *vote)
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
        lantern_client_ensure_status_entry_locked(client, peer_id);

    if (entry)
    {
        if (entry->votes_received < UINT64_MAX)
        {
            entry->votes_received += 1u;
        }
        if (vote)
        {
            entry->last_vote_validator_id = vote->data.validator_id;
            entry->last_vote_slot = vote->data.slot;
        }
    }

    pthread_mutex_unlock(&client->status_lock);
}


/**
 * Record the outcome of processing a vote from a peer.
 *
 * @param client    Client instance
 * @param peer_id   Peer ID that sent the vote
 * @param vote      Vote that was processed (may be NULL)
 * @param accepted  True if vote was accepted, false if rejected
 *
 * @note Thread safety: This function acquires status_lock
 */
void lantern_client_note_vote_outcome(
    struct lantern_client *client,
    const char *peer_id,
    const LanternSignedVote *vote,
    bool accepted)
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
        lantern_client_ensure_status_entry_locked(client, peer_id);

    if (entry)
    {
        if (accepted)
        {
            if (entry->votes_accepted < UINT64_MAX)
            {
                entry->votes_accepted += 1u;
            }
        }
        else
        {
            if (entry->votes_rejected < UINT64_MAX)
            {
                entry->votes_rejected += 1u;
            }
        }

        if (vote)
        {
            entry->last_vote_validator_id = vote->data.validator_id;
            entry->last_vote_slot = vote->data.slot;
        }
    }

    pthread_mutex_unlock(&client->status_lock);
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
 * Note that a status request has failed.
 *
 * @param client   Client instance
 * @param peer_id  Peer ID the request was for
 * @return true for the first failure since the peer's last successful status
 *
 * @note Thread safety: This function acquires status_lock
 */
bool lantern_client_status_request_failed(
    struct lantern_client *client,
    const char *peer_id)
{
    if (!client || !peer_id || !peer_id[0] || !client->status_lock_initialized)
    {
        return true;
    }

    if (pthread_mutex_lock(&client->status_lock) != 0)
    {
        return true;
    }

    struct lantern_peer_status_entry *entry =
        lantern_client_find_status_entry_locked(client, peer_id);
    bool first_failure = !entry || !entry->status_request_failed;

    if (entry)
    {
        entry->status_request_inflight = false;
        entry->status_request_failed = true;
    }

    pthread_mutex_unlock(&client->status_lock);
    return first_failure;
}
