/**
 * @file genesis.c
 * @brief Public API for loading genesis artifacts.
 *
 * Implements lifecycle helpers for `struct lantern_genesis_artifacts` and the
 * top-level `lantern_genesis_load()` entry point.
 *
 * @spec Lantern devnet genesis artifact files (lean quickstart).
 */

#include "lantern/genesis/genesis.h"

#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "genesis_internal.h"
#include "lantern/support/log.h"

/**
 * Initialize a genesis artifacts container.
 *
 * @spec Lantern genesis artifact loader.
 *
 * @param artifacts Artifacts container to initialize (caller-owned).
 *
 * @note Thread safety: Caller must ensure exclusive access to `artifacts`.
 */
void lantern_genesis_artifacts_init(struct lantern_genesis_artifacts *artifacts)
{
    if (!artifacts)
    {
        return;
    }

    memset(artifacts, 0, sizeof(*artifacts));
    lantern_enr_record_list_init(&artifacts->enrs);
}


/**
 * Reset a genesis artifacts container and free any owned memory.
 *
 * @spec Lantern genesis artifact loader.
 *
 * @param artifacts Artifacts container to reset. Safe to call with NULL.
 *
 * @note Thread safety: Caller must ensure exclusive access to `artifacts`.
 */
void lantern_genesis_artifacts_reset(struct lantern_genesis_artifacts *artifacts)
{
    if (!artifacts)
    {
        return;
    }

    lantern_enr_record_list_reset(&artifacts->enrs);
    genesis_free_validator_registry(&artifacts->validator_registry);
    genesis_free_validator_config(&artifacts->validator_config);

    free(artifacts->state_bytes);
    artifacts->state_bytes = NULL;
    artifacts->state_size = 0;

    free(artifacts->chain_config.validator_pubkeys);
    memset(&artifacts->chain_config, 0, sizeof(artifacts->chain_config));
}


/**
 * @brief Loads chain configuration and genesis validator pubkeys.
 *
 * Populates `config` by parsing the chain configuration file. On success, any
 * genesis pubkeys returned via `config->validator_pubkeys` are owned by `config`
 * and must be freed by the caller (typically via `lantern_genesis_artifacts_reset()`).
 *
 * @param config      Chain config to populate.
 * @param config_path Path to the chain config file.
 *
 * @return LANTERN_GENESIS_OK on success
 * @return LANTERN_GENESIS_ERR_INVALID_PARAM on NULL inputs
 * @return LANTERN_GENESIS_ERR_IO on file I/O failures
 * @return LANTERN_GENESIS_ERR_OUT_OF_MEMORY on allocation failure
 * @return LANTERN_GENESIS_ERR_INVALID_DATA on parse/validation failures
 *
 * @note Thread safety: Caller must ensure exclusive access to `config`.
 */
static int load_chain_config_and_pubkeys(
    struct lantern_chain_config *config,
    const char *config_path)
{
    if (!config || !config_path)
    {
        return LANTERN_GENESIS_ERR_INVALID_PARAM;
    }

    int result = genesis_parse_chain_config(config_path, config);
    if (result != LANTERN_GENESIS_OK)
    {
        lantern_log_error("genesis", NULL, "failed to parse chain config at %s", config_path);
        return result;
    }

    uint8_t *pubkeys = NULL;
    size_t pubkey_count = 0;
    result = genesis_parse_genesis_validator_pubkeys(config_path, &pubkeys, &pubkey_count);
    if (result != LANTERN_GENESIS_OK)
    {
        lantern_log_error("genesis", NULL, "failed to parse genesis pubkeys at %s", config_path);
        return result;
    }

    if (pubkeys && pubkey_count > 0)
    {
        config->validator_pubkeys = pubkeys;
        config->validator_pubkeys_count = pubkey_count;
        if (config->validator_count == 0)
        {
            config->validator_count = pubkey_count;
        }

        lantern_log_info(
            "genesis",
            NULL,
            "loaded %zu genesis pubkeys from %s",
            pubkey_count,
            config_path);
    }
    else
    {
        free(pubkeys);
        lantern_log_warn("genesis", NULL, "no genesis pubkeys found in %s", config_path);
    }

    if (config->validator_count == 0)
    {
        lantern_log_error("genesis", NULL, "validator count missing or zero in %s", config_path);
        return LANTERN_GENESIS_ERR_INVALID_DATA;
    }

    return LANTERN_GENESIS_OK;
}


/**
 * Load genesis artifacts from disk.
 *
 * Populates `artifacts` by parsing the provided YAML/SSZ files. On success, the
 * caller owns the returned buffers via `artifacts` and must call
 * `lantern_genesis_artifacts_reset()` to free them.
 *
 * @spec Lantern genesis artifact loader.
 *
 * @param artifacts Output artifacts container (must be initialized).
 * @param paths     Paths to genesis artifact files.
 *
 * @return LANTERN_GENESIS_OK on success
 * @return LANTERN_GENESIS_ERR_INVALID_PARAM on NULL inputs or missing required paths
 * @return LANTERN_GENESIS_ERR_IO on file I/O failures
 * @return LANTERN_GENESIS_ERR_OUT_OF_MEMORY on allocation failure
 * @return LANTERN_GENESIS_ERR_INVALID_DATA on parse/validation failures
 *
 * @note Thread safety: Caller must ensure exclusive access to `artifacts`.
 */
int lantern_genesis_load(
    struct lantern_genesis_artifacts *artifacts,
    const struct lantern_genesis_paths *paths)
{
    if (!artifacts || !paths)
    {
        return LANTERN_GENESIS_ERR_INVALID_PARAM;
    }

    if (!paths->config_path
        || !paths->validator_registry_path
        || !paths->nodes_path
        || !paths->validator_config_path)
    {
        lantern_log_error("genesis", NULL, "missing required genesis path");
        return LANTERN_GENESIS_ERR_INVALID_PARAM;
    }

    lantern_genesis_artifacts_reset(artifacts);

    int result = load_chain_config_and_pubkeys(&artifacts->chain_config, paths->config_path);
    if (result != LANTERN_GENESIS_OK)
    {
        goto error;
    }

    result = genesis_parse_validator_registry(
        paths->validator_registry_path,
        &artifacts->validator_registry);
    if (result != LANTERN_GENESIS_OK)
    {
        lantern_log_error(
            "genesis",
            NULL,
            "failed to parse validator registry at %s",
            paths->validator_registry_path);
        goto error;
    }

    genesis_merge_chain_pubkeys_into_registry(
        &artifacts->chain_config,
        &artifacts->validator_registry);

    result = genesis_parse_nodes_file(paths->nodes_path, &artifacts->enrs);
    if (result != LANTERN_GENESIS_OK)
    {
        lantern_log_error("genesis", NULL, "failed to parse nodes at %s", paths->nodes_path);
        goto error;
    }

    result = genesis_parse_validator_config(
        paths->validator_config_path,
        &artifacts->validator_config);
    if (result != LANTERN_GENESIS_OK)
    {
        lantern_log_error(
            "genesis",
            NULL,
            "failed to parse validator-config at %s",
            paths->validator_config_path);
        goto error;
    }

    if (paths->state_path && paths->state_path[0] != '\0')
    {
        result = genesis_read_state_blob(
            paths->state_path,
            &artifacts->state_bytes,
            &artifacts->state_size);
        if (result != LANTERN_GENESIS_OK)
        {
            lantern_log_error(
                "genesis",
                NULL,
                "failed to read genesis state at %s",
                paths->state_path);
            goto error;
        }
    }

    return LANTERN_GENESIS_OK;

error:
    lantern_genesis_artifacts_reset(artifacts);
    return result;
}
