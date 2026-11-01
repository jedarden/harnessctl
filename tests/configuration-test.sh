#!/usr/bin/env bash
set -Eeuo pipefail
export START_SH_CAPACITY_POLICY=off # Configuration cases do not model host load.
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/harness-config.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/home/.config/harnessctl" "$TMP/bin"
cp "$ROOT/start.sh" "$TMP/home/start.sh"
cat > "$TMP/bin/agent" <<'SH'
#!/usr/bin/env bash
printf '%s' "${0##*/}"
printf ' <%s>' "$@"
printf ' pwd=<%s>' "$PWD"
printf '\n'
SH
cat > "$TMP/bin/curl" <<'SH'
#!/usr/bin/env bash
echo 'network lookup was unexpectedly attempted' >&2
exit 99
SH
chmod +x "$TMP/bin/"*
ln -s agent "$TMP/bin/claude"
ln -s agent "$TMP/bin/codex"
fail() { echo "FAIL: $*" >&2; exit 1; }
export HOME="$TMP/home" PATH="$TMP/bin:$PATH" HERDR_ENV=configuration-test
unset START_SH_CONFIG START_SH_CLAUDE_MODEL START_SH_CLAUDE_EFFORT START_SH_CODEX_MODEL START_SH_CODEX_EFFORT
unset START_SH_PERMISSION_MODE START_SH_AGENT

echo 'Checking user configuration and disabled agent updates...'
mkdir -p "$TMP/configured work"
cat > "$HOME/.config/harnessctl/config.sh" <<'SH'
START_SH_AGENT=claude
START_SH_CLAUDE_MODEL='custom model'
START_SH_PERMISSION_MODE=default
SH
printf 'START_SH_WORKDIR=%q\n' "$TMP/configured work" >> "$HOME/.config/harnessctl/config.sh"
output=$("$HOME/start.sh" --no-update --no-agent-update --resume 'session with spaces' 2>&1)
[[ "$output" == *'claude <--model> <custom model> <--effort> <high> <--resume> <session with spaces>'* ]] || fail 'Claude configuration or resume quoting failed'
[[ "$output" == *'pwd=<'"$TMP"'/configured work>'* ]] || fail 'configured workdir was not applied to direct launch'
[[ "$output" != *dangerously* && "$output" != *'network lookup'* ]] || fail 'permission or update configuration was ignored'

cat > "$HOME/.config/harnessctl/config.sh" <<'SH'
START_SH_AGENT=codex
START_SH_CODEX_MODEL='custom-codex-model'
START_SH_PERMISSION_MODE=default
SH
output=$("$HOME/start.sh" --no-update --no-agent-update --resume 'codex session' 2>&1)
[[ "$output" == *'codex <resume> <--model> <custom-codex-model> <-c> <model_reasoning_effort="high"> <codex session>'* ]] || fail 'Codex model or resume configuration failed'
[[ "$output" != *dangerously* ]] || fail 'Codex ignored permission mode'

echo 'Checking safe/fleet profiles and deterministic update policies...'
rm -f "$HOME/.config/harnessctl/config.sh"
printf 'safe\n' > "$HOME/.config/harnessctl/profile"
output=$(START_SH_AGENT=codex "$HOME/start.sh" --no-update 2>&1)
[[ "$output" == *'codex <--model> <gpt-6.1-sol> <-c> <model_reasoning_effort="high"> pwd=<'* ]] || fail 'safe profile did not launch the installed agent'
[[ "$output" != *dangerously* && "$output" != *'network lookup'* ]] ||
    fail 'safe profile bypassed permissions or updated an already-installed agent'

printf 'fleet\n' > "$HOME/.config/harnessctl/profile"
output=$(START_SH_AGENT=codex "$HOME/start.sh" --no-update --no-agent-update 2>&1)
[[ "$output" == *'codex <--dangerously-bypass-approvals-and-sandbox>'* ]] ||
    fail 'fleet profile did not preserve permission bypass'

mkdir -p "$HOME/.local/state/harnessctl"
date +%s > "$HOME/.local/state/harnessctl/launcher-update"
date +%s > "$HOME/.local/state/harnessctl/agent-codex-update"
output=$(
    START_SH_AGENT=codex \
    START_SH_PERMISSION_MODE=default \
    START_SH_UPDATE_POLICY=daily \
    START_SH_AGENT_UPDATE_POLICY=daily \
    "$HOME/start.sh" 2>&1
)
[[ "$output" == *'codex <--model> <gpt-6.1-sol> <-c> <model_reasoning_effort="high"> pwd=<'* && "$output" != *'network lookup'* ]] ||
    fail 'fresh daily policy state did not provide a network-free launch'

output=$(
    START_SH_AGENT=codex \
    START_SH_PERMISSION_MODE=default \
    START_SH_UPDATE_POLICY=never \
    START_SH_AGENT_UPDATE_POLICY=never \
    "$HOME/start.sh" 2>&1
)
[[ "$output" == *'codex <--model> <gpt-6.1-sol> <-c> <model_reasoning_effort="high"> pwd=<'* && "$output" != *'network lookup'* ]] ||
    fail 'never policies contacted the network'

echo 'Checking model and effort defaults and overrides...'
launch() { START_SH_PERMISSION_MODE=default "$HOME/start.sh" "$1" --no-update --no-agent-update "${@:2}" 2>&1; }
rm -f "$HOME/.config/harnessctl/config.sh"
output=$(launch claude)
[[ "$output" == *'claude <--model> <claude-opus-5-5> <--effort> <high> pwd=<'* ]] || fail 'Claude defaults changed'
output=$(launch codex)
[[ "$output" == *'codex <--model> <gpt-6.1-sol> <-c> <model_reasoning_effort="high"> pwd=<'* ]] ||
    fail 'Codex defaults changed'

cat > "$HOME/.config/harnessctl/config.sh" <<'SH'
START_SH_CLAUDE_EFFORT=low
START_SH_CODEX_EFFORT=xhigh
SH
output=$(launch claude)
[[ "$output" == *'claude <--model> <claude-opus-5-5> <--effort> <low> pwd=<'* ]] || fail 'Claude effort was not configurable'
output=$(launch codex)
[[ "$output" == *'codex <--model> <gpt-6.1-sol> <-c> <model_reasoning_effort="xhigh"> pwd=<'* ]] ||
    fail 'Codex effort was not configurable'

cat > "$HOME/.config/harnessctl/config.sh" <<'SH'
START_SH_CLAUDE_MODEL=
START_SH_CLAUDE_EFFORT=
START_SH_CODEX_MODEL=
START_SH_CODEX_EFFORT=
SH
output=$(launch claude)
[[ "$output" == *'claude <> pwd=<'* ]] || fail 'empty Claude settings did not defer to agent configuration'
output=$(launch codex)
[[ "$output" == *'codex <> pwd=<'* ]] || fail 'empty Codex settings did not defer to agent configuration'

rm -f "$HOME/.config/harnessctl/config.sh"
for form in '--model other' '--model=other' '-m other' '-mother'; do
    read -r -a model_args <<< "$form"
    output=$(launch codex -- "${model_args[@]}")
    [[ "$output" != *'<gpt-6.1-sol>'* ]] || fail "Codex default model was repeated beside: $form"
    [[ "$output" == *'<-c> <model_reasoning_effort="high">'* ]] || fail "Codex effort was lost beside: $form"
done
output=$(launch codex -- --search 'prompt about --model')
[[ "$output" == *'<--model> <gpt-6.1-sol>'* ]] || fail 'Codex default model yielded to an unrelated argument'
output=$(launch claude -- --effort low)
[[ "$output" == *'<--effort> <high> <--effort> <low> pwd=<'* ]] || fail 'Claude pass-through effort did not follow the default'

echo 'Checking invalid configuration fails before launching...'
printf 'unsafe\n' > "$HOME/.config/harnessctl/profile"
if "$HOME/start.sh" status > "$TMP/error.log" 2>&1; then fail 'invalid profile file was accepted'; fi
grep -Fq 'profile must contain exactly one line: safe or fleet' "$TMP/error.log" ||
    fail 'invalid profile error was not actionable'
printf 'fleet\n' > "$HOME/.config/harnessctl/profile"
printf 'START_SH_PERMISSION_MODE=invalid\n' > "$HOME/.config/harnessctl/config.sh"
if "$HOME/start.sh" codex --no-update --no-agent-update > "$TMP/error.log" 2>&1; then
    fail 'invalid permission mode was accepted'
fi
if "$HOME/start.sh" update codex > "$TMP/error.log" 2>&1; then fail 'update accepted agent arguments'; fi
printf 'START_SH_UPDATE_POLICY=sometimes\n' > "$HOME/.config/harnessctl/config.sh"
if "$HOME/start.sh" codex > "$TMP/error.log" 2>&1; then fail 'invalid update policy was accepted'; fi
cat > "$HOME/.config/harnessctl/config.sh" <<'SH'
START_SH_CODEX_EFFORT='high" x'
SH
if "$HOME/start.sh" codex --no-update --no-agent-update > "$TMP/error.log" 2>&1; then
    fail 'invalid Codex effort was accepted'
fi
grep -Fq 'START_SH_CODEX_EFFORT must be empty or one lowercase word' "$TMP/error.log" ||
    fail 'invalid effort error was not actionable'
echo 'Configuration tests passed.'
