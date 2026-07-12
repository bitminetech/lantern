#ifndef LANTERN_CONSENSUS_RUNTIME_H
#define LANTERN_CONSENSUS_RUNTIME_H

#include <stdbool.h>
#include <stdint.h>

#include "lantern/consensus/duties.h"
#include "lantern/consensus/slot_clock.h"

#ifdef __cplusplus
extern "C" {
#endif

struct lantern_consensus_runtime_config {
    uint64_t genesis_time;
    uint32_t seconds_per_slot;
    uint32_t intervals_per_slot;
    uint64_t validator_count;
};

struct lantern_consensus_runtime {
    struct lantern_slot_clock clock;
    struct lantern_slot_timepoint timepoint;
    struct lantern_validator_assignment validator_assignment;
    uint64_t validator_count;
    bool has_timepoint;
    bool initialized;
};

void lantern_consensus_runtime_config_init(struct lantern_consensus_runtime_config *config);
int lantern_consensus_runtime_init(
    struct lantern_consensus_runtime *runtime,
    const struct lantern_consensus_runtime_config *config,
    const struct lantern_validator_assignment *assignment);
void lantern_consensus_runtime_reset(struct lantern_consensus_runtime *runtime);

int lantern_consensus_runtime_update_time(struct lantern_consensus_runtime *runtime, uint64_t now_milliseconds);
const struct lantern_slot_timepoint *lantern_consensus_runtime_current_timepoint(const struct lantern_consensus_runtime *runtime);

int lantern_consensus_runtime_local_proposer(
    const struct lantern_consensus_runtime *runtime,
    uint64_t slot,
    bool *out_is_local,
    uint64_t *out_local_validator_index);


#ifdef __cplusplus
}
#endif

#endif /* LANTERN_CONSENSUS_RUNTIME_H */
