# Performance plan: closing the measured fronts

> **THE CURRENT NEXT STEP (one pointer — kept current; the history below is
> the trail, round 141 cont. 44, 2026-11-12)**: **the duel A/A re-ground
> LANDED (window 62, campaign-20261112-030105: all five instruments flat
> inside the band — solo 100.7%, c2 101.0%, c4 101.8%, ITL ~flat, overhead
> 99.5%; the c4 198.0 the highest ever recorded; the anchors re-dated on
> the third pair — production-vs-us is now measured v1.2.7-vs-v1.2.7 at
> every row)**, and the warmkeep arc is CLOSED (windows 52-61: six voids,
> then the first VALID A/B — the end state never admitted on the GLM
> native serving path; 023 retired). The re-ground closes the re-pair
> item. What remains: the upstream watch (#2852 EXL3 whole-pass routing,
> #2856 batched shared MTP — OPEN with no numbers; the next release may
> mainline them), the user-parked 0110 KV-SHARD port, the DRAFTS=0+
> LIVE_HALF composition. The next sitting opens with the ECOSYSTEM read
> and a stage brief naming a user-visible number — no launch without one.
> The board behind it: the warmkeep arc CLOSED
> (windows 52-61: six instrument voids, then the first VALID A/B — window
> 61's page-aligned fills on both arms, the colds honest, the greedy shas
> IDENTICAL, and the ON arm's warm `cached=2048/6144` IDENTICAL to the OFF
> arm: the end state is never admitted on the GLM native serving path; the
> kill criterion fired; 023 retired; the ledger's OPEN warm-resume item
> CLOSED; the upstream-data fact the arc bought: the GLM native family
> never wires the radix report() line, so the store's per-request counters
> are invisible — a re-open requires the report() wiring FIRST)**. The
> board: config.sh back at the 18-patch qualified optimum on v1.2.7; the
> warm row stands measured at 945 ms (d8192, the page resume's len−2048
> coverage); quality holds 95 ×33; the anchors' duel rows date to the
> round-133 re-pair on the v1.2.6-era 16-patch stack. **THE NEXT STEP: the
> duel re-pairs on the v1.2.7 engine** — the round-139 native-vs-native
> shape (the baseline arm IS this repo's promoted config on 8001; the ours
> arm the same 18-patch stack — an A/A by design: the five instruments
> re-ground the decode rows on the promoted engine, the pair's delta IS
> the noise floor). Remaining levers after it: the 0110 KV-SHARD port
> (user-parked), the DRAFTS=0+LIVE_HALF four-window composition, the
> upstream watch (#2852/#2856 — no numbers yet). The stage brief rides the
> launch (round 141 cont. 44). (The earlier round-141 arc — the #2699
> recovery, the #2181 live-half knob, the #2257 watch, the #2744
> retirement, the #2793 ADOPTION (+6.1% c4, campaign-20261111-094017), the
> v1.2.7 rebase + promotion — sits in the round history below.)

> **The bar (user, 2026-10-23):** surpass production 0.6.6 on model loading time,
> generation tok/s, and prefill rate. This document is the continuing-look home for
> that hunt: the measured scoreboard, the fronts in attack order, every lever with its
> mechanism and verification plan, and the research log. The mandate (user): look hard,
> keep looking, go outside the scope if necessary — everything documented.

> **The bar re-targeted (the round-139 (user) directive): comparisons are
> NATIVE-vs-NATIVE** — production IS this repo's promoted native line now; the
> retired Python recipe's numbers are history and never cross-compare. The
> operative floor is the native-native pair (the anchors' duel rows).

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
  **TR3-4bpw Quality 94/100** (the served default, the (user) swap) ties the MIA pack
  and ties **production's current-bench anchor: Quality 94/100** (the prodbench receipt,
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
  `local/GLM-5.3-Flash-AZ-EXL3`, receipted Quality 90/100 in the 4bpw sweep). Sub-4bpw work
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
  module-global `top_k`, both patched in 017-topk4b.patch)**: routed 18.45 → 11.0 ms at
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
  qualified defaults serve top4cfg + 017-topk4b (round 27; the scoreboard regenerated:
  solo 108%, c2 103%, c4 78%, streaming ~189%, prefill 45%, loading 27%).
  **Experiment 2 (the AZ full checkpoint — the quality-safe upgrade to the same lever)**:
  the download is COMPLETE (the Xet CAS survived the reboot; 170 G materialized,
  topk=4, 288 experts, auto-round int4 — verified 2026-10-24). The route: requant
  auto-round int4 → EXL3 4bpw (the engine's format; try exllamav3's streaming convert
  first — it may dequant per-layer with no intermediate; else dequant→bf16 ~640 GB
  intermediate with the disk choreography, then quant, then delete the intermediate),
  serve with 017-topk4b (the reference is already topk=4), then the battery + the perf
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

## Retired sections

The front-3 history, the dated roadmap, the research log, the vision-qualification
record and the resolved front-2 A2 census moved to [docs/perf-history.md](perf-history.md)
— immutable once written; the living plan is this file's top.

