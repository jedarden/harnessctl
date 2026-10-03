# Harness Start

`start.sh` is the canonical, self-contained Bash launcher. It is derived from
bootstrap commit 32993be and supports Claude Code and Codex, tmux, and herdr.
Work on main and push only to Forgejo origin. Preserve concurrent edits.

Every change belongs to an owning bead. This repository uses bead-rs (`bead`).
Keep verification and deployment evidence on that bead and flush its checkpoint.

`install.sh` is generated from `scripts/install.sh.in` and the launcher's pinned
trust anchor and verification functions. Run `python3 scripts/release.py generate`
after editing either input. `keys/release-signing.pub` contains only the public
key. Private release keys remain in OpenBao Transit.

Run `scripts/check.sh` for the complete local gate: shell syntax, generated
installer parity, offline updater/installer/interface/configuration tests, and
real tmux runtime tests. Test artifacts live in the physical scratch directory.
When run as root in CI, the gate runs the tmux runtime tests as `nobody` using
`runuser` and a disposable directory under `/tmp`.
`python3 scripts/release.py check` additionally authenticates a prepared release.

Publish through declarative-config's protected `harness-start-release-sign`
WorkflowTemplate in iad-ci. No GitHub Actions, client-side mirror pushes, or
direct managed-resource changes. Never change immutable release archives.
Bootstrap adoption belongs to this application's owning bead and uses
`scripts/adopt-bootstrap.sh`; it preserves bootstrap's own distribution URL.
