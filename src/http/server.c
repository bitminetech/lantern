/**
 * @file server.c
 * @brief Lean API HTTP server for checkpoint sync and health/metrics endpoints.
 *
 * Exposes endpoints:
 * - GET /lean/v0/states/finalized  (SSZ state snapshot)
 * - GET /lean/v0/checkpoints/justified  (JSON justified checkpoint)
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
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>

#include "lantern/http/common.h"
#include "lantern/http/metrics.h"
#include "lantern/support/log.h"
#include "lantern/support/strings.h"

static const size_t LANTERN_HTTP_READ_BUFFER_SIZE = 4096;
static const int LANTERN_HTTP_LISTEN_BACKLOG = 16;
static const char LANTERN_HTTP_PATH_HEALTH[] = "/lean/v0/health";
static const char LANTERN_HTTP_PATH_METRICS[] = "/metrics";
static const char LANTERN_HTTP_PATH_FINALIZED[] = "/lean/v0/states/finalized";
static const char LANTERN_HTTP_PATH_JUSTIFIED[] = "/lean/v0/checkpoints/justified";
static const char LANTERN_HTTP_JSON_HEALTH[] = "{\"status\":\"healthy\",\"service\":\"lean-spec-api\"}";
static const char LANTERN_HTTP_JSON_MALFORMED[] = "{\"error\":\"malformed request\"}";
static const char LANTERN_HTTP_JSON_UNKNOWN_ENDPOINT[] = "{\"error\":\"unknown endpoint\"}";
static const char LANTERN_HTTP_JSON_UNAVAILABLE[] = "{\"error\":\"service unavailable\"}";
static const char LANTERN_HTTP_JSON_STATE_MISSING[] = "{\"error\":\"finalized state not available\"}";
static const char LANTERN_HTTP_JSON_INTERNAL[] = "{\"error\":\"internal error\"}";

enum
{
    LANTERN_HTTP_METHOD_CAP = 8,
    LANTERN_HTTP_PATH_CAP = 256,
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

        char root_hex[(LANTERN_ROOT_SIZE * 2u) + 1u];
        if (lantern_bytes_to_hex(
                snapshot.justified.root.bytes,
                LANTERN_ROOT_SIZE,
                root_hex,
                sizeof(root_hex),
                0)
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
