#ifndef LANTERN_CONSENSUS_CONTAINERS_H
#define LANTERN_CONSENSUS_CONTAINERS_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define LANTERN_ROOT_SIZE 32
#ifndef LANTERN_SIGNATURE_SIZE
#define LANTERN_SIGNATURE_SIZE 2536
#endif
#define LANTERN_MAX_ATTESTATIONS 4096
#define LANTERN_MAX_ATTESTATIONS_DATA UINT8_C(16)
#define LANTERN_VALIDATOR_PUBKEY_SIZE 52
#define LANTERN_VALIDATOR_REGISTRY_LIMIT 4096
#define LANTERN_MAX_BLOCK_SIGNATURES LANTERN_VALIDATOR_REGISTRY_LIMIT
#define LANTERN_HISTORICAL_ROOTS_LIMIT 262144
#define LANTERN_JUSTIFICATION_VALIDATORS_LIMIT ((size_t)LANTERN_HISTORICAL_ROOTS_LIMIT * (size_t)LANTERN_VALIDATOR_REGISTRY_LIMIT)
#define LANTERN_AGG_PROOF_MAX_BYTES (1024u * 1024u)
#define LANTERN_AGGREGATED_SIGNATURE_PROOF_INVERSE_PROOF_SIZE 2u
#define LANTERN_INVERSE_PROOF_SIZE 2u

struct lantern_bitlist {
    uint8_t *bytes;
    size_t bit_length;
    size_t capacity;
};

typedef struct {
    uint8_t *data;
    size_t length;
    size_t capacity;
} LanternByteList;

typedef struct {
    uint8_t bytes[LANTERN_ROOT_SIZE];
} LanternRoot;

typedef struct {
    uint8_t bytes[LANTERN_SIGNATURE_SIZE];
} LanternSignature;

typedef uint64_t LanternValidatorIndex;

typedef struct {
    LanternValidatorIndex *data;
    size_t length;
    size_t capacity;
} LanternValidatorIndices;

typedef struct {
    uint64_t num_validators;
    uint64_t genesis_time;
} LanternConfig;

typedef struct {
    LanternRoot root;
    uint64_t slot;
} LanternCheckpoint;

typedef struct {
    uint64_t slot;
    LanternCheckpoint head;
    LanternCheckpoint target;
    LanternCheckpoint source;
} LanternAttestationData;

typedef struct {
#if defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L
    LanternValidatorIndex validator_id;
    union {
        LanternAttestationData data;
        struct {
            uint64_t slot;
            LanternCheckpoint head;
            LanternCheckpoint target;
            LanternCheckpoint source;
        };
    };
#else
    LanternValidatorIndex validator_id;
    uint64_t slot;
    LanternCheckpoint head;
    LanternCheckpoint target;
    LanternCheckpoint source;
#endif
} LanternVote;

typedef struct {
    LanternVote data;
    LanternSignature signature;
} LanternSignedVote;

typedef struct {
    LanternSignature *data;
    size_t length;
    size_t capacity;
} LanternSignatureList;

typedef struct {
    LanternVote *data;
    size_t length;
    size_t capacity;
} LanternAttestations;

typedef struct {
    struct lantern_bitlist aggregation_bits;
    LanternAttestationData data;
} LanternAggregatedAttestation;

typedef struct {
    LanternAggregatedAttestation *data;
    size_t length;
    size_t capacity;
} LanternAggregatedAttestations;

typedef struct {
    struct lantern_bitlist participants;
    LanternByteList proof_data;
} LanternAggregatedSignatureProof;

typedef struct {
    LanternAttestationData data;
    LanternAggregatedSignatureProof proof;
} LanternSignedAggregatedAttestation;

typedef struct {
    LanternAggregatedSignatureProof *data;
    size_t length;
    size_t capacity;
} LanternAttestationSignatures;

typedef struct {
    LanternAttestationSignatures attestation_signatures;
    LanternSignature proposer_signature;
} LanternBlockSignatures;

typedef struct {
    LanternAggregatedAttestations attestations;
    /* Decode-time hint: true when body attestations came from legacy plain-vote layout. */
    bool legacy_plain_attestation_layout;
} LanternBlockBody;

typedef struct {
    uint8_t attestation_pubkey[LANTERN_VALIDATOR_PUBKEY_SIZE];
    uint8_t proposal_pubkey[LANTERN_VALIDATOR_PUBKEY_SIZE];
    LanternValidatorIndex index;
} LanternValidator;

typedef struct {
    uint64_t slot;
    LanternValidatorIndex proposer_index;
    LanternRoot parent_root;
    LanternRoot state_root;
    LanternRoot body_root;
} LanternBlockHeader;

typedef struct {
    uint64_t slot;
    LanternValidatorIndex proposer_index;
    LanternRoot parent_root;
    LanternRoot state_root;
    LanternBlockBody body;
} LanternBlock;

typedef struct {
    LanternBlock block;
    LanternBlockSignatures signatures;
} LanternSignedBlock;

void lantern_attestations_init(LanternAttestations *list);
void lantern_attestations_reset(LanternAttestations *list);
int lantern_attestations_append(LanternAttestations *list, const LanternVote *vote);
int lantern_attestations_resize(LanternAttestations *list, size_t new_length);

void lantern_validator_indices_init(LanternValidatorIndices *indices);
void lantern_validator_indices_reset(LanternValidatorIndices *indices);
int lantern_validator_indices_append(LanternValidatorIndices *indices, LanternValidatorIndex index);
int lantern_validator_indices_copy(LanternValidatorIndices *dst, const LanternValidatorIndices *src);
int lantern_validator_indices_resize(LanternValidatorIndices *indices, size_t new_length);
bool lantern_validator_index_is_valid(LanternValidatorIndex index, size_t num_validators);
bool lantern_validator_index_is_proposer_for(
    LanternValidatorIndex index,
    uint64_t slot,
    size_t num_validators);
int lantern_validator_index_compute_subnet_id(
    LanternValidatorIndex index,
    size_t num_committees,
    size_t *out_subnet_id);
int lantern_aggregation_bits_from_validator_indices(
    struct lantern_bitlist *out_bits,
    const LanternValidatorIndices *indices);
int lantern_aggregation_bits_to_validator_indices(
    const struct lantern_bitlist *bits,
    LanternValidatorIndices *out_indices);

void lantern_bitlist_init(struct lantern_bitlist *list);
void lantern_bitlist_reset(struct lantern_bitlist *list);
int lantern_bitlist_resize(struct lantern_bitlist *list, size_t new_bit_length);
bool lantern_bitlist_get(const struct lantern_bitlist *list, size_t index);
int lantern_bitlist_set(struct lantern_bitlist *list, size_t index, bool value);

void lantern_byte_list_init(LanternByteList *list);
void lantern_byte_list_reset(LanternByteList *list);
int lantern_byte_list_resize(LanternByteList *list, size_t new_length);
int lantern_byte_list_copy(LanternByteList *dst, const LanternByteList *src);

void lantern_aggregated_attestation_init(LanternAggregatedAttestation *attestation);
void lantern_aggregated_attestation_reset(LanternAggregatedAttestation *attestation);
int lantern_aggregated_attestation_copy(
    LanternAggregatedAttestation *dst,
    const LanternAggregatedAttestation *src);

void lantern_aggregated_attestations_init(LanternAggregatedAttestations *list);
void lantern_aggregated_attestations_reset(LanternAggregatedAttestations *list);
int lantern_aggregated_attestations_append(
    LanternAggregatedAttestations *list,
    const LanternAggregatedAttestation *attestation);
int lantern_aggregated_attestations_copy(
    LanternAggregatedAttestations *dst,
    const LanternAggregatedAttestations *src);
int lantern_aggregated_attestations_resize(LanternAggregatedAttestations *list, size_t new_length);
int lantern_expand_aggregated_attestations(
    const LanternAggregatedAttestations *aggregated,
    size_t validator_count,
    LanternAttestations *out_attestations);
int lantern_wrap_attestations_as_aggregated(
    const LanternAttestations *attestations,
    LanternAggregatedAttestations *out_aggregated);

const uint8_t *lantern_validator_get_attestation_pubkey(const LanternValidator *validator);
const uint8_t *lantern_validator_get_proposal_pubkey(const LanternValidator *validator);

void lantern_aggregated_signature_proof_init(LanternAggregatedSignatureProof *proof);
void lantern_aggregated_signature_proof_reset(LanternAggregatedSignatureProof *proof);
int lantern_aggregated_signature_proof_copy(
    LanternAggregatedSignatureProof *dst,
    const LanternAggregatedSignatureProof *src);

void lantern_signed_aggregated_attestation_init(LanternSignedAggregatedAttestation *attestation);
void lantern_signed_aggregated_attestation_reset(LanternSignedAggregatedAttestation *attestation);
int lantern_signed_aggregated_attestation_copy(
    LanternSignedAggregatedAttestation *dst,
    const LanternSignedAggregatedAttestation *src);

void lantern_attestation_signatures_init(LanternAttestationSignatures *list);
void lantern_attestation_signatures_reset(LanternAttestationSignatures *list);
int lantern_attestation_signatures_append(
    LanternAttestationSignatures *list,
    const LanternAggregatedSignatureProof *proof);
int lantern_attestation_signatures_copy(
    LanternAttestationSignatures *dst,
    const LanternAttestationSignatures *src);
int lantern_attestation_signatures_resize(LanternAttestationSignatures *list, size_t new_length);

void lantern_signature_list_init(LanternSignatureList *list);
void lantern_signature_list_reset(LanternSignatureList *list);
int lantern_signature_list_append(LanternSignatureList *list, const LanternSignature *signature);
int lantern_signature_list_resize(LanternSignatureList *list, size_t new_length);

void lantern_block_signatures_init(LanternBlockSignatures *signatures);
void lantern_block_signatures_reset(LanternBlockSignatures *signatures);
int lantern_block_signatures_copy(LanternBlockSignatures *dst, const LanternBlockSignatures *src);

void lantern_block_init(LanternBlock *block);
void lantern_block_reset(LanternBlock *block);
void lantern_block_body_init(LanternBlockBody *body);
void lantern_block_body_reset(LanternBlockBody *body);

void lantern_signed_block_init(LanternSignedBlock *block);
void lantern_signed_block_reset(LanternSignedBlock *block);

#define lantern_signed_block_with_attestation_init lantern_signed_block_init
#define lantern_signed_block_with_attestation_reset lantern_signed_block_reset

#endif /* LANTERN_CONSENSUS_CONTAINERS_H */
