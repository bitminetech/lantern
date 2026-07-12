#include "lantern/networking/gossipsub_service.h"

#include <stdbool.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>

#include "lantern/core/client.h"
#include "lantern/encoding/snappy.h"
#include "lantern/networking/gossip.h"
#include "lantern/networking/gossip_payloads.h"
#include "lantern/support/log.h"

#define LANTERN_GOSSIP_ENCODE_BUFFER_BYTES (16u * 1024u * 1024u)
#define LANTERN_GOSSIP_MAX_MESSAGE_BYTES (10u * 1024u * 1024u)
#define LANTERN_GOSSIP_MAX_RPC_BYTES (LANTERN_GOSSIP_MAX_MESSAGE_BYTES + (64u * 1024u))
#define LANTERN_GOSSIP_TX_BUFFER_BYTES (4u * LANTERN_GOSSIP_MAX_RPC_BYTES)
#define LANTERN_GOSSIP_MCACHE_BYTES (4u * LANTERN_GOSSIP_MAX_MESSAGE_BYTES)

static pthread_mutex_t g_lantern_gossipsub_mutex = PTHREAD_MUTEX_INITIALIZER;

static int lock_gossipsub(void) {
    return pthread_mutex_lock(&g_lantern_gossipsub_mutex) == 0 ? 0 : -1;
}

static void unlock_gossipsub(void) {
    (void)pthread_mutex_unlock(&g_lantern_gossipsub_mutex);
}

static libp2p_host_err_t gossipsub_protocol_open_locked(
    libp2p_host_t *host,
    libp2p_host_stream_t *stream,
    libp2p_host_stream_direction_t direction,
    void *user_data) {
    struct lantern_gossipsub_protocol_adapter *adapter =
        (struct lantern_gossipsub_protocol_adapter *)user_data;
    if (!adapter || !adapter->service || !adapter->on_open) {
        return LIBP2P_HOST_ERR_INVALID_ARG;
    }
    if (lock_gossipsub() != 0) {
        return LIBP2P_HOST_ERR_INTERNAL;
    }
    libp2p_host_err_t rc = adapter->on_open(host, stream, direction, adapter->user_data);
    unlock_gossipsub();
    return rc;
}

static libp2p_host_err_t gossipsub_protocol_event_locked(
    libp2p_host_t *host,
    libp2p_host_stream_t *stream,
    libp2p_host_protocol_event_kind_t kind,
    void *user_data) {
    struct lantern_gossipsub_protocol_adapter *adapter =
        (struct lantern_gossipsub_protocol_adapter *)user_data;
    if (!adapter || !adapter->service || !adapter->on_event) {
        return LIBP2P_HOST_ERR_INVALID_ARG;
    }
    if (lock_gossipsub() != 0) {
        return LIBP2P_HOST_ERR_INTERNAL;
    }
    libp2p_host_err_t rc = adapter->on_event(host, stream, kind, adapter->user_data);
    unlock_gossipsub();
    return rc;
}

static void wrap_gossipsub_protocols(struct lantern_gossipsub_service *service) {
    if (!service) {
        return;
    }
    for (size_t i = 0; i < service->gossipsub_protocol_count; i++) {
        struct lantern_gossipsub_protocol_adapter *adapter = &service->gossipsub_protocol_adapters[i];
        adapter->service = service;
        adapter->on_open = service->gossipsub_protocols[i].on_open;
        adapter->on_event = service->gossipsub_protocols[i].on_event;
        adapter->user_data = service->gossipsub_protocols[i].user_data;
        service->gossipsub_protocols[i].on_open = gossipsub_protocol_open_locked;
        service->gossipsub_protocols[i].on_event = gossipsub_protocol_event_locked;
        service->gossipsub_protocols[i].user_data = adapter;
    }
}

struct gossipsub_message_snapshot {
    libp2p_gossipsub_event_t event;
    uint8_t *topic;
    uint8_t *data;
};

static int topic_eq(const libp2p_gossipsub_bytes_t topic, const char *expected) {
    return expected && strlen(expected) == topic.len && memcmp(topic.data, expected, topic.len) == 0;
}

static int copy_gossipsub_bytes(
    const libp2p_gossipsub_bytes_t source,
    uint8_t **owned,
    libp2p_gossipsub_bytes_t *dest) {
    if (!owned || !dest) {
        return -1;
    }
    *owned = NULL;
    dest->data = NULL;
    dest->len = source.len;
    if (source.len == 0) {
        return 0;
    }
    if (!source.data) {
        return -1;
    }
    uint8_t *copy = (uint8_t *)malloc(source.len);
    if (!copy) {
        return -1;
    }
    memcpy(copy, source.data, source.len);
    *owned = copy;
    dest->data = copy;
    return 0;
}

static void gossipsub_message_snapshot_reset(struct gossipsub_message_snapshot *snapshot) {
    if (!snapshot) {
        return;
    }
    free(snapshot->topic);
    free(snapshot->data);
    memset(snapshot, 0, sizeof(*snapshot));
}

static int gossipsub_message_snapshot_init(
    struct gossipsub_message_snapshot *snapshot,
    const libp2p_gossipsub_event_t *event) {
    if (!snapshot || !event || event->type != LIBP2P_GOSSIPSUB_EVENT_MESSAGE) {
        return -1;
    }
    memset(snapshot, 0, sizeof(*snapshot));
    snapshot->event = *event;
    if (copy_gossipsub_bytes(event->topic, &snapshot->topic, &snapshot->event.topic) != 0) {
        gossipsub_message_snapshot_reset(snapshot);
        return -1;
    }
    if (copy_gossipsub_bytes(event->message.data, &snapshot->data, &snapshot->event.message.data) != 0) {
        gossipsub_message_snapshot_reset(snapshot);
        return -1;
    }
    snapshot->event.message.topic = snapshot->event.topic;
    snapshot->event.message.raw_message.data = NULL;
    return 0;
}

static bool topic_is_vote_topic(
    const struct lantern_gossipsub_service *service,
    const libp2p_gossipsub_bytes_t topic);

static void peer_id_to_text_safe(const struct lantern_peer_id *peer, char *out, size_t out_len) {
    if (!out || out_len == 0) {
        return;
    }
    out[0] = '\0';
    if (!peer || peer->len == 0) {
        return;
    }
    if (lantern_peer_id_to_text(peer, out, out_len) < 0) {
        out[0] = '\0';
    }
}

static int peer_from_conn(libp2p_host_conn_t *conn, struct lantern_peer_id *out_peer) {
    if (!conn || !out_peer) {
        return -1;
    }
    memset(out_peer, 0, sizeof(*out_peer));
    size_t written = 0;
    if (libp2p_host_conn_peer_id(conn, out_peer->bytes, sizeof(out_peer->bytes), &written) != LIBP2P_HOST_OK ||
        written == 0 || written > sizeof(out_peer->bytes)) {
        memset(out_peer, 0, sizeof(*out_peer));
        return -1;
    }
    out_peer->len = written;
    return 0;
}

static int peer_from_gossipsub_event(const libp2p_gossipsub_event_t *event, struct lantern_peer_id *out_peer) {
    if (!event || !out_peer || event->peer.len == 0 || event->peer.len > sizeof(out_peer->bytes)) {
        return -1;
    }
    memset(out_peer, 0, sizeof(*out_peer));
    memcpy(out_peer->bytes, event->peer.data, event->peer.len);
    out_peer->len = event->peer.len;
    return 0;
}

static int peer_id_cmp_bytes(const uint8_t *left, size_t left_len, const uint8_t *right, size_t right_len) {
    size_t min_len = left_len < right_len ? left_len : right_len;
    int cmp = min_len > 0 ? memcmp(left, right, min_len) : 0;
    if (cmp != 0) {
        return cmp;
    }
    if (left_len < right_len) {
        return -1;
    }
    if (left_len > right_len) {
        return 1;
    }
    return 0;
}

static int service_prefers_inbound_conn(
    const struct lantern_gossipsub_service *service,
    const struct lantern_peer_id *peer) {
    if (!service || !service->network || !peer || service->network->local_peer_id_len == 0) {
        return 0;
    }
    return peer_id_cmp_bytes(
               service->network->local_peer_id,
               service->network->local_peer_id_len,
               peer->bytes,
               peer->len) > 0;
}

static struct lantern_gossipsub_peer_connection_state *find_peer_state(
    struct lantern_gossipsub_service *service,
    const struct lantern_peer_id *peer,
    int create) {
    if (!service || !peer || peer->len == 0) {
        return NULL;
    }
    for (size_t i = 0; i < LANTERN_GOSSIPSUB_MAX_TRACKED_PEERS; i++) {
        struct lantern_gossipsub_peer_connection_state *state = &service->peer_connections[i];
        if (state->used && lantern_peer_id_equal(&state->peer, peer)) {
            return state;
        }
    }
    if (!create) {
        return NULL;
    }
    for (size_t i = 0; i < LANTERN_GOSSIPSUB_MAX_TRACKED_PEERS; i++) {
        struct lantern_gossipsub_peer_connection_state *state = &service->peer_connections[i];
        if (!state->used) {
            memset(state, 0, sizeof(*state));
            state->used = 1;
            state->peer = *peer;
            state->retry_backoff_us = LANTERN_GOSSIPSUB_RETRY_INITIAL_US;
            return state;
        }
    }
    return NULL;
}

static struct lantern_gossipsub_peer_connection_state *find_peer_state_by_conn(
    struct lantern_gossipsub_service *service,
    libp2p_host_conn_t *conn) {
    if (!service || !conn) {
        return NULL;
    }
    for (size_t i = 0; i < LANTERN_GOSSIPSUB_MAX_TRACKED_PEERS; i++) {
        struct lantern_gossipsub_peer_connection_state *state = &service->peer_connections[i];
        if (!state->used) {
            continue;
        }
        for (size_t j = 0; j < state->conn_count; j++) {
            if (state->conns[j] == conn) {
                return state;
            }
        }
        if (state->writer_conn == conn || state->opening_conn == conn) {
            return state;
        }
    }
    return NULL;
}

static ssize_t peer_state_conn_index(
    const struct lantern_gossipsub_peer_connection_state *state,
    libp2p_host_conn_t *conn) {
    if (!state || !conn) {
        return -1;
    }
    for (size_t i = 0; i < state->conn_count; i++) {
        if (state->conns[i] == conn) {
            return (ssize_t)i;
        }
    }
    return -1;
}

static void peer_state_select_primary(
    struct lantern_gossipsub_service *service,
    struct lantern_gossipsub_peer_connection_state *state) {
    if (!service || !state || state->conn_count == 0) {
        if (state) {
            state->primary_conn = NULL;
            state->primary_inbound = 0;
        }
        return;
    }
    const int prefer_inbound = service_prefers_inbound_conn(service, &state->peer);
    size_t selected = LANTERN_GOSSIPSUB_MAX_CONNS_PER_PEER;
    for (size_t i = 0; i < state->conn_count; i++) {
        if (!state->conn_closing[i] && (state->conn_inbound[i] ? 1 : 0) == prefer_inbound) {
            selected = i;
            break;
        }
    }
    if (selected == LANTERN_GOSSIPSUB_MAX_CONNS_PER_PEER) {
        for (size_t i = 0; i < state->conn_count; i++) {
            if (!state->conn_closing[i]) {
                selected = i;
                break;
            }
        }
    }
    if (selected == LANTERN_GOSSIPSUB_MAX_CONNS_PER_PEER) {
        state->primary_conn = NULL;
        state->primary_inbound = 0;
        return;
    }
    state->primary_conn = state->conns[selected];
    state->primary_inbound = state->conn_inbound[selected] ? 1 : 0;
}

static void schedule_writer_retry(
    struct lantern_gossipsub_peer_connection_state *state,
    libp2p_host_time_us_t now_us) {
    if (!state) {
        return;
    }
    uint64_t delay = state->retry_backoff_us;
    if (delay == 0) {
        delay = LANTERN_GOSSIPSUB_RETRY_INITIAL_US;
    }
    state->next_retry_us = now_us + delay;
    delay *= 2;
    if (delay > LANTERN_GOSSIPSUB_RETRY_MAX_US) {
        delay = LANTERN_GOSSIPSUB_RETRY_MAX_US;
    }
    state->retry_backoff_us = delay;
}

static void reset_writer_retry(struct lantern_gossipsub_peer_connection_state *state) {
    if (!state) {
        return;
    }
    state->next_retry_us = 0;
    state->retry_backoff_us = LANTERN_GOSSIPSUB_RETRY_INITIAL_US;
}

static int open_primary_writer(
    struct lantern_gossipsub_service *service,
    struct lantern_gossipsub_peer_connection_state *state,
    libp2p_host_time_us_t now_us) {
    if (!service || !service->gossipsub || !service->network || !service->network->host ||
        !state || !state->primary_conn || state->writer_stream || state->opening_conn) {
        return 0;
    }
    if (state->next_retry_us != 0 && now_us < state->next_retry_us) {
        return 0;
    }

    libp2p_host_stream_open_t *open = NULL;
    libp2p_gossipsub_err_t err = libp2p_gossipsub_open_peer(
        service->gossipsub,
        service->network->host,
        state->primary_conn,
        LIBP2P_GOSSIPSUB_VERSION_NONE,
        NULL,
        &open);
    if (err == LIBP2P_GOSSIPSUB_OK && open) {
        char peer_text[128];
        peer_id_to_text_safe(&state->peer, peer_text, sizeof(peer_text));
        state->opening_conn = state->primary_conn;
        lantern_log_debug(
            "gossip",
            &(const struct lantern_log_metadata){.peer = peer_text[0] ? peer_text : NULL},
            "opening gossipsub writer on primary connection inbound=%u",
            (unsigned)state->primary_inbound);
        return 0;
    }

    schedule_writer_retry(state, now_us);
    return -1;
}

static void maybe_repair_writer(
    struct lantern_gossipsub_service *service,
    struct lantern_gossipsub_peer_connection_state *state,
    libp2p_host_time_us_t now_us) {
    if (!service || !state || !state->used || state->conn_count == 0) {
        return;
    }
    peer_state_select_primary(service, state);
    (void)open_primary_writer(service, state, now_us);
}

static void add_peer_connection(
    struct lantern_gossipsub_service *service,
    libp2p_host_conn_t *conn,
    int inbound,
    libp2p_host_time_us_t now_us) {
    struct lantern_peer_id peer;
    if (peer_from_conn(conn, &peer) != 0) {
        return;
    }
    struct lantern_gossipsub_peer_connection_state *state = find_peer_state(service, &peer, 1);
    if (!state) {
        (void)libp2p_host_conn_close(service->network->host, conn, 0);
        return;
    }

    ssize_t existing = peer_state_conn_index(state, conn);
    if (existing >= 0) {
        state->conn_inbound[(size_t)existing] = inbound ? 1 : 0;
        state->conn_closing[(size_t)existing] = 0;
    } else if (state->conn_count < LANTERN_GOSSIPSUB_MAX_CONNS_PER_PEER) {
        state->conns[state->conn_count] = conn;
        state->conn_inbound[state->conn_count] = inbound ? 1 : 0;
        state->conn_closing[state->conn_count] = 0;
        state->conn_count++;
    } else {
        (void)libp2p_host_conn_close(service->network->host, conn, 0);
        return;
    }

    maybe_repair_writer(service, state, now_us);
}

static void remove_peer_connection(
    struct lantern_gossipsub_service *service,
    libp2p_host_conn_t *conn,
    libp2p_host_time_us_t now_us) {
    struct lantern_gossipsub_peer_connection_state *state = find_peer_state_by_conn(service, conn);
    if (!state) {
        return;
    }
    ssize_t found = peer_state_conn_index(state, conn);
    if (found >= 0) {
        size_t index = (size_t)found;
        for (size_t i = index + 1; i < state->conn_count; i++) {
            state->conns[i - 1] = state->conns[i];
            state->conn_inbound[i - 1] = state->conn_inbound[i];
            state->conn_closing[i - 1] = state->conn_closing[i];
        }
        state->conn_count--;
        if (state->conn_count < LANTERN_GOSSIPSUB_MAX_CONNS_PER_PEER) {
            state->conns[state->conn_count] = NULL;
            state->conn_inbound[state->conn_count] = 0;
            state->conn_closing[state->conn_count] = 0;
        }
    }
    if (state->primary_conn == conn) {
        state->primary_conn = NULL;
        state->primary_inbound = 0;
    }
    if (state->writer_conn == conn) {
        state->writer_conn = NULL;
        state->writer_stream = NULL;
    }
    if (state->opening_conn == conn) {
        state->opening_conn = NULL;
        schedule_writer_retry(state, now_us);
    }
    if (state->conn_count == 0) {
        memset(state, 0, sizeof(*state));
        return;
    }
    maybe_repair_writer(service, state, now_us);
}

static void handle_writer_open_failed(
    struct lantern_gossipsub_service *service,
    libp2p_host_conn_t *conn,
    libp2p_host_time_us_t now_us) {
    struct lantern_gossipsub_peer_connection_state *state = find_peer_state_by_conn(service, conn);
    if (!state) {
        return;
    }
    if (state->opening_conn == conn) {
        state->opening_conn = NULL;
        schedule_writer_retry(state, now_us);
    }
}

static void repair_all_writers(struct lantern_gossipsub_service *service, libp2p_host_time_us_t now_us) {
    if (!service) {
        return;
    }
    for (size_t i = 0; i < LANTERN_GOSSIPSUB_MAX_TRACKED_PEERS; i++) {
        if (service->peer_connections[i].used) {
            maybe_repair_writer(service, &service->peer_connections[i], now_us);
        }
    }
}

static libp2p_gossipsub_err_t lantern_gossipsub_message_id(
    const libp2p_gossipsub_message_t *message,
    uint8_t *out,
    size_t out_len,
    size_t *written,
    void *user_data) {
    (void)user_data;
    if (!message || !written) {
        return LIBP2P_GOSSIPSUB_ERR_INVALID_ARG;
    }
    *written = LANTERN_GOSSIP_MESSAGE_ID_SIZE;
    if (!out || out_len < LANTERN_GOSSIP_MESSAGE_ID_SIZE) {
        return LIBP2P_GOSSIPSUB_ERR_BUF_TOO_SMALL;
    }

    LanternGossipMessageId id;
    uint8_t stack_scratch[4096];
    size_t required = 0;
    int rc = lantern_gossip_compute_message_id(
        &id,
        message->topic.data,
        message->topic.len,
        message->data.data,
        message->data.len,
        stack_scratch,
        sizeof(stack_scratch),
        &required);
    if (rc != 0 && required > sizeof(stack_scratch)) {
        uint8_t *scratch = (uint8_t *)malloc(required);
        if (!scratch) {
            return LIBP2P_GOSSIPSUB_ERR_INTERNAL;
        }
        rc = lantern_gossip_compute_message_id(
            &id,
            message->topic.data,
            message->topic.len,
            message->data.data,
            message->data.len,
            scratch,
            required,
            NULL);
        free(scratch);
    }
    if (rc != 0) {
        return LIBP2P_GOSSIPSUB_ERR_INTERNAL;
    }
    memcpy(out, id.bytes, LANTERN_GOSSIP_MESSAGE_ID_SIZE);
    return LIBP2P_GOSSIPSUB_OK;
}

enum gossipsub_payload_kind {
    GOSSIPSUB_PAYLOAD_BLOCK,
    GOSSIPSUB_PAYLOAD_VOTE,
    GOSSIPSUB_PAYLOAD_AGGREGATED_ATTESTATION,
};

static int encode_payload(
    enum gossipsub_payload_kind kind,
    const void *payload,
    uint8_t **out,
    size_t *out_len) {
    if (!payload || !out || !out_len) {
        return -1;
    }
    uint8_t *buffer = (uint8_t *)malloc(LANTERN_GOSSIP_ENCODE_BUFFER_BYTES);
    if (!buffer) {
        return -1;
    }
    size_t written = 0;
    int rc = -1;
    switch (kind) {
    case GOSSIPSUB_PAYLOAD_BLOCK:
        rc = lantern_gossip_encode_signed_block_snappy(
            (const LanternSignedBlock *)payload,
            buffer,
            LANTERN_GOSSIP_ENCODE_BUFFER_BYTES,
            &written);
        break;
    case GOSSIPSUB_PAYLOAD_VOTE:
        rc = lantern_gossip_encode_signed_vote_snappy(
            (const LanternSignedVote *)payload,
            buffer,
            LANTERN_GOSSIP_ENCODE_BUFFER_BYTES,
            &written);
        break;
    case GOSSIPSUB_PAYLOAD_AGGREGATED_ATTESTATION:
        rc = lantern_gossip_encode_signed_aggregated_attestation_snappy(
            (const LanternSignedAggregatedAttestation *)payload,
            buffer,
            LANTERN_GOSSIP_ENCODE_BUFFER_BYTES,
            &written);
        break;
    }
    if (rc != 0) {
        free(buffer);
        return -1;
    }
    *out = buffer;
    *out_len = written;
    return 0;
}

static int deliver_message(
    struct lantern_gossipsub_service *service,
    const libp2p_gossipsub_event_t *event) {
    struct lantern_peer_id peer = {0};
    if (event->peer.len <= sizeof(peer.bytes)) {
        memcpy(peer.bytes, event->peer.data, event->peer.len);
        peer.len = event->peer.len;
    }

    if (topic_eq(event->topic, service->block_topic)) {
        LanternSignedBlock block;
        lantern_signed_block_init(&block);
        uint8_t *raw = NULL;
        size_t raw_len = 0;
        int rc = lantern_gossip_decode_signed_block_snappy(
            &block,
            event->message.data.data,
            event->message.data.len,
            &raw,
            &raw_len);
        if (rc == 0 && service->block_handler) {
            rc = service->block_handler(
                &block,
                &peer,
                raw,
                raw_len,
                service->block_handler_user_data);
        }
        free(raw);
        lantern_signed_block_reset(&block);
        return rc;
    }

    if (topic_is_vote_topic(service, event->topic)) {
        LanternSignedVote vote;
        memset(&vote, 0, sizeof(vote));
        int rc = lantern_gossip_decode_signed_vote_snappy(&vote, event->message.data.data, event->message.data.len);
        if (rc == 0 && service->vote_handler) {
            rc = service->vote_handler(
                &vote,
                &peer,
                event->message.data.data,
                event->message.data.len,
                service->vote_handler_user_data);
        }
        return rc;
    }

    if (topic_eq(event->topic, service->aggregated_attestation_topic)) {
        LanternSignedAggregatedAttestation attestation;
        lantern_signed_aggregated_attestation_init(&attestation);
        int rc = lantern_gossip_decode_signed_aggregated_attestation_snappy(
            &attestation,
            event->message.data.data,
            event->message.data.len);
        if (rc == 0 && service->aggregated_attestation_handler) {
            rc = service->aggregated_attestation_handler(
                &attestation,
                &peer,
                event->message.data.data,
                event->message.data.len,
                service->aggregated_attestation_handler_user_data);
        }
        lantern_signed_aggregated_attestation_reset(&attestation);
        return rc;
    }

    return -1;
}

static libp2p_gossipsub_validation_result_t validation_result_from_delivery_rc(int rc) {
    if (rc == LANTERN_CLIENT_OK) {
        return LIBP2P_GOSSIPSUB_VALIDATION_ACCEPT;
    }
    if (rc == LANTERN_CLIENT_ERR_IGNORED) {
        return LIBP2P_GOSSIPSUB_VALIDATION_IGNORE;
    }
    return LIBP2P_GOSSIPSUB_VALIDATION_REJECT;
}

static const char *validation_result_name(libp2p_gossipsub_validation_result_t result) {
    switch (result) {
        case LIBP2P_GOSSIPSUB_VALIDATION_ACCEPT:
            return "accept";
        case LIBP2P_GOSSIPSUB_VALIDATION_REJECT:
            return "reject";
        case LIBP2P_GOSSIPSUB_VALIDATION_IGNORE:
            return "ignore";
    }
    return "unknown";
}

static void handle_gossipsub_peer_opened(
    struct lantern_gossipsub_service *service,
    const libp2p_gossipsub_event_t *event,
    libp2p_host_time_us_t now_us) {
    struct lantern_peer_id peer;
    if (peer_from_gossipsub_event(event, &peer) != 0) {
        return;
    }
    struct lantern_gossipsub_peer_connection_state *state = find_peer_state(service, &peer, 1);
    if (!state) {
        return;
    }

    if (event->direction == LIBP2P_HOST_STREAM_OUTBOUND) {
        if (!state->writer_stream && (!state->opening_conn || event->conn == state->opening_conn)) {
            state->writer_conn = event->conn;
            state->writer_stream = event->stream;
            state->opening_conn = NULL;
            reset_writer_retry(state);
        } else {
            if (event->stream && service->network && service->network->host) {
                (void)libp2p_host_stream_reset(service->network->host, event->stream, 0);
            }
            if (event->conn && event->conn == state->opening_conn) {
                state->opening_conn = NULL;
                schedule_writer_retry(state, now_us);
            }
        }
    }
}

static void handle_gossipsub_peer_closed(
    struct lantern_gossipsub_service *service,
    const libp2p_gossipsub_event_t *event,
    libp2p_host_time_us_t now_us) {
    struct lantern_gossipsub_peer_connection_state *state = NULL;
    struct lantern_peer_id peer;
    if (peer_from_gossipsub_event(event, &peer) == 0) {
        state = find_peer_state(service, &peer, 0);
    }
    if (!state && event->conn) {
        state = find_peer_state_by_conn(service, event->conn);
    }
    if (!state) {
        return;
    }

    int writer_closed =
        (event->stream && event->stream == state->writer_stream) ||
        (event->conn && event->conn == state->writer_conn);
    if (writer_closed) {
        if (event->stream && event->conn && event->conn != state->writer_conn &&
            service->network && service->network->host) {
            (void)libp2p_host_stream_reset(service->network->host, event->stream, 0);
        }
        state->writer_conn = NULL;
        state->writer_stream = NULL;
    }
    if (event->conn && event->conn == state->opening_conn) {
        state->opening_conn = NULL;
        schedule_writer_retry(state, now_us);
    }
    maybe_repair_writer(service, state, now_us);
}

static void drain_gossipsub_events(struct lantern_gossipsub_service *service, libp2p_host_time_us_t now_us) {
    libp2p_gossipsub_event_t event;
    while (1) {
        if (lock_gossipsub() != 0) {
            return;
        }
        if (!service->gossipsub) {
            unlock_gossipsub();
            return;
        }
        libp2p_gossipsub_err_t next_err = libp2p_gossipsub_next_event(service->gossipsub, &event);
        if (next_err != LIBP2P_GOSSIPSUB_OK) {
            unlock_gossipsub();
            return;
        }
        if (event.type == LIBP2P_GOSSIPSUB_EVENT_MESSAGE) {
            struct gossipsub_message_snapshot snapshot;
            int snapshot_ok = gossipsub_message_snapshot_init(&snapshot, &event) == 0;
            if (!snapshot_ok) {
                if (event.validation) {
                    (void)libp2p_gossipsub_report_validation(
                        service->gossipsub,
                        event.validation,
                        LIBP2P_GOSSIPSUB_VALIDATION_REJECT);
                }
                unlock_gossipsub();
                continue;
            }
            unlock_gossipsub();

            int delivery_rc = deliver_message(service, &snapshot.event);
            libp2p_gossipsub_validation_result_t validation_result =
                validation_result_from_delivery_rc(delivery_rc);
            if (event.validation && validation_result != LIBP2P_GOSSIPSUB_VALIDATION_ACCEPT) {
                void (*log_validation_result)(
                    const char *,
                    const struct lantern_log_metadata *,
                    const char *,
                    ...) =
                    validation_result == LIBP2P_GOSSIPSUB_VALIDATION_REJECT
                        ? lantern_log_warn
                        : lantern_log_debug;
                log_validation_result(
                    "gossip",
                    NULL,
                    "gossipsub validation result=%s rc=%d topic=%.*s",
                    validation_result_name(validation_result),
                    delivery_rc,
                    (int)snapshot.event.topic.len,
                    snapshot.event.topic.data ? (const char *)snapshot.event.topic.data : "");
            }
            if (event.validation) {
                if (lock_gossipsub() != 0) {
                    gossipsub_message_snapshot_reset(&snapshot);
                    return;
                }
                if (service->gossipsub) {
                    (void)libp2p_gossipsub_report_validation(
                        service->gossipsub,
                        event.validation,
                        validation_result);
                }
                unlock_gossipsub();
            }
            gossipsub_message_snapshot_reset(&snapshot);
        } else if (event.type == LIBP2P_GOSSIPSUB_EVENT_PEER_OPENED) {
            handle_gossipsub_peer_opened(service, &event, now_us);
            unlock_gossipsub();
        } else if (event.type == LIBP2P_GOSSIPSUB_EVENT_PEER_CLOSED) {
            handle_gossipsub_peer_closed(service, &event, now_us);
            unlock_gossipsub();
        } else if (event.type == LIBP2P_GOSSIPSUB_EVENT_PEER_FAILED) {
            if (event.conn) {
                handle_writer_open_failed(service, event.conn, now_us);
            }
            unlock_gossipsub();
        } else if (event.type == LIBP2P_GOSSIPSUB_EVENT_DROPPED || event.type == LIBP2P_GOSSIPSUB_EVENT_ERROR) {
            unlock_gossipsub();
            lantern_log_debug("gossip", NULL, "gossipsub event type=%d reason=%d", (int)event.type, (int)event.reason);
        } else {
            unlock_gossipsub();
        }
    }
}

static void gossipsub_host_event(
    struct lantern_libp2p_host *network,
    const libp2p_host_event_t *event,
    void *user_data) {
    struct lantern_gossipsub_service *service = (struct lantern_gossipsub_service *)user_data;
    if (!service || !service->gossipsub || !network || !network->host || !event) {
        return;
    }
    libp2p_host_time_us_t now_us = lantern_libp2p_now_us();
    if (lock_gossipsub() != 0) {
        return;
    }
    if (event->type == LIBP2P_HOST_EVENT_CONN_ESTABLISHED && event->conn) {
        add_peer_connection(service, event->conn, event->dial == NULL, now_us);
    }
    (void)libp2p_gossipsub_handle_host_event(service->gossipsub, network->host, event);
    if (event->type == LIBP2P_HOST_EVENT_CONN_CLOSED && event->conn) {
        remove_peer_connection(service, event->conn, now_us);
    } else if (event->type == LIBP2P_HOST_EVENT_STREAM_OPEN_FAILED && event->conn) {
        handle_writer_open_failed(service, event->conn, now_us);
    }
    unlock_gossipsub();
}

static void gossipsub_drive(
    struct lantern_libp2p_host *network,
    libp2p_host_time_us_t now_us,
    void *user_data) {
    struct lantern_gossipsub_service *service = (struct lantern_gossipsub_service *)user_data;
    if (!service || !service->gossipsub || !network || !network->host) {
        return;
    }
    if (lock_gossipsub() != 0) {
        return;
    }
    (void)libp2p_gossipsub_drive(service->gossipsub, network->host, now_us, NULL);
    repair_all_writers(service, now_us);
    unlock_gossipsub();
    drain_gossipsub_events(service, now_us);
}

static int subscribe_topic(struct lantern_gossipsub_service *service, const char *topic) {
    libp2p_gossipsub_topic_config_t topic_config = {
        .topic = {.data = (const uint8_t *)topic, .len = strlen(topic)},
        .validation_mode = LIBP2P_GOSSIPSUB_VALIDATION_REQUIRE_APP,
        .enable_idontwant = 1,
        .idontwant_min_message_bytes = LIBP2P_GOSSIPSUB_DEFAULT_IDONTWANT_MIN_BYTES,
    };
    if (lock_gossipsub() != 0) {
        return -1;
    }
    int rc = service->gossipsub &&
            libp2p_gossipsub_subscribe(service->gossipsub, &topic_config) == LIBP2P_GOSSIPSUB_OK
        ? 0
        : -1;
    unlock_gossipsub();
    return rc;
}

static bool topic_is_vote_topic(
    const struct lantern_gossipsub_service *service,
    const libp2p_gossipsub_bytes_t topic) {
    if (topic_eq(topic, service->vote_topic) || topic_eq(topic, service->vote_subnet_topic)) {
        return true;
    }
    for (size_t i = 0; i < service->extra_vote_subnet_topic_count; ++i) {
        if (topic_eq(topic, service->extra_vote_subnet_topics[i])) {
            return true;
        }
    }
    return false;
}

static int remember_vote_subnet_topic(
    struct lantern_gossipsub_service *service,
    size_t subnet_id,
    const char *topic) {
    if (!service || !topic || topic[0] == '\0') {
        return -1;
    }
    if (subnet_id == service->attestation_subnet_id) {
        snprintf(service->vote_subnet_topic, sizeof(service->vote_subnet_topic), "%s", topic);
        return 0;
    }
    for (size_t i = 0; i < service->extra_vote_subnet_topic_count; ++i) {
        if (strcmp(service->extra_vote_subnet_topics[i], topic) == 0) {
            return 0;
        }
    }
    if (service->extra_vote_subnet_topic_count == SIZE_MAX ||
        (service->extra_vote_subnet_topic_count + 1u) > SIZE_MAX / sizeof(*service->extra_vote_subnet_topics)) {
        return -1;
    }
    size_t next_count = service->extra_vote_subnet_topic_count + 1u;
    char (*next_topics)[128] = realloc(
        service->extra_vote_subnet_topics,
        next_count * sizeof(*next_topics));
    if (!next_topics) {
        return -1;
    }
    service->extra_vote_subnet_topics = next_topics;
    snprintf(
        service->extra_vote_subnet_topics[service->extra_vote_subnet_topic_count],
        sizeof(service->extra_vote_subnet_topics[service->extra_vote_subnet_topic_count]),
        "%s",
        topic);
    service->extra_vote_subnet_topic_count = next_count;
    return 0;
}

static int setup_topics(struct lantern_gossipsub_service *service, const struct lantern_gossipsub_config *config) {
    snprintf(service->topic_network_name, sizeof(service->topic_network_name), "%s", config->topic_network_name);
    memcpy(service->fork_digest, config->fork_digest, sizeof(service->fork_digest));
    service->attestation_subnet_id = config->attestation_subnet_id;
    service->subscribe_attestation_subnet = config->subscribe_attestation_subnet ? 1 : 0;
    return lantern_gossip_topic_format(
               LANTERN_GOSSIP_TOPIC_BLOCK,
               service->topic_network_name,
               service->block_topic,
               sizeof(service->block_topic)) == 0 &&
            lantern_gossip_topic_format(
               LANTERN_GOSSIP_TOPIC_VOTE,
               service->topic_network_name,
               service->vote_topic,
               sizeof(service->vote_topic)) == 0 &&
            lantern_gossip_topic_format_subnet(
               LANTERN_GOSSIP_TOPIC_VOTE_SUBNET,
               service->topic_network_name,
               service->attestation_subnet_id,
               service->vote_subnet_topic,
               sizeof(service->vote_subnet_topic)) == 0 &&
            lantern_gossip_topic_format(
               LANTERN_GOSSIP_TOPIC_AGGREGATED_ATTESTATION,
               service->topic_network_name,
               service->aggregated_attestation_topic,
               sizeof(service->aggregated_attestation_topic)) == 0
        ? 0
        : -1;
}

void lantern_gossipsub_service_init(struct lantern_gossipsub_service *service) {
    if (service) {
        memset(service, 0, sizeof(*service));
    }
}

void lantern_gossipsub_service_stop(struct lantern_gossipsub_service *service) {
    if (!service || !service->gossipsub) {
        return;
    }
    if (service->network && service->network->host) {
        if (lock_gossipsub() != 0) {
            return;
        }
        (void)libp2p_gossipsub_close(service->gossipsub, service->network->host, 0);
        unlock_gossipsub();
    }
}

void lantern_gossipsub_service_reset(struct lantern_gossipsub_service *service) {
    if (!service) {
        return;
    }
    lantern_gossipsub_service_stop(service);
    if (service->gossipsub) {
        if (lock_gossipsub() != 0) {
            return;
        }
        libp2p_gossipsub_deinit(service->gossipsub);
        service->gossipsub = NULL;
        unlock_gossipsub();
    }
    free(service->gossipsub_storage);
    free(service->extra_vote_subnet_topics);

    int (*publish_hook)(const char *, const uint8_t *, size_t, void *) = service->publish_hook;
    void *publish_user_data = service->publish_hook_user_data;
    int loopback_only = service->loopback_only;
    lantern_gossipsub_block_handler block_handler = service->block_handler;
    void *block_user_data = service->block_handler_user_data;
    lantern_gossipsub_vote_handler vote_handler = service->vote_handler;
    void *vote_user_data = service->vote_handler_user_data;
    lantern_gossipsub_aggregated_attestation_handler aggregate_handler = service->aggregated_attestation_handler;
    void *aggregate_user_data = service->aggregated_attestation_handler_user_data;

    memset(service, 0, sizeof(*service));
    service->publish_hook = publish_hook;
    service->publish_hook_user_data = publish_user_data;
    service->loopback_only = loopback_only;
    service->block_handler = block_handler;
    service->block_handler_user_data = block_user_data;
    service->vote_handler = vote_handler;
    service->vote_handler_user_data = vote_user_data;
    service->aggregated_attestation_handler = aggregate_handler;
    service->aggregated_attestation_handler_user_data = aggregate_user_data;
}

int lantern_gossipsub_service_start(
    struct lantern_gossipsub_service *service,
    const struct lantern_gossipsub_config *config) {
    if (!service || !config || !config->topic_network_name) {
        return -1;
    }

    lantern_gossipsub_service_reset(service);
    service->network = config->network;
    service->data_dir = config->data_dir;
    service->devnet = config->devnet;
    if (setup_topics(service, config) != 0) {
        return -1;
    }
    if (service->loopback_only || !service->network || !service->network->host) {
        return 0;
    }

    libp2p_gossipsub_config_t gs_config;
    if (libp2p_gossipsub_config_default(&gs_config) != LIBP2P_GOSSIPSUB_OK) {
        return -1;
    }
    gs_config.random_fn = lantern_libp2p_gossipsub_random;
    gs_config.message_id_fn = lantern_gossipsub_message_id;
    /* Match leanSpec's 10 MiB max networking payload; hash-sig blocks exceed libp2p's 1 MiB defaults. */
    gs_config.limits.max_message_data_bytes = LANTERN_GOSSIP_MAX_MESSAGE_BYTES;
    gs_config.limits.max_rpc_bytes = LANTERN_GOSSIP_MAX_RPC_BYTES;
    gs_config.capacity.tx_buffer_bytes = LANTERN_GOSSIP_TX_BUFFER_BYTES;
    gs_config.capacity.mcache_bytes = LANTERN_GOSSIP_MCACHE_BYTES;
    gs_config.mesh.enable_flood_publish = 1;
    gs_config.mesh.seen_ttl_us = 120000000ull;
    gs_config.protocol_mask = LIBP2P_GOSSIPSUB_PROTOCOL_MASK_ALL;
    gs_config.preferred_protocol = LIBP2P_GOSSIPSUB_VERSION_12;

    if (libp2p_gossipsub_storage_size(&gs_config, &service->gossipsub_storage_len) !=
        LIBP2P_GOSSIPSUB_OK) {
        return -1;
    }
    service->gossipsub_storage = calloc(1u, service->gossipsub_storage_len);
    if (!service->gossipsub_storage) {
        return -1;
    }
    if (libp2p_gossipsub_init(
            service->gossipsub_storage,
            service->gossipsub_storage_len,
            &gs_config,
            &service->gossipsub)
        != LIBP2P_GOSSIPSUB_OK) {
        return -1;
    }
    if (libp2p_gossipsub_protocols(
            service->gossipsub,
            service->gossipsub_protocols,
            LIBP2P_GOSSIPSUB_PROTOCOL_COUNT,
            &service->gossipsub_protocol_count)
        != LIBP2P_GOSSIPSUB_OK) {
        return -1;
    }
    wrap_gossipsub_protocols(service);
    for (size_t i = 0; i < service->gossipsub_protocol_count; i++) {
        if (lantern_libp2p_host_register_protocol(service->network, &service->gossipsub_protocols[i]) != 0) {
            return -1;
        }
    }
    if (subscribe_topic(service, service->block_topic) != 0) {
        return -1;
    }
    if (service->subscribe_attestation_subnet) {
        if (subscribe_topic(service, service->vote_subnet_topic) != 0) {
            return -1;
        }
    } else if (subscribe_topic(service, service->vote_topic) != 0) {
        return -1;
    }
    if (subscribe_topic(service, service->aggregated_attestation_topic) != 0) {
        return -1;
    }
    if (libp2p_gossipsub_start(service->gossipsub, service->network->host, lantern_libp2p_now_us()) !=
        LIBP2P_GOSSIPSUB_OK) {
        return -1;
    }
    if (lantern_libp2p_host_register_event_handler(service->network, gossipsub_host_event, service) != 0 ||
        lantern_libp2p_host_register_drive_handler(service->network, gossipsub_drive, service) != 0) {
        return -1;
    }

    lantern_log_info("network", &(const struct lantern_log_metadata){.peer = config->devnet}, "gossipsub topics ready");
    return 0;
}

static int publish_payload(
    struct lantern_gossipsub_service *service,
    const char *topic,
    const uint8_t *payload,
    size_t payload_len) {
    if (!service || !topic || !payload || payload_len == 0) {
        return -1;
    }
    if (service->publish_hook &&
        service->publish_hook(topic, payload, payload_len, service->publish_hook_user_data) != 0) {
        return -1;
    }
    if (service->loopback_only) {
        return 0;
    }
    if (!service->gossipsub) {
        return -1;
    }
    libp2p_gossipsub_publish_t publish = {
        .topic = {.data = (const uint8_t *)topic, .len = strlen(topic)},
        .data = {.data = payload, .len = payload_len},
        .message_id = {.data = NULL, .len = 0},
        .user_data = NULL,
    };
    if (lock_gossipsub() != 0) {
        return -1;
    }
    int rc = service->gossipsub &&
            libp2p_gossipsub_publish(service->gossipsub, &publish, NULL, 0, NULL) == LIBP2P_GOSSIPSUB_OK
        ? 0
        : -1;
    unlock_gossipsub();
    return rc;
}

int lantern_gossipsub_service_publish_block(
    struct lantern_gossipsub_service *service,
    const LanternSignedBlock *block) {
    if (!service || !block || service->block_topic[0] == '\0') {
        return -1;
    }
    uint8_t *payload = NULL;
    size_t payload_len = 0;
    int rc = encode_payload(GOSSIPSUB_PAYLOAD_BLOCK, block, &payload, &payload_len);
    if (rc == 0) {
        rc = publish_payload(service, service->block_topic, payload, payload_len);
    }
    free(payload);
    return rc;
}

int lantern_gossipsub_service_publish_vote_subnet(
    struct lantern_gossipsub_service *service,
    const LanternSignedVote *vote,
    size_t subnet_id) {
    if (!service || !vote) {
        return -1;
    }
    char topic[128];
    const char *publish_topic = service->vote_topic;
    if (subnet_id != service->attestation_subnet_id || service->vote_subnet_topic[0] == '\0') {
        if (lantern_gossip_topic_format_subnet(
                LANTERN_GOSSIP_TOPIC_VOTE_SUBNET,
                service->topic_network_name,
                subnet_id,
                topic,
                sizeof(topic))
            != 0) {
            return -1;
        }
        publish_topic = topic;
    } else if (service->subscribe_attestation_subnet) {
        publish_topic = service->vote_subnet_topic;
    }
    uint8_t *payload = NULL;
    size_t payload_len = 0;
    int rc = encode_payload(GOSSIPSUB_PAYLOAD_VOTE, vote, &payload, &payload_len);
    if (rc == 0) {
        rc = publish_payload(service, publish_topic, payload, payload_len);
    }
    free(payload);
    return rc;
}

int lantern_gossipsub_service_publish_aggregated_attestation(
    struct lantern_gossipsub_service *service,
    const LanternSignedAggregatedAttestation *attestation) {
    if (!service || !attestation || service->aggregated_attestation_topic[0] == '\0') {
        return -1;
    }
    uint8_t *payload = NULL;
    size_t payload_len = 0;
    int rc = encode_payload(GOSSIPSUB_PAYLOAD_AGGREGATED_ATTESTATION, attestation, &payload, &payload_len);
    if (rc == 0) {
        rc = publish_payload(service, service->aggregated_attestation_topic, payload, payload_len);
    }
    free(payload);
    return rc;
}

int lantern_gossipsub_service_subscribe_attestation_subnet(
    struct lantern_gossipsub_service *service,
    size_t subnet_id) {
    if (!service) {
        return -1;
    }
    char topic[128];
    if (lantern_gossip_topic_format_subnet(
            LANTERN_GOSSIP_TOPIC_VOTE_SUBNET,
            service->topic_network_name,
            subnet_id,
            topic,
            sizeof(topic))
        != 0) {
        return -1;
    }
    if (service->gossipsub && !service->loopback_only && subscribe_topic(service, topic) != 0) {
        return -1;
    }
    return remember_vote_subnet_topic(service, subnet_id, topic);
}

size_t lantern_gossipsub_service_mesh_peer_count(const struct lantern_gossipsub_service *service) {
    size_t count = 0;
    if (!service || lock_gossipsub() != 0) {
        return 0;
    }
    if (service->gossipsub) {
        (void)libp2p_gossipsub_mesh_peer_count(service->gossipsub, &count);
    }
    unlock_gossipsub();
    return count;
}

void lantern_gossipsub_service_set_publish_hook(
    struct lantern_gossipsub_service *service,
    int (*hook)(const char *topic, const uint8_t *payload, size_t payload_len, void *user_data),
    void *user_data) {
    if (service) {
        service->publish_hook = hook;
        service->publish_hook_user_data = user_data;
    }
}

void lantern_gossipsub_service_set_loopback_only(
    struct lantern_gossipsub_service *service,
    int loopback_only) {
    if (service) {
        service->loopback_only = loopback_only ? 1 : 0;
    }
}

void lantern_gossipsub_service_set_block_handler(
    struct lantern_gossipsub_service *service,
    lantern_gossipsub_block_handler handler,
    void *user_data) {
    if (service) {
        service->block_handler = handler;
        service->block_handler_user_data = user_data;
    }
}

void lantern_gossipsub_service_set_vote_handler(
    struct lantern_gossipsub_service *service,
    lantern_gossipsub_vote_handler handler,
    void *user_data) {
    if (service) {
        service->vote_handler = handler;
        service->vote_handler_user_data = user_data;
    }
}

void lantern_gossipsub_service_set_aggregated_attestation_handler(
    struct lantern_gossipsub_service *service,
    lantern_gossipsub_aggregated_attestation_handler handler,
    void *user_data) {
    if (service) {
        service->aggregated_attestation_handler = handler;
        service->aggregated_attestation_handler_user_data = user_data;
    }
}
