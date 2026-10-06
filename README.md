# harnessctl

`harnessctl` installs the `start` command: a small Bash launcher for Claude
Code and Codex that updates itself, resumes sessions left by Herdr, and avoids
nesting tmux inside tmux or Herdr.

Forgejo is the [source of truth](https://git.ardenone.com/jedarden/harnessctl).
GitHub is a [read-only release mirror](https://github.com/jedarden/harnessctl).

## Before you run it

An ordinary `start` invocation has three deliberate side effects:

- It checks the configured source for a newer signed launcher. Use
  `--no-update` for a deterministic invocation.
- It installs or updates the selected coding agent. Use `--no-agent-update` to
  require an already-installed agent.
- For compatibility with the original launcher on dedicated hosts, its default
  permission mode is `bypass`. Set `START_SH_PERMISSION_MODE=default` to retain
  the agent's normal approval and sandbox behavior.

The launcher never replaces a tracked source file, an unrelated `start`
command, or a newer installed version.

## Install

The supported platform is Linux with Bash 4+, curl, OpenSSL, and GNU coreutils.
Bare-shell launches also need tmux and git. Automatic Codex installation needs
Node.js/npm; an already-installed Codex can run without npm.

Download the bootstrap installer from the immutable v1.4.0 release commit:

```bash
curl -fsSLo /tmp/harnessctl-install.sh \
  https://raw.githubusercontent.com/jedarden/harnessctl/f87ab1bf25a64a48320b288111c2b1e823580164/releases/v1.4.0/install.sh
printf '%s  %s\n' \
  c5b54e7445c1fa9fe3b65ce1c65baec49ee4eb9706fad3829fe3dd284e33bebe \
  /tmp/harnessctl-install.sh | sha256sum -c -
bash /tmp/harnessctl-install.sh --source \
  https://raw.githubusercontent.com/jedarden/harnessctl/f87ab1bf25a64a48320b288111c2b1e823580164/releases/v1.4.0
```

The initial installer is trusted through the immutable commit and checksum
above. Once running, its embedded public key authenticates the release
manifest, launcher hash, and launcher version before atomically installing
`~/start.sh` and linking `~/.local/bin/start`. The public-key DER SHA-256
fingerprint is
`f8e3bdf686cbdcbf5608276b2e63db734f64e9329cfaac7c12843826aee14080`.
Obtaining this README and checksum from the same compromised channel would not
provide independent bootstrap trust; see [SECURITY.md](SECURITY.md).

If needed, add the command to your shell path:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Adopt the latest signed release, then inspect the installation without changing
it:

```bash
start update
start doctor
```

Use `bash /tmp/harnessctl-install.sh --help` for custom `--script-path` and
`--bin-dir` destinations. Their environment equivalents are
`START_SH_INSTALL_PATH` and `START_SH_BIN_DIR`.

## Launch and resume

Run from the project directory you want the agent to use:

```bash
cd ~/projects/example
start claude
start codex
```

When a Herdr tab exits a coding harness, copy the session identifier Herdr
leaves in the pane and pass it back to the same harness:

```bash
start claude --resume 4dcb6804-7929-4ae4-92c6-cb0cc43b8290
start codex --resume 019dbf76-c928-76b3-84b9-6d8b14fdb99c
```

Quote session names containing spaces or shell characters. `start` translates
to the correct Claude or Codex resume syntax and preserves the argument if an
update restarts the launcher.

Use `-C` or `--workdir` when the caller is not already in the project:

```bash
start codex -C ~/projects/example
start claude --workdir ~/projects/example --resume SESSION_ID
```

| Context | Behavior | Working directory |
| --- | --- | --- |
| Bare shell | Creates the first free NATO-named tmux session and attaches | Caller directory or `-C` |
| Existing tmux | Runs the agent directly; no nested session | Caller directory or `-C` |
| Herdr pane | Runs the agent directly and leaves multiplexing to Herdr | Caller directory or `-C` |

## Command reference

| Command or option | Effect |
| --- | --- |
| `start claude`, `start codex` | Select and launch an agent |
| `--agent claude\|codex` | Long-form agent selection |
| `--resume ID` | Resume a Claude or Codex session |
| `-C DIR`, `--workdir DIR` | Launch from an explicit directory |
| `--no-update` | Skip the launcher update check |
| `--no-agent-update` | Do not install, update, or query the selected agent |
| `start update` | Update only the launcher |
| `start doctor [--json]` | Diagnose the installation; warnings do not fail |
| `start --version` | Print the installed launcher version |

`start doctor --json` emits the stable schema name `harnessctl-doctor-v1`.
Exit status is `0` when no required check fails and `1` otherwise. Warnings,
including an unavailable update service or an uninstalled optional agent, do
not make the diagnostic fail.

## Configuration

Export variables or put assignments in
`~/.config/harnessctl/config.sh`. The config file is sourced after incoming
environment variables; its assignments therefore take precedence. CLI agent
and workdir options take precedence over configuration.

| Variable | Default | Purpose |
| --- | --- | --- |
| `START_SH_AGENT` | prompt, or Claude without a TTY | `claude` or `codex` |
| `START_SH_PERMISSION_MODE` | `bypass` | `default` retains approvals/sandbox; `bypass` disables them |
| `START_SH_CLAUDE_MODEL` | `sonnet` | Claude model argument |
| `START_SH_CODEX_MODEL` | unset | Optional Codex model argument |
| `START_SH_WORKDIR` | caller directory | Launch directory when `-C` is absent |
| `START_SH_TMUX_CONF` | `~/.tmux/tmux.conf` for the default install | tmux configuration path |
| `START_SH_UPDATE_URL` | signed GitHub mirror | Alternate signed distribution root |
| `START_SH_CONFIG` | `$XDG_CONFIG_HOME/harnessctl/config.sh` | Alternate config file |

A safer personal-host configuration is:

```bash
mkdir -p ~/.config/harnessctl
printf '%s\n' \
  'START_SH_PERMISSION_MODE=default' \
  'START_SH_AGENT=codex' \
  > ~/.config/harnessctl/config.sh
```

## Automation and agents

Automation should select every behavior it depends on instead of relying on
interactive or fleet defaults:

```bash
start codex --no-update --no-agent-update -C /workspace/project
```

Run `start doctor --json` first when an agent needs to diagnose the host.
Treat check names as stable within the `harnessctl-doctor-v1` schema; consume
the `status` fields rather than parsing human prose.

## More documentation

- [Troubleshooting and uninstall](docs/troubleshooting.md)
- [Architecture and trust flow](docs/architecture.md)
- [Security policy and bootstrap trust](SECURITY.md)
- [Contributing and verification](CONTRIBUTING.md)
- [Release operations](docs/operations/releasing.md)
- [Changelog](CHANGELOG.md)
