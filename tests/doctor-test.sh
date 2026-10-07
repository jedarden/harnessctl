#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/harness-doctor.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
python3 "$ROOT/tests/fixture.py" "$TMP/release"

HOME_DIR="$TMP/home"
BIN_DIR="$TMP/bin"
CALLER_DIR="$TMP/caller work"
CONFIG="$TMP/config.sh"
mkdir -p "$HOME_DIR/.local/bin" "$BIN_DIR" "$CALLER_DIR"
cp "$TMP/release/start.sh" "$HOME_DIR/start.sh"
chmod +x "$HOME_DIR/start.sh"
ln -s "$HOME_DIR/start.sh" "$HOME_DIR/.local/bin/start"
cp "$HOME_DIR/start.sh" "$TMP/original-start.sh"

cat > "$BIN_DIR/curl" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == --version ]]; then
    echo 'curl fixture 1.0.0'
    exit 0
fi
printf '%s\n' "${!#}" >> "$FAKE_CURL_LOG"
url=${!#}
cat "$FAKE_RELEASE/${url##*/}"
SH
chmod +x "$BIN_DIR/curl"

cat > "$CONFIG" <<SH
START_SH_PERMISSION_MODE=default
START_SH_UPDATE_URL=https://fixture.invalid
START_SH_CONFIG=$TMP/not-the-selected-config.sh
SH

fail() { echo "FAIL: $*" >&2; exit 1; }

echo 'Checking human and machine-readable diagnostics...'
output=$(
    cd "$CALLER_DIR"
    HOME="$HOME_DIR" \
    PATH="$HOME_DIR/.local/bin:$BIN_DIR:$PATH" \
    START_SH_CONFIG="$CONFIG" \
    FAKE_RELEASE="$TMP/release" \
    FAKE_CURL_LOG="$TMP/curl.log" \
    start doctor
)
[[ "$output" == *'PASS update-source'* ]] || fail 'human doctor output did not verify the signed update source'
[[ "$output" == *'Ready with '* ]] || fail 'human doctor output did not report readiness'

json=$(
    cd "$CALLER_DIR"
    HOME="$HOME_DIR" \
    PATH="$HOME_DIR/.local/bin:$BIN_DIR:$PATH" \
    START_SH_CONFIG="$CONFIG" \
    FAKE_RELEASE="$TMP/release" \
    FAKE_CURL_LOG="$TMP/curl.log" \
    start doctor --json
)
DOCTOR_JSON="$json" CALLER_DIR="$CALLER_DIR" CONFIG="$CONFIG" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ["DOCTOR_JSON"])
assert payload["schema"] == "harnessctl-doctor-v1"
assert payload["ok"] is True
checks = {item["name"]: item for item in payload["checks"]}
assert checks["workdir"] == {
    "name": "workdir",
    "status": "pass",
    "detail": os.environ["CALLER_DIR"],
}
assert checks["permissions"]["status"] == "pass"
assert checks["config"]["detail"].startswith(os.environ["CONFIG"])
assert checks["path"]["status"] == "pass"
assert checks["update-source"]["status"] == "pass"
PY
cmp "$HOME_DIR/start.sh" "$TMP/original-start.sh" || fail 'doctor changed the launcher'

echo 'Checking offline doctor and status do not contact the update source...'
network_calls=$(wc -l < "$TMP/curl.log")
offline=$(
    cd "$CALLER_DIR"
    HOME="$HOME_DIR" \
    PATH="$HOME_DIR/.local/bin:$BIN_DIR:$PATH" \
    START_SH_CONFIG="$CONFIG" \
    FAKE_RELEASE="$TMP/release" \
    FAKE_CURL_LOG="$TMP/curl.log" \
    start doctor --offline --json
)
[[ "$(wc -l < "$TMP/curl.log")" -eq "$network_calls" ]] || fail 'offline doctor contacted the update source'
DOCTOR_JSON="$offline" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ["DOCTOR_JSON"])
checks = {item["name"]: item for item in payload["checks"]}
assert checks["update-source"] == {
    "name": "update-source",
    "status": "warn",
    "detail": "not checked (--offline)",
}
PY

status_json=$(
    cd "$CALLER_DIR"
    HOME="$HOME_DIR" \
    PATH="$HOME_DIR/.local/bin:$BIN_DIR:$PATH" \
    START_SH_CONFIG="$CONFIG" \
    FAKE_RELEASE="$TMP/release" \
    FAKE_CURL_LOG="$TMP/curl.log" \
    HERDR_ENV= TMUX= \
    start status --json
)
[[ "$(wc -l < "$TMP/curl.log")" -eq "$network_calls" ]] || fail 'status contacted the update source'
STATUS_JSON="$status_json" CALLER_DIR="$CALLER_DIR" CONFIG="$CONFIG" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ["STATUS_JSON"])
assert payload["schema"] == "harnessctl-status-v1"
assert payload["profile"] == "compatibility"
assert payload["permission_mode"] == "default"
assert payload["launcher_update_policy"] == "always"
assert payload["agent_update_policy"] == "always"
assert payload["context"] == "bare"
assert payload["workdir"] == os.environ["CALLER_DIR"]
assert payload["config_path"] == os.environ["CONFIG"]
assert set(payload["installed"]) == {"claude", "codex"}
PY

echo 'Checking sourced-file mode warnings...'
chmod 0666 "$CONFIG"
insecure=$(
    cd "$CALLER_DIR"
    HOME="$HOME_DIR" \
    PATH="$HOME_DIR/.local/bin:$BIN_DIR:$PATH" \
    START_SH_CONFIG="$CONFIG" \
    FAKE_RELEASE="$TMP/release" \
    FAKE_CURL_LOG="$TMP/curl.log" \
    start doctor --offline --json
)
DOCTOR_JSON="$insecure" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ["DOCTOR_JSON"])
checks = {item["name"]: item for item in payload["checks"]}
assert checks["config"]["status"] == "warn"
assert "group/world writable" in checks["config"]["detail"]
PY
chmod 0644 "$CONFIG"

echo 'Checking functional dependency failures and doctor exit status...'
cat > "$BIN_DIR/openssl" <<'SH'
#!/usr/bin/env bash
exit 127
SH
chmod +x "$BIN_DIR/openssl"
status=0
json=$(
    cd "$CALLER_DIR"
    HOME="$HOME_DIR" \
    PATH="$HOME_DIR/.local/bin:$BIN_DIR:$PATH" \
    START_SH_CONFIG="$CONFIG" \
    FAKE_RELEASE="$TMP/release" \
    FAKE_CURL_LOG="$TMP/curl.log" \
    start doctor --json
) || status=$?
[[ "$status" -eq 1 ]] || fail "doctor returned $status instead of 1 for a required failure"
DOCTOR_JSON="$json" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ["DOCTOR_JSON"])
assert payload["ok"] is False
assert payload["failures"] >= 1
checks = {item["name"]: item for item in payload["checks"]}
assert checks["openssl"]["status"] == "fail"
assert checks["update-source"]["status"] == "warn"
assert "cannot run" in checks["update-source"]["detail"]
PY
cmp "$HOME_DIR/start.sh" "$TMP/original-start.sh" || fail 'failed doctor changed the launcher'

echo 'Doctor tests passed.'
