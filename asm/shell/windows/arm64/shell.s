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
.set OS_GENERIC_WRITE, 0x40000000           /* winnt.h */
.set OS_FILE_SHARE_ALL, 7                   /* FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, winnt.h */
.set OS_OPEN_ALWAYS, 4                      /* fileapi.h */
.set OS_FILE_BEGIN, 0                       /* fileapi.h */
.set OS_FILE_END, 2
.set OS_PAGE_READONLY, 2                    /* winnt.h */
.set OS_FILE_MAP_READ, 4                    /* memoryapi.h */
.set OS_MOVEFILE_REPLACE_THROUGH, 9         /* MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH, winbase.h */
.set OS_ERROR_WRITE_FAULT, 29               /* winerror.h */
.set OS_ERROR_INVALID_PARAMETER, 87

/* x0 = GetLastError, never 0. */
.macro OS_LAST_ERROR
    CALL_GLOBAL GetLastError
    mov     w0, w0
    cmp     x0, #0
    csinc   x0, x0, xzr, ne
.endm

/* x22 = new memory of \size bytes for paths in UTF-16; to \fail with x0 the error. */
.macro WIDE_ALLOC size, fail
    mov     x0, #0
    MOVQ    x1, (\size)
    mov     w2, #OS_MEM_COMMIT_RESERVE
    mov     w3, #OS_PAGE_READWRITE
    CALL_GLOBAL VirtualAlloc
    mov     x22, x0
    cbnz    x0, 86f
    OS_LAST_ERROR
    b       \fail
86:
.endm

/* The memory at x22 goes back; x0 kept, through x24. */
.macro WIDE_FREE
    mov     x24, x0
    mov     x0, x22
    mov     x1, #0
    mov     w2, #OS_MEM_RELEASE
    CALL_GLOBAL VirtualFree
    mov     x0, x24
.endm

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

/*
 * (path at x0, to at x1): the path ByteList in UTF-16 with a zero after it, at most
 * SHELL_WIDE_BYTES; x0 0, or the error. x19 the path, x20 to.
 */
LOCAL_FUNCTION lantern_shell_wide
    ENTER 0
    mov     x19, x0
    mov     x20, x1
    ldr     x3, [x19, #16]
    mov     x0, #OS_ERROR_FILENAME_EXCED_RANGE
    cmp     x3, #SHELL_PATH_MAX
    b.hi    9f
    mov     w0, #OS_CP_UTF8
    mov     w1, #0
    ldr     x2, [x19, #8]
    add     x2, x19, x2
    mov     x4, x20
    mov     w5, #(SHELL_WIDE_BYTES / 2 - 1)
    CALL_GLOBAL MultiByteToWideChar
    cbz     w0, 8f
    strh    wzr, [x20, w0, uxtw #1]
    mov     x0, #0
    b       9f
8:  OS_LAST_ERROR
9:  LEAVE 0
END_FUNCTION lantern_shell_wide

/*
 * (path, mode, result): docs/reference/shell.md. x19 result, x20 the path, x22 the wide path,
 * x23 the access, x21 the disposition.
 */
FUNCTION lantern_shell_open
    ENTER 0
    mov     x19, x2
    stp     xzr, xzr, [x19]
    mov     x20, x0
    ldr     x9, [x1]
    cmp     x9, #2
    b.hi    92f
    mov     w23, #OS_GENERIC_READ
    mov     w21, #OS_OPEN_EXISTING
    cbz     x9, 1f
    mov     w23, #OS_GENERIC_WRITE
    mov     w21, #OS_OPEN_ALWAYS
    cmp     x9, #1
    b.eq    1f
    mov     w23, #(OS_GENERIC_READ | OS_GENERIC_WRITE)
1:  WIDE_ALLOC SHELL_WIDE_BYTES, 90f
    mov     x0, x20
    mov     x1, x22
    bl      lantern_shell_wide
    cbnz    x0, 85f
    mov     x0, x22
    mov     w1, w23
    mov     w2, #OS_FILE_SHARE_ALL
    mov     x3, #0
    mov     w4, w21
    mov     w5, #OS_FILE_ATTRIBUTE_NORMAL
    mov     x6, #0
    CALL_GLOBAL CreateFileW
    cmn     x0, #1
    b.eq    84f
    str     x0, [x19, #8]
    mov     x0, #0
    b       85f
92: mov     x0, #OS_ERROR_INVALID_PARAMETER
    b       90f
84: OS_LAST_ERROR
85: WIDE_FREE
90: str     x0, [x19]
    mov     x0, #LANTERN_OK
    LEAVE 0
END_FUNCTION lantern_shell_open

/*
 * (file, bytes, result): docs/reference/shell.md. x19 result, x20 the file, x21 the bytes, x22
 * their count, x23 written. Locals: L the bytes WriteFile wrote.
 */
FUNCTION lantern_shell_append
    ENTER 16
    mov     x19, x2
    stp     xzr, xzr, [x19]
    ldr     x20, [x0]
    ldr     x21, [x1, #8]
    add     x21, x1, x21
    ldr     x22, [x1, #16]
    mov     x23, #0
    mov     x0, x20                         /* the end */
    mov     x1, #0
    mov     x2, #0
    mov     w3, #OS_FILE_END
    CALL_GLOBAL SetFilePointerEx
    cbz     w0, 80f
1:  cmp     x23, x22
    b.hs    9f
    mov     x0, x20
    add     x1, x21, x23
    sub     x2, x22, x23
    mov     x9, #SHELL_IO_MAX
    cmp     x2, x9
    csel    x2, x2, x9, ls
    str     wzr, [sp, #L]
    add     x3, sp, #L
    mov     x4, #0
    CALL_GLOBAL WriteFile
    cbz     w0, 80f
    ldr     w0, [sp, #L]
    cbz     w0, 7f
    add     x23, x23, x0
    b       1b
7:  mov     x0, #OS_ERROR_WRITE_FAULT       /* no progress */
    b       8f
80: OS_LAST_ERROR
8:  str     x0, [x19]
9:  str     x23, [x19, #8]
    mov     x0, #LANTERN_OK
    LEAVE 16
END_FUNCTION lantern_shell_append

/*
 * (file, offset, bytes, result): docs/reference/shell.md. x19 result, x20 the file, x21 the bytes, x22
 * their count, x23 written, x24 the offset. Locals: L the bytes WriteFile wrote, L+8 an OVERLAPPED
 * (32 bytes) with the offset at L+24.
 */
FUNCTION lantern_shell_write_at
    ENTER 48
    mov     x19, x3
    stp     xzr, xzr, [x19]
    ldr     x20, [x0]
    ldr     x24, [x1]
    ldr     x21, [x2, #8]
    add     x21, x2, x21
    ldr     x22, [x2, #16]
    mov     x23, #0
1:  cmp     x23, x22
    b.hs    9f
    mov     x0, x20
    add     x1, x21, x23
    sub     x2, x22, x23
    mov     x9, #SHELL_IO_MAX
    cmp     x2, x9
    csel    x2, x2, x9, ls
    str     wzr, [sp, #L]
    add     x3, sp, #L
    stp     xzr, xzr, [sp, #(L + 8)]
    add     x9, x24, x23                    /* Offset and OffsetHigh: the offset + the bytes written */
    stp     x9, xzr, [sp, #(L + 24)]
    add     x4, sp, #(L + 8)
    CALL_GLOBAL WriteFile
    cbz     w0, 80f
    ldr     w0, [sp, #L]
    cbz     w0, 7f
    add     x23, x23, x0
    b       1b
7:  mov     x0, #OS_ERROR_WRITE_FAULT       /* no progress */
    b       8f
80: OS_LAST_ERROR
8:  str     x0, [x19]
9:  str     x23, [x19, #8]
    mov     x0, #LANTERN_OK
    LEAVE 48
END_FUNCTION lantern_shell_write_at

/* (file, result): docs/reference/shell.md. x19 result. */
FUNCTION lantern_shell_sync
    ENTER 0
    mov     x19, x1
    stp     xzr, xzr, [x19]
    ldr     x0, [x0]
    CALL_GLOBAL FlushFileBuffers
    cbnz    w0, 9f
    OS_LAST_ERROR
    str     x0, [x19]
9:  mov     x0, #LANTERN_OK
    LEAVE 0
END_FUNCTION lantern_shell_sync

/* (file, size, result): docs/reference/shell.md. x19 result, x20 the file. */
FUNCTION lantern_shell_truncate
    ENTER 0
    mov     x19, x2
    stp     xzr, xzr, [x19]
    ldr     x20, [x0]
    mov     x0, x20
    ldr     x1, [x1]
    mov     x2, #0
    mov     w3, #OS_FILE_BEGIN
    CALL_GLOBAL SetFilePointerEx
    cbz     w0, 8f
    mov     x0, x20
    CALL_GLOBAL SetEndOfFile
    cbnz    w0, 9f
8:  OS_LAST_ERROR
    str     x0, [x19]
9:  mov     x0, #LANTERN_OK
    LEAVE 0
END_FUNCTION lantern_shell_truncate

/* (file): docs/reference/shell.md. */
FUNCTION lantern_shell_close
    ENTER 0
    ldr     x0, [x0]
    CALL_GLOBAL CloseHandle
    mov     x0, #LANTERN_OK
    LEAVE 0
END_FUNCTION lantern_shell_close

/*
 * (path, result): docs/reference/shell.md. x19 result, x20 the path then the file, x22 the wide
 * path, x21 the mapping or 0, x23 the size, x25 an error. Locals: L the size.
 */
FUNCTION lantern_shell_map_file
    ENTER 16
    mov     x19, x1
    stp     xzr, xzr, [x19]
    stp     xzr, xzr, [x19, #16]
    mov     x20, x0
    WIDE_ALLOC SHELL_WIDE_BYTES, 90f
    mov     x0, x20
    mov     x1, x22
    bl      lantern_shell_wide
    cbnz    x0, 85f
    mov     x0, x22                         /* open it */
    mov     w1, #OS_GENERIC_READ
    mov     w2, #OS_FILE_SHARE_ALL
    mov     x3, #0
    mov     w4, #OS_OPEN_EXISTING
    mov     w5, #OS_FILE_ATTRIBUTE_NORMAL
    mov     x6, #0
    CALL_GLOBAL CreateFileW
    cmn     x0, #1
    b.eq    84f
    mov     x20, x0
    WIDE_FREE
    mov     x21, #0
    mov     x25, #0
    mov     x0, x20                         /* its size */
    add     x1, sp, #L
    CALL_GLOBAL GetFileSizeEx
    cbz     w0, 80f
    ldr     x23, [sp, #L]
    cbz     x23, 82f                        /* no bytes: address 0 */
    mov     x0, x20
    mov     x1, #0
    mov     w2, #OS_PAGE_READONLY
    mov     w3, #0
    mov     w4, #0
    mov     x5, #0
    CALL_GLOBAL CreateFileMappingW
    cbz     x0, 80f
    mov     x21, x0
    mov     w1, #OS_FILE_MAP_READ
    mov     w2, #0
    mov     w3, #0
    mov     x4, #0
    CALL_GLOBAL MapViewOfFile
    cbz     x0, 80f
    str     x0, [x19, #8]
    stp     x23, x23, [x19, #16]
    b       82f
80: OS_LAST_ERROR
    mov     x25, x0
82: cbz     x21, 83f                        /* the handles close */
    mov     x0, x21
    CALL_GLOBAL CloseHandle
83: mov     x0, x20
    CALL_GLOBAL CloseHandle
    str     x25, [x19]
    b       99f
84: OS_LAST_ERROR
85: WIDE_FREE
90: str     x0, [x19]
99: mov     x0, #LANTERN_OK
    LEAVE 16
END_FUNCTION lantern_shell_map_file

/* (address, size): docs/reference/shell.md. */
FUNCTION lantern_shell_unmap_file
    ENTER 0
    ldr     x0, [x0]
    CALL_GLOBAL UnmapViewOfFile
    mov     x0, #LANTERN_OK
    LEAVE 0
END_FUNCTION lantern_shell_unmap_file

/* (path, result): docs/reference/shell.md. x19 result, x20 the path, x22 the wide path. */
FUNCTION lantern_shell_remove
    ENTER 0
    mov     x19, x1
    stp     xzr, xzr, [x19]
    mov     x20, x0
    WIDE_ALLOC SHELL_WIDE_BYTES, 90f
    mov     x0, x20
    mov     x1, x22
    bl      lantern_shell_wide
    cbnz    x0, 85f
    mov     x0, x22
    CALL_GLOBAL DeleteFileW
    cbz     w0, 84f
    mov     x0, #0
    b       85f
84: OS_LAST_ERROR
85: WIDE_FREE
90: str     x0, [x19]
    mov     x0, #LANTERN_OK
    LEAVE 0
END_FUNCTION lantern_shell_remove

/* (from, to, result): docs/reference/shell.md. x19 result, x20 from, x21 to, x22 the wide paths: from, then to. */
FUNCTION lantern_shell_rename
    ENTER 0
    mov     x19, x2
    stp     xzr, xzr, [x19]
    mov     x20, x0
    mov     x21, x1
    WIDE_ALLOC (2 * SHELL_WIDE_BYTES), 90f
    mov     x0, x20
    mov     x1, x22
    bl      lantern_shell_wide
    cbnz    x0, 85f
    mov     x0, x21
    add     x1, x22, #SHELL_WIDE_BYTES
    bl      lantern_shell_wide
    cbnz    x0, 85f
    mov     x0, x22
    add     x1, x22, #SHELL_WIDE_BYTES
    mov     w2, #OS_MOVEFILE_REPLACE_THROUGH
    CALL_GLOBAL MoveFileExW
    cbz     w0, 84f
    mov     x0, #0
    b       85f
84: OS_LAST_ERROR
85: WIDE_FREE
90: str     x0, [x19]
    mov     x0, #LANTERN_OK
    LEAVE 0
END_FUNCTION lantern_shell_rename

/* (path, result): docs/reference/shell.md. x19 result, x20 the path, x22 the wide path. */
FUNCTION lantern_shell_mkdir
    ENTER 0
    mov     x19, x1
    stp     xzr, xzr, [x19]
    mov     x20, x0
    WIDE_ALLOC SHELL_WIDE_BYTES, 90f
    mov     x0, x20
    mov     x1, x22
    bl      lantern_shell_wide
    cbnz    x0, 85f
    mov     x0, x22
    mov     x1, #0
    CALL_GLOBAL CreateDirectoryW
    cbz     w0, 84f
    mov     x0, #0
    b       85f
84: OS_LAST_ERROR
85: WIDE_FREE
90: str     x0, [x19]
    mov     x0, #LANTERN_OK
    LEAVE 0
END_FUNCTION lantern_shell_mkdir

/* (path, result): docs/reference/shell.md. NTFS journals directory changes: no call. */
FUNCTION lantern_shell_sync_dir
    UNWIND_END_PROLOGUE
    stp     xzr, xzr, [x1]
    mov     x0, #LANTERN_OK
    ret
END_FUNCTION lantern_shell_sync_dir

/*
 * (out): docs/reference/shell.md. x19 out. Locals: L the four FILETIMEs of GetProcessTimes, L+32
 * PROCESS_MEMORY_COUNTERS (72 bytes).
 */
FUNCTION lantern_shell_process
    ENTER 112
    mov     x19, x0
    mov     x0, #-1                         /* GetProcessTimes(GetCurrentProcess(), ...) */
    add     x1, sp, #L
    add     x2, sp, #(L + 8)
    add     x3, sp, #(L + 16)
    add     x4, sp, #(L + 24)
    CALL_GLOBAL GetProcessTimes
    ldp     x9, x10, [sp, #(L + 16)]        /* kernel and user time, in 100 ns */
    add     x9, x9, x10
    mov     x10, #10
    udiv    x9, x9, x10
    str     x9, [x19]
    mov     w9, #72                         /* K32GetProcessMemoryInfo: PeakWorkingSetSize */
    str     w9, [sp, #(L + 32)]
    mov     x0, #-1
    add     x1, sp, #(L + 32)
    mov     x2, #72
    CALL_GLOBAL K32GetProcessMemoryInfo
    ldr     x9, [sp, #(L + 40)]
    str     x9, [x19, #8]
    str     xzr, [x19, #16]
    mov     x0, #LANTERN_OK
    LEAVE 112
END_FUNCTION lantern_shell_process
