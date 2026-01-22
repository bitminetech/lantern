/**
 * @file client_network.c
 * @brief Networking and connection management functions
 *
 * Implements peer connection tracking, peer dialer service, ping service,
 * and connection event handling for the lantern client.
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
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <inttypes.h>

#include <libp2p/errors.h>
#include <protocol/gossipsub/gossipsub.h>
#include <protocol/identify/protocol_identify.h>
#include <protocol/ping/protocol_ping.h>

#include "lantern/networking/libp2p.h"
#include "lantern/metrics/lean_metrics.h"
#include "lantern/support/log.h"
#include "lantern/support/string_list.h"


/* ============================================================================
 * Constants
 * ============================================================================ */

static const unsigned LANTERN_PING_INTERVAL_SECONDS = 15u;
static const uint64_t LANTERN_PING_TIMEOUT_MS = 5000ULL;


/* ============================================================================
 * Utilities
 * ============================================================================ */

/**
 * Format a peer ID as base58 text.
 *
 * @param peer     Peer ID (may be NULL)
 * @param out      Output buffer
 * @param out_len  Size of output buffer
 *
 * @note Thread safety: This function is thread-safe
 */
static void format_peer_id_text(const peer_id_t *peer, char *out, size_t out_len)
{
    if (!out || out_len == 0)
    {
        return;
    }

    out[0] = '\0';
    if (!peer)
    {
        return;
    }

    if (peer_id_to_string(peer, PEER_ID_FMT_BASE58_LEGACY, out, out_len) < 0)
    {
        out[0] = '\0';
    }
}

static lean_metrics_direction_t metrics_direction_from_inbound(bool inbound)
{
    return inbound ? LEAN_METRICS_DIR_INBOUND : LEAN_METRICS_DIR_OUTBOUND;
}

static lean_metrics_connection_result_t metrics_connection_result_from_code(int code)
{
    return (code == LIBP2P_ERR_TIMEOUT) ? LEAN_METRICS_CONN_RESULT_TIMEOUT : LEAN_METRICS_CONN_RESULT_ERROR;
}

static lean_metrics_disconnection_reason_t metrics_disconnection_reason_from_code(int reason)
{
    switch (reason)
    {
        case LIBP2P_ERR_TIMEOUT:
            return LEAN_METRICS_DISCONNECT_TIMEOUT;
        case LIBP2P_ERR_EOF:
        case LIBP2P_ERR_RESET:
            return LEAN_METRICS_DISCONNECT_REMOTE_CLOSE;
        case 0:
        case LIBP2P_ERR_CLOSED:
            return LEAN_METRICS_DISCONNECT_LOCAL_CLOSE;
        default:
            return LEAN_METRICS_DISCONNECT_ERROR;
    }
}

/* ============================================================================
 * Connection Counter Functions
 * ============================================================================ */

/**
 * Reset connection counter and connected peer list.
 *
 * @param client  Client instance
 *
 * @note Thread safety: This function acquires connection_lock if initialized
 */
void connection_counter_reset(struct lantern_client *client)
{
    if (!client)
    {
        return;
    }
    if (!client->connection_lock_initialized)
    {
        client->connected_peers = 0;
        lantern_string_list_reset(&client->connected_peer_ids);
        lantern_string_list_init(&client->connected_peer_ids);
        lantern_string_list_reset(&client->inbound_peer_ids);
        lantern_string_list_init(&client->inbound_peer_ids);
        return;
    }
    if (pthread_mutex_lock(&client->connection_lock) == 0)
    {
        client->connected_peers = 0;
        lantern_string_list_reset(&client->connected_peer_ids);
        lantern_string_list_init(&client->connected_peer_ids);
        lantern_string_list_reset(&client->inbound_peer_ids);
        lantern_string_list_init(&client->inbound_peer_ids);
        pthread_mutex_unlock(&client->connection_lock);
    }
    else
    {
        client->connected_peers = 0;
        lantern_string_list_reset(&client->connected_peer_ids);
        lantern_string_list_init(&client->connected_peer_ids);
        lantern_string_list_reset(&client->inbound_peer_ids);
        lantern_string_list_init(&client->inbound_peer_ids);
    }
}


/**
 * Update connection counter when a peer connects or disconnects.
 *
 * @param client   Client instance
 * @param delta    Change in connection count (+1 for connect, -1 for disconnect)
 * @param peer     Peer ID (may be NULL)
 * @param inbound  True if inbound connection
 * @param reason   Connection close reason code
 *
 * @note Thread safety: This function acquires connection_lock
 */
void connection_counter_update(
    struct lantern_client *client,
    int delta,
    const peer_id_t *peer,
    bool inbound,
    int reason)
{
    if (!client || !client->connection_lock_initialized)
    {
        return;
    }

    char peer_text[128];
    format_peer_id_text(peer, peer_text, sizeof(peer_text));
    size_t total = 0;
    bool was_inbound = inbound;
    if (pthread_mutex_lock(&client->connection_lock) == 0)
    {
        if (peer_text[0])
        {
            if (delta > 0)
            {
                if (!string_list_contains(&client->connected_peer_ids, peer_text))
                {
                    (void)lantern_string_list_append(&client->connected_peer_ids, peer_text);
                }
                if (inbound)
                {
                    if (!string_list_contains(&client->inbound_peer_ids, peer_text))
                    {
                        (void)lantern_string_list_append(&client->inbound_peer_ids, peer_text);
                    }
                }
                else
                {
                    string_list_remove(&client->inbound_peer_ids, peer_text);
                }
            }
            else if (delta < 0)
            {
                was_inbound = string_list_contains(&client->inbound_peer_ids, peer_text);
                string_list_remove(&client->connected_peer_ids, peer_text);
                string_list_remove(&client->inbound_peer_ids, peer_text);
            }
            client->connected_peers = client->connected_peer_ids.len;
        }
        else
        {
            if (delta > 0)
            {
                client->connected_peers += (size_t)delta;
            }
            else if (delta < 0)
            {
                size_t decrease = (size_t)(-delta);
                if (client->connected_peers > decrease)
                {
                    client->connected_peers -= decrease;
                }
                else
                {
                    client->connected_peers = 0;
                }
            }
        }
        total = client->connected_peers;
        pthread_mutex_unlock(&client->connection_lock);
    }
    else
    {
        return;
    }

    if (total == 0 && client->status_lock_initialized
        && pthread_mutex_lock(&client->status_lock) == 0)
    {
        client->sync_state = LANTERN_SYNC_STATE_IDLE;
        pthread_mutex_unlock(&client->status_lock);
    }
    lantern_log_trace(
        "network",
        &(const struct lantern_log_metadata){
            .validator = client->node_id,
            .peer = peer_text[0] ? peer_text : NULL,
        },
        "connection %s inbound=%s total=%zu reason=%d (%s)",
        delta > 0 ? "opened" : "closed",
        inbound ? "true" : "false",
        total,
        reason,
        connection_reason_text(reason));

    if (delta > 0)
    {
        lean_metrics_record_peer_connection(
            metrics_direction_from_inbound(inbound),
            LEAN_METRICS_CONN_RESULT_SUCCESS);
    }
    else if (delta < 0)
    {
        lean_metrics_record_peer_disconnection(
            metrics_direction_from_inbound(was_inbound),
            metrics_disconnection_reason_from_code(reason));
    }
}


/* ============================================================================
 * Peer Connection Checks
 * ============================================================================ */

/**
 * Check if a peer is currently connected.
 *
 * @param client   Client instance
 * @param peer_id  Peer ID string to check
 * @return true if peer is connected, false otherwise
 *
 * @note Thread safety: This function acquires connection_lock
 */
bool lantern_client_is_peer_connected(struct lantern_client *client, const char *peer_id)
{
    if (!client || !peer_id || !peer_id[0])
    {
        return false;
    }
    bool connected = false;
    if (client->connection_lock_initialized)
    {
        if (pthread_mutex_lock(&client->connection_lock) != 0)
        {
            return false;
        }
        connected = string_list_contains(&client->connected_peer_ids, peer_id);
        pthread_mutex_unlock(&client->connection_lock);
    }
    return connected;
}


/* ============================================================================
 * Status Request Functions
 * ============================================================================ */

/**
 * Request status from a peer immediately.
 *
 * @param client     Client instance
 * @param peer       Peer ID (may be NULL)
 * @param peer_text  Peer ID as string (may be NULL)
 *
 * @note Thread safety: This function acquires status_lock
 */
void request_status_now(struct lantern_client *client, const peer_id_t *peer, const char *peer_text)
{
    if (!client || !client->reqresp_running)
    {
        return;
    }
    uint64_t genesis_time = client->genesis.chain_config.genesis_time;
    if (genesis_time > 0)
    {
        uint64_t now = validator_wall_time_now_seconds();
        if (now > 0 && now < genesis_time)
        {
            struct lantern_log_metadata meta = {
                .validator = client->node_id,
                .peer = (peer_text && peer_text[0]) ? peer_text : NULL,
            };
            lantern_log_trace(
                "reqresp",
                &meta,
                "skipping status request before genesis now=%" PRIu64 " genesis_time=%" PRIu64,
                now,
                genesis_time);
            return;
        }
    }
    char peer_buffer[128];
    peer_buffer[0] = '\0';
    const char *status_peer = (peer_text && peer_text[0]) ? peer_text : NULL;
    if (!status_peer && peer)
    {
        format_peer_id_text(peer, peer_buffer, sizeof(peer_buffer));
        status_peer = peer_buffer[0] ? peer_buffer : NULL;
    }
    if (status_peer && !lantern_client_is_peer_connected(client, status_peer))
    {
        lantern_log_trace(
            "reqresp",
            &(const struct lantern_log_metadata){
                .validator = client->node_id,
                .peer = status_peer,
            },
            "cannot request status; peer is not connected");
        return;
    }

    struct lantern_log_metadata meta = {
        .validator = client->node_id,
        .peer = status_peer,
    };

    bool guard_claimed = false;
    bool guard_enabled = !client->status_guard_disabled;
    if (status_peer && client->status_lock_initialized && guard_enabled)
    {
        guard_claimed = lantern_client_try_begin_status_request(client, status_peer);
        if (!guard_claimed)
        {
            lantern_log_trace(
                "reqresp",
                &meta,
                "status request already in flight; skipping");
            return;
        }
    }
    else if (status_peer && client->status_guard_disabled)
    {
        lantern_log_debug(
            "reqresp",
            &meta,
            "status guard disabled; allowing concurrent request");
    }

    int status_rc = lantern_reqresp_service_request_status(&client->reqresp, peer, status_peer);
    if (status_peer)
    {
        const char *msg = (status_rc == 0)
            ? "initiated status request to peer"
            : "unable to initiate status request to peer";
        lantern_log_trace(
            "reqresp",
            &meta,
            "%s",
            msg);
    }
    else if (status_rc != 0)
    {
        lantern_log_trace(
            "reqresp",
            &(const struct lantern_log_metadata){
                .validator = client->node_id},
            "unable to initiate status request to peer");
    }
    else
    {
        lantern_log_trace(
            "reqresp",
            &(const struct lantern_log_metadata){
                .validator = client->node_id},
            "initiated status request to peer");
    }
    if (status_peer)
    {
        if (status_rc == 0)
        {
            lantern_client_note_status_request_start(client, status_peer);
        }
        else
        {
            lantern_client_status_request_failed(client, status_peer);
        }
    }
}


/* ============================================================================
 * Address Utilities
 * ============================================================================ */

/**
 * Check if a listen address is unspecified (0.0.0.0 or ::).
 *
 * @param addr  Listen address string
 * @return true if unspecified, false otherwise
 *
 * @note Thread safety: This function is thread-safe
 */
bool listen_address_is_unspecified(const char *addr)
{
    if (!addr || !addr[0])
    {
        return true;
    }
    if (strstr(addr, "/ip4/0.0.0.0/") != NULL)
    {
        return true;
    }
    if (strstr(addr, "/ip6/::/") != NULL)
    {
        return true;
    }
    return false;
}


/**
 * Adopt listen address from validator config if current address is unspecified.
 *
 * @param client  Client instance
 *
 * @note Thread safety: This function is thread-safe
 */
void adopt_validator_listen_address(struct lantern_client *client)
{
    if (!client || !client->assigned_validators)
    {
        return;
    }
    const char *current = client->listen_address;
    if (!listen_address_is_unspecified(current))
    {
        return;
    }
    const struct lantern_validator_config_enr *enr = &client->assigned_validators->enr;
    if (!enr->ip || *enr->ip == '\0' || enr->quic_port == 0)
    {
        return;
    }
    const char *fmt = strchr(enr->ip, ':') ? "/ip6/%s/udp/%u/quic-v1" : "/ip4/%s/udp/%u/quic-v1";
    char derived[128];
    int written = snprintf(derived, sizeof(derived), fmt, enr->ip, (unsigned)enr->quic_port);
    if (written <= 0 || (size_t)written >= sizeof(derived))
    {
        lantern_log_warn(
            "network",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to derive listen address from ENR ip=%s port=%u",
            enr->ip,
            (unsigned)enr->quic_port);
        return;
    }
    if (set_owned_string(&client->listen_address, derived) != 0)
    {
        lantern_log_warn(
            "network",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to apply derived listen address %s",
            derived);
        return;
    }
    lantern_log_info(
        "network",
        &(const struct lantern_log_metadata){.validator = client->node_id},
        "using validator ENR listen multiaddr %s",
        client->listen_address);
}


/**
 * Dial a multiaddr using the identify protocol.
 *
 * @param client      Client instance
 * @param multiaddr   Multiaddr to dial
 * @param peer_label  Label for logging
 *
 * @note Thread safety: This function is thread-safe
 */
void identify_dial_multiaddr(
    struct lantern_client *client,
    const char *multiaddr,
    const char *peer_label)
{
    if (!client || !client->network.host || !multiaddr || multiaddr[0] == '\0')
    {
        return;
    }

    libp2p_stream_t *stream = NULL;
    int rc = libp2p_host_dial_protocol_blocking(
        client->network.host,
        multiaddr,
        LIBP2P_IDENTIFY_PROTO_ID,
        LANTERN_PEER_DIAL_TIMEOUT_MS,
        &stream);

    if (rc == 0 && stream)
    {
        libp2p_stream_free(stream);
        lantern_log_debug(
            "network",
            &(const struct lantern_log_metadata){
                .validator = client->node_id,
                .peer = peer_label,
            },
            "identify dial succeeded addr=%s",
            multiaddr);
        return;
    }

    lantern_log_trace(
        "network",
        &(const struct lantern_log_metadata){
            .validator = client->node_id,
            .peer = peer_label,
        },
        "identify dial failed rc=%d addr=%s",
        rc,
        multiaddr);
}


/* ============================================================================
 * Peer Dialer Sleep
 * ============================================================================ */

/**
 * Sleep for a number of seconds, checking stop flag periodically.
 *
 * @param client   Client instance
 * @param seconds  Number of seconds to sleep
 *
 * @note Thread safety: This function is thread-safe
 */
void peer_dialer_sleep(struct lantern_client *client, unsigned seconds)
{
    if (!client || seconds == 0u)
    {
        return;
    }
    struct timespec req = {.tv_sec = 1, .tv_nsec = 0};
    for (unsigned i = 0; i < seconds; ++i)
    {
        if (__atomic_load_n(&client->dialer_stop_flag, __ATOMIC_RELAXED) != 0)
        {
            break;
        }
        (void)nanosleep(&req, NULL);
    }
}


/**
 * Attempt to redial a peer that disconnected due to timeout.
 *
 * @param client  Client instance
 * @param peer    Peer ID to redial
 *
 * @note Thread safety: This function acquires connection_lock
 */
void redial_peer_on_timeout(struct lantern_client *client, const peer_id_t *peer)
{
    if (!client || !client->network.host || !peer)
    {
        return;
    }

    const struct lantern_enr_record_list *enrs = &client->genesis.enrs;
    if (!enrs || enrs->count == 0)
    {
        return;
    }

    char peer_text[128];
    format_peer_id_text(peer, peer_text, sizeof(peer_text));

    /* Check if we're still connected to this peer (e.g., via another connection).
     * If so, skip the redial to avoid creating duplicate connections. */
    if (peer_text[0] && lantern_client_is_peer_connected(client, peer_text))
    {
        lantern_log_debug(
            "network",
            &(const struct lantern_log_metadata){
                .validator = client->node_id,
                .peer = peer_text,
            },
            "peer still connected via another connection, skipping redial");
        return;
    }

    /* Search for the peer in genesis ENRs */
    for (size_t idx = 0; idx < enrs->count; ++idx)
    {
        const struct lantern_enr_record *record = &enrs->records[idx];
        if (!record || !record->encoded)
        {
            continue;
        }

        char multiaddr[256];
        peer_id_t enr_peer_id = {0};
        if (lantern_libp2p_enr_to_multiaddr(
                record,
                multiaddr,
                sizeof(multiaddr),
                &enr_peer_id) != 0)
        {
            continue;
        }

        int eq = peer_id_equals(peer, &enr_peer_id);
        peer_id_destroy(&enr_peer_id);

        if (eq == 1)
        {
            /* Found matching peer in genesis, redial */
            lantern_log_info(
                "network",
                &(const struct lantern_log_metadata){
                    .validator = client->node_id,
                    .peer = peer_text[0] ? peer_text : NULL,
                },
                "redialing peer after disconnect addr=%s",
                multiaddr);

            (void)lantern_libp2p_host_add_enr_peer(
                &client->network,
                record,
                LANTERN_LIBP2P_DEFAULT_PEER_TTL_MS);
            identify_dial_multiaddr(client, multiaddr, peer_text[0] ? peer_text : record->encoded);
            return;
        }
    }

    /* Peer not found in genesis ENRs - cannot redial */
    lantern_log_trace(
        "network",
        &(const struct lantern_log_metadata){
            .validator = client->node_id,
            .peer = peer_text[0] ? peer_text : NULL,
        },
        "peer not in genesis ENRs, skipping redial");
}


/* ============================================================================
 * Peer Dialer Helpers
 * ============================================================================ */

/**
 * Take a snapshot of connected peer IDs.
 *
 * @param client       Client instance
 * @param out_snapshot Output list (must be initialized)
 * @return Best-effort unique connected peer count
 *
 * @note Thread safety: This function acquires connection_lock if initialized
 */
static size_t snapshot_connected_peers(
    struct lantern_client *client,
    struct lantern_string_list *out_snapshot)
{
    if (!client || !out_snapshot || !client->connection_lock_initialized)
    {
        return 0;
    }

    size_t connected_unique = 0;
    if (pthread_mutex_lock(&client->connection_lock) == 0)
    {
        connected_unique = client->connected_peer_ids.len;
        if (lantern_string_list_copy(out_snapshot, &client->connected_peer_ids) != 0)
        {
            lantern_string_list_reset(out_snapshot);
            lantern_string_list_init(out_snapshot);
            connected_unique = client->connected_peers;
        }
        pthread_mutex_unlock(&client->connection_lock);
    }
    else
    {
        connected_unique = client->connected_peers;
    }

    return connected_unique;
}


/**
 * Get local peer ID from the libp2p host.
 *
 * @param client  Client instance
 * @return Allocated peer ID pointer, or NULL on failure
 *
 * @note Thread safety: This function is thread-safe
 */
static peer_id_t *get_local_peer_id(struct lantern_client *client)
{
    if (!client || !client->network.host)
    {
        return NULL;
    }

    peer_id_t *local_peer = NULL;
    if (libp2p_host_get_peer_id(client->network.host, &local_peer) != 0)
    {
        return NULL;
    }

    return local_peer;
}


/**
 * Compute dial target count based on genesis ENRs.
 *
 * @param enrs        Genesis ENR list
 * @param local_peer  Local peer ID (may be NULL)
 * @return Target number of connections to attempt
 *
 * @note Thread safety: This function is thread-safe
 */
static size_t compute_peer_dial_target(
    const struct lantern_enr_record_list *enrs,
    const peer_id_t *local_peer)
{
    if (!enrs || enrs->count == 0)
    {
        return 0;
    }

    size_t target = enrs->count;
    if (local_peer && local_peer->bytes && local_peer->size && target > 0)
    {
        target -= 1;
    }

    return target;
}


/**
 * Dial a peer from a genesis ENR record.
 *
 * @param client             Client instance
 * @param record             ENR record to dial
 * @param local_peer         Local peer ID (may be NULL)
 * @param connected_snapshot Snapshot of currently connected peers
 *
 * @note Thread safety: This function is thread-safe
 */
static void peer_dialer_handle_record(
    struct lantern_client *client,
    const struct lantern_enr_record *record,
    const peer_id_t *local_peer,
    const struct lantern_string_list *connected_snapshot)
{
    if (!client || !record || !record->encoded)
    {
        return;
    }

    char multiaddr[256];
    peer_id_t peer_id = {0};
    if (lantern_libp2p_enr_to_multiaddr(record, multiaddr, sizeof(multiaddr), &peer_id) != 0)
    {
        peer_id_destroy(&peer_id);
        return;
    }

    if (local_peer && peer_id_equals(local_peer, &peer_id) == 1)
    {
        peer_id_destroy(&peer_id);
        return;
    }

    char peer_text[128];
    format_peer_id_text(&peer_id, peer_text, sizeof(peer_text));

    if (peer_text[0] && connected_snapshot && string_list_contains(connected_snapshot, peer_text))
    {
        peer_id_destroy(&peer_id);
        return;
    }

    (void)lantern_libp2p_host_add_enr_peer(
        &client->network,
        record,
        LANTERN_LIBP2P_DEFAULT_PEER_TTL_MS);

    const char *peer_label = peer_text[0] ? peer_text : record->encoded;
    identify_dial_multiaddr(client, multiaddr, peer_label);

    if (client->gossip_running && client->gossip.gossipsub)
    {
        bool already_added = false;
        if (peer_text[0])
        {
            already_added = string_list_contains(&client->dialer_peers, peer_text);
        }

        if (!already_added)
        {
            libp2p_err_t perr = libp2p_gossipsub_peering_add(
                client->gossip.gossipsub,
                &peer_id);
            if (perr == LIBP2P_ERR_OK)
            {
                if (peer_text[0])
                {
                    (void)lantern_string_list_append(&client->dialer_peers, peer_text);
                }
                lantern_log_trace(
                    "network",
                    &(const struct lantern_log_metadata){
                        .validator = client->node_id,
                        .peer = peer_label,
                    },
                    "dialer added peer to gossipsub peering");
            }
        }
    }

    peer_id_destroy(&peer_id);
}


/**
 * Attempt to dial peers from genesis ENRs.
 *
 * @param client  Client instance
 *
 * @note Thread safety: This function acquires connection_lock
 */
void peer_dialer_attempt(struct lantern_client *client)
{
    if (!client || !client->network.host)
    {
        return;
    }

    const struct lantern_enr_record_list *enrs = &client->genesis.enrs;
    if (!enrs || enrs->count == 0)
    {
        return;
    }

    struct lantern_string_list connected_snapshot;
    lantern_string_list_init(&connected_snapshot);
    size_t connected_unique = snapshot_connected_peers(client, &connected_snapshot);
    peer_id_t *local_peer = get_local_peer_id(client);

    size_t target = compute_peer_dial_target(enrs, local_peer);
    if (target > 0 && connected_unique >= target)
    {
        goto cleanup;
    }

    for (size_t idx = 0; idx < enrs->count; ++idx)
    {
        if (__atomic_load_n(&client->dialer_stop_flag, __ATOMIC_RELAXED) != 0)
        {
            break;
        }

        peer_dialer_handle_record(
            client,
            &enrs->records[idx],
            local_peer,
            &connected_snapshot);
    }

cleanup:
    if (local_peer)
    {
        peer_id_destroy(local_peer);
        free(local_peer);
    }

    lantern_string_list_reset(&connected_snapshot);
}


/**
 * Peer dialer thread function.
 *
 * @param arg  Client instance as void pointer
 * @return NULL
 *
 * @note Thread safety: This function runs in its own thread
 */
static void *peer_dialer_thread(void *arg)
{
    struct lantern_client *client = (struct lantern_client *)arg;
    if (!client)
    {
        return NULL;
    }

    while (__atomic_load_n(&client->dialer_stop_flag, __ATOMIC_RELAXED) == 0)
    {
        peer_dialer_attempt(client);
        peer_dialer_sleep(client, LANTERN_PEER_DIAL_INTERVAL_SECONDS);
    }
    return NULL;
}


/**
 * Start the peer dialer service.
 *
 * @param client  Client instance
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: This function is thread-safe
 */
int start_peer_dialer(struct lantern_client *client)
{
    if (!client)
    {
        return -1;
    }
    if (client->dialer_thread_started)
    {
        return 0;
    }
    __atomic_store_n(&client->dialer_stop_flag, 0, __ATOMIC_RELAXED);
    int rc = pthread_create(&client->dialer_thread, NULL, peer_dialer_thread, client);
    if (rc != 0)
    {
        __atomic_store_n(&client->dialer_stop_flag, 1, __ATOMIC_RELAXED);
        return -1;
    }
    client->dialer_thread_started = true;
    return 0;
}


/**
 * Stop the peer dialer service.
 *
 * @param client  Client instance
 *
 * @note Thread safety: This function is thread-safe
 */
void stop_peer_dialer(struct lantern_client *client)
{
    if (!client)
    {
        return;
    }
    if (!client->dialer_thread_started)
    {
        __atomic_store_n(&client->dialer_stop_flag, 1, __ATOMIC_RELAXED);
        return;
    }
    __atomic_store_n(&client->dialer_stop_flag, 1, __ATOMIC_RELAXED);
    (void)pthread_join(client->dialer_thread, NULL);
    client->dialer_thread_started = false;
}


/* ============================================================================
 * Ping Service
 * ============================================================================ */

/**
 * Callback context for async ping dial.
 */
struct ping_dial_ctx
{
    struct lantern_client *client; /**< Client instance */
    char peer_text[128];           /**< Peer ID as text */
};


/**
 * Callback when ping stream is opened.
 *
 * @param s          Opened stream
 * @param user_data  Ping dial context
 * @param err        Error code
 *
 * @note Thread safety: This function is called from libp2p thread
 */
static void ping_on_stream_open(libp2p_stream_t *s, void *user_data, int err)
{
    struct ping_dial_ctx *ctx = (struct ping_dial_ctx *)user_data;
    if (!ctx)
    {
        if (s)
        {
            libp2p_stream_close(s);
            libp2p_stream_free(s);
        }
        return;
    }
    struct lantern_client *client = ctx->client;
    const char *peer_text = ctx->peer_text;
    if (err || !s)
    {
        lantern_log_trace(
            "network",
            &(const struct lantern_log_metadata){
                .validator = client ? client->node_id : NULL,
                .peer = peer_text[0] ? peer_text : NULL,
            },
            "ping dial failed err=%d",
            err);
        free(ctx);
        return;
    }
    /* Perform the ping roundtrip. */
    uint64_t rtt_ms = 0;
    libp2p_ping_err_t rc = libp2p_ping_roundtrip_stream(s, LANTERN_PING_TIMEOUT_MS, &rtt_ms);
    if (rc == LIBP2P_PING_OK)
    {
        lantern_log_trace(
            "network",
            &(const struct lantern_log_metadata){
                .validator = client ? client->node_id : NULL,
                .peer = peer_text[0] ? peer_text : NULL,
            },
            "ping ok rtt_ms=%llu",
            (unsigned long long)rtt_ms);
    }
    else
    {
        lantern_log_trace(
            "network",
            &(const struct lantern_log_metadata){
                .validator = client ? client->node_id : NULL,
                .peer = peer_text[0] ? peer_text : NULL,
            },
            "ping failed rc=%d",
            (int)rc);
    }
    libp2p_stream_close(s);
    libp2p_stream_free(s);
    free(ctx);
}

static bool peer_status_needs_refresh(
    struct lantern_client *client,
    const char *peer_id,
    uint64_t now_ms)
{
    if (!client || !peer_id || peer_id[0] == '\0')
    {
        return false;
    }
    if (!client->status_lock_initialized)
    {
        return true;
    }
    if (pthread_mutex_lock(&client->status_lock) != 0)
    {
        return true;
    }
    struct lantern_peer_status_entry *entry =
        lantern_client_find_status_entry_locked(client, peer_id);
    bool needs_refresh = true;
    if (entry)
    {
        if (entry->status_request_inflight)
        {
            needs_refresh = false;
        }
        else if (entry->has_status && entry->last_status_ms != 0 && now_ms >= entry->last_status_ms)
        {
            needs_refresh = (now_ms - entry->last_status_ms) > LANTERN_PEER_STATUS_STALE_MS;
        }
    }
    pthread_mutex_unlock(&client->status_lock);
    return needs_refresh;
}


/**
 * Ping all connected peers.
 *
 * @param client  Client instance
 *
 * @note Thread safety: This function acquires connection_lock
 */
static void ping_all_peers(struct lantern_client *client)
{
    if (!client || !client->network.host || !client->connection_lock_initialized)
    {
        return;
    }
    /* Take a snapshot of connected peer IDs. */
    struct lantern_string_list peers = {0};
    lantern_string_list_init(&peers);
    if (pthread_mutex_lock(&client->connection_lock) != 0)
    {
        lantern_string_list_reset(&peers);
        return;
    }
    if (lantern_string_list_copy(&peers, &client->connected_peer_ids) != 0)
    {
        pthread_mutex_unlock(&client->connection_lock);
        lantern_string_list_reset(&peers);
        return;
    }
    pthread_mutex_unlock(&client->connection_lock);

    uint64_t now_ms = monotonic_millis();
    for (size_t i = 0; i < peers.len; i++)
    {
        const char *peer_str = peers.items[i];
        if (!peer_str || peer_str[0] == '\0')
        {
            continue;
        }
        peer_id_t peer = {0};
        if (peer_id_create_from_string(peer_str, &peer) != 0)
        {
            continue;
        }
        if (peer_status_needs_refresh(client, peer_str, now_ms))
        {
            request_status_now(client, &peer, peer_str);
        }
        struct ping_dial_ctx *ctx = (struct ping_dial_ctx *)calloc(1, sizeof(*ctx));
        if (!ctx)
        {
            peer_id_destroy(&peer);
            continue;
        }
        ctx->client = client;
        strncpy(ctx->peer_text, peer_str, sizeof(ctx->peer_text) - 1);
        ctx->peer_text[sizeof(ctx->peer_text) - 1] = '\0';
        int rc = libp2p_host_open_stream_async(
            client->network.host,
            &peer,
            LIBP2P_PING_PROTO_ID,
            ping_on_stream_open,
            ctx);
        if (rc != 0)
        {
            lantern_log_trace(
                "network",
                &(const struct lantern_log_metadata){
                    .validator = client->node_id,
                    .peer = peer_str,
                },
                "ping dial request failed rc=%d",
                rc);
            free(ctx);
        }
        peer_id_destroy(&peer);
    }
    lantern_string_list_reset(&peers);
}


/**
 * Ping service thread function.
 *
 * @param arg  Client instance as void pointer
 * @return NULL
 *
 * @note Thread safety: This function runs in its own thread
 */
static void *ping_thread(void *arg)
{
    struct lantern_client *client = (struct lantern_client *)arg;
    if (!client)
    {
        return NULL;
    }
    lantern_log_info(
        "network",
        &(const struct lantern_log_metadata){.validator = client->node_id},
        "ping service started interval=%us",
        LANTERN_PING_INTERVAL_SECONDS);
    while (__atomic_load_n(&client->ping_stop_flag, __ATOMIC_RELAXED) == 0)
    {
        ping_all_peers(client);
        /* Sleep in small increments to allow quick shutdown. */
        for (unsigned i = 0;
             i < LANTERN_PING_INTERVAL_SECONDS
                 && __atomic_load_n(&client->ping_stop_flag, __ATOMIC_RELAXED) == 0;
             i++)
        {
            struct timespec ts = {.tv_sec = 1, .tv_nsec = 0};
            nanosleep(&ts, NULL);
        }
    }
    return NULL;
}


/**
 * Start the ping service.
 *
 * @param client  Client instance
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: This function is thread-safe
 */
int start_ping_service(struct lantern_client *client)
{
    if (!client)
    {
        return -1;
    }
    if (client->ping_thread_started)
    {
        return 0;
    }
    __atomic_store_n(&client->ping_stop_flag, 0, __ATOMIC_RELAXED);
    int rc = pthread_create(&client->ping_thread, NULL, ping_thread, client);
    if (rc != 0)
    {
        __atomic_store_n(&client->ping_stop_flag, 1, __ATOMIC_RELAXED);
        return -1;
    }
    client->ping_thread_started = true;
    return 0;
}


/**
 * Stop the ping service.
 *
 * @param client  Client instance
 *
 * @note Thread safety: This function is thread-safe
 */
void stop_ping_service(struct lantern_client *client)
{
    if (!client)
    {
        return;
    }
    if (!client->ping_thread_started)
    {
        __atomic_store_n(&client->ping_stop_flag, 1, __ATOMIC_RELAXED);
        return;
    }
    __atomic_store_n(&client->ping_stop_flag, 1, __ATOMIC_RELAXED);
    (void)pthread_join(client->ping_thread, NULL);
    client->ping_thread_started = false;
}


/* ============================================================================
 * Connection Events
 * ============================================================================ */

/**
 * Handle connection opened events.
 *
 * @param client   Client instance
 * @param peer     Peer ID (may be NULL)
 * @param inbound  True if inbound connection
 *
 * @note Thread safety: This function is called from libp2p thread
 */
static void handle_connection_opened_event(
    struct lantern_client *client,
    const peer_id_t *peer,
    bool inbound)
{
    if (!client)
    {
        return;
    }

    connection_counter_update(client, 1, peer, inbound, 0);

    if (!peer)
    {
        return;
    }

    char peer_text[128];
    format_peer_id_text(peer, peer_text, sizeof(peer_text));
    request_status_now(client, peer, peer_text[0] ? peer_text : NULL);
}


/**
 * Handle connection closed events.
 *
 * @param client  Client instance
 * @param peer    Peer ID (may be NULL)
 * @param reason  Disconnect reason code
 *
 * @note Thread safety: This function is called from libp2p thread
 */
static void handle_connection_closed_event(
    struct lantern_client *client,
    const peer_id_t *peer,
    int reason)
{
    if (!client)
    {
        return;
    }

    connection_counter_update(client, -1, peer, false, reason);

    if (!peer)
    {
        return;
    }

    char peer_text[128];
    format_peer_id_text(peer, peer_text, sizeof(peer_text));

    lantern_log_info(
        "network",
        &(const struct lantern_log_metadata){
            .validator = client->node_id,
            .peer = peer_text[0] ? peer_text : NULL,
        },
        "connection closed reason=%d (%s)",
        reason,
        connection_reason_text(reason));

    /* If disconnected unexpectedly, attempt to redial the peer.
     * We redial for timeout, reset, EOF, and closed reasons since the remote
     * peer may have closed due to their own timeout or network issues. */
    if (reason == LIBP2P_ERR_TIMEOUT ||
        reason == LIBP2P_ERR_RESET ||
        reason == LIBP2P_ERR_EOF ||
        reason == LIBP2P_ERR_CLOSED)
    {
        redial_peer_on_timeout(client, peer);
    }
}


/**
 * Handle dialing events.
 *
 * @param client  Client instance
 * @param peer    Peer ID (may be NULL)
 * @param addr    Multiaddr being dialed (may be NULL)
 *
 * @note Thread safety: This function is called from libp2p thread
 */
static void handle_dialing_event(
    struct lantern_client *client,
    const peer_id_t *peer,
    const char *addr)
{
    if (!client)
    {
        return;
    }

    char peer_text[128];
    format_peer_id_text(peer, peer_text, sizeof(peer_text));

    lantern_log_debug(
        "network",
        &(const struct lantern_log_metadata){
            .validator = client->node_id,
            .peer = peer_text[0] ? peer_text : NULL,
        },
        "dialing peer addr=%s",
        addr ? addr : "-");
}


/**
 * Handle outgoing connection error events.
 *
 * @param client  Client instance
 * @param peer    Peer ID (may be NULL)
 * @param code    Error code
 * @param msg     Error message (may be NULL)
 *
 * @note Thread safety: This function is called from libp2p thread
 */
static void handle_outgoing_connection_error_event(
    struct lantern_client *client,
    const peer_id_t *peer,
    int code,
    const char *msg)
{
    if (!client)
    {
        return;
    }

    char peer_text[128];
    format_peer_id_text(peer, peer_text, sizeof(peer_text));

    lantern_log_warn(
        "network",
        &(const struct lantern_log_metadata){
            .validator = client->node_id,
            .peer = peer_text[0] ? peer_text : NULL,
        },
        "outgoing connection error code=%d (%s) msg=%s",
        code,
        connection_reason_text(code),
        msg ? msg : "-");

    lean_metrics_record_peer_connection(
        LEAN_METRICS_DIR_OUTBOUND,
        metrics_connection_result_from_code(code));
}


/**
 * Handle incoming connection error events.
 *
 * @param client  Client instance
 * @param peer    Peer ID (may be NULL)
 * @param code    Error code
 * @param msg     Error message (may be NULL)
 *
 * @note Thread safety: This function is called from libp2p thread
 */
static void handle_incoming_connection_error_event(
    struct lantern_client *client,
    const peer_id_t *peer,
    int code,
    const char *msg)
{
    if (!client)
    {
        return;
    }

    char peer_text[128];
    format_peer_id_text(peer, peer_text, sizeof(peer_text));

    lantern_log_warn(
        "network",
        &(const struct lantern_log_metadata){
            .validator = client->node_id,
            .peer = peer_text[0] ? peer_text : NULL,
        },
        "incoming connection error code=%d (%s) msg=%s",
        code,
        connection_reason_text(code),
        msg ? msg : "-");

    lean_metrics_record_peer_connection(
        LEAN_METRICS_DIR_INBOUND,
        metrics_connection_result_from_code(code));
}


/**
 * Connection event callback for libp2p host.
 *
 * @param evt        Event details
 * @param user_data  Client instance
 *
 * @note Thread safety: This function is called from libp2p thread
 */
void connection_events_cb(const libp2p_event_t *evt, void *user_data)
{
    if (!evt || !user_data)
    {
        return;
    }
    struct lantern_client *client = (struct lantern_client *)user_data;
    switch (evt->kind)
    {
        case LIBP2P_EVT_CONN_OPENED:
            handle_connection_opened_event(
                client,
                evt->u.conn_opened.peer,
                evt->u.conn_opened.inbound);
            break;
        case LIBP2P_EVT_CONN_CLOSED:
            handle_connection_closed_event(
                client,
                evt->u.conn_closed.peer,
                evt->u.conn_closed.reason);
            break;
        case LIBP2P_EVT_DIALING:
            handle_dialing_event(
                client,
                evt->u.dialing.peer,
                evt->u.dialing.addr);
            break;
        case LIBP2P_EVT_OUTGOING_CONNECTION_ERROR:
            handle_outgoing_connection_error_event(
                client,
                evt->u.outgoing_conn_error.peer,
                evt->u.outgoing_conn_error.code,
                evt->u.outgoing_conn_error.msg);
            break;
        case LIBP2P_EVT_INCOMING_CONNECTION_ERROR:
            handle_incoming_connection_error_event(
                client,
                evt->u.incoming_conn_error.peer,
                evt->u.incoming_conn_error.code,
                evt->u.incoming_conn_error.msg);
            break;
        default:
            break;
    }
}
