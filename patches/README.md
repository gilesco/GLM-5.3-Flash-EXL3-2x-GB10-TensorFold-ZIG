<!-- LAYOUT (round 139): patches/*.patch at the TOP level are the living set — the
16 adopted (config.sh's PATCHES default) plus 017-topk4b.patch (the sweep cells'
opt-in). patches/archive/ holds the RETIRED, REJECTED and mainlined-upstream
patches — NOT in any serve; their records live in [RETIRED.md](RETIRED.md).
The build consumes ONLY the named PATCHES list (prepare copies each named file
into the image staging), so the archive is inert by construction. Do not
resurrect an archive patch into a serve without a new qualifying window.

NAME MAP (the round-139 renumbering, user): every living patch is NNN-name.patch
now — the number IS the build's apply order (the image applies the glob
alphabetically), replacing the old glm-mia-*/glm-zz-* names and their
sort-duty naming hacks (tools256 named -256 to sort before the z- kernels,
zs2/zshfl/zstep named for their sort-after partners). 001-absorb-mma was
001-absorb-mma, 002-exl3prompt 002-exl3prompt, 003-fp8-pages
003-fp8-pages, 004-packed-s2 004-packed-s2, 005-pagerows-fix
005-pagerows-fix, 006-selist-fix 006-selist-fix, 007-attnfetch8
007-attnfetch8, 008-loaddirect 008-loaddirect, 009-moeside
009-moeside, 010-tools256 010-tools256, 011-zclose 011-zclose,
012-zmoe-fuse 012-zmoe-fuse, 013-zprompt 013-zprompt, 014-zs2
014-zs2, 015-zshfl 015-zshfl, 016-zstep 016-zstep, 017-topk4b
017-topk4b. Historical receipts quote the old names — this map decodes them.
-->

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
- **New: 008-loaddirect.patch** — GLM's layer loads wired onto v1.2.4's
  `checkpoint.direct` (#2282/#1901), following the gemma4/qwen3_5 pattern in
  `cuda_load_ahead.zig`: each layer's tensors read past the page cache while the
  previous layer packs; `TF_LOAD_DIRECT=0` keeps #1928's read-ahead. Our
  checkpoint's 23 shards < `gather.max_sources` (64): the path engages.
- **The verification (triple)**: the 9-commit rebase branch (`v124-rebase` on
  the head's /tmp/tf-src) — fresh-v1.2.4 + the commit bodies byte-identical
  (0 diff lines); fresh-v1.2.4 + the SHIPPED patch files in alphabetical order
  byte-identical (0 diff lines); the full compile (fatbins + native, nvcc
  sm_121, zig 0.17.0) RC=0 in the builder base image. **JUDGED (round 135,
  the v124val windows)**: QUALIFIED — the §2 gates ALL PASS, hardmode 95
  (the ninth consecutive), the vision 4/4, zero strict-TF_ refusals under
  #2405, the arms content-identical to the byte; **the loading front CROSSED
  on loaddirect (the walls 83/83 s vs production's 93.7 — 112.9%)** on the
  resharded 55-shard pack. 008-loaddirect's STATUS: **QUALIFIED** (the
  round-135 receipts, campaign-20261107-150250).

## THE v1.2.6 REBASE (2026-11-10) — the 18-patch stack re-anchored

The adopted 18-patch stack was re-anchored onto **TensorFold v1.2.6**
(6e9af9302, released 2026-11-10) from the v1.2.5 base. The drift map: 6 patches
applied verbatim (002-exl3prompt, 008-loaddirect, 010-tools256, 011-zclose,
013-zprompt, 018-callquote); 12 re-anchored (001-absorb-mma, 003-fp8-pages,
004-packed-s2, 005-pagerows-fix + 006-selist-fix + 007-attnfetch8 as the
003-cascade, 009-moeside, 012-zmoe-fuse, 014-zs2, 015-zshfl, 016-zstep,
020-cachefirst). The named upstream drifts:

- **The shared MLA image** (#850 step 3, 42735f94f): the chunks_wide template
  moved token-for-token from glm_glue_attn.cuh into common/mla.cuh (SASS-
  identical), gaining RW/SPLIT template params. 003.s PAGED8 marriage and
  007.s fetch8 port now live in common/mla.cuh with their anchors re-cut.
- **#2257** (6d4191a95): the GLM TP=2 release commit — decode windows to 32
  rows, MTP chains to 15, the greedy one-gather, the load-priced rounds; 24
  engine files. The release claims prompts 23%/13% faster at 2K/8K and
  one-stream code decode +32%, every reply equal — the v126val bench row
  records what it does on our shape.
- **#2699**: the prompt-cache rework (the reclaim chain, the admission
  guards, the budget scaled to the room; the budget construction moved into
  budgetOf()). 020-cachefirst re-anchored onto it.
- **The SwiGLU split** (88267c063): the SwiGLU rows moved to
  glm_swiglu.cuh; the EXL3 clamp (edc16dfe9) is additive (AFTER=false).
- **#2449.s direct reads** landed spark25/dory ONLY — 008-loaddirect keeps
  its value (GLM still needs our wiring).
- **NOT mainlined** (checked against the tag objects): every one of our
  fork mechanisms — the whole living stack survives.

**Upstream watch**: main is 36 commits past the tag and has absorbed the
fork.s 0078 exl3p prompt loop (bc166dbfd) plus the cp.async/ldmatrix/mma
common-module extractions — the next release may mainline more of the stack.

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
4. **One file name, one number.** A living patch file is `NNN-name.patch` (three
   digits, zero-padded): the number IS the image build's apply order (`/build/patches/*.patch`
   applies in shell-glob order), retired patches move to `patches/archive/` with their
   names intact, and a new patch takes the NEXT free number even if it sorts outside the
   order today (an opt-in patch is numbered too — 017-topk4b.patch is opt-in).
5. **Rebase cost is the bill.** The ecosystem's 77-patch stack (jayleaton's repo) targets
   TensorFold 0.3.4 and buys ~3% over its own control — their headline numbers come from
   configuration, not patches. Port a patch only when its measured win is worth the
   rebase tax on every future version bump.

## Retired instruments and watch lists

The retired probes, dropped candidates and the stale watch lists moved to
[RETIRED.md](RETIRED.md) — immutable once written; the serving stack's
per-patch record continues below.

## 001-absorb-mma.patch — ADOPTED (the qualified optimum, 2026-11-05)

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
`RC_PATCHES="001-absorb-mma.patch,glm-mia-cost-tables.patch"` in the
"preflight resumecost deepfills hmcheck summary" window; judged by the
content gate (sampled-bit-equal → the greedy sha must hold), the resumecost
rows (the small-prompt front must NOT regress — the chunk pair's lesson),
and the deep fills. **ADOPTED alone into config.sh's PATCHES default
(2026-11-05, cont. 20) after the attribution dropped the cost tables** —
receipts: the deep fills −6.8/−7.0/−6.9%, the small prompts −5-6%, greedy
byte-identical everywhere, the vision 4/4, the duel fronts solo 110% /
c2 ~99% of production's top volley / cold 334% / ITL ~107% crossed.

## 003-fp8-pages.patch — PORTED + RE-ANCHORED ONTO ABSORB (the composed candidate); byte-identity REFUTED (control-verified) — the judgment is the quality instruments

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

**STAGING: applies AFTER 001-absorb-mma.patch only** (alphabetical:
absorb-mma < fp8-pages). The compose initially FAILED (cuda_glue.zig:58 ×2
Kernels hunks — absorb's latent_mma fields drifted the trailing context);
RE-ANCHORED (2026-11-05): the paged fields sit before `merge`, the init
calls after `chunks_32_fp8`, absorb's lines untouched; the fresh composed
apply-check passes (1,217 lines). The ttft receipt on the composed-relevant
serves: the paged cold fill 38.1 s ≈ marriage-unpaged 37.9 s at 46k
(paging adds ~nil); the standing config's 35.3 s carries absorb's −7%.
config.sh defaults unchanged pending the quality receipt.

## 005-pagerows-fix.patch — THE CONTAMINATION FIX (staged, 2026-11-05; judged by the canary + the battery re-run)

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
sorts AFTER 003-fp8-pages.patch (the first name sorted before it and
the build's alphabetical apply failed — the rename is the receipt).

## 004-packed-s2.patch — the packed-prompt matmuls in two stages, two blocks an SM (staged 2026-11-06; the mms2 A/B decides)

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

## 009-moeside.patch — a decode window's MoE shared expert on a side stream beside the routed experts (staged 2026-11-07; the moeside A/B decides)

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

## 007-attnfetch8.patch — the latent attention FP8 key tiles load 8 bytes at a time, a tile ahead (staged 2026-11-07; the attnpref A/B decides; NAMED glm-zz- TO SORT AFTER THE STACK — the image applies patches alphabetically and the port depends on the fp8-pages marriage's PAGED8 file state; the first attnpref window burned on exactly this)

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

## 002-exl3prompt.patch — the EXL3 prompt path in one call + no MTP beside a drafter (staged 2026-11-06; the exl3call A/B decides)

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

## 011-zclose.patch — ADOPTED 2026-11-08 (the sixteenth patch; the halt fix)

The tool-call envelope closer scans VALUE-AWARE: a closer tag inside the
payload's own data — a quoted markup example inside a JSON string value, or
inside an `arg_value`/`parameter` region of the XML forms — is the model's
data, not the envelope closer. The upstream scan took the first `</tool_call>`
after the opener with no string/region awareness, so any reply whose JSON
arguments quoted tool-call markup — the shape EVERY fixture-writing reply
produces — was cut mid-string: its payload invalid, the real call lost as
content, and the fragment after the cut re-scanned as a phantom call (with
010-tools256, as a phantom "unknown tool" invocation). Live-reproduced
against the serving stack on 2026-11-08: a `write` call with the markup
quoted in its `content` argument returned **empty arguments** (`"{}"`) and
the tail leaked as content — the client saw `Arguments provided: {}`, and
the model retried the same write forever: THE HALT that blocked the
self-improvement loop (the model could not write a file that mentioned its
own tool-call format).

`envelopeCloser()` tracks JSON string state and `arg_value`/`parameter`
regions across all three envelope scans (the JSON/XML loop in
`tool_parse.envelopes`, the pipe-spelling loop, and `openCall`), falling back
to the plain first-tag find when the payload does not open as JSON or the
JSON never closes outside its strings — a malformed payload cuts and is
rejected exactly as before, so nothing regresses. A companion change
(committed with the port) makes the fork-0103 retry-salvage path require an
OFFERED name: the own-name rule is a whole envelope's rule; an example the
model quotes in prose stays prose.

Receipts: the tool-parse host suite 48/48 on the production base and 51/51
on the rebase tree (the fork's 0103 suite + the two new quoted-markup pins);
compile RC=0 (fatbins + native, sm_121); the patch applies clean on the
tools256 base and reproduces the verified tree byte-identically. The
`Qwen's <tool_call>...` fixture class — the engine writing about its own
tool-call format — now round-trips end to end.

**Knob**: none (server-layer behavior; no env surface).

## 018-callquote.patch — ADOPTED 2026-11-08 (the seventeenth patch; the fork 0103 port)

The fork's 0103: a call quoted inside prose still parses, and the envelope
scan never cuts a call's own data. Two behaviors, one concern (the call's
survival):

1. **A call quoted inside prose still parses.** Prose that quotes the opener
   (`Qwen's <tool_call>...`) ahead of a real call begins the envelope, so the
   call does not parse as its payload: the retry path takes the LAST opener
   inside the envelope (or one before that, when a value quotes the opener
   too), and the quoting prose stays content.
2. **The strict-retry composition** (this line's own rule, folded with the
   port): a call salvaged from inside a rejected envelope must name an
   OFFERED tool — the own-name rule (010-tools256) is a whole envelope's
   rule, so an example the model quotes inside a cut region stays prose and
   never goes out as a phantom call.

The port is the fork's patch 0103 (its final file state) over our composed
base (011-zclose first; both touch only `tool_parse.zig` + its test, order-
free against every kernel patch). The tree it produces is byte-identical to
the line's v124-rebase state `f202781d3` — the suite-green state inherits:
the tool-parse host suite 51/51 (the fork's 0103 suite + the two
quoted-markup pins from 011-zclose), compile RC=0 (fatbins + native, sm_121),
and the fork's 0103 kept-list test passes unchanged.

**Knob**: none (server-layer behavior; no env surface).

**The qualifying battery** (callquotequal, campaign-20261108-214221, the
17-patch image on the testing port): the greedy content sha IDENTICAL (the
same `80cc3802…` as every window — the port must not move the deterministic
probes), the quoted-markup live probe PASS (the halt's shape on the ported
serve: `finish: tool_calls`, `content: None`, complete arguments with the
quoted markup inside), the §2 content gates ALL PASS, hardmode 95 (the
SEVENTEENTH consecutive), the vision 4/4. ADOPTED: the port fixes the
quoted-example class (a call quoted inside prose parses whole; the engine
describing its own tool-call format round-trips) — the same-bits claim held,
so the behavior is the only change.

## 020-cachefirst.patch — ADOPTED 2026-11-09 (the twenty-first patch; the fork 0108 port)

The prompt cache (--prompt-cache-gib) is set aside BEFORE the room is counted
in the streams' windows (TF_PROMPT_CACHE_FIRST=1): the streams share the pages
left (the engine's own window at least) instead of the cache taking what whole
windows leave. ADAPTED to our tree: the plan gate already carried v1.2.5's
`asked` flag (--prompt-cache-gib's own priority — the windows stop at the
engine's own when the cache is asked), so cache_first composes with it — the
flag changes the ROOM the windows count (`room -| cache`), not the window cap.
The value-add on our mode: the FUND-REPORT line prints whenever the room funds
less than the ask — the fork's issue-16 room drift (our warmturnsqual battery
caught the same: none of TF_KV_SHARE=16 kept states' slots fit on a second
start, the room moving 11.8 -> 11.0 GiB with no config change) becomes VISIBLE
at boot instead of silently serving without the cache.

**The qualifying battery** (cachefirstqual, campaign-20261109-140604, the
21-patch image on the testing port): the four-arm OFF/ON plan A/B — the ON
arms' streams ceded pages to the cache-first reserve (3110/3115 -> 3103/3083
pages), the fund-report line never fired at our 3 GiB ask (the drift never
reached the cache's need on this window's serves), the §2 content gates ALL
PASS, hardmode 95 (the TWENTY-FIRST consecutive — the third on the re-grounded
--parallel 2 harness), the vision 4/4; the greedy same-bits witness held (the
battery's own probe returned empty content at max_tokens 64 — the thinking
model ate the budget — the gates' probes carried the real content witness).
ADOPTED: the env default TF_PROMPT_CACHE_FIRST=1 moves into config.sh; the
promoted repo follows on its next promotion sync.

**Knob**: `TF_PROMPT_CACHE_FIRST=0` restores the old plan (windows first).

## 010-tools256.patch — a call to a tool the request did not offer goes out under its own name (round 138; upstream PR #415, issue #256)

- What (upstream's subject, carried here from the forum thread's
  finding — post 973, 2026-11-08): with parallel_tool_calls false, a
  call to a tool the request did not offer was dropped and the
  one-call filter removed what was left, so the reply came back with
  no content, no tool calls and finish "stop" — an agent retrying at
  a fixed seed got the same empty reply and looped. With parallel
  calls the call went back into the reply's text.
  tool_parse.callName now picks the name a parsed call goes out
  under: the offered tool's spelling, else the call's own name when
  it is 1 to 64 of [A-Za-z0-9_-] and its arguments are a finite JSON
  object, as vLLM's parsers do. The client can then answer "unknown
  tool" and the model corrects itself. Any other block stays text in
  both modes. Bare JSON outside an envelope still needs an offered
  name (it is often a structured answer).
- Provenance: upstream commit be8bccbec (PR #415 by Alexbob0, issue
  #256) — in v1.0.0 through v1.2.1, REVERTED before v1.2.2, so
  v1.2.2/1.2.3/1.2.4 lack it (our promoted engine included). The rest
  of the #415 rework (Policy.parsedContent, Policy.kept,
  wholeEnvelope, the prose_sent stream tail, the attach rework in
  openai_calls.zig) is ALREADY in our v1.2.4 tree — only callName's
  own-name rule was reverted with it. This patch re-applies exactly
  that rule and flips the test back to the #415 behavior.
- Port (v1.2.4 + the 14-patch stack, on v124-rebase): 2 files —
  tool_parse.zig's callName (+7/-2), tool_parse_test.zig's test flip
  to the upstream behavior (the kept cases: a name that is no
  function name, arguments holding NaN; the new case: a well-formed
  unoffered call goes out under its own name in BOTH modes). NO
  kernel/record work — a server-layer change only.
- Verify: the compile RC=0 (fatbins + native, sm_121); the unit test
  runs in the native build's test step; the tools256qual A/B battery
  (the §2 gates, hardmode, the vision) guards the serve.
- OWNER: this line; STATUS: **STAGED — the tools256qual battery
  decides** (the gates + hardmode's sixteenth 95 + the vision 4/4;
  the fix's own unit test is the primary witness).

## 016-zstep.patch — the 4-bit read-once chain as dependent launches, exl3r c3 (round 138; Mia 1104's 0082 port)

- What (Mia's subject: the 4-bit read-once chain as dependent launches
  — rot_in, gate/up, epilogue, down; on their 0067 = our adopted
  zshfl): the decode chain's kernels launch with programmatic stream
  serialization — each one's launch and its prologue overlap the
  kernel before it (the `.pdl` launch flag when both projections take
  the new kernels; TF_EXL3_PDL=0 turns it off, the same bits). Hazard
  rules as pdl5's: before griddepcontrol.wait only immutable loads and
  the plan; every read of another grid's output and every scratch
  write after it; every CTA waits (no exit before a wait).
  tf_exl3_experts_rot_in and tf_exl3_gateup_epilogue: wait, then
  trigger, at entry; the new tf_exl3_grouped_1_k8r8p/_k8r16p (Load
  SHFL_PDL): before the wait the plan, the trellis pointer and width
  tables and the first k tile's words; the rows' A fragments and the
  partials after it. Fork-measured: the chain −6.9 to −14.5% at 1-32
  rows (RTX PRO 6000, cold 4-bit, kernel trains), exact in 108/108
  cells. A DECODE-window launch-overlap lever — the c2/c4 concurrency
  cells its home (the 0030 lesson).
- Port (v1.2.4 + the 13-patch stack, on v124-rebase): 7 of 9 hunks
  applied clean via git apply --reject (the grouped_p/pdl fields, the
  kernel resolves, the envOn TF_EXL3_PDL and all four `.pdl = chain`
  launch flags); the 2 rejected .zig hunks hand-applied — the
  tilesFor pdl field adapted to our single Layer.uniform_k2 form, the
  chain insert after our core()'s v1.2.4 act_mode check. The fork's
  text otherwise VERBATIM (line-verified: 15/15 .cu, 43/43 .cuh,
  17/17 .zig). The fork's own knob **TF_EXL3_PDL=0**; no _cl twins
  needed. The new p kernels ride the existing grouped_body_v2 template;
  rot_in/gateup_epilogue gain wait+trigger at entry — their register
  counts measured on our sm_121 build (see the commit message; the
  fork shipped no records patch — the wait/trigger pair is
  register-neutral).
- Verify: the compile RC=0 (fatbins + native, nvcc sm_121, zig 0.17.0,
  the builder base image); fresh-parent + the shipped patch = the commit
  tree byte-identical. NAMED 016-zstep TO SORT AFTER zshfl (zt > zh).
- OWNER: this line; STATUS: **ADOPTED (round 138, the 0082qual A/B —
  campaign-20261108-024926: both arms the SAME 14-patch image,
  TF_EXL3_PDL=0 vs unset; the arms' greedy content IDENTICAL — the
  same 80cc3802… sha as every window, the fork's 108/108 exactness
  confirmed on the real model; the §2 gates ALL PASS, hardmode 95 (the
  FOURTEENTH consecutive), the vision 4/4, prefill flat (the bench pp
  d0 1,528, inside the band); the fork's measured chain gain did NOT
  transfer to our shape — c2/c4/ITL/solo FLAT within the arm spread
  (the launch-COUNT reduction of 0030 transferred at concurrency; the
  launch-OVERLAP of the same kernels doesn't — the second decode-side
  non-transfer); ADOPTED anyway: bit-safe, knobbed, neutral everywhere,
  and the fork's 0083+ builds on this exact base; config.sh's
  fourteenth patch).

## 015-zshfl.patch — the 4-bit grouped experts read every trellis word once, exl3r (round 137; Mia 1104's 0081 port)

- What (Mia's subject: 4-bit grouped experts read every trellis word
  once, and decode with fewer instructions; the same bits): the grouped
  decode kernel's lanes each loaded the two 32-bit words their 16-bit
  windows span — every trellis word fetched twice (the fork's NCU:
  69-71 MB of L2 traffic for 33.7 MB of experts). Now lane l loads word
  l once (one 128-byte warp load a 4-bit tile) and takes its windows'
  words from their owners by __shfl_sync; the next tile's words and its
  A fragment issue a tile ahead (warp_tiles_shfl); at 4 bits the windows
  sit at fixed nibble offsets (lane_states8: funnel shifts and one
  byte_perm) and the mcg mask stays in a register (26 of the k step's
  252 instructions were mask MOVs; now 216). Same words, same A values,
  same decoded values, same MMA chain, same warp-order sum: the same
  bits. Fork-measured (RTX PRO 6000, 400 W, cold 4-bit experts):
  gate/up to −14.0% and down to −14.0% at 1-32 rows — a DECODE-window
  lever (the c2/c4 concurrency cells its home).
- Port (v1.2.4 + the 12-patch stack, on v124-rebase): 3 of 4 hunks
  applied clean via git apply --reject; the ONE rejected hunk (the
  tilesFor choice line) hand-applied adapted to our single
  Layer.uniform_k2 (the zmoe-fuse port's form — the fork splits
  uniform_k2_gu/_d). The fork's text otherwise VERBATIM (line-verified:
  14/14 .cu, 97/97 .cuh, 12/12 .zig). The fork's own knob
  **TF_EXL3_SHFL=0** restores the old choice (wired in their .zig —
  envOn, default on; no _cl twins needed). New kernels
  tf_exl3_grouped_1_k8r8s (≤ 8 rows) and _k8r16s (9-32 rows) ride the
  existing grouped_body_v2 template — the existing instantiations'
  SASS unchanged; unlisted in the registry → unchecked (the 0030
  precedent). The planted faults (SHFL_SRC/SHFL_A) are inert enum
  variants — only SHFL instantiates.
- Verify: the compile RC=0 (fatbins + native, nvcc sm_121, zig 0.17.0,
  the builder base image); fresh-parent + the shipped patch = the commit
  tree byte-identical. NAMED 015-zshfl TO SORT AFTER zs2 (zh > z2).
- OWNER: this line; STATUS: **ADOPTED (round 137 cont. 8, the 0081qual
  A/B — campaign-20261107-232039: both arms the SAME 13-patch image,
  TF_EXL3_SHFL=0 vs unset; the arms' greedy content IDENTICAL — the
  same 80cc3802… sha as every window; the §2 gates ALL PASS, hardmode
  95 (the THIRTEENTH consecutive), the vision 4/4, prefill flat; the
  fork's measured decode gain did NOT transfer to our shape — the
  c2/c4/ITL/solo cells read FLAT within the arm spread (the L2-gather
  saving matters on their cold-expert trains, not our hot hierarchy);
  ADOPTED anyway: bit-safe, knobbed, neutral on every instrument here,
  and the fork's 0082 builds on this exact base; config.sh's thirteenth
  patch).

## 014-zs2.patch — the packed prompt GEMMs' loads fixed once a block + 8-bit codes to bf16 pairs in fewer steps, P2 (round 137; Mia 1104's 0080 port)

- What (Mia's subject: the packed prompt GEMMs' loads fixed once a block
  and 8-bit codes to bf16 pairs in fewer steps; the same bits):
  glm_mm{4,6,8}_128s2 (the packed prompt linears, sk = 1) keep their
  tiles, B fragments, the four-K16 MMA chain from zero a 64-group and
  the ascending scale FMAs, and the bf16 RN (or fp32) store; only how
  they are fed changes (mm_kernel's P2 template param): each thread's
  cp.async sources, destinations and bounds worked out once a block (a
  stage adds its group's offset — the weights still load before
  griddepcontrol.wait, the rows after it) + bpairs8_fast (two codes u
  spread into a bf16 pair's low bytes, a = 128 + (u & 127) and c = 256
  or 128 by two LOP3s, a − c = u − 128 by one bf16x2 subtraction that
  rounds nothing — the same values as bf16((float)(u − 128))). The other
  glm_mm instances compile to the same SASS as before (P2 = false
  default). Fork-measured: 1.116-1.138x at GLM's prompt shapes, energy
  −8-12%/call; glm_mm8_128s2's loop a 64-K group 300 static + ~320
  dynamic instrs → 205 with the loads inline, 122 → 125 regs, no spills.
- Port (v1.2.4 + the 11-patch stack, on v124-rebase): 11 of 12 hunks
  applied clean via git apply --reject; the ONE rejected hunk (the
  mm_kernel template line) hand-applied — the fork's base carries 0073's
  xtile param beside zslice (our signature keeps v1.2.4's two-param
  form; P2 does not use it). The fork's text otherwise VERBATIM
  (line-verified). The classic packed-prompt kernels kept as the
  _128s2_cl twins (the pre-port instantiation verbatim); TF_GLM_MM_P2=0
  resolves them in cuda_mm.zig's load() (envOn, default on — the 0030
  knob pattern). NO contract-record work: the _128s2 kernels are not in
  our registry (unlisted → unchecked, the 0030-new-kernel precedent).
- Verify: the compile RC=0 (fatbins + native, nvcc sm_121, zig 0.17.0,
  the builder base image); fresh-parent + the shipped patch = the commit
  tree byte-identical (tree f8b47b31…). OUR cuobjdump on the built
  sm_121 fatbin CONFIRMS the fork's register claim: glm_mm8_128s2
  122 → 125 (the _cl twins at the pre-port 122/119/122); the _128s2
  kernels are not in our registry → unchecked, no record work. NAMED
  014-zs2 TO SORT AFTER zprompt (zs > zp).
- OWNER: this line; STATUS: **ADOPTED (round 137 cont. 4, the 0080qual
  A/B — campaign-20261107-214342: both arms the SAME 12-patch image,
  TF_GLM_MM_P2=0 vs unset; the arms' greedy content IDENTICAL — the
  same 80cc3802… sha as every window; the §2 gates ALL PASS, hardmode
  95 (the TWELFTH consecutive), the vision 4/4; **THE PREFILL FRONT
  CROSSED** — the bench pp d0 1,519 vs production's 1,518 = 100.1% (the
  chain 1,458 → 1,468 → 1,495 → 1,519; the TTFT slope 0.448 → 0.441 =
  −1.6% agrees); decode flat within the arm spread; the load walls
  unchanged (86/89 s); config.sh's twelfth patch).

## 013-zprompt.patch — the prompt experts' main loop reworked, exl3p (round 137; Mia 1104's 0078+0079 port)

- What (Mia's 0078 subject: the prompt kernels' main loop compiled for an
  item's 8-member column blocks, the next k tile decoded among the current
  MMAs, butterflies one FFMA, vector stores; the same bits): the new tmain
  <MATS, XR, K2, NBA, PS> (no predicate, no MMA on a member-less column
  block, no member-row load nobody reads; two decoded A fragment sets across
  the stage barrier — 4 stages at shared rows, 3 at separate gate/up rows;
  TLoads fixes each thread's cp.async pieces once an item; the mcg mask one
  LOP3 on a register (mcg2); 4-bit tiles from the lane's word and its
  neighbour's (decode_a8)) + fwht128f (each cross-lane butterfly one FFMA —
  s v exact, rounds once) + Xd's 4 halves one 8-byte store and y's 4 floats
  one 16-byte store (Kernels.run refuses a y not 16-byte or an xd not
  8-byte aligned) + the NBA dispatch (TF_EXL3_PROMPT_NBA: the loop compiled
  per 8-member-block count 1..8). Fork-measured (GPU0 400 W, 2,048 rows):
  gate/up 1.177x, down 1.161x, energy −9-10%/call; SASS stage 361→210-243
  instrs, 122 regs no spills. 0079's contract records ride along (the
  prompt kernels' nvcc-13.3 usage re-measured; our sm_121 numbers verified
  against our own build's cuobjdump — see the commit message).
- Port (v1.2.4 + the 10-patch stack, on v124-rebase): ALL of 0078's text
  verified line-identical against the fork's added lines (244/244 .cuh,
  18/18 .cu) except the documented adaptations: our tree is 4-bit-only —
  the fork's K2 template param stays and instantiates at 8 only;
  tstage_halves/tsmem_bytes keep our 1/0-param forms (identical values at
  K2 8); tgateup takes the fork's <XR, K2> and our gu kernel call sites
  pass 8; the fork's 0079 pending_133 _k6 hunk SKIPPED (our tree has no _k6
  prompt kernels). The classic loop kept as tmain_cl/tspill_cl/tgateup_cl +
  the tf_exl3_prompt_{gu,down}_cl kernel twins (our pre-port bodies
  verbatim); TF_GLM_EXL3P=0 resolves them in exl3_prompt.zig's resolve()
  (envOn, default on — the 0030 knob pattern; no #2405 surface).
- Verify: the compile RC=0 (fatbins + native, nvcc sm_121, zig 0.17.0, the
  builder base image); fresh-parent + the shipped patch = the commit tree
  byte-identical (0 diff lines). NAMED 013-zprompt TO SORT AFTER
  zmoe-fuse (the .cu hunks assume the post-0030 experts file; zp > zm).
- OWNER: this line; STATUS: **ADOPTED (round 137, the exl3pqual A/B —
  campaign-20261107-200411: both arms the SAME 11-patch image,
  TF_GLM_EXL3P=0 vs unset; the arms' greedy content IDENTICAL — the same
  80cc3802… sha as every window, the same-bits claim proven; the §2 gates
  ALL PASS, hardmode 95 (the ELEVENTH consecutive), the vision 4/4; THE
  PREFILL LEVER REAL — the bench pp d0 1,495 (the ON arm; the last three
  windows read 1,458-1,468) + the duel_arm TTFT slope 0.458 → 0.447
  (−2.4%) agree on ~2-2.5% whole-prefill (the front 96.0% → 98.5%);
  decode flat within the arm spread (c2 117.3 vs 118.1, c4 166.8 vs
  167.6, ITL 58.4 vs 58.6 ms/chunk; the solo 68.5-vs-66.8 spread is
  run-order drift — the OFF arm the highest solo ever recorded, the ON
  arm inside history, the prompt loop decode-inert; the duel re-pair
  re-grounds the decode rows); the load walls unchanged (83/87 s);
  config.sh's eleventh patch).

## 012-zmoe-fuse.patch — a decode window's MoE glue fused + one-width EXL3 decode tiles + KDA's f_b/g_b in one launch (round 136; Mia 1104's 0030 port)

- What (Mia's subject, three keep-the-bits fusions for decode windows):
  (1) the MoE glue fused — tf_glm_topk_group runs a window's top-k
  (glm_moe::topk_row, tf_glm_topk's own per-row code) AND, for the EXL3
  experts, the compact picks and their grouping (tf_exl3::group_rows in the
  new exl3_group.cuh, tf_exl3_group's own code) in one 1024-thread block;
  the grouped path's experts run core-only (two 2D copies, tf_exl3_group,
  put_slot and glue.combine GONE) and tf_exl3_down_combine takes the shared
  expert's row as an extra slot (weight wts[r][slots], summed LAST —
  tf_glm_combine's order) after the side stream's join. (2) The grouped EXL3
  decode kernel at one trellis width (grouped_body_v2: tf_exl3_grouped_1_k6r8/
  _k8r8 — no 15-way switch, 79-80 registers not 158 — plus _1_nt4, 4 tiles a
  block), chosen by tilesFor per projection (rows ≤ 8 on a uniform 3/4-bit
  projection → r8; wider windows → nt4 where it measured faster; our Layer
  keeps ONE uniform_k2 — the loader verified EVERY projection — so tilesFor
  reads it for both which-branches). (3) KDA's f_b and g_b (one shape) in one
  launch (glm_mm*_16x2 via mm_kernel's zslice). TF_GLM_MOE_FUSE=0 unfuses
  (envOn, default on — the engine switch came from Mia's 0031, which also
  carries the retired steplink; a TF_GLM_* getenv knob, no #2405 surface).
- Port (v1.2.4 + the 9-patch stack, commit 39ac60e3b on v124-rebase): 8 files
  applied clean; 4 hunks re-anchored by hand — exl3_experts.cu's include
  (v1.2.4's decode/plan includes), the run() split in src/cuda/exl3_experts.zig
  (v1.2.4's act_mode check moved INTO core() so the grouped path gates there
  too), cuda_exl3.zig's grouped fns (our tests follow run()), cuda_forward.zig's
  field (our extra fields sit between taps and side); tilesFor's
  uniform_k2_gu/_d read our single field. The engine knob wiring ported from
  0031 (the engine field + envOn + both Forward constructions carry .moe_fuse).
- Verify: the compile RC=0 (fatbins + native, nvcc sm_121, zig 0.17.0, the
  builder base image); fresh-parent + the shipped patch = the commit tree
  byte-identical (0 diff lines). NAMED 012-zmoe-fuse TO SORT AFTER moeside
  (the engine hunks assume the side field and the fork's 0030 followed 0006).
- OWNER: this line; STATUS: **ADOPTED (round 136, the moefusequal A/B —
  campaign-20261107-172250: both arms the SAME 10-patch image, the knob flips
  the path; the arms' greedy content IDENTICAL — the same 80cc3802… sha as
  every window; the §2 gates ALL PASS, hardmode 95 (the TENTH consecutive),
  the vision 4/4; c4 166.1 vs the OFF arm's 159.4 (+4.2% — our best c4), c2
  117.1 vs 115.9 (+1.0%), ITL 58.4 vs 59.3 ms/chunk (−1.5%), solo flat,
  prefill flat (the prompt path untouched by design — the bench pp d0 1,468),
  the load walls unchanged (83/87 s); config.sh's tenth patch).

## 022-shared-budgets.patch — DFlash2's shared rounds keep the budgets rule (round 141, the #2793 port)

- WHAT: upstream #2793 (commit cc2fa8d23690, PR #2793, fixes #2720, 2026-11-11)
  — DFlash2's shared draft rounds sized every stream's drafts by last grant +
  slack WITHOUT the budgets rule, so a stream whose lane was BLOCKED (the pool's
  fits() refusing at the 524,288 window) sat at zero drafts while its peers
  decoded. The one functional line: `.allocate_shared_drafts = drafting and
  !block` — a blocked stream stops pricing shared drafts, so the budget
  redistributes to the streams that can use it. Upstream's measured claim on OUR
  exact shape (two GB10s, TP=2, four-stream decode): **3.7% faster greedy / 3.5%
  at T=0.7; one-stream unchanged; every reply's tokens unchanged.**
- PORT: no port needed — upstream's own diff, staged verbatim as
  022-shared-budgets.patch with the provenance header. Host-side only:
  cuda_lanes.zig's one lane-admission line + two host-test files
  (cuda_zero_budget_test.zig, copy_drafts_cuda_test.zig); no kernels, no
  contract records. Numbered 022 to sort LAST (the line's rule: the next port
  takes the next free number; the fix assumes the whole adopted stack's lane
  state, and no stack member touches cuda_lanes.zig — order-free among them).
- Verify: applies clean against pristine v1.2.6 AND on the full 18-patch
  DEFAULT stack in alphabetical order (scratch clone of the tag, 2026-11-11;
  the 017/019/021 non-default patches excluded from the verify composition).
  Symbol check clean: no introduced names — the functional line reuses the
  in-scope `block` variable; no duplicate-member or shadow risk. Compile risk
  minimal (one boolean conjunction in an existing struct literal).
- OWNER: this line; STATUS: STAGED (value-first; the A/B battery is
  stagebrief'd in LAUNCH.md round 141 cont. 15 — the value gate reads the
  CONCURRENT steady-state instruments: c2/c4 decode, the ITL, hardmode holding
  95; QUALIFIED = joins config.sh's PATCHES default).
