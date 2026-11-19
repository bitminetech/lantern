# Benchmark results

## Run

| Item | Value |
|---|---|
| Commit | `fa0793c` |
| Machine | GitHub Actions `ubuntu-24.04-arm` runner, [bench.yml](../.github/workflows/bench.yml) |
| ISA | ARM64, Linux, no emulation |

## Times

| Step | 20000 validators | 80000 validators | 1000000 validators |
|---|---|---|---|
| State buffer | 7 MB | 15 MB | 143 MB |
| State copy | 0.002 s | 0.005 s | 0.047 s |
| ssz_hash_tree_root | 0.137 s | 0.416 s | 4.699 s |
| `StateCache` | 92 MB | 105 MB | 306 MB |
| lantern_state_root, empty cache | 0.133 s | 0.412 s | 4.685 s |
| lantern_state_root, unchanged state | 0.002 s | 0.002 s | 0.015 s |
| process_slots of one slot inside an epoch, with the cache | 0.002 s | 0.002 s | 0.014 s |
| get_beacon_committee, no cache | 0.0074 s | 0.0070 s | 0.0331 s |
| get_beacon_committee, empty `CommitteeCache` | 0.0063 s | 0.0246 s | 0.3224 s |
| get_beacon_committee, filled `CommitteeCache` | 0.000007 s | 0.000008 s | 0.000008 s |
| process_epoch | 0.111 s | 0.121 s | 0.310 s |
| process_slots to the next epoch, with the cache | 0.116 s | 0.134 s | 0.449 s |

## Steps of process_epoch

| Step | 20000 validators | 80000 validators | 1000000 validators |
|---|---|---|---|
| process_justification_and_finalization | 0.000 s | 0.002 s | 0.027 s |
| process_rewards_and_penalties | 0.002 s | 0.008 s | 0.129 s |
| process_registry_updates | 0.000 s | 0.000 s | 0.006 s |
| process_slashings | 0.000 s | 0.001 s | 0.013 s |
| process_effective_balance_updates | 0.000 s | 0.000 s | 0.006 s |
| process_inactivity_updates | 0.000 s | 0.001 s | 0.017 s |
| process_pending_deposits | 0.000 s | 0.000 s | 0.009 s |
| process_proposer_lookahead | 0.109 s | 0.109 s | 0.114 s |
| The other steps | 0.000 s | 0.000 s | 0.000 s |

## Earlier

| Item | Value |
|---|---|
| Commit | `9cb7ff2`, before compute_shuffled_index ran on one index and get_base_reward_per_increment ran once per loop |
| Machine | An Apple ARM64 Mac, Linux in Docker |
| process_epoch, 20000 validators | 13.072 s: process_proposer_lookahead 10.613 s, process_rewards_and_penalties 2.455 s |
| process_epoch, 80000 validators | 85.804 s |
