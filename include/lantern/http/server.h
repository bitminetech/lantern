#ifndef LANTERN_HTTP_SERVER_H
#define LANTERN_HTTP_SERVER_H

#include <stddef.h>
#include <stdbool.h>
#include <stdint.h>

#include "lantern/consensus/containers.h"
#include "lantern/http/core.h"
#include "lantern/metrics/server.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum
{
    LANTERN_HTTP_CB_OK = 0,
    LANTERN_HTTP_CB_ERR_INVALID_PARAM = -1,
    LANTERN_HTTP_CB_ERR_NOT_FOUND = -2,
    LANTERN_HTTP_CB_ERR_INVALID_STATE = -3,
    LANTERN_HTTP_CB_ERR_LOCK_FAILED = -4,
    LANTERN_HTTP_CB_ERR_HASH_FAILED = -5,
    LANTERN_HTTP_CB_ERR_IO = -6,
    LANTERN_HTTP_CB_ERR_UNAVAILABLE = -7,
} lantern_http_callback_error_t;

struct lantern_http_head_snapshot {
    uint64_t slot;
    LanternRoot head_root;
    LanternCheckpoint justified;
    LanternCheckpoint finalized;
};

struct lantern_http_fork_choice_node {
    LanternRoot root;
    uint64_t slot;
    LanternRoot parent_root;
    uint64_t proposer_index;
    uint64_t weight;
};

struct lantern_http_fork_choice_snapshot {
    struct lantern_http_fork_choice_node *nodes;
    size_t node_count;
    LanternRoot head;
    LanternCheckpoint justified;
    LanternCheckpoint finalized;
    LanternRoot safe_target;
    uint64_t validator_count;
};

struct lantern_http_validator_info {
    uint64_t global_index;
    bool enabled;
    char label[64];
};

struct lantern_http_server_callbacks {
    void *context;
    int (*snapshot_head)(void *context, struct lantern_http_head_snapshot *out_snapshot);
    int (*snapshot_fork_choice)(void *context, struct lantern_http_fork_choice_snapshot *out_snapshot);
    size_t (*validator_count)(void *context);
    int (*validator_info)(void *context, size_t index, struct lantern_http_validator_info *out_info);
    int (*set_validator_status)(void *context, uint64_t global_index, bool enabled);
    int (*metrics_snapshot)(void *context, struct lantern_metrics_snapshot *out_snapshot);
    int (*finalized_state_ssz)(void *context, uint8_t **out_bytes, size_t *out_len);
    int (*finalized_block_ssz)(void *context, uint8_t **out_bytes, size_t *out_len);
    int (*get_is_aggregator)(void *context, bool *out_enabled);
    int (*set_is_aggregator)(void *context, bool enabled, bool *out_previous);
};

struct lantern_http_server_config {
    uint16_t port;
    struct lantern_http_server_callbacks callbacks;
};

struct lantern_http_server {
    struct lantern_http_core_server core;
    uint16_t port;
    struct lantern_http_server_callbacks callbacks;
    struct lantern_metrics_http_handler metrics_handler;
};

void lantern_http_server_init(struct lantern_http_server *server);
int lantern_http_server_start(struct lantern_http_server *server, const struct lantern_http_server_config *config);
void lantern_http_server_stop(struct lantern_http_server *server);

#ifdef __cplusplus
}
#endif

#endif /* LANTERN_HTTP_SERVER_H */
