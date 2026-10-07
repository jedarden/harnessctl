#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/harness-install.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
python3 "$ROOT/tests/fixture.py" "$TMP/release"
mkdir -p "$TMP/bin" "$TMP/home with spaces"
export HOME="$TMP/home with spaces"
export PATH="$TMP/bin:$PATH" FAKE_RELEASE="$TMP/release" FAKE_AGENT_LOG="$TMP/agent.log"
export START_SH_CONFIG="$TMP/absent-config"
unset START_SH_INSTALL_PATH START_SH_BIN_DIR START_SH_UPDATE_URL
cat > "$TMP/bin/curl" <<'SH'
#!/usr/bin/env bash
url="${!#}"
name="${url##*/}"
[[ -z "${FAKE_DOWNLOAD_FAILURE:-}" ]] || exit 22
cat "$FAKE_RELEASE/$name"
SH
cat > "$TMP/bin/claude" <<'SH'
#!/usr/bin/env bash
echo "unexpected agent launch" >> "$FAKE_AGENT_LOG"
exit 99
SH
chmod +x "$TMP/bin/"*
fail() { echo "FAIL: $*" >&2; exit 1; }

echo 'Checking installer help and environment documentation...'
help=$(bash "$TMP/release/install.sh" --help)
[[ "$help" == *'--script-path PATH'* && "$help" == *'START_SH_INSTALL_PATH'* &&
   "$help" == *'--profile PROFILE'* && "$help" == *'START_SH_INSTALL_PROFILE'* ]] ||
    fail 'installer help omitted custom destination controls'

echo 'Checking authenticated install and PATH symlink with spaces...'
bash "$TMP/release/install.sh" > "$TMP/install.log"
cmp "$HOME/start.sh" "$TMP/release/start.sh"
[[ "$(readlink -f "$HOME/.local/bin/start")" == "$HOME/start.sh" ]] || fail 'installed link is wrong'
[[ -x "$HOME/start.sh" ]] || fail 'launcher is not executable'
[[ "$(<"$HOME/.config/harnessctl/profile")" == safe ]] || fail 'fresh install did not select the safe profile'
status=$("$HOME/.local/bin/start" status --json)
STATUS_JSON="$status" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ["STATUS_JSON"])
assert payload["schema"] == "harnessctl-status-v1"
assert payload["profile"] == "safe"
assert payload["permission_mode"] == "default"
assert payload["launcher_update_policy"] == "daily"
assert payload["agent_update_policy"] == "missing-only"
PY

echo 'Checking reinstall preserves policy unless explicitly changed...'
printf 'fleet\n' > "$HOME/.config/harnessctl/profile"
bash "$TMP/release/install.sh" > "$TMP/reinstall.log"
[[ "$(<"$HOME/.config/harnessctl/profile")" == fleet ]] || fail 'reinstall changed an existing profile'
bash "$TMP/release/install.sh" --profile safe > "$TMP/reinstall.log"
[[ "$(<"$HOME/.config/harnessctl/profile")" == safe ]] || fail 'explicit installer profile was ignored'

echo 'Checking explicit update without agent dispatch...'
sed -i 's/^START_SH_VERSION=".*"$/START_SH_VERSION="1.0.0"/' "$HOME/start.sh"
START_SH_UPDATE_URL=https://fixture.invalid "$HOME/.local/bin/start" update > "$TMP/update.log"
cmp "$HOME/start.sh" "$TMP/release/start.sh"
[[ ! -e "$FAKE_AGENT_LOG" ]] || fail 'explicit update launched an agent'

echo 'Checking signature, payload, and download failures preserve the installation...'
cp "$HOME/start.sh" "$TMP/installed"
cp "$TMP/release/artifact-manifest.sig" "$TMP/signature"
printf '%s\n' 'key_id=fixture-test' 'signature=AAAA' > "$TMP/release/artifact-manifest.sig"
if START_SH_UPDATE_URL=https://fixture.invalid "$HOME/.local/bin/start" update > "$TMP/error.log" 2>&1; then
    fail 'explicit update accepted an invalid signature'
fi
cmp "$HOME/start.sh" "$TMP/installed"
if bash "$TMP/release/install.sh" > "$TMP/error.log" 2>&1; then fail 'installer accepted an invalid signature'; fi
cmp "$HOME/start.sh" "$TMP/installed"
cp "$TMP/signature" "$TMP/release/artifact-manifest.sig"
cp "$TMP/release/start.sh" "$TMP/payload"
printf '\n# tampered\n' >> "$TMP/release/start.sh"
if bash "$TMP/release/install.sh" > "$TMP/error.log" 2>&1; then fail 'installer accepted a tampered payload'; fi
cmp "$HOME/start.sh" "$TMP/installed"
cp "$TMP/payload" "$TMP/release/start.sh"
if FAKE_DOWNLOAD_FAILURE=true bash "$TMP/release/install.sh" > "$TMP/error.log" 2>&1; then
    fail 'installer accepted an unavailable download'
fi
cmp "$HOME/start.sh" "$TMP/installed"

echo 'Checking an unusable OpenSSL is diagnosed before installation...'
printf '%s\n' '#!/usr/bin/env bash' 'exit 127' > "$TMP/bin/openssl"
chmod +x "$TMP/bin/openssl"
if bash "$TMP/release/install.sh" > "$TMP/error.log" 2>&1; then
    fail 'installer accepted an unusable OpenSSL'
fi
grep -Fq 'openssl exists but cannot run; check its shared libraries' "$TMP/error.log" ||
    fail 'installer did not explain the unusable OpenSSL failure'
cmp "$HOME/start.sh" "$TMP/installed"
rm "$TMP/bin/openssl"

echo 'Checking installer refuses downgrades and unrelated PATH commands...'
sed -i 's/^START_SH_VERSION=".*"$/START_SH_VERSION="99.0.0"/' "$HOME/start.sh"
cp "$HOME/start.sh" "$TMP/newer"
if bash "$TMP/release/install.sh" > "$TMP/error.log" 2>&1; then fail 'installer downgraded the launcher'; fi
cmp "$HOME/start.sh" "$TMP/newer"
mkdir "$TMP/conflicting-bin"
printf 'unrelated command\n' > "$TMP/conflicting-bin/start"
if bash "$TMP/release/install.sh" --bin-dir "$TMP/conflicting-bin" > "$TMP/error.log" 2>&1; then
    fail 'installer replaced an unrelated start command'
fi
[[ "$(cat "$TMP/conflicting-bin/start")" == 'unrelated command' ]] || fail 'unrelated command changed'

echo 'Checking custom deployment path and tracked-source protection...'
bash "$TMP/release/install.sh" --script-path "$TMP/custom/start.sh" --bin-dir "$TMP/custom/bin" > "$TMP/install.log"
cmp "$TMP/custom/start.sh" "$TMP/release/start.sh"
bash "$TMP/release/install.sh" --script-path "$TMP/custom-profile/start.sh" \
    --bin-dir "$TMP/custom-profile/bin" --profile fleet \
    --profile-path "$TMP/custom-profile/profile" > "$TMP/install.log"
[[ "$(<"$TMP/custom-profile/profile")" == fleet ]] || fail 'custom fleet profile was not written'
git -C "$TMP/release" init -q
git -C "$TMP/release" add start.sh
if "$TMP/release/start.sh" update > "$TMP/error.log" 2>&1; then fail 'updater replaced tracked source'; fi
if bash "$TMP/release/install.sh" --script-path "$TMP/release/start.sh" --bin-dir "$TMP/release/bin" > "$TMP/error.log" 2>&1; then
    fail 'installer replaced tracked source'
fi
[[ ! -e "$FAKE_AGENT_LOG" ]] || fail 'install or explicit update dispatched an agent'
echo 'Installer and explicit updater tests passed.'
