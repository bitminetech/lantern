#ifndef LANTERN_CLIENT_H
#define LANTERN_CLIENT_H

#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>

#include "lantern/consensus/state.h"
#include "lantern/consensus/duties.h"
#include "lantern/consensus/runtime.h"
#include "lantern/consensus/fork_choice.h"
#include "lantern/genesis/genesis.h"
#include "lantern/http/metrics.h"
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
#define LANTERN_DEFAULT_VALIDATOR_REGISTRY "./genesis/validators.yaml"
#define LANTERN_DEFAULT_NODES_FILE "./genesis/nodes.yaml"
#define LANTERN_DEFAULT_GENESIS_STATE "./genesis/genesis.ssz"
#define LANTERN_DEFAULT_VALIDATOR_CONFIG "./genesis/validator-config.yaml"
#define LANTERN_DEFAULT_NODE_ID "lantern_0"
#define LANTERN_DEFAULT_LISTEN_ADDR "/ip4/0.0.0.0/udp/9000/quic-v1"
#define LANTERN_DEFAULT_HTTP_PORT 5052
#define LANTERN_DEFAULT_METRICS_PORT 8080
#define LANTERN_DEFAULT_DEVNET "devnet0"

struct lantern_client_options {
    const char *data_dir;
    const char *genesis_config_path;
    const char *validator_registry_path;
    const char *nodes_path;
    const char *genesis_state_path;
    const char *validator_config_path;
    const char *node_id;
    const char *node_key_hex;
    const char *node_key_path;
    const char *listen_address;
    uint16_t http_port;
    uint16_t metrics_port;
    const char *devnet;
    struct lantern_string_list bootnodes;
    const char *hash_sig_key_dir;
    const char *hash_sig_public_path;
    const char *hash_sig_secret_path;
    const char *hash_sig_public_template;
    const char *hash_sig_secret_template;
};

struct libp2p_subscription;
struct libp2p_protocol_server;
struct lantern_peer_status_entry;
struct lantern_pending_block {
    LanternSignedBlock block;
    LanternRoot root;
    LanternRoot parent_root;
    char peer_text[128];
    bool parent_requested;
};

struct lantern_pending_block_list {
    struct lantern_pending_block *items;
    size_t length;
    size_t capacity;
};

struct lantern_validator_duty_state {
    uint64_t last_slot;
    uint32_t last_interval;
    bool have_timepoint;
    bool slot_proposed;
    bool slot_attested;
    bool pending_local_proposal;
    uint64_t pending_local_index;
    bool proposal_signal_pending;
};

struct lantern_local_validator {
    uint64_t global_index;
    const struct lantern_validator_record *registry;
    uint8_t *secret;
    size_t secret_len;
    bool has_secret;
    struct PQSignatureSchemeSecretKey *secret_key;
    bool has_secret_handle;
    uint64_t last_proposed_slot;
    uint64_t last_attested_slot;
    LanternSignedVote pending_attestation;
    uint64_t pending_attestation_slot;
    bool has_pending_attestation;
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
    struct libp2p_protocol_server *ping_server;
    bool ping_running;
    struct lantern_gossipsub_service gossip;
    bool gossip_running;
    struct lantern_reqresp_service reqresp;
    bool reqresp_running;
    uint8_t node_private_key[32];
    bool has_node_private_key;
    const struct lantern_validator_config_entry *assigned_validators;
    struct lantern_local_validator *local_validators;
    size_t local_validator_count;
    struct lantern_validator_assignment validator_assignment;
    bool has_validator_assignment;
    struct PQSignatureSchemePublicKey **validator_pubkeys;
    size_t validator_pubkey_count;
    struct lantern_consensus_runtime runtime;
    bool has_runtime;
    struct lantern_validator_duty_state validator_duty;
    LanternForkChoice fork_choice;
    bool has_fork_choice;
    LanternState state;
    bool has_state;
    pthread_mutex_t state_lock;
    bool state_lock_initialized;
    bool *validator_enabled;
    pthread_mutex_t validator_lock;
    bool validator_lock_initialized;
    struct lantern_peer_vote_metric *peer_vote_stats;
    size_t peer_vote_stats_len;
    size_t peer_vote_stats_cap;
    pthread_mutex_t peer_vote_lock;
    bool peer_vote_lock_initialized;
    pthread_t validator_thread;
    bool validator_thread_started;
    int validator_stop_flag;
    struct lantern_metrics_server metrics_server;
    bool metrics_running;
    struct lantern_http_server http_server;
    bool http_running;
    bool genesis_fallback_used;
    size_t connected_peers;
    pthread_mutex_t connection_lock;
    bool connection_lock_initialized;
    struct libp2p_subscription *connection_subscription;
    struct lantern_string_list dialer_peers;
    struct lantern_string_list connected_peer_ids;
    struct lantern_string_list status_failure_peer_ids;
    struct lantern_pending_block_list pending_blocks;
    pthread_mutex_t pending_lock;
    bool pending_lock_initialized;
    size_t status_requests_inflight_total;
    size_t status_requests_peak;
    bool status_guard_disabled;
    pthread_t dialer_thread;
    bool dialer_thread_started;
    int dialer_stop_flag;
    pthread_t ping_thread;
    bool ping_thread_started;
    int ping_stop_flag;
    struct lantern_peer_status_entry *peer_status_entries;
    size_t peer_status_count;
    size_t peer_status_capacity;
    pthread_mutex_t status_lock;
    bool status_lock_initialized;
    bool debug_disable_block_requests;
    bool debug_disable_fork_choice_time;
    char *hash_sig_key_dir;
    char *hash_sig_public_template;
    char *hash_sig_secret_template;
    char *hash_sig_public_path;
    char *hash_sig_secret_path;
};

void lantern_client_options_init(struct lantern_client_options *options);
void lantern_client_options_free(struct lantern_client_options *options);
int lantern_client_options_add_bootnode(struct lantern_client_options *options, const char *bootnode);

int lantern_init(struct lantern_client *client, const struct lantern_client_options *options);
void lantern_shutdown(struct lantern_client *client);

size_t lantern_client_local_validator_count(const struct lantern_client *client);
const struct lantern_local_validator *lantern_client_local_validator(
    const struct lantern_client *client,
    size_t index);
int lantern_validator_refresh_cached_vote(
    struct lantern_local_validator *validator,
    uint64_t slot,
    const LanternCheckpoint *head,
    const LanternCheckpoint *target,
    const LanternCheckpoint *source,
    LanternSignedVote *vote);
int lantern_client_publish_block(struct lantern_client *client, const LanternSignedBlock *block);

int lantern_client_debug_record_vote(
    struct lantern_client *client,
    const LanternSignedVote *vote,
    const char *peer_id_text);

int lantern_client_debug_import_block(
    struct lantern_client *client,
    const LanternSignedBlock *block,
    const LanternRoot *block_root,
    const char *peer_id_text);
size_t lantern_client_pending_block_count(const struct lantern_client *client);

#define LANTERN_DEBUG_BLOCKS_REQUEST_SUCCESS 0
#define LANTERN_DEBUG_BLOCKS_REQUEST_FAILED 1
#define LANTERN_DEBUG_BLOCKS_REQUEST_ABORTED 2

int lantern_client_debug_enqueue_pending_block(
    struct lantern_client *client,
    const LanternSignedBlock *block,
    const LanternRoot *block_root,
    const LanternRoot *parent_root,
    const char *peer_id_text);
int lantern_client_debug_pending_entry(
    const struct lantern_client *client,
    size_t index,
    LanternRoot *out_root,
    LanternRoot *out_parent_root,
    bool *out_parent_requested,
    char *out_peer_text,
    size_t peer_text_len);
void lantern_client_debug_pending_reset(struct lantern_client *client);
int lantern_client_debug_set_parent_requested(
    struct lantern_client *client,
    const LanternRoot *root,
    bool requested);
void lantern_client_debug_disable_block_requests(struct lantern_client *client, bool disable);
int lantern_client_debug_on_blocks_request_complete(
    struct lantern_client *client,
    const char *peer_id,
    const LanternRoot *request_root,
    int outcome_code);

#ifdef __cplusplus
}
#endif

#endif /* LANTERN_CLIENT_H */
