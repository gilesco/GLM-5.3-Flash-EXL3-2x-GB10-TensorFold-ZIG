# The port queue — recipes staged, dispositions recorded

Working notes for the fork-tail and upstream port work. Full recipes from the
round-139 cont. 7 subagent scan (2026-11-08); line numbers reference our tree
at `f202781d3` (the v124-rebase head). **The dispositions come from
docs/ECOSYSTEM.md's scan** — port order reflects value and risk, not just
readiness.

## The order (the scan's verdict)

1. **The v1.2.5 bump** — the cheapest since the v1.2.2→v1.2.4 rebase. One hard
   re-anchor: 003-fp8-pages' contract-registry append re-cuts onto v1.2.5's
   new `registry_joins.zig` (`joins.cuda_pending`, #2422); `glm_family_host.zig`
   likely one line. `tool_parse.zig` byte-identical v1.2.4→v1.2.5 (both server
   patches survive); all kernel files our nine kernel patches stand on are
   byte-identical; the engine's gate/shared block moved to
   `cuda_engine_gate.zig` but all `e.*` call sites keep working. Guarded by
   the §2/hardmode/vision battery as usual.
2. **0104 warm-turns** — the fork's highest-value patch for our line: the
   server background-prefills conversation+reply+next-turn-opening after a
   reply (`warm_quiet` 150 ms), so an agent loop's next turn stops
   re-prefilling the whole prefix (their 50–100K prefills: 10–30 s → resumed
   from 4,096 of 9,335 tokens). 8 files (`lane_host.zig`, `cuda_lanes.zig`,
   `cuda_native.zig`, `native/cuda.zig`, `warm.zig`, `openai.zig` + tests).
   Needs its own port recipe — none staged yet. Merges with our
   `cuda_lanes.zig` hunk (003-fp8-pages' `fits()` note).
3. **0108 CACHE_FIRST / 0110 KV_SHARD** — the 512K-plan candidates; decide
   after the v1.2.5 rebase lands (0110 touches the same pool ground as
   003-fp8-pages + 005-pagerows-fix).
4. **0105 / 0107 / 0092** — recipes staged below, but DISPOSITIONED watch:
   port when the shape appears in a receipt (the patch policy: the measured
   win must be worth the rebase tax).

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
