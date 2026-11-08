#!/usr/bin/env bash
# shellcheck shell=bash disable=SC2034  # a config file: several vars are consumed by the scripts that source it
# Shared settings for start.sh, stop.sh, status.sh and scripts/*.sh. A setting's value comes from
# the first of these that sets it:
#   1. the environment: `PORT=9000 ./scripts/start.sh`
#   2. scripts/local.sh (this setup's own values; sourced as bash), then ./.env (KEY=value lines,
#      read, never run): both are yours, not the repository's; where both set a key, local.sh wins
#   3. the defaults below
#
# This recipe serves GLM-5.3-Flash on the native TensorFold CUDA engine ("tensorfold-native")
# at tensor parallel over two GB10 hosts, from the EXL3 checkpoint line — the AZ-Focus
# variant by default (the (user) hardmode-bar call, 2026-10-27), with the DFlash2 drafter —
# the two-rank path upstream measured for 1.1.0 and onwards. This line is EXL3
# only: the NVFP4 route has its own repo (GLM-5.3-Flash-NVFP4-2x-GB10-TensorFold-v1-testing).
# Everything runs in Docker; no Python engine and no patch stack.
_cfg_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if [[ -f "$_cfg_root/scripts/local.sh" ]]; then
  declare -A _cfg_env=()
  while IFS= read -r _n; do _cfg_env[$_n]=${!_n}; done < <(compgen -e)
  source "$_cfg_root/scripts/local.sh"
  for _n in "${!_cfg_env[@]}"; do [[ "${!_n-}" == "${_cfg_env[$_n]}" ]] || export "$_n=${_cfg_env[$_n]}"; done
  unset _cfg_env
fi
if [[ -f "$_cfg_root/.env" ]]; then
  while IFS= read -r _line || [[ -n "$_line" ]]; do
    [[ "$_line" =~ ^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]] || continue
    _key=${BASH_REMATCH[2]}; _value=${BASH_REMATCH[3]}
    if [[ "$_value" =~ ^\"([^\"]*)\"[[:space:]]*(#.*)?$ || "$_value" =~ ^\'([^\']*)\'[[:space:]]*(#.*)?$ ]]; then
      _value=${BASH_REMATCH[1]}
    else
      _value=${_value%%#*}; _value=${_value%"${_value##*[![:space:]]}"}
    fi
    [[ -n "${!_key+set}" ]] || export "$_key=$_value"
  done < "$_cfg_root/.env"
fi
unset _n _line _key _value

# ---------------------------------------------------------------------------
# TensorFold version. Releases are frequent; "latest-v1" (the default) resolves to the newest
# v1.* release at prepare time and records the resolved tag and commit in the prepared marker,
# so an upstream release changes nothing until you re-run prepare. Pin instead with e.g.
# TF_REF=v1.0.12 (a tag) or TF_COMMIT=<sha> (an exact tree; wins over TF_REF).
# ---------------------------------------------------------------------------
TF_REF="${TF_REF:-latest-v1}"
TF_COMMIT="${TF_COMMIT:-}"
TF_REPO="${TF_REPO:-https://github.com/ashhart/TensorFold.git}"

# The served default checkpoint: Mia-AiLab's TR3-4bpw EXL3 (the round-132 (user)
# swap — the 4bpw sweep's verdict: 94/104 hardmode with the best top-8 decode; the
# scorecards: docs/bpw4-sweep-cards.svg). The prior default was AxonZeta's AZ-Focus
# EXL3 (topk=8 by design, the 2026-10-27 swap; 93/104) — still serveable as a local
# checkpoint on both hosts (see docs/SITE.md, not in git). The stock/top4cfg cells
# serve Mia-AiLab's EXL3 one (4-bit mcg routed experts, BF16 elsewhere) —
# production's checkpoint, already in this site's Hugging Face caches. This
# line is EXL3 only; the NVFP4 route has its own repo. The ranks cross-check every
# checkpoint byte against each other at start, so a copy that differs on one host stops
# both before serving.
MODEL_ID="${MODEL_ID:-local/GLM-5.3-Flash-TR3-4bpw-reshard}"   # the TR3-4bpw pack reshared 120 -> 55 shards (round 135): checkpoint.direct's gather draws on at most max_sources 64 files (the fd budget: 64 x 16 readers ~ the 1024 soft limit), and the served pack's 120 files ALL hold model.language_model.* tensors — the direct path silently stayed off on the original pack. Byte-identical tensors (the reshard tool verified: the name set, every length, the total volume, sha256 of 24 sampled tensors); SERVED_NAME unchanged; the same bytes the round-132 (user) TR3 swap qualified — 94/104 hardmode, the best top-8 decode
MODEL_REVISION="${MODEL_REVISION:-main}"   # the qualified optimum (2026-11-02, (user): the 4bpw sweep's verdict — TR3 94/104 hardmode with the best top-8 decode (tg128 46.0/46.2/45.2), dominating the Focus's 93 on both axes; the scorecards: docs/bpw4-sweep-cards.svg; the prior Focus swap (2026-10-27) stood at 93)
                             # the site's top4cfg variant of this checkpoint — num_experts_per_tok
                             # 4, byte-surgical vs the base snapshot (one line differs). Receipts:
                             # perf campaign-20261024-135458 (solo 108% of production, c2 103%,
                             # c4 78%, slope 0.593) and the battery campaign-20261024-142659
                             # (§2 gates ALL PASS, tool-eval 93/100 above stock's 92; hardmode
                             # 89 vs production's 91). The base revision stays in the caches;
                             # serve stock with MODEL_REVISION=078455ffe6472f9a52fbc1139f58b9db2881b25c.
                             # The original base revision comment: present in this
                             # site's HF caches on both hosts (see docs/SITE.md, not in git)

# The DFlash2 drafter (incoai's weights, CC BY-NC-ND 4.0 — non-commercial terms; production
# runs the same revision). DRAFTS=1 passes --drafter with this snapshot when it is present on
# the head (the EXL3 path upstream measured; give both ranks the same drafter); when the
# snapshot is missing the server drafts with the checkpoint's MTP head instead, with a warning.
# DRAFTS=0 still passes --no-drafts (the serial reference).
DFLASH2_ID="${DFLASH2_ID:-incoai/GLM-5.3-Flash-DFlash2}"
DFLASH2_REVISION="${DFLASH2_REVISION:-bf582e4eacc1810f76656d1811693ff6c6737d2a}"

# The two GB10s: this machine (the head) serves rank 0 and the API; WORKER (ssh target,
# key-based) runs rank 1. Rank 1 is started first, rank 0 serves HTTP (the native engine's
# rank-over-host pattern; docs/DELTAS.md). TP=3 is not servable on the native engine yet
# (it waits on upstream's multi-rank bootstrap fabric), so TP is fixed at 2.
TP=2
# Site identity — REQUIRED, set in scripts/local.sh (git-ignored; local.sh.example has the
# shape, docs/SITE.md on a prepared site has its real values — that file is not in git).
WORKER="${WORKER:-}"                     # rank 1's ssh target (key-based), e.g. user@worker-host

# The CX7 rails between the pair (one private subnet per cable — /24s are the easy choice;
# see local.sh.example for how to find the interfaces and assign the addresses). NCCL's
# bootstrap listens on the head's rail address; NCCL discovers the rest from there. With
# both rails cabled the default split exchange works and TF_GLM_PREFILL_REDUCE=gather is
# NOT needed (that is for fabrics where some rank pairs cannot connect).
HEAD_FABRIC_ADDR="${HEAD_FABRIC_ADDR:-}"      # the head's rail address (NCCL bootstraps here)
WORKER_FABRIC_ADDR="${WORKER_FABRIC_ADDR:-}"  # the worker's rail address
NCCL_PORT="${NCCL_PORT:-29741}"
# Comma-separated netdevs NCCL may use over the link (both rails on a two-rail site).
# NCCL_IB_HCA is left empty on purpose (all RoCE devices); set it in local.sh to pin devices.
NCCL_SOCKET_IFNAME="${NCCL_SOCKET_IFNAME:-}"
NCCL_IB_HCA="${NCCL_IB_HCA:-}"
# Extra NCCL debug, for a first bring-up: set NCCL_DEBUG=INFO in local.sh and watch the logs.

# Docker. The builder image compiles tensorfold-native (Zig + nvcc, sm_121); the runtime image
# carries the binary, its libraries and NCCL and is what both ranks run. The builder needs a
# CUDA devel base with nvcc for aarch64: nvcr.io/nvidia/pytorch:26.07-py3 is already pulled on
# the head and ships both, but any arm64 CUDA 13.x devel image works (set BASE_IMAGE).
ZIG_VERSION="${ZIG_VERSION:-0.17.0}"                     # TensorFold's .zig-version (still 0.17.0 at v1.1.0)
SM_ARCH="${SM_ARCH:-121}"                                # GB10
BASE_IMAGE="${BASE_IMAGE:-nvcr.io/nvidia/pytorch:26.07-py3}"
IMAGE_NAME="${IMAGE_NAME:-glm53-native-tf}"   # the runtime image; prepare.sh tags it <name>:<resolved version>
CONTAINER_NAME="${CONTAINER_NAME:-glm53-native-tf-test}"      # the -test suffix (the round-138 promotion fix): the PROMOTED production owns glm53-native-tf on port 8000 — the two stacks share this repo's scripts, so the testing stack MUST have its own name (the name-shared 12:15 window died on the prod_running guard firing on the testing stack itself). Production's own repo carries the unsuffixed name.

# Checkpoint and binary locations (host paths; the container mounts the HF cache read-write so
# the snapshot layout, blob names and hashes stay exactly as Hugging Face wrote them).
HF_CACHE="${HF_CACHE:-${HF_HOME:-$HOME/.cache/huggingface}}"
MODEL_SNAPSHOT="$HF_CACHE/hub/models--${MODEL_ID//\//--}/snapshots/$MODEL_REVISION"

# Serving. The defaults ARE the qualified optimum (2026-10-23 campaign receipts in
# docs/TOOL_EVAL_TESTING.md): dense4fp8 at the 524,288 window, 4 streams — all §2 gates
# PASS, tool-eval 92 (= the production-parity cell's), throughput leader, ~2 GiB cheaper
# than dense8. PARALLEL: 5 admits at 512K on window-mode fp8 (the engine's own arithmetic);
# the KV-pages branch admits 8 with paging but excludes fp8 KV — docs/ECOSYSTEM.md.
SERVED_NAME="${SERVED_NAME:-GLM-5.3-Flash-EXL3}"
HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-8001}"             # the TESTING stack's port — (user, round 117): tests never
                                 # serve on 8000 (production's, OpenCode's own endpoint — the
                                 # split keeps opencode traffic off the test instances and the
                                 # figures clean). Production still stops for GPU windows.
PROD_PORT="${PROD_PORT:-8000}"   # production's SERVING port (round 128 corrected, user): opencode is served there; production's PERF TESTS run on 8001 (the round-128 discipline) — the test flow toggles the tip's local.sh PORT 8001, restarts, probes, restores 8000, restarts. Never probe production on 8001 while it serves opencode on 8000.
                                 # (reference/prodqual/c4decomp-prod) address it here, always.
                                 # and the two stacks are mutually exclusive (start.sh's guard
                                 # refuses a busy port instead of fighting for it)
CONTEXT="${CONTEXT:-524288}"
PARALLEL="${PARALLEL:-4}"
DRAFTS="${DRAFTS:-1}"            # 0 passes --no-drafts (the serial reference); 1 drafts, with
                                 # DFlash2 when its snapshot is present (DFLASH2_* above), else MTP
RECALL="${RECALL:-0}"            # 1 passes --recall on the server (1.0.12): drafts copy from text
                                 # the server has already read; verified-exact, its own size cap.
                                 # For agent loops that re-read text (2.4-3x upstream on repeats)
VISION="${VISION:-1}"            # 1 passes --vision --vision-image-tokens 2048 (GLM-5.3-Flash
                                 # image input: data-URL image_url parts in user messages;
                                 # production's parity line: a 1.05 GiB tower with 1.41 GiB of
                                 # workspace, 2048 tokens a picture, 16384 a clip — the clip
                                 # cap is the engine's own). Needs libcublasLt.so.13 in the
                                 # image (the Dockerfile copies it from the builder's CUDA 13
                                 # toolkit — round 52's fix for the round-51 refusal). The
                                 # (user) call: vision is a want, enabled as a standing
                                 # default at the 524288 window; no perf testing.
PROMPT_CACHE_GIB="${PROMPT_CACHE_GIB:-}"  # --prompt-cache-gib on the server: the kept-states
                                 # store. Round 47 receipt: at this window (524288x4) the
                                 # engine served its own 2.6 GiB default EVEN WITH the flag
                                 # =16 in argv (campaign-20261028-113509/21-cachegib.md) —
                                 # budget-cap or ignored, unresolved; the store is NOT free
                                 # to grow here. --spill-gib (v1.1.8) is the alternative:
                                 # evict kept states to disk instead of dropping them.
CHAT_TEMPLATE="${CHAT_TEMPLATE:-effort-tail}"  # ADOPTED as the standing default (round 76, (user)):
                                  # the same-session A/B measured 92 -> 93 on hardmode and flipped
                                  # TC-92 (tenant isolation) fail->pass; TC-51 unchanged. The vision
                                  # template carries the same fix (round 77), so VISION=1 serves
                                  # effort-tail semantics inherently and this var only selects the
                                  # text-only template when VISION=0. Set CHAT_TEMPLATE= to revert
                                  # to the checkpoint's own top-hint template.
                                  # glm5-next-effort-tail.jinja: the effort hint moves from the
                                  # prompt top to just before the final assistant turn (NV forums
                                  # 381350 posts 915/933: at long context the top hint is ignored —
                                  # max reasoning 11-528 vs 1,900-7,000 tokens — and every effort
                                  # switch invalidates the whole prefix cache). Text-only A/B:
                                  # mutually exclusive with VISION=1 for now. Empty = the
                                  # checkpoint's own template (the standing default).
SPILL_GIB="${SPILL_GIB:-}"       # --spill-gib on the server (v1.1.8): evicted kept states
                                 # are written to disk (one I/O worker) instead of dropped
API_KEY="${API_KEY:-}"           # recommended; also required by upstream for --slide-style features
MEMORY_LIMIT_GB="${MEMORY_LIMIT_GB:-}"   # -> TENSORFOLD_CUDA_MEMORY_LIMIT_GB, empty: engine default

# Decode-side packing knobs (shipped in v1.1.0; 4, 6, 8 or 16 bits; empty = 16/bf16).
# The defaults are the measured optimum: dense4 is the speed leader at every depth
# (4 < 6 < 8 < 16 bits, monotonic — the v1.1.2+RoCE matrix) and dense4fp8 is the
# qualified serving config (all §2 gates PASS, tool-eval 92 = parity, throughput lead).
# Exactness holds within one configuration (drafted = plain there); packing is not
# bf16-exact, which is why each config's gates run on itself. PDL=1 turns on
# programmatic dependent launch on the mm kernels — it HURT dense4 in the matrix
# (−13/−11/−8% solo); keep 0.
DENSE_BITS="${DENSE_BITS:-4}"
HEAD_BITS="${HEAD_BITS:-4}"
PDL="${PDL:-0}"
# KV_CACHE: the latent cache's storage (config.sh → serve_args → --kv-cache). fp8 is
# v1.1.2's prepared fp8 latent cache and now the DEFAULT: the §2 exactness gates PASSED on
# it at 524288 (dense8+fp8 and dense4fp8, content form — VALIDATION §2 receipt), it halves
# per-stream KV bytes (the 512K ladder fits at 4–5 streams on it), and dense4fp8 is the
# qualified serving config. NOTE: fp8 KV + TF_KV_PAGES=on is the ADOPTED serving
# mode (the 1106 marriage + the pagerows/selist fixes — the elastic paged pool;
# hardmode 95 + the vision 4/4, the duel cleared, §2 gates PASS —
# campaign-20261106-043015/-052114/-054902; re-validated on the v1.2.3
# rebase by v123qual, campaign-20261106-065920). The ${VAR-default} form (no colon) makes the EMPTY spelling
# reachable: unset → fp8 (the standing default); KV_CACHE= (empty) → bf16
# explicitly (start.sh omits --kv-cache on empty — the "bf16" literal is not a
# legal value). The 233025/235800 windows burned on the ${:-} form treating
# empty as unset.
KV_CACHE="${KV_CACHE-fp8}"

# TF_KV_PAGES: the elastic paged KV pool (512-row pages shared across the
# streams — ~2.1M tokens at the 512K window). ADOPTED as the default (2026-11-06,
# round 133 cont. 65): the receipts-equal-or-better protocol satisfied on the
# 4-patch stack — the §2 gates (pagedgates, campaign-20261106-054902), the duel
# (duelpaged, campaign-20261106-052114: solo 108.5%, c2 above production's
# floor, c4 parity, ITL crossed 15.7 vs 17.1 ms/token, the cold depth 3.3×),
# hardmode 95 + the vision 4/4 (pagedquality3, campaign-20261106-043015 — the
# standing run's exact token profile, median turns 6.5% faster). The
# ${VAR-default} form: unset → on (the adopted mode); TF_KV_PAGES=off → the
# window-mode KV (the engine refuses an EMPTY value — always pass off).
# EXPORTED: env_args() forwards TF_KV_* from the ENVIRONMENT (env | grep) — an
# unexported shell assignment reaches the arg builder but never the container
# (the adoptsmoke smoke test caught exactly that: the bare start ran
# window-mode while config.sh said on).
export TF_KV_PAGES="${TF_KV_PAGES-on}"

# TF_KV_SHARE: the prompt cache's states live as POOL PAGES (the host
# store off) — a resume re-binds pages instead of copying from the host
# store. ADOPTED at 8 as TF_GLM_KV_SHARE (2026-11-06, round 133 cont. 74):
# kvshare2 (campaign-20261106-092703) held all four prefix states through
# the live streams (16 pool pages, zero eviction), the concurrent
# 4-prefix volley hit 4/4 (the aggregate 7.41 s vs the host store's
# 12.29 s — −40%; the per-request cost flat under concurrency — the
# round-123 serialization is the queue), and the host store's cascade
# eviction (each warm miss re-prefills and re-keeps, evicting the next
# state) disappears. kvsharequal (campaign-20261106-093921): §2 ALL PASS
# (g3 resumed=fresh — the resume path rides the pool pages), hardmode 95
# + the vision 4/4, total_tokens 662,693 byte-identical to the standing
# run's. The trade: the pool reserves 1025 pages (~3.4 GiB) for the store
# (4100 → 3075 free; the one-at-524288 guarantee unchanged).
# RENAMED BY v1.2.4 (round 135): upstream mainlined the store for every
# family as core's TF_KV_SHARE (kv_prompts.zig) and REFUSES the old
# TF_GLM_KV_SHARE name at startup (the first v124val window burned on
# exactly this — campaign-20261107-123013). The floor moved too:
# fewStates demands N ≥ 4×PARALLEL (v1.2.4's "4 states a GLM stream"),
# so 8 → 16 at the standing PARALLEL=4 — the v124val re-run receipts it.
# EXPORTED: env_args() forwards TF_KV_* from the environment (the
# cont. 66 lesson — an unexported assignment never reaches the container).
export TF_KV_SHARE="${TF_KV_SHARE-16}"

# PROMPT_K: v1.1.1 regroups prompt-projection K slices (one K slice at every operator row
# count), which can change replies versus 1.1.0 — including long or resumed prompts. "shape"
# selects K slices by shape instead (the 1.1.0 policy family); it needs TF_GLM_MM=1 on every
# rank, which is the engine default. Empty: 1.1.1's default.
PROMPT_K="${PROMPT_K:-}"

# PATCHES: optional overlay of local .patch files applied to the TensorFold tree at image
# build (see patches/README.md for the policy: upstream-first, receipts required, rebase
# cost owned). Empty = pristine upstream. Names are files in patches/, space or comma
# separated; prepare.sh stages them into the build.
# The qualified default (2026-10-24, (user)): 017-topk4b — the glm family's reference
# shape moves to topk=4 (the parse's `want` pin + the EXL3 experts' module global), which
# the top4cfg checkpoint requires. Receipts: perf campaign-20261024-135458 (solo 108% of
# production, c2 103%, c4 78%, slope 0.593) and the battery campaign-20261024-142659
# (§2 gates ALL PASS, tool-eval 93/100 above stock's 92, hardmode 89 vs production's 91).
# The names today are NNN-name.patch (round 139, user): the three-digit prefix IS the
# build's apply order — no more sort-duty naming; the next port takes the next free number.
PATCHES="${PATCHES-001-absorb-mma.patch 002-exl3prompt.patch 003-fp8-pages.patch 004-packed-s2.patch 005-pagerows-fix.patch 006-selist-fix.patch 007-attnfetch8.patch 008-loaddirect.patch 009-moeside.patch 010-tools256.patch 011-zclose.patch 012-zmoe-fuse.patch 013-zprompt.patch 014-zs2.patch 015-zshfl.patch 016-zstep.patch 018-callquote.patch}"   # the adopted optimum + the round-139 fifteenth patch glm-zz-tools256 — NAMED glm-zz-tools256- TO SORT BEFORE THE z- KERNEL PATCHES (tools256 < zstep; it touches no kernel file, so order-free) — the round-139 #256 port: the upstream PR #415 re-apply (issue #256, from the forum thread post 973) — a call to a tool the request did not offer goes out under its own name: tool_parse.callName takes the offered tool's spelling, else the call's own name when it is 1 to 64 of [A-Za-z0-9_-] and its arguments a finite JSON object (as vLLM's parsers do), so the client answers unknown tool and the model corrects itself; any other block stays text in both modes; bare JSON outside an envelope still needs an offered name (a structured answer); the fix is in v1.0.0..v1.2.1 and REVERTED before v1.2.2 — every 1.2.x including our promoted engine lacked it; the REST of the #415 rework (Policy.parsedContent/kept/wholeEnvelope/prose_sent/the attach rework) was already in our tree — only callName was reverted with it; the tools256qual A/B battery (campaign-20261108-140329, the 15-patch image on the testing port): the same-bits greedy witness IDENTICAL (the same 80cc3802… sha as every window — the fix must not move the deterministic probes), the §2 gates ALL PASS, hardmode 95 (the SIXTEENTH consecutive), the vision 4/4; the tool-parse host suite 46/46 PASS on the ported tree (the fix's primary witness); server-layer only, no kernel/record work — ADOPTED: the behavior IS the fix (no knob — an unoffered call is the client's to refuse); the promoted production repo's config carries the same fifteenth patch. The round-138 fourteenth patch glm-zz-zstep — NAMED glm-zz-zstep- TO SORT AFTER zshfl (zt > zh) — the fork's 0082 port: the 4-bit read-once chain as dependent launches (exl3r c3, on the adopted 0081 base: the decode chain's kernels — rot_in, the grouped experts, the gate/up epilogue, the down combine — launch with programmatic stream serialization, each launch and its prologue overlapping the predecessor; hazard rules as pdl5's: before griddepcontrol.wait only immutable loads and the plan; new kernels k8r8p/k8r16p, Load SHFL_PDL); TF_EXL3_PDL=0 turns it off (the fork's own knob, envOn default on); the 0082qual A/B (campaign-20261108-024926, both arms the SAME 14-patch image, the knob flips the path): the arms' greedy content IDENTICAL (the same 80cc3802… sha as every window — the fork's 108/108 exactness confirmed on the real model), the §2 gates ALL PASS, hardmode 95 (the FOURTEENTH consecutive), the vision 4/4, prefill flat (the bench pp d0 1,528, inside the band — the prefill row stands at the 0080qual crossing); and the fork's measured chain gain did NOT transfer to our shape — c2/c4/ITL/solo FLAT within the arm spread (the launch-COUNT reduction of 0030 transferred at concurrency; the launch-OVERLAP of the same kernels doesn't — the second decode-side non-transfer) — ADOPTED anyway: bit-safe, knobbed, neutral everywhere, and the fork's 0083+ builds on this exact base; the load walls unchanged (84/87 s); register-neutral confirmed on our sm_121 build (rot_in 19, gateup_epilogue 40, the p kernels 79 = the s kernels — no record work). The round-137 thirteenth patch glm-zz-zshfl — NAMED glm-zz-zshfl- TO SORT AFTER zs2 (zh > z2) — the fork's 0081 port: the 4-bit grouped experts read every trellis word once (exl3r: the grouped decode kernels' lanes each loaded the two words their windows span — every trellis word fetched twice, the fork's NCU 69-71 MB of L2 traffic for 33.7 MB of experts; now one 128-byte warp load a tile + __shfl_sync hand-off, the next tile issued a tile ahead (warp_tiles_shfl), the mcg mask in a register — 26 of the k step's 252 instructions were mask MOVs, now 216); same words, same A values, same MMA chain, same warp-order sum — the same bits; TF_EXL3_SHFL=0 restores the old choice (the fork's OWN knob, envOn default on); the 0081qual A/B (campaign-20261107-232039, both arms the SAME 13-patch image, the knob flips the path): the arms' greedy content IDENTICAL (the same 80cc3802… sha as every window), the §2 gates ALL PASS, hardmode 95 (the THIRTEENTH consecutive), the vision 4/4, prefill flat (the read-once kernels serve decode windows only), and the fork's measured decode gain did NOT transfer to our shape — the c2/c4/ITL/solo cells read FLAT within the arm spread (the L2-gather saving matters on their cold-expert trains, not our hot serving hierarchy) — ADOPTED anyway: bit-safe, knobbed, neutral on every instrument here, and the fork's 0082 (the chain as dependent launches) builds on this exact base; the load walls unchanged (84/87 s). The round-137 twelfth patch glm-zz-zs2 — NAMED glm-zz-zs2- TO SORT AFTER zprompt (zs > zp) — the fork's 0080 port: the packed prompt GEMMs' loads fixed once a block + 8-bit codes to bf16 pairs in fewer steps (mm_kernel's P2: each thread's cp.async sources/destinations/bounds worked out once a block — a stage adds its group's offset, the weights still load before griddepcontrol.wait — and bpairs8_fast: two codes spread into a bf16 pair's low bytes by two LOP3s, a − c = u − 128 by one bf16x2 subtraction that rounds nothing — the same values; the other glm_mm instances compile to the same SASS, P2=false default); TF_GLM_MM_P2=0 resolves the classic _128s2_cl twins (the pre-port instantiation verbatim, envOn default on); the 0080qual A/B (campaign-20261107-214342, both arms the SAME 12-patch image, the knob flips the path): the arms' greedy content IDENTICAL (the same 80cc3802… sha as every window), the §2 gates ALL PASS, hardmode 95 (the TWELFTH consecutive), the vision 4/4, **THE PREFILL FRONT CROSSED** — bench pp d0 1,519 vs production's 1,518 = 100.1% (the chain 1,458 → 1,468 → 1,495 → 1,519; the TTFT slope 0.448 → 0.441 = −1.6% agrees); decode flat within the arm spread; the load walls unchanged (86/89 s). The round-137 eleventh patch glm-zz-zprompt — NAMED glm-zz-zprompt- TO SORT AFTER zmoe-fuse (the .cu hunks assume the post-0030 experts file; zp > zm) — the fork's 0078+0079 port: the prompt experts' main loop reworked (exl3p: compiled for an item's 8-member column blocks NBA 1..8 — no predicate, no dead MMA; the next k tile's trellis decode issued among the current MMAs across the stage barrier (PS 4/3); each thread's cp.async pieces fixed per item (TLoads); the mcg mask one LOP3 (mcg2); 4-bit tiles from the lane's word and its neighbour's (decode_a8); fwht128 epilogues one FFMA per butterfly (fwht128f); Xd one 8-byte and y one 16-byte store) + the contract records re-measured per 0079 (gu 122/125/125/122/122, down 123/125/125/122/122 added — our sm_121 cuobjdump verified 122/122 on our own nvcc 13.3 build); TF_GLM_EXL3P=0 resolves the classic _cl kernel twins (the pre-port loop kept verbatim, envOn default on); the exl3pqual A/B (campaign-20261107-200411, both arms the SAME 11-patch image, the knob flips the path): the arms' greedy content IDENTICAL (the same 80cc3802… sha as every window — the same-bits claim), the §2 gates ALL PASS, hardmode 95 (the ELEVENTH consecutive), the vision 4/4, THE PREFILL LEVER REAL — bench pp d0 1,495 (the ON arm; the last three windows read 1,458-1,468) + the TTFT slope 0.458 → 0.447 (−2.4%) agree on ~2-2.5% whole-prefill (the front 96.0% → 98.5%); decode flat within the arm spread (c2/c4/ITL; the solo 68.5-vs-66.8 spread is run-order drift — the duel re-pair re-grounds it); the load walls unchanged (83/87 s). The round-136 tenth patch glm-zz-zmoe-fuse — NAMED glm-zz-zmoe- TO SORT AFTER moeside (the engine hunks assume the side field; the fork's 0030 followed its 0006) — the fork's 0030 port: a decode window's MoE glue fused (tf_glm_topk_group: the select + the compact picks + the EXL3 grouping in ONE 1024-thread block; the grouped experts core with NO slot-row copies — the two 2D copies, tf_exl3_group, put_slot and glue.combine GONE; the shared expert's row summed LAST in tf_exl3_down_combine, glue.combine's order, after the side stream's join) + the one-width grouped EXL3 decode tiles (grouped_body_v2: k6r8/k8r8 + nt4, tilesFor per projection reading our single Layer.uniform_k2) + KDA's f_b/g_b in one launch (glm_mm*_16x2); TF_GLM_MOE_FUSE=0 unfuses (envOn, the engine default ON — the switch ported from 0031, a TF_GLM_* getenv knob, no #2405 surface); the moefusequal A/B (campaign-20261107-172250, both arms the SAME 10-patch image, the knob flips the path): the arms' greedy content IDENTICAL (the same 80cc3802… sha as every window), the §2 gates ALL PASS, hardmode 95 (the TENTH consecutive), the vision 4/4, c4 166.1 vs the OFF arm's 159.4 (+4.2% — our best c4), c2 117.1 vs 115.9 (+1.0%), ITL 58.4 vs 59.3 ms/chunk (−1.5%), solo flat (67.7/67.4 vs 67.2/67.5), prefill flat (the prompt path untouched by design — the bench pp d0 1,468), the load walls unchanged (83/87 s). The round-135 ninth patch glm-zz-loaddirect (the image applies ALPHABETICALLY: attnfetch8 < loaddirect < moeside; loaddirect touches only cuda_load_ahead.zig so its position between them is free) — the GLM layer loads on v1.2.4's checkpoint.direct (the next layer read on the thread while one packs; TF_LOAD_DIRECT=0 keeps #1928's read-ahead; 23 shards < max_sources 64 so the path engages; the first v124val window burned on EXACTLY this omission — the patch existed in patches/ but never made this list, so the image built without it and the direct-reads witness counted 0, campaign-20261107-125114). The eight before it: (2026-11-07, round 134: cont. 100 the EIGHTH patch glm-zz-moeside — NAMED glm-zz- TO SORT AFTER THE STACK (the hunks assume the absorb-mma port's .absorb_mma field; the image applies patches alphabetically) — a decode window's MoE shared expert on a second stream beside the routed experts (the fork right after the block's input, the join before the slot combine; the kernels and the combine's order unchanged, the bits the same; TF_GLM_SHARED_SIDE=0 the kill switch; 0010's drain on error/teardown); hand-ported from Mia 1104 0006+0010 (our drift: the two Forward constructions carry .absorb_mma — .side added beside it; upstream's flashnext has the same pattern so the Stream/Event API matches); the content BIT-IDENTICAL everywhere incl. the 2048-token essay replies (campaign-20261107-083254), the steady-state probe RESOLVED (the off arm 51/51 s, both on-runs faster: 40.2→41.4 tok/s avg +3.0%, 4/4 sign-consistent — matching the claim's transfer math), the bench corroborating on the solo cells (+2.9%/+3.1%), §2 PASS + hardmode 95 (the SEVENTH consecutive) + the vision 4/4 (moesidequal, campaign-20261107-092913), the duel re-paired on the candidate (solo 65.9/66.2 vs 58.7/58.8 = 112.3% — +2.9% over the ATTN8 pair, two independent instruments agreeing, c2 113.1, c4 158.6); cont. 96 the SEVENTH patch glm-zz-attnfetch8 — NAMED glm-zz- TO SORT AFTER THE STACK: the image applies patches alphabetically and this port depends on the fp8-pages marriage's PAGED8 file state (the first attnpref window burned on exactly this) — the latent attention's FP8 key tiles load 8 bytes at a time, a tile ahead (the reads overlap QK/softmax/PV; the conversion moves to where load_kv(tile+2) stood; the shared-memory keys are the same bits — bit-order verified) + the 256-thread launch as the named contract CHUNK_THREADS; hand-ported from Mia 1104 0005+0011 (the fork's baseline predates the paged marriage — fetch8 folds our PAGED8 page-table addressing); the content BIT-IDENTICAL everywhere incl. the 2048-token decode replies (campaign-20261107-010849), bench pp +1.7/+3.6-4.3% and tg +2.9/+3.3/+4.7/+5.8/+10.9% at every depth cell, §2 PASS + hardmode 95 (the SIXTH consecutive) + the vision 4/4 (attnqual, campaign-20261107-020420), the duel re-paired on the candidate (solo 109.4% — beyond the instrument's 0.2% band, c4 +2.4%, the cold d8192 3,942 ms slope 0.458 = 434% of production's true cold, the prefill front 1,458 tok/s = 96.0%); cont. 89 the SIXTH patch glm-mia-exl3prompt — the EXL3 prompt path in ONE call a pass (chunk_rows follows prefill_rows: the trellis decodes once instead of twice, the bits unchanged) + the down kernel writing the MoE slot rows straight (the yrow ABI — the cuMemcpy2D of [rows][8][4096] fp32 per call dropped) + no target-MTP prompt absorption beside a drafter (the caches are never read with DFlash2 — a whole DSA+MoE layer a pass); hand-ported from Mia 1104 0007+0008 (the fork's hunks drifted; verified byte-identical to the port commit on a fresh v1.2.3 checkout); the content BIT-IDENTICAL across arms (campaign-20261106-201824), pp +24.5/+22.7/+23.3% at d0/d4096/d8192 — EXCEEDING Mia's +12.6-16% combined claim — §2 PASS + hardmode 95 (the FIFTH consecutive) + the vision 4/4 (exl3qual, campaign-20261106-212157), the duel re-paired on the candidate (solo 108.9%, the prefill front 1,150→1,434 tok/s = 94.4% of production, cold d8192 4,134 ms slope 0.482); cont. 86 the FIFTH patch glm-mia-packed-s2 — the two-stage packed-prompt matmuls, the content BIT-IDENTICAL across arms (campaign-20261106-174454), pp +3.4/+5.8/+6.7% at d0/d4096/d8192, §2 PASS + hardmode 95 + the vision 4/4 (mms2qual, campaign-20261106-185208), the duel re-paired on the candidate (solo 109.2%, cold d8192 5,034 ms slope 0.591); cont. 65 the 4-patch stack — re-anchored onto v1.2.3 cont. 67, re-validated by v123qual): the Mia-1104 ABSORB_MMA port + the fp8-pages marriage + the pagerows fix (the E4M3 Tables' page_rows) + the selist fix (the prefill's token lists stay logical — the loop bug; hardmode 95 + the vision 4/4, campaign-20261106-043015) — the cost tables DROPPED: the attribution duel campaign-20261105-000521 puts c2 at 110.4 with ABSORB-only vs 93.1 with the tables (campaign-20261104-234405) — the un-starved overhead learner costs the c2 aggregate ~16% on our shape and buys nothing measurable (the prefill identical: slope 0.602 in both duels; hardmode 95-with-tables vs the 94 control is within the instrument's scenario noise). ABSORB receipts: the deep fills -6.8/-7.0/-6.9% (campaign-20261104-213422), the small prompts -5-6% (campaign-20261104-233541), greedy byte-identical everywhere, the vision 4/4 (campaign-20261104-234405), the duel fronts solo 110% / cold 334% (campaign-20261105-000521). ${PATCHES-} (no colon): unset -> this default, EMPTY -> no patches (the opt-out; 017-topk4b.patch stays opt-in for the top4cfg/AZ cells)

# TEMPERATURE: the server's default sampling temperature (stock default 1.0). TensorFold
# drafts with DFlash2 on greedy (temperature 0) requests only — agent frameworks that send
# no temperature get the 1.0 default and no DFlash2 drafts (jayleaton's measured set:
# 4.36 -> 5.73 tokens/step, ~68 -> ~83 tok/s on the same hardware class with
# --temperature=0). Set 0 for agent serving; clients that send their own temperature are
# unaffected. Empty: the engine default.
TEMPERATURE="${TEMPERATURE:-}"

# VISION: 1 passes --vision (the checkpoint's vision tower serves images; rank 0 encodes,
# the others receive). VISION_IMAGE_TOKENS bounds the per-image token budget (--vision-image-tokens).
# UNQUALIFIED: no vision receipts exist on this line yet — the vision gate round
# (PERF_PLAN) validates before any default flips to 1. Empty: the engine default (off).
VISION="${VISION:-}"
VISION_IMAGE_TOKENS="${VISION_IMAGE_TOKENS:-}"

# CPU pinning for both ranks (as --cpuset-cpus on the containers). On a GB10 the engine's CUDA
# sync thread and NCCL's progress thread spin at ~100% CPU each and heat the CPU's thermal
# zones (five of seven ACPI zones are the CPU's), which a heat watch eventually punishes
# (ashhart/TensorFold#1033: as-shipped, a 40-reply run stopped at the 7th at 94.7 C; pinned to
# the efficiency cores it finished 40/40 at -1.1% decode / -2.7% prefill). This site's GB10s
# are the same 20-core SoC; the issue's map is 0-4,10-14. Empty: all cores (as shipped).
CPUSET="${CPUSET:-}"

# Runtime state: pidfiles, logs (each rank's docker log saved gzipped at stop, LOG_KEEP kept),
# and the prepared marker that start.sh compares to decide whether prepare.sh must run again.
STATE_DIR="${STATE_DIR:-$HOME/.local/state/glm53-native}"
LOG_DIR="${LOG_DIR:-$HOME/.cache/glm53-native/logs}"
LOG_KEEP="${LOG_KEEP:-10}"

# Colours only on a terminal.
_c() { [[ -t "$1" ]] && printf '\033[%sm' "$2" || true; }
log()  { printf '%s[%s]%s %s\n' "$(_c 1 '1;36')" "$(basename "$0")" "$(_c 1 0)" "$*"; }
warn() { printf '%s[%s] WARN:%s %s\n' "$(_c 2 '1;33')" "$(basename "$0")" "$(_c 2 0)" "$*" >&2; }
die()  { printf '%s[%s] ERROR:%s %s\n' "$(_c 2 '1;31')" "$(basename "$0")" "$(_c 2 0)" "$*" >&2; exit 1; }

worker() { ssh -o BatchMode=yes "$WORKER" "$@"; }  # args ARE the remote command (a bare ssh
                                                   # would eat our stdin as shell input)

# The docker run contract, shared by both ranks (the same as the EXL3 recipe's: host networking
# for the CX7 rails, the RDMA devices, locked memory for NCCL's registered buffers). The
# tensorfold-cache mount keeps the engine's file-digest cache (v1.1.0's #900) across restarts:
# without it every start re-reads the whole checkpoint for the byte verify — measured here at
# 624.8 s (163.6 GiB); with the cache a warm start skips it (0.1 s upstream).
RUN_ARGS=(--gpus all --ipc=host --network host --shm-size 16g --device /dev/infiniband
          --cap-add IPC_LOCK --ulimit memlock=-1 --ulimit stack=67108864
          -v "$STATE_DIR/tensorfold-cache:/root/.cache/tensorfold")
[[ -z "$CPUSET" ]] || RUN_ARGS+=(--cpuset-cpus "$CPUSET")

# Environment passed into both ranks: offline serving from the mounted cache, plus every
# TENSORFOLD_/TF_GLM_/NCCL_ variable this recipe sets.
env_args() {
  ENV_ARGS=(-e HF_HUB_OFFLINE=1 -e NCCL_SOCKET_IFNAME="$NCCL_SOCKET_IFNAME")
  [[ -z "$NCCL_IB_HCA" ]] || ENV_ARGS+=(-e NCCL_IB_HCA="$NCCL_IB_HCA")
  [[ -z "$MEMORY_LIMIT_GB" ]] || ENV_ARGS+=(-e TENSORFOLD_CUDA_MEMORY_LIMIT_GB="$MEMORY_LIMIT_GB")
  # Every other NCCL_* (channels, passthrough, debug), TENSORFOLD_*, TF_GLM_*, the engine's
  # TF_HEAT_* bands, the TF_ROCE_* gather settings and TF_KV_* (#1163's paging knob) pass
  # through to both ranks.
  while IFS='=' read -r name _; do ENV_ARGS+=(-e "$name=${!name}"); done \
    < <(env | grep -E '^(TENSORFOLD|TF_GLM|TF_HEAT|TF_ROCE|TF_KV|NCCL)_[A-Z0-9_]+=' || true)
}

# The serve arguments both ranks take (rank 0 adds --name/--host/--port in start.sh). The ranks
# must agree on window and streams: each allocates its own state before rank 0 admits.
serve_args() {
  local args=(serve "/root/.cache/huggingface/hub/models--${MODEL_ID//\//--}/snapshots/$MODEL_REVISION"
              --context "$CONTEXT" --parallel "$PARALLEL")
  [[ -z "$TEMPERATURE" ]] || args+=(--temperature "$TEMPERATURE")
  [[ -z "$KV_CACHE" ]] || args+=(--kv-cache "$KV_CACHE")
  # VISION=1: serve the checkpoint's vision tower (347 model.visual.* tensors; rank 0
  # encodes, the others receive). Unqualified until the vision gate round runs —
  # PERF_PLAN's vision section carries the plan.
  [[ "$VISION" != 1 ]] || args+=(--vision)
  [[ -z "$VISION_IMAGE_TOKENS" ]] || args+=(--vision-image-tokens "$VISION_IMAGE_TOKENS")
  if [[ "$DRAFTS" == 1 ]]; then
    local dflash="/root/.cache/huggingface/hub/models--${DFLASH2_ID//\//--}/snapshots/$DFLASH2_REVISION"
    if [[ -e "$HF_CACHE/hub/models--${DFLASH2_ID//\//--}/snapshots/$DFLASH2_REVISION/config.json" ]]; then
      args+=(--drafter "$dflash")   # the same folder on both ranks; the engine checks that
    else
      warn "DFlash2 snapshot $DFLASH2_REVISION missing on the head; drafts fall back to MTP"
    fi
  else
    args+=(--no-drafts)
  fi
  echo "${args[@]}"
}

# The prepared marker: a one-line description of everything a start depends on. start.sh re-runs
# prepare.sh whenever the config fingerprint no longer matches (a new upstream release, another
# revision, another worker, a different window or stream count).
config_line() {   # the fingerprint: everything except the resolved version
  echo "model=$MODEL_ID@$MODEL_REVISION worker=$WORKER context=$CONTEXT parallel=$PARALLEL head=$HEAD_FABRIC_ADDR patches=${PATCHES// /,}"
}
prepared_line() { # the fingerprint plus what prepare resolved (written to $STATE_DIR/prepared)
  echo "tf=$TF_RESOLVED_REF@$TF_RESOLVED_COMMIT image=$IMAGE_REF $(config_line)"
}

# --- optional knob exports (must sit after die's definition; before the site guard) ----------
# The engine reads the TF_GLM_ names directly; exporting here means local.sh can use the short
# forms and env_args' TENSORFOLD_/TF_GLM_ forwarding carries them into both ranks.
case "$KV_CACHE" in ""|fp8) ;; *) die "KV_CACHE must be empty (bf16, the engine default) or fp8 (v1.1.2's prepared latent cache; quality unqualified upstream)" ;; esac
case "$DENSE_BITS" in ""|4|6|8|16) ;; *) die "DENSE_BITS must be empty (engine default 16) or 4, 6 or 8" ;; esac
case "$HEAD_BITS" in ""|4|6|8|16) ;; *) die "HEAD_BITS must be empty (engine default 16) or 4, 6 or 8" ;; esac
[[ -z "$DENSE_BITS" ]] || export TF_GLM_DENSE_BITS="$DENSE_BITS"
[[ -z "$HEAD_BITS" ]] || export TF_GLM_HEAD_BITS="$HEAD_BITS"
[[ "$PDL" == 0 ]] || export TF_GLM_PDL="$PDL"
case "$PROMPT_K" in ""|shape) ;; *) die "PROMPT_K must be empty (v1.1.1 default) or shape" ;; esac
[[ -z "$PROMPT_K" ]] || export TF_GLM_PROMPT_K="$PROMPT_K"
# The DSA indexer's two dedicated CUDA kernels (#1449, v1.1.8): upstream's contract is
# byte-equal scoring; our receipts (rounds 47-48 — campaign-20261028-113509/20-indexdepth.md,
# campaign-20261028-141916/22-ixgates.md): cold-TTFT -2.6% at 131k → -5.5% at 393k with the
# off-arm slopes rising vs flat on-arm, §2 gates ALL PASS, the duel within noise, loading/
# decode/d0 unchanged. ADOPTED as the standing default (round 49); unset to compare.
export TF_GLM_INDEX_CUDA="${TF_GLM_INDEX_CUDA:-1}"
# ABSORB_MMA (the qualified optimum, 2026-11-04, round 133 cont. 16): a prompt pass's
# absorb_q and expand_v MLA matmuls run as head-batched bf16 tensor-core GEMMs with fp32
# sums (the Mia-1104 0041 port; the SIMT kernels keep decode windows). Receipts: the deep
# fills -6.8/-7.0/-6.9% (0.735/0.727/0.738 vs the standing 0.788/0.782/0.793 ms/tok at
# 43.7k/87.4k/174.8k — campaign-20261104-213422 deepfills; the fill-rate drop is itself
# the proof the MMA kernels ran), the small-prompt front clean (the resumecost rows on
# the patches-staged serve), greedy byte-identical (sha 9e04a49e5786), 93.9 s warm-cache
# boot, 13.9 GiB left. The fp32 summation ORDER differs from SIMT, hence the opt-out:
# TF_GLM_ABSORB_MMA=0. The numerics ride every rank fingerprint (layout 17): ranks that
# disagree refuse to start. Needs PATCHES (below) — the kernels ship in the overlay.
export TF_GLM_ABSORB_MMA="${TF_GLM_ABSORB_MMA:-1}"
# PROMPT_STEPS=0 (the qualified default, 2026-11-08, round 139 cont. 9): prompt
# passes run whole instead of stepping — the confirm receipt (campaign-20261108-214221,
# two independent restarts): c2 @ d8192 48.2/37.0 t/s vs the 17.3 baseline (the
# original knob-sweep lead was 33.1; the criterion "near 33 reproduces, near 17
# retires" is exceeded); d0 58.1/56.8 vs 49.9; d4096 c2 31.0/31.3 vs 24.0. The
# callquotequal bench on the same campaign (no steps0) read d8192 c2 23.8 — the
# delta attributes to the knob. Bit-safe: the port is a work-splitting change.
export TF_GLM_PROMPT_STEPS="${TF_GLM_PROMPT_STEPS:-0}"
case "$TEMPERATURE" in ""|*) [[ -z "$TEMPERATURE" ]] || [[ "$TEMPERATURE" =~ ^[0-9]+(\.[0-9]+)?$ ]] || die "TEMPERATURE must be a number (0 enables DFlash2 drafts on every request; empty: the engine default 1.0)" ;; esac

# --- site identity must be set (scripts/local.sh) -------------------------------------------
# Fail loudly rather than guessing a worker or a fabric address: a wrong guess rank-1s into
# nothing, or worse, onto the wrong host.
for _req in WORKER HEAD_FABRIC_ADDR WORKER_FABRIC_ADDR NCCL_SOCKET_IFNAME; do
  [[ -n "${!_req}" ]] || die "site setting $_req is empty — copy scripts/local.sh.example to
scripts/local.sh and fill it in (a prepared site's values are in docs/SITE.md, not in git)"
done
unset _req
