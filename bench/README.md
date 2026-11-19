# Benchmarks

| Item | Value |
|---|---|
| Program | [state.c](state.c), with the test runner's helpers of [tests/runner/runner.c](../tests/runner/runner.c) |
| Run | `bench/run.sh ISA VALIDATORS`: builds lantern for Linux in the lantern-build image and runs the program, under QEMU for an ISA other than the host's; `VECTORS` sets the vector folder |
| CI | [.github/workflows/bench.yml](../.github/workflows/bench.yml): on an ARM64 runner, on a push to a `bench/` branch, at 20000, 80000 and 1000000 validators |
| State | The first mainnet fulu `epoch_processing-rewards_and_penalties` pre-state of the vectors, its validators, balances, participations and inactivity scores repeated up to `VALIDATORS` |
| Timed | A copy of the state; ssz_hash_tree_root; lantern_state_root with a `StateCache` of the validators, empty and then unchanged; process_slots of one slot with the cache; get_beacon_committee with no cache and with a `CommitteeCache`, empty and filled; is_valid_indexed_attestation of 488 and of 31232 keys, with no cache and with a `PubkeyCache`, empty and filled; each epoch step and process_epoch; process_slots of a copy to the next epoch's first slot, with the cache; then, at the 10th slot of that epoch, a full signed block (8 attestations of every committee of a slot, a sync aggregate of the whole committee, the expected withdrawals): verify_block_signature, process_block with the committee and public key caches empty and then filled, lantern_state_root after it with the cache, get_total_active_balance, get_attesting_indices of one attestation, process_attestation and process_sync_aggregate alone, and process_sync_aggregate with each member's key found only among the last validators |
