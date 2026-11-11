#!/usr/bin/env bash
# The documentation guard — runs after every change (the committed pre-commit hook
# executes it; activate with: git config core.hooksPath scripts/hooks).
#
# Checks, each failing with its own fix line:
#   1. bash -n on every scripts/*.sh
#   2. site identifiers in tracked files: real hostnames / ssh targets / the site's
#      rail IPs anywhere; platform-generic device names outside local.sh.example
#   3. the perf chart matches docs/perf-anchors.tsv (render-perf-chart.sh --check)
#   4. the README's PHASES example only names phases the campaign script knows, and
#      its default phase list is complete (checked against the script's PHASES default)
#   5. config.sh's defaults (CONTEXT, PARALLEL, KV_CACHE, DENSE_BITS/HEAD_BITS) appear
#      in the README's configuration table
#   6. on the head (where results/ exists): every campaign dir cited in the docs exists,
#      and the newest campaign dir is mentioned in LAUNCH.md or the ledger
#   7. every local file link/img src in README, AGENTS.md and docs/*.md resolves
#      (relative to the containing file, as GitHub resolves them)
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")/.."

FAILS=0
fail() { printf 'GUARD FAIL: %s\n' "$*" >&2; FAILS=$((FAILS + 1)); }
pass() { printf 'GUARD PASS: %s\n' "$*"; }

# --- 1. syntax -------------------------------------------------------------------
_bad=""
for f in scripts/*.sh; do bash -n "$f" 2>/dev/null || _bad+=" $f"; done
[[ -z $_bad ]] && pass "scripts/*.sh syntax" || fail "syntax errors in:$_bad — run bash -n scripts/<file>"

# --- 2. site identifiers ---------------------------------------------------------
# (the guard's own file is excluded: it must carry the patterns to detect them)
# The forbidden values come from THIS clone's git-ignored site files (local.sh,
# SITE.md) — every address, ssh target, hostname, and netdev they carry. The guard
# embeds no site value itself (its old check pattern carried the site's subnet —
# round 109 removed that).
_forbid=$(sed -nE '
  s/.*([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}).*/\1/p
  s/.*([a-zA-Z0-9_.-]+@[a-zA-Z0-9_.-]+).*/\1/p
  s/.*(brain[0-9]+)([^a-z0-9-]|$).*/\1/p
  s/.*(en[a-zA-Z0-9]*np[0-9]+|roce[a-zA-Z0-9]+).*/\1/p
' scripts/local.sh docs/SITE.md 2>/dev/null | grep -vE '^$' | sort -u)
_site=""
if [ -n "$_forbid" ]; then
  _pat=$(printf '%s\n' $_forbid | sed 's/\./\\./g' | paste -sd '|' -)
  _site=$(git grep -inE "\b($_pat)\b" -- . ':!scripts/docs-guard.sh' ':!scripts/local.sh.example' ':!scripts/discover-site.sh' 2>/dev/null | head -5 || true)
fi
[[ -z $_site ]] || fail "site identifiers committed (hostnames/ssh/IPs/netdevs) — see AGENTS.md:$_site"

# --- 3. the charts ----------------------------------------------------------------
for tsv in docs/*-anchors.tsv; do
  [[ -e $tsv ]] || continue
  if ./scripts/render-perf-chart.sh "$tsv" --check >/dev/null 2>&1; then
    pass "$tsv matches its chart"
  else
    fail "chart stale vs $tsv — ./scripts/render-perf-chart.sh $tsv then commit both"
  fi
done

# --- 4. the phase lists ----------------------------------------------------------
script_default=$(grep -m1 -oP 'PHASES="\$\{PHASES:-\K[^}]+' scripts/run-qualification.sh | tr ' ' '\n' | sort -u)
[[ -n $script_default ]] || fail "cannot read the script's default PHASES list"
readme_phases=$(grep -m1 -oP 'PHASES="\K[^"]+' README.md | tr ' ' '\n' | sort -u)
[[ -n $readme_phases ]] || fail "README's quick start lost its PHASES example"
_unknown=$(comm -23 <(printf '%s\n' "$readme_phases") <(printf '%s\n' "$script_default") | tr '\n' ' ')
[[ -z $_unknown ]] && pass "README's PHASES example names known phases" \
  || fail "README's PHASES example names unknown phases: $_unknown"

# --- 4b. the patch names (round 139: NNN-name.patch, the number IS the order) -----
_pfiles=$(ls patches/*.patch 2>/dev/null | xargs -n1 basename | grep -E '^[0-9]{3}-.*\.patch$' | sort)
[[ -n $_pfiles ]] || fail "no NNN-name.patch files in patches/ (the round-139 scheme)"
_pnums=$(printf '%s\n' $_pfiles | cut -d- -f1)
_pdup=$(printf '%s\n' $_pnums | sort | uniq -d)
[[ -z $_pdup ]] || fail "duplicate patch numbers:$_pdup — renumber"
_pmax=$(printf '%s\n' "$_pfiles" | tail -1 | cut -d- -f1)
_pmax=$((10#$_pmax))
# every number 1..max present (no gaps: the next port takes the next free number,
# and a retired one compacts only with a round entry — gaps would suggest reuse mistakes)
_gap=""
for n in $(seq 1 "$_pmax"); do
  printf '%03d\n' "$n" | grep -qxF "$_pnums" || _gap+=" $n"
done
[[ -z $_gap ]] || fail "patch numbers gap:$_gap — renumber or record the freed number in a round entry"
_cfg=$(grep -m1 -oP '^PATCHES="\$\{PATCHES-\K[^}]+' config.sh | tr ' ' '\n' | grep '.patch$')
_for_cfg=""
for f in $_cfg; do
  printf '%s\n' "$_pfiles" | grep -qxF "$f" || _for+=" $f"
done
[[ -z $_for_cfg ]] || fail "config.sh's PATCHES names files that are not in patches/:$_for_cfg"
grep -q "^PATCHES=" config.sh || fail "config.sh lost its PATCHES line"
pass "patch names are NNN-name, numbered 1..$_pmax with no gaps; the PATCHES default resolves"

# --- 5. config defaults in the README table --------------------------------------

# --- 5. config defaults in the README table --------------------------------------
check_default() {  # $1 config var, $2 README grep pattern, $3 what must appear
  local d
  d=$(grep -m1 -oP "^$1=\"\\\$\\{$1:?-?\\K[^}]+" config.sh || true)
  [[ -n $d ]] || { fail "cannot read $1's default from config.sh"; return; }
  if grep -q "^$2" README.md && grep "^$2" README.md | grep -q -- "$3"; then
    pass "README's $1 row carries the default ($3)"
  else
    fail "README's $1 row does not carry the config.sh default ($3) — update the config table"
  fi
}
check_default CONTEXT   '| `CONTEXT`'  "$(grep -m1 -oP '^CONTEXT="\$\{CONTEXT:-\K[^}]+' config.sh)"
check_default KV_CACHE  '| `KV_CACHE`'              "$(grep -m1 -oP '^KV_CACHE="\$\{KV_CACHE:?-?\K[^}]+' config.sh)"
check_default DENSE_BITS '| `DENSE_BITS`' "$(grep -m1 -oP '^DENSE_BITS="\$\{DENSE_BITS:-\K[^}]+' config.sh)"

# --- 6. receipt existence (the head only — results/ is not in git) ---------------
if [[ -d results ]]; then
  _phantom=""
  for c in $(grep -hoE 'campaign-[0-9]{8}-[0-9]{6}' docs/*.md | sort -u); do
    [[ -d "results/$c" ]] || _phantom+=" $c"
  done
  [[ -z $_phantom ]] && pass "every cited campaign dir exists" \
    || fail "docs cite campaign dirs that do not exist:$_phantom"
  newest=$(ls -t results | head -1)
  if grep -q "$newest" docs/LAUNCH.md docs/log/*.md docs/TOOL_EVAL_TESTING.md 2>/dev/null; then
    pass "the newest campaign ($newest) is in the log or the ledger"
  else
    fail "the newest campaign ($newest) is not in LAUNCH.md or the ledger — fold it in"
  fi
fi

# --- 6b. the launch index is fresh ------------------------------------------------
# The index is generated from the split log (LAUNCH.md + docs/log/); regenerate it
# in the same sitting a log append lands, or this fails the commit. The check
# diffs a fresh render against the committed file (the chart's --check pattern):
# content must be identical, so a stale index fails no matter how the counts drift.
_tmp=$(mktemp)
if OUT="$_tmp" ./scripts/render-launch-index.sh >/dev/null 2>&1 && diff -q "$_tmp" docs/LAUNCH_INDEX.md >/dev/null 2>&1; then
  pass "LAUNCH_INDEX.md matches the log ($(grep -c '^\| \[' docs/LAUNCH_INDEX.md) round entries)"
else
  fail "LAUNCH_INDEX.md is stale vs the split log (LAUNCH.md + docs/log/) — ./scripts/render-launch-index.sh then commit both"
fi
rm -f "$_tmp"

# --- 7. links resolve ------------------------------------------------------------
_badlinks=""
for f in README.md AGENTS.md docs/*.md; do
  d=$(dirname "$f")
  while IFS= read -r l; do
    case $l in \#*|http*|mailto*) continue ;; esac
    l=${l%%#*}; [[ -n $l ]] || continue
    [[ -e "$d/$l" ]] || _badlinks+=" $f -> $l"
  done < <(grep -oE '\]\([^)]+\)|src="[^"]+"' "$f" 2>/dev/null \
    | sed -E 's/^\]\(|^src="//; s/\)$|"$//')
done
[[ -z $_badlinks ]] && pass "all local links resolve" || fail "broken local links:$_badlinks"

# --- summary ---------------------------------------------------------------------
if [[ $FAILS -gt 0 ]]; then
  printf 'GUARD: %d failure(s)\n' "$FAILS" >&2
  exit 1
fi
printf 'GUARD: all checks pass\n'
