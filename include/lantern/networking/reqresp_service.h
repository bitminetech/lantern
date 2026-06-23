#ifndef LANTERN_NETWORKING_REQRESP_SERVICE_H
#define LANTERN_NETWORKING_REQRESP_SERVICE_H

#include <pthread.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <sys/types.h>

#include "lantern/networking/libp2p.h"
#include "lantern/networking/messages.h"

#define LANTERN_REQRESP_STATUS_PROTOCOL_SNAPPY "/leanconsensus/req/status/1/ssz_snappy"
#define LANTERN_REQRESP_BLOCKS_BY_ROOT_PROTOCOL_SNAPPY "/leanconsensus/req/blocks_by_root/1/ssz_snappy"
#define LANTERN_REQRESP_BLOCKS_BY_RANGE_PROTOCOL_SNAPPY "/leanconsensus/req/blocks_by_range/1/ssz_snappy"
#define LANTERN_REQRESP_STATUS_PROTOCOL LANTERN_REQRESP_STATUS_PROTOCOL_SNAPPY
#define LANTERN_REQRESP_BLOCKS_BY_ROOT_PROTOCOL LANTERN_REQRESP_BLOCKS_BY_ROOT_PROTOCOL_SNAPPY
#define LANTERN_REQRESP_BLOCKS_BY_RANGE_PROTOCOL LANTERN_REQRESP_BLOCKS_BY_RANGE_PROTOCOL_SNAPPY
#define LANTERN_REQRESP_STATUS_PREVIEW_BYTES 256u
#define LANTERN_REQRESP_MAX_CHUNK_BYTES (10u * 1024u * 1024u)
#define LANTERN_REQRESP_MAX_CONTEXT_BYTES (1u << 20)
#define LANTERN_REQRESP_HEADER_MAX_BYTES 10u
#define LANTERN_REQRESP_TTFB_TIMEOUT_MS 10000u
#define LANTERN_REQRESP_RESP_TIMEOUT_MS 10000u
#define LANTERN_REQRESP_STALL_TIMEOUT_MS LANTERN_REQRESP_TTFB_TIMEOUT_MS
#define LANTERN_REQRESP_MAX_ERROR_MESSAGE_SIZE 256u
#define LANTERN_MIN_SLOTS_FOR_BLOCK_REQUESTS 3600u
#define LANTERN_REQRESP_RESPONSE_SUCCESS 0u
#define LANTERN_REQRESP_RESPONSE_INVALID_REQUEST 1u
#define LANTERN_REQRESP_RESPONSE_SERVER_ERROR 2u
#define LANTERN_REQRESP_RESPONSE_RESOURCE_UNAVAILABLE 3u
#define LANTERN_REQRESP_MAX_TRACKED_CONNECTIONS 64u

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
    LANTERN_REQRESP_ERR_INVALID_PAYLOAD = -1008,
} lantern_reqresp_error;

enum lantern_reqresp_protocol_kind {
    LANTERN_REQRESP_PROTOCOL_STATUS = 0,
    LANTERN_REQRESP_PROTOCOL_BLOCKS_BY_ROOT = 1,
    LANTERN_REQRESP_PROTOCOL_BLOCKS_BY_RANGE = 2,
    LANTERN_REQRESP_PROTOCOL_KIND_COUNT,
};

#define LANTERN_STATUS_PROTOCOL_ID LANTERN_REQRESP_STATUS_PROTOCOL
#define LANTERN_BLOCKS_BY_ROOT_PROTOCOL_ID LANTERN_REQRESP_BLOCKS_BY_ROOT_PROTOCOL
#define LANTERN_BLOCKS_BY_RANGE_PROTOCOL_ID LANTERN_REQRESP_BLOCKS_BY_RANGE_PROTOCOL
#define LANTERN_STATUS_PREVIEW_BYTES LANTERN_REQRESP_STATUS_PREVIEW_BYTES

struct lantern_log_metadata;

struct lantern_reqresp_stream;
struct lantern_reqresp_exchange;

struct lantern_reqresp_stream_ops {
    ssize_t (*read)(void *io_ctx, void *buf, size_t len);
    ssize_t (*write)(void *io_ctx, const void *buf, size_t len);
    int (*close)(void *io_ctx);
    int (*reset)(void *io_ctx);
    int (*set_deadline)(void *io_ctx, uint64_t ms);
    int (*shutdown_write)(void *io_ctx);
    void (*free_ctx)(void *io_ctx);
};

struct lantern_reqresp_stream {
    libp2p_host_t *host;
    libp2p_host_stream_t *stream;
    void *io_ctx;
    struct lantern_reqresp_stream_ops ops;
    struct lantern_peer_id remote_peer;
    bool has_remote_peer;
};

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

struct lantern_reqresp_conn_entry {
    struct lantern_peer_id peer;
    libp2p_host_conn_t *conn;
    int inbound;
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
    struct lantern_reqresp_conn_entry conns[LANTERN_REQRESP_MAX_TRACKED_CONNECTIONS];
    size_t conn_count;
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
struct lantern_reqresp_stream *lantern_reqresp_stream_from_ops(
    void *io_ctx,
    const struct lantern_reqresp_stream_ops *ops,
    const struct lantern_peer_id *remote_peer);
void lantern_reqresp_stream_free(struct lantern_reqresp_stream *stream);

int lantern_reqresp_read_response_chunk(
    struct lantern_reqresp_service *service,
    struct lantern_reqresp_stream *stream,
    enum lantern_reqresp_protocol_kind protocol,
    uint8_t **out_data,
    size_t *out_len,
    ssize_t *out_err,
    uint8_t *out_response_code,
    bool *response_code_pending);

uint32_t lantern_reqresp_stall_timeout_ms(void);

#ifdef __cplusplus
}
#endif

#endif /* LANTERN_NETWORKING_REQRESP_SERVICE_H */
