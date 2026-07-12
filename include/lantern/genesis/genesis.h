#ifndef LANTERN_GENESIS_H
#define LANTERN_GENESIS_H

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#include "lantern/consensus/containers.h"

#include "lantern/networking/enr.h"
#include "lantern/support/string_list.h"

#ifdef __cplusplus
extern "C" {
#endif

struct lantern_genesis_paths {
    char *config_path;
    char *validator_registry_path;
    char *nodes_path;
    char *validator_config_path;
};

struct lantern_chain_config {
    uint64_t genesis_time;
    uint64_t validator_count;
    uint64_t attestation_committee_count;
    uint8_t *validator_attestation_pubkeys; /* flattened array: count * LANTERN_VALIDATOR_PUBKEY_SIZE */
    uint8_t *validator_proposal_pubkeys;    /* flattened array: count * LANTERN_VALIDATOR_PUBKEY_SIZE */
};

struct lantern_validator_config_enr {
    char *ip;
    uint16_t quic_port;
    uint64_t sequence;
    bool is_aggregator;
};

struct lantern_validator_config_entry {
    char *name;
    char *privkey_hex;
    struct lantern_validator_config_enr enr;
    uint64_t count;
    uint64_t subnet;
    bool has_subnet;
    char *xmss_dir;
    uint64_t *indices;
    size_t indices_len;
};

struct lantern_validator_config {
    struct lantern_validator_config_entry *entries;
    size_t count;
};

struct lantern_genesis_artifacts {
    struct lantern_chain_config chain_config;
    struct lantern_enr_record_list enrs;
    struct lantern_validator_config validator_config;
};

void lantern_genesis_artifacts_init(struct lantern_genesis_artifacts *artifacts);
void lantern_genesis_artifacts_reset(struct lantern_genesis_artifacts *artifacts);
int lantern_genesis_load(struct lantern_genesis_artifacts *artifacts, const struct lantern_genesis_paths *paths);
struct lantern_validator_config_entry *lantern_validator_config_find(
    struct lantern_validator_config *config,
    const char *name);
int lantern_validator_config_assign_ranges(
    struct lantern_validator_config *config,
    uint64_t validator_count);
int lantern_validator_config_apply_assignments(
    struct lantern_validator_config *config,
    const char *path,
    uint64_t validator_count);

#ifdef __cplusplus
}
#endif

#endif /* LANTERN_GENESIS_H */
