#!/usr/bin/env bash
# scripts/render-sweep-cards.sh — renders the 4bpw sweep's scorecard SVG from
# docs/bpw4-sweep.tsv (one card per pack: hardmode, prefill, tg at three
# depths, tg c4 at d8192). The SVG is generated — never hand-edit it; edit the
# TSV and re-run. Usage: scripts/render-sweep-cards.sh [docs/bpw4-sweep.tsv]
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")/.."
TSV="${1:-docs/bpw4-sweep.tsv}"
OUT="${TSV%.tsv}-cards.svg"
python3 - "$TSV" "$OUT" <<'PYEOF'
import sys

tsv, out = sys.argv[1], sys.argv[2]
rows = []
for line in open(tsv, encoding="utf-8"):
    line = line.strip()
    if not line or line.startswith("#"):
        continue
    rows.append(line.split("|"))

COLS = ["hardmode", "pp_d0", "tg_d0", "tg_d4096", "tg_d8192", "tg_c4_d8192"]
best = {c: max(float(r[1 + i]) for r in rows) for i, c in enumerate(COLS)}

def color(score):
    s = float(score)
    return "#2e7d32" if s >= 94 else ("#1565c0" if s >= 93 else "#b26a00")

CARD_W, CARD_H, GAP, PAD = 285, 240, 18, 16
W = PAD * 2 + CARD_W * len(rows) + GAP * (len(rows) - 1)
H = CARD_H + 110
parts = [
    f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" '
    f'viewBox="0 0 {W} {H}" font-family="DejaVu Sans, sans-serif">',
    '<rect width="100%" height="100%" fill="#fafafa"/>',
    '<text x="16" y="28" font-size="17" font-weight="bold" fill="#212121">'
    'GLM-5.3-Flash 4bpw sweep — v1.2.3 + the 4-patch stack, paged KV + KV_SHARE=8, dense4fp8, 512K×4, vision</text>',
    '<text x="16" y="48" font-size="12" fill="#616161">'
    'hardmode = the 104-scenario battery (bench v3.0.1) · pp = llama-benchy pp2048 @ d0 tok/s · '
    'tg = solo tg128 tok/s at depth · c4 = 4 streams at d8192</text>',
    '<text x="16" y="66" font-size="11" fill="#9e9e9e">'
    'the re-sweep (2026-11-06, the (user) ask): every pack on the SHIPPING stack — these cards are the CURRENT ranking; the served TR3 pack\'s standing receipts: hardmode 95 three times, byte-identical token profiles.'
    ' The round-132 v1.2.1 sweep (94/93/94/90) is history: docs/LAUNCH.md</text>',
]
x = PAD
for r in rows:
    pack, hm, pp, tg0, tg4k, tg8k, tgc4, note = r
    c = color(hm)
    parts.append(f'<g><rect x="{x}" y="86" width="{CARD_W}" height="{CARD_H}" rx="10" fill="#ffffff" stroke="#e0e0e0"/>')
    parts.append(f'<rect x="{x}" y="86" width="{CARD_W}" height="6" rx="3" fill="{c}"/>')
    parts.append(f'<text x="{x+14}" y="116" font-size="14" font-weight="bold" fill="#212121">{pack}</text>')
    parts.append(f'<text x="{x+14}" y="156" font-size="34" font-weight="bold" fill="{c}">{hm}</text>')
    parts.append(f'<text x="{x+86}" y="156" font-size="12" fill="#757575">/104 hardmode</text>')
    metric = [
        ("prefill pp2048 @ d0", pp, best["pp_d0"]),
        ("tg128 solo @ d0", tg0, best["tg_d0"]),
        ("tg128 solo @ d4096", tg4k, best["tg_d4096"]),
        ("tg128 solo @ d8192", tg8k, best["tg_d8192"]),
        ("tg128 c4 @ d8192", tgc4, best["tg_c4_d8192"]),
    ]
    y = 180
    for label, val, b in metric:
        star = ' <tspan fill="#2e7d32" font-weight="bold">★</tspan>' if float(val) == b else ""
        parts.append(f'<text x="{x+14}" y="{y}" font-size="11.5" fill="#424242">{label}</text>')
        parts.append(f'<text x="{x+CARD_W-14}" y="{y}" font-size="11.5" text-anchor="end" fill="#212121">{val}{star}</text>')
        y += 21
    parts.append(f'<text x="{x+14}" y="{y-4}" font-size="10" font-style="italic" fill="#9e9e9e">{note}</text>')
    parts.append('</g>')
    x += CARD_W + GAP
parts.append(f'<text x="16" y="{H-14}" font-size="11" fill="#616161">★ = the sweep\'s best value in its column · '
             'production\'s hardmode on this bench version is owed (a solo prodqual window) · receipts: results/bpw4sweep/ on the head</text>')
parts.append("</svg>")
open(out, "w", encoding="utf-8").write("\n".join(parts))
print(f"[render-sweep-cards] wrote {out} ({len(rows)} cards)")
PYEOF
