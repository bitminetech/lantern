# Vector runner

## Run

```bash
build/linux-x86_64/runner-minimal-fulu ~/.cache/lantern/vectors minimal-fulu-operations-attestation.bin
```

- Arguments: the vector folder, then the files to run. Files of another preset or fork are skipped.
- A file of a kind the runner has no handler for prints a `SKIP` line.
- The status is 0 only when every case of every file passes.
- `tests/runner/run.sh RUNNER_DIR VECTOR_DIR [FILE ...]` runs the runners of one target, one process for each runner and file, as many at once as the machine has cores. Each file goes to the runners of its preset and fork. `QEMU` sets the command that runs them, `JOBS` the processes at once. `run.ps1` does the same on Windows.
- `tests/runner/docker.sh` builds every target in Docker and runs the three Linux ISAs; `tests/runner/macos.sh` runs the macOS runners. Both call `run.sh`.

## Files

| File | What it holds |
|---|---|
| `runner.c` | Reads the case files of tests/generator/, calls lantern for each case and compares the results |
| `bls_off.c` | Stand-ins for the three BLS verify functions of asm-crypto that return valid, for `runner-<preset>-bls-off` |
| `abi_<ISA>.s` | `abi_call`: calls a lantern function and checks that it keeps the registers and stack of the core ABI |
| `run.sh`, `run.ps1` | Run the runners of one target on every core, and merge their results |
| `docker.sh`, `macos.sh` | Build and run scripts |

## Runners

| Runner | Cases |
|---|---|
| `runner-<preset>-<fork>` | Every case of the fork whose `bls_setting` is 0 or 1 |
| `runner-<preset>-<fork>-bls-off` | The cases of the fork with `bls_setting` 2, linked with `bls_off.c` |

- Each runner calls the `lantern_<fork>_*` functions of its fork, built with `-DFORK=<number> -DFORK_NAME=<fork>` (include/forks.inc).
- Every runner runs the `descriptors` and `ssz_static` files of its fork.
- Every runner also runs the state transition files of its fork: epoch processing, operations, sanity, finality, random, rewards and shuffling.
- The runners of altair to fulu also run `fork` (the upgrade of a state of the fork before) and `transition` (blocks across the fork epoch: the blocks up to `fork_block` with the fork before, process_slots of the fork before to the fork slot, the upgrade, then the other blocks; a block on the fork slot gets its signature check, process_block and state root check, since its slots ran before the upgrade).
- The phase0 runners also run `genesis` (initialization and validity).
- The runners of altair to fulu also run fork choice and its compliance cases; those of bellatrix to fulu also run sync.
- Every runner runs the gossip validation files of its fork (`networking`) lantern's p2p helper files (`p2p`) and lantern's req/resp encoding files (`reqresp`); the fulu runners also run custody. The runners of deneb to fulu run `merkle_proof`: the proof of a blob commitment for deneb and electra, of the commitment list for fulu.

## Buffers

| Buffer | How the runner prepares it |
|---|---|
| Scratch | One buffer of `SCRATCH_BYTES` (4 MiB), refilled with `0xA5` before every call, so a call that reads scratch it did not write gives a wrong result |
| Outputs and states | Allocated at the size each function asks for, filled with `0xA5`, with 64 guard bytes after them that must stay unchanged |

- `SCRATCH_BYTES` is more than any call of the vectors needs. The largest need is a KZG check of a column: 2 MiB of asm-crypto scratch plus about 10 KB per blob. Refilling the scratch is most of the runner's own time, so it is not larger.
- `-DSCRATCH_BYTES=<bytes>` sets another size, for example when new vectors need more.

## Call check

`abi_call(ctx)` sets each register the callee must keep to a known value, paints `paint` bytes of stack below the call, calls `fn`, then records the status, a mask of the kept state that changed, and the stack the call used.

### Layout of ctx

| Offset | Field | Meaning |
|---|---|---|
| 0 | `fn` | The function |
| 8 | `arg[5]` | Arguments 1 to 5 |
| 48 | `paint` | Bytes of stack to paint |
| 56 | `status` | The returned status |
| 64 | `fault` | Mask of kept state that changed |
| 72 | `stack` | Bytes of stack the call used |
| 80 | `scratch[4]` | `abi_call`'s own: the stack pointer and the control words |
| 112 | `arg5` | Argument 6 |
| 120 | `more[5]` | Arguments 7 to 11 |

- Arguments past those in registers go on the stack as the core ABI says: 7 to 11 on x86-64, 9 to 11 on ARM64 and RISC-V.

### Bits of fault

| ISA | Bit | Kept state |
|---|---|---|
| x86-64 | 0 to 5 | rbx, rbp, r12, r13, r14, r15 |
| x86-64 | 60 | x87 control word |
| x86-64 | 61 | MXCSR control bits |
| x86-64 | 62 | Direction flag set |
| ARM64 | 0 to 10 | x19 to x29 |
| ARM64 | 11 to 18 | d8 to d15 |
| ARM64 | 61 | FPCR |
| RISC-V | 0 to 11 | s0 to s11 |
| RISC-V | 12 to 23 | fs0 to fs11 |
| RISC-V | 24, 25 | gp, tp |
| All | 63 | The stack pointer |
