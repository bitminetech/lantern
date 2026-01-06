# Lantern C Code Standards

This document defines the coding standards for the Lantern codebase. All C code must follow these conventions to ensure consistency, readability, and maintainability.

---

## Table of Contents

1. [Formatting](#formatting)
2. [Naming Conventions](#naming-conventions)
3. [Documentation](#documentation)
4. [Functions](#functions)
5. [Error Handling](#error-handling)
6. [Memory Management](#memory-management)
7. [Header Files](#header-files)
8. [Thread Safety](#thread-safety)
9. [Constants and Macros](#constants-and-macros)
10. [Control Flow](#control-flow)
11. [Integer Safety](#integer-safety)
12. [Array and Buffer Safety](#array-and-buffer-safety)
13. [Struct Initialization](#struct-initialization)
14. [Static Analysis and Compiler Warnings](#static-analysis-and-compiler-warnings)
15. [Assertions and Invariants](#assertions-and-invariants)
16. [Portability](#portability)
17. [Global and Static Variables](#global-and-static-variables)
18. [Bit Manipulation](#bit-manipulation)
19. [Testing](#testing)
20. [Modular Design](#modular-design)

---

## Modular Design

### Module Structure

Each module must be self-contained with clear boundaries:

```
src/
├── consensus/              # Module directory
│   ├── state.c            # Implementation
│   ├── state_internal.h   # Internal declarations (not public)
│   ├── fork_choice.c
│   └── ...
include/
└── lantern/
    └── consensus/          # Public API
        ├── state.h        # Public interface
        ├── fork_choice.h
        └── ...
```

### Single Responsibility

Each module and file should have ONE clear purpose:

```c
// CORRECT - focused modules
src/consensus/state.c           // State transitions only
src/consensus/fork_choice.c     // Fork choice only
src/consensus/hash.c            // Hashing only

// INCORRECT - mixed responsibilities
src/consensus/state_and_sync.c  // Don't combine unrelated concerns
```

### File Size Limits

| File Type | Maximum Lines | Action if Exceeded |
|-----------|---------------|-------------------|
| Source (.c) | 1,500 | Split into focused sub-modules |
| Header (.h) | 500 | Split by type/functionality |
| Internal header | 800 | Consider restructuring module |

When a file exceeds limits, split by functionality:

```
// Before: client.c (7,900 lines) - TOO LARGE

// After: Split by responsibility
client.c           (1,500 lines) - Core init/shutdown
client_sync.c      (1,500 lines) - Block synchronization
client_validator.c (800 lines)   - Validator duties
client_network.c   (1,200 lines) - Network management
client_internal.h  (800 lines)   - Shared internal declarations
```

### Dependency Direction

Dependencies must flow DOWN the hierarchy, never up:

```
                    ┌─────────────┐
                    │   core/     │  Depends on ALL below
                    │  client.c   │
                    └──────┬──────┘
                           │
         ┌─────────────────┼─────────────────┐
         ▼                 ▼                 ▼
   ┌───────────┐    ┌───────────┐    ┌───────────┐
   │ consensus │    │ networking│    │  storage  │
   └─────┬─────┘    └─────┬─────┘    └─────┬─────┘
         │                │                │
         └────────────────┼────────────────┘
                          ▼
                   ┌───────────┐
                   │  support  │  No dependencies (stdlib only)
                   │ log, time │
                   └───────────┘
```

**Rules:**
- `support/` depends only on standard library
- `consensus/` may depend on `support/`
- `networking/` may depend on `support/`, `consensus/`
- `core/` may depend on everything
- **NEVER** create circular dependencies

### Interface Segregation

Headers should expose minimal interfaces:

```c
// CORRECT - minimal public interface
// include/lantern/consensus/state.h
int lantern_state_init(LanternState *state);
int lantern_state_process_block(LanternState *state, const LanternBlock *block);
void lantern_state_reset(LanternState *state);

// Internal helpers stay in implementation or internal header
// src/consensus/state_internal.h (NOT in include/)
static int validate_block_header(const LanternBlockHeader *header);
static void update_justified_checkpoint(LanternState *state);
```

### Opaque Types

Hide implementation details using opaque pointers:

```c
// PUBLIC HEADER - include/lantern/consensus/state.h
// Forward declaration only - size unknown to users
struct lantern_state;
typedef struct lantern_state LanternState;

// Users can only use pointers, not access fields directly
LanternState *lantern_state_create(void);
uint64_t lantern_state_get_slot(const LanternState *state);

// IMPLEMENTATION - src/consensus/state.c
// Full definition only visible to implementation
struct lantern_state
{
    uint64_t slot;
    LanternCheckpoint justified;
    LanternCheckpoint finalized;
    // ... internal fields hidden from users
};
```

### Internal Headers

Use `*_internal.h` headers for cross-file sharing within a module:

```c
// src/core/client_internal.h
#ifndef LANTERN_CLIENT_INTERNAL_H
#define LANTERN_CLIENT_INTERNAL_H

// NOT part of public API - only for use within src/core/

/**
 * Lock ordering (acquire in this order to prevent deadlocks):
 * 1. state_lock
 * 2. pending_lock
 * 3. validator_lock
 */

// Shared types between client_*.c files
struct lantern_peer_status_entry
{
    char peer_id[128];
    bool has_status;
    // ...
};

// Internal functions shared between client_*.c files
void connection_counter_reset(struct lantern_client *client);
int initialize_fork_choice(struct lantern_client *client);

#endif
```

### Callback Interfaces

Use callbacks for dependency inversion:

```c
// CORRECT - module defines callback interface, doesn't know caller
// include/lantern/networking/reqresp_service.h
struct lantern_reqresp_callbacks
{
    void *context;                                           /**< Opaque context */
    int (*build_status)(void *ctx, LanternStatus *out);     /**< Build status msg */
    int (*handle_block)(void *ctx, const LanternBlock *blk); /**< Handle received block */
};

int lantern_reqresp_start(
    struct lantern_reqresp_service *service,
    const struct lantern_reqresp_callbacks *callbacks);

// INCORRECT - networking module directly calls client functions
#include "lantern/core/client.h"  // Creates circular dependency!
lantern_client_handle_block(client, block);
```

### Module Initialization Order

Document and enforce initialization order:

```c
/**
 * Module initialization order:
 * 1. support/log      - Logging must be first
 * 2. support/time     - Time utilities
 * 3. storage          - Load persisted state
 * 4. consensus/state  - Initialize from storage
 * 5. consensus/fork_choice - Depends on state
 * 6. networking       - Depends on consensus for handlers
 * 7. http/metrics     - Depends on everything for snapshots
 *
 * Shutdown order is REVERSE of initialization.
 */
int lantern_init(struct lantern_client *client)
{
    // Follow documented order...
}
```

### Testing Modularity

Modules must be testable in isolation:

```c
// CORRECT - module can be tested without full client
// tests/unit/test_fork_choice.c
void test_fork_choice_updates_head(void)
{
    LanternForkChoice fc;
    lantern_fork_choice_init(&fc);

    // Test fork choice in isolation
    LanternBlock block = create_test_block(1);
    lantern_fork_choice_on_block(&fc, &block);

    ASSERT_EQ(fc.head_slot, 1);
    lantern_fork_choice_reset(&fc);
}

// If a module CANNOT be tested without initializing the entire client,
// it has too many dependencies and should be refactored.
```

### Avoiding God Objects

No single struct should know about everything:

```c
// INCORRECT - "god object" that touches all modules
struct lantern_client
{
    // 57 fields spanning ALL modules
    LanternState state;
    LanternForkChoice fork_choice;
    struct lantern_network network;
    struct lantern_storage storage;
    struct lantern_http_server http;
    struct lantern_metrics metrics;
    // ... everything in one place
};

// CORRECT - client composes focused sub-systems
struct lantern_client
{
    struct lantern_client_config config;     /**< Configuration */
    struct lantern_consensus *consensus;     /**< Consensus subsystem */
    struct lantern_network *network;         /**< Network subsystem */
    struct lantern_api *api;                 /**< HTTP/metrics subsystem */
};

// Each subsystem is independently manageable
struct lantern_consensus
{
    LanternState state;
    LanternForkChoice fork_choice;
    pthread_mutex_t lock;
};
```

### Change Impact Analysis

Before adding code, consider:

1. **Does this change affect only ONE module?** If not, reconsider design
2. **Can this be tested without other modules?** If not, extract interface
3. **Does this create a new dependency?** If so, verify direction is correct
4. **Will this file exceed size limits?** If so, split first

### Module Checklist

When creating or modifying a module:

- [ ] Single, clear responsibility documented in file header
- [ ] Public API in `include/lantern/module/`
- [ ] Internal declarations in `src/module/*_internal.h`
- [ ] Dependencies only on lower-level modules
- [ ] No circular includes
- [ ] Can be unit tested in isolation
- [ ] File under size limits
- [ ] Initialization/shutdown order documented

---

## Formatting

### Brace Style (Allman Style)

Braces always appear on their own line:

```c
// CORRECT
int lantern_state_process_block(LanternState *state, const LanternBlock *block)
{
    if (block->slot <= state->slot)
    {
        return -1;
    }

    for (size_t i = 0; i < block->attestation_count; i++)
    {
        process_attestation(state, &block->attestations[i]);
    }

    return 0;
}

// INCORRECT
int lantern_state_process_block(LanternState *state, const LanternBlock *block) {
    if (block->slot <= state->slot) {
        return -1;
    }
    // ...
}
```

### Indentation

- Use 4 spaces for indentation (no tabs)
- Continuation lines are indented by 4 additional spaces

```c
// CORRECT
int result = lantern_very_long_function_name(
    first_argument,
    second_argument,
    third_argument
);

// CORRECT - aligned parameters
int result = lantern_very_long_function_name(first_argument,
                                             second_argument,
                                             third_argument);
```

### Line Length

- Maximum line length: 100 characters
- Prefer breaking before operators

```c
// CORRECT
bool is_valid = (checkpoint->slot > finalized_slot)
    && (checkpoint->root != ZERO_ROOT)
    && lantern_verify_signature(checkpoint);
```

### Spacing

- One space after keywords (`if`, `for`, `while`, `switch`, `return`)
- No space between function name and opening parenthesis
- One space around binary operators
- No space after unary operators
- No trailing whitespace

```c
// CORRECT
if (slot > 0)
{
    result = a + b * c;
    pointer = &value;
    negated = !flag;
}

// INCORRECT
if(slot > 0){
    result = a+b*c;
    pointer = & value;
}
```

### Blank Lines

- Two blank lines between function definitions
- One blank line between logical sections within a function
- No multiple consecutive blank lines

```c
static int helper_function(void)
{
    return 0;
}


int lantern_public_function(void)
{
    // Initialization section
    int result = 0;
    LanternState *state = NULL;

    // Processing section
    state = lantern_state_create();
    if (!state)
    {
        return -1;
    }

    // Cleanup section
    lantern_state_destroy(state);
    return result;
}
```

---

## Naming Conventions

### General Rules

| Element | Convention | Example |
|---------|------------|---------|
| Functions (public) | `lantern_module_action` | `lantern_state_process_block` |
| Functions (static) | `snake_case` | `process_attestation` |
| Types (structs) | `lantern_module_name` | `struct lantern_client` |
| Types (typedef) | `PascalCase` | `LanternCheckpoint` |
| Constants | `SCREAMING_SNAKE_CASE` | `LANTERN_MAX_VALIDATORS` |
| Variables | `snake_case` | `block_root` |
| Macros | `SCREAMING_SNAKE_CASE` | `LANTERN_ASSERT` |
| Enums | `LANTERN_MODULE_VALUE` | `LANTERN_ERR_INVALID_SLOT` |

### Public API Prefix

All public symbols must be prefixed with `lantern_`:

```c
// Public API
int lantern_client_init(struct lantern_client *client);
void lantern_client_shutdown(struct lantern_client *client);

// Internal/static functions - no prefix required
static int validate_block_header(const LanternBlockHeader *header);
static void update_finalized_checkpoint(LanternState *state);
```

### Type Definitions

```c
// Opaque struct (forward declaration in header)
struct lantern_client;

// Typedef for simple types used frequently
typedef struct
{
    uint8_t bytes[32];
} LanternRoot;

typedef struct
{
    LanternRoot root;
    uint64_t slot;
} LanternCheckpoint;
```

### Boolean Variables and Functions

- Boolean variables should read as assertions
- Functions returning bool should be named as questions

```c
// CORRECT
bool is_valid;
bool has_signature;
bool should_process;

bool lantern_block_is_valid(const LanternBlock *block);
bool lantern_state_has_validator(const LanternState *state, uint64_t index);

// INCORRECT
bool valid;
bool signature;
bool process;
```

---

## Documentation

### File Headers

Every source file must begin with a file header:

```c
/**
 * @file state.c
 * @brief Consensus state management and transitions
 * @spec subspecs/containers/state/state.py
 *
 * Implements the Lean consensus state machine including:
 * - Block processing and validation
 * - Attestation aggregation
 * - Justification and finalization
 */
```

### Function Documentation

**All functions must have a Doxygen-style comment.** This ensures visual consistency and provides uniform documentation across the codebase.

#### Public Functions (Full Documentation)

Public functions require comprehensive documentation:

```c
/**
 * Process a signed block and update consensus state.
 *
 * @spec State.state_transition() in subspecs/containers/state/state.py
 *
 * Validates the block against current state, processes all attestations,
 * and updates justification/finalization checkpoints.
 *
 * @param state   Consensus state to update (modified in place)
 * @param block   Signed block to process
 * @param flags   Processing flags (LANTERN_VERIFY_SIG, LANTERN_SKIP_STATE_ROOT)
 *
 * @return 0 on success
 * @return -1 on invalid block (slot, parent, proposer)
 * @return -2 on signature verification failure
 * @return -3 on state root mismatch
 *
 * @note Thread safety: Caller must hold state_lock
 * @see lantern_state_process_block_header()
 * @see lantern_state_process_attestations()
 */
int lantern_state_transition(
    LanternState *state,
    const LanternSignedBlock *block,
    uint32_t flags
);
```

#### Static/Internal Functions (Brief Documentation)

Static and internal helper functions require at minimum a brief one-line Doxygen comment:

```c
/**
 * @brief Frees all peers in the list.
 */
static void free_peer_list(peer_list_t *list)
{
    // ...
}


/**
 * @brief Returns current slot based on genesis time.
 */
static uint64_t get_current_slot(void)
{
    // ...
}


/**
 * @brief Validates block header fields.
 *
 * @param header Block header to validate
 * @return true if valid, false otherwise
 */
static bool validate_block_header(const LanternBlockHeader *header)
{
    // ...
}
```

For more complex internal functions, expand as needed with `@param`, `@return`, and `@note`.

### Struct Field Documentation

All struct fields must be documented:

```c
/**
 * Validator attestation (vote) data.
 * @spec AttestationData in subspecs/containers/attestation/attestation.py
 */
typedef struct
{
    uint64_t validator_id;    /**< Index of the attesting validator */
    uint64_t slot;            /**< Slot being attested to */
    LanternCheckpoint head;   /**< Validator's view of the chain head */
    LanternCheckpoint target; /**< Target checkpoint for justification */
    LanternCheckpoint source; /**< Source (previously justified) checkpoint */
} LanternVote;
```

### Inline Comments

- Use `//` for single-line comments
- Use `/* */` for multi-line comments
- Comments should explain "why", not "what"

```c
// CORRECT - explains why
// Skip genesis block as it has no parent to validate against
if (block->slot == 0)
{
    return 0;
}

// INCORRECT - explains what (obvious from code)
// Check if slot is zero
if (block->slot == 0)
{
    return 0;
}
```

### Spec References

Functions implementing spec behavior must reference the spec:

```c
/**
 * @spec Store._compute_lmd_ghost_head() in subspecs/forkchoice/store.py
 *
 * Implements LMD GHOST fork choice:
 * 1. Start from justified checkpoint
 * 2. Accumulate validator weights from attestations
 * 3. Greedily select heaviest child at each fork
 * 4. Break ties lexicographically by block hash
 */
static LanternRoot compute_head(const LanternForkChoice *fc);
```

---

## Functions

### Function Length

- Functions should not exceed 100 lines (excluding comments)
- If longer, split into well-named helper functions

### Parameter Order

1. Context/state (modified in place)
2. Input parameters (const)
3. Output parameters (pointers)

```c
// CORRECT
int lantern_state_get_proposer(
    const LanternState *state,      // Context (input)
    uint64_t slot,                  // Input parameter
    uint64_t *out_proposer_index    // Output parameter
);
```

### Return Values

- Return `0` for success, negative values for errors
- Use specific error codes, not just `-1`
- Document all possible return values

```c
typedef enum
{
    LANTERN_OK = 0,
    LANTERN_ERR_INVALID_PARAM = -1,
    LANTERN_ERR_OUT_OF_MEMORY = -2,
    LANTERN_ERR_INVALID_SLOT = -3,
    LANTERN_ERR_INVALID_BLOCK = -4,
    LANTERN_ERR_SIGNATURE_FAILED = -5,
    LANTERN_ERR_STATE_ROOT_MISMATCH = -6,
} lantern_error_t;
```

### Single Return Point (Preferred)

Use `goto cleanup` for complex functions with multiple exit points:

```c
int lantern_process_block(LanternState *state, const LanternBlock *block)
{
    int result = LANTERN_OK;
    uint8_t *buffer = NULL;
    LanternRoot *roots = NULL;

    buffer = malloc(BUFFER_SIZE);
    if (!buffer)
    {
        result = LANTERN_ERR_OUT_OF_MEMORY;
        goto cleanup;
    }

    roots = calloc(block->attestation_count, sizeof(LanternRoot));
    if (!roots)
    {
        result = LANTERN_ERR_OUT_OF_MEMORY;
        goto cleanup;
    }

    // Process block...
    result = process_attestations(state, block, buffer, roots);

cleanup:
    free(roots);
    free(buffer);
    return result;
}
```

---

## Error Handling

### Check All Return Values

```c
// CORRECT
int result = lantern_state_init(state);
if (result != LANTERN_OK)
{
    lantern_log_error("state", NULL, "Failed to initialize state: %d", result);
    return result;
}

// INCORRECT
lantern_state_init(state);  // Ignoring return value
```

### Check All Allocations

```c
// CORRECT
char *buffer = malloc(size);
if (!buffer)
{
    return LANTERN_ERR_OUT_OF_MEMORY;
}

// INCORRECT
char *buffer = malloc(size);
strcpy(buffer, source);  // May crash if malloc failed
```

### Validate Input Parameters

Public functions must validate inputs:

```c
int lantern_state_process_block(LanternState *state, const LanternBlock *block)
{
    if (!state || !block)
    {
        return LANTERN_ERR_INVALID_PARAM;
    }

    if (block->slot == 0)
    {
        return LANTERN_ERR_INVALID_SLOT;
    }

    // Continue processing...
}
```

---

## Memory Management

### Ownership Rules

- Functions that allocate must document who owns the memory
- Use `_create` suffix for functions that allocate
- Use `_destroy` suffix for functions that deallocate
- Use `_init` / `_reset` for functions operating on caller-owned memory

```c
// Allocates and returns new state (caller owns)
LanternState *lantern_state_create(void);

// Frees state allocated by _create
void lantern_state_destroy(LanternState *state);

// Initializes caller-owned state struct
int lantern_state_init(LanternState *state, const LanternConfig *config);

// Resets state to initial values (does not free)
void lantern_state_reset(LanternState *state);
```

### Null Safety

```c
// CORRECT - safe to call with NULL
void lantern_state_destroy(LanternState *state)
{
    if (!state)
    {
        return;
    }

    free(state->validators);
    free(state->block_roots);
    free(state);
}
```

### Use sizeof(*ptr) Pattern

```c
// CORRECT - type changes automatically tracked
LanternValidator *validators = calloc(count, sizeof(*validators));

// INCORRECT - must update if type changes
LanternValidator *validators = calloc(count, sizeof(LanternValidator));
```

### Clear Sensitive Data

```c
// Clear private keys before freeing
lantern_secure_memzero(secret_key, sizeof(*secret_key));
free(secret_key);
```

---

## Header Files

### Include Guards

```c
#ifndef LANTERN_CONSENSUS_STATE_H
#define LANTERN_CONSENSUS_STATE_H

// Content...

#endif /* LANTERN_CONSENSUS_STATE_H */
```

### Include Order

1. Corresponding header (for .c files)
2. System headers (alphabetical)
3. Third-party headers (alphabetical)
4. Project headers (alphabetical)

```c
// state.c
#include "lantern/consensus/state.h"

#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>

#include <pthread.h>

#include "lantern/consensus/fork_choice.h"
#include "lantern/consensus/hash.h"
#include "lantern/support/log.h"
```

### C++ Compatibility

```c
#ifndef LANTERN_STATE_H
#define LANTERN_STATE_H

#ifdef __cplusplus
extern "C" {
#endif

// Declarations...

#ifdef __cplusplus
}
#endif

#endif /* LANTERN_STATE_H */
```

### Forward Declarations

Use forward declarations to minimize header dependencies:

```c
// In header - forward declare instead of including
struct lantern_client;

int lantern_state_attach_client(LanternState *state, struct lantern_client *client);
```

---

## Thread Safety

### Document Thread Safety

```c
/**
 * @note Thread safety: This function is thread-safe
 */
uint64_t lantern_slot_clock_get_current(const LanternSlotClock *clock);

/**
 * @note Thread safety: Caller must hold client->state_lock
 */
static void update_justified_checkpoint(struct lantern_client *client);
```

### Lock Ordering

Document lock acquisition order to prevent deadlocks:

```c
/**
 * Lock ordering (acquire in this order to prevent deadlocks):
 * 1. client->state_lock
 * 2. client->network_lock
 * 3. client->validator_lock
 */
```

### Use RAII-like Patterns

```c
// Lock guard pattern
#define WITH_LOCK(mutex) \
    for (int _once = (pthread_mutex_lock(mutex), 1); \
         _once; \
         _once = (pthread_mutex_unlock(mutex), 0))

// Usage
WITH_LOCK(&client->state_lock)
{
    update_state(client);
}
```

---

## Constants and Macros

### Prefer const over #define

```c
// CORRECT - typed, scoped, debuggable
static const size_t MAX_VALIDATORS = 4096;
static const uint64_t SECONDS_PER_SLOT = 4;

// AVOID - untyped, global namespace
#define MAX_VALIDATORS 4096
```

### Macro Safety

- Wrap macro arguments in parentheses
- Wrap entire macro in `do { } while(0)` for statement macros

```c
// CORRECT
#define LANTERN_MIN(a, b) (((a) < (b)) ? (a) : (b))

#define LANTERN_LOG_ERROR(fmt, ...) \
    do { \
        lantern_log_error(__FILE__, __LINE__, fmt, ##__VA_ARGS__); \
    } while (0)

// INCORRECT - operator precedence issues
#define LANTERN_MIN(a, b) a < b ? a : b
```

### Enum for Related Constants

```c
// CORRECT - grouped, typed
typedef enum
{
    LANTERN_INTERVAL_PROPOSAL = 0,
    LANTERN_INTERVAL_ATTESTING = 1,
    LANTERN_INTERVAL_SAFE_TARGET = 2,
    LANTERN_INTERVAL_ACCEPTANCE = 3,
    LANTERN_INTERVALS_PER_SLOT = 4,
} lantern_interval_t;

// AVOID - unrelated constants scattered
#define INTERVAL_PROPOSAL 0
#define INTERVAL_ATTESTING 1
```

---

## Control Flow

### Early Return for Guards

```c
// CORRECT - early returns reduce nesting
int lantern_process_attestation(LanternState *state, const LanternVote *vote)
{
    if (!state || !vote)
    {
        return LANTERN_ERR_INVALID_PARAM;
    }

    if (vote->slot > state->slot)
    {
        return LANTERN_ERR_INVALID_SLOT;
    }

    // Main logic at base indentation level
    return process_vote(state, vote);
}

// AVOID - deep nesting
int lantern_process_attestation(LanternState *state, const LanternVote *vote)
{
    if (state && vote)
    {
        if (vote->slot <= state->slot)
        {
            // Deeply nested main logic
        }
    }
}
```

### Switch Statements

```c
switch (message_type)
{
    case LANTERN_MSG_STATUS:
        result = handle_status(client, message);
        break;

    case LANTERN_MSG_BLOCK:
        result = handle_block(client, message);
        break;

    case LANTERN_MSG_ATTESTATION:
        result = handle_attestation(client, message);
        break;

    default:
        lantern_log_warn("network", NULL, "Unknown message type: %d", message_type);
        result = LANTERN_ERR_INVALID_PARAM;
        break;
}
```

### Avoid Magic Numbers

```c
// CORRECT
static const size_t CHECKPOINT_HISTORY_SIZE = 256;

if (history_index < CHECKPOINT_HISTORY_SIZE)
{
    // ...
}

// INCORRECT
if (history_index < 256)
{
    // ...
}
```

---

## Integer Safety

### Type Selection

| Use Case | Type | Rationale |
|----------|------|-----------|
| Array indices, sizes | `size_t` | Matches `sizeof`, `malloc`, standard library |
| Loop counters (small) | `size_t` | Consistent with array indexing |
| Slot numbers, timestamps | `uint64_t` | Spec-defined, large range needed |
| Validator indices | `uint64_t` | Spec-defined |
| Byte counts | `size_t` | Standard for memory operations |
| Error codes | `int` | Convention for return values |
| Boolean flags | `bool` | From `<stdbool.h>` |

### Overflow Prevention

Check for overflow BEFORE performing arithmetic:

```c
// CORRECT - check before addition
if (a > SIZE_MAX - b)
{
    return LANTERN_ERR_OVERFLOW;
}
size_t sum = a + b;

// CORRECT - check before multiplication
if (b != 0 && a > SIZE_MAX / b)
{
    return LANTERN_ERR_OVERFLOW;
}
size_t product = a * b;

// INCORRECT - overflow already happened
size_t sum = a + b;
if (sum < a)  // Too late!
{
    return LANTERN_ERR_OVERFLOW;
}
```

### Safe Casting

```c
// CORRECT - validate before narrowing cast
if (value > UINT32_MAX)
{
    return LANTERN_ERR_OVERFLOW;
}
uint32_t narrow = (uint32_t)value;

// CORRECT - use explicit cast for intentional truncation
uint8_t byte = (uint8_t)(value & 0xFF);

// INCORRECT - implicit narrowing without check
uint32_t narrow = large_value;  // May truncate silently
```

### Comparison Safety

```c
// CORRECT - same types in comparison
if (index < array_length)

// AVOID - mixed signed/unsigned comparison
int i = get_index();
if (i < array_length)  // Warning: comparison of int and size_t

// CORRECT - cast after validation
int i = get_index();
if (i >= 0 && (size_t)i < array_length)
```

---

## Array and Buffer Safety

### Bounds Checking

Always validate indices before array access:

```c
// CORRECT
if (index >= array_length)
{
    return LANTERN_ERR_OUT_OF_BOUNDS;
}
return array[index];

// INCORRECT - no bounds check
return array[index];
```

### Safe String Functions

Always use size-limited string functions:

```c
// CORRECT
char buffer[128];
int written = snprintf(buffer, sizeof(buffer), "slot=%" PRIu64, slot);
if (written < 0 || (size_t)written >= sizeof(buffer))
{
    // Handle truncation or error
}

// CORRECT - strncpy with explicit null termination
strncpy(dest, src, sizeof(dest) - 1);
dest[sizeof(dest) - 1] = '\0';

// INCORRECT - unbounded
sprintf(buffer, "slot=%" PRIu64, slot);
strcpy(dest, src);
```

### Buffer Size Validation

Validate buffer sizes at function boundaries:

```c
int lantern_encode_block(
    const LanternBlock *block,
    uint8_t *buffer,
    size_t buffer_len,
    size_t *out_written)
{
    if (!block || !buffer || !out_written)
    {
        return LANTERN_ERR_INVALID_PARAM;
    }

    size_t required = calculate_encoded_size(block);
    if (buffer_len < required)
    {
        return LANTERN_ERR_BUFFER_TOO_SMALL;
    }

    // Safe to proceed...
}
```

### Dynamic Array Pattern

Use consistent resize patterns for dynamic arrays:

```c
int lantern_list_ensure_capacity(LanternList *list, size_t required)
{
    if (list->capacity >= required)
    {
        return 0;
    }

    // Grow by 1.5x or to required, whichever is larger
    size_t new_capacity = list->capacity + (list->capacity / 2);
    if (new_capacity < required)
    {
        new_capacity = required;
    }

    // Check for overflow
    if (new_capacity > SIZE_MAX / sizeof(*list->items))
    {
        return LANTERN_ERR_OVERFLOW;
    }

    void *new_items = realloc(list->items, new_capacity * sizeof(*list->items));
    if (!new_items)
    {
        return LANTERN_ERR_OUT_OF_MEMORY;
    }

    list->items = new_items;
    list->capacity = new_capacity;
    return 0;
}
```

---

## Struct Initialization

### Zero Initialization

Use `memset` or designated initializers for complete initialization:

```c
// CORRECT - memset for complete zeroing
LanternState state;
memset(&state, 0, sizeof(state));

// CORRECT - designated initializer (partial, rest zero)
LanternCheckpoint checkpoint = {
    .slot = 0,
    .root = {0}
};

// CORRECT - compound literal for inline initialization
lantern_log_error(
    "client",
    &(const struct lantern_log_metadata){
        .validator = client->node_id,
        .slot = current_slot,
        .has_slot = true
    },
    "error message");

// INCORRECT - uninitialized struct
LanternState state;
state.slot = 0;  // Other fields contain garbage
```

### Init/Reset Functions

Provide paired init/reset functions for complex structs:

```c
// Initialize to default state
void lantern_block_body_init(LanternBlockBody *body)
{
    if (!body)
    {
        return;
    }
    memset(body, 0, sizeof(*body));
    lantern_attestations_init(&body->attestations);
}

// Free internal resources, reset to init state
void lantern_block_body_reset(LanternBlockBody *body)
{
    if (!body)
    {
        return;
    }
    lantern_attestations_reset(&body->attestations);
    memset(body, 0, sizeof(*body));
}
```

### Const Compound Literals

Use `const` compound literals for read-only temporary structs:

```c
// CORRECT - const compound literal
const LanternCheckpoint *genesis = &(const LanternCheckpoint){
    .slot = 0,
    .root = {0}
};

// Use in function calls
process_checkpoint(&(const LanternCheckpoint){.slot = slot, .root = root});
```

---

## Static Analysis and Compiler Warnings

### Required Compiler Flags

All builds must use these warning flags:

```makefile
CFLAGS += -Wall -Wextra -Werror
CFLAGS += -Wshadow                 # Warn on variable shadowing
CFLAGS += -Wconversion             # Warn on implicit conversions
CFLAGS += -Wsign-conversion        # Warn on sign conversion
CFLAGS += -Wformat=2               # Strict format string checking
CFLAGS += -Wstrict-prototypes      # Require full prototypes
CFLAGS += -Wmissing-prototypes     # Warn on missing prototypes
CFLAGS += -Wdouble-promotion       # Warn on float->double promotion
CFLAGS += -Wnull-dereference       # Warn on null pointer dereference
CFLAGS += -Wstack-usage=4096       # Warn on large stack frames
```

### Debug Build Flags

Additional flags for debug builds:

```makefile
DEBUG_CFLAGS += -fsanitize=address,undefined
DEBUG_CFLAGS += -fno-omit-frame-pointer
DEBUG_CFLAGS += -DLANTERN_DEBUG=1
```

### Static Analysis Tools

Code must pass these static analysis tools without warnings:

1. **clang-tidy** with `modernize-*`, `bugprone-*`, `cert-*` checks
2. **cppcheck** with `--enable=all`
3. **scan-build** (Clang static analyzer)

### Suppressing Warnings

When warnings must be suppressed, document why:

```c
// Suppress warning: intentional fallthrough in switch
// FALLTHROUGH
case LANTERN_MSG_LEGACY:

// Suppress warning: unused parameter in callback interface
void callback(void *context, int event)
{
    (void)context;  // Required by interface but unused
    handle_event(event);
}
```

---

## Assertions and Invariants

### Debug Assertions

Use assertions for conditions that should never occur if code is correct:

```c
#include <assert.h>

void process_validated_block(const LanternBlock *block)
{
    // Caller must have validated block is non-NULL
    assert(block != NULL);
    assert(block->slot > 0);  // Genesis handled separately

    // Proceed with processing...
}
```

### Runtime Checks vs Assertions

| Condition | Use |
|-----------|-----|
| External input (network, file, user) | Runtime check with error return |
| Internal invariants | `assert()` |
| Programmer errors (NULL after allocation) | `assert()` |
| Resource exhaustion | Runtime check with error return |

```c
// CORRECT - runtime check for external input
int lantern_process_message(const uint8_t *data, size_t len)
{
    if (!data || len == 0)
    {
        return LANTERN_ERR_INVALID_PARAM;  // Runtime check
    }
    // ...
}

// CORRECT - assertion for internal invariant
static void update_state(LanternState *state)
{
    assert(state != NULL);  // Caller bug if NULL
    assert(state->slot <= state->config.max_slot);  // Invariant
    // ...
}
```

### Invariant Documentation

Document complex invariants:

```c
/**
 * Invariants:
 * - state->slot >= state->finalized_checkpoint.slot
 * - state->justified_checkpoint.slot >= state->finalized_checkpoint.slot
 * - All roots in state->historical_roots are non-zero
 */
struct LanternState
{
    // ...
};
```

---

## Portability

### Platform-Specific Code

Isolate platform-specific code in dedicated sections:

```c
// CORRECT - isolated platform code
#if defined(_WIN32)
#include <windows.h>
static uint64_t get_monotonic_ms(void)
{
    return GetTickCount64();
}
#elif defined(__APPLE__)
#include <mach/mach_time.h>
static uint64_t get_monotonic_ms(void)
{
    // macOS implementation
}
#else
#include <time.h>
static uint64_t get_monotonic_ms(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000 + (uint64_t)ts.tv_nsec / 1000000;
}
#endif
```

### Endianness

Use explicit byte-order functions for network/storage:

```c
// CORRECT - explicit endianness for serialization
static void write_uint64_le(uint8_t *buf, uint64_t value)
{
    buf[0] = (uint8_t)(value);
    buf[1] = (uint8_t)(value >> 8);
    buf[2] = (uint8_t)(value >> 16);
    buf[3] = (uint8_t)(value >> 24);
    buf[4] = (uint8_t)(value >> 32);
    buf[5] = (uint8_t)(value >> 40);
    buf[6] = (uint8_t)(value >> 48);
    buf[7] = (uint8_t)(value >> 56);
}

static uint64_t read_uint64_le(const uint8_t *buf)
{
    return (uint64_t)buf[0]
         | ((uint64_t)buf[1] << 8)
         | ((uint64_t)buf[2] << 16)
         | ((uint64_t)buf[3] << 24)
         | ((uint64_t)buf[4] << 32)
         | ((uint64_t)buf[5] << 40)
         | ((uint64_t)buf[6] << 48)
         | ((uint64_t)buf[7] << 56);
}

// INCORRECT - assumes host endianness
memcpy(buf, &value, sizeof(value));
```

### Compiler Extensions

Avoid compiler-specific extensions, or guard them:

```c
// CORRECT - guarded extension
#if defined(__GNUC__) || defined(__clang__)
#define LANTERN_LIKELY(x)   __builtin_expect(!!(x), 1)
#define LANTERN_UNLIKELY(x) __builtin_expect(!!(x), 0)
#else
#define LANTERN_LIKELY(x)   (x)
#define LANTERN_UNLIKELY(x) (x)
#endif

// CORRECT - C11 feature detection
#if defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L
_Static_assert(sizeof(LanternRoot) == 32, "LanternRoot must be 32 bytes");
#endif
```

---

## Global and Static Variables

### When Globals Are Acceptable

Globals are permitted for:
1. **Metrics/profiling** - Performance counters
2. **Configuration** - Read-only after initialization
3. **Singleton services** - Logging, memory allocators

```c
// ACCEPTABLE - profiling metrics
static struct state_profile_metric g_profile_process_slots;
static struct state_profile_metric g_profile_process_block;

// ACCEPTABLE - cached environment variable
static bool finalization_trace_enabled(void)
{
    static bool initialized = false;
    static bool enabled = false;
    if (!initialized)
    {
        const char *env = getenv("LANTERN_DEBUG_FINALIZATION");
        enabled = env && env[0] != '\0';
        initialized = true;
    }
    return enabled;
}
```

### Naming Globals

Prefix file-scope globals with `g_` or `s_`:

```c
// File-scope global
static struct metrics g_metrics;

// Module-scope global (in header)
extern struct lantern_config g_lantern_config;
```

### Thread Safety for Globals

Document thread safety of global access:

```c
/**
 * Global metrics counters.
 *
 * @note Thread safety: These are updated non-atomically. Reads may see
 *       torn values during updates. Acceptable for approximate metrics.
 */
static uint64_t g_blocks_processed;
static uint64_t g_attestations_received;
```

---

## Bit Manipulation

### Safe Bit Operations

Use explicit masks and shifts:

```c
// CORRECT - explicit mask
uint8_t get_bit(uint8_t byte, size_t bit_index)
{
    assert(bit_index < 8);
    return (byte >> bit_index) & 0x01;
}

void set_bit(uint8_t *byte, size_t bit_index, bool value)
{
    assert(byte != NULL);
    assert(bit_index < 8);
    if (value)
    {
        *byte |= (uint8_t)(1u << bit_index);
    }
    else
    {
        *byte &= (uint8_t)~(1u << bit_index);
    }
}

// INCORRECT - undefined behavior for large shifts
uint64_t mask = 1 << bit_index;  // UB if bit_index >= 32 on 32-bit int
```

### Bitfield Structs

Avoid bitfield structs for serialized data (non-portable):

```c
// AVOID for serialization - implementation-defined layout
struct Flags
{
    unsigned int valid : 1;
    unsigned int processed : 1;
    unsigned int reserved : 6;
};

// CORRECT - explicit bit manipulation for serialization
#define FLAG_VALID     (1u << 0)
#define FLAG_PROCESSED (1u << 1)

uint8_t flags = 0;
flags |= FLAG_VALID;
if (flags & FLAG_PROCESSED) { /* ... */ }
```

### Bitlist Operations

For variable-length bitlists (like justified slots):

```c
static size_t bitlist_byte_index(size_t bit_index)
{
    return bit_index / 8;
}

static size_t bitlist_bit_offset(size_t bit_index)
{
    return bit_index % 8;
}

int bitlist_get(const uint8_t *data, size_t data_len, size_t bit_index, bool *out)
{
    size_t byte_idx = bitlist_byte_index(bit_index);
    if (byte_idx >= data_len)
    {
        return LANTERN_ERR_OUT_OF_BOUNDS;
    }

    size_t bit_off = bitlist_bit_offset(bit_index);
    *out = (data[byte_idx] >> bit_off) & 0x01;
    return 0;
}
```

---

## Testing

### Test File Naming

```
tests/
├── unit/
│   ├── test_state.c           # Unit tests for state.c
│   ├── test_fork_choice.c     # Unit tests for fork_choice.c
│   └── test_ssz.c             # Unit tests for ssz.c
├── integration/
│   ├── test_block_sync.c      # Integration tests for block sync
│   └── test_networking.c      # Integration tests for networking
└── fixtures/
    ├── blocks/                # Test block data
    └── states/                # Test state data
```

### Test Function Naming

```c
// Pattern: test_<module>_<function>_<scenario>
void test_state_process_block_valid_block(void);
void test_state_process_block_invalid_slot(void);
void test_state_process_block_missing_parent(void);
void test_fork_choice_on_block_updates_head(void);
void test_fork_choice_on_attestation_increases_weight(void);
```

### Test Structure

```c
void test_state_process_block_valid_block(void)
{
    // Arrange
    LanternState state;
    lantern_state_init(&state);
    LanternBlock block = create_test_block(/* slot */ 1);

    // Act
    int result = lantern_state_process_block(&state, &block);

    // Assert
    ASSERT_EQ(result, LANTERN_OK);
    ASSERT_EQ(state.slot, 1);
    ASSERT_TRUE(roots_equal(&state.latest_block_header.parent_root, &block.parent_root));

    // Cleanup
    lantern_state_reset(&state);
}
```

### Test Helpers

Create helpers to reduce test boilerplate:

```c
// test_helpers.h
LanternBlock create_test_block(uint64_t slot);
LanternState create_test_state_at_slot(uint64_t slot);
LanternVote create_test_vote(uint64_t validator_id, uint64_t slot);
bool roots_equal(const LanternRoot *a, const LanternRoot *b);

// Assertion macros
#define ASSERT_EQ(actual, expected) \
    do { \
        if ((actual) != (expected)) { \
            test_fail(__FILE__, __LINE__, #actual " != " #expected); \
        } \
    } while (0)

#define ASSERT_TRUE(condition) ASSERT_EQ(!!(condition), 1)
#define ASSERT_FALSE(condition) ASSERT_EQ(!!(condition), 0)
```

---

## Summary Checklist

Before submitting code, verify:

### Formatting
- [ ] Braces on their own lines (Allman style)
- [ ] 4-space indentation, no tabs
- [ ] Lines under 100 characters
- [ ] Two blank lines between functions

### Naming & Documentation
- [ ] Public functions prefixed with `lantern_`
- [ ] All public functions documented with `@spec` reference
- [ ] All struct fields documented
- [ ] Thread safety documented for each function
- [ ] No magic numbers - use named constants

### Safety
- [ ] All return values checked
- [ ] All allocations checked for NULL
- [ ] All array accesses bounds-checked
- [ ] All string operations use size-limited functions
- [ ] Integer overflow checked before arithmetic
- [ ] No implicit narrowing conversions

### Memory
- [ ] Memory ownership clearly documented
- [ ] Init/reset function pairs provided
- [ ] Sensitive data cleared before free

### Quality
- [ ] No compiler warnings with `-Wall -Wextra -Werror`
- [ ] Passes static analysis (clang-tidy, cppcheck)
- [ ] Assertions for internal invariants
- [ ] Runtime checks for external input
- [ ] Platform-specific code properly guarded
