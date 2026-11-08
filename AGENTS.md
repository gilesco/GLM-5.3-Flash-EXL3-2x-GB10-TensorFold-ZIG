# AGENTS.md — how to work in this repo

> All edits in this repository are AI-generated (OpenCode agents running GLM, by Z.ai);
> the README banner carries the provenance disclaimer. This file is the working
> conventions digest — pointers to the real trackers, not a second copy of them.

## What this repo is

The EXL3-only **promoted native line** for GLM-5.3-Flash on a two-GB10 pair — one **head**
host (rank 0 + API) and one **worker** host (rank 1); this site's real hostnames,
addresses and devices live in git-ignored `scripts/local.sh` / `docs/SITE.md` —
served by TensorFold's **native CUDA
engine**. It **IS the production deployment** ((user) round-138/139 promotion): the
promoted native stack serves opencode on 8000 from this repo's config, and testing
windows run from the same repo — the old Python recipe is retired (its GitHub repo
points here), and comparisons are native-vs-native: current production against
current testing.

Hard boundaries, never crossed:

- **Production's lifecycle is autonomously managed (user, round 129)**: the window
  flow and test dances stop production for GPU work and restart it on EVERY exit
  path; the crash-net restarts it whenever it is down with no window running. The
  guardrails: production always comes back; production's code/config is never
  modified beyond the intent-keyed port; test phases probe the testing serve
  read-only. **The ports are intent-keyed (user)**: production started FOR OPENCODE
  serves 8000 (the promoted repo's config); a stack started FOR TESTING serves
  8001 (`PORT=8001 ./scripts/start.sh` — the promoted repo IS the baseline arm now);
  opencode never connects to 8001. **Separation runs through the autonomous window flow, never ad-hoc
  (user, round 132)**: when a phase starts a testing serve on 8001 it stops the
  8000 stack first (the two never share the port — the round-132 duel
  refusal: "port 8001 is already in use", the round-139 void: the duel restarted
  the ours arm without stopping the 8001 stack first) and restarts the 8000
  stack after; production
  itself is stopped/restored only by the window flow's entry/exit paths.
- This line is **EXL3 only** (the NVFP4 route has its own repo) and the context goal is
  **524,288 tokens — nothing above**.
- **Every quality/perf metric runs on the clean testing port 8001** — never
  tool-eval-bench or any load against production's live 8000 (user, round 132: it
  negates the testing environment; any such result is invalid). Production-vs-us
  comparisons are NATIVE-vs-NATIVE (the round-139 (user) directive): the duel's
  baseline arm is THIS repo's own promoted config started FOR TESTING on 8001
  (`PORT=8001 ./scripts/start.sh`) — the promoted repo IS the baseline arm; the
  retired Python recipe's pairs are history.
- **Vision tests use the repo's own vision assets — never ad-hoc fixtures, never
  files scavenged from other tools' trees (user, round 132)**: `assets/vision/`
  (`manifest.json`: the synthetic byte-verified `_quadrants.png` + 3 CC-licensed
  photos with agent-verified ground truth) via the repoed runner
  `scripts/vision-suite-probe.py <base-url> <out-json>`. The round-132 SVG sanity
  was an invalid test — the tower wants raster; the suite exists so no test ever
  improvises an image again.
- **Nothing is posted upstream** (no issues/PRs to ashhart/TensorFold or other repos).
  Findings for upstream are written into `docs/ECOSYSTEM.md` as data.
- Site identity (hostnames, IPs, ssh targets, rail devices, HCA names) lives only in
  git-ignored `scripts/local.sh` / `docs/SITE.md`. **Never commit it, in any file**:
  committed prose says "the head" / "the worker", never a hostname, address, netdev
  or HCA name.

## Where evidence and decisions live — use these, don't spawn alternatives

| Need | The tracker | Not this |
| --- | --- | --- |
| **The current status snapshot** | **`README.md` — current status and pointers ONLY; no history** | round references, narratives, duplicated scoreboards |
| Run receipts, raw outputs | `results/campaign-*/` (one dir per run, on the head's checkout) | ad-hoc scratch dirs or files |
| **The production-vs-native scoreboard** | **`docs/DELTAS.md`** (+ `docs/perf-anchors.tsv` for the chart's pairs) | second copies in the README or PERF_PLAN |
| Session log, decisions, incidents | `docs/LAUNCH.md` — **append-only**, one `## (round N)` header each | new log files |
| Matrix status, open items, result tables | `docs/TOOL_EVAL_TESTING.md` — the ledger | per-round summary files |
| Gate definitions + the native-line receipt | `docs/VALIDATION.md` | new gate docs |
| Production-vs-native comparison | `docs/DELTAS.md` | — |
| Upstream/community watch | `docs/ECOSYSTEM.md` | — |
| Port queue + staged port recipes | `docs/PORT_QUEUE.md` | working notes in scratch files |
| Context-ladder math and its outcome | `docs/CONTEXT_512K_PLAN.md` | — |
| This site's real values | `docs/SITE.md` (git-ignored) | — |

## Rules of the road

- **Every number in the docs quotes a receipt** — a file in `results/` or a LAUNCH.md
  entry. No number without a run behind it. Correcting a wrong number gets a round
  entry explaining the withdrawal; never edit it silently.
- **Parallelizable reading is subagent work (user, round 139)** — independent,
  read-only scans (upstream/fork reviews, reference inventories, doc digests)
  are delegated to subagents (at most TWO in flight) while the main sitting
  keeps the hands-on, state-mutating work (commits, patches, launches)
  serialized. Subagents report findings; they never commit, push, launch, or
  touch production. **A window may not launch while any subagent is still in
  flight** — the window stops production, and a scan reading the head mid-stop
  reads a moving machine; every subagent completes (its findings digested) or
  is explicitly cancelled before the launch goes out.
- **A new measurement is a phase in `scripts/run-qualification.sh`**, not a one-off
  script. The campaign is phased (`.done` markers, `PHASES=` selectable, `FORCE=1`
  re-run), production-guarded, and its receipts ARE the evidence chain. Session-specific
  phases say so in their comment and are deleted when they retire.
- **Version pins go in `scripts/local.sh`** (`TF_REPO`/`TF_COMMIT`), never the session
  env: `start.sh`'s auto-prepare re-resolves the default ref whenever the config
  fingerprint changes and silently drops a session pin (round 7's window was voided on
  exactly this; `local.sh.example` carries the example).
- **Never edit `scripts/*.sh` or `config.sh` while a campaign is running** — bash
  re-reads scripts lazily, and `config.sh` is re-sourced by every restart.
- **GPU windows run inside the standing autonomous loop (the next bullet)** — the
  (user) handover is the loop itself. Outside its shape (a new instrument class, a
  window the perf plan doesn't state as the next step, anything touching
  production itself) they are the user's, asked first. Long runs go under `nohup`
  on the head with the console at `/tmp/<name>.console`, not in a foreground ssh.
- **The launch is the LAST action of a sitting (user, round 133 — confirmed working:
  no launch has cut a sitting's work off midway since)**. Finish every task first —
  the docs, the digests, the commits, the pushes, the head's ff-only — then launch
  at most ONE window and go dark until the poke. The launch command takes the phase
  list as its ARGUMENT: `RC_PATCHES="a.patch,b.patch" scripts/autonomous-launch.sh
  "phase summary"` (space-separated, `summary` last; a `PHASES` env var is silently
  ignored — cont. 69's window ran only part of its list that way). A sitting with
  nothing to test launches nothing.
- **The autonomous loop is the standing mode (user) — its map, all four scripts in
  this repo**: `autonomous-launch.sh` (on the head; the ONLY launcher — syncs to
  origin/main, refuses a double launch via the flag file, starts the window
  detached) → `autonomous-window.sh` (detached; the only thing allowed to stop
  production, always through the production repo's own stop/start scripts which
  handle BOTH ranks; runs the phases; restores production on EVERY exit path via
  the EXIT trap) → `autonomous-cron.sh` (the head's 5-min cron: production down +
  no window flag → restart through the production repo's start.sh; hands off
  while a window is in flight) → `autonomous-poke.sh` (the agent host's 5-min
  cron: production up + the newest campaign unpoked → POSTs the wake into this
  session's durable prompt inbox).
  The woken sitting digests the receipt the same sitting and launches the next
  window last — the loop closes itself. The skills `autonomous-agent-wake-loop`
  and `opencode-agent-wake` carry the mechanism's generic form (the wake vector,
  the marker discipline, the two-cron split).
- A round's digest updates **the same sitting**: LAUNCH.md (append), the ledger's
  status items, any affected plan doc, and the README status table when a qualified
  fact changes. When a comparison metric changes, also update `docs/perf-anchors.tsv`
  (the standing chart's data) and re-run `scripts/render-perf-chart.sh <tsv>` — the
  chart
  SVGs are generated, never hand-edited: one bar = our performance as % of
  production, time metrics inverted, higher always better; the truth, bad or good.
  The guard and the campaign's summary phase flag a stale chart via `--check`.
- `config.sh` defaults track the **qualified optimum** (with receipts cited in
  comments) — a bare `./scripts/start.sh` serves them. Site-only values (worker,
  rails, identity) stay in `local.sh`.
- User decisions are recorded as "(user)" in the LAUNCH.md round entry, with the
  reasoning — they override agent judgment.

## Commit and sync protocol

Edit locally → commit (message names the finding, not the file) → push → on the head:
`git fetch origin && git merge --ff-only origin/main` (ff-only, never rebase shared
history). **The committed pre-commit hook runs the docs guard on every commit** —
activate it once per clone with `git config core.hooksPath scripts/hooks`; a failing
check blocks the commit until the doc it flags is fixed. Campaign receipts live on the
head's checkout under `results/` and are not committed — quote them from there.

## Gotchas that have already cost us (don't relearn them)

- Bench **tg128 rows divide by TOTAL time** — prefill pollutes short generations at
  depth. Steady-state probes (long generations, e.g. max_tokens 2048) are the honest
  decode instrument.
- **Whole-envelope sha is not a determinism instrument** (envelope `id`/`created`/
  metadata vary per request on every engine). Gates bind on normalized `content_sha`.
- **`cached_tokens` in usage is unwired** (0 even on cache hits) — cache-hit
  verification is content + the `/metrics` counters (`tensorfold_cached_tokens_total`
  via goshi's exporter).
- **fp8 KV × `TF_KV_PAGES=on` is THE adopted serving mode** (the 1106 marriage + the
  pagerows/selist fixes, round 133) — the old "bf16 is the only paged path" warning
  died with the marriage; the mode is receipted end to end (§2 on both KV cells, the
  depth ladder, hardmode, the duel).
- **config.sh knobs have TWO forwarding paths, and they fail differently** — the arg
  builders consume shell variables directly (`KV_CACHE` → `--kv-cache`), while
  `env_args()` forwards TF_*/NCCL_* from the EXPORTED environment (`env | grep`).
  A default added on the wrong path fails silently: the serve line's memory
  arithmetic is the only witness. Defaults for env-forwarded knobs must be
  `export`ed (the KV_SHARE adoption was smoke-caught on exactly this), and **the
  bare config is smoke-tested after ANY default change** (the adoptsmoke phase
  pattern — read the serve line, don't trust the probe alone).
- **One quoted argument per `K=V` pair in restart calls** — joining pairs into a
  single string makes `env` set ONE mangled variable (the resweep window burned on
  it; prepare's error named a hub dir with `MODEL_REVISION=main` inside — read
  error text for embedded pair syntax before suspecting the cache).
- **`git rev-parse <tag>` yields the annotated TAG OBJECT, not the commit** — a pin
  field needs `<tag>^{commit}` (the v1.2.3 pin would have checked out a tag object).
- **A phase's refusal path prints the prepare/start log's tail** — the error must
  land in the receipt, not hide in the campaign log (the resweep's first run didn't
  self-diagnose and the window was wasted).
- **Thinking eats small `max_tokens`** — gate probes use ≥1024.
- **`VAR=x func` persists in bash** — any function that overrides a config variable
  (e.g. `SERVED_NAME`) restores it after the override; keep that pattern for any new
  override.
- The engine's admission refusal prints its own arithmetic — a refusal is a receipt,
  not a failure; record it instead of retrying blind.
