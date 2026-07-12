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

#include <inttypes.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>

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

    *artifacts = (struct lantern_genesis_artifacts){0};
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
    genesis_free_validator_config(&artifacts->validator_config);

    free(artifacts->chain_config.validator_attestation_pubkeys);
    free(artifacts->chain_config.validator_proposal_pubkeys);
    *artifacts = (struct lantern_genesis_artifacts){0};
}


/**
 * @brief Loads chain configuration and genesis validator pubkeys.
 *
 * Populates `config` by parsing the chain configuration file. On success, any
 * genesis pubkeys returned via `config->validator_attestation_pubkeys` and
 * `config->validator_proposal_pubkeys` are owned by `config` and must be freed
 * by the caller (typically via `lantern_genesis_artifacts_reset()`).
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

    uint8_t *attestation_pubkeys = NULL;
    uint8_t *proposal_pubkeys = NULL;
    size_t pubkey_count = 0;
    result = genesis_parse_genesis_validator_pubkeys(
        config_path,
        &attestation_pubkeys,
        &proposal_pubkeys,
        &pubkey_count);
    if (result != LANTERN_GENESIS_OK)
    {
        lantern_log_error("genesis", NULL, "failed to parse genesis pubkeys at %s", config_path);
        return result;
    }

    if (!attestation_pubkeys || !proposal_pubkeys || pubkey_count == 0)
    {
        free(attestation_pubkeys);
        free(proposal_pubkeys);
        lantern_log_error("genesis", NULL, "genesis pubkeys missing from %s", config_path);
        return LANTERN_GENESIS_ERR_INVALID_DATA;
    }

    if (config->validator_count == 0)
    {
        config->validator_count = pubkey_count;
    }
    else if (config->validator_count != pubkey_count)
    {
        free(attestation_pubkeys);
        free(proposal_pubkeys);
        lantern_log_error(
            "genesis",
            NULL,
            "validator count mismatch in %s config=%" PRIu64 " entries=%zu",
            config_path,
            config->validator_count,
            pubkey_count);
        return LANTERN_GENESIS_ERR_INVALID_DATA;
    }

    config->validator_attestation_pubkeys = attestation_pubkeys;
    config->validator_proposal_pubkeys = proposal_pubkeys;
    lantern_log_info(
        "genesis",
        NULL,
        "loaded %zu genesis pubkeys from %s",
        pubkey_count,
        config_path);

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

    return LANTERN_GENESIS_OK;

error:
    lantern_genesis_artifacts_reset(artifacts);
    return result;
}
