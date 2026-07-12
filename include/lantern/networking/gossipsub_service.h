#ifndef LANTERN_NETWORKING_GOSSIPSUB_SERVICE_H
#define LANTERN_NETWORKING_GOSSIPSUB_SERVICE_H

#include <stddef.h>
#include <stdint.h>

#include "lantern/consensus/containers.h"
#include "lantern/networking/libp2p.h"

typedef struct libp2p_gossipsub libp2p_gossipsub_t;
struct lantern_gossipsub_validation_pool;
struct lantern_gossipsub_service;

#ifdef __cplusplus
extern "C" {
#endif

struct lantern_gossipsub_config {
    struct lantern_libp2p_host *network;
    const char *devnet;
    const char *data_dir;
    const char *topic_network_name;
    uint8_t fork_digest[4];
    size_t attestation_subnet_id;
    int subscribe_attestation_subnet;
};

typedef int (*lantern_gossipsub_block_handler)(
    const LanternSignedBlock *block,
    const struct lantern_peer_id *from,
    const uint8_t *raw_block_ssz,
    size_t raw_block_ssz_len,
    void *user_data);
typedef int (*lantern_gossipsub_vote_handler)(
    const LanternSignedVote *vote,
    const struct lantern_peer_id *from,
    const uint8_t *raw_vote_payload,
    size_t raw_vote_payload_len,
    void *user_data);
typedef int (*lantern_gossipsub_aggregated_attestation_handler)(
    const LanternSignedAggregatedAttestation *attestation,
    const struct lantern_peer_id *from,
    const uint8_t *raw_attestation_payload,
    size_t raw_attestation_payload_len,
    void *user_data);

#define LANTERN_GOSSIPSUB_MAX_TRACKED_PEERS      128u
#define LANTERN_GOSSIPSUB_MAX_CONNS_PER_PEER     8u
#define LANTERN_GOSSIPSUB_RETRY_INITIAL_US       250000ull
#define LANTERN_GOSSIPSUB_RETRY_MAX_US           5000000ull

struct lantern_gossipsub_peer_connection_state {
    struct lantern_peer_id peer;
    libp2p_host_conn_t *conns[LANTERN_GOSSIPSUB_MAX_CONNS_PER_PEER];
    uint8_t conn_inbound[LANTERN_GOSSIPSUB_MAX_CONNS_PER_PEER];
    uint8_t conn_closing[LANTERN_GOSSIPSUB_MAX_CONNS_PER_PEER];
    size_t conn_count;
    libp2p_host_conn_t *primary_conn;
    uint8_t primary_inbound;
    libp2p_host_conn_t *writer_conn;
    libp2p_host_stream_t *writer_stream;
    libp2p_host_conn_t *opening_conn;
    libp2p_host_time_us_t next_retry_us;
    uint64_t retry_backoff_us;
    uint8_t used;
};

struct lantern_gossipsub_protocol_adapter {
    struct lantern_gossipsub_service *service;
    libp2p_host_protocol_open_fn_t on_open;
    libp2p_host_protocol_event_fn_t on_event;
    void *user_data;
};

struct lantern_gossipsub_service {
    struct lantern_libp2p_host *network;
    libp2p_gossipsub_t *gossipsub;
    void *gossipsub_storage;
    size_t gossipsub_storage_len;
    libp2p_host_protocol_t gossipsub_protocols[LIBP2P_GOSSIPSUB_PROTOCOL_COUNT];
    struct lantern_gossipsub_protocol_adapter gossipsub_protocol_adapters[LIBP2P_GOSSIPSUB_PROTOCOL_COUNT];
    size_t gossipsub_protocol_count;
    char block_topic[128];
    char vote_topic[128];
    char vote_subnet_topic[128];
    char aggregated_attestation_topic[128];
    const char *data_dir;
    const char *devnet;
    char topic_network_name[64];
    uint8_t fork_digest[4];
    size_t attestation_subnet_id;
    int subscribe_attestation_subnet;
    int (*publish_hook)(const char *topic, const uint8_t *payload, size_t payload_len, void *user_data);
    void *publish_hook_user_data;
    int loopback_only;
    lantern_gossipsub_block_handler block_handler;
    void *block_handler_user_data;
    lantern_gossipsub_vote_handler vote_handler;
    void *vote_handler_user_data;
    lantern_gossipsub_aggregated_attestation_handler aggregated_attestation_handler;
    void *aggregated_attestation_handler_user_data;
    char (*extra_vote_subnet_topics)[128];
    size_t extra_vote_subnet_topic_count;
    struct lantern_gossipsub_validation_pool *validation_pool;
    struct lantern_gossipsub_peer_connection_state peer_connections[LANTERN_GOSSIPSUB_MAX_TRACKED_PEERS];
};

void lantern_gossipsub_service_init(struct lantern_gossipsub_service *service);
void lantern_gossipsub_service_stop(struct lantern_gossipsub_service *service);
void lantern_gossipsub_service_reset(struct lantern_gossipsub_service *service);
int lantern_gossipsub_service_start(
    struct lantern_gossipsub_service *service,
    const struct lantern_gossipsub_config *config);
int lantern_gossipsub_service_publish_block(
    struct lantern_gossipsub_service *service,
    const LanternSignedBlock *block);
int lantern_gossipsub_service_publish_vote_subnet(
    struct lantern_gossipsub_service *service,
    const LanternSignedVote *vote,
    size_t subnet_id);
int lantern_gossipsub_service_publish_aggregated_attestation(
    struct lantern_gossipsub_service *service,
    const LanternSignedAggregatedAttestation *attestation);
int lantern_gossipsub_service_subscribe_attestation_subnet(
    struct lantern_gossipsub_service *service,
    size_t subnet_id);
/** Sum of peer memberships across all locally joined topic meshes. */
size_t lantern_gossipsub_service_mesh_peer_count(const struct lantern_gossipsub_service *service);
void lantern_gossipsub_service_set_publish_hook(
    struct lantern_gossipsub_service *service,
    int (*hook)(const char *topic, const uint8_t *payload, size_t payload_len, void *user_data),
    void *user_data);
void lantern_gossipsub_service_set_loopback_only(
    struct lantern_gossipsub_service *service,
    int loopback_only);
void lantern_gossipsub_service_set_block_handler(
    struct lantern_gossipsub_service *service,
    lantern_gossipsub_block_handler handler,
    void *user_data);
void lantern_gossipsub_service_set_vote_handler(
    struct lantern_gossipsub_service *service,
    lantern_gossipsub_vote_handler handler,
    void *user_data);
void lantern_gossipsub_service_set_aggregated_attestation_handler(
    struct lantern_gossipsub_service *service,
    lantern_gossipsub_aggregated_attestation_handler handler,
    void *user_data);

#ifdef __cplusplus
}
#endif

#endif /* LANTERN_NETWORKING_GOSSIPSUB_SERVICE_H */
