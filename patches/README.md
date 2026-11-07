<!-- ROUND 133 (cont. 7): glm-tail-release is RETIRED from the default PATCHES
(empty since the v1.2.2 bump) — #1884 mainlined the page-cache release for every
CUDA family and the no-patch serve is byte-identical on memory AND speed
(campaign-20261103-235114 arm D: 14.1 GiB left, 68.8 s at an 87k fill — the same
rate as the with-patch curve). The patch stays here as history and re-runs only
if the line ever pins below v1.2.2. -->
# Patch overlay policy

This directory carries **optional local patches** applied to the TensorFold tree at image
build. `config.sh`'s `PATCHES` knob selects them (empty = pristine upstream, the default and
the tested configuration); `scripts/prepare.sh` stages the named files into `image/patches/`
and the Docker build applies them right after the TensorFold checkout.

## THE v1.2.4 REBASE (2026-11-07, round 135) — all 8 stack patches + one new wiring

The adopted 8-patch stack was rebased onto **TensorFold v1.2.4** (`267c5af6a`,
675 commits after v1.2.3) and one new patch joined. Every patch file here now
carries a `REBASE (2026-11-07, onto v1.2.4 267c5af6a)` paragraph in its header;
the per-entry staging lines below that say "v1.2.3" are the historical port
records — the header note supersedes them.

- **Applied verbatim (content unchanged, only anchors re-cut)**:
  exl3prompt, packed-s2, pagerows-fix, selist-fix, attnfetch8 — the drift map's
  bare-v1.2.4 failures re-aligned once the stack sat beneath them.
- **Hand-re-anchored**: absorb-mma (the Fingerprint at layout 20 — 19 plus
  numerics — after v1.2.4's prompt-pair fields; the Forward constructions carry
  `l2pf`/`prompt_pair.piecesOf`; the numerics test appended after v1.2.4's
  KV_SHARE adapter test), fp8-pages (the snapshot tests append after the
  adapter test; the records import beside the pages family; the explain lines,
  `Pages.waiting` and the host-test step re-anchored), moeside (the side field,
  `sideStream`/`freeSide`, the constructor, deinit and both Forward call sites
  re-anchored around `pair` and `l2pf`).
- **New: glm-zz-loaddirect.patch** — GLM's layer loads wired onto v1.2.4's
  `checkpoint.direct` (#2282/#1901), following the gemma4/qwen3_5 pattern in
  `cuda_load_ahead.zig`: each layer's tensors read past the page cache while the
  previous layer packs; `TF_LOAD_DIRECT=0` keeps #1928's read-ahead. Our
  checkpoint's 23 shards < `gather.max_sources` (64): the path engages.
- **The verification (triple)**: the 9-commit rebase branch (`v124-rebase` on
  the head's /tmp/tf-src) — fresh-v1.2.4 + the commit bodies byte-identical
  (0 diff lines); fresh-v1.2.4 + the SHIPPED patch files in alphabetical order
  byte-identical (0 diff lines); the full compile (fatbins + native, nvcc
  sm_121, zig 0.17.0) RC=0 in the builder base image. Judgment: the v124val
  window (the §2 gates, the bare-config smoke under #2405's strict TF_
  validation, the battery, the vision, the loading wall's re-take on the direct
  reads).

## The rules

1. **Upstream first.** A patch exists here only while upstream lacks the feature (check
   #840's carry-over tracker and the latest release notes). The moment an upstream release
   covers it, the patch is dropped and the version bump takes over.
2. **A receipt or it doesn't go in.** Each patch carries, in this file or the patch header:
   what it changes, the measured effect (config, hardware, cell-by-cell numbers from
   `run-bench-matrix.sh` or the engine's own counters), the exact TreeFold commit it was
   ported against, and who owns rebasing it at the next bump.
3. **One concern per patch.** A patch that bundles several changes cannot be measured or
   dropped independently.
4. **Rebase cost is the bill.** The ecosystem's 77-patch stack (jayleaton's repo) targets
   TensorFold 0.3.4 and buys ~3% over its own control — their headline numbers come from
   configuration, not patches. Port a patch only when its measured win is worth the
   rebase tax on every future version bump.

## The Mia 1104 fold-in stack (verdicts 2026-11-04, round 133 cont. 12-13)

Ported from [MiaAI-Lab/GLM-5.3-Flash-DGX-Sparks-1104](https://github.com/MiaAI-Lab/GLM-5.3-Flash-DGX-Sparks-1104)
(Apache-2.0) against TensorFold `00e7ddd` (v1.2.2). The scratch-repo stack
verify passed; two windows measured them (campaign-20261104-203617 and
-210211). **The chunk pair is REJECTED for our line; the cost tables stay
staged.**

- **glm-mia-chunk4096.patch + glm-mia-dflash2-ingest.patch — REJECTED**
  (keep as history; re-run only if the line ever wants a deep-prefill-only
  mode). The receipts: builds and boots healthy ("passes of up to 4096
  rows", 13.7 GiB left, load 94.6 s warm-cache — no loading cost), replies
  byte-identical (sha 9e04a49e5786 on every probe, both windows), BUT the
  small-prompt front regresses on the clean same-instrument rows (both sides
  ran TF_GLM_PROF=1 VISION=0 — the standing resumecost pattern):
  d8192 cold 5.55 → 7.17/7.20 s (+29/30%), d8192 warm 1.44 → 3.22/3.24 s
  (+124%), d4096 warm **benefit lost entirely** (resume at 0 — a 4096-row
  state cut cannot partially serve a 3737-token prompt), d2048 ~2% faster.
  The mechanism is structural: states cut at 4096-row boundaries — sub-4096
  and odd-sized prompts (the opencode workload's mid-range) lose their warm
  resumes. Mia's fixed-deep-prompt workload never feels this. The deep +7%
  claim went unverified on our shape (the deepfills instrument ran against
  the unpatched serve after an in-phase restart lost RC_PATCHES — see the
  launch log) and does not change the verdict: the bump protocol requires
  receipts-equal-or-better and the warm front regresses.
- **glm-mia-cost-tables.patch — STAGED for the ABSORB_MMA window** (output-
  neutral: sha-identical everywhere, no effect on max_tokens=1 probes —
  rounds=0). The 2-constant correction (52.0+6.8 → 38.73+5.68 lone, 76.0+4.1
  → 47.38+5.05 shared) is measured on our exact hardware (2× GB10) and
  un-starves depth.zig's overhead learner; its effect shows only under
  loaded draft scheduling, so it rides the ABSORB_MMA window's hardmode
  phases. Applies clean (proving v1.2.2 still carries the over-priced
  tables).

OWNER: this line. The stack verdict receipts: results/campaign-20261104-203617/
and results/campaign-20261104-210211/ (the resumecost rows + the deepfills
receipts + the g3 counter find: `tensorfold:prompt_tokens_cached_total`).

## glm-mia-cost-tables.patch — DROPPED (2026-11-05, round 133 cont. 20)

The attribution duel settled it: with ABSORB-only, c2 returns to **110.4**
(its stable 109-110 band) vs **93.1** with the tables — the un-starved
overhead learner costs our c2 aggregate ~16% and buys nothing measurable
(the prefill identical: slope 0.602 in both duels; hardmode 95-with-tables
vs the 94 control is within scenario noise). Mia's "throughput effect is
their noise" does not hold on our shape. Keep as history; re-run only if
the draft-rule front ever needs the learner fed (with a c2-first judgment).

## glm-mia-absorb-mma.patch — ADOPTED (the qualified optimum, 2026-11-05)

The ABSORB_MMA port (Mia 0041, Apache-2.0): a prompt pass's absorb_q and
expand_v MLA matmuls run as head-batched bf16 tensor-core GEMMs with fp32
sums when `TF_GLM_ABSORB_MMA=1` (off by default — the fp32 summation order
differs from the SIMT kernels; the numerics ride every rank fingerprint,
layout 16 → 17, so disagreeing ranks refuse to start). 17 context-drifted
hunks re-anchored onto the v1.2.2 tree; the diffstat matches the original
exactly (9 files, 247 insertions, 7 deletions); glm_glue_num.cuh (the
156-line kernel file) applies verbatim; the scratch stack verify passed
(alone and under the cost tables, alphabetical). Their measurement (RTX PRO
6000, 2048 rows × 32 heads): absorb 1.212 → 0.113 ms, expand 1.471 →
0.093 ms per matmul, +8% prefill end-to-end, sampled outputs bit-equal to
SIMT. SHIPPED with glm-mia-cost-tables.patch via
`RC_PATCHES="glm-mia-absorb-mma.patch,glm-mia-cost-tables.patch"` in the
"preflight resumecost deepfills hmcheck summary" window; judged by the
content gate (sampled-bit-equal → the greedy sha must hold), the resumecost
rows (the small-prompt front must NOT regress — the chunk pair's lesson),
and the deep fills. **ADOPTED alone into config.sh's PATCHES default
(2026-11-05, cont. 20) after the attribution dropped the cost tables** —
receipts: the deep fills −6.8/−7.0/−6.9%, the small prompts −5-6%, greedy
byte-identical everywhere, the vision 4/4, the duel fronts solo 110% /
c2 ~99% of production's top volley / cold 334% / ITL ~107% crossed.

## glm-mia-fp8-pages.patch — PORTED + RE-ANCHORED ONTO ABSORB (the composed candidate); byte-identity REFUTED (control-verified) — the judgment is the quality instruments

The fp8+pages marriage (Mia 1104 0017-0025, Apache-2.0, adapted to v1.2.2;
0026-0033 are separate optimizations, not ported): E4M3 latent caches on the
KV page pool — 6,380 bytes/token beside DFlash2 vs 13,056 bf16, one shared
elastic pool (4,100 pages × 512 rows ≈ 2.1M tokens, 13.61 GiB/rank). Port
history: the first window died TokenUnits at the first DSA sparse launch
(campaign-20261105-105143) — ROOT CAUSE: 0022's `Table.logical` port covered
ONE latent.Table site (their base had one; v1.2.2 has three) while 0021's
dispatch routes E4M3 to the _paged kernels at every site; FIXED at all three
(`.logical = c.ls != 0`, cuda_dsa_block.zig). The serving path then
VALIDATED (campaign-20261105-114648: 11 requests, page-level 512-row
resume, the cold 46,108-token fill 0.82 ms/tok and 92,240 → 0.80 ms/tok —
the windowed rate unchanged at depth).

**The bitwise cross-check REFUTED byte-identity** (the windowedsha arc,
control-verified): greedy + thinking-off + 64-token chains with the seed
pinned — the determinism control (the standing config booted twice) MATCHED
with identical drafter profiles, and the standing config's shas reproduced
across windows — yet standing ≠ marriage-unpaged ≠ marriage-paged. The
paged fetch kernels and the windowed load path tile the reductions
differently: same stored values, different fp accumulation order. NOT a
defect — the same class as ABSORB's own adopted fp32-summation change; the
judgment moves to the quality instruments (hardmode + the vision suite) on
the composed paged stack.

**STAGING: applies AFTER glm-mia-absorb-mma.patch only** (alphabetical:
absorb-mma < fp8-pages). The compose initially FAILED (cuda_glue.zig:58 ×2
Kernels hunks — absorb's latent_mma fields drifted the trailing context);
RE-ANCHORED (2026-11-05): the paged fields sit before `merge`, the init
calls after `chunks_32_fp8`, absorb's lines untouched; the fresh composed
apply-check passes (1,217 lines). The ttft receipt on the composed-relevant
serves: the paged cold fill 38.1 s ≈ marriage-unpaged 37.9 s at 46k
(paging adds ~nil); the standing config's 35.3 s carries absorb's −7%.
config.sh defaults unchanged pending the quality receipt.

## glm-mia-pagerows-fix.patch — THE CONTAMINATION FIX (staged, 2026-11-05; judged by the canary + the battery re-run)

The E4M3 Tables' page_rows was `c.ps/(l.lw*2)` — the WHOLE-page stride over
the bf16 row bytes = 3,481 instead of 512. The selection kernel indexes
`pt[row/page_rows]`: with 3,481 every row below 3,481 read PAGE 0's pooled
keys, the token selection scored against rows 0-511's keys, and the sparse
lists were garbage — the model attended to the wrong tokens (the hardmode
battery's cross-request-content signature, 74 vs the >=94 bar; the canary
receipts; the CudaContextLost crash under poison = the selection's garbage
indexes). The contract tests passed because their FIXTURES use per-layer
ps, where the formula coincidentally yields 512; the engine's Caches carry
the whole-page ps. THE FIX: the three Table sites take `latent.chunk` (512)
for E4M3; bf16 keeps its formula (its lists are page rows, a different
unit; its path is receipted correct — the poolcanary3 bisect). STAGING:
sorts AFTER glm-mia-fp8-pages.patch (the first name sorted before it and
the build's alphabetical apply failed — the rename is the receipt).

## glm-mia-packed-s2.patch — the packed-prompt matmuls in two stages, two blocks an SM (staged 2026-11-06; the mms2 A/B decides)

Mia 1104 0009, adapted to v1.2.3 (applies clean — glm_mm.cu/cuda_mm.zig are
untouched by the 4-patch stack). glm_mm{4,6,8}_128s2: __launch_bounds__(256, 2)
and 41 KB of shared memory in two cp.async stages (the 128-row kernels take
61.8 KB in three, one block an SM; a 768-row prompt piece's 384 blocks fit one
wave instead of 2.04). Each output's K groups run in the same order — the sums
are glm_mm{B}_128's bit for bit (Mia: 0 differing outputs on all eight shapes).
Mia's measurement (RTX PRO 6000, sm_120, 400 W sustained): 1.07-1.09x on GLM's
prompt shapes; under their power cap most of the occupancy gain became power —
the GB10 envelope differs, so the mms2 window's A/B decides (the content-sha
cross-arm gate + the pp rows, 2+ runs per arm). STAGING: applies on v1.2.3 +
the 4-patch stack; disjoint files, the list order does not matter. OWNER: this
line; STATUS: EXPERIMENTAL.

## glm-zz-steplink.patch — the follower's step in one broadcast, a window's greedy picks in one gather (staged 2026-11-07; the steplink A/B decides)

Mia 1104 0031+0032 hand-ported to v1.2.3 + the adopted stack (0031's
hunks carry 0030's moe_fuse plumbing — the fork stacks them; the port
DROPS those bits). 0031a: a window's greedy picks — one top-1 + one
gather + one sync + one read PER ROW before — batch into ONE gather of
every rank's words (the pairs buffer pick_rows=32 wide), each row
picked as greedy picks it; the verify window's rows stop paying a
round trip each. 0031b: every step's first broadcast is 384 bytes (the
header and a decode step's ids) — one host round trip instead of two;
rank 0's keep rides its next verify/block/draft step of the same slot;
a follower's verify and shared steps join their gathers and skip the
sync and read. 0032: a refused step never loses a committed keep. No
arithmetic changes — the replies are the same. STAGING: applies on
v1.2.3 + the 8-patch stack (verified byte-identical to the port
commit); NAMED glm-zz- TO SORT AFTER THE STACK (the engine hunks
assume the moeside port's side field). OWNER: this line; STATUS:
RETIRED (cont. 104: the steplink A/B — content identical everywhere but the gain at parity: the steady-state +1.0% avg inside the probe's ±2%, the bench tg mixed-sign noise; the mechanism is real but sub-resolution on our shape — a 1-row window does one gather either way, and the verify-window round trips are cheaper than the claim's context assumed; the patch stays staged for a future re-judgment if 0030's fusion changes the economics).

## glm-zz-moeside.patch — a decode window's MoE shared expert on a side stream beside the routed experts (staged 2026-11-07; the moeside A/B decides)

Mia 1104 0006+0010 hand-ported to v1.2.3 + the adopted stack (our
drift: the two Forward constructions carry .absorb_mma — the port adds
.side beside it; upstream's flashnext has the same pattern, so the
Stream/Event API matches). 0006: the shared expert's gate/up, SwiGLU,
down and put_slot fork onto a second stream right after the block's
input and join before the slot combine — the kernels and the combine's
order unchanged, the bits the same, only the overlap changes;
TF_GLM_SHARED_SIDE=0 is the kill switch; prompt chunks never fork.
0010: the side stream drains on any error from the fork on, in deinit,
and on init's error path. Mia's measurements: 70.6 → 60.6 µs a MoE
layer at one row, 96.5 → 84.9 µs at two (−14/−12%). STAGING: applies
on v1.2.3 + the 7-patch stack (verified byte-identical to the port
commit); NAMED glm-zz- TO SORT AFTER THE STACK (the hunks assume the
absorb-mma port's .absorb_mma field). OWNER: this line; STATUS:
EXPERIMENTAL.

## glm-zz-attnfetch8.patch — the latent attention FP8 key tiles load 8 bytes at a time, a tile ahead (staged 2026-11-07; the attnpref A/B decides; NAMED glm-zz- TO SORT AFTER THE STACK — the image applies patches alphabetically and the port depends on the fp8-pages marriage's PAGED8 file state; the first attnpref window burned on exactly this)

Mia 1104 0005+0011 hand-ported to v1.2.3 + the paged marriage (our
chunks_wide carries PAGED8 — the port folds the page-table addressing
into the new fetch8 lambda; 0011's contract naming lands as-is).
0005: each thread fetches its 8-code units of tile + 2 with one 8-byte
read right after the tile's first barrier — the reads overlap QK,
softmax and PV — and converts where load_kv(tile + 2) stood; the same
cvt, row scale and bf16 rounding per value, so the shared-memory keys
are the same bits. 0011: the 256-thread block is the named contract
CHUNK_THREADS (static_assert + the kernel traps on any other width).
Mia's measurements: decode dense chunks 58 → 35 µs, sparse 72 → 41-44
µs. STAGING: applies on v1.2.3 + the 6-patch stack (verified
byte-identical to the port commit). OWNER: this line; STATUS:
EXPERIMENTAL.

## glm-mia-exl3prompt.patch — the EXL3 prompt path in one call + no MTP beside a drafter (staged 2026-11-06; the exl3call A/B decides)

Mia 1104 0007+0008 hand-ported to v1.2.3 (the fork's hunks drifted: no k6
kernels here, the v1.2.x engine delegates the MTP absorption to
prompt_solo.mtpRows, the two test files don't exist — dropped, the A/B's
content gate verifies). 0007: chunk_rows follows prefill_rows (2048, was
1024 — the trellis decodes once a pass, the bits unchanged) and the down
kernel writes the MoE slot rows straight (yrow — dropping the
cuMemcpy2D of [rows][8][4096] fp32 per call and the arena's y). 0008:
with a drafter the target MTP layer's caches are never read — the prompt
stops absorbing into them (a whole DSA+MoE layer a pass). Mia's
measurements: routed experts −28%, the MTP pass 3.4-4.4% of a traced
pass; in the engine WITH 0009 (our adopted packed-s2): cold prefill
+12.6/15.6/16.0% at 4K/16K/64K, T=0 replies unchanged. STAGING: applies
on v1.2.3 + the 5-patch stack (verified byte-identical to the port
commit). OWNER: this line; STATUS: ADOPTED (cont. 89: the exl3call A/B cleared — content IDENTICAL, pp +24.5/+22.7/+23.3%; exl3qual §2 PASS + hardmode 95 + the vision 4/4; the duel re-paired; config.sh's sixth patch).

## glm-zz-dsasel3.patch — THE LOOP HUNT'S INSTRUMENT v3 (RETIRED 2026-11-06: the mechanism receipted — the selist fix closed it, and the v1.2.3 rebase re-receipted the fix end to end; the instrument is NOT in the serving PATCHES list and stays here as the hunt's record)

The DSA selection instrument: tf_glm_dsa_tokens prints VIOL lines (an
E4M3 selection containing a token beyond the row's causal limit —
mechanically impossible unless something selects outside the scored
range) and periodic SEL lines (row 0's first eight selected logical
positions + count + npool); tf_glm_index_pools prints PICK lines (the
select kernel's own pos read, vis, NP and top-2 outputs, sparse
launches only). STAGING: three same-name updates (v1-v3 under
glm-zz-dsasel.patch) NEVER reached the cached build — the container ran
v1's format twice after v2/v3 were staged; the rename to a NEW file
name is the fix and the receipt. Offline analysis of the v1-format
dumps stands: 47.6-74% of sparse selections emit out-of-horizon tokens,
frozen on fixed page-start windows (9,216; 35,328) far beyond any
request's history, while both kernels read causal in source.

## glm-zz-debug-tokenunits.patch — RETIRED (2026-11-05, the file removed)

Logged the exact mismatch inputs at the TokenUnits return in cuda_latent.zig
chunks(). Fired never (the logical fix at the three latent.Table sites held —
campaign-20261105-114648); the bitwise receipt landed (campaign-20261105-
133550) and the diagnosis closed. This entry is the history.

## Candidates under watch (upstream PR scan, 2026-10-23)

- **#1079 — DFlash2/lanes decode (+9–15% on qwen27, "replies unchanged")** — TESTED AND
  DROPPED (2026-10-23, `campaign-20261023-185520/`): all §2 gates PASS on the patched
  build ("replies unchanged" holds on our model), but the throughput A/B is a **wash** —
  solo d0 +3.3% (48.3→49.9), solo d4096 −8.6% (49.0→44.8), every other row ±2%, pp/TTFT
  unchanged. The qwen gains live in qwen's tree-draft kernels, not in the shared-lanes
  parts our chain drafting hits. Patch file removed per the rebase-tax rule; this entry
  is the receipt.
- **#1171 — qmmf half tiles (32-column, 16-row decode calls)** — bit-for-bit, gated by
  `TF_QMMF_HALF_BELOW`, but instantiated for MXFP8/BF16 **only — FP4 is excluded**, and
  our dense4/head4 packing is FP4-mode qmmf: only the residual BF16 lane calls would
  take the fast path. The diff does not apply at our pin (one registry hunk); expected
  gain small for us. Revisit when it lands in a release.
- **#1143 — Flash Next: NVFP4 experts on prompt tiles, decode-form sums, bit for bit** —
  the expert-batching-in-prompt-passes mechanism our prefill gap wants (we are 90%
  router+routed in prompt chunks), but Flash Next-family files. The glm/cuda port is
  the upstream ask (with #1080's 4096-row chunks).
- **#1078 (TF_DRAFT_NODES) is qwen-tree-only** — its knob lives in qwen's draft-frame
  staging, not the shared drafter; no path to GLM's DFlash2. Main since 1351ed16 is
  app/infra/Flash-Next/grammar — no glm/cuda perf movement; our pin stays current.

## Candidates under watch (from the ecosystem review, 2026-10-19)

- **fp8 latent KV for GLM CUDA** (jayleaton 0220) — halves KV bytes; **upstream 1.1.2 now
  prepares this in stock behind `--kv-cache fp8`** (BF16 default; native quality and device
  qualification pending). A patch would only be a backport; qualifying stock on our pair is
  the open item (see the 512K plan).
- **16-row verify windows** (jayleaton 0380) — more tokens per round; upstream's GLM window
  policy is per-release.
- **L2 weight prefetch in decode** (jayleaton 0460).
- **RoCE all-gather wiring** (jayleaton 0230/0350) — **resolved without a patch**: stock
  already wires the gather (`openRoce` at GLM startup, `TF_ROCE` defaults on); our blocker
  was the runtime image missing libibverbs/libmlx5 (rank logs warned
  "VerbsUnavailable; NCCL carries every gather"), fixed 2026-10-22 by installing
  libibverbs1 + rdma-core in the image and setting `NCCL_IB_HCA` on the site. Their +1.5%
  prefill gain was the NCCL channel set, also adoptable via env.

None of these are carried yet. Measure stock v1.1.2 + the RoCE/NCCL set first —
if the greedy cells land near the ecosystem's numbers, none of these is worth its tax.

## glm-router-ks2.patch (staged 2026-10-24, untested — PERF_PLAN Front 2 Lever A2)

One constant: `router_ks = 8 → 2` in `families/glm/cuda_glue.zig`. The prompt-router
section eats 910–1,125 ms of every 2,048-row prompt chunk (55–69% of chunk GPU time) for
a ~4.8 GFLOP GEMM (receipts: campaign-20261023-145449, the 235008 salvage, the 000708
cells); the same kernels cost 47 µs/layer at m=2 — the slowdown is superlinear in rows.
With `router_ks = 8` each tile block runs an 8-step mma pipeline (never reaches steady
state) and every x element is re-read 9×8=72 times per layer; `ks = 2` halves the
re-reads and quadruples each block's K-depth. Expected: chunk 1641 → ~600 ms, prefill
slope 0.662 → ~0.25 (production parity).

**Bit-visible by design** (the source comment: "the sliced and the single pass differ in
bits") — the §2 gates decide this patch, not hope: greedy-drafting-equals-serial must
PASS or the patch dies like #1079. Verification plan: build with
PATCHES="glm-router-ks2.patch", serve dense4fp8, prof one 2,048-row prompt chunk (the
router section + chunk wall), run the §2 gates, then the prefill slope probes.

## glm-slot-leak.patch (staged 2026-10-24, untested — upstream 7d330e24d, #1218)

One line in `core/lanes/engine.zig`'s `release`: a stream released between rounds left
its queued draw's handle unread, and GLM's ring keeps a queued round's slot until its
handle is read — so every completed or cancelled request leaked a slot until restart.
Long-serving sessions would erode toward fewer usable streams. Carried as a staged patch
until v1.1.4 ships it upstream. Bit-invisible (pure resource management); the §2 gates
run as usual when the next build carries it.

## glm-router-ks2.patch — RETIRED 2026-10-24 (content gate; receipt campaign-20261024-115242/11-routerks2.md)

The window ran the A/B clean (the agent silent): stock cell solo 55.3/55.1, c2 73.5,
c4 101.8, slope 0.659 — the duel baseline reproduces exactly. The patched cell: the
**content gate said DIFFERS** (the ks change flipped a greedy token — bit-visible as the
source warned) **and the router section did not move** (1096 → 1090 ms of the chunk —
the 8-step-pipeline hypothesis is rejected as the pathology's cause). The patched cell's
decode looked faster (solo 64.3, c4 119.6) but that is an acceptance lottery riding the
bit change (77→higher acceptance on this workload), not a mechanism — and it changes
replies, so it is unadoptable. The patch dies here; the pathology stays open with the
ks hypothesis eliminated (next candidates in PERF_PLAN Front 2 A2: microbench both
router kernels at m=2048, or route the prompt router through cuda_mm's GEMM).
glm-slot-leak.patch remains staged (bit-invisible, unaffected by this verdict).

## glm-router-part.patch (staged 2026-10-24, probe two — Front 2 A2)

Forces the unstaged router kernel (`router_part`) for every launch, replacing the
tile/ part branch in `families/glm/cuda_glue.zig`. Same ks slicing and summation order
as `router_tile`, so the math should be bit-identical — the content gate (vs the
115242 stock reply) verifies. The cost read splits the prompt-router pathology:
part ≈ tile (~1100 ms/chunk) → both kernels share it → replace with a real GEMM;
part >> tile → the tile is better and the fix is its K-depth/w-layout.

## glm-topk4b.patch (staged 2026-10-24, probe three v2 — Front 2 A2 / the AZ Experiment 1)

Renamed from glm-topk4.patch: the config fingerprint hashes the patch LIST (names), not
contents — the amended patch needs a new name to force a rebuild (the round-7 lesson's
sibling: session pins live in local.sh, and here a content change needs a name change).

Two lines: the struct default `topk: u32 = 8` → `4` in `families/glm/cuda_glue.zig`'s
parse (see below) and the module global `pub const top_k = 8` → `4` in
`families/glm/cuda_exl3.zig:128` — the EXL3 experts specialize for the routing width;
the first forward with slots=5 hit `error.UnsupportedTopK` there (campaign-20261024-13xx,
rank 1 stopped; rank 0 followed). The actual struct-default edit lives in
`families/glm/config.zig`. The
parse's validation snapshots the struct defaults BEFORE the json (`const want = c;`) and
requires `c.topk == want.topk` — any topk≠8 checkpoint is `error.NotGlm53Flash`, whose
silent catch in `weightShare` then bills the WHOLE 163.6 GiB to the budget (campaigns
125609 + 132628's refusals; the three earlier "top4" serves actually ran topk=8 because
the config edit never persisted, then the real topk=4 config was rejected here). With
the reference at topk=4 the kernels specialize for slots=5 and the variant serves.
**MEASURED 2026-10-24 (campaign-20261024-135458)**: routed 18.45 → 11.0 ms at 2 rows;
solo 63.5/63.6 t/s = **108% of production**; c2 103%; **c4 120.4 = 78% of production**
(was 65%); slope 0.593 (−10%); acceptance rose (4.8 tok/chunk vs 3.37). Outputs change
by design (the AZ Experiment 1: unretrained top-4 routing) — the content gate does not
apply to this phase; the acceptance counters and the quality battery do. **Not a
servable default** (config.sh stays topk=8) until the quality battery runs: §2 gates +
full tool-eval + structured-output + TEB. The AZ full checkpoint (the retrained
selector) is the quality-safe route to the same win.
## glm-router-gemm.patch (staged 2026-10-29, probe three v3 — Front 2 A2, the scoped fix)

Diffed against **v1.1.9 (465e48b6)** — the pin moves for this window; it does not apply to
1.1.8 (1.1.9 touched the same files). The prompt-router pathology's replacement: prompt
chunks (m ≥ 128, aligned) route through a new staged chain kernel instead of the
hand-rolled `router_tile`/`router_part` pair. Decoded into pieces:

- `tf_glm_router_mm` (glm_glue_router.cuh): one K slice per launch in glm_mm's prompt
  shape (128-row blocks, ROWS_FIRST for L2 sharing, 3-stage cp.async, PDL, 256 threads)
  with ONE continuous mma chain per output — the hand-rolled kernels' exact arithmetic
  (same canonical m16n8k16 fragments, same ascending k16 order from zero, `slice_sum`
  untouched), so the summed logits are bit-identical by construction; the content gate
  verifies. The gate tile rides the same shape as glm_mm16_rows (74112 B dynamic shared).
- `glm_mm_tile16s` (glm_mm.cu): tile16 with a strided source — each MoE gate tiles into
  8 contiguous [ne][d/8] K-slice layouts at engine init (a re-layout, same bytes;
  ~2.25 MB/layer, one buffer owned by the mm kernels).
- Wiring: `glue.router` gains a `tiles` param and the dispatch (decode-size rows,
  unaligned x and untiled gates keep the hand-rolled kernels); the MoE layer carries
  `rtiles`; the engine init builds the tiles under **TF_GLM_ROUTER_MM=1** (off by
  default — the patch is INERT without the env, so one image serves both A/B legs).
- Why not call stock glm_mm per slice: its per-64-group accumulator (fresh `d` per
  group, `acc += d`) rounds differently than the router kernels' continuous chain —
  fp32 non-associativity would fail the content gate (#1079 protocol).

Compile receipt: fatbins + native build RC=0 in the builder image (nvcc sm_121,
zig 0.17.0) at v1.1.9. Measured effect: PENDING the routergemm window (leg stock vs
leg gemm: content gate + chunk prof + hardmode). Baseline: the 1.1.8 cell's chunk
router 1096 ms of 1967 gpu (campaign-20261024-115242). Owner of rebasing at the next
bump: this line's agent.

## glm-hc-fuse.patch — the fused hcPre launch (Front 2's fusion lever, round 115)

- What: ONE kernel per hcPre replaces the two-kernel chain (tf_glm_hc_partial or
  hc_partial8, then tf_glm_hc_finish) — a block per row, 256 threads, the partials in
  shared memory in the finish's `part` row layout, `glm_hc::finish_row` inline. The
  finish body is UNMODIFIED (its `part` row offset moved to the callers); the fused
  kernel reproduces the chain's exact op order (partial8's per-step ops over all 16
  K-blocks, the dots reduced in ascending step order, the ss warp butterfly + the
  (0+2)+(1+3) combine) — bit-identical by construction; the content gate verifies.
- Gating: **TF_GLM_HC_FUSE=1** (off by default — the patch is INERT without the env,
  so one image serves both A/B legs). The finish/f32w twins gain `hc_pre_fused` /
  `hc_pre_fused_f32w` (the Set's comptime name binding picks them up).
- Design + census: patches/hc-fuse-design.md; results/campaign-20261030-134836/31-
  ncurouter.md (hc_partial p50 104 µs + hc_finish 54 µs, 4 launches/layer — the glue
  launch-count dominator; the fusion removes 2 launches/layer and the global `part`
  round-trip).
- Compile receipt: fatbins + native build RC=0 in the builder image (nvcc sm_121,
  zig 0.17.0) at v1.1.9; `git apply --check` clean on the pristine tag.
- Measured effect: PENDING the hcfuse window (leg stock vs leg fuse: content gate +
  chunk prof + duel + c4). Owner of rebasing at the next bump: this line's agent.

**Measured verdict (round 116, campaign-20261030-144836): NOT ADOPTED.** The content
gate is IDENTICAL (bit-safety by construction proven), but the perf regressed where it
mattered: solo decode −8.4% (53.9 → 49.4 t/s), c2 −8.3%, c4/prompt neutral. Mechanism:
the fusion serializes the 16 K-blocks (the chain's grid-y) into one block's sequential
loop — free at prompt occupancy (2048 blocks), costly at decode occupancy (1-16
blocks). TF_GLM_HC_FUSE stays off; the patch remains as the receipted design of a
correct-but-unprofitable fusion.

**Status correction (round 119): DEAD on v1.1.9 — does not apply** (developed
pre-v1.1.9, never rebased; `git apply` fails on the pristine tag). Even rebased it
would be near-inert on the native GLM serve: the cache rules are hardcoded
`planned = false` with no grid (glm_dsa_host.zig:46), so the patch's block never
fires — and its interior keeps address cross-prompt share-stops, not the forced
2048-aligned resume tail that owns the resumed-TTFT gap (round 119's decomposition:
the restore is at parity with production; the gap is the chunk granularity). The
round-41 "proven" claim is corrected: its 1,445 ms equals the unpatched behavior.
Rebasing is parked with the finer-grid trade-off (the prefill anchor vs the resume)
documented in LAUNCH.md round 119.

## glm-boot-marks.patch — the boot's phase marks (the loading lever, round 126)

- What: additive `std.log.info` timing at the GLM CUDA load's phase boundaries —
  the checkpoint open, every 10th weight layer, embed+norm+head, the kernel
  modules, the weights upload, the linear pack, the buffers. Logging only; no
  behavior or numerics change (the window's content gate binds the same
  content_sha as the pristine serve).
- Why: the boot's 221.5-s upload+pack bracket (campaign-20261030-210712's
  timestamped docker brackets: digest-end → pack-line) is 95% of the 233-s boot;
  the disk does 7 GB/s O_DIRECT on the shards (which re-read cold every boot —
  the loader's `ck.release()` drops pages so CUDA allocations keep room), so the
  phase is the loader itself, not storage. The marks split the loader's interior
  (read vs convert vs per-tensor upload vs pack).
- Ported against: v1.1.9 (465e48b6); `git apply --check` clean on the pinned
  tree. Owner: this line.
- Status: measurement instrument — passed via `RC_PATCHES` for its window; the
  standing config stays pristine.

## glm-pinned-upload.patch — the loader uploads through the pinned stage (round 126)

- What: `Loader.put()` chunks every tensor through the copy-source Stage's
  reusable 64 MiB PINNED buffer (cuMemHostAlloc, freed with the loader) instead
  of `DeviceBuffer.fromHost`'s synchronous path, which stages each ≤64 MiB chunk
  through a fresh PAGEABLE heap buffer (`copy_source.zig`:
  `const durable = std.heap.page_allocator`) and `cuMemcpyHtoD_v2`s from it.
  Failure contracts kept: drain-before-free on a failed staging, the stage's
  wait-before-reuse, the stage closed with the loader.
- Why: the boot's 45-layer loop is 184.5 s at ~444 MiB/s effective
  (campaign-20261030-212657's marks, ~4.1 s/layer dead-flat, GPU util 0-4%) —
  the pageable-copy regime; the disk does 7 GB/s O_DIRECT. Pinned copies run at
  fabric speed. The DeepSeek v41 loader took this exact pattern upstream
  (7fce15ce9, post-v1.1.9) — our port puts the GLM loader on the tree's own
  Stage machinery, which v1.1.9 already ships.
- Byte-identical by construction: the same bytes, the same device addresses;
  the window's content gate binds the outputs (identical content_sha to the
  pristine serve).
- Ported against: v1.1.9 (465e48b6); `git apply --check` clean. Owner: this line.
- Status: under measurement — passed via `RC_PATCHES` with glm-boot-marks.patch
  (the layer-loop marks show the effect); the standing config stays pristine
  until the receipt.

## glm-readahead.patch — one WILLNEED per tensor range at the loader's funnel (round 126)

- What: `Loader.add()` (the single funnel every tensor's bytes pass through)
  prefaults the exact byte range it is about to copy with one `MADV_POPULATE_READ`
  (22, raw syscall so the pinned std doesn't matter) before the copy. Advice only —
  anonymous memory (the no-mmap fallback) no-ops, errors ignored like `release()`'s
  own madvise. **v1 used WILLNEED and REGRESSED** (211.1 → 278.3 s boot,
  campaign-20261030-221626): WILLNEED's async readahead races the fault loop into
  duplicate I/O; POPULATE_READ is synchronous — each page read once.
- Why: the maps are `MADV_DONTNEED`ed after every layer
  (`safetensors.File.release` — unified memory needs the room), so each layer's
  ~1.8 GiB re-faults from disk in tensor-interleaved order and the kernel's
  readahead never ramps: ~3 s/layer of major faults held after the pinned-upload
  patch removed the copy component (campaign-20261030-215302: the loop 184.5 →
  162.9 s for a −0.48 s/layer copy win). A per-tensor WILLNEED starts the
  full-range read before the faults; a contiguous tensor read at fabric speed is
  ~0.3-0.5 s.
- Byte-identical by construction; the window's content gate binds the outputs.
- Ported against: v1.1.9 (465e48b6); `git apply --check` clean. Owner: this line.
- Status: under measurement — rides with glm-pinned-upload.patch and
  glm-boot-marks.patch in one window; the standing config stays pristine until
  the receipt.

## glm-boot-marks2.patch — the phase marks plus per-tensor timing (round 126)

- What: glm-boot-marks.patch's phase marks, plus `add()` marks the read (the
  map's faults + the host copy) per tensor and `put()` marks the device alloc +
  H2D per tensor — name, KiB, elapsed ms, ~4000 short lines a boot. Logging only.
- Why: both advice-based readahead variants REGRESSED (WILLNEED 211.1 → 278.3 s;
  POPULATE_READ → 289.6 s — campaigns -221626 and -224013), so the fault-read
  hypothesis needs direct evidence: the per-tensor marks decompose the 45-layer
  loop's ~4.1 s/layer into read vs upload. Runs ALONE (it patches the pristine
  loader; glm-pinned-upload.patch edits the same put() lines).
- Ported against: v1.1.9 (465e48b6); `git apply --check` clean. Owner: this line.
- Status: measurement instrument; supersedes glm-boot-marks.patch for this
  window; the standing config stays pristine.

## glm-trellis-scratch.patch — the expert trellises read whole, sliced host-side (round 126)

- What: `exl3.load`'s by_cols branch (the gate/up trellis assembly) reads each
  expert's ~4-MiB trellis ONCE contiguously into the Loader's reusable scratch
  (`@memcpy` from the map — a sequential fault stream), then appends the rank's
  tile spans host-side from the warm scratch. A `scratch` ArrayList on the
  Loader, grown to the max trellis and freed with it.
- Why: the old path issued ~kt strided 8-KiB appends per expert straight from
  the mmap — the 16-KiB stride defeats readahead (each span's fault-around reads
  8-16× its bytes) and the per-span overhead lands at ~48 µs: ~66K spans/layer ≈
  3.2 s/layer ≈ 142 s of the 184.5-s layer loop. The per-tensor marks
  (campaign-20261030-225411) proved the MARKED copy work is only 36 s (add 7.3 +
  put 29) — the appends sat outside them. Whole-tensor reads: ~1-2 ms/expert.
- Byte-identical by construction: the same spans, from a warm scratch; the
  window's content gate binds the outputs.
- Ported against: v1.1.9 (465e48b6) **on top of glm-pinned-upload.patch** (the
  build applies the staged patches alphabetically; the first cut was
  pristine-based and the build refused it — campaign-20261030-231937). The
  field is `trellis_scratch`: the Loader already has a `scratch()` device-buffer
  fn and Zig forbids a field and a declaration sharing a name — the second cut
  compiled to `duplicate struct member name 'scratch'` (campaign-20261030-233318;
  git apply passes textually, only the build catches symbol collisions).
  Owner: this line.
- Status: under measurement — rides with glm-pinned-upload.patch (the upload
  stage is part of the same honest path); glm-boot-marks2.patch stays home this
  window. The standing config stays pristine until the receipt.

## glm-upload-marks3.patch — the marks over the adopted stack: put() splits ALLOC vs staging (round 126)

- What: glm-boot-marks2's phase + per-tensor marks, regenerated as a delta ON
  TOP of glm-pinned-upload.patch + glm-trellis-scratch.patch; put()'s mark now
  prints the alloc ms and the staging ms separately.
- Why: after both patches the loop still holds ~125 s unattributed; the lead
  hypothesis is the per-tensor `cuMemAlloc` under the full unified pool (~1,534
  allocs of MB-GB sizes — which would also explain the advice-variant
  regressions and the late-layer slowdown). The mark answers it directly.
- Ported against: v1.1.9 (465e48b6) + the two patches. Owner: this line.
- **The name is load-bearing**: the build applies the staged patches
  ALPHABETICALLY, so a patch that assumes the stack must sort after it
  (campaign-20261031-000643: `glm-boot-marks3` sorted before
  `glm-pinned-upload` and the build refused it against pristine).
- Status: measurement instrument; the standing config stays pristine.

## glm-tail-release.patch — the tail tensors' pages released after the load (round 127, on v1.2.0)

- What: one `ck.release()` + `head_ck.release()` after the embed/norm/head/MTP
  tail loads — the same release the layer loop already runs per layer, applied to
  the loader's tail files.
- Why: v1.2.0's 16-reader load-ahead (#1616/#1636) pulls the whole checkpoint
  into the page cache; the per-layer releases cover the layers, but the tail's
  ~2-3 GiB (embed 1.2 GiB, norm 0.6, the head, the MTP rows) stays resident.
  v1.2.0's admission arithmetic trips on it at our config:
  `--parallel 4 needs 10.84 GiB for its streams ... the CUDA memory budget leaves
  10.72 GiB` (campaign-20261031-004214, a 0.12-GiB refusal where v1.1.9's
  accounting left 12.9 GiB). Releasing the tail restores the room.
- Advice-only (MADV_DONTNEED/fadvise), byte-identical by construction; the
  window's content gate binds the outputs.
- Ported against: v1.2.0 (a388876f); `git apply` clean on the pristine tag.
  Owner: this line. Upstream lacks it (the release notes carry no such release);
  per patches/README rule 1 it lives here until an upstream release covers it.
- Status: under measurement — the v1.2.0 qualification window runs it
  (RC_PATCHES=glm-tail-release.patch).

## glm-prompt-4096.patch — the prompt chunks at 4,096 rows (round 130, porting #1576)

- What: `cuda_state.prefill_rows` 2048 → 4096 and DFlash2's `MAX_CTX` follows
  (the ingest context one chunk takes). Two value edits; upstream's receipt says
  the output is unchanged (bit-safe by construction; our window's content gate
  verifies).
- Why: our prefill front is 69% of production's and the per-chunk overhead is the
  gap's shape — 4,096-row chunks halve the pass count, and the depth TTFTs drop a
  pass too (the d4096 probe becomes one pass). Upstream #1576 is open (unmerged);
  ported against 49a01bb3.
- The memory price: the chunk buffers double per stream — the admission
  arithmetic is the receipt if parallel 4 no longer fits (restart_fb falls to 2
  and the cells note it).
- Status: **TESTED AND REJECTED (round 130, campaigns -214624 at parallel 2 and
  -224154 at parallel 4)**: the gates PASS and the bench is a wash (pp 1,017 vs
  1,049; the score 95), but the depth probes REGRESS on our EXL3 config — the
  cold d8192 7.45 s vs 5.52 unpatched (+34%) and the warm 3.35 s vs 1.42
  (+136%): the 4,096-row chunk costs more per pass than the fewer passes save
  (the KDA/state span's per-row cost grows with the chunk). The pass-count
  theory is falsified here; upstream's receipt was the FP4 checkpoint at 500K.
  The parallel-4 fit is also memory-tight (the cache-fit yields the prompt cache
  to 1.0 GiB; one boot refused and retried at parallel 2). The patch stays as
  the record; the standing config does not adopt it.

## glm-full-hit-skip.patch — a full-hit resume skips the pass (round 131)

- What: the radix emits the prompt's full-length tail state when the prompt
  lands on the step (the tail mark was always filtered at m >= len — no state
  at `at == len` could exist), `find()`'s cap admits it, and engine.prefill's
  fast path (`resumeFirst`) installs the restored state, projects the held
  last-row hidden through the head (ONE row — the exact row the pass's own
  draw projected, bit-identical from the restored arena) and draws.
- Why: the ncuwarm receipt (campaign-20261101-055816) showed the warm resume
  REPLAYS ~one tail chunk of GEMMs (1.05 s kernel window; the wall 1.42 s vs
  the cold 5.5 s) because the kept state lacked the last-row hiddens;
  production's 0.21 s warm is a full-hit skip. This patch makes ours one.
- Unchanged: partial resumes (at < len), unaligned lens (no tail state — the
  old behavior), the chunked/follow paths, prompt_logprobs (no resume there).
- Verify: the scratch stack apply (after glm-full-hit-skip sorts before
  glm-tail-release; independent files) + the symbol greps clean (resumeFirst
  1 decl + 1 call; no collisions). Compile-risk audited: promptHead/drawWhole
  exposed on Engine, bd.logits the proven draw target (redrawFirst's pattern),
  the drafter restart copied verbatim from prefillStart.
- Receipt: the FIRST build refused — prompt_radix.zig:93 local constant
  shadows declaration of 'limit' (the Store's limit() method; the
  symbol-collision class the audit missed for LOCALS — campaign-20261101-115038);
  the local renamed to cap, the scratch apply re-verified.
- Receipt 2: build 2 booted, the gates ALL PASS (g3 resumed=fresh on the
  skip's path) and the bench held (95) — but the skip never ENGAGED (the warm
  walls 1.410/1.410/1.407 s, exactly unpatched — campaign-20261101-120948).
  The hole: the pass's keep callbacks fire only at CHUNK STARTS and no chunk
  starts at the prompt's end — the full-length tail state was emitted by
  marks() but never kept. The fix: prefill() fires the len-keep itself after
  the last chunk returns (post-commit, post-holdPrompt — the arena and the
  held last-row hidden are final).
- Status: **PARKED — the patch never engages for real prompts; kept as the
  record.**
- Receipt 3 (the arc's close): build 3 booted with the end-of-pass keep, the
  gates ALL PASS again, hardmode 95 — and the skip STILL never engaged: the
  warm walls 1.405-1.407 s (campaign-20261101-125939). The real hole is
  DESIGN, not a bug: the tail state only exists when the prompt's length
  lands on the step, and real prompts (fill + template + ask) never do. The
  general fix needs exact-match nodes in the radix core (a node's
  guaranteed-match extent is its 512-token pages; a snapshot covering rows
  beyond the pages is only valid for the exact prompt — a longer prompt
  sharing the prefix would resume a wrong state). That is engine-scale work,
  not a patch. The cheap partial (resume alignment 2048 → 512 rows, warm ≈
  0.4-0.5 s) is round 119's PARKED trade — it costs the prefill anchor 28%,
  declined per the bar. The standing config is unchanged; the warm-resume
  front is upstream-gated (ECOSYSTEM.md carries the design finding).

## glm-dflash-taps-tp.patch — DFlash2 reads complete prompt taps at TP>1 (round 131, the #1623 port)

- What: with the default split glue, the DFlash2 tap after layers 5/14/24/33/42
  read the rank's own residual for the other ranks' rows — HALF the drafter's
  prompt context was stale at TP=2. The fix: each rank taps its own rows of a
  split piece (tapPieces), then shareTaps hands the tap rows to every rank via
  the same relay that shares normed. Replies never change; what improves is
  DRAFT ACCEPTANCE — the decode front.
- Receipt (upstream #1623, 3x GB10 TP=3, our checkpoint family EXL3-4bpw @
  078455ffe): +1.0-2.1% aggregate decode at every level, the acceptance
  tokens/chunk up (2.37→2.42 chat, 3.05→3.08 code), replies unchanged, no TTFT
  cost. Our knobs sweep confirms the effect's size independently:
  PREFILL_REDUCE=gather (complete taps) measured solo 46.2 vs 45.1 (+2.4%) —
  this patch delivers that gain without gather's prefill regression.
- Port: the PR's hunks for cuda.zig/cuda_engine.zig/cuda_forward.zig were
  hand-adapted to 49a01bb3 (the contexts drifted since the PR's base); the test
  files stay upstream; cuda.zig gains the dflash_load/taps exports; prefillChunk
  nulls the taps for chunks ending before the drafter's window; the unpieced
  tap call takes the new (lo, n) signature.
- Verify: the scratch stack apply clean (independent of glm-tail-release), the
  symbols confirmed (tapPieces/shareTaps in forward_pieces, the exports, the
  new signature at the unpieced call).
- Receipt: the first port's build REFUSED — the diff-section split dropped a
  newline and glued the next header into forward_pieces' content
  (`expected ',' after field` at :153 — campaign-20261101-140226); the scratch
  verify checked the APPLY, not the FILE CONTENTS. v3: the sections are
  newline-terminated and the content check (no diff text inside the touched
  files, clean endings) is part of both the tree and the scratch verifies.
- Receipt (tapsqual, campaign-20261101-142151): the gates ALL PASS (g2
  drafted=plain on the fixed path — bit-safety holds), the bench's every tg
  row IN the standing band (solo 45.2/46.1/46.1; c2/c4 unchanged), the depth
  probes unchanged (7.24 cold / 1.410 warm), hardmode 95 — **and the upstream
  +1-2% decode does NOT reproduce on our cell**. Why: upstream measured at
  TP=3 (two-thirds stale) on a low-acceptance profile (2.37 tok/chunk); our
  TP=2 halves the staleness and our acceptance is already higher (4.8
  tok/chunk, the top4-era receipt) — less to recover, and the bench's tg128
  rows cannot resolve 1-2% inside the ±2-3% noise band.
- Status: **PARKED — bit-safe and free, but unproven on our cell; not
  adopted.** Kept as the record (and as the ready-made port if the pin ever
  bumps past #1623's landing).
