#ifndef LANTERN_SUPPORT_STRINGS_H
#define LANTERN_SUPPORT_STRINGS_H

#include <stddef.h>
#include <stdint.h>

char *lantern_string_duplicate(const char *source);
char *lantern_string_duplicate_len(const char *source, size_t length);
size_t lantern_string_copy(char *dst, size_t dst_len, const char *src);
char *lantern_trim_whitespace(char *value);
int lantern_hex_decode(const char *hex, uint8_t *out, size_t out_len);
int lantern_bytes_to_hex(const uint8_t *bytes, size_t len, char *out, size_t out_len, int include_prefix);

#endif /* LANTERN_SUPPORT_STRINGS_H */
