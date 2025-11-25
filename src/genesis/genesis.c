#include "lantern/genesis/genesis.h"

#include "lantern/support/log.h"
#include "lantern/support/strings.h"
#include "lantern/support/secure_mem.h"
#include "lantern/networking/libp2p.h"
#include "internal/yaml_parser.h"
#include "peer_id/peer_id.h"

#include <ctype.h>
#include <errno.h>
#include <inttypes.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void free_validator_registry(struct lantern_validator_registry *registry);
static void free_validator_config(struct lantern_validator_config *config);
static void free_validator_config_entry(struct lantern_validator_config_entry *entry);

static int parse_chain_config(const char *path, struct lantern_chain_config *config);
static int parse_validator_registry(const char *path, struct lantern_validator_registry *registry);
static int parse_validator_registry_mapping(const char *path, struct lantern_validator_registry *registry);
static int parse_validator_config(const char *path, struct lantern_validator_config *config);
static int parse_nodes_file(const char *path, struct lantern_enr_record_list *list);
static int read_state_blob(const char *path, uint8_t **bytes, size_t *size);
static int parse_genesis_validator_pubkeys(const char *path, uint8_t **out_pubkeys, size_t *out_count);
static void merge_chain_pubkeys_into_registry(
    const struct lantern_chain_config *config,
    struct lantern_validator_registry *registry);

static uint64_t parse_u64(const char *value, int *ok);
static char *dup_trimmed(const char *value);
static const char *yaml_object_value(const LanternYamlObject *object, const char *key);
static int read_scalar_value(const char *path, const char *key, char **out_value);
static enum lantern_validator_client_kind classify_validator_client(const char *name);
static int derive_peer_id_from_privkey_hex(const char *hex, char **out_peer_id);
static int decode_validator_pubkey_hex(const char *hex, uint8_t out[LANTERN_VALIDATOR_PUBKEY_SIZE]);
static int set_record_pubkey(struct lantern_validator_record *record);
static char *trim_whitespace(char *value);

void lantern_genesis_artifacts_init(struct lantern_genesis_artifacts *artifacts) {
    if (!artifacts) {
        return;
    }
    memset(&artifacts->chain_config, 0, sizeof(artifacts->chain_config));
    lantern_enr_record_list_init(&artifacts->enrs);
    artifacts->validator_registry.records = NULL;
    artifacts->validator_registry.count = 0;
    artifacts->validator_config.shuffle = NULL;
    artifacts->validator_config.entries = NULL;
    artifacts->validator_config.count = 0;
    artifacts->state_bytes = NULL;
    artifacts->state_size = 0;
}

void lantern_genesis_artifacts_reset(struct lantern_genesis_artifacts *artifacts) {
    if (!artifacts) {
        return;
    }
    lantern_enr_record_list_reset(&artifacts->enrs);
    free_validator_registry(&artifacts->validator_registry);
    free_validator_config(&artifacts->validator_config);
    free(artifacts->state_bytes);
    artifacts->state_bytes = NULL;
    artifacts->state_size = 0;
    artifacts->chain_config.genesis_time = 0;
    artifacts->chain_config.validator_count = 0;
    if (artifacts->chain_config.validator_pubkeys) {
        free(artifacts->chain_config.validator_pubkeys);
        artifacts->chain_config.validator_pubkeys = NULL;
    }
    artifacts->chain_config.validator_pubkeys_count = 0;
}

int lantern_genesis_load(struct lantern_genesis_artifacts *artifacts, const struct lantern_genesis_paths *paths) {
    if (!artifacts || !paths) {
        return -1;
    }

    if (!paths->config_path || !paths->validator_registry_path || !paths->nodes_path || !paths->state_path
        || !paths->validator_config_path) {
        lantern_log_error("genesis", NULL, "missing required genesis path");
        return -1;
    }

    lantern_genesis_artifacts_reset(artifacts);
    lantern_genesis_artifacts_init(artifacts);

    if (parse_chain_config(paths->config_path, &artifacts->chain_config) != 0) {
        lantern_log_error("genesis", NULL, "failed to parse chain config at %s", paths->config_path);
        goto error;
    }

    if (!artifacts->chain_config.validator_pubkeys || artifacts->chain_config.validator_pubkeys_count == 0) {
        uint8_t *pubkeys = NULL;
        size_t pubkey_count = 0;
        if (parse_genesis_validator_pubkeys(paths->config_path, &pubkeys, &pubkey_count) == 0
            && pubkeys && pubkey_count > 0) {
            artifacts->chain_config.validator_pubkeys = pubkeys;
            artifacts->chain_config.validator_pubkeys_count = pubkey_count;
            if (artifacts->chain_config.validator_count == 0) {
                artifacts->chain_config.validator_count = pubkey_count;
            }
            lantern_log_info("genesis", NULL, "loaded %zu genesis pubkeys from %s", pubkey_count, paths->config_path);
        } else {
            free(pubkeys);
            lantern_log_warn("genesis", NULL, "no genesis pubkeys found in %s", paths->config_path);
        }
    }

    if (parse_validator_registry(paths->validator_registry_path, &artifacts->validator_registry) != 0) {
        lantern_log_error("genesis", NULL, "failed to parse validator registry at %s", paths->validator_registry_path);
        goto error;
    }

    /* If validators.yaml only lists indices (lean quickstart), hydrate pubkeys from config.yaml */
    merge_chain_pubkeys_into_registry(&artifacts->chain_config, &artifacts->validator_registry);

    if (parse_nodes_file(paths->nodes_path, &artifacts->enrs) != 0) {
        lantern_log_error("genesis", NULL, "failed to parse nodes at %s", paths->nodes_path);
        goto error;
    }

    if (parse_validator_config(paths->validator_config_path, &artifacts->validator_config) != 0) {
        lantern_log_error("genesis", NULL, "failed to parse validator-config at %s", paths->validator_config_path);
        goto error;
    }

    if (read_state_blob(paths->state_path, &artifacts->state_bytes, &artifacts->state_size) != 0) {
        lantern_log_error("genesis", NULL, "failed to read genesis state at %s", paths->state_path);
        goto error;
    }

    return 0;

error:
    lantern_genesis_artifacts_reset(artifacts);
    return -1;
}

struct lantern_validator_config_entry *lantern_validator_config_find(
    struct lantern_validator_config *config,
    const char *name) {
    if (!config || !name) {
        return NULL;
    }
    for (size_t i = 0; i < config->count; ++i) {
        if (config->entries[i].name && strcmp(config->entries[i].name, name) == 0) {
            return &config->entries[i];
        }
    }
    return NULL;
}

int lantern_validator_config_assign_ranges(
    struct lantern_validator_config *config,
    uint64_t validator_count) {
    if (!config || !config->entries || config->count == 0) {
        return -1;
    }
    uint64_t next_index = 0;
    for (size_t i = 0; i < config->count; ++i) {
        struct lantern_validator_config_entry *entry = &config->entries[i];
        entry->start_index = next_index;
        uint64_t end = next_index + entry->count;
        if (end > validator_count) {
            return -1;
        }
        entry->end_index = end;
        entry->has_range = true;
        next_index = end;
    }
    if (next_index != validator_count) {
        return -1;
    }
    return 0;
}

static int compare_u64(const void *lhs, const void *rhs) {
    const uint64_t *a = lhs;
    const uint64_t *b = rhs;
    if (*a < *b) {
        return -1;
    }
    if (*a > *b) {
        return 1;
    }
    return 0;
}

static int append_assignment_index(struct lantern_validator_config_entry *entry, uint64_t index) {
    if (!entry) {
        return -1;
    }
    for (size_t i = 0; i < entry->indices_len; ++i) {
        if (entry->indices[i] == index) {
            return -1;
        }
    }
    if (entry->indices_len == entry->indices_cap) {
        size_t new_cap = entry->indices_cap == 0 ? 4 : entry->indices_cap * 2;
        uint64_t *grown = realloc(entry->indices, new_cap * sizeof(*grown));
        if (!grown) {
            return -1;
        }
        entry->indices = grown;
        entry->indices_cap = new_cap;
    }
    entry->indices[entry->indices_len++] = index;
    return 0;
}

int lantern_validator_config_apply_assignments(
    struct lantern_validator_config *config,
    const char *path,
    uint64_t validator_count) {
    if (!config || !config->entries || config->count == 0 || !path) {
        return -1;
    }
    FILE *fp = fopen(path, "r");
    if (!fp) {
        return -1;
    }

    bool *assigned = NULL;
    if (validator_count > 0) {
        assigned = calloc((size_t)validator_count, sizeof(*assigned));
        if (!assigned) {
            fclose(fp);
            return -1;
        }
    }

    bool saw_mapping = false;
    size_t assigned_total = 0;
    struct lantern_validator_config_entry *current = NULL;

    char line[2048];
    while (fgets(line, sizeof(line), fp)) {
        char *trimmed = trim_whitespace(line);
        if (!trimmed || *trimmed == '\0' || *trimmed == '#') {
            continue;
        }
        if (*trimmed == '-') {
            if (!current || !assigned) {
                continue;
            }
            char *value = trimmed + 1;
            value = trim_whitespace(value);
            if (!value || *value == '\0') {
                continue;
            }
            char *endptr = NULL;
            unsigned long long parsed = strtoull(value, &endptr, 10);
            if (endptr == value) {
                continue;
            }
            if (parsed >= validator_count) {
                free(assigned);
                fclose(fp);
                return -1;
            }
            if (assigned[(size_t)parsed]) {
                free(assigned);
                fclose(fp);
                return -1;
            }
            if (append_assignment_index(current, (uint64_t)parsed) != 0) {
                free(assigned);
                fclose(fp);
                return -1;
            }
            assigned[(size_t)parsed] = true;
            assigned_total++;
            continue;
        }
        char *colon = strchr(trimmed, ':');
        if (!colon) {
            current = NULL;
            continue;
        }
        bool has_value = false;
        for (char *p = colon + 1; *p; ++p) {
            if (!isspace((unsigned char)*p)) {
                has_value = true;
                break;
            }
        }
        if (has_value) {
            current = NULL;
            continue;
        }
        *colon = '\0';
        char *name = trim_whitespace(trimmed);
        if (!name || *name == '\0') {
            current = NULL;
            continue;
        }
        size_t name_len = strlen(name);
        if (name_len >= 2 && ((name[0] == '"' && name[name_len - 1] == '"')
                              || (name[0] == '\'' && name[name_len - 1] == '\''))) {
            name[name_len - 1] = '\0';
            ++name;
        }
        struct lantern_validator_config_entry *entry = lantern_validator_config_find(config, name);
        current = entry;
        if (entry) {
            saw_mapping = true;
            entry->indices_len = 0;
        }
    }

    fclose(fp);

    if (!saw_mapping) {
        free(assigned);
        return 0;
    }
    if (assigned_total != validator_count) {
        free(assigned);
        return -1;
    }

    for (size_t i = 0; i < config->count; ++i) {
        struct lantern_validator_config_entry *entry = &config->entries[i];
        if (entry->indices_len != entry->count || entry->indices_len == 0) {
            free(assigned);
            return -1;
        }
        qsort(entry->indices, entry->indices_len, sizeof(*entry->indices), compare_u64);
        entry->start_index = entry->indices[0];
        entry->end_index = entry->indices[entry->indices_len - 1] + 1u;
        entry->has_range = true;
    }

    free(assigned);
    return 0;
}

static void free_validator_registry(struct lantern_validator_registry *registry) {
    if (!registry || !registry->records) {
        return;
    }
    for (size_t i = 0; i < registry->count; ++i) {
        free(registry->records[i].pubkey_hex);
        free(registry->records[i].withdrawal_credentials_hex);
    }
    free(registry->records);
    registry->records = NULL;
    registry->count = 0;
}

static void free_validator_config(struct lantern_validator_config *config) {
    if (!config) {
        return;
    }
    if (config->entries) {
        for (size_t i = 0; i < config->count; ++i) {
            free_validator_config_entry(&config->entries[i]);
        }
        free(config->entries);
    }
    config->entries = NULL;
    config->count = 0;
    free(config->shuffle);
    config->shuffle = NULL;
}

static void free_validator_config_entry(struct lantern_validator_config_entry *entry) {
    if (!entry) {
        return;
    }
    free(entry->name);
    entry->name = NULL;
    if (entry->privkey_hex) {
        size_t len = strlen(entry->privkey_hex);
        if (len > 0) {
            lantern_secure_zero(entry->privkey_hex, len);
        }
        free(entry->privkey_hex);
    }
    entry->privkey_hex = NULL;
    free(entry->peer_id_text);
    entry->peer_id_text = NULL;
    entry->client_kind = LANTERN_VALIDATOR_CLIENT_UNKNOWN;
    free(entry->enr.ip);
    entry->enr.ip = NULL;
    entry->enr.quic_port = 0;
    entry->enr.sequence = 0;
    entry->count = 0;
    free(entry->hash_sig_dir);
    entry->hash_sig_dir = NULL;
    entry->has_range = false;
    entry->start_index = 0;
    entry->end_index = 0;
    free(entry->indices);
    entry->indices = NULL;
    entry->indices_len = 0;
    entry->indices_cap = 0;
}

static char *trim_whitespace(char *value) {
    while (*value && isspace((unsigned char)*value)) {
        ++value;
    }
    char *end = value + strlen(value);
    while (end > value && isspace((unsigned char)*(end - 1))) {
        --end;
    }
    *end = '\0';
    return value;
}

static enum lantern_validator_client_kind classify_validator_client(const char *name) {
    if (!name) {
        return LANTERN_VALIDATOR_CLIENT_UNKNOWN;
    }
    if (strncmp(name, "lantern", 7) == 0) {
        return LANTERN_VALIDATOR_CLIENT_LANTERN;
    }
    if (strncmp(name, "qlean", 5) == 0) {
        return LANTERN_VALIDATOR_CLIENT_QLEAN;
    }
    if (strncmp(name, "ream", 4) == 0) {
        return LANTERN_VALIDATOR_CLIENT_REAM;
    }
    if (strncmp(name, "zeam", 4) == 0) {
        return LANTERN_VALIDATOR_CLIENT_ZEAM;
    }
    return LANTERN_VALIDATOR_CLIENT_UNKNOWN;
}

static int derive_peer_id_from_privkey_hex(const char *hex, char **out_peer_id) {
    if (!hex || !out_peer_id) {
        return -1;
    }
    uint8_t secret[32];
    if (lantern_hex_decode(hex, secret, sizeof(secret)) != 0) {
        return -1;
    }
    uint8_t *encoded = NULL;
    size_t encoded_len = 0;
    if (lantern_libp2p_encode_secp256k1_private_key_proto(secret, sizeof(secret), &encoded, &encoded_len) != 0) {
        lantern_secure_zero(secret, sizeof(secret));
        return -1;
    }
    lantern_secure_zero(secret, sizeof(secret));
    peer_id_t peer_id = {0};
    peer_id_error_t perr = peer_id_create_from_private_key(encoded, encoded_len, &peer_id);
    free(encoded);
    if (perr != PEER_ID_SUCCESS) {
        return -1;
    }
    char buffer[128];
    if (peer_id_to_string(&peer_id, PEER_ID_FMT_BASE58_LEGACY, buffer, sizeof(buffer)) < 0) {
        peer_id_destroy(&peer_id);
        return -1;
    }
    peer_id_destroy(&peer_id);
    char *dup = lantern_string_duplicate(buffer);
    if (!dup) {
        return -1;
    }
    *out_peer_id = dup;
    return 0;
}

static const char *strip_hex_prefix(const char *hex) {
    if (!hex) {
        return NULL;
    }
    if (hex[0] == '0' && (hex[1] == 'x' || hex[1] == 'X')) {
        return hex + 2;
    }
    return hex;
}

static int decode_validator_pubkey_hex(const char *hex, uint8_t out[LANTERN_VALIDATOR_PUBKEY_SIZE]) {
    if (!hex || !out) {
        return -1;
    }
    const char *trimmed = strip_hex_prefix(hex);
    if (!trimmed) {
        return -1;
    }
    size_t len = strlen(trimmed);
    if (len != (size_t)LANTERN_VALIDATOR_PUBKEY_SIZE * 2u) {
        return -1;
    }
    return lantern_hex_decode(trimmed, out, LANTERN_VALIDATOR_PUBKEY_SIZE);
}

static int set_record_pubkey(struct lantern_validator_record *record) {
    if (!record || !record->pubkey_hex) {
        return -1;
    }
    if (decode_validator_pubkey_hex(record->pubkey_hex, record->pubkey_bytes) != 0) {
        return -1;
    }
    record->has_pubkey_bytes = true;
    return 0;
}

static void merge_chain_pubkeys_into_registry(
    const struct lantern_chain_config *config,
    struct lantern_validator_registry *registry) {
    if (!config || !registry || !registry->records || registry->count == 0) {
        return;
    }
    if (!config->validator_pubkeys || config->validator_pubkeys_count == 0) {
        return;
    }
    size_t limit = registry->count;
    if (config->validator_pubkeys_count < limit) {
        limit = config->validator_pubkeys_count;
    }
    for (size_t i = 0; i < limit; ++i) {
        struct lantern_validator_record *rec = &registry->records[i];
        if (!rec->has_pubkey_bytes) {
            memcpy(
                rec->pubkey_bytes,
                config->validator_pubkeys + (i * LANTERN_VALIDATOR_PUBKEY_SIZE),
                LANTERN_VALIDATOR_PUBKEY_SIZE);
            rec->has_pubkey_bytes = true;
        }
        if (!rec->pubkey_hex) {
            char hex[(LANTERN_VALIDATOR_PUBKEY_SIZE * 2u) + 3u];
            if (lantern_bytes_to_hex(
                    rec->pubkey_bytes,
                    LANTERN_VALIDATOR_PUBKEY_SIZE,
                    hex,
                    sizeof(hex),
                    1)
                == 0) {
                rec->pubkey_hex = lantern_string_duplicate(hex);
            }
        }
    }
}

static int parse_chain_config(const char *path, struct lantern_chain_config *config) {
    if (!config) {
        return -1;
    }

    /* clear any existing pubkeys before re-populating */
    if (config->validator_pubkeys) {
        free(config->validator_pubkeys);
        config->validator_pubkeys = NULL;
    }
    config->validator_pubkeys_count = 0;

    FILE *fp = fopen(path, "r");
    if (!fp) {
        perror("lantern: fopen chain config");
        return -1;
    }

    uint8_t *pubkeys = NULL;
    size_t pubkeys_count = 0;
    size_t pubkeys_cap = 0;
    bool in_pubkey_array = false;

    char line[1024];
    while (fgets(line, sizeof(line), fp)) {
        char *trimmed = trim_whitespace(line);
        if (*trimmed == '#' || *trimmed == '\0') {
            continue;
        }

        if (strncmp(trimmed, "GENESIS_VALIDATORS", strlen("GENESIS_VALIDATORS")) == 0) {
            in_pubkey_array = true;
            continue;
        }
        if (in_pubkey_array) {
            if (*trimmed != '-') {
                /* end of the list */
                in_pubkey_array = false;
            } else {
                char *val = trimmed + 1;
                while (*val && isspace((unsigned char)*val)) {
                    ++val;
                }
                if (*val == '"') {
                    ++val;
                    char *endq = strrchr(val, '"');
                    if (endq) {
                        *endq = '\0';
                    }
                }
                uint8_t decoded[LANTERN_VALIDATOR_PUBKEY_SIZE];
                if (decode_validator_pubkey_hex(val, decoded) != 0) {
                    fclose(fp);
                    free(pubkeys);
                    return -1;
                }
                if (pubkeys_count == pubkeys_cap) {
                    size_t new_cap = pubkeys_cap == 0 ? 4 : pubkeys_cap * 2;
                    uint8_t *grown = realloc(pubkeys, new_cap * LANTERN_VALIDATOR_PUBKEY_SIZE);
                    if (!grown) {
                        fclose(fp);
                        free(pubkeys);
                        return -1;
                    }
                    pubkeys = grown;
                    pubkeys_cap = new_cap;
                }
                memcpy(pubkeys + (pubkeys_count * LANTERN_VALIDATOR_PUBKEY_SIZE), decoded, LANTERN_VALIDATOR_PUBKEY_SIZE);
                pubkeys_count++;
                continue;
            }
        }

        char *sep = strchr(trimmed, ':');
        if (!sep) {
            continue;
        }
        *sep = '\0';
        char *key = trimmed;
        char *value = trim_whitespace(sep + 1);

        if (strcmp(key, "GENESIS_TIME") == 0) {
            int ok = 0;
            config->genesis_time = parse_u64(value, &ok);
            if (!ok) {
                fclose(fp);
                free(pubkeys);
                return -1;
            }
        } else if (strcmp(key, "VALIDATOR_COUNT") == 0) {
            int ok = 0;
            config->validator_count = parse_u64(value, &ok);
            if (!ok) {
                fclose(fp);
                free(pubkeys);
                return -1;
            }
        }
    }

    fclose(fp);

    if (pubkeys_count > 0) {
        config->validator_pubkeys = pubkeys;
        config->validator_pubkeys_count = pubkeys_count;
    } else {
        free(pubkeys);
    }

    if (config->validator_count == 0 && pubkeys_count > 0) {
        config->validator_count = pubkeys_count;
    }

    if (config->genesis_time == 0 || config->validator_count == 0) {
        return -1;
    }
    return 0;
}

/* Lightweight parser for GENESIS_VALIDATORS array used by lean quickstart configs. */
static int parse_genesis_validator_pubkeys(const char *path, uint8_t **out_pubkeys, size_t *out_count) {
    if (!path || !out_pubkeys || !out_count) {
        return -1;
    }
    *out_pubkeys = NULL;
    *out_count = 0;

    FILE *fp = fopen(path, "r");
    if (!fp) {
        return -1;
    }

    bool in_array = false;
    size_t count = 0;
    size_t cap = 0;
    uint8_t *pubkeys = NULL;

    char line[1024];
    while (fgets(line, sizeof(line), fp)) {
        char *trimmed = trim_whitespace(line);
        if (*trimmed == '#' || *trimmed == '\0') {
            continue;
        }
        if (strncmp(trimmed, "GENESIS_VALIDATORS", strlen("GENESIS_VALIDATORS")) == 0) {
            in_array = true;
            continue;
        }
        if (!in_array) {
            continue;
        }
        if (*trimmed != '-') {
            /* end of list */
            in_array = false;
            continue;
        }

        char *val = trimmed + 1;
        while (*val && isspace((unsigned char)*val)) {
            ++val;
        }
        if (*val == '"') {
            ++val;
            char *endq = strrchr(val, '"');
            if (endq) {
                *endq = '\0';
            }
        }
        uint8_t decoded[LANTERN_VALIDATOR_PUBKEY_SIZE];
        if (decode_validator_pubkey_hex(val, decoded) != 0) {
            free(pubkeys);
            fclose(fp);
            return -1;
        }
        if (count == cap) {
            size_t new_cap = cap == 0 ? 4 : cap * 2;
            uint8_t *grown = realloc(pubkeys, new_cap * LANTERN_VALIDATOR_PUBKEY_SIZE);
            if (!grown) {
                free(pubkeys);
                fclose(fp);
                return -1;
            }
            pubkeys = grown;
            cap = new_cap;
        }
        memcpy(pubkeys + (count * LANTERN_VALIDATOR_PUBKEY_SIZE), decoded, LANTERN_VALIDATOR_PUBKEY_SIZE);
        count++;
    }

    fclose(fp);
    if (count == 0) {
        free(pubkeys);
        return 0;
    }

    *out_pubkeys = pubkeys;
    *out_count = count;
    return 0;
}

static int parse_validator_registry(const char *path, struct lantern_validator_registry *registry) {
    size_t count = 0;
    LanternYamlObject *objects = lantern_yaml_read_array(path, "validators", &count);
    if (!objects || count == 0) {
        lantern_yaml_free_objects(objects, count);
        return parse_validator_registry_mapping(path, registry);
    }

    bool has_pubkey_field = false;
    for (size_t i = 0; i < count; ++i) {
        if (yaml_object_value(&objects[i], "pubkey")) {
            has_pubkey_field = true;
            break;
        }
    }

    if (!has_pubkey_field) {
        lantern_yaml_free_objects(objects, count);
        return parse_validator_registry_mapping(path, registry);
    }

    bool have_explicit_indices = false;
    size_t max_index = 0;
    for (size_t i = 0; i < count; ++i) {
        const char *index_val = yaml_object_value(&objects[i], "index");
        if (!index_val) {
            continue;
        }
        int ok = 0;
        uint64_t parsed_index = parse_u64(index_val, &ok);
        if (ok) {
            have_explicit_indices = true;
            if (parsed_index > SIZE_MAX) {
                lantern_yaml_free_objects(objects, count);
                return -1;
            }
            if ((size_t)parsed_index > max_index) {
                max_index = (size_t)parsed_index;
            }
        }
    }

    size_t record_count = have_explicit_indices ? (max_index + 1) : count;
    struct lantern_validator_record *records = calloc(record_count, sizeof(*records));
    if (!records) {
        lantern_yaml_free_objects(objects, count);
        return -1;
    }

    bool *assigned = calloc(record_count, sizeof(*assigned));
    if (!assigned) {
        free(records);
        lantern_yaml_free_objects(objects, count);
        return -1;
    }

    for (size_t i = 0; i < count; ++i) {
        size_t slot = i;
        if (have_explicit_indices) {
            const char *index_val = yaml_object_value(&objects[i], "index");
            int ok = 0;
            uint64_t parsed_index = parse_u64(index_val, &ok);
            if (!index_val || !ok || parsed_index >= record_count) {
                free(assigned);
                free_validator_registry(&(struct lantern_validator_registry){.records = records, .count = record_count});
                lantern_yaml_free_objects(objects, count);
                return -1;
            }
            slot = (size_t)parsed_index;
        }

        if (assigned[slot]) {
            free(assigned);
            free_validator_registry(&(struct lantern_validator_registry){.records = records, .count = record_count});
            lantern_yaml_free_objects(objects, count);
            return -1;
        }

        const char *pubkey = yaml_object_value(&objects[i], "pubkey");
        const char *withdrawal = yaml_object_value(&objects[i], "withdrawal_credentials");
        if (!pubkey || !withdrawal) {
            free(assigned);
            free_validator_registry(&(struct lantern_validator_registry){.records = records, .count = record_count});
            lantern_yaml_free_objects(objects, count);
            return -1;
        }

        char *pubkey_hex = dup_trimmed(pubkey);
        char *withdrawal_hex = dup_trimmed(withdrawal);
        if (!pubkey_hex || !withdrawal_hex) {
            free(pubkey_hex);
            free(withdrawal_hex);
            free(assigned);
            free_validator_registry(&(struct lantern_validator_registry){.records = records, .count = record_count});
            lantern_yaml_free_objects(objects, count);
            return -1;
        }

        records[slot].index = (uint64_t)slot;
        records[slot].pubkey_hex = pubkey_hex;
        records[slot].withdrawal_credentials_hex = withdrawal_hex;
        if (set_record_pubkey(&records[slot]) != 0) {
            free(assigned);
            free_validator_registry(&(struct lantern_validator_registry){.records = records, .count = record_count});
            lantern_yaml_free_objects(objects, count);
            return -1;
        }
        assigned[slot] = true;
    }

    if (have_explicit_indices) {
        for (size_t i = 0; i < record_count; ++i) {
            if (!assigned[i]) {
                free(assigned);
                free_validator_registry(&(struct lantern_validator_registry){.records = records, .count = record_count});
                lantern_yaml_free_objects(objects, count);
                return -1;
            }
        }
    }

    free(assigned);
    lantern_yaml_free_objects(objects, count);
    registry->records = records;
    registry->count = record_count;
    return 0;
}

static int parse_validator_registry_mapping(const char *path, struct lantern_validator_registry *registry) {
    FILE *fp = fopen(path, "r");
    if (!fp) {
        return -1;
    }

    size_t *indices = NULL;
    size_t count = 0;
    size_t capacity = 0;
    size_t max_index = 0;

    char line[1024];
    while (fgets(line, sizeof(line), fp)) {
        char *trimmed = trim_whitespace(line);
        if (!trimmed || *trimmed != '-') {
            continue;
        }
        ++trimmed;
        while (*trimmed && isspace((unsigned char)*trimmed)) {
            ++trimmed;
        }
        if (*trimmed == '\0') {
            continue;
        }
        char *endptr = NULL;
        unsigned long long value = strtoull(trimmed, &endptr, 10);
        if (endptr == trimmed) {
            continue;
        }
        if (value > SIZE_MAX) {
            fclose(fp);
            free(indices);
            return -1;
        }
        if (count == capacity) {
            size_t new_capacity = capacity == 0 ? 8 : capacity * 2;
            size_t *new_indices = realloc(indices, new_capacity * sizeof(*new_indices));
            if (!new_indices) {
                fclose(fp);
                free(indices);
                return -1;
            }
            indices = new_indices;
            capacity = new_capacity;
        }
        indices[count++] = (size_t)value;
        if ((size_t)value > max_index) {
            max_index = (size_t)value;
        }
    }
    fclose(fp);

    if (count == 0) {
        free(indices);
        return -1;
    }

    size_t record_count = max_index + 1;
    struct lantern_validator_record *records = calloc(record_count, sizeof(*records));
    if (!records) {
        free(indices);
        return -1;
    }

    const char *zero_hex = "0x00";
    for (size_t i = 0; i < record_count; ++i) {
        records[i].index = i;
        records[i].pubkey_hex = strdup(zero_hex);
        records[i].withdrawal_credentials_hex = strdup(zero_hex);
        if (!records[i].pubkey_hex || !records[i].withdrawal_credentials_hex) {
            free_validator_registry(&(struct lantern_validator_registry){.records = records, .count = record_count});
            free(indices);
            return -1;
        }
        (void)set_record_pubkey(&records[i]);
    }

    registry->records = records;
    registry->count = record_count;
    free(indices);
    return 0;
}

static int parse_validator_config(const char *path, struct lantern_validator_config *config) {
    if (read_scalar_value(path, "shuffle", &config->shuffle) != 0) {
        return -1;
    }

    size_t count = 0;
    LanternYamlObject *objects = lantern_yaml_read_array(path, "validators", &count);
    if (!objects || count == 0) {
        lantern_yaml_free_objects(objects, count);
        return -1;
    }

    struct lantern_validator_config_entry *entries = calloc(count, sizeof(*entries));
    if (!entries) {
        lantern_yaml_free_objects(objects, count);
        return -1;
    }

    for (size_t i = 0; i < count; ++i) {
        const char *name_val = yaml_object_value(&objects[i], "name");
        const char *priv_val = yaml_object_value(&objects[i], "privkey");
        const char *count_val = yaml_object_value(&objects[i], "count");
        const char *ip_val = yaml_object_value(&objects[i], "ip");
        const char *quic_val = yaml_object_value(&objects[i], "quic");
        const char *seq_val = yaml_object_value(&objects[i], "seq");
        const char *hash_dir_val = yaml_object_value(&objects[i], "hashSigDir");

        entries[i].name = dup_trimmed(name_val);
        entries[i].privkey_hex = dup_trimmed(priv_val);
        entries[i].client_kind = classify_validator_client(entries[i].name);
        if (!entries[i].privkey_hex
            || derive_peer_id_from_privkey_hex(entries[i].privkey_hex, &entries[i].peer_id_text) != 0) {
            lantern_yaml_free_objects(objects, count);
            free_validator_config_entry(&entries[i]);
            free(entries);
            return -1;
        }

        int ok = 0;
        entries[i].count = parse_u64(count_val, &ok);
        if (!ok) {
            lantern_yaml_free_objects(objects, count);
            free_validator_config_entry(&entries[i]);
            free(entries);
            return -1;
        }

        entries[i].enr.ip = dup_trimmed(ip_val);
        uint64_t quic_port = parse_u64(quic_val, &ok);
        if (!ok || quic_port > UINT16_MAX) {
            lantern_yaml_free_objects(objects, count);
            free_validator_config_entry(&entries[i]);
            free(entries);
            return -1;
        }
        entries[i].enr.quic_port = (uint16_t)quic_port;

        entries[i].enr.sequence = 1; // default ENR sequence if unspecified
        if (seq_val && *seq_val) {
            entries[i].enr.sequence = parse_u64(seq_val, &ok);
            if (!ok) {
                lantern_yaml_free_objects(objects, count);
                free_validator_config_entry(&entries[i]);
                free(entries);
                return -1;
            }
        }
        entries[i].hash_sig_dir = dup_trimmed(hash_dir_val);
        entries[i].has_range = false;
        entries[i].start_index = 0;
        entries[i].end_index = 0;
        entries[i].indices = NULL;
        entries[i].indices_len = 0;
        entries[i].indices_cap = 0;
    }

    lantern_yaml_free_objects(objects, count);
    config->entries = entries;
    config->count = count;
    return 0;
}

static int parse_nodes_file(const char *path, struct lantern_enr_record_list *list) {
    FILE *fp = fopen(path, "r");
    if (!fp) {
        perror("lantern: fopen nodes");
        return -1;
    }

    char line[2048];
    while (fgets(line, sizeof(line), fp)) {
        char *trimmed = trim_whitespace(line);
        if (*trimmed == '#' || *trimmed == '\0') {
            continue;
        }
        char *enr = strstr(trimmed, "enr:");
        if (!enr) {
            continue;
        }
        enr = trim_whitespace(enr);
        if (*enr == '\0') {
            continue;
        }
        if (lantern_enr_record_list_append(list, enr) != 0) {
            fclose(fp);
            return -1;
        }
    }

    fclose(fp);
    return 0;
}

static int read_state_blob(const char *path, uint8_t **bytes, size_t *size) {
    FILE *fp = fopen(path, "rb");
    if (!fp) {
        perror("lantern: fopen genesis ssz");
        return -1;
    }

    if (fseek(fp, 0, SEEK_END) != 0) {
        fclose(fp);
        return -1;
    }
    long file_size = ftell(fp);
    if (file_size < 0) {
        fclose(fp);
        return -1;
    }
    if (fseek(fp, 0, SEEK_SET) != 0) {
        fclose(fp);
        return -1;
    }

    uint8_t *buffer = malloc((size_t)file_size);
    if (!buffer) {
        fclose(fp);
        return -1;
    }

    size_t read_bytes = fread(buffer, 1, (size_t)file_size, fp);
    fclose(fp);
    if (read_bytes != (size_t)file_size) {
        free(buffer);
        return -1;
    }

    *bytes = buffer;
    *size = read_bytes;
    return 0;
}

static uint64_t parse_u64(const char *value, int *ok) {
    if (ok) {
        *ok = 0;
    }
    if (!value) {
        return 0;
    }

    char *end = NULL;
    errno = 0;
    uint64_t parsed = strtoull(value, &end, 0);
    if (errno != 0 || end == value) {
        return 0;
    }
    if (ok) {
        *ok = 1;
    }
    return parsed;
}

static char *dup_trimmed(const char *value) {
    if (!value) {
        return NULL;
    }
    const char *start = value;
    while (*start && isspace((unsigned char)*start)) {
        ++start;
    }
    const char *end = start + strlen(start);
    while (end > start && isspace((unsigned char)*(end - 1))) {
        --end;
    }

    if (end - start >= 2 && ((*start == '"' && *(end - 1) == '"') || (*start == '\'' && *(end - 1) == '\''))) {
        ++start;
        --end;
    }

    return lantern_string_duplicate_len(start, (size_t)(end - start));
}

static const char *yaml_object_value(const LanternYamlObject *object, const char *key) {
    if (!object || !key) {
        return NULL;
    }
    for (size_t i = 0; i < object->num_pairs; ++i) {
        if (object->pairs[i].key && strcmp(object->pairs[i].key, key) == 0) {
            return object->pairs[i].value;
        }
    }
    return NULL;
}

static int read_scalar_value(const char *path, const char *key, char **out_value) {
    if (!path || !key || !out_value) {
        return -1;
    }

    FILE *fp = fopen(path, "r");
    if (!fp) {
        perror("lantern: fopen validator-config");
        return -1;
    }

    char line[1024];
    size_t key_len = strlen(key);
    while (fgets(line, sizeof(line), fp)) {
        char *trimmed = trim_whitespace(line);
        if (*trimmed == '#' || *trimmed == '\0') {
            continue;
        }

        if (strncmp(trimmed, key, key_len) != 0) {
            continue;
        }
        if (trimmed[key_len] != ':') {
            continue;
        }

        char *value = trim_whitespace(trimmed + key_len + 1);
        *out_value = dup_trimmed(value);
        fclose(fp);
        return *out_value ? 0 : -1;
    }

    fclose(fp);
    return -1;
}
