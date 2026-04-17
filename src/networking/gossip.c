#include "lantern/networking/gossip.h"

#include <stdint.h>
#include <stdlib.h>
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

static int lantern_hex_nibble(char ch)
{
    if (ch >= '0' && ch <= '9')
    {
        return ch - '0';
    }
    if (ch >= 'a' && ch <= 'f')
    {
        return 10 + (ch - 'a');
    }
    return -1;
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

int lantern_gossip_fork_digest_from_hex(
    const char *text,
    uint8_t out_fork_digest[LANTERN_GOSSIP_FORK_DIGEST_SIZE])
{
    if (!text || !out_fork_digest)
    {
        return -1;
    }
    if (strncmp(text, "0x", 2) == 0 || strncmp(text, "0X", 2) == 0)
    {
        return -1;
    }
    if (strlen(text) != LANTERN_GOSSIP_FORK_DIGEST_HEX_LEN)
    {
        return -1;
    }

    for (size_t i = 0; i < LANTERN_GOSSIP_FORK_DIGEST_SIZE; ++i)
    {
        int hi = lantern_hex_nibble(text[i * 2u]);
        int lo = lantern_hex_nibble(text[(i * 2u) + 1u]);
        if (hi < 0 || lo < 0)
        {
            return -1;
        }
        out_fork_digest[i] = (uint8_t)((hi << 4u) | lo);
    }
    return 0;
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

int lantern_gossip_topic_parse(
    const char *topic,
    struct lantern_gossip_parsed_topic *out_topic)
{
    if (!topic || !out_topic)
    {
        return -1;
    }

    memset(out_topic, 0, sizeof(*out_topic));
    out_topic->kind = (enum lantern_gossip_topic_kind)-1;

    if (strncmp(topic, "/leanconsensus/", 15) != 0)
    {
        return -1;
    }

    const char *cursor = topic + 15;
    const char *digest_end = strchr(cursor, '/');
    if (!digest_end)
    {
        return -1;
    }
    size_t digest_len = (size_t)(digest_end - cursor);
    if (digest_len == 0u || digest_len >= sizeof(out_topic->network_name))
    {
        return -1;
    }
    for (size_t i = 0; i < digest_len; ++i)
    {
        unsigned char ch = (unsigned char)cursor[i];
        if (ch < 0x21u || ch > 0x7eu)
        {
            return -1;
        }
    }
    memcpy(out_topic->network_name, cursor, digest_len);
    out_topic->network_name[digest_len] = '\0';

    const char *topic_name = digest_end + 1;
    const char *topic_name_end = strchr(topic_name, '/');
    if (!topic_name_end)
    {
        return -1;
    }
    size_t topic_name_len = (size_t)(topic_name_end - topic_name);
    const char *encoding = topic_name_end + 1;
    if (strcmp(encoding, "ssz_snappy") != 0)
    {
        return -1;
    }

    if (topic_name_len == 5u && strncmp(topic_name, "block", 5u) == 0)
    {
        out_topic->kind = LANTERN_GOSSIP_TOPIC_BLOCK;
        return 0;
    }
    if (topic_name_len == 11u && strncmp(topic_name, "aggregation", 11u) == 0)
    {
        out_topic->kind = LANTERN_GOSSIP_TOPIC_AGGREGATED_ATTESTATION;
        return 0;
    }
    if (topic_name_len > 12u && strncmp(topic_name, "attestation_", 12u) == 0)
    {
        size_t subnet_len = topic_name_len - 12u;
        if (subnet_len == 0u || subnet_len >= 32u)
        {
            return -1;
        }
        char subnet_text[32];
        memcpy(subnet_text, topic_name + 12u, subnet_len);
        subnet_text[subnet_len] = '\0';
        char *end = NULL;
        unsigned long long subnet = strtoull(subnet_text, &end, 10);
        if (!end || *end != '\0')
        {
            return -1;
        }
        out_topic->kind = LANTERN_GOSSIP_TOPIC_VOTE_SUBNET;
        out_topic->subnet_id = (size_t)subnet;
        return 0;
    }

    return -1;
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
