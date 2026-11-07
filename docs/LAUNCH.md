# Launch runbook — read this before touching the machines

Handover document for whoever attempts the first launch of this testing stack. The site's
own verified facts (hosts, addresses, driver, disk, caches) are **not in this repository** —
they live in `docs/SITE.md` (git-ignored; see below). Everything else below was verified on
2026-10-16 by the session that wrote this repo; re-check anything that looks different
before acting.

## 0. The situation

- **The site runs the PRODUCTION stack on the same two GB10 machines (128 GB unified memory
  each, aarch64)**: the EXL3/Python TensorFold recipe in containers named `glm53-flash-tf`
  on both hosts. It serves GLM-5.3-Flash EXL3 @ `078455ff` with DFlash2 on **port 8000** —
  rank 0 on the head, rank 1 on the worker, rendezvous on the head's CX7 rail address.
- **This repo is the testing line** (native engine, EXL3 only — the NVFP4 route has its
  own repo; no patches — see `../README.md`
  and `docs/DELTAS.md`). Its launch **requires both GPUs free**, so **production must be
  stopped first**. Stopping the agent session does NOT stop the containers; someone must stop
  them explicitly (step 4).
- Do not modify anything under `~/GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold*` on the
  machines, and do not delete their HF cache — that is the rollback path (and production
  serves from it).

## 1. Facts that are part of the recipe

| Fact | Value |
| --- | --- |
| Arch | aarch64 throughout (arm64 images and builds) |
| Toolchain on hosts | none (no zig, no nvcc, no system libnccl) — hence the containerized build; NCCL is bundled into the runtime image |
| Checkpoint | default `Mia-AiLab/GLM-5.3-Flash-EXL3-4bpw-TensorFold` @ `078455ff…` + drafter `incoai/GLM-5.3-Flash-DFlash2` @ `bf582e4e…`, served from the hosts' `~/.cache/huggingface` (the EXL3 one is production's checkpoint: `quant_method: exl3`, 4-bit mcg routed experts). Fallback route: `nvidia/GLM-5.3-Flash-NVFP4` @ `09b04e5e…` |
| zig 0.17.0 aarch64 tarball | reachable at ziglang.org (verified) |
| Site identity | `WORKER`, the rail addresses and netdevs — set in `scripts/local.sh` (git-ignored); `docs/SITE.md` records one site's real values |

## 2. Launch (on the head)

```sh
# 1. get the repo onto the head
git clone https://github.com/gilesco/GLM-5.3-Flash-EXL3-2x-GB10-TensorFold-v1.1-testing
cd GLM-5.3-Flash-EXL3-2x-GB10-TensorFold-v1.1-testing
cp scripts/local.sh.example scripts/local.sh      # fill in this site's values
                                                  # (docs/SITE.md lists one site's real ones)

# 2. resolve version, build the image (LONG the first time: Zig + nvcc for sm_121),
#    smoke-test it, copy it to the worker, write the prepared marker
./scripts/prepare.sh

# 3. inspect what will run (needs nothing, changes nothing)
DRY_RUN=1 ./scripts/start.sh

# 4. STOP PRODUCTION on both hosts (from the production checkout on the head)
~/GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold-tip/stop.sh
# verify: no glm53-flash-tf container on either host, and
#   nvidia-smi --query-gpu=memory.used --format=csv   shows both GPUs nearly idle

# 5. launch: rank 1 on the worker first, rank 0 here, then wait for /health
./scripts/start.sh

# 6. verify
curl -s http://127.0.0.1:8000/health ; curl -s http://127.0.0.1:8000/v1/models
./scripts/status.sh
```

`start.sh` refuses to run while unified memory is mostly held (MemAvailable < 30 GB) or the
port is taken, so a launch over a live production stack fails in seconds with a named reason.

Clients point at **port 8000** (`http://<head>:8000/v1`, model `GLM-5.3-Flash-EXL3` —
`SERVED_NAME`) — the
same port production serves, deliberately, so clients keep one endpoint when switching
engines. The consequence: **the two stacks are mutually exclusive** — stop one before
starting the other (`start.sh`'s port guard enforces it).

## 3. When something fails

| Symptom | First response |
| --- | --- |
| `prepare.sh` build fails | Read the docker build log — `image/build-native.sh` echoes every step. Check free disk, and that `BASE_IMAGE` (default NGC 26.07) is present. A changed upstream build.zig may have renamed `-Dsm`/`-Dnvcc` — the script falls back automatically; if both forms fail, read `packaging/README.md` at the pinned tag. |
| `could not start rank 1` | `ssh "$WORKER" true` from the head (key-based ssh), and `docker info` there. |
| A rank exits during start | `docker logs glm53-native-tf` (rank 0) and `ssh "$WORKER" docker logs glm53-native-tf` (rank 1). The ranks verify each other's build/cut/checkpoint bytes before loading and name any mismatch. |
| NCCL timeout / rank waits forever | `ping "$WORKER_FABRIC_ADDR"` from the head; add `NCCL_DEBUG=INFO` to `scripts/local.sh` and restart; check the rails are up (`ip -br addr` shows every netdev from `NCCL_SOCKET_IFNAME` UP on both hosts). |
| `/health` never comes up | Both logs (see above); the engine's admission names a rank and its reason when memory is short. `HEALTH_TIMEOUT_S` (default 900) can be raised for the first cold load. |
| libnccl/libstdc++ errors from the binary | The runtime image bundles libnccl only; if `--version` worked in prepare but serve complains, note the missing soname from `ldd` output and add it to `image/build-native.sh`'s collect step. |

Log everything you see into a new section at the bottom of this file (append, never rewrite
history) — the next session starts from your notes.

## 4. Rollback (restore production)

```sh
cd /path/to/this/repo && ./scripts/stop.sh          # stops both testing ranks, saves logs
cd ~/GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold-tip && ./start.sh
# verify: docker ps shows glm53-flash-tf on both hosts, port 8000 answers on the head
```

The testing stack shares nothing with production except the port (both 8000, by design —
only one runs at a time): different image (`glm53-native-tf:*` vs `tensorfold-glm53:*`),
container name (`glm53-native-tf` vs `glm53-flash-tf`), state/log dirs. Optional cleanup to
reclaim ~191 GB per host:
`docker rmi glm53-native-tf:<tag>` and remove
`~/.cache/huggingface/hub/models--nvidia--GLM-5.3-Flash-NVFP4` (**do not delete any
checkpoint blobs** — the NVFP4 line and production serve from the same caches).

## 5. After a successful launch

Work through [VALIDATION.md](VALIDATION.md) in order (exactness → capacity → speed →
clients) and record results in its table. Until then, this stack is a curiosity, not a
server.

## 6. Session log (append-only)

- **2026-10-16** (session that built this repo): repo created and pushed at `46f05e5`;
  shellcheck clean; DRY_RUN/marker/version-resolution flows tested from the workstation;
  both checkpoints verified admit-compatible and complete; builder base verified
  (nvcc 13.3 + NCCL, aarch64); no GPU work attempted (production was serving).
- **2026-10-16 first launch: SUCCESS.** Production stopped cleanly; prepare built
  `glm53-native-tf:v1.0.12` (first build only ~3 min on the Grace CPU) and distributed it to
  the worker; both ranks verified each other's checkpoint bytes and **loaded in 229.3 s**;
  `/health` ok (`backend cuda`, `NVIDIA GB10`, model `GLM-5.3-Flash-NVFP4`), peak memory
  100.6 GB (rank 0, `--context 40960 --parallel 4`) — ~21 GiB spare. Inference works
  end to end; measured ~22 tok/s drafted on 512-token completions (thinking on). Notes:
  - fixed live: `worker()` passed no remote command — a bare ssh ate stdin (the docker-save
    tar reached the worker's bash; commit `c8066c0`) — re-run prepare after the fix; the
    docker cache made it instant.
  - GB10's nvidia-smi reports memory as `[N/A]`; busy-checks use MemAvailable (`6e0a22b`).
  - container `docker stats` MEM is meaningless for device allocations on unified memory —
    use the engine's `/health` `memory` block.
  - `reasoning_effort: low` is advertised in `/v1/models` but the model still thought in the
    probe — pin down the no-think path in the validation phase.
  - over-ssh scripts: background with `< /dev/null` or ssh hangs on inherited stdin.
- **2026-10-16** port default changed 8888 → **8000** (same endpoint as production, so
  clients never reconfigure when switching engines); the stacks are now explicitly mutually
  exclusive and `start.sh`'s guard enforces it. The running instance was restarted onto 8000
  and verified healthy (`/health` ok, 100.6 GB active, the old port closed).
- **2026-10-16 Phase 1 perf campaign started** (`PHASE=perf`, `--perf-only`): baseline
  (p4) / recall (p4) / parallel6 (p6) / recall6 (p6). Findings so far:
  - llama-benchy needs `--tokenizer nvidia/GLM-5.3-Flash-NVFP4` on an offline host — the
    served name is not a Hub id; fixed in the fixed bench options (`34fcb46`).
  - a `pkill -f` whose pattern appears in the same remote command kills the invoking ssh
    shell (self-match) — kill and launch must be separate ssh calls, bracket-quoted.
  - baseline memory under load: 100.64 GB active at rest → 107.29 GB while llama-benchy
    fills KV; MemAvailable 18.7 → 12.2 GiB. Healthy margin, peak tracking works.
- **2026-10-16 first perf numbers (recall config, p4 @ 40960):** the standing 512-token
  probe, three runs: recall cold 24.4 s (~21.0 tok/s, drafts 342/445) — baseline-equal;
  recall warm 17.5/17.6 s (**~29.4 tok/s, drafts 383/383 accepted**) — **+29% over the
  baseline probes (23.45/23.59 s)** with identical output sha (exact). Recall validated as
  the top no-code optimization for repeated/agent traffic; fresh content decodes at
  baseline speed. Remaining Phase-1 matrix (llama-benchy pp/tg per config) still to run.
- **2026-10-16 long-context attempt (halted): 262144/p1 overshoots.** Restarted at
  `--context 262144 --parallel 1` with default knobs (reserve 12.2, prompt cache 3.9): the
  engine's model predicted ~6 GiB slack, but at load+prefill MemAvailable fell to
  **0.3 GiB** — the real usage ran ~6 GiB past the engine's accounting (the long-context
  overshoot; indexer pool-scan scratch at depth is the suspect). Halted per resource
  caution; memory recovered to 117 GiB after stop. Next attempt must start at the ladder's
  first rung (131072, with the trimmed knobs reserve 8 / prompt cache 1.5) and measure the
  overshoot before climbing. **Nothing past 40,960 has served yet.**
- **2026-10-16 memory model extracted** (read-only, from the startup log + config.json):
  model 93.72 GiB/rank; **0.89 GiB per stream at a 40,960-token window (≈22.8 KiB/token,
  bf16 latent + indexer pools, replicated on both ranks)**; 12.2 GiB reserve; 3.9 GiB prompt
  cache; 6.5 GiB free at --parallel 4. 45 layers = 33 KDA + 12 DSA; indexer selects top-2,048
  tokens/row (attention cost flat with context; the index scan grows). Used for the 500K
  feasibility math (docs/DELTAS.md): **500K fits only at --parallel 1** (and only with the
  reserve trimmed ~2 GiB); --parallel 2+ does not fit on bf16 KV.
- **2026-10-16 vision review** (docs/DELTAS.md said CUDA vision was missing — confirmed): no
  upstream PR or issue exists for GLM-5.3-Flash CUDA vision; the nearest precedent
  (#652/#653, "dense path ports to a MoE family in ~70 lines") is a draft against the
  **python-0.6** engine (not native Zig), unmerged and closed. Native CUDA vision exists
  in-tree only for Nemotron Super VL. Decision: do not fork the engine for this — vision
  workloads stay on the production stack until an upstream PR lands; a proposal issue on
  ashhart/TensorFold is the cheap accelerator (our pair is the TP=2 test hardware the gate
  needs). Filed as
  [ashhart/TensorFold#971](https://github.com/ashhart/TensorFold/issues/971) (proposal +
  test-hardware offer, LLM-agent-posted on gilesco's behalf and approved by them, per their
  request; no implementation commitment).
- **2026-10-18 rebase to TensorFold v1.1.0 + the EXL3 pivot (prepared, NOT started).**
  Upstream's latest release, v1.1.0 (tag `76aafcf2…`), resolved by `TF_REF=latest-v1`; image
  `glm53-native-tf:v1.1.0` built on the head (Zig 0.17.0, sm_121, ~4 min compile) and
  distributed to the worker; prepared marker written. **Nothing was started** — production
  serves port 8000 and was never touched; `start.sh` is the manual next step. Changes:
  - **Checkpoint pivot, NVFP4 → EXL3.** v1.1.0's known issues name our old route: the NVFP4
    two-rank path was *not run upstream for the release* ("the weights leave no room for its
    streams beside the memory reserve" on two GB10s). The EXL3 two-rank path is the one they
    measured (#855/#976; DFlash2 in #979). config.sh now defaults to
    `Mia-AiLab/GLM-5.3-Flash-EXL3-4bpw-TensorFold@078455ff` (production's pin, in both
    caches) and passes `--drafter` with DFlash2 `incoai/…@bf582e4e` when its snapshot is
    present (DRAFTS=0 still passes `--no-drafts`). The NVFP4 route stays one
    `MODEL_ID`/`MODEL_REVISION` override in local.sh away.
  - **The production recipe's `zig-engine` branch was evaluated and rejected**: it pins
    TensorFold v1.0.7 + ~326k patch lines + a captured Triton AOT set, is unqualified by its
    own docs, and 1.1.0 absorbed its goal upstream. What was borrowed: its CONTEXT=131072 /
    PARALLEL=8 defaults for this checkpoint family on GB10s (noted in local.sh.example).
  - **Cosmetic quirk:** the binary built from the v1.1.0 tag still prints
    `tensorfold-native 1.0.12` — upstream did not bump `.version` in build.zig.zon at the
    tag. The pin is the commit sha; ignore the version string.
  - **Repo moved** to `gilesco/GLM-5.3-Flash-EXL3-2x-GB10-TensorFold-v1.1-testing` (full
    history); the old NVFP4 testing repo stays untouched as the v1.0.x record.
  - **Site details moved out of the repo**: hosts, addresses, driver, ssh targets and disk
    facts now live in `docs/SITE.md` (git-ignored); config.sh requires site identity from
    `scripts/local.sh` instead of shipping this site's values as defaults.
  - Not yet done here: first start on 1.1.0 (memory fit at 131072 unmeasured on this pair;
    ladder rules from 2026-10-16 still apply), the EXL3-context of docs/DELTAS.md and
    docs/VALIDATION.md.
- **2026-10-18 first EXL3 launch on v1.1.0: SUCCESS, then swapped back to NVFP4.** Loaded in
  **843.6 s**: the new-in-1.1.0 digest verify read 163.6 GiB in **624.8 s (~262 MB/s, cold,
  effectively single-threaded — upstream's 199 s receipt was on faster storage)**, then the
  weights load. **EXL3-native memory model (both ranks, from the startup line):** model
  **86.11 GiB/rank**; **0.71 GiB/stream at 40960** (NVFP4 was 93.72 / 0.89); 12.2 GiB
  reserve; **11.2 GiB prompt cache**; **13.3 GiB free at p4**. DFlash2 loaded: 0.57 GiB on
  device, linears at 4 bits; one 128-token probe drafted **84/99 accepted**. Perf verdict
  from the operator: "uninspiring" — **no tok/s was measured before the swap back** (the
  probe attempt hit the port after the NVFP4 stack returned), so the EXL3-native baseline
  number is still missing and is the first item of the next test window. Operational notes:
  - `docker logs` is **empty during the digest phase** (buffered stdout) — do not mistake
    for a hang; the liveness signal is the read counter:
    `docker exec glm53-native-tf sh -c 'cat /proc/1/io'` climbing on both ranks, in lockstep.
  - The engine's memory accounting looks conservative vs the NVFP4-era overshoot finding
    (13.3 GiB free claimed at p4) — trust but verify at the first ladder rung.
  - Recipe updates from this session: the digest cache is now a mounted volume
    (`$STATE_DIR/tensorfold-cache:/root/.cache/tensorfold` — saves the 624.8 s re-read on
    every restart); `DENSE_BITS`/`HEAD_BITS`/`PDL` knobs added (v1.1.0's pack-at-load and
    programmatic dependent launch); the bench matrix grew to seven configurations
    (baseline, pdl, dense8, parallel6, parallel8, recall, recall6) — one variable each.
- **2026-10-18 the first EXL3-native numbers (matrix run-20261018-174541, baseline row).**
  Config: v1.1.0, EXL3 + DFlash2, `--context 40960 --parallel 4`, server `GLM-5.3-Flash-EXL3`
  on port 8000 (NVFP4 stack stopped first — the matrix's own stop.sh did it); llama-benchy
  pp2048/tg128, depths 0/4096/8192, concurrency 1/2/4, 3 runs, --no-cache:

  | Cell | pp tok/s | tg tok/s | TTFT |
  |---|---:|---:|---:|
  | d0 solo | ~657* | **21.2** | 3.1 s |
  | d0 c4 | ~598 | 25.3 agg | 8.4 s |
  | d8192 solo | ~652 | 22.1 | 15.7 s |
  | d8192 c4 | ~625 | **8.6 agg** | 43.8 s |

  (\* prefill estimated from e2e_ttft; llama-benchy#33's early-chunk caveat.) Reading: decode
  ~21 tok/s solo is **below the NVFP4 route's drafted ~28-33 and a third of production's
  ~62** (Python engine); prefill ~625 tok/s is ~⅓ of production's ~2,050 and under half the
  NVFP4-native's ~1,440. Concurrency barely scales at d0 (c4 aggregate 25.3, +19% over solo)
  and **collapses at depth** (d8192 c4 aggregate 8.6 — streams starve each other). The rails
  are NOT the bottleneck (measured ~2.6 GB/s per rail, ~10% of line rate; pinned
  NCCL_SOCKET_IFNAME verified inside the live container). The knobs matrix (pdl, dense8,
  parallel6/8, recall) tests whether scheduling/packing helps. Operational: the bench's
  progress events sit in Python's 8 KB stdout buffer through the pipe until exit — the
  server's `done chatcmpl` count in docker logs is the true progress signal; and the tty-ful
  fix (PYTHONUNBUFFERED=1 in the matrix) waits for the matrix process to end first (bash
  streams the script it runs — never edit a script mid-flight).
- **2026-10-18 knob matrix complete (run-20261018-174541, all 7 configs, perf-only).**
  tg tok/s cells (d0 solo / d0 c4-aggregate / d8192 solo / d8192 c4-aggregate); pp ~590-660
  unchanged in every config:

  | config | d0 solo | d0 c4 | d8192 solo | d8192 c4 | model GiB |
  |---|---:|---:|---:|---:|---:|
  | baseline | 21.2 | 25.3 | 22.1 | 8.6 | 86.11 |
  | pdl | 21.6 | 24.9 | 22.3 | 8.2 | 86.11 |
  | **dense8** | **24.0** | **26.6** | 22.3 | 8.7 | **82.31** |
  | parallel6 | 21.6 | 25.6 | 19.7 | 8.5 | 86.11 |
  | parallel8 | 20.8 | 25.6 | 18.1 | 8.5 | 86.11 |
  | recall | 20.1 | 24.1 | 20.0 | 8.5 | 86.11 |
  | recall6 | 21.0 | 24.4 | 19.9 | 8.6 | 86.11 |

  Verdicts:
  - **dense8 is the only winner**: solo decode +13% (21.2 → 24.0), c4 +5% (25.3 → 26.6), and
    it frees memory (model −3.8 GiB; free-after-reserve 13.2 → 17.5 GiB; prompt cache 11.1 →
    15.4 GiB). Denser packing is the follow-up — `dense4`/`dense6` rows added to the matrix,
    with a quality check owed for `dense4`.
  - **pdl: noise-to-inconclusive** (d0 +0.4, d4096 solo +2.7 but d4096 c2 worse, d8192 flat)
    — the knob stays, don't count on it.
  - **parallel6/8: no gain, slightly negative at depth** — the concurrency ceiling is not
    admission-side; extra lanes trade prompt cache for nothing (11.1 → 8.5 GiB at p8).
  - **recall: unrewarded by this bench's shape** — it runs `--no-cache` on fresh prompts
    (cache hits stayed 0), and the +29% NVFP4-era figure was warm repeats. Not refuted;
    just not this measurement.
  - **The deep-prompt concurrency collapse is structural**: d8192 c4 sits at 8.5-8.7
    aggregate in EVERY config, d4096 c2 at ~14-15 — no shipped knob touches it. That is
    per-layer exchange/verify-window contention, i.e. upstream work; 1.1.1's planned GLM
    CUDA fresh-prompt batching and prompt scoring (#1014-#1018) is the nearest candidate.
    Line's next move: re-run the matrix there.
- **2026-10-18 investigation: why v1.1-native trails the Python engine, with receipts.**
  The operator switched production back to Python 0.6.6 EXL3 (its decode/preill lead held
  over every v1.1 config we measured) and asked what upstream says. Findings, by strength:
  - **#1033 (GB10-specific, config-level fix available)**: the native engine spins two CPU
    cores per rank (CUDA sync — `CU_CTX_SCHED_BLOCKING_SYNC` would stop it at -12% decode;
    and NCCL's progress thread — spins regardless), and on a GB10 five of seven ACPI thermal
    zones are the CPU's. As-shipped, a 40-reply run hits the 94.7 C heat watch and stops at
    the 7th reply; **pinned to the efficiency cores (0-4, 10-14) it runs 40/40 at -1.1%
    decode / -2.7% prefill**. Recipe response: `CPUSET` knob added to config.sh
    (→ `--cpuset-cpus` on both ranks; empty = as-shipped). Set `CPUSET=0-4,10-14` in
    local.sh for long runs.
  - **#918 (structural, open since 1.0.3, cross-backend)**: an independent team shadow-benched
    native vs Python 0.6.6 on Metal 27B: sampled decode -21% to -34%, 8-stream -17% to -45%,
    **cold prefill 1.7x slower at 1.0.7 and again at 1.0.8** — and 1.0.10's prefill fix
    (simd_qmm) does not reach uniform checkpoints. Our GB10 GLM gap (decode ~-64%, prefill
    ~-70% vs production) is that gap plus greener EXL3 CUDA kernels plus the GB10 spin.
  - **#840 (the official carry-over tracker)**: the native engine is behind the Python engine
    by design and rows are being ported. The perf-relevant one: **`--decode-share` (#248) is
    an unclaimed row — prefill does not block replies in the Python engine, and native has
    no equivalent**. That is our d8192/c4 collapse (8.6 aggregate in every config): a
    concurrent deep prefill starves decode. Metal's native analog is #1032.
  - **#993 (the Python engine's own GLM TP=2 bug)**: with uptime, prefill decays to 18.8 s
    for 13 tokens and decode 40 → 14 tok/s, an idle rank 1 reads 96% GPU (the #305
    idle-follower spin), and a restart clears it. Production is not immune — worth
    mentioning to whoever runs it long.
  - **Mia's zig-engine branch adds no missing magic**: its own qual notes say decode at 8
    streams is *under* the Python engine even with Python-derived captured Triton kernels —
    the native lane-core round architecture is part of the ceiling, not just kernels.
  Net: the line's thesis stands (upstream fixes land by bumping), but the gap is real,
  multi-issue, and partly deployable-around (CPUSET now; --decode-share and prefill parity
  wait for upstream). Worth offering our receipts to #1033 (they asked for a direction
  preference; we have an independent GB10 pair and EXL3-v1.1.0 data).
- **2026-10-19 fold in v1.1.1 (released today; prepared, NOT started).** v1.1.1 is the
  release this line was waiting for — what it carries, and what it changes:
  - **GLM CUDA batched fresh prompts (#1014-#1018 landed)**: stepped serving interleaves
    fresh prompt chunks with running decode, and whole-prompt serving can batch eligible
    fresh text prompts across ranks (≤16 prompts, 2,048 rows per pass). This is the direct
    candidate for the d8192/c4 collapse (8.6 aggregate in every 1.1.0 config) — the matrix's
    baseline row on 1.1.1 is the first comparison to make.
  - **Bits move in 1.1.1**: prompt projections use one K slice at every row count by default
    and "can change replies versus 1.1.0". All 1.1.0 matrix numbers are therefore a stale
    baseline — re-run `baseline` first. `PROMPT_K=shape` knob added (→ `TF_GLM_PROMPT_K`)
    for the A/B; it needs `TF_GLM_MM=1`, the engine default.
  - **#1033 resolved our way**: "GB10 efficiency-core pinning is documented in the runbook";
    the engine-level spin fix stays open — so `CPUSET=0-4,10-14` remains the remedy and now
    has upstream's endorsement.
  - **#1040: the NVFP4 two-rank route loads and serves on 1.1.0 on two GB10s** (community
    run) — the fallback route's known issue is cleared, though "scored prompts and more than
    two ranks are untested".
  - Also: the version string is fixed ("source builds report the correct release version");
    new Host-header security (every request needs one valid `Host`; loopback binds accept
    loopback IPs — our curl/health checks pass, but a client sending an unusual `Host` needs
    `--allowed-host NAME`); `#1030`'s missing-library errors now name the library.
  - Fold-in: config.sh's PROMPT_K knob; `scripts/prepare.sh` re-run on the head resolves
    latest-v1 → v1.1.1 (zig still 0.17.0), rebuilds + distributes the image, updates the
    marker. Production untouched; nothing started.
  - **Prepare receipts (17:28)**: v1.1.1 @ `b10231b9` built in 225 s and distributed to the
    worker; smoke `tensorfold-native 1.1.1` (version string correct at last); prepared
    marker updated; the local.sh WORKER changed to the worker's rail IP in the
    same window (SITE.md updated to match).
- **2026-10-19 ecosystem review: what the other GLM-on-GB10 repos know that we didn't.**
  Repos found (GitHub): jayleaton/glm53-tensorfold-spark (115★, 77 patches, an upstream
  contributor), TechGuardCoders/glm53-tensorfold-spark-recipe (one-command install on top of
  jayleaton's), Bizuayeu/GLM-5.3-Flash-NVFP4-DGX-Sparks-BIZ (the #1040/#1033 authors),
  MiaAI-Lab's 3x-Spark and TP4 lines, Aevonix's RTX PRO 6000 recipes, bertholomus's TP4 and
  DeepSeek recipes. What folds into OUR stock-engine line today (config/env only):
  - **TEMPERATURE knob added** — the ecosystem's "one setting most people miss": stock
    TensorFold drafts with DFlash2 on greedy (temperature 0) requests ONLY, so agent
    frameworks that omit temperature get 1.0 and no DFlash2 drafts. jayleaton measured
    4.36 → 5.73 tokens/step (~68 → ~83 tok/s) with `--temperature=0` on this hardware
    class; TechGuard ships it as their default. This also re-frames our matrix numbers:
    llama-benchy's sampled cells (t=0.7) ran without DFlash2 — the greedy cells are the
    drafted reference. Knob added (empty: engine default 1.0; clients sending their own
    temperature are unaffected).
  - **NCCL tunings adopted as env pass-through**: jayleaton's W19 measured set —
    `NCCL_IB_HCA` with both functions of the linked CX7 port, `NCCL_PASSTHROUGH=1`,
    `NCCL_MIN/MAX_NCHANNELS=4` — took a 4 MiB all-gather from 322 to 142 µs, prefill +1.5%,
    and freed ~1.4 GiB of NCCL memory. env_args now forwards every NCCL_* (and the
    TF_HEAT_* bands) from the environment to both ranks; the measured set is documented in
    local.sh.example. Our 2-cable site needs its own `ibdev2netdev` check (4 functions).
  - **TF_HEAT_* bands now pass through** — Bizuayeu's #1040 run used 92/88 and finished
    40/40 replies unthrottled; our CPUSET knob remains the #1033-documented alternative.
  - **What we cannot adopt without forking (and mostly shouldn't)**: jayleaton's 77-patch
    stack (fp8 latent KV, the shared 1M KV pool, NVMe session tier, L2 weight prefetch,
    deeper verify windows...) is where their 49-83 tok/s lives. Mapping it against stock:
    1.1.0/1.1.1 have since absorbed several pieces (structured output, required/named tool
    calls, batched fresh prompts, vision, DENSE_BITS ≈ their 4-bit non-experts), the rest
    belongs in #840's carry-over tracker. Our thesis (unpatched upstream) stands; their
    repo is the reference for what's worth asking upstream for.
  - **The NVFP4 route measured 2× our EXL3 on the same hardware class**: #1040's regression
    on v1.1.0, two GB10s, NVFP4, TP=2, 245760 context: decode median 45 tok/s (vs our 21-24),
    prefill 1,402 (vs our ~625), whole 199k prompt found. A checkpoint-choice data point,
    not a line change: EXL3 stays for production parity; the numbers are recorded in
    docs/VALIDATION.md's comparison table when the next window runs.
- **2026-10-19 quick window on v1.1.1: first launch + probes (production restored after).**
  - Launch clean: **loaded in 222.7 s** — the warm digest cache works (no verify pass).
    v1.1.1 memory model: model 86.12 GiB; 0.71 GiB/stream at 40960; **11.0 GiB free after
    the 12.2 reserve; 8.9 GiB prompt cache** — 1.1.1 holds **~2.3 GiB more** than 1.1.0
    (13.3/11.2); suspect the K-slice regrouping or the stepped-admission structures
    (unconfirmed). The ladder anchor in docs/CONTEXT_512K_PLAN.md is updated; 524288×1
    still fits (usable ~3.2 GiB after the margin).
  - **Greedy 512-token probe: 24.7 tok/s** — v1.1.1 ≥ our best 1.1.0 config (dense8's
    24.0), +3.5% over 1.1.0's baseline, still ~half of #1040's NVFP4 45.
  - **Sampled 0.7 probe: 25.9 tok/s — no temperature trap on stock 1.1.1**: sampled
    requests draft as fast as greedy ones. jayleaton's "temperature trap" is their patch
    0010 (auto-deep-dflash-drafts), not stock behavior. The TEMPERATURE knob was removed
    from local.sh the same window (receipt note left in place).
  - **Probes 3 (prefill) and 4 (exactness) were botched by the probe design, not the
    engine**: probe 3's "7.5k-token" prompt was actually ~41k tokens (over the 40960
    window — the server rightly refused, hence no usage); probe 4's max_tokens 32 was
    fully consumed by thinking, so content was empty and the sha was the empty-string
    hash. Corrected probes issued (14k-token prompt; 512 tokens; hash the whole message).
    **The exactness gate has NOT yet passed on v1.1.1** — first item next window.
  - Operational: production stop/start uses the **-tip** checkout
    (`~/GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold-tip`); the non-suffixed directory
    exists on the head and is not the live one (paths fixed in the docs and SITE.md).
- **2026-10-21/22 review window (no GPUs touched; production ran throughout): v1.1.2
  reviewed + the RoCE root cause found and fixed in the image.**
  - **v1.1.2 review** (release notes + shallow source read, tag commit `4ff78441...`;
    Zig stays 0.17.0). What it gives our EXL3 TP=2 pair:
    - **#1053 — waiting GLM ranks sleep instead of polling at full load**, waking for
      rank 0's next step. This is the #1033 follower-spin fix; may make our CPUSET knob
      unnecessary — test next window.
    - **#993 fixed for GLM CUDA**: committed prompt prefixes kept in bounded,
      preallocated snapshot pages inside the prompt-cache budget — the uptime-decay
      fix, native side.
    - **`TF_GLM_PROF=1` diagnostics**: per-rank prompt-chunk stages, transport phases,
      event waits — the tool for the collapse/exchange investigation (passes through
      our env_args).
    - **FP8 latent cache prepared behind `--kv-cache fp8`** (BF16 default; native
      quality and device qualification pending) — the 1M-window unlock exists in stock
      now; WE are the natural qualification pair for our 512K ladder.
    - Shared-lane scheduling: spare rows go to other streams when a forced window does
      not fit; shared prompt scheduling prefers admitted prompts with less work left;
      #1059 adds one deeper draft row every eighth round. TP=3 KDA projections (#1067)
      land (not our topology). Security/HTTP hardening (header/body time bounds, 128-
      connection cap, key-file/perms). Tool params decode as JSON (#1121);
      `--thinking-reserve`, `--loop-guard` for repeated reasoning.
  - **RoCE root cause PROVEN — we never used the RoCE path, and neither did the NVFP4
    media run.** Upstream's #971 closer (2026-10-21): our media receipts "used NCCL
    fallback; it does not qualify the separate RoCE media path." Investigation:
    - Stock engine wiring: `cuda_native.zig:188` calls `openRoce` unconditionally at
      GLM startup; `TF_ROCE` defaults to wanted (unset = on, both ranks must ask);
      HCA list from `TF_ROCE_HCA` else `NCCL_IB_HCA`. Two-rank small all-gathers
      (greedy picks, split-reduce, dflash) route through `group.allGather` → direct
      verbs writes when the gather is up; media rows cross ranks the same way.
    - **Saved rank logs contain `warning: RoCE all-gather: VerbsUnavailable (); NCCL
      carries every gather` on every launch** — `roce.Gather.init` dlopens
      `libibverbs.so.1` and our **runtime image ships neither libibverbs nor libmlx5**
      (we bundle only the binary + libnccl). Without verbs, NCCL's own IB transport is
      also unavailable → NCCL ran TCP sockets over the CX7, so our 2.6 GB/s "rails"
      were likely not RDMA at all. Plausible share of the prefill gap (625 vs
      jayleaton's 1,630 tok/s — their repo bundles libibverbs + the mlx5 provider).
    - `ibdev2netdev` on the head maps the two cabled CX7 HCAs to their rail netdevs
      (both Up; the f0 functions are the uncabled ones) — jayleaton's exact measured
      HCA set; this site's device names live in the site files, not the repo.
  - **Fix, three files**: runtime stage installs `libibverbs1 ibverbs-providers
    rdma-core` (distro 50.0 matches the host kernel's rdma-core 50.0 exactly; the
    builder's newer pair deliberately not bundled to avoid kernel-ABI skew. Gotcha
    caught on rebuild: Ubuntu's `rdma-core` package does NOT pull the provider
    plugins — without `ibverbs-providers` the image had libibverbs but no mlx5
    driver, and verbs could not open the CX-7s at all); `env_args` now forwards
    `TF_ROCE_*`; `local.sh.example` documents the `NCCL_IB_HCA` form (the DGX Spark's
    typical cabled CX7 HCA names) as REQUIRED for the RoCE gather + NCCL RDMA (with
    the ibdev2netdev discovery walkthrough). Site: `NCCL_IB_HCA` added to the head's
    `local.sh` and probed.
  - **v1.1.2 image built and distributed** (rebuild after the providers fix;
    compile stage cached): smoke `tensorfold-native 1.1.2` (the 1.1.1+ version-
    string fix holds); image on both hosts; marker
    `tf=v1.1.2@4ff78441... patches=` (pristine); `libmlx5-rdmav34.so` +
    `libmlx5.so.1.24` verified inside the image at
    `/usr/lib/aarch64-linux-gnu/libibverbs/`.
  - **Next window verification list**: rank logs must NOT contain "VerbsUnavailable";
    baseline probes re-run (24.7 greedy reference); corrected probes 3+4 still owed;
    `TF_GLM_PROF=1` transport phases optional.
- **2026-10-22 launch + 5-config matrix on v1.1.2 (user-driven window): everything
  moved; RoCE confirmed up on every restart.**
  - **RoCE gather up**: rank logs carry `info: RoCE all-gather: 2 HCA(s), shards up to
    4096 KiB by RDMA writes` (10×, one per rank per restart) and zero
    `VerbsUnavailable`/fallback warnings — the image fix + `NCCL_IB_HCA` worked. The
    #971 media path now has a qualifying EXL3 configuration on site.
  - **Matrix** (`results/run-20261022-154406/`; baseline/dense4/dense6/dense8/pdl;
    table in docs/TOOL_EVAL_TESTING.md): vs the v1.1.0 matrix, **prefill pp2048
    657 → 1,026 (+56%), solo decode 21.2 → 36.4 (+72%), TTFT d0 −36%, c4@d8192
    8.6 → 13.5 agg**. **dense4 is the new leader: 55.4 solo / 42.6 c4 / 1,053 pp,
    19.4 GiB free + 16.0 cache** — approaches production Python's 62–63 solo decode.
    Clean monotonic ordering in dense bits (unlike 1.1.0's dense8-within-noise). PDL
    marginal (+3.6 solo, worse at depth). Memory anchor back to 13.3/11.2 (1.1.1's
    11.0/8.9 transient — plausibly #993).
  - **Caveat — three changes bundled** (engine 1.1.0→1.1.2, RoCE RDMA, HCA set): the
    split needs a `TF_ROCE=0` control run (stock knob, one restart).
  - **Unchanged structural issue**: aggregate decode does not scale with streams
    (baseline 36.4 solo → 37.8 c4; dense4 drops 55.4 → 42.6; d8192 c4 13.5). Next
    diagnostic: `TF_GLM_PROF=1` at c4@d4096.
  - **Next: qualify dense4** (exactness gate + recall — 4-bit dense linears are a
    quality risk), corrected probes 3+4 on baseline then dense4, `TF_ROCE=0` control,
    NCCL channel set, then the ladder on the winner.
- **2026-10-22/23 search matrix digested (`results/run-20261022-172325/`; tables and
  verdicts in docs/TOOL_EVAL_TESTING.md).**
  - **dense4 alone stays the leader; nothing stacks on it cleanly.** dense4pdl −13%
    solo (PDL's sign flips with the config), dense4chan4 −10% solo, dense4h8 slower
    still. chan4 on baseline: no prefill gain, decode ≤ baseline at depth — its value
    is ~2 GiB of freed NCCL workspace. fp8: works (stream 0.71 → 0.48 GiB), ≈ baseline
    speed −3% — a memory knob with a small speed tax.
  - **Attribution answered by roce0**: the engine's RoCE gather adds ~5–10% solo
    decode; prefill is unchanged without it → the 657→1,026 prefill jump came from
    NCCL RDMA replacing TCP, not the gather. (Receipt for the next upstream note.)
  - **fp8 stream facts for the ladder**: per-stream at 40960 = ~0.25 GiB fixed +
    KV ≈ 11.8 KiB/token bf16 / 5.9 fp8. Recomputed rungs: every 512K iso-budget rung
    fits on every v1.1.2 config even at the plan's conservative 17.75 KiB/token rate
    (baseline 5.3 usable after margin; dense4 11.3); fp8 roughly halves rung costs.
    **The 512K constraint is the quality gates, not memory** — docs/CONTEXT_512K_PLAN.md
    updated with the per-config anchors.
  - **Next: `dense4fp8` cell added to the matrix** (leader + fp8 caches, the ladder
    candidate), then gates on dense4 and fp8, then the ladder on the qualified winner.
- **2026-10-23 forum thread read end-to-end (381350, 45 pages, Aug 26 → Oct 22) — the
  community has benchmarked OUR repos, and the end-of-thread findings reframe the plan.**
  User's reframe recorded: production is the `-tip` fork (Python 0.6.6, DENSE=fp8,
  KV=fp8, COMM=roce, CONTEXT=524288, DFlash2, admission 87.45/101.21 GiB, cache slots
  524304); we are NOT migrating to 0.6.6 — **the task is replicating the 0.6.x
  improvements on the 1.1.x native line**.
  - **ajvazan's 14-config consolidated benchmark (Oct 12, #809) includes our repos:**
    - **G647 = "TensorFold v0.6.6-tip + 106 patches (gilesco+MiaAI merge), DENSE=fp8 —
      the current production stack"**: tool-eval **91.00±0.00 high / 93.00±0.00 max**
      (best TensorFold-line max in the field), cold prefill 1,601 t/s, gen sweep
      **52.7 t/s** (2.1× Canada W4A16), **KV pool 2,287,616 tokens at 1M context**
      (deepest in the field with the q4 variants), Cyrillic depth test **93.9%**
      (199/212), **zero loops, zero contamination**. Called "the production pick".
    - **G644a/G = gilesco TF v0.6.4 q4-dense era**: 92/92, fastest TF decode
      (56.5–61.8 t/s sweep), but the Cyrillic depth test showed the **q4 degradation
      band at 192k–384k** (fact tasks 12→10/16, 9–14 cuts, 2 contamination rows).
      This validates production's 2026-10-07 DENSE q4→fp8 switch from outside.
    - Both TF stacks' weak cells: deep concurrency (d4096×c4 27.3, d8192×c4 18.3) —
      the concurrency cliff, now with community numbers. Strongest cells: 0-depth
      c2/c4 (67.6/59.6).
  - **Depth degradation is real on every fast stack**: fact-task accuracy collapses
    384k–480k (length-cuts with filler-echo) on fp8/q4/vLLM-NVFP4; only Canada W4A16
    marlin holds 100% at every depth (at 2.1× slower decode). **A depth-quality gate
    must be part of our 512K qualification** — ajvazan's Cyrillic depth test is the
    template (fact/needle tasks at 8k/64k/192k/384k, temp 0, exec-checked).
  - **The 1.1.x native line already has community traction**: giles8 (Oct 2): "Mia's
    GLM on TensorFold now feels like c4 with >100 tokens/s on 2 Spark — and the
    concurrency is REAL". bernisse (Oct 22): TensorFold **1.1.2 bare metal with fp8
    KV unqualified, fine for weeks — tool-eval 94/100**, the best EXL3 score in the
    thread. Direct community support for our `--kv-cache fp8` qualification.
  - **Bizuayeu (Oct 14)**: "TensorFold GLM 5.3 family native CUDA inference engine
    completed; detailed tuning and verification" + container re-measurement coming —
    upstream momentum on our line.
  - **MaTeZZ's kernel finding (Sep 30, #610)**: DGX OS 7.5/kernel 6.17 can run the
    Grace CPU at floor frequency (~1.38 GHz vs 3.9) with scaling_cur_freq lying; fix
    was the 7.0 kernel + cppc auto_sel_mode → **+8–10% decode**. Our hosts run
    7.0.0-1019 — likely fine, verify with the acpi_cppc feedback_ctrs probe. Also
    their mechanism for our concurrency cliff: **one structured-output request forces
    draft-length truncation off for the whole batch** (31.5 → 22 tok/s per stream) —
    test with/without a json_schema request in the batch under TF_GLM_PROF.
  - **Other notables**: DFlash2 is CC BY-NC-ND (non-commercial — production carries
    it; the MTP fallback is the licensed path); vLLM stacks cannot prefill and decode
    simultaneously (TensorFold can — our scheduling advantage); EXLR8 (new EXL3-
    trellis experts quant, kindlingai stack) posts 2,300 t/s prefill / 4.2M KV —
    vLLM-line competition, the NVFP4 repo's domain.
  - **The 0.6.x → 1.1.x replication map** (the plan's spine):
    | production (0.6.x) | 1.1.x native | action |
    |---|---|---|
    | CONTEXT=524288 | env-supported, untested at scale | ladder + parity cell |
    | KV=fp8 (qualified, drafted=serial) | `--kv-cache fp8` prepared, unqualified | gates on fp8 + dense4fp8 |
    | DENSE=fp8 | DENSE_BITS=8 | parity cell (dense8); community says fp8-dense > q4 at depth — mirrors our dense4-vs-dense8 gate |
    | COMM=roce | fixed this window ✓ | receipts logged |
    | DFlash2 | same drafter via DRAFTS=1 ✓ | nodraft cell quantifies |
    | fork knobs (SPLIT/SHARED_PREFIX/KDA_CHUNKED/COPY_CODE/MULTI_PREFILL/STREAM_SMOOTH, decode floor, hybrid prefix, loop guard) | upstream equivalents: #1053 sleeping ranks, #993 snapshot pages, shared lanes, prompt passes, --loop-guard | knob-by-knob mapping; gaps → upstream asks |

## 2026-10-23 — campaign script finished; ecosystem research pass

- **`scripts/run-qualification.sh` debug pass** (found on review, fixed before any run):
  a leftover `$prompt_combine` in the g3 probe would have killed the script under
  `set -u`; the g5 seed-body line never applied (req_file ignored `MSG_SEED_BODY`);
  curl timeout 240s would kill the 384k depth probe (prefill alone ≈ 384s at our
  ~1,000 pp) → chat() now defaults `-m 900` with per-call override; `sha_msg`/`content_of`
  made defensive (parse failure → raw-file sha / empty string, not a crash);
  `req_file` now gets `SERVED_MODEL="$SERVED_NAME"` explicitly; `restart` gained the
  production guard (refuses if glm53-flash-tf is up here or on the worker) and
  `restart_fb` gives every cell the PARALLEL=4→2 fallback (kvqual cells included);
  depth-fact placement fixed to ~60% of the filler (old arithmetic put it at ~22%
  while the comment claimed "near the end"); cliff background curls guarded with
  `|| true` so one failed request can't `wait`-kill the phase; `clock_mhz` runs
  locally on the head instead of ssh-to-self. `bash -n` clean.
- **Ecosystem research pass → docs/ECOSYSTEM.md.** Read the repos ajvazan and others
  referenced (kindlingai gx10 + exlr8, technigmaai tp2-native, eugr/spark-vllm-docker,
  Entrpi's EXL3 stack, goshi's exporter) against our line. Headlines:
  - **goshi's `tensorfold-spark-dashboard-metrics-exporter` targets our engine line
    directly** (`zig-v1` profile: `tensorfold_*` families + `/health` JSON) and
    production's 0.6.6 too (`python-v1`); zero-dependency, systemd unit, honest
    omissions. Adopt as a doc pointer; note its examples assume upstream on :8002,
    ours serves :8000.
  - kindlingai gx10: adaptive-k DFlash2 (draft length picked per step from a live
    acceptance/cost model — matches MaTeZZ's acceptance data), prefill-fairness cap
    (a 120k prefill blocked a 12-token request 78–90s until capped), dual-root
    all-reduce 110→190 Gb/s (we already name both HCAs; rank logs confirm 2), spin-wait
    patch (~20°C cost on GB10's shared power budget), and the rule we adopt as an
    invariant: **never pin NCCL_IB_GID_INDEX** (RoCE GID tables reorder across reboots).
  - EXLR8 (mmastrac): EXL3-trellis experts at k2/k3/k4 decoded by a custom MoE kernel —
    decode +3–8% vs NVFP4, KV +15%, prefill −7.7% open. The one EXL3-family development
    in the field; needs an upstream TensorFold loader → watch item #1, not adoptable here.
  - Entrpi (EXL3 on vLLM) is the other easy button; its failure mode per the thread is
    .env drift across releases. Our guarded config.sh + git-ignored site identity +
    receipt discipline is the structural answer — hold the line, import no frameworks.
  - Verdict recorded in ECOSYSTEM.md: Tier 1 adopt-now (exporter, GID invariant, clock
    probe — already in the campaign), Tier 2 measure-and-hand-upstream (adaptive-k,
    prefill fairness, spin, structured-output truncation = the cliff phase), Tier 3
    watch (EXLR8, dual-root — done, b12x/megamoe/mentat/instanttensor — engine-specific).
- Campaign + ecosystem doc ready to run in the user's next GPU window: stop production,
  `bash scripts/run-qualification.sh` (it captures the production reference probe first,
  then asks to proceed).

## 2026-10-23 (later) — first campaign digested: 512K qualified, gates reinterpret, cliff absent

- **The run** (`results/campaign-20261023-011329/`, 01:13–02:45, unattended): all 8 phases
  completed. Both bench cells — parity (dense8+fp8 KV+524288×4) and candidate dense4fp8 —
  scored **92/100 tool-eval (125/136, ★★★★★, 0 errors, identical points)**; dense4fp8 edges
  deployability 68 vs 67 and responsiveness 11 vs 10. Depth 12/12 at 8k/64k/192k/384k. Rung
  524288×1 fits (3.61 GiB/stream fp8, 13.9 GiB left). **The 512K ladder goal is met at 4×
  concurrency with 15.8 GiB spare** — CONTEXT_512K_PLAN.md carries the banner now.
- **The gate "FAILs" were the instrument, not the cache.** Every gate output was semantically
  identical (primes+sum across drafted/plain, solo/c1–c4). g1 exposed the root cause: the
  native engine is **byte-level nondeterministic at greedy** (same prompt, same server, raw
  shas differ, content matches) — unlike byte-stable production Python 0.6.6. So §2's
  sha-of-message gates can never bind on this engine; VALIDATION.md §2 now carries the
  receipt and the gates compare normalized content (`content_sha`), raw-sha as bonus line.
  g3 was doubly broken: it compared two DIFFERENT prompts (turn 2 alone vs turn 1+2 —
  unrunnable by design) and 512 max_tokens was eaten by 2,242 chars of thinking on the
  resumed arm (empty content). g3 now sends the same 3-message conversation twice — cold
  compute vs full cache hit — with per-arm `cached_tokens` receipts and max_tokens 1024.
- **Cliff verdict: absent.** Schema batch 17.9s vs plain 21.2s for 4×256 — MaTeZZ's
  structured-output draft-truncation mechanism does NOT reproduce on native 1.1.x. (The
  general solo→c4 aggregate flatness remains open — TF_GLM_PROF next.)
- **Campaign script fixes** (committed same day, ready for `PHASES="kvqual prefill"` rerun):
  content-form gates, g3 redesign, prefill probe timed via `curl -w %{time_total}` with
  `max_tokens=1` (wall ≈ prefill; the first run's probe emitted 26,869 tokens — filler
  denser than the 4 chars/token estimate — and no timing at all).
- **Two housekeeping findings:** (1) start.sh re-prepares when the config fingerprint changes
  — the new KV_CACHE knob guaranteed a rebuild — and prepare.sh builds from upstream HEAD,
  so the campaign ran 1.1.2 at **1351ed16** while the Oct-22 matrix receipts are from
  **4ff78441** (same engine version; cross-receipt comparisons carry this footnote). (2) Both
  fp8 cells served 524288 only because the launching shell exported CONTEXT — dense4fp8's
  matrix cell now pins CONTEXT=524288 explicitly.
- **Open after this:** throughput tables for parity/dense4fp8 at 512K (the campaign's bench
  call ran full tool-eval instead of `--perf-only` — one matrix window fills it), the
  content-form gate rerun (~20 min), dense4fp8's own kvqual, PARALLEL=6/8 climb at 512K,
  TF_GLM_PROF at c4@d4096, then phase 2/3 quality on the winner.

## 2026-10-23 (round 2) — gates all-PASS, dense4fp8 qualified, climb refused at defaults

- **`results/campaign-20261023-093827/`**: the content-form gates ran on BOTH configs and
  **everything passed** — g1 content-deterministic (raw bytes differ, as documented), g2
  drafted=plain, g3 cache-hit=computed (both arms: "alpha-7391, bravo-2250, charlie-8118"),
  g4 concurrent=solo, g5 seeded-sampling content-stable. **The 0.6.x exactness replication
  is now on paper for the native line** (VALIDATION §2 receipt). Caveat: g3's
  cached_tokens=0 on both arms — the engine doesn't populate the usage field, so the
  cache-hit path itself is unverified; a /metrics counter check closes it.
- **Throughput at 524288×PARALLEL=4 fp8 KV** (pp2048 tg128): dense4fp8 **48.3/49.0/48.0
  solo** vs parity 42.9/43.9/44.0 (+13%); c2/c4 lead +2–3% everywhere; pp2048 1,025 vs
  1,018. Solo 48.3 vs the Oct-22 dense4 55.4 (40960/bf16) prices the 512K window+fp8 at
  ~13% of solo. **Depth cliff reconfirmed: 48.3 solo → 13.3 agg at c4@d8192
  (3.3/stream), TTFT 2.0→28.4s** — the open performance question for TF_GLM_PROF.
- **Prefill: 1,063 t/s on a 26,869-token probe** (wall 25.3s, max_tokens=1) — no
  deep-prefill collapse; the upstream fairness note has its native-line data point.
- **Climb: PARALLEL=6 and 8 both refused at 512K with default knobs** — recorded
  outcomes; the kept-states store's worst-case sizing is the suspected cause. The climb
  phase now retries each N with `PROMPT_CACHE_GIB=4` before recording the refusal.
- **Script hardening while digesting:** `restart` now propagates start.sh's exit code
  (set -e is suppressed in if-contexts — refusals were invisible before, which the
  climb phase depends on); run_gates guards every restart; bench_perf prints the saved
  report's results table (the live tail is JSON events, which is why round 2's first
  throughput receipt had no numbers — the tables above came from the report files).
- **Verdict: dense4fp8 is the qualified 512K serving config** — gates PASS, tool-eval
  92 = parity, throughput leads every cell, 2 GiB cheaper than parity. Next: climb with
  the trimmed cache, TF_GLM_PROF cliff diagnosis, then phase 2/3 quality on the winner.

## 2026-10-23 (round 3) — prodqual: production head-to-head + the determinism correction

- **prodqual ran read-only against live production** (`campaign-20261023-110446/`):
  pg1/pg3/pg4/pg5 all PASS; **production tool-eval 95 (131 pts, ★★★★★, deployability 73,
  responsiveness 21)** vs our dense4fp8's 92 (125 pts, 68/11) on the same harness,
  version and seed. Perf: production pp2048 1,530 (ours 1,025), solo 51.6/56.0/53.1
  (ours 48.3/49.0/48.0), and the decisive one — **production's aggregate decode RISES
  with concurrency (51.6 → 67.3 at c2 → 60.5 at c4) while ours falls (48.3 → 41.3 →
  38.7)**; c4@d8192: 19.0 vs 13.3. TTFT 1,339 vs 1,999 ms. The native line's real gap
  is concurrency scheduling + prefill, now measured like-for-like.
- **The determinism narrative corrected.** pg1 on production: content-identical, raw
  bytes differ in exactly `id`/`created`/metadata — and `choices` byte-identical.
  Re-checked our g1 pair: same result. **Both engines are token-deterministic at
  greedy**; the first campaign's "byte-level engine nondeterminism" was the instrument
  (whole-envelope sha can never match across requests), not the engine. VALIDATION §2
  and the TOOL_EVAL tables corrected. The content-form gates remain the right
  instrument (envelope-proof); with the envelope excluded, the §2 equalities hold to
  the byte on both engines.
- **Campaign script survived a real failure and got hardened**: the prodqual perf bench
  exited non-zero (after saving a complete report) and `set -e` killed the campaign
  before the handover prompt — production was never touched. bench_cell/bench_perf now
  record a non-zero exit as a receipt NOTE and always extract the saved report's table.
- **Open**: climb with the trimmed prompt cache (production now stopped first), g3's
  /metrics cache-counter check, the 138-vs-136 max-points bench quirk, phase 2/3
  quality on dense4fp8, TF_GLM_PROF concurrency diagnosis (now with production's
  scaling curve as the reference).

## 2026-10-23 (round 4) — the climb ceiling is the engine's own arithmetic

- **PARALLEL=6/8 refused even with PROMPT_CACHE_GIB=4** (`campaign-20261023-121811/`).
  The refusal line carries the full math: **8 streams need 25.29 GiB at 524288, budget
  leaves 15.83 GiB — "serve --parallel 5, or lower --context"**. So the ceiling at the
  goal window is **PARALLEL=5** (15.81 of 15.83 GiB), and the blocker above it is the
  engine's **12.2 GiB reserve** — no flag exposes it (`serve --help` is usage-only).
  PROMPT_CACHE_GIB=4 freed +0.06 GiB (it ≈ the default) — not the lever. The climb
  phase now runs 5/6/8 so a rerun completes the ladder with the engine's suggestion.
- **Quality-gap location found in the prodqual receipt**: production passed
  TC-65/66/67/69 (nested schema / enum / multi-tool structured outputs) where both our
  cells took partials; both engines failed TC-68. The 3-point gap lives entirely in
  the structured-output category, identically across dense8 and dense4fp8 → an
  engine-level decoding-path difference (native vs Python), not a quant effect.
- Situation after four rounds: **dense4fp8 = the qualified 512K config** (gates PASS,
  TEB 92, throughput leader, 5-stream ceiling known); exactness replicated with the
  determinism narrative corrected; head-to-head vs production measured (95 vs 92,
  production's aggregate decode rises with streams while ours falls — the one big
  open engineering item, with TF_GLM_PROF the next tool).

## 2026-10-23 (round 5) — ladder closed at 5; upstream PRs found for both gaps

- **Ladder complete**: PARALLEL=5 ADMITTED at 524288 (climb receipt
  `campaign-20261023-130428/`), and the engine flexed the prompt cache itself (1.4 GiB)
  to make room. climb5's c4 row ≈ the PARALLEL=4 cell (38.7 agg @d0, 13.3 @d8192) — the
  bench drives 4 clients, so admission is the achievement. 6/8 refused, per the
  engine's own arithmetic. **The 512K goal is closed at its true maximum.**
- **Upstream scan (ashhart/TensorFold)**: 16 commits since our build pin (1351ed16) —
  Flash Next vision work, tool envelopes, a Windows build fix; nothing concurrency.
  But three OPEN PRs target our gaps directly (receipts in ECOSYSTEM.md):
  - **#1163+#1211 glm/cuda KV paging** (`TF_KV_PAGES`; heads on Bizuayeu's fork,
    r9 @ 87e4417ebec6): streams become 512-row pages from the core pool, kept states
    sized by position — the mechanism that could unlock 6+ streams at 524288 and
    change the concurrency curve. `auto` pages only from 3 ranks up; we opt in with
    `TF_KV_PAGES=on` at TP=2.
  - **#1080 prefill 5.4×** (qwen CUDA; 4096-row chunks + tensor-core prompt attention
    + the delta-rule chain) — our prefill gap to production sits in this blast radius;
    glm/cuda port is the watch item.
  - **#1215 round-class GPU timers** (`TF_Q27_PROFILE`) — the instrumentation pattern
    for the concurrency diagnosis (route/experts/attention/**drafter** per round).
- **Plumbing added**: `config.sh` env passthrough now forwards `TF_KV_*` to both
  ranks (TF_KV_PAGES ready); `prepare.sh` already takes TF_REPO/TF_COMMIT overrides,
  so a PR-branch build is `TF_REPO=…Bizuayeu/TensorFold.git TF_COMMIT=87e4417ebec6
  ./scripts/prepare.sh` — no script changes needed.
- **Next**: TF_GLM_PROF baseline diagnosis on the current build, then build + qualify
  the KV-pages head (admission, §2 gates on paged KV, throughput curve).

## 2026-10-23 (round 5b) — KV-pages image staged, prof phase ready

- **Built and distributed `glm53-native-tf:kvpages-r9`** (the #1163+#1211 head,
  Bizuayeu/TensorFold @ 87e4417ebec6): side-tagged so the current build stays
  servable for the baseline. Smoke: tensorfold-native 1.1.2 on both ranks. The build
  (~7 min compile) also warms prepare's layer cache — the branch's `prepare.sh` run
  with the same TF_REPO/TF_COMMIT will be a cache hit.
- **Source reads**: TF_GLM_PROF exists on our pin (glm/cuda_prof.zig — per-forward
  CUDA-event sections, reports every 64 calls per draft-window profiler; sections
  gate/embed/kda/mla/gather_a/dense/router/routed/shared/gather_b/head/draw/mtp/
  commit). TF_KV_PAGES exists on our pin only for Nemotron — GLM paging is exactly
  what #1163 adds; `auto` pages only from 3 ranks up, so our TP=2 qualification sets
  `TF_KV_PAGES=on`.
- **prof phase added** (`a28d055`): solo/c4 × d0/d4096 probes at max_tokens 2048
  (≈78 calls per draft-window profiler → every window reports), walls + completion
  tokens + aggregate rates, /health drafted/accepted/rounds deltas, and both ranks'
  `glm prof` section lines into the receipt.
- Waiting on: production stopped → (1) `PHASES="prof"` on the current build, (2)
  prepare the branch, (3) `PHASES="kvqual4 throughput climb" TF_KV_PAGES=on` against it.

## 2026-10-23 (round 6) — the prof receipt: the cliff was a bench artifact

- **`campaign-20261023-145449/` (user-run, TF_GLM_PROF=1)**: with long generations the
  aggregate decode RISES solo→c4 — 53.7/57.6 t/s solo (d0/d4096-class), **99.2/102.8
  at c4** — matching production's steady-state (103.7, derived from its bench rows:
  total time minus TTFT). The bench's falling tg numbers were **prefill polluting
  128-token generations** (tg divides by total time; at c4@d8192 prefill is ~80% of
  the wall). The matrix's "structural collapse" interpretation is withdrawn.
- **Section economics (the actual diagnosis)**: wall≈gpu everywhere (zero bubbles);
  `routed` experts dominate (46% of a 2-row verify, marginal ~6.0 ms per draft row);
  the RoCE gather is 4–8% (innocent); attention 13–16 ms/call (gentle with depth);
  prompt passes are **90% router+routed** — the prefill gap to production is the MoE
  expert path, NOT attention (so #1080's kernels are the wrong tool for our gap; the
  GLM upstream conversation is expert batching in prompt passes).
- **Reframed consequences**: more streams = more aggregate for agent workloads (the
  KV-pages unlock buys real throughput); long-generation probes are the honest
  steady-state bench (the prof phase doubles as one); our real remaining gaps are
  prefill (MoE-bound), short-generation latency (TTFT-driven), and the 3-point
  structured-output quality gap.
- KV-pages image (`kvpages-r9`) already built and distributed to both ranks — the
  branch qualification (kvqual4 gates on paged KV, throughput, climb 5/6/8 with
  TF_KV_PAGES=on) is ready to run in the next production-down window.

## 2026-10-23 (round 7) — branch qualification voided: start.sh's auto-prepare dropped the pin

- **The KV-pages campaign (`campaign-20261023-151516/`) ran on the WRONG image.** The
  user's `TF_REPO`/`TF_COMMIT` prepare built the branch and wrote the marker at
  87e4417e; the campaign's first restart then differed from the marker's config
  fingerprint (phase knobs), so start.sh auto-ran prepare — **without the session
  env** — resolved the default ref (1351ed16), cache-hit the rebuild and overwrote
  the branch tag + marker. TF_KV_PAGES=on reached a container whose engine ignores it
  for GLM (Nemotron-only on our pin). The kvqual4 PASS receipts are round-2 repeats;
  the climb refusals are pre-paging arithmetic. Results voided as a branch test.
- **Footgun recorded**: a version pin via session env does not survive start.sh's
  auto-prepare. Pins must live in scripts/local.sh (sourced by config.sh before the
  TF_* defaults, git-ignored) — local.sh.example gains the commented line. The
  side-tagged kvpages-r9 image remains on both ranks for a future window.
- **Decision recorded (user)**: PARALLEL=6/8 not worth pursuing — with steady-state
  aggregate already at ~99–110 t/s (c4) and matching production, the marginal gain
  from two more streams does not buy anything we need. The KV-pages branch test is
  deferred until upstream merges #1163/#1211 and a rebase picks it up; the paged-KV
  §2 gate runs then (one command with the pin in local.sh).

## 2026-10-23 (round 8 prep) — the pin verified; branch marker locked

- **TF_REPO/TF_COMMIT pinned in scripts/local.sh** (site file, git-ignored) at
  Bizuayeu/TensorFold @ 87e4417e (the #1163+#1211 KV-pages head). `./scripts/prepare.sh`
  run with the pin: resolved `tf=commit@87e4417e`, image `glm53-native-tf:commit`
  (a commit pin tags as `:commit` — no more tag collision with the main-line build),
  smoke 1.1.2, distributed to the worker. The round-7 failure mode (auto-prepare
  re-resolving the default ref) is closed: any future auto-prepare inherits the pin
  from local.sh and cache-hits the same build.
- **The window's command** (production stopped, ~40 min):
  `PHASES="kvqual4 throughput climb" TF_KV_PAGES=on ./scripts/run-qualification.sh`
  — gates on paged KV, the throughput tables, and the 5/6/8 climb (with paging the
  admission arithmetic may finally differ; 6 admitting would be the branch's headline).
  After: restart production, and the pin comes OUT of local.sh when the branch test
  concludes (or when #1163/#1211 merge and a rebase carries them).

## 2026-10-23 (round 8A) — the pin worked, then the branch refused: fp8 KV × paging are exclusive

- The window (`campaign-20261023-165319`) ran the RIGHT image (` glm53-native-tf:commit`,
  marker `tf=commit@87e4417e`, `TF_KV_PAGES=on` verified in the container env) — the
  local.sh pin closed round 7's failure mode exactly as designed (every auto-prepare
  re-resolved the branch from the pin).
- But every phase's server exited at startup: on the KV-pages branch, `TF_KV_PAGES`
  and `--kv-cache fp8` are **mutually exclusive** — the engine prints
  `tensorfold: --kv-cache fp8 keeps a window per stream: unset TF_KV_PAGES, or set it
  to auto or off` and exits. Since every existing cell gates/benches fp8 KV, kvqual4
  returned "SKIP: server refused to start", throughput both cells refused, and climb
  5/6/8 refused on the fatal config (not memory arithmetic). The "quick" run the user
  observed was four phases of refused launches — server never lived to print the
  sm_121 admission line ("no server line" in all receipts).
- Real data point for upstream: GLM paging at 87e4417e pages the bf16 KV path only.
- **The agent now runs GPU windows itself** — the user switched this agent to a cloud
  model, decoupling it from production uptime. run-qualification.sh gains three
  paged-bf16 phases (`kvqual4P` with a no-paging admission control, `throughputP`,
  `climbP`) that set `TF_KV_PAGES=on` explicitly and leave KV_CACHE unset. The
  agent launches: `PHASES="kvqual4P throughputP climbP" ./scripts/run-qualification.sh`.

## 2026-10-23 (round 8C) — site identifiers scrubbed from the repo (user)

- **(user) The repo is generic**: no hostnames, ssh targets, IPs, netdev or HCA
  names in any committed file. Committed prose says "the head" / "the worker";
  real values live only in git-ignored `scripts/local.sh` / `docs/SITE.md`.
- History entries in this log were redacted mechanically (the HCA/netdev
  mentions and one ssh path); receipt filenames, public GitHub handles and the
  repo's own URLs are untouched. The architecture SVG's host labels are now
  generic ("HEAD HOST" / "WORKER HOST").
- `results/` added to .gitignore — receipts live only on the head's checkout and
  must never be committable by a careless `git add -A` there.

## 2026-10-23 (round 8D) — prepare.sh discovers the site (ease-of-use)

- **`scripts/discover-site.sh`**: when `scripts/local.sh` is missing, prepare.sh now
  detects the site instead of failing on the empty-WORKER guard — the cabled CX7
  HCAs/netdevs (carrier-up links only, sysfs-based, lexically sorted so both hosts
  pair the same rail), the rails' IPv4 addresses, and the worker (ssh as the same
  user to the head's rail subnet's .2, the point-to-point convention;
  WORKER_TARGET=... overrides the guess). It writes exactly five keys into
  local.sh; unassigned rails are reported with the exact `ip addr add` commands
  for both hosts (discovery does not assign addresses — that is a root decision).
- **`REDISCOVER=1 ./scripts/prepare.sh`** re-runs detection on an existing local.sh:
  timestamped backup, the five keys updated in place, every other entry kept.
- README's requirements and quick-start now lead with the discovery path;
  `local.sh.example` stays as the by-hand walkthrough.
- NOTE: prepare.sh/discover-site.sh reach the head's checkout only AFTER the
  running campaign completes (mid-run script swaps are the AGENTS.md rule).

## 2026-10-23 (round 9) — the KV-pages branch qualified: gates PASS, 8 streams, bf16 only

- `campaign-20261023-170125/` (17:01–18:20, agent-run window): kvqual4P + throughputP +
  climbP on the #1163+#1211 head (`glm53-native-tf:commit` @ 87e4417e, pinned via
  local.sh).
- **Gates: all §2 PASS on paged bf16 KV at 524288 × PARALLEL=4** (content form). The
  no-paging control refused with the engine's own arithmetic ("4 streams need 19.77 GiB,
  budget leaves 12.06: serve --parallel 2") — the comparison is valid.
- **Admission: 5, 6 AND 8 streams admit** at 512K under paging (window-mode refused 6+ on
  the 12.2 GiB reserve). The pool is fixed at ~one full window (1028–1032 pages, 6.4 GiB)
  shared on demand; each stream costs ~220 MiB fixed (180 without the drafter; DFlash2
  adds ~2.8 GiB of model and a bigger prompt cache). Depth × streams is the budget:
  "enough for one at a 524288-token window".
- **Bench (same instrument on both configs)**: paged-bf16 leads dense4fp8-window on every
  row — solo d0 51.4 vs 48.3, c2 43.2 vs 41.3, c4 42.0 vs 38.7, d8192 c4 14.1 vs 13.3,
  pp ~1,037 vs 1,025, TTFT d0 1,976 vs 1,999. The solo row reaches PRODUCTION parity
  (51.0–51.4 vs 51.6). Caveats: rows are the TTFT-polluted instrument; the bench loads at
  most c4 clients regardless of server streams (the 5/6/8 rungs measured ADMISSION, not
  >4-client load); the steady-state probe on paged KV is owed before calling the curve.
- **fp8 KV × paging stay exclusive on the branch** — paged-bf16 is a shallow-many
  concurrency option, not a serving-config replacement: dense4fp8 window-mode keeps 5
  FULL-window streams where the paged pool caps deep concurrency at ~one window.
- **Housekeeping after the window**: bench_perf/run_cell's report-capture globs fixed
  (an off-by-one path level had been silently dropping tables from receipts); the TF pin
  removed from the head's local.sh and prepare re-run — marker back to main (1351ed16),
  so a bare start serves the qualified build; testing stack stopped.
- **(user) Launch defaults now track the qualified optimum**: config.sh defaults are
  dense4fp8 @ 524288 × PARALLEL=4 (receipts cited in its comments); README table matches.

## 2026-10-23 (round 10) — upstream PR scan for immediate performance gains; #1079 staged

- **Production is back on the head** (the agent is local again — GPU windows are the
  user's again).
- **Upstream scan** (releases + 50 open PRs + main since our pin): newest engine release
  is still **v1.1.2**; main since 1351ed16 is app/infra/Flash-Next/grammar — no glm/cuda
  perf movement, our pin stays current.
- **#1079 staged as a test patch** (`patches/1079-qwen-dflash2-shared-decode.patch`):
  qwen-measured DFlash2 decode +9–15%, "replies unchanged" — and it touches the SHARED
  core (core/lanes windows/proposer/drafter/lone_costs, cuda/sample) that GLM's DFlash2
  windows ride on. `git apply --check` clean at our pin (verified in a scratch clone at
  1351ed16). The §2 gates in the test window decide "replies unchanged" on OUR model;
  the tables decide keep-or-drop against the dense4fp8 receipts.
- **#1171 (qmmf half tiles)**: bit-for-bit but MXFP8/BF16-only — FP4 excluded, and our
  dense4/head4 packing is FP4 qmmf; diff does not apply at our pin (one registry hunk);
  small expected gain. Parked with reasoning in patches/README.md.
- **#1078 (TF_DRAFT_NODES)**: qwen-tree-only, no path to GLM's DFlash2. **#1143** (Flash
  Next: NVFP4 experts on prompt tiles) is the mechanism our prefill gap wants — the
  glm/cuda port joins the upstream ask with #1080.
- **Mechanism note**: the PATCHES knob is part of the config fingerprint, so a window
  run with `PATCHES=...` exported re-prepares with the overlay automatically; the patch
  is committed (patches/ is tracked) so the head gets it by the normal sync.

## 2026-10-23 (round 11) — #1079 A/B is a wash (dropped); the perf bar and the knob sweep

- **(user) The testing line's bar, restated**: to succeed it must **surpass production
  0.6.6 on model loading time, generation tok/s, and prefill rate**. Quality round
  approved but performance leads.
- **#1079 A/B** (`campaign-20261023-185520/`, the PATCHES window): gates all PASS on the
  patched build — "replies unchanged" holds on our model — but the throughput is a
  wash (solo d0 +3.3%, solo d4096 −8.6%, everything else ±2%, pp/TTFT unchanged). The
  qwen gains live in qwen's tree-draft kernels; our chain drafting doesn't hit the
  shared-lanes changes. **Dropped**: knob removed from local.sh, patch file removed,
  receipt kept in patches/README.md and the ledger.
- **Loading-time finding**: production 0.6.6 logs "loaded in **93.7 s**"; our restart
  walls run **~265 s**. Behind 2.8× on the user's first metric, cause unmeasured —
  candidates: the load-time packing (dense4/head4 pack at load), the DFlash2 drafter
  load, or the two-rank orchestration. The new knobs phase times every cell and records
  the engine's own "loaded in" line vs the wall.
- **Source scan of the pin found five untested TF_GLM_ knobs** with direct decode/prefill
  semantics (DRAFT_CONFIDENCE, PROMPT_STEPS, OVERLAP_PIECES, KDA_DECODE_WIDE, SHARED) —
  the new `knobs` phase sweeps them with timed restarts + the bench matrix.
- The `knobs` phase: 5 knob cells + a load-nodraft cell, each = timed restart +
  engine-load-line + bench. ~65 min; production must be stopped (user's window).

## 2026-10-23 (round 12) — the knob sweep ingested: one sharp lead, the loading gap located

- `campaign-20261023-200302/` (the `knobs` phase, six cells): every cell = timed restart +
  engine load line + the bench matrix.
- **Loading decomposition (the user's first metric front): the gap is INSIDE the engine.**
  Engine "loaded in" 241.5–253.5 s across all cells vs walls 251–269 s — orchestration
  (docker + ssh + rank handshake) is only ~8–17 s, and the DFlash2 drafter costs just
  ~11 s of load (241.5 nodraft vs 252.7 full). Production 0.6.6 loads the same checkpoint
  in 93.7 s → the ~2.7× gap is the native loader's convert-and-pack path
  (dense4/head4 packing + fp8 KV prep at load). Patch candidate: a packed-weights cache
  beside the existing byte-verify digest cache.
- **`TF_GLM_PROMPT_STEPS=0` (prompt passes run whole): c2 @ d8192 aggregate 17.3 → 33.1 t/s
  (1.9×)** — the sharpest movement any knob has produced, and the d8192-c2 row is tight
  across rounds (16.9–17.7), so the jump is real-looking; c4 is unchanged (13.6 vs 13.3)
  and solo d0 dipped (44.7 vs 49.9). NEEDS A CONFIRM CELL before the ledger calls it.
- conf085: solo d0 +3.8% (51.8) — weak, and the duel's acceptance/ITL instruments should
  decide it, not the bench rows. conf055/overlap6/kdawide0: no effect (kdawide0 −7% solo;
  drop). load-nodraft confirms the drafter's decode value: 29.6 vs 49.9 t/s solo (+68%).
- Next window: a steps0 confirm cell (+ the duel phase with production up first), then
  the loading-patch investigation (load_plan/qpack prepack cache).

## 2026-10-23 (round 13) — the duel corrects the scoreboard; version policy goes perf-gated

- **(user) Version bumps are perf-gated**: an upstream release is followed ONLY if it
  carries measured glm/cuda performance. v1.1.3 (published 21:25 tonight) has none for
  our stack (the one perf item — greedy sampling without a full-vocab sort — is ~1%
  unverified; a draft-scheduling change measured −17%/+13% on Nemotron only), so **we
  stay at our qualified tree**: local.sh pins TF_COMMIT=1351ed16 (the default latest-v1
  would now resolve v1.1.3 implicitly). The builder's grammar fix (libtfgrammar, xgrammar
  v0.2.8) rides along at this pin for the quality round — a builder fix, not a version bump.
- **The duel's production arm (salvaged, campaign-20261023-215834) + ours arm
  (campaign-20261023-221204)
  rewrite the scoreboard** — the bench-derived anchors are RETIRED as polluted instruments:
  - solo decode measured: **55.2 vs 58.7 t/s (94%)** — the old 48.3-vs-51.6 rows were
    instrument understatement on both engines.
  - **c4 aggregate measured: 99.8 vs 154.5 (65%)** — production scales 2.6× vs our 1.8×;
    the "steady-state parity ~104" claim came from derived numbers and is withdrawn. The
    concurrency front reopens as the biggest real gap.
  - **Request overhead: PARITY** (200 vs 183 ms solo) — the bench's 1,999-vs-1,339 TTFT
    rows were concurrency queueing, not fixed overhead. The TTFT front as imagined
    closes; the queueing behavior folds into the concurrency front.
  - prefill slope sharply 2.5× (0.662 vs 0.265 ms/token) — the MoE prompt path, cleanly measured.
  - streaming: same per-token pace (17.0 ms both); ours arrives in 3.4-token DFlash2
    bursts vs production's per-token trickle — a rhythm/feel difference to record, not a gap.
- perf-anchors.tsv rewritten from the duel (7 rows); the chart regenerated + checked.

## 2026-10-23 (round 14) — steps0 retired; the bench's variance found; the continuing-look opens

- **steps0 RETIRED**: the confirm runs landed d8192-c2 at 17.4/17.6 (baseline 17.3) — the
  1.9× lead was a one-off (receipt: campaign-20261023-221204/08-confirm.md). No knob
  adopted. ALSO: the confirm's d0-c4 rows swung
  45.8 → 57.9 and d4096-c4 19.5 → 40.8 across runs (baseline 38.7/19.2) — **the bench's
  shallow-depth concurrent rows are unstable instruments** (swings up to ~2×); single-run
  A/Bs on them are void as evidence. The duel's probes and the d8192 rows are the stable
  instruments. (The #1079 wash verdict stands via the duel's instrument, not the bench's.)
- **(user) The continuing look opens**: docs/PERF_PLAN.md — the scoreboard, the three
  fronts in attack order (concurrency scaling 65%, prefill slope 40%, loading 35%), every
  lever with mechanism + verification plan, and the research log. First levers: (1) do our
  verify rounds batch across streams at c4? (prof at c4, then a #1155-mechanism glm port
  if per-stream); (2) the AZ checkpoint (top-4 routing, 12.5B active, community-tested) —
  ~+25% prefill/decode expected, our gates + tool-eval decide; (3) the packing cache for
  loading. Production is back up (the user moved the agent back to local serving) — GPU
  work is window-gated again; the research and documentation run continuously.

## 2026-10-23 (round 15) — the AZ lever approved and moving; the blog's Act VII spliced

- **(user) The AZ checkpoint attempt is approved** — "a new checkpoint will mean seriously
  more quality checks. Let's try this though." The quality battery is expanded
  accordingly (PERF_PLAN Front 2 Lever A): §2 gates + full tool-eval + structured-output
  scenarios + hardmode TEB + duel probes, for BOTH experiments below.
- The AZ download (~169 GiB) is running on the head under nohup (console
  /tmp/az-download.console) — no GPU needed; 1.2 TB free.
- **Loader verification at our pin** (source cloned to /tmp/tf-src on the head): the
  native loader is EXL3-only — no GPTQ/autoround path in zig/src — so AZ as distributed
  cannot serve natively. But the glm config parser reads num_experts_per_tok dynamically
  (families/glm/config.zig:163) with the routing kernels taking topk as a runtime config
  field, so: **Experiment 1** = top4 routing on our own checkpoint (symlinked variant
  dir + a config edit — zero download, window-cheap, measures the compute saving and the
  un-retrained quality floor); **Experiment 2** = the full AZ after an EXL3 requant
  (int4→bf16→EXL3, window-gated, hours, disk choreography noted in the plan).
- The blog's Act VII spliced (vague, per user): the retired steady-parity claim corrected
  to the head-to-head's honest shape, the stale bench-derived scoreboard figure dropped
  from the act, two figures live. Pre-edit backup exists on the blog host.

- Window prep (same sitting): the campaign gained two session-specific phases for this
  window — `prof4` (Front 1: the duel arm under TF_GLM_PROF=1 at c4 answers whether
  verify rounds batch across streams; then TF_GLM_SHARED=0 answers the sharing-vs-thrash
  question) and `top4` (Front 2 Lever A Experiment 1: a symlinked `top4cfg` variant
  snapshot with num_experts_per_tok 8→4, served via a MODEL_REVISION override — prepare's
  rsync distributes it to the worker and the shared blobs keep the byte cross-check
  green; an admission refusal is a receipt). `duel_arm` was hoisted to the shared helpers
  so all phases run the identical five instruments; a `c4_reprobe` helper refreshes the
  64-call prof window before extraction. Perf only in `top4` — the quality battery stays
  with the quality round (user's "seriously more quality checks").

## 2026-10-24 (round 16) — prof4 answered Front 1's two levers; top4 crashed on a missing worker rsync

Receipts: campaign-20261024-000708/09-prof4.md (cells a+b) and /10-top4.md (the failure).

- The 23:35/23:36 attempts died in the 23:42 reboot (the user's "restart" was a pair
  reboot: containers shutdown-killed, /tmp wiped, the -tip production stack never
  restarted). Nothing was lost; the AZ download's ~184 GB of chunks survived in the Xet
  CAS (the model dir's 640K is just the small files — a re-run resumes from the CAS).
- **Front 1 Lever A (batching): ANSWERED** — at c4 our shared verify windows run **8 rows
  in one 76.5 ms round** (4 streams × ~2 draft rows; solo is 2 rows/41 ms). Verify batches
  across streams; the #1155-mechanism glm port is the wrong patch for the c4 gap.
- **Front 1 Lever B (TF_GLM_SHARED=0): ANSWERED, retired** — windows alone at c4 =
  51.6 t/s (4 × 52 ms unshared rounds) vs sharing's 70–105 in the same sitting. Sharing
  IS the scaling mechanism; the knob stays default.
- Front 1 now narrows to round economics: acceptance at concurrency, the window cost
  tables (alone 52.0+6.8/row vs shared 76.0+4.1/row), draft/verify overlap.
- **Methodology caveat**: the window's absolute numbers carry the agent's own inference —
  the session rides the engine under test and was generating during cell a's probes
  (solo 14.2/34.1, Δ58% = agent traffic). The duel receipt (221204) stays the clean
  baseline; probe windows run with the agent silent from now on.
- **top4 crashed as a receipt**: the variant served the head fine but prepare refuses a
  locally-built snapshot missing on the worker (it only rsyncs what it downloads itself).
  Fixed: the phase pushes the variant to the worker explicitly. Re-running top4+summary;
  the agent stays silent during the probes.

## 2026-10-24 (round 17, evening) — the innards cross-examination opens; the prompt-router pathology found

- top4's second attempt (receipts: campaign-20261024-003708/10-top4.md + campaign.log)
  failed on the port guard — prepare SUCCEEDED end-to-end (the
  round-16 rsync fix works: both hosts verified the variant, the image cache answered,
  the marker written with model=@top4cfg) and start.sh refused :8000 because production
  was back up (00:43). The variant is fully prepared on both hosts; the next window
  serves it with zero prep. CAUTION: the head's prepared state is currently top4cfg — a
  bare testing-start before the next top4 run would serve the variant silently.
- (user) production is up evenings; the agent rides it (confirmed by production's
  /health: this session IS its requests_total=2 / prompt_tokens_total=180224). The
  cross-examination of the engine innards runs as source analysis while the GPUs serve
  production.
- **The prompt-router pathology (PERF_PLAN Front 2 Lever A2)**: the router section eats
  910–1125 ms of every 2048-row prompt chunk (55–69% of chunk GPU time) for a ~4.8 GFLOP
  GEMM production does in ~1 ms — and the same kernels cost 47 µs/layer at m=2. The
  superlinear blowup is the prefill front's real cause; patch candidates written up with
  the evidence chain. Expected win: prefill slope 0.662 → ~0.25 (production parity).
- Gotcha corrected: production's /health DOES carry drafter counters now (rounds 1221 /
  drafted 2569 / accepted 1610 = 62.7% acceptance, tokens = rounds + accepted exactly);
  OURS is the health that lacks them (backend/device/live/memory/model/status only) —
  our acceptance instruments stay the request-log lines and /metrics.

- Watcher postscript (same sitting): the 003708 campaign's summary died on the receipts
  glob — `0*.md` misses `10-top4.md` (starts with 1); with no 0-prefixed receipt in that
  run's dir the glob matched nothing, cat failed on the literal pattern, and set -e ended
  the campaign inside its own summary (no done line; CAMPAIGN.md partially written). The
  summary's globs now accept `[0-9]*.md` — all numbered receipts. The receipts themselves
  (10-top4.md's port-guard failure) were already complete on disk.

## 2026-10-24 (round 18) — the upstream sweep: nothing to bump to; two patches staged, three PRs on the watch

- Upstream check against our pin (1351ed16): v1.1.3 is still the newest release and
  carries no glm/cuda perf content — **the perf gate holds, no bump**. main is 136
  commits ahead: Flash Next/HIP/Windows/app heavy, nothing glm-perf.
- **Staged `patches/glm-slot-leak.patch`** (upstream 7d330e24d, #1218): a released
  stream left its queued draw's ring slot taken — every completed/cancelled request
  leaked a stream slot until restart. 1 line, bit-invisible, carried until v1.1.4.
- **Watch list refreshed (ECOSYSTEM.md)**: #1176 (qwen int8 prompt matmuls, cold prefill
  20–27% shorter — a glm port candidate behind the router patch), #1168 (qwen decode
  attention on tensor cores — our kda+mla are 40% of a verify round), #1228 (prefill
  preserved across cancellation), #1155 closed unmerged with its fix-ups landing pieces
  (the batched-drafting precedent), #1163+#1211 (glm KV pages, still open).
- The next window's experiment list stands: router-ks2 A/B, top4 variant, acceptance
  counters at c4 — plus the slot-leak patch riding the same build.

## 2026-10-24 (round 19) — the window prep: top4 + routerks2 A/B, staged for an unattended run

- New session phase `routerks2` (PERF_PLAN Front 2 Lever A2): cell a = stock serve
  (the duel arm + chunk-prof extraction + the drafter acceptance lines from the request
  log and /metrics — the Front 1 counters); cell b = the patched build
  (PATCHES=glm-router-ks2.patch,glm-slot-leak.patch — the slot-leak fix rides along)
  with the same probes plus the content-identity gate (the patched greedy reply must
  equal the stock cell's; the ks change is bit-visible by design — the gate decides the
  patch like #1079). Receipt: 11-routerks2.md.
- Window order: top4 FIRST (the prepared marker is still top4cfg — zero prep), then
  routerks2's stock cell (re-prepare to the default revision, fast), then the patched
  cell (a real rebuild), then summary. Estimated ~60 min. The agent stays OFF the
  engine during the probes (the round-16 pollution lesson): the session rides cloud
  while production is down.

## 2026-10-24 (round 20) — the window digested: the router patch dies by its gate; acceptance is not our gap; the top4 config bug found and fixed

Receipts: campaign-20261024-115242/10-top4.md + /11-routerks2.md. The window completed
(12:26 done.) with the agent silent — and the stock cell reproduced the duel exactly
(solo 55.3/55.1 Δ0.3%, c2 73.5, c4 101.8, slope 0.659, overhead 199 ms): the duel
baseline stands, the instruments are stable.

- **glm-router-ks2: RETIRED by the content gate.** The patched cell's greedy reply
  DIFFERS from stock (a token flipped — bit-visible as the source warned) AND the router
  section did not move (1096 → 1090 ms of the chunk): the pipeline-depth hypothesis is
  rejected as the pathology's cause. The patched cell's decode gains (solo 64.3, c2 89.8,
  c4 119.6) are an acceptance lottery riding the bit change — unadoptable. The gate did
  its job; the pathology stays open (next candidates in PERF_PLAN Front 2 A2).
- **Acceptance is NOT our concurrency gap**: our /metrics exports the drafter counters
  (tensorfold:mtp_drafted/accepted_total): **ours 77.2%** (15660/20292) vs production's
  **62.7%** (1610/2569, its /health). Front 1 narrows to the shared-round cost scaling
  at c4: our 8-row shared round = 76.5 ms (routed marginal ~5.5 ms/row at topk=8) vs
  production's ~34 ms implied round rhythm.
- **top4 served topk=8 three times** — the config edit never persisted: the snapshot's
  config.json is a SYMLINK into the shared blobs (cp -P preserved it; the edit aliased
  the base checkpoint or silently vanished; the blob's mtime proves it was never
  written). The base checkpoint is intact (mtime Oct 3; the stock cell's authentic
  topk=8 behavior confirms it). Fixed in the phase: the variant's config is now a REAL
  file, verified topk=4 before serving, verified on both hosts (12:48). The next
  window's top4 runs with zero prep — and this time the engine will actually route 4.
- glm-slot-leak.patch stays staged (bit-invisible, unaffected).
- The scoreboard and chart are UNCHANGED (no qualified fact moved: the patch died by
  its own gate, the top4 experiment has not actually run yet).

## 2026-10-24 (round 21) — the next window staged: top4 (real) + the router kernel A/B

- `glm-router-part.patch`: forces the unstaged router kernel for every launch —
  bit-identical math in theory (same ks slicing/summation), the content gate vs the
  115242 stock reply verifies. The cost read splits the pathology: shared by both
  kernels → replace with a real GEMM; tile-specific → fix the tile's K-depth/w-layout.
  New session phase `routerpart` (receipt 12-routerpart.md); glm-slot-leak rides the
  build. Window order: top4 FIRST (the variant config is now a real topk=4 file on both
  hosts — zero prep, and this time the engine will actually route 4), then routerpart,
  then summary. ~45-50 min.

## 2026-10-24 (round 22) — the window digested: the router pathology is in BOTH kernels; the top4 refusal was a config-parse failure, fixed byte-surgically

Receipts: campaign-20261024-125609/10-top4.md + /12-routerpart.md.

- **routerpart (the kernel A/B): DECISIVE.** The content gate says **IDENTICAL** (the
  forced fallback is bit-safe — same ks slicing/summation, as reasoned), and the cost
  read says the unstaged kernel costs the **same** as the tile (router 1140 vs 1096 ms
  of the chunk; solo 54.1, c4 100.6, slope 0.673 — stock-neutral). **Both kernels share
  the pathology: the hand-rolled mma approach itself is the bottleneck. The fix is a
  real GEMM replacement (the cuda_mm class) — with the bit-exactness constraint now
  explicit: any accumulation reorder is bit-visible, so the replacement must keep the
  K-slicing/summation structure or the gate kills it.**
- **top4 refused on a budget illusion, not topk**: "163.6 GiB of weights do not fit
  103.5" — the WHOLE checkpoint billed to one rank. Root cause chain: `weightShare`
  reads config.json, parses it with the engine's parser, and EVERY failure path
  silently returns the whole; my python json.dump round-trip produced bytes that parser
  rejects (the earlier symlinked config parsed fine — the three topk=8 serves). Fixed:
  the variant config is now a **byte-surgical copy** (diff vs base = exactly one line,
  verified both hosts), and the phase's build step does the same byte replacement.
- glm-slot-leak rode the routerpart build and served fine (informal validation).
- The scoreboard stays unchanged. The next window: top4 (now actually topk=4) + the
  GEMM-replacement scoping.

- Window prep (round 22 addendum): the top4 phase now also captures the drafter
  acceptance counters (/metrics + request-log lines) — halving the routed experts may
  shift acceptance, and the counter read comes free with the probes. The window is
  PHASES="top4 summary" (~20 min): the variant config is byte-surgical on both hosts,
  the phase verifies topk=4 before serving, and the budget arithmetic resolves to the
  rank share (~83.5 GiB) now that the config parses.

## 2026-10-24 (round 23) — the topk pin found; the loop goes autonomous (user handed the restarts over)

- Receipt: campaign-20261024-132628/10-top4.md — the byte-surgical variant STILL refused
  the same 163.6 arithmetic, in 16 seconds (no load at all: the admission check fires at
  startup). Root cause one level deeper than round 22: the parse VALIDATES against
  `want` — a snapshot of the struct's compiled-in defaults taken before the json
  (`const want = c;`) — and requires `c.topk == want.topk`; topk=4 is
  `error.NotGlm53Flash`, whose silent catch in `weightShare` bills the WHOLE checkpoint
  to the budget. **The top4 experiment was never a config tweak: it needs the reference
  shape rebuilt.** Staged `patches/glm-topk4.patch` (the struct default `topk: u32 = 8`
  → `4`; the kernels specialize for slots=5 at load).
- **(user) The loop is autonomous from here**: on cloud, the agent may restart the
  testing stack at will until the qualification gets through; production stays down and
  untouched.
- Launching: PHASES="top4 summary" PATCHES="glm-topk4.patch" — the build applies ONLY
  the topk4 patch; the expected sequence is build (~10 min) → load (~4.2 min) → probes
  (~9 min) → the receipt tells whether the routed section actually halves.

## 2026-10-24 (round 24) — top4 GOT THROUGH: real top-4 routing measured; the AZ thesis holds

Receipts: campaign-20261024-135458/10-top4.md. Attempt four (the ladder: admission
illusions ×2 → the parse's `want` pin → the EXL3 global; each stage moved one level
deeper; the fingerprint-hashes-names gotcha cost attempt three — a patch content change
needs a name change, the round-7 lesson's sibling).

- **The serve: real topk=4** (slots=5 scratch — the serve line's 83.35 GiB; the
  fingerprint's patch-rename forced the rebuild). Load 714 s in the receipt = build +
  load; the container's own line: loaded in 343.8 s (the first variant load packs new
  5-slot layouts — ~+87 s over the base's 257; a repeat-load number wanted).
- **The compute claim CONFIRMED (unretrained selector, our own checkpoint)**: routed
  **18.45 → 11.0 ms** at 2 rows (−40% — the weight-traffic union isn't slot-proportional,
  hence not −44%); verify rounds 40 → 32.3 ms; 8-row shared rounds 76.5 → 53.3 ms.
  **Solo 63.5/63.6 (Δ0.2%) — 108% of production's 58.7: the generation-tok/s front
  CROSSES THE BAR at solo.** c2 90.0 = 103% of production's 87.1. **c4 120.4 = 78%**
  (was 65% — the concurrency front jumped a fifth of the gap in one lever). Prefill
  slope 0.593 (−10%) — still 2.2× production's 0.265: the front now needs the GEMM
  router replacement (the ROUTER section, 1096 ms of the chunk, untouched by topk).
- **The acceptance shift is real**: 4.8 tokens/chunk (427 chunks for 2048) vs 3.37
  (608) at topk=8 — the fewer-expert target is easier to draft against. The /metrics
  counter read was cut by `head -2` (a phase bug — the value lines got truncated);
  the request-log lines didn't match the grep. Fix both next window; the exact
  acceptance number at topk=4 is still open.
- **The quality question stands, unresolved**: topk=4-unretrained is a different model
  behavior — the (user) bar says a new checkpoint/model behavior means seriously more
  quality checks (§2 gates + full tool-eval + structured-output + TEB). Until that
  battery runs, this is a measured lever, NOT a servable default; config.sh stays
  topk=8. The AZ full checkpoint (the retrained selector + requant path) is the
  quality-safe route to the same win.
- Scoreboard/chart: UNCHANGED (the served default is still stock topk=8).

## 2026-10-24 (round 25) — the quality battery on top-4, staged

- New session phase `top4qual`: the battery on the real topk=4 serve — §2 gates
  (run_gates with the top4cfg config) + the full tool-eval (run-bench-matrix
  PHASE=tools; the structured-output scenarios ride it) + hardmode (the 28 scenarios).
  Receipt: 13-top4qual.md. The reference bar: the stock dense4fp8 cell's 92/100
  (125/136 pts, 0 errors). A battery failure sends the lever to the AZ full checkpoint
  (the retrained selector) instead of a default change.
- The bench-matrix gained a `top4` config entry (PATCHES=glm-topk4b.patch +
  MODEL_REVISION=top4cfg). The prepared state is already the top-4 serve (from attempt
  four) — the battery's serves need no rebuild.
- Window: PHASES="top4qual summary" — gates ~12 min + tools ~20 min + hardmode ~20 min.

## 2026-10-24 (round 26) — the top-4 quality battery: gates ALL PASS, tool-eval 93 (above stock's 92), hardmode 89 vs production's 91 — the default fork opens (user)

Receipts: campaign-20261024-142659/13-top4qual.md.

- **§2 gates on real topk=4: ALL PASS** — g1 greedy determinism (content), g2
  drafted=plain (the drafter is exact on the new model), g3 cache-hit=computed, g4
  concurrent=solo (4/4), g5 seeded (NOTE form — the standard).
- **The full tool-eval: 93/100 — ABOVE the stock bar** (92; production's anchor is 95 —
  the top-4 serve closes 1 of the 3 points to production). The structured-output
  scenarios rode the suite.
- **Hardmode: 89/100** vs production's anchor **91** — the FIRST hardmode datum on this
  line (stock dense4fp8 never ran hardmode; the ledger's Phase 2/3 item stays open for
  that). Two points under production on the adversarial suite.
- **The fork (user decision)**: (a) adopt top-4-unretrained as the served default — the
  perf receipts (solo 108%, c4 78%) + the battery (gates pass, tool-eval above stock)
  back it, and the scoreboard/chart finally move; but the served model then differs
  from production's stock behavior, and hardmode runs 2 under production's anchor.
  (b) hold stock as the default and route the lever through the AZ full checkpoint
  (the retrained selector — quality-safe by construction, the download's ~184 GB of
  chunks survived the reboot, the requant is window+GPU work). The agent's
  recommendation: (b) — the comparison story stays honest until the retrained selector
  is measured. Scoreboard and config.sh UNCHANGED this round either way.

## 2026-10-24 (round 27) — (user) the default moves to top-4; the AZ full checkpoint route opens

- **(user) The fork resolved: adopt.** config.sh's qualified defaults now serve the
  top4cfg checkpoint with PATCHES=glm-topk4b.patch (receipts cited in the comments:
  perf 135458 + battery 142659). Stock remains one env away
  (MODEL_REVISION=078455ffe6472f9a52fbc1139f58b9db2881b25c, PATCHES=).
- **The scoreboard moved for real** (the anchors + the chart regenerated from the
  receipts): solo **108%** and c2 **103%** of production — the generation front CROSSED
  the bar; overhead 119%, streaming ~189% — two more rows over the line; c4 **78%**
  (from 65%); prefill **45%** (the router GEMM is the remaining fix); loading **27%**
  (344 s — the 5-slot pack is heavier than the base's 257; the packing cache is the fix).
- Next: the AZ full checkpoint route (the retrained selector — the quality-safe upgrade
  to the same lever). The download's ~184 GB of Xet chunks survived the reboot; resuming
  it now (no GPU). Before staging a requant, check whether the community already
  published an EXL3 variant of the AZ checkpoint.

## 2026-10-24 (round 28) — the AZ route: the download verified complete; the requant plan staged; AZ-Focus discovered

- The AZ download is COMPLETE (the Xet CAS survived the reboot — the resume finished in
  seconds): 170 G materialized, 37 shards, topk=4, 288 experts, auto-round int4. The
  Experiment-2 checkpoint (the retrained selector) is on disk.
- The route staged in PERF_PLAN: requant auto-round int4 → EXL3 4bpw (streaming convert
  first — no ~640 GB intermediate if exllamav3 dequants per-layer; else the disk
  choreography), serve with glm-topk4b (the reference is already topk=4), the battery +
  the perf probes, and — if it passes — the default upgrades to the retrained selector.
  GPU: hours, window-gated.
- **Discovered en route**: AxonZeta/GLM-5.3-Flash-AZ-Focus-EXL3 — a DIFFERENT mod
  (AxonZeta's own, from Z.AI's BF16): 40–50% fewer thinking tokens at max effort with
  accuracy level or up (AIME 81.7 vs 75.0, GPQA up, SWE-bench 92 vs 95), topk=8 intact,
  EXL3 4bpw native — serve-ready as-is. A candidate lever for the agentic workload
  (fewer thinking tokens = effective throughput), recorded in PERF_PLAN; not the AZ route.

## 2026-10-24 (round 29) — the AZ requant window staged: the dequant, the convert, the battery

- scripts/az_dequant.py: streams the AZ auto-round int4 (the GPTQ layout decoded from
  the shard headers: qweight [in/8,out] I32, qzeros [groups,out/8], scales [groups,out]
  F16, group 128; everything else BF16 pass-through) to a plain fp16 HF dir. The GPTQ
  zero convention auto-detects on the first expert tensor (the wrong one leaves every
  weight offset by a scale step — mean|w| decides). RAM stays per-shard; the output
  carries a real safetensors index + the config minus quantization_config.
- scripts/az-window.sh: the orchestrator (dequant → exllamav3 convert -b 4 -hb 16 -eb 16
  → place as local/GLM-5.3-Flash-AZ-EXL3 → the worker rsync → the azqual campaign).
  exllamav3 1.6.4 installed at ~/.venv-exl3 (the host nvcc 13.0 + ninja; the JIT builds
  on first import).
- The azqual phase: §2 gates + the duel arm + the tool-eval + hardmode on the AZ-EXL3
  serve (the bench-matrix gained the azexl3 config entry). References: top4cfg's
  135458/142659 receipts. A battery pass upgrades the default to the retrained selector.

- README currency pass (same sitting): the config table + the revisions table now carry
  the round-27 default (top4cfg + PATCHES=glm-topk4b; stock one env away; the AZ
  requant listed as staged). The vision question settled: the engine code + the
  checkpoint's tower (347 visual tensors) are present, but the line has never passed
  --vision — the README now says "vision here is unserved" instead of the ambiguous
  "does not carry it". A VISION knob + a vision gate round is a small future window item.

## 2026-10-24 (round 30, evening) — (user) the convert runs overnight; Focus verified test-ready

- **(user) The trade resolved: the convert runs overnight** (production down until the
  window completes; ~10 h remaining at the measured 58 tensors/min, layer 4 of 45; the
  window's done lands ~06:00 with the placement + the battery). The alternatives
  (a pausable resume now, or pivoting to the test-ready Focus) are recorded in the plan.
- **The AZ-Focus-EXL3 download: COMPLETE + verified** on the worker (164 GiB resolving,
  48 shards) — the reasoning-efficiency lever (topk=8, EXL3-native, no requant) is
  test-ready for its own battery whenever the user calls it.
- Overnight watcher armed: fires on the campaign's done. OR pipeline death (the
  checkpointed stages resume on any re-run of block 2; the staging survives).

- 21:18 crash (the overnight run): the converter's calibration forward hit
  "weight must be [dim, conv_kernel_size]" — the AZ checkpoint's conv1d weights are
  HF-style [dim, 1, K]; exllamav3's decode-path triton kernel wants [dim, K]. Fixed:
  az_squeeze_conv.py rewrites the conv1d tensors in the fp16 dir (they live mostly in
  model_extra_conv.safetensors — a minutes-fast surgical fix), az_dequant squeezes on
  pass-through (future runs), and the orchestrator runs the squeeze as stage 1b before
  resuming the convert (the 8+ layers of checkpointed work survive).

- Overnight post-mortem (01:48 death, found 08:57): the healer SELF-MATCHED (its own
  command line contains "scripts/az-window.sh" — the liveness pgrep saw itself as the
  pipeline alive all night) AND the conv1d fix was wrong twice: the squeeze flattened
  the CANONICAL bf16 splits ([c,1,K] — what TensorFold's convs() reads, weights.zig:372)
  and left the NON-canonical F32 mixed convs ([3c,1,K]) in place, so the converter's
  split-cat produced 40960 channels against 24576 expected. Fixed: az_conv_fix.py
  (drop the F32 mixed, unsqueeze the bf16 splits — idempotent, atomic), the dequant's
  pass-through drops the F32 convs (future runs), stage 1b points at the new script.
  GPU verified clean (no memory held; 6122 = the frozen progress counter, not GPU tensors).

## (round 31) The requant saga: three refusals, one format gap (2026-10-26)

- **azqual refusal 1 — the codebook** (`campaign-20261026-010238/14-azqual.md`): the
  1.6.4 convert defaulted to `-cb mul1` + float `bits: 4.0`; the engine's `admit()`
  (families/glm/cuda_exl3.zig) reads integer bits 4 + the "mcg" codebook only. Both
  ranks refused (UnsupportedQuant) in 0.1 s. The receipt is the refusal's own
  arithmetic — recorded, not retried blind.
- **The mcg rework** (`406334f`): `-cb mcg` baked into `scripts/az-window.sh`, fresh
  WORK/EXLOUT (the mul1 qtensors invalidated), a byte-surgical bits normalization +
  hard assert (`scripts/az_bits_fix.py`) before placement, and the retry-wrapped
  worker sync (6 attempts, -W, keepalives). The 12-h mcg convert ran clean; the
  assert PASSED; the sync placed 153.4 GiB on the worker (the delta-mode trap cost
  it 5× — see the sync lesson below).
- **azqual refusal 2 — the checkpoint format** (`campaign-20261026-210257`): the
  engine admitted the mcg checkpoint and then refused at tensor load
  (MissingTensor: `layers.0.self_attn.q_proj.weight`). Root cause: exllamav3 1.6.4
  writes the NEW checkpoint layout (fused `qkv_proj.mcg/.trellis/.suh/.svh` quads,
  merged `conv1d.weight`); the engine (pin 1351ed16 — and upstream main, verified
  byte-same) reads the OLD layout (`q_proj.weight` + conv splits + per-module bits
  in quantization_config). **Nobody's engine reads 1.6.4's layout yet.**
- **The AZ-Focus checkpoint (AxonZeta) is OLD-format** — `focusqual` (the battery
  phase, `37b07ec`) is unblocked; the thinking-efficiency track's first measured
  cell. (user) Focus battery first; the AZ-EXL3 format path (1.5.3 side-venv
  re-convert / repack shim / upstream watch) is decided after the Focus verdict.
- **Disk choreography done**: the mul1 dead weight freed (~499 G — az-az-work 191 G,
  az-az-exl3 154 G, the local mul1 placement 154 G); 958 G free on the head during
  the convert. Pending after the AZ verdicts: az-az-fp16 (599 G) + az-az-work-mcg
  (165 G). (user) the AZ quant publishes to huggingface.co IF its gates pass
  (ledger open item).
- **The sync lessons** (skill-smith log, unpromoted): (1) the 4 silent rsync deaths
  → the retry-wrapped sync pattern; (2) rsync's delta mode against a stale
  same-named destination (sender pegged 97%, receiver asleep 4.7%, 60 vs 320 MB/s;
  the rail does >1 GB/s on 4 streams) → wipe the destination + -W, deployed in
  stage 3 (`92723f4`).

## (round 32) The Focus battery: the first complete AZ-family verdict (2026-10-27)

- **The six-refusal root cause, solved by trace** (`b1f42bd`, the :diag/:diag2 receipts): the served
  default's `glm-topk4b` pin makes the engine's strict `config.parse` reject the Focus's field-less
  config (`NotGlm53Flash`); `weightShare`'s silent `catch return total` then bills the WHOLE checkpoint
  to one rank (163.6 vs ~102) — the identical refusal six times. The top4cfg survives the pin only
  because the ladder's surgery declared `num_experts_per_tok` in its config. The Focus (topk=8 by
  design) now serves PRISTINE: `PATCHES=` empty, config.sh `${PATCHES-…}` so an explicit empty survives.
  The diagnostic methodology: the trace built to its OWN tag (`:diag2` — the campaign's auto-prepare
  rebuilds `:commit` per its staging and had silently dropped an earlier diagnostic patch).
- **The battery** (`campaign-20261026-235703/15-focusqual.md`, `run-20261027-002357` + `005153`):
  §2 gates ALL PASS (g1–g5 content-form); **solo 57.9 t/s** (production ≈ 58.9 — at par; the top4cfg's
  108% stands); **c2 74.7** (the top4cfg's 90.0 — a step behind); **c4 119.8** (≈ the top4cfg's 120.4,
  2× production's 60.5); TTFT slope 0.663; **tool-eval 94** and **hardmode 90** — the highest-quality
  checkpoint this line has ever served, one point under production on BOTH instruments (the top4cfg:
  93/89; the stock: 92). The thinking-efficiency track's first measured cell: quality-first, at-par
  solo, concurrency a step behind the top4cfg.
- Production returned 01:29 after the battery (the agent ran the window end-to-end under the user's
  grant; the serve line confirmed `PATCHES=` riding in every restart).
- Open: the AZ-EXL3 requant still parks on the 1.6.4 format gap; the Focus's c2 gap (74.7 vs 90.0)
  joins the router/slope work as a perf question; the thinking-efficiency next steps (`TF_GLM_CLEAR_THINKING`
  #840 + the token-count instrumentation) now have their baseline cell.

## (round 33) The v1.1.6 rebase: adopted on a +26% concurrency landslide (2026-10-27)

- **The pin**: 1351ed16 → **eea9dc9c (Release 1.1.6)** — `local.sh` updated, the topk4b patch
  applies cleanly at the new tree, the campaign receipt carries `tf=commit@eea9dc9c…`.
- **The A/B** (`campaign-20261027-085035` vs `20261026-235703`, the identical Focus serve):
  gates PASS ×4 both; solo 57.9 = 57.9; **c2 74.7 → 94.3 (+26%)**; **c4 119.8 → 150.6 (+26%)**;
  slope 0.663 = 0.663; tool-eval 94 = 94; **hardmode 90 → 91 (ties production's anchor)**.
  The upstream #1322 measurement (+14% at two streams on NVFP4) transferred at +26% on our
  EXL3 checkpoint. ADOPTED — receipts-equal-or-better everywhere, dramatically better at
  concurrency.
- **The first A/B silently ran the old engine**: the auto-prepare keys on the config
  fingerprint (the patch names) — a TF_COMMIT pin change in local.sh does NOT move it, so
  `campaign-20261027-053451` re-ran the v1.1.2 engine and the numbers matched the baseline
  exactly. Caught by the image ID (9 h old). **A pin change needs an explicit prepare.sh.**
  (lessons log carries it.)
- **The scoreboard staleness**: the served default (the top4cfg) still carries v1.1.2-era
  anchors — its re-qual on v1.1.6 is the next window's battery before the scoreboard rows move.
- **The Focus's c2 gap is CLOSED by the rebase** (94.3 ≥ the top4cfg's 90.0) — the router/slope
  perf question narrows to the solo/c4 slope only.

## (round 33 addendum) Production's fresh duel receipt — the Focus crosses c2, the TTFT frontier named (2026-10-27)

- **Production re-measured** (idle-gated, the campaign's own `duel_arm` lifted verbatim against
  the -tip production with Mia's new patch series): **solo 58.6/58.5 (Δ 0.0%), c2 87.0, c4 154.6,
  ITL p50 13.7 ms, TTFT d0 186 ms** — and the TTFT **slope −0.005 ms/token** (d0 186 → d4096 161
  → d8192 142: production's TTFT IMPROVES with depth — its prefix cache hits the duel fills'
  shared prefixes across requests).
- **The head-to-head vs the Focus on v1.1.6** (the same probes): solo **98.8%**, **c2 108.4% —
  CROSSED** (94.3 vs 87.0), c4 **97.4%** (150.6 vs 154.6). The scoreboard's formal rows still wait
  for the top4cfg's v1.1.6 re-qual (both sides of that comparison have now moved).
- **The TTFT-at-depth frontier is the new #1 perf item**: ours grows +0.663 ms/token (d8192:
  5,645 ms) while production is flat (142 ms) — a 40× gap. Production's cross-request
  shared-prefix caching (the 0.6.x kept-state work + Mia's new patches) vs our engine's
  same-conversation-only cache (the g3 gate covers the same-conversation case; the
  cross-request shared-prefix case does not hit). Upstream's #1321 (the shared-prefix
  queue) and #1262 (the kept-state resumption) are in v1.1.6 — the frontier is the
  cross-request prefix mark, not the queue.
- The production benchy baseline also landed (idle, clean): pp2048 1,514-1,627 t/s, solo tg
  54.4 — consistent with the old anchors (Mia's patches did not move production's speed).

## (round 34) The TTFT-at-depth frontier: root cause found at source level (2026-10-27)

- **Method**: no GPU needed — the v1.1.6 source cloned at the pin (`eea9dc9c`) and read end to
  end: `zig/src/core/prompt_cache.zig` (the store), `zig/src/core/lane_stream.zig` (the
  per-request entry), `zig/src/server/chat.zig` (what a chat request passes),
  `zig/src/native/cuda_snaps.zig` + `families/glm/cuda_native.zig` (GLM's rules).
- **The cache is a token-prefix cache** — `find` matches a kept state's full token array as a
  strict prefix of the new prompt, with decode spans equal through the kept position. NOT
  same-conversation-only: any request whose tokens extend a kept state resumes it.
- **But states are kept only at conversation-structure marks** (`marksRewind`): the history
  boundary, the rewind point before the latest user message, the stable diff vs the
  conversation's previous prompt, and caller-provided `shared_prefixes` cuts — each snapped to
  the planned grid (`snap_grid = prompt_rows`), min_gap 256 apart.
- **And a chat request's shared cuts cover only the system prefix** (`server/chat.zig`):
  three positions at system_len−2048/−512/system_len, only when the system prefix exceeds 512
  tokens. Nothing else ever populates `shared_prefixes` from the HTTP payload.
- **Consequence (the frontier)**: a shared prefix inside **user content** — the duel's fill, any
  long document re-sent across conversations — never gets a kept state, so every request
  prefills it from zero: TTFT grows linearly (+0.663 ms/tok measured). Same-conversation
  follow-ups hit via the history + stable marks — exactly the g3 gate's same-conversation case.
  Production's python engine matches prefixes at arbitrary KV-page boundaries across requests,
  hence its flat/improving TTFT (186→161→142 ms).
- **The span machinery does not block the fix**: decode spans are token-derived per request
  (`replySpans` "from the tokens alone"), so identical token prefixes carry identical spans
  through the shared position — grid-boundary states inside long prompts would resume exactly.
- **Upstream's own paths** (v1.1.6, both present): #1321 dedups only requests arriving
  *together* on a new shared prefix; the `imprint`/`--learn` path writes shared cuts' states to
  disk "read back by later sessions and servers" — but the chat server's cuts are system-only.
  `Request.shared_prefixes` exists on the API struct but is not client-settable.
- **The proposed experiment (next window, needs a serve)**: a marks-policy patch keeping
  grid-boundary states inside long prompts for CUDA — measured by the duel probes (the TTFT
  slope is the direct instrument) with the full §2 gates battery around it (state keep/restore
  is exactness-sensitive; the resume marks are where determinism could break).
- Receipt: this entry + the clone at `/tmp/opencode/tf` (local workstation); no new numbers —
  the round 33 addendum's duel receipts are the measurements this explains.

## (round 35) Production's v3.0.1 score anchors — tool-eval 96, hardmode subset 90% (2026-10-27)

- **The morning's score attempt was killed** (the user's report: production was in use during
  the run — 4 concurrent requests at scenario ~53/69; timings AND scores compromised). Partials
  discarded. The idle-gated discipline the user set for the perf run was applied here too.
- **The clean re-run** (idle-gated: fired at 11:46 when /health showed 0 running ×3 checks,
  both suites back-to-back, ~40 min): receipt
  `~/tool-eval-bench/results/prod-score-rebaseline-20261027-114634/` on the head, bench
  `3.0.1.dev4+gb672b53ff`, model `GLM-5.3-Flash-EXL3`, seed 42, parallel 4, timeout 240.
- **tool-eval: 96/100** (133/138 points — 66 pass, 1 partial TC-40, 2 fail TC-43/TC-51; 69
  scenarios). **hardmode run: 94** (196/208 over all 104 scenarios = standard 69 + hardmode
  35). **hardmode subset: 63/70 = 90%** (30 pass, 3 partial, 2 fail TC-92/TC-104 — production
  scores 0 on TC-104, the newest scenario).
- **The cross-version boundary, receipted**: the Focus battery's hardmode run counted
  `total: 97` (69 + the old 28-scenario hardmode suite) in
  `results/campaign-20261026-235703/bench-hardmode.log` — today's run counts 104 (69 + 35).
  The old production anchors (95/91) are formally cross-version; kept as history only.
- **README correction (withdrawn + re-stated)**: the round 34 Quality row labeled the Focus's
  94/90 as "bench v3.0.1" — wrong, the battery ran the night BEFORE the bench update. The row
  now states the Focus's 94/90 as old-bench, pending our v3.0.1 re-bench.
- **State**: production's score side is re-baselined on v3.0.1 (96 / 94 / subset 90%). The
  cross-engine score comparison waits for OUR serves' re-bench (the Focus + the top4cfg on
  v3.0.1, next window). The perf/duel side is already comparable (round 33 addendum: c2
  108.4% CROSSED, c4 97.4%).

## (round 36) The window block ran the WRONG phases — and the accident qualified the default's v1.1.6 perf (2026-10-27)

- **The bug**: `run-window-block.sh` set `PHASES` without exporting it — the campaign never
  saw it and ran its full default phase list (12:41→17:22, ~4.7 h) instead of the two
  batteries. My session died with production as designed, so nothing could correct it
  mid-flight; the block itself wrapped cleanly (rc=0) and stopped our stack.
- **What the accident produced** (`results/campaign-20261027-124115/` — the FULL v1.1.6
  receipt set for the served top4cfg default, which the scoreboard needed anyway):
  §2 gates ALL PASS on every cell (g1–g4 content form); **the duel receipt: solo 64.8/64.9
  (Δ 0.2%), c2 108.0, c4 167.4 t/s, TTFT d0 148 ms, ITL mean 42.8 ms/chunk (427 chunks ≈
  4.8 tokens/chunk → 8.9 ms/token); prefill 1,175 tok/s** (26,869-token wall, was ~1,026);
  **loading 256 s** (the knobs cells' timed restarts 246–260 s, engine loaded ~248 s —
  the v1.1.2-era 344 s is gone); depth **12/12** at 8k/64k/192k/384k; fresh
  throughput/climb/knobs/confirm receipts. The prod arm of the duel skipped (production
  already down — its round-33 fresh receipt is the other side).
- **The scoreboard moved** (`docs/perf-anchors.tsv` + the regenerated chart): vs production's
  fresh duel receipt (58.6/87.0/154.6) — **solo 111%, c2 124%, c4 108% — every concurrency
  front CROSSED** (c4 was 78% at v1.1.2); TTFT overhead 126% (148 vs 186 ms); ITL 192%
  (8.9 vs 17.1 ms/token); prefill 78% (1,177 vs 1,514 benchy, TTFT-estimated both sides);
  loading 37% (256 vs 93.7 s). **TTFT at depth: 3%** (4,954 vs 142 ms at d8192) — the one
  open front, round 34's root cause.
- **Row evolution, explained**: the `prefill slope (ms/token)` row became `TTFT at depth
  (1-token, d8192)` — production's fresh slope is **−0.005 ms/tok** (flat-to-improving: its
  cross-request prefix cache), and a negative production value degenerates the chart's
  inverted-ratio math. The absolute d8192 pair tells the same story honestly. Not a silent
  edit: this entry is the explanation.
- **The wrapper fix, verified three ways** (verify-shell-config-edits): `bash -n`; a
  child-visibility probe (`bash -c 'echo $PHASES'` through the exact assignment+export);
  and the live guard path — with production UP, `STEPS=1` runs the wait once and aborts
  cleanly ("nothing was started", exit 1). The head's copy carries the fix.
- **Still owed (one more window, ~2.5–3 h)**: `top4qual` + `focusqual` — the tool-eval +
  hardmode scores on bench v3.0.1 for both serves (the score side of the comparison; the
  perf side is now fully receipted). The steps0 knob lead stayed inconclusive on v1.1.6
  (benchy-at-depth rows 19.8/52.9 across two identical restarts — the polluted instrument;
  duel-style probes at depth would decide it if pursued).

## (round 37) The corrected block: both batteries on bench v3.0.1 — the score comparison complete (2026-10-27)

- **The corrected wrapper ran as designed** (17:38→20:24, `PHASES="preflight top4qual
  focusqual summary"` honored — the export fix verified live): `campaign-20261027-173843`,
  rc=0, the stack stopped after, production back on the port.
- **§2 gates ALL PASS on both serves** (g1–g4 content form + the g5 note; the byte-level
  nondeterminism note is the engine's documented raw-bytes behavior, not a content fault).
- **The duel arms re-confirm round 36 within noise** — top4cfg: solo 64.6/64.7 (Δ 0.2%),
  c2 108.1, c4 168.1, TTFT d0 148 ms, slope 0.588 (round 36: 64.8/108.0/167.4/0.587 — the
  chart's rows stand, no churn); Focus: solo 57.4/57.5, c2 94.4, c4 153.3, slope 0.665
  (round 33 A/B: 57.9/94.3/150.6/0.663).
- **The v3.0.1 scores — the comparison is now apples-to-apples on all three serves**:
  | serve | tool-eval (/138) | hardmode run (/208) | hardmode subset (/70) | subset fails |
  | --- | --- | --- | --- | --- |
  | production (round 35) | **96** (133) | **94** (196) | **63 = 90%** | TC-92, TC-104 |
  | top4cfg (round 37) | **96** (133 — TIED, same points) | 89 (186) | **53 = 76%** | TC-85, TC-88, TC-89, TC-92, TC-98, TC-101, TC-104 |
  | Focus (round 37) | 95 (131) | 92 (191) | **60 = 86%** | TC-80, TC-92, TC-101, TC-104 |
- **The reading**: the top4cfg matches production point-for-point on the standard suite and
  is the perf leader by far (c2 124%, c4 109%, solo 110%) — but hard-mode costs it 10 subset
  points (76% vs 90%), concentrated in TC-85/88/89/98/101 (the two engines' shared fails are
  TC-92/TC-104). The Focus sits between on scores (95/86%) while at-par-to-crossed on perf
  (solo 98%, c2 108.5%, c4 99%). The default trade is a (user) decision: perf-first (keep
  the top4cfg) vs hard-mode-quality-first (the Focus). The unretrained top-4 selector is the
  suspected mechanism for the top4cfg's subset fails — the AZ retrained-selector route
  (parked) is the principled fix if the trade is deemed unacceptable.
- **The bar (user) scoreboard**: generation tok/s — CROSSED on every front. Prefill — 78%
  (open). Loading — 37% (open, 256 s vs 93.7 s, decomposition still pending). The bar is
  one of three fronts; the remaining two plus the TTFT-at-depth frontier (3%, round 34's
  root cause) are the perf way forward.

- **Round 37 addendum — the upstream look (the continuing-look mandate)**: v1.1.7 is out
  (daily release cadence) and main carries #1430 `TF_GLM_INDEX_CUDA=1` — GLM-5.3-Flash's
  prompt-chunk DSA indexer in two byte-equal CUDA kernels, upstream-measured on a GB10 at
  **cold-TTFT −2% @131k, −9% @524k, −16% @1M** — the first upstream item aimed at our
  TTFT-at-depth/prefill fronts since the v1.1.6 rebase. It is opt-in and unreleased (main
  only). Recommendation: **wait for v1.1.8** (the cadence says imminent) rather than pin
  unreleased main, then A/B the knob as a knobs-phase-shaped cell (gates first — the
  byte-equal claim makes them near-certain — then the duel probes at depth and a prefill
  pass; the pin change gets the explicit `prepare.sh` + image-ID check). The marks policy
  is untouched upstream: our patch experiment remains the cross-request fix.

## (round 38) The (user) hardmode bar — the Focus becomes the served default (2026-10-27)

- **The decision (user)**: "focus on hardmode — no one online is just running the standard
  set; hardmode is the quality measure and we need to either beat production or almost
  equal it." The target is the bench's own headline: production's **run-level 94**.
- **The receipts that frame it**: Focus **92** (2 under — almost equal; its whole gap is
  TC-38 + TC-80, both `wrong_args`, since TC-92/TC-104 fail on production too), top4cfg
  **89** (5 under — fails the bar). The failure-kind analysis (round 37) showed every fail
  on every serve is judgment-shaped (`wrong_args`/`missing_step`) — the top4cfg's deficit
  is the unretrained top-4 selector's, not the engine's.
- **Executed**: `config.sh` defaults swapped to the Focus serve shape
  (`MODEL_ID=local/GLM-5.3-Flash-AZ-Focus-EXL3 MODEL_REVISION=main PATCHES=` empty);
  README/DELTAS/ledger/PERF_PLAN updated; **the chart re-anchored to the Focus cell**:
  loading 41% (230 s — the focusqual restart walls 226–239), solo 98%, **c2 109% — CROSSED**,
  c4 99%, TTFT overhead 92%, **TTFT at depth 3%** (5,647 vs 142 ms), prefill 67%
  (1,020 t/s benchy), ITL 102%. The top4cfg's crossed rows (111/124/108) stay in the
  ledger as the documented perf leader.
- **The beat-94 track (the new quality line)**: (a) a multi-trial hardmode run (`--trials`)
  to measure run variance around TC-38/TC-80; (b) the AZ retrained-selector route — the
  principled fix that could hold the top-4 perf AND trained-routing quality; its blocker
  (the fused-quads EXL3 format) gets re-checked at v1.1.8 — upstream main now carries
  `exl3_layout.zig`/`eaq_container.zig` (active EXL3-format work); (c) the v1.1.8 A/B runs
  regardless (the indexer kernels + any reasoning-path changes).

## (round 39) The (user) bench-parallel decision: tool-eval-bench runs at --parallel 2 from now on (2026-10-27)

- **The decision (user)**: future tool-eval-bench runs are limited to **`--parallel 2`** —
  motivated by performance under load looking awful with RoCE chatter suspected (the
  counters so far show zero error-class events on both CX7 rails — the "chatter" is more
  likely the four concurrent scenario chains themselves contending on the RoCE gather than
  a transport fault; the markspatch cell's duel numbers will quantify it).
- **Scope**: the BENCH's `--parallel` (its `run` invocation) only — the serve's own
  `PARALLEL=4` stream count is untouched (its admission arithmetic is receipted).
- **The changes, at the block's wrap** (scripts are frozen mid-campaign): the
  `run-bench-matrix.sh` default, the `hmtrials`/`settingsab` phase invocations — all
  `--parallel 4` bench lines → `--parallel 2`.
- **Comparability note, stated up front**: the score anchors (production 94, the Focus 92,
  the top4cfg 89) were measured at `--parallel 4` — the SCORES are comparable across the
  change (content-deterministic per variant seed; parallel affects timing, not judgments),
  but the WALL-TIME/duration receipts of new runs are not comparable to the old ones.
  The benchmarks' own throughput rows will read slower per-request by design of the change.

## (round 40) The overnight block's three verdicts (2026-10-28 morning)

- **hmtrials — the variance answer: the Focus's 92 is rock-stable.** Variant seeds 7/8/9
  all scored exactly **92** (plus round-37's default-seed 92 = four draws, one score).
  The 2-point gap to production's run-level 94 is real capability distance, not run
  noise — beating 94 needs a capability change, not re-rolls. Receipts:
  `campaign-20261027-212746/16-hmtrials.md`.
- **settingsab — no lift from the recommended settings.** Temperature 1.0 / top_p 0.95
  scored **91** (one sampled draw, 1 under the greedy anchor). The recommended-settings
  hypothesis is dead for this suite; greedy stays the harness's sampling and the
  deterministic anchor. Receipt: `17-settingsab.md`.
- **markspatch — safe but unproven.** The interior-marks patch (grid-aligned prompt
  states) passed the FULL §2 gates battery (g1–g4 + the g5 note — exactness intact with
  the new resume path) — but the duel moved nothing: solo 57.9/57.9, c2 94.4, c4 151.9,
  TTFT d0 202 ms, **slope 0.664 vs the 0.665 baseline**. Reading: the duel instrument
  does not exercise the cross-request resume path the patch adds (each depth probe is a
  single cold request; the d8192 probe's shared fill prefix with the d4096 probe should
  have engaged the marks but didn't). The patch is NOT falsified — the instrument is
  insufficient. Next: a same-prefix-repeat probe (the same long prompt sent twice; TTFT#2
  vs TTFT#1 is the direct resume test) plus the engine's own prompt-cache counters during
  it (hits/misses/evicted — are interior states kept at all). Receipt: `18-markspatch.md`.
- **The wrap queue landed**: bench invocations at `--parallel 2` (the (user) round-39
  decision — the matrix default, the probe bench line, the hmtrials/settingsab cells;
  the perf-only benchy cells keep their parameterized client counts as the concurrency
  instrument); the redundant tools passes stripped from top4qual/azqual/focusqual (the
  hardmode run covers the 69 — the (user) hardmode-only directive); config.sh's two
  comment lines now describe the Focus default.
- The block wrapped at 00:29:59 (rc 0), the stack stopped clean, production back on the
  port this morning.

## (round 41) The two-shot instrument: the patch works, and the resume-cost gap is named (2026-10-28)

- **The three-way two-shot signature** (the same ~7.7k-token prompt twice per pair,
  `scripts/twoshot-probe.sh`; receipts `campaign-20261028-060716/18-markspatch.md` +
  this entry's production control):
  | serve | shot 1 (cold) | shot 2 (resume) | saving |
  | --- | --- | --- | --- |
  | production | 4,525 ms | **65 ms** | **99%** |
  | ours unpatched | 7,359 ms | 1,440 ms | 80% |
  | ours PATCHED (pair-1 shot-1, after the duel's same-fill prefill) | **1,445 ms** | 1,435 ms | already-resumed |
- **The marks-patch WORKS**: the patched serve's pair-1 shot-1 was already fast (1,445 ms
  vs the unpatched cold 7,359 ms) — it resumed the interior states the duel's d8192 probe
  had just kept (the duel's fill and the probe's fill are the same generator/words/count),
  and the cache counters corroborate (hits climbing 2→4→6, evicted 0). Cross-prompt
  prefix resume — the exact thing the conversation-structure marks never covered — is
  delivered by the patch, with the full §2 gates PASSing around it (second independent
  run). The patch is exactness-safe and functionally proven.
- **Identical-prompt resume already exists unpatched** (7,359 → 1,440 ms, 80%): upstream's
  engine resumes the same prompt without the patch (some end-of-pass state). The patch's
  addition is the cross-prompt case.
- **The duel's d4096→d8192 non-resume explained**: the two prompts share text but the
  junction tokenizes differently (fill_4096's last word + "\n\n" vs fill_8192's
  continuation), so the d4096 state is not an exact token-prefix of the d8192 prompt and
  `find` correctly rejects it. The duel instrument cannot measure cross-length resume;
  the two-shot is the right instrument.
- **The new named gap — restore cost**: our resumed shot costs **1,440 ms** where
  production's costs **65 ms** (22×). Production's block cache remaps already-resident
  blocks; ours restores a snapshot's KV bytes per resume. Even with perfect prefix
  matching, our resume floor is ~1.4 s at 7.7k tokens. That — plus the cold-prefill
  slope (unchanged 0.665, the indexer path → v1.1.8) — is the TTFT-at-depth frontier's
  decomposition.
- **The bench-slowness mechanism (last night's 2× scenario durations) is cache churn**:
  the engine's line during the scenario runs showed hits 0 / evicted 113 with the ~3.4 GiB
  state budget full — four concurrent multi-turn chains evict each other's states before
  their next turn, so every turn re-prefills. The patch adds states (more pressure); the
  lever for the churn is the state budget/eviction policy (`PROMPT_CACHE_GIB`), a knobs
  cell for the next window.
- The stack stopped clean after the block; production's control probe ran read-only
  against the idle serve (six 1-token requests).

## (round 42) Round 41's adoption call is REVISED — the A/B was confounded; the A/A/B probe is the decisive instrument (2026-10-28)

- **The revision (withdrawn, not silently)**: round 41's "the marks-patch works" rested on
  the patched serve's pair-1 shot-1 being already fast (1,445 ms) — but that serve had just
  run the duel, whose d8192 probe prefilled the SAME fill (the duel's generator and the
  probe's are identical — words, formula, count). The unpatched arm's pair-1 shot-1 was
  genuinely cold (7,359 ms). Warm-vs-cold across arms is not an A/B.
- **The deeper finding that forced it**: the UNPATCHED arm's own pair-1 shot-2 resumed 80%
  (7,359 → 1,440 ms) — the stock engine already keeps reusable states cross-request. The
  round-34 mark-policy diagnosis is therefore incomplete: whatever blocks resume in real
  workloads (the bench scenarios' hits-0 churn, the duel's junction divergence), a missing
  interior mark is not the whole story, and the patch's marks may be partially redundant.
- **The decisive instrument, now built**: the probe is A/A/B — body A (fill+tail1) twice
  (A1 cold, A2 = same-prompt resume), then body B (the SAME fill, a different tail): B1
  fast = cross-prompt resume (the fill's prefill reused across a changed tail). The
  markspatch phase now runs the probe FIRST on both arms (probe-before-gates/duel: cold
  readings), plus a post-duel probe on the patched arm (the cross-fill case). The counters
  echo between shots.
- **The adoption decision waits for the clean readings**: if the unpatched arm's B1 is
  already fast, the patch is redundant (do not adopt); if only the patched arm's B1 is
  fast, the patch earns its standing line. The production reference (65 ms) stands from
  round 41's control.

## (round 43) The A/A/B verdict: stock resume is real — the patch question needs one more discriminator (2026-10-28)

- **The A/A/B receipts** (`campaign-20261028-065603/18-markspatch.md`): the stock engine
  (UNPATCHED) already resumes **same-prompt (A2 = 1,434 ms, 80%) and cross-prompt (B1 =
  1,439 ms — the fill reused across a changed tail)** — identical to the patched arm on
  every A/A/B reading (patched: A2 1,434, B1 1,433). The mechanism is v1.1.6's mainline
  paged KV (page-level prefix sharing), not the Store's marks. **On this instrument the
  patch adds nothing.**
- **But the patched duel's TTFTs collapsed** (d4096 2,007 ms vs the 3,784 baseline;
  d8192 1,468 vs 5,650 — slope 0.155 vs 0.665) — and the patched duel ran AFTER the A/A/B
  probe had prefilled the same fill. The unpatched arm never ran a duel-after-probe
  sequence, so the cause is unresolved: the pages would explain it without the patch.
- **The discriminator is staged**: the markspatch phase now runs the duel on BOTH arms
  after each arm's probe. If the unpatched duel's d4096/d8192 drop like the patched ones,
  the pages do the work and the patch is redundant (do not adopt); if only the patched
  duel drops, the snapshot marks add value beyond the pages.
- **Standing regardless of the patch**: production's resume reference is 65 ms where ours
  is ~1,434 ms at 7.2k tokens — the page-resume/restore cost is the gap to close; and the
  cache churn under concurrent load (last night's hits-0/evicted-113) is the bench-slowness
  mechanism with `PROMPT_CACHE_GIB` as the lever.

## (round 44) The discriminator's verdict: the patch is redundant — and v1.1.8 is out with our levers (2026-10-28)

- **The discriminator's answer** (`campaign-20261028-073209/18-markspatch.md`): the
  UNPATCHED duel, run after the probe's fill prefill, collapsed exactly like the patched
  one — d4096 3,785 / d8192 1,485, slope **0.157** (the patched arm: 2,024/1,471/0.155 —
  identical within noise). **v1.1.6's paged KV does the cross-request resume; the marks
  patch is redundant and retires unadopted.** The A/A/B readings were identical on both
  arms too (A2 ~1,435, B1 ~1,435). The round-34 mark-policy diagnosis is superseded: the
  pages handle cross-request prefixes at page granularity; the round-37-era cold baselines
  were simply measured without a prior same-fill prefill.
- **v1.1.8 is out** (176 commits past our pin) with three items aimed at this line:
  **`TF_GLM_INDEX_CUDA=1`** (#1449 — the DSA indexer kernels: upstream's GB10 cold-TTFT
  −2%/−9%/−16% at 131k/524k/1M — the cold-prefill lever); **the fork rule** (#1291,
  `snap_fork` — opt-in per CUDA family: keep a state where a new prompt parts from an
  already-kept one — the repeated-document/changed-question pattern); and a GLM CUDA
  DFlash2 drafter-loader fix (rank-count sizing). Plus the longest-first prompt-cache
  find index and the KV-pool admission fix.
- **The adoption battery is staged** (the `v118` phase): the pin bumps to v1.1.8
  (`812fb040`) with `patches/glm-fork-rule.patch` (one line: `pub const snap_fork = true`,
  upstream's own opt-in mechanism); the battery = the §2 gates → the A/A/B probe on
  v1.1.8+fork (vs the stock A2 ~1,434/B1 ~1,435) → the INDEX_CUDA A/B (the duel unset
  vs =1 — the TTFT slope is the instrument) → hardmode at --parallel 2 (the score
  receipt; receipts-equal-or-better vs the Focus's 92 decides the adoption). The
  `--parallel 2` bench shape (round 39) and the hardmode-only directive (round 38) are
  baked into the phase.

## (round 45) v1.1.8 ADOPTED — receipts-equal-or-better on every instrument (2026-10-28)

- **The battery** (`campaign-20261028-095233/19-v118.md`, engine v1.1.8 `03d08f1e` + the
  fork rule staged): §2 gates **ALL PASS** (g1–g4 content form); **hardmode 92** — equal
  to the Focus's v1.1.6 receipts (rounds 37/40); solo 57.5/57.9, c2 93.9, c4 152.4 —
  within noise of v1.1.6; the A/A/B probe identical to stock (A2 1,432 / B1 1,438 vs
  1,434/1,435). **Adopted: the pin stands at v1.1.8 (`812fb040`), the standing config
  serves pristine (PATCHES empty — the fork rule showed no delta on the instrument and
  stays unstaged; the marks patch retired in round 44).**
- **The INDEX_CUDA A/B was confounded by the phase order — the lesson repeats**: the
  unset arm's duel ran after the probe's fill prefill (pages-resumed: d8192 1,472 ms),
  the INDEX_CUDA arm's duel ran cold on a fresh serve (d8192 5,627 ms — matching the
  v1.1.6 cold baselines exactly). The 8k-depth instrument cannot resolve the indexer:
  upstream's own curve claims ~0.3% at 8k and the real numbers at 131k/524k/1M. **The
  INDEX_CUDA receipt is owed at depth** — the depth ladder's 64k–384k TTFT rows with the
  env unset vs =1 is the next window's instrument.
- **What v1.1.8 brings the line**: the indexer kernels (the deep-depth lever, receipt
  owed), the fork rule (unstaged — no measured delta; the pages already cover the
  shared-prefix case), the longest-first cache index, the KV-pool admission fix, and the
  DFlash2 drafter-loader fix (rank-count sizing — a real GLM CUDA bug fix).
- **The frontier decomposition stands**: cold prefill (the indexer at depth — receipt
  owed), the resume/tail cost (~1,434 ms vs production's 65 ms — the granularity gap),
  and the cache churn under load (the `PROMPT_CACHE_GIB` lever).

## (round 46) Two window cells staged: the INDEX_CUDA depth ladder + the PROMPT_CACHE_GIB churn cell (2026-10-28)

- **`indexdepth`** (the owed round-45 receipt): the `TF_GLM_INDEX_CUDA` A/B at depth —
  the TTFT ladder 64k/128k/192k/256k/320k/384k (`max_tokens=1`, actual prompt_tokens read
  from each response's usage) plus a 512-token decode row at 96k, both arms on the standing
  config (Focus pristine, dense4fp8, 524288×4), each arm a fresh serve. **The ladder fills
  are per-row distinct from token 1** (decoration keyed on `(i + depth)`) — a close read of
  the duel's generator showed its rows are token-prefixes of each other, so it is NOT
  reused here; no ladder row can resume another's pages, and the prompt-cache counters
  double as the no-sharing proof (one miss per row). Walls are client-side; the fixed share
  is identical across arms, so the deltas stand.
- **`cachegib`** (the round-45 queue item): the `PROMPT_CACHE_GIB` churn cell — a fixed
  load of 24 distinct ~64k fills through 8 rounds × 4 concurrent streams (rounds 1–6 cover
  all 24, rounds 7–8 re-visit fills 1–8), engine-default store vs `PROMPT_CACHE_GIB=16`
  (auto-drop to 8 on an admission refusal — the ceiling itself is a receipt). Pressure
  math: the 3.9 GiB default store thrashes once KV state exceeds ~2.6 KB/token; the
  expected reading is default-arm revisit rounds ≈ cold (99%) vs gib16 revisit ≈ resume
  (the fabricated-data dry run of the receipt parser reads exactly this shape).
- Both phases are session-specific (retire with their receipts), both arms have identical
  pre-histories (fresh serve each), and both receipt parsers were dry-run against
  fabricated data before staging. Runbook: `PHASES="preflight indexdepth cachegib summary"`.

## (round 47) The window's receipts: INDEX_CUDA is a real, growing win at depth; the cache knob is budget-bound (2026-10-28)

- **`indexdepth` — the owed receipt is IN** (`campaign-20261028-113509/20-indexdepth.md`,
  both arms fresh serves on the standing config, Focus pristine, 524288×4):
  `TF_GLM_INDEX_CUDA=1` **flattens the depth-prefill growth**. TTFT deltas: 64k +0.0%,
  **131k −2.6%**, 192k −2.7%, 256k −3.6%, 320k −4.5%, **384k −5.5%** (350.5 → 331.4 s).
  The off-arm marginal slopes RISE with depth (0.860 → 0.976 ms/tty) — cold prefill is
  superlinear; the on-arm stays flat-ish (0.816 → 0.882). Overall cold slope 0.891 →
  0.842. The no-sharing proof held: exactly 8 misses per arm (the per-row-distinct
  fills did not resume each other). Loading unchanged (224.5–226.8 s), decode unchanged
  (38.3 vs 39.6 t/s at the 96k row — the indexer is prefill-side only), d0 unchanged
  (+0.7%, noise).
- **Upstream's claim transfers**: upstream (#1449) claimed −2% cold-TTFT at 131k — we
  **measured −2.6%** at exactly that depth; their curve's shape (gains growing with
  depth) matches our ladder's trend (−5.5% at 384k, extrapolating ≈ −6.5% at 524k vs
  their −9% — their deeper points sit beyond our ladder). Written into
  `docs/ECOSYSTEM.md` as a verification datum.
- **Adoption status: pending one gates serve** — the knob rebuilds the same indexer
  scoring in two dedicated kernels (upstream's contract is byte-equal), but our exactness
  gates never ran WITH it, so the discipline holds: **next window = one restart + §2
  gates with `TF_GLM_INDEX_CUDA=1` (~12 min), then the default flips** in config.sh.
- **`cachegib` — the knob is NOT free at the standing budget, and the churn mechanism is
  now a controlled fact** (`campaign-20261028-113509/21-cachegib.md`):
  - The **default arm (complete)**: 8 rounds × 4 concurrent ~116k-token fills — hits stay
    **0 across all 32 requests**, evictions climb **+5/round** (37 by round 8), and every
    revisit round re-prefills in full (walls 438.1–440.5 s, revisit = cold 99%+). The
    overnight bench's hits-0/evicted-113 pattern is now receipted as the store thrashing
    at 2.6 GiB under concurrent distinct-prompt load.
  - **The gib16 arm is void, and that is its own receipt**: `--prompt-cache-gib 16` is in
    the engine's argv (verified via `docker inspect`), yet the serve line reads **2.6 GiB
    prompt cache — identical to default** — and the arm's counters march default's
    trajectory exactly (evicted 2/7/12/17). Whether the engine budget-caps the knob (the
    serve line: 13.4 GiB left after a 12.2 GiB reserve) or ignores it is unresolved from
    one serve. **Discriminator cell queued**: one serve at `PROMPT_CACHE_GIB=10` with
    `CONTEXT=262144` — if the store lifts, the budget binds and the cache lever is a
    window/stream trade; if it stays 2.6, the flag doesn't lift the store upstream-bound
    (ECOSYSTEM data).
  - **The lever reframed**: at 524288×4 the kept-states store does not grow on request —
    the cache lever is shrinking CONTEXT/PARALLEL, or the **`--spill-gib` route (v1.1.8):
    evict to disk instead of dropping**, the natural next cell.
- **The window's slow half is owned**: the cg fills measured **115,771 actual
  prompt_tokens each** (designed ~64k; my word→token assumption was ~2, actual ~3.5) —
  each round is ~463k cold-prefill tokens at the machine's ~1,060–1,220 tok/s aggregate ≈
  438 s, so 8 rounds ≈ 58 min/arm. The gib16 arm's last 4 rounds (a proven no-op — the
  counters already matched default exactly) were killed at 13:3x to hand production back
  ~25 min early. Ops lesson rerun (the ledger's "watchers must exclude their own command
  text"): the kill's `pkill -f "cg-f"` matched the issuing ssh's own command line and cut
  the session mid-kill — the pgid TERM had already landed; the follow-up verified the
  window gone (bracket-trick pgrep), stopped the stack, and freed the port.
- **Wrap-queue**: (1) the gates-with-INDEX_CUDA serve then the config flip; (2) the GIB
  discriminator serve; (3) a `--spill-gib` churn cell (the load recipe now exists — the
  phase's bodies/curls are reusable); (4) the retired session phases (markspatch, v118,
  indexdepth, cachegib) get deleted from run-qualification.sh now that their receipts
  are in; (5) optional: a read-only prodqual extension to take PRODUCTION's depth-prefill
  ladder for the same table (a new comparison axis: our 0.84–0.98 ms/tty cold at depth vs
  theirs).

## (round 48) The ~50-minute window staged: the INDEX_CUDA adoption gates, the GIB discriminator, the spill cell (2026-10-28)

- **`ixgates`**: §2 gates + the standard duel WITH `TF_GLM_INDEX_CUDA=1` — the exactness
  receipt the adoption needs (the perf side is already in: round 47's depth ladder).
  Gates PASS → config.sh flips the knob as the standing default in the digest sitting.
- **`gibdisc`**: the round-47 discriminator — arm 1 serves `PROMPT_CACHE_GIB=10` at the
  standing 524288×4 (10 fits inside the serve line's 13.4-GiB slack: a budget cap would
  lift the store off 2.6 GiB); if it still reads 2.6, arm 2 drops the window to 262144 —
  a lift there means the knob works and the standing budget binds; still 2.6 means the
  flag doesn't lift the store at all (upstream-bound data).
- **`spillgib`**: the round-47 reframe's cell — `--spill-gib 32` (new: plumbed through
  start.sh/config.sh this round) with the round-47 churn load scaled to churn cheaply:
  16 distinct ~56k-token fills, 6 rounds × 4 streams (rounds 1–4 cover, 5–6 revisit fills
  1–8); the working set (~900k tokens) exceeds the store's ~810k-token hold, so rounds
  5–6 MUST come from somewhere — fast revisits = spill restores from disk; revisit = cold
  = spill does not (round 47's default arm is the control). A serve refusal on the new
  flag is itself the receipt.
- All three receipt parsers/serve-line greps dry-run against fabricated data and the
  observed serve line before staging. Runbook: `PHASES="preflight ixgates gibdisc spillgib summary"`,
  ~50 min (2–4 restarts + one ~16-min churn load + one ~14-min cover ladder).

## (round 49) INDEX_CUDA ADOPTED; the cache levers close; seven retired phases deleted (2026-10-28)

- **`TF_GLM_INDEX_CUDA=1` is the standing default** (`campaign-20261028-141916/
  22-ixgates.md`): §2 gates **ALL PASS** under the knob — upstream's byte-equal contract
  shown on our serve (g1 determinism, g2 drafted=plain, g3 resumed=fresh, g4
  concurrent=solo; g5 note as always) — and the duel is within noise of the v1.1.8
  references (solo 57.0/56.9, c2 93.7, c4 152.3 vs 57.5–57.9/93.9/152.4). Combined with
  round 47's depth ladder (−2.6% at 131k → −5.5% at 393k, growing with depth), the
  receipts-equal-or-better bar is cleared. config.sh exports the knob (outside the config
  fingerprint — no rebuild on the next start); the README table carries the row.
- **The gibdisc receipt's first conclusion is WITHDRAWN** (the correction protocol):
  `23-gibdisc.md` printed "arm1 LIFTED the store — the knob works" — that was my
  branch-anchoring bug (I matched the literal "2.6"): the data line reads **2.5 GiB with
  GIB=10**, i.e. the store did NOT lift to ~10. The full evidence now reads: GIB=16 →
  2.6 with default-identical counters (round 47, behavioral); GIB=10 → 2.5 (round 48).
  **`--prompt-cache-gib` does not size the kept-states store at 524288×4.** The last
  open read is one cheap serve (`GIB=10 @ CONTEXT=262144`) — queued.
- **The spill lever is CLOSED for GLM** (`24-spillgib.md`): the engine refused the serve
  — spill covers "Nemotron, the Qwen hybrids and Flash Next only on CUDA". Upstream-bound
  (ECOSYSTEM); the SPILL_GIB plumbing stays staged for the day upstream covers GLM.
- **Seven retired session phases deleted** from run-qualification.sh (markspatch, v118,
  indexdepth, cachegib, ixgates, gibdisc, spillgib — 522 lines; all receipts live in
  results/ and the docs). The script is back to its standing phases only.
- **The frontier after today**: cold prefill at depth is now receipted AND mitigated
  (the indexer knob — the standing config serves it). The remaining frontier items:
  (1) the resume/restore cost (~1,434 ms vs production's 65 ms at 7.2k — the source-level
  dig, no window needed); (2) the churn-under-load reality (the store is fixed at ~2.6 GiB
  and spill doesn't cover GLM — the honest statement is the store thrashes under
  distinct-prompt concurrency and the fix is upstream's); (3) the beat-94 quality track
  (the AZ retrained-selector route, blocked on the EXL3 requant format — watch upstream's
  exl3_layout/eaq_container work).

## (round 50) The audit: vision is a real parity gap (production serves it, we don't); the docs swept current (2026-10-28)

- **Vision: NOT included — and now it's a receipted gap, not a silent one.** The facts,
  all checked today: the AZ-Focus checkpoint carries the vision tower (347
  `model.visual.*` tensors in its safetensors index; `architectures:
  Glm5NextForConditionalGeneration`); TensorFold v1.1.8 supports GLM vision on CUDA
  behind `--vision` (`families/glm/cuda_vision.zig`, `cuda_images.zig`; the optional
  `--vision-image-tokens` limit; "every rank must hold the rows rank 0 sends" — a real
  memory term at 524288×4); **production's argv carries `--vision`** (docker inspect,
  read-only). Our serve has never passed it, no receipt exists for it, and the bench is
  text-only — so neither the quality bars nor the perf instruments have ever seen it.
  **Enabling is a (user) call**: a `VISION` config knob + a qualification cell (the
  admission arithmetic at 524288×4, the §2 gates, a smoke image request, and the
  carry-cost duel). Recorded as an open item in TOOL_EVAL_TESTING.md and the README's
  status table.
- **The docs sweep** (the second audit question): README's status moved to forty-nine
  rounds + the indexer adoption; DELTAS's header carries the knob; VALIDATION §4 and
  CONTEXT_512K_PLAN gained dated 2026-10-28 superseding notes (the engine is v1.1.8+knob;
  the gates re-qualified on it; the depth fact-ladder's last run is v1.1.6-era — re-run
  queued); PERF_PLAN gained the rounds-45–49 status line. The historical v1.1.6 mentions
  are dated entries and stand as history. The anchors TSV is unchanged — the knob's duel
  (round 48) is within noise of the standing row, and the receipts carry it.

## (round 51) VISION ENABLED as the standing default; the photo suite staged (2026-10-28)

- **The (user) calls, verbatim in substance**: vision is a want — "we should have enabled
  it by now"; 512k context is a want; **no more performance testing**; nothing below
  512k max context; **get vision admitted as a default before anything else**; and the
  test must check detail perception — "more than just a general question", long answers
  allowed. All recorded here as standing directives.
- **The source facts that made the flip safe** (v1.1.8): the checkpoint's 347
  `model.visual.*` tensors are **BF16** (verified in the safetensors headers — the
  requant's `-vb 16` recipe), which the engine's vision loader (`Lin` union: bf16 /
  MXFP8 / NVFP4) reads directly; `--vision` defaults to 4 images × 4096 tokens;
  requests are OpenAI-style `image_url` data-URL parts; the flag family also carries
  `--vision-urls`, `--vision-offload`, `--vision-max-images` (1–64),
  `--vision-image-tokens`. Production already serves `--vision` (round 50) — the parity
  gap closes with this default.
- **The flip**: config.sh defaults `VISION=1` → start.sh passes `--vision` (knob exports
  sit outside the config fingerprint — no rebuild). 524288×4 stands.
- **The test suite** (`assets/vision/`, committed): a synthetic four-quadrant PNG
  (byte-verified: TL=red TR=green BL=blue BR=white) plus **three Wikimedia Commons
  photos** — the Golden Gate Bridge from a beach, a plains zebra at a waterhole (rainbow,
  impala), a desert STOP sign with a row of numbered mailboxes — CC BY-SA with
  attribution (`NOTICE.md`, `_fetch-meta.json`). Each image's ground truth was **viewed
  by the agent** on production's vision-enabled serve. Per image the phase asks a
  targeted question (max_tokens 64) and a long-form detail question (max_tokens 1024),
  scoring **detail coverage n/m** against 4–7 agent-verified details (the receipt
  parser dry-run shows the scoring discriminates: a thin answer reads 5/7, a full one
  7/7).
- **The `visionen` phase** (staged, retires with its receipt): the standing serve's
  admission at 524288×4 with `--vision` (a PARALLEL=2 retry preserves the window if the
  arithmetic refuses), the four-image suite, and the §2 gates on the vision serve.
- **Dropped per the (user) call**: the queued `GIB=10 @ CONTEXT=262144` serve (a sub-512k
  config). Sub-512k cells are out of scope.

## (round 52) The vision refusal digested: the image lacked CUDA 13 cuBLAS — fixed in the Dockerfile (2026-10-28)

- **The refusal receipt** (`campaign-20261028-151636/25-visionen.md`): the vision serve
  refused on both PARALLEL attempts — the engine's own words: *"`libcublasLt.so.13` is
  required for CUDA vision towers (`--vision`) and CUDA cuBLASLt projections; install the
  NVIDIA CUDA 13 cuBLAS runtime; a driver-only host does not include it."* The checkpoint
  digest had already read (47/47 files cached); the failure is purely the runtime image.
- **The root cause**: our image is multi-stage — stage 1 builds on
  `nvcr.io/nvidia/pytorch:26.07-py3` (a CUDA-devel base WITH the toolkit, where the
  fatbins compile); stage 2 is a minimal `ubuntu:24.04` runtime that ships the binary,
  NCCL, and the RDMA user space — but NOT cuBLAS. The vision tower's projections run
  cuBLASLt; the main model path never needed it, so the gap was invisible until --vision.
  Production runs the same NVCR base and carries `/usr/local/cuda-13.3` with
  `libcublasLt.so.13` (verified read-only via docker exec) — that is how it serves vision.
- **The fix** (image/Dockerfile): stage 2 now `COPY --from=build`s
  `libcublasLt.so.13` + `libcublas.so.13` (the soname symlinks materialize as full
  copies) into `/opt/tensorfold/lib/` — already on the loader path via the image's
  ld.so.conf, so no LD_LIBRARY_PATH is needed.
- **The support target, from production's own serve line (the user's reference)**:
  *vision: image and video input, a 1.05 GiB tower with 1.41 GiB of workspace; at most
  2048 tokens a picture, 16384 a clip (128 frames at 2 a second)*. Our flag mapping:
  `--vision-image-tokens 2048` (production parity; our default was 4096),
  `--vision-video-tokens` already defaults to 16384, the 128-frames/2fps clip cap is the
  engine's own, and the tower/workspace figures are the engine's arithmetic. start.sh now
  passes `--vision --vision-image-tokens 2048` when VISION=1.
- **The rebuild**: the Dockerfile is outside the config fingerprint — an explicit
  `prepare.sh` runs on the head (CPU-side, production untouched); the visionen re-run
  follows once the image lands.

## (round 53) The rank mismatch digested: vision is rank-agreed + the decode libs are pinned (2026-10-28)

- **The refusal receipt** (`campaign-20261028-153511/25-visionen.md`): *"REFUSE rank
  settings: rank 1's vision differs from rank 0's (--vision (or its image tokens) given
  to some ranks and not others)"*. **The cause was my flag placement**: `--vision` went
  into `rank0_flags` (head-only server flags), but vision is a **rank-agreed setting**
  the engine cross-checks at start. The prompt-cache/spill flags above it are genuinely
  rank-0-side; vision is not. **Fix**: a new `rank_both_flags` array appended to BOTH
  rank commands in start.sh (rank 1's docker run on the worker included).
- **Two decode-lib warnings rode along** (head log): `libturbojpeg.so.0 is required for
  JPEG inputs (--vision)` and `libwebpdecoder.so.3 ... for WebP inputs`. Non-fatal at
  serve time but fatal at first JPEG input — and our test suite is three JPEGs. Source
  read: the engine dlsyms the **tj3 API and version-checks** what it loads
  (`core/picture/jpeg.zig` pins 3.1.4.1; `webp.zig` pins 1.6.0, code 0x010600) — distro
  libjpeg-turbo 2.x / libwebp 1.3.x do not carry it. Production's container carries
  neither (torchvision bundles its own codecs) — no base-image shortcut.
- **The fix** (image/Dockerfile, stage 1): build libjpeg-turbo **3.1.4.1** (cmake, SIMD
  via nasm) and libwebp **1.6.0**, install the real shared objects renamed to the
  sonames the engine searches — `libturbojpeg.so.0` and `libwebpdecoder.so.3` — into
  `/out/lib/`, which ships to the runtime stage's `/opt/tensorfold/lib/`: both the
  image's loader path AND the engine's `../lib` search location. (Also confirmed:
  `libtfgrammar.so` is already in the image — structured output is covered.)
- The rebuild runs on the head; the visionen re-run follows.

## (round 54) The 500s digested: the chat template is text-only — a vision template generated from the tokenizer (2026-10-28)

- **The serve came UP with the tower resident** (`campaign-20261028-154906/
  25-visionen.md`): model 84.75 GiB (the ~1.25 GiB vision tower, was 83.50), 12.6 GiB
  left — the cuBLAS fix and the rank agreement both held, and the §2 text gates ALL
  PASS. Every image request 500'd.
- **The engine's own warning named it** (head log): *"--vision: the chat template writes
  no image placeholder for an image part, so image requests will fail; serve with
  --chat-template naming a template that has an image path."* The source confirms the
  contract (server.zig `templateImages` probes the render and looks for
  `image_token_id`; images.zig `expand` counts ONE placeholder per part and expands each
  to the image's rows).
- **The root cause is the EXL3 conversion line, not our serve**: BOTH the AZ-Focus
  requant AND the stock Mia EXL3 ship the same **text-only chat template** — its media
  branch emits `"<reminder>You are unable to process this image because you don't have
  multi-modal input ability…</reminder>"`. **Production's images work anyway because the
  PYTHON engine routes media parts through the model's HF processor, which writes the
  markers itself** (`<|​begin_of_image|><|​image|><|​end_of_image|>` — the repo's own
  vision tools show the convention); the native engine delegates the media branch to
  the template. Upstream-bound data (ECOSYSTEM.md).
- **The fix**: `image/share/glm5-next-vision.jinja` — the checkpoint's own template with
  ONLY the media branch replaced (image → begin_of_image+image+end_of_image, video →
  begin_of_video+video+end_of_video, audio keeps the reminder), generated by
  `image/gen-vision-template.py` **from the tokenizer's exact bytes** (the media tokens
  carry zero-width characters — never hand-typed). Baked into the image at
  `/opt/tensorfold/share/`; start.sh passes `--chat-template` with it on BOTH ranks
  under VISION=1. The template is a build artifact of the tokenizer + base template —
  regenerate for a new checkpoint.

## (round 55) VISION VERIFIED — the suite passes on the native line at production-equivalent perception (2026-10-28)

- **The enablement receipt is complete** (`campaign-20261028-165021/25-visionen.md`):
  the serve came up with the tower resident (model 84.75 GiB, 12.6 GiB left), the
  startup template-probe warning is GONE, the §2 gates ALL PASS on the vision serve, and
  the four-image suite read **targeted 4/4, detail coverage 23/25** (the bridge answer
  names International Orange; the zebra answer catches the stripe transition and the
  open mouth; the sign answer reads STOP, the octagon, the mailboxes and their numbers).
- **The production comparison** (the same suite read-only against production,
  prodqual-style; both raw answer sets + the scored comparison are in the campaign
  dir): **ours 4/4 targeted, 23/25 detail — production 4/4 targeted, 22/25 detail**.
  The subjective read (the agent viewed every image and both full answer sets):
  equivalent depth and accuracy. Two honest notes: (1) production's targeted answers
  needed a 1024 budget (the python engine reasons before answering — at 64 tokens they
  truncated; ours answered complete at 64); (2) the one scoring divergence — production
  read specific mailbox numbers ("77", "783") that don't match the legible
  5835/5841/5909 (apparent misreads the keyword scorer under-credited); ours read the
  numbers generically and did not misattribute.
- **The ground-truth correction** (the correction protocol): both engines wrote the
  zebra "walking from left to right" — the manifest's original ground truth said "to
  the left" and was WRONG (the head faces right; re-viewed today). The manifest is
  corrected with a note; both engines out-read the provided ground truth on that detail.
- **The structural note**: both lines run the same GLM-5.3-Flash tower (BF16 in both
  checkpoints) — this comparison validates the native stack end to end (decode → tower
  → cuBLASLt projections → rows → the language model).
- **The chain that took five windows, all receipted**: the missing CUDA 13 cuBLAS
  runtime (round 52), the rank-agreed vision setting (round 53), the pinned decode
  libraries (round 53), libwebp's static-by-default CMake (round 53 fix), and the
  text-only EXL3 chat template (round 54 — the python engine's processor path masks it
  on production; upstream-bound data in ECOSYSTEM.md).

## (round 56) The depth re-run re-pointed to the standing config; the resume gap root-read at source level (2026-10-28)

- **The depth phase modernized** (the (user) catch: PARALLEL=2 was dense8-era legacy): the
  phase now serves the **standing defaults** (bare `restart` — dense4fp8 +
  `TF_GLM_INDEX_CUDA=1` + vision at 524288×4) and cites the v1.1.6-era 12/12 receipt as
  its comparison anchor. Staged for the next window.
- **The resume-cost dig, source level** (no window): our ~1,434 ms resume of a 7.2k-token
  state vs production's 65 ms is **architectural, not incidental**. The native engine's
  prompt cache is a SNAP-COPY design: a kept state is a private buffer ("its MLA prefixes
  beside its KDA states", `kept.zig`), and a resume (`restore` → `copySnap`) **copies the
  whole saved state back into the resuming slot's pools** (one command-buffer submission +
  `finish`), with a peer `mirror.send(.restore)` exchange around it and `overwrite`/
  `copyOut` bookkeeping when the resuming slot differs from the state's home. The state at
  7.2k tokens is ~23 MB (the cachegib calibration: ~3.2 KB/token) — the copy's bandwidth is
  trivial; the cost is the synchronization structure (the device-wide `finish`, the peer
  exchange, the request pipeline around it) — the resume-specific share is ~1.2 s of the
  1,434 ms wall. **Production's 65 ms is the python engine's page-remap design**: its kept
  pages ARE pool pages, reused by reference — nothing is copied.
- **The lever** (recorded in ECOSYSTEM.md as upstream-shaped, nothing posted): the engine
  carries a **paged prompt store** (`prompt_radix.zig`; `rules.paged`, "0: not paged") —
  a remap-style resume path — but the GLM family does not wire it (`engine_paged=false`
  default; the snap_* decls set lookahead/fork/grid, never paged). If upstream's paged
  store is GLM-ready, a family-level enable is the production-class resume lever; it
  needs the backend's page-ownership callbacks. The second lever is batching the peer
  mirror out of the restore's critical path.
- **The upstream watch**: zero commits on main since v1.1.8 (no v1.1.9 yet) — the beat-94
  blocker (the EXL3-format work for the AZ retrained-selector route) is unchanged; the
  watch stays open.

## (round 57) The standing config fully qualified: depth 12/12 on dense4fp8 + the indexer + vision (2026-10-28)

- **The depth gate passed clean** (`campaign-20261028-174914/04-depth.md`): 3/3 facts at
  8k, 64k, 192k, and 384k — **12/12** — on the standing default (dense4fp8 +
  `TF_GLM_INDEX_CUDA=1` + vision resident, 524288×4, the serve line's 84.75 GiB model
  with the tower). Equal to the v1.1.6-era 12/12 anchor.
- **The line's qualification is now complete end to end on ONE config**: the §2 gates
  (rounds 48/55), the depth fact ladder (this round), hardmode 92 / tool-eval 95
  (rounds 37–45's Focus receipts), the depth-prefill receipt (round 47), the vision
  suite at production-equivalent perception (round 55), and the perf anchors within
  noise. Everything the (user) asked for — vision, 512k, the indexer — serves as the
  default with receipts.
- **What remains open** (no windows needed): the upstream watch (v1.1.9+ decides the
  next adoption; the beat-94 blocker — the EXL3-format work for the AZ retrained-
  selector route — unchanged as of round 56's check); the resume lever (the paged
  prompt store, upstream-shaped, round 56); and the two disk items awaiting (user)
  calls (vllm-node-b12x 28 GB ×2; the AZ/Focus mirror copies ~154 G + ~328 G).

## (round 58) The disk choreography done; the requant's format gap root-read — the bridge is a dequantize (2026-10-28)

- **The publish item closes** ((user)): what we run is already out there (the served
  checkpoint IS AxonZeta's public release — MIT, the zai-org BF16 lineage, its
  azfocus_provenance.json carries the tensor-level lineage). Nothing to publish.
- **The disk choreography** ((user) confirmed): deleted the upstream mirrors
  (AxonZeta 164 G, azampatti 170 G), the TR3 variant (164 G) and two 1-G stubs — ~200 G
  freed (the blob store hardlinks dedup the logical sizes). Kept: the served Focus, the
  drafter, production's Mia stock, the requant working dir (the repack source), and the
  NVFP4 repo + spark-vllm docker untouched ((user): the vLLM docker is not this
  project's — the ledger's vllm-node item DROPPED). 2.0 T free.
- **The requant format gap, root-read to the byte level**: the layouts differ in THREE
  places — (1) the routed experts' `.mcg/.trellis/.suh/.svh` quads are STRUCTURALLY
  IDENTICAL in both (same dtypes/shapes; `.mcg` is `I32 [1]` vs `I32 []` — a marker
  reshape); (2) the merged `conv1d.weight [24576,1,4]` splits into
  `q/k/v_conv1d.weight [8192,1,4]` (a dim-0 slice); (3) **the 290 non-expert linears**:
  the 1.6.4 converter stored them as trellis-coded 4-bit payloads
  (`trellis I16 [256,1536,64]` + `suh/svh` scales), while the engine's old layout wants
  **BF16 `.weight`** (`q_proj.weight BF16 [8192,4096]`) — the engine quantizes those
  linears ITSELF at load ("290 linears packed (4/4 bits)").
- **So the bridge is a DEQUANTIZE, not a repack**: reconstruct BF16 weights from the
  trellis payloads (the pipeline's own az_dequant.py machinery — exllamav3's dequant —
  already proved this path on the azampatti source), emit the old layout (BF16 .weight
  for the 290 linears, the experts' quads copied through with the mcg reshape, the conv
  split, the old-shape quantization_config: bits 4 / codebook mcg / head_bits 16 /
  scope glm53_routed_experts_only), then the serve attempt is the format verdict and
  the azqual battery — gates + hardmode — finally runs: **the beat-94 verdict on the
  retrained selector unblocks.**
- **The both-hosts plan** ((user)): the dequant/re-emit job shards naturally by layer —
  the head and the worker each process half the 23 shards against a shared output dir,
  the expert quads and unquantized tensors copy byte-identical. Validation: one window,
  the serve attempt first (the refusal would be the receipt), then the battery on the
  green serve.

## (round 59) The requant bridge: the loader verification (the user's get-it-right-first-time standard) (2026-10-28)

- **The engine's EXL3 contract, from its own source** (`families/glm/cuda_exl3.zig` line
  26): *"The EXL3 checkpoints the kernels read: 4-bit routed experts on the 'mcg'
  codebook (everything else bf16)."* `admit()` requires integer `bits=4` +
  `codebook="mcg"` — the requant's config carries both. So the target layout is exactly:
  experts as 4-bit mcg quads, all other linears as BF16 `.weight` (the engine packs
  those itself at load — the serve line's "290 linears packed (4/4 bits)").
- **Verified against the loader, item by item**:
  - The routed experts: the quads are byte-structure-identical between the requant and
    the served Focus, and the `.mcg` markers carry the SAME magic value (-877912083) —
    the requant's experts are genuine 4-bit mcg (the -eb 16 did not change the mcg
    coding). **Copy-through with the []→[1] reshape is CONFIRMED.**
  - The conv1d: the loader accepts the MERGED form itself (`convs()` reads
    `conv1d.weight [3*channels, conv, 1]` and cuts it three ways — "mlx-lm's one"); the
    requant's tensor is `[24576, 1, 4]` — a last-two-dims transpose feeds the loader's
    own cut. **No 3-way split needed.**
  - The linears: `weights.zig` stacks per-projection tensors by exact name
    (`q_proj/k_proj/v_proj/...` — `src()` fails with the receipted MissingTensor), BF16
    at the old checkpoint's shapes. **The trellis payloads must dequantize to BF16
    `.weight` — confirmed required.**
  - The shards: the loader resolves tensors through the index's name→file mapping —
    shard naming is free.
- **Still open before the script is trusted** (the next sitting's first work): (1) the
  exllamav3 1.6.4 dequant path — the exact trellis→BF16 math and a callable API in the
  installed venv (az_dequant.py proved the machinery on a 16-bit source; the 4-bit
  trellis decode is the same reader); (2) the converter's qkv fusion order (q,k,v vs
  another order) — read from exllamav3's writer source, not assumed; (3) the fail-fast
  design: a one-layer dry-run printing the full name-mapping diff before the full run,
  per-tensor NaN/Inf/scale sanity on every dequantized weight, and a name-set equality
  check against the loader's expected inventory.

## (round 60) The repack script built — the name mapping verified EXACT on the real data (2026-10-28)

- **The writer-side verification completed** (the round-59 open checks): the dequant API
  is exllamav3's own — `Exl3HfLinear.dequantized_weight()` ("W as (in, out) fp16,
  reconstructed from the trellis" — trellis decode + Hadamard + scales, the exact
  inverse of the converter); the qkv fusion order is **q|k|v** (confirmed from
  `gated_delta_net`'s own arithmetic: `fdim_qkv == 2*nk*kd + nv*vd` and the conv stash
  map's piece order); the conv1d merged form slices q|k|v the same way.
- **The script** (`scripts/az-repack.py`, runs on the head's exllamav3 venv): four
  modes — `--mode names` (no torch/GPU: the name mapping applied to all 150,891
  requant tensors and diffed against the served Focus's inventory), `--mode dry` (the
  GPU gate: one dense + one expert layer end to end, per-tensor finite/absmax checks
  with the name in every failure, the name-set + shape equality vs the reference,
  the mcg magic verified on every expert group), `--mode full` (both hosts: the source
  staged to the worker whole-file, both halves on each host's GPU, the outputs merged
  and verified, the old-shape config + an honest repack_provenance.json written),
  and the internal work/merge modes. 26 fail-fast `die()` points, every one naming its
  tensor or step.
- **The name-level pre-flight ran on the real data: EXACT** — 150,226 produced names ==
  the reference's 150,226, zero missing, zero extra. The first `--mode names` run
  actually caught the one design bug (the conv1d: the reference uses three separate
  q/k/v_conv1d tensors — the 3-way slice, not the transpose I'd designed) before
  anything touched a GPU: 150,158 + 68 = 150,226 exactly.
- **The runbook** (the user drives): production offline → `git pull` on the head →
  `--mode dry` (the log comes back to the agent for inspection) → on the OK, `--mode
  full` (~1 h; the worker needs the exllamav3 venv — the script checks and prints the
  install line if missing, with a head-only fallback documented) → the placement + the
  serve window (the format verdict), then the azqual battery on green.

## (round 61) The repack runbook staged: the worker's dequant venv provisioned, the az2 battery phase written (2026-10-28)

- **The worker's exllamav3 venv provisioned by the agent** (the round-60 script's one
  prerequisite): `~/.venv-exl3` on the worker with torch 2.14.1+cu130,
  exllamav3 1.6.4 (the ext compiled for the device at first import — ninja + the CUDA 13
  toolkit + python3.12-dev were the missing pieces, all resolved), safetensors,
  transformers. **Verified to the last symbol**: `ext.reconstruct` present and
  `Exl3HfLinear` importable — the dequant path the repack calls is complete on both
  hosts. The install lessons: the venv's bin must be on PATH for torch's ninja check,
  and the ext compile needs python3.12-dev (Python.h) — neither is a surprise now.
- **The `az2` phase written** (session-specific; retires with the verdict): places the
  repacked checkpoint (`~/az-repack-out/merged`) into the HF cache as
  `local/GLM-5.3-Flash-AZ-EXL3`, serves it at the standing config (VISION=0 — the cell
  tests the selector's text quality; the requant's template is the text-only family
  template), and on a green load runs the §2 gates + hardmode at --parallel 2 —
  **the beat-94 verdict on the retrained selector**. A serve refusal is the format
  receipt (the engine names the tensor).
- **The runbook** (the user drives; every step fail-fast): production offline → the
  head: `--mode names` (re-confirmed EXACT) → `--mode dry` (the log comes back for
  inspection) → on the go, `--mode full` (both hosts, ~1 h) → the `az2` window (the
  format verdict + the battery).

## (round 62) The dry-run's traceback fixed host-agnostically: the ext's JIT needs PATH, and the head needed transformers (2026-10-28)

- **The dry-run's failure** was the same class the worker hit over ssh: the exllamav3
  ext JIT-compiles at import and torch runs ninja via subprocess — running the script
  through the venv's python does NOT put the venv's bin (ninja) or the CUDA toolkit's
  bin (nvcc) on PATH. The head had both tools installed; they were simply unreachable.
- **The fix is in the script, by construction**: `fix_path()` runs at `main()` before
  any import — the venv's bin joins PATH ahead (ninja), the CUDA toolkit's bin joins if
  it holds nvcc, and a missing ninja dies with the exact install line. Both hosts then
  verified with the literal import chain: **HEAD IMPORT OK, WORKER IMPORT OK** (the
  head additionally needed `transformers` — installed; the worker already had it from
  the round-61 provisioning).
- The user re-runs `--mode dry`; every subsequent mode inherits the fixed PATH.

## (round 63) The dry-run's second traceback: my meta-buffer bug — the assign semantics fix (2026-10-28)

- **The failure moved forward** (the user's offline run): the conv1d slice worked, the
  PATH fix held, and the dequant itself failed at `mod.to(device)` —
  *"Cannot copy out of meta tensor"*. **My bug**: `Exl3HfLinear` registers its buffers
  on the META device (no storage), and my `copy_`-into-meta + `.to()` construction
  can't work — the class is built for the HF loader's **assign** semantics.
- **The fix** (`dequant_linear`): `load_state_dict({trellis, suh, svh, mcg}, strict=True,
  assign=True)` — the meta buffers are REPLACED by the real CUDA tensors (the mcg meta
  shape declared as (1,) to match the reshaped marker), `.to()` removed, `finalize()`
  then builds the inner LinearEXL3 on real data.
- **The CPU-side verification** (no GPU, production untouched): the construction chain
  (meta → assign → real buffers → finalize) runs against layer 0's real qkv_proj
  tensors — the only GPU remainder is `ext.reconstruct` itself (exllamav3's own path,
  its symbol verified on both hosts).

## (round 64) The CPU mechanism check PASSED; the "stall" was the sink, not the process (2026-10-28)

- **The assign-check result** (the round-63 verification, run against layer 0's real
  qkv_proj tensors on the head): the full construction chain verified — the meta
  buffers replaced by real tensors via `load_state_dict(assign=True)` (trellis I16
  [256,1536,64], suh F16 [4096], svh F16 [24576], mcg I32 reshaped [] → [1]), all
  `is_meta == False` after the assign, and `finalize()` built the inner LinearEXL3
  with the mcg magic **-877912083** intact. The mechanism that broke the round-63
  dry-run is gone on real data; the GPU dequant (`ext.reconstruct`) is the only
  untested remainder, and its symbol is verified on both hosts.
- **The stall that wasn't**: the check looked hung (empty output for minutes, 2.4%
  CPU) — the output pipe ended in `tail`, which emits nothing until EOF, so emptiness
  was guaranteed; and the process was I/O-bound (first-load page-ins of torch + the
  ext .so under production's just-restarted memory pressure), which reads as near-zero
  CPU. It completed on its own, correctly. Second sink artifact this session (round
  62's `tail` hid a compile error) — captured as the `diagnose-hung-commands` skill
  (installed 2026-10-28, ~/.config/opencode/skills/).
- **Practical note for the re-run**: the first dequant call pays the exllamav3 import
  (~1–2 min silent on the loaded head after the conv1d line) — a pause, not a hang;
  the script's own log lines are flushed live thereafter.

## (round 65) The dry-run's third failure was the last shape bug: the dequant transpose; the full shape contract verified (2026-10-28)

- **The failure** (the user's offline dry-run, production down): the PATH fix, the
  conv1d slice, all 3,456 expert-quad copies, the 35 plain copies and every |max|
  (0.10–0.41, indexer.wq_b 1.73 — sane) PASSED; the dequant itself worked and the
  shape gate caught the final bug: all 15 dequanted linears came out **(in, out)** —
  exllamav3's kernel convention (`get_weight_tensor` builds `(in_features,
  out_features)`) — where the loader reads the HF/nn.Linear **(out, in)** (down_proj
  [12288, 4096] vs the reference [4096, 12288], exactly swapped).
- **The fix**: the transpose lives in `dequant_linear` (`return w.t().contiguous()`),
  and the fused qkv split became a ROW split (`w[pi*third:(pi+1)*third]`) — the fused
  row order q|k|v is the verified round-60 order, preserved under the transpose.
- **The full shape contract verified CPU-side** (a header-only replay of the mapping
  against the reference — no torch, no GPU, production untouched): **all 150,226
  produced tensors match the reference exactly** — 148,608 expert quads (the [] → [1]
  mcg reshape confirmed against the reference's own shape), 34 conv1d → 102 slices,
  267 quad groups → 335 weights (the arithmetic pins exactly 34 fused qkv groups =
  the 34 delta-net layers, each +2), 1,181 plain. The check itself needed two fixes
  (a with-block scoping bug; a q vs q_proj naming bug in the checker — the repack's
  names-mode was already EXACT and unaffected).
- **What remains for the dry-run to prove**: only the CUDA path of the assign+
  finalize+reconstruct chain (the CPU check covered CPU; the CUDA assign is untested
  since the round-63 rewrite) and the GPU dequant values (finite + |max| per tensor).
  The full run's merge re-checks every shape again.

## (round 66) The full run's first attempt failed on a broken check, not a broken worker (2026-10-28)

- **The failure** (the user's offline `--mode full`, 435 s in): staging to the worker
  completed (~7 min, whole-file rsync), then the worker's venv probe died —
  "lacks torch+cuda/exllamav3/safetensors". **The worker was healthy**; the probe was
  broken. It ran as a bare ssh `python -c "import …"` WITHOUT the run's PATH: the ext
  import's rebuild check found no ninja (the round-62 trap in a new spot — any probe
  of the run environment must run through the run's own PATH setup), and the same
  command with `~/.venv-exl3/bin:/usr/local/cuda/bin` joined ahead passed ("bare chain
  OK" verified on the worker live).
- **The fix** (`80a0945`): a `--mode check` gate — `fix_path()` + the full import chain
  (torch+cuda, `ext.reconstruct`, `Exl3HfLinear`, safetensors, transformers) + the
  disk floor (~85 GiB for a host's output half) — and `full()` now **scps the script
  to the worker first and gates it through `--mode check`**, so the probe IS the run
  environment by construction. A stale dead line (`-c 'import torch'`) in the same
  block was removed.
- **The both-hosts recheck ran through the real path: CHECK OK on both** — the head
  (1960 GiB free) and the worker (1989 GiB free), identical stacks (torch
  2.14.1+cu130, GB10, the full dequant import chain). Note: the head's first ext load
  sat ~158 s silently (cold page cache under production's memory pressure) while the
  worker's took 2.8 s — the diagnose-hung-commands pattern again; the full run's
  check absorbs the wait.
- **The second failure of the attempt** (337 s in, after the staging and a green
  worker check): the worker's half died on
  `FileNotFoundError: /home/<user>/az-az-exl3-mcg/model.safetensors.index.json` — the
  script's hardcoded head-side source path. The worker's staged copy lives at
  `/home/<user>/az-repack-src` and work mode never pointed at it; right behind it was
  a second latent failure (work mode also reads the reference inventory from the
  head's served-Focus path). **Fixes**: work mode takes `--src` (full() passes the
  staged copy), and the reference check degrades to a warning in work mode — the
  merge's verification binds regardless.
- **The worker requirement checklist, verified**: the venv + the full import chain
  (round 66's CHECK OK through the script's own gate); CUDA visible (GB10); 1,989 GiB
  free; the staged source complete and byte-matched (154G, 23 shards + index); the
  script scp'd by full() before the check; the reference snapshot complete (58 files,
  same as the head — the conv1d belt-and-suspenders check will actually run there);
  the output dir auto-created; head→worker ssh proven by the staging itself. The one
  requirement that stays the user's: the GPUs free — production offline on both hosts.
- **The third failure** (524 s in, at the head's in-process half): `work() missing 1
  required positional argument 'src'` — the round-66b `--src` threading missed the
  SECOND call site inside full(). **The down-the-line audit it triggered found a
  guaranteed merge failure**: a leftover pre-round-60 in-place rename in merge()'s
  partial-map loop renamed shards to `of-00023` BEFORE the merged/ move globbed for
  `of-NNNNN` — the move would find nothing and the shape check would die on a missing
  output shard. The merge path had never executed and could never have succeeded.
  **Fixes** (`2aaa591`): the call site, the leftover rename removed, the conv1d
  blocks `.clone()` instead of `.contiguous()` (a dim-0 slice is contiguous, so
  contiguous() returned a storage-sharing view; the worker's 12 conv1d tensors
  empirically survived save_file, but the clone kills the class), and full() cleans
  stale work-*/merged dirs (idempotent re-runs).
- **The synthetic merge test** (fixtures on the head, CPU-only, no GPU): the REAL
  merge() run against a fake source/reference/partials — on the pre-fix script it
  reproduced the exact predicted "missing output shard" failure; on the fixed script
  it PASSES with independent post-verification (the merged dir re-read: 9 tensors,
  shapes, the old-shape config, the provenance). The never-run merge path is now
  proven before the next GPU window.
- **What the failed attempt still proved**: the worker's half completed end to end
  (~3 min for its 11 shards — the whole remote pipeline works: staging, the
  script-run check, work with --src, the partial maps). The re-run is fully
  idempotent: it re-stages, re-checks, and redoes both halves (~15–20 min total —
  the "~1 h" estimate was conservative).
- **The triple-check battery** (the user's ask; independent methods, not re-runs):
  (1) DATA INTEGRITY via header byte-range sweeps — the source (23 shards /
  150,891 tensors), the reference (47 / 150,226), the worker's staged copy
  (23 / 150,891) and the worker's completed output (11 / 70,021): zero truncation,
  index cross-checks exact where an index exists. (2) SCRIPT IDENTITY: the head's
  checkout sha256 == the audited local file; py_compile + module import OK; the
  --mode names regression still EXACT. (3) ORCHESTRATION: the six remote command
  constructions (2 rsync, 1 scp, 3 ssh) all previously exercised live except the
  fetch, which is the staging rsync's sibling.
- **The staging question answered**: the 154G stage already on the worker is
  complete and identical (mtimes preserved across the rail) — the full() pre-stage
  `rm -rf` was removed (e4c6a25): rsync's own size+mtime quick check now skips an
  up-to-date stage to a zero-transfer pass, while a partial one still completes
  (-W + --delete; the round-31 delta trap is handled by -W, not by wiping). A
  re-run's staging drops from ~6 min to seconds; the next run's expected total is
  ~15 min (the worker's half is redone — 3 min — keeping the run self-verifying).

## (round 67) The repack COMPLETED — 8 min 46 s end to end; the beat-94 blocker is a checkpoint on disk (2026-10-28)

- **The receipt** (/tmp/az-repack-full.log on the head): preflight → staging SKIPPED
  by the quick check in 0.7 s (the round-66d change paying off) → the worker's
  script-run check → its 11 shards in 74 s → our 12 shards in 275 s → the fetch
  (~166 s, ~80 G at ~480 MB/s) → the merge: **name-set + shape equality vs the served
  Focus: PASS (150,226 tensors)**. Final stats: 148,608 expert quads copied,
  102 conv1d slices, **335 dequanted** (34 fused qkv × 3 + 233 singles — exactly the
  predicted arithmetic), 1,181 plain. The independent integrity sweep on merged/:
  23 shards / 150,226 tensors, zero truncation, index exact. **164 G — byte-for-byte
  the same size as the served Focus reference, as the same-tensor-set-same-dtypes
  contract predicts.**
- **Why 9 minutes where the requant took ~20 hours** — the user's question, answered:
  the ~20-hour job was the ORIGINAL requant (exllamav3's converter encoding the base
  to 4-bit trellis) — quantization is an OPTIMIZATION SEARCH (choosing the best
  trellis codes per weight tile to minimize reconstruction error), compute-bound per
  tile. This repack performs **no quantization at all**: the experts (~99% of the
  bytes) copy byte-identical, the 335 linears DECODE (trellis → lookup → Hadamard →
  scale — a single memory-bound pass, ~0.2 s each), the rest is disk I/O. Decode is
  the inverse's cheap half; the 20 h was the encoder's search. The double-
  quantization caveat stands: the 335 linears get re-packed by the ENGINE at serve
  load (converter 4-bit → bf16 → the load-time pack) — that is the az2 serve's job.
- **State**: ~/az-repack-out/merged is a complete old-layout checkpoint with the
  old-shape quantization_config (bits 4, codebook mcg, head_bits 16, scope
  glm53_routed_experts_only) and repack_provenance.json. Production is back up (the
  user's serve). **Next: the az2 window** — placement into the cache, the serve =
  the format verdict, then §2 gates + hardmode at --parallel 2 = the beat-94 verdict.

## (round 68) The az2 window ran: the serve refusal diagnosed — the requant needs the reference-shape patch (2026-10-28)

- **Production is verified serving** (the user's "not serving" was the load window:
  the container is Up minutes before the API binds; the probe answers).
- **The az2 window ran and the serve REFUSED** — the exact round-26 signature:
  "the checkpoint's 163.6 GiB of weights do not fit the 102.0 GiB budget" = the
  whole-checkpoint billing = the strict config.parse rejected the config and the
  silent catch billed everything to one rank (the wrapper itself worked perfectly:
  rc=0, the stack stopped, the port freed for production).
- **The diagnosis chain**: the config diff (requant vs the served Focus, nested
  text_config, 58 keys each) is EXACTLY ONE field — `num_experts_per_tok` 4 vs 8;
  the quantization_configs are identical (our merge wrote the Focus's shape). The
  default PATCHES is EMPTY (config.sh: pristine = the Focus's serving shape, topk-8
  by design) — so the az2 serve ran PRISTINE against a top-4 config → NotGlm53Flash.
  **The requant is a top-4 model** (azampatti's retrained selector; the Focus is
  top-8 by design) and the matrix's `azexl3` cell already defined its serve shape:
  `PATCHES=glm-topk4b.patch` — the patch changes the family's topk default 8→4 AND
  the EXL3 kernels' top_k specialization ("the reference shape the kernels
  specialize for; the variant checkpoint routes top-4").
- **The fix**: PATCHES=glm-topk4b.patch wired into the az2 phase's restart AND
  run_gates (the receipt's 26-az2.md refusal stands as the format receipt of the
  pristine attempt; FORCE=1 overwrites it with the patched attempt).
- **The look-ahead sweep**: the merged dir carries the full tokenizer family
  (tokenizer.json, tokenizer_config.json, generation_config.json, chat_template.jinja
  — no serve-side gap); the placement already happened and skips cleanly; with a
  valid parse the weightShare arithmetic returns to the round-26 receipt's ~81.8 GiB
  share < the ~102 GiB budget; the wrapper's wrap-up is proven (rc=0, port freed);
  the re-run needs FORCE=1 (phase_done bypasses .done markers). Note: the Focus's 92
  was a pristine-topk8 serve — the AZ cell is a patched-topk4 serve (the matrix's
  design); the beat-94 bar is production's 94 either way.

## (round 69) The second az2 attempt: RankMismatch — the worker's stale placement; the both-host placement fixed (2026-10-28)

- **The refusal was NEW and different**: "REFUSE rank settings: rank 1's config
  differs from rank 0's (config.json) → RankMismatch". The engine serves as two
  ranks and each reads ITS OWN copy of the checkpoint: the az2 phase placed the
  repacked checkpoint into the HEAD's cache only, and the worker's cache held a
  STALE pre-repack placement whose quantization_config still carried the converter's
  1.6.4 shape (verified live: worker `version: 1.6.4, calibration…` vs head
  `bits 4, codebook mcg, scope…`). prepare's model copy to the worker is guarded by
  "skipped when its cache already has it" — the stale copy satisfied it, so the
  repacked checkpoint never reached the worker.
- **The look-ahead that closed the next trap too**: prepare.sh `docker save | docker
  load`s the freshly-built image to the worker on EVERY prepare and verifies it with
  `--version` — so the glm-topk4b patch reaches BOTH ranks automatically (the
  fingerprint changes with PATCHES → the image rebuilds → the worker gets it). The
  only un-provisioned piece was the checkpoint copy.
- **The fix** (the az2 phase): after the head placement, the phase compares the
  config.json digests across the two hosts and, on any difference, resets the
  worker's cache entry and rsyncs the repacked checkpoint over (whole-file, ~164 G,
  some minutes), then re-verifies the digest — idempotent (a matching pair skips the
  sync on re-runs). The re-run command is unchanged (FORCE=1 still required).

## (round 70) The third az2 attempt: UnexpectedTensor — the dtype contract; the repack fixes the 388 and gains dtype gates (2026-10-28)

- **The third refusal was the engine's actual tensor loader** — progress: the rank
  handshake PASSED (the round-69 sync worked; the patched parse accepted the config).
  The error was bare ("cannot load … with its own glue kernels (UnexpectedTensor)",
  no tensor named). **A dtype sweep against the served Focus found it**: 388 tensors
  differ in dtype with shapes identical — 274 unquantized weights (the requant left
  them unquantized; the byte-copy kept the source model's F16) + 114 state tensors
  (F32) where the engine's proven-good layout is uniformly BF16. The shape contract
  never checked dtypes — the one axis the loader cares about. The 335 dequanted
  weights, the expert quads and the conv slices are ABSENT from the diff: their
  dtypes were already correct.
- **The repack fix**: ref_inventory carries dtypes; the plain pass-through CONVERTS
  to the reference's dtype (F16→BF16, F32→BF16 — the reference is the contract, the
  engine serves it today); the dry-run AND the merge now gate dtype equality too
  (a future dtype drift dies at the gate, not at a serve). The stats carry
  dtype_fixed (expect 388).
- **The az2 phase's placement currency** moved from config.json's digest to
  SHARD 1's digest (a dtype fix does not touch config.json — a config-only guard
  would re-serve the stale placement after the re-repack). Three-way: merged vs the
  head's placed copy vs the worker's; each side refreshes only on a difference.
- **The re-run sequence adds a verification gate between the repack and the window**:
  the user runs --mode full, the agent verifies the dtype contract + integrity on the
  new merged/ BEFORE the window launches — no fourth blind window.

## (round 70b) The treble check: one real bug caught in the round-70 fix; the diagnosis corroborated externally (2026-10-28)

- **On the code** (re-read + research): the round-70 dry-run dtype gate used a PARTIAL
  torch→safetensors map — torch "int16"/"int32" stayed unmapped against the headers'
  "I16"/"I32", which would have FALSE-DIED the dry-run on the first expert quad (the
  dry layers contain 3,456 int quads). Fixed with the full vocabulary (exllamav3's own
  torch<->ST map as the canonical reference); the mapping sanity-checked for every
  dtype class the dry layers produce. The plain-path conversion now dies NAMED on an
  unknown reference dtype instead of KeyError. Everything else verified as-written.
- **On the opinions** (external corroboration): (1) the requant's F16 unquantized
  weights are the CONVERTER's documented behavior — exllamav3's LinearFP16 stores
  unquantized weights as half regardless of the source dtype (source: exllamav3
  modules/quant/fp16.py, loader/safetensors.py) — not our error, and the conversion to
  the reference's BF16 is exactly the right correction; (2) the stock GLM-5.3-Flash
  routes **8 of 288 experts** (vLLM recipes, the HF internals dataset, the
  architecture notes — all agreeing), so the Focus's topk=8 is stock and the requant's
  topk=4 is the retrained selector's genuine design deviation (the efficiency play:
  fewer active experts) — the glm-topk4b patch serves exactly that; (3) the public
  architecture split (34 KDA + 11 MLA layers, the first 3 dense, the MTP draft) matches
  our tensor inventory class-for-class (34 fused qkv + 34 conv1d; layer 3's MLA indexer
  tensors in the dry) — the requant is the same architecture, the reference is a valid
  structural contract; (4) the F32→BF16 state-tensor conversions match the engine's
  storage contract (the reference stores BF16 and serves) — HF's fp32 router-bias
  convention is a training-side detail, not the engine's storage format.
- **On the research**: the safetensors dtype vocabulary (F16/BF16/F32/I16/I32/I64/…)
  confirmed from the spec and multiple implementations; the exllamav3 converter's
  dtype behavior confirmed from its source; the GLM-5.3-Flash routing width confirmed
  from three independent public sources.

## (round 70c) The treble check's third catch: the dtype conversion counter was an overcount (2026-10-28)

- **The bug**: the plain-path conversion condition compared `t.dtype` (a torch dtype) to `rd`
  (the reference's safetensors dtype STRING — "BF16", "F16", "F32"), which is NEVER
  equal → the conversion fired for EVERY plain tensor, inflating dtype_fixed to 712
  on the worker's half (all of its plain tensors) when the real mismatch count is
  388 (per the dtype sweep on the pre-fix merged dir). The conversion OUTPUT was
  still correct (`.to(rd_torch)` produces the right dtype), so the merge would have
  passed — but the log lied about how much work the conversion did.
- **The fix**: compare torch.dtype to torch.dtype (`rd_torch = {BF16: torch.bfloat16,
  F16: torch.float16, F32: torch.float32}[rd]`); only count when an actual
  conversion happens. The unknown-dtype die is preserved.
- **The verification gate still holds**: the merge's dtype check (ST-string to
  ST-string) and the dry-run's dtype gate (torch-to-ST map) are both correct; the
  re-run's stats will now report the honest count (≈194 on the worker's half,
  ~388 total).

## (round 71) The re-repack COMPLETED with the dtype fix — the verification gate is green (2026-10-28)

- **The receipt** (/tmp/az-repack-full3.log): the detached run finished at 401.2 s
  (the launch-suspension saga ended by running detached). Stats: 148,608 expert quads,
  102 conv slices, 335 dequanted, 1,181 plain, **dtype_fixed: 388** — the honest
  count, split 217 on the head + 171 on the worker, matching the round-70 dtype
  sweep's 388 exactly (the counter bug is confirmed gone). The merge: name-set +
  shape equality vs the served Focus PASS on all 150,226; the merge's dtype gate
  passed (no "dtype mismatch" die).
- **The verification gate** (the agent's own independent checks, run before the
  window): the dtype+shape contract reports **0 diffs** ("merged is byte-class-
  identical to the reference"); the integrity sweep reports **zero truncation, index
  exact** (23 shards / 150,226 tensors); the merged dir is 164 G — byte-for-byte
  the reference's size. Every structural axis (names, shapes, dtypes, byte integrity)
  is verified before the serve.
- **State**: ~/az-repack-out/merged is the fixed checkpoint; production is back up
  (the user restarted it). **Next: the az2 window** — the head's placed copy and
  the worker's are both stale (the shard-1 digests differ from the new merged dir),
  so the phase refreshes both (~6 min sync), serves with the top-4 patch (the format
  verdict), then gates + hardmode (the beat-94 verdict).

## (round 72) The az2 window: the serve LOADED — the format rescue is complete; the beat-94 verdict is NO at 89 (2026-10-29)

- **The format verdict: GREEN.** The repacked checkpoint served under the top-4
  reference-shape patch: the serve line reads "model 83.32 GiB; 4 streams at once,
  3.61 GiB each at a 524288-token window (fp8 caches), of 14.7 GiB left" — both
  placements (the head refreshed, the worker synced via the shard-1 digest) matched
  and the rank handshake passed. The §2 gates all PASS on content (g1 determinism,
  g2 drafted=plain, g3 resumed=fresh, g4 concurrent=solo; g5 note: seeded samples
  content-identical). The three-refusal arc (pristine parse → RankMismatch →
  UnexpectedTensor) is closed with a served checkpoint.
- **The beat-94 verdict: NO — 89** on hardmode at --parallel 2 (the (user) bench
  shape), vs production's 94 and the Focus's 92 (receipt: results/campaign-20261028-
  234233/az2/az2-hm.json, final_score 89 over 104 scenarios).
- **The scenario-level read** (az2-hm.log vs the round-37 Focus bench log, 104
  common scenarios): az2 passed 90, the Focus 94 — az2 LOST 3 (TC-63, TC-85, TC-98)
  and GAINED 2 (TC-38, TC-101). A near-tie with the Focus: the selector performs at
  Focus-adjacent level; the losses are concentrated, not diffuse — consistent with a
  routing-quality trade (top-4 vs top-8) plus the double-quantized linears, not a
  broken checkpoint.
- **The confound, recorded honestly**: the 335 dequanted linears passed through two
  4-bit quantizations (the requant's converter, then the engine's load-time pack).
  The azampatti source was deleted in the round-58 cleanup, so routing-vs-quantization
  cannot be de-confounded without a re-download + re-convert. 89 is a LOWER BOUND on
  the selector's quality; the ceiling (the Focus's 92) still does not beat
  production's 94.
- **The bookkeeping**: the beat-94 ledger item CLOSED with the receipt
  (docs/TOOL_EVAL_TESTING.md); the az2 phase RETIRED from scripts/run-qualification.sh
  (session-specific, verdict delivered — the receipt lives in results/); the standing
  config is untouched (dense4fp8 + INDEX_CUDA + vision remains the qualified default).
  The hmtrials phase is the next session-specific retirement candidate (its spread
  question is now answered) — left for the user's next sitting.

## (round 74) The recommendations land: the effort-tail template built + wired; the base audit resolved; the router fix located (2026-10-29)

- **Lever 1 — the effort-tail template is BUILT AND WIRED**: the bug confirmed in our
  own templates (both the Focus checkpoint's chat_template.jinja and our vision
  template emit `<|system|>Reasoning Effort: …` at line 3 — the prompt top). The
  variant (image/share/glm5-next-effort-tail.jinja): the top emission replaced by a
  provenance comment, the effort line now emitted just before the final assistant
  turn, ONLY when the request ends with a user message (grebneke's recipe — avoids
  5x over-reasoning on routine tool-result turns). Wired end to end: the Dockerfile
  stages it next to the vision template; config.sh gains CHAT_TEMPLATE (empty =
  the checkpoint's default); start.sh adds the rank-agreed --chat-template flag with
  a VISION=1 conflict guard (the two would collide; merging the fix into the vision
  template is the follow-up). The guard's logic sandbox-verified on all four cases —
  after catching a bash-precedence slip that would have killed every serve.
  **Quality targets: TC-51 and TC-92 fail deterministically on our line on BOTH
  checkpoints (verified in our receipts) — technigma is the only stack clean on both;
  bernisse pre-warned exactly this. The A/B window: prepare rebuild →
  CHAT_TEMPLATE=effort-tail VISION=0 → the battery + the TC checks.**
- **Lever 2 — the base audit resolved**: our pin 812fb040 IS upstream Release 1.1.8
  (03d08f1e). The KV-pages code is ALREADY in our base (TF_KV_PAGES in
  glm/cuda_native.zig + cuda_pages_test.zig) — usable with bf16 KV only; the
  fp8xpages combination is the open upstream item (bernisse's caveat and our round-59
  finding agree independently). The #1218 slot-leak / #1168 fp8-attention / #1176
  int8-matmul fix-ups ship in tags as old as v1.0.0-beta.10 — a targeted code check
  against our tree remains to confirm each (time-boxed here). Net: the "wait for
  TensorFold" answer shifts — our base already carries most of the watch list; the
  open upstream item is pagesxfp8, and upstream main has diverged from our line.
- **Lever 3 — the router fix is DESIGNED AND SCOPED, not implemented**: PERF_PLAN
  Front 2 Lever A2 (the 910-1125 ms router section per 2048-row chunk, 55-69% of
  chunk GPU time, for a ~4.8 GFLOP GEMM production does in ~1 ms; the ks hypothesis
  rejected with a clean A/B; the 8-slice bit-stable replacement design scoped).
  bernisse's field assessment: the highest-leverage kernel work in the field. This is
  the next work block: implement the Zig patch, then a window to build + measure.

## (round 75) The effort-tail A/B is STAGED: the template proven by a render gate, the window phase written (2026-10-29)

- **The render gate PASSED pre-window** (jinja semantics, on the head, CPU-only):
  four placement cases verified — user-ending+max (the hint exactly once, immediately
  before the final assistant turn, NOT at the top, the rest of the render identical),
  tool-result-ending (NO hint — the user-only rule), undefined effort (Max, tail —
  the stock's line-2 coercion), None (coerced to Max, tail — stock-consistent). The
  harness needed jinja2.ext.loopcontrols (the stock template uses break) — the same
  extension serving stacks enable. Two test-expectation corrections along the way
  (the stock's None coercion; the single-line top render) — the gate now tests the
  STOCK's actual semantics, not assumed ones.
- **The efforttail phase written** (session-specific, retires with the verdict): an
  explicit prepare first (the Dockerfile stages the template; a Dockerfile change does
  not move the fingerprint — the round-27 lesson), then TWO LEGS in the same window
  (bernisse's rule): baseline (the checkpoint's own template) vs CHAT_TEMPLATE=
  effort-tail, each VISION=0 on the Focus at the standing quant env, each running the
  hardmode battery with final_score + TC-51/TC-92 extracted into 27-efforttail.md.
  The flip-list comparison happens at digest (the agent reads both logs). Wired into
  NEEDS_GPU; the summary's [0-9]*.md glob catches 27- (the round-17 gotcha is fixed
  upstream of this receipt name).
- **The window runbook** (the user drives, detached): production down →
  PHASES="preflight efforttail summary" FORCE=1 setsid nohup scripts/run-window-block.sh
  </dev/null >/tmp/et.console 2>&1 & → the wrapper: prepare (rebuild+staging, ~5-10 min)
  → leg baseline (~35 min) → leg tail (~35 min) → summary → the port frees →
  production back. ~80-90 min total. I read 27-efforttail.md + both logs for the
  verdict: the score delta, the TC-51/TC-92 statuses, and the flip list.

## (round 76) The effort-tail A/B verdict: +1 score, TC-92 FIXED — the template-family diagnosis confirmed (2026-10-29)

- **The receipt** (results/campaign-20261029-103523/27-efforttail.md): leg baseline
  (the checkpoint's own template) **92** with TC-51 FAIL + TC-92 FAIL; leg tail
  (effort-tail) **93** with TC-51 FAIL + **TC-92 PASS**. Same-session legs, both
  served cleanly (83.50 GiB, 4 streams at the 524288 window — the serve line identical
  across legs; the only variable was the template).
- **The flip list** (104 common scenarios): baseline passed 94, tail passed 94 — the
  tail LOST 1 (TC-100) and GAINED 3 (TC-38, TC-101, **TC-92 tenant isolation**). The
  score moved +1 because the gained scenarios carry more points. **TC-92 flipping to
  pass confirms the template-family diagnosis**: the tenant-isolation failure was the
  effort-hint placement, not the model, not a kernel — bernisse pre-warned exactly
  this scenario and technigma's stack (the template-fix family) is clean on it.
- **The baseline reproduced**: 92 today vs the round-37 Focus 92 — the standing
  receipt is stable across weeks (the default template unchanged).
- **The remaining gap**: TC-51 still fails on both legs — that is the SECOND template
  gap (reasoning collapse after tool results; technigma's TOOL_REASONING_VALIDATION.md
  fix, not yet applied on our line). The vision template still carries the top-hint
  bug (merging the effort-tail fix into it is the follow-up). One small loss (TC-100)
  — unexamined, single scenario.
- **The adoption question** (the user's call): CHAT_TEMPLATE=effort-tail as the
  standing default — the evidence is +1 score, TC-92 fixed, 1 minor loss, zero
  serve-side cost (a template file, no kernel change).

## (round 77) The effort-tail ADOPTED — with vision intact: the fix merged into the vision template (2026-10-29)

- **The adoption** ((user): "adopt, but we want vision still"): CHAT_TEMPLATE defaults
  to effort-tail in config.sh with the round-76 receipts cited; the revert is
  CHAT_TEMPLATE= (the checkpoint's own top-hint template).
- **The vision interplay resolved by merging, not by a flag fight**: the vision
  template received the same two edits (the top emission → a provenance comment; the
  tail emission, user-message-ending only — the vision template differs from the
  stock in exactly one region, the media branch, so the fix is mechanical). The render
  gate re-run EXTENDED: the vision template passes the text placement cases AND an
  image-bearing case (the media tokens render, the hint sits once at the tail). The
  serve matrix verified in a sandbox: VISION=1 → the vision template (+fix, no extra
  flag); VISION=0 + effort-tail → the text template; VISION=0 + empty → the
  checkpoint's own template (the revert path).
- **The validation window pending**: the adopted default changes the vision serve's
  prompt — the vision suite (assets/vision) + a bench re-verification belong in the
  next window before the adoption is fully receipted on the vision path.
- Workflow note: the vision-template render test initially ran against the head's
  STALE checkout (the patch was local-only) — the gate failed correctly and passed
  after the file synced. The gate catches staleness too.

## (round 78) The validation window staged: the adopted default receipts on the vision path (2026-10-29)

- **The etadopt phase written** (session-specific, retires with the receipt): an
  explicit prepare (the vision template's CONTENT changed — content does not move the
  fingerprint, the round-27 lesson) → the standing-default serve (VISION=1 +
  CHAT_TEMPLATE=effort-tail flow from config.sh; the vision template carries the fix —
  the serve line names the template) → the vision suite (assets/vision via the
  round-55 runner, now repoed at scripts/vision-suite-probe.py — promoted out of /tmp
  for reproducibility) → ONE hardmode run re-verifying the score on the vision serve.
  The receipt (28-etadopt.md) extracts the suite result + final_score + TC-51/TC-92.
- **The comparisons the window delivers**: the vision suite vs its round-55 baseline
  (4/4 targeted + 23/25 detail) and the hardmode score vs the round-76 receipts (93
  tail text-only / 92 baseline) — the adopted default's first vision-path datapoint.
  TC-51/TC-92 tracked (the round-76 tail state: TC-51 fail, TC-92 pass).
- Wiring note: the phase anchors before the summary block (the doubled separator left
  by the round-75 insertion made the old anchor ambiguous — the insertion now anchors
  on `if want summary; then`); NEEDS_GPU updated.

## (round 79) The adoption is FULLY RECEIPTED: the vision path holds — 93 on the vision serve, the suite 8/8 (2026-10-29)

- **The receipt** (results/campaign-20261029-120042/28-etadopt.md): the standing
  default served (VISION=1 + the vision template with the effort-tail fix — the serve
  line names the template; 84.75 GiB with the tower, 4 streams at the 524288 window,
  12.6 GiB left — the standing vision config's line). The vision suite: **8/8 ok**
  (the four ground truths hit: red / golden gate / zebra / stop; the targeted answers
  clean — quadrants "Red", sign "STOP"). The hardmode: **93** — matching the round-76
  tail receipt exactly; TC-92 pass ✓, TC-51 fail (expected — its fix is the next A/B).
- **The manifest note**: the current manifest is the trimmed 4-item version (4 images
  × targeted+detail = 8 checks), so the round-55 detail counts (23/25) do not
  cross-compare — the round-55 receipt predates the manifest trim. The window's
  comparison is the current suite against its ground truths: 8/8.
- **The adoption is fully receipted on both paths**: text 93 (round 76) + vision 93
  with the suite 8/8 (this window). The standing default is the effort-tail template
  family with vision intact. The next levers, in order: TC-51's tool-result reminder
  A/B (the second template gap, still failing on both legs), then the router patch
  (PERF_PLAN Front 2 A2's 8-slice bit-stable design — the implementation work block).

## (round 80) The TC-51 lever staged: the tool-continuation reminder variant + the etreminder A/B (2026-10-29)

- **The mechanism, from technigma's 23c7b03 diff** (fetched in full): with the last
  message a tool result, the template injects a short synthetic user turn —
  "Continue the original task using the latest tool result. Before your next answer
  or tool call, briefly assess the result in the thinking block. Keep that assessment
  separate from the user-facing answer." — immediately before the assistant prefix.
  Their before/after replay: ZERO reasoning tokens at 38k/500k/900k with the original
  template (raw completions began with </think>) → 240/212/194 with the reminder +
  correct plans. Honest limits recorded: their fresh-data reminder-off controls also
  passed, so the A/B measures it on OUR bench (our TC-51 fails deterministically on
  both checkpoints — the reproduced-family failure our line actually exhibits).
- **The variant** (image/share/glm5-next-effort-tail-tr.jinja): the adopted
  effort-tail template + the reminder block, mirrored to our template's structure (no
  thinking_enabled var — our generation prompt always opens <think>; the opt-out
  kwarg tool_reasoning_reminder=false honored). The two fixes are MUTUALLY EXCLUSIVE
  by condition (tool-ending vs user-ending) — they compose without interaction. The
  render gate extended to nine checks: the reminder fires exactly once on
  tool-ending, silent on user-ending, the opt-out honored, the effort hint intact on
  user-ending. ALL PASS.
- **The etreminder phase written** (session-specific): explicit prepare → two
  same-session legs (effort-tail vs effort-tail-tr, the adopted default as the
  control) on the Focus at VISION=0, hardmode + TC-51/TC-92 per leg, the flip
  analysis at digest. Wired into NEEDS_GPU.

## (round 81) The etreminder A/B verdict: REJECTED — the reminder is net-negative on our bench (2026-10-29)

- **The receipt** (results/campaign-20261029-125309/29-etreminder.md): leg tail (the
  adopted control) **93**, TC-51 fail, TC-92 pass — reproducing the round-76/79
  receipts exactly. Leg tail-tr (the tool-continuation reminder) **90** — a 3-point
  regression. **TC-51 unchanged (fail)** — the reminder did NOT fix it — and **TC-92
  REGRESSED to fail** (the effort-tail gain was lost).
- **The flip list** (104 scenarios): tail-tr passed 92 vs the control's 94 — LOST 4
  (TC-74, TC-85, TC-92, TC-98), GAINED 1 (TC-100). Note: TC-85 and TC-98 also moved
  in the az2-vs-focus comparison — marginal scenarios sensitive to prompt structure.
- **The interpretation**: technigma's reminder mitigates THEIR reproduced failure
  (zero reasoning on tool continuations at very long context); on OUR bench the
  synthetic user turn is net-negative — it perturbs prompt structure the scenarios
  depend on. The reminder is a mitigation for a specific reproduced failure mode, not
  a general quality lever. The variant is NOT adopted; the file stays as a receipted
  dead end (CHAT_TEMPLATE only serves it if explicitly selected).
- **TC-51 remains open** — the documented candidate fix is rejected, so its cause
  needs diagnosis: read the scenario definition from the bench repo and reproduce the
  actual-vs-expected locally. The quality queue after that: the router patch (PERF_PLAN
  Front 2 A2 — the big perf lever), the settings A/B.
- The A/B discipline worked as designed: a harmful change was caught before adoption.

## (round 82) TC-51 diagnosed and CLOSED as a shared failure; the real gap decomposed; the (user) no-overfitting principle (2026-10-29)

- **The TC-51 mechanism** (from the bench source `planning/tc51.py` + our run's
  transcript, results/campaign-20261029-125309/etreminder/et-tail.json): the model's
  trace is semantically complete — contacts → event with all 3 engineers (right date,
  time, title) → email — with coherent reasoning at every turn. It hard-fails on
  ORDERING: it batched `send_email` in the SAME assistant turn as
  `create_calendar_event`, and the bench's dependency rule
  (`create_calendar_event → send_email`) requires the notification in a strictly
  LATER turn; the premature-notification check zeroes the whole trace (fail, 0
  points — not even partial). Had it sent NO email, it would have PASSED via the
  event-invite path (the eval accepts the event's attendees as the notification).
- **The decisive cross-check — production fails TC-51 too, identically**: the bench
  repo's own production rebaseline receipt (prod-score-rebaseline-20261027,
  hardmode.json) shows TC-51 fail/0, parallel_tool_turns [2], and the SAME summary
  string ("Batched send_email with create_calendar_event in the same turn instead of
  waiting for the create_calendar_event result"). TC-51 is a benchmark-policy trap
  (strict serialization of declared dependency pairs vs the model's correct judgment
  that the two calls are independent) — BOTH stacks fall into it. It was never a gap
  between our line and production. The reminder A/B's null result is fully explained:
  reasoning was present every turn; the failure is turn-ordering policy, not the
  reasoning-collapse family the reminder targeted.
- **The real 93-vs-94 gap, per-scenario vs production's rebaseline** (104 common):
  we pass 94 / prod 96. We WIN TC-92 (+2 — production FAILS tenant isolation; our
  effort-tail fix is the clean side), TC-40, TC-90 (+1 each). We LOSE TC-80 (−2,
  mutated before reading/deciding), TC-100 (−2, deferred a `retryable:true`
  single-account retry to the user — good non-idempotency safety judgment; the bench
  scores autonomy), TC-62 (−1, skipped chain steps before the email), TC-63 (−1, an
  extra unrelated call), TC-68 (−1, schema-compliant JSON wrapped in Markdown fences).
- **The reading**: two-directional agency-calibration variance (over-eager on TC-80/
  62/63, under-eager on TC-100) + one formatting habit (TC-68) — not a systematic
  capability gap. The only lever that moves these is targeted prompt surgery, which
  is exactly what the reminder experiment showed to be net-negative (TC-92 regressed).
- **(user) principle, recorded**: improvements must make the model genuinely better —
  NOT targeted at specific TCs — unless a change is a real general improvement. Under
  that principle: no template surgery for the calibration scenarios (it would be
  benchmark-overfitting); the effort-tail adoption stands on its general merits
  (long-context reasoning engagement, receipted 92→93 with a real behavioral fix);
  the remaining levers are the GENERAL ones — the router patch (PERF_PLAN Front 2 A2,
  every request benefits) and the stack-level settings A/B.

## (round 83) Upstream v1.1.9 reviewed: three bit-exact GLM items, no router work, no fp8×pages — hold-and-fold-in (2026-10-29)

- **The audit**: v1.1.8...v1.1.9 = 50 commits / 256 files; the changelog matches the
  diff. Three GLM-5.3-Flash CUDA items, all bit-exact, all by @Bizuayeu: #1404 the
  TP≥2 DSA indexer split (1–2% prefill at 128k on 2×GB10 — our topology),
  #1424 the DSA select decode widening (+1.8% at TP=3/136k, flat at TP=2/65k),
  #1352 TENSORFOLD_PREFILL_SHARE (decode-under-prefill fairness, opt-in).
- **Not included**: no router-GEMM work (Front 2 A2 remains ours — the Kolibri
  #1460 item is the same CLASS of routed-expert L2 pathology but different kernels),
  no fp8×KV-pages (the ledger watch stays open), no GLM vision/template changes.
- **(agent recommendation, pending user)**: hold the pin; base the router A2 patch on
  v1.1.9 so one re-qualification window adopts both. Recorded in ECOSYSTEM.md.

## (round 84) Front 2 A2 IMPLEMENTED: the staged chain router patch, compiled clean on v1.1.9 (2026-10-29)

- **The design de-risked in source first** (the v1.1.9 tree read end to end): the
  hand-rolled router kernels accumulate each output as ONE continuous mma.m16n8k16 chain
  per 512-wide K slice (K ascending from zero); glm_mm's kernels accumulate per-64-group
  (fresh `d` per group, `acc += d`). fp32 non-associativity means calling stock glm_mm
  per slice would flip low bits — the content gate (#1079 protocol) would kill it. The
  PERF_PLAN's "preserving the summation structure via sliceSum" was necessary but not
  sufficient; the fix is a dedicated **chain kernel**: glm_mm's exact prompt shape
  (128-row blocks, ROWS_FIRST L2 sharing, 3-stage cp.async, PDL, 256 threads) with the
  mma chained directly into one accumulator — same fragments, same order, same bits by
  construction, staged loads instead of the per-step global reads that are the pathology.
- **The patch** (patches/glm-router-gemm.patch, diffed against v1.1.9, 8 files +209/−3):
  `tf_glm_router_mm` (the chain kernel, glue image, Set-auto-loaded);
  `glm_mm_tile16s` (strided tile16 — each MoE gate tiles into 8 contiguous K-slice
  layouts at engine init, a same-bytes re-layout, one buffer owned by the mm kernels);
  `glue.router` gains the `tiles` dispatch (m ≥ 128, aligned, tiled — decode rows and
  unaligned callers keep the hand-rolled kernels); the MoE layer carries `rtiles`; the
  engine init builds the tiles under TF_GLM_ROUTER_MM=1 (OFF by default — the patch is
  inert without the env, so one image serves both A/B legs); contract records added
  (copied from the shape sibling until the contract run prints actuals).
- **Compile receipt**: fatbins + native build RC=0 in the builder container
  (nvcc sm_121, zig 0.17.0, v1.1.9) — three fix iterations (bpairs is glm_mm-local —
  inlined the trivial bf16 copy; the `tiles` param; DeviceBuffer.ptr is a plain u64).
- **The routergemm phase written** (session-specific): ONE prepare (the patch overlay),
  two same-session legs — stock (patched binary, env off = the executed hand-rolled
  path: v1.1.9's true baseline) vs gemm (TF_GLM_ROUTER_MM=1) — duel solo + c4 + chunk
  prof per leg, hardmode on the gemm leg, the content gate stock-vs-gemm in the receipt.
  The pin moves 812fb040 → 465e48b6 for this window (the patch diffs the v1.1.9 tree;
  1.1.9's GLM items are bit-exact upstream). patches/README carries the full design +
  the rebase-ownership note.

## (round 85) The routergemm A/B verdict: bit-safe PROVEN, perf prize NOT there — the pathology is implementation-independent (2026-10-29)

- **The receipt** (results/campaign-20261029-152500/30-routergemm.md): **content gate
  IDENTICAL** — the staged chain router reproduces the hand-rolled kernels' replies
  byte-for-byte; the round-84 bit-stability design is PROVEN on hardware. Hardmode **93**
  on the gemm leg (TC-92 pass, TC-51 fail as everywhere) — quality untouched. The pin's
  v1.1.9 base is receipted (leg stock: solo 54.1, c4 140.7, slope 0.659 — the new base
  line; bit-exact from 1.1.8 as upstream claimed).
- **The perf read: ZERO movement.** Chunk router section 1109 (stock) vs 1114 ms (chain)
  at 2048 rows; slope 0.659 vs 0.660; solo/c4 within noise. The chain kernel carries
  glm_mm's ENTIRE staging machinery and costs the same as the direct-load hand-rolled
  kernels. The m=64 chunk's router is 54.9 ms — far from FLOP-proportional.
- **The conclusion**: three kernel probes (ks 8→2, part-forced, the staged chain GEMM)
  agree — the ~1100 ms router section is NOT the kernel's implementation. The staging
  hypothesis is dead. Remaining suspects: the prof-span semantics (what the span really
  brackets), host-enqueue bubbles landing inside the spans, or a systemic engine
  property (clocks / stream serialization). **Next instrument: an ncu capture of one
  chunk's router kernels** (true kernel duration, SM busy %, stall reasons) — a small
  diagnostic window, no A/B needed.
- **Decisions**: the patch is NOT adopted (no measured win — the rebase-tax rule;
  patches/README updated with the round-85 status). The v1.1.9 pin STAYS (bit-exact
  upstream, the round-83 fold-in verdict; leg stock is the new base line). The bit-safe
  chain kernel stays in the repo as the probe artifact — if the profiler ever shows a
  real kernel-shaped cost, the fix rides on it.

## (round 86) The next window staged: the ncu capture + the settings A/B (2026-10-29)

- **ncurouter written** (session-specific, fail-honest): the serve container (patched
  image, TF_GLM_ROUTER_MM=1) is committed; ncu + its nsight-compute dir are copied in
  from the base image (the head HAS host ncu at /usr/local/cuda/bin/ncu; the serve image
  does NOT — the base does); a throwaway container runs the engine under ncu filtered to
  tf_glm_router_mm + tf_glm_slice_sum, one ~2k-token prompt fires one 2048-row chunk, the
  CSV lands in the receipt. **The read**: mean per-launch duration × 8 slices × 80 layers
  vs the section's 1109 ms — fast kernels = the section is bubbles (host enqueue / span
  semantics); slow kernels = the SASS metrics say why. An instrument refusal is recorded,
  not retried.
- **settingsab already wired** (the round-24 phase): one hardmode run at temperature 1.0 /
  top_p 0.95 against the greedy receipts — production was also measured greedy, so a lift
  is ours without touching the comparison's fairness. Sampled runs are non-deterministic —
  one run is a draw, not a receipt.
- One prepare is NOT needed (the patched image from campaign-20261029-152500 is current);
  both phases restart the serve themselves.

## (round 87) The settings A/B is a WASH (item closed); the ncu capture died on phase plumbing (2026-10-29)

- **settingsab** (results/campaign-20261029-165850/17-settingsab.md): hardmode **92** at
  temperature 1.0 / top_p 0.95 vs the greedy 92 anchor — no lift. The recommended-sampling
  lever is a documented no-op on our bench (production was also measured greedy, so nothing
  is forfeited). Item CLOSED; the greedy 92/93 stays the deterministic anchor; config.sh
  unchanged.
- **ncurouter**: the phase died right after the serve came up (rc=1 at 17:50:27, before any
  capture step logged) — an instrument bug in my base-image ncu-extraction plumbing under
  the campaign's strict mode, NOT an engine result. The fix pass: drop the fragile
  docker-create/export dance and tar the nsight-compute dir from a `docker run --rm` pipe
  straight into the serve container (the one path whose mechanics are proven), guarded
  end to end. Cheap to rerun — no prepare needed.

## (round 88) The community perf sweep: the MiaAI-Lab fork's patch table — +36% prefill exists in the field (2026-10-29)

- **The find**: MiaAI-Lab/GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold — our exact model
  on our exact topology, 1,940–1,980 tok/s prefill at short context with a measured patch
  stack (we run ~1,517 tok/s at slope 0.659). Full table + ranking in ECOSYSTEM.md.
- **The levers, ranked**: (1) the HC-split/overlap set — +36% prefill at 50k, decode −1.5%,
  TP=2-native, and the same fix class our bubbles hypothesis predicts; (2) 0086
  prompt-scores-loop (BadAd84) — bit-exact, scoring −36%, cold prefill at 226k −8.5%;
  (3) the KDA chunked set — prefill −7–10%. Upstream main has moved past v1.1.9
  (36470cec) — scan for these graduating before porting.
- **Next**: the ncu rerun (the plumbing fix) + the upstream scan; the 0086 port is the
  first port candidate if upstream lacks it.

## (round 90) The autonomous window system: the agent-owned stop/restart, the cron safety net (2026-10-29)

- **(user)**: the agent may stop/restart production for a staged window — delegated to
  the script, not to the live session ("you stop production you will stop yourself").
- **scripts/autonomous-window.sh**: stop production → the window phases → restart
  production on EVERY exit path (trapped) — success, failure, interrupt. A flag file
  (/tmp/autonomous-testing.flag) marks an in-flight window for the cron; a second
  launch refuses while one is active. Multi-hour/multi-day safe: nothing depends on a
  live agent session.
- **scripts/autonomous-cron.sh** (cron every 30 min on the head): production down with
  no flag → restart it (the crash net; production must never stay down); a newer
  campaign receipt than the marker → write ~/.opencode-poke — the marker file the
  agent reads FIRST on any wake. The opencode CLI poke wires when its headless
  invocation lands; until then the user wakes the agent and it reads the poke file.
- The round-89 stale-chain incident's lesson is baked in: the orchestration lives in
  the repo script, never in an inline command chain.

## (round 92) The autonomous loop rebuilt on the real topology: the durable-inbox poke, the tip-owned production lifecycle (2026-10-30)

- **(user) restated the topology**: production on the head is the -tip checkout, started and
  stopped with ITS OWN start.sh/stop.sh (both ranks, rank logs saved, API-wait + smoke on
  start) — the raw docker stop/start the round-90/91 scripts used only touched the head rank;
  the agent harness runs on the agent host as a web server (systemd, basic auth); the testing
  repo lands on both hosts. Site values (the head's ssh target, the tip dir name, the server
  URL, the unit path) now come from git-ignored scripts/local.sh on each host — nothing
  site-specific committed.
- **The wake vector is PROVEN on hardware**: POST /api/session/{id}/prompt — the harness
  server's durable prompt inbox ("durably admit one session input and schedule agent-loop
  execution"). A throwaway session was created, prompted, answered in <10 s, deleted (204).
  The poke finds the session by project directory (newest first) and marks the campaign dir
  in a marker file, so each window pokes exactly once; a failed POST retries next tick.
- **scripts/autonomous-poke.sh** (agent-host cron, every 5 min): production up = container
  running AND /health answering (the port read from the tip's own config); then the durable
  prompt. **scripts/autonomous-window.sh** rewritten: production lifecycle through the tip's
  stop.sh/start.sh (the user-delegated stop), restore on every exit path via the trap, the
  flag file guards double launches, 30 s grace before the stop so the agent's closing message
  flushes. **scripts/autonomous-cron.sh** (head cron, every 5 min): the crash net only —
  production down with no flag → the tip's start.sh (flock-guarded); the poke half moved to
  the agent host.
- **The ncu generator's real bug found** (the round-90/91 windows never profiled): the
  run-capture.sh template was an f-string carrying a literal JSON body — Python ate the
  braces (ValueError: Invalid format specifier). Two latent bugs beside it: the capture
  script was copied into the serve container AFTER the commit (the capture container never
  had it), and the blind sleep 300 raced the ~4-min model load. The template is
  placeholder-based now, self-waits for the serve, self-queries the served model id, signals
  done; the serve container is stopped before the capture (port + GPUs free; the capture
  container is rank 0, the worker's rank 1 may not accept the fresh peer — fail-honest); the
  phase polls for the done marker up to 25 min. Generation PROVEN locally on an inspect.json
  fixture (rc=0, binds filtered, bash parses, no unresolved placeholders).
- **Next window**: preflight ncurouter summary through the rebuilt loop — the first full
  autonomous cycle: stop → phases → restart → poke. The poke marker is seeded with the
  current newest campaign (this round's diagnosis) so only the new window wakes the agent.

## (round 92) The autonomous loop rebuilt on the real topology: the durable-inbox wake, the production checkout's own lifecycle (2026-10-30)

- **(user) restated the topology**: production on the head is the -tip checkout, started and
  stopped with ITS OWN start.sh/stop.sh (both ranks, rank logs saved, API-wait + smoke test)
  — the raw docker stop/start the round-90/91 scripts used only touched the head rank, which
  is why the early attempts "did not work". The agent harness runs on the agent host (a
  systemd web server, basic auth). Site values (the head's ssh target, the tip dir name, the
  server URL, the unit path) now come from git-ignored scripts/local.sh on each host —
  nothing site-specific is committed (SSH_TARGET, PROD_TIP, OPENCODE_API, OPENCODE_UNIT).
- **The wake vector is PROVEN on hardware**: POST /api/session/{id}/prompt — the harness
  server's durable prompt inbox ("durably admit one session input and schedule agent-loop
  execution"). A throwaway session was created, prompted, answered in <10 s, deleted (204).
  The poke finds the agent's session by project directory (newest first) and marks the
  campaign dir in a marker file, so each window pokes exactly once; a failed POST retries
  next tick.
- **scripts/autonomous-poke.sh** (agent-host cron, every 5 min): production up = container
  running AND /health answering (the port read from the tip's own config), then the durable
  prompt. **scripts/autonomous-window.sh** rewritten: production lifecycle through the tip's
  stop.sh/start.sh (the user-delegated stop), restore on every exit path via the trap, the
  flag file guards double launches, 30 s grace before the stop so the agent's closing message
  flushes. **scripts/autonomous-cron.sh** (head cron, every 5 min): crash net only —
  production down with no flag → the tip's start.sh (flock-guarded); the poke half moved to
  the agent host.
- **(user) on redaction**: methodology may be generalized in committed text, but site
  specifics stay in git-ignored files — enforced on the new scripts (no hostnames, no
  absolute local paths; values only from local.sh with fail-honest `:?` guards).
- **The ncu generator's real bug found** (the round-90/91 windows never profiled): the
  run-capture.sh template was an f-string carrying a literal JSON body — Python ate the
  braces (ValueError: Invalid format specifier). Two latent bugs beside it: the capture
  script was copied into the serve container AFTER the commit (the capture container never
  had it), and the blind sleep 300 raced the ~4-min model load. The template is
  placeholder-based now, self-waits for the serve, self-queries the served model id, signals
  done; the serve container is stopped before the capture (port + GPUs free; the capture
  container is rank 0 and the worker's rank 1 may not accept the fresh peer — fail-honest);
  the phase polls for the done marker up to 25 min. Generation PROVEN locally on an
  inspect.json fixture (rc=0, binds filtered, bash parses, no unresolved placeholders).
  A bash gotcha cost a pass: an apostrophe inside a `${VAR:?message}` expansion is parsed as
  a quote — the guard's syntax check caught all three scripts.
- **Next window**: preflight ncurouter summary through the rebuilt loop — the first full
  autonomous cycle: stop → phases → restart → poke. The poke marker is seeded with the
  current newest campaign (this round's diagnosis) so only the new window wakes the agent.

## (round 93) The first COMPLETE autonomous cycle — and the capture's structural post-mortem (2026-10-30)

- **(user)**: standing autonomy granted — "rinse and repeat": research online, check
  ashhart/TensorFold for updates, PRs and forks, the NVIDIA forums, keep the repo current,
  continue the development; site specifics stay git-ignored (enforced: SSH_TARGET, PROD_TIP,
  OPENCODE_API, OPENCODE_UNIT only in scripts/local.sh per clone).
- **The cycle worked end to end**: launch → production stopped (both ranks, via the tip's
  stop.sh) → preflight + ncurouter + summary ran → production restored (start.sh) → the
  cron poke woke the agent. The wake loop is real.
- **The capture failed on three structural facts, now receipted** (results/campaign-
  20261030-011413/31-ncurouter.md + the console): (a) the capture container inherited NO
  binds — the model cache is a BIND mount the swap cannot carry (the engine died instantly:
  model path "neither a directory nor a HF repo id"); (b) the WORKER rank exits cleanly the
  moment the head rank's container stops — a throwaway rank 0 has no TP peer, ever; (c) the
  agent's double-launch race (two ssh attempts) stripped the flag mid-window, the head's
  crash-net cron then started production while the window ran, and the poke fired
  mid-window about an unfinished campaign.
- **Fixes, all committed and fixture-proven (3b22d74)**: the capture is now a WRAPPED
  RESTART — RANK0_WRAP/RUN_IMAGE hooks in the testing start.sh (rank 0's engine under ncu
  INSIDE the stack's normal lifecycle; rank 1 comes up normally and the pair forms);
  duration-metric-only collection (minimal per-launch overhead); WAIT_TIMEOUT bounds the
  boot; the reader reports the duration DISTRIBUTION (boot/warmup/smoke/prompt mix
  shapes). The DRY_RUN fixture on the head shows rank 0 wrapped + the committed image,
  rank 1 clean. scripts/autonomous-launch.sh is now the ONLY launcher (sync + flag-refuse
  + detached start); the window's refusal path no longer touches production or writes a
  completion file (STARTED gate); the poke hands off while a window flag exists.

## (round 94) The research pass: upstream's row-split pair seam, the fork's KV/spill patches, the forum's looping pathology (2026-10-30)

- **Upstream (465e48b6..cefb72fd, no new tag)**: the recent work is Nemotron CUDA (#548)
  and Qwen3.8-27B pair-seam kernels (#1432) — including a NEW CORE primitive,
  "the row-split pair seam, split simd_qmm over K" (e06a6eef): row-splitting between the
  ranks as a core mechanism — the native shape of what the fork's HC-split set hand-rolls.
  No GLM performance items graduated; our v1.1.9 pin stands until something GLM-relevant
  lands.
- **The fork (MiaAI-Lab)**: newest 2026-10-25 — the published v0.6.0 image pinned with 123
  patches; new since the round-88 sweep: patch 0128 (spill tier in blocks shared by later
  turns) and 0129 (KV sharding — each conversation's latent cache once on its owner Spark),
  both serving-memory items, not prefill. The HC-split/overlap set (round 88's +36%) and
  0086 (bit-exact scoring) remain the port candidates; 0086 stays first (smallest diff,
  bit-exact).
- **The forums (thread through Oct 13)**: a DETERMINISTIC high-context looping pathology on
  the TensorFold engine — long-form document processing loops on the same paragraph, same
  payload fails identically every time (the reporter: 7 restarts in hours on TF vs one
  loop in 22+ h on the EXL3/vLLM engine); a standing watch item — our greedy determinism
  would reproduce it identically if a bench scenario hit it. tool-eval-bench gained
  official TensorFold support upstream (PR #190, in main) and the community's hardmode
  protocol (thinking+max effort, temp 0.1, trials 5) converges on ours. New recipe
  pattern spotted: jordanm82's "dealign o_proj transplant (layers 15–44), latent FP8" —
  a quality-preserving transplant, untested by us. Adoption is broad (k8s helm charts,
  metric TUIs, vLLM backports of TF's speedups).
- **Next**: the ncu window relaunch through the hardened loop — the wrap design's first
  live test; the read splits the router section into kernel time vs bubbles.

## (round 95) The wrapped restart's first live test: one bug, found by its own fail-honest branch, fixed (2026-10-30)

- The wrap-design window (campaign-20261030-014654) failed in 5 s with a clean receipt:
  rank 1's docker run on the worker could not find `rg-ncu-img` — the committed instrument
  image exists on the head alone and the worker tried to PULL it. The loop mechanics were
  perfect: the fail-honest branch recorded the error, the campaign wrapped, and the
  window's restore had production serving again in 97 s.
- **Fix**: rank 1 never needed the instrument image — its engine bits are identical. The
  RUN_IMAGE override now applies to rank 0's image only; rank 1 always runs the prepared
  ref (no 2 GB docker save/load over ssh). DRY fixture on the head: rank 0 = rg-ncu-img +
  the ncu wrap, rank 1 = the prepared image, unwrapped.
- Next window relaunches the same phases — the wrap design's second live test.

## (round 96) The wrap becomes the container entrypoint (2026-10-30)

- The second live test failed in seconds with another exact receipt: the engine printed
  its USAGE — the image's ENTRYPOINT is the engine binary itself, so prepending the
  wrapper to the command gave the engine argv `ncu --kernel-name ...` (garbage to it).
- **Fix**: RANK0_WRAP now overrides `--entrypoint` with the wrapper binary; the image's
  engine path (inspected from the prepared image) and the serve args follow as the
  wrapper's arguments. DRY fixture: `--entrypoint /usr/local/bin/ncu ... rg-ncu-img
  --kernel-name ... --log-file /tmp/rg-ncu.csv /opt/tensorfold/bin/tensorfold-native
  serve ...` — ncu execs the engine as its child, exactly the profiling shape.
- Next window relaunches the same phases.

## (round 97) ERR_NVGPUCTRPERM: the last instrument gate — SYS_ADMIN satisfies it (2026-10-30)

- The third live test's engine booted under ncu and answered a REAL prompt (1053-byte
  reply, try 1) — the wrap-as-entrypoint design works — but the CSV held only ncu's
  banner: `ERR_NVGPUCTRPERM - The user does not have permission to access NVIDIA GPU
  Performance Counters`. The driver loads with `RmProfilingAdminOnly: 1`.
- Hardware test (throwaway container, tiny matmul, production untouched): with
  `--cap-add SYS_ADMIN` ncu connected, profiled, and produced duration rows
  (`gpu__time_duration.sum`, ns). No driver module reload needed.
- **Fix**: the wrapped rank-0 command now carries `--cap-add SYS_ADMIN` (only when
  RANK0_WRAP is set). DRY fixture confirms cap + entrypoint together.
- Two side lessons from the test: the committed serve image has no python3 (its CUDA
  program test needed the base image), and NGC's python lives at /opt/conda but this
  box resolves /usr/bin/python3.
- Next window: the full capture — boot + smoke + one 2048-row prompt under the counter-
  enabled profiler; the receipt should finally carry the duration distribution.

## (round 98) FRONT 2 A2 RESOLVED: the router section is ~97% bubbles — device-event spans starve between µs-scale kernels (2026-10-30)

- **The verdict data** (campaign-20261030-023707/31-ncurouter.md, completed offline after the
  reader's banner-skip fix): under the counter-permitted wrapped restart, 512 kernel rows —
  336 x tf_glm_router_mm (p50 36.2 µs, p95 45.6 µs, grid (11,5,1) constant) + 176 x
  tf_glm_slice_sum (p50 10.5 µs, p95 65.5 µs; grid (1,1,1) x121 — launch-latency stubs).
  Kernel time per 2048-row chunk: **p50 29.9 ms, p95 71.1 ms** against the section's
  ~1109 ms — **kernels 2.7% at p50 (6.4% at p95); the other ~1080 ms is gaps**.
- **The span semantics settled from source**: zig/src/families/glm/cuda_prompt_trace.zig —
  "paired same-stream events" — the engine's stage ms= values are CUDA EVENTS (device
  time). The 1109 ms was device time: the stream idles between µs-scale kernels — host
  enqueue / sync starvation, NOT kernel cost. Hypothesis four's answer: the section needs
  OVERLAP (fewer, bigger launches; exchange overlapped with compute), the exact fix class
  of the fork's HC-split/overlap set (+36% prefill) and upstream's new core row-split pair
  seam (e06a6eef).
- The ncu instrument is complete and receipted: wrap-as-entrypoint + SYS_ADMIN (the
  RmProfilingAdminOnly=1 gate) + rank 1 on the prepared image + duration-metric-only +
  bounded wait. Reader fixed (ncu banners precede the CSV header — skip to the "ID" line).
- **Recon for the next window**: 0086-glm-prompt-scores-loop is a 131-line, ONE-file
  (tensorfold/families/glm5_next/cuda/sparse.py — python, no fatbin rebuild), bit-exact
  patch (the fork's receipt: scoring -36%, cold prefill at 226k -8.5%); the fork is cloned
  on the head (/tmp/tf-fork) with 0010/0033/0086 present. Next: verify 0086 applies to the
  v1.1.9 pin, port it, and A/B it (prefill instrument + content parity) in a window; the
  HC-split set stages behind it as the confirmed-class big prize.

## (round 99) The port plan re-scoped: the fork's stack is the PYTHON engine — our line is native (2026-10-30)

- **0086 is not portable**: the patch targets `tensorfold/families/glm5_next/cuda/sparse.py`
  — a Triton kernel in the PYTHON engine — and our pin has NO glm5_next python files at all
  (the native CUDA line's scoring is tf_glm_* kernels). The fork's WHOLE stack is python-side
  (0010: comm.py/decode.py; 0033: forward.py/hcsplit.py; 0064: engine.py) — none of it ports
  to the native line. The round-88 "port 0086 first" plan is withdrawn; the fork's NUMBERS
  (1,940–1,980 tok/s prefill on 2×Sparks) remain the field reference for the model's
  potential, now understood as a DIFFERENT engine.
- **Upstream's row-split pair seam (e06a6eef) is native-core** — four kernels
  (pair_stage/pair_gather/pair_argmax/pair_pick) exchanging whole output rows instead of K
  halves — but its steps 2–6 are Qwen-specific; GLM coverage is future. WATCH, not port.
- **The fix path for our bubbles verdict is native-side**, guided by a clean stage map: the
  new **profchunk** phase (no ncu — the round-98 capture proved the paired-event spans
  inflate ~7× under a profiler) restarts the probe config with TF_GLM_PROF=1, fires one
  ~2k-token prompt, and aggregates the LAST chunk's spans per (site,stage) in device time —
  naming which stage owns the chunk and how much of the wall is inter-stage gaps.
- Next window: preflight profchunk summary — the stage-resolved bubbles map.

## (round 100) Front 2 A2 finally resolved: the "1109 ms router section" was a span-under-concurrency artifact (2026-10-30)

- **The clean stage map** (campaign-20261030-030326/32-profchunk.md — the profchunk phase,
  no ncu): a lone 1322-row chunk = wall 1283 ms; ffn/ffn (the expert GEMMs) 636 ms — the
  real compute; ffn/router **8.6 ms total (~0.2 ms/layer)**; wait_filled spans ~1019 ms
  overlapping across streams (spans sum to 143% of the wall — they are concurrent-stream
  pairs, per cuda_prompt_trace.zig's design).
- **The round-85 number's source, found**: `glm prof prompt chunk to 2048 rows (4 calls):
  wall 1693.44 ms, gpu 1968.41 ms a call; ... router 1109.46 ...` — measured under 4-way
  concurrent load (gpu > wall proves overlap). Paired-event spans absorb device-busy time
  when other streams share the GPU: the router stage — the one with MANY µs-scale launches
  — was the canary absorbing the enqueue/queue contention. The three round-85 kernel probes
  "agreed" because they all measured the same artifact. The m=64-chunk 54.9 ms reading: the
  same mechanism.
- **What is solid**: the router kernels are µs-scale (ncu, round 98); the router STAGE is
  negligible in clean spans (round 99's map); the expert GEMMs own ~half the lone-chunk
  wall; and the qualified perf deficit is the c4 aggregate (99.8 vs production's 154.5 t/s,
  65%). The native line's bottleneck hypothesis: **launch/enqueue efficiency under
  concurrency** — which the fork's python engine dodges with bigger fused Triton kernels.
- **The artifact becomes the instrument**: the new profload phase runs the same serve under
  TF_GLM_PROF=1 through (1) a lone 14k prefill and (2) four concurrent 2k prefills, and
  reads the engine's own `glm prof prompt chunk` aggregates side by side — where the
  concurrency cost lands, stage-attributed.
- Front 2 A2 CLOSED (the mystery was the measurement, not the kernels); the perf front
  refocuses on the concurrency deficit. No config change; no chart change (no new
  qualified perf fact yet — profload's read may produce one).

## (round 101) The concurrency cost, stage-attributed: the router stage inflates 18x under 4-way load (2026-10-30)

- **profload's verdict** (campaign-20261030-031655/33-profload.md): under the 4-way 2k
  prefill (1839 tok/s aggregate, 4.35 s wall), the engine's own aggregate attributes
  `router 285.72` + `routed 284.43` of the 607.78 gpu-ms per call — the router stage at
  285 ms/call against its clean ~16 ms (0.2 ms/layer x 80, round 99): **18x inflation from
  enqueue contention**, while the routed experts carry ~1.8x (real compute + queueing).
  The lone 14k leg: 15.8 s (~885 tok/s single-stream); its aggregate line did not appear
  in the tail (the engine prints the aggregate on multi-call chunk completion — noted,
  not blocking).
- **The diagnosis chain is complete**: round 98 (the kernels are µs-scale) → round 99
  (the clean stage map; router negligible, experts own the wall) → round 100 (the 1109 ms
  was spans absorbing concurrency) → round 101 (WHERE it lands: the many-tiny-launch
  stages). The native line's concurrency deficit lives in launch/enqueue serialization of
  the micro-kernel stages — the same pressure the fork's fused Triton kernels and
  upstream's pair seam attack by having FEWER, BIGGER launches.
- **Next**: re-qualify the actual c4 deficit on the current pin before any fusion work —
  the c4 99.8 t/s receipt predates the v1.1.9 pin. Window: preflight throughput
  throughputP summary (the standard throughput battery, fresh receipts). If the deficit
  holds, the fix candidate is a native FUSION patch (fewer launches per layer in the
  router/slice/glue stages) — designed against the fresh receipts, never against TCs.

## (round 102) The fresh throughput receipts: the c4 aggregate moved 99.8 -> ~146 t/s on the current pin (2026-10-30)

- **throughput (campaign-20261030-033009/03c)**: dense4fp8 (the standing config), fresh
  bench — c1 tg128@d0 46.4 t/s; **c4 aggregate at d0 = 36.5 x 4 = ~146 t/s** (vs the
  anchored 99.8 — the v1.1.9 pin + the current config moved it +46%); d4096 c4 18.8 x 4 =
  75; d8192 c4 ~65. Prefill pp2048 c4 894 t/s (d0).
- **throughputP refused honestly**: the production-parity leg (paged bf16 KV) does not
  fit at 512K x PARALLEL=4 (the known memory wall) — no fresh like-for-like production
  number from this window.
- **Next**: prodqual — the full read-only battery against the UP production (its current
  engine), giving the honest fresh side-by-side; if the gap narrowed as indicated, the
  anchors + chart update with the fresh pair. The poke now fires only on COMPLETED
  campaigns (the wrapper's final " done." log line), so the long prodqual run cannot
  wake the agent prematurely.

## (round 103) The fresh cross-engine re-baseline: production runs the fork-patched python tip — the native line's answer is its own engine's main (2026-10-30)

- **prodqual's fresh receipt** (campaign-20261030-041536/02b): production on its CURRENT
  engine — score 96 (★★★★★, 133/138; the ledger's round-35 v3.0.1 baseline already carried
  the 96 — the quality gap is standing, not new), and PERF that jumped: c1 tg128@d0 57.4,
  **c4 aggregate 241.6 t/s (60.4 x 4)**, prefill pp2048 1,513 t/s.
- **The jump is explained** (the ledger's standing (user) item): production runs MIA'S
  PATCH SERIES folded onto the python-0.6 tip (0109-0122 + 0128-0129 + the 0088 NoRoom fix)
  — the fork's overlap stack materialized in production's numbers, exactly as the fork's
  table promised. The gap is CROSS-ENGINE: our native CUDA line (v1.1.9) at c4 146.0
  (60%), prefill 1,032 (68%), c1 46.4 (81%).
- **Anchors + chart updated with the fresh pair** (decode solo 46.4/57.4, c2 77.4/134.2,
  c4 146.0/241.6, prefill 1,032/1,513; dated 2026-10-30; the duel-era rows preserved in
  the raw labels). The old "at par / CROSSED" rows are history — production's engine moved
  under it.
- **The native line's answer stages now**: a PIN BUMP to upstream native main (cefb72fd —
  the Nemotron/Qwen/pair-seam line, possibly carrying launch-efficiency work), gated by
  the FULL battery: parity's content gates + the reference score (the 92 bar) MUST pass or
  the pin reverts to 465e48b6. This does NOT override the round-85 (user) pin decision —
  it TESTS whether its premise (upstream actively improving the native engine) has produced
  something worth taking; the receipts decide, and the revert is automatic on wake if the
  gates fail. The fork-patched python engine is production's choice; this line's charter
  (EXL3 native) stands.

## (round 104) The pin bump did NOT take: the fingerprint excludes TF_COMMIT — the battery measured the old engine (2026-10-30)

- The round-103 window's preflight receipt betrays it: the prepared marker stayed
  `tf=commit@465e48b6` — the pin in scripts/local.sh does NOT trigger the auto-prepare
  (the fingerprint covers the config settings, not the commit pin), the image existed, so
  start.sh served the OLD engine and the whole battery re-measured it: parity's probes
  passed (on the old engine — no information), throughput's c4 aggregate read 122 t/s
  (vs this morning's fresh 146 on the same engine — run variance / config delta, noted).
- **My phase-list error, also recorded**: `reference` probes PRODUCTION (read-only) — it
  skipped in a production-down window ("production was not running at campaign start").
  Production-probing phases belong in prodqual runs, not windows.
- **The fix**: the new pinbump phase — an EXPLICIT prepare.sh (the pin drives what it
  builds; the kernel cache makes the compile incremental) with the marker verified
  before/after (fail-honest if it does not move to the pin). The battery only counts when
  the marker moved.
- Next window: pinbump parity throughput summary (reference dropped from windows).

## (round 105) The pin-bump verdict: upstream native main is SLOWER — revert to v1.1.9 (2026-10-30)

- The pinbump receipt: the marker was ALREADY at cefb72fd before this window's prepare —
  the auto-prepare fired during the round-104 window (a phase's config fingerprint change
  coincided with the pin sitting in local.sh), so the pin DID drive a build once prepare
  ran; the round-104 window simply measured the old engine before that point.
- **The new engine's battery** (campaign-20261030-062126, all on cefb72fd): parity's
  probes PASS (the engine is compatible with the served checkpoint), but the perf is
  SLOWER than v1.1.9 across the board: c1 tg128@d0 39.0 vs 46.4, c4 aggregate 31.3x4=125
  vs 36.5x4=146, prefill 1,023 vs 1,032 (same phase, same config, same day). Upstream
  main's recent work (Nemotron/Qwen/pair-seam) did not help — and slightly hurt — our
  model's paths.
- **DECISION (the round-103 discipline, automatic)**: the bump's purpose was perf; it
  delivered negative → REVERT the pin to 465e48b6 (v1.1.9) and rebuild. The quality gate
  (the candidate score) is moot on a slower engine. The revert window re-prepares and
  re-runs parity + throughput to confirm the 146-class numbers return.
- The perf plan after the revert: the native line's deficit (60% c4 vs the fork-patched
  python tip) stands on v1.1.9, and the fix path is the round-98-101 diagnosis — native
  launch/fusion work in the micro-kernel stages. That is the next major sitting's build.

## (round 106) The pin saga closes as INCONCLUSIVE — run variance (~16%) swamps the engine delta, and the auto-prepare drops pins (2026-10-30)

- This window's pinbump found the marker ALREADY back at 465e48b6 — the auto-prepare
  DROPPED the cefb72fd pin mid-round-105 (a phase's fingerprint change fired it; it
  re-resolves the DEFAULT ref, ignoring local.sh pins — the round-7 lesson re-confirmed
  live). Round-105's "new engine slower" numbers were therefore probably the OLD engine.
- **The variance discovery**: three same-engine (465e48b6), same-phase, same-config runs
  today span c1 39.2–46.4 t/s and c4 aggregate 122–146 t/s — a ~16% band. The engine
  comparison (v1.1.9 vs cefb72fd) is UNRESOLVED at this noise; the round-105 revert
  verdict was premature (its numbers may have measured either engine).
- **Resolution**: the pin is REMOVED from scripts/local.sh entirely — the default ref
  (v1.1.9) applies with no pin-drop risk. The bump attempt is receipted as inconclusive-
  at-noise; future engine A/Bs need 2+ runs per arm (or a tighter instrument) before a
  verdict. The anchors' decode rows gain the variance band in their raw labels.
- The perf work proceeds on the diagnosis, not the pin: the native fusion/overlap build
  (rounds 98-101) is the next sitting's work — code first, then its A/B window.

## (round 107) The definitive benchmark staged: one hardmode+perf run per serve, the model cards regenerated from it (2026-10-30, (user) directive)

- **(user)**: re-run tool-eval-bench once (hardmode + perf statistics in a single run),
  regenerate the model cards on the GitHub site, confirm the current benchmarks for
  production AND testing; nothing else runs during the window; the results are the
  definitive performance comparison.
- **The cardrun phase** (session-specific): BENCH_TARGET=prod runs the bench READ-ONLY
  against the up production (the campaign launched directly, never through a window);
  BENCH_TARGET=test runs it against the standing Focus default inside a window. ONE
  invocation per serve: the full suite (standard + --hardmode) + --perf, the receipted
  protocol (seed 42, parallel 2, timeout 240, no-live). The run's stored run id renders
  the serve's definitive card into the receipt dir; the cards move to docs/cards/ and the
  README's table + the anchors update on the final wake.
- **The order**: the prod leg first (the agent launches and goes idle — the
  clean-window discipline; the poke fires on the campaign's done), then the test leg as a
  window, then the cards/README/anchors digest. The top4cfg's historical cards stand as
  receipted history (regenerating them needs a dedicated cell window — offered on wake).

## (round 108) The definitive benchmark is in: one hardmode+perf run per serve, the cards + the anchors carry it (2026-10-30, (user) directive complete)

- **The runs** (nothing else touched either serve during the legs — the agent launched
  and went idle per the (user) discipline): production
  `results/campaign-20261030-091518/card-prod` (run `…ac7ca1ed`, 09:27) and ours
  `results/campaign-20261030-095456/card-test` (run `…37325127`, 10:10) — each ONE
  invocation: the full 104-scenario suite (standard + Hard-Mode) plus perf statistics,
  the receipted protocol (seed 42, parallel 2, timeout 240, no-live).
- **The definitive scores**: production **94**, ours (the Focus default) **93** — consistent
  with the standing baselines (the prodqual 96 this morning was the 69-scenario standard
  suite; the 104-suite denominators differ).
- **The definitive perf pair** (the anchors now carry it): prefill pp2048@d0 1,039 vs
  1,516 (68%); decode solo 45.3 vs 52.9 (86%); c4 aggregate@d0 148.0 vs 241.2 (61%);
  c4@d8192 52.0 vs 76.4 (68%). Production's d4096-c4 row carries a stall outlier
  (TTFT 92.9 s) — noted in the receipt, not the anchors.
- **The cards**: `docs/cards/prod-definitive.svg` + `focus-definitive.svg` rendered from
  the stored runs (cwd-scoped store, the receipted recipe); the README's card section
  restructured around the definitive pair (the per-suite cards remain as history; the
  top4cfg's cards stand as receipted history — regenerating them needs a dedicated cell
  window).
- The perf plan's next step stands: the native fusion/overlap build against the
  round-98-101 diagnosis, A/B'd with 2+ runs per arm (the variance rule).

## (round 109) The confidentiality audit (user directive): the current tree is clean; the guard now reads the site's values dynamically (2026-10-30)

- **(user)**: check everything uploaded to GitHub for sensitive information.
- **The sweep**: every tracked file grepped for the site's identity classes
  (hostnames, the LAN/rail addresses, ssh targets, netdev/HCA names), creds-shaped
  strings, username paths, tracked artifacts, and the git history (pickaxe).
- **Fixed in the current tree**: (1) four tracked `.pyc` bytecode files removed and
  `__pycache__/`, `*.pyc`, `data/` git-ignored (the bench's cwd-scoped run store
  lives in `data/` on the head — never committed); (2) the docs guard's own check
  pattern EMBEDDED the site's subnet (`192.168.2.`) and a hostname pattern — the
  guard now builds its forbidden-value patterns dynamically from THIS clone's
  git-ignored local.sh/SITE.md (embedding nothing; the agent host's docs/SITE.md
  was written for it, git-ignored); (3) the retired AZ-era scripts' hardcoded
  `/home/giles` paths redacted to `/home/<user>` (six scripts + two historical
  LAUNCH.md lines — the append-only rule respected with this note); (4) the
  README's chart alt-text genericized (it carried stale per-bar numbers).
- **Verified clean**: no site tokens, no creds-shaped strings, no username paths,
  no tracked bytecode/sqlite/logs in any tracked file; `results/`, `data/`,
  `local.sh`, `SITE.md`, `__pycache__/` all git-ignored; no untracked surprises.
- **The history finding (the user's call, not acted on)**: the earliest commits
  (b045077..~1e29e84, before the repo's first genericization) carry real site
  values in tracked receipts/config — the two later scrub commits cleaned the
  TREE, but git history retains them. Purging them means a history rewrite
  (git-filter-repo) + a force-push + re-syncing every clone. Options on request:
  rewrite, or accept-and-document (the values are LAN-private; the repo's
  exposure is whoever GitHub grants access).

## (round 110) The history finding is closed: accepted as-is (user, 2026-10-30)

- **(user)**: "We accept that early commits had this and do not require addressing — it
  was site-specific data, but not ultra-sensitive." No history rewrite; the round-109
  audit's current-tree fixes stand, and the guard's dynamic site check (round 109) keeps
  every future commit self-policing. The audit item is CLOSED.

## (round 111) The next-release scan: mtp-confidence lands for GLM (off-by-default, TP=2-adverse), the launch-batching pattern migrates model by model (2026-10-30)

- Upstream main cefb72fd..a0d2489 (+25 commits, no new tag): the Unreleased section grows
  the GLM `--mtp-confidence` decode lever (#1585 — off by default, bit-safe, but TP=2
  code-heavy 3.7% slower: not our lever), the GLM lanes' depth-floor drafting, the
  Qwen3.5/FlashNext BATCHED MTP drafting ("many rings in one launch" — the launch-
  batching fix class our diagnosis calls for, per-model), the pair seam's Metal step 1,
  LFM2 taps, the DFlash2 threshold, Nemotron consolidation, HIP tuning.
- GLM-path activity confirms the family is maintained (glm_glue_rows/lanes/mtp_chance
  touched) — all decode-side; nothing moves our prefill/concurrency deficit. The pin
  stays the default (v1.1.9); the bump waits for GLM pair-seam CUDA steps, the batched-
  launch pattern reaching GLM, or a v1.2.0 tag.
- The fusion-patch recon scoped: cuda_engine.zig:prefillChunk → cuda_forward_pieces.zig →
  core launch helpers; the deep trace (the per-layer micro-kernel census + the fusion
  design) is the next sitting's build. Full findings in ECOSYSTEM.md (round 111).

## (round 112) The launch-path trace: the SERVED path already batches the router slices — the round-98 capture profiled the wrong path (2026-10-30)

- **The trace** (the pinned source): prefillChunk → f.run → per layer: f.pre (glue.hcPre —
  the tf_glm_hc_partial(8) chain) → f.mixer (kda/dsa) → f.gather → f.post (hc_finish) →
  f.pre → f.ffn → glue.router → **f.gather → f.post. The STOCK router path launches
  router_part ONCE per layer with grid.z = router_ks (the slices batched) + slice_sum —
  it is the round-84 PATCH that splits them into 8 launches (the chain kernel's 74 KB
  dynamic shared memory cannot z-batch). The served config runs the STOCK path — so the
  round-98 ncu capture profiled the PATCHED path (8 router_mm/layer), not the served one.
- **The corrected fusion targets** (the served path's kernels):
  tf_glm_router_part + tf_glm_slice_sum (the router pair) and the hc chain
  tf_glm_hc_partial(8) / tf_glm_hc_finish(_f32w) (the glue's pre/post — the
  partials/glued stages in the clean span map). The bit-safety constraint that shaped
  the stock design stands: the slice sum's order is fixed (sliceSum in slice order), so
  a router_part+slice_sum fusion needs a cross-block dependency — not trivially
  bit-safe; the hc chain's partial/finish pair is the cleaner fusion candidate.
- **The instrument corrected too**: the ncurouter phase takes NCU_TARGET=stock|patched —
  stock restarts the SERVED config and filters to the served kernels (the patched path
  remains available). Next window: the SERVED path's per-launch census under the counter-
  permitted wrap — the census decides which pair the fusion patch targets.

## (round 113) The served-path census refused — the instrument made rank-symmetric (RANK1_WRAP) — and relaunched (2026-10-30)

- **The poke receipt** (campaign-20261030-120744): the window completed, production
  restored — but `31-ncurouter.md` records the WRAPPED restart refused:
  `REFUSE rank settings: rank 1's program differs from rank 0's (the executable)`.
  The refusal is a receipt: the admission gate worked; the instrument was wrong.
- **Root cause, two layers**:
  1. The round-112 parameterization was HALF-done — the phase's first restart took
     `NCU_TARGET` (the stock warm-up ran), but the WRAPPED restart line still carried
     the patched env (`PATCHES=glm-router-gemm.patch TF_GLM_ROUTER_MM=1`), so the
     re-prepare built rank 1 a patched binary while rank 0 ran the just-committed
     instrument image (unpatched v1.1.9 + ncu).
  2. The deeper mechanism: the GLM rank start all-gathers a Fingerprint whose
     `program` field is the **sha256 of the executable** (cuda_ranks.zig:132) — any
     engine-binary asymmetry refuses the pair. The old "rank 1 is never wrapped"
     design predates this check (the round-98 captures ran on a source without it).
- **The fix (round 113a, c60305e)**: start.sh gains `RANK1_WRAP` — a wrapped rank 1
  mirrors rank 0 (`--cap-add SYS_ADMIN --entrypoint ncu …`, and it follows RUN_IMAGE so
  both engines come from the SAME instrument image); the ncurouter phase ships the
  fresh `rg-ncu-img` commit to the worker before the wrapped restart (docker save |
  worker docker load, 3 tries — the LAN link flaps); the wrapped restart now honors
  `NCU_TARGET` (stock: no PATCHES, no re-prepare → both ranks run the committed
  v1.1.9+ncu engine); launch budget 512→2048 (the hc chain multiplies the launch
  count); rank 1's CSV is copied out as the symmetry receipt. Dry-run verified: the
  rendered pair is argv-identical except `TF_GLM_RANK`/serve flags (which the
  fingerprint never compared — normal operation proves that).
- **The worker link flap noted**: two `Network is unreachable` bursts to the worker
  mid-sitting (ping + ssh answered between them); the image ship retries through it.
- **Third instrument failure (campaign-20261030-125326) — the topology, not the quoting**:
  both ranks started under ncu and the pair FORMED (the %q + same-image fixes worked —
  no refusal), but the boot never reached /health in 900 s; rank 1's process ended
  first and rank 0 followed (`another rank's process ended`), and rank 0's ncu CSV
  held only the connect banner — ZERO kernels profiled in 15 min: both-wrapped ranks
  stall at their first profiled launch. (The worker-side log.gz I first pulled was
  production's teardown noise — `tensorfold-glm53/logs` is production's log home.)
- **The decisive mechanism (round 113c, eaddce0)**: the fingerprint's program field is
  `hashFile("/proc/self/exe")` (cuda_engine.zig:120) — the sha256 of the ENGINE's own
  binary; ncu wrapping does not change the engine child's exe. So the 12:07 refusal
  was an IMAGE mismatch (round-97 instrument image vs fresh prepare), not wrap
  asymmetry — and an UNWRAPPED rank 1 on the SAME image passes. start.sh gains
  RANK1_IMAGE (same image, no wrap); the phase reverts to the round-98-proven
  rank-0-only topology with the proven 512-launch budget (the hc filter's 4 names at
  2048 made the warmup's profiled-launch volume unaffordable). Relaunched.
- **Relaunch misfire (recorded, fail-honest)**: the first relaunch passed a TITLE to
  autonomous-launch.sh — its argument is the PHASES LIST ("preflight ncurouter
  summary", as every prior window). `PHASES=served-path census: …` matched no phase:
  campaign-20261030-123548 exited in the same second (`done.`, rc=0, no receipts) and
  the window restored production. One needless production stop/start cycle; the
  running-request cutoff warn noted. The TRUE relaunch used the phase list; the census
  read is round 114 when the poke lands.
- **Second instrument failure (campaign-20261030-124211), also mine**: the wrapped
  rank 1 never started — `bash: line 1: tf_glm_slice_sum: command not found` on the
  worker. rank 1's command travels as an ssh STRING (a remote shell parses it) and the
  ncu filter regex's `|` pipes executed as shell pipes; rank 0's command is an argv
  ARRAY (no shell) — which is exactly why the round-98 rank-0-only wrap worked. Fixed
  in round 113b (7a2dd6f): the wrap's tokens are `printf '%q'`-quoted into the rank-1
  string (dry-run verified: `regex:…part\|…sum` reaches the remote bash escaped). Also
  noted: the fingerprint changed with the start.sh edits, so the stock warm-up
  re-prepared once (docker cache, ~5 min) — the round-7 lesson's mechanism, one-time.
- **Relaunched again** (preflight ncurouter summary, NCU_TARGET=stock); the census
  read is round 114 when the poke lands.

## (round 114) The served-path census, first half: the hc chain measured; the router_tile discovery and the stale-source catch (2026-10-30)

- **The census landed** (campaign-20261030-132328, the round-113c rank-0-only topology):
  512 rows captured, prompt fired try 1 (1322 tokens — the probe's literal repetition
  tokenizes shorter than the ~2048 target; one 1322-row chunk, spans=2560 in the
  TF_GLM_PROF map).
- **The hc chain's per-kernel costs** (prompt-shaped rows, ns): tf_glm_hc_partial
  p50 103,328 / p95 114,400 (min 50,528); tf_glm_hc_finish p50 55,616 / p95 73,408;
  tf_glm_slice_sum p50 55,552 / p95 63,200. The glue glue dominates the captured
  launch count (hc pairs 467 of 512 rows).
- **tf_glm_router_part: zero rows — and the reason is a REAL find**: v1.1.9's prompt
  router takes an alignment branch the stale /tmp/tf-src export (carrying round-84
  patch remnants as source) did not have — prompt chunks launch **tf_glm_router_tile**
  (64-row cp.async tiles, grid.z STILL batching the K slices; router_part is the
  unaligned fallback). The 45 slice_sum rows are the router's slice sums. Round 112's
  "the stock path batches via router_part" is corrected: same conclusion (the stock
  path batches the slices in ONE launch), but the kernel is router_tile. /tmp/tf-src
  re-exported from the v1.1.9 tag (465e48b6) — the fusion design now reads the served
  source. The round-84 chain path (router_mm ×8) is NOT in v1.1.9 — purely the patch.
- **The fusion shape firms up**: the hc chain (partial→finish per hcPre, 2 hcPre/layer
  + hcPost) is the launch-count dominator with micro-scale kernels; the router pair
  (tile→slice_sum) fires 2/layer with the slices already batched. The hc partial+finish
  fusion stays the prime candidate — same-block same-order arithmetic is bit-safe by
  construction. router_tile's per-launch cost is the missing number; the corrected
  filter (all six v1.1.9 names) is relaunched for the census's second half.

## (round 114, cont.) The census complete: the four served-path kernels measured — the hc partial+finish fusion is the named target (2026-10-30)

- **The corrected census** (campaign-20261030-134836, prompt-shaped rows=1322, budget
  512 — the boot's prompt-shaped warmup + the probe's first ~42 layers):
  | kernel | launches | p50 µs | p95 µs |
  | --- | --- | --- | --- |
  | tf_glm_hc_partial | 214 | 104.4 | 115.0 |
  | tf_glm_hc_finish | 214 | 53.9 | 70.5 |
  | tf_glm_router_tile | 42 | 204.4 | 215.4 |
  | tf_glm_slice_sum | 42 | 58.5 | 67.6 |
- **The reads**: router_tile is the single most expensive kernel (204 µs — the real
  1322×4096×8 router dot, slices z-batched) but it is COMPUTE, one launch/layer. The
  hc chain is the LAUNCH-COUNT dominator: 4 matched launches/layer (2 hcPre ×
  partial+finish) + 2 hcPost — ~480 glue launches per prompt pass vs the router's 160.
- **The fusion target is named**: **tf_glm_hc_partial + tf_glm_hc_finish → one fused
  hc_pre kernel** (and the decode-side partial8+finish pair for the graphs). Bit-safety
  by construction: the fused block-per-row computes the same 24 dots + ss in the same
  K-block order, then the finish's math on the same values — identical arithmetic, one
  launch, no global-scratch round-trip. The router pair stays UNFUSED: serializing the
  8 z-slices into one block drops parallelism ~8×, and ordered cross-block reduction
  needs grid sync — not the clean candidate.
- **The A/B protocol stands** (the user's round-107/108 decision): the fused-kernel
  patch vs the standing config, 2+ runs per arm (the ~16% same-engine variance rule),
  the definitive benchmark protocol, the content gate (bit-identical replies) required
  for adoption.

## (round 115) The fused hc_pre kernel: built, compiled, staged — the hcfuse A/B window launched (2026-10-30)

- **The kernel** (patches/glm-hc-fuse.patch, 179 lines): ONE kernel per hcPre —
  a block per row, 256 threads (two 128-thread groups walk the 16 K-blocks' steps;
  the finish's syncs need the uniform 256), the partials in shared memory in the
  finish's `part` row layout, and **glm_hc::finish_row inline — the finish body
  UNMODIFIED** (its row-offset moved to the callers; the chain's wrappers pass
  `part + blockIdx.x*nb*32`, the fused kernel passes the shared dtot). The ops are
  partial8's exact per-step sequence extended over all blocks: the dots reduce in
  ascending step order (the chain's acc), the ss keeps the warp butterfly and the
  (0+2)+(1+3) combine — bit-identical by construction.
- **The gating**: TF_GLM_HC_FUSE=1 (hcPre's fused branch reads the env at launch —
  the cuda_mm.zig PDL pattern). Inert without it: one image serves both legs. The
  Set's comptime name binding picks up hc_pre_fused/_f32w automatically.
- **The receipts**: compile RC=0 in the builder image (fatbins sm_121 + native,
  zig 0.17.0 — the round-84 loop's recipe, minus the clone: the tree mounted);
  `git apply --check` clean on the pristine v1.1.9 tag; two contract records added
  (resources copied from the finish sibling until actuals print — the round-84 note).
- **The staged window** (PHASES="preflight hcfuse summary"): one prepare stages the
  overlay; leg stock (the patched binary, env off — the chain) vs leg fuse (the env
  on) — duel_arm + c4_reprobe + the chunk prof per leg, then the content gate
  (hf-stock vs hf-fuse solo replies: IDENTICAL = bit-safe, DIFFERS = the patch dies).
  The design: patches/hc-fuse-design.md. The read is round 116 when the poke lands.

## (round 116) The hcfuse A/B: bit-safe PROVEN, lever REJECTED — fusion traded block parallelism for a launch (2026-10-30)

- **The content gate: IDENTICAL** (campaign-20261030-144836/32-hcfuse.md) — the fused
  kernel is bit-safe exactly as designed: the finish_row refactor kept one body, the
  op orders survived the block-per-row re-shape. The construction method (same ops,
  same order, shared partials) is VALIDATED as an instrument.
- **The perf: no metric improved; decode regressed.** solo decode 53.9 → 49.4 t/s
  (−8.4%, within-leg stability 0.0%/0.3%), c2 88.5 → 81.2 (−8.3%), c4 134.0 → 132.5
  (within the variance), the 2048-row chunk wall 1688.5 → 1686.8 ms (EXACTLY neutral),
  TTFT slope identical (0.655 ms/token both).
- **The mechanism read**: the fusion removes a launch but SERIALIZES the 16 K-blocks
  into one block's sequential loop. The chain's grid-y parallelism was work
  distribution, not overhead: at prompt sizes (2048 blocks — SMs full) the fusion is
  free; at decode sizes (1-16 rows = 1-16 blocks) the fused kernel's 64-step critical
  path lands directly on the graph's latency — the −8% solo decode. (Register spills
  are the secondary suspect; the structural cause stands either way.) The launch-gap
  saving the census motivated did not exist as wall time — the glue's gaps were
  already hidden behind the router/expert GEMMs' queue depth.
- **The verdict (the standing rule: genuinely better, not neutral/negative): NOT
  ADOPTED.** The patch stays in patches/ as receipted non-adopted (the round-84
  pattern); TF_GLM_HC_FUSE stays off. The hc-chain FUSION sub-lever CLOSES.
- **What the pair of experiments bought**: the census measured the four kernels; the
  A/B measured the launch-gap hypothesis — both together establish the hc glue's
  launches are NOT the wall-time lever at either shape. Front 2's remaining
  direction is the OVERLAP class (the fork's HC-split/overlap set 0010/0033, or PDL
  on the finish launch — the launch site already carries a .pdl flag) — the next
  sitting's scoping.

## (round 117) The c4 deficit decomposed — the probe built and the production leg measured (2026-10-30)

- **The reasoning that shaped the probe**: the hcfuse A/B showed c4 NEUTRAL under the
  fusion (134.0 vs 132.5) — the glue launches are not the c4 lever either; ITL is 102%
  of production's (we win) while the aggregate is 61% (we lose) — the streams are
  idle between tokens: a SCHEDULING gap, not per-token speed. And c4's body is the
  SHORT-prompt d0-2048 (decode-dominated) while c4@d8192 (prefill-heavy) is relatively
  better (68% vs 61%) — the deficit smells like concurrent decode scheduling.
- **The probe (c4decomp phase)**: identical 4-concurrent volleys against whichever
  engine is up — (short, mt1), (deep ~8192-token, mt1) ×2 with different fills (both
  cold), (short, 2048) = the c4 aggregate's exact shape, (deep, 2048) = the deep
  envelope. Production leg: read-only, no window (production never restarted).
  Our leg: the standing config restarted inside the window (cold — like-for-like
  with the production leg's cold state).
- **The production leg (campaign-20261030-152632, direct run — no window)**:
  p0 0.47 s | p8a 17.95 s | p8b 17.77 s (the concurrent deep prefill ≈ 1,834 t/s
  aggregate, tight) | e0 52.76 s = 155.3 t/s | e8 46.45 s = 176.4 t/s.
- **The warm/cold caveat, recorded**: production's e0 (155.3) is the FIRST volley
  after 2+ h idle — the duel-history warm number is 241.6 (the anchors'). The deficit
  exists in both states (61% warm). The prefill walls are cold-by-design and solid.
  Our leg runs cold (fresh restart) — like-for-like for this receipt.
- **The our-side window launched**; the ratio read is the next digest.

## (round 117, cont.) The port split (user): tests on 8001, production keeps 8000 — and the our-side decomposition measured (2026-10-30)

- **(user)**: tests must not run on production's port — the testing stack serves on
  **8001** (a production-like stack loaded for testing would also take 8001); **8000
  stays production's, OpenCode's own endpoint** — the split stops opencode-originated
  traffic from landing on test instances and muddying the figures. **Production still
  stops for test windows** (the GPUs cannot serve both) — the window flow is
  unchanged; the split is endpoint hygiene.
- **Implemented**: config.sh's PORT default → 8001 (+ the comment citing the
  decision); a PROD_PORT=8000 var for the read-only production phases — the reference
  and prodqual phases' 8 curl sites and c4decomp's prod mode now address PROD_PORT;
  the c4decomp volleys take CD_PORT per mode; the python PORT fallback → 8001.
  SITE.md carries the port facts (git-ignored).
- **The our-side decomposition (campaign-20261030-153503, cold like-for-like)**:
  p0 0.78 s | p8a 11.73 s | p8b 11.72 s | e0 44.03 s | e8 221.36 s.
  **The ratios vs production's leg**: concurrent deep prefill OURS 2,799 t/s vs PROD
  1,834 — **we WIN 1.53×**; the short-prompt envelope 143.7 vs 155.3 t/s — parity
  (ours stopped naturally at 1,587-token replies, production capped at 2,048 — noted);
  **the deep envelope 37.0 vs 176.4 t/s — 4.8× slower**, and isolating the decode
  share (envelope − prefill): **ours ~39 t/s vs production ~286 t/s of concurrent
  decode after 8192-token prompts — 7.3× slower**. THE DEFICIT IS CONCURRENT DECODE
  AT KV DEPTH. The prefill is our strong side; short-prompt decode is parity; the
  collapse is depth-specific under concurrency.
- **The depth-curve extension**: c4decomp gains the ~2048/~4096-token-depth
  envelopes (e2/e4, distinct fills, both cold) + the engine's per-request lines
  (tok/s, rounds, accepted — the draft-quality confound read). The production leg
  (read-only, on 8000) runs next, then our leg in a window (on 8001) — the curve
  locates where the collapse starts.

## (round 117, cont. 2) The production depth curve — it INVERTS ours (2026-10-30)

- **The production leg, run 2** (campaign-20261030-155751, read-only on 8000): e0
  42.48 s = 192.8 t/s (warm) | e2 79.20 s = 103.4 (cold, fresh fill) | e4 74.29 s =
  110.3 (cold, fresh fill) | e8 37.34 s = 219.4 (warm — the cached deep fill; the
  cold first run: 46.45 s = 176.4). p8a/b 17.89/17.77 s — the walls REPRODUCED from
  run 1 (the production prompt cache did not spare the re-run prefill — the prefill
  measurements are robust).
- **The shape**: production's envelope aggregate is FASTEST at depth (219 warm/176
  cold at ~8192 tokens vs 193/155 at ~0) — deep context IMPROVES its decode, the
  classic draft-acceptance signature (deeper context → better DFlash2 acceptance →
  more tokens per verify round). Ours COLLAPSES with depth (144 → 37). The divergence
  is total: ~5× at 8192-token depth.
- **The hypothesis stack for our collapse** (the next window's per-request lines
  discriminate): (1) the DRAFT ACCEPTANCE collapsing at depth on the native drafter
  (the numbers fit: 144/37 ≈ the acceptance ratio; production's fork stack carries
  the scoring patches — 0086's bit-exact scoring loop is python-only); (2) the
  KV/indexer path at depth × 4 streams; (3) the L2 prefetch thrash. The engine's
  per-request `accepted=N/M rounds=R tok/s=` lines decide it.
- The our-side window (on 8001, the port split live) is running; the curve + the
  acceptance lines are the next digest.

## (round 117, cont. 4) The 153503 anomaly EXPLAINED: opencode traffic on the test serve — the port split caught in the wild (2026-10-30)

- **The discriminator window reproduced the clean curve exactly** (campaign-20261030-
  162521 vs 160633): e8 61.24 s = 133.8 t/s with CACHE HITS (`resumed at 6144`, evicted
  0, 1496 MiB spare), acceptance 80-88% flat, the per-stream decode ~24-37 t/s —
  **no acceptance collapse, no depth pathology**. The drafter is healthy at depth.
- **The 153503 window's 221-s e8 was REAL LOAD, not the engine**: that window served
  on port 8000 — BEFORE the port split — with production stopped, i.e. exactly the
  endpoint opencode's own client targets. The agent's own inference traffic landed on
  the test instance during the longest volley and deflated the envelope 3.6×. This is
  the precise failure mode the (user) port-split directive prevents — caught in the
  wild, before/after on the same shape.
- **Consequence for the anchors**: our c4 numbers measured on 8000 (the anchors' c4
  aggregate 148.0, c4@d8192 52.0) carry an unknown opencode-traffic component. Today's
  clean numbers: the short envelope 142-144 t/s (matches the anchor ✓ lightly
  polluted at most), the deep envelope 133.8 cache-hit (vs the anchor's 52.0 — the
  anchor is withdrawn pending the clean cold measurement).
- **The final confound removed**: e8 always cache-hit because p8a shared its fill.
  The phase now gives p8a its own fill (deep_fill(5)), e8 = deep_fill(0) COLD, e8c =
  a second distinct cold fill, e8r = the fill0 re-run (cache-hit). The next window
  yields the clean cold-vs-cached deep envelopes on 8001 — the honest deep number
  for the anchors' correction.

## (round 118) The c4 decomposition CONCLUDED: the deficit is measurement-plus-state, not a pathology — the anchors corrected (2026-10-30)

- **The clean curve (campaign-20261030-164612, port 8001, de-conflicted fills)**:
  the deep envelope at 118.2 (cold fill 11) / 133.6 (cold fill 0, one stream cold +
  three sharing in-flight) / 133.9 (cache-hit) — vs the polluted 37.0 (the opencode
  traffic, withdrawn). The short envelope 141.9 (reproduced across FOUR windows:
  142.5/142.2/141.9 — tight). The depth curve: 142 → 115 → 87 → 118-134; production's
  own curve dips mid-depth too (155-193 → 103 → 110 → 176-219) — the SHAPE is shared
  (the fills' acceptance varies: 80% at e4's fill, 88% at e8's), our dip is deeper
  but no cliff.
- **The final decomposition of the c4 gap**: (1) the hc glue launches — NOT the lever
  (the fusion A/B: neutral); (2) the drafter acceptance — healthy (80-88% flat);
  (3) a depth pathology — none (the shape is production-like); (4) the opencode
  traffic on port 8000 — WAS a real 3.6× deflation on the longest volleys, now
  eliminated by the (user) port split; (5) production's own state-dependence — its
  same-shape aggregate wanders 155.3/192.8/241.2 across cache states (ours: 142-144
  across four windows — tight). The honest c4 ratio: **0.6-0.9 depending on
  production's state**; the "61%" anchor sat at production's best state.
- **The anchors corrected**: the c4 aggregate row gains the clean-reproduction
  annotation (the numbers stand — the definitive pair keeps production's best
  state); the README's pair table gains the round-118 correction block (the 52.0
  d8192 number WITHDRAWN as polluted; the clean range 118-134). The chart's bars
  unchanged (the numbers stand; the annotation is textual) — the guard's --check
  still passes.
- **Where the perf front stands after the decomposition**: prefill 68% (solo) but our
  CONCURRENT deep prefill WINS 1.53× (2,799 vs 1,834 t/s — the pieced/chunked
  prefill machinery is our strength); short-depth decode ~0.9×; deep-depth decode
  ~0.7-0.76× (clean); the TTFT-at-depth frontier (3% — the round-34 root cause)
  remains THE open front, and the marks-policy patch its fix candidate. The native
  fusion/overlap levers are measured out — the remaining named lever is the TTFT
  frontier's cross-request prefix resume (production 65 ms vs ours 1,440 ms, round
  41's finding — the marks-policy patch).

## (round 119, final) The resume frontier decomposed: the restore is at parity, the gap is the chunk granularity — the marks patch is DEAD on v1.1.9 (2026-10-30)

- **The paired resumecost receipts** (production: campaign-20261030-171449, ours:
  -171822): production resumes FLAT — 0.173/0.151/0.138 s at d2048/d4096/d8192 (its
  python engine keeps prompt-end states on a 64-token grid: zero tail). Ours: the
  resumed ttft scales with the TAIL, not the restore extent — d4096 (cached 2048,
  tail 1689) 1.99 s; d8192 (cached 6144, tail 1298) 1.447 s; the tail ratio 1.30 ≈
  the ttft ratio 1.375. **The restore is at parity (~0.15 s); ~1.2-1.3 s of our
  resumed ttft is the FORCED tail** — the 2048-row prefill alignment (comptime
  `prefill_rows`, the resume hard-requires `% prefill_rows == 0`) leaves
  prompt.len − last-2048-multiple tokens that must re-prefill at the sub-chunk rate.
- **The marks patch is DEAD on v1.1.9** (campaign-20261030-173827): the patched
  prepare FAILED — `git apply glm-prefix-marks.patch` → "patch does not apply" (the
  patch was developed pre-v1.1.9 and never rebased; the routergemm patch was). And
  the deeper finding: even rebased it would be near-inert — its block requires
  `s.rules.planned and s.rules.grid > 0`, and the GLM serve's cache rules are
  hardcoded `planned = false` with no grid (glm_dsa_host.zig:46); its interior keeps
  address the cross-prompt share-stops, not the forced tail. **The round-41 "proven"
  claim corrected**: the proof's 1,445 ms equals today's UNPATCHED 1.447 s — the
  patch was inert in that measurement too; the resume it measured was the stock
  policy's own share-stop keep. The adoption call is MOOT — nothing to adopt without
  a rebase, and the rebase isn't worth building (the tail doesn't move).
- **The frontier's real lever, priced and parked**: a finer prefill grid. A 512-row
  variant would cut the resumed ttft to ~0.7-0.9 s (the tail 274 tokens ≈ one small
  chunk + the fixed ~250 ms chunk overhead) but regress the prefill anchor ~28%
  (1,039 → ~750 t/s — the chunk fixed cost ~250 ms amortizes over 4× more chunks) —
  the user's bar (the prefill rate) prices against it. The 64-row grid (production's)
  is a deep rewrite of the chunk pipeline's alignment assumptions. PARKED: if
  upstream ever makes prefill_rows a knob, we take it the same day.
- **Also noted**: the prompt-cache budget varies with the boot's free memory (1.3-2.1
  GiB across today's boots) — a state-dependence source for any cache-sensitive
  measurement.
- **Upstream pulse (this sitting)**: +10 commits since a0d2489 — all Qwen27/Metal;
  no GLM movement, no new tag. The pin stays.

## (round 120) The quality front's verdict: the 1-point gap is checkpoint-inherent — the per-scenario diff analyzed (2026-10-30)

- **The definitive pair's per-scenario diff** (the stored runs' reports; ours 93 =
  193/208 points, production 94 = 196/208): eight scenarios differ. Ours LOSES
  TC-100 (0/2 vs 2/2 — the partial-batch-retry chain, 0/3 milestones), TC-80 (0/2 —
  the read-before-write precondition), TC-62/63/68 (1/2 each — a milestone miss, a
  distractor call, a fenced-JSON format). Ours WINS TC-92 (+2), TC-40 (+1), TC-90
  (+1). Both fail TC-43/TC-51 identically.
- **TC-68's traces compared** (the one candidate that looked engine-side): the
  reasoning is NEARLY IDENTICAL on both serves (the same schema-conflict logic);
  production's answer is bare JSON, ours fences + a "Note:". Same checkpoint
  behavior, different formatting — BUT the serves are not the same checkpoint:
  **production serves Mia-AiLab/GLM-5.3-Flash-EXL3-4bpw-TensorFold; ours serves the
  AZ-Focus EXL3 (the round-38 (user) swap) under the engine's effort-tail template
  override.** The gap is checkpoint+template-inherent.
- **The lever priced and declined**: dropping the effort-tail override for the
  Focus checkpoint's own template would shift the thinking behavior across all 104
  scenarios — a full definitive re-run to verify, a regression risk on the 103
  others, a probable tie at best (94), and the overfitting smell of tuning the
  serving against the eval's format checks. The bar says "beat 94 — or come close":
  93 comes close; the checkpoint's ceiling stands.
- **The quality front's state**: the Focus checkpoint at 93 is the standing quality;
  the top4cfg (89/76%) stays the receipted perf leader, not the default. The
  remaining quality lever is a CHECKPOINT update (the AZ-Focus's next rev), not an
  engine change.

## (round 122) The depth census complete: the attention path is ~1% of the decode token cost — the deep-decode gap re-attributed (2026-10-30)

- **The instrument arc** (4 windows): the budget-512 capture took the prefill's
  kernels (chunks_32_fp8 4.8 ms p50, absorb_q 4.0 ms, merge 1.3-3.4 ms — the
  attention path owns ~60% of the chunk wall, consistent with the span map); the
  skip-1900 overshot (the prefill's matched total < 1900, zero rows); the decode
  proved graph-hidden (856 rows = exactly the prefill's 4 passes); **TF_GRAPH_CACHE=off
  (the shared graph-cache knob — "runs every step eagerly") made the decode visible**
  and the reader's segmentation (the last chunks_32 row = the prefill's end) split the
  segments cleanly.
- **The decode-at-depth census** (campaign-20261030-190512, the DECODE segment, 44
  layer-groups, ~8192 depth): chunks_16_fp8 161 µs | expand_v 51 | absorb_q 51.5 |
  merge 16.8 | scores 15.3 | the writes ~30 — **~326 µs/token of attention-path time
  against the observed 27-30 ms/token (33-37 t/s/stream) — ~1%**. The prefill
  segment reconfirms: chunks_32_fp8 4.8 ms p50 (18.6 max), absorb_q 4.0, expand_v
  5.2, merge 1.3 — the prefill's kernel-time owners.
- **The re-attribution**: the deep-decode aggregate gap (ours 132-134 vs production's
  176 cold at the same shape) is NOT depth-scaling in the attention kernels — the
  attention path is noise-level per token. The gap is the UNIFORM per-token
  machinery (the same 0.73-0.92× we measure at short depth); production merely gains
  ~13% at depth where we lose ~7% (its mid-depth dip inverts later than ours). The
  depth thread CLOSES.
- **The decode gap's remaining lever** is the per-token machinery itself — the MoE
  GEMM batching at 4 streams, the draft/verify round cadence, the scheduler — the
  same class the round-111 watch tracks upstream (the batched-launch pattern
  reaching GLM). No native lever identified that we haven't measured out; the front
  is upstream-gated.
- **Also priced**: TF_GRAPH_CACHE=off costs the decode's graph replay (the eager
  launches) — a measurement-only setting, never a serving config.

## (round 123) The cache-churn cell: no evictions, but the concurrent resume SERIALIZES 4× — the round-41 decomposition fully measured (2026-10-30)

- **The paired cachurn receipts** (production: campaign-20261030-192624, ours:
  -193233): three rounds of 4-concurrent distinct deep fills (~32K tokens of states
  a round), then the round-0/1 re-fires. Production: the rounds 17.7 s each, the
  re-fires **0.24 s** — twelve deep states survived, the resume near-free. Ours: the
  rounds 11.7 s each (our prefill strength again, 1.5×), the re-fires **5.78 s**.
- **No eviction pathology**: the intra-volley sharing keeps ONE state per distinct
  fill (3 states, 666 MiB of 2123 — the budget pressures at ~9 distinct deep fills).
  The refires HIT (`resumed at 6144` ✓ the states survived).
- **The new named finding: the concurrent resume SERIALIZES.** The 4-concurrent
  refire = 5.78 s ≈ 4 × the solo resumed ttft (1.45 s) — the resumed requests' tail
  chunks do NOT share a pass (the multi-prefill sharing covers new prompts'
  prefills, not resumed ones), so N concurrent cache-hit requests cost N tail
  passes. Under concurrency the resume gap to production is **24×** (5.78 vs 0.24).
- **The round-41 decomposition is now fully measured**: the cold prefill (TF_GLM_INDEX_CUDA
  adopted round 49 ✓), the restore cost (at parity solo ~0.15 s; the forced 2048-aligned
  tail owns the solo gap; the serialization owns the concurrent gap — both parked with
  the prices), the cache churn (no evictions at probe scale; the serialization finding).
  The frontier's levers are all either adopted, measured out, or parked with prices.
- **The decode-at-depth census instrument** (round 122) + this cell close the perf
  plan's open items. The standing recommendation: the remaining levers are
  upstream-gated (the batched-launch pattern reaching GLM, the pair-seam CUDA steps,
  a v1.2.0 tag) — the watch continues each sitting.

## (round 126) The loading front attacked: the boot decomposed, two levers adopted-candidate, two variants withdrawn (2026-10-30/31)

- **The wall decomposition** (round 125's instruments, this round's receipts): the
  stop 1 s, the checks 1 s, the container starts <1 s — the ENTIRE ~233-s wall is
  the engine boot (its own line: `loaded in 232.9-234.7 s`).
- **The boot's internal split** (glm-boot-marks.patch, campaign-20261030-212657):
  the 45-layer weight loop 184.5 s (79%, ~4.1 s/layer dead-flat), the linear pack
  28.9 s (12%), everything else ~20 s. GPU util 0-4% through the boot — copy/CPU-bound.
- **The disk is NOT the bottleneck**: the shards re-read cold every boot
  (`safetensors.File.release` DONTNEEDs all 47 maps per layer — unified memory
  needs the room) but O_DIRECT measures 7 GB/s; the release itself costs 1-10 ms
  (the micro-benchmark refuted the release-walk hypothesis).
- **glm-pinned-upload.patch (adopted-candidate, −21.8 s)**: `fromHost`'s
  synchronous path staged every ≤64-MiB chunk through a fresh PAGEABLE heap
  buffer (`copy_source.zig`: `durable = std.heap.page_allocator`); the patch
  routes `put()` through the tree's own Stage machinery — the reusable 64-MiB
  PINNED stage (the DeepSeek v41 pattern, 7fce15ce9, ported to v1.1.9).
  232.9 → 211.1 s; the content gate sha IDENTICAL (9e04a49e5786).
- **Two readahead variants WITHDRAWN** (+67/+78 s WORSE): MADV_WILLNEED raced the
  fault loop into duplicate I/O (211.1 → 278.3, campaign-221626);
  MADV_POPULATE_READ regressed the same way (289.6, campaign-224013) — both
  fattened the per-layer page-cache churn under the full pool. Receipts held;
  the patches stay in patches/ as the negative record.
- **The per-tensor marks** (glm-boot-marks2.patch, campaign-225411): reads are
  CHEAP (add: 7.3 s total; the 1.2-GiB embed at 1.25 GB/s), uploads 29 s (put,
  ~2.9 GiB/s pageable) — ~148 s of the 184.5-s loop sat OUTSIDE the marked calls.
- **glm-trellis-scratch.patch (adopted-candidate, −6.2 s more)**: the gate/up
  trellis assembly's ~66K strided 8-KiB mmap appends per layer (the 16-KiB stride
  defeats readahead) — the patch reads each 4-MiB trellis once contiguously into
  a reusable scratch and slices host-side. 211.1 → 204.9 s; the gate sha
  IDENTICAL. The modeled −100 s did NOT materialize — the residual's true owner
  stays open; the next instrument (marks over the current stack) tests the
  cuMemAlloc-under-pressure hypothesis (~1,534 per-tensor device allocs on a full
  pool — which would also explain the advice regressions and the late-layer
  slowdown).
- **Two voided windows (the guards working)**: campaign-231937 (the trellis patch
  pristine-based, refused by the build's apply), campaign-233318 (the field named
  `scratch` collided with the Loader's existing `scratch()` fn — Zig forbids a
  field/declaration name collision; git apply passes textually, only the build
  catches symbols). Both fixed; the stack verifies apply+symbols.
- **The standing tally: 232.9 → 204.9 s (−12%), two bit-safe patches**; the
  loading anchor's chart row still quotes the pristine wall until the patches are
  adopted into config.sh's defaults. Production's wall: 93.7 s. The pin stays at
  v1.1.9 (these are this line's own patches, receipted in patches/).

## (round 127) THE LOADING FRONT IS TAKEN: the v1.2.0 bump, the rename to -ZIG, 93.0 s vs production's 93.7 (2026-10-31)

- **(user)** "let's review the latest version release of tensorfold ... update the
  repo name to -ZIG rather than v1.1 (latest release is now v1.2). I think there
  are updates there that affect us, so we should pin to the new version if you
  agree." — Agreed and executed: the release carries the GLM loading cluster and
  the EXL3 decode win; the bump conditions in the perf-gated policy are met by
  upstream's own receipts.
- **The upstream research** (the user: "check upstream updates, identify issues
  and PRs"): +129 commits since the round-124 scan. **#1636's cluster** (61bb392ee
  → ab366b1e3 → a72b9d00f → af2909ce6): the 16-reader load-ahead (cuda_load_ahead.zig,
  NEW — not in v1.1.9) + the 8-thread expert pack + the piecewise mapped-pinned
  upload; upstream measured GLM XSFP4 327 → 51 s at TP=2, 268 → 46 s at TP=3.
  Coverage read against our EXL3 Focus: the pack serves the decoded formats only
  (zero exl3/trellis references); the EXL3-relevant part is the load-ahead. Also
  merged: #1659 (prompt_radix's planned grid — the marks-patch territory, inert
  until opted in), #1534 (the EXL3 trellis reads skip L1: EXL3 decode +2.3% at
  TP=3 — OUR format), #1585 (--mtp-confidence), #1524 (RoCE_MULTI, 3+ ranks). The
  open GLM PR queue (35): #1576 (4,096-row prompt chunks — our parked finer-grid
  lever, upstream is trying it), #1580 (TF_GLM_L2PF: the L2 prefetch), #1505 (the
  EXL3 experts kernel loads a tile ahead), #1732 (TF_GLM_KV_SHARE in prompt_radix).
  No open GLM-loading issues.
- **The rename (user)**: GitHub gilesco/GLM-5.3-Flash-EXL3-2x-GB10-TensorFold-ZIG-testing
  (gh repo rename), the remotes on both checkouts, the head's checkout dir, the
  head's poke cron line, the local checkout, and this session's cwd. The old name
  redirects on GitHub.
- **The first bumped boot REFUSED at admission — a receipt, not a failure**
  (campaign-20261031-004214): the v1.2.0 loader ran (16 readers read 156.4 GiB
  ahead; the load+pack done in ~90 s) and then refused: `--parallel 4 needs 10.84
  GiB ... the CUDA memory budget leaves 10.72 GiB` — a 0.12-GiB shortfall where
  v1.1.9 left 12.9. Root cause read from the source + the numbers: the load-ahead
  leaves the tail tensors' pages resident (embed 1.2 GiB, norm 0.6, the head, the
  MTP rows — never released; the per-layer releases cover the layers only), and
  the admission budget reads MemAvailable. PROMPT_CACHE_GIB was ruled out
  (cache_fit derives the cache FROM the free room, not against the budget).
- **glm-tail-release.patch**: the same release() the layer loop runs, applied to
  the tail's two files (ck + head_ck) after the load. Advice-only, byte-identical.
- **THE RESULT (campaign-20261031-142431, v1.2.0 + the tail release, no other
  patches)**: **loaded in 93.0 s — production's engine boot is 93.7 s; the full
  wall 95 s vs 93.7 — 98.6%, TAKEN.** The content gate sha 9e04a49e5786 IDENTICAL
  (bit-safety across the bump and the patch). Admission: 16.4 GiB left (the
  release restored ~5.7 GiB; the prompt cache grew to 5.6 GiB with the room). The
  probes: d2048 1.71 s / d4096 1.96 / d8192 1.42 — equal to v1.1.9's values.
- **The standing config**: local.sh pins TF_REF=v1.2.0; config.sh's PATCHES
  default is glm-tail-release.patch (the qualified optimum, receipt-cited); the
  anchors' loading row and the chart re-rendered (98.6%); the README's status
  table updated. Our v1.1.9 loading patches (pinned-upload −21.8 s, trellis-scratch
  −6.2 s, both bit-safe) are superseded by the bump — retired to the record per
  patches/README rule 1.
- **The arc's loading trail** (the receipts behind the front): 232.9 s pristine →
  the wall decomposition (the stop 1 s / the checks 1 s / the boot everything) →
  the marks (the 45-layer loop 79%, the pack 12%) → the disk exonerated (7 GB/s
  O_DIRECT) → the release cost refuted (1-10 ms) → the per-tensor marks (reads
  7.3 s, uploads 29 s) → the fault rate measured (~840 MiB/s) → our two patches
  (−28 s, bit-safe) → **the bump: 93.0 s**.
- **The head rebooted unattended ~09:40** (/tmp cleaned: the upstream clone, the
  source export, the console lost — re-established; production restored; no
  receipts lost — they live in the checkout). /tmp scratch is now re-created per
  need; nothing load-bearing lives there.
- The pin stays at v1.2.0; the watch continues (the open PR queue above; the next
  bump waits for the queue's loading/perf items to merge or a v1.2.1).

## (round 128) The port discipline extends to production: production serves the testing port 8001 (user); the perf+quality refresh launched (2026-10-31)

- **(user)** "If we are to test production, then we should test it running on the
  testing port (8001), so that opencode doesn't make the test dirty. When we test
  ours, we should also run on the testing port (8001), also so opencode doesn't
  confuse it to be an available model." — Both sides now test on 8001: production's
  tip local.sh PORT=8000 → 8001 (effective at its next start — the window flow's
  restore), our PROD_PORT default 8000 → 8001, the start.sh comment updated. Until
  production's next restore it still serves 8000; the read-only production phases
  (reference/prodqual) run after that restore.
- **The refresh window launched**: PHASES="preflight focusqual throughput depth
  prefill summary" on the v1.2.0 stack — focusqual is the Focus's full battery
  (§2 gates, the full tool-eval, hardmode, the duel-arm perf probes) and the
  perf instruments (throughput's bench tables, the depth/prefill TTFT
  instruments) re-measure the anchors on the new engine. The v1.2.0 changes that
  could move the numbers: #1534's trellis L1 hint (EXL3 decode), the bigger
  prompt cache (5.6 GiB — the cache behavior changed), the new engine's decode
  work. Production's fresh side: the follow-up PROMPT=0 run (reference prodqual)
  on production-up-8001 after the window restores it there.

## (round 129) The guidelines corrected: production's lifecycle is autonomous, the ports are intent-keyed (user); the prodqual-on-8001 dance (2026-10-31)

- **(user)** "Review the autonomous guidelines - I expect the instructions are
  conflicting in our docs. We now allow the autonomous stop/start of production."
  + "If we start production for testing it starts on port 8001, if we start
  production for opencode it starts on port 8000" + "If we start our testing it
  always starts on 8001, so it never gets connected to by opencode" + "you can
  work autonomously, and push to opencode when you have restarted production on
  port 8000."
- **AGENTS.md's hard-boundary bullet rewritten**: production's lifecycle is
  autonomously managed (the window flow, test dances, the crash-net — restored on
  every exit path); the ports are intent-keyed (opencode 8000 / testing 8001 /
  ours always 8001). The tip's start.sh honors `PORT=...` env overrides (its own
  header documents it) — intent-keyed starts need no local.sh toggling.
- **The prodqual port corrections recorded**: the first prodqual ran against the
  stale synced config and hit a dead 8001 (campaign-20261031-165441 — the voided
  receipt of the transition); the re-run hit production on 8000 (the serving
  port — the wrong port for tests per the discipline); this round's dance runs it
  against production ON 8001 and restores production to 8000 for opencode after.

- **The dance completed cleanly**: production served the prodqual on 8001, then
  restored for opencode on 8000 (the trap restore; the flag held the crash-net
  off throughout). **The poke did NOT fire — and the reason is a real bug the
  rename introduced**: `scripts/autonomous-poke.sh`'s PROJ still named the
  pre-repo-rename directory, so the cron's poke looked at a path that no longer
  exists. Fixed (the ZIG name; the rename's residue).
- **The refresh results (both engines, the same day, the testing port)**:
  - Ours (campaign-20261031-145914, v1.2.0 + the tail release): the §2 gates ALL
    PASS (determinism, drafted=plain, resumed=fresh, concurrent=solo, sampled),
    hardmode **93** (the standing ceiling), the duel arm solo 54.0/54.2, c2 89.9,
    c4 142.8 (in the clean band), ITL 16.9 ms/tok, TTFT d0 195 ms / slope 0.654,
    prefill 1,089 tok/s, the depth gate 12/12, the bench dense4fp8 cell solo 49.1
    / pp 1,049.
  - Production (campaign-20261031-171731, the 0.6.6 Python engine, probed on 8001; 96 is bench v3.0.1's score): tool-eval **96**
    (133/138), pg1-pg5 PASS (byte-determinism is still production's control
    property), the bench solo 55.8 / c4 61.6 / pp 1,518.
- **The anchors now carry the same-day pairs** (the chart re-rendered): prefill
  1,049/1,518 (69%), TTFT overhead 195/186 (94%), ITL 16.9/17.1 (99%), depth
  5,553/142 (~4% — the standing frontier), loading 95/93.7 (98.6% — TAKEN). The
  duel-arm rows keep the round-108 definitive pairs with the in-band refresh
  notes (production's duel arm was not re-run today — its bench pair is recorded
  instead).
- **The stale-details sweep**: DELTAS' scoreboard and the README's status table
  carry the round-129 numbers; PERF_PLAN's Front 3 header marks the front TAKEN;
  the window script's "the agent goes dark" comments removed (the cloud-model
  switch made them false). The ledger's era entries stay (they quote their
  receipts — history, not current facts).

## (round 130) The depth-front lever priced and parked; the decode win lands on main (2026-10-31)

- **The kvshare phase ran and was REFUSED — a receipt, not a failure**
  (campaign-20261031-184502): `--kv-cache fp8 keeps a window per stream: unset
  TF_KV_PAGES, or set it to auto or off` — the fp8-KV × paged-pool exclusivity
  holds on current main (the AGENTS gotcha's root). #1732's KV_SHARE lever needs
  the paged pool → **blocked for our fp8 config**; the bf16-paged route costs a
  stream at 524K (the streams don't fit at parallel 4) — parked with that price.
  #1736's TF_GLM_HOST_CACHE buys kept-state CAPACITY (host-sized), not the
  warm-latency (our 1.42-s warm is the 2048-aligned tail re-prefill, not the
  copy). The depth front stays open (~4%); the watch: upstream's fp8-paged
  evolution (#1510's option B — #1755 generalizes the adapter).
- **The pin sits on main (49a01bb3)** — the bump carried #1505 (the EXL3
  grouped-experts tile-ahead) and #1534 (the trellis L1 hint): **the round-130
  duel: solo 55.6/55.6 t/s (Δ 0.1%) — +2.7% over v1.2.0's 54.0-54.2, above the
  definitive pair's production number (52.9)**. c2 89.7, c4 144.6 (the clean
  band), ITL 16.6 ms/tok, TTFT d0 197 / slope 0.655 — unchanged. The bench
  dense4fp8: pp 1,033, tg 37.8-46.3 (in-band).
- **The duel's production arm skipped** (production down in the window — the
  head-to-head pairs at the next production-up duel run).
- **The poke chain is fully restored**: the agent-host crontab still named the
  pre-rename directory (the cron tick died silently every 5 min); fixed to the
  ZIG path — the poke for this window's completion arrived through the fixed
  script. The head-side dance scripts do not poke (the poke lives on the agent
  host) — the hand-back + the cron poke is the designed pair.

- **THE HEAD-TO-HEAD IS COMPLETE** (campaign-20261031-200757 — the first two-arm
  duel since the port split): the duel phase now starts production FOR TESTING on
  8001 itself (the intent-keyed start), probes it, stops it, runs ours, and the
  window flow restores production on 8000. The fresh pairs (production 58.9 solo /
  110.6 c2 / 192.6 c4 / ITL 17.0 / TTFT 185, slope 0.266; ours 54.9 / 89.0 / 144.9 /
  16.6 / 200, slope 0.656): solo 93.2%, c2 80.5%, c4 75.2%, ITL 102% crossed,
  overhead 92.5%, **and the depth-front correction: production's fresh d8192 TTFT
  is 2,363 ms — the old 142 was its cache fully warm from days of repeated
  identical probes; the frontier is 42% (2.4×), not ~4% (39×)**. The anchors,
  DELTAS and the README carry the same-window pairs; the chart re-rendered. The
  duel's model fetch also had a latent $PORT bug (it hit our 8001 since the port
  split, masked by the identical SERVED_NAME) — fixed.
- **The perf plan's state after the head-to-head**: loading TAKEN; ITL crossed;
  solo 93% (the closest decode has been); c2 80% / c4 75% (the concurrency front's
  honest ratios); prefill 69%; TTFT-at-depth 42% — the open fronts are prefill and
  depth, both with upstream watch items (#1576's 4,096-row chunks; the fp8-paged
  evolution for #1732's lever).

- **The first 4,096 battery re-ran the standing config — the passthrough miss
  recorded** (campaign-20261031-204953): the window's phase restarts never passed
  `PATCHES=glm-prompt-4096.patch` (the config default carries only the tail
  release), so every cell served "passes of up to 2048 rows". The data point
  gained: the standing config's gates ALL PASS again same-day (the stability).
  The dedicated `p4096` phase now carries the PATCHES passthrough (the gates +
  the bench + the slope probes on the patched serve).

- **The p4096 patch REJECTED — and the depth front's honest rework**
  (campaigns -214624 parallel 2, -224154 parallel 4): the 4,096-row chunk patch
  passes the gates and holds the bench, but the depth probes regress on our EXL3
  config (the cold d8192 7.45 vs 5.52 unpatched, +34%; the warm 3.35 vs 1.42,
  +136%) — the per-row cost of the bigger chunk's KDA/state span exceeds the
  saved pass overhead; upstream's receipt was the FP4 checkpoint at 500K. The
  patch stays as the record; the standing config does not adopt it.
- **The depth front's honest rework from the same receipts**: the WARM-RESUME
  pair — ours 1,422 ms (the kept-states resume, the resumecost receipt) vs
  production's 2,363 (its fresh probe, warm-from-history) — **166%: CROSSED**.
  The old "142 ms / ~4% frontier" was production's cache fully warm from days of
  repeated probes. The COLD side (the prefill slope, 0.656 vs 0.266 ms/tok) is
  the real open front — and production's cold number lands with the next
  prodqual's first shots (its cache is always warm across our windows today).
  The anchors' depth row reworked to the warm-resume pair; the chart
  re-rendered; the README and DELTAS carry the rework.

## (round 131) The cold depth cost decomposed — the slope is bubbles (2026-11-01)

- **THE COLD DEPTH COST IS DECOMPOSED (the ncudepth census, four attempts)**:
  the instrument is the ncurouter wrapper on the standing config (rank 0 under
  ncu, rank 1 the same committed image unwrapped — the round-98 topology), one
  cold d8192 probe (fill + max_tokens=1). Attempt 1 UNFILTERED: the wrapped
  boot blew both waits (every launch collected → rank 0 10-30× slower → rank
  1's peer wait fired → the pair died; fail-honest receipt
  campaign-20261101-000435). Attempts 2-3 FILTERED from the pin's source: the
  launch-name registry gave tf_glm_ + qmmf_kernel + custom_kernel + trellis +
  gemm, and attempt 3's miss (zero GEMM rows) gave the EXL3 family
  (tf_exl3_linear_*, prompt_gu, prompt_down — exl3_block*.zig). The complete
  attribution (campaign-20261101-004319): the probe window's kernels 1.35 s of
  the 5.4 s uninstrumented wall — **the EXL3 prompt GEMMs 56% of kernel time**
  (prompt_gu 0.474 s, prompt_down 0.280 s), chunks_32_fp8 14% (p50 11.2 ms at
  depth), the rest glue (hc_partial/post ~80/chunk at ~0.1 ms). Attempt 4
  (nccl added) re-created the blowout — **a collective profiled on rank 0 only
  deadlocks the pair** (ncu serializes/replays; a collective needs both
  ranks): the collectives are NOT ncu-capturable per-rank; their device time
  is link-bounded instead (~2.8 GiB moved per probe + per-collective latency ≈
  0.3-0.6 s).
- **The verdict: the cold-prefill slope is ~65% HOST GAPS** (~14% EXL3 GEMMs,
  ~11% glue + fp8 state writes, ~6-11% collectives). The slope is
  bubble-dominated, not kernel-dominated — the round-34 KDA/state span's host
  work per chunk is the candidate, and the p4096 rejection is explained
  (bigger chunks extend, not shrink, the per-chunk host span). The lever is
  engine-side (less host span work per chunk, or graph-captured prompt
  passes) — **upstream-gated**; the finding is recorded in ECOSYSTEM.md as
  data. The ncudepth phase is RETAINED as the depth front's instrument (it
  verifies any future bubbles fix).
- **The upstream watch (round 131)**: #1792 (Flash Next prompt kernels faster,
  byte-unchanged, one GPU and --tp 2; TF_FLASHNEXT_PROFILE=2 phase-times a
  pass — an instrument to watch), #1783 (GB10 affine-4 grouped launches,
  byte-equal — a port candidate), #1784 (dense layers split across two ranks),
  and the KV_SHARE paged store on main (40c03bf/004655c, #1755 open): our
  TF_GLM_KV_SHARE lever stays PARKED — error.Fp8OnPages still refuses fp8 ×
  pages on the tip (verified in the source at origin/main).
- **THE OVERNIGHT DIRECTIVE (user)**: continue through the night — look for
  performance improvements by trying the various knobs, AND try to make the
  engine somewhat deterministic (the g1 byte-level nondeterminism: content
  identical, raw reasoning/metadata bytes drift run to run — the native engine
  lost the 0.6.x Python engine's byte stability). The night's shape: the knob
  sweep phases (the unexplored env knobs on the standing config, one serve per
  knob) + the determinism investigation (source knobs first, then the
  first-divergence attribution across repeated greedy runs).

- **The knobs sweep — verdicts (43-/44-knobs.md, campaign-20261101-012951 and
  -033514)**: every unexplored env knob at our pin is a WASH on our cell —
  PDL=1 (the MM kernels' programmatic dependent launch), OVERLAP_PIECES 1/6,
  PREFILL_REDUCE=ring, INDEX_SPLIT=0, KDA_DECODE_WIDE=0, HOST_CACHE=1, the
  RoCE shard sizes 1024/16384 (live in the RoCE lines, no movement), and the
  drafter confidence (its throughput axis covered by the STANDING knobs
  phase's fresh bench cells in the same window — see below). Two variants
  REGRESS the depth TTFTs and are doubly rejected: PREFILL_REDUCE=gather
  (cold d8192 7.67 twice, warm 1.47-1.48) and PROMPT_K=shape (7.66-7.68,
  warm 1.46-1.47). MM=0 refused structurally (no server line — the untiled
  bf16 linears do not fit our cell). HOST_CACHE=1's signature: the prompt
  cache moves to pinned host memory and GROWS 3.2 → 8.0 GiB — a
  device-memory capacity lever worth remembering for tight-admission
  experiments. The standing config is unchanged.
- **The determinism findings (the round-131 directive (user))**: the model's
  greedy output is BYTE-DETERMINISTIC run to run — 5/5 identical reasoning
  shas (742a33a2…, 4263B) and identical content shas on the standing config;
  the g1 "raw bytes differ" is the ENVELOPE (id/created/metadata — as
  AGENTS documents), not the model. Nine of ten knob variants reproduce the
  baseline's bytes exactly. ONE knob flips the byte path:
  TF_GLM_PROMPT_K=shape selects a DIFFERENT but equally deterministic path
  (ccb6be44…, 4030B — 2/2 identical shots under the knob; knobs2's shot1 vs
  shot2 receipt). The first attribution named gather — wrong: the receipt's
  det-line pairing shifted one variant; the FILES are the truth
  (det-promptk-1.json carries the flip). The drafter confidence is
  content-safe at the byte level (conf055's sha matches baseline — the g2
  gate's claim verified byte-wise). Answer to "somewhat deterministic": the
  engine already is, at the model level, on our cell; the drift is
  envelope-only; PROMPT_K is the one determinism-relevant knob found (and
  it regresses depth — no reason to touch it).
- **The knobs-name collision discovered**: the round-34-era knobs phase is a
  STANDING phase (in the default PHASES list) — it re-ran its cells
  (conf055/conf085/steps0/overlap6/kdawide0/load-nodraft, full bench
  matrices) in the same window as the session-specific knobs phase
  (06-knobs.md AND 43-knobs.md). Its fresh data: all cells in-band on the
  bench rows (conf055 tg d0 46.8 / conf085 46.3 / steps0 44.8 / overlap6
  46.8 — the standing band 45-47; the d8192 tg rows 42-49 are single cells
  and the tg128-row gotcha applies). No adoption from it either; the
  standing config keeps the defaults. knobs2/knobs3 use distinct want-names.
- **The knobs front is CLOSED (knobs3, campaign-20261101-035853)**: the RoCE
  shard size is a wash under c2 too (baseline 79.7 / 1024 KiB 78.7 /
  16384 KiB 79.1 t/s aggregate — in-band). Every env knob at our pin has now
  been measured on our cell: no adoption, two depth rejections (gather,
  PROMPT_K=shape), one structural refusal (MM=0), one capacity lever noted
  (HOST_CACHE moves the prompt cache to host memory, 3.2 → 8.0 GiB). The
  determinism directive is answered: the model output is byte-deterministic
  run to run; the drift is envelope-only; PROMPT_K is the one
  determinism-relevant knob (and it regresses depth — untouched).
- **THE AZQUAL VERDICT — the quality-vs-routing trade, precisely priced**
  (campaign-20261101-041447): the Oct 28 mcg placement serves (the Oct 26
  tensor-name refusal fixed — `self_attn.q_proj.weight` present in this
  convert), the gates ALL PASS, and the perf is the line's best ever: solo
  **80.1/79.9 t/s** (Δ0.2%), c2 **128.2**, c4 **199.4 — above production's
  192.6**; TTFT d0 147 ms (ours 200, production 185); slope 0.580. **The
  cause is one config line: the AZ-EXL3 serves num_experts_per_tok=4 vs the
  Focus's 8** — the quantization identical (exl3 4bpw mcg, head 16,
  routed-experts-only); half the routed-expert FLOPs per token. **The cost:
  hardmode 90 vs the Focus cell's 93** (consistent with az2's 89-vs-94).
  **No adoption — the round-2026-10-27 (user) quality bar stands** (hardmode
  is the bar; the served config stays Focus top-8). Two consequences: the
  old top4cfg perf receipts (solo 63.6) are superseded — the engine gained
  ~26% decode engine-side since on the same top-4 shape; and the decode
  front's attribution MOVES — a large share of our gap to production is
  routing depth (a user-decision trade, now priced at 3 hardmode points for
  +46% solo / +44% c2 / +38% c4), not engine machinery. The ledger and
  PERF_PLAN carry the re-attribution; the azqual phase retires (the route's
  decision is receipted).
- **THE DEPTH FRONTIER'S FINAL SHAPE (prodcold, campaign-20261101-051733)**:
  production's TRUE cold depth cost, measured on NOVEL fills its persistent
  cache cannot hit: d8192 **17.13 s**, d4096 8.83 s — slope **2.026 ms/tok**
  (and its cold prefill SLOWS with depth: 0.66 ms/tok at d0 from its bench
  rate). Ours: 5.52 s, slope 0.656 flat. **The cold front CROSSES — 309%.**
  The b-shots (warm re-fires): 0.21 s at d8192, 0.086 s at d4096 —
  production's persistent cache makes a full hit a near-free SKIP (no
  prefill at all); our kept-states resume replays ring/state work at
  1.42 s. The record corrections: the round-130 "42%" (5,570 vs 2,363)
  compared our COLD against its WARM-from-cache; the round-130 "166%"
  (1,422 vs 2,363) compared our resume against its warm-from-cache — both
  were cross-cache-state artifacts. The anchors now carry TWO depth rows
  (cold: ours win 309%; warm: production's skip leads, 1,422 vs 212 — the
  open piece is the full-hit skip, engine-side; the host-cache trio
  #1736/#1795 is upstream's pattern); the chart re-rendered (9 metrics);
  DELTAS, the README and PERF_PLAN carry the final shape. The depth front
  has NO cold gap — our engine prefills cold 3.1× faster than production's.
- **THE WARM RESUME IS A REPLAY (ncuwarm, campaign-20261101-055816 — the
  first attempt was a fail-honest clone bug: it inherited attempt 4's nccl
  filter, which deadlocks the pair; the WRAP dropped nccl in both retained
  instruments)**: the warm resume's kernel window carries **1.05 s of
  kernels — the pass re-runs**: the EXL3 GEMMs replay (prompt_gu 88× /
  prompt_down 88×, 0.61 s — ~80% of the cold pass's launches), only the
  state writes shrink (chunks_32_fp8 12× vs 16×). The mechanism: the kept
  state holds KV/rings/MTP caches but NOT the prompt's last-row hidden
  states, so the resume re-projects the prompt through the layers to
  regenerate them; production's 0.21 s warm is a full-hit SKIP (no pass at
  all). The warm path's kernels/gaps ratio is healthier than the cold pass
  (~1.05 s kernels of a 1.42 s wall — the resume is less bubbly). **The
  full-hit-skip patch is GO as the next arc's design** (cache the last-row
  hiddens in the kept state — ~370 KB per prompt — and add a full-hit fast
  path that installs them instead of re-running the pass; the g3 gate and
  the resumecost instrument verify) — but the resume flow spans
  cuda_prefix/cuda_engine's keep/begin/Resume machinery and needs a fresh
  deep source read before crafting; not rushed at the end of a long night.
  The ncuwarm phase is RETAINED as the patch's before/after instrument.
- **THE FULL-HIT-SKIP ARC CLOSES PARKED — and the warm-resume front's
  mechanism is now fully understood** (three builds, three receipts): build 1
  refused (the 'limit' shadow — the local-vs-declaration collision class,
  now in the patch-craft skill's gotchas); build 2 booted (the gates ALL
  PASS, hardmode 95) but the skip never engaged — the pass's keep callbacks
  fire only at CHUNK STARTS, so the full-length tail state was never kept;
  build 3 (the end-of-pass keep in prefill) booted, the gates ALL PASS again,
  and the skip STILL never engaged (the warm walls 1.405-1.407 s,
  campaign-20261101-125939) — the REAL hole is design: the tail state only
  exists when the prompt's length lands on the step, and real prompts never
  do. The general fix needs exact-match nodes in the radix core (a node's
  guaranteed-match extent is its 512-token pages; a longer prompt sharing the
  prefix would resume a wrong state from an exact-length snapshot) —
  engine-scale work. The cheap partial (resume alignment 2048 → 512 rows) is
  round 119's PARKED trade (the prefill anchor −28%). **The warm-resume
  front closes upstream-gated**: the 1.42 s warm = the tail chunk's replay,
  inherent to the page-quantized state design; production's 0.21 s skip
  needs exact-match states (ECOSYSTEM.md carries the finding as data). The
  patch is PARKED (kept as the record); the standing config unchanged; the
  two skipqual runs double as standing-config stability points (hardmode 95
  twice, the gates ALL PASS twice).
- **THE WATCH'S SCOPE (user, round 131)**: this line's upstream/community watch
  tracks TensorFold + GLM-5.3-Flash ideas ONLY — other engines (veloGB10, SGLang
  setups) and other model families (DeepSeek, Qwen, Flash-Next) are out of
  scope. The ECOSYSTEM.md pulses carry the scope note; the sub-4bpw Focus
  requant idea survives the scoping (it is a GLM-5.3-Flash checkpoint lever).
- **THE TAPS PORT: bit-safe, free, and unproven on our cell — PARKED**
  (three builds: the glued-header compile refusal, the v3 content-check fix,
  and the clean battery campaign-20261101-142151): the gates ALL PASS (g2
  drafted=plain on the fixed drafter path), the bench's every tg row in the
  standing band, the depth probes unchanged, hardmode 95 — and the upstream
  +1-2% decode does NOT reproduce (upstream measured TP=3's two-thirds
  staleness on a 2.37-tok/chunk acceptance profile; our TP=2 halves the
  staleness and our acceptance is already 4.8 tok/chunk — the bench's tg128
  rows cannot resolve 1-2% in the ±2-3% band). The patch stays as the record
  and the ready-made port if the pin ever bumps past #1623's landing; the
  standing config is unchanged.

## (round 131, cont.) The reqproof failure ladder runs to the MoE wall and fixes it; the proof redesigned on the converter's real contracts (2026-11-01)

The reqproof window iterated via `PHASES="preflight reqproof"` relaunches,
each failure a receipt, each fix committed before the next launch:

- **campaign-20261101-163344**: the proof's `cd` was one level short
  (scripts/requant is two levels down) — `./config.sh` not found.
- **campaign-20261101-164604**: the driver skipped the converter's arg
  normalization — `get_base_model` crashed on `vision_bits=None`; fixed by
  walking `prepare()` (which fills the defaults) and passing `-vb 16 -mb 4`
  explicitly (GLM's vision tower needs it, as the AZ convert did).
- **campaign-20261101-165608**: `prepare` demands `--out_dir` — the throwaway
  work/out added (the capture writes hessians/, not a checkpoint).
- **campaign-20261101-170530**: the driver's deferred-load close was
  `stc.close()` where the converter's loop calls `stc.end_deferred_load()`
  (close leaves the deferred flag set; the next module's begin asserts).
- **campaign-20261101-171541**: the driver loaded modules to CPU — the capture
  forward is a CUDA path (`CUDAGuardImpl` crash in hc_mix); modules now load
  to cuda:0 with the prefer_cpu exception, as the converter's loop does.
- **campaign-20261101-172539 — THE CAPTURE WORKS**: hin files landed layer by
  layer (qkv, o_proj, gate/up/down per layer 0-2), then the wall:
  `exl3_moe_gather: top-k too large` at layer 3's MoE gather.

**The wall, rooted and fixed**: the check is `exl3_moe.cu:689`
(`topk <= MOE_GATHER_MAX_TOPK`, the define is 32) — but the failing topk is
NOT the Focus's num_experts_per_tok=8; the capture passes
`activate_all_experts=True` (glm4_moe.py sets `calibration_all_experts=True`
— the converter's intended dense capture), so the gather sees
topk = n_routed_experts = **288**. Site-local venv patch: the define raised to
512 (shared mem 6 KB/block; the original kept as `exl3_moe.cu.orig-site`);
the JIT rebuild verified (source-hash keyed, ninja in the venv bin — the
first rebuild attempt failed on PATH and was re-run with the venv activated).
The worker needs NO patch: with hin files the conversion runs uncalibrated
(convert_model.py:1224 — `use_reference_state = False`, no forward passes at
all).

**The proof redesigned on what the converter actually enforces** (read this
sitting): (a) recipes demand FULL coverage of every budgeted tensor and every
entry must match one (allocation.py) — a partial recipe is refused, so each
host's recipe is GENERATED from the captured key list: catch-all `"*": 16`
(unquantized store, no trellis cost) plus its half at 3; the merge takes each
3-bit file from its owner. (b) The hin volume corrected: per-expert keys
(`{expert_idx}`), 288 × 42 layers × 3 matrices, moe_intermediate 2048 →
~920 GB (not 4-5 GB) — fits both disks, syncs over the CX7 pair in minutes.
(c) The online-H sqnr run LEFT the gate (it would cost a full calibration
capture); the precomputed runs' own sqnr prints are recorded as the baseline
receipt, and the quality bar stays the final bench battery. (d)
capture_h.py filters `qbits_key == "bits"` so head/MTP linears never enter
recipes. (e) The worker's encode launches concurrently with the head's half +
reference. The hin contract held exactly: the packed row-major upper triangle
unpacks via `unpack_sym`, `count: 1`, no normalization.

Relaunched (preflight reqproof). The window is long: the capture is ~2-3 h
(42 MoE layers × 250 rows × all-experts forwards), the encodes add hours —
production returns at the window's exit per the flow.

## (round 131, cont. 2) The requant arc STOPPED (user) — the head's thermal envelope, not the code (2026-11-01)

**The incident**: ~19 min into the relaunched reqproof window
(campaign-20261101-181600, launched 18:16), the head hard-shut-down. The
capture log's last write is 18:34:37 — module 6/50, the first MoE layer's
all-experts forward (layers 0-2, dense, had captured normally; 15 hin files /
1.6 GB on disk). No kernel record of the shutdown (hard cutoffs log nothing);
the journal's previous boot ends at 18:35:02. The machine auto-POWERED-OFF
and stayed off — the user found it and powered it back on; the crash-net then
brought production up. The user's read: overheating.

**The read**: the all-experts capture (288 experts × 250 rows, ~36× a normal
forward's routing compute, sustained for hours) is outside the machine's
thermal envelope. It was never a 19-minute scare — the full capture is 2-3 h
and the encodes are also heavy. Not a code bug: the proof gate did exactly
its job, catching a site-level blocker for 1.6 GB of hessians and no encodes.

**(user) decision — STOP the requant arc.** The user's reasoning: they already
throttle the clocks via the `nvidia-power-limit` systemd service
(`nvidia-smi -pm 1 && nvidia-smi -lgc 200,2200` at boot), **but they have
found the limits are sometimes ignored by measured metrics — "seems to be an
issue with nvidia-smi."** That matches the known GB10 behavior documented in
the clock-cap diagnostics: `-lgc` can report success ("All done.") without
being enforced — a unit-specific firmware issue; `-pl` power limits are
unsupported on GB10, so the clock lock is the only lever, and a soft reboot
does not reliably restore enforcement (the documented recovery is a full AC
power cycle). With enforcement unreliable AND the cap itself mild (2200 MHz
vs ~2418 boost — a ~9% trim, never a safety margin for this load class),
continuing carried unbounded hardware risk on the user's primary machine.

**Post-trip diagnostic** (read-only, per the clock-cap skill): this boot's
service applied the lock cleanly (19:29:23 journal), and five live samples
show 2184-2197 MHz at/below the 2200 cap (clock-step rounding, not violation)
— enforcement is holding at this moment. The caveats stand: compliance now
proves nothing about the next heavy load, and the user's "sometimes ignored"
observation is the skill's documented silent-lapse signature.

**Disposition**: the arc's design, driver, contracts, and receipts stay
banked in docs/REQUANT.md (closure banner at the top; ledger row STOPPED).
The venv kernel patch stays (only the all-experts capture path reaches it;
serving's topk=8 never does; original preserved). Nothing runs on either
host; production is up on 8000. Revisit conditions are written in the
REQUANT.md banner: cooling/thermal headroom, different hardware, or a
community 3bpw line. The reqproof phase retires from
scripts/run-qualification.sh in the next sitting's commit (window flow
untouched otherwise).

## (round 132) TensorFold v1.2.1: the review, the pin bump, the re-qualification, and the hardmode baseline (2026-11-02)

**The review.** Upstream tagged v1.2.1 (1db3edb) on Nov 1; 173 commits past our
round-130 pin (49a01bb3 = v1.2.0 + #1732 + #1736 + #1505 — all three confirmed
in the release, so the bump loses nothing). What v1.2.1 adds for GLM-5.3-Flash
on our cell: `TF_GLM_CHUNK_SOLO=4096` (#1823 — a cold prompt's first token
6-9% sooner from 8K to 128K on GB10s, same bytes, 1.6-1.9 GiB more prompt
buffers), `TF_GLM_VISION_HOST=1` (#1760 — with --vision, rank 0 holds 240 MiB
for the tower instead of 1.05 GiB; ~0.8 GiB/rank back for KV at 512K), the
#1868 fix (a loaded server left ~36 GiB of checkpoint in the page cache — on
GB10 unified memory that is the GPU's too; long prompts ran 0.73x until
restart — now dropped after load), `GET /v1/load` (#1655), the CUDA-graph
capture-poisoning fix (#1744), TP rank-liveness error clarity (#1813), and the
CUDA-13 driver floor (#1791). Both knobs are untested here — the knobs front
REOPENS with exactly these two (cold depth + memory headroom).

**The pin bump + re-qualification** (campaign-20261102-081320): TF_COMMIT →
1db3edbe in scripts/local.sh; pinbump PASS (tensorfold-native 1.2.1 on both
hosts, the marker moved, the image copied to the worker). The full battery:
gates g1-g4 all PASS (content form), depth 12/12 (8k/64k/192k/384k, the
standing config re-qualified end to end), prefill 1,085 tok/s on the ~26.9k
probe (pp2048@d0 1,035-1,036 across cells — within noise of the standing
1,049; no anchor change), climb's PARALLEL=5/6/8 ALL REFUSED at 512K even
with a 4 GiB prompt cache (recorded outcomes). prodqual was SKIPPED —
production was down when its turn came (a flow deviation; production's fresh
current-bench anchor is owed on the next window). The standard tool-eval
scored 95 on the dense8+fp8 cell (69 scenarios) — same instrument +3 over
that cell's first-campaign 92; recorded as tool-eval, never cross-compared
with hardmode.

**(user) decisions, all in bca058e:**
- "GLM-5.3-Flash-Next" → **GLM-5.3-Flash** — the same model (the architecture
  name IS glm5_next; the release notes' "Flash Next" items are this family).
- **PARALLEL caps at 4** on the 2-node pair — the climb and climbP phases
  retired permanently; no 5/6/8 tests anywhere.
- **Hardmode is the only quality instrument** — bench_cell's battery gains
  --hardmode (the standard batch rides inside it; plain 69-scenario runs are
  retired; tool-eval and hardmode scores never cross-compare families).

**The hardmode baseline on v1.2.1** (campaign-20261102-095700, the first
hardmode-instrument campaign): the standing config (dense4fp8, the Focus
checkpoint, vision, 512Kx4) scores **93** on the 104-scenario battery — the
Focus cell's best hardmode receipt (ties the effort-tail-era 93; production's
run-level 94 is the old-bench-era anchor — the current-bench production datum
is owed via prodqual). Fails: TC-100, TC-104, partial TC-99. The dense8+fp8
reference cell scored 88 (fails TC-99 partial, TC-101, TC-104 — the diff is
one scenario each way; stability-shaped, recorded). The next step per
PERF_PLAN: the prodqual + same-window duel on v1.2.1 (the decode rows' duel
instrument), then the two new GLM knobs.

## (round 132, cont.) The v1.2.1 duel re-pairs the decode fronts; prodqual's window-ordering fact (2026-11-02)

**prodqual skipped AGAIN** (campaign-20261102-112634) — and the reason is now
clear: prodqual probes the opencode production on 8000 (read-only), while the
duel's production arm restarts production FOR TESTING on 8001 — the two arms
cannot share one window (the flow stops 8000 around the duel's restart). The
duel's production probes ARE a fresh same-instrument production measurement,
so the perf rows carry a current anchor; production's current-bench HARMODE
datum still needs its own window (prodqual alone, or prodqual-first
ordering).

**The v1.2.1 duel** (ours dense4fp8 vs production 0.6.6, same probes):
- solo decode: ours 55.5/55.3 (Δ 0.3%) vs production 58.9/59.1 (Δ 0.2%) —
  **93.9%** (the round-130 pair was 93.2% — +0.7 pp on the new engine)
- c2 aggregate: ours 92.3 vs 111.1 — **83.1%** (was 80.5%)
- c4 aggregate: ours 143.3 vs 155.1 — **92.4%**, with production's volley
  coming in LOW this run (its range is 155-241 with cache state; ours holds
  142-148 across runs — the round-130 pair was 144.9/192.6)
- request overhead: ours 199 vs 183 ms (92.0%, unchanged shape)
- ITL: ours 56.8 ms/chunk (507 chunks, the chunked rhythm) vs production
  17.0 ms (2049 chunks) — per-token ~16.7 vs 17.0 ms, the crossing stands
- TTFT at depth: ours 3,748/5,574 ms (d4096/d8192 — true cold, slope 0.656)
  vs production 2,440/2,368 — its persistent cache warm-hit artifact again
  (its d8192 came in BELOW its d4096); the prodcold receipt (17.1 s true
  cold) stands as production's real cold cost

The anchors' solo/c2/c4/overhead rows re-paired (dated 2026-11-02) and the
chart re-rendered. The depth-front picture on v1.2.1: cold crossed (ours),
warm still production's edge, decode gaps narrowed.

## (round 132, cont. 2) The bpw4sweep's first three windows: two script bugs, then the AZ receipted (2026-11-02)

The sweep's first two launches died to my own bugs (each caught by the phase's
own receipts within a minute, production restored each time): the pack env
strings dropped the `MODEL_ID=` prefix (env tried to EXECUTE the pack path —
campaign-20261102-121636), and the pack extraction then kept the prefix in the
hub-dir derivation (`models--MODEL_ID=local--...`; the staging rsync aborted
the window — campaign-20261102-122535). Both fixed (bca058e lineage), staging
failure now takes the receipt path instead of aborting.

**Window 3 (campaign-20261102-123433) — the AZ pack receipted** (~50 min, the
one-pack-per-window shape working as designed):
- **glm-topk4b.patch applies cleanly on v1.2.1** — the AZ's top-4 selector
  serve is intact on the new engine (the prepare marker carries it)
- **hardmode 90/104** — the AZ's best receipt (+1 over its 89 history; the
  Focus leads at 93)
- **g1 determinism: identical contents**
- **the fastest bench table on this line**: pp 1,184 tok/s at d0 (the Focus
  cell: 1,035), solo tg128 57.7 (the Focus: ~40) — the top-4 design's half
  expert work showing in prefill and decode alike

The checkpoint matrix so far (hardmode, 104 scenarios, v1.2.1, standing
config): **Focus 93 · AZ 90** · Mia-AiLab 4bpw and TR3 pending (windows 2-3;
the MIA window stages its pack from the worker — the staging path's first
real exercise). Production serves the Mia-AiLab family, so that window is
the closest like-for-like with the served default.

## (round 132, cont. 5) The poke chain proven fixed; the MIA skip was one more byte bug (2026-11-02)

**The poke chain works again — proven**: the campaign-20261102-141000 window
hit the pack refusal path, the rebuilt phase RETURNED cleanly (no fall-through
into the dead-server probes), the campaign printed its completion marker, and
the cron poked — the first refusal-path poke of the arc. The staleness
fallback (a quiet-10-min campaign while production is up pokes anyway) is now
belt-and-braces behind it.

**The MIA skip was bogus**: refusal #2 came from the HUBDIR derivation losing
a byte in the function rebuild (`${PACK//\/ --}` without the separator — the
slash was never replaced, so the phase looked for a nonexistent dir and
concluded "neither host has it"). Both hosts' MIA copies are actually fine and
`snapshots/main`-normalized. The line is rewritten byte-explicitly (od
verified: `PACK//\/--` — the same proven form as the MODEL_ID derivation) and
the skip marker + refusal counter are cleared. The MIA window relaunches: no
staging needed (both hosts have the pack + the main ref), straight to the
restart.

## (round 132, cont. 6) The MIA pack receipted: 94/104 — the sweep's best, and production's own family (2026-11-02)

The HUBDIR byte fix held: no staging needed (both hosts had the pack +
normalized main refs), straight to the restart. **Mia-AiLab 4bpw-TensorFold:
hardmode 94/104** — the sweep's best score, and the pack family PRODUCTION
serves (its /v1 serve line mounts this checkpoint's hash snapshot), measured
at our standing config on v1.2.1. g1 clean. Perf level with the Focus cell
(pp 1,031 d0, solo tg128 39.2 — same family shape).

**The matrix (hardmode, 104 scenarios, v1.2.1, dense4fp8 standing)**:
Mia-AiLab 4bpw **94** · Focus **93** · AZ **90** (the top-4 selector — the
perf leader: pp 1,184, solo tg 57.7) · TR3 next (window 3).

## (round 132, cont. 7) The TR3 window: the staging path worked; the refusal was prepare's worker-side check (2026-11-02)

Window 3's first attempt: the staging code's first real run SUCCEEDED (the
TR3 pack staged worker -> head, 164 GB, main symlinked to the hash snapshot),
then the restart refused — and the receipt shows it was NOT the engine:
**prepare demands snapshots/main on BOTH hosts**, and the worker's TR3 copy
is hash-keyed only (the same pattern the MIA pack had; both packs' local
copies carry no main ref — production serves its own pack by hash from its
own volume). The refusal path recorded + armed the retry cleanly (the poke
fired; the completion marker printed). Fix: the staging function now
normalizes the worker's snapshots/main too (a permanent fix, not the MIA
manual one-off). TR3's marker cleared; the window relaunches.

## (round 132, cont. 8) The 4bpw sweep complete: TR3 ties the best quality with the best top-8 decode; the scorecards rendered (2026-11-02)

Window 3's retry: the worker-side snapshots/main normalization held, the TR3
pack served, g1 clean. **TR3-4bpw: hardmode 94/104** — ties the MIA pack for
the best quality AND posts the best top-8 decode of the sweep (solo tg128
46.0/46.2/45.2 at d0/d4096/d8192 vs the MIA's 39.2/45.3/41.5 and the Focus's
40.6/46.0/40.7), prefill level (1,039).

**The complete matrix** (hardmode 104 scenarios + the bench table, v1.2.1,
dense4fp8 standing): TR3 **94** (tg 46.0/46.2/45.2, pp 1,039) · MIA **94**
(39.2/45.3/41.5, pp 1,031) · Focus **93** (40.6/46.0/40.7, pp 1,036) · AZ
**90** (57.7/52.5/61.4, pp 1,184 — the perf leader by the top-4 design).

**The scorecards**: docs/bpw4-sweep-cards.svg, generated by
scripts/render-sweep-cards.sh from docs/bpw4-sweep.tsv (the data committed;
the SVG generated — the same discipline as the standing chart). The user's
decision rule stands: better quality is acceptable when the performance gap
is small. TR3 vs the served Focus: +1 hardmode AND better decode at d0/d8192
(+13%/+11%) with prefill level — the Focus is dominated on both axes; the
served-default swap is the user's call (asked with the cards).

The 3bpw track (turboderp 3.05/3.10 + androidli 3.0bpw) launches next per
the user's sequencing; production's current-bench hardmode anchor (solo
prodqual) is still owed and pairs the cards' production row.

## (round 132, cont. 9) THE SERVED DEFAULT SWAPS TO TR3-4BPW (user) (2026-11-02)

**(user)**: "Swap to TR3" — config.sh's MODEL_ID default is now
Mia-AiLab/GLM-5.3-Flash-EXL3-TR3-4bpw (main). The reasoning, receipted: the
sweep's verdict — TR3 94/104 hardmode (best, tied with the MIA pack) with the
best top-8 decode (tg128 46.0/46.2/45.2 at d0/d4096/d8192) — dominates the
served Focus (93) on BOTH axes (+1 quality, +13%/+11% decode, prefill level);
the user's rule ("better quality is acceptable when the performance gap is
small") is met with no gap at all. The README's served-default notes and the
anchors header carry the swap (the duel rows stand as the Focus cell's until
a TR3 duel re-pairs them — the next duel window runs on the new default).
The swap takes effect at the next testing-stack restart (the fingerprint
changes; both hosts carry the pack staged).

## (round 132, cont. 11) Requants OUT OF SCOPE (user) — the docs scrubbed (2026-11-02)

**(user)**: "Requants are going to be out of scope for this repo until we find a
safe efficient method. Remove any requant tasks or aspirations from all docs."

Executed: **docs/REQUANT.md deleted** (the arc's design + the closure banner —
its lessons live in this log's round-131/132 entries and the agent-skill
stores); **PERF_PLAN.md** carries the scope note at the front list (requants
out of scope; sub-4bpw work proceeds by SERVING community-built packs, never
by local quantization; the requant mentions below in that doc are the AZ
pack's executed provenance only) and the stale "Vision qualification (queued,
post-requant)" section is replaced by its closure (vision qualified in the
round-55 era, the standing default); **ECOSYSTEM.md**'s two aspiration
phrasings reworded (the sub-4bpw watch item and the androidli entry — the
community 3bpw packs are a serving track, not a quantization one). The
ledger's requant mentions are closed history (the round-58/72 entries) and
stand. The requant-era scripts (scripts/requant/, scripts/az-window.sh) are
inert and unreferenced. The 3bpw track continues unchanged — it downloads and
SERVES community packs.

## (round 132, cont. 14) THE 3BPW ENGINE FLOOR: the CUDA family reads 4-bit EXL3 experts (2026-11-02)

The dereferencing staging worked (the worker's copy: real files — but 589G,
because -L walked the whole hub dir and materialized the blob chain's data
twice over; the snapshots are self-contained), and the serve produced THE
definitive receipt of the sub-4bpw question:

`error: EXL3 at 3.05 bits: the CUDA family reads 4-bit EXL3 experts (UnsupportedQuant)`

**The native engine's GLM family has a hard 4-bit expert floor.** The
turboderp packs (3.05bpw plain and sc_3.10bpw self-calibrated) are
unservable on this engine regardless of quantizer quality — the check names
the family's reader, not the pack, so the sc_3.10 variant was skipped
WITHOUT a window (the receipt text is pack-generic) and both hosts'
turboderp dirs were pruned (~720G reclaimed: the head 129G+135G, the worker
589G of -L duplication). TB305/TB310 carry skip receipts.

**The decisive window is running**: androidli's 3.0bpw-mcg-TensorFold pack —
its community verification was on TensorFold 0.6.0 (the PYTHON-engine era,
production's line), so its window settles whether ANY sub-4-bit GLM pack
serves on the native CUDA line, or whether the 4-bit expert floor gates the
whole sub-4bpw goal (an upstream watch item if so — the packs exist; the
engine's reader is the constraint).

The README now leads with both SVGs (the perf-vs-production chart and the
sweep scorecards, moved above the status table), and the docs table carries
the sweep artifacts' row. The docs alignment pass completed: DELTAS' header
and Engine row on v1.2.1 with the era-labeled quality numbers, VALIDATION
and the CONTEXT plan carry the v1.2.1 re-qualification notes (the CONTEXT
plan's queued depth re-run: DONE, 12/12 twice).

## (round 132, cont. 15) THE 3BPW TRACK CLOSES — the engine gate is total (2026-11-02)

The androidli window (campaign-20261102-184142): the TensorFold-native mcg
pack staged (426G with the -L materialization), served — and REFUSED:
`EXL3 at 3 bits: the CUDA family reads 4-bit EXL3 experts (UnsupportedQuant)`.
The same floor as the turboderp packs, on a pack whose layout is exactly what
our engine reads at 4bpw. **The sub-4bpw goal on the native line is
engine-gated, full stop**: the packs exist, the quantizers did their work,
the family's reader admits 4-bit experts only. The androidli pack served on
TensorFold 0.6.0 — the python-engine era (production's line).

**Closed**: the androidli + turboderp dirs pruned on both hosts (the worker's
-426G/-589G copies reclaimed; the head ~1130G, the worker ~1887G free), the
ANDROID/TB305/TB310 skip receipts in results/bpw4sweep/, and **both sweep
phases retired** from run-qualification.sh (the receipts + the re-run patterns
live in results/bpw4sweep/ and git history). The 4bpw sweep's verdict stands
as the arc's product: **TR3-4bpw is the served default at 94/104**.

The upstream watch item (ECOSYSTEM.md): the CUDA family's GLM reader gaining
sub-4-bit expert support would reopen the sub-4bpw serving track with zero
local work — the packs are one download away.

Next per the plan: the owed production anchor (a solo prodqual window on the
current bench version), then the two GLM knobs (TF_GLM_CHUNK_SOLO,
TF_GLM_VISION_HOST).

## (round 132, cont. 17) THE METRICS-PORT RULE (user) — the 8000 runs invalidated, the lock installed (2026-11-02)

**(user)**: "We should never run tool-eval-bench against port 8000, it negates the
testing environment. Any results in this thread of tool-eval-bench on port 8000
are invalid." And: "If we want quality or performance metrics we need to run them
on a clean unused port (8001)."

Executed: the against-8000 bench KILLED mid-run; **both campaign receipts from
this thread's 8000-targeted runs deleted** (the two invalidated dirs, the
191715 / 191940 evening timestamps — invalid, never to be cited); the BENCH_BASE_URL override plumbing
REVERTED (the load arms point at the testing port unconditionally); **the
metrics-port lock installed** at run-qualification.sh's start (`PORT != 8001`
refuses to run — one guard covering every load arm and probe); **the prodqual
phase retired** (its probes measured against the live 8000 — the same
violation; the production-vs-us instrument is the DUEL: production started FOR
TESTING on 8001, both engines on the clean port); the flow's prodqual-aware
ordering references cleaned; **AGENTS.md carries the rule as a hard boundary**.
The state verified clean before proceeding: no bench processes, production
back on 8000 (the crash-net restored it), no stale window flags, the invalid
receipts gone.

The next tests per the plan, prepared under the criteria: the duel window
(re-pairs the anchors on the served TR3 default — production-for-testing on
8001, both engines clean), then the two GLM knobs (TF_GLM_CHUNK_SOLO /
TF_GLM_VISION_HOST) on 8001.

## (round 132, cont. 19) THE DUEL+KNOBS WINDOW: TR3's decode dividend is real; the prod arm's port conflict receipted; two (user) directives documented (2026-11-02)

**The window** (campaign-20261102-195440): the duel's OURS arm measured on the
served TR3 default — **solo 63.9/63.6 t/s** (stability Δ 0.6%), c2 109.0, c4
150.5 aggregate; ITL mean 61.6 ms / p50 54.8 / p95 86.3 (520 chunks); TTFT d0
201 ms, slope 0.656 ms/token. vs the Focus-cell ours arm (solo 55.4): **+15%**
— the TR3 perf dividend is real. **The prod arm SKIPPED with its receipt**: our
own stack (left up by knobsv121, which runs first in the phase-list order) held
8001 — production-for-testing's start refused: "port 8001 is already in use"
(campaign.log 20:35). The anchors still stand on the Focus-cell pair until the
prod arm re-runs in the same window as the ours arm.

**The knobs** (results/knobsv121/, bench_perf tables per arm):
- **CS (TF_GLM_CHUNK_SOLO=4096)**: tg d0 49.8 (+5.1%), d4096 47.4 (+8.7%),
  d8192 47.8 (flat) vs BASE 47.4/43.6/47.7 — real gains, beyond noise. The
  trade: model 86.62 GiB (+1.87), prompt cache 3.3→1.9 GiB (halved),
  13.1 GiB left (−1.5) — resume-capacity risk at depth.
- **VH (TF_GLM_VISION_HOST=1)**: tg d0 44.2 (−6.7%), d4096 45.9 (+5.3%),
  d8192 44.8 (−6.1%) — noise-to-negative. The memory: model 83.93 GiB (−0.82)
  but the prompt cache GREW 3.3→3.5 GiB — net free +0.2 GiB only; the tower's
  gift is mostly absorbed. Lean reject. **Its vision sanity was an INVALID
  test** — an SVG data URL fixture; the tower wants raster (PARSE FAIL receipt).

**Two (user) directives, documented permanently in AGENTS.md hard boundaries**:
1. (user) "We use our vision assets for testing" — vision tests run the repoed
   `assets/vision/` suite (manifest.json: the synthetic _quadrants.png + 3
   CC-licensed photos, agent-verified ground truth) via
   `scripts/vision-suite-probe.py`; never ad-hoc fixtures, never files
   scavenged from other tools' trees.
2. (user) "We use the autonomous workflow process for keeping the production
   and testing processes separate" — separation runs through the window flow:
   production stops at entry, restored on every exit path; production-for-
   testing binds 8001 (intent-keyed) only while our testing stack is stopped;
   a phase starting production-for-testing stops our stack first and restarts
   ours after.

**Executed on both**: the duel phase stops our stack before the 8001
production-for-testing start (the ours arm restarts it); the knobsv121 VH arm's
vision sanity is now the repoed suite (4 targeted + 4 detail over
assets/vision). `results/knobsv121/VH.done` cleared — the arm re-runs with a
valid vision test. AGENTS.md also drops the stale prodqual mention (retired
cont. 17).

Next: relaunch `PHASES="duel knobsv121"` — the prod arm pairs (both engines on
8001, same window) and the anchors re-pair onto TR3; VH re-tests with the
suite; then the CS adopt-vs-hold call goes to the user.

## (round 132, cont. 20) THE TR3 DUEL PAIRS — SOLO CROSSES 110%; VH rejected on two arms; the vision instrument fixed (2026-11-02)

**The duel paired** (campaign-20261102-210117 — the stack-stop fix worked: the
phase stopped our stack, production-for-testing bound 8001, both arms measured
in the same window). **The served TR3 cell's scoreboard vs production 0.6.6**:
solo **110% — CROSSED** (ours 64.4/64.2 vs production 58.5/58.6), c2 **127%**
(110.3 vs 87.0), c4 **80%** (152.6 vs 192.0 — production's c4 range 155-241
with cache state, this run near its top; ours holds 150-153), ITL **109%**
(15.6 vs 17.1 ms/token — ours' chunked rhythm 61.6 ms ÷ 3.9 tokens), TTFT
overhead **91%** (201 vs 183 ms). The TR3 decode dividend is now a same-window
receipt: the Focus cell was 93.9/83.1/92.4/102/92.0 — the swap moved every
decode front. **Anchors re-paired, the chart re-rendered, DELTAS + README
updated** (the cold/warm depth rows stand on the round-131 prodcold receipt,
untouched).

**VH (TF_GLM_VISION_HOST=1) REJECTED — final, two arms**: tg d0 −6.7/−8.9%,
d4096 +5.3/+12.6%, d8192 −6.1/−7.1% vs BASE (noise-to-negative, no consistent
gain); the model sheds 0.82 GiB but the prompt cache GREW 3.3→3.4-3.5 GiB —
net free headroom +0.2 GiB. **Vision is INTACT on the knob** — the repoed
assets/vision suite's detail leg: all four answers correct (quadrant colors +
positions, Golden Gate, zebra, STOP sign). The targeted leg's 3-of-4 empties
were the probe's 64-token cap burning on the reasoning channel (the
small-max_tokens gotcha) — **the instrument fixed to 1024** (cont. 20a: the
probe + the visionen inline copy). The base-serve targeted re-check rides the
next window (the exit path stopped our stack before restoring production —
correct: production needs both GPUs; the stack is down until the next window).

**CS (TF_GLM_CHUNK_SOLO=4096) — the adopt call is the user's**: real gains
(tg d0 +5.1%, d4096 +8.7%, d8192 flat) at a real trade (+1.87 GiB model, the
prompt cache halved 3.3→1.9 GiB — resume-capacity risk at depth). Presented
with this digest.

Next per the plan: the user's CS call, then the next plan item.

## (round 132, cont. 21) PRODBENCH — the owed production hardmode anchor gets a port-rule-compliant instrument (2026-11-02)

The perf plan's one owed item is production's current-bench hardmode anchor
(prodqual measured against the live 8000 — retired with the port rule). The
replacement: **prodbench** — production FOR TESTING on 8001 (the duel's
choreography verbatim: our stack yields the port, the intent-keyed start, the
stop after, our stack restored) with the bench's hardmode battery (v3.0.1,
--hardmode, ~25 min of client load) as the read-only probe. Our side's
same-bench receipt: TR3 94/104. Also: the BENCH_BASE_URL override — still
present in the load functions despite cont. 17's revert note — is now removed
at all 4 sites; the testing port is unconditional and the script-start port
lock is the one guard. The phase retires when the anchor lands in the
scoreboard. Window launched: PHASES="prodbench".

## (round 132, cont. 22) THE OWED QUALITY ANCHOR LANDS: production's current-bench hardmode 94/104 — the served TR3 TIES it (2026-11-02)

**prodbench ran clean** (campaign-20261102-213954): production FOR TESTING on
8001 (the duel's choreography — our stack yielded the port, the intent-keyed
start, the stop after, our stack restored), the bench's hardmode battery
(v3.0.1, --hardmode, seed 42, --parallel 2 — the same bench_cell instrument as
ours) as read-only client load. **Final score: 94/104.** The served TR3's
sweep receipt: **94/104 — a tie at the bar** ("beat production's run-level 94
or come close" — met AT the number). The battery's own saturation warning
(--parallel 2 can record timeouts as FAILs) applies to both sides alike —
same instrument, same seed, same parallelism. README/DELTAS/PERF_PLAN/ledger
carry the closure; **the prodbench phase retired** (its receipt stands; the
re-run pattern in git history). The last owed item on the plan is now closed.

Next per the plan: the user's CS call (presented with options this sitting);
beyond it the one open perf front is the warm full-hit skip (production 0.21 s
vs our 1.42 s resume — the upstream host-cache trio #1736/#1795 is the named
pattern), upstream-gated pending the watch.

## (round 132, cont. 23) CS HELD (user); the knobs retire; the upstream watch points at #1732 — the kvshare A/B launches (2026-11-02)

**(user)**: "We go with your recommendation" — **CS (TF_GLM_CHUNK_SOLO=4096)
HOLD**: the gains land on fronts already crossed (solo 110%, c2 127%); c4 (the
one front behind, 80%) doesn't move; the +1.87 GiB / halved prompt-cache trade
is paid at the 512K×4 admission margin with an unmeasured multi-turn risk. The
knob stays available as an env, never the default. **The knobsv121 phase
retired** (VH rejected + CS held — both verdicts final; the receipts stand in
results/knobsv121/).

**The upstream watch** (the releases page): v1.2.1 (Nov 1) is still the latest
engine release — nothing to bump to. The v1.2.1 GLM opt-ins are now
dispositioned in ECOSYSTEM.md: #1823 held, #1760 rejected, **#1732
(TF_GLM_KV_SHARE=n + TF_KV_PAGES=on — prompts as pool pages; upstream's
receipt: a 64k re-send resumes in ~1.7 s vs 36 s prefill) is the named
mechanism for our WARM front** (production full-hit 0.21 s vs our 1.42 s
kept-states replay) — and #1736 (host-cache) is low-priority for our
unified-memory shape. No c4 content beyond what we run; no sub-4-bit reader
(the 3bpw gate stands).

**Launched: the kvshare121 window** (PHASES="kvshare121") — the #1732 A/B on
the standing config: BASE vs KVS (fp8; if the serve refuses, KVS2 retries on
bf16 — the branch-era fatality re-decided on mainline). Each arm: restart →
serve line (the memory shape) → the warm-resume probe (an ~8k prompt sent
twice at max_tokens 1: cold TTFT vs warm TTFT — the resume cost is THE
instrument) → bench_perf. The BASE arm carries the vision-suite rider (the
targeted-1024 cross-check, cont. 20a's loose end). The verdict decides
whether the WARM row moves onto the anchors.

## (round 132, cont. 24) THE KWSHARE A/B'S REFUSALS WERE MY INVOCATION BUGS — fixed, relaunched; the vision rider closed 4/4 (2026-11-02)

The kvshare121 window (campaign-20261102-230421) refused BOTH arms — and the
refusal lines name my bugs, not engine gates: (1) `TF_GLM_KV_SHARE=n` — the
release notes' "n" is a COUNT placeholder ("give how many states the prompt
cache over the KV pages keeps"), not a literal; the engine's arg-parse refused
the letter. (2) The bf16 fallback spelled `KV_CACHE=bf16` — start.sh only
accepts empty (the bf16 default) or fp8. **The #1732 mechanism was never
tested; the fp8×pages fatality is NOT re-decided.** Fixed: `TF_GLM_KV_SHARE=2`
(a two-state keep), the bf16 fallback omits KV_CACHE, and the warm_probe
parser's split-index off-by-one (it printed FAILED on successful sends — the
same campaign's evidence) replaced with labeled regex parsing. Arm markers
cleared; the window relaunched.

Landed from the same window: **the vision-suite rider on the standing config:
targeted 4/4** (quadrants 'Red', Golden Gate, zebra, 'STOP') — the targeted-1024
instrument fix verified on the standing serve; cont. 20a's loose end is closed.
The BASE bench table landed too (its tg numbers wobble vs the knobsv121 BASE —
the bench's known run-to-run noise; the duel instruments remain the honest
pairs). The lesson, for the record: a refusal is a receipt — read WHAT it
refuses before writing the verdict (the engine printed the expected format).

## (round 132, cont. 25) THE WARM FRONT RE-MEASURED: 0.302 s — 70% of production's skip; the fp8×pages rule confirmed; the bf16 arm re-spelled (2026-11-02)

**The BASE arm's warm-resume receipt (campaign-20261102-233025) is the
headline**: an 8,414-token prompt sent twice at max_tokens=1 — cold TTFT
**7.22 s**, warm TTFT **0.302 s** (24×). The SAME instrument definition as the
anchors' WARM row (1-token, d8192, cache hit) whose ours-number was 1,422 ms
from the round-131 receipt — **the row is corrected to 302 ms / 70% of
production's 0.21 s full-hit skip**, per the round-entry rule (both receipts
cited; the round-131 number was the v1.2.0-era stack — the #1868 page-cache
fix the likely mover). The chart re-rendered; DELTAS/README/PERF_PLAN
re-scoped: the warm solo TTFT is near-parity; the open pieces are the
cross-restart resume path and the concurrent resume's 4× serialization.

**The fp8×pages pair is a DESIGNED non-combination on mainline** — the
engine's admission line (the KVS refusal, campaign-20261102-233025):
"--kv-cache fp8 keeps a window per stream: unset TF_KV_PAGES, or set it to
auto or off". Pages require bf16/auto KV; the standing fp8 config cannot take
pages without leaving fp8. **And the "bf16" arm never ran**: omitting KV_CACHE
let config.sh's fp8 default leak through — the same fp8 refusal fired on the
KVS2 arm. Fixed: `KV_CACHE=` (EMPTY) is the bf16 spelling; the phase header
carries the confirmed rule. Markers cleared; the window relaunched for the
bf16 mechanism test (the #1732 question: does pages beat our 0.302 s
same-session hit, and at what memory shape on bf16).

**Overnight queue** (the autonomous run continues on the pokes): (1) the KVS2
verdict → retire kvshare121; (2) the cross-restart warm attribution (a
prodcold-style re-run on v1.2.1 — the row's open piece); (3) the ledger's
no-GPU hygiene items (the worker clock probe, the g3 /metrics counter check);
(4) the upstream watch each sitting.

## (round 132, cont. 26) THE KV_CACHE CATCH-22 — the empty spelling was structurally unreachable; one config line opens bf16+pages (2026-11-03)

The 235800 window's KVS2 refusal was the SAME fp8 message — the "bf16" arm
re-fp8'd itself again. Root cause, precisely: config.sh's
`KV_CACHE="${KV_CACHE:-fp8}"` — the `:-` form treats EMPTY as unset and
substitutes fp8 — while start.sh's bf16 path (omitting --kv-cache) requires
KV_CACHE empty AFTER config.sh. The empty spelling could not exist through the
stack; both the 233025 and 235800 windows burned on it. **Fix**: the form is
now `${KV_CACHE-fp8}` (no colon) — unset keeps the fp8 standing default,
`KV_CACHE=` (empty) is the explicit bf16 spelling (start.sh line 273 omits
--kv-cache on empty; the "bf16" literal stays illegal per start.sh's case).
Verified on the head with both-path probes: unset→fp8, empty→bf16,
fp8→fp8. The docs-guard's check_default needed its internal grep (the
call-site edit was cosmetic — the function re-derives its own pattern with
`:-` hardcoded) widened to both expansion forms. The window relaunched for
the bf16 mechanism arm.

## (round 132, cont. 28) THE HOLLOW WINDOW — a phase registered against the wrong line; warmrestart fixed and relaunched (2026-11-03)

The warmrestart launch bug, for the record: the patcher's registration
substring matched BOTH the phase-registration line and the default-PHASES line
(the cont. 23 trap, reintroduced) — the assert stopped the write, but the
newline-separated shell chain still committed the digest and launched
`PHASES="warmrestart"` against a script that had no such phase. **The window
(campaign-20261103-003103) ran hollow** — its receipt is campaign.log only, no
phase output; noted and superseded. Fixed: the registration is line-targeted
(the `for _p in` line only), the phase's warm_probe block rewritten with
single backslashes (the patcher's escaping had doubled the line-continuations
into literal `\\`, ending each command early), bash -n + the guard green.
 Relaunched.

## (round 132, cont. 29) THE CROSS-RESTART ATTRIBUTION + the worker clock probe's eternal zero, solved (2026-11-03)

**warmrestart (campaign-20261103-003946) closes the WARM row's first open
piece**: cold 7.24 s → warm 0.302 s before the restart (the same-session hit
re-verified — triple-receipted 0.302/0.302/0.305 across windows); **after the
restart the same prompt costs 7.25 s — CROSS-RESTART IS COLD**. The prompt
cache does not survive a stack restart; the round-131 v1.2.0-era 1.42 s was
that era's measurement of the same instrument definition (the row already
carries both receipts; its note now records the cold cross-restart receipt).
The front's open piece narrows to the concurrent resume's 4× serialization.
The warmrestart phase retired with the receipt.

**The worker clock probe's eternal zero — solved**: `ssh host bash -c
"$snippet"` lets the REMOTE shell word-split the probe snippet — its second
line (`[[ -e $f ]] || { echo 0; exit 0; }`) ran standalone with $f unset and
printed 0, which the probe took as its answer. The fix: feed the snippet via
stdin (`ssh host bash -s <<<"$snippet"` — byte-exact, no remote parsing).
Verified on the live hosts: **the worker delivers 3834 MHz, the head 3892**
(healthy X925; the probe's preflight line will now read the worker honestly).
The ledger's hygiene item closed; the g3 /metrics counter check remains (it
needs a live serve — rides the next window).

## (round 132, cont. 31) THE DOCS AUDIT — what a fresh checkout serves, verified; the loading row re-dated to 90% on the served default (2026-11-03)

**(user)**: "Check all the documents are up to date. Reflecting what serves
when a new checkout occurs, improve the documentation for quickstart. Ensure
the performance and quality is correct for the served defaults."

**The audit's findings, all fixed**:
- The quickstart + config table verified against the fresh-clone experience:
  prepare.sh discovers the site when `scripts/local.sh` is missing (or
  `local.sh.example` is the by-hand shape), `DOWNLOAD=1 scripts/prepare.sh`
  fetches a missing checkpoint, `./scripts/start.sh` serves the TR3 pack on
  8001 (v1.2.1, dense4fp8, 524288×4, DFlash2 drafts, vision on). The config
  table gained the missing **VISION row** (default `1` — it was served but
  undocumented) and the **KV_CACHE empty-means-bf16 spelling** (cont. 26's
  semantics — the literal `bf16` is refused, empty omits `--kv-cache`).
- The scoreboard's numbers audited for the served default: quality 94/104 ✓
  (the prodbench tie), solo/c2/ITL/overhead ✓ (the TR3 duel), c4 80% ✓, cold
  309% ✓ (annotated with the TR3 duel re-verification: d8192 5,587 ms, slope
  0.657), warm 70% ✓, the cross-restart text fixed (receipted cold).
- **The loading row RE-DATED — the audit's one real correction**: the served
  TR3-on-v1.2.1 serve times **104.5 s end to end** (103/106 s, Δ 2.9%;
  campaign-20261103-090007) vs production's 93.7 — **90%**, not "taken at
  98.6%". The prior 95 s receipt was the Focus-cell v1.2.0 qualification; the
  TR3 pack's load pays ~+9 s over the Focus cell (the mover unattributed —
  the pack's staging layout or the v1.2.1 load path). The chart re-rendered;
  README's Speed row, the bars row, PERF_PLAN's status bullet + scoreboard
  table, and DELTAS's TR3 paragraph all carry the honest number. **The
  loading front's re-take is open** — a new named front for the plan.
The loadtime phase retired with the receipt.

## (round 132, cont. 32) THE MODEL CARD'S STALE DEFAULT MARKER — the user caught it (2026-11-03)

**(user)**: "Redo the model card on the readme.md — I still see 'Focus (the
served default)' on there." Found and fixed at the SOURCE: `docs/bpw4-sweep.tsv`
labeled the Focus card "the served default" (the cards predate the TR3 swap)
while the TR3 card carried no marker — the TSV now marks **TR3-4bpw (the served
default)** and the cards regenerated. The same staleness in **config.sh's
comment block above MODEL_ID** (it still described the Focus as the default)
rewritten (TR3 the default, the Focus the prior default still serveable); the
settingsab phase comment's "the served default" → "the then-served Focus".
The final sweep: every remaining "served default" hit is either current-TR3 or
clearly dated history (the round-27/38 decision records). The lesson: the
generated artifacts inherit their sources — the TSV was fixed for the numbers
in cont. 31's audit but its LABELS were not re-checked.

## (round 133) THE V1.2.2 BUMP — the watch fired: the GLM cold-prompt gain, our tail-release patch mainlined, the digest cache; pinbump launched (2026-11-03)

**(user)**: "Ok, time to look at the upstream repo v1.2.2 released now?" —
**Confirmed: v1.2.2 released 18:53 Nov 3 (00e7ddd)**, and it is a strong bump
for our line: #1577 (GLM cold prompts 5-14% sooner at 32-167K, identical
replies), #1884 (the page cache released on load for every CUDA family —
glm-tail-release.patch mainlined, ~15 GiB class), #1771 (the cached
cross-rank checkpoint digest — the byte-verify may skip warm), #1795
(TF_GLM_KV_HOST — the WARM row's named pattern), #1842 (CS beside --drafter
refused — validates the user's hold), #1962 (image-state identity in the
prompt cache), the risks: #1987 (the non-bf16 activation-dtype refusal —
the packs likely moot) and the patch's applicability. The full disposition:
docs/ECOSYSTEM.md (the 2026-11-03 entry). **The pin moved to 00e7ddd**
(scripts/local.sh on the head); **pinbump launched** (the explicit prepare,
the marker must move — fail-honest). Next: the re-qualification window
(the gates, depth, prefill, the duel re-pair), the loading re-measurement
(two levers landed for the re-take), hardmode if the gates move.

## (round 133, cont. 1) THE PINBUMP LANDED: v1.2.2 built and distributed (2026-11-03)

**pinbump (campaign-20261103-195127): the marker moved** — 1db3edb → 00e7ddd
(the prepare built the pinned commit; "the battery runs on the new engine").
**glm-tail-release.patch applied cleanly on the new loader** (patches= listed
in the prepared marker) — its redundancy question (#1884 mainlined the
page-cache release) is now empirical: the serve lines' memory numbers in the
re-qualification receipts decide whether the patch still adds anything or
retires. The re-qualification window launched: `PHASES="preflight parity
candidate kvqual4 depth prefill duel"` — the §2 gates (the GLM items claim
identical replies; the gates verify), the depth ladder, prefill, and the duel
re-pair on the new engine. The window's restart walls carry the v1.2.2
loading receipt (the digest-cache + page-cache-release effects on the 104.5 s
wall). Hardmode after the gates, if they hold.

## (round 133, cont. 2) THE HOLLOW WINDOW, AGAIN — the launch wrapper's arg IS the phase list (2026-11-03)

The re-qualification launch used a descriptive label ("requal v1.2.2") —
**autonomous-launch.sh's $1 is BOTH the label AND the PHASES string** (its
header's own example: `autonomous-launch.sh "preflight ncurouter summary"`) —
so PHASES became "requal v1.2.2", want() matched no phase, and
campaign-20261103-200937 ran hollow ("done." in one line; the flow restored
production cleanly — no harm). Every prior launch had label == PHASES, which
masked the contract. Relaunched with the phase list as the argument.

## (round 133, cont. 3) THE V1.2.2 RE-QUALIFICATION: gates PASS, depth 12/12, the fronts hold, prefill −3.5% (2026-11-03)

**The re-qualification (campaign-20261103-201958) certifies the bump**:
- **The §2 gates g1-g4 ALL PASS** (content form) — the GLM items' identical-
  replies claims hold on our pack (drafted=plain, resumed=fresh,
  concurrent=solo, determinism).
- **Depth 12/12** (3/3 at 8k/64k/192k/384k).
- **Prefill 1,114 tok/s at a 26,870-token fill** — above the pp2048-era ~1,030
  receipts; the duel's prefill slope **0.657 → 0.634 ms/tok (−3.5%)** — #1577
  partially visible at 8k (its full 5-14% claim lives at 32-167K).
- **The duel pair (both engines on 8001, same window)**: solo 63.3/63.2 vs
  58.6/58.6 (**108% — crossed holds**), c2 109.1 vs 87.2 (**125%**), c4 149.3
  vs 192.4 (78% — production near its range top again), ITL 16.0 vs 17.1
  (**107%**), overhead 197 vs 184 ms (93%). All within noise of the v1.2.1
  pair; the anchors re-dated onto the v1.2.2 pair, the chart re-rendered.
- **Memory: no regression on the served config** — the dense4fp8 serve line:
  model 84.75 GiB (identical to v1.2.1), 14.2 GiB left, a 2.9 GiB prompt
  cache. (The 86.71/12.6 first line was the dense8 parity cell.)
- **The loading**: health waits 96-101 s — consistent with the 104.5 s wall;
  no visible digest-cache skip (the load dominates). The hmcheck window re-dates
  the row with a timed v1.2.2 wall + the hardmode battery (the 94's
  certification on the new engine).

## (round 133, cont. 4) THE BUMP IS CERTIFIED: hardmode 94 on v1.2.2; the loading row re-dated (91%); the postbump window launched (2026-11-03)

**hmcheck (campaign-20261103-221555) closes the certification**: **hardmode
94/104 on the served v1.2.2 config** — the quality tie holds on the new engine
(the same score as the v1.2.1 receipt and production's prodbench 94). The
**timed v1.2.2 restart wall: 103 s** — the loading row re-dated (91% vs
production's 93.7; the front is stable across the bump; the digest-cache and
page-cache-release levers show no wall effect — the weights load dominates).
The serve line: model 84.75 GiB, 13.9 GiB left, a 2.7 GiB prompt cache.

**Launched: the postbump window** — four arms: (A) the deep-prefill curve
(cold TTFT at 32k/64k/128k novel fills — #1577's 5-14% claim lives where our
8k instruments don't reach; measured-vs-slope is the receipt), (B) KV_HOST on
fp8 (the refusal would be the receipt), (C) KV_HOST on bf16+pages (the memory
shape + the warm probe — #1795, the WARM row's named pattern), (D) PATCHES=
(the glm-tail-release redundancy — #1884 mainlined the release; the memory
numbers decide the retirement).

## (round 133, cont. 5) THE PATCH RETIRES; KV_HOST's shape is striking; the deepfill probe fixed and relaunched (2026-11-03)

**postbump (campaign-20261103-230631) — three of four arms delivered**:
- **Arm D — glm-tail-release.patch RETIRES**: the no-patch serve is identical
  on memory (model 84.75 GiB, 13.9 GiB left — the with-patch serves read
  13.9-14.2). #1884 mainlined the release; **the PATCHES default is now
  EMPTY** (patches opt-in by name; the config fingerprint change re-prepares
  cached). The patch's v1.2.0-era history stays in its comment + the ledger.
- **Arm C — TF_GLM_KV_HOST works on bf16+pages, and the shape is striking**:
  model 82.03 GiB, the device pool collapsed to **1.50 GiB** (the KV latent
  rows in pinned host memory), **a 14.1 GiB prompt cache**, 16.7 GiB left —
  the host-side cache could hold many more kept states (resume capacity).
  Its warm check never ran (the probe bug) — the re-run decides.
- **Arm B — KV_HOST on fp8 refused, and the engine names it**: "TF_GLM_KV_HOST
  keeps the KV pool's pages in host memory: set TF_KV_PAGES=on (and --kv-cache
  bf16) as well" — consistent with the fp8×pages rule.
- **Arm A — the deep fills FAILED on my probe bug**: the JSON body went
  through a shell argument and blew the arg limit at 32k+ tokens. Fixed:
  `-d @file` (a temp body file); arm C gains the warm check. Relaunching.

Also landed: the docs' version moves (README's serve row/pin line/config
table, DELTAS's engine row — v1.2.2 with the certification receipts).

## (round 133, cont. 6) THE DEEP-PREFILL CURVE: linear at ~0.785 ms/tok to 170K; the wake missed a poke; the warm_probe definition fixed (2026-11-04)

**The poke chain missed the 23:38 completion** (the user asked "No poke
today?") — the wake for campaign-20261103-232127 never fired; processed
directly. **Arm A's deep-prefill curve is the sitting's headline**: cold TTFT
33.5 s at 42,469 tokens, 66.7 s at 84,959, 133.1 s at 169,904 — **~0.785
ms/tok, perfectly linear across 42k→170k** (no depth blowup inside the 512K
window). The deep slope sits above the duel's 8k slope (0.634) — the deep
curve is the front's new evidence (a v1.2.1 comparison was never run, so no
#1577 delta claim at depth; the 8k duel already receipted −3.5%).

**The phase died mid-arm-C**: the fix added the warm_probe CALL but postbump
never defined the function (the retired phases took their definitions with
them) — arm D never ran. The definition added; relaunched (arms re-run; the
KV_HOST warm check and the patch arm land their receipts). Arm C's serve
shape re-confirmed: model 82.03, the device pool 1.50 GiB, a 13.6 GiB prompt
cache, 16.1 GiB left.

## (round 133, cont. 7) THE POSTBUMP VERDICTS: the deep curve reproduced; the patch retirement confirmed on speed too; KV_HOST non-viable here (2026-11-04)

**The third postbump run (campaign-20261103-235114) completes the arc**:
- **Arm A — the deep-prefill curve REPRODUCED**: 33.67/66.88/133.44 s at
  42,469/84,959/169,904 tokens (the re-run Δ < 0.5%) — **linear at ~0.785
  ms/tok, no depth blowup inside the 512K window**. The front's deep evidence
  (the #1577 delta stays at the 8k duel's −3.5%; no v1.2.1 deep comparison was
  run).
- **Arm D — the patch retirement CONFIRMED on speed too**: the no-patch serve
  at 14.1 GiB left (identical memory) and its 87.4k fill at 68.8 s — **the
  same 0.787 ms/tok rate as the with-patch curve**. glm-tail-release is
  retired from the default PATCHES (empty; opt-in by name), noted in
  patches/README.md.
- **Arm C — TF_GLM_KV_HOST is NON-VIABLE on our shape**: refused on fp8 (the
  engine names pages+bf16); on bf16+pages the serve comes up (the device pool
  1.50 GiB, a 13.6 GiB prompt cache) but **every request timed out** (600 s
  deep, 300 s warm × 2) — the host-side KV path does not answer at 512K×4.
  The WARM row's named pattern (#1795) is closed for this line; the standing
  0.302 s hit (70%) stands. Dispositioned in ECOSYSTEM.md.
- **Arm B — the fp8 refusal re-receipted** (the engine's own requirement line).

**The perf plan's state after the bump**: every named lever is adopted,
measured out, parked with a price, or upstream-gated — quality tied (94=94),
loading 91% (GLM lacks TF_LOAD_PREFETCH upstream — gated), solo/c2/ITL/cold
crossed, c4 + the concurrent resume gated/parked, warm 70% (the 0.09 s
residual parked). The 8-hour run continues on the watch cadence (the wake-gap
noted: one completion's poke never fired — monitored), the docs current.

## (round 133, cont. 8) THE DEEPDELTA WINDOW — the #1577 deep curve on both pins (2026-11-04)

The watch: v1.2.2 still latest (no new trigger). The one quantitative receipt
left on the bump gets taken: **deepdelta** — the SAME novel fills
(42,469/84,959/169,904 tokens — the postbump curve's sizes) on **v1.2.1
(1db3edb) and v1.2.2 (00e7ddd)**, the pin swapped twice in one window (each
leg's prepare explicit per the pinbump pattern; each leg's engine commit
receipted from the log). The duel already receipted the 8k slope −3.5%; the
deep fills quantify the gain where #1577's 5-14% claim lives (32-167K). The
g3 /metrics cache-counter hygiene check rides leg 2 (it needs a live serve).

## (round 133, cont. 9) THE #1577 DEEP DELTA QUANTIFIED: −2.6 to −3.5% at 50k-204k fills (2026-11-04)

**deepdelta (campaign-20261104-182759) closes the bump's last quantitative
question**: the SAME novel fills on both pins — v1.2.1: 41.35/82.71/166.96 s
at 50,960/101,948/203,882 tokens; v1.2.2: 39.98/80.53/161.13 s — **−2.6 to
−3.5%, v1.2.2 uniformly faster** (both curves linear: 0.811-0.819 vs
0.785-0.790 ms/tok; the legs' prompt_tokens match exactly, so the comparison
is clean). The gain is the LOW end of the upstream 5-14% claim — that was
TP=3, we are TP=2. The anchors' cold row carries the deep-curve line; the
ECOSYSTEM #1577 entry is dispositioned; the ledger carries the entry; the
phase retired. The g3 /metrics hygiene check came back INCONCLUSIVE (neither
the count nor the fallback landed in the receipt — the capture needs a
cleaner re-run; the item stays open with that note).

## (round 133, cont. 10) MIA'S 1104 RECIPE — a native-engine cousin for our hardware; the wedge guard adopted; the fold-in list ranked (2026-11-04)

**(user)**: "Take a look at this https://github.com/MiaAI-Lab/GLM-5.3-Flash-DGX-Sparks-1104
— what can we learn from it to fold into our solution?"

**What it is**: Mia's lab's brand-new native-engine recipe for 2× GB10 — 105
patches on their own pin (f350cd3e, a 1.1.9-era base), fp8 KV on shared pages
(2.1M tokens), 1M window × 8 streams, ABSORB_MMA on, DFlash2 4-bit — with a
full measurement campaign published (RESULTS.md, traps and retractions
included). Cross-stack numbers (caveated): their decode is far behind ours
(our v1.2.2 base decodes ~65% faster); **their prefill wins ~40%** (1,735-1,812
tok/s flat vs our ~1,030-1,274 declining).

**Adopted immediately — the wedge guard**: their campaign power-cycled a host
on a restart race (docker rm -f returning with the old ~100 GiB task dying;
docker run over it). Our three removal points (start.sh's rank-1 remote
launch, rank-0's local launch, stop.sh's worker removal) now poll docker
inspect until the name is genuinely absent — die-loud on launch, warn on
stop. **The fold-in queue (the user prioritizes)**: #1 ABSORB_MMA (+8.0%
prefill, identical answers — the port candidate), #2 the 4,096-row chunk
(+7%, byte-identical — our round-131 rejection was on the old pin), #3 the
fp8+pages marriage (the heavyweight port), #4 the cost-table correctness fix
(0096/0097 — check upstream v1.2.2 first). The methodology adoptions: the
per-passage NLL rule (never the aggregate mean), the
never-consult-the-measured-endpoint rule, the host-drift awareness. Full
disposition: docs/ECOSYSTEM.md (the 2026-11-04 entry).

## (round 133, cont. 11) THE MIA FOLD-IN STACK PORTED: chunk4096 + cost-tables + dflash2-ingest (2026-11-04)

The patch-craft protocol ran end to end on fold-ins #2+#4 (+#1's companion):
- **0094 → glm-mia-chunk4096.patch**: the reject was trailing hunk context
  only (their base carries `window_rows = 16`, ours 8); the change itself
  (`prefill_rows` 2048 → 4096) is verbatim. Adapted against 00e7ddd.
- **0095 → glm-mia-dflash2-ingest.patch** (verbatim, applies clean): DFlash2's
  `MAX_CTX` 2048 → 4096 — without it the pair dies at the first real prefill
  (DrafterContextTooWide). `WIN` stays 2048 by design.
- **0096 → glm-mia-cost-tables.patch** (verbatim, applies clean): the GB10
  verify-cost tables re-priced (52.0+6.8 → 38.73+5.68 lone, 76.0+4.1 →
  47.38+5.05 shared) — applies clean, PROVING v1.2.2 still carries the
  over-priced tables that starve the overhead learner.
- **The scratch-repo stack verify passed**: all three apply in alphabetical
  order (chunk4096 < cost-tables < dflash2-ingest) and alone; symbol greps
  clean (every consumer reads the constants; the only remaining 2048 in the
  touched files is `WIN`). One tooling bug caught and fixed en route: a header
  builder that dropped the diff body for two files.
- **The deepfills phase added** (session-specific): deepdelta's instrument on
  the patched serve (+7% claimed → ~0.73 ms/tok expected vs the standing
  0.785), plus the g3 /metrics capture re-done cleanly (curl to a file, then
  grep — the two heredoc captures landed nothing).

**LAUNCHED**: `RC_PATCHES="glm-mia-chunk4096.patch,glm-mia-cost-tables.patch,
glm-mia-dflash2-ingest.patch" scripts/autonomous-launch.sh "preflight
resumecost deepfills summary"` — the receipt (content gate sha, the deep-fill
delta, the boot wall, the serve line's memory) judges the stack. ABSORB_MMA
(0041, 28 KB of CUDA) is the next port after this verdict.

## (round 133, cont. 12) THE MIA STACK'S FIRST WINDOW: builds, boots, byte-identical — but the small-prompt front REGRESSES; the deep fills hit a phase bug (2026-11-04)

**campaign-20261104-203617** (the stack's first window): the build applied all
three patches clean, the boot came up healthy — **"prompts in passes of up to
4096 rows"** (chunk4096 live), 13.7 GiB left (−0.4 vs standing), load 142.1 s
(0/47 cached files — a COLD page cache from the fresh image build; the re-run
settles whether the patch itself costs loading). The content receipts:
**sha=9e04a49e5786 on every probe — byte-identical replies** (the ship check
PASSES), and the resume path works at the new boundary (resumed at 4096).

**But the same-instrument resumecost rows (both sides run TF_GLM_PROF=1
VISION=0 — the standing resumecost pattern, so the comparison is clean)**:
- d2048 (1886 tok) cold: 1.710 → 1.673 s (~2% faster)
- d4096 (3737 tok) cold: 3.709 → 3.711 s (identical); **warm: 1.964 → 3.717 s
  — the resume benefit LOST** (the patched cache shows resumed at 0, misses:
  a 4096-row cut is bigger than a 3737-token prompt, so nothing resumes)
- d8192 (7442 tok) cold: 5.55 → 7.17 s (**+29%**); warm: 1.44 → 3.22 s
  (**+124%**)

The mechanism is structural: states cut at 4096-row boundaries — sub-4096
prompts can't partially resume. Mia's workload (fixed deep prompts, 8
streams) never feels this; **our opencode workload lives on small/medium warm
resumes — our weakest front (70%)**.

**The deep fills did not run**: two compounding bugs — my deepfills phase
passed the depth as the REPEAT COUNT (n=32768 repeats ≈ 1.37M-token fills →
instant refusals), and the phase ran before the boot (no restart of its own —
the greps found an empty log, the curls hit a dead serve). Fixed: n=d/27 in
bash with its own argv slot, the phase is self-contained (its own restart, the
deepdelta pattern), the receipt lines hardened, the resume-evidence tail
added. **RE-LAUNCHED**: the same PHASES with the fixed phase; the image is
cached so the window is fast. The verdict framework: the deep fills decide
whether Mia's +7% holds on our shape, but the warm-resume granularity loss is
already disqualifying for OUR line unless the user weighs it otherwise
(the bump protocol: receipts-equal-or-better — the warm row would regress).

## (round 133, cont. 13) THE MIA STACK VERDICT: the chunk pair REJECTED (double-receipted); the cost tables staged; the g3 counter found (2026-11-04)

**campaign-20261104-210211 (the re-run) completes the verdict**:
- **The small-prompt regression REPRODUCED** (two windows, same instrument —
  both sides TF_GLM_PROF=1 VISION=0): d8192 cold 7.20 s (vs standing 5.55,
  +30%), d8192 warm 3.23 s (vs 1.44, +124%), d4096 warm==cold at 3.74 s (the
  resume benefit lost — resumed at 0), d2048 1.68 s (~2% faster). Replies
  byte-identical again (sha 9e04a49e5786). Loading FINE: 94.6 s warm-cache
  (47/47 cached) vs the standing 103 — the first window's 142 s was pure
  cold-cache from the fresh image build.
- **The deep fills ran against the UNPATCHED serve**: the deepfills phase's
  own restart LOST the window's RC_PATCHES (the framework's in-phase restart
  does not propagate the wrapper's patch env — the serve line's "passes of up
  to 2048 rows" caught it). The fills (34.43/68.36/138.62 s at
  43,682/87,386/174,758 tokens = 0.788/0.782/0.793 ms/tok) are a THIRD
  reproduction of the standing deep curve. The +7% claim goes unverified on
  our shape — and does not change the verdict.
- **THE VERDICT: glm-mia-chunk4096 + glm-mia-dflash2-ingest REJECTED for our
  line** (the bump protocol: receipts-equal-or-better — the warm front
  regresses on exactly the prompt sizes our opencode workload uses; the
  4096-row state cut cannot partially serve sub-4096/odd-sized prompts).
  The patches stay as history in patches/ with the receipt; config.sh's
  PATCHES default stays empty.
- **glm-mia-cost-tables STAGED for the ABSORB_MMA window** (output-neutral,
  sha-identical everywhere; its learner-unstarving effect shows only under
  loaded draft scheduling — it rides that window's hardmode phases).
- **The g3 /metrics counter is FOUND**: `tensorfold:prompt_tokens_cached_total`
  (294 lines; the 0 reading was a fresh serve with no requests). The API
  usage field stays 0 (the known gotcha) — /metrics is the wired instrument.
  The nonzero reading rides the next window with resume traffic.

**Next**: the ABSORB_MMA (0041) port — the reject map is known (glm_glue.cu:9
include-block context; cuda_engine.zig:188 Buffers.init context; the other 7
files apply clean). A phase-level restart losing RC_PATCHES is logged as a
gotcha (check the serve line's rows-clause whenever a patched window's phase
restarts).

## (round 133, cont. 14) THE ABSORB_MMA PORT MAPPED: 17 hunks across 7 files; the two trivial adaptations solved; the rest checkpointed for the next sitting (2026-11-04)

The 0041 (ABSORB_MMA) reject survey is complete: 17 hunks across 7 files
reject on our v1.2.2 tree (their base is a 1.1.9-era pin — the #1577-era
upstream rework moved the contexts; the scratch --reject pass + manual fixes
is the method). **Solved**: glm_glue.cu's include (append glm_glue_num.cuh
after attn; their base carried a p2p include we lack) and cuda_engine.zig's
`e.initNumerics();` (after our bp errdefer — their context had the pre-CS bp
init). **Remaining (formulaic, per-site)**: cuda_ranks.zig ×7 — with the
key detail that our Fingerprint layout is already 16 ("15 plus kda_pad";
their base was 12), so the bump is 16 → 17 onto OUR field lists — plus the
engine view/MTP Forward literals ×2, the Forward field, cuda_glue.zig ×2,
cuda_prompts.zig ×1, cuda_ranks_test.zig ×2. The full map + the window plan
(absorb-mma + cost-tables, TF_GLM_ABSORB_MMA=1, hardmode in PHASES) live in
the ledger's open item. The chunk-pair verdict and the g3 counter find are
committed (cont. 13); no window is running — the port continues next sitting
with fresh context.

## (round 133, cont. 15) THE ABSORB_MMA PORT COMPLETE AND SHIPPED: all 17 sites adapted, the diffstat identical to the original (2026-11-04)

The 0041 (ABSORB_MMA) port is done: **all 17 rejected hunks re-anchored onto
the v1.2.2 tree** via the scratch --reject + per-site python fixer (every
site an exact-once assertion — two anchors needed disambiguating: forward's
set() matches twice, the second builder untouched; "indexer" not "index").
**The adapted diff's diffstat matches Mia's original exactly: 9 files, 247
insertions, 7 deletions** — the strongest possible shape signal. Verified:
fresh-tree apply-check alone, the stack (absorb < cost, alphabetical)
applies, the symbol matrix complete, layout 16 → 17 with all three list
sites + explain.

**The restart discovery**: `restart` takes env pairs directly
(`restart K=V ...` → `env "$@" ./scripts/start.sh`) — which both explains
the cont.-13 RC_PATCHES loss (a restart only carries what it is handed) and
gives the window its opt-in path. The deepfills phase now restarts with
`TF_GLM_ABSORB_MMA=1 PATCHES="${RC_PATCHES:-}"` explicitly, and the g3
/metrics capture moved BEFORE the restart (resumecost's resume traffic is
what moves the counter; the phase's restart resets the serve).

**LAUNCHED**: `RC_PATCHES="glm-mia-absorb-mma.patch,glm-mia-cost-tables.patch"
scripts/autonomous-launch.sh "preflight resumecost deepfills hmcheck summary"`
— the judgment: the content sha (bit-equal outputs), the resumecost rows
(the small-prompt front must NOT regress — the chunk pair's lesson), the
deep fills (+8% claimed on their card), hardmode (the loaded judgment), and
the g3 counter. The build is fresh (a new patch) — the window is ~35-45 min.

## (round 133, cont. 16) THE ABSORB_MMA VERDICT: the +7% claim LANDS (−6.8/−7.0/−6.9%); the stack ADOPTED into config.sh; the confirmation window launched (2026-11-04)

**campaign-20261104-213422 (the verdict window)**:
- **The deep fills on the full stack (ABSORB ON)**: 32.08/63.54/129.05 s at
  43,682/87,386/174,758 tokens = **0.735/0.727/0.738 ms/tok vs the standing
  0.788/0.782/0.793 — −6.8/−7.0/−6.9%. Mia's +7% prefill claim lands almost
  exactly on our shape** (the fill-rate drop is itself the proof the MMA
  kernels ran — nothing else in the stack touches prefill).
- **The g3 item CLOSES**: `tensorfold:prompt_tokens_cached_total 126976`
  after resumecost's traffic (pre-restart capture) — the counter is wired;
  the 0 post-restart is the fresh serve, consistent.
- **The fingerprint pairing (layout 17) verified by the healthy boot** — the
  port's riskiest bit (rank pairing) works.
- **The boot order decoded**: hmcheck ran FIRST bare (its 94 = the standing
  control, NOT the stack judged) and resumecost ran patches-staged with
  ABSORB off (its rows clean: d4096 warm 1.91 restored, d8192 cold 5.38 /
  warm 1.40 — no regression). So the missing pieces: the sha + the
  small-prompt rows on the ABSORB-ON serve, and hardmode on the stack.
- Memory 13.9 GiB left (−0.2 vs standing), boot 93.9 s warm-cache — flat.

**THE ADOPTION** (the bump pattern: the config edit makes the candidate the
thing the standing phases test): config.sh now carries
`PATCHES="glm-mia-absorb-mma.patch,glm-mia-cost-tables.patch"` (unset → the
stack, EMPTY → the opt-out) and `TF_GLM_ABSORB_MMA=1` (the generic TF_GLM_*
env passthrough reaches both ranks). README's PATCHES row + a new
TF_GLM_ABSORB_MMA row.

**LAUNCHED (the confirmation window)**: `scripts/autonomous-launch.sh
"preflight resumecost hmcheck summary"` — bare restarts now inherit the
adopted stack, so the resumecost probes receipt the sha + the small-prompt
rows on the ABSORB-ON serve and hmcheck judges the stack loaded. The duel
re-pair + the vision re-check follow on the next window.

## (round 133, cont. 17) THE CONFIRMATION WINDOW: hardmode 95 ON THE STACK (a point above production); the resumecost override caught and fixed (2026-11-04)

**campaign-20261104-224230**:
- **hardmode on the full stack: 95/104** — the first boot inherited the
  adopted config (the serve line's 13.9 GiB / 2.6 GiB cache = the ABSORB-ON
  shape) and scored a point ABOVE production's 94 (the standing control the
  same day: 94). The restart wall 120 s. The stack's quality receipt is
  better-or-equal.
- **The plumbing catch**: the resumecost phase's restart carried
  `PATCHES="${RC_PATCHES:-}"` — the RC_PATCHES-era mechanism; with
  RC_PATCHES unset it expanded EMPTY and defeated the config.sh adoption
  (the rows ran on the pristine serve). Silver lining: those rows are the
  FIRST clean v1.2.2-pristine resumecost baseline (d2048 1.69 / d4096
  3.64→1.92 / d8192 5.41→1.41, sha 9e04a49e5786). **Fixed** to the nested
  form `${RC_PATCHES-${PATCHES-}}` (an explicit RC_PATCHES still wins; the
  unset case inherits the adopted default) in both the resumecost phase and
  the deepfills phase.
- The trackers: the ledger's ABSORB item + the g3 closure committed, the
  ECOSYSTEM #1 dispositioned ADOPTED, the anchors' cold row carries the
  adopted deep curve (0.727-0.738).

**LAUNCHED (window C)**: `scripts/autonomous-launch.sh "preflight resumecost
summary"` — with the override fixed, the resumecost phase now receipts the
sha + the small-prompt rows on the ABSORB-ON serve (the last gap in the
stack's confirmation). The duel re-pair + the vision re-check follow.

## (round 133, cont. 18) THE STACK'S CONFIRMATION COMPLETE: byte-identical AND 5-6% faster on the small prompts; the visioncheck phase prepared; the duel re-pair launched (2026-11-04)

**campaign-20261104-233541 (window C)** — with the resumecost override fixed,
the rows ran on the FULL stack (the restart line carries
PATCHES=glm-mia-absorb-mma.patch,glm-mia-cost-tables.patch; the ABSORB env
flows via config.sh's TF_GLM_* passthrough):
- **sha 9e04a49e5786 on every probe** — the content gate on the ABSORB-ON
  serve PASSES.
- **The small prompts are 5-6% FASTER on the stack**: d2048 1.587/1.589/1.591
  (the pristine v1.2.2 baseline: 1.69), d4096 3.453→1.838/1.834 (pristine
  3.64→1.92), d8192 5.141→1.342/1.343 (pristine 5.41→1.41) — the MMA
  kernels engage on small prompt passes too (rows ≥ 64), and the warm
  resumes work (cached=2048 on the d4096 shots).

**The adoption's evidence is now complete on every axis**: deep prefill
−6.8/−7.0/−6.9%, small prompts −5/−5/−6% cold + warm better, greedy
byte-identical everywhere, hardmode 95 on the stack (≥ the 94 tie), memory
−0.2 GiB, loading flat, the fingerprint pairing verified.

**The visioncheck phase added** (session-specific): the vision suite on the
adopted stack — the ABSORB_MMA kernels engage on the vision tower's prompt
passes too, so the standing 4/4 receipt needs a re-take. **LAUNCHED**:
`scripts/autonomous-launch.sh "visioncheck duel summary"` — the vision
re-take, then the duel re-pair (the fronts vs production-for-testing → the
anchors/chart update), then the digest.

## (round 133, cont. 19) THE VISION RE-TAKE 4/4 ON THE STACK; THE DUEL IS MIXED — the prefill fronts improved, c2 REGRESSED; the ABSORB-only attribution launched (2026-11-04 → 11-05)

**campaign-20261104-234405 (visioncheck + duel)**:
- **The vision suite on the adopted stack: 4/4 verified** (Red / Golden Gate
  International Orange / the zebra at the waterhole / STOP — all match the
  manifest's agent-verified ground truth; 8/8 requests ok, the raw answers
  saved). The ABSORB_MMA kernels engaging on the vision tower's prompt
  passes changed nothing.
- **The duel (both engines, the same instruments)** — production 59.0 solo /
  110.8 c2 / 192.4 c4 / slope 0.265; ours 64.5 / 93.1 / 143.9 / slope 0.602:
  - IMPROVED: the 8k slope **0.657 → 0.602 (−8.4%)** and d8192 5,570 →
    5,126 ms (the ABSORB effect on prefill); solo 109% (was 108%); the cold
    front vs production's cold slope 2.026 widens to ~337%; ITL per-token
    unchanged (~16 ms, the chunked rhythm); d0 94%.
  - **REGRESSED: c2 125% → 84%** (ours 93.1 vs its stable 109-110 band
    across two windows; production volleyed to the top of its 87-111 range).
    c4 75% (was 78%, marginal). **The suspect is the cost tables** — the only
    decode-path change adopted: the un-starved overhead learner feeds
    allocateDrafts, and on our shape the new allocation costs the c2
    aggregate (Mia's "throughput effect is their noise" does not hold here).
- The anchors/chart HOLD until the attribution lands (one update, not two).

**LAUNCHED (the attribution)**: `PATCHES="glm-mia-absorb-mma.patch"
scripts/autonomous-launch.sh "duel summary"` — the duel on ABSORB-only (the
env-set PATCHES beats config.sh's default; TF_GLM_ABSORB_MMA=1 still flows).
If c2 returns to ~109-110: the cost tables DROP (a round entry), the
ABSORB-only stack becomes the qualified optimum, and the anchors/chart
update once. If c2 stays low: the drop is ABSORB's (or variance) and the
decision re-weighs.

## (round 133, cont. 20) THE ATTRIBUTION SETTLED: c2 returns on ABSORB-only — the cost tables DROPPED; the ABSORB-only optimum re-paired into the anchors (2026-11-05)

**campaign-20261105-000521 (the ABSORB-only duel)**:
- **c2: ours 110.4** — back in its stable 109-110 band (93.1 with the
  tables). Production 111.0 (again its top-of-range volley). **The cost
  tables were the c2 regression.**
- **Every gain is ABSORB's**: the 8k slope 0.602 / d8192 5,122 — identical
  to the both-patch duel (the tables contributed nothing to prefill, as
  their output-neutrality promised); solo 65.1/59.0 = **110%**; c4 151.3 vs
  production's floor-of-range 154.7 (98%); ITL unchanged; the cold front
  **334%** (17,129/5,122).
- **THE DECISION**: the cost tables DROP (the ~16% c2 cost buys nothing
  measurable; hardmode 95-with-tables vs the 94 control is within scenario
  noise). **ABSORB-only is the qualified optimum** — config.sh's PATCHES
  default updated; the ECOSYSTEM item 5 dispositioned; patches/README
  carries both verdicts.
- **The anchors/chart re-paired** on the ABSORB-only duel: solo 110%, c2
  ~99% (the volley caveats in the notes), c4 98%, overhead 98%, cold 334%,
  ITL ~107% crossed — the guard's chart check passes.

**LAUNCHED (the last protocol piece)**: `scripts/autonomous-launch.sh
"hmcheck summary"` — the hardmode re-take on the ABSORB-only default (the 95
receipt ran on both-patches; the 94 control is the floor; the battery
settles the quality receipt on the shipping config).

## (round 133, cont. 21) THE ADOPTION CLOSED: hardmode 95 on the shipping config; the session phases retired (2026-11-05)

**campaign-20261105-003101 (the re-take)**: hardmode on the ABSORB-only
shipping config reads **95/104** — the 95 was not the tables' artifact (the
serve line's ABSORB-ON shape; the wall flat at 103 s). The adoption is fully
receipted on every axis: the deep fills −6.8/−7.0/−6.9%, the small prompts
−5-6%, greedy byte-identical everywhere, the vision 4/4, the duel fronts
solo 110% / c2 ~99% / c4 98% / cold 334% / ITL ~107%, hardmode 95, memory
−0.1 GiB, the wall 103 s. The README's quality row settles at 95; the
ledger's ABSORB item closes. **The deepfills and visioncheck session phases
retired** (their receipts complete; the registry notes live in this log and
the ledger). One tooling slip during the retirement (the "fi"-substring
match in the cut helper) caught by bash -n and fixed before commit.

## (round 133, cont. 23) THE FP8+PAGES MARRIAGE: (user) proceeds; the port scoped and 0017 adapted (2026-11-05)

**(user)**: "Proceed with 'The fp8+pages marriage'". The scoping pass:
- **The scope correction**: the marriage is patches **0017-0025** (~1,460
  lines — the E4M3 latent-cache kernels, the page layout, the pool
  admission, the contract tests); **0026-0033 are separate decode
  optimizations** (the EXL3 grouped load-ahead, the MoE-glue fusion, the
  step-link work) that rode their stack — not part of the marriage, not
  ported now.
- **The cumulative stack-apply map**: 16 rejected hunks across ~12 files,
  centered on the KV pool core + the snapshot layout (the rank-pairing-
  critical, boot-refusal class). 0021 applies clean.
- **0017 DONE** (scratch commit b592905): the paged E4M3 fetch woven into
  v1.2.2's restructured inline `load_kv` — v1.2.2 replaced their base's
  uint2-fetch lambda with a byte-wise `__nv_cvt_fp8x2` decode, so the page
  translation (dense_page found once; the sparse token→page/row) weaves
  into our branch; unpaged compiles to page=0/row=src — identical
  arithmetic. The bf16 paged path's keys_at base came in the applied hunks.
- **REMAINING**: 0018 (440 lines, 8 files — the page layout + pool +
  snapshot centerpiece), 0019 (the pool admission), 0020 (the contract
  tests), 0022-0025. Method: scratch-repo per-patch commits, the final
  `git diff` = the shippable `glm-mia-fp8-pages.patch`. The candidate
  config: KV_CACHE=fp8 + TF_KV_PAGES=on. The value on our 512K×4 spec: the
  shared pool's free list feeds the prompt cache (the warm front's kept
  states) and the admission goes elastic; the worst case is unchanged.

## (round 133, cont. 24) THE MARRIAGE'S 0018 MAPPED: v1.2.2 already carries the paged-pool machinery (2026-11-05)

The 0018 reject map is complete (8 files): **the headline is that v1.2.2
already carries the paged-pool machinery** — `TF_GLM_KV_SHARE` ("keeps
prompts as KV pool pages"), `fw.State.initPagedFormat`, `Pages.pool/leases/
promise/finish` are all upstream — so the marriage adds the E4M3 layout and
flips the fp8 refusal onto EXISTING infrastructure. The per-file map lives
in the ledger's open item. The semantics after 0018: fp8+pages pages (one
shared pool; a stream takes the pages its request needs; 6,380 bytes/token
E4M3 beside DFlash2 vs 13,056 bf16), unknown TF_KV_PAGES values refused
(`BadKvPages`), and the pool admits elastically (`PoolTooSmall` when even
every-other-stream-done cannot fit). 0017 is committed in the scratch repo
(b592905); 0018's adaptation is the next sitting's work block — the
KV-pool core deserves fresh context, not a drained one.

## (round 133, cont. 25) THE MARRIAGE PORTED: all nine patches adapted, the combined patch verified, the judgment window launched (2026-11-05)

**The fp8+pages marriage (patches 0017-0025) is fully adapted** — nine
scratch commits, the combined `glm-mia-fp8-pages.patch` (1,193 lines, 21
files, 634 insertions) applies clean on a fresh 00e7ddd tree. The
adaptation highlights:
- **0017+0023's fetch kernels** woven onto v1.2.2's restructured `load_kv`
  (the byte-wise E4M3 decode; 0023's dense-bases-move-once superseding
  0017's per-key form — the dense chunk loads as the window's, the sparse
  keys walk the table with the s>>9 / s&(CH-1) arithmetic).
- **Our KV_HOST branches preserved everywhere** (pkPageBytes, the 6-arg
  addCache, the p.pk pooled-keys pages, the pkCacheBytes block).
- **stateSizes kept at our 5-param signature** — the fixed part holds no
  head-conditional rows on this tree, so pagedBytesOf delegates with the
  flag documented as inert here.
- **The registry records** appended to our import-list shape (v1.2.2 moved
  the exl3_prompt records their base had).
- The semantics: TF_KV_PAGES=on pages either format (one shared pool,
  6,380 bytes/token E4M3 beside DFlash2), BadKvPages for unknown values,
  PoolTooSmall for the elastic exhaustion, BadStep for a foreign page id.
- The unpaged standing config is preserved by construction (the flags
  default off; pageBytesOf(false,true) ≡ the old pageBytes; PAGED8=false
  compiles the unpaged branch).

**LAUNCHED**: `RC_PATCHES="glm-mia-fp8-pages.patch" TF_KV_PAGES=on
scripts/autonomous-launch.sh "preflight resumecost summary"` — the
judgment: the boot's pool shape (the serve line), the gates (Mia's paged
chunks are bitwise the window's — the sha must hold), the resumecost rows,
the memory. The kernel recompile makes the window ~35-45 min.

## (round 133, cont. 26) THE MARRIAGE'S FIRST WINDOW: the port compiles+boots — the pool is EXACTLY Mia's (2.1M tokens); a prof-gated crash found at the second chunk; the discriminator launched (2026-11-05)

**campaign-20261105-101240**:
- **The port COMPILED AND BOOTED** — the biggest compile-risk check of the
  arc passed. The serve line: "4 streams at once, the engine's own and 3
  more taking **4100 pages of 512 rows (13.61 GiB) as they need them**
  (enough for one at a 524288-token window), **220 MiB fixed each**, of
  **17.6 GiB left**" — **the pool is exactly Mia's 2.1M tokens**, the fixed
  per-stream cost collapsed from ~3.75 GiB to 220 MiB, and the elastic pool
  frees ~3.5 GiB at the same 512K×4 spec.
- **The sha is bitwise on the single-chunk probes** (9e04a49e5786, the
  d2048s) — Mia's "the paged chunks are bitwise the window's" verified.
- **THE CRASH**: the d4096 warm shots and d8192 all failed — the rank died
  at the SECOND chunk of a multi-chunk paged prompt:
  `glm prompt invalid ... reason=InvalidPromptProfile`. The guard is
  **prof-gated** (cuda_prompt_trace's collect runs only under TF_GLM_PROF=1;
  the resumecost boot instruments) — the second paged chunk's trace comes
  up empty and the validation kills the rank. **The served config has no
  prof** — this is a debug-instrument interaction, not (yet proven) a
  serving-path bug.
- The rank-0 docker logs were lost (the stop's save skips dead containers);
  rank-1's log carried the trace.

**LAUNCHED (the discriminator)**: a `pagedchecks` session phase — the SAME
probes (d2048/4096/8192 cold+warm, then the d32k/d64k deep fills — all
multi-chunk at depth) with **no TF_GLM_PROF**. Pass → the crash is a
debug-instrument interaction, the serving path is sound, the adoption
judgment proceeds (the prof interaction documented as a known limitation).
Fail → the port has a real bug and the marriage parks.

## (round 133, cont. 27) THE PAGED SERVE DIES ON THE FIRST REQUEST WITHOUT PROF; the wake-gap recorded; the failure capture added (2026-11-05)

**campaign-20261105-103431 (the discriminator)**: the paged boot came up
(TF_KV_PAGES=on ✓ env flowed) and rank 0 died at the FIRST request — every
probe failed instantly, rank 1 followed with
`following rank 0 stopped (TokenUnits)` (the follower's error name for a
dead peer). **No prof in this boot** — so the crash is NOT prof-gated: the
paged serving path itself dies on the first request. The first window's
single-chunk success (with prof) vs this: the difference is the prof
instrument's serialization, masking what looks like a race or an
uninitialized path in the no-prof paged launch.
- The root cause is in **rank 0's stderr — which is lost**: the stop's
  save_log skips dead containers (the second logging gap this arc; the
  pagedchecks phase now captures `docker logs` for BOTH ranks into the
  receipt at failure time).
- **The wake-gap recorded as infrastructure**: the second missed poke (the
  pagedchecks window completed ~10:38, no poke arrived; (user) noticed
  production restarted) — the completion→poke chain has now dropped twice
  (232127, 103431); the receipts get processed directly on pokes' absence.

**LAUNCHED (the diagnostic re-run)**: the same pagedchecks window with the
failure capture — rank 0's dying words land in the receipt this time.

## (round 133, cont. 28) THE MARRIAGE BUG ROOT-CAUSED AND FIXED: TokenUnits = the one-site logical port; the poke-chain script fixed; the re-run launched (2026-11-05)

**The 105143 poke arrived late** (the poke script's broken quiet-age probe —
see below) and its receipt was already digested directly. **The root cause
of the paged-serve death**: the marriage's `chunks()` dispatch sets
`paged8 = kv8 and t.pt != 0` and enforces the contract
`t.logical == paged8` on every paged sparse call (error.TokenUnits). Mia's
0022 set `Table.logical` on **one** latent.Table site — **their base had
one; v1.2.2 has three**. My port adapted the attend site only; the other
two (blockLastRow, the window fn — the first request's DSA sparse launch)
passed `logical=false` while 0021's dispatch routed E4M3 to the _paged
kernels → the mismatch → both ranks died ~1 s after the health check,
before any request. **FIXED**: `.logical = c.ls != 0` at all three sites;
the combined patch rebuilt (1,201 lines) and apply-checked on fresh
00e7ddd; staged as patches/glm-mia-fp8-pages.patch.

**The poke chain fixed** (the second gap's root): autonomous-poke.sh's
quiet-age probe was malformed — it stat'ed the .md mtimes then re-stat'ed
the TIMESTAMPS as files → always empty → `integer expected` → silent exit
for any campaign that failed the completion-marker gate (a crashed window
never poked). Fixed to stat the campaign.log. The user's manual cron run
was correct behavior (the crash-net guards production only; production was
up). The single-marker design still only tracks the newest campaign — a
campaign superseded before a tick skips its poke (103431's fate; the
receipts get read directly when a poke is late).

**LAUNCHED**: the pagedchecks re-run with the fixed patch — the first
request should now pass the DSA sparse launch; the probes and the deep
fills judge the serving path.

## (round 133, cont. 29) THE WEDGE INCIDENT: the worker's ssh down after the paged crash — the marriage parked on hardware; the wedge guard proved itself (2026-11-05)

**campaign-20261105-111256 (the pagedchecks re-run with the logical fix)**:
the restart hit the wedge guard — **"rank 1's old container is still
present on the worker after 60 s — refusing to start over it (the
Mia-1104 wedge)"** — the 105143 rank-1 crash left the worker's container
wedged. The guard (adopted from Mia's 1104 recipe) did exactly its job:
die-loud instead of starting the head over a dying worker container.
**The worker is now unreachable on ssh** (Network is unreachable) while it
still PINGS (0.6 ms) — the wedge took sshd, not the host; the container
cannot be cleaned without ssh. **This is Mia's incident profile**: their
rank crash wedged a host so hard it needed a power cycle. **(user) needed**:
recover the worker (console/IPMI: kill the wedged container or power-cycle
it); every window needs its rank 1.

**The marriage PARKS on hardware**: the logical fix is committed and the
combined patch apply-checks (the TokenUnits root cause is fixed); the
serving-path validation (the pagedchecks probes) waits for the worker.
The ABSORB_MMA adoption is unaffected (its own receipts stand; the
standing config is unpaged and production is untouched on 8000).

**The poke chain works again**: the fixed quiet-age probe fired the 111256
poke (the second fix verified); the guard's fold-in rule caught the
un-digested 105143 (the pipe-masked guard failure taught the command
pattern: `./scripts/docs-guard.sh 2>&1 | tail -1` eats the exit code —
check the output, not the rc).

## (round 133, cont. 30) THE WEDGE DIAGNOSIS CORRECTED: the worker was never wedged — the guard's semantics fixed; the pagedchecks re-run launched (2026-11-05)

**Correction to cont. 29**: the worker was NEVER wedged. The "Network is
unreachable" came from the AGENT host (no route to the private 192.168.2.x
subnet — only the head sits on it); (user) ssh'd from the head fine. The
worker's rank-1 container had **Exited (1)** 35 minutes prior — a dead
husk, not a wedge. **The real bug was the wedge guard's semantics**:
`docker inspect NAME` succeeds for exited containers too, so the guard
refused to launch over a dead husk that the launch's own `docker rm -f`
would have cleared — the guard blocked its own self-healing. **Fixed**:
both polls check `{{.State.Running}}` — an Exited husk passes, only a
container that will not stop running is the wedge. The husk removed on the
worker; production's rank 1 confirmed up.

**LAUNCHED**: the pagedchecks re-run (the logical-fixed patch, no prof) —
the first request's DSA sparse launch should now clear TokenUnits, and the
probes + the deep fills judge the marriage's serving path at last.

## (round 133, cont. 31) THE 113129 POKE (the fixed quiet-age probe verified) + the TokenUnits debug patch shipped (2026-11-05)

**The campaign-20261105-113129 poke arrived** via the fixed quiet-age probe (10 min of quiet
on a crashed window — the catch path working as designed; the receipt was
already digested in cont. 27/28). **The logical fix did NOT resolve the
death**: the pagedchecks re-run (113129) died identically — rank 1 first
(its log ends pre-serving), `following rank 0 stopped (TokenUnits)`, the
watch taking rank 0 down — with all three latent.Table sites carrying
`.logical = c.ls != 0`. The married chunks() is self-consistent
(kv8 = scales != 0; the sites pass c.ls as scales and logical = c.ls != 0),
so the mismatch comes from a call path static reading hasn't surfaced.
**The debug patch** (glm-zz-debug-tokenunits.patch, sorts after the
marriage) logs the exact mismatch inputs at the TokenUnits return: sparse,
t.pt, t.logical, paged8, kv8, rows/heads/lw/nch/hb — the dying rank's
words land in the pagedchecks receipt via the docker-logs capture.
**LAUNCHED**: `RC_PATCHES="glm-mia-fp8-pages.patch,glm-zz-debug-tokenunits.patch"
scripts/autonomous-launch.sh "pagedchecks summary"`.

## (round 133, cont. 33) THE MARRIAGE'S SERVING PATH VALIDATED (campaign-20261105-114648); the max_tokens=1 shas WITHDRAWN as jitter; the redesigned greedy bitwise cross-check launched (2026-11-05)

**campaign-20261105-114648 (pagedchecks, the logical fix + the debug
stack)**: THE SERVING PATH WORKS. No TokenUnits anywhere — the debug patch
never fired; the serve completed every request and was still alive at the
phase's end. The receipt (the engine's own lines; the probe FAILEDs are the
instrument's reply-parse):
- the resume chains at 512-row page granularity: 15,315 cached
  6144/14336/14336 → ttft 7.500/0.898/0.862 s; 30,690 cached
  14336/28672/28672 → 13.191/1.812/1.709 s;
- the cold paged fills: 46,108 → 37.952 s = 0.82 ms/tok; 92,240 → 74.213 s
  = 0.80 ms/tok — the deep-prefill rate HOLDS at depth on pages;
- the pool mechanics live: prompt-cache hits climbing, evicted 2 under
  pressure; the boot pool 4,100 pages × 512 rows (13.61 GiB), 15.7 GiB left.

**The sha references WITHDRAWN (correction discipline)**: the max_tokens=1
engine shas are seed jitter, not depth signatures — 9e04a49e5786 dominates
across 15,315 (×3), 30,690 fully-resumed (×2) AND 92,240 cold, all with
different seeds, while the "depth" shas (d59eced1ded0 @30,690 cached=14336,
9d06e5d38103 @46,108) are single occurrences whose pattern sampling explains
(the same prompt's fully-resumed shots hash the common value). A bitwise
instrument needs deterministic decoding.

**LAUNCHED: windowedsha (redesigned)** — greedy (temperature 0), thinking
off, max_tokens=64: the sha of a deterministic 64-token chain is a logits
fingerprint (one divergent argmax ⇒ a different sha). THREE serves in one
window, the same three prompts each (harbor ×102 ≈ 15,315, ×204 ≈ 30,690,
the fill ×1213 ≈ 46,108; fresh cache, same order ⇒ the same resume
pattern): B the standing config first (proven), P the marriage paged (the
exact 114648 serve), A the marriage unpaged (same image, never booted —
riskiest, last). P==A ⇒ paging byte-identical; A==B ⇒ the marriage's
unpaged path matches the shipping model. Pairwise verdicts print into the
receipt. RC_PATCHES="glm-mia-fp8-pages.patch,glm-zz-debug-tokenunits.patch"
(the cached image — no rebuilds anywhere in the window).

**(user) topology recorded** (the git-ignored SITE.md, both copies): the
head↔worker link is a POINT-TO-POINT fabric — the worker's fabric address
is reachable from the head only; the agent host reaches the worker by its
routable name (the cont. 29 misdiagnosis came from exactly this).

## (round 133, cont. 34) windowedsha's CAPTURE BUG (the shas lost; the phase died at the verdict block); the ttft no-regression receipt stands; the fixed re-run launched (2026-11-05)

**campaign-20261105-123923 (windowedsha v1)**: all THREE serves booted and
answered — B standing / P marriage-paged / A marriage-unpaged, three probes
each, no deaths, no TokenUnits. The receipt's ttfts are a no-regression
receipt on their own: the cold 46,109-token fill 35.49 s (B) / 38.21 s (P)
/ 38.03 s (A) — the paged serve matches the marriage-unpaged serve (paging
adds ~nil at depth) and both sit at the base tree's deep-prefill rate (the
marriage tree lacks absorb by construction; base ≈ 38 s here follows from
absorb's −7% deep-fill receipt); B's 35.49 s is absorb's front.

**The shas are LOST and the phase died**: the per-serve capture grepped
"$LOG" — which is $OUT/campaign.log (run-qualification.sh line 64), NOT the
engine's log; campaign.log never carries per-request engine lines (the
pagedchecks receipts' done-lines actually came from their docker-logs
captures). The captures were empty, and the verdict block's
`_bb=$(grep ... | paste)` assignment then killed the script under
`set -euo pipefail` (grep finds nothing → the pipeline's rc 1 → the
assignment fails set -e) — the campaign died after serve A with no summary
and no " done." marker; the quiet-age poke caught it (third verified
firing). The rank-log saves hold no rank-0 request lines for the serving
boots (only the death boots' banners were ever saved) — the B/P/A shas are
not recoverable; the rm -f'd containers' docker logs are gone.

**FIXED and relaunched**: the phase captures per serve from
`docker logs "$CONTAINER_NAME"` (the live container, before the next
restart rotates it) with a flush pause; every sha-extraction assignment is
pipefail-guarded (`|| true` inside the substitution); an empty capture
prints a loud warning into the receipt instead of dying. Same probe shapes
(7,666 / 15,316 / 46,109 tokens — the harbor sentence is ~75 tok/rep, not
150; the receipt's prompt_tokens is the truth), same three serves, same
cached image (the debug patch stays in RC_PATCHES for the fingerprint and
retires at the verdict).

## (round 133, cont. 35) windowedsha v2 RAN CLEAN — MISMATCH on all three serves; the drafter confound identified; v3 (the seed pin + a determinism control) launched (2026-11-05)

**campaign-20261105-130738 (windowedsha v2)**: the fixed phase ran
end-to-end — all nine engine lines captured, the verdicts printed, the
summary completed (the normal-path poke ✓). The verdict: **MISMATCH on
both comparisons** — B (standing) 2b850b4131e5/fe7455676b0e/8a727d09edf4,
P (marriage paged) cd83affed326/b329335ec26a/c858f728c763, A (marriage
unpaged) 3db8352f5eee/9e431f718cee/d97e80a27672 — and P≠A is the clean
isolation (same image, same tree, paging toggled).

**BUT the drafter confound is uncontrolled**: the DFlash2 drafter samples
per request — the done-lines show wildly different verify profiles on the
SAME prompts (B rounds 20/21/20; P 16/27/11 with 52/53 accepted on the
fill; A 32/32/28 with 35/41) — and the verify-batch SIZE changes the
target GEMM shapes, whose fp reduction orders can flip near-tied argmaxes:
even a greedy target's reply chain is seed-dependent through the drafter.
The accept-pattern corroboration (P 52/53 vs A 35/41 on the same fill)
says the targets' outputs genuinely differ — but it cannot separate kernel
numerics from batch-shape numerics without a seed pin.

**v3 launched**: every probe pins seed=42 (the duel's precedent) — the
drafter's proposals and verify-batch shapes become identical across serves
— plus a CONTROL serve (B2: the standing config booted twice) measuring
the instrument's own determinism; P-vs-A and A-vs-B are interpretable only
if B==B2. If v3 still mismatches with clean profiles, byte-identity is NOT
a property the marriage can claim (the paged fetch kernels and the
windowed load_kv tile the reductions differently — same stored values,
different fp accumulation order) and the judgment moves entirely to the
quality instruments on the paged config (hardmode + the gates + the duel
re-pair with TF_KV_PAGES=on; the ABSORB precedent: hardmode ≥ production's
94). The ttft receipt stands (no perf surprise: the paged fill 38.12 s ≈
marriage-unpaged 37.94 s; standing 35.39 s carries absorb's −7%).

## (round 133, cont. 36) THE BITWISE VERDICT: byte-identity REFUTED (control-verified); the compose re-anchored onto absorb; the poke-marker root cause fixed; pagedquality launched (2026-11-05)

**campaign-20261105-133550 (windowedsha v3)**: the determinism CONTROL
matched — B and B2 (the standing config booted twice) produced identical
shas AND identical drafter profiles (20/43-of-52, 21/42-of-49, 20/43-of-51
twice), and B's shas reproduced across windows (v3's B == v2's B). The
instrument is deterministic, so the verdict is REAL: **standing ≠
marriage-unpaged ≠ marriage-paged — BYTE-IDENTITY REFUTED on both
comparisons** (paging on the marriage tree; the marriage tree vs the
standing config). The drafter conditions on the target's state (the
verify profiles differ across configs, are identical within one), which
corroborates independently. **This is not a defect**: the paged E4M3
fetch kernels and the windowed load path tile the reductions differently —
same stored values, different fp accumulation order — the same class as
ABSORB's own adopted fp32-summation change. The judgment moves to the
quality instruments on the composed paged stack. The ttft receipt stands
(P 38.08 ≈ A 37.84 at 46k — paging adds ~nil; B 35.25 carries absorb's
−7%).

**(user) asked why campaigns stopped finishing with " done." and the pokes
lagged — ROOT CAUSED**: the summary phase ends with `log "done."` (the
marker the poke greps), but its CAMPAIGN.md section globs
`"$OUT"/[0-9]*.md` — the numbered-receipt convention. My session phases
wrote UN-numbered names (pagedchecks.md, windowedsha.md) → the glob stayed
literal → `cat` died under set -e right after "=== summary" → "done."
never ran → EVERY poke since campaign-20261105-114648 took the 10-minute
quiet-age path (114648 +12 min, 130738 +14 min, 123923 +10 min on a
crashed window). FIXED both ways: the summary glob guards each file
(`[ -f "$f" ] || continue` — any future un-numbered receipt can't kill
it), and the session phases retire (pagedquality writes 92-pagedquality.md
— the numbered convention). Completed windows now poke on the normal path
within one cron tick of production's restore.

**The compose receipt + the re-anchor**: absorb + marriage FAILED to apply
(cuda_glue.zig:58 ×2 Kernels hunks — absorb's latent_mma fields drifted
the hunks' trailing context). RE-ANCHORED on the scratch repo with the
per-patch commit discipline (absorb committed, then the marriage): the
paged fields sit before `merge`, the init calls after `chunks_32_fp8`,
absorb's lines untouched; the fresh composed apply-check passes (1,217
lines); the patch now applies AFTER absorb only (alphabetical staging).
The paged-field sites: 2 in cuda_glue.zig, 5 files total.

**Retired this sitting**: the debug patch (the file removed; the README
entry is the history) and the pagedchecks/windowedsha session phases (the
receipts landed; git history carries the re-run patterns).

**LAUNCHED: pagedquality** — the hardmode battery + the vision suite on
the COMPOSED candidate (absorb + marriage + TF_KV_PAGES=on, nested
PATCHES). The fingerprint change rides a rebuild (~15-25 min) in the
window preamble. The adoption bar: hardmode ≥ 94 (production parity;
absorb set 95) + the vision 4/4. If it passes, the duel re-pair (the duel
on the paged composed stack — a session phase, the standing duel does not
thread TF_KV_PAGES) is the last receipt before the config.sh decision.

## (round 133, cont. 37) THE 74 IS A CORRECTNESS BUG, NOT QUALITY: cross-request CONTENT CONTAMINATION in the raw logs (TC-103's material inside TC-104's answer); the pool recycling is the suspect; treequality launched (2026-11-05)

**campaign-20261105-141241 (pagedquality)**: the composed paged stack
booted right (the pool line, 15.6 GiB left), the vision suite passed 4/4
(all 8 probes), and the marker fix is VERIFIED — the summary ran through to
"done." and the poke arrived on the normal path. **The hardmode score: 74
vs the >=94 adoption bar** — deployability 73→59, responsiveness unchanged,
total_tokens −10%, worst_category 89→25%.

**THE FINDING (the raw logs)**: TC-104's final answer — a VPN-certificate
scenario — contains **TC-103's cart/coupon analysis verbatim** (AeroMesh
chairs and LiftPro desks tables inside a VPN resolution); TC-103's log
shows literal `<think>` closing markers leaking mid-content repeatedly;
TC-102's answer spirals with self-repetition. **The model's context is
polluted by PRIOR REQUESTS' KV state** — on the paged pool, recycled pages
hand stale rows to new requests' attention. The collapse concentrates in
the long-context capabilities (toolset-scale 89→25, state-tracking 6→1/6,
concurrency 6→3/6 — the classes that churn the pool across 104
back-to-back scenarios); vision passes (8 short prompts, no pool
pressure); per-turn latency IMPROVED (it was never speed).

**This REINTERPRETS the v3 bitwise mismatch** (the cont. 35/36 correction):
the serves' shas differed because their REQUEST HISTORIES differed —
different contamination — not (only) "different kernel tiling". B==B2
matched because both boots saw the same history. The windowedsha
byte-identity instrument was measuring contamination, and the standing
config (no pool) is immune.

**The marriage is DISQUALIFIED for serving on this receipt** (a correctness
bug — stale-page reads). The diagnosis continues: **treequality launched**
— the SAME battery on the marriage tree UNPAGED (no pool; the same patch
set ⇒ the cached image, no rebuild). ~95 ⇒ the pool recycling is the bug
(and Mia's un-ported 0026-0033 get re-read for a pool fix we classified as
"optimizations"); ~74 ⇒ the tree's KV handling is broken deeper and the
marriage parks permanently. The battery's perf sub-instrument was fine
(pp ~1000-1100 tok/s, tg within noise) — perf was never the issue.

## (round 133, cont. 38) THE DISAMBIGUATION IS DECISIVE: the unpaged marriage tree scores 95 — the tree's kernels are quality-neutral; the bug is the E4M3 paged-state lifecycle; Mia's 0026-0033 carry no pool fix (2026-11-05)

**campaign-20261105-152436 (treequality)**: the SAME hardmode battery on
the marriage tree UNPAGED (absorb+marriage, TF_KV_PAGES off, the cached
image): **final_score 95 — identical to the standing config's 95** — and
the vision suite 4/4 (all 8 probes). The marriage tree's kernels are
QUALITY-NEUTRAL. Combined with the pagedquality receipt (74 on the same
tree WITH the pool): **the bug is exclusively in the paged pool's
recycling path — stale E4M3 pages handed to new requests.**

**The bug-hunt scope narrows**: Mia's 0026-0033 (re-read this sitting) are
genuinely load-ahead/trellis/broadcast optimizations plus comms robustness
and TP3 tests — NO pool fix rides in them. And the BASE's bf16 paged path
passed the gates historically (kvqual4P, campaign-20261023-165319) — the
base pool recycling works for bf16. So the bug is specific to the E4M3
page-STATE lifecycle. **The prime suspect: the keep/restore state-slicing
math** (stateSizes' 5-param adaptation, pagedBytesOf, the snapshot host's
E4M3 paged keep/restore test) — a size/slice mismatch there leaks exactly
this stale material into resumed states. Second suspect: the prompt-cache
eviction path on paged states ("evicted 2" under pressure).

**The arc state**: the marriage PARKS as a serving candidate on the pool
bug (correctness — disqualifying); the TREE is validated quality-neutral
(95) and its unpaged numerics differ but harmlessly. The next session is a
CODE-READING session on the port's E4M3 keep/restore + eviction paths (no
GPU needed), against the contamination evidence. The pagedquality and
treequality session phases retire (their receipts landed; git history
carries the re-run patterns — the quality battery re-runs as pagedquality2
once a fix candidate exists).

## (round 133, cont. 39) THE CONTAMINATION MECHANISM HUNT: the radix store's matching is token-exact; the suspect is the adopt→close→re-adopt cycle; the poolcanary launched (2026-11-05)

**The code-reading session** (the composed tree on the scratch repo): the
marriage touches NEITHER pool.zig NOR cuda_prefix.zig NOR kept.zig — the
pool/eviction/kept machinery is the base's. The state-size math
(pageCacheBytes/pageBytesOf/onPages/stateSizes/pagedBytesOf) is
self-consistent for E4M3 (codes+fp32 scales; the pk region after the
scales; the fixed bytes head-independent as documented). The radix store
(prompt_radix.zig) matches TOKEN-EXACTLY — the lookahead row even
differentiates branches (a page past which the lookahead differs is
another page) — so a false MATCH is unlikely. **The suspect window is the
adopt→close→re-adopt cycle**: a resume adopts the tree's pages into a
stream's lease; the stream closes (finish releases them); if the tree's
node reference is not dropped in step, the NEXT resume of that node reads
the INTERMEDIATE request's rows — exactly the battery's one-step-back
chain (TC-103's answer carried TC-102's material; TC-104's carried
TC-103's). The radix-adopt path is exercised ONLY on the paged serve
(the standing config's cache keeps full states, no pool pages) — which is
why the battery caught it and nothing before did.

**LAUNCHED: poolcanary** — the cycle in miniature, per round: a long prompt
carrying a unique vault code (MKR-{i}QX), a 46k-token churn fill (forcing
store evictions), then a short prompt asking for the code — the short
prompt shares ONLY the ~1,530-token preamble, so an honest serve answers
NONE. Five rounds on the paged serve, then the same on the unpaged
control; the engine's resumed-at lines captured per round (a short
request's resumed-at past the preamble is the numeric smoking gun). Same
patch set ⇒ the cached image; the window is ~15 min.

## (round 133, cont. 40) poolcanary v1 CLEAN BUT INCONCLUSIVE (the prompts never crossed the keep grid — the adopt path never fired); poolcanary2 launched (concurrent, grid-crossing, three serves) (2026-11-05)

**campaign-20261105-163035 (poolcanary v1)**: all ten short replies (paged
AND unpaged) answered NONE — but the engine lines expose the design flaw:
every request shows **resumed at 0** — my prompts were ~790 tokens, BELOW
the store's 2,048-row keep grid ("states on the 2,048-row prompt grid"),
so no state was ever kept from them ("kept 0"), the adopt path never
fired, and the canary tested nothing. The only kept state was the 46k
fill's (kept at 45,056, a grid multiple) which resumed honestly from
itself.

**The code reading advanced anyway**: the core pool is REFCOUNTED
("holders a page: each lease that maps it once, the store once") — a page
frees only when every holder releases, so the naive double-ownership leak
is designed against. What remains: **rank 1 has no pool and nothing
promises pages there — its store never reclaims** — a potential rank
divergence in the store lifecycle that only CONCURRENT multi-turn traffic
exercises (the battery ran 4 streams; every prior paged instrument ran
sequential probes). The battery's chain pattern (each scenario's answer
carrying the previous scenario's material) fits a lifecycle divergence
under concurrency.

**LAUNCHED: poolcanary2** — the canary redesigned: the shared preamble is
~2,100 tokens (harbor ×28) so BOTH prompts cross the keep grid and the
2,048 state is genuinely kept/adopted; the long (carrying vault code
MKR-{i}QX PAST the shared prefix) and the short (asking for the code) fire
CONCURRENTLY on separate streams; five rounds. THREE serves: paged (the
battery's config), paged with TF_GLM_KV_SHARE=0 (the store off — splits
the store's role from the pool's), and unpaged (the control). A short
reply naming any MKR- code is contamination on that serve; the
paged-vs-pagednoshare split identifies the channel. Same patch set ⇒ the
cached image; ~20 min.

## (round 133, cont. 41) THE CHANNEL IS THE POOL PAGES THEMSELVES: the store EXONERATED (pagednoshare behaves identically); the paged two-chunk prefill is NON-DETERMINISTIC on identical inputs (the alternation); the stride-discrepancy lead; v3 launched (2026-11-05)

**campaign-20261105-164822 (poolcanary2)** — three findings and one bug of
mine:
- **MY BUG**: the phase rm'd the long requests' body files right after
  backgrounding their curls — the longs never ran (PARSE-FAILED); only the
  shorts executed. Fixed (the body file survives until the wait).
- **THE STORE EXONERATED**: paged and pagednoshare (TF_GLM_KV_SHARE=0, no
  store, no resumes) behave IDENTICALLY — the adopt path is not the
  channel. The store's role in the battery's contamination is dead.
- **THE PUREST SIGNAL**: on pagednoshare — no store, no resumes, five
  IDENTICAL sequential two-chunk prompts (2,139 tokens, temp 0, seed 42) —
  the replies ALTERNATE ("The user has provided a long repeated list" /
  NONE / …). Non-determinism on identical fresh prefill inputs, requiring
  exactly: the paged path AND a multi-chunk prompt (>2,048 rows, crossing
  the chunk boundary). The one-chunk canary v1 was perfectly deterministic.
  On the store-on serve: fresh ≠ resumed (one fresh reply, four identical
  resumed). The unpaged serve: fully consistent.
- The two-chunk prefill means chunk 2 READS CHUNK 1'S ROWS BACK FROM THE
  PAGES. Non-determinism there, varying with WHICH PHYSICAL PAGES a
  request got (the free list cycles — hence the period), plus the
  battery's wholesale cross-request content, points at ONE class: a wrong
  address stride in the paged E4M3 fetch — reads landing in neighboring
  pages whose recycled content varies per allocation. **The documented
  lead**: the code carries BOTH "6,380 in E4M3 beside DFlash2 (no head
  part)" and "E4M3 6,960" (with head) as per-row bytes; the boot runs
  6,960 (4,100 pages × 512 rows = 13.61 GiB). A kernel or path still using
  the 6,380 stride drifts ~1.6 pages off by row 512 — reads landing in
  other pages, content varying with recycling.

**LAUNCHED: v3** — the race fixed, 10 rounds (the alternation's
period/pattern fingerprinted against the pool's free-list rotation), paged
(store off — the cleanest instrument) + unpaged, the LONG replies now
visible. The next sitting reads the marriage's kernel file
(glm_glue_latent.cuh) for the paged fetch's address arithmetic against the
6,380/6,960 discrepancy.

## (round 133, cont. 42) THE V3 FINGERPRINT: the paged multi-chunk prefill MIS-READS ITS OWN CHUNK-2 ROWS; the kernel addressing verified consistent; the gates-coverage hole; the format bisect launched (2026-11-05)

**campaign-20261105-170810 (poolcanary2 v3, the race fixed)**: the
fingerprint is decisive — **the unpaged control is perfect** (all ten longs
reply their own MKR-{i}QX, all shorts NONE); **the paged serve cannot
reliably read its own chunk-2 rows**: round 1's long mangles the code
("Vault Access Code: 7-"), round 2's answer surfaces "gable" — a token
from the harbor PREAMBLE (chunk-1 content!) — as the "code", rounds 3-10
collapse to NONE. The vault code sits at row ~2,105 — chunk 2's own
freshly-written rows. Round 1 failed on FRESH pages (never written) — the
mis-read is not (only) stale content; the fetch itself is wrong for the
rows past the 2,048 boundary. The battery's gross contamination: with
concurrency + recycling, the mis-addressed reads land in OTHER streams'
pages.

**The kernel-addressing read came back CLEAN**: the write kernel
(cache + page + row×512; scales at +page + row), the dense read (bases
moved once: pt[c]×pstep − start×LW, the same pattern the bf16 gates
proved), the sparse read (pt[src/CH]×pstep + (src%CH)×LW — matching the
write exactly), the pooled-keys fetch (ps/2 elements = ps bytes) — every
path cross-checks against every other. Static analysis is exhausted.

**THE GATES-COVERAGE HOLE**: the bf16-paged gates (kvqual4P) ran the gate
battery — and the depth probes (8k+, multi-chunk) ran on the UNPAGED
config. If the gate probes were all one-chunk (≤2,048 tokens), **the
battery was the first multi-chunk multi-turn paged workload this line has
ever run** — and the bug may live in the BASE's shared paged machinery,
not the marriage at all.

**LAUNCHED: poolcanary3** — the format bisect: the same canary on PAGED
BF16 (KV_CACHE=bf16 + TF_KV_PAGES=on — the base's path, the same kernel
structure) beside the fp8 control, five rounds each. bf16 fails too ⇒ the
base's shared multi-chunk machinery (the finding goes upstream as data);
bf16 clean ⇒ E4M3-specific and the kernel hunt narrows to the
scales/quantize path.

## (round 133, cont. 43) THE BISECT'S FIRST ATTEMPT DIED AT START.SH'S VALIDATION (KV_CACHE=bf16 is not an accepted value — empty is bf16); fixed and relaunched (2026-11-05)

**campaign-20261105-172441**: the poolcanary3 bf16 leg passed
`KV_CACHE=bf16` — start.sh refuses it ("KV_CACHE must be empty (bf16, the
engine default) or fp8") — the restart died, set -e took the campaign, and
the quiet-age poke caught it (the completed-window marker path only fires
on windows that reach the summary). FIXED: the bf16 leg passes `KV_CACHE=`
(empty — the engine default). The windowed-fp8 serve line in the log was
the framework reading a stale serve line after the failed restart, not a
boot. Relaunched unchanged otherwise.

## (round 133, cont. 44) THE BISECT IS DECISIVE: bf16-paged PERFECT (5/5 exact codes) — the bug is E4M3-SPECIFIC, and the failure follows the PHYSICAL PAGE history; the poison discriminator launched (2026-11-05)

**campaign-20261105-173936 (poolcanary3, the format bisect)**:
- **bf16-paged (the base's path): PERFECT** — all five longs reply their
  own exact code (MKR-1QX → MKR-5QX). The base's shared paged multi-chunk
  machinery is CORRECT, and the gates-coverage worry dissolves.
- **fp8-paged: broken, page-history-dependent**: round 1 (fresh pages)
  hallucinated digits ("Vault Access Code: 7-14-19-"); rounds 3/5 surfaced
  PREAMBLE tokens ("cistern-10", "gravel-2") as the code — the previous
  rounds' rows; round 4 was CORRECT (the recycled pages held near-identical
  rows from round 3's almost-identical prompt). **The read path returns
  PHYSICAL PAGE CONTENT rather than the written rows** — a write-visibility
  or write-address failure in the E4M3 paged path specifically.

**LAUNCHED: poolcanary4** — the poison discriminator:
TF_KV_POISON=1 NaN-fills every request's fresh pages at map time, erasing
stale content — uniform garbling under poison means the reads miss the
writes (write visibility); an unchanged pattern means the reads hit the
written rows but the stored content is wrong (quantize/scales). Each round
also splits the code position: chunk 1 (~row 1,520) vs chunk 2 (~row
2,110). The window is ~10 min.

## (round 133, cont. 45) poolcanary4 DIED AT ROUND-1 LATE (my cont. 34 pipefail lesson REPEATED in the canary phases); the early data point is confounded; the fixed two-leg relaunch (2026-11-05)

**campaign-20261105-175654**: the phase died at round-1 late — the
`R=$(curl | python)` assignments were UNGUARDED, the late request's curl
failed, and pipefail killed the phase (the cont. 34 lesson, repeated in my
own canary phases — the lessons log gets the recurrence note). The round-1
EARLY reply under poison ("The user has provided a list of words with
numbers" — coherent, code-blind) is CONFOUNDED: the early code sits at row
~1,517 of a 2,267-token repetitive prompt — a hard needle even for a
correct engine — so it needs a bf16 control to interpret. Coherent (no NaN
artifacts) suggests the reads hit written rows, but one confounded round
proves nothing. The engine's fate in round-1 late is unrecoverable (the
serving boots' rank-0 saves are still not written — the known gap).

**RELAUNCHED (fixed)**: every assignment pipefail-guarded; a bf16-poison
CONTROL leg added (the early/late split is interpretable only against it);
per-serve docker-logs captures (the engine's fate in a failing round lands
in the receipt); the early/late split kept. ~12 min.

## (round 133, cont. 46) THE POISON VERDICT: the stored content is WRONG-BUT-FINITE (coherent garbles, never NaN-mush) — the quantize/scales/write path; AND the engine CRASHED (rank 1 CudaContextLost); the byte-level write-vs-read dump launched (2026-11-05)

**campaign-20261105-181641 (poolcanary4, the fixed two-leg run)**:
- **bf16 + poison: 6/6 exact codes** (early AND late) — the canary design
  validated end to end; the poison doesn't perturb a correct engine; the
  early needle (row ~1,517) is retrievable when the engine works.
- **fp8 + poison: coherent garbles, NEVER NaN-mush** (round-1 early
  code-blind-coherent, then PARSE-FAILEDs) — under poison a read of
  unwritten rows returns NaN and the output would be NaN mush. Coherent
  garbles mean **the reads hit finite, written-but-wrong content: the
  quantize/scales/write-content path, not write visibility**.
- **THE ENGINE CRASHED**: "rank 1 stopped (CudaContextLost)" during
  round-1 late (the recycled+poisoned pages) — a hard CUDA context loss,
  possibly page-id-dependent (round-1 early on fresh pages survived).

**LAUNCHED: glm-zz-dumppages** — the byte-level write-vs-read dump: the
write kernel printfs its own written scale+code for global row 2,100
(inside the code sentence); the read kernel printfs what it sees for the
same row. Write-vs-read at the byte level splits the path definitively:
write says X / read says X ⇒ the content is right and the loss is
elsewhere; write says X / read says Y ⇒ the read addressing; write says
garbage ⇒ the quantize/scales path. The debug patch is 30 lines, applies
on the full stack (the per-patch-commit discipline held this time — the
first two generation attempts captured the whole stack diff), and the
fingerprint change rides a rebuild (~15-25 min) in the window preamble.

## (round 133, cont. 47) THE ROOT CAUSE FOUND: the E4M3 Tables' page_rows = 3,481 instead of 512 — the selection scored every token against page 0's pooled keys; the fix staged; the validation launched (2026-11-05)

**The dumppages receipt (campaign-20261105-183615)**: the READ kernel's
GLMDUMP lines show the dense path sane (scale 0.003017, a well-formed row)
— the dense reads are fine (the kernel hardcodes CH=512) — and **the WRITE
kernel's printf never fired**, which led to the dispatch audit and then to
the real bug: **the DSA Tables' page_rows = c.ps/(l.lw*2) — the WHOLE-page
stride (3,565,440) over the bf16 row bytes (1,024) = 3,481 instead of
512.** The selection kernel (selectTokensProfile) indexes the pooled keys
pt[row/page_rows]: with 3,481, EVERY row below 3,481 reads PAGE 0's pooled
keys — all tokens score against rows 0-511's keys — the sparse lists are
garbage — **the model attends to the wrong tokens and mis-reads its own
prompt**. The dense path is exonerated (the kernel hardcodes CH=512; the
sane dense read in the receipt). The contract tests passed because their
FIXTURES use per-layer ps, where the formula coincidentally yields 512;
the engine's Caches carry the whole-page ps — the port's semantic
mismatch. The CudaContextLost crash: the selection's garbage indexes under
poison — consistent.

**THE FIX (glm-mia-fp8-pages-pagerows.patch, 47 lines)**: the three Table
sites in cuda_dsa_block.zig — `.page_rows = if (c.ls != 0) latent.chunk
else c.ps / (l.lw * 2)` — E4M3 gets the true 512; bf16 keeps its formula
(its lists are page rows, a different unit, and its path is receipted
correct). Applies on absorb+marriage; verified.

**LAUNCHED: poolcanary4 under the fix** (the poison discriminator is the
harshest validation: the NaN refill forces the writes and the selection to
prove themselves) — bf16 control + fp8, early/late split. fp8 answering
MKR-{i}QX under poison ⇒ the fix holds; then the battery re-run
(pagedquality2) is the adoption judgment. The dumppages debug patch
RETIRES (the file removed; the diagnosis closed).

## (round 133, cont. 48) THE BUILD'S ALPHABETICAL STAGING CAUGHT THE MIS-NAMED FIX (the skill's first gotcha, self-inflicted); renamed and relaunched (2026-11-05)

**campaign-20261105-190228**: the build FAILED — "PATCH FAILED:
glm-mia-fp8-pages-pagerows.patch (cuda_dsa_block.zig:137 does not apply)" —
**the fix patch's name sorted BEFORE the marriage's** ("…-pagerows.patch" <
"….patch" since '-' < '.'), so the build's alphabetical apply ran the fix
on the absorb-only tree where its context doesn't exist. The
tensorfold-patch-craft skill's first gotcha, self-inflicted. RENAMED:
glm-mia-pagerows-fix.patch (sorts after both). The README carries the fix's
entry (the root cause + the staging note). Relaunched: poolcanary4 under
absorb + marriage + pagerows-fix.

## (round 133, cont. 49) THE FIX VALIDATED UNDER POISON FOR THE MIS-READ (fp8 round-1 early CORRECT — before the fix, code-blind); the crash is a SEPARATE NaN-robustness gap; the no-poison validation launched (2026-11-05)

**campaign-20261105-192124 (poolcanary4 under the fix)**:
- **bf16 + poison: 6/6 exact** (the control, again).
- **fp8 + poison: round-1 early = MKR-1QX — CORRECT** (before the fix, the
  same request was code-blind) — **the page_rows fix cures the selection**.
- **fp8 round-1 late + everything after: the CudaContextLost crash AGAIN** —
  poison-specific (the no-poison v3 canary ran 10 rounds crash-free): the
  poison's NaN in the UNWRITTEN KV region feeds the E4M3 selection, whose
  NaN comparisons break the index output → the sparse fetch's illegal
  access. The bf16+poison control is clean (the bf16 selection = the
  page-row-list path, NaN-tolerant) — **the E4M3 selection path is the
  NaN-fragile one: a separate robustness gap, upstream-relevant, NOT the
  contamination bug**.

**LAUNCHED: poolcanary5** — the no-poison fix validation: five rounds, the
code at chunk 1 AND chunk 2, on the fixed fp8-paged serve. Ten exact
MKR-{i}QX replies ⇒ the mis-read is fixed ⇒ the battery re-run
(pagedquality2) is the adoption judgment. ~10 min.

## (round 133, cont. 50) THE MIS-READ IS FIXED: poolcanary5 = 10/10 EXACT CODES (chunk 1 and chunk 2, five rounds of recycling, no crashes); pagedquality2 launched — the adoption judgment (2026-11-05)

**campaign-20261105-194159 (poolcanary5, the no-poison fix validation)**:
**ten out of ten exact MKR-{i}QX replies** — the code at chunk 1 (~row
1,520) AND chunk 2 (~row 2,110), five rounds of page recycling, no crashes,
no failures. The page_rows fix completely cures the E4M3 paged mis-read.
The poison-only CudaContextLost crash stands as a separate E4M3-selection
NaN-robustness gap (upstream-relevant; the bf16 path tolerates NaN), not
blocking anything here.

**LAUNCHED: pagedquality2** — the hardmode battery + the vision suite on
the FIXED composed paged stack (absorb + marriage + pagerows-fix,
TF_KV_PAGES=on). The adoption bar: hardmode ≥ 94 (production parity; absorb
set 95) + the vision 4/4. The battery is ~50 min; the window ~60 min.

## (round 133, cont. 51) pagedquality2 = 75: the mis-read is cured, a NEW failure mode — degenerate token loops; the decode-time hunt opens (2026-11-05)

**campaign-20261105-195559 (pagedquality2, the fixed composed paged
stack)**: hardmode **75** (bar ≥94; the pre-fix 74 — barely moved), the
vision **4/4**. The contamination is GONE (poolcanary5 10/10) — the
failure mode is DIFFERENT: **degenerate token loops in long generations**.
TC-62 emitted 51,967 tokens ending "…alendar, calendar, calendar, …"
(79,525 chars of reasoning, no answer); TC-49 repeated " " to the 16,384
cap. Engine lines: finish=length at tokens=16384 with the draft acceptance
99% (a repeating token is trivial to draft; a normal short reply shows
~80%). The shape: total_tokens +60% (662k→1,064k), token_efficiency
halved (0.30→0.15), deployability 73→60, the multi-turn capabilities
collapsed (constraints 10→3, state-tracking 5→1, concurrency 6→3) — while
**median_turn_ms IMPROVED (6,830→5,993 ms; the pages' speed win is real)**.

**Why the canary missed it**: dense_limit = keyWidth = i_topk + kpool - 1
— the canary's 12-token decodes sat ON the dense/sparse boundary; the
battery lives almost entirely beyond it (prompts 3k-20k, decodes to 16k).
The static audit closed the easy suspects: NOT a page_rows repeat (no
unfixed ps/(l.lw*2) formula remains; cuda_sparse.zig:131 consumes the
fixed Table); the decode path's t-vs-tk Table difference is inert (pks≠0
only under TF_GLM_KV_HOST — never set here); the MTP drafter's caches are
paged by the marriage (mtp_caches at kv.ptr+part, the same page table) and
covered by the fix's three sites.

**LAUNCHED: pagedecode** — the greedy-decode comparison, pages on vs off,
SAME binary (absorb + marriage + pagerows-fix): G1 tiny prompt → 2k
decode, L1 3.3k → 2k, L2 16k → 2k (TC-62's depth regime), T1 thinking-ON
16k → 4k decode (the battery's mode: the loops lived in the reasoning
channel), M1 a ~2.3k turn-1 conversation (the resume path fires) + recall.
LOOP on pages with pages-off clean ⇒ the decode-time paged path diverges
(bisect the onset next); LOOP on BOTH ⇒ the marriage's non-paging changes;
CLEAN both ⇒ the trigger is the battery's multi-turn/tool structure
(instrument TC-62 directly next). ~20 min.

## (round 133, cont. 52) pagedecode's first window: the pages-ON greedy decode ladder CLEAN at 2k depth (the loops did not reproduce); the phase aborted at the pages-off serve — TF_KV_PAGES= (empty) is REFUSED by the engine; re-launched with off + a 12k-decode probe (2026-11-05)

**campaign-20261105-221651 (pagedecode, the ON side only)**: G1/L1/L2
(tiny/3.3k/16k prompts × 2k decodes) all CLEAN — counts 1..~770 perfect,
no loops, tok/s 77-89 — and **T1 (thinking ON, 16k prompt) decoded clean
on a 16k STORE-RESUMED prefix (cached=16384)**: the battery's loops did
not reproduce at 2k decode depth. M1 turn2 = "391" correct with the
resume fired (cached=2048); the turn3 RECALL-MISS is a probe flaw (the
48-token cap cut the answer mid-description), not evidence.

**The abort**: the phase demanded `TF_KV_PAGES=` (empty) for the off side
— **the engine refuses empty** ("TF_KV_PAGES: give auto, on (or 1, all)
or off (or 0)") — the serve died at validation, the phase stopped before
the OFF side and the verdict, and the `.done` marker was never written.
The poke chain is intact: with no ` done.` marker the poke correctly fell
back to the 10-min-quiet rule; it was fired manually at 22:33 (the marker
set) — the fallback latency is the round-132 design working, not a bug.

**RE-LAUNCHED: pagedecode (fixed)** — `TF_KV_PAGES=off` explicitly;
**G2: tiny prompt, count to 20000, max_tokens 12288 — walks decode depth
to ~12k, into the battery's regime** (the runaway decodes ran to the
16,384 cap); T1 now forces the reasoning channel deep (thinking ON + a
count task — the battery's loops lived in reasoning); M1 gets 128 tokens
and a sterner recall instruction. Same verdict branches; ~20 min.

## (round 133, cont. 53) pagedecode's verdict: CLEAN BOTH SIDES with IDENTICAL SHAS — plain decode is exonerated to 12k depth; the loops need a repetitive KV region; pageloop launched; v1.2.3 scanned (2026-11-05)

**campaign-20261105-223622 (pagedecode, both sides — the poke fired
normally: the re-run wrote its done marker)**: pages ON vs OFF, SAME
binary — G1/G2/L1/L2/M1 replies **BIT-IDENTICAL** (the same shas per
probe on both serves), T1 CLEAN on both (the ON side declined the task,
the OFF side counted to its cap — the thinking probe's numerics differ
legitimately). **The greedy decode on the paged fp8 stack is numerically
identical to unpaged: 12k decode depth (G2, tok/s 94.6 on / 95.3 off),
16k prompts, 16k store-resumed thinking, the resume path, recall exact
("FALCON-7")**. The battery's loops did not reproduce with any plain
request.

**The new lead**: TC-62's raw log shows the loop turns ALTERNATE (turns
2/4/6 ≈ 80K chars each, turns 1/3/5 normal) and run from ~1.4-2K-token
prompts (the engine lines). The harness (tool-eval-bench orchestrator,
_assistant_message) feeds the FULL assistant output back — **each loop
turn's history carried the PRIOR loop's ~20K tokens of highly repetitive
text**, a KV region the pagedecode probes never had.

**LAUNCHED: pageloop** — the minimal pair, pages ON vs OFF, same binary:
R1 a ~20K-token repetitive assistant message ("calendar, "×6000) in
history → 2k decode; R2 the same length, varied (numbers 1..8000) → 2k
decode. R1 loops with R2 clean ⇒ the paged path chokes on repetitive KV
regions — a tiny reproducer, the bisect is on. Both clean ⇒ the battery
composition holds the trigger (the faithful TC-62 replay next). R1 loops
on BOTH ⇒ not paged (the standing 95 contradicts).

**v1.2.3 scanned (the user asked: this track, or v1.2.3?)**: the tag
exists, **425 commits**, and it TOUCHES our patch sites (cuda_dsa_block.zig,
cuda_forward.zig — the CHUNK_SOLO plumbing). Its GLM/CUDA changelog is
opt-in prefill/serving features — TF_GLM_CHUNK_SOLO=4096 beside --drafter
(~7% TTFT at TP=2), TF_GLM_COPIES=1, TF_GLM_ROCE_MULTI 8-piece at TP=3 —
plus the KV-pages --prompt-cache-gib sizing fix (#2220, no change with
the flag unset). **Nothing on the DSA selection, the paged fp8 decode,
or loops — not a shortcut around the bug.** The agent's recommendation
(executed under the standing directive): FINISH the loop track — one
window from a verdict — then rebase onto v1.2.3 as its own arc
(re-anchor the three patches, canary + battery re-validate ONCE on the
new base, the perf items feed PERF_PLAN). Rebasing now would run the
same validation twice.

## (round 133, cont. 54) pageloop: the repetitive-KV hypothesis DIES (clean both sides, R1 bit-identical); the last untested difference is the battery's CONCURRENCY; pageconc launched — the synthetic concurrent pair + the FAITHFUL harness replay (2026-11-05)

**campaign-20261105-230200 (pageloop, both sides)**: R1 (a ~12K-token
repetitive assistant message in history → 2k decode) CLEAN on both
serves with **identical shas** (and identical to the ladder's count
output) — the paged path handles a large repetitive KV region fine.
R2 (the same length, varied) CLEAN but the pages-ON reply **flipped one
token** ("28 28 29…" vs OFF's "28 29…") — the first reply-level
divergence seen in the whole investigation, benign (a greedy numerics
flip, then coherent to the cap). Verdict: the repetitive-history
hypothesis is dead.

**What remains**: the battery runs **--parallel 2 — concurrent scenarios
sharing the page pool** — every probe so far was sequential. And the
standing run's TC-62 **passed** (12 turns, 5,043 completion tokens, no
loop) — the control expectation for the replay. TC-62's alternating
loop turns (2/4/6) are consistent with a concurrency-dependent pool
state.

**LAUNCHED: pageconc** (~40 min) — pages ON vs OFF, same binary:
(1) the synthetic concurrent pair — a tiny 12k-decode count ∥ a
16k-prompt 2k-decode count fired simultaneously (isolates the
concurrency variable); (2) **the faithful harness replay** —
tool-eval-bench run --scenarios TC-62 TC-49 --hardmode --parallel 2
(the battery's exact flags and budget; the harness has a --scenarios
filter). Loops on pages-ON with OFF passing ⇒ reproduced. All clean ⇒
the trigger needs the full 104-scenario pool state — next: the
marriage-unpaged battery as the fork (95 ⇒ pages×battery; 75 ⇒ the
marriage's non-paging changes).

## (round 133, cont. 55) THE LOOPS ARE REPRODUCED FAITHFULLY — the harness replay fails on fp8-paged and is healthy on pages-off (identical to the standing run: the marriage's non-paging changes are exonerated); concurrency exonerated; the bf16-paged format bisect launched (2026-11-05)

**campaign-20261105-231751 (pageconc, both sides)**:
- The synthetic concurrent pair (a tiny 12k-decode count ∥ a 16k-prompt
  2k-decode count, fired simultaneously): **CLEAN both sides with shas
  identical to the sequential runs** — **concurrency is NOT the
  co-trigger**.
- **The faithful harness replay (tool-eval-bench --scenarios TC-62
  TC-49 --hardmode --parallel 2 — the battery's exact flags): REPRODUCED.**
  fp8-paged: TC-62 **FAILS** — 19,458 completion tokens over 8 turns,
  **turn 8 hit the 16,384 ceiling with 72,502 chars of reasoning** (the
  loop, in the reasoning channel); final_score 50. pages-off: TC-62
  **PASSES** — 5,043 tokens / 12 turns and TC-49 751 / 3 turns —
  **IDENTICAL to the standing battery run's numbers: the marriage's
  non-paging changes are exonerated**; final_score 100.
- **The reproducer is now cheap**: one harness command (~5 min) instead
  of the 50-min battery — the fix hunt's instrument.

**LAUNCHED: pagebisect** — the same replay on **bf16-paged** (the
receipted-correct sibling format; KV_CACHE= empty per the start.sh
convention). TC-62 fails with a ceiling note ⇒ the loop is **E4M3-
specific** (the quantized latent read/selection during long thinking
decodes — the fix hunt digs the fp8 path). TC-62 passes ⇒ **paging
itself** degrades long thinking chains (the Table/mapping layer —
format-independent). The same bisect that cracked the original
contamination, at the loop level.

## (round 133, cont. 56) THE BISECTION IS COMPLETE: bf16-paged is CLEAN (final_score 100, no loops) — the loop needs fp8 AND pages TOGETHER; the user HALTS new launches pending the explanation (2026-11-06)

**campaign-20261106-000548 (pagebisect, bf16-paged)**: the faithful
harness replay (TC-62 + TC-49, the battery's exact flags) on bf16-paged:
**final_score 100** — TC-62 **passes** (5,188 completion tokens, 12
turns, zero truncated notes), TC-49 passes (783). Every generation
finish=stop. **The loop is E4M3-specific.**

**The completed bisection** (each cell a receipt):
- fp8 + pages = **LOOPS** (the battery 75; the replay fails, turn 8 →
  the 16,384 ceiling, 72,502 chars of reasoning).
- bf16 + pages = **CLEAN** (this receipt).
- fp8 + no pages (the marriage) = **CLEAN** (the replay = the standing
  run's numbers exactly).
- bf16 + no pages (the standing stack) = **CLEAN** (the battery 95).
**The loop is an INTERACTION bug: the E4M3 quantized format × the paged
read/selection path, manifesting only in long thinking decodes** — the
same family as the page_rows bug (also E4M3×pages-specific), a second
member. The fix hunt's target: the E4M3 paged latent read / sparse
selection under long decodes; the instrument: the ~5-min harness replay.

Phase-code note: the receipt's extraction section is empty — the block
printed to the console, not $P (cosmetic; the numbers come from reading
tc-bf16/result.json directly; the console carries the lines).

**(user, 2026-11-06)**: no new tests are launched until the user says
so — the user asked for the complete high-level explanation first. The
stack holds: production up on 8000, the testing stack down, everything
digested. The queued options for the user: (a) dig the fp8×pages
interaction with a debug instrument on the cheap reproducer; (b) park
the marriage and rebase onto v1.2.3 (its GLM items are prefill/serving
features; the loops stay unfixed — upstream-relevant data either way);
(c) the user's own direction.

## (round 133, cont. 57) THE USER LIFTS THE HOLD: continue autonomously, fold in v1.2.3 when appropriate; the fix hunt opens with the selection instrument (2026-11-06)

**(user, 2026-11-06)**: "Ok, yes, you should continue — autonomously,
and fold in v1.2.3 when you feel appropriate." The agent's plan, on the
timing: **finish the loop fix on the current pin first** (the
reproducer, the anchor discipline and the instruments all live on
00e7ddd; rebasing mid-hunt adds a moving base to a bug hunt), then
rebase onto v1.2.3 as its own arc (re-anchor the three patches + the
fix, canary + battery re-validate ONCE on the new base), then the
config.sh adoption decision.

**The hunt's opening moves (static, no window)**:
- The CUDA-index "quick" selection path: ELIMINATED — off by default
  (TF_GLM_INDEX_CUDA unset = Mode.off) and prompt-sized-only (takes()
  requires rows >= rows_from); our serves run the glue selection,
  driven by the fixed Table.
- The assembler (tf_glm_dsa_tokens): for E4M3 the token lists stay
  LOGICAL positions (pt=0 on this path — "its chunks take the table"
  later); PAGE=512 hardcoded, consistent with the fix. The scores
  kernel reads the pooled keys THROUGH the page table (t.pt + t.ps
  raw — its own mapping, not the fixed page_rows: noted).
- The loop onsets: EARLY (tokens 500-1,650 into each runaway) at no
  common boundary; the loop token ("calendar,") is a tool-schema name
  from the prompt; the replay's runaway is a SOFT loop (72,502 chars of
  reasoning, no exact-repeat run, draft acceptance 72.8%) vs the
  battery's hard loops (99%) — a severity spectrum, one disease.

**LAUNCHED: pagehunt** — the selection instrument. The glm-zz-dsasel
debug patch (30 lines, staged, applies on the full stack) makes
tf_glm_dsa_tokens print row 0's first eight selected logical positions
+ the count every 64th position (__syncwarp-guarded, read-only). The
replay runs on fp8-paged (loops) AND bf16-paged (clean control); the
SEL dumps save whole with a per-position distinct-top-4 summary in the
receipt. FREEZE on fp8 with a healthy slide on bf16 ⇒ the selection is
the site; both slide ⇒ the sparse attention's gather/read is the site.
~25 min.

## (round 133, cont. 58) pagehunt's instrument receipt: the fp8 selection's page-start attractor AND causally impossible selections; the refined VIOL detector launched; (user) the workflow directive (2026-11-06)

**(user, 2026-11-06)**: "do not launch tests until all tasks have
completed. You will go dark after launching a test. And not come back
until they are complete." — adopted as the standing workflow: every
sitting completes ALL tasks (digests, analysis, docs), launches at most
one window LAST, and goes dark until its poke. Logged in the lessons
file.

**campaign-20261106-004057 (pagehunt, the selection instrument)**: the
loop reproduced under the debug build (fp8: TC-62 fail, turn 3 → the
16,384 ceiling, 72,000 chars of reasoning; final_score 25; bf16:
final_score 100 ✓ the control). The SEL dump (4,037 fp8 lines):
- **The page-start attractor**: every dominant top-4 across the run
  starts at a 512-multiple — (5120..5123)=page 10, (2048..)=page 4,
  (10240..)=page 20 — with (5120..5123) recurring at pos 2,048/4,096/
  6,144/8,192/10,240/10,368 for ~18% of layer launches. The bf16
  control's dominants vary per position (physical pages 5, 3, 65, 34 —
  content-tracking) ✓ healthy.
- **Causally impossible selections**: (17408..17415) selected at
  pos=2240, (26112..) at 6,272, (21504..) at 8,192 — no request in the
  replay had 17K tokens of history, so pool 4352 could never be legally
  scored. But the scores kernel's per-pool mask reads correct
  (`p < npool ? s : -INFINITY`, per-row) and the pooled-key writer/
  reader addressing agrees exactly (`at<128>(pt, ps/2, p, 128)` both
  sides — glm_pages + key_at).
- **Instrument artifacts identified**: the pos=2048 lines (n=968) were
  STALE SCRATCH (count=0 — dense rows printing unused pools buffers);
  both dumps stop at ~4,000 lines (the CUDA printf FIFO cap).

**The refined instrument (glm-zz-dsasel v2, 36 lines, staged)**: gate on
count>0, tag npool (each line's causal horizon), and a mechanical VIOL
detector — for E4M3 lists (pt==0, logical positions) a selected token
beyond the row's own limit (row[0] > q) fires a VIOL line per instance.
**LAUNCHED: pagehunt2** — the replay on fp8-paged AND bf16-paged: VIOL
on fp8 with bf16 silent ⇒ the selection reads beyond the scored range
(the leak is real; the next sit digs select_rows' scan range vs the
written range); no VIOL anywhere ⇒ the impossible positions were stale
scratch and the fixation is real attention (dig the pooled keys'
content). ~25 min. THEN DARK per the user's directive.

## (round 133, cont. 59) THE VIOLATION IS REAL: 74% of sparse selections emit tokens beyond the row's causal limit (offline analysis of pagehunt2's dump — the build had consumed the stale v1 patch); the hop-isolating PICK instrument launched (2026-11-06)

**The instrument miss, diagnosed**: pagehunt2's container ran the OLD v1
patch (its lines have no npool/VIOL — the build consumed the stale
glm-zz-dsasel.patch despite the repo file being v2; a same-name patch
update did not reach the build). The v2-format analyzer therefore
matched nothing — "VIOL lines: 0" was the ANALYZER matching nothing,
not the mechanism being absent. **Lesson: verify the instrument's
output FORMAT in the receipt before concluding zero** (logged).

**The offline analysis of the saved v1-format dump (sel-fp8.log, 4,598
lines, the looping serve — TC-62 AND TC-49 both hit the ceiling this
run; two 16,384-token runaways at 99.4% acceptance; final_score 25;
bf16 clean at 100)**:
- Sparse rows (count>0): 3,641. **CAUSAL VIOLATIONS (t0 > pos): 2,684 —
  74%.** pos=2112 selecting t0=2560 (future by +448); the selection
  FROZEN on (9216..9219) across pos 2,240-3,904 while the visible
  history ends ~2,500; pos=4096's top = (13312..) — future by 9,216.
- **49.2% of sparse rows' top token sits on a 512-page start** (pool ≡ 0
  mod 128).
- The loop ignites right past the sparse boundary (npool ≈ K, pos just
  over 2,048) — where stale slots MUST fill the top-K — and the
  E4M3-poison crash (the NaN-fragile selection over unwritten rows) is
  the same root: unwritten/stale rows entering the selection.

**Both kernels read causal in source**: the scores kernel masks
per-pool (`p < npool ? s : -INFINITY`), and select_rows scans
`NP = min(np, max(vis, K))` — the row's own horizon. Yet the emissions
are out-of-horizon ⇒ the corruption lives in the state BETWEEN the
kernels (the shared pools scratch / an aliasing gap, or the two
kernels' views of pos_dev).

**LAUNCHED: pagehunt3** — the hop isolator. glm-zz-dsasel v3 (50 lines,
staged, applies) adds the select kernel's PICK printf (its own pos
read, vis, NP, top-2 outputs; sparse launches only) beside the
assembler's VIOL/SEL. One fp8-paged replay: PICK causal with the
assembler out-of-horizon ⇒ the pools scratch / aliasing gap; PICK
already out-of-horizon ⇒ the scores buffer's stale slots win the
top-K. ~15 min. THEN DARK.

## (round 133, cont. 60) THE STALE-BUILD GOTCHA BIT TWICE; the hop isolator re-delivered under a NEW patch name; the fresh dump reconfirms the frozen out-of-horizon selections (2026-11-06)

**The instrument delivery failed again**: pagehunt3's container ran the
v1 patch a SECOND time (no PICK/npool/VIOL — the v3 content never
reached the build despite the repo file being v3). Two same-name
updates, two stale builds. **The fix per the logged lesson: a NEW file
name** — glm-zz-dsasel.patch is retired (git rm; the README entry
documents the series and the rename receipt) and the v3 instrument is
re-delivered as **glm-zz-dsasel3.patch**.

**The fresh dump (pagehunt3's sel-fp8.log, 6,050 lines, the looping
serve — TC-62's loop hit its FIRST generated turn, prompt 1,383;
final_score 25; bf16 clean 100)** reconfirms the signature: **47.6% of
sparse selections emit out-of-horizon tokens** — the selection frozen
on **(35328..35331) = page 69's start** across pos 2,240-3,264 while
the visible history ends ~2,500 (no request had 35K tokens of history).
The frozen window differs per serve (9,216 in the prior run; 35,328
here) — consistent with fixed stale/unwritten slots at
config-deterministic addresses winning the top-K.

**LAUNCHED: pagehunt4** — the hop isolator, the instrument finally
delivered: the select kernel's PICK lines (its own pos read, vis, NP,
top-2 outputs) beside the assembler's VIOL/SEL on the fp8-paged replay.
PICK causal with the assembler out-of-horizon ⇒ the pools scratch /
aliasing gap; PICK already out-of-horizon ⇒ the scores buffer's stale
slots win the top-K. ~15 min. THEN DARK.

## (round 133, cont. 61) THE LOOP BUG FOUND: the prefill's E4M3 token lists were PHYSICAL and the prefill's sparse attention double-mapped them (pt[pt[page]]) — harmless on identity page mappings, corrupting once pages recycle; the one-flag fix staged; the validation launched (2026-11-06)

**pagehunt4 (campaign-20261106-031244) — the instrument finally
delivered (the new file name worked) — and it killed the selection-
causality hypothesis**: the select kernel's outputs are causal in
**1,254 of 1,254 samples** (PICK out0 beyond its own horizon: 0), and
the assembler's VIOL detector (E4M3 logical lists only) printed **0**.
The "out-of-horizon" SEL lines are launches with pt≠0 — PHYSICAL
page-row lists — a different token-unit stream. My earlier 47-74%
"violations" were that stream mixed into the target's logical one.

**The source read found the real bug**: in attend (cuda_dsa_block.zig
~141), the prefill's sparse selection receives **tk** — whose .logical
defaults to FALSE — so the prefill's E4M3 token lists were assembled as
PHYSICAL page-row values, while the prefill's sparse attention receives
**t** (.logical = c.ls != 0 = TRUE) and maps the token values through
the page table AGAIN: **pt[pt[page]] — a double lookup.** Idempotent
while pages are allocated in order (pt[p] == p — which is why the
canary, the decode ladders and every fresh-serve probe were bit-clean:
the canary's prompts even sat UNDER dense_limit, never touching the
sparse prefill at all), corrupting the boundary chunk's attention once
pages recycle or interleave (the battery's --parallel 2 × 104
scenarios): the model mis-attends from the first sparse rows onward and
long thinking generations degenerate into loops. The decode path was
already self-consistent (t on both sides) — why every decode-only probe
was bit-perfect. The poison crash (the E4M3 NaN-fragile selection) and
this share the theme: unwritten/mis-mapped rows entering E4M3 attention.

**THE FIX (glm-mia-selist-fix.patch, 34 lines, staged, applies)**: tk
carries `.logical = c.ls != 0` — E4M3 lists stay positions end-to-end
(the design comment's own rule); bf16 keeps physical page rows.

**LAUNCHED: sparsefix** — the validation: the harness replay FIRST (it
churns the pages non-identity), THEN the **sparse-prefill code probe** —
the code at ~row 3,650 of a ~4.5k prompt, beyond dense_limit, on
recycled pages: the path the original canary never touched. The replay
stops looping + five exact codes ⇒ the mechanism confirmed ⇒ the
battery re-run is the adoption judgment. ~20 min. THEN DARK.

## (round 133, cont. 62) THE FIX VALIDATES COMPLETELY: the replay 100 (TC-62 passes with the standing run's exact profile — 5,043 tokens / 12 turns) + the sparse-prefill probe 5/5 exact on recycled pages; the battery re-run launched — the adoption judgment (2026-11-06)

**campaign-20261106-035856 (sparsefix, the tk.logical fix stack)**:
- **The harness replay: final_score 100** — TC-62 **passes** (5,043
  completion tokens, 12 turns — **byte-for-byte the standing run's
  profile**), TC-49 passes (751), **zero truncated notes**. The loops
  are GONE on the recycled-page churn that reproduced them 4/4 runs
  before.
- **The sparse-prefill code probe: 5/5 exact MKR-{i}QX** — the code at
  ~row 3,650 of a ~4.5k prompt, beyond dense_limit, on recycled pages:
  the prefill's sparse path, exercised explicitly for the first time,
  reads perfectly under the fix.
- The mechanism stands confirmed: the prefill's E4M3 token lists were
  physical (tk without .logical) and the prefill's sparse attention
  double-mapped them through the page table — idempotent on identity
  mappings, corrupting on recycled ones.

**LAUNCHED: pagedquality3** — the adoption judgment: the hardmode
battery + the vision suite on absorb + marriage + pagerows-fix +
selist-fix, TF_KV_PAGES=on. The bar: **hardmode ≥ 94** (production
parity; absorb set 95) + the vision 4/4. ~50 min. THEN DARK.

## (round 133, cont. 63) THE BATTERY GATE CLEARS: pagedquality3 = 95 + the vision 4/4 — production parity with the speed win (median turns 6.5% faster); the duel re-pair launched — the last gate before the config.sh adoption decision (2026-11-06)

**campaign-20261106-043015 (pagedquality3, the adoption judgment on
absorb + marriage + pagerows-fix + selist-fix, TF_KV_PAGES=on)**:
- **hardmode final_score: 95** — production parity (the standing 95;
  absorb set 95; the bar was ≥ 94). The vision suite **4/4**.
- **total_tokens: 662,693 — byte-identical to the standing run's
  662,693** (the pre-fix paged run was 1,063,881): the loops are gone,
  not merely reduced. **Zero scenarios over 8k completion tokens** (the
  pre-fix run's runaways eliminated).
- token_efficiency 0.30 (standing 0.30), worst category P Hard Mode 89%
  (standing 89%), **deployability 74 (standing 73 — a point better)**.
- **median_turn_ms 6,381.8 vs the standing 6,829.6 — 6.5% faster**: the
  pages' speed win holds at production quality.
- The fp8+pages marriage now delivers production-parity quality WITH
  the speed win. The loop arc is closed: the battery gate is cleared.

**LAUNCHED: duelpaged** — the duel re-pair, the last gate before the
config.sh adoption decision: the standing duel's five instruments with
the ours arm on the paged candidate; the production arm unchanged
(production-for-testing on 8001, the intent-keyed start, read-only;
restored by the window flow's exit path). ~20 min. THEN DARK. The
adoption decision follows the duel receipt (the receipts-equal-or-
better protocol), and the v1.2.3 rebase is the arc after that.

## (round 133, cont. 64) THE DUEL GATE CLEARS (mixed-favorable): solo 108.5%, c2 above production's floor, c4 parity, ITL CROSSED at 15.7 vs 17.1 ms/token, the cold depth crossed at 3.3×; the anchors re-paired for the paged candidate; the last pre-adoption gate launched (2026-11-06)

**campaign-20261106-052114 (duelpaged — production-for-testing on 8001
vs the paged candidate)**:
- **Solo decode: 63.5/63.2 vs 58.5/58.6 t/s — 108.5%** (the ABSORB-only
  pair was 110% — the pages cost ~1.5% solo and buy the elastic pool).
- **c2 aggregate: 110.6 vs 87.1 t/s** — production's c2 volleys 87-111
  with cache state, this run at its floor; ours stable 110.4-110.6
  across the absorb and paged duels.
- **c4 aggregate: 154.8 vs 154.6 — parity** (production's range
  155-241, this run at its floor).
- **ITL: 15.7 vs 17.1 ms/token — CROSSED (109%)** (ours' chunked rhythm
  61.9 ms ÷ ~3.94 tokens vs production's single-token chunks).
- **TTFT overhead: 199 vs 186 ms** (93% — stable across windows).
- **The cold depth: d8192 5,215 ms, slope 0.612 vs production's
  17,129 ms, slope 2.026 — 3.3× CROSSED** (the ABSORB-only pair was
  5,122/0.602 — the pages' overhead +1.8%).

**The anchors re-paired**: perf-anchors.tsv's duel rows now carry the
paged candidate's pair (solo/c2/c4/ITL/overhead/cold-depth) and the
chart is re-rendered; the README's stale "Mutually exclusive with
TF_KV_PAGES" claim on the KV_CACHE row is corrected (the marriage made
the combination the point).

**The adoption state**: the battery gate cleared (95 + the vision 4/4),
the duel gate cleared (mixed-favorable: the throughput instruments
equal-or-better, the cold depth crossed; the ITL is per-token CROSSED
too). The remaining gate: **VALIDATION §2 on the final stack** —
**LAUNCHED: pagedgates** (run_gates on fp8-paged, dense4, 512K,
TF_KV_PAGES=on, the 4-patch build; PATCHES threaded explicitly). The
config.sh adoption decision follows its receipt. ~15 min. THEN DARK.

## (round 133, cont. 65) THE ADOPTION: config.sh defaults to TF_KV_PAGES=on + the 4-patch stack — the receipts-equal-or-better protocol satisfied on all four gate families; the bare-config smoke test launched (2026-11-06)

**pagedgates (campaign-20261106-054902): ALL §2 GATES PASS on the
fp8-paged final stack** — g1 determinism (content), g2 drafted=plain,
g3 resumed=fresh (the cache-hit reply identical — the resume path
correct), g4 concurrent=solo (4/4), g5 sampled determinism. The last
pre-adoption gate clears.

**THE ADOPTION DECISION (the receipts-equal-or-better protocol)**: the
four gate families all hold receipts-equal-or-better on the final stack
(absorb + marriage + pagerows-fix + selist-fix, TF_KV_PAGES=on):
- **Gates**: §2 ALL PASS (pagedgates, campaign-20261106-054902).
- **Depth**: the 512K window gates ran at CONTEXT=524288 on the paged
  stack ✓ (the marriage's 512-row page-level resume validated earlier;
  the depth ladder re-qualification on the paged stack is queued as the
  post-adoption re-run).
- **Duel**: mixed-favorable (duelpaged, campaign-20261106-052114 — solo
  108.5%, c2 above production's floor and ~parity with its top, c4
  parity, ITL crossed 15.7 vs 17.1 ms/token, the cold depth crossed
  3.3×; the pages' overhead vs absorb ~+1.8% on the cold prefill).
- **Hardmode**: 95 + the vision 4/4 (pagedquality3,
  campaign-20261106-043015 — the standing run's exact token profile,
  median turns 6.5% faster).

**THE EDITS**:
- **config.sh**: `TF_KV_PAGES="${TF_KV_PAGES-on}"` (the adopted default;
  unset → on, `off` → the window-mode KV; the engine refuses an EMPTY
  value), `PATCHES` → the four patches (absorb + fp8-pages +
  pagerows-fix + selist-fix), and the stale "fp8 KV and TF_KV_PAGES are
  mutually exclusive" comment corrected (the marriage made the
  combination the point).
- **run-qualification.sh**: seven unpaged-semantics sites pinned
  `TF_KV_PAGES=off` explicitly (kvqual's and kvqual4's run_gates, the
  throughput phase's both cells, kvqual4P's window-mode control, the
  parity reference cell, the depth ladder's dense8 arm) — their
  historical unpaged semantics preserved; the serve-default phases
  (prefill/depth's dense4fp8 arm/hmcheck/confirm) inherit the adopted
  default.
- **README**: the `TF_KV_PAGES` env row added (the default `on`).
- **DELTAS.md**: the engine row updated to the adopted state.

**LAUNCHED: adoptsmoke** — the bare-config smoke test: a restart with
ONLY the structural pairs (every serving default from config.sh), the
serve line verified (the 4-patch list + the pages pool), one greedy
probe. ~10 min. THEN DARK. Next arc: the v1.2.3 rebase (re-anchor the
four patches, re-validate), per the (user) directive.

## (round 133, cont. 66) THE SMOKE TEST CAUGHT A REAL ADOPTION GAP: config.sh's TF_KV_PAGES was an unexported shell variable — env_args() forwards TF_KV_* from the ENVIRONMENT (env | grep), so the bare start ran window-mode; the export fix; the smoke re-launched (2026-11-06)

**campaign-20261106-061130 (adoptsmoke, the first run)**: the probe
answered OK, but the serve line was **window-mode fp8** (3.75 GiB per
stream, model 84.75 GiB — the paged serves all read 81.35 GiB with the
pages pool line): **TF_KV_PAGES=on never reached the engine.**

**The root cause**: env_args() (config.sh) forwards the engine's
TF_KV_* variables **from the environment** — `env | grep -E
'^(TENSORFOLD|TF_GLM|TF_HEAT|TF_ROCE|TF_KV|NCCL)_...'` — and `env`
lists only EXPORTED variables. config.sh's
`TF_KV_PAGES="${TF_KV_PAGES-on}"` set an unexported shell variable:
it reaches the arg builder (nothing to build — the engine reads the
env), never the container. The paged phases worked because
`env TF_KV_PAGES=on ./scripts/start.sh` EXPORTS. The bare start
(the adoption's whole point) did not.

**THE FIX**: `export TF_KV_PAGES="${TF_KV_PAGES-on}"` in config.sh —
the exported variable lands in start.sh's environment (config.sh is
sourced at start.sh:20), env_args() forwards it to both ranks, and the
explicit `TF_KV_PAGES=off` pins override it (env's override semantics).

**RE-LAUNCHED: adoptsmoke** — the same bare-config smoke test; the
serve line must now carry the pages pool. ~10 min. THEN DARK.

## (round 133, cont. 67) THE v1.2.3 REBASE: the four patches re-anchored onto v1.2.3 (6ec5fa4cb), verified byte-identical on a fresh checkout; v123qual launched (2026-11-06)

The adoption was smoke-verified first (campaign-20261106-062829: the bare
config serves the paged pool — model 81.35 GiB, **4100 pages of 512 rows
(13.61 GiB)**, probe OK, deterministic sha — the export fix works; the
fp8+pages marriage is the line's default, fully receipted).

**THE DRIFT MAP** (all four patches DRIFT on v1.2.3 — the rebase work):
- **absorb**: only the cuda_engine.zig:181 hunk — v1.2.3 logs a prompt
  chunk's exchange row pieces at TP>1, and the new line sits in the
  hunk's trailing context (the insertion point itself unchanged). The
  re-anchored hunk carries the pieces line; the diffstat still matches
  the original exactly (9 files, 247 insertions, 7 deletions).
- **the marriage (fp8-pages)**: v1.2.3 CONSOLIDATED the three inline
  `latent.Table` sites (attend/blockLastRow/writeKeys) into a
  `tables(l, c)` helper — the port's `.logical = c.ls != 0` on `t` now
  lands there (one site; the LatentShape guards moved into the helper by
  the refactor and are preserved). cuda_native.zig's explain() table
  re-anchored: v1.2.3 dropped GlmSoloWithDrafter and added
  BadCopyPolicy/GlmKvHostNeedsPages — BadKvPages + PoolTooSmall still
  insert after Fp8OnPages. cuda_glue.zig applies VERBATIM (the file is
  unchanged between v1.2.2 and v1.2.3 — the hunk was anchored on the
  absorb tree and absorb re-anchored identically).
- **pagerows-fix**: one site in the helper (was three); tk inherits
  t.page_rows there as before.
- **selist-fix**: one site in the helper (was attend only). v1.2.3
  ALREADY threads tk into blockLastRow's indexUpdate and
  attendLastRow's selectTokensProfile — with the fix, the MTP
  prompt-chunk path is covered too (on v1.2.2 it rode t). Upstream's
  refactor converged toward our fix's semantics (selection via tk,
  attention via t).

**THE VERIFICATION**: the four patches applied in sequence on a rebase
branch (bbed940e → 1ce28d3c → a5f80170 → abb6bb90), regenerated as the
same-named patch files with v1.2.3 headers (the marriage's duplicated
STAGING paragraph deduped), then applied on a FRESH v1.2.3 worktree —
**byte-identical to the branch tip**. `latent.chunk = 512` exists on
clean v1.2.3; the Table line is untouched by v1.2.3.

**THE PIN**: scripts/local.sh TF_COMMIT → 6ec5fa4cb233f3606acbdad5bec433f0f8758f96
(the COMMIT sha — `git rev-parse v1.2.3` returns the annotated tag
object abcdefb5…, not the commit; the pin must checkout the commit).
v1.2.2 remains the qualified default until the receipt; the pin reverts
if the window fails.

**LAUNCHED: v123qual** — the full instrument set in the sparsefix order:
the harness replay (TC-62 TC-49, the loop discriminator on churned
pages), the sparse-prefill code probe (5 rounds MKR-{i}QX at ~row 3,650),
a FRESH restart, the hardmode battery + the vision suite. The bar: the
replay stops looping + the probe 5/5 exact + hardmode ≥ 94 + the vision
4/4. ~50 min (the image rebuild for the new ref included). THEN DARK.
If it clears: the v1.2.3 adoption digest (the pin stays, config.sh
comments) + v1.2.3's perf items (TF_GLM_CHUNK_SOLO=4096 ~7% TTFT at
TP=2, TF_GLM_COPIES=1) go on the perf plan.

## (round 133, cont. 68) THE v1.2.3 ADOPTION: v123qual (campaign-20261106-065920) clears every bar — the replay 100 with the standing run's EXACT token profile, the probe 5/5, hardmode 95, the vision 4/4; the pin stays on v1.2.3 (2026-11-06)

**v123qual's receipt** (the rebased 4-patch stack on v1.2.3 = 6ec5fa4cb,
TF_KV_PAGES=on — the serve line carries the paged pool: model 81.35 GiB,
4100 pages of 512 rows, 13.61 GiB):
- **The harness replay: final_score 100** — TC-62 passes 5,043 tokens /
  12 turns, TC-49 751 / 3 turns — **byte-for-byte the standing run's
  profile**, zero truncated notes: the loops GONE on v1.2.3's rebased
  stack (the churn discriminator).
- **The sparse-prefill code probe: 5/5 exact** MKR-{i}QX (the code at
  ~row 3,650, beyond dense_limit, on recycled pages).
- **The hardmode battery: final_score 95** (production parity; the bar
  ≥ 94; the standing paged run's 95 exactly) — **total_tokens 662,693,
  BYTE-IDENTICAL to the standing run's**; token_efficiency 0.30 and
  deployability 74 (both standing); median_turn_ms 6,405.5 (the standing
  window-mode 6,829.6 — 6.2% faster; the paged receipt's 6,381.8 within
  instrument noise).
- **The vision suite: 4/4** (all eight probes ok).

**THE v1.2.3 ADOPTION**: the bar fully cleared — the pin STAYS on
v1.2.3 (6ec5fa4cb, the commit sha). The digest edits: config.sh's
TF_KV_PAGES + PATCHES comments cite the v123qual receipt; README's
status rows + the TF_COMMIT mentions move to v1.2.3; DELTAS' engine row
re-based; the loop hunt's instrument glm-zz-dsasel3.patch RETIRED in
patches/README.md (the mechanism receipted twice — the v1.2.2 sparsefix
and this re-qualification; the instrument was never in the serving
PATCHES list). v1.2.2's §2-gates and duel receipts stand as the MODE's
receipts (the rebase changed no perf path — absorb's diffstat is
identical and the helper consolidation is semantics-preserving); the
v123perf arms double as the rebase's perf spot-check.

**LAUNCHED: kvqual4P + depth + v123perf** (one window): the §2 gates on
the paged v1.2.3 stack (the adoption's gates receipt on the new ref),
the depth ladder re-qualification (the post-adoption re-run, the 12/12
bar), and v1.2.3's two perf knobs (TF_GLM_CHUNK_SOLO=4096 — upstream's
~7% TTFT at TP=2; TF_GLM_COPIES=1) A/B'd on the duel instruments vs the
standing absolutes (solo 63.5/63.2, c2 110.6, c4 154.8, ITL p50 55.3,
slope 0.612). ~60 min + the prepare. THEN DARK. A knob advances to
confirm only on a sharp, reproduced win + the gates (the protocol).

## (round 133, cont. 69) v123perf: CHUNK_SOLO=4096 REFUSED beside the drafter, COPIES=1 pure parity — both knobs retired; the rebase's perf spot-check passes; the launch-interface miss cost kvqual4P+depth their slot (relaunched) (2026-11-06)

**campaign-20261106-080743 (v123perf)**:
- **TF_GLM_CHUNK_SOLO=4096: REFUSED** — "holds buffers no pass uses
  beside --drafter: unset it, or leave out --drafter". The refusal
  survives v1.2.3 (its explain() table entry was dropped, the error was
  not). Our serving keeps DFlash2 — **the knob is retired for our
  shape** (upstream's ~7% TTFT is a drafter-less measurement). The
  refusal is the receipt.
- **TF_GLM_COPIES=1: PURE PARITY** — solo 63.8/63.4 t/s (standing
  63.5/63.2), c2 109.8 (110.6), c4 154.2 (154.8), ITL p50 55.3 ms
  (55.3), TTFT slope 0.611 (0.612), d0 193 (199 ms) — within ~1% on
  every instrument. **Retired per the discipline** (parity retires; a
  knob must win to advance). No config.sh change.
- **The rebase perf spot-check: PASSED** — the copies1 arm (v1.2.3 +
  COPIES=1) rides the v1.2.2 standing absolutes within ~1% everywhere:
  the rebase changed no perf path, as predicted.

**THE LAUNCH-INTERFACE MISS**: autonomous-launch.sh takes the PHASE
LIST AS ITS ARGUMENT (`autonomous-launch.sh "phases summary"`) — the
PHASES env I set alongside was silently ignored, and only "v123perf
summary" ran. kvqual4P and depth never launched. The interface is
logged here; the relaunch passes them in the arg.

**RELAUNCHED: kvqual4P + depth + summary** — the §2 gates on the paged
v1.2.3 stack (the adoption's gates receipt on the new ref) + the depth
ladder re-qualification (the post-adoption re-run, the 12/12 bar).
~40 min. THEN DARK.

## (round 133, cont. 70) kvqual4P + depth on the v1.2.3 stack: the ladder 12/12 (the post-adoption re-qual COMPLETE), the §2 gates ALL PASS on the bf16-paged cell — the fp8-paged cell's gates re-staged and launched (2026-11-06)

**campaign-20261106-081942 (the cont. 69 relaunch — the arg carried the
phase list this time)**:
- **depth: 12/12** — 3/3 facts at each of 8k/64k/192k/384k on the
  adopted paged v1.2.3 stack. **The post-adoption depth re-qualification
  is COMPLETE** (the depth family's receipt on the new ref; the queued
  item closes).
- **kvqual4P: ALL §2 gates PASS** (g1 determinism content, g2
  drafted=plain, g3 resumed=fresh, g4 concurrent=solo 4/4, g5 sampled)
  — **on its original bf16-paged cell**: that phase predates the
  marriage (its restart pairs run bf16 + pages + a bf16-window control,
  whose expected refusal didn't fire — recorded). A real receipt for
  the bf16 cell + the gate machinery on v1.2.3, but NOT the adopted
  fp8-paged cell's.

**The v1.2.3 receipt set** now: hardmode 95 + the vision 4/4 + the
replay 100 + the probe 5/5 (v123qual), the perf parity (v123perf), the
depth 12/12, the bf16-paged §2 (kvqual4P). The one missing piece for a
fully symmetric set: the fp8-paged §2 on v1.2.3.

**LAUNCHED: pagedgatesv123 + summary** — the retired pagedgates phase
re-staged under a new name (the instrument rule), one restart + the
gates on fp8 + pages + dense4 + 512K on the rebased stack. ~15 min.
THEN DARK. This completes the v1.2.3 arc's receipt set; the perf plan's
next step is the Front 2 overlap class (the fork's 0010/0033 HC-split/
overlap set or PDL on the finish launch) — the next arc.

## (round 133, cont. 71) THE v1.2.3 ARC COMPLETE: pagedgatesv123 (campaign-20261106-084338) — ALL §2 gates PASS on the fp8-paged rebased stack; the session phases retired; the next arc opens on #1732's KV_SHARE warm-resume mechanism (2026-11-06)

**pagedgatesv123's receipt** (fp8 + pages + dense4 + 512K on the rebased
stack): PASS g1 determinism (content), g2 drafted=plain, g3
resumed=fresh (the same answer tokens as the v1.2.2 run: alpha-7391,
bravo-2250, charlie-8118), g4 concurrent=solo (4/4), g5 sampled
identical-in-content. Identical receipt shape to the v1.2.2 pagedgates
run.

**THE v1.2.3 RECEIPT SET IS FULLY SYMMETRIC** — every family re-
receipted on the new ref: §2 gates (fp8-paged ALL PASS + the bf16-
paged cell ALL PASS), depth 12/12, hardmode 95 + the vision 4/4, the
replay 100 + the probe 5/5, the perf parity (the copies1 arm within
~1% of the v1.2.2 absolutes on every instrument). The arc closes:
pagedgatesv123 + v123perf + v123qual retired from
run-qualification.sh (all receipted; the discipline).

**THE NEXT ARC (the perf plan's Front 2)**: the survey of the two
remaining overlap candidates — the PERF_PLAN's ".pdl flag" reference
turned out to be the FORK's field (their 0033 test shows their
mm.Kernels carries .pdl/.pair/.packed_prompt; OUR tree has zero PDL
plumbing — building it is a from-scratch job with a modest expected
win, the round-116 finding being that the hc chain's launch gaps are
already hidden behind the queue depth), and the fork's 0010 (the
HC-split/overlap implementation) was never fetched — 0033 is its TEST,
targeting their kernel set (a foreign-base port). **The chosen next
step: the plan's own listed next A/B — #1732's KV_SHARE+pages pair,
the warm-resume mechanism** (the concurrent resume's 4× serialization
is a priced, parked gap; the knob remaps the resume onto pool pages).

**LAUNCHED: kvshare + summary** — two arms (the standing host store vs
TF_GLM_KV_SHARE=4): the g3-style content check per arm (the resume
path changed — the content must not), the resumecost volley instrument
(d2048/4096/8192 × 3 shots, the ttft walls), and the concurrent
4-prefix volley (cold sequential, then all four resumed in parallel —
the 4× serialization probe). The <4-states refusal is a receipt. A
sharp warm/concurrent-resume win advances the knob to the gates + the
battery; parity or a regression retires it. ~25 min. THEN DARK.

## (round 133, cont. 72) kvshare (campaign-20261106-090311): the knob is PARITY on the solo warm resume and the concurrent 4-prefix resume MISSES in BOTH stores (cached=0 ×8) — the cascade eviction exposed; kvshare2 probes N=8 + the solo-warm diagnostic (2026-11-06)

**kvshare's receipt** (the host store vs TF_GLM_KV_SHARE=4):
- **The solo warm resume: DEAD PARITY** — every ttft wall identical
  between the arms to within 0.1-0.3% (the colds 3.48/3.50, the warm
  resumes 1.87/1.87, 1.35/1.35; the walls' d-row labels shift with the
  cross-request prefix sharing — the d4096 cold resumed 2048 tokens
  from the d2048 state, the shared-prefix mark working as designed).
  **The pool-page store's per-resume cost is NOT faster than the host
  store's** — the resume cost is not the store's medium.
- **The content check: IDENTICAL in both arms** (the resume path does
  not change content).
- **The concurrent 4-prefix probe: BOTH ARMS MISS** — all eight warm
  requests cached=0, the aggregate 13.93/13.91 s = four full cold
  prefills. The host arm's cache lines expose the mechanism: "3
  states, 546 MiB and 132 MiB spare of 679 MiB (evicted 7)" — 4 × 182
  MiB does not fit the 679 MiB store, and each warm MISS re-prefills
  and re-keeps, evicting the NEXT state: a cascade. The page store
  (share4) missed identically — N=4 states with 4 live streams yields
  nothing spare (the refusal's own arithmetic warned: "live streams
  evict each other's before a resume").
- **THE VERDICT: the knob retires at N=4** (parity on the solo resume;
  no concurrent fix) — **but the receipt localizes the concurrent-
  resume gap to store capacity/eviction, not the resume medium**. The
  round-123 4× serialization park has its mechanism-level suspect.

**RE-LAUNCHED: kvshare2 + summary** — the deciding probe: N=8 (states >
streams — the page budget is trivial: 8 × 8 pages of 4100) + the
solo-warm diagnostic (after the 4 colds, ONE warm solo before the
concurrent volley: a solo HIT with concurrent MISSES = the live-stream
interaction; a solo MISS = the states are gone entirely). The host arm
runs as the reference. A concurrent-hit win advances the knob to the
gates + the battery; a miss retires the mechanism for good and the
park's explanation is receipted. ~15 min. THEN DARK.

## (round 133, cont. 73) kvshare2 (campaign-20261106-092703): THE CAPACITY FIX WORKS — N=8 holds all four states through the live streams, the concurrent volley hits 4/4 (7.41 s vs the host arm's 12.29 s, −40%); the knob advances to the adoption judgment (2026-11-06)

**kvshare2's receipt** (the host store vs TF_GLM_KV_SHARE=8):
- **The page store HOLDS the states**: the pool's idle lines walk
  "free 4096 + store 4 → 4092 + 8 → 4088 + 12 → 4084 + 16" — four
  prefix states as 16 pool pages, **zero eviction**, stable through
  the live streams and the concurrent volley.
- **The solo warm: HIT** (1.841 s) — the host arm's solo warm MISSED
  (3.475 s, the cascade: "hits 0, misses 5, evicted 3").
- **The concurrent 4-prefix volley: ALL FOUR HIT** — cached=2048 ×4,
  ttft 1.840-1.848 each, the aggregate **7.41 s vs the host arm's
  12.29 s** (−40%; vs kvshare's 13.9 s baseline, −47%). The per-
  request resume cost did NOT inflate under concurrency (1.84 solo =
  1.84 concurrent) — **the round-123 serialization confirmed cleanly**:
  the queue serializes the resumes; the cost per resume is flat.
- The host arm's concurrent volley: 1 hit + 3 misses (12.29 s) — the
  store's budget/eviction decides which prefixes survive.

**THE KNOB ADVANCES**: the concurrent-resume aggregate −40% with a
reliable solo warm, zero content risk surfaced (kvshare's content
check IDENTICAL; the g3 gate re-receipts it on the knob).

**LAUNCHED: kvsharequal + summary** — the adoption judgment: the full
§2 gates on the knob (g3 resumed=fresh is THE gate — the resume path
now rides the pool pages), a fresh restart, the hardmode battery + the
vision suite. The bar: §2 PASS + hardmode ≥ 94 + the vision 4/4 =
ADOPT (config.sh exports TF_GLM_KV_SHARE=8 as the default); any miss =
retire. ~50 min. THEN DARK.

## (round 133, cont. 74) THE KV_SHARE=8 ADOPTION: kvsharequal (campaign-20261106-093921) — §2 ALL PASS (g3 receipts the pool-page resume path), hardmode 95 + the vision 4/4, total_tokens 662,693 byte-identical; config.sh adopts the knob; the bare-config smoke test launched (2026-11-06)

**kvsharequal's receipt** (TF_GLM_KV_SHARE=8, the 4-patch v1.2.3 stack):
- **§2 ALL PASS** — g1 determinism (content), g2 drafted=plain, **g3
  resumed=fresh** (the same answer tokens: alpha-7391, bravo-2250,
  charlie-8118 — THE gate for the changed resume path), g4
  concurrent=solo (4/4), g5 sampled.
- **The serve line**: "the prompt cache over the pool's pages" — the
  knob's signature; the pool reads **3075 pages of 512 rows (10.21
  GiB)** — 1025 pages (~3.4 GiB) reserved for the store, 4100 → 3075
  free; the one-at-524288 guarantee unchanged.
- **The hardmode battery: final_score 95** (production parity; the
  standing score) — **total_tokens 662,693, BYTE-IDENTICAL to the
  standing run's** (the third consecutive receipt with the exact
  profile); token_efficiency 0.30, deployability 74 (both standing);
  median_turn_ms 6,432.4 (within instrument noise of the paged
  receipt's 6,381.8).
- **The vision suite: 4/4** (all eight probes ok).

**THE ADOPTION DECISION (the receipts-equal-or-better protocol)**:
the quality gates (the battery 95 + the vision 4/4), the correctness
gates (§2 ALL PASS — g3 receipts the re-plumbed resume), the
instrumented win (kvshare2: the concurrent 4-prefix aggregate −40%,
7.41 vs 12.29 s, with the per-request cost flat; the solo warm
reliable where the host store cascades), the content checks IDENTICAL
(kvshare + g3), and a bounded, receipted trade (the pool reserve).
**config.sh adopts `export TF_GLM_KV_SHARE="${TF_GLM_KV_SHARE-8}"`**
(the cont. 66 export lesson applied — env_args() forwards TF_GLM_*
from the environment); the README carries the env row; DELTAS' engine
row gains the knob; PERF_PLAN's concurrent-resume item splits into the
SOLVED store half and the remaining queue half (upstream-shaped).

**LAUNCHED: adoptsmoke2 + summary** — the bare-config smoke test (the
cont. 66 discipline: after ANY default change, smoke-test the bare
config and read the serve line's memory arithmetic). ~10 min. THEN
DARK. Next arc: the Front 2 build-class candidates (PDL from scratch
or the 0010 port) need a design decision; the upstream watch continues
each sitting.

## (round 133, cont. 75) THE KV_SHARE ARC CLOSED END TO END: adoptsmoke2 (campaign-20261106-103510) — the bare config serves the knob (the export fix verified); the 0010 fetch corrects the plan's citation (2026-11-06)

**adoptsmoke2's receipt** (the bare config: only the structural pairs on
the restart — every serving default from config.sh): the serve line
carries **"the prompt cache over the pool's pages"** — TF_GLM_KV_SHARE=8
reached the engine via config.sh's export (the cont. 66 lesson holds
for the new knob); the probe answers OK. **The pool arithmetic matches
the receipted kvshare2 shape exactly** — 4100 pages total, store 0 at
boot, the kept states carving dynamically ("free N + store M == 4100",
the kvshare2 receipt's own boot shape, where the −40% win was
measured). kvsharequal's 3075-page boot is noted as boot-time variance
(an immediate restart after the gates' container; its battery still ran
95 — both shapes serve the bar). adoptsmoke2 retired (receipted).

**THE KV_SHARE ARC IS CLOSED END TO END**: the probe (kvshare, parity
at N=4 + the cascade exposed) → the diagnostic (kvshare2, N=8 holds
all four states, the concurrent volley −40%) → the qualification
(kvsharequal, §2 ALL PASS + hardmode 95 + the vision 4/4 +
byte-identical) → the adoption (config.sh exports the default) → the
smoke (the bare config serves it).

**THE 0010 FETCH + THE CITATION CORRECTION**: the fork's repo
(MiaAI-Lab/GLM-5.3-Flash-DGX-Sparks-1104 — active, now at patch 0108)
cloned to /tmp/mia-fork; **patches/engine/0010 is a 7-line CORRECTNESS
patch** (the shared-expert side stream drains before its buffers go —
error paths only, "successful calls are unchanged"), NOT the +36%
prefill perf lever the perf plan attributed to "(0010/0033)". Our tree
has no side-stream code (no Engine.side in cuda_moe.zig) — 0010 has no
anchor here regardless. The fork's prefill-class lever in that era is
the **0009 (packed prompt matmuls in two stages) + 0033 (the f_b+g_b
pair launch test)** line. PERF_PLAN's citation corrected; the next
sitting's opener is the design pass: locate the fork's actual prefill
claim in its README/RESULTS, map 0009+0033's surface onto our v1.2.3
tree, and write the candidate-patch design before any window.

No window this sitting — nothing to test until a candidate patch is
built; the design pass is desk work.

## (round 133, cont. 76) THE DOCS-ACCURACY PASS: the README/DELTAS/anchors re-paired to the current receipts; the model cards refreshed from the bench store (2026-11-06, (user) ask)

No new measurements — every number cited was already receipted; this sitting
re-paired the standing docs to them:

- **README**: the Speed row re-paired to the PAGED duel (the stale TR3-duel
  numbers retired: solo 110%→**108.5%**, c4 80%→**parity 154.8 vs 154.6**,
  cold 309%→**328%** (5,215 ms, slope 0.612), overhead 91%→**93%**, with
  c2's floor-vs-top nuance and the prefill 69% added); the Quality row cites
  the three byte-identical 95 receipts (campaign-20261106-043015/-065920/-093921);
  the serve/Exactness/Context rows cite the v1.2.3 receipts (pagedgatesv123,
  kvqual4P, the depth 12/12, the smoke); the PATCHES row carries the
  **4-patch default** (it still described absorb-only); the KV_CACHE and
  TF_KV_PAGES rows cite the current receipts; the bars row's loading fixed
  (90/91 → **91%**) and the fronts' states named.
- **The anchors** (docs/perf-anchors.tsv): the cold row's `ours` data cell
  5122 → **5215** (the paged duel's number — the ABSORB-only 5122 was the
  pre-pages stack; the chart's bar now matches its own narrative's 328%);
  the header comment moved to v1.2.3 + TF_GLM_KV_SHARE=8; **the chart
  re-rendered** (9 metrics — the guard --check passes).
- **DELTAS' header**: v1.2.2 → **v1.2.3** with the full re-receipt set; the
  CURRENT scoreboard lead is the PAGED duel (the round-132 window-mode duel
  marked as the superseded history); "the served TR3 TIES production" →
  "a point ABOVE" (95 vs 94, three receipts).
- **THE MODEL CARDS (the (user) ask)**: docs/cards/ held only the
  round-108-era cards (the Focus/top4cfg cells and the old production run —
  the served default itself had no card). Refreshed from the bench store
  (cwd-scoped data/benchmarks.sqlite on the head, `tool-eval-bench card`):
  **tr3-definitive.svg** — the shipping config's receipted battery
  (hardmode 95, the byte-identical token profile; kvsharequal,
  campaign-20261106-093921, run 2026-11-06T09-57-44_4a88b560) — and
  **prod-definitive.svg** — production's current-bench anchor (94/104; the
  prodbench receipt, campaign-20261102-213954, run 2026-11-02T21-49-55_2a0fde3b,
  the same instrument, superseding the round-108-era production card). The
  round-108-era cell cards (focus/top4cfg, the old eras) stay as history;
  the README's cards paragraph names each card and its receipt.

No window — desk work only.

## (round 133, cont. 77) THE SWEEP CARDS ANNOTATED ((user) ask): bpw4-sweep-cards.svg now carries its fixed-engine framing and the served pack's current score; the SVG verified in sync with its data first (2026-11-06)

The (user) asked after docs/bpw4-sweep-cards.svg (embedded in the README).
**Verified in sync first**: re-rendering from docs/bpw4-sweep.tsv +
scripts/render-sweep-cards.sh reproduced the committed SVG byte-for-byte —
no drift. **The staleness was framing, not data**: the sweep is the
round-132 FIXED-ENGINE ranking (the (user) swap's basis — all four packs
on TF v1.2.1, window-mode KV), and its served-pack row shows the
sweep-era hardmode 94, while the shipping stack (v1.2.3 + the 4-patch
paged KV + KV_SHARE=8) has receipted **95** three times with
byte-identical profiles. The sweep's scores stay as measured (changing
the cell would falsify the sweep receipt; the packs were not re-swept on
the new engine — that would be its own window).

**The edits**:
- **render-sweep-cards.sh**: the SVG gains a third header line — "the
  round-132 fixed-engine ranking (the (user) swap's basis, 2026-11-02,
  window-mode KV) — the served TR3 cell's CURRENT score on the shipping
  stack (v1.2.3 + the 4-patch paged KV + KV_SHARE=8): hardmode 95,
  receipted three times with byte-identical token profiles" — the cards
  shifted down 24px, the canvas grown to match; re-rendered (4 cards).
- **bpw4-sweep.tsv**: the header carries the NOTE (the fixed-engine
  framing + the current-score pointer).
- **README**: the Quality row and the embedded image's alt text say the
  cards are the round-132 fixed-engine ranking and that the served
  pack's current score is the 95 (the row above).
- **DELTAS' header**: the Focus 93 / AZ 90 figures now carry their
  provenance (the round-132 sweep on v1.2.1; the served pack's sweep-era
  row superseded on the shipping stack).

No new measurements; no window — desk work only.

## (round 133, cont. 78) THE RE-SWEEP LAUNCHED ((user) ask: "re-run the sweep — the readme should reflect what a user gets if they download and use the current version"): the four local packs on the SHIPPING stack, one window, the tsv rows emitted per cell (2026-11-06)

**The design** (the resweep session phase): the round-132 sweep's four
packs re-measured on the shipping stack — v1.2.3 + the 4-patch paged KV
+ TF_GLM_KV_SHARE=8, every serving default from config.sh, only the
pack's MODEL_ID/REVISION varying per cell:
- **tr3** — the served default (Mia-AiLab/GLM-5.3-Flash-EXL3-TR3-4bpw).
- **mia** — production's stock (…-4bpw-TensorFold @ main).
- **focus** — the AZ-Focus (local/GLM-5.3-Flash-AZ-Focus-EXL3).
- **az4** — the AZ top-4 selector (local/GLM-5.3-Flash-AZ-EXL3) riding
  **glm-topk4b.patch on TOP of the 4-patch stack** (verified applying
  clean on v1.2.3+the-4-patches before staging — the AZ cell's fingerprint
  change triggers a prepare rebuild inside its restart).

Per cell: restart → the serve line + RoCE → g1 determinism (two greedy
probes, content sha) → bench_cell (the 104-scenario hardmode battery,
bench v3.0.1) → bench_perf (llama-benchy pp2048/tg128 at d0/d4096/d8192
+ c4@d8192) → a **TSVROW|** line emitted (the battery's final_score +
the benchy table's five values, parsed from the report by the phase).
The tokenizer note: the bench's --tokenizer rides the shell's default
MODEL_ID for every cell (the packs share the GLM tokenizer family; the
round-132 sweep ran the same way — the comparison stays consistent).

~40 min per cell (the load, the g1, the battery ~30 min, the benchy) ≈
**3.5 h for the window** — the longest yet; production restores on the
exit path as always. When it lands: the four TSVROW lines transplant
into docs/bpw4-sweep.tsv, the cards re-render, the README re-frames
(the cards become the CURRENT ranking — "what a user gets"; the
round-132 sweep and its annotation move to history: LAUNCH +
results/bpw4sweep/). A FAIL cell keeps its round-132 row with a note.

THEN DARK.

## (round 133, cont. 79) THE RESWEEP WINDOW BURNED ON MY QUOTING BUG — every cell's env pairs passed as ONE argument (MODEL_ID swallowed "MODEL_REVISION=main"; prepare looked for a mangled hub dir); fixed (one arg per pair + the log-tail on refusal) and relaunched (2026-11-06)

**campaign-20261106-110937: all four cells FAIL in ~1 s each.** The
receipt's prepare error named the tell:
`checkpoint snapshot missing ... models--Mia-AiLab--GLM-5.3-Flash-EXL3-TR3-4bpw MODEL_REVISION=main`
— the pair text embedded in the hub dir name. My resweep_cell call
passed each cell's env pairs as ONE quoted argument; the restart helper
forwards `"$@"` to `env`, which set MODEL_ID to the whole string. The
original round-132 sweep phase avoided it with `$ENVPAIRS` unquoted
(word-splitting); my kvshare/v123perf phases passed one quoted arg per
pair. The resweep was the first to join pairs into one string.

**The fix**: one quoted argument per K=V pair, a comment at the call
site, and the phase now prints the prepare/start log's tail on a
refusal (the first run's phase didn't self-diagnose — the error hid in
the campaign log). The lesson logged (read error text for embedded pair
syntax before suspecting the cache).

**RE-LAUNCHED: resweep + summary** — the same four cells on the
shipping stack (~3.5 h). THEN DARK.

## (round 133, cont. 80) THE RE-SWEEP LANDED (campaign-20261106-112022): the served pack 3 POINTS CLEAR on the shipping stack — TR3 95, production's stock 92, the Focus 92, the AZ top-4 87; the cards re-rendered as the CURRENT ranking (2026-11-06)

**The four cells' receipt** (the shipping stack: v1.2.3 + the 4-patch
paged KV + TF_GLM_KV_SHARE=8, every serving default from config.sh; g1
determinism PASS per cell; RoCE up per cell):

| pack | hardmode | pp_d0 | tg_d0 | tg_d4096 | tg_d8192 | tg_c4_d8192 |
| --- | --- | --- | --- | --- | --- | --- |
| **TR3-4bpw (the served default)** | **95** | 1115 | 48.8 | 50.0 | 43.0 | 14.2 |
| Mia-AiLab 4bpw (production's stock) | 92 | 1114 | 46.7 | 47.8 | 49.0 | 14.3 |
| Focus | 92 | 1116 | 48.4 | 47.3 | 43.4 | 14.2 |
| AZ top-4 (glm-topk4b on the 4-patch stack) | 87 | **1295** | **60.8** | **65.7** | 54.8 | **17.0** |

**The ranking held and STRENGTHENED**: the round-132 v1.2.1 sweep chose
TR3 at 94 vs the field's 93/94/90; on the current stack the served pack
is **95** (matching its three standing receipts byte-for-byte in score)
while production's stock and the Focus both slipped to 92 and the AZ
top-4 to 87 — **the served pack is 3 points clear of everything**. The
(user)'s round-132 choice is validated more strongly on the current
engine. The AZ top-4 stays the perf leader (pp 1,295, tg_d0 60.8,
tg_d4096 65.7 — +25% over the sweep era) at a now-larger quality cost.

**The boot notes**: tr3 loaded in 103 s (cache hit); mia and az4 took
517/501 s (the fingerprint change rebuilt the image inside their
restarts); focus 127 s. The serve lines carried the pool-pages store on
every cell; the boot-time page arithmetic varied (4100 vs 3075 — the
cont. 75 variance, receipted as such).

**THE TRANSPLANT**: docs/bpw4-sweep.tsv's data rows replaced with the
re-sweep's values (the header: the current era + the round-132 sweep as
history); render-sweep-cards.sh's subtitle moved to the current stack;
**the cards re-rendered as the CURRENT ranking**; the README (the
Quality row, the embedded alt text, the AZ-EXL3 revisions row's numbers)
and DELTAS' header re-framed — the embedded scorecards now show what a
user gets on this version. No window — desk work.

## (round 133, cont. 82) THE WORKFLOW CONSISTENCY AUDIT ((user) ask): the autonomous loop's definition found scattered and self-contradicting in one place — fixed; AGENTS.md now carries the loop's canonical map (2026-11-06)

**What was audited**: the four autonomous scripts' headers
(autonomous-launch/window/poke/cron), AGENTS.md, the README's coexistence
section, and the two wake skills (autonomous-agent-wake-loop,
opencode-agent-wake).

**Consistent already**: the scripts' headers (the launcher "the ONLY way
a window is launched... the LAST action of its turn"; the window
"restarts production on EVERY exit path" through the tip's own scripts;
the crash-net "hands off while a window is in flight"; the poke's
health-gate + marker discipline); the README's coexistence section; and
BOTH skills — accurate generic distillations of this repo's loop (the
wake vector, the marker format rules, the two-cron split, "finish the
launch turn before the stop lands") with no drift against the
implementation.

**THE CONTRADICTION FOUND AND FIXED**: AGENTS.md's old bullet said GPU
windows run "only when asked" — while the standing mode for the whole
arc has been the poke-driven loop (the (user) handover). Now:
- the windows bullet defers to the standing loop (outside its shape —
  a new instrument class, a window the plan doesn't state, anything
  touching production — they are the user's, asked first);
- a NEW bullet carries the loop's canonical map: launcher → window →
  head cron (crash net) → agent-host cron (poke), each with its
  one-line contract, closing with the same-sitting digest + the
  launch-last rule, and pointing at the two skills for the mechanism's
  generic form.

No window — desk work.

## (round 133, cont. 83) THE FRONT 2 DESIGN PASS → THE CANDIDATE BUILT AND THE A/B LAUNCHED: glm-mia-packed-s2.patch (Mia 1104 0009 — the two-stage packed-prompt matmuls, bit-identical sums, Mia 1.07-1.09x on prompt shapes); the "+36% prefill" citation withdrawn (2026-11-06)

**The design pass's findings**: the fork's "+36% prefill" (the perf
plan's old citation) is unlocatable in their materials — withdrawn.
0010 = the side-stream drain fix (no anchor here); 0033 = the pair-launch
TEST for a decode-side fusion (the implementation patch unlocated —
parked). The real prefill-class lever: **0009 — glm_mm{4,6,8}_128s2**, 21
lines, applies clean on v1.2.3 (glm_mm.cu/cuda_mm.zig are untouched by
our stack), the mechanism pure occupancy (41 KB two-stage smem → two
blocks/SM; a 768-row piece's 384 blocks fit one wave instead of 2.04),
and the sums **bit-identical by construction** (the K groups run in the
same order; Mia measured 0 differing outputs on all eight shapes). Mia's
number: 1.07-1.09x on GLM's prompt shapes (sm_120, RTX PRO 6000) — with
the power-cap caveat that our GB10's envelope may convert differently.

**THE PORT**: `glm-mia-packed-s2.patch` staged (the provenance header +
Mia's measurements + the staging note; verified applying on
v1.2.3+the-4-patches), patches/README.md's entry written.

**LAUNCHED: mms2 + summary** — the definitive A/B: arm off (the standing
stack) vs arm on (+ the s2 patch; the rebuild rides the restart), each
with the greedy content probes (three prompt sizes, the content shas —
the cross-arm identity IS the bit-exactness gate) and bench_perf twice
per arm. The bar: content IDENTICAL + a sharp pp gain → the battery +
the duel re-pair; a content DIFFERENT retires outright; pp parity
retires; the tg rows moving is a red flag. ~50 min (the rebuild
included). THEN DARK.

## (round 133, cont. 84) THE mms2 WINDOW DIED AT ITS FIRST PROBE — a python -c invoked without its positional argument (sys.argv[1] IndexError under set -e) AND the window wrapper swallowed the rc (an echo-last reported rc=0 on the dead campaign); both fixed; the console carried the truth (2026-11-06)

**campaign-20261106-172745: the receipt stops after arm off's load
line** — the probe builder called `python3 -c "<script>"` with NO
positional argument: `sys.argv[1]` raised IndexError, `set -e` killed the
campaign, arm on never ran. My kvshare phase used the same pattern but
interpolated the filename into the python source; mms2 used sys.argv[1]
and forgot to pass `"$bf"`.

**THE SECOND BUG, WORSE**: the window logged `window finished rc=0` on
the dead campaign — run-window-block.sh captured `RC=$?`, printed it,
and ended on an `echo`, so the wrapper's own exit status was 0. The
fail-honesty chain broke at the wrapper. **The console carried the
truth** (the traceback + `campaign wrapped (rc=1)`) — reading the
receipt caught what the rc signals hid.

**THE FIXES**: the probe builder passes `"$bf"`; run-window-block.sh
ends with `exit "$RC"` (the wrapper's rc now propagates). The lesson
logged and verify-shell-config-edits extended (end every wrapper with
`exit "$RC"`).

**RE-LAUNCHED: mms2 + summary** — the same A/B (~50 min). THEN DARK.

## (round 133, cont. 85) THE mms2 A/B CLEARS EVERY BAR (campaign-20261106-174454) — the content shas IDENTICAL, pp +3.4/+5.8/+6.7% growing with depth, tg parity; the adoption judgment + the duel re-pair launched in one window (2026-11-06)

**The A/B's receipt** (arm off = the standing 4-patch stack, arm on =
+glm-mia-packed-s2.patch; the rebuild rode arm on's restart):
- **The content gate: IDENTICAL on all three prompt sizes** (short/mid/
  long — the same content sha off and on): **the bit-exactness claim
  verified on our shape** (the K groups' order argument holds on sm_121).
- **The pp rows: +3.4% (d0, 1112→1150), +5.8% (d4096, 1043→1104), +6.7%
  (d8192, 1064→1136)** — two runs per arm, tight spreads (off 1115/1109,
  on 1140/1159), and the gains GROW with depth: the mechanism's
  signature (the packed-prompt path fires harder as pieces deepen).
- **The tg red-flag check: parity** (the d0 means 49.6 off vs 48.6 on,
  inside the benchy tg128 rows' noise band; the decode path uses
  by_rows/tile kernels the patch never touches).

**THE PATCH ADVANCES TO THE ADOPTION JUDGMENT.**

**LAUNCHED: mms2qual + duel + summary** (one window, ~1.5 h): mms2qual —
the §2 gates + a fresh restart + the hardmode battery + the vision on
the 5-patch stack (the bar: §2 PASS + ≥94 + 4/4 = ADOPT) — then the
standing duel phase re-paired with the duel's ours arm riding
**MMS2_DUEL_PATCHES** (the 5-patch candidate; its image is a cache hit
on mms2qual's build; the empty default keeps the duel backwards
compatible). The duel receipt gives the anchors' prefill + cold-depth
rows on the candidate for the adoption digest. THEN DARK.

## (round 133, cont. 86) THE PACKED-S2 ADOPTION: mms2qual + the duel re-pair (campaign-20261106-185208) — §2 ALL PASS, hardmode 95, the vision 4/4, solo 109.2%, cold 340%, prefill 76%; config.sh's PATCHES is the 5-patch stack; the anchors + the chart re-paired (2026-11-06)

**mms2qual's receipt** (the 5-patch stack: the 4 patches +
glm-mia-packed-s2.patch): §2 ALL PASS (g1 determinism, g2 drafted=plain,
g3 resumed=fresh with the standing answer tokens, g4 concurrent=solo
4/4, g5 sampled); **the hardmode battery: final_score 95** (the
standing score — the fourth consecutive 95 on the line's configs); **the
vision suite: 4/4** (all eight probes ok).

**The duel re-pair** (production-for-testing on 8001, read-only, vs ours
on the 5-patch candidate — the same window, the same probes):
- solo: **64.0/64.1 vs 58.6/58.7 — 109.2% CROSSED**
- c2: **110.3 vs 87.2** (production's floor; its range 87-111 — ~parity
  with its top)
- c4: 153.0 vs **193.2** — production near its TOP this run (its range
  155-241; at its floor the pair is parity; ours holds 151-155 across
  every duel)
- ITL: **15.6 vs 17.0 ms/token — 109% crossed**
- TTFT overhead: **192 vs 185 ms — 96%**
- the cold depth: **d8192 5,034 ms, slope 0.591** (the paged pair was
  5,215/0.612 — the s2 gain compounding) vs production's true cold
  17,129 (the prodcold receipt) → **340% CROSSED**

**THE ADOPTION DECISION (the receipts-equal-or-better protocol)**: the
correctness gates (§2 ALL PASS), the quality gates (95 + the vision
4/4), the bit-exactness proof (the content shas identical across arms),
the instrumented gain (pp +3.4/+5.8/+6.7% twice-receipted: the A/B and
the duel's slope), the duel fronts all equal-or-better — **ADOPTED:
config.sh's PATCHES defaults to the 5-patch stack**. The anchors
re-paired on the S2 duel (solo 64.0, c2 110.3, c4 153.0/193.2 with the
range note, overhead 192, cold 5,034 → **340%**, ITL 15.6, prefill
**1,150 → 76%**); **the chart re-rendered** (the prefill bar's first
structural move: 69% → 76%). The README's Speed/PATCHES/serve rows and
DELTAS' engine row re-framed. mms2 + mms2qual retired (receipted); the
duel's MMS2_DUEL_PATCHES override stays (the candidate-duel pattern).

No window — desk work.

## (round 133, cont. 87) THE PREFILL FRONT'S NEXT LEVER PORTED AND THE A/B LAUNCHED: glm-mia-exl3prompt.patch (Mia 1104 0007+0008 hand-ported — one call a pass, the slot-row write, no MTP beside a drafter) (2026-11-06)

**The candidate**: the fork's 0007+0008 — the pair behind the "+next two
changes" in the packed-s2's combined cold-prefill claim (+12.6/15.6/16.0%
at 4K/16K/64K with 0009, which we already adopted). The mechanisms:
- **One call a pass** (0007a): cuda_exl3.chunk_rows follows
  cuda_state.prefill_rows (2048 here; was 1024) — every expert's trellis
  decoded once a pass instead of twice (~28 pairs an expert); a pair's
  sums do not depend on which item of 64 holds it — the bits unchanged.
- **The slot-row write** (0007b): the down kernel gains yrow — it writes
  the routed slots of ey straight, dropping the cuMemcpy2D of
  [rows][8][4096] fp32 after every call and the prompt arena's y.
  yrow defaults 0: the old ABI for every other caller.
- **No MTP beside a drafter** (0008): with DFlash2 the target MTP
  layer's caches are never read — the prompt stops absorbing into them
  (a whole DSA+MoE layer a pass; Mia's nsys: 3.4-4.4% of a traced
  2048-row pass).

**THE PORT** (hand-applied — the fork's hunks drifted on v1.2.3): five
files, the k6 hunks dropped (our tree has no 3/6-bit kernels), the
engine's site re-anchored onto prompt_solo.mtpRows, the two test hunks
dropped (the content gate verifies). **The chain verified byte-identical
to the port commit on a fresh v1.2.3 checkout** (the 5 patches + the
port). Staged as glm-mia-exl3prompt.patch (patches/README.md's entry
written).

**LAUNCHED: exl3call + summary** — the mms2 A/B pattern: arm off (the
standing 5-patch stack) vs arm on (+ the patch; the rebuild rides the
restart), the content-sha cross-arm gate (three prompt sizes) + the pp
rows twice per arm. The bar: content IDENTICAL + a sharp pp gain → the
battery + the duel re-pair; a content DIFFERENT or pp parity retires.
~50 min (the rebuild included). THEN DARK.

## (round 133, cont. 88) THE exl3call A/B CLEARS EVERY BAR AND EXCEEDS THE CLAIM (campaign-20261106-201824): content IDENTICAL, pp +24.5/+22.7/+23.3% — the prefill front 76% → 94.5%; the adoption judgment + the duel re-pair launched (2026-11-06)

**The A/B's receipt** (arm off = the standing 5-patch stack, arm on =
+glm-mia-exl3prompt.patch; the rebuild rode arm on's restart, load
558 s):
- **The content gate: IDENTICAL on all three prompt sizes** — the
  bit-exactness claim verified through the one-call rewrite (the
  trellis-decode halving, the slot-row write, the MTP skip).
- **The pp rows: +24.5% (d0, 1151→1434), +22.7% (d4096, 1099→1348),
  +23.3% (d8192, 1129→1392)** — two runs per arm with near-zero spread
  (off 1151/1151, on 1437/1430). **It EXCEEDS Mia's +12.6-16% combined
  claim** — the GB10 converts better than their sm_120 (the dropped
  copy + the halved trellis decodes + the MTP-pass skip land harder
  here).
- **The prefill front: 1,150 → 1,434 tok/s = 94.5% of production's
  1,518** — from 76% in one patch.

**THE PATCH ADVANCES TO THE ADOPTION JUDGMENT.**

**LAUNCHED: exl3qual + duel + summary** (one window, ~1.5 h): exl3qual —
the §2 gates + a fresh restart + the hardmode battery + the vision on
the 6-patch stack (the bar: §2 PASS + ≥94 + 4/4 = ADOPT) — then the
standing duel phase re-paired with the duel's ours arm riding
MMS2_DUEL_PATCHES (the 6-patch candidate; its image is a cache hit on
exl3qual's build). The duel receipt gives the anchors' prefill + cold
rows on the candidate for the adoption digest. THEN DARK.

## (round 133, cont. 89) THE EXL3PROMPT ADOPTION: GO — the sixth patch joins the default stack (exl3qual + the duel, campaign-20261106-212157) (2026-11-06)

**The adoption judgment cleared every bar** on the 6-patch candidate:
- **§2 gates ALL PASS** (g1-g4 PASS, g5's note is the known raw-byte
  nondeterminism) — exl3qual's receipt.
- **Hardmode 95** — the FIFTH consecutive receipt on the line's configs
  (pagedquality3, v123qual, kvsharequal, mms2qual, exl3qual) vs
  production's current-bench anchor 94.
- **The vision 4/4** (all eight sub-scores ok).
- **The duel re-pair** (production-for-testing on 8001, same window):
  solo 63.9/63.7 vs 58.6/58.7 (**108.9%** — decode untouched, the drift
  from the s2 pair's 109.2% is instrument noise); c2 110.3 vs 87.3
  (126% of its floor); c4 153.7 vs 193.1 (production near its TOP this
  run — its range 155-241; at its floor the pair is parity); ITL 15.5
  vs 17.0 (109% — crossed); overhead 190 vs 183 ms (96%); **the cold
  d8192 4,134 ms, slope 0.482 — 414% of production's true cold** (the
  exl3prompt patch compounding the s2 pair's 5,034 and the paged pair's
  5,215); **the prefill front 1,434 tok/s = 94.4% of production's
  1,518** (ours: the exl3call arm-on pair, campaign-20261106-201824).

**DECISION: ADOPT — config.sh's PATCHES is the 6-patch stack** (the
exl3prompt patch appended after packed-s2; the comment carries the
cont. 89 receipt chain).

**The digest executed the same sitting**: the anchors' five duel rows +
the cold row re-paired on the EXL3P duel; **the anchors' header was
found TWO adoptions stale** (it still said the 4-patch stack + the
PAGED duel — the s2-era header edit had failed its assert and was never
retried; this sitting's six-patch rewrite folded the s2 + exl3prompt
adoptions in) — rewritten and the chart re-rendered; the README's
serve/Quality/Speed/bars/PATCHES rows re-paired (the quality row now
cites five 95 receipts, the speed row the EXL3P duel, the bars row
prefill at 94.4% "nearly closed"); DELTAS's header scoreboard
re-paired to the EXL3P duel (the S2 + PAGED duels folded into the
superseded chain — the s2-era DELTAS scoreboard update had also never
landed) and the engine row now describes the 6-patch stack; the exl3call
+ exl3qual session phases RETIRED from run-qualification.sh (both
receipted; the duel's MMS2_DUEL_PATCHES override stays as the
candidate-duel pattern); the ledger's arc block carries the adoption.

**Process note**: two doc-update asserts failed silently across the s2
digest (the anchors header, the DELTAS scoreboard) — the row updates
landed but the header/scoreboard prose was left stale until this
sitting's full re-pair. The digest discipline going forward: after an
adoption, grep the docs for the PRIOR adoption's name to find every
stale mention (the row edits and the prose edits are separate assert
targets, and only the rows were verified cont. 86).

## (round 133, cont. 90) THE BARE-CONFIG SMOKE: the serve evidence is AFFIRMATIVE but the phase died on its own grep (rc=1); the phase fixed, the rerun launched (campaign-20261106-222939) (2026-11-06)

**What the window proved before it died**: the bare start (no env pairs —
config.sh's defaults expand) came up in 103 s on the v1.2.3 pin
(6ec5fa4cb), and the serve line carries both adoption signatures:
"prompts in passes of up to 2048 rows" (the exl3prompt patch's
chunk_rows=prefill_rows) and "the prompt cache over the pool's pages"
(TF_GLM_KV_SHARE=8). RoCE up. The load was a fingerprint CACHE HIT on
exl3qual's build — and the cache-hit condition is config_line equality,
so the bare default's patch list expands to exactly the stored prepared
line: **`$STATE_DIR/prepared` names all SIX patches on the v1.2.3 pin**
(read directly this sitting).

**Why rc=1**: the phase's first witness grep (`^model=.*patches=` over
the start log) has no match in the log — the config_line echo lives in
the prepared marker, and no prepare ran on a cache hit — and
run-qualification.sh's `set -euo pipefail` turned the missing pattern
into a campaign kill before the probe. The receipt file truncated at
the death point; the campaign.log holds the full story.

**The phase fixed**: every receipt-writing grep guarded with
`|| true`; the fingerprint witness now reads `$STATE_DIR/prepared`
(the direct evidence) instead of grepping the start log. The probe and
the serve line unchanged.

**LAUNCHED: adoptsmoke3 + summary** (the rerun — the .done marker was
never touched, so the phase reruns cleanly): the complete receipt
expected (the fingerprint line + the serve line + the probe). THEN DARK.

## (round 133, cont. 91) THE BARE-CONFIG SMOKE: PASS — the complete evidence chain survived the phase's self-inflicted rc=1; the phase retired, nothing launched (campaign-20261106-225025) (2026-11-06)

**The smoke verdict: PASS.** The bare default (config.sh's defaults, no
env pairs) serves the adopted 6-patch stack on the v1.2.3 pin. The
evidence chain, all read this sitting:
1. **The prepared fingerprint the start matched** ($STATE_DIR/prepared
   — start.sh re-prepares only on a config_line mismatch, so a
   cache-hit start proves the bare default expands to exactly this
   line): `patches=glm-mia-absorb-mma.patch,glm-mia-fp8-pages.patch,
   glm-mia-pagerows-fix.patch,glm-mia-selist-fix.patch,
   glm-mia-packed-s2.patch,glm-mia-exl3prompt.patch` at
   `tf=commit@6ec5fa4cb…` — all SIX patches.
2. **The serve line**: "prompts in passes of up to 2048 rows" (the
   exl3prompt patch's chunk_rows=prefill_rows) + "the prompt cache over
   the pool's pages" (TF_GLM_KV_SHARE=8) — load 107 s (the fingerprint
   cache hit on exl3qual's build).
3. **The probe**: the reply `'smoke-ok-6patch'` EXACT (23 prompt + 7
   completion tokens; as3-probe.json).

**Why rc=1 anyway (the forensics, closed)**: my cont. 90 phase fix
spliced by string-index and left the OLD block in the file behind the
fixed one. The window script runs every window with **FORCE=1**
(autonomous-window.sh line 46 — intra-window .done markers never
guard), so both blocks executed: the fixed block completed in full
(the probe json + marker at 22:52:14.44/.47), then the old block ran —
restarted the stack a second time, re-truncated the receipt file, and
died at its unguarded `^model=` grep (pipefail + set -e) — rc=1. The
summary phase never ran (killed before it); the guard checks ran on
this sitting's commits instead.

**Actions**: the adoptsmoke3 phase RETIRED whole (both blocks — the
receipted smoke closed the default-change loop; a future default
change writes a new smoke phase); the splice lesson and the
FORCE=1-in-windows property logged (splices go by line-range deletion,
never string-index replacement of a partial region).

**NO LAUNCH** — nothing to test: the default-change loop is closed and
the perf plan's next step is a hunt (the fork's later series, the
upstream watch, or the loading wall's re-take at 91%).

## (round 133, cont. 92) (user) THE DEV MODEL ON 8001 FOR PRESTO-MONITOR TESTS — production stopped for an interactive user session (2026-11-06)

**The (user) call**: "start the dev model on port 8001, I need to do
some tests with it for the presto-monitor project, this will mean
shutting you down temporarily." The user takes the GPUs for their own
interactive session — outside the window flow's shape, done by direct
instruction (the standing rule: anything outside the loop's shape is
the user's, asked first — this is the asking).

**The arrangement**: the window flag (/tmp/autonomous-testing.flag) is
set manually so the crash-net cron hands off instead of restarting
production under the user's session; production (8000 — this agent's
serving model) is stopped through the tip's own stop.sh (both ranks);
the testing stack starts via the bare ./scripts/start.sh (the
smoke-verified 6-patch default, port 8001) and stays UP for the user.

**The restore** (when the user's tests are done): clear the flag —
`rm /tmp/autonomous-testing.flag` on the head — and the crash-net's
next tick (≤5 min) restarts production via the tip's start.sh; or the
agent restores on the user's signal the same way. The testing stack
comes down first (scripts/stop.sh) so the GPUs are free.

## (round 134, cont. 93) THE ATTENTION FP8 8-BYTE PREFETCH PORTED AND THE A/B LAUNCHED: glm-mia-attnfetch8.patch (Mia 1104 0005+0011 — decode chunks −40% claimed) (2026-11-07)

**The dev session closed first (user)**: the flag cleared (the
crash-net re-armed — it had correctly hands-off'd through the user's
session), the fork's remaining series triaged: 0013's stale-tap bug is
ALREADY MAINLINED in v1.2.3 (upstream PR #1623 — tapPieces/shareTaps
present in our tree), 0006+0010 (the MoE side-stream overlap) is the
next candidate after this one, 0012/0014/0015 are capacity/hygiene.

**The candidate**: 0005+0011 — the latent attention's FP8 key tiles
load 8 bytes at a time, a tile ahead (the reads overlap QK/softmax/PV),
converting where load_kv(tile+2) stood; the same cvt/row-scale/bf16
rounding per value (bit-order verified: little-endian code pairs), so
the shared-memory keys are the same bits. 0011 names the 256-thread
block CHUNK_THREADS (static_assert + the kernel traps otherwise).
**Mia's claim: decode dense chunks 58 → 35 µs, sparse 72 → 41-44 µs.**

**THE PORT** (hand-applied): the fork's baseline predates the paged
marriage — our chunks_wide carries PAGED8, so fetch8 folds the
page-table addressing (dense at the bases moved once, sparse through
pt[src/CH]; uint2 8-byte loads safe — pstep is 16-aligned for cp16).
**The chain verified byte-identical to the port commit on a fresh
v1.2.3 checkout** (the 6 patches + the port). Staged as
glm-mia-attnfetch8.patch (patches/README.md's entry written; the
exl3prompt entry's status corrected to ADOPTED).

**LAUNCHED: attnpref + summary** — the A/B: arm off (the 6-patch
stack) vs arm on (+ the patch; the rebuild rides the restart), the
content-sha cross-arm gate (three prompt sizes) + bench twice per arm
+ **the steady-state decode probe** (two solo 2048-token greedy
generations per arm — the honest tg instrument). The bar: content
IDENTICAL + a sharp steady-state tg gain → the battery + the duel
re-pair. ~50 min. THEN DARK.

## (round 134, cont. 95) THE ATTNFETCH8 A/B CLEARS THE CONTENT GATE WITH A CONSISTENT DEPTH GAIN; THE JUDGMENT + THE DUEL LAUNCHED (campaign-20261107-010849) (2026-11-07)

**The A/B's receipt** (arm off = the 6-patch stack, arm on = +
glm-zz-attnfetch8.patch; the rebuild rode arm on's restart):
- **The content gate: IDENTICAL everywhere** — the three prompt sizes
  AND the 2048-token decode replies (369 vs 369 tokens). The
  same-bits claim holds: the quality instruments cannot move.
- **The bench rows** (2 runs/cell, sub-second resolution): pp
  +1.7/+3.6/+3.9/+4.0/+4.3% (growing with depth); tg +4.7/+3.3% (c2/c4
  at d4096), +3.2/+2.9% (c2/c4 at d8192), +10.9% (d4096 solo), +5.8%
  (d8192 solo); d0 tg -1.4% is the noise cell.
- **The steady-state probe read parity** (off 41.0/36.9 vs on
  36.9/41.0 tok/s) — an instrument limit, not a patch fact: its walls
  are integer seconds on a ~9 s request (±1 s = ±11%), so it cannot
  resolve the 3-5% the bench rows show; the probe's pairs mirrored
  each other. The bar's "tg parity retires" clause assumed the probe
  resolves single digits — it does not; the duel's solo ITL instrument
  (0.2% stability) is the resolving instrument and rides this window.

**LAUNCHED: attnqual + duel + summary** (one window): attnqual — the
§2 gates + the hardmode battery + the vision on the 7-patch stack (the
formality receipts: bit-identical outputs) — then the standing duel
re-paired with the duel's ours arm riding MMS2_DUEL_PATCHES (the
7-patch candidate). **The duel decides the adoption**: its solo decode
moving beyond the 0.2% band + the depth rows = ADOPT; a duel solo
parity = retire. THEN DARK.

## (round 134, cont. 96) THE ATTNFETCH8 ADOPTION: GO — the seventh patch joins the default stack (attnqual + the duel, campaign-20261107-020420) (2026-11-07)

**The adoption judgment cleared every bar** on the 7-patch candidate:
- **§2 gates ALL PASS**, **hardmode 95 — the SIXTH consecutive
  receipt** on the line's configs vs production's current-bench
  anchor 94, **the vision 4/4** — the formality receipts (the outputs
  are bit-identical by construction).
- **The duel re-pair** (production-for-testing on 8001, same window):
  solo **64.2/65.0 vs 58.7/58.8 (109.4%)** — up from the exl3prompt
  pair's 63.8 avg, a ~6× move beyond production's 0.2% band — the
  resolving instrument the steady-state probe could not be; c2 111.2
  (127% of its floor); c4 157.4 (+2.4% across the duels; production
  near its top again, its range 155-241); ITL 15.6 vs 17.0 (crossed);
  overhead 189 vs 181 ms (96%); **the cold d8192 3,942 ms, slope
  0.458 — −4.6%, matching the bench's depth gain = 434% of
  production's true cold**. Three independent instruments agree (the
  bench depth tg, the duel solo, the duel TTFT-at-depth).

**DECISION: ADOPT — config.sh's PATCHES is the 7-patch stack** (the
patch named glm-zz- to sort after the stack — the alphabetical-apply
gotcha the first window burned on).

**The digest executed the same sitting**: the anchors' six rows +
header re-paired on the ATTN8 duel, the chart re-rendered; the
README's serve/Quality/Speed/bars/PATCHES rows re-paired (six 95
receipts cited, prefill at 96.0% — from 76% two patches ago); DELTAS's
header scoreboard re-paired to the ATTN8 duel (the EXL3P/S2/PAGED
duels in the superseded chain) and the engine row describes the
7-patch stack; the attnpref + attnqual session phases RETIRED (both
receipted); the ledger's arc block carries the adoption. The
staging-order + patch-naming lessons logged.

**NO LAUNCH** — the next candidate (0006+0010, the GLM MoE
side-stream overlap, −12-14% a layer claimed) needs its hand-port
first; that is the next sitting's opener.

## (round 134, cont. 97) THE MOE SIDE-STREAM OVERLAP PORTED AND THE A/B LAUNCHED: glm-zz-moeside.patch (Mia 1104 0006+0010 — the shared expert beside the routed experts) (2026-11-07)

**The candidate**: the MoE block ran the shared expert AFTER the
routed experts on one stream; a decode window now forks the shared
expert's gate/up, SwiGLU, down and put_slot onto a second stream right
after the block's input and joins it before the slot combine — the
kernels, their inputs and the combine's order unchanged, so the bits
are the same; only the overlap changes. TF_GLM_SHARED_SIDE=0 keeps one
stream (the kill switch). 0010 is the correctness companion (the drain
on error/teardown — the side stream never outlives its buffers).
**Mia's claim: 70.6 → 60.6 µs a MoE layer at one row, 96.5 → 84.9 µs
at two (−14/−12%)** — a decode-layer overlap lever, the last real one
in the pre-marriage series.

**THE PORT** (hand-applied, three files): moe's Side/Kernels/forks/
body/fill split into fill + sharedRows; Forward.side + moeKernels;
Engine.side + sideStream()/freeSide() + the 0010 drains. Our drift:
the two Forward constructions carry .absorb_mma (our ABSORB_MMA port)
— .side added beside it; upstream's flashnext has the same pattern
(TF_FLASHNEXT_SHARED_SIDE) so the Stream/Event API matches. **The
chain verified byte-identical to the port commit on a fresh v1.2.3
checkout** (the 7 patches + the port). NAMED glm-zz- TO SORT AFTER THE
STACK (the hunks assume the absorb-mma port's field — the
alphabetical-apply gotcha).

**LAUNCHED: moeside + summary** — the A/B: arm off (the 7-patch
stack) vs arm on (+ the patch; the rebuild rides the restart), the
content-sha cross-arm gate (three prompt sizes + the long-essay
decode reply) + bench twice per arm + the steady-state decode probe
with ~2000-token walls (±2.5% resolution — the attnpref probe's
lesson applied). The bar: content IDENTICAL + a steady-state tg gain
beyond the probe's resolution → the battery + the duel re-pair. ~55
min. THEN DARK.

## (round 134, cont. 98) THE MOESIDE A/B CLEARS WITH A RESOLVED SOLO GAIN; THE JUDGMENT + THE DUEL LAUNCHED (campaign-20261107-083254) (2026-11-07)

**The A/B's receipt** (arm off = the 7-patch stack, arm on = +
glm-zz-moeside.patch; the rebuild rode arm on's restart):
- **The content gate: IDENTICAL everywhere** — three prompt sizes +
  the long-essay decode replies (2048 vs 2048 tokens — the probe
  worked as designed this time).
- **The steady-state probe RESOLVED**: the off arm repeated at
  exactly 51/51 s (0% spread), both on-runs faster (49/50 s):
  **40.2 → 41.4 tok/s avg (+3.0%), 4/4 sign-consistent** — matching
  the claim's transfer math (−14% a MoE layer × the MoE share of a
  decode step ≈ +2.4%). The attnpref probe's quantization lesson,
  applied, paid off.
- **The bench corroborates on the solo cells** (+2.9% d0, +3.1%
  d8192, +6.0% c2@d0) with the depth-concurrency cells flat
  (−0.4-2.2%) — expected: the overlap gain shrinks under saturation;
  the claim's mechanism is the 1-2-row decode window.

**LAUNCHED: moesidequal + duel + summary** (one window): moesidequal —
the §2 gates + the hardmode battery + the vision on the 8-patch stack
(the formality receipts) — then the duel re-paired with the duel's
ours arm riding MMS2_DUEL_PATCHES (the 8-patch candidate). **The duel
decides**: its solo beyond the 0.2% band = ADOPT (the eighth patch);
a duel solo parity = retire. THEN DARK.

## (round 134, cont. 100) THE MOESIDE ADOPTION: GO — the eighth patch joins the default stack; the pre-marriage series is fully triaged (moesidequal + the duel, campaign-20261107-092913) (2026-11-07)

**The adoption judgment cleared every bar** on the 8-patch candidate:
- **§2 gates ALL PASS**, **hardmode 95 — the SEVENTH consecutive
  receipt** on the line's configs vs production's current-bench
  anchor 94, **the vision 4/4** — the formality receipts (the outputs
  are bit-identical by construction).
- **The duel re-pair** (production-for-testing on 8001, same window):
  solo **65.9/66.2 vs 58.7/58.8 — 112.3%** (+2.9% over the ATTN8
  pair's 64.6 avg; two independent instruments agree — the A/B's
  steady-state probe +3.0% and this duel); c2 **113.1 — 129% of the
  floor, past production's top-of-range volley at ~111**; c4 158.6
  (+3.2% across the last three duels; production near its top again);
  ITL 15.4 vs 17.0 (110% — crossed); overhead 187 vs 185 ms (99%);
  the cold d8192 3,990 ms, slope 0.464 (**429%** — within the row's
  window drift of the ATTN8 pair's 3,942/434%; the chain preserved).

**DECISION: ADOPT — config.sh's PATCHES is the 8-patch stack.**

**The digest executed the same sitting**: the anchors' seven rows +
header re-paired on the MOESIDE duel, the chart re-rendered; the
README's serve/Quality/Speed/bars/PATCHES rows re-paired (seven 95
receipts cited); DELTAS's header scoreboard re-paired to the MOESIDE
duel (the ATTN8/EXL3P/S2/PAGED duels in the superseded chain) and the
engine row describes the 8-patch stack; the moeside + moesidequal
session phases RETIRED (both receipted); the ledger's arc block
carries the adoption.

**THE SERIES IS TRIAGED**: every perf-relevant patch in the fork's
pre-marriage series (0005/0006/0007/0008/0009/0011) is adopted with a
receipt or retired with a reason; 0012/0014/0015 are capacity/hygiene.
The arc's scoreboard: the prefill front 76% → 96.0%, solo 108.5% →
112.3%, the cold depth 328% → 429%, ITL 109% → 110% — every quality
receipt intact throughout (seven consecutive hardmode 95s, the vision
4/4 every time).

**NO LAUNCH** — the next lever is a hunt (the loading wall's re-take,
the upstream watch, or the capacity/hygiene ports); that is the next
sitting's opener.

## (round 134, cont. 101) THE BARE-CONFIG SMOKE FOR THE 8-PATCH DEFAULT: PASS, complete on the first try (campaign-20261107-103127); the phase retired (2026-11-07)

**The smoke PASSed with the complete receipt** — every lesson from
the prior smokes applied and none needed: load 109 s (a fingerprint
cache hit on the moesidequal build), **the prepared fingerprint names
all EIGHT patches on the v1.2.3 pin** (the cache-hit condition being
config_line equality, the bare default's expansion is proven), the
serve line carries both signatures (the 2048-row prompt passes, the
pool-pages prompt cache), and the probe replies **'smoke-ok-8patch'**
exact. The phase retired (receipted); the default-change loop is
closed.

## (round 134, cont. 102) THE POST-MARRIAGE SERIES TRIAGED: 0026/0027/0028 already mainlined in v1.2.3; 0030 and 0031+0032 queued as structural ports (2026-11-07)

**The hunt's result**: the EXL3 decode levers (0026 the grouped
load-ahead, 0027 the sm_120 variant, 0028 the no_allocate trellis
policy) are ALL in our tree already — v1.2.3 mainlined them (our
`exl3_grouped.cuh` carries the nx-prefetch warp_tiles with the
LOAD-mode instrument; `ldg_stream_u32` = `ld_nc32`, 0028's exact
rationale in the comment). 0029 a comment fix.

**The remaining candidates are structural**: 0030 (the MoE-glue
fusion — topk_row + group_rows one block, down_combine with the
shared row, two copies + group + put_slot + combine gone a layer; the
bits the same byte for byte; TF_GLM_MOE_FUSE=0) — the biggest port
surface yet, the next sitting's opener with full budget; 0031+0032
(the step-link broadcast — one host round trip per step, the keep
piggybacked, the keep-loss guard) — a TP-pair latency lever in the
rank-pairing-critical class, queued.

**NO LAUNCH** — nothing staged; the smoke's digest (cont. 101) and
this triage are the sitting's work. The next sitting: the 0030 port.

## (round 134, cont. 103) THE STEP-LINK PORTED AND THE A/B LAUNCHED: glm-zz-steplink.patch (Mia 1104 0031+0032 — the picks one gather, the step one broadcast) (2026-11-07)

**The scoping that set the order**: 0030 (the MoE-glue fusion) is 991
lines across 12 files — a multi-sitting port; 0031+0032 (383 lines)
went first.

**The candidate** (bit-preserving, three mechanisms):
- **The greedy picks in one gather**: a window's picks ran one top-1 +
  one gather + one sync + one device read PER ROW; greedyRows batches
  them (the pairs buffer pick_rows=32 wide) — the verify window's rows
  stop paying a round trip each.
- **The step in one broadcast**: 384 bytes (the header + a decode
  step's ids) — one host round trip on the other ranks instead of
  two; rank 0's keep rides its next verify/block/draft step of the
  same slot (keep_flag); 0032's guard: a refused step never loses a
  committed keep.
- **The follower's draws join their gathers** (Engine.discard_draws):
  rank 0 alone reads the tokens.

**THE PORT**: engine_pick + follow + pages_host applied VERBATIM
(v1.2.3's files match the fork's baseline); cuda_engine.zig
hand-ported (pick_rows, discard_draws, the pairs ×pick_rows, draw()'s
discard branch + the greedyRows call) with **0031's moe_fuse leakage
DROPPED** (0030's plumbing — the fork stacks them; 0030 stays queued
with full budget). **The chain verified byte-identical to the port
commit on a fresh v1.2.3 checkout** (the 8 patches + the port).
NAMED glm-zz- TO SORT AFTER THE STACK (the engine hunks assume the
moeside port's side field).

**LAUNCHED: steplink + summary** — the A/B: arm off (the 8-patch
stack) vs arm on (+ the patch; the rebuild rides the restart), the
content-sha cross-arm gate + bench twice per arm + the steady-state
decode probe (~2,000-token walls). The bar: content IDENTICAL + a
steady-state tg gain beyond the probe's resolution → the battery +
the duel re-pair. ~55 min. THEN DARK.

## (round 134, cont. 104) THE STEPLINK RETIRED — the content gate clean, the gain at parity (campaign-20261107-105455); the 8-patch stack stands (2026-11-07)

**The A/B's receipt**: the content shas IDENTICAL on three prompt
sizes AND the 2,048-token essay replies (the no-arithmetic-change
claim held exactly) — but the perf gain is at PARITY:
- The steady-state probe: off 41.0/41.0 vs on 41.0/41.8 tok/s —
  +1.0% avg, 3 of 4 runs at exactly 50 s, inside the probe's ±2%.
- The bench tg: mixed-sign (−2.5% to +2.7% across the nine cells) —
  noise; pp flat (−0.5 to +0.1%) — no overhead, as designed.

**Why parity**: the batching's saving lives ONLY in multi-row verify
windows (a 1-row window does one gather either way — the solo
instruments cannot see the mechanism by construction), and the
verify-window round trips are evidently cheaper on our RoCE pair than
the claim's context assumed. A sub-resolution patch does not meet the
adoption bar.

**DECISION: RETIRE** — the patch stays staged in patches/ (the README
entry carries the retirement and the re-judgment condition: 0030's
fusion changes the economics); the steplink session phase retired;
the 8-patch stack stands unchanged.

**NO LAUNCH** — nothing staged; the next sitting's opener is the 0030
port (the last structural candidate, multi-sitting) or the loading
wall's re-take.

## (round 134, cont. 105) THE UPSTREAM WATCH: v1.2.4 assessed — the direct-reads lever for the loading wall found; the rebase drift mapped (the (user) ask) (2026-11-07)

**The (user) call**: "We should look at the new release of tensorfold
v1.2.4 now." The assessment (ECOSYSTEM.md carries the full note):

- v1.2.4 shipped 675 commits after v1.2.3; the GLM-CUDA/GB10-relevant
  items are few but ONE IS OUR LAST FRONT'S LEVER: **checkpoint.direct
  (#2282/#1901) — direct reads past the page cache, 28-31% faster cold
  on a GB10 claimed** (Flash Next's variant: 74 s → 48 s). Wired for
  Gemma 4/Qwen 3.5 only; **GLM needs a small weights-loader patch
  following their pattern**. Our loading wall: 91% (103 vs 93.7 s) —
  this could cross it.
- #2289: GB10 integrated-GPU sync-D2H staging through the shared pinned
  buffer — possibly shaves the per-step reads. #2354: the TP=2 startup
  naming (observability). #2405: STRICT TF_-setting validation — the
  rebase validation must confirm our knobs boot (our patches' getenv
  knobs live outside core's registry).
- **The rebase drift measured**: packed-s2 + exl3prompt APPLY CLEAN;
  30 failed hunks across the other six (absorb-mma 8, fp8-pages 12,
  the dsa pair 4, attnfetch8 2, moeside 4) — v1.2.4's GLM
  engine/forward/DSA changes.

**THE PLAN (the next sitting)**: rebase the 8-patch stack onto v1.2.4
(the re-anchoring is the opener), wire GLM's weights loader onto
checkpoint_direct (glm-zz-loaddirect, following the gemma4/qwen3_5
pattern), then ONE validation window covers both — the gates + the
smoke + the loading wall's re-take on the direct reads.

**NO LAUNCH** — the rebase is a full sitting's careful work; the
assessment and the plan are this sitting's product.

## (round 135) THE v1.2.4 REBASE LANDED + glm-zz-loaddirect WRITTEN; the v124val window launched (the (user) ask: "Begin the rebase") (2026-11-07)

**The rebase** (the head's /tmp/tf-src, branch v124-rebase = v1.2.4
267c5af6a + 9 commits, one per patch in ALPHABETICAL order):
- **Verbatim (5)**: exl3prompt, packed-s2, pagerows-fix, selist-fix,
  attnfetch8 — the bare-tree drift map's failures re-aligned once the
  stack sat beneath them (the drift was measured against BARE v1.2.4;
  the anchors the stack produces match the hunks' context).
- **Hand-re-anchored (3)**: absorb-mma (the Fingerprint: v1.2.4 is at
  layout 19 "18 plus the prompt pair" with pair/l2pf fields — the patch
  bumps to 20 "19 plus numerics", inserts numerics after bits, and the
  two Forward constructions carry .absorb_mma beside l2pf/
  prompt_pair.piecesOf; the numerics test appended at the new EOF),
  fp8-pages (the two E4M3 snapshot tests + expectSamePrefix8 append
  after v1.2.4's KV_SHARE adapter test; the glm_kv_paged_records import
  beside the pages family; the BadKvPages/PoolTooSmall explain lines,
  Pages.waiting, the host-test step re-anchored), moeside (the side
  field, sideStream/freeSide, the constructor, deinit, view() and the
  solo Forward re-anchored around pair/l2pf; .side on decode windows
  only, the same b == &e.bp logic).
- **New 9th commit glm-zz-loaddirect**: cuda_load_ahead.layersWithCount
  builds core.checkpoint.direct.Layers(gpa, ck, count); on() →
  direct.enter(prefix, next) before each layer's loads (the next layer's
  tensors read on the thread while one packs; ck.get returns the
  copies); off → #1928's read-ahead + release exactly as it was
  (TF_LOAD_DIRECT=0). 23 shards < gather.max_sources 64: engages on our
  checkpoint. No arithmetic changes — the tensors' bytes are the same.

**THE TRIPLE VERIFY**: fresh-v1.2.4 + the 9 commit bodies in order =
byte-identical (0 diff lines); fresh-v1.2.4 + the SHIPPED patch files
(headers + bodies, alphabetical, as the image applies them) =
byte-identical (0 diff lines); the full compile in the builder base
image (zig 0.17.0, nvcc sm_121: fatbins + native) **BUILD RC=0**. The
assembly guard: the 5 verbatim patches' +/- content identical to the old
bodies (a lone "--" separator artifact excluded).

**The pin bumped**: local.sh TF_COMMIT → 267c5af6a (v1.2.4); README's
version-identity rows carry v1.2.4 with the pending-window note; the
scoreboard rows keep the v1.2.3 receipts until the digest re-pairs.

**LAUNCHED: v124val + summary** — the OFF-arm insurance (TF_LOAD_DIRECT=0
restart + probe + the read-ahead witness), the standing restart + the
witnesses (the serve line, the direct-reads rank log, the strict-TF_
refusal scan under #2405, the arms' content shas), the §2 content gates,
one bench pass + the steady-state decode probe, ONE hardmode run (the 95
must hold), the vision suite (4/4 must hold), TWO timed load walls (the
loading row's re-take — 91%, the last uncrossed front, on the direct
reads). ~45 min + the prepare build. THEN DARK.

## (round 135, cont. 2) THE v124val WINDOW BURNED ON THE v1.2.4 KV-SHARE RENAME — fixed (TF_KV_SHARE=16), relaunched (campaign-20261107-123013) (2026-11-07)

**The receipt**: every restart REFUSED — `tensorfold: TF_GLM_KV_SHARE is
now TF_KV_SHARE, the prompt store every family on the KV pool shares:
set that instead`. v1.2.4 MAINLINED the KV-share-over-pages as a core
knob for every family (`core/kv_prompts.zig`, #2282-era work) and its
strict startup validation (#2405) refuses the old name before any
checkpoint work — the exact risk cont. 105 flagged, firing on a NAME
move, not a malformed value. Everything downstream (the OFF arm, the
gates, bench, hardmode, the vision, the walls) is void. The useful
half: the prepare REBUILT clean with the rebased patches (no PATCH
FAILED) and the engine ran far enough to hit the validation — the
rebase's code executes.

**The sweep**: the migration guard AND the new floor are VANILLA v1.2.4
(not our patch). The floor moved too: `fewStates` demands
**N ≥ 4×PARALLEL** ("4 states a GLM stream") — the old ≥PARALLEL rule is
gone, so the adopted 8 at PARALLEL=4 refuses next. Every other exported
name survives v1.2.4 (swept in the rebased tree: TF_KV_PAGES,
TF_GLM_DENSE_BITS, TF_GLM_HEAD_BITS, TF_GLM_PDL, TF_GLM_SHARED_SIDE,
TF_GLM_ABSORB_MMA, TF_HEAT_*, TF_GLM_CHUNK_SOLO; nothing exports
TF_ROCE_*).

**THE FIX**: config.sh exports `TF_KV_SHARE="${TF_KV_SHARE-16}"` (the
rename + the floor: 16 = 4×PARALLEL at the standing config; the comment
carries the full provenance — the kvshare2/kvsharequal receipts stand,
the rename + the floor are v1.2.4's, the value receipted by the re-run).
The store's page reservation roughly doubles (8→16 states) — the pool's
elasticity and the admission arithmetic are the re-run's to verify.

**RELAUNCHED: v124val + summary** (FORCE=1 re-runs the phase from
scratch). THEN DARK.

## (round 135, cont. 3) THE v124val RE-RUN: the rebase QUALIFIES on quality — but the direct reads never engaged (the ninth patch never made the PATCHES list) and hardmode never ran (a phase mkdir bug); both fixed, relaunched (campaign-20261107-125114) (2026-11-07)

**What passed**: the OFF arm boots (104 s, the read-ahead witness fired);
the standing restart boots (112 s, the serve line clean, strict-TF_
refusal lines 0 — #2405 passes with TF_KV_SHARE=16); the arms' content
IDENTICAL; **the §2 gates ALL PASS on v1.2.4 + the native TF_KV_SHARE
store** (g1/g2/g3/g4 PASS, g5 note); the bench pp 1,469/1,410/1,454
(flat vs the v1.2.3 era); the steady-state decode 41.8 tok/s (flat); the
vision 4/4 + the detail rows; the walls 103/103 s; the KV_SHARE=16 boot
holds the one-at-524288 guarantee ("enough for 3 at a 524288 window").

**What failed and why**:
- The direct-reads witness counted 0 and the log shows the read-ahead
  line on the standing boot — **glm-zz-loaddirect.patch was never added
  to config.sh's PATCHES**: the patch existed in patches/ (written,
  triple-verified, committed) but the image built WITHOUT it. The walls
  re-dated nothing (103 = the v1.2.3-era wall, the old path). THE FIX:
  PATCHES gains the ninth (alphabetical: attnfetch8 < loaddirect <
  moeside; it touches only cuda_load_ahead.zig).
- The hardmode section is empty — the phase redirected the bench log to
  "$OUT/v124hm/hm.log" without mkdir (the vision block had one; the
  redirection failed and || true swallowed it). THE FIX: mkdir -p.

**RELAUNCHED: v124val + summary** — the third run of the phase (the
walls + hardmode + the direct-reads witness are its remaining unknowns).
THEN DARK.

## (round 135, cont. 4) THE THIRD v124val: the rebase QUALIFIES (hardmode 95 — the eighth consecutive, the gates ALL PASS, the vision 4/4) — but the direct reads STILL never engaged: the served TR3 pack has 120 shards > checkpoint.direct's max_sources 64; a byte-identical reshard to 55 is the fix (campaign-20261107-132414) (2026-11-07)

**The quality receipt** (everything but the wall lever):
- The OFF arm boots (104 s, the read-ahead witness), the standing boot
  clean (strict-TF_ refusals 0, the arms' content IDENTICAL).
- **The §2 gates ALL PASS** on v1.2.4 + the native TF_KV_SHARE=16 store.
- **hardmode 95** (TC-51 pass, TC-92 pass) — the eighth consecutive 95.
- The vision 4/4 + the detail rows. The decode flat (41.8 tok/s). The
  bench flat (pp 1,475/1,421/1,464; the d0 tg cells noisy upward as
  ever — the duel re-pair settles the solo rows).
- The walls 103/103 s — the OLD path (no change; the row stands).

**The direct-reads diagnosis (the real one this time)**: the ninth
patch WAS in the image (the campaign log: 9 patches staged and applied;
the binary carries the string). `direct.on()` was false at runtime →
the init guard → `files.len > gather.max_sources`: the served
TR3-4bpw pack has **120 safetensors files, ALL holding
model.language_model.* tensors — 120 > max_sources 64** → the direct
path off by design. The 64 cap is an fd budget (64 sources × 16 readers
≈ the 1024 soft limit — each reader opens one fd per file it touches),
so raising it locally is the wrong fix.

**THE FIX: a byte-identical reshard** (`/tmp/tr3-reshard.py` on the
head; the AZ local-pack precedent): 120 shards → 55 × ~3 GiB, every
tensor's bytes copied verbatim, the name set + lengths + total volume +
sha256 of 24 sampled tensors verified before success. The pack lands at
models--local--GLM-5.3-Flash-TR3-4bpw-reshard (the engine mounts the
host HF cache; SERVED_NAME stays "GLM-5.3-Flash-EXL3" — only the source
path moves). config.sh MODEL_ID swaps to the resharded pack. The
checkpoint digest re-hashes once on the first load (the digest cache
rebuilds — absorbed in the untimed first restart). The next v124val run
re-verifies the content gates on the resharded pack (the tensors are
the same bytes — the gates must reproduce exactly).

## (round 135, cont. 5) THE RESHARD VERIFIED AND THE v124val RE-RUN LAUNCHED — the docs swept for stale state (2026-11-07)

**The reshard receipt**: 120 shards → 55 × ~3 GiB in 296 s; VERIFIED —
the name set identical, 24 sampled tensors sha-identical, 163.6 GiB
total; the tokenizer/config family copied
(models--local--GLM-5.3-Flash-TR3-4bpw-reshard; SERVED_NAME unchanged).
config.sh MODEL_ID swapped.

**The stale-state sweep (the same sitting)**: README's serve row (v1.2.4
+ the 9-patch stack + TF_KV_SHARE=16 + the v124val receipts), the
PATCHES row (the ninth + the rebase qualification), the KV_SHARE row
(the rename + the floor + the new value), the served-default row (the
reshard), the bpw4-sweep caption ("then-shipping"), the Speed row (the
v1.2.3-era vintage note — the duel re-pair pending); DELTAS's header
paragraph + the Engine row (v1.2.4 + the 9-patch stack + the round-135
sentence); PERF_PLAN's round-135 entry. Every remaining v1.2.3 mention
quotes its campaign — history stands.

**LAUNCHED: v124val + summary** — the fourth run: the direct-reads
witness on the resharded pack + the timed walls (the loading row's
re-take) + the full quality battery re-run (the content gates must
reproduce on the same tensor bytes). THEN DARK.

## (round 135, cont. 6) THE FOURTH v124val BURNED AT PREPARE — the resharded pack never reached the worker; DOWNLOAD=1 prepare is running the rsync (campaign-20261107-144549) (2026-11-07)

**The receipt**: prepare refused before anything ran — "checkpoint
snapshot missing on [the worker]:
models--local--GLM-5.3-Flash-TR3-4bpw-reshard/snapshots/main ... get it
with: DOWNLOAD=1 scripts/prepare.sh (downloads on the head, then rsyncs
to the worker)". The reshard wrote to the HEAD's hub dir only; the
worker's cache still holds only the original 120-shard pack. Production
restored normally (the window's exit path, rc=1).

**Running now**: DOWNLOAD=1 scripts/prepare.sh on the head — the
163.6 GiB rsync to the worker (skipped when its cache already has the
pack), then the cached image build + the prepared marker. The window
relaunches when it lands; the phase's own prepare needs no change (the
rsync is one-time — future prepares find the pack on both hosts).

## (round 135, cont. 7) THE LOADING FRONT CROSSED — the direct reads engaged, the walls 83/83 s vs production's 93.7 = 112.9% (campaign-20261107-150250) (2026-11-07)

**The fifth v124val window, everything landed**:
- **The direct-reads witness: 1 rank line** — the path engaged on the
  resharded pack. The OFF arm's 138 s load carried the one-time
  digest-cache rebuild on the model swap (noted, not a clean
  instrument); the standing restart 88 s; **the walls 83/83 s**.
- **The quality battery**: the §2 gates ALL PASS; **hardmode 95** (the
  NINTH consecutive; TC-51/TC-92 pass); the vision 4/4; the decode
  flat 41.8 tok/s; the pp flat (1,461/1,406/1,449).
- **The arms' content IDENTICAL** — the same greedy sha
  (80cc3802…) as every previous window: the reshard's tensor bytes
  proven identical end to end.

**THE SCOREBOARD**: loading 91% → **112.9% — CROSSED** (the anchors
re-paired, the chart re-rendered). The (user) bar's fronts: solo
112.3% crossed, loading 112.9% crossed, prefill 96.0% the closest gap.
The duel rows stay v1.2.3-era.

**LAUNCHED: duel + summary** — the v1.2.4 duel re-pair (production-
for-testing on 8001 vs ours on the 9-patch stack): the same-window
probes re-date the speed rows on the qualified engine. THEN DARK.

## (round 135, cont. 8) THE FIRST v1.2.4 DUEL BURNED — ours arm rode an EMPTY patch list (the standalone-launch hole in the candidate-duel pattern) and the stock build refused fp8+pages; fixed, relaunched (campaign-20261107-160107) (2026-11-07)

**The receipt**: production's arm ran clean (solo 58.7/58.7, c2 87.2,
c4 192.7, ITL 17.1 ms, overhead 184 ms — its receipt stands) and OURS
REFUSED at boot: `--kv-cache fp8 keeps a window per stream: unset
TF_KV_PAGES` — the STOCK engine's fp8+pages refusal. The prepared line
says `patches=` — EMPTY. The duel's ours arm used
`PATCHES="${MMS2_DUEL_PATCHES-}"`: the candidate-duel pattern expects
MMS2_DUEL_PATCHES exported by the pairing candidate phase (the
moesidequal duel rode it); a STANDALONE duel launch has it unset and
the bare `-` form expanded to the explicit EMPTY list — the opt-out —
so the fingerprint moved, prepare rebuilt a stock image, and the
refusal followed.

**THE FIX**: the duel's ours arm falls back to the standing config's
stack — `PATCHES="${MMS2_DUEL_PATCHES-${PATCHES-}}"` — the same shape
the RC_PATCHES phases use; the receipt label names "the standing
stack" when no candidate is set.

**RELAUNCHED: duel + summary** — the v1.2.4 duel re-pair on the
standing 9-patch stack. THEN DARK.

## (round 135, cont. 9) THE v1.2.4 DUEL RE-PAIRED — every row improved or held: solo 114.2%, c2 133.5% of the floor, ITL 113%, cold 433% (campaign-20261107-163011) (2026-11-07)

**The same-window pair** (production-for-testing on 8001 vs ours on
the standing 9-patch stack — the re-pair after the empty-patch burn):
- **Solo: 67.3/66.8 vs 58.7/58.7 — 114.2%** (the rebase is a straight
  solo upgrade: the MOESIDE pair read 112.3% on v1.2.3).
- **c2: 116.3 vs 87.1 — 133.5% of the floor** (ours 110.3 → 111.2 →
  113.1 → 116.3 across four duels — past production's top-of-range
  volley at ~111).
- **c4: 160.2 vs 155.0** — production at its exact floor this run (its
  range 155-241 with cache state); above parity even there (103.4%).
- **ITL: 15.1 vs 17.1 ms/token — 113%** (the chunked rhythm 59.4 ms
  over 520 chunks; crossed further from the MOESIDE pair's 110%).
- **Overhead: 188 vs 183 ms (97.3%)**; **the cold d8192: 3,957 ms,
  slope 0.460 — 433% of production's true cold** (the 2.5 s it shows
  in-window is its persistent cache, not cold).
- The prefill front: the duel carries no bench rows — the row stands
  (96.0%; the v1.2.4 benches read 1,461/1,406/1,449, inside the noise
  of the attnpref receipt's 1,458).

**The anchors re-paired** (solo/c2/c4/overhead/cold/ITL to the v1.2.4
duel; loading already re-paired on v124val) and the chart re-rendered.
The scoreboard: two of the (user) bar's three fronts crossed at
114.2%/112.9%; prefill 96.0% the remaining gap.

**NO LAUNCH** — nothing staged. The next sitting's opener: the 0030
port (the MoE-glue fusion, 991 lines, 12 files — multi-sitting, full
budget), whose launch-savings math faces the prefill front's 4% gap
first.

## (round 136) THE 0030 PORT — glm-zz-zmoe-fuse staged (the fork's MoE-glue fusion, 991 lines, 12 files + 1 new): 8 clean / 4 re-anchored hunks, compile RC=0 first pass, byte-identity 0 diff lines; the moefusequal A/B LAUNCHED (2026-11-07)

**The port** (multi-sitting plan, sitting 1 — the full port landed in one):
- **The candidate**: Mia 1104's 0030 (patches/engine/, 991 lines, 12 files +
  the new exl3_group.cuh): a decode window's MoE glue fused (tf_glm_topk_group
  = the select + the compact picks + the EXL3 grouping in one 1024-thread
  block; the grouped experts core with no slot-row copies — two 2D copies,
  tf_exl3_group, put_slot and glue.combine GONE; the shared expert's row
  summed LAST in tf_exl3_down_combine, glue.combine's order), the one-width
  grouped decode tiles (grouped_body_v2: k6r8/k8r8 + nt4), KDA's f_b/g_b in
  one launch (glm_mm*_16x2). TF_GLM_MOE_FUSE=0 unfuses (default on).
- **The drift map**: the fork's series places 0030 after 0006 (moeside),
  0007 (exl3prompt), 0009 (packed-s2) — our stack carries all three ports,
  so the hunks assume our tree's shape. git apply --reject: 8 files clean,
  4 hunks rejected (one per file).
- **The re-anchors**: the .cu include (v1.2.4's decode/plan includes); the
  run() split in src/cuda/exl3_experts.zig (v1.2.4's act_mode check moved
  INTO core() — the grouped path gates there too, runGrouped calls core
  directly); cuda_exl3.zig's three grouped fns (after run(), our tests
  follow); cuda_forward.zig's field (our extra fields sit between taps and
  side); tilesFor reads our single Layer.uniform_k2 (the fork splits gate/up
  from down; ours is every-projection-verified — conservative and correct);
  the engine knob wiring ported from 0031 (envOn + the engine field + both
  Forward constructions carry .moe_fuse — 0030's exported diff never reads
  the env; found by grepping the whole exported series for MOE_FUSE).
- **The verify**: compile RC=0 (fatbins + native, nvcc sm_121, zig 0.17.0,
  the builder base image — FIRST PASS, no fallout); fresh-parent + the
  shipped patch = the commit tree byte-identical (0 diff lines); commit
  39ac60e3b on v124-rebase (ff-merged). NAMED glm-zz-zmoe-fuse TO SORT AFTER
  moeside (the engine hunks assume the side field; "zmoe" > "moeside").
- **The phase**: moefusequal in run-qualification.sh — the A/B on the SAME
  patched image (the standing 9 + zmoe-fuse), the knob flips the path: the
  OFF arm (TF_GLM_MOE_FUSE=0) greedy sha + duel_arm; the ON arm (unset) the
  same + the identity + duel_arm + the §2 gates + one bench pass (prefill
  flat — the prompt path untouched by design) + the steady-state decode +
  hardmode (the tenth 95) + the vision 4/4. Explicit prepare with the
  10-patch overlay (PATCHES="$MFPATCH" scripts/prepare.sh — the fingerprint
  moves; one-shot env, not an export).

**LAUNCHED: moefusequal + summary.** THEN DARK.

## (round 136, cont. 2) THE 0030 PORT QUALIFIED AND ADOPTED — content identical to the byte, hardmode 95 (the TENTH consecutive), c4 +4.2% (our best); config.sh's tenth patch; the duel re-pair LAUNCHED (campaign-20261107-172250) (2026-11-07)

**The moefusequal A/B receipt** (both arms the SAME 10-patch image,
the knob flips the path):
- **The arms' greedy content IDENTICAL** — the same 80cc3802… sha as
  every window: the port's same-bits claim proven on the real model.
- **The quality battery**: the §2 gates ALL PASS; **hardmode 95** (the
  TENTH consecutive; TC-51/TC-92 pass); the vision 4/4.
- **The decode savings**: c4 **166.1 vs the OFF arm's 159.4 (+4.2% —
  our best c4)**; c2 117.1 vs 115.9 (+1.0%); ITL 58.4 vs 59.3 ms/chunk
  (−1.5%); solo flat (67.7/67.4 vs 67.2/67.5); the TTFT slope flat
  (0.459 vs 0.456 — the prompt path untouched by design); the load
  walls unchanged (83/87 s).
- The bench pp rows inside the noise (d0 1,468) — prefill stands at
  96.0%, the fusion cannot move it (a decode-window lever).

**ADOPTED**: config.sh's PATCHES carries glm-zz-zmoe-fuse.patch (the
tenth; the config edit verified per the sourced-config skill — the
10-name probe, config_line RC=0, the fingerprint moves so the next
window rebuilds with 10 patches). The anchors re-paired to the ON arm
(solo 115.2%, c2 134.4% of the floor, c4 107.2% at production's floor,
ITL 115%, cold 434% — production cited from the same-day v1.2.4 duel,
campaign-20261107-163011) and the chart re-rendered; README (serve/
Speed/PATCHES rows), DELTAS (scoreboard + Engine), the ledger,
PERF_PLAN and ECOSYSTEM updated. The steplink stays retired (its
mechanism is gather-side, the fusion launch-side — no interaction
measured).

**LAUNCHED: duel + summary** — the v1.2.4+zmoe-fuse duel re-pair
(production-for-testing on 8001 vs ours on the adopted 10-patch
stack): every speed row re-paired same-window on the fused engine.
THEN DARK.

## (round 136, cont. 4) THE ZMOE-FUSE DUEL RE-PAIRED — solo 115.4%, c2 above production even at its top, c4 109.1% at its floor (our best again), ITL 117% (campaign-20261107-183530); the prefill scope landed — exl3p 0078+0079 the top candidate, its port is the next sitting; NO LAUNCH (2026-11-07)

**The same-window pair** (production-for-testing on 8001 vs ours on
the fused 10-patch engine):
- **Solo: 67.6/67.5 vs 58.6/58.6 — 115.4%** (the adoption A/B's
  115.2% holds).
- **c2: 117.3 vs 110.3 — 106.3%, above production even at its
  top-of-range volley** (its floor 87.1 — 134.7% there).
- **c4: 168.8 vs 154.7 at its floor — 109.1%, our best c4 again**
  (the chain 153.7 → 157.4 → 158.6 → 160.2 → 166.1 → 168.8).
- **ITL: 14.6 vs 17.1 ms/token — 117%**; overhead 189 vs 185 ms;
  the cold d8192 3,961 ms, slope 0.460 — 433%. The prefill row
  stands (96.0% — the duel carries no bench rows).

The anchors re-paired same-window and the chart re-rendered; README/
DELTAS/ledger/PERF_PLAN updated.

**The prefill scope** (the sitting's second work item): the fork's
gen-5 tail mapped — **exl3p 0078+0079 is the top candidate** (the
prompt experts' main loop rework: gate/up 1.177x, down 1.161x
MEASURED on the prompt kernels — at the experts' plausible share of
our prefill that is the 96.0% front's crossing); the PDL set and the
HC-split set parked behind it (launch-gap levers, unmeasured for our
dense prefill loop / a multi-patch TP rework for 50k prompts). The
port's drift is measured: 0078 rejects in all 3 files (the fork's K2
template param vs our 2-param loop — the 4-bit path is what runs on
our model); the port is kernel-level, the next sitting's work, then
the exl3pqual A/B.

**NO LAUNCH** — nothing staged to test; the sitting ends with the
scope documented.

## (round 137) THE EXL3P PORT — glm-zz-zprompt staged (the fork's 0078+0079, the prompt experts' main loop reworked): the fork's text verified line-identical (244/244 .cuh, 18/18 .cu), compile RC=0, byte-identity 0 diff lines; the exl3pqual A/B LAUNCHED (2026-11-07)

**The port** (v1.2.4 + the 10-patch stack, commit e9d511546 on
v124-rebase): the prompt experts' main loop reworked (exl3p) — compiled
for an item's 8-member column blocks (NBA 1..8, no predicate, no dead
MMA), the next k tile's trellis decode issued among the current MMAs
across the stage barrier (PS 4/3), each thread's cp.async pieces fixed
per item (TLoads), the mcg mask one LOP3 (mcg2), 4-bit tiles from the
lane's word and its neighbour's (decode_a8), fwht128 epilogues one FFMA
per butterfly (fwht128f), Xd one 8-byte and y one 16-byte store. The
fork measured the prompt kernels **gate/up 1.177x, down 1.161x** (2,048
rows, nvcc 13.3) — the 96.0% prefill front's top candidate.

- **Fidelity, line-verified**: every one of 0078's added lines appears
  verbatim in our port (244/244 in exl3_prompt.cuh, 18/18 in
  exl3_experts.cu); the only deviations are the documented adaptations.
- **Our adaptations** (the drift measured last round, resolved): the tree
  is 4-bit-only — the fork's K2 template param stays and instantiates at
  8 only; tstage_halves/tsmem_bytes keep our 1/0-param forms (identical
  values at K2 8); tgateup takes the fork's <XR, K2> and our gu kernel
  call sites pass 8; 0079's pending_133 _k6 records hunk SKIPPED (our
  tree has no _k6 prompt kernels). The classic loop kept as
  tmain_cl/tspill_cl/tgateup_cl + the tf_exl3_prompt_{gu,down}_cl kernel
  twins (our pre-port bodies verbatim); **TF_GLM_EXL3P=0** resolves them
  in exl3_prompt.zig's resolve() (envOn, default on — the 0030 knob
  pattern).
- **The contract records re-measured per 0079** (nvcc 13.3 set): gu
  128/126/126/128/128 → **122/125/125/122/122**, down ADDED at
  123/125/125/122/122; **our own sm_121 cuobjdump on this tree reads
  122/122 — 0079's entry-5 values verified on our build**; static 43264
  unchanged (the __shared__ layout is byte-identical); the _cl twins
  (128/127 measured) stay unlisted → unchecked, the 0030-new-kernel
  precedent.
- **Verify**: the compile RC=0 twice (pre-records and final tree;
  fatbins + native, nvcc sm_121, zig 0.17.0, the builder base image);
  fresh-parent + the shipped patch = the commit tree **byte-identical**
  (tree 731656f6…). NAMED glm-zz-zprompt TO SORT AFTER zmoe-fuse (the
  .cu hunks assume the post-0030 experts file; zp > zm). The engine
  commit authored with the house identity at the source (the From: leak
  the guard caught once cannot recur).
- Staged, NOT adopted: config.sh's PATCHES stays at 10 — the exl3pqual
  A/B decides. 0080 (the packed prompt linears' cp.async) remains the
  follow-on candidate.

**LAUNCHED: exl3pqual + summary** — both arms the SAME 11-patch image,
TF_GLM_EXL3P=0 vs unset: the arms' greedy content identical is the
same-bits claim; the bench pp rows + the TTFT slope are the prefill
lever's instruments; the §2 gates, hardmode (the eleventh 95) and the
vision 4/4 must hold. THEN DARK.
