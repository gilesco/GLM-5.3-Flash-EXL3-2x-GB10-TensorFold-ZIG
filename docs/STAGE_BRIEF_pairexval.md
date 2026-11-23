# STAGE BRIEF — pairexval (the #4493/#4619 paired-experts A/B)

## The question

Does #4493/#4619's `TF_GLM_PAIR_EXPERTS=1` move the prefill row at our
shape? The release's own claim: **+15% prompts at 2K, ~+5% at 8K/32K
on two GB10s** at TP=2 prefill — our exact shape (two GB10s, TP=2, the
4-stream serve). The mechanism: one grouped routed-expert pass per
prompt pair with 128-row items (experts with many tokens read their
weights once), each rank passing its own FFN partial under the default
split reduction, so tokens match the unpaired path.

## The value-if-yes

- The prefill row moves: the anchors' prefill is 1,524 tok/s; a +5-15%
  pp move would be the largest prefill gain since 002's port (+24.5%
  at d0).
- The claim names the knob opt-in and off by default — an adoption
  would need its own default-change battery; THIS window only reads
  whether the value transfers.

## The arms (order-matched)

default(1) → `TF_GLM_PAIR_EXPERTS=1` → default(2), each arm the bench
grid (pp2048 tg128 @ d0/d4096/d8192, c1/c2/c4). The pp cells judge
against the bracketing defaults' mean inside the ±5% order-matched
band (the round-149 drift map). The claim's primary cell: pp @ d0.

## The safety net (every gate must hold on BOTH arms)

- The greedy content sha `80cc3802…` IDENTICAL on all three arms — the
  release says outputs are unchanged; the same-bits witness is THE
  proof at our checkpoint (the promoted checkpoint, not upstream's
  test recipe).
- The vision suite 4/4 on the ON arm.

## The kill criteria

- The witness moves on ANY arm → the knob is NOT bit-safe at our
  shape; the claim dies here; the pin holds at v1.3.4 and the knob
  stays off.
- The pp cells in-band → the claim does not transfer at our shape;
  the question CLOSES; the knob stays default-off.
- The pp cells beyond the band with the bracket agreeing → the claim
  TRANSFERS; the adoption question opens (its own battery decides the
  config default).
- ANY gate FAIL (a boot refusal, the vision suite) → the pin holds;
  the defect question opens with the receipt.

## The prior instrument

The knobcsval window's shape (campaign-20261119-223933 — the CS
TF_GLM_CHUNK_SOLO A/B): the same three-arm order-matched bracket, the
same bench grid per arm, the same witness gate. The v134val battery
(campaign-20261122-232612) is the closest prior VALIDATION instrument;
this window's arms differ only in the knob.

## The desk check before the launch

- The knob reaches the binary: `TF_GLM_PAIR_EXPERTS` is in the env
  forwarding list (verify the serve line's env on the ON arm — the
  arm-distinctness check).
- The arms' inputs are distinct (the ON arm's env carries the knob;
  the defaults' do not) — phase-lint's arm-distinctness class.
- The bench grid's cell set matches the anchors' row set (pp2048 tg128
  at the three depths) so the bracket reads against the standing rows.

## The launch

`scripts/autonomous-launch.sh "preflight pairexval summary"` — the
pairexval phase (session-specific; retires with the receipt), last
action of the sitting.
