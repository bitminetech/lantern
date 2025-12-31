/**
 * @file server.c
 * @brief Lean API HTTP server (disabled stub).
 *
 * The HTTP API is intentionally disabled. The CLI flags remain accepted, but
 * the server does not start. This file provides no-op stubs to satisfy the
 * public API while removing the server implementation.
 */

#include "lantern/http/server.h"

#include <string.h>

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

void lantern_http_server_reset(struct lantern_http_server *server)
{
    if (!server)
    {
        return;
    }

    lantern_http_server_stop(server);
    lantern_http_server_init(server);
}

int lantern_http_server_start(
    struct lantern_http_server *server,
    const struct lantern_http_server_config *config)
{
    if (!server || !config)
    {
        return -1;
    }

    server->listen_fd = -1;
    server->running = 0;
    server->thread_started = 0;
    server->port = 0;
    return -1;
}

void lantern_http_server_stop(struct lantern_http_server *server)
{
    if (!server)
    {
        return;
    }

    server->running = 0;
    server->listen_fd = -1;
    server->thread_started = 0;
    server->port = 0;
}
