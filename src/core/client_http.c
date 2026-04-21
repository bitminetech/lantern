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
#include <stdlib.h>
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
        const LanternCheckpoint *fork_justified =
            lantern_fork_choice_latest_justified(&client->fork_choice);
        const LanternCheckpoint *fork_finalized =
            lantern_fork_choice_latest_finalized(&client->fork_choice);
        if (fork_justified && !lantern_root_is_zero(&fork_justified->root))
        {
            justified = *fork_justified;
        }
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

int http_snapshot_fork_choice(
    void *context,
    struct lantern_http_fork_choice_snapshot *out_snapshot)
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

    if (!client->has_fork_choice
        || !client->fork_choice.initialized
        || !client->fork_choice.has_anchor)
    {
        lantern_client_unlock_state(client, state_locked);
        return LANTERN_HTTP_CB_ERR_INVALID_STATE;
    }

    struct lantern_fork_choice_tree_snapshot snapshot;
    memset(&snapshot, 0, sizeof(snapshot));
    if (lantern_fork_choice_snapshot_tree(&client->fork_choice, &snapshot) != 0)
    {
        lantern_client_unlock_state(client, state_locked);
        return LANTERN_HTTP_CB_ERR_IO;
    }

    uint64_t validator_count = 0;
    const LanternState *head_state =
        lantern_fork_choice_block_state(&client->fork_choice, &snapshot.head);
    if (head_state)
    {
        validator_count = (uint64_t)lantern_state_validator_count(head_state);
    }
    else if (client->has_state)
    {
        LanternRoot state_head_root;
        if (lantern_hash_tree_root_block_header(
                &client->state.latest_block_header,
                &state_head_root)
            != 0)
        {
            lantern_fork_choice_tree_snapshot_reset(&snapshot);
            lantern_client_unlock_state(client, state_locked);
            return LANTERN_HTTP_CB_ERR_HASH_FAILED;
        }
        if (memcmp(state_head_root.bytes, snapshot.head.bytes, LANTERN_ROOT_SIZE) == 0)
        {
            validator_count = (uint64_t)lantern_state_validator_count(&client->state);
        }
    }

    if (snapshot.node_count > 0)
    {
        out_snapshot->nodes = calloc(snapshot.node_count, sizeof(*out_snapshot->nodes));
        if (!out_snapshot->nodes)
        {
            lantern_fork_choice_tree_snapshot_reset(&snapshot);
            lantern_client_unlock_state(client, state_locked);
            return LANTERN_HTTP_CB_ERR_IO;
        }
    }

    for (size_t i = 0; i < snapshot.node_count; ++i)
    {
        out_snapshot->nodes[i].root = snapshot.nodes[i].root;
        out_snapshot->nodes[i].slot = snapshot.nodes[i].slot;
        out_snapshot->nodes[i].parent_root = snapshot.nodes[i].parent_root;
        out_snapshot->nodes[i].proposer_index = snapshot.nodes[i].proposer_index;
        out_snapshot->nodes[i].weight = snapshot.nodes[i].weight;
    }

    out_snapshot->node_count = snapshot.node_count;
    out_snapshot->head = snapshot.head;
    out_snapshot->justified = snapshot.justified;
    out_snapshot->finalized = snapshot.finalized;
    out_snapshot->safe_target = snapshot.safe_target;
    out_snapshot->validator_count = validator_count;

    lantern_fork_choice_tree_snapshot_reset(&snapshot);
    lantern_client_unlock_state(client, state_locked);
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


int http_get_is_aggregator_cb(void *context, bool *out_enabled)
{
    if (!context || !out_enabled)
    {
        return LANTERN_HTTP_CB_ERR_INVALID_PARAM;
    }
    struct lantern_client *client = context;
    if (!client->assigned_validators)
    {
        return LANTERN_HTTP_CB_ERR_INVALID_STATE;
    }
    *out_enabled = client->assigned_validators->enr.is_aggregator;
    return LANTERN_HTTP_CB_OK;
}


int http_set_is_aggregator_cb(void *context, bool enabled, bool *out_previous)
{
    if (!context || !out_previous)
    {
        return LANTERN_HTTP_CB_ERR_INVALID_PARAM;
    }
    struct lantern_client *client = context;
    if (!client->assigned_validators)
    {
        return LANTERN_HTTP_CB_ERR_INVALID_STATE;
    }
    if (!client->validator_lock_initialized)
    {
        return LANTERN_HTTP_CB_ERR_INVALID_STATE;
    }
    if (pthread_mutex_lock(&client->validator_lock) != 0)
    {
        return LANTERN_HTTP_CB_ERR_LOCK_FAILED;
    }
    struct lantern_validator_config_entry *mutable_entry =
        (struct lantern_validator_config_entry *)client->assigned_validators;
    bool previous = mutable_entry->enr.is_aggregator;
    mutable_entry->enr.is_aggregator = enabled;
    unlock_mutex_with_log(&client->validator_lock, client->node_id, "validator_lock");

    *out_previous = previous;

    if (previous != enabled)
    {
        lantern_log_info(
            "validator",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "aggregator role %s via admin API",
            enabled ? "activated" : "deactivated");
    }

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
    size_t gossip_signature_count = 0;
    size_t new_aggregated_payload_count = 0;
    size_t known_aggregated_payload_count = 0;
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
    gossip_signature_count = client->store.attestation_signatures.length;
    new_aggregated_payload_count = client->store.new_aggregated_payloads.length;
    known_aggregated_payload_count = client->store.known_aggregated_payloads.length;

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
    out_snapshot->lean_justified_slot = client->state.latest_justified.slot;
    out_snapshot->lean_finalized_slot = client->state.latest_finalized.slot;
    out_snapshot->lean_validators_count = client->local_validator_count;
    out_snapshot->lean_gossip_signatures = (uint64_t)gossip_signature_count;
    out_snapshot->lean_latest_new_aggregated_payloads = (uint64_t)new_aggregated_payload_count;
    out_snapshot->lean_latest_known_aggregated_payloads = (uint64_t)known_aggregated_payload_count;
    out_snapshot->lean_is_aggregator =
        (client->assigned_validators && client->assigned_validators->enr.is_aggregator) ? 1u : 0u;
    out_snapshot->lean_attestation_committee_subnet = (uint64_t)client->gossip.attestation_subnet_id;
    out_snapshot->lean_attestation_committee_count =
        (uint64_t)lantern_client_attestation_committee_count(client);
    out_snapshot->lean_node_sync_status = (uint64_t)client->sync_state;
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
