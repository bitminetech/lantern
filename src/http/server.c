/**
 * @file server.c
 * @brief Lean API HTTP server.
 *
 * Exposes a minimal JSON HTTP API:
 * - GET /lean/v1/head
 * - GET /lean/v1/validators
 * - POST /lean/v1/validators/{index}/(activate|deactivate)
 *
 * @spec RFC 9110/9112 (HTTP) and POSIX sockets/pthreads.
 */

#include "lantern/http/server.h"

#include <arpa/inet.h>
#include <errno.h>
#include <inttypes.h>
#include <netinet/in.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>

#include "lantern/http/common.h"
#include "lantern/support/log.h"
#include "lantern/support/strings.h"

static const size_t LANTERN_HTTP_READ_BUFFER_SIZE = 4096;
static const size_t LANTERN_HTTP_BODY_INITIAL_CAP = 512;
static const int LANTERN_HTTP_LISTEN_BACKLOG = 16;
static const size_t LANTERN_HTTP_ROOT_HEX_CAP = (2u * LANTERN_ROOT_SIZE) + 3u;

enum
{
    LANTERN_HTTP_METHOD_CAP = 8,
    LANTERN_HTTP_PATH_CAP = 256,
};

/**
 * HTTP server module-specific error codes.
 */
typedef enum
{
    LANTERN_HTTP_SERVER_OK = 0,
    LANTERN_HTTP_SERVER_ERR_INVALID_PARAM = -1,
    LANTERN_HTTP_SERVER_ERR_OUT_OF_MEMORY = -2,
    LANTERN_HTTP_SERVER_ERR_OVERFLOW = -3,
    LANTERN_HTTP_SERVER_ERR_IO = -4,
    LANTERN_HTTP_SERVER_ERR_FORMATTING = -5,
    LANTERN_HTTP_SERVER_ERR_MALFORMED_REQUEST = -6,
} lantern_http_server_error_t;

struct lantern_http_body_buffer
{
    char *data;  /**< Heap buffer (NUL-terminated). */
    size_t len;  /**< Bytes written (excluding terminator). */
    size_t cap;  /**< Allocated capacity in bytes. */
};

/**
 * Initialize a dynamic HTTP body buffer.
 *
 * @param buf         Buffer to initialize (modified in place).
 * @param initial_cap Initial allocation size in bytes (0 uses default).
 *
 * @return 0 on success.
 * @return LANTERN_HTTP_SERVER_ERR_INVALID_PARAM on invalid parameters.
 * @return LANTERN_HTTP_SERVER_ERR_OUT_OF_MEMORY on allocation failure.
 *
 * @note Thread safety: This function is thread-safe.
 */
static int http_buffer_init(struct lantern_http_body_buffer *buf, size_t initial_cap)
{
    if (!buf)
    {
        return LANTERN_HTTP_SERVER_ERR_INVALID_PARAM;
    }

    size_t capacity = initial_cap != 0 ? initial_cap : LANTERN_HTTP_BODY_INITIAL_CAP;
    buf->data = malloc(capacity);
    if (!buf->data)
    {
        return LANTERN_HTTP_SERVER_ERR_OUT_OF_MEMORY;
    }

    buf->len = 0;
    buf->cap = capacity;
    buf->data[0] = '\0';
    return 0;
}


/**
 * @brief Free resources owned by an HTTP body buffer.
 *
 * @param buf Buffer to free (may be NULL).
 *
 * @note Thread safety: This function is thread-safe.
 */
static void http_buffer_free(struct lantern_http_body_buffer *buf)
{
    if (!buf)
    {
        return;
    }

    free(buf->data);
    buf->data = NULL;
    buf->len = 0;
    buf->cap = 0;
}


/**
 * Ensure an HTTP body buffer has space for an additional number of bytes.
 *
 * @param buf   Buffer to grow (modified in place).
 * @param extra Additional bytes required (excluding terminator).
 *
 * @return 0 on success.
 * @return LANTERN_HTTP_SERVER_ERR_INVALID_PARAM on invalid parameters.
 * @return LANTERN_HTTP_SERVER_ERR_OUT_OF_MEMORY on allocation failure.
 * @return LANTERN_HTTP_SERVER_ERR_OVERFLOW on size overflow.
 *
 * @note Thread safety: This function is thread-safe.
 */
static int http_buffer_reserve(struct lantern_http_body_buffer *buf, size_t extra)
{
    if (!buf)
    {
        return LANTERN_HTTP_SERVER_ERR_INVALID_PARAM;
    }
    if (extra == 0)
    {
        return 0;
    }

    if (buf->len > SIZE_MAX - extra - 1)
    {
        return LANTERN_HTTP_SERVER_ERR_OVERFLOW;
    }

    size_t required = buf->len + extra + 1;
    if (required <= buf->cap)
    {
        return 0;
    }

    size_t new_cap = buf->cap != 0 ? buf->cap : LANTERN_HTTP_BODY_INITIAL_CAP;
    while (new_cap < required)
    {
        if (new_cap > SIZE_MAX / 2)
        {
            return LANTERN_HTTP_SERVER_ERR_OVERFLOW;
        }
        new_cap *= 2;
    }

    char *data = realloc(buf->data, new_cap);
    if (!data)
    {
        return LANTERN_HTTP_SERVER_ERR_OUT_OF_MEMORY;
    }

    buf->data = data;
    buf->cap = new_cap;
    return 0;
}


/**
 * Append raw bytes to an HTTP body buffer.
 *
 * @param buf   Buffer to append to (modified in place).
 * @param data  Bytes to append.
 * @param len   Number of bytes to append.
 *
 * @return 0 on success.
 * @return LANTERN_HTTP_SERVER_ERR_INVALID_PARAM on invalid parameters.
 * @return LANTERN_HTTP_SERVER_ERR_OUT_OF_MEMORY on allocation failure.
 * @return LANTERN_HTTP_SERVER_ERR_OVERFLOW on size overflow.
 *
 * @note Thread safety: This function is thread-safe.
 */
static int http_buffer_append(struct lantern_http_body_buffer *buf, const char *data, size_t len)
{
    if (!buf)
    {
        return LANTERN_HTTP_SERVER_ERR_INVALID_PARAM;
    }
    if (len == 0)
    {
        return 0;
    }
    if (!data)
    {
        return LANTERN_HTTP_SERVER_ERR_INVALID_PARAM;
    }

    int result = http_buffer_reserve(buf, len);
    if (result != 0)
    {
        return result;
    }

    memcpy(buf->data + buf->len, data, len);
    buf->len += len;
    buf->data[buf->len] = '\0';
    return 0;
}


/**
 * Append a NUL-terminated string to an HTTP body buffer.
 *
 * @param buf Buffer to append to (modified in place).
 * @param str String to append (not modified).
 *
 * @return 0 on success.
 * @return LANTERN_HTTP_SERVER_ERR_INVALID_PARAM on invalid parameters.
 * @return LANTERN_HTTP_SERVER_ERR_OUT_OF_MEMORY on allocation failure.
 * @return LANTERN_HTTP_SERVER_ERR_OVERFLOW on size overflow.
 *
 * @note Thread safety: This function is thread-safe.
 */
static int http_buffer_append_cstr(struct lantern_http_body_buffer *buf, const char *str)
{
    if (!buf || !str)
    {
        return LANTERN_HTTP_SERVER_ERR_INVALID_PARAM;
    }

    return http_buffer_append(buf, str, strlen(str));
}


/**
 * Append formatted text to an HTTP body buffer.
 *
 * @param buf Buffer to append to (modified in place).
 * @param fmt printf-style format string.
 *
 * @return 0 on success.
 * @return LANTERN_HTTP_SERVER_ERR_INVALID_PARAM on invalid parameters.
 * @return LANTERN_HTTP_SERVER_ERR_OUT_OF_MEMORY on allocation failure.
 * @return LANTERN_HTTP_SERVER_ERR_OVERFLOW on size overflow.
 * @return LANTERN_HTTP_SERVER_ERR_FORMATTING on formatting failure.
 *
 * @note Thread safety: This function is thread-safe.
 */
static int http_buffer_appendf(struct lantern_http_body_buffer *buf, const char *fmt, ...)
{
    if (!buf || !fmt)
    {
        return LANTERN_HTTP_SERVER_ERR_INVALID_PARAM;
    }

    va_list args;
    va_start(args, fmt);
    va_list args_copy;
    va_copy(args_copy, args);

    int required = vsnprintf(NULL, 0, fmt, args);
    va_end(args);
    if (required < 0)
    {
        va_end(args_copy);
        return LANTERN_HTTP_SERVER_ERR_FORMATTING;
    }

    size_t extra = (size_t)required;
    int result = http_buffer_reserve(buf, extra);
    if (result != 0)
    {
        va_end(args_copy);
        return result;
    }

    int written = vsnprintf(buf->data + buf->len, buf->cap - buf->len, fmt, args_copy);
    va_end(args_copy);
    if (written < 0 || (size_t)written != extra)
    {
        return LANTERN_HTTP_SERVER_ERR_FORMATTING;
    }

    buf->len += extra;
    return 0;
}


/**
 * Append a JSON-escaped string value to a buffer (no surrounding quotes).
 *
 * @param buf Buffer to append to (modified in place).
 * @param str String to JSON-escape (may be NULL, treated as empty).
 *
 * @return 0 on success.
 * @return LANTERN_HTTP_SERVER_ERR_INVALID_PARAM on invalid parameters.
 * @return LANTERN_HTTP_SERVER_ERR_OUT_OF_MEMORY on allocation failure.
 * @return LANTERN_HTTP_SERVER_ERR_OVERFLOW on size overflow.
 * @return LANTERN_HTTP_SERVER_ERR_FORMATTING on formatting failure.
 *
 * @note Thread safety: This function is thread-safe.
 */
static int http_buffer_append_json_escaped(struct lantern_http_body_buffer *buf, const char *str)
{
    if (!buf)
    {
        return LANTERN_HTTP_SERVER_ERR_INVALID_PARAM;
    }

    const char *text = str ? str : "";
    for (; *text != '\0'; ++text)
    {
        unsigned char c = (unsigned char)(*text);
        switch (c)
        {
            case '"':
            {
                int rc = http_buffer_append(buf, "\\\"", 2);
                if (rc != 0)
                {
                    return rc;
                }
                break;
            }
            case '\\':
            {
                int rc = http_buffer_append(buf, "\\\\", 2);
                if (rc != 0)
                {
                    return rc;
                }
                break;
            }
            case '\b':
            {
                int rc = http_buffer_append(buf, "\\b", 2);
                if (rc != 0)
                {
                    return rc;
                }
                break;
            }
            case '\f':
            {
                int rc = http_buffer_append(buf, "\\f", 2);
                if (rc != 0)
                {
                    return rc;
                }
                break;
            }
            case '\n':
            {
                int rc = http_buffer_append(buf, "\\n", 2);
                if (rc != 0)
                {
                    return rc;
                }
                break;
            }
            case '\r':
            {
                int rc = http_buffer_append(buf, "\\r", 2);
                if (rc != 0)
                {
                    return rc;
                }
                break;
            }
            case '\t':
            {
                int rc = http_buffer_append(buf, "\\t", 2);
                if (rc != 0)
                {
                    return rc;
                }
                break;
            }
            default:
            {
                if (c < 0x20)
                {
                    char escaped[7];
                    int written = snprintf(escaped, sizeof(escaped), "\\u%04x", (unsigned)c);
                    if (written < 0 || (size_t)written >= sizeof(escaped))
                    {
                        return LANTERN_HTTP_SERVER_ERR_FORMATTING;
                    }
                    int rc = http_buffer_append(buf, escaped, (size_t)written);
                    if (rc != 0)
                    {
                        return rc;
                    }
                    break;
                }
                int rc = http_buffer_append(buf, (const char *)&c, 1);
                if (rc != 0)
                {
                    return rc;
                }
                break;
            }
        }
    }

    return 0;
}


/**
 * Convert a root to a 0x-prefixed hex string.
 *
 * @param root    Root to encode.
 * @param out     Output buffer (NUL-terminated on return when out_len > 0).
 * @param out_len Output buffer length.
 *
 * @return 0 on success.
 * @return LANTERN_HTTP_SERVER_ERR_INVALID_PARAM on invalid parameters.
 * @return LANTERN_HTTP_SERVER_ERR_FORMATTING on encoding failure.
 *
 * @note Thread safety: This function is thread-safe.
 */
static int root_to_hex(const LanternRoot *root, char *out, size_t out_len)
{
    if (!out || out_len == 0)
    {
        return LANTERN_HTTP_SERVER_ERR_INVALID_PARAM;
    }

    out[0] = '\0';
    if (!root || out_len < LANTERN_HTTP_ROOT_HEX_CAP)
    {
        return LANTERN_HTTP_SERVER_ERR_INVALID_PARAM;
    }

    if (lantern_bytes_to_hex(root->bytes, LANTERN_ROOT_SIZE, out, out_len, 1) != 0)
    {
        out[0] = '\0';
        return LANTERN_HTTP_SERVER_ERR_FORMATTING;
    }

    return 0;
}


/**
 * Send an HTTP JSON response.
 *
 * @param client_fd   Client socket file descriptor.
 * @param status_code HTTP status code.
 * @param status_text HTTP status text.
 * @param json_body   JSON body (may be NULL when json_len is 0).
 * @param json_len    JSON body length in bytes.
 *
 * @return 0 on success.
 * @return LANTERN_HTTP_SERVER_ERR_INVALID_PARAM on invalid parameters.
 * @return LANTERN_HTTP_SERVER_ERR_FORMATTING on header formatting failure.
 * @return LANTERN_HTTP_SERVER_ERR_IO on send failure.
 *
 * @note Thread safety: Caller must ensure exclusive access to client_fd.
 */
static int send_json_response(
    int client_fd,
    int status_code,
    const char *status_text,
    const char *json_body,
    size_t json_len)
{
    int rc = lantern_http_send_response(
        client_fd,
        status_code,
        status_text,
        "application/json",
        json_body,
        json_len);
    if (rc == 0)
    {
        return 0;
    }

    if (rc == -1)
    {
        return LANTERN_HTTP_SERVER_ERR_INVALID_PARAM;
    }
    if (rc == -3)
    {
        return LANTERN_HTTP_SERVER_ERR_FORMATTING;
    }
    return LANTERN_HTTP_SERVER_ERR_IO;
}


/**
 * Send a simple static JSON error response.
 *
 * @param client_fd   Client socket file descriptor.
 * @param status_code HTTP status code.
 * @param status_text HTTP status text.
 * @param json_body   JSON body (may be NULL).
 *
 * @return 0 on success.
 * @return LANTERN_HTTP_SERVER_ERR_INVALID_PARAM on invalid parameters.
 * @return LANTERN_HTTP_SERVER_ERR_FORMATTING on header formatting failure.
 * @return LANTERN_HTTP_SERVER_ERR_IO on send failure.
 *
 * @note Thread safety: Caller must ensure exclusive access to client_fd.
 */
static int send_json_error(
    int client_fd,
    int status_code,
    const char *status_text,
    const char *json_body)
{
    if (!json_body)
    {
        return send_json_response(client_fd, status_code, status_text, NULL, 0);
    }

    return send_json_response(client_fd, status_code, status_text, json_body, strlen(json_body));
}


/**
 * Send a JSON error response and set the status code output.
 *
 * @param client_fd        Client socket file descriptor.
 * @param status_code      HTTP status code.
 * @param status_text      HTTP status text.
 * @param json_body        JSON body.
 * @param out_status_code  Output status code (modified in place).
 *
 * @return 0 on success.
 * @return LANTERN_HTTP_SERVER_ERR_INVALID_PARAM on invalid parameters.
 * @return LANTERN_HTTP_SERVER_ERR_FORMATTING on header formatting failure.
 * @return LANTERN_HTTP_SERVER_ERR_IO on send failure.
 *
 * @note Thread safety: Caller must ensure exclusive access to client_fd.
 */
static int send_json_error_status(
    int client_fd,
    int status_code,
    const char *status_text,
    const char *json_body,
    int *out_status_code)
{
    if (!out_status_code)
    {
        return LANTERN_HTTP_SERVER_ERR_INVALID_PARAM;
    }

    *out_status_code = status_code;
    return send_json_error(client_fd, status_code, status_text, json_body);
}


/**
 * Handle the `GET /lean/v1/head` endpoint.
 *
 * @param server          HTTP server instance.
 * @param client_fd       Client socket file descriptor.
 * @param out_status_code Output HTTP status code (modified in place).
 *
 * @return 0 on success.
 * @return LANTERN_HTTP_SERVER_ERR_INVALID_PARAM on invalid parameters.
 * @return LANTERN_HTTP_SERVER_ERR_IO on send failure.
 *
 * @note Thread safety: This function is thread-safe if callbacks are thread-safe.
 */
static int handle_get_head(
    struct lantern_http_server *server,
    int client_fd,
    int *out_status_code)
{
    if (!server || client_fd < 0 || !out_status_code)
    {
        return LANTERN_HTTP_SERVER_ERR_INVALID_PARAM;
    }

    if (!server->callbacks.snapshot_head)
    {
        return send_json_error_status(
            client_fd,
            501,
            "Not Implemented",
            "{\"error\":\"head query unsupported\"}",
            out_status_code);
    }

    struct lantern_http_head_snapshot snapshot;
    if (server->callbacks.snapshot_head(server->callbacks.context, &snapshot) != 0)
    {
        return send_json_error_status(
            client_fd,
            503,
            "Service Unavailable",
            "{\"error\":\"head snapshot unavailable\"}",
            out_status_code);
    }

    char head_hex[LANTERN_HTTP_ROOT_HEX_CAP];
    char justified_hex[LANTERN_HTTP_ROOT_HEX_CAP];
    char finalized_hex[LANTERN_HTTP_ROOT_HEX_CAP];
    if (root_to_hex(&snapshot.head_root, head_hex, sizeof(head_hex)) != 0
        || root_to_hex(&snapshot.justified.root, justified_hex, sizeof(justified_hex)) != 0
        || root_to_hex(&snapshot.finalized.root, finalized_hex, sizeof(finalized_hex)) != 0)
    {
        return send_json_error_status(
            client_fd,
            500,
            "Internal Server Error",
            "{\"error\":\"root encoding failed\"}",
            out_status_code);
    }

    char body[512];
    int written = snprintf(
        body,
        sizeof(body),
        "{"
        "\"slot\":%" PRIu64 ","
        "\"head_root\":\"%s\","
        "\"justified\":{\"slot\":%" PRIu64 ",\"root\":\"%s\"},"
        "\"finalized\":{\"slot\":%" PRIu64 ",\"root\":\"%s\"}"
        "}",
        snapshot.slot,
        head_hex,
        snapshot.justified.slot,
        justified_hex,
        snapshot.finalized.slot,
        finalized_hex);
    if (written < 0 || (size_t)written >= sizeof(body))
    {
        return send_json_error_status(
            client_fd,
            500,
            "Internal Server Error",
            "{\"error\":\"head response too large\"}",
            out_status_code);
    }

    int rc = send_json_response(client_fd, 200, "OK", body, (size_t)written);
    if (rc != 0)
    {
        return rc;
    }

    *out_status_code = 200;
    return 0;
}


/**
 * Handle the `GET /lean/v1/validators` endpoint.
 *
 * @param server          HTTP server instance.
 * @param client_fd       Client socket file descriptor.
 * @param out_status_code Output HTTP status code (modified in place).
 *
 * @return 0 on success.
 * @return LANTERN_HTTP_SERVER_ERR_INVALID_PARAM on invalid parameters.
 * @return LANTERN_HTTP_SERVER_ERR_IO on send failure.
 *
 * @note Thread safety: This function is thread-safe if callbacks are thread-safe.
 */
static int handle_get_validators(
    struct lantern_http_server *server,
    int client_fd,
    int *out_status_code)
{
    if (!server || client_fd < 0 || !out_status_code)
    {
        return LANTERN_HTTP_SERVER_ERR_INVALID_PARAM;
    }

    if (!server->callbacks.validator_count || !server->callbacks.validator_info)
    {
        return send_json_error_status(
            client_fd,
            501,
            "Not Implemented",
            "{\"error\":\"validator listing unsupported\"}",
            out_status_code);
    }

    size_t count = server->callbacks.validator_count(server->callbacks.context);

    struct lantern_http_body_buffer body;
    bool body_initialized = false;
    int result = http_buffer_init(&body, LANTERN_HTTP_BODY_INITIAL_CAP);
    if (result != 0)
    {
        goto internal_error;
    }
    body_initialized = true;

    result = http_buffer_append_cstr(&body, "{\"validators\":[");
    if (result != 0)
    {
        goto internal_error;
    }

    for (size_t i = 0; i < count; ++i)
    {
        struct lantern_http_validator_info info;
        if (server->callbacks.validator_info(server->callbacks.context, i, &info) != 0)
        {
            result = send_json_error_status(
                client_fd,
                503,
                "Service Unavailable",
                "{\"error\":\"validator snapshot unavailable\"}",
                out_status_code);
            goto cleanup;
        }

        if (i > 0)
        {
            result = http_buffer_append(&body, ",", 1);
            if (result != 0)
            {
                goto internal_error;
            }
        }

        result = http_buffer_appendf(
            &body,
            "{\"index\":%" PRIu64 ",\"enabled\":%s,\"label\":\"",
            info.global_index,
            info.enabled ? "true" : "false");
        if (result != 0)
        {
            goto internal_error;
        }

        result = http_buffer_append_json_escaped(&body, info.label);
        if (result != 0)
        {
            goto internal_error;
        }

        result = http_buffer_append_cstr(&body, "\"}");
        if (result != 0)
        {
            goto internal_error;
        }
    }

    result = http_buffer_append_cstr(&body, "]}");
    if (result != 0)
    {
        goto internal_error;
    }

    result = send_json_response(client_fd, 200, "OK", body.data, body.len);
    if (result != 0)
    {
        goto cleanup;
    }

    *out_status_code = 200;
    result = 0;
    goto cleanup;

internal_error:
    {
        const char *error_body = "{\"error\":\"allocator failure\"}";
        if (result == LANTERN_HTTP_SERVER_ERR_FORMATTING)
        {
            error_body = "{\"error\":\"formatting failure\"}";
        }
        result = send_json_error_status(
            client_fd,
            500,
            "Internal Server Error",
            error_body,
            out_status_code);
    }

cleanup:
    if (body_initialized)
    {
        http_buffer_free(&body);
    }

    return result;
}


/**
 * Handle validator activation and deactivation requests.
 *
 * Supports `POST /lean/v1/validators/{index}/activate` and
 * `POST /lean/v1/validators/{index}/deactivate`.
 *
 * @param server          HTTP server instance.
 * @param client_fd       Client socket file descriptor.
 * @param path            Request path.
 * @param out_status_code Output HTTP status code (modified in place).
 *
 * @return 0 on success.
 * @return LANTERN_HTTP_SERVER_ERR_INVALID_PARAM on invalid parameters.
 * @return LANTERN_HTTP_SERVER_ERR_IO on send failure.
 *
 * @note Thread safety: This function is thread-safe if callbacks are thread-safe.
 */
static int handle_post_validator_action(
    struct lantern_http_server *server,
    int client_fd,
    const char *path,
    int *out_status_code)
{
    if (!server || client_fd < 0 || !path || !out_status_code)
    {
        return LANTERN_HTTP_SERVER_ERR_INVALID_PARAM;
    }

    if (!server->callbacks.set_validator_status)
    {
        return send_json_error_status(
            client_fd,
            501,
            "Not Implemented",
            "{\"error\":\"validator control unsupported\"}",
            out_status_code);
    }

    static const char prefix[] = "/lean/v1/validators/";
    size_t prefix_len = strlen(prefix);
    if (strncmp(path, prefix, prefix_len) != 0)
    {
        return send_json_error_status(
            client_fd,
            404,
            "Not Found",
            "{\"error\":\"unknown validator path\"}",
            out_status_code);
    }

    const char *rest = path + prefix_len;
    if (!*rest)
    {
        return send_json_error_status(
            client_fd,
            400,
            "Bad Request",
            "{\"error\":\"missing validator index\"}",
            out_status_code);
    }

    errno = 0;
    char *endptr = NULL;
    uint64_t index = strtoull(rest, &endptr, 10);
    if (errno != 0 || rest == endptr)
    {
        return send_json_error_status(
            client_fd,
            400,
            "Bad Request",
            "{\"error\":\"invalid validator index\"}",
            out_status_code);
    }
    if (!endptr || *endptr != '/')
    {
        return send_json_error_status(
            client_fd,
            400,
            "Bad Request",
            "{\"error\":\"missing validator action\"}",
            out_status_code);
    }

    const char *action = endptr + 1;
    bool should_enable = false;
    if (strcmp(action, "activate") == 0)
    {
        should_enable = true;
    }
    else if (strcmp(action, "deactivate") == 0)
    {
        should_enable = false;
    }
    else
    {
        return send_json_error_status(
            client_fd,
            404,
            "Not Found",
            "{\"error\":\"unknown validator action\"}",
            out_status_code);
    }

    if (server->callbacks.set_validator_status(
            server->callbacks.context,
            index,
            should_enable)
        != 0)
    {
        return send_json_error_status(
            client_fd,
            404,
            "Not Found",
            "{\"error\":\"validator not found\"}",
            out_status_code);
    }

    int rc = send_json_response(client_fd, 204, "No Content", NULL, 0);
    if (rc != 0)
    {
        return rc;
    }

    *out_status_code = 204;
    return 0;
}


/**
 * Dispatch an HTTP request to the appropriate handler.
 *
 * @param server          HTTP server instance.
 * @param client_fd       Client socket file descriptor.
 * @param method          Request method.
 * @param path            Request path.
 * @param out_status_code Output HTTP status code (modified in place).
 *
 * @return 0 on success.
 * @return LANTERN_HTTP_SERVER_ERR_INVALID_PARAM on invalid parameters.
 * @return LANTERN_HTTP_SERVER_ERR_IO on send failure.
 *
 * @note Thread safety: This function is thread-safe if callbacks are thread-safe.
 */
static int dispatch_request(
    struct lantern_http_server *server,
    int client_fd,
    const char *method,
    const char *path,
    int *out_status_code)
{
    if (!server || client_fd < 0 || !method || !path || !out_status_code)
    {
        return LANTERN_HTTP_SERVER_ERR_INVALID_PARAM;
    }

    if (strcmp(method, "GET") == 0)
    {
        if (strcmp(path, "/lean/v1/head") == 0)
        {
            return handle_get_head(server, client_fd, out_status_code);
        }
        if (strcmp(path, "/lean/v1/validators") == 0)
        {
            return handle_get_validators(server, client_fd, out_status_code);
        }
    }
    else if (strcmp(method, "POST") == 0)
    {
        return handle_post_validator_action(server, client_fd, path, out_status_code);
    }

    return send_json_error_status(
        client_fd,
        404,
        "Not Found",
        "{\"error\":\"unknown endpoint\"}",
        out_status_code);
}


/**
 * Convert a peer address to a printable string.
 *
 * @param peer_addr Peer address (may be NULL).
 * @param out       Output buffer (NUL-terminated on return).
 * @param out_len   Output buffer length.
 *
 * @note Thread safety: This function is thread-safe.
 */
static void peer_to_text(const struct sockaddr_in *peer_addr, char *out, size_t out_len)
{
    if (!out || out_len == 0)
    {
        return;
    }

    const char *fallback = "unknown";
    if (!peer_addr)
    {
        strncpy(out, fallback, out_len - 1);
        out[out_len - 1] = '\0';
        return;
    }

    if (!inet_ntop(AF_INET, &peer_addr->sin_addr, out, out_len))
    {
        strncpy(out, fallback, out_len - 1);
        out[out_len - 1] = '\0';
    }
}


/**
 * Parse a minimal HTTP request line (method and path).
 *
 * @param request    Request bytes (NUL-terminated).
 * @param method     Output method buffer (NUL-terminated on success).
 * @param method_len Method buffer length.
 * @param path       Output path buffer (NUL-terminated on success).
 * @param path_len   Path buffer length.
 *
 * @return 0 on success.
 * @return LANTERN_HTTP_SERVER_ERR_INVALID_PARAM on invalid parameters.
 * @return LANTERN_HTTP_SERVER_ERR_MALFORMED_REQUEST on parse failure.
 *
 * @note Thread safety: This function is thread-safe.
 */
static int parse_request_line(
    const char *request,
    char *method,
    size_t method_len,
    char *path,
    size_t path_len)
{
    if (!request || !method || method_len == 0 || !path || path_len == 0)
    {
        return LANTERN_HTTP_SERVER_ERR_INVALID_PARAM;
    }

    const char *space = strchr(request, ' ');
    if (!space)
    {
        return LANTERN_HTTP_SERVER_ERR_MALFORMED_REQUEST;
    }

    size_t method_written = (size_t)(space - request);
    if (method_written == 0 || method_written >= method_len)
    {
        return LANTERN_HTTP_SERVER_ERR_MALFORMED_REQUEST;
    }

    memcpy(method, request, method_written);
    method[method_written] = '\0';

    const char *cursor = space;
    while (*cursor == ' ')
    {
        ++cursor;
    }
    if (*cursor == '\0')
    {
        return LANTERN_HTTP_SERVER_ERR_MALFORMED_REQUEST;
    }

    const char *path_start = cursor;
    while (*cursor != '\0'
        && *cursor != ' '
        && *cursor != '\r'
        && *cursor != '\n'
        && *cursor != '\t')
    {
        ++cursor;
    }

    size_t path_written = (size_t)(cursor - path_start);
    if (path_written == 0 || path_written >= path_len)
    {
        return LANTERN_HTTP_SERVER_ERR_MALFORMED_REQUEST;
    }

    memcpy(path, path_start, path_written);
    path[path_written] = '\0';
    return 0;
}


/**
 * Handle a single client connection.
 *
 * @param server    HTTP server instance.
 * @param client_fd Client socket file descriptor.
 * @param peer_addr Peer address (may be NULL).
 *
 * @note Thread safety: This function is thread-safe if callbacks are thread-safe.
 */
static void handle_client_connection(
    struct lantern_http_server *server,
    int client_fd,
    const struct sockaddr_in *peer_addr)
{
    if (!server || client_fd < 0)
    {
        return;
    }

    char peer_text[INET_ADDRSTRLEN];
    peer_to_text(peer_addr, peer_text, sizeof(peer_text));

    char buffer[LANTERN_HTTP_READ_BUFFER_SIZE];
    ssize_t received = -1;
    do
    {
        received = recv(client_fd, buffer, sizeof(buffer) - 1, 0);
    } while (received < 0 && errno == EINTR);

    if (received <= 0)
    {
        return;
    }
    buffer[(size_t)received] = '\0';

    char method[LANTERN_HTTP_METHOD_CAP];
    char path[LANTERN_HTTP_PATH_CAP];
    int http_status = 500;

    int result = parse_request_line(buffer, method, sizeof(method), path, sizeof(path));
    if (result != 0)
    {
        int rc = send_json_error(
            client_fd,
            400,
            "Bad Request",
            "{\"error\":\"malformed request\"}");
        if (rc == 0)
        {
            lantern_log_info(
                "http",
                &(const struct lantern_log_metadata){.peer = peer_text},
                "malformed request -> 400");
        }
        else
        {
            lantern_log_error(
                "http",
                &(const struct lantern_log_metadata){.peer = peer_text},
                "failed to send 400 response rc=%d",
                rc);
        }
        return;
    }

    result = dispatch_request(server, client_fd, method, path, &http_status);
    if (result != 0)
    {
        lantern_log_error(
            "http",
            &(const struct lantern_log_metadata){.peer = peer_text},
            "%s %s failed rc=%d",
            method,
            path,
            result);
        return;
    }

    lantern_log_info(
        "http",
        &(const struct lantern_log_metadata){.peer = peer_text},
        "%s %s -> %d",
        method,
        path,
        http_status);
}


/**
 * Thread entry point for the HTTP server accept loop.
 *
 * @param arg Pointer to struct lantern_http_server.
 * @return NULL.
 *
 * @note Thread safety: This function is not thread-safe; it is intended to run
 *       as a single server thread created by lantern_http_server_start().
 */
static void *lantern_http_server_thread(void *arg)
{
    struct lantern_http_server *server = arg;
    if (!server)
    {
        return NULL;
    }

    int listen_fd = server->listen_fd;
    for (;;)
    {
        struct sockaddr_in peer;
        socklen_t peer_len = sizeof(peer);
        int client_fd = accept(listen_fd, (struct sockaddr *)&peer, &peer_len);
        if (client_fd < 0)
        {
            if (errno == EINTR)
            {
                continue;
            }
            if (errno == EBADF || errno == EINVAL)
            {
                break;
            }
            lantern_log_error("http", NULL, "accept failed errno=%d", errno);
            continue;
        }

        handle_client_connection(server, client_fd, &peer);
        close(client_fd);
    }

    return NULL;
}


/**
 * Initialize an HTTP server structure.
 *
 * @param server Server instance to initialize (modified in place).
 *
 * @note Thread safety: Caller must not call concurrently with start/stop.
 */
void lantern_http_server_init(struct lantern_http_server *server)
{
    if (!server)
    {
        return;
    }

    memset(server, 0, sizeof(*server));
    server->listen_fd = -1;
    server->running = 0;
    server->thread_started = 0;
    server->port = 0;
}


/**
 * Reset an HTTP server structure, stopping it if running.
 *
 * @param server Server instance to reset (modified in place).
 *
 * @note Thread safety: Caller must not call concurrently with start/stop.
 */
void lantern_http_server_reset(struct lantern_http_server *server)
{
    if (!server)
    {
        return;
    }

    lantern_http_server_stop(server);
    lantern_http_server_init(server);
}


/**
 * Start the HTTP server.
 *
 * Creates a listening socket and starts a background thread to accept incoming
 * connections and serve the Lean API endpoints.
 *
 * @param server Server instance to start (modified in place).
 * @param config Server configuration (callbacks must be set).
 *
 * @spec POSIX sockets and pthreads.
 *
 * @return 0 on success.
 * @return LANTERN_HTTP_SERVER_ERR_INVALID_PARAM on invalid parameters.
 * @return LANTERN_HTTP_SERVER_ERR_IO on socket/bind/listen/thread creation failure.
 *
 * @note Thread safety: Caller must serialize start/stop operations.
 */
int lantern_http_server_start(
    struct lantern_http_server *server,
    const struct lantern_http_server_config *config)
{
    if (!server || !config)
    {
        return LANTERN_HTTP_SERVER_ERR_INVALID_PARAM;
    }
    if (!config->callbacks.snapshot_head
        || !config->callbacks.validator_count
        || !config->callbacks.validator_info
        || !config->callbacks.set_validator_status)
    {
        return LANTERN_HTTP_SERVER_ERR_INVALID_PARAM;
    }

    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0)
    {
        lantern_log_error("http", NULL, "socket creation failed errno=%d", errno);
        return LANTERN_HTTP_SERVER_ERR_IO;
    }

    int opt = 1;
    if (setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt)) != 0)
    {
        lantern_log_warn("http", NULL, "setsockopt(SO_REUSEADDR) failed errno=%d", errno);
    }

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_ANY);
    addr.sin_port = htons(config->port);

    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) != 0)
    {
        lantern_log_error("http", NULL, "bind failed errno=%d", errno);
        close(fd);
        return LANTERN_HTTP_SERVER_ERR_IO;
    }

    if (listen(fd, LANTERN_HTTP_LISTEN_BACKLOG) != 0)
    {
        lantern_log_error("http", NULL, "listen failed errno=%d", errno);
        close(fd);
        return LANTERN_HTTP_SERVER_ERR_IO;
    }

    server->listen_fd = fd;
    server->callbacks = config->callbacks;
    server->port = config->port;
    server->running = 1;
    server->thread_started = 0;

    int create_rc = pthread_create(&server->thread, NULL, lantern_http_server_thread, server);
    if (create_rc != 0)
    {
        lantern_log_error("http", NULL, "pthread_create failed rc=%d", create_rc);
        close(fd);
        server->listen_fd = -1;
        server->running = 0;
        return LANTERN_HTTP_SERVER_ERR_IO;
    }

    server->thread_started = 1;
    lantern_log_info("http", NULL, "http server listening port=%" PRIu16, server->port);
    return 0;
}


/**
 * Stop the HTTP server if running.
 *
 * @param server Server instance to stop (modified in place).
 *
 * @note Thread safety: Caller must serialize start/stop operations.
 */
void lantern_http_server_stop(struct lantern_http_server *server)
{
    if (!server)
    {
        return;
    }

    server->running = 0;

    int listen_fd = server->listen_fd;
    server->listen_fd = -1;
    if (listen_fd >= 0)
    {
        (void)shutdown(listen_fd, SHUT_RDWR);
        close(listen_fd);
    }

    if (server->thread_started)
    {
        pthread_join(server->thread, NULL);
        server->thread_started = 0;
    }
}
