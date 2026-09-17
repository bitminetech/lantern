#include "lantern/support/log.h"

#include <ctype.h>
#include <inttypes.h>
#include <stdarg.h>
#include <stdatomic.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

static atomic_int s_default_min_level = LANTERN_LOG_LEVEL_INFO;

static const char *level_to_string(enum lantern_log_level level)
{
    switch (level)
    {
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

enum lantern_log_result lantern_log_set_level(enum lantern_log_level level)
{
    if (level < LANTERN_LOG_LEVEL_TRACE || level > LANTERN_LOG_LEVEL_ERROR)
    {
        return LANTERN_LOG_ERR_INVALID;
    }

    atomic_store_explicit(&s_default_min_level, level, memory_order_relaxed);
    return LANTERN_LOG_OK;
}

static bool equals_ignore_case(const char *lhs, const char *rhs)
{
    if (!lhs || !rhs)
    {
        return false;
    }

    while (*lhs && *rhs)
    {
        unsigned char a = (unsigned char)(*lhs);
        unsigned char b = (unsigned char)(*rhs);

        if (tolower(a) != tolower(b))
        {
            return false;
        }

        ++lhs;
        ++rhs;
    }

    return *lhs == '\0' && *rhs == '\0';
}

static enum lantern_log_result parse_level(
    const char *text, enum lantern_log_level *out_level)
{
    if (!text || !out_level)
    {
        return LANTERN_LOG_ERR_INVALID;
    }

    if (equals_ignore_case(text, "trace"))
    {
        *out_level = LANTERN_LOG_LEVEL_TRACE;
        return LANTERN_LOG_OK;
    }

    if (equals_ignore_case(text, "debug"))
    {
        *out_level = LANTERN_LOG_LEVEL_DEBUG;
        return LANTERN_LOG_OK;
    }

    if (equals_ignore_case(text, "info"))
    {
        *out_level = LANTERN_LOG_LEVEL_INFO;
        return LANTERN_LOG_OK;
    }

    if (equals_ignore_case(text, "warn") || equals_ignore_case(text, "warning"))
    {
        *out_level = LANTERN_LOG_LEVEL_WARN;
        return LANTERN_LOG_OK;
    }

    if (equals_ignore_case(text, "error"))
    {
        *out_level = LANTERN_LOG_LEVEL_ERROR;
        return LANTERN_LOG_OK;
    }

    return LANTERN_LOG_ERR_INVALID;
}

enum lantern_log_result lantern_log_set_level_from_string(
    const char *text, enum lantern_log_level *out_level)
{
    enum lantern_log_level parsed = LANTERN_LOG_LEVEL_INFO;

    if (parse_level(text, &parsed) != LANTERN_LOG_OK)
    {
        return LANTERN_LOG_ERR_INVALID;
    }

    enum lantern_log_result result = lantern_log_set_level(parsed);

    if (result != LANTERN_LOG_OK)
    {
        return result;
    }

    if (out_level)
    {
        *out_level = parsed;
    }

    return LANTERN_LOG_OK;
}

static enum lantern_log_timestamp_result default_timestamp(
    void *context, char buffer[32])
{
    (void)context;

    struct timespec ts;

    if (timespec_get(&ts, TIME_UTC) != TIME_UTC)
    {
        return LANTERN_LOG_TIMESTAMP_UNAVAILABLE;
    }

    struct tm tm_result;

    if (!gmtime_r(&ts.tv_sec, &tm_result))
    {
        return LANTERN_LOG_TIMESTAMP_UNAVAILABLE;
    }

    int written =
        snprintf(buffer, 32, "%04d-%02d-%02dT%02d:%02d:%02d.%03ldZ",
                 tm_result.tm_year + 1900, tm_result.tm_mon + 1,
                 tm_result.tm_mday, tm_result.tm_hour, tm_result.tm_min,
                 tm_result.tm_sec, ts.tv_nsec / 1000000L);
    return written >= 0 && written < 32
               ? LANTERN_LOG_TIMESTAMP_AVAILABLE
               : LANTERN_LOG_TIMESTAMP_UNAVAILABLE;
}

static void format_component_tag(const char *component, char out[16])
{
    char lowered[11];
    const char *text = component && component[0] ? component : "?";
    size_t i = 0;

    for (; i < sizeof(lowered) - 1u && text[i]; ++i)
    {
        lowered[i] = (char)tolower((unsigned char)text[i]);
    }

    lowered[i] = '\0';

    (void)snprintf(out, 16, "[%s]", lowered);
}

static enum lantern_log_sink_result default_sink(
    void *context, const struct lantern_log_record *record)
{
    (void)context;

    FILE *target =
        record->level >= LANTERN_LOG_LEVEL_WARN ? stderr : stdout;
    char tag[16];
    format_component_tag(record->component, tag);

    enum lantern_log_sink_result result = LANTERN_LOG_SINK_OK;
    flockfile(target);

    if (fprintf(target, "%s  %-5s  %-12s", record->timestamp,
                level_to_string(record->level), tag) < 0)
    {
        result = LANTERN_LOG_SINK_ERR_WRITE;
    }

    if (record->metadata && record->metadata->validator &&
        fprintf(target, " validator=%s",
                record->metadata->validator) < 0)
    {
        result = LANTERN_LOG_SINK_ERR_WRITE;
    }

    if (record->metadata && record->metadata->peer &&
        fprintf(target, " peer=%s", record->metadata->peer) < 0)
    {
        result = LANTERN_LOG_SINK_ERR_WRITE;
    }

    if (record->metadata && record->metadata->has_slot &&
        fprintf(target, " slot=%" PRIu64, record->metadata->slot) < 0)
    {
        result = LANTERN_LOG_SINK_ERR_WRITE;
    }

    if (fprintf(target, " %s\n", record->message) < 0 ||
        fflush(target) != 0)
    {
        result = LANTERN_LOG_SINK_ERR_WRITE;
    }

    funlockfile(target);
    return result;
}

static enum lantern_log_result log_emit_v(
    const struct lantern_log_config *config,
    enum lantern_log_level level,
    const char *component,
    const struct lantern_log_metadata *metadata,
    const char *fmt,
    va_list args)
{
    if (!config || !config->sink || !fmt ||
        config->min_level < LANTERN_LOG_LEVEL_TRACE ||
        config->min_level > LANTERN_LOG_LEVEL_ERROR ||
        level < LANTERN_LOG_LEVEL_TRACE ||
        level > LANTERN_LOG_LEVEL_ERROR)
    {
        return LANTERN_LOG_ERR_INVALID;
    }

    if (level < config->min_level)
    {
        return LANTERN_LOG_OK;
    }

    char message[1024];
    int written = vsnprintf(message, sizeof(message), fmt, args);

    if (written < 0)
    {
        return LANTERN_LOG_ERR_FORMAT;
    }

    message[sizeof(message) - 1u] = '\0';
    bool truncated = (size_t)written >= sizeof(message);

    static const char unknown_timestamp[] = "????"
                                            "-??"
                                            "-??T??:??:??.???Z";
    char timestamp[32];
    const char *timestamp_text = unknown_timestamp;

    if (config->timestamp &&
        config->timestamp(config->context, timestamp) ==
            LANTERN_LOG_TIMESTAMP_AVAILABLE)
    {
        timestamp_text = timestamp;
    }

    const struct lantern_log_record record =
    {
        .level = level,
        .timestamp = timestamp_text,
        .component = component,
        .metadata = metadata,
        .message = message,
    };

    if (config->sink(config->context, &record) != LANTERN_LOG_SINK_OK)
    {
        return LANTERN_LOG_ERR_SINK;
    }

    return truncated ? LANTERN_LOG_TRUNCATED : LANTERN_LOG_OK;
}

enum lantern_log_result lantern_log_emit(
    const struct lantern_log_config *config,
    enum lantern_log_level level,
    const char *component,
    const struct lantern_log_metadata *metadata,
    const char *fmt,
    ...)
{
    va_list args;
    va_start(args, fmt);
    enum lantern_log_result result =
        log_emit_v(config, level, component, metadata, fmt, args);
    va_end(args);
    return result;
}

void lantern_log(enum lantern_log_level level, const char *component,
                 const struct lantern_log_metadata *metadata, const char *fmt,
                 ...)
{
    const struct lantern_log_config config =
    {
        .min_level = (enum lantern_log_level)atomic_load_explicit(
            &s_default_min_level, memory_order_relaxed),
        .timestamp = default_timestamp,
        .sink = default_sink,
        .context = NULL,
    };

    va_list args;
    va_start(args, fmt);
    (void)log_emit_v(&config, level, component, metadata, fmt, args);
    va_end(args);
}
