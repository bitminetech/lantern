#ifndef LANTERN_SUPPORT_LOG_H
#define LANTERN_SUPPORT_LOG_H

#include <stdbool.h>
#include <stdint.h>
#include <stdarg.h>

#ifdef __cplusplus
extern "C" {
#endif

enum LanternLogLevel {
    LANTERN_LOG_LEVEL_TRACE = 0,
    LANTERN_LOG_LEVEL_DEBUG,
    LANTERN_LOG_LEVEL_INFO,
    LANTERN_LOG_LEVEL_WARN,
    LANTERN_LOG_LEVEL_ERROR,
};

struct lantern_log_metadata {
    const char *validator;
    const char *peer;
    uint64_t slot;
    bool has_slot;
};

void lantern_log_set_node_id(const char *node_id);
void lantern_log_reset_node_id(void);
void lantern_log_set_level(enum LanternLogLevel level);
int lantern_log_set_level_from_string(const char *text, enum LanternLogLevel *out_level);

void lantern_log_log(
    enum LanternLogLevel level,
    const char *component,
    const struct lantern_log_metadata *metadata,
    const char *fmt,
    va_list args);

void lantern_log_trace(
    const char *component,
    const struct lantern_log_metadata *metadata,
    const char *fmt,
    ...) __attribute__((format(printf, 3, 4)));

void lantern_log_debug(
    const char *component,
    const struct lantern_log_metadata *metadata,
    const char *fmt,
    ...) __attribute__((format(printf, 3, 4)));

void lantern_log_info(
    const char *component,
    const struct lantern_log_metadata *metadata,
    const char *fmt,
    ...) __attribute__((format(printf, 3, 4)));

void lantern_log_warn(
    const char *component,
    const struct lantern_log_metadata *metadata,
    const char *fmt,
    ...) __attribute__((format(printf, 3, 4)));

void lantern_log_error(
    const char *component,
    const struct lantern_log_metadata *metadata,
    const char *fmt,
    ...) __attribute__((format(printf, 3, 4)));

#ifdef __cplusplus
}
#endif

#endif /* LANTERN_SUPPORT_LOG_H */
