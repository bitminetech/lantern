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
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "libp2p/errors.h"
#include "libp2p/stream.h"
#include "multiformats/unsigned_varint/unsigned_varint.h"
#include "peer_id/peer_id.h"

#include "lantern/networking/reqresp_service.h"
#include "lantern/support/log.h"
#include "lantern/support/strings.h"


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


/* ============================================================================
 * Forward Declarations
 * ============================================================================ */

static void init_peer_log_metadata(
    libp2p_stream_t *stream,
    char *peer_text,
    size_t peer_text_len,
    struct lantern_log_metadata *out_meta);
static void hint_peer_legacy_framing(
    struct lantern_reqresp_service *service,
    const char *peer_text,
    bool is_legacy);
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
    uint8_t *out_byte,
    ssize_t *out_err);
static int read_response_code_prefix(
    struct lantern_reqresp_service *service,
    libp2p_stream_t *stream,
    bool expect_code,
    const struct lantern_log_metadata *meta,
    const char *peer_text,
    uint8_t *out_frame_code,
    uint8_t *out_response_code_byte,
    bool *out_legacy_no_code,
    uint8_t *out_response_code,
    ssize_t *out_err);
static int read_payload_header_first_byte(
    libp2p_stream_t *stream,
    bool expect_code,
    bool legacy_no_code,
    uint8_t response_code_byte,
    const struct lantern_log_metadata *meta,
    uint8_t *out_header_first_byte,
    ssize_t *out_err);
static int read_stream_exact(
    libp2p_stream_t *stream,
    const struct lantern_log_metadata *meta,
    const char *label,
    uint8_t *buffer,
    size_t buffer_len,
    size_t *out_read,
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
    const char *label);
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
    const char *label);
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
    ssize_t *out_err,
    const struct lantern_log_metadata *meta,
    const char *label);


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
 * @brief Records peer legacy framing preference.
 */
static void hint_peer_legacy_framing(
    struct lantern_reqresp_service *service,
    const char *peer_text,
    bool is_legacy)
{
    if (!service || !peer_text || peer_text[0] == '\0')
    {
        return;
    }

#if defined(LANTERN_REQRESP_STATUS_PROTOCOL_LEGACY) \
    || defined(LANTERN_REQRESP_BLOCKS_BY_ROOT_PROTOCOL_LEGACY)
    lantern_reqresp_service_hint_peer_legacy(service, peer_text, is_legacy ? 1 : 0);
#else
    (void)is_legacy;
#endif
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


/**
 * @brief Reads a single byte from a stream, retrying on AGAIN.
 */
static int read_stream_byte_with_retry(
    libp2p_stream_t *stream,
    const struct lantern_log_metadata *meta,
    const char *label,
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
        int rc = set_stream_deadline(
            stream,
            LANTERN_REQRESP_STALL_TIMEOUT_MS,
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
    uint8_t *out_frame_code,
    uint8_t *out_response_code_byte,
    bool *out_legacy_no_code,
    uint8_t *out_response_code,
    ssize_t *out_err)
{
    if (!out_frame_code || !out_response_code_byte || !out_legacy_no_code)
    {
        if (out_err)
        {
            *out_err = LIBP2P_ERR_NULL_PTR;
        }
        return LANTERN_REQRESP_ERR_INVALID_PARAM;
    }

    *out_frame_code = 0;
    *out_response_code_byte = 0;
    *out_legacy_no_code = !expect_code;

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

    if (response_code_byte > LANTERN_REQRESP_RESPONSE_SERVER_ERROR)
    {
        *out_legacy_no_code = true;
        if (out_response_code)
        {
            *out_response_code = LANTERN_REQRESP_RESPONSE_SUCCESS;
        }

        lantern_log_trace(
            "reqresp",
            meta,
            "legacy response missing code, treating first byte as header (0x%02x)",
            (unsigned)response_code_byte);
        lantern_log_info(
            "reqresp",
            meta,
            "response legacy framing first_byte=0x%02x",
            (unsigned)response_code_byte);
        hint_peer_legacy_framing(service, peer_text, true);
    }
    else
    {
        *out_legacy_no_code = false;
        if (out_response_code)
        {
            *out_response_code = response_code_byte;
        }
        lantern_log_info("reqresp", meta, "response code=%u", (unsigned)response_code_byte);
        hint_peer_legacy_framing(service, peer_text, false);
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
    bool legacy_no_code,
    uint8_t response_code_byte,
    const struct lantern_log_metadata *meta,
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

    if (legacy_no_code && expect_code)
    {
        *out_header_first_byte = response_code_byte;
        if (out_err)
        {
            *out_err = 0;
        }
        return 0;
    }

    ssize_t read_err = 0;
    int rc = read_stream_byte_with_retry(
        stream,
        meta,
        "payload header",
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
        int rc = set_stream_deadline(
            stream,
            LANTERN_REQRESP_STALL_TIMEOUT_MS,
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
    const char *label)
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
        int rc = read_stream_byte_with_retry(stream, meta, label, &next_byte, &read_err);
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

    lantern_log_info(
        "reqresp",
        meta,
        "%s payload_len=%" PRIu64 " header_hex=%s",
        label ? label : "chunk",
        payload_len,
        header_hex[0] ? header_hex : "-");
    if (payload_len > (uint64_t)LANTERN_REQRESP_SUSPICIOUS_PAYLOAD_BYTES)
    {
        lantern_log_warn(
            "reqresp",
            meta,
            "%s suspicious large payload_len=%" PRIu64 " header_hex=%s",
            label ? label : "chunk",
            payload_len,
            header_hex[0] ? header_hex : "-");
    }
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
    const char *label)
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
    int rc = read_stream_exact(stream, meta, label, buffer, payload_size, &collected, &read_err);
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
    lantern_log_info(
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
    size_t offset = 0;
    while (offset < length)
    {
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
 * Handles both modern (with response code) and legacy (no code) framing.
 * The response code byte indicates success (0), invalid request (1),
 * or server error (2). Legacy peers omit this byte entirely.
 *
 * Protocol flow:
 * 1. Read response code byte (if expected)
 * 2. Detect legacy framing if code > 2 (treat as varint header)
 * 3. Read varint-prefixed payload
 * 4. Update peer preference tracking for future requests
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
    uint8_t frame_code = 0;
    uint8_t response_code_byte = 0;
    bool legacy_no_code = false;
    int rc = read_response_code_prefix(
        service,
        stream,
        expect_code,
        &meta,
        peer_text,
        &frame_code,
        &response_code_byte,
        &legacy_no_code,
        out_response_code,
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
    rc = read_payload_header_first_byte(
        stream,
        expect_code,
        legacy_no_code,
        response_code_byte,
        &meta,
        &header_first_byte,
        out_err);
    if (rc != 0)
    {
        return rc;
    }

    lantern_log_trace(
        "reqresp",
        &meta,
        "response using varint framing code=0x%02x header_first=0x%02x",
        (unsigned)frame_code,
        (unsigned)header_first_byte);

    return read_varint_payload_chunk(
        stream,
        header_first_byte,
        out_data,
        out_len,
        out_err,
        &meta,
        "chunk");
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
    ssize_t *out_err,
    const struct lantern_log_metadata *meta,
    const char *label)
{
    if (!stream || !out_data || !out_len)
    {
        if (out_err)
        {
            *out_err = LIBP2P_ERR_NULL_PTR;
        }
        return LANTERN_REQRESP_ERR_INVALID_PARAM;
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
        label);
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

    if (payload_len == 0)
    {
        *out_data = NULL;
        *out_len = 0;
        if (out_err)
        {
            *out_err = 0;
        }
        return 0;
    }

    size_t payload_size = (size_t)payload_len;
    uint8_t *buffer = NULL;
    rc = read_payload_bytes(stream, payload_size, &buffer, out_err, meta, label);
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
