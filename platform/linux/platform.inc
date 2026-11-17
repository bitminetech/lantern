/*
 * Linux platform metadata for core and shell assembly (ELF).
 * Core files call these macros so that one instruction sequence serves every OS.
 */

/* Mark the stack as not executable. */
.section .note.GNU-stack, "", %progbits

/* A global function. */
.macro FUNCTION name
    .text
    .globl \name
    .type \name, %function
    .p2align 4
\name:
    .cfi_startproc
.endm

.macro END_FUNCTION name
    .cfi_endproc
    .size \name, . - \name
.endm

/* Unwind metadata for frame changes (DWARF CFI in .eh_frame). */
.macro UNWIND_ALLOC bytes
    .cfi_adjust_cfa_offset \bytes
.endm

.macro UNWIND_FREE bytes
    .cfi_adjust_cfa_offset -(\bytes)
.endm

.macro UNWIND_PUSH reg
    .cfi_adjust_cfa_offset 8
    .cfi_rel_offset \reg, 0
.endm

.macro UNWIND_POP reg
    .cfi_adjust_cfa_offset -8
    .cfi_restore \reg
.endm

.macro UNWIND_SAVE reg, offset
    .cfi_rel_offset \reg, \offset
.endm

.macro UNWIND_RESTORE reg
    .cfi_restore \reg
.endm

.macro UNWIND_END_PROLOGUE
.endm

.macro UNWIND_BEGIN_EPILOGUE
.endm

.macro UNWIND_END_EPILOGUE
.endm

/* A local function: unwind data, no export. */
.macro LOCAL_FUNCTION name
    .text
    .type \name, %function
    .p2align 4
\name:
    .cfi_startproc
.endm

/* A global function label at this address, for an export that shares its code with a local label. */
.macro GLOBAL_LABEL name
    .globl \name
    .type \name, %function
\name:
.endm
.macro GLOBAL_LABEL_END name
    .size \name, . - \name
.endm

/* Call a global function: of this library, or of a dependency. */
.macro CALL_GLOBAL name
.ifdef ISA_ARM64
    bl      \name
.else
    call    \name
.endif
.endm

/* ARM64 frame records and saved register pairs (DWARF CFI). */
.macro UNWIND_SAVE_FPLR_X bytes
    .cfi_def_cfa_offset \bytes
    .cfi_offset x29, -(\bytes)
    .cfi_offset x30, 8 - (\bytes)
.endm

.macro UNWIND_SET_FP
.endm

.macro UNWIND_SAVE_REGP first, second, offset, bytes
    .cfi_offset \first, \offset - (\bytes)
    .cfi_offset \second, \offset + 8 - (\bytes)
.endm

.macro UNWIND_RESTORE_REGP first, second, offset
    .cfi_restore \first
    .cfi_restore \second
.endm

.macro UNWIND_RESTORE_FPLR_X bytes
    .cfi_restore x29
    .cfi_restore x30
    .cfi_def_cfa_offset 0
.endm

/* lantern: read only data, and a global data label. */
.macro RODATA
    .section .rodata
.endm

.macro DATA_GLOBAL name
    .globl \name
    .type \name, %object
\name:
.endm

/* lantern, ARM64: reg = address of label, in this object or another. */
.ifdef ISA_ARM64
.macro ADDRESS reg, label
    adrp    \reg, \label
    add     \reg, \reg, :lo12:\label
.endm
.endif
