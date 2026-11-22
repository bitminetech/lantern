# Debug only: the ARM64 mainnet binary under gdb, which prints the signal, the backtrace and the
# registers when it stops.
FROM debian:trixie-slim@sha256:a72b4433de1cf7d6bae0c4cee74d0547f58601a643b3375f070c51600d63b6b2
RUN apt-get update && apt-get install -y --no-install-recommends gdb && rm -rf /var/lib/apt/lists/*
COPY linux-arm64/lantern-mainnet /lantern
ENTRYPOINT ["gdb", "-q", "-batch", "-ex", "handle SIGPIPE nostop noprint pass", "-ex", "run", "-ex", "bt 20", "-ex", "info registers", "-ex", "x/12i $pc-24", "--args", "/lantern"]
