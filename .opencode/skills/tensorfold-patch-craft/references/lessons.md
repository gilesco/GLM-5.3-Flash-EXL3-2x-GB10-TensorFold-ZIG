
## 2026-11-09 — the reject inventory lied after a scoping run
- Skill: tensorfold-patch-craft (extended)
- Symptom: the second `git apply --reject` of the 5,309-line 0110 patch
  reported 102 rejected hunks; the first honest run reported 79.
- Root cause: the scoping run's cleanly-applied hunks stayed in the working
  tree (only the `.rej` files were deleted); the re-run rejected the same
  hunks differently against contaminated context.
- Fix: `git reset --hard HEAD` + delete the untracked new files the patch
  creates (`??` entries survive reset) before re-running; verify
  `git status --porcelain` is empty first.
- Location: .opencode/skills/tensorfold-patch-craft/SKILL.md (Gotchas)
- Note: the same sitting also extended the skill with the patches/-store
  promotion-sync gotcha (the image/patches dir alone dies the re-prepare).

## 2026-11-09 — the idempotency guard silently skipped removals
- Skill: tensorfold-patch-craft (extended)
- Symptom: the compile gate kept failing on `use of undeclared identifier
  'layout'` and a FileNotFound import after the "already applied" removal
  edit reported success.
- Root cause: the `if new in s: skip` idempotency guard is vacuously true
  for removals (empty replacement), and a prior anchor edit had consumed a
  needed import line.
- Fix: guard removals on the OLD text's presence; grep the post-edit file
  for every import the new code references before the next compile.
- Location: .opencode/skills/tensorfold-patch-craft/SKILL.md (Gotchas)
- Note: same sitting's compile round also adapted the fork's heads() helper
  to our bool fields (o.mtp and !o.drafter).

## 2026-11-09 — the host suite never compiles the GLM family modules
- Skill: tensorfold-patch-craft (extended)
- Symptom: test-tool-parse-host returned RC=0 while the family tree carried
  12 compile errors; they surfaced only in compile-cuda-tests.
- Root cause: the suite's build target compiles the server's tool-parse
  module only; the tf-cuda-test runner (compile-cuda-tests) is what imports
  glm_cuda.
- Fix: after any family-module port, run compile-cuda-tests before trusting
  the suite.
- Location: .opencode/skills/tensorfold-patch-craft/SKILL.md (Gotchas)
- Note: the engine-level GPU checks (VALIDATION §6) remain the only witness
  for behavior the server modules never reference.

## 2026-11-09 — the lazy-analysis trap: a usage-text-only registration compiles and dies at runtime
- Skill: tensorfold-patch-craft (extended)
- Symptom: compile-cuda-tests passed RC=0 with the check program registered in the
  usage text only; the check would have failed at RUNTIME with unknown-command after
  a wasted GPU window.
- Root cause: Zig analyzes a module lazily — the never-dispatched module's body (and
  its compile errors) never reached the compiler. Landing the DISPATCH line is what
  forced the body's eight error rounds out.
- Fix: verify the command string appears in main.zig's dispatch table before any GPU
  run; land the dispatch FIRST, then fix the body's errors, then compile.
- Location: .opencode/skills/tensorfold-patch-craft/SKILL.md (Gotchas)
- Note: the same sitting recorded the reference-scan discipline (extract the check's
  own glm.X.Y/e./x. references and verify each against the tree before compiling —
  the one-error-per-compile grind was all pre-computable; scan patterns must cover
  pub const aliases, not just fns).

## 2026-11-09 — the kshardcheck gate burned two windows on instrument bugs before touching the GPUs
- Skill: tensorfold-patch-craft (extended)
- Symptom: window 1 died before any GPU work ("invalid characters for a local
  volume name"); window 2 built the binary fine but rank 1 FAILed
  FileNotFound in ~2 s and the phase died before its receipt's rc lines.
- Root cause: (1) relative docker -v host paths become named volumes; (2) a
  background id-file poller raced the consumer it fed, and the consumer's
  nonzero rc hit set -e, killing the phase mid-receipt.
- Fix: absolute paths at the phase head; the handoff synchronous (poll →
  rsync → THEN start the consumer); every rc capture `|| RC=$?`.
- Location: .opencode/skills/tensorfold-patch-craft/SKILL.md (Gotchas)
- Note: rank 1 probed SOLO (blocked in ncclCommInitRank, rc 124) proved the
  whole runtime path sound without rank 0 — the cheap two-rank debug order.

## 2026-11-10 — the kshardcheck CUDA fault: five instrument generations, then the NaN chain
- Skill: tensorfold-patch-craft (extended)
- The chain that worked: launch ring (names the submission order) → TF_LAUNCH_SYNC
  (sync after every launch names the kernel faulting IN EXECUTION — launches succeed
  asynchronously; the ring alone only orders submissions) → compute-sanitizer with
  the report INSIDE a container mount (a host-path log-file inside a container is a
  fake path the root container creates and --rm discards — mount the campaign dir rw
  and write there) → full host-side index validation (samples are not proof: read
  the WHOLE buffer and compute the exact arithmetic the kernel does) → the x/hidden
  NaN site dumps (the value chain, one buffer at a time upstream).
- THE CENSUS PARADOX: diagnostic cuMemcpyDtoH on the NULL stream does NOT serialize
  with the engine's own stream — the reads RACED the kernels mid-flight, and the
  "drifting garbage boundary" was the kernel's WRITE PROGRESS at read time. Every
  diagnostic read must synchronize the stream first. The final state was clean; five
  windows of "garbage picks" were chasing an instrument artifact.
- The compounding lesson: the fault moved UNDER the sanitizer (serialized execution
  changes timing) — position-independent evidence (the ADDRESS, the values) beats
  position evidence (which kernel) when a race is in play.
- Location: .opencode/skills/tensorfold-patch-craft/SKILL.md
