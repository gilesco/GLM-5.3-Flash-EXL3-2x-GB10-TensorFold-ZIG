# STAGE BRIEF — v133val (the v1.3.3 bump)

## The question

Does the v1.3.3 engine (`1e4a32cb`, 631 commits past v1.3.2) + the re-anchored
16-patch store hold every quality gate — and do the release's default-behavior
changes move a user-visible number at our shape?

## The value-if-yes

- The line stays current (the ninth bump) with the witness unchanged.
- #3486's long-prompt step sharing and #3693's identical-prompt leader join
  are decode-side levers: if either transfers, the steady-state decode row
  (77.3, the PDL-bracket mean re-dated round 157) moves again.
- #3164's resume skip: warm-resume quality unchanged is the gate; no perf row
  is staged to move (our warm path closes round 141's arc: parity).

## The ground

- The compose `627e0238` (branch compose-v133 in /tmp/opencode/tf130-rt):
  pristine v1.3.3 + the store, the round-trip PROVEN byte-exact.
- The fork's exl3p NBA ground stays primary at 4 bits; the k6 twins
  (#3249's) ride it; the fingerprint layout 23 (numerics beside
  draft_split); the lanes ground is v1.3.3's own (the shared-cap depth
  state machine — no member owns those files).
- The b7e4f6d store carries the four regenerated members
  (001/002/003/013) + the round-157 fixed regen format.

## The gates (all must hold)

1. The same-bits greedy witness `80cc3802…` IDENTICAL (the eighth→ninth
   bump must not move the deterministic probes).
2. §2 content gates g1–g4 ALL PASS.
3. hardmode **94 on tool-eval-bench 3.1.0** holds (the re-based boundary).
4. The vision suite 4/4 (the repo's own assets).
5. The load walls in band (83 s ± the boot wobble).
6. Strict-TF_ refusal lines at boot: 0 (the video-library note excluded).

## The value bracket (secondary, order-matched)

The steady-state decode probe ×3 across the battery's serve: the default(1)
reading opens, the default(2) reading closes the bracket. In-band both sides
→ no decode row move; a consistent shift beyond the ±5% order-matched band
with both bracket arms agreeing → the decode row re-dates again (the receipt
names which lever claims it: #3486 or #3693 — the bracket cannot separate
them; a claim needs a follow-up knob A/B, NOT this battery).

## The kill criteria

- ANY gate FAIL → the pin holds at v1.3.2; the defect question opens with
  the receipt.
- The witness moved → VOID regardless of the scores; the rebase ground is
  wrong until understood.

## The prior instrument

This is the v132val battery's shape exactly (the round-157 window,
campaign-20261121-215341): the same standing restart, the same §2 gates, the
same hardmode invocation, the same vision suite, the same bracket design —
the ground moved one release, nothing else. The round-141 lesson holds: the
gate probes use ≥1024 max_tokens; the whole-envelope sha is not an
instrument (gates bind on normalized content).

## The launch

`scripts/autonomous-launch.sh "preflight v133val summary"` — the v133val
phase (session-specific; retires with its receipt), last action of the
sitting.
