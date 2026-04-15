#include "fixture_runner.h"

int main(void) {
    const struct lantern_fixture_run_config config = {
        .suite_name = "lantern_genesis_vectors",
        .state_transition_subdir = "state_transition",
        .fork_choice_subdir = NULL,
        .include_fork_choice = false,
    };
    return lantern_run_fixture_suite(&config);
}
