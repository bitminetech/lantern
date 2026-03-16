/**
 * @file client.c
 * @brief Lantern client core initialization and lifecycle management
 *
 * Implements the main client structure initialization, startup sequence,
 * and graceful shutdown. This is the central coordinator that brings together:
 * - Genesis configuration loading
 * - Consensus state management
 * - Networking (libp2p, gossipsub, request/response)
 * - Validator services
 * - HTTP and metrics servers
 *
 * @see client_internal.h for shared internal declarations
 */

#include "lantern/core/client.h"

#include <ctype.h>
#include <errno.h>
#include <inttypes.h>
#include <limits.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <time.h>

#if defined(_WIN32)
#include <windows.h>
#else
#include <netdb.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>
#endif

#include "internal/yaml_parser.h"
#include "libp2p/errors.h"
#include "libp2p/events.h"
#include "libp2p/host.h"
#include "libp2p/protocol_dial.h"
#include "libp2p/stream.h"
#include "multiformats/unsigned_varint/unsigned_varint.h"
#include "peer_id/peer_id.h"
#include "protocol/gossipsub/gossipsub.h"
#include "protocol/identify/protocol_identify.h"
#include "protocol/ping/protocol_ping.h"

#include "client_internal.h"
#include "lantern/consensus/containers.h"
#include "lantern/consensus/duties.h"
#include "lantern/consensus/fork_choice.h"
#include "lantern/consensus/hash.h"
#include "lantern/consensus/runtime.h"
#include "lantern/consensus/signature.h"
#include "lantern/consensus/ssz.h"
#include "lantern/consensus/state.h"
#include "lantern/crypto/xmss.h"
#include "lantern/encoding/snappy.h"
#include "lantern/http/server.h"
#include "lantern/metrics/lean_metrics.h"
#include "lantern/networking/messages.h"
#include "lantern/networking/reqresp_service.h"
#include "lantern/storage/storage.h"
#include "lantern/support/log.h"
#include "lantern/support/secure_mem.h"
#include "lantern/support/strings.h"
#include "lantern/support/time.h"

static const size_t NODE_PRIVATE_KEY_SIZE = 32u;
static const size_t BOOTNODE_LINE_MAX_LEN = 2048u;
static const size_t CHECKPOINT_SYNC_MAX_RESPONSE_BYTES =
    512u
    + (LANTERN_HISTORICAL_ROOTS_LIMIT * 32u)
    + (LANTERN_HISTORICAL_ROOTS_LIMIT / 8u)
    + (LANTERN_VALIDATOR_REGISTRY_LIMIT * 52u)
    + (LANTERN_HISTORICAL_ROOTS_LIMIT * 32u)
    + (LANTERN_JUSTIFICATION_VALIDATORS_LIMIT / 8u);
static const size_t LANTERN_ATTESTATION_COMMITTEE_COUNT = 1u;

static void sync_aggregated_payload_pools_after_time_advance(
    struct lantern_client *client,
    uint64_t previous_intervals,
    bool has_proposal) {
    if (!client || !client->has_fork_choice) {
        return;
    }
    if (client->fork_choice.intervals_per_slot == 0
        || client->fork_choice.time_intervals <= previous_intervals) {
        return;
    }
    for (uint64_t step = previous_intervals + 1u;
         step <= client->fork_choice.time_intervals;
         ++step) {
        uint64_t interval_index = step % client->fork_choice.intervals_per_slot;
        bool step_has_proposal = has_proposal && (step == client->fork_choice.time_intervals);
        if (interval_index == 4u || (interval_index == 0u && step_has_proposal)) {
            (void)lantern_store_promote_new_aggregated_payloads(&client->store);
        }
    }
}

static int fork_choice_interval_boundary_milliseconds(
    const LanternForkChoice *store,
    uint64_t target_interval,
    uint64_t *out_now_milliseconds) {
    if (!store || !out_now_milliseconds || store->milliseconds_per_interval == 0) {
        return -1;
    }
    if (store->config.genesis_time > UINT64_MAX / 1000u) {
        return -1;
    }
    uint64_t genesis_milliseconds = store->config.genesis_time * 1000u;
    if (target_interval > (UINT64_MAX - genesis_milliseconds) / store->milliseconds_per_interval) {
        return -1;
    }
    *out_now_milliseconds =
        genesis_milliseconds + (target_interval * store->milliseconds_per_interval);
    return 0;
}

static int fork_choice_target_interval(
    const LanternForkChoice *store,
    uint64_t now_milliseconds,
    uint64_t *out_target_interval) {
    if (!store || !out_target_interval || store->milliseconds_per_interval == 0) {
        return -1;
    }
    if (store->config.genesis_time > UINT64_MAX / 1000u) {
        return -1;
    }
    uint64_t genesis_milliseconds = store->config.genesis_time * 1000u;
    if (now_milliseconds < genesis_milliseconds) {
        return 1;
    }
    *out_target_interval = (now_milliseconds - genesis_milliseconds) / store->milliseconds_per_interval;
    return 0;
}

int lantern_client_set_gossip_signature(
    struct lantern_client *client,
    const LanternSignatureKey *key,
    const LanternAttestationData *data,
    const LanternSignature *signature,
    uint64_t target_slot) {
    if (!client) {
        return -1;
    }
    return lantern_store_set_gossip_signature(&client->store, key, data, signature, target_slot);
}

int lantern_client_add_new_aggregated_payload(
    struct lantern_client *client,
    const LanternRoot *data_root,
    const LanternAttestationData *data,
    const LanternAggregatedSignatureProof *proof,
    uint64_t target_slot) {
    if (!client) {
        return -1;
    }
    return lantern_store_add_new_aggregated_payload(&client->store, data_root, data, proof, target_slot);
}

int lantern_client_add_known_aggregated_payload(
    struct lantern_client *client,
    const LanternRoot *data_root,
    const LanternAttestationData *data,
    const LanternAggregatedSignatureProof *proof,
    uint64_t target_slot) {
    if (!client) {
        return -1;
    }
    return lantern_store_add_known_aggregated_payload(&client->store, data_root, data, proof, target_slot);
}

size_t lantern_client_promote_new_aggregated_payloads(
    struct lantern_client *client) {
    if (!client) {
        return 0u;
    }
    return lantern_store_promote_new_aggregated_payloads(&client->store);
}

size_t lantern_client_prune_finalized_attestation_material(
    struct lantern_client *client,
    uint64_t finalized_slot) {
    if (!client) {
        return 0u;
    }
    return lantern_store_prune_finalized_attestation_material(&client->store, finalized_slot);
}

int lantern_client_tick_fork_choice_interval_locked(
    struct lantern_client *client,
    bool has_proposal) {
    if (!client || !client->has_fork_choice) {
        return -1;
    }

    uint64_t previous_intervals = client->fork_choice.time_intervals;
    uint64_t next_interval = previous_intervals + 1u;
    if (next_interval < previous_intervals) {
        return -1;
    }

    uint64_t now_milliseconds = 0;
    if (fork_choice_interval_boundary_milliseconds(
            &client->fork_choice,
            next_interval,
            &now_milliseconds)
        != 0) {
        return -1;
    }

    int rc = lantern_fork_choice_advance_time(&client->fork_choice, now_milliseconds, has_proposal);
    if (rc != 0) {
        return rc;
    }
    if (client->fork_choice.time_intervals != next_interval) {
        return -1;
    }

    sync_aggregated_payload_pools_after_time_advance(client, previous_intervals, has_proposal);
    return 0;
}

int lantern_client_skip_fork_choice_intervals_locked(
    struct lantern_client *client,
    uint64_t target_interval) {
    if (!client || !client->has_fork_choice) {
        return -1;
    }
    if (target_interval < client->fork_choice.time_intervals) {
        return -1;
    }
    uint64_t previous_intervals = client->fork_choice.time_intervals;
    client->fork_choice.time_intervals = target_interval;
    uint64_t intervals_per_slot = client->fork_choice.intervals_per_slot;
    if (intervals_per_slot == 0u || target_interval == previous_intervals) {
        return 0;
    }
    for (uint64_t step = previous_intervals + 1u;; ++step) {
        uint64_t phase = step % intervals_per_slot;
        if (phase == 3u) {
            if (lantern_fork_choice_update_safe_target(&client->fork_choice) != 0) {
                return -1;
            }
        } else if (phase == 4u) {
            if (lantern_fork_choice_accept_new_votes(&client->fork_choice) != 0) {
                return -1;
            }
        }
        if (step == target_interval) {
            break;
        }
    }
    return 0;
}

int lantern_client_advance_fork_choice_time_locked(
    struct lantern_client *client,
    uint64_t now_milliseconds,
    bool has_proposal) {
    if (!client || !client->has_fork_choice) {
        return -1;
    }

    uint64_t previous_intervals = client->fork_choice.time_intervals;
    uint64_t target_interval = 0u;
    int target_rc = fork_choice_target_interval(&client->fork_choice, now_milliseconds, &target_interval);
    if (target_rc < 0) {
        return -1;
    }
    if (target_rc == 0
        && client->fork_choice.intervals_per_slot > 0
        && target_interval > previous_intervals
        && (target_interval - previous_intervals) > client->fork_choice.intervals_per_slot)
    {
        uint64_t skip_to_interval =
            target_interval - (uint64_t)client->fork_choice.intervals_per_slot;
        if (lantern_client_skip_fork_choice_intervals_locked(client, skip_to_interval) != 0) {
            return -1;
        }
        previous_intervals = client->fork_choice.time_intervals;
    }

    int rc = lantern_fork_choice_advance_time(&client->fork_choice, now_milliseconds, has_proposal);
    if (rc != 0) {
        return rc;
    }
    sync_aggregated_payload_pools_after_time_advance(client, previous_intervals, has_proposal);
    return 0;
}

/* ============================================================================
 * External Functions (from client_init.c)
 * ============================================================================ */

extern int copy_genesis_paths(struct lantern_genesis_paths *paths,
                              const struct lantern_client_options *options);
extern void reset_genesis_paths(struct lantern_genesis_paths *paths);
extern int append_genesis_bootnodes(struct lantern_client *client);
extern int compute_local_validator_assignment(struct lantern_client *client);
extern int populate_local_validators(struct lantern_client *client);
extern int init_consensus_runtime(struct lantern_client *client);


/**
 * @brief Initialize client options with default values.
 *
 * Sets all fields to their default values, including paths to configuration
 * files, network settings, and an empty bootnode list.
 *
 * @param options  Client options struct to initialize
 *
 * @note Thread safety: None required - operates on caller-provided struct.
 */
void lantern_client_options_init(struct lantern_client_options *options)
{
    if (!options)
    {
        return;
    }

    options->data_dir = LANTERN_DEFAULT_DATA_DIR;
    options->genesis_config_path = LANTERN_DEFAULT_GENESIS_CONFIG;
    options->validator_registry_path = LANTERN_DEFAULT_VALIDATOR_REGISTRY;
    options->nodes_path = LANTERN_DEFAULT_NODES_FILE;
    options->genesis_state_path = NULL;
    options->use_genesis_state = false;
    options->validator_config_path = LANTERN_DEFAULT_VALIDATOR_CONFIG;
    options->node_id = LANTERN_DEFAULT_NODE_ID;
    options->node_key_hex = NULL;
    options->node_key_path = NULL;
    options->listen_address = LANTERN_DEFAULT_LISTEN_ADDR;
    options->checkpoint_sync_url = NULL;
    options->http_port = LANTERN_DEFAULT_HTTP_PORT;
    options->metrics_port = LANTERN_DEFAULT_METRICS_PORT;
    options->devnet = LANTERN_DEFAULT_DEVNET;
    lantern_string_list_init(&options->bootnodes);
    options->xmss_key_dir = NULL;
    options->xmss_public_path = NULL;
    options->xmss_secret_path = NULL;
    options->xmss_public_template = NULL;
    options->xmss_secret_template = NULL;
    options->is_aggregator = false;
}


/**
 * @brief Free resources allocated within client options.
 *
 * Releases the bootnode list and any other dynamically allocated resources.
 * The options struct itself is not freed (caller-owned).
 *
 * @param options  Client options struct to free (may be NULL)
 *
 * @note Thread safety: None required - operates on caller-provided struct.
 */
void lantern_client_options_free(struct lantern_client_options *options)
{
    if (!options)
    {
        return;
    }
    lantern_string_list_reset(&options->bootnodes);
}


/**
 * @brief Add a bootnode address to client options.
 *
 * Appends an ENR string to the list of bootnodes that will be used
 * during client initialization to discover peers.
 *
 * @param options   Client options struct to modify
 * @param bootnode  ENR string (e.g., "enr:-...")
 *
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM if options or bootnode is NULL
 * @return LANTERN_CLIENT_ERR_ALLOC on allocation failure
 *
 * @note Thread safety: None required - operates on caller-provided struct.
 */
lantern_client_error lantern_client_options_add_bootnode(
    struct lantern_client_options *options,
    const char *bootnode)
{
    if (!options || !bootnode)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    return lantern_string_list_append(&options->bootnodes, bootnode) == 0
               ? LANTERN_CLIENT_OK
               : LANTERN_CLIENT_ERR_ALLOC;
}


/**
 * @brief Trim leading and trailing whitespace from a string in place.
 *
 * Advances the pointer past leading whitespace and overwrites trailing
 * whitespace with a null terminator.
 *
 * @param line  String to trim (modified in place)
 *
 * @return Pointer to the trimmed string, or NULL if input is NULL
 *
 * @note Thread safety: Caller must ensure exclusive access to the buffer.
 */
static char *trim_line(char *line)
{
    if (!line)
    {
        return NULL;
    }
    while (*line && isspace((unsigned char)*line))
    {
        ++line;
    }
    char *end = line + strlen(line);
    while (end > line && isspace((unsigned char)*(end - 1)))
    {
        --end;
    }
    *end = '\0';
    return line;
}


/**
 * @brief Add bootnodes from a newline-delimited or YAML-style file.
 *
 * Supports YAML list entries (leading '-') and ignores comments beginning
 * with '#'. Each parsed ENR is appended to the options bootnode list.
 *
 * @param options  Client options to mutate
 * @param path     Path to bootnodes file
 *
 * @return LANTERN_CLIENT_OK on success (at least one ENR added)
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM on bad inputs or parse failure
 * @return LANTERN_CLIENT_ERR_ALLOC on allocation failure
 *
 * @note Thread safety: Not thread-safe; mutates caller-owned options and uses
 *       shared logging. Call during single-threaded startup only.
 */
lantern_client_error lantern_client_options_add_bootnodes_from_file(
    struct lantern_client_options *options,
    const char *path)
{
    if (!options || !path)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    FILE *fp = fopen(path, "r");
    if (!fp)
    {
        lantern_log_error(
            "cli",
            &(const struct lantern_log_metadata){.validator = options->node_id},
            "unable to open bootnodes file %s",
            path);
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    char line[BOOTNODE_LINE_MAX_LEN];
    size_t added = 0;
    lantern_client_error result = LANTERN_CLIENT_OK;

    while (fgets(line, sizeof(line), fp))
    {
        char *trimmed = trim_line(line);
        if (!trimmed || *trimmed == '\0' || *trimmed == '#')
        {
            continue;
        }

        char *hash = strchr(trimmed, '#');
        if (hash)
        {
            *hash = '\0';
            trimmed = trim_line(trimmed);
            if (!trimmed || *trimmed == '\0')
            {
                continue;
            }
        }

        if (*trimmed == '-')
        {
            ++trimmed;
            while (*trimmed && isspace((unsigned char)*trimmed))
            {
                ++trimmed;
            }
        }

        char *value_start = strstr(trimmed, "enr:");
        if (!value_start)
        {
            if (strncmp(trimmed, "enr:", 4) != 0)
            {
                continue;
            }
            value_start = trimmed;
        }

        char *end = value_start + strlen(value_start);
        while (end > value_start && isspace((unsigned char)*(end - 1)))
        {
            --end;
        }
        *end = '\0';

        if (*value_start == '"' || *value_start == '\'')
        {
            ++value_start;
            size_t len = strlen(value_start);
            if (len > 0 && (value_start[len - 1] == '"' || value_start[len - 1] == '\''))
            {
                value_start[len - 1] = '\0';
            }
        }

        if (strncmp(value_start, "enr:", 4) != 0)
        {
            continue;
        }

        result = lantern_client_options_add_bootnode(options, value_start);
        if (result != LANTERN_CLIENT_OK)
        {
            break;
        }
        ++added;
        lantern_log_info(
            "cli",
            &(const struct lantern_log_metadata){
                .validator = options->node_id,
                .peer = value_start},
            "bootnode registered from %s",
            path);
    }

    if (fclose(fp) != 0)
    {
        lantern_log_warn(
            "cli",
            &(const struct lantern_log_metadata){.validator = options->node_id},
            "failed to close bootnodes file %s: %s",
            path,
            strerror(errno));
        if (result == LANTERN_CLIENT_OK)
        {
            result = LANTERN_CLIENT_ERR_INVALID_PARAM;
        }
    }

    if (result != LANTERN_CLIENT_OK)
    {
        return result;
    }

    if (added == 0)
    {
        lantern_log_warn(
            "cli",
            &(const struct lantern_log_metadata){.validator = options->node_id},
            "no ENRs found in %s",
            path);
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    return LANTERN_CLIENT_OK;
}


/**
 * @brief Add bootnodes from a command-line style argument.
 *
 * If the value begins with "enr:" it is treated as an ENR; otherwise it is
 * treated as a file path of ENRs.
 *
 * @param options  Client options to mutate
 * @param value    ENR string or path
 *
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM on invalid input/parse error
 * @return LANTERN_CLIENT_ERR_ALLOC on allocation failure
 *
 * @note Thread safety: Not thread-safe; mutates caller-owned options.
 */
lantern_client_error lantern_client_options_add_bootnodes_argument(
    struct lantern_client_options *options,
    const char *value)
{
    if (!options || !value)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    if (strncmp(value, "enr:", 4) == 0)
    {
        return lantern_client_options_add_bootnode(options, value);
    }

    return lantern_client_options_add_bootnodes_from_file(options, value);
}


/* ============================================================================
 * Internal Helpers
 * ============================================================================ */

/**
 * @brief Reset the client struct to baseline defaults.
 *
 * Zeroes all fields and initializes embedded lists, services, and locks to
 * known empty states. This prepares the struct for subsequent initialization
 * steps.
 *
 * @param client  Client instance to reset (must not be NULL)
 *
 * @note Thread safety: Caller must ensure exclusive access; intended for
 *       single-threaded initialization only.
 */
static void client_reset_base(struct lantern_client *client)
{
    memset(client, 0, sizeof(*client));
    lantern_string_list_init(&client->bootnodes);
    lantern_string_list_init(&client->dialer_peers);
    lantern_string_list_init(&client->connected_peer_ids);
    lantern_string_list_init(&client->inbound_peer_ids);
    lantern_string_list_init(&client->status_failure_peer_ids);
    double now_seconds = lantern_time_now_seconds();
    client->start_time_seconds = now_seconds > 0.0 ? (uint64_t)now_seconds : 0u;
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
    lantern_store_init(&client->store);
    lean_metrics_reset();
    client->state_lock_initialized = false;
    lantern_fork_choice_init(&client->fork_choice);
    lantern_store_attach_fork_choice(&client->store, &client->fork_choice);
    client->has_fork_choice = false;
    client->timing_thread_started = false;
    client->timing_stop_flag = 1;
    client->dialer_thread_started = false;
    client->dialer_stop_flag = 1;
    client->ping_thread_started = false;
    client->ping_stop_flag = 1;
    pending_block_list_init(&client->pending_blocks);
    pending_vote_list_init(&client->pending_gossip_votes);
    client->pending_lock_initialized = false;
    client->sync_state = LANTERN_SYNC_STATE_IDLE;
}


/**
 * @brief Apply user-provided options to the client instance.
 *
 * Copies configurable strings and ports into the client.
 *
 * @param client   Client being configured
 * @param options  Source options (must not be NULL)
 *
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_ALLOC if allocation fails
 *
 * @note Thread safety: Must be called before concurrent access to the client.
 */
static lantern_client_error client_apply_options(
    struct lantern_client *client,
    const struct lantern_client_options *options)
{
    if (set_owned_string(&client->data_dir, options->data_dir) != 0)
    {
        return LANTERN_CLIENT_ERR_ALLOC;
    }
    if (set_owned_string(&client->node_id, options->node_id) != 0)
    {
        return LANTERN_CLIENT_ERR_ALLOC;
    }
    lantern_log_set_node_id(client->node_id);
    if (set_owned_string(&client->listen_address, options->listen_address) != 0)
    {
        return LANTERN_CLIENT_ERR_ALLOC;
    }
    if (set_owned_string(&client->devnet, options->devnet) != 0)
    {
        return LANTERN_CLIENT_ERR_ALLOC;
    }

    client->http_port = options->http_port;
    client->metrics_port = options->metrics_port;
    return LANTERN_CLIENT_OK;
}


/**
 * @brief Initialize mutexes used by the client.
 *
 * Creates pending, status, state, and peer vote locks if they have not already
 * been initialized.
 *
 * @param client  Client owning the locks
 *
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_RUNTIME if any mutex initialization fails
 *
 * @note Thread safety: Must be invoked before any multi-threaded use.
 */
static lantern_client_error client_init_locks(struct lantern_client *client)
{
    if (pthread_mutex_init(&client->pending_lock, NULL) != 0)
    {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to initialize pending block lock");
        return LANTERN_CLIENT_ERR_RUNTIME;
    }
    client->pending_lock_initialized = true;

    if (!client->status_lock_initialized)
    {
        if (pthread_mutex_init(&client->status_lock, NULL) != 0)
        {
            lantern_log_error(
                "client",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "failed to initialize peer status lock");
            return LANTERN_CLIENT_ERR_RUNTIME;
        }
        client->status_lock_initialized = true;
    }

    if (!client->state_lock_initialized)
    {
        if (pthread_mutex_init(&client->state_lock, NULL) != 0)
        {
            lantern_log_error(
                "client",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "failed to initialize state lock");
            return LANTERN_CLIENT_ERR_RUNTIME;
        }
        client->state_lock_initialized = true;
    }

    if (!client->peer_vote_lock_initialized)
    {
        if (pthread_mutex_init(&client->peer_vote_lock, NULL) != 0)
        {
            lantern_log_error(
                "client",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "failed to initialize vote metrics lock");
            return LANTERN_CLIENT_ERR_RUNTIME;
        }
        client->peer_vote_lock_initialized = true;
    }

    return LANTERN_CLIENT_OK;
}


/**
 * @brief Prepare storage directories and load genesis artifacts.
 *
 * Ensures the data directory exists, copies bootnodes and path configuration,
 * loads genesis configuration, and validates validator assignment coverage.
 *
 * @param client   Client being prepared
 * @param options  Caller-provided options
 *
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_STORAGE on storage preparation failure
 * @return LANTERN_CLIENT_ERR_ALLOC on allocation failure
 * @return LANTERN_CLIENT_ERR_GENESIS on genesis validation failure
 *
 * @note Thread safety: Single-threaded initialization only.
 */
static lantern_client_error client_prepare_storage_and_genesis(
    struct lantern_client *client,
    const struct lantern_client_options *options)
{
    if (lantern_storage_prepare(client->data_dir) != 0)
    {
        lantern_log_error(
            "storage",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to prepare data directory '%s'",
            client->data_dir);
        return LANTERN_CLIENT_ERR_STORAGE;
    }

    if (lantern_string_list_copy(&client->bootnodes, &options->bootnodes) != 0)
    {
        return LANTERN_CLIENT_ERR_ALLOC;
    }

    if (copy_genesis_paths(&client->genesis_paths, options) != 0)
    {
        return LANTERN_CLIENT_ERR_ALLOC;
    }

    if (lantern_genesis_load(&client->genesis, &client->genesis_paths) != 0)
    {
        return LANTERN_CLIENT_ERR_GENESIS;
    }

    if (lantern_validator_config_assign_ranges(
            &client->genesis.validator_config,
            client->genesis.chain_config.validator_count)
        != 0)
    {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "validator-config does not cover %" PRIu64 " validators",
            client->genesis.chain_config.validator_count);
        return LANTERN_CLIENT_ERR_GENESIS;
    }

    if (lantern_validator_config_apply_assignments(
            &client->genesis.validator_config,
            client->genesis_paths.validator_registry_path,
            client->genesis.chain_config.validator_count)
        != 0)
    {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "validator assignment mapping invalid or incomplete");
        return LANTERN_CLIENT_ERR_GENESIS;
    }

    return LANTERN_CLIENT_OK;
}


/**
 * @brief Attempt genesis creation using embedded validator pubkeys.
 *
 * Builds the initial state from pubkeys included in the chain configuration.
 *
 * @param client  Client with loaded chain configuration
 *
 * @return true on success, false if pubkeys are missing or initialization fails
 *
 * @note Thread safety: Must run before concurrent access to the state.
 */
static bool client_try_genesis_from_pubkeys(struct lantern_client *client)
{
    if (!client->genesis.chain_config.validator_pubkeys
        || client->genesis.chain_config.validator_pubkeys_count == 0)
    {
        return false;
    }

    size_t vcount = client->genesis.chain_config.validator_pubkeys_count;
    if (lantern_state_generate_genesis(
            &client->state, client->genesis.chain_config.genesis_time, vcount)
        != 0)
    {
        return false;
    }

    if (lantern_state_set_validator_pubkeys(
            &client->state,
            client->genesis.chain_config.validator_pubkeys,
            vcount)
        != 0)
    {
        return false;
    }

    client->genesis_fallback_used = false;
    return true;
}


/**
 * @brief Attempt genesis creation from the validator registry file.
 *
 * Builds the genesis state using pubkeys sourced from the registry when the
 * explicit pubkey array is unavailable.
 *
 * @param client  Client with loaded genesis registry
 *
 * @return true on success, false otherwise
 *
 * @note Thread safety: Must run before concurrent access to the state.
 */
static bool client_try_genesis_from_registry(struct lantern_client *client)
{
    size_t vcount = client->genesis.validator_registry.count;
    if (vcount == 0
        || vcount != client->genesis.chain_config.validator_count)
    {
        lantern_log_warn(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "validator registry count (%zu) does not match chain config (%" PRIu64 ")",
            vcount,
            client->genesis.chain_config.validator_count);
        return false;
    }

    if (lantern_state_generate_genesis(
            &client->state,
            client->genesis.chain_config.genesis_time,
            vcount)
        != 0)
    {
        return false;
    }

    if (vcount > SIZE_MAX / LANTERN_VALIDATOR_PUBKEY_SIZE)
    {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "validator count overflow while allocating pubkeys");
        return false;
    }

    size_t pubkeys_len = vcount * LANTERN_VALIDATOR_PUBKEY_SIZE;
    uint8_t *pubkeys = calloc(pubkeys_len, sizeof(*pubkeys));
    if (!pubkeys)
    {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to allocate validator pubkey buffer");
        return false;
    }

    bool pubkey_ok = true;
    for (size_t i = 0; i < vcount; ++i)
    {
        const struct lantern_validator_record *rec = &client->genesis.validator_registry.records[i];
        uint8_t *dest = pubkeys + (i * LANTERN_VALIDATOR_PUBKEY_SIZE);
        if (rec->has_pubkey_bytes)
        {
            memcpy(dest, rec->pubkey_bytes, LANTERN_VALIDATOR_PUBKEY_SIZE);
        }
        else if (rec->pubkey_hex
                 && lantern_hex_decode(rec->pubkey_hex, dest, LANTERN_VALIDATOR_PUBKEY_SIZE) == 0)
        {
            /* decoded */
        }
        else
        {
            lantern_log_error(
                "client",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "missing or invalid pubkey for validator index=%zu; aborting genesis build",
                i);
            pubkey_ok = false;
            break;
        }
    }

    bool success = false;
    if (pubkey_ok
        && lantern_state_set_validator_pubkeys(&client->state, pubkeys, vcount) == 0)
    {
        client->genesis_fallback_used = true;
        success = true;
    }

    free(pubkeys);
    return success;
}


/**
 * @brief Log the deterministic anchor block derived from genesis state.
 *
 * Builds the canonical anchor block from the configured genesis parameters and
 * emits its root for debugging purposes.
 *
 * @param client  Client whose genesis configuration is used
 *
 * @note Thread safety: Read-only access to client during single-threaded init.
 */
static void client_log_generated_anchor_block(struct lantern_client *client)
{
    LanternState generated_state;
    LanternRoot generated_state_root;
    LanternBlock generated_block;
    LanternRoot generated_block_root;
    bool body_initialized = false;
    lantern_state_init(&generated_state);

    if (lantern_state_generate_genesis(
            &generated_state,
            client->state.config.genesis_time,
            client->state.config.num_validators)
        != 0)
    {
        goto cleanup;
    }

    if (lantern_hash_tree_root_state(&generated_state, &generated_state_root) != 0)
    {
        goto cleanup;
    }

    memset(&generated_block, 0, sizeof(generated_block));
    generated_block.slot = generated_state.slot;
    generated_block.proposer_index = 0;
    generated_block.parent_root = generated_state.latest_block_header.parent_root;
    generated_block.state_root = generated_state_root;
    lantern_block_body_init(&generated_block.body);
    body_initialized = true;

    if (lantern_hash_tree_root_block(&generated_block, &generated_block_root) == 0)
    {
        char generated_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
        format_root_hex(&generated_block_root, generated_hex, sizeof(generated_hex));
        lantern_log_info(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "generated anchor block root=%s",
            generated_hex[0] ? generated_hex : "0x0");
    }

cleanup:
    if (body_initialized)
    {
        lantern_block_body_reset(&generated_block.body);
    }
    lantern_state_reset(&generated_state);
}


/**
 * @brief Log all genesis anchor roots for debugging.
 *
 * Emits hash tree roots for the genesis block header, block, signed block, and
 * related canonical variants to help detect mismatched genesis data.
 *
 * @param client     Client containing the prepared genesis state
 * @param state_root Optional state root override (may be NULL)
 *
 * @note Thread safety: Read-only logging during initialization.
 */
static void client_log_genesis_anchors(
    struct lantern_client *client,
    const LanternRoot *state_root)
{
    LanternRoot header_root;
    LanternRoot genesis_block_root;
    LanternRoot genesis_signed_block_root;
    LanternRoot canonical_header_root;
    LanternRoot spec_header_root;
    char header_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    char state_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    char block_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    char signed_block_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    char parent_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    char canonical_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    char body_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    char spec_header_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    header_hex[0] = '\0';
    state_hex[0] = '\0';
    block_hex[0] = '\0';
    signed_block_hex[0] = '\0';
    parent_hex[0] = '\0';
    canonical_hex[0] = '\0';
    body_hex[0] = '\0';
    spec_header_hex[0] = '\0';
    if (lantern_hash_tree_root_block_header(&client->state.latest_block_header, &header_root) == 0)
    {
        format_root_hex(&header_root, header_hex, sizeof(header_hex));
    }
    if (state_root)
    {
        format_root_hex(state_root, state_hex, sizeof(state_hex));
    }
    LanternBlock genesis_block;
    memset(&genesis_block, 0, sizeof(genesis_block));
    genesis_block.slot = client->state.latest_block_header.slot;
    genesis_block.proposer_index = client->state.latest_block_header.proposer_index;
    genesis_block.parent_root = client->state.latest_block_header.parent_root;
    genesis_block.state_root = state_root
                                 ? *state_root
                                 : client->state.latest_block_header.state_root;
    lantern_block_body_init(&genesis_block.body);
    if (lantern_hash_tree_root_block(&genesis_block, &genesis_block_root) == 0)
    {
        format_root_hex(&genesis_block_root, block_hex, sizeof(block_hex));
    }
    lantern_block_body_reset(&genesis_block.body);
    format_root_hex(
        &client->state.latest_block_header.parent_root,
        parent_hex,
        sizeof(parent_hex));
    LanternBlockHeader canonical_header = client->state.latest_block_header;
    canonical_header.state_root = state_root ? *state_root : canonical_header.state_root;
    if (lantern_hash_tree_root_block_header(&canonical_header, &canonical_header_root) == 0)
    {
        format_root_hex(&canonical_header_root, canonical_hex, sizeof(canonical_hex));
    }
    LanternBlockBody empty_body_snapshot;
    lantern_block_body_init(&empty_body_snapshot);
    LanternRoot default_body_root;
    if (lantern_hash_tree_root_block_body(&empty_body_snapshot, &default_body_root) != 0)
    {
        memset(&default_body_root, 0, sizeof(default_body_root));
    }
    lantern_block_body_reset(&empty_body_snapshot);
    LanternBlockHeader spec_header = client->state.latest_block_header;
    spec_header.state_root = state_root ? *state_root : spec_header.state_root;
    spec_header.body_root = default_body_root;
    if (lantern_hash_tree_root_block_header(&spec_header, &spec_header_root) == 0)
    {
        format_root_hex(&spec_header_root, spec_header_hex, sizeof(spec_header_hex));
    }
    format_root_hex(
        &client->state.latest_block_header.body_root,
        body_hex,
        sizeof(body_hex));
    LanternSignedBlock genesis_signed;
    int resize_result = 0;
    lantern_signed_block_with_attestation_init(&genesis_signed);
    genesis_signed.message.block = genesis_block;
    resize_result = lantern_attestation_signatures_resize(
        &genesis_signed.signatures.attestation_signatures,
        0);
    if (resize_result != 0)
    {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to size genesis signatures list");
    }
    else if (lantern_hash_tree_root_signed_block(&genesis_signed, &genesis_signed_block_root) == 0)
    {
        format_root_hex(&genesis_signed_block_root, signed_block_hex, sizeof(signed_block_hex));
    }

    client_log_generated_anchor_block(client);

    lantern_log_info(
        "client",
        &(const struct lantern_log_metadata){.validator = client->node_id},
        "genesis anchors header_root=%s state_root=%s body_root=%s block_root=%s "
        "signed_block_root=%s canonical_header_root=%s spec_header_root=%s parent_root=%s",
        header_hex[0] ? header_hex : "0x0",
        state_hex[0] ? state_hex : "0x0",
        body_hex[0] ? body_hex : "0x0",
        block_hex[0] ? block_hex : "0x0",
        signed_block_hex[0] ? signed_block_hex : "0x0",
        canonical_hex[0] ? canonical_hex : "0x0",
        spec_header_hex[0] ? spec_header_hex : "0x0",
        parent_hex[0] ? parent_hex : "0x0");

    lantern_signed_block_with_attestation_reset(&genesis_signed);
}


/**
 * @brief Finalize the prepared genesis state.
 *
 * Allocates validator vote records, computes and logs the genesis state root,
 * and marks the client as having an initialized state.
 *
 * @param client  Client holding the generated genesis state
 *
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_GENESIS on failure to prepare votes or hash roots
 *
 * @note Thread safety: Single-threaded initialization only.
 */
static lantern_client_error client_finalize_genesis_state(struct lantern_client *client)
{
    if (lantern_store_prepare_validator_votes(
            &client->store,
            client->state.config.num_validators)
        != 0
        || lantern_store_prepare_fork_choice_votes(
               &client->store,
               client->state.config.num_validators)
        != 0)
    {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to prepare validator vote records");
        return LANTERN_CLIENT_ERR_GENESIS;
    }
    LanternRoot state_root;
    if (lantern_hash_tree_root_state(&client->state, &state_root) != 0)
    {
        return LANTERN_CLIENT_ERR_GENESIS;
    }

    client_log_genesis_anchors(client, &state_root);
    client->has_state = true;
    return LANTERN_CLIENT_OK;
}


/* ============================================================================
 * Checkpoint Sync Helpers
 * ============================================================================ */

static int checkpoint_sync_parse_port(
    const char *text,
    size_t text_len,
    uint16_t *out_port)
{
    if (!text || text_len == 0 || !out_port)
    {
        return -1;
    }

    uint32_t port = 0;
    for (size_t i = 0; i < text_len; ++i)
    {
        unsigned char ch = (unsigned char)text[i];
        if (!isdigit(ch))
        {
            return -1;
        }
        port = (port * 10u) + (uint32_t)(ch - '0');
        if (port > UINT16_MAX)
        {
            return -1;
        }
    }

    if (port == 0)
    {
        return -1;
    }
    *out_port = (uint16_t)port;
    return 0;
}

static int checkpoint_sync_parse_url(
    const char *url,
    char **out_host,
    uint16_t *out_port,
    char **out_base_path)
{
    if (!url || !out_host || !out_port || !out_base_path)
    {
        return -1;
    }

    *out_host = NULL;
    *out_base_path = NULL;
    *out_port = 0;

    const char *http_prefix = "http://";
    const char *https_prefix = "https://";
    size_t prefix_len = strlen(http_prefix);
    if (strncasecmp(url, http_prefix, prefix_len) == 0)
    {
        /* plain http — use as-is */
    }
    else if (strncasecmp(url, https_prefix, strlen(https_prefix)) == 0)
    {
        /* TLS not supported; downgrade to plain HTTP */
        prefix_len = strlen(https_prefix);
    }
    else
    {
        return -1;
    }

    const char *cursor = url + prefix_len;
    if (*cursor == '\0')
    {
        return -1;
    }

    const char *authority_start = cursor;
    while (*cursor && *cursor != '/' && *cursor != '?' && *cursor != '#')
    {
        ++cursor;
    }
    const char *authority_end = cursor;
    if (authority_end <= authority_start)
    {
        return -1;
    }

    char *base_path = NULL;
    if (*cursor == '/')
    {
        const char *path_start = cursor;
        while (*cursor && *cursor != '?' && *cursor != '#')
        {
            ++cursor;
        }
        base_path = lantern_string_duplicate_len(
            path_start,
            (size_t)(cursor - path_start));
    }
    else
    {
        base_path = lantern_string_duplicate("");
    }
    if (!base_path)
    {
        return -1;
    }

    char *host = NULL;
    uint16_t port = 80;

    if (*authority_start == '[')
    {
        const char *host_start = authority_start + 1;
        const char *host_end = host_start;
        while (host_end < authority_end && *host_end != ']')
        {
            ++host_end;
        }
        if (host_end >= authority_end || host_end == host_start)
        {
            free(base_path);
            return -1;
        }

        host = lantern_string_duplicate_len(
            host_start,
            (size_t)(host_end - host_start));
        if (!host)
        {
            free(base_path);
            return -1;
        }

        const char *port_start = host_end + 1;
        if (port_start < authority_end)
        {
            if (*port_start != ':'
                || checkpoint_sync_parse_port(
                       port_start + 1,
                       (size_t)(authority_end - (port_start + 1)),
                       &port)
                    != 0)
            {
                free(host);
                free(base_path);
                return -1;
            }
        }
    }
    else
    {
        const char *port_sep = NULL;
        for (const char *p = authority_start; p < authority_end; ++p)
        {
            if (*p == ':')
            {
                port_sep = p;
            }
        }

        const char *host_end = port_sep ? port_sep : authority_end;
        if (host_end <= authority_start)
        {
            free(base_path);
            return -1;
        }

        host = lantern_string_duplicate_len(
            authority_start,
            (size_t)(host_end - authority_start));
        if (!host)
        {
            free(base_path);
            return -1;
        }

        if (port_sep)
        {
            if (checkpoint_sync_parse_port(
                    port_sep + 1,
                    (size_t)(authority_end - (port_sep + 1)),
                    &port)
                != 0)
            {
                free(host);
                free(base_path);
                return -1;
            }
        }
    }

    if (!host[0])
    {
        free(host);
        free(base_path);
        return -1;
    }

    *out_host = host;
    *out_port = port;
    *out_base_path = base_path;
    return 0;
}

static bool checkpoint_sync_header_has_token(
    const char *value,
    const char *token)
{
    if (!value || !token || !token[0])
    {
        return false;
    }

    size_t token_len = strlen(token);
    const char *cursor = value;
    while (*cursor)
    {
        while (*cursor == ',' || isspace((unsigned char)*cursor))
        {
            ++cursor;
        }
        const char *entry_start = cursor;
        while (*cursor && *cursor != ',')
        {
            ++cursor;
        }
        const char *entry_end = cursor;
        while (entry_end > entry_start
               && isspace((unsigned char)*(entry_end - 1)))
        {
            --entry_end;
        }
        if ((size_t)(entry_end - entry_start) == token_len
            && strncasecmp(entry_start, token, token_len) == 0)
        {
            return true;
        }
        if (*cursor == ',')
        {
            ++cursor;
        }
    }

    return false;
}

#if defined(_WIN32)
static int checkpoint_sync_connect_tcp(const char *host, uint16_t port)
{
    (void)host;
    (void)port;
    return -1;
}
#else
static int checkpoint_sync_connect_tcp(const char *host, uint16_t port)
{
    if (!host || !host[0])
    {
        return -1;
    }

    char port_text[6];
    int port_written = snprintf(port_text, sizeof(port_text), "%u", (unsigned int)port);
    if (port_written <= 0 || (size_t)port_written >= sizeof(port_text))
    {
        return -1;
    }

    struct addrinfo hints;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;

    struct addrinfo *results = NULL;
    if (getaddrinfo(host, port_text, &hints, &results) != 0)
    {
        return -1;
    }

    int fd = -1;
    for (const struct addrinfo *candidate = results; candidate; candidate = candidate->ai_next)
    {
        fd = socket(candidate->ai_family, candidate->ai_socktype, candidate->ai_protocol);
        if (fd < 0)
        {
            continue;
        }
        if (connect(fd, candidate->ai_addr, candidate->ai_addrlen) == 0)
        {
            break;
        }
        close(fd);
        fd = -1;
    }

    freeaddrinfo(results);
    return fd;
}
#endif

static int checkpoint_sync_send_all(
    int fd,
    const uint8_t *data,
    size_t data_len)
{
    if (fd < 0 || !data)
    {
        return -1;
    }

    size_t sent = 0;
    while (sent < data_len)
    {
#if defined(_WIN32)
        int rc = send(fd, (const char *)(data + sent), (int)(data_len - sent), 0);
#else
        ssize_t rc = send(fd, data + sent, data_len - sent, 0);
#endif
        if (rc < 0)
        {
#if !defined(_WIN32)
            if (errno == EINTR)
            {
                continue;
            }
#endif
            return -1;
        }
        if (rc == 0)
        {
            return -1;
        }
        sent += (size_t)rc;
    }

    return 0;
}

static int checkpoint_sync_read_response(
    int fd,
    uint8_t **out_bytes,
    size_t *out_len)
{
    if (fd < 0 || !out_bytes || !out_len)
    {
        return -1;
    }

    *out_bytes = NULL;
    *out_len = 0;

    uint8_t *buffer = NULL;
    size_t buffer_len = 0;
    size_t buffer_cap = 0;

    for (;;)
    {
        uint8_t chunk[4096];
#if defined(_WIN32)
        int read_bytes = recv(fd, (char *)chunk, (int)sizeof(chunk), 0);
#else
        ssize_t read_bytes = recv(fd, chunk, sizeof(chunk), 0);
#endif
        if (read_bytes < 0)
        {
#if !defined(_WIN32)
            if (errno == EINTR)
            {
                continue;
            }
#endif
            free(buffer);
            return -1;
        }
        if (read_bytes == 0)
        {
            break;
        }

        if ((size_t)read_bytes > CHECKPOINT_SYNC_MAX_RESPONSE_BYTES - buffer_len)
        {
            free(buffer);
            return -1;
        }
        size_t needed = buffer_len + (size_t)read_bytes;
        if (needed > buffer_cap)
        {
            size_t new_cap = buffer_cap == 0 ? 8192u : buffer_cap;
            while (new_cap < needed)
            {
                if (new_cap > CHECKPOINT_SYNC_MAX_RESPONSE_BYTES / 2u)
                {
                    new_cap = CHECKPOINT_SYNC_MAX_RESPONSE_BYTES;
                    break;
                }
                new_cap *= 2u;
            }
            if (new_cap < needed)
            {
                free(buffer);
                return -1;
            }
            uint8_t *resized = realloc(buffer, new_cap);
            if (!resized)
            {
                free(buffer);
                return -1;
            }
            buffer = resized;
            buffer_cap = new_cap;
        }

        memcpy(buffer + buffer_len, chunk, (size_t)read_bytes);
        buffer_len += (size_t)read_bytes;
    }

    if (!buffer || buffer_len == 0)
    {
        free(buffer);
        return -1;
    }

    *out_bytes = buffer;
    *out_len = buffer_len;
    return 0;
}

static int checkpoint_sync_find_header_end(
    const uint8_t *data,
    size_t data_len,
    size_t *out_header_end)
{
    if (!data || data_len < 4 || !out_header_end)
    {
        return -1;
    }

    for (size_t i = 0; i + 3 < data_len; ++i)
    {
        if (data[i] == '\r'
            && data[i + 1] == '\n'
            && data[i + 2] == '\r'
            && data[i + 3] == '\n')
        {
            *out_header_end = i + 4;
            return 0;
        }
    }
    return -1;
}

static int checkpoint_sync_decode_chunked_body(
    const uint8_t *chunked_data,
    size_t chunked_len,
    uint8_t **out_body,
    size_t *out_body_len)
{
    if (!chunked_data || !out_body || !out_body_len)
    {
        return -1;
    }

    *out_body = NULL;
    *out_body_len = 0;

    uint8_t *decoded = NULL;
    size_t decoded_len = 0;
    size_t decoded_cap = 0;
    size_t cursor = 0;

    while (cursor < chunked_len)
    {
        size_t line_start = cursor;
        while (cursor + 1 < chunked_len
               && !(chunked_data[cursor] == '\r'
                    && chunked_data[cursor + 1] == '\n'))
        {
            ++cursor;
        }
        if (cursor + 1 >= chunked_len)
        {
            free(decoded);
            return -1;
        }

        size_t line_len = cursor - line_start;
        if (line_len == 0 || line_len >= 64u)
        {
            free(decoded);
            return -1;
        }

        char line[64];
        memcpy(line, chunked_data + line_start, line_len);
        line[line_len] = '\0';

        char *extensions = strchr(line, ';');
        if (extensions)
        {
            *extensions = '\0';
        }

        char *trimmed = line;
        while (*trimmed && isspace((unsigned char)*trimmed))
        {
            ++trimmed;
        }
        if (!*trimmed)
        {
            free(decoded);
            return -1;
        }

        errno = 0;
        char *endptr = NULL;
        unsigned long long chunk_size_u64 = strtoull(trimmed, &endptr, 16);
        if (errno != 0 || endptr == trimmed)
        {
            free(decoded);
            return -1;
        }
        while (*endptr && isspace((unsigned char)*endptr))
        {
            ++endptr;
        }
        if (*endptr != '\0')
        {
            free(decoded);
            return -1;
        }

        cursor += 2;

        if (chunk_size_u64 == 0)
        {
            if (cursor + 1 < chunked_len
                && chunked_data[cursor] == '\r'
                && chunked_data[cursor + 1] == '\n')
            {
                cursor += 2;
                break;
            }

            bool trailers_done = false;
            for (size_t i = cursor; i + 3 < chunked_len; ++i)
            {
                if (chunked_data[i] == '\r'
                    && chunked_data[i + 1] == '\n'
                    && chunked_data[i + 2] == '\r'
                    && chunked_data[i + 3] == '\n')
                {
                    cursor = i + 4;
                    trailers_done = true;
                    break;
                }
            }
            if (!trailers_done)
            {
                free(decoded);
                return -1;
            }
            break;
        }

        if (chunk_size_u64 > (unsigned long long)(chunked_len - cursor))
        {
            free(decoded);
            return -1;
        }
        if (chunk_size_u64 > CHECKPOINT_SYNC_MAX_RESPONSE_BYTES - decoded_len)
        {
            free(decoded);
            return -1;
        }

        size_t chunk_size = (size_t)chunk_size_u64;
        size_t needed = decoded_len + chunk_size;
        if (needed > decoded_cap)
        {
            size_t new_cap = decoded_cap == 0 ? 4096u : decoded_cap;
            while (new_cap < needed)
            {
                if (new_cap > CHECKPOINT_SYNC_MAX_RESPONSE_BYTES / 2u)
                {
                    new_cap = CHECKPOINT_SYNC_MAX_RESPONSE_BYTES;
                    break;
                }
                new_cap *= 2u;
            }
            if (new_cap < needed)
            {
                free(decoded);
                return -1;
            }

            uint8_t *resized = realloc(decoded, new_cap);
            if (!resized)
            {
                free(decoded);
                return -1;
            }
            decoded = resized;
            decoded_cap = new_cap;
        }

        memcpy(decoded + decoded_len, chunked_data + cursor, chunk_size);
        decoded_len += chunk_size;
        cursor += chunk_size;

        if (cursor + 1 >= chunked_len
            || chunked_data[cursor] != '\r'
            || chunked_data[cursor + 1] != '\n')
        {
            free(decoded);
            return -1;
        }
        cursor += 2;
    }

    *out_body = decoded;
    *out_body_len = decoded_len;
    return 0;
}

static int checkpoint_sync_extract_http_body(
    const uint8_t *response,
    size_t response_len,
    int *out_status_code,
    uint8_t **out_body,
    size_t *out_body_len)
{
    if (!response || !out_status_code || !out_body || !out_body_len)
    {
        return -1;
    }

    *out_status_code = 0;
    *out_body = NULL;
    *out_body_len = 0;

    size_t header_end = 0;
    if (checkpoint_sync_find_header_end(response, response_len, &header_end) != 0)
    {
        return -1;
    }

    char *headers = malloc(header_end + 1u);
    if (!headers)
    {
        return -1;
    }
    memcpy(headers, response, header_end);
    headers[header_end] = '\0';

    int status_code = 0;
    if (sscanf(headers, "HTTP/%*u.%*u %d", &status_code) != 1)
    {
        free(headers);
        return -1;
    }
    *out_status_code = status_code;

    bool is_chunked = false;
    bool has_content_length = false;
    size_t content_length = 0;

    char *line = strstr(headers, "\r\n");
    if (line)
    {
        line += 2;
    }
    while (line && line[0] != '\0')
    {
        char *line_end = strstr(line, "\r\n");
        if (!line_end)
        {
            break;
        }
        if (line_end == line)
        {
            break;
        }

        *line_end = '\0';
        size_t line_len = (size_t)(line_end - line);
        if (line_len >= 15
            && strncasecmp(line, "Content-Length:", 15) == 0)
        {
            const char *value = line + 15;
            while (*value && isspace((unsigned char)*value))
            {
                ++value;
            }
            errno = 0;
            char *endptr = NULL;
            unsigned long long parsed = strtoull(value, &endptr, 10);
            while (endptr && *endptr && isspace((unsigned char)*endptr))
            {
                ++endptr;
            }
            if (errno == 0 && endptr && *endptr == '\0')
            {
                if (parsed > CHECKPOINT_SYNC_MAX_RESPONSE_BYTES)
                {
                    free(headers);
                    return -1;
                }
                content_length = (size_t)parsed;
                has_content_length = true;
            }
        }
        else if (line_len >= 18
                 && strncasecmp(line, "Transfer-Encoding:", 18) == 0)
        {
            const char *value = line + 18;
            while (*value && isspace((unsigned char)*value))
            {
                ++value;
            }
            if (checkpoint_sync_header_has_token(value, "chunked"))
            {
                is_chunked = true;
            }
        }

        *line_end = '\r';
        line = line_end + 2;
    }

    const uint8_t *body_start = response + header_end;
    size_t body_available = response_len - header_end;

    if (status_code != 200)
    {
        free(headers);
        return 1;
    }

    int rc = -1;
    if (is_chunked)
    {
        rc = checkpoint_sync_decode_chunked_body(
            body_start,
            body_available,
            out_body,
            out_body_len);
    }
    else
    {
        size_t body_len = body_available;
        if (has_content_length)
        {
            if (body_available < content_length)
            {
                free(headers);
                return -1;
            }
            body_len = content_length;
        }

        if (body_len > CHECKPOINT_SYNC_MAX_RESPONSE_BYTES)
        {
            free(headers);
            return -1;
        }

        uint8_t *copy = malloc(body_len);
        if (!copy)
        {
            free(headers);
            return -1;
        }
        if (body_len > 0)
        {
            memcpy(copy, body_start, body_len);
        }
        *out_body = copy;
        *out_body_len = body_len;
        rc = 0;
    }

    free(headers);
    return rc;
}

static int checkpoint_sync_fetch_state_bytes(
    const char *checkpoint_sync_url,
    uint8_t **out_state_bytes,
    size_t *out_state_len,
    int *out_status_code)
{
    if (!checkpoint_sync_url || !out_state_bytes || !out_state_len || !out_status_code)
    {
        return -1;
    }

    *out_state_bytes = NULL;
    *out_state_len = 0;
    *out_status_code = 0;

    char *host = NULL;
    char *base_path = NULL;
    uint16_t port = 0;
    if (checkpoint_sync_parse_url(checkpoint_sync_url, &host, &port, &base_path) != 0)
    {
        return -1;
    }

    if (!base_path || !base_path[0])
    {
        free(base_path);
        free(host);
        return -1;
    }
    char *request_target = base_path;
    base_path = NULL;

    bool is_ipv6 = strchr(host, ':') != NULL;
    int host_header_len = snprintf(
        NULL,
        0,
        is_ipv6 ? "[%s]:%u" : "%s:%u",
        host,
        (unsigned int)port);
    if (host_header_len <= 0)
    {
        free(request_target);
        free(host);
        return -1;
    }
    char *host_header = malloc((size_t)host_header_len + 1u);
    if (!host_header)
    {
        free(request_target);
        free(host);
        return -1;
    }
    snprintf(
        host_header,
        (size_t)host_header_len + 1u,
        is_ipv6 ? "[%s]:%u" : "%s:%u",
        host,
        (unsigned int)port);

    int request_len = snprintf(
        NULL,
        0,
        "GET %s HTTP/1.1\r\n"
        "Host: %s\r\n"
        "Accept: application/octet-stream\r\n"
        "Connection: close\r\n"
        "\r\n",
        request_target,
        host_header);
    if (request_len <= 0)
    {
        free(host_header);
        free(request_target);
        free(host);
        return -1;
    }

    char *request = malloc((size_t)request_len + 1u);
    if (!request)
    {
        free(host_header);
        free(request_target);
        free(host);
        return -1;
    }
    snprintf(
        request,
        (size_t)request_len + 1u,
        "GET %s HTTP/1.1\r\n"
        "Host: %s\r\n"
        "Accept: application/octet-stream\r\n"
        "Connection: close\r\n"
        "\r\n",
        request_target,
        host_header);

    int fd = checkpoint_sync_connect_tcp(host, port);
    if (fd < 0)
    {
        free(request);
        free(host_header);
        free(request_target);
        free(host);
        return -1;
    }

    int rc = -1;
    uint8_t *response = NULL;
    size_t response_len = 0;
    if (checkpoint_sync_send_all(
            fd,
            (const uint8_t *)request,
            (size_t)request_len)
        != 0)
    {
        goto cleanup;
    }
    if (checkpoint_sync_read_response(fd, &response, &response_len) != 0)
    {
        goto cleanup;
    }

    rc = checkpoint_sync_extract_http_body(
        response,
        response_len,
        out_status_code,
        out_state_bytes,
        out_state_len);

cleanup:
#if !defined(_WIN32)
    close(fd);
#endif
    free(response);
    free(request);
    free(host_header);
    free(request_target);
    free(host);
    return rc;
}

static lantern_client_error client_load_state_from_checkpoint(
    struct lantern_client *client,
    const char *checkpoint_sync_url)
{
    if (!client || !checkpoint_sync_url || checkpoint_sync_url[0] == '\0')
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    struct lantern_log_metadata meta = {.validator = client->node_id};
    lantern_log_info(
        "checkpoint_sync",
        &meta,
        "fetching finalized checkpoint state from %s",
        checkpoint_sync_url);

    uint8_t *state_bytes = NULL;
    size_t state_len = 0;
    int status_code = 0;
    int fetch_rc = checkpoint_sync_fetch_state_bytes(
        checkpoint_sync_url,
        &state_bytes,
        &state_len,
        &status_code);
    if (fetch_rc != 0)
    {
        if (fetch_rc == 1)
        {
            lantern_log_error(
                "checkpoint_sync",
                &meta,
                "checkpoint sync endpoint returned HTTP %d",
                status_code);
        }
        else
        {
            lantern_log_error(
                "checkpoint_sync",
                &meta,
                "failed to fetch checkpoint state from %s",
                checkpoint_sync_url);
        }
        free(state_bytes);
        return LANTERN_CLIENT_ERR_NETWORK;
    }

    if (!state_bytes || state_len == 0)
    {
        free(state_bytes);
        lantern_log_error(
            "checkpoint_sync",
            &meta,
            "checkpoint sync endpoint returned an empty state payload");
        return LANTERN_CLIENT_ERR_NETWORK;
    }

    LanternState decoded;
    lantern_state_init(&decoded);
    bool decoded_owned = true;
    lantern_client_error result = LANTERN_CLIENT_OK;

    if (lantern_ssz_decode_state(&decoded, state_bytes, state_len) != 0)
    {
        lantern_log_error(
            "checkpoint_sync",
            &meta,
            "failed to decode checkpoint state SSZ (bytes=%zu)",
            state_len);
        result = LANTERN_CLIENT_ERR_GENESIS;
        goto cleanup;
    }

    if (decoded.config.num_validators == 0
        || decoded.validator_count == 0
        || decoded.config.num_validators != (uint64_t)decoded.validator_count)
    {
        lantern_log_error(
            "checkpoint_sync",
            &meta,
            "checkpoint state validator metadata invalid config=%" PRIu64 " decoded=%zu",
            decoded.config.num_validators,
            decoded.validator_count);
        result = LANTERN_CLIENT_ERR_GENESIS;
        goto cleanup;
    }

    if (decoded.config.genesis_time != client->genesis.chain_config.genesis_time)
    {
        lantern_log_error(
            "checkpoint_sync",
            &meta,
            "checkpoint genesis time mismatch checkpoint=%" PRIu64 " local=%" PRIu64,
            decoded.config.genesis_time,
            client->genesis.chain_config.genesis_time);
        result = LANTERN_CLIENT_ERR_GENESIS;
        goto cleanup;
    }

    if (decoded.latest_block_header.slot > decoded.slot
        || decoded.latest_justified.slot > decoded.slot
        || decoded.latest_finalized.slot > decoded.slot
        || decoded.latest_finalized.slot > decoded.latest_justified.slot)
    {
        lantern_log_error(
            "checkpoint_sync",
            &meta,
            "checkpoint state has inconsistent slot metadata state=%" PRIu64
            " head=%" PRIu64 " justified=%" PRIu64 " finalized=%" PRIu64,
            decoded.slot,
            decoded.latest_block_header.slot,
            decoded.latest_justified.slot,
            decoded.latest_finalized.slot);
        result = LANTERN_CLIENT_ERR_GENESIS;
        goto cleanup;
    }

    if (lantern_store_prepare_validator_votes(
            &client->store,
            decoded.config.num_validators)
        != 0
        || lantern_store_prepare_fork_choice_votes(
               &client->store,
               decoded.config.num_validators)
        != 0)
    {
        lantern_log_error(
            "checkpoint_sync",
            &meta,
            "failed to prepare validator votes for checkpoint state");
        result = LANTERN_CLIENT_ERR_GENESIS;
        goto cleanup;
    }

    LanternRoot state_root;
    if (lantern_hash_tree_root_state(&decoded, &state_root) != 0)
    {
        lantern_log_error(
            "checkpoint_sync",
            &meta,
            "failed to compute checkpoint state root");
        result = LANTERN_CLIENT_ERR_GENESIS;
        goto cleanup;
    }

    LanternBlockHeader anchor_header = decoded.latest_block_header;
    anchor_header.state_root = state_root;
    LanternRoot anchor_root;
    if (lantern_hash_tree_root_block_header(&anchor_header, &anchor_root) != 0)
    {
        lantern_log_error(
            "checkpoint_sync",
            &meta,
            "failed to compute checkpoint anchor root");
        result = LANTERN_CLIENT_ERR_GENESIS;
        goto cleanup;
    }

    /*
     * Preserve checkpoint roots exactly as provided by the remote state.
     *
     * Rewriting justified/finalized roots here mutates state content before
     * fork-choice anchor initialization, which can skew state/anchor hashing
     * relative to peers and force unnecessary slot-0 backfill requests.
     * Any root remapping needed for local fork-choice restoration is handled
     * later during restore_persisted_blocks().
     */

    char state_root_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    char anchor_root_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    format_root_hex(&state_root, state_root_hex, sizeof(state_root_hex));
    format_root_hex(&anchor_root, anchor_root_hex, sizeof(anchor_root_hex));

    lantern_state_reset(&client->state);
    client->state = decoded;
    decoded_owned = false;
    client->has_state = true;
    client->genesis_fallback_used = false;

    lantern_log_info(
        "checkpoint_sync",
        &meta,
        "initialized from checkpoint state slot=%" PRIu64
        " validators=%" PRIu64 " finalized_slot=%" PRIu64 " state_root=%s"
        " anchor_root=%s",
        client->state.slot,
        client->state.config.num_validators,
        client->state.latest_finalized.slot,
        state_root_hex[0] ? state_root_hex : "0x0",
        anchor_root_hex[0] ? anchor_root_hex : "0x0");

cleanup:
    free(state_bytes);
    if (decoded_owned)
    {
        lantern_state_reset(&decoded);
    }
    return result;
}

/**
 * @brief Build genesis state using the available artifact priority order.
 *
 * Tries embedded pubkeys first and then the validator registry. Lantern no
 * longer decodes local genesis.ssz for bootstrap so replay/state roots remain
 * deterministic from config/registry inputs.
 *
 * @param client  Client being initialized
 *
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_GENESIS when all strategies fail
 *
 * @note Thread safety: Single-threaded initialization only.
 */
static lantern_client_error client_generate_state_from_genesis(struct lantern_client *client)
{
    if (client_try_genesis_from_pubkeys(client))
    {
        return client_finalize_genesis_state(client);
    }

    if (client_try_genesis_from_registry(client))
    {
        return client_finalize_genesis_state(client);
    }

    return LANTERN_CLIENT_ERR_GENESIS;
}


/**
 * @brief Load persisted state or construct a new genesis state.
 *
 * Attempts to load state and votes from storage; if unavailable, constructs the
 * state from genesis artifacts and persists the initial snapshot.
 *
 * @param client               Client whose state is being initialized
 * @param options              Client options (checkpoint sync URL, etc.)
 * @param loaded_from_storage  Optional output flag indicating storage load
 *
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_STORAGE on storage I/O failure
 * @return LANTERN_CLIENT_ERR_GENESIS on genesis construction failure
 * @return LANTERN_CLIENT_ERR_NETWORK on checkpoint fetch failure
 *
 * @note Thread safety: Must be called before any concurrent access.
 */
static lantern_client_error client_load_or_build_state(
    struct lantern_client *client,
    const struct lantern_client_options *options,
    bool *loaded_from_storage)
{
    bool from_storage = false;
    int storage_state_rc = lantern_storage_load_state(client->data_dir, &client->state);
    if (storage_state_rc == 0)
    {
        client->has_state = true;
        from_storage = true;
        if (options
            && options->checkpoint_sync_url
            && options->checkpoint_sync_url[0] != '\0')
        {
            lantern_log_info(
                "checkpoint_sync",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "using persisted state; skipping checkpoint fetch");
        }
    }
    else if (storage_state_rc < 0)
    {
        lantern_log_error(
            "storage",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to load persisted state");
        return LANTERN_CLIENT_ERR_STORAGE;
    }
    else
    {
        if (options
            && options->checkpoint_sync_url
            && options->checkpoint_sync_url[0] != '\0')
        {
            lantern_client_error checkpoint_rc = client_load_state_from_checkpoint(
                client,
                options->checkpoint_sync_url);
            if (checkpoint_rc != LANTERN_CLIENT_OK)
            {
                return checkpoint_rc;
            }
        }
        else if (client_generate_state_from_genesis(client) != LANTERN_CLIENT_OK)
        {
            return LANTERN_CLIENT_ERR_GENESIS;
        }
    }

    if (client->has_state)
    {
        int votes_rc = lantern_storage_load_votes(client->data_dir, &client->state, &client->store);
        if (votes_rc < 0)
        {
            lantern_log_error(
                "storage",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "failed to load persisted votes");
            return LANTERN_CLIENT_ERR_STORAGE;
        }
        if (initialize_fork_choice(client) != 0)
        {
            return LANTERN_CLIENT_ERR_GENESIS;
        }
        if (restore_persisted_blocks(client) != 0)
        {
            return LANTERN_CLIENT_ERR_STORAGE;
        }
    }

    if (client->has_state && !from_storage)
    {
        if (lantern_storage_save_state(client->data_dir, &client->state) != 0)
        {
            lantern_log_warn(
                "storage",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "failed to persist initial state snapshot");
        }
        if (lantern_storage_save_votes(client->data_dir, &client->state, &client->store) != 0)
        {
            lantern_log_warn(
                "storage",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "failed to persist initial votes snapshot");
        }
    }

    if (loaded_from_storage)
    {
        *loaded_from_storage = from_storage;
    }
    return client->has_state ? LANTERN_CLIENT_OK : LANTERN_CLIENT_ERR_GENESIS;
}


/**
 * @brief Configure the client's local validator slice and key material.
 *
 * Validates presence of the node's ENR entry, computes validator assignments,
 * loads local validator definitions, and refreshes pubkeys.
 *
 * @param client   Client being configured
 * @param options  User-supplied options for key sources
 *
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_CONFIG or LANTERN_CLIENT_ERR_VALIDATOR on failure
 *
 * @note Thread safety: Initialization only; not safe for concurrent use.
 */
static lantern_client_error client_setup_validators(
    struct lantern_client *client,
    const struct lantern_client_options *options)
{
    client->assigned_validators = lantern_validator_config_find(
        &client->genesis.validator_config,
        client->node_id);

    if (!client->assigned_validators)
    {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "node-id '%s' not found in validator-config",
            client->node_id);
        return LANTERN_CLIENT_ERR_CONFIG;
    }

    if (options->is_aggregator)
    {
        ((struct lantern_validator_config_entry *)client->assigned_validators)
            ->enr.is_aggregator = true;
    }

    if (!client->assigned_validators->enr.ip || client->assigned_validators->enr.quic_port == 0)
    {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "validator '%s' missing ENR fields",
            client->node_id);
        return LANTERN_CLIENT_ERR_CONFIG;
    }

    if (lantern_client_configure_xmss_sources(client, options) != 0)
    {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to configure xmss key sources");
        return LANTERN_CLIENT_ERR_CONFIG;
    }

    adopt_validator_listen_address(client);

    if (compute_local_validator_assignment(client) != 0)
    {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to compute validator assignment for '%s'",
            client->node_id);
        return LANTERN_CLIENT_ERR_VALIDATOR;
    }

    if (populate_local_validators(client) != 0)
    {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to enumerate local validators for '%s'",
            client->node_id);
        return LANTERN_CLIENT_ERR_VALIDATOR;
    }

    if (client->local_validator_count == 0 || !client->has_state)
    {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "no local validators assigned for '%s'; check validator-config",
            client->node_id);
        return LANTERN_CLIENT_ERR_VALIDATOR;
    }

    if (lantern_client_refresh_state_validators(client) != 0)
    {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to refresh validator pubkeys for '%s'",
            client->node_id);
        return LANTERN_CLIENT_ERR_VALIDATOR;
    }

    if (lantern_client_load_xmss_keys(client) != 0)
    {
        return LANTERN_CLIENT_ERR_VALIDATOR;
    }

    lantern_log_info(
        "client",
        &(const struct lantern_log_metadata){.validator = client->node_id},
        "validator slice start=%" PRIu64 " count=%" PRIu64,
        client->validator_assignment.start_index,
        client->validator_assignment.count);

    return LANTERN_CLIENT_OK;
}


/**
 * @brief Start the consensus runtime used by validator duties.
 *
 * Initializes runtime structures after state and validator configuration are
 * ready.
 *
 * @param client  Client containing prepared state
 *
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_RUNTIME if initialization fails
 *
 * @note Thread safety: Single-threaded initialization only.
 */
static lantern_client_error client_start_runtime(struct lantern_client *client)
{
    if (init_consensus_runtime(client) != 0)
    {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to initialize consensus runtime");
        return LANTERN_CLIENT_ERR_RUNTIME;
    }

    lantern_log_info(
        "client",
        &(const struct lantern_log_metadata){.validator = client->node_id},
        "consensus runtime ready genesis_time=%" PRIu64 " validators=%" PRIu64,
        client->genesis.chain_config.genesis_time,
        client->genesis.chain_config.validator_count);
    return LANTERN_CLIENT_OK;
}


/**
 * @brief Start libp2p host and connection-level services.
 *
 * Loads the node key, starts the libp2p host, subscribes to connection events,
 * and launches the ping service.
 *
 * @param client   Client to start networking for
 * @param options  User options containing key paths
 * @param node_key Buffer for the loaded node private key (cleared on return)
 *
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_CONFIG on key load failure
 * @return LANTERN_CLIENT_ERR_NETWORK on libp2p errors
 *
 * @note Thread safety: Must be called before networking threads start.
 */
static lantern_client_error client_start_network(
    struct lantern_client *client,
    const struct lantern_client_options *options,
    uint8_t node_key[NODE_PRIVATE_KEY_SIZE])
{
    if (load_node_key_bytes(options, node_key) != 0)
    {
        return LANTERN_CLIENT_ERR_CONFIG;
    }
    memcpy(client->node_private_key, node_key, NODE_PRIVATE_KEY_SIZE);
    client->has_node_private_key = true;

    struct lantern_libp2p_config net_cfg = {
        .listen_multiaddr = client->listen_address,
        .secp256k1_secret = node_key,
        .secret_len = NODE_PRIVATE_KEY_SIZE,
        .allow_outbound_identify = 1,
    };

    if (lantern_libp2p_host_start(&client->network, &net_cfg) != 0)
    {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to initialize libp2p host");
        return LANTERN_CLIENT_ERR_NETWORK;
    }

    if (!client->connection_lock_initialized)
    {
        if (pthread_mutex_init(&client->connection_lock, NULL) != 0)
        {
            lantern_log_error(
                "network",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "failed to initialize connection lock");
            return LANTERN_CLIENT_ERR_NETWORK;
        }
        client->connection_lock_initialized = true;
    }
    connection_counter_reset(client);

    if (libp2p_event_subscribe(
            client->network.host,
            connection_events_cb,
            client,
            &client->connection_subscription)
        != 0)
    {
        lantern_log_error(
            "network",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to subscribe to libp2p connection events");
        return LANTERN_CLIENT_ERR_NETWORK;
    }

    libp2p_protocol_server_t *ping_server = NULL;
    if (libp2p_ping_service_start(client->network.host, &ping_server) != 0)
    {
        lantern_log_error(
            "network",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to start libp2p ping service");
        return LANTERN_CLIENT_ERR_NETWORK;
    }

    client->ping_server = ping_server;
    client->ping_running = true;
    lantern_log_info(
        "network",
        &(const struct lantern_log_metadata){.validator = client->node_id},
        "libp2p ping service started");

    return LANTERN_CLIENT_OK;
}


/**
 * @brief Start gossipsub and request/response protocols.
 *
 * Configures protocol handlers, seeds peer modes, and builds the local ENR
 * using the provided node key.
 *
 * @param client   Client with an active libp2p host
 * @param node_key Node private key used for ENR construction
 *
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_NETWORK on protocol startup failure
 *
 * @note Thread safety: Must be invoked before background networking threads.
 */
static lantern_client_error client_start_protocols(
    struct lantern_client *client,
    uint8_t node_key[NODE_PRIVATE_KEY_SIZE])
{
    size_t subnet_id = 0;
    if (client->local_validators && client->local_validator_count > 0) {
        (void)lantern_validator_index_compute_subnet_id(
            client->local_validators[0].global_index,
            LANTERN_ATTESTATION_COMMITTEE_COUNT,
            &subnet_id);
    }
    struct lantern_gossipsub_config gossip_cfg = {
        .host = client->network.host,
        .devnet = client->devnet,
        .data_dir = client->data_dir,
        .attestation_subnet_id = subnet_id,
        .subscribe_attestation_subnet = 1,
    };
    lantern_gossipsub_service_set_block_handler(&client->gossip, gossip_block_handler, client);
    lantern_gossipsub_service_set_vote_handler(&client->gossip, gossip_vote_handler, client);
    lantern_gossipsub_service_set_aggregated_attestation_handler(
        &client->gossip,
        gossip_aggregated_attestation_handler,
        client);
    if (lantern_gossipsub_service_start(&client->gossip, &gossip_cfg) != 0)
    {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to start gossipsub service");
        return LANTERN_CLIENT_ERR_NETWORK;
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
    if (lantern_reqresp_service_start(&client->reqresp, &req_config) != 0)
    {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to start request/response service");
        return LANTERN_CLIENT_ERR_NETWORK;
    }
    client->reqresp_running = true;

    if (append_genesis_bootnodes(client) != 0)
    {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to append bootnodes from genesis");
        return LANTERN_CLIENT_ERR_NETWORK;
    }

    if (lantern_enr_record_build_v4(
            &client->local_enr,
            node_key,
            client->assigned_validators->enr.ip,
            client->assigned_validators->enr.quic_port,
            client->assigned_validators->enr.sequence,
            client->assigned_validators->enr.is_aggregator)
        != 0)
    {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to build local ENR");
        return LANTERN_CLIENT_ERR_NETWORK;
    }

    lantern_log_info(
        "client",
        &(const struct lantern_log_metadata){.validator = client->node_id},
        "local ENR prepared sequence=%" PRIu64,
        client->assigned_validators->enr.sequence);

    memset(node_key, 0, NODE_PRIVATE_KEY_SIZE);
    return LANTERN_CLIENT_OK;
}


/**
 * @brief Launch background services for peer dialing, ping, and validator duties.
 *
 * Starts auxiliary threads; failures are logged as warnings but do not abort
 * client startup.
 *
 * @param client  Client for which background services are started
 *
 * @note Thread safety: Caller must ensure services are started once during init.
 */
static void client_start_background_services(struct lantern_client *client)
{
    if (start_peer_dialer(client) != 0)
    {
        lantern_log_warn(
            "network",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to start peer dialer thread");
    }

    if (start_ping_service(client) != 0)
    {
        lantern_log_warn(
            "network",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to start ping service thread");
    }

    if (start_timing_service(client) != 0)
    {
        lantern_log_warn(
            "forkchoice",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "fork-choice timing inactive");
    }

    if (start_validator_service(client) != 0)
    {
        lantern_log_warn(
            "validator",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "validator duties inactive");
    }
}


/**
 * @brief Stop validator-related services and free xmss key resources.
 *
 * Shuts down validator, ping, and peer dialer threads and frees hash signature
 * key material paths and buffers.
 *
 * @param client  Client to clean up
 *
 * @note Thread safety: Caller must ensure background threads are not running.
 */
static void shutdown_validator_and_keys(struct lantern_client *client)
{
    stop_timing_service(client);
    stop_validator_service(client);
    stop_ping_service(client);
    stop_peer_dialer(client);
    lantern_client_free_xmss_pubkeys(client);
    free(client->xmss_key_dir);
    client->xmss_key_dir = NULL;
    free(client->xmss_public_template);
    client->xmss_public_template = NULL;
    free(client->xmss_secret_template);
    client->xmss_secret_template = NULL;
    free(client->xmss_public_path);
    client->xmss_public_path = NULL;
    free(client->xmss_secret_path);
    client->xmss_secret_path = NULL;
}


/**
 * @brief Stop HTTP and metrics servers and reset their state.
 *
 * @param client  Client whose API servers are being stopped
 *
 * @note Thread safety: Caller must ensure no requests are in flight.
 */
static void shutdown_http_and_metrics(struct lantern_client *client)
{
    lantern_metrics_server_stop(&client->metrics_server);
    lantern_metrics_server_init(&client->metrics_server);
    client->metrics_running = false;

    lantern_http_server_stop(&client->http_server);
    lantern_http_server_init(&client->http_server);
    client->http_running = false;
}


/**
 * @brief Tear down networking services and related synchronization primitives.
 *
 * Unsubscribes from libp2p events, stops ping service, destroys connection
 * lock, and clears peer tracking lists.
 *
 * @param client  Client whose networking stack is being shut down
 *
 * @note Thread safety: Must be called after networking threads have stopped.
 */
static void shutdown_network_services(struct lantern_client *client)
{
    if (client->network.host && client->connection_subscription)
    {
        libp2p_event_unsubscribe(client->network.host, client->connection_subscription);
    }
    client->connection_subscription = NULL;

    if (client->network.host && client->ping_running && client->ping_server)
    {
        if (libp2p_ping_service_stop(client->network.host, client->ping_server) != 0)
        {
            lantern_log_warn(
                "network",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "failed to stop libp2p ping service cleanly");
        }
        else
        {
            lantern_log_info(
                "network",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "shutdown: libp2p ping service stopped");
        }
    }
    client->ping_server = NULL;
    client->ping_running = false;

    if (client->connection_lock_initialized)
    {
        connection_counter_reset(client);
        pthread_mutex_destroy(&client->connection_lock);
        client->connection_lock_initialized = false;
    }
    else
    {
        client->connected_peers = 0;
    }
    lantern_string_list_reset(&client->connected_peer_ids);
    lantern_string_list_reset(&client->inbound_peer_ids);
}


/**
 * @brief Free peer tracking structures and destroy associated locks.
 *
 * @param client  Client whose peer tracking data is being cleared
 *
 * @note Thread safety: Caller must ensure no concurrent access to peer data.
 */
static void shutdown_peer_tracking(struct lantern_client *client)
{
    if (client->status_lock_initialized)
    {
        if (pthread_mutex_lock(&client->status_lock) == 0)
        {
            free(client->peer_status_entries);
            client->peer_status_entries = NULL;
            client->peer_status_count = 0;
            client->peer_status_capacity = 0;
            free(client->active_blocks_requests);
            client->active_blocks_requests = NULL;
            client->active_blocks_request_count = 0;
            client->active_blocks_request_capacity = 0;
            client->next_blocks_request_id = 0;
            pthread_mutex_unlock(&client->status_lock);
        }
        else
        {
            free(client->peer_status_entries);
            client->peer_status_entries = NULL;
            client->peer_status_count = 0;
            client->peer_status_capacity = 0;
            free(client->active_blocks_requests);
            client->active_blocks_requests = NULL;
            client->active_blocks_request_count = 0;
            client->active_blocks_request_capacity = 0;
            client->next_blocks_request_id = 0;
        }
        pthread_mutex_destroy(&client->status_lock);
        client->status_lock_initialized = false;
    }
    else
    {
        free(client->peer_status_entries);
        client->peer_status_entries = NULL;
        client->peer_status_count = 0;
        client->peer_status_capacity = 0;
        free(client->active_blocks_requests);
        client->active_blocks_requests = NULL;
        client->active_blocks_request_count = 0;
        client->active_blocks_request_capacity = 0;
        client->next_blocks_request_id = 0;
    }

    if (client->peer_vote_lock_initialized)
    {
        if (pthread_mutex_lock(&client->peer_vote_lock) == 0)
        {
            free(client->peer_vote_stats);
            client->peer_vote_stats = NULL;
            client->peer_vote_stats_len = 0;
            client->peer_vote_stats_cap = 0;
            pthread_mutex_unlock(&client->peer_vote_lock);
        }
        else
        {
            free(client->peer_vote_stats);
            client->peer_vote_stats = NULL;
            client->peer_vote_stats_len = 0;
            client->peer_vote_stats_cap = 0;
        }
        pthread_mutex_destroy(&client->peer_vote_lock);
        client->peer_vote_lock_initialized = false;
    }
    else
    {
        free(client->peer_vote_stats);
        client->peer_vote_stats = NULL;
        client->peer_vote_stats_len = 0;
        client->peer_vote_stats_cap = 0;
    }
}


/**
 * @brief Destroy validator enablement lock and associated arrays.
 *
 * @param client  Client whose validator lock is being destroyed
 *
 * @note Thread safety: Caller must ensure no validator access is ongoing.
 */
static void shutdown_validator_lock(struct lantern_client *client)
{
    if (client->validator_lock_initialized)
    {
        if (pthread_mutex_lock(&client->validator_lock) == 0)
        {
            free(client->validator_enabled);
            client->validator_enabled = NULL;
            pthread_mutex_unlock(&client->validator_lock);
        }
        else
        {
            free(client->validator_enabled);
            client->validator_enabled = NULL;
        }
        pthread_mutex_destroy(&client->validator_lock);
        client->validator_lock_initialized = false;
    }
    else
    {
        free(client->validator_enabled);
        client->validator_enabled = NULL;
    }
}


/**
 * @brief Clear pending block list and destroy its mutex.
 *
 * @param client  Client whose pending blocks are being cleared
 *
 * @note Thread safety: Caller must stop block processing threads first.
 */
static void shutdown_pending_blocks(struct lantern_client *client)
{
    if (client->pending_lock_initialized)
    {
        if (pthread_mutex_lock(&client->pending_lock) == 0)
        {
            pending_block_list_reset(&client->pending_blocks);
            pthread_mutex_unlock(&client->pending_lock);
        }
        else
        {
            pending_block_list_reset(&client->pending_blocks);
        }
        pthread_mutex_destroy(&client->pending_lock);
        client->pending_lock_initialized = false;
    }
    else
    {
        pending_block_list_reset(&client->pending_blocks);
    }
}


/**
 * @brief Release string lists and dynamically allocated client strings.
 *
 * @param client  Client whose lists and strings are being freed
 *
 * @note Thread safety: Caller must ensure exclusive access.
 */
static void shutdown_strings_and_lists(struct lantern_client *client)
{
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
}


/**
 * @brief Reset genesis artifacts and networking components.
 *
 * Resets req/resp and gossipsub services, libp2p host, local ENR, and zeroes
 * the node private key buffer.
 *
 * @param client  Client whose genesis/network resources are being reset
 *
 * @note Thread safety: Caller must ensure no networking activity is ongoing.
 */
static void shutdown_genesis_and_network(struct lantern_client *client)
{
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
}


/**
 * @brief Reset state, fork choice, validator assignments, and runtime.
 *
 * @param client  Client to reset
 *
 * @note Thread safety: Caller must ensure no concurrent state access.
 */
static void shutdown_state_and_runtime(struct lantern_client *client)
{
    pending_vote_list_reset(&client->pending_gossip_votes);
    if (client->has_state)
    {
        lantern_state_reset(&client->state);
        client->has_state = false;
    }
    else
    {
        lantern_state_reset(&client->state);
    }
    lantern_store_reset(&client->store);
    if (client->state_lock_initialized)
    {
        pthread_mutex_destroy(&client->state_lock);
        client->state_lock_initialized = false;
    }
    lantern_fork_choice_reset(&client->fork_choice);
    client->has_fork_choice = false;
    lantern_client_reset_local_validators(client);
    lantern_validator_assignment_reset(&client->validator_assignment);
    client->has_validator_assignment = false;
    lantern_consensus_runtime_reset(&client->runtime);
    client->has_runtime = false;

    client->http_port = 0;
    client->metrics_port = 0;
    client->assigned_validators = NULL;
    lantern_log_reset_node_id();
}


/**
 * @brief Start HTTP and metrics APIs for the client.
 *
 * Configures the HTTP server callbacks and, if configured, the Prometheus
 * metrics endpoint.
 *
 * @param client  Client owning the API services
 *
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_NETWORK if either server fails to start
 *
 * @note Thread safety: Must be called before serving concurrent requests.
 */
static lantern_client_error client_start_apis(struct lantern_client *client)
{
    client->http_running = false;

    struct lantern_metrics_callbacks metrics_callbacks;
    memset(&metrics_callbacks, 0, sizeof(metrics_callbacks));
    metrics_callbacks.context = client;
    metrics_callbacks.snapshot = metrics_snapshot_cb;
    if (client->metrics_port != 0)
    {
        if (lantern_metrics_server_start(
                &client->metrics_server,
                client->metrics_port,
                &metrics_callbacks)
            != 0)
        {
            lantern_log_error(
                "client",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "failed to start metrics server on port %" PRIu16,
                client->metrics_port);
            return LANTERN_CLIENT_ERR_NETWORK;
        }
        client->metrics_running = true;
    }

    struct lantern_http_server_config http_config;
    memset(&http_config, 0, sizeof(http_config));
    http_config.port = client->http_port;
    http_config.callbacks.context = client;
    http_config.callbacks.snapshot_head = http_snapshot_head;
    http_config.callbacks.snapshot_fork_choice = http_snapshot_fork_choice;
    http_config.callbacks.validator_count = http_validator_count_cb;
    http_config.callbacks.validator_info = http_validator_info_cb;
    http_config.callbacks.set_validator_status = http_set_validator_status_cb;
    http_config.callbacks.metrics_snapshot = metrics_snapshot_cb;
    http_config.callbacks.finalized_state_ssz = http_finalized_state_ssz_cb;
    if (client->http_port != 0)
    {
        if (lantern_http_server_start(&client->http_server, &http_config) != 0)
        {
            lantern_log_error(
                "client",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "failed to start HTTP server on port %" PRIu16,
                client->http_port);
            return LANTERN_CLIENT_ERR_NETWORK;
        }
        client->http_running = true;
    }

    return LANTERN_CLIENT_OK;
}


/**
 * @brief Initialize and start the Lantern client.
 *
 * Sets up all subsystems including networking, gossip, request/response,
 * validator services, and HTTP/metrics servers. This is the main entry
 * point for starting a Lantern node.
 *
 * Initialization order:
 * 1. Genesis and state loading
 * 2. Validator configuration
 * 3. Networking (libp2p host, gossipsub, request/response)
 * 4. Services (HTTP, metrics, validator duties)
 *
 * @param client   Client struct to initialize (must be zeroed or freshly allocated)
 * @param options  Configuration options (not modified, can be freed after call)
 *
 * @return LANTERN_CLIENT_OK on success
 * @return negative lantern_client_error on failure (client is cleaned up via lantern_shutdown)
 *
 * @note Thread safety: Must be called from a single thread before any
 *       concurrent access to the client. Initializes all internal locks.
 */
lantern_client_error lantern_init(
    struct lantern_client *client,
    const struct lantern_client_options *options)
{
    if (!client || !options)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    uint8_t node_key[NODE_PRIVATE_KEY_SIZE];
    lantern_client_error err = LANTERN_CLIENT_OK;

    client_reset_base(client);

    err = client_apply_options(client, options);
    if (err != LANTERN_CLIENT_OK)
    {
        goto error;
    }

    err = client_init_locks(client);
    if (err != LANTERN_CLIENT_OK)
    {
        goto error;
    }

    err = client_prepare_storage_and_genesis(client, options);
    if (err != LANTERN_CLIENT_OK)
    {
        goto error;
    }

    err = client_load_or_build_state(client, options, NULL);
    if (err != LANTERN_CLIENT_OK)
    {
        goto error;
    }

    err = client_setup_validators(client, options);
    if (err != LANTERN_CLIENT_OK)
    {
        goto error;
    }

    err = client_start_runtime(client);
    if (err != LANTERN_CLIENT_OK)
    {
        goto error;
    }

    err = client_start_network(client, options, node_key);
    if (err != LANTERN_CLIENT_OK)
    {
        memset(node_key, 0, sizeof(node_key));
        goto error;
    }

    err = client_start_protocols(client, node_key);
    if (err != LANTERN_CLIENT_OK)
    {
        memset(node_key, 0, sizeof(node_key));
        goto error;
    }

    client_start_background_services(client);

    err = client_start_apis(client);
    if (err != LANTERN_CLIENT_OK)
    {
        goto error;
    }

    return LANTERN_CLIENT_OK;

error:
    memset(node_key, 0, sizeof(node_key));
    lantern_shutdown(client);
    return (err == LANTERN_CLIENT_OK) ? LANTERN_CLIENT_ERR_RUNTIME : err;
}


/**
 * @brief Shutdown and clean up the Lantern client.
 *
 * Stops all services and releases all resources. After this call, the client
 * struct is zeroed and must be re-initialized before reuse.
 *
 * Shutdown order (reverse of initialization):
 * 1. Validator and ping services
 * 2. HTTP and metrics servers
 * 3. Networking (gossipsub, request/response, libp2p)
 * 4. State and fork choice
 * 5. Genesis artifacts and configuration
 *
 * @param client  Client to shutdown (may be NULL, which is a no-op)
 *
 * @note Thread safety: Must be called from a single thread after all other
 *       threads have stopped using the client. Destroys all internal locks.
 */
void lantern_shutdown(struct lantern_client *client)
{
    if (!client)
    {
        return;
    }

    shutdown_validator_and_keys(client);
    shutdown_http_and_metrics(client);
    shutdown_network_services(client);
    shutdown_peer_tracking(client);
    shutdown_validator_lock(client);
    shutdown_pending_blocks(client);
    shutdown_strings_and_lists(client);
    shutdown_genesis_and_network(client);
    shutdown_state_and_runtime(client);
}
