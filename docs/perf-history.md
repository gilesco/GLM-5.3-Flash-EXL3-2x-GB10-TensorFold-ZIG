# Perf history — the retired sections of the performance plan

<!-- ARCHIVED PERF HISTORY — immutable once written. The living plan is docs/PERF_PLAN.md. -->

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
   rebase 017-topk4b, run the §2 gates + the perf probes; adopt only receipts-equal-or-better.
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
  the 017-topk4b rebase). Also: NVIDIA's FP4-Local and XSFP4 checkpoint formats land in
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
differs, so our A/B decides. **Ported as `004-packed-s2.patch`**
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
our DFlash2 shape). **Hand-ported as `002-exl3prompt.patch`** (the
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
Renamed 007-attnfetch8.patch (the dsasel3 convention). The arm-off
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
on error/teardown). **Hand-ported as `009-moeside.patch`** — our
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
`013-zprompt.patch` (the eleventh; zp > zmoe-fuse). The fork's text
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

**THE EXL3P PORT QUALIFIED AND ADOPTED (round 137)**: the exl3pqual A/B
(campaign-20261107-200411) cleared it — the arms' content IDENTICAL (the
same 80cc3802… sha as every window), the §2 gates ALL PASS, **hardmode 95
(the ELEVENTH consecutive)**, the vision 4/4, and **THE PREFILL LEVER IS
REAL**: the bench pp d0 **1,495** (the ON arm; the last three windows read
1,458-1,468) and the duel_arm TTFT slope **0.458 → 0.447 (−2.4%)** agree
on ~2-2.5% whole-prefill — **the front moved 96.0% → 98.5%** (1,495 vs
production's 1,518). config.sh carries the eleventh patch; the prefill
anchor row re-paired and the chart re-rendered. Decode flat within the
arm spread (the solo 68.5-vs-66.8 spread is run-order drift — the OFF arm
the highest solo ever recorded, the ON arm inside history, the prompt
loop decode-inert; a watch item for the duel).

**THE NEXT STEP: the duel re-pair on the adopted 11-patch stack** —
production-for-testing + ours the same window re-dates every speed row
same-window on the exl3p engine (and settles the solo watch item).
THEN the prefill front's remaining 1.5%: 0080 (the packed prompt
linears' cp.async rework, 185 lines) is the follow-on candidate — check
its base against the fork's 0073 MmTwo concepts first; behind it the
PDL set and the HC-split set stay parked. The front may also cross on
the duel's own prefill reading if production's same-window prefill
drifts low — the duel receipt decides.

**THE EXL3P DUEL RE-PAIRED (round 137 cont. 2)**: the same-window pair
on the adopted 11-patch engine (campaign-20261107-211404) — solo
**68.2/68.3 vs 58.6/58.7 = 116.4%** (the A/B's solo watch item SETTLED:
the adopted engine reads at the top of its range); c2 **118.1 vs 86.4
at its floor = 136.7% there**; c4 **168.9 vs 188.2 at a warm-cache high
= 109.0% at its floor** (our best c4 again); ITL **14.7 vs 17.4 ms/token
= 118%**; overhead 185 vs 182 ms; the cold d8192 **3,845 ms, slope
0.447 = 445%**. The duel's own slope re-confirms the exl3p prefill
lever same-window. The anchors re-paired, the chart re-rendered.

**THE NEXT STEP: the prefill front's last 1.5%** (98.5%, 1,495 vs
1,518): **0080** (`0080-exl3p-0069-r6-glm-mm-prompt-loads-and-pairs.patch`,
185 lines — the packed prompt linears' cp.async loads and launch
pairing) is the follow-on candidate — its base may need the fork's 0073
MmTwo concepts checked first (the fork's series is a dependency web).
Scope it this sitting; if it stages cleanly (a small, self-contained
port), ship and launch its A/B next window; if it needs 0073's two-
problem machinery, park it behind a dependency decision and re-scope
(the PDL set and the HC-split set stay parked regardless).

**THE 0080 PORT STAGED (round 137 cont. 2)**: the dependency check came
back clean — 0080 does NOT need the fork's 0073 MmTwo machinery (only
its base signature carries 0073's xtile param; P2 does not use it). 11
of 12 hunks applied clean; the one rejected hunk (the mm_kernel template
line) hand-applied keeping v1.2.4's signature; the fork's text otherwise
verbatim (line-verified). The classic packed-prompt kernels kept as the
_128s2_cl twins behind **TF_GLM_MM_P2=0**; no contract-record work (the
_128s2 kernels are unlisted in our registry). Shipped as
`014-zs2.patch` (zs > zprompt). **THE NEXT STEP: the 0080qual A/B** —
both arms the same 12-patch image, the knob flips the path: content
identity, the bench pp rows (the prefill lever's primary read — the
fork measured the packed prompt linears 1.116-1.138x at GLM's prompt
shapes, which at their share of pp2048 is maybe +0.5-1.5% whole-prefill
— the front's remaining 1.5% could cross), hardmode's twelfth 95, the
§2 gates, the vision 4/4. At adoption: config.sh's twelfth patch, the
prefill row re-paired, the duel re-pair next window.

**THE 0080 PORT QUALIFIED AND ADOPTED — THE PREFILL FRONT CROSSED
(round 137 cont. 4)**: the 0080qual A/B (campaign-20261107-214342) —
the arms' content IDENTICAL (the same 80cc3802… sha as every window),
the §2 gates ALL PASS, **hardmode 95 (the TWELFTH consecutive)**, the
vision 4/4, and the bench pp d0 **1,519 vs production's 1,518 =
100.1%** (the chain 1,458 → 1,468 → 1,495 → 1,519; the TTFT slope
0.448 → 0.441 = −1.6% agrees). **The last uncrossed (user)-bar front
falls**: loading 112.9%, solo 116.4%, c2 136.7% of the floor, c4
109.0% at the floor, ITL 118%, cold 445%, and now prefill 100.1%.
config.sh carries the twelfth patch; the prefill anchor row re-paired
and the chart re-rendered.

**THE NEXT STEP: the duel re-pair on the adopted 12-patch stack** —
production-for-testing + ours the same window re-dates every speed row
same-window on the P2 engine (the prefill row's production side
re-pairs too). THEN the frontier re-scopes: every (user)-bar front is
crossed, so the plan's next levers are the parked candidates — the
fork's exl3r decode series (0081: the 4-bit grouped experts read every
trellis word once; 0082: the chain as dependent launches — decode-side,
the 0030 lesson says decode levers show at concurrency), the PDL set,
and the HC-split/overlap set (the +36%-at-50k class — a TP-exchange
rework for long prompts). Scope 0081 next sitting; the 0082 pair
needs the fork's dependent-launch concepts checked first.

**THE P2 DUEL RE-PAIRED (round 137 cont. 6)**: the same-window pair on
the adopted 12-patch engine (campaign-20261107-225124) — solo
**68.0/68.1 vs 58.5/58.6 = 116.2%**; c2 **118.6 vs 110.2 at its
top-of-range volley = 107.6%** (our best c2); c4 **168.9 vs 154.8 at
its floor = 109.1%** (our best c4, held three windows); ITL **14.7 vs
17.1 ms/token = 116%**; overhead 183 vs 185 ms; the cold d8192 **3,803
ms, slope 0.442 = 450% — the best yet**. The prefill row stands at the
0080qual reading (100.1% — the duel carries no bench rows; the duel's
own slope 0.442 re-confirms the prefill gains at depth). The anchors
re-paired, the chart re-rendered. EVERY (USER)-BAR FRONT IS CROSSED.

**THE NEXT STEP: scope the fork's exl3r decode series** — with the
prefill front crossed, the frontier moves to decode: 0081 (the 4-bit
grouped experts read every trellis word once + fewer decode
instructions, 221 lines) and 0082 (the chain as dependent launches,
250 lines — needs the fork's dependent-launch/PDL concepts checked
first). The decode concurrency cells (c2/c4) are where a decode kernel
lever shows (the 0030 lesson). Read 0081's header + test-apply next
sitting; if it stages cleanly, ship and launch its A/B; the PDL and
HC-split sets stay parked behind it.

**THE 0081 PORT STAGED (round 137 cont. 6)**: the exl3r read-once
trellis patch (0081) applied 3 of 4 hunks clean; the one rejected hunk
(the tilesFor choice line) hand-adapted to our single Layer.uniform_k2;
the fork's text otherwise line-verbatim (14/14 .cu, 97/97 .cuh, 12/12
.zig). The fork's own knob **TF_EXL3_SHFL=0** restores the old choice —
no _cl twins needed. New kernels k8r8s/k8r16s ride the existing
grouped_body_v2 template (no existing-kernel changes, no record work).
Shipped as `015-zshfl.patch` (zh > z2). **THE NEXT STEP: the
0081qual A/B** — both arms the same 13-patch image, the knob flips the
path: content identity, the duel_arm c2/c4 cells (the decode lever's
home — the fork measured the read-once loads to −14% at 16-32 rows),
hardmode's thirteenth 95, the §2 gates, the vision 4/4, the bench as
the regression watch (prefill flat expected — the read-once kernels
serve decode windows only). At adoption: config.sh's thirteenth patch,
the decode rows re-paired, the duel re-pair next window. 0082 (the
chain as dependent launches) stays behind it — needs the fork's
dependent-launch concepts checked first.

**THE 0081 PORT QUALIFIED AND ADOPTED (round 137 cont. 8)**: the
0081qual A/B (campaign-20261107-232039) — the arms' content IDENTICAL,
the §2 gates ALL PASS, **hardmode 95 (the THIRTEENTH consecutive)**,
the vision 4/4, prefill flat. **The fork's measured decode gain did
NOT transfer to our shape** — the c2/c4/ITL/solo cells read FLAT (the
first fork claim not to transfer; the L2-gather saving matters on
their cold-expert trains, not our hot hierarchy). ADOPTED anyway:
bit-safe, knobbed (TF_EXL3_SHFL=0), neutral everywhere, and the fork's
0082 builds on this exact base. config.sh carries the thirteenth patch.

**THE (USER) BENCH (2026-11-08)**: the user asked for a single
tool-eval bench run on the best candidate — parallel=4, hardmode, perf
on, needle find enabled — and a forum-ready model card. The run: the
adopted 13-patch stack on the testing port 8001,
`tool-eval-bench run --seed 42 --perf --needle --hardmode --parallel
4` (the README's own one-shot recipe). The card: MODEL_CARD.md at the
repo root, built from the standing receipts + this run, no site
identity (it gets posted publicly).

**THE NEXT STEP: the duel re-pair on the adopted 13-patch stack** —
launched after the (user) bench completes; every speed row re-pairs
same-window on the SHFL engine.

**THE SHFL DUEL RE-PAIRED + THE (USER) BENCH LANDED (round 137
cont. 10)**: the same-window pair on the adopted 13-patch engine
(campaign-20261108-010714) — solo **115.2%**, c2 **107.2% at its
top**, c4 **108.7% at its floor**, ITL **116%**, overhead **99.5%**,
cold **449%** — every row holds within noise (the SHFL adoption
decode-neutral on the duels too, as the A/B read). The (user)
model-card bench ran in the same campaign: **final 95/100**, needle
**80.0% (16/20), effective context ~174,762 tokens (estimated)**,
perf cells pp d0 1,511 / tg 56.5 solo. **MODEL_CARD.md is COMPLETE**
(postable). The anchors re-paired, the chart re-rendered.

**THE NEXT STEP: scope 0082** (the exl3r chain as dependent launches,
250 lines — rot_in, gate/up, epilogue, down as a dependent-launch
chain): it builds on 0081's read-once base (adopted ✓). Read its
header + test-apply next sitting; the PDL set's concepts (the chain
machinery) may already be in v1.2.4 (the engine's own PDL — glm_mm's
pdl launches) or may need the fork's 0069-0071 line first. The PDL
set and the HC-split set stay parked behind it.

**THE 0082 PORT STAGED (round 138)**: the exl3r dependent-launch chain
(0082, on the adopted 0081 base) applied 7 of 9 hunks clean; the 2
rejected .zig hunks hand-applied (the tilesFor pdl field on our single
uniform_k2 form; the chain insert after our act_mode check); the
fork's text otherwise line-verbatim (15/15 .cu, 43/43 .cuh, 17/17
.zig). The fork's own knob **TF_EXL3_PDL=0**. New kernels k8r8p/k8r16p
ride the existing template; rot_in/gateup_epilogue gain wait+trigger
(register-neutral per the fork's missing records patch — our cuobjdump
confirms). Shipped as `016-zstep.patch` (zt > zh). **THE NEXT STEP:
the 0082qual A/B** — both arms the same 14-patch image, the knob flips
the path: content identity (the fork's 108/108 exactness), the
duel_arm c2/c4 cells (the launch-overlap lever's home — the 0030
lesson says launch savings show at concurrency), hardmode's fourteenth
95, the §2 gates, the vision 4/4, the bench as the regression watch.
At adoption: config.sh's fourteenth patch, the decode rows re-paired,
the duel re-pair next window. Behind it: the PDL set (0069-0071 — the
engine's glm_mm already chains; the exl3r chain may make the wider PDL
line redundant), the HC-split set, and the fork's 0083+ tail.

**THE 0082 PORT QUALIFIED AND ADOPTED (round 138)**: the 0082qual A/B
(campaign-20261108-024926) — the arms' content IDENTICAL (the fork's
108/108 exactness confirmed on the real model), the §2 gates ALL PASS,
**hardmode 95 (the FOURTEENTH consecutive)**, the vision 4/4, prefill
flat (the bench pp d0 1,528, inside the band). **The fork's measured
chain gain did NOT transfer to our shape** (c2/c4/ITL/solo flat — the
launch-COUNT class of 0030 transferred at concurrency; the
launch-OVERLAP class doesn't — the second decode-side non-transfer).
ADOPTED anyway: bit-safe, knobbed (TF_EXL3_PDL=0), neutral everywhere,
and the fork's 0083+ builds on this exact base. config.sh carries the
fourteenth patch.

**THE NEXT STEP: the duel re-pair on the adopted 14-patch stack** —
every speed row re-pairs same-window on the zstep engine. THEN the
frontier: the fork's 0083+ tail (read its headers — what follows the
exl3r line), the PDL set (possibly redundant with the engine's own
glm_mm chaining + the zstep chain), and the HC-split set. The decode
side has now cost two non-transferring ports (0081, 0082) — both kept
for the base chain; the prefill side is crossed; the next REAL lever
may be the HC-split/overlap class (+36% at 50k) — scope it with fresh
eyes against our 2k bench shape before committing to a port.

**THE #256 PORT STAGED (round 138 cont. 7)**: from the forum thread's
finding (post 973): the unoffered-tool-call leak — the fix (upstream
be8bccbec, PR #415) is in v1.0.0-1.2.1, REVERTED before v1.2.2, so our
promoted v1.2.4 engine lacks it. The port turned out SMALL: the rest
of the #415 rework (parsedContent/kept/wholeEnvelope/prose_sent/the
attach rework) is already in our tree — only callName's own-name rule
was reverted with it. 2 files (+7/-2 + the test flip), no kernel
work. Shipped as `010-tools256.patch` (sorts before the z- kernel
patches alphabetically — it touches no kernel file, order-free).
**THE NEXT STEP: the tools256qual battery** — the §2 gates, hardmode's
sixteenth 95, the vision 4/4, the greedy content identity (the fix's
own unit test is the primary witness; the A/B arms exercise the knob-
free path — the patch has no env switch because the behavior IS the
fix).

**THE FORK TAIL SCOPED (round 139, the 0083-0108 read)**: 26 patches remain
beyond our 0082. The T3 glue set is the perf substance: 0086 (the hc
finish-split — warp 0 publishes, Sinkhorn runs beside the collapse; exact,
TF_GLM_HC_SPLIT) + 0089 (the hc partial-split — the decode dots over more
blocks, TF_GLM_HC_PART steps) are self-contained ports; 0088 (the batched
shared-window writes) rides the fork's 0070 batched shared windows, which we
do not carry — a two-patch port if wanted; 0090 (PDL waits) only matters
after the splits. Translated to our shape: ~-83 us (0086) + ~-64 us (0089) a
plain step ~ 1% of our ~15 ms decode step — at the edge of the ±2% band,
the same class as the two decode-side non-transfers (0081 L2-gather, 0082
launch-overlap): their claims were real on cold 4-bit trains, not our hot
serving hierarchy. The rest of the tail is server-side behavior (0092/0103/
0105/0107 — the #256 class), warm turns (0104), the prompt-cache set-aside
(0108), and DFlash2 tuning knobs (0094-0102) for the drafter line we don't
measure. **JUDGMENT: no fork-tail port is committed now** — the decode side
has cost two non-transferring ports; the HC-split set waits for a decode-
side instrument that resolves 1% (the duel re-pair first, then re-judge).
The server-side behavior ports (the #256 class) are cheap and safe — they
queue AFTER the perf frontier, not before it.

**UPDATE (round 139 cont. 9): the 0103 port is SHIPPED AND ADOPTED as
018-callquote** (the halt class's last shape; the battery campaign-20261108-
214221 — the seventeenth patch), and the round-139 cont. 7 scan re-set the
fork-tail dispositions (docs/ECOSYSTEM.md + docs/PORT_QUEUE.md): 0104
warm-turns is the next fork port (the agent-loop re-prefill — the 512K
workload's own front, not a decode-side micro-win), 0108 CACHE_FIRST +
0110 KV_SHARD the 512K-plan candidates; the HC-split set stays parked
per the judgment above; 0105/0107 stay watch. The **v1.2.5 bump is
receipted as the cheapest since the v1.2.2→v1.2.4 rebase** (one hunk
re-anchor in 003-fp8-pages; tool_parse and all our kernel files
byte-identical) — it queues BEFORE the fork ports (the bump takes 0104
onto the newer base afterward).

**THE NEXT STEP (re-set, round 139 cont. 9): the duel re-pair on the
adopted 17-patch stack with the steps0 serving default** — every speed row
re-pairs same-window (the seventeenth is perf-neutral server work; steps0
moved the DEPTH-DECODE row materially: d8192 c2 48.2/37.0 vs the 17.3
floor — the anchors carry it). The re-pair re-dates the chart on the
adopted state and re-grounds the duel instrument before the 512K ladder
resumes.

