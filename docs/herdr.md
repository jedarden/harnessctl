# Herdr integration

Herdr already owns the terminal pane and multiplexer. When `HERDR_ENV` is
nonempty, `start` executes the selected coding agent in the current pane and
does not create or attach another tmux session.

## Resume contract

An exact session identifier always works:

```bash
start claude --resume SESSION_ID
start codex --resume SESSION_ID
```

For one-command recovery after a harness exits, Herdr can export:

| Variable | Required | Meaning |
| --- | --- | --- |
| `HERDR_RESUME_ID` | yes for `--resume last` | Opaque Claude or Codex session identifier |
| `HERDR_RESUME_AGENT` | no | `claude` or `codex`; selects the matching agent when none was requested |

Then the pane can run:

```bash
start --resume last
```

The identifier is treated as one inert argument. If Herdr omits it, `start`
fails with an instruction to pass the copied ID explicitly. If the selected
agent conflicts with `HERDR_RESUME_AGENT`, it fails instead of opening the ID
with the wrong harness.

`HERDR_RESUME_ID` is intentionally distinct from `HERDR_SESSION`: the latter
identifies Herdr's own multiplexer session, not the coding harness conversation.
Herdr should clear or replace resume metadata when a new harness starts so a
stale identifier is never presented as the last exited harness.

## Recommended pane handoff

1. Record the harness kind and opaque session ID when the child exits.
2. Export both resume variables only in the pane where they apply.
3. Render `start --resume last` as the recovery command.
4. Preserve the pane's project directory; `start` otherwise uses its current
   physical directory.
5. Clear metadata after the resumed process starts successfully or a newer
   harness exits.

Until Herdr exports this metadata, use the exact ID that it leaves in the pane.
