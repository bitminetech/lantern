#ifndef LANTERN_CONSENSUS_STORE_H
#define LANTERN_CONSENSUS_STORE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdatomic.h>
#include <stdint.h>

#include "lantern/consensus/state.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    LanternValidatorIndex validator_index;
    LanternRoot data_root;
} LanternSignatureKey;

struct lantern_attestation_signature_entry {
    LanternSignatureKey key;
    LanternAttestationData data;
    LanternSignature signature;
};

struct lantern_attestation_signature_map {
    struct lantern_attestation_signature_entry *entries;
    size_t length;
    size_t capacity;
};

struct lantern_aggregated_payload_entry {
    LanternRoot data_root;
    LanternAttestationData data;
    LanternAggregatedSignatureProof proof;
};

struct lantern_aggregated_payload_pool {
    struct lantern_aggregated_payload_entry *entries;
    size_t length;
    size_t capacity;
};

void lantern_aggregated_payload_pool_reset(
    struct lantern_aggregated_payload_pool *pool);
int lantern_aggregated_payload_pool_add(
    struct lantern_aggregated_payload_pool *pool,
    const LanternRoot *data_root,
    const LanternAttestationData *data,
    const LanternAggregatedSignatureProof *proof);

struct lantern_fork_choice_block_entry {
    LanternRoot root;
    LanternRoot parent_root;
    uint64_t slot;
    LanternValidatorIndex proposer_index;
    LanternState state;
};

struct lantern_fork_choice_checkpoint_snapshot {
    atomic_uint_fast64_t sequence;
    atomic_uint_fast64_t justified_slot;
    atomic_uchar justified_root[LANTERN_ROOT_SIZE];
    atomic_uint_fast64_t finalized_slot;
    atomic_uchar finalized_root[LANTERN_ROOT_SIZE];
};

struct lantern_store {
    struct lantern_attestation_signature_map attestation_signatures;
    struct lantern_aggregated_payload_pool new_aggregated_payloads;
    struct lantern_aggregated_payload_pool known_aggregated_payloads;

    LanternCheckpoint anchor;
    uint64_t time_intervals;
    LanternCheckpoint latest_justified;
    LanternCheckpoint latest_finalized;
    struct lantern_fork_choice_checkpoint_snapshot checkpoint_snapshot;
    LanternRoot head;
    LanternRoot safe_target;

    struct lantern_fork_choice_block_entry *blocks;
    size_t block_len;
    size_t block_cap;
};

void lantern_store_init(LanternStore *store);
void lantern_store_reset(LanternStore *store);

int lantern_store_set_attestation_signature(
    LanternStore *store,
    const LanternSignatureKey *key,
    const LanternAttestationData *data,
    const LanternSignature *signature);
size_t lantern_store_remove_attestation_signatures_for_data_root(
    LanternStore *store,
    const LanternRoot *data_root);
int lantern_store_add_new_aggregated_payload(
    LanternStore *store,
    const LanternRoot *data_root,
    const LanternAttestationData *data,
    const LanternAggregatedSignatureProof *proof);
int lantern_store_add_known_aggregated_payload(
    LanternStore *store,
    const LanternRoot *data_root,
    const LanternAttestationData *data,
    const LanternAggregatedSignatureProof *proof);
bool lantern_store_aggregated_payloads_cover_participants(
    const LanternStore *store,
    const LanternRoot *data_root,
    const struct lantern_bitlist *participants);
void lantern_store_clear_new_aggregated_payloads(LanternStore *store);
size_t lantern_store_remove_new_aggregated_payloads_matching(
    LanternStore *store,
    const struct lantern_aggregated_payload_pool *snapshot);
size_t lantern_store_promote_new_aggregated_payloads(LanternStore *store);
size_t lantern_store_prune_finalized_attestation_material(
    LanternStore *store,
    uint64_t finalized_slot);
#ifdef __cplusplus
}
#endif

#endif /* LANTERN_CONSENSUS_STORE_H */
