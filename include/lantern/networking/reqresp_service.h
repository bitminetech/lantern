#ifndef LANTERN_NETWORKING_REQRESP_SERVICE_H
#define LANTERN_NETWORKING_REQRESP_SERVICE_H

#include <pthread.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "lantern/networking/libp2p.h"
#include "lantern/networking/messages.h"

#define LANTERN_REQRESP_STATUS_PROTOCOL_SNAPPY "/leanconsensus/req/status/1/ssz_snappy"
#define LANTERN_REQRESP_BLOCKS_BY_ROOT_PROTOCOL_SNAPPY "/leanconsensus/req/blocks_by_root/1/ssz_snappy"
#define LANTERN_REQRESP_BLOCKS_BY_RANGE_PROTOCOL_SNAPPY "/leanconsensus/req/blocks_by_range/1/ssz_snappy"
#define LANTERN_REQRESP_STATUS_PROTOCOL LANTERN_REQRESP_STATUS_PROTOCOL_SNAPPY
#define LANTERN_REQRESP_BLOCKS_BY_ROOT_PROTOCOL LANTERN_REQRESP_BLOCKS_BY_ROOT_PROTOCOL_SNAPPY
#define LANTERN_REQRESP_BLOCKS_BY_RANGE_PROTOCOL LANTERN_REQRESP_BLOCKS_BY_RANGE_PROTOCOL_SNAPPY
#define LANTERN_REQRESP_MAX_CHUNK_BYTES (10u * 1024u * 1024u)
#define LANTERN_REQRESP_MAX_ERROR_MESSAGE_SIZE 256u
#define LANTERN_MIN_SLOTS_FOR_BLOCK_REQUESTS 3600u
#define LANTERN_REQRESP_RESPONSE_SUCCESS 0u
#define LANTERN_REQRESP_RESPONSE_INVALID_REQUEST 1u
#define LANTERN_REQRESP_RESPONSE_SERVER_ERROR 2u
#define LANTERN_REQRESP_RESPONSE_RESOURCE_UNAVAILABLE 3u

enum
{
    LANTERN_REQRESP_ERR_STREAM_READ = -1003,
    LANTERN_REQRESP_ERR_STREAM_WRITE = -1004,
    LANTERN_REQRESP_ERR_INVALID_PAYLOAD = -1008,
};

enum lantern_reqresp_protocol_kind {
    LANTERN_REQRESP_PROTOCOL_STATUS = 0,
    LANTERN_REQRESP_PROTOCOL_BLOCKS_BY_ROOT = 1,
    LANTERN_REQRESP_PROTOCOL_BLOCKS_BY_RANGE = 2,
    LANTERN_REQRESP_PROTOCOL_KIND_COUNT,
};

struct lantern_log_metadata;
struct lantern_reqresp_exchange;

struct lantern_reqresp_service_callbacks {
    void *context;
    int (*build_status)(void *context, LanternStatusMessage *out_status);
    int (*handle_status)(
        void *context,
        const LanternStatusMessage *peer_status,
        const char *peer_id);
    void (*status_failure)(
        void *context,
        const char *peer_id,
        int error);
    int (*collect_blocks)(
        void *context,
        const LanternRoot *roots,
        size_t root_count,
        LanternSignedBlockList *out_blocks);
    int (*collect_blocks_by_range)(
        void *context,
        uint64_t start_slot,
        uint64_t count,
        LanternSignedBlockList *out_blocks);
    int (*current_slot)(void *context, uint64_t *out_slot);
    int (*handle_block_response)(
        void *context,
        const LanternSignedBlock *block,
        const uint8_t *raw_block_ssz,
        size_t raw_block_ssz_len,
        const char *peer_id);
    void (*blocks_request_complete)(
        void *context,
        const char *peer_id,
        const LanternRoot *roots,
        size_t root_count,
        uint64_t request_id,
        int success);
};

struct lantern_reqresp_service_config {
    struct lantern_libp2p_host *network;
    const struct lantern_reqresp_service_callbacks *callbacks;
};

struct lantern_reqresp_protocol_context {
    struct lantern_reqresp_service *service;
    enum lantern_reqresp_protocol_kind kind;
};

struct lantern_reqresp_service {
    struct lantern_libp2p_host *network;
    struct lantern_reqresp_service_callbacks callbacks;
    libp2p_host_protocol_t status_protocol;
    libp2p_host_protocol_t blocks_protocol;
    libp2p_host_protocol_t blocks_by_range_protocol;
    struct lantern_reqresp_protocol_context status_context;
    struct lantern_reqresp_protocol_context blocks_context;
    struct lantern_reqresp_protocol_context blocks_by_range_context;
    struct lantern_reqresp_exchange *exchanges;
    int lock_initialized;
    pthread_mutex_t lock;
};

#ifdef __cplusplus
extern "C" {
#endif

void lantern_reqresp_service_init(struct lantern_reqresp_service *service);
void lantern_reqresp_service_reset(struct lantern_reqresp_service *service);
int lantern_reqresp_service_request_status(
    struct lantern_reqresp_service *service,
    const struct lantern_peer_id *peer_id,
    const char *peer_id_text);
int lantern_reqresp_service_request_blocks(
    struct lantern_reqresp_service *service,
    const struct lantern_peer_id *peer_id,
    const char *peer_id_text,
    const LanternRoot *roots,
    size_t root_count,
    uint64_t request_id);
int lantern_reqresp_service_start(
    struct lantern_reqresp_service *service,
    const struct lantern_reqresp_service_config *config);

#ifdef __cplusplus
}
#endif

#endif /* LANTERN_NETWORKING_REQRESP_SERVICE_H */
