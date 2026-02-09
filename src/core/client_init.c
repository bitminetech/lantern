/**
 * @file client_init.c
 * @brief Client initialization helpers
 *
 * @spec subspecs/containers/state/genesis.py in tools/leanSpec
 *
 * Implements genesis path management, bootnode configuration, validator
 * assignment computation, local validator population, and consensus
 * runtime initialization.
 *
 * Related files:
 * - client.c: Main client initialization and lifecycle
 * - client_keys.c: Key loading and management
 *
 * @note Thread safety: Functions are called during single-threaded
 *       initialization phase. No locking required.
 */

#include "client_internal.h"

#include "lantern/consensus/runtime.h"
#include "lantern/networking/libp2p.h"
#include "lantern/support/log.h"
#include "lantern/support/secure_mem.h"
#include "lantern/support/strings.h"

#include <inttypes.h>
#include <limits.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>


/* ============================================================================
 * Forward Declarations
 * ============================================================================ */

void reset_genesis_paths(struct lantern_genesis_paths *paths);
int append_unique_bootnode(struct lantern_string_list *list, const char *value);


/* ============================================================================
 * Genesis Path Management
 * ============================================================================ */

/**
 * Copy genesis file paths from client options.
 *
 * @spec subspecs/containers/state/genesis.py - genesis configuration
 *
 * @param paths   Output paths structure
 * @param options Client options containing source paths
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: Called during init, no locking required
 */
int copy_genesis_paths(
    struct lantern_genesis_paths *paths,
    const struct lantern_client_options *options)
{
    if (!paths || !options)
    {
        return -1;
    }

    reset_genesis_paths(paths);

    if (set_owned_string(&paths->config_path, options->genesis_config_path) != 0)
    {
        return -1;
    }
    if (set_owned_string(&paths->validator_registry_path, options->validator_registry_path) != 0)
    {
        return -1;
    }
    if (set_owned_string(&paths->nodes_path, options->nodes_path) != 0)
    {
        return -1;
    }
    if (set_owned_string(&paths->validator_config_path, options->validator_config_path) != 0)
    {
        return -1;
    }

    return 0;
}


/**
 * Reset and free all genesis path strings.
 *
 * @param paths Paths structure to reset
 *
 * @note Thread safety: Called during cleanup, no locking required
 */
void reset_genesis_paths(struct lantern_genesis_paths *paths)
{
    if (!paths)
    {
        return;
    }
    free(paths->config_path);
    free(paths->validator_registry_path);
    free(paths->nodes_path);
    free(paths->state_path);
    free(paths->validator_config_path);
    memset(paths, 0, sizeof(*paths));
}


/* ============================================================================
 * Bootnode Management
 * ============================================================================ */

/**
 * Append a bootnode to the list if not already present.
 *
 * @param list  String list to append to
 * @param value Bootnode address to append
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: Called during init, no locking required
 */
int append_unique_bootnode(struct lantern_string_list *list, const char *value)
{
    if (!list || !value)
    {
        return -1;
    }
    if (*value == '\0')
    {
        return 0;
    }
    if (string_list_contains(list, value))
    {
        return 0;
    }
    return lantern_string_list_append(list, value);
}


/**
 * Append bootnodes from genesis ENR records.
 *
 * @spec subspecs/networking/discovery.py - peer discovery
 *
 * Iterates through ENR records from genesis and adds them as bootnodes
 * to the client's bootnode list and peer store.
 *
 * @param client Client instance
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: Called during init, no locking required
 */
int append_genesis_bootnodes(struct lantern_client *client)
{
    if (!client)
    {
        return -1;
    }
    const struct lantern_enr_record_list *enrs = &client->genesis.enrs;
    for (size_t i = 0; i < enrs->count; ++i)
    {
        const struct lantern_enr_record *record = &enrs->records[i];
        if (!record->encoded)
        {
            continue;
        }
        if (append_unique_bootnode(&client->bootnodes, record->encoded) != 0)
        {
            return -1;
        }
        if (client->network.host)
        {
            if (lantern_libp2p_host_add_enr_peer(&client->network, record, LANTERN_LIBP2P_DEFAULT_PEER_TTL_MS) != 0)
            {
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


/* ============================================================================
 * Validator Assignment
 * ============================================================================ */

/**
 * Compute validator assignment from assigned validator indices.
 *
 * @spec subspecs/duties/duties.py - validator duties assignment
 *
 * Takes the validator configuration and computes which validators
 * are assigned to this node based on the node ID.
 *
 * @param client Client instance
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: Called during init, no locking required
 */
int compute_local_validator_assignment(struct lantern_client *client)
{
    if (!client || !client->assigned_validators)
    {
        return -1;
    }
    lantern_validator_assignment_reset(&client->validator_assignment);
    client->has_validator_assignment = false;
    if (lantern_validator_assignment_from_config(
            &client->genesis.validator_config,
            client->assigned_validators,
            &client->validator_assignment)
        != 0)
    {
        return -1;
    }
    if (!lantern_validator_assignment_is_valid(&client->validator_assignment))
    {
        return -1;
    }
    client->has_validator_assignment = true;
    return 0;
}


/**
 * Populate local validator keys from assignment.
 *
 * @spec subspecs/xmss/keygen.py - validator key management
 *
 * Allocates and initializes local validator structures, decodes
 * validator secrets, and sets up per-validator state.
 *
 * @param client Client instance
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: Called during init, acquires validator_lock
 */
int populate_local_validators(struct lantern_client *client)
{
    if (!client || !client->has_validator_assignment || !client->assigned_validators)
    {
        return -1;
    }

    struct lantern_log_metadata meta = {.validator = client->node_id};
    uint64_t local_count = client->validator_assignment.count;
    if (local_count == 0 || client->validator_assignment.length != local_count)
    {
        return -1;
    }
    if (!client->validator_assignment.indices)
    {
        return -1;
    }
    if (local_count > SIZE_MAX)
    {
        return -1;
    }

    uint64_t total_validators = client->genesis.chain_config.validator_count;
    if (!client->genesis.validator_registry.records
        || client->genesis.validator_registry.count < total_validators)
    {
        return -1;
    }

    char indices_buf[512];
    indices_buf[0] = '\0';
    size_t written = 0;
    for (size_t i = 0; i < client->validator_assignment.length; ++i)
    {
        int n = snprintf(
            indices_buf + written,
            sizeof(indices_buf) - written,
            "%s%" PRIu64,
            written > 0 ? "," : "",
            client->validator_assignment.indices[i]);
        if (n < 0 || (size_t)n >= sizeof(indices_buf) - written)
        {
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
    if (!priv_hex || *priv_hex == '\0')
    {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "validator '%s' missing privkey in validator-config",
            client->node_id);
        return -1;
    }

    uint8_t *decoded_secret = NULL;
    size_t decoded_len = 0;
    if (lantern_client_decode_validator_secret(priv_hex, &decoded_secret, &decoded_len) != 0
        || decoded_len == 0)
    {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "validator '%s' privkey is invalid",
            client->node_id);
        if (decoded_secret)
        {
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
    if (stored_len > 0)
    {
        lantern_secure_zero(client->assigned_validators->privkey_hex, stored_len);
        client->assigned_validators->privkey_hex[0] = '\0';
    }

    size_t count = (size_t)local_count;
    struct lantern_local_validator *validators = calloc(count, sizeof(*validators));
    if (!validators)
    {
        lantern_secure_zero(decoded_secret, decoded_len);
        free(decoded_secret);
        return -1;
    }

    for (size_t i = 0; i < count; ++i)
    {
        uint64_t global_index = client->validator_assignment.indices[i];
        if (global_index >= total_validators)
        {
            for (size_t j = 0; j < i; ++j)
            {
                lantern_client_local_validator_cleanup(&validators[j]);
            }
            free(validators);
            lantern_secure_zero(decoded_secret, decoded_len);
            free(decoded_secret);
            return -1;
        }
        validators[i].global_index = global_index;
        validators[i].registry = &client->genesis.validator_registry.records[global_index];
        validators[i].secret_len = decoded_len;
        if (decoded_len > 0)
        {
            validators[i].secret = malloc(decoded_len);
            if (!validators[i].secret)
            {
                for (size_t j = 0; j <= i; ++j)
                {
                    lantern_client_local_validator_cleanup(&validators[j]);
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
    if (!enabled)
    {
        for (size_t i = 0; i < count; ++i)
        {
            lantern_client_local_validator_cleanup(&validators[i]);
        }
        free(validators);
        lantern_secure_zero(decoded_secret, decoded_len);
        free(decoded_secret);
        return -1;
    }
    for (size_t i = 0; i < count; ++i)
    {
        enabled[i] = true;
    }

    if (!client->validator_lock_initialized)
    {
        if (pthread_mutex_init(&client->validator_lock, NULL) != 0)
        {
            free(enabled);
            for (size_t i = 0; i < count; ++i)
            {
                lantern_client_local_validator_cleanup(&validators[i]);
            }
            free(validators);
            lantern_secure_zero(decoded_secret, decoded_len);
            free(decoded_secret);
            return -1;
        }
        client->validator_lock_initialized = true;
    }

    if (pthread_mutex_lock(&client->validator_lock) != 0)
    {
        free(enabled);
        for (size_t i = 0; i < count; ++i)
        {
            lantern_client_local_validator_cleanup(&validators[i]);
        }
        free(validators);
        lantern_secure_zero(decoded_secret, decoded_len);
        free(decoded_secret);
        return -1;
    }

    free(client->validator_enabled);
    client->validator_enabled = enabled;
    enabled = NULL;

    lantern_client_reset_local_validators(client);
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


/* ============================================================================
 * Consensus Runtime Initialization
 * ============================================================================ */

/**
 * Initialize consensus runtime for a client.
 *
 * @spec subspecs/runtime/runtime.py - consensus runtime
 *
 * Configures and initializes the consensus runtime with genesis time,
 * validator count, and local validator assignment.
 *
 * @param client Client instance
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: Called during init, no locking required
 */
int init_consensus_runtime(struct lantern_client *client)
{
    if (!client || !client->has_validator_assignment)
    {
        return -1;
    }
    struct lantern_consensus_runtime_config runtime_config;
    lantern_consensus_runtime_config_init(&runtime_config);
    runtime_config.genesis_time = client->genesis.chain_config.genesis_time;
    runtime_config.validator_count = client->genesis.chain_config.validator_count;
    if (runtime_config.validator_count == 0)
    {
        return -1;
    }
    if (lantern_consensus_runtime_init(
            &client->runtime,
            &runtime_config,
            &client->validator_assignment)
        != 0)
    {
        return -1;
    }
    client->has_runtime = true;
    return 0;
}
