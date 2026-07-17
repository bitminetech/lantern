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
 */

#include "client_internal.h"

#include <pthread.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>

#include "lantern/consensus/fork_choice.h"
#include "lantern/http/server.h"
#include "lantern/metrics/lean_metrics.h"
#include "lantern/storage/storage.h"
#include "lantern/support/log.h"
#include "lantern/support/strings.h"


/* ============================================================================
 * HTTP Snapshot Callbacks
 * ============================================================================ */

/**
 * Get the current justified checkpoint for HTTP API.
 *
 * @param context       Client instance
 * @param out_checkpoint Output checkpoint
 *
 * @return 0 on success
 * @return LANTERN_HTTP_CB_ERR_INVALID_PARAM if context or out_checkpoint is NULL
 * @return LANTERN_HTTP_CB_ERR_INVALID_STATE if checkpoint snapshot is unavailable
 *
 * @note Thread safety: Reads fork-choice checkpoint snapshots without acquiring state_lock.
 */
int http_snapshot_justified(void *context, LanternCheckpoint *out_checkpoint)
{
    if (!context || !out_checkpoint)
    {
        return LANTERN_HTTP_CB_ERR_INVALID_PARAM;
    }
    struct lantern_client *client = context;

    if (client->store.block_len == 0u)
    {
        return LANTERN_HTTP_CB_ERR_INVALID_STATE;
    }

    if (!lantern_fork_choice_read_checkpoint_snapshot(
            &client->store,
            out_checkpoint,
            NULL))
    {
        return LANTERN_HTTP_CB_ERR_INVALID_STATE;
    }

    return LANTERN_HTTP_CB_OK;
}

int http_snapshot_fork_choice(
    void *context,
    struct lantern_fork_choice_tree_snapshot *out_snapshot)
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

    if (client->store.block_len == 0u)
    {
        lantern_client_unlock_state(client, state_locked);
        return LANTERN_HTTP_CB_ERR_INVALID_STATE;
    }

    int result = lantern_fork_choice_snapshot_tree(&client->store, out_snapshot);
    lantern_client_unlock_state(client, state_locked);
    return result == 0 ? LANTERN_HTTP_CB_OK : LANTERN_HTTP_CB_ERR_IO;
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
    bool previous = client->assigned_validators->enr.is_aggregator;
    client->assigned_validators->enr.is_aggregator = enabled;
    lantern_client_unlock_mutex(
        &client->validator_lock, client->node_id, "validator_lock", "client_http");

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
 * @note Thread safety: This function may acquire state_lock and status_lock
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
    if (client->store.block_len > 0u)
    {
        fork_head_root = client->store.head;
        uint64_t slot = 0;
        if (lantern_fork_choice_block_info(
                &client->store,
                &fork_head_root,
                &slot,
                NULL,
                NULL)
            == 0)
        {
            fork_head_slot = slot;
            have_fork_head = true;
        }

        slot = 0;
        if (lantern_fork_choice_block_info(
                &client->store,
                &client->store.safe_target,
                &slot,
                NULL,
                NULL)
            == 0)
        {
            safe_target_slot = slot;
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
    if (client->state.validator_count > 0u)
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
    out_snapshot->lean_justified_slot = state_justified.slot;
    out_snapshot->lean_finalized_slot = state_finalized.slot;
    (void)snprintf(
        out_snapshot->lean_client_label,
        sizeof(out_snapshot->lean_client_label),
        "%s",
        client->node_id && client->node_id[0] != '\0' ? client->node_id : "unknown");
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
    out_snapshot->lean_gossip_mesh_peers = lantern_gossipsub_service_mesh_peer_count(&client->gossip);
    out_snapshot->lean_connected_peers = 0;
    if (client->connection_lock_initialized)
    {
        if (pthread_mutex_lock(&client->connection_lock) != 0)
        {
            return LANTERN_HTTP_CB_ERR_LOCK_FAILED;
        }
        out_snapshot->lean_connected_peers = client->connected_peers;
        lantern_client_unlock_mutex(
            &client->connection_lock, client->node_id, "connection_lock", "client_http");
    }
    out_snapshot->peer_vote_metrics_count = 0;
    if (client->status_lock_initialized)
    {
        if (pthread_mutex_lock(&client->status_lock) != 0)
        {
            return LANTERN_HTTP_CB_ERR_LOCK_FAILED;
        }

        const size_t limit = LANTERN_METRICS_MAX_PEER_VOTE_STATS;
        for (size_t i = 0;
             i < client->peer_status_count && out_snapshot->peer_vote_metrics_count < limit;
             ++i)
        {
            const struct lantern_peer_status_entry *entry = &client->peer_status_entries[i];
            struct lantern_peer_vote_metric *metric =
                &out_snapshot->peer_vote_metrics[out_snapshot->peer_vote_metrics_count++];
            (void)lantern_string_copy(metric->peer_id, sizeof(metric->peer_id), entry->peer_id);
            metric->received_total = entry->votes_received;
            metric->accepted_total = entry->votes_accepted;
            metric->rejected_total = entry->votes_rejected;
            metric->last_validator_id = entry->last_vote_validator_id;
            metric->last_slot = entry->last_vote_slot;
        }
        lantern_client_unlock_mutex(
            &client->status_lock, client->node_id, "status_lock", "client_http");
    }
    lean_metrics_snapshot(&out_snapshot->lean_metrics);
    return LANTERN_HTTP_CB_OK;
}


/* ============================================================================
 * Checkpoint Sync Callbacks
 * ============================================================================ */

static int load_finalized_ssz(
    void *context,
    uint8_t **out_bytes,
    size_t *out_len,
    int (*load)(const struct lantern_storage *, const LanternRoot *, uint8_t **, size_t *))
{
    if (!context || !out_bytes || !out_len || !load)
    {
        return LANTERN_HTTP_CB_ERR_INVALID_PARAM;
    }

    *out_bytes = NULL;
    *out_len = 0;

    struct lantern_client *client = context;
    if (!client->storage.backend || client->store.block_len == 0u)
    {
        return LANTERN_HTTP_CB_ERR_INVALID_STATE;
    }

    LanternCheckpoint finalized;
    if (!lantern_fork_choice_read_checkpoint_snapshot(&client->store, NULL, &finalized))
    {
        return LANTERN_HTTP_CB_ERR_INVALID_STATE;
    }
    if (lantern_root_is_zero(&finalized.root))
    {
        return LANTERN_HTTP_CB_ERR_NOT_FOUND;
    }

    int load_rc = load(&client->storage, &finalized.root, out_bytes, out_len);
    return load_rc == 0
        ? LANTERN_HTTP_CB_OK
        : (load_rc > 0 ? LANTERN_HTTP_CB_ERR_NOT_FOUND : LANTERN_HTTP_CB_ERR_IO);
}

/**
 * Get finalized state SSZ bytes for checkpoint sync.
 *
 * @param context    Client instance
 * @param out_bytes  Output buffer pointer (caller owns and must free)
 * @param out_len    Output byte length
 *
 * @return 0 on success
 * @return LANTERN_HTTP_CB_ERR_INVALID_PARAM if inputs are NULL
 * @return LANTERN_HTTP_CB_ERR_INVALID_STATE if client has no snapshot or data dir
 * @return LANTERN_HTTP_CB_ERR_NOT_FOUND if finalized state is unavailable
 * @return LANTERN_HTTP_CB_ERR_IO on storage read failure
 *
 * @note Thread safety: Reads the finalized checkpoint from fork-choice's
 *       lock-free snapshot. Loading the full state still depends on persisted
 *       storage for that finalized root and may perform blocking I/O.
 */
int http_finalized_state_ssz_cb(void *context, uint8_t **out_bytes, size_t *out_len)
{
    return load_finalized_ssz(
        context,
        out_bytes,
        out_len,
        lantern_storage_load_state_bytes_for_root);
}

/**
 * Get finalized signed block SSZ bytes for the finalized block endpoint.
 *
 * @param context    Client instance
 * @param out_bytes  Output buffer pointer (caller owns and must free)
 * @param out_len    Output byte length
 *
 * @return 0 on success
 * @return LANTERN_HTTP_CB_ERR_INVALID_PARAM if inputs are NULL
 * @return LANTERN_HTTP_CB_ERR_INVALID_STATE if client has no snapshot or data dir
 * @return LANTERN_HTTP_CB_ERR_NOT_FOUND if finalized block is unavailable
 * @return LANTERN_HTTP_CB_ERR_IO on storage read failure
 */
int http_finalized_block_ssz_cb(void *context, uint8_t **out_bytes, size_t *out_len)
{
    return load_finalized_ssz(
        context,
        out_bytes,
        out_len,
        lantern_storage_load_block_bytes_for_root);
}
