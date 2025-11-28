/*
 * Tool to regenerate networking test fixtures after signature size changes.
 * Usage: regenerate_networking_fixtures <output_dir>
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "lantern/consensus/containers.h"
#include "lantern/consensus/ssz.h"
#include "lantern/networking/messages.h"
#include "lantern/networking/gossip_payloads.h"
#include "lantern/encoding/snappy.h"

static void fill_bytes(uint8_t *dst, size_t len, uint8_t seed) {
    for (size_t i = 0; i < len; ++i) {
        dst[i] = (uint8_t)(seed + i);
    }
}

static void fill_signature(LanternSignature *signature, uint8_t seed) {
    fill_bytes(signature->bytes, LANTERN_SIGNATURE_SIZE, seed);
}

static void fill_root(LanternRoot *root, uint8_t seed) {
    fill_bytes(root->bytes, LANTERN_ROOT_SIZE, seed);
}

static void build_vote(LanternVote *vote, uint64_t validator_id, uint64_t slot,
                       uint64_t head_slot, uint8_t head_seed,
                       uint64_t target_slot, uint8_t target_seed,
                       uint64_t source_slot, uint8_t source_seed) {
    memset(vote, 0, sizeof(*vote));
    vote->validator_id = validator_id;
    vote->slot = slot;
    vote->head.slot = head_slot;
    fill_root(&vote->head.root, head_seed);
    vote->target.slot = target_slot;
    fill_root(&vote->target.root, target_seed);
    vote->source.slot = source_slot;
    fill_root(&vote->source.root, source_seed);
}

static int write_file(const char *path, const uint8_t *data, size_t len) {
    FILE *fp = fopen(path, "wb");
    if (!fp) {
        fprintf(stderr, "Failed to open %s for writing\n", path);
        return -1;
    }
    if (fwrite(data, 1, len, fp) != len) {
        fprintf(stderr, "Failed to write %zu bytes to %s\n", len, path);
        fclose(fp);
        return -1;
    }
    fclose(fp);
    printf("Wrote %zu bytes to %s\n", len, path);
    return 0;
}

static int generate_signed_vote_fixtures(const char *output_dir) {
    LanternSignedVote vote;
    memset(&vote, 0, sizeof(vote));
    build_vote(&vote.data, 9, 96, 97, 0x33, 96, 0x53, 94, 0x73);
    fill_signature(&vote.signature, 0xE1);

    /* SSZ */
    uint8_t ssz[LANTERN_SIGNED_VOTE_SSZ_SIZE];
    size_t written = 0;
    if (lantern_ssz_encode_signed_vote(&vote, ssz, sizeof(ssz), &written) != 0) {
        fprintf(stderr, "Failed to encode signed vote SSZ\n");
        return -1;
    }

    char path[512];
    snprintf(path, sizeof(path), "%s/gossip_signed_vote_leanspec.ssz", output_dir);
    if (write_file(path, ssz, written) != 0) return -1;

    /* Gossip Snappy (with framing) */
    size_t max_compressed = 0;
    if (lantern_snappy_max_compressed_size(written, &max_compressed) != LANTERN_SNAPPY_OK) {
        fprintf(stderr, "Failed to get max compressed size\n");
        return -1;
    }
    uint8_t *compressed = malloc(max_compressed);
    size_t compressed_len = 0;
    if (lantern_gossip_encode_signed_vote_snappy(&vote, compressed, max_compressed, &compressed_len) != 0) {
        fprintf(stderr, "Failed to gossip-snappy encode signed vote\n");
        free(compressed);
        return -1;
    }

    snprintf(path, sizeof(path), "%s/gossip_signed_vote_leanspec.snappy", output_dir);
    if (write_file(path, compressed, compressed_len) != 0) {
        free(compressed);
        return -1;
    }
    free(compressed);
    return 0;
}

static int generate_signed_block_fixtures(const char *output_dir) {
    LanternSignedBlock block;
    lantern_signed_block_with_attestation_init(&block);

    block.message.block.slot = 72;
    block.message.block.proposer_index = 5;
    fill_root(&block.message.block.parent_root, 0x24);
    fill_root(&block.message.block.state_root, 0x74);

    /* Add attestations */
    if (lantern_attestations_resize(&block.message.block.body.attestations, 2) != 0) {
        fprintf(stderr, "Failed to resize attestations\n");
        return -1;
    }
    build_vote(&block.message.block.body.attestations.data[0], 9, 71, 72, 0x24, 71, 0x44, 69, 0x64);
    build_vote(&block.message.block.body.attestations.data[1], 10, 70, 71, 0x29, 70, 0x49, 68, 0x69);

    /* Proposer attestation - must match expect_signed_block_fixture expectations */
    build_vote(&block.message.proposer_attestation, 8, 74, 75, 0xA4, 74, 0xC4, 72, 0xE4);

    /* Signatures: 2 attestation sigs + 1 proposer sig - must match test expectations */
    if (lantern_block_signatures_resize(&block.signatures, 3) != 0) {
        fprintf(stderr, "Failed to resize signatures\n");
        return -1;
    }
    fill_signature(&block.signatures.data[0], 0xC4);
    fill_signature(&block.signatures.data[1], 0xC7);
    fill_signature(&block.signatures.data[2], 0xCA);

    /* Encode SSZ - use generous buffer */
    size_t ssz_size = 100000;
    uint8_t *ssz = malloc(ssz_size);
    size_t written = 0;
    if (lantern_ssz_encode_signed_block(&block, ssz, ssz_size, &written) != 0) {
        fprintf(stderr, "Failed to encode signed block SSZ\n");
        free(ssz);
        return -1;
    }

    char path[512];
    snprintf(path, sizeof(path), "%s/gossip_signed_block_leanspec.ssz", output_dir);
    if (write_file(path, ssz, written) != 0) {
        free(ssz);
        return -1;
    }

    /* Gossip Snappy (with framing) */
    size_t max_compressed = 0;
    if (lantern_snappy_max_compressed_size(written, &max_compressed) != LANTERN_SNAPPY_OK) {
        fprintf(stderr, "Failed to get max compressed size\n");
        free(ssz);
        return -1;
    }
    uint8_t *compressed = malloc(max_compressed);
    size_t compressed_len = 0;
    if (lantern_gossip_encode_signed_block_snappy(&block, compressed, max_compressed, &compressed_len) != 0) {
        fprintf(stderr, "Failed to gossip-snappy encode signed block\n");
        free(ssz);
        free(compressed);
        return -1;
    }

    snprintf(path, sizeof(path), "%s/gossip_signed_block_leanspec.snappy", output_dir);
    if (write_file(path, compressed, compressed_len) != 0) {
        free(ssz);
        free(compressed);
        return -1;
    }

    free(ssz);
    free(compressed);
    lantern_signed_block_with_attestation_reset(&block);
    return 0;
}

static int generate_status_fixture(const char *output_dir) {
    LanternStatusMessage status;
    memset(&status, 0, sizeof(status));
    /* Must match test expectations in test_networking_messages.c */
    status.finalized.slot = 42;
    fill_root(&status.finalized.root, 0x11);
    status.head.slot = 96;
    fill_root(&status.head.root, 0x41);

    /* Status SSZ size = 2 checkpoints = 2 * (32 + 8) = 80 bytes */
    uint8_t ssz[80];
    size_t written = 0;
    if (lantern_network_status_encode(&status, ssz, sizeof(ssz), &written) != 0) {
        fprintf(stderr, "Failed to encode status SSZ\n");
        return -1;
    }

    char path[512];
    snprintf(path, sizeof(path), "%s/status_leanspec.ssz", output_dir);
    if (write_file(path, ssz, written) != 0) return -1;

    /* Snappy */
    size_t max_compressed = 0;
    if (lantern_snappy_max_compressed_size(written, &max_compressed) != LANTERN_SNAPPY_OK) {
        fprintf(stderr, "Failed to get max compressed size for status\n");
        return -1;
    }
    uint8_t *compressed = malloc(max_compressed);
    size_t compressed_len = 0;
    if (lantern_snappy_compress(ssz, written, compressed, max_compressed, &compressed_len) != LANTERN_SNAPPY_OK) {
        fprintf(stderr, "Failed to compress status\n");
        free(compressed);
        return -1;
    }

    snprintf(path, sizeof(path), "%s/status_leanspec.snappy", output_dir);
    if (write_file(path, compressed, compressed_len) != 0) {
        free(compressed);
        return -1;
    }
    free(compressed);
    return 0;
}

static int generate_blocks_by_root_request_fixture(const char *output_dir) {
    LanternBlocksByRootRequest req;
    lantern_blocks_by_root_request_init(&req);
    if (lantern_root_list_resize(&req.roots, 3) != 0) {
        fprintf(stderr, "Failed to resize roots\n");
        return -1;
    }
    fill_root(&req.roots.items[0], 0x21);
    fill_root(&req.roots.items[1], 0x52);
    fill_root(&req.roots.items[2], 0x83);

    /* 3 roots * 32 bytes = 96 bytes, but we need extra for encoding */
    size_t ssz_size = 1024;
    uint8_t *ssz = malloc(ssz_size);
    size_t written = 0;
    if (lantern_network_blocks_by_root_request_encode(&req, ssz, ssz_size, &written) != 0) {
        fprintf(stderr, "Failed to encode request SSZ\n");
        free(ssz);
        return -1;
    }

    char path[512];
    snprintf(path, sizeof(path), "%s/blocks_by_root_request_leanspec.ssz", output_dir);
    int rc = write_file(path, ssz, written);
    free(ssz);
    lantern_blocks_by_root_request_reset(&req);
    return rc;
}

static int generate_blocks_by_root_response_fixture(const char *output_dir) {
    LanternBlocksByRootResponse resp;
    lantern_blocks_by_root_response_init(&resp);
    if (lantern_blocks_by_root_response_resize(&resp, 2) != 0) {
        fprintf(stderr, "Failed to resize response\n");
        return -1;
    }

    /* Block 0 */
    LanternSignedBlock *block0 = &resp.blocks[0];
    lantern_signed_block_with_attestation_init(block0);
    block0->message.block.slot = 12;
    block0->message.block.proposer_index = 1;
    fill_root(&block0->message.block.parent_root, 0x10);
    fill_root(&block0->message.block.state_root, 0x60);
    if (lantern_attestations_resize(&block0->message.block.body.attestations, 1) != 0) {
        fprintf(stderr, "Failed to resize block0 attestations\n");
        return -1;
    }
    build_vote(&block0->message.block.body.attestations.data[0], 1, 13, 14, 0x10, 15, 0x30, 13, 0x50);
    build_vote(&block0->message.proposer_attestation, 4, 17, 18, 0x90, 19, 0xB0, 17, 0xD0);
    if (lantern_block_signatures_resize(&block0->signatures, 2) != 0) {
        fprintf(stderr, "Failed to resize block0 signatures\n");
        return -1;
    }
    fill_signature(&block0->signatures.data[0], 0xB0);
    fill_signature(&block0->signatures.data[1], 0xB3);

    /* Block 1 */
    LanternSignedBlock *block1 = &resp.blocks[1];
    lantern_signed_block_with_attestation_init(block1);
    block1->message.block.slot = 18;
    block1->message.block.proposer_index = 3;
    fill_root(&block1->message.block.parent_root, 0x30);
    fill_root(&block1->message.block.state_root, 0x80);
    if (lantern_attestations_resize(&block1->message.block.body.attestations, 2) != 0) {
        fprintf(stderr, "Failed to resize block1 attestations\n");
        return -1;
    }
    build_vote(&block1->message.block.body.attestations.data[0], 3, 19, 20, 0x30, 21, 0x50, 19, 0x70);
    build_vote(&block1->message.block.body.attestations.data[1], 4, 20, 21, 0x35, 22, 0x55, 20, 0x75);
    build_vote(&block1->message.proposer_attestation, 6, 24, 25, 0xB0, 26, 0xD0, 24, 0xF0);
    if (lantern_block_signatures_resize(&block1->signatures, 3) != 0) {
        fprintf(stderr, "Failed to resize block1 signatures\n");
        return -1;
    }
    fill_signature(&block1->signatures.data[0], 0xD0);
    fill_signature(&block1->signatures.data[1], 0xD3);
    fill_signature(&block1->signatures.data[2], 0xD6);

    /* Encode - estimate size generously */
    size_t ssz_size = 100000;
    uint8_t *ssz = malloc(ssz_size);
    size_t written = 0;
    if (lantern_network_blocks_by_root_response_encode(&resp, ssz, ssz_size, &written) != 0) {
        fprintf(stderr, "Failed to encode response SSZ\n");
        free(ssz);
        return -1;
    }

    char path[512];
    snprintf(path, sizeof(path), "%s/blocks_by_root_response_leanspec.ssz", output_dir);
    int rc = write_file(path, ssz, written);
    free(ssz);
    lantern_blocks_by_root_response_reset(&resp);
    return rc;
}

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "Usage: %s <output_dir>\n", argv[0]);
        return 1;
    }
    const char *output_dir = argv[1];

    printf("Regenerating networking fixtures to %s\n", output_dir);
    printf("Signature size: %d bytes\n", LANTERN_SIGNATURE_SIZE);

    if (generate_signed_vote_fixtures(output_dir) != 0) return 1;
    if (generate_signed_block_fixtures(output_dir) != 0) return 1;
    if (generate_status_fixture(output_dir) != 0) return 1;
    if (generate_blocks_by_root_request_fixture(output_dir) != 0) return 1;
    if (generate_blocks_by_root_response_fixture(output_dir) != 0) return 1;

    printf("Done!\n");
    return 0;
}
