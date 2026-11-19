# Benchmarks

| Item | Value |
|---|---|
| Program | [state.c](state.c), with the test runner's helpers of [tests/runner/runner.c](../tests/runner/runner.c) |
| Run | `bench/run.sh ISA VALIDATORS`: builds lantern for Linux in the lantern-build image and runs the program, under QEMU for an ISA other than the host's; `VECTORS` sets the vector folder |
| CI | [.github/workflows/bench.yml](../.github/workflows/bench.yml): on an ARM64 runner, on a push to a `bench/` branch, at 20000, 80000 and 1000000 validators |
| State | The first mainnet fulu `epoch_processing-rewards_and_penalties` pre-state of the vectors, its validators, balances, participations and inactivity scores repeated up to `VALIDATORS` |
| Timed | A copy of the state, hash_tree_root, process_epoch, and process_slots of a copy to the next epoch's first slot |
