/*
 * lantern core for RISC-V (RV64GC, LP64D).
 * One object for each fork: the build assembles this file with --defsym FORK=<FORK_*>
 * (include/forks.inc). It includes every core module whose code reads a fork's layouts.
 * Requirements: docs/reference/. Layouts: include/.
 *
 * v1: follows the steps and function calls of consensus-specs v1.7.0-beta.4.
 * Every function follows the RISC-V psABI: pointer arguments, status in a0.
 * gp and tp are never used.
 */
.set ISA_RISCV64, 1
.include "ssz.inc"
.include "crypto.inc"
.include "bls12381.inc"
.include "kzg.inc"
.include "preset.inc"
.include "lantern.inc"
.include "forks.inc"
.include "ssz_types.inc"
.if FORK > FORK_PHASE0
SSZ_NAMES PRE_                      /* the layouts of the fork before, for upgrade_to_<fork> */
.set TYPES_FORK, FORK - 1
.include "types.inc"
.endif
SSZ_NAMES
.set TYPES_FORK, FORK
.include "types.inc"
.include "platform.inc"
.include "macros.s"

/* Powers of two that the core divides by with shifts and masks. */
SSZ_DEPTH LOG2_SLOTS_PER_EPOCH, SLOTS_PER_EPOCH
.if (1 << LOG2_SLOTS_PER_EPOCH) != SLOTS_PER_EPOCH
.error "SLOTS_PER_EPOCH is not a power of two"
.endif
.if (SLOTS_PER_HISTORICAL_ROOT & (SLOTS_PER_HISTORICAL_ROOT - 1)) || (EPOCHS_PER_HISTORICAL_VECTOR & (EPOCHS_PER_HISTORICAL_VECTOR - 1)) || (EPOCHS_PER_SLASHINGS_VECTOR & (EPOCHS_PER_SLASHINGS_VECTOR - 1))
.error "a history length is not a power of two"
.endif
.if Validator__mem != 128
.error "the code indexes validators with a shift by 7"
.endif

/* ---------------------------------------------------------------- Functions */

.include "memory.s"
.include "helpers.s"
.include "state.s"
.include "shuffle.s"
.include "deposits.s"
.if FORK >= FORK_ALTAIR
.include "sync.s"
.endif
.if FORK == FORK_PHASE0
.include "pending.s"
.endif
.include "epoch.s"
.include "block.s"
.if FORK >= FORK_CAPELLA
.include "withdrawals.s"
.endif
.include "payload.s"
.include "requests.s"
.include "attestation.s"
.include "slashing.s"
.if FORK >= FORK_ALTAIR
.include "syncagg.s"
.endif
.include "transition.s"
.if FORK == FORK_PHASE0
.include "genesis.s"
.else
.include "upgrade.s"
.endif
.include "forkchoice.s"
.include "seen_find.s"
.include "networking.s"
.include "p2p.s"

/* ---------------------------------------------------------------- Read only data */

    RODATA
.include "descriptors.inc"
