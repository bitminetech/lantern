#include "lantern/consensus/store.h"

#include <stdlib.h>
#include <string.h>

#include "lantern/consensus/fork_choice.h"
#include "lantern/consensus/signature.h"

static const size_t LANTERN_AGG_PROOF_CACHE_LIMIT = 4096u;
static const size_t LANTERN_ATTESTATION_SIGNATURE_LIMIT = LANTERN_VALIDATOR_REGISTRY_LIMIT;

static bool signature_key_equals(
    const LanternSignatureKey *lhs,
    const LanternSignatureKey *rhs) {
    if (!lhs || !rhs) {
        return false;
    }
    return lhs->validator_index == rhs->validator_index
        && memcmp(lhs->data_root.bytes, rhs->data_root.bytes, LANTERN_ROOT_SIZE) == 0;
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
    const LanternAttestationData *data,
    const LanternSignature *signature) {
    if (!map || !key || !data || !signature || lantern_signature_is_zero(signature)) {
        return -1;
    }
    for (size_t i = 0; i < map->length; ++i) {
        if (!signature_key_equals(&map->entries[i].key, key)) {
            continue;
        }
        map->entries[i].data = *data;
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
    map->entries[map->length].data = *data;
    map->entries[map->length].signature = *signature;
    map->length += 1u;
    return 0;
}

void lantern_aggregated_payload_pool_reset(struct lantern_aggregated_payload_pool *pool) {
    if (!pool) {
        return;
    }
    if (pool->entries) {
        for (size_t i = 0; i < pool->length; ++i) {
            lantern_aggregated_signature_proof_reset(&pool->entries[i].proof);
        }
    }
    free(pool->entries);
    *pool = (struct lantern_aggregated_payload_pool){0};
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
        if (!lantern_root_equal(&cache->entries[i].data_root, data_root)) {
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
        if (lantern_root_equal(&cache->entries[index].data_root, &data_root)
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

int lantern_aggregated_payload_pool_add(
    struct lantern_aggregated_payload_pool *pool,
    const LanternRoot *data_root,
    const LanternAttestationData *data,
    const LanternAggregatedSignatureProof *proof) {
    if (!pool || !data_root || !data || !proof) {
        return -1;
    }
    if (!proof_has_participant(proof) || proof->proof_data.length == 0) {
        return -1;
    }
    for (size_t i = 0; i < pool->length; ++i) {
        if (!aggregated_payload_entry_equals(&pool->entries[i], data_root, proof)) {
            continue;
        }
        pool->entries[i].data = *data;
        return 0;
    }
    if (aggregated_payload_pool_covers_proof_participants(pool, data_root, proof)) {
        return 0;
    }
    if (pool->length >= LANTERN_AGG_PROOF_CACHE_LIMIT) {
        aggregated_payload_pool_remove_index(pool, 0u);
    }
    if (pool->length >= pool->capacity) {
        size_t desired = pool->capacity == 0 ? 8u : pool->capacity * 2u;
        if (desired > LANTERN_AGG_PROOF_CACHE_LIMIT) {
            desired = LANTERN_AGG_PROOF_CACHE_LIMIT;
        }
        if (desired <= pool->capacity) {
            return -1;
        }
        struct lantern_aggregated_payload_entry *entries =
            realloc(pool->entries, desired * sizeof(*entries));
        if (!entries) {
            return -1;
        }
        pool->entries = entries;
        pool->capacity = desired;
    }
    struct lantern_aggregated_payload_entry *entry = &pool->entries[pool->length];
    entry->data_root = *data_root;
    entry->data = *data;
    lantern_aggregated_signature_proof_init(&entry->proof);
    if (lantern_aggregated_signature_proof_copy(&entry->proof, proof) != 0) {
        lantern_aggregated_signature_proof_reset(&entry->proof);
        return -1;
    }
    pool->length += 1u;
    aggregated_payload_pool_prune_subsets_of_entry(pool, pool->length - 1u);
    return 0;
}

void lantern_store_init(LanternStore *store) {
    if (!store) {
        return;
    }
    memset(store, 0, sizeof(*store));
    atomic_init(&store->checkpoint_snapshot.sequence, 0u);
    atomic_init(&store->checkpoint_snapshot.justified_slot, 0u);
    atomic_init(&store->checkpoint_snapshot.finalized_slot, 0u);
    for (size_t i = 0; i < LANTERN_ROOT_SIZE; ++i) {
        atomic_init(&store->checkpoint_snapshot.justified_root[i], 0u);
        atomic_init(&store->checkpoint_snapshot.finalized_root[i], 0u);
    }
}

void lantern_store_reset(LanternStore *store) {
    if (!store) {
        return;
    }
    lantern_fork_choice_reset(store);
    attestation_signature_map_reset(&store->attestation_signatures);
    lantern_aggregated_payload_pool_reset(&store->new_aggregated_payloads);
    lantern_aggregated_payload_pool_reset(&store->known_aggregated_payloads);
}

int lantern_store_set_attestation_signature(
    LanternStore *store,
    const LanternSignatureKey *key,
    const LanternAttestationData *data,
    const LanternSignature *signature) {
    if (!store || !key || !data) {
        return -1;
    }
    if (!signature || lantern_signature_is_zero(signature)) {
        return 0;
    }
    if (attestation_signature_map_set(
            &store->attestation_signatures,
            key,
            data,
            signature)
        != 0) {
        return -1;
    }
    return 0;
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
        if (lantern_root_equal(
                &store->attestation_signatures.entries[index].key.data_root,
                data_root)) {
            attestation_signature_map_remove_index(&store->attestation_signatures, index);
            removed += 1u;
            continue;
        }
        index += 1u;
    }
    return removed;
}

int lantern_store_add_new_aggregated_payload(
    LanternStore *store,
    const LanternRoot *data_root,
    const LanternAttestationData *data,
    const LanternAggregatedSignatureProof *proof) {
    if (!store) {
        return -1;
    }
    return lantern_aggregated_payload_pool_add(
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
    return lantern_aggregated_payload_pool_add(
        &store->known_aggregated_payloads,
        data_root,
        data,
        proof);
}

void lantern_store_clear_new_aggregated_payloads(LanternStore *store) {
    if (!store) {
        return;
    }
    lantern_aggregated_payload_pool_reset(&store->new_aggregated_payloads);
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
            if (aggregated_payload_entry_equals(
                    &pool->entries[i],
                    &snapshot->entries[j].data_root,
                    &snapshot->entries[j].proof)) {
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
            &entry->data,
            &entry->proof);
        if (add_rc != 0) {
            break;
        }
        aggregated_payload_pool_remove_index(&store->new_aggregated_payloads, index);
        moved += 1u;
    }
    return moved;
}

static bool signature_root_seen_before(
    const LanternStore *store,
    const LanternRoot *root,
    size_t end) {
    for (size_t i = 0u; i < end; ++i) {
        if (lantern_root_equal(&store->attestation_signatures.entries[i].key.data_root, root)) {
            return true;
        }
    }
    return false;
}

static bool payload_root_seen_before(
    const struct lantern_aggregated_payload_pool *pool,
    const LanternRoot *root,
    size_t end) {
    for (size_t i = 0u; i < end; ++i) {
        if (lantern_root_equal(&pool->entries[i].data_root, root)) {
            return true;
        }
    }
    return false;
}

static size_t stale_attestation_root_count(
    const LanternStore *store,
    uint64_t finalized_slot) {
    size_t count = 0u;
    for (size_t i = 0u; i < store->attestation_signatures.length; ++i) {
        const struct lantern_attestation_signature_entry *entry =
            &store->attestation_signatures.entries[i];
        if (entry->data.target.slot <= finalized_slot
            && !signature_root_seen_before(store, &entry->key.data_root, i)) {
            count += 1u;
        }
    }
    const struct lantern_aggregated_payload_pool *pools[] = {
        &store->new_aggregated_payloads,
        &store->known_aggregated_payloads,
    };
    for (size_t pool_index = 0u; pool_index < 2u; ++pool_index) {
        const struct lantern_aggregated_payload_pool *pool = pools[pool_index];
        for (size_t i = 0u; i < pool->length; ++i) {
            const struct lantern_aggregated_payload_entry *entry = &pool->entries[i];
            bool seen = signature_root_seen_before(
                store,
                &entry->data_root,
                store->attestation_signatures.length);
            for (size_t previous = 0u; previous <= pool_index && !seen; ++previous) {
                size_t end = previous == pool_index ? i : pools[previous]->length;
                seen = payload_root_seen_before(pools[previous], &entry->data_root, end);
            }
            if (entry->data.target.slot <= finalized_slot && !seen) {
                count += 1u;
            }
        }
    }
    return count;
}

size_t lantern_store_prune_finalized_attestation_material(
    LanternStore *store,
    uint64_t finalized_slot) {
    if (!store) {
        return 0u;
    }
    size_t stale_roots = stale_attestation_root_count(store, finalized_slot);
    size_t index = 0u;
    while (index < store->attestation_signatures.length) {
        if (store->attestation_signatures.entries[index].data.target.slot <= finalized_slot) {
            attestation_signature_map_remove_index(&store->attestation_signatures, index);
        } else {
            index += 1u;
        }
    }
    struct lantern_aggregated_payload_pool *pools[] = {
        &store->new_aggregated_payloads,
        &store->known_aggregated_payloads,
    };
    for (size_t pool_index = 0u; pool_index < 2u; ++pool_index) {
        index = 0u;
        while (index < pools[pool_index]->length) {
            if (pools[pool_index]->entries[index].data.target.slot <= finalized_slot) {
                aggregated_payload_pool_remove_index(pools[pool_index], index);
            } else {
                index += 1u;
            }
        }
    }
    return stale_roots;
}
