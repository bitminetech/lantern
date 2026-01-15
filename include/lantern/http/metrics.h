#ifndef LANTERN_HTTP_METRICS_H
#define LANTERN_HTTP_METRICS_H

#include <pthread.h>
#include <stddef.h>
#include <stdint.h>

#include "lantern/metrics/lean_metrics.h"

#ifdef __cplusplus
extern "C" {
#endif

#define LANTERN_METRICS_MAX_PEER_VOTE_STATS 64u
#define LANTERN_METRICS_NODE_NAME_MAX 64u
#define LANTERN_METRICS_NODE_VERSION_MAX 32u
#define LANTERN_METRICS_PEER_DIRECTION_COUNT 2u
#define LANTERN_METRICS_PEER_CONN_RESULT_COUNT 3u
#define LANTERN_METRICS_PEER_DISCONNECT_REASON_COUNT 4u

enum lantern_metrics_peer_direction {
    LANTERN_METRICS_DIR_INBOUND = 0,
    LANTERN_METRICS_DIR_OUTBOUND = 1,
};

enum lantern_metrics_peer_conn_result {
    LANTERN_METRICS_CONN_SUCCESS = 0,
    LANTERN_METRICS_CONN_TIMEOUT = 1,
    LANTERN_METRICS_CONN_ERROR = 2,
};

enum lantern_metrics_peer_disconnect_reason {
    LANTERN_METRICS_DISCONNECT_TIMEOUT = 0,
    LANTERN_METRICS_DISCONNECT_REMOTE_CLOSE = 1,
    LANTERN_METRICS_DISCONNECT_LOCAL_CLOSE = 2,
    LANTERN_METRICS_DISCONNECT_ERROR = 3,
};

struct lantern_peer_vote_metric {
    char peer_id[128];
    uint64_t received_total;
    uint64_t accepted_total;
    uint64_t rejected_total;
    uint64_t last_validator_id;
    uint64_t last_slot;
};

struct lantern_metrics_snapshot {
    char node_name[LANTERN_METRICS_NODE_NAME_MAX];
    char node_version[LANTERN_METRICS_NODE_VERSION_MAX];
    uint64_t node_start_time_seconds;
    uint64_t lean_head_slot;
    uint64_t lean_current_slot;
    uint64_t lean_safe_target_slot;
    uint64_t lean_latest_justified_slot;
    uint64_t lean_latest_finalized_slot;
    size_t lean_validators_count;
    size_t lean_connected_peers;
    uint64_t peer_connection_events[LANTERN_METRICS_PEER_DIRECTION_COUNT]
                                   [LANTERN_METRICS_PEER_CONN_RESULT_COUNT];
    uint64_t peer_disconnection_events[LANTERN_METRICS_PEER_DIRECTION_COUNT]
                                      [LANTERN_METRICS_PEER_DISCONNECT_REASON_COUNT];
    struct lean_metrics_snapshot lean_metrics;
    size_t peer_vote_metrics_count;
    struct lantern_peer_vote_metric peer_vote_metrics[LANTERN_METRICS_MAX_PEER_VOTE_STATS];
};

struct lantern_metrics_callbacks {
    void *context;
    int (*snapshot)(void *context, struct lantern_metrics_snapshot *out_snapshot);
};

struct lantern_metrics_server {
    int listen_fd;
    pthread_t thread;
    int running;
    int thread_started;
    uint16_t port;
    struct lantern_metrics_callbacks callbacks;
};

void lantern_metrics_server_init(struct lantern_metrics_server *server);
void lantern_metrics_server_reset(struct lantern_metrics_server *server);
int lantern_metrics_server_start(
    struct lantern_metrics_server *server,
    uint16_t port,
    const struct lantern_metrics_callbacks *callbacks);
void lantern_metrics_server_stop(struct lantern_metrics_server *server);

#ifdef __cplusplus
}
#endif

#endif /* LANTERN_HTTP_METRICS_H */
