#include <assert.h>
#include <errno.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "lantern/consensus/hash.h"
#include "lantern/consensus/state.h"
#include "lantern/storage/storage.h"
#include "../support/state_store_adapter.h"
#include "../support/storage_cleanup.h"
#include "../support/validator_registry.h"

static void expect_zero(int result, const char *label)
{
    if (result != 0)
    {
        fprintf(stderr, "%s failed rc=%d\n", label, result);
        exit(EXIT_FAILURE);
    }
}

static void cleanup_storage(struct lantern_storage *storage, const char *directory)
{
    lantern_storage_close(storage);
    if (lantern_test_remove_storage_dir(directory) != 0)
    {
        perror("remove storage directory");
        exit(EXIT_FAILURE);
    }
}

static void build_signed_block(
    const LanternState *state,
    uint64_t slot,
    LanternSignedBlock *block,
    LanternRoot *root)
{
    lantern_signed_block_init(block);
    block->block.slot = slot;
    expect_zero(
        lantern_proposer_for_slot(slot, state->validator_count, &block->block.proposer_index),
        "compute proposer");
    expect_zero(
        lantern_hash_tree_root_block_header(&state->latest_block_header, &block->block.parent_root),
        "hash parent header");
    expect_zero(lantern_hash_tree_root_block(&block->block, root), "hash block");
}

static void populate_pubkeys(LanternState *state, uint8_t seed)
{
    size_t length = state->validator_count * LANTERN_VALIDATOR_PUBKEY_SIZE;
    uint8_t *pubkeys = malloc(length);
    assert(pubkeys);
    for (size_t i = 0; i < state->validator_count; ++i)
    {
        memset(
            pubkeys + (i * LANTERN_VALIDATOR_PUBKEY_SIZE),
            (int)(seed + i),
            LANTERN_VALIDATOR_PUBKEY_SIZE);
    }
    expect_zero(
        lantern_test_state_set_validator_pubkeys(state, pubkeys, state->validator_count),
        "populate validator pubkeys");
    free(pubkeys);
}

struct iterate_context {
    size_t count;
};

static int count_block(const LanternSignedBlock *block, const LanternRoot *root, void *context)
{
    if (!block || !root || !context)
    {
        return -1;
    }
    ((struct iterate_context *)context)->count += 1u;
    return 0;
}

static int test_storage_rejects_excess_validators(void)
{
    char template[] = "/tmp/lantern_storage_limitXXXXXX";
    char *directory = mkdtemp(template);
    struct lantern_storage storage = {0};
    LanternState invalid;
    lantern_state_init(&invalid);
    if (!directory || lantern_storage_open(&storage, directory) != 0)
    {
        return 1;
    }
    invalid.config.genesis_time = 555u;
    invalid.validator_count = (size_t)LANTERN_VALIDATOR_REGISTRY_LIMIT + 1u;
    invalid.validators = calloc(invalid.validator_count, sizeof(*invalid.validators));
    if (!invalid.validators)
    {
        cleanup_storage(&storage, directory);
        return 1;
    }
    for (size_t i = 0; i < invalid.validator_count; ++i)
    {
        memset(
            invalid.validators[i].attestation_pubkey,
            (int)(0x30u + (i & 0x3fu)),
            LANTERN_VALIDATOR_PUBKEY_SIZE);
        memset(
            invalid.validators[i].proposal_pubkey,
            (int)(0x50u + (i & 0x3fu)),
            LANTERN_VALIDATOR_PUBKEY_SIZE);
    }

    int stored = lantern_storage_save_state(&storage, &invalid);
    LanternState loaded;
    lantern_state_init(&loaded);
    int accepted = stored == 0 && lantern_storage_load_state(&storage, &loaded) == 0;
    lantern_state_reset(&loaded);
    lantern_state_reset(&invalid);
    cleanup_storage(&storage, directory);
    if (accepted)
    {
        fprintf(stderr, "storage accepted a state beyond the validator registry limit\n");
        return 1;
    }
    return 0;
}

static int test_storage_prunes_before_slot(void)
{
    char template[] = "/tmp/lantern_storage_pruneXXXXXX";
    char *directory = mkdtemp(template);
    struct lantern_storage storage = {0};
    LanternState state;
    LanternState snapshots[3];
    LanternSignedBlock blocks[3];
    LanternRoot roots[3];
    LanternSignedBlockList collected = {0};
    lantern_state_init(&state);
    if (!directory || lantern_storage_open(&storage, directory) != 0)
    {
        return 1;
    }
    expect_zero(lantern_state_generate_genesis(&state, 123456u, 4u), "generate prune genesis");
    populate_pubkeys(&state, 0xB0u);
    for (size_t i = 0; i < 3u; ++i)
    {
        uint64_t slot = (uint64_t)i + 1u;
        build_signed_block(&state, slot, &blocks[i], &roots[i]);
        expect_zero(
            lantern_storage_store_block_for_root(&storage, &roots[i], &blocks[i]),
            "store prune block");
        lantern_state_init(&snapshots[i]);
        expect_zero(lantern_state_clone(&state, &snapshots[i]), "clone prune state");
        snapshots[i].slot = slot;
        snapshots[i].latest_block_header.slot = slot;
        expect_zero(
            lantern_storage_store_state_for_root(&storage, &roots[i], &snapshots[i]),
            "store prune state");
    }

    int pruned = lantern_storage_prune_before_slot(&storage, 3u, &roots[1], 1u);
    if (pruned != 2)
    {
        fprintf(stderr, "expected prune count 2 got %d\n", pruned);
        return 1;
    }
    expect_zero(
        lantern_storage_collect_blocks(&storage, roots, 3u, &collected),
        "collect pruned blocks");
    if (collected.length != 2u || collected.blocks[0].block.slot != 2u
        || collected.blocks[1].block.slot != 3u)
    {
        fprintf(stderr, "prune retained the wrong blocks\n");
        return 1;
    }
    for (size_t i = 0; i < 3u; ++i)
    {
        uint8_t *bytes = NULL;
        size_t length = 0u;
        int result = lantern_storage_load_state_bytes_for_root(
            &storage,
            &roots[i],
            &bytes,
            &length);
        free(bytes);
        if ((i == 0u && result != 1) || (i != 0u && result != 0))
        {
            fprintf(stderr, "prune retained the wrong states\n");
            return 1;
        }
    }

    lantern_signed_block_list_reset(&collected);
    for (size_t i = 0; i < 3u; ++i)
    {
        lantern_signed_block_reset(&blocks[i]);
        lantern_state_reset(&snapshots[i]);
    }
    lantern_state_reset(&state);
    cleanup_storage(&storage, directory);
    return 0;
}

int main(void)
{
    char template[] = "/tmp/lantern_storage_testXXXXXX";
    char *directory = mkdtemp(template);
    struct lantern_storage storage = {0};
    if (!directory)
    {
        return EXIT_FAILURE;
    }
    expect_zero(lantern_storage_open(&storage, directory), "open storage");

    LanternState state;
    lantern_state_init(&state);
    expect_zero(lantern_state_generate_genesis(&state, 123456u, 4u), "generate genesis");
    populate_pubkeys(&state, 0xA0u);
    expect_zero(lantern_storage_save_state(&storage, &state), "save state");

    LanternSignedBlock block;
    LanternRoot root;
    build_signed_block(&state, 1u, &block, &root);
    expect_zero(lantern_storage_store_block(&storage, &block), "store block");
    expect_zero(lantern_storage_store_block(&storage, &block), "store duplicate block");
    lantern_storage_close(&storage);
    expect_zero(lantern_storage_open(&storage, directory), "reopen storage");

    LanternState loaded;
    lantern_state_init(&loaded);
    expect_zero(lantern_storage_load_state(&storage, &loaded), "load state after reopen");
    assert(loaded.validator_count == state.validator_count);
    lantern_state_reset(&loaded);
    LanternSignedBlockList collected = {0};
    expect_zero(
        lantern_storage_collect_blocks(&storage, &root, 1u, &collected),
        "collect block");
    assert(collected.length == 1u && collected.blocks[0].block.slot == 1u);
    struct iterate_context context = {0};
    expect_zero(lantern_storage_iterate_blocks(&storage, count_block, &context), "iterate blocks");
    assert(context.count == 1u);

    lantern_signed_block_list_reset(&collected);
    lantern_signed_block_reset(&block);
    lantern_state_reset(&state);
    cleanup_storage(&storage, directory);
    if (test_storage_rejects_excess_validators() != 0
        || test_storage_prunes_before_slot() != 0)
    {
        return EXIT_FAILURE;
    }
    return EXIT_SUCCESS;
}
