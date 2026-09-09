#ifdef NDEBUG
#undef NDEBUG
#endif
#include <assert.h>
#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "lantern/consensus/fork_choice.h"
#include "lantern/consensus/hash.h"
#include "lantern/consensus/ssz.h"
#include "lantern/storage/storage.h"
#include "../../src/core/client/internal.h"

/* Public fork-choice operations against a real, isolated disk backing store. */
struct test_storage
{
    struct lantern_storage disk;
    bool fail_read;
    bool fail_write;
    bool truncate_read;
    size_t reads;
};

static int load_state(void *context, const LanternRoot *root, LanternState *out)
{
    struct test_storage *storage = context;
    ++storage->reads;
    if (storage->fail_read)
    {
        return -1;
    }

    uint8_t *bytes = NULL;
    size_t length = 0;
    int result = lantern_storage_load_state_bytes_for_root(&storage->disk, root, &bytes, &length);
    if (result == 0)
    {
        size_t decoded_length = storage->truncate_read && length > 0u ? length - 1u : length;
        result = lantern_ssz_decode_state(out, bytes, decoded_length) == SSZ_SUCCESS ? 0 : -1;
    }

    free(bytes);
    return result;
}

static int save_state(void *context, const LanternRoot *root, const LanternState *state)
{
    struct test_storage *storage = context;
    return storage->fail_write ? -1
        : lantern_storage_store_state_for_root(&storage->disk, root, state);
}

static LanternRoot root_for(unsigned index)
{
    LanternRoot root = {0};
    root.bytes[0] = (uint8_t)(index + 1u);
    return root;
}

static LanternCheckpoint checkpoint(unsigned index, uint64_t slot)
{
    LanternCheckpoint result = {.root = root_for(index), .slot = slot};
    return result;
}

static void make_state(LanternState *state, uint64_t slot, LanternCheckpoint finalized)
{
    lantern_state_init(state);
    state->config.genesis_time = 1000u;
    state->slot = slot;
    state->latest_block_header.slot = slot;
    state->latest_finalized = finalized;
    state->latest_justified = finalized;
    state->validator_count = 4u;
    state->validators = calloc(state->validator_count, sizeof(*state->validators));
    assert(state->validators);
    for (size_t i = 0; i < state->validator_count; ++i)
    {
        state->validators[i].index = i;
    }

    assert(lantern_root_list_resize(&state->historical_block_hashes, (size_t)slot + 1u) == 0);
}

static size_t cached_states(const LanternStore *store)
{
    size_t count = 0;
    for (size_t i = 0; i < store->block_len; ++i)
    {
        count += store->blocks[i].state.validator_count != 0u;
    }

    return count;
}

static bool resident(const LanternStore *store, const LanternRoot *root)
{
    for (size_t i = 0; i < store->block_len; ++i)
    {
        if (memcmp(store->blocks[i].root.bytes, root->bytes, LANTERN_ROOT_SIZE) == 0)
        {
            return store->blocks[i].state.validator_count != 0u;
        }
    }

    return false;
}

static void assert_same_state(const LanternState *left, const LanternState *right)
{
    LanternRoot a;
    LanternRoot b;
    assert(left && right);
    assert(lantern_hash_tree_root_state(left, &a) == SSZ_SUCCESS);
    assert(lantern_hash_tree_root_state(right, &b) == SSZ_SUCCESS);
    assert(memcmp(a.bytes, b.bytes, LANTERN_ROOT_SIZE) == 0);
}

static void assert_same_view(const LanternStore *left, const LanternStore *right)
{
    assert(memcmp(left->head.bytes, right->head.bytes, LANTERN_ROOT_SIZE) == 0);
    assert(left->latest_justified.slot == right->latest_justified.slot);
    assert(memcmp(left->latest_justified.root.bytes, right->latest_justified.root.bytes, LANTERN_ROOT_SIZE) == 0);
    assert(left->latest_finalized.slot == right->latest_finalized.slot);
    assert(memcmp(left->latest_finalized.root.bytes, right->latest_finalized.root.bytes, LANTERN_ROOT_SIZE) == 0);
    assert_same_state(lantern_fork_choice_block_state(left, &left->head),
        lantern_fork_choice_block_state(right, &right->head));
}

static void add_state(LanternStore *store, unsigned index, unsigned parent, uint64_t slot,
    LanternCheckpoint justified, LanternCheckpoint finalized)
{
    LanternState state;
    make_state(&state, slot, finalized);
    state.latest_justified = justified;
    LanternBlock block = {.slot = slot, .parent_root = root_for(parent)};
    LanternRoot root = root_for(index);
    assert(lantern_fork_choice_add_block_with_state(
        store, &block, &justified, &finalized, &root, &state) == 0);
    lantern_state_reset(&state);
}

static void clear_test_directory(const char *path)
{
    const char *names[] = {"states", "blocks"};
    for (size_t i = 0; i < 2u; ++i)
    {
        char directory[256];
        snprintf(directory, sizeof(directory), "%s/%s", path, names[i]);
        DIR *dir = opendir(directory);
        assert(dir);
        struct dirent *entry;
        while ((entry = readdir(dir)) != NULL)
        {
            if (entry->d_name[0] == '.')
            {
                continue;
            }

            char file[512];
            snprintf(file, sizeof(file), "%s/%s", directory, entry->d_name);
            assert(unlink(file) == 0);
        }

        closedir(dir);
        assert(rmdir(directory) == 0);
    }

    assert(rmdir(path) == 0);
}

static void test_startup_restoration(void)
{
    char directory[] = "/tmp/lantern-cache-restore-XXXXXX";
    assert(mkdtemp(directory));
    struct lantern_client client = {0};
    client.node_id = "cache_restore";
    client.data_dir = directory;
    assert(lantern_storage_open(&client.storage, directory) == 0);
    lantern_state_init(&client.state);
    assert(lantern_state_generate_genesis(&client.state, 1000u, 4u) == 0);
    assert(initialize_fork_choice(&client) == LANTERN_CLIENT_OK);
    LanternRoot parent = client.store.head;
    LanternCheckpoint finalized = client.store.latest_finalized;

    for (uint64_t slot = 1u; slot <= 32u; ++slot)
    {
        LanternSignedBlock block;
        lantern_signed_block_init(&block);
        block.block.slot = slot;
        block.block.parent_root = parent;
        LanternState state;
        make_state(&state, slot, finalized);
        state.latest_block_header.parent_root = parent;
        assert(lantern_hash_tree_root_state(&state, &block.block.state_root) == SSZ_SUCCESS);
        LanternRoot root;
        assert(lantern_hash_tree_root_block(&block.block, &root) == SSZ_SUCCESS);
        state.latest_justified = (LanternCheckpoint){.root = root, .slot = slot};
        assert(lantern_storage_store_block_for_root(&client.storage, &root, &block) == 0);
        assert(lantern_storage_store_state_for_root(&client.storage, &root, &state) == 0);
        parent = root;
        lantern_state_reset(&state);
        lantern_signed_block_reset(&block);
    }

    assert(restore_persisted_blocks(&client) == LANTERN_CLIENT_OK);
    assert(client.store.block_len == 33u);
    assert(cached_states(&client.store) <= 10u);
    assert(memcmp(client.store.head.bytes, parent.bytes, LANTERN_ROOT_SIZE) == 0);
    assert(lantern_fork_choice_block_state(&client.store, &finalized.root));
    assert(cached_states(&client.store) <= 10u);
    lantern_store_reset(&client.store);
    lantern_state_reset(&client.state);
    lantern_storage_close(&client.storage);
    clear_test_directory(directory);
}

int main(void)
{
    char directory[] = "/tmp/lantern-state-cache-XXXXXX";
    assert(mkdtemp(directory));
    struct test_storage storage = {0};
    assert(lantern_storage_open(&storage.disk, directory) == 0);
    const struct lantern_state_storage callbacks =
    {
        .load = load_state,
        .save = save_state,
        .context = &storage,
    };
    LanternStore cached;
    LanternStore reference;
    lantern_store_init(&cached);
    lantern_store_init(&reference);
    assert(lantern_fork_choice_set_state_storage(&cached, &callbacks) == 0);
    assert(lantern_fork_choice_set_state_storage(&cached, &callbacks) == -1);
    LanternState genesis;
    make_state(&genesis, 0u, checkpoint(0, 0));
    LanternBlock anchor = {0};
    LanternRoot genesis_root = root_for(0);
    LanternCheckpoint genesis_cp = checkpoint(0, 0);
    assert(lantern_fork_choice_set_anchor_with_state(
        &cached, &anchor, &genesis_cp, &genesis_cp, &genesis_root, &genesis) == 0);
    assert(lantern_fork_choice_set_anchor_with_state(
        &reference, &anchor, &genesis_cp, &genesis_cp, &genesis_root, &genesis) == 0);
    lantern_state_reset(&genesis);

    for (unsigned i = 1; i <= 40u; ++i)
    {
        add_state(&cached, i, i - 1u, i, checkpoint(i, i), genesis_cp);
        add_state(&reference, i, i - 1u, i, checkpoint(i, i), genesis_cp);
        assert(cached_states(&cached) <= 10u);
        assert(cached.block_len == reference.block_len);
        assert_same_view(&cached, &reference);
    }

    assert(cached_states(&cached) == 10u);
    assert(cached_states(&reference) == 41u);
    LanternRoot oldest = root_for(1);
    assert(!resident(&cached, &oldest));
    size_t reads = storage.reads;
    assert_same_state(lantern_fork_choice_block_state(&cached, &oldest),
        lantern_fork_choice_block_state(&reference, &oldest));
    assert(storage.reads == reads + 1u);
    assert(resident(&cached, &cached.head));
    assert(cached_states(&cached) == 10u);

    LanternRoot corrupt = root_for(2u);
    assert(!resident(&cached, &corrupt));
    storage.truncate_read = true;
    assert(lantern_fork_choice_block_state(&cached, &corrupt) == NULL);
    assert(cached_states(&cached) == 10u);
    assert_same_view(&cached, &reference);
    storage.truncate_read = false;
    assert_same_state(lantern_fork_choice_block_state(&cached, &corrupt),
        lantern_fork_choice_block_state(&reference, &corrupt));

    /* A branch's old head can be selected after its post-state was evicted. */
    add_state(&cached, 100u, 1u, 2u, genesis_cp, checkpoint(1, 1));
    add_state(&reference, 100u, 1u, 2u, genesis_cp, checkpoint(1, 1));
    for (unsigned i = 41; i <= 55u; ++i)
    {
        add_state(&cached, i, i - 1u, i, checkpoint(i, i), genesis_cp);
        add_state(&reference, i, i - 1u, i, checkpoint(i, i), genesis_cp);
    }

    LanternRoot branch = root_for(100u);
    LanternCheckpoint branch_cp = checkpoint(100u, 2u);
    assert(!resident(&cached, &branch));
    LanternRoot previous_head = cached.head;
    storage.fail_read = true;
    assert(lantern_fork_choice_restore_checkpoints(&cached, &branch_cp, &genesis_cp) == -1);
    assert(memcmp(cached.head.bytes, previous_head.bytes, LANTERN_ROOT_SIZE) == 0);
    assert(cached.latest_finalized.slot == 0u);
    assert_same_view(&cached, &reference);
    storage.fail_read = false;
    assert(lantern_fork_choice_restore_checkpoints(&cached, &branch_cp, &genesis_cp) == 0);
    assert(lantern_fork_choice_restore_checkpoints(&reference, &branch_cp, &genesis_cp) == 0);
    assert_same_view(&cached, &reference);
    assert(cached.latest_finalized.slot == 1u);
    assert(cached_states(&cached) <= 10u);

    storage.fail_write = true;
    LanternState failed;
    make_state(&failed, 3u, checkpoint(1, 1));
    LanternBlock failed_block = {.slot = 3u, .parent_root = branch};
    LanternRoot failed_root = root_for(101u);
    size_t previous_count = cached.block_len;
    assert(lantern_fork_choice_add_block_with_state(&cached, &failed_block,
        &branch_cp, &genesis_cp, &failed_root, &failed) == -1);
    assert(cached.block_len == previous_count);
    assert_same_view(&cached, &reference);
    lantern_state_reset(&failed);
    storage.fail_write = false;

    assert(lantern_fork_choice_prune_states(&cached) == 0);
    assert(lantern_fork_choice_prune_states(&reference) == 0);
    assert_same_view(&cached, &reference);
    assert(cached.block_len == reference.block_len);
    assert(cached_states(&cached) <= 10u);
    /* Large histories must hit the byte budget before the ten-entry limit. */
    unsigned parent = 100u;
    for (unsigned i = 0; i < 8u; ++i)
    {
        unsigned index = 110u + i;
        LanternState large;
        make_state(&large, 3u + i, checkpoint(1, 1));
        assert(lantern_root_list_resize(&large.historical_block_hashes,
            LANTERN_HISTORICAL_ROOTS_LIMIT) == 0);
        assert(lantern_root_list_resize(&large.justification_roots,
            LANTERN_HISTORICAL_ROOTS_LIMIT) == 0);
        LanternBlock block = {.slot = 3u + i, .parent_root = root_for(parent)};
        LanternRoot root = root_for(index);
        LanternCheckpoint justified = checkpoint(index, block.slot);
        large.latest_justified = justified;
        assert(lantern_fork_choice_add_block_with_state(&cached, &block,
            &justified, &large.latest_finalized, &root, &large) == 0);
        lantern_state_reset(&large);
        parent = index;
    }

    assert(cached_states(&cached) <= 3u);
    assert(resident(&cached, &cached.head));
    LanternRoot cold_large = root_for(110u);
    assert(!resident(&cached, &cold_large));
    assert(lantern_fork_choice_block_state(&cached, &cold_large));
    assert(resident(&cached, &cached.head));
    assert(cached_states(&cached) <= 3u);

    LanternState oversized;
    make_state(&oversized, 11u, checkpoint(1, 1));
    assert(lantern_bitlist_resize(&oversized.justification_validators, 65u * 1024u * 1024u * 8u) == 0);
    LanternBlock oversized_block = {.slot = 11u, .parent_root = cached.head};
    LanternRoot oversized_root = root_for(120u);
    LanternCheckpoint oversized_cp = checkpoint(120u, 11u);
    assert(lantern_fork_choice_add_block_with_state(&cached, &oversized_block,
        &oversized_cp, &oversized.latest_finalized, &oversized_root, &oversized) == 0);
    assert(cached_states(&cached) <= 2u);
    assert_same_state(lantern_fork_choice_block_state(&cached, &oversized_root), &oversized);
    lantern_state_reset(&oversized);

    lantern_store_reset(&cached);
    lantern_store_reset(&reference);
    lantern_storage_close(&storage.disk);
    clear_test_directory(directory);
    test_startup_restoration();
    puts("Post-state cache: bound, cold reads, head protection, reorg/finality equivalence, I/O failures, byte-budget eviction, and startup restoration passed.");
    return 0;
}
