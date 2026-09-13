#include "lantern/support/strings.h"

#include <ctype.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

char *lantern_string_duplicate(const char *source)
{
    if (!source)
    {
        return NULL;
    }

    return lantern_string_duplicate_len(source, strlen(source));
}

char *lantern_string_duplicate_len(const char *source, size_t length)
{
    if (!source || length == SIZE_MAX)
    {
        return NULL;
    }

    char *copy = malloc(length + 1u);

    if (!copy)
    {
        return NULL;
    }

    memcpy(copy, source, length);
    copy[length] = '\0';
    return copy;
}

enum lantern_string_copy_result
lantern_string_copy(char *dst, size_t dst_len, const char *src,
                    size_t *out_source_len)
{
    if (!src)
    {
        if (dst && dst_len > 0)
        {
            dst[0] = '\0';
        }

        return LANTERN_STRING_COPY_ERR_INVALID;
    }

    if (!dst || dst_len == 0)
    {
        return LANTERN_STRING_COPY_ERR_INVALID;
    }

    const size_t src_len = strlen(src);
    size_t copy_len = src_len;

    if (copy_len >= dst_len)
    {
        copy_len = dst_len - 1u;
    }

    if (copy_len > 0)
    {
        memcpy(dst, src, copy_len);
    }

    dst[copy_len] = '\0';

    if (out_source_len)
    {
        *out_source_len = src_len;
    }

    return copy_len == src_len ? LANTERN_STRING_COPY_OK
                               : LANTERN_STRING_COPY_TRUNCATED;
}

char *lantern_trim_whitespace(char *value)
{
    if (!value)
    {
        return NULL;
    }

    while (*value && isspace((unsigned char)*value))
    {
        ++value;
    }

    char *end = value + strlen(value);

    while (end > value && isspace((unsigned char)*(end - 1)))
    {
        --end;
    }

    *end = '\0';
    return value;
}
