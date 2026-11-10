#!/usr/bin/env bash
# scripts/autonomous-launch.sh — the ONLY way a window is launched (the round-89
# inline-chain incident; the round-93 double-launch race where one launch's flag
# rm stripped the flag another window had just taken, so the crash-net started
# production mid-window). Syncs the head to origin/main, refuses when a window
# is already running, and starts the window detached. The agent calls exactly
# this, via one ssh, as the LAST action of its turn:
#   ssh <head> 'cd <repo> && scripts/autonomous-launch.sh "preflight ncurouter summary"'
set -uo pipefail
cd "$(dirname "$0")/.."
STATE=/tmp/autonomous-testing.flag
# DRY_RUN=1 runs every gate (double-launch, phase-name, phase-lint) and prints
# the would-be launch — but starts NO window and touches NO flag. The safe way
# to replay the launcher's refusal paths or preview a launch (round 141: the
# valid-arguments replay of a real launcher IS a real launch).
DRY_RUN="${DRY_RUN:-0}"
[ -f "$STATE" ] && { echo "a window is already running ($STATE) — refusing"; exit 1; }
# the phase-name gate (round 141: window 35 was a no-op void — the requested
# `cachefixqual` phase had been swept out of run-qualification.sh by the same
# sitting's retirement sweep, and `want` matches nothing silently; the window
# stopped production, ran preflight+summary in 10 s, and exited rc=0). Every
# requested phase name must appear in the script's `want` dispatch table or
# the launch REFUSES — before production is ever stopped.
WANT_TABLE=$(grep -oP "want \K[a-z0-9_]+" scripts/run-qualification.sh | sort -u)
UNKNOWN=""
for p in ${1:-preflight summary}; do
  echo "$WANT_TABLE" | grep -qx "$p" || UNKNOWN="$UNKNOWN $p"
done
if [ -n "$UNKNOWN" ]; then
  echo "REFUSED: phase(s) not in run-qualification.sh's dispatch table:$UNKNOWN"
  echo "  dispatch table: $(echo "$WANT_TABLE" | tr '\n' ' ')"
  echo "  (a swept-away, typo'd, or renamed phase cannot run; add the phase to"
  echo "   scripts/run-qualification.sh first, then relaunch)"
  exit 1
fi
# the phase-lint gate (round 140: windows 33/34 burned by staged phase code —
# the doubled env name and the unguarded grep under set -euo pipefail): the
# launch REFUSES on lint findings. Fix the phase, then relaunch.
if ! scripts/phase-lint.sh scripts/run-qualification.sh; then
  echo "phase-lint FAILED — fix the findings above, then relaunch"; exit 1
fi
if [ "$DRY_RUN" = "1" ]; then
  echo "DRY_RUN: all gates pass; would launch: ${1:-preflight summary} (console ${2:-/tmp/autonomous.console})"
  exit 0
fi
git fetch origin -q || true
git merge --ff-only origin/main -q || echo "sync to origin/main failed — launching the checkout as-is"
setsid nohup scripts/autonomous-window.sh "${1:-preflight summary}" "${2:-/tmp/autonomous.console}" </dev/null >/tmp/autonomous-launch.log 2>&1 &
sleep 1
echo "launched: ${1:-preflight summary}"
