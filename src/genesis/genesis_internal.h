/**
 * @file genesis_internal.h
 * @brief Internal helpers for parsing and managing genesis artifacts.
 *
 * This header is NOT part of the public API and is only intended for use by
 * source files within `src/genesis/`.
 */

#ifndef LANTERN_GENESIS_INTERNAL_H
#define LANTERN_GENESIS_INTERNAL_H

#include <stddef.h>
#include <stdint.h>

#include "lantern/genesis/genesis.h"

/**
 * Genesis module-specific error codes.
 */
enum
{
    LANTERN_GENESIS_OK = 0,
    LANTERN_GENESIS_ERR_INVALID_PARAM = -1,
    LANTERN_GENESIS_ERR_IO = -2,
    LANTERN_GENESIS_ERR_OUT_OF_MEMORY = -3,
    LANTERN_GENESIS_ERR_OVERFLOW = -4,
    LANTERN_GENESIS_ERR_PARSE = -5,
    LANTERN_GENESIS_ERR_INVALID_DATA = -6,
};

void genesis_free_validator_registry(struct lantern_validator_registry *registry);
void genesis_free_validator_config(struct lantern_validator_config *config);

int genesis_parse_chain_config(const char *path, struct lantern_chain_config *config);
int genesis_parse_genesis_validator_pubkeys(
    const char *path,
    uint8_t **out_pubkeys,
    size_t *out_count);
int genesis_parse_validator_registry(const char *path, struct lantern_validator_registry *registry);
int genesis_parse_validator_config(const char *path, struct lantern_validator_config *config);
int genesis_parse_nodes_file(const char *path, struct lantern_enr_record_list *list);
int genesis_read_state_blob(const char *path, uint8_t **bytes, size_t *size);

void genesis_merge_chain_pubkeys_into_registry(
    const struct lantern_chain_config *config,
    struct lantern_validator_registry *registry);

#endif /* LANTERN_GENESIS_INTERNAL_H */
