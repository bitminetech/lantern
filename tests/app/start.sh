#!/bin/sh
# The start of the lantern binary (docs/reference/app.md): a faulty option gives exit code 1 and
# its line; a network directory with no config.yaml gives exit code 2 and a "cannot read" line.
# Usage: tests/app/start.sh RUNNER BINARY    (RUNNER: "" or a qemu command)
set -u
runner=$1
binary=$2
fail=0
out=$($runner "$binary" --bogus 2>&1); code=$?
echo "$out"
if [ $code -eq 1 ] && [ "$out" = "lantern: faulty option at argument 0" ]; then echo "PASS a faulty option"; else echo "FAIL a faulty option: exit $code"; fail=1; fi
out=$($runner "$binary" --network-dir /nonexistent 2>&1); code=$?
echo "$out"
case "$out" in
  "lantern: cannot read /nonexistent/config.yaml: error "*) ok=1 ;;
  *) ok=0 ;;
esac
if [ $code -eq 2 ] && [ $ok -eq 1 ]; then echo "PASS a missing network directory"; else echo "FAIL a missing network directory: exit $code"; fail=1; fi
exit $fail
