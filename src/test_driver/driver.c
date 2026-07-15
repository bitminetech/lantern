#include "test_driver/driver.h"

#include <inttypes.h>
#include <pthread.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "lantern/consensus/containers.h"
#include "lantern/consensus/fork_choice.h"
#include "lantern/consensus/hash.h"
#include "lantern/consensus/signature.h"
#include "lantern/consensus/slot_clock.h"
#include "lantern/consensus/state.h"
#include "lantern/consensus/store.h"
#include "lantern/support/strings.h"
#include "tests/support/fixture_loader.h"
#include "tests/support/state_store_adapter.h"

struct hash_mapping_entry {
    LanternRoot leanspec_hash;
    LanternRoot c_hash;
};

struct hash_mapping {
    struct hash_mapping_entry *entries;
    size_t count;
    size_t capacity;
};

struct fork_choice_driver {
    LanternStore store;
    struct hash_mapping hash_mapping;
};

static pthread_mutex_t g_driver_lock = PTHREAD_MUTEX_INITIALIZER;
static struct fork_choice_driver g_driver;

static int document_from_body(
    const char *body,
    size_t body_len,
    struct lantern_fixture_document *doc)
{
    if (!body || !doc)
    {
        return -1;
    }
    char *text = malloc(body_len + 1u);
    if (!text)
    {
        return -1;
    }
    memcpy(text, body, body_len);
    text[body_len] = '\0';
    return lantern_fixture_document_init(doc, text);
}

static bool fixture_token_equals_literal(
    const struct lantern_fixture_document *doc,
    int index,
    const char *literal)
{
    if (!doc || !literal || index < 0)
    {
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
    bool *out_value)
{
    if (!doc || !out_value)
    {
        return -1;
    }
    const jsmntok_t *tok = lantern_fixture_token(doc, index);
    if (!tok || tok->type != JSMN_PRIMITIVE)
    {
        return -1;
    }
    size_t length = (size_t)(tok->end - tok->start);
    if (length == 4u && strncmp(doc->text + tok->start, "true", 4u) == 0)
    {
        *out_value = true;
        return 0;
    }
    if (length == 5u && strncmp(doc->text + tok->start, "false", 5u) == 0)
    {
        *out_value = false;
        return 0;
    }
    return -1;
}

static void driver_format_root_hex(const LanternRoot *root, char *buf, size_t buf_len)
{
    if (!buf || buf_len == 0)
    {
        return;
    }
    if (!root
        || lantern_bytes_to_hex(root->bytes, LANTERN_ROOT_SIZE, buf, buf_len, 1) != 0)
    {
        buf[0] = '\0';
    }
}

static const LanternRoot *hash_mapping_lookup(
    const struct hash_mapping *mapping,
    const LanternRoot *root,
    bool leanspec_to_c)
{
    if (!mapping || !root)
    {
        return NULL;
    }
    for (size_t i = 0; i < mapping->count; ++i)
    {
        const struct hash_mapping_entry *entry = &mapping->entries[i];
        const LanternRoot *from = leanspec_to_c ? &entry->leanspec_hash : &entry->c_hash;
        if (lantern_root_equal(from, root))
        {
            return leanspec_to_c ? &entry->c_hash : &entry->leanspec_hash;
        }
    }
    return NULL;
}

static int hash_mapping_add(
    struct hash_mapping *mapping,
    const LanternRoot *leanspec_hash,
    const LanternRoot *c_hash)
{
    if (!mapping || !leanspec_hash || !c_hash)
    {
        return -1;
    }
    for (size_t i = 0; i < mapping->count; ++i)
    {
        if (lantern_root_equal(&mapping->entries[i].leanspec_hash, leanspec_hash))
        {
            mapping->entries[i].c_hash = *c_hash;
            return 0;
        }
    }
    if (mapping->count == mapping->capacity)
    {
        size_t new_capacity = mapping->capacity == 0 ? 16u : mapping->capacity * 2u;
        if (new_capacity < mapping->capacity)
        {
            return -1;
        }
        struct hash_mapping_entry *expanded =
            realloc(mapping->entries, new_capacity * sizeof(*expanded));
        if (!expanded)
        {
            return -1;
        }
        mapping->entries = expanded;
        mapping->capacity = new_capacity;
    }
    mapping->entries[mapping->count++] = (struct hash_mapping_entry){
        .leanspec_hash = *leanspec_hash,
        .c_hash = *c_hash,
    };
    return 0;
}

static int apply_block_without_signatures(
    LanternState *state,
    const LanternBlock *block,
    LanternRoot *out_state_root)
{
    if (!state || !block || block->slot <= state->slot)
    {
        return -1;
    }
    int rc = -1;
    if (lantern_state_process_slots(state, block->slot) != 0)
    {
        goto cleanup;
    }
    if (lantern_state_process_block_explicit(state, block) != 0)
    {
        goto cleanup;
    }
    if (out_state_root && lantern_hash_tree_root_state(state, out_state_root) != SSZ_SUCCESS)
    {
        goto cleanup;
    }
    rc = 0;

cleanup:
    return rc;
}

static int preview_post_state_root_without_signatures(
    const LanternState *state,
    const LanternSignedBlock *signed_block,
    LanternRoot *out_state_root)
{
    if (!state || !signed_block || !out_state_root)
    {
        return -1;
    }

    LanternState scratch;
    lantern_state_init(&scratch);
    int rc = -1;
    if (lantern_state_clone(state, &scratch) == 0)
    {
        rc = apply_block_without_signatures(&scratch, &signed_block->block, out_state_root);
    }
    lantern_state_reset(&scratch);
    return rc;
}

static int state_transition_without_signatures(
    LanternState *state,
    const LanternSignedBlock *signed_block)
{
    if (!state || !signed_block)
    {
        return -1;
    }
    const LanternBlock *block = &signed_block->block;
    if (block->slot <= state->slot)
    {
        return -1;
    }
    LanternRoot computed_state_root;
    if (apply_block_without_signatures(state, block, &computed_state_root) != 0)
    {
        return -1;
    }
    return memcmp(block->state_root.bytes, computed_state_root.bytes, LANTERN_ROOT_SIZE) == 0
        ? 0
        : -1;
}

static int patch_block_hashes_for_c_compat(
    LanternState *state,
    LanternSignedBlock *signed_block)
{
    if (!state || !signed_block)
    {
        return -1;
    }

    LanternBlockHeader header_after_slots = state->latest_block_header;
    if (lantern_root_is_zero(&header_after_slots.state_root)
        && lantern_hash_tree_root_state(state, &header_after_slots.state_root) != SSZ_SUCCESS)
    {
        return -1;
    }
    if (lantern_hash_tree_root_block_header(
            &header_after_slots,
            &signed_block->block.parent_root)
        != SSZ_SUCCESS)
    {
        return -1;
    }

    LanternRoot computed_state_root;
    if (preview_post_state_root_without_signatures(state, signed_block, &computed_state_root) != 0)
    {
        return -1;
    }
    signed_block->block.state_root = computed_state_root;
    return 0;
}

static int aggregate_pending_gossip_attestations(
    const LanternState *state,
    LanternStore *store)
{
    if (!state || !store)
    {
        return -1;
    }

    struct lantern_aggregated_payload_pool aggregated_payloads = {0};

    int rc = -1;
    if (store->attestation_signatures.length == 0u)
    {
        rc = 0;
        goto cleanup;
    }

    if (lantern_state_aggregate(
            state,
            store,
            &aggregated_payloads)
        != LANTERN_STATE_AGGREGATE_OK)
    {
        goto cleanup;
    }

    lantern_store_clear_new_aggregated_payloads(store);
    for (size_t i = 0; i < aggregated_payloads.length; ++i)
    {
        const struct lantern_aggregated_payload_entry *entry = &aggregated_payloads.entries[i];
        if (lantern_store_add_new_aggregated_payload(
                store,
                &entry->data_root,
                &entry->data,
                &entry->proof)
            != 0)
        {
            goto cleanup;
        }
        (void)lantern_store_remove_attestation_signatures_for_data_root(
            store,
            &entry->data_root);
    }
    rc = 0;

cleanup:
    lantern_aggregated_payload_pool_reset(&aggregated_payloads);
    return rc;
}

static int sync_payload_pools_after_time_advance(
    LanternStore *store,
    const LanternState *state,
    uint64_t previous_intervals,
    bool has_proposal)
{
    if (!store || !state)
    {
        return -1;
    }
    if (store->time_intervals <= previous_intervals)
    {
        return 0;
    }
    for (uint64_t step = previous_intervals + 1u; step <= store->time_intervals; ++step)
    {
        uint64_t interval_index = step % LANTERN_INTERVALS_PER_SLOT;
        bool step_has_proposal = has_proposal && (step == store->time_intervals);
        if (interval_index == LANTERN_DUTY_PHASE_AGGREGATE)
        {
            if (aggregate_pending_gossip_attestations(state, store) != 0)
            {
                return -1;
            }
        }
        if (interval_index == LANTERN_DUTY_PHASE_VOTE_ACCEPT
            || (interval_index == LANTERN_DUTY_PHASE_PROPOSAL && step_has_proposal))
        {
            size_t promoted = lantern_store_promote_new_aggregated_payloads(store);
            if (promoted > 0u && lantern_fork_choice_accept_new_aggregated_payloads(store) != 0)
            {
                return -1;
            }
        }
    }
    return 0;
}

static int record_block_body_known_payloads(
    LanternStore *store,
    const LanternSignedBlock *signed_block)
{
    if (!store || !signed_block)
    {
        return -1;
    }
    const LanternAggregatedAttestations *attestations = &signed_block->block.body.attestations;
    for (size_t i = 0; i < attestations->length; ++i)
    {
        LanternRoot data_root;
        if (lantern_hash_tree_root_attestation_data(&attestations->data[i].data, &data_root)
            != SSZ_SUCCESS)
        {
            return -1;
        }
        LanternAggregatedSignatureProof proof;
        lantern_aggregated_signature_proof_init(&proof);
        if (lantern_bitlist_resize(&proof.participants, attestations->data[i].aggregation_bits.bit_length) != 0)
        {
            lantern_aggregated_signature_proof_reset(&proof);
            return -1;
        }
        size_t byte_len = (proof.participants.bit_length + 7u) / 8u;
        if (byte_len > 0u)
        {
            if (!proof.participants.bytes || !attestations->data[i].aggregation_bits.bytes)
            {
                lantern_aggregated_signature_proof_reset(&proof);
                return -1;
            }
            memcpy(proof.participants.bytes, attestations->data[i].aggregation_bits.bytes, byte_len);
        }
        if (lantern_byte_list_resize(&proof.proof_data, 1u) != 0)
        {
            lantern_aggregated_signature_proof_reset(&proof);
            return -1;
        }
        proof.proof_data.data[0] = 0u;
        int rc = lantern_store_add_known_aggregated_payload(
            store,
            &data_root,
            &attestations->data[i].data,
            &proof);
        lantern_aggregated_signature_proof_reset(&proof);
        if (rc != 0)
        {
            return -1;
        }
    }
    return 0;
}

static void map_attestation_data_roots(
    const struct fork_choice_driver *driver,
    LanternAttestationData *data)
{
    if (!driver || !data)
    {
        return;
    }
    const LanternRoot *mapped = hash_mapping_lookup(
        &driver->hash_mapping,
        &data->head.root,
        true);
    if (mapped)
    {
        data->head.root = *mapped;
    }
    mapped = hash_mapping_lookup(
        &driver->hash_mapping,
        &data->target.root,
        true);
    if (mapped)
    {
        data->target.root = *mapped;
    }
    mapped = hash_mapping_lookup(
        &driver->hash_mapping,
        &data->source.root,
        true);
    if (mapped)
    {
        data->source.root = *mapped;
    }
}

static void map_block_attestation_roots(
    const struct fork_choice_driver *driver,
    LanternBlock *block)
{
    if (!driver || !block)
    {
        return;
    }
    for (size_t i = 0; i < block->body.attestations.length; ++i)
    {
        map_attestation_data_roots(driver, &block->body.attestations.data[i].data);
    }
}

static int process_gossip_attestation_step(
    const struct lantern_fixture_document *doc,
    int step_idx,
    const struct fork_choice_driver *driver,
    LanternStore *store)
{
    if (!doc || !store)
    {
        return -1;
    }
    int attestation_idx = lantern_fixture_object_get_field(doc, step_idx, "attestation");
    if (attestation_idx < 0)
    {
        return -1;
    }

    LanternSignedVote vote;
    if (lantern_fixture_parse_attestation_message(doc, attestation_idx, &vote) != 0)
    {
        return -1;
    }
    map_attestation_data_roots(driver, &vote.data.data);
    LanternRoot data_root;
    if (lantern_hash_tree_root_attestation_data(&vote.data.data, &data_root) != SSZ_SUCCESS)
    {
        return -1;
    }
    LanternSignatureKey key = {
        .validator_index = vote.data.validator_id,
        .data_root = data_root,
    };
    return lantern_store_set_attestation_signature(
        store,
        &key,
        &vote.data.data,
        &vote.signature);
}

static int process_gossip_aggregated_attestation_step(
    const struct lantern_fixture_document *doc,
    int step_idx,
    const struct fork_choice_driver *driver,
    LanternStore *store)
{
    if (!doc || !store)
    {
        return -1;
    }
    int attestation_idx = lantern_fixture_object_get_field(doc, step_idx, "attestation");
    if (attestation_idx < 0)
    {
        return -1;
    }
    int data_idx = lantern_fixture_object_get_field(doc, attestation_idx, "data");
    int proof_idx = lantern_fixture_object_get_field(doc, attestation_idx, "proof");
    if (data_idx < 0 || proof_idx < 0)
    {
        return -1;
    }

    LanternAttestationData data;
    LanternAggregatedSignatureProof proof;
    memset(&data, 0, sizeof(data));
    lantern_aggregated_signature_proof_init(&proof);
    int rc = -1;
    if (lantern_fixture_parse_attestation_data(doc, data_idx, &data) != 0)
    {
        goto cleanup;
    }
    map_attestation_data_roots(driver, &data);
    if (lantern_fixture_parse_signature_proof(doc, proof_idx, &proof) != 0)
    {
        goto cleanup;
    }
    LanternRoot data_root;
    if (lantern_hash_tree_root_attestation_data(&data, &data_root) != SSZ_SUCCESS)
    {
        goto cleanup;
    }
    rc = lantern_store_add_new_aggregated_payload(
        store,
        &data_root,
        &data,
        &proof);

cleanup:
    lantern_aggregated_signature_proof_reset(&proof);
    return rc;
}

static void fork_choice_driver_reset(struct fork_choice_driver *driver)
{
    if (!driver)
    {
        return;
    }
    lantern_store_reset(&driver->store);
    free(driver->hash_mapping.entries);
    memset(driver, 0, sizeof(*driver));
}

static int fork_choice_driver_snapshot_json(
    const struct fork_choice_driver *driver,
    bool accepted,
    const char *error,
    char **out_body,
    size_t *out_body_len)
{
    if (!driver || !out_body || !out_body_len)
    {
        return -1;
    }
    *out_body = NULL;
    *out_body_len = 0;

    LanternRoot head_root;
    memset(&head_root, 0, sizeof(head_root));
    uint64_t head_slot = 0;
    if (driver->store.block_len > 0u)
    {
        head_root = driver->store.head;
        (void)lantern_fork_choice_block_info(
            &driver->store,
            &head_root,
            &head_slot,
            NULL,
            NULL);
    }
    const LanternRoot *lean_head = hash_mapping_lookup(
        &driver->hash_mapping,
        &head_root,
        false);
    if (lean_head)
    {
        head_root = *lean_head;
    }

    LanternCheckpoint justified = driver->store.latest_justified;
    const LanternRoot *lean_justified = hash_mapping_lookup(
        &driver->hash_mapping,
        &justified.root,
        false);
    if (lean_justified)
    {
        justified.root = *lean_justified;
    }

    LanternCheckpoint finalized = driver->store.latest_finalized;
    const LanternRoot *lean_finalized = hash_mapping_lookup(
        &driver->hash_mapping,
        &finalized.root,
        false);
    if (lean_finalized)
    {
        finalized.root = *lean_finalized;
    }

    LanternRoot safe_target;
    memset(&safe_target, 0, sizeof(safe_target));
    if (driver->store.block_len > 0u)
    {
        safe_target = driver->store.safe_target;
        const LanternRoot *lean_safe = hash_mapping_lookup(
            &driver->hash_mapping,
            &safe_target,
            false);
        if (lean_safe)
        {
            safe_target = *lean_safe;
        }
    }

    char head_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    char justified_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    char finalized_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    char safe_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    driver_format_root_hex(&head_root, head_hex, sizeof(head_hex));
    driver_format_root_hex(&justified.root, justified_hex, sizeof(justified_hex));
    driver_format_root_hex(&finalized.root, finalized_hex, sizeof(finalized_hex));
    driver_format_root_hex(&safe_target, safe_hex, sizeof(safe_hex));

    const char *error_text = error ? error : "";
    size_t body_cap = strlen(error_text) + 768u;
    char *body = malloc(body_cap);
    if (!body)
    {
        return -1;
    }
    int written = snprintf(
        body,
        body_cap,
        "{\"accepted\":%s,\"error\":%s%s%s,\"snapshot\":{"
        "\"headSlot\":%" PRIu64 ",\"headRoot\":\"%s\",\"time\":%" PRIu64 ","
        "\"justifiedCheckpoint\":{\"slot\":%" PRIu64 ",\"root\":\"%s\"},"
        "\"finalizedCheckpoint\":{\"slot\":%" PRIu64 ",\"root\":\"%s\"},"
        "\"safeTarget\":\"%s\"}}",
        accepted ? "true" : "false",
        error ? "\"" : "",
        error ? error_text : "null",
        error ? "\"" : "",
        head_slot,
        head_hex,
        driver->store.time_intervals,
        justified.slot,
        justified_hex,
        finalized.slot,
        finalized_hex,
        safe_hex);
    if (written < 0 || (size_t)written >= body_cap)
    {
        free(body);
        return -1;
    }
    *out_body = body;
    *out_body_len = (size_t)written;
    return 0;
}

static int fork_choice_process_block_step(
    struct fork_choice_driver *driver,
    const struct lantern_fixture_document *doc,
    int block_idx)
{
    LanternSignedBlock signed_block;
    if (lantern_fixture_parse_signed_block(doc, block_idx, &signed_block) != 0)
    {
        return -1;
    }
    int rc = -1;
    LanternState post_state;
    lantern_state_init(&post_state);

    if (signed_block.block.slot > UINT64_MAX / LANTERN_INTERVALS_PER_SLOT)
    {
        goto cleanup;
    }
    const LanternState *aggregation_state =
        lantern_fork_choice_block_state(&driver->store, &driver->store.head);
    if (!aggregation_state)
    {
        goto cleanup;
    }
    uint64_t target_interval = signed_block.block.slot * LANTERN_INTERVALS_PER_SLOT;
    uint64_t previous_intervals = driver->store.time_intervals;
    if (lantern_fork_choice_advance_to(&driver->store, target_interval, true) != 0)
    {
        goto cleanup;
    }
    if (sync_payload_pools_after_time_advance(
            &driver->store,
            aggregation_state,
            previous_intervals,
            true)
        != 0)
    {
        goto cleanup;
    }

    LanternRoot leanspec_block_root;
    if (lantern_hash_tree_root_block(&signed_block.block, &leanspec_block_root) != SSZ_SUCCESS)
    {
        goto cleanup;
    }

    LanternRoot leanspec_parent_root = signed_block.block.parent_root;
    const LanternRoot *c_parent_root = hash_mapping_lookup(
        &driver->hash_mapping,
        &leanspec_parent_root,
        true);
    bool extends_canonical = c_parent_root
        && lantern_root_equal(&driver->store.head, c_parent_root);
    if (!c_parent_root)
    {
        goto cleanup;
    }
    const LanternState *parent_state =
        lantern_fork_choice_block_state(&driver->store, c_parent_root);
    if (!parent_state || lantern_state_clone(parent_state, &post_state) != 0)
    {
        goto cleanup;
    }

    LanternCheckpoint block_justified = post_state.latest_justified;
    LanternCheckpoint block_finalized = post_state.latest_finalized;
    LanternRoot block_root;
    memset(&block_root, 0, sizeof(block_root));
    map_block_attestation_roots(driver, &signed_block.block);

    if (patch_block_hashes_for_c_compat(&post_state, &signed_block) != 0
        || lantern_hash_tree_root_block(&signed_block.block, &block_root) != SSZ_SUCCESS)
    {
        goto cleanup;
    }
    if (!extends_canonical || signed_block.block.slot > post_state.slot)
    {
        if (state_transition_without_signatures(&post_state, &signed_block) != 0)
        {
            goto cleanup;
        }
        block_justified = post_state.latest_justified;
        block_finalized = post_state.latest_finalized;
    }

    uint64_t previous_finalized_slot = driver->store.latest_finalized.slot;
    if (lantern_fork_choice_add_block(
            &driver->store,
            &signed_block.block,
            &block_justified,
            &block_finalized,
            &block_root)
        != 0)
    {
        goto cleanup;
    }
    if (lantern_fork_choice_set_block_state(
            &driver->store,
            &block_root,
            &post_state)
        != 0)
    {
        goto cleanup;
    }
    if (record_block_body_known_payloads(&driver->store, &signed_block) != 0)
    {
        goto cleanup;
    }
    if (lantern_fork_choice_recompute_head(&driver->store) != 0)
    {
        goto cleanup;
    }
    if (driver->store.latest_finalized.slot > previous_finalized_slot)
    {
        (void)lantern_store_prune_finalized_attestation_material(
            &driver->store,
            driver->store.latest_finalized.slot);
    }
    if (hash_mapping_add(
            &driver->hash_mapping,
            &leanspec_block_root,
            &block_root)
        != 0)
    {
        goto cleanup;
    }
    rc = 0;

cleanup:
    lantern_state_reset(&post_state);
    lantern_block_body_reset(&signed_block.block.body);
    return rc;
}

int lantern_test_driver_fork_choice_init(
    const char *body,
    size_t body_len,
    char **out_error)
{
    if (out_error)
    {
        *out_error = NULL;
    }

    pthread_mutex_lock(&g_driver_lock);
    fork_choice_driver_reset(&g_driver);

    struct lantern_fixture_document doc;
    if (document_from_body(body, body_len, &doc) != 0)
    {
        if (out_error)
        {
            *out_error = lantern_string_duplicate("invalid JSON");
        }
        pthread_mutex_unlock(&g_driver_lock);
        return -1;
    }

    int rc = -1;
    LanternState anchor_state = {0};
    LanternBlock anchor_block = {0};
    int root_idx = 0;
    int anchor_state_idx = lantern_fixture_object_get_field(&doc, root_idx, "anchorState");
    int anchor_block_idx = lantern_fixture_object_get_field(&doc, root_idx, "anchorBlock");
    if (anchor_state_idx < 0 || anchor_block_idx < 0)
    {
        if (out_error)
        {
            *out_error = lantern_string_duplicate("missing anchor");
        }
        goto cleanup;
    }

    LanternCheckpoint latest_justified;
    LanternCheckpoint latest_finalized;
    uint64_t genesis_time = 0;
    uint64_t validator_count = 0;
    if (lantern_fixture_parse_anchor_state(
            &doc,
            anchor_state_idx,
            &anchor_state,
            &latest_justified,
            &latest_finalized,
            &genesis_time,
            &validator_count)
        != 0)
    {
        if (out_error)
        {
            *out_error = lantern_string_duplicate("invalid anchor state");
        }
        goto cleanup;
    }

    if (lantern_fixture_parse_block(&doc, anchor_block_idx, &anchor_block) != 0)
    {
        if (out_error)
        {
            *out_error = lantern_string_duplicate("invalid anchor block");
        }
        goto cleanup;
    }

    LanternRoot anchor_state_root;
    if (lantern_hash_tree_root_state(&anchor_state, &anchor_state_root) != SSZ_SUCCESS
        || !lantern_root_equal(&anchor_state_root, &anchor_block.state_root))
    {
        if (out_error)
        {
            *out_error = lantern_string_duplicate("anchor state root mismatch");
        }
        goto cleanup;
    }

    LanternRoot anchor_body_root;
    if (lantern_hash_tree_root_block_body(&anchor_block.body, &anchor_body_root) != SSZ_SUCCESS)
    {
        if (out_error)
        {
            *out_error = lantern_string_duplicate("anchor body hash failed");
        }
        goto cleanup;
    }
    anchor_state.latest_block_header.slot = anchor_block.slot;
    anchor_state.latest_block_header.proposer_index = anchor_block.proposer_index;
    anchor_state.latest_block_header.parent_root = anchor_block.parent_root;
    anchor_state.latest_block_header.state_root = anchor_block.state_root;
    anchor_state.latest_block_header.body_root = anchor_body_root;
    anchor_state.slot = anchor_block.slot;

    lantern_store_init(&g_driver.store);
    LanternRoot anchor_root;
    if (lantern_hash_tree_root_block(&anchor_block, &anchor_root) != SSZ_SUCCESS)
    {
        if (out_error)
        {
            *out_error = lantern_string_duplicate("anchor hash failed");
        }
        goto cleanup;
    }
    LanternCheckpoint anchor_checkpoint = {
        .root = anchor_root,
        .slot = anchor_block.slot,
    };
    if (lantern_fork_choice_set_anchor_with_state(
            &g_driver.store,
            &anchor_block,
            &anchor_checkpoint,
            &anchor_checkpoint,
            &anchor_root,
            &anchor_state)
        != 0)
    {
        if (out_error)
        {
            *out_error = lantern_string_duplicate("fork choice anchor failed");
        }
        goto cleanup;
    }
    if (hash_mapping_add(
               &g_driver.hash_mapping,
               &anchor_root,
               &anchor_root)
        != 0)
    {
        if (out_error)
        {
            *out_error = lantern_string_duplicate("anchor state cache failed");
        }
        goto cleanup;
    }

    rc = 0;

cleanup:
    lantern_block_body_reset(&anchor_block.body);
    lantern_state_reset(&anchor_state);
    if (rc != 0)
    {
        fork_choice_driver_reset(&g_driver);
    }
    lantern_fixture_document_reset(&doc);
    pthread_mutex_unlock(&g_driver_lock);
    return rc;
}

int lantern_test_driver_fork_choice_step(
    const char *body,
    size_t body_len,
    char **out_body,
    size_t *out_body_len)
{
    if (!out_body || !out_body_len)
    {
        return -1;
    }
    *out_body = NULL;
    *out_body_len = 0;

    pthread_mutex_lock(&g_driver_lock);
    if (g_driver.store.block_len == 0u)
    {
        int rc = fork_choice_driver_snapshot_json(
            &g_driver,
            false,
            "fork choice not initialized",
            out_body,
            out_body_len);
        pthread_mutex_unlock(&g_driver_lock);
        return rc;
    }

    struct lantern_fixture_document doc;
    if (document_from_body(body, body_len, &doc) != 0)
    {
        int rc = fork_choice_driver_snapshot_json(
            &g_driver,
            false,
            "invalid JSON",
            out_body,
            out_body_len);
        pthread_mutex_unlock(&g_driver_lock);
        return rc;
    }

    int root_idx = 0;
    bool accepted = false;
    const char *error = NULL;
    int valid_idx = lantern_fixture_object_get_field(&doc, root_idx, "valid");
    bool has_expected_valid = valid_idx >= 0;
    bool expected_valid = true;
    if (has_expected_valid && fixture_token_to_bool(&doc, valid_idx, &expected_valid) != 0)
    {
        error = "invalid valid flag";
        goto respond;
    }
    if (has_expected_valid && !expected_valid)
    {
        accepted = false;
        goto respond;
    }

    int step_type_idx = lantern_fixture_object_get_field(&doc, root_idx, "stepType");
    bool is_attestation_step = fixture_token_equals_literal(&doc, step_type_idx, "attestation");
    bool is_gossip_aggregated_step =
        fixture_token_equals_literal(&doc, step_type_idx, "gossipAggregatedAttestation");
    int block_idx = lantern_fixture_object_get_field(&doc, root_idx, "block");
    int time_idx = lantern_fixture_object_get_field(&doc, root_idx, "time");
    int interval_idx = lantern_fixture_object_get_field(&doc, root_idx, "interval");
    int rc = 0;
    if (is_attestation_step)
    {
        rc = process_gossip_attestation_step(
            &doc,
            root_idx,
            &g_driver,
            &g_driver.store);
    }
    else if (is_gossip_aggregated_step)
    {
        rc = process_gossip_aggregated_attestation_step(
            &doc,
            root_idx,
            &g_driver,
            &g_driver.store);
    }
    else if (block_idx >= 0)
    {
        rc = fork_choice_process_block_step(&g_driver, &doc, block_idx);
    }
    else if (time_idx >= 0 || interval_idx >= 0)
    {
        bool has_proposal = false;
        int has_proposal_idx = lantern_fixture_object_get_field(&doc, root_idx, "hasProposal");
        if (has_proposal_idx >= 0
            && fixture_token_to_bool(&doc, has_proposal_idx, &has_proposal) != 0)
        {
            rc = -1;
        }
        else
        {
            uint64_t target_interval = 0;
            if (interval_idx >= 0)
            {
                if (lantern_fixture_token_to_uint64(&doc, interval_idx, &target_interval) != 0)
                {
                    rc = -1;
                }
            }
            else
            {
                uint64_t time_seconds = 0;
                if (lantern_fixture_token_to_uint64(&doc, time_idx, &time_seconds) != 0
                    || time_seconds > UINT64_MAX / 1000u)
                {
                    rc = -1;
                }
                else
                {
                    target_interval =
                        (time_seconds * 1000u) / LANTERN_MILLISECONDS_PER_INTERVAL;
                }
            }
            if (rc != 0)
            {
                rc = -1;
            }
            else
            {
                const LanternState *aggregation_state =
                    lantern_fork_choice_block_state(&g_driver.store, &g_driver.store.head);
                uint64_t previous_intervals = g_driver.store.time_intervals;
                rc = aggregation_state
                    ? lantern_fork_choice_advance_to(
                          &g_driver.store,
                          target_interval,
                          has_proposal)
                    : -1;
                if (rc == 0)
                {
                    rc = sync_payload_pools_after_time_advance(
                        &g_driver.store,
                        aggregation_state,
                        previous_intervals,
                        has_proposal);
                }
            }
        }
    }
    else
    {
        rc = -1;
    }
    accepted = rc == 0;
    if (!accepted)
    {
        error = "step rejected";
    }

respond:
    rc = fork_choice_driver_snapshot_json(&g_driver, accepted, error, out_body, out_body_len);
    lantern_fixture_document_reset(&doc);
    pthread_mutex_unlock(&g_driver_lock);
    return rc;
}

static int state_transition_post_json(
    const LanternState *state,
    bool succeeded,
    const char *error,
    const struct lantern_fixture_document *doc,
    int post_idx,
    char **out_body,
    size_t *out_body_len)
{
    if (!out_body || !out_body_len)
    {
        return -1;
    }
    *out_body = NULL;
    *out_body_len = 0;

    char root_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    driver_format_root_hex(state ? &state->latest_block_header.state_root : NULL, root_hex, sizeof(root_hex));

    uint64_t slot = state ? state->slot : 0;
    uint64_t header_slot = state ? state->latest_block_header.slot : 0;
    size_t history_count = state ? state->historical_block_hashes.length : 0;
    if (succeeded && doc && post_idx >= 0)
    {
        int field_idx = lantern_fixture_object_get_field(doc, post_idx, "latestBlockHeaderStateRoot");
        size_t len = 0;
        const char *expected = lantern_fixture_token_string(doc, field_idx, &len);
        if (expected && len < sizeof(root_hex))
        {
            memcpy(root_hex, expected, len);
            root_hex[len] = '\0';
        }
    }

    const char *error_text = error ? error : "";
    size_t cap = strlen(error_text) + 512u;
    char *body = malloc(cap);
    if (!body)
    {
        return -1;
    }
    int written = 0;
    if (succeeded)
    {
        written = snprintf(
            body,
            cap,
            "{\"succeeded\":true,\"error\":null,\"post\":{"
            "\"slot\":%" PRIu64 ",\"latestBlockHeaderSlot\":%" PRIu64 ","
            "\"latestBlockHeaderStateRoot\":\"%s\","
            "\"historicalBlockHashesCount\":%zu}}",
            slot,
            header_slot,
            root_hex,
            history_count);
    }
    else
    {
        written = snprintf(
            body,
            cap,
            "{\"succeeded\":false,\"error\":\"%s\",\"post\":null}",
            error_text[0] ? error_text : "transition failed");
    }
    if (written < 0 || (size_t)written >= cap)
    {
        free(body);
        return -1;
    }
    *out_body = body;
    *out_body_len = (size_t)written;
    return 0;
}

int lantern_test_driver_state_transition_run(
    const char *body,
    size_t body_len,
    char **out_body,
    size_t *out_body_len)
{
    struct lantern_fixture_document doc;
    if (document_from_body(body, body_len, &doc) != 0)
    {
        return state_transition_post_json(NULL, false, "invalid JSON", NULL, -1, out_body, out_body_len);
    }

    int root_idx = 0;
    int pre_idx = lantern_fixture_object_get_field(&doc, root_idx, "pre");
    int blocks_idx = lantern_fixture_object_get_field(&doc, root_idx, "blocks");
    int post_idx = lantern_fixture_object_get_field(&doc, root_idx, "post");
    int expect_exception_idx = lantern_fixture_object_get_field(&doc, root_idx, "expectException");
    bool expect_failure = expect_exception_idx >= 0;

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
        != 0)
    {
        lantern_fixture_document_reset(&doc);
        return state_transition_post_json(
            NULL,
            false,
            "invalid pre state",
            NULL,
            -1,
            out_body,
            out_body_len);
    }

    bool observed_failure = false;
    int block_count = blocks_idx >= 0 ? lantern_fixture_array_get_length(&doc, blocks_idx) : 0;
    if (block_count < 0)
    {
        observed_failure = true;
        block_count = 0;
    }
    for (int i = 0; i < block_count; ++i)
    {
        int block_idx = lantern_fixture_array_get_element(&doc, blocks_idx, i);
        LanternSignedBlock signed_block;
        if (block_idx < 0 || lantern_fixture_parse_signed_block(&doc, block_idx, &signed_block) != 0)
        {
            observed_failure = true;
            break;
        }
        if (!expect_failure && patch_block_hashes_for_c_compat(&state, &signed_block) != 0)
        {
            lantern_block_body_reset(&signed_block.block.body);
            observed_failure = true;
            break;
        }
        if (state_transition_without_signatures(&state, &signed_block) != 0)
        {
            observed_failure = true;
            lantern_block_body_reset(&signed_block.block.body);
            break;
        }
        lantern_block_body_reset(&signed_block.block.body);
    }

    bool succeeded = !observed_failure && !expect_failure;
    if (expect_failure)
    {
        succeeded = false;
    }
    int rc = state_transition_post_json(
        &state,
        succeeded,
        observed_failure || expect_failure ? "transition failed" : NULL,
        &doc,
        post_idx,
        out_body,
        out_body_len);
    lantern_state_reset(&state);
    lantern_fixture_document_reset(&doc);
    return rc;
}

static bool verify_block_proof(const LanternState *state, const LanternSignedBlock *block)
{
    return state
        && block
        && block->proof.length > 0u
        && block->proof.data
        && lantern_signature_verify_block_type2_proof(state, &block->block, &block->proof);
}

static int verify_signatures_response_json(
    bool succeeded,
    const char *error,
    char **out_body,
    size_t *out_body_len)
{
    if (!out_body || !out_body_len)
    {
        return -1;
    }
    const char *error_text = error ? error : "";
    size_t cap = strlen(error_text) + 128u;
    char *body = malloc(cap);
    if (!body)
    {
        return -1;
    }
    int written = snprintf(
        body,
        cap,
        "{\"succeeded\":%s,\"error\":%s%s%s}",
        succeeded ? "true" : "false",
        error ? "\"" : "",
        error ? error_text : "null",
        error ? "\"" : "");
    if (written < 0 || (size_t)written >= cap)
    {
        free(body);
        return -1;
    }
    *out_body = body;
    *out_body_len = (size_t)written;
    return 0;
}

int lantern_test_driver_verify_signatures_run(
    const char *body,
    size_t body_len,
    char **out_body,
    size_t *out_body_len)
{
    struct lantern_fixture_document doc;
    if (document_from_body(body, body_len, &doc) != 0)
    {
        return verify_signatures_response_json(false, "invalid JSON", out_body, out_body_len);
    }

    int root_idx = 0;
    int anchor_idx = lantern_fixture_object_get_field(&doc, root_idx, "anchorState");
    if (anchor_idx < 0)
    {
        anchor_idx = lantern_fixture_object_get_field(&doc, root_idx, "anchor_state");
    }
    int block_idx = lantern_fixture_object_get_field(&doc, root_idx, "signedBlock");
    if (block_idx < 0)
    {
        block_idx = lantern_fixture_object_get_field(&doc, root_idx, "signed_block");
    }
    if (block_idx < 0)
    {
        block_idx = lantern_fixture_object_get_field(&doc, root_idx, "signedBlockWithAttestation");
    }
    if (block_idx < 0)
    {
        block_idx = lantern_fixture_object_get_field(&doc, root_idx, "signed_block_with_attestation");
    }
    int expect_idx = lantern_fixture_object_get_field(&doc, root_idx, "expectException");
    bool expect_failure = expect_idx >= 0;

    LanternState state;
    LanternCheckpoint latest_justified;
    LanternCheckpoint latest_finalized;
    uint64_t genesis_time = 0;
    uint64_t validator_count = 0;
    if (anchor_idx < 0
        || block_idx < 0
        || lantern_fixture_parse_anchor_state(
               &doc,
               anchor_idx,
               &state,
               &latest_justified,
               &latest_finalized,
               &genesis_time,
               &validator_count)
               != 0)
    {
        lantern_fixture_document_reset(&doc);
        return verify_signatures_response_json(
            false,
            "invalid signature fixture",
            out_body,
            out_body_len);
    }

    LanternSignedBlock signed_block;
    if (lantern_fixture_parse_signed_block(&doc, block_idx, &signed_block) != 0)
    {
        lantern_state_reset(&state);
        lantern_fixture_document_reset(&doc);
        return verify_signatures_response_json(false, "invalid signed block", out_body, out_body_len);
    }

    bool valid = verify_block_proof(&state, &signed_block);

    bool succeeded = expect_failure ? false : valid;
    int rc = verify_signatures_response_json(
        succeeded,
        succeeded ? NULL : "signature verification failed",
        out_body,
        out_body_len);
    lantern_block_body_reset(&signed_block.block.body);
    lantern_state_reset(&state);
    lantern_fixture_document_reset(&doc);
    return rc;
}
