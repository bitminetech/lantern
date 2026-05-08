/**
 * @file main.c
 * @brief Lantern client entry point and command-line interface
 *
 * Provides the main entry point for the Lantern consensus client, handling:
 * - Command-line argument parsing
 * - Signal handling for graceful shutdown
 * - Client initialization and lifecycle management
 */

#include "lantern/core/client.h"
#include "lantern/support/log.h"
#include "lantern/support/version.h"

#include <ctype.h>
#include <errno.h>
#include <getopt.h>
#include <inttypes.h>
#include <libgen.h>
#include <limits.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#if defined(__GLIBC__)
#include <malloc.h>
#endif

enum {
    OPT_GENESIS_CONFIG = 1000,
    OPT_NODES_PATH,
    OPT_GENESIS_STATE,
    OPT_USE_GENESIS_STATE,
    OPT_VALIDATOR_CONFIG,
    OPT_NODE_ID,
    OPT_NODE_KEY,
    OPT_NODE_KEY_PATH,
    OPT_LISTEN_ADDRESS,
    OPT_CHECKPOINT_SYNC_URL,
    OPT_HTTP_PORT,
    OPT_METRICS_PORT,
    OPT_BOOTNODE,
    OPT_BOOTNODES,
    OPT_BOOTNODE_FILE,
    OPT_DEVNET,
    OPT_LOG_LEVEL,
    OPT_XMSS_KEY_DIR,
    OPT_HASH_SIG_KEY_DIR,
    OPT_XMSS_PUBLIC_PATH,
    OPT_XMSS_SECRET_PATH,
    OPT_XMSS_PUBLIC_TEMPLATE,
    OPT_XMSS_SECRET_TEMPLATE,
    OPT_IS_AGGREGATOR,
    OPT_ATTESTATION_COMMITTEE_COUNT,
    /* Deprecated: legacy file-path flags retained so pre-migration
     * lean-quickstart wrappers keep working. Each resolves to the parent
     * directory of the given file and feeds validator_config_dir. */
    OPT_LEGACY_VALIDATOR_REGISTRY_PATH,
    OPT_LEGACY_VALIDATOR_KEYS_PATH,
    OPT_LEGACY_VALIDATOR_CONFIG_PATH,
};

/* Return a heap-allocated copy of dirname(path). Program-lifetime allocation. */
static const char *derive_parent_dir(const char *path)
{
    if (!path || !*path)
    {
        return NULL;
    }
    char *copy = strdup(path);
    if (!copy)
    {
        return NULL;
    }
    char *dir = dirname(copy);
    char *result = dir ? strdup(dir) : NULL;
    free(copy);
    return result;
}

/* Forward declarations */
static lantern_client_error configure_logging_from_env(void);
static lantern_client_error register_signal_handlers(void);
static lantern_client_error apply_option(
    struct lantern_client_options *options,
    int opt,
    const char *optarg,
    bool *show_help,
    bool *show_version);
static lantern_client_error handle_port_option(
    struct lantern_client_options *options,
    int opt,
    const char *optarg);
static lantern_client_error handle_bootnode_option(
    struct lantern_client_options *options,
    int opt,
    const char *optarg);
static lantern_client_error handle_xmss_option(
    struct lantern_client_options *options,
    int opt,
    const char *optarg);
static lantern_client_error parse_arguments(
    struct lantern_client_options *options,
    int argc,
    char **argv,
    bool *show_help,
    bool *show_version);
static lantern_client_error validate_required_options(
    const struct lantern_client_options *options);
static lantern_client_error run_main_loop(struct lantern_client *client);
static void print_usage(const char *prog);
static lantern_client_error parse_u16(const char *text, uint16_t *out_value);
static lantern_client_error parse_size_t_positive(const char *text, size_t *out_value);

/** Flag indicating whether the main loop should continue running. */
static volatile sig_atomic_t g_keep_running = 1;

static void configure_allocator_from_env(void)
{
#if defined(__GLIBC__) && defined(M_ARENA_MAX)
    const char *arena_env = getenv("MALLOC_ARENA_MAX");
    if (!arena_env || arena_env[0] == '\0')
    {
        (void)mallopt(M_ARENA_MAX, 2);
    }
#endif
}


/**
 * Handle termination signals (SIGINT, SIGTERM).
 *
 * Sets the global keep_running flag to false to trigger graceful shutdown.
 *
 * @param signo  Signal number (unused)
 *
 * @note Thread safety: Async-signal safe; only writes a sig_atomic_t flag.
 */
static void lantern_handle_signal(int signo)
{
    (void)signo;
    g_keep_running = 0;
}


/**
 * Register signal handlers for graceful shutdown.
 *
 * @return 0 on success
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM if registration fails
 *
 * @note Thread safety: Must be called during single-threaded startup.
 */
static lantern_client_error register_signal_handlers(void)
{
    if (signal(SIGINT, lantern_handle_signal) == SIG_ERR
        || signal(SIGTERM, lantern_handle_signal) == SIG_ERR)
    {
        lantern_log_error(
            "cli",
            &(const struct lantern_log_metadata){0},
            "failed to register signal handlers");
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    return LANTERN_CLIENT_OK;
}


/**
 * Configure logging from the LANTERN_LOG_LEVEL environment variable.
 *
 * @return LANTERN_CLIENT_OK on success or if the variable is unset
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM if the value is invalid
 *
 * @note Thread safety: Must be called during single-threaded startup.
 */
static lantern_client_error configure_logging_from_env(void)
{
    const char *env_log_level = getenv("LANTERN_LOG_LEVEL");
    if (!env_log_level)
    {
        return LANTERN_CLIENT_OK;
    }

    if (lantern_log_set_level_from_string(env_log_level, NULL) != 0)
    {
        lantern_log_error(
            "cli",
            &(const struct lantern_log_metadata){0},
            "invalid LANTERN_LOG_LEVEL '%s'",
            env_log_level);
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    return LANTERN_CLIENT_OK;
}


/**
 * Apply a single parsed option to the client options structure.
 *
 * @param options       Options structure to update
 * @param opt           Parsed option identifier
 * @param optarg        Argument provided to the option (may be NULL)
 * @param show_help     Output flag indicating help request
 * @param show_version  Output flag indicating version request
 *
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM on invalid option or parse error
 * @return LANTERN_CLIENT_ERR_ALLOC on allocation failure
 *
 * @note Thread safety: Not thread-safe; mutates caller-owned options.
 */
static lantern_client_error apply_option(
    struct lantern_client_options *options,
    int opt,
    const char *optarg,
    bool *show_help,
    bool *show_version)
{
    if (!options || !show_help || !show_version)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    switch (opt)
    {
    case 'd':
        options->data_dir = optarg;
        return LANTERN_CLIENT_OK;
    case 'h':
        *show_help = true;
        return LANTERN_CLIENT_OK;
    case 'v':
        *show_version = true;
        return LANTERN_CLIENT_OK;
    case OPT_GENESIS_CONFIG:
        options->genesis_config_path = optarg;
        return LANTERN_CLIENT_OK;
    case OPT_NODES_PATH:
        options->nodes_path = optarg;
        return LANTERN_CLIENT_OK;
    case OPT_GENESIS_STATE:
        options->genesis_state_path = optarg;
        return LANTERN_CLIENT_OK;
    case OPT_USE_GENESIS_STATE:
        options->use_genesis_state = true;
        return LANTERN_CLIENT_OK;
    case OPT_VALIDATOR_CONFIG:
        options->validator_config_dir = optarg;
        return LANTERN_CLIENT_OK;
    case OPT_LEGACY_VALIDATOR_REGISTRY_PATH:
    case OPT_LEGACY_VALIDATOR_KEYS_PATH:
    case OPT_LEGACY_VALIDATOR_CONFIG_PATH:
    {
        const char *parent = derive_parent_dir(optarg);
        if (!parent)
        {
            return LANTERN_CLIENT_ERR_INVALID_PARAM;
        }
        options->validator_config_dir = parent;
        return LANTERN_CLIENT_OK;
    }
    case OPT_NODE_ID:
        options->node_id = optarg;
        return LANTERN_CLIENT_OK;
    case OPT_NODE_KEY:
        options->node_key_hex = optarg;
        return LANTERN_CLIENT_OK;
    case OPT_NODE_KEY_PATH:
        options->node_key_path = optarg;
        return LANTERN_CLIENT_OK;
    case OPT_LISTEN_ADDRESS:
        options->listen_address = optarg;
        return LANTERN_CLIENT_OK;
    case OPT_CHECKPOINT_SYNC_URL:
        options->checkpoint_sync_url = optarg;
        return LANTERN_CLIENT_OK;
    case OPT_HTTP_PORT:
    case OPT_METRICS_PORT:
        return handle_port_option(options, opt, optarg);
    case OPT_BOOTNODE:
    case OPT_BOOTNODES:
    case OPT_BOOTNODE_FILE:
        return handle_bootnode_option(options, opt, optarg);
    case OPT_DEVNET:
        options->devnet = optarg;
        return LANTERN_CLIENT_OK;
    case OPT_LOG_LEVEL:
        if (lantern_log_set_level_from_string(optarg, NULL) != 0)
        {
            lantern_log_error(
                "cli",
                &(const struct lantern_log_metadata){.validator = options->node_id},
                "invalid log-level '%s'",
                optarg);
            return LANTERN_CLIENT_ERR_INVALID_PARAM;
        }
        return LANTERN_CLIENT_OK;
    case OPT_XMSS_KEY_DIR:
    case OPT_HASH_SIG_KEY_DIR:
    case OPT_XMSS_PUBLIC_PATH:
    case OPT_XMSS_SECRET_PATH:
    case OPT_XMSS_PUBLIC_TEMPLATE:
    case OPT_XMSS_SECRET_TEMPLATE:
        return handle_xmss_option(options, opt, optarg);
    case OPT_IS_AGGREGATOR:
        options->is_aggregator = true;
        return LANTERN_CLIENT_OK;
    case OPT_ATTESTATION_COMMITTEE_COUNT: {
        size_t parsed_value = 0;
        if (parse_size_t_positive(optarg, &parsed_value) != LANTERN_CLIENT_OK)
        {
            lantern_log_error(
                "cli",
                &(const struct lantern_log_metadata){.validator = options->node_id},
                "invalid attestation-committee-count '%s'",
                optarg ? optarg : "");
            return LANTERN_CLIENT_ERR_INVALID_PARAM;
        }
        options->attestation_committee_count_override = (uint64_t)parsed_value;
        options->has_attestation_committee_count_override = true;
        return LANTERN_CLIENT_OK;
    }
    default:
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
}


/**
 * Handle port-related CLI options.
 *
 * @param options  Options structure to update
 * @param opt      Parsed option identifier
 * @param optarg   Port value string
 *
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM on parse error or invalid option
 *
 * @note Thread safety: Not thread-safe; mutates caller-owned options.
 */
static lantern_client_error handle_port_option(
    struct lantern_client_options *options,
    int opt,
    const char *optarg)
{
    if (!options || !optarg)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    uint16_t *target_port = (opt == OPT_HTTP_PORT) ? &options->http_port : &options->metrics_port;
    const char *label = (opt == OPT_HTTP_PORT) ? "http-port" : "metrics-port";

    if (parse_u16(optarg, target_port) != 0)
    {
        lantern_log_error(
            "cli",
            &(const struct lantern_log_metadata){.validator = options->node_id},
            "invalid %s '%s'",
            label,
            optarg);
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    return LANTERN_CLIENT_OK;
}


/**
 * Handle bootnode-related CLI options.
 *
 * @param options  Options structure to update
 * @param opt      Parsed option identifier
 * @param optarg   ENR value or path
 *
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM on error
 *
 * @note Thread safety: Not thread-safe; mutates caller-owned options.
 */
static lantern_client_error handle_bootnode_option(
    struct lantern_client_options *options,
    int opt,
    const char *optarg)
{
    if (!options || !optarg)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    lantern_client_error result = LANTERN_CLIENT_ERR_INVALID_PARAM;
    switch (opt)
    {
    case OPT_BOOTNODE:
        result = lantern_client_options_add_bootnode(options, optarg);
        break;
    case OPT_BOOTNODES:
        result = lantern_client_options_add_bootnodes_argument(options, optarg);
        break;
    case OPT_BOOTNODE_FILE:
        result = lantern_client_options_add_bootnodes_from_file(options, optarg);
        break;
    default:
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    return result;
}


/**
 * Handle hash signature configuration options.
 *
 * @param options  Options structure to update
 * @param opt      Parsed option identifier
 * @param optarg   Option argument string
 *
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM on invalid option
 *
 * @note Thread safety: Not thread-safe; mutates caller-owned options.
 */
static lantern_client_error handle_xmss_option(
    struct lantern_client_options *options,
    int opt,
    const char *optarg)
{
    if (!options)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    switch (opt)
    {
    case OPT_XMSS_KEY_DIR:
    case OPT_HASH_SIG_KEY_DIR:
        options->xmss_key_dir = optarg;
        return LANTERN_CLIENT_OK;
    case OPT_XMSS_PUBLIC_PATH:
        options->xmss_public_path = optarg;
        return LANTERN_CLIENT_OK;
    case OPT_XMSS_SECRET_PATH:
        options->xmss_secret_path = optarg;
        return LANTERN_CLIENT_OK;
    case OPT_XMSS_PUBLIC_TEMPLATE:
        options->xmss_public_template = optarg;
        return LANTERN_CLIENT_OK;
    case OPT_XMSS_SECRET_TEMPLATE:
        options->xmss_secret_template = optarg;
        return LANTERN_CLIENT_OK;
    default:
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
}


/**
 * Parse CLI arguments and populate client options.
 *
 * @param options       Options structure to populate
 * @param argc          Argument count
 * @param argv          Argument vector
 * @param show_help     Output flag indicating help was requested
 * @param show_version  Output flag indicating version was requested
 *
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM on invalid input or parse failure
 *
 * @note Thread safety: Not thread-safe; mutates caller-owned options and
 *       relies on global getopt state.
 */
static lantern_client_error parse_arguments(
    struct lantern_client_options *options,
    int argc,
    char **argv,
    bool *show_help,
    bool *show_version)
{
    if (!options || !argv || !show_help || !show_version)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    *show_help = false;
    *show_version = false;

    static const struct option long_options[] = {
        {"data-dir", required_argument, NULL, 'd'},
        {"genesis-config", required_argument, NULL, OPT_GENESIS_CONFIG},
        {"nodes-path", required_argument, NULL, OPT_NODES_PATH},
        {"genesis-state", required_argument, NULL, OPT_GENESIS_STATE},
        {"use-genesis-state", no_argument, NULL, OPT_USE_GENESIS_STATE},
        {"validator_config", required_argument, NULL, OPT_VALIDATOR_CONFIG},
        /* Deprecated: pre-migration lean-quickstart wrappers pass these three as
         * file paths; we accept them and derive the parent directory. */
        {"validator-registry-path", required_argument, NULL, OPT_LEGACY_VALIDATOR_REGISTRY_PATH},
        {"validator-keys-path", required_argument, NULL, OPT_LEGACY_VALIDATOR_KEYS_PATH},
        {"validator-config", required_argument, NULL, OPT_LEGACY_VALIDATOR_CONFIG_PATH},
        {"node-id", required_argument, NULL, OPT_NODE_ID},
        {"node-key", required_argument, NULL, OPT_NODE_KEY},
        {"node-key-path", required_argument, NULL, OPT_NODE_KEY_PATH},
        {"listen-address", required_argument, NULL, OPT_LISTEN_ADDRESS},
        {"checkpoint-sync-url", required_argument, NULL, OPT_CHECKPOINT_SYNC_URL},
        {"http-port", required_argument, NULL, OPT_HTTP_PORT},
        {"metrics-port", required_argument, NULL, OPT_METRICS_PORT},
        {"bootnode", required_argument, NULL, OPT_BOOTNODE},
        {"bootnodes", required_argument, NULL, OPT_BOOTNODES},
        {"bootnodes-file", required_argument, NULL, OPT_BOOTNODE_FILE},
        {"devnet", required_argument, NULL, OPT_DEVNET},
        {"log-level", required_argument, NULL, OPT_LOG_LEVEL},
        {"xmss-key-dir", required_argument, NULL, OPT_XMSS_KEY_DIR},
        {"hash-sig-key-dir", required_argument, NULL, OPT_HASH_SIG_KEY_DIR},
        {"xmss-public", required_argument, NULL, OPT_XMSS_PUBLIC_PATH},
        {"xmss-secret", required_argument, NULL, OPT_XMSS_SECRET_PATH},
        {"xmss-public-template", required_argument, NULL, OPT_XMSS_PUBLIC_TEMPLATE},
        {"xmss-secret-template", required_argument, NULL, OPT_XMSS_SECRET_TEMPLATE},
        {"is-aggregator", no_argument, NULL, OPT_IS_AGGREGATOR},
        {"attestation-committee-count", required_argument, NULL, OPT_ATTESTATION_COMMITTEE_COUNT},
        {"help", no_argument, NULL, 'h'},
        {"version", no_argument, NULL, 'v'},
        {0, 0, 0, 0},
    };

    int opt = 0;
    int option_index = 0;
    while ((opt = getopt_long(argc, argv, "d:hv", long_options, &option_index)) != -1)
    {
        if (apply_option(options, opt, optarg, show_help, show_version) != LANTERN_CLIENT_OK)
        {
            return LANTERN_CLIENT_ERR_INVALID_PARAM;
        }
    }

    if (options->use_genesis_state || options->genesis_state_path)
    {
        lantern_log_warn(
            "cli",
            &(const struct lantern_log_metadata){.validator = options->node_id},
            "ignoring --genesis-state/--use-genesis-state; Lantern derives genesis from config/annotated_validators");
        options->use_genesis_state = false;
        options->genesis_state_path = NULL;
    }

    if (options->node_key_hex && options->node_key_path)
    {
        lantern_log_error(
            "cli",
            &(const struct lantern_log_metadata){.validator = options->node_id},
            "specify only one of --node-key or --node-key-path");
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    return LANTERN_CLIENT_OK;
}


/**
 * Validate required options are present.
 *
 * @param options  Populated options structure
 *
 * @return LANTERN_CLIENT_OK when required options are present
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM when validation fails
 *
 * @note Thread safety: Reentrant; read-only access to options.
 */
static lantern_client_error validate_required_options(
    const struct lantern_client_options *options)
{
    if (!options)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    if (!options->node_id)
    {
        lantern_log_error(
            "cli",
            &(const struct lantern_log_metadata){0},
            "--node-id is required");
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    return LANTERN_CLIENT_OK;
}


/**
 * Run the main sleep loop until shutdown is requested.
 *
 * @param client  Initialized client instance (used for logging)
 *
 * @return LANTERN_CLIENT_OK on clean exit
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM on failure
 *
 * @note Thread safety: Relies on the global shutdown flag; should be invoked
 *       from the main thread.
 */
static lantern_client_error run_main_loop(struct lantern_client *client)
{
    if (!client)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    const struct timespec sleep_request = {
        .tv_sec = 1,
        .tv_nsec = 0,
    };
    struct timespec sleep_remaining = sleep_request;
    while (g_keep_running)
    {
        if (nanosleep(&sleep_remaining, &sleep_remaining) != 0)
        {
            if (errno == EINTR)
            {
                sleep_remaining = sleep_request;
                continue;
            }

            lantern_log_error(
                "cli",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "sleep interrupted: %s",
                strerror(errno));
            return LANTERN_CLIENT_ERR_INVALID_PARAM;
        }
        sleep_remaining = sleep_request;
    }

    return LANTERN_CLIENT_OK;
}


/**
 * Program entry point.
 *
 * Parses command-line arguments, configures logging, initializes the client,
 * and blocks until a shutdown signal is received.
 *
 * @param argc  Argument count
 * @param argv  Argument vector
 *
 * @return 0 on clean shutdown
 * @return 1 on argument or initialization failure
 *
 * @note Thread safety: Must be invoked on the process main thread before any
 *       additional threads are started.
 */
int main(int argc, char **argv)
{
    configure_allocator_from_env();

    int exit_code = 0;
    struct lantern_client_options options;
    lantern_client_options_init(&options);

    struct lantern_client client;
    memset(&client, 0, sizeof(client));

    bool show_version = false;
    bool show_help = false;

    if (register_signal_handlers() != 0)
    {
        exit_code = 1;
        goto cleanup;
    }

    if (configure_logging_from_env() != 0)
    {
        exit_code = 1;
        goto cleanup;
    }

    if (parse_arguments(&options, argc, argv, &show_help, &show_version) != 0)
    {
        exit_code = 1;
        goto cleanup;
    }

    if (show_version)
    {
        lantern_log_info(
            "main", NULL, "lantern %s (commit %s, branch %s)",
            LANTERN_VERSION, LANTERN_GIT_COMMIT, LANTERN_GIT_BRANCH);
        goto cleanup;
    }

    if (show_help)
    {
        print_usage(argv[0]);
        goto cleanup;
    }

    lantern_log_info(
        "cli", NULL, "lantern %s (commit %s, branch %s)",
        LANTERN_VERSION, LANTERN_GIT_COMMIT, LANTERN_GIT_BRANCH);

    if (validate_required_options(&options) != 0)
    {
        exit_code = 1;
        goto cleanup;
    }

    if (lantern_init(&client, &options) != 0)
    {
        lantern_log_error(
            "cli",
            &(const struct lantern_log_metadata){.validator = options.node_id},
            "initialization failed");
        exit_code = 1;
        goto cleanup;
    }

    lantern_log_info(
        "cli",
        &(const struct lantern_log_metadata){.validator = client.node_id},
        "lantern ready genesis_time=%" PRIu64 " validators=%" PRIu64
        " enr=%zu manual_bootnodes=%zu local_enr=%s",
        client.genesis.chain_config.genesis_time,
        client.genesis.chain_config.validator_count,
        client.genesis.enrs.count,
        client.bootnodes.len,
        client.local_enr.encoded ? client.local_enr.encoded : "-");

    if (run_main_loop(&client) != 0)
    {
        exit_code = 1;
        goto cleanup;
    }

    lantern_log_info(
        "cli",
        &(const struct lantern_log_metadata){.validator = client.node_id},
        "shutdown requested");

cleanup:
    lantern_shutdown(&client);
    lantern_client_options_free(&options);
    if (exit_code != 0)
    {
        print_usage(argv[0]);
    }
    return exit_code;
}


/**
 * @brief Print path-related CLI options.
 */
static void print_usage_paths(void)
{
    lantern_log_info(
        "main",
        NULL,
        "  --data-dir PATH              Data directory (default %s)",
        LANTERN_DEFAULT_DATA_DIR);
    lantern_log_info(
        "main",
        NULL,
        "  --genesis-config PATH        Path to genesis config YAML");
    lantern_log_info(
        "main",
        NULL,
        "  --nodes-path PATH            Path to nodes.yaml");
    lantern_log_info(
        "main",
        NULL,
        "  --genesis-state PATH         Deprecated; ignored");
    lantern_log_info(
        "main",
        NULL,
        "  --use-genesis-state          Deprecated; ignored");
    lantern_log_info(
        "main",
        NULL,
        "  --validator_config DIR       Directory with annotated_validators.yaml and validator-config.yaml");
}


/**
 * @brief Print node identity CLI options.
 */
static void print_usage_node_identity(void)
{
    lantern_log_info(
        "main",
        NULL,
        "  --node-id NAME               Node identifier (e.g., ream_0)");
    lantern_log_info(
        "main",
        NULL,
        "  --node-key HEX               Local node private key (32-byte hex)");
    lantern_log_info(
        "main",
        NULL,
        "  --node-key-path PATH         Path to file containing node private key hex");
}


/**
 * @brief Print network-related CLI options.
 */
static void print_usage_network(void)
{
    lantern_log_info(
        "main",
        NULL,
        "  --listen-address ADDR        QUIC listen multiaddr");
    lantern_log_info(
        "main",
        NULL,
        "  --checkpoint-sync-url URL    Fetch finalized state from remote beacon API");
    lantern_log_info(
        "main",
        NULL,
        "  --http-port PORT             HTTP API port");
    lantern_log_info(
        "main",
        NULL,
        "  --metrics-port PORT          Metrics port");
    lantern_log_info(
        "main",
        NULL,
        "  --bootnode ENR               Add a bootnode enr");
    lantern_log_info(
        "main",
        NULL,
        "  --bootnodes VALUE            ENR or path to YAML/List file of ENRs");
    lantern_log_info(
        "main",
        NULL,
        "  --bootnodes-file PATH        File with newline-delimited ENRs");
    lantern_log_info(
        "main",
        NULL,
        "  --devnet NAME                Devnet identifier for gossip topics");
    lantern_log_info(
        "main",
        NULL,
        "  --attestation-committee-count N  Number of attestation committees (subnets); overrides config.yaml ATTESTATION_COMMITTEE_COUNT");
    lantern_log_info(
        "main",
        NULL,
        "  --is-aggregator              Mark this node as the subnet aggregator");
}


/**
 * @brief Print hash signature key CLI options.
 */
static void print_usage_xmss(void)
{
    lantern_log_info(
        "main",
        NULL,
        "  --xmss-key-dir PATH     Directory containing XMSS key files");
    lantern_log_info(
        "main",
        NULL,
        "  --hash-sig-key-dir PATH Alias for --xmss-key-dir");
    lantern_log_info(
        "main",
        NULL,
        "  --xmss-public PATH      Path to a single XMSS public key file");
    lantern_log_info(
        "main",
        NULL,
        "  --xmss-secret PATH      Path to a single XMSS secret key file");
    lantern_log_info(
        "main",
        NULL,
        "  --xmss-public-template STR  printf-style template for public key paths");
    lantern_log_info(
        "main",
        NULL,
        "  --xmss-secret-template STR  printf-style template for secret key paths");
}


/**
 * @brief Print miscellaneous CLI options.
 */
static void print_usage_misc(void)
{
    lantern_log_info(
        "main",
        NULL,
        "  --log-level LEVEL           Minimum log level (trace, debug, info, warn, error)");
    lantern_log_info(
        "main",
        NULL,
        "  --help                       Show this message");
    lantern_log_info(
        "main",
        NULL,
        "  --version                    Print version information");
}


/**
 * Print command-line usage information.
 *
 * Outputs all available command-line options and their descriptions
 * to the log.
 *
 * @param prog  Program name (typically argv[0])
 *
 * @note Thread safety: Intended for single-threaded CLI execution before
 *       worker threads are started.
 */
static void print_usage(const char *prog)
{
    lantern_log_info("main", NULL, "Usage: %s [options]", prog);
    print_usage_paths();
    print_usage_node_identity();
    print_usage_network();
    print_usage_xmss();
    print_usage_misc();
}


/**
 * Parse a string as an unsigned 16-bit integer.
 *
 * @param text       String to parse
 * @param out_value  Output parameter for the parsed value
 *
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM if text is NULL, out_value is NULL, or parsing fails
 *
 * @note Thread safety: Reentrant; no shared state.
 */
static lantern_client_error parse_u16(const char *text, uint16_t *out_value)
{
    if (!text || !out_value)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    errno = 0;
    char *end = NULL;
    long parsed = strtol(text, &end, 10);
    if (errno != 0 || end == text)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    while (end && *end != '\0' && isspace((unsigned char)*end))
    {
        ++end;
    }
    if (end && *end != '\0')
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    if (parsed < 0 || parsed > UINT16_MAX)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    *out_value = (uint16_t)parsed;
    return LANTERN_CLIENT_OK;
}

static lantern_client_error parse_size_t_positive(const char *text, size_t *out_value)
{
    if (!text || !out_value)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    errno = 0;
    char *end = NULL;
    unsigned long long parsed = strtoull(text, &end, 10);
    if (errno != 0 || end == text)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    while (end && *end != '\0' && isspace((unsigned char)*end))
    {
        ++end;
    }
    if ((end && *end != '\0') || parsed == 0 || parsed > (unsigned long long)SIZE_MAX)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    *out_value = (size_t)parsed;
    return LANTERN_CLIENT_OK;
}
