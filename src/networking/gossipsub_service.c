#include "lantern/networking/gossipsub_service.h"

#include <limits.h>
#include <inttypes.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#include "lantern/consensus/ssz.h"
#include "lantern/encoding/snappy.h"
#include "lantern/networking/gossip.h"
#include "lantern/networking/gossip_payloads.h"
#include "lantern/storage/storage.h"
#include "lantern/support/log.h"
#include "lantern/support/strings.h"
#include "ssz_constants.h"

#include "libp2p/errors.h"
#include "libp2p/host.h"
#include "protocol/gossipsub/gossipsub.h"
#include "../../external/c-libp2p/src/protocol/gossipsub/proto/gen/gossipsub_rpc.pb.h"

#ifdef __cplusplus
extern "C" {
#endif
libp2p_err_t libp2p_gossipsub_rpc_decode_frame(
    const uint8_t *frame,
    size_t frame_len,
    libp2p_gossipsub_RPC **out_rpc);
#ifdef __cplusplus
}
#endif

#define LANTERN_GOSSIPSUB_TOPIC_CAP 128u
#define LANTERN_ARRAY_SIZE(arr) (sizeof(arr) / sizeof((arr)[0]))
#define LANTERN_GOSSIPSUB_PROTOCOL "/meshsub/1.0.0"
#define LANTERN_GOSSIPSUB_HEARTBEAT_INTERVAL_MS 700u
#define LANTERN_GOSSIPSUB_FANOUT_TTL_MS 60000u
#define LANTERN_GOSSIPSUB_MESH_D 8
#define LANTERN_GOSSIPSUB_MESH_D_LOW 6
#define LANTERN_GOSSIPSUB_MESH_D_HIGH 12
#define LANTERN_GOSSIPSUB_MESH_D_LAZY 6
#define LANTERN_GOSSIPSUB_MESSAGE_CACHE_LEN 6u
#define LANTERN_GOSSIPSUB_MESSAGE_CACHE_GOSSIP 3u
#define LANTERN_LEANSPEC_SECONDS_PER_SLOT 4u
#define LANTERN_LEANSPEC_JUSTIFICATION_LOOKBACK 3u
#define LANTERN_LEANSPEC_SEEN_TTL_FACTOR 2u

/* Accept both raw 1.0.0 and libp2p's stacked identifiers (prefix/1.1.0) */
static const char *const k_leanspec_gossipsub_protocols[] = {
    "/meshsub/1.1.0",
    "/meshsub/1.0.0/1.1.0",
    "/meshsub/1.0.0",
};

static uint32_t lantern_leanspec_seen_ttl_ms(void) {
    const uint64_t ttl_seconds = (uint64_t)LANTERN_LEANSPEC_SECONDS_PER_SLOT
        * (uint64_t)LANTERN_LEANSPEC_JUSTIFICATION_LOOKBACK
        * (uint64_t)LANTERN_LEANSPEC_SEEN_TTL_FACTOR;
    const uint64_t ttl_ms = ttl_seconds * 1000u;
    return ttl_ms > UINT32_MAX ? UINT32_MAX : (uint32_t)ttl_ms;
}

static size_t bitlist_encoded_size_bits(size_t bit_length) {
    if (bit_length == 0) {
        return 1;
    }
    size_t byte_len = (bit_length + 7u) / 8u;
    if ((bit_length % 8u) == 0) {
        return byte_len + 1u;
    }
    return byte_len;
}

static size_t aggregated_attestation_encoded_size(const LanternAggregatedAttestation *attestation) {
    if (!attestation) {
        return 0;
    }
    if (attestation->aggregation_bits.bit_length > LANTERN_VALIDATOR_REGISTRY_LIMIT) {
        return 0;
    }
    size_t bits_size = bitlist_encoded_size_bits(attestation->aggregation_bits.bit_length);
    size_t fixed_section = SSZ_BYTE_SIZE_OF_UINT32 + LANTERN_ATTESTATION_DATA_SSZ_SIZE;
    if (fixed_section > SIZE_MAX - bits_size) {
        return 0;
    }
    return fixed_section + bits_size;
}

static size_t aggregated_attestations_encoded_size(const LanternAggregatedAttestations *attestations) {
    if (!attestations) {
        return 0;
    }
    if (attestations->length == 0) {
        return 0;
    }
    if (attestations->length > LANTERN_MAX_ATTESTATIONS || !attestations->data) {
        return 0;
    }
    size_t offset_table = attestations->length * SSZ_BYTE_SIZE_OF_UINT32;
    size_t total = offset_table;
    for (size_t i = 0; i < attestations->length; ++i) {
        size_t entry = aggregated_attestation_encoded_size(&attestations->data[i]);
        if (entry == 0 || entry > SIZE_MAX - total) {
            return 0;
        }
        total += entry;
    }
    return total;
}

static size_t aggregated_signature_proof_encoded_size(const LanternAggregatedSignatureProof *proof) {
    if (!proof) {
        return 0;
    }
    if (proof->participants.bit_length > LANTERN_VALIDATOR_REGISTRY_LIMIT) {
        return 0;
    }
    if (proof->proof_data.length > LANTERN_AGG_PROOF_MAX_BYTES) {
        return 0;
    }
    size_t participants_size = bitlist_encoded_size_bits(proof->participants.bit_length);
    size_t fixed_section = SSZ_BYTE_SIZE_OF_UINT32 * 2u;
    if (fixed_section > SIZE_MAX - participants_size) {
        return 0;
    }
    if (fixed_section + participants_size > SIZE_MAX - proof->proof_data.length) {
        return 0;
    }
    return fixed_section + participants_size + proof->proof_data.length;
}

static size_t attestation_signatures_encoded_size(const LanternAttestationSignatures *signatures) {
    if (!signatures) {
        return 0;
    }
    if (signatures->length == 0) {
        return 0;
    }
    if (signatures->length > LANTERN_MAX_BLOCK_SIGNATURES || !signatures->data) {
        return 0;
    }
    size_t offset_table = signatures->length * SSZ_BYTE_SIZE_OF_UINT32;
    size_t total = offset_table;
    for (size_t i = 0; i < signatures->length; ++i) {
        size_t entry = aggregated_signature_proof_encoded_size(&signatures->data[i]);
        if (entry == 0 || entry > SIZE_MAX - total) {
            return 0;
        }
        total += entry;
    }
    return total;
}

static void describe_peer_id(const peer_id_t *peer, char *buffer, size_t length) {
    if (!buffer || length == 0) {
        return;
    }
    if (!peer) {
        buffer[0] = '\0';
        return;
    }
    size_t written = 0;
    peer_id_error_t rc = peer_id_text_write(
        peer,
        PEER_ID_TEXT_LEGACY_BASE58,
        buffer,
        length,
        &written);
    if (rc != PEER_ID_OK) {
        buffer[0] = '\0';
    }
}

static void maybe_dump_invalid_gossip_payload(
    struct lantern_gossipsub_service *service,
    const char *payload_type,
    const uint8_t *payload,
    size_t payload_len,
    const struct lantern_log_metadata *meta) {
    if (!service || !service->data_dir || service->data_dir[0] == '\0' || !payload_type || !payload || payload_len == 0) {
        return;
    }

    if (lantern_storage_store_invalid_gossip_payload(
            service->data_dir,
            payload_type,
            payload,
            payload_len)
        != 0) {
        lantern_log_warn(
            "storage",
            meta,
            "failed to persist invalid gossip payload type=%s bytes=%zu",
            payload_type,
            payload_len);
    }
}

static void lantern_gossipsub_score_update(
    libp2p_gossipsub_t *gs,
    const libp2p_gossipsub_score_update_t *update,
    void *user_data) {
    (void)gs;
    struct lantern_gossipsub_service *service = (struct lantern_gossipsub_service *)user_data;
    if (!update || !service) {
        return;
    }

    char peer_text[128];
    describe_peer_id(update->peer, peer_text, sizeof(peer_text));
    const struct lantern_log_metadata meta = {.peer = peer_text[0] ? peer_text : NULL};
    lantern_log_debug(
        "gossip",
        &meta,
        "gossipsub score peer=%s score=%.3f override=%d",
        peer_text[0] ? peer_text : "unknown",
        update->score,
        update->score_override ? 1 : 0);
}

static bool gossipsub_message_has_forbidden_metadata(const libp2p_gossipsub_message_t *msg) {
    if (!msg || !msg->raw_message || msg->raw_message_len == 0) {
        return false;
    }
    libp2p_gossipsub_RPC *rpc = NULL;
    libp2p_err_t rc = libp2p_gossipsub_rpc_decode_frame(msg->raw_message, msg->raw_message_len, &rpc);
    if (rc != LIBP2P_ERR_OK || !rpc) {
        if (rpc) {
            libp2p_gossipsub_RPC_free(rpc);
        }
        return true;
    }
    bool forbidden = false;
    if (libp2p_gossipsub_RPC_has_publish(rpc)) {
        size_t publish_count = libp2p_gossipsub_RPC_count_publish(rpc);
        for (size_t i = 0; i < publish_count && !forbidden; ++i) {
            libp2p_gossipsub_Message *proto_msg = libp2p_gossipsub_RPC_get_at_publish(rpc, i);
            if (!proto_msg) {
                continue;
            }
            if (libp2p_gossipsub_Message_has_from(proto_msg)
                || libp2p_gossipsub_Message_has_seqno(proto_msg)
                || libp2p_gossipsub_Message_has_signature(proto_msg)) {
                forbidden = true;
            }
        }
    }
    libp2p_gossipsub_RPC_free(rpc);
    return forbidden;
}

static size_t signed_block_min_capacity(const LanternSignedBlock *block) {
    if (!block) {
        return 0;
    }
    size_t offsets = SSZ_BYTE_SIZE_OF_UINT32 * 2u;
    size_t block_fixed = (SSZ_BYTE_SIZE_OF_UINT64 * 2u)
        + (LANTERN_ROOT_SIZE * 2u)
        + SSZ_BYTE_SIZE_OF_UINT32;
    size_t block_offset = SSZ_BYTE_SIZE_OF_UINT32;
    size_t body_header = SSZ_BYTE_SIZE_OF_UINT32;
    size_t att_count = block->message.block.body.attestations.length;
    size_t att_bytes = aggregated_attestations_encoded_size(&block->message.block.body.attestations);
    if (att_count > 0 && att_bytes == 0) {
        return 0;
    }
    size_t proposer_bytes = LANTERN_VOTE_SSZ_SIZE;
    size_t sig_count = block->signatures.attestation_signatures.length;
    size_t sig_list_bytes = attestation_signatures_encoded_size(&block->signatures.attestation_signatures);
    if (sig_count > 0 && sig_list_bytes == 0) {
        return 0;
    }
    size_t signatures_bytes = (SSZ_BYTE_SIZE_OF_UINT32 * 2u) + LANTERN_SIGNATURE_SIZE + sig_list_bytes;
    size_t total = offsets + block_fixed;
    if (block_offset > SIZE_MAX - total) {
        return 0;
    }
    total += block_offset;
    if (total > SIZE_MAX - proposer_bytes) {
        return 0;
    }
    total += proposer_bytes;
    if (body_header > SIZE_MAX - total) {
        return 0;
    }
    total += body_header;
    if (att_bytes > SIZE_MAX - total) {
        return 0;
    }
    total += att_bytes;
    if (signatures_bytes > SIZE_MAX - total) {
        return 0;
    }
    total += signatures_bytes;
    return total;
}

static size_t signed_block_max_ssz_size(void) {
    size_t offsets = SSZ_BYTE_SIZE_OF_UINT32 * 2u;
    size_t block_fixed = (SSZ_BYTE_SIZE_OF_UINT64 * 2u)
        + (LANTERN_ROOT_SIZE * 2u)
        + SSZ_BYTE_SIZE_OF_UINT32;
    size_t block_offset = SSZ_BYTE_SIZE_OF_UINT32;
    size_t body_header = SSZ_BYTE_SIZE_OF_UINT32;
    size_t att_bits_max = bitlist_encoded_size_bits(LANTERN_VALIDATOR_REGISTRY_LIMIT);
    size_t att_entry_max = SSZ_BYTE_SIZE_OF_UINT32 + LANTERN_ATTESTATION_DATA_SSZ_SIZE + att_bits_max;
    size_t att_bytes = (size_t)LANTERN_MAX_ATTESTATIONS * (SSZ_BYTE_SIZE_OF_UINT32 + att_entry_max);
    size_t proposer_bytes = LANTERN_VOTE_SSZ_SIZE;
    size_t proof_bits_max = att_bits_max;
    size_t proof_entry_max = (SSZ_BYTE_SIZE_OF_UINT32 * 2u) + proof_bits_max + LANTERN_AGG_PROOF_MAX_BYTES;
    size_t signatures_bytes = (SSZ_BYTE_SIZE_OF_UINT32 * 2u) + LANTERN_SIGNATURE_SIZE
        + ((size_t)LANTERN_MAX_BLOCK_SIGNATURES * (SSZ_BYTE_SIZE_OF_UINT32 + proof_entry_max));
    size_t total = offsets + block_fixed;
    if (block_offset > SIZE_MAX - total) {
        return 0;
    }
    total += block_offset;
    if (total > SIZE_MAX - proposer_bytes) {
        return 0;
    }
    total += proposer_bytes;
    if (body_header > SIZE_MAX - total) {
        return 0;
    }
    total += body_header;
    if (att_bytes > SIZE_MAX - total) {
        return 0;
    }
    total += att_bytes;
    if (signatures_bytes > SIZE_MAX - total) {
        return 0;
    }
    total += signatures_bytes;
    return total;
}

static size_t signed_aggregated_attestation_max_ssz_size(void) {
    size_t att_bits_max = bitlist_encoded_size_bits(LANTERN_VALIDATOR_REGISTRY_LIMIT);
    size_t proof_entry_max = (SSZ_BYTE_SIZE_OF_UINT32 * 2u) + att_bits_max + LANTERN_AGG_PROOF_MAX_BYTES;
    size_t total = LANTERN_ATTESTATION_DATA_SSZ_SIZE + SSZ_BYTE_SIZE_OF_UINT32;
    if (proof_entry_max > SIZE_MAX - total) {
        return SIZE_MAX;
    }
    return total + proof_entry_max;
}

static size_t gossipsub_snappy_max_uncompressed(
    const struct lantern_gossipsub_service *service,
    const char *topic) {
    size_t block_max = signed_block_max_ssz_size();
    size_t vote_max = LANTERN_SIGNED_VOTE_SSZ_SIZE;
    size_t aggregated_max = signed_aggregated_attestation_max_ssz_size();
    size_t default_max = block_max > vote_max ? block_max : vote_max;
    if (aggregated_max > default_max) {
        default_max = aggregated_max;
    }
    if (!service || !topic) {
        return default_max;
    }
    if (service->block_topic[0] != '\0' && strcmp(topic, service->block_topic) == 0) {
        return block_max;
    }
    if (service->vote_topic[0] != '\0' && strcmp(topic, service->vote_topic) == 0) {
        return vote_max;
    }
    if (service->vote_subnet_topic[0] != '\0' && strcmp(topic, service->vote_subnet_topic) == 0) {
        return vote_max;
    }
    if (service->aggregated_attestation_topic[0] != '\0' && strcmp(topic, service->aggregated_attestation_topic) == 0)
    {
        return aggregated_max;
    }
    return default_max;
}

static libp2p_err_t lantern_gossipsub_message_id_cb(
    const libp2p_gossipsub_message_t *msg,
    uint8_t **out_id,
    size_t *out_len,
    void *user_data) {
    if (!msg || !out_id || !out_len) {
        return LIBP2P_ERR_NULL_PTR;
    }
    struct lantern_gossipsub_service *service = (struct lantern_gossipsub_service *)user_data;
    if (!service) {
        return LIBP2P_ERR_NULL_PTR;
    }
    const char *topic = msg->topic.topic;
   if (!topic) {
       return LIBP2P_ERR_INTERNAL;
   }

    uint8_t *scratch = NULL;
    size_t scratch_len = 0;
    if (msg->data && msg->data_len > 0) {
        size_t expected = 0;
        if (lantern_snappy_uncompressed_length_raw(msg->data, msg->data_len, &expected) == LANTERN_SNAPPY_OK
            && expected > 0) {
            size_t max_expected = gossipsub_snappy_max_uncompressed(service, topic);
            if (max_expected > 0 && expected > max_expected) {
                expected = 0;
            }
        }
        if (expected > 0) {
            scratch = (uint8_t *)malloc(expected);
            if (!scratch) {
                return LIBP2P_ERR_INTERNAL;
            }
            scratch_len = expected;
        }
    }

    LanternGossipMessageId id;
    if (lantern_gossip_compute_message_id(
            &id,
            (const uint8_t *)topic,
            strlen(topic),
            msg->data,
            msg->data_len,
            scratch,
            scratch_len,
            NULL)
        != 0) {
        free(scratch);
        return LIBP2P_ERR_INTERNAL;
    }

    free(scratch);
    uint8_t *buffer = (uint8_t *)malloc(LANTERN_GOSSIP_MESSAGE_ID_SIZE);
    if (!buffer) {
        return LIBP2P_ERR_INTERNAL;
    }
    memcpy(buffer, id.bytes, LANTERN_GOSSIP_MESSAGE_ID_SIZE);
    *out_id = buffer;
    *out_len = LANTERN_GOSSIP_MESSAGE_ID_SIZE;

    /* Debug: log message ID computation */
    char id_hex[LANTERN_GOSSIP_MESSAGE_ID_SIZE * 2 + 1];
    for (size_t i = 0; i < LANTERN_GOSSIP_MESSAGE_ID_SIZE; ++i) {
        snprintf(id_hex + (i * 2), 3, "%02x", id.bytes[i]);
    }
    lantern_log_debug(
        "gossip",
        NULL,
        "message_id_cb called topic=%s data_len=%zu msg_id=%s",
        topic,
        msg->data_len,
        id_hex);

    return LIBP2P_ERR_OK;
}

static int subscribe_topic(
    struct lantern_gossipsub_service *service,
    const char *topic) {
    if (!service || !service->gossipsub || !topic) {
        return -1;
    }
    libp2p_gossipsub_topic_config_t cfg;
    memset(&cfg, 0, sizeof(cfg));
    cfg.struct_size = sizeof(cfg);
    cfg.descriptor.struct_size = sizeof(cfg.descriptor);
    cfg.descriptor.topic = topic;
    cfg.message_id_fn = lantern_gossipsub_message_id_cb;
    cfg.message_id_user_data = service;
    libp2p_err_t err = libp2p_gossipsub_subscribe(service->gossipsub, &cfg);
    return err == LIBP2P_ERR_OK ? 0 : -1;
}

static libp2p_gossipsub_validation_result_t gossipsub_block_validator(
    const libp2p_gossipsub_message_t *msg,
    void *user_data) {
    struct lantern_gossipsub_service *service = (struct lantern_gossipsub_service *)user_data;
    if (!service || !msg) {
        return LIBP2P_GOSSIPSUB_VALIDATION_REJECT;
    }
    if (!service->block_handler || !msg->data || msg->data_len == 0) {
        return LIBP2P_GOSSIPSUB_VALIDATION_ACCEPT;
    }

    LanternSignedBlock block;
    lantern_signed_block_with_attestation_init(&block);
    uint8_t *raw_block_ssz = NULL;
    size_t raw_block_ssz_len = 0;

    libp2p_gossipsub_validation_result_t result = LIBP2P_GOSSIPSUB_VALIDATION_ACCEPT;
    char peer_text[128];
    describe_peer_id(msg->from, peer_text, sizeof(peer_text));
    const struct lantern_log_metadata meta = {.peer = peer_text[0] ? peer_text : NULL};

    if (gossipsub_message_has_forbidden_metadata(msg)) {
        lantern_log_debug(
            "gossip",
            &meta,
            "block gossip contains author/seqno/signature metadata (allowing for compatibility)");
    }

    lantern_log_debug(
        "gossip",
        &meta,
        "block gossip message received bytes=%zu from_peer=%s",
        msg->data_len,
        peer_text[0] ? peer_text : "(local)");
    if (lantern_gossip_decode_signed_block_snappy(
            &block,
            msg->data,
            msg->data_len,
            &raw_block_ssz,
            &raw_block_ssz_len)
        != 0) {
        lantern_log_warn(
            "gossip",
            &meta,
            "failed to decode gossip block payload bytes=%zu",
            msg->data_len);
        maybe_dump_invalid_gossip_payload(service, "block", msg->data, msg->data_len, &meta);
        result = LIBP2P_GOSSIPSUB_VALIDATION_REJECT;
        goto cleanup;
    }

    if (service->block_handler(
            &block,
            msg->from,
            raw_block_ssz,
            raw_block_ssz_len,
            service->block_handler_user_data)
        != 0)
    {
        result = LIBP2P_GOSSIPSUB_VALIDATION_IGNORE;
    }
    char block_root_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    if (lantern_bytes_to_hex(
            block.message.block.parent_root.bytes,
            LANTERN_ROOT_SIZE,
            block_root_hex,
            sizeof(block_root_hex),
            1)
        != 0) {
        block_root_hex[0] = '\0';
    }
    if (result == LIBP2P_GOSSIPSUB_VALIDATION_ACCEPT)
    {
        lantern_log_debug(
            "gossip",
            &meta,
            "accepted block gossip slot=%" PRIu64 " proposer=%" PRIu64 " parent=%s",
            block.message.block.slot,
            block.message.block.proposer_index,
            block_root_hex[0] ? block_root_hex : "0x0");
    }
    else if (result == LIBP2P_GOSSIPSUB_VALIDATION_IGNORE)
    {
        lantern_log_debug(
            "gossip",
            &meta,
            "ignored block gossip slot=%" PRIu64 " proposer=%" PRIu64 " parent=%s",
            block.message.block.slot,
            block.message.block.proposer_index,
            block_root_hex[0] ? block_root_hex : "0x0");
    }

cleanup:
    free(raw_block_ssz);
    lantern_signed_block_with_attestation_reset(&block);
    return result;
}

static libp2p_gossipsub_validation_result_t gossipsub_vote_validator(
    const libp2p_gossipsub_message_t *msg,
    void *user_data) {
    struct lantern_gossipsub_service *service = (struct lantern_gossipsub_service *)user_data;
    if (!service || !msg) {
        return LIBP2P_GOSSIPSUB_VALIDATION_REJECT;
    }
    if (!service->vote_handler || !msg->data || msg->data_len == 0) {
        return LIBP2P_GOSSIPSUB_VALIDATION_ACCEPT;
    }

    LanternSignedVote vote;
    memset(&vote, 0, sizeof(vote));

    libp2p_gossipsub_validation_result_t result = LIBP2P_GOSSIPSUB_VALIDATION_ACCEPT;
    char peer_text[128];
    describe_peer_id(msg->from, peer_text, sizeof(peer_text));
    const struct lantern_log_metadata meta = {.peer = peer_text[0] ? peer_text : NULL};

    if (gossipsub_message_has_forbidden_metadata(msg)) {
        lantern_log_debug(
            "gossip",
            &meta,
            "vote gossip contains author/seqno/signature metadata (allowing for compatibility)");
    }

    lantern_log_debug(
        "gossip",
        &meta,
        "vote gossip message received bytes=%zu",
        msg->data_len);
    if (lantern_gossip_decode_signed_vote_snappy(&vote, msg->data, msg->data_len) != 0) {
        lantern_log_warn(
            "gossip",
            &meta,
            "failed to decode gossip vote payload bytes=%zu",
            msg->data_len);
        maybe_dump_invalid_gossip_payload(service, "vote", msg->data, msg->data_len, &meta);
        result = LIBP2P_GOSSIPSUB_VALIDATION_REJECT;
        goto cleanup;
    }

    if (service->vote_handler(&vote, msg->from, service->vote_handler_user_data) != 0)
    {
        result = LIBP2P_GOSSIPSUB_VALIDATION_IGNORE;
    }
    char head_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    if (lantern_bytes_to_hex(
            vote.data.head.root.bytes,
            LANTERN_ROOT_SIZE,
            head_hex,
            sizeof(head_hex),
            1)
        != 0) {
        head_hex[0] = '\0';
    }
    if (result == LIBP2P_GOSSIPSUB_VALIDATION_ACCEPT)
    {
        lantern_log_debug(
            "gossip",
            &meta,
            "accepted vote gossip validator=%" PRIu64 " slot=%" PRIu64 " head=%s",
            vote.data.validator_id,
            vote.data.slot,
            head_hex[0] ? head_hex : "0x0");
    }
    else if (result == LIBP2P_GOSSIPSUB_VALIDATION_IGNORE)
    {
        lantern_log_debug(
            "gossip",
            &meta,
            "ignored vote gossip validator=%" PRIu64 " slot=%" PRIu64 " head=%s",
            vote.data.validator_id,
            vote.data.slot,
            head_hex[0] ? head_hex : "0x0");
    }

cleanup:
    return result;
}

static libp2p_gossipsub_validation_result_t gossipsub_aggregated_attestation_validator(
    const libp2p_gossipsub_message_t *msg,
    void *user_data) {
    struct lantern_gossipsub_service *service = (struct lantern_gossipsub_service *)user_data;
    if (!service || !msg) {
        return LIBP2P_GOSSIPSUB_VALIDATION_REJECT;
    }
    if (!service->aggregated_attestation_handler || !msg->data || msg->data_len == 0) {
        return LIBP2P_GOSSIPSUB_VALIDATION_ACCEPT;
    }

    LanternSignedAggregatedAttestation attestation;
    lantern_signed_aggregated_attestation_init(&attestation);

    libp2p_gossipsub_validation_result_t result = LIBP2P_GOSSIPSUB_VALIDATION_ACCEPT;
    char peer_text[128];
    describe_peer_id(msg->from, peer_text, sizeof(peer_text));
    const struct lantern_log_metadata meta = {.peer = peer_text[0] ? peer_text : NULL};

    if (gossipsub_message_has_forbidden_metadata(msg)) {
        lantern_log_debug(
            "gossip",
            &meta,
            "aggregated attestation gossip contains author/seqno/signature metadata (allowing for compatibility)");
    }

    lantern_log_debug(
        "gossip",
        &meta,
        "aggregated attestation gossip message received bytes=%zu",
        msg->data_len);
    if (lantern_gossip_decode_signed_aggregated_attestation_snappy(&attestation, msg->data, msg->data_len) != 0) {
        lantern_log_warn(
            "gossip",
            &meta,
            "failed to decode aggregated attestation gossip payload bytes=%zu",
            msg->data_len);
        maybe_dump_invalid_gossip_payload(
            service,
            "aggregated_attestation",
            msg->data,
            msg->data_len,
            &meta);
        result = LIBP2P_GOSSIPSUB_VALIDATION_REJECT;
        goto cleanup;
    }

    if (service->aggregated_attestation_handler(
            &attestation,
            msg->from,
            service->aggregated_attestation_handler_user_data)
        != 0) {
        result = LIBP2P_GOSSIPSUB_VALIDATION_IGNORE;
    }

cleanup:
    lantern_signed_aggregated_attestation_reset(&attestation);
    return result;
}

void lantern_gossipsub_service_init(struct lantern_gossipsub_service *service) {
    if (!service) {
        return;
    }
    memset(service, 0, sizeof(*service));
}

void lantern_gossipsub_service_reset(struct lantern_gossipsub_service *service) {
    if (!service) {
        return;
    }
    if (service->gossipsub) {
        if (service->block_validator_handle) {
            (void)libp2p_gossipsub_remove_validator(service->gossipsub, service->block_validator_handle);
        }
        if (service->vote_validator_handle) {
            (void)libp2p_gossipsub_remove_validator(service->gossipsub, service->vote_validator_handle);
        }
        if (service->vote_subnet_validator_handle) {
            (void)libp2p_gossipsub_remove_validator(service->gossipsub, service->vote_subnet_validator_handle);
        }
        if (service->aggregated_attestation_validator_handle) {
            (void)libp2p_gossipsub_remove_validator(
                service->gossipsub,
                service->aggregated_attestation_validator_handle);
        }
    }
    service->block_validator_handle = NULL;
    service->vote_validator_handle = NULL;
    service->vote_subnet_validator_handle = NULL;
    service->aggregated_attestation_validator_handle = NULL;
    if (service->gossipsub) {
        libp2p_gossipsub_stop(service->gossipsub);
        libp2p_gossipsub_free(service->gossipsub);
        service->gossipsub = NULL;
    }
    memset(service->block_topic, 0, sizeof(service->block_topic));
    memset(service->vote_topic, 0, sizeof(service->vote_topic));
    memset(service->vote_subnet_topic, 0, sizeof(service->vote_subnet_topic));
    memset(service->aggregated_attestation_topic, 0, sizeof(service->aggregated_attestation_topic));
    service->data_dir = NULL;
    service->attestation_subnet_id = 0;
    service->subscribe_attestation_subnet = 0;
    service->publish_hook = NULL;
    service->publish_hook_user_data = NULL;
    service->loopback_only = 0;
}

int lantern_gossipsub_service_start(
    struct lantern_gossipsub_service *service,
    const struct lantern_gossipsub_config *config) {
    if (!service || !config || !config->host || !config->devnet) {
        return -1;
    }
    int previous_loopback = service->loopback_only;
    int (*previous_publish_hook)(const char *, const uint8_t *, size_t, void *) = service->publish_hook;
    void *previous_publish_user_data = service->publish_hook_user_data;
    lantern_gossipsub_block_handler previous_block_handler = service->block_handler;
    void *previous_block_user_data = service->block_handler_user_data;
    lantern_gossipsub_vote_handler previous_vote_handler = service->vote_handler;
    void *previous_vote_user_data = service->vote_handler_user_data;
    lantern_gossipsub_aggregated_attestation_handler previous_aggregated_handler =
        service->aggregated_attestation_handler;
    void *previous_aggregated_user_data = service->aggregated_attestation_handler_user_data;

    lantern_gossipsub_service_reset(service);
    service->loopback_only = previous_loopback;
    service->publish_hook = previous_publish_hook;
    service->publish_hook_user_data = previous_publish_user_data;
    service->block_handler = previous_block_handler;
    service->block_handler_user_data = previous_block_user_data;
    service->vote_handler = previous_vote_handler;
    service->vote_handler_user_data = previous_vote_user_data;
    service->aggregated_attestation_handler = previous_aggregated_handler;
    service->aggregated_attestation_handler_user_data = previous_aggregated_user_data;
    service->data_dir = config->data_dir;
    service->attestation_subnet_id = config->attestation_subnet_id;
    service->subscribe_attestation_subnet = config->subscribe_attestation_subnet ? 1 : 0;

    if (lantern_gossip_topic_format(
            LANTERN_GOSSIP_TOPIC_BLOCK,
            config->devnet,
            service->block_topic,
            sizeof(service->block_topic))
        != 0) {
        return -1;
    }
    if (lantern_gossip_topic_format(
            LANTERN_GOSSIP_TOPIC_VOTE,
            config->devnet,
            service->vote_topic,
            sizeof(service->vote_topic))
        != 0) {
        return -1;
    }
    if (lantern_gossip_topic_format_subnet(
            LANTERN_GOSSIP_TOPIC_VOTE_SUBNET,
            config->devnet,
            config->attestation_subnet_id,
            service->vote_subnet_topic,
            sizeof(service->vote_subnet_topic))
        != 0) {
        return -1;
    }
    if (lantern_gossip_topic_format(
            LANTERN_GOSSIP_TOPIC_AGGREGATED_ATTESTATION,
            config->devnet,
            service->aggregated_attestation_topic,
            sizeof(service->aggregated_attestation_topic))
        != 0) {
        return -1;
    }

    libp2p_gossipsub_config_t cfg;
    if (libp2p_gossipsub_config_default(&cfg) != LIBP2P_ERR_OK) {
        return -1;
    }
    cfg.heartbeat_interval_ms = LANTERN_GOSSIPSUB_HEARTBEAT_INTERVAL_MS;
    cfg.d = LANTERN_GOSSIPSUB_MESH_D;
    cfg.d_lo = LANTERN_GOSSIPSUB_MESH_D_LOW;
    cfg.d_hi = LANTERN_GOSSIPSUB_MESH_D_HIGH;
    cfg.d_lazy = LANTERN_GOSSIPSUB_MESH_D_LAZY;
    cfg.message_cache_length = LANTERN_GOSSIPSUB_MESSAGE_CACHE_LEN;
    cfg.message_cache_gossip = LANTERN_GOSSIPSUB_MESSAGE_CACHE_GOSSIP;
    cfg.seen_cache_ttl_ms = (int)lantern_leanspec_seen_ttl_ms();
    cfg.fanout_ttl_ms = LANTERN_GOSSIPSUB_FANOUT_TTL_MS;
    cfg.protocol_ids = k_leanspec_gossipsub_protocols;
    cfg.protocol_id_count = LANTERN_ARRAY_SIZE(k_leanspec_gossipsub_protocols);
    cfg.enable_flood_publish = true;
    cfg.on_score_update = lantern_gossipsub_score_update;
    cfg.score_update_user_data = service;
    cfg.anonymous_mode = true; /* Required for rust-libp2p compatibility (Anonymous validation mode) */

    libp2p_gossipsub_t *gs = NULL;
    if (libp2p_gossipsub_new(config->host, &cfg, &gs) != LIBP2P_ERR_OK || !gs) {
        return -1;
    }
    if (libp2p_gossipsub_start(gs) != LIBP2P_ERR_OK) {
        libp2p_gossipsub_free(gs);
        return -1;
    }
    service->gossipsub = gs;
    if (subscribe_topic(service, service->block_topic) != 0) {
        lantern_gossipsub_service_reset(service);
        return -1;
    }
    lantern_log_info(
        "gossip",
        &(const struct lantern_log_metadata){.peer = config->devnet},
        "subscribed gossipsub topic=%s",
        service->block_topic);
    if (subscribe_topic(service, service->vote_topic) != 0) {
        lantern_gossipsub_service_reset(service);
        return -1;
    }
    lantern_log_info(
        "gossip",
        &(const struct lantern_log_metadata){.peer = config->devnet},
        "subscribed gossipsub topic=%s",
        service->vote_topic);
    if (service->subscribe_attestation_subnet) {
        if (subscribe_topic(service, service->vote_subnet_topic) != 0) {
            lantern_gossipsub_service_reset(service);
            return -1;
        }
        lantern_log_info(
            "gossip",
            &(const struct lantern_log_metadata){.peer = config->devnet},
            "subscribed gossipsub topic=%s",
            service->vote_subnet_topic);
    }
    if (subscribe_topic(service, service->aggregated_attestation_topic) != 0) {
        lantern_gossipsub_service_reset(service);
        return -1;
    }
    lantern_log_info(
        "gossip",
        &(const struct lantern_log_metadata){.peer = config->devnet},
        "subscribed gossipsub topic=%s",
        service->aggregated_attestation_topic);

    if (service->block_handler) {
        libp2p_gossipsub_validator_def_t def = {
            .struct_size = sizeof(def),
            .type = LIBP2P_GOSSIPSUB_VALIDATOR_SYNC,
            .sync_fn = gossipsub_block_validator,
            .async_fn = NULL,
            .user_data = service
        };
        if (libp2p_gossipsub_add_validator(service->gossipsub, service->block_topic, &def, &service->block_validator_handle)
            != LIBP2P_ERR_OK) {
            lantern_log_error(
                "gossip",
                NULL,
                "failed to register block gossip validator");
            lantern_gossipsub_service_reset(service);
            return -1;
        }
    }

    if (service->vote_handler) {
        libp2p_gossipsub_validator_def_t def = {
            .struct_size = sizeof(def),
            .type = LIBP2P_GOSSIPSUB_VALIDATOR_SYNC,
            .sync_fn = gossipsub_vote_validator,
            .async_fn = NULL,
            .user_data = service
        };
        if (libp2p_gossipsub_add_validator(service->gossipsub, service->vote_topic, &def, &service->vote_validator_handle)
            != LIBP2P_ERR_OK) {
            lantern_log_error(
                "gossip",
                NULL,
                "failed to register vote gossip validator");
            lantern_gossipsub_service_reset(service);
            return -1;
        }
        if (service->subscribe_attestation_subnet) {
            if (libp2p_gossipsub_add_validator(
                    service->gossipsub,
                    service->vote_subnet_topic,
                    &def,
                    &service->vote_subnet_validator_handle)
                != LIBP2P_ERR_OK) {
                lantern_log_error(
                    "gossip",
                    NULL,
                    "failed to register subnet vote gossip validator");
                lantern_gossipsub_service_reset(service);
                return -1;
            }
        }
    }

    if (service->aggregated_attestation_handler) {
        libp2p_gossipsub_validator_def_t def = {
            .struct_size = sizeof(def),
            .type = LIBP2P_GOSSIPSUB_VALIDATOR_SYNC,
            .sync_fn = gossipsub_aggregated_attestation_validator,
            .async_fn = NULL,
            .user_data = service
        };
        if (libp2p_gossipsub_add_validator(
                service->gossipsub,
                service->aggregated_attestation_topic,
                &def,
                &service->aggregated_attestation_validator_handle)
            != LIBP2P_ERR_OK) {
            lantern_log_error(
                "gossip",
                NULL,
                "failed to register aggregated attestation gossip validator");
            lantern_gossipsub_service_reset(service);
            return -1;
        }
    }

    lantern_log_info(
        "network",
        &(const struct lantern_log_metadata){.peer = config->devnet},
        "gossipsub topics ready");
    return 0;
}

static int publish_payload(
    struct lantern_gossipsub_service *service,
    const char *topic,
    const uint8_t *payload,
    size_t payload_len) {
    if (!service || !topic || !payload || payload_len == 0) {
        return -1;
    }
    if (service->publish_hook) {
        if (service->publish_hook(topic, payload, payload_len, service->publish_hook_user_data) != 0) {
            return -1;
        }
    }
    if (service->loopback_only) {
        return 0;
    }
    if (!service->gossipsub) {
        return -1;
    }
    libp2p_gossipsub_message_t message;
    memset(&message, 0, sizeof(message));
    message.topic.struct_size = sizeof(message.topic);
    message.topic.topic = topic;
    message.data = payload;
    message.data_len = payload_len;
    libp2p_err_t err = libp2p_gossipsub_publish(service->gossipsub, &message);
    if (err != LIBP2P_ERR_OK) {
        lantern_log_warn(
            "gossip",
            NULL,
            "gossipsub publish failed for topic %s (err=%d)",
            topic,
            (int)err);
        return -1;
    }
    return 0;
}

int lantern_gossipsub_service_publish_block(
    struct lantern_gossipsub_service *service,
    const LanternSignedBlock *block) {
    if (!service || !block) {
        return -1;
    }
    size_t raw_capacity = signed_block_min_capacity(block);
    if (raw_capacity == 0) {
        return -1;
    }
    size_t max_compressed = 0;
    /* Use raw snappy max size (no framing overhead) for gossip */
    if (lantern_snappy_max_compressed_size_raw(raw_capacity, &max_compressed) != LANTERN_SNAPPY_OK) {
        return -1;
    }
    uint8_t *compressed = (uint8_t *)malloc(max_compressed);
    if (!compressed) {
        return -1;
    }
    size_t written = 0;
    int encode_rc = lantern_gossip_encode_signed_block_snappy(block, compressed, max_compressed, &written);
    if (encode_rc != 0 || written == 0) {
        free(compressed);
        return -1;
    }
    int publish_rc = publish_payload(service, service->block_topic, compressed, written);
    free(compressed);
    return publish_rc;
}

int lantern_gossipsub_service_publish_vote(
    struct lantern_gossipsub_service *service,
    const LanternSignedVote *vote) {
    if (!service || !vote) {
        return -1;
    }
    size_t max_compressed = 0;
    /* Use raw snappy max size (no framing overhead) for gossip */
    if (lantern_snappy_max_compressed_size_raw(LANTERN_SIGNED_VOTE_SSZ_SIZE, &max_compressed) != LANTERN_SNAPPY_OK) {
        return -1;
    }
    uint8_t *compressed = (uint8_t *)malloc(max_compressed);
    if (!compressed) {
        return -1;
    }
    size_t written = 0;
    int encode_rc = lantern_gossip_encode_signed_vote_snappy(vote, compressed, max_compressed, &written);
   if (encode_rc != 0 || written == 0) {
       free(compressed);
       return -1;
   }
    int publish_rc = publish_payload(service, service->vote_topic, compressed, written);
    free(compressed);
    return publish_rc;
}

int lantern_gossipsub_service_publish_vote_subnet(
    struct lantern_gossipsub_service *service,
    const LanternSignedVote *vote) {
    if (!service || !vote || service->vote_subnet_topic[0] == '\0') {
        return -1;
    }
    size_t max_compressed = 0;
    if (lantern_snappy_max_compressed_size_raw(LANTERN_SIGNED_VOTE_SSZ_SIZE, &max_compressed) != LANTERN_SNAPPY_OK) {
        return -1;
    }
    uint8_t *compressed = (uint8_t *)malloc(max_compressed);
    if (!compressed) {
        return -1;
    }
    size_t written = 0;
    if (lantern_gossip_encode_signed_vote_snappy(vote, compressed, max_compressed, &written) != 0 || written == 0) {
        free(compressed);
        return -1;
    }
    int publish_rc = publish_payload(service, service->vote_subnet_topic, compressed, written);
    free(compressed);
    return publish_rc;
}

int lantern_gossipsub_service_publish_aggregated_attestation(
    struct lantern_gossipsub_service *service,
    const LanternSignedAggregatedAttestation *attestation) {
    if (!service || !attestation || service->aggregated_attestation_topic[0] == '\0') {
        return -1;
    }
    size_t max_compressed = 0;
    size_t max_raw = signed_aggregated_attestation_max_ssz_size();
    if (lantern_snappy_max_compressed_size_raw(max_raw, &max_compressed) != LANTERN_SNAPPY_OK) {
        return -1;
    }
    uint8_t *compressed = (uint8_t *)malloc(max_compressed);
    if (!compressed) {
        return -1;
    }
    size_t written = 0;
    if (lantern_gossip_encode_signed_aggregated_attestation_snappy(
            attestation,
            compressed,
            max_compressed,
            &written)
        != 0
        || written == 0) {
        free(compressed);
        return -1;
    }
    int publish_rc = publish_payload(service, service->aggregated_attestation_topic, compressed, written);
    free(compressed);
    return publish_rc;
}

void lantern_gossipsub_service_set_publish_hook(
    struct lantern_gossipsub_service *service,
    int (*hook)(const char *topic, const uint8_t *payload, size_t payload_len, void *user_data),
    void *user_data) {
    if (!service) {
        return;
    }
    service->publish_hook = hook;
    service->publish_hook_user_data = user_data;
}

void lantern_gossipsub_service_set_loopback_only(
    struct lantern_gossipsub_service *service,
    int loopback_only) {
    if (!service) {
        return;
    }
    service->loopback_only = loopback_only ? 1 : 0;
}

void lantern_gossipsub_service_set_block_handler(
    struct lantern_gossipsub_service *service,
    lantern_gossipsub_block_handler handler,
    void *user_data) {
    if (!service) {
        return;
    }
    service->block_handler = handler;
    service->block_handler_user_data = user_data;
}

void lantern_gossipsub_service_set_vote_handler(
    struct lantern_gossipsub_service *service,
    lantern_gossipsub_vote_handler handler,
    void *user_data) {
    if (!service) {
        return;
    }
    service->vote_handler = handler;
    service->vote_handler_user_data = user_data;
}

void lantern_gossipsub_service_set_aggregated_attestation_handler(
    struct lantern_gossipsub_service *service,
    lantern_gossipsub_aggregated_attestation_handler handler,
    void *user_data) {
    if (!service) {
        return;
    }
    service->aggregated_attestation_handler = handler;
    service->aggregated_attestation_handler_user_data = user_data;
}
