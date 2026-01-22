#include "lantern/consensus/signature.h"

#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "lantern/metrics/lean_metrics.h"
#include "lantern/support/log.h"
#include "pq-bindings-c-rust.h"

static double get_time_seconds(void) {
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) {
        return 0.0;
    }
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

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
    if (!signature || !message) {
        return false;
    }
    if (message_len != LANTERN_ROOT_SIZE) {
        return false;
    }
    // Use pq_verify_ssz which handles the 52-byte pubkey as SSZ format.
    // This matches Ream's leanSig serialization using the Serializable trait.
    // The 52-byte pubkey is serialized using leanSig's to_bytes()/from_bytes().
    double start = get_time_seconds();
    int verify_rc = pq_verify_ssz(
        pubkey_bytes,
        pubkey_len,
        epoch,
        message,
        message_len,
        signature->bytes,
        sizeof(signature->bytes));
    double elapsed = get_time_seconds() - start;
    lean_metrics_record_pq_signature_verification(elapsed);
    if (verify_rc != 1) {
        lantern_log_debug("signature", NULL, "pq_verify_ssz rc=%d", verify_rc);
    }
    return verify_rc == 1;
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
    // Use SSZ format (compatible with Ream's leanSig)
    enum PQSigningError sig_err =
        pq_signature_deserialize(signature->bytes, sizeof(signature->bytes), &pq_signature);
    if (sig_err != Success || !pq_signature) {
        lantern_log_debug("signature", NULL, "signature deserialize failed");
        return false;
    }
    double start = get_time_seconds();
    int verify_rc = pq_verify(pubkey, epoch, message, message_len, pq_signature);
    double elapsed = get_time_seconds() - start;
    lean_metrics_record_pq_signature_verification(elapsed);
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
    double start = get_time_seconds();
    enum PQSigningError sign_err = pq_sign(secret_key, epoch, message, message_len, &pq_signature);
    double elapsed = get_time_seconds() - start;
    lean_metrics_record_pq_signature_signing(elapsed);
    if (sign_err != Success || !pq_signature) {
        return false;
    }

    uintptr_t written = 0;
    // Use SSZ format (compatible with Ream's leanSig)
    enum PQSigningError serialize_err = pq_signature_serialize(
        pq_signature,
        out_signature->bytes,
        sizeof(out_signature->bytes),
        &written);
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

bool lantern_signature_aggregate(
    const uint8_t *const *pubkeys,
    const LanternSignature *signatures,
    size_t count,
    const uint8_t *message,
    size_t message_len,
    uint64_t epoch,
    LanternByteList *out_proof) {
    if (!pubkeys || !signatures || !message || !out_proof) {
        return false;
    }
    if (count == 0) {
        return false;
    }
    if (message_len != LANTERN_ROOT_SIZE) {
        return false;
    }
    lantern_log_info(
        "signature",
        NULL,
        "aggregation start count=%zu epoch=%" PRIu64,
        count,
        epoch);

    double start = get_time_seconds();
    if (lantern_byte_list_resize(out_proof, LANTERN_AGG_PROOF_MAX_BYTES) != 0) {
        lantern_log_error("signature", NULL, "aggregation resize failed max=%zu", (size_t)LANTERN_AGG_PROOF_MAX_BYTES);
        return false;
    }

    struct PQSignatureSchemePublicKey **pubkey_handles = calloc(count, sizeof(*pubkey_handles));
    struct PQSignature **sig_handles = calloc(count, sizeof(*sig_handles));
    if (!pubkey_handles || !sig_handles) {
        free(pubkey_handles);
        free(sig_handles);
        (void)lantern_byte_list_resize(out_proof, 0);
        return false;
    }

    bool ok = true;
    for (size_t i = 0; i < count; ++i) {
        if (!pubkeys[i]) {
            ok = false;
            break;
        }
        enum PQSigningError pk_err = pq_public_key_deserialize(
                pubkeys[i],
                LANTERN_VALIDATOR_PUBKEY_SIZE,
                &pubkey_handles[i]);
        if (pk_err != Success) {
            lantern_log_error(
                "signature",
                NULL,
                "aggregation pubkey deserialize failed index=%zu err=%d",
                i,
                (int)pk_err);
            ok = false;
            break;
        }
        enum PQSigningError sig_err = pq_signature_deserialize(
                signatures[i].bytes,
                sizeof(signatures[i].bytes),
                &sig_handles[i]);
        if (sig_err != Success) {
            lantern_log_error(
                "signature",
                NULL,
                "aggregation signature deserialize failed index=%zu err=%d",
                i,
                (int)sig_err);
            ok = false;
            break;
        }
    }

    if (ok) {
        pq_xmss_aggregation_setup_prover();
        uintptr_t written_len = 0;
        enum PQSigningError err = pq_aggregate_signatures(
            (const struct PQSignatureSchemePublicKey *const *)pubkey_handles,
            (const struct PQSignature *const *)sig_handles,
            count,
            message,
            message_len,
            epoch,
            out_proof->data,
            out_proof->length,
            &written_len);
        if (err != Success || written_len == 0 || written_len > out_proof->length) {
            lantern_log_error(
                "signature",
                NULL,
                "aggregation failed err=%d written=%zu buffer=%zu count=%zu",
                (int)err,
                (size_t)written_len,
                (size_t)out_proof->length,
                count);
            ok = false;
        } else if (lantern_byte_list_resize(out_proof, (size_t)written_len) != 0) {
            lantern_log_error(
                "signature",
                NULL,
                "aggregation resize failed written=%zu",
                (size_t)written_len);
            ok = false;
        }
    }

    for (size_t i = 0; i < count; ++i) {
        if (sig_handles[i]) {
            pq_signature_free(sig_handles[i]);
        }
        if (pubkey_handles[i]) {
            pq_public_key_free(pubkey_handles[i]);
        }
    }
    free(sig_handles);
    free(pubkey_handles);

    if (!ok) {
        (void)lantern_byte_list_resize(out_proof, 0);
        lantern_log_error(
            "signature",
            NULL,
            "aggregation failed count=%zu epoch=%" PRIu64,
            count,
            epoch);
    } else {
        double elapsed = get_time_seconds() - start;
        lantern_log_debug(
            "signature",
            NULL,
            "aggregation ok count=%zu proof_len=%zu elapsed=%.6f",
            count,
            out_proof->length,
            elapsed);
    }
    return ok;
}

bool lantern_signature_verify_aggregated(
    const uint8_t *const *pubkeys,
    size_t count,
    const uint8_t *message,
    size_t message_len,
    const LanternByteList *proof,
    uint64_t epoch) {
    if (!pubkeys || !message || !proof) {
        return false;
    }
    if (count == 0) {
        return false;
    }
    if (message_len != LANTERN_ROOT_SIZE) {
        return false;
    }
    if (proof->length == 0 || !proof->data) {
        return false;
    }
    lantern_log_info(
        "signature",
        NULL,
        "aggregation verify start count=%zu epoch=%" PRIu64 " proof_len=%zu",
        count,
        epoch,
        proof->length);

    struct PQSignatureSchemePublicKey **pubkey_handles = calloc(count, sizeof(*pubkey_handles));
    if (!pubkey_handles) {
        return false;
    }

    bool ok = true;
    for (size_t i = 0; i < count; ++i) {
        if (!pubkeys[i]) {
            ok = false;
            break;
        }
        enum PQSigningError pk_err = pq_public_key_deserialize(
                pubkeys[i],
                LANTERN_VALIDATOR_PUBKEY_SIZE,
                &pubkey_handles[i]);
        if (pk_err != Success) {
            lantern_log_error(
                "signature",
                NULL,
                "aggregation verify pubkey deserialize failed index=%zu err=%d",
                i,
                (int)pk_err);
            ok = false;
            break;
        }
    }

    int verify_rc = -1;
    if (ok) {
        pq_xmss_aggregation_setup_verifier();
        double start = get_time_seconds();
        verify_rc = pq_verify_aggregated_signatures(
            (const struct PQSignatureSchemePublicKey *const *)pubkey_handles,
            count,
            message,
            message_len,
            proof->data,
            proof->length,
            epoch);
        double elapsed = get_time_seconds() - start;
        lantern_log_debug(
            "signature",
            NULL,
            "aggregation verify rc=%d elapsed=%.6f",
            verify_rc,
            elapsed);
    }

    for (size_t i = 0; i < count; ++i) {
        if (pubkey_handles[i]) {
            pq_public_key_free(pubkey_handles[i]);
        }
    }
    free(pubkey_handles);

    if (!ok) {
        return false;
    }
    if (verify_rc != 1) {
        lantern_log_error(
            "signature",
            NULL,
            "aggregation verify failed rc=%d count=%zu epoch=%" PRIu64,
            verify_rc,
            count,
            epoch);
    }
    return verify_rc == 1;
}
