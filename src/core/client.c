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
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "internal/yaml_parser.h"
#include "client_internal.h"
#include "lantern/consensus/containers.h"
#include "lantern/consensus/fork_choice.h"
#include "lantern/consensus/hash.h"
#include "lantern/consensus/signature.h"
#include "lantern/consensus/slot_clock.h"
#include "lantern/consensus/ssz.h"
#include "lantern/consensus/state.h"
#include "lantern/crypto/xmss.h"
#include "lantern/encoding/snappy.h"
#include "lantern/http/client.h"
#include "lantern/http/server.h"
#include "lantern/metrics/lean_metrics.h"
#include "lantern/networking/gossip.h"
#include "lantern/networking/messages.h"
#include "lantern/networking/reqresp_service.h"
#include "lantern/storage/storage.h"
#include "lantern/support/log.h"
#include "lantern/support/secure_mem.h"
#include "lantern/support/strings.h"
#include "lantern/support/time.h"

_Static_assert(
    sizeof(LanternValidator)
        == (2u * LANTERN_VALIDATOR_PUBKEY_SIZE) + sizeof(LanternValidatorIndex),
    "LanternValidator registry entries must not contain padding");

static const size_t NODE_PRIVATE_KEY_SIZE = 32u;
static const size_t BOOTNODE_LINE_MAX_LEN = 2048u;
static const size_t CHECKPOINT_SYNC_MAX_RESPONSE_BYTES =
    512u
    + (LANTERN_HISTORICAL_ROOTS_LIMIT * 32u)
    + (LANTERN_HISTORICAL_ROOTS_LIMIT / 8u)
    + (LANTERN_VALIDATOR_REGISTRY_LIMIT * 52u)
    + (LANTERN_HISTORICAL_ROOTS_LIMIT * 32u)
    + (LANTERN_JUSTIFICATION_VALIDATORS_LIMIT / 8u);
static const size_t CHECKPOINT_SYNC_MAX_BLOCK_RESPONSE_BYTES = 64u * 1024u * 1024u;
static const size_t LANTERN_DEFAULT_ATTESTATION_COMMITTEE_COUNT = 1u;
static const uint64_t LANTERN_CHECKPOINT_SYNC_STALE_PERSISTED_STATE_SLOT_THRESHOLD = 2u * 32u;
static const char CHECKPOINT_SYNC_FINALIZED_STATE_PATH[] = "/lean/v0/states/finalized";
static const char CHECKPOINT_SYNC_FINALIZED_BLOCK_PATH[] = "/lean/v0/blocks/finalized";

static void log_aggregated_payload_interval_transition(
    const struct lantern_client *client,
    const char *context,
    uint64_t interval,
    uint64_t phase,
    size_t new_before,
    size_t known_before,
    size_t promoted) {
    if (!client || !context) {
        return;
    }
    struct lantern_log_metadata meta = {.validator = client->node_id};
    lantern_log_info(
        "forkchoice",
        &meta,
        "aggregated payload transition context=%s interval=%" PRIu64 " phase=%" PRIu64
        " new_before=%zu known_before=%zu promoted=%zu new_after=%zu known_after=%zu",
        context,
        interval,
        phase,
        new_before,
        known_before,
        promoted,
        client->store.new_aggregated_payloads.length,
        client->store.known_aggregated_payloads.length);
}

static int client_resolve_gossip_fork_digest(
    const struct lantern_client *client,
    uint8_t out_fork_digest[4])
{
    if (!client || !out_fork_digest || !client->genesis.enrs.records)
    {
        return -1;
    }

    bool have_digest = false;
    for (size_t i = 0; i < client->genesis.enrs.count; ++i)
    {
        struct lantern_enr_eth2_data eth2;
        if (lantern_enr_record_eth2(&client->genesis.enrs.records[i], &eth2) != 0)
        {
            continue;
        }
        if (!have_digest)
        {
            memcpy(out_fork_digest, eth2.fork_digest, 4u);
            have_digest = true;
            continue;
        }
        if (memcmp(out_fork_digest, eth2.fork_digest, 4u) != 0)
        {
            return -1;
        }
    }

    return have_digest ? 0 : -1;
}

bool lantern_client_persisted_state_is_stale_for_checkpoint_sync(
    const LanternState *persisted_state,
    uint64_t genesis_time,
    uint64_t now_seconds,
    uint64_t *out_expected_current_slot,
    uint64_t *out_gap) {
    uint64_t expected_current_slot = 0u;
    uint64_t gap = 0u;

    if (out_expected_current_slot) {
        *out_expected_current_slot = 0u;
    }
    if (out_gap) {
        *out_gap = 0u;
    }
    if (!persisted_state) {
        return false;
    }

    if (now_seconds > genesis_time) {
        expected_current_slot = (now_seconds - genesis_time) / LANTERN_SECONDS_PER_SLOT;
    }
    if (expected_current_slot > persisted_state->slot) {
        gap = expected_current_slot - persisted_state->slot;
    }

    if (out_expected_current_slot) {
        *out_expected_current_slot = expected_current_slot;
    }
    if (out_gap) {
        *out_gap = gap;
    }

    return gap > LANTERN_CHECKPOINT_SYNC_STALE_PERSISTED_STATE_SLOT_THRESHOLD;
}

static void sync_aggregated_payload_pools_after_time_advance(
    struct lantern_client *client,
    uint64_t previous_intervals,
    bool has_proposal) {
    if (!client || client->store.block_len == 0u) {
        return;
    }
    if (client->store.time_intervals <= previous_intervals) {
        return;
    }
    for (uint64_t step = previous_intervals + 1u;
         step <= client->store.time_intervals;
         ++step) {
        uint64_t interval_index = step % LANTERN_INTERVALS_PER_SLOT;
        bool step_has_proposal = has_proposal && (step == client->store.time_intervals);
        if (interval_index == LANTERN_DUTY_PHASE_SAFE_TARGET) {
            log_aggregated_payload_interval_transition(
                client,
                "safe_target",
                step,
                interval_index,
                client->store.new_aggregated_payloads.length,
                client->store.known_aggregated_payloads.length,
                0u);
        } else if (interval_index == LANTERN_DUTY_PHASE_VOTE_ACCEPT
            || (interval_index == LANTERN_DUTY_PHASE_PROPOSAL && step_has_proposal)) {
            size_t new_before = client->store.new_aggregated_payloads.length;
            size_t known_before = client->store.known_aggregated_payloads.length;
            size_t promoted = lantern_store_promote_new_aggregated_payloads(&client->store);
            if (promoted > 0u && lantern_fork_choice_accept_new_aggregated_payloads(&client->store) != 0) {
                lantern_log_warn(
                    "forkchoice",
                    &(struct lantern_log_metadata){.validator = client->node_id},
                    "failed to recompute head after aggregated payload promotion");
            }
            log_aggregated_payload_interval_transition(
                client,
                interval_index == LANTERN_DUTY_PHASE_VOTE_ACCEPT
                    ? "accept_new"
                    : "proposal_accept_new",
                step,
                interval_index,
                new_before,
                known_before,
                promoted);
        }
    }
}

static bool interval_range_first_with_phase(
    uint64_t start,
    uint64_t end,
    uint64_t phase,
    uint64_t *out_interval) {
    if (phase >= LANTERN_INTERVALS_PER_SLOT || start > end) {
        return false;
    }
    uint64_t distance = end - start;
    uint64_t remainder = start % LANTERN_INTERVALS_PER_SLOT;
    uint64_t offset =
        (phase + LANTERN_INTERVALS_PER_SLOT - remainder) % LANTERN_INTERVALS_PER_SLOT;
    if (offset > distance) {
        return false;
    }
    if (out_interval) {
        *out_interval = start + offset;
    }
    return true;
}

static bool interval_range_last_with_phase(
    uint64_t start,
    uint64_t end,
    uint64_t phase,
    uint64_t *out_interval) {
    if (phase >= LANTERN_INTERVALS_PER_SLOT || start > end) {
        return false;
    }
    uint64_t distance = end - start;
    uint64_t remainder = end % LANTERN_INTERVALS_PER_SLOT;
    uint64_t offset =
        (remainder + LANTERN_INTERVALS_PER_SLOT - phase) % LANTERN_INTERVALS_PER_SLOT;
    if (offset > distance) {
        return false;
    }
    if (out_interval) {
        *out_interval = end - offset;
    }
    return true;
}

int lantern_client_tick_fork_choice_interval_locked(
    struct lantern_client *client,
    bool has_proposal) {
    if (!client || client->store.block_len == 0u) {
        return -1;
    }

    uint64_t previous_intervals = client->store.time_intervals;
    uint64_t next_interval = previous_intervals + 1u;
    if (next_interval < previous_intervals) {
        return -1;
    }

    double tick_start_seconds = lantern_time_now_seconds();
    int rc = lantern_fork_choice_advance_to(&client->store, next_interval, has_proposal);
    if (rc != 0) {
        return rc;
    }
    if (client->store.time_intervals != next_interval) {
        return -1;
    }

    if (tick_start_seconds > 0.0) {
        if (client->last_tick_interval_started_seconds > 0.0
            && tick_start_seconds >= client->last_tick_interval_started_seconds) {
            lean_metrics_record_tick_interval_duration(
                tick_start_seconds - client->last_tick_interval_started_seconds);
        }
        client->last_tick_interval_started_seconds = tick_start_seconds;
    }

    sync_aggregated_payload_pools_after_time_advance(client, previous_intervals, has_proposal);
    return 0;
}

int lantern_client_skip_fork_choice_intervals_locked(
    struct lantern_client *client,
    uint64_t target_interval) {
    if (!client || client->store.block_len == 0u) {
        return -1;
    }
    if (target_interval < client->store.time_intervals) {
        return -1;
    }
    uint64_t previous_intervals = client->store.time_intervals;
    client->store.time_intervals = target_interval;
    if (target_interval == previous_intervals) {
        return 0;
    }

    uint64_t start_interval = previous_intervals + 1u;
    uint64_t first_accept_interval = 0u;
    uint64_t last_safe_interval = 0u;
    bool has_accept = interval_range_first_with_phase(
        start_interval,
        target_interval,
        LANTERN_DUTY_PHASE_VOTE_ACCEPT,
        &first_accept_interval);
    bool has_safe = interval_range_last_with_phase(
        start_interval,
        target_interval,
        LANTERN_DUTY_PHASE_SAFE_TARGET,
        &last_safe_interval);

    if (has_safe && (!has_accept || last_safe_interval < first_accept_interval)) {
        size_t new_before = client->store.new_aggregated_payloads.length;
        size_t known_before = client->store.known_aggregated_payloads.length;
        if (lantern_fork_choice_update_safe_target(&client->store) != 0) {
            return -1;
        }
        log_aggregated_payload_interval_transition(
            client,
            "skip_safe_target",
            last_safe_interval,
            last_safe_interval % LANTERN_INTERVALS_PER_SLOT,
            new_before,
            known_before,
            0u);
    }

    if (has_accept) {
        size_t new_before = client->store.new_aggregated_payloads.length;
        size_t known_before = client->store.known_aggregated_payloads.length;
        if (lantern_fork_choice_accept_new_aggregated_payloads(&client->store) != 0) {
            return -1;
        }
        size_t promoted = lantern_store_promote_new_aggregated_payloads(&client->store);
        if (promoted > 0u && lantern_fork_choice_accept_new_aggregated_payloads(&client->store) != 0) {
            return -1;
        }
        log_aggregated_payload_interval_transition(
            client,
            "skip_accept_new",
            first_accept_interval,
            first_accept_interval % LANTERN_INTERVALS_PER_SLOT,
            new_before,
            known_before,
            promoted);
    }

    if (has_safe && has_accept && last_safe_interval > first_accept_interval) {
        size_t new_before = client->store.new_aggregated_payloads.length;
        size_t known_before = client->store.known_aggregated_payloads.length;
        if (lantern_fork_choice_update_safe_target(&client->store) != 0) {
            return -1;
        }
        log_aggregated_payload_interval_transition(
            client,
            "skip_safe_target",
            last_safe_interval,
            last_safe_interval % LANTERN_INTERVALS_PER_SLOT,
            new_before,
            known_before,
            0u);
    }
    return 0;
}

int lantern_client_advance_fork_choice_time_locked(
    struct lantern_client *client,
    uint64_t now_milliseconds,
    bool has_proposal) {
    if (!client || client->store.block_len == 0u) {
        return -1;
    }

    uint64_t previous_intervals = client->store.time_intervals;
    uint64_t target_interval = 0u;
    int target_rc = lantern_slot_clock_total_interval(
        client->state.config.genesis_time,
        now_milliseconds,
        &target_interval);
    if (target_rc < 0) {
        return -1;
    }
    if (target_rc == 0
        && target_interval > previous_intervals
        && (target_interval - previous_intervals) > LANTERN_INTERVALS_PER_SLOT)
    {
        uint64_t skip_to_interval =
            target_interval - LANTERN_INTERVALS_PER_SLOT;
        if (lantern_client_skip_fork_choice_intervals_locked(client, skip_to_interval) != 0) {
            return -1;
        }
        previous_intervals = client->store.time_intervals;
    }

    if (target_rc > 0) {
        return 0;
    }
    int rc = lantern_fork_choice_advance_to(&client->store, target_interval, has_proposal);
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
extern int populate_local_validators(struct lantern_client *client);


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

    memset(options, 0, sizeof(*options));
    options->data_dir = LANTERN_DEFAULT_DATA_DIR;
    options->genesis_config_path = LANTERN_DEFAULT_GENESIS_CONFIG;
    options->validator_config_dir = LANTERN_DEFAULT_VALIDATOR_CONFIG_DIR;
    options->nodes_path = LANTERN_DEFAULT_NODES_FILE;
    options->node_id = LANTERN_DEFAULT_NODE_ID;
    options->listen_address = LANTERN_DEFAULT_LISTEN_ADDR;
    options->http_port = LANTERN_DEFAULT_HTTP_PORT;
    options->metrics_port = LANTERN_DEFAULT_METRICS_PORT;
    options->devnet = LANTERN_DEFAULT_DEVNET;
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
    free(options->aggregate_subnet_ids);
    options->aggregate_subnet_ids = NULL;
    options->aggregate_subnet_id_count = 0;
    options->aggregate_subnet_id_capacity = 0;
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

lantern_client_error lantern_client_options_add_aggregate_subnet_id(
    struct lantern_client_options *options,
    size_t subnet_id)
{
    if (!options)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    if (options->aggregate_subnet_id_count == options->aggregate_subnet_id_capacity)
    {
        if (options->aggregate_subnet_id_capacity > SIZE_MAX / 2u)
        {
            return LANTERN_CLIENT_ERR_ALLOC;
        }
        size_t next_capacity =
            options->aggregate_subnet_id_capacity == 0
                ? 4u
                : options->aggregate_subnet_id_capacity * 2u;
        if (next_capacity < options->aggregate_subnet_id_count
            || next_capacity > SIZE_MAX / sizeof(*options->aggregate_subnet_ids))
        {
            return LANTERN_CLIENT_ERR_ALLOC;
        }
        size_t *next = realloc(
            options->aggregate_subnet_ids,
            next_capacity * sizeof(*next));
        if (!next)
        {
            return LANTERN_CLIENT_ERR_ALLOC;
        }
        options->aggregate_subnet_ids = next;
        options->aggregate_subnet_id_capacity = next_capacity;
    }
    options->aggregate_subnet_ids[options->aggregate_subnet_id_count++] = subnet_id;
    return LANTERN_CLIENT_OK;
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
 * Zeroes all fields, establishes server descriptor sentinels and Store atomics,
 * and leaves background services stopped. This prepares the struct for
 * subsequent initialization steps.
 *
 * @param client  Client instance to reset (must not be NULL)
 *
 * @note Thread safety: Caller must ensure exclusive access; intended for
 *       single-threaded initialization only.
 */
static void client_reset_base(struct lantern_client *client)
{
    memset(client, 0, sizeof(*client));
    double now_seconds = lantern_time_now_seconds();
    client->start_time_seconds = now_seconds > 0.0 ? (uint64_t)now_seconds : 0u;
    lantern_metrics_server_init(&client->metrics_server);
    lantern_http_server_init(&client->http_server);
    lantern_store_init(&client->store);
    lean_metrics_reset();
    client->block_proposal_stop = true;
    client->timing_stop_flag = 1;
    client->dialer_stop_flag = 1;
    client->block_import_stop = true;
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
    if (options->attestation_committee_count_override > 0u)
    {
        client->debug_attestation_committee_count =
            (size_t)options->attestation_committee_count_override;
    }
    if (options->aggregate_subnet_id_count > 0)
    {
        size_t bytes =
            options->aggregate_subnet_id_count * sizeof(*client->aggregate_subnet_ids);
        if (bytes / sizeof(*client->aggregate_subnet_ids) != options->aggregate_subnet_id_count)
        {
            return LANTERN_CLIENT_ERR_ALLOC;
        }
        client->aggregate_subnet_ids = malloc(bytes);
        if (!client->aggregate_subnet_ids)
        {
            return LANTERN_CLIENT_ERR_ALLOC;
        }
        memcpy(
            client->aggregate_subnet_ids,
            options->aggregate_subnet_ids,
            bytes);
        client->aggregate_subnet_id_count = options->aggregate_subnet_id_count;
    }
    return LANTERN_CLIENT_OK;
}

size_t lantern_client_attestation_committee_count(const struct lantern_client *client)
{
    if (!client)
    {
        return LANTERN_DEFAULT_ATTESTATION_COMMITTEE_COUNT;
    }
    if (client->debug_attestation_committee_count > 0)
    {
        return client->debug_attestation_committee_count;
    }
    if (client->genesis.chain_config.attestation_committee_count > 0)
    {
        return (size_t)client->genesis.chain_config.attestation_committee_count;
    }
    return LANTERN_DEFAULT_ATTESTATION_COMMITTEE_COUNT;
}

int lantern_client_aggregation_subnet_id(
    const struct lantern_client *client,
    size_t *out_subnet_id)
{
    if (!client || !out_subnet_id)
    {
        return -1;
    }

    const struct lantern_validator_config_entry *entry = client->assigned_validators;
    if (entry && entry->enr.is_aggregator && entry->has_subnet)
    {
        if (entry->subnet > (uint64_t)SIZE_MAX)
        {
            return -1;
        }
        *out_subnet_id = (size_t)entry->subnet;
        return 0;
    }

    if (client->local_validators && client->local_validator_count > 0)
    {
        return lantern_validator_index_compute_subnet_id(
            client->local_validators[0].global_index,
            lantern_client_attestation_committee_count(client),
            out_subnet_id);
    }
    if (entry && entry->indices_len > 0)
    {
        return lantern_validator_index_compute_subnet_id(
            entry->indices[0],
            lantern_client_attestation_committee_count(client),
            out_subnet_id);
    }
    *out_subnet_id = client->gossip.attestation_subnet_id;
    return 0;
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
            "annotated_validators.yaml assignment mapping invalid or incomplete");
        return LANTERN_CLIENT_ERR_GENESIS;
    }

    return LANTERN_CLIENT_OK;
}


/**
 * @brief Attempt genesis creation using the embedded validator registry.
 *
 * Builds the initial state from validators included in the chain configuration.
 *
 * @param client  Client with loaded chain configuration
 *
 * @return true on success, false if pubkeys are missing or initialization fails
 *
 * @note Thread safety: Must run before concurrent access to the state.
 */
static bool client_try_genesis_from_pubkeys(struct lantern_client *client)
{
    if (!client->genesis.chain_config.validators
        || client->genesis.chain_config.validator_count == 0
        || client->genesis.chain_config.validator_count > SIZE_MAX)
    {
        return false;
    }

    size_t vcount = (size_t)client->genesis.chain_config.validator_count;
    if (lantern_state_generate_genesis(
            &client->state, client->genesis.chain_config.genesis_time, vcount)
        != 0)
    {
        return false;
    }

    memcpy(
        client->state.validators,
        client->genesis.chain_config.validators,
        vcount * sizeof(*client->state.validators));
    return true;
}


/* ============================================================================
 * Checkpoint Sync Helpers
 * ============================================================================ */

static char *checkpoint_sync_endpoint_url(const char *checkpoint_sync_url, const char *endpoint_path)
{
    if (!checkpoint_sync_url || checkpoint_sync_url[0] == '\0'
        || !endpoint_path || endpoint_path[0] != '/')
    {
        return NULL;
    }

    size_t url_len = strlen(checkpoint_sync_url);
    size_t endpoint_len = strlen(endpoint_path);
    while (url_len > 0u && checkpoint_sync_url[url_len - 1u] == '/')
    {
        --url_len;
    }

    const char *known_endpoints[] = {
        CHECKPOINT_SYNC_FINALIZED_STATE_PATH,
        CHECKPOINT_SYNC_FINALIZED_BLOCK_PATH,
    };

    for (size_t i = 0; i < sizeof(known_endpoints) / sizeof(known_endpoints[0]); ++i)
    {
        size_t known_len = strlen(known_endpoints[i]);
        if (url_len < known_len
            || strncmp(
                   checkpoint_sync_url + url_len - known_len,
                   known_endpoints[i],
                   known_len)
                   != 0)
        {
            continue;
        }
        url_len -= known_len;
        break;
    }

    size_t out_len = url_len + endpoint_len;
    char *out = malloc(out_len + 1u);
    if (!out)
    {
        return NULL;
    }
    memcpy(out, checkpoint_sync_url, url_len);
    memcpy(out + url_len, endpoint_path, endpoint_len);
    out[out_len] = '\0';
    return out;
}

static lantern_client_error client_fetch_checkpoint_bytes(
    struct lantern_client *client,
    const char *checkpoint_sync_url,
    const char *endpoint_path,
    size_t max_response_bytes,
    const char *label,
    struct lantern_http_fetch_result *out_result)
{
    if (!client || !checkpoint_sync_url || !endpoint_path || !label || !out_result)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    memset(out_result, 0, sizeof(*out_result));
    char *url = checkpoint_sync_endpoint_url(checkpoint_sync_url, endpoint_path);
    if (!url)
    {
        return LANTERN_CLIENT_ERR_NETWORK;
    }

    struct lantern_log_metadata meta = {.validator = client->node_id};
    lantern_log_info("checkpoint_sync", &meta, "fetching finalized checkpoint %s from %s", label, url);
    int fetch_rc = lantern_http_get_bytes(
        url,
        "application/octet-stream",
        max_response_bytes,
        out_result);
    if (fetch_rc != 0)
    {
        if (fetch_rc == LANTERN_HTTP_CLIENT_STATUS_ERROR)
        {
            lantern_log_error(
                "checkpoint_sync",
                &meta,
                "checkpoint %s endpoint returned HTTP %d",
                label,
                out_result->status_code);
        }
        else
        {
            lantern_log_error("checkpoint_sync", &meta, "failed to fetch checkpoint %s", label);
        }
        lantern_http_fetch_result_reset(out_result);
        free(url);
        return LANTERN_CLIENT_ERR_NETWORK;
    }
    free(url);

    if (!out_result->body || out_result->body_len == 0)
    {
        lantern_http_fetch_result_reset(out_result);
        lantern_log_error("checkpoint_sync", &meta, "checkpoint %s endpoint returned no data", label);
        return LANTERN_CLIENT_ERR_NETWORK;
    }
    return LANTERN_CLIENT_OK;
}

static lantern_client_error client_fetch_checkpoint_anchor_block(
    struct lantern_client *client,
    const char *checkpoint_sync_url,
    LanternSignedBlock *out_block,
    LanternRoot *out_root)
{
    if (!client || !checkpoint_sync_url || !out_block || !out_root)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    struct lantern_http_fetch_result fetch_result;
    lantern_client_error fetch_rc = client_fetch_checkpoint_bytes(
        client,
        checkpoint_sync_url,
        CHECKPOINT_SYNC_FINALIZED_BLOCK_PATH,
        CHECKPOINT_SYNC_MAX_BLOCK_RESPONSE_BYTES,
        "block",
        &fetch_result);
    if (fetch_rc != LANTERN_CLIENT_OK)
    {
        return fetch_rc;
    }

    struct lantern_log_metadata meta = {.validator = client->node_id};
    if (lantern_ssz_decode_signed_block(out_block, fetch_result.body, fetch_result.body_len)
        != SSZ_SUCCESS)
    {
        lantern_http_fetch_result_reset(&fetch_result);
        lantern_log_error(
            "checkpoint_sync",
            &meta,
            "failed to decode checkpoint block SSZ (bytes=%zu)",
            fetch_result.body_len);
        return LANTERN_CLIENT_ERR_GENESIS;
    }
    lantern_http_fetch_result_reset(&fetch_result);

    if (lantern_hash_tree_root_block(&out_block->block, out_root) != SSZ_SUCCESS)
    {
        lantern_log_error(
            "checkpoint_sync",
            &meta,
            "failed to compute checkpoint block root");
        return LANTERN_CLIENT_ERR_GENESIS;
    }

    return LANTERN_CLIENT_OK;
}

static bool checkpoint_anchor_block_matches_state_header(
    const LanternSignedBlock *anchor_block,
    const LanternState *state,
    const LanternRoot *state_root)
{
    if (!anchor_block || !state || !state_root)
    {
        return false;
    }

    const LanternBlockHeader *header = &state->latest_block_header;
    if (anchor_block->block.slot != header->slot
        || anchor_block->block.proposer_index != header->proposer_index
        || memcmp(
               anchor_block->block.parent_root.bytes,
               header->parent_root.bytes,
               LANTERN_ROOT_SIZE)
            != 0)
    {
        return false;
    }

    if (!lantern_root_is_zero(&header->state_root)
        && memcmp(header->state_root.bytes, state_root->bytes, LANTERN_ROOT_SIZE) != 0)
    {
        return false;
    }

    LanternRoot body_root;
    if (lantern_hash_tree_root_block_body(&anchor_block->block.body, &body_root) != SSZ_SUCCESS)
    {
        return false;
    }
    return memcmp(body_root.bytes, header->body_root.bytes, LANTERN_ROOT_SIZE) == 0;
}

int lantern_client_validate_state_validator_pubkeys(
    const struct lantern_client *client,
    const LanternState *state,
    const char *log_component)
{
    if (!client || !state)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    const char *component =
        (log_component && log_component[0] != '\0') ? log_component : "client";
    const struct lantern_log_metadata meta = {.validator = client->node_id};
    const struct lantern_chain_config *config = &client->genesis.chain_config;
    if (!config->validators
        || config->validator_count == 0
        || config->validator_count > SIZE_MAX)
    {
        lantern_log_error(
            component,
            &meta,
            "local genesis validator pubkeys unavailable for state validation");
        return LANTERN_CLIENT_ERR_GENESIS;
    }

    size_t expected_count = (size_t)config->validator_count;
    if (!state->validators
        || state->validator_count != expected_count)
    {
        lantern_log_error(
            component,
            &meta,
            "state validator count mismatch state=%zu local=%zu",
            state->validator_count,
            expected_count);
        return LANTERN_CLIENT_ERR_GENESIS;
    }

    if (memcmp(
            state->validators,
            config->validators,
            expected_count * sizeof(*state->validators))
        != 0)
    {
        lantern_log_error(component, &meta, "state validator registry mismatch");
        return LANTERN_CLIENT_ERR_GENESIS;
    }

    return LANTERN_CLIENT_OK;
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
    LanternSignedBlock anchor_signed_block;
    lantern_signed_block_init(&anchor_signed_block);
    LanternRoot anchor_root = {0};
    lantern_client_error block_rc = client_fetch_checkpoint_anchor_block(
        client,
        checkpoint_sync_url,
        &anchor_signed_block,
        &anchor_root);
    if (block_rc != LANTERN_CLIENT_OK)
    {
        lantern_signed_block_reset(&anchor_signed_block);
        return block_rc;
    }

    struct lantern_http_fetch_result fetch_result;
    lantern_client_error fetch_rc = client_fetch_checkpoint_bytes(
        client,
        checkpoint_sync_url,
        CHECKPOINT_SYNC_FINALIZED_STATE_PATH,
        CHECKPOINT_SYNC_MAX_RESPONSE_BYTES,
        "state",
        &fetch_result);
    if (fetch_rc != LANTERN_CLIENT_OK)
    {
        lantern_signed_block_reset(&anchor_signed_block);
        return fetch_rc;
    }

    LanternState decoded;
    lantern_state_init(&decoded);
    lantern_client_error result = LANTERN_CLIENT_OK;

    if (lantern_ssz_decode_state(&decoded, fetch_result.body, fetch_result.body_len) != SSZ_SUCCESS)
    {
        lantern_log_error(
            "checkpoint_sync",
            &meta,
            "failed to decode checkpoint state SSZ (bytes=%zu)",
            fetch_result.body_len);
        result = LANTERN_CLIENT_ERR_GENESIS;
        goto cleanup;
    }

    if (decoded.validator_count == 0)
    {
        lantern_log_error(
            "checkpoint_sync",
            &meta,
            "checkpoint state validator metadata invalid decoded=%zu",
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

    int pubkey_rc = lantern_client_validate_state_validator_pubkeys(
        client,
        &decoded,
        "checkpoint_sync");
    if (pubkey_rc != LANTERN_CLIENT_OK)
    {
        result = pubkey_rc;
        goto cleanup;
    }

    LanternRoot state_root;
    if (lantern_hash_tree_root_state(&decoded, &state_root) != SSZ_SUCCESS)
    {
        lantern_log_error(
            "checkpoint_sync",
            &meta,
            "failed to compute checkpoint state root");
        result = LANTERN_CLIENT_ERR_GENESIS;
        goto cleanup;
    }

    if (memcmp(anchor_signed_block.block.state_root.bytes, state_root.bytes, LANTERN_ROOT_SIZE) != 0)
    {
        char block_state_root_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
        char state_root_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
        format_root_hex(
            &anchor_signed_block.block.state_root,
            block_state_root_hex,
            sizeof(block_state_root_hex));
        format_root_hex(&state_root, state_root_hex, sizeof(state_root_hex));
        lantern_log_error(
            "checkpoint_sync",
            &meta,
            "checkpoint anchor block/state mismatch block_state_root=%s state_root=%s",
            block_state_root_hex[0] ? block_state_root_hex : "0x0",
            state_root_hex[0] ? state_root_hex : "0x0");
        result = LANTERN_CLIENT_ERR_GENESIS;
        goto cleanup;
    }

    if (!checkpoint_anchor_block_matches_state_header(&anchor_signed_block, &decoded, &state_root))
    {
        lantern_log_error(
            "checkpoint_sync",
            &meta,
            "checkpoint anchor block/header mismatch");
        result = LANTERN_CLIENT_ERR_GENESIS;
        goto cleanup;
    }

    char state_root_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    char anchor_root_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    format_root_hex(&state_root, state_root_hex, sizeof(state_root_hex));
    format_root_hex(&anchor_root, anchor_root_hex, sizeof(anchor_root_hex));

    if (!client->data_dir)
    {
        lantern_log_error(
            "storage",
            &meta,
            "checkpoint sync requires a data directory for the anchor block");
        result = LANTERN_CLIENT_ERR_STORAGE;
        goto cleanup;
    }
    if (lantern_storage_store_block_for_root(
            client->data_dir,
            &anchor_root,
            &anchor_signed_block)
        != 0)
    {
        lantern_log_error(
            "storage",
            &meta,
            "failed to persist checkpoint anchor block");
        result = LANTERN_CLIENT_ERR_STORAGE;
        goto cleanup;
    }
    if (lantern_storage_store_state_for_root(
            client->data_dir,
            &anchor_root,
            &decoded)
        != 0)
    {
        lantern_log_error(
            "storage",
            &meta,
            "failed to persist checkpoint anchor state alias");
        result = LANTERN_CLIENT_ERR_STORAGE;
        goto cleanup;
    }

    lantern_state_reset(&client->state);
    client->state = decoded;
    decoded = (LanternState){0};
    lantern_log_info(
        "checkpoint_sync",
        &meta,
        "initialized from checkpoint state slot=%" PRIu64
        " validators=%" PRIu64 " finalized_slot=%" PRIu64 " state_root=%s"
        " anchor_root=%s",
        client->state.slot,
        (uint64_t)client->state.validator_count,
        client->state.latest_finalized.slot,
        state_root_hex[0] ? state_root_hex : "0x0",
        anchor_root_hex[0] ? anchor_root_hex : "0x0");

cleanup:
    lantern_http_fetch_result_reset(&fetch_result);
    lantern_signed_block_reset(&anchor_signed_block);
    lantern_state_reset(&decoded);
    return result;
}

/**
 * @brief Build genesis state using the available artifact priority order.
 *
 * Builds the state from the canonical validator keypairs in the chain config.
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
    if (!client_try_genesis_from_pubkeys(client))
    {
        return LANTERN_CLIENT_ERR_GENESIS;
    }
    return LANTERN_CLIENT_OK;
}


/**
 * @brief Load persisted state, checkpoint state, or construct a genesis state.
 *
 * Reuses fresh persisted state when available. If checkpoint sync is configured
 * and no reusable state exists, checkpoint sync must succeed; genesis bootstrap
 * is only used when checkpoint sync is not configured.
 *
 * @param client               Client whose state is being initialized
 * @param options              Client options (checkpoint sync URL, etc.)
 * @param loaded_from_storage  Optional output flag indicating storage load
 *
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_STORAGE on storage I/O failure
 * @return LANTERN_CLIENT_ERR_GENESIS on genesis construction failure
 * @return negative lantern_client_error when checkpoint sync fails
 *
 * @note Thread safety: Must be called before any concurrent access.
 */
static lantern_client_error client_load_or_build_state(
    struct lantern_client *client,
    const struct lantern_client_options *options,
    bool *loaded_from_storage)
{
    const bool checkpoint_sync_configured =
        options
        && options->checkpoint_sync_url
        && options->checkpoint_sync_url[0] != '\0';
    const struct lantern_log_metadata meta = {.validator = client ? client->node_id : NULL};
    bool from_storage = false;
    bool should_attempt_checkpoint_sync = false;
    int storage_state_rc = lantern_storage_load_state(client->data_dir, &client->state);
    if (storage_state_rc == 0)
    {
        from_storage = true;
        if (checkpoint_sync_configured)
        {
            uint64_t expected_current_slot = 0u;
            uint64_t gap = 0u;
            time_t now_time = time(NULL);
            if (now_time != (time_t)-1
                && lantern_client_persisted_state_is_stale_for_checkpoint_sync(
                    &client->state,
                    client->genesis.chain_config.genesis_time,
                    (uint64_t)now_time,
                    &expected_current_slot,
                    &gap))
            {
                lantern_log_info(
                    "checkpoint_sync",
                    &meta,
                    "persisted state stale slot=%" PRIu64
                    " expected_current_slot=%" PRIu64
                    " gap=%" PRIu64
                    " threshold=%" PRIu64
                    "; discarding state and using checkpoint sync",
                    client->state.slot,
                    expected_current_slot,
                    gap,
                    LANTERN_CHECKPOINT_SYNC_STALE_PERSISTED_STATE_SLOT_THRESHOLD);
                lantern_state_reset(&client->state);
                from_storage = false;
                should_attempt_checkpoint_sync = true;
            }
            else
            {
                lantern_log_info(
                    "checkpoint_sync",
                    &meta,
                    "using persisted state; skipping checkpoint fetch");
            }
        }
    }
    else if (storage_state_rc < 0)
    {
        lantern_log_error(
            "storage",
            &meta,
            "failed to load persisted state");
        return LANTERN_CLIENT_ERR_STORAGE;
    }
    else
    {
        should_attempt_checkpoint_sync = checkpoint_sync_configured;
    }

    if (client->state.validator_count == 0u)
    {
        if (should_attempt_checkpoint_sync)
        {
            lantern_client_error checkpoint_rc = client_load_state_from_checkpoint(
                client,
                options->checkpoint_sync_url);
            if (checkpoint_rc != LANTERN_CLIENT_OK)
            {
                lantern_log_error(
                    "checkpoint_sync",
                    &meta,
                    "checkpoint sync failed; aborting startup");
                return checkpoint_rc;
            }
        }
        else if (client_generate_state_from_genesis(client) != LANTERN_CLIENT_OK)
        {
            return LANTERN_CLIENT_ERR_GENESIS;
        }
    }

    if (client->state.validator_count > 0u)
    {
        if (initialize_fork_choice(client) != 0)
        {
            return LANTERN_CLIENT_ERR_GENESIS;
        }
        if (restore_persisted_blocks(client) != 0)
        {
            return LANTERN_CLIENT_ERR_STORAGE;
        }
    }

    if (client->state.validator_count > 0u && !from_storage)
    {
        if (lantern_storage_save_state(client->data_dir, &client->state) != 0)
        {
            lantern_log_warn(
                "storage",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "failed to persist initial state snapshot");
        }
    }

    if (loaded_from_storage)
    {
        *loaded_from_storage = from_storage;
    }
    return client->state.validator_count > 0u ? LANTERN_CLIENT_OK : LANTERN_CLIENT_ERR_GENESIS;
}


/**
 * @brief Configure the client's local validator slice and key material.
 *
 * Validates the node's ENR entry, loads its assigned validators, and refreshes
 * pubkeys.
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
        client->assigned_validators->enr.is_aggregator = true;
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

    if (populate_local_validators(client) != 0)
    {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to enumerate local validators for '%s'",
            client->node_id);
        return LANTERN_CLIENT_ERR_VALIDATOR;
    }

    if (client->local_validator_count == 0 || client->state.validator_count == 0u)
    {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "no local validators assigned for '%s'; check validator-config",
            client->node_id);
        return LANTERN_CLIENT_ERR_VALIDATOR;
    }

    if (lantern_client_validate_state_validator_pubkeys(
            client,
            &client->state,
            "client")
        != 0)
    {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "validator pubkey validation failed for '%s'",
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
        "validator slice start=%" PRIu64 " count=%zu",
        client->local_validators[0].global_index,
        client->local_validator_count);

    return LANTERN_CLIENT_OK;
}


/**
 * @brief Start libp2p host and connection-level services.
 *
 * Loads the node key and prepares the libp2p host.
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
    struct lantern_libp2p_config net_cfg = {
        .listen_multiaddr = client->listen_address,
        .secp256k1_secret = node_key,
        .secret_len = NODE_PRIVATE_KEY_SIZE,
    };

    if (lantern_libp2p_host_prepare(&client->network, &net_cfg) != 0)
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

    return LANTERN_CLIENT_OK;
}

static bool subnet_id_list_contains(
    const size_t *subnet_ids,
    size_t count,
    size_t subnet_id)
{
    for (size_t i = 0; i < count; ++i)
    {
        if (subnet_ids[i] == subnet_id)
        {
            return true;
        }
    }
    return false;
}

static int subnet_id_list_append_unique(
    size_t **subnet_ids,
    size_t *count,
    size_t subnet_id)
{
    if (!subnet_ids || !count)
    {
        return -1;
    }
    if (subnet_id_list_contains(*subnet_ids, *count, subnet_id))
    {
        return 0;
    }
    if (*count == SIZE_MAX || (*count + 1u) > SIZE_MAX / sizeof(**subnet_ids))
    {
        return -1;
    }
    size_t new_count = *count + 1u;
    size_t *next = realloc(*subnet_ids, new_count * sizeof(*next));
    if (!next)
    {
        return -1;
    }
    next[*count] = subnet_id;
    *subnet_ids = next;
    *count = new_count;
    return 0;
}

static int collect_startup_attestation_subnets(
    const struct lantern_client *client,
    size_t attestation_committee_count,
    size_t primary_subnet_id,
    size_t **out_subnet_ids,
    size_t *out_count)
{
    if (!client || !out_subnet_ids || !out_count)
    {
        return -1;
    }
    *out_subnet_ids = NULL;
    *out_count = 0;

    if (subnet_id_list_append_unique(out_subnet_ids, out_count, primary_subnet_id) != 0)
    {
        return -1;
    }

    bool is_aggregator =
        client->assigned_validators && client->assigned_validators->enr.is_aggregator;
    if (is_aggregator)
    {
        for (size_t i = 0; i < client->aggregate_subnet_id_count; ++i)
        {
            if (subnet_id_list_append_unique(
                    out_subnet_ids,
                    out_count,
                    client->aggregate_subnet_ids[i])
                != 0)
            {
                return -1;
            }
        }
    }

    if (client->local_validators && client->local_validator_count > 0)
    {
        for (size_t i = 0; i < client->local_validator_count; ++i)
        {
            size_t validator_subnet_id = 0;
            if (lantern_validator_index_compute_subnet_id(
                    client->local_validators[i].global_index,
                    attestation_committee_count,
                    &validator_subnet_id)
                != 0)
            {
                return -1;
            }
            if (subnet_id_list_append_unique(out_subnet_ids, out_count, validator_subnet_id) != 0)
            {
                return -1;
            }
        }
    }

    return 0;
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
    uint8_t fork_digest[4] = {0};
    char topic_network_name[32];
    size_t subnet_id = 0;
    size_t *subscription_subnet_ids = NULL;
    size_t subscription_subnet_id_count = 0;
    size_t attestation_committee_count = lantern_client_attestation_committee_count(client);
    bool is_aggregator =
        client->assigned_validators && client->assigned_validators->enr.is_aggregator;
    bool has_explicit_aggregate_subnets =
        is_aggregator && client->aggregate_subnet_id_count > 0;
    bool have_fork_digest = client_resolve_gossip_fork_digest(client, fork_digest) == 0;
    if (have_fork_digest) {
        if (lantern_gossip_fork_digest_to_hex(fork_digest, topic_network_name) != 0) {
            lantern_log_error(
                "client",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "failed to format gossip fork digest for topic strings");
            return LANTERN_CLIENT_ERR_NETWORK;
        }
    } else {
        lantern_log_warn(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "gossip fork digest missing from genesis ENRs; falling back to --devnet topic slot '%s'",
            client->devnet ? client->devnet : "-");
        if (!client->devnet || client->devnet[0] == '\0') {
            lantern_log_error(
                "client",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "gossip topic fallback requires a non-empty --devnet value");
            return LANTERN_CLIENT_ERR_NETWORK;
        }
        snprintf(topic_network_name, sizeof(topic_network_name), "%s", client->devnet);
    }
    if (has_explicit_aggregate_subnets) {
        subnet_id = client->aggregate_subnet_ids[0];
        lantern_log_info(
            "gossip",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "aggregator subnet ids configured count=%zu primary=%zu committee_count=%zu",
            client->aggregate_subnet_id_count,
            subnet_id,
            attestation_committee_count);
    } else if (client->local_validators && client->local_validator_count > 0) {
        if (lantern_validator_index_compute_subnet_id(
                client->local_validators[0].global_index,
                attestation_committee_count,
                &subnet_id)
            != 0) {
            lantern_log_error(
                "client",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "failed to compute startup attestation subnet validator=%" PRIu64,
                client->local_validators[0].global_index);
            return LANTERN_CLIENT_ERR_NETWORK;
        }
    }
    if (!has_explicit_aggregate_subnets
        && client->assigned_validators
        && client->assigned_validators->enr.is_aggregator
        && client->assigned_validators->has_subnet) {
        if (lantern_client_aggregation_subnet_id(client, &subnet_id) != 0) {
            lantern_log_error(
                "client",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "failed to resolve configured aggregator subnet");
            return LANTERN_CLIENT_ERR_NETWORK;
        }
        lantern_log_info(
            "gossip",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "aggregator subnet configured subnet=%zu committee_count=%zu",
            subnet_id,
            attestation_committee_count);
    }
    if (collect_startup_attestation_subnets(
            client,
            attestation_committee_count,
            subnet_id,
            &subscription_subnet_ids,
            &subscription_subnet_id_count)
        != 0) {
        free(subscription_subnet_ids);
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to resolve attestation subnet subscriptions");
        return LANTERN_CLIENT_ERR_NETWORK;
    }
    struct lantern_gossipsub_config gossip_cfg = {
        .network = &client->network,
        .topic_network_name = topic_network_name,
        .attestation_subnet_id = subnet_id,
        .subscribe_attestation_subnet = 1,
    };
    client->gossip.block_handler = gossip_block_handler;
    client->gossip.block_handler_user_data = client;
    client->gossip.vote_handler = gossip_vote_handler;
    client->gossip.vote_handler_user_data = client;
    client->gossip.aggregated_attestation_handler = gossip_aggregated_attestation_handler;
    client->gossip.aggregated_attestation_handler_user_data = client;
    if (lantern_gossipsub_service_start(&client->gossip, &gossip_cfg) != 0)
    {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to start gossipsub service");
        free(subscription_subnet_ids);
        return LANTERN_CLIENT_ERR_NETWORK;
    }
    for (size_t i = 0; i < subscription_subnet_id_count; ++i) {
        size_t current_subnet_id = subscription_subnet_ids[i];
        if (current_subnet_id != subnet_id) {
            if (lantern_gossipsub_service_subscribe_attestation_subnet(
                    &client->gossip,
                    current_subnet_id)
                != 0) {
                lantern_log_error(
                    "client",
                    &(const struct lantern_log_metadata){.validator = client->node_id},
                    "failed to subscribe attestation subnet subnet=%zu",
                    current_subnet_id);
                lantern_gossipsub_service_reset(&client->gossip);
                free(subscription_subnet_ids);
                return LANTERN_CLIENT_ERR_NETWORK;
            }
        }
        lantern_log_info(
            "gossip",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "attestation subnet subscribed subnet=%zu committee_count=%zu explicit_aggregate_subnets=%s",
            current_subnet_id,
            attestation_committee_count,
            has_explicit_aggregate_subnets ? "true" : "false");
    }
    lantern_log_info(
        "gossip",
        &(const struct lantern_log_metadata){.validator = client->node_id},
        "gossip subscriptions: block + aggregation + %zu attestation subnet(s)",
        subscription_subnet_id_count);
    free(subscription_subnet_ids);

    struct lantern_reqresp_service_callbacks req_callbacks;
    memset(&req_callbacks, 0, sizeof(req_callbacks));
    req_callbacks.context = client;
    req_callbacks.build_status = reqresp_build_status;
    req_callbacks.handle_status = reqresp_handle_status;
    req_callbacks.status_failure = reqresp_status_failure;
    req_callbacks.collect_blocks = reqresp_collect_blocks;
    req_callbacks.collect_blocks_by_range = reqresp_collect_blocks_by_range;
    req_callbacks.current_slot = reqresp_current_slot;
    req_callbacks.handle_block_response = reqresp_handle_block_response;
    req_callbacks.blocks_request_complete = reqresp_blocks_request_complete;

    struct lantern_reqresp_service_config req_config;
    memset(&req_config, 0, sizeof(req_config));
    req_config.network = &client->network;
    req_config.callbacks = &req_callbacks;
    if (lantern_reqresp_service_start(&client->reqresp, &req_config) != 0)
    {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to start request/response service");
        return LANTERN_CLIENT_ERR_NETWORK;
    }
    /*
     * This handler may immediately send Status on CONN_ESTABLISHED. Register
     * it after reqresp so the req/resp protocols and event handler are ready.
     */
    if (lantern_libp2p_host_register_event_handler(&client->network, connection_events_cb, client) != 0
        || lantern_libp2p_host_register_drive_handler(&client->network, peer_maintenance_drive, client) != 0)
    {
        lantern_log_error(
            "network",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to register libp2p client handlers");
        return LANTERN_CLIENT_ERR_NETWORK;
    }

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

    if (lantern_libp2p_host_launch(&client->network) != 0)
    {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to launch libp2p host");
        return LANTERN_CLIENT_ERR_NETWORK;
    }

    memset(node_key, 0, NODE_PRIVATE_KEY_SIZE);
    return LANTERN_CLIENT_OK;
}


/**
 * @brief Launch background services for peer maintenance and validator duties.
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
            "failed to enable peer maintenance");
    }

    if (start_block_proposal_worker(client) != 0)
    {
        lantern_log_warn(
            "validator",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "block proposal worker inactive");
    }

    if (start_timing_service(client) != 0)
    {
        lantern_log_warn(
            "forkchoice",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "chain scheduler inactive");
    }
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
    }

    struct lantern_http_server_config http_config;
    memset(&http_config, 0, sizeof(http_config));
    http_config.port = client->http_port;
    http_config.callbacks.context = client;
    http_config.callbacks.snapshot_justified = http_snapshot_justified;
    http_config.callbacks.snapshot_fork_choice = http_snapshot_fork_choice;
    http_config.callbacks.metrics_snapshot = metrics_snapshot_cb;
    http_config.callbacks.finalized_state_ssz = http_finalized_state_ssz_cb;
    http_config.callbacks.finalized_block_ssz = http_finalized_block_ssz_cb;
    http_config.callbacks.get_is_aggregator = http_get_is_aggregator_cb;
    http_config.callbacks.set_is_aggregator = http_set_is_aggregator_cb;
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

    lantern_signature_configure_shadow_costs(
        options->shadow_xmss_rates,
        options->shadow_xmss_rates_set);

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

    err = lantern_client_block_importer_start(client);
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
 * Stops all services, releases all resources, and restores the same empty
 * baseline used at initialization.
 *
 * Shutdown order (reverse of initialization):
 * 1. Validator and ping services
 * 2. HTTP and metrics servers
 * 3. Networking (gossipsub, request/response, libp2p)
 * 4. Genesis artifacts and configuration
 * 5. State and fork choice
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

    stop_timing_service(client);
    stop_block_proposal_worker(client);
    stop_peer_dialer(client);
    lantern_libp2p_host_stop(&client->network);
    free(client->xmss_key_dir);
    free(client->xmss_secret_template);
    free(client->xmss_secret_path);

    lantern_metrics_server_stop(&client->metrics_server);
    lantern_http_server_stop(&client->http_server);
    lantern_client_block_importer_stop(client);

    connection_counter_reset(client);
    if (client->connection_lock_initialized)
    {
        pthread_mutex_destroy(&client->connection_lock);
    }

    bool status_locked = client->status_lock_initialized
        && pthread_mutex_lock(&client->status_lock) == 0;
    free(client->peer_status_entries);
    for (size_t i = 0; i < client->active_blocks_request_count; ++i)
    {
        free(client->active_blocks_requests[i].roots);
    }
    free(client->active_blocks_requests);
    if (status_locked)
    {
        pthread_mutex_unlock(&client->status_lock);
    }
    if (client->status_lock_initialized)
    {
        pthread_mutex_destroy(&client->status_lock);
    }
    if (client->validator_lock_initialized)
    {
        pthread_mutex_destroy(&client->validator_lock);
    }

    bool pending_locked = client->pending_lock_initialized
        && pthread_mutex_lock(&client->pending_lock) == 0;
    pending_block_list_reset(&client->pending_blocks);
    free(client->backfill.roots);
    if (pending_locked)
    {
        pthread_mutex_unlock(&client->pending_lock);
    }
    if (client->pending_lock_initialized)
    {
        pthread_mutex_destroy(&client->pending_lock);
    }

    reset_genesis_paths(&client->genesis_paths);
    lantern_genesis_artifacts_reset(&client->genesis);
    lantern_log_info(
        "client",
        &(const struct lantern_log_metadata){.validator = client->node_id},
        "shutdown: stopping request/response service");
    lantern_reqresp_service_reset(&client->reqresp);
    lantern_log_info(
        "client",
        &(const struct lantern_log_metadata){.validator = client->node_id},
        "shutdown: request/response service stopped");
    lantern_log_info(
        "client",
        &(const struct lantern_log_metadata){.validator = client->node_id},
        "shutdown: stopping gossipsub");
    lantern_gossipsub_service_stop(&client->gossip);
    lantern_log_info(
        "client",
        &(const struct lantern_log_metadata){.validator = client->node_id},
        "shutdown: gossipsub stopped");
    lantern_log_info(
        "client",
        &(const struct lantern_log_metadata){.validator = client->node_id},
        "shutdown: resetting libp2p host");
    lantern_libp2p_host_reset(&client->network);
    lantern_gossipsub_service_reset(&client->gossip);
    lantern_log_info(
        "client",
        &(const struct lantern_log_metadata){.validator = client->node_id},
        "shutdown: libp2p host reset");
    lantern_enr_record_reset(&client->local_enr);

    pending_vote_list_reset(&client->pending_gossip_votes);
    lantern_state_reset(&client->state);
    lantern_store_reset(&client->store);
    if (client->state_lock_initialized)
    {
        pthread_mutex_destroy(&client->state_lock);
    }
    lantern_client_reset_local_validators(client);
    lantern_log_reset_node_id();

    lantern_string_list_reset(&client->bootnodes);
    free(client->data_dir);
    free(client->node_id);
    free(client->listen_address);
    free(client->devnet);
    free(client->aggregate_subnet_ids);
    client_reset_base(client);
}
