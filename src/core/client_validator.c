/**
 * @file client_validator.c
 * @brief Validator service and duty management
 *
 * Implements the validator service thread, block proposal,
 * attestation publishing, and vote signing.
 *
 * @note Lock ordering (acquire in this order to prevent deadlocks):
 *       1. state_lock
 *       2. status_lock
 *       3. pending_lock
 *       4. validator_lock
 *       5. connection_lock
 */

#include "client_services_internal.h"

#include <inttypes.h>
#include <pthread.h>
#if defined(_WIN32)
#include <windows.h>
#else
#include <sched.h>
#endif
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "client_internal.h"

#include "lantern/consensus/fork_choice.h"
#include "lantern/consensus/hash.h"
#include "lantern/consensus/signature.h"
#include "lantern/consensus/state.h"
#include "lantern/crypto/xmss.h"
#include "lantern/metrics/lean_metrics.h"
#include "lantern/networking/gossipsub_service.h"
#include "lantern/support/log.h"
#include "lantern/support/time.h"


/* ============================================================================
 * Constants
 * ============================================================================ */

/** Sleep interval when timing service cannot run (ms). */
static const uint32_t TIMING_SERVICE_IDLE_SLEEP_MS = 200;

/** Sleep interval after timing service errors (ms). */
static const uint32_t TIMING_SERVICE_POLL_SLEEP_MS = 50;

/** Maximum sleep while waiting for a proposal's target slot (ms). */
static const uint32_t BLOCK_PROPOSAL_BOUNDARY_WAIT_SLICE_MS = 1000;

/** Slot lag past which local validator duties are silenced. */
static const uint64_t VALIDATOR_SYNC_LAG_THRESHOLD = 4u;

/** Slot lag past which the network is considered stalled, so duties stay live. */
static const uint64_t VALIDATOR_NETWORK_STALL_THRESHOLD = 8u;

/** Hysteresis band for reopening a closed duty gate. */
static const uint64_t VALIDATOR_SYNC_LAG_HYSTERESIS = 2u;

void lantern_signature_set_stage_timings(struct lantern_block_build_stage_timings *timings);

int validator_publish_aggregated_attestations(struct lantern_client *client, uint64_t slot);
lantern_client_error validator_collect_and_aggregate_attestation_signatures(
    struct lantern_client *client,
    struct lantern_aggregated_payload_pool *out_payloads,
    const uint64_t *scope_slot,
    struct lantern_block_build_stage_timings *stage_timings,
    bool *out_missing_state);
static void validator_log_duty_skipped(
    struct lantern_client *client,
    uint64_t slot,
    const char *reason);

static bool validator_record_aggregation_skipped_once(
    struct lantern_client *client,
    uint64_t slot,
    lean_metrics_aggregator_skipped_reason_t reason)
{
    if (!client)
    {
        return false;
    }
    struct lantern_validator_duty_state *duty = &client->validator_duty;
    uint64_t marker = slot + 1u;
    if (duty->aggregation_skip_marker == marker)
    {
        return false;
    }
    lean_metrics_record_aggregator_skipped(reason);
    duty->aggregation_skip_marker = marker;
    if (duty->slot_marker == marker)
    {
        duty->slot_aggregated = true;
    }
    return true;
}

static double validator_elapsed_seconds(double started_seconds, double finished_seconds)
{
    return finished_seconds >= started_seconds ? finished_seconds - started_seconds : 0.0;
}

static void validator_add_stage_seconds(double *stage_seconds, double seconds)
{
    if (!stage_seconds || seconds <= 0.0)
    {
        return;
    }
    *stage_seconds += seconds;
}

static double validator_stage_timings_sum(const struct lantern_block_build_stage_timings *timings)
{
    if (!timings)
    {
        return 0.0;
    }
    return timings->vote_collection_seconds
        + timings->key_sig_deserialize_seconds
        + timings->pq_aggregate_seconds
        + timings->proof_copy_seconds
        + timings->lock_waits_seconds
        + timings->other_prover_setup_seconds;
}

static void validator_stage_timings_add_remainder(
    struct lantern_block_build_stage_timings *timings,
    double total_seconds)
{
    if (!timings)
    {
        return;
    }
    double accounted_seconds = validator_stage_timings_sum(timings);
    if (total_seconds > accounted_seconds)
    {
        validator_add_stage_seconds(
            &timings->other_prover_setup_seconds,
            total_seconds - accounted_seconds);
    }
    else if (accounted_seconds > total_seconds)
    {
        double overage_seconds = accounted_seconds - total_seconds;
        if (timings->other_prover_setup_seconds >= overage_seconds)
        {
            timings->other_prover_setup_seconds -= overage_seconds;
        }
    }
}

struct lantern_async_block_proposal_job {
    struct lantern_client *client;
    size_t local_index;
    double build_started_seconds;
    struct lantern_block_build_stage_timings stage_timings;
    LanternRoot block_root;
    LanternSignedBlock block;
    LanternState proof_state;
    LanternState post_state;
    struct lantern_aggregated_payload_pool attestation_payloads;
    LanternSignature proposer_signature;
};

static uint32_t timing_service_sleep_until_next_interval(
    const struct lantern_client *client,
    uint64_t now_milliseconds,
    uint64_t target_interval)
{
    if (!client || client->state.validator_count == 0u || target_interval == UINT64_MAX) {
        return TIMING_SERVICE_POLL_SLEEP_MS;
    }

    uint64_t genesis_time = client->state.config.genesis_time;
    if (genesis_time > UINT64_MAX / 1000u) {
        return TIMING_SERVICE_POLL_SLEEP_MS;
    }

    uint64_t genesis_milliseconds = genesis_time * 1000u;
    uint64_t next_interval = target_interval + 1u;
    if (next_interval < target_interval
        || next_interval > (UINT64_MAX - genesis_milliseconds) / LANTERN_MILLISECONDS_PER_INTERVAL) {
        return TIMING_SERVICE_POLL_SLEEP_MS;
    }

    uint64_t next_interval_start =
        genesis_milliseconds + (next_interval * LANTERN_MILLISECONDS_PER_INTERVAL);
    if (now_milliseconds >= next_interval_start) {
        return 0u;
    }

    uint64_t remaining = next_interval_start - now_milliseconds;
    if (remaining > UINT32_MAX) {
        remaining = UINT32_MAX;
    }
    return (uint32_t)remaining;
}

static void timing_service_yield(void)
{
#if defined(_WIN32)
    Sleep(0);
#else
    sched_yield();
#endif
}

static void format_slot_text(char *out, size_t out_len, bool has_slot, uint64_t slot)
{
    if (!out || out_len == 0)
    {
        return;
    }
    if (has_slot)
    {
        snprintf(out, out_len, "%" PRIu64, slot);
    }
    else
    {
        snprintf(out, out_len, "-");
    }
}

static void validator_log_status_for_slot(struct lantern_client *client, uint64_t slot)
{
    if (!client)
    {
        return;
    }

    LanternRoot head_root = {0};
    uint64_t head_slot = 0u;
    uint64_t justified_slot = 0u;
    uint64_t finalized_slot = 0u;
    bool have_head_root = false;
    bool state_locked = lantern_client_lock_state(client);
    if (state_locked)
    {
        if (client->store.block_len > 0u)
        {
            head_root = client->store.head;
            have_head_root = true;
            (void)lantern_fork_choice_block_info(
                &client->store,
                &head_root,
                &head_slot,
                NULL,
                NULL);
            justified_slot = client->store.latest_justified.slot;
            finalized_slot = client->store.latest_finalized.slot;
        }
        else if (client->state.validator_count > 0u)
        {
            head_slot = client->state.slot;
            justified_slot = client->state.latest_justified.slot;
            finalized_slot = client->state.latest_finalized.slot;
        }
        lantern_client_unlock_state(client, state_locked);
    }

    size_t orphan_count = 0u;
    bool pending_locked = lantern_client_lock_pending(client);
    if (pending_locked)
    {
        orphan_count = client->pending_blocks.length;
        lantern_client_unlock_pending(client, pending_locked);
    }

    size_t peers = client->connected_peers;
    if (client->connection_lock_initialized
        && pthread_mutex_lock(&client->connection_lock) == 0)
    {
        peers = client->connected_peers;
        pthread_mutex_unlock(&client->connection_lock);
    }

    LanternSyncState sync_state = client->sync_state;
    LanternStatusMessage network_view = client->network_view;
    if (client->status_lock_initialized
        && pthread_mutex_lock(&client->status_lock) == 0)
    {
        sync_state = client->sync_state;
        network_view = client->network_view;
        pthread_mutex_unlock(&client->status_lock);
    }

    char head_root_hex[2 * LANTERN_ROOT_SIZE + 3];
    char network_head_text[32];
    char network_finalized_text[32];
    format_root_hex(have_head_root ? &head_root : NULL, head_root_hex, sizeof(head_root_hex));
    format_slot_text(
        network_head_text,
        sizeof(network_head_text),
        !lantern_root_is_zero(&network_view.head.root),
        network_view.head.slot);
    format_slot_text(
        network_finalized_text,
        sizeof(network_finalized_text),
        !lantern_root_is_zero(&network_view.finalized.root),
        network_view.finalized.slot);
    lantern_log_info(
        "status",
        &(const struct lantern_log_metadata){.validator = client->node_id},
        "slot %" PRIu64 ", head %" PRIu64 ", head_root %s, justified %" PRIu64
        ", finalized %" PRIu64 ", %s, %zu peers, orphans %zu, net_head %s, net_finalized %s",
        slot,
        head_slot,
        head_root_hex[0] ? head_root_hex : "0x0",
        justified_slot,
        finalized_slot,
        lantern_sync_state_name(sync_state),
        peers,
        orphan_count,
        network_head_text,
        network_finalized_text);
}

static const char *validator_service_skip_reason(const struct lantern_client *client)
{
    if (!client)
    {
        return "client_null";
    }
    if (client->state.validator_count == 0u)
    {
        return "state_not_ready";
    }
    if (client->store.block_len == 0u)
    {
        return "fork_choice_not_ready";
    }
    if (!client->gossip.gossipsub && !client->gossip.loopback_only)
    {
        return "gossip_not_running";
    }
    if (client->local_validator_count == 0)
    {
        return "no_validators";
    }
    return NULL;
}

static bool validator_duty_gate_allows(
    struct lantern_client *client,
    uint64_t slot,
    const char *duty)
{
    if (!client)
    {
        return false;
    }

    LanternCheckpoint network_head = {0};
    if (client->status_lock_initialized
        && pthread_mutex_lock(&client->status_lock) == 0)
    {
        network_head = client->network_view.head;
        pthread_mutex_unlock(&client->status_lock);
    }

    uint64_t head_slot = 0u;
    uint64_t max_seen_slot = 0u;
    uint64_t finalized_slot = 0u;
    bool have_head_slot = false;
    bool network_head_known = false;
    bool state_locked = lantern_client_lock_state(client);
    if (!state_locked)
    {
        validator_log_duty_skipped(client, slot, "duty_gate_state_lock_failed");
        return false;
    }

    if (client->store.block_len > 0u)
    {
        LanternRoot head_root;
        if (lantern_fork_choice_recompute_head(&client->store) != 0)
        {
            lantern_client_unlock_state(client, state_locked);
            validator_log_duty_skipped(client, slot, "duty_gate_head_recompute_failed");
            return false;
        }
        head_root = client->store.head;
        finalized_slot = client->store.latest_finalized.slot;
        if (lantern_fork_choice_block_info(
                   &client->store,
                   &head_root,
                   &head_slot,
                   NULL,
                   NULL)
                   == 0)
        {
            have_head_slot = true;
            max_seen_slot = head_slot;
        }

        if (client->store.blocks)
        {
            for (size_t i = 0; i < client->store.block_len; ++i)
            {
                uint64_t block_slot = client->store.blocks[i].slot;
                if (!have_head_slot || block_slot > max_seen_slot)
                {
                    max_seen_slot = block_slot;
                }
            }
        }
        uint64_t known_network_head_slot = 0u;
        network_head_known = !lantern_root_is_zero(&network_head.root)
            && lantern_client_block_known_locked(
                client,
                &network_head.root,
                &known_network_head_slot)
            && known_network_head_slot == network_head.slot;
    }
    else if (client->state.validator_count > 0u)
    {
        head_slot = client->state.slot;
        max_seen_slot = head_slot;
        have_head_slot = true;
    }
    lantern_client_unlock_state(client, state_locked);

    if (!lantern_root_is_zero(&network_head.root)
        && network_head.slot > finalized_slot
        && !network_head_known)
    {
        validator_log_duty_skipped(client, slot, "network_head_unresolved");
        return false;
    }

    if (!have_head_slot)
    {
        return true;
    }

    uint64_t lag = head_slot >= slot ? 0u : slot - head_slot;
    uint64_t network_lag = max_seen_slot >= slot ? 0u : slot - max_seen_slot;
    bool network_stalling = network_lag > VALIDATOR_NETWORK_STALL_THRESHOLD;
    struct lantern_validator_duty_state *duty_state = &client->validator_duty;
    bool allow = true;

    if (network_stalling)
    {
        allow = true;
        if (duty_state->duty_gate_closed)
        {
            duty_state->duty_gate_closed = false;
            lantern_log_info(
                "validator",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "duty gate reopened: network stall detected duty=%s slot=%" PRIu64
                " head=%" PRIu64 " lag=%" PRIu64 " max_seen=%" PRIu64
                " network_lag=%" PRIu64,
                duty ? duty : "-",
                slot,
                head_slot,
                lag,
                max_seen_slot,
                network_lag);
        }
    }
    else if (duty_state->duty_gate_closed)
    {
        uint64_t reopen_lag = VALIDATOR_SYNC_LAG_THRESHOLD > VALIDATOR_SYNC_LAG_HYSTERESIS
            ? VALIDATOR_SYNC_LAG_THRESHOLD - VALIDATOR_SYNC_LAG_HYSTERESIS
            : 0u;
        allow = lag <= reopen_lag;
        if (allow)
        {
            duty_state->duty_gate_closed = false;
            lantern_log_info(
                "validator",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "duty gate reopened: local view caught up duty=%s slot=%" PRIu64
                " head=%" PRIu64 " lag=%" PRIu64,
                duty ? duty : "-",
                slot,
                head_slot,
                lag);
        }
    }
    else
    {
        allow = lag <= VALIDATOR_SYNC_LAG_THRESHOLD;
        if (!allow)
        {
            duty_state->duty_gate_closed = true;
            lantern_log_info(
                "validator",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "duty gate closed: local view stale duty=%s slot=%" PRIu64
                " head=%" PRIu64 " lag=%" PRIu64 " max_seen=%" PRIu64
                " network_lag=%" PRIu64,
                duty ? duty : "-",
                slot,
                head_slot,
                lag,
                max_seen_slot,
                network_lag);
        }
    }

    if (!allow)
    {
        validator_log_duty_skipped(client, slot, "duty_gate_stale_view");
    }
    return allow;
}

static void validator_log_duty_skipped(
    struct lantern_client *client,
    uint64_t slot,
    const char *reason)
{
    if (!client || !reason || reason[0] == '\0')
    {
        return;
    }

    bool should_log = true;
    if (client->status_lock_initialized
        && pthread_mutex_lock(&client->status_lock) == 0)
    {
        if (client->last_duty_skip_reason
            && client->last_duty_skip_slot == slot
            && strcmp(client->last_duty_skip_reason, reason) == 0)
        {
            should_log = false;
        }
        else
        {
            client->last_duty_skip_slot = slot;
            client->last_duty_skip_reason = reason;
        }
        pthread_mutex_unlock(&client->status_lock);
    }
    else if (client->last_duty_skip_reason
             && client->last_duty_skip_slot == slot
             && strcmp(client->last_duty_skip_reason, reason) == 0)
    {
        should_log = false;
    }
    else
    {
        client->last_duty_skip_slot = slot;
        client->last_duty_skip_reason = reason;
    }

    if (should_log)
    {
        lantern_log_info(
            "duty",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "slot %" PRIu64 ", skipped, reason: %s",
            slot,
            reason);
    }
}

static lantern_client_error state_aggregate_result_to_client_error(
    lantern_state_aggregate_result rc)
{
    switch (rc)
    {
        case LANTERN_STATE_AGGREGATE_OK:
            return LANTERN_CLIENT_OK;
        case LANTERN_STATE_AGGREGATE_INVALID_PARAM:
            return LANTERN_CLIENT_ERR_INVALID_PARAM;
        case LANTERN_STATE_AGGREGATE_ALLOC:
            return LANTERN_CLIENT_ERR_ALLOC;
        case LANTERN_STATE_AGGREGATE_RUNTIME:
            return LANTERN_CLIENT_ERR_RUNTIME;
        case LANTERN_STATE_AGGREGATE_VALIDATOR:
        default:
            return LANTERN_CLIENT_ERR_VALIDATOR;
    }
}

static int payload_pool_snapshot(
    struct lantern_aggregated_payload_pool *dst,
    const struct lantern_aggregated_payload_pool *src)
{
    dst->entries = NULL;
    dst->length = 0;
    dst->capacity = 0;
    if (!src || src->length == 0u || !src->entries)
    {
        return 0;
    }
    dst->entries = calloc(src->length, sizeof(*dst->entries));
    if (!dst->entries)
    {
        return -1;
    }
    dst->capacity = src->length;
    for (size_t i = 0; i < src->length; ++i)
    {
        dst->entries[i].data_root = src->entries[i].data_root;
        dst->entries[i].data = src->entries[i].data;
        lantern_aggregated_signature_proof_init(&dst->entries[i].proof);
        dst->length = i + 1u;
        if (lantern_aggregated_signature_proof_copy(
                &dst->entries[i].proof,
                &src->entries[i].proof)
            != 0)
        {
            lantern_aggregated_payload_pool_reset(dst);
            return -1;
        }
    }
    return 0;
}

static int signature_map_snapshot(
    struct lantern_attestation_signature_map *dst,
    const struct lantern_attestation_signature_map *src,
    const uint64_t *scope_slot)
{
    *dst = (struct lantern_attestation_signature_map){0};
    if (!src || src->length == 0u)
    {
        return 0;
    }
    dst->entries = calloc(src->length, sizeof(*dst->entries));
    if (!dst->entries)
    {
        return -1;
    }
    dst->capacity = src->length;
    for (size_t i = 0u; i < src->length; ++i)
    {
        if (scope_slot && src->entries[i].data.slot != *scope_slot)
        {
            continue;
        }
        dst->entries[dst->length++] = src->entries[i];
    }
    return 0;
}

lantern_client_error validator_collect_and_aggregate_attestation_signatures(
    struct lantern_client *client,
    struct lantern_aggregated_payload_pool *out_payloads,
    const uint64_t *scope_slot,
    struct lantern_block_build_stage_timings *stage_timings,
    bool *out_missing_state)
{
    if (!client || !out_payloads)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    if (out_missing_state)
    {
        *out_missing_state = false;
    }

    double lock_started_seconds = lantern_time_now_seconds();
    bool state_locked = lantern_client_lock_state(client);
    double lock_finished_seconds = lantern_time_now_seconds();
    validator_add_stage_seconds(
        stage_timings ? &stage_timings->lock_waits_seconds : NULL,
        validator_elapsed_seconds(lock_started_seconds, lock_finished_seconds));
    if (!state_locked)
    {
        return LANTERN_CLIENT_ERR_RUNTIME;
    }
    if (client->state.validator_count == 0u)
    {
        if (out_missing_state)
        {
            *out_missing_state = true;
        }
        lantern_client_unlock_state(client, state_locked);
        return LANTERN_CLIENT_ERR_RUNTIME;
    }

    LanternState state_snapshot;
    LanternStore store_snapshot;
    lantern_store_init(&store_snapshot);

    bool raw_only = scope_slot != NULL;
    int snapshot_rc = lantern_state_clone(&client->state, &state_snapshot);
    double collection_started_seconds = lantern_time_now_seconds();
    if (snapshot_rc == 0)
    {
        snapshot_rc = signature_map_snapshot(
            &store_snapshot.attestation_signatures,
            &client->store.attestation_signatures,
            scope_slot);
    }
    double collection_finished_seconds = lantern_time_now_seconds();
    validator_add_stage_seconds(
        stage_timings ? &stage_timings->vote_collection_seconds : NULL,
        validator_elapsed_seconds(collection_started_seconds, collection_finished_seconds));
    double other_started_seconds = lantern_time_now_seconds();
    if (!raw_only && snapshot_rc == 0)
    {
        snapshot_rc = payload_pool_snapshot(
            &store_snapshot.new_aggregated_payloads,
            &client->store.new_aggregated_payloads);
    }
    if (!raw_only && snapshot_rc == 0)
    {
        snapshot_rc = payload_pool_snapshot(
            &store_snapshot.known_aggregated_payloads,
            &client->store.known_aggregated_payloads);
    }
    double other_finished_seconds = lantern_time_now_seconds();
    validator_add_stage_seconds(
        stage_timings ? &stage_timings->other_prover_setup_seconds : NULL,
        validator_elapsed_seconds(other_started_seconds, other_finished_seconds));

    lantern_client_unlock_state(client, state_locked);

    lantern_client_error rc = LANTERN_CLIENT_OK;
    if (snapshot_rc != 0)
    {
        rc = LANTERN_CLIENT_ERR_ALLOC;
    }
    else
    {
        lantern_signature_set_stage_timings(stage_timings);
        lantern_state_aggregate_result aggregate_result = lantern_state_aggregate(
            &state_snapshot,
            &store_snapshot,
            out_payloads);
        lantern_signature_set_stage_timings(NULL);
        rc = state_aggregate_result_to_client_error(aggregate_result);
    }

    if (rc == LANTERN_CLIENT_OK)
    {
        double commit_lock_started_seconds = lantern_time_now_seconds();
        bool commit_locked = lantern_client_lock_state(client);
        double commit_lock_finished_seconds = lantern_time_now_seconds();
        validator_add_stage_seconds(
            stage_timings ? &stage_timings->lock_waits_seconds : NULL,
            validator_elapsed_seconds(commit_lock_started_seconds, commit_lock_finished_seconds));
        if (!commit_locked)
        {
            rc = LANTERN_CLIENT_ERR_RUNTIME;
        }
        else if (client->state.validator_count == 0u)
        {
            lantern_client_unlock_state(client, commit_locked);
            rc = LANTERN_CLIENT_ERR_RUNTIME;
        }
        else
        {
            (void)lantern_store_remove_new_aggregated_payloads_matching(
                &client->store,
                &store_snapshot.new_aggregated_payloads);

            for (size_t i = 0; i < out_payloads->length; ++i)
            {
                const struct lantern_aggregated_payload_entry *entry = &out_payloads->entries[i];
                int add_rc = lantern_store_add_new_aggregated_payload(
                    &client->store,
                    &entry->data_root,
                    &entry->data,
                    &entry->proof);
                if (add_rc != 0)
                {
                    rc = LANTERN_CLIENT_ERR_ALLOC;
                    break;
                }
                (void)lantern_store_remove_attestation_signatures_for_data_root(
                    &client->store,
                    &entry->data_root);
            }
            lantern_client_unlock_state(client, commit_locked);
        }
    }

    lantern_state_reset(&state_snapshot);
    lantern_store_reset(&store_snapshot);

    if (rc != LANTERN_CLIENT_OK)
    {
        lantern_aggregated_payload_pool_reset(out_payloads);
    }
    return rc;
}

/* ============================================================================
 * Mutex Utilities
 * ============================================================================ */

/* ============================================================================
 * Validator Service Checks
 * ============================================================================ */

/**
 * Check if the validator service should run.
 *
 * @param client  Client instance
 * @return true if service should run, false otherwise
 *
 * @note Thread safety: This function is thread-safe
 */
/* ============================================================================
 * Vote Signing and Storage
 * ============================================================================ */

/**
 * Check whether a slot is within a prepared XMSS interval.
 *
 * @param prepared Prepared interval returned by pq_get_prepared_interval()
 * @param slot     Slot/epoch to test
 * @return true when slot is signable by the currently prepared key state
 */
static bool validator_slot_in_prepared_interval(struct PQRange prepared, uint64_t slot)
{
    return prepared.start <= slot && slot < prepared.end;
}

static bool validator_signature_history_find_slot(
    const struct lantern_validator_signature_history *history,
    uint64_t slot,
    size_t *out_index)
{
    size_t lo = 0u;
    size_t hi = history ? history->length : 0u;
    while (lo < hi)
    {
        size_t mid = lo + ((hi - lo) / 2u);
        if (history->records[mid].slot < slot)
        {
            lo = mid + 1u;
        }
        else
        {
            hi = mid;
        }
    }
    if (out_index)
    {
        *out_index = lo;
    }
    return history
        && lo < history->length
        && history->records[lo].slot == slot;
}

static lantern_client_error validator_signature_history_reserve(
    struct lantern_validator_signature_history *history)
{
    if (!history)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    if (history->length < history->capacity)
    {
        return LANTERN_CLIENT_OK;
    }
    size_t new_capacity = history->capacity == 0u ? 8u : history->capacity * 2u;
    if (new_capacity <= history->capacity
        || new_capacity > SIZE_MAX / sizeof(*history->records))
    {
        return LANTERN_CLIENT_ERR_ALLOC;
    }
    struct lantern_validator_signature_record *records =
        realloc(history->records, new_capacity * sizeof(*history->records));
    if (!records)
    {
        return LANTERN_CLIENT_ERR_ALLOC;
    }
    history->records = records;
    history->capacity = new_capacity;
    return LANTERN_CLIENT_OK;
}

/*
 * Retain enough records to guard every slot a key could still legitimately
 * re-sign: proposals may sign shortly before their slot opens and cached-vote
 * refresh stays at the vote's own slot, so a few hundred slots is generous. Resident keys
 * cannot sign below their advanced prepared interval, so pruned slots stay
 * unsignable; only file-loaded proposal keys rely on the history alone, and
 * proposals never reach back through this window.
 */
#define LANTERN_SIGNATURE_HISTORY_RETENTION_SLOTS UINT64_C(256)

static void validator_signature_history_prune(
    struct lantern_validator_signature_history *history)
{
    if (!history || history->length == 0u)
    {
        return;
    }
    uint64_t newest_slot = history->records[history->length - 1u].slot;
    if (newest_slot <= LANTERN_SIGNATURE_HISTORY_RETENTION_SLOTS)
    {
        return;
    }
    uint64_t min_slot = newest_slot - LANTERN_SIGNATURE_HISTORY_RETENTION_SLOTS;
    size_t keep_from = 0u;
    while (keep_from < history->length && history->records[keep_from].slot < min_slot)
    {
        keep_from += 1u;
    }
    if (keep_from == 0u)
    {
        return;
    }
    history->length -= keep_from;
    memmove(
        history->records,
        &history->records[keep_from],
        history->length * sizeof(*history->records));
}

static void validator_signature_history_insert(
    struct lantern_validator_signature_history *history,
    size_t index,
    uint64_t slot,
    const LanternRoot *message,
    const LanternSignature *signature)
{
    if (!history || !message || !signature || index > history->length)
    {
        return;
    }
    if (index < history->length)
    {
        memmove(
            &history->records[index + 1u],
            &history->records[index],
            (history->length - index) * sizeof(*history->records));
    }
    history->records[index].slot = slot;
    history->records[index].message = *message;
    history->records[index].signature = *signature;
    history->length += 1u;
    validator_signature_history_prune(history);
}

static void validator_log_signature_reuse_conflict(
    const struct lantern_local_validator *validator,
    uint64_t slot,
    const LanternRoot *recorded_message,
    const LanternRoot *requested_message,
    bool use_proposal_key)
{
    char recorded_hex[2 * LANTERN_ROOT_SIZE + 3];
    char requested_hex[2 * LANTERN_ROOT_SIZE + 3];
    format_root_hex(recorded_message, recorded_hex, sizeof(recorded_hex));
    format_root_hex(requested_message, requested_hex, sizeof(requested_hex));
    lantern_log_warn(
        "validator",
        NULL,
        "slot %" PRIu64 ", skipped, reason: xmss_key_reuse_conflict"
        ", validator %" PRIu64 ", key %s, signed_root %s, requested_root %s",
        slot,
        validator ? validator->global_index : 0u,
        use_proposal_key ? "proposal" : "attestation",
        recorded_hex[0] ? recorded_hex : "0x0",
        requested_hex[0] ? requested_hex : "0x0");
}


/**
 * Sign a message root with one of a validator's XMSS keys.
 *
 * Enforces the leanSig one-time-key rule for the selected key domain: a slot
 * may sign one message root. Repeating the identical root is idempotent and
 * returns the cached signature without invoking XMSS again.
 *
 * Advances the selected key until it can sign for `slot`, mutating resident
 * keys in place. Proposal keys may be loaded for one signature from
 * `proposal_secret_path` so their Merkle trees are not kept resident.
 *
 * @param validator         Local validator
 * @param slot              Slot number
 * @param message           Message root to sign
 * @param use_proposal_key  When true, sign with proposal_secret_key; otherwise
 *                          sign with attestation_secret_key
 * @param out_signature     Output signature
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM on NULL inputs
 * @return LANTERN_CLIENT_ERR_VALIDATOR on missing keys, signing failure, or
 *         an attempted different message for an already-signed slot
 *
 * @note Thread safety: Caller must ensure exclusive access to validator
 */
int validator_sign_with_key(
    struct lantern_local_validator *validator,
    uint64_t slot,
    const LanternRoot *message,
    bool use_proposal_key,
    LanternSignature *out_signature)
{
    if (!validator || !message || !out_signature)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    struct lantern_validator_signature_history *history = use_proposal_key
        ? &validator->proposal_signature_history
        : &validator->attestation_signature_history;
    size_t history_index = 0u;
    if (validator_signature_history_find_slot(history, slot, &history_index))
    {
        struct lantern_validator_signature_record *record = &history->records[history_index];
        if (memcmp(record->message.bytes, message->bytes, LANTERN_ROOT_SIZE) != 0)
        {
            validator_log_signature_reuse_conflict(
                validator,
                slot,
                &record->message,
                message,
                use_proposal_key);
            return LANTERN_CLIENT_ERR_VALIDATOR;
        }
        *out_signature = record->signature;
        return LANTERN_CLIENT_OK;
    }
    lantern_client_error reserve_rc = validator_signature_history_reserve(history);
    if (reserve_rc != LANTERN_CLIENT_OK)
    {
        return reserve_rc;
    }

    struct PQSignatureSchemeSecretKey *temporary_proposal_key = NULL;
    struct PQSignatureSchemeSecretKey *selected_key =
        use_proposal_key ? validator->proposal_secret_key : validator->attestation_secret_key;
    bool free_selected_key = false;
    if (use_proposal_key && !selected_key && validator->proposal_secret_path)
    {
        if (lantern_xmss_load_secret_file(validator->proposal_secret_path, &temporary_proposal_key) != 0)
        {
            return LANTERN_CLIENT_ERR_VALIDATOR;
        }
        selected_key = temporary_proposal_key;
        free_selected_key = true;
    }
    if (!selected_key)
    {
        return LANTERN_CLIENT_ERR_VALIDATOR;
    }

    int result = LANTERN_CLIENT_OK;
    struct PQRange prepared = pq_get_prepared_interval(selected_key);
    if (prepared.end <= prepared.start)
    {
        result = LANTERN_CLIENT_ERR_VALIDATOR;
        goto cleanup;
    }
    if (slot < prepared.start)
    {
        result = LANTERN_CLIENT_ERR_VALIDATOR;
        goto cleanup;
    }

    while (!validator_slot_in_prepared_interval(prepared, slot))
    {
        uint64_t previous_start = prepared.start;
        uint64_t previous_end = prepared.end;
        pq_advance_preparation(selected_key);
        prepared = pq_get_prepared_interval(selected_key);
        if (prepared.end <= prepared.start
            || (prepared.start == previous_start && prepared.end == previous_end)
            || slot < prepared.start)
        {
            result = LANTERN_CLIENT_ERR_VALIDATOR;
            goto cleanup;
        }
    }

    if (!lantern_signature_sign(selected_key, slot, message, out_signature))
    {
        result = LANTERN_CLIENT_ERR_VALIDATOR;
        goto cleanup;
    }
    validator_signature_history_insert(
        history,
        history_index,
        slot,
        message,
        out_signature);

cleanup:
    if (free_selected_key && temporary_proposal_key)
    {
        pq_secret_key_free(temporary_proposal_key);
    }
    return result;
}


static lantern_client_error validator_build_block_merge_proof_with_state(
    const LanternState *state,
    uint64_t proposer_index,
    const LanternRoot *block_root,
    const struct lantern_aggregated_payload_pool *attestation_payloads,
    const LanternSignature *proposer_signature,
    LanternSignedBlock *out_block)
{
    if (!state || !block_root || !attestation_payloads || !proposer_signature || !out_block)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    if (proposer_index >= LANTERN_VALIDATOR_REGISTRY_LIMIT)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    LanternAggregatedSignatureProof proposer_proof;
    struct lantern_bitlist proposer_participants;
    lantern_aggregated_signature_proof_init(&proposer_proof);
    lantern_bitlist_init(&proposer_participants);

    lantern_client_error result = LANTERN_CLIENT_OK;
    if (!state->validators || proposer_index >= state->validator_count)
    {
        result = LANTERN_CLIENT_ERR_VALIDATOR;
        goto cleanup;
    }
    const uint8_t *proposer_pubkey = state->validators[proposer_index].proposal_pubkey;
    if (lantern_validator_pubkey_is_zero(proposer_pubkey))
    {
        result = LANTERN_CLIENT_ERR_VALIDATOR;
        goto cleanup;
    }
    if (lantern_bitlist_resize(&proposer_participants, (size_t)proposer_index + 1u) != 0
        || lantern_bitlist_set(&proposer_participants, (size_t)proposer_index, true) != 0)
    {
        result = LANTERN_CLIENT_ERR_ALLOC;
        goto cleanup;
    }

    LanternRawXmssSignature raw_proposer = {
        .pubkey = proposer_pubkey,
        .signature = proposer_signature,
    };
    if (!lantern_aggregated_signature_proof_aggregate(
            state,
            &proposer_participants,
            NULL,
            0u,
            &raw_proposer,
            1u,
            block_root,
            out_block->block.slot,
            &proposer_proof))
    {
        result = LANTERN_CLIENT_ERR_VALIDATOR;
        goto cleanup;
    }
    if (!lantern_signature_merge_block_type2_proof(
            state,
            &out_block->block,
            attestation_payloads,
            &proposer_proof,
            &out_block->proof))
    {
        result = LANTERN_CLIENT_ERR_VALIDATOR;
        goto cleanup;
    }

cleanup:
    lantern_bitlist_reset(&proposer_participants);
    lantern_aggregated_signature_proof_reset(&proposer_proof);
    return result;
}

static void block_proposal_job_free(struct lantern_async_block_proposal_job *job)
{
    if (!job)
    {
        return;
    }
    lantern_aggregated_payload_pool_reset(&job->attestation_payloads);
    lantern_state_reset(&job->post_state);
    lantern_state_reset(&job->proof_state);
    lantern_signed_block_reset(&job->block);
    free(job);
}

static bool block_proposal_worker_can_accept(
    struct lantern_client *client,
    uint64_t slot,
    bool *out_active)
{
    bool can_accept = false;
    if (out_active)
    {
        *out_active = true;
    }
    if (!client || !client->block_proposal_sync_initialized
        || pthread_mutex_lock(&client->block_proposal_lock) != 0)
    {
        return false;
    }
    if (out_active)
    {
        *out_active = client->block_proposal_job
            && client->block_proposal_job->block.block.slot == slot;
    }
    can_accept = !client->block_proposal_stop && !client->block_proposal_job;
    pthread_mutex_unlock(&client->block_proposal_lock);
    return can_accept;
}

static lantern_client_error validator_prepare_block_proposal_job(
    struct lantern_client *client,
    uint64_t slot,
    size_t local_index,
    struct lantern_async_block_proposal_job **out_job)
{
    if (out_job)
    {
        *out_job = NULL;
    }
    if (!client || !out_job)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    if (local_index >= client->local_validator_count || !client->local_validators)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    struct lantern_async_block_proposal_job *job = calloc(1u, sizeof(*job));
    if (!job)
    {
        return LANTERN_CLIENT_ERR_ALLOC;
    }
    job->client = client;
    job->local_index = local_index;
    job->build_started_seconds = lantern_time_now_seconds();
    lantern_signed_block_init(&job->block);
    lantern_state_init(&job->proof_state);
    lantern_state_init(&job->post_state);
    lantern_signature_zero(&job->proposer_signature);

    LanternRoot parent_root;
    double collect_started_seconds = lantern_time_now_seconds();
    double collect_finished_seconds = collect_started_seconds;
    lantern_client_error result = LANTERN_CLIENT_OK;
    struct lantern_local_validator *local = &client->local_validators[local_index];

    double lock_started_seconds = lantern_time_now_seconds();
    bool state_locked = lantern_client_lock_state(client);
    double lock_finished_seconds = lantern_time_now_seconds();
    validator_add_stage_seconds(
        &job->stage_timings.lock_waits_seconds,
        validator_elapsed_seconds(lock_started_seconds, lock_finished_seconds));
    if (!state_locked)
    {
        result = LANTERN_CLIENT_ERR_RUNTIME;
        goto cleanup;
    }

    if (client->state.validator_count == 0u)
    {
        result = LANTERN_CLIENT_ERR_RUNTIME;
        lantern_client_unlock_state(client, state_locked);
        goto cleanup;
    }

    if (lantern_state_select_block_parent(&client->state, &client->store, &parent_root) != 0)
    {
        result = LANTERN_CLIENT_ERR_RUNTIME;
        lantern_client_unlock_state(client, state_locked);
        goto cleanup;
    }
    double collection_started_seconds = lantern_time_now_seconds();
    if (lantern_state_collect_attestations_for_block(
            &client->state,
            &client->store,
            slot,
            local->global_index,
            &parent_root,
            &job->block.block.body.attestations,
            &job->attestation_payloads)
        != 0)
    {
        result = LANTERN_CLIENT_ERR_RUNTIME;
        lantern_client_unlock_state(client, state_locked);
        goto cleanup;
    }
    double collection_finished_for_stage_seconds = lantern_time_now_seconds();
    validator_add_stage_seconds(
        &job->stage_timings.vote_collection_seconds,
        validator_elapsed_seconds(collection_started_seconds, collection_finished_for_stage_seconds));
    collect_finished_seconds = lantern_time_now_seconds();

    job->block.block.slot = slot;
    job->block.block.proposer_index = local->global_index;
    job->block.block.parent_root = parent_root;

    LanternRoot computed_state_root;
    double other_started_seconds = lantern_time_now_seconds();
    if (lantern_state_compute_post_state(
            &client->state,
            &client->store,
            &job->block,
            &job->post_state,
            &computed_state_root)
        != 0)
    {
        result = LANTERN_CLIENT_ERR_RUNTIME;
        lantern_client_unlock_state(client, state_locked);
        goto cleanup;
    }
    job->block.block.state_root = computed_state_root;

    if (lantern_state_clone(&client->state, &job->proof_state) != 0)
    {
        result = LANTERN_CLIENT_ERR_ALLOC;
        lantern_client_unlock_state(client, state_locked);
        goto cleanup;
    }
    double other_finished_seconds = lantern_time_now_seconds();
    validator_add_stage_seconds(
        &job->stage_timings.other_prover_setup_seconds,
        validator_elapsed_seconds(other_started_seconds, other_finished_seconds));
    lantern_client_unlock_state(client, state_locked);
    state_locked = false;

    other_started_seconds = lantern_time_now_seconds();
    if (lantern_hash_tree_root_block(&job->block.block, &job->block_root) != SSZ_SUCCESS)
    {
        result = LANTERN_CLIENT_ERR_RUNTIME;
        goto cleanup;
    }
    if (validator_sign_with_key(
            local,
            slot,
            &job->block_root,
            true,
            &job->proposer_signature)
        != LANTERN_CLIENT_OK)
    {
        result = LANTERN_CLIENT_ERR_VALIDATOR;
        goto cleanup;
    }
    other_finished_seconds = lantern_time_now_seconds();
    validator_add_stage_seconds(
        &job->stage_timings.other_prover_setup_seconds,
        validator_elapsed_seconds(other_started_seconds, other_finished_seconds));

    lean_metrics_record_block_aggregated_payloads(job->block.block.body.attestations.length);
    lean_metrics_record_block_building_payload_aggregation_time(
        validator_elapsed_seconds(collect_started_seconds, collect_finished_seconds));

    *out_job = job;
    job = NULL;

cleanup:
    if (result != LANTERN_CLIENT_OK)
    {
        lean_metrics_record_block_building_failure();
    }
    block_proposal_job_free(job);
    return result;
}

static int enqueue_block_proposal_job(
    struct lantern_client *client,
    struct lantern_async_block_proposal_job *job)
{
    if (!client || !job)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    if (!client->block_proposal_sync_initialized)
    {
        return LANTERN_CLIENT_ERR_RUNTIME;
    }
    if (pthread_mutex_lock(&client->block_proposal_lock) != 0)
    {
        return LANTERN_CLIENT_ERR_RUNTIME;
    }
    if (client->block_proposal_stop)
    {
        pthread_mutex_unlock(&client->block_proposal_lock);
        return LANTERN_CLIENT_ERR_RUNTIME;
    }
    if (client->block_proposal_job)
    {
        pthread_mutex_unlock(&client->block_proposal_lock);
        return LANTERN_CLIENT_ERR_IGNORED;
    }
    client->block_proposal_job = job;
    pthread_cond_signal(&client->block_proposal_cond);
    pthread_mutex_unlock(&client->block_proposal_lock);
    return LANTERN_CLIENT_OK;
}

static bool block_proposal_local_success_recorded(
    struct lantern_client *client,
    size_t local_index,
    uint64_t slot)
{
    bool recorded = false;
    if (!client || !client->validator_lock_initialized)
    {
        return false;
    }
    if (pthread_mutex_lock(&client->validator_lock) != 0)
    {
        return false;
    }
    if (local_index < client->local_validator_count)
    {
        recorded = client->local_validators[local_index].last_proposed_slot == slot;
    }
    lantern_client_unlock_mutex(
        &client->validator_lock, client->node_id, "validator_lock", "validator");
    return recorded;
}

static int block_proposal_commit_and_log(struct lantern_async_block_proposal_job *job)
{
    if (!job || !job->client)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    struct lantern_client *client = job->client;
    uint64_t slot = job->block.block.slot;
    char root_hex[2 * LANTERN_ROOT_SIZE + 3];
    format_root_hex(&job->block_root, root_hex, sizeof(root_hex));
    uint64_t slot_start_milliseconds = 0u;
    if (lantern_slot_clock_slot_start_time(
               client->state.config.genesis_time,
               slot,
               &slot_start_milliseconds)
            != 0)
    {
        lantern_log_warn(
            "propose",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "slot %" PRIu64 ", skipped, reason: slot_boundary_unavailable",
            slot);
        return LANTERN_CLIENT_ERR_RUNTIME;
    }

    for (;;)
    {
        if (!client->block_proposal_sync_initialized
            || pthread_mutex_lock(&client->block_proposal_lock) != 0)
        {
            return LANTERN_CLIENT_ERR_RUNTIME;
        }
        bool stopping = client->block_proposal_stop;
        pthread_mutex_unlock(&client->block_proposal_lock);
        if (stopping)
        {
            return LANTERN_CLIENT_ERR_IGNORED;
        }

        uint64_t now_milliseconds = validator_wall_time_now_millis();
        if (now_milliseconds >= slot_start_milliseconds)
        {
            break;
        }
        uint64_t delay_milliseconds = slot_start_milliseconds - now_milliseconds;
        uint32_t sleep_milliseconds = delay_milliseconds > BLOCK_PROPOSAL_BOUNDARY_WAIT_SLICE_MS
            ? BLOCK_PROPOSAL_BOUNDARY_WAIT_SLICE_MS
            : (uint32_t)delay_milliseconds;
        validator_sleep_ms(sleep_milliseconds);
    }

    int rc = lantern_client_commit_and_publish_local_block(
        client,
        &job->block,
        &job->block_root,
        &job->post_state);
    if (rc == LANTERN_CLIENT_OK)
    {
        if (client->validator_lock_initialized
            && pthread_mutex_lock(&client->validator_lock) == 0)
        {
            if (job->local_index < client->local_validator_count)
            {
                client->local_validators[job->local_index].last_proposed_slot = slot;
            }
            lantern_client_unlock_mutex(
                &client->validator_lock, client->node_id, "validator_lock", "validator");
        }
        lantern_log_info(
            "propose",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "slot %" PRIu64 ", %s, %zu attestations",
            slot,
            root_hex[0] ? root_hex : "0x0",
            job->block.block.body.attestations.length);
    }
    else
    {
        lantern_log_warn(
            "propose",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "slot %" PRIu64 ", skipped, reason: publish_failed, rc %d",
            slot,
            rc);
    }
    return rc;
}

static int finish_block_proposal_job(struct lantern_async_block_proposal_job *job)
{
    if (!job || !job->client)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    struct lantern_client *client = job->client;
    char root_hex[2 * LANTERN_ROOT_SIZE + 3];
    format_root_hex(&job->block_root, root_hex, sizeof(root_hex));

    double proof_started_seconds = lantern_time_now_seconds();
    lantern_signature_set_stage_timings(&job->stage_timings);
    lantern_client_error proof_rc = validator_build_block_merge_proof_with_state(
        &job->proof_state,
        job->block.block.proposer_index,
        &job->block_root,
        &job->attestation_payloads,
        &job->proposer_signature,
        &job->block);
    lantern_signature_set_stage_timings(NULL);
    double proof_finished_seconds = lantern_time_now_seconds();
    double proof_seconds = validator_elapsed_seconds(proof_started_seconds, proof_finished_seconds);
    double total_seconds =
        validator_elapsed_seconds(job->build_started_seconds, proof_finished_seconds);

    if (proof_rc != LANTERN_CLIENT_OK)
    {
        lean_metrics_record_block_building_failure();
        lantern_log_warn(
            "propose",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "slot %" PRIu64 ", skipped, reason: proof_failed, rc %d, proof %.3fs",
            job->block.block.slot,
            proof_rc,
            proof_seconds);
        return proof_rc;
    }

    validator_stage_timings_add_remainder(&job->stage_timings, total_seconds);
    lean_metrics_record_block_build_stage_timings(&job->stage_timings);
    lean_metrics_record_block_building_time(total_seconds);
    lean_metrics_record_block_building_success();
    lantern_log_info(
        "propose",
        &(const struct lantern_log_metadata){.validator = client->node_id},
        "slot %" PRIu64 ", %s, proof ready, attestation_count=%zu, proof %.3fs, total %.3fs",
        job->block.block.slot,
        root_hex[0] ? root_hex : "0x0",
        job->block.block.body.attestations.length,
        proof_seconds,
        total_seconds);

    return LANTERN_CLIENT_OK;
}

static void *block_proposal_worker_main(void *arg)
{
    struct lantern_client *client = arg;
    if (!client)
    {
        return NULL;
    }

    for (;;)
    {
        if (pthread_mutex_lock(&client->block_proposal_lock) != 0)
        {
            break;
        }
        while (!client->block_proposal_stop && !client->block_proposal_job)
        {
            (void)pthread_cond_wait(&client->block_proposal_cond, &client->block_proposal_lock);
        }
        if (client->block_proposal_stop)
        {
            struct lantern_async_block_proposal_job *queued = client->block_proposal_job;
            client->block_proposal_job = NULL;
            pthread_mutex_unlock(&client->block_proposal_lock);
            block_proposal_job_free(queued);
            break;
        }
        struct lantern_async_block_proposal_job *job = client->block_proposal_job;
        pthread_mutex_unlock(&client->block_proposal_lock);

        if (finish_block_proposal_job(job) == LANTERN_CLIENT_OK)
        {
            (void)block_proposal_commit_and_log(job);
        }
        if (pthread_mutex_lock(&client->block_proposal_lock) != 0)
        {
            break;
        }
        client->block_proposal_job = NULL;
        pthread_mutex_unlock(&client->block_proposal_lock);
        block_proposal_job_free(job);
    }
    return NULL;
}

/**
 * Publish a vote to the network and cache it for staged aggregation.
 *
 * @param client  Client instance
 * @param vote    Vote to publish
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM on NULL inputs
 * @return LANTERN_CLIENT_ERR_NETWORK if gossip publish fails
 *
 * @note Thread safety: This function is thread-safe
 */
int validator_publish_vote(struct lantern_client *client, const LanternSignedVote *vote)
{
    if (!client || !vote)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    struct lantern_log_metadata meta = {.validator = client->node_id};
    bool state_locked = lantern_client_lock_state(client);
    if (!state_locked)
    {
        return LANTERN_CLIENT_ERR_RUNTIME;
    }

    LanternRoot data_root;
    if (lantern_hash_tree_root_attestation_data(&vote->data.data, &data_root) == SSZ_SUCCESS)
    {
        LanternSignatureKey key = {
            .validator_index = vote->data.validator_id,
            .data_root = data_root,
        };
        if (lantern_store_set_attestation_signature(
                &client->store,
                &key,
                &vote->data.data,
                &vote->signature)
            != 0)
        {
            lantern_log_debug(
                "validator",
                &meta,
                "failed to cache local vote for aggregation validator=%" PRIu64 " slot=%" PRIu64,
                vote->data.validator_id,
                vote->data.slot);
        }
    }
    lantern_client_unlock_state(client, state_locked);

    size_t subnet_id = 0;
    if (lantern_validator_index_compute_subnet_id(
            vote->data.validator_id,
            lantern_client_attestation_committee_count(client),
            &subnet_id)
        == 0) {
        if (lantern_gossipsub_service_publish_vote_subnet(&client->gossip, vote, subnet_id) != 0) {
            lantern_log_warn(
                "gossip",
                &meta,
                "failed to publish subnet attestation validator=%" PRIu64 " slot=%" PRIu64 " subnet=%zu",
                vote->data.validator_id,
                vote->data.slot,
                subnet_id);
            return LANTERN_CLIENT_ERR_NETWORK;
        }
    } else {
        lantern_log_warn(
            "gossip",
            &meta,
            "failed to compute attestation subnet validator=%" PRIu64 " slot=%" PRIu64,
            vote->data.validator_id,
            vote->data.slot);
        return LANTERN_CLIENT_ERR_NETWORK;
    }
    char target_hex[2 * LANTERN_ROOT_SIZE + 3];
    char source_hex[2 * LANTERN_ROOT_SIZE + 3];
    format_root_hex(&vote->data.target.root, target_hex, sizeof(target_hex));
    format_root_hex(&vote->data.source.root, source_hex, sizeof(source_hex));
    lantern_log_info(
        "attest",
        &meta,
        "slot %" PRIu64 ", validator %" PRIu64 ", target %s @ %" PRIu64
        ", source %s @ %" PRIu64,
        vote->data.slot,
        vote->data.validator_id,
        target_hex[0] ? target_hex : "0x0",
        vote->data.target.slot,
        source_hex[0] ? source_hex : "0x0",
        vote->data.source.slot);
    return LANTERN_CLIENT_OK;
}


/**
 * Publish a signed block via gossipsub.
 *
 * Broadcasts the signed block to all connected peers via the gossipsub
 * network. Logs the block root and attestation count on success.
 *
 * @param client  Client with an active gossip service
 * @param block   Signed block to publish
 *
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM on NULL parameters
 * @return LANTERN_CLIENT_ERR_NETWORK if gossip is inactive or publish fails
 *
 * @note Thread safety: Acquires gossip lock internally
 */
int lantern_client_publish_block(struct lantern_client *client, const LanternSignedBlock *block)
{
    if (!client || !block)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    if (lantern_gossipsub_service_publish_block(&client->gossip, block) != 0)
    {
        lantern_log_error(
            "propose",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "slot %" PRIu64 ", skipped, reason: publish_failed",
            block->block.slot);
        return LANTERN_CLIENT_ERR_NETWORK;
    }

    LanternRoot block_root;
    char root_hex[2 * LANTERN_ROOT_SIZE + 3];
    if (lantern_hash_tree_root_block(&block->block, &block_root) == SSZ_SUCCESS)
    {
        format_root_hex(&block_root, root_hex, sizeof(root_hex));
    }
    else
    {
        root_hex[0] = '\0';
    }

    lantern_log_debug(
        "propose",
        &(const struct lantern_log_metadata){.validator = client->node_id},
        "slot %" PRIu64 ", %s, published, attestations %zu",
        block->block.slot,
        root_hex[0] ? root_hex : "0x0",
        block->block.body.attestations.length);
    return LANTERN_CLIENT_OK;
}


/* ============================================================================
 * Block Building and Proposal
 * ============================================================================ */

/**
 * Build a block for a validator.
 *
 * @param client            Client instance
 * @param slot              Slot number
 * @param local_index       Local validator index
 * @param out_block         Output for the built block
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM on bad input
 * @return LANTERN_CLIENT_ERR_RUNTIME on state/runtime errors
 * @return LANTERN_CLIENT_ERR_VALIDATOR on signing failures
 * @return LANTERN_CLIENT_ERR_ALLOC on allocation/copy failures
 *
 * @note Thread safety: This function acquires state_lock
 */
int validator_build_block(
    struct lantern_client *client,
    uint64_t slot,
    size_t local_index,
    LanternSignedBlock *out_block)
{
    if (!out_block)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    lantern_signed_block_init(out_block);
    struct lantern_async_block_proposal_job *job = NULL;
    int rc = validator_prepare_block_proposal_job(client, slot, local_index, &job);
    if (rc == LANTERN_CLIENT_OK)
    {
        rc = finish_block_proposal_job(job);
    }
    if (rc == LANTERN_CLIENT_OK)
    {
        *out_block = job->block;
        lantern_signed_block_init(&job->block);
    }
    block_proposal_job_free(job);
    return rc;
}

static int validator_start_block_proposal_job(
    struct lantern_client *client,
    uint64_t slot,
    size_t local_index)
{
    struct lantern_async_block_proposal_job *job = NULL;
    int rc = validator_prepare_block_proposal_job(client, slot, local_index, &job);
    if (rc != LANTERN_CLIENT_OK)
    {
        return rc;
    }

    rc = enqueue_block_proposal_job(client, job);
    if (rc == LANTERN_CLIENT_OK)
    {
        job = NULL;
    }
    block_proposal_job_free(job);
    return rc;
}


/**
 * Propose a block for a validator.
 *
 * @param client       Client instance
 * @param slot         Slot number
 * @param local_index  Local validator index
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_RUNTIME if validator service prerequisites are
 *         not met
 * @return Propagated error codes from validator_build_block() or
 *         lantern_client_publish_block()
 *
 * @note Thread safety: This function acquires validator_lock
 */
int validator_propose_block(struct lantern_client *client, uint64_t slot, size_t local_index)
{
    if (!client)
    {
        return LANTERN_CLIENT_ERR_RUNTIME;
    }
    if (slot == 0u)
    {
        validator_log_duty_skipped(client, slot, "genesis_slot");
        return LANTERN_CLIENT_OK;
    }

    const char *skip_reason = validator_service_skip_reason(client);
    if (skip_reason)
    {
        validator_log_duty_skipped(client, slot, skip_reason);
        return LANTERN_CLIENT_ERR_RUNTIME;
    }
    if (!validator_duty_gate_allows(client, slot, "block"))
    {
        return LANTERN_CLIENT_ERR_RUNTIME;
    }
    if (block_proposal_local_success_recorded(client, local_index, slot))
    {
        return LANTERN_CLIENT_OK;
    }

    bool active = false;
    if (!block_proposal_worker_can_accept(client, slot, &active))
    {
        return active ? LANTERN_CLIENT_OK : LANTERN_CLIENT_ERR_IGNORED;
    }

    return validator_start_block_proposal_job(client, slot, local_index);
}

static bool validator_local_proposer(
    const struct lantern_client *client,
    uint64_t slot,
    size_t *out_local_index)
{
    if (!client || !client->local_validators || client->local_validator_count == 0u
        || client->state.validator_count == 0u)
    {
        return false;
    }
    uint64_t proposer = slot % client->state.validator_count;
    size_t low = 0u;
    size_t high = client->local_validator_count;
    while (low < high)
    {
        size_t middle = low + ((high - low) / 2u);
        uint64_t candidate = client->local_validators[middle].global_index;
        if (candidate == proposer)
        {
            if (out_local_index)
            {
                *out_local_index = middle;
            }
            return true;
        }
        if (candidate < proposer)
        {
            low = middle + 1u;
        }
        else
        {
            high = middle;
        }
    }
    return false;
}

static void validator_maybe_start_next_proposal(
    struct lantern_client *client,
    uint64_t slot)
{
    if (!client || slot == UINT64_MAX)
    {
        return;
    }
    uint64_t next_slot = slot + 1u;
    size_t local_index = 0u;
    if (!validator_local_proposer(client, next_slot, &local_index))
    {
        return;
    }

    if (next_slot > UINT64_MAX / LANTERN_INTERVALS_PER_SLOT)
    {
        return;
    }
    uint64_t target_interval = next_slot * LANTERN_INTERVALS_PER_SLOT;

    if (block_proposal_local_success_recorded(client, local_index, next_slot)
        || !block_proposal_worker_can_accept(client, next_slot, NULL)
        || !validator_duty_gate_allows(client, next_slot, "proposal"))
    {
        return;
    }
    if (lantern_client_chain_service_tick_to(client, target_interval, true, NULL, NULL) != 0)
    {
        return;
    }

    (void)validator_start_block_proposal_job(client, next_slot, local_index);
}


/* ============================================================================
 * Attestation Publishing
 * ============================================================================ */

/**
 * Publish attestations for all enabled validators.
 *
 * @param client  Client instance
 * @param slot    Slot number
 * @return LANTERN_CLIENT_OK on success (even if individual publishes fail)
 * @return LANTERN_CLIENT_ERR_RUNTIME when prerequisites are not satisfied or
 *         locks fail
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM when inputs are NULL or no local
 *         validators are configured
 *
 * @note Thread safety: This function acquires state_lock and validator_lock
 */
int validator_publish_attestations(struct lantern_client *client, uint64_t slot)
{
    lantern_client_error result = LANTERN_CLIENT_OK;

    const char *skip_reason = validator_service_skip_reason(client);
    if (skip_reason)
    {
        validator_log_duty_skipped(client, slot, skip_reason);
        return LANTERN_CLIENT_ERR_RUNTIME;
    }
    if (!validator_duty_gate_allows(client, slot, "attestation"))
    {
        return LANTERN_CLIENT_ERR_RUNTIME;
    }
    if (!client->local_validators || client->local_validator_count == 0)
    {
        validator_log_duty_skipped(client, slot, "validators_not_loaded");
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    LanternCheckpoint head_cp;
    LanternCheckpoint target_cp;
    LanternCheckpoint source_cp;
    bool state_locked = lantern_client_lock_state(client);
    if (!state_locked)
    {
        validator_log_duty_skipped(client, slot, "state_lock_failed");
        return LANTERN_CLIENT_ERR_RUNTIME;
    }
    if (lantern_fork_choice_recompute_head(&client->store) != 0)
    {
        lantern_client_unlock_state(client, state_locked);
        validator_log_duty_skipped(client, slot, "head_recompute_failed");
        return LANTERN_CLIENT_ERR_RUNTIME;
    }
    if (lantern_state_compute_vote_checkpoints(
            &client->state,
            &client->store,
            &head_cp,
            &target_cp,
            &source_cp)
        != 0)
    {
        lantern_client_unlock_state(client, state_locked);
        validator_log_duty_skipped(client, slot, "checkpoint_compute_failed");
        return LANTERN_CLIENT_ERR_RUNTIME;
    }
    lantern_client_unlock_state(client, state_locked);
    bool have_lock = false;
    if (client->validator_lock_initialized)
    {
        if (pthread_mutex_lock(&client->validator_lock) != 0)
        {
            validator_log_duty_skipped(client, slot, "validator_lock_failed");
            return LANTERN_CLIENT_ERR_RUNTIME;
        }
        have_lock = true;
    }

    for (size_t i = 0; i < client->local_validator_count; ++i)
    {
        struct lantern_local_validator *validator = &client->local_validators[i];
        if (validator_signature_history_find_slot(
                &validator->attestation_signature_history,
                slot,
                NULL))
        {
            continue;
        }
        double production_start = lantern_time_now_seconds();
        LanternSignedVote vote;
        memset(&vote, 0, sizeof(vote));
        vote.data.validator_id = validator->global_index;
        vote.data.slot = slot;
        vote.data.head = head_cp;
        vote.data.target = target_cp;
        vote.data.source = source_cp;
        LanternRoot vote_root;
        int sign_rc = lantern_hash_tree_root_attestation_data(&vote.data.data, &vote_root)
                == SSZ_SUCCESS
            ? validator_sign_with_key(validator, slot, &vote_root, false, &vote.signature)
            : LANTERN_CLIENT_ERR_VALIDATOR;
        if (sign_rc != LANTERN_CLIENT_OK)
        {
            lantern_log_warn(
                "duty",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "slot %" PRIu64 ", skipped, reason: attestation_sign_failed, validator %" PRIu64
                ", rc %d",
                slot,
                validator->global_index,
                sign_rc);
            if (result == LANTERN_CLIENT_OK)
            {
                result = (lantern_client_error)sign_rc;
            }
            continue;
        }

        int publish_rc = validator_publish_vote(client, &vote);
        if (publish_rc != LANTERN_CLIENT_OK)
        {
            lantern_log_warn(
                "duty",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "slot %" PRIu64 ", skipped, reason: attestation_publish_failed, validator %" PRIu64
                ", rc %d",
                slot,
                validator->global_index,
                publish_rc);
            if (result == LANTERN_CLIENT_OK)
            {
                result = (lantern_client_error)publish_rc;
            }
        }
        lean_metrics_record_attestations_production_time(
            lantern_time_now_seconds() - production_start);
    }

    if (have_lock)
    {
        lantern_client_unlock_mutex(
            &client->validator_lock, client->node_id, "validator_lock", "validator");
    }
    return result;
}

static lean_metrics_aggregator_skipped_reason_t validator_aggregator_skipped_reason(
    lantern_client_error result,
    bool missing_state)
{
    switch (result)
    {
        case LANTERN_CLIENT_ERR_ALLOC:
            return LEAN_METRICS_AGGREGATOR_SKIPPED_SPAWN_FAILED;
        case LANTERN_CLIENT_ERR_IGNORED:
        case LANTERN_CLIENT_ERR_RUNTIME:
            return missing_state
                ? LEAN_METRICS_AGGREGATOR_SKIPPED_MISSING_STATE
                : LEAN_METRICS_AGGREGATOR_SKIPPED_OTHER;
        case LANTERN_CLIENT_ERR_INVALID_PARAM:
        case LANTERN_CLIENT_ERR_CONFIG:
        case LANTERN_CLIENT_ERR_STORAGE:
        case LANTERN_CLIENT_ERR_GENESIS:
        case LANTERN_CLIENT_ERR_VALIDATOR:
        case LANTERN_CLIENT_ERR_NETWORK:
        case LANTERN_CLIENT_OK:
        default:
            return LEAN_METRICS_AGGREGATOR_SKIPPED_OTHER;
    }
}

int validator_publish_aggregated_attestations(struct lantern_client *client, uint64_t slot)
{
    if (!client || !client->assigned_validators || !client->assigned_validators->enr.is_aggregator) {
        if (client) {
            (void)validator_record_aggregation_skipped_once(
                client,
                slot,
                LEAN_METRICS_AGGREGATOR_SKIPPED_NOT_AGGREGATOR);
        }
        return LANTERN_CLIENT_ERR_RUNTIME;
    }

    struct lantern_aggregated_payload_pool aggregated_payloads = {0};

    double aggregation_started_seconds = lantern_time_now_seconds();
    bool missing_state = false;
    lantern_client_error result = validator_collect_and_aggregate_attestation_signatures(
        client,
        &aggregated_payloads,
        &slot,
        NULL,
        &missing_state);
    size_t successful_aggregations = 0u;
    double aggregation_finished_seconds = lantern_time_now_seconds();
    double aggregation_seconds =
        validator_elapsed_seconds(aggregation_started_seconds, aggregation_finished_seconds);
    uint64_t aggregated_attestations_total = 0;
    if (result == LANTERN_CLIENT_OK) {
        aggregated_attestations_total = (uint64_t)aggregated_payloads.length;
    }
    lean_metrics_record_committee_signature_aggregation(
        aggregation_seconds,
        aggregated_attestations_total);
    if (result != LANTERN_CLIENT_OK) {
        goto cleanup;
    }
    if (aggregated_payloads.length == 0) {
        result = LANTERN_CLIENT_ERR_IGNORED;
        goto cleanup;
    }

    for (size_t i = 0; i < aggregated_payloads.length; ++i) {
        const struct lantern_aggregated_payload_entry *entry = &aggregated_payloads.entries[i];
        const LanternSignedAggregatedAttestation signed_attestation = {
            .data = entry->data,
            .proof = entry->proof,
        };
        if (lantern_gossipsub_service_publish_aggregated_attestation(&client->gossip, &signed_attestation) != 0) {
            result = LANTERN_CLIENT_ERR_NETWORK;
            break;
        }
        successful_aggregations += 1u;
    }
    if (successful_aggregations < aggregated_payloads.length && result == LANTERN_CLIENT_OK) {
        result = LANTERN_CLIENT_ERR_NETWORK;
    }

cleanup:
    (void)0;
    if (result != LANTERN_CLIENT_OK && successful_aggregations == 0u) {
        (void)validator_record_aggregation_skipped_once(
            client,
            slot,
            validator_aggregator_skipped_reason(result, missing_state));
    }
    lantern_aggregated_payload_pool_reset(&aggregated_payloads);
    return result;
}


int lantern_client_chain_service_tick_to(
    struct lantern_client *client,
    uint64_t target_interval,
    bool has_proposal,
    uint64_t *out_skipped_to_interval,
    uint64_t *out_ticked_intervals)
{
    if (out_skipped_to_interval) {
        *out_skipped_to_interval = UINT64_MAX;
    }
    if (out_ticked_intervals) {
        *out_ticked_intervals = 0u;
    }
    if (!client || client->store.block_len == 0u) {
        return -1;
    }

    bool skipped = false;
    for (;;)
    {
        bool state_locked = lantern_client_lock_state(client);
        if (!state_locked) {
            return -1;
        }
        if (client->store.block_len == 0u) {
            lantern_client_unlock_state(client, state_locked);
            return -1;
        }

        uint64_t current_interval = client->store.time_intervals;
        if (current_interval >= target_interval) {
            lantern_client_unlock_state(client, state_locked);
            return 0;
        }

        if (!skipped
            && (target_interval - current_interval) > LANTERN_INTERVALS_PER_SLOT)
        {
            uint64_t skip_to_interval =
                target_interval - LANTERN_INTERVALS_PER_SLOT;
            if (lantern_client_skip_fork_choice_intervals_locked(client, skip_to_interval) != 0) {
                lantern_client_unlock_state(client, state_locked);
                return -1;
            }
            if (out_skipped_to_interval) {
                *out_skipped_to_interval = skip_to_interval;
            }
            skipped = true;
            lantern_client_unlock_state(client, state_locked);
            continue;
        }

        if (lantern_client_tick_fork_choice_interval_locked(client, has_proposal) != 0) {
            lantern_client_unlock_state(client, state_locked);
            return -1;
        }

        uint64_t advanced_interval = client->store.time_intervals;
        lantern_client_unlock_state(client, state_locked);

        if (out_ticked_intervals) {
            *out_ticked_intervals += 1u;
        }
        if (advanced_interval >= target_interval) {
            return 0;
        }

        timing_service_yield();
    }
}

static bool validator_prepare_duties(
    struct lantern_client *client,
    uint64_t total_interval,
    uint64_t *out_slot,
    enum lantern_duty_phase *out_phase,
    size_t *out_local_proposer)
{
    uint64_t slot = total_interval / LANTERN_INTERVALS_PER_SLOT;
    const char *skip_reason = validator_service_skip_reason(client);
    if (skip_reason)
    {
        validator_log_duty_skipped(client, slot, skip_reason);
        return false;
    }

    struct lantern_validator_duty_state *duty = &client->validator_duty;
    uint64_t slot_marker = slot + 1u;
    if (duty->slot_marker != slot_marker)
    {
        duty->slot_marker = slot_marker;
        duty->slot_proposed = false;
        duty->slot_attested = false;
        duty->slot_aggregated = false;
        duty->aggregation_skip_marker = 0u;
    }
    *out_slot = slot;
    *out_phase = (enum lantern_duty_phase)(total_interval % LANTERN_INTERVALS_PER_SLOT);
    *out_local_proposer = SIZE_MAX;
    (void)validator_local_proposer(client, slot, out_local_proposer);
    return true;
}

static void validator_run_duties(
    struct lantern_client *client,
    uint64_t slot,
    enum lantern_duty_phase phase,
    size_t local_proposer)
{
    struct lantern_validator_duty_state *duty = &client->validator_duty;
    switch (phase)
    {
        case LANTERN_DUTY_PHASE_PROPOSAL:
            if (local_proposer != SIZE_MAX && !duty->slot_proposed
                && validator_propose_block(client, slot, local_proposer)
                    == LANTERN_CLIENT_OK)
            {
                duty->slot_proposed = true;
            }
            break;

        case LANTERN_DUTY_PHASE_VOTE:
            if (!duty->slot_attested
                && validator_publish_attestations(client, slot) == LANTERN_CLIENT_OK)
            {
                duty->slot_attested = true;
            }
            break;

        case LANTERN_DUTY_PHASE_AGGREGATE:
            if (!duty->slot_aggregated)
            {
                (void)validator_publish_aggregated_attestations(client, slot);
                duty->slot_aggregated = true;
            }
            break;

        case LANTERN_DUTY_PHASE_VOTE_ACCEPT:
            validator_maybe_start_next_proposal(client, slot);
            break;

        case LANTERN_DUTY_PHASE_SAFE_TARGET:
        default:
            break;
    }
}


/* ============================================================================
 * Chain Scheduler Thread
 * ============================================================================ */

void *timing_thread(void *arg)
{
    struct lantern_client *client = arg;
    if (!client) {
        return NULL;
    }

    while (__atomic_load_n(&client->timing_stop_flag, __ATOMIC_RELAXED) == 0)
    {
        if (client->state.validator_count == 0u
            || client->store.block_len == 0u)
        {
            validator_sleep_ms(TIMING_SERVICE_IDLE_SLEEP_MS);
            continue;
        }

        uint64_t now_milliseconds = validator_wall_time_now_millis();
        uint64_t target_interval = 0u;
        int target_rc = lantern_slot_clock_total_interval(
            client->state.config.genesis_time,
            now_milliseconds,
            &target_interval);
        if (target_rc > 0)
        {
            uint64_t genesis_milliseconds = client->state.config.genesis_time * 1000u;
            uint64_t sleep_milliseconds = TIMING_SERVICE_IDLE_SLEEP_MS;
            if (genesis_milliseconds > now_milliseconds) {
                sleep_milliseconds = genesis_milliseconds - now_milliseconds;
                if (sleep_milliseconds > TIMING_SERVICE_IDLE_SLEEP_MS) {
                    sleep_milliseconds = TIMING_SERVICE_IDLE_SLEEP_MS;
                }
            }
            validator_sleep_ms((uint32_t)sleep_milliseconds);
            continue;
        }
        if (target_rc != 0)
        {
            validator_sleep_ms(TIMING_SERVICE_POLL_SLEEP_MS);
            continue;
        }

        uint64_t duty_slot = 0u;
        enum lantern_duty_phase duty_phase = LANTERN_DUTY_PHASE_PROPOSAL;
        size_t local_proposer = SIZE_MAX;
        bool duties_ready = client->local_validator_count > 0u
            && validator_prepare_duties(
                   client,
                   target_interval,
                   &duty_slot,
                   &duty_phase,
                   &local_proposer);
        uint64_t current_interval = 0u;
        bool state_locked = lantern_client_lock_state(client);
        if (!state_locked)
        {
            validator_sleep_ms(TIMING_SERVICE_POLL_SLEEP_MS);
            continue;
        }
        current_interval = client->store.time_intervals;
        lantern_client_unlock_state(client, state_locked);
        if (current_interval / LANTERN_INTERVALS_PER_SLOT
            < target_interval / LANTERN_INTERVALS_PER_SLOT)
        {
            validator_log_status_for_slot(client, target_interval / LANTERN_INTERVALS_PER_SLOT);
        }

        bool has_proposal = local_proposer != SIZE_MAX
            && !client->validator_duty.slot_proposed;
        bool tick_ok = current_interval >= target_interval
            || lantern_client_chain_service_tick_to(
                   client,
                   target_interval,
                   has_proposal,
                   NULL,
                   NULL)
                   == 0;
        if (tick_ok && duties_ready)
        {
            validator_run_duties(client, duty_slot, duty_phase, local_proposer);
        }

        if (!tick_ok || duties_ready)
        {
            validator_sleep_ms(TIMING_SERVICE_POLL_SLEEP_MS);
            continue;
        }

        uint32_t sleep_milliseconds = timing_service_sleep_until_next_interval(
            client,
            now_milliseconds,
            target_interval);
        if (sleep_milliseconds == 0u) {
            timing_service_yield();
        } else {
            validator_sleep_ms(sleep_milliseconds);
        }
    }

    return NULL;
}


int start_block_proposal_worker(struct lantern_client *client)
{
    if (!client)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    if (client->block_proposal_sync_initialized)
    {
        return LANTERN_CLIENT_OK;
    }
    if (client->local_validator_count == 0)
    {
        return LANTERN_CLIENT_OK;
    }
    if (pthread_mutex_init(&client->block_proposal_lock, NULL) != 0)
    {
        return LANTERN_CLIENT_ERR_RUNTIME;
    }
    if (pthread_cond_init(&client->block_proposal_cond, NULL) != 0)
    {
        pthread_mutex_destroy(&client->block_proposal_lock);
        return LANTERN_CLIENT_ERR_RUNTIME;
    }
    client->block_proposal_sync_initialized = true;

    client->block_proposal_stop = false;
    if (pthread_create(&client->block_proposal_thread, NULL, block_proposal_worker_main, client) != 0)
    {
        client->block_proposal_stop = true;
        pthread_cond_destroy(&client->block_proposal_cond);
        pthread_mutex_destroy(&client->block_proposal_lock);
        client->block_proposal_sync_initialized = false;
        return LANTERN_CLIENT_ERR_RUNTIME;
    }
    lantern_log_info(
        "validator",
        &(const struct lantern_log_metadata){.validator = client->node_id},
        "block proposal worker started");
    return LANTERN_CLIENT_OK;
}

void stop_block_proposal_worker(struct lantern_client *client)
{
    if (!client || !client->block_proposal_sync_initialized)
    {
        return;
    }
    if (pthread_mutex_lock(&client->block_proposal_lock) == 0)
    {
        client->block_proposal_stop = true;
        pthread_cond_broadcast(&client->block_proposal_cond);
        pthread_mutex_unlock(&client->block_proposal_lock);
    }
    int join_rc = pthread_join(client->block_proposal_thread, NULL);
    if (join_rc != 0)
    {
        lantern_log_warn(
            "validator",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "pthread_join failed: %d",
            join_rc);
    }
    block_proposal_job_free(client->block_proposal_job);
    client->block_proposal_job = NULL;
    client->block_proposal_stop = true;

    pthread_cond_destroy(&client->block_proposal_cond);
    pthread_mutex_destroy(&client->block_proposal_lock);
    client->block_proposal_sync_initialized = false;
    lantern_log_info(
        "validator",
        &(const struct lantern_log_metadata){.validator = client->node_id},
        "block proposal worker stopped");
}


/**
 * Start the timing service.
 *
 * @param client  Client instance
 *
 * @return LANTERN_CLIENT_OK on success, or if service is already running or
 *         prerequisites are missing
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM if client is NULL
 * @return LANTERN_CLIENT_ERR_RUNTIME if the thread cannot be created
 *
 * @note Thread safety: This function is thread-safe
 */
static void *prover_prewarm_thread(void *arg)
{
    (void)arg;
    lantern_signature_prewarm_prover();
    return NULL;
}

int start_timing_service(struct lantern_client *client)
{
    if (!client)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    if (client->timing_thread_started)
    {
        return LANTERN_CLIENT_OK;
    }
    if (client->store.block_len == 0u)
    {
        return LANTERN_CLIENT_OK;
    }
    if (client->local_validator_count > 0u)
    {
        pthread_t prewarm_thread;
        if (pthread_create(&prewarm_thread, NULL, prover_prewarm_thread, NULL) == 0)
        {
            (void)pthread_detach(prewarm_thread);
        }
        client->validator_duty = (struct lantern_validator_duty_state){0};
    }

    __atomic_store_n(&client->timing_stop_flag, 0, __ATOMIC_RELAXED);
    if (pthread_create(&client->timing_thread, NULL, timing_thread, client) != 0)
    {
        __atomic_store_n(&client->timing_stop_flag, 1, __ATOMIC_RELAXED);
        lantern_log_warn(
            "forkchoice",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to start timing service thread");
        return LANTERN_CLIENT_ERR_RUNTIME;
    }

    client->timing_thread_started = true;
    lantern_log_info(
        "forkchoice",
        &(const struct lantern_log_metadata){.validator = client->node_id},
        "chain scheduler started");
    return LANTERN_CLIENT_OK;
}


/**
 * Stop the timing service.
 *
 * Signals the timing service thread to stop and waits for it to exit.
 * Safe to call even if the service was never started.
 *
 * @param client  Client instance (may be NULL)
 *
 * @note Thread safety: This function is thread-safe
 */
void stop_timing_service(struct lantern_client *client)
{
    if (!client || !client->timing_thread_started)
    {
        return;
    }

    __atomic_store_n(&client->timing_stop_flag, 1, __ATOMIC_RELAXED);
    int join_rc = pthread_join(client->timing_thread, NULL);
    if (join_rc != 0)
    {
        lantern_log_warn(
            "forkchoice",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "pthread_join failed: %d",
            join_rc);
    }

    client->timing_thread_started = false;
    lantern_log_info(
        "forkchoice",
        &(const struct lantern_log_metadata){.validator = client->node_id},
        "chain scheduler stopped");
}
