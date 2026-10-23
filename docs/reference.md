# Command and configuration reference

## Commands

```text
start [claude|codex] [OPTIONS] [-- AGENT_ARGS...]
start [claude|codex] resume ID [OPTIONS] [-- AGENT_ARGS...]
start update
start status [--json]
start doctor [--json] [--offline]
start --version
```

| Option | Meaning |
| --- | --- |
| `claude`, `codex` | Select the coding agent |
| `--agent NAME` | Long-form agent selection |
| `resume ID`, `--resume ID` | Resume an exact Claude or Codex session using the selected agent |
| `resume last`, `--resume last` | Consume `HERDR_RESUME_ID` and optional `HERDR_RESUME_AGENT` |
| `-C DIR`, `--workdir DIR` | Select the launch directory |
| `--no-update` | Skip launcher update work for this invocation |
| `--no-agent-update` | Require an installed agent without querying or changing it |
| `--force-capacity` | Override a failed or unavailable N+1 capacity check for one launch |
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
| `START_SH_CAPACITY_POLICY` | `enforce` (default), `off` | Require or disable the prelaunch capacity decision |
| `START_SH_AGENT_CPU_MILLICORES` | `1000` | CPU headroom required for the proposed agent |
| `START_SH_CPU_RESERVE_MILLICORES` | `0` | Extra CPU budget reserved for non-agent work |
| `START_SH_AGENT_MEMORY_MIB` | `1024` | Memory required for the proposed agent |
| `START_SH_MEMORY_RESERVE_MIB` | `512` | Memory kept free after the proposed launch |

`START_SH_PROFILE_PATH` selects the plain profile file before configuration is
sourced, so set it in the process environment rather than `config.sh`.

## Host inventory and launch capacity

`start status` scans live `/proc` processes across users and launch methods.
It counts exact `claude` and `codex` executables and the npm Node entrypoints
for those agents. Zombies, kernel threads, launcher shells, similarly named
helpers, and service modes such as `codex app-server` are excluded. The JSON `host.inventory` field gives PID, UID, agent,
counts, and whether the scan was complete; it does not expose command arguments.
When CCDash's existing SessionStart registry is available, a matching live PID
may also carry `session_id`. The launcher checks the agent type and process
start time before attaching that identity. Stale registry records do not count
as running agents, and agents without hooks remain visible through `/proc`.

Before dispatch, the launcher takes a fresh snapshot. It requires the host's
one-minute load average plus the proposed agent's CPU budget and configured
reserve to fit the effective CPU capacity. That capacity is the smallest
of online CPUs, process affinity, and available cgroup v2 quota/cpuset limits.
It also requires the proposed agent's memory budget plus the reserve to fit
the smaller of host `MemAvailable` and remaining cgroup v2 memory limits.
These are planning budgets, not measured per-process usage. By default a new
launch needs one CPU of headroom and 1 GiB plus 512 MiB free.
The load average is host-wide; for a small CPU-limited cgroup, unrelated host
load can make this check conservatively refuse a launch. Use the one-off
override after inspecting that cgroup's own utilization.
Unknown required metrics or an incomplete process scan refuse a launch. The
status command still succeeds and reports `host.capacity.ready=false` with a
reason. `--force-capacity` permits one launch after a failed check;
`START_SH_CAPACITY_POLICY=off` disables enforcement for a trusted host policy.
The snapshot is point-in-time and concurrent launches can race.
If the cgroup v2 mount or current cgroup cannot be inspected, the metrics are
treated as unavailable; cgroup v1 limits are not interpreted.

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
