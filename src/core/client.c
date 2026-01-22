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
#include <time.h>

#if defined(_WIN32)
#include <windows.h>
#else
#include <sys/time.h>
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
static const size_t LANTERN_AGG_PROOF_CACHE_LIMIT = 4096u;

static void agg_proof_cache_init(struct lantern_agg_proof_cache *cache) {
    if (!cache) {
        return;
    }
    cache->entries = NULL;
    cache->length = 0;
    cache->capacity = 0;
}

static void agg_proof_cache_reset(struct lantern_agg_proof_cache *cache) {
    if (!cache) {
        return;
    }
    if (cache->entries) {
        for (size_t i = 0; i < cache->length; ++i) {
            lantern_aggregated_signature_proof_reset(&cache->entries[i].proof);
        }
    }
    free(cache->entries);
    cache->entries = NULL;
    cache->length = 0;
    cache->capacity = 0;
}

static bool agg_proof_cache_entry_equals(
    const struct lantern_agg_proof_cache_entry *entry,
    const LanternRoot *data_root,
    const LanternAggregatedSignatureProof *proof) {
    if (!entry || !data_root || !proof) {
        return false;
    }
    if (memcmp(entry->data_root.bytes, data_root->bytes, LANTERN_ROOT_SIZE) != 0) {
        return false;
    }
    if (entry->proof.participants.bit_length != proof->participants.bit_length) {
        return false;
    }
    size_t bits = proof->participants.bit_length;
    size_t bytes = (bits + 7u) / 8u;
    if (bytes > 0) {
        if (!entry->proof.participants.bytes || !proof->participants.bytes) {
            return false;
        }
        if (memcmp(entry->proof.participants.bytes, proof->participants.bytes, bytes) != 0) {
            return false;
        }
    }
    if (entry->proof.proof_data.length != proof->proof_data.length) {
        return false;
    }
    if (proof->proof_data.length > 0) {
        if (!entry->proof.proof_data.data || !proof->proof_data.data) {
            return false;
        }
        if (memcmp(entry->proof.proof_data.data, proof->proof_data.data, proof->proof_data.length) != 0) {
            return false;
        }
    }
    return true;
}

static void agg_proof_cache_evict_oldest(struct lantern_agg_proof_cache *cache) {
    if (!cache || cache->length == 0 || !cache->entries) {
        return;
    }
    lantern_aggregated_signature_proof_reset(&cache->entries[0].proof);
    if (cache->length > 1) {
        memmove(cache->entries, cache->entries + 1, (cache->length - 1) * sizeof(*cache->entries));
    }
    cache->length -= 1u;
}

int lantern_client_agg_proof_cache_add(
    struct lantern_client *client,
    const LanternRoot *data_root,
    const LanternAggregatedSignatureProof *proof) {
    if (!client || !data_root || !proof) {
        return -1;
    }
    if (proof->participants.bit_length == 0 || proof->proof_data.length == 0) {
        return -1;
    }
    struct lantern_agg_proof_cache *cache = &client->agg_proof_cache;
    for (size_t i = 0; i < cache->length; ++i) {
        if (agg_proof_cache_entry_equals(&cache->entries[i], data_root, proof)) {
            return 0;
        }
    }

    if (cache->length >= LANTERN_AGG_PROOF_CACHE_LIMIT) {
        agg_proof_cache_evict_oldest(cache);
    }

    if (cache->length >= cache->capacity) {
        size_t desired = cache->capacity == 0 ? 8u : cache->capacity * 2u;
        if (desired > LANTERN_AGG_PROOF_CACHE_LIMIT) {
            desired = LANTERN_AGG_PROOF_CACHE_LIMIT;
        }
        if (desired <= cache->capacity) {
            return -1;
        }
        struct lantern_agg_proof_cache_entry *entries =
            realloc(cache->entries, desired * sizeof(*entries));
        if (!entries) {
            return -1;
        }
        cache->entries = entries;
        cache->capacity = desired;
    }

    struct lantern_agg_proof_cache_entry *entry = &cache->entries[cache->length];
    entry->data_root = *data_root;
    lantern_aggregated_signature_proof_init(&entry->proof);
    if (lantern_aggregated_signature_proof_copy(&entry->proof, proof) != 0) {
        lantern_aggregated_signature_proof_reset(&entry->proof);
        return -1;
    }
    cache->length += 1u;
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
    options->xmss_key_dir = NULL;
    options->xmss_public_path = NULL;
    options->xmss_secret_path = NULL;
    options->xmss_public_template = NULL;
    options->xmss_secret_template = NULL;
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
    agg_proof_cache_init(&client->agg_proof_cache);
    lean_metrics_reset();
    client->state_lock_initialized = false;
    lantern_fork_choice_init(&client->fork_choice);
    client->has_fork_choice = false;
    client->dialer_thread_started = false;
    client->dialer_stop_flag = 1;
    client->ping_thread_started = false;
    client->ping_stop_flag = 1;
    pending_block_list_init(&client->pending_blocks);
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
 * @brief Attempt genesis creation from an SSZ state snapshot.
 *
 * Decodes the serialized genesis state if provided in the configuration.
 *
 * @param client  Client with loaded genesis artifacts
 *
 * @return true on success, false if snapshot is missing or decode fails
 *
 * @note Thread safety: Must run before concurrent access to the state.
 */
static bool client_try_genesis_from_ssz(struct lantern_client *client)
{
    if (!client->genesis.state_bytes || client->genesis.state_size == 0)
    {
        return false;
    }

    if (lantern_ssz_decode_state(
            &client->state,
            client->genesis.state_bytes,
            client->genesis.state_size)
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
 * explicit pubkey array or SSZ snapshot is unavailable.
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
    if (lantern_state_prepare_validator_votes(
            &client->state,
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


/**
 * @brief Build genesis state using the available artifact priority order.
 *
 * Tries embedded pubkeys first, then SSZ snapshot, and finally the validator
 * registry. On success, finalizes validator vote structures.
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

    if (client_try_genesis_from_ssz(client))
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
 * @param loaded_from_storage  Optional output flag indicating storage load
 *
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_STORAGE on storage I/O failure
 * @return LANTERN_CLIENT_ERR_GENESIS on genesis construction failure
 *
 * @note Thread safety: Must be called before any concurrent access.
 */
static lantern_client_error client_load_or_build_state(
    struct lantern_client *client,
    bool *loaded_from_storage)
{
    bool from_storage = false;
    int storage_state_rc = lantern_storage_load_state(client->data_dir, &client->state);
    if (storage_state_rc == 0)
    {
        client->has_state = true;
        from_storage = true;
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
        if (client_generate_state_from_genesis(client) != LANTERN_CLIENT_OK)
        {
            return LANTERN_CLIENT_ERR_GENESIS;
        }
    }

    if (client->has_state)
    {
        int votes_rc = lantern_storage_load_votes(client->data_dir, &client->state);
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
        if (lantern_storage_save_votes(client->data_dir, &client->state) != 0)
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
    struct lantern_gossipsub_config gossip_cfg = {
        .host = client->network.host,
        .devnet = client->devnet,
    };
    lantern_gossipsub_service_set_block_handler(&client->gossip, gossip_block_handler, client);
    lantern_gossipsub_service_set_vote_handler(&client->gossip, gossip_vote_handler, client);
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
            client->assigned_validators->enr.sequence)
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
            pthread_mutex_unlock(&client->status_lock);
        }
        else
        {
            free(client->peer_status_entries);
            client->peer_status_entries = NULL;
            client->peer_status_count = 0;
            client->peer_status_capacity = 0;
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
    if (client->has_state)
    {
        lantern_state_reset(&client->state);
        client->has_state = false;
    }
    else
    {
        lantern_state_reset(&client->state);
    }
    agg_proof_cache_reset(&client->agg_proof_cache);
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

    err = client_load_or_build_state(client, NULL);
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


/**
 * @brief Get the count of local validators.
 *
 * Returns the number of validators that this client is responsible for
 * managing (proposing blocks, creating attestations).
 *
 * @param client  Client to query
 *
 * @return Number of local validators, or 0 if client is NULL
 *
 * @note Thread safety: None required - reads immutable field after init.
 */
size_t lantern_client_local_validator_count(const struct lantern_client *client)
{
    if (!client)
    {
        return 0;
    }
    return client->local_validator_count;
}


/**
 * @brief Get a local validator by index.
 *
 * Returns a pointer to the local validator at the specified index.
 * The returned pointer is valid for the lifetime of the client.
 *
 * @param client  Client to query
 * @param index   Index of the local validator (0 to count-1)
 *
 * @return Pointer to the validator, or NULL if client is NULL or index is out of range
 *
 * @note Thread safety: None required - returns pointer to immutable data.
 */
const struct lantern_local_validator *lantern_client_local_validator(
    const struct lantern_client *client,
    size_t index)
{
    if (!client || index >= client->local_validator_count)
    {
        return NULL;
    }
    return &client->local_validators[index];
}
