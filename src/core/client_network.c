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

#include "lantern/networking/libp2p.h"
#include "lantern/metrics/lean_metrics.h"
#include "lantern/support/log.h"
#include "lantern/support/string_list.h"


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
static void format_peer_id_text(const struct lantern_peer_id *peer, char *out, size_t out_len)
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

    if (lantern_peer_id_to_text(peer, out, out_len) < 0)
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
    (void)code;
    return LEAN_METRICS_CONN_RESULT_ERROR;
}

static lean_metrics_disconnection_reason_t metrics_disconnection_reason_from_code(int reason)
{
    if (reason == LIBP2P_HOST_OK)
    {
        return LEAN_METRICS_DISCONNECT_LOCAL_CLOSE;
    }
    if (reason == LIBP2P_HOST_ERR_CLOSED)
    {
        return LEAN_METRICS_DISCONNECT_REMOTE_CLOSE;
    }
    return LEAN_METRICS_DISCONNECT_ERROR;
}

bool connection_tie_break_prefers_inbound(
    const uint8_t *local_peer_id,
    size_t local_peer_id_len,
    const struct lantern_peer_id *remote_peer)
{
    if (!local_peer_id || local_peer_id_len == 0 || !remote_peer || remote_peer->len == 0)
    {
        return false;
    }

    size_t min_len = local_peer_id_len < remote_peer->len ? local_peer_id_len : remote_peer->len;
    int cmp = memcmp(local_peer_id, remote_peer->bytes, min_len);
    if (cmp == 0)
    {
        if (local_peer_id_len > remote_peer->len)
        {
            cmp = 1;
        }
        else if (local_peer_id_len < remote_peer->len)
        {
            cmp = -1;
        }
    }
    return cmp > 0;
}

/* ============================================================================
 * Connection Counter Functions
 * ============================================================================ */

static void connection_peer_refs_reset_locked(struct lantern_client *client)
{
    if (!client)
    {
        return;
    }
    free(client->connection_peer_refs);
    client->connection_peer_refs = NULL;
    client->connection_peer_ref_count = 0;
    client->connection_peer_ref_capacity = 0;
}

static struct lantern_connection_peer_ref *connection_peer_ref_find_locked(
    struct lantern_client *client,
    const void *conn)
{
    if (!client || !conn)
    {
        return NULL;
    }
    for (size_t i = 0; i < client->connection_peer_ref_count; ++i)
    {
        if (client->connection_peer_refs[i].conn == conn)
        {
            return &client->connection_peer_refs[i];
        }
    }
    return NULL;
}

static bool connection_peer_ref_lookup_locked(
    struct lantern_client *client,
    const void *conn,
    struct lantern_peer_id *out_peer,
    bool *out_inbound)
{
    struct lantern_connection_peer_ref *ref = connection_peer_ref_find_locked(client, conn);
    if (!ref)
    {
        return false;
    }
    if (out_peer)
    {
        *out_peer = ref->peer;
    }
    if (out_inbound)
    {
        *out_inbound = ref->inbound;
    }
    return true;
}

static bool connection_peer_ref_lookup(
    struct lantern_client *client,
    const void *conn,
    struct lantern_peer_id *out_peer,
    bool *out_inbound)
{
    if (!client || !client->connection_lock_initialized || !conn)
    {
        return false;
    }
    bool found = false;
    if (pthread_mutex_lock(&client->connection_lock) == 0)
    {
        found = connection_peer_ref_lookup_locked(client, conn, out_peer, out_inbound);
        pthread_mutex_unlock(&client->connection_lock);
    }
    return found;
}

static int connection_peer_ref_remember_locked(
    struct lantern_client *client,
    const void *conn,
    const struct lantern_peer_id *peer,
    bool inbound)
{
    if (!client || !conn || !peer || peer->len == 0)
    {
        return 0;
    }
    struct lantern_connection_peer_ref *existing =
        connection_peer_ref_find_locked(client, conn);
    if (existing)
    {
        existing->peer = *peer;
        existing->inbound = inbound;
        existing->closing = false;
        return 0;
    }
    if (client->connection_peer_ref_count == client->connection_peer_ref_capacity)
    {
        size_t next_capacity =
            client->connection_peer_ref_capacity ? client->connection_peer_ref_capacity * 2u : 8u;
        struct lantern_connection_peer_ref *next =
            realloc(client->connection_peer_refs, next_capacity * sizeof(*next));
        if (!next)
        {
            return -1;
        }
        client->connection_peer_refs = next;
        client->connection_peer_ref_capacity = next_capacity;
    }
    client->connection_peer_refs[client->connection_peer_ref_count++] =
        (struct lantern_connection_peer_ref){
            .conn = conn,
            .peer = *peer,
            .inbound = inbound,
            .closing = false,
        };
    return 0;
}

static bool connection_peer_matches(
    const struct lantern_connection_peer_ref *ref,
    const struct lantern_peer_id *peer)
{
    return ref && peer && lantern_peer_id_equal(&ref->peer, peer);
}

static bool connection_peer_exists_locked(
    const struct lantern_client *client,
    const struct lantern_peer_id *peer)
{
    if (!client || !peer)
    {
        return false;
    }
    for (size_t i = 0; i < client->connection_peer_ref_count; ++i)
    {
        if (connection_peer_matches(&client->connection_peer_refs[i], peer))
        {
            return true;
        }
    }
    return false;
}

static bool connection_dedup_collect_closures(
    struct lantern_client *client,
    const void *conn,
    const struct lantern_peer_id *peer,
    const void ***out_conns,
    size_t *out_count,
    bool *out_current_closing)
{
    if (out_conns)
    {
        *out_conns = NULL;
    }
    if (out_count)
    {
        *out_count = 0;
    }
    if (out_current_closing)
    {
        *out_current_closing = false;
    }
    if (!client || !conn || !peer || peer->len == 0 || !out_conns || !out_count
        || !out_current_closing || !client->connection_lock_initialized
        || client->network.local_peer_id_len == 0)
    {
        return false;
    }

    bool prefer_inbound = connection_tie_break_prefers_inbound(
        client->network.local_peer_id,
        client->network.local_peer_id_len,
        peer);
    const void *keep_conn = NULL;

    if (pthread_mutex_lock(&client->connection_lock) != 0)
    {
        return false;
    }

    for (size_t i = 0; i < client->connection_peer_ref_count; ++i)
    {
        struct lantern_connection_peer_ref *ref = &client->connection_peer_refs[i];
        if (connection_peer_matches(ref, peer) && !ref->closing && ref->inbound == prefer_inbound)
        {
            keep_conn = ref->conn;
            break;
        }
    }
    if (!keep_conn)
    {
        for (size_t i = 0; i < client->connection_peer_ref_count; ++i)
        {
            struct lantern_connection_peer_ref *ref = &client->connection_peer_refs[i];
            if (connection_peer_matches(ref, peer) && !ref->closing)
            {
                keep_conn = ref->conn;
                break;
            }
        }
    }
    if (!keep_conn)
    {
        pthread_mutex_unlock(&client->connection_lock);
        return false;
    }

    size_t close_count = 0;
    for (size_t i = 0; i < client->connection_peer_ref_count; ++i)
    {
        struct lantern_connection_peer_ref *ref = &client->connection_peer_refs[i];
        if (connection_peer_matches(ref, peer) && !ref->closing && ref->conn != keep_conn)
        {
            close_count++;
        }
    }

    if (close_count == 0)
    {
        pthread_mutex_unlock(&client->connection_lock);
        return false;
    }

    const void **close_conns = calloc(close_count, sizeof(*close_conns));
    if (!close_conns)
    {
        pthread_mutex_unlock(&client->connection_lock);
        return false;
    }

    size_t out = 0;
    for (size_t i = 0; i < client->connection_peer_ref_count; ++i)
    {
        struct lantern_connection_peer_ref *ref = &client->connection_peer_refs[i];
        if (connection_peer_matches(ref, peer) && !ref->closing && ref->conn != keep_conn)
        {
            ref->closing = true;
            close_conns[out++] = ref->conn;
            if (ref->conn == conn)
            {
                *out_current_closing = true;
            }
        }
    }

    pthread_mutex_unlock(&client->connection_lock);

    *out_conns = close_conns;
    *out_count = out;
    return out != 0;
}

static bool dedup_peer_connections_after_open(
    struct lantern_client *client,
    const void *conn,
    const struct lantern_peer_id *peer)
{
    const void **close_conns = NULL;
    size_t close_count = 0;
    bool current_closing = false;

    if (!connection_dedup_collect_closures(
            client,
            conn,
            peer,
            &close_conns,
            &close_count,
            &current_closing))
    {
        return false;
    }

    char peer_text[128];
    format_peer_id_text(peer, peer_text, sizeof(peer_text));
    for (size_t i = 0; i < close_count; ++i)
    {
        libp2p_host_conn_t *close_conn = (libp2p_host_conn_t *)close_conns[i];
        if (!close_conn || !client->network.host)
        {
            continue;
        }
        lantern_log_debug(
            "network",
            &(const struct lantern_log_metadata){
                .validator = client->node_id,
                .peer = peer_text[0] ? peer_text : NULL,
            },
            "closing duplicate peer connection");
        (void)libp2p_host_conn_close(client->network.host, close_conn, 0);
    }
    free(close_conns);
    return current_closing;
}

static void connection_peer_ref_remove_locked(struct lantern_client *client, const void *conn)
{
    if (!client || !conn)
    {
        return;
    }
    for (size_t i = 0; i < client->connection_peer_ref_count; ++i)
    {
        if (client->connection_peer_refs[i].conn == conn)
        {
            client->connection_peer_refs[i] =
                client->connection_peer_refs[client->connection_peer_ref_count - 1u];
            client->connection_peer_ref_count -= 1u;
            return;
        }
    }
}

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
        connection_peer_refs_reset_locked(client);
        return;
    }
    if (pthread_mutex_lock(&client->connection_lock) == 0)
    {
        client->connected_peers = 0;
        connection_peer_refs_reset_locked(client);
        pthread_mutex_unlock(&client->connection_lock);
    }
    else
    {
        client->connected_peers = 0;
        connection_peer_refs_reset_locked(client);
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
    const void *conn,
    const struct lantern_peer_id *peer,
    bool inbound,
    int reason)
{
    if (!client || !client->connection_lock_initialized)
    {
        return;
    }

    char peer_text[128];
    struct lantern_peer_id cached_peer;
    const struct lantern_peer_id *effective_peer = peer;
    format_peer_id_text(effective_peer, peer_text, sizeof(peer_text));
    size_t total = 0;
    bool was_inbound = inbound;
    bool record_disconnect = false;
    size_t refs = 0;
    if (pthread_mutex_lock(&client->connection_lock) == 0)
    {
        struct lantern_connection_peer_ref *existing =
            connection_peer_ref_find_locked(client, conn);
        if (delta < 0 && existing)
        {
            cached_peer = existing->peer;
            effective_peer = &cached_peer;
            was_inbound = existing->inbound;
            format_peer_id_text(effective_peer, peer_text, sizeof(peer_text));
        }
        if (effective_peer && effective_peer->len > 0u)
        {
            if (delta > 0)
            {
                bool peer_was_connected = connection_peer_exists_locked(client, effective_peer);
                struct lantern_peer_id previous_peer = {0};
                bool peer_changed = existing
                    && !lantern_peer_id_equal(&existing->peer, effective_peer);
                if (peer_changed)
                {
                    previous_peer = existing->peer;
                }
                if (connection_peer_ref_remember_locked(client, conn, effective_peer, inbound) == 0)
                {
                    if (!peer_was_connected)
                    {
                        client->connected_peers += 1u;
                    }
                    if (peer_changed && !connection_peer_exists_locked(client, &previous_peer)
                        && client->connected_peers > 0u)
                    {
                        client->connected_peers -= 1u;
                    }
                }
            }
            else if (delta < 0 && existing)
            {
                connection_peer_ref_remove_locked(client, conn);
                if (!connection_peer_exists_locked(client, effective_peer))
                {
                    if (client->connected_peers > 0u)
                    {
                        client->connected_peers -= 1u;
                    }
                    record_disconnect = true;
                }
            }
        }
        total = client->connected_peers;
        refs = client->connection_peer_ref_count;
        pthread_mutex_unlock(&client->connection_lock);
    }
    else
    {
        return;
    }

    if (delta < 0 && !record_disconnect)
    {
        return;
    }

    if (total == 0 && client->status_lock_initialized
        && pthread_mutex_lock(&client->status_lock) == 0)
    {
        lantern_client_set_sync_state_logged(client, LANTERN_SYNC_STATE_IDLE, "no peers");
        pthread_mutex_unlock(&client->status_lock);
    }
    lantern_log_trace(
        "network",
        &(const struct lantern_log_metadata){
            .validator = client->node_id,
            .peer = peer_text[0] ? peer_text : NULL,
        },
        "connection %s inbound=%s total=%zu refs=%zu reason=%d (%s)",
        delta > 0 ? "opened" : "closed",
        (delta > 0 ? inbound : was_inbound) ? "true" : "false",
        total,
        refs,
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
    struct lantern_peer_id peer;
    if (lantern_peer_id_from_text(peer_id, &peer) != 0)
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
        connected = connection_peer_exists_locked(client, &peer);
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
void request_status_now(struct lantern_client *client, const struct lantern_peer_id *peer, const char *peer_text)
{
    if (!client || !client->reqresp_running)
    {
        return;
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

    struct lantern_peer_id resolved_peer;
    const struct lantern_peer_id *peer_arg = peer;
    if (!peer_arg && status_peer
        && lantern_peer_id_from_text(status_peer, &resolved_peer) == 0)
    {
        peer_arg = &resolved_peer;
    }

    int status_rc = lantern_reqresp_service_request_status(&client->reqresp, peer_arg, status_peer);
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

    lantern_log_trace(
        "network",
        &(const struct lantern_log_metadata){
            .validator = client->node_id,
            .peer = peer_label,
        },
        "identify query will run after connection opens addr=%s",
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
 * Attempt to redial a disconnected genesis peer.
 *
 * @param client  Client instance
 * @param peer    Peer ID to redial
 *
 * @note Thread safety: This function acquires connection_lock
 */
void redial_peer(struct lantern_client *client, const struct lantern_peer_id *peer)
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
        struct lantern_peer_id enr_peer_id;
        if (lantern_libp2p_enr_to_multiaddr(
                record,
                multiaddr,
                sizeof(multiaddr),
                &enr_peer_id) != 0)
        {
            continue;
        }

        if (lantern_peer_id_equal(peer, &enr_peer_id))
        {
            /* Found matching peer in genesis, redial */
            lantern_log_info(
                "network",
                &(const struct lantern_log_metadata){
                    .validator = client->node_id,
                    .peer = peer_text[0] ? peer_text : NULL,
                },
                "redialing peer addr=%s",
                multiaddr);

            (void)lantern_libp2p_host_dial_multiaddr(&client->network, multiaddr);
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
        for (size_t i = 0; i < client->connection_peer_ref_count; ++i)
        {
            char peer_text[128];
            format_peer_id_text(
                &client->connection_peer_refs[i].peer,
                peer_text,
                sizeof(peer_text));
            if (peer_text[0] && !string_list_contains(out_snapshot, peer_text)
                && lantern_string_list_append(out_snapshot, peer_text) != 0)
            {
                lantern_string_list_reset(out_snapshot);
                lantern_string_list_init(out_snapshot);
                break;
            }
        }
        connected_unique = client->connected_peers;
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
static bool get_local_peer_id(struct lantern_client *client, struct lantern_peer_id *out_peer)
{
    if (!client || !out_peer || client->network.local_peer_id_len == 0
        || client->network.local_peer_id_len > sizeof(out_peer->bytes))
    {
        return false;
    }

    memcpy(out_peer->bytes, client->network.local_peer_id, client->network.local_peer_id_len);
    out_peer->len = client->network.local_peer_id_len;
    return true;
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
    const struct lantern_peer_id *local_peer)
{
    if (!enrs || enrs->count == 0)
    {
        return 0;
    }

    size_t target = enrs->count;
    if (local_peer && target > 0)
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
    const struct lantern_peer_id *local_peer,
    const struct lantern_string_list *connected_snapshot)
{
    if (!client || !record || !record->encoded)
    {
        return;
    }

    char multiaddr[256];
    struct lantern_peer_id peer_id;
    if (lantern_libp2p_enr_to_multiaddr(record, multiaddr, sizeof(multiaddr), &peer_id) != 0)
    {
        return;
    }

    if (local_peer && lantern_peer_id_equal(local_peer, &peer_id))
    {
        return;
    }

    char peer_text[128];
    format_peer_id_text(&peer_id, peer_text, sizeof(peer_text));

    if (peer_text[0] && connected_snapshot && string_list_contains(connected_snapshot, peer_text))
    {
        return;
    }

    if (peer_text[0] && lantern_client_is_peer_connected(client, peer_text))
    {
        return;
    }

    (void)lantern_libp2p_host_dial_multiaddr(&client->network, multiaddr);

    const char *peer_label = peer_text[0] ? peer_text : record->encoded;
    identify_dial_multiaddr(client, multiaddr, peer_label);

    if (peer_text[0] && !string_list_contains(&client->dialer_peers, peer_text))
    {
        (void)lantern_string_list_append(&client->dialer_peers, peer_text);
    }
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
    struct lantern_peer_id local_peer_value;
    struct lantern_peer_id *local_peer = get_local_peer_id(client, &local_peer_value) ? &local_peer_value : NULL;

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
    lantern_string_list_reset(&connected_snapshot);
}


void peer_status_refresh(struct lantern_client *client)
{
    if (!client || !client->reqresp_running)
    {
        return;
    }

    struct lantern_string_list connected_snapshot;
    lantern_string_list_init(&connected_snapshot);
    (void)snapshot_connected_peers(client, &connected_snapshot);

    for (size_t idx = 0; idx < connected_snapshot.len; ++idx)
    {
        if (__atomic_load_n(&client->dialer_stop_flag, __ATOMIC_RELAXED) != 0)
        {
            break;
        }
        const char *peer_text = connected_snapshot.items[idx];
        if (peer_text && peer_text[0])
        {
            request_status_now(client, NULL, peer_text);
        }
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
        peer_status_refresh(client);
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
    const void *conn,
    const struct lantern_peer_id *peer,
    bool inbound)
{
    if (!client)
    {
        return;
    }

    connection_counter_update(client, 1, conn, peer, inbound, 0);

    if (!peer)
    {
        return;
    }
    bool current_closing = dedup_peer_connections_after_open(client, conn, peer);
    if (current_closing)
    {
        return;
    }
    if (inbound)
    {
        char peer_text[128];
        format_peer_id_text(peer, peer_text, sizeof(peer_text));
        lantern_log_trace(
            "reqresp",
            &(const struct lantern_log_metadata){
                .validator = client->node_id,
                .peer = peer_text[0] ? peer_text : NULL,
            },
            "inbound connection opened; waiting for peer status request");
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
    const void *conn,
    const struct lantern_peer_id *peer,
    int reason,
    uint64_t app_error_code,
    uint64_t transport_error_code)
{
    if (!client)
    {
        return;
    }

    connection_counter_update(client, -1, conn, peer, false, reason);

    if (!peer)
    {
        return;
    }

    char peer_text[128];
    format_peer_id_text(peer, peer_text, sizeof(peer_text));
    bool peer_still_connected = peer_text[0] && lantern_client_is_peer_connected(client, peer_text);
    const struct lantern_log_metadata meta = {
        .validator = client->node_id,
        .peer = peer_text[0] ? peer_text : NULL,
    };
    if (reason == LIBP2P_HOST_OK && peer_still_connected)
    {
        lantern_log_debug(
            "network",
            &meta,
            "duplicate connection closed reason=%d (%s) app_error=%" PRIu64 " transport_error=%" PRIu64,
            reason,
            connection_reason_text(reason),
            app_error_code,
            transport_error_code);
    }
    else
    {
        lantern_log_info(
            "network",
            &meta,
            "connection closed reason=%d (%s) app_error=%" PRIu64 " transport_error=%" PRIu64,
            reason,
            connection_reason_text(reason),
            app_error_code,
            transport_error_code);
    }

    if (reason != LIBP2P_HOST_OK)
    {
        redial_peer(client, peer);
    }
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
    const struct lantern_peer_id *peer,
    int code,
    const char *msg,
    uint64_t app_error_code,
    uint64_t transport_error_code)
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
        "outgoing connection error code=%d (%s) msg=%s app_error=%" PRIu64 " transport_error=%" PRIu64,
        code,
        connection_reason_text(code),
        msg ? msg : "-",
        app_error_code,
        transport_error_code);

    lean_metrics_record_peer_connection(
        LEAN_METRICS_DIR_OUTBOUND,
        metrics_connection_result_from_code(code));
}


static bool connection_event_peer_id(
    const libp2p_host_conn_t *conn,
    struct lantern_peer_id *out_peer)
{
    if (!conn || !out_peer)
    {
        return false;
    }
    size_t written = 0;
    if (libp2p_host_conn_peer_id(conn, out_peer->bytes, sizeof(out_peer->bytes), &written) != LIBP2P_HOST_OK ||
        written == 0 || written > sizeof(out_peer->bytes))
    {
        memset(out_peer, 0, sizeof(*out_peer));
        return false;
    }
    out_peer->len = written;
    return true;
}


/**
 * Connection event callback for c-lean-libp2p host.
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
    void *user_data)
{
    if (!network || !evt || !user_data)
    {
        return;
    }
    struct lantern_client *client = (struct lantern_client *)user_data;
    struct lantern_peer_id peer;
    bool has_peer = connection_event_peer_id(evt->conn, &peer);
    if (!has_peer && evt->type == LIBP2P_HOST_EVENT_CONN_CLOSED)
    {
        has_peer = connection_peer_ref_lookup(client, evt->conn, &peer, NULL);
    }
    const struct lantern_peer_id *peer_ptr = has_peer ? &peer : NULL;

    switch (evt->type)
    {
        case LIBP2P_HOST_EVENT_CONN_ESTABLISHED:
            handle_connection_opened_event(client, evt->conn, peer_ptr, evt->dial == NULL);
            if (network->host && evt->conn)
            {
                (void)libp2p_identify_query(&network->identify, network->host, evt->conn, NULL, NULL);
            }
            break;
        case LIBP2P_HOST_EVENT_CONN_CLOSED:
            handle_connection_closed_event(
                client,
                evt->conn,
                peer_ptr,
                (int)evt->reason,
                evt->app_error_code,
                evt->transport_error_code);
            break;
        case LIBP2P_HOST_EVENT_DIAL_FAILED:
            handle_outgoing_connection_error_event(
                client,
                peer_ptr,
                (int)evt->reason,
                "dial failed",
                evt->app_error_code,
                evt->transport_error_code);
            break;
        default:
            break;
    }
}
