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
#define LANTERN_METRICS_CONTENT_TYPE "text/plain; version=0.0.4; charset=utf-8"

struct lantern_peer_vote_metric {
    char peer_id[128];
    uint64_t received_total;
    uint64_t accepted_total;
    uint64_t rejected_total;
    uint64_t last_validator_id;
    uint64_t last_slot;
};

struct lantern_metrics_snapshot {
    uint64_t lean_node_start_time_seconds;
    uint64_t lean_head_slot;
    uint64_t lean_current_slot;
    uint64_t lean_safe_target_slot;
    uint64_t lean_latest_justified_slot;
    uint64_t lean_latest_finalized_slot;
    size_t lean_validators_count;
    size_t lean_connected_peers;
    uint64_t lean_gossip_signatures;
    uint64_t lean_latest_new_aggregated_payloads;
    uint64_t lean_latest_known_aggregated_payloads;
    uint64_t lean_is_aggregator;
    uint64_t lean_attestation_committee_subnet;
    uint64_t lean_attestation_committee_count;
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
int lantern_metrics_server_start(
    struct lantern_metrics_server *server,
    uint16_t port,
    const struct lantern_metrics_callbacks *callbacks);
void lantern_metrics_server_stop(struct lantern_metrics_server *server);
int lantern_metrics_format_prometheus(
    const struct lantern_metrics_snapshot *snapshot,
    char **out_body,
    size_t *out_len);

#ifdef __cplusplus
}
#endif

#endif /* LANTERN_HTTP_METRICS_H */
