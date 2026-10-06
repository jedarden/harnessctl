# Architecture

`harnessctl` deliberately ships as one self-contained Bash launcher. The
installed file is normally `~/start.sh`; `~/.local/bin/start` is a symlink kept
for operator compatibility.

## Runtime flow

1. Source the selected user config file and parse the command line.
2. For an ordinary launch, fetch and authenticate signed release metadata.
3. If a newer semantic version exists, download it beside the installed file,
   verify its manifest hash and embedded version, check Bash syntax, replace it
   atomically, and re-exec with the original arguments.
4. Enter the caller/configured/CLI-selected working directory.
5. Resolve the selected agent, optionally install or update it, and build its
   argv without shell evaluation.
6. In Herdr or an existing tmux client, execute the agent directly. Otherwise,
   create a NATO-named tmux session and safely quote the argv sent to its shell.

`start update` stops after step 3. `start doctor` performs read-only checks and
does not run the update or agent-update paths.

## Source and generated files

| Path | Role |
| --- | --- |
| `start.sh` | Canonical launcher, trust anchor, and verifier implementation |
| `scripts/install.sh.in` | Canonical installer wrapper template |
| `install.sh` | Generated installer; do not edit directly |
| `start.sh.version` | Generated version file |
| `artifact-manifest.txt` | Signed artifact/version bindings for the current release |
| `artifact-manifest.sig` | Detached Transit signature for the current release |
| `keys/release-signing.pub` | Public verification key only |
| `releases/vVERSION/` | Immutable exact release artifacts |
| `scripts/release.py` | Generate, prepare, verify, sign in tests, and archive releases |

The installer embeds the same trust block and verification functions as the
launcher. `scripts/release.py generate` is the only supported way to refresh
the generated files.

## Trust boundaries

The initial installer is a bootstrap trust decision. Once the embedded key is
trusted, the detached signature authenticates the manifest, and the manifest
authenticates the launcher bytes and version. The raw GitHub mirror is a
distribution channel, not a trust anchor. Forgejo is the only writable Git
origin; GitHub is populated by its server-side mirror.

Production signing occurs in a protected Argo WorkflowTemplate. Preparation,
signing, verification, and publication run in ordered containers sharing a
temporary workspace. Only the signing container receives an OpenBao-audience
token, and the private key never leaves Transit.

## Configuration precedence

The process environment selects `START_SH_CONFIG`. That file is then sourced,
so assignments in it override incoming variables. CLI agent and workdir options
override their configured equivalents. Built-in defaults apply last when no
value is supplied.

The selected working directory is one invariant across launch contexts:

```text
-C/--workdir > START_SH_WORKDIR > caller's physical current directory
```

## Diagnostic contract

`start doctor --json` returns one object with schema
`harnessctl-doctor-v1`, launcher version, aggregate readiness, warning/failure
counts, and named checks. `pass` and `warn` do not cause a failing exit status;
`fail` does. Optional agents and network reachability are warnings because an
installed launcher can remain usable without them.
