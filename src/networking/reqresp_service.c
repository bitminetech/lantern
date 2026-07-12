#include "lantern/networking/reqresp_service.h"

#include <stdlib.h>
#include <string.h>

#include "lantern/encoding/snappy.h"
#include "lantern/consensus/hash.h"
#include "lantern/consensus/ssz.h"
#include "lantern/support/log.h"
#include "lantern/support/strings.h"
#include "multiformats/unsigned_varint/unsigned_varint.h"

enum {
    LANTERN_SNAPPY_FRAME_CHUNK_HEADER_BYTES = 4u,
    LANTERN_SNAPPY_FRAME_STREAM_HEADER_BYTES = 10u,
};

struct reqresp_buffer {
    uint8_t *data;
    size_t len;
    size_t cap;
};

struct lantern_reqresp_exchange {
    struct lantern_reqresp_service *service;
    enum lantern_reqresp_protocol_kind kind;
    int outbound;
    libp2p_host_conn_t *conn;
    libp2p_host_t *host;
    libp2p_host_stream_t *stream;
    char peer_id_text[128];
    uint8_t *write_buf;
    size_t write_len;
    size_t write_off;
    struct reqresp_buffer read_buf;
    LanternRoot *roots;
    bool *roots_matched;
    size_t root_count;
    size_t matched_root_count;
    uint64_t request_id;
    int completed;
    int request_complete;
    struct lantern_reqresp_exchange *next;
};

static uint8_t normalize_response_code(uint8_t code) {
    if (code <= LANTERN_REQRESP_RESPONSE_RESOURCE_UNAVAILABLE) {
        return code;
    }
    return (code & 0x80u) ? LANTERN_REQRESP_RESPONSE_INVALID_REQUEST : LANTERN_REQRESP_RESPONSE_SERVER_ERROR;
}

static void reqresp_buffer_reset(struct reqresp_buffer *buffer) {
    if (!buffer) {
        return;
    }
    free(buffer->data);
    buffer->data = NULL;
    buffer->len = 0;
    buffer->cap = 0;
}

static int reqresp_buffer_reserve(struct reqresp_buffer *buffer, size_t required) {
    if (!buffer) {
        return -1;
    }
    if (required <= buffer->cap) {
        return 0;
    }
    size_t next = buffer->cap == 0u ? 1024u : buffer->cap;
    while (next < required) {
        if (next > SIZE_MAX / 2u) {
            next = required;
            break;
        }
        next *= 2u;
    }
    uint8_t *grown = (uint8_t *)realloc(buffer->data, next);
    if (!grown) {
        return -1;
    }
    buffer->data = grown;
    buffer->cap = next;
    return 0;
}

static int reqresp_buffer_append(struct reqresp_buffer *buffer, const uint8_t *data, size_t len) {
    if (!buffer || (!data && len > 0u)) {
        return -1;
    }
    if (len == 0u) {
        return 0;
    }
    if (buffer->len > SIZE_MAX - len || reqresp_buffer_reserve(buffer, buffer->len + len) != 0) {
        return -1;
    }
    memcpy(buffer->data + buffer->len, data, len);
    buffer->len += len;
    return 0;
}

static void reqresp_buffer_consume(struct reqresp_buffer *buffer, size_t len) {
    if (!buffer || len == 0u) {
        return;
    }
    if (len >= buffer->len) {
        buffer->len = 0;
        return;
    }
    memmove(buffer->data, buffer->data + len, buffer->len - len);
    buffer->len -= len;
}

static void exchange_free(struct lantern_reqresp_exchange *exchange) {
    if (!exchange) {
        return;
    }
    free(exchange->write_buf);
    reqresp_buffer_reset(&exchange->read_buf);
    free(exchange->roots);
    free(exchange->roots_matched);
    free(exchange);
}

static void service_add_exchange(struct lantern_reqresp_service *service, struct lantern_reqresp_exchange *exchange) {
    if (!service || !exchange) {
        return;
    }
    if (service->lock_initialized) {
        pthread_mutex_lock(&service->lock);
    }
    exchange->next = service->exchanges;
    service->exchanges = exchange;
    if (service->lock_initialized) {
        pthread_mutex_unlock(&service->lock);
    }
}

static int service_remove_exchange(struct lantern_reqresp_service *service, struct lantern_reqresp_exchange *exchange) {
    if (!service || !exchange) {
        return 0;
    }
    int removed = 0;
    if (service->lock_initialized) {
        pthread_mutex_lock(&service->lock);
    }
    struct lantern_reqresp_exchange **cursor = &service->exchanges;
    while (*cursor) {
        if (*cursor == exchange) {
            *cursor = exchange->next;
            exchange->next = NULL;
            removed = 1;
            break;
        }
        cursor = &(*cursor)->next;
    }
    if (service->lock_initialized) {
        pthread_mutex_unlock(&service->lock);
    }
    return removed;
}

static void service_clear_exchanges(struct lantern_reqresp_service *service) {
    if (!service) {
        return;
    }
    struct lantern_reqresp_exchange *list = NULL;
    if (service->lock_initialized) {
        pthread_mutex_lock(&service->lock);
    }
    list = service->exchanges;
    service->exchanges = NULL;
    if (service->lock_initialized) {
        pthread_mutex_unlock(&service->lock);
    }
    while (list) {
        struct lantern_reqresp_exchange *next = list->next;
        exchange_free(list);
        list = next;
    }
}

static uint32_t read_le24(const uint8_t bytes[3]) {
    return (uint32_t)bytes[0] | ((uint32_t)bytes[1] << 8u) | ((uint32_t)bytes[2] << 16u);
}

static int snappy_frame_payload_len(
    const uint8_t *data,
    size_t data_len,
    size_t raw_len,
    size_t *out_frame_len,
    int *out_need_more) {
    if (out_need_more) {
        *out_need_more = 0;
    }
    if (!data || !out_frame_len) {
        return -1;
    }
    if (data_len < (size_t)LANTERN_SNAPPY_FRAME_STREAM_HEADER_BYTES) {
        if (out_need_more) {
            *out_need_more = 1;
        }
        return 0;
    }
    if (!lantern_snappy_is_framed(data, data_len)) {
        return -1;
    }
    size_t offset = (size_t)LANTERN_SNAPPY_FRAME_STREAM_HEADER_BYTES;
    size_t decoded_total = 0;
    while (decoded_total < raw_len) {
        if (data_len - offset < (size_t)LANTERN_SNAPPY_FRAME_CHUNK_HEADER_BYTES) {
            if (out_need_more) {
                *out_need_more = 1;
            }
            return 0;
        }
        size_t chunk_len = (size_t)read_le24(data + offset + 1u);
        offset += (size_t)LANTERN_SNAPPY_FRAME_CHUNK_HEADER_BYTES;
        if (chunk_len > data_len - offset) {
            if (out_need_more) {
                *out_need_more = 1;
            }
            return 0;
        }

        offset += chunk_len;
        if (lantern_snappy_uncompressed_length(data, offset, &decoded_total) != LANTERN_SNAPPY_OK
            || decoded_total > raw_len) {
            return -1;
        }
    }
    *out_frame_len = offset;
    return 0;
}

static int build_frame_from_raw(
    const uint8_t *raw,
    size_t raw_len,
    int include_response_code,
    uint8_t response_code,
    uint8_t **out_frame,
    size_t *out_frame_len) {
    if (!out_frame || !out_frame_len || (!raw && raw_len > 0u)) {
        return -1;
    }
    *out_frame = NULL;
    *out_frame_len = 0;
    if (raw_len > LANTERN_REQRESP_MAX_CHUNK_BYTES) {
        return -1;
    }
    size_t max_compressed = 0;
    if (lantern_snappy_max_compressed_size(raw_len, &max_compressed) != LANTERN_SNAPPY_OK) {
        return -1;
    }
    uint8_t *compressed = (uint8_t *)malloc(max_compressed);
    if (!compressed) {
        return -1;
    }
    size_t compressed_len = 0;
    if (lantern_snappy_compress(raw, raw_len, compressed, max_compressed, &compressed_len) != LANTERN_SNAPPY_OK) {
        free(compressed);
        return -1;
    }
    uint8_t header[10];
    size_t header_len = 0;
    if (libp2p_uvarint_encode((uint64_t)raw_len, header, sizeof(header), &header_len)
        != LIBP2P_UVARINT_OK) {
        free(compressed);
        return -1;
    }
    size_t prefix = include_response_code ? 1u : 0u;
    if (compressed_len > SIZE_MAX - header_len - prefix) {
        free(compressed);
        return -1;
    }
    size_t total = prefix + header_len + compressed_len;
    uint8_t *frame = (uint8_t *)malloc(total > 0u ? total : 1u);
    if (!frame) {
        free(compressed);
        return -1;
    }
    size_t offset = 0;
    if (include_response_code) {
        frame[offset++] = response_code;
    }
    memcpy(frame + offset, header, header_len);
    offset += header_len;
    memcpy(frame + offset, compressed, compressed_len);
    offset += compressed_len;
    free(compressed);
    *out_frame = frame;
    *out_frame_len = offset;
    return 0;
}

static int append_frame_from_raw(
    struct reqresp_buffer *buffer,
    const uint8_t *raw,
    size_t raw_len,
    uint8_t response_code) {
    uint8_t *frame = NULL;
    size_t frame_len = 0;
    if (build_frame_from_raw(raw, raw_len, 1, response_code, &frame, &frame_len) != 0) {
        return -1;
    }
    int rc = reqresp_buffer_append(buffer, frame, frame_len);
    free(frame);
    return rc;
}

static int extract_frame_from_buffer(
    struct reqresp_buffer *buffer,
    int has_response_code,
    uint8_t *out_code,
    uint8_t **out_raw,
    size_t *out_raw_len,
    int *out_need_more) {
    if (out_need_more) {
        *out_need_more = 0;
    }
    if (!buffer || !out_raw || !out_raw_len) {
        return -1;
    }
    *out_raw = NULL;
    *out_raw_len = 0;
    size_t offset = 0;
    if (has_response_code) {
        if (buffer->len == 0u) {
            if (out_need_more) {
                *out_need_more = 1;
            }
            return 0;
        }
        if (out_code) {
            *out_code = normalize_response_code(buffer->data[0]);
        }
        offset = 1u;
    }
    if (offset == buffer->len) {
        if (out_need_more) {
            *out_need_more = 1;
        }
        return 0;
    }
    uint64_t declared_len = 0;
    size_t consumed = 0;
    libp2p_uvarint_err_t varint_err =
        libp2p_uvarint_decode(buffer->data + offset, buffer->len - offset, &declared_len, &consumed);
    if (varint_err == LIBP2P_UVARINT_ERR_TRUNCATED) {
        if (out_need_more) {
            *out_need_more = 1;
        }
        return 0;
    }
    if (varint_err != LIBP2P_UVARINT_OK || declared_len > LANTERN_REQRESP_MAX_CHUNK_BYTES) {
        return -1;
    }
    offset += consumed;
    size_t compressed_len = 0;
    int need_more = 0;
    if (snappy_frame_payload_len(
            buffer->data + offset,
            buffer->len - offset,
            (size_t)declared_len,
            &compressed_len,
            &need_more)
        != 0) {
        return -1;
    }
    if (need_more) {
        if (out_need_more) {
            *out_need_more = 1;
        }
        return 0;
    }
    uint8_t *raw = NULL;
    if (declared_len > 0u) {
        raw = (uint8_t *)malloc((size_t)declared_len);
        if (!raw) {
            return -1;
        }
    }
    size_t written = 0;
    if (lantern_snappy_decompress(
            buffer->data + offset,
            compressed_len,
            raw,
            (size_t)declared_len,
            &written)
        != LANTERN_SNAPPY_OK
        || written != (size_t)declared_len) {
        free(raw);
        return -1;
    }
    reqresp_buffer_consume(buffer, offset + compressed_len);
    *out_raw = raw;
    *out_raw_len = written;
    return 1;
}

static int peer_from_conn(libp2p_host_conn_t *conn, struct lantern_peer_id *out_peer) {
    if (!conn || !out_peer) {
        return -1;
    }
    size_t written = 0;
    if (libp2p_host_conn_peer_id(conn, out_peer->bytes, sizeof(out_peer->bytes), &written) != LIBP2P_HOST_OK
        || written == 0u || written > sizeof(out_peer->bytes)) {
        return -1;
    }
    out_peer->len = written;
    return 0;
}

static libp2p_host_conn_t *service_find_conn(
    struct lantern_reqresp_service *service,
    const struct lantern_peer_id *peer) {
    if (!service || !service->network || !service->network->host || !peer) {
        return NULL;
    }
    libp2p_host_conn_t *host_conn = NULL;
    if (libp2p_host_conn_for_peer_id(
            service->network->host,
            peer->bytes,
            peer->len,
            &host_conn)
        == LIBP2P_HOST_OK) {
        return host_conn;
    }
    return NULL;
}

static void exchange_set_peer_text_from_conn(struct lantern_reqresp_exchange *exchange, libp2p_host_conn_t *conn) {
    if (!exchange || exchange->peer_id_text[0] != '\0') {
        return;
    }
    struct lantern_peer_id peer;
    if (peer_from_conn(conn, &peer) == 0) {
        (void)lantern_peer_id_to_text(&peer, exchange->peer_id_text, sizeof(exchange->peer_id_text));
    }
}

static struct lantern_reqresp_exchange *service_take_opening_exchange(
    struct lantern_reqresp_service *service,
    enum lantern_reqresp_protocol_kind kind,
    libp2p_host_conn_t *conn) {
    if (!service) {
        return NULL;
    }
    struct lantern_reqresp_exchange *result = NULL;
    if (service->lock_initialized) {
        pthread_mutex_lock(&service->lock);
    }
    for (struct lantern_reqresp_exchange *exchange = service->exchanges; exchange; exchange = exchange->next) {
        if (exchange->outbound && exchange->kind == kind && !exchange->stream
            && (!conn || exchange->conn == conn)) {
            result = exchange;
            break;
        }
    }
    if (service->lock_initialized) {
        pthread_mutex_unlock(&service->lock);
    }
    return result;
}

static int build_status_request_frame(
    struct lantern_reqresp_service *service,
    uint8_t **out_frame,
    size_t *out_frame_len) {
    if (!service || !out_frame || !out_frame_len || !service->callbacks.build_status) {
        return -1;
    }
    LanternStatusMessage status;
    memset(&status, 0, sizeof(status));
    if (service->callbacks.build_status(service->callbacks.context, &status) != 0) {
        return -1;
    }
    uint8_t raw[2u * LANTERN_CHECKPOINT_SSZ_SIZE];
    size_t raw_len = 0;
    if (lantern_network_status_encode(&status, raw, sizeof(raw), &raw_len) != 0) {
        return -1;
    }
    return build_frame_from_raw(raw, raw_len, 0, 0, out_frame, out_frame_len);
}

static int build_blocks_request_frame(
    const LanternRoot *roots,
    size_t root_count,
    uint8_t **out_frame,
    size_t *out_frame_len) {
    if (!roots || root_count == 0u || root_count > LANTERN_MAX_REQUEST_BLOCKS || !out_frame || !out_frame_len) {
        return -1;
    }
    size_t raw_cap = sizeof(uint32_t) + (root_count * LANTERN_ROOT_SIZE);
    uint8_t *raw = (uint8_t *)malloc(raw_cap);
    if (!raw) {
        return -1;
    }
    LanternBlocksByRootRequest req;
    memset(&req, 0, sizeof(req));
    req.roots.items = (LanternRoot *)roots;
    req.roots.length = root_count;
    size_t raw_len = 0;
    int rc = lantern_network_blocks_by_root_request_encode(&req, raw, raw_cap, &raw_len);
    if (rc == 0) {
        rc = build_frame_from_raw(raw, raw_len, 0, 0, out_frame, out_frame_len);
    }
    free(raw);
    return rc;
}

static int encode_signed_block_raw(const LanternSignedBlock *block, uint8_t **out_raw, size_t *out_raw_len) {
    if (!block || !out_raw || !out_raw_len) {
        return -1;
    }
    *out_raw = NULL;
    *out_raw_len = 0;
    size_t cap = 4096u;
    for (unsigned attempt = 0; attempt < 20u; ++attempt) {
        uint8_t *raw = (uint8_t *)malloc(cap);
        if (!raw) {
            return -1;
        }
        size_t written = 0;
        ssz_error_t err = lantern_ssz_encode_signed_block(block, raw, cap, &written);
        if (err == SSZ_SUCCESS) {
            *out_raw = raw;
            *out_raw_len = written;
            return 0;
        }
        free(raw);
        if (cap > LANTERN_REQRESP_MAX_CHUNK_BYTES / 2u) {
            return -1;
        }
        cap *= 2u;
    }
    return -1;
}

static int exchange_append_block_responses(
    struct lantern_reqresp_exchange *exchange,
    const LanternSignedBlockList *blocks) {
    if (!exchange || !blocks) {
        return -1;
    }
    for (size_t i = 0; i < blocks->length; ++i) {
        uint8_t *block_raw = NULL;
        size_t block_raw_len = 0;
        if (encode_signed_block_raw(&blocks->blocks[i], &block_raw, &block_raw_len) != 0
            || append_frame_from_raw(
                   &exchange->read_buf,
                   block_raw,
                   block_raw_len,
                   LANTERN_REQRESP_RESPONSE_SUCCESS)
                   != 0) {
            free(block_raw);
            return -1;
        }
        free(block_raw);
    }
    return 0;
}

static int exchange_queue_error_response(struct lantern_reqresp_exchange *exchange, uint8_t code, const char *message) {
    if (!exchange) {
        return -1;
    }
    const char *text = message ? message : "";
    size_t text_len = strlen(text);
    if (text_len > LANTERN_REQRESP_MAX_ERROR_MESSAGE_SIZE) {
        text_len = LANTERN_REQRESP_MAX_ERROR_MESSAGE_SIZE;
    }
    return append_frame_from_raw(
        &exchange->read_buf,
        (const uint8_t *)text,
        text_len,
        code);
}

static int exchange_prepare_status_response(struct lantern_reqresp_exchange *exchange) {
    if (!exchange || !exchange->service || !exchange->service->callbacks.build_status) {
        return -1;
    }
    LanternStatusMessage status;
    memset(&status, 0, sizeof(status));
    if (exchange->service->callbacks.build_status(exchange->service->callbacks.context, &status) != 0) {
        return exchange_queue_error_response(
            exchange,
            LANTERN_REQRESP_RESPONSE_SERVER_ERROR,
            "Status not available");
    }
    uint8_t raw[2u * LANTERN_CHECKPOINT_SSZ_SIZE];
    size_t raw_len = 0;
    if (lantern_network_status_encode(&status, raw, sizeof(raw), &raw_len) != 0) {
        return exchange_queue_error_response(
            exchange,
            LANTERN_REQRESP_RESPONSE_SERVER_ERROR,
            "Status encode failed");
    }
    return append_frame_from_raw(&exchange->read_buf, raw, raw_len, LANTERN_REQRESP_RESPONSE_SUCCESS);
}

static int exchange_prepare_blocks_response(struct lantern_reqresp_exchange *exchange, const uint8_t *raw, size_t raw_len) {
    if (!exchange || !exchange->service || !raw) {
        return -1;
    }
    LanternBlocksByRootRequest req;
    lantern_blocks_by_root_request_init(&req);
    if (lantern_network_blocks_by_root_request_decode(&req, raw, raw_len) != 0) {
        lantern_blocks_by_root_request_reset(&req);
        return exchange_queue_error_response(
            exchange,
            LANTERN_REQRESP_RESPONSE_INVALID_REQUEST,
            "Invalid BlocksByRootRequest");
    }
    LanternSignedBlockList blocks;
    lantern_signed_block_list_init(&blocks);
    int collect_rc = exchange->service->callbacks.collect_blocks
        ? exchange->service->callbacks.collect_blocks(
              exchange->service->callbacks.context,
              req.roots.items,
              req.roots.length,
              &blocks)
        : -1;
    if (collect_rc != 0) {
        lantern_signed_block_list_reset(&blocks);
        lantern_blocks_by_root_request_reset(&req);
        return exchange_queue_error_response(
            exchange,
            LANTERN_REQRESP_RESPONSE_SERVER_ERROR,
            "Block lookup failed");
    }
    if (exchange_append_block_responses(exchange, &blocks) != 0) {
        lantern_signed_block_list_reset(&blocks);
        lantern_blocks_by_root_request_reset(&req);
        return -1;
    }
    lantern_log_info(
        "network",
        &(const struct lantern_log_metadata){.peer = exchange->peer_id_text[0] ? exchange->peer_id_text : NULL},
        "served blocks-by-root request (%zu roots)",
        req.roots.length);
    lantern_signed_block_list_reset(&blocks);
    lantern_blocks_by_root_request_reset(&req);
    return 0;
}

static int exchange_prepare_blocks_by_range_response(
    struct lantern_reqresp_exchange *exchange,
    const uint8_t *raw,
    size_t raw_len) {
    if (!exchange || !exchange->service || (!raw && raw_len > 0u)) {
        return -1;
    }
    LanternBlocksByRangeRequest req;
    memset(&req, 0, sizeof(req));
    if (lantern_network_blocks_by_range_request_decode(&req, raw, raw_len) != 0) {
        return exchange_queue_error_response(
            exchange,
            LANTERN_REQRESP_RESPONSE_INVALID_REQUEST,
            "Invalid BlocksByRangeRequest message");
    }
    if (!exchange->service->callbacks.collect_blocks_by_range) {
        return exchange_queue_error_response(
            exchange,
            LANTERN_REQRESP_RESPONSE_SERVER_ERROR,
            "Block lookup not available");
    }
    if (req.count == 0u || req.count > LANTERN_MAX_REQUEST_BLOCKS) {
        return exchange_queue_error_response(
            exchange,
            LANTERN_REQRESP_RESPONSE_INVALID_REQUEST,
            "Invalid count");
    }
    if (!exchange->service->callbacks.current_slot) {
        return exchange_queue_error_response(
            exchange,
            LANTERN_REQRESP_RESPONSE_SERVER_ERROR,
            "Current slot not available");
    }
    uint64_t current_slot = 0;
    if (exchange->service->callbacks.current_slot(exchange->service->callbacks.context, &current_slot) != 0) {
        return exchange_queue_error_response(
            exchange,
            LANTERN_REQRESP_RESPONSE_SERVER_ERROR,
            "Current slot not available");
    }
    uint64_t window_floor = current_slot >= LANTERN_MIN_SLOTS_FOR_BLOCK_REQUESTS
        ? current_slot - LANTERN_MIN_SLOTS_FOR_BLOCK_REQUESTS
        : 0u;
    if (req.start_slot < window_floor) {
        return exchange_queue_error_response(
            exchange,
            LANTERN_REQRESP_RESPONSE_RESOURCE_UNAVAILABLE,
            "Requested slot predates history window");
    }

    LanternSignedBlockList blocks;
    lantern_signed_block_list_init(&blocks);
    int collect_rc = exchange->service->callbacks.collect_blocks_by_range(
        exchange->service->callbacks.context,
        req.start_slot,
        req.count,
        &blocks);
    if (collect_rc != 0) {
        lantern_signed_block_list_reset(&blocks);
        return exchange_queue_error_response(
            exchange,
            LANTERN_REQRESP_RESPONSE_SERVER_ERROR,
            "Block range lookup failed");
    }
    if (exchange_append_block_responses(exchange, &blocks) != 0) {
        lantern_signed_block_list_reset(&blocks);
        return -1;
    }
    lantern_signed_block_list_reset(&blocks);
    return 0;
}

static int exchange_set_write_from_buffer(struct lantern_reqresp_exchange *exchange) {
    if (!exchange) {
        return -1;
    }
    free(exchange->write_buf);
    exchange->write_buf = exchange->read_buf.data;
    exchange->write_len = exchange->read_buf.len;
    exchange->write_off = 0;
    exchange->read_buf.data = NULL;
    exchange->read_buf.len = 0;
    exchange->read_buf.cap = 0;
    return 0;
}

static int exchange_flush_write(struct lantern_reqresp_exchange *exchange) {
    if (!exchange || !exchange->host || !exchange->stream) {
        return -1;
    }
    while (exchange->write_off < exchange->write_len) {
        size_t accepted = 0;
        libp2p_host_err_t err = libp2p_host_stream_write(
            exchange->host,
            exchange->stream,
            exchange->write_buf + exchange->write_off,
            exchange->write_len - exchange->write_off,
            0,
            &accepted);
        if (err == LIBP2P_HOST_OK && accepted > 0u) {
            exchange->write_off += accepted;
            continue;
        }
        if (err == LIBP2P_HOST_ERR_WOULD_BLOCK) {
            return 0;
        }
        return -1;
    }
    (void)libp2p_host_stream_finish(exchange->host, exchange->stream);
    return 0;
}

static int exchange_read_available(struct lantern_reqresp_exchange *exchange, int *out_fin) {
    if (out_fin) {
        *out_fin = 0;
    }
    if (!exchange || !exchange->host || !exchange->stream) {
        return -1;
    }
    uint8_t tmp[4096];
    for (;;) {
        size_t read_len = 0;
        int fin = 0;
        libp2p_host_err_t err =
            libp2p_host_stream_read(exchange->host, exchange->stream, tmp, sizeof(tmp), &read_len, &fin);
        if (err == LIBP2P_HOST_ERR_WOULD_BLOCK) {
            return 0;
        }
        if (err != LIBP2P_HOST_OK) {
            return -1;
        }
        if (read_len > 0u && reqresp_buffer_append(&exchange->read_buf, tmp, read_len) != 0) {
            return -1;
        }
        if (fin) {
            if (out_fin) {
                *out_fin = 1;
            }
            return 0;
        }
        if (read_len == 0u) {
            return 0;
        }
    }
}

static bool exchange_blocks_request_success(const struct lantern_reqresp_exchange *exchange) {
    return exchange && exchange->kind == LANTERN_REQRESP_PROTOCOL_BLOCKS_BY_ROOT
        && exchange->roots_matched
        && exchange->root_count > 0u
        && exchange->matched_root_count == exchange->root_count;
}

static bool exchange_find_unmatched_root_index(
    const struct lantern_reqresp_exchange *exchange,
    const LanternRoot *root,
    size_t *out_index) {
    if (!exchange || !root || !exchange->roots || !exchange->roots_matched) {
        return false;
    }
    for (size_t i = 0; i < exchange->root_count; ++i) {
        if (!exchange->roots_matched[i]
            && memcmp(exchange->roots[i].bytes, root->bytes, LANTERN_ROOT_SIZE) == 0) {
            if (out_index) {
                *out_index = i;
            }
            return true;
        }
    }
    return false;
}

static void exchange_complete_blocks_request(struct lantern_reqresp_exchange *exchange, int success) {
    if (!exchange || exchange->completed) {
        return;
    }
    exchange->completed = 1;
    if (exchange->service->callbacks.blocks_request_complete) {
        exchange->service->callbacks.blocks_request_complete(
            exchange->service->callbacks.context,
            exchange->peer_id_text,
            exchange->roots,
            exchange->root_count,
            exchange->request_id,
            success);
    }
}

static void exchange_fail(struct lantern_reqresp_exchange *exchange, int error) {
    if (!exchange || exchange->completed) {
        return;
    }
    if (exchange->outbound && exchange->kind == LANTERN_REQRESP_PROTOCOL_STATUS) {
        exchange->completed = 1;
        if (exchange->service->callbacks.status_failure) {
            exchange->service->callbacks.status_failure(
                exchange->service->callbacks.context,
                exchange->peer_id_text,
                error);
        }
    } else if (exchange->outbound && exchange->kind == LANTERN_REQRESP_PROTOCOL_BLOCKS_BY_ROOT) {
        exchange_complete_blocks_request(exchange, 0);
    } else {
        exchange->completed = 1;
    }
}

static void exchange_handle_outbound_closed(struct lantern_reqresp_exchange *exchange, bool reset) {
    if (!exchange || !exchange->outbound || exchange->completed) {
        return;
    }
    if (!reset && exchange_blocks_request_success(exchange)) {
        exchange_complete_blocks_request(exchange, 1);
        return;
    }
    exchange_fail(exchange, LANTERN_REQRESP_ERR_STREAM_READ);
}

static int exchange_handle_outbound_status_frame(
    struct lantern_reqresp_exchange *exchange,
    uint8_t code,
    uint8_t *raw,
    size_t raw_len) {
    if (!exchange || !raw) {
        return -1;
    }
    if (code != LANTERN_REQRESP_RESPONSE_SUCCESS) {
        exchange_fail(exchange, (int)code);
        return 0;
    }
    LanternStatusMessage status;
    memset(&status, 0, sizeof(status));
    if (lantern_network_status_decode(&status, raw, raw_len) != 0) {
        exchange_fail(exchange, LANTERN_REQRESP_ERR_INVALID_PAYLOAD);
        return 0;
    }
    if (exchange->service->callbacks.handle_status) {
        (void)exchange->service->callbacks.handle_status(
            exchange->service->callbacks.context,
            &status,
            exchange->peer_id_text);
    }
    exchange->completed = 1;
    return 0;
}

static int exchange_handle_outbound_block_frame(
    struct lantern_reqresp_exchange *exchange,
    uint8_t code,
    uint8_t *raw,
    size_t raw_len) {
    if (!exchange) {
        return -1;
    }
    if (code == LANTERN_REQRESP_RESPONSE_RESOURCE_UNAVAILABLE) {
        return 0;
    }
    if (code != LANTERN_REQRESP_RESPONSE_SUCCESS || !raw) {
        exchange_fail(exchange, (int)code);
        return 0;
    }
    LanternSignedBlock block;
    lantern_signed_block_init(&block);
    if (lantern_ssz_decode_signed_block(&block, raw, raw_len) != SSZ_SUCCESS) {
        lantern_signed_block_reset(&block);
        exchange_fail(exchange, LANTERN_REQRESP_ERR_INVALID_PAYLOAD);
        return 0;
    }
    size_t root_index = 0;
    if (exchange->kind == LANTERN_REQRESP_PROTOCOL_BLOCKS_BY_ROOT) {
        LanternRoot block_root = {0};
        if (lantern_hash_tree_root_block(&block.block, &block_root) != SSZ_SUCCESS
            || !exchange_find_unmatched_root_index(exchange, &block_root, &root_index)) {
            lantern_signed_block_reset(&block);
            exchange_fail(exchange, LANTERN_REQRESP_ERR_INVALID_PAYLOAD);
            return 0;
        }
    }
    int handled = 0;
    if (exchange->service->callbacks.handle_block_response) {
        handled = exchange->service->callbacks.handle_block_response(
            exchange->service->callbacks.context,
            &block,
            raw,
            raw_len,
            exchange->peer_id_text);
    }
    lantern_signed_block_reset(&block);
    if (handled == 0) {
        if (exchange->kind == LANTERN_REQRESP_PROTOCOL_BLOCKS_BY_ROOT) {
            exchange->roots_matched[root_index] = true;
        }
        exchange->matched_root_count += 1u;
        if (exchange_blocks_request_success(exchange)) {
            exchange_complete_blocks_request(exchange, 1);
        }
    } else {
        exchange_fail(exchange, handled);
    }
    return 0;
}

static int exchange_parse_outbound_frames(struct lantern_reqresp_exchange *exchange) {
    if (!exchange) {
        return -1;
    }
    while (!exchange->completed) {
        uint8_t code = 0;
        uint8_t *raw = NULL;
        size_t raw_len = 0;
        int need_more = 0;
        int rc = extract_frame_from_buffer(&exchange->read_buf, 1, &code, &raw, &raw_len, &need_more);
        if (rc < 0) {
            exchange_fail(exchange, LANTERN_REQRESP_ERR_INVALID_PAYLOAD);
            return 0;
        }
        if (rc == 0) {
            return need_more ? 0 : -1;
        }
        if (exchange->kind == LANTERN_REQRESP_PROTOCOL_STATUS) {
            (void)exchange_handle_outbound_status_frame(exchange, code, raw, raw_len);
        } else {
            (void)exchange_handle_outbound_block_frame(exchange, code, raw, raw_len);
        }
        free(raw);
        if (exchange->kind == LANTERN_REQRESP_PROTOCOL_STATUS) {
            break;
        }
    }
    return 0;
}

static int exchange_handle_inbound_request(struct lantern_reqresp_exchange *exchange) {
    if (!exchange || exchange->write_buf) {
        return 0;
    }
    uint8_t *raw = NULL;
    size_t raw_len = 0;
    int need_more = 0;
    int rc = extract_frame_from_buffer(&exchange->read_buf, 0, NULL, &raw, &raw_len, &need_more);
    if (rc < 0) {
        reqresp_buffer_reset(&exchange->read_buf);
        (void)exchange_queue_error_response(
            exchange,
            LANTERN_REQRESP_RESPONSE_INVALID_REQUEST,
            "Invalid request");
        return exchange_set_write_from_buffer(exchange);
    }
    if (rc == 0) {
        return need_more ? 0 : -1;
    }
    exchange->request_complete = 1;
    int prepare_rc = 0;
    if (exchange->kind == LANTERN_REQRESP_PROTOCOL_STATUS) {
        LanternStatusMessage peer_status;
        memset(&peer_status, 0, sizeof(peer_status));
        if (lantern_network_status_decode(&peer_status, raw, raw_len) != 0) {
            prepare_rc = exchange_queue_error_response(
                exchange,
                LANTERN_REQRESP_RESPONSE_INVALID_REQUEST,
                "Invalid Status message");
        } else {
            if (exchange->service->callbacks.handle_status) {
                (void)exchange->service->callbacks.handle_status(
                    exchange->service->callbacks.context,
                    &peer_status,
                    exchange->peer_id_text);
            }
            prepare_rc = exchange_prepare_status_response(exchange);
        }
    } else if (exchange->kind == LANTERN_REQRESP_PROTOCOL_BLOCKS_BY_ROOT) {
        prepare_rc = exchange_prepare_blocks_response(exchange, raw, raw_len);
    } else if (exchange->kind == LANTERN_REQRESP_PROTOCOL_BLOCKS_BY_RANGE) {
        prepare_rc = exchange_prepare_blocks_by_range_response(exchange, raw, raw_len);
    } else {
        prepare_rc = exchange_queue_error_response(
            exchange,
            LANTERN_REQRESP_RESPONSE_SERVER_ERROR,
            "Unknown protocol");
    }
    free(raw);
    if (prepare_rc != 0) {
        reqresp_buffer_reset(&exchange->read_buf);
        (void)exchange_queue_error_response(
            exchange,
            LANTERN_REQRESP_RESPONSE_SERVER_ERROR,
            "Internal error");
    }
    return exchange_set_write_from_buffer(exchange);
}

static libp2p_host_err_t reqresp_on_open(
    libp2p_host_t *host,
    libp2p_host_stream_t *stream,
    libp2p_host_stream_direction_t direction,
    void *protocol_user_data) {
    struct lantern_reqresp_protocol_context *protocol_ctx =
        (struct lantern_reqresp_protocol_context *)protocol_user_data;
    if (!host || !stream || !protocol_ctx || !protocol_ctx->service) {
        return LIBP2P_HOST_ERR_INVALID_ARG;
    }
    libp2p_host_conn_t *conn = NULL;
    (void)libp2p_host_stream_conn(stream, &conn);
    struct lantern_reqresp_exchange *exchange = NULL;
    if (direction == LIBP2P_HOST_STREAM_OUTBOUND) {
        exchange = service_take_opening_exchange(protocol_ctx->service, protocol_ctx->kind, conn);
        if (!exchange) {
            return LIBP2P_HOST_ERR_STATE;
        }
    } else {
        exchange = (struct lantern_reqresp_exchange *)calloc(1u, sizeof(*exchange));
        if (!exchange) {
            return LIBP2P_HOST_ERR_INTERNAL;
        }
        exchange->service = protocol_ctx->service;
        exchange->kind = protocol_ctx->kind;
        exchange->outbound = 0;
        exchange->conn = conn;
        service_add_exchange(protocol_ctx->service, exchange);
    }
    exchange->host = host;
    exchange->stream = stream;
    exchange_set_peer_text_from_conn(exchange, conn);
    (void)libp2p_host_stream_set_user_data(stream, exchange);
    return LIBP2P_HOST_OK;
}

static libp2p_host_err_t reqresp_on_event(
    libp2p_host_t *host,
    libp2p_host_stream_t *stream,
    libp2p_host_protocol_event_kind_t kind,
    void *protocol_user_data) {
    (void)protocol_user_data;
    void *user_data = NULL;
    if (!host || !stream || libp2p_host_stream_user_data(stream, &user_data) != LIBP2P_HOST_OK || !user_data) {
        return LIBP2P_HOST_OK;
    }
    struct lantern_reqresp_exchange *exchange = (struct lantern_reqresp_exchange *)user_data;
    if (kind == LIBP2P_HOST_PROTOCOL_EVENT_RESET || kind == LIBP2P_HOST_PROTOCOL_EVENT_CLOSED) {
        if (exchange->outbound) {
            exchange_handle_outbound_closed(
                exchange,
                kind == LIBP2P_HOST_PROTOCOL_EVENT_RESET);
        }
        service_remove_exchange(exchange->service, exchange);
        exchange_free(exchange);
        return LIBP2P_HOST_OK;
    }
    if (kind == LIBP2P_HOST_PROTOCOL_EVENT_WRITABLE && exchange->write_buf) {
        if (exchange_flush_write(exchange) != 0) {
            exchange_fail(exchange, LANTERN_REQRESP_ERR_STREAM_WRITE);
            return LIBP2P_HOST_ERR_PROTOCOL;
        }
        return LIBP2P_HOST_OK;
    }
    if (kind == LIBP2P_HOST_PROTOCOL_EVENT_READABLE) {
        int fin = 0;
        if (exchange_read_available(exchange, &fin) != 0) {
            exchange_fail(exchange, LANTERN_REQRESP_ERR_STREAM_READ);
            return LIBP2P_HOST_ERR_PROTOCOL;
        }
        if (exchange->outbound) {
            if (exchange_parse_outbound_frames(exchange) != 0) {
                return LIBP2P_HOST_ERR_PROTOCOL;
            }
        } else if (exchange_handle_inbound_request(exchange) != 0) {
            return LIBP2P_HOST_ERR_PROTOCOL;
        }
        if (!exchange->outbound && exchange->write_buf && exchange_flush_write(exchange) != 0) {
            return LIBP2P_HOST_ERR_PROTOCOL;
        }
        if (!exchange->outbound && exchange->request_complete && !exchange->write_buf && exchange->read_buf.len == 0u) {
            (void)libp2p_host_stream_finish(host, stream);
        }
        (void)fin;
    }
    return LIBP2P_HOST_OK;
}

static void reqresp_host_event(
    struct lantern_libp2p_host *network,
    const libp2p_host_event_t *event,
    void *user_data) {
    (void)network;
    struct lantern_reqresp_service *service = (struct lantern_reqresp_service *)user_data;
    if (!service || !event) {
        return;
    }
    if (event->type == LIBP2P_HOST_EVENT_STREAM_OPEN_FAILED && event->user_data) {
        struct lantern_reqresp_exchange *exchange = (struct lantern_reqresp_exchange *)event->user_data;
        if (!service_remove_exchange(service, exchange)) {
            return;
        }
        exchange_fail(exchange, (int)event->reason);
        exchange_free(exchange);
    }
}

void lantern_reqresp_service_init(struct lantern_reqresp_service *service) {
    if (!service) {
        return;
    }
    memset(service, 0, sizeof(*service));
}

void lantern_reqresp_service_reset(struct lantern_reqresp_service *service) {
    if (!service) {
        return;
    }
    service_clear_exchanges(service);
    if (service->lock_initialized) {
        pthread_mutex_destroy(&service->lock);
    }
    memset(service, 0, sizeof(*service));
}

int lantern_reqresp_service_start(
    struct lantern_reqresp_service *service,
    const struct lantern_reqresp_service_config *config) {
    if (!service || !config || !config->network || !config->network->host) {
        return -1;
    }
    service->network = config->network;
    if (config->callbacks) {
        service->callbacks = *config->callbacks;
    }
    if (pthread_mutex_init(&service->lock, NULL) == 0) {
        service->lock_initialized = 1;
    }

    service->status_protocol.id = (const uint8_t *)LANTERN_REQRESP_STATUS_PROTOCOL;
    service->status_protocol.id_len = strlen(LANTERN_REQRESP_STATUS_PROTOCOL);
    service->status_protocol.on_open = reqresp_on_open;
    service->status_protocol.on_event = reqresp_on_event;
    service->status_context.service = service;
    service->status_context.kind = LANTERN_REQRESP_PROTOCOL_STATUS;
    service->status_protocol.user_data = &service->status_context;

    service->blocks_protocol.id = (const uint8_t *)LANTERN_REQRESP_BLOCKS_BY_ROOT_PROTOCOL;
    service->blocks_protocol.id_len = strlen(LANTERN_REQRESP_BLOCKS_BY_ROOT_PROTOCOL);
    service->blocks_protocol.on_open = reqresp_on_open;
    service->blocks_protocol.on_event = reqresp_on_event;
    service->blocks_context.service = service;
    service->blocks_context.kind = LANTERN_REQRESP_PROTOCOL_BLOCKS_BY_ROOT;
    service->blocks_protocol.user_data = &service->blocks_context;

    service->blocks_by_range_protocol.id = (const uint8_t *)LANTERN_REQRESP_BLOCKS_BY_RANGE_PROTOCOL;
    service->blocks_by_range_protocol.id_len = strlen(LANTERN_REQRESP_BLOCKS_BY_RANGE_PROTOCOL);
    service->blocks_by_range_protocol.on_open = reqresp_on_open;
    service->blocks_by_range_protocol.on_event = reqresp_on_event;
    service->blocks_by_range_context.service = service;
    service->blocks_by_range_context.kind = LANTERN_REQRESP_PROTOCOL_BLOCKS_BY_RANGE;
    service->blocks_by_range_protocol.user_data = &service->blocks_by_range_context;

    if (lantern_libp2p_host_register_protocol(service->network, &service->status_protocol) != 0 ||
        lantern_libp2p_host_register_protocol(service->network, &service->blocks_protocol) != 0 ||
        lantern_libp2p_host_register_protocol(service->network, &service->blocks_by_range_protocol) != 0) {
        return -1;
    }
    if (lantern_libp2p_host_register_event_handler(service->network, reqresp_host_event, service) != 0) {
        return -1;
    }
    return 0;
}

static const char *reqresp_protocol_id_for_kind(enum lantern_reqresp_protocol_kind kind) {
    switch (kind) {
    case LANTERN_REQRESP_PROTOCOL_STATUS:
        return LANTERN_REQRESP_STATUS_PROTOCOL;
    case LANTERN_REQRESP_PROTOCOL_BLOCKS_BY_ROOT:
        return LANTERN_REQRESP_BLOCKS_BY_ROOT_PROTOCOL;
    case LANTERN_REQRESP_PROTOCOL_BLOCKS_BY_RANGE:
        return LANTERN_REQRESP_BLOCKS_BY_RANGE_PROTOCOL;
    default:
        return NULL;
    }
}

static int service_open_exchange(
    struct lantern_reqresp_service *service,
    const struct lantern_peer_id *peer_id,
    const char *peer_id_text,
    enum lantern_reqresp_protocol_kind kind,
    uint8_t *frame,
    size_t frame_len,
    const LanternRoot *roots,
    size_t root_count,
    uint64_t request_id) {
    if (!service || !service->network || !service->network->host || !peer_id || !frame || frame_len == 0u) {
        free(frame);
        return -1;
    }
    libp2p_host_conn_t *conn = service_find_conn(service, peer_id);
    if (!conn) {
        free(frame);
        return -1;
    }
    struct lantern_reqresp_exchange *exchange = (struct lantern_reqresp_exchange *)calloc(1u, sizeof(*exchange));
    if (!exchange) {
        free(frame);
        return -1;
    }
    exchange->service = service;
    exchange->kind = kind;
    exchange->outbound = 1;
    exchange->conn = conn;
    exchange->host = service->network->host;
    exchange->write_buf = frame;
    exchange->write_len = frame_len;
    exchange->request_id = request_id;
    if (peer_id_text) {
        (void)lantern_string_copy(
            exchange->peer_id_text,
            sizeof(exchange->peer_id_text),
            peer_id_text);
    }
    if (root_count > 0u) {
        if (!roots) {
            exchange_free(exchange);
            return -1;
        }
        exchange->roots = (LanternRoot *)calloc(root_count, sizeof(*exchange->roots));
        if (!exchange->roots) {
            exchange_free(exchange);
            return -1;
        }
        memcpy(exchange->roots, roots, root_count * sizeof(*exchange->roots));
        exchange->roots_matched = (bool *)calloc(root_count, sizeof(*exchange->roots_matched));
        if (!exchange->roots_matched) {
            exchange_free(exchange);
            return -1;
        }
        exchange->root_count = root_count;
    }
    service_add_exchange(service, exchange);
    const char *protocol = reqresp_protocol_id_for_kind(kind);
    if (!protocol) {
        service_remove_exchange(service, exchange);
        exchange_free(exchange);
        return -1;
    }
    libp2p_host_stream_open_t *open = NULL;
    libp2p_host_err_t err = libp2p_host_open_stream(
        service->network->host,
        conn,
        (const uint8_t *)protocol,
        strlen(protocol),
        exchange,
        &open);
    if (err != LIBP2P_HOST_OK) {
        service_remove_exchange(service, exchange);
        exchange_free(exchange);
        return -1;
    }
    return 0;
}

int lantern_reqresp_service_request_status(
    struct lantern_reqresp_service *service,
    const struct lantern_peer_id *peer_id,
    const char *peer_id_text) {
    uint8_t *frame = NULL;
    size_t frame_len = 0;
    if (build_status_request_frame(service, &frame, &frame_len) != 0) {
        if (service && service->callbacks.status_failure) {
            service->callbacks.status_failure(
                service->callbacks.context,
                peer_id_text,
                LANTERN_REQRESP_ERR_STREAM_WRITE);
        }
        return -1;
    }
    if (service_open_exchange(
            service,
            peer_id,
            peer_id_text,
            LANTERN_REQRESP_PROTOCOL_STATUS,
            frame,
            frame_len,
            NULL,
            0,
            0)
        != 0) {
        if (service && service->callbacks.status_failure) {
            service->callbacks.status_failure(
                service->callbacks.context,
                peer_id_text,
                LANTERN_REQRESP_ERR_STREAM_WRITE);
        }
        return -1;
    }
    return 0;
}

int lantern_reqresp_service_request_blocks(
    struct lantern_reqresp_service *service,
    const struct lantern_peer_id *peer_id,
    const char *peer_id_text,
    const LanternRoot *roots,
    size_t root_count,
    uint64_t request_id) {
    uint8_t *frame = NULL;
    size_t frame_len = 0;
    if (build_blocks_request_frame(roots, root_count, &frame, &frame_len) != 0) {
        return -1;
    }
    return service_open_exchange(
        service,
        peer_id,
        peer_id_text,
        LANTERN_REQRESP_PROTOCOL_BLOCKS_BY_ROOT,
        frame,
        frame_len,
        roots,
        root_count,
        request_id);
}
