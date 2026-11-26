# Shell

Memory, files, the log and the clock.

## Contents

### Functions

- [`lantern_shell_map`](#function-lantern_shell_map): gives zeroed memory.
- [`lantern_shell_unmap`](#function-lantern_shell_unmap): gives memory back.
- [`lantern_shell_read_file`](#function-lantern_shell_read_file): reads a whole file into a new ByteList.
- [`lantern_shell_write`](#function-lantern_shell_write): writes bytes to the standard output or the standard error.
- [`lantern_shell_time_ms`](#function-lantern_shell_time_ms): reads the Unix time in milliseconds.
- [`lantern_shell_open`](#function-lantern_shell_open): opens a file to read, or to append to.
- [`lantern_shell_append`](#function-lantern_shell_append): writes bytes at the end of a file.
- [`lantern_shell_sync`](#function-lantern_shell_sync): makes a file's bytes durable.
- [`lantern_shell_truncate`](#function-lantern_shell_truncate): cuts a file to a size.
- [`lantern_shell_close`](#function-lantern_shell_close): closes a file.
- [`lantern_shell_map_file`](#function-lantern_shell_map_file): maps a whole file to read.
- [`lantern_shell_unmap_file`](#function-lantern_shell_unmap_file): unmaps a mapped file.
- [`lantern_shell_remove`](#function-lantern_shell_remove): deletes a file.
- [`lantern_shell_rename`](#function-lantern_shell_rename): renames a file over another.
- [`lantern_shell_mkdir`](#function-lantern_shell_mkdir): makes a directory.
- [`lantern_shell_sync_dir`](#function-lantern_shell_sync_dir): makes a directory's entries durable.
- [`lantern_shell_process`](#function-lantern_shell_process): reads the process's CPU time, highest resident memory and open file limit.
- [`lantern_shell_wide`](#function-lantern_shell_wide): a path in UTF-16 with a zero after it, for the Windows calls.
- [`main`](#function-main): the entry point of the binary on macOS.
- [`mainCRTStartup`](#function-maincrtstartup): the entry point of the binary on Windows.
- [`_start`](#function-_start): the entry point of the binary on Linux.

### Types

- [`FileOp`](#type-fileop): the outcome of the other file functions.
- [`FileResult`](#type-fileresult): the outcome of `lantern_shell_read_file` and `lantern_shell_map_file`.

## Spec

- Document: ARCHITECTURE.md section 2 (core and shell) and section 7 (operating systems).
- Section: the shell of the lantern binary: memory, files, the log and the clock, for Linux (system calls), macOS (libSystem) and Windows (kernel32). Sockets, the monotonic clock and random bytes come from the shell of asm-libp2p.
- The file functions serve the database of [db.md](db.md): files written once at their end, made durable, mapped to read, renamed into place, and deleted whole.

## The `sha` variant

On x86-64 and ARM64 the binary holds a second copy of the core and of the dependency cores, built with asm-crypto's `asm/core/<ISA>/sha256x.s` in place of `sha256.s`. Each symbol of that copy has the prefix `lx_`. The entry point runs that copy when the CPU has the features below.

| ISA | Extra instructions | Feature check |
|---|---|---|
| x86-64 | SSSE3 and SHA | CPUID leaf 1 ECX bit 9, and leaf 7 subleaf 0 EBX bit 29 |
| ARM64 | FEAT_SHA256 | Linux: bit 6 (`HWCAP_SHA2`) of `AT_HWCAP` (16). macOS: the sysctl `hw.optional.arm.FEAT_SHA256`. Windows: `IsProcessorFeaturePresent(PF_ARM_V8_CRYPTO_INSTRUCTIONS_AVAILABLE)` (30). |

- Proof claims cover only the baseline copy.

## Function `lantern_shell_map`

Gives memory of a size, zeroed, readable and writable.

### Signature

```
lantern_shell_map(size, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `size` | input | u64: 1 or more bytes |
| `out` | output | u64: the address of the memory, or 0 when the OS gave none |

### Returns

- `LANTERN_OK`, always.

### Function does

- Linux: `mmap` of anonymous private memory. macOS: `mmap` of libSystem. Windows: `VirtualAlloc` with MEM_COMMIT and MEM_RESERVE.
- The address is a multiple of 4096.
- Returns `LANTERN_OK` when its result is written, also when the OS call failed; the result then holds the OS error.
- Makes an OS call again when Linux or macOS ends it early with `EINTR`.

### Limits

- Stack of its own on Linux: 32 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_shell_map`, with `_` before it on macOS.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); OS calls use the native convention.
- Argument order: `size`, `out`.

## Function `lantern_shell_unmap`

Gives back memory that lantern_shell_map gave.

### Signature

```
lantern_shell_unmap(address, size) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `address` | input | u64: an address lantern_shell_map gave |
| `size` | input | u64: the size of that call |

### Returns

- `LANTERN_OK`, always.

### Function does

- Linux and macOS: `munmap`. Windows: `VirtualFree` with MEM_RELEASE.
- Returns `LANTERN_OK` when its result is written, also when the OS call failed; the result then holds the OS error.
- Makes an OS call again when Linux or macOS ends it early with `EINTR`.

### Limits

- Stack of its own on Linux: 16 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_shell_unmap`, with `_` before it on macOS.
- Convention: as `lantern_shell_map`.
- Argument order: `address`, `size`.

## Function `lantern_shell_read_file`

Reads a whole file into a ByteList in memory that lantern_shell_map gives.

### Signature

```
lantern_shell_read_file(path, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `path` | input | ByteList: the path in UTF-8, without a terminating zero, at most 4095 bytes |
| `result` | output | [`FileResult`](#type-fileresult) |

### Returns

- `LANTERN_OK`, always.

### Caller must

- `path` is a ByteList in UTF-8 without a terminating zero, at most `SHELL_PATH_MAX` (4095) bytes; a longer one gives Linux and macOS `ENAMETOOLONG`, Windows `ERROR_FILENAME_EXCED_RANGE`.

### Function does

- Opens the file for reading, reads its size, maps 24 bytes more than that size with lantern_shell_map, reads every byte after the first 24, and closes the file.
- The memory is a ByteList: `size` the bytes mapped, `offset` 24, `count` the file's size.
- An OS error of any step, a path above 4095 bytes (Linux and macOS `ENAMETOOLONG`, Windows `ERROR_FILENAME_EXCED_RANGE`), or a file that ends before its size: `error` holds it, the memory goes back, and `address` is 0.
- Returns `LANTERN_OK` when its result is written, also when the OS call failed; the result then holds the OS error.
- Makes an OS call again when Linux or macOS ends it early with `EINTR`.
- Windows converts the path to UTF-16.

### Limits

- Stack of its own on Linux: 4400 bytes on x86-64 (return address included), 2 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_shell_read_file`, with `_` before it on macOS.
- Convention: as `lantern_shell_map`.
- Argument order: `path`, `result`.

## Function `lantern_shell_write`

Writes bytes to the standard output or the standard error.

### Signature

```
lantern_shell_write(stream, bytes) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `stream` | input | u64: 1 the standard output, 2 the standard error |
| `bytes` | input | ByteList |

### Returns

- `LANTERN_OK`, always.

### Function does

- Writes until every byte is written or the OS gives an error; an error drops the rest.
- Linux and macOS: `write` to file descriptor 1 or 2. Windows: `WriteFile` to `GetStdHandle` of STD_OUTPUT_HANDLE or STD_ERROR_HANDLE.
- Returns `LANTERN_OK` when its result is written, also when the OS call failed; the result then holds the OS error.
- Makes an OS call again when Linux or macOS ends it early with `EINTR`.

### Limits

- Stack of its own on Linux: 96 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_shell_write`, with `_` before it on macOS.
- Convention: as `lantern_shell_map`.
- Argument order: `stream`, `bytes`.

## Function `lantern_shell_time_ms`

Reads the Unix time in milliseconds.

### Signature

```
lantern_shell_time_ms(out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `out` | output | u64: milliseconds since 1970-01-01 00:00:00 UTC |

### Returns

- `LANTERN_OK`, always.

### Function does

- Linux: `clock_gettime` of CLOCK_REALTIME. macOS: `clock_gettime_nsec_np` of CLOCK_REALTIME. Windows: `GetSystemTimePreciseAsFileTime`, less the 11644473600 seconds from 1601 to 1970.
- Returns `LANTERN_OK` when its result is written, also when the OS call failed; the result then holds the OS error.
- Makes an OS call again when Linux or macOS ends it early with `EINTR`.

### Limits

- Stack of its own on Linux: 48 bytes on x86-64 (return address included), 16 bytes on ARM64, 16 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_shell_time_ms`, with `_` before it on macOS.
- Convention: as `lantern_shell_map`.
- Argument order: `out`.

## Function `lantern_shell_open`

Opens a file to read, or to append to, made when it is missing.

### Signature

```
lantern_shell_open(path, mode, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `path` | input | ByteList: a path |
| `mode` | input | u64: `SHELL_OPEN_READ` (0) or `SHELL_OPEN_APPEND` (1) |
| `result` | output | `FileOp`: `value` the file |

### Returns

- `LANTERN_OK`, always.

### Caller must

- `path` is a ByteList in UTF-8 without a terminating zero, at most `SHELL_PATH_MAX` (4095) bytes; a longer one gives Linux and macOS `ENAMETOOLONG`, Windows `ERROR_FILENAME_EXCED_RANGE`.

### Function does

- `SHELL_OPEN_READ`: Linux `openat` and macOS `open` with O_RDONLY and O_CLOEXEC; Windows `CreateFileW` with GENERIC_READ and OPEN_EXISTING.
- `SHELL_OPEN_APPEND`: Linux and macOS with O_WRONLY, O_CREAT, O_APPEND and O_CLOEXEC, mode 0644; Windows `CreateFileW` with GENERIC_WRITE and OPEN_ALWAYS.
- Windows shares the file for reading, writing and deleting.
- Another mode: Linux and macOS `EINVAL`, Windows `ERROR_INVALID_PARAMETER`.
- Returns `LANTERN_OK` when its result is written, also when the OS call failed; the result then holds the OS error.
- Makes an OS call again when Linux or macOS ends it early with `EINTR`.
- Windows converts the path to UTF-16.

### Limits

- Stack of its own on Linux: 4208 bytes on x86-64 (return address included), 1 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_shell_open`, with `_` before it on macOS.
- Convention: as `lantern_shell_map`.
- Argument order: `path`, `mode`, `result`.

## Function `lantern_shell_append`

Writes bytes at the end of a file opened with `SHELL_OPEN_APPEND`.

### Signature

```
lantern_shell_append(file, bytes, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `file` | input | u64 |
| `bytes` | input | ByteList |
| `result` | output | `FileOp`: `value` the bytes written |

### Returns

- `LANTERN_OK`, always.

### Caller must

- `file` is a u64: a file descriptor on Linux and macOS, a HANDLE on Windows.

### Function does

- Writes until every byte is written or the OS gives an error; `value` then holds the bytes written before it.
- A call that writes no bytes is an error: Linux and macOS `EIO`, Windows `ERROR_WRITE_FAULT`.
- Linux: `write`, which O_APPEND puts at the end. macOS: the same, at most 2^30 bytes a call, as its `write` refuses more than INT_MAX. Windows: `SetFilePointerEx` to the end, then `WriteFile`, at most 2^30 bytes a call.
- Returns `LANTERN_OK` when its result is written, also when the OS call failed; the result then holds the OS error.
- Makes an OS call again when Linux or macOS ends it early with `EINTR`.

### Limits

- Stack of its own on Linux: 32 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_shell_append`, with `_` before it on macOS.
- Convention: as `lantern_shell_map`.
- Argument order: `file`, `bytes`, `result`.

## Function `lantern_shell_sync`

Makes the bytes of a file durable: they survive a crash of the OS or a loss of power once it returns with no error.

### Signature

```
lantern_shell_sync(file, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `file` | input | u64 |
| `result` | output | `FileOp` |

### Returns

- `LANTERN_OK`, always.

### Caller must

- `file` is a u64: a file descriptor on Linux and macOS, a HANDLE on Windows.

### Function does

- Linux: `fdatasync`. macOS: `fcntl` with F_FULLFSYNC, as `fsync` alone leaves the bytes in the drive's cache; `fsync` when that `fcntl` gives an error, as on a file system without F_FULLFSYNC. Windows: `FlushFileBuffers`.
- Returns `LANTERN_OK` when its result is written, also when the OS call failed; the result then holds the OS error.
- Makes an OS call again when Linux or macOS ends it early with `EINTR`.

### Limits

- Stack of its own on Linux: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_shell_sync`, with `_` before it on macOS.
- Convention: as `lantern_shell_map`.
- Argument order: `file`, `result`.

## Function `lantern_shell_truncate`

Cuts a file opened with `SHELL_OPEN_APPEND` to a size.

### Signature

```
lantern_shell_truncate(file, size, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `file` | input | u64 |
| `size` | input | u64: at most 2^63 - 1 |
| `result` | output | `FileOp` |

### Returns

- `LANTERN_OK`, always.

### Caller must

- `file` is a u64: a file descriptor on Linux and macOS, a HANDLE on Windows.

### Function does

- Linux and macOS: `ftruncate`. Windows: `SetFilePointerEx` to the size, then `SetEndOfFile`.
- Returns `LANTERN_OK` when its result is written, also when the OS call failed; the result then holds the OS error.
- Makes an OS call again when Linux or macOS ends it early with `EINTR`.

### Limits

- Stack of its own on Linux: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_shell_truncate`, with `_` before it on macOS.
- Convention: as `lantern_shell_map`.
- Argument order: `file`, `size`, `result`.

## Function `lantern_shell_close`

Closes a file.

### Signature

```
lantern_shell_close(file) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `file` | input | u64 |

### Returns

- `LANTERN_OK`, always.

### Caller must

- `file` is a u64: a file descriptor on Linux and macOS, a HANDLE on Windows.

### Function does

- Linux and macOS: `close`. Windows: `CloseHandle`.
- Returns `LANTERN_OK` when its result is written, also when the OS call failed; the result then holds the OS error.
- Makes an OS call again when Linux or macOS ends it early with `EINTR`.

### Limits

- Stack of its own on Linux: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_shell_close`, with `_` before it on macOS.
- Convention: as `lantern_shell_map`.
- Argument order: `file`.

## Function `lantern_shell_map_file`

Maps a whole file to read, without copying it.

### Signature

```
lantern_shell_map_file(path, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `path` | input | ByteList: a path |
| `result` | output | [`FileResult`](#type-fileresult): `address` the file's first byte, `size` and `mapped` its size |

### Returns

- `LANTERN_OK`, always.

### Caller must

- Unmap a file before it renames over it, deletes it or truncates it: Windows refuses those while a view is mapped.
- `path` is a ByteList in UTF-8 without a terminating zero, at most `SHELL_PATH_MAX` (4095) bytes; a longer one gives Linux and macOS `ENAMETOOLONG`, Windows `ERROR_FILENAME_EXCED_RANGE`.

### Function does

- Linux and macOS: opens the file read only, reads its size, `mmap` with PROT_READ and MAP_SHARED, and closes it. Windows: `CreateFileW` with GENERIC_READ, `GetFileSizeEx`, `CreateFileMappingW` with PAGE_READONLY, `MapViewOfFile` with FILE_MAP_READ, and closes both handles.
- A file of no bytes: `address` 0, `size` 0 and no error.
- The bytes stay readable until lantern_shell_unmap_file.
- Returns `LANTERN_OK` when its result is written, also when the OS call failed; the result then holds the OS error.
- Makes an OS call again when Linux or macOS ends it early with `EINTR`.
- Windows converts the path to UTF-16.

### Limits

- Stack of its own on Linux: 4400 bytes on x86-64 (return address included), 2 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_shell_map_file`, with `_` before it on macOS.
- Convention: as `lantern_shell_map`.
- Argument order: `path`, `result`.

## Function `lantern_shell_unmap_file`

Unmaps a file that lantern_shell_map_file mapped.

### Signature

```
lantern_shell_unmap_file(address, size) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `address` | input | u64: an `address` of lantern_shell_map_file, not 0 |
| `size` | input | u64: its `mapped` |

### Returns

- `LANTERN_OK`, always.

### Function does

- Linux and macOS: `munmap`. Windows: `UnmapViewOfFile`.
- Returns `LANTERN_OK` when its result is written, also when the OS call failed; the result then holds the OS error.
- Makes an OS call again when Linux or macOS ends it early with `EINTR`.

### Limits

- Stack of its own on Linux: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_shell_unmap_file`, with `_` before it on macOS.
- Convention: as `lantern_shell_map`.
- Argument order: `address`, `size`.

## Function `lantern_shell_remove`

Deletes a file.

### Signature

```
lantern_shell_remove(path, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `path` | input | ByteList: a path |
| `result` | output | `FileOp` |

### Returns

- `LANTERN_OK`, always.

### Caller must

- `path` is a ByteList in UTF-8 without a terminating zero, at most `SHELL_PATH_MAX` (4095) bytes; a longer one gives Linux and macOS `ENAMETOOLONG`, Windows `ERROR_FILENAME_EXCED_RANGE`.

### Function does

- Linux: `unlinkat`. macOS: `unlink`. Windows: `DeleteFileW`.
- Returns `LANTERN_OK` when its result is written, also when the OS call failed; the result then holds the OS error.
- Makes an OS call again when Linux or macOS ends it early with `EINTR`.
- Windows converts the path to UTF-16.

### Limits

- Stack of its own on Linux: 4208 bytes on x86-64 (return address included), 1 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_shell_remove`, with `_` before it on macOS.
- Convention: as `lantern_shell_map`.
- Argument order: `path`, `result`.

## Function `lantern_shell_rename`

Renames a file, over a file of the new name when there is one, in one step.

### Signature

```
lantern_shell_rename(from, to, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `from` | input | ByteList: a path |
| `to` | input | ByteList: a path in the same directory |
| `result` | output | `FileOp` |

### Returns

- `LANTERN_OK`, always.

### Function does

- Linux: `renameat2` with no flags. macOS: `rename`. Windows: `MoveFileExW` with MOVEFILE_REPLACE_EXISTING and MOVEFILE_WRITE_THROUGH.
- Returns `LANTERN_OK` when its result is written, also when the OS call failed; the result then holds the OS error.
- Makes an OS call again when Linux or macOS ends it early with `EINTR`.

### Limits

- Stack of its own on Linux: 8304 bytes on x86-64 (return address included), 2 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_shell_rename`, with `_` before it on macOS.
- Convention: as `lantern_shell_map`.
- Argument order: `from`, `to`, `result`.

## Function `lantern_shell_mkdir`

Makes a directory.

### Signature

```
lantern_shell_mkdir(path, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `path` | input | ByteList: a path |
| `result` | output | `FileOp`: an existing one gives Linux and macOS `EEXIST`, Windows `ERROR_ALREADY_EXISTS` |

### Returns

- `LANTERN_OK`, always.

### Caller must

- `path` is a ByteList in UTF-8 without a terminating zero, at most `SHELL_PATH_MAX` (4095) bytes; a longer one gives Linux and macOS `ENAMETOOLONG`, Windows `ERROR_FILENAME_EXCED_RANGE`.

### Function does

- Linux: `mkdirat`, mode 0755. macOS: `mkdir`, mode 0755. Windows: `CreateDirectoryW`.
- Returns `LANTERN_OK` when its result is written, also when the OS call failed; the result then holds the OS error.
- Makes an OS call again when Linux or macOS ends it early with `EINTR`.
- Windows converts the path to UTF-16.

### Limits

- Stack of its own on Linux: 4208 bytes on x86-64 (return address included), 1 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_shell_mkdir`, with `_` before it on macOS.
- Convention: as `lantern_shell_map`.
- Argument order: `path`, `result`.

## Function `lantern_shell_sync_dir`

Makes the entries of a directory durable, as a rename or a new file in it.

### Signature

```
lantern_shell_sync_dir(path, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `path` | input | ByteList: a path |
| `result` | output | `FileOp` |

### Returns

- `LANTERN_OK`, always.

### Caller must

- `path` is a ByteList in UTF-8 without a terminating zero, at most `SHELL_PATH_MAX` (4095) bytes; a longer one gives Linux and macOS `ENAMETOOLONG`, Windows `ERROR_FILENAME_EXCED_RANGE`.

### Function does

- Linux and macOS: opens the directory read only, `fsync`, and closes it. Windows: nothing, with no error: NTFS journals its directory changes, and lantern_shell_rename writes through.
- Returns `LANTERN_OK` when its result is written, also when the OS call failed; the result then holds the OS error.
- Makes an OS call again when Linux or macOS ends it early with `EINTR`.
- Windows converts the path to UTF-16.

### Limits

- Stack of its own on Linux: 4208 bytes on x86-64 (return address included), 1 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_shell_sync_dir`, with `_` before it on macOS.
- Convention: as `lantern_shell_map`.
- Argument order: `path`, `result`.

## Type `FileOp`

The outcome of a file function.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `error` | u64 | 0, or the OS error number |
| 8 | `value` | u64 | What the function gives: a file, 0 on an error; or the bytes written |

## Type `FileResult`

The outcome of `lantern_shell_read_file` and `lantern_shell_map_file`.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `error` | u64 | 0, or the OS error number; 1 when the file ends before its size |
| 8 | `address` | u64 | The ByteList with the bytes, or 0 |
| 16 | `size` | u64 | The bytes of the file |
| 24 | `mapped` | u64 | The size given to lantern_shell_map, for lantern_shell_unmap |

## Function `lantern_shell_process`

Reads the process's CPU time, highest resident memory and open file limit, for the metrics ([metrics.md](metrics.md)).

### Signature

```
lantern_shell_process(out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `out` | output | 24 bytes: `cpu_us`, `max_rss_bytes`, `max_fds`, each a u64 |

### Returns

- `LANTERN_OK`.

### Function does

- `cpu_us`: the process's user and system CPU time, in microseconds.
- `max_rss_bytes`: the highest resident memory of the process, in bytes.
- `max_fds`: the soft limit of open files; 0 when the OS reports none or the call fails.
- Linux: getrusage(RUSAGE_SELF) (`ru_maxrss` in KiB) and prlimit64(0, RLIMIT_NOFILE).
- macOS: getrusage and getrlimit(RLIMIT_NOFILE) of libSystem (`ru_maxrss` in bytes).
- Windows: GetProcessTimes and K32GetProcessMemoryInfo (`PeakWorkingSetSize`) of the current process; `max_fds` 0.

### Limits

- Stack of its own on Linux: 192 bytes on x86-64 (return address included), 176 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_shell_process`, with `_` before it on macOS.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each u64 argument is passed by its address.
- Argument order: `out`.

## Function `lantern_shell_wide`

A path in UTF-16 with a zero after it, for the Windows calls.

### Signature

```
lantern_shell_wide(path, to) -> error
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `path` | input | ByteList: the path in UTF-8 |
| `to` | output | at most `SHELL_WIDE_BYTES` bytes |

### Caller must

- `path` is a ByteList in UTF-8 without a terminating zero, at most `SHELL_PATH_MAX` (4095) bytes; a longer one gives Linux and macOS `ENAMETOOLONG`, Windows `ERROR_FILENAME_EXCED_RANGE`.

### Function does

- Writes the path in UTF-16 with a zero after it to `to`, and returns 0, or the error.
- Windows converts the path to UTF-16.

### ABI

- Role: L0.
- Symbol: `lantern_shell_wide`, with `_` before it on macOS. Only the Windows shells have it. Only x86-64 and ARM64 have it.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each u64 argument is passed by its address.
- Argument order: `path`, `to`.

## Function `main`

The entry point of the binary on macOS.

### Signature

```
main(argc, argv) -> exit code
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `argc` | input | u64 in a register |
| `argv` | input | the arguments |

### Function does

- Copies `argv` without the program name into an [`ArgList`](app.md#type-arglist) in memory from lantern_shell_map.
- Checks the CPU features of the `sha` variant: `cpuid` on x86-64, `sysctlbyname` on ARM64; with all of them calls `lx_lantern_app_main`, else lantern_app_main, with the ArgList.
- Returns the status lantern_app_main returns as the exit code.

### ABI

- Role: L0.
- Symbol: `main`, the entry point the OS calls, in the macOS shell of each ISA.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Convention of the macOS C runtime's `main`.
- Argument order: `argc`, `argv`.

## Function `mainCRTStartup`

The entry point of the binary on Windows.

### Signature

```
mainCRTStartup() -> exit code
```

### Function does

- Splits `GetCommandLineW` by the rules of `CommandLineToArgvW`, converts each argument to UTF-8, and copies them without the program name into an [`ArgList`](app.md#type-arglist) in memory from lantern_shell_map.
- Checks the CPU features of the `sha` variant: `cpuid` on x86-64, `IsProcessorFeaturePresent` on ARM64; with all of them calls `lx_lantern_app_main`, else lantern_app_main, with the ArgList.
- Ends the process with the status lantern_app_main returns as the exit code.

### ABI

- Role: L0.
- Symbol: `mainCRTStartup`, the entry point the OS calls, in the Windows shell of each ISA.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Convention of the Windows process entry point.

## Function `_start`

The entry point of the binary on Linux.

### Signature

```
_start() -> exit code
```

### Function does

- Copies the arguments from the stack the kernel builds, without the program name, into an [`ArgList`](app.md#type-arglist) in memory from lantern_shell_map.
- On x86-64 and ARM64 checks the CPU features of the `sha` variant: `cpuid` on x86-64, the `AT_HWCAP` entry of the auxiliary vector on ARM64; with all of them calls `lx_lantern_app_main`, else lantern_app_main, with the ArgList.
- Ends the process with `exit_group` and the status lantern_app_main returns.

### ABI

- Role: L0.
- Symbol: `_start`, the entry point the OS calls, in the Linux shell of each ISA.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Convention of the Linux process entry: the stack holds argc, then argv, a 0, envp, a 0, then the auxiliary vector.

## Test vectors

- tests/shell/shell.c, linked with the shell object of the target: it maps and unmaps memory, reads a file it wrote, an empty file, a missing file and a path of 5000 bytes, writes a line to the standard output, and reads the time.
- It also makes a directory, then the same one again (an error), appends to a new file in it in two writes, syncs it and the directory, maps it and finds both writes, truncates it and maps it again, opens it again to append and finds the new end, opens it to read, opens with a faulty mode (an error), maps an empty file (address 0), renames the empty file over the first and maps the result, removes it, and maps and removes the missing file (each an error).
- platform/linux/build.sh builds it as `shell-test` for each Linux ISA, and platform/macos/link-runner.sh for each macOS ISA; CI runs it.

## Results

<!-- CI generates the tick table for each function here. -->

### `lantern_shell_map`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_shell_unmap`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_shell_read_file`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_shell_write`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_shell_time_ms`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_shell_open`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_shell_append`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_shell_sync`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_shell_truncate`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_shell_close`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_shell_map_file`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_shell_unmap_file`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_shell_remove`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_shell_rename`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_shell_mkdir`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_shell_sync_dir`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_shell_process`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_shell_wide`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `main`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `mainCRTStartup`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `_start`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |
