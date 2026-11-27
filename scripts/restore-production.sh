#!/usr/bin/env bash
# scripts/restore-production.sh — the round-163 incident restore: return
# serving to the PROMOTED production stack (v1.3.5) after the poisoned
# image tag (glm53-native-tf:commit — BOTH repos tag it; the testing
# prepare overwrote production's image and the crash-net's restart served
# the broken v1.3.6 compose AS PRODUCTION).
#
# Two invocations, run ON THE HEAD:
#   scripts/restore-production.sh prepare   # phase A: rebuild the image
#                            from the production repo's own pin. SAFE to
#                            run while the fallback serves — nothing stops.
#   scripts/restore-production.sh swap      # phase B: the detached swap —
#                            stop the fallback vLLM (the agent's serving
#                            path: the agent goes dark ~2 min), start the
#                            production stack (both ranks), health-wait,
#                            coherence curl. Run DETACHED (setsid nohup) —
#                            it must survive the agent's session. ON ANY
#                            FAILURE the fallback restarts: nobody is
#                            stranded.
#
# The log: /tmp/restore-production.log (both phases append).
set -uo pipefail
LOG=/tmp/restore-production.log
PROD=~/GLM-5.3-Flash-EXL3-2x-GB10-TensorFold-production
TEST=~/GLM-5.3-Flash-EXL3-2x-GB10-TensorFold-ZIG-testing
FALLBACK_CONTAINER=vllm_node
say() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

phase="${1:-}"
case "$phase" in
prepare)
  say "=== phase A: re-preparing PRODUCTION from its own pin ==="
  cd "$PROD" || exit 1
  grep "^TF_COMMIT" scripts/local.sh | tee -a "$LOG"
  POISONED_ID=$(docker images --format "{{.ID}}" glm53-native-tf:commit)
  say "the image ID BEFORE prepare: $POISONED_ID"
  if scripts/prepare.sh </dev/null >>"$LOG" 2>&1; then
    NEW_ID=$(docker images --format "{{.ID}}" glm53-native-tf:commit)
    say "prepare OK; the image ID AFTER: $NEW_ID"
    echo "image_id=$NEW_ID" > /tmp/restore-production.state
    grep -oE "tf=[^ ]+" /home/giles/.local/state/glm53-native/prepared \
      | tee -a "$LOG"
  else
    say "PREPARE FAILED — the image may still be poisoned; DO NOT swap."
    say "read $LOG."
    exit 1
  fi
  say "=== phase A done ==="
  ;;
swap)
  say "=== phase B: the swap (the agent goes dark here) ==="
  # 1. the image must be the one phase A built: the recorded image ID
  if [ ! -f /tmp/restore-production.state ]; then
    say "REFUSING: no phase-A state (/tmp/restore-production.state)."
    say "run 'restore-production.sh prepare' first"; exit 1
  fi
  WANT_ID=$(sed -n 's/^image_id=//p' /tmp/restore-production.state)
  GOT_ID=$(docker images --format "{{.ID}}" glm53-native-tf:commit)
  say "the image: want=$WANT_ID got=$GOT_ID"
  if [ -z "$WANT_ID" ] || [ "$WANT_ID" != "$GOT_ID" ]; then
    say "REFUSING: the image is not the phase-A build."
    say "re-run prepare"; exit 1
  fi
  # 2. stop the fallback (the agent's serving path)
  say "stopping the fallback ($FALLBACK_CONTAINER) — serving goes dark"
  docker stop "$FALLBACK_CONTAINER" >>"$LOG" 2>&1 \
    || say "the fallback stop returned $? (continuing)"
  sleep 3
  # 3. start production (both ranks) through the production repo's own scripts
  say "starting the production stack (the production repo's start.sh)"
  cd "$PROD" || exit 1
  if ! scripts/start.sh </dev/null >>"$LOG" 2>&1; then
    say "PRODUCTION START FAILED — restarting the fallback"
    docker start "$FALLBACK_CONTAINER" >>"$LOG" 2>&1
    say "the fallback is back; read $LOG"; exit 1
  fi
  # 4. health-wait (the weights load in minutes)
  ok=""
  for i in $(seq 1 60); do
    sleep 10
    if curl -sf -m 5 localhost:8000/health >/dev/null 2>&1; then
      ok=yes; break
    fi
  done
  if [ -z "$ok" ]; then
    say "HEALTH WAIT TIMED OUT (10 min) — restarting the fallback"
    docker stop glm53-native-tf >/dev/null 2>&1
    docker start "$FALLBACK_CONTAINER" >>"$LOG" 2>&1
    say "the fallback is back; read $LOG"; exit 1
  fi
  say "production /health is UP after $((i * 10)) s"
  # 5. a coherence curl: a tiny prompt, the content must be non-empty
  BODY='{"model":"GLM-5.3-Flash-EXL3","messages":[{"role":"user",'
    '"content":"Reply with exactly: restored"}],"max_tokens":512,'
    '"temperature":0}'
  RESP=$(curl -sf -m 120 localhost:8000/v1/chat/completions \
    -H "Content-Type: application/json" -d "$BODY" 2>/dev/null)
  PYEXTRACT='import json,sys
d = json.load(sys.stdin)
m = d["choices"][0]["message"]
print((m.get("content") or "")[:120])'
  C=$(echo "$RESP" | python3 -c "$PYEXTRACT" 2>/dev/null)
  if [ -n "$C" ]; then
    say "coherence check: the reply's content: $C"
    say "=== RESTORED: production serves the promoted v1.3.5 stack ==="
  else
    say "coherence check: EMPTY/failed reply — the serve may be degraded"
    say "read $LOG and the container logs"
    say "=== the stack is UP but UNVERIFIED — investigate first ==="
  fi
  ;;
*)
  say "usage: restore-production.sh prepare|swap"; exit 1 ;;
esac
