/*
 * The shell of the lantern binary for Windows on ARM64: memory, files, the log and the clock,
 * through kernel32. Requirements: docs/reference/shell.md.
 *
 * The functions use AAPCS64 like the core, and call the Windows APIs with the Windows ARM64
 * convention, which is AAPCS64 for these calls: arguments in x0 to x7, the result in x0 (an int
 * or a BOOL in w0). x18 belongs to Windows.
 */
.set ISA_ARM64, 1
.include "ssz.inc"
.include "crypto.inc"
.include "bls12381.inc"
.include "kzg.inc"
.include "preset.inc"
.include "lantern.inc"
.include "platform.inc"
.include "macros.s"

/* Windows numbers: the llvm-mingw headers. */
.set OS_MEM_COMMIT_RESERVE, 0x3000          /* MEM_COMMIT | MEM_RESERVE, winnt.h */
.set OS_MEM_RELEASE, 0x8000                 /* winnt.h */
.set OS_PAGE_READWRITE, 4                   /* winnt.h */
.set OS_GENERIC_READ, 0x80000000            /* winnt.h */
.set OS_FILE_SHARE_READ, 1                  /* winnt.h */
.set OS_OPEN_EXISTING, 3                    /* fileapi.h */
.set OS_FILE_ATTRIBUTE_NORMAL, 0x80         /* winnt.h */
.set OS_CP_UTF8, 65001                      /* winnls.h */
.set OS_STD_OUTPUT_HANDLE, -11              /* processenv.h */
.set OS_STD_ERROR_HANDLE, -12
.set OS_ERROR_FILENAME_EXCED_RANGE, 206     /* winerror.h */
.set OS_UNIX_EPOCH, 116444736000000000      /* 100 ns ticks from 1601-01-01 to 1970-01-01 */
.set SHELL_PATH_MAX, 4095
.set SHELL_WIDE_BYTES, 8192                 /* read_file: the path in UTF-16, with a zero after it */
.set SHELL_IO_MAX, 1 << 30                  /* the bytes of one ReadFile or WriteFile */

/* (size, out): docs/reference/shell.md. x19 out. */
FUNCTION lantern_shell_map
    ENTER 0
    mov     x19, x1
    ldr     x1, [x0]
    mov     x0, #0
    mov     w2, #OS_MEM_COMMIT_RESERVE
    mov     w3, #OS_PAGE_READWRITE
    CALL_GLOBAL VirtualAlloc
    str     x0, [x19]
    mov     x0, #LANTERN_OK
    LEAVE 0
END_FUNCTION lantern_shell_map

/* (address, size): docs/reference/shell.md. */
FUNCTION lantern_shell_unmap
    ENTER 0
    ldr     x0, [x0]
    mov     x1, #0
    mov     w2, #OS_MEM_RELEASE
    CALL_GLOBAL VirtualFree
    mov     x0, #LANTERN_OK
    LEAVE 0
END_FUNCTION lantern_shell_unmap

/*
 * (path, result): docs/reference/shell.md. x19 result, x20 the path then the file, x21 the
 * memory, x22 the file's size, x23 the size mapped (24 more), x24 the bytes read or an error.
 * Locals: L the wide path's memory, L+8 a count, L+16 the size.
 */
FUNCTION lantern_shell_read_file
    ENTER 32
    mov     x19, x1
    stp     xzr, xzr, [x19]
    stp     xzr, xzr, [x19, #16]
    mov     x20, x0
    ldr     x9, [x20, #16]
    cmp     x9, #SHELL_PATH_MAX
    b.hi    91f
    mov     x0, #0                          /* the path in UTF-16, with a zero after it */
    mov     x1, #SHELL_WIDE_BYTES
    mov     w2, #OS_MEM_COMMIT_RESERVE
    mov     w3, #OS_PAGE_READWRITE
    CALL_GLOBAL VirtualAlloc
    cbz     x0, 90f
    str     x0, [sp, #L]
    mov     x4, x0
    mov     w0, #OS_CP_UTF8
    mov     w1, #0
    ldr     x2, [x20, #8]
    add     x2, x20, x2
    ldr     x3, [x20, #16]
    mov     w5, #(SHELL_WIDE_BYTES / 2 - 1)
    CALL_GLOBAL MultiByteToWideChar
    cbz     w0, 85f
    ldr     x0, [sp, #L]                    /* open it */
    mov     w1, #OS_GENERIC_READ
    mov     w2, #OS_FILE_SHARE_READ
    mov     x3, #0
    mov     w4, #OS_OPEN_EXISTING
    mov     w5, #OS_FILE_ATTRIBUTE_NORMAL
    mov     x6, #0
    CALL_GLOBAL CreateFileW
    cmn     x0, #1
    b.eq    85f
    mov     x20, x0
    ldr     x0, [sp, #L]
    mov     x1, #0
    mov     w2, #OS_MEM_RELEASE
    CALL_GLOBAL VirtualFree
    mov     x0, x20                         /* its size */
    add     x1, sp, #(L + 16)
    CALL_GLOBAL GetFileSizeEx
    cbz     w0, 80f
    ldr     x22, [sp, #(L + 16)]
    add     x23, x22, #24                   /* a ByteList: 24 bytes, then the file's */
    mov     x0, #0
    mov     x1, x23
    mov     w2, #OS_MEM_COMMIT_RESERVE
    mov     w3, #OS_PAGE_READWRITE
    CALL_GLOBAL VirtualAlloc
    cbz     x0, 80f
    mov     x21, x0
    mov     x2, #24
    stp     x23, x2, [x21]
    str     x22, [x21, #16]
    mov     x24, #0
4:  cmp     x24, x22                        /* every byte */
    b.hs    5f
    mov     x0, x20
    add     x1, x21, x24
    add     x1, x1, #24
    sub     x2, x22, x24
    mov     x9, #SHELL_IO_MAX
    cmp     x2, x9
    csel    x2, x2, x9, ls
    str     wzr, [sp, #(L + 8)]
    add     x3, sp, #(L + 8)
    mov     x4, #0
    CALL_GLOBAL ReadFile
    cbz     w0, 70f
    ldr     w0, [sp, #(L + 8)]
    cbz     w0, 71f
    add     x24, x24, x0
    b       4b
5:  mov     x0, x20
    CALL_GLOBAL CloseHandle
    stp     xzr, x21, [x19]
    stp     x22, x23, [x19, #16]
    b       99f
70: CALL_GLOBAL GetLastError
    mov     w0, w0
    b       72f
71: mov     x0, #1                          /* the file ends before its size: error 1 */
72: mov     x24, x0                         /* the memory goes back */
    mov     x0, x21
    mov     x1, #0
    mov     w2, #OS_MEM_RELEASE
    CALL_GLOBAL VirtualFree
    mov     x0, x24
    b       81f
80: CALL_GLOBAL GetLastError                /* the file closes */
    mov     w0, w0
81: mov     x24, x0
    mov     x0, x20
    CALL_GLOBAL CloseHandle
    mov     x0, x24
    b       92f
85: CALL_GLOBAL GetLastError                /* the wide path's memory goes back */
    mov     w24, w0
    ldr     x0, [sp, #L]
    mov     x1, #0
    mov     w2, #OS_MEM_RELEASE
    CALL_GLOBAL VirtualFree
    mov     x0, x24
    b       92f
90: CALL_GLOBAL GetLastError
    mov     w0, w0
92: cmp     x0, #0                          /* the error, never 0 */
    csinc   x0, x0, xzr, ne
93: str     x0, [x19]
    b       99f
91: mov     x0, #OS_ERROR_FILENAME_EXCED_RANGE
    b       93b
99: mov     x0, #LANTERN_OK
    LEAVE 32
END_FUNCTION lantern_shell_read_file

/*
 * (stream, bytes): docs/reference/shell.md. x19 the handle, x20 the next byte, x21 the bytes
 * left. Locals: L the bytes written.
 */
FUNCTION lantern_shell_write
    ENTER 16
    ldr     x9, [x1, #8]
    add     x20, x1, x9
    ldr     x21, [x1, #16]
    ldr     x9, [x0]
    mov     w0, #OS_STD_OUTPUT_HANDLE
    cmp     x9, #2
    b.ne    1f
    mov     w0, #OS_STD_ERROR_HANDLE
1:  CALL_GLOBAL GetStdHandle
    mov     x19, x0
    cbz     x19, 9f
    cmn     x19, #1
    b.eq    9f
2:  cbz     x21, 9f
    mov     x0, x19
    mov     x1, x20
    mov     x2, x21
    mov     x9, #SHELL_IO_MAX
    cmp     x2, x9
    csel    x2, x2, x9, ls
    str     wzr, [sp, #L]
    add     x3, sp, #L
    mov     x4, #0
    CALL_GLOBAL WriteFile
    cbz     w0, 9f
    ldr     w0, [sp, #L]
    cbz     w0, 9f
    add     x20, x20, x0
    sub     x21, x21, x0
    b       2b
9:  mov     x0, #LANTERN_OK
    LEAVE 16
END_FUNCTION lantern_shell_write

/* (out): docs/reference/shell.md. x19 out. Locals: L a FILETIME. */
FUNCTION lantern_shell_time_ms
    ENTER 16
    mov     x19, x0
    add     x0, sp, #L
    CALL_GLOBAL GetSystemTimePreciseAsFileTime
    ldr     x0, [sp, #L]
    MOVQ    x1, OS_UNIX_EPOCH
    sub     x0, x0, x1
    mov     x1, #10000
    udiv    x0, x0, x1
    str     x0, [x19]
    mov     x0, #LANTERN_OK
    LEAVE 16
END_FUNCTION lantern_shell_time_ms
