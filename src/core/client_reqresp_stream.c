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

#include "lantern/networking/reqresp_service.h"
#include "lantern/support/strings.h"
#include "lantern/support/log.h"

#include "libp2p/errors.h"
#include "libp2p/stream.h"
#include "multiformats/unsigned_varint/unsigned_varint.h"
#include "peer_id/peer_id.h"

#include <errno.h>
#include <inttypes.h>
#include <stdlib.h>
#include <string.h>


/* ============================================================================
 * Constants
 * ============================================================================ */

/** Maximum bytes for a reqresp header varint */
#define LANTERN_REQRESP_HEADER_MAX_BYTES 10u


/* ============================================================================
 * Forward Declarations
 * ============================================================================ */

static int read_varint_payload_chunk(
    libp2p_stream_t *stream,
    uint8_t first_byte,
    uint8_t **out_data,
    size_t *out_len,
    ssize_t *out_err,
    const struct lantern_log_metadata *meta,
    const char *label);


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
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: This function is thread-safe
 */
int stream_write_all(libp2p_stream_t *stream, const uint8_t *data, size_t length)
{
    if (!stream || (!data && length > 0))
    {
        return -1;
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
        return -1;
    }
    return 0;
}


/* ============================================================================
 * Varint Reading Operations
 * ============================================================================ */

/**
 * Read a varint from a stream.
 *
 * @spec Ethernet 2.0 Networking Spec - SSZ-snappy encoding with varint length prefix
 *
 * Reads an unsigned varint (LEB128-style) from the stream byte by byte.
 * Used for decoding length-prefixed payloads in the reqresp protocol.
 *
 * @param stream     libp2p stream
 * @param out_value  Output value
 * @param meta       Log metadata
 * @param label      Label for logging
 * @param out_err    Output error code (may be NULL)
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: This function is thread-safe
 */
int read_stream_varint(
    libp2p_stream_t *stream,
    uint64_t *out_value,
    const struct lantern_log_metadata *meta,
    const char *label,
    ssize_t *out_err)
{
    if (!stream || !out_value)
    {
        if (out_err)
        {
            *out_err = LIBP2P_ERR_NULL_PTR;
        }
        return -1;
    }

    uint8_t header[LANTERN_REQRESP_HEADER_MAX_BYTES];
    size_t header_used = 0;
    uint64_t value = 0;
    ssize_t last_err = 0;

    while (header_used < sizeof(header))
    {
        (void)libp2p_stream_set_deadline(stream, LANTERN_REQRESP_STALL_TIMEOUT_MS);
        ssize_t n = libp2p_stream_read(stream, &header[header_used], 1);
        if (n == 1)
        {
            header_used += 1;
            size_t consumed = 0;
            if (unsigned_varint_decode(header, header_used, &value, &consumed) == UNSIGNED_VARINT_OK)
            {
                lantern_log_trace(
                    "reqresp",
                    meta,
                    "%s decoded length=%" PRIu64,
                    label ? label : "varint",
                    value);
                (void)libp2p_stream_set_deadline(stream, 0);
                *out_value = value;
                if (out_err)
                {
                    *out_err = 0;
                }
                return 0;
            }
            continue;
        }
        if (n == (ssize_t)LIBP2P_ERR_AGAIN)
        {
            continue;
        }
        if (n == 0 || n == (ssize_t)LIBP2P_ERR_EOF || n == (ssize_t)LIBP2P_ERR_CLOSED || n == (ssize_t)LIBP2P_ERR_RESET)
        {
            last_err = n == 0 ? (ssize_t)LIBP2P_ERR_EOF : n;
            break;
        }
        last_err = n;
        break;
    }
    (void)libp2p_stream_set_deadline(stream, 0);

    if (out_err)
    {
        *out_err = last_err == 0 ? LIBP2P_ERR_INTERNAL : last_err;
    }
    lantern_log_trace(
        "reqresp",
        meta,
        "%s decode failed err=%zd bytes=%zu",
        label ? label : "varint",
        last_err == 0 ? (ssize_t)LIBP2P_ERR_INTERNAL : last_err,
        header_used);
    return -1;
}


/**
 * Discard bytes from a stream.
 *
 * @spec Ethernet 2.0 Networking Spec - Error recovery
 *
 * Reads and discards a specified number of bytes from the stream.
 * Used for skipping error message payloads or unwanted data.
 *
 * @param stream   libp2p stream
 * @param length   Number of bytes to discard
 * @param meta     Log metadata
 * @param label    Label for logging
 * @param out_err  Output error code (may be NULL)
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: This function is thread-safe
 */
int discard_stream_bytes(
    libp2p_stream_t *stream,
    uint64_t length,
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
        return -1;
    }
    uint8_t buffer[256];
    uint64_t remaining = length;
    while (remaining > 0)
    {
        size_t chunk = remaining > sizeof(buffer) ? sizeof(buffer) : (size_t)remaining;
        (void)libp2p_stream_set_deadline(stream, LANTERN_REQRESP_STALL_TIMEOUT_MS);
        ssize_t n = libp2p_stream_read(stream, buffer, chunk);
        if (n > 0)
        {
            remaining -= (size_t)n;
            continue;
        }
        if (n == (ssize_t)LIBP2P_ERR_AGAIN)
        {
            continue;
        }
        (void)libp2p_stream_set_deadline(stream, 0);
        if (out_err)
        {
            *out_err = n == 0 ? (ssize_t)LIBP2P_ERR_EOF : n;
        }
        lantern_log_trace(
            "reqresp",
            meta,
            "%s discard failed err=%zd remaining=%" PRIu64,
            label ? label : "context",
            n,
            remaining);
        return -1;
    }
    (void)libp2p_stream_set_deadline(stream, 0);
    lantern_log_trace(
        "reqresp",
        meta,
        "%s discarded bytes=%" PRIu64,
        label ? label : "context",
        length);
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
 * @return 0 on success, -1 on failure
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
        return -1;
    }
    if (out_response_code)
    {
        *out_response_code = LANTERN_REQRESP_RESPONSE_SERVER_ERROR;
    }

    char peer_text[128];
    peer_text[0] = '\0';
    const peer_id_t *peer = libp2p_stream_remote_peer(stream);
    if (peer && peer_id_to_string(peer, PEER_ID_FMT_BASE58_LEGACY, peer_text, sizeof(peer_text)) < 0)
    {
        peer_text[0] = '\0';
    }
    const struct lantern_log_metadata meta = {.peer = peer_text[0] ? peer_text : NULL};

    (void)libp2p_stream_set_read_interest(stream, true);

    uint8_t response_code = 0;
    bool expect_code = response_code_pending
        ? *response_code_pending
        : ((protocol == LANTERN_REQRESP_PROTOCOL_STATUS) || (protocol == LANTERN_REQRESP_PROTOCOL_BLOCKS_BY_ROOT));
    bool legacy_no_code = !expect_code;
    ssize_t last_err = 0;
    uint8_t frame_code = 0;
    if (expect_code)
    {
        while (true)
        {
            (void)libp2p_stream_set_deadline(stream, LANTERN_REQRESP_STALL_TIMEOUT_MS);
            ssize_t n = libp2p_stream_read(stream, &response_code, 1);
            if (n == 1)
            {
                frame_code = response_code;
                break;
            }
            if (n == (ssize_t)LIBP2P_ERR_AGAIN)
            {
                continue;
            }
            (void)libp2p_stream_set_deadline(stream, 0);
            last_err = n == 0 ? (ssize_t)LIBP2P_ERR_EOF : n;
            if (out_err)
            {
                *out_err = last_err;
            }
            lantern_log_trace(
                "reqresp",
                &meta,
                "response code read failed err=%zd",
                last_err);
            return -1;
        }
        (void)libp2p_stream_set_deadline(stream, 0);
        if (response_code > LANTERN_REQRESP_RESPONSE_SERVER_ERROR)
        {
            legacy_no_code = true;
            if (out_response_code)
            {
                *out_response_code = LANTERN_REQRESP_RESPONSE_SUCCESS;
            }
            lantern_log_trace(
                "reqresp",
                &meta,
                "legacy response missing code, treating first byte as header (0x%02x)",
                (unsigned)response_code);
            lantern_log_info(
                "reqresp",
                &meta,
                "response legacy framing first_byte=0x%02x",
                (unsigned)response_code);
            if (service && peer_text[0] != '\0')
            {
#if defined(LANTERN_REQRESP_STATUS_PROTOCOL_LEGACY) || defined(LANTERN_REQRESP_BLOCKS_BY_ROOT_PROTOCOL_LEGACY)
                lantern_reqresp_service_hint_peer_legacy(service, peer_text, 1);
#endif
            }
        }
        else
        {
            if (out_response_code)
            {
                *out_response_code = response_code;
            }
            frame_code = response_code;
            lantern_log_info(
                "reqresp",
                &meta,
                "response code=%u",
                (unsigned)response_code);
            if (service && peer_text[0] != '\0')
            {
#if defined(LANTERN_REQRESP_STATUS_PROTOCOL_LEGACY) || defined(LANTERN_REQRESP_BLOCKS_BY_ROOT_PROTOCOL_LEGACY)
                lantern_reqresp_service_hint_peer_legacy(service, peer_text, 0);
#endif
            }
        }
    }
    else
    {
        if (out_response_code)
        {
            *out_response_code = LANTERN_REQRESP_RESPONSE_SUCCESS;
        }
    }
    if (response_code_pending)
    {
        *response_code_pending = false;
    }

    uint8_t header_first_byte = 0;
    if (legacy_no_code && expect_code)
    {
        header_first_byte = response_code;
    }
    else
    {
        while (true)
        {
            (void)libp2p_stream_set_deadline(stream, LANTERN_REQRESP_STALL_TIMEOUT_MS);
            ssize_t n = libp2p_stream_read(stream, &header_first_byte, 1);
            if (n == 1)
            {
                break;
            }
            if (n == (ssize_t)LIBP2P_ERR_AGAIN)
            {
                continue;
            }
            (void)libp2p_stream_set_deadline(stream, 0);
            last_err = n == 0 ? (ssize_t)LIBP2P_ERR_EOF : n;
            if (out_err)
            {
                *out_err = last_err;
            }
            lantern_log_trace(
                "reqresp",
                &meta,
                "response payload header read failed err=%zd",
                last_err);
            return -1;
        }
        (void)libp2p_stream_set_deadline(stream, 0);
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
 * @return 0 on success, -1 on failure
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
        return -1;
    }

    uint8_t header[LANTERN_REQRESP_HEADER_MAX_BYTES];
    size_t used = 0;
    uint64_t payload_len = 0;
    size_t consumed = 0;
    header[used++] = first_byte;

    while (true)
    {
        if (unsigned_varint_decode(header, used, &payload_len, &consumed) == UNSIGNED_VARINT_OK)
        {
            break;
        }
        if (used == sizeof(header))
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
            return -1;
        }
        (void)libp2p_stream_set_deadline(stream, LANTERN_REQRESP_STALL_TIMEOUT_MS);
        ssize_t n = libp2p_stream_read(stream, &header[used], 1);
        if (n == 1)
        {
            used += 1;
            continue;
        }
        if (n == (ssize_t)LIBP2P_ERR_AGAIN)
        {
            continue;
        }
        (void)libp2p_stream_set_deadline(stream, 0);
        if (out_err)
        {
            *out_err = n == 0 ? (ssize_t)LIBP2P_ERR_EOF : n;
        }
        lantern_log_warn(
            "reqresp",
            meta,
            "%s header read failed err=%zd",
            label ? label : "chunk",
            n);
        return -1;
    }
    (void)libp2p_stream_set_deadline(stream, 0);

    char header_hex[(sizeof(header) * 2) + 1];
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
    if (payload_len > 512)
    {
        lantern_log_warn(
            "reqresp",
            meta,
            "%s suspicious large payload_len=%" PRIu64 " header_hex=%s",
            label ? label : "chunk",
            payload_len,
            header_hex[0] ? header_hex : "-");
    }

    if (payload_len > LANTERN_REQRESP_MAX_CHUNK_BYTES || payload_len > SIZE_MAX)
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
        return -1;
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
    uint8_t *buffer = (uint8_t *)malloc(payload_size);
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
        return -1;
    }

    size_t collected = 0;
    while (collected < payload_size)
    {
        (void)libp2p_stream_set_deadline(stream, LANTERN_REQRESP_STALL_TIMEOUT_MS);
        ssize_t n = libp2p_stream_read(stream, buffer + collected, payload_size - collected);
        if (n > 0)
        {
            collected += (size_t)n;
            continue;
        }
        if (n == (ssize_t)LIBP2P_ERR_AGAIN)
        {
            continue;
        }
        (void)libp2p_stream_set_deadline(stream, 0);
        if (collected > 0)
        {
            char partial_hex[(LANTERN_STATUS_PREVIEW_BYTES * 2u) + 1u];
            size_t preview_len = collected < LANTERN_STATUS_PREVIEW_BYTES ? collected : LANTERN_STATUS_PREVIEW_BYTES;
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
            *out_err = n == 0 ? (ssize_t)LIBP2P_ERR_EOF : n;
        }
        lantern_log_warn(
            "reqresp",
            meta,
            "%s payload read failed err=%zd collected=%zu/%zu",
            label ? label : "chunk",
            n,
            collected,
            payload_size);
        return -1;
    }
    (void)libp2p_stream_set_deadline(stream, 0);

    *out_data = buffer;
    *out_len = payload_size;
    if (out_err)
    {
        *out_err = 0;
    }
    char payload_hex[(LANTERN_STATUS_PREVIEW_BYTES * 2u) + 1u];
    payload_hex[0] = '\0';
    size_t preview = payload_size < LANTERN_STATUS_PREVIEW_BYTES ? payload_size : LANTERN_STATUS_PREVIEW_BYTES;
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
    return 0;
}
