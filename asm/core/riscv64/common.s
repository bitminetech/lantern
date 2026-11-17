/*
 * lantern core for RISC-V (RV64GC, LP64D): the functions that read no fork's layouts, one object
 * (include/forks.inc). Requirements: docs/reference/. Layouts: include/.
 */
.set ISA_RISCV64, 1
.include "ssz.inc"
.include "crypto.inc"
.include "bls12381.inc"
.include "kzg.inc"
.include "preset.inc"
.include "lantern.inc"
.include "platform.inc"
.include "macros.s"

/* ---------------------------------------------------------------- Functions */

.include "memory.s"
.include "seen_find.s"
.include "store.s"
.include "seen.s"
