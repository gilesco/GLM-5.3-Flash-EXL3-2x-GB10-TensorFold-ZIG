# STAGE BRIEF — v134val (the v1.3.4 bump)

## The question

Does the v1.3.4 engine (`12ebd414`, 362 commits past v1.3.3) + the
re-anchored 16-patch store hold every quality gate — and do the
release's value candidates move a user-visible number at our shape?

## The value-if-yes

- The line stays current (the tenth bump) with the witness unchanged.
- **#4493/#4619's `TF_GLM_PAIR_EXPERTS=1`** (opt-in): the release's
  claimed number on OUR shape — "+15% prompts at 2K, ~+5% at 8K/32K on
  two GB10s". The battery does NOT measure it (default-off; an A/B
  needs its own window with the knob flipped — a follow-up pairexval
  window is the candidate and the reason this bump is worth more than
  currency).
- #4499's prefill skips and #4427's cached-page startup budget: the
  walls row and the load line are the witnesses; no row is staged to
  move (outputs unchanged upstream).
- #3659's `TF_GLM_MOE_DIRECT=1` (opt-in, bit-equal): composed beside
  our fused-select ground; no gate staged to move.

## The ground

- The compose `1c599da60` (branch compose-v134 in /tmp/opencode/tf130-rt):
  pristine v1.3.4 + the store, the round-trip PROVEN byte-exact
  (zero diffs). Ten members regenerated under the state-machine
  discipline (the before-state anchors at the tree the earlier members
  left); 011's body retired EMPTY (its content rode 010 — v1.3.4's
  tool-parse module split collapsed the shared file set).
- The fork ground held: the fp8-pages marriage stays (upstream STILL
  refuses fp8-on-pages — `cuda_native.zig:571` tests exactly that
  refusal; ours' Table.logical, pageCacheBytes(kv8) and the paged
  kernels are load-bearing on the adopted serving mode). The exl3p NBA
  ground stays primary at 4 bits. The fused-select group stays.
- Upstream's folds in: #4493/#4619's pair_experts (fingerprint layout
  23 carries it beside numerics/draft_split), #3659's TF_GLM_MOE_DIRECT
  (the topk kernel's sh pointer serves both the group and the direct
  path), #4499's prefill skips, #4427's cached-page budget, the mla/
  Shape refactor beside ours' kv8 sizing, the tool-parse module split
  beside ours' callName ABI, mtpMode beside ours' drafter guard.
- The head's `local.sh` pin moved to `12ebd414` BEFORE the launch (the
  two-gate rule the round-158 window paid for).

## The gates (all must hold)

1. The same-bits greedy witness `80cc3802…` IDENTICAL (the ninth→tenth
   bump must not move the deterministic probes).
2. §2 content gates g1–g4 ALL PASS.
3. hardmode **94 on tool-eval-bench 3.1.0** holds (the re-based boundary).
4. The vision suite 4/4 (the repo's own assets).
5. The load walls in band (83 s ± the boot wobble; #4427's budget
   change may move the walls a little — in-band is the judgment).
6. Strict-TF_ refusal lines at boot: 0 (the video-library note excluded).

## The value bracket (secondary, order-matched)

The steady-state decode probe ×2 across the battery's serve (the
default(1) / default(2) bracket): in-band both sides → no decode row
move (the row stands at the round-157 PDL mean 77.3).

## The kill criteria

- ANY gate FAIL → the pin holds at v1.3.3; the defect question opens
  with the receipt.
- The witness moved → VOID regardless of the scores; the rebase ground
  is wrong until understood.

## The prior instrument

The v133val battery's shape exactly (campaign-20261122-000800): the
same standing restart, the same §2 gates, the same hardmode invocation,
the same vision suite, the same bracket design — the ground moved one
release, nothing else. The v132val battery named the stage-brief
discipline this brief follows.

## The follow-up this battery does NOT carry

The pairexval window (#4493/#4619's `TF_GLM_PAIR_EXPERTS=1` A/B): the
release's own claimed +15%/+5% on two GB10s at TP=2 prefill. Staged
AFTER this battery qualifies the base — the value gate names the
user-visible number (the prefill row), the arms are the default vs the
knob, order-matched, the same v134val gates as the safety net.
