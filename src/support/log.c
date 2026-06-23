#include "lantern/support/log.h"

#include <ctype.h>
#include <inttypes.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static char g_node_id[96] = {0};
static pthread_mutex_t g_log_mutex = PTHREAD_MUTEX_INITIALIZER;
static enum LanternLogLevel g_min_level = LANTERN_LOG_LEVEL_INFO;

static int equals_ignore_case(const char *lhs, const char *rhs);

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
    int written = snprintf(
        buffer, 32, "%04d-%02d-%02dT%02d:%02d:%02d.%03ldZ",
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

static void format_component_tag(const char *component, char out[16]) {
    char lowered[11];
    const char *text = component && component[0] ? component : "?";
    size_t i = 0;
    for (; text[i] && i < sizeof(lowered) - 1u; ++i) {
        lowered[i] = (char)tolower((unsigned char)text[i]);
    }
    lowered[i] = '\0';
    snprintf(out, 16, "[%s]", lowered);
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
    (void)metadata;

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

    FILE *target = level >= LANTERN_LOG_LEVEL_WARN ? stderr : stdout;
    char tag[16];
    format_component_tag(component, tag);
    static const char kUnknownTimestamp[] = "????" "-??" "-??T??:??:??.???Z";

    pthread_mutex_lock(&g_log_mutex);
    fprintf(
        target,
        "%s  %-5s  %-12s %s\n",
        timestamp[0] ? timestamp : kUnknownTimestamp,
        level_to_string(level),
        tag,
        formatted);

    fflush(target);
    pthread_mutex_unlock(&g_log_mutex);
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
