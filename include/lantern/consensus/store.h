#ifndef LANTERN_CONSENSUS_STORE_H
#define LANTERN_CONSENSUS_STORE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "lantern/consensus/containers.h"

#ifdef __cplusplus
extern "C" {
#endif

struct lantern_fork_choice;

struct lantern_vote_record {
    LanternVote vote;
    LanternSignature signature;
    bool has_vote;
    bool has_signature;
};

typedef struct {
    LanternValidatorIndex validator_index;
    LanternRoot data_root;
} LanternSignatureKey;

struct lantern_attestation_signature_entry {
    LanternSignatureKey key;
    LanternSignature signature;
    uint64_t attestation_slot;
    uint64_t target_slot;
};

struct lantern_attestation_signature_map {
    struct lantern_attestation_signature_entry *entries;
    size_t length;
    size_t capacity;
};

struct lantern_aggregated_payload_entry {
    LanternRoot data_root;
    LanternAggregatedSignatureProof proof;
    uint64_t target_slot;
};

struct lantern_aggregated_payload_pool {
    struct lantern_aggregated_payload_entry *entries;
    size_t length;
    size_t capacity;
};

struct lantern_attestation_data_by_root_entry {
    LanternRoot data_root;
    LanternAttestationData data;
    uint64_t target_slot;
};

struct lantern_attestation_data_by_root {
    struct lantern_attestation_data_by_root_entry *entries;
    size_t length;
    size_t capacity;
};

typedef struct lantern_store {
    struct lantern_vote_record *validator_votes;
    size_t validator_votes_len;

    struct lantern_attestation_signature_map attestation_signatures;
    struct lantern_aggregated_payload_pool new_aggregated_payloads;
    struct lantern_aggregated_payload_pool known_aggregated_payloads;
    struct lantern_attestation_data_by_root attestation_data_by_root;

    struct lantern_fork_choice *fork_choice;
} LanternStore;

void lantern_store_init(LanternStore *store);
void lantern_store_reset(LanternStore *store);
void lantern_store_attach_fork_choice(LanternStore *store, struct lantern_fork_choice *fork_choice);

int lantern_store_prepare_validator_votes(LanternStore *store, uint64_t validator_count);
int lantern_store_clone_validator_votes(const LanternStore *source, LanternStore *dest);
size_t lantern_store_validator_capacity(const LanternStore *store);
bool lantern_store_validator_has_vote(const LanternStore *store, size_t index);
int lantern_store_get_signed_validator_vote(
    const LanternStore *store,
    size_t index,
    LanternSignedVote *out_vote);
int lantern_store_get_validator_vote(const LanternStore *store, size_t index, LanternVote *out_vote);
int lantern_store_set_signed_validator_vote(
    LanternStore *store,
    size_t index,
    const LanternSignedVote *vote);
int lantern_store_set_validator_vote(LanternStore *store, size_t index, const LanternVote *vote);
void lantern_store_clear_validator_vote(LanternStore *store, size_t index);

int lantern_store_set_attestation_signature(
    LanternStore *store,
    const LanternSignatureKey *key,
    const LanternAttestationData *data,
    const LanternSignature *signature,
    uint64_t target_slot);
int lantern_store_get_attestation_signature(
    const LanternStore *store,
    const LanternSignatureKey *key,
    LanternSignature *out_signature);
size_t lantern_store_remove_attestation_signatures_for_data_root(
    LanternStore *store,
    const LanternRoot *data_root);
int lantern_store_add_new_aggregated_payload(
    LanternStore *store,
    const LanternRoot *data_root,
    const LanternAttestationData *data,
    const LanternAggregatedSignatureProof *proof,
    uint64_t target_slot);
int lantern_store_add_known_aggregated_payload(
    LanternStore *store,
    const LanternRoot *data_root,
    const LanternAttestationData *data,
    const LanternAggregatedSignatureProof *proof,
    uint64_t target_slot);
bool lantern_store_aggregated_payloads_cover_participants(
    const LanternStore *store,
    const LanternRoot *data_root,
    const struct lantern_bitlist *participants);
int lantern_store_add_attestation_data(
    LanternStore *store,
    const LanternRoot *data_root,
    const LanternAttestationData *data,
    uint64_t target_slot);
void lantern_store_clear_new_aggregated_payloads(LanternStore *store);
size_t lantern_store_remove_new_aggregated_payloads_matching(
    LanternStore *store,
    const struct lantern_aggregated_payload_pool *snapshot);
size_t lantern_store_promote_new_aggregated_payloads(LanternStore *store);
size_t lantern_store_prune_finalized_attestation_material(
    LanternStore *store,
    uint64_t finalized_slot);
int lantern_store_get_attestation_data(
    const LanternStore *store,
    const LanternRoot *data_root,
    LanternAttestationData *out_data);

#ifdef __cplusplus
}
#endif

#endif /* LANTERN_CONSENSUS_STORE_H */
