"""
Write the tick table of every documented function into the Results section of its
document (ARCHITECTURE.md section 10).

Usage: python3 -I tests/runner/tick_tables.py RESULTS_DIR
Runs from the repo root.

- RESULTS_DIR holds results-<os>-<isa>-<fork>.txt: the output of tests/runner/run.sh
  (or run.ps1) of each target and fork. Its "FUNCTION <symbol> PASS" and
  "FUNCTION <symbol> FAIL" lines name each function the runners called, and
  whether every process that called it passed.
- A symbol lantern_<fork>_<name> of a fork object counts for lantern_<name>.

An OS cell gets a tick when the target has the results of all 7 forks, and the
function is named by at least one FUNCTION line of them and by no FAIL line.
A function the runners never call (one tested only through its callers) gets no
tick. The `equal` column stays empty: lantern has no proofs yet.
"""

import glob
import os
import re
import sys

OSES = ("linux", "windows", "macos")
ISAS = (("x86_64", "x86-64"), ("arm64", "ARM64"), ("riscv64", "RISC-V"))
FORKS = ("phase0", "altair", "bellatrix", "capella", "deneb", "electra", "fulu")
SUPPORTED = {(o, i) for o in OSES for i, _ in ISAS} - {("windows", "riscv64"), ("macos", "riscv64")}
TICK = "✅"
MARKER = "<!-- CI generates the tick table for each function here. -->"
FORK_SYMBOL = re.compile(r"^lantern_(?:%s)_" % "|".join(FORKS))


def documented():
    """[(path, [function])] in document order."""
    docs = []
    for path in sorted(glob.glob("docs/reference/*.md")):
        with open(path, encoding="utf-8") as f:
            functions = re.findall(r"^## Function `([^`]+)`", f.read(), re.M)
        if functions:
            docs.append((path, functions))
    return docs


def results(results_dir, os_name, isa):
    """{function: passed} of a target, or None when a fork's results are missing."""
    out = {}
    for fork in FORKS:
        path = os.path.join(results_dir, f"results-{os_name}-{isa}-{fork}.txt")
        if not os.path.exists(path):
            return None
        with open(path, encoding="utf-8", errors="replace") as f:
            for m in re.finditer(r"^FUNCTION (\S+) (PASS|FAIL)\s*$", f.read(), re.M):
                name = FORK_SYMBOL.sub("lantern_", m.group(1))
                out[name] = out.get(name, True) and m.group(2) == "PASS"
    return out


def table(function, targets):
    lines = [f"### `{function}`", "", "| ISA | Linux | Windows | macOS | `equal` |", "|---|---|---|---|---|"]
    for isa, label in ISAS:
        cells = []
        for o in OSES:
            r = targets.get((o, isa))
            cells.append(TICK if r is not None and r.get(function) is True else "")
        lines.append("| " + " | ".join([label] + cells + [""]) + " |")
    return "\n".join(lines)


def main(results_dir):
    targets = {(o, i): results(results_dir, o, i) for o, i in sorted(SUPPORTED)}
    for path, functions in documented():
        with open(path, encoding="utf-8") as f:
            text = f.read()
        m = re.search(r"^## Results\n", text, re.M)
        if not m:
            sys.exit(f"{path}: no Results section")
        end = re.search(r"^## ", text[m.end():], re.M)
        rest = text[m.end() + end.start():] if end else ""
        tables = "\n\n".join(table(f, targets) for f in functions)
        new = text[: m.end()] + "\n" + MARKER + "\n\n" + tables + "\n" + ("\n" + rest if rest else "")
        if new != text:
            with open(path, "w", encoding="utf-8") as f:
                f.write(new)
            print(f"updated {path}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: tick_tables.py RESULTS_DIR")
    main(sys.argv[1])
