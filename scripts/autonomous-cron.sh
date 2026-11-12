#!/usr/bin/env bash
# scripts/autonomous-cron.sh — the head's crash net (cron every 5 min). If
# production is DOWN and no window is running (no flag): restart it through
# the PROMOTED production repo's start.sh (both ranks; PROD_REPO in
# scripts/local.sh) and log it — production must never stay
# down. The wake/poke half lives on the agent host now (scripts/autonomous-
# poke.sh, the opencode server's durable prompt inbox); this file only guards
# production's lifecycle.
set -uo pipefail
cd "$(dirname "$0")/.."
exec 9>/tmp/autonomous-cron.lock
flock -n 9 || exit 0
[ -f scripts/local.sh ] && source scripts/local.sh
: "${PROD_REPO:?set PROD_REPO (the production repo dir name) in scripts/local.sh}"
STATE=/tmp/autonomous-testing.flag
LOG="$HOME/autonomous-cron.log"
PROD="$HOME/$PROD_REPO"
# the maintenance pause (the (user) maintenance window, round 141): while this
# file exists the crash-net HANDS OFF — no restarts, no log noise — so planned
# reboots (both hosts) do not fight the net. It lives in /tmp so the pause is
# SELF-CLEARING: the reboot that ends maintenance removes it too, and the net
# re-arms on the next tick without anyone remembering to re-enable anything.
PAUSE=/tmp/autonomous-maintenance.pause
if [ -f "$PAUSE" ]; then
  echo "[$(date '+%F %T')] maintenance pause present — hands off (rm $PAUSE to re-arm; the reboot clears it)" >> "$LOG"
  exit 0
fi
if ! docker ps --format "{{.Names}}" | grep -qx glm53-native-tf; then
  if [ ! -f "$STATE" ]; then
    echo "[$(date '+%F %T')] production down with no active window — restarting via the production repo's start.sh" >> "$LOG"
    "$PROD/scripts/start.sh" >> "$LOG" 2>&1 || echo "[$(date '+%F %T')] start.sh rc=$? — will retry next tick" >> "$LOG"
  else
    echo "[$(date '+%F %T')] production down, window in flight — hands off" >> "$LOG"
  fi
fi
