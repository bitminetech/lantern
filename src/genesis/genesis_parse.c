#include "genesis_internal.h"

#include <limits.h>
#include <stdlib.h>
#include <string.h>

#include "lantern/support/strings.h"

static const char *mapping_scalar(
    const struct lantern_yaml_document *document,
    const yaml_node_t *mapping,
    const char *key)
{
    return lantern_yaml_scalar(lantern_yaml_mapping_get(document, mapping, key));
}

static int parse_u64_field(
    const struct lantern_yaml_document *document,
    const yaml_node_t *mapping,
    const char *key,
    uint64_t *out)
{
    int ok = 0;
    const char *value = mapping_scalar(document, mapping, key);
    if (value)
    {
        *out = genesis_parse_u64(value, &ok);
    }
    return value && ok ? 0 : -1;
}

static int parse_bool(const char *value, bool *out)
{
    if (!value || !out)
    {
        return -1;
    }
    if (strcmp(value, "true") == 0 || strcmp(value, "1") == 0)
    {
        *out = true;
        return 0;
    }
    if (strcmp(value, "false") == 0 || strcmp(value, "0") == 0)
    {
        *out = false;
        return 0;
    }
    return -1;
}

static void free_validator_config_entry(struct lantern_validator_config_entry *entry)
{
    if (entry)
    {
        free(entry->name);
        free(entry->enr.ip);
        free(entry->xmss_dir);
        free(entry->indices);
        *entry = (struct lantern_validator_config_entry){0};
    }
}

void genesis_free_validator_config(struct lantern_validator_config *config)
{
    if (!config)
    {
        return;
    }
    for (size_t i = 0; i < config->count; ++i)
    {
        free_validator_config_entry(&config->entries[i]);
    }
    free(config->entries);
    *config = (struct lantern_validator_config){0};
}

int genesis_parse_chain_config(const char *path, struct lantern_chain_config *config)
{
    if (!path || !config)
    {
        return LANTERN_GENESIS_ERR_INVALID_PARAM;
    }
    free(config->validators);
    *config = (struct lantern_chain_config){0};

    struct lantern_yaml_document document;
    if (lantern_yaml_document_load(path, &document) != 0)
    {
        return LANTERN_GENESIS_ERR_IO;
    }
    const yaml_node_t *root = lantern_yaml_root(&document);
    int result = LANTERN_GENESIS_ERR_INVALID_DATA;
    if (root && root->type == YAML_MAPPING_NODE
        && parse_u64_field(&document, root, "GENESIS_TIME", &config->genesis_time) == 0
        && config->genesis_time != 0u)
    {
        const char *count_key = NULL;
        if (mapping_scalar(&document, root, "VALIDATOR_COUNT"))
        {
            count_key = "VALIDATOR_COUNT";
        }
        else if (mapping_scalar(&document, root, "NUM_VALIDATORS"))
        {
            count_key = "NUM_VALIDATORS";
        }
        const char *committees = mapping_scalar(&document, root, "ATTESTATION_COMMITTEE_COUNT");
        result = (!count_key
                  || parse_u64_field(
                         &document,
                         root,
                         count_key,
                         &config->validator_count)
                      == 0)
                && (!committees
                || (parse_u64_field(
                        &document,
                        root,
                        "ATTESTATION_COMMITTEE_COUNT",
                        &config->attestation_committee_count)
                        == 0
                    && config->attestation_committee_count != 0u))
            ? LANTERN_GENESIS_OK
            : LANTERN_GENESIS_ERR_INVALID_DATA;
    }
    lantern_yaml_document_reset(&document);
    return result;
}

int genesis_parse_genesis_validators(
    const char *path,
    LanternValidator **out_validators,
    size_t *out_count)
{
    if (!path || !out_validators || !out_count)
    {
        return LANTERN_GENESIS_ERR_INVALID_PARAM;
    }
    *out_validators = NULL;
    *out_count = 0u;

    struct lantern_yaml_document document;
    if (lantern_yaml_document_load(path, &document) != 0)
    {
        return LANTERN_GENESIS_ERR_IO;
    }
    const yaml_node_t *root = lantern_yaml_root(&document);
    const yaml_node_t *sequence = lantern_yaml_mapping_get(
        &document,
        root,
        "GENESIS_VALIDATORS");
    size_t count = lantern_yaml_sequence_length(sequence);
    if (count == 0u)
    {
        lantern_yaml_document_reset(&document);
        return LANTERN_GENESIS_OK;
    }
    LanternValidator *validators = calloc(count, sizeof(*validators));
    int result = validators ? LANTERN_GENESIS_OK : LANTERN_GENESIS_ERR_OUT_OF_MEMORY;
    for (size_t i = 0; result == LANTERN_GENESIS_OK && i < count; ++i)
    {
        const yaml_node_t *entry = lantern_yaml_sequence_get(&document, sequence, i);
        const char *attestation = mapping_scalar(&document, entry, "attestation_pubkey");
        const char *proposal = mapping_scalar(&document, entry, "proposal_pubkey");
        if (!attestation || !proposal
            || genesis_decode_validator_pubkey_hex(
                   attestation,
                   validators[i].attestation_pubkey)
                != LANTERN_GENESIS_OK
            || genesis_decode_validator_pubkey_hex(
                   proposal,
                   validators[i].proposal_pubkey)
                != LANTERN_GENESIS_OK)
        {
            result = LANTERN_GENESIS_ERR_INVALID_DATA;
        }
        validators[i].index = i;
    }
    lantern_yaml_document_reset(&document);
    if (result != LANTERN_GENESIS_OK)
    {
        free(validators);
        return result;
    }
    *out_validators = validators;
    *out_count = count;
    return LANTERN_GENESIS_OK;
}

static int parse_validator_config_entry(
    const struct lantern_yaml_document *document,
    const yaml_node_t *mapping,
    struct lantern_validator_config_entry *entry)
{
    const yaml_node_t *enr = lantern_yaml_mapping_get(document, mapping, "enrFields");
    const char *name = mapping_scalar(document, mapping, "name");
    const char *ip = mapping_scalar(document, enr, "ip");
    const char *quic = mapping_scalar(document, enr, "quic");
    int ok = 0;
    if (!name || !ip || !quic)
    {
        return LANTERN_GENESIS_ERR_INVALID_DATA;
    }
    entry->name = lantern_string_duplicate(name);
    entry->enr.ip = lantern_string_duplicate(ip);
    entry->count = genesis_parse_u64(mapping_scalar(document, mapping, "count"), &ok);
    if (!entry->name || !entry->enr.ip)
    {
        return LANTERN_GENESIS_ERR_OUT_OF_MEMORY;
    }
    if (!ok || entry->count == 0u)
    {
        return LANTERN_GENESIS_ERR_INVALID_DATA;
    }
    uint64_t port = genesis_parse_u64(quic, &ok);
    if (!ok || port > UINT16_MAX)
    {
        return LANTERN_GENESIS_ERR_INVALID_DATA;
    }
    entry->enr.quic_port = (uint16_t)port;
    entry->enr.sequence = 1u;
    const char *sequence = mapping_scalar(document, enr, "seq");
    if (sequence)
    {
        entry->enr.sequence = genesis_parse_u64(sequence, &ok);
        if (!ok)
        {
            return LANTERN_GENESIS_ERR_INVALID_DATA;
        }
    }
    const char *aggregator = mapping_scalar(document, enr, "is_aggregator");
    if (!aggregator)
    {
        aggregator = mapping_scalar(document, mapping, "isAggregator");
    }
    if (aggregator && parse_bool(aggregator, &entry->enr.is_aggregator) != 0)
    {
        return LANTERN_GENESIS_ERR_INVALID_DATA;
    }
    const char *subnet = mapping_scalar(document, mapping, "subnet");
    if (subnet)
    {
        entry->subnet = genesis_parse_u64(subnet, &ok);
        entry->has_subnet = ok != 0;
        if (!ok)
        {
            return LANTERN_GENESIS_ERR_INVALID_DATA;
        }
    }
    const char *xmss_dir = mapping_scalar(document, mapping, "xmssDir");
    if (xmss_dir && !(entry->xmss_dir = lantern_string_duplicate(xmss_dir)))
    {
        return LANTERN_GENESIS_ERR_OUT_OF_MEMORY;
    }
    return LANTERN_GENESIS_OK;
}

int genesis_parse_validator_config(const char *path, struct lantern_validator_config *config)
{
    if (!path || !config)
    {
        return LANTERN_GENESIS_ERR_INVALID_PARAM;
    }
    genesis_free_validator_config(config);
    struct lantern_yaml_document document;
    if (lantern_yaml_document_load(path, &document) != 0)
    {
        return LANTERN_GENESIS_ERR_IO;
    }
    const yaml_node_t *entries_node = lantern_yaml_mapping_get(
        &document,
        lantern_yaml_root(&document),
        "validators");
    size_t count = lantern_yaml_sequence_length(entries_node);
    config->entries = calloc(count, sizeof(*config->entries));
    int result = count > 0u && config->entries
        ? LANTERN_GENESIS_OK
        : LANTERN_GENESIS_ERR_PARSE;
    config->count = count;
    for (size_t i = 0; result == LANTERN_GENESIS_OK && i < count; ++i)
    {
        result = parse_validator_config_entry(
            &document,
            lantern_yaml_sequence_get(&document, entries_node, i),
            &config->entries[i]);
    }
    lantern_yaml_document_reset(&document);
    if (result != LANTERN_GENESIS_OK)
    {
        genesis_free_validator_config(config);
    }
    return result;
}

int genesis_parse_nodes_file(const char *path, struct lantern_enr_record_list *list)
{
    if (!path || !list)
    {
        return LANTERN_GENESIS_ERR_INVALID_PARAM;
    }
    struct lantern_yaml_document document;
    if (lantern_yaml_document_load(path, &document) != 0)
    {
        return LANTERN_GENESIS_ERR_IO;
    }
    const yaml_node_t *root = lantern_yaml_root(&document);
    int result = !root || root->type == YAML_SEQUENCE_NODE
        ? LANTERN_GENESIS_OK
        : LANTERN_GENESIS_ERR_PARSE;
    for (size_t i = 0; result == LANTERN_GENESIS_OK && i < lantern_yaml_sequence_length(root); ++i)
    {
        const char *enr = lantern_yaml_scalar(lantern_yaml_sequence_get(&document, root, i));
        if (!enr || lantern_enr_record_list_append(list, enr) != 0)
        {
            result = LANTERN_GENESIS_ERR_PARSE;
        }
    }
    lantern_yaml_document_reset(&document);
    return result;
}
