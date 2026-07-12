#ifndef _DARWIN_C_SOURCE
#define _DARWIN_C_SOURCE
#endif

#include "lantern/consensus/state.h"

#include <inttypes.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "lantern/support/log.h"
#include "lantern/support/strings.h"
#include "lantern/support/time.h"
#include "lantern/metrics/lean_metrics.h"

#include "lantern/consensus/duties.h"
#include "lantern/consensus/fork_choice.h"
#include "lantern/consensus/hash.h"
#include "lantern/consensus/quorum.h"
#include "lantern/consensus/signature.h"
#include "lantern/consensus/store.h"

static void record_attestation_validation_metric(double start_seconds, bool valid) {
    lean_metrics_record_attestation_validation(lantern_time_now_seconds() - start_seconds, valid);
}

static void format_root_hex(const LanternRoot *root, char *out, size_t out_len) {
    if (!out || out_len == 0) {
        return;
    }
    out[0] = '\0';
    if (!root) {
        return;
    }
    if (lantern_bytes_to_hex(root->bytes, LANTERN_ROOT_SIZE, out, out_len, 1) != 0) {
        out[0] = '\0';
    }
}

static uint64_t lantern_state_justified_slots_anchor(const LanternState *state) {
    if (!state || state->latest_finalized.slot == UINT64_MAX) {
        return 0u;
    }
    return state->latest_finalized.slot + 1u;
}

static const LanternState *lantern_state_cached_fork_choice_state_for_root(
    const LanternStore *store,
    const LanternRoot *root);

static bool lantern_checkpoint_equal(const LanternCheckpoint *a, const LanternCheckpoint *b);

static int lantern_root_list_append(struct lantern_root_list *list, const LanternRoot *root);
static int lantern_bitlist_set_bit(struct lantern_bitlist *list, size_t index, bool value);
static int lantern_bitlist_get_bit(const struct lantern_bitlist *list, size_t index, bool *out_value);
static int lantern_bitlist_ensure_length(struct lantern_bitlist *list, size_t bit_length);
static int lantern_bitlist_drop_front(struct lantern_bitlist *list, size_t bits);
static void lantern_root_zero(LanternRoot *root);
static bool lantern_root_is_zero(const LanternRoot *root);
static int lantern_state_append_historical_root(LanternState *state, const LanternRoot *root);
static int lantern_state_set_justified_slot_bit(LanternState *state, uint64_t slot, bool value);
bool lantern_state_slot_in_justified_window(const LanternState *state, uint64_t slot);
int lantern_state_get_justified_slot_bit(const LanternState *state, uint64_t slot, bool *out_value);
static bool lantern_root_list_contains(const struct lantern_root_list *list, const LanternRoot *root);
static bool lantern_attestation_head_is_known(
    const LanternState *state,
    const LanternStore *store,
    const LanternCheckpoint *head);
struct lantern_block_payload_group {
    LanternRoot data_root;
    LanternAttestationData data;
};
static int collect_attestations_for_checkpoint(
    const LanternState *state,
    const LanternState *justified_view,
    const LanternStore *proof_store,
    const LanternRoot *parent_root,
    uint64_t block_slot,
    struct lantern_root_list *processed_data_roots,
    LanternAggregatedAttestations *out_attestations,
    LanternAttestationSignatures *out_signatures);
static lantern_state_aggregate_result state_select_child_proofs_from_pool(
    const struct lantern_aggregated_payload_pool *pool,
    const LanternRoot *data_root,
    bool *covered,
    LanternAggregatedSignatureProof *out_children,
    size_t out_child_capacity,
    size_t *out_child_count);
static const LanternAggregatedSignatureProof *state_select_best_proof_from_pool(
    const struct lantern_aggregated_payload_pool *pool,
    const LanternRoot *data_root);
static lantern_state_aggregate_result state_append_cached_proof(
    const LanternAttestationData *data,
    const LanternAggregatedSignatureProof *proof,
    LanternAggregatedAttestations *out_attestations,
    LanternAttestationSignatures *out_signatures);

static const LanternState *lantern_state_cached_fork_choice_state_for_root(
    const LanternStore *store,
    const LanternRoot *root) {
    if (!store || !store->fork_choice || !root || lantern_root_is_zero(root)) {
        return NULL;
    }
    return lantern_fork_choice_block_state(store->fork_choice, root);
}

static bool validator_pubkey_is_zero(const uint8_t *pubkey) {
    if (!pubkey) {
        return true;
    }
    for (size_t i = 0; i < LANTERN_VALIDATOR_PUBKEY_SIZE; ++i) {
        if (pubkey[i] != 0u) {
            return false;
        }
    }
    return true;
}

static int lantern_state_validate_block_attestation_data_uniqueness(const LanternBlock *block) {
    if (!block) {
        return -1;
    }

    const LanternAggregatedAttestations *attestations = &block->body.attestations;
    if (attestations->length == 0u) {
        return 0;
    }

    const struct lantern_log_metadata meta = {
        .has_slot = true,
        .slot = block->slot,
    };
    if (!attestations->data) {
        lantern_log_warn("state", &meta, "block attestation data missing");
        return -1;
    }

    struct lantern_root_list seen_data_roots;
    lantern_root_list_init(&seen_data_roots);
    int rc = 0;

    for (size_t i = 0; i < attestations->length; ++i) {
        LanternRoot data_root;
        if (lantern_hash_tree_root_attestation_data(&attestations->data[i].data, &data_root) != SSZ_SUCCESS) {
            lantern_log_warn(
                "state",
                &meta,
                "failed to hash block attestation data index=%zu",
                i);
            rc = -1;
            break;
        }
        if (lantern_root_list_contains(&seen_data_roots, &data_root)) {
            char root_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
            format_root_hex(&data_root, root_hex, sizeof(root_hex));
            lantern_log_warn(
                "state",
                &meta,
                "block rejected: duplicate attestation data index=%zu data_root=%s",
                i,
                root_hex[0] ? root_hex : "-");
            rc = -1;
            break;
        }
        if (lantern_root_list_append(&seen_data_roots, &data_root) != 0) {
            rc = -1;
            break;
        }
        if (seen_data_roots.length > (size_t)LANTERN_MAX_ATTESTATIONS_DATA) {
            lantern_log_warn(
                "state",
                &meta,
                "block rejected: distinct attestation data count=%zu exceeds limit=%u",
                seen_data_roots.length,
                (unsigned)LANTERN_MAX_ATTESTATIONS_DATA);
            rc = -1;
            break;
        }
    }

    lantern_root_list_reset(&seen_data_roots);
    return rc;
}

static bool lantern_root_list_contains(const struct lantern_root_list *list, const LanternRoot *root) {
    if (!list || !list->items || !root) {
        return false;
    }
    for (size_t i = 0; i < list->length; ++i) {
        if (memcmp(list->items[i].bytes, root->bytes, LANTERN_ROOT_SIZE) == 0) {
            return true;
        }
    }
    return false;
}

static bool lantern_attestation_head_is_known(
    const LanternState *state,
    const LanternStore *store,
    const LanternCheckpoint *head) {
    if (!state || !head || lantern_root_is_zero(&head->root)) {
        return false;
    }
    if (store && store->fork_choice
        && lantern_fork_choice_block_info(store->fork_choice, &head->root, NULL, NULL, NULL) == 0) {
        return true;
    }
    if (head->slot < state->historical_block_hashes.length) {
        return memcmp(
                   state->historical_block_hashes.items[head->slot].bytes,
                   head->root.bytes,
                   LANTERN_ROOT_SIZE)
            == 0;
    }
    return false;
}

static int lantern_block_payload_group_compare(const void *lhs, const void *rhs) {
    const struct lantern_block_payload_group *left = lhs;
    const struct lantern_block_payload_group *right = rhs;
    if (!left || !right) {
        return 0;
    }
    if (left->data.target.slot < right->data.target.slot) {
        return -1;
    }
    if (left->data.target.slot > right->data.target.slot) {
        return 1;
    }
    return memcmp(left->data_root.bytes, right->data_root.bytes, LANTERN_ROOT_SIZE);
}

/* LeanSpec attestation_data_matches_chain against the proposal chain view:
 * recorded history, then the parent root at the parent's slot, then zero-hash
 * entries for skipped slots up to the new block. */
static bool checkpoint_matches_proposal_chain(
    const LanternState *state,
    const LanternRoot *parent_root,
    uint64_t block_slot,
    const LanternCheckpoint *checkpoint) {
    if (!state || !parent_root || !checkpoint || lantern_root_is_zero(&checkpoint->root)) {
        return false;
    }
    uint64_t historical_length = (uint64_t)state->historical_block_hashes.length;
    uint64_t header_slot = state->latest_block_header.slot;
    uint64_t empty_slots = block_slot > header_slot + 1u ? block_slot - header_slot - 1u : 0u;
    uint64_t view_length = historical_length + 1u + empty_slots;
    if (checkpoint->slot >= view_length) {
        return false;
    }
    if (checkpoint->slot < historical_length) {
        return memcmp(
                   checkpoint->root.bytes,
                   state->historical_block_hashes.items[checkpoint->slot].bytes,
                   LANTERN_ROOT_SIZE)
            == 0;
    }
    if (checkpoint->slot == historical_length) {
        return memcmp(checkpoint->root.bytes, parent_root->bytes, LANTERN_ROOT_SIZE) == 0;
    }
    /* Skipped slots carry the zero hash; a nonzero root can never match. */
    return false;
}

static int collect_attestations_for_checkpoint(
    const LanternState *state,
    const LanternState *justified_view,
    const LanternStore *proof_store,
    const LanternRoot *parent_root,
    uint64_t block_slot,
    struct lantern_root_list *processed_data_roots,
    LanternAggregatedAttestations *out_attestations,
    LanternAttestationSignatures *out_signatures) {
    if (!state || !justified_view || !proof_store || !parent_root || !processed_data_roots
        || !out_attestations || !out_signatures) {
        return -1;
    }
    const struct lantern_aggregated_payload_pool *payloads = &proof_store->known_aggregated_payloads;
    if (!payloads->entries || payloads->length == 0) {
        return 0;
    }
    if (processed_data_roots->length >= (size_t)LANTERN_PRODUCER_MAX_ATTESTATIONS_DATA) {
        return 0;
    }

    size_t remaining_data_capacity =
        (size_t)LANTERN_PRODUCER_MAX_ATTESTATIONS_DATA - processed_data_roots->length;

    struct lantern_block_payload_group *groups =
        calloc(payloads->length, sizeof(*groups));
    if (!groups) {
        return -1;
    }
    size_t group_count = 0u;
    int rc = 0;

    for (size_t payload_index = 0; payload_index < payloads->length; ++payload_index) {
        const struct lantern_aggregated_payload_entry *entry = &payloads->entries[payload_index];
        LanternAttestationData data;
        memset(&data, 0, sizeof(data));

        if (entry->proof.participants.bit_length == 0 || !entry->proof.participants.bytes) {
            continue;
        }
        if (lantern_store_get_attestation_data(proof_store, &entry->data_root, &data) != 0) {
            continue;
        }
        if (!lantern_attestation_head_is_known(state, proof_store, &data.head)) {
            continue;
        }
        if (data.source.slot != justified_view->latest_justified.slot) {
            continue;
        }
        if (!checkpoint_matches_proposal_chain(state, parent_root, block_slot, &data.source)
            || !checkpoint_matches_proposal_chain(state, parent_root, block_slot, &data.target)) {
            continue;
        }

        bool source_justified = false;
        if (lantern_state_get_justified_slot_bit(justified_view, data.source.slot, &source_justified) != 0) {
            continue;
        }
        if (!source_justified) {
            continue;
        }
        if (data.target.slot <= data.source.slot) {
            continue;
        }
    
        bool target_justified = false;
        if (lantern_state_get_justified_slot_bit(justified_view, data.target.slot, &target_justified) != 0) {
            continue;
        }
        if (target_justified) {
            continue;
        }
        if (lantern_root_list_contains(processed_data_roots, &entry->data_root)) {
            continue;
        }
        
        bool seen_group = false;
        for (size_t i = 0; i < group_count; ++i) {
            if (memcmp(groups[i].data_root.bytes, entry->data_root.bytes, LANTERN_ROOT_SIZE) == 0) {
                seen_group = true;
                break;
            }
        }
        if (seen_group) {
            continue;
        }
        groups[group_count].data_root = entry->data_root;
        groups[group_count].data = data;
        group_count += 1u;
    }

    if (group_count > 1u) {
        qsort(groups, group_count, sizeof(*groups), lantern_block_payload_group_compare);
    }
    if (group_count > remaining_data_capacity) {
        group_count = remaining_data_capacity;
    }

    for (size_t group_index = 0; group_index < group_count; ++group_index) {
        const LanternAggregatedSignatureProof *best_proof =
            state_select_best_proof_from_pool(payloads, &groups[group_index].data_root);
        if (!best_proof) {
            continue;
        }
        if (lantern_root_list_append(processed_data_roots, &groups[group_index].data_root) != 0) {
            rc = -1;
            break;
        }
        if (state_append_cached_proof(
                &groups[group_index].data,
                best_proof,
                out_attestations,
                out_signatures)
            != LANTERN_STATE_AGGREGATE_OK) {
            rc = -1;
        }
        if (rc != 0) {
            break;
        }
    }
    free(groups);
    return rc;
}

struct state_aggregation_group {
    LanternRoot data_root;
    LanternAttestationData data;
    LanternValidatorIndex *validator_ids;
    LanternSignature *signatures;
    size_t count;
    size_t capacity;
};

static void state_aggregation_group_init(struct state_aggregation_group *group) {
    if (!group) {
        return;
    }
    memset(group, 0, sizeof(*group));
}

static void state_aggregation_group_reset(struct state_aggregation_group *group) {
    if (!group) {
        return;
    }
    free(group->validator_ids);
    free(group->signatures);
    memset(group, 0, sizeof(*group));
}

static struct state_aggregation_group *state_aggregation_group_find_or_add(
    struct state_aggregation_group **groups,
    size_t *group_count,
    size_t *group_capacity,
    const LanternRoot *data_root,
    const LanternAttestationData *data) {
    if (!groups || !group_count || !group_capacity || !data_root || !data) {
        return NULL;
    }

    for (size_t i = 0; i < *group_count; ++i) {
        if (memcmp((*groups)[i].data_root.bytes, data_root->bytes, LANTERN_ROOT_SIZE) == 0) {
            (*groups)[i].data = *data;
            return &(*groups)[i];
        }
    }

    size_t required = *group_count + 1u;
    if (*group_capacity < required) {
        size_t new_capacity = *group_capacity == 0u ? 4u : *group_capacity;
        while (new_capacity < required) {
            if (new_capacity > (SIZE_MAX / 2u)) {
                return NULL;
            }
            new_capacity *= 2u;
        }
        struct state_aggregation_group *new_groups =
            realloc(*groups, new_capacity * sizeof(*new_groups));
        if (!new_groups) {
            return NULL;
        }
        *groups = new_groups;
        *group_capacity = new_capacity;
    }

    struct state_aggregation_group *group = &(*groups)[*group_count];
    state_aggregation_group_init(group);
    group->data_root = *data_root;
    group->data = *data;
    *group_count += 1u;
    return group;
}

static int state_aggregation_group_append(
    struct state_aggregation_group *group,
    LanternValidatorIndex validator_id,
    const LanternSignature *signature) {
    if (!group || !signature || lantern_signature_is_zero(signature)) {
        return -1;
    }

    for (size_t i = 0; i < group->count; ++i) {
        if (group->validator_ids[i] == validator_id) {
            return 0;
        }
    }

    size_t required = group->count + 1u;
    if (group->capacity < required) {
        size_t new_capacity = group->capacity == 0u ? 4u : group->capacity;
        while (new_capacity < required) {
            if (new_capacity > (SIZE_MAX / 2u)) {
                return -1;
            }
            new_capacity *= 2u;
        }
        LanternValidatorIndex *ids = calloc(new_capacity, sizeof(*ids));
        LanternSignature *signatures = calloc(new_capacity, sizeof(*signatures));
        if (!ids || !signatures) {
            free(ids);
            free(signatures);
            return -1;
        }
        if (group->count > 0u) {
            memcpy(ids, group->validator_ids, group->count * sizeof(*ids));
            memcpy(signatures, group->signatures, group->count * sizeof(*signatures));
        }
        free(group->validator_ids);
        free(group->signatures);
        group->validator_ids = ids;
        group->signatures = signatures;
        group->capacity = new_capacity;
    }

    group->validator_ids[group->count] = validator_id;
    group->signatures[group->count] = *signature;
    group->count += 1u;
    return 0;
}

static void state_aggregation_group_sort(struct state_aggregation_group *group) {
    if (!group || group->count < 2u) {
        return;
    }

    for (size_t i = 1; i < group->count; ++i) {
        LanternValidatorIndex key_id = group->validator_ids[i];
        LanternSignature key_signature = group->signatures[i];
        size_t j = i;
        while (j > 0u && group->validator_ids[j - 1u] > key_id) {
            group->validator_ids[j] = group->validator_ids[j - 1u];
            group->signatures[j] = group->signatures[j - 1u];
            --j;
        }
        group->validator_ids[j] = key_id;
        group->signatures[j] = key_signature;
    }
}

static size_t state_proof_new_participant_count(
    const LanternAggregatedSignatureProof *proof,
    const bool *covered) {
    if (!proof || proof->participants.bit_length == 0u || !proof->participants.bytes) {
        return 0u;
    }

    size_t count = 0u;
    size_t limit = proof->participants.bit_length;
    if (limit > LANTERN_VALIDATOR_REGISTRY_LIMIT) {
        limit = LANTERN_VALIDATOR_REGISTRY_LIMIT;
    }
    for (size_t i = 0; i < limit; ++i) {
        if (lantern_bitlist_get(&proof->participants, i) && (!covered || !covered[i])) {
            count += 1u;
        }
    }
    return count;
}

static void state_mark_proof_participants_covered(
    const LanternAggregatedSignatureProof *proof,
    bool *covered) {
    if (!proof || !covered || proof->participants.bit_length == 0u || !proof->participants.bytes) {
        return;
    }

    size_t limit = proof->participants.bit_length;
    if (limit > LANTERN_VALIDATOR_REGISTRY_LIMIT) {
        limit = LANTERN_VALIDATOR_REGISTRY_LIMIT;
    }
    for (size_t i = 0; i < limit; ++i) {
        if (lantern_bitlist_get(&proof->participants, i)) {
            covered[i] = true;
        }
    }
}

static lantern_state_aggregate_result state_select_child_proofs_from_pool(
    const struct lantern_aggregated_payload_pool *pool,
    const LanternRoot *data_root,
    bool *covered,
    LanternAggregatedSignatureProof *out_children,
    size_t out_child_capacity,
    size_t *out_child_count) {
    if (!data_root || !covered || !out_children || !out_child_count) {
        return LANTERN_STATE_AGGREGATE_INVALID_PARAM;
    }
    if (!pool || !pool->entries || pool->length == 0u) {
        return LANTERN_STATE_AGGREGATE_OK;
    }
    size_t child_limit = out_child_capacity;
    if (child_limit > LANTERN_MAX_AGGREGATION_CHILDREN) {
        child_limit = LANTERN_MAX_AGGREGATION_CHILDREN;
    }
    if (*out_child_count >= child_limit) {
        return LANTERN_STATE_AGGREGATE_OK;
    }

    while (*out_child_count < child_limit) {
        size_t best_index = SIZE_MAX;
        size_t best_new_count = 0u;
        for (size_t i = 0; i < pool->length; ++i) {
            if (memcmp(pool->entries[i].data_root.bytes, data_root->bytes, LANTERN_ROOT_SIZE) != 0) {
                continue;
            }
            size_t new_count = state_proof_new_participant_count(&pool->entries[i].proof, covered);
            if (new_count > best_new_count) {
                best_new_count = new_count;
                best_index = i;
            }
        }
        if (best_index == SIZE_MAX || best_new_count == 0u) {
            break;
        }

        out_children[*out_child_count] = pool->entries[best_index].proof;
        *out_child_count += 1u;
        state_mark_proof_participants_covered(&pool->entries[best_index].proof, covered);
    }

    return LANTERN_STATE_AGGREGATE_OK;
}

static const LanternAggregatedSignatureProof *state_select_best_proof_from_pool(
    const struct lantern_aggregated_payload_pool *pool,
    const LanternRoot *data_root) {
    if (!pool || !pool->entries || pool->length == 0u || !data_root) {
        return NULL;
    }

    const LanternAggregatedSignatureProof *best = NULL;
    size_t best_count = 0u;
    for (size_t i = 0; i < pool->length; ++i) {
        if (memcmp(pool->entries[i].data_root.bytes, data_root->bytes, LANTERN_ROOT_SIZE) != 0) {
            continue;
        }
        size_t count = state_proof_new_participant_count(&pool->entries[i].proof, NULL);
        if (count > best_count) {
            best = &pool->entries[i].proof;
            best_count = count;
        }
    }
    return best;
}

static lantern_state_aggregate_result state_append_cached_proof(
    const LanternAttestationData *data,
    const LanternAggregatedSignatureProof *proof,
    LanternAggregatedAttestations *out_attestations,
    LanternAttestationSignatures *out_signatures) {
    if (!data || !proof || !out_attestations || !out_signatures) {
        return LANTERN_STATE_AGGREGATE_INVALID_PARAM;
    }
    if (proof->participants.bit_length == 0u || !proof->participants.bytes) {
        return LANTERN_STATE_AGGREGATE_INVALID_PARAM;
    }

    LanternAggregatedAttestation attestation;
    lantern_aggregated_attestation_init(&attestation);
    attestation.data = *data;
    if (lantern_bitlist_resize(&attestation.aggregation_bits, proof->participants.bit_length) != 0) {
        lantern_aggregated_attestation_reset(&attestation);
        return LANTERN_STATE_AGGREGATE_ALLOC;
    }

    size_t byte_len = (proof->participants.bit_length + 7u) / 8u;
    if (byte_len > 0u) {
        if (!attestation.aggregation_bits.bytes) {
            lantern_aggregated_attestation_reset(&attestation);
            return LANTERN_STATE_AGGREGATE_ALLOC;
        }
        memcpy(attestation.aggregation_bits.bytes, proof->participants.bytes, byte_len);
    }

    if (lantern_aggregated_attestations_append(out_attestations, &attestation) != 0) {
        lantern_aggregated_attestation_reset(&attestation);
        return LANTERN_STATE_AGGREGATE_ALLOC;
    }
    if (lantern_attestation_signatures_append(out_signatures, proof) != 0) {
        lantern_aggregated_attestation_reset(&attestation);
        return LANTERN_STATE_AGGREGATE_ALLOC;
    }

    lantern_aggregated_attestation_reset(&attestation);
    return LANTERN_STATE_AGGREGATE_OK;
}

static lantern_state_aggregate_result state_append_selected_group(
    const LanternState *state,
    const struct state_aggregation_group *group,
    const bool *covered,
    const LanternAggregatedSignatureProof *children,
    size_t child_count,
    LanternAggregatedAttestations *out_attestations,
    LanternAttestationSignatures *out_signatures) {
    if (!state || !group || !out_attestations || !out_signatures) {
        return LANTERN_STATE_AGGREGATE_INVALID_PARAM;
    }

    size_t raw_count = 0u;
    LanternValidatorIndex highest_raw_id = 0u;
    for (size_t i = 0; i < group->count; ++i) {
        LanternValidatorIndex validator_id = group->validator_ids[i];
        if (covered
            && validator_id < LANTERN_VALIDATOR_REGISTRY_LIMIT
            && covered[validator_id]) {
            continue;
        }
        raw_count += 1u;
        if (validator_id > highest_raw_id) {
            highest_raw_id = validator_id;
        }
    }

    if (raw_count == 0u && child_count < LANTERN_INVERSE_PROOF_SIZE) {
        return LANTERN_STATE_AGGREGATE_OK;
    }

    LanternRawXmssSignature *raw_xmss = NULL;
    struct lantern_bitlist xmss_participants;
    LanternAggregatedSignatureProof proof;
    lantern_bitlist_init(&xmss_participants);
    lantern_aggregated_signature_proof_init(&proof);

    lantern_state_aggregate_result rc = LANTERN_STATE_AGGREGATE_OK;
    size_t validator_count = lantern_state_validator_count(state);

    if (raw_count > 0u) {
        if (highest_raw_id >= validator_count
            || lantern_bitlist_resize(&xmss_participants, (size_t)highest_raw_id + 1u) != 0) {
            rc = LANTERN_STATE_AGGREGATE_RUNTIME;
            goto cleanup;
        }
        raw_xmss = calloc(raw_count, sizeof(*raw_xmss));
        if (!raw_xmss) {
            rc = LANTERN_STATE_AGGREGATE_ALLOC;
            goto cleanup;
        }

        size_t raw_index = 0u;
        for (size_t i = 0; i < group->count; ++i) {
            LanternValidatorIndex validator_id = group->validator_ids[i];
            if (covered
                && validator_id < LANTERN_VALIDATOR_REGISTRY_LIMIT
                && covered[validator_id]) {
                continue;
            }
            if (validator_id >= validator_count) {
                rc = LANTERN_STATE_AGGREGATE_RUNTIME;
                goto cleanup;
            }
            if (lantern_bitlist_set(&xmss_participants, (size_t)validator_id, true) != 0) {
                rc = LANTERN_STATE_AGGREGATE_RUNTIME;
                goto cleanup;
            }

            const uint8_t *pubkey =
                lantern_state_validator_attestation_pubkey(state, (size_t)validator_id);
            if (!pubkey || validator_pubkey_is_zero(pubkey)) {
                rc = LANTERN_STATE_AGGREGATE_RUNTIME;
                goto cleanup;
            }
            raw_xmss[raw_index].pubkey = pubkey;
            raw_xmss[raw_index].signature = &group->signatures[i];
            raw_index += 1u;
        }
    }

    if (!lantern_aggregated_signature_proof_aggregate(
            state,
            raw_count > 0u ? &xmss_participants : NULL,
            children,
            child_count,
            raw_xmss,
            raw_count,
            &group->data_root,
            group->data.slot,
            &proof)) {
        rc = LANTERN_STATE_AGGREGATE_VALIDATOR;
        goto cleanup;
    }

    rc = state_append_cached_proof(&group->data, &proof, out_attestations, out_signatures);

cleanup:
    free(raw_xmss);
    lantern_bitlist_reset(&xmss_participants);
    lantern_aggregated_signature_proof_reset(&proof);
    return rc;
}

lantern_state_aggregate_result lantern_state_aggregate(
    const LanternState *state,
    const LanternStore *store,
    const LanternAttestationSignatureInputs *attestation_signatures,
    const struct lantern_aggregated_payload_pool *new_payloads,
    const struct lantern_aggregated_payload_pool *known_payloads,
    LanternAggregatedAttestations *out_attestations,
    LanternAttestationSignatures *out_signatures) {
    if (!state || !out_attestations || !out_signatures) {
        return LANTERN_STATE_AGGREGATE_INVALID_PARAM;
    }

    const LanternAttestations *raw_attestations =
        attestation_signatures ? attestation_signatures->attestations : NULL;
    const LanternSignatureList *raw_signatures =
        attestation_signatures ? attestation_signatures->signatures : NULL;

    if ((raw_attestations && raw_attestations->length > 0u && !raw_attestations->data)
        || (raw_signatures && raw_signatures->length > 0u && !raw_signatures->data)) {
        return LANTERN_STATE_AGGREGATE_INVALID_PARAM;
    }
    if (new_payloads && new_payloads->length > 0u && !store) {
        return LANTERN_STATE_AGGREGATE_INVALID_PARAM;
    }

    if (lantern_aggregated_attestations_resize(out_attestations, 0u) != 0) {
        return LANTERN_STATE_AGGREGATE_ALLOC;
    }
    if (lantern_attestation_signatures_resize(out_signatures, 0u) != 0) {
        (void)lantern_aggregated_attestations_resize(out_attestations, 0u);
        return LANTERN_STATE_AGGREGATE_ALLOC;
    }

    struct state_aggregation_group *groups = NULL;
    size_t group_count = 0u;
    size_t group_capacity = 0u;
    lantern_state_aggregate_result rc = LANTERN_STATE_AGGREGATE_OK;

    if (raw_attestations) {
        for (size_t i = 0; i < raw_attestations->length; ++i) {
            const LanternSignature *signature = NULL;
            if (raw_signatures && raw_signatures->data && i < raw_signatures->length) {
                signature = &raw_signatures->data[i];
            }
            if (!signature || lantern_signature_is_zero(signature)) {
                continue;
            }

            LanternRoot data_root;
            if (lantern_hash_tree_root_attestation_data(&raw_attestations->data[i].data, &data_root) != SSZ_SUCCESS) {
                rc = LANTERN_STATE_AGGREGATE_VALIDATOR;
                break;
            }

            struct state_aggregation_group *group = state_aggregation_group_find_or_add(
                &groups,
                &group_count,
                &group_capacity,
                &data_root,
                &raw_attestations->data[i].data);
            if (!group
                || state_aggregation_group_append(
                       group,
                       raw_attestations->data[i].validator_id,
                       signature)
                    != 0) {
                rc = LANTERN_STATE_AGGREGATE_ALLOC;
                break;
            }
        }
    }

    if (rc == LANTERN_STATE_AGGREGATE_OK && store && new_payloads && new_payloads->entries) {
        for (size_t i = 0; i < new_payloads->length; ++i) {
            LanternAttestationData data;
            memset(&data, 0, sizeof(data));
            if (lantern_store_get_attestation_data(store, &new_payloads->entries[i].data_root, &data) != 0) {
                continue;
            }
            if (!state_aggregation_group_find_or_add(
                    &groups,
                    &group_count,
                    &group_capacity,
                    &new_payloads->entries[i].data_root,
                    &data)) {
                rc = LANTERN_STATE_AGGREGATE_ALLOC;
                break;
            }
        }
    }

    if (rc == LANTERN_STATE_AGGREGATE_OK) {
        for (size_t i = 0; i < group_count; ++i) {
            state_aggregation_group_sort(&groups[i]);

            bool covered[LANTERN_VALIDATOR_REGISTRY_LIMIT];
            memset(covered, 0, sizeof(covered));
            LanternAggregatedSignatureProof children[LANTERN_MAX_AGGREGATION_CHILDREN];
            size_t child_count = 0u;

            rc = state_select_child_proofs_from_pool(
                new_payloads,
                &groups[i].data_root,
                covered,
                children,
                LANTERN_MAX_AGGREGATION_CHILDREN,
                &child_count);
            if (rc == LANTERN_STATE_AGGREGATE_OK) {
                rc = state_select_child_proofs_from_pool(
                    known_payloads,
                    &groups[i].data_root,
                    covered,
                    children,
                    LANTERN_MAX_AGGREGATION_CHILDREN,
                    &child_count);
            }
            if (rc == LANTERN_STATE_AGGREGATE_OK) {
                rc = state_append_selected_group(
                    state,
                    &groups[i],
                    covered,
                    children,
                    child_count,
                    out_attestations,
                    out_signatures);
            }

            if (rc != LANTERN_STATE_AGGREGATE_OK) {
                break;
            }
        }
    }

    for (size_t i = 0; i < group_count; ++i) {
        state_aggregation_group_reset(&groups[i]);
    }
    free(groups);

    if (rc != LANTERN_STATE_AGGREGATE_OK) {
        (void)lantern_aggregated_attestations_resize(out_attestations, 0u);
        (void)lantern_attestation_signatures_resize(out_signatures, 0u);
    }
    return rc;
}


int lantern_state_mark_justified_slot(LanternState *state, uint64_t slot);

static size_t bitlist_required_bytes(size_t bit_length) {
    if (bit_length == 0) {
        return 0;
    }
    return (bit_length + 7) / 8;
}

static int ensure_root_capacity(struct lantern_root_list *list, size_t required) {
    if (!list) {
        return -1;
    }
    if (list->capacity >= required) {
        return 0;
    }
    size_t new_capacity = list->capacity == 0 ? 4 : list->capacity;
    while (new_capacity < required) {
        if (new_capacity > (SIZE_MAX / 2)) {
            return -1;
        }
        new_capacity *= 2;
    }
    LanternRoot *items = realloc(list->items, new_capacity * sizeof(*items));
    if (!items) {
        return -1;
    }
    list->items = items;
    list->capacity = new_capacity;
    return 0;
}

static int ensure_bit_capacity(struct lantern_bitlist *list, size_t required_bytes) {
    if (!list) {
        return -1;
    }
    if (list->capacity >= required_bytes) {
        return 0;
    }
    size_t new_capacity = list->capacity == 0 ? 4 : list->capacity;
    while (new_capacity < required_bytes) {
        if (new_capacity > (SIZE_MAX / 2)) {
            return -1;
        }
        new_capacity *= 2;
    }
    size_t old_capacity = list->capacity;
    uint8_t *bytes = realloc(list->bytes, new_capacity * sizeof(*bytes));
    if (!bytes) {
        return -1;
    }
    if (new_capacity > old_capacity) {
        memset(bytes + old_capacity, 0, new_capacity - old_capacity);
    }
    list->bytes = bytes;
    list->capacity = new_capacity;
    return 0;
}

void lantern_root_list_init(struct lantern_root_list *list) {
    if (!list) {
        return;
    }
    list->items = NULL;
    list->length = 0;
    list->capacity = 0;
}

void lantern_root_list_reset(struct lantern_root_list *list) {
    if (!list) {
        return;
    }
    free(list->items);
    list->items = NULL;
    list->length = 0;
    list->capacity = 0;
}

static int clone_root_list(struct lantern_root_list *dst, const struct lantern_root_list *src) {
    lantern_root_list_init(dst);
    if (!src || src->length == 0) {
        return 0;
    }
    if (!src->items) {
        return -1;
    }
    size_t count = src->length;
    LanternRoot *items = malloc(count * sizeof(*items));
    if (!items) {
        return -1;
    }
    memcpy(items, src->items, count * sizeof(*items));
    dst->items = items;
    dst->length = count;
    dst->capacity = count;
    return 0;
}

static int clone_bitlist(struct lantern_bitlist *dst, const struct lantern_bitlist *src) {
    lantern_bitlist_init(dst);
    if (!src || src->bit_length == 0) {
        return 0;
    }
    size_t bytes = bitlist_required_bytes(src->bit_length);
    if (bytes == 0) {
        dst->bit_length = 0;
        dst->capacity = 0;
        return 0;
    }
    if (!src->bytes) {
        return -1;
    }
    uint8_t *copy = malloc(bytes);
    if (!copy) {
        return -1;
    }
    memcpy(copy, src->bytes, bytes);
    dst->bytes = copy;
    dst->bit_length = src->bit_length;
    dst->capacity = bytes;
    return 0;
}

int lantern_state_clone(const LanternState *source, LanternState *dest) {
    if (!source || !dest) {
        return -1;
    }
    lantern_state_init(dest);
    dest->config = source->config;
    dest->slot = source->slot;
    dest->latest_block_header = source->latest_block_header;
    dest->latest_justified = source->latest_justified;
    dest->latest_finalized = source->latest_finalized;

    if (clone_root_list(&dest->historical_block_hashes, &source->historical_block_hashes) != 0) {
        goto error;
    }
    if (clone_root_list(&dest->justification_roots, &source->justification_roots) != 0) {
        goto error;
    }
    if (clone_bitlist(&dest->justified_slots, &source->justified_slots) != 0) {
        goto error;
    }
    if (clone_bitlist(&dest->justification_validators, &source->justification_validators) != 0) {
        goto error;
    }

    if (source->validators && source->validator_count > 0) {
        size_t bytes = source->validator_count * sizeof(*source->validators);
        LanternValidator *validators = malloc(bytes);
        if (!validators) {
            goto error;
        }
        memcpy(validators, source->validators, bytes);
        dest->validators = validators;
        dest->validator_count = source->validator_count;
        dest->validator_capacity = source->validator_count;
    }
    return 0;

error:
    lantern_state_reset(dest);
    return -1;
}


int lantern_root_list_resize(struct lantern_root_list *list, size_t new_length) {
    if (!list) {
        return -1;
    }
    if (new_length == 0) {
        if (list->items && list->length > 0) {
            memset(list->items, 0, list->length * sizeof(*list->items));
        }
        list->length = 0;
        return 0;
    }
    if (ensure_root_capacity(list, new_length) != 0) {
        return -1;
    }
    size_t old_length = list->length;
    if (new_length > old_length) {
        size_t added = new_length - old_length;
        memset(&list->items[old_length], 0, added * sizeof(*list->items));
    } else if (new_length < old_length) {
        size_t removed = old_length - new_length;
        memset(&list->items[new_length], 0, removed * sizeof(*list->items));
    }
    list->length = new_length;
    return 0;
}

static bool lantern_root_is_zero(const LanternRoot *root) {
    if (!root) {
        return false;
    }
    for (size_t i = 0; i < LANTERN_ROOT_SIZE; ++i) {
        if (root->bytes[i] != 0) {
            return false;
        }
    }
    return true;
}

static bool lantern_checkpoint_matches_history(
    const LanternCheckpoint *checkpoint,
    const struct lantern_root_list *history) {
    if (!checkpoint || !history || lantern_root_is_zero(&checkpoint->root) || checkpoint->slot > SIZE_MAX) {
        return false;
    }
    size_t slot = (size_t)checkpoint->slot;
    return slot < history->length
        && memcmp(checkpoint->root.bytes, history->items[slot].bytes, LANTERN_ROOT_SIZE) == 0;
}

static bool lantern_vote_matches_history(const LanternVote *vote, const struct lantern_root_list *history) {
    return vote
        && lantern_checkpoint_matches_history(&vote->source, history)
        && lantern_checkpoint_matches_history(&vote->target, history)
        && lantern_checkpoint_matches_history(&vote->head, history);
}

static uint64_t lantern_u64_isqrt(uint64_t value) {
    uint64_t result = 0;
    uint64_t bit = 1ull << 62;
    while (bit > value) {
        bit >>= 2;
    }
    while (bit != 0) {
        if (value >= result + bit) {
            value -= result + bit;
            result = (result >> 1) + bit;
        } else {
            result >>= 1;
        }
        bit >>= 2;
    }
    return result;
}

static bool lantern_is_pronic(uint64_t delta) {
    if (delta == 0) {
        return true;
    }
    uint64_t root = lantern_u64_isqrt(delta);
    uint64_t candidates[3];
    size_t count = 0;
    if (root > 0) {
        candidates[count++] = root - 1;
    }
    candidates[count++] = root;
    if (root < UINT64_MAX) {
        candidates[count++] = root + 1;
    }
    for (size_t i = 0; i < count; ++i) {
        uint64_t a = candidates[i];
        if (a == UINT64_MAX) {
            continue;
        }
        uint64_t b = a + 1;
        if (b == 0) {
            continue;
        }
        if (a > UINT64_MAX / b) {
            continue;
        }
        if (a * b == delta) {
            return true;
        }
    }
    return false;
}

static bool lantern_slot_is_justifiable(uint64_t candidate_slot, uint64_t finalized_slot) {
    if (candidate_slot < finalized_slot) {
        return false;
    }
    uint64_t delta = candidate_slot - finalized_slot;
    if (delta <= 5) {
        return true;
    }
    uint64_t root = lantern_u64_isqrt(delta);
    if (root * root == delta) {
        return true;
    }
    return lantern_is_pronic(delta);
}

static int lantern_root_list_append(struct lantern_root_list *list, const LanternRoot *root) {
    if (!list || !root) {
        return -1;
    }
    if (lantern_root_list_resize(list, list->length + 1) != 0) {
        return -1;
    }
    list->items[list->length - 1] = *root;
    return 0;
}

static int lantern_bitlist_set_bit(struct lantern_bitlist *list, size_t index, bool value) {
    if (!list) {
        return -1;
    }
    size_t required_bytes = bitlist_required_bytes(index + 1);
    if (ensure_bit_capacity(list, required_bytes) != 0) {
        return -1;
    }
    if (!list->bytes) {
        return -1;
    }
    size_t byte_index = index / 8u;
    if (byte_index >= list->capacity) {
        return -1;
    }
    size_t bit_index = index % 8u;
    uint8_t mask = (uint8_t)(1u << bit_index);
    if (value) {
        list->bytes[byte_index] |= mask;
    } else {
        list->bytes[byte_index] &= (uint8_t)~mask;
    }
    if (index + 1 > list->bit_length) {
        list->bit_length = index + 1;
    }
    return 0;
}

static int lantern_bitlist_get_bit(const struct lantern_bitlist *list, size_t index, bool *out_value) {
    if (!list || !out_value) {
        return -1;
    }
    if (index >= list->bit_length) {
        return -1;
    }
    if (!list->bytes) {
        return -1;
    }
    size_t byte_index = index / 8u;
    size_t bit_index = index % 8u;
    uint8_t mask = (uint8_t)(1u << bit_index);
    *out_value = (list->bytes[byte_index] & mask) != 0;
    return 0;
}

static int lantern_bitlist_drop_front(struct lantern_bitlist *list, size_t bits) {
    if (!list || bits == 0) {
        return 0;
    }
    if (bits >= list->bit_length) {
        return lantern_bitlist_resize(list, 0);
    }
    size_t byte_len = bitlist_required_bytes(list->bit_length);
    size_t byte_shift = bits / 8u;
    size_t bit_shift = bits % 8u;
    if (byte_shift > 0) {
        memmove(list->bytes, list->bytes + byte_shift, byte_len - byte_shift);
        memset(list->bytes + (byte_len - byte_shift), 0, byte_shift);
        byte_len -= byte_shift;
    }
    if (bit_shift > 0 && byte_len > 0) {
        uint8_t carry = 0;
        for (size_t i = byte_len; i > 0; --i) {
            size_t idx = i - 1;
            uint8_t current = list->bytes[idx];
            /* Shift right to drop low-order bits, carry in from higher byte. */
            uint8_t next_carry = (uint8_t)(current << (8u - bit_shift));
            list->bytes[idx] = (uint8_t)((current >> bit_shift) | carry);
            carry = next_carry;
        }
    }
    size_t new_length = list->bit_length - bits;
    return lantern_bitlist_resize(list, new_length);
}

bool lantern_state_slot_in_justified_window(const LanternState *state, uint64_t slot) {
    if (!state) {
        return false;
    }
    uint64_t anchor = lantern_state_justified_slots_anchor(state);
    if (slot < anchor) {
        return true;
    }
    uint64_t bit_length = state->justified_slots.bit_length;
    if (anchor > UINT64_MAX - bit_length) {
        return false;
    }
    return slot < anchor + bit_length;
}

/**
 * Check if any slot between start_slot (exclusive) and end_slot (exclusive)
 * is justifiable relative to the finalized_slot.
 *
 * This implements the LeanSpec finalization check (lines 435-439):
 *   if not any(
 *       Slot(slot).is_justifiable_after(self.latest_finalized.slot)
 *       for slot in range(source_slot + 1, target_slot)
 *   ):
 *       latest_finalized = source
 */
static bool has_justifiable_slot_between(
    uint64_t start_slot,
    uint64_t end_slot,
    uint64_t finalized_slot) {
    if (end_slot <= start_slot + 1u) {
        return false;
    }
    for (uint64_t slot = start_slot + 1u; slot < end_slot; ++slot) {
        if (lantern_slot_is_justifiable(slot, finalized_slot)) {
            return true;
        }
    }
    return false;
}

int lantern_state_get_justified_slot_bit(const LanternState *state, uint64_t slot, bool *out_value) {
    if (!state || !out_value) {
        return -1;
    }
    uint64_t anchor = lantern_state_justified_slots_anchor(state);
    if (slot < anchor) {
        *out_value = true;
        return 0;
    }
    if (!lantern_state_slot_in_justified_window(state, slot)) {
        *out_value = false;
        return 0;
    }
    uint64_t relative = slot - anchor;
    if (relative > SIZE_MAX) {
        return -1;
    }
    return lantern_bitlist_get_bit(&state->justified_slots, (size_t)relative, out_value);
}

static int lantern_state_ensure_justified_slot_index(LanternState *state, uint64_t slot, size_t *out_index) {
    if (!state) {
        return -1;
    }
    size_t limit = LANTERN_HISTORICAL_ROOTS_LIMIT;
    if (limit == 0) {
        return -1;
    }
    uint64_t anchor = lantern_state_justified_slots_anchor(state);
    if (slot < anchor) {
        return 1;
    }
    uint64_t relative = slot - anchor;
    if (relative >= limit) {
        return -1;
    }
    if (relative > SIZE_MAX) {
        return -1;
    }
    size_t desired_length = (size_t)relative + 1u;
    if (desired_length > state->justified_slots.bit_length) {
        if (lantern_bitlist_ensure_length(&state->justified_slots, desired_length) != 0) {
            return -1;
        }
    }
    if (out_index) {
        *out_index = (size_t)relative;
    }
    return 0;
}

static int lantern_state_set_justified_slot_bit(LanternState *state, uint64_t slot, bool value) {
    if (!state) {
        return -1;
    }
    if (slot < lantern_state_justified_slots_anchor(state)) {
        return 0;
    }
    if (slot > SIZE_MAX) {
        return -1;
    }
    size_t index = 0;
    int rc = lantern_state_ensure_justified_slot_index(state, slot, &index);
    if (rc > 0) {
        return 0;
    }
    if (rc != 0) {
        return -1;
    }
    return lantern_bitlist_set_bit(&state->justified_slots, index, value);
}

static int lantern_state_append_historical_root(LanternState *state, const LanternRoot *root) {
    if (!state || !root) {
        return -1;
    }
    if (state->historical_block_hashes.length >= LANTERN_HISTORICAL_ROOTS_LIMIT) {
        return 0;
    }
    return lantern_root_list_append(&state->historical_block_hashes, root);
}

static int lantern_bitlist_ensure_length(struct lantern_bitlist *list, size_t bit_length) {
    if (!list) {
        return -1;
    }
    if (bit_length <= list->bit_length) {
        return 0;
    }
    size_t original = list->bit_length;
    if (lantern_bitlist_resize(list, bit_length) != 0) {
        return -1;
    }
    for (size_t i = original; i < bit_length; ++i) {
        if (lantern_bitlist_set_bit(list, i, false) != 0) {
            return -1;
        }
    }
    return 0;
}

static bool lantern_checkpoint_equal(const LanternCheckpoint *a, const LanternCheckpoint *b) {
    if (!a || !b) {
        return false;
    }
    if (a->slot != b->slot) {
        return false;
    }
    return memcmp(a->root.bytes, b->root.bytes, LANTERN_ROOT_SIZE) == 0;
}

static size_t lantern_quorum_threshold(uint64_t validator_count) {
    uint64_t threshold = lantern_consensus_quorum_threshold(validator_count);
    if (threshold > SIZE_MAX) {
        return SIZE_MAX;
    }
    return (size_t)threshold;
}

/* === Justification vote tracking helpers === */

/**
 * Find the index of a root in the justification_roots list.
 * Returns -1 if not found, otherwise returns the index.
 */
static int lantern_state_find_justification_root_index(
    const LanternState *state,
    const LanternRoot *root) {
    if (!state || !root) {
        return -1;
    }
    for (size_t i = 0; i < state->justification_roots.length; ++i) {
        if (memcmp(state->justification_roots.items[i].bytes, root->bytes, LANTERN_ROOT_SIZE) == 0) {
            return (int)i;
        }
    }
    return -1;
}

/**
 * Add a new root to track justification votes for.
 * Inserts the root in lexicographically sorted order to match LeanSpec behavior.
 * Initializes all validator vote bits to false.
 * Returns the index of the new root, or -1 on error.
 */
static int lantern_state_add_justification_root(
    LanternState *state,
    const LanternRoot *root,
    size_t validator_count) {
    if (!state || !root || validator_count == 0) {
        return -1;
    }

    /* Find the insertion position to maintain sorted order (lexicographically by root bytes) */
    size_t insert_pos = 0;
    while (insert_pos < state->justification_roots.length &&
           memcmp(state->justification_roots.items[insert_pos].bytes, root->bytes, LANTERN_ROOT_SIZE) < 0) {
        insert_pos++;
    }

    if (lantern_root_list_append(&state->justification_roots, root) != 0) {
        return -1;
    }

    size_t old_root_count = state->justification_roots.length - 1;
    size_t new_bit_length = state->justification_validators.bit_length + validator_count;
    if (lantern_bitlist_ensure_length(&state->justification_validators, new_bit_length) != 0) {
        state->justification_roots.length--;
        return -1;
    }

    if (insert_pos == old_root_count) {
        return (int)insert_pos;
    }

    LanternRoot inserted = state->justification_roots.items[old_root_count];
    memmove(
        &state->justification_roots.items[insert_pos + 1u],
        &state->justification_roots.items[insert_pos],
        (old_root_count - insert_pos) * sizeof(*state->justification_roots.items));
    state->justification_roots.items[insert_pos] = inserted;

    for (size_t row = old_root_count; row > insert_pos; --row) {
        size_t dst = row * validator_count;
        size_t src = (row - 1u) * validator_count;
        for (size_t validator = 0; validator < validator_count; ++validator) {
            bool bit = false;
            if (lantern_bitlist_get_bit(&state->justification_validators, src + validator, &bit) != 0
                || lantern_bitlist_set_bit(&state->justification_validators, dst + validator, bit) != 0) {
                return -1;
            }
        }
    }
    size_t insert_start = insert_pos * validator_count;
    for (size_t validator = 0; validator < validator_count; ++validator) {
        if (lantern_bitlist_set_bit(&state->justification_validators, insert_start + validator, false) != 0) {
            return -1;
        }
    }

    return (int)insert_pos;
}

/**
 * Get whether a validator has voted for a specific justification root.
 */
static int lantern_state_get_justification_vote(
    const LanternState *state,
    int root_index,
    size_t validator_id,
    size_t validator_count,
    bool *out_value) {
    if (!state || !out_value || root_index < 0 || validator_count == 0) {
        return -1;
    }
    if (validator_id >= validator_count) {
        return -1;
    }
    size_t bit_index = (size_t)root_index * validator_count + validator_id;
    return lantern_bitlist_get_bit(&state->justification_validators, bit_index, out_value);
}

/**
 * Record a validator's vote for a justification root.
 */
static int lantern_state_set_justification_vote(
    LanternState *state,
    int root_index,
    size_t validator_id,
    size_t validator_count,
    bool value) {
    if (!state || root_index < 0 || validator_count == 0) {
        return -1;
    }
    if (validator_id >= validator_count) {
        return -1;
    }
    size_t bit_index = (size_t)root_index * validator_count + validator_id;
    return lantern_bitlist_set_bit(&state->justification_validators, bit_index, value);
}

/**
 * Count the number of validators who have voted for a justification root.
 */
static size_t lantern_state_count_justification_votes(
    const LanternState *state,
    int root_index,
    size_t validator_count) {
    if (!state || root_index < 0 || validator_count == 0) {
        return 0;
    }
    size_t count = 0;
    for (size_t i = 0; i < validator_count; ++i) {
        bool voted = false;
        if (lantern_state_get_justification_vote(state, root_index, i, validator_count, &voted) == 0 && voted) {
            count++;
        }
    }
    return count;
}

/**
 * Remove a root from justification tracking after it has been justified.
 * This shifts all remaining roots and their vote bits.
 */
static int lantern_state_remove_justification_root(
    LanternState *state,
    int root_index,
    size_t validator_count) {
    if (!state || root_index < 0 || validator_count == 0) {
        return -1;
    }
    size_t idx = (size_t)root_index;
    if (idx >= state->justification_roots.length) {
        return -1;
    }
    
    /* Remove the root from the list by shifting */
    size_t remaining_roots = state->justification_roots.length - idx - 1;
    if (remaining_roots > 0) {
        memmove(
            &state->justification_roots.items[idx],
            &state->justification_roots.items[idx + 1],
            remaining_roots * sizeof(LanternRoot));
    }
    state->justification_roots.length--;
    
    /* Remove the validator vote bits for this root by shifting */
    size_t start_bit = idx * validator_count;
    size_t bits_to_remove = validator_count;
    size_t total_bits = state->justification_validators.bit_length;
    
    if (start_bit + bits_to_remove <= total_bits) {
        /* Shift all bits after this root's section */
        size_t remaining_bits = total_bits - start_bit - bits_to_remove;
        for (size_t i = 0; i < remaining_bits; ++i) {
            bool bit = false;
            if (lantern_bitlist_get_bit(&state->justification_validators, start_bit + bits_to_remove + i, &bit) == 0) {
                lantern_bitlist_set_bit(&state->justification_validators, start_bit + i, bit);
            }
        }
        /* Resize to remove the extra bits */
        lantern_bitlist_resize(&state->justification_validators, total_bits - bits_to_remove);
    }
    
    return 0;
}

static int lantern_state_find_latest_slot_for_root(
    const LanternState *state,
    const LanternRoot *root,
    uint64_t start_slot,
    uint64_t *out_slot) {
    if (!state || !root || !out_slot) {
        return -1;
    }
    size_t length = state->historical_block_hashes.length;
    if (length == 0) {
        return 1;
    }
    if (start_slot >= length) {
        return 1;
    }
    for (size_t i = length; i-- > (size_t)start_slot;) {
        if (memcmp(state->historical_block_hashes.items[i].bytes, root->bytes, LANTERN_ROOT_SIZE) == 0) {
            *out_slot = (uint64_t)i;
            return 0;
        }
    }
    return 1;
}

static int lantern_state_prune_justification_roots(
    LanternState *state,
    uint64_t base_finalized_slot,
    uint64_t finalized_slot,
    size_t validator_count,
    const struct lantern_log_metadata *meta) {
    if (!state || validator_count == 0) {
        return -1;
    }
    if (state->justification_roots.length == 0) {
        return 0;
    }
    if (base_finalized_slot == UINT64_MAX) {
        return -1;
    }
    uint64_t start_slot = base_finalized_slot + 1u;
    for (size_t i = state->justification_roots.length; i-- > 0;) {
        uint64_t latest_slot = 0;
        int find_rc = lantern_state_find_latest_slot_for_root(
            state,
            &state->justification_roots.items[i],
            start_slot,
            &latest_slot);
        if (find_rc != 0) {
            if (lantern_state_remove_justification_root(state, (int)i, validator_count) != 0) {
                if (meta) {
                    lantern_log_warn(
                        "state",
                        meta,
                        "failed to prune off-chain justification root");
                }
                return -1;
            }
            continue;
        }
        if (latest_slot <= finalized_slot) {
            if (lantern_state_remove_justification_root(state, (int)i, validator_count) != 0) {
                if (meta) {
                    lantern_log_warn(
                        "state",
                        meta,
                        "failed to prune justification root at slot %" PRIu64,
                        latest_slot);
                }
                return -1;
            }
        }
    }
    return 0;
}

int lantern_state_set_validator_pubkeys_dual(
    LanternState *state,
    const uint8_t *attestation_pubkeys,
    const uint8_t *proposal_pubkeys,
    size_t count) {
    if (!state) {
        return -1;
    }
    if (count > (size_t)LANTERN_VALIDATOR_REGISTRY_LIMIT) {
        return -1;
    }
    if (count > 0 && (!attestation_pubkeys || !proposal_pubkeys)) {
        return -1;
    }
    if (count > 0 && count > SIZE_MAX / sizeof(*state->validators)) {
        return -1;
    }
    LanternValidator *items = NULL;
    if (count > 0) {
        items = malloc(count * sizeof(*items));
        if (!items) {
            return -1;
        }
        for (size_t i = 0; i < count; ++i) {
            memcpy(
                items[i].attestation_pubkey,
                attestation_pubkeys + (i * LANTERN_VALIDATOR_PUBKEY_SIZE),
                LANTERN_VALIDATOR_PUBKEY_SIZE);
            memcpy(
                items[i].proposal_pubkey,
                proposal_pubkeys + (i * LANTERN_VALIDATOR_PUBKEY_SIZE),
                LANTERN_VALIDATOR_PUBKEY_SIZE);
            items[i].index = (uint64_t)i;
        }
    }
    if (state->validators) {
        free(state->validators);
    }
    state->validators = items;
    state->validator_count = count;
    state->validator_capacity = count;
    return 0;
}

int lantern_state_set_validator_pubkeys(LanternState *state, const uint8_t *pubkeys, size_t count) {
    return lantern_state_set_validator_pubkeys_dual(state, pubkeys, pubkeys, count);
}

size_t lantern_state_validator_count(const LanternState *state) {
    if (!state || !state->validators) {
        return 0;
    }
    return state->validator_count;
}

const uint8_t *lantern_state_validator_attestation_pubkey(const LanternState *state, size_t index) {
    if (!state || !state->validators || index >= state->validator_count) {
        return NULL;
    }
    return state->validators[index].attestation_pubkey;
}

const uint8_t *lantern_state_validator_proposal_pubkey(const LanternState *state, size_t index) {
    if (!state || !state->validators || index >= state->validator_count) {
        return NULL;
    }
    return state->validators[index].proposal_pubkey;
}

static void lantern_root_zero(LanternRoot *root) {
    if (root) {
        memset(root->bytes, 0, LANTERN_ROOT_SIZE);
    }
}

void lantern_state_init(LanternState *state) {
    if (!state) {
        return;
    }
    memset(state, 0, sizeof(*state));
    lantern_root_list_init(&state->historical_block_hashes);
    lantern_bitlist_init(&state->justified_slots);
    lantern_root_list_init(&state->justification_roots);
    lantern_bitlist_init(&state->justification_validators);
}

void lantern_state_reset(LanternState *state) {
    if (!state) {
        return;
    }
    lantern_state_hash_cache_reset(state);
    lantern_root_list_reset(&state->historical_block_hashes);
    lantern_bitlist_reset(&state->justified_slots);
    lantern_root_list_reset(&state->justification_roots);
    lantern_bitlist_reset(&state->justification_validators);
    if (state->validators) {
        free(state->validators);
        state->validators = NULL;
        state->validator_count = 0;
        state->validator_capacity = 0;
    }
    memset(state, 0, sizeof(*state));
    lantern_root_list_init(&state->historical_block_hashes);
    lantern_bitlist_init(&state->justified_slots);
    lantern_root_list_init(&state->justification_roots);
    lantern_bitlist_init(&state->justification_validators);
}

int lantern_state_generate_genesis(LanternState *state, uint64_t genesis_time, uint64_t num_validators) {
    if (!state || num_validators == 0) {
        return -1;
    }
    if (num_validators > (uint64_t)LANTERN_VALIDATOR_REGISTRY_LIMIT) {
        return -1;
    }
    lantern_state_reset(state);
    state->config.num_validators = num_validators;
    state->config.genesis_time = genesis_time;
    state->slot = 0;

    lantern_root_zero(&state->latest_block_header.parent_root);
    lantern_root_zero(&state->latest_block_header.state_root);
    state->latest_block_header.slot = 0;
    state->latest_block_header.proposer_index = 0;

    LanternBlockBody empty_body;
    lantern_block_body_init(&empty_body);
    LanternRoot body_root;
    if (lantern_hash_tree_root_block_body(&empty_body, &body_root) != SSZ_SUCCESS) {
        lantern_block_body_reset(&empty_body);
        lantern_state_reset(state);
        return -1;
    }
    state->latest_block_header.body_root = body_root;
    lantern_block_body_reset(&empty_body);

    lantern_root_zero(&state->latest_justified.root);
    state->latest_justified.slot = 0;
    lantern_root_zero(&state->latest_finalized.root);
    state->latest_finalized.slot = 0;

    return 0;
}

int lantern_state_process_slot(LanternState *state) {
    if (!state) {
        return -1;
    }
    if (lantern_root_is_zero(&state->latest_block_header.state_root)) {
        LanternRoot computed;
        if (lantern_hash_tree_root_state_cached(state, &computed) != SSZ_SUCCESS) {
            return -1;
        }
        state->latest_block_header.state_root = computed;
    }
    return 0;
}

int lantern_state_process_slots(LanternState *state, uint64_t target_slot) {
    if (!state) {
        return -1;
    }
    if (target_slot <= state->slot) {
        const struct lantern_log_metadata meta = {
            .has_slot = true,
            .slot = state->slot,
        };
        lantern_log_warn(
            "state",
            &meta,
            "process slots target=%" PRIu64 " must be in the future (current=%" PRIu64 ")",
            target_slot,
            state->slot);
        return -1;
    }
    while (state->slot < target_slot) {
        if (lantern_state_process_slot(state) != 0) {
            return -1;
        }
        if (state->slot == UINT64_MAX) {
            return -1;
        }
        state->slot += 1;
        lantern_log_debug(
            "state",
            &(const struct lantern_log_metadata){
                .has_slot = true,
                .slot = state->slot},
            "slot advanced");
    }
    return 0;
}







int lantern_state_mark_justified_slot(LanternState *state, uint64_t slot) {
    if (!state) {
        return -1;
    }
    if (slot > SIZE_MAX) {
        return -1;
    }
    return lantern_state_set_justified_slot_bit(state, slot, true);
}

int lantern_state_process_block_header(LanternState *state, const LanternBlock *block) {
    if (!state || !block) {
        return -1;
    }
    const struct lantern_log_metadata meta = {
        .has_slot = true,
        .slot = block->slot,
    };
    if (block->slot != state->slot) {
        lantern_log_warn(
            "state",
            &meta,
            "header rejected: block slot %" PRIu64 " expected state slot %" PRIu64,
            block->slot,
            state->slot);
        return -1;
    }
    if (block->slot <= state->latest_block_header.slot) {
        const char *reason = block->slot == state->latest_block_header.slot ? "duplicate" : "stale";
        lantern_log_warn(
            "state",
            &meta,
            "header rejected: %s slot %" PRIu64 " latest %" PRIu64,
            reason,
            block->slot,
            state->latest_block_header.slot);
        return -1;
    }
    uint64_t expected_proposer = 0;
    if (lantern_proposer_for_slot(block->slot, state->config.num_validators, &expected_proposer) != 0) {
        return -1;
    }
    if (block->proposer_index != expected_proposer) {
        lantern_log_warn(
            "state",
            &meta,
            "header rejected: proposer %" PRIu64 " expected %" PRIu64,
            block->proposer_index,
            expected_proposer);
        return -1;
    }

    LanternRoot latest_header_root;
    if (lantern_hash_tree_root_block_header(&state->latest_block_header, &latest_header_root) != SSZ_SUCCESS) {
        return -1;
    }
    if (memcmp(block->parent_root.bytes, latest_header_root.bytes, LANTERN_ROOT_SIZE) != 0) {
        char expected_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
        char received_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
        if (lantern_bytes_to_hex(
                latest_header_root.bytes,
                LANTERN_ROOT_SIZE,
                expected_hex,
                sizeof(expected_hex),
                1)
            != 0) {
            expected_hex[0] = '\0';
        }
        if (lantern_bytes_to_hex(
                block->parent_root.bytes,
                LANTERN_ROOT_SIZE,
                received_hex,
                sizeof(received_hex),
                1)
            != 0) {
            received_hex[0] = '\0';
        }
        lantern_log_warn(
            "state",
            &meta,
            "header rejected: parent mismatch expected=%s received=%s",
            expected_hex[0] ? expected_hex : "0x0",
            received_hex[0] ? received_hex : "0x0");
        return -1;
    }

    if (state->latest_block_header.slot == 0) {
        state->latest_justified.root = block->parent_root;
        state->latest_finalized.root = block->parent_root;
    }

    uint64_t parent_slot = state->latest_block_header.slot;
    if (lantern_state_append_historical_root(state, &block->parent_root) != 0) {
        return -1;
    }
    if (lantern_state_set_justified_slot_bit(state, parent_slot, parent_slot == 0) != 0) {
        return -1;
    }

    uint64_t delta = block->slot - parent_slot;
    if (delta > 1) {
        LanternRoot zero_root;
        lantern_root_zero(&zero_root);
        for (uint64_t i = 0; i < delta - 1; ++i) {
            uint64_t slot = parent_slot + 1 + i;
            if (lantern_state_append_historical_root(state, &zero_root) != 0) {
                return -1;
            }
            if (lantern_state_set_justified_slot_bit(state, slot, false) != 0) {
                return -1;
            }
        }
    }

    LanternRoot body_root;
    if (lantern_hash_tree_root_block_body(&block->body, &body_root) != SSZ_SUCCESS) {
        return -1;
    }
    state->latest_block_header.slot = block->slot;
    state->latest_block_header.proposer_index = block->proposer_index;
    state->latest_block_header.parent_root = block->parent_root;
    state->latest_block_header.body_root = body_root;
    lantern_root_zero(&state->latest_block_header.state_root);

    return 0;
}

int lantern_state_process_attestations(
    LanternState *state,
    LanternStore *store,
    const LanternAttestations *attestations,
    const LanternSignatureList *signatures) {
    if (!state || !store || !attestations) {
        return -1;
    }
    uint64_t validator_count_u64 = state->config.num_validators;
    if (validator_count_u64 == 0 || validator_count_u64 > SIZE_MAX) {
        return -1;
    }
    size_t validator_count = (size_t)validator_count_u64;
    const struct lantern_log_metadata meta = {
        .has_slot = true,
        .slot = state->slot,
    };
    if (!store->validator_votes || store->validator_votes_len != validator_count) {
        return -1;
    }

    if (attestations->length > LANTERN_MAX_ATTESTATIONS) {
        return -1;
    }
    for (size_t i = 0; i < state->justification_roots.length; ++i) {
        if (lantern_root_is_zero(&state->justification_roots.items[i])) {
            lantern_log_warn(
                "state",
                &meta,
                "zero hash is not allowed in justification roots");
            return -1;
        }
    }

    LanternCheckpoint latest_justified = state->latest_justified;
    LanternCheckpoint latest_finalized = state->latest_finalized;
    uint64_t finalized_slot = latest_finalized.slot;
    double att_batch_start = lantern_time_now_seconds();
    size_t att_attempted = 0;
    bool finalization_attempted = false;

    for (size_t i = 0; i < attestations->length; ++i) {
        const LanternVote *vote = &attestations->data[i];
        const LanternSignature *signature = NULL;
        if (signatures && signatures->data && i < signatures->length) {
            signature = &signatures->data[i];
        }
        att_attempted += 1;
        double att_validation_start = lantern_time_now_seconds();
        if (vote->validator_id >= validator_count) {
            lantern_log_warn(
                "state",
                &meta,
                "attestation rejected: validator %" PRIu64 " out of range (validators=%" PRIu64 ")",
                vote->validator_id,
                (uint64_t)validator_count);
            record_attestation_validation_metric(att_validation_start, false);
            continue;
        }
        if (vote->target.slot <= vote->source.slot) {
            /* LeanSpec: silently skip if target <= source (state.py:406) */
            continue;
        }
        if (!lantern_state_slot_in_justified_window(state, vote->source.slot)) {
            /* LeanSpec: silently skip attestations with source outside justified window */
            continue;
        }
        bool source_is_justified = false;
        /* LeanSpec checks against live justified_slots, so earlier votes in this
         * loop may unlock later votes in the same block. */
        if (lantern_state_get_justified_slot_bit(state, vote->source.slot, &source_is_justified) != 0) {
            /* LeanSpec: silently skip if we can't read source justified status */
            continue;
        }
        if (!source_is_justified) {
            /* LeanSpec: silently skip attestations with unjustified source (state.py:386) */
            continue;
        }

        /* LeanSpec: skip if source, target, or head root mismatches history. */
        if (!lantern_vote_matches_history(vote, &state->historical_block_hashes)) {
            continue;
        }

        bool target_is_justified = false;
        if (lantern_state_slot_in_justified_window(state, vote->target.slot)) {
            if (lantern_state_get_justified_slot_bit(state, vote->target.slot, &target_is_justified) != 0) {
                /* LeanSpec: silently skip if we can't read target justified status */
                continue;
            }
        }
        LanternSignedVote stored_vote;
        memset(&stored_vote, 0, sizeof(stored_vote));
        stored_vote.data = *vote;
        if (signature) {
            stored_vote.signature = *signature;
        }
        if (lantern_store_set_signed_validator_vote(store, (size_t)vote->validator_id, &stored_vote) != 0) {
            record_attestation_validation_metric(att_validation_start, false);
            return -1;
        }

        /* Skip if target is already justified (leanSpec line 394) */
        if (target_is_justified) {
            record_attestation_validation_metric(att_validation_start, true);
            continue;
        }

        /* Target slot must remain justifiable after the current finalized slot. */
        if (!lantern_slot_is_justifiable(vote->target.slot, finalized_slot)) {
            record_attestation_validation_metric(att_validation_start, true);
            continue;
        }

        /* Track vote for justification - find or add the target root */
        int root_idx = lantern_state_find_justification_root_index(state, &vote->target.root);
        if (root_idx < 0) {
            /* New target root - add to tracking */
            root_idx = lantern_state_add_justification_root(state, &vote->target.root, validator_count);
            if (root_idx < 0) {
                lantern_log_warn(
                    "state",
                    &meta,
                    "failed to add justification root for slot %" PRIu64,
                    vote->target.slot);
                record_attestation_validation_metric(att_validation_start, false);
                continue;
            }
        }

        /* Check if this validator already voted for this target */
        bool already_voted = false;
        if (lantern_state_get_justification_vote(state, root_idx, (size_t)vote->validator_id, validator_count, &already_voted) != 0) {
            record_attestation_validation_metric(att_validation_start, false);
            continue;
        }

        /* Record the validator's vote if they haven't voted yet */
        if (!already_voted) {
            if (lantern_state_set_justification_vote(state, root_idx, (size_t)vote->validator_id, validator_count, true) != 0) {
                record_attestation_validation_metric(att_validation_start, false);
                continue;
            }
        }

        /* Count total votes for this target */
        size_t vote_count = lantern_state_count_justification_votes(state, root_idx, validator_count);
        size_t quorum = lantern_quorum_threshold(validator_count_u64);

        /* Check if 2/3 supermajority reached (leanSpec line 428: 3 * count >= 2 * validators) */
        if (vote_count >= quorum) {
            /* Supermajority reached - mark as justified */
            if (lantern_state_mark_justified_slot(state, vote->target.slot) != 0) {
                record_attestation_validation_metric(att_validation_start, false);
                return -1;
            }
            if (vote->target.slot > latest_justified.slot) {
                latest_justified = vote->target;
            }

            /* Clean up tracking for this root (leanSpec line 431) */
            if (lantern_state_remove_justification_root(state, root_idx, validator_count) != 0) {
                lantern_log_warn(
                    "state",
                    &meta,
                    "failed to remove justification root after justifying slot %" PRIu64,
                    vote->target.slot);
            }

            /* Finalization: if the source is newer than the finalized boundary and
             * the target is the next valid justifiable slot after source relative
             * to that boundary, finalize the source checkpoint.
             */
            bool source_after_finalized = vote->source.slot > finalized_slot;
            bool has_justifiable_between =
                source_after_finalized
                && has_justifiable_slot_between(vote->source.slot, vote->target.slot, finalized_slot);
            bool vote_has_consecutive_source = source_after_finalized && !has_justifiable_between;

            if (vote_has_consecutive_source) {
                /* Finalize the source checkpoint */
                uint64_t old_finalized_slot = finalized_slot;
                latest_finalized = vote->source;
                finalized_slot = latest_finalized.slot;
                finalization_attempted = true;
                lean_metrics_record_finalization_attempt(true);
                if (finalized_slot > old_finalized_slot) {
                    uint64_t delta = finalized_slot - old_finalized_slot;
                    if (delta > SIZE_MAX) {
                        if (finalization_attempted) {
                            lean_metrics_record_finalization_attempt(false);
                        }
                        record_attestation_validation_metric(att_validation_start, false);
                        return -1;
                    }
                    if (delta > 0) {
                        if (lantern_bitlist_drop_front(&state->justified_slots, (size_t)delta) != 0) {
                            if (finalization_attempted) {
                                lean_metrics_record_finalization_attempt(false);
                            }
                            record_attestation_validation_metric(att_validation_start, false);
                            return -1;
                        }
                    }
                    state->latest_finalized = latest_finalized;
                    if (lantern_state_prune_justification_roots(
                            state,
                            old_finalized_slot,
                            finalized_slot,
                            validator_count,
                            &meta)
                        != 0) {
                        if (finalization_attempted) {
                            lean_metrics_record_finalization_attempt(false);
                        }
                        record_attestation_validation_metric(att_validation_start, false);
                        return -1;
                    }
                }
            }
        }

        record_attestation_validation_metric(att_validation_start, true);
    }

    if (lantern_state_mark_justified_slot(state, latest_justified.slot) != 0) {
        if (finalization_attempted) {
            lean_metrics_record_finalization_attempt(false);
        }
        return -1;
    }
    if (lantern_state_mark_justified_slot(state, latest_finalized.slot) != 0) {
        if (finalization_attempted) {
            lean_metrics_record_finalization_attempt(false);
        }
        return -1;
    }

    state->latest_justified = latest_justified;
    state->latest_finalized = latest_finalized;
    if (store->fork_choice) {
        if (lantern_fork_choice_update_checkpoints(
                store->fork_choice,
                &state->latest_justified,
                &state->latest_finalized)
            != 0) {
            if (finalization_attempted) {
                lean_metrics_record_finalization_attempt(false);
            }
            return -1;
        }
    }
    lean_metrics_record_state_transition_attestations(att_attempted, lantern_time_now_seconds() - att_batch_start);
    return 0;
}

int lantern_state_process_block(
    LanternState *state,
    LanternStore *store,
    const LanternBlock *block) {
    if (!state || !store || !block) {
        return -1;
    }
    if (lantern_state_validate_block_attestation_data_uniqueness(block) != 0) {
        return -1;
    }
    double block_metrics_start = lantern_time_now_seconds();
    if (lantern_state_process_block_header(state, block) != 0) {
        return -1;
    }
    size_t validator_count = 0;
    if (state->config.num_validators > SIZE_MAX) {
        return -1;
    }
    validator_count = (size_t)state->config.num_validators;
    LanternAttestations expanded = {0};
    lantern_attestations_init(&expanded);
    if (lantern_expand_aggregated_attestations(&block->body.attestations, validator_count, &expanded) != 0) {
        lantern_attestations_reset(&expanded);
        return -1;
    }
    if (lantern_state_process_attestations(state, store, &expanded, NULL) != 0) {
        lantern_attestations_reset(&expanded);
        return -1;
    }
    lantern_attestations_reset(&expanded);

    lean_metrics_record_state_transition_block(lantern_time_now_seconds() - block_metrics_start);
    return 0;
}

int lantern_state_transition(LanternState *state, LanternStore *store, const LanternSignedBlock *signed_block) {
    if (!state || !store || !signed_block) {
        return -1;
    }
    const LanternBlock *block = &signed_block->block;
    double transition_metrics_start = lantern_time_now_seconds();
#define STATE_FAIL(fmt, ...)                                                                 \
    do {                                                                                     \
        lantern_log_warn(                                                                    \
            "state",                                                                         \
            &(const struct lantern_log_metadata){.has_slot = true, .slot = block->slot},     \
            fmt,                                                                             \
            ##__VA_ARGS__);                                                                  \
        return -1;                                                                           \
    } while (0)

    if (block->slot <= state->slot) {
        STATE_FAIL("block slot %" PRIu64 " not ahead of state %" PRIu64, block->slot, state->slot);
    }
    if (signed_block->proof.length == 0u || !signed_block->proof.data) {
        STATE_FAIL("block proof missing");
    }
    if (!lantern_signature_verify_block_type2_proof(state, block, &signed_block->proof)) {
        STATE_FAIL("block proof invalid");
    }
    uint64_t slot_before = state->slot;
    double slots_metrics_start = lantern_time_now_seconds();
    if (lantern_state_process_slots(state, block->slot) != 0) {
        STATE_FAIL("process slots failed current=%" PRIu64, state->slot);
    }
    double slots_duration = lantern_time_now_seconds() - slots_metrics_start;
    uint64_t slots_processed = block->slot >= slot_before ? (block->slot - slot_before) : 0;
    lean_metrics_record_state_transition_slots(slots_processed, slots_duration);
    if (lantern_state_process_block(state, store, block) != 0) {
        STATE_FAIL("process block failed");
    }
    LanternRoot computed_state_root;
    bool hashed_state = lantern_hash_tree_root_state_cached(state, &computed_state_root) == SSZ_SUCCESS;
    if (hashed_state) {
        if (memcmp(block->state_root.bytes, computed_state_root.bytes, LANTERN_ROOT_SIZE) != 0) {
            char expected_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
            char computed_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
            if (lantern_bytes_to_hex(
                    block->state_root.bytes,
                    LANTERN_ROOT_SIZE,
                    expected_hex,
                    sizeof(expected_hex),
                    1)
                != 0) {
                expected_hex[0] = '\0';
            }
            if (lantern_bytes_to_hex(
                    computed_state_root.bytes,
                    LANTERN_ROOT_SIZE,
                    computed_hex,
                    sizeof(computed_hex),
                    1)
                != 0) {
                computed_hex[0] = '\0';
            }
            lantern_log_warn(
                "state",
                &(const struct lantern_log_metadata){.has_slot = true, .slot = block->slot},
                "state root mismatch: expected=%s computed=%s",
                expected_hex[0] ? expected_hex : "0x0",
                computed_hex[0] ? computed_hex : "0x0");
            char finalized_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
            char justified_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
            finalized_hex[0] = '\0';
            justified_hex[0] = '\0';
            if (lantern_bytes_to_hex(
                    state->latest_finalized.root.bytes,
                    LANTERN_ROOT_SIZE,
                    finalized_hex,
                    sizeof(finalized_hex),
                    1)
                != 0) {
                finalized_hex[0] = '\0';
            }
            if (lantern_bytes_to_hex(
                    state->latest_justified.root.bytes,
                    LANTERN_ROOT_SIZE,
                    justified_hex,
                    sizeof(justified_hex),
                    1)
                != 0) {
                justified_hex[0] = '\0';
            }
            lantern_log_warn(
                "state",
                &(const struct lantern_log_metadata){.has_slot = true, .slot = block->slot},
                "state root context state_slot=%" PRIu64 " header_slot=%" PRIu64
                " finalized_slot=%" PRIu64 " justified_anchor=%" PRIu64
                " justified_bits=%zu hist_len=%zu"
                " just_roots=%zu just_votes=%zu",
                state->slot,
                state->latest_block_header.slot,
                state->latest_finalized.slot,
                lantern_state_justified_slots_anchor(state),
                state->justified_slots.bit_length,
                state->historical_block_hashes.length,
                state->justification_roots.length,
                state->justification_validators.bit_length);
            lantern_log_warn(
                "state",
                &(const struct lantern_log_metadata){.has_slot = true, .slot = block->slot},
                "state root checkpoints finalized_slot=%" PRIu64 " finalized_root=%s"
                " justified_slot=%" PRIu64 " justified_root=%s",
                state->latest_finalized.slot,
                finalized_hex[0] ? finalized_hex : "0x0",
                state->latest_justified.slot,
                justified_hex[0] ? justified_hex : "0x0");
            STATE_FAIL("state root mismatch for slot %" PRIu64, block->slot);
        }
    } else {
        STATE_FAIL("failed to hash state for slot %" PRIu64, block->slot);
    }

    if (store->fork_choice) {
        if (lantern_fork_choice_add_block_with_state(
                store->fork_choice,
                block,
                &state->latest_justified,
                &state->latest_finalized,
                NULL,
                state)
            != 0) {
            STATE_FAIL("fork choice add block failed for slot %" PRIu64, block->slot);
        }
    }

    state->slot = block->slot;
    lean_metrics_record_state_transition(lantern_time_now_seconds() - transition_metrics_start);
#undef STATE_FAIL
    return 0;
}

int lantern_state_select_block_parent(
    LanternState *state,
    const LanternStore *store,
    LanternRoot *out_parent_root) {
    if (!state || !store || !out_parent_root) {
        return -1;
    }
    if (state->config.num_validators == 0) {
        return -1;
    }

    if (store->fork_choice) {
        LanternRoot head_root;
        if (lantern_fork_choice_current_head(store->fork_choice, &head_root) != 0) {
            return -1;
        }
        if (lantern_state_cached_fork_choice_state_for_root(store, &head_root)) {
            *out_parent_root = head_root;
            return 0;
        }
    }

    if (lantern_state_process_slot(state) != 0) {
        return -1;
    }

    LanternRoot header_root;
    if (lantern_hash_tree_root_block_header(&state->latest_block_header, &header_root) != SSZ_SUCCESS) {
        return -1;
    }

    if (store->fork_choice) {
        LanternRoot head_root;
        if (lantern_fork_choice_current_head(store->fork_choice, &head_root) != 0) {
            return -1;
        }
        if (memcmp(head_root.bytes, header_root.bytes, LANTERN_ROOT_SIZE) != 0) {
            return -1;
        }
        *out_parent_root = head_root;
        return 0;
    }

    *out_parent_root = header_root;
    return 0;
}

int lantern_state_collect_attestations_for_block(
    const LanternState *state,
    const LanternStore *store,
    uint64_t block_slot,
    uint64_t proposer_index,
    const LanternRoot *parent_root,
    LanternAggregatedAttestations *out_attestations,
    LanternAttestationSignatures *out_signatures) {
    if (!state || !store || !out_attestations || !out_signatures || !parent_root) {
        return -1;
    }
    const LanternState *base_state = lantern_state_cached_fork_choice_state_for_root(store, parent_root);
    if (!base_state) {
        base_state = state;
    }
    if (block_slot <= base_state->slot) {
        return -1;
    }
    if (lantern_aggregated_attestations_resize(out_attestations, 0) != 0) {
        return -1;
    }
    if (lantern_attestation_signatures_resize(out_signatures, 0) != 0) {
        (void)lantern_aggregated_attestations_resize(out_attestations, 0);
        return -1;
    }

    LanternState slot_snapshot;
    lantern_state_init(&slot_snapshot);
    LanternState scratch;
    lantern_state_init(&scratch);
    LanternStore scratch_store;
    lantern_store_init(&scratch_store);
    struct lantern_root_list processed_data_roots;
    lantern_root_list_init(&processed_data_roots);
    int rc = 0;

    if (lantern_state_clone(base_state, &slot_snapshot) != 0) {
        rc = -1;
        goto cleanup;
    }
    if (lantern_state_process_slots(&slot_snapshot, block_slot) != 0) {
        rc = -1;
        goto cleanup;
    }

    LanternCheckpoint checkpoint = slot_snapshot.latest_justified;
    if (slot_snapshot.latest_block_header.slot == 0u) {
        checkpoint.root = *parent_root;
    }
    /* LeanSpec build_block re-runs the filter against the post-state justified
     * slots, so each converged iteration may unlock further sources. */
    const LanternState *justified_view = &slot_snapshot;
    size_t iteration = 0;
    size_t iteration_guard = store->known_aggregated_payloads.length + 1u;
    if (iteration_guard == 0u) {
        iteration_guard = 1u;
    }
    if (iteration_guard < SIZE_MAX) {
        iteration_guard += 1u;
    }
    const struct lantern_log_metadata meta = {
        .has_slot = true,
        .slot = block_slot,
    };
    while (true) {
        size_t previous_attestation_count = out_attestations->length;
        if (collect_attestations_for_checkpoint(
                &slot_snapshot,
                justified_view,
                store,
                parent_root,
                block_slot,
                &processed_data_roots,
                out_attestations,
                out_signatures)
            != 0) {
            rc = -1;
            goto cleanup;
        }
        if (out_attestations->length == previous_attestation_count) {
            break;
        }

        lantern_state_reset(&scratch);
        if (lantern_state_clone(&slot_snapshot, &scratch) != 0) {
            rc = -1;
            goto cleanup;
        }
        lantern_store_reset(&scratch_store);
        lantern_store_init(&scratch_store);
        if (lantern_store_prepare_validator_votes(&scratch_store, scratch.config.num_validators) != 0) {
            rc = -1;
            goto cleanup;
        }

        LanternBlock candidate;
        memset(&candidate, 0, sizeof(candidate));
        candidate.slot = block_slot;
        candidate.proposer_index = proposer_index;
        candidate.parent_root = *parent_root;
        candidate.body.attestations.data = out_attestations->data;
        candidate.body.attestations.length = out_attestations->length;
        candidate.body.attestations.capacity = out_attestations->length;

        if (lantern_state_process_block(&scratch, &scratch_store, &candidate) != 0) {
            rc = -1;
            goto cleanup;
        }

        LanternCheckpoint post_checkpoint = scratch.latest_justified;
        if (lantern_checkpoint_equal(&post_checkpoint, &checkpoint)) {
            break;
        }
        checkpoint = post_checkpoint;
        justified_view = &scratch;
        iteration += 1u;
        if (iteration > iteration_guard) {
            uint64_t store_justified_slot = 0u;
            if (store->fork_choice) {
                const LanternCheckpoint *store_justified =
                    lantern_fork_choice_latest_justified(store->fork_choice);
                store_justified_slot = store_justified ? store_justified->slot : 0u;
            }
            lantern_log_warn(
                "propose",
                &meta,
                "slot %" PRIu64 ", skipped, reason: fixed_point_not_converged"
                ", block_justified_slot %" PRIu64 ", store_justified_slot %" PRIu64,
                block_slot,
                checkpoint.slot,
                store_justified_slot);
            rc = -1;
            break;
        }
    }

	cleanup:
    lantern_store_reset(&scratch_store);
    lantern_state_reset(&scratch);
    lantern_state_reset(&slot_snapshot);
    lantern_root_list_reset(&processed_data_roots);
    if (rc != 0) {
        (void)lantern_aggregated_attestations_resize(out_attestations, 0);
        (void)lantern_attestation_signatures_resize(out_signatures, 0);
    }
    return rc;
}

int lantern_state_compute_post_state(
    const LanternState *state,
    const LanternStore *store,
    const LanternSignedBlock *block,
    LanternState *out_post_state,
    LanternStore *out_post_store,
    LanternRoot *out_state_root) {
    if (!state || !store || !block) {
        return -1;
    }
    const LanternState *base_state = lantern_state_cached_fork_choice_state_for_root(
        store,
        &block->block.parent_root);
    if (!base_state) {
        base_state = state;
    }
    if (block->block.slot <= base_state->slot) {
        return -1;
    }
    LanternState scratch;
    lantern_state_init(&scratch);
    LanternStore scratch_store;
    lantern_store_init(&scratch_store);
    if (lantern_state_clone(base_state, &scratch) != 0) {
        return -1;
    }
    if (lantern_store_clone_validator_votes(store, &scratch_store) != 0) {
        lantern_state_reset(&scratch);
        return -1;
    }
    int rc = 0;
    if (lantern_state_process_slots(&scratch, block->block.slot) != 0) {
        rc = -1;
        goto cleanup;
    }
    if (lantern_state_process_block(&scratch, &scratch_store, &block->block) != 0) {
        rc = -1;
        goto cleanup;
    }
    if (out_state_root && lantern_hash_tree_root_state_cached(&scratch, out_state_root) != SSZ_SUCCESS) {
        rc = -1;
        goto cleanup;
    }
    if (out_post_state) {
        *out_post_state = scratch;
        lantern_state_init(&scratch);
    }
    if (out_post_store) {
        *out_post_store = scratch_store;
        lantern_store_init(&scratch_store);
    }

cleanup:
    lantern_store_reset(&scratch_store);
    lantern_state_reset(&scratch);
    return rc;
}

int lantern_state_preview_post_state_root(
    const LanternState *state,
    const LanternStore *store,
    const LanternSignedBlock *block,
    LanternRoot *out_state_root) {
    if (!out_state_root) {
        return -1;
    }
    return lantern_state_compute_post_state(
        state,
        store,
        block,
        NULL,
        NULL,
        out_state_root);
}

int lantern_state_compute_vote_checkpoints(
    const LanternState *state,
    const LanternStore *store,
    LanternCheckpoint *out_head,
    LanternCheckpoint *out_target,
    LanternCheckpoint *out_source) {
    if (!state || !store || !out_head || !out_target || !out_source) {
        return -1;
    }
    if (!store->fork_choice) {
        return -1;
    }

    const LanternForkChoice *fork_choice = store->fork_choice;
    LanternRoot head_root;
    if (lantern_fork_choice_current_head(fork_choice, &head_root) != 0) {
        return -1;
    }
    const LanternState *base_state = lantern_state_cached_fork_choice_state_for_root(store, &head_root);
    if (!base_state) {
        base_state = state;
    }
    uint64_t head_slot = 0;
    if (lantern_fork_choice_block_info(fork_choice, &head_root, &head_slot, NULL, NULL) != 0) {
        return -1;
    }
    const LanternCheckpoint *store_latest_finalized =
        lantern_fork_choice_latest_finalized(fork_choice);
    LanternCheckpoint source_checkpoint = base_state->latest_justified;
    LanternCheckpoint finalized_checkpoint = base_state->latest_finalized;
    /* Normalize the genesis placeholder root from the head state. */
    if (lantern_root_is_zero(&source_checkpoint.root)) {
        source_checkpoint.root = head_root;
    }
    if (store_latest_finalized && !lantern_root_is_zero(&store_latest_finalized->root)) {
        finalized_checkpoint = *store_latest_finalized;
    }
    LanternRoot target_root = head_root;
    uint64_t target_slot = head_slot;

    uint64_t safe_slot = head_slot;
    bool has_safe = false;
    const LanternRoot *safe_ptr = lantern_fork_choice_safe_target(fork_choice);
    if (safe_ptr) {
        if (lantern_fork_choice_block_info(fork_choice, safe_ptr, &safe_slot, NULL, NULL) != 0) {
            return -1;
        }
        has_safe = true;
    }

    if (has_safe) {
        uint64_t lower_bound_slot =
            safe_slot > finalized_checkpoint.slot ? safe_slot : finalized_checkpoint.slot;
        for (size_t i = 0; i < 3 && target_slot > lower_bound_slot; ++i) {
            LanternRoot parent_root;
            bool has_parent = false;
            if (lantern_fork_choice_block_info(
                    fork_choice,
                    &target_root,
                    &target_slot,
                    &parent_root,
                    &has_parent)
                != 0) {
                return -1;
            }
            if (!has_parent) {
                break;
            }
            uint64_t parent_slot = 0;
            if (lantern_fork_choice_block_info(fork_choice, &parent_root, &parent_slot, NULL, NULL) != 0) {
                return -1;
            }
            target_root = parent_root;
            target_slot = parent_slot;
        }
    }

    while (!lantern_slot_is_justifiable(target_slot, finalized_checkpoint.slot)) {
        LanternRoot parent_root;
        bool has_parent = false;
        if (lantern_fork_choice_block_info(
                fork_choice,
                &target_root,
                &target_slot,
                &parent_root,
                &has_parent)
            != 0) {
            return -1;
        }
        if (!has_parent) {
            break;
        }
        uint64_t parent_slot = 0;
        if (lantern_fork_choice_block_info(fork_choice, &parent_root, &parent_slot, NULL, NULL) != 0) {
            return -1;
        }
        if (parent_slot < finalized_checkpoint.slot) {
            break;
        }
        target_root = parent_root;
        target_slot = parent_slot;
    }

    if (target_slot < source_checkpoint.slot) {
        target_root = source_checkpoint.root;
        target_slot = source_checkpoint.slot;
    }
    out_head->root = head_root;
    out_head->slot = head_slot;
    out_target->root = target_root;
    out_target->slot = target_slot;
    *out_source = source_checkpoint;
    return 0;
}
