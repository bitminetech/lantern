#include "lantern/networking/libp2p.h"

#include "lantern/support/log.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#include <winsock2.h>
#include <ws2tcpip.h>
#else
#include <arpa/inet.h>
#endif

#include "lantern/networking/enr.h"

#include "libp2p/host.h"
#include "libp2p/log.h"
#include "libp2p/host_builder.h"
#include "libp2p/peerstore.h"
#include "multiformats/multiaddr/multiaddr.h"
#include "multiformats/multicodec/multicodec_codes.h"
#include "multiformats/unsigned_varint/unsigned_varint.h"
#include "peer_id/peer_id.h"
#include "peer_id/peer_id_proto.h"

#define LANTERN_LIBP2P_KEY_TYPE_SECP256K1 2u

static void lantern_libp2p_configure_logging(void);

static enum LanternLogLevel lantern_libp2p_convert_level(libp2p_log_level_t level)
{
    switch (level) {
    case LIBP2P_LOG_TRACE:
        return LANTERN_LOG_LEVEL_TRACE;
    case LIBP2P_LOG_DEBUG:
        return LANTERN_LOG_LEVEL_DEBUG;
    case LIBP2P_LOG_INFO:
        return LANTERN_LOG_LEVEL_INFO;
    case LIBP2P_LOG_WARN:
        return LANTERN_LOG_LEVEL_WARN;
    case LIBP2P_LOG_ERROR:
    default:
        return LANTERN_LOG_LEVEL_ERROR;
    }
}

static void lantern_libp2p_log_writer(libp2p_log_level_t level, const char *msg, void *ud)
{
    (void)ud;
    if (!msg) {
        return;
    }
    enum LanternLogLevel mapped = lantern_libp2p_convert_level(level);
    switch (mapped) {
    case LANTERN_LOG_LEVEL_TRACE:
        lantern_log_trace("libp2p", NULL, "%s", msg);
        break;
    case LANTERN_LOG_LEVEL_DEBUG:
        lantern_log_debug("libp2p", NULL, "%s", msg);
        break;
    case LANTERN_LOG_LEVEL_INFO:
        lantern_log_info("libp2p", NULL, "%s", msg);
        break;
    case LANTERN_LOG_LEVEL_WARN:
        lantern_log_warn("libp2p", NULL, "%s", msg);
        break;
    case LANTERN_LOG_LEVEL_ERROR:
    default:
        lantern_log_error("libp2p", NULL, "%s", msg);
        break;
    }
}

static void lantern_libp2p_configure_logging(void)
{
    static bool writer_installed = false;
    if (!writer_installed) {
        libp2p_log_set_writer(lantern_libp2p_log_writer, NULL);
        writer_installed = true;
    }

    libp2p_log_level_t target = LIBP2P_LOG_ERROR;
    switch (lantern_log_get_level()) {
    case LANTERN_LOG_LEVEL_TRACE:
        target = LIBP2P_LOG_TRACE;
        break;
    case LANTERN_LOG_LEVEL_DEBUG:
        target = LIBP2P_LOG_DEBUG;
        break;
    case LANTERN_LOG_LEVEL_INFO:
        target = LIBP2P_LOG_INFO;
        break;
    case LANTERN_LOG_LEVEL_WARN:
        target = LIBP2P_LOG_WARN;
        break;
    case LANTERN_LOG_LEVEL_ERROR:
    default:
        target = LIBP2P_LOG_ERROR;
        break;
    }
    libp2p_log_set_level(target);
}

int lantern_libp2p_encode_secp256k1_private_key_proto(
    const uint8_t *secret,
    size_t secret_len,
    uint8_t **out,
    size_t *out_len) {
    if (!secret || secret_len != 32 || !out || !out_len) {
        return -1;
    }
    uint8_t type_buf[10];
    uint8_t len_buf[10];
    size_t type_written = 0;
    size_t len_written = 0;
    if (unsigned_varint_encode(LANTERN_LIBP2P_KEY_TYPE_SECP256K1, type_buf, sizeof(type_buf), &type_written) != UNSIGNED_VARINT_OK) {
        return -1;
    }
    if (unsigned_varint_encode((uint64_t)secret_len, len_buf, sizeof(len_buf), &len_written) != UNSIGNED_VARINT_OK) {
        return -1;
    }
    size_t total = 1 + type_written + 1 + len_written + secret_len;
    uint8_t *buffer = (uint8_t *)malloc(total);
    if (!buffer) {
        return -1;
    }
    size_t offset = 0;
    buffer[offset++] = 0x08;
    memcpy(buffer + offset, type_buf, type_written);
    offset += type_written;
    buffer[offset++] = 0x12;
    memcpy(buffer + offset, len_buf, len_written);
    offset += len_written;
    memcpy(buffer + offset, secret, secret_len);
    *out = buffer;
    *out_len = total;
    return 0;
}

static int multiaddr_has_protocol(const multiaddr_t *ma, uint64_t code) {
    if (!ma) {
        return 0;
    }
    size_t protocols = multiaddr_nprotocols(ma);
    for (size_t idx = 0; idx < protocols; idx++) {
        uint64_t current = 0;
        if (multiaddr_get_protocol_code(ma, idx, &current) == 0 && current == code) {
            return 1;
        }
    }
    return 0;
}

static int multiaddr_is_quic(const multiaddr_t *ma) {
    if (!ma) {
        return 0;
    }
    return multiaddr_has_protocol(ma, MULTICODEC_QUIC_V1) || multiaddr_has_protocol(ma, MULTICODEC_QUIC);
}

void lantern_libp2p_host_init(struct lantern_libp2p_host *state) {
    if (!state) {
        return;
    }
    state->host = NULL;
    state->started = 0;
}

void lantern_libp2p_host_stop(struct lantern_libp2p_host *state) {
    if (!state || !state->host || !state->started) {
        return;
    }
    if (libp2p_host_stop(state->host) != 0) {
        lantern_log_warn(
            "network",
            &(const struct lantern_log_metadata){.peer = "local"},
            "libp2p_host_stop failed");
    }
    state->started = 0;
}

void lantern_libp2p_host_reset(struct lantern_libp2p_host *state) {
    if (!state) {
        return;
    }
    if (state->host) {
        lantern_libp2p_host_stop(state);
        libp2p_host_free(state->host);
        state->host = NULL;
    }
    state->started = 0;
}

int lantern_libp2p_host_start(struct lantern_libp2p_host *state, const struct lantern_libp2p_config *config) {
    if (!state || !config || !config->listen_multiaddr || !config->secp256k1_secret) {
        return -1;
    }
    if (config->secret_len != 32) {
        lantern_log_error(
            "network",
            &(const struct lantern_log_metadata){.peer = config->listen_multiaddr},
            "libp2p expects 32-byte secp256k1 secrets");
        return -1;
    }

    lantern_libp2p_host_reset(state);

    lantern_libp2p_configure_logging();

    libp2p_host_builder_t *builder = libp2p_host_builder_new();
    if (!builder) {
        return -1;
    }

    int rc = 0;
    int addr_err = 0;
    multiaddr_t *ma = multiaddr_new_from_str(config->listen_multiaddr, &addr_err);
    if (!ma || addr_err != 0) {
        lantern_log_error(
            "network",
            &(const struct lantern_log_metadata){.peer = config->listen_multiaddr},
            "invalid listen multiaddr '%s' (err=%d)",
            config->listen_multiaddr,
            addr_err);
        multiaddr_free(ma);
        libp2p_host_builder_free(builder);
        return -1;
    }
    if (!multiaddr_is_quic(ma)) {
        lantern_log_error(
            "network",
            &(const struct lantern_log_metadata){.peer = config->listen_multiaddr},
            "listen multiaddr '%s' must include /quic(_v1)",
            config->listen_multiaddr);
        multiaddr_free(ma);
        libp2p_host_builder_free(builder);
        return -1;
    }
    multiaddr_free(ma);

    int b_rc = libp2p_host_builder_listen_addr(builder, config->listen_multiaddr);
    if (b_rc != 0) {
        lantern_log_error(
            "network",
            &(const struct lantern_log_metadata){.peer = config->listen_multiaddr},
            "libp2p listen addr %s failed (%d)",
            config->listen_multiaddr,
            b_rc);
        rc = -1;
    }
    if (rc == 0) {
        b_rc = libp2p_host_builder_transport(builder, "quic");
        if (b_rc != 0) {
            lantern_log_error(
                "network",
                &(const struct lantern_log_metadata){.peer = config->listen_multiaddr},
                "libp2p transport 'quic' setup failed (%d)",
                b_rc);
            rc = -1;
        }
    }
    if (rc == 0) {
        b_rc = libp2p_host_builder_multistream(builder, 5000, true);
        if (b_rc != 0) {
            lantern_log_error(
                "network",
                &(const struct lantern_log_metadata){.peer = config->listen_multiaddr},
                "libp2p multistream setup failed (%d)",
                b_rc);
            rc = -1;
        }
    }
    if (rc == 0) {
        uint32_t flags = LIBP2P_HOST_F_AUTO_IDENTIFY_INBOUND;
        if (config->allow_outbound_identify) {
            flags |= LIBP2P_HOST_F_AUTO_IDENTIFY_OUTBOUND;
        }
        if (flags != 0u) {
            b_rc = libp2p_host_builder_flags(builder, flags);
            if (b_rc != 0) {
                lantern_log_warn(
                    "network",
                    &(const struct lantern_log_metadata){.peer = config->listen_multiaddr},
                    "libp2p host flags setup failed (%d)",
                    b_rc);
            }
        }
    }

    libp2p_host_t *host = NULL;
    int build_rc = 0;
    if (rc == 0) {
        build_rc = libp2p_host_builder_build(builder, &host);
        if (build_rc != 0 || !host) {
            lantern_log_error(
                "network",
                &(const struct lantern_log_metadata){.peer = config->listen_multiaddr},
                "libp2p host builder failed (%d)",
                build_rc);
            rc = -1;
        }
    }
    if (rc != 0) {
        rc = -1;
    }
    libp2p_host_builder_free(builder);
    builder = NULL;
    if (rc != 0) {
        return -1;
    }

    uint8_t *identity_pb = NULL;
    size_t identity_len = 0;
    if (lantern_libp2p_encode_secp256k1_private_key_proto(
            config->secp256k1_secret,
            config->secret_len,
            &identity_pb,
            &identity_len)
        != 0) {
        libp2p_host_free(host);
        return -1;
    }

    if (libp2p_host_set_private_key(host, identity_pb, identity_len) != 0) {
        free(identity_pb);
        lantern_log_error(
            "network",
            &(const struct lantern_log_metadata){.peer = config->listen_multiaddr},
            "libp2p failed to set private key");
        libp2p_host_free(host);
        return -1;
    }
    free(identity_pb);

    if (libp2p_host_start(host) != 0) {
        lantern_log_error(
            "network",
            &(const struct lantern_log_metadata){.peer = config->listen_multiaddr},
            "libp2p host start failed");
        libp2p_host_free(host);
        return -1;
    }

    lantern_log_info(
        "network",
        &(const struct lantern_log_metadata){.peer = config->listen_multiaddr},
        "libp2p host started");

    state->host = host;
    state->started = 1;
    return 0;
}

static int extract_ipv4_multiaddr(
    const struct lantern_enr_record *record,
    char *buffer,
    size_t buffer_len,
    uint16_t *port) {
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
    if (written < 0 || (size_t)written >= buffer_len) {
        return -1;
    }
    if (port) {
        *port = parsed_port;
    }
    return 0;
}

static int extract_ipv6_multiaddr(
    const struct lantern_enr_record *record,
    char *buffer,
    size_t buffer_len,
    uint16_t *port) {
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
    if (written < 0 || (size_t)written >= buffer_len) {
        return -1;
    }
    if (port) {
        *port = parsed_port;
    }
    return 0;
}

int lantern_libp2p_enr_to_multiaddr(
    const struct lantern_enr_record *record,
    char *buffer,
    size_t buffer_len,
    peer_id_t *peer_id) {
    if (!record || !buffer || !peer_id) {
        return -1;
    }
    const struct lantern_enr_key_value *pubkey = lantern_enr_record_find(record, "secp256k1");
    if (!pubkey || !pubkey->value || pubkey->value_len == 0) {
        return -1;
    }

    uint8_t *pubkey_pb = NULL;
    size_t pubkey_pb_len = 0;
    peer_id_error_t perr = peer_id_build_public_key_protobuf(
        LANTERN_LIBP2P_KEY_TYPE_SECP256K1,
        pubkey->value,
        pubkey->value_len,
        &pubkey_pb,
        &pubkey_pb_len);
    if (perr != PEER_ID_SUCCESS) {
        return -1;
    }
    perr = peer_id_create_from_public_key(pubkey_pb, pubkey_pb_len, peer_id);
    free(pubkey_pb);
    if (perr != PEER_ID_SUCCESS) {
        return -1;
    }

    char base_addr[128];
    if (extract_ipv4_multiaddr(record, base_addr, sizeof(base_addr), NULL) != 0) {
        if (extract_ipv6_multiaddr(record, base_addr, sizeof(base_addr), NULL) != 0) {
            peer_id_destroy(peer_id);
            return -1;
        }
    }

    char peer_text[128];
    int pid_written = peer_id_to_string(peer_id, PEER_ID_FMT_BASE58_LEGACY, peer_text, sizeof(peer_text));
    if (pid_written < 0) {
        peer_id_destroy(peer_id);
        return -1;
    }

    int written = snprintf(buffer, buffer_len, "%s/p2p/%s", base_addr, peer_text);
    if (written < 0 || (size_t)written >= buffer_len) {
        peer_id_destroy(peer_id);
        return -1;
    }
    return 0;
}

int lantern_libp2p_host_add_enr_peer(
    struct lantern_libp2p_host *state,
    const struct lantern_enr_record *record,
    int ttl_ms) {
    if (!state || !state->host || !record) {
        return -1;
    }
    peer_id_t peer_id = {0};
    char multiaddr[256];
    if (lantern_libp2p_enr_to_multiaddr(record, multiaddr, sizeof(multiaddr), &peer_id) != 0) {
        return -1;
    }

    int ttl = ttl_ms > 0 ? ttl_ms : LANTERN_LIBP2P_DEFAULT_PEER_TTL_MS;
    int rc = libp2p_host_add_peer_addr_str(state->host, &peer_id, multiaddr, ttl);
    peer_id_destroy(&peer_id);
    return rc;
}
