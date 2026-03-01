#include "lantern/networking/reqresp_service.h"

#include <errno.h>
#include <stdbool.h>
#include <pthread.h>
#include <stdio.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <inttypes.h>

#include "lantern/encoding/snappy.h"
#include "lantern/consensus/ssz.h"
#include "lantern/support/log.h"
#include "lantern/support/strings.h"
#include "lantern/support/time.h"

#include "libp2p/events.h"
#include "libp2p/host.h"
#include "libp2p/protocol.h"
#include "libp2p/protocol_listen.h"
#include "libp2p/stream.h"
#include "libp2p/stream_internal.h"
#include "libp2p/errors.h"
#include "multiformats/unsigned_varint/unsigned_varint.h"

#include "peer_id/peer_id.h"

#include "ssz_constants.h"
#include "../core/client_network_internal.h"

uint32_t lantern_reqresp_stall_timeout_ms(void) {
    static uint32_t timeout_ms = LANTERN_REQRESP_STALL_TIMEOUT_MS;
    static bool initialized = false;
    if (initialized) {
        return timeout_ms;
    }
    initialized = true;
    const char *env = getenv("LANTERN_REQRESP_STALL_TIMEOUT_MS");
    if (env && env[0] != '\0') {
        char *end = NULL;
        unsigned long parsed = strtoul(env, &end, 10);
        if (end && *end == '\0' && parsed > 0 && parsed <= UINT32_MAX) {
            timeout_ms = (uint32_t)parsed;
        } else {
            lantern_log_warn(
                "reqresp",
                NULL,
                "invalid LANTERN_REQRESP_STALL_TIMEOUT_MS value=%s (using default=%u)",
                env,
                LANTERN_REQRESP_STALL_TIMEOUT_MS);
        }
    }
    return timeout_ms;
}

static uint64_t reqresp_trace_id_next(void) {
    static uint64_t seq = 0;
    return __atomic_fetch_add(&seq, 1u, __ATOMIC_RELAXED);
}

struct status_stream_ctx {
    struct lantern_reqresp_service *service;
    libp2p_stream_t *stream;
    const char *protocol_id;
    uint64_t debug_trace_id;
};

struct blocks_stream_ctx {
    struct lantern_reqresp_service *service;
    libp2p_stream_t *stream;
    const char *protocol_id;
};

struct status_request_ctx {
    struct lantern_reqresp_service *service;
    peer_id_t *peer_id;
    char peer_text[128];
    const char *protocol_id;
    uint64_t debug_trace_id;
};

struct status_request_worker_args {
    struct status_request_ctx *ctx;
    libp2p_stream_t *stream;
};

static void log_stream_error(const char *phase, const char *protocol_id, const char *peer_id);
static void status_request_notify_failure(
    struct lantern_reqresp_service *service,
    const char *peer_text,
    int error);
static int status_request_launch(
    struct lantern_reqresp_service *service,
    const peer_id_t *peer_id,
    const char *peer_id_text,
    bool notify_on_failure);
static void lantern_reqresp_service_clear(struct lantern_reqresp_service *service) {
    if (!service) {
        return;
    }
    service->host = NULL;
    service->callbacks.context = NULL;
    service->callbacks.build_status = NULL;
    service->callbacks.handle_status = NULL;
    service->callbacks.status_failure = NULL;
    service->callbacks.collect_blocks = NULL;
    service->status_server = NULL;
    service->blocks_server = NULL;
    service->event_subscription = NULL;
}

static int write_legacy_peer_id_text(const peer_id_t *peer, char *buffer, size_t length) {
    if (!peer || !buffer || length == 0) {
        return -1;
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
        return -1;
    }
    return (int)written;
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

    struct libp2p_host *host = service->host;
    if (service->event_subscription && host) {
        libp2p_event_unsubscribe(host, service->event_subscription);
    }

    if (service->status_server && host) {
        (void)libp2p_host_unlisten(host, service->status_server);
    }

    if (service->blocks_server && host) {
        (void)libp2p_host_unlisten(host, service->blocks_server);
    }
    lantern_reqresp_service_clear(service);
}

static void describe_peer(const peer_id_t *peer, char *buffer, size_t length) {
    if (!buffer || length == 0) {
        return;
    }
    if (!peer) {
        buffer[0] = '\0';
        return;
    }
    if (write_legacy_peer_id_text(peer, buffer, length) < 0) {
        buffer[0] = '\0';
    }
}

static void status_request_ctx_free(struct status_request_ctx *ctx) {
    if (!ctx) {
        return;
    }
    peer_id_free(ctx->peer_id);
    free(ctx);
}

static const char *stream_error_name(ssize_t code) {
    switch (code) {
    case LIBP2P_ERR_AGAIN:
        return "again";
    case LIBP2P_ERR_TIMEOUT:
        return "timeout";
    case LIBP2P_ERR_EOF:
        return "eof";
    case LIBP2P_ERR_CLOSED:
        return "closed";
    case LIBP2P_ERR_RESET:
        return "reset";
    case LIBP2P_ERR_MSG_TOO_LARGE:
        return "too_large";
    default:
        return NULL;
    }
}

static void log_payload_preview(
    const char *stage,
    const char *peer_text,
    const uint8_t *data,
    size_t length) {
    if (!data) {
        return;
    }
    size_t preview_len = length < LANTERN_STATUS_PREVIEW_BYTES ? length : LANTERN_STATUS_PREVIEW_BYTES;
    char hex[(LANTERN_STATUS_PREVIEW_BYTES * 2u) + 1u];
    if (preview_len > 0) {
        if (lantern_bytes_to_hex(data, preview_len, hex, sizeof(hex), 0) != 0) {
            hex[0] = '\0';
        }
    } else {
        hex[0] = '\0';
    }
    const char *ellipsis = length > preview_len ? "..." : "";
    const struct lantern_log_metadata meta = {.peer = peer_text};
    lantern_log_trace(
        "reqresp",
        &meta,
        "%s bytes=%zu preview=%s%s",
        stage ? stage : "payload",
        length,
        hex[0] ? hex : "-",
        ellipsis);
}

static void log_snappy_frame_summary(
    const char *stage,
    const struct lantern_log_metadata *meta,
    const uint8_t *data,
    size_t length) {
    if (!data || !meta) {
        return;
    }

    bool framed = lantern_snappy_is_framed(data, length);
    bool have_first = false;
    bool have_second = false;
    uint8_t first_type = 0;
    uint32_t first_len = 0;
    uint8_t second_type = 0;
    uint32_t second_len = 0;
    size_t second_offset = 0;

    if (length >= 4u) {
        have_first = true;
        first_type = data[0];
        first_len = (uint32_t)data[1] | ((uint32_t)data[2] << 8u) | ((uint32_t)data[3] << 16u);
        second_offset = 4u + (size_t)first_len;
        if (second_offset + 4u <= length) {
            have_second = true;
            second_type = data[second_offset];
            second_len = (uint32_t)data[second_offset + 1u]
                | ((uint32_t)data[second_offset + 2u] << 8u)
                | ((uint32_t)data[second_offset + 3u] << 16u);
        }
    }

    size_t preview_len = length < 24u ? length : 24u;
    char preview_hex[(24u * 2u) + 1u];
    if (preview_len > 0) {
        if (lantern_bytes_to_hex(data, preview_len, preview_hex, sizeof(preview_hex), 0) != 0) {
            preview_hex[0] = '\0';
        }
    } else {
        preview_hex[0] = '\0';
    }
    const char *ellipsis = length > preview_len ? "..." : "";

    lantern_log_warn(
        "reqresp",
        meta,
        "%s snappy summary framed=%s len=%zu first_ok=%s first_type=0x%02x first_len=%u "
        "second_ok=%s second_type=0x%02x second_len=%u preview=%s%s",
        stage ? stage : "payload",
        framed ? "true" : "false",
        length,
        have_first ? "true" : "false",
        (unsigned)first_type,
        first_len,
        have_second ? "true" : "false",
        (unsigned)second_type,
        second_len,
        preview_hex[0] ? preview_hex : "-",
        ellipsis);
}

static uint64_t reqresp_now_ms(void) {
    double now_sec = lantern_time_now_seconds();
    if (now_sec <= 0.0) {
        return 0;
    }
    double now_ms = now_sec * 1000.0;
    if (now_ms >= (double)UINT64_MAX) {
        return UINT64_MAX;
    }
    return (uint64_t)now_ms;
}

static int set_stream_deadline_remaining(
    libp2p_stream_t *stream,
    uint64_t deadline_ms,
    const struct lantern_log_metadata *meta,
    const char *label,
    ssize_t *out_err) {
    if (!stream) {
        if (out_err) {
            *out_err = LIBP2P_ERR_NULL_PTR;
        }
        return -1;
    }
    uint64_t now_ms = reqresp_now_ms();
    if (now_ms >= deadline_ms) {
        if (out_err) {
            *out_err = LIBP2P_ERR_TIMEOUT;
        }
        lantern_log_warn(
            "reqresp",
            meta,
            "%s timed out",
            label ? label : "stream");
        return -1;
    }
    uint64_t remaining_ms = deadline_ms - now_ms;
    int rc = libp2p_stream_set_deadline(stream, remaining_ms);
    if (rc != 0) {
        if (out_err) {
            *out_err = (ssize_t)rc;
        }
        lantern_log_warn(
            "reqresp",
            meta,
            "%s failed to set deadline_ms=%" PRIu64 " err=%d",
            label ? label : "stream",
            remaining_ms,
            rc);
        return -1;
    }
    if (out_err) {
        *out_err = 0;
    }
    return 0;
}

static bool payload_is_snappy_framed(const uint8_t *data, size_t len) {
    return lantern_snappy_is_framed(data, len);
}

static int decode_status_payload(
    const uint8_t *data,
    size_t data_len,
    LanternStatusMessage *out_status) {
    if (!data || !out_status) {
        return -1;
    }
    if (!payload_is_snappy_framed(data, data_len)) {
        return -1;
    }
    if (lantern_network_status_decode_snappy(out_status, data, data_len) != 0) {
        return -1;
    }
    return 0;
}

static int read_stream_exact(
    libp2p_stream_t *stream,
    const struct lantern_log_metadata *meta,
    const char *label,
    uint8_t *buffer,
    size_t buffer_len,
    uint64_t deadline_ms,
    size_t *out_read,
    ssize_t *out_err) {
    if (!stream || !buffer) {
        if (out_err) {
            *out_err = LIBP2P_ERR_NULL_PTR;
        }
        return -1;
    }
    if (buffer_len == 0) {
        if (out_read) {
            *out_read = 0;
        }
        if (out_err) {
            *out_err = 0;
        }
        return 0;
    }

    size_t collected = 0;
    while (collected < buffer_len) {
        if (set_stream_deadline_remaining(stream, deadline_ms, meta, label, out_err) != 0) {
            if (out_read) {
                *out_read = collected;
            }
            return -1;
        }
        ssize_t n = libp2p_stream_read(stream, buffer + collected, buffer_len - collected);
        if (n > 0) {
            collected += (size_t)n;
            continue;
        }
        if (n == (ssize_t)LIBP2P_ERR_AGAIN) {
            continue;
        }
        (void)libp2p_stream_set_deadline(stream, 0);
        if (out_read) {
            *out_read = collected;
        }
        if (out_err) {
            *out_err = (n == 0) ? (ssize_t)LIBP2P_ERR_EOF : n;
        }
        const char *err_name = stream_error_name(out_err ? *out_err : n);
        lantern_log_warn(
            "reqresp",
            meta,
            "%s read failed err=%s(%zd) collected=%zu/%zu",
            label ? label : "stream",
            err_name ? err_name : "unknown",
            out_err ? *out_err : n,
            collected,
            buffer_len);
        return -1;
    }
    (void)libp2p_stream_set_deadline(stream, 0);
    if (out_read) {
        *out_read = collected;
    }
    if (out_err) {
        *out_err = 0;
    }
    return 0;
}

static bool accept_legacy_declared_len(
    const uint8_t *buffer,
    size_t offset,
    uint64_t declared_len,
    size_t *out_uncompressed)
{
    if (!buffer || offset == 0 || declared_len == 0)
    {
        return false;
    }
    if (offset != (size_t)declared_len)
    {
        return false;
    }
    size_t raw_len = 0;
    if (lantern_snappy_uncompressed_length(buffer, offset, &raw_len) != LANTERN_SNAPPY_OK)
    {
        return false;
    }
    if (out_uncompressed)
    {
        *out_uncompressed = raw_len;
    }
    return true;
}

static int read_snappy_framed_payload(
    libp2p_stream_t *stream,
    const char *label,
    const struct lantern_log_metadata *meta,
    uint64_t declared_len,
    uint64_t deadline_ms,
    uint8_t **out_data,
    size_t *out_len,
    bool *out_legacy_len,
    ssize_t *out_err) {
    if (!stream || !out_data || !out_len) {
        if (out_err) {
            *out_err = LIBP2P_ERR_NULL_PTR;
        }
        return -1;
    }
    if (out_legacy_len) {
        *out_legacy_len = false;
    }
    if (declared_len > LANTERN_REQRESP_MAX_CHUNK_BYTES || declared_len > SIZE_MAX) {
        if (out_err) {
            *out_err = LIBP2P_ERR_MSG_TOO_LARGE;
        }
        lantern_log_warn(
            "reqresp",
            meta,
            "%s declared uncompressed length invalid=%" PRIu64,
            label ? label : "stream",
            declared_len);
        return -1;
    }

    if (declared_len == 0) {
        uint8_t header[4];
        size_t read_len = 0;
        if (read_stream_exact(
                stream,
                meta,
                label ? label : "stream",
                header,
                sizeof(header),
                deadline_ms,
                &read_len,
                out_err)
            != 0) {
            return -1;
        }
        uint8_t chunk_type = header[0];
        uint32_t chunk_len = (uint32_t)header[1]
            | ((uint32_t)header[2] << 8u)
            | ((uint32_t)header[3] << 16u);
        if (chunk_type != 0xffu || chunk_len != 6u) {
            if (out_err) {
                *out_err = LIBP2P_ERR_INTERNAL;
            }
            lantern_log_warn(
                "reqresp",
                meta,
                "%s snappy stream identifier invalid type=0x%02x len=%u",
                label ? label : "stream",
                (unsigned)chunk_type,
                chunk_len);
            return -1;
        }
        uint8_t payload[6];
        if (read_stream_exact(
                stream,
                meta,
                label ? label : "stream",
                payload,
                sizeof(payload),
                deadline_ms,
                &read_len,
                out_err)
            != 0) {
            return -1;
        }
        uint8_t *buffer = (uint8_t *)malloc(10u);
        if (!buffer) {
            if (out_err) {
                *out_err = -ENOMEM;
            }
            lantern_log_warn(
                "reqresp",
                meta,
                "%s payload allocation failed bytes=10",
                label ? label : "stream");
            return -1;
        }
        memcpy(buffer, header, sizeof(header));
        memcpy(buffer + sizeof(header), payload, sizeof(payload));
        if (!lantern_snappy_is_framed(buffer, 10u)) {
            free(buffer);
            if (out_err) {
                *out_err = LIBP2P_ERR_INTERNAL;
            }
            lantern_log_warn(
                "reqresp",
                meta,
                "%s payload missing snappy framing bytes=10",
                label ? label : "stream");
            return -1;
        }
        if (out_err) {
            *out_err = 0;
        }
        *out_data = buffer;
        *out_len = 10u;
        return 0;
    }

    size_t max_compressed = 0;
    if (lantern_snappy_max_compressed_size((size_t)declared_len, &max_compressed) != LANTERN_SNAPPY_OK
        || max_compressed == 0) {
        if (out_err) {
            *out_err = LIBP2P_ERR_INTERNAL;
        }
        lantern_log_warn(
            "reqresp",
            meta,
            "%s failed to compute snappy max size declared_uncompressed=%" PRIu64,
            label ? label : "stream",
            declared_len);
        return -1;
    }

    uint8_t *buffer = (uint8_t *)malloc(max_compressed);
    if (!buffer) {
        if (out_err) {
            *out_err = -ENOMEM;
        }
        lantern_log_warn(
            "reqresp",
            meta,
            "%s payload allocation failed bytes=%zu",
            label ? label : "stream",
            max_compressed);
        return -1;
    }

    size_t offset = 0;
    uint64_t uncompressed_total = 0;
    bool saw_data_chunk = false;
    size_t chunk_index = 0;
    const uint32_t max_chunk_len = 0x00ffffffu;

    while (!saw_data_chunk || uncompressed_total < declared_len) {
        uint8_t header[4];
        size_t read_len = 0;
        ssize_t read_err = 0;
        if (read_stream_exact(
                stream,
                meta,
                label ? label : "stream",
                header,
                sizeof(header),
                deadline_ms,
                &read_len,
                &read_err)
            != 0) {
            size_t legacy_uncompressed = 0;
            if ((read_err == (ssize_t)LIBP2P_ERR_EOF
                    || read_err == (ssize_t)LIBP2P_ERR_CLOSED
                    || read_err == (ssize_t)LIBP2P_ERR_RESET)
                && accept_legacy_declared_len(buffer, offset, declared_len, &legacy_uncompressed))
            {
                lantern_log_warn(
                    "reqresp",
                    meta,
                    "%s legacy reqresp length declared=%" PRIu64 " compressed=%zu uncompressed=%zu",
                    label ? label : "stream",
                    declared_len,
                    offset,
                    legacy_uncompressed);
                if (out_legacy_len) {
                    *out_legacy_len = true;
                }
                if (out_err) {
                    *out_err = 0;
                }
                *out_data = buffer;
                *out_len = offset;
                return 0;
            }
            free(buffer);
            if (out_err) {
                *out_err = read_err;
            }
            return -1;
        }

        uint8_t chunk_type = header[0];
        uint32_t chunk_len = (uint32_t)header[1]
            | ((uint32_t)header[2] << 8u)
            | ((uint32_t)header[3] << 16u);

        if (chunk_len > max_chunk_len) {
            free(buffer);
            if (out_err) {
                *out_err = LIBP2P_ERR_MSG_TOO_LARGE;
            }
            lantern_log_warn(
                "reqresp",
                meta,
                "%s snappy chunk length invalid=%u",
                label ? label : "stream",
                chunk_len);
            return -1;
        }

        if (offset + sizeof(header) + (size_t)chunk_len > max_compressed) {
            free(buffer);
            if (out_err) {
                *out_err = LIBP2P_ERR_MSG_TOO_LARGE;
            }
            lantern_log_warn(
                "reqresp",
                meta,
                "%s snappy payload exceeds max_compressed bytes=%zu",
                label ? label : "stream",
                max_compressed);
            return -1;
        }

        memcpy(buffer + offset, header, sizeof(header));
        offset += sizeof(header);

        if (chunk_len > 0) {
            if (read_stream_exact(
                    stream,
                    meta,
                    label ? label : "stream",
                    buffer + offset,
                    (size_t)chunk_len,
                    deadline_ms,
                    &read_len,
                    out_err)
                != 0) {
                free(buffer);
                return -1;
            }
        }

        const uint8_t *chunk_payload = buffer + offset;
        offset += (size_t)chunk_len;
        chunk_index++;

        uint64_t chunk_uncompressed = 0;
        bool contributes = false;
        switch (chunk_type) {
        case 0xffu: /* stream identifier */
            if (chunk_len != 6u) {
                free(buffer);
                if (out_err) {
                    *out_err = LIBP2P_ERR_INTERNAL;
                }
                lantern_log_warn(
                    "reqresp",
                    meta,
                    "%s snappy stream identifier length invalid=%u",
                    label ? label : "stream",
                    chunk_len);
                return -1;
            }
            break;
        case 0x00u: /* compressed */
            if (chunk_len < 4u) {
                free(buffer);
                if (out_err) {
                    *out_err = LIBP2P_ERR_INTERNAL;
                }
                lantern_log_warn(
                    "reqresp",
                    meta,
                    "%s snappy compressed chunk too short len=%u",
                    label ? label : "stream",
                    chunk_len);
                return -1;
            }
            {
                size_t raw_len = 0;
                int rc = lantern_snappy_uncompressed_length_raw(
                    chunk_payload + 4u,
                    (size_t)chunk_len - 4u,
                    &raw_len);
                if (rc != LANTERN_SNAPPY_OK) {
                    free(buffer);
                    if (out_err) {
                        *out_err = LIBP2P_ERR_INTERNAL;
                    }
                    lantern_log_warn(
                        "reqresp",
                        meta,
                        "%s snappy compressed chunk length decode failed rc=%d len=%u",
                        label ? label : "stream",
                        rc,
                        chunk_len);
                    return -1;
                }
                chunk_uncompressed = (uint64_t)raw_len;
                contributes = true;
            }
            break;
        case 0x01u: /* uncompressed */
            if (chunk_len < 4u) {
                free(buffer);
                if (out_err) {
                    *out_err = LIBP2P_ERR_INTERNAL;
                }
                lantern_log_warn(
                    "reqresp",
                    meta,
                    "%s snappy uncompressed chunk too short len=%u",
                    label ? label : "stream",
                    chunk_len);
                return -1;
            }
            chunk_uncompressed = (uint64_t)(chunk_len - 4u);
            contributes = true;
            break;
        default:
            if (chunk_type >= 0x80u && chunk_type <= 0xfeu) {
                /* skippable chunk - ignore */
                break;
            }
            free(buffer);
            if (out_err) {
                *out_err = LIBP2P_ERR_INTERNAL;
            }
            lantern_log_warn(
                "reqresp",
                meta,
                "%s snappy chunk type unsupported=0x%02x",
                label ? label : "stream",
                (unsigned)chunk_type);
            return -1;
        }

        if (contributes) {
            saw_data_chunk = true;
            if (chunk_uncompressed > UINT64_MAX - uncompressed_total) {
                free(buffer);
                if (out_err) {
                    *out_err = LIBP2P_ERR_INTERNAL;
                }
                lantern_log_warn(
                    "reqresp",
                    meta,
                    "%s snappy uncompressed length overflow",
                    label ? label : "stream");
                return -1;
            }
            uncompressed_total += chunk_uncompressed;
        }

        lantern_log_trace(
            "reqresp",
            meta,
            "%s snappy chunk[%zu] type=0x%02x len=%u uncompressed=%" PRIu64 " total=%" PRIu64 "/%" PRIu64,
            label ? label : "stream",
            chunk_index,
            (unsigned)chunk_type,
            chunk_len,
            chunk_uncompressed,
            uncompressed_total,
            declared_len);

        if (uncompressed_total > declared_len) {
            size_t legacy_uncompressed = 0;
            if (accept_legacy_declared_len(buffer, offset, declared_len, &legacy_uncompressed)) {
                lantern_log_warn(
                    "reqresp",
                    meta,
                    "%s legacy reqresp length declared=%" PRIu64 " compressed=%zu uncompressed=%zu",
                    label ? label : "stream",
                    declared_len,
                    offset,
                    legacy_uncompressed);
                if (out_legacy_len) {
                    *out_legacy_len = true;
                }
                if (out_err) {
                    *out_err = 0;
                }
                *out_data = buffer;
                *out_len = offset;
                return 0;
            }
            free(buffer);
            if (out_err) {
                *out_err = LIBP2P_ERR_INTERNAL;
            }
            lantern_log_warn(
                "reqresp",
                meta,
                "%s snappy uncompressed length exceeded declared=%" PRIu64 " got=%" PRIu64,
                label ? label : "stream",
                declared_len,
                uncompressed_total);
            return -1;
        }

        if (offset >= max_compressed && uncompressed_total < declared_len) {
            free(buffer);
            if (out_err) {
                *out_err = LIBP2P_ERR_MSG_TOO_LARGE;
            }
            lantern_log_warn(
                "reqresp",
                meta,
                "%s snappy payload truncated bytes=%zu",
                label ? label : "stream",
                offset);
            return -1;
        }
    }

    if (!lantern_snappy_is_framed(buffer, offset)) {
        lantern_log_warn(
            "reqresp",
            meta,
            "%s payload missing snappy framing bytes=%zu",
            label ? label : "stream",
            offset);
        log_snappy_frame_summary(label, meta, buffer, offset);
        free(buffer);
        if (out_err) {
            *out_err = LIBP2P_ERR_INTERNAL;
        }
        return -1;
    }

    lantern_log_debug(
        "reqresp",
        meta,
        "%s snappy payload read compressed=%zu uncompressed=%" PRIu64,
        label ? label : "stream",
        offset,
        uncompressed_total);

    if (out_err) {
        *out_err = 0;
    }
    *out_data = buffer;
    *out_len = offset;
    return 0;
}

static int read_length_prefixed_stream(
    libp2p_stream_t *stream,
    const char *label,
    const char *peer_text,
    uint8_t **out_data,
    size_t *out_len,
    bool *out_legacy_len,
    ssize_t *out_err) {
    if (!stream || !out_data || !out_len) {
        if (out_err) {
            *out_err = LIBP2P_ERR_NULL_PTR;
        }
        return -1;
    }
    if (out_legacy_len) {
        *out_legacy_len = false;
    }

    struct lantern_log_metadata meta = {.peer = peer_text};
    uint64_t start_ms = reqresp_now_ms();
    uint64_t ttfb_deadline_ms = start_ms + LANTERN_REQRESP_TTFB_TIMEOUT_MS;
    uint64_t resp_deadline_ms = start_ms + LANTERN_REQRESP_RESP_TIMEOUT_MS;
    uint8_t header[LANTERN_REQRESP_HEADER_MAX_BYTES];
    size_t header_used = 0;
    size_t consumed = 0;
    uint64_t payload_len = 0;
    ssize_t last_err = 0;

    if (out_err) {
        *out_err = 0;
    }

    while (header_used < sizeof(header)) {
        uint64_t deadline_ms = header_used == 0 ? ttfb_deadline_ms : resp_deadline_ms;
        if (set_stream_deadline_remaining(stream, deadline_ms, &meta, label, out_err) != 0) {
            last_err = out_err ? *out_err : (ssize_t)LIBP2P_ERR_TIMEOUT;
            break;
        }
        ssize_t n = libp2p_stream_read(stream, &header[header_used], 1);
        if (n == 1) {
            header_used += 1;
            lantern_log_trace(
                "reqresp",
                &meta,
                "%s header byte[%zu]=0x%02x",
                label ? label : "stream",
                header_used - 1,
                (unsigned)header[header_used - 1]);
            if (unsigned_varint_decode(header, header_used, &payload_len, &consumed) == UNSIGNED_VARINT_OK) {
                lantern_log_trace(
                    "reqresp",
                    &meta,
                    "%s header decoded uncompressed_len=%" PRIu64,
                    label ? label : "stream",
                    payload_len);
                char header_hex[(LANTERN_REQRESP_HEADER_MAX_BYTES * 2u) + 1u];
                header_hex[0] = '\0';
                if (lantern_bytes_to_hex(header, consumed, header_hex, sizeof(header_hex), 0) != 0) {
                    header_hex[0] = '\0';
                }
                lantern_log_debug(
                    "reqresp",
                    &meta,
                    "%s header decoded uncompressed_len=%" PRIu64 " header_len=%zu header_hex=%s",
                    label ? label : "stream",
                    payload_len,
                    consumed,
                    header_hex[0] ? header_hex : "-");
                break;
            }
            continue;
        }
        if (n == (ssize_t)LIBP2P_ERR_AGAIN) {
            continue;
        }
        if (n == 0 || n == (ssize_t)LIBP2P_ERR_EOF || n == (ssize_t)LIBP2P_ERR_CLOSED || n == (ssize_t)LIBP2P_ERR_RESET) {
            last_err = n == 0 ? (ssize_t)LIBP2P_ERR_EOF : n;
            break;
        }
        last_err = n;
        break;
    }
    (void)libp2p_stream_set_deadline(stream, 0);

    if (header_used == sizeof(header)
        && unsigned_varint_decode(header, header_used, &payload_len, &consumed) != UNSIGNED_VARINT_OK) {
        last_err = LIBP2P_ERR_INTERNAL;
    }

    if (payload_len > LANTERN_REQRESP_MAX_CHUNK_BYTES || payload_len > SIZE_MAX) {
        if (last_err == 0) {
            last_err = LIBP2P_ERR_MSG_TOO_LARGE;
        }
        lantern_log_warn(
            "reqresp",
            &meta,
            "%s header invalid uncompressed_len=%" PRIu64,
            label ? label : "stream",
            payload_len);
    }

    if (last_err != 0) {
        if (out_err) {
            *out_err = last_err;
        }
        const char *err_name = stream_error_name(last_err);
        lantern_log_warn(
            "reqresp",
            &meta,
            "%s header read failed err=%s(%zd) bytes=%zu",
            label ? label : "stream",
            err_name ? err_name : "unknown",
            last_err,
            header_used);
        return -1;
    }

    if (read_snappy_framed_payload(
            stream,
            label,
            &meta,
            payload_len,
            resp_deadline_ms,
            out_data,
            out_len,
            out_legacy_len,
            out_err)
        != 0) {
        return -1;
    }
    lantern_log_debug(
        "reqresp",
        &meta,
        "%s payload read complete bytes=%zu",
        label ? label : "stream",
        *out_len);
    return 0;
}

static int write_stream_all(
    libp2p_stream_t *stream,
    const uint8_t *data,
    size_t length,
    const char *protocol_id,
    const char *phase,
    const char *peer_hint) {
    if (!stream || (!data && length > 0)) {
        return LIBP2P_ERR_NULL_PTR;
    }

    char peer_text[128];
    peer_text[0] = '\0';
    if (!peer_hint || peer_hint[0] == '\0') {
        const peer_id_t *peer = libp2p_stream_remote_peer(stream);
        if (peer && write_legacy_peer_id_text(peer, peer_text, sizeof(peer_text)) < 0) {
            peer_text[0] = '\0';
        }
    }
    const char *peer_label = (peer_hint && peer_hint[0]) ? peer_hint : (peer_text[0] ? peer_text : NULL);
    struct lantern_log_metadata meta = {
        .peer = peer_label,
    };

    lantern_log_trace(
        "reqresp",
        &meta,
        "%s write start bytes=%zu protocol=%s",
        phase ? phase : "stream",
        length,
        protocol_id ? protocol_id : "-");

    size_t offset = 0;
    while (offset < length) {
        ssize_t written = libp2p_stream_write(stream, data + offset, length - offset);
        if (written > 0) {
            offset += (size_t)written;
            lantern_log_trace(
                "reqresp",
                &meta,
                "%s write progress chunk=%zd offset=%zu/%zu",
                phase ? phase : "stream",
                written,
                offset,
                length);
            continue;
        }
        if (written == (ssize_t)LIBP2P_ERR_AGAIN || written == (ssize_t)LIBP2P_ERR_TIMEOUT) {
            continue;
        }

        ssize_t err = written;
        if (written == 0) {
            err = LIBP2P_ERR_EOF;
        }

        const char *err_name = stream_error_name(err);
        lantern_log_warn(
            "reqresp",
            &meta,
            "%s write failed protocol=%s err=%s(%zd) offset=%zu/%zu",
            phase ? phase : "stream",
            protocol_id ? protocol_id : "-",
            err_name ? err_name : "unknown",
            err,
            offset,
            length);
        if (protocol_id) {
            log_stream_error("write", protocol_id, peer_label);
        }
        return (int)err;
    }
    lantern_log_debug(
        "reqresp",
        &meta,
        "%s write complete bytes=%zu protocol=%s",
        phase ? phase : "stream",
        length,
        protocol_id ? protocol_id : "-");
    return 0;
}

static int send_response_chunk(
    libp2p_stream_t *stream,
    const struct lantern_log_metadata *meta,
    const char *protocol_id,
    const char *phase,
    const char *peer_text,
    bool include_response_code,
    uint8_t response_code,
    bool legacy_len,
    const uint8_t *payload,
    size_t payload_len,
    size_t raw_len) {
    if (!stream) {
        return -1;
    }

    bool include_code = include_response_code;

    size_t declared_len = legacy_len ? payload_len : raw_len;

    lantern_log_debug(
        "reqresp",
        meta,
        "%s framing include_code=%s code=%u payload_len=%zu raw_len=%zu declared_len=%zu legacy_len=%s",
        phase ? phase : "response",
        include_code ? "true" : "false",
        (unsigned)response_code,
        payload_len,
        raw_len,
        declared_len,
        legacy_len ? "true" : "false");

    /* The varint prefix indicates the uncompressed payload size (SSZ length). */
    uint8_t header[LANTERN_REQRESP_HEADER_MAX_BYTES];
    size_t header_len = 0;
    if (unsigned_varint_encode(declared_len, header, sizeof(header), &header_len) != UNSIGNED_VARINT_OK) {
        lantern_log_error(
            "reqresp",
            meta,
            "%s payload header encode failed bytes=%zu",
            phase ? phase : "response",
            declared_len);
        return -1;
    }

    size_t frame_len = header_len + payload_len + (include_code ? 1u : 0u);
    uint8_t *frame = (uint8_t *)malloc(frame_len > 0 ? frame_len : 1u);
    if (!frame) {
        lantern_log_error(
            "reqresp",
            meta,
            "%s frame allocation failed bytes=%zu",
            phase ? phase : "response",
            frame_len);
        return -1;
    }
    size_t frame_offset = 0;
    if (include_code) {
        frame[frame_offset++] = response_code;
    }
    if (header_len > 0) {
        memcpy(frame + frame_offset, header, header_len);
        frame_offset += header_len;
    }
    if (payload_len > 0) {
        memcpy(frame + frame_offset, payload, payload_len);
    }

    /* Debug aid: summarize the outgoing frame (response path) so we can match consumer expectations */
    if (protocol_id && strstr(protocol_id, "/status/1/ssz_snappy") != NULL) {
        char frame_hex[(LANTERN_STATUS_PREVIEW_BYTES * 2u) + 1u];
        frame_hex[0] = '\0';
        size_t preview = frame_len < LANTERN_STATUS_PREVIEW_BYTES ? frame_len : LANTERN_STATUS_PREVIEW_BYTES;
        if (preview > 0
            && lantern_bytes_to_hex(frame, preview, frame_hex, sizeof(frame_hex), 0) != 0) {
            frame_hex[0] = '\0';
        }
        lantern_log_debug(
            "reqresp",
            meta,
            "%s frame summary code_byte=0x%02x header_len=%zu payload_len=%zu frame_len=%zu%s%s",
            phase ? phase : "response",
            (unsigned)response_code,
            header_len,
            payload_len,
            frame_len,
            frame_hex[0] ? " frame_hex=" : "",
            frame_hex[0] ? frame_hex : "");
    }

    if (write_stream_all(
            stream,
            frame,
            frame_len,
            protocol_id,
            phase ? phase : "response frame",
            peer_text)
        != 0) {
        free(frame);
        lantern_log_error(
            "reqresp",
            meta,
            "%s frame write failed bytes=%zu",
            phase ? phase : "response",
            frame_len);
        return -1;
    }
    free(frame);

    lantern_log_trace(
        "reqresp",
        meta,
        "%s response sent bytes=%zu",
        phase ? phase : "response",
        payload_len);

    return 0;
}

static int send_error_response(
    libp2p_stream_t *stream,
    const struct lantern_log_metadata *meta,
    const char *protocol_id,
    const char *peer_text,
    bool legacy_len,
    uint8_t response_code,
    const char *message) {
    if (!stream) {
        return -1;
    }
    const uint8_t *payload = (const uint8_t *)(message ? message : "");
    size_t raw_len = message ? strlen(message) : 0;

    size_t max_payload = 0;
    if (lantern_snappy_max_compressed_size(raw_len, &max_payload) != LANTERN_SNAPPY_OK) {
        lantern_log_warn(
            "reqresp",
            meta,
            "error response snappy size failed bytes=%zu",
            raw_len);
        return -1;
    }
    if (max_payload == 0) {
        max_payload = 1u;
    }

    uint8_t *compressed = (uint8_t *)malloc(max_payload);
    if (!compressed) {
        lantern_log_warn(
            "reqresp",
            meta,
            "error response allocation failed bytes=%zu",
            max_payload);
        return -1;
    }

    size_t written = 0;
    if (lantern_snappy_compress(payload, raw_len, compressed, max_payload, &written) != LANTERN_SNAPPY_OK) {
        free(compressed);
        lantern_log_warn(
            "reqresp",
            meta,
            "error response compress failed bytes=%zu",
            raw_len);
        return -1;
    }

    int rc = send_response_chunk(
        stream,
        meta,
        protocol_id,
        "error response",
        peer_text,
        true,
        response_code,
        legacy_len,
        compressed,
        written,
        raw_len);
    free(compressed);
    return rc;
}

static void status_request_notify_failure(
    struct lantern_reqresp_service *service,
    const char *peer_text,
    int error) {
    if (!service || !service->callbacks.status_failure) {
        return;
    }
    service->callbacks.status_failure(
        service->callbacks.context,
        peer_text,
        error);
}


static void close_stream(libp2p_stream_t *stream) {
    if (!stream) {
        return;
    }
    int rc = libp2p_stream_close(stream);
    (void)rc;
    /* Guard against concurrent host-side destruction: prefer async release.
       If the stream wasn't retained, skip free to avoid double-free when the
       underlying connection has already torn down the stream. (Potential
       small leak is preferable to a hard crash on use-after-free.) */
    (void)libp2p__stream_release_async(stream);
}

static void log_stream_error(const char *phase, const char *protocol_id, const char *peer_id) {
    lantern_log_error(
        "network",
        &(const struct lantern_log_metadata){.peer = peer_id},
        "%s %s request failed",
        protocol_id ? protocol_id : "unknown",
        phase ? phase : "processing");
}

static void handle_remote_status(
    struct lantern_reqresp_service *service,
    const LanternStatusMessage *status,
    const char *peer_text) {
    if (!service || !status) {
        return;
    }
    if (service->callbacks.handle_status) {
        service->callbacks.handle_status(service->callbacks.context, status, peer_text);
    }
}

static void *status_worker(void *arg) {
    struct status_stream_ctx *ctx = (struct status_stream_ctx *)arg;
    if (!ctx) {
        return NULL;
    }
    struct lantern_reqresp_service *service = ctx->service;
    libp2p_stream_t *stream = ctx->stream;
    const char *protocol_id =
        ctx->protocol_id ? ctx->protocol_id : LANTERN_STATUS_PROTOCOL_ID;
    uint64_t trace_id = ctx->debug_trace_id;
    free(ctx);

    if (!service || !stream) {
        close_stream(stream);
        return NULL;
    }

    char peer_text[128];
    describe_peer(libp2p_stream_remote_peer(stream), peer_text, sizeof(peer_text));

    bool include_response_code = true;

    const struct lantern_log_metadata stream_meta = {.peer = peer_text[0] ? peer_text : NULL};
    lantern_log_debug(
        "reqresp",
        &stream_meta,
        "status[%" PRIu64 "] stream protocol=%s",
        trace_id,
        protocol_id ? protocol_id : "-");

    lantern_log_trace(
        "reqresp",
        &(const struct lantern_log_metadata){.peer = peer_text},
        "status[%" PRIu64 "] stream opened",
        trace_id);

    libp2p_stream_set_read_interest(stream, true);

    uint8_t *request = NULL;
    size_t request_len = 0;
    ssize_t read_err = 0;
    bool request_legacy_len = false;
    char trace_label[64];
    snprintf(trace_label, sizeof(trace_label), "status[%" PRIu64 "]", trace_id);
    if (read_length_prefixed_stream(
            stream,
            trace_label,
            peer_text,
            &request,
            &request_len,
            &request_legacy_len,
            &read_err)
        != 0) {
        const char *err_name = read_err == 0 ? "empty" : stream_error_name(read_err);
        lantern_log_warn(
            "reqresp",
            &(const struct lantern_log_metadata){.peer = peer_text},
            "status[%" PRIu64 "] read failed err=%s(%zd)",
            trace_id,
            err_name ? err_name : "unknown",
            read_err);
        log_stream_error("read", protocol_id, peer_text[0] ? peer_text : NULL);
        (void)send_error_response(
            stream,
            &stream_meta,
            protocol_id,
            peer_text[0] ? peer_text : NULL,
            false,
            LANTERN_REQRESP_RESPONSE_INVALID_REQUEST,
            "invalid request");
        close_stream(stream);
        return NULL;
    }
    if (request_legacy_len && service && service->callbacks.context && peer_text[0]) {
        lantern_client_mark_peer_reqresp_legacy(
            (struct lantern_client *)service->callbacks.context,
            peer_text);
    }
    bool use_legacy_len = request_legacy_len;
    if (!use_legacy_len && service && service->callbacks.context && peer_text[0]) {
        use_legacy_len = lantern_client_peer_reqresp_legacy(
            (struct lantern_client *)service->callbacks.context,
            peer_text);
    }

    lantern_log_debug(
        "reqresp",
        &stream_meta,
        "status[%" PRIu64 "] request payload_len=%zu",
        trace_id,
        request_len);

    snprintf(trace_label, sizeof(trace_label), "status[%" PRIu64 "] request raw", trace_id);
    log_payload_preview(trace_label, peer_text, request, request_len);

    LanternStatusMessage remote_status;
    memset(&remote_status, 0, sizeof(remote_status));
    if (request_len == 0
        || decode_status_payload(request, request_len, &remote_status) != 0) {
        snprintf(trace_label, sizeof(trace_label), "status[%" PRIu64 "] request decode_failed", trace_id);
        log_payload_preview(trace_label, peer_text, request, request_len);
        free(request);
        log_stream_error("decode", protocol_id, peer_text[0] ? peer_text : NULL);
        (void)send_error_response(
            stream,
            &stream_meta,
            protocol_id,
            peer_text[0] ? peer_text : NULL,
            use_legacy_len,
            LANTERN_REQRESP_RESPONSE_INVALID_REQUEST,
            "invalid request");
        close_stream(stream);
        return NULL;
    }
    free(request);

    lantern_log_debug(
        "reqresp",
        &stream_meta,
        "status[%" PRIu64 "] request framing=framed include_response_code=%s",
        trace_id,
        include_response_code ? "true" : "false");

    char head_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    if (lantern_bytes_to_hex(remote_status.head.root.bytes, LANTERN_ROOT_SIZE, head_hex, sizeof(head_hex), 1) != 0) {
        head_hex[0] = '\0';
    }
    char finalized_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    if (lantern_bytes_to_hex(
            remote_status.finalized.root.bytes,
            LANTERN_ROOT_SIZE,
            finalized_hex,
            sizeof(finalized_hex),
            1)
        != 0) {
        finalized_hex[0] = '\0';
    }
    lantern_log_trace(
        "reqresp",
        &(const struct lantern_log_metadata){.peer = peer_text},
        "status[%" PRIu64 "] decoded head_slot=%" PRIu64 " head_root=%s finalized_slot=%" PRIu64 " finalized_root=%s",
        trace_id,
        remote_status.head.slot,
        head_hex[0] ? head_hex : "0x0",
        remote_status.finalized.slot,
        finalized_hex[0] ? finalized_hex : "0x0");

    handle_remote_status(service, &remote_status, peer_text);

    LanternStatusMessage response;
    memset(&response, 0, sizeof(response));
    if (!service->callbacks.build_status
        || service->callbacks.build_status(service->callbacks.context, &response) != 0) {
        log_stream_error("status", protocol_id, peer_text);
        (void)send_error_response(
            stream,
            &stream_meta,
            protocol_id,
            peer_text[0] ? peer_text : NULL,
            use_legacy_len,
            LANTERN_REQRESP_RESPONSE_SERVER_ERROR,
            "server error");
        close_stream(stream);
        return NULL;
    }

    uint8_t raw_status[2u * LANTERN_CHECKPOINT_SSZ_SIZE];
    size_t response_raw_len = 0;
    if (lantern_network_status_encode(&response, raw_status, sizeof(raw_status), &response_raw_len) != 0) {
        log_stream_error("encode", protocol_id, peer_text);
        (void)send_error_response(
            stream,
            &stream_meta,
            protocol_id,
            peer_text[0] ? peer_text : NULL,
            use_legacy_len,
            LANTERN_REQRESP_RESPONSE_SERVER_ERROR,
            "server error");
        close_stream(stream);
        return NULL;
    }

    size_t max_payload = response_raw_len;
    if (lantern_snappy_max_compressed_size(response_raw_len, &max_payload) != LANTERN_SNAPPY_OK) {
        log_stream_error("encode", protocol_id, peer_text);
        (void)send_error_response(
            stream,
            &stream_meta,
            protocol_id,
            peer_text[0] ? peer_text : NULL,
            use_legacy_len,
            LANTERN_REQRESP_RESPONSE_SERVER_ERROR,
            "server error");
        close_stream(stream);
        return NULL;
    }

    uint8_t *buffer = (uint8_t *)malloc(max_payload > 0 ? max_payload : 1u);
    if (!buffer) {
        log_stream_error("encode", protocol_id, peer_text);
        (void)send_error_response(
            stream,
            &stream_meta,
            protocol_id,
            peer_text[0] ? peer_text : NULL,
            use_legacy_len,
            LANTERN_REQRESP_RESPONSE_SERVER_ERROR,
            "server error");
        close_stream(stream);
        return NULL;
    }

    size_t written = 0;
    if (lantern_snappy_compress(raw_status, response_raw_len, buffer, max_payload, &written)
        != LANTERN_SNAPPY_OK) {
        free(buffer);
        log_stream_error("encode", protocol_id, peer_text);
        (void)send_error_response(
            stream,
            &stream_meta,
            protocol_id,
            peer_text[0] ? peer_text : NULL,
            use_legacy_len,
            LANTERN_REQRESP_RESPONSE_SERVER_ERROR,
            "server error");
        close_stream(stream);
        return NULL;
    }

    log_payload_preview("status response raw", peer_text, buffer, written);

    const struct lantern_log_metadata meta = {.peer = peer_text};
    lantern_log_debug(
        "reqresp",
        &meta,
        "status response lengths raw=%zu compressed=%zu",
        response_raw_len,
        written);

    if (send_response_chunk(
            stream,
            &meta,
            protocol_id,
            "status response",
            peer_text[0] ? peer_text : NULL,
            include_response_code,
            LANTERN_REQRESP_RESPONSE_SUCCESS,
            use_legacy_len,
            buffer,
            written,
            response_raw_len)
        != 0) {
        free(buffer);
        log_stream_error("write", protocol_id, peer_text);
        close_stream(stream);
        return NULL;
    }
    free(buffer);
    close_stream(stream);

    lantern_log_debug(
        "network",
        &(const struct lantern_log_metadata){.peer = peer_text},
        "served status request");
    return NULL;
}

static void *status_request_worker(void *arg) {
    struct status_request_worker_args *worker = (struct status_request_worker_args *)arg;
    if (!worker) {
        return NULL;
    }
    struct status_request_ctx *ctx = worker->ctx;
    libp2p_stream_t *stream = worker->stream;
    free(worker);
    if (!ctx || !stream) {
        if (stream) {
            close_stream(stream);
        }
        status_request_ctx_free(ctx);
        return NULL;
    }

    struct lantern_reqresp_service *service = ctx->service;
    char peer_text[sizeof(ctx->peer_text)];
    memcpy(peer_text, ctx->peer_text, sizeof(peer_text));
    if (peer_text[sizeof(peer_text) - 1] != '\0') {
        peer_text[sizeof(peer_text) - 1] = '\0';
    }
    struct lantern_log_metadata meta = {
        .peer = peer_text[0] ? peer_text : NULL,
    };
    uint64_t trace_id = ctx->debug_trace_id;
    int failure_code = LIBP2P_ERR_INTERNAL;
    int rc = 0;

    LanternStatusMessage local_status;
    memset(&local_status, 0, sizeof(local_status));
    if (!service->callbacks.build_status
        || service->callbacks.build_status(service->callbacks.context, &local_status) != 0) {
        lantern_log_warn(
            "reqresp",
            &meta,
            "failed to build local status for request");
        goto finish;
    }

    uint8_t raw_status[2u * LANTERN_CHECKPOINT_SSZ_SIZE];
    size_t payload_raw_len = 0;
    if (lantern_network_status_encode(&local_status, raw_status, sizeof(raw_status), &payload_raw_len) != 0) {
        lantern_log_error(
            "reqresp",
            &meta,
            "failed to encode status request");
        goto finish;
    }

    size_t max_payload = 0;
    int max_rc = lantern_snappy_max_compressed_size(payload_raw_len, &max_payload);
    if (max_rc != LANTERN_SNAPPY_OK) {
        lantern_log_error(
            "reqresp",
            &meta,
            "failed to compute snappy size for status request");
        goto finish;
    }

    uint8_t *payload = (uint8_t *)malloc(max_payload > 0 ? max_payload : 1u);
    if (!payload) {
        lantern_log_error(
            "reqresp",
            &meta,
            "out of memory building status request");
        goto finish;
    }

    size_t payload_len = 0;
    int snappy_rc = lantern_snappy_compress(raw_status, payload_raw_len, payload, max_payload, &payload_len);
    if (snappy_rc != LANTERN_SNAPPY_OK) {
        lantern_log_error(
            "reqresp",
            &meta,
            "failed to encode status request");
        free(payload);
        goto finish;
    }

    char trace_stage[64];
    snprintf(trace_stage, sizeof(trace_stage), "status[%" PRIu64 "] request snappy", trace_id);
    log_payload_preview(trace_stage, ctx->peer_text, payload, payload_len);

    bool use_legacy_len = false;
    if (service && service->callbacks.context && peer_text[0]) {
        use_legacy_len = lantern_client_peer_reqresp_legacy(
            (struct lantern_client *)service->callbacks.context,
            peer_text);
    }

    /* The varint prefix indicates the uncompressed payload size (SSZ length). */
    uint8_t header[LANTERN_REQRESP_HEADER_MAX_BYTES];
    size_t header_len = 0;
    size_t declared_len = use_legacy_len ? payload_len : payload_raw_len;
    if (unsigned_varint_encode(declared_len, header, sizeof(header), &header_len) != UNSIGNED_VARINT_OK) {
        lantern_log_error(
            "reqresp",
            &meta,
            "failed to encode status request header bytes=%zu",
            declared_len);
        free(payload);
        goto finish;
    }

    char header_hex[(LANTERN_REQRESP_HEADER_MAX_BYTES * 2u) + 1u];
    header_hex[0] = '\0';
    if (lantern_bytes_to_hex(header, header_len, header_hex, sizeof(header_hex), 0) != 0) {
        header_hex[0] = '\0';
    }
    const char *protocol_id = ctx->protocol_id ? ctx->protocol_id : LANTERN_STATUS_PROTOCOL_ID;
    lantern_log_debug(
        "reqresp",
        &meta,
        "status[%" PRIu64 "] request header_len=%zu varint_len=%zu declared_len=%zu raw_len=%zu compressed_len=%zu legacy_len=%s header_hex=%s",
        trace_id,
        header_len,
        declared_len,
        declared_len,
        payload_raw_len,
        payload_len,
        use_legacy_len ? "true" : "false",
        header_hex[0] ? header_hex : "-");

    lantern_log_debug(
        "reqresp",
        &meta,
        "status[%" PRIu64 "] expect_response_code=true",
        trace_id);

    lantern_log_debug(
        "reqresp",
        &meta,
        "status[%" PRIu64 "] sending %s request declared_bytes=%zu raw_bytes=%zu compressed_bytes=%zu legacy_len=%s",
        trace_id,
        protocol_id,
        declared_len,
        payload_raw_len,
        payload_len,
        use_legacy_len ? "true" : "false");

    const char *peer_label = ctx->peer_text[0] ? ctx->peer_text : NULL;
    size_t frame_len = header_len + payload_len;
    uint8_t *frame = (uint8_t *)malloc(frame_len > 0 ? frame_len : 1u);
    if (!frame) {
        lantern_log_error(
            "reqresp",
            &meta,
            "status[%" PRIu64 "] failed to allocate request frame bytes=%zu",
            trace_id,
            frame_len);
        free(payload);
        goto finish;
    }
    if (header_len > 0) {
        memcpy(frame, header, header_len);
    }
    if (payload_len > 0) {
        memcpy(frame + header_len, payload, payload_len);
    }

    rc = write_stream_all(
        stream,
        frame,
        frame_len,
        protocol_id,
        "status request frame",
        peer_label);
    free(frame);
    if (rc != 0) {
        lantern_log_error(
            "reqresp",
            &meta,
            "status[%" PRIu64 "] failed to write request",
            trace_id);
        free(payload);
        failure_code = rc;
        goto finish;
    }
    free(payload);

    /* Half-close the stream (send FIN on write side) to signal we're done sending.
     * This is required by the libp2p req/resp protocol - the responder waits for FIN
     * before processing the request and sending the response.
     * NOTE: We use shutdown_write() not close() - close() would prevent reading the response! */
    rc = libp2p_stream_shutdown_write(stream);
    if (rc != 0) {
        lantern_log_error(
            "reqresp",
            &meta,
            "status[%" PRIu64 "] failed to half-close stream",
            trace_id);
        failure_code = rc;
        goto finish;
    }

    uint8_t *response = NULL;
    size_t response_len = 0;
    ssize_t read_err = 0;
    uint8_t response_code = LANTERN_REQRESP_RESPONSE_SUCCESS;
    rc = lantern_reqresp_read_response_chunk(
        service,
        stream,
        LANTERN_REQRESP_PROTOCOL_STATUS,
        &response,
        &response_len,
        &read_err,
        &response_code,
        NULL);
    if (rc != 0) {
        lantern_log_error(
            "reqresp",
            &meta,
            "status[%" PRIu64 "] failed to read response err=%zd",
            trace_id,
            read_err);
        failure_code = (read_err != 0) ? (int)read_err : LIBP2P_ERR_INTERNAL;
        goto finish;
    }

    lantern_log_debug(
        "reqresp",
        &meta,
        "status[%" PRIu64 "] response received code=%u raw_len=%zu",
        trace_id,
        (unsigned)response_code,
        response_len);

    snprintf(trace_stage, sizeof(trace_stage), "status[%" PRIu64 "] response raw", trace_id);
    log_payload_preview(trace_stage, ctx->peer_text, response, response_len);

    if (response_code != LANTERN_REQRESP_RESPONSE_SUCCESS) {
        lantern_log_error(
            "reqresp",
            &meta,
            "status[%" PRIu64 "] response returned code=%u payload_len=%zu",
            trace_id,
            (unsigned)response_code,
            response_len);
        free(response);
        failure_code = LIBP2P_ERR_INTERNAL;
        goto finish;
    }

    LanternStatusMessage remote_status;
    memset(&remote_status, 0, sizeof(remote_status));
    if (response_len == 0
        || decode_status_payload(response, response_len, &remote_status) != 0) {
        lantern_log_error(
            "reqresp",
            &meta,
            "status[%" PRIu64 "] failed to decode response bytes=%zu",
            trace_id,
            response_len);
        free(response);
        failure_code = LIBP2P_ERR_INTERNAL;
        goto finish;
    }
    free(response);

    char head_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    if (lantern_bytes_to_hex(remote_status.head.root.bytes, LANTERN_ROOT_SIZE, head_hex, sizeof(head_hex), 1) != 0) {
        head_hex[0] = '\0';
    }
    char finalized_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    if (lantern_bytes_to_hex(
            remote_status.finalized.root.bytes,
            LANTERN_ROOT_SIZE,
            finalized_hex,
            sizeof(finalized_hex),
            1)
        != 0) {
        finalized_hex[0] = '\0';
    }
    lantern_log_trace(
        "reqresp",
        &meta,
        "status[%" PRIu64 "] received head_slot=%" PRIu64 " head_root=%s finalized_slot=%" PRIu64 " finalized_root=%s",
        trace_id,
        remote_status.head.slot,
        head_hex[0] ? head_hex : "0x0",
        remote_status.finalized.slot,
        finalized_hex[0] ? finalized_hex : "0x0");

    lantern_log_debug(
        "reqresp",
        &meta,
        "status[%" PRIu64 "] decoded head_slot=%" PRIu64 " finalized_slot=%" PRIu64,
        trace_id,
        remote_status.head.slot,
        remote_status.finalized.slot);

    handle_remote_status(service, &remote_status, ctx->peer_text);
    failure_code = LIBP2P_ERR_OK;

finish:
    close_stream(stream);
    status_request_ctx_free(ctx);
    if (failure_code != LIBP2P_ERR_OK) {
        status_request_notify_failure(service, peer_text[0] ? peer_text : NULL, failure_code);
    }
    return NULL;
}

static void status_request_on_open(libp2p_stream_t *stream, void *user_data, int err) {
    struct status_request_ctx *ctx = (struct status_request_ctx *)user_data;
    struct lantern_log_metadata meta = {
        .peer = (ctx && ctx->peer_text[0]) ? ctx->peer_text : NULL,
    };
    uint64_t trace_id = ctx ? ctx->debug_trace_id : 0;
    const char *protocol_id =
        (ctx && ctx->protocol_id) ? ctx->protocol_id : LANTERN_STATUS_PROTOCOL_ID;
    lantern_log_debug(
        "reqresp",
        &meta,
        "status[%" PRIu64 "] request stream opened protocol=%s err=%d",
        trace_id,
        protocol_id,
        err);
    bool retained = (stream && libp2p__stream_retain_async(stream));
    if (!ctx) {
        if (retained) {
            close_stream(stream);
        }
        return;
    }

    if (err != 0 || !stream) {
        lantern_log_warn(
            "reqresp",
            &meta,
            "status[%" PRIu64 "] failed to open %s stream err=%d",
            trace_id,
            protocol_id,
            err);
        status_request_notify_failure(ctx->service, meta.peer, err != 0 ? err : LIBP2P_ERR_INTERNAL);
        if (retained) {
            close_stream(stream);
            retained = false;
        }
        status_request_ctx_free(ctx);
        return;
    }

    if (!retained) {
        lantern_log_warn(
            "reqresp",
            &meta,
            "status[%" PRIu64 "] stream unavailable (destroying), aborting request",
            trace_id);
        status_request_notify_failure(ctx->service, meta.peer, LIBP2P_ERR_INTERNAL);
        status_request_ctx_free(ctx);
        return;
    }

    struct status_request_worker_args *worker = (struct status_request_worker_args *)malloc(sizeof(*worker));
    if (!worker) {
        lantern_log_error(
            "reqresp",
            &meta,
            "status[%" PRIu64 "] failed to allocate worker for %s stream",
            trace_id,
            protocol_id);
        status_request_notify_failure(ctx->service, meta.peer, LIBP2P_ERR_INTERNAL);
        close_stream(stream);
        status_request_ctx_free(ctx);
        return;
    }
    worker->ctx = ctx;
    worker->stream = stream;

    pthread_t thread;
    if (pthread_create(&thread, NULL, status_request_worker, worker) != 0) {
        lantern_log_error(
            "reqresp",
            &meta,
            "status[%" PRIu64 "] failed to spawn request worker",
            trace_id);
        free(worker);
        status_request_notify_failure(ctx->service, meta.peer, LIBP2P_ERR_INTERNAL);
        close_stream(stream);
        status_request_ctx_free(ctx);
        return;
    }
    lantern_log_debug(
        "reqresp",
        &meta,
        "status[%" PRIu64 "] spawned request worker",
        trace_id);
    pthread_detach(thread);
}

static int status_request_launch(
    struct lantern_reqresp_service *service,
    const peer_id_t *peer_id,
    const char *peer_id_text,
    bool notify_on_failure) {
    if (!service || !service->host || !peer_id) {
        return -1;
    }

    struct status_request_ctx *ctx = (struct status_request_ctx *)calloc(1, sizeof(*ctx));
    if (!ctx) {
        return -1;
    }
    ctx->service = service;
    ctx->debug_trace_id = reqresp_trace_id_next();

    struct lantern_log_metadata meta = {
        .peer = NULL,
    };

    if (peer_id_text && peer_id_text[0] != '\0') {
        strncpy(ctx->peer_text, peer_id_text, sizeof(ctx->peer_text) - 1);
        ctx->peer_text[sizeof(ctx->peer_text) - 1] = '\0';
    } else {
        if (write_legacy_peer_id_text(peer_id, ctx->peer_text, sizeof(ctx->peer_text)) < 0) {
            ctx->peer_text[0] = '\0';
        }
    }
    if (ctx->peer_text[0] != '\0') {
        meta.peer = ctx->peer_text;
    }
    lantern_log_trace(
        "reqresp",
        &meta,
        "status[%" PRIu64 "] scheduling request",
        ctx->debug_trace_id);

    if (peer_id_clone(peer_id, &ctx->peer_id) != PEER_ID_OK || !ctx->peer_id) {
        lantern_log_warn(
            "reqresp",
            &meta,
            "failed to clone peer id for status request");
        if (notify_on_failure) {
            status_request_notify_failure(service, meta.peer, LIBP2P_ERR_INTERNAL);
        }
        status_request_ctx_free(ctx);
        return -1;
    }

    ctx->protocol_id = LANTERN_STATUS_PROTOCOL_ID;
    int rc = libp2p_host_open_stream_async(
        service->host,
        ctx->peer_id,
        ctx->protocol_id,
        status_request_on_open,
        ctx);
    if (rc != 0) {
        lantern_log_warn(
            "reqresp",
            &meta,
            "libp2p open stream failed rc=%d",
            rc);
        if (notify_on_failure) {
            status_request_notify_failure(service, meta.peer, rc);
        }
        status_request_ctx_free(ctx);
        return -1;
    }
    return 0;
}

int lantern_reqresp_service_request_status(
    struct lantern_reqresp_service *service,
    const peer_id_t *peer_id,
    const char *peer_id_text) {
    return status_request_launch(service, peer_id, peer_id_text, true);
}

static void *blocks_worker(void *arg) {
    struct blocks_stream_ctx *ctx = (struct blocks_stream_ctx *)arg;
    if (!ctx) {
        return NULL;
    }
    struct lantern_reqresp_service *service = ctx->service;
    libp2p_stream_t *stream = ctx->stream;
    const char *protocol_id =
        ctx->protocol_id ? ctx->protocol_id : LANTERN_BLOCKS_BY_ROOT_PROTOCOL_ID;
    free(ctx);

    if (!service || !stream) {
        close_stream(stream);
        return NULL;
    }

    char peer_text[128];
    describe_peer(libp2p_stream_remote_peer(stream), peer_text, sizeof(peer_text));

    const struct lantern_log_metadata meta = {.peer = peer_text[0] ? peer_text : NULL};
    lantern_log_debug(
        "reqresp",
        &meta,
        "blocks_by_root stream protocol=%s",
        protocol_id ? protocol_id : "-");

    libp2p_stream_set_read_interest(stream, true);

    uint8_t *request = NULL;
    size_t request_len = 0;
    ssize_t request_err = 0;
    bool request_legacy_len = false;
    if (read_length_prefixed_stream(
            stream,
            "blocks_by_root",
            peer_text,
            &request,
            &request_len,
            &request_legacy_len,
            &request_err)
        != 0) {
        const char *err_name = request_err == 0 ? "empty" : stream_error_name(request_err);
        lantern_log_warn(
            "reqresp",
            &meta,
            "blocks_by_root read failed err=%s(%zd)",
            err_name ? err_name : "unknown",
            request_err);
        log_stream_error("read", protocol_id, peer_text[0] ? peer_text : NULL);
        (void)send_error_response(
            stream,
            &meta,
            protocol_id,
            peer_text[0] ? peer_text : NULL,
            false,
            LANTERN_REQRESP_RESPONSE_INVALID_REQUEST,
            "invalid request");
        close_stream(stream);
        return NULL;
    }
    if (request_legacy_len && service && service->callbacks.context && peer_text[0]) {
        lantern_client_mark_peer_reqresp_legacy(
            (struct lantern_client *)service->callbacks.context,
            peer_text);
    }
    bool use_legacy_len = request_legacy_len;
    if (!use_legacy_len && service && service->callbacks.context && peer_text[0]) {
        use_legacy_len = lantern_client_peer_reqresp_legacy(
            (struct lantern_client *)service->callbacks.context,
            peer_text);
    }

    lantern_log_debug(
        "reqresp",
        &meta,
        "blocks_by_root request payload_len=%zu",
        request_len);

    log_payload_preview("blocks_by_root request raw", peer_text, request, request_len);

    bool request_framed = payload_is_snappy_framed(request, request_len);
    if (!request_framed) {
        lantern_log_warn(
            "reqresp",
            &meta,
            "blocks_by_root request missing snappy framing");
        free(request);
        log_stream_error("decode", protocol_id, peer_text[0] ? peer_text : NULL);
        (void)send_error_response(
            stream,
            &meta,
            protocol_id,
            peer_text[0] ? peer_text : NULL,
            use_legacy_len,
            LANTERN_REQRESP_RESPONSE_INVALID_REQUEST,
            "invalid request");
        close_stream(stream);
        return NULL;
    }
    lantern_log_debug(
        "reqresp",
        &meta,
        "blocks_by_root request framing=%s include_response_code=%s",
        request_framed ? "framed" : "raw",
        "true");
    LanternBlocksByRootRequest decoded_request;
    lantern_blocks_by_root_request_init(&decoded_request);
    int decode_rc = lantern_network_blocks_by_root_request_decode_snappy(
        &decoded_request,
        request,
        request_len);
    free(request);
    if (decode_rc != 0) {
        lantern_blocks_by_root_request_reset(&decoded_request);
        log_stream_error("decode", protocol_id, peer_text[0] ? peer_text : NULL);
        (void)send_error_response(
            stream,
            &meta,
            protocol_id,
            peer_text[0] ? peer_text : NULL,
            use_legacy_len,
            LANTERN_REQRESP_RESPONSE_INVALID_REQUEST,
            "invalid request");
        close_stream(stream);
        return NULL;
    }

    lantern_log_debug(
        "reqresp",
        &meta,
        "blocks_by_root decoded roots=%zu",
        decoded_request.roots.length);

    LanternSignedBlockList response;
    lantern_signed_block_list_init(&response);

    int collect_rc = 0;
    if (service->callbacks.collect_blocks) {
        collect_rc = service->callbacks.collect_blocks(
            service->callbacks.context,
            decoded_request.roots.items,
            decoded_request.roots.length,
            &response);
    }

    lantern_log_debug(
        "reqresp",
        &meta,
        "blocks_by_root collect rc=%d blocks=%zu",
        collect_rc,
        response.length);
    lantern_blocks_by_root_request_reset(&decoded_request);

    if (collect_rc != 0) {
        lantern_signed_block_list_reset(&response);
        log_stream_error("collect", protocol_id, peer_text[0] ? peer_text : NULL);
        (void)send_error_response(
            stream,
            &meta,
            protocol_id,
            peer_text[0] ? peer_text : NULL,
            use_legacy_len,
            LANTERN_REQRESP_RESPONSE_SERVER_ERROR,
            "server error");
        close_stream(stream);
        return NULL;
    }

    size_t block_count = response.length;
    uint8_t *ssz_buffer = NULL;
    size_t ssz_capacity = 4096u;
    uint8_t *snappy_buffer = NULL;
    size_t snappy_capacity = 0;

    if (block_count == 0) {
        lantern_log_debug(
            "reqresp",
            &meta,
            "blocks_by_root response has zero blocks for peer=%s",
            peer_text[0] ? peer_text : "-");
        if (send_response_chunk(
                stream,
                &meta,
                protocol_id,
                "blocks_by_root response (empty)",
                peer_text[0] ? peer_text : NULL,
                true,
                LANTERN_REQRESP_RESPONSE_SUCCESS,
                use_legacy_len,
                NULL,
                0,
                0)
            != 0) {
            lantern_signed_block_list_reset(&response);
            log_stream_error("write", protocol_id, peer_text[0] ? peer_text : NULL);
            close_stream(stream);
            free(ssz_buffer);
            free(snappy_buffer);
            return NULL;
        }
    }

    for (size_t i = 0; i < block_count; ++i) {
        const LanternSignedBlock *block = &response.blocks[i];
        size_t ssz_written = 0;
        bool encoded = false;
        while (ssz_capacity > 0 && ssz_capacity <= LANTERN_REQRESP_MAX_CHUNK_BYTES) {
            uint8_t *resized = (uint8_t *)realloc(ssz_buffer, ssz_capacity);
            if (!resized) {
                free(ssz_buffer);
                free(snappy_buffer);
                lantern_signed_block_list_reset(&response);
                log_stream_error("encode", protocol_id, peer_text[0] ? peer_text : NULL);
                (void)send_error_response(
                    stream,
                    &meta,
                    protocol_id,
                    peer_text[0] ? peer_text : NULL,
                    use_legacy_len,
                    LANTERN_REQRESP_RESPONSE_SERVER_ERROR,
                    "server error");
                close_stream(stream);
                return NULL;
            }
            ssz_buffer = resized;

            if (lantern_ssz_encode_signed_block_legacy(block, ssz_buffer, ssz_capacity, &ssz_written) == 0) {
                encoded = true;
                break;
            }
            if (ssz_capacity > SIZE_MAX / 2) {
                break;
            }
            size_t next_capacity = ssz_capacity * 2u;
            if (next_capacity > LANTERN_REQRESP_MAX_CHUNK_BYTES) {
                next_capacity = LANTERN_REQRESP_MAX_CHUNK_BYTES;
            }
            if (next_capacity <= ssz_capacity) {
                break;
            }
            ssz_capacity = next_capacity;
        }
        if (!encoded || ssz_written == 0) {
            free(ssz_buffer);
            free(snappy_buffer);
            lantern_signed_block_list_reset(&response);
            log_stream_error("encode", protocol_id, peer_text[0] ? peer_text : NULL);
            (void)send_error_response(
                stream,
                &meta,
                protocol_id,
                peer_text[0] ? peer_text : NULL,
                use_legacy_len,
                LANTERN_REQRESP_RESPONSE_SERVER_ERROR,
                "server error");
            close_stream(stream);
            return NULL;
        }

        size_t max_compressed = 0;
        int max_rc = lantern_snappy_max_compressed_size(ssz_written, &max_compressed);
        if (max_rc != LANTERN_SNAPPY_OK || max_compressed == 0) {
            free(ssz_buffer);
            free(snappy_buffer);
            lantern_signed_block_list_reset(&response);
            log_stream_error("compress", protocol_id, peer_text[0] ? peer_text : NULL);
            (void)send_error_response(
                stream,
                &meta,
                protocol_id,
                peer_text[0] ? peer_text : NULL,
                use_legacy_len,
                LANTERN_REQRESP_RESPONSE_SERVER_ERROR,
                "server error");
            close_stream(stream);
            return NULL;
        }

        if (max_compressed > snappy_capacity) {
            uint8_t *resized = (uint8_t *)realloc(snappy_buffer, max_compressed);
            if (!resized) {
                free(ssz_buffer);
                free(snappy_buffer);
                lantern_signed_block_list_reset(&response);
                log_stream_error("compress", protocol_id, peer_text[0] ? peer_text : NULL);
                (void)send_error_response(
                    stream,
                    &meta,
                    protocol_id,
                    peer_text[0] ? peer_text : NULL,
                    use_legacy_len,
                    LANTERN_REQRESP_RESPONSE_SERVER_ERROR,
                    "server error");
                close_stream(stream);
                return NULL;
            }
            snappy_buffer = resized;
            snappy_capacity = max_compressed;
        }

        size_t compressed_len = 0;
        int snappy_rc = lantern_snappy_compress(
            ssz_buffer,
            ssz_written,
            snappy_buffer,
            snappy_capacity,
            &compressed_len);
        if (snappy_rc != LANTERN_SNAPPY_OK) {
            free(ssz_buffer);
            free(snappy_buffer);
            lantern_signed_block_list_reset(&response);
            log_stream_error("compress", protocol_id, peer_text[0] ? peer_text : NULL);
            (void)send_error_response(
                stream,
                &meta,
                protocol_id,
                peer_text[0] ? peer_text : NULL,
                use_legacy_len,
                LANTERN_REQRESP_RESPONSE_SERVER_ERROR,
                "server error");
            close_stream(stream);
            return NULL;
        }

        char chunk_label[64];
        snprintf(
            chunk_label,
            sizeof(chunk_label),
            "blocks_by_root chunk[%zu/%zu]",
            i + 1,
            block_count);
        log_payload_preview(chunk_label, peer_text, snappy_buffer, compressed_len);
        lantern_log_debug(
            "reqresp",
            &meta,
            "%s slot=%" PRIu64 " raw=%zu compressed=%zu",
            chunk_label,
            block->message.slot,
            ssz_written,
            compressed_len);

        if (send_response_chunk(
                stream,
                &meta,
                protocol_id,
                chunk_label,
                peer_text[0] ? peer_text : NULL,
                true,
                LANTERN_REQRESP_RESPONSE_SUCCESS,
                use_legacy_len,
                snappy_buffer,
                compressed_len,
                ssz_written)
            != 0) {
            free(ssz_buffer);
            free(snappy_buffer);
            lantern_signed_block_list_reset(&response);
            log_stream_error("write", protocol_id, peer_text[0] ? peer_text : NULL);
            close_stream(stream);
            return NULL;
        }
    }

    free(ssz_buffer);
    free(snappy_buffer);
    lantern_signed_block_list_reset(&response);
    close_stream(stream);

    lantern_log_info(
        "network",
        &(const struct lantern_log_metadata){.peer = peer_text},
        "served blocks-by-root request (%zu roots)",
        block_count);
    return NULL;
}

static void status_on_open_impl(
    libp2p_stream_t *stream,
    void *user_data,
    const char *protocol_id) {
    struct lantern_reqresp_service *service = (struct lantern_reqresp_service *)user_data;
    if (stream && !libp2p__stream_retain_async(stream)) {
        /* Stream is already being torn down; skip handling. */
        return;
    }
    struct status_stream_ctx *ctx = (struct status_stream_ctx *)malloc(sizeof(*ctx));
    if (!ctx) {
        close_stream(stream);
        return;
    }
    ctx->service = service;
    ctx->stream = stream;
    ctx->protocol_id = protocol_id;
    ctx->debug_trace_id = reqresp_trace_id_next();
    pthread_t thread;
    if (pthread_create(&thread, NULL, status_worker, ctx) != 0) {
        free(ctx);
        close_stream(stream);
        return;
    }
    pthread_detach(thread);
}

static void status_on_open_primary(libp2p_stream_t *stream, void *user_data) {
    status_on_open_impl(stream, user_data, LANTERN_STATUS_PROTOCOL_ID);
}

static void blocks_on_open_impl(libp2p_stream_t *stream, void *user_data, const char *protocol_id) {
    struct lantern_reqresp_service *service = (struct lantern_reqresp_service *)user_data;
    if (!service) {
        close_stream(stream);
        return;
    }
    if (stream && !libp2p__stream_retain_async(stream)) {
        /* Stream is already being torn down; skip handling. */
        return;
    }
    struct blocks_stream_ctx *ctx = (struct blocks_stream_ctx *)malloc(sizeof(*ctx));
    if (!ctx) {
        close_stream(stream);
        return;
    }
    ctx->service = service;
    ctx->stream = stream;
    ctx->protocol_id = protocol_id;
    pthread_t thread;
    if (pthread_create(&thread, NULL, blocks_worker, ctx) != 0) {
        free(ctx);
        close_stream(stream);
        return;
    }
    pthread_detach(thread);
}

static void blocks_on_open_primary(libp2p_stream_t *stream, void *user_data) {
    blocks_on_open_impl(stream, user_data, LANTERN_BLOCKS_BY_ROOT_PROTOCOL_ID);
}

int lantern_reqresp_service_start(
    struct lantern_reqresp_service *service,
    const struct lantern_reqresp_service_config *config) {
    if (!service || !config || !config->host) {
        return -1;
    }

    lantern_reqresp_service_reset(service);

    service->host = config->host;
    if (config->callbacks) {
        service->callbacks = *config->callbacks;
    } else {
        memset(&service->callbacks, 0, sizeof(service->callbacks));
    }

    libp2p_protocol_def_t status_def;
    memset(&status_def, 0, sizeof(status_def));
    status_def.protocol_id = LANTERN_STATUS_PROTOCOL_ID;
    status_def.read_mode = LIBP2P_READ_PULL;
    status_def.on_open = status_on_open_primary;
    status_def.user_data = service;

    const char *blocks_protocol_primary = LANTERN_BLOCKS_BY_ROOT_PROTOCOL_ID;

    libp2p_protocol_def_t blocks_def;
    memset(&blocks_def, 0, sizeof(blocks_def));
    blocks_def.protocol_id = blocks_protocol_primary;
    blocks_def.read_mode = LIBP2P_READ_PULL;
    blocks_def.on_open = blocks_on_open_primary;
    blocks_def.user_data = service;

    if (libp2p_host_listen_protocol(service->host, &status_def, &service->status_server) != 0) {
        lantern_reqresp_service_reset(service);
        return -1;
    }
    if (libp2p_host_listen_protocol(service->host, &blocks_def, &service->blocks_server) != 0) {
        lantern_reqresp_service_reset(service);
        return -1;
    }

    lantern_log_info(
        "network",
        &(const struct lantern_log_metadata){0},
        "request/response protocols registered");

    return 0;
}
