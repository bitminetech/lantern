#ifndef LANTERN_NETWORKING_GOSSIP_H
#define LANTERN_NETWORKING_GOSSIP_H

#include <stddef.h>
#include <stdint.h>

#define LANTERN_GOSSIP_MESSAGE_ID_SIZE 20u
#define LANTERN_GOSSIP_DOMAIN_SIZE 4u
#define LANTERN_GOSSIP_FORK_DIGEST_SIZE 4u
#define LANTERN_GOSSIP_FORK_DIGEST_HEX_LEN 8u

extern const uint8_t LANTERN_GOSSIP_DOMAIN_INVALID[LANTERN_GOSSIP_DOMAIN_SIZE];
extern const uint8_t LANTERN_GOSSIP_DOMAIN_VALID[LANTERN_GOSSIP_DOMAIN_SIZE];

enum lantern_gossip_topic_kind {
    LANTERN_GOSSIP_TOPIC_BLOCK = 0,
    LANTERN_GOSSIP_TOPIC_VOTE = 1,
    LANTERN_GOSSIP_TOPIC_VOTE_SUBNET = 2,
    LANTERN_GOSSIP_TOPIC_AGGREGATED_ATTESTATION = 3,
};

typedef struct {
    uint8_t bytes[LANTERN_GOSSIP_MESSAGE_ID_SIZE];
} LanternGossipMessageId;

int lantern_gossip_fork_digest_to_hex(
    const uint8_t fork_digest[LANTERN_GOSSIP_FORK_DIGEST_SIZE],
    char buffer[LANTERN_GOSSIP_FORK_DIGEST_HEX_LEN + 1u]);

int lantern_gossip_topic_format(
    enum lantern_gossip_topic_kind kind,
    const char *network_name,
    char *buffer,
    size_t buffer_len);

int lantern_gossip_topic_format_subnet(
    enum lantern_gossip_topic_kind kind,
    const char *network_name,
    size_t subnet_id,
    char *buffer,
    size_t buffer_len);

int lantern_gossip_compute_message_id(
    LanternGossipMessageId *message_id,
    const uint8_t *topic,
    size_t topic_len,
    const uint8_t *payload,
    size_t payload_len,
    uint8_t *snappy_scratch,
    size_t snappy_scratch_len,
    size_t *required_scratch);

#endif /* LANTERN_NETWORKING_GOSSIP_H */
