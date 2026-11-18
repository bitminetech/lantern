# Shell

## Contents

### Functions

- [`lantern_shell_map`](#function-lantern_shell_map): gives zeroed memory.
- [`lantern_shell_unmap`](#function-lantern_shell_unmap): gives memory back.
- [`lantern_shell_read_file`](#function-lantern_shell_read_file): reads a whole file into a new ByteList.
- [`lantern_shell_write`](#function-lantern_shell_write): writes bytes to the standard output or the standard error.
- [`lantern_shell_time_ms`](#function-lantern_shell_time_ms): reads the Unix time in milliseconds.

### Types

- [`FileResult`](#type-fileresult): the outcome of `lantern_shell_read_file`.

## Spec

- Document: ARCHITECTURE.md section 2 (core and shell) and section 7 (operating systems).
- Section: the shell of the lantern binary: memory, files, the log and the clock, for Linux (system calls), macOS (libSystem) and Windows (kernel32). Sockets, the monotonic clock and random bytes come from the shell of asm-libp2p.

## Common rules

- Each OS and ISA has one shell, `asm/shell/<OS>/<ISA>/shell.s`, with the functions below and the entry point of the binary.
- The entry point copies the program's arguments into an [`ArgList`](app.md#type-arglist) in memory from lantern_shell_map, calls lantern_app_main ([app.md](app.md)) with it, and ends the process with the status it returns as the exit code.
  - Linux: `_start`; the arguments from the stack the kernel builds, without the program name.
  - macOS: `main`; `argv` without the program name.
  - Windows: `mainCRTStartup`; `GetCommandLineW` split by the rules of `CommandLineToArgvW`, each argument converted to UTF-8, without the program name.
- A function returns `LANTERN_OK` when its result is written, also when the OS call failed; the result then holds the OS error.

## Test vectors

- tests/shell/shell.c, linked with the shell object of the target: it maps and unmaps memory, reads a file it wrote, an empty file, a missing file and a path of 5000 bytes, writes a line to the standard output, and reads the time.
- platform/linux/build.sh builds it as `shell-test` for each Linux ISA, and CI runs it.

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

## Type `FileResult`

The outcome of `lantern_shell_read_file`.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `error` | u64 | 0, or the OS error number; 1 when the file ends before its size |
| 8 | `address` | u64 | The ByteList with the bytes, or 0 |
| 16 | `size` | u64 | The bytes of the file |
| 24 | `mapped` | u64 | The size given to lantern_shell_map, for lantern_shell_unmap |

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
