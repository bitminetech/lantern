/*
 * The shell of the lantern binary (docs/reference/shell.md, Test vectors): memory, files, the log
 * and the clock, on the target it runs on. Usage: shell DIR, a directory it may write a file in.
 * Prints PASS or FAIL for each check, and exits 1 when one fails.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#if defined(_WIN32) && defined(__x86_64__)
#define ABI __attribute__((sysv_abi))
#else
#define ABI
#endif

ABI uint64_t lantern_shell_map(const uint64_t *size, uint64_t *out);
ABI uint64_t lantern_shell_unmap(const uint64_t *address, const uint64_t *size);
ABI uint64_t lantern_shell_read_file(const void *path, uint64_t *result);
ABI uint64_t lantern_shell_write(const uint64_t *stream, const void *bytes);
ABI uint64_t lantern_shell_time_ms(uint64_t *out);
ABI uint64_t lantern_shell_open(const void *path, const uint64_t *mode, uint64_t *result);
ABI uint64_t lantern_shell_append(const uint64_t *file, const void *bytes, uint64_t *result);
ABI uint64_t lantern_shell_write_at(const uint64_t *file, const uint64_t *offset, const void *bytes, uint64_t *result);
ABI uint64_t lantern_shell_sync(const uint64_t *file, uint64_t *result);
ABI uint64_t lantern_shell_truncate(const uint64_t *file, const uint64_t *size, uint64_t *result);
ABI uint64_t lantern_shell_close(const uint64_t *file);
ABI uint64_t lantern_shell_map_file(const void *path, uint64_t *result);
ABI uint64_t lantern_shell_unmap_file(const uint64_t *address, const uint64_t *size);
ABI uint64_t lantern_shell_remove(const void *path, uint64_t *result);
ABI uint64_t lantern_shell_rename(const void *from, const void *to, uint64_t *result);
ABI uint64_t lantern_shell_mkdir(const void *path, uint64_t *result);
ABI uint64_t lantern_shell_sync_dir(const void *path, uint64_t *result);
ABI uint64_t lantern_shell_pool_start(void *pool, const uint64_t *threads, uint64_t *result);
ABI uint64_t lantern_shell_pool_run(void *pool, const void *job);
ABI uint64_t lantern_shell_pool_stop(void *pool);

static int failures;

static void check(int ok, const char *what) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok) failures++;
}

/* A ByteList of the n bytes at b, at offset 32, with junk before and after them. */
static uint8_t *list_of(const void *b, uint64_t n) {
    uint64_t size = (32 + n + 8 + 7) & ~(uint64_t)7;
    uint8_t *l = malloc(size);
    if (!l) exit(2);
    memset(l, 'J', size);
    memcpy(l, &size, 8);
    uint64_t at = 32;
    memcpy(l + 8, &at, 8);
    memcpy(l + 16, &n, 8);
    memcpy(l + 32, b, n);
    return l;
}

/* lantern_shell_read_file of path: its FileResult in r. */
static void read_file(const char *path, uint64_t n, uint64_t r[4]) {
    uint8_t *l = list_of(path, n);
    for (int k = 0; k < 4; k++) r[k] = 0xA5A5A5A5A5A5A5A5u;
    check(lantern_shell_read_file(l, r) == 0, "read_file: status 0");
    free(l);
}

/* A ShellJob of the pool test: entry i of the context gets 3 i + 1, and the number of the calls goes up. */
typedef struct {
    uint64_t *out, calls;
} pool_ctx;

static ABI uint64_t pool_job(void *context, uint64_t index) {
    pool_ctx *c = context;
    c->out[index] = 3 * index + 1;
    __atomic_fetch_add(&c->calls, 1, __ATOMIC_RELAXED);
    return 0;
}

/* The pool of threads (shell.md, lantern_shell_pool_start, _run, _stop): every index once, for each count. */
static void pool_check(uint64_t threads) {
    uint8_t *pool = calloc(1, 8192);
    uint64_t result[2] = {7, 7}, n = 1 << 16;
    pool_ctx c = {calloc(n, 8), 0};
    if (!pool || !c.out) exit(2);
    check(lantern_shell_pool_start(pool, &threads, result) == 0 && result[0] == 0 && result[1] == (threads ? threads : 1) - 1,
          threads == 4 ? "pool_start: 4 threads, 3 workers" : "pool_start: 1 thread, no workers");
    int ok = 1;
    for (uint64_t round = 0; round < 200 && ok; round++) {
        uint64_t count = round < 100 ? round : n - round;
        memset(c.out, 0, (size_t)(8 * n));
        c.calls = 0;
        uint64_t job[3] = {(uint64_t)(uintptr_t)pool_job, (uint64_t)(uintptr_t)&c, count};
        ok &= lantern_shell_pool_run(pool, job) == 0 && c.calls == count;
        for (uint64_t i = 0; i < n && ok; i++) ok &= c.out[i] == (i < count ? 3 * i + 1 : 0);
    }
    check(ok, threads == 4 ? "pool_run: 200 runs on 4 threads, each index once" : "pool_run: 200 runs alone, each index once");
    check(lantern_shell_pool_stop(pool) == 0 && ((uint64_t *)pool)[7] == 0, "pool_stop: the workers joined");
    free(c.out);
    free(pool);
}

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: %s DIR\n", argv[0]);
        return 2;
    }
    /* Memory: zeroed, writable, page aligned. */
    uint64_t size = 1 << 20, address = 0;
    check(lantern_shell_map(&size, &address) == 0 && address != 0, "map: 1 MiB");
    if (address) {
        uint8_t *m = (uint8_t *)(uintptr_t)address;
        int zero = 1;
        for (uint64_t k = 0; k < size; k += 4096) zero &= m[k] == 0 && m[k + 4095] == 0;
        m[0] = 1;
        m[size - 1] = 2;
        check(zero && address % 4096 == 0, "map: zeroed and page aligned");
        check(lantern_shell_unmap(&address, &size) == 0, "unmap");
    }

    /* A file of 100000 bytes, read whole. */
    char path[4096];
    snprintf(path, sizeof path, "%s/shell-test.bin", argv[1]);
    uint64_t n = 100000;
    uint8_t *want = malloc(n);
    if (!want) return 2;
    for (uint64_t k = 0; k < n; k++) want[k] = (uint8_t)(k * 7 + 3);
    FILE *f = fopen(path, "wb");
    if (!f || fwrite(want, 1, n, f) != n || fclose(f) != 0) {
        fprintf(stderr, "cannot write %s\n", path);
        return 2;
    }
    uint64_t r[4];
    read_file(path, strlen(path), r);
    const uint64_t *h = (const uint64_t *)(uintptr_t)r[1];
    check(r[0] == 0 && r[1] != 0 && r[2] == n && r[3] == 24 + n && h[0] == r[3] && h[1] == 24 && h[2] == n &&
              !memcmp((const uint8_t *)h + 24, want, n),
          "read_file: a ByteList of the bytes of a file");
    if (r[1]) lantern_shell_unmap(&r[1], &r[3]);

    /* An empty file: no error, size 0, memory of at least 1 byte. */
    f = fopen(path, "wb");
    if (!f || fclose(f) != 0) return 2;
    read_file(path, strlen(path), r);
    h = (const uint64_t *)(uintptr_t)r[1];
    check(r[0] == 0 && r[1] != 0 && r[2] == 0 && r[3] == 24 && h[0] == 24 && h[1] == 24 && h[2] == 0, "read_file: an empty file");
    if (r[1]) lantern_shell_unmap(&r[1], &r[3]);
    remove(path);

    /* A missing file, and a path above 4095 bytes: an error and no memory. */
    read_file(path, strlen(path), r);
    check(r[0] != 0 && r[1] == 0, "read_file: a missing file");
    char *longpath = malloc(5000);
    if (!longpath) return 2;
    memset(longpath, 'a', 5000);
    read_file(longpath, 5000, r);
    check(r[0] != 0 && r[1] == 0, "read_file: a path of 5000 bytes");
    free(longpath);
    free(want);

    /* The file functions of the database: a new directory, a file appended to, synced, mapped, truncated, renamed over and removed. */
    {
        uint64_t stamp = 0, op[2], m[4], mode = 1, file = 0, cut = 6000;
        lantern_shell_time_ms(&stamp);
        char dir[4096], seg[4096], other[4096];
        snprintf(dir, sizeof dir, "%s/shell-db-%llu", argv[1], (unsigned long long)stamp);
        snprintf(seg, sizeof seg, "%s/seg.bin", dir);
        snprintf(other, sizeof other, "%s/other.bin", dir);
        uint8_t *ld = list_of(dir, strlen(dir)), *ls = list_of(seg, strlen(seg)), *lo = list_of(other, strlen(other));
        uint8_t data[8100];
        for (int k = 0; k < 8100; k++) data[k] = (uint8_t)(k * 13 + 5);
        uint8_t *la = list_of(data, 5000), *lb = list_of(data + 5000, 3000), *lc = list_of(data + 7000, 100);
        check(lantern_shell_mkdir(ld, op) == 0 && op[0] == 0, "mkdir: a new directory");
        check(lantern_shell_mkdir(ld, op) == 0 && op[0] != 0, "mkdir: an existing directory is an error");
        check(lantern_shell_open(ls, &mode, op) == 0 && op[0] == 0, "open: a new file to append to");
        file = op[1];
        check(lantern_shell_append(&file, la, op) == 0 && op[0] == 0 && op[1] == 5000, "append: 5000 bytes");
        check(lantern_shell_append(&file, lb, op) == 0 && op[0] == 0 && op[1] == 3000, "append: 3000 bytes more");
        check(lantern_shell_sync(&file, op) == 0 && op[0] == 0, "sync: the file");
        check(lantern_shell_sync_dir(ld, op) == 0 && op[0] == 0, "sync_dir: the directory");
        check(lantern_shell_map_file(ls, m) == 0 && m[0] == 0 && m[1] != 0 && m[2] == 8000 && m[3] == 8000 &&
                  !memcmp((const void *)(uintptr_t)m[1], data, 8000),
              "map_file: both writes");
        if (m[1]) lantern_shell_unmap_file(&m[1], &m[3]);
        check(lantern_shell_truncate(&file, &cut, op) == 0 && op[0] == 0, "truncate: to 6000 bytes");
        check(lantern_shell_map_file(ls, m) == 0 && m[0] == 0 && m[2] == 6000 && !memcmp((const void *)(uintptr_t)m[1], data, 6000),
              "map_file: the first 6000 bytes");
        if (m[1]) lantern_shell_unmap_file(&m[1], &m[3]);
        lantern_shell_close(&file);
        check(lantern_shell_open(ls, &mode, op) == 0 && op[0] == 0, "open: the file again to append to");
        file = op[1];
        check(lantern_shell_append(&file, lc, op) == 0 && op[0] == 0 && op[1] == 100, "append: at the new end");
        lantern_shell_close(&file);
        check(lantern_shell_map_file(ls, m) == 0 && m[0] == 0 && m[2] == 6100 && !memcmp((const void *)(uintptr_t)m[1], data, 6000) &&
                  !memcmp((const uint8_t *)(uintptr_t)m[1] + 6000, data + 7000, 100),
              "map_file: the bytes after the cut");
        if (m[1]) lantern_shell_unmap_file(&m[1], &m[3]);
        mode = 0;
        check(lantern_shell_open(ls, &mode, op) == 0 && op[0] == 0, "open: the file to read");
        file = op[1];
        lantern_shell_close(&file);
        /* SHELL_OPEN_WRITE and write_at: over bytes, then past the end (a gap of zero bytes). */
        mode = 2;
        check(lantern_shell_open(ls, &mode, op) == 0 && op[0] == 0, "open: the file to read and write");
        file = op[1];
        uint64_t at = 100;
        check(lantern_shell_write_at(&file, &at, lc, op) == 0 && op[0] == 0 && op[1] == 100, "write_at: 100 bytes at 100");
        at = 6200;
        check(lantern_shell_write_at(&file, &at, la, op) == 0 && op[0] == 0 && op[1] == 5000, "write_at: 5000 bytes past the end");
        lantern_shell_sync(&file, op);
        lantern_shell_close(&file);
        {
            static uint8_t want[11200];
            memcpy(want, data, 6000);
            memcpy(want + 6000, data + 7000, 100);
            memcpy(want + 100, data + 7000, 100);
            memset(want + 6100, 0, 100);
            memcpy(want + 6200, data, 5000);
            check(lantern_shell_map_file(ls, m) == 0 && m[0] == 0 && m[2] == 11200 && !memcmp((const void *)(uintptr_t)m[1], want, 11200),
                  "map_file: the bytes of write_at, and zeros in the gap");
            if (m[1]) lantern_shell_unmap_file(&m[1], &m[3]);
        }
        mode = 2;
        check(lantern_shell_open(lo, &mode, op) == 0 && op[0] == 0, "open: a new file to read and write");
        file = op[1];
        lantern_shell_close(&file);
        check(lantern_shell_remove(lo, op) == 0 && op[0] == 0, "remove: that file");
        mode = 7;
        check(lantern_shell_open(ls, &mode, op) == 0 && op[0] != 0 && op[1] == 0, "open: a faulty mode is an error");
        mode = 1;
        check(lantern_shell_open(lo, &mode, op) == 0 && op[0] == 0, "open: an empty file");
        file = op[1];
        lantern_shell_close(&file);
        check(lantern_shell_map_file(lo, m) == 0 && m[0] == 0 && m[1] == 0 && m[2] == 0, "map_file: an empty file, address 0");
        check(lantern_shell_rename(lo, ls, op) == 0 && op[0] == 0, "rename: over the first file");
        check(lantern_shell_map_file(ls, m) == 0 && m[0] == 0 && m[2] == 0, "map_file: the renamed file");
        check(lantern_shell_map_file(lo, m) == 0 && m[0] != 0 && m[1] == 0, "map_file: the old name is missing");
        check(lantern_shell_remove(ls, op) == 0 && op[0] == 0, "remove: the file");
        check(lantern_shell_remove(ls, op) == 0 && op[0] != 0, "remove: a missing file is an error");
        check(lantern_shell_map_file(ls, m) == 0 && m[0] != 0 && m[1] == 0, "map_file: a missing file is an error");
        free(ld);
        free(ls);
        free(lo);
        free(la);
        free(lb);
        free(lc);
    }

    /* The log. */
    static const char line[] = "shell: a line on the standard output\n";
    uint8_t *l = list_of(line, sizeof line - 1);
    uint64_t stream = 1;
    fflush(stdout);
    check(lantern_shell_write(&stream, l) == 0, "write: status 0");
    free(l);

    /* The clock: within 2 s of the C library's. */
    uint64_t ms = 0, now = (uint64_t)time(NULL) * 1000;
    check(lantern_shell_time_ms(&ms) == 0 && ms + 2000 > now && ms < now + 2000, "time_ms: the Unix time");

    pool_check(4);
    pool_check(1);
    printf("%s: %d failed\n", failures ? "FAIL" : "PASS", failures);
    return failures ? 1 : 0;
}
