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

#include "lantern/networking/libp2p.h"
#include "lantern/support/log.h"
#include "lantern/support/string_list.h"

#include <libp2p/errors.h>
#include <protocol/gossipsub/gossipsub.h>
#include <protocol/identify/protocol_identify.h>
#include <protocol/ping/protocol_ping.h>

#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>


/* ============================================================================
 * Constants
 * ============================================================================ */

#define LANTERN_PING_INTERVAL_SECONDS 15
#define LANTERN_PING_TIMEOUT_MS 5000


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
        return;
    }
    if (pthread_mutex_lock(&client->connection_lock) == 0)
    {
        client->connected_peers = 0;
        lantern_string_list_reset(&client->connected_peer_ids);
        lantern_string_list_init(&client->connected_peer_ids);
        pthread_mutex_unlock(&client->connection_lock);
    }
    else
    {
        client->connected_peers = 0;
        lantern_string_list_reset(&client->connected_peer_ids);
        lantern_string_list_init(&client->connected_peer_ids);
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
    peer_text[0] = '\0';
    if (peer)
    {
        if (peer_id_to_string(peer, PEER_ID_FMT_BASE58_LEGACY, peer_text, sizeof(peer_text)) < 0)
        {
            peer_text[0] = '\0';
        }
    }

    const char *label = peer_text[0] ? peer_text : NULL;
    size_t total = 0;
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
            }
            else if (delta < 0)
            {
                string_list_remove(&client->connected_peer_ids, peer_text);
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

    (void)label;
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
    char peer_buffer[128];
    peer_buffer[0] = '\0';
    const char *status_peer = (peer_text && peer_text[0]) ? peer_text : NULL;
    if ((!status_peer || status_peer[0] == '\0') && peer)
    {
        if (peer_id_to_string(peer, PEER_ID_FMT_BASE58_LEGACY, peer_buffer, sizeof(peer_buffer)) == 0)
        {
            status_peer = peer_buffer;
        }
        else
        {
            status_peer = NULL;
        }
    }
    if (status_peer && !lantern_client_is_peer_connected(client, status_peer))
    {
        lantern_log_trace(
            "reqresp",
            &(const struct lantern_log_metadata){
                .validator = client->node_id,
                .peer = status_peer},
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
        lantern_log_trace(
            "reqresp",
            &meta,
            status_rc == 0 ? "initiated status request to peer" : "unable to initiate status request to peer");
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


/**
 * Seed reqresp service with peer legacy mode hints from genesis config.
 *
 * @param client  Client instance
 *
 * @note Thread safety: This function is thread-safe
 */
void lantern_client_seed_reqresp_peer_modes(struct lantern_client *client)
{
    if (!client)
    {
        return;
    }
#if defined(LANTERN_REQRESP_STATUS_PROTOCOL_LEGACY) || defined(LANTERN_REQRESP_BLOCKS_BY_ROOT_PROTOCOL_LEGACY)
    const struct lantern_validator_config *config = &client->genesis.validator_config;
    if (!config || !config->entries)
    {
        return;
    }
    for (size_t i = 0; i < config->count; ++i)
    {
        const struct lantern_validator_config_entry *entry = &config->entries[i];
        if (!entry->peer_id_text || !entry->peer_id_text[0])
        {
            continue;
        }
        int legacy = (entry->client_kind == LANTERN_VALIDATOR_CLIENT_QLEAN);
        lantern_reqresp_service_hint_peer_legacy(&client->reqresp, entry->peer_id_text, legacy);
    }
#else
    (void)client;
#endif
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
void identify_dial_multiaddr(struct lantern_client *client, const char *multiaddr, const char *peer_label)
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
                .peer = peer_label},
            "identify dial succeeded addr=%s",
            multiaddr);
        return;
    }

    lantern_log_trace(
        "network",
        &(const struct lantern_log_metadata){
            .validator = client->node_id,
            .peer = peer_label},
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
    peer_text[0] = '\0';
    if (peer_id_to_string(peer, PEER_ID_FMT_BASE58_LEGACY, peer_text, sizeof(peer_text)) < 0)
    {
        peer_text[0] = '\0';
    }

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
        if (lantern_libp2p_enr_to_multiaddr(record, multiaddr, sizeof(multiaddr), &enr_peer_id) != 0)
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

            (void)lantern_libp2p_host_add_enr_peer(&client->network, record, LANTERN_LIBP2P_DEFAULT_PEER_TTL_MS);
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

    size_t connected_unique = 0;
    if (client->connection_lock_initialized)
    {
        if (pthread_mutex_lock(&client->connection_lock) == 0)
        {
            connected_unique = client->connected_peer_ids.len;
            if (lantern_string_list_copy(&connected_snapshot, &client->connected_peer_ids) != 0)
            {
                lantern_string_list_reset(&connected_snapshot);
                lantern_string_list_init(&connected_snapshot);
                connected_unique = client->connected_peers;
            }
            pthread_mutex_unlock(&client->connection_lock);
        }
        else
        {
            connected_unique = client->connected_peers;
        }
    }

    peer_id_t *local_peer = NULL;
    if (libp2p_host_get_peer_id(client->network.host, &local_peer) != 0)
    {
        local_peer = NULL;
    }

    size_t target = 0;
    if (enrs->count > 0)
    {
        target = enrs->count;
        if (local_peer && local_peer->bytes && local_peer->size)
        {
            if (target > 0)
            {
                target -= 1;
            }
        }
    }

    if (target > 0 && connected_unique >= target)
    {
        if (local_peer)
        {
            peer_id_destroy(local_peer);
            free(local_peer);
        }
        lantern_string_list_reset(&connected_snapshot);
        return;
    }

    for (size_t idx = 0; idx < enrs->count; ++idx)
    {
        if (__atomic_load_n(&client->dialer_stop_flag, __ATOMIC_RELAXED) != 0)
        {
            break;
        }

        const struct lantern_enr_record *record = &enrs->records[idx];
        if (!record || !record->encoded)
        {
            continue;
        }

        char multiaddr[256];
        peer_id_t peer_id = {0};
        if (lantern_libp2p_enr_to_multiaddr(record, multiaddr, sizeof(multiaddr), &peer_id) != 0)
        {
            continue;
        }

        bool is_self = false;
        if (local_peer)
        {
            int eq = peer_id_equals(local_peer, &peer_id);
            if (eq == 1)
            {
                is_self = true;
            }
        }

        if (!is_self)
        {
            char peer_text[128];
            peer_text[0] = '\0';
            if (peer_id_to_string(&peer_id, PEER_ID_FMT_BASE58_LEGACY, peer_text, sizeof(peer_text)) < 0)
            {
                peer_text[0] = '\0';
            }

            if (peer_text[0] && string_list_contains(&connected_snapshot, peer_text))
            {
                peer_id_destroy(&peer_id);
                continue;
            }

            (void)lantern_libp2p_host_add_enr_peer(&client->network, record, LANTERN_LIBP2P_DEFAULT_PEER_TTL_MS);
            identify_dial_multiaddr(client, multiaddr, peer_text[0] ? peer_text : record->encoded);

            bool already_added = false;
            if (peer_text[0])
            {
                already_added = string_list_contains(&client->dialer_peers, peer_text);
            }

            if (client->gossip_running && client->gossip.gossipsub)
            {
                if (!already_added)
                {
                    libp2p_err_t perr = libp2p_gossipsub_peering_add(client->gossip.gossipsub, &peer_id);
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
                                .peer = peer_text[0] ? peer_text : record->encoded},
                            "dialer added peer to gossipsub peering");
                    }
                }
            }
        }

        peer_id_destroy(&peer_id);
    }

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
    struct lantern_client *client;
    char peer_text[128];
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
        return;
    }
    if (lantern_string_list_copy(&peers, &client->connected_peer_ids) != 0)
    {
        pthread_mutex_unlock(&client->connection_lock);
        return;
    }
    pthread_mutex_unlock(&client->connection_lock);

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
        "ping service started interval=%ds",
        LANTERN_PING_INTERVAL_SECONDS);
    while (__atomic_load_n(&client->ping_stop_flag, __ATOMIC_RELAXED) == 0)
    {
        ping_all_peers(client);
        /* Sleep in small increments to allow quick shutdown. */
        for (unsigned i = 0; i < LANTERN_PING_INTERVAL_SECONDS && __atomic_load_n(&client->ping_stop_flag, __ATOMIC_RELAXED) == 0; i++)
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
            connection_counter_update(client, 1, evt->u.conn_opened.peer, evt->u.conn_opened.inbound, 0);
            if (evt->u.conn_opened.peer)
            {
                char peer_text[128];
                peer_text[0] = '\0';
                if (peer_id_to_string(evt->u.conn_opened.peer, PEER_ID_FMT_BASE58_LEGACY, peer_text, sizeof(peer_text)) < 0)
                {
                    peer_text[0] = '\0';
                }
                request_status_now(client, evt->u.conn_opened.peer, peer_text[0] ? peer_text : NULL);
            }
            break;
        case LIBP2P_EVT_CONN_CLOSED:
        {
            connection_counter_update(client, -1, evt->u.conn_closed.peer, false, evt->u.conn_closed.reason);
            /* If disconnected unexpectedly, attempt to redial the peer.
             * We redial for timeout, reset, EOF, and closed reasons since the remote
             * peer may have closed due to their own timeout or network issues. */
            if (evt->u.conn_closed.peer)
            {
                int reason = evt->u.conn_closed.reason;
                char peer_text[128];
                peer_text[0] = '\0';
                if (peer_id_to_string(evt->u.conn_closed.peer, PEER_ID_FMT_BASE58_LEGACY, peer_text, sizeof(peer_text)) < 0)
                {
                    peer_text[0] = '\0';
                }
                lantern_log_info(
                    "network",
                    &(const struct lantern_log_metadata){
                        .validator = client->node_id,
                        .peer = peer_text[0] ? peer_text : NULL,
                    },
                    "connection closed reason=%d (%s)",
                    reason,
                    connection_reason_text(reason));
                if (reason == LIBP2P_ERR_TIMEOUT ||
                    reason == LIBP2P_ERR_RESET ||
                    reason == LIBP2P_ERR_EOF ||
                    reason == LIBP2P_ERR_CLOSED)
                {
                    redial_peer_on_timeout(client, evt->u.conn_closed.peer);
                }
            }
            break;
        }
        case LIBP2P_EVT_DIALING:
        {
            char peer_text[128];
            peer_text[0] = '\0';
            if (evt->u.dialing.peer)
            {
                if (peer_id_to_string(evt->u.dialing.peer, PEER_ID_FMT_BASE58_LEGACY, peer_text, sizeof(peer_text)) < 0)
                {
                    peer_text[0] = '\0';
                }
            }
            lantern_log_debug(
                "network",
                &(const struct lantern_log_metadata){
                    .validator = client->node_id,
                    .peer = peer_text[0] ? peer_text : NULL,
                },
                "dialing peer addr=%s",
                evt->u.dialing.addr ? evt->u.dialing.addr : "-");
            break;
        }
        case LIBP2P_EVT_OUTGOING_CONNECTION_ERROR:
        {
            char peer_text[128];
            peer_text[0] = '\0';
            if (evt->u.outgoing_conn_error.peer)
            {
                if (peer_id_to_string(evt->u.outgoing_conn_error.peer, PEER_ID_FMT_BASE58_LEGACY, peer_text, sizeof(peer_text)) < 0)
                {
                    peer_text[0] = '\0';
                }
            }
            lantern_log_warn(
                "network",
                &(const struct lantern_log_metadata){
                    .validator = client->node_id,
                    .peer = peer_text[0] ? peer_text : NULL,
                },
                "outgoing connection error code=%d (%s) msg=%s",
                evt->u.outgoing_conn_error.code,
                connection_reason_text(evt->u.outgoing_conn_error.code),
                evt->u.outgoing_conn_error.msg ? evt->u.outgoing_conn_error.msg : "-");
            break;
        }
        case LIBP2P_EVT_INCOMING_CONNECTION_ERROR:
        {
            char peer_text[128];
            peer_text[0] = '\0';
            if (evt->u.incoming_conn_error.peer)
            {
                if (peer_id_to_string(evt->u.incoming_conn_error.peer, PEER_ID_FMT_BASE58_LEGACY, peer_text, sizeof(peer_text)) < 0)
                {
                    peer_text[0] = '\0';
                }
            }
            lantern_log_warn(
                "network",
                &(const struct lantern_log_metadata){
                    .validator = client->node_id,
                    .peer = peer_text[0] ? peer_text : NULL,
                },
                "incoming connection error code=%d (%s) msg=%s",
                evt->u.incoming_conn_error.code,
                connection_reason_text(evt->u.incoming_conn_error.code),
                evt->u.incoming_conn_error.msg ? evt->u.incoming_conn_error.msg : "-");
            break;
        }
        default:
            break;
    }
}
