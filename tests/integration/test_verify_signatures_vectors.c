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
    int block_idx = lantern_fixture_object_get_field(&doc, case_idx, "signedBlock");
    if (block_idx < 0) {
        block_idx = lantern_fixture_object_get_field(&doc, case_idx, "signed_block");
    }
    if (block_idx < 0) {
        block_idx = lantern_fixture_object_get_field(&doc, case_idx, "signedBlockWithAttestation");
    }
    if (block_idx < 0) {
        block_idx = lantern_fixture_object_get_field(&doc, case_idx, "signed_block_with_attestation");
    }
    int expect_idx = lantern_fixture_object_get_field(&doc, case_idx, "expectException");
    int rejection_idx = lantern_fixture_object_get_field(&doc, case_idx, "rejectionReason");

    if (anchor_idx < 0 || block_idx < 0) {
        lantern_fixture_document_reset(&doc);
        return -1;
    }
    if (lantern_fixture_object_get_field(&doc, block_idx, "proof") < 0) {
        lantern_fixture_document_reset(&doc);
        return 0;
    }

    bool expect_failure = false;
    if (expect_idx >= 0) {
        const jsmntok_t *tok = lantern_fixture_token(&doc, expect_idx);
        if (tok && tok->type == JSMN_STRING) {
            expect_failure = true;
        }
    }
    if (rejection_idx >= 0) {
        const jsmntok_t *tok = lantern_fixture_token(&doc, rejection_idx);
        if (tok && tok->type == JSMN_STRING) {
            expect_failure = true;
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

    bool valid = signed_block.proof.length > 0u
        && signed_block.proof.data
        && lantern_signature_verify_block_type2_proof(&state, &signed_block.block, &signed_block.proof);

    int result = 0;
    if (expect_failure) {
        if (valid) {
            fprintf(stderr, "expected failure did not occur in %s\n", path);
            result = -1;
        }
    } else if (!valid) {
        fprintf(stderr, "unexpected signature verification failure in %s\n", path);
        result = -1;
    }

    lantern_signed_block_reset(&signed_block);
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
        "%s/verify_signatures",
        LANTERN_CONSENSUS_FIXTURE_DIR);
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
