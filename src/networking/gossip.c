#include "lantern/networking/gossip.h"

#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include <openssl/sha.h>

#include "lantern/encoding/snappy.h"

const uint8_t LANTERN_GOSSIP_DOMAIN_INVALID[LANTERN_GOSSIP_DOMAIN_SIZE] = {0x00, 0x00, 0x00, 0x00};
const uint8_t LANTERN_GOSSIP_DOMAIN_VALID[LANTERN_GOSSIP_DOMAIN_SIZE] = {0x01, 0x00, 0x00, 0x00};

static const char *lantern_gossip_topic_name(enum lantern_gossip_topic_kind kind) {
    switch (kind) {
        case LANTERN_GOSSIP_TOPIC_BLOCK:
            return "block";
        case LANTERN_GOSSIP_TOPIC_VOTE:
            return "attestation";
        case LANTERN_GOSSIP_TOPIC_AGGREGATED_ATTESTATION:
            return "aggregation";
        default:
            return NULL;
    }
}

int lantern_gossip_fork_digest_to_hex(
    const uint8_t fork_digest[LANTERN_GOSSIP_FORK_DIGEST_SIZE],
    char buffer[LANTERN_GOSSIP_FORK_DIGEST_HEX_LEN + 1u])
{
    if (!fork_digest || !buffer)
    {
        return -1;
    }

    int written = snprintf(
        buffer,
        LANTERN_GOSSIP_FORK_DIGEST_HEX_LEN + 1u,
        "%02x%02x%02x%02x",
        fork_digest[0],
        fork_digest[1],
        fork_digest[2],
        fork_digest[3]);
    return written == (int)LANTERN_GOSSIP_FORK_DIGEST_HEX_LEN ? 0 : -1;
}

int lantern_gossip_topic_format(
    enum lantern_gossip_topic_kind kind,
    const char *network_name,
    char *buffer,
    size_t buffer_len) {
    if (!network_name || !buffer || buffer_len == 0) {
        return -1;
    }
    if (kind == LANTERN_GOSSIP_TOPIC_VOTE_SUBNET) {
        return -1;
    }
    const char *message = lantern_gossip_topic_name(kind);
    if (!message || network_name[0] == '\0') {
        return -1;
    }
    int written = snprintf(buffer, buffer_len, "/leanconsensus/%s/%s/ssz_snappy", network_name, message);
    if (written < 0 || (size_t)written >= buffer_len) {
        return -1;
    }
    return 0;
}

int lantern_gossip_topic_format_subnet(
    enum lantern_gossip_topic_kind kind,
    const char *network_name,
    size_t subnet_id,
    char *buffer,
    size_t buffer_len) {
    if (!network_name || !buffer || buffer_len == 0) {
        return -1;
    }
    if (kind != LANTERN_GOSSIP_TOPIC_VOTE_SUBNET || network_name[0] == '\0') {
        return -1;
    }
    int written = snprintf(
        buffer,
        buffer_len,
        "/leanconsensus/%s/attestation_%zu/ssz_snappy",
        network_name,
        subnet_id);
    if (written < 0 || (size_t)written >= buffer_len) {
        return -1;
    }
    return 0;
}

static void write_u64_le(uint64_t value, uint8_t out[8]) {
    for (size_t i = 0; i < 8; ++i) {
        out[i] = (uint8_t)((value >> (8u * i)) & 0xFFu);
    }
}

int lantern_gossip_compute_message_id(
    LanternGossipMessageId *message_id,
    const uint8_t *topic,
    size_t topic_len,
    const uint8_t *payload,
    size_t payload_len,
    uint8_t *snappy_scratch,
    size_t snappy_scratch_len,
    size_t *required_scratch) {
    if (!message_id || (!topic && topic_len > 0u) || (!payload && payload_len > 0u)) {
        return -1;
    }
    if (required_scratch) {
        *required_scratch = 0;
    }

    const uint8_t *domain = LANTERN_GOSSIP_DOMAIN_INVALID;
    const uint8_t *data_for_hash = payload;
    size_t data_len = payload_len;

    if (snappy_scratch && payload_len > 0) {
        size_t expected_len = 0;
        int len_rc = lantern_snappy_uncompressed_length_raw(payload, payload_len, &expected_len);
        if (len_rc == LANTERN_SNAPPY_OK) {
            if (snappy_scratch_len >= expected_len) {
                size_t written = expected_len;
                int dec_rc =
                    lantern_snappy_decompress_raw(payload, payload_len, snappy_scratch, snappy_scratch_len, &written);
                if (dec_rc == LANTERN_SNAPPY_OK) {
                    domain = LANTERN_GOSSIP_DOMAIN_VALID;
                    data_for_hash = snappy_scratch;
                    data_len = written;
                }
            } else if (required_scratch) {
                *required_scratch = expected_len;
            }
        }
    }

    SHA256_CTX ctx;
    if (SHA256_Init(&ctx) != 1) {
        return -1;
    }
    if (SHA256_Update(&ctx, domain, LANTERN_GOSSIP_DOMAIN_SIZE) != 1) {
        return -1;
    }

    uint8_t topic_len_encoded[8];
    write_u64_le((uint64_t)topic_len, topic_len_encoded);
    if (SHA256_Update(&ctx, topic_len_encoded, sizeof(topic_len_encoded)) != 1) {
        return -1;
    }
    if (topic_len > 0 && SHA256_Update(&ctx, topic, topic_len) != 1) {
        return -1;
    }
    if (data_len > 0 && data_for_hash && SHA256_Update(&ctx, data_for_hash, data_len) != 1) {
        return -1;
    }
    uint8_t digest[SHA256_DIGEST_LENGTH];
    if (SHA256_Final(digest, &ctx) != 1) {
        return -1;
    }
    memcpy(message_id->bytes, digest, LANTERN_GOSSIP_MESSAGE_ID_SIZE);
    return 0;
}
