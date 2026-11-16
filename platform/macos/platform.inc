/*
 * macOS platform metadata for core and shell assembly (Mach-O).
 * Core files call these macros so that one instruction sequence serves every OS.
 */

/*
 * A global function. Mach-O adds a leading underscore to symbol names; the
 * second label lets core code call the function by its plain name.
 */
.macro FUNCTION name
    .text
    .globl _\name
    .p2align 4
_\name:
\name:
    .cfi_startproc
.endm

.macro END_FUNCTION name
    .cfi_endproc
.endm

/* Unwind metadata for frame changes (DWARF CFI; the linker makes compact unwind from it). */
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
    .p2align 4
\name:
    .cfi_startproc
.endm

/* Call a global function: of this library, or of a dependency. Mach-O adds a leading underscore. */
.macro CALL_GLOBAL name
.ifdef ISA_ARM64
    bl      _\name
.else
    call    _\name
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

/* lantern: read only data, and a global data label. Mach-O adds a leading underscore. */
.macro RODATA
    .section __TEXT,__const
.endm

.macro DATA_GLOBAL name
    .globl _\name
_\name:
\name:
.endm

/* lantern, ARM64: reg = address of label, in this object or another. */
.ifdef ISA_ARM64
.macro ADDRESS reg, label
    adrp    \reg, \label@PAGE
    add     \reg, \reg, \label@PAGEOFF
.endm
.endif
