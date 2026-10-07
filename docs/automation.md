# Automation and agent integration

Automation should make launch side effects explicit and consume JSON instead
of human output.

## Deterministic launch

This form performs no launcher or agent network check and never prompts for an
agent or directory:

```bash
start codex --no-update --no-agent-update -C /workspace/project
```

Pass agent-native arguments only after the delimiter:

```bash
start codex --no-update --no-agent-update -C /workspace/project -- \
  --search
```

The launcher stores arguments in Bash arrays and shell-quotes each element only
at the tmux boundary. Do not pre-quote individual argument values.

## Local state

`start status --json` is read-only and makes no network request. It emits one
`harnessctl-status-v1` object and returns nonzero for invalid configuration.

```bash
start status --json | jq '{profile, permission_mode, context, installed}'
```

The checked-in [status schema](schemas/harnessctl-status-v1.schema.json)
defines required fields and enums. Within v1, fields may be added but existing
fields are not removed or redefined.

## Diagnostics

Use the offline form when network access is forbidden:

```bash
start doctor --offline --json
```

It preserves the `update-source` check with status `warn` and detail
`not checked (--offline)`, keeping the check-name contract stable. Without
`--offline`, doctor downloads and authenticates the release manifest but never
installs or updates anything.

The checked-in [doctor schema](schemas/harnessctl-doctor-v1.schema.json)
defines the response. Consumers should:

1. Confirm the top-level `schema` value.
2. Use `ok` or the process exit status for required readiness.
3. Index checks by `name` and branch on `status`.
4. Treat `detail` as human-facing text, not a machine protocol.
5. Ignore unknown fields and checks for forward compatibility.

## Side-effect matrix

| Invocation | Launcher network | Agent network/change | Launches agent | Changes launcher |
| --- | --- | --- | --- | --- |
| `start status [--json]` | no | no | no | no |
| `start doctor --offline [--json]` | no | no | no | no |
| `start doctor [--json]` | signed metadata | no | no | no |
| `start update` | signed metadata/artifact | no | no | if newer |
| `start AGENT --no-update --no-agent-update` | no | no | yes | no |
| ordinary `start AGENT` | according to policy | according to policy | yes | if signed newer release exists |

The sourced user config remains outside this matrix: because `config.sh` is
arbitrary trusted Bash, commands placed in it can have their own side effects.
