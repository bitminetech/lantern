#include "lantern/networking/libp2p.h"

#include "lantern/networking/enr.h"
#include "lantern/support/log.h"
#include "lantern/support/time.h"

#include "multiformats/multiaddr/multiaddr.h"

#include <openssl/rand.h>

#include <arpa/inet.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static void *lantern_quic_malloc(size_t size, void *user_data) {
    (void)user_data;
    return malloc(size);
}

static void *lantern_quic_calloc(size_t nmemb, size_t size, void *user_data) {
    (void)user_data;
    return calloc(nmemb, size);
}

static void *lantern_quic_realloc(void *ptr, size_t size, void *user_data) {
    (void)user_data;
    return realloc(ptr, size);
}

static void lantern_quic_free(void *ptr, void *user_data) {
    (void)user_data;
    free(ptr);
}

static libp2p_quic_err_t lantern_quic_unix_time(uint64_t *out_unix_seconds, void *user_data) {
    (void)user_data;
    if (!out_unix_seconds) {
        return LIBP2P_QUIC_ERR_INVALID_ARG;
    }
    time_t now = time(NULL);
    if (now < 0) {
        return LIBP2P_QUIC_ERR_INTERNAL;
    }
    *out_unix_seconds = (uint64_t)now;
    return LIBP2P_QUIC_OK;
}

static libp2p_ping_err_t lantern_ping_random(uint8_t *out, size_t out_len, void *user_data) {
    return lantern_libp2p_quic_random(out, out_len, user_data) == LIBP2P_QUIC_OK
        ? LIBP2P_PING_OK
        : LIBP2P_PING_ERR_RANDOM;
}

static libp2p_ping_err_t lantern_ping_time(libp2p_host_time_us_t *out_now_us, void *user_data) {
    (void)user_data;
    if (!out_now_us) {
        return LIBP2P_PING_ERR_INVALID_ARG;
    }
    *out_now_us = lantern_libp2p_now_us();
    return LIBP2P_PING_OK;
}

libp2p_host_time_us_t lantern_libp2p_now_us(void) {
    double seconds = lantern_time_now_seconds();
    if (seconds <= 0.0) {
        return 0;
    }
    return (libp2p_host_time_us_t)(seconds * 1000000.0);
}

libp2p_quic_err_t lantern_libp2p_quic_random(uint8_t *out, size_t out_len, void *user_data) {
    (void)user_data;
    if (!out && out_len != 0) {
        return LIBP2P_QUIC_ERR_INVALID_ARG;
    }
    if (out_len == 0) {
        return LIBP2P_QUIC_OK;
    }
    return RAND_bytes(out, out_len) == 1 ? LIBP2P_QUIC_OK : LIBP2P_QUIC_ERR_INTERNAL;
}

libp2p_gossipsub_err_t lantern_libp2p_gossipsub_random(
    uint8_t *out,
    size_t out_len,
    void *user_data) {
    return lantern_libp2p_quic_random(out, out_len, user_data) == LIBP2P_QUIC_OK
        ? LIBP2P_GOSSIPSUB_OK
        : LIBP2P_GOSSIPSUB_ERR_RANDOM;
}

static int register_default_protocols(struct lantern_libp2p_host *state) {
    libp2p_ping_config_t ping_config;
    libp2p_identify_config_t identify_config;
    static const uint8_t protocol_version[] = "ipfs/0.1.0";
    static const uint8_t agent_version[] = "lantern";

    if (libp2p_ping_config_default(&ping_config) != LIBP2P_PING_OK) {
        return -1;
    }
    ping_config.random_fn = lantern_ping_random;
    ping_config.time_fn = lantern_ping_time;
    if (libp2p_ping_init(&state->ping, &ping_config) != LIBP2P_PING_OK) {
        return -1;
    }
    if (libp2p_ping_protocol(&state->ping, &state->default_protocols[state->default_protocol_count]) !=
        LIBP2P_PING_OK) {
        return -1;
    }
    state->default_protocol_count++;

    if (libp2p_identify_config_default(&identify_config) != LIBP2P_IDENTIFY_OK) {
        return -1;
    }
    identify_config.local_message.protocol_version.data = protocol_version;
    identify_config.local_message.protocol_version.len = sizeof(protocol_version) - 1u;
    identify_config.local_message.agent_version.data = agent_version;
    identify_config.local_message.agent_version.len = sizeof(agent_version) - 1u;
    identify_config.local_message.public_key.data = state->host_identity_storage.public_key_message;
    identify_config.local_message.public_key.len = state->host_identity_storage.public_key_message_len;
    if (libp2p_identify_init(&state->identify, &identify_config) != LIBP2P_IDENTIFY_OK) {
        return -1;
    }
    if (libp2p_identify_protocol(
            &state->identify,
            &state->default_protocols[state->default_protocol_count])
        != LIBP2P_IDENTIFY_OK) {
        return -1;
    }
    state->default_protocol_count++;
    if (libp2p_identify_push_protocol(
            &state->identify,
            &state->default_protocols[state->default_protocol_count])
        != LIBP2P_IDENTIFY_OK) {
        return -1;
    }
    state->default_protocol_count++;

    for (size_t i = 0; i < state->default_protocol_count; i++) {
        if (lantern_libp2p_host_register_protocol(state, &state->default_protocols[i]) != 0) {
            return -1;
        }
    }
    return 0;
}

static void drain_protocol_events(struct lantern_libp2p_host *state) {
    libp2p_ping_event_t ping_event;
    while (libp2p_ping_next_event(&state->ping, &ping_event) == LIBP2P_PING_OK) {
        if (ping_event.type == LIBP2P_PING_EVENT_ERROR) {
            lantern_log_debug("network", NULL, "libp2p ping event error (%d)", (int)ping_event.reason);
        }
    }

    libp2p_identify_event_t identify_event;
    while (libp2p_identify_next_event(&state->identify, &identify_event) == LIBP2P_IDENTIFY_OK) {
        if (identify_event.type == LIBP2P_IDENTIFY_EVENT_ERROR) {
            lantern_log_debug("network", NULL, "libp2p identify event error (%d)", (int)identify_event.reason);
        }
    }
}

static void drain_host_events(struct lantern_libp2p_host *state) {
    libp2p_host_event_t event;
    while (libp2p_host_next_event(state->host, &event) == LIBP2P_HOST_OK) {
        for (size_t i = 0; i < state->event_handler_count; i++) {
            state->event_handlers[i](state, &event, state->event_handler_user_data[i]);
        }
    }
}

static void *lantern_libp2p_drive_thread(void *arg) {
    struct lantern_libp2p_host *state = (struct lantern_libp2p_host *)arg;
    const struct timespec pause = {.tv_sec = 0, .tv_nsec = 5000000};

    while (__atomic_load_n(&state->stop_flag, __ATOMIC_RELAXED) == 0) {
        libp2p_host_time_us_t now = lantern_libp2p_now_us();
        (void)libp2p_host_drive(state->host, now, LIBP2P_HOST_READY_ALL, NULL);
        drain_host_events(state);
        for (size_t i = 0; i < state->drive_handler_count; i++) {
            state->drive_handlers[i](state, now, state->drive_handler_user_data[i]);
        }
        drain_protocol_events(state);
        (void)nanosleep(&pause, NULL);
    }
    return NULL;
}

void lantern_libp2p_host_init(struct lantern_libp2p_host *state) {
    if (!state) {
        return;
    }
    memset(state, 0, sizeof(*state));
}

void lantern_libp2p_host_stop(struct lantern_libp2p_host *state) {
    if (!state || !state->host) {
        return;
    }
    if (state->started) {
        (void)libp2p_host_close(state->host, 0);
    }
    __atomic_store_n(&state->stop_flag, 1, __ATOMIC_RELAXED);
    if (state->drive_thread_started) {
        (void)pthread_join(state->drive_thread, NULL);
        state->drive_thread_started = 0;
    }
    state->started = 0;
}

void lantern_libp2p_host_reset(struct lantern_libp2p_host *state) {
    if (!state) {
        return;
    }
    lantern_libp2p_host_stop(state);
    if (state->host) {
        libp2p_host_deinit(state->host);
        state->host = NULL;
    }
    free(state->host_storage);
    lantern_libp2p_host_init(state);
}

int lantern_libp2p_host_prepare(struct lantern_libp2p_host *state, const struct lantern_libp2p_config *config) {
    if (!state || !config || !config->listen_multiaddr || !config->secp256k1_secret) {
        return -1;
    }
    if (config->secret_len != LIBP2P_PEER_ID_SECP256K1_PRIVATE_KEY_BYTES) {
        lantern_log_error("network", NULL, "libp2p expects 32-byte secp256k1 secrets");
        return -1;
    }

    lantern_libp2p_host_reset(state);

    if (libp2p_multiaddr_from_string(
            config->listen_multiaddr,
            strlen(config->listen_multiaddr),
            state->listen_multiaddr,
            sizeof(state->listen_multiaddr),
            &state->listen_multiaddr_len)
        != LIBP2P_MULTIADDR_OK) {
        lantern_log_error(
            "network",
            &(const struct lantern_log_metadata){.peer = config->listen_multiaddr},
            "invalid listen multiaddr");
        return -1;
    }

    if (libp2p_host_secp256k1_identity_init(
            &state->host_identity_storage,
            config->secp256k1_secret,
            config->secret_len,
            &state->host_identity)
        != LIBP2P_HOST_OK) {
        return -1;
    }
    memcpy(state->local_peer_id, state->host_identity_storage.peer_id, state->host_identity_storage.peer_id_len);
    state->local_peer_id_len = state->host_identity_storage.peer_id_len;

    uint64_t unix_now = 0;
    if (lantern_quic_unix_time(&unix_now, NULL) != LIBP2P_QUIC_OK) {
        return -1;
    }
    libp2p_quic_host_key_t host_key = {
        .type = LIBP2P_QUIC_HOST_KEY_SECP256K1,
        .private_key = config->secp256k1_secret,
        .private_key_len = config->secret_len,
        .public_key_message = state->host_identity_storage.public_key_message,
        .public_key_message_len = state->host_identity_storage.public_key_message_len,
    };
    libp2p_quic_certificate_config_t certificate_config = {
        .certificate_key_type = LIBP2P_QUIC_CERT_KEY_ECDSA_P256,
        .not_before_unix_seconds = unix_now > 3600u ? unix_now - 3600u : 0u,
        .not_after_unix_seconds = unix_now + (uint64_t)(365u * 24u * 60u * 60u),
        .random_fn = lantern_libp2p_quic_random,
        .random_user_data = NULL,
    };
    size_t cert_len = 0;
    size_t key_len = 0;
    if (libp2p_quic_identity_write_certificate_der(
            &host_key,
            &certificate_config,
            state->certificate_der,
            sizeof(state->certificate_der),
            &cert_len,
            state->certificate_key_der,
            sizeof(state->certificate_key_der),
            &key_len)
        != LIBP2P_QUIC_OK) {
        return -1;
    }
    state->quic_identity.certificate_der = state->certificate_der;
    state->quic_identity.certificate_der_len = cert_len;
    state->quic_identity.certificate_private_key_der = state->certificate_key_der;
    state->quic_identity.certificate_private_key_der_len = key_len;
    state->quic_identity.peer_id = state->local_peer_id;
    state->quic_identity.peer_id_len = state->local_peer_id_len;

    state->allocator.malloc_fn = lantern_quic_malloc;
    state->allocator.calloc_fn = lantern_quic_calloc;
    state->allocator.realloc_fn = lantern_quic_realloc;
    state->allocator.free_fn = lantern_quic_free;
    state->allocator.user_data = NULL;

    if (libp2p_quic_service_config_default(&state->quic_config) != LIBP2P_QUIC_OK) {
        return -1;
    }
    state->quic_config.endpoint.role = LIBP2P_QUIC_ROLE_CLIENT_SERVER;
    state->quic_config.endpoint.identity = state->quic_identity;
    state->quic_config.endpoint.allocator = state->allocator;
    state->quic_config.endpoint.random_fn = lantern_libp2p_quic_random;
    state->quic_config.endpoint.unix_time_fn = lantern_quic_unix_time;
    state->quic_config.endpoint.max_connections = 64u;
    state->quic_config.endpoint.max_incoming_connections = 64u;
    state->quic_config.endpoint.max_outgoing_connections = 64u;
    state->quic_config.endpoint.max_bidi_streams = 128u;
    state->quic_config.max_rx_datagrams_per_drive = LIBP2P_QUIC_SERVICE_DEFAULT_DATAGRAM_BUDGET;
    state->quic_config.max_tx_datagrams_per_drive = LIBP2P_QUIC_SERVICE_DEFAULT_DATAGRAM_BUDGET;

    libp2p_host_config_t host_config;
    if (libp2p_host_config_default(&host_config) != LIBP2P_HOST_OK) {
        return -1;
    }
    host_config.identity = state->host_identity;
    host_config.listen_multiaddr = state->listen_multiaddr;
    host_config.listen_multiaddr_len = state->listen_multiaddr_len;
    host_config.transport = libp2p_host_quic_transport();
    host_config.transport_config = &state->quic_config;
    host_config.max_protocols = LANTERN_LIBP2P_MAX_PROTOCOLS;
    host_config.max_connections = 64u;
    host_config.max_streams_per_conn = 128u;
    host_config.max_pending_dials = 64u;
    host_config.max_pending_stream_opens = 128u;
    host_config.event_capacity = 256u;
    host_config.max_negotiation_steps = 128u;

    if (libp2p_host_storage_size(&host_config, &state->host_storage_len) != LIBP2P_HOST_OK) {
        return -1;
    }
    state->host_storage = calloc(1u, state->host_storage_len);
    if (!state->host_storage) {
        return -1;
    }
    if (libp2p_host_init(state->host_storage, state->host_storage_len, &host_config, &state->host) !=
        LIBP2P_HOST_OK) {
        return -1;
    }
    return register_default_protocols(state);
}

int lantern_libp2p_host_register_protocol(
    struct lantern_libp2p_host *state,
    const libp2p_host_protocol_t *protocol) {
    if (!state || !state->host || !protocol || state->started) {
        return -1;
    }
    return libp2p_host_handle(state->host, protocol) == LIBP2P_HOST_OK ? 0 : -1;
}

int lantern_libp2p_host_register_event_handler(
    struct lantern_libp2p_host *state,
    lantern_libp2p_host_event_handler handler,
    void *user_data) {
    if (!state || !handler || state->event_handler_count >= LANTERN_LIBP2P_MAX_EVENT_HANDLERS) {
        return -1;
    }
    size_t index = state->event_handler_count++;
    state->event_handlers[index] = handler;
    state->event_handler_user_data[index] = user_data;
    return 0;
}

int lantern_libp2p_host_register_drive_handler(
    struct lantern_libp2p_host *state,
    lantern_libp2p_drive_handler handler,
    void *user_data) {
    if (!state || !handler || state->drive_handler_count >= LANTERN_LIBP2P_MAX_DRIVE_HANDLERS) {
        return -1;
    }
    size_t index = state->drive_handler_count++;
    state->drive_handlers[index] = handler;
    state->drive_handler_user_data[index] = user_data;
    return 0;
}

int lantern_libp2p_host_launch(struct lantern_libp2p_host *state) {
    if (!state || !state->host || state->started) {
        return -1;
    }
    if (libp2p_host_start(state->host) != LIBP2P_HOST_OK) {
        lantern_log_error("network", NULL, "libp2p host start failed");
        return -1;
    }
    __atomic_store_n(&state->stop_flag, 0, __ATOMIC_RELAXED);
    if (pthread_create(&state->drive_thread, NULL, lantern_libp2p_drive_thread, state) != 0) {
        (void)libp2p_host_close(state->host, 0);
        return -1;
    }
    state->drive_thread_started = 1;
    state->started = 1;
    lantern_log_info("network", NULL, "libp2p host started");
    return 0;
}

int lantern_libp2p_host_start(struct lantern_libp2p_host *state, const struct lantern_libp2p_config *config) {
    if (lantern_libp2p_host_prepare(state, config) != 0) {
        return -1;
    }
    return lantern_libp2p_host_launch(state);
}

int lantern_peer_id_from_text(const char *text, struct lantern_peer_id *out_peer) {
    if (!text || !out_peer) {
        return -1;
    }
    size_t written = 0;
    if (libp2p_peer_id_from_string(text, strlen(text), out_peer->bytes, sizeof(out_peer->bytes), &written) !=
        LIBP2P_PEER_ID_OK) {
        return -1;
    }
    out_peer->len = written;
    return 0;
}

int lantern_peer_id_to_text(const struct lantern_peer_id *peer, char *buffer, size_t buffer_len) {
    if (!peer || !buffer || buffer_len == 0) {
        return -1;
    }
    size_t written = 0;
    if (libp2p_peer_id_to_string(peer->bytes, peer->len, buffer, buffer_len, &written) !=
        LIBP2P_PEER_ID_OK ||
        written >= buffer_len) {
        buffer[0] = '\0';
        return -1;
    }
    buffer[written] = '\0';
    return (int)written;
}

int lantern_peer_id_equal(const struct lantern_peer_id *left, const struct lantern_peer_id *right) {
    return left && right && left->len == right->len && memcmp(left->bytes, right->bytes, left->len) == 0;
}

static int extract_ipv4_multiaddr(
    const struct lantern_enr_record *record,
    char *buffer,
    size_t buffer_len) {
    const struct lantern_enr_key_value *ip = lantern_enr_record_find(record, "ip");
    const struct lantern_enr_key_value *port_field = lantern_enr_record_find(record, "quic");
    if (!port_field) {
        port_field = lantern_enr_record_find(record, "udp");
    }
    if (!ip || !port_field || ip->value_len != 4 || port_field->value_len != 2 || !port_field->value) {
        return -1;
    }
    uint16_t parsed_port = (uint16_t)(((uint16_t)port_field->value[0] << 8) | (uint16_t)port_field->value[1]);
    char ip_text[INET_ADDRSTRLEN];
    if (!inet_ntop(AF_INET, ip->value, ip_text, sizeof(ip_text))) {
        return -1;
    }
    int written = snprintf(buffer, buffer_len, "/ip4/%s/udp/%u/quic-v1", ip_text, (unsigned)parsed_port);
    return written >= 0 && (size_t)written < buffer_len ? 0 : -1;
}

static int extract_ipv6_multiaddr(
    const struct lantern_enr_record *record,
    char *buffer,
    size_t buffer_len) {
    const struct lantern_enr_key_value *ip = lantern_enr_record_find(record, "ip6");
    const struct lantern_enr_key_value *port_field = lantern_enr_record_find(record, "quic6");
    if (!port_field) {
        port_field = lantern_enr_record_find(record, "udp6");
    }
    if (!port_field) {
        port_field = lantern_enr_record_find(record, "quic");
    }
    if (!port_field) {
        port_field = lantern_enr_record_find(record, "udp");
    }
    if (!ip || !port_field || ip->value_len != 16 || port_field->value_len != 2 || !port_field->value) {
        return -1;
    }
    uint16_t parsed_port = (uint16_t)(((uint16_t)port_field->value[0] << 8) | (uint16_t)port_field->value[1]);
    char ip_text[INET6_ADDRSTRLEN];
    if (!inet_ntop(AF_INET6, ip->value, ip_text, sizeof(ip_text))) {
        return -1;
    }
    int written = snprintf(buffer, buffer_len, "/ip6/%s/udp/%u/quic-v1", ip_text, (unsigned)parsed_port);
    return written >= 0 && (size_t)written < buffer_len ? 0 : -1;
}

int lantern_libp2p_enr_to_multiaddr(
    const struct lantern_enr_record *record,
    char *buffer,
    size_t buffer_len,
    struct lantern_peer_id *peer_id) {
    if (!record || !buffer || buffer_len == 0 || !peer_id) {
        return -1;
    }

    const struct lantern_enr_key_value *pubkey = lantern_enr_record_find(record, "secp256k1");
    if (!pubkey || !pubkey->value || pubkey->value_len == 0) {
        return -1;
    }
    size_t peer_len = 0;
    if (libp2p_peer_id_from_secp256k1_public_key(
            pubkey->value,
            pubkey->value_len,
            peer_id->bytes,
            sizeof(peer_id->bytes),
            &peer_len)
        != LIBP2P_PEER_ID_OK) {
        return -1;
    }
    peer_id->len = peer_len;

    char base_addr[128];
    if (extract_ipv4_multiaddr(record, base_addr, sizeof(base_addr)) != 0 &&
        extract_ipv6_multiaddr(record, base_addr, sizeof(base_addr)) != 0) {
        return -1;
    }

    char peer_text[LANTERN_LIBP2P_PEER_TEXT_MAX_BYTES];
    if (lantern_peer_id_to_text(peer_id, peer_text, sizeof(peer_text)) < 0) {
        return -1;
    }
    int written = snprintf(buffer, buffer_len, "%s/p2p/%s", base_addr, peer_text);
    return written >= 0 && (size_t)written < buffer_len ? 0 : -1;
}

int lantern_libp2p_validate_enr_peer(const struct lantern_enr_record *record) {
    if (!record) {
        return -1;
    }
    struct lantern_peer_id peer_id;
    char multiaddr_text[LANTERN_LIBP2P_MULTIADDR_MAX_BYTES];
    uint8_t multiaddr[LANTERN_LIBP2P_MULTIADDR_MAX_BYTES];
    size_t multiaddr_len = 0;
    if (lantern_libp2p_enr_to_multiaddr(record, multiaddr_text, sizeof(multiaddr_text), &peer_id) != 0) {
        return -1;
    }
    if (libp2p_multiaddr_from_string(
            multiaddr_text,
            strlen(multiaddr_text),
            multiaddr,
            sizeof(multiaddr),
            &multiaddr_len)
        != LIBP2P_MULTIADDR_OK) {
        return -1;
    }
    return 0;
}

int lantern_libp2p_host_dial_multiaddr(
    struct lantern_libp2p_host *state,
    const char *multiaddr_text) {
    if (!state || !state->host || !multiaddr_text || multiaddr_text[0] == '\0') {
        return -1;
    }
    uint8_t multiaddr[LANTERN_LIBP2P_MULTIADDR_MAX_BYTES];
    size_t multiaddr_len = 0;
    if (libp2p_multiaddr_from_string(
            multiaddr_text,
            strlen(multiaddr_text),
            multiaddr,
            sizeof(multiaddr),
            &multiaddr_len)
        != LIBP2P_MULTIADDR_OK) {
        return -1;
    }
    libp2p_host_dial_t *dial = NULL;
    libp2p_host_err_t err = libp2p_host_dial(state->host, multiaddr, multiaddr_len, NULL, &dial);
    return err == LIBP2P_HOST_OK || err == LIBP2P_HOST_ERR_LIMIT ? 0 : -1;
}
