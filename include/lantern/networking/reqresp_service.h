#ifndef LANTERN_NETWORKING_REQRESP_SERVICE_H
#define LANTERN_NETWORKING_REQRESP_SERVICE_H

#include <pthread.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "lantern/networking/messages.h"
#include "libp2p/stream.h"
#include "peer_id/peer_id.h"

#define LANTERN_REQRESP_STATUS_PROTOCOL_SNAPPY "/leanconsensus/req/status/1/ssz_snappy"
#define LANTERN_REQRESP_BLOCKS_BY_ROOT_PROTOCOL_SNAPPY "/leanconsensus/req/blocks_by_root/1/ssz_snappy"
#define LANTERN_REQRESP_STATUS_PROTOCOL LANTERN_REQRESP_STATUS_PROTOCOL_SNAPPY
#define LANTERN_REQRESP_BLOCKS_BY_ROOT_PROTOCOL LANTERN_REQRESP_BLOCKS_BY_ROOT_PROTOCOL_SNAPPY
#define LANTERN_REQRESP_STATUS_PREVIEW_BYTES 256u
#define LANTERN_REQRESP_MAX_CHUNK_BYTES (10u * 1024u * 1024u)
#define LANTERN_REQRESP_MAX_CONTEXT_BYTES (1u << 20)
#define LANTERN_REQRESP_HEADER_MAX_BYTES 10u
#define LANTERN_REQRESP_TTFB_TIMEOUT_MS 10000u
#define LANTERN_REQRESP_RESP_TIMEOUT_MS 10000u
#define LANTERN_REQRESP_STALL_TIMEOUT_MS LANTERN_REQRESP_TTFB_TIMEOUT_MS
#define LANTERN_REQRESP_RESPONSE_SUCCESS 0u
#define LANTERN_REQRESP_RESPONSE_INVALID_REQUEST 1u
#define LANTERN_REQRESP_RESPONSE_SERVER_ERROR 2u
#define LANTERN_REQRESP_RESPONSE_RESOURCE_UNAVAILABLE 3u

/**
 * Reqresp service error codes.
 *
 * Functions return 0 on success and a negative value on failure.
 *
 * When a function also provides an `out_err` parameter, `out_err` contains the
 * underlying libp2p error code or `-errno` value for debugging.
 */
typedef enum
{
    LANTERN_REQRESP_OK = 0,
    LANTERN_REQRESP_ERR_INVALID_PARAM = -1000,
    LANTERN_REQRESP_ERR_SET_DEADLINE = -1001,
    LANTERN_REQRESP_ERR_SET_READ_INTEREST = -1002,
    LANTERN_REQRESP_ERR_STREAM_READ = -1003,
    LANTERN_REQRESP_ERR_STREAM_WRITE = -1004,
    LANTERN_REQRESP_ERR_VARINT_HEADER_TOO_LONG = -1005,
    LANTERN_REQRESP_ERR_PAYLOAD_TOO_LARGE = -1006,
    LANTERN_REQRESP_ERR_ALLOC = -1007,
} lantern_reqresp_error;

enum lantern_reqresp_protocol_kind {
    LANTERN_REQRESP_PROTOCOL_STATUS = 0,
    LANTERN_REQRESP_PROTOCOL_BLOCKS_BY_ROOT = 1,
    LANTERN_REQRESP_PROTOCOL_KIND_COUNT,
};

#define LANTERN_STATUS_PROTOCOL_ID LANTERN_REQRESP_STATUS_PROTOCOL
#define LANTERN_BLOCKS_BY_ROOT_PROTOCOL_ID LANTERN_REQRESP_BLOCKS_BY_ROOT_PROTOCOL
#define LANTERN_STATUS_PREVIEW_BYTES LANTERN_REQRESP_STATUS_PREVIEW_BYTES

struct libp2p_host;
struct libp2p_protocol_server;
struct libp2p_subscription;
struct lantern_log_metadata;

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
        LanternBlocksByRootResponse *out_blocks);
};

struct lantern_reqresp_service_config {
    struct libp2p_host *host;
    const struct lantern_reqresp_service_callbacks *callbacks;
};

struct lantern_reqresp_service {
    struct libp2p_host *host;
    struct lantern_reqresp_service_callbacks callbacks;
    struct libp2p_protocol_server *status_server;
    struct libp2p_protocol_server *blocks_server;
    struct libp2p_subscription *event_subscription;
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
    const peer_id_t *peer_id,
    const char *peer_id_text);
int lantern_reqresp_service_start(
    struct lantern_reqresp_service *service,
    const struct lantern_reqresp_service_config *config);

int lantern_reqresp_read_response_chunk(
    struct lantern_reqresp_service *service,
    libp2p_stream_t *stream,
    enum lantern_reqresp_protocol_kind protocol,
    uint8_t **out_data,
    size_t *out_len,
    ssize_t *out_err,
    uint8_t *out_response_code,
    bool *response_code_pending);

uint32_t lantern_reqresp_stall_timeout_ms(void);
bool lantern_reqresp_debug_bytes_enabled(void);
uint64_t lantern_reqresp_debug_sequence_next(void);
void lantern_reqresp_debug_log_bytes(
    const char *phase,
    const struct lantern_log_metadata *meta,
    size_t offset_base,
    const uint8_t *data,
    size_t length);

#ifdef __cplusplus
}
#endif

#endif /* LANTERN_NETWORKING_REQRESP_SERVICE_H */
