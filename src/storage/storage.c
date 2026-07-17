#include "lantern/storage/storage.h"

#include <dirent.h>
#include <errno.h>
#include <inttypes.h>
#include <limits.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#if defined(_WIN32)
#include <direct.h>
#include <io.h>
#endif

#include "lantern/consensus/hash.h"
#include "lantern/consensus/ssz.h"
#include "lantern/support/log.h"
#include "lantern/support/strings.h"
#include "ssz.h"

#define STORAGE_BLOCKS_DIR "blocks"
#define STORAGE_STATES_DIR "states"
#define STORAGE_STATE_FILE "state.ssz"

struct storage_context {
    char *blocks_dir;
    char *states_dir;
    char *state_file;
    pthread_rwlock_t lock;
};

static struct storage_context *get_context(const struct lantern_storage *storage)
{
    return storage ? storage->backend : NULL;
}

static int ensure_directory(const char *path)
{
    struct stat status;
    if (!path)
    {
        return -1;
    }
    if (stat(path, &status) == 0)
    {
        return S_ISDIR(status.st_mode) ? 0 : -1;
    }
#if defined(_WIN32)
    return _mkdir(path) == 0 || errno == EEXIST ? 0 : -1;
#else
    return mkdir(path, 0700) == 0 || errno == EEXIST ? 0 : -1;
#endif
}

static char *join_path(const char *directory, const char *leaf)
{
    if (!directory || !leaf)
    {
        return NULL;
    }
    size_t directory_length = strlen(directory);
    size_t leaf_length = strlen(leaf);
    bool separator = directory_length > 0u
        && directory[directory_length - 1u] != '/'
        && directory[directory_length - 1u] != '\\';
    if (directory_length > SIZE_MAX - leaf_length - 2u)
    {
        return NULL;
    }
    size_t length = directory_length + leaf_length + (separator ? 2u : 1u);
    char *path = malloc(length);
    if (path)
    {
        snprintf(path, length, "%s%s%s", directory, separator ? "/" : "", leaf);
    }
    return path;
}

static int sync_file(FILE *file)
{
#if defined(_WIN32)
    return _commit(_fileno(file));
#else
    return fsync(fileno(file));
#endif
}

static int write_atomic_file(const char *path, const uint8_t *data, size_t length)
{
    if (!path || !data || length == 0u)
    {
        return -1;
    }
    size_t path_length = strlen(path);
    char *temporary = malloc(path_length + sizeof(".tmp"));
    if (!temporary)
    {
        return -1;
    }
    memcpy(temporary, path, path_length);
    memcpy(temporary + path_length, ".tmp", sizeof(".tmp"));
    FILE *file = fopen(temporary, "wb");
    int result = -1;
    if (file
        && fwrite(data, 1u, length, file) == length
        && fflush(file) == 0
        && sync_file(file) == 0)
    {
        int close_result = fclose(file);
        file = NULL;
        if (close_result != 0)
        {
            goto cleanup;
        }
#if defined(_WIN32)
        if (remove(path) != 0 && errno != ENOENT)
        {
            goto cleanup;
        }
#endif
        result = rename(temporary, path) == 0 ? 0 : -1;
    }
cleanup:
    if (file)
    {
        fclose(file);
    }
    if (result != 0)
    {
        (void)remove(temporary);
    }
    free(temporary);
    return result;
}

static int read_file(const char *path, uint8_t **out_data, size_t *out_length)
{
    if (!path || !out_data || !out_length)
    {
        return -1;
    }
    *out_data = NULL;
    *out_length = 0u;
    FILE *file = fopen(path, "rb");
    if (!file)
    {
        return errno == ENOENT ? 1 : -1;
    }
    uint8_t *data = NULL;
    int result = -1;
    if (fseek(file, 0, SEEK_END) != 0)
    {
        goto cleanup;
    }
    long size = ftell(file);
    if (size <= 0 || (uintmax_t)size > SIZE_MAX || fseek(file, 0, SEEK_SET) != 0)
    {
        goto cleanup;
    }
    data = malloc((size_t)size);
    if (!data || fread(data, 1u, (size_t)size, file) != (size_t)size)
    {
        goto cleanup;
    }
    *out_data = data;
    *out_length = (size_t)size;
    data = NULL;
    result = 0;
cleanup:
    if (fclose(file) != 0 && result == 0)
    {
        free(*out_data);
        *out_data = NULL;
        *out_length = 0u;
        result = -1;
    }
    free(data);
    return result;
}

static char *root_path(const char *directory, const LanternRoot *root)
{
    if (!directory || !root)
    {
        return NULL;
    }
    char filename[(2u * LANTERN_ROOT_SIZE) + sizeof(".ssz")];
    if (lantern_bytes_to_hex(
            root->bytes, LANTERN_ROOT_SIZE, filename, sizeof(filename) - 4u, 0) != 0)
    {
        return NULL;
    }
    memcpy(filename + (2u * LANTERN_ROOT_SIZE), ".ssz", sizeof(".ssz"));
    return join_path(directory, filename);
}

static bool filename_root(const char *filename, LanternRoot *root)
{
    if (!filename || !root || strlen(filename) != (2u * LANTERN_ROOT_SIZE) + 4u
        || strcmp(filename + (2u * LANTERN_ROOT_SIZE), ".ssz") != 0)
    {
        return false;
    }
    char hex[(2u * LANTERN_ROOT_SIZE) + 1u];
    memcpy(hex, filename, sizeof(hex) - 1u);
    hex[sizeof(hex) - 1u] = '\0';
    return lantern_hex_decode(hex, root->bytes, LANTERN_ROOT_SIZE) == 0;
}

int lantern_storage_open(struct lantern_storage *storage, const char *data_dir)
{
    if (!storage || storage->backend || ensure_directory(data_dir) != 0)
    {
        return -1;
    }
    struct storage_context *context = calloc(1u, sizeof(*context));
    if (!context)
    {
        return -1;
    }
    context->blocks_dir = join_path(data_dir, STORAGE_BLOCKS_DIR);
    context->states_dir = join_path(data_dir, STORAGE_STATES_DIR);
    context->state_file = join_path(data_dir, STORAGE_STATE_FILE);
    if (!context->blocks_dir || !context->states_dir || !context->state_file
        || ensure_directory(context->blocks_dir) != 0
        || ensure_directory(context->states_dir) != 0
        || pthread_rwlock_init(&context->lock, NULL) != 0)
    {
        free(context->blocks_dir);
        free(context->states_dir);
        free(context->state_file);
        free(context);
        return -1;
    }
    storage->backend = context;
    return 0;
}

void lantern_storage_close(struct lantern_storage *storage)
{
    struct storage_context *context = get_context(storage);
    if (!context)
    {
        return;
    }
    storage->backend = NULL;
    pthread_rwlock_destroy(&context->lock);
    free(context->blocks_dir);
    free(context->states_dir);
    free(context->state_file);
    free(context);
}

static int encode_state(const LanternState *state, uint8_t **out_data, size_t *out_length)
{
    size_t length = 0u;
    if (!state || state->validator_count == 0u || !out_data || !out_length
        || lantern_ssz_encode_state(state, NULL, 0u, &length) != SSZ_SUCCESS || length == 0u)
    {
        return -1;
    }
    uint8_t *data = malloc(length);
    size_t written = 0u;
    if (!data || lantern_ssz_encode_state(state, data, length, &written) != SSZ_SUCCESS
        || written != length)
    {
        free(data);
        return -1;
    }
    *out_data = data;
    *out_length = length;
    return 0;
}

static int encode_block(const LanternSignedBlock *block, uint8_t **out_data, size_t *out_length)
{
    size_t length = 0u;
    if (!block || !out_data || !out_length
        || lantern_ssz_encode_signed_block(block, NULL, 0u, &length) != SSZ_SUCCESS || length == 0u)
    {
        return -1;
    }
    uint8_t *data = malloc(length);
    size_t written = 0u;
    if (!data || lantern_ssz_encode_signed_block(block, data, length, &written) != SSZ_SUCCESS
        || written != length)
    {
        free(data);
        return -1;
    }
    *out_data = data;
    *out_length = length;
    return 0;
}

static int write_storage_file(
    const struct lantern_storage *storage,
    const char *path,
    const uint8_t *data,
    size_t length,
    bool immutable)
{
    struct storage_context *context = get_context(storage);
    if (!context || !path || pthread_rwlock_wrlock(&context->lock) != 0)
    {
        return -1;
    }
    int result = -1;
    struct stat status;
    if (immutable && stat(path, &status) == 0)
    {
        result = S_ISREG(status.st_mode) ? 0 : -1;
    }
    else if (!immutable || errno == ENOENT)
    {
        result = write_atomic_file(path, data, length);
    }
    pthread_rwlock_unlock(&context->lock);
    return result;
}

static int read_storage_file(
    const struct lantern_storage *storage,
    const char *path,
    uint8_t **out_data,
    size_t *out_length)
{
    struct storage_context *context = get_context(storage);
    if (!context || !path || pthread_rwlock_rdlock(&context->lock) != 0)
    {
        return -1;
    }
    int result = read_file(path, out_data, out_length);
    pthread_rwlock_unlock(&context->lock);
    return result;
}

int lantern_storage_save_state(const struct lantern_storage *storage, const LanternState *state)
{
    struct storage_context *context = get_context(storage);
    uint8_t *data = NULL;
    size_t length = 0u;
    if (!context || encode_state(state, &data, &length) != 0)
    {
        return -1;
    }
    int result = write_storage_file(storage, context->state_file, data, length, false);
    free(data);
    return result;
}

int lantern_storage_load_state(const struct lantern_storage *storage, LanternState *state)
{
    struct storage_context *context = get_context(storage);
    if (!context || !state)
    {
        return -1;
    }
    uint8_t *data = NULL;
    size_t length = 0u;
    int result = read_storage_file(storage, context->state_file, &data, &length);
    if (result != 0)
    {
        return result;
    }
    LanternState decoded;
    lantern_state_init(&decoded);
    if (lantern_ssz_decode_state(&decoded, data, length) != SSZ_SUCCESS
        || decoded.validator_count == 0u)
    {
        result = -1;
    }
    else
    {
        lantern_state_reset(state);
        *state = decoded;
        decoded = (LanternState){0};
    }
    lantern_state_reset(&decoded);
    free(data);
    return result;
}

static bool block_is_synthetic_anchor_alias(const LanternSignedBlock *block)
{
    const LanternBlockBody *body = block ? &block->block.body : NULL;
    return body && body->attestations.length == 0u && !body->attestations.data
        && block->proof.length == 0u && !block->proof.data;
}

static int verify_block_root(const LanternSignedBlock *block, const LanternRoot *root)
{
    LanternRoot computed;
    if (!block || !root || lantern_hash_tree_root_block(&block->block, &computed) != SSZ_SUCCESS)
    {
        return -1;
    }
    if (memcmp(computed.bytes, root->bytes, LANTERN_ROOT_SIZE) == 0)
    {
        return 0;
    }
    if (!block_is_synthetic_anchor_alias(block))
    {
        return -1;
    }
    lantern_log_warn(
        "storage",
        &(const struct lantern_log_metadata){0},
        "accepted synthetic anchor root alias at slot=%" PRIu64,
        block->block.slot);
    return 0;
}

static int store_block(
    const struct lantern_storage *storage,
    const LanternRoot *root,
    const LanternSignedBlock *block)
{
    struct storage_context *context = get_context(storage);
    char *path = context ? root_path(context->blocks_dir, root) : NULL;
    uint8_t *data = NULL;
    size_t length = 0u;
    if (!path || encode_block(block, &data, &length) != 0)
    {
        free(path);
        return -1;
    }
    int result = write_storage_file(storage, path, data, length, true);
    free(data);
    free(path);
    return result;
}

int lantern_storage_store_block(const struct lantern_storage *storage, const LanternSignedBlock *block)
{
    LanternRoot root;
    return block && lantern_hash_tree_root_block(&block->block, &root) == SSZ_SUCCESS
        ? store_block(storage, &root, block)
        : -1;
}

int lantern_storage_store_block_for_root(
    const struct lantern_storage *storage,
    const LanternRoot *root,
    const LanternSignedBlock *block)
{
    return root && block ? store_block(storage, root, block) : -1;
}

int lantern_storage_store_state_for_root(
    const struct lantern_storage *storage,
    const LanternRoot *root,
    const LanternState *state)
{
    struct storage_context *context = get_context(storage);
    char *path = context ? root_path(context->states_dir, root) : NULL;
    uint8_t *data = NULL;
    size_t length = 0u;
    if (!path || encode_state(state, &data, &length) != 0)
    {
        free(path);
        return -1;
    }
    int result = write_storage_file(storage, path, data, length, false);
    free(data);
    free(path);
    return result;
}

static int load_root_bytes(
    const struct lantern_storage *storage,
    const char *directory,
    const LanternRoot *root,
    uint8_t **out_data,
    size_t *out_length)
{
    char *path = root_path(directory, root);
    if (!path)
    {
        return -1;
    }
    int result = read_storage_file(storage, path, out_data, out_length);
    free(path);
    return result;
}

int lantern_storage_load_state_bytes_for_root(
    const struct lantern_storage *storage,
    const LanternRoot *root,
    uint8_t **out_data,
    size_t *out_len)
{
    struct storage_context *context = get_context(storage);
    return context && root
        ? load_root_bytes(storage, context->states_dir, root, out_data, out_len)
        : -1;
}

int lantern_storage_load_block_bytes_for_root(
    const struct lantern_storage *storage,
    const LanternRoot *root,
    uint8_t **out_data,
    size_t *out_len)
{
    struct storage_context *context = get_context(storage);
    return context && root
        ? load_root_bytes(storage, context->blocks_dir, root, out_data, out_len)
        : -1;
}

int lantern_storage_collect_blocks(
    const struct lantern_storage *storage,
    const LanternRoot *roots,
    size_t root_count,
    LanternSignedBlockList *out_blocks)
{
    if (!get_context(storage) || (!roots && root_count > 0u) || !out_blocks
        || lantern_signed_block_list_resize(out_blocks, 0u) != 0)
    {
        return -1;
    }
    for (size_t i = 0; i < root_count; ++i)
    {
        uint8_t *data = NULL;
        size_t length = 0u;
        int result = lantern_storage_load_block_bytes_for_root(storage, &roots[i], &data, &length);
        if (result > 0)
        {
            continue;
        }
        size_t index = out_blocks->length;
        if (result < 0 || lantern_signed_block_list_resize(out_blocks, index + 1u) != 0
            || lantern_ssz_decode_signed_block(&out_blocks->blocks[index], data, length) != SSZ_SUCCESS
            || verify_block_root(&out_blocks->blocks[index], &roots[i]) != 0)
        {
            free(data);
            return -1;
        }
        free(data);
    }
    return 0;
}

static int scan_blocks(
    struct storage_context *storage,
    lantern_storage_block_visitor_fn visitor,
    void *context)
{
    DIR *directory = opendir(storage->blocks_dir);
    if (!directory)
    {
        return errno == ENOENT ? 0 : -1;
    }
    int result = 0;
    struct dirent *entry;
    while ((entry = readdir(directory)) != NULL)
    {
        LanternRoot root;
        if (!filename_root(entry->d_name, &root))
        {
            continue;
        }
        char *path = join_path(storage->blocks_dir, entry->d_name);
        uint8_t *data = NULL;
        size_t length = 0u;
        int read_result = path ? read_file(path, &data, &length) : -1;
        free(path);
        if (read_result > 0)
        {
            continue;
        }
        LanternSignedBlock block;
        lantern_signed_block_init(&block);
        if (read_result < 0
            || lantern_ssz_decode_signed_block(&block, data, length) != SSZ_SUCCESS
            || verify_block_root(&block, &root) != 0)
        {
            result = -1;
        }
        else
        {
            result = visitor(&block, &root, context);
        }
        lantern_signed_block_reset(&block);
        free(data);
        if (result != 0)
        {
            break;
        }
    }
    closedir(directory);
    return result;
}

int lantern_storage_iterate_blocks(
    const struct lantern_storage *storage,
    lantern_storage_block_visitor_fn visitor,
    void *context)
{
    struct storage_context *backend = get_context(storage);
    if (!backend || !visitor || pthread_rwlock_rdlock(&backend->lock) != 0)
    {
        return -1;
    }
    int result = scan_blocks(backend, visitor, context);
    pthread_rwlock_unlock(&backend->lock);
    return result;
}

static bool root_is_kept(
    const LanternRoot *root,
    const LanternRoot *keep_roots,
    size_t keep_root_count)
{
    for (size_t i = 0; i < keep_root_count; ++i)
    {
        if (memcmp(root->bytes, keep_roots[i].bytes, LANTERN_ROOT_SIZE) == 0)
        {
            return true;
        }
    }
    return false;
}

static int remove_root_file(const char *directory, const LanternRoot *root, int *count)
{
    char *path = root_path(directory, root);
    if (!path)
    {
        return -1;
    }
    int result = remove(path);
    int remove_error = errno;
    free(path);
    if (result == 0)
    {
        if (*count == INT_MAX)
        {
            return -1;
        }
        ++*count;
        return 0;
    }
    return remove_error == ENOENT ? 0 : -1;
}

struct prune_context {
    struct storage_context *storage;
    uint64_t slot;
    const LanternRoot *keep_roots;
    size_t keep_root_count;
    int count;
};

static int prune_block(const LanternSignedBlock *block, const LanternRoot *root, void *context)
{
    struct prune_context *prune = context;
    if (block->block.slot >= prune->slot
        || root_is_kept(root, prune->keep_roots, prune->keep_root_count))
    {
        return 0;
    }
    return remove_root_file(prune->storage->states_dir, root, &prune->count) == 0
            && remove_root_file(prune->storage->blocks_dir, root, &prune->count) == 0
        ? 0
        : -1;
}

int lantern_storage_prune_before_slot(
    const struct lantern_storage *storage,
    uint64_t slot,
    const LanternRoot *keep_roots,
    size_t keep_root_count)
{
    struct storage_context *backend = get_context(storage);
    if (!backend || (!keep_roots && keep_root_count > 0u)
        || pthread_rwlock_wrlock(&backend->lock) != 0)
    {
        return -1;
    }
    struct prune_context context = {
        .storage = backend,
        .slot = slot,
        .keep_roots = keep_roots,
        .keep_root_count = keep_root_count,
    };
    int result = scan_blocks(backend, prune_block, &context);
    pthread_rwlock_unlock(&backend->lock);
    return result == 0 ? context.count : -1;
}
