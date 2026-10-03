# Harness Start

A self-updating `start` command for Claude Code and Codex. It creates a named
tmux session from a bare shell and runs directly inside an existing tmux or
herdr pane. Resume a coding session without remembering each agent's syntax.

Source of truth: [Forgejo](https://git.ardenone.com/jedarden/harness-start).
[GitHub](https://github.com/jedarden/harness-start) is a read-only release mirror.

## Install

Linux, Bash 4+, curl, OpenSSL, GNU coreutils, and git are supported. tmux is
needed for bare-shell launches. Codex installation additionally needs npm;
already-installed agents can run with `--no-agent-update`.

Download the installer from a pinned release and run it:

```bash
curl -fsSLo /tmp/harness-start-install.sh \
  https://raw.githubusercontent.com/jedarden/harness-start/main/releases/v1.4.0/install.sh
bash /tmp/harness-start-install.sh --source \
  https://raw.githubusercontent.com/jedarden/harness-start/main/releases/v1.4.0
```

The installer authenticates the release manifest using its embedded public key,
checks the launcher hash and version, and installs it atomically as `~/start.sh`
with a `~/.local/bin/start` symlink. Include `~/.local/bin` in your PATH.
Existing unrelated `start` commands and newer installed versions are preserved.
Use `--script-path PATH` and `--bin-dir DIR` for custom deployment locations.

## Use

```bash
start claude
start codex
start codex --resume SESSION_ID
start update
start --version
start codex --no-update --no-agent-update
```

Every ordinary launch checks for a newer signed launcher. Failed downloads or
verification preserve the installed file and allow the agent to launch.
`start update` updates only the launcher and returns a failing exit status when
verification or installation fails. It never starts or updates an agent.
`--no-update` skips launcher updates; `--no-agent-update` separately disables
agent installation and version lookups. Resume arguments survive update re-exec.
The updater refuses to replace tracked source files.

## Configure

Export variables or put them in `~/.config/harness-start/config.sh`:

```bash
START_SH_AGENT=codex
START_SH_PERMISSION_MODE=default
START_SH_CLAUDE_MODEL=sonnet
# Optional: START_SH_CODEX_MODEL=<model available to your account>
# Optional: START_SH_TMUX_CONF="$HOME/.tmux.conf"
# Optional: START_SH_WORKDIR="$HOME/projects"
```

`START_SH_CONFIG` selects another configuration file. `START_SH_AGENT` applies
when no agent argument is given. With no selection, an interactive shell prompts;
a noninteractive shell defaults to Claude. The default permission mode is
`bypass`, preserving the original dedicated-host launcher; `default` leaves the
selected agent's approval and sandbox configuration in effect. Claude defaults
to Sonnet; Codex uses its own configured model. The default working directory is
the deployed script's directory. `START_SH_UPDATE_URL` overrides distribution
while keeping pinned signature verification.

## Develop and release

```bash
python3 scripts/release.py generate
scripts/check.sh
```

The complete local gate covers signed update failures, atomic replacement,
installation, explicit updates, CLI dispatch, configuration, and real tmux
runtime. It uses disposable signed fixtures and does not contact a live signer.

Publish with the protected `harness-start-release-sign` WorkflowTemplate in
iad-ci using `expected-commit=<exact Forgejo main SHA>` and a forward semantic
`version`. It prepares, Transit-signs, verifies, archives, commits, and pushes
only to Forgejo. The server-side mirror publishes the same commit on GitHub.
Signing uses the existing non-exportable
`bootstrap-signing/bootstrap-rsa-2026-10` key for continuity with deployed hosts.
Private key material remains in OpenBao. Each `releases/vVERSION/` directory is
immutable. Roll back behavior by releasing older code under a higher version.

For an operator-held key or authenticated Transit environment, the same helper
also supports `prepare-unsigned VERSION`, `sign --key /secure/path/key.pem`,
`sign --transit-key MOUNT/KEY`, `check`, and `archive`.

Bootstrap migration and release operations are documented in
[the release notes](docs/notes/releases.md). The implementation plan is in
[docs/plan/plan.md](docs/plan/plan.md).
