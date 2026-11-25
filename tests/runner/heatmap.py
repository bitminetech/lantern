"""
Write the verification heatmap into the README from the tick tables
(ARCHITECTURE.md section 10).

Usage: python3 -I tests/runner/heatmap.py
Runs from the repo root, after tick_tables.py.

- Reads every tick table in docs/reference/*.md.
- A function's level is the number of ISAs whose proof cells are all ticked.
- Writes the images to docs/heatmap/ and removes images it no longer uses.
- Replaces the block between the two heatmap markers in README.md. Each cell
  links to its function's entry in docs/reference/.
"""

import glob
import os
import re
import sys
from html import escape

MARK_START = "<!-- CI generates the verification heatmap here. -->"
MARK_END = "<!-- End of the verification heatmap. -->"
OUT = "docs/heatmap"
ISAS = ("x86-64", "ARM64", "RISC-V")
TICK = "✅"
LEVELS = ("Not proved", "Proved on 1 ISA", "2 ISAs", "All 3 ISAs")
WIDTH, LABEL, CELL = 840, 236, 20
COLS = (WIDTH - 30 - LABEL) // CELL
FONT = "system-ui,-apple-system,'Segoe UI',Helvetica,Arial,sans-serif"
MONO = "ui-monospace,SFMono-Regular,'SF Mono',Menlo,Consolas,monospace"
THEMES = {
    "light": {"ink": "#1f2328", "ink2": "#59636e", "muted": "#818b98",
              "border": "#d1d9e0", "track": "#eff2f5",
              "fill": ("#ebedf0", "#86b6ef", "#2a78d6", "#104281")},
    "dark": {"ink": "#f0f6fc", "ink2": "#9198a1", "muted": "#6e7681",
             "border": "#3d444d", "track": "#151b23",
             "fill": ("#1f262f", "#1c5cab", "#3987e5", "#9ec5f4")},
}


def functions():
    """[(section, name, level)] in document order."""
    found = []
    for path in sorted(glob.glob("docs/reference/*.md")):
        section = os.path.basename(path)[:-3]
        lines = open(path, encoding="utf-8").read().splitlines()
        for i, line in enumerate(lines):
            m = re.match(r"^### `([^`]+)`$", line)
            if not m or i + 6 >= len(lines) or not lines[i + 2].startswith("| ISA | Linux"):
                continue
            head = [c.strip() for c in lines[i + 2].strip("|").split("|")]
            proofs = len(head) - 4
            level = 0
            for row in lines[i + 4:i + 7]:
                cells = [c.strip() for c in row.strip("|").split("|")]
                if cells[0] in ISAS and proofs and all(c == TICK for c in cells[4:4 + proofs]):
                    level += 1
            found.append((section, m.group(1), level))
    return found


def svg(w, h, body):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" '
            f'viewBox="0 0 {w} {h}">{body}</svg>\n')


def picture(name, alt, title=None):
    t = f' title="{escape(title)}"' if title else ""
    return (f'<picture><source media="(prefers-color-scheme: dark)" '
            f'srcset="{OUT}/{name}-dark.svg"><img src="{OUT}/{name}-light.svg" '
            f'alt="{escape(alt)}"{t}></picture>')


def images(repo, funcs, sections):
    """{file name: SVG text} for both themes."""
    files = {}
    total = len(funcs)
    proved = sum(1 for f in funcs if f[2])
    for mode, th in THEMES.items():
        for level in range(len(LEVELS)):
            files[f"cell-{level}-{mode}.svg"] = svg(CELL, CELL,
                f'<rect x="2" y="2" width="16" height="16" rx="4" fill="{th["fill"][level]}"/>')
        bar, x = "", 0.0
        for level in range(len(LEVELS) - 1, 0, -1):
            n = sum(1 for f in funcs if f[2] == level)
            if n:
                w = max(4.0, WIDTH * n / total)
                bar += (f'<rect x="{x:.1f}" y="70" width="{w - 2:.1f}" height="8" '
                        f'rx="4" fill="{th["fill"][level]}"/>')
                x += w
        files[f"header-{mode}.svg"] = svg(WIDTH, 90,
            f'<rect x="0" y="70" width="{WIDTH}" height="8" rx="4" fill="{th["track"]}"/>{bar}'
            f'<text x="0" y="22" font-family="{MONO}" font-size="12" fill="{th["muted"]}">{escape(repo)}</text>'
            f'<text x="0" y="48" font-family="{FONT}" font-size="20" font-weight="600" '
            f'fill="{th["ink"]}">Formal verification</text>'
            f'<text x="{WIDTH}" y="22" text-anchor="end" font-family="{FONT}" font-size="12" '
            f'fill="{th["muted"]}">functions proved on at least one ISA</text>'
            f'<text x="{WIDTH}" y="50" text-anchor="end" font-family="{FONT}" fill="{th["ink"]}">'
            f'<tspan font-size="28" font-weight="600">{proved}</tspan>'
            f'<tspan font-size="14" fill="{th["ink2"]}" dx="4">/ {total}</tspan></text>')
        for section in sections:
            levels = [f[2] for f in funcs if f[0] == section]
            done = sum(1 for level in levels if level)
            files[f"label-{section}-{mode}.svg"] = svg(LABEL, CELL,
                f'<text x="164" y="14.5" text-anchor="end" font-family="{FONT}" font-size="13" '
                f'fill="{th["ink2"]}">{escape(section)}</text>'
                f'<text x="222" y="14.5" text-anchor="end" font-family="{FONT}" font-size="12" '
                f'style="font-variant-numeric:tabular-nums" fill="{th["ink" if done else "muted"]}">'
                f'{done} / {len(levels)}</text>')
        files[f"label-{mode}.svg"] = svg(LABEL, CELL, "")
        legend, x = "", 0.0
        for level, text in enumerate(LEVELS):
            legend += (f'<rect x="{x:.1f}" y="14" width="12" height="12" rx="3" fill="{th["fill"][level]}"/>'
                       f'<text x="{x + 18:.1f}" y="24.5" font-family="{FONT}" font-size="12" '
                       f'fill="{th["ink2"]}">{text}</text>')
            x += 18 + 7.2 * len(text) + 22
        files[f"legend-{mode}.svg"] = svg(WIDTH, 56,
            f'<line x1="0" y1="2" x2="{WIDTH}" y2="2" stroke="{th["border"]}"/>{legend}'
            f'<text x="0" y="50" font-family="{FONT}" font-size="11" fill="{th["muted"]}">'
            f'Generated by CI from the tick tables. Select a cell to open its function.</text>')
    return files


def block(repo, funcs, sections):
    proved = sum(1 for f in funcs if f[2])
    rows = []
    for section in sections:
        names = [f for f in funcs if f[0] == section]
        for k in range(0, len(names), COLS):
            label = picture(f"label-{section}", section) if k == 0 else picture("label", "")
            cells = "".join(
                f'<a href="docs/reference/{s}.md#function-{n}">'
                + picture(f"cell-{level}", n, f"{n}: {LEVELS[level]}") + "</a>"
                for s, n, level in names[k:k + COLS])
            rows.append(label + cells)
    return (f"{MARK_START}\n<table><tr><td>\n\n"
            + picture("header", f"{repo} formal verification: {proved} of {len(funcs)} functions proved")
            + "\n\n" + "<br>\n".join(rows) + "\n\n" + picture("legend", "Legend")
            + f"\n\n</td></tr></table>\n{MARK_END}")


def main():
    readme = open("README.md", encoding="utf-8").read()
    m = re.match(r"# (\S+)", readme)
    if not m:
        sys.exit("README.md: no title")
    repo = m.group(1)
    funcs = functions()
    if not funcs:
        sys.exit("no tick tables in docs/reference")
    sections = list(dict.fromkeys(f[0] for f in funcs))
    os.makedirs(OUT, exist_ok=True)
    files = images(repo, funcs, sections)
    for name, text in files.items():
        path = os.path.join(OUT, name)
        if not os.path.exists(path) or open(path, encoding="utf-8").read() != text:
            with open(path, "w", encoding="utf-8") as f:
                f.write(text)
    for path in glob.glob(os.path.join(OUT, "*.svg")):
        if os.path.basename(path) not in files:
            os.remove(path)
    start, end = readme.find(MARK_START), readme.find(MARK_END)
    if start < 0 or end < start:
        sys.exit("README.md: no heatmap markers")
    new = readme[:start] + block(repo, funcs, sections) + readme[end + len(MARK_END):]
    if new != readme:
        with open("README.md", "w", encoding="utf-8") as f:
            f.write(new)
        print("updated README.md")


if __name__ == "__main__":
    main()
