#include "lantern/consensus/store.h"

#include <stdlib.h>
#include <string.h>

#include "lantern/consensus/fork_choice.h"

static const size_t LANTERN_AGG_PROOF_CACHE_LIMIT = 4096u;
static const size_t LANTERN_GOSSIP_SIGNATURE_LIMIT = LANTERN_VALIDATOR_REGISTRY_LIMIT;

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

static void lantern_vote_record_reset(struct lantern_vote_record *record) {
    if (!record) {
        return;
    }
    memset(record, 0, sizeof(*record));
}

static void fork_choice_votes_reset(struct lantern_fork_choice_vote_entry *entries, size_t count) {
    if (!entries) {
        return;
    }
    for (size_t i = 0; i < count; ++i) {
        entries[i].has_checkpoint = false;
        memset(&entries[i].checkpoint, 0, sizeof(entries[i].checkpoint));
    }
}

static void sync_attached_fork_choice(LanternStore *store) {
    if (!store || !store->fork_choice) {
        return;
    }
    store->fork_choice->known_votes = store->known_votes;
    store->fork_choice->new_votes = store->new_votes;
    store->fork_choice->validator_count = store->fork_choice_vote_count;
    store->fork_choice->new_aggregated_payloads = &store->new_aggregated_payloads;
    store->fork_choice->known_aggregated_payloads = &store->known_aggregated_payloads;
    store->fork_choice->attestation_data_by_root = &store->attestation_data_by_root;
}

static void detach_attached_fork_choice(LanternStore *store) {
    if (!store || !store->fork_choice) {
        return;
    }
    store->fork_choice->known_votes = NULL;
    store->fork_choice->new_votes = NULL;
    store->fork_choice->validator_count = 0;
    store->fork_choice->new_aggregated_payloads = NULL;
    store->fork_choice->known_aggregated_payloads = NULL;
    store->fork_choice->attestation_data_by_root = NULL;
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

static void gossip_signature_map_init(struct lantern_gossip_signature_map *map) {
    if (!map) {
        return;
    }
    map->entries = NULL;
    map->length = 0;
    map->capacity = 0;
}

static void gossip_signature_map_reset(struct lantern_gossip_signature_map *map) {
    if (!map) {
        return;
    }
    free(map->entries);
    map->entries = NULL;
    map->length = 0;
    map->capacity = 0;
}

static void gossip_signature_map_remove_index(
    struct lantern_gossip_signature_map *map,
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

static int gossip_signature_map_set(
    struct lantern_gossip_signature_map *map,
    const LanternSignatureKey *key,
    const LanternSignature *signature,
    uint64_t target_slot) {
    if (!map || !key || !signature || signature_is_zero(signature)) {
        return -1;
    }
    for (size_t i = 0; i < map->length; ++i) {
        if (!signature_key_equals(&map->entries[i].key, key)) {
            continue;
        }
        map->entries[i].signature = *signature;
        map->entries[i].target_slot = target_slot;
        return 0;
    }
    if (map->length >= LANTERN_GOSSIP_SIGNATURE_LIMIT) {
        gossip_signature_map_remove_index(map, 0u);
    }
    if (map->length >= map->capacity) {
        size_t desired = map->capacity == 0 ? 8u : map->capacity * 2u;
        if (desired > LANTERN_GOSSIP_SIGNATURE_LIMIT) {
            desired = LANTERN_GOSSIP_SIGNATURE_LIMIT;
        }
        if (desired <= map->capacity) {
            return -1;
        }
        struct lantern_gossip_signature_entry *entries =
            realloc(map->entries, desired * sizeof(*entries));
        if (!entries) {
            return -1;
        }
        map->entries = entries;
        map->capacity = desired;
    }
    map->entries[map->length].key = *key;
    map->entries[map->length].signature = *signature;
    map->entries[map->length].target_slot = target_slot;
    map->length += 1u;
    return 0;
}

static int gossip_signature_map_get(
    const struct lantern_gossip_signature_map *map,
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

static int aggregated_payload_pool_add(
    struct lantern_aggregated_payload_pool *cache,
    const LanternRoot *data_root,
    const LanternAggregatedSignatureProof *proof,
    uint64_t target_slot) {
    if (!cache || !data_root || !proof) {
        return -1;
    }
    if (proof->participants.bit_length == 0 || proof->proof_data.length == 0) {
        return -1;
    }
    for (size_t i = 0; i < cache->length; ++i) {
        if (!aggregated_payload_entry_equals(&cache->entries[i], data_root, proof)) {
            continue;
        }
        cache->entries[i].target_slot = target_slot;
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
    entry->target_slot = target_slot;
    cache->length += 1u;
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

static int attestation_data_by_root_add(
    struct lantern_attestation_data_by_root *cache,
    const LanternRoot *data_root,
    const LanternAttestationData *data,
    uint64_t target_slot) {
    if (!cache || !data_root || !data) {
        return -1;
    }
    for (size_t i = 0; i < cache->length; ++i) {
        if (memcmp(cache->entries[i].data_root.bytes, data_root->bytes, LANTERN_ROOT_SIZE) == 0) {
            cache->entries[i].data = *data;
            cache->entries[i].target_slot = target_slot;
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
    cache->entries[cache->length].target_slot = target_slot;
    cache->length += 1u;
    return 0;
}

void lantern_store_init(LanternStore *store) {
    if (!store) {
        return;
    }
    memset(store, 0, sizeof(*store));
    gossip_signature_map_init(&store->gossip_signatures);
    aggregated_payload_pool_init(&store->new_aggregated_payloads);
    aggregated_payload_pool_init(&store->known_aggregated_payloads);
    attestation_data_by_root_init(&store->attestation_data_by_root);
}

void lantern_store_reset(LanternStore *store) {
    if (!store) {
        return;
    }
    detach_attached_fork_choice(store);
    free(store->validator_votes);
    store->validator_votes = NULL;
    store->validator_votes_len = 0;
    free(store->known_votes);
    store->known_votes = NULL;
    free(store->new_votes);
    store->new_votes = NULL;
    store->fork_choice_vote_count = 0;
    gossip_signature_map_reset(&store->gossip_signatures);
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

int lantern_store_prepare_validator_votes(LanternStore *store, uint64_t validator_count) {
    if (!store || validator_count == 0) {
        return -1;
    }
    if (validator_count > (uint64_t)LANTERN_VALIDATOR_REGISTRY_LIMIT || validator_count > SIZE_MAX) {
        return -1;
    }
    size_t count = (size_t)validator_count;
    if (store->validator_votes && store->validator_votes_len != count) {
        free(store->validator_votes);
        store->validator_votes = NULL;
        store->validator_votes_len = 0;
    }
    if (!store->validator_votes) {
        struct lantern_vote_record *records = calloc(count, sizeof(*records));
        if (!records) {
            return -1;
        }
        store->validator_votes = records;
        store->validator_votes_len = count;
    } else {
        for (size_t i = 0; i < count; ++i) {
            lantern_vote_record_reset(&store->validator_votes[i]);
        }
    }
    return 0;
}

int lantern_store_clone_validator_votes(const LanternStore *source, LanternStore *dest) {
    if (!dest) {
        return -1;
    }
    if (!source || !source->validator_votes || source->validator_votes_len == 0) {
        return 0;
    }
    if (lantern_store_prepare_validator_votes(dest, (uint64_t)source->validator_votes_len) != 0) {
        return -1;
    }
    memcpy(
        dest->validator_votes,
        source->validator_votes,
        source->validator_votes_len * sizeof(*source->validator_votes));
    return 0;
}

size_t lantern_store_validator_capacity(const LanternStore *store) {
    if (!store || !store->validator_votes) {
        return 0;
    }
    return store->validator_votes_len;
}

bool lantern_store_validator_has_vote(const LanternStore *store, size_t index) {
    if (!store || !store->validator_votes || index >= store->validator_votes_len) {
        return false;
    }
    return store->validator_votes[index].has_vote;
}

int lantern_store_get_signed_validator_vote(
    const LanternStore *store,
    size_t index,
    LanternSignedVote *out_vote) {
    if (!store || !store->validator_votes || index >= store->validator_votes_len || !out_vote) {
        return -1;
    }
    const struct lantern_vote_record *record = &store->validator_votes[index];
    if (!record->has_vote) {
        return -1;
    }
    memset(out_vote, 0, sizeof(*out_vote));
    out_vote->data = record->vote;
    out_vote->data.validator_id = (uint64_t)index;
    if (record->has_signature) {
        out_vote->signature = record->signature;
    }
    return 0;
}

int lantern_store_get_validator_vote(const LanternStore *store, size_t index, LanternVote *out_vote) {
    if (!out_vote) {
        return -1;
    }
    LanternSignedVote signed_vote;
    if (lantern_store_get_signed_validator_vote(store, index, &signed_vote) != 0) {
        return -1;
    }
    *out_vote = signed_vote.data;
    return 0;
}

int lantern_store_set_signed_validator_vote(
    LanternStore *store,
    size_t index,
    const LanternSignedVote *vote) {
    if (!store || !store->validator_votes || index >= store->validator_votes_len || !vote) {
        return -1;
    }
    struct lantern_vote_record *record = &store->validator_votes[index];
    LanternVote previous_vote = record->vote;
    LanternSignature previous_signature = record->signature;
    bool previous_has_signature = record->has_signature;
    record->vote = vote->data;
    record->vote.validator_id = (uint64_t)index;
    record->has_vote = true;
    if (!signature_is_zero(&vote->signature)) {
        record->signature = vote->signature;
        record->has_signature = true;
    } else if (previous_has_signature
               && memcmp(&previous_vote, &record->vote, sizeof(previous_vote)) == 0) {
        record->signature = previous_signature;
        record->has_signature = true;
    } else {
        memset(&record->signature, 0, sizeof(record->signature));
        record->has_signature = false;
    }
    return 0;
}

int lantern_store_set_validator_vote(LanternStore *store, size_t index, const LanternVote *vote) {
    if (!vote) {
        return -1;
    }
    LanternSignedVote signed_vote;
    memset(&signed_vote, 0, sizeof(signed_vote));
    signed_vote.data = *vote;
    return lantern_store_set_signed_validator_vote(store, index, &signed_vote);
}

void lantern_store_clear_validator_vote(LanternStore *store, size_t index) {
    if (!store || !store->validator_votes || index >= store->validator_votes_len) {
        return;
    }
    lantern_vote_record_reset(&store->validator_votes[index]);
}

int lantern_store_prepare_fork_choice_votes(LanternStore *store, uint64_t validator_count) {
    if (!store || validator_count == 0) {
        return -1;
    }
    if (validator_count > (uint64_t)LANTERN_VALIDATOR_REGISTRY_LIMIT || validator_count > SIZE_MAX) {
        return -1;
    }
    size_t count = (size_t)validator_count;
    if (store->known_votes && store->fork_choice_vote_count != count) {
        free(store->known_votes);
        store->known_votes = NULL;
    }
    if (store->new_votes && store->fork_choice_vote_count != count) {
        free(store->new_votes);
        store->new_votes = NULL;
    }
    if (!store->known_votes) {
        store->known_votes = calloc(count, sizeof(*store->known_votes));
        if (!store->known_votes) {
            return -1;
        }
    }
    if (!store->new_votes) {
        store->new_votes = calloc(count, sizeof(*store->new_votes));
        if (!store->new_votes) {
            free(store->known_votes);
            store->known_votes = NULL;
            return -1;
        }
    }
    fork_choice_votes_reset(store->known_votes, count);
    fork_choice_votes_reset(store->new_votes, count);
    store->fork_choice_vote_count = count;
    sync_attached_fork_choice(store);
    return 0;
}

int lantern_store_set_gossip_signature(
    LanternStore *store,
    const LanternSignatureKey *key,
    const LanternAttestationData *data,
    const LanternSignature *signature,
    uint64_t target_slot) {
    if (!store || !key) {
        return -1;
    }
    if (data) {
        (void)attestation_data_by_root_add(
            &store->attestation_data_by_root,
            &key->data_root,
            data,
            target_slot);
    }
    if (!signature || signature_is_zero(signature)) {
        return 0;
    }
    if (gossip_signature_map_set(&store->gossip_signatures, key, signature, target_slot) != 0) {
        return -1;
    }
    return 0;
}

int lantern_store_get_gossip_signature(
    const LanternStore *store,
    const LanternSignatureKey *key,
    LanternSignature *out_signature) {
    if (!store) {
        return -1;
    }
    return gossip_signature_map_get(&store->gossip_signatures, key, out_signature);
}

int lantern_store_remove_gossip_signature(
    LanternStore *store,
    const LanternSignatureKey *key) {
    if (!store || !key) {
        return -1;
    }

    struct lantern_gossip_signature_map *map = &store->gossip_signatures;
    for (size_t i = 0; i < map->length; ++i) {
        if (!signature_key_equals(&map->entries[i].key, key)) {
            continue;
        }
        gossip_signature_map_remove_index(map, i);
        return 0;
    }
    return -1;
}

static int lantern_store_add_aggregated_payload(
    LanternStore *store,
    struct lantern_aggregated_payload_pool *pool,
    const LanternRoot *data_root,
    const LanternAttestationData *data,
    const LanternAggregatedSignatureProof *proof,
    uint64_t target_slot) {
    if (!store || !pool || !data_root || !proof) {
        return -1;
    }
    if (aggregated_payload_pool_add(pool, data_root, proof, target_slot) != 0) {
        return -1;
    }
    if (data) {
        (void)attestation_data_by_root_add(&store->attestation_data_by_root, data_root, data, target_slot);
    }
    return 0;
}

int lantern_store_add_new_aggregated_payload(
    LanternStore *store,
    const LanternRoot *data_root,
    const LanternAttestationData *data,
    const LanternAggregatedSignatureProof *proof,
    uint64_t target_slot) {
    if (!store) {
        return -1;
    }
    return lantern_store_add_aggregated_payload(
        store,
        &store->new_aggregated_payloads,
        data_root,
        data,
        proof,
        target_slot);
}

int lantern_store_add_known_aggregated_payload(
    LanternStore *store,
    const LanternRoot *data_root,
    const LanternAttestationData *data,
    const LanternAggregatedSignatureProof *proof,
    uint64_t target_slot) {
    if (!store) {
        return -1;
    }
    return lantern_store_add_aggregated_payload(
        store,
        &store->known_aggregated_payloads,
        data_root,
        data,
        proof,
        target_slot);
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
            &entry->proof,
            entry->target_slot);
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
        if (data_cache->entries[i].target_slot <= finalized_slot) {
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
        if (data_cache->entries[data_index].target_slot <= finalized_slot) {
            stale_roots[stale_root_index] = data_cache->entries[data_index].data_root;
            stale_root_index += 1u;
            attestation_data_by_root_remove_index(data_cache, data_index);
            continue;
        }
        data_index += 1u;
    }

    size_t signature_index = 0u;
    while (signature_index < store->gossip_signatures.length) {
        if (root_in_set(
                &store->gossip_signatures.entries[signature_index].key.data_root,
                stale_roots,
                stale_root_count)) {
            gossip_signature_map_remove_index(&store->gossip_signatures, signature_index);
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
