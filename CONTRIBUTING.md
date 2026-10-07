# Contributing

Changes are made directly on `main`; Forgejo is the writable source of truth
and GitHub is its read-only mirror. Read [AGENTS.md](AGENTS.md) before editing.
If the checkout has an active bead store, create or select the owning bead
before changing repository files and record the affected paths and verification
there.

## Repository workflow

1. Inspect `git status --short` and preserve unrelated work.
2. Edit the canonical inputs. `start.sh` is the launcher;
   `scripts/install.sh.in` is the installer template.
3. Run `python3 scripts/release.py generate` after changing either canonical
   input. Never hand-edit generated `install.sh` or `start.sh.version`.
4. Run the focused test for the changed behavior, then `scripts/check.sh`.
5. Inspect the diff and stage only the paths owned by the change.
6. Commit to `main`, push only to Forgejo `origin`, and flush the bead
   checkpoint if needed.

Do not put a private signing key in this repository, a command line, a log, or
a test fixture committed to Git. Production signatures are created by OpenBao
Transit through the protected workflow described in
[the release runbook](docs/operations/releasing.md).

## Change and verification matrix

| Change | Focused verification | Additional action |
| --- | --- | --- |
| CLI parsing, resume, workdir | `bash tests/start-sh-interface-test.sh` | Update `--help` and README examples |
| Real tmux execution | `bash tests/start-sh-runtime-test.sh` | Confirm both Claude and Codex cases |
| Config variables/defaults | `bash tests/configuration-test.sh` | Update the reference configuration table |
| Profiles/update policies | `bash tests/configuration-test.sh` | Update reference and security docs |
| Status or doctor JSON | `bash tests/doctor-test.sh` | Keep v1 schemas additive or version them |
| Update/trust verification | `bash tests/start-sh-self-update-test.sh` | Regenerate the installer |
| Installer | `bash tests/install-update-test.sh` | Regenerate the installer |
| Release helper | `bash tests/release-test.sh` | Check archive immutability |
| Bootstrap bridge | `BOOTSTRAP_SOURCE=/clean/bootstrap scripts/check.sh` | Use a clean, signed bootstrap source |
| Any releaseable change | `scripts/check.sh` | Release only from a clean pushed commit |

The complete gate performs shell syntax checks, generated-file parity, offline
signed fixture tests, and real unprivileged tmux tests. It does not use the
production signer or modify an installed launcher.

## Compatibility rules

- Preserve exact resume arguments through tmux quoting and self-update re-exec.
- Bare shell, tmux, and Herdr must use the same requested working directory.
- Routine update failure must leave the installed launcher unchanged and allow
  an ordinary agent launch to continue. `start update` must fail explicitly.
- A source checkout must never self-update in place.
- Signed release archives are immutable. Correct a bad release with a higher
  semantic version.
- Key rotation requires a transition launcher that trusts old and new keys
  while the manifest is still signed by the old key.
- JSON diagnostics are an automation interface. Add fields compatibly; change
  or remove existing semantics only under a new schema name.
- `status` and offline doctor must remain network-free in launcher-owned code.
- A fresh install defaults to `safe`; updating an existing no-profile launcher
  must retain compatibility behavior until the operator chooses a profile.

## Definition of done

A change is complete when canonical and generated files agree, relevant docs
and tests cover the behavior, the complete gate passes, the owning bead records
the actual commands and outcomes, and the precise commit is pushed to Forgejo.
A user-visible launcher change is not deployed until a signed release is
published and its Forgejo/GitHub artifacts are verified.
