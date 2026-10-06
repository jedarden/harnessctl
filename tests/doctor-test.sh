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
url=${!#}
cat "$FAKE_RELEASE/${url##*/}"
SH
chmod +x "$BIN_DIR/curl"

cat > "$CONFIG" <<SH
START_SH_PERMISSION_MODE=default
START_SH_UPDATE_URL=https://fixture.invalid
SH

fail() { echo "FAIL: $*" >&2; exit 1; }

echo 'Checking human and machine-readable diagnostics...'
output=$(
    cd "$CALLER_DIR"
    HOME="$HOME_DIR" \
    PATH="$HOME_DIR/.local/bin:$BIN_DIR:$PATH" \
    START_SH_CONFIG="$CONFIG" \
    FAKE_RELEASE="$TMP/release" \
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
    start doctor --json
)
DOCTOR_JSON="$json" CALLER_DIR="$CALLER_DIR" python3 - <<'PY'
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
assert checks["path"]["status"] == "pass"
assert checks["update-source"]["status"] == "pass"
PY
cmp "$HOME_DIR/start.sh" "$TMP/original-start.sh" || fail 'doctor changed the launcher'

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
