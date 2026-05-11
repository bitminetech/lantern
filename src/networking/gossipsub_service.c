#include "lantern/networking/gossipsub_service.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "lantern/encoding/snappy.h"
#include "lantern/networking/gossip.h"
#include "lantern/networking/gossip_payloads.h"
#include "lantern/support/log.h"

#define LANTERN_GOSSIP_ENCODE_BUFFER_BYTES (16u * 1024u * 1024u)

static int topic_eq(const libp2p_gossipsub_bytes_t topic, const char *expected) {
    return expected && strlen(expected) == topic.len && memcmp(topic.data, expected, topic.len) == 0;
}

static libp2p_gossipsub_err_t lantern_gossipsub_message_id(
    const libp2p_gossipsub_message_t *message,
    uint8_t *out,
    size_t out_len,
    size_t *written,
    void *user_data) {
    (void)user_data;
    if (!message || !written) {
        return LIBP2P_GOSSIPSUB_ERR_INVALID_ARG;
    }
    *written = LANTERN_GOSSIP_MESSAGE_ID_SIZE;
    if (!out || out_len < LANTERN_GOSSIP_MESSAGE_ID_SIZE) {
        return LIBP2P_GOSSIPSUB_ERR_BUF_TOO_SMALL;
    }

    LanternGossipMessageId id;
    uint8_t stack_scratch[4096];
    size_t required = 0;
    int rc = lantern_gossip_compute_message_id(
        &id,
        message->topic.data,
        message->topic.len,
        message->data.data,
        message->data.len,
        stack_scratch,
        sizeof(stack_scratch),
        &required);
    if (rc != 0 && required > sizeof(stack_scratch)) {
        uint8_t *scratch = (uint8_t *)malloc(required);
        if (!scratch) {
            return LIBP2P_GOSSIPSUB_ERR_INTERNAL;
        }
        rc = lantern_gossip_compute_message_id(
            &id,
            message->topic.data,
            message->topic.len,
            message->data.data,
            message->data.len,
            scratch,
            required,
            NULL);
        free(scratch);
    }
    if (rc != 0) {
        return LIBP2P_GOSSIPSUB_ERR_INTERNAL;
    }
    memcpy(out, id.bytes, LANTERN_GOSSIP_MESSAGE_ID_SIZE);
    return LIBP2P_GOSSIPSUB_OK;
}

static int encode_payload_block(const LanternSignedBlock *block, uint8_t **out, size_t *out_len) {
    if (!block || !out || !out_len) {
        return -1;
    }
    uint8_t *buffer = (uint8_t *)malloc(LANTERN_GOSSIP_ENCODE_BUFFER_BYTES);
    if (!buffer) {
        return -1;
    }
    size_t written = 0;
    if (lantern_gossip_encode_signed_block_snappy(
            block,
            buffer,
            LANTERN_GOSSIP_ENCODE_BUFFER_BYTES,
            &written)
        != 0) {
        free(buffer);
        return -1;
    }
    *out = buffer;
    *out_len = written;
    return 0;
}

static int encode_payload_vote(const LanternSignedVote *vote, uint8_t **out, size_t *out_len) {
    if (!vote || !out || !out_len) {
        return -1;
    }
    uint8_t *buffer = (uint8_t *)malloc(LANTERN_GOSSIP_ENCODE_BUFFER_BYTES);
    if (!buffer) {
        return -1;
    }
    size_t written = 0;
    if (lantern_gossip_encode_signed_vote_snappy(
            vote,
            buffer,
            LANTERN_GOSSIP_ENCODE_BUFFER_BYTES,
            &written)
        != 0) {
        free(buffer);
        return -1;
    }
    *out = buffer;
    *out_len = written;
    return 0;
}

static int encode_payload_aggregated_attestation(
    const LanternSignedAggregatedAttestation *attestation,
    uint8_t **out,
    size_t *out_len) {
    if (!attestation || !out || !out_len) {
        return -1;
    }
    uint8_t *buffer = (uint8_t *)malloc(LANTERN_GOSSIP_ENCODE_BUFFER_BYTES);
    if (!buffer) {
        return -1;
    }
    size_t written = 0;
    if (lantern_gossip_encode_signed_aggregated_attestation_snappy(
            attestation,
            buffer,
            LANTERN_GOSSIP_ENCODE_BUFFER_BYTES,
            &written)
        != 0) {
        free(buffer);
        return -1;
    }
    *out = buffer;
    *out_len = written;
    return 0;
}

static int deliver_message(
    struct lantern_gossipsub_service *service,
    const libp2p_gossipsub_event_t *event) {
    struct lantern_peer_id peer = {0};
    if (event->peer.len <= sizeof(peer.bytes)) {
        memcpy(peer.bytes, event->peer.data, event->peer.len);
        peer.len = event->peer.len;
    }

    if (topic_eq(event->topic, service->block_topic)) {
        LanternSignedBlock block;
        lantern_signed_block_init(&block);
        uint8_t *raw = NULL;
        size_t raw_len = 0;
        int rc = lantern_gossip_decode_signed_block_snappy(
            &block,
            event->message.data.data,
            event->message.data.len,
            &raw,
            &raw_len);
        if (rc == 0 && service->block_handler) {
            rc = service->block_handler(
                &block,
                &peer,
                raw,
                raw_len,
                service->block_handler_user_data);
        }
        free(raw);
        lantern_signed_block_reset(&block);
        return rc;
    }

    if (topic_eq(event->topic, service->vote_topic) || topic_eq(event->topic, service->vote_subnet_topic)) {
        LanternSignedVote vote;
        memset(&vote, 0, sizeof(vote));
        int rc = lantern_gossip_decode_signed_vote_snappy(&vote, event->message.data.data, event->message.data.len);
        if (rc == 0 && service->vote_handler) {
            rc = service->vote_handler(
                &vote,
                &peer,
                event->message.data.data,
                event->message.data.len,
                service->vote_handler_user_data);
        }
        return rc;
    }

    if (topic_eq(event->topic, service->aggregated_attestation_topic)) {
        LanternSignedAggregatedAttestation attestation;
        lantern_signed_aggregated_attestation_init(&attestation);
        int rc = lantern_gossip_decode_signed_aggregated_attestation_snappy(
            &attestation,
            event->message.data.data,
            event->message.data.len);
        if (rc == 0 && service->aggregated_attestation_handler) {
            rc = service->aggregated_attestation_handler(
                &attestation,
                &peer,
                event->message.data.data,
                event->message.data.len,
                service->aggregated_attestation_handler_user_data);
        }
        lantern_signed_aggregated_attestation_reset(&attestation);
        return rc;
    }

    return -1;
}

static void drain_gossipsub_events(struct lantern_gossipsub_service *service) {
    libp2p_gossipsub_event_t event;
    while (libp2p_gossipsub_next_event(service->gossipsub, &event) == LIBP2P_GOSSIPSUB_OK) {
        if (event.type == LIBP2P_GOSSIPSUB_EVENT_MESSAGE) {
            int ok = deliver_message(service, &event) == 0;
            if (event.validation) {
                (void)libp2p_gossipsub_report_validation(
                    service->gossipsub,
                    event.validation,
                    ok ? LIBP2P_GOSSIPSUB_VALIDATION_ACCEPT : LIBP2P_GOSSIPSUB_VALIDATION_REJECT);
            }
        } else if (event.type == LIBP2P_GOSSIPSUB_EVENT_DROPPED || event.type == LIBP2P_GOSSIPSUB_EVENT_ERROR) {
            lantern_log_debug("gossip", NULL, "gossipsub event type=%d reason=%d", (int)event.type, (int)event.reason);
        }
    }
}

static void gossipsub_host_event(
    struct lantern_libp2p_host *network,
    const libp2p_host_event_t *event,
    void *user_data) {
    struct lantern_gossipsub_service *service = (struct lantern_gossipsub_service *)user_data;
    if (!service || !service->gossipsub || !network || !network->host || !event) {
        return;
    }
    if (event->type == LIBP2P_HOST_EVENT_CONN_ESTABLISHED && event->conn) {
        libp2p_host_stream_open_t *open = NULL;
        (void)libp2p_gossipsub_open_peer(
            service->gossipsub,
            network->host,
            event->conn,
            LIBP2P_GOSSIPSUB_VERSION_NONE,
            NULL,
            &open);
    }
    (void)libp2p_gossipsub_handle_host_event(service->gossipsub, network->host, event);
}

static void gossipsub_drive(
    struct lantern_libp2p_host *network,
    libp2p_host_time_us_t now_us,
    void *user_data) {
    struct lantern_gossipsub_service *service = (struct lantern_gossipsub_service *)user_data;
    if (!service || !service->gossipsub || !network || !network->host) {
        return;
    }
    (void)libp2p_gossipsub_drive(service->gossipsub, network->host, now_us, NULL);
    drain_gossipsub_events(service);
}

static int subscribe_topic(struct lantern_gossipsub_service *service, const char *topic) {
    libp2p_gossipsub_topic_config_t topic_config = {
        .topic = {.data = (const uint8_t *)topic, .len = strlen(topic)},
        .validation_mode = LIBP2P_GOSSIPSUB_VALIDATION_REQUIRE_APP,
        .enable_idontwant = 1,
        .idontwant_min_message_bytes = LIBP2P_GOSSIPSUB_DEFAULT_IDONTWANT_MIN_BYTES,
    };
    return libp2p_gossipsub_subscribe(service->gossipsub, &topic_config) == LIBP2P_GOSSIPSUB_OK ? 0 : -1;
}

static int setup_topics(struct lantern_gossipsub_service *service, const struct lantern_gossipsub_config *config) {
    snprintf(service->topic_network_name, sizeof(service->topic_network_name), "%s", config->topic_network_name);
    memcpy(service->fork_digest, config->fork_digest, sizeof(service->fork_digest));
    service->attestation_subnet_id = config->attestation_subnet_id;
    service->subscribe_attestation_subnet = config->subscribe_attestation_subnet ? 1 : 0;
    return lantern_gossip_topic_format(
               LANTERN_GOSSIP_TOPIC_BLOCK,
               service->topic_network_name,
               service->block_topic,
               sizeof(service->block_topic)) == 0 &&
            lantern_gossip_topic_format(
               LANTERN_GOSSIP_TOPIC_VOTE,
               service->topic_network_name,
               service->vote_topic,
               sizeof(service->vote_topic)) == 0 &&
            lantern_gossip_topic_format_subnet(
               LANTERN_GOSSIP_TOPIC_VOTE_SUBNET,
               service->topic_network_name,
               service->attestation_subnet_id,
               service->vote_subnet_topic,
               sizeof(service->vote_subnet_topic)) == 0 &&
            lantern_gossip_topic_format(
               LANTERN_GOSSIP_TOPIC_AGGREGATED_ATTESTATION,
               service->topic_network_name,
               service->aggregated_attestation_topic,
               sizeof(service->aggregated_attestation_topic)) == 0
        ? 0
        : -1;
}

void lantern_gossipsub_service_init(struct lantern_gossipsub_service *service) {
    if (service) {
        memset(service, 0, sizeof(*service));
    }
}

void lantern_gossipsub_service_stop(struct lantern_gossipsub_service *service) {
    if (!service || !service->gossipsub) {
        return;
    }
    if (service->network && service->network->host) {
        (void)libp2p_gossipsub_close(service->gossipsub, service->network->host, 0);
    }
}

void lantern_gossipsub_service_reset(struct lantern_gossipsub_service *service) {
    if (!service) {
        return;
    }
    lantern_gossipsub_service_stop(service);
    if (service->gossipsub) {
        libp2p_gossipsub_deinit(service->gossipsub);
    }
    free(service->gossipsub_storage);
    free(service->extra_vote_subnet_topics);

    int (*publish_hook)(const char *, const uint8_t *, size_t, void *) = service->publish_hook;
    void *publish_user_data = service->publish_hook_user_data;
    int loopback_only = service->loopback_only;
    lantern_gossipsub_block_handler block_handler = service->block_handler;
    void *block_user_data = service->block_handler_user_data;
    lantern_gossipsub_vote_handler vote_handler = service->vote_handler;
    void *vote_user_data = service->vote_handler_user_data;
    lantern_gossipsub_aggregated_attestation_handler aggregate_handler = service->aggregated_attestation_handler;
    void *aggregate_user_data = service->aggregated_attestation_handler_user_data;

    memset(service, 0, sizeof(*service));
    service->publish_hook = publish_hook;
    service->publish_hook_user_data = publish_user_data;
    service->loopback_only = loopback_only;
    service->block_handler = block_handler;
    service->block_handler_user_data = block_user_data;
    service->vote_handler = vote_handler;
    service->vote_handler_user_data = vote_user_data;
    service->aggregated_attestation_handler = aggregate_handler;
    service->aggregated_attestation_handler_user_data = aggregate_user_data;
}

int lantern_gossipsub_service_start(
    struct lantern_gossipsub_service *service,
    const struct lantern_gossipsub_config *config) {
    if (!service || !config || !config->topic_network_name) {
        return -1;
    }

    lantern_gossipsub_service_reset(service);
    service->network = config->network;
    service->data_dir = config->data_dir;
    service->devnet = config->devnet;
    if (setup_topics(service, config) != 0) {
        return -1;
    }
    if (service->loopback_only || !service->network || !service->network->host) {
        return 0;
    }

    libp2p_gossipsub_config_t gs_config;
    if (libp2p_gossipsub_config_default(&gs_config) != LIBP2P_GOSSIPSUB_OK) {
        return -1;
    }
    gs_config.random_fn = lantern_libp2p_gossipsub_random;
    gs_config.message_id_fn = lantern_gossipsub_message_id;
    gs_config.mesh.enable_flood_publish = 1;
    gs_config.mesh.seen_ttl_us = 120000000ull;
    gs_config.protocol_mask = LIBP2P_GOSSIPSUB_PROTOCOL_MASK_ALL;
    gs_config.preferred_protocol = LIBP2P_GOSSIPSUB_VERSION_12;

    if (libp2p_gossipsub_storage_size(&gs_config, &service->gossipsub_storage_len) !=
        LIBP2P_GOSSIPSUB_OK) {
        return -1;
    }
    service->gossipsub_storage = calloc(1u, service->gossipsub_storage_len);
    if (!service->gossipsub_storage) {
        return -1;
    }
    if (libp2p_gossipsub_init(
            service->gossipsub_storage,
            service->gossipsub_storage_len,
            &gs_config,
            &service->gossipsub)
        != LIBP2P_GOSSIPSUB_OK) {
        return -1;
    }
    if (libp2p_gossipsub_protocols(
            service->gossipsub,
            service->gossipsub_protocols,
            LIBP2P_GOSSIPSUB_PROTOCOL_COUNT,
            &service->gossipsub_protocol_count)
        != LIBP2P_GOSSIPSUB_OK) {
        return -1;
    }
    for (size_t i = 0; i < service->gossipsub_protocol_count; i++) {
        if (lantern_libp2p_host_register_protocol(service->network, &service->gossipsub_protocols[i]) != 0) {
            return -1;
        }
    }
    if (subscribe_topic(service, service->block_topic) != 0) {
        return -1;
    }
    if (service->subscribe_attestation_subnet) {
        if (subscribe_topic(service, service->vote_subnet_topic) != 0) {
            return -1;
        }
    } else if (subscribe_topic(service, service->vote_topic) != 0) {
        return -1;
    }
    if (subscribe_topic(service, service->aggregated_attestation_topic) != 0) {
        return -1;
    }
    if (libp2p_gossipsub_start(service->gossipsub, service->network->host, lantern_libp2p_now_us()) !=
        LIBP2P_GOSSIPSUB_OK) {
        return -1;
    }
    if (lantern_libp2p_host_register_event_handler(service->network, gossipsub_host_event, service) != 0 ||
        lantern_libp2p_host_register_drive_handler(service->network, gossipsub_drive, service) != 0) {
        return -1;
    }

    lantern_log_info("network", &(const struct lantern_log_metadata){.peer = config->devnet}, "gossipsub topics ready");
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
    if (service->publish_hook &&
        service->publish_hook(topic, payload, payload_len, service->publish_hook_user_data) != 0) {
        return -1;
    }
    if (service->loopback_only) {
        return 0;
    }
    if (!service->gossipsub) {
        return -1;
    }
    libp2p_gossipsub_publish_t publish = {
        .topic = {.data = (const uint8_t *)topic, .len = strlen(topic)},
        .data = {.data = payload, .len = payload_len},
        .message_id = {.data = NULL, .len = 0},
        .user_data = NULL,
    };
    return libp2p_gossipsub_publish(service->gossipsub, &publish, NULL, 0, NULL) == LIBP2P_GOSSIPSUB_OK
        ? 0
        : -1;
}

int lantern_gossipsub_service_publish_block(
    struct lantern_gossipsub_service *service,
    const LanternSignedBlock *block) {
    if (!service || !block || service->block_topic[0] == '\0') {
        return -1;
    }
    uint8_t *payload = NULL;
    size_t payload_len = 0;
    int rc = encode_payload_block(block, &payload, &payload_len);
    if (rc == 0) {
        rc = publish_payload(service, service->block_topic, payload, payload_len);
    }
    free(payload);
    return rc;
}

int lantern_gossipsub_service_publish_vote_subnet(
    struct lantern_gossipsub_service *service,
    const LanternSignedVote *vote,
    size_t subnet_id) {
    if (!service || !vote) {
        return -1;
    }
    char topic[128];
    const char *publish_topic = service->vote_topic;
    if (subnet_id != service->attestation_subnet_id || service->vote_subnet_topic[0] == '\0') {
        if (lantern_gossip_topic_format_subnet(
                LANTERN_GOSSIP_TOPIC_VOTE_SUBNET,
                service->topic_network_name,
                subnet_id,
                topic,
                sizeof(topic))
            != 0) {
            return -1;
        }
        publish_topic = topic;
    } else if (service->subscribe_attestation_subnet) {
        publish_topic = service->vote_subnet_topic;
    }
    uint8_t *payload = NULL;
    size_t payload_len = 0;
    int rc = encode_payload_vote(vote, &payload, &payload_len);
    if (rc == 0) {
        rc = publish_payload(service, publish_topic, payload, payload_len);
    }
    free(payload);
    return rc;
}

int lantern_gossipsub_service_publish_aggregated_attestation(
    struct lantern_gossipsub_service *service,
    const LanternSignedAggregatedAttestation *attestation) {
    if (!service || !attestation || service->aggregated_attestation_topic[0] == '\0') {
        return -1;
    }
    uint8_t *payload = NULL;
    size_t payload_len = 0;
    int rc = encode_payload_aggregated_attestation(attestation, &payload, &payload_len);
    if (rc == 0) {
        rc = publish_payload(service, service->aggregated_attestation_topic, payload, payload_len);
    }
    free(payload);
    return rc;
}

int lantern_gossipsub_service_subscribe_attestation_subnet(
    struct lantern_gossipsub_service *service,
    size_t subnet_id) {
    if (!service) {
        return -1;
    }
    char topic[128];
    if (lantern_gossip_topic_format_subnet(
            LANTERN_GOSSIP_TOPIC_VOTE_SUBNET,
            service->topic_network_name,
            subnet_id,
            topic,
            sizeof(topic))
        != 0) {
        return -1;
    }
    if (service->gossipsub && !service->loopback_only) {
        libp2p_gossipsub_topic_config_t topic_config = {
            .topic = {.data = (const uint8_t *)topic, .len = strlen(topic)},
            .validation_mode = LIBP2P_GOSSIPSUB_VALIDATION_REQUIRE_APP,
            .enable_idontwant = 1,
            .idontwant_min_message_bytes = LIBP2P_GOSSIPSUB_DEFAULT_IDONTWANT_MIN_BYTES,
        };
        if (libp2p_gossipsub_subscribe(service->gossipsub, &topic_config) != LIBP2P_GOSSIPSUB_OK) {
            return -1;
        }
    }
    if (subnet_id == service->attestation_subnet_id) {
        snprintf(service->vote_subnet_topic, sizeof(service->vote_subnet_topic), "%s", topic);
    }
    return 0;
}

size_t lantern_gossipsub_service_mesh_peer_count(const struct lantern_gossipsub_service *service) {
    (void)service;
    return 0;
}

void lantern_gossipsub_service_set_publish_hook(
    struct lantern_gossipsub_service *service,
    int (*hook)(const char *topic, const uint8_t *payload, size_t payload_len, void *user_data),
    void *user_data) {
    if (service) {
        service->publish_hook = hook;
        service->publish_hook_user_data = user_data;
    }
}

void lantern_gossipsub_service_set_loopback_only(
    struct lantern_gossipsub_service *service,
    int loopback_only) {
    if (service) {
        service->loopback_only = loopback_only ? 1 : 0;
    }
}

void lantern_gossipsub_service_set_block_handler(
    struct lantern_gossipsub_service *service,
    lantern_gossipsub_block_handler handler,
    void *user_data) {
    if (service) {
        service->block_handler = handler;
        service->block_handler_user_data = user_data;
    }
}

void lantern_gossipsub_service_set_vote_handler(
    struct lantern_gossipsub_service *service,
    lantern_gossipsub_vote_handler handler,
    void *user_data) {
    if (service) {
        service->vote_handler = handler;
        service->vote_handler_user_data = user_data;
    }
}

void lantern_gossipsub_service_set_aggregated_attestation_handler(
    struct lantern_gossipsub_service *service,
    lantern_gossipsub_aggregated_attestation_handler handler,
    void *user_data) {
    if (service) {
        service->aggregated_attestation_handler = handler;
        service->aggregated_attestation_handler_user_data = user_data;
    }
}
