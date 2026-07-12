#ifndef LANTERN_CLIENT_H
#define LANTERN_CLIENT_H

#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>

#include "lantern/consensus/state.h"
#include "lantern/consensus/store.h"
#include "lantern/consensus/duties.h"
#include "lantern/consensus/runtime.h"
#include "lantern/consensus/fork_choice.h"
#include "lantern/genesis/genesis.h"
#include "lantern/metrics/server.h"
#include "lantern/http/server.h"
#include "lantern/networking/libp2p.h"
#include "lantern/networking/gossipsub_service.h"
#include "lantern/networking/reqresp_service.h"
#include "lantern/support/string_list.h"

#include "pq-bindings-c-rust.h"

#ifdef __cplusplus
extern "C" {
#endif

#define LANTERN_DEFAULT_DATA_DIR "./data"
#define LANTERN_DEFAULT_GENESIS_CONFIG "./genesis/config.yaml"
#define LANTERN_DEFAULT_VALIDATOR_CONFIG_DIR "./genesis"
#define LANTERN_DEFAULT_NODES_FILE "./genesis/nodes.yaml"
#define LANTERN_DEFAULT_NODE_ID "lantern_0"
#define LANTERN_DEFAULT_LISTEN_ADDR "/ip4/0.0.0.0/udp/9000/quic-v1"
#define LANTERN_DEFAULT_HTTP_PORT 5052
#define LANTERN_DEFAULT_METRICS_PORT 8080
#define LANTERN_DEFAULT_DEVNET "12345678"
#define LANTERN_PENDING_BLOCK_LIMIT 1024u
#define LANTERN_PENDING_GOSSIP_VOTE_LIMIT 1024u

typedef enum
{
    LANTERN_CLIENT_OK = 0,
    LANTERN_CLIENT_ERR_INVALID_PARAM = -1,
    LANTERN_CLIENT_ERR_ALLOC = -2,
    LANTERN_CLIENT_ERR_CONFIG = -3,
    LANTERN_CLIENT_ERR_STORAGE = -4,
    LANTERN_CLIENT_ERR_GENESIS = -5,
    LANTERN_CLIENT_ERR_VALIDATOR = -6,
    LANTERN_CLIENT_ERR_RUNTIME = -7,
    LANTERN_CLIENT_ERR_NETWORK = -8,
    LANTERN_CLIENT_ERR_IGNORED = -9
} lantern_client_error;

typedef enum
{
    LANTERN_SYNC_STATE_IDLE = 0,
    LANTERN_SYNC_STATE_SYNCING = 1,
    LANTERN_SYNC_STATE_SYNCED = 2
} LanternSyncState;

struct lantern_client_options {
    const char *data_dir;
    const char *genesis_config_path;
    const char *validator_config_dir;
    const char *nodes_path;
    const char *node_id;
    const char *node_key_hex;
    const char *node_key_path;
    const char *listen_address;
    const char *checkpoint_sync_url;
    uint16_t http_port;
    uint16_t metrics_port;
    const char *devnet;
    struct lantern_string_list bootnodes;
    const char *xmss_key_dir;
    const char *xmss_public_path;
    const char *xmss_secret_path;
    const char *xmss_public_template;
    const char *xmss_secret_template;
    uint64_t attestation_committee_count_override;
    bool has_attestation_committee_count_override;
    bool is_aggregator;
    size_t *aggregate_subnet_ids;
    size_t aggregate_subnet_id_count;
    size_t aggregate_subnet_id_capacity;
    double shadow_xmss_aggregate_signatures_rate;
    bool has_shadow_xmss_aggregate_signatures_rate;
    double shadow_xmss_verify_aggregated_signatures_rate;
    bool has_shadow_xmss_verify_aggregated_signatures_rate;
    double shadow_xmss_merge_rate;
    bool has_shadow_xmss_merge_rate;
};

struct lantern_peer_status_entry;
struct lantern_active_blocks_request;
struct lantern_async_block_import_job;
struct lantern_async_block_proposal_job;
struct lantern_backfill_session {
    bool active;
    LanternRoot head_root;
    LanternRoot frontier_root;
    uint64_t head_slot;
    uint64_t anchor_slot;
    uint32_t frontier_depth;
    char peer_text[128];
    LanternRoot *roots;
    size_t length;
    size_t capacity;
    uint64_t persisted_count;
    size_t imported_count;
    uint64_t dropped_gossip_hints;
};

struct lantern_pending_block {
    LanternSignedBlock block;
    LanternRoot root;
    LanternRoot parent_root;
    char peer_text[128];
    bool parent_requested;
    uint64_t parent_requested_ms;
    uint32_t backfill_depth;
};

struct lantern_pending_block_list {
    struct lantern_pending_block *items;
    size_t length;
    size_t capacity;
};

struct lantern_pending_vote {
    LanternSignedVote vote;
    char peer_text[128];
};

struct lantern_pending_vote_list {
    struct lantern_pending_vote *items;
    size_t length;
    size_t capacity;
};

struct lantern_active_blocks_request {
    uint64_t request_id;
    char peer_id[128];
    uint64_t started_ms;
    uint64_t deadline_ms;
    bool timeout_recorded;
};

struct lantern_validator_duty_state {
    uint64_t last_slot;
    uint32_t last_interval;
    bool have_timepoint;
    bool slot_proposed;
    bool slot_attested;
    bool slot_aggregated;
    uint64_t last_aggregation_skip_slot;
    bool have_aggregation_skip_slot;
    bool pending_local_proposal;
    uint64_t pending_local_index;
    bool proposal_signal_pending;
    bool duty_gate_closed;
};

struct lantern_connection_peer_ref {
    const void *conn;
    struct lantern_peer_id peer;
    bool inbound;
    bool closing;
};

struct lantern_validator_signature_record {
    uint64_t slot;
    LanternRoot message;
    LanternSignature signature;
};

struct lantern_validator_signature_history {
    struct lantern_validator_signature_record *records;
    size_t length;
    size_t capacity;
};

struct lantern_local_validator {
    uint64_t global_index;
    bool disabled;
    uint8_t *secret;
    size_t secret_len;
    bool has_secret;
    struct PQSignatureSchemeSecretKey *attestation_secret_key;
    struct PQSignatureSchemeSecretKey *proposal_secret_key;
    char *proposal_secret_path;
    bool has_attestation_secret_handle;
    bool has_proposal_secret_handle;
    uint64_t last_proposed_slot;
    uint64_t last_attested_slot;
    struct lantern_validator_signature_history attestation_signature_history;
    struct lantern_validator_signature_history proposal_signature_history;
};

struct lantern_network_view {
    uint64_t latest_observed_head_slot;
    uint64_t network_finalized_slot;
    bool has_latest_observed_head_slot;
    bool has_network_finalized_slot;
};

struct lantern_client {
    char *data_dir;
    char *node_id;
    char *listen_address;
    uint16_t http_port;
    uint16_t metrics_port;
    char *devnet;
    struct lantern_string_list bootnodes;
    struct lantern_genesis_paths genesis_paths;
    struct lantern_genesis_artifacts genesis;
    struct lantern_enr_record local_enr;
    struct lantern_libp2p_host network;
    struct lantern_gossipsub_service gossip;
    bool gossip_running;
    struct lantern_reqresp_service reqresp;
    bool reqresp_running;
    const struct lantern_validator_config_entry *assigned_validators;
    struct lantern_local_validator *local_validators;
    size_t local_validator_count;
    struct lantern_validator_assignment validator_assignment;
    struct lantern_consensus_runtime runtime;
    bool has_runtime;
    struct lantern_validator_duty_state validator_duty;
    LanternStore store;
    LanternForkChoice fork_choice;
    bool has_fork_choice;
    LanternState state;
    bool has_state;
    pthread_mutex_t state_lock;
    bool state_lock_initialized;
    pthread_mutex_t validator_lock;
    bool validator_lock_initialized;
    struct lantern_peer_vote_metric *peer_vote_stats;
    size_t peer_vote_stats_len;
    size_t peer_vote_stats_cap;
    pthread_mutex_t peer_vote_lock;
    bool peer_vote_lock_initialized;
    pthread_t timing_thread;
    bool timing_thread_started;
    int timing_stop_flag;
    double last_tick_interval_started_seconds;
    bool has_last_tick_interval_started_seconds;
    pthread_t validator_thread;
    bool validator_thread_started;
    int validator_stop_flag;
    struct lantern_async_block_proposal_job *block_proposal_job;
    uint64_t block_proposal_inflight_slot;
    pthread_mutex_t block_proposal_lock;
    pthread_cond_t block_proposal_cond;
    pthread_t block_proposal_thread;
    bool block_proposal_lock_initialized;
    bool block_proposal_cond_initialized;
    bool block_proposal_thread_started;
    bool block_proposal_stop;
    bool block_proposal_inflight;
    struct lantern_metrics_server metrics_server;
    bool metrics_running;
    uint64_t start_time_seconds;
    struct lantern_http_server http_server;
    bool http_running;
    size_t connected_peers;
    pthread_mutex_t connection_lock;
    bool connection_lock_initialized;
    struct lantern_string_list dialer_peers;
    struct lantern_connection_peer_ref *connection_peer_refs;
    size_t connection_peer_ref_count;
    size_t connection_peer_ref_capacity;
    struct lantern_string_list status_failure_peer_ids;
    struct lantern_pending_block_list pending_blocks;
    struct lantern_pending_vote_list pending_gossip_votes;
    struct lantern_backfill_session backfill;
    pthread_mutex_t pending_lock;
    bool pending_lock_initialized;
    struct lantern_async_block_import_job *block_import_head;
    struct lantern_async_block_import_job *block_import_tail;
    size_t block_import_queue_len;
    pthread_mutex_t block_import_lock;
    pthread_cond_t block_import_cond;
    pthread_t block_import_thread;
    bool block_import_lock_initialized;
    bool block_import_cond_initialized;
    bool block_import_thread_started;
    bool block_import_stop;
    LanternRoot sync_last_requested_root;
    uint64_t sync_last_requested_root_ms;
    uint64_t sync_started_ms;
    uint64_t sync_last_log_ms;
    uint64_t sync_imported_blocks;
    uint64_t sync_target_slot;
    LanternSyncState sync_state;
    bool sync_in_progress;
    struct lantern_network_view network_view;
    uint64_t last_status_log_slot;
    bool has_last_status_log_slot;
    uint64_t last_duty_skip_slot;
    bool has_last_duty_skip_slot;
    const char *last_duty_skip_reason;
    size_t status_requests_inflight_total;
    size_t status_requests_peak;
    bool status_guard_disabled;
    pthread_t dialer_thread;
    bool dialer_thread_started;
    int dialer_stop_flag;
    struct lantern_peer_status_entry *peer_status_entries;
    size_t peer_status_count;
    size_t peer_status_capacity;
    struct lantern_active_blocks_request *active_blocks_requests;
    size_t active_blocks_request_count;
    size_t active_blocks_request_capacity;
    uint64_t next_blocks_request_id;
    pthread_mutex_t status_lock;
    bool status_lock_initialized;
    bool debug_disable_block_requests;
    bool debug_disable_fork_choice_time;
    size_t debug_attestation_committee_count;
    size_t *aggregate_subnet_ids;
    size_t aggregate_subnet_id_count;
    char *xmss_key_dir;
    char *xmss_public_template;
    char *xmss_secret_template;
    char *xmss_public_path;
    char *xmss_secret_path;
};

void lantern_client_options_init(struct lantern_client_options *options);
void lantern_client_options_free(struct lantern_client_options *options);
lantern_client_error lantern_client_options_add_bootnode(
    struct lantern_client_options *options,
    const char *bootnode);
lantern_client_error lantern_client_options_add_bootnodes_from_file(
    struct lantern_client_options *options,
    const char *path);
lantern_client_error lantern_client_options_add_bootnodes_argument(
    struct lantern_client_options *options,
    const char *value);
lantern_client_error lantern_client_options_add_aggregate_subnet_id(
    struct lantern_client_options *options,
    size_t subnet_id);

lantern_client_error lantern_init(
    struct lantern_client *client,
    const struct lantern_client_options *options);
void lantern_shutdown(struct lantern_client *client);
int lantern_client_aggregation_subnet_id(
    const struct lantern_client *client,
    size_t *out_subnet_id);

/**
 * Publish a signed block to the gossip network.
 *
 * @param client Client instance with gossip service running
 * @param block  Signed block to publish
 *
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM on NULL inputs
 * @return LANTERN_CLIENT_ERR_NETWORK if gossip is inactive or publish fails
 */
int lantern_client_publish_block(struct lantern_client *client, const LanternSignedBlock *block);

#ifdef __cplusplus
}
#endif

#endif /* LANTERN_CLIENT_H */
