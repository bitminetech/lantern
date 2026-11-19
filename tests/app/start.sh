#!/bin/sh
# The start of the lantern binary (docs/reference/app.md): a faulty option gives exit code 1 and
# its line, with today's UTC date; a network directory with no config.yaml gives exit code 2 and a
# "cannot read" line.
# Usage: tests/app/start.sh RUNNER BINARY    (RUNNER: "" or a qemu command)
set -u
runner=$1
binary=$2
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
exit $fail
