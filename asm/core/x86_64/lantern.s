/*
 * lantern core for x86-64 (System V AMD64 psABI). AT&T syntax.
 * One object for each fork: the build assembles this file with --defsym FORK=<FORK_*>
 * (include/forks.inc). It includes every core module whose code reads a fork's layouts.
 * Requirements: docs/reference/. Layouts: include/.
 *
 * v1: follows the steps and function calls of consensus-specs v1.7.0-beta.4.
 * Every function follows the System V ABI: pointer arguments, status in rax.
 * Baseline x86-64 instructions only.
 */
.set ISA_X86_64, 1
.include "ssz.inc"
.include "crypto.inc"
.include "bls12381.inc"
.include "kzg.inc"
.include "preset.inc"
.include "lantern.inc"
.include "forks.inc"
.include "ssz_types.inc"
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
/* Fork choice and networking are in the fulu object so far. */
.if FORK == FORK_FULU
.include "forkchoice.s"
.include "seen_find.s"
.include "networking.s"
.endif

/* ---------------------------------------------------------------- Read only data */

    RODATA
.include "descriptors.inc"
