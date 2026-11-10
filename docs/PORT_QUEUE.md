# The port queue — recipes staged, dispositions recorded

Working notes for the fork-tail and upstream port work. Full recipes from the
round-139 cont. 7 subagent scan (2026-11-08); line numbers reference our tree
at `f202781d3` (the v124-rebase head). **The dispositions come from
docs/ECOSYSTEM.md's scan** — port order reflects value and risk, not just
readiness.

## The order (the scan's verdict)

1. **The v1.2.5 bump — DONE (round 139 cont. 11-12)**: 15 of 17 patches applied
   verbatim, 003-fp8-pages re-anchored onto the registry_joins move; the tree
   verified byte-identical; the v125val battery qualified it (the greedy sha
   IDENTICAL across the engine bump, hardmode 95, the vision 4/4, the walls
   83/83 s). The pin holds at v1.2.5; production serves it.
2. **0104 warm-turns** — PORTED, MEASURED, **PARKED** (round 139 cont. 14-15):
   the mechanism engages on our KV_SHARE mode (the share-store substrate fix;
   3 done / 3 stepped aside per ON arm) but buys NOTHING — the deepened
   instrument (~9-10K loop, the fork's own shape) read off2 6194 vs on2 6292 ms.
   Explanation: our share store's per-turn radix keeps already carry what the
   warm pass adds; the fork's win existed on their snap-store base. 019 stays
   staged, NOT in the PATCHES default. The battery hardening (the
   witnessed-state gate, the four-arm drift control) is the A/B pattern now.

3. **0108 CACHE_FIRST — DONE AND ADOPTED (round 139 cont. 16-17)**:
   `020-cachefirst.patch` is the TWENTY-FIRST patch, the env default
   TF_PROMPT_CACHE_FIRST=1 in config.sh. The cachefirstqual receipt: the ON
   arms' streams ceded pages to the reserve (3110/3115 -> 3103/3083), the
   fund-report line live, the §2 gates ALL PASS, hardmode 95 — the
   TWENTY-FIRST consecutive — the vision 4/4.
4. **0110 KV_SHARD** — SCOPED, NOT PORTED (round 139 cont. 17): the fork's
   biggest single patch — 5,309 lines across ~44 files (NEW modules:
   `cuda_kv_shard.zig`/`_attn.zig`/`_keep.zig`, `kv_parts.zig`, `kv-shard-check`
   + their tests; the pool/pages/state/forward/disk machinery). The dry run
   against our v1.2.5+21-patch tree: 23 files reject with 79 hunks needing
   hands (the fork's base is `f350cd3e + 0001-0109`, much older than ours).
   The design note (inside the patch) is exceptional — the sharded layout
   (3,542 B/token a rank vs 6,380), the owner-computed attention over NCCL,
   the trash-page latent table, the part-ownership rules. THE VALUE: the pool
   holds ~1.8× the tokens — the 512K plan's own front. THE COST: a
   multi-sitting port with the §2 battery guarding it. The decision (the
   fork's measured −1.6/−3.6% decode vs 1.8× pool) is the user's when the
   512K ladder resumes; the port itself is the next major sitting's main
   work, on a fresh sitting with the recipes pattern (the warmturnsqual
   A/B pattern applies: TF_GLM_KV_SHARD=1 vs unset).

   **The digest's planning facts (cont. 19, the design-note read complete;
   tranche 1 COMMITTED on the port tree)**:
   - **No new CUDA kernels anywhere** — the whole port is host-side Zig +
     NCCL send/recv call sites; the fork explicitly did NOT port the old
     engine's `glm_shard.cu`. No sm_121 compile risk from device code.
   - **No 0109 dependency** — the disk-image/keep machinery is modified in
     place but every path is shard-conditional; unsharded disk format 1 is
     byte-identical; our native #1411 learned-states take the integration
     point's place.
   - **Fully switch-gated, byte-identical off** — `TF_GLM_KV_SHARD=1` plus
     CARRY/TWINS/CHECK knobs; the off path is proven unchanged by the
     patch's own recorded-launch test suite (150 random windows + mutants,
     all new files).
   - **The GPU check program is the port's primary validator**:
     `tf-cuda-test glm-kv-shard-check` serves a sharded stream against an
     unsharded twin IN THE SAME ENGINE PAIR byte-for-byte over seven paths
     (twins both parts, owner-computed prompts at 2,049 and 9,000 tokens,
     resumes at home / off-home with the carry, kept-in-part-1, the disk
     image) and FAILS if any path never engaged — the port qualifies on
     this plus our §2 battery.
   - **The collision map** (where our stack already touched the same ground):
     `cuda_dsa_block.zig` is the most delicate — our 005-pagerows-fix and
     006-selist-fix sit on the SAME `latent.Table` lines 0110 reworks
     (`latPt/latPs/latTable`); `cuda_state.zig`/`cuda_pages.zig` (003's
     page-byte layout), `cuda_snapshots.zig`+layout (003's fp8 parts),
     `cuda_engine.zig` (our Forward-literal fields) follow.
   - **The fingerprint struct will NOT merge mechanically** — theirs is
     layout 14→15; ours is already at 20 from our own patches. Our port
     bumps 20→21 adding `kv_shard` + `kv_shard_check` after `numerics`
     (the anchor position is identical in both trees; verified).
   - **The measurements**: the 1.8× is exact arithmetic (6,380 → 3,542
     B/token, asserted in a host unit test — safe to bank); the decode cost
     (−1.4/−3.7%) is an OLD-ENGINE measurement at single-row streams — the
     DFlash2 verify-width cost and the sharded-vs-unsharded acceptance
     identity on THIS engine are explicitly unmeasured GPU-only questions.
     Our own battery must measure them.
   - **The env plumbing**: no scripts/config.sh hunks in the fork's patch —
     the knobs are read from the environment per rank (`TF_GLM_KV_SHARD`,
     CARRY, TWINS, CHECK). Our port adds the export through config.sh's
     env-forwarded path (the export rule; the env-args gotcha applies).

   **Tranche 2 LANDED (round 139 cont. 20; all 79 rejects + 2 lost-clean
   hunks anchored, the port tree at `/tmp/v125-rebase/tf` WIP f83bd57..
   2n)**:
   - **The fingerprint** is OUR layout 21 (ours was already 20; the fork's
     14→15) — the two new words after `numerics`; the test adapted into our
     separate `cuda_ranks_test.zig` (the fork's was inline).
   - **The collision map confirmed**: `cuda_dsa_block.zig` anchored with our
     005/006 `page_rows` rule carried INTO the new `latTable` helper; our
     `tables()` plural + `pk` host-key fields preserved.
   - **Deliberate skips** (our tree integrates these grounds differently):
     the fork's `cuda_disk_image`/`cuda_disk_ranks`/`cuda_glm_disk` + their
     tests (~250 lines — our kept-states flow has no disk-image counterpart;
     `blankAs`/`seal` do not exist here), the fork's shared-segs batching in
     `cuda_shared.zig` (`segsKind`/`shared_writes`/`writeSegLatent`/
     `writeSegsLatent` — our `.mla` is the per-segment shape), and the
     `pageable()` gate (our engine never unsets pages once on; the
     `KvShardNeedsPages` refusal anchors before `ownSequence` instead).
   - **Adaptations on our own features**: our `adopted`/`openWith` prompt-
     cache flow preserved in `pagesFor`; our `heldPages`/`shared` snapshot
     params preserved; our `Snap` one-line struct; our `Kind` lacks `disk`
     (the keeps integrate differently); `copyOut` composed for our single-
     arena Pool (the fork's had a dev/host split).
   - **The fidelity check discipline worked**: 3,853 fork `+` lines checked
     against the tree; every miss classified (landed / adapted / skipped);
     it caught TWO lost-clean hunks the apply had silently dropped (the
     `Switches.read` in cuda_ranks, the `KvParts` in engine_status) plus the
     lane-host trio and the own-sequence sharded sizing — all fixed.
   - **The suite is green** (test-tool-parse-host RC=0 on the pre-fix tree);
     the REAL compile gate is `zig build compile-cuda-tests` (the fork's
     `glm_kv_shard_check` runner compiles inside tf-cuda-test) — in flight.
   - **COMPILE-CLEAN (cont. 21)**: `zig build compile-cuda-tests` RC=0 —
     the fork's `glm_kv_shard_check` runner compiles inside tf-cuda-test
     against the ported modules — AND the host suite still RC=0. Seven
     error rounds fixed: the engine_status field ordering, the idempotent-
     rerun duplicate export, the re-added host_tier import (dropped — no
     such file here), the mtp_drafts adaptation (`o.mtp and !o.drafter`),
     the fork `f.ce` lines (two sites; our Forward has no CE field), the
     pagedBytesFor arity (our head-less stateSizes), `Plan.max_parts`
     (ours at +2), `latent.max_segs` defined on our module (the fork
     0075's value 16 — our per-segment .mla never needed it), and the
     lanes pagesFor routing (the adopted prompt-cache pages are a pool
     lease via openWith; the shard home only on the openFor path — the two
     flows never compose).
   - **COMPILE-CLEAN END TO END (cont. 22)**: `compile-cuda-tests` RC=0
     WITH the check's dispatch landed (the fork's `shardCheck` wired into
     main.zig's run table — the usage-text-only registration would have
     died at runtime) and the check's body type-checked (the lazy-analysis
     blind spot closed). Seven more rounds of check-only fixes landed:
     keepAt/kept_id, the Options mtp adaptation, the e.link vestige, the
     snapshots arity, the prefill call mapping (the fork's ids,null,null,
     marks maps onto our ids,from,cancel,marks exactly), three beginOn
     calls gaining our kept arg. The disk cases stripped (our tree has no
     disk-image machinery) — the seven non-disk paths are the gate.
   - **THE STRATEGIC QUESTION RESOLVED (the user, round 139)**: "Finish the
     fork port now for a single iteration" — the watch is superseded;
     upstream #1431/#2415 remains background context only. The GPU gate
     (`kshardcheck`) is the iteration's goal, then the `kshardqual` battery
     on a PASS.
   - **THE GPU GATE ON THE REAL PAIR (cont. 25)**: two instrument failures
     fixed (the relative `-v` named-volume trap; the id-file poller race +
     the set-e kill — the handoff is synchronous now, the RC captures
     `|| RC=$?`). Window 3 failed the PLACEMENT check — the begin-step wire
     contract was mapped swapped (the fork keeps `h.a` = kept and
     re-purposes `h.depth` = the TWIN count on a begin; fixed, tranche 2zh).
     Window 4 RAN THE REAL ENGINE PATH: checkpoint digests verified on both
     ranks, weights loaded direct, steps crossed the wire, placement
     passed — then BOTH ranks faulted inside the first prefill of the
     sharded stream: `CUDA_ERROR_ILLEGAL_ADDRESS (700); kernel ?, grid
     92x1x1, block 256x1x1` (the sticky fault poisoned the context, so
     cuFuncGetName answered `?`). The launch-ring instrument landed
     (tranche 2zi, 89faa5d): every launch records its name+shape BEFORE
     launching, and a fault dumps the ring — the next window names the
     victim and the predecessors the culprit hides among.
   - **THE EXACT CULPRIT PINNED (cont. 27)**: window 6 ran TF_LAUNCH_SYNC
     (sync after every launch): `TF_LAUNCH_SYNC: launch #2893 faulted IN
     EXECUTION` — the kernel at 30x256 is `plan_scatter` (the MoE plan
     scatter, cuda/grouped.zig), and every one of the ~2,892 launches
     before it synced clean. The 0110 patch never touches the MoE files —
     the scatter reads memory the shard path corrupted (or garbage picks
     from a clobbered router scratch), so the corruption happened EARLIER
     (the last DSA layer writes at layer 43 of 45; the fault at the MoE
     plan of the same layer's block). KSHARD_SAN=1 landed: rank 0 under
     compute-sanitizer memcheck — the report names the faulting ADDRESS
     and the nearest allocation, settling whose buffer the walk-off
     touched.
   - **THE EXACT CULPRIT PINNED (cont. 27)**: window 6 ran TF_LAUNCH_SYNC:
     `launch #2893 faulted IN EXECUTION` — the kernel at 30x256 is
     `plan_scatter` (the MoE plan scatter, cuda/grouped.zig), every one of
     the ~2,892 launches before it synced clean. The 0110 patch never
     touches the MoE files — the scatter reads memory the shard path
     corrupted (or garbage picks from a clobbered router scratch), so the
     corruption happened EARLIER. KSHARD_SAN landed: rank 0 under
     compute-sanitizer memcheck — the report names the faulting ADDRESS
     and the nearest allocation, settling whose buffer the walk-off
     touched. Window 7's report was LOST (the host-path log-file inside
     the container) — fixed to the /ids mount; window 8 reruns.

## The test-count note (do not re-litigate)

The subagent counted 33 `test "` blocks in tool_parse_test.zig at f202781d3
and flagged the "51" gate. Reconciled: the 51 is the whole tool-parse host
suite (`zig build test-tool-parse-host`) — all server-module test files
(33 in tool_parse_test.zig + 14 in tool_stream_test.zig + tool_params +
visibility + witness). Use the suite runner's count, not one file's.

---

## Recipe A — 0105, untyped tool parameter (STAGED, watch)

Files (3): `tool_params.zig` (insert `schemaUntyped` after line 78; line 122
`orelse return untyped(a, value)`; private `fn untyped` after `decode` ~137;
doc-comment line 120; +1 test after line 403), `tool_stream.zig` (fields
`untyped`/`pending_open` after line 47; `.function` state ~252–256; `.value`
state first-non-blank gate ~288; `finishCut` flush block ~368–377), and
`tool_union_witness.zig` **applies CLEAN** (blob 0d3f57ba4 byte-identical;
six expectation flips at lines 147/152/202/218/219/220).

No missing dependencies (`tool_kinds.schemaKinds` at tool_kinds.zig:129,
`closedJson`, `finite`, `json.parseText` all exist). Risks: our
`tool_stream_test.zig:88` witness-loop test's string expectations must flip in
lockstep (not read to line level — run it and update); `emptySchema` (line 69)
means schema-less parameters whose text parses as object/array now decode —
the intent, covered by the flipped witness.

## Recipe B — 0092, JSON answer beside offered tools (STAGED, watch; port
second if ever)

Files (5): `chat.zig` Reply/Prepared + `response_channel: ResponseChannel`
enum (line ~51–52, first field), `prepare()` channel computation before line
211's return literal, `generate()` gen literal + `.tools = if
(structured_json) &.{} else input.tools` + streamer gate `gen.tools.len > 0`;
`chat_generation.zig` (OURS — the fork's Generation methods live here)
streaming-visible gate lines 124–126, `finish()` harmony branch ~253 + `and
g.response_channel != .structured_json`, Reply literal ~324;
`openai_calls.zig attach()` line 13 gate (BEFORE the native_tool_format
branch); `openai.zig stream()` line 491 rename `tools`→`has_tools` + gated
`const tools = has_tools and prepared.response_channel != .structured_json`
(lines 496/500/517 call sites); `build/server.zig` json_answer test step after
line 97 (`all.dependOn(&json_answer.step)` included, mirroring the fork);
`root.zig` import after line 57; `json_answer_test.zig` drop-in verbatim (all
compile-deps verified at f202781d3: `late.DropLate/Capture/exchange`,
`Server.init` signature, Config fields, `srv.info.structures`,
`srv.grammars`, the `Compile` fixture shape).

No missing dependencies. Risks: the finish() gate attaches to the
capability-reasoning branch only (ours has native/thinking/reasoning — attach
to the third); `gen.tools = &.{}` also disables the dsml rewrites (intent);
verify `tool_grammar.structure()` produces `structural_tag` so
`tool_choice: required` stays on the automatic channel (server.zig:325).

## Recipe C — 0107, TF_TOOL_CALL_GUARD=1 (STAGED ~85%, watch; port third —
after 0092: its context carries 0092's `response_channel` line)

Files (3): `tool_guard.zig` NEW drop-in verbatim (self-contained); 
`tool_stream.zig` TextFilter gains `hid: bool = false` after line 433
(OURS has `deferred: bool = false` line 434 — keep it; set `f.hid = true`
next to line ~480's `f.hidden = ...`), Policy gains `guard`/`drop_rejected`
+ `filtering()` (line ~508; `text`/`flush`/`content` flip from `p.single` to
`p.filtering()`; **keep `parsedContent`/`kept` gated on `single`**), new `pub
fn hideCalls(a, s)` after Policy ~line 554 before `wholeEnvelope` (557),
test-tail import ~570; `openai.zig` import line 12, plan() guard block after
lines 174–178, StreamSink.call delta branch ~449, policyDelta line 458
first line flips to `filtering()`, stream() tail ~556–572 guard tail; 
`openai_calls.zig attach()` — the biggest divergence: line 14 `if (tools.len
== 0) return null;` becomes the guard block; after line 28 `const found` the
`dropped`/`base` pair; lines 30/34 gain `or dropped` with `base`.

⚠ OPEN: the fork's stream() tail scope — in OUR tree the `kept`/`prose_sent`
chain sits inside `if (tools)` (block ~541–573) and a guard request has
`tools == false`, so the dry-run placement is dead code. **Read the fork's
working-tree `/tmp/mia-fork/zig/src/server/openai.zig` stream() tail directly
and mirror its scope before porting.** Everything else is scope-unambiguous.

Tests: +4 in tool_guard.zig (`usedTools`, Policy.guard whole+streamed,
hideCalls); `test-tool-visibility-http-host` + `test-tool-parse-host` stay
green.
