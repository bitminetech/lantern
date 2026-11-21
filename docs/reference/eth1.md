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

### Types

- [`Eth1Block`](#type-eth1block): an eth1 block as get_eth1_vote reads it.
- [`Eth1Deposit`](#type-eth1deposit): one deposit of a `DepositEvent` log.
- [`DepositTree`](#type-deposittree): the deposit contract's incremental Merkle tree.

## Spec

- Document: [consensus-specs v1.7.0-beta.4](https://github.com/ethereum/consensus-specs/tree/aa16bb4c156184e9548a997d53efaf2a228a6304/specs): phase0 `deposit-contract.md`, `validator.md` (Eth1 Data, Deposits) and `beacon-chain.md` (`DepositData`, `DEPOSIT_CONTRACT_TREE_DEPTH`, process_deposit's is_valid_merkle_branch); electra `validator.md`.
- Document: [execution-apis 981aa66](https://github.com/ethereum/execution-apis/tree/981aa66d79364be8322a9c358aaf0a571cca0873/src/engine) `common.md`: the Engine API connection also serves `eth_getBlockByNumber` and `eth_getLogs`, with the same JWT.
- Document: the deposit contract's source, [solidity-deposit-contract](https://github.com/ethereum/solidity-deposit-contract/blob/master/deposit_contract.sol), which `deposit-contract.md` names: the `DepositEvent` log, its little endian `amount` and `index`, and get_deposit_root.
- Document: the Solidity ABI encoding of a log's `data`: five dynamic `bytes` values.

## Common rules

- As in [helpers.md](helpers.md#common-rules).
- JSON is written compact, as in [engine-api.md](engine-api.md#common-rules): a `QUANTITY` is lowercase hex with no leading zeros, `0x0` for zero; `DATA` is lowercase hex, two digits a byte.
- The `DepositEvent` topic: keccak256 of `DepositEvent(bytes,bytes,bytes,bytes,bytes)`, `0x649bbc62d0e31342afea4e5cd82d4049e7e1ee912fc0889aa790803be39038c5`.
- A leaf of the deposit tree is hash_tree_root of the deposit's `DepositData`.
- Every function is in the common object of the core (asm/core/<ISA>/eth1.s), and its symbol is its name. Every u64 argument is passed by its address.

## Test vectors

- Lantern's cases `<preset>-phase0-eth1-<kind>.bin` (`requests`, `block`, `logs`, `tree`), made by tests/generator/eth1.py:
  - Requests: block numbers, `latest`, address and block ranges, and the JSON the rules above give.
  - Blocks: eth_getBlockByNumber results that Python's `json` module writes with several spacings and member orders and with members the parser skips; texts with a bad `QUANTITY` or `DATA`.
  - Logs: arrays of logs whose `data` is the ABI encoding of random `DepositData` and indices, with `removed` absent and false; logs with `removed` true, another topic, a non canonical encoding, and bad JSON.
  - The tree: random `DepositData` lists; lantern_deposit_leaf of each must be the spec's hash_tree_root; after each push the root must be the spec's (hash_tree_root of the list, as process_deposit checks it), and each proof of a leaf below a count must pass is_valid_merkle_branch against the root of the first `count` leaves.

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

## Type `Eth1Block`

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `number` | u64 | The block's number |
| 8 | `timestamp` | u64 | |
| 16 | `deposit_count` | u64 | The deposits of the contract after the block |
| 24 | `hash` | Hash32 | |
| 56 | `deposit_root` | Root | get_deposit_root after the block |
| 88 | | | Size |

## Type `Eth1Deposit`

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `block_number` | u64 | The block of the log |
| 8 | `index` | u64 | The deposit's index in the contract |
| 16 | `data` | `DepositData` | 184 bytes: `pubkey` 48, `withdrawal_credentials` 32, `amount` 8, `signature` 96 |
| 200 | | | Size |

## Type `DepositTree`

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `count` | u64 | The leaves pushed |
| 8 | `branch` | `DEPOSIT_CONTRACT_TREE_DEPTH` Roots | The deposit contract's `branch`: at level i the root of the last whole subtree of 2^i leaves |
| 8 + 32 * `DEPOSIT_CONTRACT_TREE_DEPTH` | | | Size |

## Results

<!-- CI generates the tick table for each function here. -->
