# Stage brief — v131val
# (the v1.3.1 bump: the lean gate — the release carries nothing for our line)

## The question

Does TensorFold **v1.3.1** (`5e1e1912`, released 2026-11-20 13:39 UTC,
11 commits past v1.3.0) + the 17-patch store serve **gate-clean** —
so the pin moves — when the release itself claims zero content for
our line ("1.3.0 plus native Hy4-flash on Metal. Nothing else
changes: every other model, flag and default is as in 1.3.0")?

## The value-if-yes

The line stays current on the newest tag (the release watch's reason
to exist): every future rebase rides the newer ground and the pin's
comment carries the current release. No perf claim rides this bump —
the value is currency, not speed.

## The desk ground (this sitting, no window spent to learn it)

1. **The release body's own scope claim**: Hy4-flash on Metal is the
   ONLY item; "every other model, flag and default is as in 1.3.0".
2. **The tree verifies the claim**: `git diff v1.3.0 v1.3.1` is 138
   files/19,244 insertions — ALL Hy4-flash (a new family) + its
   contract tests + fixtures. `git diff v1.3.0 v1.3.1 --
   zig/src/families/glm/ zig/kernels/cuda/` touches ONLY
   `zig/kernels/cuda/hy4_flash/*` new files — ZERO hunks on any
   existing GLM file. No knob, no default, no serving-path change.
3. **The store composes zero-conflict on pristine v1.3.1** (the
   scratch worktree verify, this sitting): the 10 verbatim carriers
   apply; the 7 empty-body regens apply as no-ops; 43 files modified
   — the identical result to the v1.3.0 compose. The replay property
   holds trivially, as at v1.3.0.
4. **The gap is 14 hours** (v1.3.0 23:04 UTC Nov 19 → v1.3.1 13:39
   UTC Nov 20): a same-day patch release; the risk profile is the
   tag-relabeled engine, not new behavior.

## The arms

- **The qualification arm only**: the v1.3.1 engine + the 17-patch
  store, the standing defaults (the fingerprint moves with TF_COMMIT
  — the window re-prepares). No A/B: the comparison is the v130val
  receipt itself (campaign-20261120-002016) — the same-bits witness,
  the §2 gates, hardmode, the vision 4/4, the walls band. The release
  moves nothing on our path; the battery proves the tag moved
  nothing live.

## The gates (all must hold on the qualification arm)

- The greedy same-bits witness `80cc3802…` IDENTICAL (the seventh
  consecutive bump on PASS).
- The §2 content gates ALL PASS.
- Hardmode: **95 or the new instrument's named equivalent once
  measured** (THE BENCH VERSION BOUNDARY, round 153 cont.: this is
  the first battery on tool-eval-bench **3.1.0** — the user upgraded
  the bench this morning; a slightly different score is the
  INSTRUMENT, not the line. The receipt records its
  `tool_eval_bench_version` field and the 3.1.0 number RE-BASES the
  streak's descriptive frame if it moves from 95).
- The vision suite 4/4.
- The walls inside the band (80 s ±10%).
- The pool line at the videorows arithmetic; the boot-state wobble
  priced separately per round 149.

## The kill criterion

ANY gate FAIL holds the pin at v1.3.0 until understood — the bump
does not land on a single missed gate. The pin at v1.3.0 stays
production's served engine the whole time; production is not touched
until the battery qualifies and the promotion sync follows.

## The closest prior instrument

The v130val battery (campaign-20261120-002016, yesterday) — the bump
gate shape, run one release ago. Diffs against it: (1) NO value
screen rides inside this window — the release carries no perf claim
for our line (v1.3.0's L2PF screen closed flat; nothing new to
screen); (2) the hardmode gate carries the bench-version-boundary
rule (the first 3.1.0 battery); (3) the pool line's expectation
re-reads from the v130val receipt (3,530 pages at 16.2 GiB, the
boot-state wobble priced).

## The constants the instrument assumes

- The greedy witness sha `80cc3802…` — measured, the standing witness
  across six engine bumps.
- The walls band center 80 s ±10% — the standing anchor row.
- The pool-pages slope ~305-314/GiB — the round-149 digest.
- The bench version field — recorded per battery by the JSON; the
  boundary note (round 153 cont.) governs the score's reading.

## The retirement

On QUALIFIED: the pin moves to 5e1e1912 in the head's local.sh, the
promotion sync mirrors the pin + the store to production behind the
round-146 identity guard, the production restart verifies the /health
version field, the anchors re-date only if a measured row moved (no
perf claim rides this bump), the release watch's PIN_TAG moves to
v1.3.1. On any FAIL: the pin holds at v1.3.0 and the defect question
opens with the receipt.
