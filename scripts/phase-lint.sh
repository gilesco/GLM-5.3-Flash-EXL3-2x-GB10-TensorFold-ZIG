#!/usr/bin/env bash
# scripts/phase-lint.sh — the mechanical pre-launch catch for the two staging
# failure classes that burned windows 33 and 34 (round 140):
#   (a) unguarded grep at a pipeline's end inside a command substitution or a
#       run-qualification phase block: under `set -euo pipefail`, a no-match
#       grep exits 1 and set -e kills the whole window (window 34);
#   (b) K=V env pairs staged by hand whose name the consumer never reads —
#       start.sh's flags are the contract (window 33: PROMPT_PROMPT_CACHE_GIB).
# Usage: phase-lint.sh [run-qualification.sh] — exits nonzero on findings.
# Wired into autonomous-launch.sh BEFORE a window starts; the launch REFUSES
# on findings (a lint failure is cheaper than a dead window).
set -uo pipefail
cd "$(dirname "$0")/.."
TARGET="${1:-scripts/run-qualification.sh}"
fails=0
say() { printf '%s\n' "$*"; }

say "== phase-lint: $TARGET =="

# (a) unguarded greps in ASSIGNMENT command substitutions: `VAR=$( ... | grep ... )`
# where the substitution's last command is a grep (incl. `grep -c`, which exits 1
# on a zero count). An assignment's status IS the substitution's, so set -e kills
# the script (window 34). Echo-embedded substitutions are status-discarded and
# are NOT flagged (empirically safe across every window; e.g. the serve-line
# echoes). Parsing is paren-depth-aware and quote-aware so a grep pattern
# containing escaped parens does not truncate the body.
lint_unguarded() {
  python3 - "$TARGET" <<'PYL'
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
finds = []
for i, line in enumerate(src.splitlines(), 1):
    # find $( ... ) spans with paren-depth counting, honoring quotes
    j = 0
    while True:
        k = line.find("$(", j)
        if k < 0:
            break
        depth, m = 1, k + 2
        quote = None
        while m < len(line) and depth:
            ch = line[m]
            if quote:
                if ch == quote:
                    quote = None
            elif ch in "\"'":
                quote = ch
            elif ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
            m += 1
        if depth == 0:
            body = line[k + 2:m - 1]
            # only assignment-shaped substitutions carry the status
            prefix = line[:k].rstrip()
            if re.search(r'=\s*$', prefix) or re.search(r'\b(local|readonly)\s+\S+\s*=\s*$', prefix):
                tail = body.rstrip()
                # last command is grep (any flags)? tokenize on unquoted pipes
                pipes = []
                q = None
                for n, ch in enumerate(tail):
                    if q:
                        if ch == q: q = None
                    elif ch in "\"'": q = ch
                    elif ch == "|": pipes.append(n)
                last_cmd = tail[pipes[-1] + 1:].strip() if pipes else tail
                if re.match(r'grep(\s|$)', last_cmd) and "|| true" not in body:
                    finds.append((i, line.strip()[:150]))
            j = m
        else:
            j = k + 2
for i, l in finds:
    print(f"FIND (unguarded grep tailing an assignment substitution) line {i}: {l}")
sys.exit(0)
PYL
}
lint_out=$(lint_unguarded)
lint_rc=0
if [ -n "$lint_out" ]; then
  say "$lint_out"; fails=$((fails + 1)); lint_rc=1
else
  say "PASS: no unguarded greps in command substitutions"
fi

# (b) env names staged by phase code against the consumers' contract:
# only lines that PASS K=V pairs to the restart/restart_fb/run_gates helpers
# matter — those go through `env` to start.sh. Ordinary shell assignments
# (TS=, V1CONV=, ...) are local and are NOT checked.
lint_envnames() {
  python3 - "$TARGET" <<'PYL'
import re, sys
target, = sys.argv[1:]
known = set()
for f in ("scripts/start.sh", "config.sh"):
    src = open(f, encoding="utf-8").read()
    known |= set(re.findall(r'^\s*(?:export\s+)?([A-Z][A-Z0-9_]+)=', src, re.M))
    known |= set(re.findall(r'\[\[ -z "\$\{?([A-Z][A-Z0-9_]+)\}?" \]\]', src))
allow = {"DENSE_BITS", "HEAD_BITS", "KV_CACHE", "CONTEXT", "PARALLEL", "PATCHES",
         "PORT", "DRAFTS", "VISION", "CHAT_TEMPLATE", "PROMPT_CACHE_GIB",
         "SPILL_GIB", "TF_KV_SHARE", "TF_PROMPT_CACHE_FIRST"}
bad = []
for i, line in enumerate(open(target, encoding="utf-8"), 1):
    if not re.search(r'\b(restart|restart_fb|run_gates)\s', line):
        continue
    for m in re.finditer(r'\b([A-Z][A-Z0-9_]+)=', line):
        name = m.group(1)
        if name in known or name in allow or name.startswith("TF_") or name.startswith("NCCL_"):
            continue
        bad.append((name, i, line.strip()[:130]))
for name, i, l in bad:
    print(f"FIND (env pair on a restart/gates line not in start.sh/config.sh's contract) line {i}: {name} — {l}")
sys.exit(0)
PYL
}
lint_envout=$(lint_envnames)
if [ -n "$lint_envout" ]; then
  say "$lint_envout"; fails=$((fails + 1))
else
  say "PASS: every staged K=V name is in the consumers' contract"
fi

# (c) the env-contract check itself: the names the phase stages AS overrides
# (PROMPT_CACHE_GIB=4 etc.) must appear in start.sh's flag-mapping lines.
grep -n 'PROMPT_CACHE_GIB' scripts/start.sh > /dev/null || { say "FIND: PROMPT_CACHE_GIB has no mapping in scripts/start.sh"; fails=$((fails + 1)); }

say "== phase-lint: $fails failing class(es) =="
exit "$fails"
