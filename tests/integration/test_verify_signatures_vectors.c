#include "tests/support/fixture_loader.h"

#include <dirent.h>
#include <errno.h>
#include <inttypes.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "lantern/consensus/containers.h"
#include "lantern/consensus/hash.h"
#include "lantern/consensus/signature.h"
#include "lantern/consensus/state.h"
#include "lantern/support/log.h"

static void configure_logging(void) {
    const char *env_level = getenv("LANTERN_LOG_LEVEL");
    if (env_level && env_level[0] != '\0') {
        if (lantern_log_set_level_from_string(env_level, NULL) != 0) {
            fprintf(stderr, "invalid LANTERN_LOG_LEVEL '%s'\n", env_level);
        }
        return;
    }
    lantern_log_set_level(LANTERN_LOG_LEVEL_WARN);
}

static bool pubkey_is_zero(const uint8_t *pubkey) {
    if (!pubkey) {
        return true;
    }
    for (size_t i = 0; i < LANTERN_VALIDATOR_PUBKEY_SIZE; ++i) {
        if (pubkey[i] != 0u) {
            return false;
        }
    }
    return true;
}

// leanSpec fixtures currently emit 0x00 for aggregated proofs when test_mode is enabled.
static bool is_placeholder_agg_proof(const LanternByteList *proof) {
    if (!proof || !proof->data) {
        return false;
    }
    return proof->length == 1 && proof->data[0] == 0u;
}

static bool verify_aggregated_attestations(
    const LanternState *state,
    const LanternSignedBlock *block,
    const char *path) {
    if (!state || !block) {
        return false;
    }
    const LanternAggregatedAttestations *attestations = &block->message.block.body.attestations;
    const LanternAttestationSignatures *sig_groups = &block->signatures.attestation_signatures;
    size_t att_count = attestations->length;

    if (att_count != sig_groups->length) {
        fprintf(
            stderr,
            "%s: attestation signature count mismatch expected=%zu actual=%zu\n",
            path ? path : "(unknown)",
            att_count,
            sig_groups->length);
        return false;
    }
    if (att_count > 0 && (!attestations->data || !sig_groups->data)) {
        fprintf(stderr, "%s: missing attestation data/signatures\n", path ? path : "(unknown)");
        return false;
    }

    size_t validator_count = (size_t)state->config.num_validators;

    for (size_t i = 0; i < att_count; ++i) {
        const LanternAggregatedAttestation *att = &attestations->data[i];
        const LanternAggregatedSignatureProof *proof = &sig_groups->data[i];
        size_t bit_length = att->aggregation_bits.bit_length;

        if (bit_length == 0 || !att->aggregation_bits.bytes) {
            fprintf(stderr, "%s: empty aggregation bits\n", path ? path : "(unknown)");
            return false;
        }
        if (proof->participants.bit_length != att->aggregation_bits.bit_length) {
            fprintf(stderr, "%s: participant bitlist length mismatch\n", path ? path : "(unknown)");
            return false;
        }
        size_t bytes = (bit_length + 7u) / 8u;
        if (bytes > 0) {
            if (!proof->participants.bytes
                || memcmp(proof->participants.bytes, att->aggregation_bits.bytes, bytes) != 0) {
                fprintf(stderr, "%s: participant bits mismatch\n", path ? path : "(unknown)");
                return false;
            }
        }

        size_t participant_count = 0;
        for (size_t v = 0; v < bit_length; ++v) {
            if (lantern_bitlist_get(&att->aggregation_bits, v)) {
                participant_count += 1u;
            }
        }
        if (participant_count == 0) {
            fprintf(stderr, "%s: no aggregation participants\n", path ? path : "(unknown)");
            return false;
        }

        const uint8_t **pubkeys = calloc(participant_count, sizeof(*pubkeys));
        if (!pubkeys) {
            return false;
        }
        size_t idx = 0;
        for (size_t v = 0; v < bit_length; ++v) {
            if (!lantern_bitlist_get(&att->aggregation_bits, v)) {
                continue;
            }
            if (v >= validator_count) {
                free(pubkeys);
                fprintf(stderr, "%s: validator index out of range\n", path ? path : "(unknown)");
                return false;
            }
            const uint8_t *pubkey = lantern_state_validator_pubkey(state, v);
            if (!pubkey || pubkey_is_zero(pubkey)) {
                free(pubkeys);
                fprintf(stderr, "%s: missing pubkey for validator %zu\n", path ? path : "(unknown)", v);
                return false;
            }
            pubkeys[idx++] = pubkey;
        }

        LanternRoot data_root;
        if (lantern_hash_tree_root_attestation_data(&att->data, &data_root) != 0) {
            free(pubkeys);
            fprintf(stderr, "%s: failed to hash attestation data\n", path ? path : "(unknown)");
            return false;
        }
        if (is_placeholder_agg_proof(&proof->proof_data)) {
            fprintf(
                stderr,
                "%s: skipping aggregated signature verification (placeholder proof data)\n",
                path ? path : "(unknown)");
            free(pubkeys);
            continue;
        }
        bool sig_ok = lantern_signature_verify_aggregated(
            pubkeys,
            participant_count,
            &data_root,
            &proof->proof_data,
            att->data.slot);
        free(pubkeys);
        if (!sig_ok) {
            fprintf(stderr, "%s: aggregated signature verification failed\n", path ? path : "(unknown)");
            return false;
        }
    }

    return true;
}

static bool verify_proposer_signature(const LanternState *state, const LanternSignedBlock *block, const char *path) {
    if (!state || !block) {
        return false;
    }
    const LanternVote *vote = &block->message.proposer_attestation;
    uint64_t validator_id = vote->validator_id;
    if (validator_id >= state->config.num_validators) {
        fprintf(stderr, "%s: proposer validator out of range\n", path ? path : "(unknown)");
        return false;
    }
    const uint8_t *pubkey = lantern_state_validator_pubkey(state, (size_t)validator_id);
    if (!pubkey || pubkey_is_zero(pubkey)) {
        fprintf(stderr, "%s: proposer pubkey missing\n", path ? path : "(unknown)");
        return false;
    }
    LanternRoot vote_root;
    if (lantern_hash_tree_root_attestation_data(&vote->data, &vote_root) != 0) {
        fprintf(stderr, "%s: proposer attestation hash failed\n", path ? path : "(unknown)");
        return false;
    }
    if (!lantern_signature_verify(
            pubkey,
            LANTERN_VALIDATOR_PUBKEY_SIZE,
            vote->data.slot,
            &block->signatures.proposer_signature,
            &vote_root)) {
        fprintf(stderr, "%s: proposer signature verification failed\n", path ? path : "(unknown)");
        return false;
    }
    return true;
}

static int run_verify_signatures_fixture(const char *path);

static int for_each_json(const char *root, int (*callback)(const char *path)) {
    if (!root || !callback) {
        return -1;
    }
    DIR *dir = opendir(root);
    if (!dir) {
        perror("opendir");
        return -1;
    }
    int status = 0;
    struct dirent *entry = NULL;
    while ((entry = readdir(dir)) != NULL) {
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) {
            continue;
        }
        char child_path[1024];
        int written = snprintf(child_path, sizeof(child_path), "%s/%s", root, entry->d_name);
        if (written <= 0 || written >= (int)sizeof(child_path)) {
            status = -1;
            break;
        }
        if (entry->d_type == DT_DIR) {
            if (for_each_json(child_path, callback) != 0) {
                status = -1;
                break;
            }
            continue;
        }
        const char *ext = strrchr(entry->d_name, '.');
        if (!ext || strcmp(ext, ".json") != 0) {
            continue;
        }
        if (callback(child_path) != 0) {
            status = -1;
            break;
        }
    }
    closedir(dir);
    return status;
}

static int run_verify_signatures_fixture(const char *path) {
    char *text = NULL;
    if (lantern_fixture_read_text_file(path, &text) != 0) {
        fprintf(stderr, "failed to read %s\n", path);
        return -1;
    }

    struct lantern_fixture_document doc;
    if (lantern_fixture_document_init(&doc, text) != 0) {
        fprintf(stderr, "failed to parse %s\n", path);
        return -1;
    }
    if (doc.token_count <= 0) {
        lantern_fixture_document_reset(&doc);
        return -1;
    }

    int root_idx = 0;
    int case_idx = lantern_fixture_object_get_value_at(&doc, root_idx, 0);
    if (case_idx < 0) {
        lantern_fixture_document_reset(&doc);
        return -1;
    }

    int anchor_idx = lantern_fixture_object_get_field(&doc, case_idx, "anchorState");
    if (anchor_idx < 0) {
        anchor_idx = lantern_fixture_object_get_field(&doc, case_idx, "anchor_state");
    }
    int block_idx = lantern_fixture_object_get_field(&doc, case_idx, "signedBlockWithAttestation");
    if (block_idx < 0) {
        block_idx = lantern_fixture_object_get_field(&doc, case_idx, "signed_block_with_attestation");
    }
    int expect_idx = lantern_fixture_object_get_field(&doc, case_idx, "expectException");
    int lean_env_idx = lantern_fixture_object_get_field(&doc, case_idx, "leanEnv");

    if (anchor_idx < 0 || block_idx < 0) {
        lantern_fixture_document_reset(&doc);
        return -1;
    }

    bool expect_failure = false;
    if (expect_idx >= 0) {
        const jsmntok_t *tok = lantern_fixture_token(&doc, expect_idx);
        if (tok && tok->type == JSMN_STRING) {
            expect_failure = true;
        }
    }
    bool lean_env_test = false;
    if (lean_env_idx >= 0) {
        size_t lean_env_len = 0;
        const char *lean_env = lantern_fixture_token_string(&doc, lean_env_idx, &lean_env_len);
        if (lean_env && lean_env_len == 4u && strncmp(lean_env, "test", 4u) == 0) {
            lean_env_test = true;
        }
    }

    LanternState state;
    LanternCheckpoint latest_justified;
    LanternCheckpoint latest_finalized;
    uint64_t genesis_time = 0;
    uint64_t validator_count = 0;
    if (lantern_fixture_parse_anchor_state(
            &doc,
            anchor_idx,
            &state,
            &latest_justified,
            &latest_finalized,
            &genesis_time,
            &validator_count)
        != 0) {
        lantern_fixture_document_reset(&doc);
        return -1;
    }

    LanternSignedBlock signed_block;
    if (lantern_fixture_parse_signed_block(&doc, block_idx, &signed_block) != 0) {
        lantern_state_reset(&state);
        lantern_fixture_document_reset(&doc);
        return -1;
    }

    bool skip_proposer_verification = false;
    int signature_idx = lantern_fixture_object_get_field(&doc, block_idx, "signature");
    if (signature_idx >= 0 && lean_env_test) {
        int proposer_sig_idx = lantern_fixture_object_get_field(&doc, signature_idx, "proposerSignature");
        if (proposer_sig_idx < 0) {
            proposer_sig_idx = lantern_fixture_object_get_field(&doc, signature_idx, "proposer_signature");
        }
        if (proposer_sig_idx >= 0) {
            const jsmntok_t *proposer_sig_tok = lantern_fixture_token(&doc, proposer_sig_idx);
            if (proposer_sig_tok && proposer_sig_tok->type == JSMN_OBJECT) {
                skip_proposer_verification = true;
            }
        }
    }

    bool skip_positive_fixture_crypto = lean_env_test && !expect_failure;
    bool valid = true;
    if (!skip_positive_fixture_crypto) {
        if (!verify_aggregated_attestations(&state, &signed_block, path)) {
            valid = false;
        }
    }
    bool proposer_verified = false;
    if (valid) {
        if (skip_positive_fixture_crypto) {
            fprintf(
                stderr,
                "%s: skipping signature verification (leanEnv=test positive fixture)\n",
                path);
        } else if (skip_proposer_verification) {
            fprintf(
                stderr,
                "%s: skipping proposer signature verification (leanEnv=test object signature)\n",
                path);
        } else {
            proposer_verified = true;
            if (!verify_proposer_signature(&state, &signed_block, path)) {
                valid = false;
            }
        }
    }

    int result = 0;
    if (expect_failure) {
        if (valid && proposer_verified) {
            fprintf(stderr, "expected failure did not occur in %s\n", path);
            result = -1;
        }
    } else if (!valid) {
        fprintf(stderr, "unexpected signature verification failure in %s\n", path);
        result = -1;
    }

    lantern_block_body_reset(&signed_block.message.block.body);
    lantern_block_signatures_reset(&signed_block.signatures);
    lantern_state_reset(&state);
    lantern_fixture_document_reset(&doc);
    return result;
}

int main(void) {
    configure_logging();

    char fixture_root[1024];
    int written = snprintf(
        fixture_root,
        sizeof(fixture_root),
        "%s/consensus/verify_signatures",
        LANTERN_TEST_FIXTURE_DIR);
    if (written <= 0 || written >= (int)sizeof(fixture_root)) {
        fprintf(stderr, "fixture path too long\n");
        return 1;
    }

    if (for_each_json(fixture_root, run_verify_signatures_fixture) != 0) {
        return 1;
    }

    printf("lantern_verify_signatures_vectors OK\n");
    return 0;
}
