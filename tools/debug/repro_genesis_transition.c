#include "lantern/consensus/containers.h"
#include "lantern/consensus/hash.h"
#include "lantern/consensus/signature.h"
#include "lantern/consensus/state.h"
#include "lantern/consensus/ssz.h"
#include "lantern/support/log.h"
#include "lantern/support/strings.h"

#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int read_file(const char *path, uint8_t **out_data, size_t *out_len) {
    if (!path || !out_data || !out_len) {
        return -1;
    }
    FILE *fp = fopen(path, "rb");
    if (!fp) {
        perror("fopen");
        return -1;
    }
    if (fseek(fp, 0, SEEK_END) != 0) {
        fclose(fp);
        return -1;
    }
    long size = ftell(fp);
    if (size < 0) {
        fclose(fp);
        return -1;
    }
    if (fseek(fp, 0, SEEK_SET) != 0) {
        fclose(fp);
        return -1;
    }
    uint8_t *buffer = (uint8_t *)malloc((size_t)size);
    if (!buffer) {
        fclose(fp);
        return -1;
    }
    size_t read = fread(buffer, 1, (size_t)size, fp);
    fclose(fp);
    if (read != (size_t)size) {
        free(buffer);
        return -1;
    }
    *out_data = buffer;
    *out_len = (size_t)size;
    return 0;
}

static void log_root(const char *label, const LanternRoot *root) {
    char hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    if (lantern_bytes_to_hex(root->bytes, LANTERN_ROOT_SIZE, hex, sizeof(hex), 1) != 0) {
        hex[0] = '\0';
    }
    fprintf(stderr, "%s=%s\n", label, hex[0] ? hex : "0x0");
}

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "usage: %s <state-ssz> <block-ssz>\n", argv[0]);
        return 1;
    }
    const char *state_path = argv[1];
    const char *block_path = argv[2];

    lantern_log_set_level(LANTERN_LOG_LEVEL_DEBUG);
    lantern_log_set_node_id("repro_genesis");

    uint8_t *state_bytes = NULL;
    size_t state_len = 0;
    if (read_file(state_path, &state_bytes, &state_len) != 0) {
        fprintf(stderr, "failed to read %s\n", state_path);
        return 1;
    }

    LanternState state;
    lantern_state_init(&state);
    if (lantern_ssz_decode_state(&state, state_bytes, state_len) != 0) {
        fprintf(stderr, "failed to decode state SSZ\n");
        free(state_bytes);
        lantern_state_reset(&state);
        return 1;
    }
    free(state_bytes);

    if (state.config.num_validators == 0) {
        fprintf(stderr, "state missing validators\n");
        lantern_state_reset(&state);
        return 1;
    }
    if (lantern_state_prepare_validator_votes(&state, state.config.num_validators) != 0) {
        fprintf(stderr, "failed to prepare validator votes\n");
        lantern_state_reset(&state);
        return 1;
    }

    LanternRoot header_root;
    if (lantern_hash_tree_root_block_header(&state.latest_block_header, &header_root) == 0) {
        log_root("header_root", &header_root);
    }
    LanternRoot state_root;
    if (lantern_hash_tree_root_state(&state, &state_root) == 0) {
        log_root("computed_state_root", &state_root);
    }
    log_root("stored_state_root", &state.latest_block_header.state_root);

    uint8_t *block_bytes = NULL;
    size_t block_len = 0;
    if (read_file(block_path, &block_bytes, &block_len) != 0) {
        fprintf(stderr, "failed to read block %s\n", block_path);
        lantern_state_reset(&state);
        return 1;
    }

    LanternSignedBlock signed_block;
    lantern_signed_block_with_attestation_init(&signed_block);
    if (lantern_ssz_decode_signed_block(&signed_block, block_bytes, block_len) != 0) {
        fprintf(stderr, "failed to decode signed block\n");
        free(block_bytes);
        lantern_signed_block_with_attestation_reset(&signed_block);
        lantern_state_reset(&state);
        return 1;
    }
    free(block_bytes);
    (void)lantern_attestation_signatures_resize(&signed_block.signatures.attestation_signatures, 0);
    memset(signed_block.signatures.proposer_signature.bytes, 0, LANTERN_SIGNATURE_SIZE);

    fprintf(
        stderr,
        "decoded block slot=%" PRIu64 " proposer=%" PRIu64 "\n",
        signed_block.message.block.slot,
        signed_block.message.block.proposer_index);
    log_root("block_parent_root", &signed_block.message.block.parent_root);
    log_root("block_state_root", &signed_block.message.block.state_root);

    LanternRoot block_root;
    if (lantern_hash_tree_root_block(&signed_block.message.block, &block_root) == 0) {
        log_root("block_root", &block_root);
    }
    log_root("pre.latest_justified_root", &state.latest_justified.root);
    log_root("pre.latest_finalized_root", &state.latest_finalized.root);

    int rc = lantern_state_transition(&state, &signed_block);
    fprintf(stderr, "lantern_state_transition -> %d\n", rc);
    log_root("post.latest_block_parent", &state.latest_block_header.parent_root);
    log_root("post.latest_block_state_root", &state.latest_block_header.state_root);
    log_root("post.latest_justified_root", &state.latest_justified.root);
    log_root("post.latest_finalized_root", &state.latest_finalized.root);
    if (state.historical_block_hashes.length > 0 && state.historical_block_hashes.items) {
        log_root("post.historical[0]", &state.historical_block_hashes.items[0]);
    }
    fprintf(stderr, "post.justified_slots.bits=%zu\n", state.justified_slots.bit_length);

    if (rc == 0) {
        LanternRoot alt_root;
        if (state.historical_block_hashes.length > 0 && state.historical_block_hashes.items) {
            LanternRoot saved = state.historical_block_hashes.items[0];
            state.historical_block_hashes.items[0] = signed_block.message.block.parent_root;
            if (lantern_hash_tree_root_state(&state, &alt_root) == 0) {
                log_root("patched_hist_state_root", &alt_root);
            }
            state.historical_block_hashes.items[0] = block_root;
            if (lantern_hash_tree_root_state(&state, &alt_root) == 0) {
                log_root("patched_hist_block_root_state_root", &alt_root);
            }
            state.historical_block_hashes.items[0] = saved;
        }
        LanternCheckpoint saved_justified = state.latest_justified;
        LanternCheckpoint saved_finalized = state.latest_finalized;
        state.latest_justified.root = signed_block.message.block.parent_root;
        state.latest_finalized.root = signed_block.message.block.parent_root;
        if (lantern_hash_tree_root_state(&state, &alt_root) == 0) {
            log_root("patched_checkpoint_state_root", &alt_root);
        }
        state.latest_justified = saved_justified;
        state.latest_finalized = saved_finalized;
    }

    lantern_signed_block_with_attestation_reset(&signed_block);
    lantern_state_reset(&state);
    return rc == 0 ? 0 : 2;
}
