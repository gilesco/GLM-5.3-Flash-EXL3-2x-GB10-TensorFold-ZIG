---
name: TensorFold Patch Craft
description: Craft, verify, and measure a local TensorFold engine patch on this testing line — writing the zig diff, the apply/symbol checks that git apply cannot do for you, the alphabetical staging order, shipping it through a resumecost window via RC_PATCHES, and reading the receipt (the boot wall, the content gate). Trigger words: engine patch, RC_PATCHES, patches/, git apply failed, duplicate struct member, the build refused the patch, boot marks, decompose the loader.
---

# TensorFold Patch Craft

One paragraph: this line measures engine changes as patches in `patches/`, applied
at image build against the pinned TensorFold tree, shipped through a resumecost
window (`RC_PATCHES="a.patch,b.patch" scripts/autonomous-launch.sh "preflight
resumecost summary"`), and judged by the campaign receipt: the restart wall, the
boot marks, and the content gate's `content_sha` (bit-safety). The state assumed:
the pin in `scripts/local.sh`, the source export at `/tmp/tf-src` (re-clone from
the pin's tag after any head reboot — /tmp is ephemeral), and a window slot.

## When to use

- A loader/serve change is hypothesized and needs a measured A/B against the pin.
- The build refused a patch (`PATCH FAILED`, `patch does not apply`) and the fix
  is not obvious.
- The build compiled but failed with a Zig symbol error (`duplicate struct member`).
- A patch window completed and the receipt needs reading (wall, marks, gate sha).

## Workflow

1. Generate the diff against the exact tree the build will apply it to: clone the
   pin (`git clone -q --depth 1 --branch <tag> https://github.com/ashhart/TensorFold /tmp/tf-src`),
   edit there, `git diff -- <file>` into `patches/<name>.patch` with a `#!`
   provenance header (what/why/port-against/owner/status).
2. Verify the FULL STACK in build order: the build applies the staged patches
   ALPHABETICALLY (`for p in /build/patches/*.patch`). A patch that assumes an
   earlier patch must sort after it — rename it (e.g. `glm-upload-marks3.patch`
   sorts after `glm-pinned-upload.patch`; `glm-boot-marks3.patch` does not).
   Verify: a scratch repo, apply each patch in alphabetical order, then check the
   symbols (below). Record the verify in the patch's README entry.
3. Symbol check (git apply is TEXTUAL — it cannot catch Zig semantics): grep the
   post-patch files for the names you introduced. Zig forbids a field and a
   declaration sharing a name — the Loader already had a `scratch()` fn when a
   patch added a `scratch` field (`duplicate struct member name 'scratch'`). Also
   grep for existing fields/fns with your candidate name BEFORE naming.
4. Compile-risk audit before spending a window: every Zig idiom copied from the
   same tree (the clock: `std.Io.Clock.awake.now(io)`; the integer-width rules —
   `i + 1 == layers.len` fails u32-vs-usize, use `@intCast`), the format-string
   placeholder counts, the imports reachable via the package root. A compile
   failure voids a ~25-minute window.
5. Ship: commit, push, sync the head (ff-only), launch
   `PHASES="preflight resumecost summary" RC_PATCHES="..." scripts/autonomous-launch.sh "preflight resumecost summary"`.
   The config fingerprint changes → the auto-prepare rebuilds (~15-25 min) → the
   boot runs the patched engine.
6. Read the receipt: `results/campaign-*/boot-full.log` (the marks, `loaded in`),
   `campaign.log` (the wall: `healthy after N s`), `34-resumecost.md` (the probes
   + the gate). Bit-safety = the probes' `sha=` matches the standing config's gate
   sha. A refusal printing its own arithmetic is a RECEIPT — record it, never
   retry blind.

## Gotchas

- **Alphabetical staging order is load-bearing** (see step 2). The voided
  campaign-20261031-000643 is the receipt.
- **git apply passes what the compiler rejects** — the symbol check is mandatory
  (campaign-20261031-233318's `duplicate struct member name 'scratch'`).
- **Zig locals shadow the enclosing struct's declarations too** — a `const limit`
  inside a struct's method collides with that struct's `limit()` fn
  (`local constant shadows declaration of 'limit'`); the pre-name grep must cover
  the LOCAL names you introduce against the whole enclosing struct, not just the
  top-level names you add. The field case (`scratch`) was caught pre-window; the
  local case cost a build (campaign-20261101-115038).
- **Do NOT try advice-based prefaulting on the GLM loader** (MADV_WILLNEED or
  MADV_POPULATE_READ per tensor): both REGRESSED the boot (+32%/+37%,
  campaigns -221626/-224013) — WILLNEED's async readahead races the fault loop
  into duplicate I/O; the population fattens the per-layer page-cache churn under
  the full unified pool. The reads' own cost is the mmap fault rate (~840 MiB/s
  measured); the fix that worked was upstream's parallel read-ahead (#1616), not advice.
- **The engine prints no boot progress on non-tty stdout** — decompose the boot
  with marks patches (`glm-boot-marks.patch`'s pattern: `std.log.info` phase
  lines, captured via `docker logs --timestamps` in the resumecost ours-branch —
  plain `docker logs` is untimestamped and the stopped container is rm'd at stop).
- **A patch edit on the head's /tmp/tf-src does not persist across reboots** —
  regenerate from the pin's tag; never treat /tmp scratch as state.
- **The nvidia-smi memory.used reads [N/A] on GB10** — sample utilization only,
  or read the room from the engine's own serve line.
- One concern per patch (patches/README rule 3): a bundled patch cannot be
  measured or dropped independently.
- **A phase-level `restart` loses the window's RC_PATCHES** (2026-11-04,
  campaign-20261104-210211): the wrapper's initial boot carries the patch env,
  but an in-phase restart silently falls back to config.sh's PATCHES (empty) —
  the later phases then measure the UNPATCHED serve while the receipt claims
  the patched one. Detection: the serve line's rows-clause ("passes of up to
  2048 rows" where 4096 was expected) and the memory numbers. Before any
  phase of a patched window restarts the serve, re-assert the patch env
  explicitly and verify the rows-clause in the receipt.
- **Porting an instrument function is not copy-paste-simplify** (2026-11-04):
  the deepdelta fill contract computes the repeat count in bash
  (`n=$((d / 27))`) and passes model/tag/n as SEPARATE argv slots; inlining it
  and passing the depth as the count built 1.37M-token fills that the
  admission layer refused instantly — the receipt read "FAILED" with no
  error surfaced. Keep the argv contract when porting a proven instrument;
  sanity-check the built body's size (wc -c on the temp file) before the
  first send.
- **`git apply --reject` can apply ZERO hunks on a cross-tree port** (2026-11-07,
  the exl3p port): the "only the .rej files need hands" recipe assumes hunks are
  locally anchored — a whole-file region rewrite (a 116→267-line kernel loop)
  against a structurally drifted base rejects in every file at once, and the
  applied-hunk guarantee is gone entirely. The line-level fidelity check
  (Workflow → Cross-tree ports) replaces it — 244/244 + 18/18 fork lines
  verified on the port that shipped.
- **`git apply --reject` is NOT idempotent — a scoping run contaminates the
  real run's inventory** (2026-11-09, the 0110 port): the scoping run's
  cleanly-applied hunks STAY in the tree even after `find . -name '*.rej'
  -delete` — only the rejects were removed, the applied hunks remained as
  working-tree modifications. The next apply then rejects the SAME hunks
  differently (the context lines are already applied) and the reject count
  LIES (102 vs the true 79). Before ANY second `--reject` run against a tree:
  `git reset --hard HEAD` AND delete the untracked new files the patch
  creates (they appear as `??` in status — a patch's new files apply as
  untracked and survive a reset). Verify the tree is byte-clean
  (`git status --porcelain | wc -l` → 0) before trusting a reject inventory.
- **A ported patch lands in the STORE (`patches/`), not just the build
  staging dir** (2026-11-09, the 020 promotion sync): production's
  `prepare.sh` stages the named PATCHES list from `patches/` into
  `image/patches/` after `find image/patches -name '*.patch' -delete` — a
  patch copied into `image/patches/` alone dies the next fingerprint
  re-prepare (`PATCHES names 'x.patch' but patches/x.patch does not
  exist`). The store is the source of truth; the image dir is
  build-generated. After any promotion sync, verify every named patch
  exists in the store before the next window re-prepares production.
- **The t256 host suite does NOT compile the GLM family modules** (2026-11-09,
  the 0110 port): `/tmp/t256_full.sh` runs `zig build test-tool-parse-host`,
  which compiles only the server's tool-parse module — the whole
  `zig/src/families/glm/` tree can be broken and the suite stays green
  (RC=0 while 12 family errors existed). The family compile gate is
  `zig build compile-cuda-tests` (the tf-cuda-test runner imports
  `glm_cuda`), or `zig build test-cuda-host` for the host tests. After ANY
  family-module port: run compile-cuda-tests BEFORE trusting the suite.
  Same class: an engine-level change the server modules never reference is
  invisible to every server-side host suite — the GPU-check receipt is the
  only witness (VALIDATION §6).
- **Zig's lazy analysis makes a usage-text-only registration compile-clean
  and dead at runtime** (2026-11-09, the 0110 port): the check program was
  imported and listed in the usage text but never dispatched in `run()` —
  `compile-cuda-tests` passed RC=0 because Zig never analyzed the
  never-referenced module's body (its own compile errors invisible). It
  would have died with an unknown-command error AFTER a wasted GPU window.
  Before any check-program run: verify the command string appears in the
  DISPATCH table (`if (std.mem.eql(u8, cmd, "<name>")) return <mod>.run`),
  not just the usage block — and note that landing the dispatch line is
  what finally forced the body's errors out (eight more rounds). The
  dispatch is the compile gate's real trigger.
- **Port a check program by scanning ITS OWN references first** (2026-11-09,
  the 0110 port, the discipline that ends one-error-per-compile): after
  landing the dispatch, extract every `glm.X.Y` path, `e.`/`x.` member and
  call arity from the check's source and verify each against the tree
  BEFORE compiling — the eight-round grind (keepAt, Options.mtp, e.link,
  snapshots arity, prefill mapping, three beginOn calls) was all
  pre-computable from the check's own text. The scan's grep patterns must
  cover `pub const` ALIASES too (`keepState`/`dropState` are alias
  constants, not fns — a `pub fn`-only scan reports false misses).
- **`docker run -v` with a RELATIVE host path silently becomes a named
  volume** (2026-11-09, the kshardcheck phase): `-v "$OUT:/ids"` where
  `$OUT` is `results/campaign-...` (relative) is parsed as a NAMED VOLUME,
  and the run dies before any GPU work with "includes invalid characters
  for a local volume name". Every `docker run -v` host path must be
  absolute (`readlink -f` at the phase head). The same ssh layers that eat
  `find -exec`'s `;` also eat quoted fallbacks — do the path fix in the
  script, not on the command line.
- **A background coordination poller races the process it feeds — and
  `set -e` turns the loser's failure into a dead phase** (2026-11-09, the
  kshardcheck gate): the "rsync the NCCL id file the moment it appears"
  poller raced rank 1's ssh, rank 1 read the missing file and FAILed in
  ~2 s, and rank 1's nonzero rc hit the campaign script's
  `set -euo pipefail` — the phase died before writing its receipt's rank
  tails and rc lines. Fix BOTH halves: make the handoff SYNCHRONOUS (poll
  for the file's existence in the foreground, rsync, THEN start the
  consumer) and make every rc capture set-e-proof (`cmd || RC=$?`) so a
  failing rank can never kill a phase before its receipt completes. A
  phase that captures another host's rc must NEVER rely on the command's
  success to continue.
- **A two-rank NCCL handshake debugged one rank at a time is the cheap
  path** (2026-11-09, the kshardcheck gate): with the id file present and
  rank 0 absent, rank 1 alone sits BLOCKED in ncclCommInitRank (rc 124 on
  a `timeout N` wrapper) — that silence IS the correct state, proving the
  binary, mounts, env and NCCL env are all sound without rank 0 running.
  Probe each rank's full runtime path solo before blaming the handshake.
- **A scripted-edit helper's idempotency guard silently skips REMOVALS**
  (2026-11-09, the 0110 port): the natural pattern —
  `if new_text in file: print("already applied"); return` — is vacuously
  TRUE for removal edits (the empty or shorter new string is always
  "in" the file), so the removal never happens and the helper LIES
  ("already applied"). The compile gate then fails on the undeclared
  import you thought you had removed. For removal edits, guard on the
  OLD text (`if old_text in file`) or assert the count of the line being
  removed. Same class: an anchor edit that CONSUMES a needed line (here
  the `layout` import line was the anchor and got replaced instead of
  kept) surfaces as `use of undeclared identifier` several errors later
  — grep the post-edit file for every import the new code references
  BEFORE spending a compile.

## Cross-tree ports (a fork patch generated against a different base)

When the patch to ship is a FORK's patch (Mia's series) and our tree's base
has drifted, the port is a hand-rewrite, and hand-rewrites get verified
differently:

1. Read the fork's patch fully first; identify EVERY helper/symbol it
   references and check each against OUR tree (the fork's intermediate
   patches — e.g. a 3-bit work adding a template param — may have changed the
   base declarations the patch assumes). The `+` lines are the fork's new
   text; the `-` lines are the FORK's base, not ours.
2. Port by scripted exact-anchor edits (every replacement asserts its anchor
   is unique) — never by hand in an editor. Keep the fork's text verbatim
   except DOCUMENTED adaptations (each listed in the shipped patch's
   comment/commit message).
3. Line-level fidelity check (replaces the applied-hunk guarantee): parse the
   fork patch's `+` lines per file section and assert every one appears
   verbatim in the ported tree. Reverse-check: every ported line must be a
   fork `+` line, a diff CONTEXT line (space-prefixed — the carried-over
   unchanged text), or a documented adaptation. The forward check catches
   transcription typos; the reverse catches invented code.
4. Template-param drift: a fork param our tree lacks can be KEPT in the
   signature and instantiated only at our value at the call sites — the
   unused instantiations never compile, and `if constexpr` discarded branches
   never instantiate (a helper referenced only in the discarded branch may be
   absent from our tree entirely).
5. If the port changes an EXISTING kernel's register count, the contract
   records must be re-measured: build the sm_121 fatbin, `cuobjdump
   --dump-resource-usage`, and set the records to the MEASURED values (the
   fork's same-nvcc records verify against our build — check, don't assume).
   New kernel names (`_cl` twins) stay unlisted → unchecked.
6. Verify: compile RC=0 on the final tree, then byte-identity — fresh parent
   + `git format-patch` output applied = the commit tree hash.

## Verification

- The scratch-repo stack apply passes in alphabetical order AND the symbol greps
  come back clean (each introduced name exactly once, no collisions).
- The window completes rc=0; `boot-full.log` carries the expected marks; the
  content gate's sha equals the standing config's; the wall delta matches the
  hypothesis (or the receipt explains why not — record it either way).
