#include "lantern/storage/storage.h"

#include <errno.h>
#include <inttypes.h>
#include <limits.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#include <dirent.h>

#if defined(_WIN32)
#include <direct.h>
#include <io.h>
#endif

#include "lantern/consensus/hash.h"
#include "lantern/consensus/ssz.h"
#include "lantern/networking/messages.h"
#include "lantern/support/log.h"
#include "lantern/support/strings.h"
#include "ssz.h"

#define LANTERN_STORAGE_BLOCKS_DIR "blocks"
#define LANTERN_STORAGE_STATES_DIR "states"
#define LANTERN_STORAGE_STATE_FILE "state.ssz"

#if defined(_WIN32)
#define LANTERN_STORAGE_PATH_SEP '\\'
#else
#define LANTERN_STORAGE_PATH_SEP '/'
#endif

/*
 * Internal helpers for filesystem/path handling, SSZ size estimation, and
 * atomic file reads/writes.
 *
 * Public API: see include/lantern/storage/storage.h
 */

static int ensure_directory(const char *path) {
    if (!path) {
        return -1;
    }
    struct stat st;
    if (stat(path, &st) == 0) {
        return S_ISDIR(st.st_mode) ? 0 : -1;
    }
#if defined(_WIN32)
    if (_mkdir(path) != 0 && errno != EEXIST) {
        return -1;
    }
#else
    if (mkdir(path, 0700) != 0 && errno != EEXIST) {
        return -1;
    }
#endif
    return 0;
}

static int join_path(const char *base, const char *leaf, char **out_path) {
    if (!base || !leaf || !out_path) {
        return -1;
    }
    const size_t base_len = strlen(base);
    const size_t leaf_len = strlen(leaf);
    bool needs_sep = false;
    if (base_len > 0) {
        const char tail = base[base_len - 1];
        needs_sep = (tail != '/' && tail != '\\');
    }
    const size_t total = base_len + (needs_sep ? 1u : 0u) + leaf_len + 1u;
    char *buffer = malloc(total);
    if (!buffer) {
        return -1;
    }
    memcpy(buffer, base, base_len);
    size_t offset = base_len;
    if (needs_sep) {
        buffer[offset++] = LANTERN_STORAGE_PATH_SEP;
    }
    memcpy(buffer + offset, leaf, leaf_len);
    buffer[offset + leaf_len] = '\0';
    *out_path = buffer;
    return 0;
}

static void free_path(char *path) {
    free(path);
}

static int write_atomic_file(const char *path, const uint8_t *data, size_t data_len) {
    if (!path || !data || data_len == 0) {
        return -1;
    }
    int rc = -1;
    FILE *fp = NULL;
    char *tmp_path = NULL;

    const size_t path_len = strlen(path);
    tmp_path = malloc(path_len + sizeof(".tmp"));
    if (!tmp_path) {
        goto cleanup;
    }
    memcpy(tmp_path, path, path_len);
    memcpy(tmp_path + path_len, ".tmp", sizeof(".tmp"));

    fp = fopen(tmp_path, "wb");
    if (!fp) {
        goto cleanup;
    }
    const size_t written = fwrite(data, 1u, data_len, fp);
    if (written != data_len) {
        goto cleanup;
    }
    if (fflush(fp) != 0) {
        goto cleanup;
    }
#if defined(_WIN32)
    if (_commit(_fileno(fp)) != 0) {
        goto cleanup;
    }
#else
    if (fsync(fileno(fp)) != 0) {
        goto cleanup;
    }
#endif
    const int close_rc = fclose(fp);
    fp = NULL;
    if (close_rc != 0) {
        goto cleanup;
    }
#if defined(_WIN32)
    if (remove(path) != 0 && errno != ENOENT) {
        goto cleanup;
    }
#endif
    if (rename(tmp_path, path) != 0) {
        goto cleanup;
    }
    rc = 0;

cleanup:
    if (fp) {
        fclose(fp);
    }
    free(tmp_path);
    return rc;
}

static int read_file_buffer(const char *path, uint8_t **out_data, size_t *out_len) {
    if (!path || !out_data || !out_len) {
        return -1;
    }
    FILE *fp = fopen(path, "rb");
    if (!fp) {
        return (errno == ENOENT) ? 1 : -1;
    }
    int rc = -1;
    uint8_t *buffer = NULL;

    if (fseek(fp, 0, SEEK_END) != 0) {
        goto cleanup;
    }
    const long file_size = ftell(fp);
    if (file_size < 0) {
        goto cleanup;
    }
    if (fseek(fp, 0, SEEK_SET) != 0) {
        goto cleanup;
    }
    if (file_size == 0) {
        rc = 1;
        goto cleanup;
    }
    buffer = malloc((size_t)file_size);
    if (!buffer) {
        goto cleanup;
    }
    const size_t read = fread(buffer, 1u, (size_t)file_size, fp);
    if (read != (size_t)file_size) {
        goto cleanup;
    }

    *out_data = buffer;
    *out_len = (size_t)file_size;
    buffer = NULL;
    rc = 0;

cleanup:
    fclose(fp);
    free(buffer);
    return rc;
}

enum storage_dir_kind {
    STORAGE_DIR_BLOCKS,
    STORAGE_DIR_STATES,
    STORAGE_DIR_COUNT,
};

static const char *const STORAGE_DIR_LEAVES[STORAGE_DIR_COUNT] = {
    [STORAGE_DIR_BLOCKS] = LANTERN_STORAGE_BLOCKS_DIR,
    [STORAGE_DIR_STATES] = LANTERN_STORAGE_STATES_DIR,
};

static int storage_dir_path(
    const char *data_dir,
    enum storage_dir_kind kind,
    char **out_path) {
    if (!data_dir || !out_path) {
        return -1;
    }
    *out_path = NULL;

    const unsigned index = (unsigned)kind;
    if (index >= (unsigned)STORAGE_DIR_COUNT || !STORAGE_DIR_LEAVES[index]) {
        return -1;
    }
    return join_path(data_dir, STORAGE_DIR_LEAVES[index], out_path);
}

static int ensure_storage_dir(
    const char *data_dir,
    enum storage_dir_kind kind,
    char **out_path) {
    if (out_path) {
        *out_path = NULL;
    }
    char *path = NULL;
    if (storage_dir_path(data_dir, kind, &path) != 0 || ensure_directory(path) != 0) {
        free_path(path);
        return -1;
    }
    if (out_path) {
        *out_path = path;
    } else {
        free_path(path);
    }
    return 0;
}

static int storage_dir_file_path(
    const char *data_dir,
    enum storage_dir_kind kind,
    const char *filename,
    bool ensure_parent,
    char **out_path) {
    if (!data_dir || !filename || !out_path) {
        return -1;
    }
    *out_path = NULL;

    char *dir = NULL;
    int rc = ensure_parent
        ? ensure_storage_dir(data_dir, kind, &dir)
        : storage_dir_path(data_dir, kind, &dir);
    if (rc == 0) {
        rc = join_path(dir, filename, out_path);
    }
    free_path(dir);
    return rc;
}

static int storage_root_file_path(
    const char *data_dir,
    enum storage_dir_kind kind,
    const LanternRoot *root,
    bool ensure_parent,
    char **out_path,
    char *out_root_hex,
    size_t out_root_hex_len) {
    if (!data_dir || !root || !out_path) {
        return -1;
    }
    *out_path = NULL;

    char local_hex[2u * LANTERN_ROOT_SIZE + 1u];
    char *root_hex = out_root_hex ? out_root_hex : local_hex;
    size_t root_hex_len = out_root_hex ? out_root_hex_len : sizeof(local_hex);
    if (lantern_bytes_to_hex(root->bytes, LANTERN_ROOT_SIZE, root_hex, root_hex_len, 0) != 0) {
        return -1;
    }

    char filename[2u * LANTERN_ROOT_SIZE + 5u];
    const int wrote = snprintf(filename, sizeof(filename), "%s.ssz", root_hex);
    if (wrote < 0 || (size_t)wrote >= sizeof(filename)) {
        return -1;
    }
    return storage_dir_file_path(data_dir, kind, filename, ensure_parent, out_path);
}

static int storage_write_state_path(const char *path, const LanternState *state) {
    if (!path || !state || state->config.num_validators == 0) {
        return -1;
    }

    int rc = -1;
    uint8_t *buffer = NULL;
    size_t encoded_size = 0;
    if (lantern_ssz_encode_state(state, NULL, 0, &encoded_size) != SSZ_SUCCESS
        || encoded_size == 0) {
        goto cleanup;
    }
    buffer = malloc(encoded_size);
    if (!buffer) {
        goto cleanup;
    }
    size_t written = 0;
    if (lantern_ssz_encode_state(state, buffer, encoded_size, &written) != SSZ_SUCCESS
        || written != encoded_size) {
        goto cleanup;
    }
    rc = write_atomic_file(path, buffer, written);

cleanup:
    free(buffer);
    return rc;
}

static int storage_save_state_file(
    const char *data_dir,
    const char *filename,
    const LanternState *state) {
    if (!data_dir || !filename) {
        return -1;
    }

    char *path = NULL;
    int rc = join_path(data_dir, filename, &path);
    if (rc == 0) {
        rc = storage_write_state_path(path, state);
    }
    free_path(path);
    return rc;
}

static int storage_load_state_file(
    const char *data_dir,
    const char *filename,
    LanternState *state) {
    if (!data_dir || !filename || !state) {
        return -1;
    }

    int rc = -1;
    char *path = NULL;
    uint8_t *data = NULL;
    size_t data_len = 0;
    LanternState decoded;
    lantern_state_init(&decoded);
    bool decoded_owned = true;

    if (join_path(data_dir, filename, &path) != 0) {
        goto cleanup;
    }
    rc = read_file_buffer(path, &data, &data_len);
    if (rc != 0) {
        goto cleanup;
    }
    if (lantern_ssz_decode_state(&decoded, data, data_len) != SSZ_SUCCESS
        || decoded.config.num_validators == 0) {
        rc = -1;
        goto cleanup;
    }
    lantern_state_reset(state);
    *state = decoded;
    decoded_owned = false;
    rc = 0;

cleanup:
    free_path(path);
    free(data);
    if (decoded_owned) {
        lantern_state_reset(&decoded);
    }
    return rc;
}

static int storage_load_root_bytes(
    const char *data_dir,
    enum storage_dir_kind kind,
    const LanternRoot *root,
    uint8_t **out_data,
    size_t *out_len) {
    if (!data_dir || !root || !out_data || !out_len) {
        return -1;
    }
    *out_data = NULL;
    *out_len = 0;

    char *path = NULL;
    uint8_t *data = NULL;
    size_t len = 0;
    int rc = storage_root_file_path(data_dir, kind, root, false, &path, NULL, 0);
    if (rc != 0) {
        goto cleanup;
    }
    rc = read_file_buffer(path, &data, &len);
    if (rc != 0) {
        rc = (rc > 0) ? 1 : -1;
        goto cleanup;
    }

    *out_data = data;
    *out_len = len;
    data = NULL;

cleanup:
    free_path(path);
    free(data);
    return rc;
}

static bool storage_root_is_kept(
    const LanternRoot *root,
    const LanternRoot *keep_roots,
    size_t keep_root_count) {
    if (!root || !keep_roots || keep_root_count == 0) {
        return false;
    }
    for (size_t i = 0; i < keep_root_count; ++i) {
        if (memcmp(root->bytes, keep_roots[i].bytes, LANTERN_ROOT_SIZE) == 0) {
            return true;
        }
    }
    return false;
}

static int remove_storage_path(const char *path, int *pruned) {
    if (!path || !pruned) {
        return -1;
    }
    if (remove(path) != 0) {
        return (errno == ENOENT) ? 0 : -1;
    }
    if (*pruned < INT_MAX) {
        *pruned += 1;
    }
    return 0;
}

/**
 * Ensure all storage directories exist under `data_dir`.
 *
 * @param data_dir Base directory path.
 * @return 0 on success.
 * @return -1 on invalid parameters or filesystem errors.
 */
int lantern_storage_prepare(const char *data_dir) {
    if (!data_dir) {
        return -1;
    }

    if (ensure_directory(data_dir) != 0) {
        return -1;
    }
    const enum storage_dir_kind dirs[] = {
        STORAGE_DIR_BLOCKS,
        STORAGE_DIR_STATES,
    };
    for (size_t i = 0; i < sizeof(dirs) / sizeof(dirs[0]); ++i) {
        if (ensure_storage_dir(data_dir, dirs[i], NULL) != 0) {
            return -1;
        }
    }
    return 0;
}

/**
 * Persist `state` under `data_dir` using SSZ (`state.ssz`).
 *
 * @param data_dir Base directory path.
 * @param state State to persist.
 * @return 0 on success.
 * @return -1 on invalid parameters, encoding failure, or filesystem errors.
 */
int lantern_storage_save_state(const char *data_dir, const LanternState *state) {
    return storage_save_state_file(data_dir, LANTERN_STORAGE_STATE_FILE, state);
}

/**
 * Load a persisted state from `data_dir/state.ssz`.
 *
 * On success, the contents of `state` are replaced.
 *
 * @param data_dir Base directory path.
 * @param state Output state (replaced on success).
 * @return 0 on success.
 * @return 1 if the state file is missing or empty.
 * @return -1 on invalid parameters or decode/validation errors.
 */
int lantern_storage_load_state(const char *data_dir, LanternState *state) {
    return storage_load_state_file(data_dir, LANTERN_STORAGE_STATE_FILE, state);
}

static bool block_root_alias_matches_expected(
    const LanternSignedBlock *block,
    const LanternRoot *expected_root) {
    if (!block || !expected_root) {
        return false;
    }

    /*
     * Fork-choice bootstrap can persist the materialized synthetic anchor
     * block under the hinted checkpoint root when no source block bytes are
     * available. That root can differ from the block's computed hash_tree_root
     * because the header's historical body_root is not reconstructible from the
     * empty synthetic body.
     *
     * The persisted alias is only expected for the anchor-shaped block we
     * synthesize locally: no attestations and no block-level proof.
     */
    const LanternBlockBody *body = &block->block.body;
    if (body->attestations.length != 0 || block->proof.length != 0u) {
        return false;
    }
    if (body->attestations.data != NULL || block->proof.data != NULL) {
        return false;
    }

    return true;
}

static int storage_store_block_internal(
    const char *data_dir,
    const LanternSignedBlock *block,
    const LanternRoot *root_override) {
    if (!data_dir || !block) {
        return -1;
    }

    int rc = -1;
    char *block_path = NULL;
    uint8_t *buffer = NULL;

    LanternRoot root = {0};
    if (root_override) {
        root = *root_override;
    } else if (lantern_hash_tree_root_block(&block->block, &root) != SSZ_SUCCESS) {
        goto cleanup;
    }
    if (storage_root_file_path(
            data_dir,
            STORAGE_DIR_BLOCKS,
            &root,
            true,
            &block_path,
            NULL,
            0)
        != 0) {
        goto cleanup;
    }

    struct stat st;
    if (stat(block_path, &st) == 0) {
        rc = 0;
        goto cleanup;
    }

    size_t encoded_size = 0;
    if (lantern_ssz_encode_signed_block(block, NULL, 0, &encoded_size) != SSZ_SUCCESS
        || encoded_size == 0) {
        lantern_log_warn(
            "storage",
            &(const struct lantern_log_metadata){0},
            "store_block size estimate failed slot=%" PRIu64 " attestations=%zu proof_len=%zu",
            block->block.slot,
            block->block.body.attestations.length,
            block->proof.length);
        goto cleanup;
    }
    buffer = malloc(encoded_size);
    if (!buffer) {
        goto cleanup;
    }
    size_t written_size = 0;
    const ssz_error_t encode_rc = lantern_ssz_encode_signed_block(block, buffer, encoded_size, &written_size);
    if (encode_rc != 0
        || written_size == 0
        || written_size > encoded_size) {
        lantern_log_warn(
            "storage",
            &(const struct lantern_log_metadata){0},
            "store_block encode failed slot=%" PRIu64 " rc=%d estimated=%zu written=%zu",
            block->block.slot,
            encode_rc,
            encoded_size,
            written_size);
        goto cleanup;
    }

    rc = write_atomic_file(block_path, buffer, written_size);

cleanup:
    free(buffer);
    free_path(block_path);
    return rc;
}

/**
 * Store a signed block under `data_dir/blocks/<root>.ssz`.
 *
 * The operation is idempotent: if the block already exists on disk, this
 * function returns success without modifying it.
 *
 * @param data_dir Base directory path.
 * @param block Block to persist.
 * @return 0 on success.
 * @return -1 on invalid parameters, encoding failure, or filesystem errors.
 */
int lantern_storage_store_block(const char *data_dir, const LanternSignedBlock *block) {
    return storage_store_block_internal(data_dir, block, NULL);
}

int lantern_storage_store_block_for_root(
    const char *data_dir,
    const LanternRoot *root,
    const LanternSignedBlock *block) {
    if (!root) {
        return -1;
    }
    return storage_store_block_internal(data_dir, block, root);
}

/**
 * Persist `state` under `data_dir/states` using the given `root` as filename.
 *
 * @param data_dir Base directory path.
 * @param root Root used to build the on-disk filename.
 * @param state State to persist.
 * @return 0 on success.
 * @return -1 on invalid parameters, encoding failure, or filesystem errors.
 */
int lantern_storage_store_state_for_root(
    const char *data_dir,
    const LanternRoot *root,
    const LanternState *state) {
    if (!data_dir || !root || !state || state->config.num_validators == 0) {
        return -1;
    }

    char *state_path = NULL;
    int rc = storage_root_file_path(
        data_dir,
        STORAGE_DIR_STATES,
        root,
        true,
        &state_path,
        NULL,
        0);
    if (rc == 0) {
        rc = storage_write_state_path(state_path, state);
    }
    free_path(state_path);
    return rc;
}

/**
 * Load the raw persisted SSZ bytes for a state stored under `data_dir/states`.
 *
 * @param data_dir Base directory path.
 * @param root Root used to build the on-disk filename.
 * @param out_data Output buffer (caller must free) on success.
 * @param out_len Output length on success.
 * @return 0 on success.
 * @return 1 if the state file is missing or empty.
 * @return -1 on invalid parameters or filesystem errors.
 */
int lantern_storage_load_state_bytes_for_root(
    const char *data_dir,
    const LanternRoot *root,
    uint8_t **out_data,
    size_t *out_len) {
    return storage_load_root_bytes(data_dir, STORAGE_DIR_STATES, root, out_data, out_len);
}

/**
 * Load the raw persisted SSZ bytes for a block stored under `data_dir/blocks`.
 *
 * @param data_dir Base directory path.
 * @param root Root used to build the on-disk filename.
 * @param out_data Output buffer (caller must free) on success.
 * @param out_len Output length on success.
 * @return 0 on success.
 * @return 1 if the block file is missing or empty.
 * @return -1 on invalid parameters or filesystem errors.
 */
int lantern_storage_load_block_bytes_for_root(
    const char *data_dir,
    const LanternRoot *root,
    uint8_t **out_data,
    size_t *out_len) {
    return storage_load_root_bytes(data_dir, STORAGE_DIR_BLOCKS, root, out_data, out_len);
}

struct prune_context {
    const char *data_dir;
    uint64_t slot;
    const LanternRoot *keep_roots;
    size_t keep_root_count;
    int pruned;
};

static int prune_block_state_pair(
    const LanternSignedBlock *block,
    const LanternRoot *root,
    void *context) {
    struct prune_context *prune = context;
    if (!block || !root || !prune) {
        return -1;
    }
    if (block->block.slot >= prune->slot
        || storage_root_is_kept(root, prune->keep_roots, prune->keep_root_count)) {
        return 0;
    }

    const enum storage_dir_kind dirs[] = {STORAGE_DIR_STATES, STORAGE_DIR_BLOCKS};
    for (size_t i = 0; i < sizeof(dirs) / sizeof(dirs[0]); ++i) {
        char *path = NULL;
        if (storage_root_file_path(
                prune->data_dir,
                dirs[i],
                root,
                false,
                &path,
                NULL,
                0)
                != 0
            || remove_storage_path(path, &prune->pruned) != 0) {
            free_path(path);
            return -1;
        }
        free_path(path);
    }
    return 0;
}

/**
 * Remove persisted blocks/states strictly before `slot`, preserving keep_roots.
 *
 * Mirrors leanSpec's Database.prune_before_slot(): finalized advancement makes
 * earlier block/state entries unnecessary, except for roots the caller names
 * explicitly, such as the finalized block root itself.
 *
 * @param data_dir Base storage directory.
 * @param slot Prune entries with slot < this value.
 * @param keep_roots Roots to preserve regardless of slot.
 * @param keep_root_count Number of entries in keep_roots.
 * @return Non-negative count of removed files on success, -1 on error.
 */
int lantern_storage_prune_before_slot(
    const char *data_dir,
    uint64_t slot,
    const LanternRoot *keep_roots,
    size_t keep_root_count) {
    if (!data_dir || (!keep_roots && keep_root_count > 0)) {
        return -1;
    }

    struct prune_context context = {
        .data_dir = data_dir,
        .slot = slot,
        .keep_roots = keep_roots,
        .keep_root_count = keep_root_count,
    };
    int rc = lantern_storage_iterate_blocks(data_dir, prune_block_state_pair, &context);
    if (rc < 0) {
        return -1;
    }
    return context.pruned;
}

/**
 * Collect signed blocks from disk that match the given set of roots.
 *
 * For each root in `roots`, looks up `data_dir/blocks/<hex>.ssz`, decodes
 * the block, and appends it to `out_blocks`.  Missing blocks are silently
 * skipped.
 *
 * @param data_dir   Base storage directory.
 * @param roots      Array of block roots to look up.
 * @param root_count Number of entries in `roots`.
 * @param out_blocks Output collection (resized to 0 on entry, filled on success).
 * @return 0 on success, -1 on error.
 */
int lantern_storage_collect_blocks(
    const char *data_dir,
    const LanternRoot *roots,
    size_t root_count,
    LanternSignedBlockList *out_blocks) {
    if (!data_dir || (!roots && root_count > 0) || !out_blocks) {
        return -1;
    }
    if (lantern_signed_block_list_resize(out_blocks, 0) != 0) {
        return -1;
    }

    int rc = -1;
    const struct lantern_log_metadata meta = {0};
    for (size_t i = 0; i < root_count; ++i) {
        char root_hex[2u * LANTERN_ROOT_SIZE + 1u];
        char *block_path = NULL;
        if (storage_root_file_path(
                data_dir,
                STORAGE_DIR_BLOCKS,
                &roots[i],
                false,
                &block_path,
                root_hex,
                sizeof(root_hex))
            != 0) {
            goto cleanup;
        }
        lantern_log_trace(
            "storage",
            &meta,
            "collect_blocks search root=%s path=%s",
            root_hex,
            block_path ? block_path : "null");

        uint8_t *data = NULL;
        size_t data_len = 0;
        const int read_rc = read_file_buffer(block_path, &data, &data_len);
        free_path(block_path);
        if (read_rc != 0) {
            lantern_log_debug(
                "storage",
                &meta,
                "collect_blocks miss root=%s rc=%d",
                root_hex,
                read_rc);
            continue;
        }

        const size_t current = out_blocks->length;
        if (lantern_signed_block_list_resize(out_blocks, current + 1) != 0) {
            free(data);
            goto cleanup;
        }
        LanternSignedBlock *dest = &out_blocks->blocks[current];
        if (lantern_ssz_decode_signed_block(dest, data, data_len) != SSZ_SUCCESS) {
            free(data);
            goto cleanup;
        }
        LanternRoot computed;
        if (lantern_hash_tree_root_block(&dest->block, &computed) != SSZ_SUCCESS) {
            free(data);
            goto cleanup;
        }
        if (memcmp(computed.bytes, roots[i].bytes, LANTERN_ROOT_SIZE) != 0) {
            if (!block_root_alias_matches_expected(dest, &roots[i])) {
                free(data);
                goto cleanup;
            }
            char computed_hex[2u * LANTERN_ROOT_SIZE + 1u];
            if (lantern_bytes_to_hex(computed.bytes, LANTERN_ROOT_SIZE, computed_hex, sizeof(computed_hex), 0) != 0) {
                computed_hex[0] = '\0';
            }
            lantern_log_warn(
                "storage",
                &meta,
                "collect_blocks accepted synthetic anchor alias requested=%s computed=%s",
                root_hex,
                computed_hex[0] ? computed_hex : "unknown");
        }
        lantern_log_trace(
            "storage",
            &meta,
            "collect_blocks loaded root=%s slot=%" PRIu64 " attestations=%zu",
            root_hex,
            dest->block.slot,
            dest->block.body.attestations.length);
        free(data);
    }
    rc = 0;

cleanup:
    return rc;
}

/**
 * Iterate over every persisted block in the blocks directory.
 *
 * Opens `data_dir/blocks/`, reads each `.ssz` file, decodes the signed
 * block, derives its canonical root key from filename, and calls `visitor` with the block,
 * root, and caller-supplied `context`.  Iteration stops early if the
 * visitor returns non-zero (its return value is propagated).
 *
 * @param data_dir Base storage directory.
 * @param visitor  Callback invoked for each block.
 * @param context  Opaque pointer forwarded to the visitor.
 * @return 0 on success (all blocks visited).
 * @return 1 if the blocks directory does not exist.
 * @return -1 on I/O or decoding errors; positive visitor return values
 *         are forwarded as-is.
 */
int lantern_storage_iterate_blocks(
    const char *data_dir,
    lantern_storage_block_visitor_fn visitor,
    void *context) {
    if (!data_dir || !visitor) {
        return -1;
    }

    int rc = -1;
    char *blocks_dir = NULL;
    DIR *dir = NULL;

    if (storage_dir_path(data_dir, STORAGE_DIR_BLOCKS, &blocks_dir) != 0) {
        goto cleanup;
    }
    dir = opendir(blocks_dir);
    if (!dir) {
        rc = (errno == ENOENT) ? 1 : -1;
        goto cleanup;
    }

    rc = 0;
    const struct lantern_log_metadata meta = {0};
    struct dirent *entry = NULL;
    while ((entry = readdir(dir)) != NULL) {
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) {
            continue;
        }
        const size_t len = strlen(entry->d_name);
        if (len < 5 || strcmp(entry->d_name + len - 4, ".ssz") != 0) {
            continue;
        }
        char *block_path = NULL;
        if (join_path(blocks_dir, entry->d_name, &block_path) != 0) {
            rc = -1;
            break;
        }
        uint8_t *data = NULL;
        size_t data_len = 0;
        const int read_rc = read_file_buffer(block_path, &data, &data_len);
        free_path(block_path);
        if (read_rc != 0) {
            if (read_rc == 1) {
                continue;
            }
            rc = -1;
            break;
        }
        LanternSignedBlock block;
        lantern_signed_block_with_attestation_init(&block);
        if (lantern_ssz_decode_signed_block(&block, data, data_len) != SSZ_SUCCESS) {
            lantern_signed_block_with_attestation_reset(&block);
            free(data);
            rc = -1;
            break;
        }
        LanternRoot computed_root;
        if (lantern_hash_tree_root_block(&block.block, &computed_root) != SSZ_SUCCESS) {
            lantern_signed_block_with_attestation_reset(&block);
            free(data);
            rc = -1;
            break;
        }
        LanternRoot root_from_filename = {0};
        bool have_root_from_filename = false;
        if (len == ((2u * LANTERN_ROOT_SIZE) + 4u)) {
            char filename_hex[(2u * LANTERN_ROOT_SIZE) + 1u];
            memcpy(filename_hex, entry->d_name, 2u * LANTERN_ROOT_SIZE);
            filename_hex[2u * LANTERN_ROOT_SIZE] = '\0';
            have_root_from_filename =
                lantern_hex_decode(filename_hex, root_from_filename.bytes, LANTERN_ROOT_SIZE)
                == 0;
        }
        const LanternRoot *root_for_visitor = &computed_root;
        if (have_root_from_filename) {
            root_for_visitor = &root_from_filename;
            if (memcmp(computed_root.bytes, root_from_filename.bytes, LANTERN_ROOT_SIZE) != 0) {
                if (!block_root_alias_matches_expected(&block, &root_from_filename)) {
                    lantern_signed_block_with_attestation_reset(&block);
                    free(data);
                    rc = -1;
                    break;
                }
                char computed_hex[2u * LANTERN_ROOT_SIZE + 1u];
                char filename_hex[2u * LANTERN_ROOT_SIZE + 1u];
                if (lantern_bytes_to_hex(
                        computed_root.bytes,
                        LANTERN_ROOT_SIZE,
                        computed_hex,
                        sizeof(computed_hex),
                        0)
                    != 0) {
                    computed_hex[0] = '\0';
                }
                if (lantern_bytes_to_hex(
                        root_from_filename.bytes,
                        LANTERN_ROOT_SIZE,
                        filename_hex,
                        sizeof(filename_hex),
                        0)
                    != 0) {
                    filename_hex[0] = '\0';
                }
                lantern_log_warn(
                    "storage",
                    &meta,
                    "iterate_blocks accepted synthetic anchor alias filename_root=%s computed=%s",
                    filename_hex[0] ? filename_hex : "unknown",
                    computed_hex[0] ? computed_hex : "unknown");
            }
        }
        const int visit_rc = visitor(&block, root_for_visitor, context);
        lantern_signed_block_with_attestation_reset(&block);
        free(data);
        if (visit_rc != 0) {
            rc = visit_rc;
            break;
        }
    }

cleanup:
    if (dir) {
        closedir(dir);
    }
    free_path(blocks_dir);
    return rc;
}
