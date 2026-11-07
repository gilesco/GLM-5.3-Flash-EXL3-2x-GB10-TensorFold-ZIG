# Performance plan: closing the measured fronts

> **The bar (user, 2026-10-23):** surpass production 0.6.6 on model loading time,
> generation tok/s, and prefill rate. This document is the continuing-look home for
> that hunt: the measured scoreboard, the fronts in attack order, every lever with its
> mechanism and verification plan, and the research log. The mandate (user): look hard,
> keep looking, go outside the scope if necessary — everything documented.

## The status (round 123, 2026-10-30 — the consolidation)

> **UPDATED round 133 (2026-11-05, the ABSORB_MMA adoption — the Mia fold-in
> arc closed)**: the chunk pair REJECTED (the warm-front granularity cost),
> the cost tables DROPPED (the c2 attribution), **ABSORB_MMA ADOPTED** —
> the deep fills −6.8/−7.0/−6.9% (0.727-0.738 ms/tok), the small prompts
> −5-6%, hardmode **95** on the shipping config, and the duel re-paired:
> solo **110%**, cold **334%**, c2 ~99% of production's top-of-range volley,
> c4 98%, ITL ~107% crossed, the 8k slope 0.657 → **0.602 ms/tok**. The
> decode fronts' structural pieces (the batched-launch pattern, the
> concurrent resume's 4× serialization) remain upstream-gated/parked; the
> warm front stays 70%; the loading wall is flat (103 s). Receipts:
> campaigns 20261104-213422 → 20261105-003101.

Every named lever is now **adopted, measured out, parked with a price, or
upstream-gated**:

- **Quality (Front 1)**: UPDATED round 132 — the 4bpw sweep moved the ceiling:
  **TR3-4bpw 94/104** (the served default, the (user) swap) ties the MIA pack
  and ties **production's current-bench anchor: 94/104** (the prodbench receipt,
  cont. 22 — production FOR TESTING on the clean 8001, the same bench_cell
  instrument; campaign-20261102-213954) — the quality bar is met AT the number. The
  checkpoint-lever idea this bullet gestured at is now DONE — the sweep ran it
  (docs/bpw4-sweep-cards.svg); the 3bpw track CLOSED round 132: the engine gates it — the CUDA family reads
  4-bit EXL3 experts (all three community packs refused, UnsupportedQuant; the
  androidli pack is TensorFold-native mcg and still gated — it served on the
  python-era 0.6.0 only). Sub-4bpw on this line waits on upstream (the CUDA
  family's reader), not on quantizers.
- **Concurrency (Front 2)**: fully decomposed (rounds 114-123). UPDATED
  round 133 (cont. 71): the v1.2.3 arc closed with the receipt set fully
  symmetric on the new ref (pagedgatesv123: §2 ALL PASS fp8-paged; depth
  12/12; hardmode 95 + the vision 4/4; the perf parity). The KV_SHARE A/B ran
  (campaigns 20261106-090311/-next): the knob is PARITY on the solo warm
  resume (the page store's per-resume cost is not faster than the host
  store's — the medium is not the cost) and the concurrent 4-prefix
  resume MISSES in both stores (cached=0 ×8; the host store's cascade
  eviction exposed: 4 × 182 MiB > 679 MiB, each warm miss re-keeps and
  evicts the next). The gap localizes to store capacity/eviction, not
  the resume medium — and kvshare2 (campaign-20261106-092703)
  CONFIRMED it: N=8 held all four states through the live streams
  (16 pool pages, zero eviction), the concurrent 4-prefix volley hit
  4/4 at a flat 1.84 s/request (the aggregate 7.41 s vs the host
  store's 12.29 s — −40%; the round-123 serialization is the queue,
  the per-resume cost does not inflate). The knob advances to the
  gates + the battery (kvsharequal, campaign-20261106-093921: §2 ALL
  PASS — g3 receipts the pool-page resume path — hardmode 95 + the
  vision 4/4, total_tokens 662,693 byte-identical) — **ADOPTED
  (cont. 74): config.sh exports TF_GLM_KV_SHARE=8**. The concurrent-
  resume gap SPLITS: the store half is SOLVED (the page store holds the
  states; the aggregate −40%), the queue half remains (the resumes
  serialize behind the admission — upstream-shaped, the batched-launch/
  pair-seam class). The cross-restart resume stays COLD (the store is
  device memory; it does not survive a restart). The PDL-on-the-finish route
  was surveyed and priced: OUR tree has no PDL plumbing (the plan's
  earlier ".pdl flag" reference was the fork's field), so it is a
  from-scratch build with a modest expected win (round 116: the hc
  chain's launch gaps are already queue-hidden). CORRECTED (cont. 75):
  the fork's 0010 is a 7-line correctness patch (the side-stream
  drain), NOT the perf lever — our tree has no side-stream code (no
  anchor); the fork's prefill-class lever is the 0009 (packed prompt
  matmuls in two stages) + 0033 (the f_b+g_b pair launch) line. The
  fork's repo is cloned at /tmp/mia-fork (active, patch 0108); the
  next sitting's opener is the design pass: locate the actual prefill
  claim in its README/RESULTS, map 0009+0033 onto our v1.2.3 tree,
  write the candidate design before any window. The hc fusion:
  built, bit-safe, NOT adopted (the occupancy trade — round 116). The depth census:
  the attention path is ~1% of the decode token cost (round 122) — no depth
  pathology. The cache churn: no evictions at probe scale, but the concurrent
  resume SERIALIZES 4× (round 123). The remaining decode gap is the uniform
  per-token machinery — **upstream-gated** (the batched-launch pattern reaching
  GLM, the pair-seam CUDA steps — v1.2.1 LANDED (round 132: the GLM knobs #1823/#1760 are upstream, the #1868 page-cache fix, /v1/load; the re-qualification + the duel re-paired the decode fronts; the knobs A/B'd: #1760 VH rejected, #1823 CS held (user) — and #1732's KV_SHARE+pages pair is the next A/B, the warm-resume mechanism) — the watch continues each sitting).
  **Re-attributed (round 131, the azqual receipt)**: a large share of the
  decode gap is ROUTING DEPTH, not machinery — the AZ-EXL3 serve
  (num_experts_per_tok=4 vs the Focus's 8, quantization identical) decodes
  80.1 t/s solo / 128.2 c2 / **199.4 c4 — above production's c4** — at
  hardmode 90 vs the Focus's 93. The trade is priced (3 hardmode points for
  +46% solo / +44% c2 / +38% c4) and declined per the quality bar (user,
  2026-10-27); the served config stays Focus top-8.
- **The TTFT-at-depth frontier**: the restore is at parity solo (~0.15 s); the gap
  is the forced 2048-aligned tail (the comptime chunk granularity — a 512-row grid
  buys the resume but costs the prefill anchor 28%: parked per the bar); the
  concurrent resume serializes 4× (24× behind production under concurrency) — both
  parked with prices (round 119/123).
- **THE COLD DEPTH COST DECOMPOSED (round 131, the ncudepth census — four
  attempts; the receipts in campaign-20261101-*)**: the cold d8192 prefill's
  5.4 s wall is **~65% host gaps** — ~14% tf_exl3 prompt GEMMs (prompt_gu +
  prompt_down), ~11% tf_glm glue + the fp8 state writes (chunks_32_fp8 p50
  11.2 ms at depth), ~6-11% TP collectives (link-bounded, not ncu-capturable
  per-rank — a collective profiled on rank 0 only deadlocks the pair). The
  slope is bubble-dominated, not kernel-dominated: the lever is engine-side
  host span work per chunk (the round-34 KDA/state span candidate), or
  graph-captured prompt passes. It also explains the p4096 rejection: bigger
  chunks extend, not shrink, the per-chunk host span. **And the frontier's
  final shape (the prodcold receipt)**: production's cold slope is 2.026
  ms/tok (17.1 s at d8192, SLOWING with depth — not the 0.266 the round-130
  duel read, which was its persistent-cache-warm number); ours is 0.656 flat
  — the cold front CROSSES (309%). Production's real edge was the WARM full-
  hit skip — RE-MEASURED cont. 25 on v1.2.1 (the same instrument definition,
  the same-session immediate repeat at max_tokens=1, d8.4k): ours 0.302 s vs
  production's 0.21 s — 70%, from the v1.2.0-era 1.42 s (the #1868 page-cache
  fix the likely mover; both receipts cited in the anchors row). The open
  pieces: the cross-restart resume path and the concurrent resume's 4×
  serialization. The #1732 pages mechanism (the named upstream pattern for a
  full-hit skip) requires bf16/auto KV — the fp8×pages pair is a designed
  non-combination on mainline (the engine's admission line, the 233025
  receipt); the bf16 arm SERVED (the 000653 receipt: +3.5 GiB headroom, the
  on-demand pool) and the verdict is NO ADOPTION — the warm same-session TTFT
  is a wash vs the standing cache and bf16 KV costs solo decode ~5-10%. The
  standing fp8 config stays; the front's open pieces are unchanged.
- **The standing strengths**: the concurrent deep prefill WINS 1.53× (2,799 vs
  1,834 t/s); the decode ITL crosses (102%); TTFT overhead 92%.
- **LOADING: RE-DATED (cont. 31) — 90% on the served default (104.5 vs 93.7 s; the TR3 pack's load pays ~+9 s over the Focus cell's 95 s v1.2.0 receipt — the mover unattributed). The front was TAKEN at 98.6% on round 127 (the Focus cell, v1.2.0 + the tail release).** The
  pin bumped to v1.2.0 (user) for the upstream loading cluster (#1616/#1636: the
  16-reader load-ahead + the 8-thread expert pack; 268 → 46 s at TP=3 upstream) —
  the first bumped boot refused at admission 0.12 GiB short (the read-ahead's
  un-released tail: embed/norm/head/MTP, campaign-004214); glm-tail-release.patch
  releases the tail files' pages and the qualification passed at **93.0 s engine /
  95 s wall vs production's 93.7 s**, the gate sha identical, the probes equal
  (campaign-20261031-142431). The line's own v1.1.9 loading patches (pinned-upload
  −21.8 s, trellis-scratch −6.2 s, both bit-safe) are superseded by the bump and
  retired to the record. The residual decomposition that found the lever: the
  marks (the 45-layer loop 79%, the pack 12%), the disk exonerated (7 GB/s
  O_DIRECT), the release cost refuted (1-10 ms), the per-tensor marks (reads 7.3 s,
  uploads 29 s — the loop's interior), the fault rate measured (~840 MiB/s).

## The scoreboard

The current scoreboard lives in [DELTAS.md](DELTAS.md) (the comparison's
home) and [perf-anchors.tsv](perf-anchors.tsv) (the chart's definitive pairs);
this file keeps the fronts' analysis, not a second copy of the numbers. The round-108-era
protocol (one hardmode+perf single run per serve, same day, same protocol) produced the
definitive pairs the anchors carry; the round-129 same-day refresh (2026-10-31) re-ran
both engines on the testing port. Historical table below for the round-23 duel's shape:

<details><summary>the round-23 duel's original table (history)</summary>

| front | production | ours | ours as % | instrument |
| --- | --- | --- | --- | --- |
| solo decode | 58.7 t/s | 55.2 t/s | 94% | 2048-token greedy ×2, Δ 0.6% |
| c2 aggregate | 87.1 t/s | 72.1 t/s | 83% | 2×2048-token concurrent |
| **c4 aggregate** | **154.5 t/s** | **99.8 t/s** | **65%** | 4×2048-token concurrent |
| request overhead | 183 ms | 200 ms | 92% | TTFT at max_tokens=1, solo |
| prefill slope | 0.265 ms/tok | 0.662 ms/tok | 40% | TTFT deltas at d0/d4096/d8192 |
| streaming pace | 17.0 ms/tok | 17.0 ms/tok | 100% | per-token ITL (ours arrives in 3.4-token bursts) |

</details>
| loading (restart wall) | 93.7 s | 104.5 s | 90% | RE-DATED cont. 31 for the served default (TR3 on v1.2.1: 103/106 s, campaign-20261103-090007); the 95 s / 98.6% row was the Focus-cell v1.2.0 receipt (campaign-20261031-142431) |

Retired claims: the "concurrency cliff" (bench artifact, round 6), the "2-second fixed
overhead" (was concurrency queueing), the bench's shallow-depth concurrent rows as an
instrument (they swing up to 2× run to run — campaign-20261023-221204's confirm receipt;
single-run A/Bs on them are void as evidence; the duel's probes and the d8192 rows are
the stable instruments).

## Front 1: concurrency scaling (65% at c4) — the biggest gap

Production retains 66% of per-stream speed at 4× concurrency (154.5/4 = 38.6 vs solo
58.7); we retain 45% (99.8/4 = 24.95 vs 55.2). Our GPU is saturated with useful work
(wall ≈ gpu in every prof line), so this is about *how the work is batched*, not about
waiting.

- **Lever A — ANSWERED (2026-10-24, campaign-20261024-000708)**: our verify rounds
  **do batch across streams** — at c4 the shared windows run 8 rows (4 streams × ~2 draft
  rows) in one 76.5 ms round, while a solo stream's window is 2 rows/41 ms. Batching is
  NOT the missing piece; a #1155-style glm port is the wrong patch for this gap.
- **Lever B — ANSWERED, retired (same receipt)**: `TF_GLM_SHARED=0` (windows alone) at
  c4 = **51.6 t/s** vs sharing's 70–105 in the same sitting (and 4×52 ms per-stream rounds
  of unshared GPU work). Sharing IS our concurrency-scaling mechanism — the knob stays at
  its default.
- **What remains of Front 1**: with batching present and sharing load-bearing, the c4 gap
  (ours ~100 vs production 154.5, the clean duel receipt) lives in the *round economics*.
  **Acceptance is ANSWERED (2026-10-24, 115242/11-routerks2.md + production's /health):
  NOT our gap** — our drafter accepts **77.2%** (15660/20292 via our /metrics
  `tensorfold:mtp_drafted/accepted_total`) against production's 62.7% (1610/2569). The
  remaining question is the **shared-round cost scaling at c4**: our 8-row shared round
  costs 76.5 ms (vs 40 ms solo at 2 rows — the routed experts' marginal ~5.5 ms/row at
  topk=8), production's rhythm implies ~34 ms rounds at c4 against ~22 ms solo. Levers:
  the routed-expert kernel's marginal per-row cost (topk=4 via the AZ route cuts it in
  half — the top4 experiment), the cost tables that size shared windows
  (`cuda_lanes.zig`: alone 52.0 base + 6.8/row vs shared 76.0 + 4.1/row), and whether the
  draft block pass (1.6 ms, batched across streams) serializes against verify rounds
  instead of overlapping them.
- **Methodology caveat (recorded with the receipt)**: this window's absolute numbers are
  polluted by the agent's own inference — the session is served by the engine under test,
  and the agent was generating during cell a's probes (solo 14.2/34.1 t/s, Δ58%, is the
  agent's traffic, not engine behavior). The duel receipt (campaign-20261023-221204)
  remains the clean baseline; probe windows now run with the agent silent.

## Front 2: prefill slope (40%) — the MoE prompt path

Prompt chunks are 90% router+routed (a 2,048-row chunk: router 910 + routed 793 of
1,892 gpu ms). Three levers, the first one new tonight:

- **Lever A2 STATUS (round 85, 2026-10-29): the GEMM replacement RAN bit-safe and moved NOTHING — the staging hypothesis is dead.** The scoped fix was implemented in full
  (patches/glm-router-gemm.patch on v1.1.9: the tf_glm_router_mm chain kernel with glm_mm's complete prompt shape — 128-row blocks, ROWS_FIRST L2 sharing, 3-stage cp.async, PDL —
  and ONE continuous mma chain per output, bit-identical by construction; compile RC=0). The window (campaign-20261029-152500/30-routergemm.md): **content gate IDENTICAL**
  (the bit-safety design proof holds), hardmode 93 / TC-92 pass — and the router section **1109 (stock) vs 1114 ms (chain)** per 2048-row chunk: ZERO movement, slope 0.659 vs 0.660.
  Three kernel probes now agree the section is implementation-independent (ks 8→2, part-forced, fully-staged GEMM). The m=64 chunk's router (54.9 ms, vs 1/32 of the 2048-row cost)
  shows a large non-FLOP component. **Next instrument: a kernel profiler capture** (ncu on one chunk's router kernels: duration, SM busy, stall reasons) — the pathology is
  either in the measurement (prof-span semantics, host-enqueue bubbles) or systemic (clocks, stream serialization), not in kernel shape. The patch is NOT adopted (no measured
  win; rebase-tax rule); kept as the bit-safe probe artifact. The v1.1.9 pin STAYS (bit-exact upstream, the fold-in verdict).
- **Lever A2 — the prompt-router pathology (ks hypothesis REJECTED 2026-10-24,
  campaign-20261024-115242/11-routerks2.md)**: the A/B ran clean (the agent silent —
  the stock cell reproduces the duel exactly: solo 55.3/55.1 Δ0.3%, c4 101.8, slope
  0.659). The `router_ks 8 → 2` patch **did not move the router section** (1096 → 1090
  ms of the chunk) and the **content gate flipped a token** — the patch died (#1079
  protocol). The +16% decode in the patched cell was an acceptance lottery on the
  bit change, not a mechanism. **The pathology remains open with the pipeline-depth
  hypothesis eliminated as the pathology's cause**: next candidates are (a) a 10-minute microbench of
  `router_tile` vs `router_part` at m=2048 (**DONE 2026-10-24, campaign-20261024-125609:
  the forced fallback costs the same — router 1140 vs 1096 ms — and the content gate says
  IDENTICAL: both kernels share the pathology; the hand-rolled mma approach itself is the
  bottleneck**), (b) **the GEMM replacement (the scoped fix)**, (c) the
  w-matrix layout/packing as the latency source. The prize stands: chunk 1641 → ~600 ms
  would put prefill at production parity with zero quality risk.
  **The GEMM replacement's design (scoped from `families/glm/cuda_mm.zig`, 175 lines)**:
  glm_mm is the engine's bf16/tensor-core linear machinery — "weights tiled once at load,
  any row count, **row-stable K slices**" (the row-stability is the bit-property that
  matters). The replacement: skip the `.router_pack` fix (keep the raw bf16 gate
  [288][4096]), call glm_mm **once per K-slice (ks=8 slices, x-sliced [m][512] ×
  w-sliced [288][512])**, then the existing `sliceSum` adds the 8 partials in order —
  preserving the current kernel's exact summation structure so the cross-build content
  gate (the repo's patch bar: "replies unchanged", the #1079 precedent) can pass.
  glm_mm's tile16 takes bf16 [n][k] directly; its split_target=192 launch shaping is the
  performance win (column tiles × slices aimed at the GB10's SMs, prompt blocks sharing
  weight tiles in L2). Files: `weights.zig` (keep the raw gate ref), `cuda_glue.zig`
  (the router() body), possibly `cuda_mm.zig` (an exported row-count-generic entry).
  Wiring ~30–50 lines; verify with the content gate + the chunk prof + the §2 gates.
- **Lever A — the AZ checkpoint (community, 2026-10-23) — (user) APPROVED, with a heavier
  quality battery**: `azampatti/GLM-5.3-Flash-AZ` routes top-4 of the original top-8
  (18B → ~12.5B active) with the shared experts *retrained* to keep the selection faithful
  ("95% exact same answer"), and ajvazan's quality-degradation test passed everything but
  one 8k-context case. On their Python stack: ~2,300 tok/s cold prefill, 50 tok/s decode
  to 150k. For us the routed path halved should cut a prompt chunk's routed share
  (~793 → ~400 ms) and verify's (~18.5 → ~9 ms): expected **~+25% prefill, ~+25–29%
  decode**. Base model is MIT. **The download is running** on the head (nohup, console
  `/tmp/az-download.console`, ~169 GiB, no GPU needed; 1.2 TB free ✓).
  **Loader verification (2026-10-23, source at our pin)**: the native loader is
  EXL3-only — no GPTQ/autoround path exists in `zig/src` (91 files reference exl3; the
  gptq hits are unrelated xpu files) — so AZ *as distributed* cannot serve natively.
  **SCOPE (user, round 132): requants are OUT OF SCOPE for this repo until a safe,
  efficient method exists** — no requant tasks or plans live in this doc; the requant
  mentions below are the AZ pack's executed provenance only (its artifacts:
  `local/GLM-5.3-Flash-AZ-EXL3`, receipted 90/104 in the 4bpw sweep). Sub-4bpw work
  proceeds by SERVING community-built packs (the 3bpw track), never by local
  quantization. The arc's design doc (docs/REQUANT.md) is deleted; its lessons live in
  the append-only log and the agent-skill stores.
  But the glm config parser reads `num_experts_per_tok` from the checkpoint
  (`families/glm/config.zig:163`) and the routing kernels take topk as a runtime config
  field, which splits the lever into two experiments:
  1. **top4-on-our-own-checkpoint (cheap, next window)**: a variant model dir (symlinks
     to the existing safetensors + a config edit to `num_experts_per_tok: 4`) — measures
     the pure compute saving and the *un-retrained* quality floor with zero download.
     If the engine refuses top4, the refusal prints its arithmetic — a receipt.
  2. **the full AZ (after download + requant)**: the AZ checkpoint needs dequant
     int4→bf16→EXL3 4-bit (exllamav3 convert; window-gated, hours; disk choreography:
     ~640 GB bf16 intermediate + 169 GB source + output against 1.2 TB free — stage it,
     delete the intermediate before the gates run).
  **The quality battery (user: a new checkpoint means seriously more quality checks)**:
  both experiments get §2 gates + the full tool-eval + the structured-output scenarios +
  hardmode TEB + the duel probes — a double-quantized modded checkpoint is maximally
  guilty until measured.
  **Status 2026-10-24 (post-window)**: the variant served **topk=8 three times** — the
  config edit never persisted, because the snapshot's `config.json` is a *symlink into
  the shared blobs* (the edit aliased the base checkpoint or vanished; the early consoles
  that would show which were reboot-wiped). Fixed in the phase: the variant's config is
  now a REAL file, verified to read 4 before anything serves (verified on both hosts
  2026-10-24 12:48). The next window's top4 runs with zero prep. The 115242 top4 receipt
  doubles as a clean instrument validation — the duel baseline reproduces exactly with
  the agent silent (solo 55.8/55.7 Δ0.2%, c4 101.0, slope 0.660).
  **Experiment 1 MEASURED (2026-10-24, campaign-20261024-135458 — the real topk=4 serve,
  unretrained selector, after the full gate ladder: the parse's `want` pin + the EXL3
  module-global `top_k`, both patched in glm-topk4b.patch)**: routed 18.45 → 11.0 ms at
  2 rows (−40%; the weight-traffic union isn't slot-proportional, hence not −44%),
  verify 40 → 32.3 ms, 8-row shared rounds 76.5 → 53.3 ms. **Solo 63.5/63.6 (Δ0.2%) =
  108% of production's 58.7 — the generation-tok/s front crosses the bar at solo**; c2
  103%; **c4 120.4 = 78% of production (was 65%)**; slope 0.593 (−10%); acceptance rose
  (4.8 tok/chunk vs 3.37 — the fewer-expert target drafts easier). What remains: the
  quality battery (the unretrained selector is guilty until measured — config.sh stays
  topk=8 until it passes), and the AZ full checkpoint (the retrained selector) as the
  quality-safe route to the same win.
  **The battery RAN (2026-10-24, campaign-20261024-142659/13-top4qual.md)**: §2 gates
  ALL PASS (drafted=plain on the new model ✓); the full tool-eval **93/100 — above
  stock's 92** (production's anchor: 95); hardmode **89/100 vs production's 91** (the
  line's first hardmode datum — no stock reference exists). **The fork (user)**: adopt
  top-4-unretrained as the default now, or hold stock and route through the AZ full
  checkpoint (the retrained selector). **(user, 2026-10-24): ADOPTED** — config.sh's
  qualified defaults serve top4cfg + glm-topk4b (round 27; the scoreboard regenerated:
  solo 108%, c2 103%, c4 78%, streaming ~189%, prefill 45%, loading 27%).
  **Experiment 2 (the AZ full checkpoint — the quality-safe upgrade to the same lever)**:
  the download is COMPLETE (the Xet CAS survived the reboot; 170 G materialized,
  topk=4, 288 experts, auto-round int4 — verified 2026-10-24). The route: requant
  auto-round int4 → EXL3 4bpw (the engine's format; try exllamav3's streaming convert
  first — it may dequant per-layer with no intermediate; else dequant→bf16 ~640 GB
  intermediate with the disk choreography, then quant, then delete the intermediate),
  serve with glm-topk4b (the reference is already topk=4), then the battery + the perf
  probes. GPU work: hours, window-gated. If the battery passes, the default upgrades to
  the retrained selector.
  **Discovered en route (a separate lever, recorded)**: `AxonZeta/GLM-5.3-Flash-AZ-Focus-EXL3`
  — NOT azampatti's mod: AxonZeta's own weight edit against second-guessing (40–50%
  fewer thinking tokens at max effort, AIME 81.7 vs 75.0, GPQA up, SWE-bench 92 vs 95),
  **topk=8 intact, EXL3 4bpw native — serve-ready for our engine as-is**. For the
  agent-farm workload the fewer-thinking-tokens effect is an effective-throughput
  multiplier; a candidate experiment after the AZ route.
- **Lever B — upstream expert-prefill kernels**: #1143 (Flash Next NVFP4 experts on
  prompt tiles, decode-form sums) is the mechanism; the glm port remains the upstream ask.

## Front 3: loading — TAKEN at v1.2.0 (98.6%, the status block above); this section is the front's history (the packing-cache era)

The engine loads in ~250 s across every knob cell (walls 251–269 s; orchestration only
~8–17 s; the drafter ~11 s). The cost is the native loader's convert-and-pack path
(dense4/head4 packing + fp8 KV prep at load). Fix shape: a packed-weights cache beside
the existing byte-verify digest cache — pack once per (checkpoint, packing config), reuse
on every start. Scope from `load_plan.zig`/`cuda_qpack.zig` at our pin.

**Scope verified 2026-10-23 (source at our pin, re-cloned after the site's reboot wiped
/tmp)**: the load flow is `families/glm/weights.zig` (581 lines) — parallel preads of the
shards, then pack transforms into the serving layouts (`fixed(..., .router_pack)`,
`.hc_pack`, stacked projections and expert mixes via the `Loader`'s `stack`/`mat`/`experts`
helpers; the EXL3 handling in `families/glm/cuda_exl3.zig`, 206 lines). The cache
precedent exists: `core/checkpoint_identity.zig` already caches per-file digests
("83/83 cached files" — the byte-verify line in every serve log). **Patch shape**: after
a load, serialize the packed weight slabs keyed by (checkpoint digest, packing config =
DENSE_BITS/HEAD_BITS/KV_CACHE); on a matching start, skip read-and-pack and restore
(I/O-only, ~30–40 s at NVMe speed — a ~4–5× load win). Storage ~170–200 GB per config —
fits, but the cache should be one-config-deep with the key visible in /health so a stale
config self-invalidates. Open engineering question for the patch window: whether the
pack runs on CPU before upload (cache skips it cleanly) or interleaved on GPU (the cache
must then capture the device layout).

## The roadmap (2026-10-25, from the upstream sweep + bernisse's second-pair bake-off)

*Bernisse (forum post #926, a second 2×GB10 pair, same fixed prompts/thinking-off/T=0):
native 1.1.x prose 40.4 / code 62.3 / prefill64k 1,448 / 4× 217; **the fork (0.6.6+106)
49.1 / 91.6 / 2,483 / 639**; technigma NVFP4 43.0 / 67.4 / 2,933 / 359. Their native
4× (217) beats our measured 120 — workload/acceptance difference to reconcile; **the
fork's 639 aggregate and 91.6 code-decode make the PATCHED PYTHON STACK the field's
concurrency reference, not vanilla production.** They also independently confirm our
router diagnosis ("the router fix looks like the highest-leverage kernel work in the
field right now") and flag a quality instrument we've never run: **TC-92 (tenant
isolation) + TC-51 — the fork fails TC-92 deterministically; technigma is the only
clean stack (97).**

1. **Tonight**: the AZ battery digest (the convert lands ~20:00, `done.` ~21:00) — the
   retrained selector vs the top4cfg references.
2. **The thinking-efficiency track (quality + effective throughput)**: the AZ-Focus
   battery (test-ready on both hosts) + the `TF_GLM_CLEAR_THINKING` knob (#840, landed
   upstream Oct 25) — fewer thinking tokens at equal-or-better accuracy = the agent
   farm's effective throughput, quality-safe by construction.
3. **The router GEMM replacement** (Front 2 A2) — now field-confirmed as the
   highest-leverage kernel work; the 8-slice bit-stable design is scoped.
4. **The v1.1.5 candidate test**: released Oct 25; visible glm content = functional,
   no measured perf — the gate holds, BUT **#1218 (our slot-leak) is MERGED and slated**
   — the first correctness reason to test a bump. Protocol: build 1.1.5's tree,
   rebase glm-topk4b, run the §2 gates + the perf probes; adopt only receipts-equal-or-better.
5. **The pages×fp8 marriage** (#1163 mergeable-clean, #1211 stacks): when paging×fp8
   lands, the 512K window admits 8 streams ON fp8 — concurrency and cache bytes together.
6. **The concurrency references**: reproduce bernisse's native-217 cell (workload-matched:
   code-domain prompts, thinking off) and study the fork's scheduler for the 639
   mechanism; both re-anchor Front 1.
7. **The isolation quality round**: add TC-92/TC-51-class scenarios to our battery —
   drafted/serial equality does NOT cover tenant isolation (bernisse's caveat).

## Research log

- 2026-10-23: upstream v1.1.3 released (21:25) — **no glm/cuda perf content** (one
  sampler change, ~1% unverified; a Nemotron-only draft-schedule change −17%/+13%);
  **(user) version bumps are perf-gated** — we stay at TF_COMMIT=1351ed16, the pin is in
  local.sh. The builder now builds and ships libtfgrammar (xgrammar v0.2.8) beside the
  binary — our source builds never carried it (structured output ran degraded; the
  quality round will test whether the 3-point tool-eval gap closes) — a builder fix at
  this pin, not a version bump.
- 2026-10-23: the forum (381350, 904 posts, active today): **azampatti/GLM-5.3-Flash-AZ**
  (the top-4 routing mod above) is the first community checkpoint mod that attacks
  per-token *compute* rather than quantization; ajvazan's quality pass makes it testable.
  Also: the request log lines carry per-request acceptance (`accepted=168/299 rounds=119`)
  — an instrument for the drafter's behavior. grebneke's finding: the reasoning-effort
  hint is ignored at depth when it sits at the prompt top (template-level, quality-adjacent).
- 2026-10-23: PR #1155 read — batched MTP drafting is flashnext-family-only (17 files);
  the glm port is the concurrency-scaling patch candidate.
- 2026-10-23 (later): **(user) approved the AZ attempt** — "a new checkpoint will mean
  seriously more quality checks" — the quality battery is expanded accordingly (Front 2
  Lever A). The download is running on the head; the loader check at our pin found the
  native engine EXL3-only but topk-dynamic, splitting the lever into the cheap
  top4-on-our-own-checkpoint experiment (no download) and the full-AZ EXL3 requant
  (window-gated, hours).

## Vision qualification — DONE (the round-55 era; the section's queued framing retired round 132)

Vision is the standing default: served with VISION=1 at the 524,288 window, the
vision suite 8/8 on the adopted template, verified production-equivalent perception
(docs/DELTAS.md). The tower rides BF16 in every served pack (the requant-era staging
notes are history in LAUNCH.md). Requants themselves are OUT OF SCOPE (user, round
132) — see the scope note at the top of this file.

- 2026-10-24 (later): **the two-box conversion pattern (user asked)** — today's convert
  is single-GPU by design (exllamav3 quantizes layer-by-layer with calibration in one
  process; no layer-range/multi-host mode), so the worker cannot share the bottleneck.
  What the worker CAN take: (a) half of any future stream-dequant (the shard-parallel
  CPU+disk stage) with the rail merge, and (b) the NEXT lever's downloads — the
  AZ-Focus-EXL3 download started on the worker now (59 files, ~163 GiB, 1.7 T free)
  while the head's convert runs. The worker always joins the serving/battery as rank 1.
- 2026-10-25: **v1.1.5 released** (Oct 25) — the visible glm items functional, not perf
  (the pool-queue fix `2e33e297d`, `TF_GLM_CLEAR_THINKING` #840, the shared-gate
  saturation fix, the cold-prompt-state fix, `return_token_ids` instrumentation, the
  tool-call max_tokens fix) — the perf gate holds, but the **#1218 slot-leak is MERGED
  and slated** → the first correctness reason to run the v1.1.5 candidate test (with
  the glm-topk4b rebase). Also: NVIDIA's FP4-Local and XSFP4 checkpoint formats land in
  the engine's model catalog (the README's Pick-a-model row) — the checkpoint-class watch.
- 2026-10-25: **the forum (914 posts)**: bernisse's second-pair bake-off (the roadmap's
  numbers + the TC-92/TC-51 quality instrument + the fork-as-field-reference) — the
  roadmap section carries the synthesis. **kindlingai/gr8: a THIRD engine** (a
  from-scratch CUDA engine; GLM-5.3 full on TP=3-6 + the Flash TP=2 doc with caveats,
  "not final") — the ecosystem's third implementation; the watch: its numbers + the
  DFlash/vision roadmap. ajvazan daily-drives an EXLR8 quant on TensorFold with no
  issues — the checkpoint candidate class.

- 2026-10-27: **the v1.1.6 rebase ADOPTED** (round 33) — the engine at `eea9dc9c`; the A/B on the
  identical Focus serve: **c2 74.7→94.3 (+26%), c4 119.8→150.6 (+26%)**, hardmode 90→91 (ties
  production), everything else flat. The upstream #1322 KV-pages default transferred at +26% on
  EXL3. **The Focus's c2 gap vs the top4cfg is CLOSED** (94.3 ≥ 90.0) — the perf question narrows
  to the solo/c4 slope. The served default's scoreboard rows are v1.1.2-era — the top4cfg re-qual
  on v1.1.6 is the next window before the rows/chart move. The bench updated to v3.0.1 (the
  graphics + the web `serve` + hardmode to TC-104) — scores across the bench boundary wait for
  the re-baselines (production's in flight; our serves next window).

- 2026-10-28 (rounds 45–49): **v1.1.8 ADOPTED** (the receipts-equal battery), then
  **`TF_GLM_INDEX_CUDA=1` ADOPTED** — the depth ladder receipted cold prefill as
  superlinear (marginal slopes rising 0.860→0.976 ms/tok) and the indexer kernels flatten
  it (−2.6% at 131k → −5.5% at 393k; gates ALL PASS; duel/loading/decode unchanged). The
  cache levers closed at this window (the store doesn't grow on request; spill doesn't
  cover GLM — upstream-bound). **The remaining frontier: the resume/restore cost**
  (~1,434 ms vs production's 65 ms at 7.2k tokens — the source-level dig), and the
  depth-fact re-run on the standing config.

- 2026-10-27 (round 34): **the TTFT-at-depth frontier root-caused at source level** — the native
  engine's prompt cache is a token-prefix cache, but it keeps states only at conversation-structure
  marks (history / rewind / stable-diff / shared cuts), and a chat request's shared cuts cover only
  the system prefix. Shared prefixes inside user content never get a kept state → full prefill every
  request → the +0.663 ms/tok slope. The fix shape: keep grid-boundary states inside long prompts
  (spans are token-derived, so resumes stay exact) — a marks-policy patch experiment for the next
  window, gates battery around it. Full chain: LAUNCH.md round 34.

- 2026-10-27 (round 37): **the score comparison completed on v3.0.1** — the top4cfg ties
  production on tool-eval (96 = 96, 133/138 both) and leads every perf front (c2 124%, c4
  109%, solo 110%) but takes hard-mode 76% vs 90%; the Focus 95/86%. The bar's fronts:
  tok/s CROSSED; **prefill 78% and loading 37% remain the open fronts** (loading
  decomposition still pending), plus the TTFT-at-depth frontier (3%). The way-forward
  stack: (1) the marks-policy patch experiment for the frontier, (2) the loading
  decomposition from the restart logs, (3) the upstream watch for a marks-policy/prefix
  fix landing, (4) the (user) hardmode-trade decision on the default.

- 2026-10-27 (round 38): **the (user) hardmode-bar decision** — hardmode is THE quality
  measure; the served default swapped to the Focus (92 run-level vs production's 94). The
  chart re-anchored to the Focus cell (solo 98%, c2 109% CROSSED, c4 99%, ITL 102%, loading
  41%, prefill 67%, TTFT-at-depth 3%). The perf fronts keep their receipts: the top4cfg's
  crossed rows remain the documented perf leader; the open perf items are unchanged
  (TTFT-at-depth → the marks-policy patch; loading decomposition; prefill; the v1.1.8
  indexer A/B). The quality line's new track: the beat-94 plan (multi-trial variance, the
  AZ retrained selector un-park decision, the upstream EXL3-format watch).

- 2026-10-28 (round 40): the overnight verdicts — the variance check says the Focus's 92
  is stable (three variant seeds, one score); the recommended-settings cell scored 91 (no
  lift; greedy stays); the marks-patch passed every gate but the duel didn't move (the
  instrument can't see the cross-request resume — a same-prefix-repeat probe + the cache
  counters is the next experiment before the patch is judged). The bench moves to
  --parallel 2 for all future runs (the (user) round-39 call). The TTFT-at-depth frontier
  remains open pending the better instrument; the loading and prefill fronts unchanged.

- 2026-10-28 (round 41): **the two-shot instrument landed and re-wrote the frontier** —
  the marks-patch is proven (cross-prompt prefix resume, gates PASS, the fingerprint:
  patched pair-1 shot-1 1,445 ms resumed from the duel's kept states vs the unpatched
  cold 7,359 ms); identical-prompt resume exists unpatched (80%); production's resume is
  65 ms where ours is 1,440 ms (22× — the snapshot-restore cost is the new named gap);
  the duel's cross-length non-resume is junction tokenization (the instrument, not the
  patch). The frontier decomposes into: cold prefill (the indexer path → v1.1.8's
  TF_GLM_INDEX_CUDA) + restore cost (the snapshot copy — a source-level dig) + cache
  churn under load (the budget/eviction lever, a knobs cell). The patch's adoption
  (a standing PATCHES line) is the (user) call: exactness-safe, proven, helps repeated
  prefixes; it does not move the cold-prefill slope.

### Front 2 A2 — RESOLVED (round 98, 2026-10-30); the served-path census complete (round 114, 2026-10-30)

The ~1109 ms router section is **bubbles, not kernels**: ncu under the counter-permitted
wrapped restart shows the section's kernels cost ~30 ms p50 (~71 ms p95) per 2048-row
chunk — 2.7% (6.4%) of the section. The stage spans are paired same-stream CUDA events
(zig/src/families/glm/cuda_prompt_trace.zig), so the ~1080 ms is device-side idle between
µs-scale launches: host enqueue/sync starvation. Fix class: OVERLAP — the fork's
HC-split/overlap set (0010/0033, +36% prefill) or upstream's row-split pair seam
(e06a6eef) when it covers GLM. 0086 (bit-exact scoring loop, 131 lines, python-only)
ports first as the cheap adjacent win; the receipt:
results/campaign-20261030-023707/31-ncurouter.md (completed read in the receipt).

**The served-path per-kernel census (round 114, campaign-20261030-134836 — the
rank-0-only ncu topology, prompt-shaped rows=1322)**: hc_partial p50 104.4 µs /
hc_finish 53.9 µs (×2 hcPre/layer each — 320 launches/pass), router_tile 204.4 µs /
slice_sum 58.5 µs (×1/layer — 160 launches/pass; the router's slices are ALREADY
z-batched in one launch via tf_glm_router_tile — v1.1.9's aligned 64-row tile branch;
round 112's kernel attribution corrected, the round-84 chain path is not in v1.1.9).
**The fusion target: the hc chain** — fuse partial+finish into one block-per-row
kernel (same K-block order, same arithmetic → bit-safe by construction; the decode
partial8+finish pair likewise, shrinking the CUDA graphs). The router pair stays
unfused (serializing the 8 z-slices per block drops parallelism ~8×; ordered
cross-block reduction needs grid sync). Next: the fused-kernel patch, compiled on
v1.1.9, A/B'd per the definitive protocol with 2+ runs per arm and the content gate.

**Front 2's fusion sub-lever — CLOSED (rounds 115/116, campaign-20261030-144836)**:
the fused hc_pre kernel was built to spec, compiled RC=0, and the content gate came
back IDENTICAL — bit-safety by construction proven. But the perf regressed where it
mattered (solo decode −8.4%, c2 −8.3%; prompt exactly neutral) and the patch was NOT
adopted: the fusion serializes the 16 K-blocks (the chain's grid-y parallelism) into
one block's sequential loop — free at prompt occupancy, costly at decode occupancy.
The launch-gap hypothesis is measured and void: the glue's launch gaps are hidden
behind the router/expert GEMMs' queue depth at both shapes. Front 2's remaining
direction: the OVERLAP class — the fork's HC-split/overlap set (0010/0033, +36%
prefill) or PDL on the finish launch (the launch site already carries a .pdl flag;
the finish's x/nw prologue is independent of `part`, so a dependent-launch overlap
would hide the gap without giving up the grid-y).

**The v1.2.3 perf items (added 2026-11-06, cont. 68 — the rebase validated, the ref adopted)**:
v1.2.3's changelog carries two opt-in serving knobs relevant at TP=2, both now
probed by the `v123perf` window on the duel instruments against the standing
paged absolutes (duelpaged, campaign-20261106-052114: solo 63.5/63.2 t/s, c2
110.6, c4 154.8, ITL p50 55.3 ms, TTFT slope 0.612, d0 199 ms):
- **TF_GLM_CHUNK_SOLO=4096** — CLOSED (v123perf, campaign-20261106-080743):
  REFUSED beside the drafter — "TF_GLM_CHUNK_SOLO=4096 holds buffers no pass
  uses beside --drafter: unset it, or leave out --drafter" (the refusal is
  the receipt; the error survives v1.2.3 even though its explain() entry
  was dropped from the message table). Our serving keeps DFlash2, so the
  knob is unusable on our shape — upstream's ~7% TTFT is a drafter-less
  measurement. RETIRED for this line.
- **TF_GLM_COPIES=1** — CLOSED (v123perf, campaign-20261106-080743): PURE
  PARITY on every instrument — solo 63.8/63.4 (standing 63.5/63.2), c2
  109.8 (110.6), c4 154.2 (154.8), ITL p50 55.3 (55.3), TTFT slope 0.611
  (0.612), d0 193 (199) — all within ~1%. RETIRED per the discipline
  (parity retires; a knob must win to advance).
The knob discipline applies: a knob advances to a confirm window only on a
sharp, instrument-consistent win; parity or a regression retires it; adoption
additionally wants the quality gates (the receipts-equal-or-better protocol).
The arms double as the v1.2.3 rebase's perf spot-check — a wild move vs the
v1.2.2 absolutes is a rebase red flag. **SPOT-CHECK PASSED** (campaign-
20261106-080743): the copies1 arm (v1.2.3 + COPIES=1) sits within ~1% of
the v1.2.2 standing absolutes on every instrument — the rebase changed no
perf path, as the diffstat/semantics analysis predicted.
Also in the same window: the depth ladder re-qualification on the adopted
paged v1.2.3 stack (the standing `depth` phase — the 12/12 bar, the post-
adoption re-run queued at the adoption digest).

**The Front 2 design pass (cont. 83, desk work) — the candidate found, the
citation corrected**: the fork's materials contain NO "+36% prefill" claim
(grepped the repo — the number is unlocatable; the plan's "(0010/0033,
+36% prefill)" citation is withdrawn). 0010 is the side-stream drain fix
(no anchor here); 0033 is the TEST for a decode-side f_b+g_b pair fusion
(whose implementation patch was never located — parked). The REAL
prefill-class lever in the fork's early series is **0009: the packed-prompt
matmuls in two stages (`glm_mm{4,6,8}_128s2`)** — 21 lines on
glm_mm.cu/cuda_mm.zig (files our 4-patch stack never touches; **applies
clean on v1.2.3, verified**), the mechanism pure occupancy (41 KB smem in
two cp.async stages → two blocks/SM instead of one; a 768-row piece's 384
blocks fit one wave instead of 2.04), and the sums **bit-identical** (the K
groups run in the same order — Mia measured 0 differing outputs on all
eight shapes). Mia's measurement: 1.07-1.09x on GLM's prompt shapes on
sm_120 (RTX PRO 6000, 400 W sustained), with the caveat that under their
power cap most of the occupancy gain became power — the GB10's envelope
differs, so our A/B decides. **Ported as `glm-mia-packed-s2.patch`**
(staged, the header carries the provenance + the measurements). **The
mms2 window launched**: arm off (the standing 4-patch stack) vs arm on
(+ the s2 patch; the rebuild rides the restart), each with the greedy
content probes (three prompt sizes, the content shas — the cross-arm
identity IS the bit-exactness gate on our shape) and bench_perf twice per
arm. The bar: content IDENTICAL + a sharp pp gain → the battery + the
duel re-pair (the adoption judgment); a content DIFFERENT retires it
outright; pp parity retires it; the tg rows moving is an instrument red
flag. The target: the prefill front's 69% (1,049-1,115 vs production's
1,518) — an 8% prefill gain would be the front's first structural move.

**The prefill front's next lever, ported (cont. 87)**: Mia 1104 0007+0008
— the EXL3 prompt path in one call (chunk_rows follows prefill_rows: the
trellis decodes once a pass instead of twice) + the down kernel writing
the MoE slot rows straight (yrow — the cuMemcpy2D of [rows][8][4096] fp32
per call dropped) + no target-MTP prompt absorption beside a drafter (a
whole DSA+MoE layer a pass, 3.4-4.4% of a traced pass — pure waste on
our DFlash2 shape). **Hand-ported as `glm-mia-exl3prompt.patch`** (the
fork's hunks drifted: no k6 kernels here, the v1.2.x engine delegates to
prompt_solo.mtpRows, the test files dropped — the content gate verifies);
**verified byte-identical to the port commit on a fresh checkout**. Mia's
combined claim WITH 0009 (our adopted packed-s2): cold prefill
+12.6/15.6/16.0% at 4K/16K/64K, T=0 replies unchanged. **The exl3call
window launched**: the mms2 A/B pattern (arm off = the 5-patch stack, arm
on = + the patch), the content-sha cross-arm gate + the pp rows twice per
arm. The target: the prefill front's 76% → the low 80s.

**The exl3call A/B cleared every bar (campaign-20261106-201824) — the
front's biggest move yet**: the content shas IDENTICAL across arms (the
bit-exactness claim verified through the one-call rewrite), pp
**+24.5/+22.7/+23.3%** at d0/d4096/d8192 — two runs per arm with
near-zero spread (off 1151/1151, on 1437/1430) — **exceeding Mia's own
+12.6-16% combined claim** (the GB10 converts better than their sm_120:
the dropped copy + the halved trellis decodes + the MTP-pass skip land
harder here). **The prefill front: 1,150 → 1,434 tok/s = 94.5% of
production's 1,518** — from 76% in one patch. The exl3qual window
launched: the gates + the battery + the vision on the 6-patch candidate,
then the duel re-pair (the duel's ours arm rides MMS2_DUEL_PATCHES with
the 6-patch list; its image is a cache hit on exl3qual's build).

**The exl3prompt ADOPTED (cont. 89)**: config.sh's PATCHES is the 6-patch
stack; the anchors + DELTAS + README re-paired on the EXL3P duel; the
prefill front stands at **94.4%** — the remaining candidates are thin
(0033's implementation unlocated; 0011 is contract-hardening, no perf
claim). The next lever hunt (the fork's later series, the upstream
watch) or the loading wall's re-take (91%, the other open front) are
the live options. The bare 6-patch default gets its codified smoke
(adoptsmoke3) before anything else.

**The bare-config smoke PASSed (cont. 91)** — the 6-patch default is
served and verified end to end (the fingerprint witness + the serve
line + the exact probe reply). The default-change loop is closed. The
next step stands: the prefill front is at 94.4% with thin candidates
(0033 unlocated, 0011 contract-hardening) — the live options are the
fork's later-series hunt, the upstream watch, or the loading wall's
re-take (91%, the other open front).

**The next lever, ported (cont. 93)**: Mia 1104 0005+0011 — the latent
attention FP8 key tiles load 8 bytes at a time, a tile ahead (the reads
overlap QK/softmax/PV; the conversion moves to where load_kv(tile+2)
stood; the shared-memory keys are the same bits) + the 256-thread
launch as a named contract. **Hand-ported as
`glm-mia-attnfetch8.patch`** — the port's novel work: our chunks_wide
carries PAGED8 (the marriage), so fetch8 folds the page-table
addressing for a sparse key's codes and scales; bit-order verified
identical (little-endian code pairs); the chain verified
byte-identical on a fresh checkout. **Mia's claim: decode dense chunks
58 → 35 µs, sparse 72 → 41-44 µs** — the largest claimed decode lever
left in the series. The 0013 stale-tap bug turned out ALREADY MAINLINED
in v1.2.3 (upstream PR #1623 — tapPieces/shareTaps present); 0006+0010
(the MoE side-stream overlap, −12-14% a layer) is the next candidate
after this one. The attnpref A/B launched: the content gate + the bench
rows + the steady-state decode probe (the honest tg instrument).

**The attnpref window burned on the patch-order gotcha
(campaign-20261107-003829)**: the arm-on build refused — the image
applies the stack ALPHABETICALLY and glm-mia-attnfetch8 sorted before
the fp8-pages marriage whose PAGED8 file-state the hunks assume.
Renamed glm-zz-attnfetch8.patch (the dsasel3 convention). The arm-off
baseline is banked (the content shas + bench + the steady-state
probes). Relaunched.

**The attnfetch8 A/B cleared the content gate and shows a consistent
depth gain (campaign-20261107-010849)**: the content shas IDENTICAL on
three prompt sizes AND the 2048-token decode replies (369 vs 369
tokens — the keys are the same bits, so the quality instruments cannot
move); bench pp +1.7/+3.6-4.3% and bench tg +2.9/+3.3/+4.7/+5.8/+10.9%
at every depth cell (d4096 solo +10.9% the largest; d0 tg -1.4% the
noise cell). The steady-state probe read parity but cannot resolve
single digits (integer-second walls on a ~9 s request — its pairs
mirrored each other); the duel's solo ITL instrument (0.2% stability)
is the resolver and rides the judgment window. attnqual + the duel
launched: the formality receipts (§2 + hardmode + the vision) + the
duel re-pair on the 7-patch candidate decide the adoption.

**The last pre-marriage candidate, ported (cont. 97)**: Mia 1104
0006+0010 — a decode window's MoE shared expert on a side stream beside
the routed experts (the fork right after the block's input, the join
before the slot combine; the kernels and the combine's order unchanged,
the bits the same; TF_GLM_SHARED_SIDE=0 the kill switch; 0010's drain
on error/teardown). **Hand-ported as `glm-zz-moeside.patch`** — our
drift: the two Forward constructions carry .absorb_mma, the port adds
.side beside it; upstream's flashnext has the same pattern so the
Stream/Event API matches. **Mia's claim: 70.6 → 60.6 µs a MoE layer at
one row, 96.5 → 84.9 µs at two (−14/−12%)** — a decode-layer overlap
lever, the last one in the series (0012/0014/0015 are
capacity/hygiene). The chain verified byte-identical on a fresh
checkout. The moeside A/B launched: the content gate + the bench rows +
the steady-state decode probe with ~2000-token walls (±2.5% resolution
— the attnpref probe's lesson).

**The moeside A/B clears with a resolved solo gain
(campaign-20261107-083254)**: the content shas IDENTICAL on three
prompt sizes AND the 2048-token essay replies (the bits are the same);
the steady-state probe RESOLVED this time — the off arm 51/51 s (0%
spread), both on-runs faster: **40.2 → 41.4 tok/s avg (+3.0%),
4/4 sign-consistent**, matching the claim's transfer math (−14% × the
MoE share of a decode step ≈ +2.4%); the bench corroborates on the
solo cells (+2.9%/+3.1%, c2@d0 +6.0%) with depth concurrency flat
(expected — the overlap gains shrink under saturation). moesidequal +
the duel launched: the formality receipts + the duel's solo (the 0.2%
instrument) decide the adoption.

**The moeside ADOPTED (cont. 100)**: config.sh's PATCHES is the
8-patch stack; the anchors + DELTAS + README re-paired on the MOESIDE
duel — **solo 112.3%** (65.9/66.2 vs 58.7/58.8, two instruments
agreeing), c2 129% of the floor (past production's top volley), c4
158.6, ITL 110%, the cold 429%, prefill 96.0%. **The fork's
pre-marriage series is now fully triaged** — every perf-relevant patch
(0005/0006/0007/0008/0009/0011) is adopted or retired with a receipt;
0012/0014/0015 are capacity/hygiene (no perf claim). The live options
for the next lever: the loading wall's re-take (91% — the last open
front), the upstream watch (docs/ECOSYSTEM.md — v1.2.4+ when it
ships), or the capacity/hygiene ports when the resume front needs
them.

**The post-marriage series triaged (cont. 102)**: 0026/0027/0028 (the
EXL3 grouped load-ahead + the no_allocate trellis policy) are ALREADY
MAINLINED in v1.2.3 — our `exl3_grouped.cuh` carries the nx-prefetch
warp_tiles with the LOAD-mode instrument (PLAIN/SKIP/STALE) and
`ldg_stream_u32` = `ld_nc32` with 0028's exact rationale in its
comment; 0029 is a comment fix. What remains is structural:
- **0030** — a decode window's MoE glue fused: topk_row + group_rows
  in one block, down_combine taking the shared expert's row, gone two
  2D copies + tf_exl3_group + put_slot + combine a layer (the bits the
  same byte for byte; TF_GLM_MOE_FUSE=0 the kill switch). The port
  surface is the biggest yet (a fused kernel + the experts staged) —
  the next sitting's opener with full budget.
- **0031+0032** — the step-link: the first broadcast 384 bytes (one
  host round trip instead of two), the keep piggybacked, the followers
  skip their gathers; 0032 the keep-loss guard. A TP-pair latency
  lever, likely ~1-2% decode, in the rank-pairing-critical class —
  queued behind 0030.

**The step-link ported first (cont. 103)**: 0030's true size (991
lines, 12 files) makes it a multi-sitting port — 0031+0032 (383
lines) went first as `glm-zz-steplink.patch`: a window's greedy picks
in ONE gather (the pairs buffer pick_rows=32 wide — the verify
window's rows stop paying a round trip each), the step in one
384-byte broadcast, the keep piggybacked on the next step of the same
slot, the follower joining its gathers and skipping the reads, and
0032's keep-loss guard. The port DROPPED 0031's moe_fuse leakage
(0030's plumbing — the fork stacks them; 0030 stays queued with full
budget). The engine_pick + follow hunks applied verbatim (v1.2.3's
files match the fork's baseline); the engine bits hand-ported. The
chain verified byte-identical on a fresh checkout. No arithmetic
changes — the content gate covers it. The steplink A/B launched.

**The steplink RETIRED (cont. 104)**: the A/B (campaign-20261107-
105455) — content identical everywhere (the no-arithmetic-change
claim held) but the gain at parity: the steady-state +1.0% avg inside
the probe's ±2%, the bench tg mixed-sign noise, pp flat. The
mechanism is real but sub-resolution on our shape (a 1-row window
does one gather either way; the verify-window round trips are cheaper
than assumed). The patch stays staged. **The remaining structural
candidate: 0030 alone** (991 lines, 12 files — the MoE-glue fusion,
multi-sitting). The loading wall's re-take (91%, the last uncrossed
front) and the upstream watch remain the other live threads.

**Round 135 (the v1.2.4 sitting)**: the rebase landed and QUALIFIED
(v124val, campaign-20261107-132414: §2 ALL PASS, hardmode 95 — the
eighth consecutive, the vision 4/4, flat decode/pp; two burns on the
way — the TF_KV_SHARE rename + floor, and the ninth patch's PATCHES
omission). The loading lever's last obstacle found and removed: the
served TR3 pack's 120 shards exceed checkpoint.direct's max_sources 64
(the fd budget) — the pack resharded byte-identically to 55 (the tool
verified sha256 on sampled tensors). **THE NEXT STEP: the v124val
re-run on the resharded pack — the direct-reads witness + the timed
walls are the loading row's re-take; then the duel re-pair re-dates
the v1.2.3-era scoreboard rows.** The 0030 port (the MoE-glue fusion,
991 lines) stays queued behind the loading front.

**THE LOADING FRONT CROSSED (round 135 cont. 7)**: the fifth v124val
window (campaign-20261107-150250) — the direct reads ENGAGED on the
resharded pack (the witness line fired; three windows of diagnosis
behind it: the rename, the PATCHES omission, the 120-shard fd budget —
each a receipt), the timed walls **83/83 s vs production's 93.7 =
112.9%** (the v1.2.3-era 103 s wall = 91%; the direct reads took 20 s
off). The quality held through every run: hardmode 95 (the ninth
consecutive), the §2 gates ALL PASS, the vision 4/4, the arms
content-identical to the byte, the decode and pp flat. **The (user)
bar's fronts: solo 112.3% crossed, loading 112.9% crossed, prefill
96.0% the closest remaining gap.** NEXT: the v1.2.4 duel re-pair
re-dates the v1.2.3-era speed rows (the duel window); then the 0030
port (the MoE-glue fusion, 991 lines) with full budget — and the
prefill front looks at 0030's launch-savings math first.

**THE 0030 PORT QUALIFIED AND ADOPTED (round 136)**: the port landed in
one sitting (8 files clean, 4 hunks re-anchored — the receipt in
patches/README.md; compile RC=0 first pass; byte-identity 0 diff
lines) and the moefusequal A/B (campaign-20261107-172250) cleared it:
the arms' content IDENTICAL (the same 80cc3802… sha as every window),
the §2 gates ALL PASS, **hardmode 95 (the TENTH consecutive)**, the
vision 4/4 — and the decode instruments read the launch savings: **c4
166.1 vs the OFF arm's 159.4 (+4.2% — our best c4)**, c2 +1.0%, ITL
−1.5%, solo flat, prefill flat (the prompt path untouched by design —
the fusion is a decode-window lever; it cannot move the prefill
front). config.sh carries the tenth patch; the anchors re-paired to
the ON arm (solo 115.2%, c2 134.4% of the floor, c4 107.2% at
production's floor, ITL 115%, cold 434%) and the chart re-rendered.

**THE NEXT STEP: the duel re-pair on the adopted 10-patch stack** —
production-for-testing + ours the same window re-dates every speed row
same-window (the adoption pair cites production from the same-day
v1.2.4 duel; the duel makes it same-window). THEN the prefill front
(96.0%, 1,458 vs 1,518 tok/s — the last uncrossed (user)-bar front):
0030's fusion is decode-side, so the prefill lever must come from
elsewhere — the fork's 0033+ untriaged tail (the 0009+0033
packed-prompt/pair-launch line the design pass named) and the
launch-savings math the fusion proved (fewer launches a window) are
the candidates to scope.

**THE ZMOE-FUSE DUEL RE-PAIRED (round 136 cont. 3)**: the same-window
pair on the fused 10-patch engine (campaign-20261107-183530) — solo
**67.6/67.5 vs 58.6/58.6 = 115.4%**; c2 **117.3 vs 110.3 = 106.3% —
above production even at its top-of-range volley** (its floor 87.1 =
134.7% there); c4 **168.8 vs 154.7 at its floor = 109.1%** (our best
c4 again); ITL **14.6 vs 17.1 ms/token = 117%**; overhead 189 vs 185
ms; the cold d8192 3,961 ms, slope 0.460 — 433%. Every row holds the
A/B's adoption read. The anchors re-paired, the chart re-rendered.

**THE NEXT STEP: the prefill front's scope** (96.0%, 1,458 vs 1,518
tok/s — the last uncrossed (user)-bar front): read the fork's
untriaged 0033+ engine-series tail on the head (/tmp/mia-fork), map
the prefill-class candidates (the 0009+0033 packed-prompt/pair-launch
line the design pass named; the ECOSYSTEM table's HC-split/overlap
set and prompt-scoring lever if they appear in this series), size the
top one, and stage its port next sitting. No window until a candidate
is staged.

**THE PREFILL SCOPE, LANDED (round 136 cont. 4)**: the fork's gen-5
tail mapped (0033-0090). The candidates by measured claim:
- **exl3p 0078+0079 (527 lines)** — the prompt experts' main loop
  compiled for 8-member column blocks, the next k tile decoded among
  the current MMAs, cp.async per item, the fwht epilogues as FFMAs:
  **gate/up 1.177x, down 1.161x measured on the prompt-expert kernels
  (2,048 rows)**, energy −9-10%. At a plausible experts' share of our
  pp2048 prefill (~0.3-0.5) that is +5-8% whole-prefill — the 96.0%
  front's crossing with margin. 0080 (185 lines, the packed prompt
  linears' cp.async) is a follow-on. THE TOP CANDIDATE.
- The PDL set (0069+0070+0071, ~300 lines): the mm reduce/hc/p2p chain
  as dependent launches — a launch-gap lever, unmeasured for prefill;
  our prefill is long-kernel-dominated (the 0030 A/B's lesson: launch
  savings show at decode concurrency, not in the dense prefill loop).
  PARKED behind exl3p.
- The HC-split/overlap set (0075/0086/0088/0089/0090 + the pairing
  line 0050-0063): the +36%-at-50k class — a multi-patch TP-exchange
  rework; at our 2k bench prompt the exchanges are small. PARKED.
- 0064 W8A8: 8-bit prompt linears — a quality trade, not a rate lever
  on our 4-bit dense. NOT A CANDIDATE.

**The exl3p port's drift, measured**: 0078 rejects clean-apply on our
tree in all 3 files (4 hunks) — the fork's base carries a K2 template
parameter in the prompt loop (its 0003 3-bit work; v1.2.4 never
absorbed it; our loop is `template <int MATS, int XR>`). The port:
replace our tmain with the new loop adapted to our 2-param form (the
4-bit path is what runs on our model — decode_a8/mcg2 are the
4-bit-relevant pieces), then the .cu and .zig hunks (their drift is
our 0030 re-anchors). Multi-hour, kernel-level — the next sitting's
work, then the exl3pqual A/B (content identity — the same bits are
the claim — + the bench pp rows, hardmode, gates, vision).

**THE EXL3P PORT STAGED (round 137)**: 0078+0079 landed on v124-rebase as
`glm-zz-zprompt.patch` (the eleventh; zp > zmoe-fuse). The fork's text
verified line-identical (244/244 .cuh, 18/18 .cu) except the documented
adaptations (4-bit-only tree: K2 at 8 only, our helper forms kept, the
classic loop kept as the _cl twins behind TF_GLM_EXL3P=0, 0079's _k6
records skipped — no _k6 kernels here). Compile RC=0; the contract
records re-measured on our own nvcc 13.3 build. **THE NEXT STEP: the
exl3pqual A/B window** — both arms the same 11-patch image, the knob flips
the path: content identity (the same-bits claim), the bench pp rows + the
TTFT slope (the prefill lever's instruments — the fork measured the prompt
kernels gu 1.177x / down 1.161x), hardmode's eleventh 95, the §2 gates,
the vision 4/4. At adoption: config.sh's eleventh patch, the anchors'
prefill row re-paired, the duel re-pair next window. 0080 (the packed
prompt linears' cp.async, 185 lines) stays the follow-on candidate — its
base may need the fork's 0073 MmTwo concepts checked first.
