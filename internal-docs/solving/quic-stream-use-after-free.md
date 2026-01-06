# Debugging the QUIC Stream Use-After-Free Crash

This document describes the methodology used to identify and fix a race condition causing silent crashes in Lantern's QUIC implementation.

## Initial Symptoms

- Silent crashes with no stack trace or error message
- Lantern process would simply disappear
- Peer nodes would report "Disconnected from peer" shortly after
- Intermittent and difficult to reproduce consistently

## Debugging Strategy

### Step 1: Instrument the Code Path with Printf Statements

Since the crash was silent (no stack trace), the first step was to add printf statements with `fflush(stdout)` to trace execution flow. The key insight is that **the last printf that appears before the crash indicates where the crash occurred**.

Files instrumented:
- `quic_muxer.c` - Added `[QUIC SESSION_CB]` and `[QUIC DISPATCH]` prefixes
- `quic_listener.c` - Added `[QUIC LISTENER]` prefix

Example instrumentation pattern:
```c
printf("[QUIC DISPATCH] entry: mx=%p stream_id=%llu\n", (void *)mx, stream_id);
fflush(stdout);
// ... code ...
printf("[QUIC DISPATCH] done\n");
fflush(stdout);
```

### Step 2: Narrow Down the Crash Location

Initial logs showed the crash was happening somewhere in the QUIC dispatch path. The last log line before disconnect was:

```
[QUIC DISPATCH] scheduling readable
```

With no corresponding `[QUIC DISPATCH] readable scheduled` message, this indicated the crash was inside `quic_stream_schedule_readable()`.

### Step 3: Add Granular Debug Inside the Suspect Function

Added detailed printf statements inside `quic_stream_schedule_readable()` to trace each operation:

```c
printf("[QUIC SCHED_READ] entry: ctx=%p mx=%p\n", (void *)ctx, (void *)mx);
fflush(stdout);
// ...
printf("[QUIC SCHED_READ] loading host from mx=%p\n", (void *)mx);
fflush(stdout);
struct libp2p_host *host = atomic_load_explicit(&mx->host, memory_order_acquire);
printf("[QUIC SCHED_READ] host=%p\n", (void *)host);
fflush(stdout);
// ...
printf("[QUIC SCHED_READ] retaining stream=%p\n", (void *)stream);
fflush(stdout);
```

### Step 4: Identify the Corrupted Pointer

The debug output revealed the smoking gun:

```
[QUIC SCHED_READ] entry: ctx=0xffff2c000d70 mx=0xffff68009a00
[QUIC SCHED_READ] loading host from mx=0xffff68009a00
[QUIC SCHED_READ] host=0xaaaaf5a5eb20
[QUIC SCHED_READ] retaining stream=0x7cf827974b0fb391
```

The `stream` pointer `0x7cf827974b0fb391` is clearly invalid - it's garbage data, not a valid heap pointer. Compare to valid pointers in the same log like `0xffff2c000d70` or `0xaaaaf5a5eb20`.

### Step 5: Trace the Pointer History

Searched the logs for earlier uses of the same `ctx` (`0xffff2c000d70`):

```
Line 2225: [QUIC SCHED_READ] retaining stream=0xffff2c000fc0  ← Valid
Line 2297: [QUIC SCHED_READ] retaining stream=0xffff2c000fc0  ← Valid
Line 2414: [QUIC SCHED_READ] retaining stream=0x7cf827974b0fb391  ← Corrupted!
```

The same `ctx` had a valid `stream` pointer earlier, but it became corrupted by the third call.

### Step 6: Analyze the Interleaving Pattern

Looking at the log lines around the crash revealed interleaved execution from multiple threads:

```
2370: [QUIC DISPATCH] found stream st=0xffff2c000d70 ...
2371: [QUIC DISPATCH] locking stream st=0xffff2c000d70
2372: [QUIC DISPATCH] locked stream, pushing bytes length=32
2373: [QUIC SCHED_READ] entry: ctx=0xffff14000d10 ...  ← Different thread!
...   (Thread B runs through its entire dispatch)
2408: [QUIC SESSION_CB] done                           ← Thread B finishes
2409: [QUIC DISPATCH] unlocked stream ...              ← Thread A resumes
2410: [QUIC DISPATCH] scheduling readable
2411: [QUIC SCHED_READ] entry: ctx=0xffff2c000d70 ...
2414: [QUIC SCHED_READ] retaining stream=0x7cf827974b0fb391  ← Crash!
```

Thread A was interrupted between unlocking the stream and calling `schedule_readable`. During that time, Thread B ran completely through another dispatch cycle.

### Step 7: Identify the Race Condition

Examining the code flow in `quic_session_dispatch()`:

```c
pthread_mutex_lock(&st->lock);
// ... modify state ...
pthread_mutex_unlock(&st->lock);  // Line 1959

// ... other code ...

if (handshake_done_now && st->stream && (length > 0 || !already_fin))  // Line 1969
{
    quic_stream_schedule_readable(st, mx);  // st->stream read WITHOUT lock!
}
```

The problem: `st->stream` was being read **after** releasing `st->lock`. Another thread could free or modify `st->stream` between the unlock and the read.

## The Fix

Changed `quic_stream_schedule_readable()` to accept the stream pointer as a parameter, and capture `st->stream` while still holding the lock:

```c
// Before (broken):
pthread_mutex_unlock(&st->lock);
if (handshake_done_now && st->stream && ...)
    quic_stream_schedule_readable(st, mx);

// After (fixed):
stream_for_readable = st->stream;  // Capture while holding lock
pthread_mutex_unlock(&st->lock);
if (handshake_done_now && stream_for_readable && ...)
    quic_stream_schedule_readable(st, mx, stream_for_readable);
```

Updated the function signature:
```c
// Before:
static void quic_stream_schedule_readable(quic_stream_ctx_t *ctx, quic_muxer_ctx_t *mx)

// After:
static void quic_stream_schedule_readable(quic_stream_ctx_t *ctx, quic_muxer_ctx_t *mx, libp2p_stream_t *stream)
```

## Key Debugging Lessons

1. **Printf with fflush is essential for crash debugging** - The last printf before silence pinpoints the crash location.

2. **Print pointer values** - Seeing `0x7cf827974b0fb391` vs `0xffff2c000fc0` immediately reveals corruption.

3. **Track pointer history** - Searching logs for the same pointer across time reveals when corruption occurred.

4. **Look for interleaved output** - Log lines from different threads interleaving indicates potential race conditions.

5. **Understand lock boundaries** - Any data access after releasing a lock is a potential race condition if other threads can modify that data.

6. **Silent crashes often indicate memory corruption** - When there's no stack trace, suspect use-after-free or invalid pointer dereference.
