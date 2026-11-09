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
