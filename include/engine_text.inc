/*
 * The text of the Engine API client's JWTs and HTTP messages, as read only data for
 * asm/core/<ISA>/engine.s. Every ISA's engine.s ends with ENGINE_TEXT_DATA.
 */
.macro ENGINE_TEXT_DATA
    RODATA
base64url_alphabet:
    .ascii  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
jwt_header:                                 /* base64url({"alg":"HS256","typ":"JWT"}) and its dot: 37 bytes */
    .ascii  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."
jwt_claims:                                 /* "iat": after the brace, 6 bytes */
    .byte   0x22
    .ascii  "iat"
    .byte   0x22
    .ascii  ":"
http_post_1:                                /* 23 bytes */
    .ascii  "POST / HTTP/1.1"
    .byte   13, 10
    .ascii  "Host: "
http_post_2:                                /* 56 bytes */
    .byte   13, 10
    .ascii  "Content-Type: application/json"
    .byte   13, 10
    .ascii  "Authorization: Bearer "
http_post_3:                                /* 18 bytes */
    .byte   13, 10
    .ascii  "Content-Length: "
http_crlf2:
    .byte   13, 10, 13, 10
http_version:
    .ascii  "HTTP/1."
http_content_length:
    .ascii  "content-length"
http_transfer_encoding:
    .ascii  "transfer-encoding"
http_chunked:
    .ascii  "chunked"
engine_text_end:
.if (jwt_claims - jwt_header != 37) || (http_post_1 - jwt_claims != 6) || (http_post_2 - http_post_1 != 23) || (http_post_3 - http_post_2 != 56) || (http_crlf2 - http_post_3 != 18) || (http_version - http_crlf2 != 4)
.error "a length of the Engine API client's text is wrong"
.endif
.endm
