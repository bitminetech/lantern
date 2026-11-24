"""Send a burst of UDP datagrams to the node's discv5 port (docs/reference/app.md, the discv5 step).

Usage: python3 tests/app/burst.py PORT [COUNT]

COUNT datagrams (256 by default) of 200 fixed bytes that decode to no discv5 packet, sent at once,
so that a discv5 step of the node gets far more than 64 events.
"""

import socket
import sys

port = int(sys.argv[1])
count = int(sys.argv[2]) if len(sys.argv) > 2 else 256
datagram = bytes(range(200))
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 1 << 20)
for _ in range(count):
    s.sendto(datagram, ("127.0.0.1", port))
s.close()
