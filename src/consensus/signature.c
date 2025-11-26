#include "lantern/consensus/signature.h"

#include <stdio.h>
#include <string.h>

#include "lantern/support/log.h"
#include "pq-bindings-c-rust.h"

static bool bytes_are_zero(const uint8_t *bytes, size_t length) {
    if (!bytes && length > 0) {
        return false;
    }
    for (size_t i = 0; i < length; ++i) {
        if (bytes[i] != 0u) {
            return false;
        }
    }
    return true;
}

bool lantern_signature_is_zero(const LanternSignature *signature) {
    if (!signature) {
        return false;
    }
    return bytes_are_zero(signature->bytes, LANTERN_SIGNATURE_SIZE);
}

void lantern_signature_zero(LanternSignature *signature) {
    if (!signature) {
        return;
    }
    memset(signature->bytes, 0, sizeof(signature->bytes));
}

bool lantern_signature_verify(
    const uint8_t *pubkey_bytes,
    size_t pubkey_len,
    uint64_t epoch,
    const LanternSignature *signature,
    const uint8_t *message,
    size_t message_len) {
    if (!pubkey_bytes || pubkey_len == 0) {
        return false;
    }
    struct PQSignatureSchemePublicKey *pq_pubkey = NULL;
    enum PQSigningError pk_err = pq_public_key_deserialize(pubkey_bytes, pubkey_len, &pq_pubkey);
    if (pk_err != Success || !pq_pubkey) {
        lantern_log_debug("signature", NULL, "pq_public_key_deserialize failed err=%d len=%zu", (int)pk_err, pubkey_len);
        return false;
    }
    bool ok = lantern_signature_verify_pk(pq_pubkey, epoch, signature, message, message_len);
    pq_public_key_free(pq_pubkey);
    return ok;
}

bool lantern_signature_verify_pk(
    const struct PQSignatureSchemePublicKey *pubkey,
    uint64_t epoch,
    const LanternSignature *signature,
    const uint8_t *message,
    size_t message_len) {
    if (!pubkey || !signature || !message) {
        return false;
    }
    if (message_len != LANTERN_ROOT_SIZE) {
        return false;
    }
    struct PQSignature *pq_signature = NULL;
    // Use bincode format (compatible with Zeam/LeanSig)
    // Note: SSZ/lean bytes format is not supported by LeanSig internals
    enum PQSigningError sig_err =
        pq_signature_deserialize_bincode(signature->bytes, sizeof(signature->bytes), &pq_signature);
    if (sig_err != Success || !pq_signature) {
        lantern_log_debug("signature", NULL, "signature deserialize (bincode) failed");
        return false;
    }
    // SSZ/lean bytes format - commented out as LeanSig doesn't support SSZ
    // enum PQSigningError sig_err =
    //     pq_signature_deserialize(signature->bytes, sizeof(signature->bytes), &pq_signature);
    // if (sig_err != Success || !pq_signature) {
    //     return false;
    // }
    int verify_rc = pq_verify(pubkey, epoch, message, message_len, pq_signature);
    pq_signature_free(pq_signature);
    if (verify_rc != 1) {
        lantern_log_debug("signature", NULL, "pq_verify rc=%d", verify_rc);
    }
    return verify_rc == 1;
}

bool lantern_signature_sign(
    const struct PQSignatureSchemeSecretKey *secret_key,
    uint64_t epoch,
    const uint8_t *message,
    size_t message_len,
    LanternSignature *out_signature) {
    if (!secret_key || !message || !out_signature) {
        return false;
    }
    if (message_len != LANTERN_ROOT_SIZE) {
        return false;
    }
    struct PQSignature *pq_signature = NULL;
    enum PQSigningError sign_err = pq_sign(secret_key, epoch, message, message_len, &pq_signature);
    if (sign_err != Success || !pq_signature) {
        return false;
    }

    uintptr_t written = 0;
    // Use bincode format (compatible with Zeam/LeanSig)
    // Note: SSZ/lean bytes format is not supported by LeanSig internals
    enum PQSigningError serialize_err = pq_signature_serialize_bincode(
        pq_signature,
        out_signature->bytes,
        sizeof(out_signature->bytes),
        &written);
    // SSZ/lean bytes format - commented out as LeanSig doesn't support SSZ
    // enum PQSigningError serialize_err = pq_signature_serialize(
    //     pq_signature,
    //     out_signature->bytes,
    //     sizeof(out_signature->bytes),
    //     &written);
    pq_signature_free(pq_signature);
    if (serialize_err != Success || written == 0 || written > sizeof(out_signature->bytes)) {
        lantern_log_error(
            "signature",
            NULL,
            "lantern_signature_sign serialize failed err=%d needed=%zu buffer=%zu",
            (int)serialize_err,
            (size_t)written,
            sizeof(out_signature->bytes));
        return false;
    }
    if (written < sizeof(out_signature->bytes)) {
        memset(out_signature->bytes + written, 0, sizeof(out_signature->bytes) - written);
    }
    return true;
}
