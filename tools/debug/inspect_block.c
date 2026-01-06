#include "lantern/consensus/containers.h"
#include "lantern/consensus/hash.h"
#include "lantern/consensus/ssz.h"
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

static void format_root(const LanternRoot *root, char *out, size_t out_len) {
    if (lantern_bytes_to_hex(root->bytes, LANTERN_ROOT_SIZE, out, out_len, 1) != 0) {
        if (out_len > 0) {
            out[0] = '\0';
        }
    }
}

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: %s /path/to/block.ssz\n", argv[0]);
        return 1;
    }

    uint8_t *data = NULL;
    size_t len = 0;
    if (read_file(argv[1], &data, &len) != 0) {
        return 1;
    }

    LanternSignedBlock block;
    lantern_signed_block_with_attestation_init(&block);

    int rc = lantern_ssz_decode_signed_block(&block, data, len);
    free(data);
    if (rc != 0) {
        fprintf(stderr, "failed to decode block\n");
        lantern_signed_block_with_attestation_reset(&block);
        return 1;
    }

    LanternRoot block_root;
    LanternRoot signed_root;
    LanternRoot body_root;
    if (lantern_hash_tree_root_block(&block.message.block, &block_root) != 0) {
        fprintf(stderr, "failed to hash block\n");
        lantern_signed_block_with_attestation_reset(&block);
        return 1;
    }
    if (lantern_hash_tree_root_signed_block(&block, &signed_root) != 0) {
        fprintf(stderr, "failed to hash signed block\n");
        lantern_signed_block_with_attestation_reset(&block);
        return 1;
    }
    if (lantern_hash_tree_root_block_body(&block.message.block.body, &body_root) != 0) {
        memset(&body_root, 0, sizeof(body_root));
    }

    char parent_hex[2 * LANTERN_ROOT_SIZE + 3];
    char state_hex[sizeof(parent_hex)];
    char body_hex[sizeof(parent_hex)];
    char block_hex[sizeof(parent_hex)];
    char signed_hex[sizeof(parent_hex)];
    format_root(&block.message.block.parent_root, parent_hex, sizeof(parent_hex));
    format_root(&block.message.block.state_root, state_hex, sizeof(state_hex));
    format_root(&body_root, body_hex, sizeof(body_hex));
    format_root(&block_root, block_hex, sizeof(block_hex));
    format_root(&signed_root, signed_hex, sizeof(signed_hex));

    printf("slot=%" PRIu64 "\n", block.message.block.slot);
    printf("proposer=%" PRIu64 "\n", block.message.block.proposer_index);
    printf("parent_root=%s\n", parent_hex);
    printf("state_root=%s\n", state_hex);
    printf("body_root=%s\n", body_hex);
    printf("block_root=%s\n", block_hex);
    printf("signed_block_root=%s\n", signed_hex);
    printf("attestations=%zu\n", block.message.block.body.attestations.length);
    printf("proposer_attestation.validator=%" PRIu64 "\n", block.message.proposer_attestation.validator_id);
    printf("attestation_signatures=%zu\n", block.signatures.attestation_signatures.length);

    lantern_signed_block_with_attestation_reset(&block);
    return 0;
}
