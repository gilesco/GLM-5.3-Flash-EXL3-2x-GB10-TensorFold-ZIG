# Stage brief: videorows — the `--vision-video-tokens 64` arm (round 147)

## The question
Does capping the engine's video-token reservation (`--vision-video-tokens 64`,
the CLI's own minimum) free the reserved rows into the fp8 paged KV pool —
more pool pages / more admitted room at the 524,288-token window — without
moving any output byte?

## The value-if-yes (the user-visible number it could move)
More funded KV pages on the same hardware: the pool-pages line in the serve
line moves up from **4,223 pages (14.02 GiB)** toward the freed arithmetic —
and the same freed room is the room a 5th stream or a larger kept-states set
would need later. The number a user feels: more concurrent 512K windows on
the same two boxes.

## The measured constant (desk-calibrated BEFORE the window — the w52-60 rule)
From our v1.2.9 source (verified this sitting against the pinned tree
6b9de6951 and against production's own boot line):
- `cli.zig:266`: `vision_video_tokens` defaults **16384**; the CLI accepts
  **64..262144** (so 64 is the floor).
- `cuda_images.zig:82-83`: `rowLimit = image_tokens + video_tokens` when the
  checkpoint carries video ids (ours does).
- `cuda_native.zig:373`: `extra = ... v.streamBytes()` = rowLimit ×
  out_hidden (4096) × 2 bytes → the pool plan.
- **Arithmetic: (16384−64) × 4096 × 2 B = 127.5 MiB/stream; × 3 extra
  streams + the engine's own share of the plan = the observed delta.**
- **The witness pre-read (production's live line, v1.2.9, defaults)**:
  "4 streams at once ... **4,223 pages** of 512 rows (**14.02 GiB**) ...
  **415 MiB fixed each**". The predicted ON-arm line: pages ≈ 4,223 + ⌊(4 ×
  127.5 MiB) / pageBytes⌋ where pageBytes ≈ 14.02 GiB / 4,223 ≈ 3.40 MiB →
  **~4,373 pages (≈ 14.86 GiB), fixed each ≈ 415 − 127.5 ≈ 288 MiB**. The
  arm's serve line is checked against THIS arithmetic before any probe runs;
  a serve line that does not show the predicted pages means the flag did not
  engage (the aligned-probe-oracle rule: the probe's precondition measured
  by the engine's own observable).

## The arms
- **OFF arm** (the control): the standing serve, no new flag — this is
  production's own identity; its pool-pages number is already receipted
  (4,223 / 14.02 GiB / 415 MiB fixed each). Re-measured in-window anyway
  (A/A against the standing receipt; the round-141 w52 A/A class guard).
- **ON arm**: identical config + `--vision-video-tokens 64`.
- **Arm distinctness**: the two arms' serve lines MUST differ in the
  `pages of 512 rows (...)` and `fixed each` figures and MUST be identical
  in every other field (model, GiB model size, the window, the streams
  count). The phase asserts this explicitly and refuses a void otherwise.

## The gates (what must hold in the ON arm)
1. The serve line's arithmetic matches the desk calibration (~+150 pages,
   fixed-each ~288 MiB) — the instrument's precondition.
2. **The greedy content sha IDENTICAL** (`80cc3802…`) — the room change is
   bookkeeping; if the words move, the arm dies.
3. The §2 content gates ALL PASS (run_gates on the ON arm's config).
4. hardmode **95** and the vision suite **4/4** — the vision gate matters
   double here: the image path must be untouched by the video-token cut.
5. The load walls inside the standing band (83 s ±).

## The kill criterion
Any §2 gate fail, any hardmode < 95, any vision suite < 4/4, or the greedy
sha DIFFERENT → the arm voids, the config default does not move, the receipt
records the kill. A serve line that fails the desk-arithmetic check voids the
window before any probe (a mis-anchored instrument, not a result).

## The adoption rule
Adopt into config.sh's serve_args only if: the arithmetic held, every gate
held, and the pool-pages gain is ≥ the predicted ~150 pages (the value gate:
a number a user feels, not compliance). Then the default flips with its
receipt cited in the config comment, and production takes it on its next
restart through the promotion path.

## The window shape
One window: `preflight videorows summary`. Production stopped once by the
window flow, restored on every exit path (the standing autonomous-window.sh
contract). No subagents in flight at launch.
