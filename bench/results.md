# Benchmark results

## Run

| Item | Value |
|---|---|
| Commit | `6624bae` |
| Machine | GitHub Actions `ubuntu-24.04-arm` runner, [bench.yml](../.github/workflows/bench.yml) |
| ISA | ARM64, Linux, no emulation |

## Times

| Step | 20000 validators | 80000 validators | 1000000 validators |
|---|---|---|---|
| State buffer | 7 MB | 15 MB | 143 MB |
| State copy | 0.002 s | 0.005 s | 0.048 s |
| ssz_hash_tree_root | 0.137 s | 0.416 s | 4.695 s |
| `StateCache` | 92 MB | 105 MB | 306 MB |
| lantern_state_root, empty cache | 0.133 s | 0.412 s | 4.683 s |
| lantern_state_root, unchanged state | 0.002 s | 0.002 s | 0.019 s |
| process_slots of one slot across an epoch boundary, with the cache | 0.117 s | 0.136 s | 0.647 s |
| process_epoch | 0.112 s | 0.122 s | 0.400 s |
| process_slots to the next epoch, with the cache | 0.116 s | 0.135 s | 0.542 s |

## Steps of process_epoch

| Step | 20000 validators | 80000 validators | 1000000 validators |
|---|---|---|---|
| process_justification_and_finalization | 0.000 s | 0.002 s | 0.032 s |
| process_rewards_and_penalties | 0.002 s | 0.009 s | 0.193 s |
| process_registry_updates | 0.000 s | 0.000 s | 0.007 s |
| process_slashings | 0.000 s | 0.001 s | 0.015 s |
| process_effective_balance_updates | 0.000 s | 0.001 s | 0.007 s |
| process_inactivity_updates | 0.000 s | 0.001 s | 0.023 s |
| process_pending_deposits | 0.000 s | 0.001 s | 0.010 s |
| process_proposer_lookahead | 0.109 s | 0.109 s | 0.115 s |
| The other steps | 0.000 s | 0.000 s | 0.000 s |

## Earlier

| Item | Value |
|---|---|
| Commit | `9cb7ff2`, before compute_shuffled_index ran on one index and get_base_reward_per_increment ran once per loop |
| Machine | An Apple ARM64 Mac, Linux in Docker |
| process_epoch, 20000 validators | 13.072 s: process_proposer_lookahead 10.613 s, process_rewards_and_penalties 2.455 s |
| process_epoch, 80000 validators | 85.804 s |
