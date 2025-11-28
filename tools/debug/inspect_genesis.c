#include "lantern/consensus/hash.h"
#include "lantern/consensus/ssz.h"
#include "lantern/consensus/state.h"
#include "lantern/support/strings.h"

#include <errno.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int read_file(const char *path, uint8_t **out_data, size_t *out_len) {
    FILE *fp = fopen(path, "rb");
    if (!fp) {
        fprintf(stderr, "failed to open %s: %s\n", path, strerror(errno));
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

static void format_root(const LanternRoot *root, char *out, size_t out_len) {
    if (lantern_bytes_to_hex(root->bytes, LANTERN_ROOT_SIZE, out, out_len, 1) != 0) {
        if (out_len > 0) {
            out[0] = '\0';
        }
    }
}

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: %s /path/to/genesis.ssz\n", argv[0]);
        return 1;
    }

    uint8_t *data = NULL;
    size_t len = 0;
    if (read_file(argv[1], &data, &len) != 0) {
        return 1;
    }

    LanternState state;
    lantern_state_init(&state);

    if (lantern_ssz_decode_state(&state, data, len) != 0) {
        fprintf(stderr, "failed to decode genesis state\n");
        free(data);
        lantern_state_reset(&state);
        return 1;
    }
    free(data);

    LanternRoot computed_state_root;
    LanternRoot header_root;
    LanternRoot config_root;
    LanternRoot checkpoint_just_root;
    LanternRoot checkpoint_fin_root;
    LanternRoot hist_root;
    LanternRoot just_slots_root;
    LanternRoot validators_root;
    LanternRoot just_roots_root;
    LanternRoot just_validators_root;

    if (lantern_hash_tree_root_state(&state, &computed_state_root) != 0) {
        fprintf(stderr, "failed to hash state\n");
        lantern_state_reset(&state);
        return 1;
    }
    if (lantern_hash_tree_root_block_header(&state.latest_block_header, &header_root) != 0) {
        memset(&header_root, 0, sizeof(header_root));
    }
    if (lantern_hash_tree_root_config(&state.config, &config_root) != 0) {
        memset(&config_root, 0, sizeof(config_root));
    }
    if (lantern_hash_tree_root_checkpoint(&state.latest_justified, &checkpoint_just_root) != 0) {
        memset(&checkpoint_just_root, 0, sizeof(checkpoint_just_root));
    }
    if (lantern_hash_tree_root_checkpoint(&state.latest_finalized, &checkpoint_fin_root) != 0) {
        memset(&checkpoint_fin_root, 0, sizeof(checkpoint_fin_root));
    }

    char root_hex[2 * LANTERN_ROOT_SIZE + 3];
    char header_hex[sizeof(root_hex)];
    char header_state_hex[sizeof(root_hex)];
    char parent_hex[sizeof(root_hex)];
    char justified_hex[sizeof(root_hex)];
    char finalized_hex[sizeof(root_hex)];
    char body_root_hex[sizeof(root_hex)];
    char anchor_root_hex[sizeof(root_hex)];
    char empty_body_root_hex[sizeof(root_hex)];
    char config_root_hex[sizeof(root_hex)];
    char just_ckpt_hex[sizeof(root_hex)];
    char fin_ckpt_hex[sizeof(root_hex)];
    char validators_root_hex[sizeof(root_hex)];

    format_root(&computed_state_root, root_hex, sizeof(root_hex));
    format_root(&header_root, header_hex, sizeof(header_hex));
    format_root(&state.latest_block_header.state_root, header_state_hex, sizeof(header_state_hex));
    format_root(&state.latest_block_header.parent_root, parent_hex, sizeof(parent_hex));
    format_root(&state.latest_justified.root, justified_hex, sizeof(justified_hex));
    format_root(&state.latest_finalized.root, finalized_hex, sizeof(finalized_hex));
    format_root(&state.latest_block_header.body_root, body_root_hex, sizeof(body_root_hex));
    format_root(&config_root, config_root_hex, sizeof(config_root_hex));
    format_root(&checkpoint_just_root, just_ckpt_hex, sizeof(just_ckpt_hex));
    format_root(&checkpoint_fin_root, fin_ckpt_hex, sizeof(fin_ckpt_hex));
    format_root(&state.validator_registry_root, validators_root_hex, sizeof(validators_root_hex));

    /* Compute empty body root for comparison with leanSpec */
    LanternBlockBody empty_body;
    lantern_block_body_init(&empty_body);
    LanternRoot empty_body_root;
    if (lantern_hash_tree_root_block_body(&empty_body, &empty_body_root) != 0) {
        memset(&empty_body_root, 0, sizeof(empty_body_root));
    }
    lantern_block_body_reset(&empty_body);
    format_root(&empty_body_root, empty_body_root_hex, sizeof(empty_body_root_hex));

    /* Compute anchor block root (as per leanSpec Store.get_forkchoice_store):
     * The anchor block MUST have state_root = hash_tree_root(state)
     */
    LanternBlock anchor_block;
    memset(&anchor_block, 0, sizeof(anchor_block));
    anchor_block.slot = state.latest_block_header.slot;
    anchor_block.proposer_index = state.latest_block_header.proposer_index;
    anchor_block.parent_root = state.latest_block_header.parent_root;
    anchor_block.state_root = computed_state_root;  /* Use ACTUAL state root */
    lantern_block_body_init(&anchor_block.body);    /* Empty body */

    LanternRoot anchor_root;
    if (lantern_hash_tree_root_block(&anchor_block, &anchor_root) != 0) {
        memset(&anchor_root, 0, sizeof(anchor_root));
    }
    lantern_block_body_reset(&anchor_block.body);
    format_root(&anchor_root, anchor_root_hex, sizeof(anchor_root_hex));

    printf("config.num_validators=%" PRIu64 "\n", state.config.num_validators);
    printf("config.genesis_time=%" PRIu64 "\n", state.config.genesis_time);
    printf("state.slot=%" PRIu64 "\n", state.slot);
    printf("latest_block_header.slot=%" PRIu64 "\n", state.latest_block_header.slot);
    printf("latest_block_header.proposer=%" PRIu64 "\n", state.latest_block_header.proposer_index);
    printf("latest_block_header.parent_root=%s\n", parent_hex);
    printf("latest_block_header.state_root=%s\n", header_state_hex);
    printf("latest_block_header.body_root=%s\n", body_root_hex);
    printf("header_root (with zero state_root)=%s\n", header_hex);
    printf("computed_state_root=%s\n", root_hex);
    printf("empty_body_root (Lantern computed)=%s\n", empty_body_root_hex);
    printf("anchor_block_root (with actual state_root)=%s\n", anchor_root_hex);
    printf("latest_justified.slot=%" PRIu64 " root=%s\n", state.latest_justified.slot, justified_hex);
    printf("latest_finalized.slot=%" PRIu64 " root=%s\n", state.latest_finalized.slot, finalized_hex);
    printf("historical_block_hashes=%zu entries\n", state.historical_block_hashes.length);
    printf("justified_slots bits=%zu\n", state.justified_slots.bit_length);
    printf("justification_roots=%zu entries\n", state.justification_roots.length);
    printf("\n=== Field roots for hash_tree_root(state) comparison with leanSpec ===\n");
    printf("config_root=%s\n", config_root_hex);
    printf("latest_block_header_root=%s\n", header_hex);
    printf("latest_justified_ckpt_root=%s\n", just_ckpt_hex);
    printf("latest_finalized_ckpt_root=%s\n", fin_ckpt_hex);
    printf("validators_root=%s\n", validators_root_hex);

    lantern_state_reset(&state);
    return 0;
}
