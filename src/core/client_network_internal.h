/**
 * @file client_network_internal.h
 * @brief Internal declarations for networking and peer management
 *
 * @spec subspecs/networking/connection.py - connection management
 *
 * This header contains internal types and function declarations for
 * networking, peer status tracking, and connection management.
 * It is NOT part of the public API.
 *
 * Related files:
 * - client_network.c: Network connection management
 * - client_peers.c: Peer status tracking
 *
 * @note Lock ordering (acquire in this order to prevent deadlocks):
 *       1. state_lock
 *       2. status_lock
 *       3. pending_lock
 *       4. validator_lock
 *       5. connection_lock
 *       6. peer_vote_lock
 */

#ifndef LANTERN_CLIENT_NETWORK_INTERNAL_H
#define LANTERN_CLIENT_NETWORK_INTERNAL_H

#include "lantern/core/client.h"
#include "lantern/consensus/containers.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif


/* ============================================================================
 * Constants
 * ============================================================================ */

/** Peer dial interval in seconds */
#define LANTERN_PEER_DIAL_INTERVAL_SECONDS 5u

/** Maximum concurrent blocks requests per peer */
#define LANTERN_MAX_BLOCKS_REQUESTS_PER_PEER 1u

/** Peer dial timeout in milliseconds */
#define LANTERN_PEER_DIAL_TIMEOUT_MS 4000


/* ============================================================================
 * Internal Types
 * ============================================================================ */

/**
 * Outcome of a blocks request operation.
 */
enum lantern_blocks_request_outcome
{
    LANTERN_BLOCKS_REQUEST_SUCCESS = 0,
    LANTERN_BLOCKS_REQUEST_FAILED = 1,
    LANTERN_BLOCKS_REQUEST_ABORTED = 2,
    LANTERN_BLOCKS_REQUEST_EMPTY = 3
};

/** Peer status considered stale after this many milliseconds. */
#define LANTERN_PEER_STATUS_STALE_MS (30000u)


/**
 * Peer status tracking entry.
 *
 * @spec subspecs/networking/status.py - peer status protocol
 *
 * Tracks the status of a connected peer including their latest status
 * message and request state.
 */
struct lantern_peer_status_entry
{
    char peer_id[128];                    /**< Peer ID string */
    LanternStatusMessage status;          /**< Latest status message from peer */
    bool has_status;                      /**< True if status has been received */
    uint64_t last_status_ms;              /**< Timestamp of last status message */
    bool status_request_inflight;         /**< True if status request is pending */
    uint32_t consecutive_blocks_failures; /**< Count of consecutive request failures */
    uint32_t outstanding_status_requests; /**< Number of outstanding status requests */
    uint32_t consecutive_ping_failures;   /**< Count of consecutive ping failures */
};

/**
 * Block request context for async operations.
 *
 * @spec subspecs/networking/reqresp.py - blocks by root request
 */
struct block_request_ctx
{
    struct lantern_client *client;  /**< Client instance */
    uint64_t request_id;            /**< Internal request tracking ID */
    struct lantern_peer_id *peer_id;             /**< Peer ID structure */
    char peer_text[128];            /**< Peer ID as text */
    LanternRoot *roots;             /**< Roots being requested */
    uint32_t *depths;               /**< Backfill depth per root */
    size_t root_count;              /**< Number of roots requested */
    const char *protocol_id;        /**< Protocol ID string */
};


/**
 * Block request worker thread arguments.
 */
struct block_request_worker_args
{
    struct block_request_ctx *ctx;  /**< Request context */
    struct lantern_reqresp_stream *stream;        /**< libp2p stream */
};


/* ============================================================================
 * Peer Status Functions
 * ============================================================================ */

/**
 * Get the capacity for peer ID strings.
 *
 * @return Size of peer_id buffer in lantern_peer_status_entry
 *
 * @note Thread safety: This function is thread-safe
 */
size_t lantern_peer_id_capacity(void);


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
    const char *peer_id);


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
    const char *peer_id);


/**
 * Find a peer vote metric entry by peer ID.
 *
 * @param client   Client instance
 * @param peer_id  Peer ID to find
 * @return Pointer to entry if found, NULL otherwise
 *
 * @note Thread safety: Caller must hold peer_vote_lock
 */
struct lantern_peer_vote_metric *lantern_client_find_vote_metric_locked(
    struct lantern_client *client,
    const char *peer_id);


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
    const char *peer_id);


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
    const char *peer_id);


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
    const LanternSignedVote *vote);


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
    bool accepted);


/**
 * Try to begin a status request to a peer.
 *
 * @spec subspecs/networking/status.py - status protocol
 *
 * @param client   Client instance
 * @param peer_id  Peer ID to request status from
 * @return true if request can proceed, false if already in flight
 *
 * @note Thread safety: This function acquires status_lock
 */
bool lantern_client_try_begin_status_request(
    struct lantern_client *client,
    const char *peer_id);


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
    const char *peer_id);


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
    const char *peer_id);

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
    const char *phase);


/* ============================================================================
 * Network Functions
 * ============================================================================ */

/**
 * Reset connection counter and connected peer list.
 *
 * @param client  Client instance
 *
 * @note Thread safety: This function acquires connection_lock if initialized
 */
void connection_counter_reset(struct lantern_client *client);


/**
 * Update connection counter when a peer connects or disconnects.
 *
 * @spec subspecs/networking/connection.py - connection management
 *
 * @param client   Client instance
 * @param delta    Change in connection count (+1 for connect, -1 for disconnect)
 * @param conn     Transport connection handle (may be NULL)
 * @param peer     Peer ID (may be NULL)
 * @param inbound  True if inbound connection
 * @param reason   Connection close reason code
 *
 * @note Thread safety: This function acquires connection_lock
 */
void connection_counter_update(
    struct lantern_client *client,
    int delta,
    const void *conn,
    const struct lantern_peer_id *peer,
    bool inbound,
    int reason);

bool connection_tie_break_prefers_inbound(
    const uint8_t *local_peer_id,
    size_t local_peer_id_len,
    const struct lantern_peer_id *remote_peer);


/**
 * Check if a peer is currently connected.
 *
 * @param client   Client instance
 * @param peer_id  Peer ID string to check
 * @return true if peer is connected, false otherwise
 *
 * @note Thread safety: This function acquires connection_lock
 */
bool lantern_client_is_peer_connected(struct lantern_client *client, const char *peer_id);


/**
 * Request status from a peer immediately.
 *
 * @spec subspecs/networking/status.py - status protocol
 *
 * @param client     Client instance
 * @param peer       Peer ID (may be NULL)
 * @param peer_text  Peer ID as string (may be NULL)
 *
 * @note Thread safety: This function acquires status_lock
 */
void request_status_now(struct lantern_client *client, const struct lantern_peer_id *peer, const char *peer_text);


/**
 * Check if a listen address is unspecified (0.0.0.0 or ::).
 *
 * @param addr  Listen address string
 * @return true if unspecified, false otherwise
 *
 * @note Thread safety: This function is thread-safe
 */
bool listen_address_is_unspecified(const char *addr);


/**
 * Adopt listen address from validator config if current address is unspecified.
 *
 * @param client  Client instance
 *
 * @note Thread safety: This function is thread-safe
 */
void adopt_validator_listen_address(struct lantern_client *client);


/**
 * Dial a multiaddr using the identify protocol.
 *
 * @spec subspecs/networking/discovery.py - peer discovery
 *
 * @param client      Client instance
 * @param multiaddr   Multiaddr to dial
 * @param peer_label  Label for logging
 *
 * @note Thread safety: This function is thread-safe
 */
void identify_dial_multiaddr(struct lantern_client *client, const char *multiaddr, const char *peer_label);


/**
 * Sleep for a number of seconds, checking stop flag periodically.
 *
 * @param client   Client instance
 * @param seconds  Number of seconds to sleep
 *
 * @note Thread safety: This function is thread-safe
 */
void peer_dialer_sleep(struct lantern_client *client, unsigned seconds);


/**
 * Attempt to redial a peer that disconnected due to timeout.
 *
 * @param client  Client instance
 * @param peer    Peer ID to redial
 *
 * @note Thread safety: This function acquires connection_lock
 */
void redial_peer_on_timeout(struct lantern_client *client, const struct lantern_peer_id *peer);


/**
 * Redial a peer by text peer id, bypassing the connected-peer guard. Used by
 * the req/resp layer to recover when stream opens keep failing against a peer
 * whose registry entry was lost while a zombie connection keeps the peer
 * looking connected.
 *
 * @param client        Client instance
 * @param peer_id_text  Text form of the peer id to redial
 */
void lantern_client_redial_peer_by_text(struct lantern_client *client, const char *peer_id_text);


/**
 * Attempt to dial peers from genesis ENRs.
 *
 * @spec subspecs/networking/discovery.py - peer discovery
 *
 * @param client  Client instance
 *
 * @note Thread safety: This function acquires connection_lock
 */
void peer_dialer_attempt(struct lantern_client *client);

void peer_status_refresh(struct lantern_client *client);


/**
 * Start the peer dialer service.
 *
 * @param client  Client instance
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: This function is thread-safe
 */
int start_peer_dialer(struct lantern_client *client);


/**
 * Stop the peer dialer service.
 *
 * @param client  Client instance
 *
 * @note Thread safety: This function is thread-safe
 */
void stop_peer_dialer(struct lantern_client *client);


/**
 * Connection event callback for the c-lean-libp2p host.
 *
 * @param network    Lantern host wrapper
 * @param evt        Event details
 * @param user_data  Client instance
 *
 * @note Thread safety: This function is called from libp2p thread
 */
void connection_events_cb(
    struct lantern_libp2p_host *network,
    const libp2p_host_event_t *evt,
    void *user_data);


#ifdef __cplusplus
}
#endif

#endif /* LANTERN_CLIENT_NETWORK_INTERNAL_H */
