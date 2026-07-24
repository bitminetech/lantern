#ifndef LANTERN_CLIENT_H
#define LANTERN_CLIENT_H

#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>

#include "lantern/consensus/state.h"
#include "lantern/consensus/store.h"
#include "lantern/consensus/slot_clock.h"
#include "lantern/consensus/fork_choice.h"
#include "lantern/consensus/signature.h"
#include "lantern/genesis/genesis.h"
#include "lantern/metrics/server.h"
#include "lantern/http/server.h"
#include "lantern/networking/libp2p.h"
#include "lantern/networking/gossipsub_service.h"
#include "lantern/networking/reqresp_service.h"
#include "lantern/storage/storage.h"
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
    const char *xmss_secret_path;
    const char *xmss_secret_template;
    uint64_t attestation_committee_count_override;
    bool is_aggregator;
    size_t *aggregate_subnet_ids;
    size_t aggregate_subnet_id_count;
    size_t aggregate_subnet_id_capacity;
    double shadow_xmss_rates[LANTERN_SHADOW_OPERATION_COUNT];
    uint8_t shadow_xmss_rates_set;
};

struct lantern_peer_status_entry;
struct lantern_active_blocks_request;
struct lantern_block_fetch;
struct lantern_async_block_import_job;
struct lantern_async_block_proposal_job;

struct lantern_pending_block {
    LanternSignedBlock block;
    LanternRoot root;
    LanternRoot parent_root;
    char peer_text[128];
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
    LanternRoot *roots;
    size_t root_count;
};

struct lantern_range_sync_state {
    uint64_t next_slot;
    uint64_t target_slot;
    uint64_t batch_size;
    uint64_t request_id;
    uint64_t request_start_slot;
    uint64_t request_count;
    char request_peer[128];
    struct lantern_string_list failed_peers;
    bool peers_exhausted;
    bool batch_size_locked;
};

struct lantern_validator_duty_state {
    uint64_t slot_marker;
    bool slot_proposed;
    bool slot_attested;
    bool slot_aggregated;
    uint64_t aggregation_skip_marker;
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
    struct PQSignatureSchemeSecretKey *attestation_secret_key;
    struct PQSignatureSchemeSecretKey *proposal_secret_key;
    char *proposal_secret_path;
    uint64_t last_proposed_slot;
    struct lantern_validator_signature_history attestation_signature_history;
    struct lantern_validator_signature_history proposal_signature_history;
};

struct lantern_client {
    char *data_dir;
    struct lantern_storage storage;
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
    struct lantern_reqresp_service reqresp;
    struct lantern_validator_config_entry *assigned_validators;
    struct lantern_local_validator *local_validators;
    size_t local_validator_count;
    struct lantern_validator_duty_state validator_duty;
    LanternStore store;
    LanternState state;
    pthread_mutex_t state_lock;
    bool state_lock_initialized;
    pthread_mutex_t validator_lock;
    bool validator_lock_initialized;
    pthread_t timing_thread;
    bool timing_thread_started;
    int timing_stop_flag;
    double last_tick_interval_started_seconds;
    struct lantern_async_block_proposal_job *block_proposal_job;
    pthread_mutex_t block_proposal_lock;
    pthread_cond_t block_proposal_cond;
    pthread_t block_proposal_thread;
    bool block_proposal_sync_initialized;
    bool block_proposal_stop;
    struct lantern_metrics_server metrics_server;
    uint64_t start_time_seconds;
    struct lantern_http_server http_server;
    size_t connected_peers;
    pthread_mutex_t connection_lock;
    bool connection_lock_initialized;
    struct lantern_connection_peer_ref *connection_peer_refs;
    size_t connection_peer_ref_count;
    size_t connection_peer_ref_capacity;
    struct lantern_pending_block_list pending_blocks;
    struct lantern_pending_vote_list pending_gossip_votes;
    pthread_mutex_t pending_lock;
    bool pending_lock_initialized;
    struct lantern_async_block_import_job *block_import_head;
    struct lantern_async_block_import_job *block_import_tail;
    pthread_mutex_t block_import_lock;
    pthread_cond_t block_import_cond;
    pthread_t block_import_thread;
    bool block_import_sync_initialized;
    bool block_import_stop;
    uint64_t sync_started_ms;
    uint64_t sync_last_log_ms;
    uint64_t sync_target_slot;
    LanternSyncState sync_state;
    LanternStatusMessage network_view;
    uint64_t last_duty_skip_slot;
    const char *last_duty_skip_reason;
    int dialer_stop_flag;
    uint64_t peer_maintenance_next_us;
    struct lantern_peer_status_entry *peer_status_entries;
    size_t peer_status_count;
    size_t peer_status_capacity;
    struct lantern_active_blocks_request *active_blocks_requests;
    size_t active_blocks_request_count;
    size_t active_blocks_request_capacity;
    struct lantern_block_fetch *block_fetches;
    size_t block_fetch_count;
    size_t block_fetch_capacity;
    struct lantern_range_sync_state range_sync;
    uint64_t next_blocks_request_id;
    pthread_mutex_t status_lock;
    bool status_lock_initialized;
    size_t debug_attestation_committee_count;
    size_t *aggregate_subnet_ids;
    size_t aggregate_subnet_id_count;
    char *xmss_key_dir;
    char *xmss_secret_template;
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
