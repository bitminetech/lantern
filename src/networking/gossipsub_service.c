#include "lantern/networking/gossipsub_service.h"

#include <limits.h>
#include <inttypes.h>
#include <pthread.h>
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

#define LANTERN_GOSSIPSUB_TOPIC_CAP 128u
#define LANTERN_ARRAY_SIZE(arr) (sizeof(arr) / sizeof((arr)[0]))
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
#define LANTERN_GOSSIPSUB_VALIDATION_WORKER_COUNT 4u
#define LANTERN_GOSSIPSUB_VALIDATION_QUEUE_CAPACITY 128u

static const char *const k_leanspec_gossipsub_protocols[] = {
    "/meshsub/1.1.0",
    "/meshsub/1.0.0",
};

enum lantern_gossipsub_validation_job_kind {
    LANTERN_GOSSIPSUB_JOB_BLOCK = 0,
    LANTERN_GOSSIPSUB_JOB_VOTE,
    LANTERN_GOSSIPSUB_JOB_AGGREGATED_ATTESTATION,
    LANTERN_GOSSIPSUB_JOB_UNKNOWN,
};

struct lantern_gossipsub_validation_job {
    enum lantern_gossipsub_validation_job_kind kind;
    char *topic;
    uint8_t *payload;
    size_t payload_len;
    peer_id_t *propagation_source;
    uint8_t *message_id;
    size_t message_id_len;
};

struct lantern_gossipsub_validation_pool {
    pthread_mutex_t mutex;
    pthread_cond_t not_empty;
    pthread_t *threads;
    struct lantern_gossipsub_validation_job **queue;
    size_t worker_count;
    size_t queue_capacity;
    size_t queue_head;
    size_t queue_len;
    int stopping;
    int started;
    struct lantern_gossipsub_service *service;
};

static void lantern_gossipsub_validation_job_free(struct lantern_gossipsub_validation_job *job) {
    if (!job) {
        return;
    }
    free(job->topic);
    free(job->payload);
    if (job->propagation_source) {
        peer_id_free(job->propagation_source);
    }
    free(job->message_id);
    free(job);
}

static enum lantern_gossipsub_validation_job_kind lantern_gossipsub_classify_topic(
    const struct lantern_gossipsub_service *service,
    const char *topic);
static libp2p_gossipsub_validation_result_t lantern_validate_block_payload(
    struct lantern_gossipsub_service *service,
    const uint8_t *payload,
    size_t payload_len,
    const peer_id_t *propagation_source);
static libp2p_gossipsub_validation_result_t lantern_validate_vote_payload(
    struct lantern_gossipsub_service *service,
    const uint8_t *payload,
    size_t payload_len,
    const peer_id_t *propagation_source);
static libp2p_gossipsub_validation_result_t lantern_validate_aggregated_attestation_payload(
    struct lantern_gossipsub_service *service,
    const uint8_t *payload,
    size_t payload_len,
    const peer_id_t *propagation_source);
static int lantern_gossipsub_validation_pool_start(struct lantern_gossipsub_service *service);
static void lantern_gossipsub_validation_pool_stop(struct lantern_gossipsub_service *service);
static int lantern_gossipsub_validation_pool_try_enqueue(
    struct lantern_gossipsub_service *service,
    struct lantern_gossipsub_validation_job *job);
static void lantern_gossipsub_message_delivery_cb(
    libp2p_gossipsub_t *gs,
    const libp2p_gossipsub_message_t *msg,
    const uint8_t *message_id,
    size_t message_id_len,
    const peer_id_t *propagation_source,
    void *user_data);

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

static size_t signed_block_min_capacity(const LanternSignedBlock *block) {
    if (!block) {
        return 0;
    }
    size_t offsets = SSZ_BYTE_SIZE_OF_UINT32 * 2u;
    size_t block_fixed = (SSZ_BYTE_SIZE_OF_UINT64 * 2u)
        + (LANTERN_ROOT_SIZE * 2u)
        + SSZ_BYTE_SIZE_OF_UINT32;
    size_t body_header = SSZ_BYTE_SIZE_OF_UINT32;
    size_t att_count = block->block.body.attestations.length;
    size_t att_bytes = aggregated_attestations_encoded_size(&block->block.body.attestations);
    if (att_count > 0 && att_bytes == 0) {
        return 0;
    }
    size_t sig_count = block->signatures.attestation_signatures.length;
    size_t sig_list_bytes = attestation_signatures_encoded_size(&block->signatures.attestation_signatures);
    if (sig_count > 0 && sig_list_bytes == 0) {
        return 0;
    }
    size_t signatures_bytes = (SSZ_BYTE_SIZE_OF_UINT32 * 2u) + LANTERN_SIGNATURE_SIZE + sig_list_bytes;
    size_t total = offsets + block_fixed;
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
    size_t body_header = SSZ_BYTE_SIZE_OF_UINT32;
    size_t att_bits_max = bitlist_encoded_size_bits(LANTERN_VALIDATOR_REGISTRY_LIMIT);
    size_t att_entry_max = SSZ_BYTE_SIZE_OF_UINT32 + LANTERN_ATTESTATION_DATA_SSZ_SIZE + att_bits_max;
    size_t att_bytes = (size_t)LANTERN_MAX_ATTESTATIONS * (SSZ_BYTE_SIZE_OF_UINT32 + att_entry_max);
    size_t proof_bits_max = att_bits_max;
    size_t proof_entry_max = (SSZ_BYTE_SIZE_OF_UINT32 * 2u) + proof_bits_max + LANTERN_AGG_PROOF_MAX_BYTES;
    size_t signatures_bytes = (SSZ_BYTE_SIZE_OF_UINT32 * 2u) + LANTERN_SIGNATURE_SIZE
        + ((size_t)LANTERN_MAX_BLOCK_SIGNATURES * (SSZ_BYTE_SIZE_OF_UINT32 + proof_entry_max));
    size_t total = offsets + block_fixed;
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
    if (service) {
        if (service->vote_subnet_topic[0] != '\0' && strcmp(topic, service->vote_subnet_topic) == 0) {
            return vote_max;
        }
        for (size_t i = 0; i < service->extra_vote_subnet_topic_count; ++i) {
            if (strcmp(topic, service->extra_vote_subnet_topics[i]) == 0) {
                return vote_max;
            }
        }
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

static enum lantern_gossipsub_validation_job_kind lantern_gossipsub_classify_topic(
    const struct lantern_gossipsub_service *service,
    const char *topic) {
    if (!service || !topic) {
        return LANTERN_GOSSIPSUB_JOB_UNKNOWN;
    }
    if (service->block_topic[0] != '\0' && strcmp(topic, service->block_topic) == 0) {
        return LANTERN_GOSSIPSUB_JOB_BLOCK;
    }
    if (service->aggregated_attestation_topic[0] != '\0'
        && strcmp(topic, service->aggregated_attestation_topic) == 0) {
        return LANTERN_GOSSIPSUB_JOB_AGGREGATED_ATTESTATION;
    }
    if (service->vote_topic[0] != '\0' && strcmp(topic, service->vote_topic) == 0) {
        return LANTERN_GOSSIPSUB_JOB_VOTE;
    }
    if (service->vote_subnet_topic[0] != '\0' && strcmp(topic, service->vote_subnet_topic) == 0) {
        return LANTERN_GOSSIPSUB_JOB_VOTE;
    }
    for (size_t i = 0; i < service->extra_vote_subnet_topic_count; ++i) {
        if (strcmp(topic, service->extra_vote_subnet_topics[i]) == 0) {
            return LANTERN_GOSSIPSUB_JOB_VOTE;
        }
    }
    return LANTERN_GOSSIPSUB_JOB_UNKNOWN;
}

static libp2p_gossipsub_validation_result_t lantern_validate_block_payload(
    struct lantern_gossipsub_service *service,
    const uint8_t *payload,
    size_t payload_len,
    const peer_id_t *propagation_source) {
    if (!service) {
        return LIBP2P_GOSSIPSUB_VALIDATION_REJECT;
    }
    if (!service->block_handler || !payload || payload_len == 0) {
        return LIBP2P_GOSSIPSUB_VALIDATION_ACCEPT;
    }

    LanternSignedBlock block;
    lantern_signed_block_init(&block);
    uint8_t *raw_block_ssz = NULL;
    size_t raw_block_ssz_len = 0;

    libp2p_gossipsub_validation_result_t result = LIBP2P_GOSSIPSUB_VALIDATION_ACCEPT;
    char peer_text[128];
    describe_peer_id(propagation_source, peer_text, sizeof(peer_text));
    const struct lantern_log_metadata meta = {.peer = peer_text[0] ? peer_text : NULL};

    lantern_log_debug(
        "gossip",
        &meta,
        "block gossip message received bytes=%zu from_peer=%s",
        payload_len,
        peer_text[0] ? peer_text : "(local)");
    if (lantern_gossip_decode_signed_block_snappy(
            &block,
            payload,
            payload_len,
            &raw_block_ssz,
            &raw_block_ssz_len)
        != 0) {
        lantern_log_warn(
            "gossip",
            &meta,
            "failed to decode gossip block payload bytes=%zu",
            payload_len);
        maybe_dump_invalid_gossip_payload(service, "block", payload, payload_len, &meta);
        result = LIBP2P_GOSSIPSUB_VALIDATION_REJECT;
        goto cleanup;
    }

    if (service->block_handler(
            &block,
            propagation_source,
            raw_block_ssz,
            raw_block_ssz_len,
            service->block_handler_user_data)
        != 0) {
        result = LIBP2P_GOSSIPSUB_VALIDATION_IGNORE;
    }
    char block_root_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    if (lantern_bytes_to_hex(
            block.block.parent_root.bytes,
            LANTERN_ROOT_SIZE,
            block_root_hex,
            sizeof(block_root_hex),
            1)
        != 0) {
        block_root_hex[0] = '\0';
    }
    if (result == LIBP2P_GOSSIPSUB_VALIDATION_ACCEPT) {
        lantern_log_debug(
            "gossip",
            &meta,
            "accepted block gossip slot=%" PRIu64 " proposer=%" PRIu64 " parent=%s",
            block.block.slot,
            block.block.proposer_index,
            block_root_hex[0] ? block_root_hex : "0x0");
    } else if (result == LIBP2P_GOSSIPSUB_VALIDATION_IGNORE) {
        lantern_log_debug(
            "gossip",
            &meta,
            "ignored block gossip slot=%" PRIu64 " proposer=%" PRIu64 " parent=%s",
            block.block.slot,
            block.block.proposer_index,
            block_root_hex[0] ? block_root_hex : "0x0");
    }

cleanup:
    free(raw_block_ssz);
    lantern_signed_block_reset(&block);
    return result;
}

static libp2p_gossipsub_validation_result_t lantern_validate_vote_payload(
    struct lantern_gossipsub_service *service,
    const uint8_t *payload,
    size_t payload_len,
    const peer_id_t *propagation_source) {
    if (!service) {
        return LIBP2P_GOSSIPSUB_VALIDATION_REJECT;
    }
    if (!service->vote_handler || !payload || payload_len == 0) {
        return LIBP2P_GOSSIPSUB_VALIDATION_ACCEPT;
    }

    LanternSignedVote vote;
    memset(&vote, 0, sizeof(vote));

    libp2p_gossipsub_validation_result_t result = LIBP2P_GOSSIPSUB_VALIDATION_ACCEPT;
    char peer_text[128];
    describe_peer_id(propagation_source, peer_text, sizeof(peer_text));
    const struct lantern_log_metadata meta = {.peer = peer_text[0] ? peer_text : NULL};

    lantern_log_debug(
        "gossip",
        &meta,
        "vote gossip message received bytes=%zu",
        payload_len);
    if (lantern_gossip_decode_signed_vote_snappy(&vote, payload, payload_len) != 0) {
        lantern_log_warn(
            "gossip",
            &meta,
            "failed to decode gossip vote payload bytes=%zu",
            payload_len);
        maybe_dump_invalid_gossip_payload(service, "vote", payload, payload_len, &meta);
        result = LIBP2P_GOSSIPSUB_VALIDATION_REJECT;
        goto cleanup;
    }

    if (service->vote_handler(&vote, propagation_source, service->vote_handler_user_data) != 0) {
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
    if (result == LIBP2P_GOSSIPSUB_VALIDATION_ACCEPT) {
        lantern_log_debug(
            "gossip",
            &meta,
            "accepted vote gossip validator=%" PRIu64 " slot=%" PRIu64 " head=%s",
            vote.data.validator_id,
            vote.data.slot,
            head_hex[0] ? head_hex : "0x0");
    } else if (result == LIBP2P_GOSSIPSUB_VALIDATION_IGNORE) {
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

static libp2p_gossipsub_validation_result_t lantern_validate_aggregated_attestation_payload(
    struct lantern_gossipsub_service *service,
    const uint8_t *payload,
    size_t payload_len,
    const peer_id_t *propagation_source) {
    if (!service) {
        return LIBP2P_GOSSIPSUB_VALIDATION_REJECT;
    }
    if (!service->aggregated_attestation_handler || !payload || payload_len == 0) {
        return LIBP2P_GOSSIPSUB_VALIDATION_ACCEPT;
    }

    LanternSignedAggregatedAttestation attestation;
    lantern_signed_aggregated_attestation_init(&attestation);

    libp2p_gossipsub_validation_result_t result = LIBP2P_GOSSIPSUB_VALIDATION_ACCEPT;
    char peer_text[128];
    describe_peer_id(propagation_source, peer_text, sizeof(peer_text));
    const struct lantern_log_metadata meta = {.peer = peer_text[0] ? peer_text : NULL};

    lantern_log_debug(
        "gossip",
        &meta,
        "aggregated attestation gossip message received bytes=%zu",
        payload_len);
    if (lantern_gossip_decode_signed_aggregated_attestation_snappy(&attestation, payload, payload_len) != 0) {
        lantern_log_warn(
            "gossip",
            &meta,
            "failed to decode aggregated attestation gossip payload bytes=%zu",
            payload_len);
        maybe_dump_invalid_gossip_payload(
            service,
            "aggregated_attestation",
            payload,
            payload_len,
            &meta);
        result = LIBP2P_GOSSIPSUB_VALIDATION_REJECT;
        goto cleanup;
    }

    if (service->aggregated_attestation_handler(
            &attestation,
            propagation_source,
            service->aggregated_attestation_handler_user_data)
        != 0) {
        result = LIBP2P_GOSSIPSUB_VALIDATION_IGNORE;
    }

cleanup:
    lantern_signed_aggregated_attestation_reset(&attestation);
    return result;
}

static libp2p_gossipsub_validation_result_t lantern_gossipsub_validation_job_run(
    struct lantern_gossipsub_service *service,
    const struct lantern_gossipsub_validation_job *job) {
    if (!service || !job) {
        return LIBP2P_GOSSIPSUB_VALIDATION_IGNORE;
    }

    switch (job->kind) {
    case LANTERN_GOSSIPSUB_JOB_BLOCK:
        return lantern_validate_block_payload(service, job->payload, job->payload_len, job->propagation_source);
    case LANTERN_GOSSIPSUB_JOB_VOTE:
        return lantern_validate_vote_payload(service, job->payload, job->payload_len, job->propagation_source);
    case LANTERN_GOSSIPSUB_JOB_AGGREGATED_ATTESTATION:
        return lantern_validate_aggregated_attestation_payload(
            service,
            job->payload,
            job->payload_len,
            job->propagation_source);
    default:
        return LIBP2P_GOSSIPSUB_VALIDATION_ACCEPT;
    }
}

static struct lantern_gossipsub_validation_job *lantern_gossipsub_validation_job_new(
    enum lantern_gossipsub_validation_job_kind kind,
    const char *topic,
    const uint8_t *payload,
    size_t payload_len,
    const peer_id_t *propagation_source,
    const uint8_t *message_id,
    size_t message_id_len) {
    if (!topic || !message_id || message_id_len == 0) {
        return NULL;
    }

    struct lantern_gossipsub_validation_job *job = calloc(1, sizeof(*job));
    if (!job) {
        return NULL;
    }
    job->kind = kind;
    job->topic = strdup(topic);
    if (!job->topic) {
        lantern_gossipsub_validation_job_free(job);
        return NULL;
    }
    if (payload && payload_len > 0) {
        job->payload = malloc(payload_len);
        if (!job->payload) {
            lantern_gossipsub_validation_job_free(job);
            return NULL;
        }
        memcpy(job->payload, payload, payload_len);
        job->payload_len = payload_len;
    }
    if (propagation_source) {
        if (peer_id_clone(propagation_source, &job->propagation_source) != PEER_ID_OK || !job->propagation_source) {
            lantern_gossipsub_validation_job_free(job);
            return NULL;
        }
    }
    job->message_id = malloc(message_id_len);
    if (!job->message_id) {
        lantern_gossipsub_validation_job_free(job);
        return NULL;
    }
    memcpy(job->message_id, message_id, message_id_len);
    job->message_id_len = message_id_len;
    return job;
}

static void *lantern_gossipsub_validation_worker_main(void *user_data) {
    struct lantern_gossipsub_validation_pool *pool = (struct lantern_gossipsub_validation_pool *)user_data;
    if (!pool) {
        return NULL;
    }

    for (;;) {
        pthread_mutex_lock(&pool->mutex);
        while (!pool->stopping && pool->queue_len == 0) {
            pthread_cond_wait(&pool->not_empty, &pool->mutex);
        }
        if (pool->stopping && pool->queue_len == 0) {
            pthread_mutex_unlock(&pool->mutex);
            break;
        }

        struct lantern_gossipsub_validation_job *job = pool->queue[pool->queue_head];
        pool->queue[pool->queue_head] = NULL;
        pool->queue_head = (pool->queue_head + 1u) % pool->queue_capacity;
        pool->queue_len--;
        pthread_mutex_unlock(&pool->mutex);

        if (!job) {
            continue;
        }

        libp2p_gossipsub_validation_result_t result = lantern_gossipsub_validation_job_run(pool->service, job);
        if (pool->service && pool->service->gossipsub) {
            (void)libp2p_gossipsub_report_message_validation_result(
                pool->service->gossipsub,
                job->message_id,
                job->message_id_len,
                result);
        }
        lantern_gossipsub_validation_job_free(job);
    }

    return NULL;
}

static int lantern_gossipsub_validation_pool_start(struct lantern_gossipsub_service *service) {
    if (!service) {
        return -1;
    }
    if (service->validation_pool) {
        return 0;
    }

    struct lantern_gossipsub_validation_pool *pool = calloc(1, sizeof(*pool));
    if (!pool) {
        return -1;
    }
    pool->service = service;
    pool->worker_count = LANTERN_GOSSIPSUB_VALIDATION_WORKER_COUNT;
    pool->queue_capacity = LANTERN_GOSSIPSUB_VALIDATION_QUEUE_CAPACITY;
    pool->threads = calloc(pool->worker_count, sizeof(*pool->threads));
    pool->queue = calloc(pool->queue_capacity, sizeof(*pool->queue));
    if (!pool->threads || !pool->queue) {
        free(pool->threads);
        free(pool->queue);
        free(pool);
        return -1;
    }
    if (pthread_mutex_init(&pool->mutex, NULL) != 0) {
        free(pool->threads);
        free(pool->queue);
        free(pool);
        return -1;
    }
    if (pthread_cond_init(&pool->not_empty, NULL) != 0) {
        pthread_mutex_destroy(&pool->mutex);
        free(pool->threads);
        free(pool->queue);
        free(pool);
        return -1;
    }

    size_t started = 0;
    for (; started < pool->worker_count; ++started) {
        if (pthread_create(&pool->threads[started], NULL, lantern_gossipsub_validation_worker_main, pool) != 0) {
            pool->stopping = 1;
            pthread_cond_broadcast(&pool->not_empty);
            for (size_t i = 0; i < started; ++i) {
                pthread_join(pool->threads[i], NULL);
            }
            pthread_cond_destroy(&pool->not_empty);
            pthread_mutex_destroy(&pool->mutex);
            free(pool->threads);
            free(pool->queue);
            free(pool);
            return -1;
        }
    }

    pool->started = 1;
    service->validation_pool = pool;
    return 0;
}

static void lantern_gossipsub_validation_pool_stop(struct lantern_gossipsub_service *service) {
    if (!service || !service->validation_pool) {
        return;
    }

    struct lantern_gossipsub_validation_pool *pool = service->validation_pool;
    service->validation_pool = NULL;

    pthread_mutex_lock(&pool->mutex);
    pool->stopping = 1;
    pthread_cond_broadcast(&pool->not_empty);
    while (pool->queue_len > 0) {
        struct lantern_gossipsub_validation_job *job = pool->queue[pool->queue_head];
        pool->queue[pool->queue_head] = NULL;
        pool->queue_head = (pool->queue_head + 1u) % pool->queue_capacity;
        pool->queue_len--;
        pthread_mutex_unlock(&pool->mutex);

        if (job) {
            if (service->gossipsub) {
                (void)libp2p_gossipsub_report_message_validation_result(
                    service->gossipsub,
                    job->message_id,
                    job->message_id_len,
                    LIBP2P_GOSSIPSUB_VALIDATION_IGNORE);
            }
            lantern_gossipsub_validation_job_free(job);
        }

        pthread_mutex_lock(&pool->mutex);
    }
    pthread_mutex_unlock(&pool->mutex);

    if (pool->started) {
        for (size_t i = 0; i < pool->worker_count; ++i) {
            pthread_join(pool->threads[i], NULL);
        }
    }

    pthread_cond_destroy(&pool->not_empty);
    pthread_mutex_destroy(&pool->mutex);
    free(pool->threads);
    free(pool->queue);
    free(pool);
}

static int lantern_gossipsub_validation_pool_try_enqueue(
    struct lantern_gossipsub_service *service,
    struct lantern_gossipsub_validation_job *job) {
    if (!service || !service->validation_pool || !job) {
        return -1;
    }

    struct lantern_gossipsub_validation_pool *pool = service->validation_pool;
    pthread_mutex_lock(&pool->mutex);
    if (pool->stopping || pool->queue_len >= pool->queue_capacity) {
        pthread_mutex_unlock(&pool->mutex);
        return -1;
    }

    size_t idx = (pool->queue_head + pool->queue_len) % pool->queue_capacity;
    pool->queue[idx] = job;
    pool->queue_len++;
    pthread_cond_signal(&pool->not_empty);
    pthread_mutex_unlock(&pool->mutex);
    return 0;
}

static void lantern_gossipsub_message_delivery_cb(
    libp2p_gossipsub_t *gs,
    const libp2p_gossipsub_message_t *msg,
    const uint8_t *message_id,
    size_t message_id_len,
    const peer_id_t *propagation_source,
    void *user_data) {
    struct lantern_gossipsub_service *service = (struct lantern_gossipsub_service *)user_data;
    if (!service || !gs || !msg || !msg->topic.topic || !message_id || message_id_len == 0) {
        return;
    }

    enum lantern_gossipsub_validation_job_kind kind = lantern_gossipsub_classify_topic(service, msg->topic.topic);
    int handler_missing = 0;
    switch (kind) {
    case LANTERN_GOSSIPSUB_JOB_BLOCK:
        handler_missing = service->block_handler == NULL;
        break;
    case LANTERN_GOSSIPSUB_JOB_VOTE:
        handler_missing = service->vote_handler == NULL;
        break;
    case LANTERN_GOSSIPSUB_JOB_AGGREGATED_ATTESTATION:
        handler_missing = service->aggregated_attestation_handler == NULL;
        break;
    default:
        handler_missing = 1;
        break;
    }

    if (handler_missing || !msg->data || msg->data_len == 0) {
        (void)libp2p_gossipsub_report_message_validation_result(
            gs,
            message_id,
            message_id_len,
            LIBP2P_GOSSIPSUB_VALIDATION_ACCEPT);
        return;
    }

    struct lantern_gossipsub_validation_job *job = lantern_gossipsub_validation_job_new(
        kind,
        msg->topic.topic,
        msg->data,
        msg->data_len,
        propagation_source,
        message_id,
        message_id_len);
    if (!job) {
        lantern_log_warn(
            "gossip",
            NULL,
            "failed to allocate gossip validation job topic=%s bytes=%zu; ignoring message",
            msg->topic.topic,
            msg->data_len);
        (void)libp2p_gossipsub_report_message_validation_result(
            gs,
            message_id,
            message_id_len,
            LIBP2P_GOSSIPSUB_VALIDATION_IGNORE);
        return;
    }

    if (lantern_gossipsub_validation_pool_try_enqueue(service, job) != 0) {
        lantern_log_warn(
            "gossip",
            NULL,
            "gossip validation queue full or stopping topic=%s bytes=%zu; ignoring message",
            msg->topic.topic,
            msg->data_len);
        lantern_gossipsub_validation_job_free(job);
        (void)libp2p_gossipsub_report_message_validation_result(
            gs,
            message_id,
            message_id_len,
            LIBP2P_GOSSIPSUB_VALIDATION_IGNORE);
    }
}

void lantern_gossipsub_service_init(struct lantern_gossipsub_service *service) {
    if (!service) {
        return;
    }
    memset(service, 0, sizeof(*service));
}

static void lantern_gossipsub_service_remove_validators(struct lantern_gossipsub_service *service) {
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
        for (size_t i = 0; i < service->extra_vote_subnet_topic_count; ++i) {
            if (service->extra_vote_subnet_validator_handles
                && service->extra_vote_subnet_validator_handles[i]) {
                (void)libp2p_gossipsub_remove_validator(
                    service->gossipsub,
                    service->extra_vote_subnet_validator_handles[i]);
            }
        }
    }
    service->block_validator_handle = NULL;
    service->vote_validator_handle = NULL;
    service->vote_subnet_validator_handle = NULL;
    service->aggregated_attestation_validator_handle = NULL;
    if (service->extra_vote_subnet_validator_handles) {
        memset(
            service->extra_vote_subnet_validator_handles,
            0,
            service->extra_vote_subnet_topic_count * sizeof(*service->extra_vote_subnet_validator_handles));
    }
}

void lantern_gossipsub_service_stop(struct lantern_gossipsub_service *service) {
    if (!service) {
        return;
    }
    if (service->gossipsub) {
        (void)libp2p_gossipsub_set_message_delivery_callback(service->gossipsub, NULL, NULL);
    }
    lantern_gossipsub_validation_pool_stop(service);
    lantern_gossipsub_service_remove_validators(service);
    if (service->gossipsub) {
        libp2p_gossipsub_stop(service->gossipsub);
    }
}

void lantern_gossipsub_service_reset(struct lantern_gossipsub_service *service) {
    if (!service) {
        return;
    }
    lantern_gossipsub_service_stop(service);
    if (service->gossipsub) {
        libp2p_gossipsub_free(service->gossipsub);
        service->gossipsub = NULL;
    }
    memset(service->block_topic, 0, sizeof(service->block_topic));
    memset(service->vote_topic, 0, sizeof(service->vote_topic));
    memset(service->vote_subnet_topic, 0, sizeof(service->vote_subnet_topic));
    memset(service->aggregated_attestation_topic, 0, sizeof(service->aggregated_attestation_topic));
    service->data_dir = NULL;
    service->devnet = NULL;
    service->attestation_subnet_id = 0;
    service->subscribe_attestation_subnet = 0;
    service->publish_hook = NULL;
    service->publish_hook_user_data = NULL;
    service->loopback_only = 0;
    free(service->extra_vote_subnet_topics);
    service->extra_vote_subnet_topics = NULL;
    free(service->extra_vote_subnet_validator_handles);
    service->extra_vote_subnet_validator_handles = NULL;
    service->extra_vote_subnet_topic_count = 0;
    service->validation_pool = NULL;
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
    service->devnet = config->devnet;
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
    if (lantern_gossipsub_validation_pool_start(service) != 0) {
        lantern_gossipsub_service_reset(service);
        return -1;
    }
    if (libp2p_gossipsub_set_message_delivery_callback(
            service->gossipsub,
            lantern_gossipsub_message_delivery_cb,
            service)
        != LIBP2P_ERR_OK) {
        lantern_gossipsub_service_reset(service);
        return -1;
    }
    if (subscribe_topic(service, service->block_topic) != 0) {
        lantern_gossipsub_service_reset(service);
        return -1;
    }
    lantern_log_info(
        "gossip",
        &(const struct lantern_log_metadata){.peer = config->devnet},
        "subscribed gossipsub topic=%s",
        service->block_topic);
    if (!service->subscribe_attestation_subnet) {
        if (subscribe_topic(service, service->vote_topic) != 0) {
            lantern_gossipsub_service_reset(service);
            return -1;
        }
        lantern_log_info(
            "gossip",
            &(const struct lantern_log_metadata){.peer = config->devnet},
            "subscribed gossipsub topic=%s",
            service->vote_topic);
    }
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
    const LanternSignedVote *vote,
    size_t subnet_id) {
    if (!service || !vote) {
        return -1;
    }
    char topic[LANTERN_GOSSIPSUB_TOPIC_CAP];
    const char *publish_topic = NULL;
    if (service->devnet
        && lantern_gossip_topic_format_subnet(
            LANTERN_GOSSIP_TOPIC_VOTE_SUBNET,
            service->devnet,
            subnet_id,
            topic,
            sizeof(topic))
        == 0) {
        publish_topic = topic;
    } else if (service->vote_subnet_topic[0] != '\0'
        && service->attestation_subnet_id == subnet_id) {
        publish_topic = service->vote_subnet_topic;
    } else {
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
    int publish_rc = publish_payload(service, publish_topic, compressed, written);
    free(compressed);
    return publish_rc;
}

int lantern_gossipsub_service_subscribe_attestation_subnet(
    struct lantern_gossipsub_service *service,
    size_t subnet_id) {
    if (!service || !service->gossipsub || !service->devnet) {
        return -1;
    }

    char topic[LANTERN_GOSSIPSUB_TOPIC_CAP];
    if (lantern_gossip_topic_format_subnet(
            LANTERN_GOSSIP_TOPIC_VOTE_SUBNET,
            service->devnet,
            subnet_id,
            topic,
            sizeof(topic))
        != 0) {
        return -1;
    }

    if (service->vote_subnet_topic[0] != '\0' && strcmp(topic, service->vote_subnet_topic) == 0) {
        return 0;
    }
    for (size_t i = 0; i < service->extra_vote_subnet_topic_count; ++i) {
        if (strcmp(topic, service->extra_vote_subnet_topics[i]) == 0) {
            return 0;
        }
    }

    if (subscribe_topic(service, topic) != 0) {
        return -1;
    }
    lantern_log_info(
        "gossip",
        &(const struct lantern_log_metadata){.peer = service->devnet},
        "subscribed gossipsub topic=%s",
        topic);

    size_t new_count = service->extra_vote_subnet_topic_count + 1u;
    char (*new_topics)[LANTERN_GOSSIPSUB_TOPIC_CAP] =
        calloc(new_count, sizeof(*new_topics));
    libp2p_gossipsub_validator_handle_t **new_handles =
        calloc(new_count, sizeof(*new_handles));
    if (!new_topics || !new_handles) {
        free(new_topics);
        free(new_handles);
        (void)libp2p_gossipsub_unsubscribe(service->gossipsub, topic);
        return -1;
    }
    if (service->extra_vote_subnet_topic_count > 0) {
        memcpy(
            new_topics,
            service->extra_vote_subnet_topics,
            service->extra_vote_subnet_topic_count * sizeof(*new_topics));
        memcpy(
            new_handles,
            service->extra_vote_subnet_validator_handles,
            service->extra_vote_subnet_topic_count * sizeof(*new_handles));
    }
    memcpy(new_topics[service->extra_vote_subnet_topic_count], topic, sizeof(topic));
    new_handles[service->extra_vote_subnet_topic_count] = NULL;

    free(service->extra_vote_subnet_topics);
    free(service->extra_vote_subnet_validator_handles);
    service->extra_vote_subnet_topics = new_topics;
    service->extra_vote_subnet_validator_handles = new_handles;
    service->extra_vote_subnet_topic_count = new_count;
    return 0;
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
