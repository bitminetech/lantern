#ifndef LANTERN_CONSENSUS_CONTAINERS_H
#define LANTERN_CONSENSUS_CONTAINERS_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define LANTERN_ROOT_SIZE 32
#define LANTERN_SIGNATURE_SIZE 3116
#define LANTERN_MAX_ATTESTATIONS 4096
#define LANTERN_VALIDATOR_PUBKEY_SIZE 52
#define LANTERN_VALIDATOR_REGISTRY_LIMIT 4096
#define LANTERN_MAX_BLOCK_SIGNATURES LANTERN_VALIDATOR_REGISTRY_LIMIT
#define LANTERN_HISTORICAL_ROOTS_LIMIT 262144
#define LANTERN_JUSTIFICATION_VALIDATORS_LIMIT ((size_t)LANTERN_HISTORICAL_ROOTS_LIMIT * (size_t)LANTERN_VALIDATOR_REGISTRY_LIMIT)

typedef struct {
    uint8_t bytes[LANTERN_ROOT_SIZE];
} LanternRoot;

typedef struct {
    uint8_t bytes[LANTERN_SIGNATURE_SIZE];
} LanternSignature;

typedef struct {
    uint64_t num_validators;
    uint64_t genesis_time;
} LanternConfig;

typedef struct {
    LanternRoot root;
    uint64_t slot;
} LanternCheckpoint;

typedef struct {
    uint64_t validator_id;
    uint64_t slot;
    LanternCheckpoint head;
    LanternCheckpoint target;
    LanternCheckpoint source;
} LanternVote;

typedef struct {
    LanternVote data;
    LanternSignature signature;
} LanternSignedVote;

typedef struct {
    LanternSignature *data;
    size_t length;
    size_t capacity;
} LanternBlockSignatures;

typedef struct {
    LanternVote *data;
    size_t length;
    size_t capacity;
} LanternAttestations;

typedef struct {
    LanternAttestations attestations;
} LanternBlockBody;

typedef struct {
    uint8_t pubkey[LANTERN_VALIDATOR_PUBKEY_SIZE];
} LanternValidator;

typedef struct {
    uint64_t slot;
    uint64_t proposer_index;
    LanternRoot parent_root;
    LanternRoot state_root;
    LanternRoot body_root;
} LanternBlockHeader;

typedef struct {
    uint64_t slot;
    uint64_t proposer_index;
    LanternRoot parent_root;
    LanternRoot state_root;
    LanternBlockBody body;
} LanternBlock;

typedef struct {
#if defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L
    union {
        LanternBlock block;
        struct {
            uint64_t slot;
            uint64_t proposer_index;
            LanternRoot parent_root;
            LanternRoot state_root;
            LanternBlockBody body;
        };
    };
#else
    LanternBlock block;
#endif
    LanternVote proposer_attestation;
} LanternBlockWithAttestation;

typedef struct {
    LanternBlockWithAttestation message;
    LanternBlockSignatures signatures;
} LanternSignedBlockWithAttestation;

typedef LanternSignedBlockWithAttestation LanternSignedBlock;

void lantern_attestations_init(LanternAttestations *list);
void lantern_attestations_reset(LanternAttestations *list);
int lantern_attestations_append(LanternAttestations *list, const LanternVote *vote);
int lantern_attestations_copy(LanternAttestations *dst, const LanternAttestations *src);
int lantern_attestations_resize(LanternAttestations *list, size_t new_length);

void lantern_block_signatures_init(LanternBlockSignatures *list);
void lantern_block_signatures_reset(LanternBlockSignatures *list);
int lantern_block_signatures_append(LanternBlockSignatures *list, const LanternSignature *signature);
int lantern_block_signatures_copy(LanternBlockSignatures *dst, const LanternBlockSignatures *src);
int lantern_block_signatures_resize(LanternBlockSignatures *list, size_t new_length);

void lantern_block_body_init(LanternBlockBody *body);
void lantern_block_body_reset(LanternBlockBody *body);

void lantern_block_with_attestation_init(LanternBlockWithAttestation *block);
void lantern_block_with_attestation_reset(LanternBlockWithAttestation *block);
void lantern_signed_block_with_attestation_init(LanternSignedBlockWithAttestation *block);
void lantern_signed_block_with_attestation_reset(LanternSignedBlockWithAttestation *block);

#endif /* LANTERN_CONSENSUS_CONTAINERS_H */
