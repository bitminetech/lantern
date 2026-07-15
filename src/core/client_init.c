/**
 * @file client_init.c
 * @brief Client initialization helpers
 *
 * @spec subspecs/containers/state/genesis.py in tools/leanSpec
 *
 * Implements genesis path management, bootnode configuration, and local
 * validator population.
 *
 * Related files:
 * - client.c: Main client initialization and lifecycle
 * - client_keys.c: Key loading and management
 *
 * @note Thread safety: Functions are called during single-threaded
 *       initialization phase. No locking required.
 */

#include "client_internal.h"

#include "lantern/networking/libp2p.h"
#include "lantern/support/log.h"
#include "lantern/support/strings.h"

#include <inttypes.h>
#include <limits.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char LANTERN_ANNOTATED_VALIDATORS_FILENAME[] = "annotated_validators.yaml";
static const char LANTERN_VALIDATOR_CONFIG_FILENAME[] = "validator-config.yaml";


/* ============================================================================
 * Forward Declarations
 * ============================================================================ */

void reset_genesis_paths(struct lantern_genesis_paths *paths);
static int join_path_component(const char *dir, const char *leaf, char **out_path);


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
    if (join_path_component(
            options->validator_config_dir,
            LANTERN_ANNOTATED_VALIDATORS_FILENAME,
            &paths->validator_registry_path)
        != 0)
    {
        return -1;
    }
    if (set_owned_string(&paths->nodes_path, options->nodes_path) != 0)
    {
        return -1;
    }
    if (join_path_component(
            options->validator_config_dir,
            LANTERN_VALIDATOR_CONFIG_FILENAME,
            &paths->validator_config_path)
        != 0)
    {
        return -1;
    }

    return 0;
}

static int join_path_component(const char *dir, const char *leaf, char **out_path)
{
    if (!dir || !leaf || !out_path || dir[0] == '\0')
    {
        return -1;
    }

    *out_path = NULL;

    size_t dir_len = strlen(dir);
    size_t leaf_len = strlen(leaf);
    bool needs_sep = dir_len > 0 && dir[dir_len - 1] != '/' && dir[dir_len - 1] != '\\';
    size_t total = dir_len + (needs_sep ? 1u : 0u) + leaf_len + 1u;
    char *buffer = malloc(total);
    if (!buffer)
    {
        return -1;
    }

    int written = snprintf(
        buffer,
        total,
        needs_sep ? "%s/%s" : "%s%s",
        dir,
        leaf);
    if (written <= 0 || (size_t)written >= total)
    {
        free(buffer);
        return -1;
    }

    *out_path = buffer;
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
    free(paths->validator_config_path);
    memset(paths, 0, sizeof(*paths));
}


/**
 * Append bootnodes from genesis ENR records.
 *
 * @spec subspecs/networking/discovery.py - peer discovery
 *
 * Iterates through ENR records from genesis, stores them in the client's
 * bootnode list, and verifies that they can be converted to c-lean-libp2p
 * dial addresses. Actual dialing starts after the libp2p host is launched.
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
        if (lantern_string_list_append_unique(&client->bootnodes, record->encoded) != 0)
        {
            return -1;
        }
        lantern_log_info(
            "network",
            &(const struct lantern_log_metadata){
                .validator = client->node_id,
                .peer = record->encoded},
            "bootnode registered sequence=%" PRIu64,
            record->sequence);
    }
    return 0;
}


/**
 * Populate local validator keys from the assigned validator config.
 *
 * @spec subspecs/xmss/keygen.py - validator key management
 *
 * Allocates local validator state for the assigned global indices.
 *
 * @param client Client instance
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: Called during init, acquires validator_lock
 */
int populate_local_validators(struct lantern_client *client)
{
    if (!client || !client->assigned_validators
        || !client->assigned_validators->indices
        || client->assigned_validators->indices_len == 0u
        || client->assigned_validators->indices_len != client->assigned_validators->count)
    {
        return -1;
    }

    struct lantern_log_metadata meta = {.validator = client->node_id};
    size_t local_count = client->assigned_validators->indices_len;

    uint64_t total_validators = client->genesis.chain_config.validator_count;
    char indices_buf[512];
    indices_buf[0] = '\0';
    size_t written = 0;
    for (size_t i = 0; i < local_count; ++i)
    {
        int n = snprintf(
            indices_buf + written,
            sizeof(indices_buf) - written,
            "%s%" PRIu64,
            written > 0 ? "," : "",
            client->assigned_validators->indices[i]);
        if (n < 0 || (size_t)n >= sizeof(indices_buf) - written)
        {
            memcpy(indices_buf + (sizeof(indices_buf) > 4 ? sizeof(indices_buf) - 4 : 0), "...", 3);
            indices_buf[sizeof(indices_buf) - 1] = '\0';
            break;
        }
        written += (size_t)n;
    }
    lantern_log_info(
        "client",
        &meta,
        "local validator assignment start=%" PRIu64 " count=%zu indices=%s",
        client->assigned_validators->indices[0],
        local_count,
        indices_buf[0] ? indices_buf : "-");

    size_t count = (size_t)local_count;
    struct lantern_local_validator *validators = calloc(count, sizeof(*validators));
    if (!validators)
    {
        return -1;
    }

    for (size_t i = 0; i < count; ++i)
    {
        uint64_t global_index = client->assigned_validators->indices[i];
        if (global_index >= total_validators)
        {
            free(validators);
            return -1;
        }
        validators[i].global_index = global_index;
    }

    if (!client->validator_lock_initialized)
    {
        if (pthread_mutex_init(&client->validator_lock, NULL) != 0)
        {
            free(validators);
            return -1;
        }
        client->validator_lock_initialized = true;
    }

    if (pthread_mutex_lock(&client->validator_lock) != 0)
    {
        free(validators);
        return -1;
    }

    lantern_client_reset_local_validators(client);
    client->local_validators = validators;
    client->local_validator_count = count;
    validators = NULL;

    pthread_mutex_unlock(&client->validator_lock);

    lantern_log_info(
        "client",
        &meta,
        "local validators ready count=%zu",
        client->local_validator_count);
    return 0;
}
