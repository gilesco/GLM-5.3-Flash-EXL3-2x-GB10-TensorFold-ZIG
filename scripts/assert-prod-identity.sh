#!/usr/bin/env bash
# scripts/assert-prod-identity.sh — the round-146 guard (the port-identity
# incident: a promotion sync's wholesale config copy carried the TESTING
# identity — PORT=8001 + the -test container name — into the PRODUCTION
# repo, and only the reboot exposed it). Asserts a repo's config.sh carries
# PRODUCTION's identity BEFORE any start.sh/stop.sh runs from it or any sync
# lands into it: PORT must default 8000 and the container must be the
# unsuffixed glm53-native-tf. Fails loudly and changes nothing.
# Callers: autonomous-cron.sh + autonomous-window.sh (before every
# production stop/start) and the promotion sync (before committing).
set -uo pipefail
REPO="${1:-}"
[ -n "$REPO" ] || {
  echo "usage: assert-prod-identity.sh <repo-dir>" >&2; exit 2
}
CFG="$REPO/config.sh"
[ -f "$CFG" ] || {
  echo "IDENTITY GUARD: $CFG missing — refusing" >&2; exit 1
}
fail=0
chk() { # $1 ok-pattern, $2 bad-pattern, $3 message
  if grep -q "$1" "$CFG"; then return 0; fi
  if grep -q "$2" "$CFG"; then
    echo "IDENTITY GUARD: $3" >&2; fail=1
  else
    echo "IDENTITY GUARD: $3" \
      "(and the production default is missing)" >&2; fail=1
  fi
}
chk '^PORT="${PORT:-8000}"' '^PORT="${PORT:-8001}"' \
  "$CFG does not default PORT=8000 (the production port)"
chk '^CONTAINER_NAME="${CONTAINER_NAME:-glm53-native-tf}"' \
  '^CONTAINER_NAME="${CONTAINER_NAME:-glm53-native-tf-test}"' \
  "$CFG does not default CONTAINER_NAME=glm53-native-tf (unsuffixed)"
if [ "$fail" -ne 0 ]; then
  echo "IDENTITY GUARD: $REPO does not carry production's identity —" \
    "no start/stop/sync from it (round 146: the testing identity rode a" \
    "promotion sync into the production repo and only the reboot" \
    "exposed it)" >&2
  exit 1
fi
echo "IDENTITY GUARD: $REPO carries production's identity" \
  "(8000 / glm53-native-tf)"
