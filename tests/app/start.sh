#!/bin/sh
# The start of the lantern binary (docs/reference/app.md): a faulty option gives exit code 1 and
# its line, with today's UTC date; a network directory with no config.yaml gives exit code 2 and a
# "cannot read" line. With NETWORK, the binary runs on that network directory with
# --http-max-connections 2, tests/app/api.py checks its Beacon API's connections, and tests/app/burst.py
# gives discv5 a step of far more than 64 datagrams, after which the log holds no discv5 status line.
# Usage: tests/app/start.sh RUNNER BINARY [NETWORK]    (RUNNER: "" or a qemu command)
set -u
runner=$1
binary=$2
network=${3:-}
fail=0
out=$($runner "$binary" --bogus 2>&1); code=$?
echo "$out"
case "$out" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]" "[0-9][0-9]:[0-9][0-9]:[0-9][0-9].[0-9][0-9][0-9]" ERROR faulty option at argument 0") ok=1 ;;
  *) ok=0 ;;
esac
[ "$(echo "$out" | cut -c1-10)" = "$(date -u +%Y-%m-%d)" ] || ok=0     # the line's UTC date is today's
if [ $code -eq 1 ] && [ $ok -eq 1 ]; then echo "PASS a faulty option"; else echo "FAIL a faulty option: exit $code"; fail=1; fi
out=$($runner "$binary" --network-dir /nonexistent 2>&1); code=$?
echo "$out"
case "$out" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]" "*" ERROR cannot read /nonexistent/config.yaml: error "*) ok=1 ;;
  *) ok=0 ;;
esac
if [ $code -eq 2 ] && [ $ok -eq 1 ]; then echo "PASS a missing network directory"; else echo "FAIL a missing network directory: exit $code"; fail=1; fi
if [ -n "$network" ]; then
    log=$(mktemp)
    $runner "$binary" --network-dir "$network" --port 19100 --http-port 15052 --http-max-connections 2 > "$log" 2>&1 &
    pid=$!
    python3 "$(dirname "$0")/api.py" 15052 "$network/genesis.ssz" || fail=1
    python3 "$(dirname "$0")/burst.py" 19100 256; sleep 2   # a discv5 step of far more than 64 events
    if grep -q "discv5: status" "$log"; then echo "FAIL discv5 with a burst of datagrams: $(grep -m1 'discv5: status' "$log")"; fail=1
    else echo "PASS discv5 with a burst of datagrams"; fi
    kill -INT $pid 2>/dev/null; sleep 1; kill -9 $pid 2>/dev/null
    head -5 "$log"
    rm -f "$log"
fi
exit $fail
