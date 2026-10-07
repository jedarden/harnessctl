# Command and configuration reference

## Commands

```text
start [claude|codex] [OPTIONS] [-- AGENT_ARGS...]
start update
start status [--json]
start doctor [--json] [--offline]
start --version
```

| Option | Meaning |
| --- | --- |
| `claude`, `codex` | Select the coding agent |
| `--agent NAME` | Long-form agent selection |
| `--resume ID` | Resume an exact Claude or Codex session |
| `--resume last` | Consume `HERDR_RESUME_ID` and optional `HERDR_RESUME_AGENT` |
| `-C DIR`, `--workdir DIR` | Select the launch directory |
| `--no-update` | Skip launcher update work for this invocation |
| `--no-agent-update` | Require an installed agent without querying or changing it |
| `-- AGENT_ARGS...` | Pass every remaining argument unchanged to the agent |
| `update` | Check and update the signed launcher, then exit |
| `status` | Report resolved local state without network or changes |
| `doctor` | Run read-only host and signed-source diagnostics |
| `--offline` | With `doctor`, omit the signed-source network check |
| `--json` | With `status` or `doctor`, emit one JSON object |

The CLI agent and workdir override configured values. Supplying both a
positional agent and a different `--agent` is an error. Arguments that belong
to Claude or Codex must follow `--` so the launcher does not interpret them.

Exit status `2` indicates invalid launcher arguments or configuration. A
launcher/installation failure returns nonzero. `doctor` returns `1` only when
at least one required check fails; warnings retain exit status `0`.

## Profiles

The profile file is `${XDG_CONFIG_HOME:-$HOME/.config}/harnessctl/profile` by
default. It is plain data and must contain exactly one line:

```text
safe
```

or:

```text
fleet
```

| Effective profile | Permission mode | Launcher update | Agent update |
| --- | --- | --- | --- |
| `safe` | `default` | `daily` | `missing-only` |
| `fleet` | `bypass` | `always` | `always` |
| `compatibility` (no file on an older install) | `bypass` | `always` | `always` |

The authenticated installer writes `safe` for a fresh install and preserves
an existing install by default. Its `--profile safe|fleet|preserve` option
makes the choice explicit. `compatibility` is reported by `start status`; it
is not a value accepted in the profile file.

## Configuration

The optional `${XDG_CONFIG_HOME:-$HOME/.config}/harnessctl/config.sh` is
sourced as arbitrary Bash. Only use a file you own and trust. It is not a
declarative parser. Its assignments override incoming environment variables;
CLI agent and workdir options override both.

| Variable | Allowed/default value | Purpose |
| --- | --- | --- |
| `START_SH_PROFILE` | `safe`, `fleet`; profile file or compatibility default | Override the selected profile |
| `START_SH_AGENT` | `claude`, `codex`; prompt or non-TTY Claude | Default agent |
| `START_SH_PERMISSION_MODE` | `default`, `bypass`; from profile | Agent approval/sandbox policy |
| `START_SH_UPDATE_POLICY` | `always`, `daily`, `never`; from profile | Automatic launcher check cadence |
| `START_SH_AGENT_UPDATE_POLICY` | `always`, `daily`, `missing-only`, `never`; from profile | Agent install/update cadence |
| `START_SH_CLAUDE_MODEL` | `sonnet` | Claude model argument |
| `START_SH_CODEX_MODEL` | unset | Optional Codex model argument |
| `START_SH_WORKDIR` | caller's physical directory | Default launch directory |
| `START_SH_TMUX_CONF` | `~/.tmux/tmux.conf` for a default install | tmux config path |
| `START_SH_UPDATE_URL` | signed GitHub mirror | Alternate signed artifact root |
| `START_SH_STATE_DIR` | `${XDG_STATE_HOME:-$HOME/.local/state}/harnessctl` | Daily-check timestamps |
| `START_SH_CONFIG` | default config path | Select the sourced config file |

`START_SH_PROFILE_PATH` selects the plain profile file before configuration is
sourced, so set it in the process environment rather than `config.sh`.

Example personal-host configuration:

```bash
mkdir -p ~/.config/harnessctl
printf '%s\n' safe > ~/.config/harnessctl/profile
chmod 600 ~/.config/harnessctl/profile
cat > ~/.config/harnessctl/config.sh <<'EOF'
START_SH_AGENT=codex
START_SH_CODEX_MODEL='custom-codex-model'
EOF
chmod 600 ~/.config/harnessctl/config.sh
```

## Update semantics

- `always` checks on every ordinary launch.
- `daily` performs at most one successful/attempted agent check per 24 hours;
  launcher timestamps are written only after signed metadata succeeds.
- `missing-only` installs the selected agent only when it is absent and never
  queries an installed copy.
- `never` performs no automatic network query and requires the selected agent
  to exist.
- `--no-update` and `--no-agent-update` override policy for one invocation.
- `start update` is explicit and ignores the automatic launcher cadence.

A tracked source checkout is never replaced in place. A failed routine
launcher check preserves installed bytes and continues; a failed explicit
`start update` returns nonzero.

## Installer options

Run the pinned installer with `--help` for its authoritative interface.

| Option | Environment equivalent |
| --- | --- |
| `--script-path PATH` | `START_SH_INSTALL_PATH` |
| `--bin-dir DIR` | `START_SH_BIN_DIR` |
| `--source URL` | none |
| `--profile safe|fleet|preserve` | `START_SH_INSTALL_PROFILE` |
| `--profile-path PATH` | `START_SH_PROFILE_PATH` |
