#include "lantern/consensus/signature.h"

#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "lantern/metrics/lean_metrics.h"
#include "lantern/support/log.h"
#include "lantern/support/strings.h"
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

static void log_agg_proof_preview(const LanternByteList *proof) {
    if (!proof || !proof->data) {
        lantern_log_debug("signature", NULL, "aggregation proof is empty");
        return;
    }

    const size_t preview_len = proof->length < 32u ? proof->length : 32u;
    char hex[(32u * 2u) + 1u];
    hex[0] = '\0';
    if (preview_len > 0) {
        if (lantern_bytes_to_hex(proof->data, preview_len, hex, sizeof(hex), 0) != 0) {
            hex[0] = '\0';
        }
    }
    const char *ellipsis = proof->length > preview_len ? "..." : "";
    lantern_log_debug(
        "signature",
        NULL,
        "aggregation proof preview len=%zu hex=%s%s",
        proof->length,
        hex[0] ? hex : "-",
        ellipsis);

    if (proof->length >= 9u) {
        uint32_t proof_len = (uint32_t)proof->data[1]
            | ((uint32_t)proof->data[2] << 8u)
            | ((uint32_t)proof->data[3] << 16u)
            | ((uint32_t)proof->data[4] << 24u);
        uint32_t randomness_count = (uint32_t)proof->data[5]
            | ((uint32_t)proof->data[6] << 8u)
            | ((uint32_t)proof->data[7] << 16u)
            | ((uint32_t)proof->data[8] << 24u);
        lantern_log_debug(
            "signature",
            NULL,
            "aggregation proof header version=0x%02x proof_len=%" PRIu32 " randomness_count=%" PRIu32 " total_len=%zu",
            (unsigned)proof->data[0],
            proof_len,
            randomness_count,
            proof->length);
    }
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
    const LanternRoot *message) {
    if (!pubkey_bytes || pubkey_len == 0) {
        return false;
    }
    if (!signature || !message) {
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
        message->bytes,
        LANTERN_ROOT_SIZE,
        signature->bytes,
        sizeof(signature->bytes));
    double elapsed = get_time_seconds() - start;
    lean_metrics_record_pq_signature_verification(elapsed);
    bool valid = (verify_rc == 1);
    lean_metrics_record_pq_signature_verification_result(valid);
    return valid;
}

bool lantern_signature_verify_pk(
    const struct PQSignatureSchemePublicKey *pubkey,
    uint64_t epoch,
    const LanternSignature *signature,
    const LanternRoot *message) {
    if (!pubkey || !signature || !message) {
        return false;
    }
    struct PQSignature *pq_signature = NULL;
    // Use SSZ format (compatible with Ream's leanSig)
    enum PQSigningError sig_err =
        pq_signature_deserialize(signature->bytes, sizeof(signature->bytes), &pq_signature);
    if (sig_err != Success || !pq_signature) {
        lantern_log_debug("signature", NULL, "signature deserialize failed");
        lean_metrics_record_pq_signature_verification_result(false);
        return false;
    }
    double start = get_time_seconds();
    int verify_rc = pq_verify(pubkey, epoch, message->bytes, LANTERN_ROOT_SIZE, pq_signature);
    double elapsed = get_time_seconds() - start;
    lean_metrics_record_pq_signature_verification(elapsed);
    bool valid = (verify_rc == 1);
    lean_metrics_record_pq_signature_verification_result(valid);
    pq_signature_free(pq_signature);
    if (!valid) {
        lantern_log_debug("signature", NULL, "pq_verify rc=%d", verify_rc);
    }
    return valid;
}

bool lantern_signature_sign(
    const struct PQSignatureSchemeSecretKey *secret_key,
    uint64_t epoch,
    const LanternRoot *message,
    LanternSignature *out_signature) {
    if (!secret_key || !message || !out_signature) {
        return false;
    }
    struct PQSignature *pq_signature = NULL;
    double start = get_time_seconds();
    enum PQSigningError sign_err =
        pq_sign(secret_key, epoch, message->bytes, LANTERN_ROOT_SIZE, &pq_signature);
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
    const LanternRoot *message,
    uint64_t epoch,
    LanternByteList *out_proof) {
    if (!pubkeys || !signatures || !message || !out_proof) {
        return false;
    }
    if (count == 0) {
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
            message->bytes,
            LANTERN_ROOT_SIZE,
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
        lean_metrics_record_pq_aggregated_signature_build(count, elapsed);
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
    const LanternRoot *message,
    const LanternByteList *proof,
    uint64_t epoch) {
    if (!pubkeys || !message || !proof) {
        return false;
    }
    if (count == 0) {
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
    log_agg_proof_preview(proof);

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
    double elapsed = 0.0;
    if (ok) {
        pq_xmss_aggregation_setup_verifier();
        double start = get_time_seconds();
        verify_rc = pq_verify_aggregated_signatures(
            (const struct PQSignatureSchemePublicKey *const *)pubkey_handles,
            count,
            message->bytes,
            LANTERN_ROOT_SIZE,
            proof->data,
            proof->length,
            epoch);
        elapsed = get_time_seconds() - start;
        lean_metrics_record_pq_aggregated_signature_verification(elapsed, verify_rc == 1);
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
