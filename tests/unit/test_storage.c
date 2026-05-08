#include <assert.h>
#include <stdbool.h>
#include <dirent.h>
#include <errno.h>
#include <inttypes.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "lantern/consensus/hash.h"
#include "lantern/consensus/containers.h"
#include "lantern/consensus/duties.h"
#include "lantern/consensus/state.h"
#include "lantern/consensus/ssz.h"
#include "lantern/networking/messages.h"
#include "lantern/storage/storage.h"
#include "lantern/support/strings.h"
#include "../support/state_store_adapter.h"

static void expect_zero(int rc, const char *label) {
    if (rc != 0) {
        fprintf(stderr, "%s failed rc=%d (errno=%d)\n", label, rc, errno);
        exit(EXIT_FAILURE);
    }
}

static void expect_true(bool value, const char *label) {
    if (!value) {
        fprintf(stderr, "%s expected true\n", label);
        exit(EXIT_FAILURE);
    }
}

static void cleanup_path(const char *path) {
    if (!path) {
        return;
    }
    if (unlink(path) != 0 && errno != ENOENT) {
        fprintf(stderr, "failed to remove %s: %s\n", path, strerror(errno));
        exit(EXIT_FAILURE);
    }
}

static void cleanup_dir(const char *path) {
    if (!path) {
        return;
    }
    if (rmdir(path) != 0 && errno != ENOENT) {
        fprintf(stderr, "failed to remove dir %s: %s\n", path, strerror(errno));
        exit(EXIT_FAILURE);
    }
}

static void build_root_file_path(
    char *path,
    size_t path_len,
    const char *base_dir,
    const char *subdir,
    const LanternRoot *root,
    const char *ext) {
    char root_hex[2u * LANTERN_ROOT_SIZE + 1u];
    expect_zero(
        lantern_bytes_to_hex(root->bytes, LANTERN_ROOT_SIZE, root_hex, sizeof(root_hex), 0),
        "hex root path");
    int written = snprintf(path, path_len, "%s/%s/%s.%s", base_dir, subdir, root_hex, ext);
    assert(written > 0 && (size_t)written < path_len);
}

static void build_slot_index_path(
    char *path,
    size_t path_len,
    const char *base_dir,
    uint64_t slot) {
    int written = snprintf(path, path_len, "%s/indices/slots/%" PRIu64 ".root", base_dir, slot);
    assert(written > 0 && (size_t)written < path_len);
}

static bool path_exists(const char *path) {
    return access(path, F_OK) == 0;
}

static void build_vote(
    LanternVote *vote,
    uint64_t slot,
    uint64_t source_slot,
    uint64_t target_slot) {
    memset(vote, 0, sizeof(*vote));
    vote->slot = slot;
    vote->source.slot = source_slot;
    vote->target.slot = target_slot;
    vote->head.slot = target_slot;
    memset(vote->source.root.bytes, 0x11, LANTERN_ROOT_SIZE);
    memset(vote->target.root.bytes, 0x22, LANTERN_ROOT_SIZE);
    memset(vote->head.root.bytes, 0x33, LANTERN_ROOT_SIZE);
}

static void fill_signature(LanternSignature *signature, uint8_t marker) {
    if (!signature) {
        return;
    }
    memset(signature->bytes, marker, LANTERN_SIGNATURE_SIZE);
}

static void build_signed_block(
    const LanternState *state,
    uint64_t slot,
    LanternSignedBlock *out_block,
    LanternRoot *out_root) {
    memset(out_block, 0, sizeof(*out_block));
    out_block->block.slot = slot;
    expect_zero(
        lantern_proposer_for_slot(slot, state->config.num_validators, &out_block->block.proposer_index),
        "compute proposer");
    expect_zero(
        lantern_hash_tree_root_block_header(&state->latest_block_header, &out_block->block.parent_root),
        "hash parent header");
    lantern_block_body_init(&out_block->block.body);
    expect_zero(
        lantern_hash_tree_root_block(&out_block->block, out_root),
        "hash block");
}

struct iterate_ctx {
    size_t count;
};

static int iterate_counter(const LanternSignedBlock *block, const LanternRoot *root, void *context) {
    (void)block;
    (void)root;
    struct iterate_ctx *ctx = context;
    ctx->count += 1;
    return 0;
}

static void assert_invalid_gossip_dump(
    const char *base_dir,
    const uint8_t *expected_payload,
    size_t expected_payload_len) {
    char invalid_gossip_dir[PATH_MAX];
    int written = snprintf(
        invalid_gossip_dir,
        sizeof(invalid_gossip_dir),
        "%s/%s",
        base_dir,
        "invalid_gossip");
    assert(written > 0 && (size_t)written < sizeof(invalid_gossip_dir));

    DIR *dir = opendir(invalid_gossip_dir);
    assert(dir != NULL);

    struct dirent *entry = NULL;
    char dump_name[NAME_MAX + 1u];
    dump_name[0] = '\0';
    size_t dump_count = 0u;
    while ((entry = readdir(dir)) != NULL) {
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) {
            continue;
        }
        ++dump_count;
        assert(dump_count == 1u);
        written = snprintf(dump_name, sizeof(dump_name), "%s", entry->d_name);
        assert(written > 0 && (size_t)written < sizeof(dump_name));
    }
    closedir(dir);

    assert(dump_count == 1u);
    assert(strstr(dump_name, "_aggregated_attestation_") != NULL);
    char expected_suffix[32];
    written = snprintf(expected_suffix, sizeof(expected_suffix), "_%zub.ssz", expected_payload_len);
    assert(written > 0 && (size_t)written < sizeof(expected_suffix));
    assert(strstr(dump_name, expected_suffix) != NULL);

    char dump_path[PATH_MAX];
    written = snprintf(dump_path, sizeof(dump_path), "%s/%s", invalid_gossip_dir, dump_name);
    assert(written > 0 && (size_t)written < sizeof(dump_path));

    FILE *dump_fp = fopen(dump_path, "rb");
    assert(dump_fp != NULL);
    uint8_t readback[16];
    size_t read_len = fread(readback, 1u, sizeof(readback), dump_fp);
    assert(read_len == expected_payload_len);
    assert(memcmp(readback, expected_payload, expected_payload_len) == 0);
    assert(fgetc(dump_fp) == EOF);
    fclose(dump_fp);

    cleanup_path(dump_path);
    cleanup_dir(invalid_gossip_dir);
}

static int test_storage_rejects_excess_validators(void) {
    char dir_template[] = "/tmp/lantern_storage_limitXXXXXX";
    char *limit_dir = mkdtemp(dir_template);
    if (!limit_dir) {
        perror("mkdtemp limit");
        return 1;
    }

    LanternState invalid;
    lantern_state_init(&invalid);
    uint8_t *encoded = NULL;
    char state_path[PATH_MAX];
    state_path[0] = '\0';
    int result = 1;

    size_t too_many = (size_t)LANTERN_VALIDATOR_REGISTRY_LIMIT + 1u;
    invalid.config.genesis_time = 555u;
    invalid.config.num_validators = (uint64_t)too_many;
    invalid.validator_count = too_many;
    invalid.validator_capacity = too_many;
    invalid.validators = calloc(too_many, sizeof(LanternValidator));
    if (!invalid.validators) {
        perror("calloc validators");
        goto cleanup;
    }
    for (size_t i = 0; i < too_many; ++i) {
        memset(
            invalid.validators[i].attestation_pubkey,
            (int)(0x30 + (i & 0x3Fu)),
            LANTERN_VALIDATOR_PUBKEY_SIZE);
        memset(
            invalid.validators[i].proposal_pubkey,
            (int)(0x50 + (i & 0x3Fu)),
            LANTERN_VALIDATOR_PUBKEY_SIZE);
    }

    size_t buffer_size = 1024u * 1024u;
    encoded = malloc(buffer_size);
    if (!encoded) {
        perror("malloc encoded state");
        goto cleanup;
    }
    size_t written = 0;
    expect_zero(lantern_ssz_encode_state(&invalid, encoded, buffer_size, &written), "encode invalid state");

    int state_path_len = snprintf(state_path, sizeof(state_path), "%s/%s", limit_dir, "state.ssz");
    assert(state_path_len > 0 && (size_t)state_path_len < sizeof(state_path));
    FILE *fp = fopen(state_path, "wb");
    if (!fp) {
        perror("fopen invalid state file");
        goto cleanup;
    }
    size_t file_written = fwrite(encoded, 1u, written, fp);
    fclose(fp);
    if (file_written != written) {
        fprintf(stderr, "failed to write invalid state fixture\n");
        goto cleanup;
    }

    LanternState loaded;
    lantern_state_init(&loaded);
    int load_rc = lantern_storage_load_state(limit_dir, &loaded);
    if (load_rc == 0) {
        fprintf(stderr, "expected load_state to reject validator count > limit\n");
        lantern_state_reset(&loaded);
        goto cleanup;
    }
    lantern_state_reset(&loaded);

    result = 0;

cleanup:
    free(encoded);
    lantern_state_reset(&invalid);
    if (state_path[0] != '\0') {
        cleanup_path(state_path);
    }
    cleanup_dir(limit_dir);
    return result;
}

static int test_storage_prunes_before_slot(void) {
    char dir_template[] = "/tmp/lantern_storage_pruneXXXXXX";
    char *base_dir = mkdtemp(dir_template);
    if (!base_dir) {
        perror("mkdtemp prune");
        return 1;
    }

    int rc = 1;
    LanternState state;
    lantern_state_init(&state);
    LanternState snapshots[3];
    LanternSignedBlock blocks[3];
    LanternRoot roots[3];
    bool blocks_ready[3] = {false, false, false};
    bool states_ready[3] = {false, false, false};
    LanternSignedBlockList collected;
    lantern_signed_block_list_init(&collected);

    expect_zero(lantern_storage_prepare(base_dir), "prepare prune storage");
    expect_zero(lantern_state_generate_genesis(&state, 123456u, 4u), "generate prune genesis");

    uint8_t pubkeys[4u * LANTERN_VALIDATOR_PUBKEY_SIZE];
    for (size_t i = 0; i < 4u; ++i) {
        memset(
            pubkeys + (i * LANTERN_VALIDATOR_PUBKEY_SIZE),
            (int)(0xB0u + i),
            LANTERN_VALIDATOR_PUBKEY_SIZE);
    }
    expect_zero(lantern_state_set_validator_pubkeys(&state, pubkeys, 4u), "set prune pubkeys");

    for (size_t i = 0; i < 3u; ++i) {
        const uint64_t slot = (uint64_t)i + 1u;
        build_signed_block(&state, slot, &blocks[i], &roots[i]);
        blocks_ready[i] = true;
        expect_zero(lantern_storage_store_block_for_root(base_dir, &roots[i], &blocks[i]), "store prune block");

        lantern_state_init(&snapshots[i]);
        states_ready[i] = true;
        expect_zero(lantern_state_clone(&state, &snapshots[i]), "clone prune state");
        snapshots[i].slot = slot;
        snapshots[i].latest_block_header.slot = slot;
        snapshots[i].latest_block_header.proposer_index = blocks[i].block.proposer_index;
        snapshots[i].latest_block_header.parent_root = blocks[i].block.parent_root;
        snapshots[i].latest_block_header.state_root = blocks[i].block.state_root;
        expect_zero(lantern_storage_store_state_for_root(base_dir, &roots[i], &snapshots[i]), "store prune state");
        expect_zero(lantern_storage_store_slot_root(base_dir, slot, &roots[i]), "store prune slot root");
    }

    int pruned = lantern_storage_prune_before_slot(base_dir, 3u, &roots[1], 1u);
    if (pruned != 3) {
        fprintf(stderr, "expected prune count 3 got %d\n", pruned);
        goto cleanup;
    }

    expect_zero(lantern_storage_collect_blocks(base_dir, roots, 3u, &collected), "collect pruned blocks");
    if (collected.length != 2u) {
        fprintf(stderr, "expected two blocks after prune got %zu\n", collected.length);
        goto cleanup;
    }

    char path[PATH_MAX];
    build_root_file_path(path, sizeof(path), base_dir, "blocks", &roots[0], "ssz");
    expect_true(!path_exists(path), "old block pruned");
    build_root_file_path(path, sizeof(path), base_dir, "blocks", &roots[1], "ssz");
    expect_true(path_exists(path), "kept root block preserved");
    build_root_file_path(path, sizeof(path), base_dir, "blocks", &roots[2], "ssz");
    expect_true(path_exists(path), "new block preserved");

    build_root_file_path(path, sizeof(path), base_dir, "states", &roots[0], "ssz");
    expect_true(!path_exists(path), "old state pruned");
    build_root_file_path(path, sizeof(path), base_dir, "states", &roots[1], "ssz");
    expect_true(path_exists(path), "kept root state preserved");
    build_root_file_path(path, sizeof(path), base_dir, "states", &roots[2], "ssz");
    expect_true(path_exists(path), "new state preserved");

    build_slot_index_path(path, sizeof(path), base_dir, 1u);
    expect_true(!path_exists(path), "old slot index pruned");
    build_slot_index_path(path, sizeof(path), base_dir, 2u);
    expect_true(path_exists(path), "kept root slot index preserved");
    build_slot_index_path(path, sizeof(path), base_dir, 3u);
    expect_true(path_exists(path), "new slot index preserved");

    rc = 0;

cleanup:
    lantern_signed_block_list_reset(&collected);
    for (size_t i = 0; i < 3u; ++i) {
        if (blocks_ready[i]) {
            lantern_block_body_reset(&blocks[i].block.body);
        }
        if (states_ready[i]) {
            lantern_state_reset(&snapshots[i]);
        }
    }
    lantern_state_reset(&state);

    char cleanup_file[PATH_MAX];
    for (size_t i = 0; i < 3u; ++i) {
        build_root_file_path(cleanup_file, sizeof(cleanup_file), base_dir, "blocks", &roots[i], "ssz");
        cleanup_path(cleanup_file);
        build_root_file_path(cleanup_file, sizeof(cleanup_file), base_dir, "states", &roots[i], "ssz");
        cleanup_path(cleanup_file);
        build_slot_index_path(cleanup_file, sizeof(cleanup_file), base_dir, (uint64_t)i + 1u);
        cleanup_path(cleanup_file);
    }

    char blocks_dir[PATH_MAX];
    char invalid_blocks_dir[PATH_MAX];
    char invalid_gossip_dir[PATH_MAX];
    char states_dir[PATH_MAX];
    char indices_dir[PATH_MAX];
    char slot_index_dir[PATH_MAX];
    int written = snprintf(blocks_dir, sizeof(blocks_dir), "%s/blocks", base_dir);
    assert(written > 0 && (size_t)written < sizeof(blocks_dir));
    written = snprintf(invalid_blocks_dir, sizeof(invalid_blocks_dir), "%s/invalid_blocks", base_dir);
    assert(written > 0 && (size_t)written < sizeof(invalid_blocks_dir));
    written = snprintf(invalid_gossip_dir, sizeof(invalid_gossip_dir), "%s/invalid_gossip", base_dir);
    assert(written > 0 && (size_t)written < sizeof(invalid_gossip_dir));
    written = snprintf(states_dir, sizeof(states_dir), "%s/states", base_dir);
    assert(written > 0 && (size_t)written < sizeof(states_dir));
    written = snprintf(indices_dir, sizeof(indices_dir), "%s/indices", base_dir);
    assert(written > 0 && (size_t)written < sizeof(indices_dir));
    written = snprintf(slot_index_dir, sizeof(slot_index_dir), "%s/slots", indices_dir);
    assert(written > 0 && (size_t)written < sizeof(slot_index_dir));
    cleanup_dir(blocks_dir);
    cleanup_dir(invalid_blocks_dir);
    cleanup_dir(invalid_gossip_dir);
    cleanup_dir(states_dir);
    cleanup_dir(slot_index_dir);
    cleanup_dir(indices_dir);
    cleanup_dir(base_dir);
    return rc;
}

int main(void) {
    char dir_template[] = "/tmp/lantern_storage_testXXXXXX";
    char *base_dir = mkdtemp(dir_template);
    if (!base_dir) {
        perror("mkdtemp");
        return EXIT_FAILURE;
    }

    expect_zero(lantern_storage_prepare(base_dir), "prepare storage");

    LanternState state;
    lantern_state_init(&state);
    expect_zero(lantern_state_generate_genesis(&state, 123456u, 4u), "generate genesis");

    /* Populate validator registry with deterministic pubkeys so SSZ encoding works */
    const size_t genesis_validators = state.config.num_validators;
    const size_t pubkey_bytes = genesis_validators * LANTERN_VALIDATOR_PUBKEY_SIZE;
    uint8_t *dummy_pubkeys = calloc(pubkey_bytes, 1u);
    assert(dummy_pubkeys != NULL);
    for (size_t i = 0; i < genesis_validators; ++i) {
        memset(dummy_pubkeys + (i * LANTERN_VALIDATOR_PUBKEY_SIZE), (int)(0xA0 + i), LANTERN_VALIDATOR_PUBKEY_SIZE);
    }
    expect_zero(
        lantern_state_set_validator_pubkeys(&state, dummy_pubkeys, genesis_validators),
        "populate validator pubkeys");
    free(dummy_pubkeys);

    expect_zero(lantern_storage_save_state(base_dir, &state), "save state");

    LanternState loaded_state;
    lantern_state_init(&loaded_state);
    int load_state_rc = lantern_storage_load_state(base_dir, &loaded_state);
    if (load_state_rc != 0) {
        fprintf(stderr, "expected persisted state rc=0 got %d\n", load_state_rc);
        return EXIT_FAILURE;
    }
    assert(loaded_state.config.num_validators == state.config.num_validators);
    lantern_state_reset(&loaded_state);

    LanternVote vote;
    build_vote(&vote, 5u, 2u, 4u);
    LanternSignedVote signed_vote;
    memset(&signed_vote, 0, sizeof(signed_vote));
    signed_vote.data = vote;
    fill_signature(&signed_vote.signature, 0xAB);
    expect_zero(lantern_state_set_signed_validator_vote(&state, 1u, &signed_vote), "set validator vote");
    expect_zero(
        lantern_storage_save_votes(base_dir, &state, lantern_test_state_store_ensure(&state)),
        "save votes");
    lantern_state_clear_validator_vote(&state, 1u);
    expect_true(!lantern_state_validator_has_vote(&state, 1u), "vote cleared");

    int load_votes_rc = lantern_storage_load_votes(base_dir, &state, lantern_test_state_store_ensure(&state));
    if (load_votes_rc != 0) {
        fprintf(stderr, "expected persisted votes rc=0 got %d\n", load_votes_rc);
        return EXIT_FAILURE;
    }
    expect_true(lantern_state_validator_has_vote(&state, 1u), "vote restored");
    LanternVote restored_vote;
    expect_zero(lantern_state_get_validator_vote(&state, 1u, &restored_vote), "get restored vote");
    assert(restored_vote.slot == vote.slot);
    assert(restored_vote.source.slot == vote.source.slot);
    assert(restored_vote.target.slot == vote.target.slot);
    LanternSignedVote restored_signed_vote;
    expect_zero(
        lantern_state_get_signed_validator_vote(&state, 1u, &restored_signed_vote),
        "get restored signed vote");
    assert(
        memcmp(
            restored_signed_vote.signature.bytes,
            signed_vote.signature.bytes,
            LANTERN_SIGNATURE_SIZE)
        == 0);

    LanternSignedBlock block;
    LanternRoot block_root;
    build_signed_block(&state, 1u, &block, &block_root);
    expect_zero(lantern_storage_store_block(base_dir, &block), "store block");
    /* store again to ensure idempotent */
    expect_zero(lantern_storage_store_block(base_dir, &block), "store block duplicate");
    const uint8_t invalid_payload[] = {0xDE, 0xAD, 0xBE, 0xEF};
    expect_zero(
        lantern_storage_store_invalid_block_bytes_for_root(
            base_dir,
            &block_root,
            invalid_payload,
            sizeof(invalid_payload)),
        "store invalid block bytes");
    const uint8_t invalid_gossip_payload[] = {0x01, 0x02, 0x03, 0x04, 0x05};
    expect_zero(
        lantern_storage_store_invalid_gossip_payload(
            base_dir,
            "aggregated_attestation",
            invalid_gossip_payload,
            sizeof(invalid_gossip_payload)),
        "store invalid gossip payload");

    LanternSignedBlockList response;
    lantern_signed_block_list_init(&response);
    expect_zero(
        lantern_storage_collect_blocks(base_dir, &block_root, 1u, &response),
        "collect blocks");
    assert(response.length == 1u);
    assert(response.blocks[0].block.slot == block.block.slot);
    assert(response.blocks[0].block.proposer_index == block.block.proposer_index);

    struct iterate_ctx ctx = {.count = 0};
    expect_zero(lantern_storage_iterate_blocks(base_dir, iterate_counter, &ctx), "iterate blocks");
    assert(ctx.count == 1u);

    lantern_signed_block_list_reset(&response);
    lantern_block_body_reset(&block.block.body);

    LanternSignedBlock legacy_block;
    LanternRoot legacy_block_root;
    build_signed_block(&state, 2u, &legacy_block, &legacy_block_root);

    LanternAttestations legacy_plain_attestations;
    lantern_attestations_init(&legacy_plain_attestations);
    expect_zero(
        lantern_attestations_resize(&legacy_plain_attestations, 2u),
        "legacy plain attestation resize");
    build_vote(&legacy_plain_attestations.data[0], 6u, 4u, 5u);
    legacy_plain_attestations.data[0].validator_id = 1u;
    build_vote(&legacy_plain_attestations.data[1], 6u, 4u, 5u);
    legacy_plain_attestations.data[1].validator_id = 2u;
    expect_zero(
        lantern_wrap_attestations_as_aggregated(
            &legacy_plain_attestations,
            &legacy_block.block.body.attestations),
        "wrap legacy plain attestation");
    legacy_block.block.body.legacy_plain_attestation_layout = true;
    expect_zero(
        lantern_hash_tree_root_block(&legacy_block.block, &legacy_block_root),
        "hash legacy block");
    expect_zero(
        lantern_storage_store_block(base_dir, &legacy_block),
        "store legacy block");

    LanternSignedBlockList legacy_response;
    lantern_signed_block_list_init(&legacy_response);
    expect_zero(
        lantern_storage_collect_blocks(base_dir, &legacy_block_root, 1u, &legacy_response),
        "collect legacy block");
    assert(legacy_response.length == 1u);
    LanternRoot collected_legacy_root;
    expect_zero(
        lantern_hash_tree_root_block(
            &legacy_response.blocks[0].block,
            &collected_legacy_root),
        "hash collected legacy block");
    assert(
        memcmp(
            collected_legacy_root.bytes,
            legacy_block_root.bytes,
            LANTERN_ROOT_SIZE)
        == 0);
    assert(legacy_response.blocks[0].block.body.legacy_plain_attestation_layout == true);
    lantern_signed_block_list_reset(&legacy_response);
    lantern_block_body_reset(&legacy_block.block.body);
    lantern_attestations_reset(&legacy_plain_attestations);

    lantern_state_reset(&state);

    char state_path[PATH_MAX];
    char votes_path[PATH_MAX];
    char meta_path[PATH_MAX];
    char blocks_dir[PATH_MAX];
    char invalid_blocks_dir[PATH_MAX];
    char states_dir[PATH_MAX];
    char indices_dir[PATH_MAX];
    char slot_index_dir[PATH_MAX];
    int written = snprintf(state_path, sizeof(state_path), "%s/%s", base_dir, "state.ssz");
    assert(written > 0 && (size_t)written < sizeof(state_path));
    written = snprintf(votes_path, sizeof(votes_path), "%s/%s", base_dir, "votes.bin");
    assert(written > 0 && (size_t)written < sizeof(votes_path));
    written = snprintf(meta_path, sizeof(meta_path), "%s/%s", base_dir, "state.meta");
    assert(written > 0 && (size_t)written < sizeof(meta_path));
    written = snprintf(blocks_dir, sizeof(blocks_dir), "%s/%s", base_dir, "blocks");
    assert(written > 0 && (size_t)written < sizeof(blocks_dir));
    written = snprintf(invalid_blocks_dir, sizeof(invalid_blocks_dir), "%s/%s", base_dir, "invalid_blocks");
    assert(written > 0 && (size_t)written < sizeof(invalid_blocks_dir));
    written = snprintf(states_dir, sizeof(states_dir), "%s/%s", base_dir, "states");
    assert(written > 0 && (size_t)written < sizeof(states_dir));
    written = snprintf(indices_dir, sizeof(indices_dir), "%s/%s", base_dir, "indices");
    assert(written > 0 && (size_t)written < sizeof(indices_dir));
    written = snprintf(slot_index_dir, sizeof(slot_index_dir), "%s/%s", indices_dir, "slots");
    assert(written > 0 && (size_t)written < sizeof(slot_index_dir));

    char block_path[PATH_MAX];
    char invalid_block_path[PATH_MAX];
    char root_hex[2u * LANTERN_ROOT_SIZE + 1u];
    expect_zero(lantern_bytes_to_hex(block_root.bytes, LANTERN_ROOT_SIZE, root_hex, sizeof(root_hex), 0), "hex root");
    written = snprintf(block_path, sizeof(block_path), "%s/%s.ssz", blocks_dir, root_hex);
    assert(written > 0 && (size_t)written < sizeof(block_path));
    written = snprintf(invalid_block_path, sizeof(invalid_block_path), "%s/%s.ssz", invalid_blocks_dir, root_hex);
    assert(written > 0 && (size_t)written < sizeof(invalid_block_path));

    FILE *invalid_fp = fopen(invalid_block_path, "rb");
    assert(invalid_fp != NULL);
    uint8_t invalid_readback[sizeof(invalid_payload)];
    size_t invalid_read = fread(invalid_readback, 1u, sizeof(invalid_readback), invalid_fp);
    assert(invalid_read == sizeof(invalid_readback));
    assert(memcmp(invalid_readback, invalid_payload, sizeof(invalid_readback)) == 0);
    assert(fgetc(invalid_fp) == EOF);
    fclose(invalid_fp);

    assert_invalid_gossip_dump(base_dir, invalid_gossip_payload, sizeof(invalid_gossip_payload));

    cleanup_path(block_path);
    cleanup_path(invalid_block_path);
    expect_zero(
        lantern_bytes_to_hex(legacy_block_root.bytes, LANTERN_ROOT_SIZE, root_hex, sizeof(root_hex), 0),
        "legacy hex root");
    written = snprintf(block_path, sizeof(block_path), "%s/%s.ssz", blocks_dir, root_hex);
    assert(written > 0 && (size_t)written < sizeof(block_path));
    cleanup_path(block_path);
    cleanup_dir(blocks_dir);
    cleanup_dir(invalid_blocks_dir);
    cleanup_dir(slot_index_dir);
    cleanup_dir(indices_dir);
    cleanup_dir(states_dir);
    cleanup_path(votes_path);
    cleanup_path(meta_path);
    cleanup_path(state_path);
    cleanup_dir(base_dir);

    if (test_storage_rejects_excess_validators() != 0) {
        return EXIT_FAILURE;
    }
    if (test_storage_prunes_before_slot() != 0) {
        return EXIT_FAILURE;
    }

    return EXIT_SUCCESS;
}
