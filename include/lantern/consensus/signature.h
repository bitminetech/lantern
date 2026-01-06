#ifndef LANTERN_CONSENSUS_SIGNATURE_H
#define LANTERN_CONSENSUS_SIGNATURE_H

#include <stdbool.h>
#include <stddef.h>

#include "lantern/consensus/containers.h"

struct PQSignatureSchemeSecretKey;
struct PQSignatureSchemePublicKey;

bool lantern_signature_is_zero(const LanternSignature *signature);
void lantern_signature_zero(LanternSignature *signature);
bool lantern_signature_verify(
    const uint8_t *pubkey_bytes,
    size_t pubkey_len,
    uint64_t epoch,
    const LanternSignature *signature,
    const uint8_t *message,
    size_t message_len);
bool lantern_signature_verify_pk(
    const struct PQSignatureSchemePublicKey *pubkey,
    uint64_t epoch,
    const LanternSignature *signature,
    const uint8_t *message,
    size_t message_len);
bool lantern_signature_sign(
    const struct PQSignatureSchemeSecretKey *secret_key,
    uint64_t epoch,
    const uint8_t *message,
    size_t message_len,
    LanternSignature *out_signature);
bool lantern_signature_aggregate(
    const uint8_t *const *pubkeys,
    const LanternSignature *signatures,
    size_t count,
    const uint8_t *message,
    size_t message_len,
    uint64_t epoch,
    LanternByteList *out_proof);
bool lantern_signature_verify_aggregated(
    const uint8_t *const *pubkeys,
    size_t count,
    const uint8_t *message,
    size_t message_len,
    const LanternByteList *proof,
    uint64_t epoch);

#endif /* LANTERN_CONSENSUS_SIGNATURE_H */
