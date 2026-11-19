# Stage brief — drop020val
# (the 020 drop-verify: the store's default shrinks to 17 patches)

## The question

Does the 17-patch store (020-cachefirst dropped from the default PATCHES)
serve **bit-identically and gate-clean** against the qualified 18-patch
state — so the store's default carries 020 no longer?

## The value-if-yes

The store every future rebase re-anchors loses one member — the 020
cachefirst member is the stack's second-largest rebase surface (both
kv_pool files, both re-cut by hand at v1.2.7 and re-composed at v1.2.10).
Every future release rebase skips its two-file composition and its
collision checks. User-visible: none directly; the lever is the loop's
rebase cost and the store's fidelity surface (the round-142 incident
burned on exactly a stale member riding through a rebase).

## The desk ground (this sitting, no window spent to learn it)

1. **020's live hunks are all gated off at our standing serve.** The
   `windows()` room0 line fires only when `budget.cache_first` is true
   AND `engine_paged` AND NOT `asked` (no `--prompt-cache-gib` — our
   serve never sets it); the fund-report line fires only when
   `prompt_cache_gib != null`. At the bare serve both are dead.
2. **The adopted env never reached the container.** `TF_PROMPT_CACHE_FIRST`
   is exported in config.sh but `env_args()` forwards only
   `TENSORFOLD_|TF_GLM_|TF_HEAT_|TF_ROCE_|TF_KV_|NCCL_` prefixes — the
   live production container's env has no `TF_PROMPT_CACHE_FIRST`
   (verified by `docker exec ... env`). The "adoption" was never live.
3. **IF it were forwarded, it would cost the pool ~1,000 pages.**
   `budgetOf`'s un-asked probe sets `out.cache` to
   `cacheBytes(null, left, 0)` — the automatic half-room-with-16-GiB-floor
   after the planned streams (~1,000 pages of the ~4,180-page pool).
   Forwarding the flag would shrink the funded windows from four toward
   three. The env being dead protected production.
4. **The round-139 cachefirstqual A/B never armed a live difference.**
   The ON arms' page deltas (3,110→3,103/3,083) sit inside the
   boot-state room wobble the round-149 digest quantified
   (±0.1 GiB ≈ ±30 pages per boot) — and the ON arms' env went through
   the same dead-forwarding path, so both arms served the identical
   windows-first arithmetic. The +6.1%-c4 attribution in the round-139
   note belonged to 022-shared-budgets (mainlined at v1.2.7), not 020.
5. **The byte-exact desk replay (this sitting)**: pristine v1.2.10 +
   the store minus 020 differs from the qualified composed tree in
   exactly the two kv_pool files — 020's owned content, nothing else.

## The arms

- **The candidate arm (the only serve)**: the 17-patch store — the
  standing config with `PATCHES` minus 020-cachefirst. The fingerprint
  moves (one fewer patch staged), so the window re-prepares.
- No A/B arm: the comparison is the qualified 18-patch receipt's own
  instruments — the greedy witness `80cc3802…`, the §2 gates,
  hardmode 95, the vision 4/4, the walls band. The kv_pool content
  difference is provably dead code at our serve; the battery proves the
  drop moved nothing live.

## The gates (all must hold)

- The greedy same-bits witness: `80cc3802…` IDENTICAL.
- The §2 content gates: ALL PASS.
- Hardmode: **95** (the thirty-eighth consecutive on PASS).
- The vision suite: 4/4.
- The walls: inside the band (the v1.2.10 walls 83/83 s; the band's
  center 80 s, ±10%).
- The pool line: the same arithmetic as the v1.2.10 receipt at the same
  room figure (the boot-state wobble priced separately per round 149).
- The serve line must NOT name the cache-first reserve (no behavioral
  cache-first line at boot).

## The kill criterion

ANY gate FAIL reverts the store's default to the 18-patch stack and
re-anchors the question with the receipt — the drop does not land on a
single missed gate. The pin holds at v1.2.10 either way: this window
gates a store member, not the engine.

## The closest prior instrument

The videorows window (campaign-20261118-102606) — the same shape: a
config-side member change (a default flips), the full battery as the
gate, the serve line as the engagement witness. Diff against it: this
window has NO ON/OFF A/B (the OFF side is the qualified record itself,
the byte-exact replay replaced the live arm) and adds the
fingerprint-change prepare (the videorows window shared the image).

## The constants the instrument assumes

- The greedy witness sha `80cc3802…` — measured, the standing
  same-bits witness across five engine bumps.
- The pool-pages-per-GiB slope (~305-314/GiB) — measured in the
  round-149 digest; used only to price the boot-state wobble, not as a
  gate.
- The walls band center (80 s, ±10%) — the standing anchor row.

## The retirement

On PASS: the PATCHES default drops 020 in config.sh, the store keeps the
patch file on disk (retired members are never deleted), patches/README.md
records the drop with this receipt, the README's stack table and the
config row re-date to 17, the anchors/chart unchanged (no perf claim
moved), and the production repo's store drops 020 at the next promotion
sync (the guard asserts its identity first — round 146).
