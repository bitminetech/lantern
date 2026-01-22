#include <assert.h>
#include <stdbool.h>
#include <errno.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "lantern/consensus/hash.h"
#include "lantern/consensus/duties.h"
#include "lantern/consensus/state.h"
#include "lantern/consensus/ssz.h"
#include "lantern/networking/messages.h"
#include "lantern/storage/storage.h"
#include "lantern/support/strings.h"

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
    out_block->message.slot = slot;
    expect_zero(
        lantern_proposer_for_slot(slot, state->config.num_validators, &out_block->message.proposer_index),
        "compute proposer");
    expect_zero(
        lantern_hash_tree_root_block_header(&state->latest_block_header, &out_block->message.parent_root),
        "hash parent header");
    lantern_block_body_init(&out_block->message.body);
    expect_zero(
        lantern_hash_tree_root_block(&out_block->message.block, out_root),
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
        memset(invalid.validators[i].pubkey, (int)(0x30 + (i & 0x3Fu)), LANTERN_VALIDATOR_PUBKEY_SIZE);
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
    state.historical_roots_offset = 11u;
    state.justified_slots_offset = 22u;

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
    assert(loaded_state.historical_roots_offset == state.historical_roots_offset);
    assert(loaded_state.justified_slots_offset == state.justified_slots_offset);
    lantern_state_reset(&loaded_state);

    LanternVote vote;
    build_vote(&vote, 5u, 2u, 4u);
    LanternSignedVote signed_vote;
    memset(&signed_vote, 0, sizeof(signed_vote));
    signed_vote.data = vote;
    fill_signature(&signed_vote.signature, 0xAB);
    expect_zero(lantern_state_set_signed_validator_vote(&state, 1u, &signed_vote), "set validator vote");
    expect_zero(lantern_storage_save_votes(base_dir, &state), "save votes");
    lantern_state_clear_validator_vote(&state, 1u);
    expect_true(!lantern_state_validator_has_vote(&state, 1u), "vote cleared");

    int load_votes_rc = lantern_storage_load_votes(base_dir, &state);
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

    LanternBlocksByRootResponse response;
    lantern_blocks_by_root_response_init(&response);
    expect_zero(
        lantern_storage_collect_blocks(base_dir, &block_root, 1u, &response),
        "collect blocks");
    assert(response.length == 1u);
    assert(response.blocks[0].message.slot == block.message.slot);
    assert(response.blocks[0].message.proposer_index == block.message.proposer_index);

    struct iterate_ctx ctx = {.count = 0};
    expect_zero(lantern_storage_iterate_blocks(base_dir, iterate_counter, &ctx), "iterate blocks");
    assert(ctx.count == 1u);

    lantern_blocks_by_root_response_reset(&response);
    lantern_block_body_reset(&block.message.body);
    lantern_state_reset(&state);

    char state_path[PATH_MAX];
    char votes_path[PATH_MAX];
    char meta_path[PATH_MAX];
    char blocks_dir[PATH_MAX];
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
    written = snprintf(states_dir, sizeof(states_dir), "%s/%s", base_dir, "states");
    assert(written > 0 && (size_t)written < sizeof(states_dir));
    written = snprintf(indices_dir, sizeof(indices_dir), "%s/%s", base_dir, "indices");
    assert(written > 0 && (size_t)written < sizeof(indices_dir));
    written = snprintf(slot_index_dir, sizeof(slot_index_dir), "%s/%s", indices_dir, "slots");
    assert(written > 0 && (size_t)written < sizeof(slot_index_dir));

    char block_path[PATH_MAX];
    char root_hex[2u * LANTERN_ROOT_SIZE + 1u];
    expect_zero(lantern_bytes_to_hex(block_root.bytes, LANTERN_ROOT_SIZE, root_hex, sizeof(root_hex), 0), "hex root");
    written = snprintf(block_path, sizeof(block_path), "%s/%s.ssz", blocks_dir, root_hex);
    assert(written > 0 && (size_t)written < sizeof(block_path));

    cleanup_path(block_path);
    cleanup_dir(blocks_dir);
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

    return EXIT_SUCCESS;
}
