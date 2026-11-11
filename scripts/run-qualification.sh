#!/usr/bin/env bash
# The 0.6.x -> 1.1.x replication campaign: one blank run on the head Spark that
# tests everything needed to work out the way forward for this repo.
#
#   bash scripts/run-qualification.sh            # everything (~3 h)
#   PHASES="parity kvqual" bash scripts/run-qualification.sh   # a subset
#   FORCE=1 ...                                  # re-run even completed phases
#
# What it does, in order (each phase lands a receipt in results/campaign-<id>/):
#   preflight  guards (production untouched), marker, RoCE, CPU clocks, disk
#   reference  one greedy probe captured from production if it is still up
#              (read-only, a single request) — the cross-engine output reference
#              (the prodqual phase retired round 132 (user): metrics on the clean
#              testing port 8001 only — the duel's baseline arm on 8001 is the
#              native-vs-native instrument) + the same-harness tool-eval
#              and perf runs, giving the native engine's 92 its like-for-like
#              production baseline. Prompts to stop production only if GPU phases
#              are also selected.
#   parity     the knob-for-knob mirror of production on this engine:
#              DENSE_BITS=8 HEAD_BITS=8 KV_CACHE=fp8 CONTEXT=524288 + DFlash2,
#              benched with the fixed matrix options (PARALLEL=4, fallback 2)
#   candidate  dense4fp8 at the same window — the ladder candidate's cell
#   kvqual     VALIDATION §2 gates on dense8+fp8 KV at 512K, content form
#              (determinism, drafted=plain, resumed=fresh, concurrent=solo,
#              sampled-seed determinism; the native engine is byte-nondeterministic,
#              so gates compare normalized content — VALIDATION §2 receipt)
#   kvqual4    the same gates on the ladder candidate dense4fp8 (its own receipt)
#   throughput perf-only bench tables (llama-benchy pp/tg) for parity + dense4fp8
#   kvqual4P   the gates on PAGED bf16 KV (TF_KV_PAGES=on): the KV-pages branch pages the
#              bf16 KV path ONLY — fp8 KV and paging are mutually exclusive there (the
#              engine exits on the combination; 87e4417e receipt, campaign-20261023-165319)
#   throughputP the perf-only bench on paged bf16 KV (dense4, 512K window)
#              at 512K — the speed numbers the first campaign's full-eval cells lack
#   (climb/climbP retired round 132 (user): PARALLEL caps at 4 on the 2-node pair —
#   no 5/6/8 tests anywhere; the 5/6/8 refusals at 512K stand receipted in
#   campaign-20261102-081320)
#   depth      the depth gate the forum thread taught us: seeded fact+needle
#              probes at 8k/64k/192k/384k on the fp8-KV 512K config (production's
#              93.9% Cyrillic score is the community bar)
#   cliff      the concurrency cliff: 4-stream decode with vs without one
#              structured-output request in the batch (the draft-truncation
#              mechanism MaTeZZ documented on the vLLM stacks)
#   prefill    corrected probe 3: a ~14k-token prompt's prefill rate
#   rung       the 524288x1 ladder rung: admission line + a depth probe
#   summary    CAMPAIGN.md: verdict per gate + the way-forward recommendations
#
# Safety: this script never touches production (glm53-native-tf, the promoted stack — round 138). If production is
# running it captures the reference probe and then STOPS and asks you to stop
# production yourself; with PROMPT=0 it refuses and exits instead.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")/.."
source ./config.sh
# THE METRICS PORT LOCK (user, round 132): every quality/perf instrument runs on the
# clean testing port 8001 — never against the live production on 8000. One guard here
# covers every load arm and probe the script contains.
[[ "$PORT" == "8001" ]] || { echo " !! metrics run on the testing port 8001 only (user, round 132); PORT is '$PORT' — refusing"; exit 1; }
command -v docker >/dev/null || die "docker is required (run this on the head Spark)"
command -v python3 >/dev/null || die "python3 is required"
BENCH="$HOME/tool-eval-bench/.venv/bin/tool-eval-bench"
[[ -x "$BENCH" ]] || die "tool-eval-bench not found at $BENCH"

RUN_ID="campaign-$(date +%Y%m%d-%H%M%S)"
OUT="results/$RUN_ID"; mkdir -p "$OUT"
LOG="$OUT/campaign.log"
log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }
phase_done() { [[ -f "$OUT/.$1.done" ]] && [[ "${FORCE:-0}" != 1 ]]; }

PHASES="${PHASES:-preflight reference parity candidate kvqual kvqual4 throughput kvqual4P throughputP knobs duel confirm depth cliff prefill rung summary}"
want() { case " $PHASES " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }
# Do the selected phases need the testing stack on the GPUs? (everything except the
# read-only production passes and the summary — those run against production AS IS)
NEEDS_GPU=0
for _p in parity candidate kvqual kvqual4 throughput kvqual4P throughputP knobs duel confirm depth cliff prefill rung cachefixqual livehalf regresswatch vision2744; do
  want "$_p" && NEEDS_GPU=1
done

# ---------------------------------------------------------------------------
# shared helpers
# ---------------------------------------------------------------------------
prod_running() {   # the PROMOTED production up here and on the worker? (round 138: the name-shared
                   # testing stack is glm53-native-tf-test (the -test suffix, the round-138 fix) — never
                   # trips this; the round-139 (user) directive retired the old tip recipe — the
                   # baseline arm of a duel is THIS repo's own config on the testing stack's own
                   # name, also never trips this)
  docker ps --format '{{.Names}}' | grep -qx '^glm53-native-tf$' && return 0
  ssh -o BatchMode=yes -o ConnectTimeout=5 "$WORKER" \
    'docker ps --format "{{.Names}}" | grep -qx "^glm53-native-tf$"' 2>/dev/null && return 0
  return 1
}

restart() {        # restart the testing stack with env pairs: restart K=V ...
  local kv rc=0
  if prod_running; then die "production (glm53-native-tf) is running — stop it first; this script never touches it"; fi
  log "restarting the testing stack (${*:-defaults})"
  local ST0=$(date +%s)
  ./scripts/stop.sh < /dev/null >/dev/null 2>&1 || true
  log "the stop: $(( $(date +%s) - ST0 )) s"
  if [[ $# -gt 0 ]]; then env "$@" ./scripts/start.sh < /dev/null >>"$LOG" 2>&1 || rc=$?
  else ./scripts/start.sh < /dev/null >>"$LOG" 2>&1 || rc=$?; fi
  log "serving: $(serve_line)"
  log "$(roce_state)"
  # propagate start.sh's exit code even when called in an if-context (set -e is
  # suppressed there) — refusals stay visible for any admission probe
  return $rc
}

restart_fb() {     # restart with PARALLEL=4, falling back to PARALLEL=2 on refusal
  local retry=() kv
  if restart "$@"; then return 0; fi
  log "start failed — retrying with PARALLEL=2"
  for kv in "$@"; do [[ "$kv" == PARALLEL=* ]] || retry+=("$kv"); done
  restart "${retry[@]}" PARALLEL=2
}

roce_state() {     # did the RoCE gather come up on this launch?
  if docker logs "$CONTAINER_NAME" 2>&1 | grep -q "VerbsUnavailable\|NCCL carries every gather"; then
    echo "RoCE DOWN (fallback warning present)"
  elif docker logs "$CONTAINER_NAME" 2>&1 | grep -q "RoCE all-gather"; then
    echo "RoCE up: $(docker logs "$CONTAINER_NAME" 2>&1 | grep -m1 'RoCE all-gather' | sed 's/^info: //')"
  else
    echo "RoCE: no gather lines in the log"
  fi
}

# The duel's five-probe arm, shared by the duel phase and the session phases
# (prof4/top4) so every instrument reads the same way everywhere.
DUEL_PROMPT="Write a 300-word technical summary of a harbor crane's maintenance cycle. Do not use any formatting."

duel_arm() {   # $1 engine tag ("prod"|"ours"|<cell>), $2 the model id to address
  local tag="$1" model="$2" H
  H="http://127.0.0.1:$PORT"
  # the probe set, generated once per tag
  SERVED_MODEL="$model" PROMPT="$DUEL_PROMPT" FILL_WORDS="$FILL_WORDS" python3 - "$OUT" "$tag" <<'PYEOF'
import json, os, sys
out, tag, prompt = sys.argv[1], sys.argv[2], os.environ["PROMPT"]
model = os.environ["SERVED_MODEL"]
base = {"model": model, "temperature": 0}
for d in (0, 4096, 8192):
    if d == 0:
        body = dict(base, messages=[{"role": "user", "content": prompt}])
    else:
        words = os.environ["FILL_WORDS"].split(); n = d // 4
        fill = " ".join(w if i % 11 == 0 else w + f"-{i % 89}" for i, w in
                        ((i, words[i % len(words)]) for i in range(n)))
        body = dict(base, messages=[{"role": "user", "content": fill + "\n\n" + prompt}])
    json.dump(dict(body, max_tokens=2048), open(f"{out}/duel-{tag}-d{d}-2048.json", "w"))
    json.dump(dict(body, max_tokens=1),   open(f"{out}/duel-{tag}-d{d}-1.json", "w"))
PYEOF
    curl -s -m 10 "$H/health" > "$OUT/duel-$tag-health-before.json" || true
    # instrument 1+5: the solo twins (twice — stability), then c2 and c4 concurrently
    for r in a b; do
      S=$(date +%s.%N)
      curl -s -m 300 "$H/v1/chat/completions" -H 'Content-Type: application/json' \
        --data @"$OUT/duel-$tag-d0-2048.json" > "$OUT/duel-$tag-solo-$r.json" || true
      E=$(date +%s.%N); echo "$r $S $E" >> "$OUT/duel-$tag-walls.txt"
    done
    for c in 2 4; do
      S=$(date +%s.%N)
      for i in $(seq 1 "$c"); do { curl -s -m 300 "$H/v1/chat/completions" -H 'Content-Type: application/json' \
        --data @"$OUT/duel-$tag-d0-2048.json" > "$OUT/duel-$tag-c$c-$i.json" || true; } & done; wait
      E=$(date +%s.%N); echo "c$c $S $E" >> "$OUT/duel-$tag-walls.txt"
    done
    # instrument 2: the streamed twin (per-chunk rhythm)
    SERVED_MODEL="$model" python3 - "$OUT" "$tag" "$H" "$DUEL_PROMPT" <<'PYEOF'
import json, os, sys, time, urllib.request
out, tag, url, prompt = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
body = json.load(open(f"{out}/duel-{tag}-d0-2048.json")); body["stream"] = True
req = urllib.request.Request(url + "/v1/chat/completions",
                             data=json.dumps(body).encode(),
                             headers={"Content-Type": "application/json"})
t0 = time.monotonic(); gaps = []; prev = None; first = None
try:
    with urllib.request.urlopen(req, timeout=600) as r:
        for line in r:
            s = line.strip()
            if not s.startswith(b"data:") or s == b"data: [DONE]":
                continue
            now = time.monotonic()
            if prev is None: first = now - t0
            else: gaps.append(now - prev)
            prev = now
except Exception as e:
    print(f"- duel-{tag} stream failed: {e}"); raise SystemExit(0)
gaps.sort()
pick = lambda p: gaps[min(len(gaps) - 1, int(len(gaps) * p))] if gaps else 0
json.dump({"chunks": len(gaps) + 1, "first_chunk_ms": (first or 0) * 1000,
           "mean_itl_ms": sum(gaps) / len(gaps) * 1000 if gaps else 0,
           "p50_itl_ms": pick(.5) * 1000, "p95_itl_ms": pick(.95) * 1000},
          open(f"{out}/duel-{tag}-itl.json", "w"))
PYEOF
    # instrument 3: the prefill slope (max_tokens=1, three depths)
    for d in 0 4096 8192; do
      S=$(date +%s.%N)
      curl -s -m 300 "$H/v1/chat/completions" -H 'Content-Type: application/json' \
        --data @"$OUT/duel-$tag-d$d-1.json" > "$OUT/duel-$tag-prefill-$d.json" || true
      E=$(date +%s.%N); echo "p$d $S $E" >> "$OUT/duel-$tag-walls.txt"
    done
    curl -s -m 10 "$H/health" > "$OUT/duel-$tag-health-after.json" || true
    # the receipt block for this engine
    python3 - "$OUT" "$tag" >> "$P" <<'PYEOF'
import glob, json, sys
out, tag = sys.argv[1], sys.argv[2]
walls = {}
for line in open(f"{out}/duel-{tag}-walls.txt"):
    k, s, e = line.split(); walls[k] = float(e) - float(s)
rates = []
for r in ("a", "b"):
    try:
        d = json.load(open(f"{out}/duel-{tag}-solo-{r}.json"))
        rates.append(d["usage"]["completion_tokens"] / walls[r])
    except Exception: pass
if len(rates) == 2:
    print("- solo decode: %.1f / %.1f t/s (stability Δ %.1f%%)" % (rates[0], rates[1], abs(rates[0]-rates[1])/max(rates)*100))
for c in (2, 4):
    try:
        tot = sum(json.load(open(f))["usage"]["completion_tokens"]
                  for f in glob.glob(f"{out}/duel-{tag}-c{c}-*.json"))
        print("- c%d aggregate: %.1f t/s" % (c, tot / walls[f"c{c}"]))
    except Exception: pass
try:
    itl = json.load(open(f"{out}/duel-{tag}-itl.json"))
    print("- ITL per chunk: mean %.1f ms, p50 %.1f, p95 %.1f (%d chunks, first %.0f ms)" % (
        itl["mean_itl_ms"], itl["p50_itl_ms"], itl["p95_itl_ms"], itl["chunks"], itl["first_chunk_ms"]))
except Exception: pass
tt = {}
for d in (0, 4096, 8192):
    tt[d] = walls.get(f"p{d}", 0) * 1000
if all(tt.values()):
    print("- TTFT (max_tokens=1): d0 %.0f ms; d4096 %.0f; d8192 %.0f → slope %.3f ms/token, fixed overhead %.0f ms" % (
        tt[0], tt[4096], tt[8192], (tt[8192]-tt[0])/8192, tt[0]))
try:
    b = json.load(open(f"{out}/duel-{tag}-health-before.json")); a = json.load(open(f"{out}/duel-{tag}-health-after.json"))
    for k in ("drafted", "accepted", "rounds"):
        if isinstance(b, dict) and isinstance(a, dict) and k in b and k in a:
            d = a.get(k, 0) - b.get(k, 0)
            if d: print("- %s Δ: %d" % (k, d))
except Exception: pass
PYEOF
}

c4_reprobe() {     # $1 tag: 4 fresh concurrent 2048-token generations on the d0 body;
                   # prints the aggregate and leaves the engine's last 64-call prof
                   # window = this probe, so a following prof-line extraction reads c4
  local tag="$1" S E
  [[ -s "$OUT/duel-$tag-d0-2048.json" ]] || { echo "- c4 re-probe skipped: $OUT/duel-$tag-d0-2048.json missing (the duel arm did not run under this tag)"; return 0; }
  S=$(date +%s.%N)
  for i in 1 2 3 4; do { curl -s -m 300 "http://127.0.0.1:$PORT/v1/chat/completions" \
    -H 'Content-Type: application/json' --data @"$OUT/duel-$tag-d0-2048.json" \
    > "$OUT/duel-$tag-c4b-$i.json" || true; } & done
  wait
  E=$(date +%s.%N)
  python3 - "$S" "$E" "$OUT" "$tag" <<'PYEOF'
import glob, json, sys
s, e, out, tag = float(sys.argv[1]), float(sys.argv[2]), sys.argv[3], sys.argv[4]
tot = sum(json.load(open(f))["usage"]["completion_tokens"] for f in glob.glob(f"{out}/duel-{tag}-c4b-*.json"))
print("- c4 re-probe (fresh, so the prof window below is this probe): %.1f t/s aggregate" % (tot / (e - s)))
PYEOF
}

clock_mhz() {      # delivered CPU clock (MaTeZZ's acpi_cppc probe), 0 if unreadable
  local host="$1" out snippet
  snippet=$(cat <<'EOF'
f=/sys/devices/system/cpu/cpu5/acpi_cppc/feedback_ctrs
[[ -e $f ]] || { echo 0; exit 0; }
taskset -c 5 timeout 4 sh -c 'while :; do :; done' &
sleep 1; a=$(cat "$f"); sleep 2; b=$(cat "$f"); wait
echo "$a $b" | tr -d 'a-z:' | awk '{m=int(1000*($4-$2)/($3-$1)); print (m>100 && m<6000)?m:0}'
EOF
)
  if [[ "$host" == local ]]; then out=$(bash -c "$snippet" 2>/dev/null) || out=0
  # bash -s reads the snippet from STDIN — `ssh host bash -c "$snippet"` lets the
  # remote shell word-split it: its second line ran standalone with $f unset and
  # echoed 0 (the worker's eternal zero, solved round 132 cont. 29)
  else out=$(ssh -o BatchMode=yes -o ConnectTimeout=5 "$host" bash -s <<<"$snippet" 2>/dev/null) || out=0; fi
  echo "${out:-0}"
}

serve_line() {     # the sm_121 admission line of the running server, verbatim
  docker logs "$CONTAINER_NAME" 2>&1 | grep -m1 "CUDA sm_121" || echo "(no server line)"
}

bench_cell() {     # the fixed matrix bench options against the running server
                   # (the base URL is the testing port, unconditionally — the
                   # metrics-port lock at the script's start is the one guard)
  local label="$1" dest="$2" rc=0
  mkdir -p "$dest"
  # --hardmode (user, round 132): hardmode is THE quality instrument and it INCLUDES
  # the standard batch — the plain 69-scenario run is retired; scores never cross-compare
  # --parallel 2 is the BENCH HARNESS's scenario concurrency (tool-eval-bench's own
  # option, user round 139 cont. 10) — two scenarios in flight against the serve, so
  # two separate contexts coexist in the KV pool: a cross-spill probe. It is NOT the
  # serve's PARALLEL= lanes (config.sh — the engine's stream count; the gates restart
  # with PARALLEL=4). The two stack: 2 bench scenarios × 4 server lanes.
  PYTHONUNBUFFERED=1 "$BENCH" run \
    --base-url "http://127.0.0.1:$PORT/v1" \
    --model "$SERVED_NAME" \
    --format openai \
    --tokenizer "$MODEL_ID" \
    --seed 42 --perf --hardmode --parallel 2 --timeout 240 --no-live \
    --label "$label" --output-dir "$dest" --json-file "$dest/result.json" \
    2>&1 | tee "$dest/bench.log" | tail -20 || rc=$?
  # a non-zero bench exit must not kill the campaign (set -e) — record it and move on
  [[ $rc -ne 0 ]] && echo "- NOTE: bench exited $rc (its receipts may still be complete)" || true
  return 0
}

chat() {           # one chat completion; $1 = request file, optional $2 = curl timeout
  curl -s -m "${2:-900}" "http://127.0.0.1:$PORT/v1/chat/completions" \
    -H 'Content-Type: application/json' --data @"$1"
}

bench_perf() {     # $1 label, $2 dest, $3 client parallel (default 4) — the matrix's
                   # quick perf mode (--perf-only: llama-benchy pp/tg, minutes per cell).
                   # Prints a short live tail, then the saved report's results table.
  local label="$1" dest="$2" clients="${3:-4}" report rc=0
  mkdir -p "$dest"
  PYTHONUNBUFFERED=1 "$BENCH" run \
    --base-url "http://127.0.0.1:$PORT/v1" \
    --model "$SERVED_NAME" \
    --format openai \
    --tokenizer "$MODEL_ID" \
    --seed 42 --perf --perf-only --parallel "$clients" --timeout 240 --no-live \
    --label "$label" --output-dir "$dest" --json-file "$dest/result.json" \
    2>&1 | tee "$dest/bench.log" | tail -4 || rc=$?
  # a non-zero bench exit must not kill the campaign (set -e) — record it and move on
  [[ $rc -ne 0 ]] && echo "- NOTE: bench exited $rc (its report may still be complete)" || true
  report=$(ls -t "$dest"/2026/*/*--*.md "$dest"/2026/*/*/*--*.md 2>/dev/null | head -1) || true
  if [[ -n "${report:-}" ]]; then sed -n '/^| Test/,/^$/p' "$report" || true; fi
  return 0
}

sha_msg() {        # sha256 of the whole response message, canonical JSON (raw-file sha on parse failure)
  python3 -c '
import hashlib, json, sys
raw = open(sys.argv[1], "rb").read()
try:
    m = json.loads(raw)
    print(hashlib.sha256(json.dumps(m, sort_keys=True).encode()).hexdigest())
except Exception:
    print(hashlib.sha256(raw).hexdigest())
' "$1"
}

content_of() {
  python3 -c '
import json, sys
try:
    m = json.load(open(sys.argv[1]))
    print(m["choices"][0]["message"].get("content") or "")
except Exception:
    print("")
' "$1"
}

content_sha() {    # sha256 of the normalized CONTENT text (whitespace-folded, reasoning excluded).
                   # The native engine is byte-level nondeterministic at greedy (2026-10-23 receipt:
                   # g1 raw shas differ while content matches), so the §2 gates bind on content,
                   # with raw-sha equality recorded as a bonus line when it holds.
  python3 -c '
import hashlib, json, re, sys
try:
    m = json.load(open(sys.argv[1]))
    c = m["choices"][0]["message"].get("content") or ""
except Exception:
    c = ""
print(hashlib.sha256(re.sub(r"\s+", " ", c).strip().encode()).hexdigest())
' "$1"
}

req_file() {       # $1 dest, $2 prompt text, rest: extra curl body fields as JSON obj
  local dest="$1" prompt="$2" extra="${3:-}"
  SERVED_MODEL="$SERVED_NAME" MSG_PROMPT="$prompt" MSG_EXTRA="$extra" python3 - "$dest" <<'EOF'
import json, os, sys
body = {
    "model": os.environ["SERVED_MODEL"],
    "messages": [{"role": "user", "content": os.environ["MSG_PROMPT"]}],
    "temperature": 0, "max_tokens": 512,
}
if os.environ["MSG_EXTRA"]:
    body.update(json.loads(os.environ["MSG_EXTRA"]))
json.dump(body, open(sys.argv[1], "w"))
EOF
}

# A seeded filler that tokenizes ~4 chars/token without the degenerate-repeat trap.
FILL_WORDS="harbor lantern gravel meadow tideline quarry bramble inkwell thicket ferry
cistern gable linden sluice cobble rafter minnow heather bracken cellars
windlass tarn larch furrow beck gantry lintel osier marl culvert"

filler_words() {  # $1 = approximate token count -> N words on stdout
  python3 - "$1" "$FILL_WORDS" <<'EOF'
import random, sys
n, words = int(sys.argv[1]), sys.argv[2].split()
random.seed(1234)
out = []
for i in range(n):
    w = words[i % len(words)]
    out.append(f"{w}{i%97}" if i % 11 == 0 else w)
print(" ".join(out))
EOF
}

# ---------------------------------------------------------------------------
# phase: preflight
# ---------------------------------------------------------------------------
if want preflight && ! phase_done preflight; then
  log "=== preflight"
  P="$OUT/00-preflight.md"; : > "$P"
  # preflight demands the stop only when GPU phases are selected. Round 138: the stop itself is
  # the window wrapper's job (autonomous-window.sh stops the PROMOTED production through the
  # production repo's own scripts before the block runs) — the block never stops production
  # itself; if production is still up here, the wrapper's stop failed and the GPU phases must
  # not start.
  if prod_running && [[ "$NEEDS_GPU" == 1 ]]; then
    log "PRODUCTION IS STILL RUNNING — the window wrapper's stop failed (or a no-window run): the GPU phases will not start"
    prod_running && die "production still running — the GPU phases will not start; the window wrapper owns the stop"
  elif prod_running; then
    log "production is up — read-only phases only (reference); no restarts selected"
  fi
  prod_running && [[ "$NEEDS_GPU" == 1 ]] && die "production still running — this script will not continue"
  {
    echo "# preflight $RUN_ID"
    echo "- prepared marker: $(cat "$STATE_DIR/prepared" 2>/dev/null || echo MISSING)"
    echo "- head clocks delivered: $(clock_mhz local) MHz (healthy X925 ~3900, floor ~1378)"
    echo "- worker clocks delivered: $(clock_mhz "$WORKER") MHz"
    echo "- head RoCE devices: $(ibdev2netdev 2>/dev/null | head -4 | tr '\n' '; ' || echo 'ibdev2netdev missing')"
    echo "- NCCL_IB_HCA: ${NCCL_IB_HCA:-<empty>}"
    echo "- disk free head: $(df -BG /home | awk 'NR==2{print $4}')"
  } >> "$P"
  [[ -n "${NCCL_IB_HCA:-}" ]] || log "WARNING: NCCL_IB_HCA empty — the RoCE gather will not come up"
  touch "$OUT/.preflight.done"
fi

# ---------------------------------------------------------------------------
# phase: reference (production's output capture; read-only, one request)
# ---------------------------------------------------------------------------
REF_PROMPT="List the first eight prime numbers in order, comma separated, then state the sum."
if want reference && ! phase_done reference; then
  log "=== reference"
  P="$OUT/01-reference.md"; : > "$P"
  if prod_running; then
    req_file "$OUT/ref-req.json" "$REF_PROMPT"
    if curl -s -m 120 "http://127.0.0.1:$PROD_PORT/v1/chat/completions" \
         -H 'Content-Type: application/json' --data @"$OUT/ref-req.json" \
         > "$OUT/reference-prod.json"; then
      {
        echo "# production reference (the promoted native production, read-only single request)"
        echo "- sha256: $(sha_msg "$OUT/reference-prod.json")"
        echo '- content: '"$(content_of "$OUT/reference-prod.json" | head -c 400)"
      } >> "$P"
      log "production reference captured"
    else
      echo "# production reference: request failed (production up but not answering?)" >> "$P"
    fi
  else
    echo "# production reference: production was not running at campaign start — skipped" >> "$P"
    log "production not up; reference skipped (comparisons will be internal only)"
  fi
  touch "$OUT/.reference.done"
fi

# (the prodqual phase RETIRED round 132 (user): ALL quality/perf metrics run on the
# clean testing port 8001 — never against the live production on 8000 (it negates the
# testing environment), so there is nothing this phase can measure in place. The
# production-vs-us instrument is the DUEL: production started FOR TESTING on 8001
# (the intent-keyed port), the five direct instruments, both engines on 8001.)

# ---------------------------------------------------------------------------
# phase: parity + candidate (the bench cells; restart with admission fallback)
# ---------------------------------------------------------------------------
run_cell() {       # $1 label, $2.. env pairs; PARALLEL=4 first, fallback 2
  local label="$1"; shift
  local P="$OUT/$label.md"; : > "$P"
  log "=== cell $label: restart (parallel 4, fallback 2)"
  if ! restart_fb "$@"; then
    echo "# $label: server refused to start at parallel 4 and 2" >> "$P"; return 1; fi
  echo "# $label" >> "$P"; echo "- server: $(serve_line)" >> "$P"; echo "- $(roce_state)" >> "$P"
  log "bench: $label"
  bench_cell "$label" "$OUT/$label" >> "$P" 2>&1
  grep -A11 "^| Test" "$OUT/$label"/2026/*/*--*.md "$OUT/$label"/2026/*/*/*--*.md 2>/dev/null | head -13 >> "$P" || true
}

if want parity && ! phase_done parity; then
  run_cell parity DENSE_BITS=8 HEAD_BITS=8 KV_CACHE=fp8 CONTEXT=524288 PARALLEL=4
  touch "$OUT/.parity.done"
fi

if want candidate && ! phase_done candidate; then
  run_cell dense4fp8 DENSE_BITS=4 HEAD_BITS=4 KV_CACHE=fp8 CONTEXT=524288 PARALLEL=4
  touch "$OUT/.candidate.done"
fi

# ---------------------------------------------------------------------------
# VALIDATION §2 gates, content form — shared by kvqual (dense8) and kvqual4 (dense4fp8)
# ---------------------------------------------------------------------------
run_gates() {      # $1 tag (receipt file prefix), $2.. the gated config's env pairs
  local tag="$1"; shift
  if ! restart_fb "$@" PARALLEL=4; then
    echo "- SKIP: server refused to start for the gate config" >> "$P"
    return 1
  fi

  # g1 determinism: the same greedy probe twice — content is the gate, raw bytes are the FYI
  req_file "$OUT/g-$tag-req.json" "$REF_PROMPT"
  chat "$OUT/g-$tag-req.json" > "$OUT/g-$tag-1a.json"; chat "$OUT/g-$tag-req.json" > "$OUT/g-$tag-1b.json"
  local CA CB BA BB
  CA=$(content_sha "$OUT/g-$tag-1a.json"); CB=$(content_sha "$OUT/g-$tag-1b.json")
  BA=$(sha_msg "$OUT/g-$tag-1a.json"); BB=$(sha_msg "$OUT/g-$tag-1b.json")
  if [[ "$CA" != "$CB" ]]; then
    echo "- FAIL g1 determinism: greedy CONTENT differs across two runs on the same server" >> "$P"
  elif [[ "$BA" == "$BB" ]]; then
    echo "- PASS g1 determinism: two greedy runs byte-identical" >> "$P"
  else
    echo "- PASS g1 determinism (content): two greedy runs identical in content; raw bytes differ" >> "$P"
    echo "  (byte-level engine nondeterminism — reasoning/metadata bytes; the 0.6.x Python engine was byte-stable, the native one is not)" >> "$P"
  fi

  # g2 drafted = plain (the 0.6.x guarantee, in its semantic form: content, not bytes)
  cp "$OUT/g-$tag-1a.json" "$OUT/g-$tag-2-drafted.json"  # drafted arm = captured with DFlash2 on (g1 server)
  if ! restart "$@" PARALLEL=4 DRAFTS=0; then
    echo "- SKIP g2 drafted=plain: server refused to start with DRAFTS=0" >> "$P"
    return 1
  fi
  chat "$OUT/g-$tag-req.json" > "$OUT/g-$tag-2-plain.json"
  if [[ "$(content_sha "$OUT/g-$tag-2-drafted.json")" == "$(content_sha "$OUT/g-$tag-2-plain.json")" ]]; then
    echo "- PASS g2 drafted=plain (content): DFlash2-drafted and --no-drafts greedy outputs identical" >> "$P"
    [[ "$(sha_msg "$OUT/g-$tag-2-drafted.json")" != "$(sha_msg "$OUT/g-$tag-2-plain.json")" ]] && \
      echo "  (raw bytes differ — that is the g1 byte-level nondeterminism, not the drafter)" >> "$P"
  else
    echo "- FAIL g2 drafted=plain: CONTENT differs between drafted and plain" >> "$P"
    diff <(content_of "$OUT/g-$tag-2-drafted.json") <(content_of "$OUT/g-$tag-2-plain.json") | head -5 >> "$P" || true
  fi

  # g3 resumed = fresh (the prompt cache's snap hooks) — the SAME 3-message conversation
  # sent twice: arm 1 computes every token (cold cache, just restarted), arm 2 is a full
  # prefix-cache hit. The 0.6.x gate, in its semantic form. (The first campaign's version
  # wrongly compared two DIFFERENT prompts — turn 2 alone vs turn 1+2 — unrunnable by design.)
  if ! restart_fb "$@" PARALLEL=4; then
    echo "- SKIP g3 resumed=fresh: server refused to start" >> "$P"
    return 1
  fi
  local T1 T2 R1 A B
  T1="Remember these three codes: alpha-7391, bravo-2250, charlie-8118. Reply with exactly: codes noted."
  T2="What were the three codes? Answer with just the three codes, comma separated."
  SERVED_MODEL="$SERVED_NAME" T1="$T1" python3 - "$OUT" "$tag" <<'EOF'
import json, os, sys
json.dump({"model": os.environ["SERVED_MODEL"],
           "messages": [{"role": "user", "content": os.environ["T1"]}],
           "temperature": 0, "max_tokens": 1024}, open(f"{sys.argv[1]}/g-{sys.argv[2]}-3-turn1.json", "w"))
EOF
  chat "$OUT/g-$tag-3-turn1.json" > "$OUT/g-$tag-3-turn1-resp.json"
  R1=$(content_of "$OUT/g-$tag-3-turn1-resp.json")
  SERVED_MODEL="$SERVED_NAME" T1="$T1" T2="$T2" R1="$R1" python3 - "$OUT" "$tag" <<'EOF'
import json, os, sys
msgs = [{"role": "user", "content": os.environ["T1"]},
        {"role": "assistant", "content": os.environ["R1"]},
        {"role": "user", "content": os.environ["T2"]}]
json.dump({"model": os.environ["SERVED_MODEL"], "messages": msgs,
           "temperature": 0, "max_tokens": 1024}, open(f"{sys.argv[1]}/g-{sys.argv[2]}-3-conv.json", "w"))
EOF
  chat "$OUT/g-$tag-3-conv.json" > "$OUT/g-$tag-3-computed.json"
  chat "$OUT/g-$tag-3-conv.json" > "$OUT/g-$tag-3-cached.json"
  A=$(content_of "$OUT/g-$tag-3-computed.json"); B=$(content_of "$OUT/g-$tag-3-cached.json")
  if [[ "$A" == "$B" && -n "$A" ]]; then
    echo "- PASS g3 resumed=fresh (content): cache-hit reply identical to the computed reply (answer: $(echo "$A" | head -c 60))" >> "$P"
  else
    echo "- FAIL g3 resumed=fresh: computed='$A' cached='$B'" >> "$P"
  fi
  for arm in computed cached; do
    python3 - "$OUT/g-$tag-3-$arm.json" "$arm" >> "$P" <<'EOF'
import json, sys
try:
    u = json.load(open(sys.argv[1]))["usage"]
    print("- g3 %s arm: cached_tokens=%s" % (sys.argv[2],
          (u.get("prompt_tokens_details") or {}).get("cached_tokens")))
except Exception:
    pass
EOF
  done

  # g4 concurrent = solo (content form)
  chat "$OUT/g-$tag-req.json" > "$OUT/g-$tag-4-solo.json"
  for i in 1 2 3 4; do { chat "$OUT/g-$tag-req.json" > "$OUT/g-$tag-4-c$i.json" || true; } & done; wait
  local S OK BYTES i
  S=$(content_sha "$OUT/g-$tag-4-solo.json"); OK=1; BYTES=0
  for i in 1 2 3 4; do
    [[ "$(content_sha "$OUT/g-$tag-4-c$i.json")" == "$S" ]] || OK=0
    [[ "$(sha_msg "$OUT/g-$tag-4-c$i.json")" == "$(sha_msg "$OUT/g-$tag-4-solo.json")" ]] || BYTES=$((BYTES+1))
  done
  if [[ "$OK" == 1 ]]; then
    echo "- PASS g4 concurrent=solo (content): all 4 concurrent outputs identical in content to solo" >> "$P"
    [[ "$BYTES" -gt 0 ]] && echo "  ($BYTES/4 differ in raw bytes — the g1 byte-level nondeterminism)" >> "$P"
  else
    echo "- FAIL g4 concurrent=solo: at least one concurrent output differs in CONTENT from solo" >> "$P"
  fi

  # g5 sampled determinism (seeded, twice)
  SERVED_MODEL="$SERVED_NAME" python3 - "$OUT" "$tag" <<'EOF'
import json, os, sys
json.dump({"model": os.environ["SERVED_MODEL"],
           "messages": [{"role": "user", "content": "List the first eight prime numbers in order, comma separated, then state the sum."}],
           "temperature": 0.7, "top_p": 0.95, "seed": 42, "max_tokens": 512},
          open(f"{sys.argv[1]}/g-{sys.argv[2]}-5-req.json", "w"))
EOF
  chat "$OUT/g-$tag-5-req.json" > "$OUT/g-$tag-5a.json"; chat "$OUT/g-$tag-5-req.json" > "$OUT/g-$tag-5b.json"
  if [[ "$(sha_msg "$OUT/g-$tag-5a.json")" == "$(sha_msg "$OUT/g-$tag-5b.json")" ]]; then
    echo "- PASS g5 sampled determinism: seeded sample byte-identical across two runs" >> "$P"
  elif [[ "$(content_sha "$OUT/g-$tag-5a.json")" == "$(content_sha "$OUT/g-$tag-5b.json")" ]]; then
    echo "- NOTE g5 sampled determinism: seeded samples identical in content, raw bytes differ" >> "$P"
  else
    echo "- NOTE g5 sampled determinism: seeded samples differ (sampling is not seed-reproducible on this engine; recorded, not gating)" >> "$P"
  fi
}

# phase: kvqual — the gates on dense8+fp8 KV at the 512K window
# ---------------------------------------------------------------------------
if want kvqual && ! phase_done kvqual; then
  log "=== kvqual (dense8)"
  P="$OUT/03-kvqual.md"; : > "$P"
  echo "# kvqual (VALIDATION §2 on fp8 KV, dense8, 512K window; content-form gates — the native engine is byte-nondeterministic, see g1)" >> "$P"
  if run_gates dense8 DENSE_BITS=8 HEAD_BITS=8 KV_CACHE=fp8 CONTEXT=524288; then
    touch "$OUT/.kvqual.done"
  else
    echo "- kvqual incomplete (a restart was refused) — rerun this phase" >> "$P"
  fi
fi

# phase: kvqual4 — the same gates on the ladder candidate dense4fp8
# ---------------------------------------------------------------------------
if want kvqual4 && ! phase_done kvqual4; then
  log "=== kvqual4 (dense4fp8)"
  P="$OUT/03b-kvqual4.md"; : > "$P"
  echo "# kvqual4 (VALIDATION §2 on fp8 KV, DENSE_BITS=4, 512K window; the ladder candidate's own gates)" >> "$P"
  if run_gates dense4fp8 DENSE_BITS=4 HEAD_BITS=4 KV_CACHE=fp8 CONTEXT=524288; then
    touch "$OUT/.kvqual4.done"
  else
    echo "- kvqual4 incomplete (a restart was refused) — rerun this phase" >> "$P"
  fi
fi

# phase: throughput — the perf-only bench (llama-benchy pp/tg) for both fp8 cells at 512K.
# The first campaign's bench call accidentally ran the full tool-eval (quality 92) —
# this phase collects the speed tables those receipts lack.
# ---------------------------------------------------------------------------
if want throughput && ! phase_done throughput; then
  log "=== throughput (perf-only: parity + dense4fp8 at 512K)"
  P="$OUT/03c-throughput.md"; : > "$P"
  echo "# throughput (perf-only bench, 512K window, fp8 KV)" >> "$P"
  if restart_fb DENSE_BITS=8 HEAD_BITS=8 KV_CACHE=fp8 CONTEXT=524288 PARALLEL=4; then
    echo "## parity (dense8+fp8)" >> "$P"; echo "- server: $(serve_line)" >> "$P"
    bench_perf parity "$OUT/parity-perf" 4 >> "$P"
  else
    echo "- parity config refused to start" >> "$P"
  fi
  if restart_fb DENSE_BITS=4 HEAD_BITS=4 KV_CACHE=fp8 CONTEXT=524288 PARALLEL=4 TF_KV_PAGES=off; then
    echo "## dense4fp8" >> "$P"; echo "- server: $(serve_line)" >> "$P"
    bench_perf dense4fp8 "$OUT/dense4fp8-perf" 4 >> "$P"
  else
    echo "- dense4fp8 config refused to start" >> "$P"
  fi
  touch "$OUT/.throughput.done"
fi


# ---------------------------------------------------------------------------
# phase: kvqual4P — VALIDATION §2 gates on PAGED GLM KV (the #1163/#1211 branch):
# dense4bf16 at the 512K window, TF_KV_PAGES=on, KV_CACHE unset (bf16 is the only
# paged path — the engine exits on fp8 KV × paging, 87e4417e receipt,
# campaign-20261023-165319). First a NO-PAGING control at the same window so the
# receipt answers "would it admit anyway": window-mode bf16 holds ~6.3 GiB per
# stream, so PARALLEL=4 should refuse (~2 streams fit); paging allocates 512-row
# pages on demand, so gate-short prompts may admit 4.
# ---------------------------------------------------------------------------
if want kvqual4P && ! phase_done kvqual4P; then
  log "=== kvqual4P (paged dense4bf16)"
  P="$OUT/05a-kvqual4P.md"; : > "$P"
  echo "# kvqual4P (VALIDATION §2 on PAGED bf16 KV, DENSE_BITS=4, 512K window; TF_KV_PAGES=on)" >> "$P"
  if restart DENSE_BITS=4 HEAD_BITS=4 CONTEXT=524288 PARALLEL=4; then
    echo "- window-mode control (no TF_KV_PAGES): bf16 KV admitted PARALLEL=4 at 512K (the expected refusal did NOT happen — recorded)" >> "$P"
  else
    echo "- window-mode control (no TF_KV_PAGES): bf16 at 512K refused PARALLEL=4 — the window arithmetic holds; paging is the only route to parity" >> "$P"
    docker logs "$CONTAINER_NAME" 2>&1 | tail -2 >> "$P"
  fi
  if run_gates dense4bf16P DENSE_BITS=4 HEAD_BITS=4 CONTEXT=524288 TF_KV_PAGES=on; then
    touch "$OUT/.kvqual4P.done"
  else
    echo "- kvqual4P incomplete (a restart was refused) — rerun this phase" >> "$P"
  fi
fi

# ---------------------------------------------------------------------------
# phase: throughputP — perf-only bench on PAGED bf16 KV (dense4, 512K window):
# the same packing as dense4fp8 with only the KV dtype+layout different, so the
# tables compare directly against the fp8-window receipts in TOOL_EVAL_TESTING.md.
# ---------------------------------------------------------------------------
if want throughputP && ! phase_done throughputP; then
  log "=== throughputP (perf-only: paged dense4bf16 at 512K)"
  P="$OUT/05b-throughputP.md"; : > "$P"
  echo "# throughputP (perf-only bench, 512K window, PAGED bf16 KV, DENSE_BITS=4)" >> "$P"
  if restart_fb DENSE_BITS=4 HEAD_BITS=4 CONTEXT=524288 TF_KV_PAGES=on PARALLEL=4; then
    echo "- server: $(serve_line)" >> "$P"; echo "- $(roce_state)" >> "$P"
    bench_perf "dense4bf16P" "$OUT/dense4bf16P" 4 >> "$P"
  else
    echo "- dense4bf16P config refused to start (paged bf16 at 512K, PARALLEL=4)" >> "$P"
  fi
  touch "$OUT/.throughputP.done"
fi

# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# phase: knobs — the untested TF_GLM_ decode/prefill knobs (2026-10-23 source
# scan of the pin): TF_GLM_DRAFT_CONFIDENCE (where a DFlash2 chain's chance
# product stops it, default 0.7 — the decode acceptance trade), TF_GLM_PROMPT_
# STEPS=0 (prompt passes run whole — no other stream's round between chunks),
# TF_GLM_OVERLAP_PIECES=6 (a prompt chunk's RoCE exchanges in 6 row pieces,
# default 3), TF_GLM_KDA_DECODE_WIDE=0 (KDA decode off the three-kernel chain).
# Each cell is a TIMED restart — the engine's own "loaded in Ns" line is the
# loading-time metric (the RETIRED Python recipe loaded in 93.7 s — kept for reference until the round-139 native-vs-native re-pair re-dates the pair; the promoted production boots in ~80 s; our restart walls run
# ~265 s — the load-nodraft cell isolates the drafter's share). Baseline: the
# dense4fp8 receipts (campaign-20261023-093827, and the 185520 A/B round).
# ---------------------------------------------------------------------------
if want knobs && ! phase_done knobs; then
  log "=== knobs (untested TF_GLM_ decode/prefill knobs, dense4fp8 @ 512K)"
  P="$OUT/06-knobs.md"; : > "$P"
  echo "# knobs (dense4fp8 + fp8 KV + 524288 x4; each cell = timed restart + bench matrix)" >> "$P"
  echo "- loading-time anchor: the retired Python recipe loaded in 93.7 s (kept for reference); the promoted production boots ~80 s; the native-vs-native re-pair re-dates this pair (round 139). Our restart walls run ~265 s" >> "$P"
  knob_cell() {   # $1 label, $2.. env pairs — timed restart, the engine's load line, bench
    local label="$1" S E loaded
    shift
    S=$(date +%s)
    if restart "$@"; then
      E=$(date +%s)
      loaded=$(docker logs "$CONTAINER_NAME" 2>&1 | { grep -oE "loaded in [0-9.]+s" || true; } | tail -1)
      echo "## $label — wall $((E-S)) s, engine ${loaded:-"(no loaded-in line)"}" >> "$P"
      echo "- server: $(serve_line)" >> "$P"; echo "- $(roce_state)" >> "$P"
      bench_perf "knob-$label" "$OUT/knob-$label" 4 >> "$P"
    else
      echo "## $label — refused to start" >> "$P"
      docker logs "$CONTAINER_NAME" 2>&1 | tail -2 >> "$P"
    fi
  }
  knob_cell conf055  DENSE_BITS=4 HEAD_BITS=4 KV_CACHE=fp8 CONTEXT=524288 PARALLEL=4 TF_GLM_DRAFT_CONFIDENCE=0.55
  knob_cell conf085  DENSE_BITS=4 HEAD_BITS=4 KV_CACHE=fp8 CONTEXT=524288 PARALLEL=4 TF_GLM_DRAFT_CONFIDENCE=0.85
  knob_cell steps0   DENSE_BITS=4 HEAD_BITS=4 KV_CACHE=fp8 CONTEXT=524288 PARALLEL=4 TF_GLM_PROMPT_STEPS=0
  knob_cell overlap6 DENSE_BITS=4 HEAD_BITS=4 KV_CACHE=fp8 CONTEXT=524288 PARALLEL=4 TF_GLM_OVERLAP_PIECES=6
  knob_cell kdawide0 DENSE_BITS=4 HEAD_BITS=4 KV_CACHE=fp8 CONTEXT=524288 PARALLEL=4 TF_GLM_KDA_DECODE_WIDE=0
  # the loading-time cells: the drafter's share of our ~265 s (packing share is read
  # off the engine's own lines; a bf16 cell is not expressible via env pairs — an
  # unset would be needed, so packing is inferred from the engine's load lines)
  knob_cell load-nodraft DENSE_BITS=4 HEAD_BITS=4 KV_CACHE=fp8 CONTEXT=524288 PARALLEL=4 DRAFTS=0
  touch "$OUT/.knobs.done"
fi

# ---------------------------------------------------------------------------
# phase: prof — TF_GLM_PROF=1: where a forward's GPU time goes. The engine's
# cuda_prof.zig sums CUDA-event sections per forward and logs averages every 64
# calls per draft-window profiler; probes at max_tokens 2048 generate ~78 calls
# per window, so every window reports. The concurrency question: our aggregate
# decode FALLS with streams (48.3 solo -> 41.3 c2 -> 38.7 c4 @d0) while
# production's RISES (51.6 -> 67.3 -> 60.5). Sections to watch: wall-vs-gpu per
# call (scheduling bubbles), gather_a/gather_b (RoCE), kda/mla (attention over
# depth), dense/router/routed (the MoE path), mtp (the drafter).
# ---------------------------------------------------------------------------
if want prof && ! phase_done prof; then
  log "=== prof (TF_GLM_PROF=1, the concurrency diagnosis)"
  P="$OUT/03e-prof.md"; : > "$P"
  echo "# prof (TF_GLM_PROF=1, dense4fp8 + fp8 KV + 524288, PARALLEL=4)" >> "$P"
  restart_fb DENSE_BITS=4 HEAD_BITS=4 KV_CACHE=fp8 CONTEXT=524288 PARALLEL=4 TF_GLM_PROF=1
  python3 - "$OUT" "$FILL_WORDS" <<'EOF'
import json, random, sys
words, seed = sys.argv[2].split(), 4242
for tag, depth in (("d0", 0), ("d4096", 4096)):
    random.seed(seed + depth)
    n = depth // 4
    body = " ".join(words[i % len(words)] + (f"-{i%89}" if i % 13 == 0 else "") for i in range(n))
    q = "Write a 300-word technical summary of a harbor crane's maintenance cycle. Do not use any formatting."
    prompt = q if depth == 0 else body + "\n\n" + q
    for variant in ("solo", "c4"):
        json.dump({"model": "GLM-5.3-Flash-EXL3",
                   "messages": [{"role": "user", "content": prompt}],
                   "temperature": 0, "max_tokens": 2048},
                  open(f"{sys.argv[1]}/prof-{variant}-{tag}-req.json", "w"))
EOF
  curl -s -m 10 "http://127.0.0.1:$PORT/health" > "$OUT/prof-health-before.json" || true
  for variant in solo c4; do
    for tag in d0 d4096; do
      START=$(date +%s.%N)
      if [[ "$variant" == solo ]]; then
        chat "$OUT/prof-solo-$tag-req.json" > "$OUT/prof-solo-$tag-resp.json" || true
      else
        for i in 1 2 3 4; do { chat "$OUT/prof-c4-$tag-req.json" > "$OUT/prof-c4-$tag-$i.json" || true; } & done; wait
      fi
      ELAPSED=$(python3 -c "print(f'{$(date +%s.%N)-$START:.2f}')")
      echo "$variant $tag $ELAPSED" >> "$OUT/prof-walls.txt"
      log "prof probe $variant $tag done (${ELAPSED}s)"
    done
  done
  curl -s -m 10 "http://127.0.0.1:$PORT/health" > "$OUT/prof-health-after.json" || true
  python3 - "$OUT" >> "$P" <<'EOF'
import glob, json, sys
out = sys.argv[1]
walls = {}
for line in open(f"{out}/prof-walls.txt"):
    v, tag, t = line.split()
    walls[f"{v} {tag}"] = float(t)
for variant in ("solo", "c4"):
    for tag in ("d0", "d4096"):
        total = 0
        for f in glob.glob(f"{out}/prof-{variant}-{tag}-resp*.json") or glob.glob(f"{out}/prof-{variant}-{tag}-[0-9]*.json"):
            try: total += json.load(open(f))["usage"]["completion_tokens"]
            except Exception: pass
        t = walls.get(f"{variant} {tag}", 0)
        rate = f"{total/t:,.1f} tok/s aggregate" if t > 0 and total else "rate n/a"
        print(f"- {variant} {tag}: {t:.1f}s wall, {total} completion tokens -> {rate}")
try:
    b = json.load(open(f"{out}/prof-health-before.json")); a = json.load(open(f"{out}/prof-health-after.json"))
    for k in ("drafted", "accepted", "rounds"):
        if isinstance(b, dict) and k in b: print(f"- health {k}: {b.get(k)} -> {a.get(k)}")
except Exception as e:
    print(f"- health delta unavailable: {e}")
EOF
  echo "## head prof lines (per draft-window section averages, ms/call)" >> "$P"
  docker logs "$CONTAINER_NAME" 2>&1 | grep "glm prof" | tail -24 >> "$P" || true
  echo "## worker prof lines" >> "$P"
  ssh -o BatchMode=yes "$WORKER" "docker logs $CONTAINER_NAME 2>&1 | grep 'glm prof' | tail -24" >> "$P" 2>/dev/null || true
  touch "$OUT/.prof.done"
fi

# ---------------------------------------------------------------------------
# phase: depth — the forum-taught gate: fact+needle probes at 8k/64k/192k/384k
# ---------------------------------------------------------------------------
if want depth && ! phase_done depth; then
  log "=== depth"
  P="$OUT/04-depth.md"; : > "$P"
  echo "# depth gate (the STANDING config: dense4fp8 + TF_GLM_INDEX_CUDA=1 + vision, 524288x4; community bar: production 93.9%)" >> "$P"
  echo "- references: the v1.1.6-era receipt 12/12 (campaign-20261027-124115, the top4cfg re-qual); this run re-qualifies the current default end to end" >> "$P"
  restart
  python3 - "$OUT" "$FILL_WORDS" <<'EOF'
import json, random, sys
out, words, seed = sys.argv[1], sys.argv[2].split(), 987
facts = [("the loading-bay access code", "XJ-4821"),
         ("the maintenance vendor's name", "Ostergaard"),
         ("the coolant batch number", "B-2214-C"),
         ("the inspection due date", "March 3rd")]
for depth in (8000, 64000, 192000, 384000):
    random.seed(seed + depth)
    n = depth // 4                      # ~4 chars/token with the trailing spaces
    body = []
    anchor = (n * 3) // 5               # facts sit ~60% deep, as in grown sessions
    for i in range(n):
        body.append(words[i % len(words)] + (f"-{i%89}" if i % 13 == 0 else ""))
        if i == anchor:
            for j, (q, a) in enumerate(facts[:3]):
                body.append(f" Record {j}: {q} is {a}. ")
    prompt = " ".join(body) + (
        "\n\nFrom the records above, answer in one line each:\n"
        + "\n".join(f"{j+1}. What is {q}?" for j, (q, _) in enumerate(facts[:3]))
        + "\nAnswer with the three values only."
    )
    json.dump({"model": "GLM-5.3-Flash-EXL3",
               "messages": [{"role": "user", "content": prompt}],
               "temperature": 0, "max_tokens": 512}, open(f"{out}/depth-{depth}-req.json", "w"))
    json.dump(facts[:3], open(f"{out}/depth-{depth}-facts.json", "w"))
EOF
  for depth in 8000 64000 192000 384000; do
    log "depth probe at $depth"
    chat "$OUT/depth-$depth-req.json" > "$OUT/depth-$depth-resp.json" || true
    C=$(content_of "$OUT/depth-$depth-resp.json" 2>/dev/null || echo "")
    HITS=0; TOTAL=0
    while IFS= read -r ans; do
      TOTAL=$((TOTAL+1)); [[ "$C" == *"$ans"* ]] && HITS=$((HITS+1))
    done < <(python3 -c 'import json,sys; print("\n".join(a for _,a in json.load(open(sys.argv[1]))))' "$OUT/depth-$depth-facts.json")
    echo "- depth $depth: $HITS/$TOTAL facts retrieved" >> "$P"
  done
  touch "$OUT/.depth.done"
fi

# ---------------------------------------------------------------------------
# phase: cliff — 4-stream decode with vs without one structured-output request
# ---------------------------------------------------------------------------
if want cliff && ! phase_done cliff; then
  log "=== cliff"
  P="$OUT/05-cliff.md"; : > "$P"
  echo "# concurrency cliff: one structured request in the batch (MaTeZZ's mechanism)" >> "$P"
  python3 - "$OUT" <<'EOF'
import json, sys
plain = {"model": "GLM-5.3-Flash-EXL3",
         "messages": [{"role": "user", "content": "Write a 200-word technical description of a harbor crane. Do not use any formatting."}],
         "temperature": 0, "max_tokens": 256}
json.dump(plain, open(f"{sys.argv[1]}/cliff-plain.json", "w"))
schema = dict(plain)
schema["response_format"] = {"type": "json_schema", "json_schema": {
    "name": "crane", "strict": True,
    "schema": {"type": "object", "properties": {"description": {"type": "string"}},
               "required": ["description"], "additionalProperties": False}}}
json.dump(schema, open(f"{sys.argv[1]}/cliff-schema.json", "w"))
EOF
  for variant in plain schema; do
    START=$(date +%s.%N)
    for i in 1 2 3 4; do
      if [[ "$variant" == schema && $i -eq 4 ]]; then F="$OUT/cliff-schema.json"; else F="$OUT/cliff-plain.json"; fi
      { chat "$F" > "$OUT/cliff-$variant-$i.json" || true; } &
    done; wait
    ELAPSED=$(python3 -c "print(f'{$(date +%s.%N)-$START:.1f}')")
    echo "- batch of 4 with one $variant request: ${ELAPSED}s wall for 4x256 tokens" >> "$P"
  done
  echo "- verdict: if the schema batch is much slower, the structured-request draft-truncation cliff exists here too" >> "$P"
  touch "$OUT/.cliff.done"
fi

# ---------------------------------------------------------------------------
# phase: prefill — corrected probe 3 (~14k tokens)
# ---------------------------------------------------------------------------
if want prefill && ! phase_done prefill; then
  log "=== prefill"
  P="$OUT/06-prefill.md"; : > "$P"
  # this phase only probes — make sure a server is actually up (the climb phase may
  # have ended on a refusal with the stack down)
  curl -s -m 5 "http://127.0.0.1:$PORT/health" >/dev/null 2>&1 || \
    restart_fb DENSE_BITS=4 HEAD_BITS=4 KV_CACHE=fp8 CONTEXT=524288 PARALLEL=4
  python3 - "$OUT" "$FILL_WORDS" <<'EOF'
import json, sys
words, n = sys.argv[2].split(), 14000
body = " ".join(words[i % len(words)] + (f"-{i%83}" if i % 17 == 0 else "") for i in range(n))
json.dump({"model": "GLM-5.3-Flash-EXL3",
           "messages": [{"role": "user", "content": body + "\n\nReply with exactly: read complete."}],
           "temperature": 0, "max_tokens": 1}, open(f"{sys.argv[1]}/prefill-req.json", "w"))
EOF
  T=$(curl -s -o "$OUT/prefill-resp.json" -m 900 -w '%{time_total}' \
        "http://127.0.0.1:$PORT/v1/chat/completions" \
        -H 'Content-Type: application/json' --data @"$OUT/prefill-req.json") || true
  python3 - "$OUT/prefill-resp.json" "${T:-0}" >> "$P" <<'EOF'
import json, sys
try:
    u = json.load(open(sys.argv[1]))["usage"]
    pt = u.get("prompt_tokens") or 0
    t = float(sys.argv[2] or 0)
    rate = f" = {pt/t:,.0f} tok/s prefill" if t > 0.5 and pt else ""
    print(f"- usage: {pt:,} prompt tokens; wall {t:.1f}s (max_tokens=1, so wall is prefill + one decode step){rate}")
    print(f"- cached: {u.get('prompt_tokens_details')}")
except Exception as e:
    print(f"- prefill probe failed to parse: {e} (curl wall {sys.argv[2]}s)")
EOF
  echo "- compare with the v1.1.0 ~625 t/s and the pp2048 cells (~1,030 t/s) in TOOL_EVAL_TESTING.md" >> "$P"
  touch "$OUT/.prefill.done"
fi

# ---------------------------------------------------------------------------
# phase: rung — the 524288x1 goal rung
# ---------------------------------------------------------------------------
if want rung && ! phase_done rung; then
  log "=== rung 524288x1"
  P="$OUT/07-rung.md"; : > "$P"
  echo "# 524288 x PARALLEL=1 (the goal rung; production-parity window)" >> "$P"
  restart DENSE_BITS=8 HEAD_BITS=8 KV_CACHE=fp8 CONTEXT=524288 PARALLEL=1
  echo "- server: $(serve_line)" >> "$P"; echo "- $(roce_state)" >> "$P"
  chat "$OUT/depth-8000-req.json" > "$OUT/rung-probe.json" || true
  C=$(content_of "$OUT/rung-probe.json" 2>/dev/null || echo "")
  HITS=0
  while IFS= read -r ans; do [[ "$C" == *"$ans"* ]] && HITS=$((HITS+1)); done \
    < <(python3 -c 'import json,sys; print("\n".join(a for _,a in json.load(open(sys.argv[1]))))' "$OUT/depth-8000-facts.json")
  echo "- 8k-depth probe at the rung: $HITS/3 facts retrieved" >> "$P"
  touch "$OUT/.rung.done"
fi

# (the bpw4sweep/bpw3sweep session phases RETIRED round 132 — the 4bpw sweep
# receipted (TR3 94 / MIA 94 / Focus 93 / AZ 90 — docs/bpw4-sweep-cards.svg, the
# receipts in results/bpw4sweep/) and the 3bpw track CLOSED on the engine's 4-bit
# expert floor: the CUDA family reads 4-bit EXL3 experts — all three community
# packs refused (UnsupportedQuant). Re-run patterns: git history.

# (the postbump phase RETIRED round 133 (cont. 7) — the verdicts: the
# deep-prefill curve LINEAR at ~0.785 ms/tok, reproduced twice (33.7/66.9/133.4
# s at 42k/85k/170k; the re-run delta < 0.5%); glm-tail-release RETIRED (the
# no-patch serve byte-identical on memory AND speed — 14.1 GiB left, 68.8 s at
# 87.4k); TF_GLM_KV_HOST non-viable on our shape (refused on fp8 by design —
# the engine names pages+bf16 — and every request timed out on bf16+pages).
# Receipts: results/postbump/. Re-run patterns: git history.)
# (the deepdelta phase RETIRED round 133 (cont. 9) — the receipt: the #1577
# deep delta is −2.6 to −3.5% at 50k-204k fills (v1.2.2 uniformly faster, both
# curves linear at 0.79 vs 0.81 ms/tok) — the low end of the 5-14% claim (that
# was TP=3; we are TP=2). The identical-fill comparison is self-consistent
# (both legs' prompt_tokens match exactly). Receipts: results/deepdelta/.
# Re-run patterns: git history.)






# ---------------------------------------------------------------------------
# phase: duel — the sharp, short head-to-head. The SAME probes on production
# (read-only, run first while production is up) and on our stack (after one
# restart). Five instruments, ~4 min per engine, every number a direct
# measurement of the thing it names — no bench rows, no derivation:
#   1. solo decode rate, TWICE (the stability test): greedy, 2048 tokens,
#      completion/wall — the pair's delta is the instrument's noise floor;
#   2. inter-token latency from the SSE stream (per-chunk mean/p50/p95 — the
#      decode rhythm, where the drafter's accept/verify pattern shows);
#   3. prefill slope: max_tokens=1 at d0/d4096/d8192 — the d0 TTFT is the fixed
#      overhead, the deltas give ms/token of prefill;
#   4. the drafter's acceptance counters from /health (deltas around the decode
#      pair): drafted/accepted/rounds;
#   5. c2/c4 aggregate decode (the honest concurrency instrument, measured —
#      not derived — on both engines).
# Production arm skipped with a note when production is down; the handover
# prompt follows the duel's production-arm pattern when it is up.
# ---------------------------------------------------------------------------
if want duel && ! phase_done duel; then
  log "=== duel (the sharp head-to-head: the baseline arm first, then ours)"
  P="$OUT/07-duel.md"; : > "$P"
  echo "# duel (five direct instruments, same probes on both engines; no bench rows)" >> "$P"

  # NATIVE-vs-NATIVE (the round-139 (user) directive): the Python recipe is retired —
  # the baseline arm is THIS REPO's own promoted config, started FOR TESTING on 8001
  # (the intent-keyed start; the promoted repo IS the baseline arm now). The
  # candidate arm ("ours") carries the campaign's PATCHES (the standing stack by
  # default; MMS2_DUEL_PATCHES overrides — the candidate-duel pattern).
  # The failure shape the round-139 void fixed: the ours arm's restart happens ONLY
  # after the baseline arm's stop, and a restart failure DIES the phase — the two
  # arms must never share 8001, and a dead arm can never fall through silently
  # (the round-139 void: the duel started the baseline on 8001, then restarted the
  # ours arm WITHOUT stopping the baseline first — the round-132 port guard refused,
  # the phase fell through, the baseline sat idle on both GPUs, and the window's
  # docker-stop-then-die killed the wrapper before its EXIT trap).
  log "duel: stopping the testing stack to free 8001"
  ./scripts/stop.sh </dev/null >/dev/null 2>&1 || true
  log "duel: the baseline arm (the promoted config) starting FOR TESTING on 8001"
  PORT=8001 ./scripts/start.sh </dev/null >>"$LOG" 2>&1 || {
    echo "- the baseline arm refused to start on 8001 — its refusal is the receipt; the duel is void" >> "$P"
    touch "$OUT/.duel.done"
    log "duel: the baseline arm refused — phase void (fail-honest)"
    exit 0
  }
  BASE_MODEL=$(curl -s -m 10 "http://127.0.0.1:8001/v1/models" | python3 -c '
import json, sys
try: print(json.load(sys.stdin)["data"][0]["id"])
except Exception: print("")') || BASE_MODEL=""
  BASE_MODEL="${BASE_MODEL:-$SERVED_NAME}"
  echo "## baseline (the promoted config, read-only on the testing port 8001; model $BASE_MODEL)" >> "$P"
  PROD_PORT_SAVE="$PROD_PORT"
  PROD_PORT=8001 duel_arm baseline "$BASE_MODEL"
  PROD_PORT="$PROD_PORT_SAVE"
  log "baseline probed — stopping it for the ours arm (restored by the window flow's exit path)"
  ./scripts/stop.sh </dev/null >/dev/null 2>&1 || true
  if docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    die "the baseline arm still runs after the stop — the ours arm needs the GPUs"
  fi
  # the ours arm rides the STANDING config's stack unless a candidate overrides it
  # (MMS2_DUEL_PATCHES — the candidate-duel pattern; a standalone duel launch has it
  # unset, and the bare ${MMS2_DUEL_PATCHES-} expanded to the EMPTY opt-out list —
  # the stock build refused the adopted fp8+pages mode and the first v1.2.4 duel
  # re-pair burned on exactly that, campaign-20261107-160107).
  restart DENSE_BITS=4 HEAD_BITS=4 KV_CACHE=fp8 CONTEXT=524288 PARALLEL=4 PATCHES="${MMS2_DUEL_PATCHES-${PATCHES-}}" || {
    echo "- the ours arm refused to start — the duel is void (fail-honest; the baseline arm is stopped, production comes back on the exit path)" >> "$P"
    touch "$OUT/.duel.done"
    log "duel: the ours arm refused — phase void (fail-honest)"
    exit 0
  }
  echo "## ours (dense4fp8 @ 512K x4${MMS2_DUEL_PATCHES:+, the MMS2_DUEL_PATCHES candidate}; ${MMS2_DUEL_PATCHES:-the standing stack})" >> "$P"
  duel_arm ours "$SERVED_NAME"
  touch "$OUT/.duel.done"
fi

# ---------------------------------------------------------------------------
# phase: confirm — the knob sweep's one sharp lead, reproduced or retired:
# TF_GLM_PROMPT_STEPS=0 took c2 @ d8192 aggregate 17.3 → 33.1 t/s (1.9×) in
# campaign-20261023-200302 on a row that is tight across five rounds. Two
# independent restarts + benches decide; the receipt prints the comparison
# against the dense4fp8 baseline explicitly.
# ---------------------------------------------------------------------------
if want confirm && ! phase_done confirm; then
  log "=== confirm (steps0 twice: does the 1.9x c2@d8192 lead reproduce?)"
  P="$OUT/08-confirm.md"; : > "$P"
  echo "# confirm (TF_GLM_PROMPT_STEPS=0, dense4fp8 @ 512K x4; two independent restarts)" >> "$P"
  echo "- the lead being tested: c2 @ d8192 aggregate 17.3 → 33.1 t/s (campaign-20261023-200302)" >> "$P"
  for r in a b; do
    S=$(date +%s)
    if restart DENSE_BITS=4 HEAD_BITS=4 KV_CACHE=fp8 CONTEXT=524288 PARALLEL=4 TF_GLM_PROMPT_STEPS=0; then
      echo "## run $r (load $(( $(date +%s) - S )) s)" >> "$P"
      bench_perf "confirm-$r" "$OUT/confirm-$r" 4 >> "$P"
    else
      echo "## run $r — refused to start" >> "$P"
      docker logs "$CONTAINER_NAME" 2>&1 | tail -2 >> "$P"
    fi
  done
  python3 - "$OUT" >> "$P" <<'PYEOF'
import glob, sys
out = sys.argv[1]
rows = {}
for f in sorted(glob.glob(f"{out}/confirm-*/2026/*/*/*.md")):
    run = f.split("/confirm-")[1].split("/")[0]
    for line in open(f):
        for probe in ("| pp2048 tg128 @ d0 |", "| pp2048 tg128 @ d8192 c2 |", "| pp2048 tg128 @ d8192 c4 |", "| pp2048 tg128 @ d4096 c2 |"):
            if line.startswith(probe):
                cells = [c.strip() for c in line.split("|")[1:-1]]
                rows[f"{run} {probe.replace('| pp2048 tg128 @','').strip()}"] = cells[1]
for k in sorted(rows):
    print(f"- {k}: tg {rows[k]} t/s")
print("- baseline (dense4fp8 receipts): d0 49.9; d4096 c2 24.0; d8192 c2 17.3; d8192 c4 13.3")
print("- the lead reproduces if d8192 c2 lands near 33 again; near 17 retires it")
PYEOF
  touch "$OUT/.confirm.done"
fi
# ---------------------------------------------------------------------------

# phase: cachefixqual (SESSION-SPECIFIC; retires with the receipt). The #2699
# recovery A/B: the v1.2.6 pool plan funds ZERO of the 16 TF_KV_SHARE kept
# states. slots at the standing config (v1.2.5 funded 2) — the bigger fixed
# parts (#2257: window_rows 8 -> 32 moved the KDA projection into each stream,
# +51 MiB/stream) ate the slots' room. The serve line names the fix:
# --prompt-cache-gib 4 holds all 16. The battery: the OFF arm (the standing
# config: no prompt cache) vs the ON arm (--prompt-cache-gib 4). The
# PLACED-flag witnesses (window 33's ON arm was a PLACEBO — its env name was
# doubled, PROMPT_PROMPT_CACHE_GIB, and nothing read it; the OFF-vs-ON
# comparison measured room drift on two identical cacheless serves): the
# container argv must carry --prompt-cache-gib 4, the serve line must print
# the fully-funded phrasing "16 kept states' slots" (no "of TF_KV_SHARE=" and
# no advice tail), and the room-funds clip report must be ABSENT. The
# turn-1/turn-2 walls are REFERENCE only (window 33's lesson: a follow-up
# turn re-prefills its longer history — the walls measure re-prefill, not
# resume; g3 + the funded-slots line are the resume witnesses). The §2
# content gates + hardmode 95 + the vision 4/4 + the greedy same-bits sha
# guard the ON arm, and the bench + steady-state decode (the pool pages the
# ON arm cedes must not move the decode cells outside the bands), and the ON
# arm must keep its third 524288 window (the cache_first reserve must not eat
# it). Adoption moves config.sh's PROMPT_CACHE_GIB default.
# ---------------------------------------------------------------------------
if want cachefixqual && ! phase_done cachefixqual; then
  log "=== cachefixqual (the #2699 recovery: --prompt-cache-gib 4 vs the cacheless standing)"
  P="$OUT/11-cachefixqual.md"; : > "$P"
  echo "# cachefixqual (the #2699 recovery: the standing cacheless config vs --prompt-cache-gib 4; dense4fp8 @ 512K x4 on the testing port)" >> "$P"
  for arm in off on; do
    S=$(date +%s)
    if [ "$arm" = on ]; then CFENV="PROMPT_CACHE_GIB=4"; else CFENV=""; fi
    if restart DENSE_BITS=4 HEAD_BITS=4 KV_CACHE=fp8 CONTEXT=524288 PARALLEL=4 $CFENV; then
      echo "## the $arm arm (load $(( $(date +%s) - S )) s)" >> "$P"
      # the PLACED-flag witness (window 33's placebo lesson): the container argv
      # itself must carry --prompt-cache-gib 4 — the serve line's advice tail
      # ("--prompt-cache-gib 4 holds all 16") prints regardless and proves nothing.
      # Guards (window 34's lesson): every grep in an assignment is guarded — a
      # bare grep at a pipeline's end exits 1 on no-match and set -e kills the phase.
      argv_flags=$(docker inspect --format "{{.Config.Cmd}}" "$CONTAINER_NAME" 2>/dev/null | tr " " "\n" | { grep -A1 "^--prompt-cache-gib$" || true; } | tail -1)
      if [ "$arm" = on ]; then
        if [ "$argv_flags" = "4" ]; then
          echo "- the argv witness: --prompt-cache-gib 4 PLACED" >> "$P"
        else
          echo "- the argv witness: FAILED (the container runs WITHOUT --prompt-cache-gib; argv tail: ${argv_flags:-absent})" >> "$P"
        fi
      else
        echo "- the argv witness: the flag absent as intended (${argv_flags:-absent})" >> "$P"
      fi
      echo "- the serve line: $(serve_line | grep -oE "taking [0-9]+ pages of 512 rows \\([0-9.]+ GiB\\)|no prompt cache[^;]*|[0-9]+ of TF_KV_SHARE=[0-9]+ kept states[^;]*|[0-9]+ kept states. slots[^;]*)" | head -2)" >> "$P"
      echo "- the serve line full: $(serve_line)" >> "$P"
      docker logs "$CONTAINER_NAME" 2>&1 | grep -E "prompt cache|kept states" | tail -2 >> "$P" || true
      # the funded witness: the fully-funded phrasing has NO "of TF_KV_SHARE=" and
      # no advice tail; the clip report ("the room funds ... of the ... asks")
      # appears only when the room does not fund the full ask (cuda_kv_pool.zig:183).
      if [ "$arm" = on ]; then
        if docker logs "$CONTAINER_NAME" 2>&1 | grep -q "the room funds"; then
          echo "- the clip report: PRESENT (the room did not fund the full 4 GiB ask — a budget clip, not a placebo)" >> "$P"
        else
          echo "- the clip report: ABSENT (the room funded the ask or no cache asked)" >> "$P"
        fi
      fi
      docker logs "$CONTAINER_NAME" 2>&1 | { grep -c "enough for 3 at a 524288" || true; } | sed "s/^/- the third-512K-window witness (1 expected): /" >> "$P"
      # the greedy witness (the same-bits guard):
      req_file "$OUT/cx-$arm-req.json" "$REF_PROMPT" '{"max_tokens": 1024}'
      chat "$OUT/cx-$arm-req.json" > "$OUT/cx-$arm-resp.json" || true
      echo "- the greedy content sha: $(content_sha "$OUT/cx-$arm-resp.json")" >> "$P"
      # the warm-resume instrument, RELABELED reference-only (window 33's lesson:
      # turn 2 re-prefills its longer history, so its wall is HIGHER than turn 1's
      # by construction — the walls measure re-prefill, not resume). The resume
      # witnesses are g3 (resumed=fresh content) and the funded-slots line.
      C1=$(python3 -c "
import json, sys
print(json.dumps({'model': sys.argv[1], 'messages': [{'role': 'user', 'content': 'Remember this code word: AXIOM-4431. Reply with just the word.'}], 'max_tokens': 256, 'temperature': 0, 'seed': 7}))" "$SERVED_NAME")
      echo "$C1" > "$OUT/cx-$arm-turn1-req.json"
      T1S=$(date +%s%3N)
      chat "$OUT/cx-$arm-turn1-req.json" > "$OUT/cx-$arm-turn1.json" || true
      T1E=$(date +%s%3N)
      C2=$(python3 -c "
import json, sys
print(json.dumps({'model': sys.argv[1], 'messages': [{'role': 'user', 'content': 'Remember this code word: AXIOM-4431. Reply with just the word.'}, {'role': 'assistant', 'content': 'AXIOM-4431'}, {'role': 'user', 'content': 'What code word did I give you? Reply with just the word.'}], 'max_tokens': 256, 'temperature': 0, 'seed': 7}))" "$SERVED_NAME")
      echo "$C2" > "$OUT/cx-$arm-turn2-req.json"
      T2S=$(date +%s%3N)
      chat "$OUT/cx-$arm-turn2-req.json" > "$OUT/cx-$arm-turn2.json" || true
      T2E=$(date +%s%3N)
      # THE VALUE INSTRUMENTS (the discipline layer, window 35 on): the question
      # is not "did the slots fund" (compliance) but "did the kept states move a
      # user-visible number" (value). Two instruments, run on THIS arm's serve
      # while it stands:
      # (v1) the within-session resume delta: the g3-shaped conversation computed
      #      twice (cold then immediate) — its wall delta IS the page-cache value
      #      already present cacheless; the ON arm must BEAT the OFF arm's delta.
      # (v2) the multi-turn TTFT: a ~4k-token fill, turn 2 (a follow-up on the
      #      kept history) vs turn 1 — the opencode interaction shape.
      # The anchors: cross-restart resume is COLD cacheless (7.25 s) and the
      # imprint disk path is OFF in the standing config (checked round 140
      # cont. 5) — out of scope here; a --learn question if the within-session
      # value fails.
      V1CONV="$OUT/cx-$arm-v1-conv.json"
      SERVED_MODEL="$SERVED_NAME" python3 - "$V1CONV" <<'PYV'
import json, os, sys
conv = {"model": os.environ["SERVED_MODEL"], "temperature": 0, "max_tokens": 1024,
        "messages": [{"role": "user", "content": "Remember these three codes: alpha-7391, bravo-2250, charlie-8118. Reply with exactly: codes noted."}]}
json.dump(conv, open(sys.argv[1], "w"))
PYV
      rm -f "$OUT/cx-$arm-v1-walls.txt"
      for r in cold warm; do
        S=$(date +%s%3N); curl -s -m 300 "http://127.0.0.1:$PORT/v1/chat/completions" -H 'Content-Type: application/json' --data @"$V1CONV" -o "$OUT/cx-$arm-v1-$r.json" || true; E=$(date +%s%3N)
        echo "$r $((E-S))" >> "$OUT/cx-$arm-v1-walls.txt"
      done
      python3 - "$OUT" "$arm" >> "$P" <<'PYV'
import json, sys
out, arm = sys.argv[1], sys.argv[2]
w = {}
for line in open(f"{out}/cx-{arm}-v1-walls.txt"):
    k, v = line.split(); w[k] = int(v)
try:
    a = json.load(open(f"{out}/cx-{arm}-v1-cold.json"))["choices"][0]["message"]["content"]
    b = json.load(open(f"{out}/cx-{arm}-v1-warm.json"))["choices"][0]["message"]["content"]
    same = "yes" if a == b else "NO"
except Exception as e:
    same = f"unreadable ({e})"
d = w.get("cold", 0) - w.get("warm", 0)
print("- (v1) %s arm within-session resume: cold %d ms, warm %d ms, delta %d ms; content same: %s" % (arm, w.get("cold", 0), w.get("warm", 0), d, same))
PYV
      SERVED_MODEL="$SERVED_NAME" python3 - "$OUT" "$arm" <<'PYV'
import json, os, sys
out, arm = sys.argv[1], sys.argv[2]
fill = " ".join(f"harbor-{i%89}" for i in range(900))
common = {"model": os.environ["SERVED_MODEL"], "temperature": 0, "max_tokens": 1024}
t1 = dict(common, messages=[{"role": "user", "content": fill + "\n\nSummarize the passage in two sentences."}])
t2 = dict(common, messages=[{"role": "user", "content": fill + "\n\nSummarize the passage in two sentences."},
                            {"role": "assistant", "content": "The passage catalogues harbor terms."},
                            {"role": "user", "content": "Name the first three terms you saw, comma separated."}])
json.dump(t1, open(f"{out}/cx-{arm}-v2-t1.json", "w"))
json.dump(t2, open(f"{out}/cx-{arm}-v2-t2.json", "w"))
PYV
      rm -f "$OUT/cx-$arm-v2-walls.txt"
      for r in t1 t2; do
        S=$(date +%s%3N); curl -s -m 300 "http://127.0.0.1:$PORT/v1/chat/completions" -H 'Content-Type: application/json' --data @"$OUT/cx-$arm-v2-$r.json" -o "$OUT/cx-$arm-v2-$r-resp.json" || true; E=$(date +%s%3N)
        echo "$r $((E-S))" >> "$OUT/cx-$arm-v2-walls.txt"
      done
      python3 - "$OUT" "$arm" >> "$P" <<'PYV'
import json, sys
out, arm = sys.argv[1], sys.argv[2]
w = {}
for line in open(f"{out}/cx-{arm}-v2-walls.txt"):
    k, v = line.split(); w[k] = int(v)
d = w.get("t1", 0) - w.get("t2", 0)
print("- (v2) %s arm multi-turn TTFT: turn1 %d ms, turn2 %d ms, turn-2 saves %d ms" % (arm, w.get("t1", 0), w.get("t2", 0), d))
PYV
      python3 -c "
import json
t1 = json.load(open('$OUT/cx-$arm-turn1.json'))
t2 = json.load(open('$OUT/cx-$arm-turn2.json'))
c1 = t1['choices'][0]['message']['content']
c2 = t2['choices'][0]['message']['content']
print('- turn 1 wall: %d ms; turn 2 wall: %d ms; turn-2 content: %r (AXIOM-4431 expected); the turn-2 content correctness is the cache-resume witness' % ($T1E - $T1S, $T2E - $T2S, c2.strip()[:40]))
print('- turn 1 prompt tokens: %s, completion: %s' % (t1["usage"]["prompt_tokens"], t1["usage"]["completion_tokens"]))
print('- turn 2 prompt tokens: %s (the full history re-prefilled unless the cache resumed), completion: %s' % (t2["usage"]["prompt_tokens"], t2["usage"]["completion_tokens"]))
" >> "$P" || true
    else
      echo "## the $arm arm — REFUSED" >> "$P"; tail -4 "$LOG" | sed 's/^/  /' >> "$P"
    fi
  done
  echo "## the §2 content gates (the ON arm's serve stands)" >> "$P"
  restart DENSE_BITS=4 HEAD_BITS=4 KV_CACHE=fp8 CONTEXT=524288 PARALLEL=4 PROMPT_CACHE_GIB=4 || true
  run_gates cx DENSE_BITS=4 HEAD_BITS=4 KV_CACHE=fp8 CONTEXT=524288 PROMPT_CACHE_GIB=4 || true
  echo "## hardmode (the 95 must hold, the ON arm's serve)" >> "$P"
  mkdir -p "$OUT/cxhm"
  model=$(curl -s -m 10 "http://127.0.0.1:$PORT/v1/models" | python3 -c '
import json, sys
try: print(json.load(sys.stdin)["data"][0]["id"])
except Exception: print("")' 2>/dev/null) || model=""
  PYTHONUNBUFFERED=1 "$BENCH" run --base-url "http://127.0.0.1:$PORT" \
    --model "$model" --format openai --tokenizer "$MODEL_ID" \
    --hardmode --label "cachefixqual" --output-dir "$OUT/cxhm" --parallel 2 \
    --json-file "$OUT/cxhm/hm.json" > "$OUT/cxhm/hm.log" 2>&1 || true
  grep -o '"final_score": [0-9]*' "$OUT/cxhm/hm.json" >> "$P" 2>/dev/null || true
  grep -o '"scenario_id": "TC-51", "status": "[a-z]*"' "$OUT/cxhm/hm.log" >> "$P" 2>/dev/null || true
  grep -o '"scenario_id": "TC-92", "status": "[a-z]*"' "$OUT/cxhm/hm.log" >> "$P" 2>/dev/null || true
  echo "## the vision suite (4/4 must hold)" >> "$P"
  mkdir -p "$OUT/cxvision"
  if [ -f scripts/vision-suite-probe.py ]; then
    python3 scripts/vision-suite-probe.py "http://127.0.0.1:$PORT" "$OUT/cxvision/vision.json" > "$OUT/cxvision/vision.log" 2>&1 || true
    tail -6 "$OUT/cxvision/vision.log" >> "$P" 2>/dev/null || true
  else
    echo "- the vision-suite runner is MISSING at scripts/vision-suite-probe.py" >> "$P"
  fi
  echo "## the regression watch (the bench + steady-state on the ON arm's serve)" >> "$P"
  bench_perf cx "$OUT/cx-bench" 4 >> "$P" 2>&1 || true
  bf=$(mktemp /tmp/cxd.XXXXXX.json)
  python3 -c "
import json, sys
print(json.dumps({'model': sys.argv[1], 'messages': [{'role': 'user', 'content': 'Write a 400-word essay about lighthouses.'}], 'max_tokens': 2048, 'temperature': 0, 'seed': 42}))" "$SERVED_NAME" > "$bf"
  model=$(curl -s -m 10 "http://127.0.0.1:$PORT/v1/models" | python3 -c '
import json, sys
try: print(json.load(sys.stdin)["data"][0]["id"])
except Exception: print("")' 2>/dev/null) || model=""
  python3 -c "import json,sys; b=json.load(open(sys.argv[1])); b['model']=sys.argv[2]; json.dump(b, open(sys.argv[1],'w'))" "$bf" "$model"
  S=$(date +%s)
  curl -s -m 300 "http://127.0.0.1:$PORT/v1/chat/completions" -H 'Content-Type: application/json' --data @"$bf" -o "$OUT/cx-decode.json" || true
  W=$(( $(date +%s) - S )); rm -f "$bf"
  python3 -c "
import json
try:
    d = json.load(open('$OUT/cx-decode.json'))
    ct = d['usage']['completion_tokens']
    print('- steady-state decode: %d tokens in %d s = %.1f tok/s (wall incl. prefill)' % (ct, $W, ct / max($W, 1)))
except Exception as e:
    print('- the decode probe FAILED: ' + repr(e))
" >> "$P"
  echo "- VERDICT (VALUE-FIRST, window 35 on): QUALIFIED = the flag PLACED (the argv witness) AND the funded phrasing present AND (v1) the ON arm's warm-resume wall delta BEATS the OFF arm's by >150 ms (value, not compliance) AND g3 PASS AND hardmode 95 AND the vision 4/4 AND the decode bands hold AND the third 512K window kept => PROMPT_CACHE_GIB=4 becomes the config.sh default. Flag placed but no value delta => the cacheless standing HOLDS and the question CLOSES as upstream data (no third reshape). Any guard FAIL = the battery itself failed; the cacheless standing holds and the battery gets fixed before any re-run." >> "$P"
  touch "$OUT/.cachefixqual.done"
fi
# ---------------------------------------------------------------------------
# phase: livehalf (SESSION-SPECIFIC; retires with the receipt). The #2181
# live-half A/B: TF_GLM_KV_LIVE_HALF=1 makes a kept state hold the live KDA
# half alone — the keep ~30-35% smaller (upstream's own receipt at
# docs/receipts/glm-kv-live-half-555f052d in the v1.2.6 tree: the nine-turn
# greedy conversation content-identical across on/off/fresh/main, the drafts
# identical, TTFT flat, keeps 126 vs 194 MiB at state 1). Upstream's scope
# caveat: NOT qualified at TP=2 concurrent streams, paged sequences, the
# page-sharing store, or fp8 KV — our shape; this battery decides. The
# value-first question (the stage brief, round 141 cont. 3): does the knob
# fund ALL 16 TF_KV_SHARE kept-state slots CACHELESS — closing the standing
# config's eviction warning ("TF_KV_SHARE=16 keeps 6 states ... live streams
# evict each other's before a resume") — WITHOUT losing the third 512K
# window, the decode bands, or the §2 gates? The witnesses: the serve lines
# (the slots funded + the enough-for count + the warning's absence/presence),
# the greedy same-bits sha (the ON arm must not move the deterministic
# probes), the §2 content gates, hardmode 95, the vision 4/4, the bench +
# steady-state decode inside the bands. QUALIFIED = all 16 funded cacheless
# AND enough-for >= the OFF arm's AND every guard holds => TF_GLM_KV_LIVE_HALF=1
# becomes the config.sh default. Any guard fail or a smaller room => RETIRE,
# the standing config stays, the question closes as upstream data.
# ---------------------------------------------------------------------------
if want livehalf && ! phase_done livehalf; then
  log "=== livehalf (the #2181 live-half A/B: the standing config vs TF_GLM_KV_LIVE_HALF=1)"
  P="$OUT/12-livehalf.md"; : > "$P"
  echo "# livehalf (the #2181 live-half A/B: the standing cacheless config vs TF_GLM_KV_LIVE_HALF=1; dense4fp8 @ 512K x4 on the testing port)" >> "$P"
  for arm in off on; do
    if [ "$arm" = on ]; then LHENV="TF_GLM_KV_LIVE_HALF=1"; else LHENV=""; fi
    if restart DENSE_BITS=4 HEAD_BITS=4 KV_CACHE=fp8 CONTEXT=524288 PARALLEL=4 $LHENV; then
      echo "## the $arm arm" >> "$P"
      # the PLACED-flag witness (window 33's placebo lesson; window 36's argv
      # extraction lesson): the container argv must carry the flag as a
      # K=V env pair — inspect the Env array, not Cmd (the env var is how
      # the knob reaches the engine; the argv carries --prompt-cache-gib
      # class flags, TF_GLM_* rides the environment).
      argv_env=$(docker inspect --format "{{range .Config.Env}}{{println .}}{{end}}" "$CONTAINER_NAME" 2>/dev/null | { grep -c "^TF_GLM_KV_LIVE_HALF=1$" || true; })
      if [ "$arm" = on ]; then
        if [ "$argv_env" -ge 1 ] 2>/dev/null; then
          echo "- the env witness: TF_GLM_KV_LIVE_HALF=1 PLACED in the container env" >> "$P"
        else
          echo "- the env witness: FAILED (the container env lacks TF_GLM_KV_LIVE_HALF=1 — a placebo arm; nothing downstream counts)" >> "$P"
        fi
      else
        echo "- the env witness: the knob absent as intended" >> "$P"
      fi
      echo "- the serve line: $(serve_line)" >> "$P"
      # the slots + enough-for witnesses straight from the serve line
      echo "- the slots witness: $(serve_line | grep -oE "[0-9]+( of TF_KV_SHARE=16)? kept states. slots \([0-9.]+ GiB\)|no prompt cache")" >> "$P"
      echo "- the enough-for witness: $(serve_line | grep -oE "enough for [0-9]+ at a 524288")" >> "$P"
      # the eviction warning: the OFF arm's line carries it (6 of 16 funded);
      # the ON arm must NOT (all 16 funded) for the value gate to fire.
      if docker logs "$CONTAINER_NAME" 2>&1 | grep -q "live streams evict each other"; then
        echo "- the eviction warning: PRESENT (the standing shape — live streams evict before a resume)" >> "$P"
      else
        echo "- the eviction warning: ABSENT" >> "$P"
      fi
      # the greedy witness (the same-bits guard):
      req_file "$OUT/lh-$arm-req.json" "$REF_PROMPT" '{"max_tokens": 1024}'
      chat "$OUT/lh-$arm-req.json" > "$OUT/lh-$arm-resp.json" || true
      echo "- the greedy content sha: $(content_sha "$OUT/lh-$arm-resp.json")" >> "$P"
    else
      echo "## the $arm arm — REFUSED" >> "$P"; tail -4 "$LOG" | sed 's/^/  /' >> "$P"
    fi
  done
  echo "## the §2 content gates (the ON arm's serve stands)" >> "$P"
  restart DENSE_BITS=4 HEAD_BITS=4 KV_CACHE=fp8 CONTEXT=524288 PARALLEL=4 TF_GLM_KV_LIVE_HALF=1 || true
  run_gates lh DENSE_BITS=4 HEAD_BITS=4 KV_CACHE=fp8 CONTEXT=524288 TF_GLM_KV_LIVE_HALF=1 || true
  echo "## hardmode (the 95 must hold, the ON arm's serve)" >> "$P"
  mkdir -p "$OUT/lhhm"
  model=$(curl -s -m 10 "http://127.0.0.1:$PORT/v1/models" | python3 -c '
import json, sys
try: print(json.load(sys.stdin)["data"][0]["id"])
except Exception: print("")' 2>/dev/null) || model=""
  PYTHONUNBUFFERED=1 "$BENCH" run --base-url "http://127.0.0.1:$PORT" \
    --model "$model" --format openai --tokenizer "$MODEL_ID" \
    --hardmode --label "livehalf" --output-dir "$OUT/lhhm" --parallel 2 \
    --json-file "$OUT/lhhm/hm.json" > "$OUT/lhhm/hm.log" 2>&1 || true
  grep -o '"final_score": [0-9]*' "$OUT/lhhm/hm.json" >> "$P" 2>/dev/null || true
  grep -o '"scenario_id": "TC-51", "status": "[a-z]*"' "$OUT/lhhm/hm.log" >> "$P" 2>/dev/null || true
  grep -o '"scenario_id": "TC-92", "status": "[a-z]*"' "$OUT/lhhm/hm.log" >> "$P" 2>/dev/null || true
  echo "## the vision suite (4/4 must hold)" >> "$P"
  mkdir -p "$OUT/lhvision"
  if [ -f scripts/vision-suite-probe.py ]; then
    python3 scripts/vision-suite-probe.py "http://127.0.0.1:$PORT" "$OUT/lhvision/vision.json" > "$OUT/lhvision/vision.log" 2>&1 || true
    tail -6 "$OUT/lhvision/vision.log" >> "$P" 2>/dev/null || true
  else
    echo "- the vision-suite runner is MISSING at scripts/vision-suite-probe.py" >> "$P"
  fi
  echo "## the regression watch (the bench + steady-state on the ON arm's serve)" >> "$P"
  bench_perf lh "$OUT/lh-bench" 4 >> "$P" 2>&1 || true
  bf=$(mktemp /tmp/lh.XXXXXX.json)
  python3 -c "
import json, sys
print(json.dumps({'model': sys.argv[1], 'messages': [{'role': 'user', 'content': 'Write a 400-word essay about lighthouses.'}], 'max_tokens': 2048, 'temperature': 0, 'seed': 42}))" "$SERVED_NAME" > "$bf"
  model=$(curl -s -m 10 "http://127.0.0.1:$PORT/v1/models" | python3 -c '
import json, sys
try: print(json.load(sys.stdin)["data"][0]["id"])
except Exception: print("")' 2>/dev/null) || model=""
  python3 -c "import json,sys; b=json.load(open(sys.argv[1])); b['model']=sys.argv[2]; json.dump(b, open(sys.argv[1],'w'))" "$bf" "$model"
  S=$(date +%s)
  curl -s -m 300 "http://127.0.0.1:$PORT/v1/chat/completions" -H 'Content-Type: application/json' --data @"$bf" -o "$OUT/lh-decode.json" || true
  W=$(( $(date +%s) - S )); rm -f "$bf"
  python3 -c "
import json
try:
    d = json.load(open('$OUT/lh-decode.json'))
    ct = d['usage']['completion_tokens']
    print('- steady-state decode: %d tokens in %d s = %.1f tok/s (wall incl. prefill; the band: 70-76)' % (ct, $W, ct / max($W, 1)))
except Exception as e:
    print('- the decode probe FAILED: ' + repr(e))
" >> "$P"
  echo "- VERDICT (VALUE-FIRST, window 37 on): QUALIFIED = the env PLACED (the container-env witness) AND all 16 slots funded CACHELESS (the ON arm's serve line) AND the enough-for count >= the OFF arm's AND the eviction warning ABSENT on the ON arm AND the greedy sha == the standing 80cc3802… AND the §2 gates ALL PASS AND hardmode 95 AND the vision 4/4 AND the bench/decode bands hold => TF_GLM_KV_LIVE_HALF=1 becomes the config.sh default. Any witness/guard miss => RETIRE: the knob goes nowhere, the standing config stays, the question closes as upstream data (upstream's scope caveat stands: not qualified on our shape)." >> "$P"
  touch "$OUT/.livehalf.done"
fi
# ---------------------------------------------------------------------------
# phase: regresswatch (SESSION-SPECIFIC; retires with the receipt). The
# concurrent-resume regression watch on v1.2.6: the round-133 adoption
# receipted the concurrent 4-prefix resume at 4/4 cache hits, ttft ~1.84 s
# each, the aggregate ~7.4 s (kvshare2, campaign-20261106-092703) — on the
# v1.2.3 engine's pool plan. v1.2.6's #2257 changed the plan under that
# receipt (window_rows 8 -> 32, +51 MiB/stream fixed, 2 of the 16 TF_KV_SHARE
# slots eaten): window 37's serve lines fund 3-5 of 16 where v1.2.5 funded
# more. Does the four-prefix resume still hit 4/4 on the standing config?
# ONE arm — the standing config, no knob, no A/B: the comparison is against
# the round-133 receipt. The instrument is the kvshare2 probe's exact shape
# (four d4096 fill prefixes, cold sequential; the solo warm re-send of cc1;
# the four concurrent warms). The engine's per-request lines carry cached=
# — the verdict reads them. VALUE: a regression caught protects the opencode
# multi-turn interaction's resume cost; a pass re-anchors the adopted
# instrument's receipt on the current engine. No adoption branch: the
# standing config does not change on either outcome.
# ---------------------------------------------------------------------------
if want regresswatch && ! phase_done regresswatch; then
  log "=== regresswatch (the concurrent 4-prefix resume on the v1.2.6 pool plan: the kvshare2 shape, one arm)"
  P="$OUT/13-regresswatch.md"; : > "$P"
  echo "# regresswatch (the concurrent 4-prefix resume on v1.2.6's #2257 pool plan — the standing config vs the round-133 kvshare2 receipt: 4/4 cached, ttft ~1.84 s, aggregate ~7.4 s)" >> "$P"
  if restart DENSE_BITS=4 HEAD_BITS=4 KV_CACHE=fp8 CONTEXT=524288 PARALLEL=4; then
    echo "- the serve line: $(serve_line)" >> "$P"
    echo "- the slots funded: $(serve_line | grep -oE "[0-9]+ of TF_KV_SHARE=16 kept states[^;]*|[0-9]+ kept states. slots \([0-9.]+ GiB\)")" >> "$P"
    mark() { echo "- --- $1 ---" >> "$P"; docker logs "$CONTAINER_NAME" 2>&1 | grep -iE "prompt cache|store|keep|evict|resumed" | tail -4 | sed 's/^/  /' >> "$P"; }
    # 4 distinct d4096 prefixes, cold sequential (the kvshare2 contract verbatim)
    for i in 1 2 3 4; do
      bf="$OUT/rw-cc$i.json"
      FILL_WORDS="$FILL_WORDS" python3 -c "
import json, os, sys
words = os.environ['FILL_WORDS'].split(); off = int(sys.argv[1])
fill = ' '.join(w if i % 11 == 0 else w + f'-{(i + off) % 89}' for i, w in ((i, words[i % len(words)]) for i in range(4096 // 4)))
json.dump({'model': 'X', 'temperature': 0, 'max_tokens': 1, 'messages': [{'role': 'user', 'content': fill + ' Name three colors.'}]}, open(sys.argv[2], 'w'))
" "$((i * 7))" "$bf"
      python3 -c "import json,sys; b=json.load(open(sys.argv[1])); b['model']=sys.argv[2]; json.dump(b, open(sys.argv[1],'w'))" "$bf" "$SERVED_NAME"
      T=$(curl -s -m 300 "http://127.0.0.1:$PORT/v1/chat/completions" -H 'Content-Type: application/json' --data @"$bf" -o "$OUT/rw-cc$i-r.json" -w "%{time_starttransfer}" 2>/dev/null || echo 0)
      echo "- cc$i cold ttft_wall ${T}s" >> "$P"
    done
    mark "after the 4 colds (did all four keep?)"
    # the solo warm: cc1 again — does it hit?
    T=$(curl -s -m 300 "http://127.0.0.1:$PORT/v1/chat/completions" -H 'Content-Type: application/json' --data @"$OUT/rw-cc1.json" -o "$OUT/rw-solo.json" -w "%{time_starttransfer}" 2>/dev/null || echo 0)
    echo "- cc1 WARM SOLO ttft_wall ${T}s (the round-133 receipt: 1.841 s — a hit; the page cache over the pool's pages should hit in BOTH cases now)" >> "$P"
    mark "after the solo warm (hit or evicted?)"
    # the 4 concurrent warms
    S=$(date +%s.%N)
    for i in 1 2 3 4; do
      curl -s -m 300 "http://127.0.0.1:$PORT/v1/chat/completions" -H 'Content-Type: application/json' --data @"$OUT/rw-cc$i.json" -o "$OUT/rw-cc$i-w.json" || true
    done &
    wait
    E=$(date +%s.%N)
    echo "- the 4 concurrent resumes: $(python3 -c "print(f'{$E-$S:.2f}')") s aggregate (the round-133 receipt: 7.41 s)" >> "$P"
    mark "after the concurrent warms"
    echo "- the concurrent warms' engine lines (cached= is the verdict):" >> "$P"
    docker logs "$CONTAINER_NAME" 2>&1 | grep -oE "done chatcmpl-[a-f0-9]+ .*ttft=[0-9.]+" | tail -6 | sed 's/^/  /' >> "$P" || true
    echo "- VERDICT (the watch, no adoption branch): 4/4 cached>0 + the aggregate near 7.4 s => the #2257 pool plan did NOT regress the concurrent resume — the round-133 receipt re-anchors on v1.2.6. cached=0 on any prefix or the aggregate far off => a REGRESSION: the receipt lands, the ledger's watch item opens, and the shape gets its own stage brief." >> "$P"
  else
    echo "- the serve REFUSED (the refusal is the receipt):" >> "$P"
    tail -4 "$LOG" | sed 's/^/  /' >> "$P"
  fi
  touch "$OUT/.regresswatch.done"
fi
# ---------------------------------------------------------------------------
# phase: vision2744 (SESSION-SPECIFIC; retires with the receipt). The #2744
# port A/B: upstream's own fix (5151f19f3, main-only post-v1.2.6) — a prompt
# chunk sends the tower only the images that end after its start, so
# multi-image prompts stop re-encoding images their earlier chunks already
# injected (their host test: 18 -> 12 tower passes). Staged as
# patches/021-vision2744.patch (the body byte-identical to upstream's diff;
# applies clean on the full 18-patch stack, verified on a scratch clone of
# the tag; host-side only — no kernels, no contract records). The value
# probe (the stage brief, round 141 cont. 7): a two-image two-turn
# conversation — turn 1 carries image A + a d2048 fill, turn 2 adds image B
# on the same history — the opencode screenshot-per-turn shape; the tower
# re-encodes turn-1's image on turn-2's chunks pre-fix when the shared rows
# were taken. The arms: the OFF arm (the standing 18-patch stack) vs the ON
# arm (the stack + 021-vision2744.patch; the fingerprint moves, the rebuild
# rides the restart). The value gate: the ON arm's turn-2 TTFT beats the
# OFF arm's by >5%; the guards: the greedy same-bits sha on a TEXT probe
# (a vision fix must not move the deterministic text probes), the §2 gates
# on the ON arm, hardmode 95, the vision 4/4 (the fix must not change the
# suite's single-image answers), the bench + steady-state decode.
# QUALIFIED = ADOPT: 021 joins the PATCHES default. Any guard fail or no
# value => RETIRE: the patch leaves the stack, the question closes as
# upstream data (the release carries it; the rebase picks it up free).
# ---------------------------------------------------------------------------
if want vision2744 && ! phase_done vision2744; then
  log "=== vision2744 (the #2744 re-encode port: the standing stack vs the stack + 021)"
  P="$OUT/14-vision2744.md"; : > "$P"
  echo "# vision2744 (the #2744 port A/B: the 18-patch standing stack vs + 021-vision2744; dense4fp8 @ 512K x4 on the testing port)" >> "$P"
  # the value probe's bodies: turn 1 (image A + fill), turn 2 (image B + the
  # same fill + the history) — the repo's own CC-licensed assets (the
  # round-132 rule: the suite's assets, never ad-hoc fixtures).
  for arm in off on; do
    if [ "$arm" = on ]; then
      # ONE quoted argument per K=V pair (the AGENTS rule): the value carries
      # spaces, so the pair must reach restart as a single word — stage the
      # LIST into a var first, then the pair quotes it whole.
      V2744_LIST="$PATCHES 021-vision2744.patch"
      PENV=(PATCHES="$V2744_LIST")
    else
      PENV=()
    fi
    S=$(date +%s)
    if restart DENSE_BITS=4 HEAD_BITS=4 KV_CACHE=fp8 CONTEXT=524288 PARALLEL=4 "${PENV[@]}"; then
      echo "## the $arm arm (load $(( $(date +%s) - S )) s)" >> "$P"
      echo "- the serve line: $(serve_line)" >> "$P"
      # the patch witness: the patches ride the image build — the container's
      # runtime log cannot name them. The honest witness is the fingerprint
      # chain: prepare's "patch overlay" line (in THIS campaign log) must
      # name 021-vision2744 on the ON arm. Grep THE CAMPAIGN LOG (the
      # window's own receipt), not the container.
      APPLIED=$(grep -c "021-vision2744" "$LOG" 2>/dev/null || true)
      if [ "$arm" = on ]; then
        if [ "$APPLIED" -ge 1 ] 2>/dev/null; then
          echo "- the patch witness: 021-vision2744 in the campaign's prepare/build lines ($APPLIED mentions)" >> "$P"
        else
          echo "- the patch witness: FAILED (021-vision2744 not in the campaign log — a placebo arm; nothing downstream counts)" >> "$P"
        fi
      else
        echo "- the patch witness: 021 absent as intended" >> "$P"
      fi
      # the greedy same-bits witness (TEXT — a vision fix must not move it):
      req_file "$OUT/vi-$arm-req.json" "$REF_PROMPT" '{"max_tokens": 1024}'
      chat "$OUT/vi-$arm-req.json" > "$OUT/vi-$arm-resp.json" || true
      echo "- the greedy text sha: $(content_sha "$OUT/vi-$arm-resp.json")" >> "$P"
      # THE VALUE PROBE: two-image two-turn (the opencode screenshot shape).
      # turn 1: image A (bridge.jpg) + a d2048 fill; turn 2: image B
      # (zebra.jpg) + the same fill + the turn-1 answer — the multi-chunk,
      # multi-image, multi-turn shape where the pre-fix tower re-encodes.
      python3 - "$OUT" "$arm" <<'PYVI'
import base64, json, sys
out, arm = sys.argv[1], sys.argv[2]
def durl(p):
    mime = "image/png" if p.endswith(".png") else "image/jpeg"
    return "data:%s;base64," % mime + base64.b64encode(open(p, "rb").read()).decode()
fill = " ".join(f"harbor-{i%89}" for i in range(2048))
qa = "What bridge is shown in this photo? Answer with its name."
qb = "What animal is in this photo? Answer with the animal word only."
t1 = {"model": "X", "temperature": 0, "max_tokens": 256,
      "messages": [{"role": "user", "content": [
          {"type": "image_url", "image_url": {"url": durl("assets/vision/bridge.jpg")}},
          {"type": "text", "text": fill + "\n\n" + qa}]}]}
json.dump(t1, open(f"{out}/v2744-{arm}-t1.json", "w"))
# turn 2's body gets the model name + turn-1's answer filled at send time
t2 = {"model": "X", "temperature": 0, "max_tokens": 256,
      "messages": [
          {"role": "user", "content": [
              {"type": "image_url", "image_url": {"url": durl("assets/vision/bridge.jpg")}},
              {"type": "text", "text": fill + "\n\n" + qa}]},
          {"role": "assistant", "content": "PLACEHOLDER"},
          {"role": "user", "content": [
              {"type": "image_url", "image_url": {"url": durl("assets/vision/zebra.jpg")}},
              {"type": "text", "text": qb}]}]}
json.dump(t2, open(f"{out}/v2744-{arm}-t2.json", "w"))
print("- the value probe bodies staged (turn 1: bridge + d2048 fill; turn 2: zebra on the history)")
PYVI
      for turn in t1 t2; do
        python3 -c "import json,sys; b=json.load(open(sys.argv[1])); b['model']=sys.argv[2]; json.dump(b, open(sys.argv[1],'w'))" "$OUT/v2744-$arm-$turn.json" "$SERVED_NAME"
        T=$(curl -s -m 600 "http://127.0.0.1:$PORT/v1/chat/completions" -H 'Content-Type: application/json' --data @"$OUT/v2744-$arm-$turn.json" -o "$OUT/v2744-$arm-$turn-resp.json" -w "%{time_starttransfer}" 2>/dev/null || echo 0)
        echo "- $turn ttft_wall ${T}s" >> "$P"
      done
      # turn 2's wall needs the turn-1 answer inside its history — RESEND
      # turn 2 with the real answer (the placeholder breaks content
      # realism, not the cache/encode path: the history length is what
      # matters; record both forms' walls).
      A1=$(python3 -c "
import json
try: print(json.load(open('$OUT/v2744-$arm-t1-resp.json'))['choices'][0]['message']['content'][:200])
except Exception: print(' Golden Gate Bridge.')" )
      python3 -c "
import json, sys
b = json.load(open(sys.argv[1]))
b['messages'][1]['content'] = sys.argv[2]
json.dump(b, open(sys.argv[1], 'w'))" "$OUT/v2744-$arm-t2.json" "$A1"
      T2R=$(curl -s -m 600 "http://127.0.0.1:$PORT/v1/chat/completions" -H 'Content-Type: application/json' --data @"$OUT/v2744-$arm-t2.json" -o "$OUT/v2744-$arm-t2-resp2.json" -w "%{time_starttransfer}" 2>/dev/null || echo 0)
      echo "- t2 (the real-answer history) ttft_wall ${T2R}s — THE VALUE NUMBER" >> "$P"
      # THE CONCURRENT-PAIR INSTRUMENT (window 40's lesson): the fix's value is
      # the OWNER HANDOFF — two streams serving multi-image prompts
      # CONCURRENTLY re-encode each other's images on every chunk switch
      # pre-fix (b.image_owner != s after the other stream took the shared
      # rows); a single-stream sequential probe never loses ownership, so
      # its parity is the EXPECTED baseline, not the value. Two concurrent
      # multi-image multi-chunk prompts (each: an image + a d4096 fill =
      # three chunks), the aggregate wall is the value number.
      python3 - "$OUT" "$arm" <<'PYV2'
import base64, json, sys
out, arm = sys.argv[1], sys.argv[2]
def durl(p):
    mime = "image/png" if p.endswith(".png") else "image/jpeg"
    return "data:%s;base64," % mime + base64.b64encode(open(p, "rb").read()).decode()
# the v5 instrument (window 42's mechanism reading): the re-encode fires per
# chunk-switch when the owner flipped AND the chunk's span contains image
# rows — an image at the TOP of a d4096 prompt gets ONE encode (chunk 1);
# chunks 2-3 carry no image rows. THREE images per stream, one per chunk,
# is the upstream receipt's interleaved shape: the owner flips at every
# chunk boundary in a two-stream race, so each stream's later-chunk images
# re-encode per flip pre-fix. The fill words share NO prefix with the t1/t2
# probes (meadow fills; t1 is bridge+harbor) — a race serve with cached>0
# means the cache hijacked the race, not the handoff.
def cpbody(imgs, words, off, q):
    parts = []
    w = iter(words)
    n = len(words) // len(imgs)
    for k, im in enumerate(imgs):
        parts.append({"type": "image_url", "image_url": {"url": durl(im)}})
        parts.append({"type": "text", "text": " ".join(f"meadow-{(i+off)%89}" for i in range(n))})
    parts.append({"type": "text", "text": q})
    return {"model": "X", "temperature": 0, "max_tokens": 128,
            "messages": [{"role": "user", "content": parts}]}
# three images per stream, ~1365 fill words between them (three ~2048-row chunks)
nseg = 1365
def build(imgs, off, q):
    parts = []
    for k, im in enumerate(imgs):
        parts.append({"type": "image_url", "image_url": {"url": durl(im)}})
        parts.append({"type": "text", "text": " ".join(f"meadow-{(i + off + k * 7) % 89}" for i in range(nseg))})
    parts.append({"type": "text", "text": q})
    return {"model": "X", "temperature": 0, "max_tokens": 128,
            "messages": [{"role": "user", "content": parts}]}
pa = build(["assets/vision/zebra.jpg", "assets/vision/sign.jpg", "assets/vision/bridge.jpg"], 0, "Name the animal in one word.")
pb = build(["assets/vision/sign.jpg", "assets/vision/zebra.jpg", "assets/vision/_quadrants.png"], 311, "What does the sign say in one word?")
json.dump(pa, open(f"{out}/v2744-{arm}-cp-a.json", "w"))
json.dump(pb, open(f"{out}/v2744-{arm}-cp-b.json", "w"))
print("- the concurrent-pair bodies staged (three interleaved images per stream — the upstream receipt's shape; meadow fills, no shared prefix with the t1/t2 probes)")
PYV2
      for s in a b; do
        python3 -c "import json,sys; b=json.load(open(sys.argv[1])); b['model']=sys.argv[2]; json.dump(b, open(sys.argv[1],'w'))" "$OUT/v2744-$arm-cp-$s.json" "$SERVED_NAME"
      done
      # NO warm-up pair (window 41's lesson: the warm-up primed the page
      # cache — the race measured cache hits, cached=12288/16384, and the
      # re-encode path never ran). The race runs COLD: two multi-chunk
      # multi-image prompts from boot, their chunk switches interleaving on
      # the shared tower — the owner handoff the fix removes. The engine
      # lines' cached= values are the mechanism witness (cached=0 expected
      # on both race streams; a cached>0 line means the page cache hijacked
      # the race and the number does not count).
      S=$(date +%s.%N)
      for s in a b; do
        curl -s -m 600 "http://127.0.0.1:$PORT/v1/chat/completions" -H 'Content-Type: application/json' --data @"$OUT/v2744-$arm-cp-$s.json" -o "$OUT/v2744-$arm-cp-$s-race.json" || true
      done &
      wait
      E=$(date +%s.%N)
      echo "- the concurrent-pair race: $(python3 -c "print(f'{$E-$S:.2f}')") s aggregate — THE VALUE NUMBER (concurrent)" >> "$P"
      # the per-stream walls from the engine's own lines (the ttft of the two race requests)
      echo "- the race's engine lines:" >> "$P"
      docker logs "$CONTAINER_NAME" 2>&1 | grep -oE "done chatcmpl-[a-f0-9]+ .*ttft=[0-9.]+" | tail -2 >> "$P" || true
      # THE ROOM GUARD (window 39's confound lesson): the ON arm booted right
      # after the 560 s rebuild — the unified-memory pool carried the build's
      # residue (11.5 GiB left vs the OFF arm's 13.0), the serve funded ZERO
      # kept states, and the value probe measured the cache-state confound,
      # not the fix. THE FIX: the ON arm gains ONE build-free restart before
      # its probes — the room settles — and BOTH arms' value sections carry
      # the room line so a future room mismatch fails the battery loudly
      # (the value gate reads only when the arms' room differs by < 1.0 GiB).
      echo "- the room line: $(serve_line | grep -oE "of [0-9.]+ GiB left after")" >> "$P"
      echo "- t2's answer: $(python3 -c "
import json
try: print(json.load(open('$OUT/v2744-$arm-t2-resp2.json'))['choices'][0]['message']['content'][:120])
except Exception as e: print('unreadable:', e)")" >> "$P"
    else
      echo "## the $arm arm — REFUSED" >> "$P"; tail -4 "$LOG" | sed 's/^/  /' >> "$P"
    fi
  done
  echo "## the §2 content gates (the ON arm's serve stands)" >> "$P"
  run_gates vi DENSE_BITS=4 HEAD_BITS=4 KV_CACHE=fp8 CONTEXT=524288 PARALLEL=4 PATCHES="$PATCHES 021-vision2744.patch" || true
  echo "## hardmode (the 95 must hold, the ON arm's serve)" >> "$P"
  mkdir -p "$OUT/vihm"
  model=$(curl -s -m 10 "http://127.0.0.1:$PORT/v1/models" | python3 -c '
import json, sys
try: print(json.load(sys.stdin)["data"][0]["id"])
except Exception: print("")' 2>/dev/null) || model=""
  PYTHONUNBUFFERED=1 "$BENCH" run --base-url "http://127.0.0.1:$PORT" \
    --model "$model" --format openai --tokenizer "$MODEL_ID" \
    --hardmode --label "vision2744" --output-dir "$OUT/vihm" --parallel 2 \
    --json-file "$OUT/vihm/hm.json" > "$OUT/vihm/hm.log" 2>&1 || true
  grep -o '"final_score": [0-9]*' "$OUT/vihm/hm.json" >> "$P" 2>/dev/null || true
  grep -o '"scenario_id": "TC-51", "status": "[a-z]*"' "$OUT/vihm/hm.log" >> "$P" 2>/dev/null || true
  grep -o '"scenario_id": "TC-92", "status": "[a-z]*"' "$OUT/vihm/hm.log" >> "$P" 2>/dev/null || true
  echo "## the vision suite (4/4 must hold — the fix must not move the single-image answers)" >> "$P"
  mkdir -p "$OUT/vivision"
  python3 scripts/vision-suite-probe.py "http://127.0.0.1:$PORT" "$OUT/vivision/vision.json" > "$OUT/vivision/vision.log" 2>&1 || true
  tail -6 "$OUT/vivision/vision.log" >> "$P" 2>/dev/null || true
  echo "## the regression watch (the bench + steady-state on the ON arm's serve)" >> "$P"
  bench_perf vi "$OUT/vi-bench" 4 >> "$P" 2>&1 || true
  bf=$(mktemp /tmp/vi.XXXXXX.json)
  python3 -c "
import json, sys
print(json.dumps({'model': sys.argv[1], 'messages': [{'role': 'user', 'content': 'Write a 400-word essay about lighthouses.'}], 'max_tokens': 2048, 'temperature': 0, 'seed': 42}))" "$SERVED_NAME" > "$bf"
  model=$(curl -s -m 10 "http://127.0.0.1:$PORT/v1/models" | python3 -c '
import json, sys
try: print(json.load(sys.stdin)["data"][0]["id"])
except Exception: print("")' 2>/dev/null) || model=""
  python3 -c "import json,sys; b=json.load(open(sys.argv[1])); b['model']=sys.argv[2]; json.dump(b, open(sys.argv[1],'w'))" "$bf" "$model"
  S=$(date +%s)
  curl -s -m 300 "http://127.0.0.1:$PORT/v1/chat/completions" -H 'Content-Type: application/json' --data @"$bf" -o "$OUT/vi-decode.json" || true
  W=$(( $(date +%s) - S )); rm -f "$bf"
  python3 -c "
import json
try:
    d = json.load(open('$OUT/vi-decode.json'))
    ct = d['usage']['completion_tokens']
    print('- steady-state decode: %d tokens in %d s = %.1f tok/s (wall incl. prefill; the band: 70-76)' % (ct, $W, ct / max($W, 1)))
except Exception as e:
    print('- the decode probe FAILED: ' + repr(e))
" >> "$P"
  # THE ROOM-MATCH RESTART (window 39's confound lesson): the ON arm's first
  # boot rode the rebuild's memory residue — the serve funded zero kept
  # states and the value probe measured the cache-state confound, not the
  # fix. Restart the ON arm build-free (the fingerprint matches the prepared
  # marker now) so its value probes read the settled room, and gate the
  # verdict on the arms' room lines agreeing within 1.0 GiB.
  log "vision2744: the ON arm's room-match restart (build-free; the room settles)"
  V2744_LIST="$PATCHES 021-vision2744.patch"
  if ! restart DENSE_BITS=4 HEAD_BITS=4 KV_CACHE=fp8 CONTEXT=524288 PARALLEL=4 PATCHES="$V2744_LIST"; then
    echo "- the ON arm's room-match restart REFUSED — the battery is void; the value gate does not fire" >> "$P"
    touch "$OUT/.vision2744.done"
    log "vision2744: the room-match restart refused — phase void (fail-honest)"
    exit 0
  fi
  echo "## the ON arm's room-matched serve (the settle restart)" >> "$P"
  echo "- the room line: $(serve_line | grep -oE "of [0-9.]+ GiB left after")" >> "$P"
  echo "- the slots line: $(serve_line | grep -oE "[0-9]+ of TF_KV_SHARE=16 kept states[^;]*|[0-9]+ kept states. slots \([0-9.]+ GiB\)|no prompt cache")" >> "$P"
  # re-run the value probe on the room-matched serve (the greedy sha witness rides too)
  req_file "$OUT/vi-on-rm-req.json" "$REF_PROMPT" '{"max_tokens": 1024}'
  chat "$OUT/vi-on-rm-req.json" > "$OUT/vi-on-rm-resp.json" || true
  echo "- the room-matched greedy text sha: $(content_sha "$OUT/vi-on-rm-resp.json")" >> "$P"
  for turn in t1 t2; do
    python3 -c "import json,sys; b=json.load(open(sys.argv[1])); b['model']=sys.argv[2]; json.dump(b, open(sys.argv[1],'w'))" "$OUT/v2744-on-$turn.json" "$SERVED_NAME"
    T=$(curl -s -m 600 "http://127.0.0.1:$PORT/v1/chat/completions" -H 'Content-Type: application/json' --data @"$OUT/v2744-on-$turn.json" -o "$OUT/v2744-on-rm-$turn-resp.json" -w "%{time_starttransfer}" 2>/dev/null || echo 0)
    echo "- room-matched $turn ttft_wall ${T}s" >> "$P"
  done
  A1=$(python3 -c "
import json
try: print(json.load(open('$OUT/v2744-on-rm-t1-resp.json'))['choices'][0]['message']['content'][:200])
except Exception: print(' Golden Gate Bridge.')" )
  python3 -c "
import json, sys
b = json.load(open(sys.argv[1]))
b['messages'][1]['content'] = sys.argv[2]
json.dump(b, open(sys.argv[1], 'w'))" "$OUT/v2744-on-t2.json" "$A1"
  T2R=$(curl -s -m 600 "http://127.0.0.1:$PORT/v1/chat/completions" -H 'Content-Type: application/json' --data @"$OUT/v2744-on-t2.json" -o "$OUT/v2744-on-rm-t2-resp2.json" -w "%{time_starttransfer}" 2>/dev/null || echo 0)
  echo "- room-matched t2 (the real-answer history) ttft_wall ${T2R}s — THE VALUE NUMBER (room-matched)" >> "$P"
  # the room-matched concurrent-pair race (the value gate reads THIS number):
  # the SAME cp bodies as the arm-loop race — the settle restart wiped the
  # page cache (it is per-process), so the race runs cold on the settled
  # serve; the same shape on both sides of the value gate (window 42's
  # lesson: the cistern variant tokenized +4096 tokens and had no OFF-arm
  # counterpart, so it could not feed the gate).
  for s in a b; do
    python3 -c "import json,sys; b=json.load(open(sys.argv[1])); b['model']=sys.argv[2]; json.dump(b, open(sys.argv[1],'w'))" "$OUT/v2744-on-cp-$s.json" "$SERVED_NAME"
  done
  S=$(date +%s.%N)
  for s in a b; do
    curl -s -m 600 "http://127.0.0.1:$PORT/v1/chat/completions" -H 'Content-Type: application/json' --data @"$OUT/v2744-on-cp2-$s.json" -o "$OUT/v2744-on-rm-cp-$s-race.json" || true
  done &
  wait
  E=$(date +%s.%N)
  echo "- the room-matched concurrent-pair race: $(python3 -c "print(f'{$E-$S:.2f}')") s aggregate — THE VALUE NUMBER (room-matched, concurrent)" >> "$P"
  echo "- the room-matched race's engine lines:" >> "$P"
  docker logs "$CONTAINER_NAME" 2>&1 | grep -oE "done chatcmpl-[a-f0-9]+ .*ttft=[0-9.]+" | tail -2 >> "$P" || true
  echo "- room-matched t2's answer: $(python3 -c "
import json
try: print(json.load(open('$OUT/v2744-on-rm-t2-resp2.json'))['choices'][0]['message']['content'][:120])
except Exception as e: print('unreadable:', e)")" >> "$P"
  echo "- VERDICT (VALUE-FIRST, window 39 on): QUALIFIED = the patch PLACED (the boot-log witness) AND the greedy TEXT sha == the standing 80cc3802… AND (the value gate) the ON arm's room-matched CONCURRENT-pair race aggregate BEATS the OFF arm's by >5% (the owner-handoff shape; the single-stream probe's parity is the harness baseline) AND (the room gate) the arms' room lines differ by < 1.0 GiB AND the §2 gates ALL PASS AND hardmode 95 AND the vision suite 4/4 (the single-image answers unchanged) AND the bench/decode bands hold => 021-vision2744.patch joins config.sh's PATCHES default. Any guard fail or no value => RETIRE: the patch leaves the stack, the question closes as upstream data (the v1.2.7 release carries it; the rebase picks it up free)." >> "$P"
  touch "$OUT/.vision2744.done"
fi


# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------


# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# phase: prodcold — RETIRED (the round-139 (user) directive): its question was
# production's TRUE cold depth cost on the RETIRED Python engine (its persistent
# cache vs our fresh-process probe fills). The Python recipe is retired; the
# native engine's cold depth cost is measured directly on our own serve by the
# depth/cliff phases. Nothing re-implements this.
# ---------------------------------------------------------------------------
PRODCOLD_RETIRED=1




# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------

if want summary; then
  log "=== summary"
  S="$OUT/CAMPAIGN.md"
  {
    echo "# Replication campaign $RUN_ID"
    echo
    echo "## Gates"
    grep -hE "^- (PASS|FAIL|NOTE|depth|batch|usage|server|RoCE|PARALLEL|.*refused)" "$OUT"/[0-9]*.md 2>/dev/null | head -60 || true
    echo
    echo "## Phase receipts"
    for f in "$OUT"/[0-9]*.md; do [ -f "$f" ] || continue; echo "### $(basename "$f")"; cat "$f"; echo; done
    echo "## Way forward"
    echo "- Content-form gates (VALIDATION §2 receipt, 2026-10-23): PASS = content-identical;"
    echo "  raw-byte differences are the engine's documented nondeterminism, not a cache fault."
    echo "- dense4fp8 vs parity: tool-eval 92 = 92 (first campaign); this campaign's"
    echo "  throughput + climb receipts pick the serving config and its stream count."
    echo "- kvqual4 PASS + throughput lead = dense4fp8 is the qualified ladder config;"
    echo "  feed the cliff/prefill receipts into the next upstream note."
  } > "$S"
  if ./scripts/render-perf-chart.sh --check >> "$S" 2>&1; then
    log "chart check: the committed SVG matches the anchors"
  else
    log "chart check: STALE vs the anchors — regenerate and commit (render-perf-chart.sh)"
  fi
  log "campaign complete: $S"
  tail -40 "$S"
fi
log "done."
