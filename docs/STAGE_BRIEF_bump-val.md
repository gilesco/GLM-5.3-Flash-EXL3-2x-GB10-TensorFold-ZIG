# STAGE BRIEF — the v1.3.5 bump window (pre-staged; launches when the
# release watch fires)

## The trigger

`scripts/upstream-release-watch.sh` fires on a tag newer than v1.3.4
(main's Unreleased section is carrying the candidates; 771 commits had
climbed by 2026-11-24, the daily-release cadence through 1.3.0→1.3.4
preceded this arc). On the watch's fire: this brief governs the bump
window. Until then: no launch — every candidate knob is main-only, not
in the v1.3.4 pin (verified 2026-11-24: `TF_GLM_WIDE_EXPERT_TILE` is in
main's cuda_experts.zig + the env registry, absent from v1.3.4's tree;
#2279's GLM graphs and #4701's pipelined prompt experts are likewise
Unreleased).

## The value-if-yes — what the bump carries FREE (no port work)

1. **`TF_GLM_WIDE_EXPERT_TILE` (#4565, MERGED into main)** — routed-
   expert down for decode windows wider than 16 rows under the 64-pair
   factored tile that matches gate-up; bit-equal by construction; a
   DFlash2 block-16 + pending row = 17 rows engages it on every drafted
   window. The value question: the decode row (the anchors' 77.3) — the
   knob's own A/B (kill under +1%) is still to run upstream; OUR window
   reads it as the candidate arm.
2. **#4701's pipelined prompt experts (when it lands)** — the upstream
   mainline of our own 013-zprompt: replaces the hand-port at the bump
   (one fewer member to re-anchor every release) plus the newer SM121
   pipelining (their isolated gu −24% at 4,096 rows).
3. **The resume bundle** — #1411's rows store (`--learn-conversations`:
   states read back after eviction/restart instead of a full re-prefill),
   #4694's cancel-keeps-prefix, #4856's flush retain count. Value gate:
   the resume rows, not the anchors' decode/prefill.
4. **Watch free-riders**: #4516's DFlash2 drafter graphs + QL span are
   MERGED for the drafter side (`TF_DFLASH_GRAPH=1`,
   `TF_DFLASH_QL_SPAN=1`) — our decode is DFlash2-drafted, so these
   compose with the adopted PDL on the target side. GLM- receipts
   pending; they are candidate arms if they land GLM-side.

## The window shape (the bump protocol, the two-gate staging rule)

1. The watch fires → the tag's commit lands in `scripts/local.sh`
   TF_COMMIT (gate 2) while the store regenerates onto the release
   (gate 1) — the tensorfold-patch-craft discipline: the composed tree,
   the byte-exact round-trip, the compile gate.
2. The bumpval battery (the standing one) qualifies: the witness
   `80cc3802…` IDENTICAL across the bump, the §2 gates, hardmode on the
   3.1.0 frame, the vision suite, the walls, the value bracket.
3. **The wide-tile candidate arm** rides the same window: after the
   qualified base serves, one order-matched A/B
   (default → `TF_GLM_WIDE_EXPERT_TILE=1` → default) with the decode
   cells as the value read. The witness must hold on all three arms.
4. Promotion per the round-157/159 shape: the pin moves, production
   serves, the state docs same-sitting.

## The kill criteria

- ANY gate FAIL holds the pin at v1.3.4 until understood (the standing
  bump rule).
- The wide-tile arm's witness moves → the knob stays default-off; the
  defect question opens with the receipt.
- The wide-tile cells in-band → the knob stays default-off (the value
  does not transfer at our shape; the bump itself stands or falls on
  its own gates regardless).

## The prior instruments

- The bump protocol: the v134val battery (campaign-20261122-232612),
  the tenth bump — the witness discipline and the value bracket.
- The candidate-arm shape: the indexsplitval window
  (campaign-20261124-191142) — the three-arm order-matched bracket with
  the value cells named up front. THE NAMED CELLS FOR THIS BRIEF: the
  tg cells at depth (a DFlash2 block+pending row is 17 rows — the
  wide-tile mechanism engages on drafted windows; the d0/d4096/d8192
  tg cells are the value cells, the pp cells expected flat).
- The composition lesson: the fp8-pages marriage — the bump's free
  riders are adopted on the qualified base, never bundled blind.

## The desk check before the launch (when the watch fires)

- The two staging gates: the store regen AND `scripts/local.sh`
  TF_COMMIT (the round-155/158 lesson: the stale head pin burned two
  windows).
- The new knobs reach the binary: grep the serve line for
  `TF_GLM_WIDE_EXPERT_TILE` on the candidate arm; the env forwarding
  prefix list covers `TF_GLM_*`.
- DRY_RUN green before the real launch; the continuation scanner on
  any new phase code; the launch is the last action of the sitting.
