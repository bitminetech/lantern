# QUIC Splay Tree Race Condition Fix

## Issue Summary

The QUIC implementation in c-libp2p was experiencing intermittent SIGSEGV crashes due to a race condition when multiple threads accessed picoquic's internal splay tree data structures concurrently.

## Crash Log

```
[SOCKLOOP CRASH] Caught signal 11 (SIGSEGV)
[SOCKLOOP CRASH] Backtrace (10 frames):
/opt/lantern/lib/libpicoquic-core.so(+0x6843d)[0x7fcbe541943d]
/lib/x86_64-linux-gnu/libc.so.6(+0x42520)[0x7fcbe5c84520]
/opt/lantern/lib/libpicoquic-core.so(+0x5470a)[0x7fcbe540570a]
/opt/lantern/lib/libpicoquic-core.so(picosplay_find+0x43)[0x7fcbe5405ac3]
/opt/lantern/lib/libpicoquic-core.so(picoquic_find_stream+0x32)[0x7fcbe540a292]
/opt/lantern/lib/libpicoquic-core.so(picoquic_set_app_stream_ctx+0x16)[0x7fcbe540fda6]
/opt/lantern/lib/liblibp2p_unified.so(+0x3ed47)[0x7fcbe612fd47]
/opt/lantern/lib/liblibp2p_unified.so(+0x26a2a)[0x7fcbe6117a2a]
/lib/x86_64-linux-gnu/libc.so.6(+0x94ac3)[0x7fcbe5cd6ac3]
/lib/x86_64-linux-gnu/libc.so.6(clone+0x44)[0x7fcbe5d67a74]
```

## Root Cause Analysis

### The Problem

Picoquic uses splay trees internally for:
1. **Connection wake times** (`cnx_wake_tree`) - tracks when connections need to wake up
2. **Stream management** - tracks streams within a connection

Splay trees are **self-adjusting binary search trees** that rotate the accessed node to the root on every operation. This means even a "read" operation like `picosplay_find()` **modifies the tree structure**:

```c
// From picosplay.c - even find() mutates the tree!
picosplay_node_t* picosplay_find(picosplay_tree_t *tree, void *value)
{
    // ... find the node ...
    if(curr != NULL)
        splay(tree, curr);  // Rotates curr to root - MODIFIES TREE!
    return curr;
}
```

### The Race Condition

The crash occurred because:

1. **Thread A (Socket Loop)**: Running in `picoquic_packet_loop_v3`, processing packets and modifying internal data structures (splay trees, streams, etc.)

2. **Thread B (Application)**: Calling `picoquic_set_app_stream_ctx()` which internally calls `picoquic_find_stream()` -> `picosplay_find()`

Both threads access the same splay tree simultaneously:
- Thread A might be in the middle of rotating nodes
- Thread B tries to traverse/rotate the same tree
- Tree pointers become corrupted mid-operation
- SIGSEGV when dereferencing corrupted pointer

### Call Stack Breakdown

```
clone                          <- Thread B spawned
  liblibp2p_unified.so         <- c-libp2p code
    picoquic_set_app_stream_ctx <- Set stream context
      picoquic_find_stream     <- Look up stream in splay tree
        picosplay_find         <- Traverse + splay (MODIFIES TREE)
          SIGSEGV              <- Corrupted tree pointer
```

## The Fix

### Solution: Mutex Synchronization

Added mutex locking around all picoquic API calls that access internal data structures, ensuring only one thread can access them at a time.

### Key Changes in `quic_muxer.c`

1. **`picoquic_set_app_stream_ctx`** - Protected in stream handshake, open, and cleanup paths:

```c
if (cnx && session->quic_mtx)
{
    pthread_mutex_lock(session->quic_mtx);
    picoquic_set_app_stream_ctx(cnx, st->stream_id, NULL);
    pthread_mutex_unlock(session->quic_mtx);
}
```

2. **`picoquic_add_to_stream`** - Protected in write and close operations:

```c
/* Acquire quic_mtx to synchronize with the socket loop thread.
 * This prevents concurrent access to picoquic's internal data structures
 * (especially the cnx_wake_tree splay tree) which are not thread-safe. */
if (session->quic_mtx)
    pthread_mutex_lock(session->quic_mtx);
int rc = picoquic_add_to_stream(cnx, st->stream_id, NULL, 0, 1);
if (session->quic_mtx)
    pthread_mutex_unlock(session->quic_mtx);
```

3. **`picoquic_mark_active_stream`** - Protected in muxer initialization:

```c
/* Acquire quic_mtx before mark_active_stream - it may call reinsert_by_wake_time
 * which modifies the splay tree. Must be synchronized with socket loop thread. */
if (session->quic_mtx)
    pthread_mutex_lock(session->quic_mtx);
(void)picoquic_mark_active_stream(cnx, 0, 1, NULL);
if (session->quic_mtx)
    pthread_mutex_unlock(session->quic_mtx);
```

4. **`quic_session_replay_events`** - Protected when flushing pending events:

```c
if (pending)
{
    /* Acquire quic_mtx before replaying events - the dispatch functions may modify
     * picoquic's internal data structures (splay trees, streams, etc.) which require
     * synchronization with the socket loop thread. */
    if (session->quic_mtx)
        pthread_mutex_lock(session->quic_mtx);
    quic_session_replay_events(session, mx, cnx, pending);
    if (session->quic_mtx)
        pthread_mutex_unlock(session->quic_mtx);
}
```

### Socket Loop Callback Integration

The socket loop thread also needs to acquire the mutex. This is done via lock/unlock callbacks:

```c
// In quic_listener.c - lock callbacks for socket loop
static void quic_listener_lock(void *ctx)
{
    quic_listener_ctx_t *lctx = (quic_listener_ctx_t *)ctx;
    pthread_mutex_lock(&lctx->quic_mtx);
}

static void quic_listener_unlock(void *ctx)
{
    quic_listener_ctx_t *lctx = (quic_listener_ctx_t *)ctx;
    pthread_mutex_unlock(&lctx->quic_mtx);
}
```

### Avoiding Deadlocks

Functions called FROM WITHIN the socket loop callback must NOT lock `quic_mtx` (it's already held):

```c
static quic_stream_ctx_t *quic_accept_inbound_stream(...)
{
    /* NOTE: Do NOT lock quic_mtx here - this function is called from the dispatch callback
     * which runs inside the socket loop. The socket loop already holds quic_mtx via lock_fn.
     * Trying to lock here causes a deadlock. */
    picoquic_set_app_stream_ctx(cnx, stream_id, st);
    // ...
}
```

## Why This Fixes the Crash

### Before Fix

```
Time -->
Thread A (Socket Loop):    [---splay tree rotation---]
Thread B (App Thread):          [---splay find---]
                                      ^
                                      |
                               CRASH: corrupted pointers
```

### After Fix

```
Time -->
Thread A (Socket Loop):    [lock][---splay tree rotation---][unlock]
Thread B (App Thread):                                              [lock][---splay find---][unlock]
                                                                    ^
                                                                    |
                                                             waits for lock
```

The mutex ensures:
1. Only one thread accesses picoquic internals at a time
2. Tree operations complete atomically
3. No corrupted intermediate states are visible to other threads

## Files Modified

- `external/c-libp2p/src/protocol/quic/quic_muxer.c` - Main mutex locking around picoquic calls
- `external/c-libp2p/src/protocol/quic/quic_internal.h` - Added `libp2p__quic_session_get_quic_mtx()`
- `external/c-libp2p/src/protocol/quic/quic_listener.c` - Lock callbacks and protected shutdown
- `external/c-libp2p/src/protocol/quic/protocol_quic.c` - Protected session close

## Protected API Calls

| Function | Risk | Protection |
|----------|------|------------|
| `picoquic_set_app_stream_ctx` | Accesses stream splay tree | mutex |
| `picoquic_add_to_stream` | May call `reinsert_by_wake_time` | mutex |
| `picoquic_reset_stream` | May modify wake tree | mutex |
| `picoquic_mark_active_stream` | May call `reinsert_by_wake_time` | mutex |
| `picoquic_close` | Modifies connection state | mutex |
| `picoquic_delete_cnx` | Removes from wake tree | mutex |
| Socket loop callbacks | All picoquic operations | lock_fn/unlock_fn |

## Testing

After applying this fix, the SIGSEGV crashes in `picosplay_find` no longer occur during normal operation with multiple concurrent QUIC connections.
