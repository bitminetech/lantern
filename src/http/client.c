#include "lantern/http/client.h"

#include <limits.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

#include <curl/curl.h>

struct response_writer {
    struct lantern_http_fetch_result *result;
    size_t limit;
};

static pthread_once_t curl_once = PTHREAD_ONCE_INIT;
static int curl_initialized;

static void initialize_curl(void)
{
    curl_initialized = curl_global_init(CURL_GLOBAL_DEFAULT) == CURLE_OK;
}

static size_t receive_body(char *data, size_t size, size_t count, void *context)
{
    struct response_writer *writer = context;
    if (!writer || !writer->result || (size != 0u && count > SIZE_MAX / size))
    {
        return 0u;
    }
    size_t length = size * count;
    if (length > writer->limit - writer->result->body_len)
    {
        return 0u;
    }
    size_t total = writer->result->body_len + length;
    uint8_t *next = total > 0u ? realloc(writer->result->body, total) : NULL;
    if (total > 0u && !next)
    {
        return 0u;
    }
    if (length > 0u)
    {
        memcpy(next + writer->result->body_len, data, length);
    }
    writer->result->body = next;
    writer->result->body_len = total;
    return length;
}

static bool supported_url(const char *url)
{
    return strncasecmp(url, "http://", 7u) == 0
        || strncasecmp(url, "https://", 8u) == 0;
}

int lantern_http_get_bytes(
    const char *url,
    const char *accept,
    size_t max_response_bytes,
    struct lantern_http_fetch_result *out_result)
{
    if (!url || !out_result || max_response_bytes == 0u || !supported_url(url))
    {
        return LANTERN_HTTP_CLIENT_ERR;
    }
    memset(out_result, 0, sizeof(*out_result));
    pthread_once(&curl_once, initialize_curl);
    CURL *curl = curl_initialized ? curl_easy_init() : NULL;
    const char *accept_value = accept ? accept : "*/*";
    size_t accept_length = strlen(accept_value) + sizeof("Accept: ");
    char *accept_header = malloc(accept_length);
    if (!curl || !accept_header)
    {
        if (curl)
        {
            curl_easy_cleanup(curl);
        }
        free(accept_header);
        return LANTERN_HTTP_CLIENT_ERR;
    }
    snprintf(accept_header, accept_length, "Accept: %s", accept_value);
    struct curl_slist *headers = curl_slist_append(NULL, accept_header);
    free(accept_header);
    struct response_writer writer = {
        .result = out_result,
        .limit = max_response_bytes,
    };
    CURLcode result = headers
            && curl_easy_setopt(curl, CURLOPT_URL, url) == CURLE_OK
            && curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers) == CURLE_OK
            && curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, receive_body) == CURLE_OK
            && curl_easy_setopt(curl, CURLOPT_WRITEDATA, &writer) == CURLE_OK
            && curl_easy_setopt(curl, CURLOPT_NOPROXY, "*") == CURLE_OK
            && curl_easy_setopt(curl, CURLOPT_NOSIGNAL, 1L) == CURLE_OK
        ? curl_easy_perform(curl)
        : CURLE_FAILED_INIT;
    long status = 0;
    if (result == CURLE_OK)
    {
        result = curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &status);
    }
    curl_slist_free_all(headers);
    curl_easy_cleanup(curl);
    if (result != CURLE_OK || status > INT_MAX)
    {
        lantern_http_fetch_result_reset(out_result);
        return LANTERN_HTTP_CLIENT_ERR;
    }
    out_result->status_code = (int)status;
    if (status != 200)
    {
        free(out_result->body);
        out_result->body = NULL;
        out_result->body_len = 0u;
        return LANTERN_HTTP_CLIENT_STATUS_ERROR;
    }
    return LANTERN_HTTP_CLIENT_OK;
}

void lantern_http_fetch_result_reset(struct lantern_http_fetch_result *result)
{
    if (result)
    {
        free(result->body);
        memset(result, 0, sizeof(*result));
    }
}
