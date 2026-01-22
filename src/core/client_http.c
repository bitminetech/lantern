/**
 * @file client_http.c
 * @brief HTTP server and metrics callbacks
 *
 * Implements callback functions for the HTTP server and metrics collection.
 *
 * @note Lock ordering (acquire in this order to prevent deadlocks):
 *       1. state_lock
 *       2. status_lock
 *       3. pending_lock
 *       4. validator_lock
 *       5. connection_lock
 *       6. peer_vote_lock
 */

#include "client_internal.h"

#include <inttypes.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>

#include "lantern/consensus/fork_choice.h"
#include "lantern/consensus/hash.h"
#include "lantern/http/server.h"
#include "lantern/metrics/lean_metrics.h"
#include "lantern/storage/storage.h"
#include "lantern/support/log.h"


/**
 * @brief Unlock a mutex and log on failure.
 */
static void unlock_mutex_with_log(
    pthread_mutex_t *mutex,
    const char *validator_id,
    const char *name)
{
    if (!mutex || !name)
    {
        return;
    }

    int unlock_rc = pthread_mutex_unlock(mutex);
    if (unlock_rc != 0)
    {
        lantern_log_warn(
            "client_http",
            &(const struct lantern_log_metadata){.validator = validator_id},
            "failed to unlock %s: %d",
            name,
            unlock_rc);
    }
}


/* ============================================================================
 * Validator Index Lookup
 * ============================================================================ */

/**
 * Find local validator index by global index.
 *
 * @param client        Client instance
 * @param global_index  Global validator index to find
 * @param out_index     Output for local index
 *
 * @return 0 on success
 * @return LANTERN_HTTP_CB_ERR_INVALID_PARAM if client or out_index is NULL
 * @return LANTERN_HTTP_CB_ERR_NOT_FOUND if validator is not found
 *
 * @note Thread safety: This function is thread-safe
 */
int find_local_validator_index(
    const struct lantern_client *client,
    uint64_t global_index,
    size_t *out_index)
{
    if (!client || !out_index)
    {
        return LANTERN_HTTP_CB_ERR_INVALID_PARAM;
    }
    for (size_t i = 0; i < client->local_validator_count; ++i)
    {
        if (client->local_validators
            && client->local_validators[i].global_index == global_index)
        {
            *out_index = i;
            return LANTERN_HTTP_CB_OK;
        }
    }
    return LANTERN_HTTP_CB_ERR_NOT_FOUND;
}


/* ============================================================================
 * HTTP Snapshot Callbacks
 * ============================================================================ */

/**
 * Get current head snapshot for HTTP API.
 *
 * @param context       Client instance
 * @param out_snapshot  Output snapshot structure
 *
 * @return 0 on success
 * @return LANTERN_HTTP_CB_ERR_INVALID_PARAM if context or out_snapshot is NULL
 * @return LANTERN_HTTP_CB_ERR_INVALID_STATE if client has no state
 * @return LANTERN_HTTP_CB_ERR_LOCK_FAILED if state_lock is initialized but cannot be acquired
 * @return LANTERN_HTTP_CB_ERR_HASH_FAILED if head root cannot be computed
 *
 * @note Thread safety: This function may acquire state_lock
 */
int http_snapshot_head(void *context, struct lantern_http_head_snapshot *out_snapshot)
{
    if (!context || !out_snapshot)
    {
        return LANTERN_HTTP_CB_ERR_INVALID_PARAM;
    }
    struct lantern_client *client = context;
    memset(out_snapshot, 0, sizeof(*out_snapshot));

    const bool expect_state_lock = client->state_lock_initialized;
    bool state_locked = lantern_client_lock_state(client);
    if (expect_state_lock && !state_locked)
    {
        return LANTERN_HTTP_CB_ERR_LOCK_FAILED;
    }

    if (!client->has_state)
    {
        lantern_client_unlock_state(client, state_locked);
        return LANTERN_HTTP_CB_ERR_INVALID_STATE;
    }

    LanternBlockHeader head_header = client->state.latest_block_header;
    LanternCheckpoint justified = client->state.latest_justified;
    LanternCheckpoint finalized = client->state.latest_finalized;
    if (client->has_fork_choice)
    {
        const LanternCheckpoint *fork_finalized =
            lantern_fork_choice_latest_finalized(&client->fork_choice);
        if (fork_finalized && !lantern_root_is_zero(&fork_finalized->root))
        {
            finalized = *fork_finalized;
        }
    }
    lantern_client_unlock_state(client, state_locked);

    out_snapshot->slot = head_header.slot;
    out_snapshot->justified = justified;
    out_snapshot->finalized = finalized;
    if (lantern_hash_tree_root_block_header(&head_header, &out_snapshot->head_root) != 0)
    {
        return LANTERN_HTTP_CB_ERR_HASH_FAILED;
    }

    return LANTERN_HTTP_CB_OK;
}


/* ============================================================================
 * HTTP Validator Callbacks
 * ============================================================================ */

/**
 * Get count of local validators for HTTP API.
 *
 * @param context  Client instance
 * @return Number of local validators
 *
 * @note Thread safety: This function is thread-safe
 */
size_t http_validator_count_cb(void *context)
{
    const struct lantern_client *client = context;
    if (!client)
    {
        return 0;
    }
    return client->local_validator_count;
}


/**
 * Get validator info for HTTP API.
 *
 * @param context   Client instance
 * @param index     Local validator index
 * @param out_info  Output info structure
 *
 * @return 0 on success
 * @return LANTERN_HTTP_CB_ERR_INVALID_PARAM if context or out_info is NULL
 * @return LANTERN_HTTP_CB_ERR_NOT_FOUND if index is out of bounds or validator data is
 *         unavailable
 * @return LANTERN_HTTP_CB_ERR_LOCK_FAILED if validator_lock is initialized but cannot be
 *         acquired
 *
 * @note Thread safety: This function may acquire validator_lock
 */
int http_validator_info_cb(
    void *context,
    size_t index,
    struct lantern_http_validator_info *out_info)
{
    if (!context || !out_info)
    {
        return LANTERN_HTTP_CB_ERR_INVALID_PARAM;
    }
    struct lantern_client *client = context;
    if (index >= client->local_validator_count || !client->local_validators)
    {
        return LANTERN_HTTP_CB_ERR_NOT_FOUND;
    }
    memset(out_info, 0, sizeof(*out_info));
    out_info->global_index = client->local_validators[index].global_index;

    bool enabled = true;
    if (client->validator_lock_initialized)
    {
        if (pthread_mutex_lock(&client->validator_lock) != 0)
        {
            return LANTERN_HTTP_CB_ERR_LOCK_FAILED;
        }
        if (client->validator_enabled && index < client->local_validator_count)
        {
            enabled = client->validator_enabled[index];
        }
        unlock_mutex_with_log(&client->validator_lock, client->node_id, "validator_lock");
    }
    else if (client->validator_enabled && index < client->local_validator_count)
    {
        enabled = client->validator_enabled[index];
    }
    out_info->enabled = enabled;

    const char *base = client->node_id ? client->node_id : "validator";
    int written = snprintf(
        out_info->label,
        sizeof(out_info->label),
        "%s#%" PRIu64,
        base,
        out_info->global_index);
    if (written < 0 || (size_t)written >= sizeof(out_info->label))
    {
        strncpy(out_info->label, base, sizeof(out_info->label));
        out_info->label[sizeof(out_info->label) - 1] = '\0';
    }
    return LANTERN_HTTP_CB_OK;
}


/**
 * Set validator enabled/disabled status for HTTP API.
 *
 * @param context       Client instance
 * @param global_index  Global validator index
 * @param enabled       New enabled status
 *
 * @return 0 on success
 * @return LANTERN_HTTP_CB_ERR_INVALID_PARAM if context is NULL
 * @return LANTERN_HTTP_CB_ERR_INVALID_STATE if validator tracking is not initialized
 * @return LANTERN_HTTP_CB_ERR_LOCK_FAILED if validator_lock cannot be acquired
 * @return LANTERN_HTTP_CB_ERR_NOT_FOUND if global_index is not a local validator
 *
 * @note Thread safety: This function acquires validator_lock
 */
int http_set_validator_status_cb(void *context, uint64_t global_index, bool enabled)
{
    if (!context)
    {
        return LANTERN_HTTP_CB_ERR_INVALID_PARAM;
    }
    struct lantern_client *client = context;
    if (!client->validator_lock_initialized || !client->validator_enabled)
    {
        return LANTERN_HTTP_CB_ERR_INVALID_STATE;
    }
    if (pthread_mutex_lock(&client->validator_lock) != 0)
    {
        return LANTERN_HTTP_CB_ERR_LOCK_FAILED;
    }
    size_t local_index = 0;
    if (find_local_validator_index(client, global_index, &local_index) != 0
        || local_index >= client->local_validator_count)
    {
        unlock_mutex_with_log(&client->validator_lock, client->node_id, "validator_lock");
        return LANTERN_HTTP_CB_ERR_NOT_FOUND;
    }
    client->validator_enabled[local_index] = enabled;

    size_t enabled_count = 0;
    size_t disabled_count = 0;
    for (size_t i = 0; i < client->local_validator_count; ++i)
    {
        if (client->validator_enabled[i])
        {
            ++enabled_count;
        }
        else
        {
            ++disabled_count;
        }
    }

    unlock_mutex_with_log(&client->validator_lock, client->node_id, "validator_lock");

    lantern_log_info(
        "validator",
        &(const struct lantern_log_metadata){.validator = client->node_id},
        "validator %" PRIu64 " %s (enabled=%zu disabled=%zu)",
        global_index,
        enabled ? "activated" : "deactivated",
        enabled_count,
        disabled_count);

    return LANTERN_HTTP_CB_OK;
}


/* ============================================================================
 * Metrics Callbacks
 * ============================================================================ */

/**
 * Get metrics snapshot for HTTP API.
 *
 * @param context       Client instance
 * @param out_snapshot  Output snapshot structure
 *
 * @return 0 on success
 * @return LANTERN_HTTP_CB_ERR_INVALID_PARAM if context or out_snapshot is NULL
 * @return LANTERN_HTTP_CB_ERR_LOCK_FAILED if required locks cannot be acquired
 *
 * @note Thread safety: This function may acquire state_lock and peer_vote_lock
 */
int metrics_snapshot_cb(void *context, struct lantern_metrics_snapshot *out_snapshot)
{
    if (!context || !out_snapshot)
    {
        return LANTERN_HTTP_CB_ERR_INVALID_PARAM;
    }
    struct lantern_client *client = context;
    memset(out_snapshot, 0, sizeof(*out_snapshot));

    const bool expect_state_lock = client->state_lock_initialized;
    bool state_locked = lantern_client_lock_state(client);
    if (expect_state_lock && !state_locked)
    {
        return LANTERN_HTTP_CB_ERR_LOCK_FAILED;
    }

    bool have_fork_head = false;
    LanternRoot fork_head_root;
    memset(&fork_head_root, 0, sizeof(fork_head_root));
    uint64_t fork_head_slot = 0;
    uint64_t safe_target_slot = 0;
    if (client->has_fork_choice)
    {
        if (lantern_fork_choice_current_head(&client->fork_choice, &fork_head_root) == 0)
        {
            uint64_t slot = 0;
            if (lantern_fork_choice_block_info(
                    &client->fork_choice,
                    &fork_head_root,
                    &slot,
                    NULL,
                    NULL)
                == 0)
            {
                fork_head_slot = slot;
                have_fork_head = true;
            }
        }

        const LanternRoot *safe_target = lantern_fork_choice_safe_target(&client->fork_choice);
        if (safe_target)
        {
            uint64_t slot = 0;
            if (lantern_fork_choice_block_info(
                    &client->fork_choice,
                    safe_target,
                    &slot,
                    NULL,
                    NULL)
                == 0)
            {
                safe_target_slot = slot;
            }
        }
    }

    uint64_t state_head_slot = 0;
    uint64_t current_slot = 0;
    LanternCheckpoint state_justified;
    LanternCheckpoint state_finalized;
    memset(&state_justified, 0, sizeof(state_justified));
    memset(&state_finalized, 0, sizeof(state_finalized));
    if (client->has_state)
    {
        /* Use the latest_block_header slot which is the actual block slot,
           not state.slot which may be advanced during state transition processing */
        state_head_slot = client->state.latest_block_header.slot;
        state_justified = client->state.latest_justified;
        state_finalized = client->state.latest_finalized;
    }
    if (!lantern_client_current_slot(client, &current_slot))
    {
        current_slot = state_head_slot;
    }
    lantern_client_unlock_state(client, state_locked);

    out_snapshot->lean_node_start_time_seconds = client->start_time_seconds;
    out_snapshot->lean_head_slot = have_fork_head ? fork_head_slot : state_head_slot;
    out_snapshot->lean_current_slot = current_slot;
    out_snapshot->lean_safe_target_slot = safe_target_slot;
    out_snapshot->lean_latest_justified_slot = state_justified.slot;
    out_snapshot->lean_latest_finalized_slot = state_finalized.slot;
    out_snapshot->lean_validators_count = client->local_validator_count;
    out_snapshot->lean_connected_peers = 0;
    if (client->connection_lock_initialized)
    {
        if (pthread_mutex_lock(&client->connection_lock) != 0)
        {
            return LANTERN_HTTP_CB_ERR_LOCK_FAILED;
        }
        out_snapshot->lean_connected_peers = client->connected_peers;
        unlock_mutex_with_log(&client->connection_lock, client->node_id, "connection_lock");
    }
    out_snapshot->peer_vote_metrics_count = 0;
    if (client->peer_vote_lock_initialized)
    {
        if (pthread_mutex_lock(&client->peer_vote_lock) != 0)
        {
            return LANTERN_HTTP_CB_ERR_LOCK_FAILED;
        }

        {
            const size_t limit = LANTERN_METRICS_MAX_PEER_VOTE_STATS;
            for (size_t i = 0;
                 i < client->peer_vote_stats_len
                     && out_snapshot->peer_vote_metrics_count < limit;
                 ++i)
            {
                const struct lantern_peer_vote_metric *entry = &client->peer_vote_stats[i];
                struct lantern_peer_vote_metric *metric =
                    &out_snapshot->peer_vote_metrics[out_snapshot->peer_vote_metrics_count++];
                *metric = *entry;
            }
            unlock_mutex_with_log(&client->peer_vote_lock, client->node_id, "peer_vote_lock");
        }
    }
    lean_metrics_snapshot(&out_snapshot->lean_metrics);
    return LANTERN_HTTP_CB_OK;
}


/* ============================================================================
 * Checkpoint Sync Callbacks
 * ============================================================================ */

/**
 * Get finalized state SSZ bytes for checkpoint sync.
 *
 * @param context    Client instance
 * @param out_bytes  Output buffer pointer (caller owns and must free)
 * @param out_len    Output byte length
 *
 * @return 0 on success
 * @return LANTERN_HTTP_CB_ERR_INVALID_PARAM if inputs are NULL
 * @return LANTERN_HTTP_CB_ERR_INVALID_STATE if client has no state or data dir
 * @return LANTERN_HTTP_CB_ERR_NOT_FOUND if finalized state is unavailable
 * @return LANTERN_HTTP_CB_ERR_LOCK_FAILED if state_lock cannot be acquired
 * @return LANTERN_HTTP_CB_ERR_IO on storage read failure
 *
 * @note Thread safety: This function may acquire state_lock
 */
int http_finalized_state_ssz_cb(void *context, uint8_t **out_bytes, size_t *out_len)
{
    if (!context || !out_bytes || !out_len)
    {
        return LANTERN_HTTP_CB_ERR_INVALID_PARAM;
    }

    *out_bytes = NULL;
    *out_len = 0;

    struct lantern_client *client = context;
    if (!client->data_dir)
    {
        return LANTERN_HTTP_CB_ERR_INVALID_STATE;
    }

    const bool expect_state_lock = client->state_lock_initialized;
    bool state_locked = lantern_client_lock_state(client);
    if (expect_state_lock && !state_locked)
    {
        return LANTERN_HTTP_CB_ERR_LOCK_FAILED;
    }

    if (!client->has_state)
    {
        lantern_client_unlock_state(client, state_locked);
        return LANTERN_HTTP_CB_ERR_INVALID_STATE;
    }

    LanternCheckpoint finalized = client->state.latest_finalized;
    lantern_client_unlock_state(client, state_locked);

    if (lantern_root_is_zero(&finalized.root))
    {
        return LANTERN_HTTP_CB_ERR_NOT_FOUND;
    }

    int load_rc = lantern_storage_load_state_bytes_for_root(
        client->data_dir,
        &finalized.root,
        out_bytes,
        out_len);
    if (load_rc == 0)
    {
        return LANTERN_HTTP_CB_OK;
    }
    if (load_rc > 0)
    {
        return LANTERN_HTTP_CB_ERR_NOT_FOUND;
    }
    return LANTERN_HTTP_CB_ERR_IO;
}
