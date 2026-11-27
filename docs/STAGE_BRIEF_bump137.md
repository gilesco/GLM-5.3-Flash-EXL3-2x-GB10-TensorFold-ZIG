# STAGE BRIEF — the v1.3.7 bump (the thirteenth; the round-141 protocol)

## The release

TensorFold **v1.3.7** (`b33665493`, released 2026-11-27 22:51Z), 355
commits past v1.3.6. The poke's expected headlines — #2843's EXL3
grouped-experts decode-grid fix, #2856's batched shared MTP, #3064's
paged FP8 KV — are **NOT in the tag**: they remain on main (13 commits
past). The release carries, for our line:

- **The PDL launch guard (#5381/e9eb6c8d0)** — a host guard rejecting
  every enumerated programmatic dependent launch whose kernel lacks
  its dependency wait. Directly the bug CLASS our rounds 163-164
  chased (the illegal-address crash class). The GLM-side runtime
  change is one file (x3ld.cu, qwen-family); the guard machinery is
  build-side (`glm_pdl_scan.zig`) — our composed PDL twins gain the
  scan coverage free.
- **The #5256 GLM load read-ahead fix** (`4e846e07b`) — layer
  read-ahead uses the checkpoint's model prefix, fixing full GLM/DSA
  load reads. Our line is Flash; the refs #5256 issue was our
  round-163 desk-scan's neighbor. Low risk, on our load path.
- **The TFQ3 records consolidation (#5281/c2b4f0ba3)** + the GLM
  prompt TFQ3 sign fix (#5225/ad5b75508) — shared records module; the
  Metal sign fix is not our route but the records move touches
  `c2b4f0ba3`'s shared module our TFQ3 consumers read.
- **The EXL3 grouped-kernel changes (c1924a801, 06e3c7f5b, 91468128c,
  bc80cf280)** — 32-member tiles + the softcapped SwiGLU epilogue +
  the wide-kernel definition order + the capped-epilogue rounding,
  driven by Inkling 2's adoption of the core grouped kernel. The
  release notes state the EXISTING instantiations compile to the
  SAME SASS on every SM. These are the compose-risk hunks: they land
  in `exl3_grouped.cuh`/`exl3_experts.cu`/`exl3_experts.zig` — the
  files our 002/003/012 members' bodies live in.
- **The router-tiles 32-bit-word reading (#5360/6302ab129)** — PTX
  form stability across nvcc versions; images and outputs unchanged.
- **`TF_CUDA_SCHED` (#5165)** — a new opt-in host-wait schedule
  (`blocking` frees the core the driver spins on a GB10, ~2% decode
  cost on Inkling; unmeasured on GLM). A candidate knob, default off.
- **The prompt-cache pressure reporting (#5312)** — request logs and
  `/memory` name `prompt_cache_keeping_new_states`; observability on
  our KV-share surface, no behavior change.
- **The release-read verdict**: "GLM-5.3-Flash NVFP4 at TP=2 on two
  GB10s stays within 0.7% at one and two streams" — the release was
  read on our exact hardware shape.

## The value-if-yes

The thirteenth bump lands with: the PDL guard class (our crash-class
defense now upstream-enforced), the #5256 load-read fix, and the
release currency (the release cadence is one a day; every day held
costs the next rebase its drift). The decode/perf expectation is
FLAT (the release's own GB10 read: within 0.7%) — the value is the
guard class + the load fix + staying current, not a speed number.

## The compose risk surface

002 (+54/-10 upstream on its files), 003 (+59/-9), 012 (+98/-52).
The 32-member tile change reworks `warp_tiles`/`grouped_body` in
`exl3_grouped.cuh` — the file our 012's fork twins instantiate from.
The fork-primary rule applies: our measured machinery stays; the
32-member template param folds in beside it (`MT = 1` default keeps
the existing instantiations' SASS, per the release's own claim).

## The protocol (the round-141 v1.2.7 shape)

1. The compose: merge `v1.3.7^{commit}` INTO `compose-v136` (the
   composed tree is the ground; never reset the compose branch).
2. The regen: the members whose files moved (002/003/012) re-cut
   git-native from the composed tree's history; the byte-exact
   round-trip (`pristine v1.3.7 + the store = the composed tree`)
   before any window.
3. The compile gate: the build must pass BEFORE the battery window.
4. The battery: the v137val block (the v136val shape, re-headered:
   the witness `80cc3802` must stay IDENTICAL across the thirteenth
   bump — the fingerprint carries the release's own SASS-stability
   claim; the §2 gates; hardmode; the vision suite; the walls; the
   steady-state bracket).
5. The launch last: `scripts/autonomous-launch.sh "v137val rung"`.

## The kill criteria

- The witness moves on the fixed compose → the pin holds at v1.3.6
  and the receipt names what moved (the SASS-stability claim is
  upstream's — our greedy witness is the check).
- A compose conflict the fork-primary rule cannot resolve → the
  pin holds; the conflict surface lands in the ledger for the
  next release cycle.
- The battery's any-gate-FAIL holds the pin (the round-163
  discipline: a promotion is never blind).
