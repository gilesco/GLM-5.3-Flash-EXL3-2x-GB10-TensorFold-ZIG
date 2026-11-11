# Eval history — the completed round arcs

<!-- ARCHIVED ROUND HISTORY — immutable once written. New round arcs append to
     docs/TOOL_EVAL_TESTING.md's round-history region until archived. -->

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
- [x] **The #2744 vision re-encode port — RETIRED (window 44's value-first
  verdict: MISSED on the first valid room-gated reading; the kill criterion
  fired legitimately; the question closes as upstream data)** — windows
  39/40/41/42 narrowed the instrument four times; window 43's interleaved
  race ran but its verdict leg did NOT (the stale `cp2-` name killed the
  room-matched curl — a dead race recorded as 0.01 s, no verdict); window
  44 (campaign-20261111-081848) fixed the phase adversarially (the `cp-`
  name + race plumbing guards) and delivered the first VALID reading: the
  room gate PASSED (12.2 vs 12.4 GiB — 0.2), both plumbing guards OK, the
  mechanism witness true (`cached=0` on every race stream), §2 ALL PASS
  (**hardmode 95 — the THIRTY-FIRST consecutive**), the vision 4/4 — and
  the value gate MISSED: the room-matched interleaved race 25.53 s vs the
  OFF arm's 25.52 s (parity, −0.04%; the >5% ask unmet). The kill
  criterion's retire path is explicit: no value on a valid reading =>
  RETIRE. `021-vision2744.patch` leaves the candidate stack (never
  entered config.sh's PATCHES — nothing to un-adopt; stays in patches/ as
  receipted provenance) and the v1.2.7 rebase picks the fix up free. The
  mechanism reading: upstream's receipt measured multi-image interleaved
  prompts re-encoding each other's chunks on THEIR shape; on OURS
  (2×GB10 TP=2, PARALLEL=4, the 2048-row chunking, 18k/17k-token vision
  prompts) the chunk-switch re-encode cost is not measurable — removing
  it moves nothing user-visible. The instrument's history: window 40's
  room gate PASSED (the arms' room
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
  TWENTY-EIGHTH consecutive** — the vision 4/4). Window 42 ran the COLD race
  (no warm-up; the race bodies' prefixes de-collided from the t1/t2
  probes): the mechanism witness READ TRUE — `cached=0` on every race
  stream, both arms — and the decisive comparison is PARITY: the OFF arm's
  cold race 23.38 s vs the ON arm's 23.41 s (−0.1%; the ttft pairs
  10.80/10.89 vs 10.82/10.92). The room gate sat AT the line (12.4 vs
  11.4 GiB). The room-matched race ran a DIFFERENT shape (the cistern fill
  word tokenizes +1 vs meadow — 4096 more prompt tokens — so it had no
  OFF-arm counterpart; recorded at 31.29 s, not a value number). **The
  mechanism reading**: the re-encode fires per chunk-switch when the owner
  flipped AND the chunk's span contains image rows — a single image at the
  TOP of a d4096 prompt gets ONE encode (chunk 1); chunks 2–3 carry no
  image rows, so the owner flips never re-encode anything. Upstream's
  receipt measured interleaved MULTI-image prompts (their 12 vs 18 tower
  passes = 6 re-encodes). **The v5 instrument (window 43)**: THREE images
  per stream, one per chunk — each chunk switch with an owner flip
  re-encodes the later-chunk images pre-fix (~8 extra encodes per race);
  the room-matched race reuses the same bodies (the settle restart wipes
  the page cache — per-process — so both sides of the value gate run the
  same shape cold). **Window 43 ran** (campaign-20261111-035237): the
  guards all held — the greedy TEXT sha `80cc3802…` identical across both
  arms, §2 ALL PASS (**hardmode 95 — the THIRTIETH consecutive**), the
  vision 4/4 — and the arm-loop interleaved race read parity (25.52 vs
  25.56 s, `cached=0` on every race stream). But the value gate never got
  its number: the room gate FAILED on the first serve (11.0 vs 12.4 GiB —
  exactly why the room-matched leg exists), and the room-matched race
  itself never ran — the curl read stale `cp2-` body names (renamed `cp-`
  by the same sitting's cont. 12 commit), died under `|| true`, and the
  receipt recorded a **0.01 s "aggregate" with no `rm-cp-*` envelopes in
  the campaign dir — a dead race that would have SPURIOUSLY QUALIFIED the
  patch** had it been read as value. The receipt carries no VERDICT; the
  retirement claimed in an uncommitted comment was withdrawn — the kill
  criterion did NOT fire. The phase is fixed (the `cp-` name + race
  plumbing guards that fail loudly on a dead stream) and re-runs value-
  first as window 44; the kill criterion stands: no value on a VALID
  room-gated reading retires the patch. (campaign-20261111-000839): upstream's
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
- [x] **The DRAFTS=0 + LIVE_HALF composition — RETIRED (window 48's value-first
  verdict: the value gate MISSED decisively on the decode trade)** (campaign-20261111-
  153202): the ON arm's c4 aggregate 35.1 t/s vs the gate's ≤5%-of-185.1 ask — an ~81%
  decode loss; the solo decode halved (35.2/34.7 vs 70.2/70.3): DFlash2 drafts are worth
  ~2× on decode on our shape (the ITL probe's chunk count is the mechanism: 2,017
  single-token chunks vs 501 multi-token chunks for the same 2,048 tokens). The resume
  value the composition bought (5.22 vs 5.42 s, −3.7%) is two orders too small to pay
  for halving decode. The fund question answered YES anyway: the ON arm funded 15 of 16
  kept-state slots (vs the OFF arm's 6 of 16) and lifted enough-for 3 → 4 — the live-half
  keep plus the drafter's freed 2.84 GiB bought the store room — but the eviction warning
  stayed PRESENT (15 < 16) and the price disqualifies. **The funding path is now
  MEASURED**: the only lever that funds the store costs the drafter, and the drafter
  pays for itself ~2× on decode; the cacheless standing with the funded-6 store is the
  honest optimum. The DRAFTS env witness printed a FALSE placebo (the knob is
  config-side, never in the container env — the serve line's 78.80 GiB model + the
  campaign log's restart line prove placement); the witness instrument must match the
  knob's forwarding path. The window-drift watch FIRED: the OFF arm's c4 195.8 is the
  fourth consecutive first-arm climb (170.0 → 182.0 → 185.1 → 195.8, +15% cumulative);
  no cross-window c4 comparison is valid as a delta. **The watch's
  decomposition (window 49, campaign-20261111-170638): the drift is
  WINDOW-TO-WINDOW, not order** — six fresh serves in one window read
  FLAT (c4 −0.19 t/s/serve, −0.7% first-to-last; solo/c2/ITL flatter
  still; the clocks 3,894–3,898 MHz throughout), so the order term does
  NOT explain the climb; the value-gate rule is precise: order-matched
  same-window comparison is sufficient, no cross-window c4 delta is
  valid, and any value gate inside the ±5%-per-window drift band judges
  on order-matched same-window instruments exclusively. A guard-timing
  artifact (three receipt lines say FAILED while every checked artifact
  is valid; re-run passes 6/6) is recorded in the same entry — the
  model stands, no value gate depended on the guard lines.
- [x] **The #2793 shared-budgets port — QUALIFIED and ADOPTED (window 45's value-first
  verdict: the value gate CROSSED at +6.1%)** (campaign-20261111-094017): upstream #2793
  (commit cc2fa8d23690, fixes #2720) — DFlash2's shared draft rounds priced every stream's
  drafts by last grant + slack without the budgets rule, so a BLOCKED lane ratcheted its
  stream to zero drafts while peers decoded (upstream's own two-GB10 TP=2 receipt: drafted
  rows/stream-round 3.27 → 2.36, four-stream aggregate −1.9% to −8.8%). Ported as
  022-shared-budgets.patch (upstream's own diff verbatim; scratch-clone verified against
  pristine v1.2.6 AND the full 18-patch default stack; no introduced names). The A/B: the
  greedy TEXT sha `80cc3802…` IDENTICAL on all three serves, the room gate PASS (12.4 vs
  13.0 GiB), both c4 plumbing guards OK, the §2 gates ALL PASS (**hardmode 95 — the
  THIRTY-SECOND consecutive**), the vision 4/4, the bench bands held — and the value gate
  CROSSED: the room-matched c4 aggregate **180.4 vs the OFF arm's 170.0 t/s (+6.1%)**,
  beyond the >3% gate and upstream's own 3.7% greedy claim. The mechanism gradient
  (solo +1.0%, c2 flat, c4 +6.1%) confirms the blocked-lane ratchet's signature — the
  concurrent shape is where the ratchet lived. ADOPTED as the sixteenth patch
  (config.sh's PATCHES default); the promoted repo mirrors it on its promotion sync;
  the phase retired with its question closed. **CONFIRMED TWICE on independent
  instruments**: the duel re-pair (window 46, campaign-20261111-110018 — both arms far
  above the pre-adoption row) and the order-drift settle (window 47,
  campaign-20261111-150137 — the order-matched cross-window value +7.1% to +8.9%, the
  second-arm edge repeating across w45/46/47 while the pre-adoption pairs read flat;
  the window-drift watch is OPEN, LAUNCH cont. 20).
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
