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
   - **THE SANITIZER REPORT (cont. 29)**: `Invalid __global__ write of
     size 4 at tf_experts::plan_scatter+0x1c0 — 2,530,871,136 bytes BEFORE
     the nearest allocation` (a 512-MiB buffer). The scatter's bucket
     positions come from plan_rank's rank[] — built from the PICKS.
     Out-of-range picks (garbage router scores) never land in hist[]; the
     scatter reads uninitialized rank[] and computes a wild base (~2.5 GB
     off). The corruption is UPSTREAM of the scatter: garbage expert ids
     from garbage router scores, or a clobbered picks buffer. Suspects, in
     order: NaN latents from a misrouted latent page (the trash page read)
     feeding the router matmul; a clobbered picks buffer; a clobbered plan
     scratch. The ltable slot chain and the pool's keys/lat sizes verified
     consistent against the fork. TF_SHARD_DEBUG landed (tranche 2zk,
     6e2bf75): the picks + an x sample read BEFORE the experts consume
     them, per call — out-of-range picks prove upstream garbage; clean
     picks prove a clobbered scratch.
   - **THE PICKS ARE GARBAGE FROM CALL #0 (cont. 30)**: window 9's
     instrument: bad picks ~1,850-1,930 of 4,096 from the VERY FIRST call,
     x CLEAN (0 NaN/1,024) — the block input is fine, and the garbage
     values repeat EXACTLY across calls (720442064, -2147354444, 58417 =
     0xE431, two E4M3 code bytes): constant CONTENT in the picks' memory —
     a buffer-aliasing/layout defect (another buffer's data sitting in
     pick's memory), NOT a runtime race and NOT NaN propagation from the
     latents. The suspect: the fork's shared-buffer split (twin buffers)
     changed the scratch layout and one side of the change is missing in
     the port. The deepened dump (per-slot stride, raw picks, mlog
     scores) landed (tranche 2zl, d478292) for window 10.
   - **THE STRIDE DUMP (cont. 31)**: window 10: pick[0..23] ALL VALID, the
     mlog scores SANE at both sample points (row 0, last row), the bad
     picks spread UNIFORMLY across the 9 slots (~202-238 each) — the
     signature of whole ROWS going bad (~46%), growing slowly call over
     call. The garbage sits in the MIDDLE rows. The mlog full NaN scan
     landed (tranche 2zm, 2eba8c0): the count/range of NaN score rows —
     NaN rows make all 9 picks garbage, matching the uniform counts, and
     point at the router's INPUT (normed x rows) going NaN for exactly
     those rows (the trash-page rows?).
   - **THE MLOG SCAN BURNED ON ITS OWN BUFFER (cont. 32)**: window 11 —
     the scan buffer held 19 KB ([64 * 300]u8) while the copy needs ~74 KB
     (64 rows x 288 experts x 4 B): both ranks dumped core INSIDE the
     instrument after the mlog print (the four printed lines still
     confirmed the window-10 pattern on both ranks: bad ~1,840-1,867,
     per-slot uniform, pick[0..23] valid, mlog row0/lastrow sane). The
     buffer sized in BYTES (76,800; b02fd54); window 12 reruns.
   - **ZERO NaN IN THE SCORES — ROW 48 IS THE FIRST BAD ROW (cont. 33)**:
     window 12: mlog NaN rows 0/2048 on every call — the router scores are
     clean everywhere; the first bad pick ROW is 48 (rows 0..47 valid),
     bad slots 2-5 (float bit-patterns, the same values every call).
     The earlier x sample only covered rows 0-15 — rows 48+ were never
     sampled, and E4M3-pattern bytes are huge-but-finite as bf16
     (invisible to NaN scans). The bad-row dump landed (tranche 2zn,
     52ad9cd): x rows 44..52 + mlog rows 44..52 raw, with an
     E4-high-byte count — clean x there convicts the select/picks buffer;
     E4-pattern x convicts the sharded latents' pages.
   - **X AND MLOG CLEAN AT THE BAD ROWS (cont. 34)**: window 13: x rows
     44..52 CLEAN (0 E4-words), mlog rows 44..52 CLEAN (max score 2.81)
     — the router's input AND output are fine exactly where the bad picks
     come from. The first bad row MOVED between runs (48 -> 51) and the
     four garbage words SHIFTED ONE SLOT — an uninitialized region whose
     boundary slides.
   - **WTS IS PERFECT — THE SELECT'S PICK WRITE IS THE FAULT SITE
     (cont. 35)**: window 14's pre/post discriminator: wts rows 44/51
     carry perfect sigmoid values every call (the select's other output
     is correct); PRE-select pick rows are all-zero on call #0 and hold
     the PREVIOUS layer's VALID ids on call #1 (the buffer is reused
     across layers and the select CAN write valid rows); the first bad
     row DRIFTED again (48 -> 51 -> 59) with the same four garbage words.
     The boundary dump (pick rows 0..70 raw + a zero/valid/garbage census
     + the first bad row's neighbors + x3.picks' head — the next buffer,
     a size overlap bleeding backward) landed (tranche 2zp, 354ce54).
   - **THE BOUNDARY ESCAPED THE WINDOW — THE FULL CENSUS (cont. 36)**:
     window 15: pick rows 0..71 ALL VALID (zeros 1, valid 638, garbage 0)
     — the first-bad-row drifted past 71 (48 -> 51 -> 59 -> >71 across
     four runs; run-to-run timing, constant garbage content). The full
     census landed (tranche 2zq, 5bf9bc4): all 2,048 pick rows classified
     in one 73 KB read — bad-row count, the even/odd parity split (a
     stride-2 row-pair bug shows as even != odd), the first bad row's
     neighborhood raw. x3.picks holding the previous call's picks is
     EXPECTED (the compact copy runs during the experts' pass).
   - **THE CENSUS PARADOX RESOLVED — THE READS RACED THE STREAM
     (cont. 37)**: window 16: the FULL census over ALL 18,432 entries
     says ZERO bad rows, while the earlier small read of the same memory
     said ~1,800 bad with the first bad row drifting (48 -> 51 -> 59 ->
     60 -> >71 across five runs). Root cause: MY OWN INSTRUMENT — every
     diagnostic DtoH ran on the NULL stream (non-blocking vs the
     engine's stream): the reads raced the select's in-flight writes,
     and the drifting boundary was the select's WRITE PROGRESS at read
     time. The FINAL state is clean — the select writes valid picks
     everywhere — so garbage picks CANNOT feed plan_scatter. The suspect
     moves to the fused path's plan scratch (plan.rank/hist/items) or
     the compact copy. All 12 diagnostic reads now synchronize the
     stream first (tranche 2zr, 56d3109); the plan scratch (rank/counts)
     is dumped after the sync.
   - **THE RACE PROVEN; THE PLAN SCRATCH INCONSISTENT (cont. 38)**:
     window 17 (the synced reads): the census reads ZERO bad rows on every
     call with the sync in — the select is INNOCENT. But plan.rank is
     almost all ZEROS with three tiny entries (1, 2, 1) where cumulative
     sums belong, while plan.counts[0..1] = 401, 286 carry real values —
     the plan's own state doesn't cohere. The fault landed AFTER calls
     #0/#1 logged clean — the failing ffn call is a LATER one. The
     unverified link: the fused path's COMPACT picks (sc.x3.picks, a
     per-chunk copy the compact makes) — the plan kernels read the
     compact, not s.pick. The every-call census landed (tranche 2zs,
     b8004df): the final picks classified on EVERY ffn call, each line
     annotated with the launch ring's seq; the detail dump fires on the
     FIRST bad call.
   - **ALL 42 FIRST-CHUNK CALLS CLEAN (cont. 39)**: window 18 (the
     every-call census): every ffn call of the first chunk read clean
     final picks; call #42 — the SECOND chunk's first MoE layer
     (rows=952, the short tail piece) — logged its census at launch
     #2890 with bad 0/952, and the fault fired at #2893 INSIDE that
     call's plan chain (rank #2891 and offsets #2892 synced clean;
     plan_scatter #2893 faulted). The select is fully innocent; the
     plan buffers were trashed between calls. The prime suspect: the
     port's pool write path (tf_glm_pool_keys) at the second chunk's
     page boundary — pages the first chunk never touched. The hist/rank
     FULL scan every call landed (tranche 2zt, 7342b40) to bracket the
     trashing kernel exactly.
   - **THE BRACKET NARROWS TO THREE OPS (cont. 40)**: window 19: the plan
     buffers CLEAN at every census point including call #42 (hist bad 0,
     rank bad 0/7616), the fault STILL at #2893 inside call #42's plan
     chain. The trash happens between #2890 and #2893: only plan_rank,
     plan_offsets, and the COMPACT COPY run there — and the rank/offsets
     OUTPUT state was never read back before scatter consumed it (a
     clean launch says nothing about what they wrote), while the compact
     picks (the ids route reads) were never validated at all. The
     PRE-SCATTER bracket landed (tranche 2zu, 26176fb): the compact
     picks dumped + range-checked before route; rank/hist read AFTER
     offsets BEFORE scatter.
   - **EVERY INPUT CLEAN — THE MEMBERS BASE IS THE SUSPECT (cont. 41)**:
     window 20: the compact picks VALID (0 bad/80), rank and hist
     COHERENT (hist a valid prefix-sum), the fault STILL at #2893 — and
     the sanitizer's failing thread was p=64, whose index is provably
     small. A valid index producing an address 2.5 GB below the nearest
     allocation convicts the MEMBERS BASE POINTER itself. The PLAN PTR
     dump landed (tranche 2zv, 5d2f036): the pointers and their diffs
     against the sizes chain (items-members = P*4, rank-counts = 8,
     hist-rank = P*4) — any mismatch convicts the arena slot mapping in
     cuda_state.zig (the port's one hand-edited link).

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
