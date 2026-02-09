/**
 * @file client_reqresp_stream.c
 * @brief Low-level stream I/O utilities for reqresp protocol
 *
 * @spec subspecs/networking/reqresp in tools/leanSpec
 *
 * Implements stream read/write utilities for the request/response protocol,
 * including varint decoding, payload reading, and response chunk handling.
 *
 * @note Lock ordering (acquire in this order to prevent deadlocks):
 *       1. state_lock
 *       2. status_lock
 *       3. pending_lock
 *       4. validator_lock
 *       5. connection_lock
 *       6. peer_vote_lock
 */

#include "client_internal.h"

#include <errno.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "libp2p/errors.h"
#include "libp2p/stream.h"
#include "multiformats/unsigned_varint/unsigned_varint.h"
#include "peer_id/peer_id.h"

#include "lantern/encoding/snappy.h"
#include "lantern/networking/reqresp_service.h"
#include "lantern/support/log.h"
#include "lantern/support/strings.h"
#include "lantern/support/time.h"


/* ============================================================================
 * Constants
 * ============================================================================ */

enum
{
    /** Peer ID string buffer size */
    LANTERN_REQRESP_PEER_TEXT_BYTES = 128,

    /** Payload length threshold for additional warning logs */
    LANTERN_REQRESP_SUSPICIOUS_PAYLOAD_BYTES = 512,
};

static uint64_t reqresp_now_ms(void)
{
    double now_sec = lantern_time_now_seconds();
    if (now_sec <= 0.0)
    {
        return 0;
    }
    double now_ms = now_sec * 1000.0;
    if (now_ms >= (double)UINT64_MAX)
    {
        return UINT64_MAX;
    }
    return (uint64_t)now_ms;
}

static void log_snappy_frame_summary(
    const char *stage,
    const struct lantern_log_metadata *meta,
    const uint8_t *data,
    size_t length)
{
    if (!data || !meta)
    {
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

    if (length >= 4u)
    {
        have_first = true;
        first_type = data[0];
        first_len = (uint32_t)data[1] | ((uint32_t)data[2] << 8u) | ((uint32_t)data[3] << 16u);
        second_offset = 4u + (size_t)first_len;
        if (second_offset + 4u <= length)
        {
            have_second = true;
            second_type = data[second_offset];
            second_len = (uint32_t)data[second_offset + 1u]
                | ((uint32_t)data[second_offset + 2u] << 8u)
                | ((uint32_t)data[second_offset + 3u] << 16u);
        }
    }

    size_t preview_len = length < 24u ? length : 24u;
    char preview_hex[(24u * 2u) + 1u];
    if (preview_len > 0)
    {
        if (lantern_bytes_to_hex(data, preview_len, preview_hex, sizeof(preview_hex), 0) != 0)
        {
            preview_hex[0] = '\0';
        }
    }
    else
    {
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


/* ============================================================================
 * Forward Declarations
 * ============================================================================ */

static void init_peer_log_metadata(
    libp2p_stream_t *stream,
    char *peer_text,
    size_t peer_text_len,
    struct lantern_log_metadata *out_meta);
static bool protocol_expects_response_code(enum lantern_reqresp_protocol_kind protocol);
static int set_stream_deadline(
    libp2p_stream_t *stream,
    uint64_t deadline_ms,
    const struct lantern_log_metadata *meta,
    const char *label,
    ssize_t *out_err);
static int read_stream_byte_with_retry(
    libp2p_stream_t *stream,
    const struct lantern_log_metadata *meta,
    const char *label,
    uint64_t deadline_ms,
    uint8_t *out_byte,
    ssize_t *out_err);
static int read_response_code_prefix(
    struct lantern_reqresp_service *service,
    libp2p_stream_t *stream,
    bool expect_code,
    const struct lantern_log_metadata *meta,
    const char *peer_text,
    uint64_t deadline_ms,
    uint8_t *out_frame_code,
    uint8_t *out_response_code_byte,
    uint8_t *out_response_code,
    bool *out_missing_response_code,
    uint8_t *out_header_first_byte,
    ssize_t *out_err);
static int read_payload_header_first_byte(
    libp2p_stream_t *stream,
    bool expect_code,
    const struct lantern_log_metadata *meta,
    uint64_t deadline_ms,
    uint8_t *out_header_first_byte,
    ssize_t *out_err);
static int read_stream_exact(
    libp2p_stream_t *stream,
    const struct lantern_log_metadata *meta,
    const char *label,
    uint8_t *buffer,
    size_t buffer_len,
    uint64_t deadline_ms,
    size_t *out_read,
    ssize_t *out_err);
static int read_snappy_framed_payload(
    libp2p_stream_t *stream,
    const struct lantern_log_metadata *meta,
    const char *label,
    uint64_t declared_len,
    uint64_t deadline_ms,
    uint8_t **out_buffer,
    size_t *out_len,
    bool *out_legacy_len,
    ssize_t *out_err);
static int read_varint_header_from_first_byte(
    libp2p_stream_t *stream,
    uint8_t first_byte,
    uint8_t *header,
    size_t header_len,
    uint64_t *out_value,
    size_t *out_consumed,
    ssize_t *out_err,
    const struct lantern_log_metadata *meta,
    const char *label,
    uint64_t deadline_ms);
static void log_varint_header_details(
    const uint8_t *header,
    size_t consumed,
    uint64_t payload_len,
    const struct lantern_log_metadata *meta,
    const char *label);
static int validate_payload_len(
    uint64_t payload_len,
    ssize_t *out_err,
    const struct lantern_log_metadata *meta,
    const char *label);
static int read_payload_bytes(
    libp2p_stream_t *stream,
    size_t payload_size,
    uint8_t **out_buffer,
    ssize_t *out_err,
    const struct lantern_log_metadata *meta,
    const char *label,
    uint64_t deadline_ms);
static void log_payload_read_complete(
    const uint8_t *buffer,
    size_t payload_size,
    const struct lantern_log_metadata *meta,
    const char *label);
static int read_varint_payload_chunk(
    libp2p_stream_t *stream,
    uint8_t first_byte,
    uint8_t **out_data,
    size_t *out_len,
    bool *out_legacy_len,
    ssize_t *out_err,
    const struct lantern_log_metadata *meta,
    const char *label,
    uint64_t deadline_ms);


/* ============================================================================
 * Internal Helpers
 * ============================================================================ */

/**
 * @brief Builds peer log metadata for a stream.
 */
static void init_peer_log_metadata(
    libp2p_stream_t *stream,
    char *peer_text,
    size_t peer_text_len,
    struct lantern_log_metadata *out_meta)
{
    if (!peer_text || peer_text_len == 0 || !out_meta)
    {
        return;
    }

    peer_text[0] = '\0';
    if (stream)
    {
        const peer_id_t *peer = libp2p_stream_remote_peer(stream);
        if (peer
            && peer_id_to_string(peer, PEER_ID_FMT_BASE58_LEGACY, peer_text, peer_text_len) < 0)
        {
            peer_text[0] = '\0';
        }
    }

    *out_meta = (struct lantern_log_metadata){.peer = peer_text[0] ? peer_text : NULL};
}


/**
 * @brief Returns whether a protocol expects a response code prefix.
 */
static bool protocol_expects_response_code(enum lantern_reqresp_protocol_kind protocol)
{
    return (protocol == LANTERN_REQRESP_PROTOCOL_STATUS)
        || (protocol == LANTERN_REQRESP_PROTOCOL_BLOCKS_BY_ROOT);
}


/**
 * @brief Sets a stream deadline and validates the result.
 */
static int set_stream_deadline(
    libp2p_stream_t *stream,
    uint64_t deadline_ms,
    const struct lantern_log_metadata *meta,
    const char *label,
    ssize_t *out_err)
{
    if (!stream)
    {
        if (out_err)
        {
            *out_err = LIBP2P_ERR_NULL_PTR;
        }
        return LANTERN_REQRESP_ERR_INVALID_PARAM;
    }

    int rc = libp2p_stream_set_deadline(stream, deadline_ms);
    if (rc != 0)
    {
        if (out_err)
        {
            *out_err = (ssize_t)rc;
        }
        lantern_log_warn(
            "reqresp",
            meta,
            "%s failed to set deadline_ms=%" PRIu64 " err=%d",
            label ? label : "stream",
            deadline_ms,
            rc);
        return LANTERN_REQRESP_ERR_SET_DEADLINE;
    }
    if (out_err)
    {
        *out_err = 0;
    }
    return 0;
}

static int set_stream_deadline_remaining(
    libp2p_stream_t *stream,
    uint64_t deadline_ms,
    const struct lantern_log_metadata *meta,
    const char *label,
    ssize_t *out_err)
{
    uint64_t now_ms = reqresp_now_ms();
    if (now_ms >= deadline_ms)
    {
        if (out_err)
        {
            *out_err = LIBP2P_ERR_TIMEOUT;
        }
        lantern_log_warn(
            "reqresp",
            meta,
            "%s timed out",
            label ? label : "stream");
        return LANTERN_REQRESP_ERR_STREAM_READ;
    }
    return set_stream_deadline(stream, deadline_ms - now_ms, meta, label, out_err);
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

/**
 * @brief Reads a framed Snappy payload with declared uncompressed length.
 */
static int read_snappy_framed_payload(
    libp2p_stream_t *stream,
    const struct lantern_log_metadata *meta,
    const char *label,
    uint64_t declared_len,
    uint64_t deadline_ms,
    uint8_t **out_buffer,
    size_t *out_len,
    bool *out_legacy_len,
    ssize_t *out_err)
{
    if (!stream || !out_buffer || !out_len)
    {
        if (out_err)
        {
            *out_err = LIBP2P_ERR_NULL_PTR;
        }
        return LANTERN_REQRESP_ERR_INVALID_PARAM;
    }
    if (out_legacy_len)
    {
        *out_legacy_len = false;
    }
    if (declared_len > (uint64_t)LANTERN_REQRESP_MAX_CHUNK_BYTES
        || declared_len > (uint64_t)SIZE_MAX)
    {
        if (out_err)
        {
            *out_err = LIBP2P_ERR_MSG_TOO_LARGE;
        }
        lantern_log_warn(
            "reqresp",
            meta,
            "%s declared uncompressed length invalid=%" PRIu64,
            label ? label : "chunk",
            declared_len);
        return LANTERN_REQRESP_ERR_PAYLOAD_TOO_LARGE;
    }

    if (declared_len == 0)
    {
        uint8_t header[4];
        size_t read_len = 0;
        ssize_t read_err = 0;
        if (read_stream_exact(
                stream,
                meta,
                label ? label : "chunk",
                header,
                sizeof(header),
                deadline_ms,
                &read_len,
                &read_err)
            != 0)
        {
            if (out_err)
            {
                *out_err = read_err;
            }
            return LANTERN_REQRESP_ERR_STREAM_READ;
        }
        uint8_t chunk_type = header[0];
        uint32_t chunk_len = (uint32_t)header[1]
            | ((uint32_t)header[2] << 8u)
            | ((uint32_t)header[3] << 16u);
        if (chunk_type != 0xffu || chunk_len != 6u)
        {
            if (out_err)
            {
                *out_err = LIBP2P_ERR_INTERNAL;
            }
            lantern_log_warn(
                "reqresp",
                meta,
                "%s snappy stream identifier invalid type=0x%02x len=%u",
                label ? label : "chunk",
                (unsigned)chunk_type,
                chunk_len);
            return LANTERN_REQRESP_ERR_STREAM_READ;
        }
        uint8_t payload[6];
        if (read_stream_exact(
                stream,
                meta,
                label ? label : "chunk",
                payload,
                sizeof(payload),
                deadline_ms,
                &read_len,
                &read_err)
            != 0)
        {
            if (out_err)
            {
                *out_err = read_err;
            }
            return LANTERN_REQRESP_ERR_STREAM_READ;
        }
        uint8_t *buffer = malloc(10u);
        if (!buffer)
        {
            if (out_err)
            {
                *out_err = -ENOMEM;
            }
            lantern_log_error(
                "reqresp",
                meta,
                "%s payload allocation failed bytes=10",
                label ? label : "chunk");
            return LANTERN_REQRESP_ERR_ALLOC;
        }
        memcpy(buffer, header, sizeof(header));
        memcpy(buffer + sizeof(header), payload, sizeof(payload));
        if (!lantern_snappy_is_framed(buffer, 10u))
        {
            free(buffer);
            if (out_err)
            {
                *out_err = LIBP2P_ERR_INTERNAL;
            }
            lantern_log_warn(
                "reqresp",
                meta,
                "%s payload missing snappy framing bytes=10",
                label ? label : "chunk");
            return LANTERN_REQRESP_ERR_STREAM_READ;
        }
        if (out_err)
        {
            *out_err = 0;
        }
        *out_buffer = buffer;
        *out_len = 10u;
        return 0;
    }

    size_t max_compressed = 0;
    if (lantern_snappy_max_compressed_size((size_t)declared_len, &max_compressed) != LANTERN_SNAPPY_OK
        || max_compressed == 0)
    {
        if (out_err)
        {
            *out_err = LIBP2P_ERR_INTERNAL;
        }
        lantern_log_warn(
            "reqresp",
            meta,
            "%s failed to compute snappy max size declared_uncompressed=%" PRIu64,
            label ? label : "chunk",
            declared_len);
        return LANTERN_REQRESP_ERR_ALLOC;
    }

    uint8_t *buffer = malloc(max_compressed);
    if (!buffer)
    {
        if (out_err)
        {
            *out_err = -ENOMEM;
        }
        lantern_log_error(
            "reqresp",
            meta,
            "%s payload allocation failed bytes=%zu",
            label ? label : "chunk",
            max_compressed);
        return LANTERN_REQRESP_ERR_ALLOC;
    }

    size_t offset = 0;
    uint64_t uncompressed_total = 0;
    bool saw_data_chunk = false;
    size_t chunk_index = 0;
    const uint32_t max_chunk_len = 0x00ffffffu;

    while (!saw_data_chunk || uncompressed_total < declared_len)
    {
        uint8_t header[4];
        size_t read_len = 0;
        ssize_t read_err = 0;
        if (read_stream_exact(
                stream,
                meta,
                label ? label : "chunk",
                header,
                sizeof(header),
                deadline_ms,
                &read_len,
                &read_err)
            != 0)
        {
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
                    label ? label : "chunk",
                    declared_len,
                    offset,
                    legacy_uncompressed);
                if (out_legacy_len)
                {
                    *out_legacy_len = true;
                }
                if (out_err)
                {
                    *out_err = 0;
                }
                *out_buffer = buffer;
                *out_len = offset;
                return 0;
            }
            free(buffer);
            if (out_err)
            {
                *out_err = read_err;
            }
            return LANTERN_REQRESP_ERR_STREAM_READ;
        }

        uint8_t chunk_type = header[0];
        uint32_t chunk_len = (uint32_t)header[1]
            | ((uint32_t)header[2] << 8u)
            | ((uint32_t)header[3] << 16u);

        if (chunk_len > max_chunk_len)
        {
            free(buffer);
            if (out_err)
            {
                *out_err = LIBP2P_ERR_MSG_TOO_LARGE;
            }
            lantern_log_warn(
                "reqresp",
                meta,
                "%s snappy chunk length invalid=%u",
                label ? label : "chunk",
                chunk_len);
            return LANTERN_REQRESP_ERR_PAYLOAD_TOO_LARGE;
        }

        if (offset + sizeof(header) + (size_t)chunk_len > max_compressed)
        {
            free(buffer);
            if (out_err)
            {
                *out_err = LIBP2P_ERR_MSG_TOO_LARGE;
            }
            lantern_log_warn(
                "reqresp",
                meta,
                "%s snappy payload exceeds max_compressed bytes=%zu",
                label ? label : "chunk",
                max_compressed);
            return LANTERN_REQRESP_ERR_PAYLOAD_TOO_LARGE;
        }

        memcpy(buffer + offset, header, sizeof(header));
        offset += sizeof(header);

        if (chunk_len > 0)
        {
            if (read_stream_exact(
                    stream,
                    meta,
                    label ? label : "chunk",
                    buffer + offset,
                    (size_t)chunk_len,
                    deadline_ms,
                    &read_len,
                    &read_err)
                != 0)
            {
                free(buffer);
                if (out_err)
                {
                    *out_err = read_err;
                }
                return LANTERN_REQRESP_ERR_STREAM_READ;
            }
        }

        const uint8_t *chunk_payload = buffer + offset;
        offset += (size_t)chunk_len;
        chunk_index++;

        uint64_t chunk_uncompressed = 0;
        bool contributes = false;
        switch (chunk_type)
        {
        case 0xffu: /* stream identifier */
            if (chunk_len != 6u)
            {
                free(buffer);
                if (out_err)
                {
                    *out_err = LIBP2P_ERR_INTERNAL;
                }
                lantern_log_warn(
                    "reqresp",
                    meta,
                    "%s snappy stream identifier length invalid=%u",
                    label ? label : "chunk",
                    chunk_len);
                return LANTERN_REQRESP_ERR_STREAM_READ;
            }
            break;
        case 0x00u: /* compressed */
            if (chunk_len < 4u)
            {
                free(buffer);
                if (out_err)
                {
                    *out_err = LIBP2P_ERR_INTERNAL;
                }
                lantern_log_warn(
                    "reqresp",
                    meta,
                    "%s snappy compressed chunk too short len=%u",
                    label ? label : "chunk",
                    chunk_len);
                return LANTERN_REQRESP_ERR_STREAM_READ;
            }
            {
                size_t raw_len = 0;
                int rc = lantern_snappy_uncompressed_length_raw(
                    chunk_payload + 4u,
                    (size_t)chunk_len - 4u,
                    &raw_len);
                if (rc != LANTERN_SNAPPY_OK)
                {
                    free(buffer);
                    if (out_err)
                    {
                        *out_err = LIBP2P_ERR_INTERNAL;
                    }
                    lantern_log_warn(
                        "reqresp",
                        meta,
                        "%s snappy compressed chunk length decode failed rc=%d len=%u",
                        label ? label : "chunk",
                        rc,
                        chunk_len);
                    return LANTERN_REQRESP_ERR_STREAM_READ;
                }
                chunk_uncompressed = (uint64_t)raw_len;
                contributes = true;
            }
            break;
        case 0x01u: /* uncompressed */
            if (chunk_len < 4u)
            {
                free(buffer);
                if (out_err)
                {
                    *out_err = LIBP2P_ERR_INTERNAL;
                }
                lantern_log_warn(
                    "reqresp",
                    meta,
                    "%s snappy uncompressed chunk too short len=%u",
                    label ? label : "chunk",
                    chunk_len);
                return LANTERN_REQRESP_ERR_STREAM_READ;
            }
            chunk_uncompressed = (uint64_t)(chunk_len - 4u);
            contributes = true;
            break;
        default:
            if (chunk_type >= 0x80u && chunk_type <= 0xfeu)
            {
                /* skippable chunk - ignore */
                break;
            }
            free(buffer);
            if (out_err)
            {
                *out_err = LIBP2P_ERR_INTERNAL;
            }
            lantern_log_warn(
                "reqresp",
                meta,
                "%s snappy chunk type unsupported=0x%02x",
                label ? label : "chunk",
                (unsigned)chunk_type);
            return LANTERN_REQRESP_ERR_STREAM_READ;
        }

        if (contributes)
        {
            saw_data_chunk = true;
            if (chunk_uncompressed > UINT64_MAX - uncompressed_total)
            {
                free(buffer);
                if (out_err)
                {
                    *out_err = LIBP2P_ERR_INTERNAL;
                }
                lantern_log_warn(
                    "reqresp",
                    meta,
                    "%s snappy uncompressed length overflow",
                    label ? label : "chunk");
                return LANTERN_REQRESP_ERR_STREAM_READ;
            }
            uncompressed_total += chunk_uncompressed;
        }

        lantern_log_trace(
            "reqresp",
            meta,
            "%s snappy chunk[%zu] type=0x%02x len=%u uncompressed=%" PRIu64 " total=%" PRIu64 "/%" PRIu64,
            label ? label : "chunk",
            chunk_index,
            (unsigned)chunk_type,
            chunk_len,
            chunk_uncompressed,
            uncompressed_total,
            declared_len);

        if (uncompressed_total > declared_len)
        {
            size_t legacy_uncompressed = 0;
            if (accept_legacy_declared_len(buffer, offset, declared_len, &legacy_uncompressed))
            {
                lantern_log_warn(
                    "reqresp",
                    meta,
                    "%s legacy reqresp length declared=%" PRIu64 " compressed=%zu uncompressed=%zu",
                    label ? label : "chunk",
                    declared_len,
                    offset,
                    legacy_uncompressed);
                if (out_legacy_len)
                {
                    *out_legacy_len = true;
                }
                if (out_err)
                {
                    *out_err = 0;
                }
                *out_buffer = buffer;
                *out_len = offset;
                return 0;
            }
            free(buffer);
            if (out_err)
            {
                *out_err = LIBP2P_ERR_INTERNAL;
            }
            lantern_log_warn(
                "reqresp",
                meta,
                "%s snappy uncompressed length exceeded declared=%" PRIu64 " got=%" PRIu64,
                label ? label : "chunk",
                declared_len,
                uncompressed_total);
            return LANTERN_REQRESP_ERR_STREAM_READ;
        }
    }

    if (!lantern_snappy_is_framed(buffer, offset))
    {
        lantern_log_warn(
            "reqresp",
            meta,
            "%s payload missing snappy framing bytes=%zu",
            label ? label : "chunk",
            offset);
        log_snappy_frame_summary(label, meta, buffer, offset);
        free(buffer);
        if (out_err)
        {
            *out_err = LIBP2P_ERR_INTERNAL;
        }
        return LANTERN_REQRESP_ERR_STREAM_READ;
    }

    lantern_log_debug(
        "reqresp",
        meta,
        "%s snappy payload read compressed=%zu uncompressed=%" PRIu64,
        label ? label : "chunk",
        offset,
        uncompressed_total);

    if (out_err)
    {
        *out_err = 0;
    }
    *out_buffer = buffer;
    *out_len = offset;
    return 0;
}


/**
 * @brief Reads a single byte from a stream, retrying on AGAIN.
 */
static int read_stream_byte_with_retry(
    libp2p_stream_t *stream,
    const struct lantern_log_metadata *meta,
    const char *label,
    uint64_t deadline_ms,
    uint8_t *out_byte,
    ssize_t *out_err)
{
    if (!stream || !out_byte)
    {
        if (out_err)
        {
            *out_err = LIBP2P_ERR_NULL_PTR;
        }
        return LANTERN_REQRESP_ERR_INVALID_PARAM;
    }

    while (true)
    {
        int rc = set_stream_deadline_remaining(
            stream,
            deadline_ms,
            meta,
            label,
            out_err);
        if (rc != 0)
        {
            return rc;
        }

        ssize_t n = libp2p_stream_read(stream, out_byte, 1);
        if (n == 1)
        {
            if (set_stream_deadline(stream, 0, meta, label, NULL) != 0)
            {
                /* Best-effort: already logged */
            }
            if (out_err)
            {
                *out_err = 0;
            }
            return 0;
        }
        if (n == (ssize_t)LIBP2P_ERR_AGAIN)
        {
            continue;
        }

        if (set_stream_deadline(stream, 0, meta, label, NULL) != 0)
        {
            /* Best-effort: already logged */
        }
        if (out_err)
        {
            *out_err = (n == 0) ? (ssize_t)LIBP2P_ERR_EOF : n;
        }
        return LANTERN_REQRESP_ERR_STREAM_READ;
    }
}


/**
 * @brief Reads and interprets the response code prefix for a chunk.
 */
static int read_response_code_prefix(
    struct lantern_reqresp_service *service,
    libp2p_stream_t *stream,
    bool expect_code,
    const struct lantern_log_metadata *meta,
    const char *peer_text,
    uint64_t deadline_ms,
    uint8_t *out_frame_code,
    uint8_t *out_response_code_byte,
    uint8_t *out_response_code,
    bool *out_missing_response_code,
    uint8_t *out_header_first_byte,
    ssize_t *out_err)
{
    (void)peer_text;
    if (!out_frame_code || !out_response_code_byte)
    {
        if (out_err)
        {
            *out_err = LIBP2P_ERR_NULL_PTR;
        }
        return LANTERN_REQRESP_ERR_INVALID_PARAM;
    }

    *out_frame_code = 0;
    *out_response_code_byte = 0;
    if (out_missing_response_code)
    {
        *out_missing_response_code = false;
    }
    if (out_header_first_byte)
    {
        *out_header_first_byte = 0;
    }

    if (!expect_code)
    {
        if (out_response_code)
        {
            *out_response_code = LANTERN_REQRESP_RESPONSE_SUCCESS;
        }
        if (out_err)
        {
            *out_err = 0;
        }
        return 0;
    }

    uint8_t response_code_byte = 0;
    ssize_t read_err = 0;
    int rc = read_stream_byte_with_retry(
        stream,
        meta,
        "response code",
        deadline_ms,
        &response_code_byte,
        &read_err);
    if (rc != 0)
    {
        if (out_err)
        {
            *out_err = read_err;
        }
        lantern_log_trace("reqresp", meta, "response code read failed err=%zd", read_err);
        return rc;
    }

    *out_frame_code = response_code_byte;
    *out_response_code_byte = response_code_byte;

    bool allow_missing_response_code =
        service != NULL && service->callbacks.context != NULL;

    if (response_code_byte > LANTERN_REQRESP_RESPONSE_RESOURCE_UNAVAILABLE
        && allow_missing_response_code)
    {
        if (out_missing_response_code)
        {
            *out_missing_response_code = true;
        }
        if (out_header_first_byte)
        {
            *out_header_first_byte = response_code_byte;
        }
        if (out_response_code)
        {
            *out_response_code = LANTERN_REQRESP_RESPONSE_SUCCESS;
        }
        if (out_err)
        {
            *out_err = 0;
        }
        lantern_log_warn(
            "reqresp",
            meta,
            "response code missing, using legacy no-code framing first_byte=0x%02x",
            (unsigned)response_code_byte);
        return 0;
    }

    uint8_t mapped_code = response_code_byte;
    if (response_code_byte > LANTERN_REQRESP_RESPONSE_RESOURCE_UNAVAILABLE)
    {
        mapped_code = (response_code_byte <= 127u)
            ? LANTERN_REQRESP_RESPONSE_SERVER_ERROR
            : LANTERN_REQRESP_RESPONSE_INVALID_REQUEST;
    }

    if (out_response_code)
    {
        *out_response_code = mapped_code;
    }
    if (mapped_code == LANTERN_REQRESP_RESPONSE_SUCCESS)
    {
        lantern_log_debug(
            "reqresp",
            meta,
            "response code=%u mapped=%u",
            (unsigned)response_code_byte,
            (unsigned)mapped_code);
    }
    else
    {
        lantern_log_info(
            "reqresp",
            meta,
            "response code=%u mapped=%u",
            (unsigned)response_code_byte,
            (unsigned)mapped_code);
    }

    if (out_err)
    {
        *out_err = 0;
    }
    return 0;
}


/**
 * @brief Reads the first byte of the varint payload header for a chunk.
 */
static int read_payload_header_first_byte(
    libp2p_stream_t *stream,
    bool expect_code,
    const struct lantern_log_metadata *meta,
    uint64_t deadline_ms,
    uint8_t *out_header_first_byte,
    ssize_t *out_err)
{
    if (!stream || !out_header_first_byte)
    {
        if (out_err)
        {
            *out_err = LIBP2P_ERR_NULL_PTR;
        }
        return LANTERN_REQRESP_ERR_INVALID_PARAM;
    }

    (void)expect_code;

    ssize_t read_err = 0;
    int rc = read_stream_byte_with_retry(
        stream,
        meta,
        "payload header",
        deadline_ms,
        out_header_first_byte,
        &read_err);
    if (rc != 0)
    {
        if (out_err)
        {
            *out_err = read_err;
        }
        lantern_log_trace("reqresp", meta, "response payload header read failed err=%zd", read_err);
        return rc;
    }

    if (out_err)
    {
        *out_err = 0;
    }
    return 0;
}


/**
 * @brief Reads exactly buffer_len bytes from a stream.
 */
static int read_stream_exact(
    libp2p_stream_t *stream,
    const struct lantern_log_metadata *meta,
    const char *label,
    uint8_t *buffer,
    size_t buffer_len,
    uint64_t deadline_ms,
    size_t *out_read,
    ssize_t *out_err)
{
    if (!stream || (!buffer && buffer_len > 0))
    {
        if (out_err)
        {
            *out_err = LIBP2P_ERR_NULL_PTR;
        }
        return LANTERN_REQRESP_ERR_INVALID_PARAM;
    }

    size_t collected = 0;
    while (collected < buffer_len)
    {
        int rc = set_stream_deadline_remaining(
            stream,
            deadline_ms,
            meta,
            label,
            out_err);
        if (rc != 0)
        {
            if (out_read)
            {
                *out_read = collected;
            }
            return rc;
        }

        ssize_t n = libp2p_stream_read(stream, buffer + collected, buffer_len - collected);
        if (n > 0)
        {
            collected += (size_t)n;
            continue;
        }
        if (n == (ssize_t)LIBP2P_ERR_AGAIN)
        {
            continue;
        }

        if (set_stream_deadline(stream, 0, meta, label, NULL) != 0)
        {
            /* Best-effort: already logged */
        }
        if (out_read)
        {
            *out_read = collected;
        }
        if (out_err)
        {
            *out_err = (n == 0) ? (ssize_t)LIBP2P_ERR_EOF : n;
        }
        return LANTERN_REQRESP_ERR_STREAM_READ;
    }
    if (set_stream_deadline(stream, 0, meta, label, NULL) != 0)
    {
        /* Best-effort: already logged */
    }
    if (out_read)
    {
        *out_read = collected;
    }
    if (out_err)
    {
        *out_err = 0;
    }
    return 0;
}


/**
 * @brief Reads and decodes a varint header after the first byte.
 */
static int read_varint_header_from_first_byte(
    libp2p_stream_t *stream,
    uint8_t first_byte,
    uint8_t *header,
    size_t header_len,
    uint64_t *out_value,
    size_t *out_consumed,
    ssize_t *out_err,
    const struct lantern_log_metadata *meta,
    const char *label,
    uint64_t deadline_ms)
{
    if (!stream || !header || !out_value || !out_consumed)
    {
        if (out_err)
        {
            *out_err = LIBP2P_ERR_NULL_PTR;
        }
        return LANTERN_REQRESP_ERR_INVALID_PARAM;
    }

    size_t used = 0;
    size_t consumed = 0;
    uint64_t value = 0;
    header[used++] = first_byte;

    while (unsigned_varint_decode(header, used, &value, &consumed) != UNSIGNED_VARINT_OK)
    {
        if (used == header_len)
        {
            if (out_err)
            {
                *out_err = LIBP2P_ERR_INTERNAL;
            }
            lantern_log_warn(
                "reqresp",
                meta,
                "%s varint header exceeded limit",
                label ? label : "chunk");
            return LANTERN_REQRESP_ERR_VARINT_HEADER_TOO_LONG;
        }

        uint8_t next_byte = 0;
        ssize_t read_err = 0;
        int rc = read_stream_byte_with_retry(stream, meta, label, deadline_ms, &next_byte, &read_err);
        if (rc != 0)
        {
            if (out_err)
            {
                *out_err = read_err;
            }
            lantern_log_warn(
                "reqresp",
                meta,
                "%s header read failed err=%zd",
                label ? label : "chunk",
                read_err);
            return rc;
        }

        header[used++] = next_byte;
    }

    *out_value = value;
    *out_consumed = consumed;
    if (out_err)
    {
        *out_err = 0;
    }
    return 0;
}


/**
 * @brief Logs decoded varint header details.
 */
static void log_varint_header_details(
    const uint8_t *header,
    size_t consumed,
    uint64_t payload_len,
    const struct lantern_log_metadata *meta,
    const char *label)
{
    char header_hex[(LANTERN_REQRESP_HEADER_MAX_BYTES * 2) + 1];
    header_hex[0] = '\0';
    if (lantern_bytes_to_hex(header, consumed, header_hex, sizeof(header_hex), 0) != 0)
    {
        header_hex[0] = '\0';
    }

    lantern_log_debug(
        "reqresp",
        meta,
        "%s payload_uncompressed_len=%" PRIu64 " header_hex=%s",
        label ? label : "chunk",
        payload_len,
        header_hex[0] ? header_hex : "-");
}


/**
 * @brief Validates a decoded payload length.
 */
static int validate_payload_len(
    uint64_t payload_len,
    ssize_t *out_err,
    const struct lantern_log_metadata *meta,
    const char *label)
{
    if ((payload_len > (uint64_t)LANTERN_REQRESP_MAX_CHUNK_BYTES)
        || (payload_len > (uint64_t)SIZE_MAX))
    {
        if (out_err)
        {
            *out_err = LIBP2P_ERR_MSG_TOO_LARGE;
        }
        lantern_log_warn(
            "reqresp",
            meta,
            "%s payload too large=%" PRIu64,
            label ? label : "chunk",
            payload_len);
        return LANTERN_REQRESP_ERR_PAYLOAD_TOO_LARGE;
    }
    return 0;
}


/**
 * @brief Allocates and reads a payload buffer.
 */
static int read_payload_bytes(
    libp2p_stream_t *stream,
    size_t payload_size,
    uint8_t **out_buffer,
    ssize_t *out_err,
    const struct lantern_log_metadata *meta,
    const char *label,
    uint64_t deadline_ms)
{
    if (!stream || !out_buffer)
    {
        if (out_err)
        {
            *out_err = LIBP2P_ERR_NULL_PTR;
        }
        return LANTERN_REQRESP_ERR_INVALID_PARAM;
    }

    uint8_t *buffer = malloc(payload_size);
    if (!buffer)
    {
        if (out_err)
        {
            *out_err = -ENOMEM;
        }
        lantern_log_error(
            "reqresp",
            meta,
            "%s payload allocation failed bytes=%zu",
            label ? label : "chunk",
            payload_size);
        return LANTERN_REQRESP_ERR_ALLOC;
    }

    size_t collected = 0;
    ssize_t read_err = 0;
    int rc = read_stream_exact(
        stream,
        meta,
        label,
        buffer,
        payload_size,
        deadline_ms,
        &collected,
        &read_err);
    if (rc != 0)
    {
        if (collected > 0)
        {
            char partial_hex[(LANTERN_STATUS_PREVIEW_BYTES * 2u) + 1u];
            size_t preview_max = (size_t)LANTERN_STATUS_PREVIEW_BYTES;
            size_t preview_len = collected < preview_max ? collected : preview_max;
            if (lantern_bytes_to_hex(buffer, preview_len, partial_hex, sizeof(partial_hex), 0) != 0)
            {
                partial_hex[0] = '\0';
            }
            lantern_log_trace(
                "reqresp",
                meta,
                "%s payload partial hex=%s%s",
                label ? label : "chunk",
                partial_hex[0] ? partial_hex : "-",
                (collected > preview_len) ? "..." : "");
        }

        free(buffer);
        if (out_err)
        {
            *out_err = read_err;
        }
        lantern_log_warn(
            "reqresp",
            meta,
            "%s payload read failed err=%zd collected=%zu/%zu",
            label ? label : "chunk",
            read_err,
            collected,
            payload_size);
        return rc;
    }

    if (out_err)
    {
        *out_err = 0;
    }
    *out_buffer = buffer;
    return 0;
}


/**
 * @brief Logs a completed payload read with a hex preview.
 */
static void log_payload_read_complete(
    const uint8_t *buffer,
    size_t payload_size,
    const struct lantern_log_metadata *meta,
    const char *label)
{
    char payload_hex[(LANTERN_STATUS_PREVIEW_BYTES * 2u) + 1u];
    payload_hex[0] = '\0';
    size_t preview = payload_size < (size_t)LANTERN_STATUS_PREVIEW_BYTES
        ? payload_size
        : (size_t)LANTERN_STATUS_PREVIEW_BYTES;
    if (preview > 0
        && lantern_bytes_to_hex(buffer, preview, payload_hex, sizeof(payload_hex), 0) != 0)
    {
        payload_hex[0] = '\0';
    }
    lantern_log_debug(
        "reqresp",
        meta,
        "%s payload read complete bytes=%zu%s%s",
        label ? label : "chunk",
        payload_size,
        payload_hex[0] ? " hex=" : "",
        payload_hex[0] ? payload_hex : "");
}


/* ============================================================================
 * Stream Write Operations
 * ============================================================================ */

/**
 * Write all bytes to a stream.
 *
 * @spec Ethernet 2.0 Networking Spec - ReqResp Protocol
 *
 * Implements reliable stream writing with retry on AGAIN/TIMEOUT errors.
 * Used for sending request payloads to peers.
 *
 * @param stream  libp2p stream
 * @param data    Data to write
 * @param length  Number of bytes to write
 * @param out_err Optional output error code (may be NULL)
 * @return 0 on success
 * @return LANTERN_REQRESP_ERR_INVALID_PARAM if parameters are invalid
 * @return LANTERN_REQRESP_ERR_STREAM_WRITE on stream write failure
 *
 * @note Thread safety: This function is thread-safe
 */
int stream_write_all(
    libp2p_stream_t *stream,
    const uint8_t *data,
    size_t length,
    ssize_t *out_err)
{
    if (!stream || (!data && length > 0))
    {
        if (out_err)
        {
            *out_err = LIBP2P_ERR_NULL_PTR;
        }
        return LANTERN_REQRESP_ERR_INVALID_PARAM;
    }

    char peer_text[LANTERN_REQRESP_PEER_TEXT_BYTES];
    struct lantern_log_metadata meta;
    init_peer_log_metadata(stream, peer_text, sizeof(peer_text), &meta);

    uint64_t deadline_ms = UINT64_MAX;
    uint64_t now_ms = reqresp_now_ms();
    uint64_t stall_timeout_ms = lantern_reqresp_stall_timeout_ms();
    if (stall_timeout_ms > 0u
        && now_ms != 0u
        && now_ms <= UINT64_MAX - stall_timeout_ms)
    {
        deadline_ms = now_ms + stall_timeout_ms;
    }

    size_t offset = 0;
    while (offset < length)
    {
        if (deadline_ms != UINT64_MAX)
        {
            now_ms = reqresp_now_ms();
            if (now_ms != 0u && now_ms >= deadline_ms)
            {
                if (out_err)
                {
                    *out_err = LIBP2P_ERR_TIMEOUT;
                }
                lantern_log_warn(
                    "reqresp",
                    &meta,
                    "stream write timed out bytes_written=%zu total_bytes=%zu",
                    offset,
                    length);
                return LANTERN_REQRESP_ERR_STREAM_WRITE;
            }

            uint64_t remaining_ms = (now_ms == 0u) ? stall_timeout_ms : (deadline_ms - now_ms);
            if (remaining_ms == 0u)
            {
                remaining_ms = 1u;
            }
            int deadline_rc = libp2p_stream_set_deadline(stream, remaining_ms);
            if (deadline_rc != 0)
            {
                if (out_err)
                {
                    *out_err = (ssize_t)deadline_rc;
                }
                lantern_log_warn(
                    "reqresp",
                    &meta,
                    "failed to set write deadline err=%d",
                    deadline_rc);
                return LANTERN_REQRESP_ERR_STREAM_WRITE;
            }
        }

        ssize_t written = libp2p_stream_write(stream, data + offset, length - offset);
        if (written > 0)
        {
            offset += (size_t)written;
            continue;
        }
        if (written == (ssize_t)LIBP2P_ERR_AGAIN || written == (ssize_t)LIBP2P_ERR_TIMEOUT)
        {
            continue;
        }
        if (out_err)
        {
            *out_err = (written == 0) ? (ssize_t)LIBP2P_ERR_CLOSED : written;
        }
        return LANTERN_REQRESP_ERR_STREAM_WRITE;
    }
    if (out_err)
    {
        *out_err = 0;
    }
    return 0;
}


/* ============================================================================
 * Response Chunk Reading
 * ============================================================================ */

/**
 * Read a response chunk from a reqresp stream.
 *
 * @spec subspecs/networking/reqresp/message.py - Response framing
 *
 * Handles response framing with a required response code byte.
 * The response code byte indicates success (0), invalid request (1),
 * server error (2), or resource unavailable (3). Unknown codes are
 * mapped per spec.
 *
 * Protocol flow:
 * 1. Read response code byte (if expected)
 * 2. Read varint-prefixed payload
 *
 * @param service               Reqresp service (may be NULL)
 * @param stream                libp2p stream
 * @param protocol              Protocol kind
 * @param out_data              Output data buffer (caller must free)
 * @param out_len               Output data length
 * @param out_err               Output error code (may be NULL)
 * @param out_response_code     Output response code (may be NULL)
 * @param response_code_pending Tracks whether response code is still expected
 * @return 0 on success
 * @return LANTERN_REQRESP_ERR_INVALID_PARAM if required parameters are NULL
 * @return LANTERN_REQRESP_ERR_SET_READ_INTEREST if enabling read interest fails
 * @return LANTERN_REQRESP_ERR_SET_DEADLINE if setting a stream deadline fails
 * @return LANTERN_REQRESP_ERR_STREAM_READ if reading from the stream fails
 * @return LANTERN_REQRESP_ERR_VARINT_HEADER_TOO_LONG if the varint header exceeds limits
 * @return LANTERN_REQRESP_ERR_PAYLOAD_TOO_LARGE if the payload length exceeds limits
 * @return LANTERN_REQRESP_ERR_ALLOC if allocating the payload buffer fails
 *
 * @note Thread safety: This function is thread-safe
 */
int lantern_reqresp_read_response_chunk(
    struct lantern_reqresp_service *service,
    libp2p_stream_t *stream,
    enum lantern_reqresp_protocol_kind protocol,
    uint8_t **out_data,
    size_t *out_len,
    ssize_t *out_err,
    uint8_t *out_response_code,
    bool *response_code_pending)
{
    if (!stream || !out_data || !out_len)
    {
        if (out_err)
        {
            *out_err = LIBP2P_ERR_NULL_PTR;
        }
        return LANTERN_REQRESP_ERR_INVALID_PARAM;
    }
    if (out_response_code)
    {
        *out_response_code = LANTERN_REQRESP_RESPONSE_SERVER_ERROR;
    }

    char peer_text[LANTERN_REQRESP_PEER_TEXT_BYTES];
    struct lantern_log_metadata meta;
    init_peer_log_metadata(stream, peer_text, sizeof(peer_text), &meta);

    int interest_rc = libp2p_stream_set_read_interest(stream, true);
    if (interest_rc != 0)
    {
        if (out_err)
        {
            *out_err = (ssize_t)interest_rc;
        }
        lantern_log_warn(
            "reqresp",
            &meta,
            "failed to set read interest err=%d",
            interest_rc);
        return LANTERN_REQRESP_ERR_SET_READ_INTEREST;
    }

    bool expect_code = response_code_pending
        ? *response_code_pending
        : protocol_expects_response_code(protocol);
    uint64_t start_ms = reqresp_now_ms();
    uint64_t ttfb_deadline_ms = start_ms + LANTERN_REQRESP_TTFB_TIMEOUT_MS;
    uint64_t resp_deadline_ms = start_ms + LANTERN_REQRESP_RESP_TIMEOUT_MS;
    uint8_t frame_code = 0;
    uint8_t response_code_byte = 0;
    bool missing_response_code = false;
    uint8_t missing_code_header_first = 0;
    int rc = read_response_code_prefix(
        service,
        stream,
        expect_code,
        &meta,
        peer_text,
        ttfb_deadline_ms,
        &frame_code,
        &response_code_byte,
        out_response_code,
        &missing_response_code,
        &missing_code_header_first,
        out_err);
    if (rc != 0)
    {
        return rc;
    }
    if (response_code_pending)
    {
        *response_code_pending = false;
    }

    uint8_t header_first_byte = 0;
    if (missing_response_code)
    {
        header_first_byte = missing_code_header_first;
    }
    else
    {
        uint64_t header_deadline_ms = expect_code ? resp_deadline_ms : ttfb_deadline_ms;
        rc = read_payload_header_first_byte(
            stream,
            expect_code,
            &meta,
            header_deadline_ms,
            &header_first_byte,
            out_err);
        if (rc != 0)
        {
            return rc;
        }
    }

    lantern_log_trace(
        "reqresp",
        &meta,
        "response using varint framing code=0x%02x header_first=0x%02x",
        (unsigned)frame_code,
        (unsigned)header_first_byte);

    bool legacy_len = false;
    int payload_rc = 0;
    if (missing_response_code)
    {
        uint8_t header[LANTERN_REQRESP_HEADER_MAX_BYTES];
        uint64_t payload_len = 0;
        size_t consumed = 0;
        payload_rc = read_varint_header_from_first_byte(
            stream,
            header_first_byte,
            header,
            sizeof(header),
            &payload_len,
            &consumed,
            out_err,
            &meta,
            "chunk",
            resp_deadline_ms);
        if (payload_rc == 0)
        {
            log_varint_header_details(header, consumed, payload_len, &meta, "chunk");
            payload_rc = validate_payload_len(payload_len, out_err, &meta, "chunk");
        }
        if (payload_rc == 0)
        {
            if (payload_len == 0)
            {
                *out_data = NULL;
                *out_len = 0;
            }
            else
            {
                uint8_t *buffer = NULL;
                payload_rc = read_payload_bytes(
                    stream,
                    (size_t)payload_len,
                    &buffer,
                    out_err,
                    &meta,
                    "chunk",
                    resp_deadline_ms);
                if (payload_rc == 0)
                {
                    *out_data = buffer;
                    *out_len = (size_t)payload_len;
                }
            }
        }
        if (payload_rc == 0)
        {
            if (out_err)
            {
                *out_err = 0;
            }
            log_payload_read_complete(*out_data, *out_len, &meta, "chunk");
            legacy_len = true;
        }
    }
    else
    {
        payload_rc = read_varint_payload_chunk(
            stream,
            header_first_byte,
            out_data,
            out_len,
            &legacy_len,
            out_err,
            &meta,
            "chunk",
            resp_deadline_ms);
    }
    if (payload_rc == 0 && legacy_len && service && service->callbacks.context && peer_text[0])
    {
        lantern_client_mark_peer_reqresp_legacy(
            (struct lantern_client *)service->callbacks.context,
            peer_text);
    }

    return payload_rc;
}


/**
 * Read a payload chunk with varint header.
 *
 * @spec subspecs/networking/reqresp/message.py - Varint-prefixed payload
 *
 * Decodes the varint length header and reads the full payload.
 * Validates payload size against protocol limits.
 *
 * @param stream      libp2p stream
 * @param first_byte  First byte already read
 * @param out_data    Output data buffer (caller must free)
 * @param out_len     Output data length
 * @param out_err     Output error code (may be NULL)
 * @param meta        Log metadata
 * @param label       Label for logging
 * @return 0 on success
 * @return LANTERN_REQRESP_ERR_INVALID_PARAM if required parameters are NULL
 * @return LANTERN_REQRESP_ERR_SET_DEADLINE if setting a stream deadline fails
 * @return LANTERN_REQRESP_ERR_STREAM_READ if reading from the stream fails
 * @return LANTERN_REQRESP_ERR_VARINT_HEADER_TOO_LONG if the varint header exceeds limits
 * @return LANTERN_REQRESP_ERR_PAYLOAD_TOO_LARGE if the payload length exceeds limits
 * @return LANTERN_REQRESP_ERR_ALLOC if allocating the payload buffer fails
 *
 * @note Thread safety: This function is thread-safe
 */
static int read_varint_payload_chunk(
    libp2p_stream_t *stream,
    uint8_t first_byte,
    uint8_t **out_data,
    size_t *out_len,
    bool *out_legacy_len,
    ssize_t *out_err,
    const struct lantern_log_metadata *meta,
    const char *label,
    uint64_t deadline_ms)
{
    if (!stream || !out_data || !out_len)
    {
        if (out_err)
        {
            *out_err = LIBP2P_ERR_NULL_PTR;
        }
        return LANTERN_REQRESP_ERR_INVALID_PARAM;
    }
    if (out_legacy_len)
    {
        *out_legacy_len = false;
    }

    uint8_t header[LANTERN_REQRESP_HEADER_MAX_BYTES];
    uint64_t payload_len = 0;
    size_t consumed = 0;
    int rc = read_varint_header_from_first_byte(
        stream,
        first_byte,
        header,
        sizeof(header),
        &payload_len,
        &consumed,
        out_err,
        meta,
        label,
        deadline_ms);
    if (rc != 0)
    {
        return rc;
    }

    log_varint_header_details(header, consumed, payload_len, meta, label);

    rc = validate_payload_len(payload_len, out_err, meta, label);
    if (rc != 0)
    {
        return rc;
    }

    uint8_t *buffer = NULL;
    size_t payload_size = 0;
    rc = read_snappy_framed_payload(
        stream,
        meta,
        label,
        payload_len,
        deadline_ms,
        &buffer,
        &payload_size,
        out_legacy_len,
        out_err);
    if (rc != 0)
    {
        return rc;
    }

    *out_data = buffer;
    *out_len = payload_size;
    if (out_err)
    {
        *out_err = 0;
    }

    log_payload_read_complete(buffer, payload_size, meta, label);
    return 0;
}
