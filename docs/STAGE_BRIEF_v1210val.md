# Stage brief: v129val → v1.2.10 rebase (round 148)

## The question
Does the v1.2.10 engine + the re-anchored 18-patch stack serve our line at
parity with the v1.2.9 promotion — the same-bits greedy witness IDENTICAL
(`80cc3802…`), §2 ALL PASS, hardmode 95, the vision 4/4, the walls in band —
with the videorows default and the adopted pool plan unchanged?

## The value-if-yes
The pin stays current with upstream's release train (the release watch goes
quiet; the next candidate rides on the newest base), plus v1.2.10's GLM items
that serve us: `TF_GLM_EXPERT_FORM` (#3151 — deterministic loads, the
form-race skipped), the message-starts groundwork (#3679), the
reasoning-recovered gate (#3699 — a stuck-think reply answers its text
instead of an empty one), the grammar-size guards (#3038), background
Responses (#3220). And the 005/006 pagerows/selist ground rides cleaner.

## What v1.2.10 changes on OUR ground (read from the diff before staging)
- **The GLM CUDA kernel files are UNTOUCHED** (zig/kernels/cuda/: nemo_audio,
  nvfp4_experts32, prompt16/qwen35 — none of our 12 EXL3/MoE/kernel patches'
  files moved). The re-anchoring risk is the LOWEST of any bump since v1.2.5.
- **The GLM zig diffs are small and non-kernel**: cuda_lane_costs/cuda_share/
  cuda_experts (the expert-form knob + the FP8-Metal-adjacent rework),
  cuda_engine/cuda_forward/cuda_native 4–6-line diffs (the block32 rework +
  a TF_KV_SHARE advice-line wording change).
- **The server-layer overlap is real but bounded**: tool_parse.zig grew the
  quoted-markup scanner (#3588) AROUND our 010's callName — callName still
  returns null when unoffered (verified in the v1.2.10 source), so 010 stays
  needed and its hunks re-anchor around the new Scanner; kv_pool/openai/
  prompt_radix carry wording/tests drift.
- **Nothing mainlined any of our unmainlined residue** (same as v1.2.9→main
  mid-window). The stack stays all 18.
- **#3125's kept-states placement is already in our serve** (in v1.2.9) —
  nothing new there; the pool plan's wording gains "reserved at load".

## The arms
- No A/B: this is a re-anchor + re-qualification battery on the NEW engine —
  the v129val shape (the same-bits greedy witness against the standing
  `80cc3802…`, the §2 gates, hardmode, the vision suite, the walls), NOT a
  duel. The OFF/ON frame doesn't apply; the "arm" is the re-anchored stack.
- The one knob decision: `TF_GLM_EXPERT_FORM` stays UNSET (the engine keeps
  its form race) for the battery — the qualified behavior is the race, and
  the knob is adopted (if wanted) by its own measured window later.

## The gates (all must hold)
1. The round-trip: pristine v1.2.10 + the 18 patches = the rebase tree
   (byte-identical rebuild from the store).
2. The greedy content sha IDENTICAL (`80cc3802…`) — the bump moved nothing
   deterministic on our line.
3. The §2 content gates ALL PASS.
4. hardmode **95** — the thirty-seventh consecutive.
5. The vision suite **4/4**.
6. The walls in the standing band (83 s ±); the pool-pages line at the
   adopted videorows arithmetic (~4,352 pages, 288 MiB fixed each).

## The kill criterion
Any gate fail → the pin HOLDS at v1.2.9 (6b9de6951) and production is
restored from the v1.2.9 store; the receipt carries the failing instrument
and the defect question reopens. The round-142 lesson applies: the crash-net
and the flag discipline are verified before the launch; production always
comes back.

## The promotion rule
ALL HELD → the pin moves to 2a674b552 (v1.2.10) in scripts/local.sh, the
promotion sync mirrors the store + config to the production repo, and
production restarts through the promotion path (the detached round-146/147
pattern with the done-marker). ANY FAIL → the v1.2.9 promotion stands and
the v1.2.10 tree is quarantined for diagnosis.

## The window shape
One window: `preflight v1210val summary`. Production stopped once by the
window flow, restored on every exit path. The v1210val phase is the v129val
battery's shape re-dated (the same gates, the same witness sha, the new
engine pin).
