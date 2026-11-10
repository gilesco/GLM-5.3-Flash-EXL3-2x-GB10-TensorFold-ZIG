#!/usr/bin/env bash
# scripts/render-launch-index.sh — generates docs/LAUNCH_INDEX.md: one line per
# round entry in docs/LAUNCH.md (the chart precedent: generated, never
# hand-edited). Each line: round tag | title | campaign IDs found in the body
# | VERDICT/VOID/INVALID when the body or title carries one. The index is
# navigation ONLY — the log remains the record; LAUNCH.md stays append-only.
set -uo pipefail
cd "$(dirname "$0")/.."
OUT=docs/LAUNCH_INDEX.md
python3 - docs/LAUNCH.md "$OUT" <<'PYI'
import re, sys
src_path, out_path = sys.argv[1], sys.argv[2]
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
out = ["# LAUNCH.md index — generated; do not edit",
       "",
       "<!-- scripts/render-launch-index.sh generates this from docs/LAUNCH.md. -->",
       "<!-- The log (docs/LAUNCH.md) is the record; this is navigation. -->",
       "",
       "| Round entry | Campaign IDs | Outcome tags |",
       "|---|---|---|"]
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
    out.append(f"| [{tag}] {label} | {', '.join(campaigns) if campaigns else '—'} | {', '.join(tags) if tags else '—'} |")
open(out_path, "w", encoding="utf-8").write("\n".join(out) + "\n")
n = sum(1 for l in out if l.startswith("| ["))
print(f"wrote {out_path}: {n} round entries ({len(entries) - n} structural headers skipped)")
PYI
