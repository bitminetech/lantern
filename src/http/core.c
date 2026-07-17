#include "lantern/http/core.h"

#include <arpa/inet.h>
#include <inttypes.h>
#include <netinet/in.h>
#include <string.h>
#include <sys/socket.h>

#include <event2/buffer.h>
#include <event2/event.h>
#include <event2/http.h>
#include <event2/thread.h>

#include "lantern/support/log.h"

static const ev_ssize_t HTTP_MAX_HEADERS_SIZE = 64u * 1024u;
static const ev_ssize_t HTTP_MAX_BODY_SIZE = 64u * 1024u * 1024u;
static const int HTTP_STATUS_CODE_MIN = 100;
static const int HTTP_STATUS_CODE_MAX = 999;
static const char DEFAULT_UNKNOWN_JSON[] = "{\"error\":\"unknown endpoint\"}";

static pthread_once_t event_threads_once = PTHREAD_ONCE_INIT;
static int event_threads_ready;

static void initialize_event_threads(void)
{
    event_threads_ready = evthread_use_pthreads() == 0;
}

static const char *core_log_module(const struct lantern_http_core_server *server)
{
    return server && server->config.log_module ? server->config.log_module : "http";
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
    if (!config->unknown_json)
    {
        config->unknown_json = DEFAULT_UNKNOWN_JSON;
    }
}

static const char *http_method(enum evhttp_cmd_type command)
{
    switch (command)
    {
    case EVHTTP_REQ_GET:
        return "GET";
    case EVHTTP_REQ_POST:
        return "POST";
    case EVHTTP_REQ_HEAD:
        return "HEAD";
    case EVHTTP_REQ_PUT:
        return "PUT";
    case EVHTTP_REQ_DELETE:
        return "DELETE";
    case EVHTTP_REQ_OPTIONS:
        return "OPTIONS";
    case EVHTTP_REQ_TRACE:
        return "TRACE";
    case EVHTTP_REQ_CONNECT:
        return "CONNECT";
    case EVHTTP_REQ_PATCH:
        return "PATCH";
    default:
        return "UNKNOWN";
    }
}

static int route_matches(
    const struct lantern_http_route *route,
    const char *method,
    const char *path)
{
    return route && route->path && route->handler
        && strcmp(route->path, path) == 0
        && (!route->method || strcmp(route->method, method) == 0);
}

int lantern_http_send_response(
    const struct lantern_http_request *request,
    int status_code,
    const char *status_text,
    const char *content_type,
    const char *body,
    size_t body_len)
{
    if (!request || !request->transport
        || status_code < HTTP_STATUS_CODE_MIN
        || status_code > HTTP_STATUS_CODE_MAX
        || (!body && body_len != 0u))
    {
        return LANTERN_HTTP_CORE_ERR_INVALID_PARAM;
    }
    struct evbuffer *buffer = evbuffer_new();
    struct evkeyvalq *headers = evhttp_request_get_output_headers(request->transport);
    if (!buffer || !headers
        || evhttp_add_header(
               headers,
               "Content-Type",
               content_type ? content_type : "application/json")
            != 0
        || evhttp_add_header(headers, "Connection", "close") != 0
        || (body_len > 0u && evbuffer_add(buffer, body, body_len) != 0))
    {
        if (buffer)
        {
            evbuffer_free(buffer);
        }
        return LANTERN_HTTP_CORE_ERR_OUT_OF_MEMORY;
    }
    evhttp_send_reply(
        request->transport,
        status_code,
        status_text ? status_text : "OK",
        buffer);
    evbuffer_free(buffer);
    return LANTERN_HTTP_CORE_OK;
}

int lantern_http_send_json_error(
    const struct lantern_http_request *request,
    int status_code,
    const char *status_text,
    const char *json_body)
{
    return lantern_http_send_response(
        request,
        status_code,
        status_text,
        "application/json",
        json_body,
        json_body ? strlen(json_body) : 0u);
}

static void handle_http_request(struct evhttp_request *transport, void *context)
{
    struct lantern_http_core_server *server = context;
    const struct evhttp_uri *uri = evhttp_request_get_evhttp_uri(transport);
    const char *path = uri ? evhttp_uri_get_path(uri) : NULL;
    const char *method = http_method(evhttp_request_get_command(transport));
    struct evbuffer *input = evhttp_request_get_input_buffer(transport);
    size_t body_len = input ? evbuffer_get_length(input) : 0u;
    const char *body = body_len > 0u
        ? (const char *)evbuffer_pullup(input, -1)
        : NULL;
    char *peer = NULL;
    ev_uint16_t peer_port = 0u;
    struct evhttp_connection *connection = evhttp_request_get_connection(transport);
    if (connection)
    {
        evhttp_connection_get_peer(connection, &peer, &peer_port);
    }
    (void)peer_port;
    struct lantern_http_request request = {
        .transport = transport,
        .method = method,
        .path = path ? path : "",
        .body = body,
        .body_len = body_len,
        .peer = peer ? peer : "unknown",
    };
    if (!server || !path || (body_len > 0u && !body))
    {
        evhttp_send_error(transport, 400, "Bad Request");
        return;
    }
    for (size_t i = 0; i < server->config.route_count; ++i)
    {
        if (route_matches(&server->config.routes[i], method, path))
        {
            (void)server->config.routes[i].handler(server->config.context, &request);
            return;
        }
    }
    int result = lantern_http_send_json_error(
        &request,
        404,
        "Not Found",
        server->config.unknown_json);
    lantern_log_info(
        core_log_module(server),
        &(const struct lantern_log_metadata){.peer = request.peer},
        "%s %s -> 404 (rc=%d)",
        method,
        path,
        result);
}

static void *http_server_thread(void *context)
{
    struct lantern_http_core_server *server = context;
    int result = event_base_dispatch(server->event_base);
    if (result < 0)
    {
        lantern_log_error(core_log_module(server), NULL, "HTTP event loop failed");
    }
    return NULL;
}

static void release_transport(struct lantern_http_core_server *server)
{
    if (server->http)
    {
        evhttp_free(server->http);
        server->http = NULL;
    }
    if (server->event_base)
    {
        event_base_free(server->event_base);
        server->event_base = NULL;
    }
    server->listen_fd = -1;
}

void lantern_http_core_init(struct lantern_http_core_server *server)
{
    if (server)
    {
        memset(server, 0, sizeof(*server));
        server->listen_fd = -1;
    }
}

int lantern_http_core_start(
    struct lantern_http_core_server *server,
    const struct lantern_http_core_config *config)
{
    if (!server || !config || server->http || server->thread_started
        || (!config->routes && config->route_count != 0u))
    {
        return LANTERN_HTTP_CORE_ERR_INVALID_PARAM;
    }
    struct lantern_http_core_config normalized = *config;
    fill_config_defaults(&normalized);
    pthread_once(&event_threads_once, initialize_event_threads);
    if (!event_threads_ready)
    {
        return LANTERN_HTTP_CORE_ERR_IO;
    }
    server->event_base = event_base_new();
    server->http = server->event_base ? evhttp_new(server->event_base) : NULL;
    if (!server->http)
    {
        release_transport(server);
        return LANTERN_HTTP_CORE_ERR_OUT_OF_MEMORY;
    }
    evhttp_set_max_headers_size(server->http, HTTP_MAX_HEADERS_SIZE);
    evhttp_set_max_body_size(server->http, HTTP_MAX_BODY_SIZE);
    evhttp_set_default_content_type(server->http, NULL);
    evhttp_set_allowed_methods(server->http, UINT16_MAX);
    evhttp_set_gencb(server->http, handle_http_request, server);
    struct evhttp_bound_socket *socket = evhttp_bind_socket_with_handle(
        server->http,
        "0.0.0.0",
        normalized.port);
    if (!socket)
    {
        lantern_log_error(normalized.log_module, NULL, "HTTP bind failed port=%" PRIu16, normalized.port);
        release_transport(server);
        return LANTERN_HTTP_CORE_ERR_IO;
    }
    server->listen_fd = (int)evhttp_bound_socket_get_fd(socket);
    server->config = normalized;
    uint16_t bound_port = normalized.port;
    if (bound_port == 0u)
    {
        struct sockaddr_in address;
        socklen_t length = sizeof(address);
        if (getsockname(server->listen_fd, (struct sockaddr *)&address, &length) == 0)
        {
            bound_port = ntohs(address.sin_port);
        }
    }
    int result = pthread_create(&server->thread, NULL, http_server_thread, server);
    if (result != 0)
    {
        release_transport(server);
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
    if (server->thread_started)
    {
        (void)event_base_loopbreak(server->event_base);
        pthread_join(server->thread, NULL);
        server->thread_started = 0;
    }
    release_transport(server);
    server->config = (struct lantern_http_core_config){0};
}
