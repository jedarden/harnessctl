# harnessctl

`harnessctl` installs one command, `start`, for launching Claude Code or Codex
consistently in a shell, tmux, or Herdr pane. It can resume sessions, keep its
signed launcher current, and avoid nested terminal multiplexers.

Forgejo is the [source of truth](https://git.ardenone.com/jedarden/harnessctl).
GitHub is a [read-only release mirror](https://github.com/jedarden/harnessctl).

## Install

Linux, Bash 4+, curl, OpenSSL, and GNU coreutils are required. A bare-shell
launch also needs tmux and git. Automatic Codex installation needs npm.

Bootstrap from the immutable v1.5.0 trust release:

```bash
curl -fsSLo /tmp/harnessctl-install.sh \
  https://raw.githubusercontent.com/jedarden/harnessctl/23d64163b2392d11b7d48ba68d3282d5676e36ec/releases/v1.5.0/install.sh
printf '%s  %s\n' \
  fcffc267de23c95f16ec4c5d2b0434cf3b1d50af217c25b51e78c791892a7bc7 \
  /tmp/harnessctl-install.sh | sha256sum -c -
bash /tmp/harnessctl-install.sh --source \
  https://raw.githubusercontent.com/jedarden/harnessctl/23d64163b2392d11b7d48ba68d3282d5676e36ec/releases/v1.5.0
```

That pinned installer authenticates the current signed release, installs
`~/start.sh`, and links `~/.local/bin/start`. It remains a stable bootstrap even
as newer releases ship. If needed:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

A fresh install selects the `safe` profile: normal agent approvals stay on,
the launcher checks daily, and an installed agent is not queried or upgraded.
Reinstalling over an existing launcher preserves its policy. Dedicated fleet
hosts can opt in explicitly:

```bash
bash /tmp/harnessctl-install.sh --source URL --profile fleet
```

See [Security](SECURITY.md) for the bootstrap trust boundary and key
fingerprint.

## Use

Run from the project you want the agent to open:

```bash
start claude
start codex
start codex -C ~/projects/example
```

Resume an exact session ID:

```bash
start claude --resume 4dcb6804-7929-4ae4-92c6-cb0cc43b8290
start codex --resume 019dbf76-c928-76b3-84b9-6d8b14fdb99c
```

When Herdr provides its last-harness metadata, this shorter form also selects
the recorded agent:

```bash
start --resume last
```

Pass native agent arguments after `--`; every value remains one argument even
through tmux:

```bash
start codex -C ~/projects/example -- --search
```

In a bare shell, `start` creates and attaches to the first free NATO-named tmux
session. Inside tmux or Herdr it executes the agent directly instead of nesting
another session. All three contexts use the caller directory unless `-C`,
`--workdir`, or configuration selects another one.

## Inspect and update

These commands do not launch an agent:

```bash
start status
start doctor --offline
start doctor
start update
```

`status` is local, read-only, and network-free. It shows the resolved profile,
permission/update policies, execution context, paths, and installed agents.
`doctor --offline` validates the host without checking the release service;
plain `doctor` additionally verifies the reachable signed manifest. Use
`--json` with either command for a stable automation interface.

For a one-off deterministic launch, regardless of configured policy:

```bash
start codex --no-update --no-agent-update -C /workspace/project
```

## Choose a policy

The installer owns a plain data file at
`~/.config/harnessctl/profile` containing `safe` or `fleet`.

| Profile | Agent permissions | Launcher checks | Agent checks |
| --- | --- | --- | --- |
| `safe` | normal approvals/sandbox | daily | install only when missing |
| `fleet` | bypass approvals/sandbox | every launch | every launch |
| no profile on an older host | legacy fleet-compatible behavior | every launch | every launch |

Change profiles deliberately by rerunning the authenticated installer with
`--profile safe` or `--profile fleet`. Fine-grained overrides and the complete
CLI are in the [reference](docs/reference.md).

## Documentation

- [Command and configuration reference](docs/reference.md)
- [Automation and JSON contracts](docs/automation.md)
- [Herdr integration](docs/herdr.md)
- [Troubleshooting and uninstall](docs/troubleshooting.md)
- [Architecture and trust flow](docs/architecture.md)
- [Security policy](SECURITY.md)
- [Contributing](CONTRIBUTING.md)
- [Release operations](docs/operations/releasing.md)
- [Changelog](CHANGELOG.md)
