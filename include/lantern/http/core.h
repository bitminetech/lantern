#ifndef LANTERN_HTTP_CORE_H
#define LANTERN_HTTP_CORE_H

#include <pthread.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

struct event_base;
struct evhttp;
struct evhttp_request;

enum
{
    LANTERN_HTTP_CORE_OK = 0,
    LANTERN_HTTP_CORE_ERR_INVALID_PARAM = -1,
    LANTERN_HTTP_CORE_ERR_OUT_OF_MEMORY = -2,
    LANTERN_HTTP_CORE_ERR_IO = -3,
};

struct lantern_http_request {
    struct evhttp_request *transport;
    const char *method;
    const char *path;
    const char *body;
    size_t body_len;
    const char *peer;
};

typedef int (*lantern_http_route_handler)(
    void *context,
    const struct lantern_http_request *request);

struct lantern_http_route {
    const char *method;
    const char *path;
    lantern_http_route_handler handler;
};

struct lantern_http_core_config {
    uint16_t port;
    const char *log_module;
    const char *listen_label;
    const char *unknown_json;
    void *context;
    const struct lantern_http_route *routes;
    size_t route_count;
};

struct lantern_http_core_server {
    int listen_fd;
    pthread_t thread;
    int thread_started;
    struct event_base *event_base;
    struct evhttp *http;
    struct lantern_http_core_config config;
};

void lantern_http_core_init(struct lantern_http_core_server *server);
int lantern_http_core_start(
    struct lantern_http_core_server *server,
    const struct lantern_http_core_config *config);
void lantern_http_core_stop(struct lantern_http_core_server *server);

int lantern_http_send_response(
    const struct lantern_http_request *request,
    int status_code,
    const char *status_text,
    const char *content_type,
    const char *body,
    size_t body_len);
int lantern_http_send_json_error(
    const struct lantern_http_request *request,
    int status_code,
    const char *status_text,
    const char *json_body);

#ifdef __cplusplus
}
#endif

#endif /* LANTERN_HTTP_CORE_H */
