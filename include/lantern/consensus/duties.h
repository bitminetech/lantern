#ifndef LANTERN_CONSENSUS_DUTIES_H
#define LANTERN_CONSENSUS_DUTIES_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "lantern/genesis/genesis.h"

#ifdef __cplusplus
extern "C" {
#endif

struct lantern_validator_assignment {
    uint64_t *indices;
    size_t length;
};

void lantern_validator_assignment_init(struct lantern_validator_assignment *assignment);
void lantern_validator_assignment_reset(struct lantern_validator_assignment *assignment);
int lantern_validator_assignment_copy(
    struct lantern_validator_assignment *dst,
    const struct lantern_validator_assignment *src);
bool lantern_validator_assignment_is_valid(const struct lantern_validator_assignment *assignment);
int lantern_validator_assignment_from_config(
    const struct lantern_validator_config_entry *entry,
    struct lantern_validator_assignment *assignment);

int lantern_proposer_for_slot(uint64_t slot, uint64_t validator_count, uint64_t *out_proposer_index);
bool lantern_validator_assignment_contains(
    const struct lantern_validator_assignment *assignment,
    uint64_t global_validator_index,
    uint64_t *out_local_index);

#ifdef __cplusplus
}
#endif

#endif /* LANTERN_CONSENSUS_DUTIES_H */
