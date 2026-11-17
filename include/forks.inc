/*
 * Forks of lantern's core objects. The build assembles asm/core/<ISA>/lantern.s once
 * for each fork, with --defsym FORK=<FORK_*>; asm/core/<ISA>/common.s holds the
 * functions that read no fork's layouts, once.
 *
 * A spec function of a fork's object has two names: the local label lantern_<name>,
 * which the object's own calls use, and the export lantern_<fork>_<name>. The spec
 * defines many functions once for each fork, so the fork is part of the name.
 */

.set FORK_PHASE0, 0
.set FORK_ALTAIR, 1
.set FORK_BELLATRIX, 2
.set FORK_CAPELLA, 3
.set FORK_DENEB, 4
.set FORK_ELECTRA, 5
.set FORK_FULU, 6

.ifndef FORK
.error "assemble lantern.s with --defsym FORK=<FORK_*>"
.endif
.if FORK != FORK_FULU
.error "lantern's core has only the fulu object yet"
.endif

/* The export lantern_<fork>_<name> of this object, at this address. */
.macro FORK_LABEL name
.if FORK == FORK_FULU
    GLOBAL_LABEL lantern_fulu_\name
.endif
.endm
.macro FORK_LABEL_END name
.if FORK == FORK_FULU
    GLOBAL_LABEL_END lantern_fulu_\name
.endif
.endm

/* A spec function of this fork's object: lantern_<name> inside it, lantern_<fork>_<name> outside. */
.macro SPEC_FUNCTION name
    .text
    .p2align 4                              /* the export first: Mach-O allows no public label inside .cfi_startproc */
    FORK_LABEL \name
    LOCAL_FUNCTION lantern_\name
.endm
.macro SPEC_LEAF name
    SPEC_FUNCTION \name
    UNWIND_END_PROLOGUE
.endm
.macro SPEC_END name
    FORK_LABEL_END \name
    END_FUNCTION lantern_\name
.endm

/* Exported data of this fork's object: lantern_<fork>_<name>. */
.macro FORK_DATA name
.if FORK == FORK_FULU
    DATA_GLOBAL lantern_fulu_\name
.endif
.endm
