/**
 * @file server.c
 * @brief Lean API HTTP server for checkpoint sync and health/metrics endpoints.
 *
 * Exposes endpoints:
 * - GET /lean/v0/states/finalized  (SSZ state snapshot)
 * - GET /lean/v0/blocks/finalized  (SSZ signed block snapshot)
 * - GET /lean/v0/checkpoints/justified  (JSON justified checkpoint)
 * - GET /lean/v0/fork_choice       (JSON fork choice tree snapshot)
 * - GET /lean/v0/health            (JSON health response)
 * - GET /metrics               (Prometheus metrics)
 *
 * @spec RFC 9110/9112 (HTTP/1.1) and leanSpec subspecs/api.
 */

#include "lantern/http/server.h"

#include <arpa/inet.h>
#include <errno.h>
#include <inttypes.h>
#include <netinet/in.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>

#include "lantern/http/common.h"
#include "lantern/http/metrics.h"
#include "lantern/support/log.h"
#include "lantern/support/strings.h"
#include "test_driver/driver.h"

static const size_t LANTERN_HTTP_READ_BUFFER_SIZE = 4096;
static const size_t LANTERN_HTTP_MAX_TEST_DRIVER_BODY_SIZE = 64u * 1024u * 1024u;
static const int LANTERN_HTTP_LISTEN_BACKLOG = 16;
static const char LANTERN_HTTP_PATH_HEALTH[] = "/lean/v0/health";
static const char LANTERN_HTTP_PATH_METRICS[] = "/metrics";
static const char LANTERN_HTTP_PATH_FINALIZED[] = "/lean/v0/states/finalized";
static const char LANTERN_HTTP_PATH_FINALIZED_BLOCK[] = "/lean/v0/blocks/finalized";
static const char LANTERN_HTTP_PATH_JUSTIFIED[] = "/lean/v0/checkpoints/justified";
static const char LANTERN_HTTP_PATH_FORK_CHOICE[] = "/lean/v0/fork_choice";
static const char LANTERN_HTTP_PATH_ADMIN_AGGREGATOR[] = "/lean/v0/admin/aggregator";
static const char LANTERN_HTTP_PATH_TEST_FC_INIT[] = "/lean/v0/test_driver/fork_choice/init";
static const char LANTERN_HTTP_PATH_TEST_FC_STEP[] = "/lean/v0/test_driver/fork_choice/step";
static const char LANTERN_HTTP_PATH_TEST_STATE_RUN[] =
    "/lean/v0/test_driver/state_transition/run";
static const char LANTERN_HTTP_PATH_TEST_VERIFY_RUN[] =
    "/lean/v0/test_driver/verify_signatures/run";
static const char LANTERN_HTTP_JSON_HEALTH[] = "{\"status\":\"healthy\",\"service\":\"lean-rpc-api\"}";
static const char LANTERN_HTTP_JSON_MALFORMED[] = "{\"error\":\"malformed request\"}";
static const char LANTERN_HTTP_JSON_UNKNOWN_ENDPOINT[] = "{\"error\":\"unknown endpoint\"}";
static const char LANTERN_HTTP_JSON_UNAVAILABLE[] = "{\"error\":\"service unavailable\"}";
static const char LANTERN_HTTP_JSON_STATE_MISSING[] = "{\"error\":\"finalized state not available\"}";
static const char LANTERN_HTTP_JSON_BLOCK_MISSING[] = "{\"error\":\"finalized block not available\"}";
static const char LANTERN_HTTP_JSON_INTERNAL[] = "{\"error\":\"internal error\"}";
static const char LANTERN_HTTP_JSON_BAD_REQUEST[] = "{\"error\":\"bad request\"}";
static const char LANTERN_HTTP_JSON_METHOD_NOT_ALLOWED[] = "{\"error\":\"method not allowed\"}";

enum
{
    LANTERN_HTTP_METHOD_CAP = 8,
    LANTERN_HTTP_PATH_CAP = 256,
};

struct lantern_http_json_buffer
{
    char *data;
    size_t len;
    size_t cap;
};

/**
 * HTTP server module-specific error codes.
 */
enum
{
    LANTERN_HTTP_SERVER_OK = 0,
    LANTERN_HTTP_SERVER_ERR_INVALID_PARAM = -1,
    LANTERN_HTTP_SERVER_ERR_IO = -2,
    LANTERN_HTTP_SERVER_ERR_FORMATTING = -3,
    LANTERN_HTTP_SERVER_ERR_MALFORMED_REQUEST = -4,
};


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
        (void)lantern_string_copy(out, out_len, fallback);
        return;
    }

    if (!inet_ntop(AF_INET, &peer_addr->sin_addr, out, out_len))
    {
        (void)lantern_string_copy(out, out_len, fallback);
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
 * Send an HTTP response and map common errors to server error codes.
 *
 * @param client_fd    Client socket file descriptor.
 * @param status_code  HTTP status code.
 * @param status_text  HTTP status text.
 * @param content_type Content-Type header value.
 * @param body         Response body (may be NULL when body_len is 0).
 * @param body_len     Response body length in bytes.
 *
 * @return 0 on success.
 * @return LANTERN_HTTP_SERVER_ERR_INVALID_PARAM on invalid parameters.
 * @return LANTERN_HTTP_SERVER_ERR_FORMATTING on header formatting failure.
 * @return LANTERN_HTTP_SERVER_ERR_IO on send failure.
 *
 * @note Thread safety: Caller must ensure exclusive access to client_fd.
 */
static int send_http_response(
    int client_fd,
    int status_code,
    const char *status_text,
    const char *content_type,
    const char *body,
    size_t body_len)
{
    int rc = lantern_http_send_response(
        client_fd,
        status_code,
        status_text,
        content_type,
        body,
        body_len);
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
 * Send a JSON error response.
 *
 * @param client_fd   Client socket file descriptor.
 * @param status_code HTTP status code.
 * @param status_text HTTP status text.
 * @param json_body   JSON body (may be NULL).
 *
 * @return 0 on success.
 * @return LANTERN_HTTP_SERVER_ERR_INVALID_PARAM on invalid parameters.
 * @return LANTERN_HTTP_SERVER_ERR_FORMATTING on formatting failure.
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
        return send_http_response(client_fd, status_code, status_text, "application/json", NULL, 0);
    }
    return send_http_response(
        client_fd,
        status_code,
        status_text,
        "application/json",
        json_body,
        strlen(json_body));
}

static void json_buffer_reset(struct lantern_http_json_buffer *buf)
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

static int json_buffer_reserve(struct lantern_http_json_buffer *buf, size_t additional)
{
    if (!buf)
    {
        return -1;
    }
    size_t required = buf->len + additional + 1u;
    if (required <= buf->cap)
    {
        return 0;
    }
    size_t new_cap = buf->cap == 0 ? 256u : buf->cap;
    while (new_cap < required)
    {
        if (new_cap > (SIZE_MAX / 2u))
        {
            return -1;
        }
        new_cap *= 2u;
    }
    char *new_data = realloc(buf->data, new_cap);
    if (!new_data)
    {
        return -1;
    }
    buf->data = new_data;
    buf->cap = new_cap;
    return 0;
}

static int json_buffer_appendf(struct lantern_http_json_buffer *buf, const char *fmt, ...)
{
    if (!buf || !fmt)
    {
        return -1;
    }

    va_list measure;
    va_start(measure, fmt);
    int needed = vsnprintf(NULL, 0, fmt, measure);
    va_end(measure);
    if (needed < 0)
    {
        return -1;
    }

    if (json_buffer_reserve(buf, (size_t)needed) != 0)
    {
        return -1;
    }

    va_list args;
    va_start(args, fmt);
    int written = vsnprintf(buf->data + buf->len, buf->cap - buf->len, fmt, args);
    va_end(args);
    if (written < 0 || written != needed)
    {
        return -1;
    }

    buf->len += (size_t)written;
    return 0;
}

static int format_fork_choice_response(
    const struct lantern_http_fork_choice_snapshot *snapshot,
    char **out_body,
    size_t *out_len)
{
    if (!snapshot || !out_body || !out_len)
    {
        return -1;
    }

    *out_body = NULL;
    *out_len = 0;

    char head_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    char justified_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    char finalized_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    char safe_target_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    if (lantern_bytes_to_hex(
            snapshot->head.bytes,
            LANTERN_ROOT_SIZE,
            head_hex,
            sizeof(head_hex),
            1)
        != 0
        || lantern_bytes_to_hex(
               snapshot->justified.root.bytes,
               LANTERN_ROOT_SIZE,
               justified_hex,
               sizeof(justified_hex),
               1)
               != 0
        || lantern_bytes_to_hex(
               snapshot->finalized.root.bytes,
               LANTERN_ROOT_SIZE,
               finalized_hex,
               sizeof(finalized_hex),
               1)
               != 0
        || lantern_bytes_to_hex(
               snapshot->safe_target.bytes,
               LANTERN_ROOT_SIZE,
               safe_target_hex,
               sizeof(safe_target_hex),
               1)
               != 0)
    {
        return -1;
    }

    struct lantern_http_json_buffer buf;
    memset(&buf, 0, sizeof(buf));
    if (json_buffer_appendf(&buf, "{\"nodes\":[") != 0)
    {
        json_buffer_reset(&buf);
        return -1;
    }

    for (size_t i = 0; i < snapshot->node_count; ++i)
    {
        const struct lantern_http_fork_choice_node *node = &snapshot->nodes[i];
        char root_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
        char parent_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
        if (lantern_bytes_to_hex(
                node->root.bytes,
                LANTERN_ROOT_SIZE,
                root_hex,
                sizeof(root_hex),
                1)
            != 0
            || lantern_bytes_to_hex(
                   node->parent_root.bytes,
                   LANTERN_ROOT_SIZE,
                   parent_hex,
                   sizeof(parent_hex),
                   1)
                   != 0)
        {
            json_buffer_reset(&buf);
            return -1;
        }

        if (json_buffer_appendf(
                &buf,
                "%s{\"root\":\"%s\",\"slot\":%" PRIu64
                ",\"parent_root\":\"%s\",\"proposer_index\":%" PRIu64
                ",\"weight\":%" PRIu64 "}",
                i == 0 ? "" : ",",
                root_hex,
                node->slot,
                parent_hex,
                node->proposer_index,
                node->weight)
            != 0)
        {
            json_buffer_reset(&buf);
            return -1;
        }
    }

    if (json_buffer_appendf(
            &buf,
            "],\"head\":\"%s\",\"justified\":{\"slot\":%" PRIu64 ",\"root\":\"%s\"},"
            "\"finalized\":{\"slot\":%" PRIu64 ",\"root\":\"%s\"},"
            "\"safe_target\":\"%s\",\"validator_count\":%" PRIu64 "}",
            head_hex,
            snapshot->justified.slot,
            justified_hex,
            snapshot->finalized.slot,
            finalized_hex,
            safe_target_hex,
            snapshot->validator_count)
        != 0)
    {
        json_buffer_reset(&buf);
        return -1;
    }

    *out_body = buf.data;
    *out_len = buf.len;
    return 0;
}


/**
 * Locate the request body inside a raw HTTP request buffer.
 *
 * @param buffer      Request buffer (may be NUL-terminated; NUL terminators are honored).
 * @param buffer_len  Bytes received into the buffer.
 * @param out_body    Output: pointer to the body start inside the buffer (or NULL if absent).
 * @param out_body_len Output: body length available in the buffer.
 * @return true if a body separator was found.
 */
static bool http_locate_body(
    const char *buffer,
    size_t buffer_len,
    const char **out_body,
    size_t *out_body_len)
{
    if (!buffer || buffer_len == 0 || !out_body || !out_body_len)
    {
        return false;
    }
    static const char SEPARATOR[] = "\r\n\r\n";
    const size_t sep_len = sizeof(SEPARATOR) - 1u;
    if (buffer_len < sep_len)
    {
        return false;
    }
    for (size_t i = 0; i + sep_len <= buffer_len; ++i)
    {
        if (memcmp(buffer + i, SEPARATOR, sep_len) == 0)
        {
            *out_body = buffer + i + sep_len;
            *out_body_len = buffer_len - i - sep_len;
            return true;
        }
    }
    return false;
}

static int http_parse_content_length(
    const char *buffer,
    size_t buffer_len,
    size_t *out_content_length)
{
    if (!buffer || !out_content_length)
    {
        return -1;
    }
    *out_content_length = 0;
    const char *headers_end = NULL;
    static const char SEPARATOR[] = "\r\n\r\n";
    const size_t sep_len = sizeof(SEPARATOR) - 1u;
    for (size_t i = 0; i + sep_len <= buffer_len; ++i)
    {
        if (memcmp(buffer + i, SEPARATOR, sep_len) == 0)
        {
            headers_end = buffer + i;
            break;
        }
    }
    if (!headers_end)
    {
        return -1;
    }

    const char *cursor = buffer;
    static const char HEADER[] = "content-length:";
    const size_t header_len = sizeof(HEADER) - 1u;
    while (cursor < headers_end)
    {
        const char *line_end = memchr(cursor, '\n', (size_t)(headers_end - cursor));
        if (!line_end)
        {
            line_end = headers_end;
        }
        const char *line = cursor;
        if (line_end > line && *(line_end - 1) == '\r')
        {
            line_end -= 1;
        }
        size_t line_len = (size_t)(line_end - line);
        if (line_len >= header_len && strncasecmp(line, HEADER, header_len) == 0)
        {
            const char *value = line + header_len;
            while (value < line_end && (*value == ' ' || *value == '\t'))
            {
                ++value;
            }
            size_t content_length = 0;
            if (value == line_end)
            {
                return -1;
            }
            while (value < line_end)
            {
                if (*value < '0' || *value > '9')
                {
                    return -1;
                }
                size_t digit = (size_t)(*value - '0');
                if (content_length > (SIZE_MAX - digit) / 10u)
                {
                    return -1;
                }
                content_length = (content_length * 10u) + digit;
                ++value;
            }
            *out_content_length = content_length;
            return 0;
        }
        cursor = line_end;
        if (cursor < headers_end && *cursor == '\r')
        {
            ++cursor;
        }
        if (cursor < headers_end && *cursor == '\n')
        {
            ++cursor;
        }
    }
    return -1;
}

static int http_read_request_body(
    int client_fd,
    const char *raw_buffer,
    size_t raw_buffer_len,
    char **out_body,
    size_t *out_body_len)
{
    if (client_fd < 0 || !raw_buffer || !out_body || !out_body_len)
    {
        return -1;
    }
    *out_body = NULL;
    *out_body_len = 0;

    const char *body_ptr = NULL;
    size_t available_len = 0;
    if (!http_locate_body(raw_buffer, raw_buffer_len, &body_ptr, &available_len))
    {
        return -1;
    }

    size_t content_length = 0;
    if (http_parse_content_length(raw_buffer, raw_buffer_len, &content_length) != 0)
    {
        content_length = available_len;
    }
    if (content_length > LANTERN_HTTP_MAX_TEST_DRIVER_BODY_SIZE)
    {
        return -1;
    }

    char *body = malloc(content_length + 1u);
    if (!body)
    {
        return -1;
    }
    size_t copied = available_len < content_length ? available_len : content_length;
    if (copied > 0)
    {
        memcpy(body, body_ptr, copied);
    }
    while (copied < content_length)
    {
        ssize_t received = recv(client_fd, body + copied, content_length - copied, 0);
        if (received < 0 && errno == EINTR)
        {
            continue;
        }
        if (received <= 0)
        {
            free(body);
            return -1;
        }
        copied += (size_t)received;
    }
    body[content_length] = '\0';
    *out_body = body;
    *out_body_len = content_length;
    return 0;
}


/**
 * Strictly parse `{"enabled": <bool>}` from a JSON body.
 *
 * Accepts optional whitespace around tokens and surrounding braces. Any other
 * field, missing "enabled", non-boolean value, or trailing garbage is rejected.
 *
 * @return 0 on success (value written to `*out_enabled`).
 * @return non-zero if the body is missing, malformed, or has a wrong field type.
 */
static int parse_enabled_bool_body(const char *body, size_t body_len, bool *out_enabled)
{
    if (!body || body_len == 0 || !out_enabled)
    {
        return -1;
    }
    size_t i = 0;
    while (i < body_len && (body[i] == ' ' || body[i] == '\t' || body[i] == '\r' || body[i] == '\n'))
    {
        ++i;
    }
    if (i >= body_len || body[i] != '{')
    {
        return -1;
    }
    ++i;
    while (i < body_len && (body[i] == ' ' || body[i] == '\t' || body[i] == '\r' || body[i] == '\n'))
    {
        ++i;
    }
    static const char KEY[] = "\"enabled\"";
    const size_t key_len = sizeof(KEY) - 1u;
    if (i + key_len > body_len || memcmp(body + i, KEY, key_len) != 0)
    {
        return -1;
    }
    i += key_len;
    while (i < body_len && (body[i] == ' ' || body[i] == '\t' || body[i] == '\r' || body[i] == '\n'))
    {
        ++i;
    }
    if (i >= body_len || body[i] != ':')
    {
        return -1;
    }
    ++i;
    while (i < body_len && (body[i] == ' ' || body[i] == '\t' || body[i] == '\r' || body[i] == '\n'))
    {
        ++i;
    }
    bool value = false;
    static const char TRUE_LIT[] = "true";
    static const char FALSE_LIT[] = "false";
    if (i + (sizeof(TRUE_LIT) - 1u) <= body_len
        && memcmp(body + i, TRUE_LIT, sizeof(TRUE_LIT) - 1u) == 0)
    {
        value = true;
        i += sizeof(TRUE_LIT) - 1u;
    }
    else if (i + (sizeof(FALSE_LIT) - 1u) <= body_len
        && memcmp(body + i, FALSE_LIT, sizeof(FALSE_LIT) - 1u) == 0)
    {
        value = false;
        i += sizeof(FALSE_LIT) - 1u;
    }
    else
    {
        return -1;
    }
    while (i < body_len && (body[i] == ' ' || body[i] == '\t' || body[i] == '\r' || body[i] == '\n'))
    {
        ++i;
    }
    if (i >= body_len || body[i] != '}')
    {
        return -1;
    }
    ++i;
    while (i < body_len && (body[i] == ' ' || body[i] == '\t' || body[i] == '\r' || body[i] == '\n'))
    {
        ++i;
    }
    if (i != body_len)
    {
        return -1;
    }
    *out_enabled = value;
    return 0;
}


/**
 * Handle GET/POST /lean/v0/admin/aggregator.
 *
 * @spec https://github.com/leanEthereum/leanSpec/pull/636
 */
static void handle_admin_aggregator(
    struct lantern_http_server *server,
    int client_fd,
    const char *method,
    const char *raw_buffer,
    size_t raw_buffer_len,
    const char *peer_text)
{
    const bool is_get = (strcmp(method, "GET") == 0);
    const bool is_post = (strcmp(method, "POST") == 0);
    if (!is_get && !is_post)
    {
        int rc = send_json_error(client_fd, 405, "Method Not Allowed", LANTERN_HTTP_JSON_METHOD_NOT_ALLOWED);
        lantern_log_info(
            "http",
            &(const struct lantern_log_metadata){.peer = peer_text},
            "%s %s -> 405 (rc=%d)",
            method,
            LANTERN_HTTP_PATH_ADMIN_AGGREGATOR,
            rc);
        return;
    }

    if (is_get)
    {
        if (!server->callbacks.get_is_aggregator)
        {
            int rc = send_json_error(client_fd, 503, "Service Unavailable", LANTERN_HTTP_JSON_UNAVAILABLE);
            lantern_log_info(
                "http",
                &(const struct lantern_log_metadata){.peer = peer_text},
                "GET %s -> 503 (rc=%d)",
                LANTERN_HTTP_PATH_ADMIN_AGGREGATOR,
                rc);
            return;
        }
        bool enabled = false;
        int cb_rc = server->callbacks.get_is_aggregator(server->callbacks.context, &enabled);
        if (cb_rc != LANTERN_HTTP_CB_OK)
        {
            int rc = send_json_error(client_fd, 503, "Service Unavailable", LANTERN_HTTP_JSON_UNAVAILABLE);
            lantern_log_info(
                "http",
                &(const struct lantern_log_metadata){.peer = peer_text},
                "GET %s -> 503 (cb_rc=%d rc=%d)",
                LANTERN_HTTP_PATH_ADMIN_AGGREGATOR,
                cb_rc,
                rc);
            return;
        }
        char body[64];
        int body_len = snprintf(
            body,
            sizeof(body),
            "{\"is_aggregator\":%s}",
            enabled ? "true" : "false");
        if (body_len <= 0 || (size_t)body_len >= sizeof(body))
        {
            send_json_error(client_fd, 500, "Internal Server Error", LANTERN_HTTP_JSON_INTERNAL);
            return;
        }
        int rc = send_http_response(client_fd, 200, "OK", "application/json", body, (size_t)body_len);
        lantern_log_info(
            "http",
            &(const struct lantern_log_metadata){.peer = peer_text},
            "GET %s -> 200 (rc=%d)",
            LANTERN_HTTP_PATH_ADMIN_AGGREGATOR,
            rc);
        return;
    }

    /* POST */
    if (!server->callbacks.set_is_aggregator)
    {
        int rc = send_json_error(client_fd, 503, "Service Unavailable", LANTERN_HTTP_JSON_UNAVAILABLE);
        lantern_log_info(
            "http",
            &(const struct lantern_log_metadata){.peer = peer_text},
            "POST %s -> 503 (rc=%d)",
            LANTERN_HTTP_PATH_ADMIN_AGGREGATOR,
            rc);
        return;
    }
    const char *body_ptr = NULL;
    size_t body_len = 0;
    if (!http_locate_body(raw_buffer, raw_buffer_len, &body_ptr, &body_len) || body_len == 0)
    {
        int rc = send_json_error(client_fd, 400, "Bad Request", LANTERN_HTTP_JSON_BAD_REQUEST);
        lantern_log_info(
            "http",
            &(const struct lantern_log_metadata){.peer = peer_text},
            "POST %s -> 400 (empty body, rc=%d)",
            LANTERN_HTTP_PATH_ADMIN_AGGREGATOR,
            rc);
        return;
    }
    bool enabled = false;
    if (parse_enabled_bool_body(body_ptr, body_len, &enabled) != 0)
    {
        int rc = send_json_error(client_fd, 400, "Bad Request", LANTERN_HTTP_JSON_BAD_REQUEST);
        lantern_log_info(
            "http",
            &(const struct lantern_log_metadata){.peer = peer_text},
            "POST %s -> 400 (bad body, rc=%d)",
            LANTERN_HTTP_PATH_ADMIN_AGGREGATOR,
            rc);
        return;
    }
    bool previous = false;
    int cb_rc = server->callbacks.set_is_aggregator(server->callbacks.context, enabled, &previous);
    if (cb_rc != LANTERN_HTTP_CB_OK)
    {
        int rc = send_json_error(client_fd, 503, "Service Unavailable", LANTERN_HTTP_JSON_UNAVAILABLE);
        lantern_log_info(
            "http",
            &(const struct lantern_log_metadata){.peer = peer_text},
            "POST %s -> 503 (cb_rc=%d rc=%d)",
            LANTERN_HTTP_PATH_ADMIN_AGGREGATOR,
            cb_rc,
            rc);
        return;
    }
    char resp[96];
    int resp_len = snprintf(
        resp,
        sizeof(resp),
        "{\"is_aggregator\":%s,\"previous\":%s}",
        enabled ? "true" : "false",
        previous ? "true" : "false");
    if (resp_len <= 0 || (size_t)resp_len >= sizeof(resp))
    {
        send_json_error(client_fd, 500, "Internal Server Error", LANTERN_HTTP_JSON_INTERNAL);
        return;
    }
    int rc = send_http_response(client_fd, 200, "OK", "application/json", resp, (size_t)resp_len);
    lantern_log_info(
        "http",
        &(const struct lantern_log_metadata){.peer = peer_text},
        "POST %s -> 200 enabled=%s previous=%s (rc=%d)",
        LANTERN_HTTP_PATH_ADMIN_AGGREGATOR,
        enabled ? "true" : "false",
        previous ? "true" : "false",
        rc);
}

static bool is_test_driver_path(const char *path)
{
    return path
        && (strcmp(path, LANTERN_HTTP_PATH_TEST_FC_INIT) == 0
            || strcmp(path, LANTERN_HTTP_PATH_TEST_FC_STEP) == 0
            || strcmp(path, LANTERN_HTTP_PATH_TEST_STATE_RUN) == 0
            || strcmp(path, LANTERN_HTTP_PATH_TEST_VERIFY_RUN) == 0);
}

static void handle_test_driver(
    int client_fd,
    const char *method,
    const char *path,
    const char *raw_buffer,
    size_t raw_buffer_len,
    const char *peer_text)
{
    if (strcmp(method, "POST") != 0)
    {
        int rc = send_json_error(client_fd, 405, "Method Not Allowed", LANTERN_HTTP_JSON_METHOD_NOT_ALLOWED);
        lantern_log_info(
            "http",
            &(const struct lantern_log_metadata){.peer = peer_text},
            "%s %s -> 405 (rc=%d)",
            method,
            path,
            rc);
        return;
    }

    char *request_body = NULL;
    size_t request_body_len = 0;
    if (http_read_request_body(
            client_fd,
            raw_buffer,
            raw_buffer_len,
            &request_body,
            &request_body_len)
        != 0)
    {
        int rc = send_json_error(client_fd, 400, "Bad Request", LANTERN_HTTP_JSON_BAD_REQUEST);
        lantern_log_info(
            "http",
            &(const struct lantern_log_metadata){.peer = peer_text},
            "POST %s -> 400 (body read failed, rc=%d)",
            path,
            rc);
        return;
    }

    if (strcmp(path, LANTERN_HTTP_PATH_TEST_FC_INIT) == 0)
    {
        char *error = NULL;
        int driver_rc =
            lantern_test_driver_fork_choice_init(request_body, request_body_len, &error);
        free(request_body);
        if (driver_rc != 0)
        {
            int rc = send_json_error(
                client_fd,
                400,
                "Bad Request",
                LANTERN_HTTP_JSON_BAD_REQUEST);
            lantern_log_info(
                "http",
                &(const struct lantern_log_metadata){.peer = peer_text},
                "POST %s -> 400 (driver_rc=%d error=%s rc=%d)",
                path,
                driver_rc,
                error ? error : "-",
                rc);
            free(error);
            return;
        }
        int rc = send_http_response(client_fd, 204, "No Content", "application/json", NULL, 0);
        lantern_log_info(
            "http",
            &(const struct lantern_log_metadata){.peer = peer_text},
            "POST %s -> 204 (rc=%d)",
            path,
            rc);
        return;
    }

    char *response_body = NULL;
    size_t response_body_len = 0;
    int driver_rc = -1;
    if (strcmp(path, LANTERN_HTTP_PATH_TEST_FC_STEP) == 0)
    {
        driver_rc = lantern_test_driver_fork_choice_step(
            request_body,
            request_body_len,
            &response_body,
            &response_body_len);
    }
    else if (strcmp(path, LANTERN_HTTP_PATH_TEST_STATE_RUN) == 0)
    {
        driver_rc = lantern_test_driver_state_transition_run(
            request_body,
            request_body_len,
            &response_body,
            &response_body_len);
    }
    else if (strcmp(path, LANTERN_HTTP_PATH_TEST_VERIFY_RUN) == 0)
    {
        driver_rc = lantern_test_driver_verify_signatures_run(
            request_body,
            request_body_len,
            &response_body,
            &response_body_len);
    }
    free(request_body);

    if (driver_rc != 0 || !response_body)
    {
        free(response_body);
        int rc = send_json_error(client_fd, 500, "Internal Server Error", LANTERN_HTTP_JSON_INTERNAL);
        lantern_log_error(
            "http",
            &(const struct lantern_log_metadata){.peer = peer_text},
            "POST %s -> 500 (driver_rc=%d rc=%d)",
            path,
            driver_rc,
            rc);
        return;
    }

    int rc = send_http_response(
        client_fd,
        200,
        "OK",
        "application/json",
        response_body,
        response_body_len);
    free(response_body);
    lantern_log_info(
        "http",
        &(const struct lantern_log_metadata){.peer = peer_text},
        "POST %s -> 200 (rc=%d)",
        path,
        rc);
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

    int result = parse_request_line(buffer, method, sizeof(method), path, sizeof(path));
    if (result != 0)
    {
        int rc = send_json_error(client_fd, 400, "Bad Request", LANTERN_HTTP_JSON_MALFORMED);
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

    if (strcmp(path, LANTERN_HTTP_PATH_ADMIN_AGGREGATOR) == 0)
    {
        handle_admin_aggregator(
            server,
            client_fd,
            method,
            buffer,
            (size_t)received,
            peer_text);
        return;
    }

    if (is_test_driver_path(path))
    {
        handle_test_driver(
            client_fd,
            method,
            path,
            buffer,
            (size_t)received,
            peer_text);
        return;
    }

    if (strcmp(method, "GET") != 0)
    {
        int rc = send_json_error(client_fd, 404, "Not Found", LANTERN_HTTP_JSON_UNKNOWN_ENDPOINT);
        if (rc == 0)
        {
            lantern_log_info(
                "http",
                &(const struct lantern_log_metadata){.peer = peer_text},
                "%s %s -> 404",
                method,
                path);
        }
        else
        {
            lantern_log_error(
                "http",
                &(const struct lantern_log_metadata){.peer = peer_text},
                "failed to send 404 response rc=%d",
                rc);
        }
        return;
    }

    if (strcmp(path, LANTERN_HTTP_PATH_HEALTH) == 0)
    {
        int rc = send_http_response(
            client_fd,
            200,
            "OK",
            "application/json",
            LANTERN_HTTP_JSON_HEALTH,
            strlen(LANTERN_HTTP_JSON_HEALTH));
        if (rc == 0)
        {
            lantern_log_info(
                "http",
                &(const struct lantern_log_metadata){.peer = peer_text},
                "GET %s -> 200",
                path);
        }
        else
        {
            lantern_log_error(
                "http",
                &(const struct lantern_log_metadata){.peer = peer_text},
                "failed to send health response rc=%d",
                rc);
        }
        return;
    }

    if (strcmp(path, LANTERN_HTTP_PATH_METRICS) == 0)
    {
        if (!server->callbacks.metrics_snapshot)
        {
            int rc = send_json_error(client_fd, 503, "Service Unavailable", LANTERN_HTTP_JSON_UNAVAILABLE);
            lantern_log_error(
                "http",
                &(const struct lantern_log_metadata){.peer = peer_text},
                "metrics callback missing rc=%d",
                rc);
            return;
        }

        struct lantern_metrics_snapshot snapshot;
        memset(&snapshot, 0, sizeof(snapshot));
        if (server->callbacks.metrics_snapshot(server->callbacks.context, &snapshot) != 0)
        {
            int rc = send_json_error(client_fd, 503, "Service Unavailable", LANTERN_HTTP_JSON_UNAVAILABLE);
            lantern_log_error(
                "http",
                &(const struct lantern_log_metadata){.peer = peer_text},
                "metrics snapshot failed rc=%d",
                rc);
            return;
        }

        char *body = NULL;
        size_t body_len = 0;
        result = lantern_metrics_format_prometheus(&snapshot, &body, &body_len);
        if (result != 0)
        {
            int rc = send_json_error(client_fd, 500, "Internal Server Error", LANTERN_HTTP_JSON_INTERNAL);
            lantern_log_error(
                "http",
                &(const struct lantern_log_metadata){.peer = peer_text},
                "metrics formatting failed result=%d send_rc=%d",
                result,
                rc);
            return;
        }

        result = send_http_response(
            client_fd,
            200,
            "OK",
            LANTERN_METRICS_CONTENT_TYPE,
            body,
            body_len);
        free(body);
        if (result != 0)
        {
            lantern_log_error(
                "http",
                &(const struct lantern_log_metadata){.peer = peer_text},
                "metrics send failed rc=%d",
                result);
            return;
        }

        lantern_log_info(
            "http",
            &(const struct lantern_log_metadata){.peer = peer_text},
            "GET %s -> 200",
            path);
        return;
    }

    if (strcmp(path, LANTERN_HTTP_PATH_FINALIZED) == 0)
    {
        if (!server->callbacks.finalized_state_ssz)
        {
            int rc = send_json_error(client_fd, 503, "Service Unavailable", LANTERN_HTTP_JSON_UNAVAILABLE);
            lantern_log_error(
                "http",
                &(const struct lantern_log_metadata){.peer = peer_text},
                "finalized state callback missing rc=%d",
                rc);
            return;
        }

        uint8_t *state_bytes = NULL;
        size_t state_len = 0;
        int state_rc = server->callbacks.finalized_state_ssz(
            server->callbacks.context,
            &state_bytes,
            &state_len);
        if (state_rc != 0)
        {
            const char *body = LANTERN_HTTP_JSON_INTERNAL;
            int status_code = 500;
            const char *status_text = "Internal Server Error";
            if (state_rc == LANTERN_HTTP_CB_ERR_NOT_FOUND)
            {
                body = LANTERN_HTTP_JSON_STATE_MISSING;
                status_code = 404;
                status_text = "Not Found";
            }
            else if (state_rc == LANTERN_HTTP_CB_ERR_INVALID_STATE
                || state_rc == LANTERN_HTTP_CB_ERR_LOCK_FAILED
                || state_rc == LANTERN_HTTP_CB_ERR_UNAVAILABLE)
            {
                body = LANTERN_HTTP_JSON_UNAVAILABLE;
                status_code = 503;
                status_text = "Service Unavailable";
            }

            if (state_bytes)
            {
                free(state_bytes);
            }

            int rc = send_json_error(client_fd, status_code, status_text, body);
            if (state_rc == LANTERN_HTTP_CB_ERR_NOT_FOUND)
            {
                lantern_log_info(
                    "http",
                    &(const struct lantern_log_metadata){.peer = peer_text},
                    "finalized state missing -> 404");
            }
            else if (state_rc == LANTERN_HTTP_CB_ERR_INVALID_STATE
                || state_rc == LANTERN_HTTP_CB_ERR_LOCK_FAILED
                || state_rc == LANTERN_HTTP_CB_ERR_UNAVAILABLE)
            {
                lantern_log_warn(
                    "http",
                    &(const struct lantern_log_metadata){.peer = peer_text},
                    "finalized state unavailable rc=%d send_rc=%d",
                    state_rc,
                    rc);
            }
            else
            {
                lantern_log_error(
                    "http",
                    &(const struct lantern_log_metadata){.peer = peer_text},
                    "finalized state failed rc=%d send_rc=%d",
                    state_rc,
                    rc);
            }
            return;
        }

        if (!state_bytes || state_len == 0)
        {
            if (state_bytes)
            {
                free(state_bytes);
            }
            int rc = send_json_error(client_fd, 500, "Internal Server Error", LANTERN_HTTP_JSON_INTERNAL);
            lantern_log_error(
                "http",
                &(const struct lantern_log_metadata){.peer = peer_text},
                "finalized state empty send_rc=%d",
                rc);
            return;
        }

        result = send_http_response(
            client_fd,
            200,
            "OK",
            "application/octet-stream",
            (const char *)state_bytes,
            state_len);
        free(state_bytes);
        if (result != 0)
        {
            lantern_log_error(
                "http",
                &(const struct lantern_log_metadata){.peer = peer_text},
                "finalized state send failed rc=%d",
                result);
            return;
        }

        lantern_log_info(
            "http",
            &(const struct lantern_log_metadata){.peer = peer_text},
            "GET %s -> 200",
            path);
        return;
    }

    if (strcmp(path, LANTERN_HTTP_PATH_FINALIZED_BLOCK) == 0)
    {
        if (!server->callbacks.finalized_block_ssz)
        {
            int rc = send_json_error(client_fd, 503, "Service Unavailable", LANTERN_HTTP_JSON_UNAVAILABLE);
            lantern_log_error(
                "http",
                &(const struct lantern_log_metadata){.peer = peer_text},
                "finalized block callback missing rc=%d",
                rc);
            return;
        }

        uint8_t *block_bytes = NULL;
        size_t block_len = 0;
        int block_rc = server->callbacks.finalized_block_ssz(
            server->callbacks.context,
            &block_bytes,
            &block_len);
        if (block_rc != 0)
        {
            const char *body = LANTERN_HTTP_JSON_INTERNAL;
            int status_code = 500;
            const char *status_text = "Internal Server Error";
            if (block_rc == LANTERN_HTTP_CB_ERR_NOT_FOUND)
            {
                body = LANTERN_HTTP_JSON_BLOCK_MISSING;
                status_code = 404;
                status_text = "Not Found";
            }
            else if (block_rc == LANTERN_HTTP_CB_ERR_INVALID_STATE
                || block_rc == LANTERN_HTTP_CB_ERR_LOCK_FAILED
                || block_rc == LANTERN_HTTP_CB_ERR_UNAVAILABLE)
            {
                body = LANTERN_HTTP_JSON_UNAVAILABLE;
                status_code = 503;
                status_text = "Service Unavailable";
            }

            free(block_bytes);

            int rc = send_json_error(client_fd, status_code, status_text, body);
            if (block_rc == LANTERN_HTTP_CB_ERR_NOT_FOUND)
            {
                lantern_log_info(
                    "http",
                    &(const struct lantern_log_metadata){.peer = peer_text},
                    "finalized block missing -> 404");
            }
            else if (block_rc == LANTERN_HTTP_CB_ERR_INVALID_STATE
                || block_rc == LANTERN_HTTP_CB_ERR_LOCK_FAILED
                || block_rc == LANTERN_HTTP_CB_ERR_UNAVAILABLE)
            {
                lantern_log_warn(
                    "http",
                    &(const struct lantern_log_metadata){.peer = peer_text},
                    "finalized block unavailable rc=%d send_rc=%d",
                    block_rc,
                    rc);
            }
            else
            {
                lantern_log_error(
                    "http",
                    &(const struct lantern_log_metadata){.peer = peer_text},
                    "finalized block failed rc=%d send_rc=%d",
                    block_rc,
                    rc);
            }
            return;
        }

        if (!block_bytes || block_len == 0)
        {
            free(block_bytes);
            int rc = send_json_error(client_fd, 500, "Internal Server Error", LANTERN_HTTP_JSON_INTERNAL);
            lantern_log_error(
                "http",
                &(const struct lantern_log_metadata){.peer = peer_text},
                "finalized block empty send_rc=%d",
                rc);
            return;
        }

        result = send_http_response(
            client_fd,
            200,
            "OK",
            "application/octet-stream",
            (const char *)block_bytes,
            block_len);
        free(block_bytes);
        if (result != 0)
        {
            lantern_log_error(
                "http",
                &(const struct lantern_log_metadata){.peer = peer_text},
                "finalized block send failed rc=%d",
                result);
            return;
        }

        lantern_log_info(
            "http",
            &(const struct lantern_log_metadata){.peer = peer_text},
            "GET %s -> 200",
            path);
        return;
    }

    if (strcmp(path, LANTERN_HTTP_PATH_JUSTIFIED) == 0)
    {
        if (!server->callbacks.snapshot_head)
        {
            int rc = send_json_error(client_fd, 503, "Service Unavailable", LANTERN_HTTP_JSON_UNAVAILABLE);
            lantern_log_error(
                "http",
                &(const struct lantern_log_metadata){.peer = peer_text},
                "justified snapshot callback missing rc=%d",
                rc);
            return;
        }

        struct lantern_http_head_snapshot snapshot;
        memset(&snapshot, 0, sizeof(snapshot));
        int snapshot_rc = server->callbacks.snapshot_head(server->callbacks.context, &snapshot);
        if (snapshot_rc != 0)
        {
            const char *body = LANTERN_HTTP_JSON_INTERNAL;
            int status_code = 500;
            const char *status_text = "Internal Server Error";
            if (snapshot_rc == LANTERN_HTTP_CB_ERR_INVALID_STATE
                || snapshot_rc == LANTERN_HTTP_CB_ERR_LOCK_FAILED
                || snapshot_rc == LANTERN_HTTP_CB_ERR_UNAVAILABLE)
            {
                body = LANTERN_HTTP_JSON_UNAVAILABLE;
                status_code = 503;
                status_text = "Service Unavailable";
            }

            int rc = send_json_error(client_fd, status_code, status_text, body);
            if (snapshot_rc == LANTERN_HTTP_CB_ERR_INVALID_STATE
                || snapshot_rc == LANTERN_HTTP_CB_ERR_LOCK_FAILED
                || snapshot_rc == LANTERN_HTTP_CB_ERR_UNAVAILABLE)
            {
                lantern_log_warn(
                    "http",
                    &(const struct lantern_log_metadata){.peer = peer_text},
                    "justified snapshot unavailable rc=%d send_rc=%d",
                    snapshot_rc,
                    rc);
            }
            else
            {
                lantern_log_error(
                    "http",
                    &(const struct lantern_log_metadata){.peer = peer_text},
                    "justified snapshot failed rc=%d send_rc=%d",
                    snapshot_rc,
                    rc);
            }
            return;
        }

        char root_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
        if (lantern_bytes_to_hex(
                snapshot.justified.root.bytes,
                LANTERN_ROOT_SIZE,
                root_hex,
                sizeof(root_hex),
                1)
            != 0)
        {
            int rc = send_json_error(client_fd, 500, "Internal Server Error", LANTERN_HTTP_JSON_INTERNAL);
            lantern_log_error(
                "http",
                &(const struct lantern_log_metadata){.peer = peer_text},
                "justified root hex failed send_rc=%d",
                rc);
            return;
        }

        char body[256];
        int body_written = snprintf(
            body,
            sizeof(body),
            "{\"slot\":%" PRIu64 ",\"root\":\"%s\"}",
            snapshot.justified.slot,
            root_hex);
        if (body_written < 0 || (size_t)body_written >= sizeof(body))
        {
            int rc = send_json_error(client_fd, 500, "Internal Server Error", LANTERN_HTTP_JSON_INTERNAL);
            lantern_log_error(
                "http",
                &(const struct lantern_log_metadata){.peer = peer_text},
                "justified response format failed send_rc=%d",
                rc);
            return;
        }

        result = send_http_response(
            client_fd,
            200,
            "OK",
            "application/json",
            body,
            (size_t)body_written);
        if (result != 0)
        {
            lantern_log_error(
                "http",
                &(const struct lantern_log_metadata){.peer = peer_text},
                "justified response send failed rc=%d",
                result);
            return;
        }

        lantern_log_info(
            "http",
            &(const struct lantern_log_metadata){.peer = peer_text},
            "GET %s -> 200",
            path);
        return;
    }

    if (strcmp(path, LANTERN_HTTP_PATH_FORK_CHOICE) == 0)
    {
        if (!server->callbacks.snapshot_fork_choice)
        {
            int rc = send_json_error(client_fd, 503, "Service Unavailable", LANTERN_HTTP_JSON_UNAVAILABLE);
            lantern_log_error(
                "http",
                &(const struct lantern_log_metadata){.peer = peer_text},
                "fork choice snapshot callback missing rc=%d",
                rc);
            return;
        }

        struct lantern_http_fork_choice_snapshot snapshot;
        memset(&snapshot, 0, sizeof(snapshot));
        int snapshot_rc = server->callbacks.snapshot_fork_choice(server->callbacks.context, &snapshot);
        if (snapshot_rc != 0)
        {
            const char *body = LANTERN_HTTP_JSON_INTERNAL;
            int status_code = 500;
            const char *status_text = "Internal Server Error";
            if (snapshot_rc == LANTERN_HTTP_CB_ERR_INVALID_STATE
                || snapshot_rc == LANTERN_HTTP_CB_ERR_LOCK_FAILED
                || snapshot_rc == LANTERN_HTTP_CB_ERR_UNAVAILABLE)
            {
                body = LANTERN_HTTP_JSON_UNAVAILABLE;
                status_code = 503;
                status_text = "Service Unavailable";
            }

            int rc = send_json_error(client_fd, status_code, status_text, body);
            if (snapshot_rc == LANTERN_HTTP_CB_ERR_INVALID_STATE
                || snapshot_rc == LANTERN_HTTP_CB_ERR_LOCK_FAILED
                || snapshot_rc == LANTERN_HTTP_CB_ERR_UNAVAILABLE)
            {
                lantern_log_warn(
                    "http",
                    &(const struct lantern_log_metadata){.peer = peer_text},
                    "fork choice snapshot unavailable rc=%d send_rc=%d",
                    snapshot_rc,
                    rc);
            }
            else
            {
                lantern_log_error(
                    "http",
                    &(const struct lantern_log_metadata){.peer = peer_text},
                    "fork choice snapshot failed rc=%d send_rc=%d",
                    snapshot_rc,
                    rc);
            }
            return;
        }

        char *body = NULL;
        size_t body_len = 0;
        result = format_fork_choice_response(&snapshot, &body, &body_len);
        free(snapshot.nodes);
        if (result != 0)
        {
            int rc = send_json_error(client_fd, 500, "Internal Server Error", LANTERN_HTTP_JSON_INTERNAL);
            lantern_log_error(
                "http",
                &(const struct lantern_log_metadata){.peer = peer_text},
                "fork choice response format failed send_rc=%d",
                rc);
            return;
        }

        result = send_http_response(
            client_fd,
            200,
            "OK",
            "application/json",
            body,
            body_len);
        free(body);
        if (result != 0)
        {
            lantern_log_error(
                "http",
                &(const struct lantern_log_metadata){.peer = peer_text},
                "fork choice response send failed rc=%d",
                result);
            return;
        }

        lantern_log_info(
            "http",
            &(const struct lantern_log_metadata){.peer = peer_text},
            "GET %s -> 200",
            path);
        return;
    }

    {
        int rc = send_json_error(client_fd, 404, "Not Found", LANTERN_HTTP_JSON_UNKNOWN_ENDPOINT);
        if (rc == 0)
        {
            lantern_log_info(
                "http",
                &(const struct lantern_log_metadata){.peer = peer_text},
                "%s %s -> 404",
                method,
                path);
        }
        else
        {
            lantern_log_error(
                "http",
                &(const struct lantern_log_metadata){.peer = peer_text},
                "failed to send 404 response rc=%d",
                rc);
        }
    }
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
static void *lantern_http_thread(void *arg)
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
            if (!server->running)
            {
                break;
            }
            if (errno == EBADF || errno == EINVAL)
            {
                break;
            }
            if (errno == ECONNABORTED)
            {
                continue;
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
 * Start the HTTP server.
 *
 * Creates a listening socket and starts a background thread to accept incoming
 * connections and serve health, metrics, and checkpoint sync endpoints.
 *
 * @param server Server instance to start (modified in place).
 * @param config Server configuration (port and callbacks).
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

    if (server->port == 0)
    {
        struct sockaddr_in bound_addr;
        socklen_t bound_len = sizeof(bound_addr);
        if (getsockname(fd, (struct sockaddr *)&bound_addr, &bound_len) == 0)
        {
            server->port = ntohs(bound_addr.sin_port);
        }
    }

    int create_rc = pthread_create(&server->thread, NULL, lantern_http_thread, server);
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
