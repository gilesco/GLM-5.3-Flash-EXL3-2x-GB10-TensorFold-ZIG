# STAGE BRIEF — the agent-traffic surface (the user's 2026-11-27
# direction: serving quality)

## The direction

The (user): "The agent-traffic surface is where I think we should go.
Serving quality is important." The queue's candidates (Mia 1104's
agent-traffic items) are ranked by LIVE failure class on OUR line, port
cost, and the user-visible number each could move.

## The desk evidence (this sitting, all read-only)

- **Our engine's stop-token list is a fixed 3 slots**
  (`config.zig:54`: `eos: [3]u32 = .{154820, 154827, 154829}`,
  `eos_n: u32 = 3`, the loader caps the array at 3), read from the
  checkpoint's `generation_config.json`. `<|assistant|>` is not among
  them. Our tree has NO equivalent knob (the EXTRA_EOS grep is empty).
- Mia's #36 (their 0120): GLM-5.3's `generation_config.json` leaves out
  `<|assistant|>`, which the model can write to close a reply; the
  token reaches the reply as text and the model writes its whole reply
  again until the length cap. Their fix: named tokens end a reply like
  the checkpoint's EOS ids; `EXTRA_EOS=none` keeps the checkpoint's
  list; a name the tokenizer does not hold refuses the start.
- Our checkpoint's `generation_config.json` (read from the served
  image): `eos_token_id: [154820, 154827, 154829]` — the same list, no
  `<|assistant|>`. The structural fact is IDENTICAL on our line.

## The ranked items

1. **EXTRA_EOS (their 0120) — FIRST.** Live failure class (the
   structural fact above), the smallest port of the set (the stop-list
   extension + one env knob), and the user-visible number: agent
   replies end at the model's own close token — no double-turn
   continuations. The reproduce-first probe comes before any port: a
   turn-end-eliciting prompt, greedy, on the testing port — minutes.
   If the failure does not reproduce on our template+checkpoint, the
   class is not live here and the item dies for the cost of one probe.
2. **The tool-call guard (their 0111/0116) — SECOND.** Bigger port
   (the parser + the streaming path + the host tests). Watch-triggered
   on OUR line's own malformed-tool-call evidence; the desk analysis
   (the async fault line, the PDL clue) is recorded in
   STAGE_BRIEF_bump-val.md's _cl section — different defect, same
   discipline.
3. **THINK_OFF_SPLIT (their 0121) — THIRD.** Opt-in, thinking-off
   only; our opencode traffic is thinking-on (the template's effort
   line), so the class is rare here. Last.
4. **The effort-line template discipline — PARKED.** Their QA gain
   (79.3% -> 86.0%) was on THEIR template shape (the Max line in
   every prompt); our line's template and quality gates differ and
   our hardmode is the quality measure here. No live failure class.

## The value-if-yes (the EXTRA_EOS window)

Agent replies on opencode traffic end at the model's own close token.
The user-visible number: double-turn continuations per day of agent
traffic — from whatever the reproduce probe shows to zero. The cost:
one member port against the promoted v1.3.6 tree (their 0120's shape,
the round-trip + compile gates), one window with the failure-replay
probe plus the standard coherence read.

## The kill criteria

- The reproduce probe does not elicit the failure on our line (the
  template's stop semantics may differ from their kit's) — the port
  is dropped, one probe spent.
- The port's off-state is not byte-identical on the greedy witness —
  the store gate refuses it before any window.
- The failure reproduces but the port changes the witness — the same
  refusal; the defect question opens instead.
