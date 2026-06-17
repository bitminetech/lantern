#include "lantern/consensus/signature.h"

#include <inttypes.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "lantern/metrics/lean_metrics.h"
#include "lantern/consensus/hash.h"
#include "lantern/support/log.h"
#include "pq-bindings-c-rust.h"

static double get_time_seconds(void) {
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) {
        return 0.0;
    }
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

#if defined(__GNUC__) || defined(__clang__)
static __thread struct lantern_block_build_stage_timings *g_stage_timings = NULL;
#else
static _Thread_local struct lantern_block_build_stage_timings *g_stage_timings = NULL;
#endif

void lantern_signature_set_stage_timings(struct lantern_block_build_stage_timings *timings);

void lantern_signature_set_stage_timings(struct lantern_block_build_stage_timings *timings) {
    g_stage_timings = timings;
}

static double signature_elapsed_seconds(double started_seconds, double finished_seconds) {
    if (finished_seconds < started_seconds) {
        return 0.0;
    }
    return finished_seconds - started_seconds;
}

static void signature_add_stage_seconds(double *stage_seconds, double seconds) {
    if (!stage_seconds || seconds <= 0.0) {
        return;
    }
    *stage_seconds += seconds;
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

struct lantern_recursive_child_input {
    struct PQSignatureSchemePublicKey **pubkey_handles;
};

static pthread_once_t g_xmss_verifier_setup_once = PTHREAD_ONCE_INIT;
static pthread_once_t g_xmss_prover_setup_once = PTHREAD_ONCE_INIT;

static void xmss_prover_setup_once(void) {
    pq_xmss_aggregation_setup_prover();
}

static void xmss_verifier_setup_once(void) {
    pq_xmss_aggregation_setup_verifier();
}

static void ensure_xmss_prover_setup(void) {
    (void)pthread_once(&g_xmss_prover_setup_once, xmss_prover_setup_once);
}

static void ensure_xmss_verifier_setup(void) {
    (void)pthread_once(&g_xmss_verifier_setup_once, xmss_verifier_setup_once);
}

static bool validator_pubkey_bytes_are_zero(const uint8_t *pubkey) {
    if (!pubkey) {
        return true;
    }
    return bytes_are_zero(pubkey, LANTERN_VALIDATOR_PUBKEY_SIZE);
}

static void lantern_recursive_child_input_reset(struct lantern_recursive_child_input *child) {
    if (!child) {
        return;
    }

    if (child->pubkey_handles) {
        for (size_t i = 0; child->pubkey_handles[i] != NULL; ++i) {
            pq_public_key_free(child->pubkey_handles[i]);
        }
    }
    free(child->pubkey_handles);
    memset(child, 0, sizeof(*child));
}

static size_t aggregated_signature_proof_participant_count(
    const LanternAggregatedSignatureProof *proof) {
    if (!proof || proof->participants.bit_length == 0u || !proof->participants.bytes) {
        return 0u;
    }

    size_t count = 0u;
    if (proof->participants.bit_length > LANTERN_VALIDATOR_REGISTRY_LIMIT) {
        return 0u;
    }
    for (size_t i = 0; i < proof->participants.bit_length; ++i) {
        if (lantern_bitlist_get(&proof->participants, i)) {
            count += 1u;
        }
    }
    return count;
}

static bool prepare_recursive_child(
    const LanternState *state,
    const LanternAggregatedSignatureProof *proof,
    const LanternRoot *message,
    uint64_t epoch,
    struct lantern_recursive_child_input *out_child,
    struct PQAggregatedSignatureChild *out_input) {
    if (!state || !proof || !message || !out_child || !out_input) {
        return false;
    }
    if (proof->participants.bit_length == 0u
        || !proof->participants.bytes
        || proof->proof_data.length == 0u
        || !proof->proof_data.data) {
        return false;
    }

    size_t participant_count = aggregated_signature_proof_participant_count(proof);
    if (participant_count == 0u) {
        return false;
    }

    out_child->pubkey_handles = calloc(participant_count + 1u, sizeof(*out_child->pubkey_handles));
    if (!out_child->pubkey_handles) {
        return false;
    }

    size_t validator_count = lantern_state_validator_count(state);
    size_t pubkey_index = 0u;
    for (size_t validator_index = 0; validator_index < proof->participants.bit_length; ++validator_index) {
        if (!lantern_bitlist_get(&proof->participants, validator_index)) {
            continue;
        }
        if (validator_index >= validator_count) {
            return false;
        }

        const uint8_t *pubkey =
            lantern_state_validator_attestation_pubkey(state, validator_index);
        if (!pubkey || validator_pubkey_bytes_are_zero(pubkey)) {
            return false;
        }

        enum PQSigningError pk_err = pq_public_key_deserialize(
            pubkey,
            LANTERN_VALIDATOR_PUBKEY_SIZE,
            &out_child->pubkey_handles[pubkey_index]);
        if (pk_err != Success || !out_child->pubkey_handles[pubkey_index]) {
            return false;
        }
        pubkey_index += 1u;
    }

    ensure_xmss_verifier_setup();
    int verify_rc = pq_verify_aggregated_signatures(
        (const struct PQSignatureSchemePublicKey *const *)out_child->pubkey_handles,
        participant_count,
        message->bytes,
        LANTERN_ROOT_SIZE,
        proof->proof_data.data,
        proof->proof_data.length,
        epoch);
    if (verify_rc == 1) {
        out_input->pubkeys = (const struct PQSignatureSchemePublicKey *const *)out_child->pubkey_handles;
        out_input->pubkey_count = participant_count;
        out_input->agg_bytes = proof->proof_data.data;
        out_input->agg_len = proof->proof_data.length;
        return true;
    }

    return false;
}

static const char *pq_error_detail_or_dash(const char *detail) {
    return detail && detail[0] ? detail : "-";
}

static void log_pq_prover_setup_error_if_any(void) {
    char *detail = pq_take_last_error_message();
    if (!detail) {
        return;
    }
    lantern_log_error("signature", NULL, "%s", pq_error_detail_or_dash(detail));
    pq_string_free(detail);
}

void lantern_signature_prewarm_prover(void) {
    ensure_xmss_prover_setup();
    log_pq_prover_setup_error_if_any();
    ensure_xmss_verifier_setup();
}

static bool write_type2_container(const LanternByteList *raw_proof, LanternByteList *out_encoded) {
    if (!raw_proof || !out_encoded) {
        return false;
    }
    if (raw_proof->length > 0u && !raw_proof->data) {
        return false;
    }
    if (raw_proof->length > LANTERN_AGG_PROOF_MAX_BYTES) {
        return false;
    }
    size_t encoded_len = raw_proof->length + 4u;
    if (lantern_byte_list_resize(out_encoded, encoded_len) != 0) {
        return false;
    }
    out_encoded->data[0] = 4u;
    out_encoded->data[1] = 0u;
    out_encoded->data[2] = 0u;
    out_encoded->data[3] = 0u;
    if (raw_proof->length > 0u) {
        memcpy(out_encoded->data + 4u, raw_proof->data, raw_proof->length);
    }
    return true;
}

bool lantern_signature_wrap_type2_proof(
    const LanternByteList *raw_proof,
    LanternByteList *out_encoded) {
    return write_type2_container(raw_proof, out_encoded);
}

bool lantern_signature_unwrap_type2_proof(
    const LanternByteList *encoded_proof,
    LanternByteList *out_raw) {
    if (!encoded_proof || !out_raw) {
        return false;
    }
    if (encoded_proof->length < 5u || !encoded_proof->data) {
        return false;
    }
    uint32_t offset = (uint32_t)encoded_proof->data[0]
        | ((uint32_t)encoded_proof->data[1] << 8)
        | ((uint32_t)encoded_proof->data[2] << 16)
        | ((uint32_t)encoded_proof->data[3] << 24);
    if (offset != 4u || offset > encoded_proof->length) {
        return false;
    }
    size_t raw_len = encoded_proof->length - (size_t)offset;
    if (raw_len == 0u || raw_len > LANTERN_AGG_PROOF_MAX_BYTES) {
        return false;
    }
    if (lantern_byte_list_resize(out_raw, raw_len) != 0) {
        return false;
    }
    memcpy(out_raw->data, encoded_proof->data + offset, raw_len);
    return true;
}

struct lantern_type2_component_work {
    struct PQSignatureSchemePublicKey **pubkey_handles;
    size_t pubkey_count;
};

static void type2_component_work_reset(struct lantern_type2_component_work *work) {
    if (!work) {
        return;
    }
    if (work->pubkey_handles) {
        for (size_t i = 0; i < work->pubkey_count; ++i) {
            if (work->pubkey_handles[i]) {
                pq_public_key_free(work->pubkey_handles[i]);
            }
        }
    }
    free(work->pubkey_handles);
    memset(work, 0, sizeof(*work));
}

static bool type2_component_init_from_pubkeys(
    const uint8_t *const *pubkeys,
    size_t pubkey_count,
    struct lantern_type2_component_work *work,
    struct PQTypeTwoComponent *component) {
    if (!pubkeys || pubkey_count == 0u || !work || !component) {
        return false;
    }
    work->pubkey_handles = calloc(pubkey_count, sizeof(*work->pubkey_handles));
    if (!work->pubkey_handles) {
        return false;
    }
    work->pubkey_count = pubkey_count;
    for (size_t i = 0; i < pubkey_count; ++i) {
        if (!pubkeys[i] || validator_pubkey_bytes_are_zero(pubkeys[i])) {
            return false;
        }
        enum PQSigningError pk_err = pq_public_key_deserialize(
            pubkeys[i],
            LANTERN_VALIDATOR_PUBKEY_SIZE,
            &work->pubkey_handles[i]);
        if (pk_err != Success || !work->pubkey_handles[i]) {
            return false;
        }
    }
    component->pubkeys = (const struct PQSignatureSchemePublicKey *const *)work->pubkey_handles;
    component->pubkey_count = pubkey_count;
    return true;
}

static size_t bitlist_count_set_bits(const struct lantern_bitlist *bits) {
    if (!bits || bits->bit_length == 0u || !bits->bytes) {
        return 0u;
    }
    size_t count = 0u;
    for (size_t i = 0; i < bits->bit_length; ++i) {
        if (lantern_bitlist_get(bits, i)) {
            count += 1u;
        }
    }
    return count;
}

static bool bitlist_equal(const struct lantern_bitlist *a, const struct lantern_bitlist *b) {
    if (!a || !b || a->bit_length != b->bit_length) {
        return false;
    }
    size_t byte_len = (a->bit_length + 7u) / 8u;
    if (byte_len == 0u) {
        return true;
    }
    return a->bytes && b->bytes && memcmp(a->bytes, b->bytes, byte_len) == 0;
}

static bool singleton_participant_matches(
    const struct lantern_bitlist *participants,
    LanternValidatorIndex expected) {
    if (!participants || participants->bit_length == 0u || !participants->bytes) {
        return false;
    }
    if (expected >= participants->bit_length || !lantern_bitlist_get(participants, (size_t)expected)) {
        return false;
    }
    return bitlist_count_set_bits(participants) == 1u;
}

static bool build_type2_attestation_component(
    const LanternState *state,
    const struct lantern_bitlist *participants,
    struct lantern_type2_component_work *work,
    struct PQTypeTwoComponent *component) {
    if (!state || !participants || !work || !component) {
        return false;
    }
    size_t validator_count = lantern_state_validator_count(state);
    if (participants->bit_length > validator_count) {
        return false;
    }
    size_t pubkey_count = bitlist_count_set_bits(participants);
    if (pubkey_count == 0u) {
        return false;
    }
    const uint8_t **pubkeys = calloc(pubkey_count, sizeof(*pubkeys));
    if (!pubkeys) {
        return false;
    }
    size_t pubkey_index = 0u;
    for (size_t i = 0; i < participants->bit_length; ++i) {
        if (!lantern_bitlist_get(participants, i)) {
            continue;
        }
        const uint8_t *pubkey = lantern_state_validator_attestation_pubkey(state, i);
        if (!pubkey || validator_pubkey_bytes_are_zero(pubkey)) {
            free(pubkeys);
            return false;
        }
        pubkeys[pubkey_index++] = pubkey;
    }
    bool ok = type2_component_init_from_pubkeys(pubkeys, pubkey_count, work, component);
    free(pubkeys);
    return ok;
}

static bool build_type2_proposer_component(
    const LanternState *state,
    LanternValidatorIndex proposer_index,
    struct lantern_type2_component_work *work,
    struct PQTypeTwoComponent *component) {
    if (!state || !work || !component) {
        return false;
    }
    size_t validator_count = lantern_state_validator_count(state);
    if (proposer_index >= validator_count) {
        return false;
    }
    const uint8_t *pubkey = lantern_state_validator_proposal_pubkey(state, (size_t)proposer_index);
    return type2_component_init_from_pubkeys(&pubkey, 1u, work, component);
}

static void reset_type2_component_set(
    struct lantern_type2_component_work *work,
    size_t component_count) {
    if (!work) {
        return;
    }
    for (size_t i = 0; i < component_count; ++i) {
        type2_component_work_reset(&work[i]);
    }
}

static bool build_type2_component_set_for_block(
    const LanternState *state,
    const LanternBlock *block,
    struct lantern_type2_component_work *work,
    struct PQTypeTwoComponent *components,
    struct PQTypeTwoMessageBinding *bindings,
    LanternRoot *message_roots,
    size_t component_count) {
    if (!state || !block || !work || !components || !bindings || !message_roots) {
        return false;
    }
    size_t attestation_count = block->body.attestations.length;
    if (component_count != attestation_count + 1u) {
        return false;
    }
    if (attestation_count > 0u && !block->body.attestations.data) {
        return false;
    }
    for (size_t i = 0; i < attestation_count; ++i) {
        const LanternAggregatedAttestation *attestation = &block->body.attestations.data[i];
        if (!build_type2_attestation_component(
                state,
                &attestation->aggregation_bits,
                &work[i],
                &components[i])) {
            return false;
        }
        if (lantern_hash_tree_root_attestation_data(&attestation->data, &message_roots[i]) != SSZ_SUCCESS) {
            return false;
        }
        bindings[i].message = message_roots[i].bytes;
        bindings[i].message_len = LANTERN_ROOT_SIZE;
        bindings[i].epoch = attestation->data.slot;
    }
    if (!build_type2_proposer_component(
            state,
            block->proposer_index,
            &work[attestation_count],
            &components[attestation_count])) {
        return false;
    }
    if (lantern_hash_tree_root_block(block, &message_roots[attestation_count]) != SSZ_SUCCESS) {
        return false;
    }
    bindings[attestation_count].message = message_roots[attestation_count].bytes;
    bindings[attestation_count].message_len = LANTERN_ROOT_SIZE;
    bindings[attestation_count].epoch = block->slot;
    return true;
}

static bool build_type2_merge_component_set_for_block(
    const LanternState *state,
    const LanternBlock *block,
    struct lantern_type2_component_work *work,
    struct PQTypeTwoComponent *components,
    size_t component_count) {
    if (!state || !block || !work || !components) {
        return false;
    }
    size_t attestation_count = block->body.attestations.length;
    if (component_count != attestation_count + 1u) {
        return false;
    }
    if (attestation_count > 0u && !block->body.attestations.data) {
        return false;
    }
    for (size_t i = 0; i < attestation_count; ++i) {
        const LanternAggregatedAttestation *attestation = &block->body.attestations.data[i];
        if (!build_type2_attestation_component(
                state,
                &attestation->aggregation_bits,
                &work[i],
                &components[i])) {
            return false;
        }
    }
    return build_type2_proposer_component(
        state,
        block->proposer_index,
        &work[attestation_count],
        &components[attestation_count]);
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
    double deserialize_started_seconds = get_time_seconds();
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
    double deserialize_finished_seconds = get_time_seconds();
    if (g_stage_timings) {
        signature_add_stage_seconds(
            &g_stage_timings->key_sig_deserialize_seconds,
            signature_elapsed_seconds(deserialize_started_seconds, deserialize_finished_seconds));
    }

    double elapsed = 0.0;
    if (ok) {
        double setup_started_seconds = get_time_seconds();
        ensure_xmss_prover_setup();
        log_pq_prover_setup_error_if_any();
        double setup_finished_seconds = get_time_seconds();
        if (g_stage_timings) {
            signature_add_stage_seconds(
                &g_stage_timings->other_prover_setup_seconds,
                signature_elapsed_seconds(setup_started_seconds, setup_finished_seconds));
        }
        uintptr_t written_len = 0;
        double start = get_time_seconds();
        enum PQSigningError err = pq_aggregate_signatures_unverified(
            (const struct PQSignatureSchemePublicKey *const *)pubkey_handles,
            (const struct PQSignature *const *)sig_handles,
            count,
            message->bytes,
            LANTERN_ROOT_SIZE,
            epoch,
            LANTERN_AGGREGATED_SIGNATURE_PROOF_INVERSE_PROOF_SIZE,
            out_proof->data,
            out_proof->length,
            &written_len);
        double pq_finished_seconds = get_time_seconds();
        if (g_stage_timings) {
            signature_add_stage_seconds(
                &g_stage_timings->pq_aggregate_seconds,
                signature_elapsed_seconds(start, pq_finished_seconds));
        }
        if (err != Success || written_len == 0 || written_len > out_proof->length) {
            char *detail = pq_take_last_error_message();
            lantern_log_error(
                "signature",
                NULL,
                "aggregation failed err=%d written=%zu buffer=%zu count=%zu detail=%s",
                (int)err,
                (size_t)written_len,
                (size_t)out_proof->length,
                count,
                pq_error_detail_or_dash(detail));
            pq_string_free(detail);
            ok = false;
        } else if (lantern_byte_list_resize(out_proof, (size_t)written_len) != 0) {
            lantern_log_error(
                "signature",
                NULL,
                "aggregation resize failed written=%zu",
                (size_t)written_len);
            ok = false;
        } else {
            elapsed = get_time_seconds() - start;
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
        lean_metrics_record_pq_aggregated_signature_build(count, elapsed);
    }
    return ok;
}

bool lantern_aggregated_signature_proof_aggregate(
    const LanternState *state,
    const struct lantern_bitlist *xmss_participants,
    const LanternAggregatedSignatureProof *children,
    size_t child_count,
    const LanternRawXmssSignature *raw_xmss,
    size_t raw_xmss_count,
    const LanternRoot *message,
    uint64_t epoch,
    LanternAggregatedSignatureProof *out_proof) {
    if (!message || !out_proof) {
        return false;
    }
    if ((child_count > 0u && !children) || (raw_xmss_count > 0u && !raw_xmss)) {
        return false;
    }
    if (raw_xmss_count == 0 && child_count == 0) {
        return false;
    }
    if (raw_xmss_count > 0 && !xmss_participants) {
        return false;
    }

    size_t aggregated_bit_length = 0;
    if (xmss_participants && xmss_participants->bit_length > aggregated_bit_length) {
        aggregated_bit_length = xmss_participants->bit_length;
    }
    for (size_t i = 0; i < child_count; ++i) {
        if (children[i].participants.bit_length > aggregated_bit_length) {
            aggregated_bit_length = children[i].participants.bit_length;
        }
    }
    if (aggregated_bit_length > LANTERN_VALIDATOR_REGISTRY_LIMIT) {
        return false;
    }
    if (lantern_bitlist_resize(&out_proof->participants, aggregated_bit_length) != 0) {
        return false;
    }
    size_t aggregated_byte_len = (aggregated_bit_length + 7u) / 8u;
    if (aggregated_byte_len > 0 && out_proof->participants.bytes) {
        memset(out_proof->participants.bytes, 0, aggregated_byte_len);
    }

    size_t raw_participant_count = 0;
    if (xmss_participants) {
        size_t bytes = (xmss_participants->bit_length + 7u) / 8u;
        if (bytes > 0 && xmss_participants->bytes && out_proof->participants.bytes) {
            memcpy(out_proof->participants.bytes, xmss_participants->bytes, bytes);
        }
        for (size_t i = 0; i < xmss_participants->bit_length; ++i) {
            if (lantern_bitlist_get(xmss_participants, i)) {
                raw_participant_count += 1u;
            }
        }
    }
    if (raw_participant_count != raw_xmss_count) {
        return false;
    }

    for (size_t child_idx = 0; child_idx < child_count; ++child_idx) {
        const struct lantern_bitlist *child_participants = &children[child_idx].participants;
        for (size_t bit = 0; bit < child_participants->bit_length; ++bit) {
            if (lantern_bitlist_get(child_participants, bit)
                && lantern_bitlist_set(&out_proof->participants, bit, true) != 0) {
                return false;
            }
        }
    }

    if (child_count == 1u && raw_xmss_count == 0u) {
        (void)lantern_byte_list_resize(&out_proof->proof_data, 0u);
        return false;
    }

    if (child_count > 0u) {
        if (!state) {
            (void)lantern_byte_list_resize(&out_proof->proof_data, 0u);
            return false;
        }
        if (lantern_byte_list_resize(&out_proof->proof_data, LANTERN_AGG_PROOF_MAX_BYTES) != 0) {
            return false;
        }

        struct lantern_recursive_child_input *prepared_children =
            calloc(child_count, sizeof(*prepared_children));
        struct PQAggregatedSignatureChild *child_inputs =
            calloc(child_count, sizeof(*child_inputs));
        struct PQSignatureSchemePublicKey **raw_pubkey_handles =
            calloc(raw_xmss_count, sizeof(*raw_pubkey_handles));
        struct PQSignature **raw_signature_handles =
            calloc(raw_xmss_count, sizeof(*raw_signature_handles));
        struct PQRawXmssSignature *raw_inputs =
            calloc(raw_xmss_count, sizeof(*raw_inputs));
        if (!prepared_children
            || !child_inputs
            || (raw_xmss_count > 0u
                && (!raw_pubkey_handles || !raw_signature_handles || !raw_inputs))) {
            free(prepared_children);
            free(child_inputs);
            free(raw_pubkey_handles);
            free(raw_signature_handles);
            free(raw_inputs);
            (void)lantern_byte_list_resize(&out_proof->proof_data, 0u);
            return false;
        }

        bool ok = true;
        double elapsed = 0.0;
        for (size_t i = 0; i < child_count; ++i) {
            if (!prepare_recursive_child(
                    state,
                    &children[i],
                    message,
                    epoch,
                    &prepared_children[i],
                    &child_inputs[i])) {
                ok = false;
                break;
            }
        }

        double deserialize_started_seconds = get_time_seconds();
        for (size_t i = 0; ok && i < raw_xmss_count; ++i) {
            if (!raw_xmss[i].pubkey || !raw_xmss[i].signature) {
                ok = false;
                break;
            }

            enum PQSigningError pk_err = pq_public_key_deserialize(
                raw_xmss[i].pubkey,
                LANTERN_VALIDATOR_PUBKEY_SIZE,
                &raw_pubkey_handles[i]);
            if (pk_err != Success || !raw_pubkey_handles[i]) {
                ok = false;
                break;
            }

            enum PQSigningError sig_err = pq_signature_deserialize(
                raw_xmss[i].signature->bytes,
                sizeof(raw_xmss[i].signature->bytes),
                &raw_signature_handles[i]);
            if (sig_err != Success || !raw_signature_handles[i]) {
                ok = false;
                break;
            }

            raw_inputs[i].pubkey = raw_pubkey_handles[i];
            raw_inputs[i].signature = raw_signature_handles[i];
        }
        double deserialize_finished_seconds = get_time_seconds();
        if (g_stage_timings) {
            signature_add_stage_seconds(
                &g_stage_timings->key_sig_deserialize_seconds,
                signature_elapsed_seconds(deserialize_started_seconds, deserialize_finished_seconds));
        }

        if (ok) {
            double setup_started_seconds = get_time_seconds();
            ensure_xmss_prover_setup();
            log_pq_prover_setup_error_if_any();
            double setup_finished_seconds = get_time_seconds();
            if (g_stage_timings) {
                signature_add_stage_seconds(
                    &g_stage_timings->other_prover_setup_seconds,
                    signature_elapsed_seconds(setup_started_seconds, setup_finished_seconds));
            }
            uintptr_t written_len = 0u;
            double start = get_time_seconds();
            enum PQSigningError agg_err = pq_aggregate_signatures_recursive_unverified(
                child_inputs,
                child_count,
                raw_inputs,
                raw_xmss_count,
                message->bytes,
                LANTERN_ROOT_SIZE,
                epoch,
                LANTERN_AGGREGATED_SIGNATURE_PROOF_INVERSE_PROOF_SIZE,
                out_proof->proof_data.data,
                out_proof->proof_data.length,
                &written_len);
            double pq_finished_seconds = get_time_seconds();
            if (g_stage_timings) {
                signature_add_stage_seconds(
                    &g_stage_timings->pq_aggregate_seconds,
                    signature_elapsed_seconds(start, pq_finished_seconds));
            }
            if (agg_err != Success || written_len == 0u || written_len > out_proof->proof_data.length) {
                char *detail = pq_take_last_error_message();
                lantern_log_error(
                    "signature",
                    NULL,
                    "recursive aggregation failed child_count=%zu raw_xmss=%zu err=%d written=%zu buffer=%zu detail=%s",
                    child_count,
                    raw_xmss_count,
                    (int)agg_err,
                    (size_t)written_len,
                    (size_t)out_proof->proof_data.length,
                    pq_error_detail_or_dash(detail));
                pq_string_free(detail);
                ok = false;
            } else if (lantern_byte_list_resize(&out_proof->proof_data, (size_t)written_len) != 0) {
                ok = false;
            } else {
                elapsed = get_time_seconds() - start;
            }
        }

        for (size_t i = 0; i < raw_xmss_count; ++i) {
            if (raw_signature_handles && raw_signature_handles[i]) {
                pq_signature_free(raw_signature_handles[i]);
            }
            if (raw_pubkey_handles && raw_pubkey_handles[i]) {
                pq_public_key_free(raw_pubkey_handles[i]);
            }
        }
        for (size_t i = 0; i < child_count; ++i) {
            lantern_recursive_child_input_reset(&prepared_children[i]);
        }
        free(prepared_children);
        free(child_inputs);
        free(raw_pubkey_handles);
        free(raw_signature_handles);
        free(raw_inputs);

        if (!ok) {
            (void)lantern_byte_list_resize(&out_proof->proof_data, 0u);
        } else {
            size_t participant_count = aggregated_signature_proof_participant_count(out_proof);
            lean_metrics_record_pq_aggregated_signature_build(participant_count, elapsed);
        }
        return ok;
    }

    const uint8_t **pubkeys = calloc(raw_xmss_count, sizeof(*pubkeys));
    LanternSignature *signatures = calloc(raw_xmss_count, sizeof(*signatures));
    if ((raw_xmss_count > 0 && (!pubkeys || !signatures))) {
        free(pubkeys);
        free(signatures);
        return false;
    }
    for (size_t i = 0; i < raw_xmss_count; ++i) {
        if (!raw_xmss[i].pubkey || !raw_xmss[i].signature) {
            free(pubkeys);
            free(signatures);
            return false;
        }
        pubkeys[i] = raw_xmss[i].pubkey;
        signatures[i] = *raw_xmss[i].signature;
    }

    bool ok = lantern_signature_aggregate(
        pubkeys,
        signatures,
        raw_xmss_count,
        message,
        epoch,
        &out_proof->proof_data);
    free(signatures);
    free(pubkeys);
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
    if (count == 1u && proof->length == LANTERN_SIGNATURE_SIZE) {
        double start = get_time_seconds();
        int verify_rc = pq_verify_ssz(
            pubkeys[0],
            LANTERN_VALIDATOR_PUBKEY_SIZE,
            epoch,
            message->bytes,
            LANTERN_ROOT_SIZE,
            proof->data,
            proof->length);
        double elapsed = get_time_seconds() - start;
        lean_metrics_record_pq_aggregated_signature_verification(elapsed, verify_rc == 1);
        if (verify_rc != 1) {
            lantern_log_error(
                "signature",
                NULL,
                "single-signature aggregation verify failed rc=%d count=%zu epoch=%" PRIu64,
                verify_rc,
                count,
                epoch);
        }
        return verify_rc == 1;
    }

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
        ensure_xmss_verifier_setup();
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

bool lantern_signature_merge_block_type2_proof(
    const LanternState *state,
    const LanternBlock *block,
    const LanternAttestationSignatures *attestation_proofs,
    const LanternAggregatedSignatureProof *proposer_proof,
    LanternByteList *out_encoded_proof) {
    if (!state || !block || !attestation_proofs || !proposer_proof || !out_encoded_proof) {
        return false;
    }
    size_t attestation_count = block->body.attestations.length;
    if (attestation_proofs->length != attestation_count) {
        return false;
    }
    if (attestation_count > 0u
        && (!block->body.attestations.data || !attestation_proofs->data)) {
        return false;
    }

    size_t component_count = attestation_count + 1u;
    struct lantern_type2_component_work *work =
        calloc(component_count, sizeof(*work));
    struct PQTypeTwoComponent *components =
        calloc(component_count, sizeof(*components));
    struct PQAggregatedSignatureChild *entries =
        calloc(component_count, sizeof(*entries));
    LanternByteList raw_type2;
    lantern_byte_list_init(&raw_type2);

    bool ok = false;
    if (!work || !components || !entries) {
        goto cleanup;
    }
    if (!build_type2_merge_component_set_for_block(
            state,
            block,
            work,
            components,
            component_count)) {
        goto cleanup;
    }

    for (size_t i = 0; i < attestation_count; ++i) {
        const LanternAggregatedAttestation *attestation = &block->body.attestations.data[i];
        const LanternAggregatedSignatureProof *proof = &attestation_proofs->data[i];
        if (!bitlist_equal(&attestation->aggregation_bits, &proof->participants)) {
            goto cleanup;
        }
        if (proof->proof_data.length == 0u || !proof->proof_data.data) {
            goto cleanup;
        }
        entries[i].pubkeys = components[i].pubkeys;
        entries[i].pubkey_count = components[i].pubkey_count;
        entries[i].agg_bytes = proof->proof_data.data;
        entries[i].agg_len = proof->proof_data.length;
    }

    if (!singleton_participant_matches(
            &proposer_proof->participants,
            block->proposer_index)) {
        goto cleanup;
    }
    if (proposer_proof->proof_data.length == 0u || !proposer_proof->proof_data.data) {
        goto cleanup;
    }
    entries[attestation_count].pubkeys = components[attestation_count].pubkeys;
    entries[attestation_count].pubkey_count = components[attestation_count].pubkey_count;
    entries[attestation_count].agg_bytes = proposer_proof->proof_data.data;
    entries[attestation_count].agg_len = proposer_proof->proof_data.length;

    double setup_started_seconds = get_time_seconds();
    ensure_xmss_prover_setup();
    log_pq_prover_setup_error_if_any();
    double setup_finished_seconds = get_time_seconds();
    if (g_stage_timings) {
        signature_add_stage_seconds(
            &g_stage_timings->other_prover_setup_seconds,
            signature_elapsed_seconds(setup_started_seconds, setup_finished_seconds));
    }
    if (lantern_byte_list_resize(&raw_type2, LANTERN_AGG_PROOF_MAX_BYTES) != 0) {
        goto cleanup;
    }
    uintptr_t written_len = 0u;
    double merge_started_seconds = get_time_seconds();
    enum PQSigningError merge_rc = pq_merge_many_type_1(
        entries,
        component_count,
        LANTERN_AGGREGATED_SIGNATURE_PROOF_INVERSE_PROOF_SIZE,
        raw_type2.data,
        raw_type2.length,
        &written_len);
    double merge_finished_seconds = get_time_seconds();
    if (g_stage_timings) {
        signature_add_stage_seconds(
            &g_stage_timings->pq_aggregate_seconds,
            signature_elapsed_seconds(merge_started_seconds, merge_finished_seconds));
    }
    if (merge_rc != Success || written_len == 0u || written_len > raw_type2.length) {
        char *detail = pq_take_last_error_message();
        lantern_log_error(
            "signature",
            NULL,
            "block Type-2 merge failed err=%d entries=%zu written=%zu detail=%s",
            (int)merge_rc,
            component_count,
            (size_t)written_len,
            pq_error_detail_or_dash(detail));
        pq_string_free(detail);
        goto cleanup;
    }
    if (lantern_byte_list_resize(&raw_type2, (size_t)written_len) != 0) {
        goto cleanup;
    }
    double copy_started_seconds = get_time_seconds();
    ok = lantern_signature_wrap_type2_proof(&raw_type2, out_encoded_proof);
    double copy_finished_seconds = get_time_seconds();
    if (g_stage_timings) {
        signature_add_stage_seconds(
            &g_stage_timings->proof_copy_seconds,
            signature_elapsed_seconds(copy_started_seconds, copy_finished_seconds));
    }

cleanup:
    if (!ok) {
        (void)lantern_byte_list_resize(out_encoded_proof, 0u);
    }
    lantern_byte_list_reset(&raw_type2);
    reset_type2_component_set(work, component_count);
    free(entries);
    free(components);
    free(work);
    return ok;
}

bool lantern_signature_verify_block_type2_proof(
    const LanternState *state,
    const LanternBlock *block,
    const LanternByteList *encoded_proof) {
    if (!state || !block || !encoded_proof) {
        return false;
    }
    size_t attestation_count = block->body.attestations.length;
    if (attestation_count > 0u && !block->body.attestations.data) {
        return false;
    }

    size_t component_count = attestation_count + 1u;
    struct lantern_type2_component_work *work =
        calloc(component_count, sizeof(*work));
    struct PQTypeTwoComponent *components =
        calloc(component_count, sizeof(*components));
    struct PQTypeTwoMessageBinding *bindings =
        calloc(component_count, sizeof(*bindings));
    LanternRoot *message_roots = calloc(component_count, sizeof(*message_roots));
    LanternByteList raw_type2;
    lantern_byte_list_init(&raw_type2);

    bool ok = false;
    if (!work || !components || !bindings || !message_roots) {
        goto cleanup;
    }
    if (!lantern_signature_unwrap_type2_proof(encoded_proof, &raw_type2)) {
        goto cleanup;
    }
    if (!build_type2_component_set_for_block(
            state,
            block,
            work,
            components,
            bindings,
            message_roots,
            component_count)) {
        goto cleanup;
    }

    ensure_xmss_verifier_setup();
    double start = get_time_seconds();
    int verify_rc = pq_verify_type_2_with_messages(
        components,
        component_count,
        bindings,
        component_count,
        raw_type2.data,
        raw_type2.length);
    double elapsed = get_time_seconds() - start;
    lean_metrics_record_pq_block_aggregated_signatures_verification(elapsed);
    ok = (verify_rc == 1);
    if (!ok) {
        lantern_log_warn(
            "signature",
            &(const struct lantern_log_metadata){.has_slot = true, .slot = block->slot},
            "block Type-2 proof verification failed rc=%d components=%zu proof_len=%zu",
            verify_rc,
            component_count,
            encoded_proof->length);
    }

cleanup:
    lantern_byte_list_reset(&raw_type2);
    reset_type2_component_set(work, component_count);
    free(message_roots);
    free(bindings);
    free(components);
    free(work);
    return ok;
}

bool lantern_signature_split_block_type2_proof_by_message(
    const LanternState *state,
    const LanternBlock *block,
    const LanternByteList *encoded_proof,
    const LanternRoot *message,
    LanternByteList *out_type1_raw) {
    if (!state || !block || !encoded_proof || !message || !out_type1_raw) {
        return false;
    }
    size_t attestation_count = block->body.attestations.length;
    if (attestation_count > 0u && !block->body.attestations.data) {
        return false;
    }

    size_t component_count = attestation_count + 1u;
    struct lantern_type2_component_work *work =
        calloc(component_count, sizeof(*work));
    struct PQTypeTwoComponent *components =
        calloc(component_count, sizeof(*components));
    struct PQTypeTwoMessageBinding *bindings =
        calloc(component_count, sizeof(*bindings));
    LanternRoot *message_roots = calloc(component_count, sizeof(*message_roots));
    LanternByteList raw_type2;
    lantern_byte_list_init(&raw_type2);

    bool ok = false;
    if (!work || !components || !bindings || !message_roots) {
        goto cleanup;
    }
    if (!lantern_signature_unwrap_type2_proof(encoded_proof, &raw_type2)) {
        goto cleanup;
    }
    if (!build_type2_component_set_for_block(
            state,
            block,
            work,
            components,
            bindings,
            message_roots,
            component_count)) {
        goto cleanup;
    }

    ensure_xmss_prover_setup();
    log_pq_prover_setup_error_if_any();
    if (lantern_byte_list_resize(out_type1_raw, LANTERN_AGG_PROOF_MAX_BYTES) != 0) {
        goto cleanup;
    }
    uintptr_t written_len = 0u;
    enum PQSigningError split_rc = pq_split_type_2_by_message(
        components,
        component_count,
        raw_type2.data,
        raw_type2.length,
        message->bytes,
        LANTERN_ROOT_SIZE,
        LANTERN_AGGREGATED_SIGNATURE_PROOF_INVERSE_PROOF_SIZE,
        out_type1_raw->data,
        out_type1_raw->length,
        &written_len);
    if (split_rc != Success || written_len == 0u || written_len > out_type1_raw->length) {
        char *detail = pq_take_last_error_message();
        lantern_log_error(
            "signature",
            NULL,
            "block Type-2 split failed err=%d components=%zu written=%zu buffer=%zu detail=%s",
            (int)split_rc,
            component_count,
            (size_t)written_len,
            (size_t)out_type1_raw->length,
            pq_error_detail_or_dash(detail));
        pq_string_free(detail);
        goto cleanup;
    }
    ok = lantern_byte_list_resize(out_type1_raw, (size_t)written_len) == 0;

cleanup:
    if (!ok) {
        (void)lantern_byte_list_resize(out_type1_raw, 0u);
    }
    lantern_byte_list_reset(&raw_type2);
    reset_type2_component_set(work, component_count);
    free(message_roots);
    free(bindings);
    free(components);
    free(work);
    return ok;
}
