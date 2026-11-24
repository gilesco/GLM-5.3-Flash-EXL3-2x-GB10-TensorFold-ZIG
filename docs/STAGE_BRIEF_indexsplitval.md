# STAGE BRIEF — indexsplitval (the TF_GLM_INDEX_SPLIT=32768 A/B)

## The question

Does `TF_GLM_INDEX_SPLIT=32768` move the prefill row at our serving
profile? The knob ships in our pinned v1.3.4 (#4510, the changelog's own
entry) and sits at default 2048: from position `from` onward, rank 0
splits a prompt chunk's indexer rows across the ranks — the picks
all-gathered. At 32768, every prompt chunk that starts below 32k stays
fully local per rank with NO blocking all-gathers (the engine's own
test: "every paired step of an 8K or 32K prompt stays local"). Upstream
records 1-2% prefill at 128k; OUR profile is short agent prompts under a
524k ceiling — nearly every real prompt sits entirely inside the local
band, so the skip should engage on every chunk.

## The value-if-yes

- The prefill row moves on the in-band depths: the anchors' prefill row
  is 1,524 tok/s; the d4096/d8192 cells (chunk starts at 2048+, where
  the default's split engages and the ON arm's does not) are the value
  cells. Even 1-2% is a standing-row move on a knob that costs nothing.
- Zero bump risk: the knob is in the pin, bit-safe by upstream's own
  receipt, and a config default flip — no patch, no rebase.

## The arm-distinguishing expectation (named up front)

The d0 cell (pp2048: one chunk starting at 0) sits BELOW the default's
2048 split too — both arms keep it local. **d0 is expected FLAT inside
the band; d4096/d8192 are the value cells.** A flat d0 does not void the
window; a flat d4096+d8192 does.

## The arms (order-matched)

default(1) → `TF_GLM_INDEX_SPLIT=32768` → default(2), each arm the bench
grid (pp2048 tg128 @ d0/d4096/d8192, c1/c2/c4) and the greedy witness.
The pp cells judge against the bracketing defaults' mean inside the ±5%
order-matched band (the round-149 drift map).

## The safety net

- The greedy content sha `80cc3802…` IDENTICAL on all three arms — the
  knob is bit-safe by construction (outputs unchanged is upstream's own
  claim AND the engine's own test structure); a moved witness on ANY arm
  kills the adoption.
- The §2 exactness gates + hardmode + the vision suite on the ON arm
  ride the summary battery as usual.

## The kill criteria

- The witness moves on ANY arm → the knob is NOT bit-safe at our shape;
  the default stays 2048; the defect question opens with the receipt.
- The d4096/d8192 cells in-band (|Δ| ≤ 5%) → the all-gather skip does
  not pay at our shape; the question CLOSES; the default stays 2048.
- The cells beyond the band with the bracket agreeing → the value
  transfers; the config default flips to 32768 through its own battery
  (this window's receipt is the evidence).

## The prior instrument

The pairexval window's shape (campaign-20261123-075710 — the three-arm
order-matched bracket with a per-arm discriminator and a named
in-band/beyond-band verdict). The difference: pairexval's value cells
were the pp cells generally; this brief NAMES which cells can move
(d4096/d8192) and which cannot (d0) before the window runs.

## The desk check before the launch

- The knob reaches the binary: `TF_GLM_*` passes env_args' forwarding
  (the pairexval desk check verified the prefix list); the ON arm's
  restart line carries `TF_GLM_INDEX_SPLIT=32768`.
- The fingerprint carries `split` (cuda_ranks.zig's Fingerprint.split) —
  every rank agrees by construction on one env.
- The engine's own tests cover the splitAt semantics at 32768
  (cuda_sparse.zig's test block) — the arm-distinguishing input reaches
  the code path the tests exercise.
- The continuation scanner + the stub-execution test run on the staged
  phase BEFORE the launch (the w639589 discipline).

## The launch

`scripts/autonomous-launch.sh "preflight indexsplitval summary"` — last
action of the sitting.
