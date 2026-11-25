"""
Check that the docs and the code name the same functions (ARCHITECTURE.md
sections 5 and 11).

Usage:
  python3 -I platform/check.py build/<target> ...
    For each target built by platform/build-all.sh: reads the functions of
    the objects of its mainnet preset and of its entry point
    (build/<target>/mainnet/*.o, build/<target>/entry.o), writes them to
    build/<target>/functions.txt, and checks them.
  python3 -I platform/check.py --docs FUNCTIONS_TXT ...
    Checks the docs against the functions.txt files of all 7 targets.
Runs from the repo root; the first form inside the image from
platform/linux/Dockerfile. It exits with status 1 when any check fails.

Checks of each target:
- Names: every function starts with lantern_, but the entry point of the
  OS (_start, main or mainCRTStartup).
- Entries: every function has a "## Function" entry in docs/reference/.
Checks of the docs, with the functions of all 7 targets:
- Entries: every documented function is a function of some target.
- Roles: every entry has its "- Role:" line.

A function of a fork object, lantern_<fork>_<name>, is the function
lantern_<name> (include/forks.inc).
"""

import glob
import os
import re
import subprocess
import sys

FORKS = ("phase0", "altair", "bellatrix", "capella", "deneb", "electra", "fulu")
ENTRY_POINTS = {"_start", "main", "mainCRTStartup"}
FORK_NAME = re.compile(r"^lantern_(?:%s)_" % "|".join(FORKS))

failures = []


def entries():
    """{function: role or None} from the documentation entries."""
    roles = {}
    for path in sorted(glob.glob("docs/reference/*.md")):
        function = None
        with open(path, encoding="utf-8") as f:
            for line in f:
                m = re.match(r"## Function `([^`]+)`", line)
                if m:
                    function = m.group(1)
                    roles[function] = None
                elif line.startswith("## "):
                    function = None
                elif function:
                    m = re.match(r"- Role: (L[012])\.", line)
                    if m:
                        roles[function] = m.group(1)
    return roles


def is_temporary(name):
    return name.startswith((".L", "ltmp", "$", "L"))


def functions(target_dir):
    """The functions defined in the mainnet objects of a target."""
    macos = os.path.basename(target_dir.rstrip("/")).startswith("macos")
    objects = sorted(glob.glob(os.path.join(target_dir, "mainnet", "*.o")))
    entry = os.path.join(target_dir, "entry.o")
    if os.path.exists(entry):
        objects.append(entry)
    if not objects:
        sys.exit(f"check.py: no objects in {target_dir}/mainnet")
    out = subprocess.run(["llvm-nm", "--defined-only", *objects],
                         check=True, capture_output=True, text=True).stdout
    names = set()
    for line in out.splitlines():
        parts = line.split()
        if len(parts) != 3 or parts[1] not in "Tt":
            continue
        name = parts[2]
        if macos and name.startswith("_"):
            name = name[1:]
        if is_temporary(name):
            continue
        names.add(FORK_NAME.sub("lantern_", name))
    return names


def check_target(target_dir, documented):
    target = os.path.basename(target_dir.rstrip("/"))
    names = functions(target_dir)
    with open(os.path.join(target_dir, "functions.txt"), "w", encoding="utf-8") as f:
        f.write("".join(n + "\n" for n in sorted(names)))
    for name in sorted(names):
        if not name.startswith("lantern_") and name not in ENTRY_POINTS:
            failures.append(f"{target}: function {name} does not start with lantern_")
        elif name not in documented:
            failures.append(f"{target}: function {name} has no documentation entry")
    print(f"check.py: {target}: {len(names)} functions")


def check_docs(lists, documented):
    if len(lists) != 7:
        failures.append(f"docs: {len(lists)} function lists, not the 7 targets")
    code = set()
    for path in lists:
        with open(path, encoding="utf-8") as f:
            code |= {line.strip() for line in f if line.strip()}
    for name, role in sorted(documented.items()):
        if name not in code:
            failures.append(f"docs: documented function {name} is in no target")
        if role is None:
            failures.append(f"docs: function {name} has no Role line")
    print(f"check.py: docs: {len(documented)} entries, {len(code)} functions in all targets")


def main():
    args = sys.argv[1:]
    if not args:
        sys.exit(__doc__)
    documented = entries()
    if args[0] == "--docs":
        check_docs(args[1:], documented)
    else:
        for target_dir in args:
            check_target(target_dir, documented)
    for line in failures:
        print(line)
    sys.exit(1 if failures else 0)


main()
