/*
 * Forks of lantern's core objects. The build assembles asm/core/<ISA>/lantern.s once
 * for each fork, with --defsym FORK=<FORK_*>; asm/core/<ISA>/common.s holds the
 * functions that read no fork's layouts, once.
 *
 * A spec function of a fork's object has two names: the local label lantern_<name>,
 * which the object's own calls use, and the export lantern_<fork>_<name>. The spec
 * defines many functions once for each fork, so the fork is part of the name.
 */

.include "fork_numbers.inc"

.ifndef FORK
.error "assemble lantern.s with --defsym FORK=<FORK_*>"
.endif
.if FORK < FORK_PHASE0 || FORK > FORK_FULU
.error "FORK is not a fork of lantern"
.endif

/*
 * The preset values that the spec renames at a fork: FORK_<name> is the value this
 * object's fork uses. Needs preset.inc first.
 */
.if FORK >= FORK_BELLATRIX
.set FORK_MIN_SLASHING_PENALTY_QUOTIENT, MIN_SLASHING_PENALTY_QUOTIENT_BELLATRIX
.set FORK_PROPORTIONAL_SLASHING_MULTIPLIER, PROPORTIONAL_SLASHING_MULTIPLIER_BELLATRIX
.set FORK_INACTIVITY_PENALTY_QUOTIENT, INACTIVITY_PENALTY_QUOTIENT_BELLATRIX
.elseif FORK == FORK_ALTAIR
.set FORK_MIN_SLASHING_PENALTY_QUOTIENT, MIN_SLASHING_PENALTY_QUOTIENT_ALTAIR
.set FORK_PROPORTIONAL_SLASHING_MULTIPLIER, PROPORTIONAL_SLASHING_MULTIPLIER_ALTAIR
.set FORK_INACTIVITY_PENALTY_QUOTIENT, INACTIVITY_PENALTY_QUOTIENT_ALTAIR
.else
.set FORK_MIN_SLASHING_PENALTY_QUOTIENT, MIN_SLASHING_PENALTY_QUOTIENT
.set FORK_PROPORTIONAL_SLASHING_MULTIPLIER, PROPORTIONAL_SLASHING_MULTIPLIER
.set FORK_INACTIVITY_PENALTY_QUOTIENT, INACTIVITY_PENALTY_QUOTIENT
.endif
.if FORK >= FORK_ELECTRA
.set FORK_MIN_SLASHING_PENALTY_QUOTIENT, MIN_SLASHING_PENALTY_QUOTIENT_ELECTRA
.set FORK_WHISTLEBLOWER_REWARD_QUOTIENT, WHISTLEBLOWER_REWARD_QUOTIENT_ELECTRA
.else
.set FORK_WHISTLEBLOWER_REWARD_QUOTIENT, WHISTLEBLOWER_REWARD_QUOTIENT
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

/*
 * A spec function that the spec defines from fork first on, which the code of earlier
 * forks also calls: exported from first on, a local label lantern_<name> before it.
 */
.macro SPEC_FUNCTION_FROM first, name
.if FORK >= \first
    SPEC_FUNCTION \name
.else
    LOCAL_FUNCTION lantern_\name
.endif
.endm
.macro SPEC_LEAF_FROM first, name
    SPEC_FUNCTION_FROM \first, \name
    UNWIND_END_PROLOGUE
.endm
.macro SPEC_END_FROM first, name
.if FORK >= \first
    SPEC_END \name
.else
    END_FUNCTION lantern_\name
.endif
.endm

/* Exported data of this fork's object: lantern_<fork>_<name>. */
.macro FORK_DATA name
    FORK_NAMED FORK_DATA_GLOBAL, \name
.endm
