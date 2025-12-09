#include "lantern/core/client.h"
#include "client_internal.h"

#include "lantern/consensus/hash.h"
#include "lantern/consensus/containers.h"
#include "lantern/consensus/duties.h"
#include "lantern/consensus/runtime.h"
#include "lantern/consensus/state.h"
#include "lantern/consensus/signature.h"
#include "lantern/consensus/ssz.h"
#include "lantern/consensus/fork_choice.h"
#include "lantern/crypto/hash_sig.h"
#include "lantern/storage/storage.h"
#include "lantern/http/server.h"
#include "lantern/support/strings.h"
#include "lantern/metrics/lean_metrics.h"
#include "lantern/support/log.h"
#include "lantern/support/time.h"
#include "lantern/support/secure_mem.h"
#include "lantern/networking/messages.h"
#include "lantern/networking/reqresp_service.h"
#include "lantern/encoding/snappy.h"
#include "libp2p/events.h"
#include "libp2p/errors.h"
#include "libp2p/protocol_dial.h"
#include "libp2p/stream.h"
#include "libp2p/host.h"
#include "protocol/identify/protocol_identify.h"
#include "protocol/gossipsub/gossipsub.h"
#include "protocol/ping/protocol_ping.h"
#include "peer_id/peer_id.h"
#include "multiformats/unsigned_varint/unsigned_varint.h"
#include "internal/yaml_parser.h"

#include <ctype.h>
#include <errno.h>
#include <inttypes.h>
#include <limits.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <stdarg.h>

#if defined(_WIN32)
#include <windows.h>
#else
#include <sys/time.h>
#endif

static int copy_genesis_paths(struct lantern_genesis_paths *paths,
                              const struct lantern_client_options *options);
static void reset_genesis_paths(struct lantern_genesis_paths *paths);
static int append_unique_bootnode(struct lantern_string_list *list,
                                  const char *value);
static int append_genesis_bootnodes(struct lantern_client *client);
static int compute_local_validator_assignment(struct lantern_client *client);
static int populate_local_validators(struct lantern_client *client);
static int init_consensus_runtime(struct lantern_client *client);


/**
 * @brief Initialize client options with default values.
 *
 * @note Thread safety: None required - operates on caller-provided struct.
 */
void lantern_client_options_init(struct lantern_client_options *options)
{
    if (!options)
    {
        return;
    }

    options->data_dir = LANTERN_DEFAULT_DATA_DIR;
    options->genesis_config_path = LANTERN_DEFAULT_GENESIS_CONFIG;
    options->validator_registry_path = LANTERN_DEFAULT_VALIDATOR_REGISTRY;
    options->nodes_path = LANTERN_DEFAULT_NODES_FILE;
    options->genesis_state_path = LANTERN_DEFAULT_GENESIS_STATE;
    options->validator_config_path = LANTERN_DEFAULT_VALIDATOR_CONFIG;
    options->node_id = LANTERN_DEFAULT_NODE_ID;
    options->node_key_hex = NULL;
    options->node_key_path = NULL;
    options->listen_address = LANTERN_DEFAULT_LISTEN_ADDR;
    options->http_port = LANTERN_DEFAULT_HTTP_PORT;
    options->metrics_port = LANTERN_DEFAULT_METRICS_PORT;
    options->devnet = LANTERN_DEFAULT_DEVNET;
    lantern_string_list_init(&options->bootnodes);
    options->hash_sig_key_dir = NULL;
    options->hash_sig_public_path = NULL;
    options->hash_sig_secret_path = NULL;
    options->hash_sig_public_template = NULL;
    options->hash_sig_secret_template = NULL;
}


/**
 * @brief Free resources allocated within client options.
 *
 * @note Thread safety: None required - operates on caller-provided struct.
 */
void lantern_client_options_free(struct lantern_client_options *options)
{
    if (!options)
    {
        return;
    }
    lantern_string_list_reset(&options->bootnodes);
}


/**
 * @brief Add a bootnode address to client options.
 *
 * @note Thread safety: None required - operates on caller-provided struct.
 */
int lantern_client_options_add_bootnode(struct lantern_client_options *options, const char *bootnode)
{
    if (!options || !bootnode)
    {
        return -1;
    }
    return lantern_string_list_append(&options->bootnodes, bootnode);
}


/**
 * @brief Initialize and start the Lantern client.
 *
 * Sets up all subsystems including networking, gossip, request/response,
 * validator services, and HTTP/metrics servers.
 *
 * @note Thread safety: Must be called from a single thread before any
 *       concurrent access to the client. Initializes all internal locks.
 */
int lantern_init(struct lantern_client *client, const struct lantern_client_options *options)
{
    if (!client || !options)
    {
        return -1;
    }

    memset(client, 0, sizeof(*client));
    lantern_string_list_init(&client->bootnodes);
    lantern_string_list_init(&client->dialer_peers);
    lantern_string_list_init(&client->connected_peer_ids);
    lantern_string_list_init(&client->status_failure_peer_ids);
    lantern_genesis_artifacts_init(&client->genesis);
    lantern_enr_record_init(&client->local_enr);
    lantern_libp2p_host_init(&client->network);
    client->ping_server = NULL;
    client->ping_running = false;
    lantern_gossipsub_service_init(&client->gossip);
    lantern_reqresp_service_init(&client->reqresp);
    client->reqresp_running = false;
    lantern_validator_assignment_reset(&client->validator_assignment);
    client->has_validator_assignment = false;
    lantern_consensus_runtime_reset(&client->runtime);
    client->has_runtime = false;
    lantern_metrics_server_init(&client->metrics_server);
    client->metrics_running = false;
    lantern_http_server_init(&client->http_server);
    client->http_running = false;
    lantern_state_init(&client->state);
    lean_metrics_reset();
    client->state_lock_initialized = false;
    lantern_fork_choice_init(&client->fork_choice);
    client->has_fork_choice = false;
    client->dialer_thread_started = false;
    client->dialer_stop_flag = 1;
    client->ping_thread_started = false;
    client->ping_stop_flag = 1;
    pending_block_list_init(&client->pending_blocks);
    client->pending_lock_initialized = false;
    if (pthread_mutex_init(&client->pending_lock, NULL) != 0)
    {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to initialize pending block lock");
        goto error;
    }
    client->pending_lock_initialized = true;

    if (set_owned_string(&client->data_dir, options->data_dir) != 0)
    {
        goto error;
    }
    if (set_owned_string(&client->node_id, options->node_id) != 0)
    {
        goto error;
    }
    lantern_log_set_node_id(client->node_id);
    if (set_owned_string(&client->listen_address, options->listen_address) != 0)
    {
        goto error;
    }
    if (set_owned_string(&client->devnet, options->devnet) != 0)
    {
        goto error;
    }
    const char *disable_guard_env = getenv("LANTERN_DEBUG_DISABLE_STATUS_GUARD");
    if (disable_guard_env && disable_guard_env[0] != '\0' && !(disable_guard_env[0] == '0' && disable_guard_env[1] == '\0'))
    {
        client->status_guard_disabled = true;
        lantern_log_warn(
            "reqresp",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "status guard disabled via LANTERN_DEBUG_DISABLE_STATUS_GUARD=\"%s\"",
            disable_guard_env);
    }
    if (!client->status_lock_initialized)
    {
        if (pthread_mutex_init(&client->status_lock, NULL) != 0)
        {
            lantern_log_error(
                "client",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "failed to initialize peer status lock");
            goto error;
        }
        client->status_lock_initialized = true;
    }
    if (!client->state_lock_initialized)
    {
        if (pthread_mutex_init(&client->state_lock, NULL) != 0)
        {
            lantern_log_error(
                "client",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "failed to initialize state lock");
            goto error;
        }
        client->state_lock_initialized = true;
    }
    if (!client->peer_vote_lock_initialized)
    {
        if (pthread_mutex_init(&client->peer_vote_lock, NULL) != 0)
        {
            lantern_log_error(
                "client",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "failed to initialize vote metrics lock");
            goto error;
        }
        client->peer_vote_lock_initialized = true;
    }
    client->http_port = options->http_port;
    client->metrics_port = options->metrics_port;
    if (lantern_storage_prepare(client->data_dir) != 0)
    {
        lantern_log_error(
            "storage",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to prepare data directory '%s'",
            client->data_dir);
        goto error;
    }

    if (lantern_string_list_copy(&client->bootnodes, &options->bootnodes) != 0)
    {
        goto error;
    }

    if (copy_genesis_paths(&client->genesis_paths, options) != 0)
    {
        goto error;
    }

    if (lantern_genesis_load(&client->genesis, &client->genesis_paths) != 0)
    {
        goto error;
    }
    if (lantern_validator_config_assign_ranges(
            &client->genesis.validator_config,
            client->genesis.chain_config.validator_count)
        != 0)
    {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "validator-config does not cover %" PRIu64 " validators",
            client->genesis.chain_config.validator_count);
        goto error;
    }
    if (lantern_validator_config_apply_assignments(
            &client->genesis.validator_config,
            client->genesis_paths.validator_registry_path,
            client->genesis.chain_config.validator_count)
        != 0)
    {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "validator assignment mapping invalid or incomplete");
        goto error;
    }

    bool loaded_from_storage = false;
    int storage_state_rc = lantern_storage_load_state(client->data_dir, &client->state);
    if (storage_state_rc == 0)
    {
        client->has_state = true;
        loaded_from_storage = true;
    }
    else if (storage_state_rc < 0)
    {
        lantern_log_error(
            "storage",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to load persisted state");
        goto error;
    }
    else
    {
        bool decoded_genesis = false;
        /* Prefer constructing genesis from config/validators like Zeam does. */
        if (client->genesis.chain_config.validator_pubkeys
            && client->genesis.chain_config.validator_pubkeys_count > 0)
        {
            size_t vcount = client->genesis.chain_config.validator_pubkeys_count;
            if (lantern_state_generate_genesis(
                    &client->state, client->genesis.chain_config.genesis_time, vcount)
                == 0
                && lantern_state_set_validator_pubkeys(
                       &client->state, client->genesis.chain_config.validator_pubkeys, vcount)
                       == 0)
            {
                decoded_genesis = true;
                client->genesis_fallback_used = false;
            }
        }
        else if (client->genesis.state_bytes && client->genesis.state_size > 0
                   && lantern_ssz_decode_state(&client->state, client->genesis.state_bytes, client->genesis.state_size) == 0)
        {
            decoded_genesis = true;
            client->genesis_fallback_used = false;
        }
        else
        {
            lantern_log_warn(
                "client",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "failed to decode genesis state; attempting to synthesize genesis from config");
            /* Fallback: synthesize a minimal genesis state using chain config + validator registry,
               mirroring Zeam's genesis handling. */
            size_t vcount = client->genesis.validator_registry.count;
            if (vcount != client->genesis.chain_config.validator_count || vcount == 0)
            {
                lantern_log_warn(
                    "client",
                    &(const struct lantern_log_metadata){.validator = client->node_id},
                    "validator registry count (%zu) does not match chain config (%" PRIu64 "), cannot build genesis",
                    vcount,
                    client->genesis.chain_config.validator_count);
            }
            else if (lantern_state_generate_genesis(
                           &client->state, client->genesis.chain_config.genesis_time, vcount)
                       == 0)
            {
                uint8_t *pubkeys = calloc(vcount, LANTERN_VALIDATOR_PUBKEY_SIZE);
                if (!pubkeys)
                {
                    lantern_log_error(
                        "client",
                        &(const struct lantern_log_metadata){.validator = client->node_id},
                        "failed to allocate validator pubkey buffer");
                }
                else
                {
                    bool pubkey_ok = true;
                    for (size_t i = 0; i < vcount; ++i)
                    {
                        const struct lantern_validator_record *rec = &client->genesis.validator_registry.records[i];
                        if (rec->has_pubkey_bytes)
                        {
                            memcpy(pubkeys + (i * LANTERN_VALIDATOR_PUBKEY_SIZE), rec->pubkey_bytes, LANTERN_VALIDATOR_PUBKEY_SIZE);
                        }
                        else if (rec->pubkey_hex
                                   && lantern_hex_decode(
                                          rec->pubkey_hex,
                                          pubkeys + (i * LANTERN_VALIDATOR_PUBKEY_SIZE),
                                          LANTERN_VALIDATOR_PUBKEY_SIZE)
                                          == 0)
                        {
                            /* decoded */
                        }
                        else
                        {
                            lantern_log_error(
                                "client",
                                &(const struct lantern_log_metadata){.validator = client->node_id},
                                "missing or invalid pubkey for validator index=%zu; aborting genesis build",
                                i);
                            pubkey_ok = false;
                            break;
                        }
                    }
                    if (pubkey_ok && lantern_state_set_validator_pubkeys(&client->state, pubkeys, vcount) == 0)
                    {
                        decoded_genesis = true;
                        client->genesis_fallback_used = true;
                    }
                    free(pubkeys);
                }
            }
        }
        if (decoded_genesis)
        {
            if (lantern_state_prepare_validator_votes(&client->state, client->state.config.num_validators) != 0)
            {
                lantern_log_error(
                    "client",
                    &(const struct lantern_log_metadata){.validator = client->node_id},
                    "failed to prepare validator vote records");
                goto error;
            }
            LanternRoot header_root;
            LanternRoot original_header_state_root = client->state.latest_block_header.state_root;
            LanternRoot state_root;
            LanternRoot genesis_block_root;
            LanternRoot genesis_signed_block_root;
            LanternRoot canonical_header_root;
            LanternRoot spec_header_root;
            char header_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
            char state_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
            char original_state_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
            char block_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
            char signed_block_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
            char parent_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
            char canonical_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
            char body_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
            char spec_header_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
            header_hex[0] = '\0';
            state_hex[0] = '\0';
            original_state_hex[0] = '\0';
            block_hex[0] = '\0';
            signed_block_hex[0] = '\0';
            parent_hex[0] = '\0';
            canonical_hex[0] = '\0';
            body_hex[0] = '\0';
            spec_header_hex[0] = '\0';
            if (lantern_hash_tree_root_block_header(&client->state.latest_block_header, &header_root) == 0)
            {
                format_root_hex(&header_root, header_hex, sizeof(header_hex));
            }
            if (lantern_hash_tree_root_state(&client->state, &state_root) == 0)
            {
                format_root_hex(&state_root, state_hex, sizeof(state_hex));
                /* NOTE: Do NOT update client->state.latest_block_header.state_root here!
                 * 
                 * According to leanSpec, the genesis block header MUST have state_root = ZERO.
                 * The genesis block root is computed from this header with state_root = ZERO.
                 * This is critical for interoperability with other leanSpec implementations.
                 * 
                 * The state's latest_block_header.state_root will be updated to the actual
                 * state root later during fork choice initialization, AFTER computing the
                 * genesis anchor root.
                 */
            }
            LanternBlock genesis_block;
            memset(&genesis_block, 0, sizeof(genesis_block));
            genesis_block.slot = client->state.latest_block_header.slot;
            genesis_block.proposer_index = client->state.latest_block_header.proposer_index;
            genesis_block.parent_root = client->state.latest_block_header.parent_root;
            genesis_block.state_root = state_root;
            lantern_block_body_init(&genesis_block.body);
            if (lantern_hash_tree_root_block(&genesis_block, &genesis_block_root) == 0)
            {
                format_root_hex(&genesis_block_root, block_hex, sizeof(block_hex));
            }
            lantern_block_body_reset(&genesis_block.body);
            format_root_hex(
                &client->state.latest_block_header.parent_root,
                parent_hex,
                sizeof(parent_hex));
            LanternBlockHeader canonical_header = client->state.latest_block_header;
            canonical_header.state_root = state_root;
            if (lantern_hash_tree_root_block_header(&canonical_header, &canonical_header_root) == 0)
            {
                format_root_hex(&canonical_header_root, canonical_hex, sizeof(canonical_hex));
            }
            LanternBlockBody empty_body_snapshot;
            lantern_block_body_init(&empty_body_snapshot);
            LanternRoot default_body_root;
            if (lantern_hash_tree_root_block_body(&empty_body_snapshot, &default_body_root) != 0)
            {
                memset(&default_body_root, 0, sizeof(default_body_root));
            }
            lantern_block_body_reset(&empty_body_snapshot);
            LanternBlockHeader spec_header = client->state.latest_block_header;
            spec_header.state_root = state_root;
            spec_header.body_root = default_body_root;
            if (lantern_hash_tree_root_block_header(&spec_header, &spec_header_root) == 0)
            {
                format_root_hex(&spec_header_root, spec_header_hex, sizeof(spec_header_hex));
            }
            format_root_hex(
                &client->state.latest_block_header.body_root,
                body_hex,
                sizeof(body_hex));
            LanternSignedBlock genesis_signed;
            lantern_signed_block_with_attestation_init(&genesis_signed);
            genesis_signed.message.block = genesis_block;
            (void)lantern_block_signatures_resize(&genesis_signed.signatures, 0);
            if (lantern_hash_tree_root_signed_block(&genesis_signed, &genesis_signed_block_root) == 0)
            {
                format_root_hex(&genesis_signed_block_root, signed_block_hex, sizeof(signed_block_hex));
            }
            LanternState generated_state;
            lantern_state_init(&generated_state);
            if (lantern_state_generate_genesis(
                    &generated_state,
                    client->state.config.genesis_time,
                    client->state.config.num_validators)
                == 0)
            {
                LanternRoot generated_state_root;
                if (lantern_hash_tree_root_state(&generated_state, &generated_state_root) == 0)
                {
                    LanternBlock generated_block;
                    memset(&generated_block, 0, sizeof(generated_block));
                    generated_block.slot = generated_state.slot;
                    generated_block.proposer_index = 0;
                    generated_block.parent_root = generated_state.latest_block_header.parent_root;
                    generated_block.state_root = generated_state_root;
                    lantern_block_body_init(&generated_block.body);
                    LanternRoot generated_block_root;
                    if (lantern_hash_tree_root_block(&generated_block, &generated_block_root) == 0)
                    {
                        char generated_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
                        format_root_hex(&generated_block_root, generated_hex, sizeof(generated_hex));
                        lantern_log_info(
                            "client",
                            &(const struct lantern_log_metadata){.validator = client->node_id},
                            "generated anchor block root=%s",
                            generated_hex[0] ? generated_hex : "0x0");
                    }
                    lantern_block_body_reset(&generated_block.body);
                }
            }
            lantern_log_info(
                "client",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "genesis anchors header_root=%s state_root=%s body_root=%s block_root=%s signed_block_root=%s canonical_header_root=%s spec_header_root=%s parent_root=%s",
                header_hex[0] ? header_hex : "0x0",
                state_hex[0] ? state_hex : "0x0",
                body_hex[0] ? body_hex : "0x0",
                block_hex[0] ? block_hex : "0x0",
                signed_block_hex[0] ? signed_block_hex : "0x0",
                canonical_hex[0] ? canonical_hex : "0x0",
                spec_header_hex[0] ? spec_header_hex : "0x0",
                parent_hex[0] ? parent_hex : "0x0");
            client->has_state = true;
        }
    }
    if (client->has_state)
    {
        int votes_rc = lantern_storage_load_votes(client->data_dir, &client->state);
        if (votes_rc < 0)
        {
            lantern_log_error(
                "storage",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "failed to load persisted votes");
            goto error;
        }
        if (initialize_fork_choice(client) != 0)
        {
            goto error;
        }
        if (restore_persisted_blocks(client) != 0)
        {
            goto error;
        }
    }
    if (client->has_state && !loaded_from_storage)
    {
        if (lantern_storage_save_state(client->data_dir, &client->state) != 0)
        {
            lantern_log_warn(
                "storage",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "failed to persist initial state snapshot");
        }
        if (lantern_storage_save_votes(client->data_dir, &client->state) != 0)
        {
            lantern_log_warn(
                "storage",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "failed to persist initial votes snapshot");
        }
    }

    client->assigned_validators = lantern_validator_config_find(
        &client->genesis.validator_config,
        client->node_id);

    if (!client->assigned_validators)
    {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "node-id '%s' not found in validator-config",
            client->node_id);
        goto error;
    }
    if (!client->assigned_validators->enr.ip || client->assigned_validators->enr.quic_port == 0)
    {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "validator '%s' missing ENR fields",
            client->node_id);
        goto error;
    }
    if (configure_hash_sig_sources(client, options) != 0)
    {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to configure hash-sig key sources");
        goto error;
    }
    adopt_validator_listen_address(client);
    if (compute_local_validator_assignment(client) != 0)
    {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to compute validator assignment for '%s'",
            client->node_id);
        goto error;
    }
    if (populate_local_validators(client) != 0)
    {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to enumerate local validators for '%s'",
            client->node_id);
        goto error;
    }
    if (client->local_validator_count == 0 || !client->has_state)
    {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "no local validators assigned for '%s'; check validator-config",
            client->node_id);
        goto error;
    }
    if (lantern_client_refresh_state_validators(client) != 0)
    {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to refresh validator pubkeys for '%s'",
            client->node_id);
        goto error;
    }
    if (load_hash_sig_keys(client) != 0)
    {
        goto error;
    }
    lantern_log_info(
        "client",
        &(const struct lantern_log_metadata){.validator = client->node_id},
        "validator slice start=%" PRIu64 " count=%" PRIu64,
        client->validator_assignment.start_index,
        client->validator_assignment.count);
    if (init_consensus_runtime(client) != 0)
    {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to initialize consensus runtime");
        goto error;
    }
    lantern_log_info(
        "client",
        &(const struct lantern_log_metadata){.validator = client->node_id},
        "consensus runtime ready genesis_time=%" PRIu64 " validators=%" PRIu64,
        client->genesis.chain_config.genesis_time,
        client->genesis.chain_config.validator_count);

    uint8_t node_key[32];
    if (load_node_key_bytes(options, node_key) != 0)
    {
        goto error;
    }
    memcpy(client->node_private_key, node_key, sizeof(node_key));
    client->has_node_private_key = true;

    struct lantern_libp2p_config net_cfg = {
        .listen_multiaddr = client->listen_address,
        .secp256k1_secret = node_key,
        .secret_len = sizeof(node_key),
        .allow_outbound_identify = 1,
    };
    if (lantern_libp2p_host_start(&client->network, &net_cfg) != 0)
    {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to initialize libp2p host");
        memset(node_key, 0, sizeof(node_key));
        goto error;
    }

    if (!client->connection_lock_initialized)
    {
        if (pthread_mutex_init(&client->connection_lock, NULL) != 0)
        {
            lantern_log_error(
                "network",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "failed to initialize connection lock");
            memset(node_key, 0, sizeof(node_key));
            goto error;
        }
        client->connection_lock_initialized = true;
    }
    connection_counter_reset(client);

    if (libp2p_event_subscribe(client->network.host, connection_events_cb, client, &client->connection_subscription) != 0)
    {
        lantern_log_error(
            "network",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to subscribe to libp2p connection events");
        memset(node_key, 0, sizeof(node_key));
        goto error;
    }

    {
        libp2p_protocol_server_t *ping_server = NULL;
        if (libp2p_ping_service_start(client->network.host, &ping_server) != 0)
        {
            lantern_log_error(
                "network",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "failed to start libp2p ping service");
            memset(node_key, 0, sizeof(node_key));
            goto error;
        }
        client->ping_server = ping_server;
        client->ping_running = true;
        lantern_log_info(
            "network",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "libp2p ping service started");
    }

    struct lantern_gossipsub_config gossip_cfg = {
        .host = client->network.host,
        .devnet = client->devnet,
    };
    lantern_gossipsub_service_set_block_handler(&client->gossip, gossip_block_handler, client);
    lantern_gossipsub_service_set_vote_handler(&client->gossip, gossip_vote_handler, client);
    if (lantern_gossipsub_service_start(&client->gossip, &gossip_cfg) != 0)
    {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to start gossipsub service");
        memset(node_key, 0, sizeof(node_key));
        goto error;
    }
    client->gossip_running = true;

    struct lantern_reqresp_service_callbacks req_callbacks;
    memset(&req_callbacks, 0, sizeof(req_callbacks));
    req_callbacks.context = client;
    req_callbacks.build_status = reqresp_build_status;
    req_callbacks.handle_status = reqresp_handle_status;
    req_callbacks.status_failure = reqresp_status_failure;
    req_callbacks.collect_blocks = reqresp_collect_blocks;

    struct lantern_reqresp_service_config req_config;
    memset(&req_config, 0, sizeof(req_config));
    req_config.host = client->network.host;
    req_config.callbacks = &req_callbacks;
    if (lantern_reqresp_service_start(&client->reqresp, &req_config) != 0)
    {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to start request/response service");
        memset(node_key, 0, sizeof(node_key));
        goto error;
    }
    client->reqresp_running = true;
    lantern_client_seed_reqresp_peer_modes(client);
    if (append_genesis_bootnodes(client) != 0)
    {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to append bootnodes from genesis");
        memset(node_key, 0, sizeof(node_key));
        goto error;
    }

    if (lantern_enr_record_build_v4(
            &client->local_enr,
            node_key,
            client->assigned_validators->enr.ip,
            client->assigned_validators->enr.quic_port,
            client->assigned_validators->enr.sequence)
        != 0)
    {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to build local ENR");
        memset(node_key, 0, sizeof(node_key));
        goto error;
    }
    lantern_log_info(
        "client",
        &(const struct lantern_log_metadata){.validator = client->node_id},
        "local ENR prepared sequence=%" PRIu64,
        client->assigned_validators->enr.sequence);
    memset(node_key, 0, sizeof(node_key));

    if (start_peer_dialer(client) != 0)
    {
        lantern_log_warn(
            "network",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to start peer dialer thread");
    }

    if (start_ping_service(client) != 0)
    {
        lantern_log_warn(
            "network",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to start ping service thread");
    }

    if (start_validator_service(client) != 0)
    {
        lantern_log_warn(
            "validator",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "validator duties inactive");
    }

    struct lantern_http_server_config http_config;
    memset(&http_config, 0, sizeof(http_config));
    http_config.port = client->http_port;
    http_config.callbacks.context = client;
    http_config.callbacks.snapshot_head = http_snapshot_head;
    http_config.callbacks.validator_count = http_validator_count_cb;
    http_config.callbacks.validator_info = http_validator_info_cb;
    http_config.callbacks.set_validator_status = http_set_validator_status_cb;
    if (lantern_http_server_start(&client->http_server, &http_config) != 0)
    {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to start HTTP server on port %" PRIu16,
            client->http_port);
        goto error;
    }
    client->http_running = true;

    struct lantern_metrics_callbacks metrics_callbacks;
    memset(&metrics_callbacks, 0, sizeof(metrics_callbacks));
    metrics_callbacks.context = client;
    metrics_callbacks.snapshot = metrics_snapshot_cb;
    if (client->metrics_port != 0)
    {
        if (lantern_metrics_server_start(&client->metrics_server, client->metrics_port, &metrics_callbacks) != 0)
        {
            lantern_log_error(
                "client",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "failed to start metrics server on port %" PRIu16,
                client->metrics_port);
            goto error;
        }
        client->metrics_running = true;
    }

    return 0;

error:
    lantern_shutdown(client);
    return -1;
}


/**
 * @brief Shutdown and clean up the Lantern client.
 *
 * Stops all services and releases all resources. After this call, the client
 * struct is zeroed and must be re-initialized before reuse.
 *
 * @note Thread safety: Must be called from a single thread after all other
 *       threads have stopped using the client. Destroys all internal locks.
 */
void lantern_shutdown(struct lantern_client *client)
{
    if (!client)
    {
        return;
    }

    stop_validator_service(client);
    stop_ping_service(client);
    stop_peer_dialer(client);
    free_hash_sig_pubkeys(client);
    free(client->hash_sig_key_dir);
    client->hash_sig_key_dir = NULL;
    free(client->hash_sig_public_template);
    client->hash_sig_public_template = NULL;
    free(client->hash_sig_secret_template);
    client->hash_sig_secret_template = NULL;
    free(client->hash_sig_public_path);
    client->hash_sig_public_path = NULL;
    free(client->hash_sig_secret_path);
    client->hash_sig_secret_path = NULL;

    lantern_metrics_server_stop(&client->metrics_server);
    lantern_metrics_server_init(&client->metrics_server);
    client->metrics_running = false;

    lantern_http_server_stop(&client->http_server);
    lantern_http_server_init(&client->http_server);
    client->http_running = false;

    if (client->network.host && client->connection_subscription)
    {
        libp2p_event_unsubscribe(client->network.host, client->connection_subscription);
    }
    client->connection_subscription = NULL;

    if (client->network.host && client->ping_running && client->ping_server)
    {
        if (libp2p_ping_service_stop(client->network.host, client->ping_server) != 0)
        {
            lantern_log_warn(
                "network",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "failed to stop libp2p ping service cleanly");
        }
        else
        {
            lantern_log_info(
                "network",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "shutdown: libp2p ping service stopped");
        }
    }
    client->ping_server = NULL;
    client->ping_running = false;

    if (client->connection_lock_initialized)
    {
        connection_counter_reset(client);
        pthread_mutex_destroy(&client->connection_lock);
        client->connection_lock_initialized = false;
    }
    else
    {
        client->connected_peers = 0;
    }
    lantern_string_list_reset(&client->connected_peer_ids);

    if (client->status_lock_initialized)
    {
        if (pthread_mutex_lock(&client->status_lock) == 0)
        {
            free(client->peer_status_entries);
            client->peer_status_entries = NULL;
            client->peer_status_count = 0;
            client->peer_status_capacity = 0;
            pthread_mutex_unlock(&client->status_lock);
        }
        else
        {
            free(client->peer_status_entries);
            client->peer_status_entries = NULL;
            client->peer_status_count = 0;
            client->peer_status_capacity = 0;
        }
        pthread_mutex_destroy(&client->status_lock);
        client->status_lock_initialized = false;
    }
    else
    {
        free(client->peer_status_entries);
        client->peer_status_entries = NULL;
        client->peer_status_count = 0;
        client->peer_status_capacity = 0;
    }

    if (client->peer_vote_lock_initialized)
    {
        if (pthread_mutex_lock(&client->peer_vote_lock) == 0)
        {
            free(client->peer_vote_stats);
            client->peer_vote_stats = NULL;
            client->peer_vote_stats_len = 0;
            client->peer_vote_stats_cap = 0;
            pthread_mutex_unlock(&client->peer_vote_lock);
        }
        else
        {
            free(client->peer_vote_stats);
            client->peer_vote_stats = NULL;
            client->peer_vote_stats_len = 0;
            client->peer_vote_stats_cap = 0;
        }
        pthread_mutex_destroy(&client->peer_vote_lock);
        client->peer_vote_lock_initialized = false;
    }
    else
    {
        free(client->peer_vote_stats);
        client->peer_vote_stats = NULL;
        client->peer_vote_stats_len = 0;
        client->peer_vote_stats_cap = 0;
    }

    if (client->validator_lock_initialized)
    {
        if (pthread_mutex_lock(&client->validator_lock) == 0)
        {
            free(client->validator_enabled);
            client->validator_enabled = NULL;
            pthread_mutex_unlock(&client->validator_lock);
        }
        else
        {
            free(client->validator_enabled);
            client->validator_enabled = NULL;
        }
        pthread_mutex_destroy(&client->validator_lock);
        client->validator_lock_initialized = false;
    }
    else
    {
        free(client->validator_enabled);
        client->validator_enabled = NULL;
    }

    if (client->pending_lock_initialized)
    {
        if (pthread_mutex_lock(&client->pending_lock) == 0)
        {
            pending_block_list_reset(&client->pending_blocks);
            pthread_mutex_unlock(&client->pending_lock);
        }
        else
        {
            pending_block_list_reset(&client->pending_blocks);
        }
        pthread_mutex_destroy(&client->pending_lock);
        client->pending_lock_initialized = false;
    }
    else
    {
        pending_block_list_reset(&client->pending_blocks);
    }
    lantern_string_list_reset(&client->dialer_peers);
    lantern_string_list_reset(&client->status_failure_peer_ids);
    lantern_string_list_reset(&client->bootnodes);
    free(client->data_dir);
    client->data_dir = NULL;
    free(client->node_id);
    client->node_id = NULL;
    free(client->listen_address);
    client->listen_address = NULL;
    free(client->devnet);
    client->devnet = NULL;

    reset_genesis_paths(&client->genesis_paths);
    lantern_genesis_artifacts_reset(&client->genesis);
    lantern_log_info(
        "client",
        &(const struct lantern_log_metadata){.validator = client->node_id},
        "shutdown: stopping request/response service");
    lantern_reqresp_service_reset(&client->reqresp);
    lantern_reqresp_service_init(&client->reqresp);
    client->reqresp_running = false;
    lantern_log_info(
        "client",
        &(const struct lantern_log_metadata){.validator = client->node_id},
        "shutdown: request/response service stopped");
    lantern_log_info(
        "client",
        &(const struct lantern_log_metadata){.validator = client->node_id},
        "shutdown: stopping gossipsub");
    lantern_gossipsub_service_reset(&client->gossip);
    client->gossip_running = false;
    lantern_log_info(
        "client",
        &(const struct lantern_log_metadata){.validator = client->node_id},
        "shutdown: gossipsub stopped");
    lantern_log_info(
        "client",
        &(const struct lantern_log_metadata){.validator = client->node_id},
        "shutdown: resetting libp2p host");
    lantern_libp2p_host_reset(&client->network);
    lantern_log_info(
        "client",
        &(const struct lantern_log_metadata){.validator = client->node_id},
        "shutdown: libp2p host reset");
    lantern_enr_record_reset(&client->local_enr);
    memset(client->node_private_key, 0, sizeof(client->node_private_key));
    client->has_node_private_key = false;
    if (client->has_state)
    {
        lantern_state_reset(&client->state);
        client->has_state = false;
    }
    else
    {
        lantern_state_reset(&client->state);
    }
    if (client->state_lock_initialized)
    {
        pthread_mutex_destroy(&client->state_lock);
        client->state_lock_initialized = false;
    }
    lantern_fork_choice_reset(&client->fork_choice);
    client->has_fork_choice = false;
    reset_local_validators(client);
    lantern_validator_assignment_reset(&client->validator_assignment);
    client->has_validator_assignment = false;
    lantern_consensus_runtime_reset(&client->runtime);
    client->has_runtime = false;

    client->http_port = 0;
    client->metrics_port = 0;
    client->assigned_validators = NULL;
    lantern_log_reset_node_id();
}


/**
 * @brief Append a bootnode to the list if not already present.
 *
 * @note Thread safety: Caller must hold no locks (modifies list directly).
 */
static int
append_unique_bootnode(struct lantern_string_list *list, const char *value)
{
    if (!list || !value)
    {
        return -1;
    }
    if (*value == '\0')
    {
        return 0;
    }
    if (string_list_contains(list, value))
    {
        return 0;
    }
    return lantern_string_list_append(list, value);
}


/**
 * @brief Append bootnodes from genesis ENR records.
 *
 * @note Thread safety: Caller must hold no locks (called during init).
 */
static int
append_genesis_bootnodes(struct lantern_client *client)
{
    if (!client)
    {
        return -1;
    }
    const struct lantern_enr_record_list *enrs = &client->genesis.enrs;
    for (size_t i = 0; i < enrs->count; ++i)
    {
        const struct lantern_enr_record *record = &enrs->records[i];
        if (!record->encoded)
        {
            continue;
        }
        if (append_unique_bootnode(&client->bootnodes, record->encoded) != 0)
        {
            return -1;
        }
        if (client->network.host)
        {
            if (lantern_libp2p_host_add_enr_peer(&client->network, record, LANTERN_LIBP2P_DEFAULT_PEER_TTL_MS) != 0)
            {
                lantern_log_warn(
                    "network",
                    &(const struct lantern_log_metadata){
                        .validator = client->node_id,
                        .peer = record->encoded},
                    "failed to add ENR peer from genesis");
                continue;
            }
            lantern_log_info(
                "network",
                &(const struct lantern_log_metadata){
                    .validator = client->node_id,
                    .peer = record->encoded},
                "bootnode registered sequence=%" PRIu64,
                record->sequence);
        }
    }
    return 0;
}


/**
 * @brief Compute validator assignment from assigned validator indices.
 *
 * @note Thread safety: Caller must hold no locks (called during init).
 */
static int
compute_local_validator_assignment(struct lantern_client *client)
{
    if (!client || !client->assigned_validators)
    {
        return -1;
    }
    lantern_validator_assignment_reset(&client->validator_assignment);
    client->has_validator_assignment = false;
    if (lantern_validator_assignment_from_config(
            &client->genesis.validator_config,
            client->assigned_validators,
            &client->validator_assignment)
        != 0)
    {
        return -1;
    }
    if (!lantern_validator_assignment_is_valid(&client->validator_assignment))
    {
        return -1;
    }
    client->has_validator_assignment = true;
    return 0;
}


/**
 * @brief Populate local validator keys from assignment.
 *
 * @note Thread safety: Caller must hold no locks (called during init).
 */
static int
populate_local_validators(struct lantern_client *client)
{
    if (!client || !client->has_validator_assignment || !client->assigned_validators)
    {
        return -1;
    }

    struct lantern_log_metadata meta = {.validator = client->node_id};
    uint64_t local_count = client->validator_assignment.count;
    if (local_count == 0 || client->validator_assignment.length != local_count)
    {
        return -1;
    }
    if (!client->validator_assignment.indices)
    {
        return -1;
    }
    if (local_count > SIZE_MAX)
    {
        return -1;
    }

    uint64_t total_validators = client->genesis.chain_config.validator_count;
    if (!client->genesis.validator_registry.records
        || client->genesis.validator_registry.count < total_validators)
    {
        return -1;
    }

    char indices_buf[512];
    indices_buf[0] = '\0';
    size_t written = 0;
    for (size_t i = 0; i < client->validator_assignment.length; ++i)
    {
        int n = snprintf(
            indices_buf + written,
            sizeof(indices_buf) - written,
            "%s%" PRIu64,
            written > 0 ? "," : "",
            client->validator_assignment.indices[i]);
        if (n < 0 || (size_t)n >= sizeof(indices_buf) - written)
        {
            strncpy(indices_buf + (sizeof(indices_buf) > 4 ? sizeof(indices_buf) - 4 : 0), "...", 3);
            indices_buf[sizeof(indices_buf) - 1] = '\0';
            break;
        }
        written += (size_t)n;
    }
    lantern_log_info(
        "client",
        &meta,
        "local validator assignment start=%" PRIu64 " count=%" PRIu64 " indices=%s",
        client->validator_assignment.start_index,
        local_count,
        indices_buf[0] ? indices_buf : "-");

    const char *priv_hex = client->assigned_validators->privkey_hex;
    if (!priv_hex || *priv_hex == '\0')
    {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "validator '%s' missing privkey in validator-config",
            client->node_id);
        return -1;
    }

    uint8_t *decoded_secret = NULL;
    size_t decoded_len = 0;
    if (decode_validator_secret(priv_hex, &decoded_secret, &decoded_len) != 0 || decoded_len == 0)
    {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "validator '%s' privkey is invalid",
            client->node_id);
        if (decoded_secret)
        {
            lantern_secure_zero(decoded_secret, decoded_len);
            free(decoded_secret);
        }
        return -1;
    }

    lantern_log_debug(
        "client",
        &meta,
        "decoded validator secret bytes len=%zu",
        decoded_len);

    size_t stored_len = strlen(client->assigned_validators->privkey_hex);
    if (stored_len > 0)
    {
        lantern_secure_zero(client->assigned_validators->privkey_hex, stored_len);
        client->assigned_validators->privkey_hex[0] = '\0';
    }

    size_t count = (size_t)local_count;
    struct lantern_local_validator *validators = calloc(count, sizeof(*validators));
    if (!validators)
    {
        lantern_secure_zero(decoded_secret, decoded_len);
        free(decoded_secret);
        return -1;
    }

    for (size_t i = 0; i < count; ++i)
    {
        uint64_t global_index = client->validator_assignment.indices[i];
        if (global_index >= total_validators)
        {
            for (size_t j = 0; j < i; ++j)
            {
                local_validator_cleanup(&validators[j]);
            }
            free(validators);
            lantern_secure_zero(decoded_secret, decoded_len);
            free(decoded_secret);
            return -1;
        }
        validators[i].global_index = global_index;
        validators[i].registry = &client->genesis.validator_registry.records[global_index];
        validators[i].secret_len = decoded_len;
        if (decoded_len > 0)
        {
            validators[i].secret = malloc(decoded_len);
            if (!validators[i].secret)
            {
                for (size_t j = 0; j <= i; ++j)
                {
                    local_validator_cleanup(&validators[j]);
                }
                free(validators);
                lantern_secure_zero(decoded_secret, decoded_len);
                free(decoded_secret);
                return -1;
            }
            memcpy(validators[i].secret, decoded_secret, decoded_len);
            validators[i].has_secret = true;
        }
        validators[i].last_proposed_slot = UINT64_MAX;
        validators[i].last_attested_slot = UINT64_MAX;
        validators[i].has_pending_attestation = false;
        validators[i].pending_attestation_slot = UINT64_MAX;
        memset(&validators[i].pending_attestation, 0, sizeof(validators[i].pending_attestation));
    }

    bool *enabled = calloc(count, sizeof(*enabled));
    if (!enabled)
    {
        for (size_t i = 0; i < count; ++i)
        {
            local_validator_cleanup(&validators[i]);
        }
        free(validators);
        lantern_secure_zero(decoded_secret, decoded_len);
        free(decoded_secret);
        return -1;
    }
    for (size_t i = 0; i < count; ++i)
    {
        enabled[i] = true;
    }

    if (!client->validator_lock_initialized)
    {
        if (pthread_mutex_init(&client->validator_lock, NULL) != 0)
        {
            free(enabled);
            for (size_t i = 0; i < count; ++i)
            {
                local_validator_cleanup(&validators[i]);
            }
            free(validators);
            lantern_secure_zero(decoded_secret, decoded_len);
            free(decoded_secret);
            return -1;
        }
        client->validator_lock_initialized = true;
    }

    if (pthread_mutex_lock(&client->validator_lock) != 0)
    {
        free(enabled);
        for (size_t i = 0; i < count; ++i)
        {
            local_validator_cleanup(&validators[i]);
        }
        free(validators);
        lantern_secure_zero(decoded_secret, decoded_len);
        free(decoded_secret);
        return -1;
    }

    free(client->validator_enabled);
    client->validator_enabled = enabled;
    enabled = NULL;

    reset_local_validators(client);
    client->local_validators = validators;
    client->local_validator_count = count;
    validators = NULL;

    pthread_mutex_unlock(&client->validator_lock);

    lantern_secure_zero(decoded_secret, decoded_len);
    free(decoded_secret);
    lantern_log_info(
        "client",
        &meta,
        "local validators ready count=%zu secrets_loaded=%zu",
        client->local_validator_count,
        client->local_validator_count);
    return 0;
}


/**
 * @brief Initialize consensus runtime for a client.
 *
 * @note Thread safety: Caller must hold no locks (called during init).
 */
static int
init_consensus_runtime(struct lantern_client *client)
{
    if (!client || !client->has_validator_assignment)
    {
        return -1;
    }
    struct lantern_consensus_runtime_config runtime_config;
    lantern_consensus_runtime_config_init(&runtime_config);
    runtime_config.genesis_time = client->genesis.chain_config.genesis_time;
    runtime_config.validator_count = client->genesis.chain_config.validator_count;
    if (runtime_config.validator_count == 0)
    {
        return -1;
    }
    if (lantern_consensus_runtime_init(
            &client->runtime,
            &runtime_config,
            &client->validator_assignment)
        != 0)
    {
        return -1;
    }
    client->has_runtime = true;
    return 0;
}


/**
 * @brief Copy genesis file paths from options.
 *
 * @note Thread safety: Caller must hold no locks (called during init).
 */
static int
copy_genesis_paths(struct lantern_genesis_paths *paths,
                   const struct lantern_client_options *options)
{
    if (!paths || !options)
    {
        return -1;
    }

    reset_genesis_paths(paths);

    if (set_owned_string(&paths->config_path, options->genesis_config_path) != 0)
    {
        return -1;
    }
    if (set_owned_string(&paths->validator_registry_path, options->validator_registry_path) != 0)
    {
        return -1;
    }
    if (set_owned_string(&paths->nodes_path, options->nodes_path) != 0)
    {
        return -1;
    }
    if (set_owned_string(&paths->state_path, options->genesis_state_path) != 0)
    {
        return -1;
    }
    if (set_owned_string(&paths->validator_config_path, options->validator_config_path) != 0)
    {
        return -1;
    }

    return 0;
}


/**
 * @brief Reset and free all genesis path strings.
 *
 * @note Thread safety: Caller must hold no locks (called during cleanup).
 */
static void
reset_genesis_paths(struct lantern_genesis_paths *paths)
{
    if (!paths)
    {
        return;
    }
    free(paths->config_path);
    free(paths->validator_registry_path);
    free(paths->nodes_path);
    free(paths->state_path);
    free(paths->validator_config_path);
    memset(paths, 0, sizeof(*paths));
}


/**
 * @brief Get the count of local validators.
 *
 * @note Thread safety: None required - reads immutable field after init.
 */
size_t lantern_client_local_validator_count(const struct lantern_client *client)
{
    if (!client)
    {
        return 0;
    }
    return client->local_validator_count;
}


/**
 * @brief Get a local validator by index.
 *
 * @note Thread safety: None required - returns pointer to immutable data.
 */
const struct lantern_local_validator *lantern_client_local_validator(
    const struct lantern_client *client,
    size_t index)
{
    if (!client || index >= client->local_validator_count)
    {
        return NULL;
    }
    return &client->local_validators[index];
}


/**
 * @brief Refresh a cached vote with updated checkpoints.
 *
 * @note Thread safety: Caller must ensure exclusive access to validator.
 */
int lantern_validator_refresh_cached_vote(
    struct lantern_local_validator *validator,
    uint64_t slot,
    const LanternCheckpoint *head,
    const LanternCheckpoint *target,
    const LanternCheckpoint *source,
    LanternSignedVote *vote)
{
    if (!validator || !head || !target || !source || !vote)
    {
        return -1;
    }
    if (!validator->secret_key)
    {
        return -1;
    }
    /* Check if a refresh is needed: source checkpoint changed */
    if (vote->data.source.slot == source->slot
        && memcmp(vote->data.source.root.bytes, source->root.bytes, LANTERN_ROOT_SIZE) == 0)
    {
        /* No change needed */
        return 0;
    }
    /* Update the vote data */
    vote->data.head = *head;
    vote->data.target = *target;
    vote->data.source = *source;
    /* Re-sign the vote */
    if (validator_sign_vote(validator, slot, vote) != 0)
    {
        return -1;
    }
    return 1;
}


/**
 * @brief Publish a signed block via gossipsub.
 *
 * @note Thread safety: Acquires gossip lock internally.
 */
int lantern_client_publish_block(struct lantern_client *client, const LanternSignedBlock *block)
{
    if (!client || !block)
    {
        return -1;
    }
    if (!client->gossip_running)
    {
        lantern_log_error(
            "gossip",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "cannot publish block at slot %" PRIu64 ": gossip service inactive",
            block->message.block.slot);
        return -1;
    }
    if (lantern_gossipsub_service_publish_block(&client->gossip, block) != 0)
    {
        lantern_log_error(
            "gossip",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to publish block at slot %" PRIu64,
            block->message.block.slot);
        return -1;
    }

    /* Use lantern_hash_tree_root_block for the block root (not signed_block).
       The block root should be the hash of the unsigned block content, consistent
       with how other clients (Zeam) and the processing path compute it. */
    LanternRoot block_root;
    char root_hex[2 * LANTERN_ROOT_SIZE + 3];
    if (lantern_hash_tree_root_block(&block->message.block, &block_root) == 0)
    {
        format_root_hex(&block_root, root_hex, sizeof(root_hex));
    }
    else
    {
        root_hex[0] = '\0';
    }

    lantern_log_info(
        "gossip",
        &(const struct lantern_log_metadata){.validator = client->node_id},
        "published block slot=%" PRIu64 " root=%s attestations=%zu",
        block->message.block.slot,
        root_hex[0] ? root_hex : "0x0",
        block->message.block.body.attestations.length);
    return 0;
}

int lantern_client_debug_record_vote(
    struct lantern_client *client,
    const LanternSignedVote *vote,
    const char *peer_id_text)
{
    if (!client || !vote)
    {
        return -1;
    }
    lantern_client_record_vote(client, vote, peer_id_text);
    return 0;
}


int lantern_client_debug_import_block(
    struct lantern_client *client,
    const LanternSignedBlock *block,
    const LanternRoot *block_root,
    const char *peer_id_text)
{
    struct lantern_log_metadata meta = {
        .validator = client ? client->node_id : NULL,
        .peer = peer_id_text,
    };
    return lantern_client_import_block(client, block, block_root, &meta) ? 1 : 0;
}


size_t lantern_client_pending_block_count(const struct lantern_client *client)
{
    if (!client)
    {
        return 0;
    }
    struct lantern_client *mutable_client = (struct lantern_client *)client;
    bool locked = lantern_client_lock_pending(mutable_client);
    size_t count = client->pending_blocks.length;
    if (locked)
    {
        lantern_client_unlock_pending(mutable_client, locked);
    }
    return count;
}


int lantern_client_debug_enqueue_pending_block(
    struct lantern_client *client,
    const LanternSignedBlock *block,
    const LanternRoot *block_root,
    const LanternRoot *parent_root,
    const char *peer_id_text)
{
    if (!client || !block || !block_root || !parent_root)
    {
        return -1;
    }
    lantern_client_enqueue_pending_block(client, block, block_root, parent_root, peer_id_text);
    return 0;
}


int lantern_client_debug_pending_entry(
    const struct lantern_client *client,
    size_t index,
    LanternRoot *out_root,
    LanternRoot *out_parent_root,
    bool *out_parent_requested,
    char *out_peer_text,
    size_t peer_text_len)
{
    if (!client)
    {
        return -1;
    }
    struct lantern_client *mutable_client = (struct lantern_client *)client;
    bool locked = lantern_client_lock_pending(mutable_client);
    if (locked && index >= client->pending_blocks.length)
    {
        lantern_client_unlock_pending(mutable_client, locked);
        return -1;
    }
    if (!locked && index >= client->pending_blocks.length)
    {
        return -1;
    }

    LanternRoot root_copy;
    LanternRoot parent_copy;
    bool requested = false;
    char peer_copy[128];
    peer_copy[0] = '\0';

    if (locked)
    {
        const struct lantern_pending_block *entry = &client->pending_blocks.items[index];
        root_copy = entry->root;
        parent_copy = entry->parent_root;
        requested = entry->parent_requested;
        if (entry->peer_text[0])
        {
            strncpy(peer_copy, entry->peer_text, sizeof(peer_copy) - 1u);
            peer_copy[sizeof(peer_copy) - 1u] = '\0';
        }
        lantern_client_unlock_pending(mutable_client, locked);
    }
    else
    {
        const struct lantern_pending_block *entry = &client->pending_blocks.items[index];
        if (!entry)
        {
            return -1;
        }
        root_copy = entry->root;
        parent_copy = entry->parent_root;
        requested = entry->parent_requested;
        if (entry->peer_text[0])
        {
            strncpy(peer_copy, entry->peer_text, sizeof(peer_copy) - 1u);
            peer_copy[sizeof(peer_copy) - 1u] = '\0';
        }
    }

    if (out_root)
    {
        *out_root = root_copy;
    }
    if (out_parent_root)
    {
        *out_parent_root = parent_copy;
    }
    if (out_parent_requested)
    {
        *out_parent_requested = requested;
    }
    if (out_peer_text && peer_text_len > 0)
    {
        if (peer_text_len == 1)
        {
            out_peer_text[0] = '\0';
        }
        else
        {
            if (peer_copy[0])
            {
                strncpy(out_peer_text, peer_copy, peer_text_len - 1u);
                out_peer_text[peer_text_len - 1u] = '\0';
            }
            else
            {
                out_peer_text[0] = '\0';
            }
        }
    }
    return 0;
}


void lantern_client_debug_pending_reset(struct lantern_client *client)
{
    if (!client)
    {
        return;
    }
    bool locked = lantern_client_lock_pending(client);
    if (locked)
    {
        pending_block_list_reset(&client->pending_blocks);
        lantern_client_unlock_pending(client, locked);
    }
    else
    {
        pending_block_list_reset(&client->pending_blocks);
    }
}


int lantern_client_debug_set_parent_requested(
    struct lantern_client *client,
    const LanternRoot *root,
    bool requested)
{
    if (!client || !root)
    {
        return -1;
    }
    bool locked = lantern_client_lock_pending(client);
    struct lantern_pending_block *entry = NULL;
    if (locked)
    {
        entry = pending_block_list_find(&client->pending_blocks, root);
        if (entry)
        {
            entry->parent_requested = requested;
        }
        lantern_client_unlock_pending(client, locked);
    }
    else
    {
        entry = pending_block_list_find(&client->pending_blocks, root);
        if (entry)
        {
            entry->parent_requested = requested;
        }
    }
    return entry ? 0 : -1;
}


void lantern_client_debug_disable_block_requests(struct lantern_client *client, bool disable)
{
    if (!client)
    {
        return;
    }
    client->debug_disable_block_requests = disable ? true : false;
}


int lantern_client_debug_on_blocks_request_complete(
    struct lantern_client *client,
    const char *peer_id,
    const LanternRoot *request_root,
    int outcome_code)
{
    if (!client)
    {
        return -1;
    }
    enum lantern_blocks_request_outcome outcome;
    switch (outcome_code)
    {
    case LANTERN_DEBUG_BLOCKS_REQUEST_SUCCESS:
        outcome = LANTERN_BLOCKS_REQUEST_SUCCESS;
        break;
    case LANTERN_DEBUG_BLOCKS_REQUEST_FAILED:
        outcome = LANTERN_BLOCKS_REQUEST_FAILED;
        break;
    case LANTERN_DEBUG_BLOCKS_REQUEST_ABORTED:
        outcome = LANTERN_BLOCKS_REQUEST_ABORTED;
        break;
    default:
        return -1;
    }
    lantern_client_on_blocks_request_complete(client, peer_id, request_root, outcome);
    return 0;
}
