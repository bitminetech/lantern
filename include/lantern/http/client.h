#ifndef LANTERN_HTTP_CLIENT_H
#define LANTERN_HTTP_CLIENT_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum
{
    LANTERN_HTTP_CLIENT_OK = 0,
    LANTERN_HTTP_CLIENT_STATUS_ERROR = 1,
    LANTERN_HTTP_CLIENT_ERR = -1,
};

struct lantern_http_fetch_result {
    int status_code;
    uint8_t *body;
    size_t body_len;
};

int lantern_http_get_bytes(
    const char *url,
    const char *accept,
    size_t max_response_bytes,
    struct lantern_http_fetch_result *out_result);
void lantern_http_fetch_result_reset(struct lantern_http_fetch_result *result);

#ifdef __cplusplus
}
#endif

#endif /* LANTERN_HTTP_CLIENT_H */
