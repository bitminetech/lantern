#ifndef LANTERN_NETWORKING_GOSSIPSUB_SERVICE_H
#define LANTERN_NETWORKING_GOSSIPSUB_SERVICE_H

#include <stddef.h>
#include <stdint.h>

#include "lantern/consensus/containers.h"
#include "peer_id/peer_id.h"

struct libp2p_host;
typedef struct libp2p_gossipsub libp2p_gossipsub_t;
typedef struct libp2p_gossipsub_validator_handle libp2p_gossipsub_validator_handle_t;

#ifdef __cplusplus
extern "C" {
#endif

struct lantern_gossipsub_config {
    struct libp2p_host *host;
    const char *devnet;
};

typedef int (*lantern_gossipsub_block_handler)(
    const LanternSignedBlock *block,
    const peer_id_t *from,
    void *user_data);
typedef int (*lantern_gossipsub_vote_handler)(
    const LanternSignedVote *vote,
    const peer_id_t *from,
    void *user_data);

struct lantern_gossipsub_service {
    libp2p_gossipsub_t *gossipsub;
    char block_topic[128];
    char vote_topic[128];
    int (*publish_hook)(const char *topic, const uint8_t *payload, size_t payload_len, void *user_data);
    void *publish_hook_user_data;
    int loopback_only;
    lantern_gossipsub_block_handler block_handler;
    void *block_handler_user_data;
    lantern_gossipsub_vote_handler vote_handler;
    void *vote_handler_user_data;
    libp2p_gossipsub_validator_handle_t *block_validator_handle;
    libp2p_gossipsub_validator_handle_t *vote_validator_handle;
};

void lantern_gossipsub_service_init(struct lantern_gossipsub_service *service);
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

#ifdef __cplusplus
}
#endif

#endif /* LANTERN_NETWORKING_GOSSIPSUB_SERVICE_H */
