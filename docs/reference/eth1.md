# Eth1 follower

## Contents

### Functions

- [`lantern_eth_get_block_by_number`](#function-lantern_eth_get_block_by_number): the JSON-RPC request of eth_getBlockByNumber.
- [`lantern_eth_get_deposit_logs`](#function-lantern_eth_get_deposit_logs): the JSON-RPC request of eth_getLogs for the deposit contract's `DepositEvent` logs.
- [`lantern_eth1_block`](#function-lantern_eth1_block): the number, hash and timestamp of an eth_getBlockByNumber result.
- [`lantern_eth1_deposit_logs`](#function-lantern_eth1_deposit_logs): the deposits of an eth_getLogs result.
- [`lantern_deposit_leaf`](#function-lantern_deposit_leaf): the leaf of a deposit: hash_tree_root of its `DepositData`.
- [`lantern_deposit_tree_push`](#function-lantern_deposit_tree_push): adds one deposit's leaf to a `DepositTree`.
- [`lantern_deposit_tree_root`](#function-lantern_deposit_tree_root): the deposit root of a `DepositTree`.
- [`lantern_deposit_proof`](#function-lantern_deposit_proof): the proof of one deposit against the root of the first leaves.
- [`lantern_e1_abi_check`](#function-lantern_e1_abi_check): whether 576 bytes of a DepositEvent's data have the ABI layout of its five byte strings.
- [`lantern_e1_close`](#function-lantern_e1_close): closes a ByteList written from its byte 24 to a cursor.
- [`lantern_e1_hash2`](#function-lantern_e1_hash2): sHA-256 of two 32-byte nodes.
- [`lantern_e1_hex`](#function-lantern_e1_hex): writes bytes as lowercase hex at a cursor.
- [`lantern_e1_qty`](#function-lantern_e1_qty): writes a QUANTITY at a cursor.
- [`lantern_e1_qty_in`](#function-lantern_e1_qty_in): reads a QUANTITY string at a cursor.

### Types

- [`Eth1Block`](#type-eth1block): an eth1 block as get_eth1_vote reads it.
- [`Eth1Deposit`](#type-eth1deposit): one deposit of a `DepositEvent` log.
- [`DepositTree`](#type-deposittree): the deposit contract's incremental Merkle tree.

## Spec

- Document: [consensus-specs v1.7.0-beta.4](https://github.com/ethereum/consensus-specs/tree/aa16bb4c156184e9548a997d53efaf2a228a6304/specs).
- Section: phase0 `deposit-contract.md`, `validator.md` (Eth1 Data, Deposits) and `beacon-chain.md` (`DepositData`, `DEPOSIT_CONTRACT_TREE_DEPTH`, process_deposit's is_valid_merkle_branch); electra `validator.md`.
- Document: [execution-apis 981aa66](https://github.com/ethereum/execution-apis/tree/981aa66d79364be8322a9c358aaf0a571cca0873/src/engine) `common.md`.
- Section: the Engine API connection also serves `eth_getBlockByNumber` and `eth_getLogs`, with the same JWT.
- Document: the deposit contract's source, [solidity-deposit-contract](https://github.com/ethereum/solidity-deposit-contract/blob/master/deposit_contract.sol), which `deposit-contract.md` names.
- Section: the `DepositEvent` log, its little endian `amount` and `index`, and get_deposit_root.
- Document: the Solidity ABI encoding of a log's `data`: five dynamic `bytes` values.
## Function `lantern_eth_get_block_by_number`

The JSON-RPC request `{"jsonrpc":"2.0","id":id,"method":"eth_getBlockByNumber","params":["<number>",false]}`: the number as a `QUANTITY`, or `latest` for 2^64 - 1.

### Signature

```
lantern_eth_get_block_by_number(number, id, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `number` | input | u64 |
| `id` | input | u64 |
| `out` | output | `ByteList`, its `size` set by the caller |

### Returns

- `LANTERN_OK`: `out` holds the request.
- `LANTERN_BUFFER_TOO_SMALL`: `out` has room for fewer than 128 bytes.

### Function does

- Writes JSON compact, with no spaces, in the field order of the spec's lists: a `QUANTITY` is lowercase hex with no leading zeros, `0x0` for zero; `DATA` is lowercase hex, two digits a byte.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_eth_get_block_by_number`, with `_` before it on macOS.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); every u64 argument is passed by its address.
- Argument order: `number`, `id`, `out`.

## Function `lantern_eth_get_deposit_logs`

The JSON-RPC request `{"jsonrpc":"2.0","id":id,"method":"eth_getLogs","params":[{"address":"0x<address>","topics":["0x<DepositEvent topic>"],"fromBlock":"<from>","toBlock":"<to>"}]}`, `from` and `to` as a `QUANTITY`.

### Signature

```
lantern_eth_get_deposit_logs(address, from, to, id, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `address` | input | 20 bytes: the deposit contract's address |
| `from` | input | u64: the first block |
| `to` | input | u64: the last block |
| `id` | input | u64 |
| `out` | output | `ByteList`, its `size` set by the caller |

### Returns

- `LANTERN_OK`: `out` holds the request.
- `LANTERN_BUFFER_TOO_SMALL`: `out` has room for fewer than 384 bytes.

### Function does

- Writes JSON compact, with no spaces, in the field order of the spec's lists: a `QUANTITY` is lowercase hex with no leading zeros, `0x0` for zero; `DATA` is lowercase hex, two digits a byte.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_eth_get_deposit_logs`, with `_` before it on macOS.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); every u64 argument is passed by its address.
- Argument order: `address`, `from`, `to`, `id`, `out`.

## Function `lantern_eth1_block`

The `number`, `hash` and `timestamp` of the `result` of eth_getBlockByNumber.

### Signature

```
lantern_eth1_block(json, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `json` | input | `ByteList`: the `result` value's text |
| `out` | output | `Eth1Block`: `number`, `hash` and `timestamp` |

### Returns

- `LANTERN_OK`: `out` holds them; its other fields are 0.
- `LANTERN_INVALID_JSON`: the text is not one object with a `QUANTITY` `number` and `timestamp` below 2^64 and a 32 byte `DATA` `hash`; `null` too.

### Function does

- Takes JSON as RFC 8259 writes it, with whitespace between tokens and around the value. Skips each member it does not read, whatever its value; takes a later member of the same name over an earlier one.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_eth1_block`, with `_` before it on macOS.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); every u64 argument is passed by its address.
- Argument order: `json`, `out`.

## Function `lantern_eth1_deposit_logs`

The deposits of the `result` of eth_getLogs: an array of log objects.

### Signature

```
lantern_eth1_deposit_logs(json, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `json` | input | `ByteList`: the `result` value's text |
| `out` | output | `ByteList`, its `size` set by the caller: the `Eth1Deposit` entries, one after another, in the array's order |

### Returns

- `LANTERN_OK`: `out` holds an entry for each log whose `removed` is false or absent.
- `LANTERN_INVALID_JSON`: the text is not one array of objects; a log without a `QUANTITY` `blockNumber`, without a `topics` array whose first item is the `DepositEvent` topic, or without a `DATA` `data`.
- `LANTERN_INVALID_DEPOSIT_LOG`: a log's `data` is not the encoding the deposit contract writes: 576 bytes, the five offsets 160, 256, 320, 384 and 512, then the lengths 48, 32, 8, 96 and 8 each before its bytes, the rest zero.
- `LANTERN_BUFFER_TOO_SMALL`: `out` has no room for an entry.

### Function does

- The entry: the log's `blockNumber`; `index` the little endian u64 of the fifth value; the `DepositData` of the first four values, `amount` their little endian u64.
- Takes the logs of the `DepositEvent` topic: keccak256 of `DepositEvent(bytes,bytes,bytes,bytes,bytes)`, `0x649bbc62d0e31342afea4e5cd82d4049e7e1ee912fc0889aa790803be39038c5`.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 704 bytes on x86-64 (return address included), 704 bytes on ARM64, 720 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_eth1_deposit_logs`, with `_` before it on macOS.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); every u64 argument is passed by its address.
- Argument order: `json`, `out`.

## Function `lantern_deposit_leaf`

hash_tree_root of a `DepositData`: the root of its four fields' roots (`pubkey` as 48 bytes, `withdrawal_credentials`, `amount`, `signature` as 96 bytes).

### Signature

```
lantern_deposit_leaf(data, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `data` | input | `DepositData`: 184 bytes, as in `Eth1Deposit` |
| `out` | output | Root |

### Returns

- `LANTERN_OK`: `out` holds the root.

### Function does

- A leaf of the deposit tree is hash_tree_root of the deposit's `DepositData`.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 256 bytes on x86-64 (return address included), 256 bytes on ARM64, 448 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_deposit_leaf`, with `_` before it on macOS.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); every u64 argument is passed by its address.
- Argument order: `data`, `out`.

## Function `lantern_deposit_tree_push`

Adds the leaf of the next deposit to the tree, as the deposit contract's deposit function does.

### Signature

```
lantern_deposit_tree_push(tree, leaf) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `tree` | state | `DepositTree` |
| `leaf` | input | Root |

### Returns

- `LANTERN_OK`: the tree holds one leaf more.
- `LANTERN_INVALID_OVERFLOW`: it holds 2^`DEPOSIT_CONTRACT_TREE_DEPTH` - 1 leaves already.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 128 bytes on x86-64 (return address included), 128 bytes on ARM64, 128 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_deposit_tree_push`, with `_` before it on macOS.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); every u64 argument is passed by its address.
- Argument order: `tree`, `leaf`.

## Function `lantern_deposit_tree_root`

get_deposit_root of the deposit contract: the root of the tree's leaves, then the count as 8 little endian bytes and 24 zero bytes, hashed: hash_tree_root of the list of the deposits' `DepositData`.

### Signature

```
lantern_deposit_tree_root(tree, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `tree` | input | `DepositTree` |
| `out` | output | Root |

### Returns

- `LANTERN_OK`: `out` holds the root.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 192 bytes on x86-64 (return address included), 192 bytes on ARM64, 192 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_deposit_tree_root`, with `_` before it on macOS.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); every u64 argument is passed by its address.
- Argument order: `tree`, `out`.

## Function `lantern_deposit_proof`

The proof of the leaf at index against the root of the first count leaves: `DEPOSIT_CONTRACT_TREE_DEPTH` sibling hashes from the leaf up, then the count as a 32 byte little endian value, as process_deposit checks it with is_valid_merkle_branch of depth `DEPOSIT_CONTRACT_TREE_DEPTH` + 1.

### Signature

```
lantern_deposit_proof(leaves, count, index, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `leaves` | input | `ByteList`: the leaves from index 0, 32 bytes each |
| `count` | input | u64: the leaves of the tree, at most those of `leaves` |
| `index` | input | u64: below `count` |
| `scratch` | scratch | A buffer whose first u64 is its bytes: at least 8 + 16 * `count` + 32 |
| `out` | output | (`DEPOSIT_CONTRACT_TREE_DEPTH` + 1) * 32 bytes |

### Returns

- `LANTERN_OK`: `out` holds the proof.
- `LANTERN_INVALID_INDEX`: `index` is not below `count`, or `count` is above the leaves of `leaves`.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` is too small.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 176 bytes on x86-64 (return address included), 160 bytes on ARM64, 176 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_deposit_proof`, with `_` before it on macOS.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); every u64 argument is passed by its address.
- Argument order: `leaves`, `count`, `index`, `scratch`, `out`.

## Function `lantern_e1_abi_check`

Whether 576 bytes of a DepositEvent's data have the ABI layout of its five byte strings.

### Signature

```
lantern_e1_abi_check(data) -> flag
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `data` | input | 576 bytes: the log's data |

### Function does

- Returns 1 when the bytes match the expected ABI words but in the values (pubkey at 192, withdrawal credentials at 288, amount at 352, signature at 416, index at 544), else 0.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_e1_abi_check`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x9 to x13; rax, rcx, rdx, r8; a0, t0 to t4.
- Argument order: `data`.

## Function `lantern_e1_close`

Closes a ByteList written from its byte 24 to a cursor.

### Signature

```
lantern_e1_close(list, cursor)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `list` | state | ByteList |
| `cursor` | input | the address after the last byte written |

### Function does

- Sets the ByteList's offset to 24 and its length to the bytes from byte 24 to `cursor`.

### Function never

- Calls another function.
- Makes an OS call.

### Limits

- Stack of its own: 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_e1_close`, local to its object. Only ARM64 and RISC-V have it.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64 and RISC-V: x9, x10; t0.
- Argument order: `list`, `cursor`.

## Function `lantern_e1_hash2`

SHA-256 of two 32-byte nodes.

### Signature

```
lantern_e1_hash2(left, right, out)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `left` | input | 32 bytes |
| `right` | input | 32 bytes |
| `out` | output | 32 bytes |

### Function does

- Writes SHA-256 of `left` then `right` to `out`, with crypto_sha256 of asm-crypto and a ByteList of 64 bytes on its own stack.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_e1_hash2`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `left`, `right`, `out`.

## Function `lantern_e1_hex`

Writes bytes as lowercase hex at a cursor.

### Signature

```
lantern_e1_hex(bytes, cursor, n) -> end
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `bytes` | input | `n` bytes |
| `cursor` | output | where the text goes |
| `n` | input | u64 in a register |

### Function does

- Writes two lowercase hex digits for each byte and returns the cursor after them.

### Function never

- Calls another function.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_e1_hex`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- On x86-64 `cursor` is in rdi, `bytes` in rsi and the end comes back in rdi; on ARM64 and RISC-V the end comes back in x1 and a1.
- Registers it changes, on ARM64, x86-64, RISC-V: x1, x9 to x12; rax, rcx, rdi, r8; a1, t0 to t3.
- Argument order: `bytes`, `cursor`, `n`.

## Function `lantern_e1_qty`

Writes a QUANTITY at a cursor.

### Signature

```
lantern_e1_qty(value, cursor) -> end
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `value` | input | u64 in a register |
| `cursor` | output | where the text goes |

### Function does

- Writes "0x", then the hex digits of `value` with no leading zero (`0x0` for zero), and returns the cursor after them.

### Function never

- Calls another function.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_e1_qty`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- `value` is in x0, rax, a0 and `cursor` in x1, rdi, a1 on ARM64, x86-64, RISC-V; the end comes back in `cursor`'s register.
- Registers it changes, on ARM64, x86-64, RISC-V: x1, x9 to x12; rcx, rdx, rdi, r8; a1, t0 to t3.
- Argument order: `value`, `cursor`.

## Function `lantern_e1_qty_in`

Reads a QUANTITY string at a cursor.

### Signature

```
lantern_e1_qty_in(cursor) -> (cursor, value)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `cursor` | input | the JSON text |

### Function does

- Returns the cursor after the string and its value, or a cursor of 0 when the bytes are not "0x" and 1 to 16 hex digits with no leading zero.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_e1_qty_in`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- The value comes back in x1 on ARM64, rsi on x86-64 and a1 on RISC-V; the cursor in x0, rdi, a0.
- Registers it changes, on ARM64, x86-64, RISC-V: x0 to x3, x9 to x11; rax, rcx, rdx, rsi, rdi, r8, r9; a0 to a3, t0 to t4.
- Argument order: `cursor`.

## Type `Eth1Block`

What lantern_eth1_block reads of an execution block.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `number` | u64 | The block's number |
| 8 | `timestamp` | u64 | |
| 16 | `deposit_count` | u64 | The deposits of the contract after the block |
| 24 | `hash` | Hash32 | |
| 56 | `deposit_root` | Root | get_deposit_root after the block |
| 88 | | | Size |

## Type `Eth1Deposit`

One deposit that lantern_eth1_deposit_logs reads from a DepositEvent log.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `block_number` | u64 | The block of the log |
| 8 | `index` | u64 | The deposit's index in the contract |
| 16 | `data` | `DepositData` | 184 bytes: `pubkey` 48, `withdrawal_credentials` 32, `amount` 8, `signature` 96 |
| 200 | | | Size |

## Type `DepositTree`

The deposit tree of the deposit contract, as the eth1 follower keeps it.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `count` | u64 | The leaves pushed |
| 8 | `branch` | `DEPOSIT_CONTRACT_TREE_DEPTH` Roots | The deposit contract's `branch`: at level i the root of the last whole subtree of 2^i leaves |
| 8 + 32 * `DEPOSIT_CONTRACT_TREE_DEPTH` | | | Size |

## Test vectors

- Lantern's cases `<preset>-phase0-eth1-<kind>.bin` (`requests`, `block`, `logs`, `tree`), made by tests/generator/eth1.py:
  - Requests: block numbers, `latest`, address and block ranges, and the JSON the rules above give.
  - Blocks: eth_getBlockByNumber results that Python's `json` module writes with several spacings and member orders and with members the parser skips; texts with a bad `QUANTITY` or `DATA`.
  - Logs: arrays of logs whose `data` is the ABI encoding of random `DepositData` and indices, with `removed` absent and false; logs with `removed` true, another topic, a non canonical encoding, and bad JSON.
  - The tree: random `DepositData` lists; lantern_deposit_leaf of each must be the spec's hash_tree_root; after each push the root must be the spec's (hash_tree_root of the list, as process_deposit checks it), and each proof of a leaf below a count must pass is_valid_merkle_branch against the root of the first `count` leaves.

## Results

<!-- CI generates the tick table for each function here. -->

### `lantern_eth_get_block_by_number`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_eth_get_deposit_logs`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_eth1_block`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_eth1_deposit_logs`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_deposit_leaf`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_deposit_tree_push`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_deposit_tree_root`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_deposit_proof`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |
