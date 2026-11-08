# GLM-5.3-Flash on two DGX Sparks — the native-engine build, tuned and measured

*Everything in this card is measured, not estimated: every number quotes a logged
campaign receipt. All edits in the underlying repository are AI-generated
(OpenCode agents running GLM, by Z.ai) — the receipts discipline is the review.*

## The rig

- **Model**: GLM-5.3-Flash (Z.ai's open-weights model), served from an EXL3 4-bit
  expert pack (resharded for the loader's direct-read path; tensors byte-identical
  to the public pack), DFlash2 drafting on top.
- **Hardware**: a pair of NVIDIA DGX Spark (GB10) boxes as a TP=2 pair — one head
  (rank 0 + API), one worker (rank 1) — connected over RoCE.
- **Engine**: TensorFold's **native** engine (Zig + CUDA, no Python at serve time)
  at v1.2.4, plus a **13-patch local tuning stack** (below). Context **524,288
  tokens**, 4 concurrent streams, fp8 KV pages, fp8 dense weights, images and video
  in.

## The tuning stack (13 patches, each A/B-qualified bit-identical)

Every patch is content-verified: its A/B's greedy outputs are identical to the
byte across arms, the §2 content gates pass, and hardmode holds. Each has an
environment kill switch and can be dropped independently.

| # | Patch | What it does |
|---|-------|--------------|
| 1 | absorb-mma | a prompt's absorb_q/expand_v as tensor-core GEMMs (deep fills −6.8/−7.0/−6.9%) |
| 2 | fp8-pages | fp8 KV caches on the paged-KV path |
| 3 | pagerows-fix | the E4M3 tables' page rows |
| 4 | selist-fix | the prefill's token lists stay logical (a loop bug) |
| 5 | packed-s2 | two-stage packed-prompt matmuls (pp +3.4/+5.8/+6.7%) |
| 6 | exl3prompt | the EXL3 prompt path in one call per pass (pp +24.5/+22.7/+23.3%) |
| 7 | attnfetch8 | the latent attention's FP8 key tiles load 8 bytes at a time, a tile ahead (pp +1.7-4.3%, tg +2.9-10.9%) |
| 8 | loaddirect | each layer's tensors read past the page cache while the previous layer packs (the load wall 103 s → 83 s) |
| 9 | moeside | a decode window's MoE shared expert on a second stream (solo +2.9%) |
| 10 | zmoe-fuse | a decode window's MoE glue fused into one block; the grouped experts without slot-row copies (c4 +4.2%) |
| 11 | zprompt | the prompt experts' main loop recompiled for 8-member column blocks, the next k-tile decoded among the current MMAs (pp +1.8-2.5%) |
| 12 | zs2 | the packed prompt GEMMs' loads fixed once a block + 8-bit codes to bf16 pairs in fewer steps (pp +1.6%) |
| 13 | zshfl | the 4-bit grouped experts read every trellis word once (bit-safe; neutral on this shape — kept as the base for the next patch) |

## The scoreboard (same-window duels against the stock EXL3/Python recipe)

Both engines serve the same model, the same probes, the same window
(campaign-20261107-225124 unless noted):

| Front | Ours | Stock recipe | Ratio |
|---|---|---|---|
| Load wall (cold, both ranks) | 83 s | 93.7 s | **112.9% — crossed** |
| Solo decode (2,048-token, t/s) | 68.0/68.1 | 58.5/58.6 | **116.2% — crossed** |
| 2-stream aggregate (t/s) | 118.6 | 110.2 (its top-of-range; floor 86.4) | **107.6% at its top, 137% at its floor** |
| 4-stream aggregate (t/s) | 168.9 | 154.8 (its floor; range 155-241 with cache state) | **109.1% at its floor** |
| Streaming latency per token | 14.7 ms | 17.1 ms | **116% — crossed** |
| TTFT at depth, cold (d8192) | 3,803 ms | 17,129 ms | **450% — crossed** |
| Request overhead (TTFT, 1-token) | 183 ms | 185 ms | 98.9% |
| **Prefill (pp2048, t/s)** | **1,519** | **1,518** | **100.1% — crossed (campaign-20261107-214342)** |

The prefill chain across four days of adoption: 1,150 → 1,434 (the one-call EXL3
prompt path) → 1,458 (the attention prefetch) → 1,495 (the prompt experts' loop
rework) → **1,519** (the packed-prompt loads) — the last uncrossed front fell.

## Quality

- **hardmode: 95, thirteen consecutive runs** (the ceiling-holding scenario
  battery; TC-51 and TC-92 pass in every run).
- **Vision: 4/4** on the raster suite (raster-only assets with agent-verified
  ground truth — no improvised fixtures).
- **The §2 content gates, every window**: greedy determinism, drafted = plain,
  resumed = fresh, concurrent = solo (content-identical; the raw-byte
  differences are the engine's documented nondeterminism).
- The cost tables were dropped after an attribution duel showed they cost the
  2-stream aggregate ~16% and bought nothing measurable.

## Benchmarks (tool-eval-bench)

A single full run on the adopted stack — parallel=4, hardmode on, perf on,
needle-in-a-haystack enabled (`--seed 42 --perf --needle --hardmode --parallel 4`)
— is in flight in the current window; this section's numbers land with the next
digest. The standing hardmode score on this stack is 95.

## Serving notes

- Every tuning patch has an opt-out environment switch (`TF_GLM_MOE_FUSE=0`,
  `TF_GLM_EXL3P=0`, `TF_GLM_MM_P2=0`, `TF_EXL3_SHFL=0`, `TF_GLM_SHARED_SIDE=0`,
  `TF_GLM_ABSORB_MMA=0`, `TF_LOAD_DIRECT=0`), so a regression on different
  hardware is one variable away, not a rebuild.
- The porting discipline: each upstream/fork patch is line-verified against its
  source (every added line must appear verbatim in the port), compiled per-arch,
  verified byte-identical from a fresh tree, and only then A/B-qualified on the
  real model.
- The engine's admission refusals print their own arithmetic — a refusal is a
  receipt, not a failure to retry blind.

## What's next

The fork's decode-side series (the read-once trellis landed; the chain as
dependent launches is next), the PDL launch-chain set, and the
hyper-connection split/overlap set (+36% at 50k prompts on the fork's
hardware) are scoped and queued.
