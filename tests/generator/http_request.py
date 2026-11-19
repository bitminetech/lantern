"""Cases of lantern_http_request (docs/reference/beacon-api.md).

read() below follows the rules of lantern_http_request, apart from the assembly: RFC 9112 sections 2
to 7 and RFC 9110 section 5, with the choices that beacon-api.md writes down.

cases() yields (name, parts): "bytes", the connection's bytes; "head_max" and "body_max"; "status"
and "http_status" of the whole bytes; "prefix", 3 bytes for each shorter length k (the status of
the first k bytes, then its HTTP status as a little endian u16); and for a request read, "used",
"method", "version", "close", and the six parts "path", "query", "accept", "content_type",
"consensus_version" and "body".
"""

OK, BUFFER_TOO_SMALL, INVALID_HTTP, HTTP_MORE = 0, 1, 52, 53
GET, POST, OTHER = 1, 2, 3
FIXED = 144
TCHAR = set(b"!#$%&'*+-.^_`|~0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
HEX = set(b"0123456789abcdefABCDEF")
U64 = 2 ** 64 - 1
PARTS = ("path", "query", "accept", "content_type", "consensus_version", "body")


class Fault(Exception):
    def __init__(self, http):
        self.http = http


class More(Exception):
    pass


def tokens(value):
    return [t.strip(b" \t").lower() for t in value.split(b",")]


def read(b, head_max, body_max):
    """(status, http_status, request or None)."""
    try:
        return OK, 0, read_request(b, head_max, body_max)
    except More:
        return HTTP_MORE, 0, None
    except Fault as f:
        return INVALID_HTTP, f.http, None


def read_request(b, head_max, body_max):
    n = len(b)
    p = 0
    while b[p:p + 2] == b"\r\n":                # empty lines before the request line
        p += 2
    e = b.find(b"\r\n\r\n", p)
    if e < 0:
        if n >= head_max:
            raise Fault(431)
        raise More
    if e + 4 > head_max:
        raise Fault(431)
    lines = b[p:e].split(b"\r\n")
    words = lines[0].split(b" ")
    if len(words) != 3:
        raise Fault(400)
    method, target, version = words
    if not method or any(c not in TCHAR for c in method):
        raise Fault(400)
    if not target.startswith(b"/") or any(c < 0x21 or c > 0x7E for c in target):
        raise Fault(400)
    if len(version) != 8 or version[:5] != b"HTTP/" or version[6:7] != b"." or not version[5:6].isdigit() \
            or not version[7:8].isdigit():
        raise Fault(400)
    if version == b"HTTP/1.1":
        ver = 11
    elif version == b"HTTP/1.0":
        ver = 10
    else:
        raise Fault(505)
    fields = {}
    for line in lines[1:]:
        if line[:1] in (b" ", b"\t"):
            raise Fault(400)                    # obsolete line folding
        colon = line.find(b":")
        if colon <= 0 or any(c not in TCHAR for c in line[:colon]):
            raise Fault(400)
        value = line[colon + 1:].strip(b" \t")
        if any(c in (0, 10, 13) for c in value):
            raise Fault(400)
        fields.setdefault(line[:colon].lower(), []).append(value)
    hosts = len(fields.get(b"host", []))
    if hosts > 1 or (ver == 11 and hosts != 1):
        raise Fault(400)
    te, cl = fields.get(b"transfer-encoding"), fields.get(b"content-length")
    if te is not None and cl is not None:
        raise Fault(400)
    if te is not None and ver == 10:
        raise Fault(400)
    if te is not None and b", ".join(te).lower() != b"chunked":
        raise Fault(501)
    length = None
    if cl is not None:
        values = set()
        for v in cl:
            for item in v.split(b","):
                item = item.strip(b" \t")
                if not item or not item.isdigit():
                    raise Fault(400)
                values.add(int(item))
        if len(values) != 1 or max(values) > U64:
            raise Fault(400)
        length = values.pop()
        if length > body_max:
            raise Fault(413)
    conn = tokens(b", ".join(fields.get(b"connection", [])))
    close = 1 if b"close" in conn or (ver == 10 and b"keep-alive" not in conn) else 0
    q = e + 4
    if length is not None:
        if n < q + length:
            raise More
        body, q = b[q:q + length], q + length
    elif te is not None:
        body, q = read_chunked(b, q, head_max, body_max)
    else:
        body = b""
    path, _, query = target.partition(b"?")
    joined = {k: b", ".join(fields.get(k, [])) for k in (b"accept", b"content-type", b"eth-consensus-version")}
    return {"used": q, "method": GET if method == b"GET" else POST if method == b"POST" else OTHER,
            "version": ver, "close": close, "path": path, "query": query, "accept": joined[b"accept"],
            "content_type": joined[b"content-type"], "consensus_version": joined[b"eth-consensus-version"],
            "body": body}


def read_chunked(b, q, head_max, body_max):
    n, body = len(b), bytearray()
    while True:
        le = b.find(b"\r\n", q)
        if le < 0:
            if n - q > head_max:
                raise Fault(400)
            raise More
        line = b[q:le]
        if len(line) > head_max:
            raise Fault(400)
        d = 0
        while d < len(line) and line[d] in HEX:
            d += 1
        if d == 0:
            raise Fault(400)
        size = int(line[:d], 16)
        rest = line[d:]
        if size > U64 or (rest and rest[:1] not in (b";", b" ", b"\t")) or any(c in (0, 10, 13) for c in rest):
            raise Fault(400)
        q = le + 2
        if size == 0:
            break
        if len(body) + size > body_max:
            raise Fault(413)
        if n < q + size + 2:
            raise More
        if b[q + size:q + size + 2] != b"\r\n":
            raise Fault(400)
        body += b[q:q + size]
        q += size + 2
    trailers = 0
    while True:                                 # trailer lines, skipped, up to the empty line
        le = b.find(b"\r\n", q)
        if le < 0:
            if trailers + n - q > head_max:
                raise Fault(431)
            raise More
        trailers += le + 2 - q
        if trailers > head_max:
            raise Fault(431)
        line, q = b[q:le], le + 2
        if not line:
            return bytes(body), q


def out_size(req):
    return FIXED + sum((len(req[k]) + 7) // 8 * 8 for k in PARTS)


def case(b, head_max=512, body_max=1024):
    status, http, req = read(b, head_max, body_max)
    prefix = bytearray()
    for k in range(len(b)):
        s, h, _ = read(b[:k], head_max, body_max)
        prefix += bytes([s]) + h.to_bytes(2, "little")
    parts = {"bytes": b, "head_max": head_max, "body_max": body_max, "status": status, "http_status": http,
             "prefix": bytes(prefix)}
    if req:
        parts.update(req)
        parts["out_size"] = out_size(req)
    return parts


H = b"Host: localhost:5052\r\n"


def cases():
    yield "get", case(b"GET /eth/v1/node/health HTTP/1.1\r\n" + H + b"\r\n")
    yield "get_query", case(b"GET /eth/v1/events?topics=head,block HTTP/1.1\r\n" + H + b"Accept: text/event-stream\r\n\r\n")
    yield "empty_query", case(b"GET /eth/v1/node/version? HTTP/1.1\r\n" + H + b"\r\n")
    yield "post_body", case(b"POST /eth/v1/beacon/pool/voluntary_exits HTTP/1.1\r\n" + H +
                            b"Content-Type: application/json\r\nContent-Length: 13\r\n\r\n{\"message\":1}")
    yield "other_method", case(b"PUT /eth/v1/node/health HTTP/1.1\r\n" + H + b"\r\n")
    yield "lower_case_method", case(b"get /eth/v1/node/health HTTP/1.1\r\n" + H + b"\r\n")
    yield "http_1_0", case(b"GET /eth/v1/node/version HTTP/1.0\r\n\r\n")
    yield "http_1_0_keep_alive", case(b"GET /eth/v1/node/version HTTP/1.0\r\nConnection: Keep-Alive\r\n\r\n")
    yield "close", case(b"GET / HTTP/1.1\r\n" + H + b"Connection: foo, CLOSE\r\n\r\n")
    yield "http_2", case(b"GET / HTTP/2.0\r\n" + H + b"\r\n")
    yield "http_bad_version", case(b"GET / HTTP/1.x\r\n" + H + b"\r\n")
    yield "no_version", case(b"GET /\r\n" + H + b"\r\n")
    yield "two_spaces", case(b"GET  / HTTP/1.1\r\n" + H + b"\r\n")
    yield "absolute_form", case(b"GET http://x/ HTTP/1.1\r\n" + H + b"\r\n")
    yield "target_space", case(b"GET /a b HTTP/1.1\r\n" + H + b"\r\n")
    yield "bad_method", case(b"G(T / HTTP/1.1\r\n" + H + b"\r\n")
    yield "leading_empty_lines", case(b"\r\n\r\nGET / HTTP/1.1\r\n" + H + b"\r\n")
    yield "fields_any_case", case(b"GET / HTTP/1.1\r\nhOsT: x\r\naccept: application/json\r\n"
                                  b"ETH-CONSENSUS-VERSION: fulu\r\ncontent-type:application/octet-stream \r\n\r\n")
    yield "accept_joined", case(b"GET / HTTP/1.1\r\n" + H + b"Accept: application/json;q=0.9\r\n"
                                b"Accept:  application/octet-stream\r\n\r\n")
    yield "space_before_colon", case(b"GET / HTTP/1.1\r\n" + H + b"Accept : */*\r\n\r\n")
    yield "folded_line", case(b"GET / HTTP/1.1\r\n" + H + b"Accept: a,\r\n b\r\n\r\n")
    yield "no_colon", case(b"GET / HTTP/1.1\r\n" + H + b"Accept\r\n\r\n")
    yield "nul_in_value", case(b"GET / HTTP/1.1\r\n" + H + b"Accept: a\x00b\r\n\r\n")
    yield "bare_lf_in_value", case(b"GET / HTTP/1.1\r\n" + H + b"Accept: a\nb\r\n\r\n")
    yield "no_host", case(b"GET / HTTP/1.1\r\n\r\n")
    yield "two_hosts", case(b"GET / HTTP/1.1\r\n" + H + H + b"\r\n")
    yield "length_zero", case(b"POST /x HTTP/1.1\r\n" + H + b"Content-Length: 0\r\n\r\n")
    yield "length_equal_twice", case(b"POST /x HTTP/1.1\r\n" + H + b"Content-Length: 3\r\nContent-Length: 3, 03\r\n\r\nabc")
    yield "length_differ", case(b"POST /x HTTP/1.1\r\n" + H + b"Content-Length: 3\r\nContent-Length: 4\r\n\r\nabcd")
    yield "length_not_digits", case(b"POST /x HTTP/1.1\r\n" + H + b"Content-Length: +3\r\n\r\nabc")
    yield "length_too_big", case(b"POST /x HTTP/1.1\r\n" + H + b"Content-Length: 1025\r\n\r\n")
    yield "length_at_limit", case(b"POST /x HTTP/1.1\r\n" + H + b"Content-Length: 1024\r\n\r\n" + bytes(range(256)) * 4)
    yield "length_overflow", case(b"POST /x HTTP/1.1\r\n" + H + b"Content-Length: 18446744073709551616\r\n\r\n")
    yield "chunked", case(b"POST /x HTTP/1.1\r\n" + H + b"Transfer-Encoding: chunked\r\n\r\n"
                          b"5\r\nhello\r\n1;ext=1\r\n \r\nA\r\n0123456789\r\n0\r\n\r\n")
    yield "chunked_trailers", case(b"POST /x HTTP/1.1\r\n" + H + b"Transfer-Encoding: Chunked\r\n\r\n"
                                   b"3\r\nabc\r\n000\r\nX-Trailer: 1\r\nY: 2\r\n\r\n")
    yield "chunked_bad_size", case(b"POST /x HTTP/1.1\r\n" + H + b"Transfer-Encoding: chunked\r\n\r\nzz\r\nab\r\n0\r\n\r\n")
    yield "chunked_bad_after_size", case(b"POST /x HTTP/1.1\r\n" + H + b"Transfer-Encoding: chunked\r\n\r\n2x\r\nab\r\n0\r\n\r\n")
    yield "chunked_no_crlf", case(b"POST /x HTTP/1.1\r\n" + H + b"Transfer-Encoding: chunked\r\n\r\n2\r\nabXY0\r\n\r\n")
    yield "chunked_too_big", case(b"POST /x HTTP/1.1\r\n" + H + b"Transfer-Encoding: chunked\r\n\r\n"
                                  b"200\r\n" + bytes(512) + b"\r\n201\r\n" + bytes(513) + b"\r\n0\r\n\r\n")
    yield "chunked_size_overflow", case(b"POST /x HTTP/1.1\r\n" + H + b"Transfer-Encoding: chunked\r\n\r\n"
                                        b"10000000000000000\r\nab\r\n0\r\n\r\n")
    yield "chunked_and_length", case(b"POST /x HTTP/1.1\r\n" + H + b"Content-Length: 3\r\nTransfer-Encoding: chunked\r\n\r\n"
                                     b"3\r\nabc\r\n0\r\n\r\n")
    yield "chunked_http_1_0", case(b"POST /x HTTP/1.0\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n")
    yield "gzip", case(b"POST /x HTTP/1.1\r\n" + H + b"Transfer-Encoding: gzip, chunked\r\n\r\n0\r\n\r\n")
    head = b"GET / HTTP/1.1\r\n" + H + b"X: "
    pad = 256 - len(head) - 4
    yield "head_at_limit", case(head + b"a" * pad + b"\r\n\r\n", head_max=256)
    yield "head_past_limit", case(head + b"a" * (pad + 1) + b"\r\n\r\n", head_max=256)
    yield "head_never_ends", case(head + b"a" * 300, head_max=256)
    yield "pipelined", case(b"GET /a HTTP/1.1\r\n" + H + b"\r\nGET /b HTTP/1.1\r\n" + H + b"\r\n")
    yield "pipelined_after_body", case(b"POST /a HTTP/1.1\r\n" + H + b"Content-Length: 2\r\n\r\nhiGET /b HTTP/1.1\r\n")
    yield "garbage", case(b"\x00\x01\x02\r\n\r\n")
    yield "empty", case(b"")
