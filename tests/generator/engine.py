"""Cases of lantern's Engine API client (docs/reference/engine-api.md).

JWTs follow RFC 7519 and RFC 7515 (HS256), made with Python's hmac, hashlib and base64. HTTP
messages follow RFC 9112. The JSON-RPC requests follow execution-apis 981aa66, with the values
of the spec modules of consensus-specs v1.7.0-beta.4 (aa16bb4).

cases(fork, preset) yields (handler, name, parts).
"""

import base64
import hashlib
import hmac
import json

U64 = (1 << 64) - 1


def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=")


def jwt(secret, iat):
    header = b64url(b'{"alg":"HS256","typ":"JWT"}')
    claims = b64url(b'{"iat":%d}' % iat)
    signing = header + b"." + claims
    return signing + b"." + b64url(hmac.new(secret, signing, hashlib.sha256).digest())


def http_post(host, token, body):
    return (b"POST / HTTP/1.1\r\nHost: " + host + b"\r\nContent-Type: application/json\r\nAuthorization: Bearer "
            + token + b"\r\nContent-Length: " + str(len(body)).encode() + b"\r\n\r\n" + body)


def chunked(body, sizes, ext=b"", trailer=b""):
    out, i = bytearray(), 0
    for n in sizes:
        out += b"%x" % n + ext + b"\r\n" + body[i : i + n] + b"\r\n"
        i += n
    assert i == len(body)
    return bytes(out) + b"0\r\n" + trailer + b"\r\n"


def http_cases():
    """(name, bytes, status, body, kind): kind "length", "chunked" or "close"."""
    body = b'{"jsonrpc":"2.0","id":1,"result":{"status":"VALID","latestValidHash":"0x' + b"ab" * 32 + b'","validationError":null}}'
    cases = [
        ("length", b"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\n\r\n" % len(body) + body, 200, body, "length"),
        ("length_case", b"HTTP/1.1 200 OK\r\ncontent-length:   %d \t\r\nX-Other: a\r\n\r\n" % len(body) + body, 200, body, "length"),
        ("length_zero", b"HTTP/1.1 401 Unauthorized\r\nContent-Length: 0\r\n\r\n", 401, b"", "length"),
        ("length_twice_same", b"HTTP/1.1 200 OK\r\nContent-Length: 5\r\nContent-Length: 5\r\n\r\nhello", 200, b"hello", "length"),
        ("chunked", b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n" + chunked(body, [10, 1, len(body) - 11]), 200, body, "chunked"),
        ("chunked_ext", b"HTTP/1.1 200 OK\r\ntransfer-encoding: CHUNKED\r\n\r\n" + chunked(body, [len(body)], b";a=b", b"X-T: 1\r\n"), 200, body, "chunked"),
        ("chunked_over_length", b"HTTP/1.1 200 OK\r\nContent-Length: 3\r\nTransfer-Encoding: chunked\r\n\r\n" + chunked(b"hello", [2, 3]), 200, b"hello", "chunked"),
        ("chunked_hex", b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n" + b"1A\r\n" + b"z" * 26 + b"\r\n0\r\n\r\n", 200, b"z" * 26, "chunked"),
        ("close", b"HTTP/1.0 500 Internal Server Error\r\n\r\n" + body, 500, body, "close"),
        ("no_content", b"HTTP/1.1 204 No Content\r\n\r\n", 204, b"", "length"),
        ("continue", b"HTTP/1.1 100 Continue\r\n\r\n", 100, b"", "length"),
    ]
    return cases


def cases(fork, preset):
    secret = hashlib.sha256(b"lantern jwt").digest()
    for iat in (0, 1, 9, 10, 1700000000, 1999999999, U64):
        yield "jwt_token", f"iat_{iat}", {"input": {"secret": secret, "iat": iat}, "output": jwt(secret, iat)}
    yield "jwt_token", "zero_secret", {"input": {"secret": bytes(32), "iat": 1700000000}, "output": jwt(bytes(32), 1700000000)}

    token = jwt(secret, 1700000000)
    for k, (host, body) in enumerate([(b"localhost:8551", b'{"jsonrpc":"2.0","id":1,"method":"engine_exchangeCapabilities","params":[[]]}'),
                                      (b"10.0.0.2:8551", b""), (b"el", b"x" * 1000)]):
        yield "http_post", f"post_{k}", {"input": {"host": host, "token": token, "body": body}, "output": http_post(host, token, body)}

    for name, data, status, body, kind in http_cases():
        tail = b"HTTP/1.1 200 OK\r\n"  # the next response's first bytes
        whole = {"status": status, "body": body, "consumed": len(data)}
        if kind == "close":
            yield "http_parse_response", name, {"input": {"bytes": data, "eof": 1}, "output": whole}
        else:
            yield "http_parse_response", name, {"input": {"bytes": data + tail, "eof": 0}, "output": whole}
            yield "http_parse_response", name + "_eof", {"input": {"bytes": data, "eof": 1}, "output": whole}
        head_end = data.index(b"\r\n\r\n") + 4
        for cut in range(len(data)):
            more = {"input": {"bytes": data[:cut], "eof": 0}, "output": "more"}
            yield "http_parse_response", f"{name}_cut{cut}", more
            if kind == "close" and cut >= head_end:
                want = {"status": status, "body": data[head_end:cut], "consumed": cut}
            else:
                want = "invalid"
            yield "http_parse_response", f"{name}_cut{cut}_eof", {"input": {"bytes": data[:cut], "eof": 1}, "output": want}
    bad = [
        b"HTTP/2 200 OK\r\n\r\n", b"HTTP/1.1 20 OK\r\n\r\n", b"HTTP/1.1 2000 OK\r\n\r\n", b"HTTP/1.1  200 OK\r\n\r\n",
        b"HTTP/1.1 200OK\r\n\r\n", b"http/1.1 200 OK\r\n\r\n", b"HTTP/1.1 200 OK\nContent-Length: 0\r\n\r\n",
        b"HTTP/1.1 200 OK\r\nContent-Length: abc\r\n\r\n", b"HTTP/1.1 200 OK\r\nContent-Length: 1\r\nContent-Length: 2\r\n\r\nab",
        b"HTTP/1.1 200 OK\r\nNoColon\r\n\r\n", b"HTTP/1.1 200 OK\r\n: empty\r\n\r\n",
        b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\nzz\r\n",
        b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n2\r\nabc\r\n0\r\n\r\n",
        b"HTTP/1.1 200 OK\r\nContent-Length: 99999999999999999999999\r\n\r\n",
    ]
    for k, data in enumerate(bad):
        yield "http_parse_response", f"bad_{k}", {"input": {"bytes": data, "eof": 1}, "output": "invalid"}
