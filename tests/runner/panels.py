"""
Write the supported platforms, CI and docs panels into the README
(ARCHITECTURE.md section 11). heatmap.py writes the fourth panel.

Usage: python3 -I tests/runner/panels.py [RUN_JSON JOBS_JSONL]
Runs from the repo root.

- Supported platforms: the seven targets of ARCHITECTURE.md section 7.
- CI: the run in RUN_JSON (gh api repos/<repo>/actions/runs/<id>) and its jobs
  in JOBS_JSONL (gh api --paginate .../jobs --jq '.jobs[]', one job per line).
  Without them, the CI panel stays as it is. The results job is the one that
  runs this script, so the panel shows it as running.
- Docs: one card for each docs/reference/*.md and docs/models/*.md, from its
  title and the summary line under the title.
- Writes the images to docs/readme/ and replaces the block between each
  panel's two markers in README.md.
"""

import glob
import json
import os
import re
import sys
from datetime import datetime
from html import escape

OUT = "docs/readme"
WIDTH, LABEL = 840, 236
CARD_W, CARD_H = 398, 64
FONT = "system-ui,-apple-system,'Segoe UI',Helvetica,Arial,sans-serif"
MONO = "ui-monospace,SFMono-Regular,'SF Mono',Menlo,Consolas,monospace"
THEMES = {
    "light": {"ink": "#1f2328", "ink2": "#59636e", "muted": "#818b98", "border": "#d1d9e0",
              "track": "#eff2f5", "panel": "#f6f8fa", "glyph": "#ffffff",
              "success": "#1a7f37", "failure": "#d1242f", "other": "#818b98"},
    "dark": {"ink": "#f0f6fc", "ink2": "#9198a1", "muted": "#6e7681", "border": "#3d444d",
             "track": "#151b23", "panel": "#151b23", "glyph": "#0d1117",
             "success": "#3fb950", "failure": "#f85149", "other": "#6e7681"},
}
MARKS = {
    "platforms": ("<!-- CI generates the supported platforms panel here. -->",
                  "<!-- End of the supported platforms panel. -->"),
    "ci": ("<!-- CI generates the CI panel here. -->", "<!-- End of the CI panel. -->"),
    "docs": ("<!-- CI generates the docs panel here. -->", "<!-- End of the docs panel. -->"),
}

# ARCHITECTURE.md section 7: the targets of every repo.
ISAS = ("x86-64", "ARM64", "RISC-V")
TARGETS = (("Linux", "", ISAS), ("Windows", "", ISAS[:2]), ("macOS", "11.0 or later", ISAS[:2]))

# CI jobs: the job ID of ci.yml is the part of the job name before " (".
OS_NAMES = {"linux": "Linux", "windows": "Windows", "macos": "macOS"}
ISA_NAMES = {"x86_64": "x86-64", "arm64": "ARM64", "riscv64": "RISC-V"}
LABELS = {
    "build": "Build", "build-macos": "Build", "key": "Vector cache key", "vectors": "Vectors",
    "trusted-setup": "Trusted setup", "docs": "Docs check", "supporting-proofs": "Lean proofs",
    "interop": "Interop", "interop-tcp": "Interop over TCP", "interop-quic": "Interop over QUIC",
    "gossipsub": "gossipsub interop", "devnet": "Following each client", "restart": "Restart",
    "fork": "Fork", "checkpoint": "Checkpoint start", "assertoor": "Assertoor",
    "sync": "Sync from lantern", "differential": "Differential reads",
    "validator": "Validator clients", "results": "Results", "interop-results": "Interop results",
}
GROUPS = {"interop": "Interop", "interop-tcp": "Interop", "interop-quic": "Interop",
          "gossipsub": "Interop", "supporting-proofs": "Proofs", "devnet": "Devnets",
          "restart": "Devnets", "fork": "Devnets", "checkpoint": "Devnets",
          "assertoor": "Devnets", "sync": "Devnets", "differential": "Devnets",
          "validator": "Devnets"}


def svg(w, h, body):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h:.0f}" '
            f'viewBox="0 0 {w} {h:.0f}">{body}</svg>\n')


def picture(name, alt):
    return (f'<picture><source media="(prefers-color-scheme: dark)" '
            f'srcset="{OUT}/{name}-dark.svg"><img src="{OUT}/{name}-light.svg" '
            f'alt="{escape(alt)}"></picture>')


def text(x, y, s, th, size=13, color="ink", weight=None, anchor=None, font=FONT, extra=""):
    w = f' font-weight="{weight}"' if weight else ""
    a = f' text-anchor="{anchor}"' if anchor else ""
    return (f'<text x="{x}" y="{y}"{a} font-family="{font}" font-size="{size}"{w} '
            f'fill="{th[color]}"{extra}>{s}</text>')


def header(repo, source, title, caption, number, th, title_x=0, extra=""):
    """The top of a panel: source line, title, caption and number on the right."""
    return (text(0, 22, escape(f"{repo} / {source}"), th, 12, "muted", font=MONO)
            + extra
            + f'<text x="{title_x}" y="48" font-family="{FONT}" font-size="20" font-weight="600" '
              f'fill="{th["ink"]}">{title}</text>'
            + text(WIDTH, 22, escape(caption), th, 12, "muted", anchor="end")
            + f'<text x="{WIDTH}" y="50" text-anchor="end" font-family="{FONT}" fill="{th["ink"]}">'
              f'{number}</text>')


def big(n, total=None, th=None):
    s = f'<tspan font-size="28" font-weight="600">{n}</tspan>'
    if total is not None:
        s += f'<tspan font-size="14" fill="{th["ink2"]}" dx="4">/ {total}</tspan>'
    return s


def hairline(th, y=74.5):
    return f'<line x1="0" y1="{y}" x2="{WIDTH}" y2="{y}" stroke="{th["border"]}"/>'


def footer_note(y, note, th):
    return (f'<line x1="0" y1="{y}" x2="{WIDTH}" y2="{y}" stroke="{th["border"]}"/>'
            + text(0, y + 26, escape(note), th, 11, "muted"))


# ---------------------------------------------------------------- Platforms


def platforms(repo, th):
    n = sum(len(t[2]) for t in TARGETS)
    s = [header(repo, "platforms", "Supported platforms", "targets", big(n), th), hairline(th)]
    y, chip_w, chip_h, step = 96, 120, 30, 132
    for name, note, isas in TARGETS:
        cy = y + chip_h / 2
        s.append(text(164, cy + 4.5, escape(name), th, 13, "ink2", anchor="end"))
        if note:
            s.append(text(164, cy + 20, escape(note), th, 11, "muted", anchor="end"))
        for isa in isas:
            x = LABEL + ISAS.index(isa) * step
            s.append(f'<rect x="{x + 0.5}" y="{y + 0.5}" width="{chip_w - 1}" height="{chip_h - 1}" '
                     f'rx="6" fill="{th["panel"]}" stroke="{th["border"]}"/>'
                     + text(x + chip_w / 2, cy + 4.5, escape(isa), th, 12, anchor="middle", font=MONO))
        y += 46
    s.append(footer_note(y + 6, "CI builds and tests every target on every push.", th))
    return svg(WIDTH, y + 40, "".join(s))


# ---------------------------------------------------------------- CI


def when(s):
    return datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ")


def span(a, b):
    s = max(0, int((when(b) - when(a)).total_seconds()))
    return f"{s // 60}m {s % 60:02d}s" if s >= 60 else f"{s}s"


def state(job):
    if job["status"] != "completed":
        return "running"
    return job["conclusion"] if job["conclusion"] in ("success", "failure") else "other"


def icon(x, y, st, th, r=8):
    if st == "running":
        return (f'<circle cx="{x}" cy="{y}" r="{r - 1}" fill="none" stroke="{th["muted"]}" '
                f'stroke-width="1.5" stroke-dasharray="3 2.5"/>')
    g = th["glyph"]
    if st == "success":
        glyph = (f'<path d="M{x - 3.6:.1f} {y + 0.2:.1f} L{x - 1:.1f} {y + 2.8:.1f} L{x + 3.8:.1f} '
                 f'{y - 2.6:.1f}" fill="none" stroke="{g}" stroke-width="2" stroke-linecap="round" '
                 f'stroke-linejoin="round"/>')
    elif st == "failure":
        glyph = (f'<path d="M{x - 3:.1f} {y - 3:.1f} L{x + 3:.1f} {y + 3:.1f} M{x + 3:.1f} {y - 3:.1f} '
                 f'L{x - 3:.1f} {y + 3:.1f}" stroke="{g}" stroke-width="2" stroke-linecap="round"/>')
    else:
        glyph = (f'<path d="M{x - 3.5:.1f} {y:.1f} L{x + 3.5:.1f} {y:.1f}" stroke="{g}" '
                 f'stroke-width="2" stroke-linecap="round"/>')
    return f'<circle cx="{x}" cy="{y}" r="{r}" fill="{th[st]}"/>{glyph}'


def needs_of(path=".github/workflows/ci.yml"):
    """{job ID: [needed job IDs]} from the workflow."""
    needs, cur, inside = {}, None, False
    for line in open(path, encoding="utf-8"):
        if line.startswith("jobs:"):
            inside = True
            continue
        if not inside:
            continue
        m = re.match(r"^  ([A-Za-z0-9_-]+):\s*$", line)
        if m:
            cur = m.group(1)
            needs[cur] = []
            continue
        m = re.match(r"^    needs:\s*(.+)$", line)
        if m and cur:
            needs[cur] = [n.strip() for n in m.group(1).strip("[] \n").split(",") if n.strip()]
    return needs


def merge(jobs, label, sub=""):
    """One row for some jobs: the worst state, the span from first start to last end."""
    states = [state(j) for j in jobs]
    st = ("failure" if "failure" in states else "running" if "running" in states
          else "success" if all(s == "success" for s in states) else "other")
    starts = [j["started_at"] for j in jobs if j["started_at"]]
    ends = [j["completed_at"] for j in jobs if j["completed_at"]]
    took = span(min(starts), max(ends)) if starts and ends and st != "running" else ""
    if len(jobs) > 1:
        sub = (sub + ", " if sub else "") + f"{len(jobs)} jobs"
    return {"state": st, "label": label, "sub": sub, "time": took}


def ci_rows(jobs):
    """(left cards, middle groups, right cards) of the panel."""
    needs = needs_of()
    by_id = {}
    for j in jobs:
        by_id.setdefault(j["name"].split(" (")[0], []).append(j)
    left, right, targets, others = [], [], {}, {}
    builds = [j for k, js in by_id.items() if k.startswith("build") for j in js]
    if builds:
        left.append(merge(builds, "Build", "all 7 targets" if len(builds) == 1 else ""))
    for key, js in by_id.items():
        if key.startswith("build"):
            continue
        if key == "results" or key.endswith("-results"):
            right.append(merge(js, LABELS.get(key, key)))
        elif key in OS_NAMES:
            for j in js:
                m = re.search(r"\b(x86_64|arm64|riscv64)\b", j["name"])
                targets.setdefault((key, m.group(1) if m else ""), []).append(j)
        elif not needs.get(key):
            left.append(merge(js, LABELS.get(key, key)))
        else:
            others.setdefault(GROUPS.get(key, "Other checks"), []).append((key, merge(js, LABELS.get(key, key))))
    rows = []
    order = {k: i for i, k in enumerate(OS_NAMES)}
    isa_order = {k: i for i, k in enumerate(ISA_NAMES)}
    trows = []
    for (os_, isa), js in sorted(targets.items(), key=lambda t: (order[t[0][0]], isa_order.get(t[0][1], 9))):
        qemu = "under QEMU" if any("qemu" in j["name"] for j in js) else ""
        trows.append(merge(js, f"{OS_NAMES[os_]} {ISA_NAMES.get(isa, isa)}".strip(), qemu))
    if trows:
        rows.append(("Tests on each target", trows))
    place = {k: i for i, k in enumerate(needs)}
    for title in ("Proofs", "Interop", "Devnets", "Other checks"):
        if title in others:
            rows.append((title, [r for _, r in sorted(others[title], key=lambda kr: place.get(kr[0], 99))]))
    right.sort(key=lambda r: r["label"] != "Results")
    return left, rows, right


def ci(repo, run, jobs, th):
    left, groups, right = ci_rows(jobs)
    counted = [j for j in jobs if j["name"] != "results"]
    passed = sum(1 for j in counted if state(j) == "success")
    states = [state(j) for j in counted]
    overall = ("failure" if "failure" in states else "running" if "running" in states
               else "success" if passed == len(counted) else "other")
    word = {"success": "passed", "failure": "failed", "running": "running"}.get(overall, "did not finish")
    color = th[overall] if overall != "running" else th["muted"]
    out = [header(repo, "ci.yml", f'Latest CI run <tspan fill="{color}">{word}</tspan>', "jobs passed",
                  big(passed, len(counted), th), th, title_x=28, extra=icon(10, 41, overall, th, r=10))]
    # The bar: one segment for each job, or the share of each state when there are many.
    if len(counted) <= 40:
        seg = WIDTH / max(1, len(counted))
        for i, j in enumerate(counted):
            st = state(j)
            fill = th[st] if st in ("success", "failure") else th["track"]
            out.append(f'<rect x="{i * seg:.1f}" y="70" width="{seg - 3:.1f}" height="8" rx="4" fill="{fill}"/>')
    else:
        out.append(f'<rect x="0" y="70" width="{WIDTH}" height="8" rx="4" fill="{th["track"]}"/>')
        x = 0.0
        for st in ("success", "failure"):
            n = states.count(st)
            if n:
                w = max(8.0, WIDTH * n / len(counted))
                out.append(f'<rect x="{x:.1f}" y="70" width="{w - (3 if x + w < WIDTH - 1 else 0):.1f}" '
                           f'height="8" rx="4" fill="{th[st]}"/>')
                x += w

    bx, bw, rh, gap = 262, 316, 26, 32
    y = 112
    centers = []
    for title, items in groups:
        out.append(text(bx, y + 4, escape(title.upper()), th, 11, "muted", weight="600",
                        extra=' letter-spacing="0.6"'))
        y += 14
        for r in items:
            cy = y + rh / 2
            centers.append(cy)
            out.append(f'<rect x="{bx}" y="{y}" width="{bw}" height="{rh}" rx="6" fill="{th["panel"]}" '
                       f'stroke="{th["border"]}"/>')
            out.append(icon(bx + 15, cy, r["state"], th, r=7))
            label = escape(r["label"])
            if r["sub"]:
                label += f'<tspan fill="{th["muted"]}" font-size="12" dx="6">{escape(r["sub"])}</tspan>'
            out.append(text(bx + 30, cy + 4.5, label, th, 13))
            out.append(text(bx + bw - 12, cy + 4, r["time"], th, 12, "ink2", anchor="end",
                            extra=' style="font-variant-numeric:tabular-nums"'))
            y += gap
        y += 10
    body_end = max(y, 112 + 80)
    if not centers:
        centers = [150]
    mid = (centers[0] + centers[-1]) / 2
    ch, cgap = 58, 12

    def cards(x, items):
        tops = []
        total = len(items) * ch + (len(items) - 1) * cgap
        top = mid - total / 2
        for r in items:
            out.append(f'<rect x="{x + 0.5}" y="{top + 0.5}" width="199" height="{ch - 1}" rx="8" '
                       f'fill="{th["panel"]}" stroke="{th["border"]}"/>')
            out.append(icon(x + 20, top + 22, r["state"], th, r=8))
            out.append(text(x + 36, top + 27, escape(r["label"]), th, 14, weight="600"))
            if r["time"]:
                out.append(text(x + 188, top + 27, r["time"], th, 12, "ink2", anchor="end",
                                extra=' style="font-variant-numeric:tabular-nums"'))
            if r["sub"]:
                out.append(text(x + 36, top + 45, escape(r["sub"]), th, 12, "ink2"))
            tops.append(top + ch / 2)
            top += ch + cgap
        return tops

    line = f'stroke="{th["border"]}" stroke-width="1.5" fill="none" stroke-linecap="round"'
    sx1, sx2 = 231, 609
    lc = cards(0, left)
    rc = cards(640, right)
    ys = centers + lc
    out.append(f'<path d="M{sx1} {min(ys)} V{max(ys)}" {line}/>')
    for cy in lc:
        out.append(f'<path d="M200 {cy} H{sx1}" {line}/>')
    if rc:
        ys2 = centers + rc
        out.append(f'<path d="M{sx2} {min(ys2)} V{max(ys2)}" {line}/>')
        for cy in rc:
            out.append(f'<path d="M{sx2} {cy} H640" {line}/>')
    for cy in centers if groups else []:
        out.append(f'<path d="M{sx1} {cy} H{bx} M{bx + bw} {cy} H{sx2}" {line}/>')
    body_end = max(body_end, mid + (len(left) * ch + (len(left) - 1) * cgap) / 2 + 12,
                   mid + (len(right) * ch + (len(right) - 1) * cgap) / 2 + 12)

    fy = body_end + 8
    out.append(f'<line x1="0" y1="{fy}" x2="{WIDTH}" y2="{fy}" stroke="{th["border"]}"/>')
    x = 0
    for st, label in (("success", "Passed"), ("failure", "Failed"), ("other", "Skipped or cancelled")):
        out.append(icon(x + 6, fy + 22, st, th, r=6))
        out.append(text(x + 18, fy + 26.5, label, th, 12, "ink2"))
        x += 18 + 7.2 * len(label) + 22
    ends = [j["completed_at"] for j in counted if j["completed_at"]]
    meta = (f'Run {run["id"]} on commit {run["head_sha"][:7]}, '
            f'{when(run["created_at"]).strftime("%-d %b %Y, %H:%M")} UTC')
    if ends and overall != "running":
        meta += f", {span(run['created_at'], max(ends))} in all"
    out.append(text(WIDTH, fy + 26.5, escape(meta), th, 12, "ink2", anchor="end"))
    out.append(text(0, fy + 52, "Generated by CI after each run. Select the panel to open the run.",
                    th, 11, "muted"))
    return svg(WIDTH, fy + 60, "".join(out)), f"Latest CI run {word}: {passed} of {len(counted)} jobs passed"


# ---------------------------------------------------------------- Docs


def doc_head(path):
    """The title of a doc and the summary line under it."""
    lines = open(path, encoding="utf-8").read().splitlines()
    if not lines or not lines[0].startswith("# "):
        sys.exit(f"{path}: no title on the first line")
    title = lines[0][2:].strip()
    summary = next((line.strip() for line in lines[1:] if line.strip()), "")
    if summary.startswith("#") or not summary:
        sys.exit(f"{path}: no summary line under the title (ARCHITECTURE.md section 11)")
    return title, summary.rstrip(".")


def card(th, title, says, tag=None):
    w, h = CARD_W - 10, CARD_H - 10
    s = [f'<rect x="0.5" y="0.5" width="{w - 1}" height="{h - 1}" rx="8" fill="{th["panel"]}" '
         f'stroke="{th["border"]}"/>',
         text(16, 24, escape(title), th, 14, weight="600"),
         text(16, 42, escape(says), th, 12, "ink2")]
    if tag:
        tw = 12 + 7 * len(tag)
        x = CARD_W - 26 - tw
        s.append(f'<rect x="{x}" y="17" width="{tw}" height="20" rx="10" fill="none" '
                 f'stroke="{th["border"]}"/>' + text(x + tw / 2, 31, escape(tag), th, 11, "ink2",
                                                     anchor="middle", font=MONO))
    else:
        x = CARD_W - 28
        s.append(f'<path d="M{x - 3} 21 L{x + 3} 27 L{x - 3} 33" fill="none" stroke="{th["muted"]}" '
                 f'stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round"/>')
    return svg(CARD_W, CARD_H, "".join(s))


def model_tag(name):
    for isa, tag in (("arm64", "ARM64"), ("x86-64", "x86-64"), ("riscv", "RISC-V")):
        if name.startswith(isa):
            return tag
    return "model"


def docs(repo, files):
    groups = []
    for kind, pattern, label in (("doc", "docs/reference/*.md", "Function docs"),
                                 ("model", "docs/models/*.md", "Lean models")):
        paths = sorted(glob.glob(pattern), key=lambda p: doc_head(p)[0].lower())
        if paths:
            groups.append((kind, label, [(p, *doc_head(p)) for p in paths]))
    total = sum(len(g[2]) for g in groups)
    for mode, th in THEMES.items():
        files[f"docs-header-{mode}.svg"] = svg(WIDTH, 84,
            header(repo, "docs", "Docs", "docs", big(total), th) + hairline(th))
        for kind, label, items in groups:
            count = f"{len(items)} {kind}{'' if len(items) == 1 else 's'}"
            files[f"docs-{kind}s-{mode}.svg"] = svg(WIDTH, 34,
                text(0, 22, escape(label.upper()), th, 11, "muted", weight="600",
                     extra=' letter-spacing="0.6"')
                + text(2 * CARD_W - 10, 22, escape(count), th, 12, "ink2", anchor="end"))
            for path, title, says in items:
                name = os.path.basename(path)[:-3]
                files[f"docs-{kind}-{name}-{mode}.svg"] = card(
                    th, title, says, model_tag(name) if kind == "model" else None)
        files[f"docs-footer-{mode}.svg"] = svg(WIDTH, 44, footer_note(2, "Select a card to open its doc.", th))
    parts = [picture("docs-header", f"{repo} docs")]
    for kind, label, items in groups:
        cards = [f'<a href="{p}">' + picture(f"docs-{kind}-{os.path.basename(p)[:-3]}", f"{t}: {s}") + "</a>"
                 for p, t, s in items]
        parts.append(picture(f"docs-{kind}s", label) + "<br>\n"
                     + "<br>\n".join("".join(cards[i:i + 2]) for i in range(0, len(cards), 2)))
    parts.append(picture("docs-footer", "Select a card to open its doc."))
    return "<br>\n".join(parts[:2]) + "\n\n" + "\n\n".join(parts[2:])


# ---------------------------------------------------------------- README


def framed(body):
    return f"<table><tr><td>\n\n{body}\n\n</td></tr></table>"


def replace(readme, key, body):
    start, end = MARKS[key]
    a, b = readme.find(start), readme.find(end)
    if a < 0 or b < a:
        sys.exit(f"README.md: no {key} panel markers")
    return readme[:a] + start + "\n" + body + "\n" + readme[b:]


def main():
    readme = open("README.md", encoding="utf-8").read()
    m = re.match(r"# (\S+)", readme)
    if not m:
        sys.exit("README.md: no title")
    repo = m.group(1)
    files = {}
    for mode, th in THEMES.items():
        files[f"platforms-{mode}.svg"] = platforms(repo, th)
    targets = "; ".join(f"{n}{' ' + note if note else ''}: {', '.join(i)}" for n, note, i in TARGETS)
    new = replace(readme, "platforms", framed(picture("platforms", f"Supported platforms. {targets}")))
    new = replace(new, "docs", framed(docs(repo, files)))
    keep = set()
    if len(sys.argv) == 3:
        run = json.load(open(sys.argv[1], encoding="utf-8"))
        jobs = [json.loads(line) for line in open(sys.argv[2], encoding="utf-8") if line.strip()]
        for mode, th in THEMES.items():
            files[f"ci-{mode}.svg"], alt = ci(repo, run, jobs, th)
        new = replace(new, "ci", framed(f'<a href="{run["html_url"]}">' + picture("ci", alt) + "</a>"))
    else:
        keep = {f"ci-{mode}.svg" for mode in THEMES}
    os.makedirs(OUT, exist_ok=True)
    for name, body in files.items():
        path = os.path.join(OUT, name)
        if not os.path.exists(path) or open(path, encoding="utf-8").read() != body:
            with open(path, "w", encoding="utf-8") as f:
                f.write(body)
    for path in glob.glob(os.path.join(OUT, "*.svg")):
        if os.path.basename(path) not in files and os.path.basename(path) not in keep:
            os.remove(path)
    if new != readme:
        with open("README.md", "w", encoding="utf-8") as f:
            f.write(new)
        print("updated README.md")


if __name__ == "__main__":
    main()
