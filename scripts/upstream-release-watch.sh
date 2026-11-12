#!/usr/bin/env bash
# scripts/upstream-release-watch.sh — the (user) wait-for-the-release decision
# (round 141 cont. 50): the #2856 stage brief is SHELVED until the next
# TensorFold release. This watch pokes the session when a tag NEWER than the
# promoted pin appears upstream — the release the rebase rides. Cron on the
# agent host (deep), every 30 min; the durable-inbox POST is the proven wake
# vector (the autonomous-poke.sh shape, this script's sibling).
set -uo pipefail
cd "$(dirname "$0")/.."
[ -f /tmp/autonomous-maintenance.pause ] && exit 0   # the maintenance pause (both arms honor it)
[ -f scripts/local.sh ] && source scripts/local.sh
: "${OPENCODE_API:?set OPENCODE_API (the opencode server API base URL) in scripts/local.sh}"
: "${OPENCODE_UNIT:?set OPENCODE_UNIT (the opencode server systemd unit path) in scripts/local.sh}"
LOG="$HOME/upstream-release-watch.log"
MARKER="$HOME/.upstream-release-last-poked"
PIN_TAG="v1.2.7"   # the promoted pin (the round-141 promotion; the rebase target when a newer tag lands)
PW=$(grep -oP 'OPENCODE_SERVER_PASSWORD=\K.*' "$OPENCODE_UNIT" 2>/dev/null | tr -d '"')
[ -n "$PW" ] || { echo "$(date '+%F %T') no web password — cannot poke" >> "$LOG"; exit 1; }
AUTH="opencode:$PW"
# 1. the newest release tag upstream (gh: the authenticated path — the
# unauthenticated API rate-limits within a single sitting's research; a cron
# running every 30 min would exhaust it in a day. gh's stored token carries
# repo scope; gh auth status verifies it on every call)
LATEST=$(timeout 30 gh api repos/ashhart/TensorFold/releases/latest --jq '.tag_name' 2>/dev/null) || LATEST=""
[ -n "$LATEST" ] || exit 0   # the API hiccuped or rate-limited: retry next tick
[ "$LATEST" = "$PIN_TAG" ] && exit 0   # no new release yet
# 2. not already poked about this one
[ "$(cat "$MARKER" 2>/dev/null)" = "$LATEST" ] && exit 0
# 3. the agent's session in this project (newest first)
SID=$(curl -s -m 10 -u "$AUTH" "$API/session?directory=$PWD&order=desc" \
      | python3 -c "import json,sys; d=json.load(sys.stdin); r=d.get('data') or []; print(r[0]['id'] if r else '')" 2>/dev/null) || true
[ -n "$SID" ] || { echo "$(date '+%F %T') no session found in $PWD" >> "$LOG"; exit 1; }
# 4. the poke
MSG="[upstream release poke] TensorFold $LATEST is out (the promoted pin is $PIN_TAG). The (user) decision (round 141 cont. 50): we WAIT for the release, then rebase. Read the release notes and the Unreleased-to-tag changelog (the GH releases page), name what the release carries for our line — the expected headline is #2843's EXL3 grouped-experts decode-grid fix, possibly #2856's batched shared MTP, possibly #3064's paged FP8 KV — then stage the rebase per the bump protocol (the round-141 v1.2.7 shape: the scratch round-trip verify, the vNNNval battery, the launch last)."
RC=$(curl -s -m 20 -u "$AUTH" -X POST "$API/session/$SID/prompt" -H 'Content-Type: application/json' \
     -d "$(python3 -c 'import json,sys; print(json.dumps({"text": sys.argv[1]}))' "$MSG")" \
     -o /dev/null -w "%{http_code}") || RC=000
if [ "$RC" = "200" ]; then
  echo "$LATEST" > "$MARKER"
  echo "$(date '+%F %T') poked session $SID about $LATEST" >> "$LOG"
else
  echo "$(date '+%F %T') poke POST rc=$RC — will retry next tick" >> "$LOG"
fi
