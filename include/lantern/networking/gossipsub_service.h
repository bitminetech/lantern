#ifndef LANTERN_NETWORKING_GOSSIPSUB_SERVICE_H
#define LANTERN_NETWORKING_GOSSIPSUB_SERVICE_H

#include <stddef.h>
#include <stdint.h>

#include "lantern/consensus/containers.h"
#include "peer_id/peer_id.h"

struct libp2p_host;
typedef struct libp2p_gossipsub libp2p_gossipsub_t;
typedef struct libp2p_gossipsub_validator_handle libp2p_gossipsub_validator_handle_t;
struct lantern_gossipsub_validation_pool;

#ifdef __cplusplus
extern "C" {
#endif

struct lantern_gossipsub_config {
    struct libp2p_host *host;
    const char *devnet;
    const char *data_dir;
    size_t attestation_subnet_id;
    int subscribe_attestation_subnet;
};

typedef int (*lantern_gossipsub_block_handler)(
    const LanternSignedBlock *block,
    const peer_id_t *from,
    const uint8_t *raw_block_ssz,
    size_t raw_block_ssz_len,
    void *user_data);
typedef int (*lantern_gossipsub_vote_handler)(
    const LanternSignedVote *vote,
    const peer_id_t *from,
    void *user_data);
typedef int (*lantern_gossipsub_aggregated_attestation_handler)(
    const LanternSignedAggregatedAttestation *attestation,
    const peer_id_t *from,
    void *user_data);

struct lantern_gossipsub_service {
    libp2p_gossipsub_t *gossipsub;
    char block_topic[128];
    char vote_topic[128];
    char vote_subnet_topic[128];
    char aggregated_attestation_topic[128];
    const char *data_dir;
    const char *devnet;
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
    libp2p_gossipsub_validator_handle_t *block_validator_handle;
    libp2p_gossipsub_validator_handle_t *vote_validator_handle;
    libp2p_gossipsub_validator_handle_t *vote_subnet_validator_handle;
    libp2p_gossipsub_validator_handle_t *aggregated_attestation_validator_handle;
    char (*extra_vote_subnet_topics)[128];
    libp2p_gossipsub_validator_handle_t **extra_vote_subnet_validator_handles;
    size_t extra_vote_subnet_topic_count;
    struct lantern_gossipsub_validation_pool *validation_pool;
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
int lantern_gossipsub_service_publish_vote(
    struct lantern_gossipsub_service *service,
    const LanternSignedVote *vote);
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
