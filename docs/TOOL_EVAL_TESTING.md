# Test plan: performance first, then quality (phased)

> **2026-10-23: the campaign script (`scripts/run-qualification.sh`) is the primary
> instrument** — phased, resumable, production-guarded; this file's ledger (Status
> below) is where its receipts land. The `run-bench-matrix.sh` phases below remain as
> the manual single-config fallback. **(User) The bar: surpass production 0.6.6 on
> loading time, generation tok/s, and prefill rate.**

**Strategy:** quick performance measurements select the best server configuration; the
scenario suites (tool-calling, Hard Mode) run only on the winner. **No `--hardmode` in
early testing.**

**Rule of the campaign:** within a phase, the bench options are **fixed and identical for
every test**; the server configuration is the only variable. Results and session notes land
as commits in this repo.

## The matrix (server configurations under test)

| Label | `PARALLEL` | `RECALL` | Extra | What it isolates |
| --- | --- | --- | --- | --- |
| `baseline` | 4 | off | — | today's default — the reference point |
| `pdl` | 4 | off | `PDL=1` | programmatic dependent launch on the mm kernels |
| `dense8` | 4 | off | `DENSE_BITS=8 HEAD_BITS=8` | dense/head packed to 8 bits at load (memory + packed mm tiles; exactness gates hold *within* the config) |
| `dense6` | 4 | off | `DENSE_BITS=6 HEAD_BITS=6` | packed to 6 bits |
| `dense4` | 4 | off | `DENSE_BITS=4 HEAD_BITS=4` | packed to 4 bits — the 2026-10-22 leader (55.4 solo); quality gate owed |
| `roce0` | 4 | off | `TF_ROCE=0` | attribution control: the engine's RoCE gather off, NCCL's RDMA transport kept — splits the 1.1.2 engine gain from the transport gain |
| `chan4` | 4 | off | `NCCL_PASSTHROUGH=1 NCCL_MIN_NCHANNELS=4 NCCL_MAX_NCHANNELS=4` | the measured NCCL channel set on the RoCE path (untestable before the transport fix) |
| `dense4pdl` | 4 | off | `DENSE_BITS=4 HEAD_BITS=4 PDL=1` | the leader + PDL |
| `dense4chan4` | 4 | off | leader + `chan4`'s env | the combination candidate |
| `dense4h8` | 4 | off | `DENSE_BITS=4 HEAD_BITS=8` | mixed bits: 4-bit dense, 8-bit head (quality/speed compromise point) |
| `fp8` | 4 | off | `KV_CACHE=fp8` | v1.1.2's prepared fp8 latent cache — speed/memory probe; quality unqualified upstream, bench-only |
| `dense4fp8` | 4 | off | leader + `KV_CACHE=fp8` | the ladder candidate: dense4's speed, fp8's halved per-token KV |
| `parallel6` | 6 | off | — | two more lanes (EXL3 model: 0.71 GiB/stream, 13.3 GiB free after reserve at p4) |
| `parallel8` | 8 | off | — | four more lanes |
| `recall` | 4 | on | — | Recall alone (drafts copy from previously-read text; verified-exact by design) |
| `recall6` | 6 | on | — | both — the candidate "best" configuration |

## The phases

### Phase 1 — quick performance (default; minutes per configuration, not hours)

`PHASE=perf scripts/run-bench-matrix.sh` (the default): the bench runs **`--perf-only`** —
llama-benchy pp/tg throughput and latency against the endpoint, no scenarios. All four
configurations in well under an hour including restarts.

Fixed options (identical every run): `--seed 42 --perf --parallel 4 --timeout 240
--no-live --format openai --model "$SERVED_NAME"` (the config default is
`GLM-5.3-Flash-EXL3`; the tokenizer follows `MODEL_ID`) against `http://127.0.0.1:8001/v1` (this line always serves the testing port 8001).

**Outcome:** the fastest configuration whose latency/throughput profile fits the traffic
(single-stream tg, concurrent aggregate, pp).

### Phase 2 — quality on the winner only

`PHASE=tools scripts/run-bench-matrix.sh <winner>`: the 69 standard tool-calling scenarios
plus `--perf` in the same run — quality and speed from one configuration, no Hard Mode.
Score within noise of the configuration's Phase-1 expectations and of production's anchor
(91/100 was achieved **with** Hard Mode; the standard-only comparison is the 69-scenario
score).

### Phase 3 — Hard Mode, last

`PHASE=hardmode scripts/run-bench-matrix.sh <winner>`: adds the 28 Hard-Mode scenarios
(the production anchor's 91/100 / 177-194 points shape). Only run once Phase 2 passes.

## Procedure

```sh
cd ~/GLM-5.3-Flash-EXL3-2x-GB10-TensorFold-v1.1-testing
PHASE=perf scripts/run-bench-matrix.sh                    # all four configurations
PHASE=perf scripts/run-bench-matrix.sh baseline recall    # or a subset
NO_BENCH=1 scripts/run-bench-matrix.sh recall6            # restart + serve only
```

- Each configuration **restarts the server** (interrupts clients — run in a quiet window),
  waits for `/health` (~4 min), then benches.
- Results land in `results/<run-id>/<label>/` (bench log, `result.json`, the server's own
  memory-model line); `SUMMARY.md` collects the score/perf lines.
- After each run the script clears the recall record, so no configuration inherits
  another's state.

## Reading the results

| Metric | Source | Anchor |
| --- | --- | --- |
| pp / tg tok/s, latency | `--perf` (llama-benchy) | production: 1,829 pp / 63.0 tg single; 78.2 / 67.1 tg at 2 and 4 concurrent (EXL3 stack — external reference) |
| Scenario score | Phase 2/3 output, `result.json` | production: 91/100, 177/194 points **with** Hard Mode |
| Server memory model | `<label>.server.log` | NVFP4-era anchor: model 93.72 GiB; streams 0.89 GiB at 4 / ~1.4 GiB at 6 — **re-derive from the EXL3 server's startup line** |

**Decision rule:** the Phase-1 winner = best tg/pp at acceptable latency; it earns Phase 2.
Phase 2's score within noise (±1 scenario / ~2 points) of expectation → it stands; a drop
→ fall back to `baseline` and re-test. Recall is exact by construction; `parallel6`'s only
risk is memory headroom (~1.2 GiB left — watch `<label>.server.log` and `/health`).

The context campaign (docs/CONTEXT_512K_PLAN.md) is separate and already performance-first
(needle probes); its ladder runs at `--parallel 1` and never touches the scenario suites.

## Status

- [x] RECALL / PROMPT_CACHE_GIB / knob support in the scripts
- [x] 7-config matrix run on **v1.1.0** (2026-10-18, `results/run-20261018-174541/`):
      **dense8 won** (solo 21.2 → 24.0 tok/s, −3.8 GiB model); pdl noise; parallel6/8 no
      gain; recall unrewarded by the fresh-prompt bench shape. Deep-prompt concurrency
      collapse (8.6 agg) structural — see docs/LAUNCH.md's session log.
- [x] ~~v1.1.1 re-baseline~~ superseded: v1.1.2 landed the same week (quick window measured
      1.1.1 greedy 24.7 / sampled 25.9 solo; 1.1.2 rebased over it).
- [x] **5-config matrix on v1.1.2 + RoCE (2026-10-22, `results/run-20261022-154406/`)** —
      every number moved; every restart came up on the RoCE gather (`2 HCA(s) … RDMA
      writes`, no fallback):

  | config | solo tg d0 / d4096 / d8192 | c4 agg d0 / d4096 | pp2048 | free / cache |
  |---|---:|---:|---:|---|
  | baseline | 36.4 / 38.9 / 35.1 | 37.8 / 19.6 | 1,026 | 13.3 / 11.2 GiB |
  | **dense4** | **55.4 / 54.7 / 51.4** | **42.6 / 21.1** | **1,053** | **19.4 / 16.0** |
  | dense6 | 47.1 / 47.0 / 47.2 | 41.3 / 20.6 | 1,042 | 18.4 / 16.0 |
  | dense8 | 43.8 / 41.0 / 43.0 | 40.3 / 20.1 | 1,032 | 17.4 / 15.3 |
  | pdl | 40.0 / 35.6 / 34.6 | 37.2 / 19.4 | 1,028 | 13.4 / 11.2 |

  vs v1.1.0 baseline (657 pp / 21.2 solo / 25.3 c4 / 8.6 c4@d8192): **prefill +56%,
  solo decode +72% (dense4 +161%), TTFT d0 3,117 → 1,995 ms**. Three changes bundled
  (engine 1.1.0→1.1.2, RoCE RDMA up, HCA set) — attribution needs a `TF_ROCE=0`
  control run. dense4's win is clean and monotonic (4 < 6 < 8 < 16 bits), unlike
  1.1.0's dense8-noise. The memory anchor recovered to 13.3/11.2 (1.1.1's 11.0/8.9
  was transient — likely #993's bounded snapshot pages).
- [x] **Search matrix on v1.1.2 + RoCE (2026-10-22, `results/run-20261022-172325/`)** —
  solo decode (d0/d4096/d8192), c4@d4096, pp2048, and the memory line:

  | config | solo tg | c4@d4096 | pp2048 | free / cache | verdict |
  |---|---|---:|---:|---|---|
  | roce0 | 34.8 / 33.5 / 31.8 | 19.3 | 1,028 | 13.4 / 11.3 | the engine's RoCE gather adds ~5–10% solo decode; prefill unchanged → the 657→1,026 prefill jump was NCCL RDMA (vs TCP), not the gather |
  | chan4 | 35.8 / 33.9 / 34.3 | 19.4 | 1,029 | 15.4 / 13.3 | no prefill gain here, decode ≤ baseline at depth; **frees ~2 GiB of NCCL workspace** — a memory knob, not a speed knob |
  | dense4pdl | 47.9 / 48.8 / 47.4 | 20.7 | 1,043 | 19.4 / 16.0 | **PDL hurts dense4** (−13/−11/−8% solo) — opposite sign from baseline; drop |
  | dense4chan4 | 49.8 / 51.9 / 44.7 | 20.8 | 1,044 | 21.3 / 16.0 | **the channel set costs dense4 ~10% solo** for +1.9 GiB — take only if a rung needs the memory |
  | dense4h8 | 45.3 / 47.2 / 47.9 | 20.8 | 1,030 | 19.3 / 16.0 | 8-bit head is *slower* than 4 (−18/−14/−7%) and +0.15 GiB — no reason over dense4 |
  | fp8 | 35.6 / 35.6 / 35.0 | 18.7 | 971 | 13.7 / 12.3 | fp8 caches work (stream 0.71→0.48 GiB); ≈ baseline speed −3% — **a memory knob with a small speed tax** |

  **Standing after two matrices: dense4 alone remains the speed leader; nothing stacks
  on it without cost. The two cheap knobs trade speed for memory (chan4 +2 GiB, fp8
  KV −32% stream bytes).**
- [x] ~~Bench the untested combination: `dense4fp8`~~ — done in the first campaign:
      tool-eval **92 = parity cell's 92** at 524288, 0 errors. Quality risk retired at
      this bench; throughput tables still owed (below).
- [x] ~~Structured-output cliff (MaTeZZ's mechanism)~~ — absent on native 1.1.x
      (schema batch 17.9s vs plain 21.2s). The general solo→c4 flatness is still open.
- [x] ~~Rerun the gates in their fixed content form~~ — done (round 2): **all PASS on
      dense8 AND dense4fp8**. Remaining rigor item: confirm the g3 cache hit via
      `/metrics` (`cached_tokens=0` in usage on both arms — field likely unwired).
- [x] ~~Throughput tables for the fp8 cells at 512K~~ — done (round 2, table above).
- [x] ~~**Qualify dense4**~~ — **done**: kvqual4 all-PASS + tool-eval 92 = parity +
      throughput lead. dense4fp8 is the qualified 512K config.
- [x] ~~Climb with the trimmed prompt cache~~ — done (entries below): the ceiling is the
      engine's own admission arithmetic, not a knob fight.
- [x] ~~Concurrency at depth — the one big open item~~ — resolved as a **bench artifact**
      (round-6 entry below): steady-state aggregate decode RISES with streams
      (c4 ≈ 99–110 t/s, matching production's derived 103.7); the tg128-at-depth rows
      were prefill-polluted by their own TTFT.
- [x] **KV-pages branch test — resolved** (#1163+#1211 @ `87e4417e`, image
      `glm53-native-tf:commit`): round 9 (`campaign-20261023-170125/`, 17:01–18:20):
      - **fp8 KV × `TF_KV_PAGES` are mutually exclusive** on the branch (the engine exits
        at startup; round-8A receipt `campaign-20261023-165319/`) — paging is bf16-KV only.
      - **All §2 gates PASS on paged bf16 at 524288 × PARALLEL=4** (content form: g1–g4
        PASS, g5 content-stable) — exactness holds under paging. The no-paging control
        refused with the engine's own arithmetic ("4 streams need 19.77 GiB, budget
        leaves 12.06: serve --parallel 2").
      - **Admission: 5, 6 and 8 streams at 512K** (window-mode: 5 on fp8, 2 on bf16). The
        pool is fixed at ~one full window (1028–1032 pages, 6.40–6.42 GiB), demand-
        allocated; each stream costs ~220 MiB fixed (180 without the drafter; DFlash2
        adds ~2.8 GiB of model). Depth × streams is the budget — "enough for one at a
        524288-token window".
      - **Bench (same instrument both configs)**: paged-bf16 leads the fp8-window config
        on every row — solo d0 51.4 vs 48.3 (+6%), c2 43.2 vs 41.3, c4 42.0 vs 38.7 (+9%),
        d8192 c4 14.1 vs 13.3, pp ~1,037 vs 1,025, TTFT ≈ equal. The solo row reaches
        production parity (51.0–51.4 vs production's 51.6). Rows stay the TTFT-polluted
        instrument; the steady-state probe on paged KV is owed for the true curve — and
        the bench loads at most c4 clients regardless of server streams, so the 5/6/8
        rungs measured ADMISSION, not >4-client load.
      - **Verdict**: a shallow-many concurrency option on bf16 — NOT a serving-config
        replacement (no fp8 KV → a deep 512K stream costs 2×, and the pool caps deep
        concurrency at one window). The head's pin came out; marker back to main
        (1351ed16). Upstream ask: paging × fp8 KV for glm/cuda.
- [x] **PR #1079 A/B — a wash, dropped** (`campaign-20261023-185520/`): the staged
      shared-lanes decode patch passed all §2 gates ("replies unchanged" holds here) but
      moved nothing that matters: solo d0 +3.3%, solo d4096 −8.6%, rest ±2%, pp/TTFT
      unchanged. Receipt in patches/README.md; knob removed from local.sh.
- [x] **Knob sweep — done, one sharp lead** (`campaign-20261023-200302/`, the `knobs`
      phase): `TF_GLM_PROMPT_STEPS=0` (prompt passes run whole) took **c2 @ d8192
      aggregate 17.3 → 33.1 t/s (1.9×)** — the d8192-c2 row is tight across five rounds,
      so the jump looks real; c4 unchanged, solo d0 dipped. conf085 solo +3.8% (weak —
      the duel's acceptance/ITL instruments decide). conf055/overlap6/kdawide0: no
      effect. **Loading decomposition**: the engine loads in 241.5–253.5 s across all
      cells (walls 251–269 s — orchestration is only ~8–17 s; the drafter ~11 s), so the
      2.7× gap to production's 93.7 s is the native loader's convert-and-pack path —
      patch candidate: a packed-weights cache beside the byte-verify digest cache.
      The drafter's decode value confirmed: 29.6 vs 49.9 t/s solo without it.
- [x] **steps0 CONFIRMED and ADOPTED as the serving default (round 139 cont. 9, the
      `confirm` phase, campaign-20261108-214221)**: two independent restarts of
      `TF_GLM_PROMPT_STEPS=0` (dense4fp8 @ 512K x4) — d8192 c2 **48.2/37.0** t/s vs the
      17.3 baseline (the original lead was 33.1; the criterion "near 33 reproduces, near
      17 retires" is EXCEEDED), d0 58.1/56.8 vs 49.9, d4096 c2 31.0/31.3 vs 24.0. The
      within-campaign control (the callquotequal bench, no steps0) read d8192 c2 23.8 —
      the delta attributes to the knob. The same-bits greedy sha held on the ported
      serve (the callquotequal arm) — the knob does not move the deterministic probes.
      `config.sh` adopts `TF_GLM_PROMPT_STEPS=0`.

- [x] **Loading time — behind 2.8× and unexplained** (part of the knobs phase): — CLOSED (rounds 126-135: the boot decomposed; the loading front CROSSED at 112.9%, re-dated 83/83 s on v1.2.6 — the anchors' row; campaign-20261109-000818, campaign-20261110-162034).
      production 0.6.6 logs **"loaded in 93.7 s"**; our restart walls run ~265 s. The
      knobs phase records each cell's engine "loaded in" line vs the wall — isolating
      the drafter's share (load-nodraft cell), the packing share (the engine's own
      lines), and the orchestration overhead (wall − engine).
- [x] Small hygiene: worker clock probe reads 0 via ssh (acpi_cppc path?); g3's — FIXED/closed (the probe repaired and receipted round 139; the g3 half closed at cont. 29; the ledger's own L220-224/232-236).
      `/metrics` cache-counter check (goshi's exporter maps `tensorfold_cached_tokens_total`).
- [x] ~~Phase 2/3 quality on **dense4fp8**~~ CLOSED (round 132): the hardmode
      battery ran on the cell twice (campaign-20261102-095700: 93; the sweep's
      per-pack windows), the scenario receipts carry the failing-TC detail; the
      production-side comparison: CLOSED (cont. 22) — production's current-bench
      hardmode anchor landed via prodbench (production FOR TESTING on 8001, the
      same bench_cell instrument): **94/104** (campaign-20261102-213954) — the
      served TR3 TIES it at 94; the battery's saturation warning (--parallel 2)
      recorded on both sides alike.
- [x] ~~Small hygiene: worker clock probe reads 0 via ssh~~ FIXED (cont. 29):
      `ssh host bash -c "$snippet"` let the remote shell word-split the probe —
      its second line ran standalone with $f unset and echoed 0. The probe now
      feeds the snippet via stdin (`bash -s <<<"$snippet"`); the worker
      delivers 3834 MHz, the head 3892 (healthy X925). Remaining hygiene: the
      g3 `/metrics` cache-counter check — **the counter is FOUND (cont. 13):
      `tensorfold:prompt_tokens_cached_total` ("prompt tokens of finished
      requests restored from kept prompt states") exists in /metrics (294
      lines); the API usage field stays 0 (the known gotcha) — the /metrics
      counter is the wired instrument.** The nonzero reading (a resume hit)
      rides the next window with resume traffic; consider
      pinning the upstream ref in prepare so receipts stop drifting with HEAD.
- [x] **The g3 `/metrics` cache-counter check — CLOSED** (round 133, cont.
      16): `tensorfold:prompt_tokens_cached_total` read **126,976** after
      resumecost's resume traffic (the pre-restart capture,
      campaign-20261104-213422) — the counter is fully wired; the API usage
      field stays 0 (the known gotcha), /metrics is the instrument.
- [x] **One-command campaign** (`scripts/run-qualification.sh`, 2026-10-23): preflight →
      production reference probe → parity cells → fp8-KV exactness gates (VALIDATION §2)
      → depth probes → structured-output cliff → prefill probe → 524288 rung → summary.
      Phased (`.done` markers, `PHASES=` selectable), production-guarded, `bash -n` clean.
      This script IS the open items above: dense4fp8 + dense4 qualify in one window.
- [x] **Ecosystem research pass** (2026-10-23) — docs/ECOSYSTEM.md: repo-by-repo findings
      from the thread + READMEs. Adopt now: goshi's TensorFold metrics exporter (targets
      our engine line directly), GID_INDEX unpinned as invariant, clock probe (in the
      campaign). Measure & hand upstream: adaptive-k acceptance, prefill fairness,
      structured-output draft truncation (the cliff). Watch: EXLR8 exl3-trellis experts.
      Ease-of-use stance held: no second config system, no patch ladders.
- [x] **The v1.2.1 engine bump + the hardmode baseline** (round 132, 2026-11-02):
      TF_COMMIT → 1db3edb (tensorfold-native 1.2.1 both hosts, pinbump PASS);
      gates g1-g4 PASS, depth 12/12, prefill within noise of standing, PARALLEL
      5/6/8 refused at 512K (climb/climbP retired — the (user) cap at 4). The
      hardmode-instrument campaign (the (user) hardmode-only directive, the
      standard batch rides inside): **the standing config (dense4fp8, Focus,
      vision) 93/104** — the cell's best hardmode receipt (ties the
      effort-tail-era 93); dense8+fp8 88/104 (TC-99 partial + TC-101/104).
      Standard tool-eval 95 (dense8 cell, the morning campaign) — recorded as
      tool-eval, never cross-compared. Owed: production's current-bench prodqual.
      → CLOSED (cont. 22): **prodbench** — production's current-bench hardmode
      anchor on the clean 8001 (production FOR TESTING, the duel's choreography,
      the same bench_cell instrument): **94/104** (campaign-20261102-213954) —
      the served TR3 TIES it; the phase retired, its receipt stands.
      The bpw4sweep (the 4bpw local packs, one per window): **Mia-AiLab 4bpw
      94/104** (production's own family, the best) · **Focus 93** · **AZ 90**
      (017-topk4b applies on v1.2.1; the perf leader) · TR3 **94** (the sweep complete: TR3 94 · MIA 94 · Focus 93 · AZ 90;
      **the 3bpw track CLOSED on the engine's 4-bit expert floor** — the CUDA
      family reads 4-bit EXL3 experts: turboderp 3.05bpw refused (campaign-
      20261102-180405), sc_3.10 skipped as pack-generic, androidli's
      TensorFold-native mcg refused too (campaign-20261102-184142; it served on
      the python-era 0.6.0 only) — sub-4bpw on the native line is upstream-
      gated on the family's reader;
TR3 posts the best top-8 decode — tg128 46.0/46.2/45.2 — and dominates the
Focus on both axes; the scorecards:
docs/bpw4-sweep-cards.svg from docs/bpw4-sweep.tsv, generated). The
served-default swap (Focus -> TR3) is asked of the user with the cards.
- [x] **The v1.2.1 knobs A/B + the duel re-pair** (round 132, 2026-11-02,
      campaign-20261102-195440 + -210117): the duel re-paired onto the served
      TR3 cell (both engines on the clean 8001, same window — the first pair
      needed the **stack-stop fix**: the knobs phase leaves our stack on 8001
      and production-for-testing's start refused "port 8001 already in use";
      the duel now stops our stack first — the (user) autonomous-flow rule):
      **solo 110% CROSSED** (64.4/64.2 vs 58.5/58.6), c2 127% (110.3 vs 87.0),
      c4 80% (152.6 vs 192.0 — production's range 155-241), ITL 109% (15.6 vs
      17.1 ms/token), overhead 91% (201 vs 183). The knobs (results/knobsv121/):
      **CS `TF_GLM_CHUNK_SOLO=4096`** — real decode gains (tg d0 +5.1%,
      d4096 +8.7%, d8192 flat) at a real trade (+1.87 GiB model, the prompt
      cache halved 3.3→1.9 GiB) — **the adopt call is the user's**;
      **VH `TF_GLM_VISION_HOST=1`** — REJECTED (two arms noise-to-negative:
      −6.7/+5.3/−6.1 then −8.9/+12.6/−7.1 tg; the model sheds 0.82 GiB but the
      prompt cache grows 3.3→3.4-3.5 — net free +0.2 GiB only). The VH arm's
      vision sanity (the repoed assets/vision suite): **vision INTACT** — all
      four detail answers correct at 1024 tokens; the targeted leg's 3 empties
      were the probe's 64-token cap under thinking (the instrument fixed to
      1024, cont. 20a), not a tower fault.
- [x] **The CS adopt-vs-hold call** — CLOSED (cont. 23, user): **HOLD** — the
      gains land on fronts already crossed (solo 110%, c2 127%); c4 (the one
      front behind, 80%) doesn't move; the +1.87 GiB / halved prompt-cache
      trade is paid at the 512K×4 admission margin with an unmeasured
      multi-turn risk. The knob stays available as an env, never the default.
- [x] **kvshare121 — the #1732 pages mechanism A/B** — CLOSED (cont. 27): the fp8×pages
      pair is a DESIGNED non-combination on mainline (the engine's admission
      line: "--kv-cache fp8 keeps a window per stream: unset TF_KV_PAGES, or
      set it to auto or off" — campaign-20261102-233025; pages require
      bf16/auto). Two invocation receipts along the way (the release's "n" is
      a count placeholder; KV_CACHE=bf16 is not a legal value — empty is the
      bf16 spelling, and omitting KV_CACHE leaks config.sh's fp8 default).
      The bf16 mechanism arm SERVED (campaign-20261103-000653): the on-demand
      pool (2050 pages of 512 rows, 12.76 GiB), 18.5 GiB left (+3.5 vs BASE) —
      but the warm same-session TTFT is a WASH (0.3047 vs 0.302 s) and solo
      bench decode costs ~5-10% on bf16 KV; the concurrent bench rows are in
      noise. **NO ADOPTION — the standing fp8 config stays**; the bf16+pages
      shape is receipted as available. Landed along the way: the BASE
      warm-resume re-measurement — cold 7.22 s → warm 0.302 s at 8,414 tokens
      (the same instrument definition as the anchors' WARM row; the v1.2.0-era
      1.42 s was 4.7× slower — the row corrected to 302 ms / 70% with both
      receipts cited).
- [x] **campaign-20261105-113129 — the marriage's second pagedchecks**: the — SUPERSEDED by the third pagedchecks (THE SERVING PATH WORKS — the ledger's next item).
      logical fix did NOT resolve the death (identical TokenUnits, rank-1
      first, all three sites fixed); the debug patch (glm-zz-debug-
      tokenunits) launched to log the exact mismatch inputs.
- [x] **campaign-20261105-114648 — the marriage's third pagedchecks: THE
      SERVING PATH WORKS** (the logical fix held; the debug patch never
      fired): 11 requests, page-level 512-row resume (ttft 7.500/0.898/0.862
      and 13.191/1.812/1.709 s on the resume chains), the cold fills 46,108
      → 0.82 ms/tok and 92,240 → 0.80 ms/tok (the windowed rate unchanged at
      depth), the pool pressure mechanics live. The probe FAILEDs are the
      instrument's parse.
- [x] **The max_tokens=1 sha references WITHDRAWN (cont. 33)**: seed jitter, — DONE (the withdrawal itself was the completion).
      not depth signatures (9e04a49e5786 dominates across depths and seeds;
      the unique shas are sampling flakes). The bitwise instrument
      redesigned — greedy + thinking-off + 64-token chains (deterministic
      logits fingerprints); **windowedsha v1 (campaign-20261105-123923):
      the serves all passed and the ttfts are a no-regression receipt
      (the cold 46,109-token fill 35.49/38.21/38.03 s on B/P/A — paging
      adds ~nil), but the sha capture grepped $LOG (= campaign.log, which
      never carries engine request lines) and the verdict block died under
      set -euo pipefail — the shas are lost, not recoverable.** The fixed
      phase (docker-logs capture, pipefail-guarded assignments) re-ran as v2
      (campaign-20261105-130738): **ran clean, MISMATCH on all three serves**
      (B/P/A all differ; P≠A is the same-tree paging toggle) — but the
      DFlash2 drafter's per-request sampling varied the verify-batch shapes
      (rounds/accepted wildly different on identical prompts), and
      verify-batch numerics make even a greedy target's chain
      seed-dependent. v3 (campaign-20261105-133550) pinned seed=42 + a
      determinism control serve (B2): **the control MATCHED (identical shas
      AND identical drafter profiles) and B reproduced across windows — the
      instrument is deterministic, and the verdict is REAL: standing ≠
      marriage-unpaged ≠ marriage-paged. BYTE-IDENTITY REFUTED on both
      comparisons** (the paged fetch kernels and the windowed load path
      tile the reductions differently — same stored values, different fp
      accumulation order; the drafter conditions on the target's state,
      corroborating independently). NOT a defect — the same class as
      absorb's adopted fp32-summation change. The composed candidate
      (absorb + marriage) initially FAILED to apply (cuda_glue.zig ×2
      Kernels hunks — absorb's latent_mma fields drifted the trailing
      context); RE-ANCHORED (2026-11-05: the paged fields before merge, the
      init calls after chunks_32_fp8, absorb's lines untouched; 1,217
      lines; the fresh composed apply-check OK; applies AFTER absorb only,
      alphabetical). The debug patch RETIRED (the file removed); the
      pagedchecks/windowedsha session phases retired per the rule.
      **pagedquality (campaign-20261105-141241): hardmode 74 vs the >=94
      bar — FAIL, and the raw logs show why: CROSS-REQUEST CONTENT
      CONTAMINATION** (TC-104's VPN answer contains TC-103's cart analysis
      verbatim; <think> markers leak mid-content) — the paged pool serves
      recycled pages carrying stale KV rows to new requests. The collapse
      concentrates in the long-context capabilities (toolset-scale 89→25,
      state-tracking 6→1, concurrency 6→3); vision 4/4 (short prompts, no
      pressure); per-turn latency improved. This REINTERPRETS the v3
      bitwise mismatch (cont. 35/36): serve-history-dependent
      contamination, not kernel tiling — the correction is logged. The
      marriage is DISQUALIFIED for serving pending the pool-bug fix.
      **treequality (campaign-20261105-152436): 95 on the UNPAGED marriage
      tree — IDENTICAL to the standing config's 95; the tree's kernels are
      quality-neutral and the bug is exclusively the paged pool's
      recycling.** Mia's 0026-0033 carry no pool fix (re-read); the base's
      bf16 paged path passed the gates historically — the bug is E4M3-page-
      state-specific. PRIME SUSPECT: the keep/restore state-slicing math
      (stateSizes/pagedBytesOf/the snapshot host's E4M3 keep test); second:
      the prompt-cache eviction on paged states. Next: a code-reading
      session on those paths; the battery re-runs as pagedquality2 once a
      fix candidate exists. **poolcanary3 (campaign-20261105-173936): the
      format bisect DECISIVE — bf16-paged PERFECT (5/5 exact codes; the
      base's shared paged multi-chunk machinery is correct), fp8-paged
      broken page-history-dependently (fresh pages: hallucination; recycled:
      previous rounds' rows surfacing; one round correct where the recycled
      rows were near-identical) — THE READ PATH RETURNS PHYSICAL PAGE
      CONTENT rather than the written rows: an E4M3-specific write-visibility
      or write-address failure. poolcanary4 in flight: TF_KV_POISON=1 (the
      NaN refill erases stale content — uniform garbling = the reads miss
      the writes; an unchanged pattern = the stored content is wrong) plus
      the chunk-1-vs-chunk-2 code-position split. **poolcanary4
      (campaign-20261105-181641): bf16+poison 6/6 exact (the design
      validated); fp8+poison COHERENT garbles, never NaN-mush — the stored
      content is wrong-but-finite: the quantize/scales/write-content path,
      NOT write visibility; AND the engine CRASHED (rank 1
      CudaContextLost, round-1 late, the recycled+poisoned pages).**
      glm-zz-dumppages ran (the dense reads sane; the write printf silent
      — which exposed the real bug): **THE ROOT CAUSE — the DSA Tables'
      page_rows = c.ps/(l.lw*2) = 3,481 instead of 512** (the whole-page
      stride over the bf16 row bytes; the formula assumes a per-layer ps
      and the tests' fixtures use one, masking it): the selection kernel
      indexed pt[row/3481] and read PAGE 0's pooled keys for every row
      below 3,481 — the sparse lists garbage, the model attending to the
      wrong tokens. **THE FIX (003-fp8-pages-pagerows.patch, 47
      lines): E4M3 page_rows = latent.chunk (512) at the three Table
      sites; bf16 keeps its formula (its lists are page rows).** The
      CudaContextLost crash: the selection's garbage indexes under poison.
      poolcanary4 under the fix (campaign-20261105-192124): **fp8 round-1
      early CORRECT under poison (MKR-1QX — before the fix, code-blind) —
      the page_rows fix cures the selection**; the CudaContextLost crash
      REMAINS poison-specific (the NaN in the unwritten KV region breaks
      the E4M3 selection's index output; the bf16+poison control clean —
      the E4M3 selection path is the NaN-fragile one: a separate
      robustness gap, upstream-relevant). **poolcanary5 (campaign-
      20261105-194159): 10/10 EXACT CODES — chunk 1 and chunk 2, five
      rounds of recycling, no crashes: THE MIS-READ IS FIXED.**
      **pagedquality2 (campaign-20261105-195559): hardmode 75** (the bar
      ≥ 94; the pre-fix 74) + **the vision 4/4** — the mis-read is cured
      but a NEW failure mode: **degenerate token loops in long
      generations** (TC-62: 51,967 tokens ending "…alendar, calendar…"
      — 79,525 chars of reasoning, no answer; TC-49: " " to the 16,384
      cap; finish=length at 99% draft acceptance). total_tokens +60%
      (662k→1,064k), token_efficiency 0.30→0.15, the multi-turn
      capabilities collapsed (constraints 10→3, state-tracking 5→1,
      concurrency 6→3) — while median_turn_ms IMPROVED (6,830→5,993 ms).
      The audit: not a page_rows repeat; pks≠0 only under TF_GLM_KV_HOST
      (inert here); the decode Tables are covered by the fix;
      dense_limit = i_topk+kpool-1 — the canary's decodes sat ON the
      dense/sparse boundary, the battery lives beyond it.
      **pagedecode re-run (campaign-20261105-223622): CLEAN BOTH SIDES,
      shas identical** — pages on/off produced BIT-IDENTICAL replies on
      the tiny/3.3k/16k prompts, the 12k decode (tok/s 94.6 on / 95.3
      off), M1's turns, and the 16k-resumed thinking request: **the
      greedy decode is numerically identical on the paged fp8 stack out
      to 12k depth.** The loop turns alternate (TC-62: turns 2/4/6 blow
      up ~80K chars, 1/3/5 behave) and run from ~1.4-2K-token prompts
      whose history carries the PRIOR loop's ~20K tokens of repetitive
      text (the harness feeds the full output back).**pageconc
      (campaign-20261105-231751): THE LOOPS ARE REPRODUCED FAITHFULLY** —
      the harness replay (TC-62+TC-49, the battery's exact flags) fails
      on fp8-paged (TC-62: turn 8 hit the 16,384 ceiling with 72,502
      chars of reasoning — the loop lives in the reasoning channel;
      19,458 tokens over 8 turns; final_score 50) and is healthy on
      pages-off (TC-62 passes with 5,043 tokens / 12 turns and TC-49
      751 — IDENTICAL to the standing run's numbers: **the marriage's
      non-paging changes are exonerated**; final_score 100). The
      synthetic concurrent pair was bit-clean — concurrency is NOT the
      co-trigger. The reproducer is cheap now (one harness command, ~5
      min). **pagebisect
      (campaign-20261106-000548): bf16-paged CLEAN — final_score 100,
      TC-62 passes (5,188 tokens / 12 turns, zero truncated notes). THE
      BISECTION IS COMPLETE: fp8+pages LOOPS; bf16+pages, fp8+no-pages
      (marriage, = standing numbers), and the standing stack are all
      CLEAN — **the loop is an INTERACTION bug: the E4M3 format × the
      paged read/selection path, only on long thinking decodes** (the
      same family as the page_rows bug, a second member). The fix
      target: the E4M3 paged latent read / sparse selection under long
      decodes; the instrument: the ~5-min harness replay. (user,
      2026-11-06) continue autonomously, fold in v1.2.3 when
      appropriate — the agent's plan: fix on the current pin first, then
      rebase as its own arc. The hunt's opening moves: the CUDA-index
      quick path ELIMINATED (off by default, prompt-sized-only); the
      assembler bypasses the table for E4M3 (logical positions,
      PAGE=512 consistent); the onsets are early (tokens 500-1,650) at
      no common boundary, the loop token is a prompt's tool-schema name,
      and the replay's runaway is a SOFT loop (72.8% acceptance) vs the
      battery's hard loops (99%) — one disease, a severity spectrum.
      **pagehunt
      (campaign-20261106-004057): the instrument receipt** — the loop
      reproduced under the debug build (fp8: TC-62 fail, turn 3 → the
      ceiling, 72,000 chars of reasoning; bf16: final_score 100 ✓). The
      SEL dump: **the fp8 selection's page-start attractor** (every
      dominant top-4 at a 512-multiple; (5120..5123)=page 10 recurring
      across pos 2,048-10,368 for ~18% of layer launches; the bf16
      control's dominants vary per position ✓) **AND causally impossible
      selections** ((17408..) at pos 2240 — no request had 17K tokens of
      history) — while the scores kernel's per-pool mask reads correct
      and the pooled-key writer/reader addressing agrees. Instrument
      artifacts identified (stale scratch at count=0; the ~4,000-line
      printf FIFO cap). (user) workflow directive: all tasks first, one
      launch last, dark until complete. **pagehunt2
      (campaign-20261106-014222): the build consumed the STALE v1 patch
      (no npool/VIOL in the container's lines — the v2-format analyzer
      matched nothing; "VIOL 0" was the analyzer, not the mechanism).
      The OFFLINE analysis of the saved v1-format dump: **2,684 of
      3,641 sparse selections (74%) emit tokens beyond the row's
      causal limit** (t0=2560 at pos 2112; frozen on (9216..) across
      pos 2240-3904; 49.2% of tops on 512-page starts), the loop
      ignites right past the sparse boundary (npool ~= K) — while BOTH
      kernels read causal in source (the scores kernel masks per-pool;
      select_rows scans NP = min(np, max(vis, K))) ⇒ the corruption
      lives in the state BETWEEN the kernels. TC-49 also looped this
      run (both scenarios hit the ceiling; final_score 25; bf16 clean
      100). **pagehunt3
      (campaign-20261106-023748): the instrument delivery failed AGAIN
      (the container ran the v1 patch a second time — two same-name
      updates, two stale builds); the fix per the lesson: a NEW file
      name (glm-zz-dsasel3.patch; the old name retired, the README
      carries the series). The fresh dump reconfirms the signature:
      **47.6% of sparse selections emit out-of-horizon tokens**, frozen
      on (35328..)=page 69's start across pos 2,240-3,264 (no request
      had 35K tokens of history; the prior run froze on 9,216 — fixed
      stale/unwritten slots at config-deterministic addresses). TC-62's
      loop hit its FIRST generated turn this run; final_score 25; bf16
      clean 100. **pagehunt4
      (campaign-20261106-031244): the instrument delivered (the new file
      name worked) — and it KILLED the selection-causality hypothesis:
      the select kernel's outputs are causal in 1,254/1,254 samples
      (PICK), the assembler's VIOL detector printed 0 (the E4M3 logical
      lists are clean) — the out-of-horizon SEL lines are pt≠0 launches
      (physical page-row lists, a different token-unit stream; the
      earlier 47-74% "violations" mixed that stream in). THE LOOP BUG
      FOUND in the source: the prefill's sparse selection receives tk
      (no .logical — physical lists for E4M3) while the prefill's
      sparse attention receives t (logical — it table-maps the token
      values AGAIN: pt[pt[page]]) — idempotent on identity page
      mappings (every fresh-serve probe bit-clean; the canary's prompts
      even sat under dense_limit) and corrupting once pages recycle
      (the battery's churn): the model mis-attends from the first
      sparse rows and long thinking generations loop. THE FIX:
      006-selist-fix.patch (34 lines) — tk carries .logical =
      c.ls != 0 (E4M3 lists stay positions end-to-end; bf16 unchanged).
      **sparsefix
      (campaign-20261106-035856): THE FIX VALIDATES COMPLETELY** — the
      harness replay **final_score 100** (TC-62 passes 5,043 tokens /
      12 turns — byte-for-byte the standing run's profile; TC-49 751;
      zero truncated notes; the loops GONE on the recycled-page churn
      that reproduced them 4/4 runs before) + **the sparse-prefill code
      probe 5/5 exact** (the code at ~row 3,650, beyond dense_limit, on
      recycled pages — the prefill's sparse path exercised explicitly
      for the first time reads perfectly). The mechanism stands
      confirmed. **pagedquality3
      (campaign-20261106-043015): THE BATTERY GATE CLEARS — hardmode
      **95** (production parity; the bar ≥ 94) + **the vision 4/4**;
      **total_tokens 662,693 — byte-identical to the standing run's
      662,693** (the pre-fix paged run was 1,063,881 — the loops gone,
      zero scenarios over 8k tokens); token_efficiency 0.30, worst
      category 89% (both standing); **deployability 74 (standing 73)**;
      **median_turn_ms 6,381.8 vs 6,829.6 — 6.5% faster**: production-
      parity quality WITH the pages' speed win. The loop arc is closed.
      **duelpaged
      (campaign-20261106-052114): THE DUEL GATE CLEARS (mixed-favorable)
      — solo 63.5/63.2 vs 58.5/58.6 t/s (**108.5%**; the pages cost
      ~1.5% vs the absorb-only 110%), c2 110.6 vs 87.1 (production's
      volley 87-111, this run at its floor), c4 154.8 vs 154.6
      (parity), **ITL 15.7 vs 17.1 ms/token — CROSSED (109%)**, TTFT
      overhead 199 vs 186 (93%), **the cold depth d8192 5,215 ms /
      slope 0.612 vs 17,129 / 2.026 — 3.3× CROSSED** (the pages'
      overhead +1.8% vs the absorb-only 5,122/0.602). The anchors
      re-paired for the paged candidate and the chart re-rendered; the
      README's stale "mutually exclusive" claim corrected.
      **pagedgates
      (campaign-20261106-054902): ALL §2 GATES PASS on the fp8-paged
      final stack** — g1 determinism (content), g2 drafted=plain, g3
      resumed=fresh (the resume path correct), g4 concurrent=solo (4/4),
      g5 sampled determinism. The last pre-adoption gate clears. **THE
      ADOPTION (2026-11-06, the receipts-equal-or-better protocol
      satisfied on all four gate families: gates §2 all pass, the 512K
      window on the paged stack, the duel mixed-favorable, hardmode 95 +
      the vision 4/4): config.sh defaults TF_KV_PAGES=on + the 4-patch
      PATCHES list; the README carries the TF_KV_PAGES row; seven
      unpaged-semantics sites pinned TF_KV_PAGES=off explicitly; the
      DELTAS engine row updated. The adoptsmoke bare-config smoke test
      CAUGHT A REAL GAP on its first run (campaign-20261106-061130):
      the serve line was window-mode fp8 — config.sh's TF_KV_PAGES was
      an unexported shell variable, and env_args() forwards TF_KV_*
      from the ENVIRONMENT (env | grep) — the bare start never carried
      it (the phases' env-var form exports, which is why they worked).
      THE FIX: export TF_KV_PAGES in config.sh (one word; the explicit
      off pins override it). The smoke re-launched. The v1.2.3 rebase is the next arc. **THE v1.2.3 REBASE IS DONE
      (cont. 67)**: all four patches re-anchored onto v1.2.3 (6ec5fa4cb)
      — v1.2.3's tables() helper consolidation absorbed the marriage's 3
      Table sites + pagerows' 3 + selist's 1 into one helper edit each;
      the native explain() table re-anchored; glue unchanged between
      tags. Verified byte-identical on a fresh v1.2.3 checkout. The pin
      (local.sh TF_COMMIT) bumped to the commit sha for the window;
      v1.2.2 stays the qualified default until the receipt.
      **v123qual (campaign-20261106-065920): THE v1.2.3 REBASE
      VALIDATES — THE ADOPTION** — the replay 100 with the standing
      run's exact token profile (TC-62 5,043/12 turns, TC-49 751; zero
      truncated), the probe 5/5 exact, hardmode **95** + the vision
      4/4, total_tokens 662,693 BYTE-IDENTICAL to the standing run's.
      The pin stays on v1.2.3 (6ec5fa4cb); config.sh/README/DELTAS
      re-based; glm-zz-dsasel3.patch retired (the mechanism receipted
      twice). **v123perf (campaign-20261106-080743): BOTH KNOBS
      RETIRED** — CHUNK_SOLO=4096 REFUSED beside the drafter (the
      refusal is the receipt; upstream's ~7% is drafter-less), COPIES=1
      pure parity (within ~1% of the standing absolutes everywhere) —
      no config.sh change. The rebase's perf spot-check PASSED (the
      copies1 arm rides the v1.2.2 absolutes). **kvqual4P + depth
      (campaign-20261106-081942): the depth ladder 12/12 on the adopted
      paged v1.2.3 stack — the post-adoption re-qualification COMPLETE;
      the §2 gates ALL PASS on kvqual4P's original bf16-paged cell (it
      predates the marriage — not the adopted fp8 cell's receipt).
      **pagedgatesv123 (campaign-20261106-084338): ALL §2 GATES
      PASS on the fp8-paged rebased stack** (the same answer tokens in
      g3 as the v1.2.2 run) — **THE v1.2.3 ARC IS COMPLETE: the
      receipt set fully symmetric** (gates fp8-paged + bf16-paged ALL
      PASS, depth 12/12, hardmode 95 + the vision 4/4, the replay 100
      + the probe 5/5, the perf parity). The session phases retired.
      **kvshare (campaign-20261106-090311): the knob retires at
      N=4** — the solo warm resume DEAD PARITY (the pool-page store's
      per-resume cost is not faster than the host store's), the
      content IDENTICAL, and the concurrent 4-prefix resume MISSED in
      both arms (cached=0 ×8, 13.9 s = four cold prefills) — the host
      store's lines expose the cascade eviction (4 × 182 MiB > 679
      MiB; each warm miss re-keeps and evicts the next). The receipt
      LOCALIZES the concurrent-resume gap to store capacity/eviction.
      **kvshare2 (campaign-20261106-092703): THE CAPACITY FIX
      WORKS** — N=8 held all four prefix states as 16 pool pages
      through the live streams (zero eviction), the solo warm HIT
      (1.84 s vs the host arm's miss), and the concurrent volley hit
      4/4 (cached=2048 ×4, the aggregate 7.41 s vs the host arm's
      12.29 s — −40%; the per-request cost flat under concurrency, the
      round-123 serialization confirmed cleanly). **kvsharequal (campaign-20261106-093921): §2 ALL
      PASS (g3 receipts the pool-page resume path — the same answer
      tokens), hardmode 95 + the vision 4/4, total_tokens 662,693
      byte-identical — **ADOPTED: config.sh exports
      TF_GLM_KV_SHARE=8** (the pool reserves 1025 pages for the store;
      the README carries the row; DELTAS updated). The bare-config
      smoke test (adoptsmoke2, campaign-20261106-103510): the knob
      ACTIVE in the bare config (the pool-pages store signature, the
      probe OK — the export fix verified), the pool arithmetic matching
      the receipted kvshare2 shape (4100 total, dynamic carving) —
      **THE KV_SHARE ARC CLOSED END TO END**. **THE RE-SWEEP
      (campaign-20261106-112022, the (user) ask): all four packs on the
      SHIPPING stack — TR3 95 (the served pack, 3 points clear),
      production's stock 92, the Focus 92, the AZ top-4 87 at the top
      perf (pp 1,295, tg_d0 60.8, tg_d4096 65.7); the round-132
      v1.2.1 ranking (94/93/94/90) held and STRENGTHENED — the tsv
      transplanted, the cards re-rendered as the CURRENT ranking, the
      README/DELTAS re-framed (the first resweep window burned on an
      env-pair quoting bug, cont. 79).** **THE PACKED-S2 ADOPTION
      (cont. 85-86): the mms2 A/B (campaign-20261106-174454) — the
      content shas IDENTICAL across arms (the bit-exactness claim
      verified), pp +3.4/+5.8/+6.7% GROWING with depth, tg parity —
      and mms2qual + the duel re-pair (campaign-20261106-185208): §2
      ALL PASS, hardmode 95, the vision 4/4, solo 109.2%, cold d8192
      5,034 ms (slope 0.591), overhead 96%, prefill 1,150 — **ADOPTED
      (config.sh's PATCHES then the 5-patch stack): the anchors
      re-paired and the chart re-rendered.**
      **THE EXL3PROMPT ADOPTION (cont. 87-89): the exl3call A/B
      (campaign-20261106-201824) — the content shas IDENTICAL across
      arms, pp +24.5/+22.7/+23.3% at d0/d4096/d8192 (two runs per arm,
      near-zero spread) — EXCEEDING Mia's +12.6-16% combined claim (the
      GB10 converts better than their sm_120); exl3qual + the duel
      re-pair (campaign-20261106-212157): §2 ALL PASS, hardmode 95 (the
      FIFTH consecutive), the vision 4/4, solo 108.9%, cold d8192 4,134
      ms (slope 0.482), overhead 96%, ITL 15.5, prefill 1,434 (94.4% of
      production's 1,518 — the front took 76% → 94.4% in one patch) —
      **ADOPTED: config.sh's PATCHES is the 6-patch stack; the anchors
      re-paired and the chart re-rendered.** The bare-config smoke
      (campaign-20261106-225025): the bare default serves the adopted
      stack — the prepared fingerprint names all six patches on the
      v1.2.3 pin, the serve line carries both signatures (the
      2048-row prompt passes, the pool-pages prompt cache), the probe
      replies 'smoke-ok-6patch' exact — PASS.
      **THE ATTNFETCH8 ADOPTION (cont. 93-96): the attnpref A/B
      (campaign-20261107-010849) — the content shas IDENTICAL on three
      prompt sizes AND the 2048-token decode replies (369 vs 369
      tokens: the keys are the same bits, the quality instruments
      cannot move); bench pp +1.7/+3.6-4.3% and tg
      +2.9/+3.3/+4.7/+5.8/+10.9% at every depth cell (d4096 solo
      +10.9% the largest; d0 tg -1.4% the noise cell); the
      steady-state probe read parity but CANNOT resolve single digits
      (integer-second walls on a ~9 s request — its pairs mirrored
      each other); attnqual + the duel (campaign-20261107-020420): §2
      ALL PASS, hardmode 95 (the SIXTH consecutive), the vision 4/4,
      the duel re-paired — solo 109.4% (64.2/65.0 vs 58.7/58.8, beyond
      the 0.2% band), c4 157.4 (+2.4%), the cold d8192 3,942 ms
      (slope 0.458, -4.6% = 434% of production's true cold) —
      **ADOPTED: config.sh's PATCHES is the 7-patch stack** (the patch
      NAMED glm-zz- to sort after the stack — the image applies
      patches alphabetically; the first attnpref window burned on
      exactly that); the anchors + DELTAS + README re-paired, the
      prefill front 94.4% → 96.0%.
      **THE MOESIDE ADOPTION (cont. 97-100): the moeside A/B
      (campaign-20261107-083254) — the content shas IDENTICAL
      everywhere incl. the 2048-token essay replies; the steady-state
      probe RESOLVED (the off arm 51/51 s, both on-runs faster: 40.2 →
      41.4 tok/s avg +3.0%, 4/4 sign-consistent — matching the claim's
      transfer math); the bench corroborating on the solo cells
      (+2.9%/+3.1%) with depth concurrency flat; moesidequal + the
      duel (campaign-20261107-092913): §2 ALL PASS, hardmode 95 (the
      SEVENTH consecutive), the vision 4/4, the duel re-paired — solo
      65.9/66.2 vs 58.7/58.8 (**112.3%**, +2.9% over the ATTN8 pair,
      two instruments agreeing), c2 113.1 (129% of the floor, past
      production's top volley), c4 158.6 (+3.2% across three duels) —
      **ADOPTED: config.sh's PATCHES is the 8-patch stack**; the
      anchors + DELTAS + README re-paired (solo 112.3%, ITL 110%, the
      cold 429%, prefill 96.0%).
      **THE v1.2.4 REBASE QUALIFIED (round 135): the 8-patch stack
      rebased onto v1.2.4 (267c5af6a) + 008-loaddirect (the layer
      loads on checkpoint.direct) — the v124val receipts
      (campaign-20261107-125114/-132414): the §2 gates ALL PASS, the
      arms content-identical, zero strict-TF_ refusals (#2405 passes),
      hardmode 95 (the eighth consecutive), the vision 4/4, the decode
      and pp flat. Two burns on the way: the TF_GLM_KV_SHARE→TF_KV_SHARE
      rename (v1.2.4 mainlined the store; the floor moved to
      4×PARALLEL — config exports TF_KV_SHARE=16) and the direct path's
      silent off (the ninth patch missed the PATCHES list once; the
      served TR3 pack's 120 shards exceed max_sources 64 — a
      byte-identical reshard to 55 is the fix, the next window
      re-verifies). **THE LOADING FRONT CROSSED (cont. 7,
      campaign-20261107-150250)**: the direct reads engaged on the
      resharded 55-shard pack (the witness line fired), the timed
      walls **83/83 s vs production's 93.7 — 112.9%** (the v1.2.3-era
      wall 103 s = 91%; the direct reads took 20 s off), hardmode 95
      (the NINTH consecutive), the vision 4/4, the gates ALL PASS, the
      arms content-identical to the byte (the same greedy sha as the
      pre-reshard windows — the reshard's tensor bytes proven identical
      end to end), the decode and pp flat. The loading row re-paired in
      the anchors (112.9%) and the chart re-rendered; the duel rows
      stay v1.2.3-era — the v1.2.4 duel re-pair re-dates them.
      **THE 0030 PORT QUALIFIED AND ADOPTED (round 136, the
      moefusequal A/B — campaign-20261107-172250)**: 012-zmoe-fuse
      (Mia 1104's 0030 — a decode window's MoE glue fused:
      tf_glm_topk_group = the select + the compact picks + the EXL3
      grouping in ONE 1024-thread block; the grouped experts core with
      NO slot-row copies — two 2D copies, tf_exl3_group, put_slot and
      glue.combine GONE; the shared expert's row summed LAST in
      tf_exl3_down_combine, glue.combine's order) + the one-width
      grouped EXL3 decode tiles (grouped_body_v2 k6r8/k8r8 + nt4) +
      KDA's f_b/g_b in one launch (glm_mm*_16x2). TF_GLM_MOE_FUSE=0
      unfuses (envOn, default ON — the switch ported from 0031; a
      TF_GLM_* getenv knob, no #2405 surface). The A/B: BOTH arms the
      SAME 10-patch image, the knob flips the path — **the arms'
      greedy content IDENTICAL** (the same 80cc3802… sha as every
      window), **the §2 gates ALL PASS, hardmode 95 (the TENTH
      consecutive), the vision 4/4**; c4 **166.1 vs the OFF arm's
      159.4 (+4.2% — our best c4)**, c2 117.1 vs 115.9 (+1.0%), ITL
      58.4 vs 59.3 ms/chunk (−1.5%), solo flat (67.7/67.4 vs
      67.2/67.5), prefill flat (the prompt path untouched by design —
      the bench pp d0 1,468), the load walls unchanged (83/87 s).
      **ADOPTED: config.sh's tenth patch** (the anchors re-paired to
      the ON arm — solo 115.2%, c2 134.4% of the floor, c4 107.2% at
      production's floor, ITL 115%, cold 434% — and the chart
      re-rendered; production cited from the same-day v1.2.4 duel
      campaign-20261107-163011). The port's 4 re-anchored hunks and
      the engine-knob wiring (0031's) are receipted in
      patches/README.md. **THE ZMOE-FUSE DUEL RE-PAIRED (cont. 3,
      campaign-20261107-183530 — both engines the same window)**: solo
      **67.6/67.5 vs 58.6/58.6 — 115.4%**; c2 **117.3 vs 110.3 — 106.3%,
      above production even at its top-of-range volley** (its floor
      87.1 — 134.7% there); c4 **168.8 vs 154.7 at its floor — 109.1%,
      our best c4 again** (the chain 153.7 → 157.4 → 158.6 → 160.2 →
      166.1 → 168.8); ITL **14.6 vs 17.1 ms/token — 117%**; overhead
      189 vs 185 ms; the cold d8192 3,961 ms, slope 0.460 — 433%.
      Every row holds the A/B's adoption read same-window; the anchors
      re-paired and the chart re-rendered. The prefill front stands at
      96.0% — the fusion is decode-side; the prefill lever is the next
      scope (the fork's untriaged 0033+ tail).
      **THE EXL3P PORT QUALIFIED AND ADOPTED (round 137, the
      exl3pqual A/B — campaign-20261107-200411)**: 013-zprompt (Mia
      1104's 0078+0079 — the prompt experts' main loop reworked:
      compiled for an item's 8-member column blocks NBA 1..8, the next
      k tile's trellis decode issued among the current MMAs across the
      stage barrier, each thread's cp.async pieces fixed per item
      (TLoads), the mcg mask one LOP3 (mcg2), 4-bit tiles from the
      lane's word and its neighbour's (decode_a8), fwht128 epilogues
      one FFMA per butterfly (fwht128f), Xd one 8-byte and y one
      16-byte store; the fork measured the kernels **gate/up 1.177x,
      down 1.161x** at 2,048 rows). TF_GLM_EXL3P=0 resolves the classic
      _cl kernel twins (the pre-port loop kept verbatim; envOn, default
      on). The port's fidelity is LINE-VERIFIED (every one of 0078's
      added lines verbatim in our port — 244/244 .cuh, 18/18 .cu —
      except the documented 4-bit-only adaptations) and the contract
      records re-measured per 0079 with OUR OWN sm_121 cuobjdump
      verifying 122/122 on our nvcc 13.3 build. The A/B: BOTH arms the
      SAME 11-patch image, the knob flips the path — **the arms' greedy
      content IDENTICAL** (the same 80cc3802… sha as every window), the
      §2 gates ALL PASS, **hardmode 95 (the ELEVENTH consecutive), the
      vision 4/4**; **THE PREFILL LEVER REAL** — the bench pp d0 1,495
      (the ON arm; the last three windows read 1,458-1,468) and the
      duel_arm TTFT slope 0.458 → 0.447 (−2.4%) agree on ~2-2.5%
      whole-prefill: **the front moved 96.0% → 98.5%** (1,495 vs
      production's 1,518). Decode flat within the arm spread (c2 117.3
      vs 118.1, c4 166.8 vs 167.6, ITL 58.4 vs 58.6 ms/chunk; the solo
      68.5-vs-66.8 spread — the OFF arm the highest solo ever recorded,
      the ON arm inside history, the prompt loop decode-inert —
      run-order drift, a watch item for the duel re-pair). The load
      walls unchanged (83/87 s); the campaign log's 20 warning-pattern
      lines are the image rebuild's CMake feature probes (benign).
      **ADOPTED: config.sh's eleventh patch** (the prefill anchor row
      re-paired to 98.5% and the chart re-rendered; the decode rows
      stay paired to the zmoe-fuse duel until the duel re-pair that
      follows re-grounds them same-window).
      **THE EXL3P DUEL RE-PAIRED (cont. 2, campaign-20261107-211404 —
      both engines the same window, the adopted 11-patch engine)**:
      solo **68.2/68.3 vs 58.6/58.7 — 116.4%** (the A/B's solo watch
      item SETTLED — the adopted engine reads at the top of its range,
      the A/B's 66.8 was run-order drift); c2 **118.1 vs 86.4 at its
      floor — 136.7% there** (above its top-of-range volley ~110-111
      even there); c4 **168.9 vs 188.2 at a warm-cache high — 109.0%
      at its floor, our best c4 again** (the chain 153.7 → 157.4 →
      158.6 → 160.2 → 166.1 → 168.8 → 168.9); ITL **14.7 vs 17.4
      ms/token — 118%**; overhead 185 vs 182 ms; the cold d8192
      **3,845 ms, slope 0.447 — 445%** (the exl3p lever shows at depth
      too, and the duel's own slope re-confirms the prefill gain
      same-window). The anchors re-paired and the chart re-rendered.
      **THE 0080 PORT QUALIFIED AND ADOPTED (round 137 cont. 4, the
      0080qual A/B — campaign-20261107-214342)**: 014-zs2 (Mia
      1104's 0080 — the packed prompt GEMMs' loads fixed once a block +
      8-bit codes to bf16 pairs in fewer steps: mm_kernel's P2 — each
      thread's cp.async sources/destinations/bounds worked out once a
      block, a stage adds its group's offset, the weights still load
      before griddepcontrol.wait — and bpairs8_fast, two LOP3s + one
      rounding-free bf16x2 subtraction, the same values; the other
      glm_mm instances compile to the same SASS). TF_GLM_MM_P2=0
      resolves the classic _128s2_cl twins (envOn, default on). The
      port: 11 of 12 hunks clean, the rejected template hunk
      hand-applied keeping v1.2.4's signature (the fork's base carries
      0073's xtile — P2 does not use it), the fork's text otherwise
      line-verbatim; our cuobjdump CONFIRMS the fork's register claim
      (glm_mm8_128s2 122 → 125); no record work (the _128s2 kernels
      unlisted). The A/B: BOTH arms the SAME 12-patch image, the knob
      flips the path — **the arms' greedy content IDENTICAL** (the same
      80cc3802… sha as every window), the §2 gates ALL PASS, **hardmode
      95 (the TWELFTH consecutive), the vision 4/4**; **THE PREFILL
      FRONT CROSSED** — the bench pp d0 **1,519 vs production's 1,518 =
      100.1%** (the chain 1,458 → 1,468 → 1,495 → 1,519; the duel_arm
      TTFT slope 0.448 → 0.441 = −1.6% agrees) — **the last uncrossed
      (user)-bar front falls**. Decode flat within the arm spread (c2
      117.1 vs 118.7, c4 167.4 vs 168.0, ITL 57.7 vs 57.9 ms/chunk,
      solo 68.5/68.3 vs 68.6/68.2 — both arms at the top of the range).
      The load walls unchanged (86/89 s). **ADOPTED: config.sh's
      twelfth patch** (the prefill anchor row re-paired to 100.1% and
      the chart re-rendered; the decode rows stay paired to the exl3p
      duel until the duel re-pair that follows).
      **THE P2 DUEL RE-PAIRED (cont. 5, campaign-20261107-225124 —
      both engines the same window, the adopted 12-patch engine)**:
      solo **68.0/68.1 vs 58.5/58.6 — 116.2%**; c2 **118.6 vs 110.2 at
      its top-of-range volley — 107.6%, our best c2** (its floor 86.4 —
      137% there); c4 **168.9 vs 154.8 at its floor — 109.1%, our best
      c4 held three windows** (the chain 153.7 → 157.4 → 158.6 → 160.2
      → 166.1 → 168.8 → 168.9); ITL **14.7 vs 17.1 ms/token — 116%**;
      overhead 183 vs 185 ms; the cold d8192 **3,803 ms, slope 0.442 —
      450%, the best yet**. Every row holds the adoption reads
      same-window; the anchors re-paired and the chart re-rendered.
      The prefill row stands at the 0080qual reading (100.1% — the
      duel carries no bench rows; the duel's own slope 0.442
      re-confirms the prefill gains at depth).
      **THE SHFL DUEL RE-PAIRED (cont. 9, campaign-20261108-010714 —
      both engines the same window, the adopted 13-patch engine)**:
      solo **67.2/67.7 vs 58.6/58.5 — 115.2%**; c2 **118.0 vs 110.1 at
      its top-of-range volley — 107.2%** (its floor 86.4 — 136.6%
      there; the record 118.6 stands); c4 **168.0 vs 154.5 at its
      floor — 108.7%** (the record 168.9, held at 168+ four windows);
      ITL **14.8 vs 17.1 ms/token — 116%**; overhead 183 vs 184 ms;
      the cold d8192 **3,812 ms, slope 0.443 — 449%**. Every row holds
      within noise — the SHFL adoption was decode-neutral on the duel
      instruments too, as the A/B read.
      **THE (USER) MODEL-CARD BENCH RAN (cont. 8's commission,
      08-modelcard.md — the full battery in the same campaign)**:
      tool-eval-bench `--perf --needle --hardmode --parallel 4`, seed
      42, ~66 min wall — **final 95/100** (104 hard-mode scenarios:
      Trivial 100%, Easy 94%, Moderate 100%, Hard 91%, Very Hard 79%);
      **needle 80.0% (16/20), effective context ~174,762 tokens
      (estimated)** on the 524,288 window — all depths retrieved at
      ~170K, 14 of 15 cells at ~340K/~510K (the misses cluster at the
      extreme corners); the perf cells pp d0 1,511 / tg 56.5 solo /
      48.5 at 4-stream. **MODEL_CARD.md completed at the repo root**
      (no site identity — postable; the needle artifact's engine table
      carries the host name — the card does not quote it).
      **THE 0082 PORT QUALIFIED AND ADOPTED (round 138, the 0082qual
      A/B — campaign-20261108-024926)**: 016-zstep (Mia 1104's 0082
      — the exl3r dependent-launch chain on the adopted 0081 base: the
      decode chain's kernels launch with programmatic stream
      serialization, each launch and its prologue overlapping the
      predecessor; hazard rules as pdl5's; new kernels k8r8p/k8r16p,
      Load SHFL_PDL). TF_EXL3_PDL=0 turns it off (the fork's own
      knob). The port: 7 of 9 hunks clean, the 2 .zig hunks
      hand-applied (the tilesFor pdl field on our single uniform_k2
      form, the chain insert after our act_mode check), the fork's
      text otherwise line-verbatim (15/15 .cu, 43/43 .cuh, 17/17
      .zig); register-neutral on our sm_121 build (rot_in 19,
      gateup_epilogue 40, the p kernels 79 = the s kernels — no
      record work). The A/B: BOTH arms the SAME 14-patch image —
      **the arms' greedy content IDENTICAL** (the same 80cc3802… sha
      as every window — the fork's 108/108 exactness confirmed), the
      §2 gates ALL PASS, **hardmode 95 (the FOURTEENTH consecutive)**,
      the vision 4/4, prefill flat (the bench pp d0 1,528, inside the
      band). **The fork's measured chain gain did NOT transfer to our
      shape** — c2 118.0 vs 119.1, c4 169.6 vs 170.4, ITL −0.3%, solo
      flat: the launch-COUNT reduction of 0030 transferred at
      concurrency; the launch-OVERLAP of the same kernels doesn't (the
      second decode-side non-transfer). **ADOPTED anyway**: bit-safe,
      knobbed, neutral everywhere, and the fork's 0083+ builds on this
      exact base.
      **THE 0081 PORT QUALIFIED AND ADOPTED (round 137 cont. 8, the
      0081qual A/B — campaign-20261107-232039)**: 015-zshfl (Mia
      1104's 0081 — the exl3r read-once trellis: the grouped decode
      kernels' lanes each loaded the two words their windows span,
      every trellis word fetched twice; now one 128-byte warp load a
      tile + __shfl_sync hand-off, the next tile issued a tile ahead,
      the mcg mask in a register). TF_EXL3_SHFL=0 restores the old
      choice (THE FORK'S OWN KNOB — no _cl twins needed). The port: 3
      of 4 hunks clean, the tilesFor choice line hand-adapted to our
      single Layer.uniform_k2, the fork's text otherwise line-verbatim
      (14/14 .cu, 97/97 .cuh, 12/12 .zig). The A/B: BOTH arms the SAME
      13-patch image — **the arms' greedy content IDENTICAL** (the
      same 80cc3802… sha as every window), the §2 gates ALL PASS,
      **hardmode 95 (the THIRTEENTH consecutive)**, the vision 4/4;
      prefill flat (the read-once kernels serve decode windows only —
      the bench pp d0 1,525, inside the noise). **The fork's measured
      decode gain did NOT transfer to our shape**: the c2/c4/ITL/solo
      cells read FLAT within the arm spread (c2 118.1 vs 118.2, c4
      168.1 vs 168.2, ITL −0.3%, solo flat) — the L2-gather saving
      matters on their cold-expert trains, not our hot hierarchy; the
      first fork claim not to transfer (the prefill-side claims went
      three for three). **ADOPTED anyway**: bit-safe, knobbed, neutral
      on every instrument here, and the fork's 0082 (the chain as
      dependent launches) builds on this exact base.
      **THE STEPLINK RETIRED (cont. 103-104): the steplink A/B
      (campaign-20261107-105455) — the content shas IDENTICAL
      everywhere (no arithmetic changes, as claimed) but the gain at
      PARITY: the steady-state +1.0% avg inside the probe's ±2% (3 of
      4 runs at exactly 50 s), the bench tg mixed-sign (−2.5% to
      +2.7%, noise), pp flat. The mechanism is real but
      sub-resolution on our shape: a 1-row window does one gather
      either way (the solo instruments cannot see it by construction)
      and the verify-window round trips are cheaper than the claim's
      context assumed; the patch stays staged for a future
      re-judgment if 0030's fusion changes the economics. The
      bare-config smoke
      (campaign-20261107-103127) PASSed complete on the first try:
      the prepared fingerprint names all eight patches on the v1.2.3
      pin, the serve line carries the signatures, the probe replies
      'smoke-ok-8patch' exact. The 0010 fetch corrected
      the plan's citation: it is a 7-line correctness patch (the
      side-stream drain), not the perf lever; the fork's prefill-class
      lever is the 0009+0033 packed-prompt/pair-launch line (the design
      pass is the next sitting's opener).
      **poolcanary v1 (campaign-20261105-163035):
      clean but INCONCLUSIVE** — its ~790-token prompts never crossed the
      store's 2,048-row keep grid (every request resumed at 0; the adopt
      path never fired). **poolcanary2 in flight**: grid-crossing prompts
      (~2,100-token preamble), the long+short fired CONCURRENTLY, three
      serves (paged / paged store-off / unpaged) — a short reply naming a
      prior round's code is contamination, and the store-off split
      identifies the channel. The code reading: the pool is refcounted
      (leases + the store as holders), leaving a RANK DIVERGENCE in the
      store lifecycle (rank 1 has no pool, never reclaims) as the prime
      suspect — only concurrent traffic exercises it.
- [x] **THE #256 PORT LANDED AND ADOPTED (round 138-139, the forum thread post 973's finding)**: the unoffered-tool-call leak — with parallel_tool_calls false, a call to a tool the request did not offer was dropped and the one-call filter removed what was left, so the reply came back empty and a fixed-seed agent looped; the fix (upstream be8bccbec, PR #415) is in v1.0.0..v1.2.1 and was REVERTED before v1.2.2, so every 1.2.x including our promoted engine lacked it. The port (010-tools256, the round-139 FIFTEENTH patch) turned out small: the rest of the #415 rework (Policy.parsedContent/kept/wholeEnvelope/prose_sent/the attach rework) was already in our v1.2.4 tree — only callName's own-name rule was reverted with it; a well-formed unoffered call now goes out under its own name (the client answers "unknown tool", the model self-corrects), names that are no function name and non-finite arguments stay text, bare JSON outside an envelope still needs an offered name. The primary witness: the tool-parse host suite 46/46 PASS (two older tests that pinned the reverted rule flipped to the #415 behavior); the tools256qual battery (campaign-20261108-140329): the same-bits greedy witness IDENTICAL (the same 80cc3802… sha as every window), the §2 gates ALL PASS, hardmode 95 — the SIXTEENTH consecutive — the vision 4/4. ADOPTED in this repo's config and mirrored to the promoted production repo (production commit 270adb9). Server-layer only: no kernel work, no knob (the behavior IS the fix). ALSO this round: the promotion repo was created without image/ — every prepare-time build failed reading the dockerfile behind docker's layer cache until the window's fingerprint move forced one; the 7 files restored verbatim (production 8ca3773) and production re-landed healthy on 8000 through its own start.sh; deep's poke local.sh was missing the promotion's PROD_REPO (the poke's :? guard exited every tick) — fixed and the poke smoke-verified silent from cron's own host.
- [x] **The fp8+pages marriage (the Mia fold-in #3) — IN PROGRESS** (round — LANDED (003-fp8-pages is a standing patch; fp8 paged KV is the serving mode — the v126val battery serves it).
      133, cont. 23; (user): "Proceed"): the port is scoped and started.
      **Scope correction**: the marriage is patches **0017-0025** (~1,460
      lines — the E4M3 latent-cache kernels, the page layout, the pool
      admission, the contract tests); 0026-0033 are separate decode
      optimizations (the EXL3 load-ahead, the MoE-glue fusion, the step-link
      work) that rode their stack — NOT part of the marriage. The cumulative
      stack-apply maps 16 rejected hunks across ~12 files, centered on the
      KV pool core + the snapshot layout (rank-pairing-critical,
      boot-refusal class). METHOD: scratch-repo per-patch commits — 0017 is
      DONE (the paged E4M3 fetch woven into v1.2.2's restructured inline
      `load_kv`: the byte-wise `__nv_cvt_fp8x2` decode keeps the window's
      arithmetic; unpaged compiles to page=0/row=src — identical; scratch
      commit b592905). REMAINING: 0018 (440 lines, 8 files — the page layout
      + pool + snapshot centerpiece), 0019 (the pool admission), 0020 (the
      contract tests), 0022-0025 (the DSA block, the paged chunks twin, the
      page-id checks, the comments) — 0021 applied clean. The candidate
      config: KV_CACHE=fp8 + TF_KV_PAGES=on. The value on our 512K×4 spec:
      the shared pool's free list feeds the prompt cache (the warm front's
      kept states) and the admission becomes elastic; the worst case is
      unchanged. The judgment window: the gates + the memory shape + the
      instruments, same as every adoption. **0018's map (cont. 24)**: the
      KEY find — v1.2.2 ALREADY carries the paged-pool machinery
      (`TF_GLM_KV_SHARE` "keeps prompts as KV pool pages: set TF_KV_PAGES=on",
      `fw.State.initPagedFormat`, `Pages.pool/leases/promise/finish`) — the
      marriage adds the E4M3 shape to existing infrastructure, not new
      machinery. Per-file: cuda.zig (+1 import), cuda_start.zig (the
      `paging()` flip: fp8+pages pages, `BadKvPages` for unknown values),
      cuda_native.zig (the BadKvPages/PoolTooSmall explains + 2 test
      rewrites — our extra `GlmKvHostNeedsPages` tail preserved),
      cuda_pages.zig (`pageBytes(e)`/`pagedState(e,at)` + the PoolTooSmall
      admission check), cuda_state.zig (`pagedBytesOf` — our stateSizes
      signature needs checking — + the init literal's `.kv8/.head` fields),
      cuda_snapshot_layout.zig, glm_snapshot_host.zig (+81 lines: the E4M3
      paged keep/restore test), glm_family_host.zig (the test step). The
      semantics: fp8+pages goes from refused-by-name to paged (one shared
      pool: a stream takes the pages its request needs; 6,380 bytes/token
      E4M3 beside DFlash2 vs 13,056 bf16).
- [x] **ABSORB_MMA — ADOPTED AND CLOSED** (round 133, cont. 21): the
      hardmode re-take on the ABSORB-only shipping config reads **95/104**
      (campaign-20261105-003101 — the 95 was not the tables' artifact; the
      serve line's ABSORB-ON shape, the wall flat at 103 s). The full
      receipt chain: the deep fills −6.8/−7.0/−6.9% (campaign-20261104-
      213422), the small prompts −5-6% (campaign-20261104-233541), greedy
      byte-identical everywhere, the vision 4/4 (campaign-20261104-234405),
      the duel fronts solo 110% / c2 ~99% / c4 98% / cold 334% / ITL ~107%
      (campaign-20261105-000521), hardmode 95 (campaign-20261105-003101).
      The cost tables dropped in the attribution (see the ECOSYSTEM item).
      The deepfills and visioncheck session phases retire.
- [x] **The ABSORB_MMA confirmation window** (round 133, cont. 17): hardmode
      on the full stack (the first boot inherited the adopted config — the
      serve line's 13.9 GiB / 2.6 GiB cache is the ABSORB-ON shape):
      **95/104 — one point ABOVE production's 94** (the standing control in
      the prior window: 94). The restart wall 120 s. **The plumbing catch**:
      the resumecost phase carried a `PATCHES="${RC_PATCHES:-}"` override
      from the RC_PATCHES era — with RC_PATCHES unset it expanded to EMPTY,
      defeating the config.sh adoption (its rows ran pristine: the first
      clean v1.2.2-pristine resumecost baseline — d2048 1.69, d4096
      3.64→1.92, d8192 5.41→1.41, sha ✓). FIXED to the nested form
      (`${RC_PATCHES-${PATCHES-}}`): an explicit RC_PATCHES still wins, the
      unset case inherits the adopted default. The stack's sha +
      small-prompt receipt rides the next resumecost run.
- [x] **deepdelta — the #1577 deep curve on both pins** (round 133, cont. 9):
      the same novel fills (50,960/101,948/203,882 tokens — the legs'
      prompt_tokens match exactly) on v1.2.1 and v1.2.2: **−2.6 to −3.5%
      (v1.2.2 uniformly faster; both curves linear, 0.79 vs 0.81 ms/tok)** —
      the low end of the upstream 5-14% claim (TP=3 there, TP=2 here). The
      cold row carries the deep-curve line.
- [x] **The docs audit for the fresh checkout** (cont. 30-31): the quickstart +
      config table verified against what serves on a new clone (the TR3 pack @
      8001 on v1.2.1, dense4fp8, 524288×4, vision on — prepare.sh discovers the
      site when local.sh is missing; DOWNLOAD=1 fetches a missing checkpoint);
      the config table gained the **VISION row** (default 1 — it was served but
      undocumented) and the **KV_CACHE empty-means-bf16 spelling** (cont. 26's
      semantics); the cold row annotated with the TR3 duel re-verification; the
      stale "open pieces" text fixed (the cross-restart resume is receipted
      cold); **the loading row RE-DATED — 90% on the served default** (104.5 vs
      93.7 s, the standing serve timed twice; the "taken at 98.6%" claim was
      the Focus-cell v1.2.0 receipt — the front's re-take is open).
- [x] **First campaign run** (2026-10-23 01:13–02:45, `results/campaign-20261023-011329/`)
      — the 512K window qualified end-to-end on the first overnight run:

  | phase | result |
  |---|---|
  | parity cell (dense8+fp8 KV+524288, PARALLEL=4) | **tool-eval 92/100** (125/136 pts, ★★★★★, 0 errors) |
  | candidate cell (dense4fp8+524288, PARALLEL=4) | **tool-eval 92/100** (identical points; deployability 68 vs 67, responsiveness 11 vs 10) |
  | depth (fp8 KV, dense8) | **12/12 facts** at 8k / 64k / 192k / 384k |
  | rung 524288 × PARALLEL=1 | fits: 3.61 GiB/stream fp8, 13.9 GiB left; 8k probe 3/3 |
  | gates g1–g5 | **byte-level gates are the wrong instrument on this engine** — see below |
  | cliff (4-stream + one schema request) | **absent**: schema batch 17.9s vs plain 21.2s — MaTeZZ's draft-truncation mechanism does not reproduce on native 1.1.x |
  | production reference | skipped (production was down) |

  **The gates need re-reading, not the KV cache.** g2/g3/g4 "failed" as raw-sha
  comparisons, but every captured output was **semantically identical** (the same
  primes+sum across drafted/plain and solo/c1–c4). Root cause (corrected after the
  prodqual control, see round 3 below): the raw-sha instrument hashes the whole
  response envelope, whose `id`/`created`/metadata fields differ on every request on
  ANY engine — it was never measuring token determinism. g3's empty reply was a probe
  bug (it compared two *different* prompts — turn 2 alone vs turn 1+2 — and 512
  max_tokens was eaten by 2,242 chars of thinking on the resumed arm).
  The script now gates on **normalized content** (`content_sha`), gives g3 the same
  conversation twice (cold compute vs full cache hit, with cached_tokens receipts), and
  times the prefill probe (`max_tokens=1`, wall ≈ prefill). Rerun `PHASES=kvqual prefill`
  to convert the three FAILs into their real verdicts — expected PASS on content for
  g2/g4 and a true cache-path test for g3.
  Two housekeeping findings: (1) the campaign rebuilt the image mid-run — start.sh
  re-prepares when the config fingerprint changes (the new KV_CACHE knob guaranteed it)
  and prepare.sh builds from upstream HEAD, so the campaign ran engine 1.1.2 at
  **1351ed16**, not the matrix's 4ff78441 (same engine version; noted for
  cross-receipt comparisons); (2) both fp8 cells served 524288 because the shell
  exported CONTEXT — dense4fp8's matrix cell now pins it explicitly.
  **Ladder verdict: the 512K goal is met and over-delivered** — dense4fp8 serves
  524288 × PARALLEL=4 with 15.8 GiB free (a PARALLEL=6/8 climb is affordable), quality
  identical to the production-parity config, ~2 GiB cheaper, and it should inherit
  dense4's solo-decode lead. Missing numbers: throughput tables for the fp8 cells at
  512K (the campaign's bench call ran the full tool-eval instead of `--perf-only`) —
  one `run-bench-matrix.sh parity dense4fp8` window fills that in.
- [x] **Round 2** (`results/campaign-20261023-093827/`, 2026-10-23 09:38): gates, speed,
      climb — **dense4fp8 is the qualified 512K serving config**.

  **Gates — all PASS on both configs** (content form, VALIDATION §2 receipt): g1
  token-deterministic (`choices` byte-identical across runs — see the round-3
  correction), g2 drafted=plain ✓, g3 cache-hit=computed ✓ (both arms answer
  "alpha-7391, bravo-2250, charlie-8118"), g4 concurrent=solo ✓, g5 seeded sampling
  content-stable. **The 0.6.x replication proof is now on paper for the native line.**
  One rigor caveat: g3's `cached_tokens=0` on *both* arms — the engine doesn't populate
  the usage field, so the gate passed on content while the cache-hit path itself went
  unverified; a `/metrics` cache-counter check closes that (goshi's exporter maps
  `tensorfold_cached_tokens_total`).

  **Throughput at 524288 × PARALLEL=4, fp8 KV** (pp2048 tg128, t/s):

  | cell | solo d0 / d4096 / d8192 | c2 d0 / d4096 / d8192 | c4 d0 / d4096 / d8192 | pp2048 |
  |---|---|---|---|---:|
  | parity (dense8+fp8) | 42.9 / 43.9 / 44.0 | 36.9 / 23.0 / 16.9 | 37.5 / 18.8 / 13.0 | 1,018 |
  | **dense4fp8** | **48.3 / 49.0 / 48.0** | **41.3 / 23.5 / 17.4** | **38.7 / 19.2 / 13.3** | **1,025** |

  dense4fp8 leads every cell: **+13% solo** (48.3 vs 42.9), +2–3% concurrent, prefill
  equal. Solo 48.3 vs the Oct-22 dense4 cell's 55.4 (at 40960/bf16 KV) prices the 512K
  window + fp8 at ~13% of solo decode. **The depth cliff reconfirms**: aggregate decode
  48.3 solo → 13.3 at c4@d8192 (3.3 t/s per stream), TTFT 2.0s → 28.4s — still THE open
  performance question. Prefill probe: **1,063 t/s on a 26,869-token prompt** — no
  deep-prefill collapse on the native line (the upstream-fairness note writes itself).
  **Climb: 6 and 8 streams refused at 512K with default knobs** — the kept-states store's
  worst-case sizing is the suspected blocker; the climb phase now retries with
  `PROMPT_CACHE_GIB=4` on refusal (rerun `PHASES=climb` to test).
- [x] **Climb ceiling found — it is the engine's own arithmetic** (`campaign-20261023-121811/`):
  the admission refusal prints its math — **"8 streams need 25.29 GiB … budget leaves
  15.83 GiB: serve --parallel 5, or lower --context"**. So 5 streams fit at 524288
  (15.81 of 15.83 GiB, knife-edge) and 6+ is blocked by the engine's **12.2 GiB
  reserve**, which no flag exposes (checked `serve --help`). `PROMPT_CACHE_GIB=4`
  freed +0.06 GiB (≈ the default) — not the lever. The climb phase now runs 5/6/8 so
  the ladder completes with the engine's own suggestion.
- [x] **The concurrency cliff was a bench artifact — steady-state decode matches production**
      (`campaign-20261023-145449/`, TF_GLM_PROF=1, 2026-10-23): with long generations
      (2048 max_tokens) the aggregate decode **rises** solo→c4 — solo 53.7/57.6 t/s
      (d0/d4096-class), c4 **99.2 / 102.8 t/s** — versus production's steady-state 103.7
      (derived from its bench rows). The engine's "tg" numbers collapse at depth because
      llama-benchy's tg128 rows divide by TOTAL time (TTFT included): at c4@d8192 the
      4×8192-token prefills are ~80% of the wall, so the 128-token generations score
      ~13 t/s. The matrix's "structural collapse at depth" was the same artifact.
      Section economics (head rank, ms/call over 64-call windows):
      - **wall ≈ gpu in every line** (40.08 vs 40.00) — zero scheduling bubbles; the GPU
        pipeline is saturated. There was never a scheduling cliff.
      - **`routed` dominates everything**: 18.5 ms of a 40 ms 2-row verify (46%), 54.7 of
        80 ms at 8 rows — **marginal cost per draft row ≈ 6.0 ms, nearly all in routed
        experts**. The RoCE gather (`gather_a`+`gather_b`) is 2.7–3.7 ms — 4–8%, innocent.
      - **prompt passes are 90% MoE**: a 2048-row chunk costs 1,892 gpu ms — router 910 +
        routed 793. Our prefill gap to production (1,025 vs 1,530) is the expert path in
        prompt chunks, not attention — a different target than #1080's kernels (which
        attack attention/projections; qwen-family).
      - attention (`kda`+`mla`) ≈ 13–16 ms/call, growing gently with depth (mla 4.4→6.7
        by ~2k context) — not the driver at our working depths.
      Consequences: (1) **more streams = more aggregate** for long-generation (agent)
      workloads — the KV-pages admission unlock buys real throughput; (2) the honest
      steady-state probe is long-generation, not tg128 — the prof phase doubles as the
      steady-state bench; (3) the upstream prefill conversation for GLM is about expert
      batching in prompt passes.
- [x] **The 3-point quality gap is located**: production PASSED TC-65/66/67/69
  (nested schema, enum, multi-tool) where BOTH our configs got partials — and both
  failed TC-68 like production. The gap is entirely in the structured-output
  category, is config-independent (parity cell = same pattern), and is therefore
  engine-level (native vs Python decoding path), not quant-level.
- [x] **Round 3 — the production head-to-head** (`results/campaign-20261023-110446/`,
      2026-10-23 11:04, prodqual read-only while production served): production 0.6.6
      (fp8 dense+KV, DFlash2, RoCE, 524288) measured with the SAME harness as our
      dense4fp8 receipts.

  | instrument | production 0.6.6 | dense4fp8 (native 1.1.2) |
  |---|---|---|
  | tool-eval (69 scenarios, same version/seed) | **95** (131 pts) ★★★★★ | 92 (125 pts) ★★★★★ |
  | deployability / responsiveness | 73 / 21 | 68 / 11 |
  | pp2048 | **1,530** | 1,025 |
  | solo tg d0 / d4096 / d8192 | **51.6 / 56.0 / 53.1** | 48.3 / 49.0 / 48.0 |
  | c2 agg d0 / d4096 / d8192 | **67.3 / 36.9 / 26.4** | 41.3 / 23.5 / 17.4 |
  | c4 agg d0 / d4096 / d8192 | **60.5 / 28.5 / 19.0** | 38.7 / 19.2 / 13.3 |
  | TTFT d0 | **1,339 ms** | 1,999 ms |
  | pg1 greedy determinism | `choices` byte-identical | `choices` byte-identical |
  | pg3/pg4/pg5 | PASS / PASS / PASS | PASS / PASS / PASS |

  Three takeaways. **(1) The determinism correction:** production's pg1 pair differs
  from our g1 pair in exactly the same way — envelope `id`/`created`/metadata only,
  `choices` byte-identical. Both engines are token-deterministic; the first campaign's
  "byte-level nondeterminism" was the instrument (whole-envelope sha), not the engine.
  **(2) The exactness guarantees hold identically on both engines** — pg2-class gates
  all PASS read-only on production. **(3) The real native-line gap is concurrency
  scheduling**: production's aggregate decode RISES with streams (51.6 solo → 67.3 at
  c2) while ours FALLS (48.3 → 41.3); at c4@d8192 it's 19.0 vs 13.3. Prefill +49% and
  TTFT −33% to production as well. This is the like-for-like evidence for the upstream
  concurrency note, and it sharpens the TF_GLM_PROF target. (Bench quirk to check:
  production's max points read 138 vs our 136 — same 69 scenarios, cause unknown.)

- [x] **Rounds 15–30 — the concurrency front's root-cause ladder** (2026-10-24/25):
  - **prof4** (`campaign-20261024-000708`): verify rounds DO batch across streams — 8-row
    shared windows at c4 (76.5 ms; solo 2-row 41 ms); `TF_GLM_SHARED=0` halves the c4
    aggregate (51.6). Both Front-1 levers answered and retired: batching exists, sharing
    is load-bearing.
  - **routerks2** (`campaign-20261024-115242`): the `router_ks 8→2` patch — the router
    section unmoved (1096→1090 ms of the chunk) + the content gate flipped a greedy token
    → RETIRED (#1079 protocol); the pipeline-depth hypothesis rejected.
  - **routerpart** (`campaign-20261024-125609`): the forced unstaged kernel costs the same
    (1140 vs 1096) with the gate IDENTICAL → the pathology is the hand-rolled mma design;
    the GEMM replacement (glm_mm's row-stable K-slices, the preserved 8-slice summation) is
    the scoped fix.
  - **the top4 ladder** (`campaign-20261024-132628` + `135458`): four attempts, one stage
    deeper each — the `weightShare` parse-failure billing (a 163.6-GiB budget illusion from
    the silent catch-return-total), the snapshot config's SYMLINK aliasing (fixed with a REAL
    file + byte-surgical edits), the parse's `want` pin and the EXL3 experts' module-global
    (both to topk=4 in `017-topk4b.patch`). **Real top-4 routing measured**: routed
    18.45→11.0 ms; **solo 63.6 t/s = 108% of production — CROSSED**; c2 103%;
    **c4 120.4 = 78% (was 65%)**; slope 0.593 (−10%); acceptance 4.8 tok/chunk (was 3.37).
  - **top4qual battery** (`campaign-20261024-142659`): §2 gates ALL PASS on the modified
    checkpoint; tool-eval **93** (above stock's 92; production's anchor 95); hardmode
    **89** (production's anchor 91; the line's first hardmode datum).
  - **(user) the served default = top4cfg + PATCHES=017-topk4b** (round 27); the anchors
    and the chart regenerated from the receipts (4 rows over the 100% line).
  - **the AZ route**: azampatti's retrained selector downloaded (the Xet CAS survived the
    site's reboot); the requant pipeline staged (az_dequant → az_conv_fix → convert
    `-b 4 -hb 16 -eb 16 -vb 16` → local model → the azqual battery); the convert in flight
    (layer 34/45 at 19:36; `done.` ~02:30 tonight). Discovered en route: **AxonZeta's
    AZ-Focus-EXL3** (the EXL3-native reasoning-efficiency checkpoint, topk=8) — test-ready
    on both hosts; a separate lever.
  - **the lessons**: the config fingerprint hashes the patch LIST, not contents (an amended
    patch needs a new name to force a rebuild); a json round-trip fails the engine's strict
    config parser (byte-surgical edits only); background watchers must exclude their own
    command text from liveness pgreps.
- [x] **The AZ battery digest (round 131, 2026-11-01, campaign-20261101-041447)**:
      the Oct 28 mcg placement (the Oct 26 tensor-name refusal fixed —
      `self_attn.q_proj.weight` present) SERVES and passes the gates. **The
      perf leadership is real and current: solo 80.1/79.9 t/s (Δ0.2%), c2
      128.2, c4 199.4 — c4 BEATS production's 192.6; TTFT d0 147 ms (ours
      200, production 185); slope 0.580.** The old top4cfg perf receipts
      (135458: solo 63.6 / c2 90.0 / c4 120.4) are superseded — the engine's
      decode machinery improved ~26% engine-side since, on the same top-4
      shape. **The cause is one config line: the AZ-EXL3 serves
      num_experts_per_tok=4 vs the Focus's 8** (the quantization identical:
      exl3 4bpw mcg, head 16, routed-experts-only) — half the routed-expert
      FLOPs per token. **The cost: hardmode 90 vs the Focus cell's 93**
      (consistent with az2's 89-vs-94). **No adoption — the round-2026-10-27
      (user) quality bar stands**; the decode front's attribution moves:
      the gap is largely ROUTING DEPTH (a user-decision trade), not engine
      machinery — the top-4 shape prices the trade at 3 hardmode points for
      +46% solo / +44% c2 / +38% c4. The azqual phase retires (the route's
      decision is receipted).
- [x] **The isolation quality round**: TC-92 FIXED and receipted (the effort-tail
      adoption, rounds 76/79 — pass on both paths; production's own rebaseline
      receipt FAILS TC-92, so our line is the clean one there). TC-51 CLOSED as a
      shared failure (round 82): production's rebaseline receipt fails it
      identically — same-turn batching of the dependent notification, a
      benchmark-policy trap both stacks fall into, not a gap between us and
      production.
- [x] **The pages×fp8 marriage watch** (#1163 mergeable-clean; #1211 stacks): when — LANDED (the marriage receipted end to end: §2 both KV cells, the depth ladder, hardmode, the duel).
      paging×fp8 lands, 512K admits 8 streams on fp8 — re-qualify the ladder then.
- [x] **The v1.1.5 candidate test**: #1218 (the slot-leak) is merged and slated upstream — — OBSOLETE (the pin passed v1.1.5 → v1.2.6; the slot-leak landed upstream long since).
      the first correctness reason to test a bump (rebase 017-topk4b, gates + probes decide).
- [x] ~~Publish the AZ quant to huggingface.co~~ CLOSED by the (user) (round 58): "there is nothing to be published, what we run is already out there" — the served checkpoint is AxonZeta's public release. The disk choreography landed with it (the mirrors/TR3/stubs deleted; the requant working dir kept as the repack source). gated on the AZ
      battery passing — repo under gilesco, the ~154-GiB EXL3 upload, and a model card
      carrying the quant contract (`-b 4 -hb 16 -eb 16 -vb 16`), provenance (azampatti's
      retrained top-4 selector → `az_dequant.py` → `az_conv_fix.py` → exllamav3 convert),
      and the gates/tool-eval/hardmode receipts summary. The `az-az-fp16` deletion
      (599 GiB) lands with this choreography once the verdict is in.
- [x] **The v1.1.6 rebase test** (round 33, `campaign-20261027-085035`): the pin → `eea9dc9c`
      (Release 1.1.6). ADOPTED — the A/B on the identical Focus serve: c2 74.7→**94.3 (+26%)**,
      c4 119.8→**150.6 (+26%)**, hardmode 90→**91** (ties production's anchor), gates/solo/
      slope/tool-eval unchanged. CAUGHT: the first A/B (`053451`) silently ran the old engine —
      the auto-prepare keys on the config fingerprint (the patch names), NOT the pin; a pin
      change needs an explicit `prepare.sh` (the image ID betrayed it).
- [x] **The bench v3.0.1 boundary**: tool-eval-bench updated to `3.0.1.dev4+gb672b53ff`
      (release v3.0.0 + two fixes) — the graphics results, the web UI (`serve`), and the
      Hard-Mode suite grows to TC-104 (seven new scenarios; the hardmode run is now 104
      scenarios, was 97). **Scores across the bench-version boundary are not comparable.**
      ALL THREE SERVES re-baselined on v3.0.1: production (round 35: 96 / run 94 / subset
      63=90%), the top4cfg (round 37: 96 / run 89 / subset 53=76%), the Focus (round 37:
      95 / run 92 / subset 60=86%). The old anchors (95/91, 94/90, 92/100) are formally
      cross-version — kept only as history. The comparison is complete; the open item the
      receipts surface is the hardmode trade (below).
- [x] **Production's patch series changed** (user): Mia's patches 0109-0122 + 0128-0129 and the — OBSOLETE (production IS the native promoted line since round 139's (user) re-target; the Python recipe retired).
      0088 NoRoom fix folded onto the python-0.6 tip (`879d7cfc`). DELTAS's production column
      carries it; the re-baseline refreshes the cross-engine anchors.
- [x] **The top4cfg re-qual on v1.1.6** — DONE across rounds 36–37: the perf side (round 36,
      campaign-20261027-124115: §2 gates ALL PASS, the duel receipt — solo 64.8, c2 108.0,
      c4 167.4 — prefill 1,175 t/s, loading 256 s, depth 12/12) and the score side (round 37,
      campaign-20261027-173843: gates ALL PASS, tool-eval 96 — a point-for-point tie with
      production at 133/138 — hardmode subset 53/70). The scoreboard/chart are current; the
      duel arms re-confirmed round 36 within noise across two independent sessions.
- [x] **The hardmode trade (user decision, 2026-10-27)**: **hardmode is THE quality measure**
      ("no one online is just running the standard set") — the target is to **beat production's
      run-level 94 or come close**. The served default is now the **Focus** (92 run-level / 86%
      subset — 2 under production; its whole gap is TC-38 + TC-80, both `wrong_args`;
      TC-92/TC-104 fail on production too). The top4cfg (89 / 76%) failed the bar and remains
      receipted as the perf leader (solo 111%/c2 124%/c4 108%). config.sh defaults swapped
      (MODEL_ID=local/GLM-5.3-Flash-AZ-Focus-EXL3, PATCHES empty). Failure-kind evidence
      (round 37): every fail on every serve is judgment-shaped (`wrong_args`/`missing_step`)
      — zero engine-pathology kinds — so the top4cfg's deficit is the unretrained selector's.
      **The variance verdict (round 40): the Focus's 92 is stable** — variant seeds 7/8/9 all
      scored exactly 92 (four draws including round 37's default seed). The beat-94 gap is
      real capability distance. The recommended-settings cell (temp 1.0 / top_p 0.95) scored
      91 — no lift; greedy stays. The remaining beat-94 paths: the AZ retrained-selector
      route, the marks-patch resume work (once its instrument sees it), upstream v1.1.8+.
  - **The window's receipts (round 47, `campaign-20261028-113509/20-indexdepth.md`)**:
      `TF_GLM_INDEX_CUDA=1` measured at depth, both arms fresh serves on the standing
      config: TTFT −2.6% at 131k, −3.6% at 262k, **−5.5% at 393k** (350.5 → 331.4 s);
      the off-arm marginal slopes RISE 0.860→0.976 ms/tok (cold prefill superlinear — the
      round-34 TTFT-frontier diagnosis confirmed at scale, the 8k-era 0.665 reference
      was the shallow case), the on-arm stays flat-ish 0.816→0.882; loading, decode
      (38.3 vs 39.6 t/s), and d0 unchanged. Upstream's −2%-at-131k claim measured at
      −2.6% — the curve transfers.
- [x] **The standing config fully qualified end to end** (round 57,
      `campaign-20261028-174914/04-depth.md`): the depth fact ladder **12/12** at
      8k/64k/192k/384k on dense4fp8 + `TF_GLM_INDEX_CUDA=1` + vision at 524288×4 — equal
      to the v1.1.6-era anchor. With the gates (rounds 48/55), the scores (rounds 37–45),
      and the vision verification (round 55), every instrument has a receipt on the one
      serving default.
- [x] **TF_GLM_INDEX_CUDA=1 ADOPTED as the standing default** (rounds 47–49, the receipts
      above + `campaign-20261028-141916/22-ixgates.md`): §2 gates **ALL PASS** under the
      knob (g1–g4 — upstream's byte-equal contract shown on our serve), the duel within
      noise of the v1.1.8 references (solo 57.0/56.9 vs 57.5–57.9, c2 93.7 vs 93.9, c4
      152.3 vs 152.4). config.sh exports `TF_GLM_INDEX_CUDA=1` (knob exports sit outside
      the config fingerprint — no rebuild on the next start); the README table carries
      the row.
- [x] **The cache-growth lever is DEAD at the standing window — and the round-48 receipt's
      first conclusion is withdrawn** (rounds 47–48): the round-48 gibdisc receipt printed
      "arm1 LIFTED the store — the knob works", which was **my branch-anchoring bug** —
      its own data line reads `a 2.5 GiB prompt cache` with GIB=10 (vs 2.6 default): the
      store did NOT lift to ~10; 2.5 ≠ 2.6 is the engine's floating budget figure, not a
      lift. The full evidence: GIB=16 → 2.6 with default-identical counters (round 47,
      behavioral); GIB=10 → 2.5 (round 48, serve-line). **`--prompt-cache-gib` does not
      size the kept-states store at 524288×4.** The lever's remaining shape: a one-serve
      check at `GIB=10 @ CONTEXT=262144` (does a smaller window free the budget? —
      wrap-queue), or accept the store as-is. The churn mechanism itself is receipted
      (round 47's default arm: hits 0, +5 evictions/round, revisit = cold).
- [x] **The spill lever is CLOSED for this line**
      (`campaign-20261028-141916/24-spillgib.md`): the engine refused the serve outright
      — *"--spill-gib keeps evicted states on disk for Nemotron, the Qwen hybrids and
      Flash Next only on CUDA: serve this model without it."* GLM-5.3-Flash is not covered
      by upstream's spill work (#1464) — upstream-bound data (docs/ECOSYSTEM.md). The
      SPILL_GIB plumbing (start.sh/config.sh) stays staged for the day upstream covers GLM.
- [x] **Vision on the testing line — ENABLED and VERIFIED** ((user) calls, rounds 51–55; the
      "vision is a want, enabled as a default before anything else"; "no more performance
      testing"; "not interested below 512k"; "ask more than a general question and allow a
      long answer"). The facts (rounds 50–51): production serves with `--vision`; the
      AZ-Focus checkpoint carries the tower (347 `model.visual.*` tensors, **BF16** — the
      requant's `-vb 16` recipe); the engine's GLM vision takes `--vision` (defaults 4
      images × 4096 tokens; OpenAI `image_url` data-URL parts; the loader's Lin union reads
      bf16 directly). config.sh now defaults `VISION=1` → start.sh passes `--vision`
      (outside the config fingerprint — no rebuild). **The test suite** (`assets/vision/`):
      a synthetic four-quadrant PNG (byte-verified) plus three Wikimedia Commons photos
      (the Golden Gate Bridge, a plains zebra at a waterhole, a desert STOP sign with
      mailboxes — CC BY-SA, attribution in NOTICE.md), each with ground truth **viewed by
      the agent** on production's vision serve; per image a targeted question (max_tokens
      64) and a long-form detail question (max_tokens 1024) scored against 4–7
      agent-verified details (detail-coverage n/m). The receipt lands with the `visionen`
      window: the serve's admission at 524288×4, the suite, and the §2 gates on the vision
      serve. Sub-512k configs are out of scope per the (user) call — the queued
      `GIB=10 @ CONTEXT=262144` serve is DROPPED.
- [x] **The effort-tail template ADOPTED as the standing default** (round 77, (user) "adopt, but we want vision still"): the same-session A/B measured 92 → 93 and flipped TC-92 (tenant isolation) fail→pass; the fix lives in BOTH serve templates (text-only + vision — the vision template patched with the same two edits and render-gated including an image-bearing case), so VISION=1 serves effort-tail semantics inherently and `CHAT_TEMPLATE=effort-tail` only selects the text-only template under VISION=0. Validation window RECEIPTED (round 79): the vision suite 8/8 ok on the adopted default (all four ground truths hit: red / golden gate / zebra / stop — the manifest is the trimmed 4-item version, so the round-55 detail counts do not cross-compare), and hardmode **93 on the vision serve** — matching the round-76 tail receipt exactly; TC-92 pass, TC-51 fail (its fix is the next A/B). The adoption is fully receipted on both paths.
- [x] ~~**The beat-94 track**~~ CLOSED with a receipt (round 72, 2026-10-29): the AZ retrained-selector route ran to a verdict — the repacked requant SERVED (the format rescue complete: the top-4 reference-shape patch, the both-host placement, the dtype contract) and scored **89** on hardmode at --parallel 2 vs production's 94 and the Focus's 92. Scenario-level: a near-tie with the Focus (3 lost / 2 gained of 104) — the selector performs at Focus-adjacent level; the gap to production stands. The path-(a) multi-trial question was answered by hmtrials (the Focus spread around 92); path-(c) remains an upstream watch item. The double-quantization confound (the 335 linears through two 4-bit passes) is recorded in the provenance; the azampatti source was deleted in the round-58 cleanup, so it cannot be de-confounded without a re-download.
- [x] **The definitive single-run benchmark (round 108, (user) directive)** — one
      invocation per serve: the full suite (standard + Hard-Mode, 104 scenarios) PLUS
      perf statistics, the receipted protocol (seed 42, parallel 2, timeout 240), both
      serves the same day. Receipts: production
      `results/campaign-20261030-091518/card-prod` (run `…ac7ca1ed`) and ours
      `results/campaign-20261030-095456/card-test` (run `…37325127`) on the head.
      **Scores: production 94, ours (the Focus default) 93** on the 104-scenario suite —
      consistent with the standing v3.0.1 baselines (96/run-level 94 production-era
      denominators differ). The definitive perf pair lives in the anchors table
      (prefill 68%, decode solo 86%, c4 aggregate 61%, c4@depth 68% of production).
      The cards: `docs/cards/prod-definitive.svg` + `focus-definitive.svg`; the README's
      card section carries the pair (the per-suite cards remain as history).

- [x] **THE 0103 PORT SHIPPED AND ADOPTED (round 139 cont. 8-9, the fork's callquote fix —
      the halt class's last shape)**: a call quoted inside prose still parses (the fork's
      kept-list semantics, composed with our strict-retry rule: a salvaged call names an
      OFFERED tool — the own-name rule is a whole envelope's rule) and the envelope scan
      never cuts a call's own data (011-zclose's value-aware closer, carried onto the
      composed base). The port landed as **018-callquote** — the first ship under the
      NNN-name scheme — via the cross-tree recipe: composed base (pristine v1.2.4 +
      011-zclose) + the fork's final file state = the commit tree EQUALS the suite-green
      tree `f202781d3` (`18da977ab…`), so the tool-parse host suite 51/51 and compile
      RC=0 (sm_121) inherit unchanged; the patch applies in stack order on pristine
      v1.2.4 and reproduces the tree byte-identically. The battery (callquotequal,
      campaign-20261108-214221, the 17-patch image): the greedy content sha IDENTICAL
      (the same 80cc3802… as every window), the quoted-markup live probe PASS (the
      halt's shape on the ported serve), the §2 gates ALL PASS, hardmode 95 — the
      SEVENTEENTH consecutive — the vision 4/4. ADOPTED: config.sh's PATCHES default
      carries 018; the promoted repo follows on the next promotion sync.

- [x] **THE 0104 PORT PARKED — THE MECHANISM ENGAGES BUT BUYS NOTHING ON OUR KV_SHARE MODE
      (round 139 cont. 14-15, campaigns -112212/-122100/-131026)**: the port now works
      end to end — the share-store substrate fix (warm turns open on either store; the
      radix rules' tail already plans the pass's end), the kill switch gating the passes
      themselves, and the hardened four-arm battery with the witnessed-state gate (a
      serve whose store did not open — the fork's issue-16 room-drift class — voids its
      rows). The ON arms ran the mechanism for real (3 done / 3 stepped aside / 0 failed
      per arm, the fork's own behavior pattern) and the deepened instrument (~9-10K loop
      tokens, the fork's measured shape) showed NO WIN: off2 6194 ms vs on2 6292 ms (the
      ON arm 1.6% slower, inside noise). The explanation: our KV_SHARE mode's per-turn
      radix keeps already carry what the warm pass adds — the fork's win existed on their
      snap-store base which missed the mid-loop states. The port stays staged (019), NOT
      in the PATCHES default; the battery hardening stays as the A/B pattern.

- [x] **THE 0104 PORT STAGED AND DISPOSITIONED INERT-ON-OUR-MODE (round 139 cont. 13, the
      warmturnsqual A/B, campaigns-083530/-093727/-102456)**: the port is bit-safe and
      receipted (the greedy sha IDENTICAL on every arm, the §2 gates ALL PASS, hardmode
      95 — the NINETEENTH consecutive, the vision 4/4) but the warm-pass mechanism never
      engages on our serving mode: the boot witness (added to the port for exactly this)
      printed `turns=false quiet=0ns host_warm_quiet=0ns` on BOTH arms — the store the
      warm pass attaches to (`snap_save` + the warm_quiet declaration) is created only
      under `!share`, and our adopted serving mode TF_KV_SHARE=16 keeps prompts as pool
      pages instead. The fork's 0104 was developed against their base without the
      KV_SHARE store — the substrate differs, not the port. The trade-off (KV_SHARE vs
      warm-turns) is the user's; the port stays staged (019), NOT in the PATCHES default.

- [x] **THE V1.2.5 BUMP QUALIFIED AND ADOPTED (round 139 cont. 11-12, the v125val battery,
      campaign-20261109-000818)**: the engine is v1.2.5 (8be9c408c) + the full 17-patch
      stack with 003-fp8-pages re-anchored (15 of 17 patches applied verbatim; the
      re-anchored 003 carries the glm_kv_paged_records join onto v1.2.5's
      registry_joins.zig, keeps v1.2.5's shareSlot beside our layout rewrite, drops the
      patch's old TF_KV_PAGES test rename — v1.2.5's title already carries — and
      re-anchors the snapshots step). The receipt: the greedy content sha IDENTICAL
      (the same 80cc3802… as every window — the engine bump did not move the
      deterministic probes), the §2 content gates ALL PASS, zero strict-TF_ refusals at
      boot, **hardmode 95 — the EIGHTEENTH consecutive AND the first on the re-grounded
      --parallel 2 harness** (see the instrument note above), the vision 4/4,
      steady-state decode 73.1 tok/s, the load walls 83/83 s (the loading row re-dated),
      prefill 1,523 at d0 (in the band), d8192 c2 68.3 (the steps0 depth-decode holding
      on the bumped engine). BOTH repos' pins moved: the promoted production repo
      carries the bump and its restarted serve (healthy on 8000) IS the v1.2.5 engine.

- [x] **The bench harness runs `--parallel 2` (user, round 139 cont. 10)**: the
      tool-eval/hardmode batteries run two scenarios CONCURRENTLY against the serve —
      two separate contexts coexist in the KV pool for the whole battery, which is a
      standing cross-spill probe (the poolcanary class caught the store bug; the
      battery now watches for its recurrence every run). NOT the serve's PARALLEL=
      lanes: `PARALLEL=4` is the engine's stream count (config.sh), `--parallel 2` is
      tool-eval-bench's scenario concurrency — they stack (2 bench scenarios × 4
      server lanes). ALL 15 hardmode battery invocations in run-qualification.sh carry
      it now (bench_cell already did). **Instrument note**: the consecutive-95 streak
      ran its batteries at the harness default (parallel 1) — the next battery re-grounds
      the instrument at parallel 2, so any score movement between them attributes to the
      INSTRUMENT CHANGE first, the engine second.

- [x] **THE 0108 PORT SHIPPED AND ADOPTED (round 139 cont. 16-17, the fork's CACHE_FIRST —
      the room-drift visibility)**: the prompt cache set aside before the streams' windows
      (TF_PROMPT_CACHE_FIRST=1), adapted to compose with our tree's `asked` flag (v1.2.5's
      own cache priority) — the flag changes the ROOM the windows count. The value-add on
      our mode: the FUND-REPORT line makes the fork's issue-16 room drift (our
      warmturnsqual battery caught the same: the room moved 11.8 -> 11.0 GiB between starts
      with no config change) VISIBLE at boot. The battery (cachefirstqual,
      campaign-20261109-140604): the four-arm OFF/ON plan A/B — the ON arms' streams ceded
      pages to the reserve (3110/3115 -> 3103/3083), the fund-report never fired at our
      3 GiB ask, the §2 gates ALL PASS, hardmode 95 — the TWENTY-FIRST consecutive — the
      vision 4/4. ADOPTED: the env default TF_PROMPT_CACHE_FIRST=1 + the 020 patch in
      config.sh's PATCHES; the promoted repo follows on its next promotion sync.
      (Instrument note: the battery's own greedy probe returned EMPTY content at
      max_tokens 64 — the thinking model ate the budget; the gates' probes carried the
      real content witness. The battery's probe needs a larger budget next revision.)

## Round 140 (2026-11-10) — the v1.2.6 rebase and the cachefixqual arc

- [x] **The v1.2.6 rebase QUALIFIED — the pin HOLDS at `6e9af9302`** (window 32,
  campaign-20261110-162034): the drift map applied (6 verbatim, 12 re-anchored), the
  round-trip PROVEN byte-identical (pristine v1.2.6 + the 18 regenerated patches =
  the rebase tree, zero diffs), the compile gate RC=0, the host suite PASS, and the
  v126val battery passed on every instrument: the same-bits greedy witness IDENTICAL
  (the `80cc3802…` sha holds across the bump), the §2 gates ALL PASS, hardmode 95 —
  the TWENTY-SECOND consecutive at the time — the vision 4/4, zero strict-TF_
  refusals under the stricter v1.2.6 settings validation, the walls 84/83 s,
  prefill 1,523, steady-state decode 73.1 tok/s. The anchors' loading row re-dated;
  the chart regenerated.
- [x] **The pool plan moved with the bump — the #2257 trade recorded** (window 32's
  serve line vs v125val's): window_rows 8→32 and the KDA projection into each stream
  cost +51 MiB/stream fixed (364→415) and 2 of the 16 TF_KV_SHARE slots (0.4 GiB);
  the release buys 32-row decode windows with the memory. The room-drift ladder
  (the fork's issue-16 class) now has six rungs: v126val 11.5 left/0 slots, w33-OFF
  12.1/3, w33-ON 13.0/6, DRAFTS=0 16.1/11, w34-OFF 13.0/7 — plus w36-OFF 13.0/6
  (reproduces w33-ON's shape) and w36-ON 12.2/16 funded on the battery's ON arm.
- [ ] **The #2744 vision re-encode port — windows 39/40/41 narrowed the instrument
  three times; the cold-race instrument (window 42) is the decisive one** (campaign-20261111-000839,
  campaign-20261111-010825): window 40's room gate PASSED (the arms' room
  lines 13.2 vs 13.0 GiB — the confound gone) and all guards held (the
  greedy TEXT sha `80cc3802…` identical, §2 ALL PASS, **hardmode 95 — the
  TWENTY-SEVENTH consecutive** — the vision 4/4), but the single-stream
  two-turn probe's value gate MISSED (the ON arm's room-matched t2
  2.684 s vs the OFF arm's 2.667 s — parity, not a >5% win) — and the
  parity is the EXPECTED baseline: the fix's mechanism is the OWNER
  HANDOFF (two streams serving multi-image prompts concurrently
  re-encode each other's images on every chunk switch pre-fix; a
  single-stream probe never loses ownership). The corrected instrument
  (window 41): TWO CONCURRENT multi-image multi-chunk prompts (each an
  image + a d4096 fill), the race aggregate the value number, the
  room-match restart kept. Window 41 ran the concurrent-pair
  race and its OWN flaw surfaced in the receipt's mechanism witness: the
  warm-up pair primed the page cache — the race measured cache hits
  (cached=12288/16384 on both arms' race serves), not chunk-switch
  re-encodes; the aggregate read parity (the OFF arm 4.27 s vs the
  room-matched ON arm 4.25 s). The room gate PASSED again (13.1 vs 12.2 —
  0.9 GiB) and every guard held (the sha identical, **hardmode 95 — the
  TWENTY-EIGHTH consecutive** — the vision 4/4). The corrected instrument
  (window 42): the race runs COLD (no warm-up pair), the race bodies share
  NO prefix with the t1/t2 probes or each other (zebra/sign + meadow fills
  for the arm-loop race; sign/zebra + cistern fills for the room-matched
  race — the page cache cannot prime the race's prefixes), and the engine
  lines' cached= values stay the mechanism witness (cached≈0 expected on
  the race streams; the chunk-switch handoff carries the value). The kill
  criterion stands: no value on the corrected instrument retires the patch. (campaign-20261111-000839): upstream's
  fix (5151f19f3, main-only) ported as `021-vision2744.patch` (the body
  byte-identical to upstream's diff; applies clean on the full 18-patch
  stack, verified on a scratch clone of the tag; host-side only). Window 39's
  A/B ran but the ON arm booted immediately after the 560 s rebuild — the
  unified-memory pool carried the build's residue (11.5 GiB left vs the OFF
  arm's 13.0), the serve funded ZERO kept states, and the value probe
  measured the cache-state confound (the page-cache miss cascade: the ON
  arm's t2 6.837 s vs the OFF arm's 2.677 s), not the fix's value. The
  guards all held on the 19-patch stack: the greedy TEXT sha `80cc3802…`
  IDENTICAL across both arms, §2 ALL PASS, **hardmode 95 — the
  TWENTY-SIXTH consecutive** — the vision suite 4/4, steady-state 73.1
  tok/s, pp d0 1,522/1,525/1,521 flat. The value question REMAINS OPEN (the
  reading is invalid, not negative). The corrected battery (window 40): the
  ON arm gains ONE build-free room-match restart before its value probes,
  both arms' value sections record the room line, and the verdict gains the
  room gate (the arms' room lines must differ by < 1.0 GiB). The patch stays
  staged but NOT in config.sh's PATCHES (no adoption on a confounded
  reading).
- [x] **The #2257 pool plan's concurrent-resume regression watch — PASS (window
  38, campaign-20261110-234815)**: the kvshare2 instrument's shape re-run on
  the standing v1.2.6 config: the solo warm hit `cached=2048` at ttft 1.339 s;
  all four concurrent warms hit `cached=2048` (ttft 1.343–1.350 s); the
  aggregate **5.41 s vs the round-133 receipt's 7.41 s — BETTER by 27%**; zero
  eviction (the pool's idle lines walked free 3134 → 3122, store 4 → 16, no
  state lost). The #2257 pool plan (window_rows 32, +51 MiB/stream, 2 of the
  16 slots) did NOT regress the concurrent resume — the round-133 receipt
  re-anchors on v1.2.6, and the resume got FASTER per request (the warm ttft
  1.841 → 1.34 s). No adoption branch existed; the standing config unchanged.
  The serve line funded 6 of 16 slots at 13.0 GiB left (matching w36-OFF —
  the slot count tracks the run's room, confirmed again).
- [x] **The #2181 live-half candidate — MEASURED OUT (window 37's value-first
  verdict: MISSED on the value gate; the mechanism reproduces; no adoption)**
  (campaign-20261110-225305): the A/B ran both arms end to end on the testing
  port. The value gate missed its primary criterion: the ON arm funds **5 of
  16** TF_KV_SHARE slots cacheless vs the OFF arm's 3 (this run; w36-OFF
  funded 6 — the slot count tracks the run's room, the fork's issue-16 class),
  and the engine's eviction warning (`live streams evict each other's before
  a resume`) prints on BOTH arms — the brief's kill criterion retired the
  knob; `TF_GLM_KV_LIVE_HALF` stays OUT of config.sh. The mechanism itself
  reproduced on our shape — the FIRST measured confirmation of upstream's
  scope-caveated receipt on a TP=2 concurrent/paged/fp8/share serve: the
  per-slot keep cost **−31%** (OFF ~237 MiB/state → ON ~164 MiB/state;
  upstream measured −30–35% on their single-stream/host-cache shape),
  enough-for-3 HELD (no window lost), the greedy same-bits sha `80cc3802…`
  IDENTICAL across both arms, §2 ALL PASS, hardmode 95 — the TWENTY-FIFTH
  consecutive — the vision 4/4, steady-state 73.1 tok/s, pp d0 1,530/1,534/
  1,535 flat. The unplanned composition datum: the g2 gates' serve
  (DRAFTS=0 + LIVE_HALF) read **enough for FOUR at 512K and 10 of 16 slots**
  — model −2.84 GiB plus the smaller keeps cross the fourth-window line at
  the drafter's price (the DRAFTS=0 trade stays declined on its decode cost);
  recorded as upstream data.
- [x] **The #2699 prompt-cache recovery — CLOSED (window 36's value-first
  verdict: MISSED; the cacheless standing holds)** (window 33's A/B INVALID —
  campaign-20261110-173035; window 34 VOID on the unguarded grep —
  campaign-20261110-192708; window 35 VOID-NO-OP: the retirement sweep
  `7cdf199` ate the freshly-staged battery, the campaign ran preflight+summary
  in 10 s, rc=0 — campaign-20261110-212651; **window 36 RAN the recovered
  value-first battery end to end — campaign-20261110-215136**): window 33's ON arm was a PLACEBO (the phase staged the
  doubled env name `PROMPT_PROMPT_CACHE_GIB`; nothing read it — the OFF-vs-ON slot
  move was room drift on two identical cacheless serves); window 34 died on its
  staging (the battery's new argv-witness line ended in a bare grep under
  `set -euo pipefail`); window 35's launcher accepted a swept-away phase name
  (nothing validated it against the `want` dispatch — the launcher now does,
  plus DRY_RUN). **The battery's verdict (window 36)**: the flag PLACED (the ON
  arm funds 16 kept states' slots, 3.6 GiB vs the OFF arm's 6 of 16 — the serve
  lines prove placement; the argv-witness line FAILED on extraction, an
  instrument defect, not the verdict) but the VALUE gate MISSED on both
  instruments: (v1) the within-session resume delta — ON cold 2,521/warm 2,532
  ms (−11) vs OFF +6 ms, needing >150 ms better; (v2) the multi-turn TTFT — ON
  saves 18,420 ms vs OFF's 18,574 ms (154 ms LESS). Both arms' turn-2 walls sit
  at ~1.8 s: the page cache over the pool's pages already delivers the resume
  value cacheless. The price of funding all 16: the third 512K window (enough-
  for-2 vs 3) and 1.0 GiB of stream room (13.0 → 12.2 GiB left). **The kill
  criterion fired as written: the cacheless standing HOLDS, `PROMPT_CACHE_GIB`
  stays empty, the question CLOSES as upstream data** — the TF_KV_SHARE slots'
  value on this shape is negative against the room they cost; the measurement
  note lives in docs/ECOSYSTEM.md (nothing posted upstream). The guards held on
  the ON arm: the greedy same-bits sha `80cc3802…` identical across both arms,
  §2 ALL PASS, hardmode 95 — the TWENTY-FOURTH consecutive — the vision 4/4,
  steady-state 73.1 tok/s, pp d0 1,529/1,532/1,530. The room-drift ladder's new
  rungs: w36-OFF 13.0/6 (reproduces w34-OFF), w36-ON 12.2/16 funded.
- [x] **The discipline layer landed (the user, round 140 cont. 5)**: the stage
  brief, the value gate, phase-lint (both burn classes mechanical — wired into
  autonomous-launch.sh as a launch refusal), the hit-rate watch, the
  state-docs-pace rule. The second launch-staging name failure of the class
  captured in verify-shell-config-edits. The generated LAUNCH_INDEX.md (338
  round entries) carries the loop's navigation.
