# STAGE BRIEF — the v1.3.6 bisect (the re-evaluation the round-163 void
# demands; the short-query instrument, the user's direction)

## The question

Which store member(s) make the composed v1.3.6 stack serve degenerate
output — so the bump can re-stage on a fixed compose, or drop the
offending member, rather than re-anchoring blind.

## What is already proven

- **Arm A (campaign-20261127-091432)**: the PRISTINE v1.3.6 engine
  (no store) serves COHERENT on all four short-query probes. The
  defect rides OUR store's compose. The user's suspicion held; the
  upstream scan (203 issues, 50 open GLM CUDA) found ZERO matching
  reports — the defect is ours.
- The page-count delta (v1.3.5's 3201 vs v1.3.6's ~4100 pages) is
  v1.3.6's own baseline change, not the defect marker (the pristine
  arm shows it too, coherent).
- The page-layout desk-kills: the config constants, latentRow(),
  the Caches struct, and the shared-indexer shape all unchanged or
  equivalent at our config.

## The suspects, ranked

The four hand-merged members are the risk concentration — their
rejects were hand-merged against v1.3.6's reshuffled machinery:
1. **003-fp8-pages** — the page-layout merge beside v1.3.6's Shape
   refactor (the marriage is load-bearing on every request).
2. **002-exl3prompt** — the _m-kernel ABI reconciliation (the
   mixed-width kernels' externs grew the fork's ys/yrow args; a
   zig-caller/kernel mismatch reads garbage).
3. **001-absorb-mma** — the engine/forward merges beside the
   keep_seqs/layout-24 lines (the numerics/fingerprint surface).
4. **009-moeside** — the Side/Kernels merge beside the tfq3 field.

## The halves

- **Arm B (half136a)**: the store's first half 001-008. Coherent ->
  the defect rides 009-018; degenerate -> arm C halves within
  001-008 (001-004 vs 005-008, then singles).
- The bisect ends when a single member isolated: that member's
  v1.3.6 compose is re-examined against its fork ground and the
  v1.3.6 side, the fix composed, the round-trip + compile gate
  re-proven, THEN the full-store bump battery re-runs.

## The value-if-yes

The twelfth bump lands WITH the defect fixed — the line stays
current (the release cadence is one a day; every day held costs the
next release's rebase work) and the keep-seqs candidate arm unlocks.

## The kill criteria

- A degenerate arm whose half contains NO hand-merged member (all
  four live in 001-009) would falsify the suspect ranking — the
  bisect continues mechanically regardless.
- The window's serve never healthy -> the arm is VOID (no
  conclusion from a dead serve).

## The instruments

- The fast one: the four short-query coherence probes (the user's
  direction — minutes, not the hardmode hour).
- The final gate before any re-promotion: the FULL bumpval battery
  (the witness 80cc3802, the §2 gates, hardmode, the vision suite,
  the walls, the bracket) — the short-query instrument narrows the
  bisect; it never qualifies a bump.

## The arm C addendum (the knob bisect — staged after arm B's void)

Arm B's first launch died rc=127 (the HALFSTORE wrap gotcha, fixed
in a6ab14f) and its second died in prepare: `exl3_group.cuh` does not
exist in a 001-008 cut — 002's include line needs the file 012
creates, and 012's engine hunks need 009's field. The alphabetical
stack carries include dependencies THROUGH later members: no clean
prefix cut before 012 can build. The half-store bisect by file-cut
is void as a design; arm C replaces it.

**Arm C (knob136)**: the full composed stack, the fork's envOn knobs
turned off one at a time — `TF_GLM_MOE_FUSE=0`, `TF_GLM_SHARED_SIDE=0`,
`TF_GLM_EXL3P=0`, then all six classic-path knobs together. Each knob
is receipted bit-identical on the v1.3.5 ground, so a coherent arm
names its member's FUSED path as the defect carrier; all-degenerate
moves the hunt to the members' base content (the remaining
instrument there: the byte-level diff review of each member's
hand-merged hunks against its v1.3.5 proven body).

**The knob136 first-run void** (campaign-20261127-102038): all four
arms' probes silent — the probe body builder OVERWROTE its request
body's first line (`>` where plain136's proven shape appends `>>`),
the serve answered 400 Bad Request, `curl -f` rc=22 with no output
file, `|| true` swallowed it, the reader found nothing. The
dead-race gate class: a value leg that fails silently. Fixed (the
append restored) AND hardened (the curl's rc is now receipted; an
arm whose curl fails is VOIDed loudly, never a silent verdict).
