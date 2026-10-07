# Troubleshooting and uninstall

Start with the read-only diagnostic:

```bash
start doctor
start doctor --offline
start doctor --json
start status
```

The human output explains each check. JSON is intended for automation and uses
exit status `0` when no required check fails and `1` otherwise.

Use `status` to inspect effective policy without network access. Use offline
doctor when the host is intentionally disconnected; its skipped update-source
check is a warning, not a failure.

## Common failures

### `start: command not found`

Confirm `~/.local/bin` is on `PATH` and the symlink targets the installed file:

```bash
export PATH="$HOME/.local/bin:$PATH"
readlink -f "$HOME/.local/bin/start"
```

The expected default target is `$HOME/start.sh`. The installer refuses to
replace an existing unrelated `start` command; choose another `--bin-dir` or
move the conflicting command deliberately.

### OpenSSL exists but cannot run

An old user-local OpenSSL can appear on `PATH` while depending on missing shared
libraries. `start doctor` reports this separately from signature failure. Run
`command -v openssl` and `openssl version`, then repair or remove the broken
installation so a working system OpenSSL is selected. Do not disable signature
verification.

### Release metadata cannot be downloaded

The launcher keeps its installed version and continues an ordinary launch.
Check network/DNS access and `START_SH_UPDATE_URL`. A deterministic offline
launch can use `--no-update`; an explicit `start update` correctly returns a
failure until the source is available.

### Signature, key, format, or payload mismatch

Do not install the downloaded bytes manually. Confirm the configured update
source points at a harnessctl artifact root and compare the public-key
fingerprint in [SECURITY.md](../SECURITY.md). Reinstall from the immutable,
checksum-pinned bootstrap command in the README if the local launcher is not
trusted.

### Agent unavailable with `--no-agent-update`

Install the selected agent independently or remove `--no-agent-update` for an
interactive installation. Automatic Codex installation requires npm. Automatic
Claude installation requires access to the native installer.

The same failure is expected with
`START_SH_AGENT_UPDATE_POLICY=never`. `missing-only` permits installation only
when the agent is absent; it does not query an installed agent.

### An invocation checks the network unexpectedly

Run `start status` and inspect both update policies. Older installations with
no profile intentionally report `compatibility`, which retains the original
every-launch checks. Select `safe` with the authenticated installer or set
`START_SH_UPDATE_POLICY=never` and
`START_SH_AGENT_UPDATE_POLICY=never` for an offline host. For a one-off launch,
use both `--no-update` and `--no-agent-update`.

### `--resume last` says Herdr did not provide an ID

The installed launcher supports the handoff, but Herdr has not exported
`HERDR_RESUME_ID` in that pane. Copy the ID Herdr printed and use
`--resume ID`. `HERDR_SESSION` is not interchangeable; it names the Herdr/tmux
session rather than a Claude or Codex conversation.

### Launch opens in the wrong directory

Current releases use the caller's directory by default. Check for an old
`START_SH_WORKDIR` assignment in the config and use `-C /expected/project` to
make the target explicit. `start doctor` shows the resolved configured/default
directory.

### All tmux session names are in use

The bare-shell launcher uses `alpha` through `zulu`. Inspect sessions with
`tmux list-sessions`, attach to one that already exists, or deliberately close
an unused session. Invoking `start` inside tmux or Herdr does not allocate
another name.

### A source checkout will not update

This is intentional. The updater refuses to overwrite a tracked `start.sh`.
Use the installer to create a deployed copy outside the checkout, then run
`start update` there.

## Uninstall

Review each path before removing it, particularly if it predates harnessctl:

```bash
readlink -f "$HOME/.local/bin/start"
```

If the link resolves to `$HOME/start.sh`, remove that symlink and launcher.
Optionally remove `~/.config/harnessctl` if it contains no configuration you
want to keep, and `~/.local/state/harnessctl` to discard daily-check timestamps.
The default installation also uses `~/.tmux/tmux.conf` and
`~/.tmux/plugins`; these may contain pre-existing user configuration, so the
uninstaller does not own or remove them automatically.

```bash
rm "$HOME/.local/bin/start" "$HOME/start.sh"
```

Custom installations should remove the exact `--script-path` and `--bin-dir`
selected at install time. Uninstalling harnessctl does not uninstall Claude,
Codex, npm, tmux, or git.
