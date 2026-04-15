#include "fixture_runner.h"

int main(void) {
    const struct lantern_fixture_run_config config = {
        .suite_name = "lantern_consensus_vectors",
        .state_transition_subdir = "state_transition",
        .fork_choice_subdir = "fork_choice",
        .include_fork_choice = true,
    };
    return lantern_run_fixture_suite(&config);
}
