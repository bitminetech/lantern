#include "lantern/core/client.h"

#include "lantern/consensus/hash.h"
#include "lantern/consensus/containers.h"
#include "lantern/consensus/duties.h"
#include "lantern/consensus/runtime.h"
#include "lantern/consensus/state.h"
#include "lantern/consensus/signature.h"
#include "lantern/consensus/ssz.h"
#include "lantern/consensus/fork_choice.h"
#include "lantern/crypto/hash_sig.h"
#include "lantern/storage/storage.h"
#include "lantern/http/server.h"
#include "lantern/support/strings.h"
#include "lantern/metrics/lean_metrics.h"
#include "lantern/support/log.h"
#include "lantern/support/time.h"
#include "lantern/support/secure_mem.h"
#include "lantern/networking/messages.h"
#include "lantern/networking/reqresp_service.h"
#include "lantern/encoding/snappy.h"
#include "libp2p/events.h"
#include "libp2p/errors.h"
#include "libp2p/protocol_dial.h"
#include "libp2p/stream.h"
#include "libp2p/host.h"
#include "protocol/identify/protocol_identify.h"
#include "protocol/gossipsub/gossipsub.h"
#include "protocol/ping/protocol_ping.h"
#include "peer_id/peer_id.h"
#include "multiformats/unsigned_varint/unsigned_varint.h"
#include "internal/yaml_parser.h"

#include <ctype.h>
#include <errno.h>
#include <inttypes.h>
#include <limits.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <stdarg.h>

#if defined(_WIN32)
#include <windows.h>
#else
#include <sys/time.h>
#endif

#define LANTERN_PEER_DIAL_INTERVAL_SECONDS 5u
#define LANTERN_BLOCKS_REQUEST_BACKOFF_BASE_MS 5000u
#define LANTERN_BLOCKS_REQUEST_BACKOFF_MAX_MS 300000u
#define LANTERN_BLOCKS_REQUEST_BACKOFF_MAX_FAILURES 8u
#define LANTERN_BLOCKS_REQUEST_MIN_POLL_MS 2000u
#define LANTERN_PENDING_BLOCK_LIMIT 256u
#define LANTERN_PEER_DIAL_TIMEOUT_MS 4000

enum lantern_blocks_request_outcome {
    LANTERN_BLOCKS_REQUEST_SUCCESS = 0,
    LANTERN_BLOCKS_REQUEST_FAILED,
    LANTERN_BLOCKS_REQUEST_ABORTED
};

struct lantern_vote_rejection_info;

static uint64_t monotonic_millis(void);
static uint64_t blocks_request_backoff_ms(uint32_t failures);
static int set_owned_string(char **dest, const char *value);
static int copy_genesis_paths(struct lantern_genesis_paths *paths, const struct lantern_client_options *options);
static void reset_genesis_paths(struct lantern_genesis_paths *paths);
static int read_trimmed_file(const char *path, char **out_text);
static int load_node_key_bytes(const struct lantern_client_options *options, uint8_t out_key[32]);
static bool string_list_contains(const struct lantern_string_list *list, const char *value);
static void string_list_remove(struct lantern_string_list *list, const char *value);
static int append_unique_bootnode(struct lantern_string_list *list, const char *value);
static int append_genesis_bootnodes(struct lantern_client *client);
static int compute_local_validator_assignment(struct lantern_client *client);
static int populate_local_validators(struct lantern_client *client);
static void persist_anchor_block(struct lantern_client *client, const LanternBlock *anchor_block, const LanternRoot *anchor_root);
static int init_consensus_runtime(struct lantern_client *client);
static int find_local_validator_index(const struct lantern_client *client, uint64_t global_index, size_t *out_index);
static void reset_local_validators(struct lantern_client *client);
static void local_validator_cleanup(struct lantern_local_validator *validator);
static int decode_validator_secret(const char *hex, uint8_t **out_key, size_t *out_len);
static int configure_hash_sig_sources(struct lantern_client *client, const struct lantern_client_options *options);
static int load_hash_sig_keys(struct lantern_client *client);
static void free_hash_sig_pubkeys(struct lantern_client *client);
static int http_snapshot_head(void *context, struct lantern_http_head_snapshot *out_snapshot);
static size_t http_validator_count_cb(void *context);
static int http_validator_info_cb(void *context, size_t index, struct lantern_http_validator_info *out_info);
static int http_set_validator_status_cb(void *context, uint64_t global_index, bool enabled);
static int metrics_snapshot_cb(void *context, struct lantern_metrics_snapshot *out_snapshot);
static void format_root_hex(const LanternRoot *root, char *out, size_t out_len);
static bool lantern_client_lock_state(struct lantern_client *client);
static void lantern_client_unlock_state(struct lantern_client *client, bool locked);
static void lantern_client_note_vote_delivery(
    struct lantern_client *client,
    const char *peer_id,
    const LanternSignedVote *vote);
static void lantern_client_note_vote_outcome(
    struct lantern_client *client,
    const char *peer_id,
    const LanternSignedVote *vote,
    bool accepted);
static void lantern_client_register_vote_peer(
    struct lantern_client *client,
    const char *peer_id);
static bool lantern_client_lock_pending(struct lantern_client *client);
static void lantern_client_unlock_pending(struct lantern_client *client, bool locked);
static int lantern_client_refresh_state_validators(struct lantern_client *client);
static size_t lantern_client_enabled_validator_count(struct lantern_client *client);
static void lantern_vote_rejection_set(struct lantern_vote_rejection_info *info, const char *fmt, ...);
static bool lantern_validator_pubkey_is_zero(const uint8_t *pubkey);
static bool lantern_client_block_known_locked(
    struct lantern_client *client,
    const LanternRoot *root,
    uint64_t *out_slot);
static bool lantern_client_current_slot(const struct lantern_client *client, uint64_t *out_slot);
static bool lantern_client_validate_vote_constraints(
    struct lantern_client *client,
    const LanternVote *vote,
    const char *facility,
    const struct lantern_log_metadata *meta,
    const char *context,
    struct lantern_vote_rejection_info *out_rejection);
static bool lantern_client_import_block(
    struct lantern_client *client,
    const LanternSignedBlock *block,
    const LanternRoot *block_root,
    const struct lantern_log_metadata *meta);
static int reqresp_build_status(void *context, LanternStatusMessage *out_status);
static int reqresp_handle_status(void *context, const LanternStatusMessage *peer_status, const char *peer_id);
static void reqresp_status_failure(void *context, const char *peer_id, int error);
static void lantern_client_on_peer_status(
    struct lantern_client *client,
    const LanternStatusMessage *peer_status,
    const char *peer_id);
static void lantern_client_adopt_peer_genesis(
    struct lantern_client *client,
    const LanternStatusMessage *peer_status,
    const char *peer_id_text);
static void lantern_client_on_blocks_request_complete(
    struct lantern_client *client,
    const char *peer_id,
    const LanternRoot *request_root,
    enum lantern_blocks_request_outcome outcome);
static int reqresp_collect_blocks(
    void *context,
    const LanternRoot *roots,
    size_t root_count,
    LanternBlocksByRootResponse *out_blocks);
static bool listen_address_is_unspecified(const char *addr);
static void adopt_validator_listen_address(struct lantern_client *client);
static void identify_dial_multiaddr(struct lantern_client *client, const char *multiaddr, const char *peer_label);
static int initialize_fork_choice(struct lantern_client *client);
static int restore_persisted_blocks(struct lantern_client *client);
static void lantern_client_seed_reqresp_peer_modes(struct lantern_client *client);
static void connection_events_cb(const libp2p_event_t *evt, void *user_data);
static const char *connection_reason_text(int reason);
static void connection_counter_update(
    struct lantern_client *client,
    int delta,
    const peer_id_t *peer,
    bool inbound,
    int reason);
static void connection_counter_reset(struct lantern_client *client);
static void request_status_now(struct lantern_client *client, const peer_id_t *peer, const char *peer_text);
static bool lantern_client_is_peer_connected(struct lantern_client *client, const char *peer_id);
static void lantern_client_status_request_update_locked(
    struct lantern_client *client,
    struct lantern_peer_status_entry *entry,
    const char *peer_id,
    int delta,
    const char *phase);
static int start_peer_dialer(struct lantern_client *client);
static void stop_peer_dialer(struct lantern_client *client);
static uint64_t validator_wall_time_now_seconds(void);
static void validator_sleep_ms(uint32_t ms);
static bool validator_service_should_run(const struct lantern_client *client);
static bool validator_is_enabled(const struct lantern_client *client, size_t local_index);
static uint64_t validator_global_index(const struct lantern_client *client, size_t local_index);
static int validator_sign_vote(
    struct lantern_local_validator *validator,
    uint64_t slot,
    LanternSignedVote *vote);
static int validator_store_vote(struct lantern_client *client, const LanternSignedVote *vote);
static int validator_publish_vote(struct lantern_client *client, const LanternSignedVote *vote);
static int validator_build_block(
    struct lantern_client *client,
    uint64_t slot,
    size_t local_index,
    LanternSignedBlock *out_block,
    LanternSignedVote *out_proposer_vote);
static int validator_propose_block(struct lantern_client *client, uint64_t slot, size_t local_index);
static int validator_publish_attestations(struct lantern_client *client, uint64_t slot);
static int start_validator_service(struct lantern_client *client);
static void stop_validator_service(struct lantern_client *client);
static void *validator_thread(void *arg);
static void *peer_dialer_thread(void *arg);
static void peer_dialer_attempt(struct lantern_client *client);
static void peer_dialer_sleep(struct lantern_client *client, unsigned seconds);
static bool lantern_root_is_zero(const LanternRoot *root);
static void pending_block_list_init(struct lantern_pending_block_list *list);
static void pending_block_list_reset(struct lantern_pending_block_list *list);
static struct lantern_pending_block *pending_block_list_find(
    struct lantern_pending_block_list *list,
    const LanternRoot *root);
static void pending_block_list_remove(struct lantern_pending_block_list *list, size_t index);
static struct lantern_pending_block *pending_block_list_append(
    struct lantern_pending_block_list *list,
    const LanternSignedBlock *block,
    const LanternRoot *block_root,
    const LanternRoot *parent_root,
    const char *peer_text);
static void lantern_client_enqueue_pending_block(
    struct lantern_client *client,
    const LanternSignedBlock *block,
    const LanternRoot *block_root,
    const LanternRoot *parent_root,
    const char *peer_text);
static void lantern_client_pending_remove_by_root(struct lantern_client *client, const LanternRoot *root);
static void lantern_client_process_pending_children(struct lantern_client *client, const LanternRoot *parent_root);

static int lantern_client_schedule_blocks_request(
    struct lantern_client *client,
    const char *peer_id_text,
    const LanternRoot *root,
    bool use_legacy);
static void lantern_client_record_block(
    struct lantern_client *client,
    const LanternSignedBlock *block,
    const LanternRoot *root,
    const char *peer_text,
    const char *context);
static void lantern_client_record_vote(
    struct lantern_client *client,
    const LanternSignedVote *vote,
    const char *peer_text);
static int gossip_block_handler(
    const LanternSignedBlock *block,
    const peer_id_t *from,
    void *context);
static int gossip_vote_handler(
    const LanternSignedVote *vote,
    const peer_id_t *from,
    void *context);
static void block_request_on_open(libp2p_stream_t *stream, void *user_data, int err);
static void *block_request_worker(void *arg);
static int stream_write_all(libp2p_stream_t *stream, const uint8_t *data, size_t length);
static int read_varint_payload_chunk(
    libp2p_stream_t *stream,
    uint8_t first_byte,
    uint8_t **out_data,
    size_t *out_len,
    ssize_t *out_err,
    const struct lantern_log_metadata *meta,
    const char *label);

static void persist_anchor_block(struct lantern_client *client, const LanternBlock *anchor_block, const LanternRoot *anchor_root) {
    if (!client || !client->data_dir || !anchor_block) {
        return;
    }

    LanternSignedBlock stored_anchor;
    lantern_signed_block_with_attestation_init(&stored_anchor);
    LanternBlock *block = &stored_anchor.message.block;
    block->slot = anchor_block->slot;
    block->proposer_index = anchor_block->proposer_index;
    block->parent_root = anchor_block->parent_root;
    block->state_root = anchor_block->state_root;

    LanternRoot computed_root;
    const LanternRoot *root_to_log = anchor_root;
    if (!root_to_log) {
        if (lantern_hash_tree_root_block(block, &computed_root) == 0) {
            root_to_log = &computed_root;
        }
    }
    char root_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    root_hex[0] = '\0';
    if (root_to_log) {
        format_root_hex(root_to_log, root_hex, sizeof(root_hex));
    }

    struct lantern_log_metadata meta = {.validator = client->node_id};
    if (lantern_storage_store_block(client->data_dir, &stored_anchor) != 0) {
        lantern_log_warn(
            "storage",
            &meta,
            "failed to persist genesis anchor block root=%s",
            root_hex[0] ? root_hex : "0x0");
    } else {
        lantern_log_debug(
            "storage",
            &meta,
            "persisted genesis anchor block root=%s",
            root_hex[0] ? root_hex : "0x0");
    }
    lantern_signed_block_with_attestation_reset(&stored_anchor);
}

struct lantern_peer_status_entry {
    char peer_id[128];
    LanternStatusMessage status;
    bool has_status;
    bool requested_head;
    bool status_request_inflight;
    uint64_t last_blocks_request_ms;
    uint32_t consecutive_blocks_failures;
    uint32_t outstanding_status_requests;
};

struct block_request_ctx {
    struct lantern_client *client;
    peer_id_t peer_id;
    char peer_text[128];
    LanternRoot root;
    const char *protocol_id;
    bool using_legacy;
};

struct block_request_worker_args {
    struct block_request_ctx *ctx;
    libp2p_stream_t *stream;
};

struct lantern_vote_rejection_info {
    bool has_reason;
    char message[256];
};

static size_t lantern_peer_id_capacity(void) {
    return sizeof(((struct lantern_peer_status_entry *)0)->peer_id);
}

static struct lantern_peer_status_entry *
lantern_client_find_status_entry_locked(struct lantern_client *client, const char *peer_id) {
    if (!client || !peer_id || !peer_id[0]) {
        return NULL;
    }
    const size_t peer_cap = lantern_peer_id_capacity();
    for (size_t i = 0; i < client->peer_status_count; ++i) {
        struct lantern_peer_status_entry *entry = &client->peer_status_entries[i];
        if (strncmp(entry->peer_id, peer_id, peer_cap) == 0) {
            return entry;
        }
    }
    return NULL;
}

static struct lantern_peer_status_entry *
lantern_client_ensure_status_entry_locked(struct lantern_client *client, const char *peer_id) {
    if (!client || !peer_id || !peer_id[0]) {
        return NULL;
    }
    struct lantern_peer_status_entry *entry = lantern_client_find_status_entry_locked(client, peer_id);
    if (entry) {
        return entry;
    }
    if (client->peer_status_count == client->peer_status_capacity) {
        size_t new_capacity = client->peer_status_capacity == 0 ? 4u : client->peer_status_capacity * 2u;
        if (new_capacity > (SIZE_MAX / sizeof(*client->peer_status_entries))) {
            return NULL;
        }
        struct lantern_peer_status_entry *grown = realloc(
            client->peer_status_entries,
            new_capacity * sizeof(*client->peer_status_entries));
        if (!grown) {
            return NULL;
        }
        memset(
            grown + client->peer_status_capacity,
            0,
            (new_capacity - client->peer_status_capacity) * sizeof(*grown));
        client->peer_status_entries = grown;
        client->peer_status_capacity = new_capacity;
    }
    entry = &client->peer_status_entries[client->peer_status_count++];
    memset(entry, 0, sizeof(*entry));
    const size_t peer_cap = lantern_peer_id_capacity();
    strncpy(entry->peer_id, peer_id, peer_cap - 1);
    entry->peer_id[peer_cap - 1] = '\0';
    lantern_client_register_vote_peer(client, peer_id);
    return entry;
}

static struct lantern_peer_vote_metric *
lantern_client_find_vote_metric_locked(struct lantern_client *client, const char *peer_id) {
    if (!client || !peer_id || !peer_id[0] || !client->peer_vote_stats || client->peer_vote_stats_len == 0) {
        return NULL;
    }
    const size_t peer_cap = sizeof(((struct lantern_peer_vote_metric *)0)->peer_id);
    for (size_t i = 0; i < client->peer_vote_stats_len; ++i) {
        struct lantern_peer_vote_metric *entry = &client->peer_vote_stats[i];
        if (strncmp(entry->peer_id, peer_id, peer_cap) == 0) {
            return entry;
        }
    }
    return NULL;
}

static struct lantern_peer_vote_metric *
lantern_client_ensure_vote_metric_locked(struct lantern_client *client, const char *peer_id) {
    if (!client || !peer_id || !peer_id[0]) {
        return NULL;
    }
    struct lantern_peer_vote_metric *entry = lantern_client_find_vote_metric_locked(client, peer_id);
    if (entry) {
        return entry;
    }
    size_t new_capacity = client->peer_vote_stats_cap == 0 ? 4u : client->peer_vote_stats_cap * 2u;
    if (new_capacity > (SIZE_MAX / sizeof(*client->peer_vote_stats))) {
        return NULL;
    }
    if (client->peer_vote_stats_len == client->peer_vote_stats_cap) {
        struct lantern_peer_vote_metric *grown = realloc(
            client->peer_vote_stats,
            new_capacity * sizeof(*client->peer_vote_stats));
        if (!grown) {
            return NULL;
        }
        memset(
            grown + client->peer_vote_stats_cap,
            0,
            (new_capacity - client->peer_vote_stats_cap) * sizeof(*grown));
        client->peer_vote_stats = grown;
        client->peer_vote_stats_cap = new_capacity;
    }
    entry = &client->peer_vote_stats[client->peer_vote_stats_len++];
    memset(entry, 0, sizeof(*entry));
    const size_t peer_cap = sizeof(entry->peer_id);
    strncpy(entry->peer_id, peer_id, peer_cap - 1u);
    entry->peer_id[peer_cap - 1u] = '\0';
    return entry;
}

static void lantern_client_register_vote_peer(struct lantern_client *client, const char *peer_id) {
    if (!client || !peer_id || !peer_id[0] || !client->peer_vote_lock_initialized) {
        return;
    }
    if (pthread_mutex_lock(&client->peer_vote_lock) != 0) {
        return;
    }
    (void)lantern_client_ensure_vote_metric_locked(client, peer_id);
    pthread_mutex_unlock(&client->peer_vote_lock);
}

static void lantern_client_note_vote_delivery(
    struct lantern_client *client,
    const char *peer_id,
    const LanternSignedVote *vote) {
    if (!client || !peer_id || !peer_id[0] || !client->peer_vote_lock_initialized) {
        return;
    }
    if (pthread_mutex_lock(&client->peer_vote_lock) != 0) {
        return;
    }
    struct lantern_peer_vote_metric *metrics = lantern_client_ensure_vote_metric_locked(client, peer_id);
    if (metrics) {
        if (metrics->received_total < UINT64_MAX) {
            metrics->received_total += 1u;
        }
        if (vote) {
            metrics->last_validator_id = vote->data.validator_id;
            metrics->last_slot = vote->data.slot;
        }
    }
    pthread_mutex_unlock(&client->peer_vote_lock);
}

static void lantern_client_note_vote_outcome(
    struct lantern_client *client,
    const char *peer_id,
    const LanternSignedVote *vote,
    bool accepted) {
    if (!client || !peer_id || !peer_id[0] || !client->peer_vote_lock_initialized) {
        return;
    }
    if (pthread_mutex_lock(&client->peer_vote_lock) != 0) {
        return;
    }
    struct lantern_peer_vote_metric *metrics = lantern_client_ensure_vote_metric_locked(client, peer_id);
    if (metrics) {
        if (accepted) {
            if (metrics->accepted_total < UINT64_MAX) {
                metrics->accepted_total += 1u;
            }
        } else {
            if (metrics->rejected_total < UINT64_MAX) {
                metrics->rejected_total += 1u;
            }
        }
        if (vote) {
            metrics->last_validator_id = vote->data.validator_id;
            metrics->last_slot = vote->data.slot;
        }
    }
    pthread_mutex_unlock(&client->peer_vote_lock);
}

static bool lantern_client_try_begin_status_request(struct lantern_client *client, const char *peer_id) {
    if (!client || !peer_id || !peer_id[0] || !client->status_lock_initialized) {
        return true;
    }
    if (pthread_mutex_lock(&client->status_lock) != 0) {
        return false;
    }
    bool allowed = false;
    struct lantern_peer_status_entry *entry = lantern_client_ensure_status_entry_locked(client, peer_id);
    if (entry && !entry->status_request_inflight) {
        entry->status_request_inflight = true;
        allowed = true;
    }
    pthread_mutex_unlock(&client->status_lock);
    return allowed;
}

static void lantern_client_note_status_request_start(struct lantern_client *client, const char *peer_id) {
    if (!client || !peer_id || !peer_id[0] || !client->status_lock_initialized) {
        return;
    }
    if (pthread_mutex_lock(&client->status_lock) != 0) {
        return;
    }
    struct lantern_peer_status_entry *entry = lantern_client_find_status_entry_locked(client, peer_id);
    if (entry) {
        lantern_client_status_request_update_locked(client, entry, peer_id, 1, "dispatch");
    }
    pthread_mutex_unlock(&client->status_lock);
}

static void lantern_client_status_request_failed(struct lantern_client *client, const char *peer_id) {
    if (!client || !peer_id || !peer_id[0] || !client->status_lock_initialized) {
        return;
    }
    if (pthread_mutex_lock(&client->status_lock) != 0) {
        return;
    }
    struct lantern_peer_status_entry *entry = lantern_client_find_status_entry_locked(client, peer_id);
    if (entry) {
        entry->status_request_inflight = false;
        lantern_client_status_request_update_locked(client, entry, peer_id, -1, "failure");
    }
    pthread_mutex_unlock(&client->status_lock);
}

struct lantern_persisted_block {
    LanternSignedBlock block;
    LanternRoot root;
};

struct lantern_persisted_block_list {
    struct lantern_persisted_block *items;
    size_t length;
    size_t capacity;
};

static uint64_t monotonic_millis(void) {
#if defined(_WIN32)
    LARGE_INTEGER freq = {0};
    LARGE_INTEGER counter = {0};
    if (!QueryPerformanceFrequency(&freq) || !QueryPerformanceCounter(&counter) || freq.QuadPart == 0) {
        return 0;
    }
    return (uint64_t)((counter.QuadPart * 1000ULL) / (uint64_t)freq.QuadPart);
#elif defined(CLOCK_MONOTONIC)
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) {
        return 0;
    }
    return (uint64_t)ts.tv_sec * 1000ULL + (uint64_t)(ts.tv_nsec / 1000000ULL);
#else
    struct timeval tv;
    if (gettimeofday(&tv, NULL) != 0) {
        return 0;
    }
    return (uint64_t)tv.tv_sec * 1000ULL + (uint64_t)(tv.tv_usec / 1000ULL);
#endif
}

static uint64_t blocks_request_backoff_ms(uint32_t failures) {
    if (failures == 0) {
        return 0;
    }
    if (failures > LANTERN_BLOCKS_REQUEST_BACKOFF_MAX_FAILURES) {
        failures = LANTERN_BLOCKS_REQUEST_BACKOFF_MAX_FAILURES;
    }
    uint64_t backoff = (uint64_t)LANTERN_BLOCKS_REQUEST_BACKOFF_BASE_MS << (failures - 1u);
    if (backoff > LANTERN_BLOCKS_REQUEST_BACKOFF_MAX_MS) {
        return LANTERN_BLOCKS_REQUEST_BACKOFF_MAX_MS;
    }
    return backoff;
}

static void connection_counter_reset(struct lantern_client *client) {
    if (!client) {
        return;
    }
    if (!client->connection_lock_initialized) {
        client->connected_peers = 0;
        lantern_string_list_reset(&client->connected_peer_ids);
        lantern_string_list_init(&client->connected_peer_ids);
        return;
    }
    if (pthread_mutex_lock(&client->connection_lock) == 0) {
        client->connected_peers = 0;
        lantern_string_list_reset(&client->connected_peer_ids);
        lantern_string_list_init(&client->connected_peer_ids);
        pthread_mutex_unlock(&client->connection_lock);
    } else {
        client->connected_peers = 0;
        lantern_string_list_reset(&client->connected_peer_ids);
        lantern_string_list_init(&client->connected_peer_ids);
    }
}

static void connection_counter_update(
    struct lantern_client *client,
    int delta,
    const peer_id_t *peer,
    bool inbound,
    int reason) {
    if (!client || !client->connection_lock_initialized) {
        return;
    }

    char peer_text[128];
    peer_text[0] = '\0';
    if (peer) {
        if (peer_id_to_string(peer, PEER_ID_FMT_BASE58_LEGACY, peer_text, sizeof(peer_text)) < 0) {
            peer_text[0] = '\0';
        }
    }

    const char *label = peer_text[0] ? peer_text : NULL;
    size_t total = 0;
    if (pthread_mutex_lock(&client->connection_lock) == 0) {
        if (peer_text[0]) {
            if (delta > 0) {
                if (!string_list_contains(&client->connected_peer_ids, peer_text)) {
                    (void)lantern_string_list_append(&client->connected_peer_ids, peer_text);
                }
            } else if (delta < 0) {
                string_list_remove(&client->connected_peer_ids, peer_text);
            }
            client->connected_peers = client->connected_peer_ids.len;
        } else {
            if (delta > 0) {
                client->connected_peers += (size_t)delta;
            } else if (delta < 0) {
                size_t decrease = (size_t)(-delta);
                if (client->connected_peers > decrease) {
                    client->connected_peers -= decrease;
                } else {
                    client->connected_peers = 0;
                }
            }
        }
        total = client->connected_peers;
        pthread_mutex_unlock(&client->connection_lock);
    } else {
        return;
    }

    lantern_log_trace(
        "network",
        &(const struct lantern_log_metadata){
            .validator = client->node_id,
            .peer = peer_text[0] ? peer_text : NULL,
        },
        "connection %s inbound=%s total=%zu reason=%d (%s)",
        delta > 0 ? "opened" : "closed",
        inbound ? "true" : "false",
        total,
        reason,
        connection_reason_text(reason));
}

static void request_status_now(struct lantern_client *client, const peer_id_t *peer, const char *peer_text) {
    if (!client || !client->reqresp_running) {
        return;
    }
    char peer_buffer[128];
    peer_buffer[0] = '\0';
    const char *status_peer = (peer_text && peer_text[0]) ? peer_text : NULL;
    if ((!status_peer || status_peer[0] == '\0') && peer) {
        if (peer_id_to_string(peer, PEER_ID_FMT_BASE58_LEGACY, peer_buffer, sizeof(peer_buffer)) == 0) {
            status_peer = peer_buffer;
        } else {
            status_peer = NULL;
        }
    }
    if (status_peer && !lantern_client_is_peer_connected(client, status_peer)) {
        lantern_log_trace(
            "reqresp",
            &(const struct lantern_log_metadata){
                .validator = client->node_id,
                .peer = status_peer},
            "cannot request status; peer is not connected");
        return;
    }

    struct lantern_log_metadata meta = {
        .validator = client->node_id,
        .peer = status_peer,
    };

    bool guard_claimed = false;
    bool guard_enabled = !client->status_guard_disabled;
    if (status_peer && client->status_lock_initialized && guard_enabled) {
        guard_claimed = lantern_client_try_begin_status_request(client, status_peer);
        if (!guard_claimed) {
            lantern_log_trace(
                "reqresp",
                &meta,
                "status request already in flight; skipping");
            return;
        }
    } else if (status_peer && client->status_guard_disabled) {
        lantern_log_debug(
            "reqresp",
            &meta,
            "status guard disabled; allowing concurrent request");
    }

    int status_rc = lantern_reqresp_service_request_status(&client->reqresp, peer, status_peer);
    if (status_peer) {
        lantern_log_trace(
            "reqresp",
            &meta,
            status_rc == 0 ? "initiated status request to peer" : "unable to initiate status request to peer");
    } else if (status_rc != 0) {
        lantern_log_trace(
            "reqresp",
            &(const struct lantern_log_metadata){
                .validator = client->node_id},
            "unable to initiate status request to peer");
    } else {
        lantern_log_trace(
            "reqresp",
            &(const struct lantern_log_metadata){
                .validator = client->node_id},
            "initiated status request to peer");
    }
    if (status_peer) {
        if (status_rc == 0) {
            lantern_client_note_status_request_start(client, status_peer);
        } else {
            lantern_client_status_request_failed(client, status_peer);
        }
    }
}

static void lantern_client_seed_reqresp_peer_modes(struct lantern_client *client) {
    if (!client) {
        return;
    }
#if defined(LANTERN_REQRESP_STATUS_PROTOCOL_LEGACY) || defined(LANTERN_REQRESP_BLOCKS_BY_ROOT_PROTOCOL_LEGACY)
    const struct lantern_validator_config *config = &client->genesis.validator_config;
    if (!config || !config->entries) {
        return;
    }
    for (size_t i = 0; i < config->count; ++i) {
        const struct lantern_validator_config_entry *entry = &config->entries[i];
        if (!entry->peer_id_text || !entry->peer_id_text[0]) {
            continue;
        }
        int legacy = (entry->client_kind == LANTERN_VALIDATOR_CLIENT_QLEAN);
        lantern_reqresp_service_hint_peer_legacy(&client->reqresp, entry->peer_id_text, legacy);
    }
#else
    (void)client;
#endif
}

static void peer_dialer_sleep(struct lantern_client *client, unsigned seconds) {
    if (!client || seconds == 0u) {
        return;
    }
    struct timespec req = {.tv_sec = 1, .tv_nsec = 0};
    for (unsigned i = 0; i < seconds; ++i) {
        if (__atomic_load_n(&client->dialer_stop_flag, __ATOMIC_RELAXED) != 0) {
            break;
        }
        (void)nanosleep(&req, NULL);
    }
}

static bool listen_address_is_unspecified(const char *addr) {
    if (!addr) {
        return false;
    }
    if (strncmp(addr, "/ip4/0.0.0.0/", strlen("/ip4/0.0.0.0/")) == 0) {
        return true;
    }
    if (strncmp(addr, "/ip6/::/", strlen("/ip6/::/")) == 0) {
        return true;
    }
    return false;
}

static void adopt_validator_listen_address(struct lantern_client *client) {
    if (!client || !client->assigned_validators) {
        return;
    }
    const char *current = client->listen_address;
    if (!listen_address_is_unspecified(current)) {
        return;
    }
    const struct lantern_validator_config_enr *enr = &client->assigned_validators->enr;
    if (!enr->ip || *enr->ip == '\0' || enr->quic_port == 0) {
        return;
    }
    const char *fmt = strchr(enr->ip, ':') ? "/ip6/%s/udp/%u/quic-v1" : "/ip4/%s/udp/%u/quic-v1";
    char derived[128];
    int written = snprintf(derived, sizeof(derived), fmt, enr->ip, (unsigned)enr->quic_port);
    if (written <= 0 || (size_t)written >= sizeof(derived)) {
        lantern_log_warn(
            "network",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to derive listen address from ENR ip=%s port=%u",
            enr->ip,
            (unsigned)enr->quic_port);
        return;
    }
    if (set_owned_string(&client->listen_address, derived) != 0) {
        lantern_log_warn(
            "network",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to apply derived listen address %s",
            derived);
        return;
    }
    lantern_log_info(
        "network",
        &(const struct lantern_log_metadata){.validator = client->node_id},
        "using validator ENR listen multiaddr %s",
        client->listen_address);
}

static bool lantern_client_is_peer_connected(struct lantern_client *client, const char *peer_id) {
    if (!client || !peer_id || !peer_id[0] || !client->connection_lock_initialized) {
        return false;
    }
    bool connected = false;
    if (pthread_mutex_lock(&client->connection_lock) == 0) {
        connected = string_list_contains(&client->connected_peer_ids, peer_id);
        pthread_mutex_unlock(&client->connection_lock);
    }
    return connected;
}

static void lantern_client_status_request_update_locked(
    struct lantern_client *client,
    struct lantern_peer_status_entry *entry,
    const char *peer_id,
    int delta,
    const char *phase) {
    if (!client || !entry || delta == 0) {
        return;
    }
    if (delta > 0) {
        uint32_t increase = (uint32_t)delta;
        if (UINT32_MAX - entry->outstanding_status_requests < increase) {
            entry->outstanding_status_requests = UINT32_MAX;
        } else {
            entry->outstanding_status_requests += increase;
        }
        client->status_requests_inflight_total += (size_t)increase;
        if (client->status_requests_inflight_total > client->status_requests_peak) {
            client->status_requests_peak = client->status_requests_inflight_total;
        }
    } else {
        uint32_t decrease = (uint32_t)(-delta);
        if (entry->outstanding_status_requests > decrease) {
            entry->outstanding_status_requests -= decrease;
        } else {
            entry->outstanding_status_requests = 0;
        }
        if (client->status_requests_inflight_total > (size_t)decrease) {
            client->status_requests_inflight_total -= (size_t)decrease;
        } else {
            client->status_requests_inflight_total = 0;
        }
    }

    lantern_log_debug(
        "reqresp",
        &(const struct lantern_log_metadata){
            .validator = client->node_id,
            .peer = (peer_id && peer_id[0]) ? peer_id : NULL,
        },
        "status guard %s delta=%d peer_outstanding=%u total_outstanding=%zu peak=%zu guard_disabled=%s",
        phase ? phase : "update",
        delta,
        entry->outstanding_status_requests,
        client->status_requests_inflight_total,
        client->status_requests_peak,
        client->status_guard_disabled ? "true" : "false");
}

static void identify_dial_multiaddr(struct lantern_client *client, const char *multiaddr, const char *peer_label) {
    if (!client || !client->network.host || !multiaddr || multiaddr[0] == '\0') {
        return;
    }

    libp2p_stream_t *stream = NULL;
    int rc = libp2p_host_dial_protocol_blocking(
        client->network.host,
        multiaddr,
        LIBP2P_IDENTIFY_PROTO_ID,
        LANTERN_PEER_DIAL_TIMEOUT_MS,
        &stream);

    if (rc == 0 && stream) {
        libp2p_stream_free(stream);
        lantern_log_debug(
            "network",
            &(const struct lantern_log_metadata){
                .validator = client->node_id,
                .peer = peer_label},
            "identify dial succeeded addr=%s",
            multiaddr);
        return;
    }

    if (stream) {
        libp2p_stream_free(stream);
    }

    lantern_log_trace(
        "network",
        &(const struct lantern_log_metadata){
            .validator = client->node_id,
            .peer = peer_label},
        "identify dial failed rc=%d addr=%s",
        rc,
        multiaddr);
}

/* Attempt to redial a peer that disconnected due to a timeout.
 * This searches the genesis ENRs for a matching peer_id and redials if found. */
static void redial_peer_on_timeout(struct lantern_client *client, const peer_id_t *peer) {
    if (!client || !client->network.host || !peer) {
        return;
    }

    const struct lantern_enr_record_list *enrs = &client->genesis.enrs;
    if (!enrs || enrs->count == 0) {
        return;
    }

    char peer_text[128];
    peer_text[0] = '\0';
    if (peer_id_to_string(peer, PEER_ID_FMT_BASE58_LEGACY, peer_text, sizeof(peer_text)) < 0) {
        peer_text[0] = '\0';
    }

    /* Search for the peer in genesis ENRs */
    for (size_t idx = 0; idx < enrs->count; ++idx) {
        const struct lantern_enr_record *record = &enrs->records[idx];
        if (!record || !record->encoded) {
            continue;
        }

        char multiaddr[256];
        peer_id_t enr_peer_id = {0};
        if (lantern_libp2p_enr_to_multiaddr(record, multiaddr, sizeof(multiaddr), &enr_peer_id) != 0) {
            continue;
        }

        int eq = peer_id_equals(peer, &enr_peer_id);
        peer_id_destroy(&enr_peer_id);

        if (eq == 1) {
            /* Found matching peer in genesis, redial */
            lantern_log_info(
                "network",
                &(const struct lantern_log_metadata){
                    .validator = client->node_id,
                    .peer = peer_text[0] ? peer_text : NULL,
                },
                "redialing peer after timeout disconnect addr=%s",
                multiaddr);

            (void)lantern_libp2p_host_add_enr_peer(&client->network, record, LANTERN_LIBP2P_DEFAULT_PEER_TTL_MS);
            identify_dial_multiaddr(client, multiaddr, peer_text[0] ? peer_text : record->encoded);
            return;
        }
    }

    /* Peer not found in genesis ENRs - cannot redial */
    lantern_log_trace(
        "network",
        &(const struct lantern_log_metadata){
            .validator = client->node_id,
            .peer = peer_text[0] ? peer_text : NULL,
        },
        "peer not in genesis ENRs, skipping redial");
}

static void peer_dialer_attempt(struct lantern_client *client) {
    if (!client || !client->network.host) {
        return;
    }

    const struct lantern_enr_record_list *enrs = &client->genesis.enrs;
    if (!enrs || enrs->count == 0) {
        return;
    }

    struct lantern_string_list connected_snapshot;
    lantern_string_list_init(&connected_snapshot);

    size_t connected_unique = 0;
    if (client->connection_lock_initialized) {
        if (pthread_mutex_lock(&client->connection_lock) == 0) {
            connected_unique = client->connected_peer_ids.len;
            if (lantern_string_list_copy(&connected_snapshot, &client->connected_peer_ids) != 0) {
                lantern_string_list_reset(&connected_snapshot);
                lantern_string_list_init(&connected_snapshot);
                connected_unique = client->connected_peers;
            }
            pthread_mutex_unlock(&client->connection_lock);
        } else {
            connected_unique = client->connected_peers;
        }
    }

    peer_id_t *local_peer = NULL;
    if (libp2p_host_get_peer_id(client->network.host, &local_peer) != 0) {
        local_peer = NULL;
    }

    size_t target = 0;
    if (enrs->count > 0) {
        target = enrs->count;
        if (local_peer && local_peer->bytes && local_peer->size) {
            if (target > 0) {
                target -= 1;
            }
        }
    }

    if (target > 0 && connected_unique >= target) {
        if (local_peer) {
            peer_id_destroy(local_peer);
            free(local_peer);
        }
        lantern_string_list_reset(&connected_snapshot);
        return;
    }

    for (size_t idx = 0; idx < enrs->count; ++idx) {
        if (__atomic_load_n(&client->dialer_stop_flag, __ATOMIC_RELAXED) != 0) {
            break;
        }

        const struct lantern_enr_record *record = &enrs->records[idx];
        if (!record || !record->encoded) {
            continue;
        }

        char multiaddr[256];
        peer_id_t peer_id = {0};
        if (lantern_libp2p_enr_to_multiaddr(record, multiaddr, sizeof(multiaddr), &peer_id) != 0) {
            continue;
        }

        bool is_self = false;
        if (local_peer) {
            int eq = peer_id_equals(local_peer, &peer_id);
            if (eq == 1) {
                is_self = true;
            }
        }

        if (!is_self) {
            char peer_text[128];
            peer_text[0] = '\0';
            if (peer_id_to_string(&peer_id, PEER_ID_FMT_BASE58_LEGACY, peer_text, sizeof(peer_text)) < 0) {
                peer_text[0] = '\0';
            }

            if (peer_text[0] && string_list_contains(&connected_snapshot, peer_text)) {
                peer_id_destroy(&peer_id);
                continue;
            }

            (void)lantern_libp2p_host_add_enr_peer(&client->network, record, LANTERN_LIBP2P_DEFAULT_PEER_TTL_MS);
            identify_dial_multiaddr(client, multiaddr, peer_text[0] ? peer_text : record->encoded);

            bool already_added = false;
            if (peer_text[0]) {
                already_added = string_list_contains(&client->dialer_peers, peer_text);
            }

            if (client->gossip_running && client->gossip.gossipsub) {
                if (!already_added) {
                    libp2p_err_t perr = libp2p_gossipsub_peering_add(client->gossip.gossipsub, &peer_id);
                    if (perr == LIBP2P_ERR_OK) {
                        if (peer_text[0]) {
                            (void)lantern_string_list_append(&client->dialer_peers, peer_text);
                        }
                        lantern_log_trace(
                            "network",
                            &(const struct lantern_log_metadata){
                                .validator = client->node_id,
                                .peer = peer_text[0] ? peer_text : record->encoded},
                            "dialer added peer to gossipsub peering");
                    }
                }
            }
        }

        peer_id_destroy(&peer_id);
    }

    if (local_peer) {
        peer_id_destroy(local_peer);
        free(local_peer);
    }

    lantern_string_list_reset(&connected_snapshot);
}

static void *peer_dialer_thread(void *arg) {
    struct lantern_client *client = (struct lantern_client *)arg;
    if (!client) {
        return NULL;
    }

    while (__atomic_load_n(&client->dialer_stop_flag, __ATOMIC_RELAXED) == 0) {
        peer_dialer_attempt(client);
        peer_dialer_sleep(client, LANTERN_PEER_DIAL_INTERVAL_SECONDS);
    }
    return NULL;
}

static int start_peer_dialer(struct lantern_client *client) {
    if (!client) {
        return -1;
    }
    if (client->dialer_thread_started) {
        return 0;
    }
    __atomic_store_n(&client->dialer_stop_flag, 0, __ATOMIC_RELAXED);
    int rc = pthread_create(&client->dialer_thread, NULL, peer_dialer_thread, client);
    if (rc != 0) {
        __atomic_store_n(&client->dialer_stop_flag, 1, __ATOMIC_RELAXED);
        return -1;
    }
    client->dialer_thread_started = true;
    return 0;
}

static void stop_peer_dialer(struct lantern_client *client) {
    if (!client) {
        return;
    }
    if (!client->dialer_thread_started) {
        __atomic_store_n(&client->dialer_stop_flag, 1, __ATOMIC_RELAXED);
        return;
    }
    __atomic_store_n(&client->dialer_stop_flag, 1, __ATOMIC_RELAXED);
    (void)pthread_join(client->dialer_thread, NULL);
    client->dialer_thread_started = false;
}

static void connection_events_cb(const libp2p_event_t *evt, void *user_data) {
    if (!evt || !user_data) {
        return;
    }
    struct lantern_client *client = (struct lantern_client *)user_data;
    switch (evt->kind) {
    case LIBP2P_EVT_CONN_OPENED:
        connection_counter_update(client, 1, evt->u.conn_opened.peer, evt->u.conn_opened.inbound, 0);
        if (evt->u.conn_opened.peer) {
            char peer_text[128];
            peer_text[0] = '\0';
            if (peer_id_to_string(evt->u.conn_opened.peer, PEER_ID_FMT_BASE58_LEGACY, peer_text, sizeof(peer_text)) < 0) {
                peer_text[0] = '\0';
            }
            request_status_now(client, evt->u.conn_opened.peer, peer_text[0] ? peer_text : NULL);
        }
        break;
    case LIBP2P_EVT_CONN_CLOSED:
        connection_counter_update(client, -1, evt->u.conn_closed.peer, false, evt->u.conn_closed.reason);
        /* If disconnected due to timeout, attempt to redial the peer */
        if (evt->u.conn_closed.reason == LIBP2P_ERR_TIMEOUT && evt->u.conn_closed.peer) {
            redial_peer_on_timeout(client, evt->u.conn_closed.peer);
        }
        break;
    case LIBP2P_EVT_DIALING: {
        char peer_text[128];
        peer_text[0] = '\0';
        if (evt->u.dialing.peer) {
            if (peer_id_to_string(evt->u.dialing.peer, PEER_ID_FMT_BASE58_LEGACY, peer_text, sizeof(peer_text)) < 0) {
                peer_text[0] = '\0';
            }
        }
        lantern_log_debug(
            "network",
            &(const struct lantern_log_metadata){
                .validator = client->node_id,
                .peer = peer_text[0] ? peer_text : NULL,
            },
            "dialing peer addr=%s",
            evt->u.dialing.addr ? evt->u.dialing.addr : "-");
        break;
    }
    case LIBP2P_EVT_OUTGOING_CONNECTION_ERROR: {
        char peer_text[128];
        peer_text[0] = '\0';
        if (evt->u.outgoing_conn_error.peer) {
            if (peer_id_to_string(evt->u.outgoing_conn_error.peer, PEER_ID_FMT_BASE58_LEGACY, peer_text, sizeof(peer_text)) < 0) {
                peer_text[0] = '\0';
            }
        }
        lantern_log_warn(
            "network",
            &(const struct lantern_log_metadata){
                .validator = client->node_id,
                .peer = peer_text[0] ? peer_text : NULL,
            },
            "outgoing connection error code=%d (%s) msg=%s",
            evt->u.outgoing_conn_error.code,
            connection_reason_text(evt->u.outgoing_conn_error.code),
            evt->u.outgoing_conn_error.msg ? evt->u.outgoing_conn_error.msg : "-");
        break;
    }
    case LIBP2P_EVT_INCOMING_CONNECTION_ERROR: {
        char peer_text[128];
        peer_text[0] = '\0';
        if (evt->u.incoming_conn_error.peer) {
            if (peer_id_to_string(evt->u.incoming_conn_error.peer, PEER_ID_FMT_BASE58_LEGACY, peer_text, sizeof(peer_text)) < 0) {
                peer_text[0] = '\0';
            }
        }
        lantern_log_warn(
            "network",
            &(const struct lantern_log_metadata){
                .validator = client->node_id,
                .peer = peer_text[0] ? peer_text : NULL,
            },
            "incoming connection error code=%d (%s) msg=%s",
            evt->u.incoming_conn_error.code,
            connection_reason_text(evt->u.incoming_conn_error.code),
            evt->u.incoming_conn_error.msg ? evt->u.incoming_conn_error.msg : "-");
        break;
    }
    default:
        break;
    }
}

static const char *connection_reason_text(int reason) {
    switch (reason) {
    case 0:
        return "ok";
    case LIBP2P_ERR_NULL_PTR:
        return "null_ptr";
    case LIBP2P_ERR_AGAIN:
        return "again";
    case LIBP2P_ERR_EOF:
        return "eof";
    case LIBP2P_ERR_TIMEOUT:
        return "timeout";
    case LIBP2P_ERR_CLOSED:
        return "closed";
    case LIBP2P_ERR_RESET:
        return "reset";
    case LIBP2P_ERR_INTERNAL:
        return "internal";
    case LIBP2P_ERR_PROTO_NEGOTIATION_FAILED:
        return "protocol_negotiation_failed";
    case LIBP2P_ERR_MSG_TOO_LARGE:
        return "msg_too_large";
    case LIBP2P_ERR_UNSUPPORTED:
        return "unsupported";
    case LIBP2P_ERR_CANCELED:
        return "canceled";
    default:
        return "unknown";
    }
}

static void persisted_block_list_init(struct lantern_persisted_block_list *list) {
    if (!list) {
        return;
    }
    list->items = NULL;
    list->length = 0;
    list->capacity = 0;
}

static void persisted_block_list_reset(struct lantern_persisted_block_list *list) {
    if (!list) {
        return;
    }
    if (list->items) {
        for (size_t i = 0; i < list->length; ++i) {
            lantern_signed_block_with_attestation_reset(&list->items[i].block);
        }
        free(list->items);
    }
    list->items = NULL;
    list->length = 0;
    list->capacity = 0;
}

static int clone_signed_block(const LanternSignedBlock *source, LanternSignedBlock *dest) {
    if (!source || !dest) {
        return -1;
    }
    lantern_signed_block_with_attestation_init(dest);
    dest->message.block.slot = source->message.block.slot;
    dest->message.block.proposer_index = source->message.block.proposer_index;
    dest->message.block.parent_root = source->message.block.parent_root;
    dest->message.block.state_root = source->message.block.state_root;
    if (lantern_attestations_copy(
            &dest->message.block.body.attestations,
            &source->message.block.body.attestations)
        != 0) {
        lantern_signed_block_with_attestation_reset(dest);
        return -1;
    }
    dest->message.proposer_attestation = source->message.proposer_attestation;
    if (lantern_block_signatures_copy(&dest->signatures, &source->signatures) != 0) {
        lantern_signed_block_with_attestation_reset(dest);
        return -1;
    }
    return 0;
}

static int persisted_block_list_append(
    struct lantern_persisted_block_list *list,
    const LanternSignedBlock *block,
    const LanternRoot *root) {
    if (!list || !block || !root) {
        return -1;
    }
    if (list->length == list->capacity) {
        size_t new_capacity = list->capacity == 0 ? 4u : list->capacity * 2u;
        struct lantern_persisted_block *expanded = realloc(
            list->items,
            new_capacity * sizeof(*expanded));
        if (!expanded) {
            return -1;
        }
        list->items = expanded;
        list->capacity = new_capacity;
    }
    struct lantern_persisted_block *entry = &list->items[list->length];
    if (clone_signed_block(block, &entry->block) != 0) {
        return -1;
    }
    entry->root = *root;
    list->length += 1;
    return 0;
}

static void pending_block_list_init(struct lantern_pending_block_list *list) {
    if (!list) {
        return;
    }
    list->items = NULL;
    list->length = 0;
    list->capacity = 0;
}

static void pending_block_list_reset(struct lantern_pending_block_list *list) {
    if (!list) {
        return;
    }
    if (list->items) {
        for (size_t i = 0; i < list->length; ++i) {
            lantern_signed_block_with_attestation_reset(&list->items[i].block);
        }
        free(list->items);
    }
    list->items = NULL;
    list->length = 0;
    list->capacity = 0;
}

static struct lantern_pending_block *pending_block_list_find(
    struct lantern_pending_block_list *list,
    const LanternRoot *root) {
    if (!list || !root || !list->items) {
        return NULL;
    }
    for (size_t i = 0; i < list->length; ++i) {
        if (memcmp(list->items[i].root.bytes, root->bytes, LANTERN_ROOT_SIZE) == 0) {
            return &list->items[i];
        }
    }
    return NULL;
}

static void pending_block_list_remove(struct lantern_pending_block_list *list, size_t index) {
    if (!list || !list->items || index >= list->length) {
        return;
    }
    struct lantern_pending_block *entry = &list->items[index];
    lantern_signed_block_with_attestation_reset(&entry->block);
    if (index + 1u < list->length) {
        memmove(
            &list->items[index],
            &list->items[index + 1u],
            (list->length - (index + 1u)) * sizeof(*list->items));
    }
    list->length -= 1u;
    if (list->length < list->capacity) {
        /* Do NOT call reset here - memmove has moved the dynamic pointers
           from the last entry to an earlier position. Calling reset would
           double-free those pointers. Just zero the leftover slot. */
        memset(&list->items[list->length], 0, sizeof(*list->items));
    }
}

static struct lantern_pending_block *pending_block_list_append(
    struct lantern_pending_block_list *list,
    const LanternSignedBlock *block,
    const LanternRoot *block_root,
    const LanternRoot *parent_root,
    const char *peer_text) {
    if (!list || !block || !block_root || !parent_root) {
        return NULL;
    }
    if (list->length == list->capacity) {
        size_t new_capacity = list->capacity == 0 ? 4u : list->capacity * 2u;
        struct lantern_pending_block *expanded = realloc(
            list->items,
            new_capacity * sizeof(*expanded));
        if (!expanded) {
            return NULL;
        }
        list->items = expanded;
        list->capacity = new_capacity;
    }
    struct lantern_pending_block *entry = &list->items[list->length];
    if (clone_signed_block(block, &entry->block) != 0) {
        lantern_signed_block_with_attestation_reset(&entry->block);
        memset(entry, 0, sizeof(*entry));
        return NULL;
    }
    entry->root = *block_root;
    entry->parent_root = *parent_root;
    entry->peer_text[0] = '\0';
    entry->parent_requested = false;
    if (peer_text && *peer_text) {
        strncpy(entry->peer_text, peer_text, sizeof(entry->peer_text) - 1u);
        entry->peer_text[sizeof(entry->peer_text) - 1u] = '\0';
    }
    list->length += 1u;
    return entry;
}

static void lantern_client_pending_remove_by_root_locked(struct lantern_client *client, const LanternRoot *root) {
    if (!client || !root) {
        return;
    }
    struct lantern_pending_block_list *list = &client->pending_blocks;
    if (!list->items) {
        return;
    }
    for (size_t i = 0; i < list->length; ++i) {
        if (memcmp(list->items[i].root.bytes, root->bytes, LANTERN_ROOT_SIZE) == 0) {
            pending_block_list_remove(list, i);
            break;
        }
    }
}

static void lantern_client_pending_remove_by_root(struct lantern_client *client, const LanternRoot *root) {
    if (!client || !root) {
        return;
    }
    bool locked = lantern_client_lock_pending(client);
    if (!locked) {
        lantern_client_pending_remove_by_root_locked(client, root);
        return;
    }
    lantern_client_pending_remove_by_root_locked(client, root);
    lantern_client_unlock_pending(client, locked);
}

static void lantern_client_enqueue_pending_block(
    struct lantern_client *client,
    const LanternSignedBlock *block,
    const LanternRoot *block_root,
    const LanternRoot *parent_root,
    const char *peer_text) {
    if (!client || !block || !block_root || !parent_root) {
        return;
    }

    LanternRoot block_root_local = *block_root;
    LanternRoot parent_root_local = *parent_root;
    char schedule_peer[128];
    schedule_peer[0] = '\0';
    bool schedule_parent = false;

    bool locked = lantern_client_lock_pending(client);
    if (!locked) {
        return;
    }

    struct lantern_pending_block_list *list = &client->pending_blocks;
    struct lantern_pending_block *existing = pending_block_list_find(list, &block_root_local);

    if (existing) {
        if (peer_text && *peer_text) {
            if (existing->peer_text[0] == '\0' || strcmp(existing->peer_text, peer_text) != 0) {
                strncpy(existing->peer_text, peer_text, sizeof(existing->peer_text) - 1u);
                existing->peer_text[sizeof(existing->peer_text) - 1u] = '\0';
            }
            /* Do NOT immediately request parent via req/resp - rely on gossip to deliver it.
               req/resp should only be used for sync recovery, not for normal block propagation. */
        }
        lantern_client_unlock_pending(client, locked);
        return;
    }

    if (list->length >= LANTERN_PENDING_BLOCK_LIMIT && list->length > 0) {
        char dropped_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
        format_root_hex(&list->items[0].root, dropped_hex, sizeof(dropped_hex));
        lantern_log_warn(
            "state",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "pending block queue full; dropping oldest root=%s",
            dropped_hex[0] ? dropped_hex : "0x0");
        pending_block_list_remove(list, 0);
    }

    struct lantern_pending_block *entry = pending_block_list_append(list, block, &block_root_local, &parent_root_local, peer_text);
    if (!entry) {
        lantern_client_unlock_pending(client, locked);
        lantern_log_warn(
            "state",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to queue pending block slot=%" PRIu64,
            block->message.block.slot);
        return;
    }

    char block_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    char parent_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    format_root_hex(&block_root_local, block_hex, sizeof(block_hex));
    format_root_hex(&parent_root_local, parent_hex, sizeof(parent_hex));

    struct lantern_log_metadata meta = {
        .validator = client->node_id,
        .peer = peer_text && *peer_text ? peer_text : NULL,
    };

    /* Do NOT immediately request parent via req/resp - rely on gossip to deliver it.
       req/resp should only be used for sync recovery, not for normal block propagation.
       The parent_requested flag is no longer used for immediate requests. */
    entry->parent_requested = false;
    (void)schedule_peer;
    (void)schedule_parent;

    lantern_client_unlock_pending(client, locked);

    lantern_log_info(
        "state",
        &meta,
        "queued block slot=%" PRIu64 " root=%s waiting for parent=%s (via gossip)",
        block->message.block.slot,
        block_hex[0] ? block_hex : "0x0",
        parent_hex[0] ? parent_hex : "0x0");
}

static void lantern_client_process_pending_children(struct lantern_client *client, const LanternRoot *parent_root) {
    if (!client || !parent_root) {
        return;
    }
    while (true) {
        LanternSignedBlock replay;
        LanternRoot child_root;
        char peer_copy[128];
        bool have_replay = false;

        bool locked = lantern_client_lock_pending(client);
        if (!locked) {
            return;
        }

        for (size_t i = 0; i < client->pending_blocks.length; ++i) {
            struct lantern_pending_block *entry = &client->pending_blocks.items[i];
            if (memcmp(entry->parent_root.bytes, parent_root->bytes, LANTERN_ROOT_SIZE) != 0) {
                continue;
            }
            if (clone_signed_block(&entry->block, &replay) != 0) {
                lantern_log_warn(
                    "state",
                    &(const struct lantern_log_metadata){.validator = client->node_id},
                    "failed to clone pending child block for replay");
            } else {
                child_root = entry->root;
                peer_copy[0] = '\0';
                if (entry->peer_text[0]) {
                    strncpy(peer_copy, entry->peer_text, sizeof(peer_copy) - 1u);
                    peer_copy[sizeof(peer_copy) - 1u] = '\0';
                }
                have_replay = true;
            }
            pending_block_list_remove(&client->pending_blocks, i);
            break;
        }

        lantern_client_unlock_pending(client, locked);

        if (!have_replay) {
            break;
        }

        struct lantern_log_metadata meta = {
            .validator = client->node_id,
            .peer = peer_copy[0] ? peer_copy : NULL,
        };
        (void)lantern_client_import_block(client, &replay, &child_root, &meta);
        lantern_signed_block_with_attestation_reset(&replay);
    }
}

static int collect_block_visitor(
    const LanternSignedBlock *block,
    const LanternRoot *root,
    void *context) {
    if (!context) {
        return -1;
    }
    struct lantern_persisted_block_list *list = context;
    return persisted_block_list_append(list, block, root);
}

static int compare_blocks_by_slot(const void *lhs_ptr, const void *rhs_ptr) {
    const struct lantern_persisted_block *lhs = lhs_ptr;
    const struct lantern_persisted_block *rhs = rhs_ptr;
    if (lhs->block.message.block.slot < rhs->block.message.block.slot) {
        return -1;
    }
    if (lhs->block.message.block.slot > rhs->block.message.block.slot) {
        return 1;
    }
    return memcmp(lhs->root.bytes, rhs->root.bytes, LANTERN_ROOT_SIZE);
}

static void local_validator_cleanup(struct lantern_local_validator *validator) {
    if (!validator) {
        return;
    }
    if (validator->secret && validator->secret_len > 0) {
        lantern_secure_zero(validator->secret, validator->secret_len);
        free(validator->secret);
    }
    validator->secret = NULL;
    validator->secret_len = 0;
    validator->has_secret = false;
    if (validator->secret_key) {
        pq_secret_key_free(validator->secret_key);
        validator->secret_key = NULL;
    }
    validator->has_secret_handle = false;
    validator->last_proposed_slot = UINT64_MAX;
    validator->last_attested_slot = UINT64_MAX;
    validator->has_pending_attestation = false;
    validator->pending_attestation_slot = UINT64_MAX;
    memset(&validator->pending_attestation, 0, sizeof(validator->pending_attestation));
}

static void reset_local_validators(struct lantern_client *client) {
    if (!client) {
        return;
    }
    if (client->local_validators) {
        for (size_t i = 0; i < client->local_validator_count; ++i) {
            local_validator_cleanup(&client->local_validators[i]);
        }
        free(client->local_validators);
        client->local_validators = NULL;
    }
    client->local_validator_count = 0;
}

static int decode_validator_secret(const char *hex, uint8_t **out_key, size_t *out_len) {
    if (!hex || !out_key || !out_len) {
        return -1;
    }

    char *dup = lantern_string_duplicate(hex);
    if (!dup) {
        return -1;
    }
    char *trimmed = lantern_trim_whitespace(dup);
    if (!trimmed || *trimmed == '\0') {
        lantern_secure_zero(dup, strlen(dup));
        free(dup);
        return -1;
    }

    const char *hex_start = trimmed;
    if (hex_start[0] == '0' && (hex_start[1] == 'x' || hex_start[1] == 'X')) {
        hex_start += 2;
    }
    size_t hex_len = strlen(hex_start);
    if (hex_len == 0 || (hex_len % 2) != 0) {
        lantern_secure_zero(dup, strlen(dup));
        free(dup);
        return -1;
    }

    size_t secret_len = hex_len / 2;
    uint8_t *secret = malloc(secret_len);
    if (!secret) {
        lantern_secure_zero(dup, strlen(dup));
        free(dup);
        return -1;
    }

    if (lantern_hex_decode(trimmed, secret, secret_len) != 0) {
        lantern_secure_zero(secret, secret_len);
        free(secret);
        lantern_secure_zero(dup, strlen(dup));
        free(dup);
        return -1;
    }

    lantern_secure_zero(dup, strlen(dup));
    free(dup);

    *out_key = secret;
    *out_len = secret_len;
    return 0;
}

struct hash_sig_manifest_entry {
    uint64_t index;
    char *public_file;
    char *secret_file;
};

struct hash_sig_manifest {
    struct hash_sig_manifest_entry *entries;
    size_t count;
};

static void hash_sig_manifest_init(struct hash_sig_manifest *manifest) {
    if (!manifest) {
        return;
    }
    manifest->entries = NULL;
    manifest->count = 0;
}

static void hash_sig_manifest_reset(struct hash_sig_manifest *manifest) {
    if (!manifest || !manifest->entries) {
        return;
    }
    for (size_t i = 0; i < manifest->count; ++i) {
        free(manifest->entries[i].public_file);
        free(manifest->entries[i].secret_file);
    }
    free(manifest->entries);
    manifest->entries = NULL;
    manifest->count = 0;
}

static const char *hash_sig_yaml_value(const LanternYamlObject *object, const char *key) {
    if (!object || !key || !object->pairs) {
        return NULL;
    }
    for (size_t i = 0; i < object->num_pairs; ++i) {
        if (object->pairs[i].key && strcmp(object->pairs[i].key, key) == 0) {
            return object->pairs[i].value;
        }
    }
    return NULL;
}

static int hash_sig_parse_u64(const char *text, uint64_t *out_value) {
    if (!text || !out_value) {
        return -1;
    }
    char *end = NULL;
    errno = 0;
    unsigned long long parsed = strtoull(text, &end, 0);
    if (errno != 0 || end == text) {
        return -1;
    }
    *out_value = (uint64_t)parsed;
    return 0;
}

static int hash_sig_manifest_load(const char *dir, struct hash_sig_manifest *manifest) {
    if (!dir || !manifest) {
        return -1;
    }
    hash_sig_manifest_reset(manifest);

    char *manifest_path = NULL;
    size_t dir_len = strlen(dir);
    const char *filename = "validator-keys-manifest.yaml";
    size_t filename_len = strlen(filename);
    bool need_sep = dir_len > 0 && dir[dir_len - 1] != '/' && dir[dir_len - 1] != '\\';
    size_t total = dir_len + (need_sep ? 1 : 0) + filename_len + 1;
    manifest_path = malloc(total);
    if (!manifest_path) {
        return -1;
    }
    memcpy(manifest_path, dir, dir_len);
    size_t offset = dir_len;
    if (need_sep) {
        manifest_path[offset++] = '/';
    }
    memcpy(manifest_path + offset, filename, filename_len);
    manifest_path[offset + filename_len] = '\0';

    size_t count = 0;
    LanternYamlObject *objects = lantern_yaml_read_array(manifest_path, "validators", &count);
    free(manifest_path);
    manifest_path = NULL;
    if (!objects || count == 0) {
        lantern_yaml_free_objects(objects, count);
        return -1;
    }

    struct hash_sig_manifest_entry *entries = calloc(count, sizeof(*entries));
    if (!entries) {
        lantern_yaml_free_objects(objects, count);
        return -1;
    }

    for (size_t i = 0; i < count; ++i) {
        const char *index_text = hash_sig_yaml_value(&objects[i], "index");
        const char *public_file = hash_sig_yaml_value(&objects[i], "public_key_file");
        const char *secret_file = hash_sig_yaml_value(&objects[i], "secret_key_file");
        if (!index_text || !public_file || !secret_file) {
            lantern_yaml_free_objects(objects, count);
            hash_sig_manifest_reset(&(struct hash_sig_manifest){.entries = entries, .count = count});
            return -1;
        }
        uint64_t index = 0;
        if (hash_sig_parse_u64(index_text, &index) != 0) {
            lantern_yaml_free_objects(objects, count);
            hash_sig_manifest_reset(&(struct hash_sig_manifest){.entries = entries, .count = count});
            return -1;
        }
        entries[i].index = index;
        entries[i].public_file = lantern_string_duplicate(public_file);
        entries[i].secret_file = lantern_string_duplicate(secret_file);
        if (!entries[i].public_file || !entries[i].secret_file) {
            lantern_yaml_free_objects(objects, count);
            hash_sig_manifest_reset(&(struct hash_sig_manifest){.entries = entries, .count = count});
            return -1;
        }
    }

    lantern_yaml_free_objects(objects, count);
    manifest->entries = entries;
    manifest->count = count;
    return 0;
}

static const struct hash_sig_manifest_entry *hash_sig_manifest_find(
    const struct hash_sig_manifest *manifest,
    uint64_t index) {
    if (!manifest || !manifest->entries) {
        return NULL;
    }
    for (size_t i = 0; i < manifest->count; ++i) {
        if (manifest->entries[i].index == index) {
            return &manifest->entries[i];
        }
    }
    return NULL;
}

static const char *hash_sig_non_empty(const char *value) {
    return (value && value[0] != '\0') ? value : NULL;
}

static int hash_sig_join_path(const char *dir, const char *leaf, char **out_path) {
    if (!dir || !leaf || !out_path) {
        return -1;
    }
    size_t dir_len = strlen(dir);
    size_t leaf_len = strlen(leaf);
    bool need_sep = dir_len > 0 && dir[dir_len - 1] != '/' && dir[dir_len - 1] != '\\';
    size_t total = dir_len + (need_sep ? 1 : 0) + leaf_len + 1;
    char *buffer = malloc(total);
    if (!buffer) {
        return -1;
    }
    memcpy(buffer, dir, dir_len);
    size_t offset = dir_len;
    if (need_sep) {
        buffer[offset++] = '/';
    }
    memcpy(buffer + offset, leaf, leaf_len);
    buffer[offset + leaf_len] = '\0';
    *out_path = buffer;
    return 0;
}

static int hash_sig_format_index_template(const char *template, uint64_t index, char **out_path) {
    if (!template || !out_path) {
        return -1;
    }
    unsigned long long value = (unsigned long long)index;
    int required = snprintf(NULL, 0, template, value);
    if (required < 0) {
        return -1;
    }
    size_t length = (size_t)required + 1u;
    char *buffer = malloc(length);
    if (!buffer) {
        return -1;
    }
    if (snprintf(buffer, length, template, value) < 0) {
        free(buffer);
        return -1;
    }
    *out_path = buffer;
    return 0;
}

static char *hash_sig_derive_default_dir(const struct lantern_genesis_paths *paths) {
    if (!paths || !paths->validator_config_path) {
        return NULL;
    }
    const char *config_path = paths->validator_config_path;
    const char *slash = strrchr(config_path, '/');
    const char *backslash = strrchr(config_path, '\\');
    const char *sep = slash;
    if (backslash && (!sep || backslash > sep)) {
        sep = backslash;
    }
    if (!sep) {
        return NULL;
    }
    size_t dir_len = (size_t)(sep - config_path);
    if (dir_len == 0) {
        return NULL;
    }
    const char *suffix = "hash-sig-keys";
    size_t suffix_len = strlen(suffix);
    size_t total = dir_len + 1 + suffix_len + 1;
    char *buffer = malloc(total);
    if (!buffer) {
        return NULL;
    }
    memcpy(buffer, config_path, dir_len);
    buffer[dir_len] = '/';
    memcpy(buffer + dir_len + 1, suffix, suffix_len);
    buffer[dir_len + 1 + suffix_len] = '\0';
    return buffer;
}

static void clear_local_secret_handles(struct lantern_client *client) {
    if (!client || !client->local_validators) {
        return;
    }
    for (size_t i = 0; i < client->local_validator_count; ++i) {
        struct lantern_local_validator *validator = &client->local_validators[i];
        if (validator->secret_key) {
            pq_secret_key_free(validator->secret_key);
            validator->secret_key = NULL;
        }
        validator->has_secret_handle = false;
    }
}

static bool hash_sig_path_is_absolute(const char *path) {
    if (!path || path[0] == '\0') {
        return false;
    }
    if (path[0] == '/' || path[0] == '\\') {
        return true;
    }
    if (strlen(path) >= 3 && isalpha((unsigned char)path[0]) && path[1] == ':' && (path[2] == '/' || path[2] == '\\')) {
        return true;
    }
    return false;
}

static int resolve_public_key_path(
    struct lantern_client *client,
    const struct hash_sig_manifest *manifest,
    uint64_t index,
    char **out_path) {
    if (!client || !out_path) {
        return -1;
    }
    if (client->hash_sig_public_template) {
        return hash_sig_format_index_template(client->hash_sig_public_template, index, out_path);
    }
    if (manifest) {
        const struct hash_sig_manifest_entry *entry = hash_sig_manifest_find(manifest, index);
        if (entry && entry->public_file) {
            if (hash_sig_path_is_absolute(entry->public_file)) {
                char *copy = lantern_string_duplicate(entry->public_file);
                if (!copy) {
                    return -1;
                }
                *out_path = copy;
                return 0;
            }
            if (client->hash_sig_key_dir) {
                return hash_sig_join_path(client->hash_sig_key_dir, entry->public_file, out_path);
            }
        }
    }
    if (client->hash_sig_key_dir) {
        char filename[64];
        int written = snprintf(filename, sizeof(filename), "validator_%" PRIu64 "_pk.json", index);
        if (written < 0 || (size_t)written >= sizeof(filename)) {
            return -1;
        }
        return hash_sig_join_path(client->hash_sig_key_dir, filename, out_path);
    }
    if (client->hash_sig_public_path && client->genesis.chain_config.validator_count == 1) {
        char *copy = lantern_string_duplicate(client->hash_sig_public_path);
        if (!copy) {
            return -1;
        }
        *out_path = copy;
        return 0;
    }
    return -1;
}

static int resolve_secret_key_path(
    struct lantern_client *client,
    const struct hash_sig_manifest *manifest,
    uint64_t index,
    char **out_path) {
    if (!client || !out_path) {
        return -1;
    }
    if (client->hash_sig_secret_template) {
        return hash_sig_format_index_template(client->hash_sig_secret_template, index, out_path);
    }
    if (manifest) {
        const struct hash_sig_manifest_entry *entry = hash_sig_manifest_find(manifest, index);
        if (entry && entry->secret_file) {
            if (hash_sig_path_is_absolute(entry->secret_file)) {
                char *copy = lantern_string_duplicate(entry->secret_file);
                if (!copy) {
                    return -1;
                }
                *out_path = copy;
                return 0;
            }
            if (client->hash_sig_key_dir) {
                return hash_sig_join_path(client->hash_sig_key_dir, entry->secret_file, out_path);
            }
        }
    }
    if (client->hash_sig_key_dir) {
        char filename[64];
        int written = snprintf(filename, sizeof(filename), "validator_%" PRIu64 "_sk.json", index);
        if (written < 0 || (size_t)written >= sizeof(filename)) {
            return -1;
        }
        return hash_sig_join_path(client->hash_sig_key_dir, filename, out_path);
    }
    if (client->hash_sig_secret_path) {
        if (client->validator_assignment.count > 1) {
            return -1;
        }
        char *copy = lantern_string_duplicate(client->hash_sig_secret_path);
        if (!copy) {
            return -1;
        }
        *out_path = copy;
        return 0;
    }
    return -1;
}

// Note: load_hash_sig_public_keys removed - per LeanSpec, signature verification
// uses 52-byte serialized pubkeys from state, not full JSON public key handles.

static int load_hash_sig_secret_keys(struct lantern_client *client, const struct hash_sig_manifest *manifest) {
    if (!client) {
        return -1;
    }
    if (client->local_validator_count == 0) {
        return 0;
    }

    bool has_template = client->hash_sig_secret_template != NULL;
    bool has_dir = client->hash_sig_key_dir != NULL;
    bool has_single = client->hash_sig_secret_path != NULL && client->validator_assignment.count == 1;
    if (!has_template && !has_dir && !has_single) {
        lantern_log_debug(
            "crypto",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "hash-sig secret key sources unavailable; skipping local key load");
        return 0;
    }

    clear_local_secret_handles(client);
    struct lantern_log_metadata meta = {.validator = client->node_id};
    size_t resolved = 0;
    size_t loaded = 0;
    for (size_t i = 0; i < client->local_validator_count; ++i) {
        struct lantern_local_validator *validator = &client->local_validators[i];
        char *path = NULL;
        if (resolve_secret_key_path(client, manifest, validator->global_index, &path) != 0) {
            lantern_log_warn(
                "crypto",
                &meta,
                "unable to resolve hash-sig secret key path for validator=%" PRIu64 "; skipping",
                validator->global_index);
            continue;
        }
        ++resolved;
        lantern_log_debug(
            "crypto",
            &meta,
            "hash-sig secret key resolved validator=%" PRIu64 " path=%s",
            validator->global_index,
            path);
        struct PQSignatureSchemeSecretKey *secret = NULL;
        if (lantern_hash_sig_load_secret_file(path, &secret) != 0) {
            lantern_log_warn(
                "crypto",
                &meta,
                "failed to load hash-sig secret key validator=%" PRIu64 " path=%s; skipping",
                validator->global_index,
                path);
            free(path);
            continue;
        }
        free(path);
        validator->secret_key = secret;
        validator->has_secret_handle = true;
        ++loaded;
    }
    lantern_log_info(
        "crypto",
        &meta,
        "hash-sig secret keys loaded=%zu/%zu resolved=%zu dir=%s template=%s",
        loaded,
        client->local_validator_count,
        resolved,
        client->hash_sig_key_dir ? client->hash_sig_key_dir : "-",
        client->hash_sig_secret_template ? client->hash_sig_secret_template : "-");
    return 0;
}

static int load_hash_sig_keys(struct lantern_client *client) {
    if (!client) {
        return -1;
    }
    struct lantern_log_metadata meta = {.validator = client->node_id};
    if (!lantern_hash_sig_is_available()) {
        lantern_log_error(
            "crypto",
            &meta,
            "hash-sig bindings unavailable");
        return -1;
    }

    struct hash_sig_manifest manifest;
    hash_sig_manifest_init(&manifest);
    bool manifest_loaded = false;
    if (client->hash_sig_key_dir && hash_sig_manifest_load(client->hash_sig_key_dir, &manifest) == 0) {
        manifest_loaded = true;
    }

    const struct hash_sig_manifest *manifest_ptr = manifest_loaded ? &manifest : NULL;
    lantern_log_info(
        "crypto",
        &meta,
        "hash-sig load start key_dir=%s manifest=%s validators=%" PRIu64 " local=%zu",
        client->hash_sig_key_dir ? client->hash_sig_key_dir : "-",
        manifest_loaded ? "loaded" : "missing",
        client->genesis.chain_config.validator_count,
        client->local_validator_count);
    // Note: load_hash_sig_public_keys removed - per LeanSpec, verification uses
    // 52-byte serialized pubkeys from state, not full JSON key handles
    if (client->local_validator_count > 0) {
        if (load_hash_sig_secret_keys(client, manifest_ptr) != 0) {
            hash_sig_manifest_reset(&manifest);
            return -1;
        }
    }
    hash_sig_manifest_reset(&manifest);
    return 0;
}

static void free_hash_sig_pubkeys(struct lantern_client *client) {
    if (!client || !client->validator_pubkeys) {
        return;
    }
    for (size_t i = 0; i < client->validator_pubkey_count; ++i) {
        if (client->validator_pubkeys[i]) {
            pq_public_key_free(client->validator_pubkeys[i]);
            client->validator_pubkeys[i] = NULL;
        }
    }
    free(client->validator_pubkeys);
    client->validator_pubkeys = NULL;
    client->validator_pubkey_count = 0;
}

// Note: lantern_client_pubkey_handle removed - per LeanSpec, verification uses
// 52-byte serialized pubkeys from state, not pre-loaded JSON key handles.

static int configure_hash_sig_sources(struct lantern_client *client, const struct lantern_client_options *options) {
    if (!client || !options) {
        return -1;
    }
    struct lantern_log_metadata meta = {.validator = client->node_id};
    const char *env_dir = hash_sig_non_empty(getenv("HASH_SIG_KEY_DIR"));
    const char *env_public_path = hash_sig_non_empty(getenv("HASH_SIG_PK_PATH"));
    const char *env_secret_path = hash_sig_non_empty(getenv("HASH_SIG_SK_PATH"));
    const char *env_public_template = hash_sig_non_empty(getenv("HASH_SIG_PK_TEMPLATE"));
    const char *env_secret_template = hash_sig_non_empty(getenv("HASH_SIG_SK_TEMPLATE"));

    const char *resolved_dir = hash_sig_non_empty(options->hash_sig_key_dir);
    if (!resolved_dir) {
        resolved_dir = env_dir;
    }
    if (!resolved_dir && client->assigned_validators && client->assigned_validators->hash_sig_dir) {
        resolved_dir = client->assigned_validators->hash_sig_dir;
    }
    if (resolved_dir) {
        if (set_owned_string(&client->hash_sig_key_dir, resolved_dir) != 0) {
            return -1;
        }
    } else {
        char *derived = hash_sig_derive_default_dir(&client->genesis_paths);
        if (derived) {
            int rc = set_owned_string(&client->hash_sig_key_dir, derived);
            free(derived);
            if (rc != 0) {
                return -1;
            }
        }
    }

    const char *resolved_public_template = hash_sig_non_empty(options->hash_sig_public_template);
    if (!resolved_public_template) {
        resolved_public_template = env_public_template;
    }
    if (resolved_public_template) {
        if (set_owned_string(&client->hash_sig_public_template, resolved_public_template) != 0) {
            return -1;
        }
    }

    const char *resolved_secret_template = hash_sig_non_empty(options->hash_sig_secret_template);
    if (!resolved_secret_template) {
        resolved_secret_template = env_secret_template;
    }
    if (resolved_secret_template) {
        if (set_owned_string(&client->hash_sig_secret_template, resolved_secret_template) != 0) {
            return -1;
        }
    }

    const char *resolved_public_path = hash_sig_non_empty(options->hash_sig_public_path);
    if (!resolved_public_path) {
        resolved_public_path = env_public_path;
    }
    if (resolved_public_path) {
        if (set_owned_string(&client->hash_sig_public_path, resolved_public_path) != 0) {
            return -1;
        }
    }

    const char *resolved_secret_path = hash_sig_non_empty(options->hash_sig_secret_path);
    if (!resolved_secret_path) {
        resolved_secret_path = env_secret_path;
    }
    if (resolved_secret_path) {
        if (set_owned_string(&client->hash_sig_secret_path, resolved_secret_path) != 0) {
            return -1;
        }
    }
    lantern_log_info(
        "crypto",
        &meta,
        "hash-sig sources resolved dir=%s pk_path=%s sk_path=%s pk_template=%s sk_template=%s",
        client->hash_sig_key_dir ? client->hash_sig_key_dir : "-",
        client->hash_sig_public_path ? client->hash_sig_public_path : "-",
        client->hash_sig_secret_path ? client->hash_sig_secret_path : "-",
        client->hash_sig_public_template ? client->hash_sig_public_template : "-",
        client->hash_sig_secret_template ? client->hash_sig_secret_template : "-");
    return 0;
}

void lantern_client_options_init(struct lantern_client_options *options) {
    if (!options) {
        return;
    }

    options->data_dir = LANTERN_DEFAULT_DATA_DIR;
    options->genesis_config_path = LANTERN_DEFAULT_GENESIS_CONFIG;
    options->validator_registry_path = LANTERN_DEFAULT_VALIDATOR_REGISTRY;
    options->nodes_path = LANTERN_DEFAULT_NODES_FILE;
    options->genesis_state_path = LANTERN_DEFAULT_GENESIS_STATE;
    options->validator_config_path = LANTERN_DEFAULT_VALIDATOR_CONFIG;
    options->node_id = LANTERN_DEFAULT_NODE_ID;
    options->node_key_hex = NULL;
    options->node_key_path = NULL;
    options->listen_address = LANTERN_DEFAULT_LISTEN_ADDR;
    options->http_port = LANTERN_DEFAULT_HTTP_PORT;
    options->metrics_port = LANTERN_DEFAULT_METRICS_PORT;
    options->devnet = LANTERN_DEFAULT_DEVNET;
    lantern_string_list_init(&options->bootnodes);
    options->hash_sig_key_dir = NULL;
    options->hash_sig_public_path = NULL;
    options->hash_sig_secret_path = NULL;
    options->hash_sig_public_template = NULL;
    options->hash_sig_secret_template = NULL;
}

void lantern_client_options_free(struct lantern_client_options *options) {
    if (!options) {
        return;
    }
    lantern_string_list_reset(&options->bootnodes);
}

int lantern_client_options_add_bootnode(struct lantern_client_options *options, const char *bootnode) {
    if (!options || !bootnode) {
        return -1;
    }
    return lantern_string_list_append(&options->bootnodes, bootnode);
}

int lantern_init(struct lantern_client *client, const struct lantern_client_options *options) {
    if (!client || !options) {
        return -1;
    }

    memset(client, 0, sizeof(*client));
    lantern_string_list_init(&client->bootnodes);
    lantern_string_list_init(&client->dialer_peers);
    lantern_string_list_init(&client->connected_peer_ids);
    lantern_string_list_init(&client->status_failure_peer_ids);
    lantern_genesis_artifacts_init(&client->genesis);
    lantern_enr_record_init(&client->local_enr);
    lantern_libp2p_host_init(&client->network);
    client->ping_server = NULL;
    client->ping_running = false;
    lantern_gossipsub_service_init(&client->gossip);
    lantern_reqresp_service_init(&client->reqresp);
    client->reqresp_running = false;
    lantern_validator_assignment_reset(&client->validator_assignment);
    client->has_validator_assignment = false;
    lantern_consensus_runtime_reset(&client->runtime);
    client->has_runtime = false;
    lantern_metrics_server_init(&client->metrics_server);
    client->metrics_running = false;
    lantern_http_server_init(&client->http_server);
    client->http_running = false;
    lantern_state_init(&client->state);
    lean_metrics_reset();
    client->state_lock_initialized = false;
    lantern_fork_choice_init(&client->fork_choice);
    client->has_fork_choice = false;
    client->dialer_thread_started = false;
    client->dialer_stop_flag = 1;
    pending_block_list_init(&client->pending_blocks);
    client->pending_lock_initialized = false;
    if (pthread_mutex_init(&client->pending_lock, NULL) != 0) {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to initialize pending block lock");
        goto error;
    }
    client->pending_lock_initialized = true;

    if (set_owned_string(&client->data_dir, options->data_dir) != 0) {
        goto error;
    }
    if (set_owned_string(&client->node_id, options->node_id) != 0) {
        goto error;
    }
    lantern_log_set_node_id(client->node_id);
    if (set_owned_string(&client->listen_address, options->listen_address) != 0) {
        goto error;
    }
    if (set_owned_string(&client->devnet, options->devnet) != 0) {
        goto error;
    }
    const char *disable_guard_env = getenv("LANTERN_DEBUG_DISABLE_STATUS_GUARD");
    if (disable_guard_env && disable_guard_env[0] != '\0' && !(disable_guard_env[0] == '0' && disable_guard_env[1] == '\0')) {
        client->status_guard_disabled = true;
        lantern_log_warn(
            "reqresp",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "status guard disabled via LANTERN_DEBUG_DISABLE_STATUS_GUARD=\"%s\"",
            disable_guard_env);
    }
    if (!client->status_lock_initialized) {
        if (pthread_mutex_init(&client->status_lock, NULL) != 0) {
            lantern_log_error(
                "client",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "failed to initialize peer status lock");
            goto error;
        }
        client->status_lock_initialized = true;
    }
    if (!client->state_lock_initialized) {
        if (pthread_mutex_init(&client->state_lock, NULL) != 0) {
            lantern_log_error(
                "client",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "failed to initialize state lock");
            goto error;
        }
        client->state_lock_initialized = true;
    }
    if (!client->peer_vote_lock_initialized) {
        if (pthread_mutex_init(&client->peer_vote_lock, NULL) != 0) {
            lantern_log_error(
                "client",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "failed to initialize vote metrics lock");
            goto error;
        }
        client->peer_vote_lock_initialized = true;
    }
    client->http_port = options->http_port;
    client->metrics_port = options->metrics_port;
    if (lantern_storage_prepare(client->data_dir) != 0) {
        lantern_log_error(
            "storage",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to prepare data directory '%s'",
            client->data_dir);
        goto error;
    }

    if (lantern_string_list_copy(&client->bootnodes, &options->bootnodes) != 0) {
        goto error;
    }

    if (copy_genesis_paths(&client->genesis_paths, options) != 0) {
        goto error;
    }

    if (lantern_genesis_load(&client->genesis, &client->genesis_paths) != 0) {
        goto error;
    }
    if (lantern_validator_config_assign_ranges(
            &client->genesis.validator_config,
            client->genesis.chain_config.validator_count)
        != 0) {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "validator-config does not cover %" PRIu64 " validators",
            client->genesis.chain_config.validator_count);
        goto error;
    }
    if (lantern_validator_config_apply_assignments(
            &client->genesis.validator_config,
            client->genesis_paths.validator_registry_path,
            client->genesis.chain_config.validator_count)
        != 0) {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "validator assignment mapping invalid or incomplete");
        goto error;
    }

    bool loaded_from_storage = false;
    int storage_state_rc = lantern_storage_load_state(client->data_dir, &client->state);
    if (storage_state_rc == 0) {
        client->has_state = true;
        loaded_from_storage = true;
    } else if (storage_state_rc < 0) {
        lantern_log_error(
            "storage",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to load persisted state");
        goto error;
    } else {
        bool decoded_genesis = false;
        /* Prefer constructing genesis from config/validators like Zeam does. */
        if (client->genesis.chain_config.validator_pubkeys
            && client->genesis.chain_config.validator_pubkeys_count > 0) {
            size_t vcount = client->genesis.chain_config.validator_pubkeys_count;
            if (lantern_state_generate_genesis(
                    &client->state, client->genesis.chain_config.genesis_time, vcount)
                == 0
                && lantern_state_set_validator_pubkeys(
                       &client->state, client->genesis.chain_config.validator_pubkeys, vcount)
                       == 0) {
                decoded_genesis = true;
                client->genesis_fallback_used = false;
            }
        } else if (client->genesis.state_bytes && client->genesis.state_size > 0
                   && lantern_ssz_decode_state(&client->state, client->genesis.state_bytes, client->genesis.state_size) == 0) {
            decoded_genesis = true;
            client->genesis_fallback_used = false;
        } else {
            lantern_log_warn(
                "client",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "failed to decode genesis state; attempting to synthesize genesis from config");
            /* Fallback: synthesize a minimal genesis state using chain config + validator registry,
               mirroring Zeam's genesis handling. */
            size_t vcount = client->genesis.validator_registry.count;
            if (vcount != client->genesis.chain_config.validator_count || vcount == 0) {
                lantern_log_warn(
                    "client",
                    &(const struct lantern_log_metadata){.validator = client->node_id},
                    "validator registry count (%zu) does not match chain config (%" PRIu64 "), cannot build genesis",
                    vcount,
                    client->genesis.chain_config.validator_count);
            } else if (lantern_state_generate_genesis(
                           &client->state, client->genesis.chain_config.genesis_time, vcount)
                       == 0) {
                uint8_t *pubkeys = calloc(vcount, LANTERN_VALIDATOR_PUBKEY_SIZE);
                if (!pubkeys) {
                    lantern_log_error(
                        "client",
                        &(const struct lantern_log_metadata){.validator = client->node_id},
                        "failed to allocate validator pubkey buffer");
                } else {
                    bool pubkey_ok = true;
                    for (size_t i = 0; i < vcount; ++i) {
                        const struct lantern_validator_record *rec = &client->genesis.validator_registry.records[i];
                        if (rec->has_pubkey_bytes) {
                            memcpy(pubkeys + (i * LANTERN_VALIDATOR_PUBKEY_SIZE), rec->pubkey_bytes, LANTERN_VALIDATOR_PUBKEY_SIZE);
                        } else if (rec->pubkey_hex
                                   && lantern_hex_decode(
                                          rec->pubkey_hex,
                                          pubkeys + (i * LANTERN_VALIDATOR_PUBKEY_SIZE),
                                          LANTERN_VALIDATOR_PUBKEY_SIZE)
                                          == 0) {
                            /* decoded */
                        } else {
                            lantern_log_error(
                                "client",
                                &(const struct lantern_log_metadata){.validator = client->node_id},
                                "missing or invalid pubkey for validator index=%zu; aborting genesis build",
                                i);
                            pubkey_ok = false;
                            break;
                        }
                    }
                    if (pubkey_ok && lantern_state_set_validator_pubkeys(&client->state, pubkeys, vcount) == 0) {
                        decoded_genesis = true;
                        client->genesis_fallback_used = true;
                    }
                    free(pubkeys);
                }
            }
        }
        if (decoded_genesis) {
            if (lantern_state_prepare_validator_votes(&client->state, client->state.config.num_validators) != 0) {
                lantern_log_error(
                    "client",
                    &(const struct lantern_log_metadata){.validator = client->node_id},
                    "failed to prepare validator vote records");
                goto error;
            }
            LanternRoot header_root;
            LanternRoot original_header_state_root = client->state.latest_block_header.state_root;
            LanternRoot state_root;
            LanternRoot genesis_block_root;
            LanternRoot genesis_signed_block_root;
            LanternRoot canonical_header_root;
            LanternRoot spec_header_root;
            char header_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
            char state_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
            char original_state_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
            char block_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
            char signed_block_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
            char parent_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
            char canonical_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
            char body_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
            char spec_header_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
            header_hex[0] = '\0';
            state_hex[0] = '\0';
            original_state_hex[0] = '\0';
            block_hex[0] = '\0';
            signed_block_hex[0] = '\0';
            parent_hex[0] = '\0';
            canonical_hex[0] = '\0';
            body_hex[0] = '\0';
            spec_header_hex[0] = '\0';
            if (lantern_hash_tree_root_block_header(&client->state.latest_block_header, &header_root) == 0) {
                format_root_hex(&header_root, header_hex, sizeof(header_hex));
            }
            if (lantern_hash_tree_root_state(&client->state, &state_root) == 0) {
                format_root_hex(&state_root, state_hex, sizeof(state_hex));
                /* NOTE: Do NOT update client->state.latest_block_header.state_root here!
                 * 
                 * According to leanSpec, the genesis block header MUST have state_root = ZERO.
                 * The genesis block root is computed from this header with state_root = ZERO.
                 * This is critical for interoperability with other leanSpec implementations.
                 * 
                 * The state's latest_block_header.state_root will be updated to the actual
                 * state root later during fork choice initialization, AFTER computing the
                 * genesis anchor root.
                 */
            }
            LanternBlock genesis_block;
            memset(&genesis_block, 0, sizeof(genesis_block));
            genesis_block.slot = client->state.latest_block_header.slot;
            genesis_block.proposer_index = client->state.latest_block_header.proposer_index;
            genesis_block.parent_root = client->state.latest_block_header.parent_root;
            genesis_block.state_root = state_root;
            lantern_block_body_init(&genesis_block.body);
            if (lantern_hash_tree_root_block(&genesis_block, &genesis_block_root) == 0) {
                format_root_hex(&genesis_block_root, block_hex, sizeof(block_hex));
            }
            lantern_block_body_reset(&genesis_block.body);
            format_root_hex(
                &client->state.latest_block_header.parent_root,
                parent_hex,
                sizeof(parent_hex));
            LanternBlockHeader canonical_header = client->state.latest_block_header;
            canonical_header.state_root = state_root;
            if (lantern_hash_tree_root_block_header(&canonical_header, &canonical_header_root) == 0) {
                format_root_hex(&canonical_header_root, canonical_hex, sizeof(canonical_hex));
            }
            LanternBlockBody empty_body_snapshot;
            lantern_block_body_init(&empty_body_snapshot);
            LanternRoot default_body_root;
            if (lantern_hash_tree_root_block_body(&empty_body_snapshot, &default_body_root) != 0) {
                memset(&default_body_root, 0, sizeof(default_body_root));
            }
            lantern_block_body_reset(&empty_body_snapshot);
            LanternBlockHeader spec_header = client->state.latest_block_header;
            spec_header.state_root = state_root;
            spec_header.body_root = default_body_root;
            if (lantern_hash_tree_root_block_header(&spec_header, &spec_header_root) == 0) {
                format_root_hex(&spec_header_root, spec_header_hex, sizeof(spec_header_hex));
            }
            format_root_hex(
                &client->state.latest_block_header.body_root,
                body_hex,
                sizeof(body_hex));
            LanternSignedBlock genesis_signed;
            lantern_signed_block_with_attestation_init(&genesis_signed);
            genesis_signed.message.block = genesis_block;
            (void)lantern_block_signatures_resize(&genesis_signed.signatures, 0);
            if (lantern_hash_tree_root_signed_block(&genesis_signed, &genesis_signed_block_root) == 0) {
                format_root_hex(&genesis_signed_block_root, signed_block_hex, sizeof(signed_block_hex));
            }
            LanternState generated_state;
            lantern_state_init(&generated_state);
            if (lantern_state_generate_genesis(
                    &generated_state,
                    client->state.config.genesis_time,
                    client->state.config.num_validators)
                == 0) {
                LanternRoot generated_state_root;
                if (lantern_hash_tree_root_state(&generated_state, &generated_state_root) == 0) {
                    LanternBlock generated_block;
                    memset(&generated_block, 0, sizeof(generated_block));
                    generated_block.slot = generated_state.slot;
                    generated_block.proposer_index = 0;
                    generated_block.parent_root = generated_state.latest_block_header.parent_root;
                    generated_block.state_root = generated_state_root;
                    lantern_block_body_init(&generated_block.body);
                    LanternRoot generated_block_root;
                    if (lantern_hash_tree_root_block(&generated_block, &generated_block_root) == 0) {
                        char generated_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
                        format_root_hex(&generated_block_root, generated_hex, sizeof(generated_hex));
                        lantern_log_info(
                            "client",
                            &(const struct lantern_log_metadata){.validator = client->node_id},
                            "generated anchor block root=%s",
                            generated_hex[0] ? generated_hex : "0x0");
                    }
                    lantern_block_body_reset(&generated_block.body);
                }
            }
            lantern_log_info(
                "client",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "genesis anchors header_root=%s state_root=%s body_root=%s block_root=%s signed_block_root=%s canonical_header_root=%s spec_header_root=%s parent_root=%s",
                header_hex[0] ? header_hex : "0x0",
                state_hex[0] ? state_hex : "0x0",
                body_hex[0] ? body_hex : "0x0",
                block_hex[0] ? block_hex : "0x0",
                signed_block_hex[0] ? signed_block_hex : "0x0",
                canonical_hex[0] ? canonical_hex : "0x0",
                spec_header_hex[0] ? spec_header_hex : "0x0",
                parent_hex[0] ? parent_hex : "0x0");
            client->has_state = true;
        }
    }
    if (client->has_state) {
        int votes_rc = lantern_storage_load_votes(client->data_dir, &client->state);
        if (votes_rc < 0) {
            lantern_log_error(
                "storage",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "failed to load persisted votes");
            goto error;
        }
        if (initialize_fork_choice(client) != 0) {
            goto error;
        }
        if (restore_persisted_blocks(client) != 0) {
            goto error;
        }
    }
    if (client->has_state && !loaded_from_storage) {
        if (lantern_storage_save_state(client->data_dir, &client->state) != 0) {
            lantern_log_warn(
                "storage",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "failed to persist initial state snapshot");
        }
        if (lantern_storage_save_votes(client->data_dir, &client->state) != 0) {
            lantern_log_warn(
                "storage",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "failed to persist initial votes snapshot");
        }
    }

    client->assigned_validators = lantern_validator_config_find(
        &client->genesis.validator_config,
        client->node_id);

    if (!client->assigned_validators) {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "node-id '%s' not found in validator-config",
            client->node_id);
        goto error;
    }
    if (!client->assigned_validators->enr.ip || client->assigned_validators->enr.quic_port == 0) {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "validator '%s' missing ENR fields",
            client->node_id);
        goto error;
    }
    if (configure_hash_sig_sources(client, options) != 0) {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to configure hash-sig key sources");
        goto error;
    }
    adopt_validator_listen_address(client);
    if (compute_local_validator_assignment(client) != 0) {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to compute validator assignment for '%s'",
            client->node_id);
        goto error;
    }
    if (populate_local_validators(client) != 0) {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to enumerate local validators for '%s'",
            client->node_id);
        goto error;
    }
    if (client->local_validator_count == 0 || !client->has_state) {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "no local validators assigned for '%s'; check validator-config",
            client->node_id);
        goto error;
    }
    if (lantern_client_refresh_state_validators(client) != 0) {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to refresh validator pubkeys for '%s'",
            client->node_id);
        goto error;
    }
    if (load_hash_sig_keys(client) != 0) {
        goto error;
    }
    lantern_log_info(
        "client",
        &(const struct lantern_log_metadata){.validator = client->node_id},
        "validator slice start=%" PRIu64 " count=%" PRIu64,
        client->validator_assignment.start_index,
        client->validator_assignment.count);
    if (init_consensus_runtime(client) != 0) {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to initialize consensus runtime");
        goto error;
    }
    lantern_log_info(
        "client",
        &(const struct lantern_log_metadata){.validator = client->node_id},
        "consensus runtime ready genesis_time=%" PRIu64 " validators=%" PRIu64,
        client->genesis.chain_config.genesis_time,
        client->genesis.chain_config.validator_count);

    uint8_t node_key[32];
    if (load_node_key_bytes(options, node_key) != 0) {
        goto error;
    }
    memcpy(client->node_private_key, node_key, sizeof(node_key));
    client->has_node_private_key = true;

    struct lantern_libp2p_config net_cfg = {
        .listen_multiaddr = client->listen_address,
        .secp256k1_secret = node_key,
        .secret_len = sizeof(node_key),
        .allow_outbound_identify = 1,
    };
    if (lantern_libp2p_host_start(&client->network, &net_cfg) != 0) {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to initialize libp2p host");
        memset(node_key, 0, sizeof(node_key));
        goto error;
    }

    if (!client->connection_lock_initialized) {
        if (pthread_mutex_init(&client->connection_lock, NULL) != 0) {
            lantern_log_error(
                "network",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "failed to initialize connection lock");
            memset(node_key, 0, sizeof(node_key));
            goto error;
        }
        client->connection_lock_initialized = true;
    }
    connection_counter_reset(client);

    if (libp2p_event_subscribe(client->network.host, connection_events_cb, client, &client->connection_subscription) != 0) {
        lantern_log_error(
            "network",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to subscribe to libp2p connection events");
        memset(node_key, 0, sizeof(node_key));
        goto error;
    }

    {
        libp2p_protocol_server_t *ping_server = NULL;
        if (libp2p_ping_service_start(client->network.host, &ping_server) != 0) {
            lantern_log_error(
                "network",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "failed to start libp2p ping service");
            memset(node_key, 0, sizeof(node_key));
            goto error;
        }
        client->ping_server = ping_server;
        client->ping_running = true;
        lantern_log_info(
            "network",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "libp2p ping service started");
    }

    struct lantern_gossipsub_config gossip_cfg = {
        .host = client->network.host,
        .devnet = client->devnet,
    };
    lantern_gossipsub_service_set_block_handler(&client->gossip, gossip_block_handler, client);
    lantern_gossipsub_service_set_vote_handler(&client->gossip, gossip_vote_handler, client);
    if (lantern_gossipsub_service_start(&client->gossip, &gossip_cfg) != 0) {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to start gossipsub service");
        memset(node_key, 0, sizeof(node_key));
        goto error;
    }
    client->gossip_running = true;

    struct lantern_reqresp_service_callbacks req_callbacks;
    memset(&req_callbacks, 0, sizeof(req_callbacks));
    req_callbacks.context = client;
    req_callbacks.build_status = reqresp_build_status;
    req_callbacks.handle_status = reqresp_handle_status;
    req_callbacks.status_failure = reqresp_status_failure;
    req_callbacks.collect_blocks = reqresp_collect_blocks;

    struct lantern_reqresp_service_config req_config;
    memset(&req_config, 0, sizeof(req_config));
    req_config.host = client->network.host;
    req_config.callbacks = &req_callbacks;
    if (lantern_reqresp_service_start(&client->reqresp, &req_config) != 0) {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to start request/response service");
        memset(node_key, 0, sizeof(node_key));
        goto error;
    }
    client->reqresp_running = true;
    lantern_client_seed_reqresp_peer_modes(client);
    if (append_genesis_bootnodes(client) != 0) {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to append bootnodes from genesis");
        memset(node_key, 0, sizeof(node_key));
        goto error;
    }

    if (lantern_enr_record_build_v4(
            &client->local_enr,
            node_key,
            client->assigned_validators->enr.ip,
            client->assigned_validators->enr.quic_port,
            client->assigned_validators->enr.sequence)
        != 0) {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to build local ENR");
        memset(node_key, 0, sizeof(node_key));
        goto error;
    }
    lantern_log_info(
        "client",
        &(const struct lantern_log_metadata){.validator = client->node_id},
        "local ENR prepared sequence=%" PRIu64,
        client->assigned_validators->enr.sequence);
    memset(node_key, 0, sizeof(node_key));

    if (start_peer_dialer(client) != 0) {
        lantern_log_warn(
            "network",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to start peer dialer thread");
    }

    if (start_validator_service(client) != 0) {
        lantern_log_warn(
            "validator",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "validator duties inactive");
    }

    struct lantern_http_server_config http_config;
    memset(&http_config, 0, sizeof(http_config));
    http_config.port = client->http_port;
    http_config.callbacks.context = client;
    http_config.callbacks.snapshot_head = http_snapshot_head;
    http_config.callbacks.validator_count = http_validator_count_cb;
    http_config.callbacks.validator_info = http_validator_info_cb;
    http_config.callbacks.set_validator_status = http_set_validator_status_cb;
    if (lantern_http_server_start(&client->http_server, &http_config) != 0) {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to start HTTP server on port %" PRIu16,
            client->http_port);
        goto error;
    }
    client->http_running = true;

    struct lantern_metrics_callbacks metrics_callbacks;
    memset(&metrics_callbacks, 0, sizeof(metrics_callbacks));
    metrics_callbacks.context = client;
    metrics_callbacks.snapshot = metrics_snapshot_cb;
    if (client->metrics_port != 0) {
        if (lantern_metrics_server_start(&client->metrics_server, client->metrics_port, &metrics_callbacks) != 0) {
            lantern_log_error(
                "client",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "failed to start metrics server on port %" PRIu16,
                client->metrics_port);
            goto error;
        }
        client->metrics_running = true;
    }

    return 0;

error:
    lantern_shutdown(client);
    return -1;
}

void lantern_shutdown(struct lantern_client *client) {
    if (!client) {
        return;
    }

    stop_validator_service(client);
    stop_peer_dialer(client);
    free_hash_sig_pubkeys(client);
    free(client->hash_sig_key_dir);
    client->hash_sig_key_dir = NULL;
    free(client->hash_sig_public_template);
    client->hash_sig_public_template = NULL;
    free(client->hash_sig_secret_template);
    client->hash_sig_secret_template = NULL;
    free(client->hash_sig_public_path);
    client->hash_sig_public_path = NULL;
    free(client->hash_sig_secret_path);
    client->hash_sig_secret_path = NULL;

    lantern_metrics_server_stop(&client->metrics_server);
    lantern_metrics_server_init(&client->metrics_server);
    client->metrics_running = false;

    lantern_http_server_stop(&client->http_server);
    lantern_http_server_init(&client->http_server);
    client->http_running = false;

    if (client->network.host && client->connection_subscription) {
        libp2p_event_unsubscribe(client->network.host, client->connection_subscription);
    }
    client->connection_subscription = NULL;

    if (client->network.host && client->ping_running && client->ping_server) {
        if (libp2p_ping_service_stop(client->network.host, client->ping_server) != 0) {
            lantern_log_warn(
                "network",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "failed to stop libp2p ping service cleanly");
        } else {
            lantern_log_info(
                "network",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "shutdown: libp2p ping service stopped");
        }
    }
    client->ping_server = NULL;
    client->ping_running = false;

    if (client->connection_lock_initialized) {
        connection_counter_reset(client);
        pthread_mutex_destroy(&client->connection_lock);
        client->connection_lock_initialized = false;
    } else {
        client->connected_peers = 0;
    }
    lantern_string_list_reset(&client->connected_peer_ids);

    if (client->status_lock_initialized) {
        if (pthread_mutex_lock(&client->status_lock) == 0) {
            free(client->peer_status_entries);
            client->peer_status_entries = NULL;
            client->peer_status_count = 0;
            client->peer_status_capacity = 0;
            pthread_mutex_unlock(&client->status_lock);
        } else {
            free(client->peer_status_entries);
            client->peer_status_entries = NULL;
            client->peer_status_count = 0;
            client->peer_status_capacity = 0;
        }
        pthread_mutex_destroy(&client->status_lock);
        client->status_lock_initialized = false;
    } else {
        free(client->peer_status_entries);
        client->peer_status_entries = NULL;
        client->peer_status_count = 0;
        client->peer_status_capacity = 0;
    }

    if (client->peer_vote_lock_initialized) {
        if (pthread_mutex_lock(&client->peer_vote_lock) == 0) {
            free(client->peer_vote_stats);
            client->peer_vote_stats = NULL;
            client->peer_vote_stats_len = 0;
            client->peer_vote_stats_cap = 0;
            pthread_mutex_unlock(&client->peer_vote_lock);
        } else {
            free(client->peer_vote_stats);
            client->peer_vote_stats = NULL;
            client->peer_vote_stats_len = 0;
            client->peer_vote_stats_cap = 0;
        }
        pthread_mutex_destroy(&client->peer_vote_lock);
        client->peer_vote_lock_initialized = false;
    } else {
        free(client->peer_vote_stats);
        client->peer_vote_stats = NULL;
        client->peer_vote_stats_len = 0;
        client->peer_vote_stats_cap = 0;
    }

    if (client->validator_lock_initialized) {
        if (pthread_mutex_lock(&client->validator_lock) == 0) {
            free(client->validator_enabled);
            client->validator_enabled = NULL;
            pthread_mutex_unlock(&client->validator_lock);
        } else {
            free(client->validator_enabled);
            client->validator_enabled = NULL;
        }
        pthread_mutex_destroy(&client->validator_lock);
        client->validator_lock_initialized = false;
    } else {
        free(client->validator_enabled);
        client->validator_enabled = NULL;
    }

    if (client->pending_lock_initialized) {
        if (pthread_mutex_lock(&client->pending_lock) == 0) {
            pending_block_list_reset(&client->pending_blocks);
            pthread_mutex_unlock(&client->pending_lock);
        } else {
            pending_block_list_reset(&client->pending_blocks);
        }
        pthread_mutex_destroy(&client->pending_lock);
        client->pending_lock_initialized = false;
    } else {
        pending_block_list_reset(&client->pending_blocks);
    }
    lantern_string_list_reset(&client->dialer_peers);
    lantern_string_list_reset(&client->status_failure_peer_ids);
    lantern_string_list_reset(&client->bootnodes);
    free(client->data_dir);
    client->data_dir = NULL;
    free(client->node_id);
    client->node_id = NULL;
    free(client->listen_address);
    client->listen_address = NULL;
    free(client->devnet);
    client->devnet = NULL;

    reset_genesis_paths(&client->genesis_paths);
    lantern_genesis_artifacts_reset(&client->genesis);
    lantern_log_info(
        "client",
        &(const struct lantern_log_metadata){.validator = client->node_id},
        "shutdown: stopping request/response service");
    lantern_reqresp_service_reset(&client->reqresp);
    lantern_reqresp_service_init(&client->reqresp);
    client->reqresp_running = false;
    lantern_log_info(
        "client",
        &(const struct lantern_log_metadata){.validator = client->node_id},
        "shutdown: request/response service stopped");
    lantern_log_info(
        "client",
        &(const struct lantern_log_metadata){.validator = client->node_id},
        "shutdown: stopping gossipsub");
    lantern_gossipsub_service_reset(&client->gossip);
    client->gossip_running = false;
    lantern_log_info(
        "client",
        &(const struct lantern_log_metadata){.validator = client->node_id},
        "shutdown: gossipsub stopped");
    lantern_log_info(
        "client",
        &(const struct lantern_log_metadata){.validator = client->node_id},
        "shutdown: resetting libp2p host");
    lantern_libp2p_host_reset(&client->network);
    lantern_log_info(
        "client",
        &(const struct lantern_log_metadata){.validator = client->node_id},
        "shutdown: libp2p host reset");
    lantern_enr_record_reset(&client->local_enr);
    memset(client->node_private_key, 0, sizeof(client->node_private_key));
    client->has_node_private_key = false;
    if (client->has_state) {
        lantern_state_reset(&client->state);
        client->has_state = false;
    } else {
        lantern_state_reset(&client->state);
    }
    if (client->state_lock_initialized) {
        pthread_mutex_destroy(&client->state_lock);
        client->state_lock_initialized = false;
    }
    lantern_fork_choice_reset(&client->fork_choice);
    client->has_fork_choice = false;
    reset_local_validators(client);
    lantern_validator_assignment_reset(&client->validator_assignment);
    client->has_validator_assignment = false;
    lantern_consensus_runtime_reset(&client->runtime);
    client->has_runtime = false;

    client->http_port = 0;
    client->metrics_port = 0;
    client->assigned_validators = NULL;
    lantern_log_reset_node_id();
}

static bool string_list_contains(const struct lantern_string_list *list, const char *value) {
    if (!list || !value) {
        return false;
    }
    for (size_t i = 0; i < list->len; ++i) {
        if (list->items && list->items[i] && strcmp(list->items[i], value) == 0) {
            return true;
        }
    }
    return false;
}

static void string_list_remove(struct lantern_string_list *list, const char *value) {
    if (!list || !value || !list->items || list->len == 0) {
        return;
    }
    for (size_t i = 0; i < list->len; ++i) {
        if (list->items[i] && strcmp(list->items[i], value) == 0) {
            free(list->items[i]);
            for (size_t j = i + 1; j < list->len; ++j) {
                list->items[j - 1] = list->items[j];
            }
            list->len -= 1;
            if (list->items) {
                list->items[list->len] = NULL;
            }
            break;
        }
    }
}

static int append_unique_bootnode(struct lantern_string_list *list, const char *value) {
    if (!list || !value) {
        return -1;
    }
    if (*value == '\0') {
        return 0;
    }
    if (string_list_contains(list, value)) {
        return 0;
    }
    return lantern_string_list_append(list, value);
}

static int append_genesis_bootnodes(struct lantern_client *client) {
    if (!client) {
        return -1;
    }
    const struct lantern_enr_record_list *enrs = &client->genesis.enrs;
    for (size_t i = 0; i < enrs->count; ++i) {
        const struct lantern_enr_record *record = &enrs->records[i];
        if (!record->encoded) {
            continue;
        }
        if (append_unique_bootnode(&client->bootnodes, record->encoded) != 0) {
            return -1;
        }
        if (client->network.host) {
            if (lantern_libp2p_host_add_enr_peer(&client->network, record, LANTERN_LIBP2P_DEFAULT_PEER_TTL_MS) != 0) {
                lantern_log_warn(
                    "network",
                    &(const struct lantern_log_metadata){
                        .validator = client->node_id,
                        .peer = record->encoded},
                    "failed to add ENR peer from genesis");
                continue;
            }
            lantern_log_info(
                "network",
                &(const struct lantern_log_metadata){
                    .validator = client->node_id,
                    .peer = record->encoded},
                "bootnode registered sequence=%" PRIu64,
                record->sequence);
        }
    }
    return 0;
}

static int compute_local_validator_assignment(struct lantern_client *client) {
    if (!client || !client->assigned_validators) {
        return -1;
    }
    lantern_validator_assignment_reset(&client->validator_assignment);
    client->has_validator_assignment = false;
    if (lantern_validator_assignment_from_config(
            &client->genesis.validator_config,
            client->assigned_validators,
            &client->validator_assignment)
        != 0) {
        return -1;
    }
    if (!lantern_validator_assignment_is_valid(&client->validator_assignment)) {
        return -1;
    }
    client->has_validator_assignment = true;
    return 0;
}

static int populate_local_validators(struct lantern_client *client) {
    if (!client || !client->has_validator_assignment || !client->assigned_validators) {
        return -1;
    }

    struct lantern_log_metadata meta = {.validator = client->node_id};
    uint64_t local_count = client->validator_assignment.count;
    if (local_count == 0 || client->validator_assignment.length != local_count) {
        return -1;
    }
    if (!client->validator_assignment.indices) {
        return -1;
    }
    if (local_count > SIZE_MAX) {
        return -1;
    }

    uint64_t total_validators = client->genesis.chain_config.validator_count;
    if (!client->genesis.validator_registry.records
        || client->genesis.validator_registry.count < total_validators) {
        return -1;
    }

    char indices_buf[512];
    indices_buf[0] = '\0';
    size_t written = 0;
    for (size_t i = 0; i < client->validator_assignment.length; ++i) {
        int n = snprintf(
            indices_buf + written,
            sizeof(indices_buf) - written,
            "%s%" PRIu64,
            written > 0 ? "," : "",
            client->validator_assignment.indices[i]);
        if (n < 0 || (size_t)n >= sizeof(indices_buf) - written) {
            strncpy(indices_buf + (sizeof(indices_buf) > 4 ? sizeof(indices_buf) - 4 : 0), "...", 3);
            indices_buf[sizeof(indices_buf) - 1] = '\0';
            break;
        }
        written += (size_t)n;
    }
    lantern_log_info(
        "client",
        &meta,
        "local validator assignment start=%" PRIu64 " count=%" PRIu64 " indices=%s",
        client->validator_assignment.start_index,
        local_count,
        indices_buf[0] ? indices_buf : "-");

    const char *priv_hex = client->assigned_validators->privkey_hex;
    if (!priv_hex || *priv_hex == '\0') {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "validator '%s' missing privkey in validator-config",
            client->node_id);
        return -1;
    }

    uint8_t *decoded_secret = NULL;
    size_t decoded_len = 0;
    if (decode_validator_secret(priv_hex, &decoded_secret, &decoded_len) != 0 || decoded_len == 0) {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "validator '%s' privkey is invalid",
            client->node_id);
        if (decoded_secret) {
            lantern_secure_zero(decoded_secret, decoded_len);
            free(decoded_secret);
        }
        return -1;
    }

    lantern_log_debug(
        "client",
        &meta,
        "decoded validator secret bytes len=%zu",
        decoded_len);

    size_t stored_len = strlen(client->assigned_validators->privkey_hex);
    if (stored_len > 0) {
        lantern_secure_zero(client->assigned_validators->privkey_hex, stored_len);
        client->assigned_validators->privkey_hex[0] = '\0';
    }

    size_t count = (size_t)local_count;
    struct lantern_local_validator *validators = calloc(count, sizeof(*validators));
    if (!validators) {
        lantern_secure_zero(decoded_secret, decoded_len);
        free(decoded_secret);
        return -1;
    }

    for (size_t i = 0; i < count; ++i) {
        uint64_t global_index = client->validator_assignment.indices[i];
        if (global_index >= total_validators) {
            for (size_t j = 0; j < i; ++j) {
                local_validator_cleanup(&validators[j]);
            }
            free(validators);
            lantern_secure_zero(decoded_secret, decoded_len);
            free(decoded_secret);
            return -1;
        }
        validators[i].global_index = global_index;
        validators[i].registry = &client->genesis.validator_registry.records[global_index];
        validators[i].secret_len = decoded_len;
        if (decoded_len > 0) {
            validators[i].secret = malloc(decoded_len);
            if (!validators[i].secret) {
                for (size_t j = 0; j <= i; ++j) {
                    local_validator_cleanup(&validators[j]);
                }
                free(validators);
                lantern_secure_zero(decoded_secret, decoded_len);
                free(decoded_secret);
                return -1;
            }
            memcpy(validators[i].secret, decoded_secret, decoded_len);
            validators[i].has_secret = true;
        }
        validators[i].last_proposed_slot = UINT64_MAX;
        validators[i].last_attested_slot = UINT64_MAX;
        validators[i].has_pending_attestation = false;
        validators[i].pending_attestation_slot = UINT64_MAX;
        memset(&validators[i].pending_attestation, 0, sizeof(validators[i].pending_attestation));
    }

    bool *enabled = calloc(count, sizeof(*enabled));
    if (!enabled) {
        for (size_t i = 0; i < count; ++i) {
            local_validator_cleanup(&validators[i]);
        }
        free(validators);
        lantern_secure_zero(decoded_secret, decoded_len);
        free(decoded_secret);
        return -1;
    }
    for (size_t i = 0; i < count; ++i) {
        enabled[i] = true;
    }

    if (!client->validator_lock_initialized) {
        if (pthread_mutex_init(&client->validator_lock, NULL) != 0) {
            free(enabled);
            for (size_t i = 0; i < count; ++i) {
                local_validator_cleanup(&validators[i]);
            }
            free(validators);
            lantern_secure_zero(decoded_secret, decoded_len);
            free(decoded_secret);
            return -1;
        }
        client->validator_lock_initialized = true;
    }

    if (pthread_mutex_lock(&client->validator_lock) != 0) {
        free(enabled);
        for (size_t i = 0; i < count; ++i) {
            local_validator_cleanup(&validators[i]);
        }
        free(validators);
        lantern_secure_zero(decoded_secret, decoded_len);
        free(decoded_secret);
        return -1;
    }

    free(client->validator_enabled);
    client->validator_enabled = enabled;
    enabled = NULL;

    reset_local_validators(client);
    client->local_validators = validators;
    client->local_validator_count = count;
    validators = NULL;

    pthread_mutex_unlock(&client->validator_lock);

    lantern_secure_zero(decoded_secret, decoded_len);
    free(decoded_secret);
    lantern_log_info(
        "client",
        &meta,
        "local validators ready count=%zu secrets_loaded=%zu",
        client->local_validator_count,
        client->local_validator_count);
    return 0;
}

static int find_local_validator_index(const struct lantern_client *client, uint64_t global_index, size_t *out_index) {
    if (!client) {
        return -1;
    }
    for (size_t i = 0; i < client->local_validator_count; ++i) {
        if (client->local_validators && client->local_validators[i].global_index == global_index) {
            if (out_index) {
                *out_index = i;
            }
            return 0;
        }
    }
    return -1;
}

static void validator_duty_state_reset(struct lantern_validator_duty_state *state) {
    if (!state) {
        return;
    }
    memset(state, 0, sizeof(*state));
}

static uint64_t validator_wall_time_now_seconds(void) {
#if defined(CLOCK_REALTIME)
    struct timespec ts;
    if (clock_gettime(CLOCK_REALTIME, &ts) == 0) {
        return (uint64_t)ts.tv_sec;
    }
#endif
    time_t now = time(NULL);
    return now > 0 ? (uint64_t)now : 0;
}

static bool lantern_client_vote_time_seconds(
    const struct lantern_client *client,
    uint64_t vote_slot,
    uint64_t *out_seconds) {
    if (!client || !client->has_fork_choice || !out_seconds) {
        return false;
    }
    uint32_t seconds_per_slot = client->fork_choice.seconds_per_slot;
    if (seconds_per_slot == 0) {
        seconds_per_slot = 1;
    }
    uint64_t slot_for_time = vote_slot;
    if (slot_for_time != UINT64_MAX) {
        slot_for_time += 1u;
    }
    __uint128_t slot_offset = (__uint128_t)slot_for_time * (uint64_t)seconds_per_slot;
    __uint128_t result = slot_offset + ( __uint128_t)client->fork_choice.config.genesis_time;
    if (result > UINT64_MAX) {
        return false;
    }
    *out_seconds = (uint64_t)result;
    return true;
}

static void validator_sleep_ms(uint32_t ms) {
    struct timespec ts;
    ts.tv_sec = ms / 1000u;
    ts.tv_nsec = (long)(ms % 1000u) * 1000000L;
    nanosleep(&ts, NULL);
}

static bool validator_service_should_run(const struct lantern_client *client) {
    if (!client) {
        return false;
    }
    if (!client->has_state || !client->has_runtime || !client->has_fork_choice) {
        return false;
    }
    if (!client->gossip_running || client->local_validator_count == 0) {
        return false;
    }
    return true;
}

static bool validator_is_enabled(const struct lantern_client *client, size_t local_index) {
    if (!client || local_index >= client->local_validator_count) {
        return false;
    }
    if (!client->validator_enabled) {
        return true;
    }
    if (!client->validator_lock_initialized) {
        return client->validator_enabled[local_index];
    }
    if (pthread_mutex_lock((pthread_mutex_t *)&client->validator_lock) != 0) {
        return client->validator_enabled[local_index];
    }
    bool enabled = client->validator_enabled[local_index];
    pthread_mutex_unlock((pthread_mutex_t *)&client->validator_lock);
    return enabled;
}

static uint64_t validator_global_index(const struct lantern_client *client, size_t local_index) {
    if (!client || !client->local_validators || local_index >= client->local_validator_count) {
        return UINT64_MAX;
    }
    return client->local_validators[local_index].global_index;
}

static int validator_sign_vote(
    struct lantern_local_validator *validator,
    uint64_t slot,
    LanternSignedVote *vote) {
    if (!validator || !vote || !validator->secret_key) {
        return -1;
    }
    LanternRoot vote_root;
    if (lantern_hash_tree_root_vote(&vote->data, &vote_root) != 0) {
        return -1;
    }
    if (!lantern_signature_sign(
            validator->secret_key,
            slot,
            vote_root.bytes,
            sizeof(vote_root.bytes),
            &vote->signature)) {
        return -1;
    }
    return 0;
}

static int validator_store_vote(struct lantern_client *client, const LanternSignedVote *vote) {
    if (!client || !vote) {
        return -1;
    }
    if (!client->has_state) {
        return -1;
    }
    bool state_locked = lantern_client_lock_state(client);
    if (!state_locked) {
        return -1;
    }
    int rc = lantern_state_set_signed_validator_vote(
        &client->state,
        (size_t)vote->data.validator_id,
        vote);
    lantern_client_unlock_state(client, state_locked);
    if (rc != 0) {
        lantern_log_warn(
            "validator",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to store attestation validator=%" PRIu64 " slot=%" PRIu64,
            vote->data.validator_id,
            vote->data.slot);
        return -1;
    }
    return 0;
}

static int validator_publish_vote(struct lantern_client *client, const LanternSignedVote *vote) {
    if (!client || !vote) {
        return -1;
    }
    struct lantern_log_metadata meta = {.validator = client->node_id};
    if (client->has_fork_choice) {
        if (lantern_fork_choice_add_vote(&client->fork_choice, vote, false) != 0) {
            lantern_log_debug(
                "validator",
                &meta,
                "failed to enqueue vote into fork choice validator=%" PRIu64 " slot=%" PRIu64,
                vote->data.validator_id,
                vote->data.slot);
        }
    }
    int rc = lantern_gossipsub_service_publish_vote(&client->gossip, vote);
    if (rc != 0) {
        lantern_log_warn(
            "gossip",
            &meta,
            "failed to publish attestation validator=%" PRIu64 " slot=%" PRIu64,
            vote->data.validator_id,
            vote->data.slot);
        return -1;
    }
    lantern_log_info(
        "gossip",
        &meta,
        "published attestation validator=%" PRIu64 " slot=%" PRIu64,
        vote->data.validator_id,
        vote->data.slot);
    return 0;
}

static int validator_build_block(
    struct lantern_client *client,
    uint64_t slot,
    size_t local_index,
    LanternSignedBlock *out_block,
    LanternSignedVote *out_proposer_vote) {
    if (!client || !out_block || !out_proposer_vote) {
        return -1;
    }
    if (local_index >= client->local_validator_count || !client->local_validators) {
        return -1;
    }
    struct lantern_local_validator *local = &client->local_validators[local_index];
    lantern_signed_block_with_attestation_init(out_block);
    memset(out_proposer_vote, 0, sizeof(*out_proposer_vote));

    bool state_locked = lantern_client_lock_state(client);
    if (!state_locked) {
        lantern_signed_block_with_attestation_reset(out_block);
        return -1;
    }
    if (!client->has_state) {
        lantern_client_unlock_state(client, state_locked);
        lantern_signed_block_with_attestation_reset(out_block);
        return -1;
    }

    LanternRoot parent_root;
    if (lantern_state_select_block_parent(&client->state, &parent_root) != 0) {
        lantern_client_unlock_state(client, state_locked);
        lantern_signed_block_with_attestation_reset(out_block);
        return -1;
    }

    LanternCheckpoint head_cp;
    LanternCheckpoint target_cp;
    LanternCheckpoint source_cp;
    if (lantern_state_compute_vote_checkpoints(&client->state, &head_cp, &target_cp, &source_cp) != 0) {
        lantern_client_unlock_state(client, state_locked);
        lantern_signed_block_with_attestation_reset(out_block);
        return -1;
    }

    out_proposer_vote->data.validator_id = local->global_index;
    out_proposer_vote->data.slot = slot;
    out_proposer_vote->data.head = head_cp;
    out_proposer_vote->data.target = target_cp;
    out_proposer_vote->data.source = source_cp;
    if (validator_sign_vote(local, slot, out_proposer_vote) != 0) {
        lantern_client_unlock_state(client, state_locked);
        lantern_signed_block_with_attestation_reset(out_block);
        return -1;
    }

    LanternAttestations att_list;
    LanternBlockSignatures att_signatures;
    lantern_attestations_init(&att_list);
    lantern_block_signatures_init(&att_signatures);
    if (lantern_state_collect_attestations_for_block(
            &client->state,
            slot,
            local->global_index,
            &parent_root,
            out_proposer_vote,
            &att_list,
            &att_signatures)
        != 0) {
        lantern_attestations_reset(&att_list);
        lantern_block_signatures_reset(&att_signatures);
        lantern_client_unlock_state(client, state_locked);
        lantern_signed_block_with_attestation_reset(out_block);
        return -1;
    }

    lantern_client_unlock_state(client, state_locked);
    state_locked = false;

    LanternBlock *message_block = &out_block->message.block;
    message_block->slot = slot;
    message_block->proposer_index = local->global_index;
    message_block->parent_root = parent_root;
    memset(&message_block->state_root, 0, sizeof(message_block->state_root));

    if (lantern_attestations_copy(&message_block->body.attestations, &att_list) != 0) {
        lantern_attestations_reset(&att_list);
        lantern_block_signatures_reset(&att_signatures);
        lantern_signed_block_with_attestation_reset(out_block);
        return -1;
    }
    lantern_attestations_reset(&att_list);

    out_block->message.proposer_attestation = out_proposer_vote->data;

    size_t signature_count = message_block->body.attestations.length + 1u;
    if (lantern_block_signatures_resize(&out_block->signatures, signature_count) != 0) {
        lantern_signed_block_with_attestation_reset(out_block);
        return -1;
    }
    for (size_t i = 0; i < signature_count - 1u; ++i) {
        if (i < att_signatures.length && att_signatures.data) {
            out_block->signatures.data[i] = att_signatures.data[i];
        } else {
            memset(out_block->signatures.data[i].bytes, 0, LANTERN_SIGNATURE_SIZE);
        }
    }
    out_block->signatures.data[signature_count - 1u] = out_proposer_vote->signature;
    lantern_block_signatures_reset(&att_signatures);

    LanternRoot computed_state_root;
    state_locked = lantern_client_lock_state(client);
    if (!state_locked) {
        lantern_signed_block_with_attestation_reset(out_block);
        return -1;
    }
    int preview_rc = lantern_state_preview_post_state_root(&client->state, out_block, &computed_state_root);
    lantern_client_unlock_state(client, state_locked);
    if (preview_rc != 0) {
        lantern_signed_block_with_attestation_reset(out_block);
        return -1;
    }
    message_block->state_root = computed_state_root;
    return 0;
}

static int validator_propose_block(struct lantern_client *client, uint64_t slot, size_t local_index) {
    if (!validator_service_should_run(client)) {
        return -1;
    }
    LanternSignedBlock block;
    LanternSignedVote proposer_vote;
    lantern_signed_block_with_attestation_init(&block);
    memset(&proposer_vote, 0, sizeof(proposer_vote));

    int rc = validator_build_block(client, slot, local_index, &block, &proposer_vote);
    if (rc != 0) {
        lantern_signed_block_with_attestation_reset(&block);
        return -1;
    }

    struct lantern_log_metadata meta = {.validator = client->node_id};
    lantern_log_info(
        "validator",
        &meta,
        "proposing block slot=%" PRIu64 " proposer=%" PRIu64,
        slot,
        block.message.block.proposer_index);

    lantern_client_record_block(client, &block, NULL, NULL, "local");
    if (lantern_client_publish_block(client, &block) != 0) {
        lantern_signed_block_with_attestation_reset(&block);
        return -1;
    }

    if (client->validator_lock_initialized && pthread_mutex_lock(&client->validator_lock) == 0) {
        if (local_index < client->local_validator_count) {
            struct lantern_local_validator *local = &client->local_validators[local_index];
            local->last_proposed_slot = slot;
            local->pending_attestation = proposer_vote;
            local->pending_attestation_slot = slot;
            local->has_pending_attestation = true;
        }
        pthread_mutex_unlock(&client->validator_lock);
    }

    lantern_signed_block_with_attestation_reset(&block);
    return 0;
}

static int validator_publish_attestations(struct lantern_client *client, uint64_t slot) {
    if (!validator_service_should_run(client)) {
        return -1;
    }
    if (!client->local_validators || client->local_validator_count == 0) {
        return -1;
    }

    LanternCheckpoint head_cp;
    LanternCheckpoint target_cp;
    LanternCheckpoint source_cp;
    bool state_locked = lantern_client_lock_state(client);
    if (!state_locked) {
        return -1;
    }
    if (lantern_state_compute_vote_checkpoints(&client->state, &head_cp, &target_cp, &source_cp) != 0) {
        lantern_client_unlock_state(client, state_locked);
        return -1;
    }
    lantern_client_unlock_state(client, state_locked);

    bool have_lock = false;
    if (client->validator_lock_initialized) {
        if (pthread_mutex_lock(&client->validator_lock) != 0) {
            return -1;
        }
        have_lock = true;
    }

    for (size_t i = 0; i < client->local_validator_count; ++i) {
        bool enabled = client->validator_enabled ? client->validator_enabled[i] : true;
        if (!enabled) {
            continue;
        }
        struct lantern_local_validator *validator = &client->local_validators[i];
        if (validator->last_attested_slot == slot) {
            continue;
        }
        LanternSignedVote vote;
        if (validator->has_pending_attestation && validator->pending_attestation_slot == slot) {
            vote = validator->pending_attestation;
        } else {
            memset(&vote, 0, sizeof(vote));
            vote.data.validator_id = validator->global_index;
            vote.data.slot = slot;
            vote.data.head = head_cp;
            vote.data.target = target_cp;
            vote.data.source = source_cp;
            if (validator_sign_vote(validator, slot, &vote) != 0) {
                continue;
            }
        }
        validator->last_attested_slot = slot;
        validator->has_pending_attestation = false;

        (void)validator_store_vote(client, &vote);
        (void)validator_publish_vote(client, &vote);
    }

    if (have_lock) {
        pthread_mutex_unlock(&client->validator_lock);
    }
    return 0;
}

static void *validator_thread(void *arg) {
    struct lantern_client *client = arg;
    if (!client) {
        return NULL;
    }

    while (__atomic_load_n(&client->validator_stop_flag, __ATOMIC_RELAXED) == 0) {
        if (!validator_service_should_run(client)) {
            validator_sleep_ms(200);
            continue;
        }

        uint64_t now = validator_wall_time_now_seconds();
        if (client->has_runtime) {
            if (lantern_consensus_runtime_update_time(&client->runtime, now) != 0) {
                validator_sleep_ms(50);
                continue;
            }
        }

        const struct lantern_slot_timepoint *tp = lantern_consensus_runtime_current_timepoint(&client->runtime);
        if (!tp) {
            validator_sleep_ms(50);
            continue;
        }

        struct lantern_validator_duty_state *duty = &client->validator_duty;
        if (!duty->have_timepoint || duty->last_slot != tp->slot) {
            duty->have_timepoint = true;
            duty->last_slot = tp->slot;
            duty->slot_proposed = false;
            duty->slot_attested = false;
            duty->pending_local_proposal = false;
            duty->pending_local_index = 0;

            bool is_local = false;
            uint64_t local_index = 0;
            if (lantern_consensus_runtime_local_proposer(&client->runtime, tp->slot, &is_local, &local_index) == 0
                && is_local
                && local_index < client->local_validator_count) {
                duty->pending_local_proposal = true;
                duty->pending_local_index = local_index;
            }
        }
        duty->last_interval = tp->interval_index;

        if (client->has_fork_choice) {
            bool has_proposal = duty->slot_proposed;
            (void)lantern_fork_choice_advance_time(&client->fork_choice, now, has_proposal);
        }

        switch (tp->phase) {
        case LANTERN_DUTY_PHASE_PROPOSAL:
            if (duty->pending_local_proposal && !duty->slot_proposed) {
                if (validator_propose_block(client, tp->slot, (size_t)duty->pending_local_index) == 0) {
                    duty->slot_proposed = true;
                }
            }
            break;
        case LANTERN_DUTY_PHASE_VOTE:
            if (!duty->slot_attested) {
                if (validator_publish_attestations(client, tp->slot) == 0) {
                    duty->slot_attested = true;
                }
            }
            break;
        default:
            break;
        }

        validator_sleep_ms(50);
    }
    return NULL;
}

static int start_validator_service(struct lantern_client *client) {
    if (!client) {
        return -1;
    }
    if (client->validator_thread_started) {
        return 0;
    }
    if (client->local_validator_count == 0 || !client->has_runtime) {
        return 0;
    }
    validator_duty_state_reset(&client->validator_duty);
    __atomic_store_n(&client->validator_stop_flag, 0, __ATOMIC_RELAXED);
    if (pthread_create(&client->validator_thread, NULL, validator_thread, client) != 0) {
        lantern_log_warn(
            "validator",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to start validator service thread");
        return -1;
    }
    client->validator_thread_started = true;
    lantern_log_info(
        "validator",
        &(const struct lantern_log_metadata){.validator = client->node_id},
        "validator service started");
    return 0;
}

static void stop_validator_service(struct lantern_client *client) {
    if (!client || !client->validator_thread_started) {
        return;
    }
    __atomic_store_n(&client->validator_stop_flag, 1, __ATOMIC_RELAXED);
    (void)pthread_join(client->validator_thread, NULL);
    client->validator_thread_started = false;
    lantern_log_info(
        "validator",
        &(const struct lantern_log_metadata){.validator = client->node_id},
        "validator service stopped");
}

static int http_snapshot_head(void *context, struct lantern_http_head_snapshot *out_snapshot) {
    if (!context || !out_snapshot) {
        return -1;
    }
    struct lantern_client *client = context;
    if (!client->has_state) {
        return -1;
    }
    memset(out_snapshot, 0, sizeof(*out_snapshot));
    out_snapshot->slot = client->state.slot;
    if (lantern_hash_tree_root_block_header(&client->state.latest_block_header, &out_snapshot->head_root) != 0) {
        return -1;
    }
    out_snapshot->justified = client->state.latest_justified;
    out_snapshot->finalized = client->state.latest_finalized;
    return 0;
}

static size_t http_validator_count_cb(void *context) {
    const struct lantern_client *client = context;
    if (!client) {
        return 0;
    }
    return client->local_validator_count;
}

static int http_validator_info_cb(void *context, size_t index, struct lantern_http_validator_info *out_info) {
    if (!context || !out_info) {
        return -1;
    }
    struct lantern_client *client = context;
    if (index >= client->local_validator_count || !client->local_validators) {
        return -1;
    }
    memset(out_info, 0, sizeof(*out_info));
    out_info->global_index = client->local_validators[index].global_index;

    bool enabled = true;
    if (client->validator_lock_initialized) {
        if (pthread_mutex_lock(&client->validator_lock) != 0) {
            return -1;
        }
        if (client->validator_enabled && index < client->local_validator_count) {
            enabled = client->validator_enabled[index];
        }
        pthread_mutex_unlock(&client->validator_lock);
    } else if (client->validator_enabled && index < client->local_validator_count) {
        enabled = client->validator_enabled[index];
    }
    out_info->enabled = enabled;

    const char *base = client->node_id ? client->node_id : "validator";
    int written = snprintf(out_info->label, sizeof(out_info->label), "%s#%" PRIu64, base, out_info->global_index);
    if (written < 0 || (size_t)written >= sizeof(out_info->label)) {
        strncpy(out_info->label, base, sizeof(out_info->label));
        out_info->label[sizeof(out_info->label) - 1] = '\0';
    }
    return 0;
}

static int http_set_validator_status_cb(void *context, uint64_t global_index, bool enabled) {
    if (!context) {
        return -1;
    }
    struct lantern_client *client = context;
    if (!client->validator_lock_initialized || !client->validator_enabled) {
        return -1;
    }
    if (pthread_mutex_lock(&client->validator_lock) != 0) {
        return -1;
    }
    size_t local_index = 0;
    if (find_local_validator_index(client, global_index, &local_index) != 0
        || local_index >= client->local_validator_count) {
        pthread_mutex_unlock(&client->validator_lock);
        return -1;
    }
    client->validator_enabled[local_index] = enabled;
    size_t enabled_count = 0;
    size_t disabled_count = 0;
    if (client->validator_enabled) {
        for (size_t i = 0; i < client->local_validator_count; ++i) {
            if (client->validator_enabled[i]) {
                ++enabled_count;
            }
        }
        if (client->local_validator_count > enabled_count) {
            disabled_count = client->local_validator_count - enabled_count;
        }
    } else {
        enabled_count = client->local_validator_count;
    }
    pthread_mutex_unlock(&client->validator_lock);

    lantern_log_info(
        "validator",
        &(const struct lantern_log_metadata){.validator = client->node_id},
        "validator %" PRIu64 " %s (enabled=%zu disabled=%zu)",
        global_index,
        enabled ? "activated" : "deactivated",
        enabled_count,
        disabled_count);
    return 0;
}

static int metrics_snapshot_cb(void *context, struct lantern_metrics_snapshot *out_snapshot) {
    if (!context || !out_snapshot) {
        return -1;
    }
    struct lantern_client *client = context;
    memset(out_snapshot, 0, sizeof(*out_snapshot));

    bool have_fork_head = false;
    LanternRoot fork_head_root;
    memset(&fork_head_root, 0, sizeof(fork_head_root));
    uint64_t fork_head_slot = 0;
    if (client->has_fork_choice) {
        if (lantern_fork_choice_current_head(&client->fork_choice, &fork_head_root) == 0) {
            uint64_t slot = 0;
            if (lantern_fork_choice_block_info(&client->fork_choice, &fork_head_root, &slot, NULL, NULL) == 0) {
                fork_head_slot = slot;
                have_fork_head = true;
            }
        }
    }

    uint64_t state_head_slot = 0;
    LanternCheckpoint state_justified;
    LanternCheckpoint state_finalized;
    memset(&state_justified, 0, sizeof(state_justified));
    memset(&state_finalized, 0, sizeof(state_finalized));
    bool state_locked = lantern_client_lock_state(client);
    if (client->has_state) {
        /* Use the latest_block_header slot which is the actual block slot,
           not state.slot which may be advanced during state transition processing */
        state_head_slot = client->state.latest_block_header.slot;
        state_justified = client->state.latest_justified;
        state_finalized = client->state.latest_finalized;
    }
    lantern_client_unlock_state(client, state_locked);

    out_snapshot->lean_head_slot = have_fork_head ? fork_head_slot : state_head_slot;
    out_snapshot->lean_latest_justified_slot = state_justified.slot;
    out_snapshot->lean_latest_finalized_slot = state_finalized.slot;
    out_snapshot->lean_validators_count = client->local_validator_count;
    out_snapshot->peer_vote_metrics_count = 0;
    if (client->peer_vote_lock_initialized) {
        if (pthread_mutex_lock(&client->peer_vote_lock) == 0) {
            size_t limit = LANTERN_METRICS_MAX_PEER_VOTE_STATS;
            for (size_t i = 0; i < client->peer_vote_stats_len && out_snapshot->peer_vote_metrics_count < limit; ++i) {
                const struct lantern_peer_vote_metric *entry = &client->peer_vote_stats[i];
                struct lantern_peer_vote_metric *metric =
                    &out_snapshot->peer_vote_metrics[out_snapshot->peer_vote_metrics_count++];
                *metric = *entry;
            }
            pthread_mutex_unlock(&client->peer_vote_lock);
        }
    }
    lean_metrics_snapshot(&out_snapshot->lean_metrics);
    return 0;
}

static void format_root_hex(const LanternRoot *root, char *out, size_t out_len) {
    if (!out || out_len == 0) {
        return;
    }
    if (!root) {
        out[0] = '\0';
        return;
    }
    if (lantern_bytes_to_hex(root->bytes, LANTERN_ROOT_SIZE, out, out_len, 1) != 0) {
        out[0] = '\0';
    }
}

static bool lantern_client_lock_state(struct lantern_client *client) {
    if (!client || !client->state_lock_initialized) {
        return false;
    }
    if (pthread_mutex_lock(&client->state_lock) != 0) {
        lantern_log_warn(
            "state",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to lock state mutex");
        return false;
    }
    return true;
}

static void lantern_client_unlock_state(struct lantern_client *client, bool locked) {
    if (!client || !locked || !client->state_lock_initialized) {
        return;
    }
    pthread_mutex_unlock(&client->state_lock);
}

static bool lantern_client_lock_pending(struct lantern_client *client) {
    if (!client || !client->pending_lock_initialized) {
        return false;
    }
    if (pthread_mutex_lock(&client->pending_lock) != 0) {
        lantern_log_warn(
            "state",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to lock pending block mutex");
        return false;
    }
    return true;
}

static void lantern_client_unlock_pending(struct lantern_client *client, bool locked) {
    if (!client || !locked || !client->pending_lock_initialized) {
        return;
    }
    pthread_mutex_unlock(&client->pending_lock);
}

static void lantern_vote_rejection_set(struct lantern_vote_rejection_info *info, const char *fmt, ...) {
    if (!info || !fmt) {
        return;
    }
    va_list args;
    va_start(args, fmt);
    vsnprintf(info->message, sizeof(info->message), fmt, args);
    va_end(args);
    info->message[sizeof(info->message) - 1u] = '\0';
    info->has_reason = true;
}

static bool lantern_validator_pubkey_is_zero(const uint8_t *pubkey) {
    if (!pubkey) {
        return true;
    }
    for (size_t i = 0; i < LANTERN_VALIDATOR_PUBKEY_SIZE; ++i) {
        if (pubkey[i] != 0u) {
            return false;
        }
    }
    return true;
}

static const struct lantern_validator_record *lantern_client_get_validator_record(
    const struct lantern_client *client,
    uint64_t validator_id) {
    if (!client || !client->genesis.validator_registry.records) {
        return NULL;
    }
    if (validator_id >= client->genesis.validator_registry.count) {
        return NULL;
    }
    return &client->genesis.validator_registry.records[validator_id];
}

static int lantern_client_refresh_state_validators(struct lantern_client *client) {
    if (!client || !client->has_state) {
        return -1;
    }
    struct lantern_log_metadata meta = {.validator = client->node_id};
    struct lantern_validator_registry *registry = &client->genesis.validator_registry;
    size_t registry_count = registry->count;
    size_t state_count = lantern_state_validator_count(&client->state);

    bool have_registry = registry->records && registry_count > 0;
    if (!have_registry) {
        if (state_count == 0) {
            return lantern_state_set_validator_pubkeys(&client->state, NULL, 0);
        }
        lantern_log_info(
            "client",
            &meta,
            "validator registry missing; retaining existing state pubkeys count=%zu",
            state_count);
        return 0;
    }

    if (state_count > 0 && state_count != registry_count) {
        lantern_log_warn(
            "client",
            &meta,
            "validator count mismatch registry=%zu state=%zu",
            registry_count,
            state_count);
    }

    size_t count = registry_count;
    size_t total_bytes = count * LANTERN_VALIDATOR_PUBKEY_SIZE;
    uint8_t *packed = malloc(total_bytes);
    if (!packed) {
        return -1;
    }
    size_t registry_used = 0;
    size_t state_used = 0;
    size_t missing_pubkeys = 0;
    for (size_t i = 0; i < count; ++i) {
        struct lantern_validator_record *record = &registry->records[i];
        const uint8_t *registry_pub =
            (record && record->has_pubkey_bytes && !lantern_validator_pubkey_is_zero(record->pubkey_bytes))
                ? record->pubkey_bytes
                : NULL;
        const uint8_t *state_pub = (state_count > i) ? lantern_state_validator_pubkey(&client->state, i) : NULL;
        if (state_pub && lantern_validator_pubkey_is_zero(state_pub)) {
            state_pub = NULL;
        }

        const uint8_t *chosen = registry_pub ? registry_pub : state_pub;
        if (chosen) {
            memcpy(packed + (i * LANTERN_VALIDATOR_PUBKEY_SIZE), chosen, LANTERN_VALIDATOR_PUBKEY_SIZE);
            if (!registry_pub && state_pub && record) {
                memcpy(record->pubkey_bytes, state_pub, LANTERN_VALIDATOR_PUBKEY_SIZE);
                record->has_pubkey_bytes = true;
                char hex[(LANTERN_VALIDATOR_PUBKEY_SIZE * 2u) + 3u];
                if (lantern_bytes_to_hex(
                        state_pub,
                        LANTERN_VALIDATOR_PUBKEY_SIZE,
                        hex,
                        sizeof(hex),
                        1)
                    == 0) {
                    free(record->pubkey_hex);
                    record->pubkey_hex = lantern_string_duplicate(hex);
                }
                ++state_used;
            } else if (registry_pub) {
                ++registry_used;
            }
        } else {
            memset(packed + (i * LANTERN_VALIDATOR_PUBKEY_SIZE), 0, LANTERN_VALIDATOR_PUBKEY_SIZE);
            ++missing_pubkeys;
        }
    }
    int rc = lantern_state_set_validator_pubkeys(&client->state, packed, count);
    free(packed);
    if (rc != 0) {
        lantern_log_warn(
            "client",
            &meta,
            "failed to copy validator pubkeys into parent state");
        return -1;
    }
    size_t enabled = lantern_client_enabled_validator_count(client);
    lantern_log_info(
        "client",
        &meta,
        "refreshed validator pubkeys count=%zu registry=%zu state_fallback=%zu missing=%zu local_validators=%zu enabled=%zu",
        count,
        registry_used,
        state_used,
        missing_pubkeys,
        client->local_validator_count,
        enabled);
    return 0;
}

static size_t lantern_client_enabled_validator_count(struct lantern_client *client) {
    if (!client) {
        return 0;
    }
    size_t enabled = 0;
    bool locked = false;
    if (client->validator_lock_initialized) {
        if (pthread_mutex_lock(&client->validator_lock) == 0) {
            locked = true;
        }
    }
    size_t limit = client->local_validator_count;
    if (!client->validator_enabled) {
        enabled = limit;
    } else {
        for (size_t i = 0; i < limit; ++i) {
            if (client->validator_enabled[i]) {
                ++enabled;
            }
        }
    }
    if (locked) {
        pthread_mutex_unlock(&client->validator_lock);
    }
    return enabled;
}

static bool lantern_client_verify_vote_signature(
    const struct lantern_client *client,
    const LanternSignedVote *vote,
    const LanternSignature *signature,
    const struct lantern_log_metadata *meta,
    const char *context) {
    if (!client || !vote || !signature) {
        return false;
    }
    const uint8_t *pubkey_bytes = NULL;
    bool state_has_registry = client && client->has_state;
    size_t state_validator_count = state_has_registry ? lantern_state_validator_count(&client->state) : 0;
    if (state_has_registry && state_validator_count > 0) {
        if (vote->data.validator_id >= state_validator_count) {
            lantern_log_warn(
                "state",
                meta,
                "validator=%" PRIu64 " exceeds parent state validator count=%zu",
                vote->data.validator_id,
                state_validator_count);
            return false;
        }
        pubkey_bytes = lantern_state_validator_pubkey(&client->state, (size_t)vote->data.validator_id);
        if (lantern_validator_pubkey_is_zero(pubkey_bytes)) {
            pubkey_bytes = NULL;
        }
    }
    if (!pubkey_bytes) {
        const struct lantern_validator_record *record =
            lantern_client_get_validator_record(client, vote->data.validator_id);
        if (!record || !record->has_pubkey_bytes) {
            lantern_log_warn(
                "state",
                meta,
                "missing validator %s pubkey for validator=%" PRIu64,
                context ? context : "signature",
                vote->data.validator_id);
            return false;
        }
        pubkey_bytes = record->pubkey_bytes;
    }
    LanternRoot vote_root;
    if (lantern_hash_tree_root_vote(&vote->data, &vote_root) != 0) {
        lantern_log_warn("state", meta, "failed to hash attestation for validator=%" PRIu64, vote->data.validator_id);
        return false;
    }
    // Per LeanSpec: Always use the 52-byte pubkey from state (root || parameter)
    // This matches Zeam's verifyBincode which takes pubkey bytes directly from state.validators[].pubkey
    bool ok = lantern_signature_verify(
        pubkey_bytes,
        LANTERN_VALIDATOR_PUBKEY_SIZE,
        vote->data.slot,
        signature,
        vote_root.bytes,
        sizeof(vote_root.bytes));
    if (!ok) {
        lantern_log_warn(
            "state",
            meta,
            "invalid XMSS signature validator=%" PRIu64 " context=%s",
            vote->data.validator_id,
            context ? context : "unknown");
    }
    return ok;
}

static bool lantern_client_verify_block_signatures(
    const struct lantern_client *client,
    const LanternSignedBlock *block,
    const struct lantern_log_metadata *meta) {
    if (!client || !block) {
        return false;
    }
    const LanternAttestations *attestations = &block->message.block.body.attestations;
    size_t expected_signatures = attestations->length + 1u;
    if (!client->genesis.validator_registry.records) {
        return true;
    }
    if (block->signatures.length == 0) {
        lantern_log_warn(
            "state",
            meta,
            "signed block slot=%" PRIu64 " missing BlockSignatures; rejecting",
            block->message.block.slot);
        return false;
    }
    if (!block->signatures.data || block->signatures.length != expected_signatures) {
        lantern_log_warn(
            "state",
            meta,
            "signed block slot=%" PRIu64 " signature count mismatch expected=%zu actual=%zu",
            block->message.block.slot,
            expected_signatures,
            block->signatures.length);
        return false;
    }
    for (size_t i = 0; i < attestations->length; ++i) {
        LanternSignedVote signed_vote;
        memset(&signed_vote, 0, sizeof(signed_vote));
        signed_vote.data = attestations->data[i];
        signed_vote.signature = block->signatures.data[i];
        if (!lantern_client_verify_vote_signature(
                client,
                &signed_vote,
                &signed_vote.signature,
                meta,
                "body")) {
            return false;
        }
    }
    LanternSignedVote proposer_signed;
    memset(&proposer_signed, 0, sizeof(proposer_signed));
    proposer_signed.data = block->message.proposer_attestation;
    proposer_signed.signature = block->signatures.data[attestations->length];
    return lantern_client_verify_vote_signature(
        client,
        &proposer_signed,
        &proposer_signed.signature,
        meta,
        "proposer");
}

static bool lantern_client_block_known_locked(
    struct lantern_client *client,
    const LanternRoot *root,
    uint64_t *out_slot) {
    if (!client || !root || !client->has_fork_choice) {
        return false;
    }
    uint64_t slot = 0;
    if (lantern_fork_choice_block_info(&client->fork_choice, root, &slot, NULL, NULL) == 0) {
        if (out_slot) {
            *out_slot = slot;
        }
        return true;
    }
    return false;
}

static bool lantern_client_current_slot(const struct lantern_client *client, uint64_t *out_slot) {
    if (!client || !out_slot || !client->has_fork_choice) {
        return false;
    }
    const LanternForkChoice *store = &client->fork_choice;
    if (store->seconds_per_slot == 0) {
        return false;
    }
    uint64_t now = validator_wall_time_now_seconds();
    if (now < store->config.genesis_time) {
        *out_slot = 0;
        return true;
    }
    uint64_t elapsed = now - store->config.genesis_time;
    *out_slot = elapsed / store->seconds_per_slot;
    return true;
}

static bool lantern_client_validate_vote_constraints(
    struct lantern_client *client,
    const LanternVote *vote,
    const char *facility,
    const struct lantern_log_metadata *meta,
    const char *context,
    struct lantern_vote_rejection_info *out_rejection) {
    if (!client || !vote || !client->has_fork_choice) {
        return false;
    }
    const char *log_facility = (facility && *facility) ? facility : "state";
    const char *label = (context && *context) ? context : "vote";

    struct checkpoint_rule {
        const LanternCheckpoint *checkpoint;
        const char *name;
    } rules[] = {
        {.checkpoint = &vote->source, .name = "source"},
        {.checkpoint = &vote->target, .name = "target"},
        {.checkpoint = &vote->head, .name = "head"},
    };

    for (size_t i = 0; i < (sizeof(rules) / sizeof(rules[0])); ++i) {
        const struct checkpoint_rule *rule = &rules[i];
        char root_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
        format_root_hex(&rule->checkpoint->root, root_hex, sizeof(root_hex));
        if (lantern_root_is_zero(&rule->checkpoint->root)) {
            lantern_log_debug(
                log_facility,
                meta,
                "dropping %s validator=%" PRIu64 " slot=%" PRIu64 " %s root=%s (zero root)",
                label,
                vote->validator_id,
                vote->slot,
                rule->name,
                root_hex[0] ? root_hex : "0x0");
            if (out_rejection) {
                lantern_vote_rejection_set(
                    out_rejection,
                    "%s checkpoint root zero slot=%" PRIu64 " root=%s",
                    rule->name,
                    rule->checkpoint->slot,
                    root_hex[0] ? root_hex : "0x0");
            }
            return false;
        }
        uint64_t block_slot = 0;
        if (!lantern_client_block_known_locked(client, &rule->checkpoint->root, &block_slot)) {
            lantern_log_debug(
                log_facility,
                meta,
                "dropping %s validator=%" PRIu64 " slot=%" PRIu64 " unknown %s root=%s",
                label,
                vote->validator_id,
                vote->slot,
                rule->name,
                root_hex[0] ? root_hex : "0x0");
            if (out_rejection) {
                lantern_vote_rejection_set(
                    out_rejection,
                    "unknown %s root=%s slot=%" PRIu64,
                    rule->name,
                    root_hex[0] ? root_hex : "0x0",
                    rule->checkpoint->slot);
            }
            return false;
        }
        if (block_slot != rule->checkpoint->slot) {
            lantern_log_debug(
                log_facility,
                meta,
                "dropping %s validator=%" PRIu64 " slot=%" PRIu64 " %s slot mismatch vote=%" PRIu64
                " block=%" PRIu64 " root=%s",
                label,
                vote->validator_id,
                vote->slot,
                rule->name,
                rule->checkpoint->slot,
                block_slot,
                root_hex[0] ? root_hex : "0x0");
            if (out_rejection) {
                lantern_vote_rejection_set(
                    out_rejection,
                    "%s checkpoint slot mismatch vote=%" PRIu64 " block=%" PRIu64,
                    rule->name,
                    rule->checkpoint->slot,
                    block_slot);
            }
            return false;
        }
    }

    uint64_t current_slot = 0;
    if (!lantern_client_current_slot(client, &current_slot)) {
        lantern_log_debug(
            log_facility,
            meta,
            "dropping %s validator=%" PRIu64 " slot=%" PRIu64 " (unable to compute current slot)",
            label,
            vote->validator_id,
            vote->slot);
        if (out_rejection) {
            lantern_vote_rejection_set(out_rejection, "unable to compute current slot");
        }
        return false;
    }
    uint64_t allowed_slot = current_slot == UINT64_MAX ? UINT64_MAX : current_slot + 1u;
    if (vote->slot > allowed_slot) {
        lantern_log_debug(
            log_facility,
            meta,
            "dropping %s validator=%" PRIu64 " slot=%" PRIu64 " (current_slot=%" PRIu64 ")",
            label,
            vote->validator_id,
            vote->slot,
            current_slot);
        if (out_rejection) {
            lantern_vote_rejection_set(
                out_rejection,
                "vote slot=%" PRIu64 " exceeds allowed=%" PRIu64 " current=%" PRIu64,
                vote->slot,
                allowed_slot,
                current_slot);
        }
        return false;
    }

    return true;
}

static bool lantern_client_import_block(
    struct lantern_client *client,
    const LanternSignedBlock *block,
    const LanternRoot *block_root,
    const struct lantern_log_metadata *meta) {
    if (!client || !block || !client->has_state) {
        return false;
    }

    bool state_locked = lantern_client_lock_state(client);
    uint64_t local_slot = client->state.slot;

    LanternRoot hashed_block_root;
    const LanternRoot *effective_block_root = block_root;
    if (!effective_block_root) {
        if (lantern_hash_tree_root_block(&block->message.block, &hashed_block_root) != 0) {
            lantern_client_unlock_state(client, state_locked);
            lantern_log_warn(
                "state",
                meta,
                "failed to hash block at slot=%" PRIu64,
                block->message.block.slot);
            return false;
        }
        effective_block_root = &hashed_block_root;
    }

    LanternRoot block_root_local = *effective_block_root;

    if (block->message.block.slot < local_slot) {
        lantern_client_unlock_state(client, state_locked);
        lantern_log_debug(
            "state",
            meta,
            "ignoring block slot=%" PRIu64 " local_slot=%" PRIu64,
            block->message.block.slot,
            local_slot);
        return false;
    }

    uint64_t known_slot = 0;
    bool root_known = false;
    if (effective_block_root) {
        if (state_locked) {
            root_known = lantern_client_block_known_locked(client, effective_block_root, &known_slot);
        } else if (client->has_fork_choice) {
            root_known = (lantern_fork_choice_block_info(&client->fork_choice, effective_block_root, &known_slot, NULL, NULL) == 0);
        }
    }

    if (root_known && block->message.block.slot <= known_slot) {
        lantern_client_unlock_state(client, state_locked);
        lantern_log_trace(
            "state",
            meta,
            "skipping known block slot=%" PRIu64,
            block->message.block.slot);
        return false;
    }

    if (block->message.block.slot < local_slot && !root_known) {
        lantern_client_unlock_state(client, state_locked);
        lantern_log_debug(
            "state",
            meta,
            "ignoring block slot=%" PRIu64 " local_slot=%" PRIu64,
            block->message.block.slot,
            local_slot);
        return false;
    }

    LanternRoot parent_root_local = block->message.block.parent_root;
    if (!lantern_root_is_zero(&parent_root_local)) {
        bool parent_known = false;
        bool parent_matches_head = false;
        bool have_head_root = false;
        LanternRoot latest_header_root;
        memset(&latest_header_root, 0, sizeof(latest_header_root));
        if (state_locked) {
            parent_known = lantern_client_block_known_locked(client, &parent_root_local, NULL);
            /* Ensure state_root is filled in latest_block_header before computing its hash.
               This is required because state_root is zeroed when a block is applied and only
               filled in lazily by lantern_state_process_slot. Without this, the computed
               header root may differ from what other clients expect. */
            (void)lantern_state_process_slot(&client->state);
            if (lantern_hash_tree_root_block_header(&client->state.latest_block_header, &latest_header_root) == 0) {
                have_head_root = true;
                parent_matches_head =
                    memcmp(latest_header_root.bytes, parent_root_local.bytes, LANTERN_ROOT_SIZE) == 0;
            }
        } else if (client->has_fork_choice) {
            parent_known = (lantern_fork_choice_block_info(&client->fork_choice, &parent_root_local, NULL, NULL, NULL) == 0);
        }
        if (!parent_known) {
            /* Parent unknown - queue block as pending and request parent */
            const char *peer_text = meta && meta->peer ? meta->peer : NULL;
            lantern_client_unlock_state(client, state_locked);
            lantern_client_enqueue_pending_block(client, block, &block_root_local, &parent_root_local, peer_text);
            return false;
        }
        if (!parent_matches_head) {
            /*
             * Parent is known in fork choice but doesn't match our current head.
             * This indicates a competing fork. Per leanSpec, we should still add
             * the block to fork choice so attestations can reference it and fork
             * choice can properly determine which chain has more weight.
             *
             * We add the block to fork choice (without post-state checkpoints since
             * we can't compute state transition), then queue it for later processing.
             * If fork choice later determines this is the better chain, pending block
             * processing will handle the reorg.
             */
            const char *peer_text = meta && meta->peer ? meta->peer : NULL;
            char parent_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
            char head_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
            if (have_head_root) {
                format_root_hex(&parent_root_local, parent_hex, sizeof(parent_hex));
                format_root_hex(&latest_header_root, head_hex, sizeof(head_hex));
                lantern_log_debug(
                    "state",
                    meta,
                    "block on competing fork slot=%" PRIu64 " parent=%s current_head=%s",
                    block->message.block.slot,
                    parent_hex[0] ? parent_hex : "0x0",
                    head_hex[0] ? head_hex : "0x0");
            }

            /* Add block to fork choice even without state transition so fork choice
             * can track competing chains and attestations can reference this block */
            if (client->has_fork_choice) {
                LanternSignedVote proposer_signed;
                memset(&proposer_signed, 0, sizeof(proposer_signed));
                proposer_signed.data = block->message.proposer_attestation;
                size_t proposer_index = block->message.block.body.attestations.length;
                if (block->signatures.length > proposer_index && block->signatures.data) {
                    proposer_signed.signature = block->signatures.data[proposer_index];
                }
                if (lantern_fork_choice_add_block(
                        &client->fork_choice,
                        &block->message.block,
                        &proposer_signed,
                        NULL, /* No post-justified - we can't compute state transition */
                        NULL, /* No post-finalized */
                        &block_root_local) == 0) {
                    char block_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
                    format_root_hex(&block_root_local, block_hex, sizeof(block_hex));
                    lantern_log_info(
                        "forkchoice",
                        meta,
                        "added competing fork block to fork choice slot=%" PRIu64 " root=%s",
                        block->message.block.slot,
                        block_hex[0] ? block_hex : "0x0");
                }
            }

            lantern_client_unlock_state(client, state_locked);
            lantern_client_enqueue_pending_block(client, block, &block_root_local, &parent_root_local, peer_text);
            return false;
        }
    }

    if (!lantern_client_verify_block_signatures(client, block, meta)) {
        lantern_client_unlock_state(client, state_locked);
        return false;
    }

    if (client->has_fork_choice) {
        const LanternAttestations *attestations = &block->message.block.body.attestations;
        for (size_t i = 0; i < attestations->length; ++i) {
            if (!lantern_client_validate_vote_constraints(
                    client,
                    &attestations->data[i],
                    "state",
                    meta,
                    "block attestation",
                    NULL)) {
                lantern_client_unlock_state(client, state_locked);
                return false;
            }
        }
        const LanternVote *proposer_vote = &block->message.proposer_attestation;
        bool proposer_present = !lantern_root_is_zero(&proposer_vote->head.root)
            || !lantern_root_is_zero(&proposer_vote->target.root)
            || !lantern_root_is_zero(&proposer_vote->source.root);
        if (proposer_present) {
            if (!lantern_client_validate_vote_constraints(
                    client,
                    proposer_vote,
                    "state",
                    meta,
                    "proposer attestation",
                    NULL)) {
                lantern_client_unlock_state(client, state_locked);
                return false;
            }
        }
    }

    LanternSignedBlock import_block = *block;

    if (lantern_state_transition(&client->state, &import_block) != 0) {
        lantern_client_unlock_state(client, state_locked);
        lantern_log_warn(
            "state",
            meta,
            "state transition failed for slot=%" PRIu64,
            block->message.block.slot);
        return false;
    }

    if (client->has_fork_choice) {
        uint64_t now_seconds = validator_wall_time_now_seconds();
        if (lantern_fork_choice_advance_time(&client->fork_choice, now_seconds, false) != 0) {
            lantern_log_debug(
                "forkchoice",
                meta,
                "advancing fork choice time failed after slot=%" PRIu64,
                block->message.block.slot);
        }
    }

    uint64_t head_slot = client->state.slot;
    LanternRoot head_root;
    memset(&head_root, 0, sizeof(head_root));
    if (client->has_fork_choice) {
        if (lantern_fork_choice_current_head(&client->fork_choice, &head_root) == 0) {
            uint64_t fork_slot = 0;
            if (lantern_fork_choice_block_info(&client->fork_choice, &head_root, &fork_slot, NULL, NULL) == 0) {
                head_slot = fork_slot;
            }
        }
    }

    if (client->data_dir) {
        if (lantern_storage_save_state(client->data_dir, &client->state) != 0) {
            lantern_log_warn(
                "storage",
                meta,
                "failed to persist state after slot=%" PRIu64,
                client->state.slot);
        }
        if (lantern_storage_save_votes(client->data_dir, &client->state) != 0) {
            lantern_log_warn(
                "storage",
                meta,
                "failed to persist votes after slot=%" PRIu64,
                client->state.slot);
        }
    }

    lantern_client_unlock_state(client, state_locked);

    lantern_client_pending_remove_by_root(client, &block_root_local);
    lantern_client_process_pending_children(client, &block_root_local);

    char head_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    format_root_hex(&head_root, head_hex, sizeof(head_hex));
    lantern_log_info(
        "state",
        meta,
        "imported block slot=%" PRIu64 " new_head_slot=%" PRIu64 " head_root=%s",
        block->message.block.slot,
        head_slot,
        head_hex[0] ? head_hex : "0x0");

    return true;
}

static bool lantern_root_is_zero(const LanternRoot *root) {
    if (!root) {
        return true;
    }
    for (size_t i = 0; i < LANTERN_ROOT_SIZE; ++i) {
        if (root->bytes[i] != 0) {
            return false;
        }
    }
    return true;
}

static int reqresp_build_status(void *context, LanternStatusMessage *out_status) {
    if (!context || !out_status) {
        return -1;
    }
    struct lantern_client *client = context;
    memset(out_status, 0, sizeof(*out_status));
    if (!client->has_state) {
        return 0;
    }

    out_status->finalized = client->state.latest_finalized;

    bool head_set = false;
    if (client->has_fork_choice) {
        LanternRoot fork_head = {{0}};
        uint64_t fork_slot = 0;
        if (lantern_fork_choice_current_head(&client->fork_choice, &fork_head) == 0
            && lantern_fork_choice_block_info(&client->fork_choice, &fork_head, &fork_slot, NULL, NULL) == 0) {
            out_status->head.root = fork_head;
            out_status->head.slot = fork_slot;
            head_set = true;
        }
    }

    if (!head_set) {
        out_status->head.slot = client->state.latest_block_header.slot;
        if (lantern_hash_tree_root_block_header(&client->state.latest_block_header, &out_status->head.root) != 0) {
            memset(&out_status->head.root, 0, sizeof(out_status->head.root));
        }
    }
    return 0;
}

static int reqresp_handle_status(void *context, const LanternStatusMessage *peer_status, const char *peer_id) {
    if (!context || !peer_status) {
        return -1;
    }
    struct lantern_client *client = context;
    char head_hex[2 * LANTERN_ROOT_SIZE + 3];
    char finalized_hex[2 * LANTERN_ROOT_SIZE + 3];
    format_root_hex(&peer_status->head.root, head_hex, sizeof(head_hex));
    format_root_hex(&peer_status->finalized.root, finalized_hex, sizeof(finalized_hex));

    lantern_log_info(
        "network",
        &(const struct lantern_log_metadata){
            .validator = client->node_id,
            .peer = peer_id},
        "peer status head_slot=%" PRIu64 " head_root=%s finalized_slot=%" PRIu64 " finalized_root=%s",
        peer_status->head.slot,
        head_hex[0] ? head_hex : "0x0",
        peer_status->finalized.slot,
        finalized_hex[0] ? finalized_hex : "0x0");
    lantern_client_on_peer_status(client, peer_status, peer_id);
    return 0;
}

static void reqresp_status_failure(void *context, const char *peer_id, int error) {
    if (!context) {
        return;
    }
    struct lantern_client *client = context;
    char peer_copy[sizeof(((struct lantern_peer_status_entry *)0)->peer_id)];
    memset(peer_copy, 0, sizeof(peer_copy));
    if (peer_id && *peer_id) {
        strncpy(peer_copy, peer_id, sizeof(peer_copy) - 1);
        peer_copy[sizeof(peer_copy) - 1] = '\0';
    }
    if (error == 0) {
        error = LIBP2P_ERR_INTERNAL;
    }

    if (peer_copy[0] != '\0') {
        lantern_client_status_request_failed(client, peer_copy);
    }

    bool first_failure = true;
    if (peer_copy[0] != '\0') {
        if (client->status_lock_initialized) {
            if (pthread_mutex_lock(&client->status_lock) == 0) {
                if (string_list_contains(&client->status_failure_peer_ids, peer_copy)) {
                    first_failure = false;
                } else {
                    (void)lantern_string_list_append(&client->status_failure_peer_ids, peer_copy);
                }
                pthread_mutex_unlock(&client->status_lock);
            } else {
                if (string_list_contains(&client->status_failure_peer_ids, peer_copy)) {
                    first_failure = false;
                } else {
                    (void)lantern_string_list_append(&client->status_failure_peer_ids, peer_copy);
                }
            }
        } else if (string_list_contains(&client->status_failure_peer_ids, peer_copy)) {
            first_failure = false;
        } else {
            (void)lantern_string_list_append(&client->status_failure_peer_ids, peer_copy);
        }
    }

    const char *reason = connection_reason_text(error);
    struct lantern_log_metadata meta = {
        .validator = client->node_id,
        .peer = peer_copy[0] ? peer_copy : NULL,
    };

    if (error == LIBP2P_ERR_PROTO_NEGOTIATION_FAILED || error == LIBP2P_ERR_UNSUPPORTED) {
        if (first_failure) {
            lantern_log_info(
                "reqresp",
                &meta,
                "peer does not support %s error=%d (%s)",
                LANTERN_STATUS_PROTOCOL_ID,
                error,
                reason ? reason : "-");
        } else {
            lantern_log_trace(
                "reqresp",
                &meta,
                "peer still misses %s support error=%d (%s)",
                LANTERN_STATUS_PROTOCOL_ID,
                error,
                reason ? reason : "-");
        }
        return;
    }

    if (error == LIBP2P_ERR_TIMEOUT) {
        if (first_failure) {
            lantern_log_warn(
                "reqresp",
                &meta,
                "status request to peer timed out error=%d (%s)",
                error,
                reason ? reason : "-");
        } else {
            lantern_log_debug(
                "reqresp",
                &meta,
                "status request still timing out error=%d (%s)",
                error,
                reason ? reason : "-");
        }
        return;
    }

    if (first_failure) {
        lantern_log_warn(
            "reqresp",
            &meta,
            "status request failed error=%d (%s)",
            error,
            reason ? reason : "-");
    } else {
        lantern_log_debug(
            "reqresp",
            &meta,
            "status request still failing error=%d (%s)",
            error,
            reason ? reason : "-");
    }
}

static void lantern_client_on_peer_status(
    struct lantern_client *client,
    const LanternStatusMessage *peer_status,
    const char *peer_id) {
    if (!client || !peer_status || !client->status_lock_initialized) {
        return;
    }
    if (!peer_id || *peer_id == '\0') {
        return;
    }
    if (lantern_root_is_zero(&peer_status->head.root)) {
        return;
    }

    char head_hex[2 * LANTERN_ROOT_SIZE + 3];
    format_root_hex(&peer_status->head.root, head_hex, sizeof(head_hex));

    const size_t peer_cap = sizeof(((struct lantern_peer_status_entry *)0)->peer_id);
    char peer_copy[sizeof(((struct lantern_peer_status_entry *)0)->peer_id)];
    memset(peer_copy, 0, sizeof(peer_copy));
    strncpy(peer_copy, peer_id, peer_cap - 1);

    LanternRoot request_root = peer_status->head.root;
    uint64_t local_slot = 0;
    bool head_known = false;
    bool state_locked = lantern_client_lock_state(client);
    if (state_locked) {
        local_slot = client->state.slot;
        head_known = lantern_client_block_known_locked(client, &peer_status->head.root, NULL);
    } else if (client->has_state) {
        local_slot = client->state.slot;
        if (client->has_fork_choice) {
            uint64_t fork_slot = 0;
            if (lantern_fork_choice_block_info(&client->fork_choice, &peer_status->head.root, &fork_slot, NULL, NULL) == 0) {
                head_known = true;
            }
        }
    }
    lantern_client_unlock_state(client, state_locked);

    bool should_request = false;

    /* If we bootstrapped via genesis fallback and the peer advertises the genesis head,
       adopt the peer's head root as our anchor so that subsequent block requests use
       the correct root. */
    if (client->genesis_fallback_used && client->has_fork_choice && client->has_state
        && peer_status->head.slot == 0 && local_slot == 0 && !head_known) {
        lantern_client_adopt_peer_genesis(client, peer_status, peer_copy);
        head_known = true;
    }

    if (pthread_mutex_lock(&client->status_lock) != 0) {
        return;
    }

    struct lantern_peer_status_entry *entry = lantern_client_ensure_status_entry_locked(client, peer_copy);
    if (!entry) {
        pthread_mutex_unlock(&client->status_lock);
        return;
    }
    entry->status_request_inflight = false;
    lantern_client_status_request_update_locked(client, entry, peer_copy, -1, "complete");

    string_list_remove(&client->status_failure_peer_ids, peer_copy);

    bool had_status = entry->has_status;
    LanternStatusMessage previous_status = entry->status;
    bool head_changed = !had_status
        || previous_status.head.slot != peer_status->head.slot
        || memcmp(previous_status.head.root.bytes, peer_status->head.root.bytes, LANTERN_ROOT_SIZE) != 0;

    entry->status = *peer_status;
    entry->has_status = true;
    bool needs_block = !head_known;
    const char *needs_block_reason = NULL;
    if (!head_known) {
        needs_block_reason = "head unknown locally";
    }
    if (!needs_block && head_changed && peer_status->head.slot > local_slot) {
        needs_block = true;
        needs_block_reason = "remote head ahead of local slot";
    }
    struct lantern_log_metadata status_meta = {
        .validator = client->node_id,
        .peer = peer_copy[0] ? peer_copy : NULL,
    };
    if (needs_block) {
        lantern_log_info(
            "reqresp",
            &status_meta,
            "status needs block head_slot=%" PRIu64 " local_slot=%" PRIu64 " head_root=%s reason=%s",
            peer_status->head.slot,
            local_slot,
            head_hex[0] ? head_hex : "0x0",
            needs_block_reason ? needs_block_reason : "unspecified");
    }
    if (needs_block && !entry->requested_head) {
        uint64_t now_ms = monotonic_millis();
        uint64_t backoff_ms = blocks_request_backoff_ms(entry->consecutive_blocks_failures);
        if (entry->consecutive_blocks_failures == 0 && backoff_ms < LANTERN_BLOCKS_REQUEST_MIN_POLL_MS) {
            backoff_ms = LANTERN_BLOCKS_REQUEST_MIN_POLL_MS;
        }
        bool within_backoff = entry->last_blocks_request_ms != 0
            && now_ms < entry->last_blocks_request_ms + backoff_ms;
        if (!within_backoff) {
            entry->requested_head = true;
            entry->last_blocks_request_ms = now_ms;
            should_request = true;
        } else {
            uint64_t resume_ms = entry->last_blocks_request_ms + backoff_ms;
            uint64_t remaining_ms = resume_ms > now_ms ? (resume_ms - now_ms) : 0;
            lantern_log_debug(
                "reqresp",
                &(const struct lantern_log_metadata){
                    .validator = client->node_id,
                    .peer = peer_copy},
                "backing off blocks_by_root head=%s failures=%u remaining_ms=%" PRIu64,
                head_hex[0] ? head_hex : "0x0",
                entry->consecutive_blocks_failures,
                remaining_ms);
        }
    } else if (!needs_block) {
        lantern_log_trace(
            "reqresp",
            &(const struct lantern_log_metadata){
                .validator = client->node_id,
                .peer = peer_copy},
            "skipping blocks_by_root for known head slot=%" PRIu64 " root=%s",
            peer_status->head.slot,
            head_hex[0] ? head_hex : "0x0");
    }

    pthread_mutex_unlock(&client->status_lock);

    if (should_request) {
        if (lantern_client_schedule_blocks_request(client, peer_copy, &request_root, false) != 0) {
            lantern_client_on_blocks_request_complete(
                client,
                peer_copy,
                &request_root,
                LANTERN_BLOCKS_REQUEST_ABORTED);
        }
    }
}

static void lantern_client_adopt_peer_genesis(
    struct lantern_client *client,
    const LanternStatusMessage *peer_status,
    const char *peer_id_text) {
    if (!client || !peer_status || !client->has_fork_choice) {
        return;
    }

    LanternBlock anchor;
    memset(&anchor, 0, sizeof(anchor));
    anchor.slot = 0;
    anchor.proposer_index = 0;
    /* Use the peer's advertised head root as both state_root and hint so our fork-choice
       anchor matches the peer even if we cannot reproduce their SSZ state. */
    anchor.state_root = peer_status->head.root;
    /* empty body / zero attestations */
    LanternCheckpoint zero_cp = {.root = {{0}}, .slot = 0};

    if (lantern_fork_choice_set_anchor(
            &client->fork_choice,
            &anchor,
            &peer_status->finalized,
            &peer_status->finalized,
            &peer_status->head.root)
        != 0) {
        lantern_log_warn(
            "fork_choice",
            &(const struct lantern_log_metadata){.validator = client->node_id, .peer = peer_id_text},
            "failed to adopt peer genesis root");
        return;
    }

    (void)lantern_fork_choice_set_block_validator_count(
        &client->fork_choice,
        &peer_status->head.root,
        client->state.config.num_validators);
    client->genesis_fallback_used = false;

    char head_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    format_root_hex(&peer_status->head.root, head_hex, sizeof(head_hex));
    lantern_log_info(
        "fork_choice",
        &(const struct lantern_log_metadata){.validator = client->node_id, .peer = peer_id_text},
        "adopted peer genesis head_slot=0 root=%s",
        head_hex);
}

static void lantern_client_on_blocks_request_complete(
    struct lantern_client *client,
    const char *peer_id,
    const LanternRoot *request_root,
    enum lantern_blocks_request_outcome outcome) {
    if (!client || !peer_id || !client->status_lock_initialized) {
        return;
    }
    const size_t peer_cap = sizeof(((struct lantern_peer_status_entry *)0)->peer_id);
    uint32_t failure_count = 0;
    bool entry_found = false;
    if (pthread_mutex_lock(&client->status_lock) != 0) {
        return;
    }
    for (size_t i = 0; i < client->peer_status_count; ++i) {
        struct lantern_peer_status_entry *entry = &client->peer_status_entries[i];
        if (strncmp(entry->peer_id, peer_id, peer_cap) == 0) {
            entry->requested_head = false;
            switch (outcome) {
            case LANTERN_BLOCKS_REQUEST_SUCCESS:
                entry->consecutive_blocks_failures = 0;
                break;
            case LANTERN_BLOCKS_REQUEST_FAILED:
                if (entry->consecutive_blocks_failures < UINT32_MAX) {
                    entry->consecutive_blocks_failures += 1;
                }
                break;
            case LANTERN_BLOCKS_REQUEST_ABORTED:
                entry->last_blocks_request_ms = 0;
                break;
            default:
                break;
            }
            if (outcome != LANTERN_BLOCKS_REQUEST_ABORTED && entry->last_blocks_request_ms == 0) {
                entry->last_blocks_request_ms = monotonic_millis();
            }
            failure_count = entry->consecutive_blocks_failures;
            entry_found = true;
            break;
        }
    }
    pthread_mutex_unlock(&client->status_lock);

    char root_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    root_hex[0] = '\0';
    if (request_root) {
        format_root_hex(request_root, root_hex, sizeof(root_hex));
    }
    const char *outcome_text = "unknown";
    switch (outcome) {
    case LANTERN_BLOCKS_REQUEST_SUCCESS:
        outcome_text = "success";
        break;
    case LANTERN_BLOCKS_REQUEST_FAILED:
        outcome_text = "failed";
        break;
    case LANTERN_BLOCKS_REQUEST_ABORTED:
        outcome_text = "aborted";
        break;
    default:
        break;
    }
    lantern_log_info(
        "reqresp",
        &(const struct lantern_log_metadata){
            .validator = client->node_id,
            .peer = peer_id},
        "blocks_by_root complete outcome=%s root=%s entry_found=%s consecutive_failures=%" PRIu32,
        outcome_text,
        root_hex[0] ? root_hex : "0x0",
        entry_found ? "true" : "false",
        failure_count);

    if (request_root && !lantern_root_is_zero(request_root)) {
        bool locked = lantern_client_lock_pending(client);
        if (locked) {
            for (size_t i = 0; i < client->pending_blocks.length; ++i) {
                struct lantern_pending_block *entry = &client->pending_blocks.items[i];
                if (memcmp(entry->parent_root.bytes, request_root->bytes, LANTERN_ROOT_SIZE) == 0) {
                    entry->parent_requested = false;
                }
            }
            lantern_client_unlock_pending(client, locked);
        } else {
            for (size_t i = 0; i < client->pending_blocks.length; ++i) {
                struct lantern_pending_block *entry = &client->pending_blocks.items[i];
                if (memcmp(entry->parent_root.bytes, request_root->bytes, LANTERN_ROOT_SIZE) == 0) {
                    entry->parent_requested = false;
        }
    }

    if (outcome == LANTERN_BLOCKS_REQUEST_SUCCESS && peer_id && peer_id[0] != '\0') {
        peer_id_t parsed_peer = {0};
        bool parsed = false;
        if (peer_id_create_from_string(peer_id, &parsed_peer) == PEER_ID_SUCCESS) {
            parsed = true;
        }
        request_status_now(client, parsed ? &parsed_peer : NULL, peer_id);
        if (parsed) {
            peer_id_destroy(&parsed_peer);
        }
    }
}
    }

}

static int stream_write_all(libp2p_stream_t *stream, const uint8_t *data, size_t length) {
    if (!stream || (!data && length > 0)) {
        return -1;
    }
    size_t offset = 0;
    while (offset < length) {
        ssize_t written = libp2p_stream_write(stream, data + offset, length - offset);
        if (written > 0) {
            offset += (size_t)written;
            continue;
        }
        if (written == (ssize_t)LIBP2P_ERR_AGAIN || written == (ssize_t)LIBP2P_ERR_TIMEOUT) {
            continue;
        }
        return -1;
    }
    return 0;
}

static int read_stream_varint(
    libp2p_stream_t *stream,
    uint64_t *out_value,
    const struct lantern_log_metadata *meta,
    const char *label,
    ssize_t *out_err) {
    if (!stream || !out_value) {
        if (out_err) {
            *out_err = LIBP2P_ERR_NULL_PTR;
        }
        return -1;
    }

    uint8_t header[LANTERN_REQRESP_HEADER_MAX_BYTES];
    size_t header_used = 0;
    uint64_t value = 0;
    ssize_t last_err = 0;

    while (header_used < sizeof(header)) {
        (void)libp2p_stream_set_deadline(stream, LANTERN_REQRESP_STALL_TIMEOUT_MS);
        ssize_t n = libp2p_stream_read(stream, &header[header_used], 1);
        if (n == 1) {
            header_used += 1;
            size_t consumed = 0;
            if (unsigned_varint_decode(header, header_used, &value, &consumed) == UNSIGNED_VARINT_OK) {
                lantern_log_trace(
                    "reqresp",
                    meta,
                    "%s decoded length=%" PRIu64,
                    label ? label : "varint",
                    value);
                (void)libp2p_stream_set_deadline(stream, 0);
                *out_value = value;
                if (out_err) {
                    *out_err = 0;
                }
                return 0;
            }
            continue;
        }
        if (n == (ssize_t)LIBP2P_ERR_AGAIN) {
            continue;
        }
        if (n == 0 || n == (ssize_t)LIBP2P_ERR_EOF || n == (ssize_t)LIBP2P_ERR_CLOSED || n == (ssize_t)LIBP2P_ERR_RESET) {
            last_err = n == 0 ? (ssize_t)LIBP2P_ERR_EOF : n;
            break;
        }
        last_err = n;
        break;
    }
    (void)libp2p_stream_set_deadline(stream, 0);

    if (out_err) {
        *out_err = last_err == 0 ? LIBP2P_ERR_INTERNAL : last_err;
    }
    lantern_log_trace(
        "reqresp",
        meta,
        "%s decode failed err=%zd bytes=%zu",
        label ? label : "varint",
        last_err == 0 ? (ssize_t)LIBP2P_ERR_INTERNAL : last_err,
        header_used);
    return -1;
}

static int discard_stream_bytes(
    libp2p_stream_t *stream,
    uint64_t length,
    const struct lantern_log_metadata *meta,
    const char *label,
    ssize_t *out_err) {
    if (!stream) {
        if (out_err) {
            *out_err = LIBP2P_ERR_NULL_PTR;
        }
        return -1;
    }
    uint8_t buffer[256];
    uint64_t remaining = length;
    while (remaining > 0) {
        size_t chunk = remaining > sizeof(buffer) ? sizeof(buffer) : (size_t)remaining;
        (void)libp2p_stream_set_deadline(stream, LANTERN_REQRESP_STALL_TIMEOUT_MS);
        ssize_t n = libp2p_stream_read(stream, buffer, chunk);
        if (n > 0) {
            remaining -= (size_t)n;
            continue;
        }
        if (n == (ssize_t)LIBP2P_ERR_AGAIN) {
            continue;
        }
        (void)libp2p_stream_set_deadline(stream, 0);
        if (out_err) {
            *out_err = n == 0 ? (ssize_t)LIBP2P_ERR_EOF : n;
        }
        lantern_log_trace(
            "reqresp",
            meta,
            "%s discard failed err=%zd remaining=%" PRIu64,
            label ? label : "context",
            n,
            remaining);
        return -1;
    }
    (void)libp2p_stream_set_deadline(stream, 0);
    lantern_log_trace(
        "reqresp",
        meta,
        "%s discarded bytes=%" PRIu64,
        label ? label : "context",
        length);
    if (out_err) {
        *out_err = 0;
    }
    return 0;
}

int lantern_reqresp_read_response_chunk(
    struct lantern_reqresp_service *service,
    libp2p_stream_t *stream,
    enum lantern_reqresp_protocol_kind protocol,
    uint8_t **out_data,
    size_t *out_len,
    ssize_t *out_err,
    uint8_t *out_response_code,
    bool *response_code_pending) {
    if (!stream || !out_data || !out_len) {
        if (out_err) {
            *out_err = LIBP2P_ERR_NULL_PTR;
        }
        return -1;
    }
    if (out_response_code) {
        *out_response_code = LANTERN_REQRESP_RESPONSE_SERVER_ERROR;
    }

    char peer_text[128];
    peer_text[0] = '\0';
    const peer_id_t *peer = libp2p_stream_remote_peer(stream);
    if (peer && peer_id_to_string(peer, PEER_ID_FMT_BASE58_LEGACY, peer_text, sizeof(peer_text)) < 0) {
        peer_text[0] = '\0';
    }
    const struct lantern_log_metadata meta = {.peer = peer_text[0] ? peer_text : NULL};

    (void)libp2p_stream_set_read_interest(stream, true);

    uint8_t response_code = 0;
    bool expect_code = response_code_pending
        ? *response_code_pending
        : ((protocol == LANTERN_REQRESP_PROTOCOL_STATUS) || (protocol == LANTERN_REQRESP_PROTOCOL_BLOCKS_BY_ROOT));
    bool legacy_no_code = !expect_code;
    ssize_t last_err = 0;
    uint8_t frame_code = 0;
    if (expect_code) {
        while (true) {
            (void)libp2p_stream_set_deadline(stream, LANTERN_REQRESP_STALL_TIMEOUT_MS);
            ssize_t n = libp2p_stream_read(stream, &response_code, 1);
            if (n == 1) {
                frame_code = response_code;
                break;
            }
            if (n == (ssize_t)LIBP2P_ERR_AGAIN) {
                continue;
            }
            (void)libp2p_stream_set_deadline(stream, 0);
            last_err = n == 0 ? (ssize_t)LIBP2P_ERR_EOF : n;
            if (out_err) {
                *out_err = last_err;
            }
            lantern_log_trace(
                "reqresp",
                &meta,
                "response code read failed err=%zd",
                last_err);
            return -1;
        }
        (void)libp2p_stream_set_deadline(stream, 0);
        if (response_code > LANTERN_REQRESP_RESPONSE_SERVER_ERROR) {
            legacy_no_code = true;
            if (out_response_code) {
                *out_response_code = LANTERN_REQRESP_RESPONSE_SUCCESS;
            }
            lantern_log_trace(
                "reqresp",
                &meta,
                "legacy response missing code, treating first byte as header (0x%02x)",
                (unsigned)response_code);
            lantern_log_info(
                "reqresp",
                &meta,
                "response legacy framing first_byte=0x%02x",
                (unsigned)response_code);
            if (service && peer_text[0] != '\0') {
#if defined(LANTERN_REQRESP_STATUS_PROTOCOL_LEGACY) || defined(LANTERN_REQRESP_BLOCKS_BY_ROOT_PROTOCOL_LEGACY)
                lantern_reqresp_service_hint_peer_legacy(service, peer_text, 1);
#endif
            }
        } else {
            if (out_response_code) {
                *out_response_code = response_code;
            }
            frame_code = response_code;
            lantern_log_info(
                "reqresp",
                &meta,
                "response code=%u",
                (unsigned)response_code);
            if (service && peer_text[0] != '\0') {
#if defined(LANTERN_REQRESP_STATUS_PROTOCOL_LEGACY) || defined(LANTERN_REQRESP_BLOCKS_BY_ROOT_PROTOCOL_LEGACY)
                lantern_reqresp_service_hint_peer_legacy(service, peer_text, 0);
#endif
            }
        }
    } else {
        if (out_response_code) {
            *out_response_code = LANTERN_REQRESP_RESPONSE_SUCCESS;
        }
    }
    if (response_code_pending) {
        *response_code_pending = false;
    }

    uint8_t header_first_byte = 0;
    if (legacy_no_code && expect_code) {
        header_first_byte = response_code;
    } else {
        while (true) {
            (void)libp2p_stream_set_deadline(stream, LANTERN_REQRESP_STALL_TIMEOUT_MS);
            ssize_t n = libp2p_stream_read(stream, &header_first_byte, 1);
            if (n == 1) {
                break;
            }
            if (n == (ssize_t)LIBP2P_ERR_AGAIN) {
                continue;
            }
            (void)libp2p_stream_set_deadline(stream, 0);
            last_err = n == 0 ? (ssize_t)LIBP2P_ERR_EOF : n;
            if (out_err) {
                *out_err = last_err;
            }
            lantern_log_trace(
                "reqresp",
                &meta,
                "response payload header read failed err=%zd",
                last_err);
            return -1;
        }
        (void)libp2p_stream_set_deadline(stream, 0);
    }

    lantern_log_trace(
        "reqresp",
        &meta,
        "response using varint framing code=0x%02x header_first=0x%02x",
        (unsigned)frame_code,
        (unsigned)header_first_byte);

    return read_varint_payload_chunk(
        stream,
        header_first_byte,
        out_data,
        out_len,
        out_err,
        &meta,
        "chunk");
}

static int read_varint_payload_chunk(
    libp2p_stream_t *stream,
    uint8_t first_byte,
    uint8_t **out_data,
    size_t *out_len,
    ssize_t *out_err,
    const struct lantern_log_metadata *meta,
    const char *label) {
    if (!stream || !out_data || !out_len) {
        if (out_err) {
            *out_err = LIBP2P_ERR_NULL_PTR;
        }
        return -1;
    }

    uint8_t header[LANTERN_REQRESP_HEADER_MAX_BYTES];
    size_t used = 0;
    uint64_t payload_len = 0;
    size_t consumed = 0;
    header[used++] = first_byte;

    while (true) {
        if (unsigned_varint_decode(header, used, &payload_len, &consumed) == UNSIGNED_VARINT_OK) {
            break;
        }
        if (used == sizeof(header)) {
            if (out_err) {
                *out_err = LIBP2P_ERR_INTERNAL;
            }
            lantern_log_warn(
                "reqresp",
                meta,
                "%s varint header exceeded limit",
                label ? label : "chunk");
            return -1;
        }
        (void)libp2p_stream_set_deadline(stream, LANTERN_REQRESP_STALL_TIMEOUT_MS);
        ssize_t n = libp2p_stream_read(stream, &header[used], 1);
        if (n == 1) {
            used += 1;
            continue;
        }
        if (n == (ssize_t)LIBP2P_ERR_AGAIN) {
            continue;
        }
        (void)libp2p_stream_set_deadline(stream, 0);
        if (out_err) {
            *out_err = n == 0 ? (ssize_t)LIBP2P_ERR_EOF : n;
        }
        lantern_log_warn(
            "reqresp",
            meta,
            "%s header read failed err=%zd",
            label ? label : "chunk",
            n);
        return -1;
    }
    (void)libp2p_stream_set_deadline(stream, 0);

    char header_hex[(sizeof(header) * 2) + 1];
    header_hex[0] = '\0';
    if (lantern_bytes_to_hex(header, consumed, header_hex, sizeof(header_hex), 0) != 0) {
        header_hex[0] = '\0';
    }

    lantern_log_info(
        "reqresp",
        meta,
        "%s payload_len=%" PRIu64 " header_hex=%s",
        label ? label : "chunk",
        payload_len,
        header_hex[0] ? header_hex : "-");
    if (payload_len > 512) {
        lantern_log_warn(
            "reqresp",
            meta,
            "%s suspicious large payload_len=%" PRIu64 " header_hex=%s",
            label ? label : "chunk",
            payload_len,
            header_hex[0] ? header_hex : "-");
    }

    if (payload_len > LANTERN_REQRESP_MAX_CHUNK_BYTES || payload_len > SIZE_MAX) {
        if (out_err) {
            *out_err = LIBP2P_ERR_MSG_TOO_LARGE;
        }
        lantern_log_warn(
            "reqresp",
            meta,
            "%s payload too large=%" PRIu64,
            label ? label : "chunk",
            payload_len);
        return -1;
    }

    if (payload_len == 0) {
        *out_data = NULL;
        *out_len = 0;
        if (out_err) {
            *out_err = 0;
        }
        return 0;
    }

    size_t payload_size = (size_t)payload_len;
    uint8_t *buffer = (uint8_t *)malloc(payload_size);
    if (!buffer) {
        if (out_err) {
            *out_err = -ENOMEM;
        }
        lantern_log_error(
            "reqresp",
            meta,
            "%s payload allocation failed bytes=%zu",
            label ? label : "chunk",
            payload_size);
        return -1;
    }

    size_t collected = 0;
    while (collected < payload_size) {
        (void)libp2p_stream_set_deadline(stream, LANTERN_REQRESP_STALL_TIMEOUT_MS);
        ssize_t n = libp2p_stream_read(stream, buffer + collected, payload_size - collected);
        if (n > 0) {
            collected += (size_t)n;
            continue;
        }
        if (n == (ssize_t)LIBP2P_ERR_AGAIN) {
            continue;
        }
        (void)libp2p_stream_set_deadline(stream, 0);
        if (collected > 0) {
            char partial_hex[(LANTERN_STATUS_PREVIEW_BYTES * 2u) + 1u];
            size_t preview_len = collected < LANTERN_STATUS_PREVIEW_BYTES ? collected : LANTERN_STATUS_PREVIEW_BYTES;
            if (lantern_bytes_to_hex(buffer, preview_len, partial_hex, sizeof(partial_hex), 0) != 0) {
                partial_hex[0] = '\0';
            }
        lantern_log_trace(
            "reqresp",
            meta,
            "%s payload partial hex=%s%s",
            label ? label : "chunk",
            partial_hex[0] ? partial_hex : "-",
            (collected > preview_len) ? "..." : "");
        }
        free(buffer);
        if (out_err) {
            *out_err = n == 0 ? (ssize_t)LIBP2P_ERR_EOF : n;
        }
        lantern_log_warn(
            "reqresp",
            meta,
            "%s payload read failed err=%zd collected=%zu/%zu",
            label ? label : "chunk",
            n,
            collected,
            payload_size);
        return -1;
    }
    (void)libp2p_stream_set_deadline(stream, 0);

    *out_data = buffer;
    *out_len = payload_size;
    if (out_err) {
        *out_err = 0;
    }
    char payload_hex[(LANTERN_STATUS_PREVIEW_BYTES * 2u) + 1u];
    payload_hex[0] = '\0';
    size_t preview = payload_size < LANTERN_STATUS_PREVIEW_BYTES ? payload_size : LANTERN_STATUS_PREVIEW_BYTES;
    if (preview > 0
        && lantern_bytes_to_hex(buffer, preview, payload_hex, sizeof(payload_hex), 0) != 0) {
        payload_hex[0] = '\0';
    }
    lantern_log_info(
        "reqresp",
        meta,
        "%s payload read complete bytes=%zu%s%s",
        label ? label : "chunk",
        payload_size,
        payload_hex[0] ? " hex=" : "",
        payload_hex[0] ? payload_hex : "");
    return 0;
}

static void block_request_ctx_free(struct block_request_ctx *ctx) {
    if (!ctx) {
        return;
    }
    peer_id_destroy(&ctx->peer_id);
    free(ctx);
}

static bool lantern_client_process_stream_block_chunk(
    struct block_request_ctx *ctx,
    uint8_t *chunk,
    size_t chunk_len,
    const struct lantern_log_metadata *meta,
    bool *saw_block) {
    if (!chunk || chunk_len == 0) {
        free(chunk);
        return true;
    }
    if (!ctx) {
        free(chunk);
        return false;
    }
    size_t raw_len = 0;
    if (lantern_snappy_uncompressed_length(chunk, chunk_len, &raw_len) != LANTERN_SNAPPY_OK || raw_len == 0) {
        lantern_log_error(
            "reqresp",
            meta,
            "blocks_by_root chunk snappy length failed bytes=%zu",
            chunk_len);
        free(chunk);
        return false;
    }
    uint8_t *raw_block = (uint8_t *)malloc(raw_len);
    if (!raw_block) {
        lantern_log_error(
            "reqresp",
            meta,
            "blocks_by_root chunk allocation failed bytes=%zu",
            raw_len);
        free(chunk);
        return false;
    }
    size_t written = raw_len;
    if (lantern_snappy_decompress(chunk, chunk_len, raw_block, raw_len, &written) != LANTERN_SNAPPY_OK) {
        lantern_log_error(
            "reqresp",
            meta,
            "blocks_by_root chunk decompress failed bytes=%zu",
            chunk_len);
        free(raw_block);
        free(chunk);
        return false;
    }

    LanternSignedBlock streamed_block;
    lantern_signed_block_with_attestation_init(&streamed_block);
    if (lantern_ssz_decode_signed_block(&streamed_block, raw_block, written) != 0) {
        lantern_log_error(
            "reqresp",
            meta,
            "blocks_by_root chunk decode failed bytes=%zu",
            written);
        lantern_signed_block_with_attestation_reset(&streamed_block);
        free(raw_block);
        free(chunk);
        return false;
    }
    free(raw_block);

    LanternRoot computed = {{0}};
    if (lantern_hash_tree_root_block(&streamed_block.message.block, &computed) != 0) {
        lantern_log_warn(
            "reqresp",
            meta,
            "failed to hash streamed block slot=%" PRIu64,
            streamed_block.message.block.slot);
        lantern_signed_block_with_attestation_reset(&streamed_block);
        free(chunk);
        return true;
    }

    char computed_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    format_root_hex(&computed, computed_hex, sizeof(computed_hex));
    bool matches = memcmp(computed.bytes, ctx->root.bytes, LANTERN_ROOT_SIZE) == 0;
    lantern_log_info(
        "reqresp",
        meta,
        "streamed block slot=%" PRIu64 " proposer=%" PRIu64 " root=%s match=%s attestations=%zu",
        streamed_block.message.block.slot,
        streamed_block.message.block.proposer_index,
        computed_hex[0] ? computed_hex : "0x0",
        matches ? "true" : "false",
        streamed_block.message.block.body.attestations.length);

    lantern_client_record_block(
        ctx->client,
        &streamed_block,
        &computed,
        ctx->peer_text[0] ? ctx->peer_text : NULL,
        "reqresp");
    lantern_signed_block_with_attestation_reset(&streamed_block);
    if (saw_block) {
        *saw_block = true;
    }
    free(chunk);
    return true;
}

static void *block_request_worker(void *arg) {
    struct block_request_worker_args *worker = (struct block_request_worker_args *)arg;
    if (!worker) {
        return NULL;
    }
    struct block_request_ctx *ctx = worker->ctx;
    libp2p_stream_t *stream = worker->stream;
    free(worker);
    if (!ctx || !stream) {
        if (stream) {
            libp2p_stream_free(stream);
        }
        block_request_ctx_free(ctx);
        return NULL;
    }

    struct lantern_log_metadata meta = {
        .validator = ctx->client ? ctx->client->node_id : NULL,
        .peer = ctx->peer_text[0] ? ctx->peer_text : NULL,
    };

    char root_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    format_root_hex(&ctx->root, root_hex, sizeof(root_hex));

    LanternBlocksByRootRequest request;
    lantern_blocks_by_root_request_init(&request);

    LanternBlocksByRootResponse response_msg;
    lantern_blocks_by_root_response_init(&response_msg);

    uint8_t *payload = NULL;
    uint8_t *response = NULL;
    bool request_success = false;
    bool schedule_legacy = false;
    bool attempt_legacy = false;
    struct lantern_client *legacy_client = NULL;
    LanternRoot legacy_root = ctx->root;
    char legacy_peer[sizeof(ctx->peer_text)];
    legacy_peer[0] = '\0';

    if (lantern_root_list_resize(&request.roots, 1) != 0) {
        lantern_log_error(
            "reqresp",
            &meta,
            "failed to size blocks_by_root request");
        schedule_legacy = !ctx->using_legacy;
        goto cleanup;
    }
    request.roots.items[0] = ctx->root;

    size_t raw_size = sizeof(uint32_t) + (request.roots.length * LANTERN_ROOT_SIZE);
    size_t max_payload = 0;
    if (lantern_snappy_max_compressed_size(raw_size, &max_payload) != LANTERN_SNAPPY_OK) {
        lantern_log_error(
            "reqresp",
            &meta,
            "failed to compute snappy size for blocks_by_root request");
        schedule_legacy = !ctx->using_legacy;
        goto cleanup;
    }

    payload = (uint8_t *)malloc(max_payload);
    if (!payload) {
        lantern_log_error(
            "reqresp",
            &meta,
            "out of memory building blocks_by_root request");
        schedule_legacy = !ctx->using_legacy;
        goto cleanup;
    }

    size_t payload_len = 0;
    if (lantern_network_blocks_by_root_request_encode_snappy(&request, payload, max_payload, &payload_len, NULL) != 0
        || payload_len == 0) {
        lantern_log_error(
            "reqresp",
            &meta,
            "failed to encode blocks_by_root request");
        schedule_legacy = !ctx->using_legacy;
        goto cleanup;
    }

    if (raw_size > 0) {
        uint8_t *plain_bytes = (uint8_t *)malloc(raw_size);
        size_t plain_written = raw_size;
        if (plain_bytes
            && lantern_network_blocks_by_root_request_encode(&request, plain_bytes, raw_size, &plain_written) == 0) {
            size_t plain_preview = plain_written < LANTERN_STATUS_PREVIEW_BYTES
                ? plain_written
                : LANTERN_STATUS_PREVIEW_BYTES;
            if (plain_preview > 0) {
                char plain_hex[(LANTERN_STATUS_PREVIEW_BYTES * 2u) + 1u];
                if (lantern_bytes_to_hex(
                        plain_bytes,
                        plain_preview,
                        plain_hex,
                        sizeof(plain_hex),
                        0)
                    == 0) {
                    lantern_log_trace(
                        "reqresp",
                        &meta,
                        "blocks_by_root request roots_hex=%s%s",
                        plain_hex,
                        (plain_written > plain_preview) ? "..." : "");
                }
            }
        }
        free(plain_bytes);
    }

    size_t payload_preview = payload_len < LANTERN_STATUS_PREVIEW_BYTES ? payload_len : LANTERN_STATUS_PREVIEW_BYTES;
    if (payload_preview > 0) {
        char payload_hex[(LANTERN_STATUS_PREVIEW_BYTES * 2u) + 1u];
        if (lantern_bytes_to_hex(
                payload,
                payload_preview,
                payload_hex,
                sizeof(payload_hex),
                0)
            == 0) {
            lantern_log_trace(
                "reqresp",
                &meta,
                "blocks_by_root request snappy_hex=%s%s",
                payload_hex,
                (payload_len > payload_preview) ? "..." : "");
        }
    }

    uint8_t header[LANTERN_REQRESP_HEADER_MAX_BYTES];
    size_t header_len = 0;
    if (unsigned_varint_encode(payload_len, header, sizeof(header), &header_len) != UNSIGNED_VARINT_OK) {
        lantern_log_error(
            "reqresp",
            &meta,
            "failed to encode blocks_by_root header length=%zu",
            payload_len);
        schedule_legacy = !ctx->using_legacy;
        goto cleanup;
    }

    lantern_log_info(
        "reqresp",
        &meta,
        "sending %s request root=%s bytes=%zu",
        ctx->protocol_id,
        root_hex[0] ? root_hex : "0x0",
        payload_len);

    if (stream_write_all(stream, header, header_len) != 0 || stream_write_all(stream, payload, payload_len) != 0) {
        lantern_log_error(
            "reqresp",
            &meta,
            "failed to write blocks_by_root request");
        schedule_legacy = !ctx->using_legacy;
        goto cleanup;
    }

    struct lantern_reqresp_service *service = ctx->client ? &ctx->client->reqresp : NULL;
    bool streaming_mode = !ctx->using_legacy;
    uint8_t *initial_chunk = NULL;
    size_t initial_chunk_len = 0;
    bool initial_chunk_pending = false;
    bool response_code_pending = true;
    bool saw_block = false;

    if (ctx->using_legacy) {
        size_t response_len = 0;
        ssize_t read_err = 0;
        uint8_t response_code = LANTERN_REQRESP_RESPONSE_SUCCESS;
        if (lantern_reqresp_read_response_chunk(
                service,
                stream,
                LANTERN_REQRESP_PROTOCOL_BLOCKS_BY_ROOT,
                &response,
                &response_len,
                &read_err,
                &response_code,
                NULL)
            != 0) {
            lantern_log_error(
                "reqresp",
                &meta,
                "failed to read blocks_by_root response err=%zd",
                read_err);
            schedule_legacy = !ctx->using_legacy;
            goto cleanup;
        }

        if (response_len > 0 && response) {
            size_t preview_len = response_len < LANTERN_STATUS_PREVIEW_BYTES ? response_len : LANTERN_STATUS_PREVIEW_BYTES;
            char response_hex[(LANTERN_STATUS_PREVIEW_BYTES * 2u) + 1u];
            if (lantern_bytes_to_hex(response, preview_len, response_hex, sizeof(response_hex), 0) != 0) {
                response_hex[0] = '\0';
            }
            lantern_log_trace(
                "reqresp",
                &meta,
                "blocks_by_root raw payload_len=%zu%s%s",
                response_len,
                preview_len > 0 ? " hex=" : "",
                preview_len > 0 ? response_hex : "");
        } else {
            lantern_log_trace(
                "reqresp",
                &meta,
                "blocks_by_root raw payload_len=%zu (empty)",
                response_len);
        }

        if (response_code != LANTERN_REQRESP_RESPONSE_SUCCESS) {
            lantern_log_error(
                "reqresp",
                &meta,
                "blocks_by_root response returned code=%u payload_len=%zu",
                (unsigned)response_code,
                response_len);
            schedule_legacy = !ctx->using_legacy;
            goto cleanup;
        }

        if (response_len == 0 || !response) {
            lantern_log_info(
                "reqresp",
                &meta,
                "received 0 block(s) via %s (empty payload)",
                ctx->protocol_id);
            request_success = true;
            goto cleanup;
        }

        if (lantern_network_blocks_by_root_response_decode_snappy(&response_msg, response, response_len) != 0) {
            size_t preview_len = response_len < LANTERN_STATUS_PREVIEW_BYTES ? response_len : LANTERN_STATUS_PREVIEW_BYTES;
            char response_hex[(LANTERN_STATUS_PREVIEW_BYTES * 2u) + 1u];
            if (preview_len > 0
                && lantern_bytes_to_hex(response, preview_len, response_hex, sizeof(response_hex), 0) != 0) {
                response_hex[0] = '\0';
            }
            lantern_log_error(
                "reqresp",
                &meta,
                "failed to decode blocks_by_root response bytes=%zu%s%s",
                response_len,
                preview_len > 0 ? " hex=" : "",
                preview_len > 0 ? response_hex : "");
            if (response && response_len > 0) {
                char root_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
                format_root_hex(&ctx->root, root_hex, sizeof(root_hex));
                const char *suffix = root_hex;
                if (suffix[0] == '0' && (suffix[1] == 'x' || suffix[1] == 'X')) {
                    suffix += 2;
                }
                char dump_path[256];
                if (snprintf(dump_path, sizeof(dump_path), "/data/lantern_blocks_by_root_failed_%s.bin", suffix) > 0) {
                    FILE *dump = fopen(dump_path, "wb");
                    if (dump) {
                        (void)fwrite(response, 1, response_len, dump);
                        fclose(dump);
                    }
                }
            }
            if (!streaming_mode && response && response_len > 0) {
                lantern_log_info(
                    "reqresp",
                    &meta,
                    "legacy decode failed; interpreting payload as streaming chunk");
                streaming_mode = true;
                response_code_pending = false;
                initial_chunk = response;
                initial_chunk_len = response_len;
                response = NULL;
                initial_chunk_pending = true;
            } else {
                schedule_legacy = !ctx->using_legacy;
                goto cleanup;
            }
        } else {
            lantern_log_info(
                "reqresp",
                &meta,
                "received %zu block(s) via %s",
                response_msg.length,
                ctx->protocol_id);

            for (size_t i = 0; i < response_msg.length; ++i) {
                LanternRoot computed = {{0}};
                if (lantern_hash_tree_root_block(&response_msg.blocks[i].message.block, &computed) != 0) {
                    lantern_log_warn(
                        "reqresp",
                        &meta,
                        "failed to hash block index=%zu slot=%" PRIu64,
                        i,
                        response_msg.blocks[i].message.slot);
                    continue;
                }
                char computed_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
                format_root_hex(&computed, computed_hex, sizeof(computed_hex));
                bool matches = memcmp(computed.bytes, ctx->root.bytes, LANTERN_ROOT_SIZE) == 0;
                lantern_log_info(
                    "reqresp",
                    &meta,
                    "block index=%zu slot=%" PRIu64 " proposer=%" PRIu64 " root=%s match=%s attestations=%zu",
                    i,
                    response_msg.blocks[i].message.slot,
                    response_msg.blocks[i].message.proposer_index,
                    computed_hex[0] ? computed_hex : "0x0",
                    matches ? "true" : "false",
                    response_msg.blocks[i].message.body.attestations.length);

                lantern_client_record_block(
                    ctx->client,
                    &response_msg.blocks[i],
                    &computed,
                    ctx->peer_text[0] ? ctx->peer_text : NULL,
                    "reqresp");
            }

            request_success = (response_msg.length > 0);
            if (!streaming_mode) {
                goto cleanup;
            }
        }
    }

    if (streaming_mode) {
        if (initial_chunk_pending) {
            if (!lantern_client_process_stream_block_chunk(ctx, initial_chunk, initial_chunk_len, &meta, &saw_block)) {
                initial_chunk = NULL;
                schedule_legacy = !ctx->using_legacy;
                goto cleanup;
            }
            initial_chunk = NULL;
            initial_chunk_pending = false;
        }

        while (true) {
            uint8_t *chunk = NULL;
            size_t chunk_len = 0;
            ssize_t read_err = 0;
            uint8_t chunk_code = LANTERN_REQRESP_RESPONSE_SUCCESS;
            int chunk_rc = lantern_reqresp_read_response_chunk(
                service,
                stream,
                LANTERN_REQRESP_PROTOCOL_BLOCKS_BY_ROOT,
                &chunk,
                &chunk_len,
                &read_err,
                &chunk_code,
                &response_code_pending);
            if (chunk_rc != 0) {
                if (read_err == (ssize_t)LIBP2P_ERR_EOF) {
                    read_err = 0;
                    break;
                }
                lantern_log_error(
                    "reqresp",
                    &meta,
                    "failed to read blocks_by_root chunk err=%zd",
                    read_err);
                free(chunk);
                schedule_legacy = !ctx->using_legacy;
                goto cleanup;
            }
            if (chunk_code != LANTERN_REQRESP_RESPONSE_SUCCESS) {
                lantern_log_error(
                    "reqresp",
                    &meta,
                    "blocks_by_root chunk returned code=%u payload_len=%zu",
                    (unsigned)chunk_code,
                    chunk_len);
                free(chunk);
                schedule_legacy = !ctx->using_legacy;
                goto cleanup;
            }
            if (chunk_len == 0 || !chunk) {
                free(chunk);
                break;
            }

            if (!lantern_client_process_stream_block_chunk(ctx, chunk, chunk_len, &meta, &saw_block)) {
                schedule_legacy = !ctx->using_legacy;
                goto cleanup;
            }
        }
        request_success = saw_block;
    }

cleanup:
    if (!request_success && schedule_legacy && ctx->client && !ctx->using_legacy && ctx->peer_text[0] && !attempt_legacy) {
        attempt_legacy = true;
        legacy_client = ctx->client;
        legacy_root = ctx->root;
        strncpy(legacy_peer, ctx->peer_text, sizeof(legacy_peer) - 1u);
        legacy_peer[sizeof(legacy_peer) - 1u] = '\0';
        char root_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
        format_root_hex(&legacy_root, root_hex, sizeof(root_hex));
        lantern_log_info(
            "reqresp",
            &meta,
            "retrying blocks_by_root with legacy protocol root=%s",
            root_hex[0] ? root_hex : "0x0");
    }
    lantern_blocks_by_root_response_reset(&response_msg);
    if (initial_chunk) {
        free(initial_chunk);
    }
    free(response);
    free(payload);
    lantern_blocks_by_root_request_reset(&request);
    libp2p_stream_free(stream);
    if (ctx->client) {
        lantern_client_on_blocks_request_complete(
            ctx->client,
            ctx->peer_text,
            &ctx->root,
            request_success ? LANTERN_BLOCKS_REQUEST_SUCCESS : LANTERN_BLOCKS_REQUEST_FAILED);
    }

    block_request_ctx_free(ctx);

    if (attempt_legacy && legacy_client && legacy_peer[0]) {
        if (lantern_client_schedule_blocks_request(legacy_client, legacy_peer, &legacy_root, true) != 0) {
            lantern_client_on_blocks_request_complete(
                legacy_client,
                legacy_peer,
                &legacy_root,
                LANTERN_BLOCKS_REQUEST_FAILED);
        }
    }
    return NULL;
}

static void block_request_on_open(libp2p_stream_t *stream, void *user_data, int err) {
    struct block_request_ctx *ctx = (struct block_request_ctx *)user_data;
    if (!ctx) {
        if (stream) {
            libp2p_stream_free(stream);
        }
        return;
    }
    struct lantern_log_metadata meta = {
        .validator = ctx->client ? ctx->client->node_id : NULL,
        .peer = ctx->peer_text[0] ? ctx->peer_text : NULL,
    };

    lantern_log_info(
        "reqresp",
        &meta,
        "block request stream opened protocol=%s err=%d",
        ctx->protocol_id ? ctx->protocol_id : "(unknown)",
        err);

    if (err != 0 || !stream) {
        lantern_log_warn(
            "reqresp",
            &meta,
            "failed to open %s stream err=%d",
            ctx->protocol_id,
            err);
        bool attempted = false;
        if (!ctx->using_legacy && ctx->client && ctx->peer_text[0]) {
            LanternRoot root = ctx->root;
            struct lantern_client *client = ctx->client;
            char peer_copy[sizeof(ctx->peer_text)];
            strncpy(peer_copy, ctx->peer_text, sizeof(peer_copy) - 1u);
            peer_copy[sizeof(peer_copy) - 1u] = '\0';
            lantern_log_info(
                "reqresp",
                &meta,
                "retrying blocks_by_root with legacy protocol after dial failure");
            if (stream) {
                libp2p_stream_free(stream);
            }
            block_request_ctx_free(ctx);
            attempted = true;
            if (lantern_client_schedule_blocks_request(client, peer_copy, &root, true) != 0) {
                lantern_client_on_blocks_request_complete(
                    client,
                    peer_copy,
                    &root,
                    LANTERN_BLOCKS_REQUEST_FAILED);
            }
        }
        if (!attempted) {
            if (ctx->client) {
                lantern_client_on_blocks_request_complete(
                    ctx->client,
                    ctx->peer_text,
                    &ctx->root,
                    LANTERN_BLOCKS_REQUEST_FAILED);
            }
            if (stream) {
                libp2p_stream_free(stream);
            }
            block_request_ctx_free(ctx);
        }
        return;
    }

    struct block_request_worker_args *worker = (struct block_request_worker_args *)malloc(sizeof(*worker));
    if (!worker) {
        lantern_log_error(
            "reqresp",
            &meta,
            "failed to allocate worker for %s stream",
            ctx->protocol_id);
        libp2p_stream_free(stream);
        if (ctx->client) {
            lantern_client_on_blocks_request_complete(
                ctx->client,
                ctx->peer_text,
                &ctx->root,
                LANTERN_BLOCKS_REQUEST_FAILED);
        }
        block_request_ctx_free(ctx);
        return;
    }
    worker->ctx = ctx;
    worker->stream = stream;

    pthread_t thread;
    if (pthread_create(&thread, NULL, block_request_worker, worker) != 0) {
        lantern_log_error(
            "reqresp",
            &meta,
            "failed to spawn blocks_by_root worker");
        free(worker);
        libp2p_stream_free(stream);
        if (ctx->client) {
            lantern_client_on_blocks_request_complete(
                ctx->client,
                ctx->peer_text,
                &ctx->root,
                LANTERN_BLOCKS_REQUEST_FAILED);
        }
        block_request_ctx_free(ctx);
        return;
    }
    lantern_log_info(
        "reqresp",
        &meta,
        "spawned blocks_by_root worker protocol=%s",
        ctx->protocol_id ? ctx->protocol_id : "(unknown)");
    pthread_detach(thread);
}

static int lantern_client_schedule_blocks_request(
    struct lantern_client *client,
    const char *peer_id_text,
    const LanternRoot *root,
    bool use_legacy) {
    if (!client || !peer_id_text || !root || !client->network.host) {
        return -1;
    }
    if (lantern_root_is_zero(root)) {
        return -1;
    }

    if (client->debug_disable_block_requests) {
        lantern_log_debug(
            "reqresp",
            &(const struct lantern_log_metadata){
                .validator = client->node_id,
                .peer = peer_id_text},
            "skipping blocks_by_root dial for test run");
        lantern_client_on_blocks_request_complete(
            client,
            peer_id_text,
            root,
            LANTERN_BLOCKS_REQUEST_ABORTED);
        return 0;
    }

    struct block_request_ctx *ctx = (struct block_request_ctx *)calloc(1, sizeof(*ctx));
    if (!ctx) {
        return -1;
    }
    ctx->client = client;
    ctx->root = *root;
    strncpy(ctx->peer_text, peer_id_text, sizeof(ctx->peer_text) - 1);
    ctx->peer_text[sizeof(ctx->peer_text) - 1] = '\0';
#if defined(LANTERN_BLOCKS_BY_ROOT_PROTOCOL_ID_LEGACY)
    bool prefer_legacy = false;
    if (!use_legacy && ctx->peer_text[0] != '\0') {
        prefer_legacy = lantern_reqresp_service_peer_prefers_legacy(&client->reqresp, ctx->peer_text) != 0;
    }
    bool effective_legacy = use_legacy || prefer_legacy;
    ctx->protocol_id =
        effective_legacy ? LANTERN_BLOCKS_BY_ROOT_PROTOCOL_ID_LEGACY : LANTERN_BLOCKS_BY_ROOT_PROTOCOL_ID;
    ctx->using_legacy = effective_legacy;
#else
    (void)use_legacy;
    ctx->protocol_id = LANTERN_BLOCKS_BY_ROOT_PROTOCOL_ID;
    ctx->using_legacy = false;
#endif

    if (peer_id_create_from_string(peer_id_text, &ctx->peer_id) != PEER_ID_SUCCESS) {
        lantern_log_warn(
            "reqresp",
            &(const struct lantern_log_metadata){
                .validator = client->node_id,
                .peer = peer_id_text},
            "failed to parse peer id for blocks_by_root request");
        block_request_ctx_free(ctx);
        return -1;
    }

    char root_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    format_root_hex(root, root_hex, sizeof(root_hex));
    lantern_log_info(
        "reqresp",
        &(const struct lantern_log_metadata){
            .validator = client->node_id,
            .peer = ctx->peer_text[0] ? ctx->peer_text : NULL},
        "dialing peer for %s root=%s",
        ctx->protocol_id,
        root_hex[0] ? root_hex : "0x0");

    int rc = libp2p_host_open_stream_async(
        client->network.host,
        &ctx->peer_id,
        ctx->protocol_id,
        block_request_on_open,
        ctx);
    if (rc != 0) {
        lantern_log_warn(
            "reqresp",
            &(const struct lantern_log_metadata){
                .validator = client->node_id,
                .peer = ctx->peer_text[0] ? ctx->peer_text : NULL},
            "libp2p open stream failed rc=%d",
            rc);
        block_request_ctx_free(ctx);
        return -1;
    }
    return 0;
}

static void lantern_client_record_block(
    struct lantern_client *client,
    const LanternSignedBlock *block,
    const LanternRoot *root,
    const char *peer_text,
    const char *context) {
    if (!client || !block) {
        return;
    }

    LanternRoot computed_root;
    const LanternRoot *selected_root = root;
    if (!selected_root) {
        if (lantern_hash_tree_root_block(&block->message.block, &computed_root) != 0) {
            return;
        }
        selected_root = &computed_root;
    }

    char root_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    format_root_hex(selected_root, root_hex, sizeof(root_hex));

    struct lantern_log_metadata meta = {
        .validator = client->node_id,
        .peer = peer_text && *peer_text ? peer_text : NULL,
    };
    const char *source = NULL;
    if (context && *context) {
        source = context;
    } else if (peer_text && *peer_text) {
        source = "peer";
    } else {
        source = "local";
    }

    lantern_log_info(
        "gossip",
        &meta,
        "processed block slot=%" PRIu64 " proposer=%" PRIu64 " root=%s attestations=%zu",
        block->message.block.slot,
        block->message.block.proposer_index,
        root_hex[0] ? root_hex : "0x0",
        block->message.block.body.attestations.length);

    if (client->data_dir) {
        if (lantern_storage_store_block(client->data_dir, block) != 0) {
            lantern_log_warn(
                "gossip",
                &meta,
                "failed to persist block root=%s",
                root_hex[0] ? root_hex : "0x0");
        }
    }

    bool imported = lantern_client_import_block(client, block, selected_root, &meta);
    lantern_log_info(
        "state",
        &meta,
        "block import outcome context=%s slot=%" PRIu64 " root=%s result=%s",
        source ? source : "unknown",
        block->message.block.slot,
        root_hex[0] ? root_hex : "0x0",
        imported ? "imported" : "not_imported");
}

static void lantern_client_record_vote(
    struct lantern_client *client,
    const LanternSignedVote *vote,
    const char *peer_text) {
    if (!client || !vote || !client->has_state) {
        return;
    }

    struct lantern_log_metadata meta = {
        .validator = client->node_id,
        .peer = (peer_text && *peer_text) ? peer_text : NULL,
    };

    bool state_locked = lantern_client_lock_state(client);
    if (!state_locked) {
        return;
    }

    struct lantern_vote_rejection_info rejection;
    memset(&rejection, 0, sizeof(rejection));
    bool vote_processed = false;

    char head_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    char target_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    char source_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    LanternSignedVote vote_copy = *vote;
    format_root_hex(&vote_copy.data.head.root, head_hex, sizeof(head_hex));
    format_root_hex(&vote_copy.data.target.root, target_hex, sizeof(target_hex));
    format_root_hex(&vote_copy.data.source.root, source_hex, sizeof(source_hex));
    lantern_log_debug(
        "gossip",
        &meta,
        "received vote validator=%" PRIu64 " slot=%" PRIu64 " head=%s target=%s@%" PRIu64,
        vote_copy.data.validator_id,
        vote_copy.data.slot,
        head_hex[0] ? head_hex : "0x0",
        target_hex[0] ? target_hex : "0x0",
        vote_copy.data.target.slot);

    if (!client->has_fork_choice) {
        lantern_log_debug(
            "gossip",
            &meta,
            "deferring vote validator=%" PRIu64 " slot=%" PRIu64 " (fork choice unavailable)",
            vote_copy.data.validator_id,
            vote_copy.data.slot);
        lantern_vote_rejection_set(&rejection, "fork choice unavailable");
        goto cleanup;
    }

    if (!lantern_client_validate_vote_constraints(
            client,
            &vote_copy.data,
            "gossip",
            &meta,
            "gossip",
            &rejection)) {
        goto cleanup;
    }

    if (!lantern_client_verify_vote_signature(
            client,
            &vote_copy,
            &vote_copy.signature,
            &meta,
            "gossip")) {
        lantern_log_debug(
            "gossip",
            &meta,
            "rejected vote validator=%" PRIu64 " slot=%" PRIu64 " (invalid XMSS signature)",
            vote_copy.data.validator_id,
            vote_copy.data.slot);
        lantern_vote_rejection_set(&rejection, "invalid XMSS signature");
        goto cleanup;
    }

    const LanternVote *vote_data = &vote_copy.data;
    uint64_t validator_count = client->state.config.num_validators;
    if (validator_count == 0 || !client->state.validator_votes || client->state.validator_votes_len == 0) {
        lantern_log_debug(
            "gossip",
            &meta,
            "dropping vote validator=%" PRIu64 " slot=%" PRIu64 " (state vote cache unavailable)",
            vote_data->validator_id,
            vote_data->slot);
        lantern_vote_rejection_set(&rejection, "state vote cache unavailable");
        goto cleanup;
    }
    if ((vote_data->validator_id >= validator_count)
        || (vote_data->validator_id >= (uint64_t)client->state.validator_votes_len)) {
        lantern_log_debug(
            "gossip",
            &meta,
            "dropping vote validator=%" PRIu64 " slot=%" PRIu64 " (validator out of range)",
            vote_data->validator_id,
            vote_data->slot);
        lantern_vote_rejection_set(&rejection, "validator out of range id=%" PRIu64, vote_data->validator_id);
        goto cleanup;
    }
    if (vote_data->target.slot < vote_data->source.slot) {
        lantern_log_debug(
            "gossip",
            &meta,
            "dropping vote validator=%" PRIu64 " slot=%" PRIu64 " (target slot < source)",
            vote_data->validator_id,
            vote_data->slot);
        lantern_vote_rejection_set(
            &rejection,
            "target slot %" PRIu64 " < source slot %" PRIu64,
            vote_data->target.slot,
            vote_data->source.slot);
        goto cleanup;
    }

    /*
     * Per leanSpec, attestation validation only requires that the referenced
     * blocks (source, target, head) exist in the store. We check fork choice
     * first, then fall back to state's justified window for backwards compat.
     * This allows attestations from competing forks to be processed correctly.
     */
    bool source_block_known = false;
    bool target_block_known = false;
    bool head_block_known = false;
    uint64_t source_block_slot = 0;
    uint64_t target_block_slot = 0;

    if (client->has_fork_choice) {
        source_block_known = (lantern_fork_choice_block_info(
            &client->fork_choice, &vote_data->source.root, &source_block_slot, NULL, NULL) == 0);
        target_block_known = (lantern_fork_choice_block_info(
            &client->fork_choice, &vote_data->target.root, &target_block_slot, NULL, NULL) == 0);
        head_block_known = (lantern_fork_choice_block_info(
            &client->fork_choice, &vote_data->head.root, NULL, NULL, NULL) == 0);
    }

    if (!source_block_known) {
        /* Source block not in fork choice - check state's justified window as fallback */
        if (!lantern_state_slot_in_justified_window(&client->state, vote_data->source.slot)) {
            lantern_log_debug(
                "gossip",
                &meta,
                "dropping vote validator=%" PRIu64 " slot=%" PRIu64 " (source block unknown and outside justified window)",
                vote_data->validator_id,
                vote_data->slot);
            lantern_vote_rejection_set(
                &rejection,
                "source slot=%" PRIu64 " block unknown and outside justified window",
                vote_data->source.slot);
            goto cleanup;
        }
        bool source_is_justified = false;
        if (lantern_state_get_justified_slot_bit(&client->state, vote_data->source.slot, &source_is_justified) != 0
            || !source_is_justified) {
            lantern_log_debug(
                "gossip",
                &meta,
                "dropping vote validator=%" PRIu64 " slot=%" PRIu64 " (source not justified in state)",
                vote_data->validator_id,
                vote_data->slot);
            lantern_vote_rejection_set(&rejection, "source slot=%" PRIu64 " not justified", vote_data->source.slot);
            goto cleanup;
        }
    } else {
        /* Source block is in fork choice - verify checkpoint slot matches block slot */
        if (source_block_slot != vote_data->source.slot) {
            lantern_log_debug(
                "gossip",
                &meta,
                "dropping vote validator=%" PRIu64 " slot=%" PRIu64 " (source checkpoint slot mismatch)",
                vote_data->validator_id,
                vote_data->slot);
            lantern_vote_rejection_set(
                &rejection,
                "source checkpoint slot=%" PRIu64 " != block slot=%" PRIu64,
                vote_data->source.slot,
                source_block_slot);
            goto cleanup;
        }
    }

    if (!target_block_known && !head_block_known) {
        lantern_log_debug(
            "gossip",
            &meta,
            "dropping vote validator=%" PRIu64 " slot=%" PRIu64 " (target and head blocks unknown)",
            vote_data->validator_id,
            vote_data->slot);
        lantern_vote_rejection_set(&rejection, "target and head blocks unknown");
        goto cleanup;
    }

    if (target_block_known && target_block_slot != vote_data->target.slot) {
        lantern_log_debug(
            "gossip",
            &meta,
            "dropping vote validator=%" PRIu64 " slot=%" PRIu64 " (target checkpoint slot mismatch)",
            vote_data->validator_id,
            vote_data->slot);
        lantern_vote_rejection_set(
            &rejection,
            "target checkpoint slot=%" PRIu64 " != block slot=%" PRIu64,
            vote_data->target.slot,
            target_block_slot);
        goto cleanup;
    }

    if (lantern_state_set_signed_validator_vote(&client->state, (size_t)vote_data->validator_id, &vote_copy) != 0) {
        lantern_log_debug(
            "state",
            &meta,
            "failed to cache gossip vote validator=%" PRIu64 " slot=%" PRIu64,
            vote_data->validator_id,
            vote_data->slot);
        lantern_vote_rejection_set(
            &rejection,
            "failed to cache vote validator=%" PRIu64 " slot=%" PRIu64,
            vote_data->validator_id,
            vote_data->slot);
        goto cleanup;
    }

    if (client->has_fork_choice) {
        if (lantern_fork_choice_add_vote(&client->fork_choice, &vote_copy, false) != 0) {
            lantern_log_debug(
                "forkchoice",
                &meta,
                "failed to track gossip vote validator=%" PRIu64 " slot=%" PRIu64,
                vote_copy.data.validator_id,
                vote_copy.data.slot);
        } else {
            if (!client->debug_disable_fork_choice_time) {
                uint64_t now_seconds = 0;
                if (!lantern_client_vote_time_seconds(client, vote_copy.data.slot, &now_seconds)) {
                    now_seconds = validator_wall_time_now_seconds();
                }
                if (lantern_fork_choice_advance_time(&client->fork_choice, now_seconds, false) != 0) {
                    lantern_log_debug(
                        "forkchoice",
                        &meta,
                        "advancing fork choice time failed after validator=%" PRIu64 " slot=%" PRIu64,
                        vote_copy.data.validator_id,
                        vote_copy.data.slot);
                }
            }
        }
    }

    if (client->data_dir) {
        if (lantern_storage_save_votes(client->data_dir, &client->state) != 0) {
            lantern_log_warn(
                "storage",
                &meta,
                "failed to persist votes after validator=%" PRIu64 " slot=%" PRIu64,
                vote_copy.data.validator_id,
                vote_copy.data.slot);
        }
    }

    vote_processed = true;
    lantern_log_info(
        "gossip",
        &meta,
        "processed vote validator=%" PRIu64
        " slot=%" PRIu64 " head=%s target=%s@%" PRIu64 " source=%s@%" PRIu64,
        vote_copy.data.validator_id,
        vote_copy.data.slot,
        head_hex[0] ? head_hex : "0x0",
        target_hex[0] ? target_hex : "0x0",
        vote_copy.data.target.slot,
        source_hex[0] ? source_hex : "0x0",
        vote_copy.data.source.slot);
cleanup:
    lantern_client_unlock_state(client, state_locked);
    lantern_client_note_vote_outcome(client, peer_text, &vote_copy, vote_processed);
    if (!vote_processed) {
        const char *reason_text = rejection.has_reason ? rejection.message : "unknown";
        lantern_log_info(
            "gossip",
            &meta,
            "rejected vote validator=%" PRIu64 " slot=%" PRIu64 " head=%s target=%s@%" PRIu64
            " source=%s@%" PRIu64 " reason=%s",
            vote_copy.data.validator_id,
            vote_copy.data.slot,
            head_hex[0] ? head_hex : "0x0",
            target_hex[0] ? target_hex : "0x0",
            vote_copy.data.target.slot,
            source_hex[0] ? source_hex : "0x0",
            vote_copy.data.source.slot,
            reason_text);
    }
}

static int gossip_block_handler(
    const LanternSignedBlock *block,
    const peer_id_t *from,
    void *context) {
    if (!block || !context) {
        return -1;
    }
    struct lantern_client *client = context;

    char peer_text[128];
    peer_text[0] = '\0';
    if (from && peer_id_to_string(from, PEER_ID_FMT_BASE58_LEGACY, peer_text, sizeof(peer_text)) < 0) {
        peer_text[0] = '\0';
    }

    lantern_client_record_block(client, block, NULL, peer_text[0] ? peer_text : NULL, "gossip");
    return 0;
}

static int gossip_vote_handler(
    const LanternSignedVote *vote,
    const peer_id_t *from,
    void *context) {
    if (!vote || !context) {
        return -1;
    }
    struct lantern_client *client = context;
    char peer_text[128];
    peer_text[0] = '\0';
    if (from) {
        if (peer_id_to_string(from, PEER_ID_FMT_BASE58_LEGACY, peer_text, sizeof(peer_text)) < 0) {
            peer_text[0] = '\0';
        }
    }
    const char *peer_id_text = peer_text[0] ? peer_text : NULL;
    lantern_client_note_vote_delivery(client, peer_id_text, vote);
    lantern_client_record_vote(client, vote, peer_id_text);
    return 0;
}

static int reqresp_collect_blocks(
    void *context,
    const LanternRoot *roots,
    size_t root_count,
    LanternBlocksByRootResponse *out_blocks) {
    if (!context || !out_blocks) {
        return -1;
    }
    struct lantern_client *client = context;
    if (!client->data_dir) {
        return lantern_blocks_by_root_response_resize(out_blocks, 0);
    }
    int rc = lantern_storage_collect_blocks(client->data_dir, roots, root_count, out_blocks);
    if (rc != 0) {
        lantern_log_error(
            "reqresp",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to collect blocks from storage");
        return -1;
    }
    return 0;
}

static int initialize_fork_choice(struct lantern_client *client) {
    if (!client || !client->has_state) {
        return -1;
    }
    lantern_fork_choice_reset(&client->fork_choice);
    if (lantern_fork_choice_configure(&client->fork_choice, &client->state.config) != 0) {
        lantern_log_error(
            "forkchoice",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to configure fork choice");
        return -1;
    }

    LanternRoot anchor_state_root;
    if (lantern_hash_tree_root_state(&client->state, &anchor_state_root) != 0) {
        lantern_log_error(
            "forkchoice",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to hash anchor state");
        return -1;
    }

    /* Create a copy of the header for computing anchor_root.
     *
     * According to leanSpec's Store.get_forkchoice_store, the anchor block
     * used for fork choice MUST have state_root = hash_tree_root(state).
     * This is different from the state's latest_block_header which starts
     * with state_root = ZERO.
     *
     * We compute anchor_root from a header with the ACTUAL state_root,
     * matching Zeam's genStateBlockHeader() behavior.
     */
    LanternBlockHeader anchor_header = client->state.latest_block_header;
    anchor_header.state_root = anchor_state_root;

    LanternRoot anchor_root;
    if (lantern_hash_tree_root_block_header(&anchor_header, &anchor_root) != 0) {
        lantern_log_error(
            "forkchoice",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to hash anchor block header");
        return -1;
    }

    /* Log the anchor root for debugging genesis mismatch issues */
    {
        char anchor_root_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
        char state_root_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
        char body_root_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
        format_root_hex(&anchor_root, anchor_root_hex, sizeof(anchor_root_hex));
        format_root_hex(&anchor_state_root, state_root_hex, sizeof(state_root_hex));
        format_root_hex(&anchor_header.body_root, body_root_hex, sizeof(body_root_hex));
        lantern_log_info(
            "forkchoice",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "genesis anchor_root=%s state_root=%s body_root=%s slot=%lu",
            anchor_root_hex,
            state_root_hex,
            body_root_hex,
            (unsigned long)anchor_header.slot);
    }

    /* Also update the state's header state_root for subsequent state transitions */
    if (memcmp(
            client->state.latest_block_header.state_root.bytes,
            anchor_state_root.bytes,
            LANTERN_ROOT_SIZE)
        != 0) {
        client->state.latest_block_header.state_root = anchor_state_root;
        lantern_log_debug(
            "forkchoice",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "updated genesis header state_root");
    }

    LanternBlock anchor;
    memset(&anchor, 0, sizeof(anchor));
    anchor.slot = client->state.latest_block_header.slot;
    anchor.proposer_index = client->state.latest_block_header.proposer_index;
    anchor.parent_root = client->state.latest_block_header.parent_root;
    anchor.state_root = anchor_state_root;
    lantern_block_body_init(&anchor.body);

    if (lantern_fork_choice_set_anchor(
            &client->fork_choice,
            &anchor,
            &client->state.latest_justified,
            &client->state.latest_finalized,
            &anchor_root)
        != 0) {
        lantern_block_body_reset(&anchor.body);
        lantern_log_error(
            "forkchoice",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to set fork choice anchor");
        return -1;
    }
    if (memcmp(client->state.latest_justified.root.bytes, anchor_root.bytes, LANTERN_ROOT_SIZE) != 0) {
        client->state.latest_justified.root = anchor_root;
        lantern_log_debug(
            "forkchoice",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "updated justified checkpoint root to anchor");
    }
    if (memcmp(client->state.latest_finalized.root.bytes, anchor_root.bytes, LANTERN_ROOT_SIZE) != 0) {
        client->state.latest_finalized.root = anchor_root;
        lantern_log_debug(
            "forkchoice",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "updated finalized checkpoint root to anchor");
    }
    persist_anchor_block(client, &anchor, &anchor_root);
    lantern_block_body_reset(&anchor.body);
    lantern_state_attach_fork_choice(&client->state, &client->fork_choice);
    client->has_fork_choice = true;
    return 0;
}

static int restore_persisted_blocks(struct lantern_client *client) {
    if (!client || !client->has_state || !client->data_dir || !client->has_fork_choice) {
        return 0;
    }
    struct lantern_persisted_block_list list;
    persisted_block_list_init(&list);
    int iterate_rc = lantern_storage_iterate_blocks(client->data_dir, collect_block_visitor, &list);
    if (iterate_rc < 0) {
        lantern_log_error(
            "storage",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to enumerate persisted blocks");
        persisted_block_list_reset(&list);
        return -1;
    }
    if (list.length == 0) {
        persisted_block_list_reset(&list);
        return 0;
    }
    qsort(list.items, list.length, sizeof(list.items[0]), compare_blocks_by_slot);

    for (size_t i = 0; i < list.length; ++i) {
        const struct lantern_persisted_block *entry = &list.items[i];
        LanternSignedVote persisted_proposer;
        memset(&persisted_proposer, 0, sizeof(persisted_proposer));
        persisted_proposer.data = entry->block.message.proposer_attestation;
        size_t proposer_index = entry->block.message.block.body.attestations.length;
        if (entry->block.signatures.length > proposer_index && entry->block.signatures.data) {
            persisted_proposer.signature = entry->block.signatures.data[proposer_index];
        }
        if (lantern_fork_choice_add_block(
                &client->fork_choice,
                &entry->block.message.block,
                &persisted_proposer,
                &client->state.latest_justified,
                &client->state.latest_finalized,
                &entry->root)
            != 0) {
            lantern_log_warn(
                "forkchoice",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "failed to restore block at slot %" PRIu64,
                entry->block.message.block.slot);
        }
    }

    uint64_t now_seconds = validator_wall_time_now_seconds();
    if (lantern_fork_choice_advance_time(&client->fork_choice, now_seconds, false) != 0) {
        lantern_log_warn(
            "forkchoice",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "advancing fork choice time after restore failed");
    }

    persisted_block_list_reset(&list);
    return 0;
}

static int init_consensus_runtime(struct lantern_client *client) {
    if (!client || !client->has_validator_assignment) {
        return -1;
    }
    struct lantern_consensus_runtime_config runtime_config;
    lantern_consensus_runtime_config_init(&runtime_config);
    runtime_config.genesis_time = client->genesis.chain_config.genesis_time;
    runtime_config.validator_count = client->genesis.chain_config.validator_count;
    if (runtime_config.validator_count == 0) {
        return -1;
    }
    if (lantern_consensus_runtime_init(
            &client->runtime,
            &runtime_config,
            &client->validator_assignment)
        != 0) {
        return -1;
    }
    client->has_runtime = true;
    return 0;
}

static int set_owned_string(char **dest, const char *value) {
    if (!dest || !value) {
        return -1;
    }
    char *copy = lantern_string_duplicate(value);
    if (!copy) {
        return -1;
    }
    free(*dest);
    *dest = copy;
    return 0;
}

static int copy_genesis_paths(struct lantern_genesis_paths *paths, const struct lantern_client_options *options) {
    if (!paths || !options) {
        return -1;
    }

    reset_genesis_paths(paths);

    if (set_owned_string(&paths->config_path, options->genesis_config_path) != 0) {
        return -1;
    }
    if (set_owned_string(&paths->validator_registry_path, options->validator_registry_path) != 0) {
        return -1;
    }
    if (set_owned_string(&paths->nodes_path, options->nodes_path) != 0) {
        return -1;
    }
    if (set_owned_string(&paths->state_path, options->genesis_state_path) != 0) {
        return -1;
    }
    if (set_owned_string(&paths->validator_config_path, options->validator_config_path) != 0) {
        return -1;
    }

    return 0;
}

static void reset_genesis_paths(struct lantern_genesis_paths *paths) {
    if (!paths) {
        return;
    }
    free(paths->config_path);
    free(paths->validator_registry_path);
    free(paths->nodes_path);
    free(paths->state_path);
    free(paths->validator_config_path);
    memset(paths, 0, sizeof(*paths));
}

static int read_trimmed_file(const char *path, char **out_text) {
    if (!path || !out_text) {
        return -1;
    }

    FILE *fp = fopen(path, "rb");
    if (!fp) {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){0},
            "unable to open %s for reading",
            path);
        return -1;
    }

    if (fseek(fp, 0, SEEK_END) != 0) {
        fclose(fp);
        return -1;
    }
    long file_size = ftell(fp);
    if (file_size < 0) {
        fclose(fp);
        return -1;
    }
    if (fseek(fp, 0, SEEK_SET) != 0) {
        fclose(fp);
        return -1;
    }

    char *buffer = malloc((size_t)file_size + 1);
    if (!buffer) {
        fclose(fp);
        return -1;
    }

    size_t read_len = fread(buffer, 1, (size_t)file_size, fp);
    fclose(fp);
    buffer[read_len] = '\0';

    char *trimmed = lantern_trim_whitespace(buffer);
    size_t trimmed_len = strlen(trimmed);
    memmove(buffer, trimmed, trimmed_len + 1);
    *out_text = buffer;
    return 0;
}

size_t lantern_client_local_validator_count(const struct lantern_client *client) {
    if (!client) {
        return 0;
    }
    return client->local_validator_count;
}

const struct lantern_local_validator *lantern_client_local_validator(
    const struct lantern_client *client,
    size_t index) {
    if (!client || index >= client->local_validator_count) {
        return NULL;
    }
    return &client->local_validators[index];
}

int lantern_validator_refresh_cached_vote(
    struct lantern_local_validator *validator,
    uint64_t slot,
    const LanternCheckpoint *head,
    const LanternCheckpoint *target,
    const LanternCheckpoint *source,
    LanternSignedVote *vote) {
    if (!validator || !head || !target || !source || !vote) {
        return -1;
    }
    if (!validator->secret_key) {
        return -1;
    }
    /* Check if a refresh is needed: source checkpoint changed */
    if (vote->data.source.slot == source->slot
        && memcmp(vote->data.source.root.bytes, source->root.bytes, LANTERN_ROOT_SIZE) == 0) {
        /* No change needed */
        return 0;
    }
    /* Update the vote data */
    vote->data.head = *head;
    vote->data.target = *target;
    vote->data.source = *source;
    /* Re-sign the vote */
    if (validator_sign_vote(validator, slot, vote) != 0) {
        return -1;
    }
    return 1;
}

int lantern_client_publish_block(struct lantern_client *client, const LanternSignedBlock *block) {
    if (!client || !block) {
        return -1;
    }
    if (!client->gossip_running) {
        lantern_log_error(
            "gossip",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "cannot publish block at slot %" PRIu64 ": gossip service inactive",
            block->message.block.slot);
        return -1;
    }
    if (lantern_gossipsub_service_publish_block(&client->gossip, block) != 0) {
        lantern_log_error(
            "gossip",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to publish block at slot %" PRIu64,
            block->message.block.slot);
        return -1;
    }

    /* Use lantern_hash_tree_root_block for the block root (not signed_block).
       The block root should be the hash of the unsigned block content, consistent
       with how other clients (Zeam) and the processing path compute it. */
    LanternRoot block_root;
    char root_hex[2 * LANTERN_ROOT_SIZE + 3];
    if (lantern_hash_tree_root_block(&block->message.block, &block_root) == 0) {
        format_root_hex(&block_root, root_hex, sizeof(root_hex));
    } else {
        root_hex[0] = '\0';
    }

    lantern_log_info(
        "gossip",
        &(const struct lantern_log_metadata){.validator = client->node_id},
        "published block slot=%" PRIu64 " root=%s attestations=%zu",
        block->message.block.slot,
        root_hex[0] ? root_hex : "0x0",
        block->message.block.body.attestations.length);
    return 0;
}

int lantern_client_debug_record_vote(
    struct lantern_client *client,
    const LanternSignedVote *vote,
    const char *peer_id_text) {
    if (!client || !vote) {
        return -1;
    }
    lantern_client_record_vote(client, vote, peer_id_text);
    return 0;
}

int lantern_client_debug_import_block(
    struct lantern_client *client,
    const LanternSignedBlock *block,
    const LanternRoot *block_root,
    const char *peer_id_text) {
    struct lantern_log_metadata meta = {
        .validator = client ? client->node_id : NULL,
        .peer = peer_id_text,
    };
    return lantern_client_import_block(client, block, block_root, &meta) ? 1 : 0;
}

size_t lantern_client_pending_block_count(const struct lantern_client *client) {
    if (!client) {
        return 0;
    }
    struct lantern_client *mutable_client = (struct lantern_client *)client;
    bool locked = lantern_client_lock_pending(mutable_client);
    size_t count = client->pending_blocks.length;
    if (locked) {
        lantern_client_unlock_pending(mutable_client, locked);
    }
    return count;
}

int lantern_client_debug_enqueue_pending_block(
    struct lantern_client *client,
    const LanternSignedBlock *block,
    const LanternRoot *block_root,
    const LanternRoot *parent_root,
    const char *peer_id_text) {
    if (!client || !block || !block_root || !parent_root) {
        return -1;
    }
    lantern_client_enqueue_pending_block(client, block, block_root, parent_root, peer_id_text);
    return 0;
}

int lantern_client_debug_pending_entry(
    const struct lantern_client *client,
    size_t index,
    LanternRoot *out_root,
    LanternRoot *out_parent_root,
    bool *out_parent_requested,
    char *out_peer_text,
    size_t peer_text_len) {
    if (!client) {
        return -1;
    }
    struct lantern_client *mutable_client = (struct lantern_client *)client;
    bool locked = lantern_client_lock_pending(mutable_client);
    if (locked && index >= client->pending_blocks.length) {
        lantern_client_unlock_pending(mutable_client, locked);
        return -1;
    }
    if (!locked && index >= client->pending_blocks.length) {
        return -1;
    }

    LanternRoot root_copy;
    LanternRoot parent_copy;
    bool requested = false;
    char peer_copy[128];
    peer_copy[0] = '\0';

    if (locked) {
        const struct lantern_pending_block *entry = &client->pending_blocks.items[index];
        root_copy = entry->root;
        parent_copy = entry->parent_root;
        requested = entry->parent_requested;
        if (entry->peer_text[0]) {
            strncpy(peer_copy, entry->peer_text, sizeof(peer_copy) - 1u);
            peer_copy[sizeof(peer_copy) - 1u] = '\0';
        }
        lantern_client_unlock_pending(mutable_client, locked);
    } else {
        const struct lantern_pending_block *entry = &client->pending_blocks.items[index];
        if (!entry) {
            return -1;
        }
        root_copy = entry->root;
        parent_copy = entry->parent_root;
        requested = entry->parent_requested;
        if (entry->peer_text[0]) {
            strncpy(peer_copy, entry->peer_text, sizeof(peer_copy) - 1u);
            peer_copy[sizeof(peer_copy) - 1u] = '\0';
        }
    }

    if (out_root) {
        *out_root = root_copy;
    }
    if (out_parent_root) {
        *out_parent_root = parent_copy;
    }
    if (out_parent_requested) {
        *out_parent_requested = requested;
    }
    if (out_peer_text && peer_text_len > 0) {
        if (peer_text_len == 1) {
            out_peer_text[0] = '\0';
        } else {
            if (peer_copy[0]) {
                strncpy(out_peer_text, peer_copy, peer_text_len - 1u);
                out_peer_text[peer_text_len - 1u] = '\0';
            } else {
                out_peer_text[0] = '\0';
            }
        }
    }
    return 0;
}

void lantern_client_debug_pending_reset(struct lantern_client *client) {
    if (!client) {
        return;
    }
    bool locked = lantern_client_lock_pending(client);
    if (locked) {
        pending_block_list_reset(&client->pending_blocks);
        lantern_client_unlock_pending(client, locked);
    } else {
        pending_block_list_reset(&client->pending_blocks);
    }
}

int lantern_client_debug_set_parent_requested(
    struct lantern_client *client,
    const LanternRoot *root,
    bool requested) {
    if (!client || !root) {
        return -1;
    }
    bool locked = lantern_client_lock_pending(client);
    struct lantern_pending_block *entry = NULL;
    if (locked) {
        entry = pending_block_list_find(&client->pending_blocks, root);
        if (entry) {
            entry->parent_requested = requested;
        }
        lantern_client_unlock_pending(client, locked);
    } else {
        entry = pending_block_list_find(&client->pending_blocks, root);
        if (entry) {
            entry->parent_requested = requested;
        }
    }
    return entry ? 0 : -1;
}

void lantern_client_debug_disable_block_requests(struct lantern_client *client, bool disable) {
    if (!client) {
        return;
    }
    client->debug_disable_block_requests = disable ? true : false;
}

int lantern_client_debug_on_blocks_request_complete(
    struct lantern_client *client,
    const char *peer_id,
    const LanternRoot *request_root,
    int outcome_code) {
    if (!client) {
        return -1;
    }
    enum lantern_blocks_request_outcome outcome;
    switch (outcome_code) {
    case LANTERN_DEBUG_BLOCKS_REQUEST_SUCCESS:
        outcome = LANTERN_BLOCKS_REQUEST_SUCCESS;
        break;
    case LANTERN_DEBUG_BLOCKS_REQUEST_FAILED:
        outcome = LANTERN_BLOCKS_REQUEST_FAILED;
        break;
    case LANTERN_DEBUG_BLOCKS_REQUEST_ABORTED:
        outcome = LANTERN_BLOCKS_REQUEST_ABORTED;
        break;
    default:
        return -1;
    }
    lantern_client_on_blocks_request_complete(client, peer_id, request_root, outcome);
    return 0;
}

static int load_node_key_bytes(const struct lantern_client_options *options, uint8_t out_key[32]) {
    if (!options || !out_key) {
        return -1;
    }

    char *owned = NULL;
    int rc = -1;

    if (options->node_key_hex) {
        owned = lantern_string_duplicate(options->node_key_hex);
        if (!owned) {
            return -1;
        }
    } else if (options->node_key_path) {
        if (read_trimmed_file(options->node_key_path, &owned) != 0) {
            return -1;
        }
    } else {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = options->node_id},
            "--node-key or --node-key-path is required");
        return -1;
    }

    char *trimmed = lantern_trim_whitespace(owned);
    if (!trimmed) {
        free(owned);
        return -1;
    }

    rc = lantern_hex_decode(trimmed, out_key, 32);
    if (rc != 0) {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = options->node_id},
            "invalid node key (expected 32-byte hex string)");
    }

    if (owned) {
        memset(owned, 0, strlen(owned));
        free(owned);
    }

    return rc;
}
