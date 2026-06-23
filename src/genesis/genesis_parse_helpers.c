#include "genesis_internal.h"

#include <ctype.h>
#include <errno.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>

#include "lantern/support/strings.h"

uint64_t genesis_parse_u64(const char *value, int *ok)
{
    if (ok)
    {
        *ok = 0;
    }
    if (!value)
    {
        return 0;
    }

    errno = 0;
    char *end = NULL;
    unsigned long long parsed = strtoull(value, &end, 0);
    if (errno != 0 || end == value)
    {
        return 0;
    }

    while (end && *end && isspace((unsigned char)*end))
    {
        ++end;
    }
    if (end && *end != '\0' && *end != '#')
    {
        return 0;
    }
    if (parsed > (unsigned long long)UINT64_MAX)
    {
        return 0;
    }

    if (ok)
    {
        *ok = 1;
    }
    return (uint64_t)parsed;
}

char *genesis_dup_trimmed(const char *value)
{
    if (!value)
    {
        return NULL;
    }

    const char *start = value;
    while (*start && isspace((unsigned char)*start))
    {
        ++start;
    }

    const char *end = start + strlen(start);
    while (end > start && isspace((unsigned char)*(end - 1)))
    {
        --end;
    }

    if ((end - start) >= 2
        && ((*start == '"' && *(end - 1) == '"') || (*start == '\'' && *(end - 1) == '\'')))
    {
        ++start;
        --end;
    }

    return lantern_string_duplicate_len(start, (size_t)(end - start));
}

const char *genesis_yaml_object_value(const LanternYamlObject *object, const char *key)
{
    if (!object || !key)
    {
        return NULL;
    }

    for (size_t i = 0; i < object->num_pairs; ++i)
    {
        if (object->pairs[i].key && strcmp(object->pairs[i].key, key) == 0)
        {
            return object->pairs[i].value;
        }
    }

    return NULL;
}

int genesis_decode_validator_pubkey_hex(const char *hex, uint8_t out[LANTERN_VALIDATOR_PUBKEY_SIZE])
{
    if (!hex || !out)
    {
        return LANTERN_GENESIS_ERR_INVALID_PARAM;
    }

    if (lantern_hex_decode(hex, out, LANTERN_VALIDATOR_PUBKEY_SIZE) != 0)
    {
        return LANTERN_GENESIS_ERR_PARSE;
    }

    return LANTERN_GENESIS_OK;
}
