/**
 * @file common.c
 * @brief Common helpers for writing HTTP responses.
 *
 * Provides socket send helpers used by Lantern's HTTP modules.
 *
 * @spec RFC 9110 (HTTP Semantics) and RFC 9112 (HTTP/1.1).
 */

#include "lantern/http/common.h"

#include <errno.h>
#include <stdio.h>
#include <sys/socket.h>
#include <sys/types.h>

static const size_t HTTP_RESPONSE_HEADER_BUFFER_LEN = 256;
static const int HTTP_STATUS_CODE_MIN = 100;
static const int HTTP_STATUS_CODE_MAX = 999;

/**
 * HTTP module-specific error codes.
 */
enum
{
    LANTERN_HTTP_OK = 0,
    LANTERN_HTTP_ERR_INVALID_PARAM = -1,
    LANTERN_HTTP_ERR_SEND_FAILED = -2,
    LANTERN_HTTP_ERR_HEADER_TOO_LARGE = -3,
};

/**
 * Send the provided buffer to a socket, retrying short writes.
 *
 * @param fd     Socket file descriptor to write to.
 * @param data   Bytes to send (not modified).
 * @param length Number of bytes to send.
 *
 * @spec POSIX send(2)
 *
 * @return 0 on success.
 * @return LANTERN_HTTP_ERR_INVALID_PARAM on invalid parameters.
 * @return LANTERN_HTTP_ERR_SEND_FAILED on write failure.
 *
 * @note Thread safety: Caller must ensure exclusive access to `fd`.
 */
int lantern_http_send_all(int fd, const char *data, size_t length)
{
    if (fd < 0)
    {
        return LANTERN_HTTP_ERR_INVALID_PARAM;
    }
    if (length == 0)
    {
        return 0;
    }
    if (!data)
    {
        return LANTERN_HTTP_ERR_INVALID_PARAM;
    }

    int flags = 0;
#ifdef MSG_NOSIGNAL
    flags |= MSG_NOSIGNAL;
#endif

    while (length > 0)
    {
        ssize_t written = send(fd, data, length, flags);
        if (written == 0)
        {
            return LANTERN_HTTP_ERR_SEND_FAILED;
        }
        if (written < 0)
        {
            if (errno == EINTR)
            {
                continue;
            }
            return LANTERN_HTTP_ERR_SEND_FAILED;
        }

        size_t bytes_written = (size_t)written;
        data += bytes_written;
        length -= bytes_written;
    }

    return 0;
}


/**
 * Send an HTTP/1.1 response and optional body to a socket.
 *
 * @param fd           Socket file descriptor to write to.
 * @param status_code  HTTP status code (100-999).
 * @param status_text  Optional HTTP status text (defaults to "OK").
 * @param content_type Optional Content-Type header value (defaults to application/json).
 * @param body         Optional response body (may be NULL when body_len is 0).
 * @param body_len     Number of bytes in body.
 *
 * @spec RFC 9110 (HTTP Semantics) and RFC 9112 (HTTP/1.1)
 *
 * @return 0 on success.
 * @return LANTERN_HTTP_ERR_INVALID_PARAM on invalid parameters.
 * @return LANTERN_HTTP_ERR_SEND_FAILED on write failure.
 * @return LANTERN_HTTP_ERR_HEADER_TOO_LARGE on header formatting/truncation failure.
 *
 * @note Thread safety: Caller must ensure exclusive access to `fd`.
 */
int lantern_http_send_response(
    int fd,
    int status_code,
    const char *status_text,
    const char *content_type,
    const char *body,
    size_t body_len)
{
    if (fd < 0)
    {
        return LANTERN_HTTP_ERR_INVALID_PARAM;
    }
    if (status_code < HTTP_STATUS_CODE_MIN || status_code > HTTP_STATUS_CODE_MAX)
    {
        return LANTERN_HTTP_ERR_INVALID_PARAM;
    }
    if (!body && body_len != 0)
    {
        return LANTERN_HTTP_ERR_INVALID_PARAM;
    }

    const char *text = status_text ? status_text : "OK";
    const char *type = content_type ? content_type : "application/json";
    size_t content_length = body ? body_len : 0u;

    char header[HTTP_RESPONSE_HEADER_BUFFER_LEN];
    int header_len = snprintf(
        header,
        sizeof(header),
        "HTTP/1.1 %d %s\r\n"
        "Content-Type: %s\r\n"
        "Content-Length: %zu\r\n"
        "Connection: close\r\n"
        "\r\n",
        status_code,
        text,
        type,
        content_length);
    if (header_len <= 0 || (size_t)header_len >= sizeof(header))
    {
        return LANTERN_HTTP_ERR_HEADER_TOO_LARGE;
    }

    int result = lantern_http_send_all(fd, header, (size_t)header_len);
    if (result != 0)
    {
        return result;
    }
    if (content_length == 0)
    {
        return 0;
    }

    result = lantern_http_send_all(fd, body, content_length);
    if (result != 0)
    {
        return result;
    }

    return 0;
}
