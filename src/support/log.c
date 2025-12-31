#include "lantern/support/log.h"

#include <ctype.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#if defined(_WIN32)
#include <io.h>
#define lantern_isatty _isatty
#define lantern_fileno _fileno
#else
#include <unistd.h>
#define lantern_isatty isatty
#define lantern_fileno fileno
#endif

static char g_node_id[96] = {0};
static enum LanternLogLevel g_min_level = LANTERN_LOG_LEVEL_INFO;
static bool g_color_initialized = false;
static bool g_color_stdout = false;
static bool g_color_stderr = false;

static int equals_ignore_case(const char *lhs, const char *rhs);

enum lantern_log_color_mode {
    LANTERN_LOG_COLOR_AUTO = 0,
    LANTERN_LOG_COLOR_NEVER,
    LANTERN_LOG_COLOR_ALWAYS,
};

static enum lantern_log_color_mode g_color_mode = LANTERN_LOG_COLOR_AUTO;

/* ANSI color codes */
#define ANSI_RESET "\x1b[0m"
#define ANSI_BOLD "\x1b[1m"
#define ANSI_DIM "\x1b[2m"
#define ANSI_BLACK "\x1b[30m"
#define ANSI_RED "\x1b[31m"
#define ANSI_GREEN "\x1b[32m"
#define ANSI_YELLOW "\x1b[33m"
#define ANSI_BLUE "\x1b[34m"
#define ANSI_MAGENTA "\x1b[35m"
#define ANSI_CYAN "\x1b[36m"
#define ANSI_WHITE "\x1b[37m"
#define ANSI_BRIGHT_BLACK "\x1b[90m"
#define ANSI_BRIGHT_RED "\x1b[91m"
#define ANSI_BRIGHT_GREEN "\x1b[92m"
#define ANSI_BRIGHT_YELLOW "\x1b[93m"
#define ANSI_BRIGHT_BLUE "\x1b[94m"
#define ANSI_BRIGHT_CYAN "\x1b[96m"

/* Level badge colors and symbols */
static const char *level_to_color(enum LanternLogLevel level) {
    switch (level) {
    case LANTERN_LOG_LEVEL_TRACE:
        return ANSI_BRIGHT_BLACK;
    case LANTERN_LOG_LEVEL_DEBUG:
        return ANSI_CYAN;
    case LANTERN_LOG_LEVEL_INFO:
        return ANSI_GREEN;
    case LANTERN_LOG_LEVEL_WARN:
        return ANSI_YELLOW;
    case LANTERN_LOG_LEVEL_ERROR:
        return ANSI_BRIGHT_RED;
    default:
        return ANSI_RESET;
    }
}

static const char *level_to_string(enum LanternLogLevel level) {
    switch (level) {
    case LANTERN_LOG_LEVEL_TRACE:
        return "TRACE";
    case LANTERN_LOG_LEVEL_DEBUG:
        return "DEBUG";
    case LANTERN_LOG_LEVEL_INFO:
        return "INFO";
    case LANTERN_LOG_LEVEL_WARN:
        return "WARN";
    case LANTERN_LOG_LEVEL_ERROR:
        return "ERROR";
    default:
        return "INFO";
    }
}

static enum lantern_log_color_mode parse_color_mode(const char *text)
{
    if (!text) {
        return LANTERN_LOG_COLOR_AUTO;
    }
    if (equals_ignore_case(text, "always")) {
        return LANTERN_LOG_COLOR_ALWAYS;
    }
    if (equals_ignore_case(text, "never")) {
        return LANTERN_LOG_COLOR_NEVER;
    }
    if (equals_ignore_case(text, "auto")) {
        return LANTERN_LOG_COLOR_AUTO;
    }
    return LANTERN_LOG_COLOR_AUTO;
}

static bool detect_terminal(FILE *stream)
{
    (void)stream;
    /* Always enable colors by default - modern terminals and log viewers support ANSI colors */
    return true;
}

static void ensure_color_configuration(void)
{
    if (g_color_initialized) {
        return;
    }
    const char *env_color = getenv("LANTERN_LOG_COLOR");
    g_color_mode = parse_color_mode(env_color);
    switch (g_color_mode) {
    case LANTERN_LOG_COLOR_ALWAYS:
        g_color_stdout = true;
        g_color_stderr = true;
        break;
    case LANTERN_LOG_COLOR_NEVER:
        g_color_stdout = false;
        g_color_stderr = false;
        break;
    case LANTERN_LOG_COLOR_AUTO:
    default:
        g_color_stdout = detect_terminal(stdout);
        g_color_stderr = detect_terminal(stderr);
        break;
    }
    g_color_initialized = true;
}

void lantern_log_set_node_id(const char *node_id) {
    if (!node_id) {
        g_node_id[0] = '\0';
        return;
    }
    size_t len = strlen(node_id);
    if (len >= sizeof(g_node_id)) {
        len = sizeof(g_node_id) - 1;
    }
    memcpy(g_node_id, node_id, len);
    g_node_id[len] = '\0';
}

void lantern_log_reset_node_id(void) {
    g_node_id[0] = '\0';
}

void lantern_log_set_level(enum LanternLogLevel level) {
    g_min_level = level;
}

enum LanternLogLevel lantern_log_get_level(void) {
    return g_min_level;
}

static int equals_ignore_case(const char *lhs, const char *rhs) {
    if (!lhs || !rhs) {
        return 0;
    }
    while (*lhs && *rhs) {
        unsigned char a = (unsigned char)(*lhs);
        unsigned char b = (unsigned char)(*rhs);
        if (tolower(a) != tolower(b)) {
            return 0;
        }
        ++lhs;
        ++rhs;
    }
    return *lhs == '\0' && *rhs == '\0';
}

static int parse_level(const char *text, enum LanternLogLevel *out_level) {
    if (!text || !out_level) {
        return -1;
    }
    if (equals_ignore_case(text, "trace")) {
        *out_level = LANTERN_LOG_LEVEL_TRACE;
        return 0;
    }
    if (equals_ignore_case(text, "debug")) {
        *out_level = LANTERN_LOG_LEVEL_DEBUG;
        return 0;
    }
    if (equals_ignore_case(text, "info")) {
        *out_level = LANTERN_LOG_LEVEL_INFO;
        return 0;
    }
    if (equals_ignore_case(text, "warn") || equals_ignore_case(text, "warning")) {
        *out_level = LANTERN_LOG_LEVEL_WARN;
        return 0;
    }
    if (equals_ignore_case(text, "error")) {
        *out_level = LANTERN_LOG_LEVEL_ERROR;
        return 0;
    }
    return -1;
}

int lantern_log_set_level_from_string(const char *text, enum LanternLogLevel *out_level) {
    enum LanternLogLevel parsed = LANTERN_LOG_LEVEL_INFO;
    if (parse_level(text, &parsed) != 0) {
        return -1;
    }
    lantern_log_set_level(parsed);
    if (out_level) {
        *out_level = parsed;
    }
    return 0;
}

static void format_timestamp(char buffer[32]) {
    struct timespec ts;
    if (timespec_get(&ts, TIME_UTC) != TIME_UTC) {
        buffer[0] = '\0';
        return;
    }
    struct tm tm_result;
    if (!gmtime_r(&ts.tv_sec, &tm_result)) {
        buffer[0] = '\0';
        return;
    }
    /* Clean format: YYYY-MM-DD HH:MM:SS.mmm */
    int written = snprintf(
        buffer, 32, "%04d-%02d-%02d %02d:%02d:%02d.%03ld",
        tm_result.tm_year + 1900,
        tm_result.tm_mon + 1,
        tm_result.tm_mday,
        tm_result.tm_hour,
        tm_result.tm_min,
        tm_result.tm_sec,
        ts.tv_nsec / 1000000L);
    if (written < 0) {
        buffer[0] = '\0';
        return;
    }
}

void lantern_log_log(
    enum LanternLogLevel level,
    const char *component,
    const struct lantern_log_metadata *metadata,
    const char *fmt,
    va_list args) {
    if (level < g_min_level) {
        return;
    }

    /* Format the user message */
    char formatted[1024];
    int msg_written = vsnprintf(formatted, sizeof(formatted), fmt ? fmt : "", args);
    if (msg_written < 0) {
        formatted[0] = '\0';
    } else if ((size_t)msg_written >= sizeof(formatted)) {
        formatted[sizeof(formatted) - 1] = '\0';
    }

    char timestamp[32];
    format_timestamp(timestamp);

    ensure_color_configuration();
    FILE *target = level >= LANTERN_LOG_LEVEL_WARN ? stderr : stdout;
    const bool colorize = (target == stderr) ? g_color_stderr : g_color_stdout;

    /* Build context string with only non-empty fields */
    char context[256];
    char *ctx_cursor = context;
    size_t ctx_remaining = sizeof(context);
    context[0] = '\0';
    const char *peer_text = (metadata && metadata->peer && metadata->peer[0]) ? metadata->peer : NULL;

    /* Add slot if present */
    if (metadata && metadata->has_slot) {
        int w = snprintf(ctx_cursor, ctx_remaining, "slot=%" PRIu64, metadata->slot);
        if (w > 0 && (size_t)w < ctx_remaining) {
            ctx_cursor += w;
            ctx_remaining -= (size_t)w;
        }
    }

    /* Add validator if present */
    if (metadata && metadata->validator && metadata->validator[0]) {
        if (ctx_cursor != context) {
            int w = snprintf(ctx_cursor, ctx_remaining, " ");
            if (w > 0 && (size_t)w < ctx_remaining) {
                ctx_cursor += w;
                ctx_remaining -= (size_t)w;
            }
        }
        int w = snprintf(ctx_cursor, ctx_remaining, "validator=%s", metadata->validator);
        if (w > 0 && (size_t)w < ctx_remaining) {
            ctx_cursor += w;
            ctx_remaining -= (size_t)w;
        }
    }

    /* Add peer later to avoid truncating long peer IDs */
    /*
     * Output format:
     * HH:MM:SS.mmm LVL [component] message  context
     *
     * With colors:
     * - Timestamp: dim
     * - Level: colored based on level
     * - Component: cyan
     * - Message: normal (white/default)
     * - Context: dim
     */

    if (colorize) {
        /* Colored output with selective coloring */
        fprintf(
            target,
            "%s%s%s %s%s%s %s[%s]%s %s",
            ANSI_DIM, timestamp[0] ? timestamp : "????-??-?? ??:??:??.???", ANSI_RESET,
            level_to_color(level), level_to_string(level), ANSI_RESET,
            ANSI_CYAN, component ? component : "?", ANSI_RESET,
            formatted);

        /* Add context if present */
        if (context[0] || peer_text) {
            fprintf(target, "  %s", ANSI_DIM);
            if (context[0]) {
                fprintf(target, "%s", context);
                if (peer_text) {
                    fprintf(target, " peer=%s", peer_text);
                }
            } else {
                fprintf(target, "peer=%s", peer_text);
            }
            fprintf(target, "%s", ANSI_RESET);
        }
        fprintf(target, "\n");
    } else {
        /* Plain output without colors */
        fprintf(
            target,
            "%s %s [%s] %s",
            timestamp[0] ? timestamp : "????-??-?? ??:??:??.???",
            level_to_string(level),
            component ? component : "?",
            formatted);

        /* Add context if present */
        if (context[0] || peer_text) {
            fprintf(target, "  ");
            if (context[0]) {
                fprintf(target, "%s", context);
                if (peer_text) {
                    fprintf(target, " peer=%s", peer_text);
                }
            } else {
                fprintf(target, "peer=%s", peer_text);
            }
        }
        fprintf(target, "\n");
    }

    fflush(target);
}

static void log_variadic(
    enum LanternLogLevel level,
    const char *component,
    const struct lantern_log_metadata *metadata,
    const char *fmt,
    va_list args) {
    lantern_log_log(level, component, metadata, fmt, args);
}

void lantern_log_trace(
    const char *component,
    const struct lantern_log_metadata *metadata,
    const char *fmt,
    ...) {
    va_list args;
    va_start(args, fmt);
    log_variadic(LANTERN_LOG_LEVEL_TRACE, component, metadata, fmt, args);
    va_end(args);
}

void lantern_log_debug(
    const char *component,
    const struct lantern_log_metadata *metadata,
    const char *fmt,
    ...) {
    va_list args;
    va_start(args, fmt);
    log_variadic(LANTERN_LOG_LEVEL_DEBUG, component, metadata, fmt, args);
    va_end(args);
}

void lantern_log_info(
    const char *component,
    const struct lantern_log_metadata *metadata,
    const char *fmt,
    ...) {
    va_list args;
    va_start(args, fmt);
    log_variadic(LANTERN_LOG_LEVEL_INFO, component, metadata, fmt, args);
    va_end(args);
}

void lantern_log_warn(
    const char *component,
    const struct lantern_log_metadata *metadata,
    const char *fmt,
    ...) {
    va_list args;
    va_start(args, fmt);
    log_variadic(LANTERN_LOG_LEVEL_WARN, component, metadata, fmt, args);
    va_end(args);
}

void lantern_log_error(
    const char *component,
    const struct lantern_log_metadata *metadata,
    const char *fmt,
    ...) {
    va_list args;
    va_start(args, fmt);
    log_variadic(LANTERN_LOG_LEVEL_ERROR, component, metadata, fmt, args);
    va_end(args);
}
