# STAGE BRIEF — thinkoffval (the THINKING=0 server-default verify)

## The question

Does `THINKING=0` on the serve line flip the DEFAULT request's thinking
behavior on the real stack (v1.3.4 + the 17-patch store, the effort-tail
template, DFlash2), with the per-request override still winning both
directions? The issue-1 reporter's ask is a deployment-level default, not
just a per-request field; the knob landed in config.sh (commit dd7669f,
THINKING=1 the standing default, no behavior change).

## The engine ground (receipted in source, not assumed)

`--no-thinking` (cli.zig:81) → `args.thinking` →
`server_config.enable_thinking` (serve.zig:206). The request paths fall
back to the server default when a request says nothing: chat
(`chat.zig:172`, `fields.flag(f, "enable_thinking") orelse
srv.config.enable_thinking`) and anthropic (`anthropic.zig:52`). Request
fields win in both directions by construction.

## The value-if-yes

The deployment can choose its thinking default with one env var
(`THINKING=0`) — a documented config option that answers the issue. The
config.sh default stays 1; a promoted flip (production serving with
THINKING=0) would need its own quality battery (the receipts are measured
with thinking on) and is NOT this window's decision.

## The arms (the reasoning_tokens discriminator; greedy; the live probe's
receipted prompt)

- A. the standing arm (THINKING=1): the default request → reasoning > 0.
- B. THINKING=0: the same default request → reasoning == 0.
- C. THINKING=0 + `chat_template_kwargs.enable_thinking: true` →
  reasoning > 0 (the override wins ON).
- D. THINKING=0 + `thinking: false` → reasoning == 0 (the override wins
  OFF).
- E. g1 on the OFF arm: two identical greedy requests → content sha
  identical.

## The kill criteria

- B reasons → the flag never reached the default path; the knob is dead;
  the THINKING default stays 1; the defect question opens with the
  receipt.
- C does not reason → the override direction is broken; the knob is
  UNSAFE as a default (it traps clients that ask for thinking); the
  THINKING default stays 1; the defect question opens.
- ANY arm's boot refusal → the knob holds at 1 until understood.
- All green → the knob is a valid deployment option; the config default
  stays 1; the README documents the knob.

## The safety net

Every arm serves on the clean testing port 8001 (the window flow owns the
stop/restore of production; the phases never touch 8000). The standing arm
restores at the phase's end so the stack is left on the qualified default.
No quality/perf metric is read — this is a functional verify; the bench
grid is not run.

## The prior instrument

The pairexval window's shape (campaign-20261123-075710): the
order-matched multi-arm bracket with a named per-arm discriminator and a
kill criterion per arm — here the discriminator is the receipted
reasoning_tokens witness from the round-160 live probe
(results/thinkoff-probe/), not a perf cell.

## The desk check before the launch

- The knob reaches the binary: DRY_RUN with THINKING=0 prints
  `--no-thinking` on BOTH ranks' serve lines (verified 2026-11-23,
  commit dd7669f); the default arm prints none.
- The arms' inputs are distinct: A/B differ by the serve line's flag;
  C/D differ by the request body's thinking field. phase-lint's
  arm-distinctness class covers the staged arms.
- The engine's `server_config.enable_thinking` default is true, so the
  standing arm's behavior is unchanged by the knob's existence.

## The launch

`scripts/autonomous-launch.sh "preflight thinkoffval summary"` — last
action of the sitting; the window stops production, runs the arms on
8001, restores production on every exit path, and the poke wakes the
digest.
