# Stage brief — knobcsval
# (the CS remeasure: TF_GLM_CHUNK_SOLO=4096 on the v1.2.10 + 17-patch base)

## The question

Does `TF_GLM_CHUNK_SOLO=4096` (CS) deliver a user-visible decode and/or
prefill gain on the CURRENT base — TensorFold v1.2.10 + the 17-patch
store, the paged fp8 pool, TR3-4bpw, PARALLEL=4 at 524,288 — at every
quality gate, with the round-132 trade re-priced on today's memory map?

CS batches two prompt chunks a pass while no stream decodes (the
engine's own line: "prompt buffers for two chunks a pass, while no
stream decodes, or 2048"). Round 132 measured it on the v1.2.1
window-mode ground: tg d0 +5.1%, d4096 +8.7%, d8192 flat — and HELD it
(user) because the gains landed on fronts already crossed, c4 (the one
behind front) did not move, and the trade was +1.87 GiB model with the
prompt cache halved 3.3→1.9 GiB (resume-capacity risk at depth).

## Why now — the hold's grounds have moved

- **c4 CROSSED since**: the c4 anchor now reads 198.0 vs production's
  194.5 (101.8%, the highest ever recorded) — the "c4 didn't move" ground
  no longer prices a c4 gain at zero; but the front is no longer behind,
  so the value-if-yes must name what CS can still move.
- **The memory map moved**: the round-132 trade was priced on the v1.2.1
  window-mode KV (the model read 86.62 GiB, the prompt cache a standing
  3.3 GiB). The serving mode is now the paged fp8 pool + share-store;
  the trade must be re-read off the v1.2.10 serve lines before the
  adopt/reject call means what it says.
- **The decode front re-dated**: the steady-state probe (2048 tokens)
  reads 73.1 tok/s on v1.2.10; the round-132 CS gains were bench-row
  numbers on the prefill-polluted tg cells. The honest instrument now
  exists and is cheap.

## The value-if-yes

One of:
- The steady-state solo decode t/s moves beyond the ±5% order-matched
  band (user-visible: the anchor row's number).
- The bench tg d0/d4096 cells move beyond the band order-matched, AND
  the steady-state probe agrees in sign.
- The bench pp d0 (the prefill anchor, 1,524) moves beyond the band —
  CS touches the prompt path by construction.
The user-visible number: whichever anchor moves, in docs/perf-anchors.tsv.

## The cost

One window, ~60-70 min: three restarts (~84 s wall each) + two bench
passes + one hardmode battery (~25 min) + the vision suite + the gates'
internal restarts. No prepare: CS is env-only (the `TF_GLM_` prefix is
forwarded by env_args(); the fingerprint does not move; the image is
shared).

## The arms (order-matched, one window)

- **OFF arm twice, bracketing the ON arm**: OFF(1) → ON → OFF(2). The
  ON deltas judge against the bracketing OFFs' mean; the ±5% band is
  the round-149 drift-map rule (order-matched same-window only).
- ON = the standing config + `TF_GLM_CHUNK_SOLO=4096` (one env pair).
- The OFF arm doubles as the standing-config witness: its greedy probe
  must read the `80cc3802…` witness IDENTICAL.

## The gates (all must hold on the ON arm)

- The greedy same-bits witness `80cc3802…` IDENTICAL on BOTH arms (CS
  must not move the deterministic probes).
- The §2 content gates ALL PASS (run_gates on the ON arm — the gates'
  internal restarts carry the ON env through).
- Hardmode **95** (the thirty-ninth consecutive on PASS).
- The vision suite 4/4.
- The ON arm's wall inside the band (80 s ±10%).
- The serve lines captured verbatim per arm: the model/pool numbers
  re-price the round-132 trade (the memory side of the verdict).

## The kill criterion

- ANY gate FAIL → no adoption; the hold stands; the knob stays
  available as an env only.
- No cell moves beyond the ±5% order-matched band (with the
  steady-state probe agreeing in sign on any tg claim) → the round-132
  hold RE-AFFIRMED on the current base, the receipt records it; the
  question closes for this base.

## The closest prior instrument

The knobsv121 phase (round 132, results/knobsv121/) — the CS A/B
itself. Diffs against it: (1) that window ran on v1.2.1's window-mode
KV with the standing 18-patch stack; this one runs on v1.2.10's paged
fp8 pool with the 17-patch store — the trade re-prices there; (2) that
window's decode readings were bench-row cells; this one adds the
steady-state 2048-token probe (the honest decode instrument per the
gotchas) fixed at max_tokens 2048 ≥1024 (thinking eats small
max_tokens); (3) the order-matched OFF-ON-OFF bracket design replaces
the single-pass arms (the round-149 drift map's requirement).

## The constants the instrument assumes

- The greedy witness sha `80cc3802…` — measured, the standing witness
  across five engine bumps.
- The ±5% same-window drift band — the round-149 drift map
  (campaign-20261111-170638), order-matched only.
- The walls band center 80 s ±10% — the standing anchor row.
- The pool-pages-per-GiB slope ~305-314/GiB — the round-149 digest;
  used only to read the pool line's room, not as a gate.
- CS's admission arithmetic: 4096-row prompt buffers while no stream
  decodes — the serve line's model/pool delta IS the engagement
  witness (the round-132 receipt: model +1.87 GiB, cache halved).

## The retirement

On QUALIFIED: the digest moves the verdict to the user (the adopt call
is the user's by the round-132 precedent — CS is an env, not a patch);
on RE-AFFIRMED: the question closes for this base and the receipt
cites both windows (the knobsv121 original + this one). Either way the
config default is untouched unless the user adopts; the phase retires
with its receipt per convention.
