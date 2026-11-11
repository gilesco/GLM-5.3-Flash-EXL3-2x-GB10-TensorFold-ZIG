#!/usr/bin/env bash
# scripts/render-launch-index.sh — generates docs/LAUNCH_INDEX.md: one line per
# round entry across the split log — the current week in docs/LAUNCH.md plus the
# archived weeks in docs/log/2026-WNN.md (the chart precedent: generated, never
# hand-edited). Each line: round tag | file | title | campaign IDs found in the
# body | VERDICT/VOID/INVALID when the body or title carries one. The index is
# navigation ONLY — the log remains the record; LAUNCH.md stays append-only and
# the weekly archives are immutable once cut.
set -uo pipefail
cd "$(dirname "$0")/.."
OUT=${OUT:-docs/LAUNCH_INDEX.md}   # OUT=... for a check-elsewhere render (the guard diffs a temp copy)
python3 - "$OUT" docs/log/2026-W*.md docs/LAUNCH.md <<'PYI'
import re, sys, os
out_path = sys.argv[1]
out = ["# Launch log index — generated; do not edit",
       "",
       "<!-- scripts/render-launch-index.sh generates this from docs/LAUNCH.md",
       "     and the archived weeks in docs/log/. -->",
       "<!-- The logs are the record; this is navigation. -->",
       "",
       "| Round entry | File | Campaign IDs | Outcome tags |",
       "|---|---|---|---|"]
total = 0
for src_path in sys.argv[2:]:
    rel = os.path.relpath(src_path, ".")  # repo-root-relative: the render is path-independent (the guard diffs a temp copy)
    lines = open(src_path, encoding="utf-8").read().splitlines()
    entries = []
    cur = None
    for i, line in enumerate(lines):
        if line.startswith("## "):
            if cur:
                cur["end"] = i
                entries.append(cur)
            cur = {"start": i, "title": line[3:].strip(), "body": []}
        elif cur:
            cur["body"].append(line)
    if cur:
        cur["end"] = len(lines)
        entries.append(cur)
    for e in entries:
        body = "\n".join(e["body"])
        title = e["title"]
        # only round-shaped entries: "(round N ...)" or the legacy "YYYY-MM-DD (round N)"
        if not (re.match(r"\(round\s+\d+", title) or re.match(r"\d{4}-\d{2}-\d{2}\s*\(\s*round\s+\d+", title)):
            continue
        campaigns = sorted(set(re.findall(r"campaign-\d{8}-\d{6}", body)))
        tags = []
        # VOID/INVALID: title match is authoritative; body match requires a
        # verdict context. The log's phrasings: "voided", "VOID", "void as
        # evidence", "is void", "voided windows" (the audit: 9 of 10 body-only).
        # Exclude the avoid/devoid family.
        if re.search(r"\bVOID\b", title):
            tags.append("VOID")
        elif re.search(r"\bvoid(?:ed)?\b", body, re.I) and not re.search(r"avoid|devoid", body, re.I):
            tags.append("void (body)")
        if re.search(r"\bINVALID\b", title):
            tags.append("INVALID")
        elif re.search(r"(A/B|arm|battery|comparison|attempt|run)\s+(was\s+)?INVALID\b|recorded\s+[^.]*\bINVALID\b|INVALID\s*[—-]", body):
            tags.append("invalid (body)")
        # qualified: uppercase only in bodies (a lowercase "qualifies" in prose
        # is a mention, not a verdict)
        if re.search(r"\bQUALIFIED\b|\bQUALIFIES\b", title) or re.search(r"\bQUALIFIED\b|\bQUALIFIES\b", body):
            tags.append("qualified")
        m = re.match(r"\(round\s+(\d+)(?:,\s*cont\.\s*(\d+))?\)", title)
        if m:
            tag = f"round {m.group(1)}" + (f" cont. {m.group(2)}" if m.group(2) else "")
        else:
            m2 = re.match(r"\d{4}-\d{2}-\d{2}\s*\(\s*round\s+(\d+)\s*\)", title)
            tag = f"round {m2.group(1)}" if m2 else title[:40]
        label = title if len(title) <= 110 else title[:107] + "…"
        out.append(f"| [{tag}] {label} | {rel} | {', '.join(campaigns) if campaigns else '—'} | {', '.join(tags) if tags else '—'} |")
        total += 1
open(out_path, "w", encoding="utf-8").write("\n".join(out) + "\n")
print(f"wrote {out_path}: {total} round entries across {len(sys.argv) - 2} log files")
PYI
