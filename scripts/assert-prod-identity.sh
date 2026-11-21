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
# the round-154 extension: the mutable state the two repos must never
# share — STATE_DIR (the prepared marker's home; the round-154 collision:
# the testing window's prepare overwrote the SHARED marker and the
# production restore's start.sh read the TESTING marker) and IMAGE_NAME
# (the docker image tag both prepares build into). The guard fires on a
# repo whose PORT is the TESTING port (8001) but whose STATE_DIR is
# production's UNSUFFIXED dir — the round-154 collision shape (the
# testing repo silently writing production's marker). Production itself
# carries the unsuffixed dir legitimately; the round-155 false-positive
# lesson: the guard must check the COLLISION (testing port + shared
# dir), not the shared dir alone.
if grep -q 'PORT="${PORT:-8001}"' "$CFG" \
  && grep -q '^STATE_DIR="${STATE_DIR:-$HOME/.local/state/glm53-native}"' \
    "$CFG"; then
  echo "IDENTITY GUARD: $CFG is the testing stack but writes production's" \
    "STATE_DIR (the round-154 collision class)" >&2; fail=1
fi
if grep -q 'PORT="${PORT:-8001}"' "$CFG" \
  && grep -q '^IMAGE_NAME="${IMAGE_NAME:-glm53-native-tf}"' "$CFG"; then
  echo "IDENTITY GUARD: $CFG is the testing stack but builds into" \
    "production's IMAGE_NAME (the round-154 collision class)" >&2
  fail=1
fi
if [ "$fail" -ne 0 ]; then
  echo "IDENTITY GUARD: $REPO does not carry production's identity —" \
    "no start/stop/sync from it (round 146: the testing identity rode a" \
    "promotion sync into the production repo and only the reboot" \
    "exposed it)" >&2
  exit 1
fi
echo "IDENTITY GUARD: $REPO carries production's identity" \
  "(8000 / glm53-native-tf)"
