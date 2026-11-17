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
.if FORK < FORK_PHASE0 || FORK > FORK_FULU
.error "FORK is not a fork of lantern"
.endif

/* Expands m with the name of this object's fork and the rest of the arguments. */
.macro FORK_NAMED m, args:vararg
.if FORK == FORK_PHASE0
    \m phase0, \args
.elseif FORK == FORK_ALTAIR
    \m altair, \args
.elseif FORK == FORK_BELLATRIX
    \m bellatrix, \args
.elseif FORK == FORK_CAPELLA
    \m capella, \args
.elseif FORK == FORK_DENEB
    \m deneb, \args
.elseif FORK == FORK_ELECTRA
    \m electra, \args
.else
    \m fulu, \args
.endif
.endm

.macro FORK_GLOBAL_LABEL fork, name
    GLOBAL_LABEL lantern_\fork\()_\name
.endm
.macro FORK_GLOBAL_LABEL_END fork, name
    GLOBAL_LABEL_END lantern_\fork\()_\name
.endm
.macro FORK_DATA_GLOBAL fork, name
    DATA_GLOBAL lantern_\fork\()_\name
.endm

/* The export lantern_<fork>_<name> of this object, at this address. */
.macro FORK_LABEL name
    FORK_NAMED FORK_GLOBAL_LABEL, \name
.endm
.macro FORK_LABEL_END name
    FORK_NAMED FORK_GLOBAL_LABEL_END, \name
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
    FORK_NAMED FORK_DATA_GLOBAL, \name
.endm
