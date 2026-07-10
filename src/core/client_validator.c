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
 *       6. peer_vote_lock
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
#include "lantern/consensus/runtime.h"
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

/** Sleep interval when validator service cannot run (ms). */
static const uint32_t VALIDATOR_SERVICE_IDLE_SLEEP_MS = 200;

/** Sleep interval between validator service iterations (ms). */
static const uint32_t VALIDATOR_SERVICE_POLL_SLEEP_MS = 50;

/** Maximum sleep while waiting for a proposal's target slot (ms). */
static const uint32_t BLOCK_PROPOSAL_BOUNDARY_WAIT_SLICE_MS = 1000;

/** Slot lag past which local validator duties are silenced. */
static const uint64_t VALIDATOR_SYNC_LAG_THRESHOLD = 4u;

/** Slot lag past which the network is considered stalled, so duties stay live. */
static const uint64_t VALIDATOR_NETWORK_STALL_THRESHOLD = 8u;

/** Hysteresis band for reopening a closed duty gate. */
static const uint64_t VALIDATOR_SYNC_LAG_HYSTERESIS = 2u;

static size_t validator_attestation_committee_count(const struct lantern_client *client)
{
    return lantern_client_attestation_committee_count(client);
}

void lantern_signature_set_stage_timings(struct lantern_block_build_stage_timings *timings);

static int validator_publish_aggregated_attestations(struct lantern_client *client, uint64_t slot);
static lantern_client_error collect_aggregation_votes(
    struct lantern_client *client,
    LanternAttestations *out_attestations,
    LanternSignatureList *out_signatures,
    const uint64_t *scope_slot,
    struct lantern_block_build_stage_timings *stage_timings,
    bool *out_missing_state);
static lantern_client_error validator_collect_and_aggregate_attestation_signatures(
    struct lantern_client *client,
    LanternAggregatedAttestations *out_attestations,
    LanternAttestationSignatures *out_signatures,
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
    if (duty->have_aggregation_skip_slot && duty->last_aggregation_skip_slot == slot)
    {
        return false;
    }
    lean_metrics_record_aggregator_skipped(reason);
    duty->have_aggregation_skip_slot = true;
    duty->last_aggregation_skip_slot = slot;
    if (duty->have_timepoint && duty->last_slot == slot)
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
    uint64_t slot;
    size_t local_index;
    uint64_t proposer_index;
    double build_started_seconds;
    struct lantern_block_build_stage_timings stage_timings;
    LanternRoot parent_root;
    LanternRoot block_root;
    LanternSignedBlock block;
    LanternState proof_state;
    LanternState post_state;
    LanternStore post_store;
    LanternAttestationSignatures attestation_signatures;
    LanternSignature proposer_signature;
};

static bool timing_service_should_run(const struct lantern_client *client)
{
    if (!client) {
        return false;
    }
    if (client->debug_disable_fork_choice_time) {
        return false;
    }
    if (!client->has_state || !client->has_runtime || !client->has_fork_choice) {
        return false;
    }
    if (!client->fork_choice.initialized || !client->fork_choice.has_anchor) {
        return false;
    }
    return true;
}

static int timing_service_compute_target_interval(
    const struct lantern_client *client,
    uint64_t now_milliseconds,
    uint64_t *out_target_interval,
    uint64_t *out_genesis_milliseconds)
{
    if (!client || !client->has_runtime || !out_target_interval) {
        return -1;
    }

    const struct lantern_slot_clock *clock = &client->runtime.clock;
    if (clock->milliseconds_per_interval == 0 || clock->genesis_time > UINT64_MAX / 1000u) {
        return -1;
    }

    uint64_t genesis_milliseconds = clock->genesis_time * 1000u;
    if (out_genesis_milliseconds) {
        *out_genesis_milliseconds = genesis_milliseconds;
    }
    if (now_milliseconds < genesis_milliseconds) {
        return 1;
    }

    *out_target_interval =
        (now_milliseconds - genesis_milliseconds) / clock->milliseconds_per_interval;
    return 0;
}

static uint32_t timing_service_sleep_until_next_interval(
    const struct lantern_client *client,
    uint64_t now_milliseconds,
    uint64_t target_interval)
{
    if (!client || !client->has_runtime || target_interval == UINT64_MAX) {
        return TIMING_SERVICE_POLL_SLEEP_MS;
    }

    const struct lantern_slot_clock *clock = &client->runtime.clock;
    if (clock->milliseconds_per_interval == 0 || clock->genesis_time > UINT64_MAX / 1000u) {
        return TIMING_SERVICE_POLL_SLEEP_MS;
    }

    uint64_t genesis_milliseconds = clock->genesis_time * 1000u;
    uint64_t next_interval = target_interval + 1u;
    if (next_interval < target_interval
        || next_interval > (UINT64_MAX - genesis_milliseconds) / clock->milliseconds_per_interval) {
        return TIMING_SERVICE_POLL_SLEEP_MS;
    }

    uint64_t next_interval_start =
        genesis_milliseconds + (next_interval * clock->milliseconds_per_interval);
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
        if (client->has_fork_choice
            && lantern_fork_choice_current_head(&client->fork_choice, &head_root) == 0)
        {
            have_head_root = true;
            (void)lantern_fork_choice_block_info(
                &client->fork_choice,
                &head_root,
                &head_slot,
                NULL,
                NULL);
            const LanternCheckpoint *justified =
                lantern_fork_choice_latest_justified(&client->fork_choice);
            const LanternCheckpoint *finalized =
                lantern_fork_choice_latest_finalized(&client->fork_choice);
            justified_slot = justified ? justified->slot : client->state.latest_justified.slot;
            finalized_slot = finalized ? finalized->slot : client->state.latest_finalized.slot;
        }
        else if (client->has_state)
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
    bool has_network_head = false;
    bool has_network_finalized = false;
    uint64_t network_head = 0u;
    uint64_t network_finalized = 0u;
    bool should_log = true;
    if (client->status_lock_initialized
        && pthread_mutex_lock(&client->status_lock) == 0)
    {
        if (client->has_last_status_log_slot && client->last_status_log_slot == slot)
        {
            should_log = false;
        }
        else
        {
            client->last_status_log_slot = slot;
            client->has_last_status_log_slot = true;
        }
        sync_state = client->sync_state;
        has_network_head = client->network_view.has_latest_observed_head_slot;
        has_network_finalized = client->network_view.has_network_finalized_slot;
        network_head = client->network_view.latest_observed_head_slot;
        network_finalized = client->network_view.network_finalized_slot;
        pthread_mutex_unlock(&client->status_lock);
    }
    else if (client->has_last_status_log_slot && client->last_status_log_slot == slot)
    {
        should_log = false;
    }
    else
    {
        client->last_status_log_slot = slot;
        client->has_last_status_log_slot = true;
        has_network_head = client->network_view.has_latest_observed_head_slot;
        has_network_finalized = client->network_view.has_network_finalized_slot;
        network_head = client->network_view.latest_observed_head_slot;
        network_finalized = client->network_view.network_finalized_slot;
    }

    if (!should_log)
    {
        return;
    }

    char head_root_hex[2 * LANTERN_ROOT_SIZE + 3];
    char network_head_text[32];
    char network_finalized_text[32];
    format_root_hex(have_head_root ? &head_root : NULL, head_root_hex, sizeof(head_root_hex));
    format_slot_text(network_head_text, sizeof(network_head_text), has_network_head, network_head);
    format_slot_text(
        network_finalized_text,
        sizeof(network_finalized_text),
        has_network_finalized,
        network_finalized);
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
    if (!client->has_state)
    {
        return "state_not_ready";
    }
    if (!client->has_runtime)
    {
        return "runtime_not_ready";
    }
    if (!client->has_fork_choice)
    {
        return "fork_choice_not_ready";
    }
    if (!client->gossip_running)
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

    uint64_t head_slot = 0u;
    uint64_t max_seen_slot = 0u;
    bool have_head_slot = false;
    bool state_locked = lantern_client_lock_state(client);
    if (!state_locked)
    {
        validator_log_duty_skipped(client, slot, "duty_gate_state_lock_failed");
        return false;
    }

    if (client->has_fork_choice)
    {
        LanternRoot head_root;
        if (lantern_fork_choice_recompute_head(&client->fork_choice) != 0)
        {
            lantern_client_unlock_state(client, state_locked);
            validator_log_duty_skipped(client, slot, "duty_gate_head_recompute_failed");
            return false;
        }
        if (lantern_fork_choice_current_head(&client->fork_choice, &head_root) == 0
            && lantern_fork_choice_block_info(
                   &client->fork_choice,
                   &head_root,
                   &head_slot,
                   NULL,
                   NULL)
                   == 0)
        {
            have_head_slot = true;
            max_seen_slot = head_slot;
        }

        if (client->fork_choice.blocks)
        {
            for (size_t i = 0; i < client->fork_choice.block_len; ++i)
            {
                uint64_t block_slot = client->fork_choice.blocks[i].slot;
                if (!have_head_slot || block_slot > max_seen_slot)
                {
                    max_seen_slot = block_slot;
                }
            }
        }
    }
    else if (client->has_state)
    {
        head_slot = client->state.slot;
        max_seen_slot = head_slot;
        have_head_slot = true;
    }
    lantern_client_unlock_state(client, state_locked);

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
        if (client->has_last_duty_skip_slot
            && client->last_duty_skip_slot == slot
            && client->last_duty_skip_reason
            && strcmp(client->last_duty_skip_reason, reason) == 0)
        {
            should_log = false;
        }
        else
        {
            client->last_duty_skip_slot = slot;
            client->has_last_duty_skip_slot = true;
            client->last_duty_skip_reason = reason;
        }
        pthread_mutex_unlock(&client->status_lock);
    }
    else if (client->has_last_duty_skip_slot
             && client->last_duty_skip_slot == slot
             && client->last_duty_skip_reason
             && strcmp(client->last_duty_skip_reason, reason) == 0)
    {
        should_log = false;
    }
    else
    {
        client->last_duty_skip_slot = slot;
        client->has_last_duty_skip_slot = true;
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

static void payload_pool_snapshot_reset(struct lantern_aggregated_payload_pool *pool)
{
    if (!pool)
    {
        return;
    }
    for (size_t i = 0; i < pool->length; ++i)
    {
        lantern_aggregated_signature_proof_reset(&pool->entries[i].proof);
    }
    free(pool->entries);
    pool->entries = NULL;
    pool->length = 0;
    pool->capacity = 0;
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
        dst->entries[i].target_slot = src->entries[i].target_slot;
        lantern_aggregated_signature_proof_init(&dst->entries[i].proof);
        dst->length = i + 1u;
        if (lantern_aggregated_signature_proof_copy(
                &dst->entries[i].proof,
                &src->entries[i].proof)
            != 0)
        {
            payload_pool_snapshot_reset(dst);
            return -1;
        }
    }
    return 0;
}

static lantern_client_error aggregate_attestation_signatures(
    struct lantern_client *client,
    const LanternAttestations *att_list,
    const LanternSignatureList *att_signatures,
    LanternAggregatedAttestations *out_attestations,
    LanternAttestationSignatures *out_signatures,
    const uint64_t *scope_slot,
    struct lantern_block_build_stage_timings *stage_timings)
{
    if (!client || !att_list || !att_signatures || !out_attestations || !out_signatures)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
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
    if (!client->has_state)
    {
        lantern_client_unlock_state(client, state_locked);
        return LANTERN_CLIENT_ERR_RUNTIME;
    }

    LanternState state_snapshot;
    LanternStore data_snapshot;
    struct lantern_aggregated_payload_pool new_snapshot;
    struct lantern_aggregated_payload_pool known_snapshot;
    memset(&new_snapshot, 0, sizeof(new_snapshot));
    memset(&known_snapshot, 0, sizeof(known_snapshot));
    lantern_store_init(&data_snapshot);

    bool raw_only = scope_slot != NULL;
    int snapshot_rc = lantern_state_clone(&client->state, &state_snapshot);
    double other_started_seconds = lantern_time_now_seconds();
    if (!raw_only && snapshot_rc == 0)
    {
        snapshot_rc = payload_pool_snapshot(&new_snapshot, &client->store.new_aggregated_payloads);
    }
    if (!raw_only && snapshot_rc == 0)
    {
        snapshot_rc =
            payload_pool_snapshot(&known_snapshot, &client->store.known_aggregated_payloads);
    }
    if (!raw_only && snapshot_rc == 0)
    {
        for (size_t i = 0; i < new_snapshot.length; ++i)
        {
            LanternAttestationData data;
            memset(&data, 0, sizeof(data));
            if (lantern_store_get_attestation_data(
                    &client->store,
                    &new_snapshot.entries[i].data_root,
                    &data)
                != 0)
            {
                continue;
            }
            if (lantern_store_add_attestation_data(
                    &data_snapshot,
                    &new_snapshot.entries[i].data_root,
                    &data,
                    new_snapshot.entries[i].target_slot)
                != 0)
            {
                snapshot_rc = -1;
                break;
            }
        }
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
        LanternAttestationSignatureInputs attestation_signatures = {
            .attestations = att_list,
            .signatures = att_signatures,
        };
        lantern_signature_set_stage_timings(stage_timings);
        lantern_state_aggregate_result aggregate_result = lantern_state_aggregate(
            &state_snapshot,
            raw_only ? NULL : &data_snapshot,
            &attestation_signatures,
            raw_only ? NULL : &new_snapshot,
            raw_only ? NULL : &known_snapshot,
            out_attestations,
            out_signatures);
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
        else if (!client->has_state)
        {
            lantern_client_unlock_state(client, commit_locked);
            rc = LANTERN_CLIENT_ERR_RUNTIME;
        }
        else
        {
            (void)lantern_store_remove_new_aggregated_payloads_matching(&client->store, &new_snapshot);

            for (size_t i = 0; i < out_attestations->length; ++i)
            {
                LanternRoot data_root;
                if (lantern_hash_tree_root_attestation_data(&out_attestations->data[i].data, &data_root) != SSZ_SUCCESS)
                {
                    rc = LANTERN_CLIENT_ERR_VALIDATOR;
                    break;
                }
                int add_rc = lantern_store_add_new_aggregated_payload(
                    &client->store,
                    &data_root,
                    &out_attestations->data[i].data,
                    &out_signatures->data[i],
                    out_attestations->data[i].data.target.slot);
                if (add_rc != 0)
                {
                    rc = LANTERN_CLIENT_ERR_ALLOC;
                    break;
                }
                (void)lantern_store_remove_attestation_signatures_for_data_root(&client->store, &data_root);
            }
            lantern_client_unlock_state(client, commit_locked);
        }
    }

    lantern_state_reset(&state_snapshot);
    lantern_store_reset(&data_snapshot);
    payload_pool_snapshot_reset(&new_snapshot);
    payload_pool_snapshot_reset(&known_snapshot);

    if (rc != LANTERN_CLIENT_OK)
    {
        (void)lantern_aggregated_attestations_resize(out_attestations, 0);
        (void)lantern_attestation_signatures_resize(out_signatures, 0);
    }
    return rc;
}

lantern_client_error lantern_client_debug_aggregate_attestation_signatures(
    struct lantern_client *client,
    LanternAggregatedAttestations *out_attestations,
    LanternAttestationSignatures *out_signatures)
{
    return validator_collect_and_aggregate_attestation_signatures(
        client,
        out_attestations,
        out_signatures,
        NULL,
        NULL,
        NULL);
}

int lantern_client_debug_publish_aggregated_attestations(
    struct lantern_client *client,
    uint64_t slot)
{
    return validator_publish_aggregated_attestations(client, slot);
}

int lantern_client_debug_run_interval_aggregation(
    struct lantern_client *client,
    uint64_t slot)
{
    if (!client) {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    if (client->validator_duty.slot_aggregated || !client->validator_duty.slot_attested) {
        return LANTERN_CLIENT_ERR_IGNORED;
    }

    int rc = validator_publish_aggregated_attestations(client, slot);
    if (rc == LANTERN_CLIENT_OK) {
        client->validator_duty.slot_aggregated = true;
    }
    return rc;
}


/* ============================================================================
 * Mutex Utilities
 * ============================================================================ */

/**
 * @brief Unlock a mutex and log on failure.
 *
 * @note Thread safety: This function is thread-safe
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
            "validator",
            &(const struct lantern_log_metadata){.validator = validator_id},
            "failed to unlock %s: %d",
            name,
            unlock_rc);
    }
}


/* ============================================================================
 * Validator Duty State
 * ============================================================================ */

/**
 * Reset validator duty state.
 *
 * @param state  Duty state to reset
 *
 * @note Thread safety: This function is thread-safe
 */
void validator_duty_state_reset(struct lantern_validator_duty_state *state)
{
    if (!state)
    {
        return;
    }
    memset(state, 0, sizeof(*state));
}

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
bool validator_service_should_run(const struct lantern_client *client)
{
    return validator_service_skip_reason(client) == NULL;
}


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


/**
 * Sign a vote with a validator's attestation secret key.
 *
 * @param validator  Local validator
 * @param slot       Slot number
 * @param vote       Vote to sign (modified in place)
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM on NULL inputs
 * @return LANTERN_CLIENT_ERR_VALIDATOR on hashing or signing failure
 *
 * @note Thread safety: Caller must ensure exclusive access to the validator
 */
int validator_sign_vote(
    struct lantern_local_validator *validator,
    uint64_t slot,
    LanternSignedVote *vote)
{
    if (!validator || !vote)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    LanternRoot vote_root;
    if (lantern_hash_tree_root_attestation_data(&vote->data.data, &vote_root) != SSZ_SUCCESS)
    {
        return LANTERN_CLIENT_ERR_VALIDATOR;
    }
    return validator_sign_with_key(
        validator,
        slot,
        &vote_root,
        false,
        &vote->signature);
}


/**
 * @brief Collect parent root and attestations for a new block.
 *
 * Computes the parent root and collects attestations/signatures to include in
 * the proposed block.
 *
 * @param client            Client instance
 * @param slot              Slot number
 * @param local             Local validator
 * @param out_parent_root   Output for selected parent root
 * @param att_list          Initialized attestation list to populate
 * @param att_signatures    Initialized signature list to populate
 *
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_RUNTIME on lock/state errors
 *
 * @note Thread safety: This function acquires state_lock
 */
static lantern_client_error validator_build_block_collect_attestations(
    struct lantern_client *client,
    uint64_t slot,
    struct lantern_local_validator *local,
    LanternRoot *out_parent_root,
    LanternAggregatedAttestations *out_attestations,
    LanternAttestationSignatures *out_signatures)
{
    lantern_client_error result = LANTERN_CLIENT_OK;

    if (!client || !local || !out_parent_root || !out_attestations || !out_signatures)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    bool state_locked = lantern_client_lock_state(client);
    if (!state_locked)
    {
        return LANTERN_CLIENT_ERR_RUNTIME;
    }

    if (!client->has_state)
    {
        result = LANTERN_CLIENT_ERR_RUNTIME;
        goto cleanup;
    }

    if (lantern_state_select_block_parent(&client->state, &client->store, out_parent_root) != 0)
    {
        result = LANTERN_CLIENT_ERR_RUNTIME;
        goto cleanup;
    }

    if (lantern_state_collect_attestations_for_block(
            &client->state,
            &client->store,
            slot,
            local->global_index,
            out_parent_root,
            out_attestations,
            out_signatures)
        != 0)
    {
        result = LANTERN_CLIENT_ERR_RUNTIME;
        goto cleanup;
    }
cleanup:
    lantern_client_unlock_state(client, state_locked);
    return result;
}


/**
 * @brief Populate a signed block from collected attestations and signatures.
 *
 * Initializes the block message fields, copies attestations into the body,
 * and fills the attestation-signature array. The proposer signature is left
 * zeroed so the caller can sign the finalized block root afterward.
 *
 * @param slot           Slot number
 * @param proposer_index Proposer's global validator index
 * @param parent_root    Parent block root
 * @param att_list       Collected attestations
 * @param att_signatures Collected attestation signatures
 * @param out_block      Block to populate
 *
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM on NULL inputs
 * @return LANTERN_CLIENT_ERR_RUNTIME on overflow or inconsistent inputs
 * @return LANTERN_CLIENT_ERR_ALLOC on allocation/copy failures
 *
 * @note Thread safety: This function is thread-safe
 */
static lantern_client_error validator_build_block_populate_message(
    uint64_t slot,
    uint64_t proposer_index,
    const LanternRoot *parent_root,
    const LanternAggregatedAttestations *attestations,
    LanternSignedBlock *out_block)
{
    if (!parent_root || !attestations || !out_block)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    LanternBlock *message_block = &out_block->block;
    message_block->slot = slot;
    message_block->proposer_index = proposer_index;
    message_block->parent_root = *parent_root;
    memset(&message_block->state_root, 0, sizeof(message_block->state_root));

    if (lantern_aggregated_attestations_copy(
            &message_block->body.attestations,
            attestations)
        != 0)
    {
        return LANTERN_CLIENT_ERR_ALLOC;
    }

    return LANTERN_CLIENT_OK;
}


/**
 * @brief Compute the post-state for a built block without mutating client state.
 *
 * Computes the expected post-state root for the proposed block and optionally
 * returns the post-state plus the updated validator-vote cache.
 *
 * @param client         Client instance
 * @param block          Built block to preview
 * @param out_state_root Output for the computed post-state root
 * @param out_post_state Optional output for the computed post-state
 * @param out_post_store Optional output for the computed post-store
 *
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM on NULL inputs
 * @return LANTERN_CLIENT_ERR_RUNTIME on lock/state failures
 *
 * @note Thread safety: This function acquires state_lock
 */
static lantern_client_error validator_build_block_compute_post_state(
    struct lantern_client *client,
    LanternSignedBlock *block,
    LanternRoot *out_state_root,
    LanternState *out_post_state,
    LanternStore *out_post_store)
{
    if (!client || !block || !out_state_root)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    bool state_locked = lantern_client_lock_state(client);
    if (!state_locked)
    {
        return LANTERN_CLIENT_ERR_RUNTIME;
    }

    lantern_client_error result = LANTERN_CLIENT_OK;
    if (lantern_state_compute_post_state(
            &client->state,
            &client->store,
            block,
            out_post_state,
            out_post_store,
            out_state_root)
        != 0)
    {
        result = LANTERN_CLIENT_ERR_RUNTIME;
    }
    lantern_client_unlock_state(client, state_locked);
    return result;
}

static lantern_client_error validator_build_block_merge_proof_with_state(
    const LanternState *state,
    uint64_t proposer_index,
    const LanternRoot *block_root,
    const LanternAttestationSignatures *attestation_proofs,
    const LanternSignature *proposer_signature,
    LanternSignedBlock *out_block)
{
    if (!state || !block_root || !attestation_proofs || !proposer_signature || !out_block)
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
    const uint8_t *proposer_pubkey =
        lantern_state_validator_proposal_pubkey(state, (size_t)proposer_index);
    if (!proposer_pubkey || lantern_validator_pubkey_is_zero(proposer_pubkey))
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
            attestation_proofs,
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

static lantern_client_error validator_build_block_merge_proof(
    struct lantern_client *client,
    const struct lantern_local_validator *local,
    const LanternRoot *block_root,
    const LanternAttestationSignatures *attestation_proofs,
    const LanternSignature *proposer_signature,
    LanternSignedBlock *out_block)
{
    if (!client || !local || !block_root || !attestation_proofs || !proposer_signature || !out_block)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    LanternState proof_state;
    lantern_state_init(&proof_state);
    bool state_locked = lantern_client_lock_state(client);
    if (!state_locked)
    {
        return LANTERN_CLIENT_ERR_RUNTIME;
    }
    int clone_rc = lantern_state_clone(&client->state, &proof_state);
    lantern_client_unlock_state(client, state_locked);
    if (clone_rc != 0)
    {
        lantern_state_reset(&proof_state);
        return LANTERN_CLIENT_ERR_ALLOC;
    }

    lantern_client_error result = validator_build_block_merge_proof_with_state(
        &proof_state,
        local->global_index,
        block_root,
        attestation_proofs,
        proposer_signature,
        out_block);
    lantern_state_reset(&proof_state);
    return result;
}

static void block_proposal_job_init(
    struct lantern_async_block_proposal_job *job,
    struct lantern_client *client,
    uint64_t slot,
    size_t local_index)
{
    if (!job)
    {
        return;
    }
    memset(job, 0, sizeof(*job));
    job->client = client;
    job->slot = slot;
    job->local_index = local_index;
    job->build_started_seconds = lantern_time_now_seconds();
    lantern_signed_block_init(&job->block);
    lantern_state_init(&job->proof_state);
    lantern_state_init(&job->post_state);
    lantern_store_init(&job->post_store);
    lantern_attestation_signatures_init(&job->attestation_signatures);
    lantern_signature_zero(&job->proposer_signature);
}

static void block_proposal_job_reset(struct lantern_async_block_proposal_job *job)
{
    if (!job)
    {
        return;
    }
    lantern_attestation_signatures_reset(&job->attestation_signatures);
    lantern_store_reset(&job->post_store);
    lantern_state_reset(&job->post_state);
    lantern_state_reset(&job->proof_state);
    lantern_signed_block_reset(&job->block);
}

static void block_proposal_job_free(struct lantern_async_block_proposal_job *job)
{
    if (!job)
    {
        return;
    }
    block_proposal_job_reset(job);
    free(job);
}

static bool block_proposal_worker_can_accept(struct lantern_client *client)
{
    bool can_accept = false;
    if (!client || !client->block_proposal_lock_initialized
        || pthread_mutex_lock(&client->block_proposal_lock) != 0)
    {
        return false;
    }
    can_accept = client->block_proposal_thread_started
        && !client->block_proposal_stop
        && !client->block_proposal_inflight
        && !client->block_proposal_job;
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
    block_proposal_job_init(job, client, slot, local_index);

    LanternAggregatedAttestations attestations;
    lantern_aggregated_attestations_init(&attestations);
    double collect_started_seconds = lantern_time_now_seconds();
    double collect_finished_seconds = collect_started_seconds;
    lantern_client_error result = LANTERN_CLIENT_OK;
    struct lantern_local_validator *local = &client->local_validators[local_index];
    job->proposer_index = local->global_index;

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

    if (!client->has_state)
    {
        result = LANTERN_CLIENT_ERR_RUNTIME;
        lantern_client_unlock_state(client, state_locked);
        goto cleanup;
    }

    if (lantern_state_select_block_parent(&client->state, &client->store, &job->parent_root) != 0)
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
            &job->parent_root,
            &attestations,
            &job->attestation_signatures)
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

    double other_started_seconds = lantern_time_now_seconds();
    result = validator_build_block_populate_message(
        slot,
        local->global_index,
        &job->parent_root,
        &attestations,
        &job->block);
    if (result != LANTERN_CLIENT_OK)
    {
        lantern_client_unlock_state(client, state_locked);
        goto cleanup;
    }
    double other_finished_seconds = lantern_time_now_seconds();
    validator_add_stage_seconds(
        &job->stage_timings.other_prover_setup_seconds,
        validator_elapsed_seconds(other_started_seconds, other_finished_seconds));

    LanternRoot computed_state_root;
    other_started_seconds = lantern_time_now_seconds();
    if (lantern_state_compute_post_state(
            &client->state,
            &client->store,
            &job->block,
            &job->post_state,
            &job->post_store,
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
    other_finished_seconds = lantern_time_now_seconds();
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

    lean_metrics_record_block_aggregated_payloads(attestations.length);
    lean_metrics_record_block_building_payload_aggregation_time(
        validator_elapsed_seconds(collect_started_seconds, collect_finished_seconds));

    *out_job = job;
    job = NULL;

cleanup:
    if (result != LANTERN_CLIENT_OK)
    {
        lean_metrics_record_block_building_failure();
    }
    lantern_aggregated_attestations_reset(&attestations);
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
    if (!client->block_proposal_thread_started || !client->block_proposal_lock_initialized)
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
    if (client->block_proposal_inflight || client->block_proposal_job)
    {
        pthread_mutex_unlock(&client->block_proposal_lock);
        return LANTERN_CLIENT_ERR_IGNORED;
    }
    client->block_proposal_job = job;
    client->block_proposal_inflight = true;
    client->block_proposal_inflight_slot = job->slot;
    if (client->block_proposal_cond_initialized)
    {
        pthread_cond_signal(&client->block_proposal_cond);
    }
    pthread_mutex_unlock(&client->block_proposal_lock);
    return LANTERN_CLIENT_OK;
}

static void block_proposal_mark_finished(struct lantern_client *client)
{
    if (!client || !client->block_proposal_lock_initialized)
    {
        return;
    }
    if (pthread_mutex_lock(&client->block_proposal_lock) != 0)
    {
        return;
    }
    client->block_proposal_inflight = false;
    client->block_proposal_inflight_slot = 0u;
    if (client->block_proposal_cond_initialized)
    {
        pthread_cond_broadcast(&client->block_proposal_cond);
    }
    pthread_mutex_unlock(&client->block_proposal_lock);
}

static void block_proposal_record_local_success(
    struct lantern_client *client,
    size_t local_index,
    uint64_t slot)
{
    if (!client || !client->validator_lock_initialized)
    {
        return;
    }
    if (pthread_mutex_lock(&client->validator_lock) != 0)
    {
        return;
    }
    if (local_index < client->local_validator_count)
    {
        client->local_validators[local_index].last_proposed_slot = slot;
    }
    unlock_mutex_with_log(&client->validator_lock, client->node_id, "validator_lock");
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
    unlock_mutex_with_log(&client->validator_lock, client->node_id, "validator_lock");
    return recorded;
}

static int block_proposal_commit_and_log(
    struct lantern_async_block_proposal_job *job,
    const char *root_hex)
{
    if (!job || !job->client)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    struct lantern_client *client = job->client;
    uint64_t slot_start_milliseconds = 0u;
    if (!client->has_runtime
        || lantern_slot_clock_slot_start_time(
               &client->runtime.clock,
               job->slot,
               &slot_start_milliseconds)
            != 0)
    {
        lantern_log_warn(
            "propose",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "slot %" PRIu64 ", skipped, reason: slot_boundary_unavailable",
            job->slot);
        return LANTERN_CLIENT_ERR_RUNTIME;
    }

    for (;;)
    {
        if (!client->block_proposal_lock_initialized
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

    int rc = lantern_client_commit_and_publish_current_head_block(
        client,
        &job->block,
        &job->block_root,
        &job->post_state,
        &job->post_store);
    if (rc == LANTERN_CLIENT_OK)
    {
        block_proposal_record_local_success(client, job->local_index, job->slot);
        lantern_log_info(
            "propose",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "slot %" PRIu64 ", %s, %zu attestations",
            job->slot,
            root_hex && root_hex[0] ? root_hex : "0x0",
            job->block.block.body.attestations.length);
    }
    else if (rc == LANTERN_CLIENT_ERR_IGNORED)
    {
        lantern_log_warn(
            "propose",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "slot %" PRIu64 ", skipped, reason: parent_changed_fork_avoided",
            job->slot);
    }
    else
    {
        lantern_log_warn(
            "propose",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "slot %" PRIu64 ", skipped, reason: publish_failed, rc %d",
            job->slot,
            rc);
    }
    return rc;
}

static int process_block_proposal_job(struct lantern_async_block_proposal_job *job)
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
        job->proposer_index,
        &job->block_root,
        &job->attestation_signatures,
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
            job->slot,
            proof_rc,
            proof_seconds);
        return LANTERN_CLIENT_ERR_RUNTIME;
    }

    validator_stage_timings_add_remainder(&job->stage_timings, total_seconds);
    lean_metrics_record_block_build_stage_timings(&job->stage_timings);
    lean_metrics_record_block_building_time(total_seconds);
    lean_metrics_record_block_building_success();
    lantern_log_info(
        "propose",
        &(const struct lantern_log_metadata){.validator = client->node_id},
        "slot %" PRIu64 ", %s, proof ready, attestation_count=%zu, proof %.3fs, total %.3fs",
        job->slot,
        root_hex[0] ? root_hex : "0x0",
        job->block.block.body.attestations.length,
        proof_seconds,
        total_seconds);

    return block_proposal_commit_and_log(job, root_hex);
}

static bool block_proposal_active_for_slot(struct lantern_client *client, uint64_t slot)
{
    bool active = false;
    if (!client)
    {
        return false;
    }
    if (!client->block_proposal_lock_initialized
        || pthread_mutex_lock(&client->block_proposal_lock) != 0)
    {
        return true;
    }
    active = (client->block_proposal_inflight && client->block_proposal_inflight_slot == slot)
        || (client->block_proposal_job && client->block_proposal_job->slot == slot);
    pthread_mutex_unlock(&client->block_proposal_lock);
    return active;
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
            client->block_proposal_inflight = false;
            client->block_proposal_inflight_slot = 0u;
            pthread_mutex_unlock(&client->block_proposal_lock);
            block_proposal_job_free(queued);
            break;
        }
        struct lantern_async_block_proposal_job *job = client->block_proposal_job;
        client->block_proposal_job = NULL;
        pthread_mutex_unlock(&client->block_proposal_lock);

        (void)process_block_proposal_job(job);
        block_proposal_job_free(job);
        block_proposal_mark_finished(client);
    }
    return NULL;
}

static int validator_build_block_internal(
    struct lantern_client *client,
    uint64_t slot,
    size_t local_index,
    LanternSignedBlock *out_block,
    LanternState *out_post_state,
    LanternStore *out_post_store,
    LanternRoot *out_block_root)
{
    lantern_client_error result = LANTERN_CLIENT_OK;
    double build_started_seconds = 0.0;
    double collect_started_seconds = 0.0;
    double collect_finished_seconds = 0.0;
    LanternRoot parent_root = {0};
    LanternAggregatedAttestations attestations;
    LanternAttestationSignatures signatures;
    bool attestations_initialized = false;
    bool signatures_initialized = false;

    if (!client || !out_block)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    if (local_index >= client->local_validator_count || !client->local_validators)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    struct lantern_local_validator *local = &client->local_validators[local_index];
    lantern_signed_block_init(out_block);
    build_started_seconds = lantern_time_now_seconds();

    lantern_aggregated_attestations_init(&attestations);
    attestations_initialized = true;
    lantern_attestation_signatures_init(&signatures);
    signatures_initialized = true;

    collect_started_seconds = lantern_time_now_seconds();
    result = validator_build_block_collect_attestations(
        client,
        slot,
        local,
        &parent_root,
        &attestations,
        &signatures);
    collect_finished_seconds = lantern_time_now_seconds();
    if (result != LANTERN_CLIENT_OK)
    {
        goto cleanup;
    }

    /* TODO: verify that block attestations remain the correct proxy for
     * "aggregated_payloads" in the leanMetrics spec. */
    lean_metrics_record_block_aggregated_payloads(attestations.length);
    lean_metrics_record_block_building_payload_aggregation_time(
        validator_elapsed_seconds(collect_started_seconds, collect_finished_seconds));

    result = validator_build_block_populate_message(
        slot,
        local->global_index,
        &parent_root,
        &attestations,
        out_block);
    if (result != LANTERN_CLIENT_OK)
    {
        goto cleanup;
    }

    LanternRoot computed_state_root;
    result = validator_build_block_compute_post_state(
        client,
        out_block,
        &computed_state_root,
        out_post_state,
        out_post_store);
    if (result != LANTERN_CLIENT_OK)
    {
        goto cleanup;
    }

    out_block->block.state_root = computed_state_root;
    LanternRoot block_root;
    if (lantern_hash_tree_root_block(&out_block->block, &block_root) != SSZ_SUCCESS) {
        result = LANTERN_CLIENT_ERR_RUNTIME;
        goto cleanup;
    }
    if (out_block_root) {
        *out_block_root = block_root;
    }
    LanternSignature proposer_signature;
    lantern_signature_zero(&proposer_signature);
    if (validator_sign_with_key(
            local,
            slot,
            &block_root,
            true,
            &proposer_signature)
        != LANTERN_CLIENT_OK) {
        result = LANTERN_CLIENT_ERR_VALIDATOR;
        goto cleanup;
    }
    result = validator_build_block_merge_proof(
        client,
        local,
        &block_root,
        &signatures,
        &proposer_signature,
        out_block);
    if (result != LANTERN_CLIENT_OK)
    {
        goto cleanup;
    }
    result = LANTERN_CLIENT_OK;

cleanup:
    {
        double build_finished_seconds = lantern_time_now_seconds();
        lean_metrics_record_block_building_time(
            validator_elapsed_seconds(build_started_seconds, build_finished_seconds));
    }
    if (result == LANTERN_CLIENT_OK)
    {
        lean_metrics_record_block_building_success();
    }
    else
    {
        lean_metrics_record_block_building_failure();
    }
    if (attestations_initialized)
    {
        lantern_aggregated_attestations_reset(&attestations);
    }
    if (signatures_initialized)
    {
        lantern_attestation_signatures_reset(&signatures);
    }
    if (result != LANTERN_CLIENT_OK)
    {
        lantern_signed_block_reset(out_block);
        if (out_post_state)
        {
            lantern_state_reset(out_post_state);
            lantern_state_init(out_post_state);
        }
        if (out_post_store)
        {
            lantern_store_reset(out_post_store);
            lantern_store_init(out_post_store);
        }
    }
    return result;
}


/**
 * Refresh a cached vote with updated checkpoints and re-sign if needed.
 *
 * Compares the vote's source checkpoint with the provided source. If they
 * differ, builds a candidate vote and signs it only if the validator has not
 * already used this slot's attestation key for a different message root.
 *
 * @param validator  Local validator with an attestation signing key
 * @param slot       Slot for signing context
 * @param head       New head checkpoint
 * @param target     New target checkpoint
 * @param source     New source checkpoint
 * @param vote       Vote to update (modified in place)
 * @param out_refreshed Optional output flag set to true when the vote is
 *        updated and re-signed
 *
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM on NULL parameters
 * @return LANTERN_CLIENT_ERR_VALIDATOR when the validator key is missing,
 *         signing fails, or refreshing would reuse a slot key for a different
 *         attestation root
 *
 * @note Thread safety: Caller must ensure exclusive access to validator
 */
int lantern_validator_refresh_cached_vote(
    struct lantern_local_validator *validator,
    uint64_t slot,
    const LanternCheckpoint *head,
    const LanternCheckpoint *target,
    const LanternCheckpoint *source,
    LanternSignedVote *vote,
    bool *out_refreshed)
{
    bool refreshed = false;

    if (out_refreshed)
    {
        *out_refreshed = false;
    }
    if (!validator || !head || !target || !source || !vote)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    /* If the source checkpoint is unchanged, no refresh is required. */
    if (vote->data.source.slot != source->slot
        || memcmp(vote->data.source.root.bytes, source->root.bytes, LANTERN_ROOT_SIZE) != 0)
    {
        LanternSignedVote candidate = *vote;
        candidate.data.head = *head;
        candidate.data.target = *target;
        candidate.data.source = *source;

        if (validator_sign_vote(validator, slot, &candidate) != 0)
        {
            return LANTERN_CLIENT_ERR_VALIDATOR;
        }
        *vote = candidate;
        refreshed = true;
    }

    if (out_refreshed)
    {
        *out_refreshed = refreshed;
    }
    return LANTERN_CLIENT_OK;
}


/**
 * Store a vote in the client state.
 *
 * @param client  Client instance
 * @param vote    Vote to store
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM on NULL input or index overflow
 * @return LANTERN_CLIENT_ERR_RUNTIME if state is unavailable or lock fails
 *
 * @note Thread safety: This function acquires state_lock
 */
int validator_store_vote(struct lantern_client *client, const LanternSignedVote *vote)
{
    if (!client || !vote)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    if (!client->has_state)
    {
        return LANTERN_CLIENT_ERR_RUNTIME;
    }
    if (vote->data.validator_id > SIZE_MAX)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    bool state_locked = lantern_client_lock_state(client);
    if (!state_locked)
    {
        return LANTERN_CLIENT_ERR_RUNTIME;
    }
    int rc = lantern_store_set_signed_validator_vote(
        &client->store,
        (size_t)vote->data.validator_id,
        vote);
    lantern_client_unlock_state(client, state_locked);
    if (rc != 0)
    {
        lantern_log_warn(
            "validator",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to store attestation validator=%" PRIu64 " slot=%" PRIu64,
            vote->data.validator_id,
            vote->data.slot);
        return LANTERN_CLIENT_ERR_RUNTIME;
    }
    return LANTERN_CLIENT_OK;
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
                &vote->signature,
                vote->data.target.slot)
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
            validator_attestation_committee_count(client),
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
 * @param client  Client with active gossip service (gossip_running must be true)
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
    if (!client->gossip_running)
    {
        lantern_log_error(
            "propose",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "slot %" PRIu64 ", skipped, reason: gossip_not_running",
            block->block.slot);
        return LANTERN_CLIENT_ERR_NETWORK;
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
    return validator_build_block_internal(
        client,
        slot,
        local_index,
        out_block,
        NULL,
        NULL,
        NULL);
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

    if (block_proposal_active_for_slot(client, slot))
    {
        return LANTERN_CLIENT_OK;
    }
    if (!block_proposal_worker_can_accept(client))
    {
        return LANTERN_CLIENT_ERR_IGNORED;
    }

    return validator_start_block_proposal_job(client, slot, local_index);
}

static void validator_maybe_start_next_proposal(
    struct lantern_client *client,
    const struct lantern_slot_timepoint *tp)
{
    if (!client || !tp || !client->has_runtime || tp->slot == UINT64_MAX)
    {
        return;
    }
    uint64_t next_slot = tp->slot + 1u;
    bool is_local = false;
    uint64_t local_index = 0u;
    if (lantern_consensus_runtime_local_proposer(
            &client->runtime,
            next_slot,
            &is_local,
            &local_index)
        != 0
        || !is_local
        || local_index >= client->local_validator_count)
    {
        return;
    }

    uint64_t intervals_per_slot = client->runtime.clock.intervals_per_slot;
    if (intervals_per_slot == 0u || next_slot > UINT64_MAX / intervals_per_slot)
    {
        return;
    }
    uint64_t target_interval = next_slot * intervals_per_slot;

    if (block_proposal_local_success_recorded(client, (size_t)local_index, next_slot)
        || block_proposal_active_for_slot(client, next_slot)
        || !validator_duty_gate_allows(client, next_slot, "proposal")
        || !block_proposal_worker_can_accept(client))
    {
        return;
    }
    if (lantern_client_chain_service_tick_to(client, target_interval, true, NULL, NULL) != 0)
    {
        return;
    }

    (void)validator_start_block_proposal_job(client, next_slot, (size_t)local_index);
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
    if (lantern_fork_choice_recompute_head(&client->fork_choice) != 0)
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
        bool enabled = client->validator_enabled ? client->validator_enabled[i] : true;
        if (!enabled)
        {
            continue;
        }
        struct lantern_local_validator *validator = &client->local_validators[i];
        if (validator->last_attested_slot == slot)
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
        int sign_rc = validator_sign_vote(validator, slot, &vote);
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
        validator->last_attested_slot = slot;

        int store_rc = validator_store_vote(client, &vote);
        if (store_rc != LANTERN_CLIENT_OK)
        {
            lantern_log_warn(
                "duty",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "slot %" PRIu64 ", skipped, reason: attestation_store_failed, validator %" PRIu64
                ", rc %d",
                slot,
                validator->global_index,
                store_rc);
            if (result == LANTERN_CLIENT_OK)
            {
                result = (lantern_client_error)store_rc;
            }
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
        unlock_mutex_with_log(&client->validator_lock, client->node_id, "validator_lock");
    }
    return result;
}

static lantern_client_error collect_aggregation_votes(
    struct lantern_client *client,
    LanternAttestations *out_attestations,
    LanternSignatureList *out_signatures,
    const uint64_t *scope_slot,
    struct lantern_block_build_stage_timings *stage_timings,
    bool *out_missing_state) {
    if (!client || !out_attestations || !out_signatures) {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    if (out_missing_state) {
        *out_missing_state = false;
    }
    if (lantern_attestations_resize(out_attestations, 0) != 0) {
        return LANTERN_CLIENT_ERR_ALLOC;
    }
    if (lantern_signature_list_resize(out_signatures, 0) != 0) {
        return LANTERN_CLIENT_ERR_ALLOC;
    }

    double lock_started_seconds = lantern_time_now_seconds();
    bool state_locked = lantern_client_lock_state(client);
    double lock_finished_seconds = lantern_time_now_seconds();
    validator_add_stage_seconds(
        stage_timings ? &stage_timings->lock_waits_seconds : NULL,
        validator_elapsed_seconds(lock_started_seconds, lock_finished_seconds));
    if (!state_locked) {
        return LANTERN_CLIENT_ERR_RUNTIME;
    }
    if (!client->has_state) {
        lantern_client_unlock_state(client, state_locked);
        return LANTERN_CLIENT_ERR_RUNTIME;
    }

    lantern_client_error result = LANTERN_CLIENT_OK;
    const struct lantern_attestation_signature_map *map = &client->store.attestation_signatures;
    double collection_started_seconds = lantern_time_now_seconds();
    for (size_t i = 0; i < map->length; ++i) {
        const struct lantern_attestation_signature_entry *entry = &map->entries[i];
        if (scope_slot && entry->attestation_slot != *scope_slot) {
            continue;
        }
        LanternAttestationData data;
        memset(&data, 0, sizeof(data));
        if (lantern_store_get_attestation_data(&client->store, &entry->key.data_root, &data) != 0) {
            if (out_missing_state) {
                *out_missing_state = true;
            }
            continue;
        }
        if (scope_slot && data.slot != *scope_slot) {
            continue;
        }
        LanternVote vote;
        memset(&vote, 0, sizeof(vote));
        vote.validator_id = entry->key.validator_index;
        vote.data = data;
        if (lantern_attestations_append(out_attestations, &vote) != 0
            || lantern_signature_list_append(out_signatures, &entry->signature) != 0) {
            result = LANTERN_CLIENT_ERR_ALLOC;
            break;
        }
    }
    double collection_finished_seconds = lantern_time_now_seconds();
    validator_add_stage_seconds(
        stage_timings ? &stage_timings->vote_collection_seconds : NULL,
        validator_elapsed_seconds(collection_started_seconds, collection_finished_seconds));
    lantern_client_unlock_state(client, state_locked);

    if (result != LANTERN_CLIENT_OK) {
        (void)lantern_attestations_resize(out_attestations, 0);
        (void)lantern_signature_list_resize(out_signatures, 0);
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

static lantern_client_error validator_collect_and_aggregate_attestation_signatures(
    struct lantern_client *client,
    LanternAggregatedAttestations *out_attestations,
    LanternAttestationSignatures *out_signatures,
    const uint64_t *scope_slot,
    struct lantern_block_build_stage_timings *stage_timings,
    bool *out_missing_state)
{
    if (!client || !out_attestations || !out_signatures)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    LanternAttestations attestations;
    LanternSignatureList signatures;
    lantern_attestations_init(&attestations);
    lantern_signature_list_init(&signatures);

    lantern_client_error rc = collect_aggregation_votes(
        client,
        &attestations,
        &signatures,
        scope_slot,
        stage_timings,
        out_missing_state);
    if (rc == LANTERN_CLIENT_OK)
    {
        rc = aggregate_attestation_signatures(
            client,
            &attestations,
            &signatures,
            out_attestations,
            out_signatures,
            scope_slot,
            stage_timings);
    }

    lantern_attestations_reset(&attestations);
    lantern_signature_list_reset(&signatures);
    return rc;
}

static int validator_publish_aggregated_attestations(struct lantern_client *client, uint64_t slot)
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

    LanternAggregatedAttestations aggregated_attestations;
    LanternAttestationSignatures aggregated_signatures;
    lantern_aggregated_attestations_init(&aggregated_attestations);
    lantern_attestation_signatures_init(&aggregated_signatures);

    double aggregation_started_seconds = lantern_time_now_seconds();
    bool missing_state = false;
    lantern_client_error result = validator_collect_and_aggregate_attestation_signatures(
        client,
        &aggregated_attestations,
        &aggregated_signatures,
        &slot,
        NULL,
        &missing_state);
    size_t successful_aggregations = 0u;
    double aggregation_finished_seconds = lantern_time_now_seconds();
    double aggregation_seconds =
        validator_elapsed_seconds(aggregation_started_seconds, aggregation_finished_seconds);
    uint64_t aggregated_attestations_total = 0;
    if (result == LANTERN_CLIENT_OK) {
        aggregated_attestations_total = (uint64_t)aggregated_attestations.length;
    }
    lean_metrics_record_committee_signature_aggregation(
        aggregation_seconds,
        aggregated_attestations_total);
    if (result != LANTERN_CLIENT_OK) {
        goto cleanup;
    }
    if (aggregated_attestations.length == 0 || aggregated_signatures.length == 0) {
        result = LANTERN_CLIENT_ERR_IGNORED;
        goto cleanup;
    }

    size_t count = aggregated_attestations.length;
    if (aggregated_signatures.length < count) {
        count = aggregated_signatures.length;
    }
    for (size_t i = 0; i < count; ++i) {
        LanternSignedAggregatedAttestation signed_attestation;
        lantern_signed_aggregated_attestation_init(&signed_attestation);
        signed_attestation.data = aggregated_attestations.data[i].data;
        if (lantern_aggregated_signature_proof_copy(
                &signed_attestation.proof,
                &aggregated_signatures.data[i])
            != 0) {
            lantern_signed_aggregated_attestation_reset(&signed_attestation);
            result = LANTERN_CLIENT_ERR_ALLOC;
            break;
        }
        if (lantern_gossipsub_service_publish_aggregated_attestation(&client->gossip, &signed_attestation) != 0) {
            lantern_signed_aggregated_attestation_reset(&signed_attestation);
            result = LANTERN_CLIENT_ERR_NETWORK;
            break;
        }
        successful_aggregations += 1u;
        lantern_signed_aggregated_attestation_reset(&signed_attestation);
    }
    if (successful_aggregations < count && result == LANTERN_CLIENT_OK) {
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
    lantern_aggregated_attestations_reset(&aggregated_attestations);
    lantern_attestation_signatures_reset(&aggregated_signatures);
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
    if (!client || !client->has_fork_choice) {
        return -1;
    }

    bool skipped = false;
    for (;;)
    {
        bool state_locked = lantern_client_lock_state(client);
        if (!state_locked) {
            return -1;
        }
        if (!client->has_fork_choice) {
            lantern_client_unlock_state(client, state_locked);
            return -1;
        }

        uint64_t current_interval = client->fork_choice.time_intervals;
        if (current_interval >= target_interval) {
            lantern_client_unlock_state(client, state_locked);
            return 0;
        }

        if (!skipped
            && client->fork_choice.intervals_per_slot > 0
            && (target_interval - current_interval) > client->fork_choice.intervals_per_slot)
        {
            uint64_t skip_to_interval =
                target_interval - (uint64_t)client->fork_choice.intervals_per_slot;
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

        uint64_t advanced_interval = client->fork_choice.time_intervals;
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


/* ============================================================================
 * Timing Service Thread
 * ============================================================================ */

void *timing_thread(void *arg)
{
    struct lantern_client *client = arg;
    if (!client) {
        return NULL;
    }

    while (__atomic_load_n(&client->timing_stop_flag, __ATOMIC_RELAXED) == 0)
    {
        if (!timing_service_should_run(client))
        {
            validator_sleep_ms(TIMING_SERVICE_IDLE_SLEEP_MS);
            continue;
        }

        uint64_t now_milliseconds = validator_wall_time_now_millis();
        uint64_t target_interval = 0u;
        uint64_t genesis_milliseconds = 0u;
        int target_rc = timing_service_compute_target_interval(
            client,
            now_milliseconds,
            &target_interval,
            &genesis_milliseconds);
        if (target_rc > 0)
        {
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

        uint64_t current_interval = 0u;
        uint64_t intervals_per_slot = 0u;
        bool state_locked = lantern_client_lock_state(client);
        if (!state_locked)
        {
            validator_sleep_ms(TIMING_SERVICE_POLL_SLEEP_MS);
            continue;
        }
        current_interval = client->has_fork_choice ? client->fork_choice.time_intervals : 0u;
        intervals_per_slot = client->has_fork_choice ? client->fork_choice.intervals_per_slot : 0u;
        lantern_client_unlock_state(client, state_locked);
        if (intervals_per_slot > 0u)
        {
            validator_log_status_for_slot(client, target_interval / intervals_per_slot);
        }

        if (current_interval >= target_interval)
        {
            uint32_t sleep_milliseconds = timing_service_sleep_until_next_interval(
                client,
                now_milliseconds,
                target_interval);
            if (sleep_milliseconds == 0u) {
                timing_service_yield();
            } else {
                validator_sleep_ms(sleep_milliseconds);
            }
            continue;
        }

        bool has_proposal = client->validator_duty.pending_local_proposal
            && !client->validator_duty.slot_proposed;
        if (lantern_client_chain_service_tick_to(client, target_interval, has_proposal, NULL, NULL) != 0)
        {
            validator_sleep_ms(TIMING_SERVICE_POLL_SLEEP_MS);
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
    if (client->block_proposal_thread_started)
    {
        return LANTERN_CLIENT_OK;
    }
    if (client->local_validator_count == 0 || !client->has_runtime)
    {
        return LANTERN_CLIENT_OK;
    }
    if (!client->block_proposal_lock_initialized)
    {
        if (pthread_mutex_init(&client->block_proposal_lock, NULL) != 0)
        {
            return LANTERN_CLIENT_ERR_RUNTIME;
        }
        client->block_proposal_lock_initialized = true;
    }
    if (!client->block_proposal_cond_initialized)
    {
        if (pthread_cond_init(&client->block_proposal_cond, NULL) != 0)
        {
            pthread_mutex_destroy(&client->block_proposal_lock);
            client->block_proposal_lock_initialized = false;
            return LANTERN_CLIENT_ERR_RUNTIME;
        }
        client->block_proposal_cond_initialized = true;
    }

    client->block_proposal_stop = false;
    client->block_proposal_inflight = false;
    client->block_proposal_inflight_slot = 0u;
    if (pthread_create(&client->block_proposal_thread, NULL, block_proposal_worker_main, client) != 0)
    {
        client->block_proposal_stop = true;
        pthread_cond_destroy(&client->block_proposal_cond);
        pthread_mutex_destroy(&client->block_proposal_lock);
        client->block_proposal_cond_initialized = false;
        client->block_proposal_lock_initialized = false;
        return LANTERN_CLIENT_ERR_RUNTIME;
    }
    client->block_proposal_thread_started = true;
    lantern_log_info(
        "validator",
        &(const struct lantern_log_metadata){.validator = client->node_id},
        "block proposal worker started");
    return LANTERN_CLIENT_OK;
}

void stop_block_proposal_worker(struct lantern_client *client)
{
    if (!client)
    {
        return;
    }
    if (client->block_proposal_lock_initialized
        && pthread_mutex_lock(&client->block_proposal_lock) == 0)
    {
        client->block_proposal_stop = true;
        if (client->block_proposal_cond_initialized)
        {
            pthread_cond_broadcast(&client->block_proposal_cond);
        }
        pthread_mutex_unlock(&client->block_proposal_lock);
    }
    if (client->block_proposal_thread_started)
    {
        int join_rc = pthread_join(client->block_proposal_thread, NULL);
        if (join_rc != 0)
        {
            lantern_log_warn(
                "validator",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "pthread_join failed: %d",
                join_rc);
        }
        client->block_proposal_thread_started = false;
    }
    block_proposal_job_free(client->block_proposal_job);
    client->block_proposal_job = NULL;
    client->block_proposal_inflight = false;
    client->block_proposal_inflight_slot = 0u;
    client->block_proposal_stop = true;

    if (client->block_proposal_cond_initialized)
    {
        pthread_cond_destroy(&client->block_proposal_cond);
        client->block_proposal_cond_initialized = false;
    }
    if (client->block_proposal_lock_initialized)
    {
        pthread_mutex_destroy(&client->block_proposal_lock);
        client->block_proposal_lock_initialized = false;
    }
    lantern_log_info(
        "validator",
        &(const struct lantern_log_metadata){.validator = client->node_id},
        "block proposal worker stopped");
}


/* ============================================================================
 * Validator Service Thread
 * ============================================================================ */

/**
 * Validator service thread function.
 *
 * @param arg  Client instance
 * @return NULL
 *
 * @note Thread safety: This function runs in a separate thread
 */
void *validator_thread(void *arg)
{
    struct lantern_client *client = arg;
    if (!client)
    {
        return NULL;
    }

    while (__atomic_load_n(&client->validator_stop_flag, __ATOMIC_RELAXED) == 0)
    {
        uint64_t now = validator_wall_time_now_millis();
        const char *skip_reason = validator_service_skip_reason(client);
        if (skip_reason)
        {
            uint64_t skip_slot =
                client->validator_duty.have_timepoint ? client->validator_duty.last_slot : 0u;
            validator_log_duty_skipped(client, skip_slot, skip_reason);
            validator_sleep_ms(VALIDATOR_SERVICE_IDLE_SLEEP_MS);
            continue;
        }

        if (client->has_runtime)
        {
            if (lantern_consensus_runtime_update_time(&client->runtime, now) != 0)
            {
                validator_sleep_ms(VALIDATOR_SERVICE_POLL_SLEEP_MS);
                continue;
            }
        }

        const struct lantern_slot_timepoint *tp =
            lantern_consensus_runtime_current_timepoint(&client->runtime);
        if (!tp)
        {
            validator_sleep_ms(VALIDATOR_SERVICE_POLL_SLEEP_MS);
            continue;
        }

        struct lantern_validator_duty_state *duty = &client->validator_duty;
        if (!duty->have_timepoint || duty->last_slot != tp->slot)
        {
            duty->have_timepoint = true;
            duty->last_slot = tp->slot;
            duty->slot_proposed = false;
            duty->slot_attested = false;
            duty->slot_aggregated = false;
            duty->have_aggregation_skip_slot = false;
            duty->pending_local_proposal = false;
            duty->pending_local_index = 0;

            bool is_local = false;
            uint64_t local_index = 0;
            if (lantern_consensus_runtime_local_proposer(
                    &client->runtime,
                    tp->slot,
                    &is_local,
                    &local_index)
                == 0
                && is_local
                && local_index < client->local_validator_count)
            {
                duty->pending_local_proposal = true;
                duty->pending_local_index = local_index;
            }
        }
        duty->last_interval = tp->interval_index;

        switch (tp->phase)
        {
            case LANTERN_DUTY_PHASE_PROPOSAL:
                if (duty->pending_local_proposal && !duty->slot_proposed)
                {
                    if (validator_propose_block(
                            client,
                            tp->slot,
                            (size_t)duty->pending_local_index)
                        == LANTERN_CLIENT_OK)
                    {
                        duty->slot_proposed = true;
                    }
                }
                break;

            case LANTERN_DUTY_PHASE_VOTE:
                if (!duty->slot_attested)
                {
                    if (validator_publish_attestations(client, tp->slot) == LANTERN_CLIENT_OK)
                    {
                        duty->slot_attested = true;
                    }
                }
                break;

            case LANTERN_DUTY_PHASE_AGGREGATE:
                if (!duty->slot_aggregated)
                {
                    (void)validator_publish_aggregated_attestations(client, tp->slot);
                    duty->slot_aggregated = true;
                }
                break;

            case LANTERN_DUTY_PHASE_SAFE_TARGET:
                break;

            case LANTERN_DUTY_PHASE_VOTE_ACCEPT:
                validator_maybe_start_next_proposal(client, tp);
                break;

            default:
                break;
        }

        validator_sleep_ms(VALIDATOR_SERVICE_POLL_SLEEP_MS);
    }
    return NULL;
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
    if (!client->has_runtime || !client->has_fork_choice)
    {
        return LANTERN_CLIENT_OK;
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
        "fork-choice timing service started");
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
        "fork-choice timing service stopped");
}


/**
 * Start the validator service.
 *
 * Spawns the validator service thread which handles block proposals and
 * attestation publishing. The service requires local validators and runtime
 * to be configured. If already started, returns success without action.
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

int start_validator_service(struct lantern_client *client)
{
    if (!client)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    if (client->validator_thread_started)
    {
        return LANTERN_CLIENT_OK;
    }
    if (client->local_validator_count == 0 || !client->has_runtime)
    {
        return LANTERN_CLIENT_OK;
    }
    pthread_t prewarm_thread;
    if (pthread_create(&prewarm_thread, NULL, prover_prewarm_thread, NULL) == 0)
    {
        (void)pthread_detach(prewarm_thread);
    }
    validator_duty_state_reset(&client->validator_duty);
    __atomic_store_n(&client->validator_stop_flag, 0, __ATOMIC_RELAXED);
    if (pthread_create(&client->validator_thread, NULL, validator_thread, client) != 0)
    {
        lantern_log_warn(
            "validator",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to start validator service thread");
        return LANTERN_CLIENT_ERR_RUNTIME;
    }
    client->validator_thread_started = true;
    lantern_log_info(
        "validator",
        &(const struct lantern_log_metadata){.validator = client->node_id},
        "validator service started");
    return LANTERN_CLIENT_OK;
}


/**
 * Stop the validator service.
 *
 * Signals the validator service thread to stop and waits for it to exit.
 * Safe to call even if the service was never started.
 *
 * @param client  Client instance (may be NULL)
 *
 * @note Thread safety: This function is thread-safe
 */
void stop_validator_service(struct lantern_client *client)
{
    if (!client || !client->validator_thread_started)
    {
        return;
    }
    __atomic_store_n(&client->validator_stop_flag, 1, __ATOMIC_RELAXED);
    int join_rc = pthread_join(client->validator_thread, NULL);
    if (join_rc != 0)
    {
        lantern_log_warn(
            "validator",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "pthread_join failed: %d",
            join_rc);
    }
    client->validator_thread_started = false;
    lantern_log_info(
        "validator",
        &(const struct lantern_log_metadata){.validator = client->node_id},
        "validator service stopped");
}
