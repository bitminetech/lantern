/**
 * @file core.c
 * @brief Shared HTTP transport core.
 *
 * Owns Lantern's small blocking HTTP/1.1 server loop, request-line parsing,
 * response writing, request-body reads, and growable formatting buffers.
 *
 * @spec RFC 9110/9112 and POSIX sockets/pthreads.
 */

#include "lantern/http/core.h"

#include <arpa/inet.h>
#include <errno.h>
#include <inttypes.h>
#include <netinet/in.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>

#include "lantern/support/log.h"
#include "lantern/support/strings.h"

static const size_t HTTP_RESPONSE_HEADER_BUFFER_LEN = 256;
static const size_t HTTP_BUFFER_DEFAULT_CAP = 1024;
static const int HTTP_STATUS_CODE_MIN = 100;
static const int HTTP_STATUS_CODE_MAX = 999;

enum
{
    LANTERN_HTTP_SEND_OK = 0,
    LANTERN_HTTP_SEND_ERR_INVALID_PARAM = -1,
    LANTERN_HTTP_SEND_ERR_SEND_FAILED = -2,
    LANTERN_HTTP_SEND_ERR_HEADER_TOO_LARGE = -3,
};

static const char DEFAULT_MALFORMED_JSON[] = "{\"error\":\"malformed request\"}";
static const char DEFAULT_UNKNOWN_JSON[] = "{\"error\":\"unknown endpoint\"}";

static const char *core_log_module(const struct lantern_http_core_server *server)
{
    return server && server->config.log_module ? server->config.log_module : "http";
}

static void peer_to_text(const struct sockaddr_in *peer_addr, char *out, size_t out_len)
{
    if (!out || out_len == 0)
    {
        return;
    }
    if (!peer_addr || !inet_ntop(AF_INET, &peer_addr->sin_addr, out, out_len))
    {
        (void)lantern_string_copy(out, out_len, "unknown");
    }
}

static int parse_request_line(
    const char *request,
    char *method,
    size_t method_len,
    char *path,
    size_t path_len)
{
    if (!request || !method || method_len == 0 || !path || path_len == 0)
    {
        return LANTERN_HTTP_CORE_ERR_INVALID_PARAM;
    }

    const char *space = strchr(request, ' ');
    if (!space)
    {
        return LANTERN_HTTP_CORE_ERR_MALFORMED_REQUEST;
    }

    size_t method_written = (size_t)(space - request);
    if (method_written == 0 || method_written >= method_len)
    {
        return LANTERN_HTTP_CORE_ERR_MALFORMED_REQUEST;
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
        return LANTERN_HTTP_CORE_ERR_MALFORMED_REQUEST;
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
        return LANTERN_HTTP_CORE_ERR_MALFORMED_REQUEST;
    }
    memcpy(path, path_start, path_written);
    path[path_written] = '\0';
    return LANTERN_HTTP_CORE_OK;
}

bool lantern_http_locate_body(
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

int lantern_http_parse_content_length(
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
            if (value == line_end)
            {
                return -1;
            }

            size_t content_length = 0;
            bool have_digit = false;
            while (value < line_end)
            {
                if (*value == ' ' || *value == '\t')
                {
                    break;
                }
                if (*value < '0' || *value > '9')
                {
                    return -1;
                }
                have_digit = true;
                size_t digit = (size_t)(*value - '0');
                if (content_length > (SIZE_MAX - digit) / 10u)
                {
                    return -1;
                }
                content_length = (content_length * 10u) + digit;
                ++value;
            }
            while (value < line_end && (*value == ' ' || *value == '\t'))
            {
                ++value;
            }
            if (!have_digit || value != line_end)
            {
                return -1;
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

int lantern_http_send_all(int fd, const char *data, size_t length)
{
    if (fd < 0 || (!data && length != 0))
    {
        return LANTERN_HTTP_SEND_ERR_INVALID_PARAM;
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
            return LANTERN_HTTP_SEND_ERR_SEND_FAILED;
        }
        if (written < 0)
        {
            if (errno == EINTR)
            {
                continue;
            }
            return LANTERN_HTTP_SEND_ERR_SEND_FAILED;
        }
        data += (size_t)written;
        length -= (size_t)written;
    }
    return LANTERN_HTTP_SEND_OK;
}

int lantern_http_send_response(
    int fd,
    int status_code,
    const char *status_text,
    const char *content_type,
    const char *body,
    size_t body_len)
{
    if (fd < 0
        || status_code < HTTP_STATUS_CODE_MIN
        || status_code > HTTP_STATUS_CODE_MAX
        || (!body && body_len != 0))
    {
        return LANTERN_HTTP_SEND_ERR_INVALID_PARAM;
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
        return LANTERN_HTTP_SEND_ERR_HEADER_TOO_LARGE;
    }

    int result = lantern_http_send_all(fd, header, (size_t)header_len);
    if (result != 0 || content_length == 0)
    {
        return result;
    }
    return lantern_http_send_all(fd, body, content_length);
}

int lantern_http_send_json_error(
    int fd,
    int status_code,
    const char *status_text,
    const char *json_body)
{
    return lantern_http_send_response(
        fd,
        status_code,
        status_text,
        "application/json",
        json_body,
        json_body ? strlen(json_body) : 0u);
}

int lantern_http_buffer_init(struct lantern_http_buffer *buf, size_t initial_cap)
{
    if (!buf)
    {
        return LANTERN_HTTP_CORE_ERR_INVALID_PARAM;
    }

    size_t capacity = initial_cap != 0 ? initial_cap : HTTP_BUFFER_DEFAULT_CAP;
    buf->data = malloc(capacity);
    if (!buf->data)
    {
        return LANTERN_HTTP_CORE_ERR_OUT_OF_MEMORY;
    }
    buf->len = 0;
    buf->cap = capacity;
    buf->data[0] = '\0';
    return LANTERN_HTTP_CORE_OK;
}

void lantern_http_buffer_free(struct lantern_http_buffer *buf)
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

int lantern_http_buffer_reserve(struct lantern_http_buffer *buf, size_t extra)
{
    if (!buf)
    {
        return LANTERN_HTTP_CORE_ERR_INVALID_PARAM;
    }
    if (extra == 0)
    {
        return LANTERN_HTTP_CORE_OK;
    }
    if (buf->len >= SIZE_MAX - 1 || extra > (SIZE_MAX - buf->len - 1))
    {
        return LANTERN_HTTP_CORE_ERR_OVERFLOW;
    }

    size_t required = buf->len + extra + 1;
    if (required <= buf->cap)
    {
        return LANTERN_HTTP_CORE_OK;
    }

    size_t new_cap = buf->cap != 0 ? buf->cap : HTTP_BUFFER_DEFAULT_CAP;
    while (new_cap < required)
    {
        if (new_cap > SIZE_MAX / 2)
        {
            return LANTERN_HTTP_CORE_ERR_OVERFLOW;
        }
        new_cap *= 2;
    }

    char *new_data = realloc(buf->data, new_cap);
    if (!new_data)
    {
        return LANTERN_HTTP_CORE_ERR_OUT_OF_MEMORY;
    }
    buf->data = new_data;
    buf->cap = new_cap;
    return LANTERN_HTTP_CORE_OK;
}

int lantern_http_buffer_appendf(struct lantern_http_buffer *buf, const char *fmt, ...)
{
    if (!buf || !fmt)
    {
        return LANTERN_HTTP_CORE_ERR_INVALID_PARAM;
    }

    va_list args;
    va_start(args, fmt);

    va_list measure;
    va_copy(measure, args);
    int needed = vsnprintf(NULL, 0, fmt, measure);
    va_end(measure);
    if (needed < 0)
    {
        va_end(args);
        return LANTERN_HTTP_CORE_ERR_FORMATTING;
    }

    int reserve_rc = lantern_http_buffer_reserve(buf, (size_t)needed);
    if (reserve_rc != 0)
    {
        va_end(args);
        return reserve_rc;
    }

    int written = vsnprintf(buf->data + buf->len, buf->cap - buf->len, fmt, args);
    va_end(args);
    if (written < 0 || written != needed)
    {
        return LANTERN_HTTP_CORE_ERR_FORMATTING;
    }
    buf->len += (size_t)written;
    return LANTERN_HTTP_CORE_OK;
}

int lantern_http_request_read_body(
    const struct lantern_http_request *request,
    size_t max_body_size,
    char **out_body,
    size_t *out_body_len)
{
    if (!request || request->client_fd < 0 || !request->raw || !out_body || !out_body_len)
    {
        return LANTERN_HTTP_CORE_ERR_INVALID_PARAM;
    }
    *out_body = NULL;
    *out_body_len = 0;

    const char *body_ptr = NULL;
    size_t available_len = 0;
    if (!lantern_http_locate_body(request->raw, request->raw_len, &body_ptr, &available_len))
    {
        return LANTERN_HTTP_CORE_ERR_MALFORMED_REQUEST;
    }

    size_t content_length = 0;
    if (lantern_http_parse_content_length(request->raw, request->raw_len, &content_length) != 0)
    {
        content_length = available_len;
    }
    if (content_length > max_body_size || content_length == SIZE_MAX)
    {
        return LANTERN_HTTP_CORE_ERR_INVALID_PARAM;
    }

    char *body = malloc(content_length + 1u);
    if (!body)
    {
        return LANTERN_HTTP_CORE_ERR_OUT_OF_MEMORY;
    }

    size_t copied = available_len < content_length ? available_len : content_length;
    if (copied > 0)
    {
        memcpy(body, body_ptr, copied);
    }
    while (copied < content_length)
    {
        ssize_t received = recv(request->client_fd, body + copied, content_length - copied, 0);
        if (received < 0 && errno == EINTR)
        {
            continue;
        }
        if (received <= 0)
        {
            free(body);
            return LANTERN_HTTP_CORE_ERR_IO;
        }
        copied += (size_t)received;
    }
    body[content_length] = '\0';
    *out_body = body;
    *out_body_len = content_length;
    return LANTERN_HTTP_CORE_OK;
}

static void fill_config_defaults(struct lantern_http_core_config *config)
{
    if (!config->log_module)
    {
        config->log_module = "http";
    }
    if (!config->listen_label)
    {
        config->listen_label = "http server";
    }
    if (!config->malformed_json)
    {
        config->malformed_json = DEFAULT_MALFORMED_JSON;
    }
    if (!config->unknown_json)
    {
        config->unknown_json = DEFAULT_UNKNOWN_JSON;
    }
}

static int route_matches(
    const struct lantern_http_route *route,
    const char *method,
    const char *path)
{
    return route
        && route->path
        && route->handler
        && strcmp(route->path, path) == 0
        && (!route->method || strcmp(route->method, method) == 0);
}

static void handle_client_connection(
    struct lantern_http_core_server *server,
    int client_fd,
    const struct sockaddr_in *peer_addr)
{
    if (!server || client_fd < 0)
    {
        return;
    }

    char peer_text[INET_ADDRSTRLEN];
    peer_to_text(peer_addr, peer_text, sizeof(peer_text));

    char buffer[LANTERN_HTTP_CORE_READ_BUFFER_SIZE];
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

    char method[LANTERN_HTTP_CORE_METHOD_CAP];
    char path[LANTERN_HTTP_CORE_PATH_CAP];
    int rc = parse_request_line(
        buffer,
        method,
        sizeof(method),
        path,
        sizeof(path));
    if (rc != 0)
    {
        int send_rc = lantern_http_send_json_error(
            client_fd,
            400,
            "Bad Request",
            server->config.malformed_json);
        if (send_rc == 0)
        {
            lantern_log_info(
                core_log_module(server),
                &(const struct lantern_log_metadata){.peer = peer_text},
                "malformed request -> 400");
        }
        else
        {
            lantern_log_error(
                core_log_module(server),
                &(const struct lantern_log_metadata){.peer = peer_text},
                "failed to send 400 response rc=%d",
                send_rc);
        }
        return;
    }

    const char *body = NULL;
    size_t body_len = 0;
    bool has_body = lantern_http_locate_body(buffer, (size_t)received, &body, &body_len);
    struct lantern_http_request request = {
        .client_fd = client_fd,
        .method = method,
        .path = path,
        .raw = buffer,
        .raw_len = (size_t)received,
        .body = body,
        .body_len = body_len,
        .has_body = has_body,
        .peer = peer_text,
    };

    for (size_t i = 0; i < server->config.route_count; ++i)
    {
        if (route_matches(&server->config.routes[i], method, path))
        {
            (void)server->config.routes[i].handler(server->config.context, &request);
            return;
        }
    }

    int send_rc = lantern_http_send_json_error(
        client_fd,
        404,
        "Not Found",
        server->config.unknown_json);
    if (send_rc == 0)
    {
        lantern_log_info(
            core_log_module(server),
            &(const struct lantern_log_metadata){.peer = peer_text},
            "%s %s -> 404",
            method,
            path);
    }
    else
    {
        lantern_log_error(
            core_log_module(server),
            &(const struct lantern_log_metadata){.peer = peer_text},
            "failed to send 404 response rc=%d",
            send_rc);
    }
}

static void *lantern_http_core_thread(void *arg)
{
    struct lantern_http_core_server *server = arg;
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
            if (!server->running || errno == EBADF || errno == EINVAL)
            {
                break;
            }
            if (errno == ECONNABORTED)
            {
                continue;
            }
            lantern_log_error(core_log_module(server), NULL, "accept failed errno=%d", errno);
            continue;
        }

        handle_client_connection(server, client_fd, &peer);
        close(client_fd);
    }
    return NULL;
}

void lantern_http_core_init(struct lantern_http_core_server *server)
{
    if (!server)
    {
        return;
    }
    memset(server, 0, sizeof(*server));
    server->listen_fd = -1;
}

int lantern_http_core_start(
    struct lantern_http_core_server *server,
    const struct lantern_http_core_config *config)
{
    if (!server || !config || (!config->routes && config->route_count != 0))
    {
        return LANTERN_HTTP_CORE_ERR_INVALID_PARAM;
    }

    struct lantern_http_core_config normalized = *config;
    fill_config_defaults(&normalized);

    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0)
    {
        lantern_log_error(normalized.log_module, NULL, "socket creation failed errno=%d", errno);
        return LANTERN_HTTP_CORE_ERR_IO;
    }

    int opt = 1;
    if (setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt)) != 0)
    {
        lantern_log_warn(normalized.log_module, NULL, "setsockopt(SO_REUSEADDR) failed errno=%d", errno);
    }

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_ANY);
    addr.sin_port = htons(normalized.port);

    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) != 0)
    {
        lantern_log_error(normalized.log_module, NULL, "bind failed errno=%d", errno);
        close(fd);
        return LANTERN_HTTP_CORE_ERR_IO;
    }
    if (listen(fd, LANTERN_HTTP_CORE_LISTEN_BACKLOG) != 0)
    {
        lantern_log_error(normalized.log_module, NULL, "listen failed errno=%d", errno);
        close(fd);
        return LANTERN_HTTP_CORE_ERR_IO;
    }

    server->listen_fd = fd;
    server->config = normalized;
    server->running = 1;
    server->thread_started = 0;

    uint16_t bound_port = normalized.port;
    if (bound_port == 0)
    {
        struct sockaddr_in bound_addr;
        socklen_t bound_len = sizeof(bound_addr);
        if (getsockname(fd, (struct sockaddr *)&bound_addr, &bound_len) == 0)
        {
            bound_port = ntohs(bound_addr.sin_port);
        }
    }

    int create_rc = pthread_create(&server->thread, NULL, lantern_http_core_thread, server);
    if (create_rc != 0)
    {
        lantern_log_error(normalized.log_module, NULL, "pthread_create failed rc=%d", create_rc);
        close(fd);
        server->listen_fd = -1;
        server->running = 0;
        return LANTERN_HTTP_CORE_ERR_IO;
    }

    server->thread_started = 1;
    lantern_log_info(
        normalized.log_module,
        NULL,
        "%s listening port=%" PRIu16,
        normalized.listen_label,
        bound_port);
    return LANTERN_HTTP_CORE_OK;
}

void lantern_http_core_stop(struct lantern_http_core_server *server)
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
