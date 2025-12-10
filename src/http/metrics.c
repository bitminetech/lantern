#include "lantern/http/metrics.h"

#include "lantern/http/common.h"
#include "lantern/support/log.h"

#include <arpa/inet.h>
#include <errno.h>
#include <inttypes.h>
#include <netinet/in.h>
#include <pthread.h>
#include <stdio.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>

#define LANTERN_METRICS_BUFFER_SIZE 4096

struct metrics_buffer {
    char *data;
    size_t len;
    size_t cap;
};

static int metrics_buffer_init(struct metrics_buffer *buf, size_t initial_cap) {
    if (!buf) {
        return -1;
    }
    size_t capacity = initial_cap ? initial_cap : 1024;
    buf->data = malloc(capacity);
    if (!buf->data) {
        return -1;
    }
    buf->len = 0;
    buf->cap = capacity;
    buf->data[0] = '\0';
    return 0;
}

static void metrics_buffer_free(struct metrics_buffer *buf) {
    if (!buf) {
        return;
    }
    free(buf->data);
    buf->data = NULL;
    buf->len = 0;
    buf->cap = 0;
}

static int metrics_buffer_reserve(struct metrics_buffer *buf, size_t extra) {
    if (!buf || extra == 0) {
        return 0;
    }
    size_t required = buf->len + extra + 1;
    if (required <= buf->cap) {
        return 0;
    }
    size_t new_cap = buf->cap ? buf->cap : 1024;
    while (new_cap < required) {
        if (new_cap > (SIZE_MAX / 2)) {
            return -1;
        }
        new_cap *= 2;
    }
    char *data = realloc(buf->data, new_cap);
    if (!data) {
        return -1;
    }
    buf->data = data;
    buf->cap = new_cap;
    return 0;
}

static int metrics_buffer_appendf(struct metrics_buffer *buf, const char *fmt, ...) {
    if (!buf || !fmt) {
        return -1;
    }
    va_list args;
    va_start(args, fmt);
    va_list measure;
    va_copy(measure, args);
    int needed = vsnprintf(NULL, 0, fmt, measure);
    va_end(measure);
    if (needed < 0) {
        va_end(args);
        return -1;
    }
    if (metrics_buffer_reserve(buf, (size_t)needed) != 0) {
        va_end(args);
        return -1;
    }
    int written = vsnprintf(buf->data + buf->len, buf->cap - buf->len, fmt, args);
    va_end(args);
    if (written < 0 || (size_t)written != (size_t)needed) {
        return -1;
    }
    buf->len += (size_t)written;
    return 0;
}

static int append_histogram_metrics(
    struct metrics_buffer *buf,
    const char *name,
    const char *help,
    const struct lean_metrics_histogram_snapshot *hist) {
    if (!buf || !name || !help || !hist) {
        return -1;
    }
    if (metrics_buffer_appendf(buf, "# HELP %s %s\n# TYPE %s histogram\n", name, help, name) != 0) {
        return -1;
    }
    size_t bucket_count = hist->bucket_count;
    if (bucket_count > LEAN_METRICS_MAX_BUCKETS) {
        bucket_count = LEAN_METRICS_MAX_BUCKETS;
    }
    for (size_t i = 0; i < bucket_count; ++i) {
        double bound = hist->buckets[i];
        if (metrics_buffer_appendf(
                buf,
                "%s_bucket{le=\"%.9g\"} %" PRIu64 "\n",
                name,
                bound,
                hist->counts[i])
            != 0) {
            return -1;
        }
    }
    if (metrics_buffer_appendf(
            buf,
            "%s_bucket{le=\"+Inf\"} %" PRIu64 "\n",
            name,
            hist->counts[bucket_count])
        != 0) {
        return -1;
    }
    if (metrics_buffer_appendf(buf, "%s_sum %.9f\n%s_count %" PRIu64 "\n", name, hist->sum, name, hist->total) != 0) {
        return -1;
    }
    return 0;
}

static int format_metrics_body(
    const struct lantern_metrics_snapshot *snapshot,
    char **out_body,
    size_t *out_len) {
    if (!snapshot || !out_body || !out_len) {
        return -1;
    }

    struct metrics_buffer buf;
    if (metrics_buffer_init(&buf, 2048) != 0) {
        return -1;
    }

    const struct lean_metrics_snapshot *lean = &snapshot->lean_metrics;
    if (metrics_buffer_appendf(
            &buf,
            "# HELP lean_head_slot Latest slot of the lean chain\n"
            "# TYPE lean_head_slot gauge\n"
            "lean_head_slot %" PRIu64 "\n"
            "# HELP lean_latest_justified_slot Latest justified slot observed by state transition\n"
            "# TYPE lean_latest_justified_slot gauge\n"
            "lean_latest_justified_slot %" PRIu64 "\n"
            "# HELP lean_latest_finalized_slot Latest finalized slot observed by state transition\n"
            "# TYPE lean_latest_finalized_slot gauge\n"
            "lean_latest_finalized_slot %" PRIu64 "\n"
            "# HELP lean_validators_count Number of validators connected to this client\n"
            "# TYPE lean_validators_count gauge\n"
            "lean_validators_count %zu\n"
            "# HELP lean_attestations_valid_total Total number of valid attestations\n"
            "# TYPE lean_attestations_valid_total counter\n"
            "lean_attestations_valid_total %" PRIu64 "\n"
            "# HELP lean_attestations_invalid_total Total number of invalid attestations\n"
            "# TYPE lean_attestations_invalid_total counter\n"
            "lean_attestations_invalid_total %" PRIu64 "\n"
            "# HELP lean_state_transition_slots_processed_total Total number of processed slots during state transitions\n"
            "# TYPE lean_state_transition_slots_processed_total counter\n"
            "lean_state_transition_slots_processed_total %" PRIu64 "\n"
            "# HELP lean_state_transition_attestations_processed_total Total number of attestations processed during state transitions\n"
            "# TYPE lean_state_transition_attestations_processed_total counter\n"
            "lean_state_transition_attestations_processed_total %" PRIu64 "\n",
            snapshot->lean_head_slot,
            snapshot->lean_latest_justified_slot,
            snapshot->lean_latest_finalized_slot,
            snapshot->lean_validators_count,
            lean->attestations_valid_total,
            lean->attestations_invalid_total,
            lean->state_transition_slots_processed_total,
            lean->state_transition_attestations_processed_total)
        != 0) {
        metrics_buffer_free(&buf);
        return -1;
    }

    if (snapshot->peer_vote_metrics_count > 0) {
        if (metrics_buffer_appendf(
                &buf,
                "# HELP lean_gossip_votes_received_total Vote gossip messages received per peer\n"
                "# TYPE lean_gossip_votes_received_total counter\n")
            != 0) {
            metrics_buffer_free(&buf);
            return -1;
        }
        for (size_t i = 0; i < snapshot->peer_vote_metrics_count; ++i) {
            const struct lantern_peer_vote_metric *metric = &snapshot->peer_vote_metrics[i];
            if (metrics_buffer_appendf(
                    &buf,
                    "lean_gossip_votes_received_total{peer=\"%s\"} %" PRIu64 "\n",
                    metric->peer_id,
                    metric->received_total)
                != 0) {
                metrics_buffer_free(&buf);
                return -1;
            }
        }
        if (metrics_buffer_appendf(
                &buf,
                "# HELP lean_gossip_votes_accepted_total Vote gossip messages accepted per peer\n"
                "# TYPE lean_gossip_votes_accepted_total counter\n")
            != 0) {
            metrics_buffer_free(&buf);
            return -1;
        }
        for (size_t i = 0; i < snapshot->peer_vote_metrics_count; ++i) {
            const struct lantern_peer_vote_metric *metric = &snapshot->peer_vote_metrics[i];
            if (metrics_buffer_appendf(
                    &buf,
                    "lean_gossip_votes_accepted_total{peer=\"%s\"} %" PRIu64 "\n",
                    metric->peer_id,
                    metric->accepted_total)
                != 0) {
                metrics_buffer_free(&buf);
                return -1;
            }
        }
        if (metrics_buffer_appendf(
                &buf,
                "# HELP lean_gossip_votes_rejected_total Vote gossip messages rejected per peer\n"
                "# TYPE lean_gossip_votes_rejected_total counter\n")
            != 0) {
            metrics_buffer_free(&buf);
            return -1;
        }
        for (size_t i = 0; i < snapshot->peer_vote_metrics_count; ++i) {
            const struct lantern_peer_vote_metric *metric = &snapshot->peer_vote_metrics[i];
            if (metrics_buffer_appendf(
                    &buf,
                    "lean_gossip_votes_rejected_total{peer=\"%s\"} %" PRIu64 "\n",
                    metric->peer_id,
                    metric->rejected_total)
                != 0) {
                metrics_buffer_free(&buf);
                return -1;
            }
        }
        if (metrics_buffer_appendf(
                &buf,
                "# HELP lean_gossip_votes_last_validator_id Last validator id observed per peer\n"
                "# TYPE lean_gossip_votes_last_validator_id gauge\n")
            != 0) {
            metrics_buffer_free(&buf);
            return -1;
        }
        for (size_t i = 0; i < snapshot->peer_vote_metrics_count; ++i) {
            const struct lantern_peer_vote_metric *metric = &snapshot->peer_vote_metrics[i];
            if (metrics_buffer_appendf(
                    &buf,
                    "lean_gossip_votes_last_validator_id{peer=\"%s\"} %" PRIu64 "\n",
                    metric->peer_id,
                    metric->last_validator_id)
                != 0) {
                metrics_buffer_free(&buf);
                return -1;
            }
        }
        if (metrics_buffer_appendf(
                &buf,
                "# HELP lean_gossip_votes_last_slot Last vote slot observed per peer\n"
                "# TYPE lean_gossip_votes_last_slot gauge\n")
            != 0) {
            metrics_buffer_free(&buf);
            return -1;
        }
        for (size_t i = 0; i < snapshot->peer_vote_metrics_count; ++i) {
            const struct lantern_peer_vote_metric *metric = &snapshot->peer_vote_metrics[i];
            if (metrics_buffer_appendf(
                    &buf,
                    "lean_gossip_votes_last_slot{peer=\"%s\"} %" PRIu64 "\n",
                    metric->peer_id,
                    metric->last_slot)
                != 0) {
                metrics_buffer_free(&buf);
                return -1;
            }
        }
    }

    if (append_histogram_metrics(
            &buf,
            "lean_fork_choice_block_processing_time_seconds",
            "Time taken to process block in fork choice",
            &lean->fork_choice_block_time)
        != 0
        || append_histogram_metrics(
               &buf,
               "lean_attestation_validation_time_seconds",
               "Time taken to validate attestation",
               &lean->attestation_validation_time)
            != 0
        || append_histogram_metrics(
               &buf,
               "lean_state_transition_time_seconds",
               "Time to process state transition",
               &lean->state_transition_time)
            != 0
        || append_histogram_metrics(
               &buf,
               "lean_state_transition_slots_processing_time_seconds",
               "Time taken to process slots during state transition",
               &lean->state_slots_time)
            != 0
        || append_histogram_metrics(
               &buf,
               "lean_state_transition_block_processing_time_seconds",
               "Time taken to process block during state transition",
               &lean->state_block_time)
            != 0
        || append_histogram_metrics(
               &buf,
               "lean_state_transition_attestations_processing_time_seconds",
               "Time taken to process attestations during state transition",
               &lean->state_attestations_time)
            != 0
        || append_histogram_metrics(
               &buf,
               "lean_pq_signature_attestation_signing_time_seconds",
               "Time taken to sign an attestation",
               &lean->pq_signature_signing_time)
            != 0
        || append_histogram_metrics(
               &buf,
               "lean_pq_signature_attestation_verification_time_seconds",
               "Time taken to verify an attestation signature",
               &lean->pq_signature_verification_time)
            != 0) {
        metrics_buffer_free(&buf);
        return -1;
    }

    *out_body = buf.data;
    *out_len = buf.len;
    return 0;
}

static void handle_metrics_request(
    struct lantern_metrics_server *server,
    int client_fd,
    const struct sockaddr_in *peer_addr) {
    char buffer[LANTERN_METRICS_BUFFER_SIZE];
    ssize_t received = recv(client_fd, buffer, sizeof(buffer) - 1, 0);
    if (received <= 0) {
        return;
    }
    buffer[received] = '\0';

    char method[8];
    char path[128];
    if (sscanf(buffer, "%7s %127s", method, path) != 2) {
        lantern_http_send_response(
            client_fd,
            400,
            "Bad Request",
            "application/json",
            "{\"error\":\"malformed request\"}",
            strlen("{\"error\":\"malformed request\"}"));
        return;
    }
    char peer_text[INET_ADDRSTRLEN];
    if (peer_addr) {
        if (!inet_ntop(AF_INET, &peer_addr->sin_addr, peer_text, sizeof(peer_text))) {
            strncpy(peer_text, "unknown", sizeof(peer_text));
            peer_text[sizeof(peer_text) - 1] = '\0';
        }
    } else {
        strncpy(peer_text, "unknown", sizeof(peer_text));
        peer_text[sizeof(peer_text) - 1] = '\0';
    }

    if (strcmp(method, "GET") != 0 || strcmp(path, "/metrics") != 0) {
        lantern_http_send_response(
            client_fd,
            404,
            "Not Found",
            "application/json",
            "{\"error\":\"unknown endpoint\"}",
            strlen("{\"error\":\"unknown endpoint\"}"));
        lantern_log_info(
            "metrics",
            &(const struct lantern_log_metadata){.peer = peer_text},
            "%s %s -> 404",
            method,
            path);
        return;
    }

    if (!server->callbacks.snapshot) {
        lantern_http_send_response(
            client_fd,
            503,
            "Service Unavailable",
            "application/json",
            "{\"error\":\"metrics unavailable\"}",
            strlen("{\"error\":\"metrics unavailable\"}"));
        lantern_log_error(
            "metrics",
            &(const struct lantern_log_metadata){.peer = peer_text},
            "metrics callback missing");
        return;
    }

    struct lantern_metrics_snapshot snapshot;
    memset(&snapshot, 0, sizeof(snapshot));
    if (server->callbacks.snapshot(server->callbacks.context, &snapshot) != 0) {
        lantern_http_send_response(
            client_fd,
            503,
            "Service Unavailable",
            "application/json",
            "{\"error\":\"metrics unavailable\"}",
            strlen("{\"error\":\"metrics unavailable\"}"));
        lantern_log_error(
            "metrics",
            &(const struct lantern_log_metadata){.peer = peer_text},
            "snapshot failed");
        return;
    }

    char *body = NULL;
    size_t body_len = 0;
    if (format_metrics_body(&snapshot, &body, &body_len) != 0) {
        lantern_http_send_response(
            client_fd,
            500,
            "Internal Server Error",
            "application/json",
            "{\"error\":\"metrics formatting failed\"}",
            strlen("{\"error\":\"metrics formatting failed\"}"));
        lantern_log_error(
            "metrics",
            &(const struct lantern_log_metadata){.peer = peer_text},
            "formatting failed");
        return;
    }

    if (lantern_http_send_response(
            client_fd,
            200,
            "OK",
            "text/plain; version=0.0.4",
            body,
            body_len)
        != 0) {
        lantern_log_error(
            "metrics",
            &(const struct lantern_log_metadata){.peer = peer_text},
            "send failed");
        free(body);
        return;
    }
    free(body);
    lantern_log_info(
        "metrics",
        &(const struct lantern_log_metadata){.peer = peer_text},
        "%s %s -> 200",
        method,
        path);
}

static void *lantern_metrics_thread(void *arg) {
    struct lantern_metrics_server *server = arg;
    while (server->running) {
        struct sockaddr_in peer;
        socklen_t peer_len = sizeof(peer);
        int client_fd = accept(server->listen_fd, (struct sockaddr *)&peer, &peer_len);
        if (client_fd < 0) {
            if (!server->running) {
                break;
            }
            if (errno == EINTR) {
                continue;
            }
            lantern_log_error(
                "metrics",
                NULL,
                "accept failed errno=%d",
                errno);
            continue;
        }
        handle_metrics_request(server, client_fd, &peer);
        close(client_fd);
    }
    return NULL;
}

void lantern_metrics_server_init(struct lantern_metrics_server *server) {
    if (!server) {
        return;
    }
    memset(server, 0, sizeof(*server));
    server->listen_fd = -1;
    server->running = 0;
    server->thread_started = 0;
    server->port = 0;
}

void lantern_metrics_server_reset(struct lantern_metrics_server *server) {
    if (!server) {
        return;
    }
    lantern_metrics_server_stop(server);
    lantern_metrics_server_init(server);
}

int lantern_metrics_server_start(
    struct lantern_metrics_server *server,
    uint16_t port,
    const struct lantern_metrics_callbacks *callbacks) {
    if (!server || !callbacks || !callbacks->snapshot) {
        return -1;
    }

    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
        lantern_log_error("metrics", NULL, "socket creation failed errno=%d", errno);
        return -1;
    }

    int opt = 1;
    if (setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt)) != 0) {
        lantern_log_warn("metrics", NULL, "setsockopt(SO_REUSEADDR) failed errno=%d", errno);
    }

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_ANY);
    addr.sin_port = htons(port);

    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
        lantern_log_error("metrics", NULL, "bind failed errno=%d", errno);
        close(fd);
        return -1;
    }
    if (listen(fd, 16) != 0) {
        lantern_log_error("metrics", NULL, "listen failed errno=%d", errno);
        close(fd);
        return -1;
    }

    server->listen_fd = fd;
    server->callbacks = *callbacks;
    server->port = port;
    server->running = 1;
    server->thread_started = 0;

    int rc = pthread_create(&server->thread, NULL, lantern_metrics_thread, server);
    if (rc != 0) {
        lantern_log_error("metrics", NULL, "pthread_create failed rc=%d", rc);
        close(fd);
        server->listen_fd = -1;
        server->running = 0;
        return -1;
    }
    server->thread_started = 1;
    lantern_log_info(
        "metrics",
        NULL,
        "metrics server listening port=%" PRIu16,
        server->port);
    return 0;
}

void lantern_metrics_server_stop(struct lantern_metrics_server *server) {
    if (!server) {
        return;
    }
    if (server->running) {
        server->running = 0;
        if (server->listen_fd >= 0) {
            shutdown(server->listen_fd, SHUT_RDWR);
        }
    }
    if (server->thread_started) {
        pthread_join(server->thread, NULL);
        server->thread_started = 0;
    }
    if (server->listen_fd >= 0) {
        close(server->listen_fd);
        server->listen_fd = -1;
    }
}
