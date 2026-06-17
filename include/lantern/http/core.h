#ifndef LANTERN_HTTP_CORE_H
#define LANTERN_HTTP_CORE_H

#include <pthread.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define LANTERN_HTTP_CORE_METHOD_CAP 8u
#define LANTERN_HTTP_CORE_PATH_CAP 256u
#define LANTERN_HTTP_CORE_METRICS_PATH_CAP 128u
#define LANTERN_HTTP_CORE_READ_BUFFER_SIZE 4096u
#define LANTERN_HTTP_CORE_LISTEN_BACKLOG 16

enum
{
    LANTERN_HTTP_CORE_OK = 0,
    LANTERN_HTTP_CORE_ERR_INVALID_PARAM = -1,
    LANTERN_HTTP_CORE_ERR_OUT_OF_MEMORY = -2,
    LANTERN_HTTP_CORE_ERR_OVERFLOW = -3,
    LANTERN_HTTP_CORE_ERR_IO = -4,
    LANTERN_HTTP_CORE_ERR_FORMATTING = -5,
    LANTERN_HTTP_CORE_ERR_MALFORMED_REQUEST = -6,
};

struct lantern_http_buffer {
    char *data;
    size_t len;
    size_t cap;
};

struct lantern_http_request {
    int client_fd;
    const char *method;
    const char *path;
    const char *raw;
    size_t raw_len;
    const char *body;
    size_t body_len;
    bool has_body;
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
    const char *malformed_json;
    const char *unknown_json;
    size_t method_cap;
    size_t path_cap;
    int listen_backlog;
    bool capture_bound_port;
    void *context;
    const struct lantern_http_route *routes;
    size_t route_count;
};

struct lantern_http_core_server {
    int listen_fd;
    pthread_t thread;
    int running;
    int thread_started;
    uint16_t port;
    struct lantern_http_core_config config;
};

void lantern_http_core_init(struct lantern_http_core_server *server);
int lantern_http_core_start(
    struct lantern_http_core_server *server,
    const struct lantern_http_core_config *config);
void lantern_http_core_stop(struct lantern_http_core_server *server);

int lantern_http_send_all(int fd, const char *data, size_t length);
int lantern_http_send_response(
    int fd,
    int status_code,
    const char *status_text,
    const char *content_type,
    const char *body,
    size_t body_len);
int lantern_http_send_json_error(
    int fd,
    int status_code,
    const char *status_text,
    const char *json_body);

int lantern_http_buffer_init(struct lantern_http_buffer *buf, size_t initial_cap);
void lantern_http_buffer_free(struct lantern_http_buffer *buf);
int lantern_http_buffer_reserve(struct lantern_http_buffer *buf, size_t extra);
int lantern_http_buffer_appendf(struct lantern_http_buffer *buf, const char *fmt, ...);

int lantern_http_request_read_body(
    const struct lantern_http_request *request,
    size_t max_body_size,
    char **out_body,
    size_t *out_body_len);

#ifdef __cplusplus
}
#endif

#endif /* LANTERN_HTTP_CORE_H */
