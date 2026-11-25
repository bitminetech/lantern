# Shell

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

### Types

- [`FileResult`](#type-fileresult): the outcome of `lantern_shell_read_file` and `lantern_shell_map_file`.
- [`FileOp`](#type-fileop): the outcome of the other file functions.

## Spec

- Document: ARCHITECTURE.md section 2 (core and shell) and section 7 (operating systems).
- Section: the shell of the lantern binary: memory, files, the log and the clock, for Linux (system calls), macOS (libSystem) and Windows (kernel32). Sockets, the monotonic clock and random bytes come from the shell of asm-libp2p.
- The file functions serve the database of [db.md](db.md): files written once at their end, made durable, mapped to read, renamed into place, and deleted whole.

## Common rules

- Each OS and ISA has one shell, `asm/shell/<OS>/<ISA>/shell.s`, with the functions below and the entry point of the binary.
- The entry point copies the program's arguments into an [`ArgList`](app.md#type-arglist) in memory from lantern_shell_map, calls lantern_app_main ([app.md](app.md)) with it, and ends the process with the status it returns as the exit code.
- On x86-64 and ARM64 it first checks the CPU features of the `sha` variant (README, Target profile), with baseline instructions only. With all of them it calls `lx_lantern_app_main`, lantern_app_main of the copy built with that variant; else lantern_app_main.
  - x86-64: `cpuid`.
  - Linux ARM64: the `AT_HWCAP` entry of the auxiliary vector, after the environment pointers on the stack the kernel builds.
  - macOS ARM64: `sysctlbyname`.
  - Windows ARM64: `IsProcessorFeaturePresent`.
  - Linux: `_start`; the arguments from the stack the kernel builds, without the program name.
  - macOS: `main`; `argv` without the program name.
  - Windows: `mainCRTStartup`; `GetCommandLineW` split by the rules of `CommandLineToArgvW`, each argument converted to UTF-8, without the program name.
- A function returns `LANTERN_OK` when its result is written, also when the OS call failed; the result then holds the OS error.
- A path is a ByteList in UTF-8 without a terminating zero, at most `SHELL_PATH_MAX` (4095) bytes; a longer one gives Linux and macOS `ENAMETOOLONG`, Windows `ERROR_FILENAME_EXCED_RANGE`. Windows converts it to UTF-16.
- A file is a u64: a file descriptor on Linux and macOS, a HANDLE on Windows. Each u64 argument is passed by its address.
- An OS call that Linux or macOS ends early with `EINTR` goes again.

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

### ABI

- Role: L2.
- Symbol: `lantern_shell_map` (`_lantern_shell_map` on macOS).
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

### ABI

- Role: L2.
- Symbol: `lantern_shell_unmap` (`_lantern_shell_unmap` on macOS).
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

### Function does

- Opens the file for reading, reads its size, maps 24 bytes more than that size with lantern_shell_map, reads every byte after the first 24, and closes the file.
- The memory is a ByteList: `size` the bytes mapped, `offset` 24, `count` the file's size.
- An OS error of any step, a path above 4095 bytes (Linux and macOS `ENAMETOOLONG`, Windows `ERROR_FILENAME_EXCED_RANGE`), or a file that ends before its size: `error` holds it, the memory goes back, and `address` is 0.

### ABI

- Role: L2.
- Symbol: `lantern_shell_read_file` (`_lantern_shell_read_file` on macOS).
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

### ABI

- Role: L2.
- Symbol: `lantern_shell_write` (`_lantern_shell_write` on macOS).
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

### ABI

- Role: L2.
- Symbol: `lantern_shell_time_ms` (`_lantern_shell_time_ms` on macOS).
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

### Function does

- `SHELL_OPEN_READ`: Linux `openat` and macOS `open` with O_RDONLY and O_CLOEXEC; Windows `CreateFileW` with GENERIC_READ and OPEN_EXISTING.
- `SHELL_OPEN_APPEND`: Linux and macOS with O_WRONLY, O_CREAT, O_APPEND and O_CLOEXEC, mode 0644; Windows `CreateFileW` with GENERIC_WRITE and OPEN_ALWAYS.
- Windows shares the file for reading, writing and deleting.
- Another mode: Linux and macOS `EINVAL`, Windows `ERROR_INVALID_PARAMETER`.

### ABI

- Role: L2.
- Symbol: `lantern_shell_open` (`_lantern_shell_open` on macOS).
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

### Function does

- Writes until every byte is written or the OS gives an error; `value` then holds the bytes written before it.
- A call that writes no bytes is an error: Linux and macOS `EIO`, Windows `ERROR_WRITE_FAULT`.
- Linux: `write`, which O_APPEND puts at the end. macOS: the same, at most 2^30 bytes a call, as its `write` refuses more than INT_MAX. Windows: `SetFilePointerEx` to the end, then `WriteFile`, at most 2^30 bytes a call.

### ABI

- Role: L2.
- Symbol: `lantern_shell_append` (`_lantern_shell_append` on macOS).
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

### Function does

- Linux: `fdatasync`. macOS: `fcntl` with F_FULLFSYNC, as `fsync` alone leaves the bytes in the drive's cache; `fsync` when that `fcntl` gives an error, as on a file system without F_FULLFSYNC. Windows: `FlushFileBuffers`.

### ABI

- Role: L2.
- Symbol: `lantern_shell_sync` (`_lantern_shell_sync` on macOS).
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

### Function does

- Linux and macOS: `ftruncate`. Windows: `SetFilePointerEx` to the size, then `SetEndOfFile`.

### ABI

- Role: L2.
- Symbol: `lantern_shell_truncate` (`_lantern_shell_truncate` on macOS).
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

### Function does

- Linux and macOS: `close`. Windows: `CloseHandle`.

### ABI

- Role: L2.
- Symbol: `lantern_shell_close` (`_lantern_shell_close` on macOS).
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

### Function does

- Linux and macOS: opens the file read only, reads its size, `mmap` with PROT_READ and MAP_SHARED, and closes it. Windows: `CreateFileW` with GENERIC_READ, `GetFileSizeEx`, `CreateFileMappingW` with PAGE_READONLY, `MapViewOfFile` with FILE_MAP_READ, and closes both handles.
- A file of no bytes: `address` 0, `size` 0 and no error.
- The bytes stay readable until lantern_shell_unmap_file.

### Caller must

- Unmap a file before it renames over it, deletes it or truncates it: Windows refuses those while a view is mapped.

### ABI

- Role: L2.
- Symbol: `lantern_shell_map_file` (`_lantern_shell_map_file` on macOS).
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

### ABI

- Role: L2.
- Symbol: `lantern_shell_unmap_file` (`_lantern_shell_unmap_file` on macOS).
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

### Function does

- Linux: `unlinkat`. macOS: `unlink`. Windows: `DeleteFileW`.

### ABI

- Role: L2.
- Symbol: `lantern_shell_remove` (`_lantern_shell_remove` on macOS).
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

### ABI

- Role: L2.
- Symbol: `lantern_shell_rename` (`_lantern_shell_rename` on macOS).
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

### Function does

- Linux: `mkdirat`, mode 0755. macOS: `mkdir`, mode 0755. Windows: `CreateDirectoryW`.

### ABI

- Role: L2.
- Symbol: `lantern_shell_mkdir` (`_lantern_shell_mkdir` on macOS).
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

### Function does

- Linux and macOS: opens the directory read only, `fsync`, and closes it. Windows: nothing, with no error: NTFS journals its directory changes, and lantern_shell_rename writes through.

### ABI

- Role: L2.
- Symbol: `lantern_shell_sync_dir` (`_lantern_shell_sync_dir` on macOS).
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

### ABI

- Role: L0.
- Symbol: `lantern_shell_process` (`_lantern_shell_process` on macOS).
- Argument order: `out`.

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
