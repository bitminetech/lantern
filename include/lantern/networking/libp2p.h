#ifndef LANTERN_NETWORKING_LIBP2P_H
#define LANTERN_NETWORKING_LIBP2P_H

#include <pthread.h>
#include <stddef.h>
#include <stdint.h>

#include "libp2p/libp2p_host.h"
#include "libp2p/libp2p_host_secp256k1_identity.h"
#include "peer_id/peer_id.h"
#include "protocol/gossipsub/gossipsub.h"
#include "protocol/identify/identify.h"
#include "protocol/ping/ping.h"
#include "transport/quic/quic_identity.h"
#include "transport/quic/quic_service.h"

#ifdef __cplusplus
extern "C" {
#endif

struct lantern_enr_record;
struct lantern_libp2p_host;

#define LANTERN_LIBP2P_MAX_PROTOCOLS 24u
#define LANTERN_LIBP2P_MAX_EVENT_HANDLERS 8u
#define LANTERN_LIBP2P_MAX_DRIVE_HANDLERS 8u
#define LANTERN_LIBP2P_MULTIADDR_MAX_BYTES 256u
#define LANTERN_LIBP2P_PEER_TEXT_MAX_BYTES 128u

struct lantern_peer_id {
    uint8_t bytes[LIBP2P_PEER_ID_MAX_BYTES];
    size_t len;
};

typedef void (*lantern_libp2p_host_event_handler)(
    struct lantern_libp2p_host *network,
    const libp2p_host_event_t *event,
    void *user_data);

typedef void (*lantern_libp2p_drive_handler)(
    struct lantern_libp2p_host *network,
    libp2p_host_time_us_t now_us,
    void *user_data);

struct lantern_libp2p_config {
    const char *listen_multiaddr;
    const uint8_t *secp256k1_secret;
    size_t secret_len;
    int allow_outbound_identify;
};

struct lantern_libp2p_host {
    libp2p_host_t *host;
    void *host_storage;
    size_t host_storage_len;
    uint8_t listen_multiaddr[LANTERN_LIBP2P_MULTIADDR_MAX_BYTES];
    size_t listen_multiaddr_len;
    uint8_t local_peer_id[LIBP2P_PEER_ID_MAX_BYTES];
    size_t local_peer_id_len;
    libp2p_host_secp256k1_identity_t host_identity_storage;
    libp2p_host_identity_t host_identity;
    uint8_t certificate_der[LIBP2P_QUIC_CERTIFICATE_DER_MAX_BYTES];
    uint8_t certificate_key_der[LIBP2P_QUIC_CERTIFICATE_KEY_DER_MAX_BYTES];
    libp2p_quic_local_identity_t quic_identity;
    libp2p_quic_service_config_t quic_config;
    libp2p_quic_allocator_t allocator;
    libp2p_ping_t ping;
    libp2p_identify_t identify;
    libp2p_host_protocol_t default_protocols[3];
    size_t default_protocol_count;
    lantern_libp2p_host_event_handler event_handlers[LANTERN_LIBP2P_MAX_EVENT_HANDLERS];
    void *event_handler_user_data[LANTERN_LIBP2P_MAX_EVENT_HANDLERS];
    size_t event_handler_count;
    lantern_libp2p_drive_handler drive_handlers[LANTERN_LIBP2P_MAX_DRIVE_HANDLERS];
    void *drive_handler_user_data[LANTERN_LIBP2P_MAX_DRIVE_HANDLERS];
    size_t drive_handler_count;
    pthread_t drive_thread;
    int drive_thread_started;
    int stop_flag;
    int started;
};

void lantern_libp2p_host_init(struct lantern_libp2p_host *state);
void lantern_libp2p_host_reset(struct lantern_libp2p_host *state);
int lantern_libp2p_host_prepare(struct lantern_libp2p_host *state, const struct lantern_libp2p_config *config);
int lantern_libp2p_host_launch(struct lantern_libp2p_host *state);
void lantern_libp2p_host_stop(struct lantern_libp2p_host *state);
int lantern_libp2p_host_register_protocol(
    struct lantern_libp2p_host *state,
    const libp2p_host_protocol_t *protocol);
int lantern_libp2p_host_register_event_handler(
    struct lantern_libp2p_host *state,
    lantern_libp2p_host_event_handler handler,
    void *user_data);
int lantern_libp2p_host_register_drive_handler(
    struct lantern_libp2p_host *state,
    lantern_libp2p_drive_handler handler,
    void *user_data);
int lantern_libp2p_host_dial_multiaddr(
    struct lantern_libp2p_host *state,
    const char *multiaddr_text);
int lantern_libp2p_enr_to_multiaddr(
    const struct lantern_enr_record *record,
    char *buffer,
    size_t buffer_len,
    struct lantern_peer_id *peer_id);
int lantern_peer_id_from_text(const char *text, struct lantern_peer_id *out_peer);
/* Returns the number of characters written on success, or -1 on failure. */
int lantern_peer_id_to_text(const struct lantern_peer_id *peer, char *buffer, size_t buffer_len);
int lantern_peer_id_equal(const struct lantern_peer_id *left, const struct lantern_peer_id *right);
libp2p_host_time_us_t lantern_libp2p_now_us(void);
libp2p_quic_err_t lantern_libp2p_quic_random(uint8_t *out, size_t out_len, void *user_data);
libp2p_gossipsub_err_t lantern_libp2p_gossipsub_random(uint8_t *out, size_t out_len, void *user_data);

#ifdef __cplusplus
}
#endif

#endif /* LANTERN_NETWORKING_LIBP2P_H */
