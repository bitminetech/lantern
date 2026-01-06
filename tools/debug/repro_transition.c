#include "lantern/consensus/state.h"
#include "lantern/consensus/ssz.h"
#include "lantern/consensus/signature.h"
#include "lantern/consensus/containers.h"
#include "lantern/consensus/hash.h"
#include "lantern/storage/storage.h"
#include "lantern/support/log.h"
#include "lantern/support/strings.h"

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <inttypes.h>
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
    uint8_t *buffer = malloc((size_t)size);
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

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "usage: %s <state-dir> <block-ssz>\\n", argv[0]);
        return 1;
    }
    const char *state_dir = argv[1];
    const char *block_path = argv[2];

    lantern_log_set_level(LANTERN_LOG_LEVEL_DEBUG);
    lantern_log_set_node_id("repro");

    LanternState state;
    lantern_state_init(&state);
    if (lantern_storage_load_state(state_dir, &state) != 0) {
        fprintf(stderr, "failed to load state from %s\\n", state_dir);
        lantern_state_reset(&state);
        return 1;
    }

    LanternRoot header_root;
    if (lantern_hash_tree_root_block_header(&state.latest_block_header, &header_root) == 0) {
        char root_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
        if (lantern_bytes_to_hex(
                header_root.bytes,
                LANTERN_ROOT_SIZE,
                root_hex,
                sizeof(root_hex),
                1)
            == 0) {
            fprintf(
                stderr,
                "current header root=%s slot=%" PRIu64 "\\n",
                root_hex,
                state.latest_block_header.slot);
        }
    }
    LanternRoot state_root;
    if (lantern_hash_tree_root_state(&state, &state_root) == 0) {
        char root_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
        if (lantern_bytes_to_hex(
                state_root.bytes,
                LANTERN_ROOT_SIZE,
                root_hex,
                sizeof(root_hex),
                1)
            == 0) {
            fprintf(stderr, "current state root=%s\\n", root_hex);
        }
    }
    LanternBlock anchor_block;
    memset(&anchor_block, 0, sizeof(anchor_block));
    anchor_block.slot = state.latest_block_header.slot;
    anchor_block.proposer_index = state.latest_block_header.proposer_index;
    anchor_block.parent_root = state.latest_block_header.parent_root;
    anchor_block.state_root = state_root;
    lantern_block_body_init(&anchor_block.body);
    LanternRoot anchor_root;
    if (lantern_hash_tree_root_block(&anchor_block, &anchor_root) == 0) {
        char anchor_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
        if (lantern_bytes_to_hex(
                anchor_root.bytes,
                LANTERN_ROOT_SIZE,
                anchor_hex,
                sizeof(anchor_hex),
                1)
            == 0) {
            fprintf(stderr, "computed anchor root=%s\\n", anchor_hex);
        }
    }
    lantern_block_body_reset(&anchor_block.body);
    if (state.historical_block_hashes.length > 0 && state.historical_block_hashes.items) {
        LanternRoot first_hist = state.historical_block_hashes.items[0];
        char hist_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
        if (lantern_bytes_to_hex(
                first_hist.bytes,
                LANTERN_ROOT_SIZE,
                hist_hex,
                sizeof(hist_hex),
                1)
            == 0) {
            fprintf(
                stderr,
                "historical_block_hashes[0]=%s (len=%zu)\\n",
                hist_hex,
                state.historical_block_hashes.length);
        }
    }

    uint8_t *data = NULL;
    size_t data_len = 0;
    if (read_file(block_path, &data, &data_len) != 0) {
        fprintf(stderr, "failed to read block file %s\\n", block_path);
        lantern_state_reset(&state);
        return 1;
    }

    LanternSignedBlock signed_block;
    lantern_signed_block_with_attestation_init(&signed_block);
    if (lantern_ssz_decode_signed_block(&signed_block, data, data_len) != 0) {
        fprintf(stderr, "failed to decode signed block\\n");
        free(data);
        lantern_signed_block_with_attestation_reset(&signed_block);
        lantern_state_reset(&state);
        return 1;
    }
    free(data);
    (void)lantern_attestation_signatures_resize(&signed_block.signatures.attestation_signatures, 0);
    memset(signed_block.signatures.proposer_signature.bytes, 0, LANTERN_SIGNATURE_SIZE);

    LanternRoot decoded_parent = signed_block.message.block.parent_root;
    LanternRoot decoded_state_root = signed_block.message.block.state_root;
    LanternRoot decoded_root;
    memset(&decoded_root, 0, sizeof(decoded_root));
    if (lantern_hash_tree_root_block(&signed_block.message.block, &decoded_root) != 0) {
        fprintf(stderr, "failed to hash decoded block\\n");
        lantern_signed_block_with_attestation_reset(&signed_block);
        lantern_state_reset(&state);
        return 1;
    }
    char parent_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    char state_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    char root_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    parent_hex[0] = '\0';
    state_hex[0] = '\0';
    root_hex[0] = '\0';
    lantern_bytes_to_hex(decoded_parent.bytes, LANTERN_ROOT_SIZE, parent_hex, sizeof(parent_hex), 1);
    lantern_bytes_to_hex(decoded_state_root.bytes, LANTERN_ROOT_SIZE, state_hex, sizeof(state_hex), 1);
    lantern_bytes_to_hex(decoded_root.bytes, LANTERN_ROOT_SIZE, root_hex, sizeof(root_hex), 1);
    fprintf(
        stderr,
        "decoded block slot=%" PRIu64 " proposer=%" PRIu64 "\\n",
        signed_block.message.block.slot,
        signed_block.message.block.proposer_index);
    fprintf(stderr, "decoded parent_root=%s\\n", parent_hex[0] ? parent_hex : "0x0");
    fprintf(stderr, "decoded state_root=%s\\n", state_hex[0] ? state_hex : "0x0");
    fprintf(stderr, "decoded block_root=%s\\n", root_hex[0] ? root_hex : "0x0");

    int rc = lantern_state_transition(&state, &signed_block);
    lantern_signed_block_with_attestation_reset(&signed_block);
    fprintf(stderr, "lantern_state_transition -> %d\\n", rc);

    lantern_state_reset(&state);
    return rc == 0 ? 0 : 2;
}
