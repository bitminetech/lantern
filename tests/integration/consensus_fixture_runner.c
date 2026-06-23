#include "lantern/consensus/containers.h"
#include "lantern/consensus/fork_choice.h"
#include "lantern/consensus/hash.h"
#include "lantern/consensus/state.h"
#include "lantern/consensus/store.h"
#include "lantern/consensus/ssz.h"
#include "lantern/support/log.h"
#include "lantern/support/strings.h"
#include "fixture_runner.h"
#include "tests/support/fixture_loader.h"
#include "../support/state_store_adapter.h"

#include <dirent.h>
#include <errno.h>
#include <inttypes.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <limits.h>

#define LABEL_MAX_LENGTH 64
#define MAX_LABELS 128


static void configure_logging(void) {
    const char *env_level = getenv("LANTERN_LOG_LEVEL");
    if (env_level && env_level[0] != '\0') {
        if (lantern_log_set_level_from_string(env_level, NULL) != 0) {
            fprintf(stderr, "invalid LANTERN_LOG_LEVEL '%s'\n", env_level);
        }
        return;
    }
    lantern_log_set_level(LANTERN_LOG_LEVEL_WARN);
}

static bool is_root_zero(const LanternRoot *root) {
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

static int preview_post_state_root_without_signatures(
    const LanternState *state,
    const LanternSignedBlock *signed_block,
    LanternRoot *out_state_root) {
    if (!state || !signed_block || !out_state_root) {
        return -1;
    }
    if (signed_block->block.slot <= state->slot) {
        return -1;
    }

    LanternState scratch;
    LanternStore scratch_store;
    lantern_state_init(&scratch);
    lantern_store_init(&scratch_store);
    if (lantern_state_clone_explicit(state, &scratch) != 0) {
        lantern_store_reset(&scratch_store);
        return -1;
    }

    int rc = 0;
    if (lantern_state_process_slots(&scratch, signed_block->block.slot) != 0) {
        rc = -1;
        goto cleanup;
    }
    if (lantern_store_prepare_validator_votes(&scratch_store, scratch.config.num_validators) != 0) {
        rc = -1;
        goto cleanup;
    }

    if (lantern_test_state_process_block_with_store(&scratch, &scratch_store, &signed_block->block) != 0) {
        rc = -1;
        goto cleanup;
    }
    if (lantern_hash_tree_root_state(&scratch, out_state_root) != SSZ_SUCCESS) {
        rc = -1;
    }

cleanup:
    lantern_store_reset(&scratch_store);
    lantern_state_reset(&scratch);
    return rc;
}

static int state_transition_without_signatures(
    LanternState *state,
    const LanternSignedBlock *signed_block) {
    if (!state || !signed_block) {
        return -1;
    }

    const LanternBlock *block = &signed_block->block;
    if (block->slot <= state->slot) {
        return -1;
    }
    if (lantern_state_process_slots(state, block->slot) != 0) {
        return -1;
    }

    LanternStore scratch_store;
    lantern_store_init(&scratch_store);
    if (lantern_store_prepare_validator_votes(&scratch_store, state->config.num_validators) != 0) {
        lantern_store_reset(&scratch_store);
        return -1;
    }
    if (lantern_test_state_process_block_with_store(state, &scratch_store, block) != 0) {
        lantern_store_reset(&scratch_store);
        return -1;
    }
    lantern_store_reset(&scratch_store);

    LanternRoot computed_state_root;
    if (lantern_hash_tree_root_state(state, &computed_state_root) != SSZ_SUCCESS) {
        return -1;
    }
    if (memcmp(block->state_root.bytes, computed_state_root.bytes, LANTERN_ROOT_SIZE) != 0) {
        return -1;
    }
    return 0;
}

/* Patch block hashes to use C-computed values instead of LeanSpec-computed values.
 * LeanSpec uses variable-length XMSS signatures which produces different hashes.
 * This function computes the correct parent_root and state_root using C code.
 *
 * The parent_root must be computed considering that process_slot fills in
 * latest_block_header.state_root if it was zero (which changes the hash). */
static int patch_block_hashes_for_c_compat(
    LanternState *state,
    LanternSignedBlock *signed_block) {
    if (!state || !signed_block) {
        return -1;
    }

    /* Compute what latest_block_header will look like after slot processing.
     * If state_root is zero, process_slot fills it with hash(state). */
    LanternBlockHeader header_after_slots = state->latest_block_header;
    if (is_root_zero(&header_after_slots.state_root)) {
        if (lantern_hash_tree_root_state(state, &header_after_slots.state_root) != SSZ_SUCCESS) {
            return -1;
        }
    }

    /* Compute parent_root = hash(header_after_slots) */
    LanternRoot computed_parent;
    if (lantern_hash_tree_root_block_header(&header_after_slots, &computed_parent) != SSZ_SUCCESS) {
        return -1;
    }
    memcpy(signed_block->block.parent_root.bytes, computed_parent.bytes, LANTERN_ROOT_SIZE);

    /* The state_transition fixtures do not ship signature material. Preview using
     * the unsigned transition path that mirrors leanSpec's valid_signatures
     * precondition instead of the strict signed-block API. */
    LanternRoot computed_state_root;
    if (preview_post_state_root_without_signatures(state, signed_block, &computed_state_root) != 0) {
        return -1;
    }

    memcpy(signed_block->block.state_root.bytes, computed_state_root.bytes, LANTERN_ROOT_SIZE);

    return 0;
}

static bool aggregated_payload_has_validator(
    const LanternAggregatedSignatureProof *proof,
    size_t validator) {
    if (!proof || validator >= proof->participants.bit_length) {
        return false;
    }
    return lantern_bitlist_get(&proof->participants, validator);
}

static int extract_attestation_from_payload_pool(
    const LanternStore *store,
    const struct lantern_aggregated_payload_pool *pool,
    size_t validator,
    LanternAttestationData *out_attestation,
    bool *out_found) {
    if (!store || !pool || !out_attestation || !out_found) {
        return -1;
    }

    bool found = false;
    LanternAttestationData latest = {0};

    for (size_t i = 0; i < pool->length; ++i) {
        const struct lantern_aggregated_payload_entry *entry = &pool->entries[i];
        if (!aggregated_payload_has_validator(&entry->proof, validator)) {
            continue;
        }

        LanternAttestationData attestation;
        memset(&attestation, 0, sizeof(attestation));
        if (lantern_store_get_attestation_data(store, &entry->data_root, &attestation) != 0) {
            return -1;
        }

        if (!found || latest.slot < attestation.slot) {
            latest = attestation;
            found = true;
        }
    }

    if (found) {
        *out_attestation = latest;
    }
    *out_found = found;
    return 0;
}

static bool fixture_token_equals_literal(
    const struct lantern_fixture_document *doc,
    int index,
    const char *literal) {
    if (!doc || !literal || index < 0) {
        return false;
    }
    size_t length = 0;
    const char *value = lantern_fixture_token_string(doc, index, &length);
    size_t literal_length = strlen(literal);
    return value && length == literal_length && strncmp(value, literal, literal_length) == 0;
}

static int fixture_token_to_bool(
    const struct lantern_fixture_document *doc,
    int index,
    bool *out_value) {
    if (!doc || !out_value) {
        return -1;
    }
    const jsmntok_t *tok = lantern_fixture_token(doc, index);
    if (!tok || tok->type != JSMN_PRIMITIVE) {
        return -1;
    }
    size_t length = (size_t)(tok->end - tok->start);
    if (length == 4u && strncmp(doc->text + tok->start, "true", 4u) == 0) {
        *out_value = true;
        return 0;
    }
    if (length == 5u && strncmp(doc->text + tok->start, "false", 5u) == 0) {
        *out_value = false;
        return 0;
    }
    return -1;
}

static int collect_attestation_signature_inputs(
    const LanternStore *store,
    LanternAttestations *out_attestations,
    LanternSignatureList *out_signatures) {
    if (!store || !out_attestations || !out_signatures) {
        return -1;
    }
    if (lantern_attestations_resize(out_attestations, 0u) != 0
        || lantern_signature_list_resize(out_signatures, 0u) != 0) {
        return -1;
    }

    for (size_t i = 0; i < store->attestation_signatures.length; ++i) {
        const struct lantern_attestation_signature_entry *entry = &store->attestation_signatures.entries[i];
        LanternAttestationData data;
        memset(&data, 0, sizeof(data));
        if (lantern_store_get_attestation_data(store, &entry->key.data_root, &data) != 0) {
            continue;
        }

        LanternVote vote;
        memset(&vote, 0, sizeof(vote));
        vote.validator_id = entry->key.validator_index;
        vote.data = data;

        if (lantern_attestations_append(out_attestations, &vote) != 0
            || lantern_signature_list_append(out_signatures, &entry->signature) != 0) {
            return -1;
        }
    }
    return 0;
}

static int aggregate_pending_gossip_attestations(
    LanternState *state,
    LanternStore *store) {
    if (!state || !store) {
        return -1;
    }

    LanternAttestations attestations;
    LanternSignatureList signatures;
    LanternAggregatedAttestations aggregated_attestations;
    LanternAttestationSignatures aggregated_signatures;
    lantern_attestations_init(&attestations);
    lantern_signature_list_init(&signatures);
    lantern_aggregated_attestations_init(&aggregated_attestations);
    lantern_attestation_signatures_init(&aggregated_signatures);

    int rc = -1;
    if (collect_attestation_signature_inputs(store, &attestations, &signatures) != 0) {
        goto cleanup;
    }
    if (attestations.length == 0u) {
        rc = 0;
        goto cleanup;
    }

    LanternAttestationSignatureInputs signature_inputs = {
        .attestations = &attestations,
        .signatures = &signatures,
    };
    if (lantern_state_aggregate(
            state,
            store,
            &signature_inputs,
            &store->new_aggregated_payloads,
            &store->known_aggregated_payloads,
            &aggregated_attestations,
            &aggregated_signatures)
        != LANTERN_STATE_AGGREGATE_OK) {
        goto cleanup;
    }

    lantern_store_clear_new_aggregated_payloads(store);
    for (size_t i = 0; i < aggregated_attestations.length; ++i) {
        LanternRoot data_root;
        if (lantern_hash_tree_root_attestation_data(&aggregated_attestations.data[i].data, &data_root) != SSZ_SUCCESS) {
            goto cleanup;
        }
        if (lantern_store_add_new_aggregated_payload(
                store,
                &data_root,
                &aggregated_attestations.data[i].data,
                &aggregated_signatures.data[i],
                aggregated_attestations.data[i].data.target.slot)
            != 0) {
            goto cleanup;
        }
        (void)lantern_store_remove_attestation_signatures_for_data_root(store, &data_root);
    }

    rc = 0;

cleanup:
    lantern_attestations_reset(&attestations);
    lantern_signature_list_reset(&signatures);
    lantern_aggregated_attestations_reset(&aggregated_attestations);
    lantern_attestation_signatures_reset(&aggregated_signatures);
    return rc;
}

static int sync_payload_pools_after_time_advance(
    LanternForkChoice *fork_choice,
    LanternStore *store,
    LanternState *state,
    uint64_t previous_intervals,
    bool has_proposal) {
    if (!fork_choice || !store || !state) {
        return -1;
    }
    if (fork_choice->intervals_per_slot == 0u || fork_choice->time_intervals <= previous_intervals) {
        return 0;
    }

    for (uint64_t step = previous_intervals + 1u; step <= fork_choice->time_intervals; ++step) {
        uint64_t interval_index = step % fork_choice->intervals_per_slot;
        bool step_has_proposal = has_proposal && (step == fork_choice->time_intervals);
        if (interval_index == 2u) {
            if (aggregate_pending_gossip_attestations(state, store) != 0) {
                return -1;
            }
        }
        if (interval_index == 4u || (interval_index == 0u && step_has_proposal)) {
            (void)lantern_store_promote_new_aggregated_payloads(store);
        }
    }
    return 0;
}

static int record_block_body_known_payloads(
    LanternStore *store,
    const LanternSignedBlock *signed_block) {
    if (!store || !signed_block) {
        return -1;
    }
    const LanternAggregatedAttestations *attestations = &signed_block->block.body.attestations;
    for (size_t i = 0; i < attestations->length; ++i) {
        LanternRoot data_root;
        if (lantern_hash_tree_root_attestation_data(&attestations->data[i].data, &data_root) != SSZ_SUCCESS) {
            return -1;
        }
        if (lantern_store_add_attestation_data(
                store,
                &data_root,
                &attestations->data[i].data,
                attestations->data[i].data.target.slot)
            != 0) {
            return -1;
        }
        LanternAggregatedSignatureProof proof;
        lantern_aggregated_signature_proof_init(&proof);
        if (lantern_bitlist_resize(&proof.participants, attestations->data[i].aggregation_bits.bit_length) != 0) {
            lantern_aggregated_signature_proof_reset(&proof);
            return -1;
        }
        size_t byte_len = (proof.participants.bit_length + 7u) / 8u;
        if (byte_len > 0u) {
            if (!proof.participants.bytes || !attestations->data[i].aggregation_bits.bytes) {
                lantern_aggregated_signature_proof_reset(&proof);
                return -1;
            }
            memcpy(proof.participants.bytes, attestations->data[i].aggregation_bits.bytes, byte_len);
        }
        if (lantern_byte_list_resize(&proof.proof_data, 1u) != 0) {
            lantern_aggregated_signature_proof_reset(&proof);
            return -1;
        }
        proof.proof_data.data[0] = 0u;
        int add_rc = lantern_store_add_known_aggregated_payload(
            store,
            &data_root,
            &attestations->data[i].data,
            &proof,
            attestations->data[i].data.target.slot);
        lantern_aggregated_signature_proof_reset(&proof);
        if (add_rc != 0) {
            return -1;
        }
    }
    return 0;
}

static int process_gossip_attestation_step(
    const struct lantern_fixture_document *doc,
    int step_idx,
    LanternStore *store) {
    if (!doc || !store) {
        return -1;
    }
    int attestation_idx = lantern_fixture_object_get_field(doc, step_idx, "attestation");
    if (attestation_idx < 0) {
        return -1;
    }

    LanternSignedVote vote;
    if (lantern_fixture_parse_attestation_message(doc, attestation_idx, &vote) != 0) {
        return -1;
    }

    LanternRoot data_root;
    if (lantern_hash_tree_root_attestation_data(&vote.data.data, &data_root) != SSZ_SUCCESS) {
        return -1;
    }

    LanternSignatureKey key = {
        .validator_index = (LanternValidatorIndex)vote.data.validator_id,
        .data_root = data_root,
    };
    return lantern_store_set_attestation_signature(
        store,
        &key,
        &vote.data.data,
        &vote.signature,
        vote.data.data.target.slot);
}

static int process_gossip_aggregated_attestation_step(
    const struct lantern_fixture_document *doc,
    int step_idx,
    LanternStore *store) {
    if (!doc || !store) {
        return -1;
    }
    int attestation_idx = lantern_fixture_object_get_field(doc, step_idx, "attestation");
    if (attestation_idx < 0) {
        return -1;
    }
    int data_idx = lantern_fixture_object_get_field(doc, attestation_idx, "data");
    int proof_idx = lantern_fixture_object_get_field(doc, attestation_idx, "proof");
    if (data_idx < 0 || proof_idx < 0) {
        return -1;
    }

    LanternAttestationData data;
    LanternAggregatedSignatureProof proof;
    memset(&data, 0, sizeof(data));
    lantern_aggregated_signature_proof_init(&proof);

    int rc = -1;
    if (lantern_fixture_parse_attestation_data(doc, data_idx, &data) != 0) {
        goto cleanup;
    }
    if (lantern_fixture_parse_signature_proof(doc, proof_idx, &proof) != 0) {
        goto cleanup;
    }

    LanternRoot data_root;
    if (lantern_hash_tree_root_attestation_data(&data, &data_root) != SSZ_SUCCESS) {
        goto cleanup;
    }
    rc = lantern_store_add_new_aggregated_payload(
        store,
        &data_root,
        &data,
        &proof,
        data.target.slot);

cleanup:
    lantern_aggregated_signature_proof_reset(&proof);
    return rc;
}

struct stored_vote_entry {
    bool has_vote;
    LanternVote vote;
};

struct stored_state_entry {
    LanternRoot root;
    LanternState state;
    bool has_state;
    struct stored_vote_entry *votes;
    size_t vote_count;
};

static void stored_state_entries_reset(struct stored_state_entry **entries_ptr, size_t *count_ptr, size_t *cap_ptr) {
    if (!entries_ptr || !count_ptr || !cap_ptr) {
        return;
    }
    struct stored_state_entry *entries = *entries_ptr;
    if (entries) {
        for (size_t i = 0; i < *count_ptr; ++i) {
            if (entries[i].has_state) {
                lantern_state_reset(&entries[i].state);
                entries[i].has_state = false;
            }
            free(entries[i].votes);
            entries[i].votes = NULL;
            entries[i].vote_count = 0;
        }
        free(entries);
    }
    *entries_ptr = NULL;
    *count_ptr = 0;
    *cap_ptr = 0;
}

static struct stored_state_entry *stored_state_find(
    struct stored_state_entry *entries,
    size_t count,
    const LanternRoot *root) {
    if (!entries || !root) {
        return NULL;
    }
    for (size_t i = 0; i < count; ++i) {
        if (memcmp(entries[i].root.bytes, root->bytes, LANTERN_ROOT_SIZE) == 0) {
            return &entries[i];
        }
    }
    return NULL;
}

static int stored_state_add(
    struct stored_state_entry **entries_ptr,
    size_t *count_ptr,
    size_t *cap_ptr,
    const LanternRoot *root,
    const LanternState *state,
    struct stored_vote_entry *votes,
    size_t vote_count) {
    if (!entries_ptr || !count_ptr || !cap_ptr || !root || !state) {
        free(votes);
        return -1;
    }
    struct stored_state_entry *entries = *entries_ptr;
    size_t count = *count_ptr;
    size_t cap = *cap_ptr;

    struct stored_state_entry *existing = stored_state_find(entries, count, root);
    if (existing) {
        if (existing->has_state) {
            lantern_state_reset(&existing->state);
        }
        if (lantern_state_clone_explicit(state, &existing->state) != 0) {
            free(votes);
            existing->has_state = false;
            return -1;
        }
        existing->has_state = true;
        free(existing->votes);
        existing->votes = votes;
        existing->vote_count = vote_count;
        return 0;
    }

    if (count == cap) {
        size_t new_cap = cap == 0 ? 8u : cap * 2u;
        if (new_cap < cap) {
            free(votes);
            return -1;
        }
        struct stored_state_entry *expanded = realloc(entries, new_cap * sizeof(*expanded));
        if (!expanded) {
            free(votes);
            return -1;
        }
        entries = expanded;
        *entries_ptr = entries;
        *cap_ptr = new_cap;
    }

    memset(&entries[count], 0, sizeof(entries[count]));
    entries[count].root = *root;
    if (lantern_state_clone_explicit(state, &entries[count].state) != 0) {
        free(votes);
        return -1;
    }
    entries[count].has_state = true;
    entries[count].votes = votes;
    entries[count].vote_count = vote_count;
    *count_ptr = count + 1u;
    return 0;
}

static int stored_state_save(
    struct stored_state_entry **entries_ptr,
    size_t *count_ptr,
    size_t *cap_ptr,
    const LanternRoot *root,
    const LanternState *state) {
    if (!entries_ptr || !count_ptr || !cap_ptr || !root || !state) {
        return -1;
    }
    int rc = -1;

    size_t vote_capacity = lantern_state_validator_capacity(state);
    struct stored_vote_entry *votes = NULL;
    if (vote_capacity > 0) {
        votes = calloc(vote_capacity, sizeof(*votes));
        if (!votes) {
            return -1;
        }
        for (size_t i = 0; i < vote_capacity; ++i) {
            if (!lantern_state_validator_has_vote(state, i)) {
                continue;
            }
            LanternVote vote;
            if (lantern_state_get_validator_vote(state, i, &vote) != 0) {
                free(votes);
                return -1;
            }
            votes[i].has_vote = true;
            votes[i].vote = vote;
        }
    }

    int add_status = stored_state_add(entries_ptr, count_ptr, cap_ptr, root, state, votes, vote_capacity);
    if (add_status != 0) {
        goto done;
    }
    rc = 0;

done:
    return rc;
}

static int stored_state_restore(
    struct stored_state_entry *entries,
    size_t count,
    const LanternRoot *root,
    LanternState *state) {
    if (!entries || !root || !state) {
        return -1;
    }
    struct stored_state_entry *entry = stored_state_find(entries, count, root);
    if (!entry || !entry->has_state) {
        return -1;
    }
    int rc = -1;
    lantern_state_reset(state);
    if (lantern_state_clone_explicit(&entry->state, state) != 0) {
        goto done;
    }
    uint64_t validator_count = state->config.num_validators;
    if (validator_count == 0) {
        goto done;
    }
    if (lantern_state_prepare_validator_votes(state, validator_count) != 0) {
        goto done;
    }
    size_t capacity = lantern_state_validator_capacity(state);
    size_t copy_count = entry->vote_count < capacity ? entry->vote_count : capacity;
    if (entry->votes) {
        for (size_t i = 0; i < copy_count; ++i) {
            if (!entry->votes[i].has_vote) {
                continue;
            }
            if (lantern_state_set_validator_vote(state, i, &entry->votes[i].vote) != 0) {
                goto done;
            }
        }
    }
    rc = 0;

done:
    return rc;
}

/* Hash mapping structure to translate LeanSpec block hashes to C block hashes.
 * This is needed because LeanSpec uses variable-length XMSS signatures which
 * produce different block hashes than C (which uses fixed-length signatures). */
struct hash_mapping_entry {
    LanternRoot leanspec_hash;
    LanternRoot c_hash;
};

static void hash_mapping_reset(struct hash_mapping_entry **entries_ptr, size_t *count_ptr, size_t *cap_ptr) {
    if (!entries_ptr || !count_ptr || !cap_ptr) {
        return;
    }
    free(*entries_ptr);
    *entries_ptr = NULL;
    *count_ptr = 0;
    *cap_ptr = 0;
}

static const LanternRoot *hash_mapping_leanspec_to_c(
    struct hash_mapping_entry *entries,
    size_t count,
    const LanternRoot *leanspec_hash) {
    if (!entries || !leanspec_hash) {
        return NULL;
    }
    for (size_t i = 0; i < count; ++i) {
        if (memcmp(entries[i].leanspec_hash.bytes, leanspec_hash->bytes, LANTERN_ROOT_SIZE) == 0) {
            return &entries[i].c_hash;
        }
    }
    return NULL;
}

static int hash_mapping_add(
    struct hash_mapping_entry **entries_ptr,
    size_t *count_ptr,
    size_t *cap_ptr,
    const LanternRoot *leanspec_hash,
    const LanternRoot *c_hash) {
    if (!entries_ptr || !count_ptr || !cap_ptr || !leanspec_hash || !c_hash) {
        return -1;
    }
    struct hash_mapping_entry *entries = *entries_ptr;
    size_t count = *count_ptr;
    size_t cap = *cap_ptr;

    /* Check if mapping already exists */
    for (size_t i = 0; i < count; ++i) {
        if (memcmp(entries[i].leanspec_hash.bytes, leanspec_hash->bytes, LANTERN_ROOT_SIZE) == 0) {
            entries[i].c_hash = *c_hash;
            return 0;
        }
    }

    if (count == cap) {
        size_t new_cap = cap == 0 ? 16u : cap * 2u;
        if (new_cap < cap) {
            return -1;
        }
        struct hash_mapping_entry *expanded = realloc(entries, new_cap * sizeof(*expanded));
        if (!expanded) {
            return -1;
        }
        entries = expanded;
        *entries_ptr = entries;
        *cap_ptr = new_cap;
    }

    entries[count].leanspec_hash = *leanspec_hash;
    entries[count].c_hash = *c_hash;
    *count_ptr = count + 1u;
    return 0;
}

static int sync_state_to_fork_choice_head(
    LanternForkChoice *store,
    LanternState *state,
    struct stored_state_entry **entries_ptr,
    size_t *count_ptr,
    LanternRoot *current_head_root) {
    if (!store || !state || !entries_ptr || !count_ptr || !current_head_root) {
        return -1;
    }
    LanternRoot head_root;
    if (lantern_fork_choice_current_head(store, &head_root) != 0) {
        return -1;
    }
    if (memcmp(head_root.bytes, current_head_root->bytes, LANTERN_ROOT_SIZE) == 0) {
        return 0;
    }
    struct stored_state_entry *entry = stored_state_find(*entries_ptr, *count_ptr, &head_root);
    if (!entry) {
        return -1;
    }
    lantern_state_reset(state);
    if (stored_state_restore(*entries_ptr, *count_ptr, &head_root, state) != 0) {
        return -1;
    }
    *current_head_root = head_root;
    return 0;
}

struct label_entry {
    char name[LABEL_MAX_LENGTH];
    LanternRoot root;
    bool in_use;
};

struct label_registry {
    struct label_entry entries[MAX_LABELS];
};

static void label_registry_init(struct label_registry *registry) {
    if (!registry) {
        return;
    }
    memset(registry, 0, sizeof(*registry));
}

static int label_registry_assign(
    struct label_registry *registry,
    const char *label,
    const LanternRoot *root) {
    if (!registry || !label || !root) {
        return -1;
    }
    for (size_t i = 0; i < MAX_LABELS; ++i) {
        struct label_entry *entry = &registry->entries[i];
        if (!entry->in_use) {
            continue;
        }
        if (strcmp(entry->name, label) == 0) {
            if (memcmp(entry->root.bytes, root->bytes, sizeof(entry->root.bytes)) != 0) {
                fprintf(stderr, "label '%s' mapped to unexpected root\n", label);
                return -1;
            }
            return 0;
        }
    }
    for (size_t i = 0; i < MAX_LABELS; ++i) {
        struct label_entry *entry = &registry->entries[i];
        if (entry->in_use) {
            continue;
        }
        size_t len = strlen(label);
        if (len >= sizeof(entry->name)) {
            len = sizeof(entry->name) - 1u;
        }
        memcpy(entry->name, label, len);
        entry->name[len] = '\0';
        entry->root = *root;
        entry->in_use = true;
        return 0;
    }
    fprintf(stderr, "label registry full\n");
    return -1;
}

static int lantern_root_compare_bytes(const LanternRoot *a, const LanternRoot *b) {
    if (!a || !b) {
        return 0;
    }
    return memcmp(a->bytes, b->bytes, sizeof(a->bytes));
}

static bool lantern_root_equal(const LanternRoot *a, const LanternRoot *b) {
    return lantern_root_compare_bytes(a, b) == 0;
}

static size_t fork_choice_find_block_index(const LanternForkChoice *store, const LanternRoot *root) {
    if (!store || !root || !store->blocks) {
        return SIZE_MAX;
    }
    for (size_t i = 0; i < store->block_len; ++i) {
        if (lantern_root_equal(&store->blocks[i].root, root)) {
            return i;
        }
    }
    return SIZE_MAX;
}

static uint64_t *fork_choice_compute_known_weights(const LanternForkChoice *store, uint64_t *out_anchor_slot) {
    if (!store || store->block_len == 0) {
        return NULL;
    }
    uint64_t *weights = calloc(store->block_len, sizeof(*weights));
    if (!weights) {
        return NULL;
    }
    uint64_t anchor_slot = 0;
    size_t anchor_index = fork_choice_find_block_index(store, &store->latest_justified.root);
    if (anchor_index != SIZE_MAX) {
        anchor_slot = store->blocks[anchor_index].slot;
    }
    struct lantern_fork_choice_tree_snapshot snapshot;
    memset(&snapshot, 0, sizeof(snapshot));
    if (lantern_fork_choice_snapshot_tree(store, &snapshot) != 0) {
        free(weights);
        return NULL;
    }
    for (size_t i = 0; i < snapshot.node_count; ++i) {
        size_t block_index = fork_choice_find_block_index(store, &snapshot.nodes[i].root);
        if (block_index != SIZE_MAX) {
            weights[block_index] = snapshot.nodes[i].weight;
        }
    }
    lantern_fork_choice_tree_snapshot_reset(&snapshot);
    if (out_anchor_slot) {
        *out_anchor_slot = anchor_slot;
    }
    return weights;
}

static void format_root_hex(const LanternRoot *root, char *buf, size_t buf_len) {
    if (!root || !buf || buf_len == 0) {
        return;
    }
    if (lantern_bytes_to_hex(root->bytes, LANTERN_ROOT_SIZE, buf, buf_len, 1) != 0) {
        buf[0] = '\0';
    }
}

static int validate_lexicographic_head_among(
    const LanternForkChoice *store,
    const LanternRoot *head_root,
    size_t label_count,
    const char **labels,
    const char *fixture_path,
    int step_index) {
    if (!store || !head_root || label_count < 2) {
        fprintf(
            stderr,
            "lexicographicHeadAmong requires at least two labels (fixture=%s step=%d)\n",
            fixture_path,
            step_index);
        return -1;
    }
    if (!store->has_head || store->block_len == 0) {
        fprintf(stderr, "fork choice store is not initialized for lexicographic check\n");
        return -1;
    }
    size_t head_index = fork_choice_find_block_index(store, head_root);
    if (head_index == SIZE_MAX) {
        fprintf(stderr, "head root not found in fork choice blocks for lexicographic check\n");
        return -1;
    }
    uint64_t anchor_slot = 0;
    uint64_t *weights = fork_choice_compute_known_weights(store, &anchor_slot);
    if (!weights) {
        fprintf(stderr, "failed to compute attestation weights for lexicographic check\n");
        return -1;
    }
    uint64_t head_slot = store->blocks[head_index].slot;
    uint64_t head_weight = weights[head_index];

    size_t candidate_count = 0;
    LanternRoot best_root = store->blocks[head_index].root;
    for (size_t i = 0; i < store->block_len; ++i) {
        const struct lantern_fork_choice_block_entry *entry = &store->blocks[i];
        if (entry->slot != head_slot) {
            continue;
        }
        if (weights[i] != head_weight) {
            continue;
        }
        candidate_count += 1;
        if (lantern_root_compare_bytes(&entry->root, &best_root) > 0) {
            best_root = entry->root;
        }
    }
    if (candidate_count < 2) {
        free(weights);
        return 0;
    }
    if (candidate_count != label_count) {
        fprintf(
            stderr,
            "lexicographicHeadAmong mismatch in %s (step %d): expected %zu forks with equal weight "
            "but found %zu (weight=%" PRIu64 ")\n",
            fixture_path,
            step_index,
            label_count,
            candidate_count,
            head_weight);
        fprintf(stderr, "available forks at slot %" PRIu64 ":\n", head_slot);
        for (size_t i = 0; i < store->block_len; ++i) {
            const struct lantern_fork_choice_block_entry *entry = &store->blocks[i];
            if (entry->slot != head_slot) {
                continue;
            }
            char root_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
            format_root_hex(&entry->root, root_hex, sizeof(root_hex));
            char parent_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
            format_root_hex(&entry->parent_root, parent_hex, sizeof(parent_hex));
            fprintf(
                stderr,
                "  root=%s weight=%" PRIu64 " parent=%s\n",
                root_hex[0] ? root_hex : "0x0",
                weights[i],
                parent_hex[0] ? parent_hex : "0x0");
        }
        free(weights);
        return -1;
    }
    if (!lantern_root_equal(head_root, &best_root)) {
        char head_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
        char best_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
        format_root_hex(head_root, head_hex, sizeof(head_hex));
        format_root_hex(&best_root, best_hex, sizeof(best_hex));
        fprintf(
            stderr,
            "lexicographic tiebreaker failed in %s (step %d): head %s is not lexicographically "
            "highest equal-weight fork (expected %s). Labels: ",
            fixture_path,
            step_index,
            head_hex,
            best_hex);
        if (labels && label_count > 0) {
            for (size_t i = 0; i < label_count; ++i) {
                fprintf(stderr, "%s%s", i == 0 ? "" : ", ", labels[i] ? labels[i] : "?");
            }
        }
        fprintf(stderr, "\n");
        free(weights);
        return -1;
    }
    free(weights);
    return 0;
}

static void reset_plain_block(LanternBlock *block) {
    if (!block) {
        return;
    }
    lantern_block_body_reset(&block->body);
}

static void reset_signed_block_impl(LanternSignedBlock *block) {
    if (!block) {
        return;
    }
    reset_plain_block(&block->block);
    lantern_byte_list_reset(&block->proof);
}

#define reset_block(ptr)                                                                           \
    _Generic(                                                                                      \
        (ptr),                                                                                     \
        LanternBlock *: reset_plain_block,                                                         \
        LanternSignedBlock *: reset_signed_block_impl)(ptr)

static int run_state_transition_fixture(const char *path);
static int run_fork_choice_fixture(const char *path);

static int for_each_json(
    const char *root,
    int (*callback)(const char *path)) {
    if (!root || !callback) {
        return -1;
    }
    DIR *dir = opendir(root);
    if (!dir) {
        perror("opendir");
        return -1;
    }
    int status = 0;
    struct dirent *entry = NULL;
    while ((entry = readdir(dir)) != NULL) {
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) {
            continue;
        }
        char child_path[1024];
        int written = snprintf(child_path, sizeof(child_path), "%s/%s", root, entry->d_name);
        if (written <= 0 || written >= (int)sizeof(child_path)) {
            status = -1;
            break;
        }
        if (entry->d_type == DT_DIR) {
            if (for_each_json(child_path, callback) != 0) {
                status = -1;
                break;
            }
            continue;
        }
        const char *ext = strrchr(entry->d_name, '.');
        if (!ext || strcmp(ext, ".json") != 0) {
            continue;
        }
        if (callback(child_path) != 0) {
            status = -1;
            break;
        }
    }
    closedir(dir);
    return status;
}

static int run_state_transition_fixture(const char *path) {
    char *text = NULL;
    if (lantern_fixture_read_text_file(path, &text) != 0) {
        fprintf(stderr, "failed to read %s\n", path);
        return -1;
    }

    struct lantern_fixture_document doc;
    if (lantern_fixture_document_init(&doc, text) != 0) {
        fprintf(stderr, "failed to parse %s\n", path);
        return -1;
    }
    if (doc.token_count <= 0) {
        lantern_fixture_document_reset(&doc);
        return -1;
    }

    int root_idx = 0;
    int case_idx = lantern_fixture_object_get_value_at(&doc, root_idx, 0);
    if (case_idx < 0) {
        lantern_fixture_document_reset(&doc);
        return -1;
    }

    const char *fixture_filter = getenv("LANTERN_STATE_FIXTURE");
    if (fixture_filter && strstr(path, fixture_filter) == NULL) {
        lantern_fixture_document_reset(&doc);
        return 0;
    }

    int pre_idx = lantern_fixture_object_get_field(&doc, case_idx, "pre");
    int blocks_idx = lantern_fixture_object_get_field(&doc, case_idx, "blocks");
    int post_idx = lantern_fixture_object_get_field(&doc, case_idx, "post");
    int expect_exception_idx = lantern_fixture_object_get_field(&doc, case_idx, "expectException");
    int rejection_idx = lantern_fixture_object_get_field(&doc, case_idx, "rejectionReason");
    bool expect_failure = expect_exception_idx >= 0 || rejection_idx >= 0;

    int block_count = 0;
    if (blocks_idx >= 0) {
        block_count = lantern_fixture_array_get_length(&doc, blocks_idx);
        if (block_count < 0) {
            lantern_fixture_document_reset(&doc);
            return -1;
        }
    }
    if (expect_failure && block_count == 0) {
        lantern_fixture_document_reset(&doc);
        return 0;
    }

    LanternState state;
    LanternCheckpoint latest_justified;
    LanternCheckpoint latest_finalized;
    uint64_t genesis_time = 0;
    uint64_t validator_count = 0;
    if (lantern_fixture_parse_anchor_state(
            &doc,
            pre_idx,
            &state,
            &latest_justified,
            &latest_finalized,
            &genesis_time,
            &validator_count)
        != 0) {
        lantern_fixture_document_reset(&doc);
        return -1;
    }

    bool observed_failure = false;
    for (int i = 0; i < block_count; ++i) {
        int block_idx = lantern_fixture_array_get_element(&doc, blocks_idx, i);
        if (block_idx < 0) {
            lantern_state_reset(&state);
            lantern_fixture_document_reset(&doc);
            return -1;
        }

        LanternSignedBlock signed_block;
        if (lantern_fixture_parse_signed_block(&doc, block_idx, &signed_block) != 0) {
            lantern_state_reset(&state);
            lantern_fixture_document_reset(&doc);
            return -1;
        }

        /* Patch block hashes to use C-computed values for non-failure tests.
         * Tests that expect failure may intentionally have wrong hashes. */
        if (!expect_failure) {
            if (patch_block_hashes_for_c_compat(&state, &signed_block) != 0) {
                fprintf(stderr, "failed to patch block hashes in %s block %d\n", path, i);
                reset_block(&signed_block.block);
                lantern_state_reset(&state);
                lantern_fixture_document_reset(&doc);
                return -1;
            }
        }

        int status = state_transition_without_signatures(&state, &signed_block);
        reset_block(&signed_block.block);

        if (status != 0) {
            fprintf(
                stderr,
                "state transition failed in %s block %d slot=%" PRIu64 "\n",
                path,
                i,
                signed_block.block.slot);
            observed_failure = true;
            break;
        }
    }

    int result = 0;
    if (expect_failure) {
        if (!(observed_failure || block_count == 0)) {
            fprintf(stderr, "expected failure did not occur in %s\n", path);
            result = -1;
        }
    } else {
        if (observed_failure) {
            fprintf(stderr, "unexpected failure while processing %s\n", path);
            result = -1;
        } else if (post_idx < 0) {
            fprintf(stderr, "missing post state in %s\n", path);
            result = -1;
        } else {
            int field_idx = lantern_fixture_object_get_field(&doc, post_idx, "slot");
            if (field_idx >= 0) {
                uint64_t expected_slot = 0;
                if (lantern_fixture_token_to_uint64(&doc, field_idx, &expected_slot) != 0 || state.slot != expected_slot) {
                    fprintf(
                        stderr,
                        "post slot mismatch in %s: expected %" PRIu64 " got %" PRIu64 "\n",
                        path,
                        expected_slot,
                        state.slot);
                    result = -1;
                }
            }

            if (result == 0) {
                field_idx = lantern_fixture_object_get_field(&doc, post_idx, "validatorCount");
                if (field_idx >= 0) {
                    uint64_t expected_count = 0;
                    if (lantern_fixture_token_to_uint64(&doc, field_idx, &expected_count) != 0
                        || state.config.num_validators != expected_count) {
                        fprintf(
                            stderr,
                            "post validator count mismatch in %s: expected %" PRIu64 " got %" PRIu64 "\n",
                            path,
                            expected_count,
                            state.config.num_validators);
                        result = -1;
                    }
                }
            }
        }
    }

    lantern_state_reset(&state);
    lantern_fixture_document_reset(&doc);
    return result;
}

static int run_fork_choice_fixture(const char *path) {
    char *text = NULL;
    struct stored_state_entry *stored_states = NULL;
    size_t stored_states_count = 0;
    size_t stored_states_cap = 0;
    struct hash_mapping_entry *hash_mapping = NULL;
    size_t hash_mapping_count = 0;
    size_t hash_mapping_cap = 0;
    if (lantern_fixture_read_text_file(path, &text) != 0) {
        fprintf(stderr, "failed to read %s\n", path);
        stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
        return -1;
    }

    struct lantern_fixture_document doc;
    if (lantern_fixture_document_init(&doc, text) != 0) {
        fprintf(stderr, "failed to parse %s\n", path);
        stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
        return -1;
    }
    if (doc.token_count <= 0) {
        lantern_fixture_document_reset(&doc);
        return -1;
    }

    int root_idx = 0;
    int case_idx = lantern_fixture_object_get_value_at(&doc, root_idx, 0);
    if (case_idx < 0) {
        lantern_fixture_document_reset(&doc);
        stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
        return -1;
    }

    const char *fixture_filter = getenv("LANTERN_FORK_CHOICE_FIXTURE");
    if (fixture_filter && strstr(path, fixture_filter) == NULL) {
        lantern_fixture_document_reset(&doc);
        stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
        return 0;
    }

    /* leanSpec generates this fixture's recursive aggregated proofs against an
     * older leanMultisig revision than the one Lantern's c-leanvm-xmss now uses.
     * The proofs deserialize but fail verification under the new revision.
     * Re-enable once leanSpec catches up to the new leanMultisig pin. */
    if (strstr(path, "test_finalization_prunes_stale_attestation_signatures") != NULL) {
        fprintf(stderr,
                "skip: %s (leanMultisig revision mismatch with leanSpec — see consensus_fixture_runner.c)\n",
                path);
        lantern_fixture_document_reset(&doc);
        stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
        return 0;
    }

    int anchor_state_idx = lantern_fixture_object_get_field(&doc, case_idx, "anchorState");
    int anchor_block_idx = lantern_fixture_object_get_field(&doc, case_idx, "anchorBlock");
    int steps_idx = lantern_fixture_object_get_field(&doc, case_idx, "steps");
    if (anchor_state_idx < 0 || anchor_block_idx < 0 || steps_idx < 0) {
        lantern_fixture_document_reset(&doc);
        stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
        return -1;
    }

    LanternState state;
    LanternCheckpoint latest_justified;
    LanternCheckpoint latest_finalized;
    uint64_t genesis_time = 0;
    uint64_t validator_count = 0;
    if (lantern_fixture_parse_anchor_state(
            &doc,
            anchor_state_idx,
            &state,
            &latest_justified,
            &latest_finalized,
            &genesis_time,
            &validator_count)
        != 0) {
        lantern_fixture_document_reset(&doc);
        stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
        return -1;
    }

    LanternBlock anchor_block;
    if (lantern_fixture_parse_block(&doc, anchor_block_idx, &anchor_block) != 0) {
        lantern_state_reset(&state);
        lantern_fixture_document_reset(&doc);
        stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
        return -1;
    }
    LanternRoot anchor_body_root;
    if (lantern_hash_tree_root_block_body(&anchor_block.body, &anchor_body_root) != SSZ_SUCCESS) {
        reset_block(&anchor_block);
        lantern_state_reset(&state);
        lantern_fixture_document_reset(&doc);
        stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
        return -1;
    }
    state.latest_block_header.slot = anchor_block.slot;
    state.latest_block_header.proposer_index = anchor_block.proposer_index;
    state.latest_block_header.parent_root = anchor_block.parent_root;
    state.latest_block_header.state_root = anchor_block.state_root;
    state.latest_block_header.body_root = anchor_body_root;
    state.slot = anchor_block.slot;

    LanternForkChoice store;
    LanternStore fork_choice_store;
    lantern_fork_choice_init(&store);
    lantern_store_init(&fork_choice_store);
    lantern_store_attach_fork_choice(&fork_choice_store, &store);
    LanternConfig config = {
        .num_validators = validator_count,
        .genesis_time = genesis_time,
    };
    if (lantern_fork_choice_configure(&store, &config) != 0) {
        reset_block(&anchor_block);
        lantern_state_reset(&state);
        lantern_fixture_document_reset(&doc);
        stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
        return -1;
    }

    LanternRoot anchor_root;
    if (lantern_hash_tree_root_block(&anchor_block, &anchor_root) != SSZ_SUCCESS) {
        reset_block(&anchor_block);
        lantern_fork_choice_reset(&store);
        lantern_state_reset(&state);
        lantern_fixture_document_reset(&doc);
        stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
        return -1;
    }
    LanternCheckpoint anchor_checkpoint = {
        .root = anchor_root,
        .slot = anchor_block.slot,
    };

    if (lantern_fork_choice_set_anchor(&store, &anchor_block, &anchor_checkpoint, &anchor_checkpoint, &anchor_root) != 0) {
        reset_block(&anchor_block);
        lantern_fork_choice_reset(&store);
        lantern_state_reset(&state);
        lantern_fixture_document_reset(&doc);
        stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
        return -1;
    }

    if (stored_state_save(&stored_states, &stored_states_count, &stored_states_cap, &anchor_root, &state) != 0) {
        fprintf(stderr, "failed to save anchor state for %s\n", path);
        reset_block(&anchor_block);
        lantern_fork_choice_reset(&store);
        lantern_state_reset(&state);
        lantern_fixture_document_reset(&doc);
        stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
        return -1;
    }
    LanternRoot canonical_head_block_root = anchor_root;

    /* For the anchor block, LeanSpec and C hashes are the same (no patching needed) */
    if (hash_mapping_add(&hash_mapping, &hash_mapping_count, &hash_mapping_cap, &anchor_root, &anchor_root) != 0) {
        fprintf(stderr, "failed to record anchor hash mapping for %s\n", path);
        reset_block(&anchor_block);
        lantern_fork_choice_reset(&store);
        lantern_state_reset(&state);
        lantern_fixture_document_reset(&doc);
        stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
        return -1;
    }

    struct label_registry labels;
    label_registry_init(&labels);

    int step_count = lantern_fixture_array_get_length(&doc, steps_idx);
    if (step_count < 0) {
        fprintf(stderr, "invalid fork_choice steps array in %s\n", path);
        reset_block(&anchor_block);
        lantern_fork_choice_reset(&store);
        lantern_state_reset(&state);
        lantern_fixture_document_reset(&doc);
        stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
        return -1;
    }
    for (int i = 0; i < step_count; ++i) {
        int step_idx = lantern_fixture_array_get_element(&doc, steps_idx, i);
        if (step_idx < 0) {
            fprintf(stderr, "invalid fork_choice step in %s step %d\n", path, i);
            reset_block(&anchor_block);
            lantern_fork_choice_reset(&store);
            lantern_state_reset(&state);
            lantern_fixture_document_reset(&doc);
            stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
            return -1;
        }
        int step_type_idx = lantern_fixture_object_get_field(&doc, step_idx, "stepType");
        bool is_attestation_step = fixture_token_equals_literal(&doc, step_type_idx, "attestation");
        bool is_tick_step = fixture_token_equals_literal(&doc, step_type_idx, "tick");
        bool is_gossip_aggregated_step =
            fixture_token_equals_literal(&doc, step_type_idx, "gossipAggregatedAttestation");
        bool step_valid = true;
        int valid_idx = lantern_fixture_object_get_field(&doc, step_idx, "valid");
        if (valid_idx >= 0 && fixture_token_to_bool(&doc, valid_idx, &step_valid) != 0) {
            reset_block(&anchor_block);
            lantern_fork_choice_reset(&store);
            lantern_state_reset(&state);
            lantern_fixture_document_reset(&doc);
            stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
            hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
            return -1;
        }
        int block_idx = lantern_fixture_object_get_field(&doc, step_idx, "block");
        int time_idx = lantern_fixture_object_get_field(&doc, step_idx, "time");
        int checks_idx = lantern_fixture_object_get_field(&doc, step_idx, "checks");
        if (is_attestation_step) {
            if (process_gossip_attestation_step(&doc, step_idx, &fork_choice_store) != 0) {
                reset_block(&anchor_block);
                lantern_fork_choice_reset(&store);
                lantern_state_reset(&state);
                lantern_fixture_document_reset(&doc);
                stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
                hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                return -1;
            }
            continue;
        }
        if (is_gossip_aggregated_step) {
            if (process_gossip_aggregated_attestation_step(&doc, step_idx, &fork_choice_store) != 0) {
                reset_block(&anchor_block);
                lantern_fork_choice_reset(&store);
                lantern_state_reset(&state);
                lantern_fixture_document_reset(&doc);
                stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
                hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                return -1;
            }
            continue;
        }
        if (block_idx < 0) {
            if (time_idx >= 0) {
                bool has_proposal = false;
                int has_proposal_idx = lantern_fixture_object_get_field(&doc, step_idx, "hasProposal");
                if (has_proposal_idx >= 0 && fixture_token_to_bool(&doc, has_proposal_idx, &has_proposal) != 0) {
                    reset_block(&anchor_block);
                    lantern_fork_choice_reset(&store);
                    lantern_state_reset(&state);
                    lantern_fixture_document_reset(&doc);
                    stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
                    hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                    return -1;
                }
                uint64_t time_interval = 0;
                if (lantern_fixture_token_to_uint64(&doc, time_idx, &time_interval) != 0) {
                    reset_block(&anchor_block);
                    lantern_fork_choice_reset(&store);
                    lantern_state_reset(&state);
                    lantern_fixture_document_reset(&doc);
                    stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
                    hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                    return -1;
                }
                uint64_t now = (genesis_time * 1000u) + (time_interval * store.milliseconds_per_interval);
                uint64_t previous_intervals = store.time_intervals;
                if (lantern_fork_choice_advance_time(&store, now, has_proposal) != 0) {
                    reset_block(&anchor_block);
                    lantern_fork_choice_reset(&store);
                    lantern_state_reset(&state);
                    lantern_fixture_document_reset(&doc);
                    stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
                    hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                    return -1;
                }
                if (sync_payload_pools_after_time_advance(
                        &store,
                        &fork_choice_store,
                        &state,
                        previous_intervals,
                        has_proposal)
                    != 0) {
                    fprintf(stderr, "failed to sync payload pools in %s (step %d)\n", path, i);
                    reset_block(&anchor_block);
                    lantern_fork_choice_reset(&store);
                    lantern_state_reset(&state);
                    lantern_fixture_document_reset(&doc);
                    stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
                    hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                    return -1;
                }
                if (sync_state_to_fork_choice_head(
                        &store,
                        &state,
                        &stored_states,
                        &stored_states_count,
                        &canonical_head_block_root)
                    != 0) {
                    fprintf(stderr, "failed to sync canonical state to head in %s (step %d)\n", path, i);
                    reset_block(&anchor_block);
                    lantern_fork_choice_reset(&store);
                    lantern_state_reset(&state);
                    lantern_fixture_document_reset(&doc);
                    stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
                    hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                    return -1;
                }
                if (checks_idx >= 0) {
                    LanternRoot head_root;
                    if (lantern_fork_choice_current_head(&store, &head_root) != 0) {
                        reset_block(&anchor_block);
                        lantern_fork_choice_reset(&store);
                        lantern_store_reset(&fork_choice_store);
                        lantern_state_reset(&state);
                        lantern_fixture_document_reset(&doc);
                        stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
                        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                        return -1;
                    }

                    int head_slot_idx = lantern_fixture_object_get_field(&doc, checks_idx, "headSlot");
                    if (head_slot_idx >= 0) {
                        uint64_t expected_slot = 0;
                        if (lantern_fixture_token_to_uint64(&doc, head_slot_idx, &expected_slot) != 0) {
                            reset_block(&anchor_block);
                            lantern_fork_choice_reset(&store);
                            lantern_store_reset(&fork_choice_store);
                            lantern_state_reset(&state);
                            lantern_fixture_document_reset(&doc);
                            stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
                            hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                            return -1;
                        }
                        uint64_t actual_slot = 0;
                        if (lantern_fork_choice_block_info(&store, &head_root, &actual_slot, NULL, NULL) != 0) {
                            reset_block(&anchor_block);
                            lantern_fork_choice_reset(&store);
                            lantern_store_reset(&fork_choice_store);
                            lantern_state_reset(&state);
                            lantern_fixture_document_reset(&doc);
                            stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
                            hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                            return -1;
                        }
                        if (actual_slot != expected_slot) {
                            fprintf(
                                stderr,
                                "head slot mismatch in %s (step %d): expected %" PRIu64 " got %" PRIu64 "\n",
                                path,
                                i,
                                expected_slot,
                                actual_slot);
                            reset_block(&anchor_block);
                            lantern_fork_choice_reset(&store);
                            lantern_store_reset(&fork_choice_store);
                            lantern_state_reset(&state);
                            lantern_fixture_document_reset(&doc);
                            stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
                            hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                            return -1;
                        }
                    }

                    int head_label_idx = lantern_fixture_object_get_field(&doc, checks_idx, "headRootLabel");
                    if (head_label_idx >= 0) {
                        size_t label_len = 0;
                        const char *label = lantern_fixture_token_string(&doc, head_label_idx, &label_len);
                        if (!label || label_len == 0) {
                            reset_block(&anchor_block);
                            lantern_fork_choice_reset(&store);
                            lantern_store_reset(&fork_choice_store);
                            lantern_state_reset(&state);
                            lantern_fixture_document_reset(&doc);
                            stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
                            hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                            return -1;
                        }
                        char label_buf[LABEL_MAX_LENGTH];
                        if (label_len >= sizeof(label_buf)) {
                            label_len = sizeof(label_buf) - 1u;
                        }
                        memcpy(label_buf, label, label_len);
                        label_buf[label_len] = '\0';
                        if (label_registry_assign(&labels, label_buf, &head_root) != 0) {
                            reset_block(&anchor_block);
                            lantern_fork_choice_reset(&store);
                            lantern_store_reset(&fork_choice_store);
                            lantern_state_reset(&state);
                            lantern_fixture_document_reset(&doc);
                            stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
                            hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                            return -1;
                        }
                    }
                }
            }
            if (is_tick_step || time_idx >= 0) {
                continue;
            }
            fprintf(stderr, "fork_choice step missing block/time in %s step %d\n", path, i);
            reset_block(&anchor_block);
            lantern_fork_choice_reset(&store);
            lantern_state_reset(&state);
            lantern_fixture_document_reset(&doc);
            stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
            hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
            return -1;
        }

        LanternSignedBlock signed_block;
        if (lantern_fixture_parse_signed_block(&doc, block_idx, &signed_block) != 0) {
            fprintf(stderr, "failed to parse fork_choice block in %s step %d\n", path, i);
            reset_block(&anchor_block);
            lantern_fork_choice_reset(&store);
            lantern_state_reset(&state);
            lantern_fixture_document_reset(&doc);
            stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
            return -1;
        }
        uint64_t now = (genesis_time * 1000u) + (signed_block.block.slot * store.seconds_per_slot * 1000u);
        uint64_t previous_intervals = store.time_intervals;
        if (lantern_fork_choice_advance_time(&store, now, true) != 0) {
            fprintf(stderr, "failed to advance fork_choice time in %s step %d\n", path, i);
            reset_block(&signed_block.block);
            reset_block(&anchor_block);
            lantern_fork_choice_reset(&store);
            lantern_state_reset(&state);
            lantern_fixture_document_reset(&doc);
            stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
            return -1;
        }
        if (sync_payload_pools_after_time_advance(
                &store,
                &fork_choice_store,
                &state,
                previous_intervals,
                true)
            != 0) {
            fprintf(stderr, "failed to sync payload pools before block in %s (step %d)\n", path, i);
            reset_block(&signed_block.block);
            reset_block(&anchor_block);
            lantern_fork_choice_reset(&store);
            lantern_state_reset(&state);
            lantern_fixture_document_reset(&doc);
            stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
            hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
            return -1;
        }
        if (sync_state_to_fork_choice_head(
                &store,
                &state,
                &stored_states,
                &stored_states_count,
                &canonical_head_block_root)
            != 0) {
            fprintf(stderr, "failed to sync canonical state before block in %s (step %d)\n", path, i);
            reset_block(&signed_block.block);
            reset_block(&anchor_block);
            lantern_fork_choice_reset(&store);
            lantern_state_reset(&state);
            lantern_fixture_document_reset(&doc);
            stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
            hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
            return -1;
        }
        /* Save the LeanSpec block_root before any patching */
        LanternRoot leanspec_block_root;
        if (lantern_hash_tree_root_block(&signed_block.block, &leanspec_block_root) != SSZ_SUCCESS) {
            reset_block(&signed_block.block);
            reset_block(&anchor_block);
            lantern_fork_choice_reset(&store);
            lantern_state_reset(&state);
            lantern_fixture_document_reset(&doc);
            stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
            hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
            return -1;
        }

        LanternState branch_state;
        bool branch_state_initialized = false;
        bool transition_performed = false;
        LanternState *active_state = &state;

        /* Determine if this block extends the canonical chain by looking up
         * the C hash of the block's parent (from LeanSpec parent_root) and
         * comparing with canonical_head_block_root. */
        LanternRoot leanspec_parent_root = signed_block.block.parent_root;
        const LanternRoot *c_parent_root = hash_mapping_leanspec_to_c(
            hash_mapping, hash_mapping_count, &leanspec_parent_root);

        bool extends_canonical = false;
        if (c_parent_root) {
            extends_canonical = memcmp(canonical_head_block_root.bytes,
                                       c_parent_root->bytes, LANTERN_ROOT_SIZE) == 0;
        }

        LanternCheckpoint block_justified = state.latest_justified;
        LanternCheckpoint block_finalized = state.latest_finalized;

        LanternRoot block_root; /* Will be the C block_root after patching */

        if (extends_canonical) {
            /* Patch block body attestation roots FIRST (before state_root preview) */
            for (size_t att_idx = 0; att_idx < signed_block.block.body.attestations.length; ++att_idx) {
                LanternAggregatedAttestation *agg = &signed_block.block.body.attestations.data[att_idx];
                const LanternRoot *c_head = hash_mapping_leanspec_to_c(
                    hash_mapping, hash_mapping_count, &agg->data.head.root);
                if (c_head) {
                    agg->data.head.root = *c_head;
                }
                const LanternRoot *c_target = hash_mapping_leanspec_to_c(
                    hash_mapping, hash_mapping_count, &agg->data.target.root);
                if (c_target) {
                    agg->data.target.root = *c_target;
                }
                const LanternRoot *c_source = hash_mapping_leanspec_to_c(
                    hash_mapping, hash_mapping_count, &agg->data.source.root);
                if (c_source) {
                    agg->data.source.root = *c_source;
                }
            }
            /* Now patch block hashes (uses patched attestations for state_root preview) */
            if (patch_block_hashes_for_c_compat(&state, &signed_block) != 0) {
                if (!step_valid) {
                    reset_block(&signed_block.block);
                    continue;
                }
                fprintf(stderr, "failed to patch block hashes in fork_choice %s step %d\n", path, i);
                reset_block(&signed_block.block);
                reset_block(&anchor_block);
                lantern_fork_choice_reset(&store);
                lantern_state_reset(&state);
                lantern_fixture_document_reset(&doc);
                stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
                hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                return -1;
            }
            /* Recompute block_root after patching to get C hash */
            if (lantern_hash_tree_root_block(&signed_block.block, &block_root) != SSZ_SUCCESS) {
                if (!step_valid) {
                    reset_block(&signed_block.block);
                    continue;
                }
                reset_block(&signed_block.block);
                reset_block(&anchor_block);
                lantern_fork_choice_reset(&store);
                lantern_state_reset(&state);
                lantern_fixture_document_reset(&doc);
                stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
                hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                return -1;
            }
            if (signed_block.block.slot > state.slot) {
                if (state_transition_without_signatures(&state, &signed_block) != 0) {
                    if (!step_valid) {
                        reset_block(&signed_block.block);
                        continue;
                    }
                    fprintf(stderr, "state transition failed in fork_choice %s step %d\n", path, i);
                    reset_block(&signed_block.block);
                    reset_block(&anchor_block);
                    lantern_fork_choice_reset(&store);
                    lantern_state_reset(&state);
                    lantern_fixture_document_reset(&doc);
                    stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
                    hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                    return -1;
                }
                transition_performed = true;
                block_justified = state.latest_justified;
                block_finalized = state.latest_finalized;
            } else {
                active_state = &state;
                block_justified = state.latest_justified;
                block_finalized = state.latest_finalized;
            }
        } else {
            /* Non-canonical branch: look up parent state using C hash */
            const LanternRoot *c_parent_for_lookup = c_parent_root;
            if (!c_parent_for_lookup) {
                /* Parent not in mapping - this shouldn't happen for valid fixtures */
                fprintf(stderr, "parent not found in hash mapping for fork_choice %s step %d\n", path, i);
                reset_block(&signed_block.block);
                reset_block(&anchor_block);
                lantern_fork_choice_reset(&store);
                lantern_state_reset(&state);
                lantern_fixture_document_reset(&doc);
                stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
                hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                return -1;
            }
            struct stored_state_entry *parent_entry =
                stored_state_find(stored_states, stored_states_count, c_parent_for_lookup);
            if (!parent_entry) {
                fprintf(stderr, "parent state not found for fork_choice %s step %d\n", path, i);
                reset_block(&signed_block.block);
                reset_block(&anchor_block);
                lantern_fork_choice_reset(&store);
                lantern_state_reset(&state);
                lantern_fixture_document_reset(&doc);
                stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
                hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                return -1;
            }
            lantern_state_init(&branch_state);
            branch_state_initialized = true;
            if (stored_state_restore(stored_states, stored_states_count, c_parent_for_lookup, &branch_state) != 0) {
                lantern_state_reset(&branch_state);
                reset_block(&signed_block.block);
                reset_block(&anchor_block);
                lantern_fork_choice_reset(&store);
                lantern_state_reset(&state);
                lantern_fixture_document_reset(&doc);
                stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
                hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                return -1;
            }
            active_state = &branch_state;
            /* Patch block body attestation roots FIRST (before state_root preview) */
            for (size_t att_idx = 0; att_idx < signed_block.block.body.attestations.length; ++att_idx) {
                LanternAggregatedAttestation *agg = &signed_block.block.body.attestations.data[att_idx];
                const LanternRoot *c_head = hash_mapping_leanspec_to_c(
                    hash_mapping, hash_mapping_count, &agg->data.head.root);
                if (c_head) {
                    agg->data.head.root = *c_head;
                }
                const LanternRoot *c_target = hash_mapping_leanspec_to_c(
                    hash_mapping, hash_mapping_count, &agg->data.target.root);
                if (c_target) {
                    agg->data.target.root = *c_target;
                }
                const LanternRoot *c_source = hash_mapping_leanspec_to_c(
                    hash_mapping, hash_mapping_count, &agg->data.source.root);
                if (c_source) {
                    agg->data.source.root = *c_source;
                }
            }
            /* Now patch block hashes (uses patched attestations for state_root preview) */
            if (patch_block_hashes_for_c_compat(active_state, &signed_block) != 0) {
                if (!step_valid) {
                    lantern_state_reset(&branch_state);
                    reset_block(&signed_block.block);
                    continue;
                }
                fprintf(stderr, "failed to patch block hashes in fork_choice %s step %d (branch)\n", path, i);
                lantern_state_reset(&branch_state);
                reset_block(&signed_block.block);
                reset_block(&anchor_block);
                lantern_fork_choice_reset(&store);
                lantern_state_reset(&state);
                lantern_fixture_document_reset(&doc);
                stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
                hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                return -1;
            }
            /* Recompute block_root after patching to get C hash */
            if (lantern_hash_tree_root_block(&signed_block.block, &block_root) != SSZ_SUCCESS) {
                if (!step_valid) {
                    lantern_state_reset(&branch_state);
                    reset_block(&signed_block.block);
                    continue;
                }
                lantern_state_reset(&branch_state);
                reset_block(&signed_block.block);
                reset_block(&anchor_block);
                lantern_fork_choice_reset(&store);
                lantern_state_reset(&state);
                lantern_fixture_document_reset(&doc);
                stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
                hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                return -1;
            }
            if (state_transition_without_signatures(active_state, &signed_block) != 0) {
                if (!step_valid) {
                    lantern_state_reset(&branch_state);
                    reset_block(&signed_block.block);
                    continue;
                }
                fprintf(stderr, "branch state transition failed in fork_choice %s step %d\n", path, i);
                lantern_state_reset(&branch_state);
                reset_block(&signed_block.block);
                reset_block(&anchor_block);
                lantern_fork_choice_reset(&store);
                lantern_state_reset(&state);
                lantern_fixture_document_reset(&doc);
                stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
                hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                return -1;
            }
            transition_performed = true;
            block_justified = active_state->latest_justified;
            block_finalized = active_state->latest_finalized;
        }

        if (transition_performed) {
            if (stored_state_save(&stored_states, &stored_states_count, &stored_states_cap, &block_root, active_state) != 0) {
                fprintf(stderr, "failed to save post-state for %s (step %d)\n", path, i);
                if (branch_state_initialized) {
                    lantern_state_reset(&branch_state);
                }
                reset_block(&signed_block.block);
                reset_block(&anchor_block);
                lantern_fork_choice_reset(&store);
                lantern_state_reset(&state);
                lantern_fixture_document_reset(&doc);
                stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
                hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                return -1;
            }
        } else if (!stored_state_find(stored_states, stored_states_count, &block_root)) {
            if (stored_state_save(&stored_states, &stored_states_count, &stored_states_cap, &block_root, &state) != 0) {
                fprintf(stderr, "failed to save canonical state for %s (step %d)\n", path, i);
                if (branch_state_initialized) {
                    lantern_state_reset(&branch_state);
                }
                reset_block(&signed_block.block);
                reset_block(&anchor_block);
                lantern_fork_choice_reset(&store);
                lantern_state_reset(&state);
                lantern_fixture_document_reset(&doc);
                stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                return -1;
            }
        }

        uint64_t previous_finalized_slot = store.latest_finalized.slot;
        LanternCheckpoint post_justified = block_justified;
        LanternCheckpoint post_finalized = block_finalized;
        if (lantern_fork_choice_add_block(
                &store,
                &signed_block.block,
                &post_justified,
                &post_finalized,
                &block_root)
            != 0) {
            if (!step_valid) {
                if (branch_state_initialized) {
                    lantern_state_reset(&branch_state);
                }
                reset_block(&signed_block.block);
                continue;
            }
            if (branch_state_initialized) {
                lantern_state_reset(&branch_state);
            }
            reset_block(&signed_block.block);
            reset_block(&anchor_block);
            lantern_fork_choice_reset(&store);
            lantern_state_reset(&state);
            lantern_fixture_document_reset(&doc);
            stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                return -1;
        }
        if (record_block_body_known_payloads(&fork_choice_store, &signed_block) != 0) {
            fprintf(stderr, "failed to record block body payloads in %s (step %d)\n", path, i);
            if (branch_state_initialized) {
                lantern_state_reset(&branch_state);
            }
            reset_block(&signed_block.block);
            reset_block(&anchor_block);
            lantern_fork_choice_reset(&store);
            lantern_state_reset(&state);
            lantern_fixture_document_reset(&doc);
            stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
            hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
            return -1;
        }
        if (lantern_fork_choice_recompute_head(&store) != 0) {
            fprintf(stderr, "failed to recompute head after payload update in %s (step %d)\n", path, i);
            if (branch_state_initialized) {
                lantern_state_reset(&branch_state);
            }
            reset_block(&signed_block.block);
            reset_block(&anchor_block);
            lantern_fork_choice_reset(&store);
            lantern_state_reset(&state);
            lantern_fixture_document_reset(&doc);
            stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
            hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
            return -1;
        }
        if (store.latest_finalized.slot > previous_finalized_slot) {
            (void)lantern_store_prune_finalized_attestation_material(
                &fork_choice_store,
                store.latest_finalized.slot);
        }
        /* `lantern_fork_choice_add_block()` already expands and applies the
         * block body attestations in-order. Replaying them here as standalone
         * gossip votes is redundant and rejects valid fixtures where multiple
         * same-slot attestations legitimately move the head within one block. */

        if (extends_canonical && transition_performed) {
            canonical_head_block_root = block_root;
        }

        /* Save the hash mapping: leanspec_block_root -> block_root (C hash) */
        if (hash_mapping_add(&hash_mapping, &hash_mapping_count, &hash_mapping_cap,
                             &leanspec_block_root, &block_root) != 0) {
            if (branch_state_initialized) {
                lantern_state_reset(&branch_state);
            }
            reset_block(&signed_block.block);
            reset_block(&anchor_block);
            lantern_fork_choice_reset(&store);
            lantern_state_reset(&state);
            lantern_fixture_document_reset(&doc);
            stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
            hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
            return -1;
        }

        if (sync_state_to_fork_choice_head(&store, &state, &stored_states, &stored_states_count, &canonical_head_block_root) != 0) {
            if (branch_state_initialized) {
                lantern_state_reset(&branch_state);
            }
            reset_block(&signed_block.block);
            reset_block(&anchor_block);
            lantern_fork_choice_reset(&store);
            lantern_state_reset(&state);
            lantern_fixture_document_reset(&doc);
            stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
            return -1;
        }
        if (branch_state_initialized) {
            lantern_state_reset(&branch_state);
        }

        if (checks_idx >= 0) {
            LanternRoot head_root;
            if (lantern_fork_choice_current_head(&store, &head_root) != 0) {
                reset_block(&signed_block.block);
                reset_block(&anchor_block);
                lantern_fork_choice_reset(&store);
                lantern_state_reset(&state);
                lantern_fixture_document_reset(&doc);
                stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                return -1;
            }
            int head_slot_idx = lantern_fixture_object_get_field(&doc, checks_idx, "headSlot");
            if (head_slot_idx >= 0) {
                uint64_t expected_slot = 0;
                if (lantern_fixture_token_to_uint64(&doc, head_slot_idx, &expected_slot) != 0) {
                    reset_block(&signed_block.block);
                    reset_block(&anchor_block);
                    lantern_fork_choice_reset(&store);
                    lantern_state_reset(&state);
                    lantern_fixture_document_reset(&doc);
                    stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                    return -1;
                }
                uint64_t actual_slot = 0;
                if (lantern_fork_choice_block_info(&store, &head_root, &actual_slot, NULL, NULL) != 0) {
                    reset_block(&signed_block.block);
                    reset_block(&anchor_block);
                    lantern_fork_choice_reset(&store);
                    lantern_state_reset(&state);
                    lantern_fixture_document_reset(&doc);
                    stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                    return -1;
                }
                if (actual_slot != expected_slot) {
                    fprintf(
                        stderr,
                        "head slot mismatch in %s (step %d): expected %" PRIu64 " got %" PRIu64 "\n",
                        path,
                        i,
                        expected_slot,
                        actual_slot);
                    reset_block(&signed_block.block);
                    reset_block(&anchor_block);
                    lantern_fork_choice_reset(&store);
                    lantern_state_reset(&state);
                    lantern_fixture_document_reset(&doc);
                    stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                    return -1;
                }
            }

            int head_label_idx = lantern_fixture_object_get_field(&doc, checks_idx, "headRootLabel");
            if (head_label_idx >= 0) {
                size_t label_len = 0;
                const char *label = lantern_fixture_token_string(&doc, head_label_idx, &label_len);
                if (!label || label_len == 0) {
                    reset_block(&signed_block.block);
                    reset_block(&anchor_block);
                    lantern_fork_choice_reset(&store);
                    lantern_state_reset(&state);
                    lantern_fixture_document_reset(&doc);
                    stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                    return -1;
                }
                char label_buf[LABEL_MAX_LENGTH];
                if (label_len >= sizeof(label_buf)) {
                    label_len = sizeof(label_buf) - 1u;
                }
                memcpy(label_buf, label, label_len);
                label_buf[label_len] = '\0';
                if (label_registry_assign(&labels, label_buf, &head_root) != 0) {
                    reset_block(&signed_block.block);
                    reset_block(&anchor_block);
                    lantern_fork_choice_reset(&store);
                    lantern_state_reset(&state);
                    lantern_fixture_document_reset(&doc);
                    stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                    return -1;
                }
            }

            int lexicographic_idx = lantern_fixture_object_get_field(&doc, checks_idx, "lexicographicHeadAmong");
            if (lexicographic_idx >= 0) {
                int label_count = lantern_fixture_array_get_length(&doc, lexicographic_idx);
                if (label_count < 0) {
                    reset_block(&signed_block.block);
                    reset_block(&anchor_block);
                    lantern_fork_choice_reset(&store);
                    lantern_state_reset(&state);
                    lantern_fixture_document_reset(&doc);
                    stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                    return -1;
                }
                if (label_count < 2) {
                    fprintf(
                        stderr,
                        "lexicographicHeadAmong requires at least two labels in %s (step %d)\n",
                        path,
                        i);
                    reset_block(&signed_block.block);
                    reset_block(&anchor_block);
                    lantern_fork_choice_reset(&store);
                    lantern_state_reset(&state);
                    lantern_fixture_document_reset(&doc);
                    stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                    return -1;
                }
                char **lex_labels = calloc((size_t)label_count, sizeof(*lex_labels));
                if (!lex_labels) {
                    reset_block(&signed_block.block);
                    reset_block(&anchor_block);
                    lantern_fork_choice_reset(&store);
                    lantern_state_reset(&state);
                    lantern_fixture_document_reset(&doc);
                    stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                    return -1;
                }
                bool lexicographic_ok = true;
                for (int label_idx = 0; label_idx < label_count; ++label_idx) {
                    int token_idx = lantern_fixture_array_get_element(&doc, lexicographic_idx, label_idx);
                    if (token_idx < 0) {
                        lexicographic_ok = false;
                        break;
                    }
                    size_t label_len = 0;
                    const char *label_token = lantern_fixture_token_string(&doc, token_idx, &label_len);
                    if (!label_token || label_len == 0) {
                        lexicographic_ok = false;
                        break;
                    }
                    lex_labels[label_idx] = malloc(label_len + 1u);
                    if (!lex_labels[label_idx]) {
                        lexicographic_ok = false;
                        break;
                    }
                    memcpy(lex_labels[label_idx], label_token, label_len);
                    lex_labels[label_idx][label_len] = '\0';
                }
                if (lexicographic_ok) {
                    if (validate_lexicographic_head_among(
                            &store,
                            &head_root,
                            (size_t)label_count,
                            (const char **)lex_labels,
                            path,
                            i)
                        != 0) {
                        lexicographic_ok = false;
                    }
                }
                for (int label_idx = 0; label_idx < label_count; ++label_idx) {
                    free(lex_labels[label_idx]);
                }
                free(lex_labels);
                if (!lexicographic_ok) {
                    reset_block(&signed_block.block);
                    reset_block(&anchor_block);
                    lantern_fork_choice_reset(&store);
                    lantern_state_reset(&state);
                    lantern_fixture_document_reset(&doc);
                    stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                    return -1;
                }
            }

            int att_target_idx = lantern_fixture_object_get_field(&doc, checks_idx, "attestationTargetSlot");
            if (att_target_idx >= 0) {
                uint64_t expected_slot = 0;
                if (lantern_fixture_token_to_uint64(&doc, att_target_idx, &expected_slot) != 0) {
                    reset_block(&signed_block.block);
                    reset_block(&anchor_block);
                    lantern_fork_choice_reset(&store);
                    lantern_state_reset(&state);
                    lantern_fixture_document_reset(&doc);
                    stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                    return -1;
                }
                LanternCheckpoint head_cp;
                LanternCheckpoint target_cp;
                LanternCheckpoint source_cp;
                LanternStore *state_store = lantern_test_state_store_ensure(&state);
                struct lantern_fork_choice *saved_fork_choice = state_store ? state_store->fork_choice : NULL;
                if (state_store) {
                    state_store->fork_choice = &store;
                }
                int checkpoints_rc =
                    lantern_state_compute_vote_checkpoints(&state, &head_cp, &target_cp, &source_cp);
                if (state_store) {
                    state_store->fork_choice = saved_fork_choice;
                }
                if (checkpoints_rc != 0) {
                    reset_block(&signed_block.block);
                    reset_block(&anchor_block);
                    lantern_fork_choice_reset(&store);
                    lantern_state_reset(&state);
                    lantern_fixture_document_reset(&doc);
                    stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                    return -1;
                }
                if (target_cp.slot != expected_slot) {
                    fprintf(
                        stderr,
                        "attestation target slot mismatch in %s (step %d): expected %" PRIu64 " got %" PRIu64 "\n",
                        path,
                        i,
                        expected_slot,
                        target_cp.slot);
                    reset_block(&signed_block.block);
                    reset_block(&anchor_block);
                    lantern_fork_choice_reset(&store);
                    lantern_state_reset(&state);
                    lantern_fixture_document_reset(&doc);
                    stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
                    hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                    return -1;
                }
            }

            int att_checks_idx = lantern_fixture_object_get_field(&doc, checks_idx, "attestationChecks");
            if (att_checks_idx >= 0) {
                int length = lantern_fixture_array_get_length(&doc, att_checks_idx);
                if (length < 0) {
                    reset_block(&signed_block.block);
                    reset_block(&anchor_block);
                    lantern_fork_choice_reset(&store);
                    lantern_state_reset(&state);
                    lantern_fixture_document_reset(&doc);
                    stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                    return -1;
                }
                for (int entry = 0; entry < length; ++entry) {
                    int check_idx = lantern_fixture_array_get_element(&doc, att_checks_idx, entry);
                    if (check_idx < 0) {
                        reset_block(&signed_block.block);
                        reset_block(&anchor_block);
                        lantern_fork_choice_reset(&store);
                        lantern_state_reset(&state);
                        lantern_fixture_document_reset(&doc);
                        stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                        return -1;
                    }

                    uint64_t validator_id = 0;
                    int validator_idx = lantern_fixture_object_get_field(&doc, check_idx, "validator");
                    if (validator_idx < 0 || lantern_fixture_token_to_uint64(&doc, validator_idx, &validator_id) != 0) {
                        reset_block(&signed_block.block);
                        reset_block(&anchor_block);
                        lantern_fork_choice_reset(&store);
                        lantern_state_reset(&state);
                        lantern_fixture_document_reset(&doc);
                        stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                        return -1;
                    }
                    size_t validator = (size_t)validator_id;
                    if (validator >= store.validator_count) {
                        reset_block(&signed_block.block);
                        reset_block(&anchor_block);
                        lantern_fork_choice_reset(&store);
                        lantern_state_reset(&state);
                        lantern_fixture_document_reset(&doc);
                        stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                        return -1;
                    }

                    size_t location_len = 0;
                    int location_idx = lantern_fixture_object_get_field(&doc, check_idx, "location");
                    const char *location = lantern_fixture_token_string(&doc, location_idx, &location_len);
                    if (!location) {
                        reset_block(&signed_block.block);
                        reset_block(&anchor_block);
                        lantern_fork_choice_reset(&store);
                        lantern_state_reset(&state);
                        lantern_fixture_document_reset(&doc);
                        stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                        return -1;
                    }

                    const struct lantern_aggregated_payload_pool *payload_pool = NULL;
                    if (location_len == 3 && strncmp(location, "new", 3) == 0) {
                        payload_pool = store.new_aggregated_payloads;
                    } else if (location_len == 5 && strncmp(location, "known", 5) == 0) {
                        payload_pool = store.known_aggregated_payloads;
                    } else {
                        reset_block(&signed_block.block);
                        reset_block(&anchor_block);
                        lantern_fork_choice_reset(&store);
                        lantern_state_reset(&state);
                        lantern_fixture_document_reset(&doc);
                        stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
                        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                        return -1;
                    }

                    LanternAttestationData attestation;
                    bool attestation_found = false;
                    if (extract_attestation_from_payload_pool(
                            &fork_choice_store,
                            payload_pool,
                            validator,
                            &attestation,
                            &attestation_found)
                        != 0) {
                        reset_block(&signed_block.block);
                        reset_block(&anchor_block);
                        lantern_fork_choice_reset(&store);
                        lantern_state_reset(&state);
                        lantern_fixture_document_reset(&doc);
                        stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
                        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                        return -1;
                    }
                    if (!attestation_found) {
                        fprintf(
                            stderr,
                            "attestation missing from %.*s payloads in %s (step %d): validator %" PRIu64 "\n",
                            (int)location_len,
                            location,
                            path,
                            i,
                            validator_id);
                        reset_block(&signed_block.block);
                        reset_block(&anchor_block);
                        lantern_fork_choice_reset(&store);
                        lantern_state_reset(&state);
                        lantern_fixture_document_reset(&doc);
                        stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
                        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                        return -1;
                    }

                    int field_idx = lantern_fixture_object_get_field(&doc, check_idx, "attestationSlot");
                    if (field_idx >= 0) {
                        uint64_t expected_slot = 0;
                        if (lantern_fixture_token_to_uint64(&doc, field_idx, &expected_slot) != 0
                            || attestation.slot != expected_slot) {
                            fprintf(
                                stderr,
                                "attestation slot mismatch in %s (step %d): validator %" PRIu64 "\n",
                                path,
                                i,
                                validator_id);
                            reset_block(&signed_block.block);
                            reset_block(&anchor_block);
                            lantern_fork_choice_reset(&store);
                            lantern_state_reset(&state);
                            lantern_fixture_document_reset(&doc);
                            stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                            return -1;
                        }
                    }

                    field_idx = lantern_fixture_object_get_field(&doc, check_idx, "headSlot");
                    if (field_idx >= 0) {
                        uint64_t expected_slot = 0;
                        if (lantern_fixture_token_to_uint64(&doc, field_idx, &expected_slot) != 0
                            || attestation.head.slot != expected_slot) {
                            fprintf(
                                stderr,
                                "attestation head slot mismatch in %s (step %d): validator %" PRIu64 "\n",
                                path,
                                i,
                                validator_id);
                            reset_block(&signed_block.block);
                            reset_block(&anchor_block);
                            lantern_fork_choice_reset(&store);
                            lantern_state_reset(&state);
                            lantern_fixture_document_reset(&doc);
                            stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                            return -1;
                        }
                    }

                    field_idx = lantern_fixture_object_get_field(&doc, check_idx, "sourceSlot");
                    if (field_idx >= 0) {
                        uint64_t expected_slot = 0;
                        if (lantern_fixture_token_to_uint64(&doc, field_idx, &expected_slot) != 0
                            || attestation.source.slot != expected_slot) {
                            fprintf(
                                stderr,
                                "attestation source slot mismatch in %s (step %d): validator %" PRIu64 "\n",
                                path,
                                i,
                                validator_id);
                            reset_block(&signed_block.block);
                            reset_block(&anchor_block);
                            lantern_fork_choice_reset(&store);
                            lantern_state_reset(&state);
                            lantern_fixture_document_reset(&doc);
                            stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                            return -1;
                        }
                    }

                    field_idx = lantern_fixture_object_get_field(&doc, check_idx, "targetSlot");
                    if (field_idx >= 0) {
                        uint64_t expected_slot = 0;
                        if (lantern_fixture_token_to_uint64(&doc, field_idx, &expected_slot) != 0
                            || attestation.target.slot != expected_slot) {
                            fprintf(
                                stderr,
                                "attestation target slot mismatch in %s (step %d): validator %" PRIu64 "\n",
                                path,
                                i,
                                validator_id);
                            reset_block(&signed_block.block);
                            reset_block(&anchor_block);
                            lantern_fork_choice_reset(&store);
                            lantern_state_reset(&state);
                            lantern_fixture_document_reset(&doc);
                            return -1;
                        }
                    }
                }
            }
        }

        reset_block(&signed_block.block);
    }

    reset_block(&anchor_block);
    lantern_fork_choice_reset(&store);
    lantern_store_reset(&fork_choice_store);
    lantern_state_reset(&state);
    lantern_fixture_document_reset(&doc);
    stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
    return 0;
}

int lantern_run_fixture_suite(const struct lantern_fixture_run_config *config) {
    if (!config || !config->suite_name || !config->state_transition_subdir) {
        fprintf(stderr, "invalid fixture run configuration\n");
        return 1;
    }

    configure_logging();
    char state_transition_root[1024];
    int written = snprintf(
        state_transition_root,
        sizeof(state_transition_root),
        "%s/%s",
        LANTERN_CONSENSUS_FIXTURE_DIR,
        config->state_transition_subdir);
    if (written <= 0 || written >= (int)sizeof(state_transition_root)) {
        fprintf(stderr, "fixture path too long\n");
        return 1;
    }
    if (for_each_json(state_transition_root, run_state_transition_fixture) != 0) {
        return 1;
    }

    if (config->include_fork_choice) {
        if (!config->fork_choice_subdir) {
            fprintf(stderr, "fork choice subdirectory not specified\n");
            return 1;
        }
        char fork_choice_root[1024];
        written = snprintf(
            fork_choice_root,
            sizeof(fork_choice_root),
            "%s/%s",
            LANTERN_CONSENSUS_FIXTURE_DIR,
            config->fork_choice_subdir);
        if (written <= 0 || written >= (int)sizeof(fork_choice_root)) {
            fprintf(stderr, "fixture path too long\n");
            return 1;
        }

        if (for_each_json(fork_choice_root, run_fork_choice_fixture) != 0) {
            return 1;
        }
    }

    printf("%s OK\n", config->suite_name);
    return 0;
}
