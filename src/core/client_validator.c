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
#include <stdlib.h>
#include <string.h>

#include "client_internal.h"

#include "lantern/consensus/fork_choice.h"
#include "lantern/consensus/hash.h"
#include "lantern/consensus/runtime.h"
#include "lantern/consensus/signature.h"
#include "lantern/consensus/state.h"
#include "lantern/metrics/lean_metrics.h"
#include "lantern/networking/gossipsub_service.h"
#include "lantern/support/log.h"


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
/** Maximum peer head lag (in slots) before pausing validator duties. */
static const uint64_t VALIDATOR_SYNC_SLOT_LAG = 2;
/** Pending queue size that indicates we're still catching up. */
static const size_t VALIDATOR_SYNC_PENDING_THRESHOLD = 8;
/** Wall clock lag (in slots) tolerated before treating peer status as stale. */
static const uint64_t VALIDATOR_SYNC_WALL_CLOCK_LAG = 16;
/** Devnet-3 committee count for subnet assignment. */
static const size_t DEFAULT_VALIDATOR_ATTESTATION_COMMITTEE_COUNT = 1u;

static size_t validator_attestation_committee_count(const struct lantern_client *client)
{
    if (client && client->debug_attestation_committee_count > 0) {
        return client->debug_attestation_committee_count;
    }
    return DEFAULT_VALIDATOR_ATTESTATION_COMMITTEE_COUNT;
}

static int validator_publish_aggregated_attestations(struct lantern_client *client, uint64_t slot);

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

static bool validator_should_pause_for_sync(const struct lantern_client *client)
{
    if (!client || !client->status_lock_initialized || !client->has_state)
    {
        return false;
    }

    uint64_t local_slot = client->has_state ? client->state.latest_block_header.slot : 0;
    LanternRoot local_head = {0};
    bool have_local_head = false;
    if (client->has_fork_choice
        && lantern_fork_choice_current_head(&client->fork_choice, &local_head) == 0)
    {
        have_local_head = true;
        uint64_t head_slot = 0;
        if (lantern_fork_choice_block_info(
                &client->fork_choice,
                &local_head,
                &head_slot,
                NULL,
                NULL)
            == 0)
        {
            local_slot = head_slot;
        }
    }

    uint64_t max_peer_slot = 0;
    bool have_fresh_status = false;
    bool have_peer_at_or_ahead = false;
    bool head_match_at_or_ahead = false;
    bool any_head_match = false;
    uint64_t now_ms = monotonic_millis();
    static LanternRoot last_head_root = {{0}};
    static bool last_head_root_set = false;
    static uint64_t last_head_match_ms = 0;
    if (have_local_head)
    {
        if (!last_head_root_set
            || memcmp(
                last_head_root.bytes,
                local_head.bytes,
                LANTERN_ROOT_SIZE)
                != 0)
        {
            last_head_root = local_head;
            last_head_root_set = true;
            last_head_match_ms = now_ms;
        }
    }
    pthread_mutex_t *status_lock = (pthread_mutex_t *)&client->status_lock;
    if (pthread_mutex_lock(status_lock) == 0)
    {
        for (size_t i = 0; i < client->peer_status_count; ++i)
        {
            const struct lantern_peer_status_entry *entry = &client->peer_status_entries[i];
            if (!entry->has_status)
            {
                continue;
            }
            if (entry->last_status_ms == 0
                || now_ms < entry->last_status_ms
                || now_ms - entry->last_status_ms > LANTERN_PEER_STATUS_STALE_MS)
            {
                continue;
            }
            have_fresh_status = true;
            if (entry->status.head.slot > max_peer_slot)
            {
                max_peer_slot = entry->status.head.slot;
            }
            if (have_local_head && entry->status.head.slot >= local_slot)
            {
                have_peer_at_or_ahead = true;
                if (memcmp(entry->status.head.root.bytes, local_head.bytes, LANTERN_ROOT_SIZE) == 0)
                {
                    head_match_at_or_ahead = true;
                }
            }
            if (have_local_head
                && memcmp(entry->status.head.root.bytes, local_head.bytes, LANTERN_ROOT_SIZE) == 0)
            {
                any_head_match = true;
            }
        }
        pthread_mutex_unlock(status_lock);
    }

    if (!have_fresh_status)
    {
        bool has_connections = false;
        pthread_mutex_t *connection_lock = (pthread_mutex_t *)&client->connection_lock;
        if (client->connection_lock_initialized
            && pthread_mutex_lock(connection_lock) == 0)
        {
            has_connections = client->connected_peers > 0;
            pthread_mutex_unlock(connection_lock);
        }
        if (has_connections || client->bootnodes.len > 0)
        {
            return true;
        }
        return false;
    }

    uint64_t current_slot = 0;
    if (lantern_client_current_slot(client, &current_slot)
        && current_slot > max_peer_slot + VALIDATOR_SYNC_WALL_CLOCK_LAG)
    {
        return true;
    }

    if (have_peer_at_or_ahead && have_local_head && !head_match_at_or_ahead)
    {
        return true;
    }

    if (have_fresh_status && have_local_head)
    {
        if (any_head_match)
        {
            last_head_match_ms = now_ms;
        }
        else
        {
            uint64_t grace_ms = 0;
            if (client->has_fork_choice && client->fork_choice.seconds_per_slot > 0)
            {
                uint64_t slot_ms = client->fork_choice.seconds_per_slot * 1000u;
                if (slot_ms > UINT64_MAX / 2u)
                {
                    slot_ms = UINT64_MAX / 2u;
                }
                grace_ms = slot_ms * 2u;
            }
            if (grace_ms == 0)
            {
                grace_ms = 8000u;
            }
            if (now_ms > last_head_match_ms + grace_ms)
            {
                return true;
            }
        }
    }

    if (max_peer_slot > local_slot + VALIDATOR_SYNC_SLOT_LAG)
    {
        return true;
    }

    size_t pending = lantern_client_pending_block_count(client);
    if (pending >= VALIDATOR_SYNC_PENDING_THRESHOLD)
    {
        return true;
    }

    return false;
}

static void validator_clear_pending_attestation(struct lantern_local_validator *validator)
{
    if (!validator)
    {
        return;
    }

    validator->has_pending_attestation = false;
    validator->pending_attestation_slot = UINT64_MAX;
    memset(&validator->pending_attestation, 0, sizeof(validator->pending_attestation));
}

/* ============================================================================
 * Aggregation Helpers
 * ============================================================================ */

struct aggregation_group {
    LanternAttestationData data;
    LanternValidatorIndex *validator_ids;
    LanternSignature *signatures;
    size_t count;
    size_t capacity;
    LanternValidatorIndex *all_validator_ids;
    size_t all_count;
    size_t all_capacity;
};

static bool attestation_data_equal(const LanternAttestationData *a, const LanternAttestationData *b)
{
    if (!a || !b)
    {
        return false;
    }
    if (a->slot != b->slot)
    {
        return false;
    }
    if (a->head.slot != b->head.slot
        || memcmp(a->head.root.bytes, b->head.root.bytes, LANTERN_ROOT_SIZE) != 0)
    {
        return false;
    }
    if (a->target.slot != b->target.slot
        || memcmp(a->target.root.bytes, b->target.root.bytes, LANTERN_ROOT_SIZE) != 0)
    {
        return false;
    }
    if (a->source.slot != b->source.slot
        || memcmp(a->source.root.bytes, b->source.root.bytes, LANTERN_ROOT_SIZE) != 0)
    {
        return false;
    }
    return true;
}

static void aggregation_group_init(struct aggregation_group *group)
{
    if (!group)
    {
        return;
    }
    memset(group, 0, sizeof(*group));
}

static void aggregation_group_reset(struct aggregation_group *group)
{
    if (!group)
    {
        return;
    }
    free(group->validator_ids);
    free(group->signatures);
    free(group->all_validator_ids);
    memset(group, 0, sizeof(*group));
}

static int aggregation_group_append(
    struct aggregation_group *group,
    LanternValidatorIndex validator_id,
    const LanternSignature *signature)
{
    if (!group)
    {
        return -1;
    }

    bool in_all = false;
    for (size_t i = 0; i < group->all_count; ++i)
    {
        if (group->all_validator_ids[i] == validator_id)
        {
            in_all = true;
            break;
        }
    }
    if (!in_all)
    {
        size_t required_all = group->all_count + 1u;
        if (group->all_capacity < required_all)
        {
            size_t new_capacity = group->all_capacity == 0 ? 4u : group->all_capacity;
            while (new_capacity < required_all)
            {
                if (new_capacity > (SIZE_MAX / 2u))
                {
                    return -1;
                }
                new_capacity *= 2u;
            }
            LanternValidatorIndex *ids = realloc(group->all_validator_ids, new_capacity * sizeof(*ids));
            if (!ids)
            {
                return -1;
            }
            group->all_validator_ids = ids;
            group->all_capacity = new_capacity;
        }
        group->all_validator_ids[group->all_count] = validator_id;
        group->all_count += 1u;
    }

    if (!signature || lantern_signature_is_zero(signature))
    {
        return 0;
    }

    for (size_t i = 0; i < group->count; ++i)
    {
        if (group->validator_ids[i] == validator_id)
        {
            return 0;
        }
    }

    size_t required = group->count + 1u;
    if (group->capacity < required)
    {
        size_t new_capacity = group->capacity == 0 ? 4u : group->capacity;
        while (new_capacity < required)
        {
            if (new_capacity > (SIZE_MAX / 2u))
            {
                return -1;
            }
            new_capacity *= 2u;
        }
        LanternValidatorIndex *ids = realloc(group->validator_ids, new_capacity * sizeof(*ids));
        if (!ids)
        {
            return -1;
        }
        LanternSignature *sigs = realloc(group->signatures, new_capacity * sizeof(*sigs));
        if (!sigs)
        {
            return -1;
        }
        group->validator_ids = ids;
        group->signatures = sigs;
        group->capacity = new_capacity;
    }
    group->validator_ids[group->count] = validator_id;
    group->signatures[group->count] = *signature;
    group->count += 1u;
    return 0;
}

static struct aggregation_group *aggregation_group_find_or_add(
    struct aggregation_group **groups,
    size_t *group_count,
    size_t *group_capacity,
    const LanternAttestationData *data)
{
    if (!groups || !group_count || !group_capacity || !data)
    {
        return NULL;
    }
    for (size_t i = 0; i < *group_count; ++i)
    {
        if (attestation_data_equal(&(*groups)[i].data, data))
        {
            return &(*groups)[i];
        }
    }
    size_t required = *group_count + 1u;
    if (*group_capacity < required)
    {
        size_t new_capacity = *group_capacity == 0 ? 4u : *group_capacity;
        while (new_capacity < required)
        {
            if (new_capacity > (SIZE_MAX / 2u))
            {
                return NULL;
            }
            new_capacity *= 2u;
        }
        struct aggregation_group *new_groups =
            realloc(*groups, new_capacity * sizeof(*new_groups));
        if (!new_groups)
        {
            return NULL;
        }
        *groups = new_groups;
        *group_capacity = new_capacity;
    }
    struct aggregation_group *group = &(*groups)[*group_count];
    aggregation_group_init(group);
    group->data = *data;
    *group_count += 1u;
    return group;
}

static void aggregation_group_sort(struct aggregation_group *group)
{
    if (!group || group->count < 2)
    {
        return;
    }
    for (size_t i = 1; i < group->count; ++i)
    {
        LanternValidatorIndex key_id = group->validator_ids[i];
        LanternSignature key_sig = group->signatures[i];
        size_t j = i;
        while (j > 0 && group->validator_ids[j - 1] > key_id)
        {
            group->validator_ids[j] = group->validator_ids[j - 1];
            group->signatures[j] = group->signatures[j - 1];
            --j;
        }
        group->validator_ids[j] = key_id;
        group->signatures[j] = key_sig;
    }
}

static int fill_bitlist_from_ids(
    struct lantern_bitlist *bits,
    const LanternValidatorIndex *ids,
    size_t count)
{
    if (!bits || !ids || count == 0)
    {
        return -1;
    }
    LanternValidatorIndices indices;
    lantern_validator_indices_init(&indices);
    if (lantern_validator_indices_resize(&indices, count) != 0)
    {
        lantern_validator_indices_reset(&indices);
        return -1;
    }
    memcpy(indices.data, ids, count * sizeof(*ids));
    int rc = lantern_aggregation_bits_from_validator_indices(bits, &indices);
    lantern_validator_indices_reset(&indices);
    return rc;
}

static lantern_client_error append_group_as_aggregated(
    const LanternState *state,
    const struct aggregation_group *group,
    LanternAggregatedAttestations *out_attestations,
    LanternAttestationSignatures *out_signatures)
{
    if (!state || !group || !out_attestations || !out_signatures)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    if (group->count == 0)
    {
        return LANTERN_CLIENT_OK;
    }

    LanternAggregatedAttestation attestation;
    lantern_aggregated_attestation_init(&attestation);
    attestation.data = group->data;
    if (fill_bitlist_from_ids(&attestation.aggregation_bits, group->validator_ids, group->count) != 0)
    {
        lantern_aggregated_attestation_reset(&attestation);
        return LANTERN_CLIENT_ERR_RUNTIME;
    }

    LanternRoot data_root;
    if (lantern_hash_tree_root_attestation_data(&group->data, &data_root) != 0)
    {
        lantern_aggregated_attestation_reset(&attestation);
        return LANTERN_CLIENT_ERR_VALIDATOR;
    }

    const uint8_t **pubkeys = calloc(group->count, sizeof(*pubkeys));
    LanternSignature *signatures = calloc(group->count, sizeof(*signatures));
    if (!pubkeys || !signatures)
    {
        free(pubkeys);
        free(signatures);
        lantern_aggregated_attestation_reset(&attestation);
        return LANTERN_CLIENT_ERR_ALLOC;
    }
    for (size_t i = 0; i < group->count; ++i)
    {
        const uint8_t *pubkey = lantern_state_validator_pubkey(state, (size_t)group->validator_ids[i]);
        if (!pubkey || lantern_validator_pubkey_is_zero(pubkey))
        {
            free(pubkeys);
            free(signatures);
            lantern_aggregated_attestation_reset(&attestation);
            return LANTERN_CLIENT_ERR_RUNTIME;
        }
        pubkeys[i] = pubkey;
        signatures[i] = group->signatures[i];
    }

    LanternAggregatedSignatureProof proof;
    lantern_aggregated_signature_proof_init(&proof);
    if (fill_bitlist_from_ids(&proof.participants, group->validator_ids, group->count) != 0)
    {
        lantern_aggregated_signature_proof_reset(&proof);
        free(pubkeys);
        free(signatures);
        lantern_aggregated_attestation_reset(&attestation);
        return LANTERN_CLIENT_ERR_RUNTIME;
    }
    if (!lantern_signature_aggregate(
            pubkeys,
            signatures,
            group->count,
            &data_root,
            group->data.slot,
            &proof.proof_data))
    {
        lantern_aggregated_signature_proof_reset(&proof);
        free(pubkeys);
        free(signatures);
        lantern_aggregated_attestation_reset(&attestation);
        return LANTERN_CLIENT_ERR_VALIDATOR;
    }

    free(pubkeys);
    free(signatures);

    if (lantern_aggregated_attestations_append(out_attestations, &attestation) != 0)
    {
        lantern_aggregated_signature_proof_reset(&proof);
        lantern_aggregated_attestation_reset(&attestation);
        return LANTERN_CLIENT_ERR_ALLOC;
    }
    if (lantern_attestation_signatures_append(out_signatures, &proof) != 0)
    {
        lantern_aggregated_signature_proof_reset(&proof);
        lantern_aggregated_attestation_reset(&attestation);
        return LANTERN_CLIENT_ERR_ALLOC;
    }

    lantern_aggregated_signature_proof_reset(&proof);
    lantern_aggregated_attestation_reset(&attestation);
    return LANTERN_CLIENT_OK;
}

static size_t proof_overlap_count(
    const LanternAggregatedSignatureProof *proof,
    const bool *remaining)
{
    if (!proof || !remaining || proof->participants.bit_length == 0 || !proof->participants.bytes)
    {
        return 0;
    }
    size_t count = 0;
    size_t limit = proof->participants.bit_length;
    if (limit > LANTERN_VALIDATOR_REGISTRY_LIMIT)
    {
        limit = LANTERN_VALIDATOR_REGISTRY_LIMIT;
    }
    for (size_t i = 0; i < limit; ++i)
    {
        if (lantern_bitlist_get(&proof->participants, i) && remaining[i])
        {
            count += 1u;
        }
    }
    return count;
}

static void proof_clear_remaining(
    const LanternAggregatedSignatureProof *proof,
    bool *remaining,
    size_t *remaining_count)
{
    if (!proof || !remaining || !remaining_count || proof->participants.bit_length == 0 || !proof->participants.bytes)
    {
        return;
    }
    size_t limit = proof->participants.bit_length;
    if (limit > LANTERN_VALIDATOR_REGISTRY_LIMIT)
    {
        limit = LANTERN_VALIDATOR_REGISTRY_LIMIT;
    }
    for (size_t i = 0; i < limit; ++i)
    {
        if (lantern_bitlist_get(&proof->participants, i) && remaining[i])
        {
            remaining[i] = false;
            if (*remaining_count > 0)
            {
                *remaining_count -= 1u;
            }
        }
    }
}

static lantern_client_error append_cached_proof_as_aggregated(
    const LanternAttestationData *data,
    const LanternAggregatedSignatureProof *proof,
    LanternAggregatedAttestations *out_attestations,
    LanternAttestationSignatures *out_signatures)
{
    if (!data || !proof || !out_attestations || !out_signatures)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    if (proof->participants.bit_length == 0 || !proof->participants.bytes)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    LanternAggregatedAttestation attestation;
    lantern_aggregated_attestation_init(&attestation);
    attestation.data = *data;
    if (lantern_bitlist_resize(&attestation.aggregation_bits, proof->participants.bit_length) != 0)
    {
        lantern_aggregated_attestation_reset(&attestation);
        return LANTERN_CLIENT_ERR_ALLOC;
    }
    size_t byte_len = (proof->participants.bit_length + 7u) / 8u;
    if (byte_len > 0)
    {
        if (!attestation.aggregation_bits.bytes)
        {
            lantern_aggregated_attestation_reset(&attestation);
            return LANTERN_CLIENT_ERR_ALLOC;
        }
        memcpy(attestation.aggregation_bits.bytes, proof->participants.bytes, byte_len);
    }

    if (lantern_aggregated_attestations_append(out_attestations, &attestation) != 0)
    {
        lantern_aggregated_attestation_reset(&attestation);
        return LANTERN_CLIENT_ERR_ALLOC;
    }
    if (lantern_attestation_signatures_append(out_signatures, proof) != 0)
    {
        lantern_aggregated_attestation_reset(&attestation);
        return LANTERN_CLIENT_ERR_ALLOC;
    }

    lantern_aggregated_attestation_reset(&attestation);
    return LANTERN_CLIENT_OK;
}

static bool proof_matches_validator_ids(
    const LanternAggregatedSignatureProof *proof,
    const LanternValidatorIndex *validator_ids,
    size_t validator_count)
{
    if (!proof || !validator_ids || validator_count == 0)
    {
        return false;
    }
    if (proof->participants.bit_length == 0 || !proof->participants.bytes)
    {
        return false;
    }

    size_t limit = proof->participants.bit_length;
    if (limit > LANTERN_VALIDATOR_REGISTRY_LIMIT)
    {
        limit = LANTERN_VALIDATOR_REGISTRY_LIMIT;
    }

    for (size_t i = 0; i < validator_count; ++i)
    {
        uint64_t validator_id = validator_ids[i];
        if (validator_id >= limit)
        {
            return false;
        }
        if (!lantern_bitlist_get(&proof->participants, (size_t)validator_id))
        {
            return false;
        }
    }

    size_t proof_count = 0;
    for (size_t i = 0; i < limit; ++i)
    {
        if (lantern_bitlist_get(&proof->participants, i))
        {
            proof_count += 1u;
        }
    }
    return proof_count == validator_count;
}

static lantern_client_error append_cached_exact_group_proof(
    const struct lantern_client *client,
    const LanternAttestationData *data,
    const LanternRoot *data_root,
    const LanternValidatorIndex *validator_ids,
    size_t validator_count,
    LanternAggregatedAttestations *out_attestations,
    LanternAttestationSignatures *out_signatures,
    bool *out_used_cached)
{
    if (!client || !data || !data_root || !out_attestations || !out_signatures || !out_used_cached)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    *out_used_cached = false;
    if (!validator_ids || validator_count == 0)
    {
        return LANTERN_CLIENT_OK;
    }

    const struct lantern_aggregated_payload_pool *cache =
        &client->store.known_aggregated_payloads;
    if (!cache->entries || cache->length == 0)
    {
        return LANTERN_CLIENT_OK;
    }

    for (size_t i = 0; i < cache->length; ++i)
    {
        if (memcmp(cache->entries[i].data_root.bytes, data_root->bytes, LANTERN_ROOT_SIZE) != 0)
        {
            continue;
        }
        if (!proof_matches_validator_ids(&cache->entries[i].proof, validator_ids, validator_count))
        {
            continue;
        }

        lantern_client_error rc = append_cached_proof_as_aggregated(
            data,
            &cache->entries[i].proof,
            out_attestations,
            out_signatures);
        if (rc != LANTERN_CLIENT_OK)
        {
            return rc;
        }
        *out_used_cached = true;
        return LANTERN_CLIENT_OK;
    }

    return LANTERN_CLIENT_OK;
}

static lantern_client_error append_cached_proofs_for_group(
    const struct lantern_client *client,
    const LanternAttestationData *data,
    const LanternRoot *data_root,
    bool *remaining,
    size_t *remaining_count,
    LanternAggregatedAttestations *out_attestations,
    LanternAttestationSignatures *out_signatures)
{
    if (!client || !data || !data_root || !remaining || !remaining_count || !out_attestations || !out_signatures)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    if (*remaining_count == 0)
    {
        return LANTERN_CLIENT_OK;
    }
    const struct lantern_aggregated_payload_pool *cache =
        &client->store.known_aggregated_payloads;
    if (!cache->entries || cache->length == 0)
    {
        return LANTERN_CLIENT_OK;
    }

    bool *used = calloc(cache->length, sizeof(*used));
    if (!used)
    {
        return LANTERN_CLIENT_ERR_ALLOC;
    }

    while (*remaining_count > 0)
    {
        size_t best_index = SIZE_MAX;
        size_t best_overlap = 0;
        for (size_t i = 0; i < cache->length; ++i)
        {
            if (used[i])
            {
                continue;
            }
            if (memcmp(cache->entries[i].data_root.bytes, data_root->bytes, LANTERN_ROOT_SIZE) != 0)
            {
                continue;
            }
            size_t overlap = proof_overlap_count(&cache->entries[i].proof, remaining);
            if (overlap > best_overlap)
            {
                best_overlap = overlap;
                best_index = i;
                if (best_overlap == *remaining_count)
                {
                    break;
                }
            }
        }
        if (best_index == SIZE_MAX || best_overlap == 0)
        {
            break;
        }
        lantern_client_error rc = append_cached_proof_as_aggregated(
            data,
            &cache->entries[best_index].proof,
            out_attestations,
            out_signatures);
        if (rc != LANTERN_CLIENT_OK)
        {
            free(used);
            return rc;
        }
        proof_clear_remaining(&cache->entries[best_index].proof, remaining, remaining_count);
        used[best_index] = true;
    }

    free(used);
    return LANTERN_CLIENT_OK;
}

static lantern_client_error aggregate_attestations_for_block(
    struct lantern_client *client,
    const LanternAttestations *att_list,
    const LanternSignatureList *att_signatures,
    bool allow_raw_signature_aggregation,
    LanternAggregatedAttestations *out_attestations,
    LanternAttestationSignatures *out_signatures)
{
    if (!client || !att_list || !att_signatures || !out_attestations || !out_signatures)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    if (lantern_aggregated_attestations_resize(out_attestations, 0) != 0)
    {
        return LANTERN_CLIENT_ERR_ALLOC;
    }
    if (lantern_attestation_signatures_resize(out_signatures, 0) != 0)
    {
        (void)lantern_aggregated_attestations_resize(out_attestations, 0);
        return LANTERN_CLIENT_ERR_ALLOC;
    }

    if (att_list->length == 0)
    {
        return LANTERN_CLIENT_OK;
    }
    if (!att_list->data)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    bool state_locked = lantern_client_lock_state(client);
    if (!state_locked)
    {
        return LANTERN_CLIENT_ERR_RUNTIME;
    }

    struct aggregation_group *groups = NULL;
    size_t group_count = 0;
    size_t group_capacity = 0;
    lantern_client_error rc = LANTERN_CLIENT_OK;

    for (size_t i = 0; i < att_list->length; ++i)
    {
        const LanternSignature *signature = NULL;
        if (att_signatures->data && i < att_signatures->length)
        {
            signature = &att_signatures->data[i];
        }
        LanternAttestationData data = {
            .slot = att_list->data[i].slot,
            .head = att_list->data[i].head,
            .target = att_list->data[i].target,
            .source = att_list->data[i].source,
        };
        struct aggregation_group *group = aggregation_group_find_or_add(
            &groups,
            &group_count,
            &group_capacity,
            &data);
        if (!group)
        {
            rc = LANTERN_CLIENT_ERR_ALLOC;
            break;
        }
        if (aggregation_group_append(group, att_list->data[i].validator_id, signature) != 0)
        {
            rc = LANTERN_CLIENT_ERR_ALLOC;
            break;
        }
    }

    if (rc == LANTERN_CLIENT_OK)
    {
        for (size_t i = 0; i < group_count; ++i)
        {
            aggregation_group_sort(&groups[i]);
            LanternRoot data_root;
            if (lantern_hash_tree_root_attestation_data(&groups[i].data, &data_root) != 0)
            {
                rc = LANTERN_CLIENT_ERR_VALIDATOR;
                break;
            }
            if (allow_raw_signature_aggregation && groups[i].count > 0)
            {
                bool used_cached_group_proof = false;
                rc = append_cached_exact_group_proof(
                    client,
                    &groups[i].data,
                    &data_root,
                    groups[i].validator_ids,
                    groups[i].count,
                    out_attestations,
                    out_signatures,
                    &used_cached_group_proof);
                if (rc != LANTERN_CLIENT_OK)
                {
                    break;
                }
                if (!used_cached_group_proof)
                {
                    rc = append_group_as_aggregated(&client->state, &groups[i], out_attestations, out_signatures);
                    if (rc != LANTERN_CLIENT_OK)
                    {
                        break;
                    }
                }
            }

            if (groups[i].all_count > 0)
            {
                bool *remaining = calloc(LANTERN_VALIDATOR_REGISTRY_LIMIT, sizeof(*remaining));
                if (!remaining)
                {
                    rc = LANTERN_CLIENT_ERR_ALLOC;
                    break;
                }
                size_t remaining_count = 0;
                for (size_t j = 0; j < groups[i].all_count; ++j)
                {
                    uint64_t vid = groups[i].all_validator_ids[j];
                    if (vid >= LANTERN_VALIDATOR_REGISTRY_LIMIT)
                    {
                        rc = LANTERN_CLIENT_ERR_RUNTIME;
                        break;
                    }
                    if (!remaining[vid])
                    {
                        remaining[vid] = true;
                        remaining_count += 1u;
                    }
                }
                if (rc == LANTERN_CLIENT_OK && allow_raw_signature_aggregation && groups[i].count > 0)
                {
                    for (size_t j = 0; j < groups[i].count; ++j)
                    {
                        uint64_t vid = groups[i].validator_ids[j];
                        if (vid >= LANTERN_VALIDATOR_REGISTRY_LIMIT)
                        {
                            rc = LANTERN_CLIENT_ERR_RUNTIME;
                            break;
                        }
                        if (remaining[vid])
                        {
                            remaining[vid] = false;
                            if (remaining_count > 0)
                            {
                                remaining_count -= 1u;
                            }
                        }
                    }
                }
                if (rc == LANTERN_CLIENT_OK && remaining_count > 0)
                {
                    rc = append_cached_proofs_for_group(
                        client,
                        &groups[i].data,
                        &data_root,
                        remaining,
                        &remaining_count,
                        out_attestations,
                        out_signatures);
                }
                free(remaining);
                if (rc != LANTERN_CLIENT_OK)
                {
                    break;
                }
            }
        }
    }

    for (size_t i = 0; i < group_count; ++i)
    {
        aggregation_group_reset(&groups[i]);
    }
    free(groups);

    lantern_client_unlock_state(client, state_locked);

    if (rc != LANTERN_CLIENT_OK)
    {
        (void)lantern_aggregated_attestations_resize(out_attestations, 0);
        (void)lantern_attestation_signatures_resize(out_signatures, 0);
    }
    return rc;
}

lantern_client_error lantern_client_aggregate_attestations_for_block(
    struct lantern_client *client,
    const LanternAttestations *att_list,
    const LanternSignatureList *att_signatures,
    LanternAggregatedAttestations *out_attestations,
    LanternAttestationSignatures *out_signatures)
{
    return aggregate_attestations_for_block(
        client,
        att_list,
        att_signatures,
        false,
        out_attestations,
        out_signatures);
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
 * Vote Time Utilities
 * ============================================================================ */

/**
 * Compute wall-clock time for a vote slot.
 *
 * Calculates the Unix timestamp (in seconds) at which the given vote slot
 * begins, based on genesis time and seconds per slot configuration.
 *
 * @param client       Client instance (must have fork_choice initialized)
 * @param vote_slot    Slot number to compute time for
 * @param out_seconds  Output for computed time in seconds (Unix timestamp)
 *
 * @return true on success
 * @return false if client is NULL, fork_choice not initialized, out_seconds
 *         is NULL, or computed time overflows uint64_t
 *
 * @note Thread safety: This function is thread-safe
 */
bool lantern_client_vote_time_seconds(
    const struct lantern_client *client,
    uint64_t vote_slot,
    uint64_t *out_seconds)
{
    if (!client || !client->has_fork_choice || !out_seconds)
    {
        return false;
    }
    uint32_t seconds_per_slot = client->fork_choice.seconds_per_slot;
    if (seconds_per_slot == 0)
    {
        seconds_per_slot = 1;
    }
    uint64_t slot_for_time = vote_slot;
    if (slot_for_time != UINT64_MAX)
    {
        slot_for_time += 1u;
    }

#if defined(__SIZEOF_INT128__)
    __uint128_t slot_offset = (__uint128_t)slot_for_time * (uint64_t)seconds_per_slot;
    __uint128_t result = slot_offset + (__uint128_t)client->fork_choice.config.genesis_time;
    if (result > UINT64_MAX)
    {
        return false;
    }
    *out_seconds = (uint64_t)result;
#else
    /* Fallback for platforms without 128-bit integers */
    uint64_t genesis_time = client->fork_choice.config.genesis_time;
    /* Check for overflow in multiplication */
    if (seconds_per_slot != 0 && slot_for_time > UINT64_MAX / seconds_per_slot)
    {
        return false;
    }
    uint64_t slot_offset = slot_for_time * (uint64_t)seconds_per_slot;
    /* Check for overflow in addition */
    if (slot_offset > UINT64_MAX - genesis_time)
    {
        return false;
    }
    *out_seconds = slot_offset + genesis_time;
#endif
    return true;
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
    if (!client)
    {
        return false;
    }
    if (!client->has_state || !client->has_runtime || !client->has_fork_choice)
    {
        return false;
    }
    if (!client->gossip_running || client->local_validator_count == 0)
    {
        return false;
    }
    if (validator_should_pause_for_sync(client))
    {
        return false;
    }
    return true;
}


/* ============================================================================
 * Vote Signing and Storage
 * ============================================================================ */

/**
 * Sign a vote with a validator's secret key.
 *
 * @param validator  Local validator
 * @param slot       Slot number
 * @param vote       Vote to sign (modified in place)
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM on NULL inputs
 * @return LANTERN_CLIENT_ERR_VALIDATOR on hashing or signing failure
 *
 * @note Thread safety: This function is thread-safe
 */
int validator_sign_vote(
    struct lantern_local_validator *validator,
    uint64_t slot,
    LanternSignedVote *vote)
{
    if (!validator || !vote || !validator->secret_key)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    LanternRoot vote_root;
    if (lantern_hash_tree_root_attestation_data(&vote->data.data, &vote_root) != 0)
    {
        return LANTERN_CLIENT_ERR_VALIDATOR;
    }
    if (!lantern_signature_sign(
            validator->secret_key,
            slot,
            &vote_root,
            &vote->signature))
    {
        return LANTERN_CLIENT_ERR_VALIDATOR;
    }
    return LANTERN_CLIENT_OK;
}


/**
 * @brief Collect parent root, checkpoints, and attestations for a new block.
 *
 * Computes the parent root and vote checkpoints from state, signs the
 * proposer's vote, and collects attestations/signatures to include in the
 * proposed block.
 *
 * @param client            Client instance
 * @param slot              Slot number
 * @param local             Local validator
 * @param out_parent_root   Output for selected parent root
 * @param out_proposer_vote Output for the proposer's signed vote
 * @param att_list          Initialized attestation list to populate
 * @param att_signatures    Initialized signature list to populate
 *
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_RUNTIME on lock/state errors
 * @return Propagated error codes from validator_sign_vote()
 *
 * @note Thread safety: This function acquires state_lock
 */
static lantern_client_error validator_build_block_collect_attestations(
    struct lantern_client *client,
    uint64_t slot,
    struct lantern_local_validator *local,
    LanternRoot *out_parent_root,
    LanternSignedVote *out_proposer_vote,
    LanternAttestations *att_list,
    LanternSignatureList *att_signatures)
{
    lantern_client_error result = LANTERN_CLIENT_OK;

    if (!client || !local || !out_parent_root || !out_proposer_vote || !att_list || !att_signatures)
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

    LanternCheckpoint head_cp;
    LanternCheckpoint target_cp;
    LanternCheckpoint source_cp;
    if (lantern_state_compute_vote_checkpoints(
            &client->state,
            &client->store,
            &head_cp,
            &target_cp,
            &source_cp)
        != 0)
    {
        result = LANTERN_CLIENT_ERR_RUNTIME;
        goto cleanup;
    }

    out_proposer_vote->data.validator_id = local->global_index;
    out_proposer_vote->data.slot = slot;
    out_proposer_vote->data.head = head_cp;
    out_proposer_vote->data.target = target_cp;
    out_proposer_vote->data.source = source_cp;

    result = (lantern_client_error)validator_sign_vote(local, slot, out_proposer_vote);
    if (result != LANTERN_CLIENT_OK)
    {
        goto cleanup;
    }

    if (lantern_state_collect_attestations_for_block(
            &client->state,
            &client->store,
            slot,
            local->global_index,
            out_parent_root,
            out_proposer_vote,
            att_list,
            att_signatures)
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
 * and fills the signatures array with attestation signatures followed by the
 * proposer signature.
 *
 * @param slot           Slot number
 * @param proposer_index Proposer's global validator index
 * @param parent_root    Parent block root
 * @param proposer_vote  Proposer's signed vote
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
    struct lantern_client *client,
    uint64_t slot,
    uint64_t proposer_index,
    const LanternRoot *parent_root,
    const LanternSignedVote *proposer_vote,
    const LanternAttestations *att_list,
    const LanternSignatureList *att_signatures,
    LanternSignedBlock *out_block)
{
    if (!client || !parent_root || !proposer_vote || !att_list || !att_signatures || !out_block)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    LanternAggregatedAttestations aggregated_attestations;
    LanternAttestationSignatures aggregated_signatures;
    lantern_aggregated_attestations_init(&aggregated_attestations);
    lantern_attestation_signatures_init(&aggregated_signatures);

    lantern_client_error agg_rc = aggregate_attestations_for_block(
        client,
        att_list,
        att_signatures,
        false,
        &aggregated_attestations,
        &aggregated_signatures);
    if (agg_rc != LANTERN_CLIENT_OK)
    {
        lantern_aggregated_attestations_reset(&aggregated_attestations);
        lantern_attestation_signatures_reset(&aggregated_signatures);
        return agg_rc;
    }

    LanternBlock *message_block = &out_block->message.block;
    message_block->slot = slot;
    message_block->proposer_index = proposer_index;
    message_block->parent_root = *parent_root;
    memset(&message_block->state_root, 0, sizeof(message_block->state_root));

    if (lantern_aggregated_attestations_copy(
            &message_block->body.attestations,
            &aggregated_attestations)
        != 0)
    {
        lantern_aggregated_attestations_reset(&aggregated_attestations);
        lantern_attestation_signatures_reset(&aggregated_signatures);
        return LANTERN_CLIENT_ERR_ALLOC;
    }

    out_block->message.proposer_attestation = proposer_vote->data;
    out_block->signatures.proposer_signature = proposer_vote->signature;

    if (lantern_attestation_signatures_copy(
            &out_block->signatures.attestation_signatures,
            &aggregated_signatures)
        != 0)
    {
        lantern_aggregated_attestations_reset(&aggregated_attestations);
        lantern_attestation_signatures_reset(&aggregated_signatures);
        return LANTERN_CLIENT_ERR_ALLOC;
    }

    lantern_aggregated_attestations_reset(&aggregated_attestations);
    lantern_attestation_signatures_reset(&aggregated_signatures);
    return LANTERN_CLIENT_OK;
}


/**
 * @brief Preview post-state root for a built block.
 *
 * Computes the expected post-state root for the proposed block without
 * mutating state.
 *
 * @param client         Client instance
 * @param block          Built block to preview
 * @param out_state_root Output for the computed post-state root
 *
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM on NULL inputs
 * @return LANTERN_CLIENT_ERR_RUNTIME on lock/state failures
 *
 * @note Thread safety: This function acquires state_lock
 */
static lantern_client_error validator_build_block_preview_state_root(
    struct lantern_client *client,
    LanternSignedBlock *block,
    LanternRoot *out_state_root)
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
    if (lantern_state_preview_post_state_root(&client->state, &client->store, block, out_state_root) != 0)
    {
        result = LANTERN_CLIENT_ERR_RUNTIME;
    }
    lantern_client_unlock_state(client, state_locked);
    return result;
}


/**
 * Refresh a cached vote with updated checkpoints and re-sign if needed.
 *
 * Compares the vote's source checkpoint with the provided source. If they
 * differ, updates all checkpoints (head, target, source) and re-signs the
 * vote using the validator's secret key.
 *
 * @param validator  Local validator with signing key (must have secret_key set)
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
 * @return LANTERN_CLIENT_ERR_VALIDATOR when the validator key is missing or
 *         signing fails
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
    if (!validator->secret_key)
    {
        return LANTERN_CLIENT_ERR_VALIDATOR;
    }

    /* If the source checkpoint is unchanged, no refresh is required. */
    if (vote->data.source.slot != source->slot
        || memcmp(vote->data.source.root.bytes, source->root.bytes, LANTERN_ROOT_SIZE) != 0)
    {
        vote->data.head = *head;
        vote->data.target = *target;
        vote->data.source = *source;

        if (validator_sign_vote(validator, slot, vote) != 0)
        {
            return LANTERN_CLIENT_ERR_VALIDATOR;
        }
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
    if (lantern_hash_tree_root_attestation_data(&vote->data.data, &data_root) == 0)
    {
        LanternSignatureKey key = {
            .validator_index = vote->data.validator_id,
            .data_root = data_root,
        };
        if (lantern_client_set_gossip_signature(
                client,
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

    int rc = lantern_gossipsub_service_publish_vote(&client->gossip, vote);
    if (rc != 0)
    {
        lantern_log_warn(
            "gossip",
            &meta,
            "failed to publish attestation validator=%" PRIu64 " slot=%" PRIu64,
            vote->data.validator_id,
            vote->data.slot);
        return LANTERN_CLIENT_ERR_NETWORK;
    }
    size_t subnet_id = 0;
    if (lantern_validator_index_compute_subnet_id(
            vote->data.validator_id,
            validator_attestation_committee_count(client),
            &subnet_id)
        == 0) {
        if (subnet_id == client->gossip.attestation_subnet_id) {
            if (lantern_gossipsub_service_publish_vote_subnet(&client->gossip, vote) != 0) {
                lantern_log_warn(
                    "gossip",
                    &meta,
                    "failed to publish subnet attestation validator=%" PRIu64 " slot=%" PRIu64 " subnet=%zu",
                    vote->data.validator_id,
                    vote->data.slot,
                    subnet_id);
                return LANTERN_CLIENT_ERR_NETWORK;
            }
        }
    }
    lantern_log_info(
        "gossip",
        &meta,
        "published attestation validator=%" PRIu64 " slot=%" PRIu64,
        vote->data.validator_id,
        vote->data.slot);
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
            "gossip",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "cannot publish block at slot %" PRIu64 ": gossip service inactive",
            block->message.block.slot);
        return LANTERN_CLIENT_ERR_NETWORK;
    }
    if (lantern_gossipsub_service_publish_block(&client->gossip, block) != 0)
    {
        lantern_log_error(
            "gossip",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to publish block at slot %" PRIu64,
            block->message.block.slot);
        return LANTERN_CLIENT_ERR_NETWORK;
    }

    LanternRoot block_root;
    char root_hex[2 * LANTERN_ROOT_SIZE + 3];
    if (lantern_hash_tree_root_block(&block->message.block, &block_root) == 0)
    {
        format_root_hex(&block_root, root_hex, sizeof(root_hex));
    }
    else
    {
        root_hex[0] = '\0';
    }

    lantern_log_info(
        "gossip",
        &(const struct lantern_log_metadata){.validator = client->node_id},
        "published block slot=%" PRIu64 " root=%s attestations=%zu",
        block->message.block.slot,
        root_hex[0] ? root_hex : "0x0",
        block->message.block.body.attestations.length);
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
 * @param out_proposer_vote Output for the proposer's vote
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
    LanternSignedBlock *out_block,
    LanternSignedVote *out_proposer_vote)
{
    lantern_client_error result = LANTERN_CLIENT_OK;
    LanternRoot parent_root;
    LanternAttestations att_list;
    LanternSignatureList att_signatures;
    bool att_list_initialized = false;
    bool att_signatures_initialized = false;

    if (!client || !out_block || !out_proposer_vote)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    if (local_index >= client->local_validator_count || !client->local_validators)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    struct lantern_local_validator *local = &client->local_validators[local_index];
    lantern_signed_block_with_attestation_init(out_block);
    memset(out_proposer_vote, 0, sizeof(*out_proposer_vote));

    lantern_attestations_init(&att_list);
    att_list_initialized = true;
    lantern_signature_list_init(&att_signatures);
    att_signatures_initialized = true;

    result = validator_build_block_collect_attestations(
        client,
        slot,
        local,
        &parent_root,
        out_proposer_vote,
        &att_list,
        &att_signatures);
    if (result != LANTERN_CLIENT_OK)
    {
        goto cleanup;
    }

    result = validator_build_block_populate_message(
        client,
        slot,
        local->global_index,
        &parent_root,
        out_proposer_vote,
        &att_list,
        &att_signatures,
        out_block);
    if (result != LANTERN_CLIENT_OK)
    {
        goto cleanup;
    }

    LanternRoot computed_state_root;
    result = validator_build_block_preview_state_root(client, out_block, &computed_state_root);
    if (result != LANTERN_CLIENT_OK)
    {
        goto cleanup;
    }

    out_block->message.block.state_root = computed_state_root;
    result = LANTERN_CLIENT_OK;

cleanup:
    if (att_list_initialized)
    {
        lantern_attestations_reset(&att_list);
    }
    if (att_signatures_initialized)
    {
        lantern_signature_list_reset(&att_signatures);
    }
    if (result != LANTERN_CLIENT_OK)
    {
        lantern_signed_block_with_attestation_reset(out_block);
    }
    return result;
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
    if (!validator_service_should_run(client))
    {
        return LANTERN_CLIENT_ERR_RUNTIME;
    }
    LanternSignedBlock block;
    LanternSignedVote proposer_vote;
    lantern_signed_block_with_attestation_init(&block);
    memset(&proposer_vote, 0, sizeof(proposer_vote));

    int rc = validator_build_block(client, slot, local_index, &block, &proposer_vote);
    if (rc != LANTERN_CLIENT_OK)
    {
        lantern_signed_block_with_attestation_reset(&block);
        return rc;
    }

    struct lantern_log_metadata meta = {.validator = client->node_id};
    lantern_log_info(
        "validator",
        &meta,
        "proposing block slot=%" PRIu64 " proposer=%" PRIu64,
        slot,
        block.message.block.proposer_index);

    lantern_client_record_block(client, &block, NULL, NULL, "local", 0, false, NULL, 0);
    if (client->validator_lock_initialized && pthread_mutex_lock(&client->validator_lock) == 0)
    {
        if (local_index < client->local_validator_count)
        {
            struct lantern_local_validator *local = &client->local_validators[local_index];
            local->last_proposed_slot = slot;
            /* The proposer already attested inside the block wrapper at interval 0. */
            local->last_attested_slot = slot;
            validator_clear_pending_attestation(local);
        }
        unlock_mutex_with_log(&client->validator_lock, client->node_id, "validator_lock");
    }

    rc = lantern_client_publish_block(client, &block);
    if (rc != LANTERN_CLIENT_OK)
    {
        lantern_signed_block_with_attestation_reset(&block);
        return rc;
    }

    lantern_signed_block_with_attestation_reset(&block);
    return LANTERN_CLIENT_OK;
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
    size_t num_validators = 0;

    if (!validator_service_should_run(client))
    {
        return LANTERN_CLIENT_ERR_RUNTIME;
    }
    if (!client->local_validators || client->local_validator_count == 0)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    LanternCheckpoint head_cp;
    LanternCheckpoint target_cp;
    LanternCheckpoint source_cp;
    bool state_locked = lantern_client_lock_state(client);
    if (!state_locked)
    {
        return LANTERN_CLIENT_ERR_RUNTIME;
    }
    num_validators = client->state.config.num_validators;
    if (lantern_state_compute_vote_checkpoints(
            &client->state,
            &client->store,
            &head_cp,
            &target_cp,
            &source_cp)
        != 0)
    {
        lantern_client_unlock_state(client, state_locked);
        return LANTERN_CLIENT_ERR_RUNTIME;
    }
    lantern_client_unlock_state(client, state_locked);

    bool have_lock = false;
    if (client->validator_lock_initialized)
    {
        if (pthread_mutex_lock(&client->validator_lock) != 0)
        {
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
        if (lantern_validator_index_is_proposer_for(
                (LanternValidatorIndex)validator->global_index,
                slot,
                num_validators))
        {
            /* Proposers do not re-attest at interval 1. */
            validator->last_attested_slot = slot;
            validator_clear_pending_attestation(validator);
            continue;
        }
        if (validator->last_attested_slot == slot)
        {
            continue;
        }
        LanternSignedVote vote;
        if (validator->has_pending_attestation && validator->pending_attestation_slot == slot)
        {
            vote = validator->pending_attestation;
        }
        else
        {
            memset(&vote, 0, sizeof(vote));
            vote.data.validator_id = validator->global_index;
            vote.data.slot = slot;
            vote.data.head = head_cp;
            vote.data.target = target_cp;
            vote.data.source = source_cp;
            int sign_rc = validator_sign_vote(validator, slot, &vote);
            if (sign_rc != LANTERN_CLIENT_OK)
            {
                if (result == LANTERN_CLIENT_OK)
                {
                    result = (lantern_client_error)sign_rc;
                }
                continue;
            }
        }
        validator->last_attested_slot = slot;
        validator_clear_pending_attestation(validator);

        int store_rc = validator_store_vote(client, &vote);
        if (store_rc != LANTERN_CLIENT_OK && result == LANTERN_CLIENT_OK)
        {
            result = (lantern_client_error)store_rc;
        }
        int publish_rc = validator_publish_vote(client, &vote);
        if (publish_rc != LANTERN_CLIENT_OK && result == LANTERN_CLIENT_OK)
        {
            result = (lantern_client_error)publish_rc;
        }
    }

    if (have_lock)
    {
        unlock_mutex_with_log(&client->validator_lock, client->node_id, "validator_lock");
    }
    return result;
}

static lantern_client_error collect_subnet_votes_for_slot(
    struct lantern_client *client,
    uint64_t slot,
    size_t subnet_id,
    LanternAttestations *out_attestations,
    LanternSignatureList *out_signatures) {
    if (!client || !out_attestations || !out_signatures) {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    if (lantern_attestations_resize(out_attestations, 0) != 0) {
        return LANTERN_CLIENT_ERR_ALLOC;
    }
    if (lantern_signature_list_resize(out_signatures, 0) != 0) {
        return LANTERN_CLIENT_ERR_ALLOC;
    }

    bool state_locked = lantern_client_lock_state(client);
    if (!state_locked) {
        return LANTERN_CLIENT_ERR_RUNTIME;
    }
    if (!client->has_state) {
        lantern_client_unlock_state(client, state_locked);
        return LANTERN_CLIENT_ERR_RUNTIME;
    }

    lantern_client_error result = LANTERN_CLIENT_OK;
    const struct lantern_gossip_signature_map *map = &client->store.gossip_signatures;
    for (size_t i = 0; i < map->length; ++i) {
        const struct lantern_gossip_signature_entry *entry = &map->entries[i];
        LanternAttestationData data;
        memset(&data, 0, sizeof(data));
        if (lantern_store_get_attestation_data(&client->store, &entry->key.data_root, &data) != 0) {
            continue;
        }
        if (data.slot != slot) {
            continue;
        }
        size_t vote_subnet = 0;
        if (lantern_validator_index_compute_subnet_id(
                entry->key.validator_index,
                validator_attestation_committee_count(client),
                &vote_subnet)
            != 0) {
            continue;
        }
        if (vote_subnet != subnet_id) {
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
    lantern_client_unlock_state(client, state_locked);

    if (result != LANTERN_CLIENT_OK) {
        (void)lantern_attestations_resize(out_attestations, 0);
        (void)lantern_signature_list_resize(out_signatures, 0);
    }
    return result;
}

static int validator_publish_aggregated_attestations(struct lantern_client *client, uint64_t slot)
{
    if (!client || !client->assigned_validators || !client->assigned_validators->enr.is_aggregator) {
        return LANTERN_CLIENT_ERR_RUNTIME;
    }

    LanternAttestations attestations;
    LanternSignatureList signatures;
    lantern_attestations_init(&attestations);
    lantern_signature_list_init(&signatures);

    LanternAggregatedAttestations aggregated_attestations;
    LanternAttestationSignatures aggregated_signatures;
    lantern_aggregated_attestations_init(&aggregated_attestations);
    lantern_attestation_signatures_init(&aggregated_signatures);

    lantern_client_error result = collect_subnet_votes_for_slot(
        client,
        slot,
        client->gossip.attestation_subnet_id,
        &attestations,
        &signatures);
    if (result != LANTERN_CLIENT_OK) {
        goto cleanup;
    }
    if (attestations.length == 0) {
        result = LANTERN_CLIENT_ERR_IGNORED;
        goto cleanup;
    }

    uint64_t aggregation_started_ms = monotonic_millis();
    result = aggregate_attestations_for_block(
        client,
        &attestations,
        &signatures,
        true,
        &aggregated_attestations,
        &aggregated_signatures);
    uint64_t aggregation_finished_ms = monotonic_millis();
    double aggregation_seconds = 0.0;
    if (aggregation_finished_ms >= aggregation_started_ms) {
        aggregation_seconds =
            (double)(aggregation_finished_ms - aggregation_started_ms) / 1000.0;
    }
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
        LanternRoot data_root;
        if (lantern_hash_tree_root_attestation_data(&signed_attestation.data, &data_root) == 0) {
            bool locked = lantern_client_lock_state(client);
            if (locked) {
                (void)lantern_client_add_new_aggregated_payload(
                    client,
                    &data_root,
                    &signed_attestation.data,
                    &signed_attestation.proof,
                    signed_attestation.data.target.slot);
            }
            lantern_client_unlock_state(client, locked);
        }
        lantern_signed_aggregated_attestation_reset(&signed_attestation);
    }

cleanup:
    lantern_aggregated_attestations_reset(&aggregated_attestations);
    lantern_attestation_signatures_reset(&aggregated_signatures);
    lantern_attestations_reset(&attestations);
    lantern_signature_list_reset(&signatures);
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
        bool state_locked = lantern_client_lock_state(client);
        if (!state_locked)
        {
            validator_sleep_ms(TIMING_SERVICE_POLL_SLEEP_MS);
            continue;
        }
        current_interval = client->has_fork_choice ? client->fork_choice.time_intervals : 0u;
        lantern_client_unlock_state(client, state_locked);

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
        if (!validator_service_should_run(client))
        {
            validator_sleep_ms(VALIDATOR_SERVICE_IDLE_SLEEP_MS);
            continue;
        }

        uint64_t now = validator_wall_time_now_millis();
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
                if (!duty->slot_aggregated && duty->slot_attested)
                {
                    if (validator_publish_aggregated_attestations(client, tp->slot) == LANTERN_CLIENT_OK)
                    {
                        duty->slot_aggregated = true;
                    }
                }
                break;

            case LANTERN_DUTY_PHASE_SAFE_TARGET:
                if (!duty->slot_aggregated && duty->slot_attested)
                {
                    if (validator_publish_aggregated_attestations(client, tp->slot) == LANTERN_CLIENT_OK)
                    {
                        duty->slot_aggregated = true;
                    }
                }
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
