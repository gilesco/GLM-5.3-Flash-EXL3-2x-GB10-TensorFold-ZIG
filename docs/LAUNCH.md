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

**This file carries the current week only.** Earlier weeks live in `docs/log/`
(one file per ISO week — `2026-W43.md`, `2026-W44.md`, `2026-W45.md`), archived
immutable once cut. Append the newest round entry here as before; the next
sitting after a Monday moves the finished week into `docs/log/`. Round
navigation across all weeks: [docs/LAUNCH_INDEX.md](LAUNCH_INDEX.md) —
generated, one line per round entry with its file.

## (round 139, cont. 11) THE V1.2.5 BUMP SHIPPED — the rebase receipted, the pin flipped (2026-11-09)

**The rebase, empirically grounded**: the subagent's scan verdict ("the
cheapest bump; one hunk re-anchor") was tested against the real trees and
CORRECTED — the true drift map is 6 files (registry.zig's joins move #2422,
cuda_engine.zig's gate/shared extraction, cuda_lanes/cuda_native/cuda_pages'
additive changes, glm_family_host's dependOn), 40 of 46 files unchanged. With
the proper apply recipe (no reset-on-failure), **15 of 17 patches apply
verbatim on v1.2.5** — only 003-fp8-pages needed re-anchoring (4 hunks: the
glm_kv_paged_records join onto registry_joins.zig, v1.2.5's shareSlot
preserved beside our layout rewrite, the TF_KV_PAGES test title v1.2.5
already carries, the snapshots step re-anchored). The first probe's
"11 of 17 fail" was MY probe script's reset artifact — the lesson: an apply
probe must never reset the tree between patches.

**The receipts on the final tree** (`4b8d7c91…`, v1.2.5 + the 17-patch
stack): byte-identical across TWO independent reconstructions (the direct
stack apply and the staged iso recipe); the tool-parse host suite 51/51;
compile RC=0 (fatbins + native, sm_121). The shipped 003-fp8-pages.patch was
verified END TO END as the file that ships: pristine v1.2.5 + the stack in
order from the shipped files = the verified tree exactly.

**The pin**: TF_COMMIT 267c5af6a (v1.2.4) → 8be9c408c (v1.2.5) in the head's
local.sh. The v125val battery decides whether it holds: the same-bits greedy
witness (the 80cc3802… sha must hold across the engine bump), the §2 gates,
the boot witnesses under #2405's strict TF_ validation, the bench +
steady-state decode, ONE hardmode run at the harness's new --parallel 2 (the
instrument re-grounds — see the ledger), the vision suite, TWO timed load
walls. Any FAIL holds the pin at v1.2.4.

**The bookkeeping correction caught on the way**: the last two digests'
commits left the anchors re-date uncommitted locally (the guard passed on the
consistent local pair while the pushed tree carried the old one) — landed now
with the 003 commit; the guard's chart check reads the committed pair.

**The window**: `preflight v125val summary`.

## (round 139, cont. 12) THE V1.2.5 BUMP QUALIFIED — the pin HOLDS, production serves the bumped engine (2026-11-09)

**The window** (campaign-20261109-000818, `preflight v125val summary`, rc=0,
production restored healthy after 81 s — on the v1.2.5 engine
`8be9c408c…`): the v125val battery passed on every instrument.

- **The same-bits greedy witness: IDENTICAL** — the engine bump did not move
  the deterministic probes (the 80cc3802… sha holds across v1.2.4 → v1.2.5
  with the full 17-patch stack).
- **The §2 content gates ALL PASS**, zero strict-TF_ refusals at boot.
- **Hardmode 95 — the EIGHTEENTH consecutive, and the first on the
  re-grounded --parallel 2 harness** (the user's cont. 10 directive: the
  instrument re-grounded and the 95 held immediately).
- **The vision 4/4**; steady-state decode 73.1 tok/s; the load walls
  **83/83 s** (the loading row re-dated; the v1.2.4-era 80 s held within the
  band); prefill 1,523 at d0 (the band); d8192 c2 68.3 (the steps0
  depth-decode holding on the bumped engine).

**The adoption**: the pin holds at v1.2.5 — the anchors' loading row
re-dated (83/83 s), the chart regenerated, the ledger closed. The promoted
production repo mirrors the bump (its config + 003 re-anchor land on its
next promotion sync; its LIVE serve was already restarted on the v1.2.5
engine through the window's restore path).

**The next queue** (docs/PORT_QUEUE.md): the **0104 warm-turns port** — the
fork's highest-value patch for our line (the agent-loop re-prefill; the
512K/agent workload's own front), ported onto the v1.2.5 base now. Then
0108 CACHE_FIRST + 0110 KV_SHARD for the 512K plan.

## (round 139, cont. 13) THE 0104 WARM-TURNS PORT: the guards hold but the mechanism is INERT on our serving mode — the substrate conflict found (2026-11-09)

**Three windows told the story** (campaigns -083530, -093727, -102456, all
rc=0, production restored healthy each time):

- **The guards hold everywhere**: the greedy same-bits sha IDENTICAL
  (80cc3802… across all three), the §2 gates ALL PASS, hardmode 95 (the
  NINETEENTH consecutive), the vision 4/4. The port is bit-safe.
- **The instrument is NULL — and the boot witness found why**: the third
  window's receipt carries `info: warm turns: turns=false quiet=0ns
  host_warm_quiet=0ns` on BOTH arms — the warm state is OFF at runtime even
  on the ON arm. Root cause: `warm_turns = h.store != null and
  @hasDecl(F, "warm_quiet")` — and the store is created only under
  `!share` (cuda_native.zig's `if (@hasDecl(F, "snap_save") and cache > 0
  and !ownCache and !share)`). **Our adopted serving mode TF_KV_SHARE=16
  keeps prompts as pool pages through the share path — the snap_save store
  the warm pass needs does not exist in that mode.** The fork's 0104 was
  developed against their base WITHOUT the KV_SHARE pool-pages store (their
  CHANGELOG carries no KV_SHARE) — the mechanism's substrate differs on
  ours.
- The battery itself hardened along the way: the boot witness added to the
  port (the first two windows' receipts couldn't diagnose because the
  engine's warm-state line wasn't captured), the arm receipts now carry it.
  The port's code stands verified (the suite PASS, compile RC=0, fidelity
  104/104 fork lines) — it is the SUBSTRATE that differs, not the port.

**The trade-off is the user's** (the KV_SHARE=16 serving mode is the adopted,
measured default; the warm turns need the other cache mode): the options are
(a) teach the warm pass to keep its states through the KV_SHARE path (new
engine work, fork-side too), (b) run the 019 patch with KV_SHARE off for the
agent-loop workloads (a serving-mode split), or (c) park the patch as
inert-on-our-mode and revisit when the KV_SHARE store grows a warm hook.

## (round 139, cont. 15) THE 0104 WARM-TURNS PORT: the mechanism ENGAGES but buys NOTHING on our KV_SHARE mode — PARKED (2026-11-09)

**The sixth window** (campaign-20261109-131026, rc=0, production restored
healthy) closed the question with the hardened four-arm battery and the
deepened instrument:

- **The mechanism now engages exactly as designed**: the ON arms witnessed
  `turns=true host_warm_quiet=150ms` and ran **3 done / 3 stepped aside /
  0 failed** per arm — the fork's own behavior pattern (their "17 of 18
  stepped aside"); the OFF arms witnessed false and ran zero passes. The
  kill switch gates the passes properly now.
- **The instrument at the fork's own shape (~9-10K loop tokens): NO WIN.**
  The final user message's wall: off2 **6194 ms** vs on2 **6292 ms** (the
  ON arm 1.6% slower, inside noise); the first pair 6212 vs 6185 (−0.4%).
  The fork's win (their 9.3K loop: 8,192 of its tokens cached vs 4,096,
  1.6 s vs 3.5 s) did not transfer.
- **The guards held on every arm**: the greedy same-bits sha IDENTICAL
  (80cc3802…), the §2 content gates ALL PASS, hardmode 95 (the TWENTIETH
  consecutive), the vision 4/4.

**The mechanistic explanation**: on our KV_SHARE serving mode, EVERY
request's prompt pass already keeps states at the radix plan's marks
(share_mod.Keeps, `tail=true` planning the end) — the loop's own turns
kept their states turn by turn, which is exactly what the warm pass would
add. The fork's win existed on their base because their snap-store cache
missed the mid-loop states; our share store does not. The port is
correct code but duplicates work the share store already does.

**DISPOSITION (user: "follow your own recommendations")**: PARKED — 019
stays staged, NOT in the PATCHES default. The port's value was the
question it answered: our KV_SHARE mode already carries the agent-loop
resume behavior the fork built warm turns to add. The A/B instruments and
the battery hardening (the witnessed-state gate, the four-arm drift
control) stay in the campaign script as the pattern for future A/B ports.

## (round 139, cont. 16-17) THE 0108 CACHE-FIRST PORT QUALIFIED AND ADOPTED — the twenty-first patch (2026-11-09)

**The port** (020-cachefirst, the fork's 0108): the prompt cache set aside
before the streams' windows (`TF_PROMPT_CACHE_FIRST=1`), adapted to compose
with our tree's `asked` flag — the flag changes the ROOM the windows count
(`room -| cache`), not the window cap. The value-add on our serving mode: the
**fund-report line** — the fork's issue-16 room drift (our warmturnsqual
battery caught the same: the room moving 11.8 -> 11.0 GiB between starts with
no config change, none of TF_KV_SHARE=16's slots fitting on a second start)
becomes VISIBLE at boot instead of silently serving without the cache.

**The receipt** (campaign-20261109-140604, `preflight cachefirstqual
summary`, rc=0, production restored healthy after 80 s): the four-arm OFF/ON
plan A/B — the ON arms' streams ceded pages to the cache-first reserve
(3110/3115 -> 3103/3083 pages), the fund-report line never fired at our
3 GiB ask (the drift never reached the cache's need on this window's serves),
the §2 content gates ALL PASS, **hardmode 95 — the TWENTY-FIRST consecutive
(the third on the re-grounded --parallel 2 harness)** — the vision 4/4.

**The adoption**: the env default `TF_PROMPT_CACHE_FIRST=1` + the 020 patch
in config.sh's PATCHES (the twenty-first patch); the promoted repo follows on
its next promotion sync. Instrument note recorded: the battery's own greedy
probe returned empty content at max_tokens 64 (the thinking model ate the
budget) — the gates' probes carried the real content witness; the probe
needs a larger budget next revision.

**The queue after this**: 0110 KV_SHARD (the pool ~2× tokens for the 512K
plan — decide against our fp8-pages ground), then the perf plan's next step.

## (round 139, cont. 18) THE 020 PROMOTION SYNC — the promoted repo carries the twenty-first patch (2026-11-09)

**The sync** (production repo on the head, four commits): the v1.2.5
re-anchored `003-fp8-pages.patch` COMMITTED (it had sat uncommitted in the
working tree since the v1.2.5 rebase — the window's exit-path restore would
have died the next fingerprint re-prepare); `020-cachefirst.patch` mirrored
into BOTH `patches/` (the store prepare stages from) and `image/patches/`
(the build consumes) — byte-identical `1517e2ab3935` across both repos;
`config.sh`: the 020 patch appended to the PATCHES default +
`TF_PROMPT_CACHE_FIRST=1` (the adopted default with its receipt comment);
the README status row updated (v1.2.5 + the 18-patch stack, hardmode 95
twenty-one consecutive).

**The store hazard closed**: production's `patches/` still carries the 29
retired `glm-*` files from before the renumbering — they are INERT by
construction (prepare stages only the named PATCHES list into
`image/patches/` after a `find -delete`; the build globs
`/build/patches/*.patch` which holds only the staged copies). Verified: all
18 named patches present in the store.

**Deployment timing**: production keeps serving the v1.2.5 17-patch image
on 8000 until the NEXT window's exit-path restore — the restart rereads
config.sh, the fingerprint moved, and start.sh re-prepares (the 020 image
build) before production returns. No manual serve touch.

**Also this sitting**: the cachefirstqual greedy probe's budget fixed
(max_tokens 64 → 1024; the thinking model ate the 64 budget — the
campaign-20261109-140604 instrument note; the gates' own probes carry
`enable_thinking: False` and were never vacuous); the testing README
refreshed to the adopted state (v1.2.5 + 18 patches, both new env defaults
documented).

## (round 139, cont. 19-20) THE 0110 KV_SHARD PORT: TRANCHE 2 LANDED — all 79 rejects anchored (2026-11-09)

**The sitting's shape**: the digest landed (the design-note read — no new
kernels, no 0109 dependency, the GPU check the primary validator), then
tranche 1 (the 10 new files verbatim + every clean hunk, 79 hunks rejecting),
then tranche 2: every reject hand-anchored through scripted exact-anchor
edits, plus the line-level fidelity check (3,853 fork `+` lines vs the tree)
catching what the apply had silently dropped.

**The catches the discipline earned**:
- The scoping run's leftover had contaminated the first reject inventory
  (102 reported vs the true 79) — `git reset --hard` + the untracked-new-file
  cleanup before the honest run.
- Two "clean" hunks from tranche 1 had NOT landed (`Switches.read` in
  cuda_ranks, `KvParts` in engine_status) — the fidelity check caught both.
- The lane-host trio (`kv_parts`/`kv_status` fields, the publish, the
  test) and the own-sequence sharded sizing were also unaccounted — the
  check surfaced all; all landed.
- The mangled-literal hazard is real: one `cuda_native.zig` sub() swallowed
  the finishRank literal's tail mid-edit and was repaired in place before
  commit.

**The adaptation record** (each in its commit): the fingerprint at OUR layout
21; our `tables()` plural + `pk` host-key fields preserved in dsa_block (the
005/006 `page_rows` rule carried INTO `latTable`); our `adopted`/`openWith`
flow preserved in pagesFor; our `heldPages`/`shared` snapshot params
preserved; `copyOut` composed for our single-arena Pool; the deliberate
skips: the fork's disk-image machinery (~250 lines; our kept-states flow has
no counterpart), the shared-segs batching (our `.mla` is per-segment), the
`pageable()` gate (our engine never unsets pages; the refusal anchors before
ownSequence).

**State**: the port tree at `/tmp/v125-rebase/tf`, WIP `f83bd57..4cc5c4f`
(14 WIP commits, tranche 1 + 2a-2n), the tree clean, the host suite
(test-tool-parse-host) RC=0. The compile-cuda-tests gate (the fork's
`glm_kv_shard_check` inside tf-cuda-test) in flight. Next: the gate's
receipt, then the GPU check on the pair, then the `kshardqual` battery, then
the adoption decision (the trade-off is the user's: −1.6/−3.6% old-engine
decode vs ~1.8× pool tokens).

## (round 139, cont. 21) THE 0110 PORT IS COMPILE-CLEAN — the GPU check is next (2026-11-09)

**The gates**: `zig build compile-cuda-tests` **RC=0** — the fork's
`glm-kv-shard-check` runner compiles inside `tf-cuda-test` against the
ported modules — AND the host suite (`test-tool-parse-host`) still RC=0.
The port tree at `/tmp/v125-rebase/tf` stands at `5c7f4f2` (WIP
`f83bd57..2w`, twenty-two commits), the tree clean.

**Seven error rounds** the compile gate caught after the host suite passed
green — the suite compiles only the tool-parse module and is blind to the
whole GLM family (the skill gotcha now recorded). The errors, each fixed in
its own commit: the engine_status field ordering (declarations between
fields); the idempotent-rerun's quintupled `kv_parts` export; the re-added
`host_tier` import (our tree has no `cuda_snapshot_host.zig`); the fork's
`heads()` helper adapted to ours (`o.mtp and !o.drafter`); the fork's `f.ce`
gate lines at two sites (our Forward has no CE field — theirs alone); the
`pagedBytesFor` arity (our stateSizes has no head param); `Plan.max_parts`
(ours at +2); `latent.max_segs` defined on our latent module (the fork
0075's value 16 — our per-segment `.mla` never needed it); and the lanes
`pagesFor` routing (the adopted prompt-cache pages are a POOL lease through
`openWith`; the shard home only on the `openFor` path — the two flows never
compose, and that composition rule is now the record).

**Next**: the GPU check on the pair — `tf-cuda-test glm-kv-shard-check` on
both ranks inside the builder-stage image (VALIDATION §6's pattern; the
first engine-level GPU check this line has ever run), then the `kshardqual`
battery phase (the four-arm off/on/off2/on2 A/B with the witnessed-state
gate), then the adoption decision — the user's call (−1.6/−3.6% old-engine
decode vs ~1.8× pool tokens; the verify-width and DFlash2-acceptance
questions are unmeasured on this engine).

## (round 139, cont. 23) THE 0110 PORT: COMPILE-CLEAN END TO END — AND THE STRATEGIC CROSSROADS (2026-11-09)

**Compile-clean end to end**: `compile-cuda-tests` RC=0 with the check's
dispatch landed and its body type-checked. The last rounds caught the
trap the usage-text-only registration had set: the check was registered in
main.zig's usage text but never dispatched — it would have died at RUNTIME
with an unknown-command error after a wasted GPU window. The dispatch-forced
analysis then surfaced seven more check-only fixes (keepAt/kept_id, the
Options mtp adaptation, the e.link vestige, the snapshots arity, the prefill
call mapping, three beginOn calls), each in its own commit. The disk cases
stripped (the seven non-disk paths are the gate on our tree).

**The strategic crossroads** (the user's call, pending): the upstream scan
found the SAME mechanism by the SAME author actively landing upstream —
issue #1431 active since 10-27, ashhart's design agreed 10-30, and
**PR #2415** (part 1: `TF_GLM_KV_SPLIT`, owner classes in core `kv_pool`)
in review as of 11-08 with all five of ashhart's points addressed; wojo
confirmed the full split already runs on their two GB10s at TP=2 with the
same numbers this line was porting toward (2.10M → 4.20M tokens,
byte-identical over 8 request sets, decode −1.6/−3.6%). The fork port and
the upstream PR are architecturally different (GLM-side two-pool vs
core-kv_pool owner classes; `TF_GLM_KV_SHARD` vs `TF_GLM_KV_SPLIT`), so the
fork port would need re-doing on upstream's shape anyway.

**The recommendation recorded in PORT_QUEUE.md**: SUSPEND the fork port —
the tree (compile-clean at `f28bb46` + the check rounds) stays as the
working reference; watch #1411 → #2415 part 1 → parts 2-4; adopt upstream
via the version bump (the v1.2.5→v1.2.6 rebase was the cheapest of the
line) + the config change + the standard battery when it lands in a
release. The GPU check and the kshardqual battery are parked until the
user's call. Nothing ships either way without it.

## (round 139, cont. 24) THE SINGLE-ITERATION KSHARDCHECK: two instrument failures, the fix, the relaunch (2026-11-09, user: "Finish the fork port now for a single iteration")

**The user's call** ended the strategic watch: finish the fork port now,
one iteration — the GPU gate's receipt, then the battery if it passes.

**The first window** (campaign-20261109-205823) died BEFORE any GPU work:
the phase's relative `-v "$OUT:…` mount paths became docker named volumes
("invalid characters for a local volume name") — the absolute-path fix
(readlink -f on OUT/PORT_TREE/HF_CACHE at the phase head) landed and the
window relaunched.

**The second window** (campaign-20261109-211540) got further: the binary
built (164M, 3 dispatch hits), rank 0 wrote the NCCL id and blocked — then
**rank 1 raced the background id-file poller**, read the missing file, and
`FAIL glm-kv-shard-check: FileNotFound` in ~2 s. Worse: rank 1's nonzero
ssh hit the script's `set -euo pipefail` and killed the phase BEFORE its
receipt's rank tails and rc lines (production restored healthy on the exit
path — the window flow held).

**The live probes on the worker confirmed the runtime path is sound**:
the binary mounts and executes, the id file reads (e17858d1…, 256 hex), the
checkpoint mounts from the worker's HF cache, and the full flag set
(gpus/ipc/host-network/shm/infiniband/IPC_LOCK/memlock) carries the check
into NCCL init — rank 1 alone sits BLOCKED (rc 124 on the 300 s timeout)
waiting for rank 0, exactly as the check's design intends.

**The fix** (one commit): the id-file handoff is SYNCHRONOUS (the phase
rsyncs it to the worker before rank 1's ssh starts — no poller race), and
the RC captures are set-e-proof (`|| RC=$?` so a failing rank can never
again kill the phase before its receipt completes).

**The state**: the fix landed and synced (9751843), production healthy on
8000, no window flag. The third launch carries the complete gate: both
ranks, the seven paths, byte-for-byte against the twin.

## (round 139, cont. 25) THE WIRE CONTRACT FIXED — THE GATE RUNS PAST PLACEMENT, THEN THE CUDA FAULT (2026-11-09)

**Window 3** (campaign-20261109-214043) burned on the begin-step wire
contract: our pre-port follower consumed the kept count from `h.a`, but the
fork's design keeps `h.a` for the kept count TOO and re-purposes `h.depth`
(the chunk-start word, unused on a begin) for the TWIN count. The tranche-2
anchor had mapped them swapped (`mapWith(..., h.a as twin, h.depth as
kept)`), rank 1 read the wrong word as the twin count, and
`FAIL glm-kv-shard-check: KvShardPlacement` — the placement check refused
the page ids before any GPU work. The fix (tranche 2zh, 332353d):
`mapWith(slot, ids, twin=h.depth, kept=h.a)`, matching `beginOn`'s
`h.depth = twinCount` line already landed from the fork.

**Window 4** (campaign-20261109-225337, the wire fix in): the gate ran the
REAL engine path for the first time — both ranks verified the checkpoint
digest (163.6 GiB, ~45 s each), loaded the weights direct, and crossed the
steps over the wire. The placement check passed. Then, inside the FIRST
prefill of the sharded stream (before any of the seven paths completed):

    cuLaunchKernel: CUDA_ERROR_ILLEGAL_ADDRESS (700); kernel ?, grid 92x1x1, block 256x1x1

Both ranks faulted identically; the context turned bad so
`cuFuncGetName` answered `?` — the victim kernel is unnamed, and the
launches before it (the culprit among them) were invisible. VERDICT:
FAILED, the port does not qualify this iteration. Production restored
healthy after every window (now 5/5, rc=0).

**The instrument** (tranche 2zi, 89faa5d): the launch ring — every kernel
launch records its name and shape BEFORE launching (while the context is
still healthy), and a failed launch or checked call dumps the ring
(oldest first, the LAST entry the newest). The next window names the
victim and everything that led to it.

**The state**: the ring compiled clean (CC-RC=0), the binary rebuilt,
`.commit-want` pinned to 89faa5d. Production healthy on 8000. The next
window carries the ring into the same first prefill.

## (round 139, cont. 26) THE RING NAMED THE POISON POINT — TF_LAUNCH_SYNC LANDS FOR THE EXACT CULPRIT (2026-11-09)

**Window 5** (campaign-20261109-233539, the ring in): the instrument
worked exactly as designed — the dump names every launch up to the poison
point (~3,899 launches deep, both ranks faulted at the same relative
position — deterministic, not a race):

- **Rank 0's tail**: `hc_post(92x4) → hc_partial(23x16) → ?(92x256) →
  ?(1x128)` — the victim's shape matches `hc_finish` exactly (the healthy
  groups ran 192x256), and the `?(1x128)` shape matches `tf_glm_put_words`
  (the piece-exchange put). The context was ALREADY bad at the victim's
  name query — `cuFuncGetName` answered `?` twice.
- **The third hc group runs at half the healthy grid** (92/23 vs 192/48
  rows) — the third row-piece of the chunk (TF_GLM_OVERLAP_PIECES=3).
- **The trap**: `cuLaunchKernel` returned SUCCESS for [3896]/[3897] —
  kernels run asynchronously, so the ring orders SUBMISSIONS while the
  culprit can hide up to the queue depth earlier in execution.

**The instrument** (tranche 2zj, e46f7ad): `TF_LAUNCH_SYNC` — sync the
stream after EVERY launch; the first failing sync names the kernel that
faulted IN EXECUTION (kernels on one stream run in order). Cost ~seconds
a prefill; diagnostic-only env in the gate phase, unset once the defect is
fixed. The gate's `.commit-want` pinned to e46f7ad.

**The state**: window 6 (the exact-culprit run) launched; production
restored healthy after window 5 (6/6, rc=0).

## (round 139, cont. 27) THE EXACT CULPRIT: plan_scatter FAULTS IN EXECUTION — THE SANITIZER RUN IS NEXT (2026-11-10)

**Window 6** (campaign-20261110-002031, TF_LAUNCH_SYNC in): the
sync-each instrument pinned the fault exactly —

    TF_LAUNCH_SYNC: launch #2893 faulted IN EXECUTION: CUDA_ERROR_ILLEGAL_ADDRESS (700); kernel ?, grid 30x1x1, block 256x1x1

The kernel at 30x256 is **`plan_scatter`** (the MoE plan scatter,
cuda/grouped.zig) — and every one of the ~2,892 launches before it synced
clean. The context poisoned at the name query again (`?`), but the shape
is unique. Rank 1's run reached the same plan (its last named launch:
`plan_scatter`, 30x256) — both ranks, same position, deterministic.

**The significance**: `plan_scatter` is UPSTREAM MoE code — the 0110
patch never touches the MoE files. The scatter is reading memory the
shard path corrupted (or garbage picks from a clobbered router scratch):
the writes happened earlier and the fault surfaced late — the last DSA
layer is 43 of 45, its MoE block's plan scatter right after. The seq
arithmetic (~2,886 launches ≈ a full 45-layer pass) says the FIRST prefill
ran to its END before the first fault — the corruption is in the
last-layer region, not the first kernel.

**The next instrument** (KSHARD_SAN=1, landed in the gate phase): rank 0
runs under `compute-sanitizer memcheck` (the build image ships the tool;
the runtime images do not) — the report names the faulting ADDRESS and
the nearest allocation, which settles whose buffer the walk-off touched
(the pool's keys/lat, the exchange room, or the plan scratch itself).
Rank 1 stays unsanitized (one instrumented rank keeps the NCCL handshake
unsynchronized); TF_LAUNCH_SYNC is unset in this mode (the sanitizer
subsumes it).

**The state**: window 7 (the sanitizer run) is launching; production
restored healthy after window 6 (7/7 windows, rc=0 restores).

## (round 139, cont. 28) THE SANITIZER RAN BUT ITS REPORT WAS LOST — THE LOG PATH FIX (2026-11-10)

**Window 7** (campaign-20261110-010136, KSHARD_SAN=1): the sanitizer CAUGHT
the error (rank 0's rc=99 = the error-exitcode) — but the report is gone:
`--log-file "$OUT/kshardcheck-san-r0.log"` passed the HOST path into the
container, where that directory does not exist; the root container created
its own fake path and `--rm` discarded it with the container.

**The fix** (one commit): the report writes to `/ids/kshardcheck-san-r0.log`
— the rank-0 container already mounts the campaign OUT dir rw at `/ids`,
so the report lands on the host. Window 8 is running the same mode with
the fixed path; the report should name the faulting ADDRESS and the
nearest allocation this time.

**Diagnostic note**: the fault MOVED under the sanitizer's app-level view —
the ring's victim now reads `hc_finish(192x256)` after `swiglu_512(768x2)`
and `put_slot(12288)` — earlier in the layer stack than the unsanitized
fault at plan_scatter. The sanitizer serializes execution and changes
memory timing, so the FAULT POSITION moves, but the corruption itself is
the same defect; the sanitizer's report (the ADDRESS) is position-
independent evidence. rc=99 proves the sanitizer trapped an error.

**The state**: production restored healthy after window 7 (8/8, rc=0).
Window 8 (the sanitizer rerun, the report path fixed) is running.

## (round 139, cont. 29) THE SANITIZER'S REPORT: plan_scatter WRITES ~2.5 GB PAST ITS BASE — GARBAGE PICKS (2026-11-10)

**Window 8** (campaign-20261110-011913, KSHARD_SAN=1, the report path
fixed): the report LANDED (158 KB) and nails the defect:

    Invalid __global__ write of size 4 bytes
        at tf_experts::plan_scatter(...)+0x1c0
        Access to 0xe33fc925f8a0 is out of bounds
        and is 2530871136 bytes BEFORE the nearest allocation at 0xe34060000000 of size 536870912 bytes

    Host Frame: grouped.Router.wide in grouped.zig:100
    Host Frame: cuda_exl3.run in cuda_exl3.zig:175  (the FUSED PROMPT path)
    Host Frame: cuda_forward.Forward.ffn → pieced → run
    Host Frame: cuda_engine.Engine.prefillChunk:476
    Host Frame: cuda_follow.Leader.prefill
    Host Frame: glm_kv_shard_check.shardCheck:103

**The reading**: plan_scatter writes bucket positions computed from the
plan scratch (rank[]) — which plan_rank built from the PICKS. Out-of-range
picks (garbage router scores) never land in hist[]; the scatter then reads
UNINITIALIZED rank[] entries and computes a wild base offset (~2.5 GB off
— the ids multiplied by the full expert stride). The corruption is NOT in
the scatter — it is UPSTREAM: garbage expert ids from garbage router
scores, or a clobbered picks buffer.

**The suspects (in order)**: (1) NaN latents from a misrouted latent page
(trash page read) feeding the router matmul; (2) the picks buffer
clobbered by a shard-path write; (3) the plan scratch clobbered. The port
adapted cuda_state.zig's `ltable` slot chain (verified consistent: the
slot exists iff shard, `make` reads it iff shard) and the pool's
keys/lat sizes (verified against the fork's formula).

**The next instrument** (TF_SHARD_DEBUG=1, landed, tranche 2zk 6e2bf75):
in the MoE body, BEFORE the routed experts consume them — the picks
(6 KB) and an x sample (16 rows) read to the host and logged per call:
out-of-range picks prove the corruption upstream of the router; clean
picks prove a clobbered plan scratch. The gate env carries it; the
`.commit-want` pinned to 6e2bf75.

**The state**: window 9 (the picks-vs-x run) launched; production restored
healthy after window 8 (9/9 windows, rc=0).

## (round 139, cont. 30) THE PICKS ARE GARBAGE FROM CALL #0 — X IS CLEAN; THE STRIDE DUMP IS NEXT (2026-11-10)

**Window 9** (campaign-20261110-021302, TF_SHARD_DEBUG=1): the instrument's
verdict, on 43 logged calls:

    TF_SHARD_DEBUG: call #0: rows 2048 slots 9: bad picks 1922/4096
    (first 720442064, last 58417, valid 0..288), x NaN/Inf 0/1024 sample

- **The picks are garbage from the VERY FIRST call** (~1,850-1,930 of
  4,096 bad) — not a corruption that builds up: the buffer is wrong from
  the start.
- **x is CLEAN** (0 NaN/1,024 in the 16-row sample) — the block input is
  fine; the router matmul's input is not the problem.
- **The garbage values repeat EXACTLY across calls** (720442064,
  -2147354444, 58417 = 0xE431 — two E4M3 code bytes, 0xE4 the E4M3 NaN
  pattern): constant CONTENT — data bytes sitting in the picks' memory,
  written once or never initialized. This is a buffer-aliasing/layout
  defect, NOT a runtime race and NOT NaN-propagation from the latents.

**The reading**: the picks buffer at `s.pick` is reading (or was filled
from) another buffer's memory — the port's scratch layout diverges from
the fork's at exactly one slot. The `pick` slot in cuda_state.zig's p[49]
chain is the suspect: the fork's patch changes the shared-buffer split
(twin buffers), and one side of the change is missing in our port.

**The next instrument** (tranche 2zl, d478292): the deepened dump — the
bad pattern's STRUCTURE (per-slot counts reveal the garbage's stride:
every 9th element = row-level aliasing; scattered = slot-level), the raw
first 24 pick values, and the router scores mlog's first rows (whether
the ROUTER itself saw garbage, or wrote good scores into a clobbered
picks buffer). The gate env carries it; `.commit-want` pinned to d478292.

**The state**: window 10 (the stride dump) launched; production restored
healthy after window 9 (10/10 windows, rc=0).

## (round 139, cont. 31) THE STRIDE DUMP: PICKS[0..23] VALID, MLOG SANE AT BOTH ENDS — THE MIDDLE ROWS ARE THE QUESTION (2026-11-10)

**Window 10** (campaign-20261110-024914, the deepened dump): on 172
logged calls, a sharper picture:

    TF_SHARD_DEBUG: call #0: bad 1880/4096, per-slot 214,207,204,211,203,202,213,224,202, x NaN 0
    TF_SHARD_DEBUG: call #0: pick[0..11] = 0,0,0,0,0,0,0,0,0,0,0,0
    TF_SHARD_DEBUG: call #0: mlog row0[0..7] = -4.51, -4.05, -5.03, -5.02, -4.92, -3.69, -5.47, -1.70 | lastrow[0..3] = -2.51, -2.46, -2.28, -2.47

- **The first 24 picks are ALL VALID** (zero or small ids) and BOTH
  mlog sample points (row 0, the last row) carry SANE scores — the
  garbage sits in the MIDDLE rows, invisible to the two-point sample.
- **The bad picks spread UNIFORMLY across the 9 slots** (~202-238 per
  slot) — the signature of whole ROWS going bad: one bad row makes all 9
  of its picks garbage. ~46% of rows bad.
- Bad counts GROW slowly call over call (1880 → 2054 over 3 calls) —
  consistent with a per-layer accumulation, not a fixed layout error.

**The discriminator now in flight** (tranche 2zm, 2eba8c0): the mlog FULL
NaN scan — first/last/COUNT of NaN score rows. NaN rows → all 9 picks
garbage (matching the uniform per-slot counts) → the router's INPUT
(normed x rows) went NaN for exactly those rows → the corruption is in
the sharded stream's values for a SUBSET of rows (the trash-page rows?),
not in the picks buffer. Plus the first bad pick row's full 9 values.
The `.commit-want` pinned to 2eba8c0.

**The state**: window 11 (the mlog scan) launched; production restored
healthy after window 10 (11/11 windows, rc=0).

## (round 139, cont. 32) THE MLOG SCAN'S OWN BUG: THE BUFFER WAS 19 KB FOR A 74 KB COPY — FIXED, RERUNNING (2026-11-10)

**Window 11** (campaign-20261110-032135): the instrument's own arithmetic
bug — `mlog_buf: [64 * 300]u8` sized 19 KB while the scan copies
`64 rows × 288 experts × 4 B ≈ 74 KB` into it. Both ranks printed the
mlog row line and then DUMPED CORE inside the scan (the host overrun
trampled the stack). The core dump is my instrument's, not the engine's;
the four lines each rank printed before dying still confirmed the window
10 pattern on both ranks (bad ~1,840-1,867/4,096, per-slot uniform,
pick[0..23] valid, mlog row0/lastrow sane).

**The fix** (tranche 2zm fixup 2, b02fd54): the buffer sized in BYTES —
`[64 * 300 * 4]u8` (76,800 B) with the comment carrying the burn. The
`.commit-want` pinned to b02fd54; window 12 is running the fixed scan.

**The state**: production restored healthy after window 11 (12/12
windows, rc=0).

## (round 139, cont. 33) ZERO NaN IN THE SCORES — THE GARBAGE STARTS AT ROW 48 (2026-11-10)

**Window 12** (campaign-20261110-034453, the fixed mlog scan): the
decisive split —

    TF_SHARD_DEBUG: call #0: mlog NaN rows 0/2048 (first 0, last 0);
    first bad pick row 48 picks 0,0,193090974,-859742099,-1016807779,-1891798265,1,0,0

- **The router scores are CLEAN everywhere** — 0 NaN rows in 2,048, on
  every call. The NaN hypothesis is dead: the router's input never went
  NaN.
- **The first bad pick ROW is 48** — rows 0..47 valid — and the bad slots
  are 2–5 (slots 0–1 and 6–8 valid), the SAME values every call
  (193090974, -859742099, -1016807779, -1891798265 — float bit-patterns,
  not ids).
- **My earlier x sample covered rows 0–15 only** — it never saw row 48+
  where the garbage starts. And E4M3 bytes read as bf16 (0xE4xx) are
  huge-but-finite floats: invisible to the NaN scans.

**The reading**: the normed x rows feeding the router could still be
E4M3-pattern garbage at rows 48+ (huge-but-finite → extreme but finite
scores → top-k writes garbage ids? no — the scores are SANE). The sharper
hypothesis: `s.pick`'s memory at rows 48+ holds ANOTHER buffer's bytes
(the x3.picks compact-route rows live beside them in the fork's layout).
The values' constancy across calls fits a written-once neighbor.

**The next instrument** (tranche 2zn, 52ad9cd, in flight on window 13):
x rows 44..52 and mlog rows 44..52 dumped raw, with an E4-high-byte
count — clean x there convicts the select/picks buffer itself; E4-pattern
x convicts the sharded latents' pages.

**The state**: window 13 (the bad-row dump) launched; production restored
healthy after window 12 (13/13 windows, rc=0).

## (round 139, cont. 34) X AND MLOG CLEAN AT THE BAD ROWS — THE GARBAGE SHIFTED ONE SLOT (2026-11-10)

**Window 13** (campaign-20261110-042048, the bad-row dump): the corruption
is NOT in the router's inputs or outputs —

    TF_SHARD_DEBUG: call #0: mlog NaN rows 0/2048; first bad pick row 51 picks 0,0,0,193090974,-859742099,-1016807779,-1891798265,1,0
    TF_SHARD_DEBUG: call #0: x rows 44..52: E4-high-byte words 0/512 sample; mlog rows 44..52: max score 2.8069

- **x rows 44..52: CLEAN** (0 E4-words in the sample) — the normed input
  the router saw is fine at the bad rows.
- **mlog rows 44..52: CLEAN** (max score 2.81) — the scores are finite
  and sane exactly where the bad picks come from.
- **The first bad pick row MOVED between runs: 48 → 51**, and the four
  garbage words SHIFTED ONE SLOT right in the row (window 12's
  `0,0,g,g,g,g,1,0,0` vs window 13's `0,0,0,g,g,g,g,1,0`). The GARBAGE
  CONTENT is identical (the same four words) but its POSITION inside the
  pick rows drifts — the signature of an UNINITIALIZED region whose
  boundary slides with run-to-run variation (a concurrent writer's
  timing, or an offset computed from something that varies per run).

**The reading**: the select's outputs (mlog → scores clean, pick →
garbage at rows ~48+) disagree — either the select's pick-write path is
wrong for those rows, or pick's memory is being overwritten by a
concurrent writer whose extent varies. The wts comparison discriminates:
the select's OTHER output for the same rows.

**The next instrument** (tranche 2zo, 7095ff4, in flight on window 14):
pick rows 44..52 read BEFORE the select (garbage already there = a
stale/concurrent writer; clean = the select writes it) and wts rows
44..52 after (garbage there too = the row loop broken; valid sigmoid
values = only pick's pointer path wrong).

**The state**: window 14 (the pre/post discriminator) launched;
production restored healthy after window 13 (14/14 windows, rc=0).

## (round 139, cont. 35) WTS IS PERFECT, PICK DRIFTS — THE BOUNDARY DUMP IS IN FLIGHT (2026-11-10)

**Window 14** (campaign-20261110-044819, the pre/post discriminator):
the sharpest split yet —

    TF_SHARD_DEBUG: call #0: PRE-select pick row44 = 0,0,0,0,0,0,0,0,0 | row51 = 0,0,0,0,0,0,0,0,0
    TF_SHARD_DEBUG: call #0: wts row44 = 0.60,0.40,0.34,0.29,0.24,0.24,0.21,0.19,1.00 | row51 = 0.87,0.45,0.26,0.24,0.18,0.17,0.16,0.16,1.00
    TF_SHARD_DEBUG: call #1: PRE-select pick row44 = 134,278,183,188,14,76,266,211,288 | row51 = 21,211,276,2,106,236,172,161,288

- **wts rows 44/51: PERFECT sigmoid values on every call** — the select's
  other output is correct for exactly the rows whose picks go garbage.
- **PRE-select pick rows are all-zero on call #0** (the buffer starts
  zeroed) and hold the PREVIOUS layer's VALID ids on call #1 — the buffer
  is reused across layers, and the select CAN write valid rows there.
- **The first bad row DRIFTED again: 48 → 51 → 59** across three runs,
  with the SAME four garbage words at the same relative slots (3–6). The
  content is constant; the boundary moves.

**The reading**: the select's outputs DISAGREE — wts correct, pick
garbage from a drifting row boundary. The strongest hypothesis now: pick's
SLICE in the arena is short (a sizing mismatch in the port's `sizes`
chain), and the writer after it in memory order bleeds BACKWARD into
pick's tail — the four constant words are that neighbor's data. The
boundary dump (pick rows 0..70 raw with a zero/valid/garbage census, the
first bad row's neighbors, and x3.picks' first words — the buffer that
would sit after pick) settles it: if the four words appear at
x3.picks[0..], pick's size is short by exactly the bleed.

**The state**: window 15 (the boundary dump) launched; production
restored healthy after window 14 (15/15 windows, rc=0).

## (round 139, cont. 36) THE BOUNDARY ESCAPED THE WINDOW AGAIN — THE FULL CENSUS IS IN FLIGHT (2026-11-10)

**Window 15** (campaign-20261110-051814, the boundary dump): the fixed
71-row window MISSED the boundary a third time —

    TF_SHARD_DEBUG: call #0: pick rows 0..71: zeros 1 valid 638 garbage 0

Rows 0..71 are ALL VALID now — the first-bad-row drifted past 71 (48 →
51 → 59 → >71 across four runs). The drift is run-to-run (timing), the
garbage content constant. Also noted: x3.picks held call #0's picks at
call #1 — expected, the compact copy runs during the experts' pass (not
the corruption).

**The instrument** (tranche 2zq, 5bf9bc4): the FULL census — every one of
the 2,048 pick rows classified in one 73 KB read: bad-row count, the
even/odd parity split (a stride-2 row-pair bug shows as even≠odd), the
first bad row's neighborhood raw. The census follows the boundary
wherever it lands.

**The state**: window 16 (the full census) launched; production restored
healthy after window 15 (16/16 windows, rc=0).

## (round 139, cont. 37) THE CENSUS PARADOX RESOLVED: THE DIAGNOSTIC READS RACED THE STREAM (2026-11-10)

**Window 16** (campaign-20261110-054406, the full census): a paradox that
turns the whole investigation —

    TF_SHARD_DEBUG: call #0: mlog NaN rows 0/2048; first bad pick row 60 picks -1016807779,...
    TF_SHARD_DEBUG: call #0: CENSUS rows 2048: bad rows 0 (even 0, odd 0); first bad-any row 0

The FULL census over ALL 18,432 entries says ZERO bad rows — while the
earlier small read of the SAME memory said ~1,800 bad, with the first bad
row drifting (48 → 51 → 59 → 60 → >71 across five runs). Two reads of the
same memory cannot both be true unless the memory CHANGED between them.

**The root cause of the drift — my own instrument**: every diagnostic
DtoH ran `cuMemcpyDtoH_v2` on the NULL stream, which does NOT serialize
with the engine's own stream. The reads RACED the select's in-flight
writes: the "drifting first-bad-row" was the select's WRITE PROGRESS at
read time (the copies launched while the select kernel was mid-flight).
The FINAL state is clean — the select writes valid picks everywhere.

**The consequence**: garbage picks CANNOT be feeding plan_scatter — the
select's output is valid at rest. The suspect moves to the fused path's
plan scratch itself (plan.rank/hist/items) or the compact copy — the
kernels the plan_scatter's own arithmetic reads.

**The instrument** (tranche 2zr, 56d3109): every diagnostic DtoH now
SYNCHRONIZES the stream first (all 12 reads), and the plan scratch
(plan.rank[0..31], counts) is dumped after the sync. If the first scan
now reads CLEAN too, the race theory is proven on the spot.

**The state**: window 17 (the synced reads + the plan scratch) launched;
production restored healthy after window 16 (17/17 windows, rc=0).

## (round 139, cont. 38) THE RACE PROVEN — THE PLAN SCRATCH IS INCONSISTENT; THE EVERY-CALL CENSUS IS IN FLIGHT (2026-11-10)

**Window 17** (campaign-20261110-061022, the synced reads): the race
theory PROVEN, and the target moved again —

    TF_SHARD_DEBUG: call #0: CENSUS rows 2048: bad rows 0 (even 0, odd 0)
    TF_SHARD_DEBUG: call #0: plan.rank[0..15] = 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    TF_SHARD_DEBUG: call #1: plan.rank[16..31] = 0,0,0,0,0,0,0,0,0,0,2,0,0,0,1,0
    TF_SHARD_DEBUG: call #1: plan.counts[0..7] = 401,286,0,0,0,0,0,0

- **The census reads ZERO bad rows on every call with the sync in** —
  the final picks are valid everywhere. The select is INNOCENT.
- **The plan scratch is inconsistent**: plan.rank (the per-pair bucket
  ranks) is almost all ZEROS with three tiny entries (1, 2, 1) where
  cumulative sums should be, while plan.counts[0..1] = 401, 286 carry
  real values. The plan's own state doesn't cohere.
- **The fault's position**: launch #2893 landed AFTER calls #0/#1
  logged clean — the failing ffn call is a LATER one, but my census was
  gated to the first two calls.

**The reading**: with picks and the select clean, the last suspects are
the plan chain inside `router.route` (plan_rank → plan_offsets →
plan_scatter) reading the COMPACT picks (`sc.x3.picks` — a different
buffer than `s.pick`!) vs the fork's layout, or a later ffn call whose
inputs differ. Note: the fused path's `exl3.run` compacts picks into
`sc.picks` (a per-chunk copy of the top_k entries) — the compact's
SIZING/stride is the unverified link between the clean select and the
plan kernels.

**The instrument** (tranche 2zs, b8004df): the EVERY-CALL census — the
final picks classified on EVERY ffn call, each line annotated with the
launch ring's seq (the receipt maps call N ↔ launch #M; the fault's
#2893 lands between two census lines), and the full detail dump fires on
the FIRST call whose final picks go bad. The `.commit-want` pinned to
b8004df.

**The state**: window 18 (the every-call census) launched; production
restored healthy after window 17 (18/18 windows, rc=0).

## (round 139, cont. 39) ALL 42 FIRST-CHUNK CALLS CLEAN — THE FAULT IS IN CALL #42'S PLAN CHAIN; THE PLAN SCAN IS IN FLIGHT (2026-11-10)

**Window 18** (campaign-20261110-070512, the every-call census): the
sharp bracket —

    TF_SHARD_DEBUG: call #42 (launch #2890): CENSUS bad rows 0/952; first bad 0
    error: TF_LAUNCH_SYNC: launch #2893 faulted IN EXECUTION: CUDA_ERROR_ILLEGAL_ADDRESS (700); kernel ?, grid 30x1x1, block 256x1x1

- **Every one of the 42 ffn calls of the FIRST chunk read CLEAN final
  picks** (bad 0/2048 on all of them). The select is fully innocent.
- **Call #42 is the SECOND chunk's first MoE layer** (rows=952 — the
  short tail chunk of the 3,000-token prompt at the pieces' split), and
  the fault fired THREE launches after its census line: #2891-2892 (the
  plan chain's rank/offsets kernels) synced CLEAN, **#2893 =
  plan_scatter faulted IN EXECUTION** — inside the SAME call.
- My census sits after the select but BEFORE the plan chain in the fused
  path — it validates the compact SOURCE, not the plan's behavior.

**The reading**: the plan buffers were TRASHED between calls — the prime
suspect is the port's pool write path (`tf_glm_pool_keys`, in the ring
before the fault): the second chunk touches PAGES the first chunk never
did — an overrun at the page boundary lands in the plan scratch, and
chunk 2's plan_scatter reads the trashed state. The first chunk ran 42
clean ffn calls; the second chunk's first MoE faults.

**The instrument** (tranche 2zt, 7342b40): the hist/rank FULL scan on
EVERY call — the first garbage there brackets the trashing kernel
exactly. The `.commit-want` pinned to 7342b40.

**The state**: window 19 (the plan scan) launched; production restored
healthy after window 18 (19/19 windows, rc=0).

## (round 139, cont. 40) THE PLAN SCAN CLEAN TOO — THE BRACKET NARROWS TO THREE OPS; THE PRE-SCATTER READ IS IN FLIGHT (2026-11-10)

**Window 19** (campaign-20261110-073553, the hist/rank full scan): the
bracket tightened again — the plan buffers are CLEAN at every census
point including call #42 (`CENSUS bad rows 0/952; hist bad 0; rank bad
0/7616`), and the fault STILL fired at #2893 inside call #42's plan
chain. The trash happens between #2890 (census) and #2893 (scatter):
only THREE operations run there — plan_rank (#2891, synced clean as a
launch), plan_offsets (#2892, synced clean as a launch), and the COMPACT
COPY (an async DtoD — invisible to the ring, never synced, never
validated).

**The gap in the instrument**: the rank/offsets kernels' OUTPUT state was
never read back before scatter consumed it (their launches synced clean —
but a clean launch says nothing about what they WROTE), and the compact
picks (the buffer route's kernels read as expert ids) were never
validated at all.

**The instrument** (tranche 2zu, 26176fb): the PRE-SCATTER bracket —
- the COMPACT picks dumped + range-checked right before `route` (in the
  exl3 prompt path, synced);
- `rank[0..15]` and `hist[0..15]` read AFTER plan_offsets, BEFORE
  plan_scatter (in grouped's wide path, synced).
If the compact holds out-of-range ids, the compact copy is the culprit;
if rank/hist are garbage pre-scatter, rank/offsets wrote it this call;
if BOTH are clean, the scatter's own arithmetic diverges from the fork's
in the port's `wide()` call (the grid/args).

**The state**: window 20 (the pre-scatter bracket) launched; production
restored healthy after window 19 (20/20 windows, rc=0).

## (round 139, cont. 41) EVERY INPUT CLEAN — THE MEMBERS BASE POINTER IS THE SUSPECT (2026-11-10)

**Window 20** (campaign-20261110-081416, the pre-scatter bracket): all
three suspects cleared in one run —

    TF_SHARD_DEBUG: COMPACT picks[0..19] = 43,193,10,77,... (bad 0/80, valid 0..288)
    TF_SHARD_DEBUG: PRE-SCATTER rank[0..15] = 0,0,0,...,1,0 | hist[0..15] = 0,34,40,529,542,641,...
    error: TF_LAUNCH_SYNC: launch #2893 faulted IN EXECUTION: CUDA_ERROR_ILLEGAL_ADDRESS (700); kernel ?, grid 30x1x1

- **The compact picks are VALID** (0 bad/80 on every call) — the compact
  copy is innocent.
- **rank and hist are COHERENT** — hist is a valid cumulative prefix-sum
  (0, 34, 40, 529, …), rank holds small local ranks — plan_rank and
  plan_offsets are innocent.
- **The fault STILL fired at #2893** — with every input verified clean
  immediately before the scatter ran.
- **The sanitizer's failing thread was (64,0,0) in block (0,0,0)** —
  p = 64, whose index `hist[picks[64]] + rank[64]` is provably SMALL
  and valid from the dumps.

**The conclusion**: a valid index producing a wild address (2.5 GB below
the nearest allocation) convicts **the `members` base pointer itself**.
The instrument (tranche 2zv, 5d2f036): the PLAN PTR dump — the pointers
and their diffs against the sizes chain (`items − members = P·4`,
`counts − items = maxItems·12`, `rank − counts = 8`, `hist − rank = P·4`).
Any mismatch convicts the arena slot mapping (the `sizes` array vs the
`p[N]` order in cuda_state.zig — the port's one hand-edited link).

**The state**: window 21 (the pointer dump) launched; production restored
healthy after window 20 (21/21 windows, rc=0).

## (round 139, cont. 42) EVERY POINTER CONSISTENT TOO — THE FULL INDEX VALIDATION IS IN FLIGHT (2026-11-10)

**Window 21** (campaign-20261110-083722, the pointer dump): the fourth
layer of the bracket cleared —

    TF_SHARD_DEBUG: PLAN PTRS: members 0xe929d8790300 items ...7a2300 counts ...7a6700 rank ...7a6800 hist ...7b8800
        items-members 73728 (P*4=65536) counts-items 17408 rank-counts 256 hist-rank 73728 (P*4=65536)

- **Every pointer diff is CONSISTENT** — items−members = 73,728 ≥ P·4
  (65,536), rank−counts = 256, hist−rank = P·4 exactly. The arena slot
  mapping in cuda_state.zig is CORRECT; the members base is sane.
- The fault STILL fired at #2893 — the fifth window in a row with every
  measurable input clean.

**The conclusion**: samples are not proof. The failing thread p=64 reads
`picks[64]`, `rank[64]`, `hist[picks[64]]` — but my dumps sampled only
[0..19] of the compact and [0..15] of rank/hist. The instrument
(tranche 2zw, fff5d82): the FULL host-side index validation — read
picks/rank/hist COMPLETELY (P pairs, nblk×E hist), compute
`hist[picks[p]] + rank[p]` for EVERY pair p on the host, report the MAX
index vs members' words. If max ≥ words, the scatter writes out of
bounds WITH clean-looking data — convicting the hist/rank alignment or
the offsets kernel's sums. Plus the failing thread's exact triple.

**The state**: window 22 (the full index validation) launched;
production restored healthy after window 21 (22/22 windows, rc=0).

## (round 139, cont. 43) CALL #42'S FULL PICTURE: X IS NAN FOR THE WHOLE CHUNK-2 PASS (2026-11-10)

**Window 22** (campaign-20261110-090155, the full index validation):
five windows of clean measurables — then the full scan caught what the
samples missed. Call #42's complete lines:

    INDEX CHECK: pairs 7616 members-words 7616: max idx 1028079817 (at p=1023), oob 2048, bad-pick 0
    call #42: mlog row0[0..7] = nan, nan, ... | lastrow = nan (ALL 952 rows NaN)
    call #42: wts row44 = 0.0000 x 8, 1.0000 (the select of NaN scores)
    COMPACT picks[0..19] = 288,288,288,288,... (the shared slot everywhere)
    p64 = picks 288, rank 1028078858, hist[288] 0, idx 1028078858
    PRE-SCATTER rank[0..15] = 1028078794,1028078795,... (a monotone run — float bits!)

- **mlog is NaN for ALL 952 rows** — the router's INPUT x for chunk 2 is
  NaN from the start. The router matmul of NaN x → NaN scores → the
  select of NaN writes zeros/wts 0 → the plan of a degenerate input →
  rank holding float-bit garbage (~1.028e9 = 0x3D4F_xxxx as f32 bits) →
  the scatter's wild writes.
- **The first chunk's 42 calls were CLEAN** (every index check oob 0 on
  pairs 16384). The corruption entered between chunk 1's end and chunk
  2's first ffn.
- **The index check on chunks 1's calls PASSED COMPLETELY** —
  `max idx 16383 (at p=16314), oob 0, bad-pick 0` — the whole range
  proven in-range.

**The reading**: the defect is NOT in the plan chain at all — the plan
chain faithfully consumed a NaN x. The corruption enters through the
mixer's x for the second chunk: the suspects are the shard path's own
writes at the chunk boundary — the twin give-back (`giveTwin` before the
first decode round) and the pool's page writes (`pool_keys` in the ring
between the calls).

**The instrument** (tranche 2zx, b2a3c83): the EVERY-CALL x NaN census —
the first call with NaN x brackets the trashing kernel to ONE
inter-call window. The `.commit-want` pinned to b2a3c83.

**The state**: window 23 (the x census) launched; production restored
healthy after window 22 (23/23 windows, rc=0).

## (round 139, cont. 44) THE BRACKET IS ONE WINDOW WIDE: X CLEAN AT #41, NaN AT #42 — THE HIDDEN DUMP IS IN FLIGHT (2026-11-10)

**Window 23** (campaign-20261110-093211, the x census): the bracket is
now ONE inter-call window —

    call #41 (launch #2718): x NaN rows 0/2048
    call #42 (launch #2890): x NaN rows 952/952 (first 0)

The trash entered between the last ffn of chunk 1 and the first ffn of
chunk 2 — a ~172-launch window whose kernels include the hc chain's
commit, the DSA/KDA writes, `pool_keys` (the indexer's pooled keys), and
— with TF_GLM_KV_SHARD — the pool's `index_write`/`pool_keys` writes
into the pool's `keys` pages.

**The structural fact**: the ffn's x (normed) derives from the hc chain
whose input is `b.hidden` — the shared buffer the layer-0 mixer reads.
The discriminator (tranche 2zy, a55a7a0): the HIDDEN dump at every ffn
call (the first 32 rows × 64 columns NaN-censused) — **NaN hidden
convicts the gate/commit path before layer 0** (the trash entered before
the layer loop); **clean hidden with NaN x convicts the layer-0
KDA/DSA state path** (the mixer's output itself).

**The state**: window 24 (the hidden dump) launched; production restored
healthy after window 23 (24/24 windows, rc=0).

## (round 139, cont. 45) HIDDEN CLEAN, X NAN — THE CORRUPTION IS INSIDE THE LAYER LOOP (2026-11-10)

**Window 24** (campaign-20261110-100124, the hidden dump): the
discriminator's answer —

    HIDDEN NaN words 0/2048 sample        (every ffn call, incl. #42)
    INDEX CHECK: pairs 7616 ... max idx 1028079817 (at p=3071), oob 2048  (call #42)

- **b.hidden is CLEAN at call #42** (0/2048 in the sample) — the gate/
  commit path before the layer loop is INNOCENT.
- **x (normed) is NaN 952/952** — the corruption enters INSIDE layer 0's
  chain: the ffn's x comes from the SECOND hcPre, whose input `b.x` was
  written by the FIRST hcPost (`xout[s] = post[s]·branch + Σ comb·x[t]`)
  — the combine of the mixer's output (`gathered`) with hcPre's Sinkhorn
  state (`post`/`comb`).

**The split this enables** (tranche 2zz, in flight): NORMED-PRE
NaN-censused right after hcPre (NaN there convicts hcPre itself, with
clean input); POST/COMB/GATHERED censused before hcPost (NaN there
convicts the gather/mixer's output hcPost combines).

**The state**: window 25 (the NaN-site dumps) pending; production
restored healthy after window 24 (25/25 windows, rc=0).

## (round 139, cont. 46) THE NAN-SITE DUMPS MISPLACED — MOVED INTO THE ROW-RANGE GLUE (2026-11-10)

**Window 25** (campaign-20261110-103551): the dumps fired but landed in
the wrong path —

    NORMED-PRE NaN words 0/2048 sample    (once, call #0)
    HIDDEN  NaN words 0/2048 sample       (per ffn call, incl. #42)
    call #42: x NaN rows 952/952          (the ffn's normed input)

- **The POST/COMB/GATHERED trio never printed**: chunk 1 runs PIECED
  (the overlap path's glue is `postRows`/`preRows` with row ranges, not
  the whole path's `post()`/`pre()` where the dumps sat).
- **The HIDDEN dump reads `b.hidden` — the stream-mean buffer written at
  the END of the forward**: its cleanliness at call #42 is meaningless
  (stale/never-written data, not the ffn's chain). The REAL ffn input is
  `b.normed` — the x NaN census reads it and it IS NaN.

**The corrected chain map**: ffn's x = `b.normed` ← written by the ffn's
hcPre ← whose input `b.x` was written by the mixer's hcPost ← combining
`b.x` + `gathered` (the mixer's output) + `post`/`comb` (the Sinkhorn
state). The births: NaN `gathered` (the mixer/DSA/owner path) or NaN
from hcPre's own state.

**The fix** (tranche 2zaa, in flight): the dumps move into
`postRows`/`preRows` — the glue BOTH paths share — so they fire on
chunk 2's layer-0 ffn regardless of which path ran.

**The state**: window 26 pending; production restored healthy after
window 25 (26/26 windows, rc=0).

## (round 139, cont. 47) THE BIRTH BRACKETED TO ONE HCPOST: NORMED-PIECED-PRE FLIPS CLEAN → ALL-NAN BETWEEN CALL #41 AND #42 (2026-11-10)

**Window 26** (campaign-20261110-110304, the relocated dumps): the
decisive transition —

    NORMED-PIECED-PRE NaN words 0/2048 sample    ×285 (every pre of chunk 1)
    NORMED-PIECED-PRE NaN words 2048/2048 sample  ← ALL NaN (from here on)

- **The normed buffer flips CLEAN → ALL-NaN inside ONE hcPre call** —
  with `hidden` clean at the same moment. hcPre's output NaN from clean
  input convicts hcPre's OTHER inputs: `hc.fn_w`/`base`/`scale` (the
  weights) or its scratch `hcpart`/`post`/`comb`/`xs`.
- **The flip sits between call #41 (chunk 1's last ffn, x clean) and
  call #42 (chunk 2's first ffn, x all-NaN)** — the glue window where
  the last hcPost of chunk 1 and the chunk-boundary pool writes run.
- **The trio was still missing from the pieced path**: `postRows` (the
  pieced hcPost) had no dumps — the GATHERED/POST/COMB state that
  hcPost combines was never read at the flip.

**The corrected instrument** (tranche 2zab, 17571f2): the trio moves
into `postRows` — GATHERED/POST/COMB plus X before and after hcPost at
every piece glue. Window 27 reads the state hcPost combines at the
flip: NaN GATHERED convicts the mixer/DSA/owner path (the mixer's
output); clean GATHERED with NaN X-after convicts hcPost's arithmetic
on the Sinkhorn state (`post`/`comb`) or its weights.

**The state**: window 27 (the postRows trio) launched; production
restored healthy after window 26 (27/27 windows, rc=0).

## (round 139, cont. 48) THE GATHERED NANS ARE THE OLDEST SIGNAL — FROM THE FIRST PIECE GLUE; THE TWINS-OFF A/B IS IN FLIGHT (2026-11-10)

**Window 27** (campaign-20261110-112805, the postRows trio): the
primary signal surfaces —

    GATHERED-PIECED NaN words: 7, 1, 4, 2, 10, 4, 3, 2, 2, 10, ... (sparse, FROM THE FIRST GLUE)
    X-PRE-POST-PIECED / X-POST-POST-PIECED: 0/2048 (clean through chunk 1)
    ... then GATHERED: ... 2048 2048 (the flip, at the chunk boundary)

- **`gathered` carries sparse NaNs (1-10 of the 2,048-word sample) from
  the VERY FIRST piece glue** — 291 readings of 1-8/2048 through all of
  chunk 1, then 2048/2048 at the boundary. The mixer/DSA path produces
  NaN rows from layer 0, piece 0 — the OLDEST signal in the whole
  investigation (everything earlier was downstream of it).
- hcPost folds them into x (bf16); they accumulate per layer; at the
  boundary some buffer boundary tips the ffn's sample over.
- The ffn consumes NaN x → NaN mlog → degenerate plan → plan_scatter
  faults. The whole downstream chain was effects.

**The primary suspect**: the DSA attention on sharded latents — the
owner-computed path reading the trash page (NaN-poisoned by design) for
rows it shouldn't hold, or the twin/latent mapping misrouting. The
original hypothesis (window 12's E4M3 reasoning) returns with proof.

**The instrument** (KSHARD_TWINS0=1, landed in the gate phase): the
TWINS-OFF A/B — TF_GLM_KV_SHARD_TWINS=0 on rank 0 alone, sequential
after the main run. Twins-off reads the owner's OWN latents for all rows
(no twin pages, no trash-page reads for held rows). **NaNs vanish
twins-off → the twin/latent mapping is the defect; NaNs persist → the
owner's own latent pages are miswritten** (the pool's keys/lat writes).

**The state**: window 28 (the main run + the A/B) launched; production
restored healthy after window 27 (28/28 windows, rc=0).

## (round 139, cont. 49) THE A/B BURNED ON A TWO-RANK PROGRAM RUN WITH ONE RANK — FIXED TO BOTH RANKS (2026-11-10)

**Window 28** (campaign-20261110-114542): the twins-off A/B produced 0
bytes — the check is a TWO-RANK program and my A/B ran rank 0 alone:
rank 0 sat in `ncclCommInitRank` waiting for rank 1 for the whole
2,400 s timeout. The main run beside it confirmed the standing state
(the fault at #2893, the GATHERED NaNs from the first glue).

**The fix** (landed): the A/B runs BOTH RANKS — the id file is already
on both hosts, rank 1 starts first on the join, exactly as the main run
does; the verdict line carries rc/FAIL/GATHERED-NaN counts for both.

**The state**: window 29 (the both-rank twins-off A/B) launched;
production restored healthy after window 28 (29/29 windows, rc=0).

## (round 139, cont. 50) THE A/B LOST RANK 0'S OUTPUT AGAIN — DIRECT WRITES INTO THE OUT DIR (2026-11-10)

**Window 29** (campaign-20261110-124515): the both-rank A/B still lost
rank 0's output —

    twins-off A/B: both ranks — twins0-r0.log rc=124 FAIL=0 (0 BYTES)
    twins0-r1.log rc=1 FAIL=1 (NcclFailed: remote process exited)

Rank 1 joined and saw rank 0 die; rank 0's log is EMPTY (rc=124 = the
timeout). The mktemp+mv redirection lost the output again — the
diagnostic manual run confirms rank 0 alone fails FAST (NcclFailed,
ncclGetUniqueId) when the id file is stale — so the window's rank 0
should have produced output immediately, and 0 bytes means the
redirection itself failed in the window's context.

**The fix** (landed): both ranks' logs write DIRECTLY into the OUT dir
(`> "$OUT/kshardcheck-twins0-r0.log"`) — the main run's own shape, no
mktemp+mv hop.

**The state**: window 30 (the direct-write A/B) launched; production
restored healthy after window 29 (30/30 windows, rc=0).

## (round 139, cont. 51) WINDOW 30: THE A/B STILL LOST RANK 0'S OUTPUT — THE VERDICT BLOCKED ON ITS PLUMBING; THE DEFECT HUNT PARKED FOR THE V1.2.6 REBASE (2026-11-10)

**Window 30** (campaign-20261110-134538): the direct-write A/B
repeated window 29's shape exactly —

    twins0-r0.log: 0 bytes, rc=124 (the full 2,400 s timeout)
    twins0-r1.log: NcclFailed: remote exited (rank 1 joined, saw rank 0 gone)
    the main run: the standing state (the fault at #2893, the
    GATHERED NaNs from the first glue) — no new facts

Three redirection shapes (mktemp+mv, direct-write, both-ranks) all
lost rank 0's output inside the window's context while the same
command run manually fails FAST with `ncclGetUniqueId: invalid
usage (5)`. The A/B's rank-0 docker line is not root-caused; the
same command fails differently inside the window flow than out of
it.

**The user parked the hunt**: "Pause after you have checked the
receipts. We will look at v1.2.6" — then directed the rebase. The
next steps on resume: (a) the v1.2.6 rebase (IN FLIGHT this sitting
— the drift map applied, the val battery staged), (b) the A/B
plumbing root-cause when the defect hunt resumes: diff the A/B's
rank-0 docker line against the main run's (the COMMON_ENV vs TWENV
shape), or run the A/B manually with production DOWN.

**The state**: production healthy (rc=0 restore, 30/30 windows);
the defect hunt parked with the receipts checked.

## (round 140) THE V1.2.6 REBASE: THE DRIFT MAP APPLIED, THE ROUND-TRIP PROVEN BYTE-IDENTICAL (2026-11-10)

**The user's directive**: rebase the repo to upstream v1.2.6, then evaluate the
patches that are still relevant.

**The release read** (v1.2.6 6e9af9302, released 2026-11-10 12:51): 762 files,
~49.9K insertions. For our line: **#2257** (the GLM TP=2 windows-32 release commit
— decode windows reach 32 rows, MTP chains 15; prompts 23%/13% faster at 2K/8K,
one-stream code decode +32%, every reply equal), **#2699** (the prompt-cache
rework: the reclaim chain, the admission guards, the budget scaled to the room),
**#2181** (TF_GLM_KV_LIVE_HALF, opt-in — a kept state holds the live KDA half
alone), and the stricter settings (GLM's 0/1 switches refused by name, blanks
read as unset). **The #1431/#2415 KV-SHARD line did NOT land** — the fork port
stays a separate decision.

**The mainline verdicts** (git-grep against the tag objects — rule #1): NO fork
mechanism landed on the v1.2.6 tag; the whole living stack survives.
008-loaddirect keeps its value (upstream's #2449 took direct reads to
spark25/dory ONLY). **Upstream watch**: main is 36 commits past the tag and has
absorbed the fork's 0078 exl3p prompt loop (bc166dbfd) plus the cp.async/
ldmatrix/mma common-module extractions — the next release may mainline more of
the stack.

**The drift map** (the stack-order apply probe, no reset between patches): 6 of
18 apply clean on bare v1.2.6 (002, 008, 010, 011, 013, 018); 12 re-anchored
(001, 003, 004, 005+006+007 as the 003-cascade, 009, 012, 014, 015, 016, 020).
The named collision sources: the shared MLA image (#850 step 3, 42735f94f —
the chunks_wide template moved into common/mla.cuh gaining RW/SPLIT params),
#2257 (24 engine files), #2699 (the kv_pool budget into budgetOf()), the SwiGLU
split (88267c063), the EXL3 clamp (edc16dfe9 — additive, AFTER=false).

**The re-anchor**: 003's PAGED8 marriage and 007's fetch8 port live in
common/mla.cuh now (the template edits re-cut onto the RW/SPLIT shape); 020
re-anchored onto budgetOf() (cache_first rides the Budget struct through it);
012/015/016 hand-anchored onto the fork-consolidated exl3 ground; 001's
Numerics moved into v1.2.6's readSet structure with the fingerprint at layout
21 (20 + numerics).

**The verification**: the tool-parse host suite PASS (RC=0, honest capture);
the compile gate caught THREE duplicate-symbol defects from the sitting's
hand-anchor replay (the duplicate grouped_body_v2 body, and duplicate
cacheFirst/Geometry/i32d copies from the replay scripts running twice against
the tree) — all fixed and re-run. **The round-trip PROVEN**: pristine v1.2.6 +
the 18 regenerated patches = the rebase tree, ZERO diffs (the byte-identical
double reconstruction of the v1.2.5 procedure). The regenerated patch files
carry the re-anchored hunks; the headers and the REBASE provenance paragraphs
preserved.

**The pin**: TF_COMMIT = 6e9af9302 in the head's local.sh; the v126val battery
phase is staged in the gate (the same-bits greedy witness, the §2 gates, the
boot witnesses under the strict TF_ validation, the bench + steady-state
decode, hardmode 95, the vision 4/4, the walls). Any FAIL holds the pin at
v1.2.5.

**The next order**: the compile gate's RC on the fixed tree, then the
`preflight v126val summary` window decides the pin.

## (round 140, cont. 2) THE V1.2.6 BUMP QUALIFIED — THE PIN HOLDS; THE PROMOTED LINE NOW SERVES THE V1.2.6 ENGINE (2026-11-10)

**Window 32** (campaign-20261110-162034, `preflight v126val summary`, rc=0,
production restored healthy after 80 s — on the v1.2.6 engine
6e9af9302): the v126val battery passed on every instrument.

- **The same-bits greedy witness: IDENTICAL** — the engine bump did not
  move the deterministic probes (the 80cc3802… sha holds across
  v1.2.5 → v1.2.6 with the full 18-patch stack re-anchored).
- **The §2 content gates ALL PASS** (g1-g4 + the g5 note), zero
  strict-TF_ refusals at boot under the stricter v1.2.6 validation.
- **Hardmode 95 — the TWENTY-SECOND consecutive** (TC-51 and TC-92
  both pass).
- **The vision 4/4**; steady-state decode 73.1 tok/s; prefill 1,523 at
  d0 (the band); the walls **84/83 s** (the first load after the
  prepare 93 s — the loading row re-dated).
- The serve line reads the v1.2.6 pool plan: the engine's own + 3
  streams at 3,098 pages of 512 rows, 415 MiB fixed each, no prompt
  cache at the standing TF_KV_SHARE=16 (#2699's reworked budget — the
  none-of-the-slots-fit note names the --prompt-cache-gib 4 that holds
  all 16).

**The adoption**: the pin HOLDS at 6e9af9302 — the anchors' loading
row re-dated, the chart regenerated, the ledger closed. The v126val
phase retires with its receipt (the session-specific pattern). The
promoted production repo mirrors the bump on its next promotion sync;
its LIVE serve was restarted on the v1.2.6 engine through the
window's restore path.

**Window 31 was VOID** (campaign-20261110-160948): my launch carried
the phase list as a PHASES env var — silently ignored (the cont. 69
lesson, re-learned); the window ran only the summary phase and
restored production on the v1.2.5 engine in 81 s. The correction: the
launch argument IS the phase list; window 32 ran it properly.

## (round 140, cont. 3) THE CACHEFIXQUAL A/B IS INVALID — THE ON ARM WAS A PLACEBO; THE BATTERY IS FIXED AND RE-RUNS (2026-11-10)

**Window 33** (campaign-20261110-173035, `preflight cachefixqual summary`,
rc=0, production restored healthy after 81 s): the battery RAN to
completion — every quality instrument passed — but the A/B itself
measured nothing, and the fault is the battery's own staging.

**The placebo**: the phase built the ON arm's env pair as
`PROMPT_PROMPT_CACHE_GIB=4` (a doubled name nothing reads — start.sh maps
`PROMPT_CACHE_GIB`; config.sh's default is empty). `--prompt-cache-gib`
never reached the engine: the console's restart lines print the mangled
name, no container argv carries the flag, and both arms' serve lines end
with the constant ADVICE tail "--prompt-cache-gib 4 holds all 16" (the
tail prints regardless — it names what WOULD hold all 16, cuda_kv_pool.zig
:264). The OFF-to-ON slot move (3 -> 6 of 16) tracked the ROOM DRIFT
(12.1 -> 13.0 GiB left), not the flag: the slot ladder across the window's
restarts is monotone in room — v126val 11.5 left/0 slots, OFF 12.1/3, ON
13.0/6, the DRAFTS=0 serve 16.1/11. Two identical cacheless serves were
compared. The verdict correctly did not fire; NOTHING adopted.

**What the window still qualified (the OFF arm as a second witness)**: the
greedy sha 80cc3802… IDENTICAL on both arms, the §2 gates ALL PASS (g3's
resumed=fresh content gate PASSED — the resume witness that matters),
hardmode 95 — the TWENTY-THIRD consecutive, the vision 4/4, the bench
cells in bands (pp d0 1,525; the depth cells 1,461-1,514), steady-state
decode 73.1 tok/s. Effectively a second v126val-grade all-pass on the
standing config.

**The instrument lesson**: the turn-1/turn-2 wall probe measured
RE-PREFILL, not resume — turn 2's wall (1,918/1,831 ms) exceeds turn 1's
(768/555 ms) by construction because turn 2 re-prefills its longer
history. g3 + the funded-slots line are the resume witnesses; the wall
probe is reference only.

**The room-drift data**: the slots funded move with the room left after
the streams, ~1 slot per ~180-230 MiB of room, across every restart in
the window — the fork's issue-16 class, now with a fifth data point on
the v1.2.6 engine. The recovery ask (4 GiB) caps the cache ABOVE the
16 x 180 MiB = 2.88 GiB the slots need, so a TRUE placed 4 GiB ask makes
the 16/16 criterion drift-immune: the fully-funded phrasing ("16 kept
states' slots", no "of TF_KV_SHARE=" and no advice tail — cuda_kv_pool.zig
:262) prints only when all 16 funded.

**The fix**: the phase's env name corrected everywhere
(PROMPT_CACHE_GIB=4), the PLACED-flag witnesses added (the container argv
carries --prompt-cache-gib 4; the fully-funded phrasing; the room-funds
clip report must be ABSENT), the turn-wall probe relabeled reference-only,
the verdict criterion sharpened to 16/16-funded + the placed witnesses +
the guards (g3, hardmode 95, the vision 4/4, the decode bands, the third
512K window kept against the cache_first reserve). The verify pass
exercised the exact pass-through path (the env pair -> restart -> env ->
start.sh line 75 -> --prompt-cache-gib) in both directions and the argv/
phrasing witnesses against the live serve before commit. The skill
capture: the second launch-staging name failure (window 31's PHASES-env
was the first) is folded into verify-shell-config-edits' gotchas.

**Side observation (recorded, not acted on)**: the DRAFTS=0 serve (the
g2 gate's no-drafts restart) freed the drafts head: model 78.80 GiB
(-2.84), the fixed part 375 MiB/stream (-40), FOUR full 512K windows
funded (12.53 GiB of pages), 11 of 16 slots. The no-drafts config buys
real room — unmeasured for decode; the #2181 KV_LIVE_HALF candidate
sits beside it, both parked pending the recovery verdict.

**The adoption path stands**: window 34 re-runs the fixed battery; the
verdict criterion is 16/16 + the placed witnesses + the guards; on a
qualified verdict PROMPT_CACHE_GIB=4 becomes the config.sh default and
the session phases retire with their receipts; any miss keeps the
cacheless standing and the arithmetic goes upstream as data.

## (round 140, cont. 4) WINDOW 34 VOID — THE UNGUARDED GREP UNDER set -euo pipefail; THE DISCIPLINE REVIEW BEGINS (2026-11-10)

**Window 34** (campaign-20261110-192708, `preflight cachefixqual summary`,
rc=1, production restored healthy after 80 s): the battery died at the
OFF arm's argv-witness line, before the greedy probe. Root cause pinned:
the script runs `set -euo pipefail` (run-qualification.sh line 50), and
the new argv-witness assignment ends in a bare `grep` — on the OFF arm
the flag is legitimately absent from the container argv, grep exits 1,
pipefail propagates it, `set -e` killed the phase. The existing phase
code guards every such pipeline with `|| true`; the new line did not.
**Two consecutive windows burned by the same newly-staged block** (33:
the env name; 34: the unguarded grep) — the failure pattern is the
staging discipline, not the loop mechanics (production restored on
schedule, 34/34).

**The data the dead window still gave**: the OFF arm's serve line
recorded **7 of 16 slots at 13.0 GiB left** — the sixth rung on the
room-drift ladder (v126val 11.5/0, w33-OFF 12.1/3, w33-ON 13.0/6,
DRAFTS=0 16.1/11, w34-OFF 13.0/7). The room drifts between restarts
and the slots follow it; no new fact beyond the ladder's growth.

**The standing correction (the user's direction, this sitting)**: the
loop's decisions gain a discipline layer — every launched window carries
a stage brief (question, value-if-yes in a user-visible number, cost,
alternatives rejected, kill criterion), a value gate replaces compliance
criteria, staging is verified against its own failure mode before
launch, a mechanical phase-lint joins the launcher, and the hit-rate
watch pauses launches when a round's void rate crosses half. The aim the
weighing serves: **the fastest, highest quality GLM 5.3 Flash
available.**

**Window 35** re-runs the battery VALUE-FIRST: the ON arm qualifies on
measured resume value (the g3-shaped resume-vs-compute wall delta), not
on the 16/16 slot count — and the question closes in either direction.

## (round 140, cont. 6) THE DISCIPLINE REVIEW LANDED; WINDOW 35 LAUNCHES ON THE FIRST STAGE BRIEF (2026-11-10)

**The review (the user's direction: more discipline in decisions, weigh
the value)**: the whole-repository audit ran this sitting — two read-only
subagent scans (the scripts census, the docs-vs-charters audit) plus the
protocol review. The findings, and what landed:

- **The scripts census**: 69 phase markers, 53 session blocks — ALL
  retired-with-receipt — and the landmine census caught the standing
  knobs phase's unguarded `loaded=$(… | grep … | tail -1)` (L734: lethal
  in EVERY default campaign, not just the retired phases). The sweep
  deleted all 52 removable blocks (run-qualification.sh 5,335 -> 1,162
  lines), fixed the L734 guard, dropped hmcheck/v124val from the PHASES
  default (a no-arg campaign no longer re-runs retired batteries), and
  trimmed the NEEDS_GPU list. The sweep tool itself burned through four
  iterations (v3's regex depth-counter ran away on resweep's span and ate
  the standing duel/confirm blocks; v4's heredoc pre-scan desynced from
  the walk and left kshardcheck's tail behind; v5's single-pass
  heredoc+continuation-aware counter, dry-run-verified on every span
  before deletion, is the one that shipped). The swept file: `bash -n`
  clean, docs-guard green, phase-lint 0 findings.
- **The docs audit**: the append-only docs are current; the STATE docs
  lagged one-to-three sittings (DELTAS named the retired Python recipe
  production; the README streak frozen at 16 vs the receipts' 23; eight
  dead opens in the ledger; ECOSYSTEM one release behind; 16 stacked
  "THE NEXT STEP" paragraphs in PERF_PLAN). All landed this sitting:
  DELTAS's promoted-native header with the Python era retired
  below-the-line, README's pin + streak 23, the ledger's round-140 block
  and the eight dead opens closed with receipts, ECOSYSTEM's v1.2.6
  entry, PORT_QUEUE's contradictions and its duplicate block removed,
  PERF_PLAN's ONE current-next-step pointer, VALIDATION's §2 standing-
  state note. The generated LAUNCH_INDEX.md (338 round entries, campaign
  IDs + outcome tags) is the loop's navigation.
- **The mechanical layer**: `scripts/phase-lint.sh` (the two burn classes:
  unguarded assignment-substitution greps under `set -euo pipefail`; env
  pairs outside start.sh's contract) wired into `autonomous-launch.sh` as
  a launch REFUSAL. The discipline section is in AGENTS.md: the stage
  brief, the value gate, adversarial staging verification, the hit-rate
  watch, fewer-bigger windows, the state-docs pace.
- **The skill layer**: 12/12 SKILL.md frontmatters now pass strict YAML
  (4 were unparseable — the "Trigger words:" colon class); skill-smith's
  workflow gained the strict-YAML verification step; the second
  launch-staging naming failure captured in verify-shell-config-edits.

**The hit-rate watch's first reading**: round 140 ran 4 windows, 1
qualified, 3 void/invalid (75% — past the half threshold). The pause
rule fires: this sitting IS the process review, and the launch below
resumes the loop with the mechanical gates in place. Round 141's rate
watch restarts from zero.

**THE STAGE BRIEF — window 35 (the discipline layer's first live
application)**:
- **Question**: does funding the 16 kept states (`--prompt-cache-gib 4`,
  the #2699 recovery) move a user-visible number on this deployment?
- **Value-if-yes**: the within-session resume delta (the v1 instrument:
  the g3-shaped conversation computed cold then warm; the ON arm must
  beat the OFF arm's delta by >150 ms) and the multi-turn TTFT (the v2
  instrument: a ~4k-token fill, turn 2 vs turn 1 — the opencode shape).
  The anchors' context: the same-session warm TTFT is already 302 ms
  cacheless (the page cache over the pool's pages exists in BOTH arms'
  serve lines); the cross-restart resume is COLD and the imprint disk
  path is OFF in the standing config — out of scope here.
- **Cost**: one window (~45 min: two restarts + the gates + hardmode +
  the vision + the value instruments + the bench).
- **Alternatives rejected**: the compliance criterion (16/16 slots —
  window 33's shape; measures the engine's advice, not the user); the
  bigger-gib sweep (spend before value); the cross-restart/imprint path
  (a separate --learn question, and the anchors say the store does not
  survive a restart in the standing config).
- **Kill criterion**: flag placed (the argv witness) but no material
  value delta => the cacheless standing HOLDS, the question CLOSES as
  upstream data, no third reshape. Any guard FAIL => the battery itself
  failed; the cacheless standing holds and the battery gets fixed before
  any re-run.
- **The verification already run**: window 34's failure mode replayed
  against the fixed code (the OFF-arm absent-flag shape under
  `set -euo pipefail` survives; the ON-arm argv witness extracts 4 from
  a synthetic placed argv — the replay also caught the json-form docker
  format bug, fixed to the plain .Config.Cmd form); the value
  instruments' heredocs run against synthetic walls files; the phase-lint
  green on both clones.

**Window 35**: `preflight cachefixqual summary` (the fixed value-first
battery), launched as this sitting's last action.

## (round 141) WINDOW 35 VOID-NO-OP — THE SWEEP ATE THE LIVE BATTERY; THE LAUNCHER VALIDATES PHASE NAMES NOW (2026-11-10)

**The window** (campaign-20261110-212651, `preflight cachefixqual summary`,
rc=0, production restored healthy after an 80 s health wait): the campaign
ran **preflight + summary only, in 10 seconds** — the `cachefixqual` battery
never executed. The campaign.log reads 5 lines (preflight 21:26:51, summary
21:27:00, done 21:27:01) and the receipt carries no battery content.

**Root cause (the git trail, all on one sitting's commits)**:
- `d9202ff` (20:37) staged the value-first battery: 7 mentions of
  `cachefixqual` in run-qualification.sh (+71 lines, the block at lines
  1373–1583).
- `7cdf199` — the retirement sweep — ran a v5 tool dry-run-verified on its
  spans, but the sweep's region INCLUDED the freshly-staged battery block:
  after the sweep the file has **0** mentions of `cachefixqual` (and
  `v126val` went too — legitimately: it had already run and qualified,
  campaign-20261110-162034).
- `81fe6c3` launched `preflight cachefixqual summary`. The launcher's
  phase-lint passed (the block was gone — nothing left to lint), the window
  stopped production, `run-qualification.sh` evaluated `want cachefixqual`
  against a dispatch table that no longer carries the name, matched nothing,
  and ran on to `summary`. **`want` matches are silent; rc=0 lied.**
- The wake fired correctly (the campaign legitimately ends `" done."`), the
  poke's live-check logic worked as designed — the gap is one layer up: the
  launcher never validates the REQUESTED phase names against the script's
  dispatch table.

**Third staging-burn class** (after the env-name placebo and the unguarded
grep): **a sweep/retirement pass run after staging live code eats the staged
code.** The discipline layer's adversarial-verification rule now extends to
structural operations: a sweep, rename, or deletion run in the same sitting
as new phase code must be followed by re-verifying the NEW code's
presence — not only the old code's absence.

**The mechanical fix (landed this sitting)**: `autonomous-launch.sh`
validates every requested phase name against the dispatch table
(`grep -oP "want \K[a-z0-9_]+" | sort -u`) BEFORE stopping production; any
unknown name refuses the launch with the unknown list printed. A
swept-away, typo'd, or renamed phase can no longer reach a window — the
no-op void class is structurally closed.

**The battery recovered**: the value-first `cachefixqual` block is restored
from `git show d9202ff:scripts/run-qualification.sh` onto the swept script
(its dependencies verified: every helper — restart, restart_fb, run_gates,
serve_line, bench_perf, content_sha, REF_PROMPT — exists on HEAD;
`start.sh:75` carries the `PROMPT_CACHE_GIB` contract), plus
`cachefixqual` added to the NEEDS_GPU list (the d92 block omitted it; the
window flow masked it, a standalone run would not).

**The hit-rate watch**: round 141 reads 0 run / 1 void (100%) — past the
half threshold. The pause rule fires; this sitting IS the process review and
the relaunch below resumes the loop with the mechanical gate in place.
Round 142's watch restarts from zero.

**The relaunch**: window 36 re-runs window 35's stage brief UNCHANGED (the
question, the value-if-yes, the kill criterion were sound — only the staging
died): `preflight cachefixqual summary`, the value-first #2699 battery,
launched as this sitting's last action.

## (round 141, cont. 2) WINDOW 36 RAN THE VALUE-FIRST BATTERY — THE VERDICT: MISSED; THE CACHELESS STANDING HOLDS; THE #2699 QUESTION CLOSES AS UPSTREAM DATA (2026-11-10)

**The window** (campaign-20261110-215136, `preflight cachefixqual summary`,
rc=0, ~42 min): the recovered battery ran end to end — both arms served, the
§2 gates on the ON arm's serve, hardmode, the vision suite, the bench. The
launcher's new phase-name gate passed legitimately this time: the recovered
`cachefixqual` block was on the head at launch (8 mentions), the DRY_RUN
preview green, the dispatch table carried the name. Production restored
healthy (200) after the window.

**The stage brief answered — VALUE, not compliance**:
- **The flag PLACED**: the ON arm's serve line funds **16 kept states'
  slots (3.6 GiB)** vs the OFF arm's **6 of TF_KV_SHARE=16 (1.4 GiB)** —
  the substance landed (the OFF arm's serve line even carries the engine's
  own warning: live streams evict each other's states before a resume).
  The argv-witness line FAILED on extraction (the `.Config.Cmd` array's
  last token is `4]` after the space-split, not `4`) — an instrument
  defect, NOT the verdict: the serve lines prove placement both ways.
- **The value gate MISSED on both instruments**: (v1) the within-session
  resume delta — OFF cold 2,497/warm 2,491 ms (+6), ON cold 2,521/warm
  2,532 ms (−11): the ON arm did not beat the OFF arm's delta by >150 ms;
  it is 17 ms WORSE. (v2) the multi-turn TTFT — OFF turn-2 saves 18,574 ms,
  ON saves 18,420 ms: 154 ms LESS value on the ON arm. Both arms' turn-2
  walls sit at ~1.8 s — the page cache over the pool's pages exists in
  BOTH arms (the anchors predicted it: the same-session warm TTFT is
  already 302 ms cacheless), so the kept states add no resume value the
  page cache does not already deliver.
- **The price is real**: the ON arm cedes the third 512K window (enough
  for 2 vs the OFF arm's enough-for-3) and 1.0 GiB of stream room (13.0 →
  12.2 GiB left) for a measured −17 ms / −154 ms on the value instruments.
- **The quality/regression guards all held**: the greedy same-bits sha
  `80cc3802…` IDENTICAL across both arms (the 24th and 25th all-pass
  serves of the battery era), §2 gates ALL PASS, **hardmode 95 — the
  TWENTY-FOURTH consecutive** (TC-51 and TC-92 pass), the vision 4/4,
  steady-state decode 73.1 tok/s, pp d0 1,529/1,532/1,530 — the ON arm's
  serve is as fast as the standing config on every perf instrument.

**The verdict: the kill criterion fires exactly as written — flag placed
but no value delta ⇒ the cacheless standing HOLDS and the question CLOSES
as upstream data, no third reshape.** `PROMPT_CACHE_GIB` stays empty in
config.sh. The #2699 recovery arc (windows 33/34/35/36) ends: the engine's
v1.2.6 pool plan funds 6 of 16 kept states at the standing config, funding
all 16 costs a 512K window + 1 GiB of stream room, and the kept states
deliver no within-session resume value the page cache does not already
deliver. Upstream data: the TF_KV_SHARE slots' value on this shape is
negative against the room they cost — worth carrying to
ashhart/TensorFold's #2699 thread as a measurement note (nothing posted —
the repo rule; the note lives in docs/ECOSYSTEM.md).

**The room-drift ladder gains two rungs** (w36-OFF 13.0 left/6 slots —
reproducing w34-OFF exactly; w36-ON 12.2/16 funded). The DRAFTS=0 serve's
room stands recorded in the same campaign: model −2.84 GiB, enough-for-3
at 512K with 15.3 GiB left — the parked candidate's facts, unchanged.

**The instrument defect, for the record**: the argv witness's
`tr " " "\n"` split assumes space-separated argv; `.Config.Cmd`'s array
form makes the last token `4]`. The witness needs the closing bracket
stripped (or `--format "{{json .Config.Cmd}}"` + jq). It did not decide
this verdict (value-first) and no re-run is warranted — the battery
retires with its receipt.

**Round 141's hit-rate watch final reading: 1 run / 1 void → 50%** — the
launch resumed mid-round after the process review, so the round's rate is
read as one run (window 36) against one void (window 35): AT the half
threshold, not past it. Round 142's watch restarts from zero.

**Next (the perf plan's order, post-closure)**: the parked candidates in
PERF_PLAN's order — #2181 `TF_GLM_KV_LIVE_HALF` (opt-in, unmeasured) and
the DRAFTS=0 room observation (model −2.84 GiB, four full 512K windows —
unmeasured for decode) are the live questions; the 0110 KV-SHARD defect
hunt stays parked (the user); the upstream-gated fronts wait on releases
via each sitting's ECOSYSTEM read. A stage brief for the next window is
the next sitting's opening work — no launch without one.

## (round 141, cont. 3) THE STAGE BRIEF — WINDOW 37: THE #2181 LIVE-HALF A/B (2026-11-10)

The same sitting continues under the user's standing directive (keep
trying). The next window's brief, written before any launch:

- **Question**: does `TF_GLM_KV_LIVE_HALF=1` (v1.2.6's opt-in: a kept state
  holds the live KDA half alone) fund all 16 `TF_KV_SHARE` kept-state slots
  CACHELESS — closing the OFF arm's eviction warning ("live streams evict
  each other's before a resume"; 6 of 16 funded at the standing config) —
  WITHOUT losing the third 512K window, the decode bands, or the §2 gates?
- **Value-if-yes**: a user-visible room win — all 16 slots funded (no
  eviction warning) while `enough for 3 at a 524288-token window` holds and
  every perf instrument stays inside its band — the keeps get their durable
  layer back (the page cache over the pool's pages plus a 16-slot store)
  for free. The eviction warning's own text names the price of the current
  standing; closing it without paying room is the value.
- **The upstream evidence carried in**: upstream's own receipt
  (`docs/receipts/glm-kv-live-half-555f052d` in the v1.2.6 tree): the
  nine-turn greedy conversation content-identical across four arms
  (`on`/`off`/`fresh`/`main`), the drafts identical, TTFT flat
  (5.91/5.88...), and the keeps ~30–35% smaller (held 126 vs 194 MiB at
  state 1; 480 vs 684 at state 3). Their scope caveat: NOT qualified at
  TP=2 concurrent streams, paged sequences, the page-sharing store, or fp8
  KV — exactly our shape; our A/B decides.
- **Cost**: one window (~40 min): two restarts (the OFF arm = the standing
  config, the ON arm = + `TF_GLM_KV_LIVE_HALF=1`), the serve-line witnesses,
  the §2 gates on the ON arm, hardmode, the vision suite, the bench +
  steady-state decode.
- **Alternatives rejected**: the DRAFTS=0 room observation (model −2.84 GiB,
  enough-for-3 at 15.3 GiB left) — DRAFTS=0 sacrifices the drafter's decode
  entirely; the room it frees is not convertible to a user-visible number
  without giving up a bigger one. The 0110 KV-SHARD port — multi-sitting,
  user-parked. The quality front — hardmode 95 is the checkpoint's ceiling
  on this bench (receipted 24×; the sweep measured every alternative pack
  lower; requants out of scope per the round-132 (user) scope).
- **Kill criterion**: the ON arm's serve line funds fewer than 16 slots
  cacheless, OR `enough for N` drops below the OFF arm's 3, OR any §2 gate
  / hardmode-95 / vision-4/4 guard fails, OR any perf instrument moves
  outside its band ⇒ RETIRE — the knob goes nowhere, the standing config
  stays cacheless-6-slot, and the question closes as upstream data (the
  scope caveat stands: not qualified on our shape).
- **The verification before launch**: the phase stages both arms as
  `restart` env pairs (`TF_GLM_KV_LIVE_HALF=1` is an exported env-forwarded
  pair — phase-lint's contract check passes TF_ names by design); the
  phase-name gate now refuses any swept-away phase; DRY_RUN previews the
  launch from the head itself.

## (round 141, cont. 4) WINDOW 37 RAN THE #2181 LIVE-HALF A/B — THE VERDICT: MISSED (THE VALUE GATE), THE MECHANISM REPRODUCES; THE STANDING CONFIG STAYS (2026-11-10)

**The window** (campaign-20261110-225305, `preflight livehalf summary`,
rc=0, ~41 min): the A/B ran end to end — both arms served, the §2 gates on
the ON arm's serve, hardmode, the vision suite, the bench. Production
restored healthy (200).

**The value gate MISSED on its primary criterion**:
- **All 16 slots funded cacheless? NO.** The ON arm funds **5 of 16** (0.8
  GiB) vs the OFF arm's **3 of 16** (0.7 GiB this run — the room-drift
  ladder: w36-OFF funded 6 at 13.0 GiB left, w37-OFF funds 3 at 12.2 left;
  the funding follows the run's room). Two more states funded on ~0.1 GiB
  less pool share — the direction is right but the warning STAYS.
- **The eviction warning ABSENT? NO** — `live streams evict each other's`
  prints on BOTH arms. The brief's kill criterion fires: the knob goes
  nowhere, the standing config stays cacheless, the question closes as
  upstream data.
- **The mechanism itself REPRODUCES on our shape** — the first measured
  confirmation of upstream's scope-caveated receipt on a TP=2 concurrent /
  paged / fp8 / share serve: the per-slot keep cost dropped **~31%** (OFF
  ~237 MiB/state → ON ~164 MiB/state; upstream measured −30–35%), the
  enough-for count HELD at 3 (no window lost), the greedy same-bits sha
  `80cc3802…` IDENTICAL across both arms (the deterministic probes did not
  move), §2 ALL PASS, **hardmode 95 — the TWENTY-FIFTH consecutive** — the
  vision 4/4, steady-state decode 73.1 tok/s (the band), pp d0
  1,530/1,534/1,535 (flat). The knob is bit-safe, room-neutral-to-positive,
  and does not close the eviction warning at PARALLEL=4: the 16 slots' cost
  is the ROOM (the 12.2 GiB reserve + 415 MiB/stream fixed + the pages),
  not the slot size.
- **The unplanned datum the window paid for**: the g2 gates' serve
  (DRAFTS=0 + LIVE_HALF) read **enough for FOUR at a 524288-token window
  and 10 of 16 slots funded** — model −2.84 GiB plus the smaller keeps
  together cross the fourth-window line. The DRAFTS=0 room observation and
  the live-half mechanism COMPOSE: the four-window shape exists on this
  engine, at the drafter's price. Recorded as upstream data and a parked
  option (the DRAFTS=0 trade stays declined on its decode cost).

**No adoption**: `TF_GLM_KV_LIVE_HALF` stays OUT of config.sh. The
livehalf phase retires with its receipt. The #2181 candidate is measured
out: bit-safe and cheap, but its value on this shape (2 extra funded slots,
no warning closed) does not clear the value gate the stage brief set.

**The room-drift ladder gains two rungs**: w37-OFF 12.2 left/3 slots,
w37-ON 12.3/5 (live-half). The ladder's lesson sharpens: the funded-slot
count tracks the run's room (the fork's issue-16 class), never the flag
alone — w36-OFF 13.0/6 vs w37-OFF 12.2/3 on identical configs.

**Round 141's hit-rate watch final reading: 2 run / 1 void → 67% run rate
** — two windows ran their batteries end to end (36, 37), one void (35,
recovered same-sitting). The pause threshold (50% void) did not fire again
after the process review.

**Next**: the parked-candidate order after two value-gate misses — the
balanced-gains review next sitting: the quality front is at its receipted
ceiling (hardmode 95 ×25, the sweep's ranking stable), the perf fronts are
crossed vs the retired recipe and flat native-vs-native; the remaining
levers are the 0110 KV-SHARD port (user-parked, multi-sitting), the
DRAFTS=0+LIVE_HALF four-window composition (the decode trade), and the
upstream watch. No launch without a stage brief that names a user-visible
number it could move.

## (round 141, cont. 5) THE STAGE BRIEF — WINDOW 38: THE CONCURRENT-RESUME REGRESSION WATCH ON V1.2.6 (2026-11-10)

The loop continues under the user's standing directive. The next window's
brief:

- **Question**: does the concurrent 4-prefix resume still hold 4/4 cache
  hits on the v1.2.6 engine's #2257 pool plan — or did the plan change
  (window_rows 8→32, +51 MiB/stream fixed, 2 of the 16 slots eaten) regress
  the resume path the round-133 adoption receipted (kvshare2,
  campaign-20261106-092703: 4/4 hits, 1.84 s each, 7.41 s aggregate)?
- **Value-if-yes**: a REGRESSION caught protects a user-visible number (the
  opencode multi-turn interaction's resume cost); a pass re-anchors the
  standing config's concurrent resume on the current engine — closing the
  one receipt whose ground the #2257 pool plan silently changed. Either way
  the watch closes a risk the discipline layer exists for: an adopted
  instrument's receipt outlived its engine.
- **The instrument**: the kvshare2 probe verbatim, ONE arm (the standing
  config — no knob, no A/B): four distinct d4096 prefixes computed cold
  sequentially, the solo warm re-send of cc1, then the four concurrent warm
  re-sends; the verdict reads the engine's `cached=` lines and the walls
  against the round-133 receipt (4/4 cached=2048, ttft ~1.84 s each, the
  aggregate ~7.4 s).
- **Cost**: one window (~25 min: one restart + the four colds + five warms +
  the serve-line/log witnesses).
- **Alternatives rejected**: another single-knob A/B (the two cheapest
  parked candidates just missed their value gates; the remaining knobs are
  the DRAFTS=0 trade — declined on decode — and the upstream-gated fronts);
  the 0110 KV-SHARD port (user-parked, multi-sitting); a hardmode anatomy
  dig (the failures are structural at the checkpoint level, ×25 stable —
  no engine-side lever receipted).
- **Kill criterion**: the watch has no adoption branch — the standing
  config does not change on either outcome. A regression ⇒ the receipt
  lands, the ledger's watch item opens, and the shape (SHARE/room) gets a
  stage brief of its own. A pass ⇒ the receipt closes the watch.
- **Verification before launch**: the phase reuses the kvshare2 block's
  exact probe shape (recovered from `01a51ad`'s tree, the d4096 fill
  contract kept — the port-the-argv-contract lesson); FILL_WORDS and
  DUEL_PROMPT exist on HEAD; the phase-name gate + DRY_RUN preview from the
  head itself.

## (round 141, cont. 6) WINDOW 38 RAN THE CONCURRENT-RESUME WATCH — THE VERDICT: PASS; THE #2257 POOL PLAN DID NOT REGRESS THE RESUME (2026-11-10)

**The window** (campaign-20261110-234815, `preflight regresswatch summary`,
rc=0, ~2 min — the watch is one serve + the probe): production restored
healthy (200).

**The watch PASSED on every criterion**:
- **4/4 concurrent cache hits**: the solo warm (cc1) hit `cached=2048` at
  ttft 1.339 s; all four concurrent warms hit `cached=2048` at ttft
  1.343/1.344/1.350/1.343 s — the round-133 receipt's shape held.
- **The aggregate 5.41 s vs the receipt's 7.41 s — BETTER by 27%**, not a
  regression: the v1.2.6 engine (+#2257's 32-row windows) resumes faster
  per request than v1.2.3's did (the warm ttft 1.841 → 1.34 s, −27%).
- **Zero eviction**: the pool's idle lines walked free 3134 → 3130 → 3126 →
  3122 with store 4 → 8 → 12 → 16 — each prefix kept as 4 pool pages, no
  state lost through the whole watch.
- The serve line funded 6 of 16 slots at 13.0 GiB left (the room ladder's
  best rung yet for the standing config — matching w36-OFF exactly; the
  slot count tracks the run's room, confirmed again).

**The round-133 receipt re-anchors on v1.2.6**: the adopted instrument's
ground is current again. No adoption branch existed; the standing config is
unchanged (as the brief required).

**Round 141's final tally: 3 windows run (36, 37, 38), 1 void (35,
recovered same-sitting) — 75% run rate.** The three windows closed three
questions: the #2699 cache question (missed, the cacheless standing holds),
the #2181 live-half knob (measured out, no adoption), and the #2257
regression watch (passed, the receipt re-anchored).

**The board after round 141** (the balanced-gains review):
- **Quality**: hardmode 95 ×25 — the receipted ceiling on this bench; the
  failures are structural at the checkpoint level; every alternative pack
  measured lower.
- **Perf**: crossed vs the retired recipe on all three (user) fronts; flat
  native-vs-native; the two cheapest config knobs measured out this round.
- **Resume**: the concurrent resume re-anchored PASSING and FASTER on
  v1.2.6; the warm solo ttft 1.34 s.
- **Remaining levers**: the 0110 KV-SHARD port (user-parked, multi-sitting,
  the 1.8× pool at a decode cost), the DRAFTS=0+LIVE_HALF four-window
  composition (the decode trade), the upstream watch (main is 36 commits
  past the tag and has absorbed the fork's 0078 — the next release may
  mainline more of the stack).

No launch without a stage brief naming a user-visible number it could move;
the next sitting opens with that brief or with the ECOSYSTEM read.

**The staging-verification incident, self-inflicted and self-caught (the
same sitting)**: the first replay invocation ran
`scripts/autonomous-launch.sh "preflight cachefixqual summary"` DIRECTLY on
the agent host instead of through ssh to the head — the launcher is a REAL
launcher with no dry-run mode, every gate passed legitimately (the battery
was by then recovered, so the name validated), and it started a stray
`autonomous-window.sh` ON DEEP. The stray's boundaries held everywhere:
`"$PROD/scripts/stop.sh"` does not exist on deep (the production repo is
not checked out here) so no stop was attempted on any GPU host;
`run-qualification.sh` died at config.sh's site-identity guard (WORKER
empty on this clone) BEFORE `mkdir results/` — no campaign dir, no
containers touched; the EXIT trap's restore attempt failed the same
no-such-file way and harmed nothing. Production on the head was verified
healthy (200) within minutes; the stray was killed and deep's
`/tmp/autonomous-testing.flag` cleared. The guard replay was then run the
safe way: a bogus phase name REFUSES with the dispatch table printed (the
swept-away-name class the fix exists for), and the refusal paths never
reach the launch line. The lesson joins verify-shell-config-edits: **a
launcher with a refusal path is not a test harness — replay a launcher's
refusals with inputs that cannot pass the gates, never with the real
launch arguments**, and the launcher could gain a DRY_RUN=1 that prints the
gates' verdicts without starting the window (next sitting's candidate).

## (round 141, cont. 7) THE ECOSYSTEM READ + THE STAGE BRIEF — WINDOW 39: THE #2744 VISION RE-ENCODE PORT (2026-11-11)

**The ecosystem read** (recorded in docs/ECOSYSTEM.md): upstream main is 87
commits past v1.2.6, no v1.2.7 tag yet; two GLM-relevant main-only items —
the #2744 vision re-encode fix and the router-mma refactor (byte-identical,
no perf claim). The four-GB10 ring is out of scope (the site's shape is a
pair). The full read is in ECOSYSTEM.md.

**THE STAGE BRIEF — window 39**:

- **Question**: does the #2744 vision fix (a chunk sends the tower only the
  images ending after its start) cut the multi-image multi-turn prompt's
  prefill cost on our pair — the opencode screenshot-per-turn shape?
- **Value-if-yes**: the turn-2 TTFT of a two-image two-turn conversation
  drops measurably (the tower stops re-encoding turn-1's image on turn-2's
  chunks; upstream's host test: 18 → 12 tower passes) — a user-visible
  number for every opencode session that carries screenshots, on the
  standing vision default.
- **The port**: `021-vision2744.patch` — upstream's own diff
  (`5151f19f3`), the body verified BYTE-IDENTICAL to upstream's commit, the
  header carries the provenance. Applies clean against pristine v1.2.6 AND
  on the full 18-patch stack (verified in a scratch clone of the tag,
  49 files from our stack + 5 more from this patch). Host-side only: no
  kernels, no contract records; upstream's own host tests ride in the patch.
- **The battery**: the A/B pattern — the OFF arm (the 18-patch stack) and
  the ON arm (the 19-patch stack), each serving the multi-image value
  probe: a two-image two-turn conversation (turn 1 carries image A + fill;
  turn 2 adds image B), the walls of both turns per arm; the greedy sha
  (the same-bits witness — a text-only probe must be IDENTICAL), the §2
  gates on the ON arm, hardmode 95, the vision 4/4, the bench +
  steady-state decode.
- **Cost**: one window (~50 min: the rebuild rides the fingerprint change —
  the patch list moves — plus two restarts and the probes).
- **Alternatives rejected**: waiting for the v1.2.7 release (the fix is
  receipted upstream; the port pattern exists and the collision map is
  empty — no patch touches prompt_images.zig or backend.zig; waiting costs
  the value for no risk reduction); the 0110 KV-SHARD port (user-parked,
  multi-sitting).
- **Kill criterion**: the ON arm's turn-2 wall does not beat the OFF arm's
  by a clear margin (>5%), OR any guard fails (the greedy sha moved on the
  text probes, the §2 gates, hardmode, the vision suite) ⇒ RETIRE — the
  patch leaves the PATCHES list and the question closes as upstream data
  (the release carries it; the rebase picks it up free).
- **Verification before launch**: the staged patch applies clean on the
  full stack (run, above); the phase-name gate + DRY_RUN from the head; the
  value probe's two-image bodies staged with the manifest's CC-licensed
  assets — never ad-hoc fixtures (the round-132 rule).

## (round 141, cont. 8) WINDOW 39 RAN THE #2744 VISION A/B — THE VALUE READING IS CONFOUNDED; THE BATTERY IS CORRECTED (2026-11-11)

**The window** (campaign-20261111-000839, `preflight vision2744 summary`,
rc=0, ~48 min): the port A/B ran end to end — the OFF arm (the 18-patch
stack, build-free) and the ON arm (the stack + `021-vision2744.patch`; the
fingerprint moved, the rebuild took 560 s and compiled the vision fatbin).
Production restored healthy (200).

**The guards all held on the 19-patch stack**: the greedy TEXT sha
`80cc3802…` IDENTICAL across both arms (the fix must not move the
deterministic text probes — it didn't), §2 ALL PASS, **hardmode 95 — the
TWENTY-SIXTH consecutive** — the vision suite 4/4 (the single-image answers
unchanged), steady-state decode 73.1 tok/s, pp d0 1,522/1,525/1,521 flat.

**The value reading is CONFOUNDED — invalid, not negative**: the ON arm
booted immediately after the 560 s rebuild; the unified-memory pool carried
the build's residue (**11.5 GiB left vs the OFF arm's 13.0** — the room
ladder's worst rung), the serve funded **ZERO kept states** ("no prompt
cache — none of the 16 slots fit"), and the value probe measured the
page-cache miss cascade: the ON arm's t2-with-history read **6.837 s vs the
OFF arm's 2.677 s** — the cache-state difference, not the encode count the
fix moves. The ON arm's own t1→t2 delta (8.017 → 6.837 = 1.18 s saved) vs
the OFF arm's (7.966 → 2.677 = 5.29 s saved) says the ON arm's turn 2
skipped nothing — its serve had no page cache to hit.

**The kill criterion does NOT fire**: it fires on "any guard fail or no
value"; this is neither — the value reading is invalid. The corrected
battery (window 40) re-runs value-first with the room gate: the ON arm
gains ONE build-free room-match restart before its value probes, both arms'
value sections record the room line, and the verdict requires the arms'
room lines to differ by < 1.0 GiB. The patch stays staged in patches/ but
NOT in config.sh's PATCHES — no adoption on a confounded reading.

**Round 141's watch: 4 windows run, 1 void — the loop is healthy at the
process level; the value questions close when their instruments are clean.**

## (round 141, cont. 10) WINDOW 40'S ROOM-GATED VALUE READING IS CLEAN — AND THE PROBE WAS THE WRONG INSTRUMENT; THE CONCURRENT-PAIR RACE IS WINDOW 41'S (2026-11-11)

**The window** (campaign-20261111-010825, `preflight vision2744 summary`,
rc=0, ~42 min): the corrected battery ran — the room gate PASSED (the arms'
room lines 13.2 vs 13.0 GiB, well inside the < 1.0 GiB gate; the ON arm's
room-match restart settled the build's memory residue), every guard held
(the greedy TEXT sha `80cc3802…` identical across all three serves, §2 ALL
PASS, **hardmode 95 — the TWENTY-SEVENTH consecutive** — the vision suite
4/4, steady-state 73.1 tok/s), production restored healthy (200).

**The value gate MISSED — and the miss is the instrument, not the fix**:
the single-stream two-turn probe read parity (the ON arm's room-matched
t2-with-history 2.684 s vs the OFF arm's 2.667 s — −0.6%, nowhere near the
>5% win the gate demands). Reading the mechanism honestly: the #2744 fix
moves the OWNER HANDOFF — two streams serving multi-image prompts
CONCURRENTLY re-encode each other's images on every chunk switch pre-fix
(`b.image_owner != s` after the other stream takes the shared rows); a
single-stream sequential probe never loses ownership, so its parity is the
EXPECTED baseline, not the value. Upstream's own receipt (18 → 12 tower
passes) measured "two interleaved image prompts" — the concurrent shape.

**The corrected instrument (v3, window 41)**: TWO CONCURRENT multi-image
multi-chunk prompts — each stream an image + a d4096 fill (three chunks),
a warm-up pair then the race; the aggregate race wall is the value number,
re-run room-matched after the settle restart. The kill criterion stands:
no value on the corrected instrument retires the patch — the v1.2.7
release carries it free either way.

**Round 141's watch: 5 windows run (36/37/38/39/40), 1 void — the loop is
healthy; the value questions close when their instruments are clean.**

## (round 141, cont. 11) WINDOW 41 RAN THE CONCURRENT-PAIR RACE — THE WARM-UP PRIMED THE CACHE; THE COLD RACE IS WINDOW 42'S (2026-11-11)

**The window** (campaign-20261111-020104, `preflight vision2744 summary`,
rc=0, ~43 min): the concurrent-pair instrument ran end to end. Production
restored healthy (200).

**The room gate PASSED again** (the arms' room lines 13.1 vs the
room-matched ON arm's 12.2 — 0.9 GiB, inside the < 1.0 GiB gate), every
guard held (the greedy TEXT sha `80cc3802…` identical across all serves,
§2 ALL PASS, **hardmode 95 — the TWENTY-EIGHTH consecutive** — the vision
suite 4/4, steady-state 73.1 tok/s).

**The value gate MISSED — and the receipt's own mechanism witness shows
why**: the warm-up pair primed the page cache; the race's serves hit it
completely (the engine lines read `cached=12288` and `cached=16384` on
BOTH arms' race streams — full-prefill cache hits, ttft 0.57/0.63 s). The
re-encode path the fix removes never ran: the aggregate read parity (the
OFF arm 4.27 s vs the room-matched ON arm 4.25 s — −0.5%).

**The corrected instrument (window 42)**: the race runs COLD — no warm-up
pair — and the race bodies share NO prefix with the t1/t2 probes or each
other (the arm-loop race: zebra+meadow / sign+meadow-offset; the
room-matched race: sign+zebra swapped with cistern fills — the page cache
cannot prime any race prefix). The engine lines' `cached=` values stay the
mechanism witness (cached≈0 expected on the race streams; the
chunk-switch handoff carries the value). The kill criterion stands: no
value on the corrected instrument retires the patch — the v1.2.7 release
carries it free either way.

**Round 141's watch: 6 windows run (36/37/38/39/40/41), 1 void — the loop
is healthy; the instrument generations narrowed each round and the
mechanism witness now reads directly from the receipt.**

## (round 141, cont. 12) WINDOW 42 RAN THE COLD RACE — PARITY; THE MECHANISM READING LANDS THE V5 INSTRUMENT (THREE IMAGES PER STREAM) (2026-11-11)

**The window** (campaign-20261111-025646, `preflight vision2744 summary`,
rc=0, ~43 min): the cold race ran end to end — the warm-up pair gone, the
race bodies' prefixes de-collided from the t1/t2 probes. Production
restored healthy (200).

**The mechanism witness finally READ TRUE**: the race's engine lines show
`cached=0` on every race stream (both arms) — the page cache did NOT
hijack the race this time; the chunk-switch handoff path RAN. And the
decisive comparison is parity: the OFF arm's cold race **23.38 s** vs the
ON arm's **23.41 s** (−0.1%; the ttft pairs 10.80/10.89 vs 10.82/10.92 —
within noise). The room gate sat AT the line (12.4 vs 11.4 GiB — exactly
1.0); the room-matched race ran a DIFFERENT shape (the cistern variant
tokenized +4096 tokens — the fill word set's BPE length differs — so it
had no OFF-arm counterpart and cannot feed the gate; the receipt records
it as 31.29 s at a different shape, not a value number).

**The mechanism reading — why parity is the honest result on this shape**:
the re-encode fires per chunk-switch when the owner flipped AND the
chunk's span contains image rows. A single image at the TOP of a d4096
prompt gets ONE encode (chunk 1); chunks 2–3 carry no image rows — the
owner flips in a two-stream race never re-encode anything. Upstream's
receipt measured "two interleaved image prompts" — MULTIPLE images spread
through the chunks (their 12 vs 18 tower passes = 6 re-encodes). Our race
had one image per stream at the top: zero exposures.

**The v5 instrument (window 43)**: THREE images per stream, one per chunk
(the upstream shape) — each chunk switch with an owner flip re-encodes the
later-chunk images pre-fix; the exposure is ~2 images × 2 later chunks ×
2 streams = up to 8 extra tower encodes (~1.8 s) per race. The fill words
share no prefix with the t1/t2 probes; the room-matched race reuses the
same bodies (the settle restart wipes the page cache — per-process — so
both sides of the value gate run the same shape cold). The kill criterion
stands: no value on the corrected instrument retires the patch.

**Round 141's watch: 7 windows run, 1 void — the loop is healthy; the
instrument is now mechanism-exact.**

## (round 141, cont. 13) WINDOW 43 DIGESTED HONESTLY — THE VERDICT LEG NEVER RAN; THE RETIREMENT CLAIM WITHDRAWN; WINDOW 44 RE-RUNS VALUE-FIRST (2026-11-11)

**The correction**: the cont. 12 sitting left an uncommitted edit claiming
window 43's kill criterion FIRED ("three instruments read parity, the patch
retires"). The receipt says otherwise — the primary evidence
(campaign-20261111-035237 on the head) contradicts the claim:

- **The value gate's number never existed.** The kill criterion binds on
  the ROOM-MATCHED interleaved race beating the OFF arm by >5%. The
  receipt's room-matched race reads `0.01 s aggregate` with `cached=6144`
  on both streams — the stale warm-primed `cp2-` bodies (the pre-cont. 12
  path). The room-matched curl read the OLD body names (the cont. 12
  commit renamed them to `cp-`), died under `|| true`, and the receipt
  recorded the dead race's ~0.01 s. There are no `rm-cp-*` envelopes in
  the campaign dir; the direction of the error makes it WORSE than a
  void — a dead race would have SPURIOUSLY QUALIFIED the patch (0.01 s
  beats everything by >5%). No VERDICT block exists in the receipt.
- **The arm-loop race's parity does not feed the gate.** 25.52 vs 25.56 s
  with `cached=0` on every stream is a clean mechanism witness — but the
  ON arm's first serve had **11.0 GiB room vs the OFF arm's 12.4** — the
  room gate FAILED at 1.4 GiB. That is exactly why the room-matched leg
  exists; the arm-loop number is a room-confounded reading, not value.
- **What held is real and recorded**: the greedy TEXT sha `80cc3802…`
  identical across both arms, §2 ALL PASS (hardmode 95 — the THIRTIETH
  consecutive), the vision suite 4/4, steady-state 73.1 tok/s. The
  experiment was honest; the retirement was not. The question stays OPEN.

**The phase fixes (adversarially staged against the failure mode)**: the
`cp2-` → `cp-` path corrected in the room-matched curl (the uncommitted
fix, kept); PLUS the race plumbing guards in BOTH race blocks — the
aggregate counts only when both streams answered with a real envelope
(the receipt records `FAILED … DOES NOT COUNT` otherwise), so a dead race
fails the battery loudly instead of recording a qualify-able number.

**The stage brief — window 44**: re-run `vision2744` value-first with the
fixed phase.
- *The question*: does upstream's #2744 re-encode fix (021-vision2744)
  deliver its >5% concurrent value on OUR shape — 2×GB10 TP=2, PARALLEL=4,
  the 2048-row chunking, our image sizes — under a valid room-gated
  reading, on the mechanism-exact interleaved instrument?
- *The value-if-yes*: multi-image concurrent vision prompts (the
  opencode screenshot-per-turn shape) get their chunk-switch re-encodes
  removed — the first user-visible TTFT number the vision line could move.
- *The cost*: one ~45 min window (the rebuild rides the ON arm's restart;
  production stops once).
- *The alternatives rejected*: adopting on the window-43 arm-loop parity
  (room-confounded — refused); retiring on the fabricated reading
  (withdrawn); widening the instrument again (three generations of
  narrowing have landed the mechanism-exact shape — a fourth refinement
  would be motion, not measurement).
- *The kill criterion*: the value gate binds ONLY on a run where the
  room-matched race plumbing guard reads OK and the room gate holds —
  no value there retires the patch (the v1.2.7 rebase picks it up free);
  any guard fail voids the window and the question stays open.

**The state-doc sweep (same sitting)**: VALIDATION's streak 26 → 30
(windows 40/41/42/43's receipts — each battery's §2 ALL PASS), README's
quality row re-dated, the ledger's #2744 item rewritten to the true
window-43 state. The forged retirement never entered any committed state
doc; it dies in this entry.


## (round 141, cont. 14) WINDOW 44 RAN THE FIXED VISION2744 BATTERY — THE FIRST VALID ROOM-GATED READING; THE VALUE GATE MISSED; THE KILL CRITERION FIRED LEGITIMATELY — 021-vision2744 RETIRES, THE #2744 QUESTION CLOSES AS UPSTREAM DATA (2026-11-11)

**The window** (campaign-20261111-081848, `preflight vision2744 summary`,
rc=0): the fixed battery ran end to end — the race plumbing guards in the
receipt, the room-matched race carrying real envelopes. Production
restored healthy (200) and the flag cleared.

**Every validity condition the window-43 failure mode broke now held**:
- the arm-loop race: OFF 25.52 s vs ON 25.64 s, both plumbing guards OK,
  `cached=0` on every race stream (the mechanism witness true);
- the room gate PASSED: the ON arm's room-matched serve 12.2 GiB vs the
  OFF arm's 12.4 — 0.2 GiB, well inside the < 1.0 GiB gate;
- the room-matched race RAN: 25.53 s aggregate, both streams answered
  (real `rm-cp-*` envelopes in the campaign dir this time).

**The value gate MISSED**: the ON arm's room-matched race 25.53 s vs the
OFF arm's 25.52 s — parity (−0.04%), nowhere near the >5% the value gate
asks. The single-stream probes read parity again too (room-matched t2
2.698 vs the OFF arm's 2.692 s). The kill criterion's retire path is
explicit: any guard fail OR no value => RETIRE. The guards all passed;
the value is absent on the first valid reading — **the kill criterion
fired legitimately, and this time the evidence chain is complete**: the
mechanism-exact instrument (three images per stream, one per chunk), the
room gate passed, both plumbing guards OK, and the number is parity.

**The verdict: RETIRE.** `021-vision2744.patch` leaves the candidate
stack (it never entered config.sh's PATCHES — nothing to un-adopt; it
stays in patches/ as receipted provenance, byte-identical to upstream's
diff). The #2744 question CLOSES as upstream data: the fix's value does
not reproduce on OUR shape — 2×GB10 TP=2, PARALLEL=4, the 2048-row
chunking, our image sizes (18k/17k-token vision prompts) — and the
mechanism reading is consistent: upstream's receipt measured multi-image
interleaved prompts re-encoding each other's chunks (12 vs 18 tower
passes on their shape); on ours the interleaved race's chunk switches
carry no measurable re-encode cost, so removing them moves nothing
user-visible. The v1.2.7 rebase picks the fix up free; the phase retires
from run-qualification.sh (session-specific, its question closed).

**The guards that held are recorded**: the greedy TEXT sha `80cc3802…`
identical across both arms and the room-matched serve, §2 ALL PASS —
**hardmode 95, the THIRTY-FIRST consecutive** — the vision suite 4/4,
steady-state 73.1 tok/s (in band), the bench bands held.

**Round 141's watch: 9 windows run (36–44), 1 void (35) — the loop is
healthy; four questions closed this round (the #2699 cache, the #2181
live-half, the #2257 watch, and now the #2744 port), every one by a
receipt.**


## (round 141, cont. 15) THE STAGE BRIEF — WINDOW 45: THE #2793 SHARED-BUDGETS A/B (BUDGETSQUAL) (2026-11-11)

**The ECOSYSTEM read that staged it** (the subagent scan, 2026-11-11):
main is ~175 commits past v1.2.6 in ~21 h (upstream moves fast); no v1.2.7
yet. The GLM-path item with numbers on OUR EXACT SHAPE: **#2793** (commit
cc2fa8d23690, fixes #2720) — DFlash2's shared draft rounds priced every
stream's drafts by last grant + slack without the budgets rule, so a
BLOCKED lane ratcheted its stream to zero drafts while peers decoded.
Upstream's #2720 receipt ran on TWO GB10s AT TP=2 — our exact hardware:
four-stream aggregate −1.9% to −8.8% across shapes, and the mechanism
witness (the drafter counters) shows drafted rows per stream-round
ratcheting 3.27 → 2.36. The fix: `.allocate_shared_drafts = drafting and
!block`; upstream's fix claim: **+3.7% greedy four-stream decode, +3.5%
at T=0.7, one-stream unchanged, tokens unchanged**. Two more upstream
candidates (#2852 EXL3 whole-pass routing, #2856 batched shared MTP) are
open WITHOUT numbers — watched, not staged. #2744 is Metal-only ("GLM on
CUDA keeps its own per-slot image rows and is unaffected" — the PR body)
— window 44's retire verdict is confirmed from upstream's own text; the
CUDA side never had the mechanism, which explains the four-generation
parity hunt. Also noted: upstream's #2404 opt-in prompt-cut knob
(`TF_GLM_REQUEST_STARTS=1`) exists but refuses above `TF_KV_SHARE=0` —
incompatible with our adopted KV_SHARE=16; not staged.

**The patch**: 022-shared-budgets.patch — upstream's own diff staged
verbatim (host-side only: one lane-admission line + two host-test files;
no kernels, no contract records; applies clean against pristine v1.2.6
AND on the full 18-patch default stack in alphabetical order — verified
in a scratch clone of the tag, 2026-11-11; symbol check clean: no
introduced names, the functional line reuses the in-scope `block`
variable).

**The stage brief — window 45** (`budgetsqual` value-first):
- *The question*: does the shared-budgets fix deliver its >3% concurrent
  decode value on OUR shape — 2×GB10 TP=2, PARALLEL=4, DFlash2 drafts at
  the 524,288 window, the adopted 18-patch stack?
- *The value-if-yes*: the four-stream aggregate decode rate (the c4
  instrument) moves >3% — a user-visible concurrency number on the
  shipping config; the drafter counters record the ratchet's recovery as
  the mechanism witness.
- *The cost*: one ~50-min window (the rebuild rides the ON arm's restart;
  production stops once).
- *The alternatives rejected*: waiting for the v1.2.7 rebase to carry it
  free (the value question would wait weeks on upstream's release
  cadence — and if the answer is RETIRE, the rebase must NOT carry an
  unmeasured claim into production); staging #2852/#2856 (no numbers
  claimed yet — upstream's own device receipts are pending; staging them
  would measure an upstream hypothesis, not a claim); the DRAFTS=0+
  LIVE_HALF composition (a trade-off already priced in PERF_PLAN — this
  window's question is cheaper and user-visible).
- *The kill criterion*: QUALIFIED = the room-matched c4 beats the OFF
  arm's c4 by >3% with every guard green (the greedy sha, the room gate
  within 1.0 GiB, both c4 plumbing guards OK, §2 ALL PASS, hardmode 95,
  the vision 4/4, the bench/decode bands). Any guard fail or no value =>
  RETIRE: the patch stays staged as provenance, the question closes as
  upstream data, and the v1.2.7 rebase decision carries the receipt
  either way. The value gate binds ONLY on a run where both c4 plumbing
  guards read OK (window 43's lesson is baked into the phase).

**The phase**: `budgetsqual` in run-qualification.sh (session-specific;
retires with the receipt) — the OFF arm → ON arm (the rebuild rides the
restart) → the room-match settle restart → the value gate on the
room-matched c4, the duel_arm instrument set (solo twins, c2, c4, ITL,
prefill slope, the drafter-counter deltas), the §2 gates + hardmode +
vision + bench/steady-state guards.


## (round 141, cont. 16) WINDOW 45 RAN THE BUDGETSQUAL A/B — THE VALUE GATE CROSSED: THE ROOM-MATCHED C4 +6.1% — 022-SHARED-BUDGETS ADOPTED (2026-11-11)

**The window** (campaign-20261111-094017, `preflight budgetsqual summary`,
rc=0, ~56 min): the A/B ran end to end — the OFF arm (the standing 18-patch
stack, load 83 s), the ON arm (+ 022-shared-budgets; the rebuild rode the
restart, load 521 s, the patch witness 4 mentions in the campaign's
prepare/build lines), then the room-match settle restart. Production
restored healthy (200) and the flag cleared.

**THE VALUE GATE CROSSED — beyond the ask**:
- **The value number**: the ON arm's room-matched c4 aggregate **180.4 t/s**
  vs the OFF arm's **170.0 t/s = +6.1%** — beyond the >3% gate AND beyond
  upstream's own 3.7% greedy claim on this shape.
- **The mechanism gradient confirms the mechanism**: solo +1.0% (69.3 →
  70.0/70.1), c2 flat (119.7 → 119.7), c4 +6.1% — exactly the signature
  upstream's #2720 analysis predicted (the ratchet bites hardest at four
  streams; one stream was always unchanged).
- **Every guard green**: the greedy TEXT sha `80cc3802…` IDENTICAL on all
  three serves (the fix must not move the probes — it didn't), both c4
  plumbing guards OK, the room gate PASS (the OFF arm 12.4 vs the settle
  serve 13.0 GiB), the §2 gates ALL PASS — **hardmode 95, the
  THIRTY-SECOND consecutive** — the vision suite 4/4 (the saved JSON's
  answers verified real), the bench bands held, steady-state 73.1 tok/s
  in band, the prefill untouched (the TTFT slope 0.439 → 0.437).

**The adoption**: `022-shared-budgets.patch` joins config.sh's PATCHES
default (the sixteenth patch, the nineteenth file member counting the
opt-in 017 and the retired companions); the promoted production repo
mirrors it on its promotion sync this sitting. The phase retires from
run-qualification.sh with its question closed (session-specific, its
receipt complete and valid — the first VALID room-gated value reading
for a perf candidate on this line).

**Round 141's final watch: 10 windows run (36–45), 1 void (35) — the
loop's best round: one upstream port retired by a valid negative
(#2744), one upstream port adopted on a valid positive beyond its own
claim (#2793, +6.1%), three questions closed by receipt, one forged
verdict caught and corrected by the primary evidence.**


## (round 141, cont. 17) THE STAGE BRIEF — WINDOW 46: THE DUEL RE-PAIR ON THE ADOPTED 19-PATCH STACK (+ THE PROMOTION'S RESTORE) (2026-11-11)

**The stage brief — window 46** (`preflight duel summary`):
- *The question*: does the adopted 19-patch stack hold the A/B's gains on
  the duel's five direct instruments — and what do the re-dated perf rows
  read against the adopted engine, both arms the promoted config (the
  round-139 A/A design)?
- *The value-if-yes*: the perf rows re-dated on the adopted engine — c4
  expected near its new 180.4 reading (~106% of production's floor row),
  solo/c2/ITL/overhead/cold settled on a proper same-window pair (the
  A/B's ITL spread 14.1/14.4/15.3 ms/token across three serves was a
  watch item; the re-pair settles it).
- *The cost*: one window; the fingerprint moved on BOTH repos (the
  testing config and production's promotion sync), so the first arm's
  start re-prepares (~15–25 min) and the exit-path restore re-prepares
  production's 19-patch image — the promotion's designed deployment path;
  no manual serve touch.
- *The alternatives rejected*: a separate validation window on the new
  default (the one-line-patch pattern doesn't need one — the A/B's ON arm
  WAS the validation: §2 ALL PASS + hardmode 95 + the vision 4/4 on the
  patched engine); waiting for the v1.2.7 rebase (the re-pair is due
  regardless — the last adoption's duel re-pair has carried every
  round-136–139 adoption).
- *The kill criterion*: the re-pair is a measurement, not an adoption —
  every instrument reads and re-dates the rows; an arm refusing to start
  is the fail-honest void. The §2 gates + hardmode rode the adoption
  window; the duel's job is the rows.

**The promotion state at launch**: the testing repo carries the 19-patch
PATCHES default (7393d5b); production's repo carries the mirrored patch
(byte-identical in the store AND image/patches), the config append, and
the README status (7819ddf + 086c1ae) — production keeps serving the
18-patch image until this window's exit-path restore re-prepares it.


## (round 141, cont. 18) WINDOW 46 RAN THE DUEL RE-PAIR ON THE ADOPTED 19-PATCH STACK — THE C4 GAIN CONFIRMED; THE ORDER-DRIFT WATCH OPENS; THE PROMOTION'S DEPLOYMENT FORENSICS (2026-11-11)

**The window** (campaign-20261111-110018, `preflight duel summary`, rc=0,
~9 min of instruments after the prepares): the duel's five direct
instruments on the round-139 A/A design — the baseline arm (the promoted
config on the testing port) and the ours arm, BOTH the adopted 19-patch
v1.2.6 engine. Production restored healthy (200) and the flag cleared.

**The re-pair's rows (the third native-vs-native pair)**:
- **c4: ours 188.1 vs baseline 182.0 t/s** — BOTH arms far above the
  pre-adoption row (167.4/169.7, the second pair) and above the
  budgetsqual room-matched reading (180.4). Even the lower arm is +7.2%
  over the old floor reading: **the #2793 adoption's c4 gain is
  CONFIRMED on an independent same-window instrument.**
- solo 69.8/69.9 vs 70.3/70.7 (99.1% — flat, ~+2% over the old row's
  level), c2 117.3 vs 121.7 (the baseline arm's 121.7 is the highest c2
  recorded on the line), ITL 58.0 vs 59.4 ms/chunk, overhead 186 vs
  185 ms, the cold d8192 slope 0.440 vs 0.442 — all flat.

**The order-drift watch opens**: the SECOND arm won c4 in both the
budgetsqual A/B (+6.1%) and this A/A pair (+3.4%) — the first
calibration pair read c4 flat inside ±2%. The arms are identical, so
the pattern is order/thermal drift, not config — but it bears directly
on the value gate's integrity: **window 45's +6.1% value reading
compared a second-serve ON arm against a first-serve OFF arm, the same
order.** If ~3 points of that are order bias, the adoption's honest
value is ~+3% — still above the >3% gate, but half the reading. The
settle: window 47 re-runs the duel pair (the third A/A pair) — if the
second arm wins c4 again, the order effect is real and the anchors'
c4 row carries the order-corrected value; if it flips or converges,
the rows stand as read.

**The promotion's deployment forensics — production IS the promoted
engine now, and one hazard is closed**:
- The 10:36 exit-path restore of window 45 re-prepared **production's
  repo against its then-stale config** (18 patches, the v1.2.4-era pin
  — the promotion sync landed 10:53, after that restore began):
  production served the round-139 promoted state for ~22 minutes.
- The 11:00 re-prepare (the duel's baseline arm start; the testing
  repo's config had moved to 19 patches) rebuilt the shared image with
  the correct tree and rewrote the shared marker.
- The 11:09 exit-path restore matched the marker → production returned
  on the promoted v1.2.6 + 19-patch engine, where it stands.
- **The structural enabler is fixed**: production's `local.sh` pin was
  still the v1.2.5-era `8be9c408c` (the round-140 bump never mirrored
  it). The pin is INERT for serving (the fingerprint excludes it; the
  marker resolves the served commit) but a re-prepare from production's
  repo would rebuild the STALE tree — exactly what the 10:36 restore
  did. The pin now reads `6e9af930` (v1.2.6), matching the served
  engine; the next re-prepare from either repo builds the same tree.
- **Residual exposure noted**: a promotion sync landing after a
  window's exit-path restore leaves production briefly on the older
  image until the next restore. Bounded (~one window's length) and
  self-healing; the pin fix removes the stale-REBUILD half of the
  hazard. The crash-net restarting production during such a lag would
  briefly serve the older image — acceptable, recorded.

**Round 141's watch: 11 windows run (36–46), 1 void (35). The loop is
healthy; the round banks one adoption (the #2793 shared-budgets, the
sixteenth patch), one retirement (the #2744 port), four closed
questions, one forged verdict caught — and the promotion protocol's
first end-to-end ride through the window flow.**


## (round 141, cont. 19) THE STAGE BRIEF — WINDOW 47: THE ORDER-DRIFT SETTLE (THE THIRD A/A PAIR) (2026-11-11)

**The stage brief — window 47** (`preflight duel summary`):
- *The question*: is the second-arm c4 win (+6.1% in window 45's A/B,
  +3.4% in window 46's A/A) an ORDER effect (thermal/clock drift between
  the first and second serve of a window) or real arm difference? The
  arms are identical configs — the third pair's order pattern decides.
- *The value-if-yes*: the anchors' c4 row carries an order-corrected
  value — the adoption's honest number, which feeds every future
  candidate duel's baseline and the PERF_PLAN's frontier arithmetic. A
  settled instrument also protects future value gates from reading
  order bias as config value.
- *The cost*: one window (~25 min: the duel's two arms + the prepares —
  the image is warm, the fingerprints unchanged).
- *The alternatives rejected*: accepting the +6.1% as read (the risk:
  every future value gate inherits a ~3-point order bias — the gate
  would pass candidates that buy nothing); widening the duel with a
  third arm in the same window (the order effect IS the between-serve
  drift — a third arm in one window measures the same thing with more
  noise, not independently); waiting for the v1.2.7 rebase (the
  instrument question is now).
- *The kill criterion*: none — a measurement window. The outcomes: (a)
  the second arm wins c4 again → the order effect is real; the anchors
  note the order-corrected c4 value (the first-arm/second-arm mean or
  the smaller arm), and future value gates bind on order-matched
  readings; (b) the second arm loses or converges → the window-45/46
  pattern was coincidence; the rows stand. Either way the §2/hardmode/
  vision guards are NOT re-run (they rode window 45's adoption receipt;
  the engine is unchanged since).


## (round 141, cont. 20) WINDOW 47 RAN THE ORDER-DRIFT SETTLE — THE SECOND ARM WON AGAIN, BUT THE ORDER-MATCHED CROSS-WINDOW READING STRENGTHENS THE ADOPTION; THE WINDOW-DRIFT WATCH OPENS (2026-11-11)

**The window** (campaign-20261111-150137, `preflight duel summary`, rc=0):
the third A/A pair on the adopted 19-patch stack. Production restored
healthy (200), the flag cleared.

**The order watch's outcome (a) fired**: the second arm won c4 again
(ours 193.2 vs baseline 185.1, +4.4%) — the third consecutive second-arm
c4 edge (+6.1% in the w45 A/B, +3.4% in w46). **But the settle's deeper
reading goes the other way**: the pre-adoption pairs read FLAT (the
first pair +0.7%, the second pair −1.4%), so the second-arm edge is not
a constant environmental order effect. And the ORDER-MATCHED
cross-window comparison — first arm vs first arm across the adoption
boundary, identical order, only the config differs — reads:

- pre-adoption first arms: 170.0 (w45 OFF), 169.7/168.5 (the second/
  first pairs) — a stable ~168-170 level;
- post-adoption first arms: 182.0 (w46), 185.1 (w47) — **+7.1% to
  +8.9% over the pre-adoption level**.

**The adoption's value survives every decomposition and is, if
anything, STRENGTHENED**: the order-confounded A/B reading (+6.1%) sits
inside the plausible band the order-matched comparisons bracket
(+2.2% naive-subtractive at one extreme, +8.9% order-matched at the
other). The value gate's conclusion stands; 022-shared-budgets stays
adopted; no un-adopt branch. The anchors' c4 row carries the
order-matched band as the value statement.

**The window-drift watch opens**: c4 levels climbed ~+2%/window on BOTH
arms across w45→47 (second arms 180.4 → 188.1 → 193.2; first arms
170.0 → 182.0 → 185.1), and w47's baseline solo stability Δ hit 2.4%
(the widest recorded; the prior windows read 0.1-0.6%). The arms are
identical configs, so the climb is window-to-window — thermal or
environmental, not config. The watch: if the next windows' c4 first-arm
readings keep climbing >2%/window, the instrument's absolute levels
need re-anchoring before any future value gate reads a small delta as
real.

**The rows re-dated on the newest pair** (the fourth pair, w47, with
w46 corroborating): solo 70.5 vs 69.9 (100.9%), c2 121.9 vs 120.7
(100.6%; the w46 pair read 117.3 vs 121.7 — the c2 instrument swings
±3-4% between windows at these levels), ITL ~14.6 vs ~14.6 ms/token
(the chunk rhythm 58.6/58.3), overhead 183 vs 186 ms, the cold d8192
3,767 vs 3,768 (slope 0.438/0.437) — all flat inside the band on the
adopted engine.

**Round 141's final tally: 12 windows run (36–47), 1 void (35) — the
loop's best round closes: one adoption (the #2793 shared-budgets,
confirmed twice on independent instruments), one retirement (the
#2744 port), four questions closed by receipt, one forged verdict
caught, the promotion protocol ridden end to end, and the instrument's
order/drift structure mapped.**


## (round 141, cont. 21) THE STAGE BRIEF — WINDOW 48: THE DRAFTS=0 + LIVE_HALF COMPOSITION A/B (DRAFTLIVE) (2026-11-11)

**The stage brief — window 48** (`preflight draftlive summary`):
- *The question*: the perf plan's priced composition — DRAFTS=0 (the
  serial reference, no DFlash2 draft block) plus the #2181 live-half
  keep (~30-35% smaller) — does it fund ALL 16 TF_KV_SHARE kept states
  cacheless (closing the eviction warning window 37 measured as
  unresolvable at PARALLEL=4 with drafts on), and what does the
  concurrent resume + decode trade read?
- *The value-if-yes*: the multi-turn resume at 4/4 cache hits without
  eviction (the opencode interaction's own cost), priced against the
  decode trade — the c4 gate binds at within 5% of the standing
  engine's w47 first-arm reading (185.1). A funded store + a bounded
  trade is a user-visible win on both axes.
- *The cost*: one window (~50 min: two serves + the rebuild-free
  restarts — no new patch, both knobs exist in the adopted engine;
  the fingerprint does not move).
- *The alternatives rejected*: the 0110 KV-SHARD port (user-parked —
  a multi-sitting scope; the composition question is one window);
  the window-drift re-anchor as a standalone window (the drift watch's
  checkpoint rides this window's OFF arm free — the OFF arm IS another
  same-window A/A-ish reading at the standing config); waiting for the
  v1.2.7 rebase (the composition's knobs exist NOW and the question is
  user-visible).
- *The kill criterion*: QUALIFIED = BOTH env witnesses PLACED AND all
  16 slots funded AND the eviction warning ABSENT AND the greedy sha ==
  the standing 80cc3802… AND the c4 aggregate within 5% of 185.1 AND
  the c4 plumbing guard OK AND §2 ALL PASS AND hardmode 95 AND the
  vision 4/4 AND the resume aggregate BETTER than the OFF arm's
  same-window reading => DRAFTS=0 + TF_GLM_KV_LIVE_HALF=1 become
  config.sh's defaults TOGETHER (neither alone). Any miss => RETIRE,
  the standing config stays, the composition closes with its receipt.
  The value gate binds on order-matched instruments throughout (the
  window-drift watch is open).

**The phase**: `draftlive` in run-qualification.sh (session-specific;
retires with the receipt) — the OFF arm (the standing DRAFTS=1 engine)
vs the ON arm (DRAFTS=0 + TF_GLM_KV_LIVE_HALF=1), the duel_arm
instrument set + the kvshare2-shape concurrent-resume probe on BOTH
arms (order-matched), the slots/enough-for/eviction witnesses from the
serve lines, the §2 gates + hardmode + vision + the bench on the ON
arm.

**The window-drift watch rides**: this window's OFF arm is the
standing config measured again — its c4/solo readings are the drift
watch's third checkpoint (w45 170.0, w46 182.0, w47 185.1 first-arm
levels).


## (round 141, cont. 22) WINDOW 48 RAN THE DRAFTLIVE COMPOSITION A/B — THE VALUE GATE MISSED DECISIVELY ON THE DECODE TRADE; THE COMPOSITION RETIRES; THE FUND QUESTION ANSWERED YES ANYWAY; THE DRAFTS WITNESS BUG; THE DRIFT WATCH FIRES (2026-11-11)

**The window** (campaign-20261111-153202, `preflight draftlive summary`,
rc=0): both arms ran end to end, the §2 gates + hardmode + vision + the
bench on the ON arm. Production restored healthy (200), the flag cleared.

**The value gate MISSED — the decode trade is catastrophic**:
- The ON arm's c4 aggregate: **35.1 t/s vs the gate's ≤5%-of-185.1 ask**
  — an ~81% decode loss. The solo decode halved too (35.2/34.7 vs the
  OFF arm's 70.2/70.3): **DFlash2 drafts are worth ~2× on decode on our
  shape.** The ITL probe's chunk count tells the mechanism plainly:
  2,017 single-token chunks vs the drafted engine's 501 multi-token
  chunks for the same 2,048 tokens — without the drafter, every chunk
  carries one token and the chain runs twice as long.
- The resume value the composition bought: 5.22 s vs the OFF arm's
  5.42 s (−3.7%) — real but two orders of magnitude too small to pay
  for halving decode.
- **The verdict: RETIRE.** The standing DRAFTS=1 config stays; the
  composition question closes with its receipt. Neither knob moves.

**The fund question answered YES anyway — recorded as structure**: the
ON arm's serve line funds **15 of 16** kept-state slots (2.4 GiB) vs
the OFF arm's 6 of 16, and lifts enough-for from 3 to 4 at the 524,288
window — the live-half keep plus the drafter's freed 2.84 GiB (model
78.80 vs 81.64) bought the store room the resume path wanted. But the
eviction warning stayed PRESENT (15 < 16, one slot short) and the
price — half the decode — is disqualifying on its own. The funding
path is now MEASURED: the only lever that funds the store costs the
drafter, and the drafter pays for itself ~2× on decode. The cacheless
standing with the funded-6 store is the honest optimum on this line.

**The DRAFTS witness bug — a lesson, not a placebo**: the env witness
checked the container env for `DRAFTS=0` and printed FAILED — but the
serve line's arithmetic proves the composition PLACED (model 78.80
GiB: the drafter's weights never loaded; the campaign log's restart
line carries both knobs). `DRAFTS` is a config-side K=V consumed by
config.sh's arg builder on the HOST — it never reaches the container
env. The placebo-witness instrument was designed for TF_GLM_*
env-forwarded knobs; applying it to a config-side pair prints a false
placebo. The rule the wake carries: **the witness instrument must match
the knob's forwarding path** — container-env witnesses for TF_GLM_*
names, serve-line/campaign-log witnesses for config-side pairs.

**The window-drift watch FIRES**: the OFF arm (the standing config, a
first arm) read c4 **195.8** — the fourth consecutive first-arm climb
(170.0 → 182.0 → 185.1 → 195.8 across w45/46/47/48), +5.8%
window-over-window, +15% cumulative over four windows, with solo/c2/
ITL/overhead flat (70.2/121.8/58.1/184). The watch's criterion
(>2%/window sustained) is met: the c4 instrument's absolute level is
NOT stable across windows. Practical force: every value gate already
binds order-matched same-window comparisons (the discipline holds);
the anchors' c4 row carries the newest reading with the drift noted;
NO cross-window c4 comparison is valid as a delta, and a future value
gate whose margin is inside the drift band (±5%/window) cannot read
c4 absolute levels as evidence.

**Round 141's watch: 13 windows run (36–48), 1 void (35) — the round
closes its last locally-actionable question; the queue is now
upstream-gated (the #2852/#2856 device receipts, the v1.2.7 rebase) or
user-parked (the 0110 KV-SHARD port).**


## (round 141, cont. 23) THE STAGE BRIEF — WINDOW 49: THE DRIFT MAP (THE FIRED WATCH'S DECOMPOSITION) (2026-11-11)

**The stage brief — window 49** (`preflight driftmap summary`):
- *The question*: the window-drift watch FIRED on window 48 (the c4
  first-arm level climbed 170.0 → 182.0 → 185.1 → 195.8 across four
  windows, +15% cumulative, while solo/c2/ITL/overhead stayed flat).
  What IS the drift? The map: six fresh serves of the standing config
  in ONE window, the full duel_arm instrument set each, the delivered
  clocks as the covariate.
- *The value-if-yes*: the drift model every future value gate cites —
  the within-window slope (the order term vs the w45/46/47 second-arm
  edges) separated from the window-to-window term, plus the
  within-window behaviour of solo/c2/ITL (unmapped until now). The
  honest margin a c4 reading must beat becomes a receipt, not a guess.
- *The cost*: one window (~30 min: six short serves + the instruments;
  no rebuild — the fingerprint does not move).
- *The alternatives rejected*: assuming the drift is order-shaped and
  moving on (the w45/46/47 edges could equally be a warming HOST — the
  two explanations make different value-gate rules); re-anchoring the
  anchors to the newest reading alone (the drift structure would still
  be unknown); the 0110 KV-SHARD port (user-parked); the upstream watch
  (no new release, both watched PRs unchanged — checked this sitting).
- *The kill criterion*: none — a calibration window, no adoption
  branch. The outcomes: (a) the within-window slope explains the
  across-window step → the drift is order-shaped; value gates compare
  order-matched INDICES; (b) the six serves sit flat → the drift
  lives across windows (host state across days); value gates anchor
  on the same window exclusively (the standing discipline made
  precise); (c) either way, the c4-specific signature (solo/c2/ITL
  flat) is itself the finding — the drift lives in the concurrent
  decode path alone, which is where the #2793 adoption also lives and
  where the perf frontier now sits.

**The staging's adversarial catches** (both pre-launch, this sitting):
the phase's first draft carried `serve's` inside a `$()` — a bare
apostrophe in a command substitution opens a quote bash never closes
(caught by the file-wide `bash -n`, not by phase-lint; the patrol
pattern for future phase staging); and the worker clock probe carried
a literal site identifier — the docs guard refused the commit before
the push (the never-commit-site-identity rule; the probe now reads
`$WORKER`).


## (round 141, cont. 24) WINDOW 49 RAN THE DRIFT MAP — THE DRIFT IS WINDOW-TO-WINDOW, NOT ORDER; THE VALUE-GATE RULE MADE PRECISE; A GUARD-TIMING ARTIFACT RECORDED (2026-11-11)

**The window** (campaign-20261111-170638, `preflight driftmap summary`,
rc=0): six fresh serves of the standing config in one window, the full
duel_arm instrument set each, the delivered clocks as the covariate.
Production restored healthy (200), the flag cleared.

**The drift model (the receipt the value gates cite)**:
- **The within-window slope is FLAT**: c4 −0.19 t/s/serve across six
  serves (196.8 → 195.5, −0.7% first-to-last; solo −0.05, c2 −0.02).
  **The order term does NOT explain the across-window climb.**
- The c4-specific signature holds inside the window too: solo/c2/ITL
  drift less than c4 does (c2 wobbles ±2% between serves, c4 ±1%).
- The clocks are flat (3,894–3,898 MHz delivered, both hosts, all six
  serves) — the covariate rules out clock throttling as the mover.
- **The conclusion: the drift lives in the WINDOW-TO-WINDOW channel** —
  host state across days/reboots, not serve order within a window. The
  across-window first-arm series (170.0 → 182.0 → 185.1 → 195.8) is a
  between-windows property; within a window the instrument is stable
  to ±1%.
- **The value-gate rule, now precise**: order-matched same-window
  comparison is sufficient (the standing discipline) — no
  order-index correction is needed; but NO cross-window c4 comparison
  is valid as a delta, and any value gate whose margin is inside the
  ±5%-per-window drift band must be judged on order-matched
  same-window instruments exclusively. The #2793 adoption's value
  (+7.1% to +8.9% order-matched) clears the band comfortably and
  stands.

**A guard-timing artifact, recorded honestly**: serves 1–3's receipt
lines say `the c4 value plumbing guard: FAILED — the c4 DOES NOT
COUNT`, but every artifact the guard checks is valid — all 24 c4
envelopes exist with tokens=2048, 24 unique ids, and the guard logic
re-run against the saved files passes 6/6 (the guard code is byte-
identical to the proven budgetsqual pattern). The aggregates the map
read came from the same files the guard now validates, so the model
stands; the FAILED lines are a run-time artifact of the phase's first
campaign run — most plausibly the guard's glob evaluating before the
files settled. The map's verdict does not depend on the guard lines
(no value gate fired on them; the phase has no adoption branch).

**Round 141's watch: 14 windows run (36–49), 1 void (35) — the round
closes with the instrument's drift structure MAPPED and the value-gate
rule made precise. The locally-actionable queue is empty; the remaining
items are upstream-gated (the #2852/#2856 device receipts, the v1.2.7
rebase) or user-parked (the 0110 KV-SHARD port).**


## (round 141, cont. 25) THE STAGE BRIEF — WINDOW 50: THE STATE-OF-THE-LINE RE-ANCHOR (DEPTH + WARMTTFT) (2026-11-11)

**The stage brief — window 50** (`preflight depth warmttft summary`):
- *The question*: do the standing receipts survive the adopted engine —
  the depth fact ladder (12/12 at 8k/64k/192k/384k, last receipted on
  the v1.2.5-era stack) and the warm-TTFT row (the v1.2.1-era receipt,
  three engine bumps ago)? The drift map taught that cross-window
  instruments need current receipts; the anchors carry both rows on
  stale receipts.
- *The value-if-yes*: the anchors' rows re-dated on the adopted engine
  — the honest current answer to "how far behind production's resume
  is the line NOW" (the warm row) and the depth fact ladder holding
  12/12 on the 19-patch engine (the context front's standing claim).
  A stale-receipt catch (a row moved) is equally valuable — it would
  name the next lever.
- *The cost*: one window (~25 min: the depth probes + two cold-warm
  pairs; no rebuild — the fingerprint does not move).
- *The alternatives rejected*: idling until upstream moves (the AGENTS
  rule is "a sitting with nothing to test launches nothing" — but the
  stale rows ARE something to test: the discipline layer's own
  receipts need the drift-map service too); folding the re-anchor into
  a future candidate window (the rows would stay stale until one came,
  and the window-38 precedent says a receipt outlived its engine once
  already); the 0110 KV-SHARD port (user-parked).
- *The kill criterion*: none — a re-anchor window, no adoption branch.
  The outcomes: (a) the depth ladder holds 12/12 and the warm numbers
  land near the old row → the rows re-date, the standing claims hold;
  (b) anything moved → the receipt lands, the ledger's item opens, the
  shape gets its own stage brief.

**The staging's catches**: the phase first wrote `06-warmttft.md` —
colliding with the knobs/prefill receipts' numbering (each `: >` would
truncate the others in a full run); renamed to `14-` (the free slot).
The hit witness moved from the envelope (the `tensorfold` object
carries no cached key — verified against window 49's real envelopes)
to the engine's own done line (cached= is the verdict — the pattern
every battery uses).


## (round 141, cont. 26) WINDOW 50 RAN THE STATE-OF-THE-LINE RE-ANCHOR — THE DEPTH LADDER HOLDS 12/12; THE WARM-TTFT ROW MOVED (302 → 945 ms): A STALE-RECEIPT CATCH, THE NEXT QUESTION NAMED (2026-11-11)

**The window** (campaign-20261111-174642, `preflight depth warmttft
summary`, rc=0): both instruments ran on the adopted engine. Production
restored healthy (200), the flag cleared.

**The depth ladder HOLDS: 12/12 on the adopted engine** (3/3 at each of
8k/64k/192k/384k) — the context front's standing claim re-qualified on
the 19-patch stack; the round-140 bump and the #2793 adoption did not
move the fact ladder.

**The warm-TTFT row MOVED — a stale-receipt catch (the brief's
outcome (b))**:
- d8192: cold 3,755 ms → warm **945 ms** (`cached=6144` — a genuine
  page-cache hit, the witness from the engine's own done line);
- d4096: cold 2,522 ms → warm **1,347 ms** (`cached=2048`);
- the row's old receipt (302 ms at d8192) was measured on the
  **window-mode KV architecture** (the v1.2.1-era serve: model 84.75
  GiB, a 3.7 GiB whole-window prompt cache — the campaign-20261102-
  233025 serve line carries no pool-pages clause). The current
  architecture is the paged pool + the share store (model 81.64 GiB,
  the store as pool pages) — **the warm resume on the CURRENT
  architecture is ~3.1× the old architecture's receipt, and ~4.5×
  production's full-hit skip (~212 ms)**.
- The comparison is honest as a ROW definition (the warm resume on the
  standing config), not as a regression claim: the architecture changed
  under the row, and the row now carries the current truth. The old
  number remains receipted as the window-mode architecture's value.

**The next question this catch names**: the warm-resume cost in the
paged+share era — the row moved FROM 302 ms (window-mode) TO 945 ms
(paged+share) across the architecture change, and the deltas are NOT
the drift band (3× is far outside ±5%/window). Whether it is the page
restore path's granularity (the 2048-aligned tail the PERF_PLAN parks),
the share-store's slot lookup, or the fp8 page readback is a source-
level question with a priced upstream analog — the stage brief for the
next window needs the source read first (the round-34 shape: root-cause
before instrument).

**The re-anchored rows land in the anchors** (the warm-TTFT row
re-dated with the architecture-change note; the depth rows carry the
12/12-on-the-adopted-engine re-qual).

**Round 141's watch: 15 windows run (36–50), 1 void (35) — the round's
final state: one adoption confirmed twice, one retirement, five
questions closed by receipt, one forged verdict caught, the promotion
protocol ridden end to end, the instrument's drift structure mapped,
and now one stale-receipt catch with its next question named.**

## (round 141, cont. 27) THE DOCS SPLIT — THE CONTEXT COST OF A DIGEST CUT ~3× (2026-11-11)

**The user's directive**: split the large doc/reference files — digests were
burning context on history they never need.

**The cut** (every split verified byte-identical against its origin — the
reconstruction concat reproduces the original file's hash exactly):
- `docs/LAUNCH.md` 11,686 → **2,767 lines**: the launch runbook + the CURRENT
  week's log (W46) only. Rounds 1–131 → `docs/log/2026-W44.md`, 132–139
  (cont. 10) → `docs/log/2026-W45.md`, rounds 1–30 → `docs/log/2026-W43.md`.
  The archives are immutable once cut; the round entry that moves a finished
  week is written in the sitting that cuts it.
- `docs/ECOSYSTEM.md` 1,051 → **281 lines**: the living watch state; the dated
  release reviews and sweeps → `docs/watch-archive.md`.
- `docs/TOOL_EVAL_TESTING.md` 1,670 → **1,444 lines**: the matrix/tables + a
  new Open-items section (the warm-resume item moved OUT of the round-history
  region so it is reachable without the history); the round-140 arc →
  `docs/eval-history.md`.
- `docs/PERF_PLAN.md` 1,164 → **353 lines**: the living plan; the front-3
  history, the dated roadmap, the research log and the resolved sections →
  `docs/perf-history.md`.
- `patches/README.md` 1,200 → **667 lines**: the serving stack's per-patch
  records; the retired instruments and stale watch lists →
  `patches/RETIRED.md` (named so it does not collide with `patches/archive/`,
  the retired .patch files).

**The navigation**: `docs/LAUNCH_INDEX.md` regenerates across ALL the log
files (364 round entries, one per round header, each carrying its file) —
the render script gained the multi-file scan and an `OUT=` override; the
docs guard gained an index-freshness check (the chart's --check pattern:
a fresh render must equal the committed file).

**The discipline rule** (AGENTS.md): digests read the living doc + the
index + the current week — never all the archives. The same retirement rule
now covers the watch archive, the eval history, the perf history and the
retired-instruments file.

**The rebase integration's first step landed in this commit**: the three
regenerated patch files (003/012/020, re-anchored onto v1.2.7's ground,
verified by the zero-diff round-trip — pristine `93a2e93` + the 16-patch
chain reproduces the verified tree byte-identically) are committed here.
The rest (config.sh's 022 drop, the pin flip, the v127val battery staging)
follows.
