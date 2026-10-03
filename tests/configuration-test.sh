#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/harness-config.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/home/.config/harness-start" "$TMP/bin"
cp "$ROOT/start.sh" "$TMP/home/start.sh"
cat > "$TMP/bin/agent" <<'SH'
#!/usr/bin/env bash
printf '%s' "${0##*/}"
printf ' <%s>' "$@"
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
unset START_SH_CONFIG START_SH_CLAUDE_MODEL START_SH_CODEX_MODEL START_SH_PERMISSION_MODE START_SH_AGENT

echo 'Checking user configuration and disabled agent updates...'
cat > "$HOME/.config/harness-start/config.sh" <<'SH'
START_SH_AGENT=claude
START_SH_CLAUDE_MODEL='custom model'
START_SH_PERMISSION_MODE=default
SH
output=$("$HOME/start.sh" --no-update --no-agent-update --resume 'session with spaces' 2>&1)
[[ "$output" == *'claude <--model> <custom model> <--resume> <session with spaces>'* ]] || fail 'Claude configuration or resume quoting failed'
[[ "$output" != *dangerously* && "$output" != *'network lookup'* ]] || fail 'permission or update configuration was ignored'

cat > "$HOME/.config/harness-start/config.sh" <<'SH'
START_SH_AGENT=codex
START_SH_CODEX_MODEL='custom-codex-model'
START_SH_PERMISSION_MODE=default
SH
output=$("$HOME/start.sh" --no-update --no-agent-update --resume 'codex session' 2>&1)
[[ "$output" == *'codex <resume> <--model> <custom-codex-model> <codex session>'* ]] || fail 'Codex model or resume configuration failed'
[[ "$output" != *dangerously* ]] || fail 'Codex ignored permission mode'

echo 'Checking invalid configuration fails before launching...'
printf 'START_SH_PERMISSION_MODE=invalid\n' > "$HOME/.config/harness-start/config.sh"
if "$HOME/start.sh" codex --no-update --no-agent-update > "$TMP/error.log" 2>&1; then
    fail 'invalid permission mode was accepted'
fi
if "$HOME/start.sh" update codex > "$TMP/error.log" 2>&1; then fail 'update accepted agent arguments'; fi
echo 'Configuration tests passed.'
