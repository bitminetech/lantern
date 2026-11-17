/*
 * lantern core for x86-64 (System V AMD64 psABI). AT&T syntax: the functions that read no fork's layouts, one object
 * (include/forks.inc). Requirements: docs/reference/. Layouts: include/.
 */
.set ISA_X86_64, 1
.include "ssz.inc"
.include "crypto.inc"
.include "bls12381.inc"
.include "kzg.inc"
.include "preset.inc"
.include "lantern.inc"
.include "platform.inc"
.include "snappy.inc"
.include "reqresp_protocols.inc"
.include "engine_text.inc"
.include "gossip_topics.inc"
.include "macros.s"

/* ---------------------------------------------------------------- Functions */

.include "memory.s"
.include "seen_find.s"
.include "store.s"
.include "seen.s"
.include "topics.s"
.include "reqresp.s"
.include "engine.s"
