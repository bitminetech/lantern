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

#include <inttypes.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "lantern/support/log.h"
#include "lantern/support/strings.h"
#include "test_driver/driver.h"

static const size_t LANTERN_HTTP_MAX_TEST_DRIVER_BODY_SIZE = 64u * 1024u * 1024u;
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

/**
 * HTTP server module-specific error codes.
 */
enum
{
    LANTERN_HTTP_SERVER_ERR_INVALID_PARAM = -1,
    LANTERN_HTTP_SERVER_ERR_IO = -2,
};

static int send_unavailable(int fd) { return lantern_http_send_json_error(fd, 503, "Service Unavailable", LANTERN_HTTP_JSON_UNAVAILABLE); }
static int send_internal(int fd) { return lantern_http_send_json_error(fd, 500, "Internal Server Error", LANTERN_HTTP_JSON_INTERNAL); }
static int send_bad_request(int fd) { return lantern_http_send_json_error(fd, 400, "Bad Request", LANTERN_HTTP_JSON_BAD_REQUEST); }
static int send_method_not_allowed(int fd) { return lantern_http_send_json_error(fd, 405, "Method Not Allowed", LANTERN_HTTP_JSON_METHOD_NOT_ALLOWED); }


static int format_fork_choice_response(
    const struct lantern_fork_choice_tree_snapshot *snapshot,
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

    struct lantern_http_buffer buf;
    memset(&buf, 0, sizeof(buf));
    if (lantern_http_buffer_appendf(&buf, "{\"nodes\":[") != 0)
    {
        lantern_http_buffer_free(&buf);
        return -1;
    }

    for (size_t i = 0; i < snapshot->node_count; ++i)
    {
        const struct lantern_fork_choice_tree_node *node = &snapshot->nodes[i];
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
            lantern_http_buffer_free(&buf);
            return -1;
        }

        if (lantern_http_buffer_appendf(
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
            lantern_http_buffer_free(&buf);
            return -1;
        }
    }

    if (lantern_http_buffer_appendf(
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
        lantern_http_buffer_free(&buf);
        return -1;
    }

    *out_body = buf.data;
    *out_len = buf.len;
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
static int handle_admin_aggregator(
    void *context,
    const struct lantern_http_request *request)
{
    struct lantern_http_server *server = context;
    if (!server || !request)
    {
        return LANTERN_HTTP_SERVER_ERR_INVALID_PARAM;
    }
    int client_fd = request->client_fd;
    const char *method = request->method;
    const char *peer_text = request->peer;
    const bool is_get = (strcmp(method, "GET") == 0);
    const bool is_post = (strcmp(method, "POST") == 0);
    if (!is_get && !is_post)
    {
        int rc = send_method_not_allowed(client_fd);
        lantern_log_info(
            "http",
            &(const struct lantern_log_metadata){.peer = peer_text},
            "%s %s -> 405 (rc=%d)",
            method,
            LANTERN_HTTP_PATH_ADMIN_AGGREGATOR,
            rc);
        return 0;
    }

    if (is_get)
    {
        if (!server->callbacks.get_is_aggregator)
        {
            int rc = send_unavailable(client_fd);
            lantern_log_info(
                "http",
                &(const struct lantern_log_metadata){.peer = peer_text},
                "GET %s -> 503 (rc=%d)",
                LANTERN_HTTP_PATH_ADMIN_AGGREGATOR,
                rc);
            return 0;
        }
        bool enabled = false;
        int cb_rc = server->callbacks.get_is_aggregator(server->callbacks.context, &enabled);
        if (cb_rc != LANTERN_HTTP_CB_OK)
        {
            int rc = send_unavailable(client_fd);
            lantern_log_info(
                "http",
                &(const struct lantern_log_metadata){.peer = peer_text},
                "GET %s -> 503 (cb_rc=%d rc=%d)",
                LANTERN_HTTP_PATH_ADMIN_AGGREGATOR,
                cb_rc,
                rc);
            return 0;
        }
        char body[64];
        int body_len = snprintf(
            body,
            sizeof(body),
            "{\"is_aggregator\":%s}",
            enabled ? "true" : "false");
        if (body_len <= 0 || (size_t)body_len >= sizeof(body))
        {
            send_internal(client_fd);
            return 0;
        }
        int rc = lantern_http_send_response(client_fd, 200, "OK", "application/json", body, (size_t)body_len);
        lantern_log_info(
            "http",
            &(const struct lantern_log_metadata){.peer = peer_text},
            "GET %s -> 200 (rc=%d)",
            LANTERN_HTTP_PATH_ADMIN_AGGREGATOR,
            rc);
        return 0;
    }

    /* POST */
    if (!server->callbacks.set_is_aggregator)
    {
        int rc = send_unavailable(client_fd);
        lantern_log_info(
            "http",
            &(const struct lantern_log_metadata){.peer = peer_text},
            "POST %s -> 503 (rc=%d)",
            LANTERN_HTTP_PATH_ADMIN_AGGREGATOR,
            rc);
        return 0;
    }
    if (!request->has_body || request->body_len == 0)
    {
        int rc = send_bad_request(client_fd);
        lantern_log_info(
            "http",
            &(const struct lantern_log_metadata){.peer = peer_text},
            "POST %s -> 400 (empty body, rc=%d)",
            LANTERN_HTTP_PATH_ADMIN_AGGREGATOR,
            rc);
        return 0;
    }
    bool enabled = false;
    if (parse_enabled_bool_body(request->body, request->body_len, &enabled) != 0)
    {
        int rc = send_bad_request(client_fd);
        lantern_log_info(
            "http",
            &(const struct lantern_log_metadata){.peer = peer_text},
            "POST %s -> 400 (bad body, rc=%d)",
            LANTERN_HTTP_PATH_ADMIN_AGGREGATOR,
            rc);
        return 0;
    }
    bool previous = false;
    int cb_rc = server->callbacks.set_is_aggregator(server->callbacks.context, enabled, &previous);
    if (cb_rc != LANTERN_HTTP_CB_OK)
    {
        int rc = send_unavailable(client_fd);
        lantern_log_info(
            "http",
            &(const struct lantern_log_metadata){.peer = peer_text},
            "POST %s -> 503 (cb_rc=%d rc=%d)",
            LANTERN_HTTP_PATH_ADMIN_AGGREGATOR,
            cb_rc,
            rc);
        return 0;
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
        send_internal(client_fd);
        return 0;
    }
    int rc = lantern_http_send_response(client_fd, 200, "OK", "application/json", resp, (size_t)resp_len);
    lantern_log_info(
        "http",
        &(const struct lantern_log_metadata){.peer = peer_text},
        "POST %s -> 200 enabled=%s previous=%s (rc=%d)",
        LANTERN_HTTP_PATH_ADMIN_AGGREGATOR,
        enabled ? "true" : "false",
        previous ? "true" : "false",
        rc);
    return 0;
}

static int handle_test_driver(
    void *context,
    const struct lantern_http_request *request)
{
    (void)context;
    if (!request)
    {
        return LANTERN_HTTP_SERVER_ERR_INVALID_PARAM;
    }
    int client_fd = request->client_fd;
    const char *method = request->method;
    const char *path = request->path;
    const char *peer_text = request->peer;
    if (strcmp(method, "POST") != 0)
    {
        int rc = send_method_not_allowed(client_fd);
        lantern_log_info(
            "http",
            &(const struct lantern_log_metadata){.peer = peer_text},
            "%s %s -> 405 (rc=%d)",
            method,
            path,
            rc);
        return 0;
    }

    char *request_body = NULL;
    size_t request_body_len = 0;
    if (lantern_http_request_read_body(
            request,
            LANTERN_HTTP_MAX_TEST_DRIVER_BODY_SIZE,
            &request_body,
            &request_body_len)
        != 0)
    {
        int rc = send_bad_request(client_fd);
        lantern_log_info(
            "http",
            &(const struct lantern_log_metadata){.peer = peer_text},
            "POST %s -> 400 (body read failed, rc=%d)",
            path,
            rc);
        return 0;
    }

    if (strcmp(path, LANTERN_HTTP_PATH_TEST_FC_INIT) == 0)
    {
        char *error = NULL;
        int driver_rc =
            lantern_test_driver_fork_choice_init(request_body, request_body_len, &error);
        free(request_body);
        if (driver_rc != 0)
        {
            int rc = send_bad_request(client_fd);
            lantern_log_info(
                "http",
                &(const struct lantern_log_metadata){.peer = peer_text},
                "POST %s -> 400 (driver_rc=%d error=%s rc=%d)",
                path,
                driver_rc,
                error ? error : "-",
                rc);
            free(error);
            return 0;
        }
        int rc = lantern_http_send_response(client_fd, 204, "No Content", "application/json", NULL, 0);
        lantern_log_info(
            "http",
            &(const struct lantern_log_metadata){.peer = peer_text},
            "POST %s -> 204 (rc=%d)",
            path,
            rc);
        return 0;
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
        int rc = send_internal(client_fd);
        lantern_log_error(
            "http",
            &(const struct lantern_log_metadata){.peer = peer_text},
            "POST %s -> 500 (driver_rc=%d rc=%d)",
            path,
            driver_rc,
            rc);
        return 0;
    }

    int rc = lantern_http_send_response(
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
    return 0;
}


static int handle_health(
    void *context,
    const struct lantern_http_request *request)
{
    (void)context;
    int rc = lantern_http_send_response(
        request->client_fd,
        200,
        "OK",
        "application/json",
        LANTERN_HTTP_JSON_HEALTH,
        strlen(LANTERN_HTTP_JSON_HEALTH));
    if (rc == 0)
    {
        lantern_log_info(
            "http",
            &(const struct lantern_log_metadata){.peer = request->peer},
            "GET %s -> 200",
            request->path);
    }
    else
    {
        lantern_log_error(
            "http",
            &(const struct lantern_log_metadata){.peer = request->peer},
            "failed to send health response rc=%d",
            rc);
    }
    return rc;
}

static int handle_metrics(
    void *context,
    const struct lantern_http_request *request)
{
    struct lantern_http_server *server = context;
    return lantern_metrics_handle_http(&server->metrics_handler, request);
}

static int send_finalized_error(
    const struct lantern_http_request *request,
    int callback_rc,
    const char *kind,
    const char *missing_body)
{
    const char *body = LANTERN_HTTP_JSON_INTERNAL;
    int status_code = 500;
    const char *status_text = "Internal Server Error";
    if (callback_rc == LANTERN_HTTP_CB_ERR_NOT_FOUND)
    {
        body = missing_body;
        status_code = 404;
        status_text = "Not Found";
    }
    else if (callback_rc == LANTERN_HTTP_CB_ERR_INVALID_STATE
        || callback_rc == LANTERN_HTTP_CB_ERR_LOCK_FAILED
        || callback_rc == LANTERN_HTTP_CB_ERR_UNAVAILABLE)
    {
        body = LANTERN_HTTP_JSON_UNAVAILABLE;
        status_code = 503;
        status_text = "Service Unavailable";
    }

    int rc = lantern_http_send_json_error(request->client_fd, status_code, status_text, body);
    if (callback_rc == LANTERN_HTTP_CB_ERR_NOT_FOUND)
    {
        lantern_log_info(
            "http",
            &(const struct lantern_log_metadata){.peer = request->peer},
            "finalized %s missing -> 404",
            kind);
    }
    else if (callback_rc == LANTERN_HTTP_CB_ERR_INVALID_STATE
        || callback_rc == LANTERN_HTTP_CB_ERR_LOCK_FAILED
        || callback_rc == LANTERN_HTTP_CB_ERR_UNAVAILABLE)
    {
        lantern_log_warn(
            "http",
            &(const struct lantern_log_metadata){.peer = request->peer},
            "finalized %s unavailable rc=%d send_rc=%d",
            kind,
            callback_rc,
            rc);
    }
    else
    {
        lantern_log_error(
            "http",
            &(const struct lantern_log_metadata){.peer = request->peer},
            "finalized %s failed rc=%d send_rc=%d",
            kind,
            callback_rc,
            rc);
    }
    return rc;
}

static int send_finalized_bytes(
    const struct lantern_http_request *request,
    uint8_t *bytes,
    size_t len,
    const char *kind)
{
    if (!bytes || len == 0)
    {
        free(bytes);
        int rc = send_internal(request->client_fd);
        lantern_log_error(
            "http",
            &(const struct lantern_log_metadata){.peer = request->peer},
            "finalized %s empty send_rc=%d",
            kind,
            rc);
        return rc;
    }

    int rc = lantern_http_send_response(
        request->client_fd,
        200,
        "OK",
        "application/octet-stream",
        (const char *)bytes,
        len);
    free(bytes);
    if (rc != 0)
    {
        lantern_log_error(
            "http",
            &(const struct lantern_log_metadata){.peer = request->peer},
            "finalized %s send failed rc=%d",
            kind,
            rc);
        return rc;
    }

    lantern_log_info(
        "http",
        &(const struct lantern_log_metadata){.peer = request->peer},
        "GET %s -> 200",
        request->path);
    return 0;
}

static int handle_finalized_ssz(
    struct lantern_http_server *server,
    const struct lantern_http_request *request,
    int (*callback)(void *context, uint8_t **out_bytes, size_t *out_len),
    const char *kind,
    const char *missing_body)
{
    if (!callback)
    {
        int rc = send_unavailable(request->client_fd);
        lantern_log_error(
            "http",
            &(const struct lantern_log_metadata){.peer = request->peer},
            "finalized %s callback missing rc=%d",
            kind,
            rc);
        return rc;
    }

    uint8_t *bytes = NULL;
    size_t len = 0;
    int callback_rc = callback(server->callbacks.context, &bytes, &len);
    if (callback_rc != 0)
    {
        free(bytes);
        return send_finalized_error(
            request,
            callback_rc,
            kind,
            missing_body);
    }
    return send_finalized_bytes(
        request,
        bytes,
        len,
        kind);
}

static int handle_finalized_state(
    void *context,
    const struct lantern_http_request *request)
{
    struct lantern_http_server *server = context;
    return handle_finalized_ssz(
        server,
        request,
        server->callbacks.finalized_state_ssz,
        "state",
        LANTERN_HTTP_JSON_STATE_MISSING);
}

static int handle_finalized_block(
    void *context,
    const struct lantern_http_request *request)
{
    struct lantern_http_server *server = context;
    return handle_finalized_ssz(
        server,
        request,
        server->callbacks.finalized_block_ssz,
        "block",
        LANTERN_HTTP_JSON_BLOCK_MISSING);
}

static int send_snapshot_error(
    const struct lantern_http_request *request,
    int callback_rc,
    const char *unavailable_log,
    const char *failed_log)
{
    const char *body = LANTERN_HTTP_JSON_INTERNAL;
    int status_code = 500;
    const char *status_text = "Internal Server Error";
    if (callback_rc == LANTERN_HTTP_CB_ERR_INVALID_STATE
        || callback_rc == LANTERN_HTTP_CB_ERR_LOCK_FAILED
        || callback_rc == LANTERN_HTTP_CB_ERR_UNAVAILABLE)
    {
        body = LANTERN_HTTP_JSON_UNAVAILABLE;
        status_code = 503;
        status_text = "Service Unavailable";
    }

    int rc = lantern_http_send_json_error(request->client_fd, status_code, status_text, body);
    if (status_code == 503)
    {
        lantern_log_warn(
            "http",
            &(const struct lantern_log_metadata){.peer = request->peer},
            "%s rc=%d send_rc=%d",
            unavailable_log,
            callback_rc,
            rc);
    }
    else
    {
        lantern_log_error(
            "http",
            &(const struct lantern_log_metadata){.peer = request->peer},
            "%s rc=%d send_rc=%d",
            failed_log,
            callback_rc,
            rc);
    }
    return rc;
}

static int handle_justified(
    void *context,
    const struct lantern_http_request *request)
{
    struct lantern_http_server *server = context;
    if (!server->callbacks.snapshot_justified)
    {
        int rc = send_unavailable(request->client_fd);
        lantern_log_error(
            "http",
            &(const struct lantern_log_metadata){.peer = request->peer},
            "justified snapshot callback missing rc=%d",
            rc);
        return rc;
    }

    LanternCheckpoint justified;
    memset(&justified, 0, sizeof(justified));
    int snapshot_rc = server->callbacks.snapshot_justified(
        server->callbacks.context,
        &justified);
    if (snapshot_rc != 0)
    {
        return send_snapshot_error(
            request,
            snapshot_rc,
            "justified snapshot unavailable",
            "justified snapshot failed");
    }

    char root_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    if (lantern_bytes_to_hex(
            justified.root.bytes,
            LANTERN_ROOT_SIZE,
            root_hex,
            sizeof(root_hex),
            1)
        != 0)
    {
        int rc = send_internal(request->client_fd);
        lantern_log_error(
            "http",
            &(const struct lantern_log_metadata){.peer = request->peer},
            "justified root hex failed send_rc=%d",
            rc);
        return rc;
    }

    char body[256];
    int body_written = snprintf(
        body,
        sizeof(body),
        "{\"slot\":%" PRIu64 ",\"root\":\"%s\"}",
        justified.slot,
        root_hex);
    if (body_written < 0 || (size_t)body_written >= sizeof(body))
    {
        int rc = send_internal(request->client_fd);
        lantern_log_error(
            "http",
            &(const struct lantern_log_metadata){.peer = request->peer},
            "justified response format failed send_rc=%d",
            rc);
        return rc;
    }

    int rc = lantern_http_send_response(
        request->client_fd,
        200,
        "OK",
        "application/json",
        body,
        (size_t)body_written);
    if (rc != 0)
    {
        lantern_log_error(
            "http",
            &(const struct lantern_log_metadata){.peer = request->peer},
            "justified response send failed rc=%d",
            rc);
        return rc;
    }

    lantern_log_info(
        "http",
        &(const struct lantern_log_metadata){.peer = request->peer},
        "GET %s -> 200",
        request->path);
    return 0;
}

static int handle_fork_choice(
    void *context,
    const struct lantern_http_request *request)
{
    struct lantern_http_server *server = context;
    if (!server->callbacks.snapshot_fork_choice)
    {
        int rc = send_unavailable(request->client_fd);
        lantern_log_error(
            "http",
            &(const struct lantern_log_metadata){.peer = request->peer},
            "fork choice snapshot callback missing rc=%d",
            rc);
        return rc;
    }

    struct lantern_fork_choice_tree_snapshot snapshot;
    memset(&snapshot, 0, sizeof(snapshot));
    int snapshot_rc = server->callbacks.snapshot_fork_choice(server->callbacks.context, &snapshot);
    if (snapshot_rc != 0)
    {
        return send_snapshot_error(
            request,
            snapshot_rc,
            "fork choice snapshot unavailable",
            "fork choice snapshot failed");
    }

    char *body = NULL;
    size_t body_len = 0;
    int result = format_fork_choice_response(&snapshot, &body, &body_len);
    lantern_fork_choice_tree_snapshot_reset(&snapshot);
    if (result != 0)
    {
        int rc = send_internal(request->client_fd);
        lantern_log_error(
            "http",
            &(const struct lantern_log_metadata){.peer = request->peer},
            "fork choice response format failed send_rc=%d",
            rc);
        return rc;
    }

    result = lantern_http_send_response(
        request->client_fd,
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
            &(const struct lantern_log_metadata){.peer = request->peer},
            "fork choice response send failed rc=%d",
            result);
        return result;
    }

    lantern_log_info(
        "http",
        &(const struct lantern_log_metadata){.peer = request->peer},
        "GET %s -> 200",
        request->path);
    return 0;
}

static const struct lantern_http_route kHttpRoutes[] = {
    {NULL, LANTERN_HTTP_PATH_ADMIN_AGGREGATOR, handle_admin_aggregator},
    {NULL, LANTERN_HTTP_PATH_TEST_FC_INIT, handle_test_driver},
    {NULL, LANTERN_HTTP_PATH_TEST_FC_STEP, handle_test_driver},
    {NULL, LANTERN_HTTP_PATH_TEST_STATE_RUN, handle_test_driver},
    {NULL, LANTERN_HTTP_PATH_TEST_VERIFY_RUN, handle_test_driver},
    {"GET", LANTERN_HTTP_PATH_HEALTH, handle_health},
    {"GET", LANTERN_HTTP_PATH_METRICS, handle_metrics},
    {"GET", LANTERN_HTTP_PATH_FINALIZED, handle_finalized_state},
    {"GET", LANTERN_HTTP_PATH_FINALIZED_BLOCK, handle_finalized_block},
    {"GET", LANTERN_HTTP_PATH_JUSTIFIED, handle_justified},
    {"GET", LANTERN_HTTP_PATH_FORK_CHOICE, handle_fork_choice},
};


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
    lantern_http_core_init(&server->core);
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

    server->callbacks = config->callbacks;
    server->metrics_handler.callbacks.context = server->callbacks.context;
    server->metrics_handler.callbacks.snapshot = server->callbacks.metrics_snapshot;
    server->metrics_handler.log_module = "http";
    server->metrics_handler.unavailable_json = LANTERN_HTTP_JSON_UNAVAILABLE;
    server->metrics_handler.formatting_failed_json = LANTERN_HTTP_JSON_INTERNAL;

    struct lantern_http_core_config core_config;
    memset(&core_config, 0, sizeof(core_config));
    core_config.port = config->port;
    core_config.log_module = "http";
    core_config.listen_label = "http server";
    core_config.malformed_json = LANTERN_HTTP_JSON_MALFORMED;
    core_config.unknown_json = LANTERN_HTTP_JSON_UNKNOWN_ENDPOINT;
    core_config.context = server;
    core_config.routes = kHttpRoutes;
    core_config.route_count = sizeof(kHttpRoutes) / sizeof(kHttpRoutes[0]);

    int rc = lantern_http_core_start(&server->core, &core_config);
    if (rc != 0)
    {
        if (rc == LANTERN_HTTP_CORE_ERR_INVALID_PARAM)
        {
            return LANTERN_HTTP_SERVER_ERR_INVALID_PARAM;
        }
        return LANTERN_HTTP_SERVER_ERR_IO;
    }
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

    lantern_http_core_stop(&server->core);
}
