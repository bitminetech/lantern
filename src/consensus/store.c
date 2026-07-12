#include "lantern/consensus/store.h"

#include <stdlib.h>
#include <string.h>

#include "lantern/consensus/fork_choice.h"

static const size_t LANTERN_AGG_PROOF_CACHE_LIMIT = 4096u;
static const size_t LANTERN_ATTESTATION_SIGNATURE_LIMIT = LANTERN_VALIDATOR_REGISTRY_LIMIT;

static bool signature_is_zero(const LanternSignature *signature) {
    if (!signature) {
        return true;
    }
    for (size_t i = 0; i < LANTERN_SIGNATURE_SIZE; ++i) {
        if (signature->bytes[i] != 0u) {
            return false;
        }
    }
    return true;
}

static void sync_attached_fork_choice(LanternStore *store) {
    if (!store || !store->fork_choice) {
        return;
    }
    store->fork_choice->attestation_store = store;
}

static void detach_attached_fork_choice(LanternStore *store) {
    if (!store || !store->fork_choice) {
        return;
    }
    store->fork_choice->attestation_store = NULL;
}

static bool signature_key_equals(
    const LanternSignatureKey *lhs,
    const LanternSignatureKey *rhs) {
    if (!lhs || !rhs) {
        return false;
    }
    return lhs->validator_index == rhs->validator_index
        && memcmp(lhs->data_root.bytes, rhs->data_root.bytes, LANTERN_ROOT_SIZE) == 0;
}

static bool root_equals(const LanternRoot *lhs, const LanternRoot *rhs) {
    if (!lhs || !rhs) {
        return false;
    }
    return memcmp(lhs->bytes, rhs->bytes, LANTERN_ROOT_SIZE) == 0;
}

static bool root_in_set(
    const LanternRoot *needle,
    const LanternRoot *roots,
    size_t root_count) {
    if (!needle || (!roots && root_count > 0u)) {
        return false;
    }
    for (size_t i = 0; i < root_count; ++i) {
        if (root_equals(needle, &roots[i])) {
            return true;
        }
    }
    return false;
}

static bool aggregated_payload_entry_equals(
    const struct lantern_aggregated_payload_entry *entry,
    const LanternRoot *data_root,
    const LanternAggregatedSignatureProof *proof) {
    if (!entry || !data_root || !proof) {
        return false;
    }
    if (memcmp(entry->data_root.bytes, data_root->bytes, LANTERN_ROOT_SIZE) != 0) {
        return false;
    }
    if (entry->proof.participants.bit_length != proof->participants.bit_length) {
        return false;
    }
    size_t bits = proof->participants.bit_length;
    size_t bytes = (bits + 7u) / 8u;
    if (bytes > 0) {
        if (!entry->proof.participants.bytes || !proof->participants.bytes) {
            return false;
        }
        if (memcmp(entry->proof.participants.bytes, proof->participants.bytes, bytes) != 0) {
            return false;
        }
    }
    if (entry->proof.proof_data.length != proof->proof_data.length) {
        return false;
    }
    if (proof->proof_data.length > 0) {
        if (!entry->proof.proof_data.data || !proof->proof_data.data) {
            return false;
        }
        if (memcmp(entry->proof.proof_data.data, proof->proof_data.data, proof->proof_data.length) != 0) {
            return false;
        }
    }
    return true;
}

static size_t proof_participant_limit(const LanternAggregatedSignatureProof *proof) {
    if (!proof) {
        return 0u;
    }
    size_t limit = proof->participants.bit_length;
    if (limit > LANTERN_VALIDATOR_REGISTRY_LIMIT) {
        limit = LANTERN_VALIDATOR_REGISTRY_LIMIT;
    }
    return limit;
}

static bool proof_has_participant(const LanternAggregatedSignatureProof *proof) {
    if (!proof || !proof->participants.bytes) {
        return false;
    }
    size_t limit = proof_participant_limit(proof);
    for (size_t validator = 0; validator < limit; ++validator) {
        if (lantern_bitlist_get(&proof->participants, validator)) {
            return true;
        }
    }
    return false;
}

static bool proof_participants_subset_of(
    const LanternAggregatedSignatureProof *candidate,
    const LanternAggregatedSignatureProof *cover) {
    if (!candidate || !candidate->participants.bytes || !cover || !cover->participants.bytes) {
        return false;
    }
    size_t limit = proof_participant_limit(candidate);
    bool has_participant = false;
    for (size_t validator = 0; validator < limit; ++validator) {
        if (!lantern_bitlist_get(&candidate->participants, validator)) {
            continue;
        }
        has_participant = true;
        if (!lantern_bitlist_get(&cover->participants, validator)) {
            return false;
        }
    }
    return has_participant;
}

static void attestation_signature_map_init(struct lantern_attestation_signature_map *map) {
    if (!map) {
        return;
    }
    map->entries = NULL;
    map->length = 0;
    map->capacity = 0;
}

static void attestation_signature_map_reset(struct lantern_attestation_signature_map *map) {
    if (!map) {
        return;
    }
    free(map->entries);
    map->entries = NULL;
    map->length = 0;
    map->capacity = 0;
}

static void attestation_signature_map_remove_index(
    struct lantern_attestation_signature_map *map,
    size_t index) {
    if (!map || !map->entries || index >= map->length) {
        return;
    }
    if (index + 1u < map->length) {
        memmove(
            &map->entries[index],
            &map->entries[index + 1u],
            (map->length - index - 1u) * sizeof(*map->entries));
    }
    map->length -= 1u;
}

static int attestation_signature_map_set(
    struct lantern_attestation_signature_map *map,
    const LanternSignatureKey *key,
    const LanternSignature *signature) {
    if (!map || !key || !signature || signature_is_zero(signature)) {
        return -1;
    }
    for (size_t i = 0; i < map->length; ++i) {
        if (!signature_key_equals(&map->entries[i].key, key)) {
            continue;
        }
        map->entries[i].signature = *signature;
        return 0;
    }
    if (map->length >= LANTERN_ATTESTATION_SIGNATURE_LIMIT) {
        attestation_signature_map_remove_index(map, 0u);
    }
    if (map->length >= map->capacity) {
        size_t desired = map->capacity == 0 ? 8u : map->capacity * 2u;
        if (desired > LANTERN_ATTESTATION_SIGNATURE_LIMIT) {
            desired = LANTERN_ATTESTATION_SIGNATURE_LIMIT;
        }
        if (desired <= map->capacity) {
            return -1;
        }
        struct lantern_attestation_signature_entry *entries =
            realloc(map->entries, desired * sizeof(*entries));
        if (!entries) {
            return -1;
        }
        map->entries = entries;
        map->capacity = desired;
    }
    map->entries[map->length].key = *key;
    map->entries[map->length].signature = *signature;
    map->length += 1u;
    return 0;
}

static int attestation_signature_map_get(
    const struct lantern_attestation_signature_map *map,
    const LanternSignatureKey *key,
    LanternSignature *out_signature) {
    if (!map || !key || !out_signature) {
        return -1;
    }
    for (size_t i = 0; i < map->length; ++i) {
        if (!signature_key_equals(&map->entries[i].key, key)) {
            continue;
        }
        *out_signature = map->entries[i].signature;
        return 0;
    }
    return -1;
}

static void aggregated_payload_pool_init(struct lantern_aggregated_payload_pool *cache) {
    if (!cache) {
        return;
    }
    cache->entries = NULL;
    cache->length = 0;
    cache->capacity = 0;
}

static void aggregated_payload_pool_reset(struct lantern_aggregated_payload_pool *cache) {
    if (!cache) {
        return;
    }
    if (cache->entries) {
        for (size_t i = 0; i < cache->length; ++i) {
            lantern_aggregated_signature_proof_reset(&cache->entries[i].proof);
        }
    }
    free(cache->entries);
    cache->entries = NULL;
    cache->length = 0;
    cache->capacity = 0;
}

static void aggregated_payload_pool_remove_index(
    struct lantern_aggregated_payload_pool *cache,
    size_t index) {
    if (!cache || !cache->entries || index >= cache->length) {
        return;
    }
    lantern_aggregated_signature_proof_reset(&cache->entries[index].proof);
    if (index + 1u < cache->length) {
        memmove(
            &cache->entries[index],
            &cache->entries[index + 1u],
            (cache->length - index - 1u) * sizeof(*cache->entries));
    }
    cache->length -= 1u;
}

static void aggregated_payload_pool_mark_participants_covered(
    const struct lantern_aggregated_payload_pool *cache,
    const LanternRoot *data_root,
    bool covered[LANTERN_VALIDATOR_REGISTRY_LIMIT]) {
    if (!cache || !data_root || !covered) {
        return;
    }
    for (size_t i = 0; i < cache->length; ++i) {
        if (!root_equals(&cache->entries[i].data_root, data_root)) {
            continue;
        }
        const struct lantern_bitlist *participants = &cache->entries[i].proof.participants;
        if (!participants->bytes) {
            continue;
        }
        size_t limit = participants->bit_length;
        if (limit > LANTERN_VALIDATOR_REGISTRY_LIMIT) {
            limit = LANTERN_VALIDATOR_REGISTRY_LIMIT;
        }
        for (size_t validator = 0; validator < limit; ++validator) {
            if (lantern_bitlist_get(participants, validator)) {
                covered[validator] = true;
            }
        }
    }
}

static bool bitlist_participants_covered(
    const struct lantern_bitlist *participants,
    const bool covered[LANTERN_VALIDATOR_REGISTRY_LIMIT]) {
    if (!participants || !participants->bytes || !covered) {
        return false;
    }
    size_t limit = participants->bit_length;
    if (limit > LANTERN_VALIDATOR_REGISTRY_LIMIT) {
        limit = LANTERN_VALIDATOR_REGISTRY_LIMIT;
    }
    bool has_participant = false;
    for (size_t validator = 0; validator < limit; ++validator) {
        if (!lantern_bitlist_get(participants, validator)) {
            continue;
        }
        has_participant = true;
        if (!covered[validator]) {
            return false;
        }
    }
    return has_participant;
}

static bool aggregated_payload_pool_covers_proof_participants(
    const struct lantern_aggregated_payload_pool *cache,
    const LanternRoot *data_root,
    const LanternAggregatedSignatureProof *proof) {
    bool covered[LANTERN_VALIDATOR_REGISTRY_LIMIT] = {false};
    if (!proof) {
        return false;
    }
    aggregated_payload_pool_mark_participants_covered(cache, data_root, covered);
    return bitlist_participants_covered(&proof->participants, covered);
}

bool lantern_store_aggregated_payloads_cover_participants(
    const LanternStore *store,
    const LanternRoot *data_root,
    const struct lantern_bitlist *participants) {
    bool covered[LANTERN_VALIDATOR_REGISTRY_LIMIT] = {false};
    if (!store || !data_root || !participants
        || participants->bit_length > LANTERN_VALIDATOR_REGISTRY_LIMIT) {
        return false;
    }
    aggregated_payload_pool_mark_participants_covered(
        &store->new_aggregated_payloads,
        data_root,
        covered);
    aggregated_payload_pool_mark_participants_covered(
        &store->known_aggregated_payloads,
        data_root,
        covered);
    return bitlist_participants_covered(participants, covered);
}

static void aggregated_payload_pool_prune_subsets_of_entry(
    struct lantern_aggregated_payload_pool *cache,
    size_t cover_index) {
    if (!cache || !cache->entries || cover_index >= cache->length) {
        return;
    }

    LanternRoot data_root = cache->entries[cover_index].data_root;
    size_t index = 0u;
    while (index < cache->length) {
        if (index == cover_index) {
            index += 1u;
            continue;
        }
        if (root_equals(&cache->entries[index].data_root, &data_root)
            && proof_participants_subset_of(
                &cache->entries[index].proof,
                &cache->entries[cover_index].proof)) {
            aggregated_payload_pool_remove_index(cache, index);
            if (index < cover_index) {
                cover_index -= 1u;
            }
            continue;
        }
        index += 1u;
    }
}

static int aggregated_payload_pool_add(
    struct lantern_aggregated_payload_pool *cache,
    const LanternRoot *data_root,
    const LanternAggregatedSignatureProof *proof) {
    if (!cache || !data_root || !proof) {
        return -1;
    }
    if (!proof_has_participant(proof) || proof->proof_data.length == 0) {
        return -1;
    }
    for (size_t i = 0; i < cache->length; ++i) {
        if (!aggregated_payload_entry_equals(&cache->entries[i], data_root, proof)) {
            continue;
        }
        return 0;
    }
    if (aggregated_payload_pool_covers_proof_participants(cache, data_root, proof)) {
        return 0;
    }
    if (cache->length >= LANTERN_AGG_PROOF_CACHE_LIMIT) {
        aggregated_payload_pool_remove_index(cache, 0u);
    }
    if (cache->length >= cache->capacity) {
        size_t desired = cache->capacity == 0 ? 8u : cache->capacity * 2u;
        if (desired > LANTERN_AGG_PROOF_CACHE_LIMIT) {
            desired = LANTERN_AGG_PROOF_CACHE_LIMIT;
        }
        if (desired <= cache->capacity) {
            return -1;
        }
        struct lantern_aggregated_payload_entry *entries =
            realloc(cache->entries, desired * sizeof(*entries));
        if (!entries) {
            return -1;
        }
        cache->entries = entries;
        cache->capacity = desired;
    }
    struct lantern_aggregated_payload_entry *entry = &cache->entries[cache->length];
    entry->data_root = *data_root;
    lantern_aggregated_signature_proof_init(&entry->proof);
    if (lantern_aggregated_signature_proof_copy(&entry->proof, proof) != 0) {
        lantern_aggregated_signature_proof_reset(&entry->proof);
        return -1;
    }
    cache->length += 1u;
    aggregated_payload_pool_prune_subsets_of_entry(cache, cache->length - 1u);
    return 0;
}

static void attestation_data_by_root_init(struct lantern_attestation_data_by_root *cache) {
    if (!cache) {
        return;
    }
    cache->entries = NULL;
    cache->length = 0;
    cache->capacity = 0;
}

static void attestation_data_by_root_reset(struct lantern_attestation_data_by_root *cache) {
    if (!cache) {
        return;
    }
    free(cache->entries);
    cache->entries = NULL;
    cache->length = 0;
    cache->capacity = 0;
}

static void attestation_data_by_root_remove_index(
    struct lantern_attestation_data_by_root *cache,
    size_t index) {
    if (!cache || !cache->entries || index >= cache->length) {
        return;
    }
    if (index + 1u < cache->length) {
        memmove(
            &cache->entries[index],
            &cache->entries[index + 1u],
            (cache->length - index - 1u) * sizeof(*cache->entries));
    }
    cache->length -= 1u;
}

static void attestation_data_by_root_shrink_to_fit(
    struct lantern_attestation_data_by_root *cache) {
    if (!cache) {
        return;
    }
    if (cache->length == cache->capacity) {
        return;
    }
    if (cache->length == 0u) {
        free(cache->entries);
        cache->entries = NULL;
        cache->capacity = 0u;
        return;
    }

    struct lantern_attestation_data_by_root_entry *entries =
        realloc(cache->entries, cache->length * sizeof(*entries));
    if (!entries) {
        return;
    }
    cache->entries = entries;
    cache->capacity = cache->length;
}

static int attestation_data_by_root_add(
    struct lantern_attestation_data_by_root *cache,
    const LanternRoot *data_root,
    const LanternAttestationData *data) {
    if (!cache || !data_root || !data) {
        return -1;
    }
    for (size_t i = 0; i < cache->length; ++i) {
        if (memcmp(cache->entries[i].data_root.bytes, data_root->bytes, LANTERN_ROOT_SIZE) == 0) {
            cache->entries[i].data = *data;
            return 0;
        }
    }
    if (cache->length >= cache->capacity) {
        size_t desired = cache->capacity == 0 ? 8u : cache->capacity * 2u;
        if (desired <= cache->capacity) {
            return -1;
        }
        struct lantern_attestation_data_by_root_entry *entries =
            realloc(cache->entries, desired * sizeof(*entries));
        if (!entries) {
            return -1;
        }
        cache->entries = entries;
        cache->capacity = desired;
    }
    cache->entries[cache->length].data_root = *data_root;
    cache->entries[cache->length].data = *data;
    cache->length += 1u;
    return 0;
}

void lantern_store_init(LanternStore *store) {
    if (!store) {
        return;
    }
    memset(store, 0, sizeof(*store));
    attestation_signature_map_init(&store->attestation_signatures);
    aggregated_payload_pool_init(&store->new_aggregated_payloads);
    aggregated_payload_pool_init(&store->known_aggregated_payloads);
    attestation_data_by_root_init(&store->attestation_data_by_root);
}

void lantern_store_reset(LanternStore *store) {
    if (!store) {
        return;
    }
    detach_attached_fork_choice(store);
    attestation_signature_map_reset(&store->attestation_signatures);
    aggregated_payload_pool_reset(&store->new_aggregated_payloads);
    aggregated_payload_pool_reset(&store->known_aggregated_payloads);
    attestation_data_by_root_reset(&store->attestation_data_by_root);
    store->fork_choice = NULL;
}

void lantern_store_attach_fork_choice(LanternStore *store, struct lantern_fork_choice *fork_choice) {
    if (!store) {
        return;
    }
    detach_attached_fork_choice(store);
    store->fork_choice = fork_choice;
    sync_attached_fork_choice(store);
}

int lantern_store_set_attestation_signature(
    LanternStore *store,
    const LanternSignatureKey *key,
    const LanternAttestationData *data,
    const LanternSignature *signature) {
    if (!store || !key || !data) {
        return -1;
    }
    (void)attestation_data_by_root_add(
        &store->attestation_data_by_root,
        &key->data_root,
        data);
    if (!signature || signature_is_zero(signature)) {
        return 0;
    }
    if (attestation_signature_map_set(
            &store->attestation_signatures,
            key,
            signature)
        != 0) {
        return -1;
    }
    return 0;
}

int lantern_store_get_attestation_signature(
    const LanternStore *store,
    const LanternSignatureKey *key,
    LanternSignature *out_signature) {
    if (!store) {
        return -1;
    }
    return attestation_signature_map_get(&store->attestation_signatures, key, out_signature);
}

size_t lantern_store_remove_attestation_signatures_for_data_root(
    LanternStore *store,
    const LanternRoot *data_root) {
    if (!store || !data_root) {
        return 0u;
    }

    size_t removed = 0u;
    size_t index = 0u;
    while (index < store->attestation_signatures.length) {
        if (root_equals(&store->attestation_signatures.entries[index].key.data_root, data_root)) {
            attestation_signature_map_remove_index(&store->attestation_signatures, index);
            removed += 1u;
            continue;
        }
        index += 1u;
    }
    return removed;
}

static int lantern_store_add_aggregated_payload(
    LanternStore *store,
    struct lantern_aggregated_payload_pool *pool,
    const LanternRoot *data_root,
    const LanternAttestationData *data,
    const LanternAggregatedSignatureProof *proof) {
    if (!store || !pool || !data_root || !proof) {
        return -1;
    }
    if (aggregated_payload_pool_add(pool, data_root, proof) != 0) {
        return -1;
    }
    if (data) {
        (void)attestation_data_by_root_add(&store->attestation_data_by_root, data_root, data);
    }
    return 0;
}

int lantern_store_add_new_aggregated_payload(
    LanternStore *store,
    const LanternRoot *data_root,
    const LanternAttestationData *data,
    const LanternAggregatedSignatureProof *proof) {
    if (!store) {
        return -1;
    }
    return lantern_store_add_aggregated_payload(
        store,
        &store->new_aggregated_payloads,
        data_root,
        data,
        proof);
}

int lantern_store_add_known_aggregated_payload(
    LanternStore *store,
    const LanternRoot *data_root,
    const LanternAttestationData *data,
    const LanternAggregatedSignatureProof *proof) {
    if (!store) {
        return -1;
    }
    return lantern_store_add_aggregated_payload(
        store,
        &store->known_aggregated_payloads,
        data_root,
        data,
        proof);
}

int lantern_store_add_attestation_data(
    LanternStore *store,
    const LanternRoot *data_root,
    const LanternAttestationData *data) {
    if (!store) {
        return -1;
    }
    return attestation_data_by_root_add(&store->attestation_data_by_root, data_root, data);
}

void lantern_store_clear_new_aggregated_payloads(LanternStore *store) {
    if (!store) {
        return;
    }
    aggregated_payload_pool_reset(&store->new_aggregated_payloads);
    aggregated_payload_pool_init(&store->new_aggregated_payloads);
}

static bool aggregated_payload_entries_equal(
    const struct lantern_aggregated_payload_entry *a,
    const struct lantern_aggregated_payload_entry *b) {
    if (!a || !b) {
        return false;
    }
    if (memcmp(a->data_root.bytes, b->data_root.bytes, sizeof(a->data_root.bytes)) != 0) {
        return false;
    }
    if (a->proof.participants.bit_length != b->proof.participants.bit_length) {
        return false;
    }
    size_t participant_bytes = (a->proof.participants.bit_length + 7u) / 8u;
    if (participant_bytes > 0u
        && (!a->proof.participants.bytes
            || !b->proof.participants.bytes
            || memcmp(a->proof.participants.bytes, b->proof.participants.bytes, participant_bytes) != 0)) {
        return false;
    }
    if (a->proof.proof_data.length != b->proof.proof_data.length) {
        return false;
    }
    if (a->proof.proof_data.length > 0u
        && (!a->proof.proof_data.data
            || !b->proof.proof_data.data
            || memcmp(a->proof.proof_data.data, b->proof.proof_data.data, a->proof.proof_data.length) != 0)) {
        return false;
    }
    return true;
}

size_t lantern_store_remove_new_aggregated_payloads_matching(
    LanternStore *store,
    const struct lantern_aggregated_payload_pool *snapshot) {
    if (!store || !snapshot || snapshot->length == 0u) {
        return 0u;
    }
    struct lantern_aggregated_payload_pool *pool = &store->new_aggregated_payloads;
    size_t removed = 0u;
    size_t write = 0u;
    for (size_t i = 0; i < pool->length; ++i) {
        bool matched = false;
        for (size_t j = 0; j < snapshot->length; ++j) {
            if (aggregated_payload_entries_equal(&pool->entries[i], &snapshot->entries[j])) {
                matched = true;
                break;
            }
        }
        if (matched) {
            lantern_aggregated_signature_proof_reset(&pool->entries[i].proof);
            removed += 1u;
            continue;
        }
        if (write != i) {
            pool->entries[write] = pool->entries[i];
        }
        write += 1u;
    }
    pool->length = write;
    return removed;
}

size_t lantern_store_promote_new_aggregated_payloads(LanternStore *store) {
    if (!store) {
        return 0u;
    }
    size_t moved = 0u;
    size_t index = 0u;
    while (index < store->new_aggregated_payloads.length) {
        const struct lantern_aggregated_payload_entry *entry =
            &store->new_aggregated_payloads.entries[index];
        int add_rc = lantern_store_add_known_aggregated_payload(
            store,
            &entry->data_root,
            NULL,
            &entry->proof);
        if (add_rc != 0) {
            break;
        }
        aggregated_payload_pool_remove_index(&store->new_aggregated_payloads, index);
        moved += 1u;
    }
    return moved;
}

size_t lantern_store_prune_finalized_attestation_material(
    LanternStore *store,
    uint64_t finalized_slot) {
    if (!store) {
        return 0u;
    }

    struct lantern_attestation_data_by_root *data_cache = &store->attestation_data_by_root;
    size_t stale_root_count = 0u;
    for (size_t i = 0; i < data_cache->length; ++i) {
        if (data_cache->entries[i].data.target.slot <= finalized_slot) {
            stale_root_count += 1u;
        }
    }
    if (stale_root_count == 0u) {
        return 0u;
    }

    LanternRoot *stale_roots = malloc(stale_root_count * sizeof(*stale_roots));
    if (!stale_roots) {
        return 0u;
    }

    size_t stale_root_index = 0u;
    size_t data_index = 0u;
    while (data_index < data_cache->length) {
        if (data_cache->entries[data_index].data.target.slot <= finalized_slot) {
            stale_roots[stale_root_index] = data_cache->entries[data_index].data_root;
            stale_root_index += 1u;
            attestation_data_by_root_remove_index(data_cache, data_index);
            continue;
        }
        data_index += 1u;
    }
    attestation_data_by_root_shrink_to_fit(data_cache);

    size_t signature_index = 0u;
    while (signature_index < store->attestation_signatures.length) {
        if (root_in_set(
                &store->attestation_signatures.entries[signature_index].key.data_root,
                stale_roots,
                stale_root_count)) {
            attestation_signature_map_remove_index(&store->attestation_signatures, signature_index);
            continue;
        }
        signature_index += 1u;
    }

    size_t proof_index = 0u;
    while (proof_index < store->new_aggregated_payloads.length) {
        if (root_in_set(
                &store->new_aggregated_payloads.entries[proof_index].data_root,
                stale_roots,
                stale_root_count)) {
            aggregated_payload_pool_remove_index(&store->new_aggregated_payloads, proof_index);
            continue;
        }
        proof_index += 1u;
    }

    proof_index = 0u;
    while (proof_index < store->known_aggregated_payloads.length) {
        if (root_in_set(
                &store->known_aggregated_payloads.entries[proof_index].data_root,
                stale_roots,
                stale_root_count)) {
            aggregated_payload_pool_remove_index(&store->known_aggregated_payloads, proof_index);
            continue;
        }
        proof_index += 1u;
    }

    free(stale_roots);
    return stale_root_count;
}

int lantern_store_get_attestation_data(
    const LanternStore *store,
    const LanternRoot *data_root,
    LanternAttestationData *out_data) {
    if (!store || !data_root || !out_data) {
        return -1;
    }
    const struct lantern_attestation_data_by_root *cache = &store->attestation_data_by_root;
    for (size_t i = 0; i < cache->length; ++i) {
        if (memcmp(cache->entries[i].data_root.bytes, data_root->bytes, LANTERN_ROOT_SIZE) == 0) {
            *out_data = cache->entries[i].data;
            return 0;
        }
    }
    return -1;
}
