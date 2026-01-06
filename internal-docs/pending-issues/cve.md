# CVE candidate: unbounded allocation in validator registry mapping parser

## Summary
A crafted validator registry file can trigger an unbounded allocation when the parser derives `record_count` from the maximum index in the mapping list. A single large index forces `calloc(record_count, ...)`, leading to memory exhaustion and a process-level denial-of-service during genesis parsing.

Status: Fixed by rejecting registry indices/counts above `LANTERN_VALIDATOR_REGISTRY_LIMIT` (4096) before allocation.

## Impact
Any node that loads a malicious or corrupted validators registry mapping file can be forced to allocate an extremely large buffer (or fail with OOM), preventing startup and causing a denial-of-service. The input is file-based and requires only control over the registry file contents.

## Root cause
- `src/genesis/genesis_parse_registry.c:398-403` computes `record_count = max_index + 1` from parsed indices and immediately allocates `calloc(record_count, sizeof(*seen))` without an upper bound.
- The mapping list accepts arbitrary indices from the file, so a single large index expands `record_count` to attacker-controlled size.

## Proof (reproducible test)
New unit test: `tests/unit/test_genesis_registry_dos.c`

Commands:
```
cmake -S . -B build
cmake --build build --target lantern_genesis_registry_dos_test
./build/lantern_genesis_registry_dos_test
```

Why this proves the issue:
- The test writes a registry file containing `- 0` and a very large index.
- A `calloc` shim records allocation attempts above a safe threshold and returns NULL.
- The parser hits `validate_registry_index_coverage`, attempts to allocate the huge `seen` array, and fails with `LANTERN_GENESIS_ERR_OUT_OF_MEMORY`, demonstrating an unbounded allocation path derived directly from input data.

## Suggested fix (high level)
- Enforce a strict upper bound on `max_index` / `record_count` based on protocol or configuration limits before allocating.
- Alternatively, validate index coverage using a sparse structure (e.g., hash set) instead of a dense `record_count`-sized bitmap, and cap total indices accepted.
