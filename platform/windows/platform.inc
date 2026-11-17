/*
 * Windows platform metadata for core and shell assembly (PE/COFF).
 * Core files call these macros so that one instruction sequence serves every OS.
 * Each core file sets ISA_X86_64 or ISA_ARM64 before it includes this file.
 */

/* A global function, with an SEH unwind record. */
.macro FUNCTION name
    .text
    .globl \name
    .def \name
    .scl 2
    .type 32
    .endef
    .p2align 4
\name:
    .seh_proc \name
.endm

.macro END_FUNCTION name
    .seh_endproc
.endm

/* Unwind metadata for frame changes (SEH unwind codes in .pdata and .xdata). */
.macro UNWIND_ALLOC bytes
    .seh_stackalloc \bytes
.endm

.macro UNWIND_PUSH reg
    .seh_pushreg \reg
.endm

.macro UNWIND_POP reg
.endm

.macro UNWIND_END_PROLOGUE
    .seh_endprologue
.endm

/* ARM64 SEH describes each epilogue. x64 SEH reads a canonical epilogue from the code. */
.macro UNWIND_BEGIN_EPILOGUE
.ifdef ISA_ARM64
    .seh_startepilogue
.endif
.endm

.macro UNWIND_FREE bytes
.ifdef ISA_ARM64
    .seh_stackalloc \bytes
.endif
.endm

.macro UNWIND_END_EPILOGUE
.ifdef ISA_ARM64
    .seh_endepilogue
.endif
.endm

/* A local function: an SEH unwind record, no export. */
.macro LOCAL_FUNCTION name
    .text
    .def \name
    .scl 3
    .type 32
    .endef
    .p2align 4
\name:
    .seh_proc \name
.endm

/* A global function label at this address, for an export that shares its code with a local label. */
.macro GLOBAL_LABEL name
    .globl \name
    .def \name
    .scl 2
    .type 32
    .endef
\name:
.endm
.macro GLOBAL_LABEL_END name
.endm

/* Call a global function: of this library, or of a dependency. */
.macro CALL_GLOBAL name
.ifdef ISA_ARM64
    bl      \name
.else
    call    \name
.endif
.endm

/* ARM64 frame records and saved register pairs (SEH unwind codes). */
.macro UNWIND_SAVE_FPLR_X bytes
    .seh_save_fplr_x \bytes
.endm

.macro UNWIND_SET_FP
    .seh_set_fp
.endm

.macro UNWIND_SAVE_REGP first, second, offset, bytes
    .seh_save_regp \first, \offset
.endm

.macro UNWIND_RESTORE_REGP first, second, offset
    .seh_save_regp \first, \offset
.endm

.macro UNWIND_RESTORE_FPLR_X bytes
    .seh_save_fplr_x \bytes
.endm

/* lantern: read only data, and a global data label. */
.macro RODATA
    .section .rdata, "dr"
.endm

.macro DATA_GLOBAL name
    .globl \name
\name:
.endm

/* lantern, ARM64: reg = address of label, in this object or another. */
.ifdef ISA_ARM64
.macro ADDRESS reg, label
    adrp    \reg, \label
    add     \reg, \reg, :lo12:\label
.endm
.endif
