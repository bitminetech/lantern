#ifndef LANTERN_STORAGE_STORAGE_H
#define LANTERN_STORAGE_STORAGE_H

#include <stddef.h>
#include <stdint.h>

#include "lantern/consensus/containers.h"
#include "lantern/consensus/state.h"
#include "lantern/networking/messages.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef int (*lantern_storage_block_visitor_fn)(
    const LanternSignedBlock *block,
    const LanternRoot *root,
    void *context);

struct lantern_storage {
    void *backend;
};

int lantern_storage_open(struct lantern_storage *storage, const char *data_dir);
void lantern_storage_close(struct lantern_storage *storage);
int lantern_storage_save_state(const struct lantern_storage *storage, const LanternState *state);
int lantern_storage_load_state(const struct lantern_storage *storage, LanternState *state);
int lantern_storage_store_block(const struct lantern_storage *storage, const LanternSignedBlock *block);
int lantern_storage_store_block_for_root(
    const struct lantern_storage *storage,
    const LanternRoot *root,
    const LanternSignedBlock *block);
int lantern_storage_store_state_for_root(
    const struct lantern_storage *storage,
    const LanternRoot *root,
    const LanternState *state);
int lantern_storage_load_state_bytes_for_root(
    const struct lantern_storage *storage,
    const LanternRoot *root,
    uint8_t **out_data,
    size_t *out_len);
int lantern_storage_load_block_bytes_for_root(
    const struct lantern_storage *storage,
    const LanternRoot *root,
    uint8_t **out_data,
    size_t *out_len);
int lantern_storage_prune_before_slot(
    const struct lantern_storage *storage,
    uint64_t slot,
    const LanternRoot *keep_roots,
    size_t keep_root_count);
int lantern_storage_collect_blocks(
    const struct lantern_storage *storage,
    const LanternRoot *roots,
    size_t root_count,
    LanternSignedBlockList *out_blocks);
int lantern_storage_iterate_blocks(
    const struct lantern_storage *storage,
    lantern_storage_block_visitor_fn visitor,
    void *context);

#ifdef __cplusplus
}
#endif

#endif /* LANTERN_STORAGE_STORAGE_H */
