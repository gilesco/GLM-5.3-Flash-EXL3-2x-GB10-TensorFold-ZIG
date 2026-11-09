
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
