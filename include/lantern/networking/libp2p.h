#ifndef LANTERN_NETWORKING_LIBP2P_H
#define LANTERN_NETWORKING_LIBP2P_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

struct lantern_enr_record;
struct libp2p_host;
typedef struct peer_id peer_id_t;

#define LANTERN_LIBP2P_DEFAULT_PEER_TTL_MS (300000)

struct lantern_libp2p_config {
    const char *listen_multiaddr;
    const uint8_t *secp256k1_secret;
    size_t secret_len;
    int allow_outbound_identify;
};

struct lantern_libp2p_host {
    struct libp2p_host *host;
    int started;
};

void lantern_libp2p_host_init(struct lantern_libp2p_host *state);
void lantern_libp2p_host_reset(struct lantern_libp2p_host *state);
int lantern_libp2p_host_start(struct lantern_libp2p_host *state, const struct lantern_libp2p_config *config);
void lantern_libp2p_host_stop(struct lantern_libp2p_host *state);
int lantern_libp2p_host_add_enr_peer(
    struct lantern_libp2p_host *state,
    const struct lantern_enr_record *record,
    int ttl_ms);
int lantern_libp2p_enr_to_multiaddr(
    const struct lantern_enr_record *record,
    char *buffer,
    size_t buffer_len,
    peer_id_t **peer_id);
int lantern_libp2p_encode_secp256k1_private_key_proto(
    const uint8_t *secret,
    size_t secret_len,
    uint8_t **out,
    size_t *out_len);

#ifdef __cplusplus
}
#endif

#endif /* LANTERN_NETWORKING_LIBP2P_H */
