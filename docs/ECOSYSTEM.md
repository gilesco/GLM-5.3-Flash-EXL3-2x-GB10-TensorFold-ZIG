# The ecosystem around us: what other GLM-5.3-Flash stacks do, and what it means for this repo

Researched 2026-10-23 from forum thread 381350 (read end-to-end — receipts in
docs/LAUNCH.md) plus each repo's own README. Question this page answers: **is
there anything in the community stacks that should change how we run, tune, or
build on the 1.1.x native line — without importing their complexity?**

Our standing bias, unchanged by the research: this repo's differentiator is
*easy to use, easy to get started with*. Ideas are welcome as **config knobs,
preflight checks, or doc pointers**; frameworks, patch ladders, and multi-file
config regimes are not.

## The field at a glance

| repo | engine | what it runs | headline numbers (their own or the thread's) |
|---|---|---|---|
| kindlingai/glm-5.3-flash-gx10 | vLLM + "mentat" scheduler | NVFP4, DFlash2 adaptive-k, dual-root RoCE | won kindlingai's six-config shootout; all-reduce 110→190 Gb/s, +11% prefill |
| technigmaai/glm-5.3-flash-gb10-tp2-native | vLLM native TP2 | NVFP4 FP4-Local, DFlash2 | thread's quality/speed leader: 96 max TEB, 2678 pp |
| kindlingai/glm-5.3-flash-exlr8-gx10 | vLLM + exlr8 MoE kernel | **EXL3-trellis experts** (k2/k3/k4) | decode +3–8% vs NVFP4, KV +15%, prefill −7.7% (open gap); k3 TP2: 84.2 code t/s, 4.2M KV pool |
| eugr/spark-vllm-docker | vLLM (regular + B12X images) | recipe system for many models; GLM-5.3 = B12X + MTP + 1M ctx | the hub the other vLLM stacks are derived from |
| Entrpi/glm-5.3-flash-exl3-2x-spark | vLLM | **EXL3 4-bit** checkpoint, 1.29M ctx at parity | the other "easy button"; one-shot installer with rollback |
| goshi/tensorfold-spark-dashboard-metrics-exporter | bridge, engine-agnostic | **TensorFold metrics → Spark Dashboard** | zero-dependency; primary profile targets our engine line |
| 0rand / DragonScale / rodman80 / gitcommit90 / kindlingai gr8 / aidenle | misc | NVFP4, W4A16, single-Spark, from-scratch CUDA | different hardware targets or quant lines — noted, not studied |
| 0rand/glm53-tensorfold-spark (`main-0rand`) | jayleaton-family fork (TF 0.3.4-era base) | **EngineMetrics/Prometheus patch 0710** (engine-native request/token/draft counters, five latency histograms, KV-pool gauges); isolated image tags; a 1.57M-token shared KV pool at lowered guards; ToolEval Q1 93/100 | first studied 2026-11-17 — see the dated watch entry below |

Community benchmarks of *our* repos from the thread (receipts in LAUNCH.md):
**G647 (production 0.6.6, fp8 dense+KV) = 93.0 max TEB / 52.7 t/s sweep / 93.9%
depth score — the best EXL3 stack measured**; bernisse runs our 1.1.2 line
unqualified for weeks at 94/100 tool-eval; giles8 confirms real concurrency
(>100 tok/s aggregate).

## What transfers to us — three tiers

### Tier 1 — adopt now (zero complexity, config/doc-level)

1. **goshi's metrics exporter is built for our engine.** Its `zig-v1` profile
   targets exactly the TensorFold native line (`tensorfold_*` underscore
   families + `/health` JSON), and `python-v1` targets production's 0.6.6
   (`tensorfold:` colon families). Zero engine changes, stdlib-only, systemd
   unit included, honest omissions (no faked KV% or queue numbers), persistent
   counters across restarts. This is a free operability win for the whole site:
   run it beside whichever stack is up, point Spark Dashboard at :8004.
   *Caveat to verify on our first trial:* the README's examples assume the
   engine on `:8002`; ours serves on `:8000` — set `TF_UPSTREAM` accordingly.
2. **Never pin `NCCL_IB_GID_INDEX`** (kindlingai's hard-won rule: RoCE GID
   tables reorder across reboots; derive at start). We already don't pin it —
   recorded here as an **invariant**, so a future tuning session doesn't
   "fix" that.
3. **CPU clock verification at preflight** (MaTeZZ's finding, now in
   `scripts/run-qualification.sh`): kernel 6.17 ran Grace at floor clock with
   `scaling_cur_freq` lying; the `acpi_cppc/feedback_ctrs` probe is the honest
   number. Our hosts run the good 7.0.0-1019 kernel — the campaign logs
   delivered MHz anyway, so a regression can't hide.
4. **Headless hosts for the heavy runs** (eugr + kindlingai both require it:
   desktop sessions cost GB10 real memory and, per kindlingai, CPU/GPU share
   one power budget). Both our hosts are SSH-driven already; noted so a future
   "why is decode low" session checks this early.

### Tier 2 — measure on our stack, hand the data to upstream (not code we write)

1. **Adaptive-k DFlash2.** kindlingai picks draft length per step from a live
   cost/acceptance model; MaTeZZ measured acceptance ~2.3 (prose) / 4.5 (code)
   / 5.8 (JSON) at temp 0 — draft depth should match the task. TensorFold's
   DFlash2 uses fixed rounds. We can't set this via config, but our
   `TF_GLM_PROF` sessions + the campaign's cliff phase produce exactly the
   acceptance data an upstream adaptive-k (or deeper rows per #1059) needs.
   Collect, don't implement.
2. **Prefill fairness.** kindlingai caps one prefill's share of each scheduler
   step (`LONG_PREFILL_TOKEN_THRESHOLD=2304`) after a 120k-token prefill
   blocked a 12-token request for 78–90s. Our engine interleaves prefill and
   decode (prompt passes) — the thread says vLLM stacks can't. Whether a deep
   prefill stalls concurrent decode *on our line* is exactly what the
   campaign's depth + cliff phases will show. If yes: that's a measured
   upstream ask with numbers attached.
3. **Spin-wait / heat.** kindlingai's `busy_loop_s=0.002` patch trades spin
   latency for ~20°C and decode loss on GB10's shared power budget. Upstream
   1.1.x already moved followers to sleeping ranks (#1053). The head's idle
   behavior between steps is unmeasured for us — a one-window `TF_GLM_PROF`
   + `clock_mhz` check closes it.
4. **Structured-output draft truncation** (MaTeZZ's mechanism for our
   concurrency cliff): one `json_schema` request disables draft truncation for
   the whole batch (31.5 → 22 tok/s per stream). The campaign's cliff phase
   tests this directly; if it reproduces on 1.1.2, it's the single most
   valuable bug report we could hand upstream (as data, not a patch).

### Tier 3 — watch, don't adopt (engine-specific or out of scope)

1. **EXLR8 (mmastrac's EXL3-trellis experts).** The one genuinely EXL3-family
   development in the field: per-layer k2/k3/k4 expert rates decoded by a
   custom MoE kernel, beating NVFP4 on decode (+3–8%) and KV (+15%) with an
   open prefill gap (−7.7%). Serving an EXLR8 checkpoint would need a loader
   in upstream TensorFold — out of our hands, but if it lands, our line gets
   smaller experts and bigger KV windows from the same trellis math we already
   serve. **Watch item #1.**
2. **Dual-root RDMA collectives** (kindlingai's arx, both CX7 PCIe roots,
   all-reduce 110→190 Gb/s). Our `NCCL_IB_HCA` (the site's cabled HCAs, set in
   `local.sh`) already names both roots and rank logs confirm 2 HCAs —
   effectively the same idea via NCCL. Nothing to change; the rank-log line
   stays in every receipt.
3. **B12X / megamoe / marlin kernels, mentat scheduler, InstantTensor
   loading** — vLLM-side engineering. Our warm digest cache loads in ~223s,
   comparable to kindlingai's ~3-minute processed-weight snapshot restarts.
4. **PMU128 prefix-cache patch** (eugr stack; 92–97% hit rates on full-prefix
   hits) — maps to upstream's existing prompt cache; revisit only if our
   cache-hit path ever shows recompute waste.
5. **RecoverSSM, dispram, 3–4-node rings, NFS weight sharing, W4A16,
   single-Spark quants** — different topologies or kernels; no path to us.

## Ease-of-use: our stance vs the field

Entrpi is the community's other "easy button" (one-shot installer with
rollback, 1.29M context at parity) — and it's vLLM-based, which means the
config regime is a `.env` with drift risk between releases; the thread
contains at least one write-up of exactly that failure (configs breaking
under them across upgrades). technigmaai fights the same problem with
discipline: a menu launcher plus `VERSIONS.md` pinning every image.

Our answer is structural, not cosmetic:

- **all knobs are guarded** in `config.sh` (one file, validated, with the
  prepared-marker check) — site identity lives in git-ignored
  `scripts/local.sh` / `docs/SITE.md`, so upgrades can't clobber it;
- **one-command qualification** (`scripts/run-qualification.sh`) with a
  production guard, phase markers, and append-only receipts — reproducibility
  is a default, not a discipline the operator must maintain;
- **every change lands with its receipt** in docs/LAUNCH.md.

That is the line we hold while borrowing: exporter → doc pointer; fairness /
adaptive-k / cliff → measured data for upstream; EXLR8 → watch. Nothing in
this research justifies adding a second config system, a patch ladder, or a
menu launcher to this repo.

## Upstream-watch list (track only — we post nothing to upstream repos)

| item | why | trigger to revisit |
|---|---|---|
| EXLR8 checkpoint loader in TensorFold | EXL3-family; smaller experts, bigger KV | upstream issue/PR appearing |
| adaptive-k or deeper DFlash2 rows (#1059) | acceptance data says depth should flex | engine release notes |
| prefill/decode fairness knobs | if our cliff phase shows deep-prefill stalls | campaign verdict |
| head idle spin behavior | GB10 shared power budget | TF_GLM_PROF window |

## Upstream PRs that bear on our fronts (rechecked 2026-11-12, round 141 cont. 45; perf-gated policy: nothing to bump to)

**The 2026-11-12 read (the subagent sweep, read-only)**: v1.2.7 is STILL the
newest tag (published 2026-11-11 17:18 UTC, target `93a2e93` — our promoted
pin is current); main moved only ~15 commits past it since our check, all
non-inference (#2750 cortheon search/registry parsing — its own changelog
line says "does not reach inference: no lane, sampler, precision or
prompt-processing change"). **#2852 (EXL3 whole-pass routing): still open,
mergeable-clean, but upstream's own device receipts remain queued** ("tf-cuda-test
glm-exl3 on a GB10 with fresh records, then a TP=2 A/B on two GB10s" — the PR
body's own words). **#2856 (batched shared MTP): still open and DIRTY**
against main; only the `glm-mtp-shared-check` device check remains before
THEY land it — and its TP=2 receipts are on the record (the 2026-11-11
07:03 comment: two GB10s, NVFP4+MTP, tokens equal 52/52 in both run
orders, four-stream chat +19.3/+19.6%, code +7.2/+7.8%). **ROUND 152
DESK ADJUDICATION: #2856 CANNOT ENGAGE ON OUR LINE — the port is DEAD
here, not deferred.** The PR batches the MTP head's chained drafts
(`draftShared` is called only from cuda_follow.zig:438 and
cuda_mtp_lanes.zig:84; no `dflash_*` file references `draft_streams`/
`draftShared`; DFlash2's block pass `dflash_block.pass` is ALREADY one
batched pass for all S streams). Our serve passes `--drafter` (DFlash2)
and never runs the MTP head's chains; upstream's own receipts are
"NVFP4 with MTP". The value gate would read flat BY DESIGN — no window
burns on it. Re-opens only if the line ever serves an MTP-drafted
checkpoint. **#2852 (EXL3 whole-pass routing) MERGED 2026-11-12
(`9247585e6`) and is an ancestor of the v1.2.10 tag (verified
`git merge-base --is-ancestor`) — it rode the round-151 bump FREE and
is already in production.** The older "still open" note is withdrawn.

The releases: v1.1.3 (2026-10-23) remains the newest and carries **no glm/cuda perf
content** (round 13's verdict stands); `main` is 136 commits ahead of our pin —
Flash Next/HIP/Windows/app heavy, **nothing glm-perf**. Staged locally instead: the
**GLM slot-leak fix** (upstream `7d330e24d`, #1218 — a released stream left its queued
draw's ring slot taken; every completed/cancelled request leaked a slot until restart;
1-line `patches/glm-slot-leak.patch`, bit-invisible) and the **router-ks2 patch**
(PERF_PLAN Front 2 Lever A2).

**The 2026-11-24 watch check (round 161)**: v1.3.4 is STILL the newest tag —
the release watch (armed at PIN_TAG=v1.3.4) correctly holds. `main` moved
**702 commits past v1.3.4** in three days (39 on the 22nd, 236 on the 23rd,
427 on the 24th — the fastest arc on record; the pre-release climb pattern
suggests a tag is being gathered). The GLM-relevant content, none of it perf-
front material for our line: **#3790's `TF_GLM_VISION_FUSED`** (the image
tower's attention on the shared full-attention kernel instead of two
cuBLASLt products around a softmax — opt-in, OFF by default, and its sums
run in another order so image replies can differ: NOT bit-safe, so the
knob's own note disqualifies the standing config's witness discipline),
**d0fbf6bd's retain-completed-shared-prefixes-on-prefill-cancellation** (a
correctness/efficiency fix on the prompt-cache path worth folding at the
next bump), **1d7cc5fe's wide-factored-decode 64-pair tile match** (opt-in),
and the **#4856 prompt-cache flush retain count** (a `retain` parameter
keeping the most recently used prompt states through a flush — engine-level
resume value on a path our #2699 closed at the API level; watch it). The
rest is MiniMax/Qwen/Flash Next/H3/OCR/app and the host KV tier (#1501) —
other families' fronts. No bump action: the pin holds at v1.3.4 until a
tag lands, and the watch fires on it.

**The 2026-11-24 community sweep (round 161, the read-only subagent scan +
the desk checks on its top claims)**: the full report's items go to the
ledger as candidates; the desk verdicts first —
- **The "sampled traffic gets no drafts" premise is FALSE on our line**:
  the community report's top decode candidate (B1 — Gumbel-coupled
  drafting, motivated by a claimed draftless gap on sampled requests)
  assumed the engine gates drafts on greedy-only serving. OUR engine
  carries keyed sampling natively (`/v1/models` capabilities reads
  `greedy_only: false`) and the draft gate keys ONLY on `--no-drafts`
  (`chat.zig:199`), not on the request's sampling — sampled requests DO
  draft on our serve. The candidate dies at the desk; no window spent.
- **The drafter-precision question stands** (B2): knapcio's FP8-drafter
  linears cut the draft graph 27% with acceptance unchanged; the
  local-inference-lab MXFP8 DFlash2 copy serves token-identical on two
  community stacks. Our drafter serves incoai's BF16 revision — what
  precision our draft path actually computes is a loader/source question
  before any window.
- **The MGEMM/MMA-operand EXL3 prefill mechanism stands as the strongest
  externally-receipted prefill lever** (exllamav3 1.4.8: ~480 →
  2,040-3,926 tok/s on the 170HX rig — 5-8×, decode unchanged): decode
  trellis tiles straight into MMA operands at prefill shapes instead of
  compute-bound dequant. A port-shape ask alongside the standing #1080
  expert-batching one.
- **KX7 exact dense weights (upstream issue #2498, hughmadden, the proof
  branch public)**: 11-bit Huffman two-class pack of the BF16 dense
  linears — replies exactly equal to BF16 (105/105), decode +11-16% solo,
  +6-24% at 2/4/8 streams, rank 0 holds 2.7 GiB less. THE
  EXACTNESS-PRESERVING BRACKET for our DENSE_BITS family — the prior that
  sizes any future dense-bits window's quality risk. Upstream-gated until
  merged; watch it into a release.
- **The single-vs-team trap (Anantus)**: at c4 speculation-on/off are
  EQUAL on their 4xGB10 rig — our serving shape sits exactly at the
  break-even; worth ONE A/A-style arm (drafts-off at c4) if a window is
  ever staged in that neighborhood, not a dedicated window.
- **Do-not-re-propose additions from the community's own negative lists**:
  W8A8 (rounds activations — theirs too), q4 dense (quality — theirs
  too), dual rails ≈ 0, 8-bit draft head no gain, re-tuned 8-bit drafter
  kernels no gain, DSpark drafter −15-20% vs DFlash2 (licensing value
  only, and DFlash2's CC BY-NC-ND terms deserve a standing note).

**The 2026-11-24 upstream sweep (round 161 cont. 1, the second read-only
subagent scan — PRs/issues/changelog verified on main `9a38b1f7b`)**:
the composition picture for the line's next window set —
- **`TF_GLM_INDEX_SPLIT=32768` is IN OUR PIN, bit-safe, and unadopted**
  (the v1.3.4 changelog's #4510; the knob sits at default 2048 in
  cuda_ranks.zig): below the split position the indexer's
  scores/pools/rows stay local per rank with NO blocking all-gathers;
  upstream's own note records 1-2% prefill at 128k. Our serving profile
  (short agent prompts under a 524k ceiling) sits entirely inside the
  local band, so the skip engages on every chunk. Zero-bump: a config
  flip + one order-matched A/B window. NOT in our closed list; no A/B
  receipt exists on our line.
- **`TF_GLM_GRAPHS=1` (#2279, open)** — the only candidate with a
  MEASURED number on our exact topology: GPU idle is 3.6-5.3% of a
  decode window at TP=2 (nsys, two GB10s); graph replay removes it →
  decode +3.3-3.6% at 1/2/4 streams, tokens equal (14/14 incl.
  drafted==undrafted). Composes with our adopted PDL: PDL chains
  dependent launches; graphs delete the host launch overhead — the nsys
  data says the residual class is real even with PDL. DFlash2 taps are
  NOT graphed (partial coverage on the drafted path). The decode
  composition candidate.
- **#4701 (open draft) — Mia's 0078 pipelined prompt experts are being
  MAINLINED upstream**: isolated gu −24% at 4,096 rows; a live 4K-prompt
  cell +40% prefill (noisy). Our 013-zprompt carries the fork's 0078 —
  at the next bump upstream's maintained, contract-gated version replaces
  our hand-port (one fewer member to re-anchor) plus the newer SM121
  pipelining. The #1143 ask is being answered through this line.
- **#4565 MERGED 2026-11-24** — `TF_GLM_WIDE_EXPERT_TILE`: 17+-row
  windows (a DFlash2 block 16 + pending row) re-read the routed-expert
  down weights under the wide tile; bit-equal; the decode A/B (kill
  under +1%) is still to run. Free at the next bump.
- **The rows store (#1411, in Unreleased)** — `--learn-conversations`
  keeps conversation states on disk through evictions and restarts (the
  resume-after-eviction class our record measured at ~1.4 s); **#4694's
  cancel-keeps-prefix** and **#4856's flush retain count** complete the
  resume bundle. Fold all three at the next bump.
- **#4573 (`TF_GLM_PRICED_WINDOWS`)** — measured DFlash2 window prices +
  cost-derived width; the upstream-shaped answer to our standing "depth
  should flex" watch item; the kill bar is stated (+3% or drop).
- **The RECALL receipt question RESOLVED by upstream's own data**: our
  RECALL=0 default is VALIDATED — #4247's lever table measures the copy
  continuation as a NET LOSS on code prompts when present
  (`TF_GLM_NO_COPY`: +4.2-11.2% on code by REMOVING it), and the copy
  proposer is opt-in on our serve (the RECALL flag, default 0). The
  unmeasured-here suspicion closes: the mechanism hurts on code on the
  builds that carry it; our default already avoids it.
- **Gated out, confirmed**: #4541 (`TF_GLM_PREFILL_SHARED_ONCE` — the
  PR's own scope line excludes EXL3), #4695 (skip MTP prompt history —
  our 002-exl3prompt already carries it), VISION_FUSED (bit-unsafe),
  pair-experts (the EXL3 gate), L2PF (flat at our instrument — Mia's
  new default flip on their fork is their posture, our instrument
  governs).
- **The single-vs-team trap (Anantus)**: at c4 speculation-on/off are
  EQUAL on their 4xGB10 rig — our shape sits at the break-even; worth
  ONE order-matched arm (drafts-off at c4) inside a window staged in
  that neighborhood, not a dedicated window.

**Watch list additions (no window owed until they land)**: the #4247
prefill lever PRs one at a time (SOLO_TO_START −4.14% cold 8k, the
one-pass prompt pipeline −4.7/−5.8/−6.5% at 8k/32k/120k on their TP=3
build); the Qwen DFlash2-graphs landing (#4516, MERGED — the precedent
for a GLM drafter-graphs PR: "over a hundred small launches per round"
captured); #4559's hc_shared_fn (our ncu census measured hc_partial
p50 104-115 µs — same neighborhood as our hc-fuse design, smaller
surgery); #4514's native-FP4/FP8 expert conversions + stages3; #4809's
keep_seqs (the slot-reuse zero-fill + prompt-copy at 524k); Mia 1104's
patch 0014 (the DFlash2 selector skips out-of-vocabulary candidate ids).

**The #4493/#4619 pair-experts scoping (round 160, 2026-11-23 — the
measured datum for upstream's own claim)**: the v1.3.4 release's
claimed +15% prompts at 2K / ~+5% at 8K/32K on two GB10s was measured
on the **NVFP4 route**, and the release's own code scopes it that
way: the engagement gate (`cuda_forward_pair.zig:42`, shipped in
v1.3.4) requires `m.exl3 == null and m.routed.format == .nvfp4`, and
the paired kernels route 128-pair NVFP4 expert items
(`cuda_experts.zig`). On an EXL3 checkpoint the pairing cannot
engage — our order-matched A/B (default(1) → TF_GLM_PAIR_EXPERTS=1 →
default(2), campaign-20261123-075710) measured the ON arm at 0/9 pp
cells beyond ±5% against the bracketing defaults, witness identical
on all three arms. Nothing to adopt on the EXL3 line by construction;
the number stands as upstream's own data for the NVFP4 repo's users.

The open PR field, by front:

- **Front 2 (prefill)**: **#1176 — qwen CUDA: `--prompt-precision int8`, prompt matmuls
  on int8 activations (cold prefill 20–27% shorter)** — a measured prefill mechanism on
  the other MoE family; a glm port candidate if our router patch lands and prefill still
  lags. **#1228 — preserve completed CUDA prefill across cancellation and retry** —
  robustness of prefill work, worth watching.
- **Front 1 (concurrency/round economics)**: **#1168 — qwen CUDA: decode attention on
  tensor cores (fp8 and bf16 caches), decode after long prompts** — our kda+mla are 40%
  of a verify round; a glm port candidate. **#1171 — qmmf half tiles for decode calls
  whose 64-column grid leaves SMs idle** — same family of fix. **#1155 (Flash Next's
  shared-round batched drafting) closed UNMERGED**, but its maintainer fix-ups
  (`c4d36404c`, "the shared pass's helpers split out") landed pieces — the mechanism
  precedent our glm ask can cite.
- **Front 3 (memory/paging)**: **#1163 + #1211 — glm/cuda: KV pages from the core pool**
  (`TF_KV_PAGES`). Today every
  stream holds a whole window (3.61 GiB of fp8 latent cache at 524288) and the
  admission refusal's math follows; with paging, streams take 512-row pages from the
  core pool and kept states hold only rows up to their position. **At TP=2 the default
  (`auto`) keeps a window per stream — `TF_KV_PAGES=on` opts us in.** If it admits
  6+ streams at 524288 and the concurrency curve changes, both the ladder ceiling and
  the cliff get re-measured. Heads live on Bizuayeu's fork:
  `Bizuayeu/TensorFold` @ `87e4417ebec6` (`pr/glm-kv-pages-r9`, stacked on #1163).
  Our prepare already takes `TF_REPO`/`TF_COMMIT` overrides — buildable and
  qualifiable as-is, and `config.sh` now forwards `TF_KV_*` to both ranks.
  **Measured on the branch head (2026-10-23, round 9): paging works on the bf16 KV
  path only — the engine exits at startup on `--kv-cache fp8` × `TF_KV_PAGES=on`**
  ("fp8 keeps a window per stream"), so every fp8 KV cell refuses. Under paging the
  engine admits 5, 6 and 8 streams at 524288 with the pool fixed at ~one full window
  (1028–1032 pages, ~6.4 GiB, demand-allocated, ~220 MiB fixed per stream) — depth ×
  streams is the pool's budget, not per-stream windows. All §2 gates PASS on paged
  bf16; the bench favors paged-bf16 over the fp8-window config on every row (+5–9%)
  and the solo row reaches production parity — but without fp8 KV it cannot displace
  dense4fp8 as the serving config (a full-depth stream costs 2× and the pool caps
  deep concurrency at one window). The upstream ask this feeds: **paging × fp8 KV
  for glm/cuda** — with fp8's halved bytes under the pool, a paged config could
  serve deep streams AND high concurrency at once.
- **#1080 — long-prompt prefill 5.4×** (qwen CUDA family): 128→4096-row chunks,
  tensor-core prompt attention on e4m3 rows, and v0.6.6's delta-rule chain —
  75,616 tokens to first token in 144.5 s → 26.9 s on one RTX 5090. Our engine's
  "prompts in passes of up to 2048 rows" and production's +49% prefill lead sit
  exactly in this PR's blast radius. Qwen-targeted today (`BobClawblaw/TensorFold`
  @ `12f8a9c40d53`); a glm/cuda port is the watch item.
- **#1215 — round-class GPU timers** (`TF_Q27_PROFILE=1` logs each round's class GPU
  times, replies carry `gpu_seconds`): the instrumentation pattern our concurrency
  diagnosis wants — route / experts / dense-attention / **drafter** per round. If
  TF_GLM_PROF lacks class timers, this is the shape of the ask.
- **#1079 — DFlash2/lanes decode +9–15% (qwen27) — TESTED HERE, A WASH, DROPPED**
  (2026-10-23, `campaign-20261023-185520/`): the staged patch passed all §2 gates
  ("replies unchanged" holds on our model) and then moved nothing — solo d0 +3.3%,
  solo d4096 −8.6%, rest ±2%. Lesson recorded: **our gates are the "replies unchanged"
  instrument, and the A/B — not upstream's numbers — decides keep-or-drop.** Receipt in
  patches/README.md.
- **#1143 — Flash Next: NVFP4 experts on prompt tiles, decode-form sums, bit for bit** —
  the expert-batching-in-prompt-passes mechanism our prefill gap wants (prompt chunks
  here are 90% router+routed; the router alone is ~910 ms of a 1,892 ms chunk). Family-
  mismatched (Flash Next files) — the glm/cuda port of this mechanism, plus #1080's
  chunking, is the standing prefill ask upstream.
- (#827 — the lane backend, one stream per slot, on DeepSeek/Metal: the architecture
  direction for per-stream concurrency; not our engine today.)

**Plan this buys us:** (1) baseline `TF_GLM_PROF` concurrency diagnosis on the current
build, then (2) build the `pr/glm-kv-pages-r9` head and re-run the campaign against it —
admission (does 6 fit now?), the §2 gates on paged KV (exactness first, as always), and
the throughput curve. The engine code itself stays upstream's; our job is the
qualification receipts.

- 2026-10-27 — **the cross-request prefix-cache gap (TTFT-at-depth), as upstream data** (found
  reading v1.1.6 at `eea9dc9c`; nothing posted upstream): the native engine's prompt cache keys
  states at conversation-structure marks only, and `server/chat.zig` populates `shared_prefixes`
  from the system prefix alone (three cuts at system_len−2048/−512/system_len). Cross-request
  shared prefixes inside user content therefore always re-prefill (linear TTFT), where
  block-level prefix caching (vLLM-APC-style, and our production's python engine) reuses them.
  The span machinery is not a blocker (spans are token-derived); #1321 covers only simultaneous
  arrivals; the `--learn` imprint path exists but is fed only system cuts from chat. A
  grid-boundary marks policy for long prompts is the natural upstream-shaped fix.

- 2026-10-27 (evening) — **v1.1.7 released (2026-10-27, daily cadence: 1.1.5→10-25, 1.1.6→10-26,
  1.1.7→10-27); 120 commits on main since our pin (`eea9dc9c`), 57 in the release**. GLM-relevant:
  in v1.1.7 — a prefill diagnostic (`--prompt-precision int8` fallback counting), the grammar
  compiled once per request, a streamed-tool-call XML newline framing fix (marginal tool-eval
  relevance); no GLM/CUDA perf headline. **Post-1.1.7 on main (unreleased) — the item that aims
  at our line: #1430/#1449 `TF_GLM_INDEX_CUDA=1`** — a prompt chunk's DSA indexer in two dedicated
  CUDA kernels, byte-equal (the kernel contract: byte-equal, stable across repeats, same reply
  tokens), opt-in, `families/glm/cuda_forward.zig` + `cuda_index.zig`. **Upstream's GB10
  measurements: cold-prompt first token 2% sooner at 131k, 9% at 524k, 16% at 1M.** Also on main:
  the prompt cache's find() walks a longest-first index and uses extension links instead of a
  whole-store scan (lookup speed; the MARKS POLICY is unchanged — our round-34 cross-request
  prefix diagnosis remains unfixed upstream and stays our patch candidate), the spill/rows-store
  write-behind + read-ahead work (#1464), Flash Next/Mac items that don't apply.
- 2026-10-28 — **#1449 verified on our hardware, and the depth curve transfers**
  (`campaign-20261028-113509/20-indexdepth.md`): at upstream's own first claimed point
  (131k) we measured **−2.6%** cold-TTFT (claimed −2%); the ladder up to 393k reads
  −2.7%/−3.6%/−4.5%/−5.5% with the flat-ish on-arm marginal slopes (0.816→0.882) against
  the RISING off-arm (0.860→0.976) — cold prefill is superlinear at depth and the indexer
  kernels counteract it. Their deeper points (524k −9%, 1M −16%) sit beyond our ladder;
  our extrapolation at 524k is ≈ −6.5% — same direction, smaller at our depth. Loading,
  decode, and short-prompt TTFT are unchanged (the knob is prefill-side only). Banked as
  an ADOPT-PENDING-GATES (one gated serve owed before our config default flips).
- 2026-10-28 (later) — **the gated serve ran: ADOPTED.** `campaign-20261028-141916/
  22-ixgates.md`: §2 gates ALL PASS under the knob (the byte-equal contract shown on our
  serve), the duel within noise of the v1.1.8 references. Our config default is now
  `TF_GLM_INDEX_CUDA=1`.
- 2026-10-28 (later) — **two upstream-bound data points from the same window**
  (`campaign-20261028-141916/23-gibdisc.md`, `24-spillgib.md`): (1) **`--spill-gib`
  refuses GLM-5.3-Flash outright** — the flag's own words: it "keeps evicted states on
  disk for Nemotron, the Qwen hybrids and Flash Next only on CUDA". The #1464 spill work
  does not cover GLM yet; the churn-heavy agentic pattern on GLM has no disk fallback.
  (2) **`--prompt-cache-gib` did not size the kept-states store on our GB10 serve** —
  GIB=16 → the store read 2.6 GiB with default-identical counters (behavioral, round 47);
  GIB=10 → 2.5 GiB (round 48) — the engine's own default figure either way. One open
  read: whether a smaller CONTEXT frees the budget (one cheap serve, queued).
- 2026-10-28 — **the resume-cost gap is architectural, and the engine already carries the
  remedy shape** (source read at v1.1.8, `zig/src/families/glm/kept.zig` +
  `core/prompt_cache.zig`): the GLM family's prompt cache resumes by COPYING the whole
  kept state back into a stream's pools (`copySnap`), while the engine also carries a
  paged prompt store (`prompt_radix.zig`, `rules.paged` — remap-style resumes) that the
  GLM family does not wire (`engine_paged=false`; the snap_* decls never set paged). The
  python 0.6.x engine's block cache remaps pages (production's 65 ms resume at 7.2k
  tokens vs the native line's ~1,434 ms — measured rounds 43–45). Data point for
  upstream: wiring the paged store for the GLM CUDA family (the backend's page-ownership
  callbacks) is the path to production-class resume times on the native line. Nothing
  posted upstream.

## The Mia 1104 recipe re-read (the (user) 2026-11-27 question; the fourth read of this repo)

**MiaAI-Lab/GLM-5.3-Flash-DGX-Sparks-1104** (the sibling two-Spark recipe,
TensorFold **1.1.9** `f350cd3e` + **121 engine patches** — a DIFFERENT
engine lineage from ours: their pin predates the PDL/1.3.x
reworks; ours is v1.3.6 `f56b1420f` + 17 members): moved to TP=4
(four Sparks on a ring or a switch), a cache-first memory plan,
KV sharding at TP=2 (their 0114, toward upstream #1431), the
#2257 32-row verify windows (their 0115), the L2PF weight
prefetch (their 0117, built into 1.3.0+ upstream), and a large
agent-traffic surface (the tool-call guard 0111, EXTRA_EOS 0120,
THINK_OFF_SPLIT 0121, the effort-line template 0121, DFlash2
selector crash-fixes 0014-0016, learned conversations 0113,
CONTEXT=auto, PROMPT_CACHE_MIN_GIB). Last commits 2026-11-21;
their commits carry Claude co-authorship — an agent-maintained
recipe like ours.

**Every perf lever they name is already IN our promoted tree** —
most through upstream absorption, some through our own store:

- The #2257 32-row verify windows: IN ours (their 0115 was a
  PORT of upstream #2257; upstream landed it at our pin's line).
- L2PF: IN ours (built into TensorFold 1.3.0+, upstream-side;
  our production boot line already prints `L2PF: 176 rows`).
- PREFILL_SHARE (their `PREFILL_SHARE=0.68` mixed-traffic
  fairness): IN ours natively (`TENSORFOLD_PREFILL_SHARE`,
  lane_host_env.zig) — our line can set it without a patch.
- The #2257-class wide verify: our store's 012 carries the
  32-row tile machinery on the EXL3 path directly.
- Their 0014/0015/0016 DFlash2 + KV-shard fixes: ported FROM
  the same upstream commits ours absorbed at v1.3.0-1.3.6; our
  pin's dflash.zig carries the vocabulary check (their 0014's
  fix) via upstream's `checkTokenIds` (`927e5d2bb`).

**Nothing actionable for the perf plan** — their speed work rides
a different engine lineage (1.1.9 + 121 patches vs our v1.3.6 +
17 members) and every lever they measured is already present on
ours through upstream or our own store. Their KV_SHARD (their
0114) is a genuine exception: upstream #1431, NOT in our tree —
but their own measurement on the pair (their 2026-11-07 entry)
was DECODE NEGATIVE (-1.6% at one stream, -3.6% aggregate at
eight) with the gain being pool TOKENS (2x) rather than speed.
Our line's 512k windows and the round-160 evidence on the KV
pool make it a memory-lever, not a speed lever — watch if a
long-context load-out (more streams at depth) becomes the
user-visible need; then it is a port from upstream #1431's
direction, not from their recipe.

**The agent-traffic surface is their genuine gap vs us** — items
we do NOT carry and they do: the tool-call guard (0111/0116),
EXTRA_EOS (0120), THINK_OFF_SPLIT (0121), the effort-line
template discipline (their QA 79.3% -> 86.0% measured), and
CONTEXT=auto / PROMPT_CACHE_MIN_GIB start-time guards. These are
SERVING-QUALITY items (agent-loop robustness), not engine-perf
items: the value gate for any of them would be agent-loop
failure rate, and the round-163 discipline says name the
user-visible number first. WATCH TRIGGER: if agent-loop
malformed-tool-call or double-turn failures appear on OUR line,
their 0111/0116/0120/0121 patch set is the first place to look —
the port cost is small (each is opt-in, byte-identical when off)
and each carries its own host tests.

**Their correctness-fix discipline is the transferable practice**
(not their patches): three crash fixes (0014-0016) were found,
verified on the sibling kit, and shipped with byte-identical
off-state guarantees and host tests — the same shape as our
store's round-trip + compile gates. Their CHANGELOG's
"measured, traps and retractions included" record (RESULTS.md)
is the same discipline as our DELTAS/LAUNCH chain.

## Watch history

The dated release reviews, community sweeps and upstream-watch entries moved to
[docs/watch-archive.md](watch-archive.md) — one entry each, immutable once written.
The living watch state is this file's top; the LAUNCH log cites receipts.


## The 2026-11-12 evening deep read (the (user) horizon review; the read-only sweeps, verified hands-on)

**Upstream (ashhart/TensorFold)**: main moved twice past the morning snapshot
— `6c5cef8941` now, **137 commits past v1.2.7**. No v1.2.8 tag, no release
commit staged. **#2843 MERGED at 13:33Z today — CUDA EXL3 grouped experts
launch and size storage at the caller's tile/pair count** (fixes #2823): the
shared EXL3 grouped path launched its decode grid at the 64-row prompt tile
while decode/verify route at 16 — **three quarters of the decode grid's
workgroups exited at once** — and pair storage was sized 4× a step's need.
Bit-equal outputs, the host steps pass; the served EXL3-MoE check (Qwen
3.6-35B) is still "to run" per the body, but the merge already carries it.
This is our line's kernel territory: free in the next release. #2673 (the
dense-GQA CUDA engine) also merged today — not our MoE path. **#2856
rebased onto today's main and flipped dirty→clean; the review fixes are
in; only the `glm-mtp-shared-check` device check remains before landing**
— and its TP=2 receipts are ALREADY ON THE RECORD (the 2026-11-11 07:03
comment, two GB10s, NVFP4+MTP: tokens equal 52/52; four-stream chat
+19.3/+19.6%, code +7.2/+7.8%; one stream level; prompt level). #2852 is
unchanged (clean) but rides the
maintainer's CI train #3056. **New on our line's radar: #3064/#3062
(explicitly paged FP8 KV for GLM CUDA — OUR adopted mode becoming a
first-class upstream path; implementation done, qualification open),
#3027 (full-prefix repetition penalties), #2894 (NVFP4_NZ5), #3063 (the
full GLM-5.3 on three GB10s), #1583 (the Apache DFlash2 drafter load).**

**The community**: **kindlingai's gr8 is the first real ease-of-use
competitor** — a from-scratch CUDA engine (no vLLM/PyTorch at serve time),
v1.0 released TODAY, 74 stars, one-command Docker for 1-6 GB10s, GLM-5.3/
Flash/DS-V4.1-Flash from their own exlr8 v2 weights. Their 2-box Flash
card: decode 76.5/41.8/93.1 tok/s, concurrent 55.1/70.3/82.9 at 1/2/4,
2.09M-token pool, 25 s warm boot — receipts published, MTP=3 waterfill
drafting (+10.45% pooled concurrent). The honest edges: **no TEB-equivalent
quality evidence published at all**; max per-request context **measured at
262,144** (their 1M path is experimental CP-KV); the exlr8 card's own
warning says the trellis values are E4M3-rounded at encode — a stock EXL3
decoder reads measurably worse weights from the same bytes (format-hostile
to our checkpoints). technigmaai's TEB leader is static since Oct 18. The
thread's new MRCR@400k result (TensorFold 18/34 vs exlr8-vLLM 8/34 fully
correct, p=0.013) supports the TF-native direction at depth. MiaAI's fork
now runs to patch 0121; their 0100/0101 (cp-async stages, drafter knobs)
measured neutral per their own changelog; their 0115 (32-row windows) is
upstream #2257 — **we already mainline it free in v1.2.7**; their L2PF
(opt-in L2 prefetch, +2% one-stream, flat under load) is the one measured
port candidate of theirs. goshi's exporter now names three more native
GB10 engines (velo, flare, tandem) — the field is densifying fast.

## The 2026-11-17 first study: 0rand/glm53-tensorfold-spark (`main-0rand`)

**What it is**: a one-day-old single-author fork (four commits, all
2026-11-17) of the jayleaton-family stack — our patches README's rule-5
line, TensorFold **0.3.4-era** base, far behind our v1.2.9 pin. Its own
work: an **EngineMetrics/Prometheus patch (0710)** — engine-native
`tensorfold:*` request/token/draft counters, five latency histograms
(request/TTFT/prefill/decode/time-per-output-token), shared-KV-pool
gauges (mapped/free/retained/reservations/admission), RAM/SSD
session-store metrics, restore-source breakdowns; instrumentation-only
(no kernel/inference/format changes), CPU-regression-verified (361
passed) on a CPU harness — the README itself states this is not GPU
exactness/perf proof. Plus isolated image tags, a `prod.env` with a
**1.57M-token shared KV pool** at lowered guards (`MEM_GATE_GIB` 108→0,
`BATCH_RESERVE_GB` 11→2), `DEFAULT_EFFORT=max`, per-request context
configured at **1,048,576**, and ToolEval **Q1 93/100** (194/208,
v3.0.1.dev6, 104 scenarios, temp 0.3).

**Against our stack — verdict: nothing to adopt; one watch item.**

- Their Q1 **93/100** sits below our receipted **95/100** (197/208,
  hardmode, campaign-20261116-001527) on the same-scale battery; their
  c1 d0 decode **60.3 tok/s** and prefill ~1,268–1,536 vs our **73.1** /
  **1,528** (directionally informative only — different forks,
  instruments); their P7 shows **c4 collapsing at depth** (d8192 c4 =
  25.0 tok/s) where our c4 is receipted ~167 — their four-way
  concurrency is their config's weak spot, the opposite of ours.
- **The 1.6M pool / lowered guards / 1M context: not carrying.** Outside
  our 524,288 hard boundary; our fp8 paged pool is already token-wise
  larger (~2.1M tokens, 4,100 pages × 512 rows, 13.61 GiB/rank); their
  own README disclaims worst-case safety and per-knob attribution.
- **Image-tag isolation: not carrying** — our intent-keyed ports +
  container names + the `PATCHES` knob solve separation more strongly.
- **Base patches 0640/0650** (thinking alias; keep earlier reasoning in
  prompt): new to our stack but unmeasured even on their side against
  cache reuse; watch only if agent-loop quality failures appear.
- **Watch: patch 0710 EngineMetrics.** The genuinely new idea. The port
  against our v1.2.9 tree is a rewrite-shaped port (hundreds of commits,
  other module layout), and the value gate would be instruments-quality
  rather than a user-visible number. Queue trigger: a concrete instrument
  gap where our goshi `/metrics` surface cannot answer a question (e.g.
  a KV_SHARE or resume experiment we cannot see inside). The attractive
  pieces: KV-pool occupancy and restore-source/restore-latency counters.
- **Notable**: their metrics contract names **Gilesco as a secondary
  reference** — our line is being cited by the community. Recorded as
  data; we post nothing upstream.
- Their README is unusually honest about its own evidence limits (same
  style as ours) — worth re-reading if it grows A/B'd engine changes;
  its one-concern-per-patch style would port into our scheme naturally.
