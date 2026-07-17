#include "lantern/core/client.h"
#include "lantern/support/log.h"
#include "lantern/support/strings.h"
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
    OPT_XMSS_SECRET_PATH,
    OPT_XMSS_SECRET_TEMPLATE,
    OPT_IS_AGGREGATOR,
    OPT_ATTESTATION_COMMITTEE_COUNT,
    OPT_AGGREGATE_SUBNET_IDS,
    OPT_SHADOW_XMSS_AGGREGATE_SIGNATURES_RATE,
    OPT_SHADOW_XMSS_VERIFY_AGGREGATED_SIGNATURES_RATE,
    OPT_SHADOW_XMSS_MERGE_RATE,
    OPT_LEGACY_VALIDATOR_REGISTRY_PATH,
    OPT_LEGACY_VALIDATOR_KEYS_PATH,
    OPT_LEGACY_VALIDATOR_CONFIG_PATH,
};

static const struct option OPTIONS[] = {
    {"data-dir", required_argument, NULL, 'd'},
    {"genesis-config", required_argument, NULL, OPT_GENESIS_CONFIG},
    {"nodes-path", required_argument, NULL, OPT_NODES_PATH},
    {"genesis-state", required_argument, NULL, OPT_GENESIS_STATE},
    {"use-genesis-state", no_argument, NULL, OPT_USE_GENESIS_STATE},
    {"validator_config", required_argument, NULL, OPT_VALIDATOR_CONFIG},
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
    {"xmss-secret", required_argument, NULL, OPT_XMSS_SECRET_PATH},
    {"xmss-secret-template", required_argument, NULL, OPT_XMSS_SECRET_TEMPLATE},
    {"is-aggregator", no_argument, NULL, OPT_IS_AGGREGATOR},
    {"attestation-committee-count", required_argument, NULL, OPT_ATTESTATION_COMMITTEE_COUNT},
    {"aggregate-subnet-ids", required_argument, NULL, OPT_AGGREGATE_SUBNET_IDS},
    {"shadow-xmss-aggregate-signatures-rate", required_argument, NULL, OPT_SHADOW_XMSS_AGGREGATE_SIGNATURES_RATE},
    {"shadow-xmss-verify-aggregated-signatures-rate", required_argument, NULL, OPT_SHADOW_XMSS_VERIFY_AGGREGATED_SIGNATURES_RATE},
    {"shadow-xmss-merge-rate", required_argument, NULL, OPT_SHADOW_XMSS_MERGE_RATE},
    {"help", no_argument, NULL, 'h'},
    {"version", no_argument, NULL, 'v'},
    {0, 0, 0, 0},
};

static volatile sig_atomic_t keep_running = 1;

static void configure_allocator(void)
{
#if defined(__GLIBC__) && defined(M_ARENA_MAX)
    const char *configured = getenv("MALLOC_ARENA_MAX");
    if (!configured || !configured[0])
    {
        (void)mallopt(M_ARENA_MAX, 2);
    }
#endif
}

static void stop_running(int signal_number)
{
    (void)signal_number;
    keep_running = 0;
}

static int register_signals(void)
{
    return signal(SIGINT, stop_running) == SIG_ERR || signal(SIGTERM, stop_running) == SIG_ERR
        ? -1
        : 0;
}

static int parse_unsigned(const char *text, uint64_t maximum, bool allow_zero, uint64_t *out)
{
    if (!text || !out)
    {
        return -1;
    }
    while (isspace((unsigned char)*text))
    {
        ++text;
    }
    if (!*text || *text == '-')
    {
        return -1;
    }
    errno = 0;
    char *end = NULL;
    unsigned long long value = strtoull(text, &end, 10);
    while (end && isspace((unsigned char)*end))
    {
        ++end;
    }
    if (errno != 0 || end == text || (end && *end) || value > maximum
        || (!allow_zero && value == 0u))
    {
        return -1;
    }
    *out = (uint64_t)value;
    return 0;
}

static const char *parent_directory(const char *path)
{
    char *copy = path && path[0] ? strdup(path) : NULL;
    if (!copy)
    {
        return NULL;
    }
    char *directory = dirname(copy);
    char *result = directory ? strdup(directory) : NULL;
    free(copy);
    return result;
}

static lantern_client_error add_subnets(
    struct lantern_client_options *options,
    const char *argument)
{
    char *copy = argument ? strdup(argument) : NULL;
    if (!copy)
    {
        return argument ? LANTERN_CLIENT_ERR_ALLOC : LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    size_t added = 0u;
    lantern_client_error result = LANTERN_CLIENT_OK;
    for (char *entry = copy; entry;)
    {
        char *comma = strchr(entry, ',');
        if (comma)
        {
            *comma = '\0';
        }
        char *trimmed = lantern_trim_whitespace(entry);
        uint64_t subnet = 0u;
        if (trimmed && trimmed[0])
        {
            if (parse_unsigned(trimmed, SIZE_MAX, true, &subnet) != 0)
            {
                result = LANTERN_CLIENT_ERR_INVALID_PARAM;
                break;
            }
            result = lantern_client_options_add_aggregate_subnet_id(options, (size_t)subnet);
            if (result != LANTERN_CLIENT_OK)
            {
                break;
            }
            ++added;
        }
        entry = comma ? comma + 1 : NULL;
    }
    free(copy);
    return result == LANTERN_CLIENT_OK && added == 0u
        ? LANTERN_CLIENT_ERR_INVALID_PARAM
        : result;
}

static lantern_client_error set_shadow_rate(
    struct lantern_client_options *options,
    int option,
    const char *argument)
{
    if (!argument || isspace((unsigned char)argument[0]))
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    char *end = NULL;
    double value = strtod(argument, &end);
    if (end == argument || (end && *end))
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    LanternShadowOperation operation;
    switch (option)
    {
    case OPT_SHADOW_XMSS_AGGREGATE_SIGNATURES_RATE:
        operation = LANTERN_SHADOW_AGGREGATE;
        break;
    case OPT_SHADOW_XMSS_VERIFY_AGGREGATED_SIGNATURES_RATE:
        operation = LANTERN_SHADOW_VERIFY;
        break;
    case OPT_SHADOW_XMSS_MERGE_RATE:
        operation = LANTERN_SHADOW_MERGE;
        break;
    default:
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    options->shadow_xmss_rates[operation] = value;
    options->shadow_xmss_rates_set |= (uint8_t)(1u << operation);
    return LANTERN_CLIENT_OK;
}

static lantern_client_error apply_option(
    struct lantern_client_options *options,
    int option,
    const char *argument,
    bool *help,
    bool *version)
{
    uint64_t number = 0u;
    switch (option)
    {
    case 'd':
        options->data_dir = argument;
        return LANTERN_CLIENT_OK;
    case 'h':
        *help = true;
        return LANTERN_CLIENT_OK;
    case 'v':
        *version = true;
        return LANTERN_CLIENT_OK;
    case OPT_GENESIS_CONFIG:
        options->genesis_config_path = argument;
        return LANTERN_CLIENT_OK;
    case OPT_NODES_PATH:
        options->nodes_path = argument;
        return LANTERN_CLIENT_OK;
    case OPT_VALIDATOR_CONFIG:
        options->validator_config_dir = argument;
        return LANTERN_CLIENT_OK;
    case OPT_NODE_ID:
        options->node_id = argument;
        return LANTERN_CLIENT_OK;
    case OPT_NODE_KEY:
        options->node_key_hex = argument;
        return LANTERN_CLIENT_OK;
    case OPT_NODE_KEY_PATH:
        options->node_key_path = argument;
        return LANTERN_CLIENT_OK;
    case OPT_LISTEN_ADDRESS:
        options->listen_address = argument;
        return LANTERN_CLIENT_OK;
    case OPT_CHECKPOINT_SYNC_URL:
        options->checkpoint_sync_url = argument;
        return LANTERN_CLIENT_OK;
    case OPT_DEVNET:
        options->devnet = argument;
        return LANTERN_CLIENT_OK;
    case OPT_XMSS_KEY_DIR:
    case OPT_HASH_SIG_KEY_DIR:
        options->xmss_key_dir = argument;
        return LANTERN_CLIENT_OK;
    case OPT_XMSS_SECRET_PATH:
        options->xmss_secret_path = argument;
        return LANTERN_CLIENT_OK;
    case OPT_XMSS_SECRET_TEMPLATE:
        options->xmss_secret_template = argument;
        return LANTERN_CLIENT_OK;
    case OPT_GENESIS_STATE:
    case OPT_USE_GENESIS_STATE:
        return LANTERN_CLIENT_OK;
    case OPT_LEGACY_VALIDATOR_REGISTRY_PATH:
    case OPT_LEGACY_VALIDATOR_KEYS_PATH:
    case OPT_LEGACY_VALIDATOR_CONFIG_PATH:
        options->validator_config_dir = parent_directory(argument);
        return options->validator_config_dir ? LANTERN_CLIENT_OK : LANTERN_CLIENT_ERR_ALLOC;
    case OPT_HTTP_PORT:
    case OPT_METRICS_PORT:
        if (parse_unsigned(argument, UINT16_MAX, true, &number) != 0)
        {
            return LANTERN_CLIENT_ERR_INVALID_PARAM;
        }
        if (option == OPT_HTTP_PORT)
        {
            options->http_port = (uint16_t)number;
        }
        else
        {
            options->metrics_port = (uint16_t)number;
        }
        return LANTERN_CLIENT_OK;
    case OPT_BOOTNODE:
        return lantern_client_options_add_bootnode(options, argument);
    case OPT_BOOTNODES:
        return lantern_client_options_add_bootnodes_argument(options, argument);
    case OPT_BOOTNODE_FILE:
        return lantern_client_options_add_bootnodes_from_file(options, argument);
    case OPT_LOG_LEVEL:
        return lantern_log_set_level_from_string(argument, NULL) == 0
            ? LANTERN_CLIENT_OK
            : LANTERN_CLIENT_ERR_INVALID_PARAM;
    case OPT_IS_AGGREGATOR:
        options->is_aggregator = true;
        return LANTERN_CLIENT_OK;
    case OPT_ATTESTATION_COMMITTEE_COUNT:
        if (parse_unsigned(argument, SIZE_MAX, false, &number) != 0)
        {
            return LANTERN_CLIENT_ERR_INVALID_PARAM;
        }
        options->attestation_committee_count_override = number;
        return LANTERN_CLIENT_OK;
    case OPT_AGGREGATE_SUBNET_IDS:
        return add_subnets(options, argument);
    case OPT_SHADOW_XMSS_AGGREGATE_SIGNATURES_RATE:
    case OPT_SHADOW_XMSS_VERIFY_AGGREGATED_SIGNATURES_RATE:
    case OPT_SHADOW_XMSS_MERGE_RATE:
        return set_shadow_rate(options, option, argument);
    default:
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
}

static int parse_arguments(
    struct lantern_client_options *options,
    int argc,
    char **argv,
    bool *help,
    bool *version)
{
    *help = false;
    *version = false;
    int option = 0;
    while ((option = getopt_long(argc, argv, "d:hv", OPTIONS, NULL)) != -1)
    {
        if (apply_option(options, option, optarg, help, version) != LANTERN_CLIENT_OK)
        {
            return -1;
        }
    }
    if ((options->node_key_hex && options->node_key_path)
        || (options->aggregate_subnet_id_count > 0u && !options->is_aggregator))
    {
        return -1;
    }
    return 0;
}

static int run_until_signal(struct lantern_client *client)
{
    struct timespec delay = {.tv_sec = 1, .tv_nsec = 0};
    while (keep_running)
    {
        struct timespec remaining = delay;
        while (nanosleep(&remaining, &remaining) != 0)
        {
            if (errno != EINTR)
            {
                lantern_log_error(
                    "cli",
                    &(const struct lantern_log_metadata){.validator = client->node_id},
                    "sleep failed: %s",
                    strerror(errno));
                return -1;
            }
        }
    }
    return 0;
}

static void print_usage(const char *program)
{
    lantern_log_info(
        "main",
        NULL,
        "Usage: %s [options]\n"
        "  --data-dir PATH              Data directory (default %s)\n"
        "  --genesis-config PATH        Path to genesis config YAML\n"
        "  --nodes-path PATH            Path to nodes.yaml\n"
        "  --genesis-state PATH         Deprecated; ignored\n"
        "  --use-genesis-state          Deprecated; ignored\n"
        "  --validator_config DIR       Directory with validator artifacts\n"
        "  --node-id NAME               Node identifier\n"
        "  --node-key HEX               Local 32-byte private key\n"
        "  --node-key-path PATH         File containing the private key",
        program,
        LANTERN_DEFAULT_DATA_DIR);
    lantern_log_info(
        "main",
        NULL,
        "  --listen-address ADDR        QUIC listen multiaddr\n"
        "  --checkpoint-sync-url URL    Remote finalized-state endpoint\n"
        "  --http-port PORT             HTTP API port\n"
        "  --metrics-port PORT          Metrics port\n"
        "  --bootnode ENR               Add one bootnode\n"
        "  --bootnodes VALUE            ENR or YAML/list file\n"
        "  --bootnodes-file PATH        Newline-delimited ENRs\n"
        "  --devnet NAME                Gossip topic devnet identifier\n"
        "  --attestation-committee-count N  Override committee count\n"
        "  --is-aggregator              Enable aggregation\n"
        "  --aggregate-subnet-ids IDS   Comma-separated imported subnets");
    lantern_log_info(
        "main",
        NULL,
        "  --xmss-key-dir PATH          XMSS key directory\n"
        "  --hash-sig-key-dir PATH      Alias for --xmss-key-dir\n"
        "  --xmss-secret PATH           Single XMSS secret key\n"
        "  --xmss-secret-template STR   Secret-key path template\n"
        "  --shadow-xmss-aggregate-signatures-rate N\n"
        "  --shadow-xmss-verify-aggregated-signatures-rate N\n"
        "  --shadow-xmss-merge-rate N\n"
        "  --log-level LEVEL            trace, debug, info, warn, or error\n"
        "  --help                       Show this message\n"
        "  --version                    Print version information");
}

int main(int argc, char **argv)
{
    configure_allocator();
    struct lantern_client_options options;
    lantern_client_options_init(&options);
    struct lantern_client client = {0};
    bool help = false;
    bool version = false;
    int exit_code = 1;

    const char *environment_level = getenv("LANTERN_LOG_LEVEL");
    if (register_signals() != 0
        || (environment_level && lantern_log_set_level_from_string(environment_level, NULL) != 0)
        || parse_arguments(&options, argc, argv, &help, &version) != 0)
    {
        goto cleanup;
    }
    if (version)
    {
        lantern_log_info(
            "main",
            NULL,
            "lantern %s (commit %s, branch %s)",
            LANTERN_VERSION,
            LANTERN_GIT_COMMIT,
            LANTERN_GIT_BRANCH);
        exit_code = 0;
        goto cleanup;
    }
    if (help)
    {
        print_usage(argv[0]);
        exit_code = 0;
        goto cleanup;
    }
    lantern_log_info(
        "cli",
        NULL,
        "lantern %s (commit %s, branch %s)",
        LANTERN_VERSION,
        LANTERN_GIT_COMMIT,
        LANTERN_GIT_BRANCH);
    if (!options.node_id)
    {
        goto cleanup;
    }
    if (lantern_init(&client, &options) != LANTERN_CLIENT_OK)
    {
        lantern_log_error(
            "cli",
            &(const struct lantern_log_metadata){.validator = options.node_id},
            "initialization failed");
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
    exit_code = run_until_signal(&client) == 0 ? 0 : 1;

cleanup:
    lantern_shutdown(&client);
    lantern_client_options_free(&options);
    if (exit_code != 0)
    {
        print_usage(argv[0]);
    }
    return exit_code;
}
