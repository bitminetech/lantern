#include "lantern/networking/gossip.h"

#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "WjCryptLib_Sha256.h"
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

int lantern_gossip_topic_format(
    enum lantern_gossip_topic_kind kind,
    const char *devnet,
    char *buffer,
    size_t buffer_len) {
    if (!devnet || !buffer || buffer_len == 0) {
        return -1;
    }
    if (kind == LANTERN_GOSSIP_TOPIC_VOTE_SUBNET) {
        return -1;
    }
    const char *message = lantern_gossip_topic_name(kind);
    if (!message || devnet[0] == '\0') {
        return -1;
    }
    int written = snprintf(buffer, buffer_len, "/leanconsensus/%s/%s/ssz_snappy", devnet, message);
    if (written < 0 || (size_t)written >= buffer_len) {
        return -1;
    }
    return 0;
}

int lantern_gossip_topic_format_subnet(
    enum lantern_gossip_topic_kind kind,
    const char *devnet,
    size_t subnet_id,
    char *buffer,
    size_t buffer_len) {
    if (!devnet || !buffer || buffer_len == 0) {
        return -1;
    }
    if (kind != LANTERN_GOSSIP_TOPIC_VOTE_SUBNET || devnet[0] == '\0') {
        return -1;
    }
    int written = snprintf(
        buffer,
        buffer_len,
        "/leanconsensus/%s/attestation_%zu/ssz_snappy",
        devnet,
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

    Sha256Context ctx;
    Sha256Initialise(&ctx);
    Sha256Update(&ctx, domain, LANTERN_GOSSIP_DOMAIN_SIZE);

    uint8_t topic_len_encoded[8];
    write_u64_le((uint64_t)topic_len, topic_len_encoded);
    Sha256Update(&ctx, topic_len_encoded, sizeof(topic_len_encoded));
    Sha256Update(&ctx, topic, topic_len);
    if (data_len > 0 && data_for_hash) {
        Sha256Update(&ctx, data_for_hash, data_len);
    }
    SHA256_HASH digest;
    Sha256Finalise(&ctx, &digest);
    memcpy(message_id->bytes, digest.bytes, LANTERN_GOSSIP_MESSAGE_ID_SIZE);
    return 0;
}
