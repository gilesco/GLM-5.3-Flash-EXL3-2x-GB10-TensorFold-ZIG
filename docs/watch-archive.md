# Ecosystem watch archive — dated release reviews and community sweeps

<!-- ARCHIVED WATCH HISTORY — immutable once written. Do not append here. -->
<!-- The living watch state (field at a glance, the tiers, the watch list) is docs/ECOSYSTEM.md. -->

## Upstream v1.2.4 review (the (user) ask, 2026-11-07) — HISTORICAL: our pin then was v1.2.3 (6ec5fa4cb); it is v1.2.7 now (the v1.2.7 rebase is in flight this sitting; the round-140 entry is in docs/log/2026-W45.md)

v1.2.4 shipped (267c5af6a, 675 commits after v1.2.3). The GLM-CUDA/GB10
read of the changelog:

- **THE LEVER — direct reads past the page cache (#2282, #1901)**:
  `checkpoint_direct.zig` + `direct_gather.zig` — a layer's tensors read
  with direct_gather into an arena, layer i+1 read on a thread while
  layer i packs; `TF_LOAD_DIRECT=0` keeps the old read-ahead. **Claimed:
  Gemma 4 / Qwen 3.5 CUDA cold loads 28-31% faster on a GB10; Flash
  Next's O_DIRECT experts dropped a GB10 cold start 74 s → 48 s.** Wired
  for Gemma 4 and Qwen 3.5 only — GLM is NOT wired (the opt-in lives in
  the family's cuda_weights.zig; the pattern is small). **The loading
  wall is our last uncrossed front (91%: 103 vs 93.7 s) — wiring GLM
  onto this is the front's lever.**
- **GB10 integrated-GPU D2H staging (#2289)**: every other synchronous
  device-to-host copy stages through the shared pinned buffer; discrete
  cards keep the direct copy. Could shave the per-step sync reads (the
  greedy pick's DtoH) on our GB10s.
- **GLM CUDA TP=2+ startup naming (#2354)**: each rank names its phases
  (NCCL init, peer warm-up, weights, calibration, ready) and warns once
  a minute while init stalls. Observability only — transfers unchanged.
- **Strict TF_-setting validation (#2405)**: a MALFORMED TF_/TENSORFOLD_
  setting stops the native server at startup with its name and forms,
  before any checkpoint work. Our patches' knobs (TF_GLM_KV_SHARE,
  TF_GLM_ABSORB_MMA, ...) are read via getenv inside the patched code —
  outside core's registry — so the rebase validation must confirm the
  bare 8-patch config boots under the strict check.
- The kernel-contract nvcc records refresh (#2390): no kernel changes.
- The rest: Qwen 3.5 BF16 decisions, Gemma 4, Flash Next KV-pages
  (#2244) and in-pass prompt-cache marks (#1866 — 19% sooner first
  token on a GB10, the FLASHNEXT family, not GLM), HIP/RDNA fixes,
  MCDMA bring-up 2a, docs/tests. Nothing else on our fronts.

**The rebase drift map (the 8-patch stack vs v1.2.4, measured
2026-11-07)**: packed-s2 and exl3prompt APPLY CLEAN; 30 failed hunks —
absorb-mma 8 (cuda_engine.zig:182, cuda_forward.zig:195,
cuda_ranks.zig:166 — v1.2.4's GLM engine changes), fp8-pages 12 (the
build files, the snapshot host, the contract registry), pagerows-fix 2
+ selist-fix 2 (cuda_dsa_block.zig — v1.2.4 touched the DSA block),
attnfetch8 2 (glm_glue_attn.cuh:73), moeside 4 (cascades from
absorb-mma + the engine changes). A sitting's re-anchoring, then the
validation battery.

**The plan**: rebase the 8-patch stack onto v1.2.4 (the re-anchoring is
the next sitting's opener), wire GLM's weights loader onto
checkpoint_direct following the gemma4/qwen3_5 pattern (a small patch —
008-loaddirect), then ONE validation window covers both (the gates +
the smoke + the loading wall's re-take on the direct reads). The
loading front could cross.

**LANDED (round 135, 2026-11-07)**: the rebase + the wiring are done and
triple-verified — the 9-commit `v124-rebase` branch (the head's
/tmp/tf-src): fresh-v1.2.4 + the commit bodies byte-identical (0 diff
lines), fresh-v1.2.4 + the SHIPPED patch files in alphabetical order
byte-identical (0 diff lines), the full compile (fatbins + native,
nvcc sm_121, zig 0.17.0) RC=0 in the builder base image. The re-anchoring
turned out LIGHTER than the bare-tree drift map: five of eight apply
verbatim once the stack sits beneath them (the bare-tree failures were
anchor shifts the stack re-aligns); absorb-mma, fp8-pages and moeside
were hand-re-anchored (the Fingerprint at layout 20, the snapshot tests
after v1.2.4's KV_SHARE adapter test, the side field around pair/l2pf).
008-loaddirect is written (cuda_load_ahead.zig; TF_LOAD_DIRECT=0 keeps
#1928's read-ahead; 23 shards < max_sources 64 so the path engages on our
checkpoint). The pin is bumped; the v124val window covers it.

**THE RENAME v1.2.4 SPRUNG (the first v124val window burned on it,
campaign-20261107-123013)**: upstream MAINLINED the KV-share-over-pages
as core's `TF_KV_SHARE` (kv_prompts.zig — "what a family on the core
pool calls of one prompt store over its pages") and REFUSES the old
TF_GLM_KV_SHARE at startup (#2405's strict validation, before any
checkpoint work). The GLM family is rewired onto the core store in
vanilla v1.2.4 (our patch's share hunks re-anchored around it). The
floor moved: TF_KV_SHARE ≥ 4×PARALLEL ("4 states a GLM stream",
fewStates in cuda_native.zig) — the adopted 8 at PARALLEL=4 refuses;
config.sh now exports TF_KV_SHARE=16. All other exported knobs swept
and intact. UPSTREAM-FIRST NOTE: with the store native, the fp8-pages
marriage's GLM KV-share hunks may be subsumed — a follow-up sitting
judges whether the patch slims to the fp8-paging core (the §2 gates on
the native store decide).

**THE RESHARD (round 135, cont. 4)**: the third v124val run qualified
the rebase end to end (the gates, hardmode 95 — the eighth consecutive,
the vision 4/4, flat decode/pp) but the direct reads STILL never
engaged: the served TR3-4bpw pack has **120 safetensors files (all
holding model.language_model.* tensors) > checkpoint.direct's
max_sources 64** — the gather's fd budget (64 sources × 16 readers ≈
the 1024 soft limit) keeps the path off by design. THE FIX: a
byte-identical reshard to 55 × ~3 GiB shards
(`models--local--GLM-5.3-Flash-TR3-4bpw-reshard`, the tool verified the
name set, every tensor's length, the total volume, and sha256 of 24
sampled tensors before success; SERVED_NAME unchanged). The loading
wall's re-take on the resharded pack is the next window's opener.

## Community sweep — the NVIDIA GB10 GLM-5.3-Flash thread + DeepSeek field (2026-10-29, round 73)

Source: forums.developer.nvidia.com/t/381350 (936 posts; the user is giles8 in-thread),
plus the DeepSeek-on-Sparks field. The findings, ranked by leverage:

1. **The effort-line template bug — a measured quality lever** (posts 915/933): the
   stock, MiaAI and technigma templates put the "Reasoning Effort" hint at the TOP of
   the prompt; on long sessions the model ignores it (max ≈ high; measured 11–528
   reasoning tokens at 84K history vs 1,900–7,000 with the line moved to just before
   the final assistant turn — "effort_tail"). Second effect: with the line at the top,
   every effort switch invalidates the whole prefix cache. A second, distinct template
   gap: reasoning collapse right after TOOL RESULTS at long context (technigma's
   TOOL_REASONING_VALIDATION.md documents + fixes it with a reminder). OUR LINE FAILS
   TC-51 AND TC-92 DETERMINISTICALLY — on both the Focus and the AZ runs (verified in
   our receipts) — while technigma's stack is clean on both (full 97). Tenant-isolation
   failures are plausibly the same tool-result/template family. This is a stack-level,
   +2-3-point quality lever that no checkpoint change touches.
2. **Do we wait for TensorFold updates? Yes — with a named watch list** (post 926,
   bernisse's peer review of this line): upstream 1.1.4+ carries #1163+#1211 (GLM CUDA
   KV pages from the core pool; #1163 mergeable-clean), #1218 (a 1-line ring-slot leak
   fix — concurrent-cold serving fails at the 64th request without it), #1168
   (tensor-core fp8 decode attention, 1.5–2.3x on qwen) and #1176 (int8 prompt
   matmuls, −20–27% prefill) — the last two attack our exact decode/prefill gaps if
   they generalize to GLM's DSA rows. Caveat bernisse confirms independently: fp8 KV ×
   TF_KV_PAGES are mutually exclusive today (bf16-only) — our round-59 finding. Check
   which of these our v1.1.8 base already carries before any window.
3. **The router-pathology fix is the field's highest-leverage kernel work** (bernisse:
   "would put native ahead of both stacks" — the user's own diagnosis implies slope
   0.662 → ~0.25 ms/tok). bernisse's cross-quant bake-off on a second 2x GB10 pair:
   the fork (0.6.6+106) beats native 1.1.x today — code decode 91.6 vs 62.3 t/s, 4x
   concurrent 639 vs 217, prefill 64k 2,483 vs 1,448 (technigma NVFP4: 2,933) — the
   router fix is what flips native ahead of both.
4. **DeepSeek 4.1 / V4-Flash on this hardware** (the user's "deepeek results"):
   DeepSeek-V4.1-Flash-1017 runs ON TensorFold's python engine at EXL3 2.9bpw —
   ajvazan's field table: tool-eval 93/93 (high/max), depth 211/212, 2.1–2.3x the
   vLLM kit. The field's quality table: technigma native 92/**96** (max — the field
   best), kindlingai 92/95.67, the user's fork (G644a) 91/92 with the FIELD-BEST
   285 pts/hr, DSV4-0731-vLLM 89.67/89. Structural caveat ajvazan verified: this TF
   build does not implement V4.1's numeric effort budget (high == max structurally) —
   GLM vs DSv4.1 rows must not be compared on effort semantics. V4-Flash-0731 on the
   vLLM kit: 10B+ production tokens, stable at a 2200 MHz clock ceiling, 2.53M-token
   KV, DSpark K=5. ds4/dspark: V4 Flash Q2/MXFP4 on 2 Sparks at 41.7–83.3 t/s with
   DSpark (code ≈ 2x prose). Field Signal's methodology caution: the 114–141 t/s
   headline numbers are count-to-200 drafts; real 1,024-token work runs ~47–54 (GLM)
   vs ~54–98 (DeepSeek) — DeepSeek wins single-stream rows, GLM wins 4-concurrent.
5. **Portable serving ideas** (DGPP engine's changelog, several cover GLM):
   vocabulary-output memory retains only generation rows (3.79 GiB → 7.58 MiB);
   attention workspace follows the per-request context limit (−4.49 GiB); concurrent
   prompts share a forward pass; short requests no longer evict long-conversation
   snapshots below a 1,024-token threshold. OllieO's long-running production settings
   on our fork (post 932, since Oct 9): TENSORFOLD_RANDOM_SEEDS=1 (fresh seed per
   unseeded request), TF_GLM_KEEP_EFFORT=1 (fork patch 1002: thinking-off prompts
   keep the effort line for same-prefix cache hits), TF_GLM_CACHE_ENTRIES=48,
   PARALLEL=8, MAX_TOKENS=65536, SPILL_GIB=64.
6. **Methodology cautions from the field**: a one-line template change (a thinking
   reminder after tool results) moved median turn time 3.4 → 4.5 s with engine speed
   unchanged — never compare medians across weeks, fixed probes only (bernisse). The
   high→max score inversion (94 high / 91 max) reproduces across stacks — it is model
   behavior, not stack artifact (rle, post 934, both TF EXL3 and eugr W4A16).

Actionable for this line, in order: (a) the effort-tail + tool-result template fixes
against TC-51/TC-92 on our line — the only known +2-3-point lever that is pure stack;
(b) check the v1.1.8 base for #1163/#1211/#1218/#1168/#1176 before the next perf
window; (c) the router-pathology fix remains ours to land; (d) the fork's settings
(RANDOM_SEEDS/KEEP_EFFORT/CACHE_ENTRIES) are worth an A/B on the standing config.

## Upstream v1.1.9 review (round 83, 2026-10-29) — our pin is v1.1.8 (812fb040)

Tag-to-tag diff audited (v1.1.8...v1.1.9: 50 commits, 256 files, zig/src + zig/kernels
concentrated). **What 1.1.9 gives this line** — three GLM-5.3-Flash CUDA items, all
bit-exact ("same picks in the same order" / "replies are the same tokens"), all
authored by @Bizuayeu (the fork owner from our watch list — the community is
maintaining our exact topology upstream):

1. **#1404 — DSA indexer split across ranks (TP≥2)**: from position 2048 each rank
   scores/picks pools for its share of a prompt chunk's rows, all-gather shares the
   picks; `TF_GLM_INDEX_SPLIT` tunes/disables. Measured **1–2% prefill at 128k on
   2×GB10 TP=2** — our exact topology, but noise-level against the Front 2 A2 prize.
2. **#1424 — DSA select decode widening**: 1,024-thread blocks at long positions over
   4,096-pool buckets, ≤48 rows. +1.8% decode after a 136k prompt at TP=3; **flat at
   TP=2/65k**. Our 512k×4 window sits inside the covered range; expect small-positive.
3. **#1352 — `TENSORFOLD_PREFILL_SHARE`**: a GLM prompt step ends on the GPU before
   returning when decoding streams are billed for it (timing, not tokens). A fairness
   lever for PARALLEL=4 decode-under-long-prefill; opt-in below 1.

**What 1.1.9 does NOT give us**: no router-GEMM work (the Front 2 A2 pathology
remains ours — `cuda_mm.zig`/`weights.zig` untouched; the Kolibri #1460 routed-expert
weight-copy fix is that family's kernels, the same CLASS of L2 pathology but not our
code path); **no fp8×KV-pages marriage** (the ledger watch stays open); no GLM
vision/template/effort changes (the effort-tail adoption is untouched); the expert-kernel
item (#1351) explicitly compiles GLM's kernels to the same code as before.

**Verdict**: a hold-and-fold-in, not a priority. ~1–2% prefill + 0–2% decode does not
justify a dedicated re-qualification window (the fingerprint moves, so §2 gates +
depth + hardmode re-verify). **The efficient path: base the router A2 patch on
v1.1.9** — A2 already forces an image rebuild and a full re-qualification, so one
window adopts both; if A2 slips, take 1.1.9 as a cheap standalone fold-in later.

## Community performance sweep (round 88, 2026-10-29) — the MiaAI-Lab fork's patch table

Upstream main has moved past v1.1.9 (36470cec vs the 465e48b6 tag) — untagged GLM work to
scan before the next pin decision. The big find: **MiaAI-Lab/GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold**
— our exact model on 2 Sparks (TP=2), 1,940–1,980 tok/s prefill at 8k–32k (1,641 at 262k;
our slope 0.659 ms/tok ≈ 1,517 tok/s), carrying a measured patch stack. Ranked for this line:

1. **The HC-split/overlap set** (`0010-glm-hc-split`, `0033-glm-prefill-overlap2`,
   `0017/0022-overlap-priority`, `0064-glm-split-connect-early`): hyper-connection glue
   split by rows between the ranks, exchanges overlapped with the next rows' work —
   **50k prefill ~1,270 → ~1,730 tok/s (+36%); decode pays ~1.5%**. TP=2-native, our
   topology, and the same fix CLASS as our 1100 ms mystery (bubbles/serialization →
   overlap is what works). The biggest prefill lever found anywhere.
2. **`0086-glm-prompt-scores-loop`** (BadAd84): the DSA indexer's prompt scoring takes one
   row + 32 pool blocks per program instead of reloading each row's queries per 64-pool
   block — **scoring 36% faster; cold prefill at 226k 138.3 → 126.6 s; the same bits**.
   Bit-exact long-context prefill — directly our slope, adjacent to the section our prof
   shows but does not itemize.
3. **The KDA chunked set** (`0012/0014/0039`): the linear-attention layers' prompt chunks
   in chunked WY form, one kernel — **50k prefill 29.3 → 26.4 s; 149k 91.1 → 84.5 s**.
4. Carried already on our side: dense fp8/q4 (we serve dense4fp8), lean prompt scratch.

Also: serapis (upstream) invites PRs on the forum thread ("I'll happily consider it"); the
fork's `FILL_BUDGET_MS`/`FILL_DRAFTS`/`STREAM_SMOOTH` decode-gap tuning table (gap p50
630 → 81 ms with budget 200 + drafts) is the lane-host fairness knob our PARALLEL=4 ITL
p95 could reuse.

**Actionable, in order**: (a) scan upstream main 465e48b6..36470cec for these graduating
(the credit style suggests they do); (b) if absent, port 0086 first (bit-exact, smallest
diff, our exact pathology neighborhood) and A/B it same-session; (c) the HC-split set is
the +36% prize but multi-patch — port behind a window with the full battery; (d) the ncu
capture rerun stands — the overlap findings strengthen the bubbles hypothesis.

**Addendum (round 136, 2026-11-07)**: the fork's engine-series 0030 (a decode window's
MoE glue fused + one-width EXL3 decode tiles + KDA's f_b/g_b pair launch) is PORTED AND
ADOPTED here as `012-zmoe-fuse.patch` (the tenth patch): the A/B content identical to
the byte, hardmode 95 (the tenth consecutive), c4 +4.2% (our best c4, 166.1 t/s), solo
flat, prefill flat by design (campaign-20261107-172250). The fork's decode-side launch
savings transfer; its prefill-class levers (the 0009+0033 packed-prompt/pair-launch line)
remain the untriaged tail.

**Addendum (round 137, 2026-11-07)**: the fork's exl3p pair 0078+0079 (the prompt
experts' main loop reworked — 8-member column blocks, the next k tile decoded among the
current MMAs, per-item cp.async, mcg2/decode_a8/fwht128f, vector stores) is PORTED AND
ADOPTED here as `013-zprompt.patch` (the eleventh patch): the A/B content identical to
the byte, hardmode 95 (the eleventh consecutive), **the prefill front 96.0% → 98.5%**
(the bench pp d0 1,495; the TTFT slope −2.4% — the fork's kernel claims, gu 1.177× /
down 1.161×, transfer to our whole-prefill at ~2-2.5%), decode flat
(campaign-20261107-200411). The fork's measured kernel claims transfer — two for two
after 0030. 0080 (the packed prompt linears' cp.async) is the next candidate from its
tail; the HC-split/overlap set stays parked behind it.

**Addendum (round 137 cont. 4, 2026-11-07)**: the fork's 0080 (the packed prompt GEMMs'
loads fixed once a block + 8-bit codes to bf16 pairs in fewer steps — mm_kernel's P2 +
bpairs8_fast) is PORTED AND ADOPTED here as `014-zs2.patch` (the twelfth patch): the
A/B content identical to the byte, hardmode 95 (the twelfth consecutive), **the prefill
front CROSSED at 100.1%** (bench pp d0 1,519 vs production's 1,518; the TTFT slope −1.6%
agrees — the fork's 1.116-1.138× claim at GLM's prompt shapes transfers as ~+1.6%
whole-prefill), decode flat (campaign-20261107-214342). **The last uncrossed (user)-bar
front falls — the fork's measured claims have transferred three for three** (0030, 0078+0079,
0080). Its untriaged tail is now the exl3r decode series (0081 read-once trellis, 0082
dependent-launch chain) — the next candidates to scope; the HC-split/overlap set stays
parked behind them.

## Round 94 research addendum (2026-10-30)

- Upstream 465e48b6..cefb72fd: Nemotron CUDA (#548), Qwen3.8-27B pair-seam kernels (#1432),
  and a new CORE primitive — the row-split pair seam (e06a6eef, "split simd_qmm over K"):
  row-splitting between ranks as core infrastructure. When the HC-split/overlap set
  graduates, expect it to land through this primitive — re-check the seam's GLM coverage
  before porting hand-rolled fork patches.
- Fork newest (10-25): v0.6.0 published image pinned at 123 patches; +0128 (spill tier in
  blocks shared by later turns), +0129 (KV sharding — per-conversation latent cache on the
  owner Spark). Serving-memory, not prefill; relevant to long multi-agent sessions.
- Forum thread (384789, through Oct 13): the engine's deterministic high-context looping
  pathology (long-form generation repeats a paragraph; identical payload fails identically;
  7 restarts/hours vs the EXL3-vLLM engine's one loop in 22+ h). Watch upstream for a fix
  before trusting long-form receipts at depth. tool-eval-bench TF support is upstream
  (PR #190); the community hardmode protocol matches ours. jordanm82's recipe transplants
  o_proj ("dealign", layers 15-44) with latent FP8 — untested pattern.
- **Engine-lineage correction (round 99)**: the MiaAI-Lab fork's ENTIRE patch stack
  (0010/0033/0086/0064/0128/0129 — all `.py`: comm/decode/forward/hcsplit/engine/sparse)
  targets TensorFold's PYTHON/Triton engine. Our testing line is the NATIVE CUDA engine
  (tf_glm_* kernels) — the fork's patches do not port. Their +36%/0086 numbers describe
  the python engine's ceiling for this model on 2×Sparks, not ours. Upstream's row-split
  pair seam (e06a6eef, native-core: pair_stage/pair_gather/pair_argmax/pair_pick) is the
  native-shape overlap mechanism to watch for GLM adoption.

## Round 111: the next-release scan (upstream main cefb72fd..a0d2489, no tag yet — the "Unreleased" section accumulates)

- **GLM CUDA `--mtp-confidence`** (#1585): each MTP draft carries its chance; chains stop
  under the floor. Decode +4.9% at TP=3, +6.5% greedy solo — **but TP=2 code-heavy 3.7%
  SLOWER** (our serving profile). Off by default; without the flag every path is main's
  and `tf_glm_top1` compiles identically. GLM lanes follow: sampled streams draft their
  rates' depth under a floor.
- **The launch-batching pattern arrives model by model**: Qwen3.5/FlashNext batch a shared
  round's streams — "MTP attention over many rings in one launch" + sampled streams in
  the batched head pass. This is the SAME fix class our round-98-101 diagnosis calls for
  (fewer, bigger launches), landing per-model. GLM's turn has not come.
- **The pair seam**: step 1 is Metal (#1432, two Macs, 27B) — "nothing serves through it
  yet"; CUDA/GLM steps pending.
- Also in Unreleased: LFM2 taps for external drafters (#1390), the DFlash2 context-copy
  threshold (#1477, +12.8-18.5% decode after long prompts on the dense 27B), Nemotron's
  shared-kernel consolidation (#1353/#548), HIP RDNA4 routed-plan tuning (#1607), and a
  PR review exchange process (a0d2489).
- **GLM-path activity**: glm_glue_rows.cuh / cuda_lanes / cuda_mtp_chance / engine_pick —
  the family is actively maintained (the round-85 premise holds), all decode-side; no
  prefill/enqueue-efficiency work for GLM yet.
- The fork: no new commits since 10-25.
- **The line's decision**: the pin stays at the default (v1.1.9) — no Unreleased item
  moves our prefill/concurrency deficit; `--mtp-confidence` is off-by-default and
  TP=2-code-heavy-adverse. The next pin bump waits for: GLM's pair-seam CUDA steps, the
  batched-launch pattern reaching GLM, or a v1.2.0 tag with a compelling GLM changelog.
- **Our native fusion patch proceeds regardless** — the recon scoped it: the GLM family's
  launch path is `cuda_engine.zig: prefillChunk` → `cuda_forward_pieces.zig` (114 lines of
  piece descriptors) → shared core launch helpers; the per-layer micro-kernel census
  (router/slice/glue) lives behind that abstraction. The deep trace is the next sitting.

## Round 124: the watch scan (+43 commits since a0d2489 — DeepSeek-V4.1's CUDA bring-up)

- The cluster: DeepSeek-V4.1 on CUDA (experimental — the pack identity, the bounded
  64 MiB pinned upload stages, the EXL3-sibling rank planning, the CPU asset tools),
  the media URL deadline fix (#1645), DFlash2 reading a dense EXL3 head over its two
  spans (#1507), the Qwen27/Metal tile work, the mtp-confidence cluster (scanned
  round 111). **No GLM prefill/concurrency movement; no new tag** (v1.1.9 stands).
- The DeepSeek upload-stage pattern (one reusable 64 MiB pinned stage instead of a
  whole-image host copy) is a LOADING-TIME pattern — our loading anchor (230 s vs
  production's 93.7 s, 41%) could borrow it IF upstream generalizes the staging
  beyond DeepSeek. A watch item, not a lever today.
- **The pin stays at v1.1.9.** The bump conditions stand: GLM's pair-seam CUDA
  steps, the batched-launch pattern reaching GLM, or a v1.2.0 tag with a compelling
  GLM changelog.

## Round 127: the watch scan (+129 commits since a0d2489 — the GLM CUDA loading cluster) AND THE PIN BUMP

- **#1636 merged (the cluster: 61bb392ee → ab366b1e3 → a72b9d00f → 9e7dddd50 →
  af2909ce6): GLM on CUDA loads faster — 8 threads decode and pack each layer's
  routed experts (TF_GLM_LOAD_PACK, 1-16), the packed experts go up a piece at a
  time (≤192 MiB) from PINNED memory MAPPED into the device and copied up by the
  GPU, and 16 readers (cuda_load_ahead.zig, NEW — not in v1.1.9) read each
  layer's tensors into the page cache ahead of the loader. Measured: GLM-5.3-Flash
  XSFP4 155 → 51 s on two GB10s (TP=2), 124 → 46 s on three; the same replies,
  memory free within ~1 GiB.**
- **The coverage read against our EXL3 Focus** (the commits' diffs): the 8-thread
  pack and the piecewise pinned upload serve the DECODED formats (XSFP4/NVFP4 —
  zero exl3/trellis references); the EXL3 trellises still upload as-is. The
  EXL3-relevant part is the **16-reader load-ahead** — it fills the page cache
  ahead of the loader, turning our measured ~840 MiB/s major-fault reads into
  warm minor faults. That is our ~76-90-s residual's exact lever.
- **Our own loading patches are superseded**: glm-pinned-upload (the copy-through
  stage) and glm-trellis-scratch (the whole-tensor scratch) overlap what #1636
  built properly — upstream-first rule (patches/README rule 1): dropped at the
  bump. Their receipts (−21.8 s, −6.2 s, both bit-safe) stay as the record and
  the evidence that the loader's staging was pageable.
- **Also merged since Oct 29**: #1659 (prompt_radix: the lookahead + planned grid
  "so a family like GLM's can share the store" — the marks-patch territory;
  inert until a family opts in), #1534 (the EXL3 trellis reads through
  ld.global.nc.L1::no_allocate — decode-side), #1585 (--mtp-confidence),
  #1524 (TF_GLM_ROCE_MULTI for 3+ ranks — we are 2), #1327 (--decode-share).
- **The open GLM PR queue (35)**: #1576 (prompt chunks of 4,096 rows — our parked
  finer-grid lever, upstream is trying it), #1580 (TF_GLM_L2PF: the decode
  window's next weights into L2 on a side stream — the "L2 prefetch" lever),
  #1505 (the EXL3 grouped-experts kernel loads a tile ahead — decode), #1732
  (TF_GLM_KV_SHARE keeps prompts as prompt_radix pages), #1423, #1577, #1623,
  #1411. No open GLM-loading issues.
- **THE PIN BUMP (user policy: bumps only for measured glm/cuda perf)**: the pin
  moved from latest-v1 (v1.1.9) to TF_COMMIT=d80e5f2ef (the upstream tip) in
  scripts/local.sh. The qualification window (preflight resumecost summary, NO
  patches — pristine upstream) runs on the bumped tree; the content gate binds
  bit-safety across the bump; the restart wall is the loading metric.

- **Round 128 pulse**: **#1736 opened — `TF_GLM_HOST_CACHE` keeps kept prompt states
  in pinned host memory** — the cache-front pattern arriving upstream (pinned pages
  don't crowd MemAvailable the way the load-ahead's did). A watch item for the
  concurrent-resume serialization (round 123's 4× finding) and the prompt-cache
  fronts; not in v1.2.0.

- **Round 131 pulse (2026-11-01)**: the prompt front moves upstream — **#1792**
  (Flash Next on CUDA: faster prompt kernels, every reply byte unchanged, at one
  GPU and --tp 2; targets from a two-GB10 phase-by-phase 4.2k-prefill comparison;
  `TF_FLASHNEXT_PROFILE=2` times a pass's phases by CUDA events — an instrument to
  watch) and **#1783** (GB10 affine-4 projections reading the same input run as one
  grouped launch, byte-equal, 18/18 gates — a port candidate for our decode, +3.5-5%
  on Qwen/Nemotron served cells), plus **#1784** (the dense layers split across two
  ranks with exact rank sums). **The KV_SHARE paged store landed on main** (commits
  40c03bf/004655c, PR #1755 open — a prompt_radix store over a paged family's core
  pool): our TF_GLM_KV_SHARE lever stays **PARKED** — `error.Fp8OnPages` still
  refuses fp8 KV with pages on the tip, and the bf16-paged route costs a stream at
  524K. **Our ncudepth finding, as upstream data**: on our EXL3/TP=2/524K cell the
  cold-prefill slope is ~65% HOST GAPS (the ncudepth census, round 131) — the
  per-chunk host span work, not kernels; #1792 optimizes the device side of prompt
  passes, the host side looks untouched — a candidate engine lever (less host span
  work per chunk, or graph-captured prompt passes) for whoever picks up the GLM
  prefill front.

- **The round-131 warm-resume finding, as upstream data**: the native CUDA
  engine's warm resume (a cache hit on an identical prompt) REPLAYS the tail
  chunk — the prompt cache's states are page-quantized (512-token pages,
  2048-aligned keep marks), so no state at the prompt's exact length exists
  and every full hit re-runs the last chunk's GEMMs (measured: 1.42 s warm vs
  5.5 s cold at d8192; the ncuwarm capture shows the pass's kernels re-run).
  A full-hit skip (production's 0.6.x reads 0.21 s on repeats — its cache
  skips the pass entirely) requires exact-match states beside the page-
  quantized tree: a node's guaranteed-match extent is its pages, so an
  exact-length snapshot is only safe for the identical prompt and needs
  exact-match nodes (or a hash-keyed side cache) in the radix core. The
  cheap partial — relaxing the resume alignment to the 512-row page — was
  priced and declined on this line (round 119: the prefill anchor −28%).
  For whoever picks up the GLM warm-resume front: the skip is a radix-core
  design change, not a patch.

- **Round 131 pulse, evening (the tip at ed28582)**: **#1842** — the chunk-4096
  lever arrives as `TF_GLM_CHUNK_SOLO` WITH its drafter refusal (1.6-1.9 GiB of
  prompt buffers no pass uses beside --drafter): our p4096 falsification stands
  and our cell drafts, so the knob is doubly not-ours. **#1833** — KV_SHARE
  gains image-turn keep/resume (the pool cache keys by image content; one
  screenshot no longer forces full reprefills): real serving value for KV_SHARE
  users, our lever still parked on fp8 × pages. **#1824** (qwen3_5 cuda) — kept
  DeltaNet rows replay in the next slot scan instead of a full-state keep: the
  replay-vs-keep trade surfacing on another family, adjacent to our warm-resume
  finding. Merged: Living Weights (#1807) and kernel-contract test-infra — no
  serving-perf movement for our fronts.

- **Round 131 pulse, evening II — the NVIDIA GB10 forum (scoped per (user),
  round 131: this line watches TensorFold + GLM-5.3-Flash ideas only — other
  engines and other model families are out of scope)**: one transferable idea
  surfaced — a peer's TensorFold-on-GB10 line runs DeepSeek-V4.1 at **EXL3
  2.9bpw at 1M context**, which makes **a sub-4bpw serve** concrete for
  OUR checkpoint: the staged pipeline (az-window.sh) exists, the quality bar is
  hardmode (user), and the payoff is device memory — the admission headroom the
  chunk-buffer and stream fights need. That is PERF_PLAN Front 1's
  checkpoint-rev lever with a concrete shape. (Out of scope, not tracked: other
  engines on GB10, other families' serving threads.)

## 2026-11-04 — Mia's 1104 recipe: a native-engine cousin for our exact hardware (the fold-in analysis)

**The find**: [MiaAI-Lab/GLM-5.3-Flash-DGX-Sparks-1104](https://github.com/MiaAI-Lab/GLM-5.3-Flash-DGX-Sparks-1104)
(Apache-2.0, released 2026-11-04) — a **brand-new native-engine recipe for
2× GB10**: `tensorfold-native` at their own pin `f350cd3e` (a 1.1.9-era base)
plus **105 patches** (93 from their RTX PRO 6000 recipe + 12 GB10-specific),
DFlash2 4-bit, `PARALLEL=8`, `CONTEXT=1048576`, **fp8 KV ON SHARED PAGES**
(4,098 pages, 2.1M tokens), `DENSE=q8`, `HEAD=q8`, `ABSORB_MMA=1`. It ships a
full measurement campaign (`docs/speed/RESULTS.md` — the traps and
retractions left in). Not comparable head-to-head: their engine base is older
(1.1.9 + patches vs our v1.2.2 upstream) and their harness differs (the
client on a third Spark, fixed prompts, greedy).

**The cross-stack numbers, caveated**: their decode (greedy prose ~37-38
solo, 68-70 at 4 fixed streams) is far behind ours (63-64 solo, 149 c4
aggregate) — our v1.2.2 base decodes ~65% faster. **Their prefill wins:
1,735-1,812 tok/s FLAT to 256K vs our ~1,030-1,274 declining** — the patch
stack's prefill work is the gap.

**The fold-in list, ranked**:
1. **ABSORB_MMA — DISPOSITIONED (cont. 16/20): ADOPTED ALONE.** Ported (0041,
   all 17 hunks re-anchored onto v1.2.2; the diffstat identical to the
   original) and measured: **the deep fills −6.8/−7.0/−6.9%** (0.735/0.727/
   0.738 vs the standing 0.788/0.782/0.793 ms/tok — the +7-8% claim lands on
   our shape), the small prompts −5-6% (the MMA kernels engage at rows ≥ 64),
   greedy byte-identical, the vision 4/4, hardmode 95 (on the both-patch
   stack; the ABSORB-only re-take rides), the duel fronts **solo 110% /
   cold 334% / c2 ~99% of production's top volley**. Adopted alone into
   config.sh after the attribution dropped the cost tables (their un-starved
   learner cost the c2 aggregate 110→93 — see item 5). Receipts:
   campaign-20261104-213422, -224230, -233541, -234405, -000521.
2. **~~The 4,096-row prompt chunk~~ — DISPOSITIONED (cont. 12-13): REJECTED
   for our line.** Ported (0094 adapted + 0095) and measured in two windows:
   builds/boots healthy, replies byte-identical, loading fine (94.6 s
   warm-cache) — but the small-prompt front regresses structurally (states
   cut at 4096-row boundaries): d8192 cold +29/30%, d8192 warm +124%, the
   d4096 warm benefit lost entirely (a 4096-row cut cannot partially serve a
   3737-token prompt). Our opencode workload lives on exactly those odd-sized
   mid-range warm resumes; Mia's fixed-deep-prompt workload never feels it.
   The deep +7% claim went unverified here (the instrument ran against the
   unpatched serve) and does not change the verdict. Receipts:
   campaign-20261104-203617 and -210211; patches/README carries the verdict.
3. **The fp8+pages marriage** (0017-0025 ported; 0026-0033 are separate
   optimizations, not ported): their pool holds 2.1M tokens on 12.5 GiB/rank
   — the combination our pin REFUSES ("fp8 keeps a window per stream"). The
   heavyweight port (a project, the roadmap's pages×fp8 item). STATUS
   (2026-11-05, cont. 33): ported (the 1,201-line combined patch) and the
   TokenUnits death root-caused — 0022's `Table.logical` covered one
   latent.Table site, v1.2.2 has three; fixed at all three. **The serving
   path VALIDATED** (campaign-20261105-114648: 11 requests, 512-row
   page-level resume, the cold 46,108-token fill 0.82 ms/tok and 92,240
   0.80 ms/tok — the windowed rate unchanged at depth); the control-verified
   bitwise cross-check then **REFUTED byte-identity** (campaign-20261105-
   133550: standing ≠ marriage-unpaged ≠ marriage-paged with a matching
   determinism control — the paged fetch and the windowed load tile the
   reductions differently; the same class as absorb's adopted fp32-summation
   change — and the bitwise mismatch itself re-interpreted as pool
   contamination, not tiling). The composed candidate (absorb + marriage)
   re-anchored onto the absorb tree (cuda_glue.zig ×2 hunks; applies AFTER
   absorb only). QUALITY DISAMBIGUATED (2026-11-05): the battery scores 95
   on the UNPAGED tree (== the standing config's 95) and 74 PAGED — the
   tree's kernels are quality-neutral; the bug is the paged pool's stale-
   page recycling (cross-request content contamination in the raw logs).
   PARKED as a serving candidate on that correctness bug; the fix hunt is
   in the E4M3 keep/restore + eviction paths.
4. **~~The restart wedge guard~~ — DONE this sitting**: their campaign
   **power-cycled a host** (`docker rm -f` returning with the old ~100 GiB
   task still dying; `docker run` over it wedged the box). Our three removal
   points (rank 1's remote launch, rank 0's local launch, stop.sh's worker
   removal) now poll `docker inspect` and die-loud/warn if it lingers.
   (Cont. 30 correction: the polls check `{{.State.Running}}` — an Exited
   husk passes and the launch's own `docker rm -f` clears it; the original
   presence form blocked its own self-healing and false-refused the
   campaign-20261105-111256 launch over a dead husk.)
5. **~~The cost-table correctness~~ — DISPOSITIONED (cont. 20): DROPPED.**
   Ported (0096 verbatim, applies clean — v1.2.2 does carry the over-priced
   tables) and adopted alongside ABSORB_MMA; the attribution duel then
   isolated it: **the un-starved overhead learner costs our c2 aggregate
   110.4 → 93.1 (~16%)** while buying nothing measurable (the prefill
   identical, hardmode within noise). The tables' fit was two-lane data on
   their stack; on ours the fed `allocateDrafts` re-allocates against the
   aggregate. Keep as history (patches/README); re-run only with a
   c2-first judgment if the draft-rule front ever needs it.
6. **Methodology adoptions**: the fixed-prompt decode gate (ours already
   matches), **per-passage NLL for numerics A/Bs — never the aggregate mean**
   (their W8A8/q6 trap: the aggregate said better while the passages said
   worse and the greedy answers moved), the never-consult-the-measured-
   endpoint rule (their advisor shim pointed at the benchmark server and
   polluted two legs), the ~1.5% host-state drift after long uptime (our
   fresh-restart windows are protected), the interleaved ABA requirement at
   the 1-2% level.
7. **Their findings that confirm ours**: DFlash2 4-bit confirmed (bf16
   drafter −3.7%), MTP a wash at 1 stream and −15/−17.5% at load,
   `cached_tokens` 0 when nothing resumed (our unwired gotcha), the
   draft-rule plateau (the confidence bracket nets zero — don't chase it),
   the shared-side overlap real (falsified the other way: −1.4/−1.0/−0.7%).

**What does not fold**: `DENSE=q8`/`HEAD=q8` as defaults (our dense4/head4 is
measured faster on our pin and the hardmode tie holds), the 1M window / 8
streams (outside our spec: 512K × 4, (user)), TP=4 (hardware we don't have),
W8A8 (their own quality-priced off), `CONTEXT=auto`/memguard (nice patterns —
noted for our scripts, low priority). **The ports are patch-port projects
against our pin** (the patch-craft protocol: read their patches, adapt to the
v1.2.2 tree, `git apply --check`, build, the A/B) — the user prioritizes.

## 2026-11-03 — v1.2.2 released (18:53, `00e7ddd`): the bump is ON — the GLM surface

The watch fired: **v1.2.2 carries directly relevant GLM content**. The items,
dispositioned for our line (the TR3 pack, 2×GB10 TP=2, dense4fp8, DFlash2, vision):

- **#1577 — GLM cold prompts 5-14% sooner at 32K-167K tokens** (a prompt chunk's
  MTP pass runs on its last row past the caches; identical replies; measured at
  TP=3, generic GLM-on-CUDA). **QUANTIFIED on our shape (the deepdelta receipt,
  campaign-20261104-182759): −2.6 to −3.5% at 50k-204k fills** — the low end of
  the claim (TP=3 there, TP=2 here), consistent across depths, both curves
  linear (0.79 vs 0.81 ms/tok). Moves our prefill front (~69-72%) and the cold
  TTFT rows.
- **#1884 — the page cache on load: released once the weights are loaded, "on
  CUDA, every family's loader"** (~15 GiB freed on a served 27B; unified memory
  no longer holds the checkpoint twice). **This is glm-tail-release.patch
  mainlined generically** — the patch likely retires on the bump, and the
  loading front's re-take (90%, 104.5 s) gets two more levers (this + #1771).
  HIGH.
- **#1771 — the ranks compute and compare a cached checkpoint digest**
  (`TENSORFOLD_CHECKPOINT_SHA256` no longer required; `--tp` lands as a server
  flag with `--rank/--master/--master-port`). Our health wait includes the
  cross-rank byte verify on EVERY restart — a cached digest may skip it warm →
  the loading front's re-take. HIGH.
- **#1795 — `TF_GLM_KV_HOST`: the KV pages' latent rows in pinned host memory**
  — **DISPOSITIONED (cont. 7): non-viable on our shape**. On fp8 the engine
  refuses it by name ("set TF_KV_PAGES=on (and --kv-cache bf16) as well"); on
  bf16+pages the serve comes up with a striking shape (the device pool
  collapses to 1.50 GiB, a 13.6-14.1 GiB prompt cache) but **every request
  timed out** (600 s deep / 300 s warm × 2) — the host-side KV path does not
  answer at our 512K×4 shape. The WARM front's named pattern is closed for
  this line; the standing 0.302 s same-session hit (70% of production's skip)
  stands.
- **#1842 — `TF_GLM_CHUNK_SOLO=4096` beside `--drafter` is REFUSED at load**
  ("it held 1.6-1.9 GiB of prompt buffers that no pass used") — **validates the
  (user) CS hold**; the knob is drafter-incompatible upstream now. BEHAVIOR
  CHANGE, no effect on our standing config.
- **#1987 — GLM refuses a checkpoint whose `tensorfold_activation_dtype` asks
  for anything but bfloat16** — the packs served on v1.2.1; if the TR3 pack
  carries the key with a non-bf16 value the bump's serve refuses (the pinbump
  receipt will show it). BEHAVIOR-CHANGE RISK, likely moot.
- **#1962 — image prompts: a cached state is never resumed for a different,
  moved or re-gridded image, and image prompts' states are no longer saved to
  disk or learned** — a correctness improvement for our vision default
  (multi-turn vision cache hits get identity-checked).
- **#1904 — the GLM DFlash2 drafter's malformed-header checks** (robustness for
  our drafter); **#1996 — the recipe documents CHUNK_SOLO's TP=3 gain halving
  under TF_GLM_ROCE_MULTI**; **#1467 — Qwen3.8-27B EXL3 prefill 38-42% faster
  on a GB10** (dense-EXL3 prompt kernels — whether the grouped-expert MoE path
  shares them, the bump's bench tells).
- No sub-4-bit EXL3 expert reader for GLM — the 3bpw gate stands.

**The bump protocol** (the round-33/45/127 pattern): the pin → 00e7ddd
(local.sh), pinbump (the explicit prepare, the marker must move), then the
re-qualification (the §2 gates, depth, prefill, the duel re-pair) + the
loading re-measurement (the digest cache + the page-cache release are the two
levers) + hardmode if the gates show any output movement. Adopt only
receipts-equal-or-better. Watch: glm-tail-release.patch may fail to apply on
the new loader (it would be redundant anyway — retire it if so).

## 2026-11-02 — the upstream watch (round 132, cont. 23): v1.2.1 still latest; the GLM opt-ins dispositioned

- The releases page: **v1.2.1 (Nov 1) is the latest engine release** — the only
  newer tag is the Mac desktop app (app-v1.0.0, Nov 2, bundles engine 1.2.0;
  irrelevant to the CUDA line). Nothing to bump to.
- The v1.2.1 GLM opt-ins, dispositioned on our line: **#1823** `TF_GLM_CHUNK_SOLO`
  (A/B'd: held, user); **#1760** `TF_GLM_VISION_HOST` (A/B'd: rejected);
  **#1732** `TF_GLM_KV_SHARE=<count>` + `TF_KV_PAGES=on` (the pages-based prompt
  retention — upstream's own receipt: "a 64k message sent again resumes in
  about 1.7 s instead of prefilling for 36 s" — THE named pattern for our WARM
  front) — the A/B is in flight (the kvshare121 phase): **the fp8×pages pair
  is a DESIGNED non-combination on mainline** (the engine's admission line:
  "--kv-cache fp8 keeps a window per stream: unset TF_KV_PAGES, or set it to
  auto or off" — the 233025 receipt; pages require bf16/auto KV); the bf16
  mechanism arm SERVED (the 000653 receipt: the on-demand pool, 18.5 GiB left,
  +3.5 vs the fp8 standing config) — and the verdict is NO ADOPTION: the warm
  same-session TTFT is a wash (0.3047 vs 0.302 s) and solo bench decode costs
  ~5-10% on bf16 KV. Our own same-session warm hit re-measured at **0.302 s**
  on the standing fp8 config (cont. 25) — 70% of production's 0.21 s full-hit
  skip, from the v1.2.0-era 1.42 s. **#1736**
  `TF_GLM_HOST_CACHE` (prompt states in pinned host
  memory — built for discrete cards with little device room; our GB10s are
  unified-memory hosts, low priority, untested).
- No GLM concurrency content for c4 in v1.2.1 beyond what we run (#1779's
  shared draft rounds covers GLM and is in our receipts; #1505's expert
  prefetch measured "within 1%" for GLM at TP=2 upstream). The c4 front stays
  upstream-gated on the batched-launch pattern.
- No sub-4-bit EXL3 expert reader for GLM in v1.2.1 — the 3bpw gate stands.

## 2026-11-02 — the GLM-5.3-Flash EXL3 checkpoint landscape (the HF sweep, round 132)

The user's spec: GLM-5.3-Flash (the architecture name IS glm5_next), vision,
2x GB10 at TP=2, 512K — the checkpoints that fit it. The sweep:

- **turboderp/GLM-5.3-Flash-exl3** (Oct 30): the canonical quantizer's plain
  2.05/3.05/4.05 + SELF-CALIBRATED 2.10/2.60/3.10/4.10 packs. The 3.05/3.10
  line is the sub-4 target from the release's author. Needs exllamav3 >=1.4.5
  (glm5_next) — our engine reads the family.
- **androidli/GLM-5.3-Flash-Uncensored-EXL3-3.0bpw-mcg-TensorFold** (the
  zai-org discussion, Oct 19): experts-only 3.0bpw mcg, everything else
  source-native (vision tower included). MEASURED ON OUR SHAPE: 2x DGX Spark
  TP=2 over CX7, TensorFold 0.6.0, vision + fp8 KV + spill + DFlash2 all
  verified; KV pool 3.89M tokens (vs 1.86M at 4bpw); forward latency -8/-16/
  -17.5% vs 4bpw; EvalPlus 86.3% (4bpw: 86.5%). THE COMMUNITY'S 3bpw PACK —
  a ready-made sub-4bpw serve — no local quantization (requants are out of
  scope, user round 132). ROUND-132 RECEIPT: the native CUDA engine REFUSES it
  — "EXL3 at 3 bits: the CUDA family reads 4-bit EXL3 experts"
  (UnsupportedQuant); its 0.6.0 verification was the python-engine era. The
  sub-4bpw goal on the native line is upstream-gated on the family's reader.
  CAVEATS: the base is dealignai's
  UNCENSORED derivative (not zai-org — content policy is the user's call),
  its receipts are EvalPlus not hardmode, and the verification era is 0.6.0.
- **JANGQ-AI/GLM-5.3-Flash-EXL3** (4.0bpw): vision 16-bit, MTP in, mul1,
  153 GB, "for DGX Spark". Quantized ON a GB10 with the layer-streamed
  converter.
- **LibertAIDAI/GLM-5.3-Flash-EXL3-4bpw**: experts 4bpw mul1 + MTP experts
  6bpw, everything else BF16 byte-identical, 165 GiB, receipts vs TR3 (ppl
  -0.8%, expert error lower).
- **Terra3312/...-4bpw-MUL1**: vision + lm_head at 6bpw (a quality trade),
  the INT8-GEMV decode path angle.
- **yamz-labs/...-EXL3-Yamz** (99.7 GB): a turboderp 2.05/3.05 per-layer mix,
  scale-tuned — tested ONLY on AMD Strix Halo (Kyojin engine), config warning.
- **vcruz305/...-EXL3-K2** (2-bit experts, 97.7 GB): qualified only on
  vLLM/L40 at 8K; vision unqualified. Deep-bit, low priority.
- On site already: the Focus (93/104 hardmode on v1.2.1 — receipted today),
  the AZ, Mia-AiLab 4bpw-TensorFold + TR3, the DFlash2 drafters.

**Addendum (round 137 cont. 8, 2026-11-08)**: the fork's 0081 (the exl3r
read-once trellis — the 4-bit grouped experts read every trellis word
once) is PORTED AND ADOPTED here as `015-zshfl.patch` (the thirteenth
patch): content identical, hardmode 95 (the thirteenth consecutive) —
but **its measured decode gain did not transfer to our shape** (decode
flat on every instrument; the L2-gather saving matters on their
cold-expert trains, not our hot hierarchy). The fork's measured claims:
three for three on the prefill side (0030 decode-side transferred at
concurrency; 0078+0079 and 0080 prefill-side transferred whole-prefill),
this one the first not to. Adopted for bit-safety + the 0082 base. The
exl3r series continues (0082: the chain as dependent launches) — the
next candidate to scope.

**Addendum (round 138, 2026-11-08)**: the fork's 0082 (the exl3r chain
as dependent launches) is PORTED AND ADOPTED here as `016-zstep.patch`
(the fourteenth patch): content identical (the fork's 108/108 exactness
confirmed), hardmode 95 (the fourteenth consecutive) — **its measured
chain gain did not transfer to our shape** (decode flat; the second
decode-side non-transfer after 0081). Pattern so far: the fork's
PREFILL-side kernel claims transfer whole-prefill (three for three:
0078+0079, 0080); its DECODE-side claims (0030 excepted — a launch-count
reduction, which did transfer at concurrency) do not. The exl3r series
continues (0083+); the HC-split/overlap set remains the biggest unported
claim (+36% at 50k prompts).

## 2026-11-08 — v1.2.5 released + the fork's 0104-0111 scan (the round-139 cont. 7 subagent)

**Upstream v1.2.5** (262 commits past our v1.2.4 pin): the CHEAPEST bump since
the v1.2.2→v1.2.4 rebase. `tool_parse.zig` byte-identical v1.2.4→v1.2.5 — both
server-layer patches (010-tools256, 011-zclose) survive untouched, and upstream
STILL lacks the #415 own-name rule (rule 1 keeps them alive). Of the ~60 files
our (then) 16 patches touch, only THREE drift: the KV-pool rewrite (#2358 — one hard
re-anchor: 003-fp8-pages' contract-registry append must re-cut onto v1.2.5's
new `registry_joins.zig`; `glm_family_host.zig` likely one line), the engine's
gate/shared block moving to `cuda_engine_gate.zig` (mechanical; all `e.*` call
sites keep working), and the peer warm-up deadline `7ead07c92` (additive, a
rank-hang-class robustness win for our pair). All nine kernel patches stand on
byte-identical kernel files. What the bump buys: #2358 TF_KV_SHARE plan
integrity, #2533 kept-state eviction control, #2442 disk-state restore retry,
#2304 prompt-width telemetry. **Verdict: schedule a v1.2.5 qualification window
after the 018-callquote receipt — moderate priority, one hunk re-anchor + the
§2/hardmode/vision battery guards it.** (Nothing posted upstream.)

**The fork's engine patches 0104-0111** (its pair is now the SAME topology as
ours — two Sparks, TP=2 direct split; its TP=4 recipe was removed):

| # | What | Disposition |
|---|---|---|
| 0104 | warm turns for GLM: the server background-prefills conversation+reply+next-turn-opening after a reply (`warm_quiet` 150 ms), so an agent loop's next turn stops re-prefilling the whole prefix from the loop's start (their measurement: 4,096 of 9,335 tokens resumed; 50-100K prefills 10-30 s) | **PORT — the highest-value of the set.** Our 512K tool-calling agent workload is exactly the shape; needs our own window; merges with our `cuda_lanes.zig` hunk |
| 0105 | an untyped tool parameter decodes into the JSON the model wrote | WATCH — our tools are typed; zclose/tools256 cover the halt-class failures |
| 0106 | warmPeers follows the prefill reduce mode | SKIP — we are TP=2 direct split, the patch leaves direct unchanged |
| 0107 | `TF_TOOL_CALL_GUARD=1` hides unoffered call markup | WATCH — interacts with 010-tools256's surface-it contract (deliberately different) |
| 0108 | `CACHE_FIRST=1` (`TF_PROMPT_CACHE_FIRST`): the prompt cache set aside BEFORE the streams' windows — a 380k conversation resumed 99% cached (3.0 s vs 234 s) at their PARALLEL=8/1M | **PORT candidate for the 512K plan** (the resume front); our own window + the memory arithmetic re-check |
| 0109 | LEARN_GIB: kept states to disk (their backport of upstream #1411) | SKIP — v1.2.4/5 carry #1411 natively; the v1.2.5 bump gives us it |
| 0110 | `KV_SHARD=1`: each stream's FP8 latent rows on its owner Spark alone → the pool holds ~2× tokens (4,098→8,196 pages), paid 1.6-3.6% decode | **PORT candidate for the 512K plan — the interesting trade**; touches our fp8-pages ground, decide after the v1.2.5 rebase lands |
| 0111 | the image build compiles warning-free (unused decls; byte-identical fatbins) | SKIP as a port — zero effect by construction |

**Adjacent fork facts**: their 2026-11-07/08 `SERVE_EXTRA_ARGS='--top-k 20'` +
`EFFORT_LINE=thinking` pair — the effort-line change moved their sparkDash QA
79.3%→86.0% thinking-off and cut malformed-markup lines from 30-36% to 3 of
1,419 (the same symptom class our zclose/tools256 address from the parse side;
worth a look when the quality instruments next run). Their raw-markup incident
never reproduced on the pair; the top-k 20 mitigation stays.

## 2026-11-11 — the main watch (round 141 cont. 7): 87 commits past the tag; two GLM-relevant main-only items

**Upstream main** is 87 commits past v1.2.6; no v1.2.7 tag yet. The GLM-relevant
main-only items:

- **#2744 — the vision tower encodes only images that end after a chunk's
  start**: multi-image prompts stop re-encoding images their earlier chunks
  already injected (their host test: 12 tower passes instead of 18). **We
  serve vision as the standing default** — a vision-prefill perf candidate
  when the next release lands (our vision suite's assets are single-image
  per request, so the gain shows on multi-image workloads we do not
  currently bench; the watch item is the release, not a port).
- **c0f8e1c4c — the router's K slices on the shared mma tiles**
  (`common/router_mma.cuh`): a refactor claiming byte-identical outputs and
  "replies, prompt and decode speed at TP=2 are unchanged" — no perf claim,
  a code-health item for the next rebase. Our router_tile is vanilla (no
  patch touches it), so the rebase is mechanical when the release comes.
- The Unreleased changelog's other CUDA items are non-GLM (LightOnOCR-3,
  Qwen 3.5, Flash Next Metal scale-index) — no move for us.
- The four-GB10 switchless ring (#2569/#2742: TP=4 on
  `TF_GLM_PREFILL_REDUCE=gather` + the NCCL settings) needs four hosts; our
  pair is the site's shape — recorded, out of scope.
- #2699's mainline entry carries the 16-agent prompt-cache rework with
  measured GB10 numbers (105 s → 25.8 s at 16 agents); the mechanism class
  is already in the v1.2.6 engine we serve.

## 2026-11-10 — v1.2.6 released; the rebase absorbed it same-day (round 140)

**Upstream v1.2.6** (6e9af9302, released 2026-11-10): carried #2257 (GLM TP=2
decode windows to 32 rows — the release's own +32% one-stream code decode
claim), #2699 (the prompt-cache rework; `budgetOf()` moved the budget
construction), #2181 (`TF_GLM_KV_LIVE_HALF`, opt-in, unmeasured candidate).
#1431/#2415 KV-SHARD did NOT land — the fork port stays a separate decision.

**The #2699 measurement note (ours, round 141 — for the upstream thread;
NOTHING posted — the repo rule)**: on the 2×GB10 TR3-4bpw serve
(524,288-token window, PARALLEL=4, fp8 paged KV, TF_KV_SHARE=16,
TF_PROMPT_CACHE_FIRST=1), the v1.2.6 pool plan funds **6 of 16** kept states'
slots at the standing config (the fixed parts' #2257 growth ate the rest),
and funding all 16 via `--prompt-cache-gib 4` costs the third 512K window
(enough-for-2 vs 3) plus 1.0 GiB of stream room. The value-first A/B
(campaign-20261110-215136) measured the funded arm at **−11 ms** on the
within-session resume delta vs the cacheless arm's **+6 ms** (the criterion:
>150 ms better) and 154 ms LESS on the multi-turn TTFT — the page cache over
the pool's pages already delivers the resume value cacheless on this shape.
Verdict: the TF_KV_SHARE kept-states slots' resume value is negative against
the room they cost at this window/stream/depth shape; the cacheless standing
holds. Shape-dependence caveat: single-rank or shallower-window deployments
differ; this is one deployment's measurement, not a general claim.
Our line rebased the same day: the drift map applied (6 of 18 verbatim, 12
re-anchored), the round-trip PROVEN byte-identical, the v126val battery
qualified every instrument — the pin HOLDS at 6e9af9302 (the round-140 cont.
2 receipt, campaign-20261110-162034). **Upstream main is 36 commits past the
tag** and has absorbed the fork's exl3p prompt loop (`bc166dbfd`) plus
cp.async/ldmatrix/mma common-module extractions — the next release may
mainline more of the fork's stack (the watch continues; findings stay data).

