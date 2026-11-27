# STAGE BRIEF — the v1.3.6 bump window (VOIDED 2026-11-27 — the battery
# caught the composed stack serving degenerate output; the store rolled
# back to the v1.3.5-proven bodies; see docs/LAUNCH.md round 163. The
# re-evaluation re-stages from the v134val block after the bisect names
# the defect.)

## The trigger — fired: TensorFold v1.3.6 (f56b1420f), one day after v1.3.5

## What v1.3.6 actually carries (read from the changelog + the tree,
## not the poke's template text)

1. **`TF_GLM_KEEP_SEQS=1`** — a released stream's sequence stays on its
   slot: the next request starts with no allocation, fill or free
   (#5122's test receipt upstream). The slot-reuse lever; default OFF.
   Value question: the steady-state decode row (the anchors' 77.3) and
   the resume/warm path. Candidate arm AFTER the bump qualifies.
2. **The mHC pre-side kernels from `common/`** (`tf_glm_hc_partial`,
   `tf_glm_hc_partial8`, `tf_glm_hc_finish`, `tf_glm_hc_finish_f32w`)
   — refactored bodies of the kernels our ncu census measured at
   p50 104-115µs. Perf-shape unknown; no knob. Rides the bump.
3. **The mla 256-wide v-heads + sink-merge kernels**
   (`tf_mla_expand_v_256`, `tf_mla_merge`) — attention-side kernels,
   EXL3-neutral on our shape. Rides the bump.
4. **`cuda_engine.zig` split to `cuda_engine_shares`** — the engine
   refactor; the file our 001/003 hand-merges live in got reshuffled
   (this is the compose's collision surface, the hand-merge work).
5. **Input checks: GLM on CUDA refuses token IDs outside its embedding
   on every path** — validation hardening, no perf claim.
6. **The fingerprint layout moves 23 → 24** (keep_seqs) — every rank
   must carry the same build; both ranks rebuild in the window.

NOT carried (the poke's template text was stale — desk-killed):
#2843's EXL3 decode-grid fix, #2856's batched MTP, #3064 — none appear
in v1.3.6's changelog (grep count 0). The fp8-pages marriage holds:
the Fp8OnPages refusal is intact in v1.3.6's tree (3 sites).

## The value-if-yes

- The bump keeps the line current (the eleventh bump's value: upstream
  correctness + the kernels) with the marriage intact and the witness
  unmoved — the value is the release itself plus the keep_seqs /
  mHC / mla-256 candidates now AVAILABLE on the qualified base.
- The keep-seqs candidate arm (the release's own lever) rides AFTER
  the bump qualifies — its own window, its own value read: the
  steady-state decode row and the resume path.

## The window shape (the bump protocol, the two-gate staging rule)

1. The tag's commit lands in `scripts/local.sh` TF_COMMIT (gate 2)
   while the store regenerates onto the release (gate 1) — the
   tensorfold-patch-craft discipline: the composed tree, the
   byte-exact round-trip (PROVEN: compose-v136 tree == pristine
   v1.3.6 + the store, zero diffs), the compile gate on the head.
2. The bumpval battery (the standing one) qualifies: the witness
   `80cc3802…` IDENTICAL across the bump, the §2 gates, hardmode on
   the 3.1.0 frame, the vision suite, the walls, the value bracket.
3. No candidate arms ride THIS window (the release's own lever,
   keep_seqs, is default-off and takes its own window after — the
   fewest-questions-per-window rule; the v1.3.5-carried wide-tile and
   DFlash2-graph arms keep their queue places).

## THE QUEUE'S DESK-KILLS (the round-165 close)

- **The wide-tile arm DESK-KILLED** (the round-165 close): the
  `TF_GLM_WIDE_EXPERT_TILE` knob routes the factored down-projection
  through `runFact` behind `l.format == .nvfp4` — AND `plan.fact`
  itself is the NVFP4 factored-tile plan. The fork's EXL3 layers
  branch at `runGrouped`/`run`/`runDirect` in cuda_moe.zig and never
  touch `experts.run`'s fact path: the lever is NVFP4-route-scoped by
  construction and CANNOT engage on the EXL3 line. The same class as
  the #4493/#4619 pair-experts finding (round 160). No window spent.
- **The DFlash2-graphs arm stays DESK-KILLED** (the round-162 read,
  reaffirmed): `TF_DFLASH_GRAPH`/`TF_DFLASH_QL_SPAN` live in the
  qwen3_5 family only — GLM never wired them.
- **The keep-seqs arm CLOSED WITHOUT ADOPTION** (the round-165
  bracket: the witness reproduced on both fresh-serve arms, the value
  cells moved nothing — the ledger carries the closure).
4. Promotion per the round-157/159 shape: the pin moves, production
   serves, the state docs same-sitting.

## The kill criteria

- ANY gate FAIL holds the pin at v1.3.5 until understood (the
  standing bump rule; the one-day cadence makes holding cheap).
- The composed tree refuses to compile on the head's build → the
  bump holds until the member is fixed (the compile gate is the
  pre-window witness; a compile failure voids a ~25-min window).
- The keep-seqs arm is NOT in this window; a keep-seqs failure
  cannot hold the bump.

## The prior instruments

- The bump protocol: the v135val battery (campaign-20261125-081420),
  the eleventh bump — the witness discipline and the value bracket.
- The window shape: the v134val staging commit (cf5406dc) — the
  v136val phase extracts from there, reheadered to v1.3.6.

## The desk check before the launch (all four must be green)

- The two staging gates: the store regen (DONE — the byte-exact
  round-trip) AND `scripts/local.sh` TF_COMMIT → f56b1420f.
- The compile gate on the head (the docker build's compile stage)
  BEFORE the window: a failed compile is a voided window.
- DRY_RUN green before the real launch; the continuation scanner on
  any new phase code; the launch is the last action of the sitting.
