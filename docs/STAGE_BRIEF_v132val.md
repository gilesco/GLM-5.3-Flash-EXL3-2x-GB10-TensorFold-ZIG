# Stage brief — v132val
# (the v1.3.2 bump: the PDL/item-plan/form-race release — a hand rebase)

## The question

Does TensorFold **v1.3.2** (`b472b9f8`, released 2026-11-20 19:27 UTC,
452 commits past v1.3.1) + the 17-patch store (re-anchored where the
PDL rewrite collides) serve **bit-identically and gate-clean** — and
do the release's THREE decode levers for our shape move the honest
instrument beyond the ±5% order-matched band?

## The value-if-yes

- The user-visible decode anchor moves: the steady-state probe
  (75.9 tok/s on v1.3.1) beyond the ±5% order-matched band with the
  bracket agreeing — three default-on decode levers ride this bump
  (#3776's PDL launch gaps, #2044's EXL3 item plan, #3249's
  per-width form race).
- The line stays current on the newest tag; the rebase absorbs the
  PDL machinery natively and retires the fork-port overlap.

## The desk ground (this sitting, no window spent to learn it)

1. **The release's GLM CUDA speed list carries three direct items**:
   - **#3776 PDL**: "GLM's kernels and qmmf's decode linears launch
     as programmatic dependent launches, so a decode token's kernels
     lose most of their launch gaps; TF_GLM_PDL=0 launches
     everything plain" — the fork's PDL-commit's upstream landing,
     measured as "2-3 us idle between each of ~1,320 kernels".
   - **#2044 EXL3 item plan**: "a decode window's EXL3 routed
     experts launch on the 16-pair item plan instead of the group
     kernel's grid of mostly idle blocks, with the same output
     bytes".
   - **#3249 form race**: the load races classic vs factored expert
     forms at each of TEN decode window widths and keeps the faster
     per width (classic unless factored is >1% faster);
     `TF_GLM_EXPERT_FORM` names one for every width.
2. **#3776 SUPERSEDES our 016-zstep's MECHANISM WIDTH, not its
   kernels** (updated this sitting): upstream's native PDL covers
   EVERY GLM kernel (the fork's covered the four EXL3 decode
   kernels only); the knob broadens from TF_EXL3_PDL to TF_GLM_PDL.
   But pristine v1.3.2 does NOT carry the fork's read-once
   k8r8s/k8r16s kernels (015-zshfl's contribution, measured flat,
   adopted bit-safe, the fork's 0083+ builds on them) — the store
   KEEPS 015/016's fields in the compose and the fork chain stays
   knob-flippable (TF_EXL3_PDL=0). The drop-016 question closes
   AFTER the battery, with the honest reading in hand: the value
   bracket measures the native PDL against the combined baseline
   (the fork chain + the native wrapper both live in the compose).
3. **The store composes 5/10 carriers clean; FIVE drift**: 001
   (cuda_glue.zig:194), 003 (cuda_kv8_test.zig:136), 004
   (cuda_mm.zig:59), 009 (cuda_moe.zig:54), 012 (glm_glue_moe.cuh:1)
   — all in the PDL launch-rewrite's file set. The re-anchor is the
   compose-and-diff discipline (the round-143 rule: the tool
   reproduces the state chain; no hand-edited hunks).
4. **#3705's sampler-rule dedup** and **#3852's KV page-retirement
   fix** ride too — the latter touches the KV pool state our 003
   marriage owns; the re-anchor reads it before the compose.
5. **The `--tp` widening (#2917)** reaches our serve only via
   defaults (we pass no --tp; the engine's TP=2 path is unchanged
   for our two-rank shape).

## The arms

- **The qualification arm**: the v1.3.2 engine + the re-anchored
  store (the fingerprint moves with TF_COMMIT + the patch bodies —
  the window re-prepares).
- **The PDL value bracket** (order-matched, inside the same
  window): default(1) → `TF_GLM_PDL=0` → default(2), each arm the
  steady-state probe + the bench. The OFF arm isolates the PDL
  launch-gap contribution from the item-plan and form-race
  contributions (which stay on in all three arms). The OFF deltas
  judge against the bracketing defaults' mean inside the ±5% band
  (the round-149 drift map).

## The gates (all must hold on the qualification arm)

- The greedy same-bits witness `80cc3802…` IDENTICAL (the eighth
  consecutive bump on PASS).
- The §2 content gates ALL PASS.
- Hardmode: **94** (the 3.1.0 instrument's named equivalent, the
  round-154 boundary re-base) — the first battery ON the new frame
  must HOLD it, not set it.
- The vision suite 4/4.
- The walls inside the band (80 s ±10%).
- The pool line at the videorows arithmetic; the boot-state wobble
  priced separately.
- The PDL engagement witness: the boot/boot-adjacent log names the
  dependent-launch state (read from the v1.3.2 source this sitting);
  the strict-TF_ refusal count at zero (the video-library note
  excluded).

## The kill criterion

ANY gate FAIL holds the pin at v1.3.1 until understood. The rebase
does not land on a missed gate; the promotion sync follows a
QUALIFIED verdict only.

## The closest prior instrument

The v131val battery (campaign-20261120-140338) — the lean gate ran
one release ago. Diffs against it: (1) the PDL value bracket rides
inside (the release's headline claim is ours to verify — the
fork's own PDL chain never transferred on our shape at 016qual; the
native, wider version is a different mechanism width and must be
measured, not assumed from either record); (2) the hardmode gate
runs ON the re-based 3.1.0 frame (94); (3) the rebase itself is a
hand rebase (five carriers), not the zero-conflict compose of the
last two releases — the scratch round-trip verify gates the stage
BEFORE the window.

## The constants the instrument assumes

- The greedy witness sha `80cc3802…` — measured, the standing
  witness across seven engine bumps.
- The ±5% same-window drift band — the round-149 drift map,
  order-matched only.
- The walls band center 80 s ±10% — the standing anchor row.
- The bench version boundary (round 153 cont.) — the 3.1.0 frame
  re-based at 94 by the v131val receipt.
- The pool-pages slope ~305-314/GiB — the round-149 digest.

## The retirement

On QUALIFIED: the pin moves to b472b9f8 in the head's local.sh, the
promotion sync mirrors the pin + the re-anchored store to production
behind the round-146 identity guard, the production restart verifies
the /health version, the anchors re-date on the battery's receipts,
the release watch's PIN_TAG moves to v1.3.2. The PDL value verdict
lands with the battery: beyond-band-and-agreeing = the launch-gap
claim transfers (the decode row re-dates); in-band = the claim does
not transfer at our shape (the fork's narrower version never
transferred either — the fourth measured-not-transferred class would
be noted). Either way the PDL question closes this window.
