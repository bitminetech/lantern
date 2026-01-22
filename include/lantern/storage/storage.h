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

int lantern_storage_prepare(const char *data_dir);
int lantern_storage_save_state(const char *data_dir, const LanternState *state);
int lantern_storage_load_state(const char *data_dir, LanternState *state);
int lantern_storage_save_votes(const char *data_dir, const LanternState *state);
int lantern_storage_load_votes(const char *data_dir, LanternState *state);
int lantern_storage_store_block(const char *data_dir, const LanternSignedBlock *block);
int lantern_storage_store_state_for_root(
    const char *data_dir,
    const LanternRoot *root,
    const LanternState *state);
int lantern_storage_load_state_bytes_for_root(
    const char *data_dir,
    const LanternRoot *root,
    uint8_t **out_data,
    size_t *out_len);
int lantern_storage_store_slot_root(
    const char *data_dir,
    uint64_t slot,
    const LanternRoot *root);
int lantern_storage_store_head_root(
    const char *data_dir,
    uint64_t slot,
    const LanternRoot *root);
int lantern_storage_store_checkpoints(
    const char *data_dir,
    const LanternCheckpoint *justified,
    const LanternCheckpoint *finalized);
int lantern_storage_collect_blocks(
    const char *data_dir,
    const LanternRoot *roots,
    size_t root_count,
    LanternBlocksByRootResponse *out_blocks);
int lantern_storage_iterate_blocks(
    const char *data_dir,
    lantern_storage_block_visitor_fn visitor,
    void *context);

#ifdef __cplusplus
}
#endif

#endif /* LANTERN_STORAGE_STORAGE_H */
