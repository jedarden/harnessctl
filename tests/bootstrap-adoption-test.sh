#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/harness-adoption.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
python3 "$ROOT/tests/fixture.py" "$TMP/release"
python3 "$TMP/release/scripts/release.py" prepare-unsigned 99.0.0
python3 "$TMP/release/scripts/release.py" sign --key "$TMP/test-signing.pem"
BOOTSTRAP_SOURCE="${BOOTSTRAP_SOURCE:?Set BOOTSTRAP_SOURCE to a local bootstrap repository}"
echo 'Checking signed bootstrap adoption preserves both distribution URLs...'
mkdir "$TMP/bootstrap"
git -C "$BOOTSTRAP_SOURCE" archive origin/main hosts/ex44 scripts README.md | tar -x -C "$TMP/bootstrap"
cp "$TMP/release/keys/release-signing.pub" "$TMP/bootstrap/hosts/ex44/keys/bootstrap-artifacts-signing.pub"
git -C "$TMP/bootstrap" init -q -b main
printf '/hosts/ex44/bootstrap-*.sh\n' > "$TMP/bootstrap/.gitignore"
current=$(cat "$TMP/bootstrap/hosts/ex44/start.sh.version")
printf '!/hosts/ex44/bootstrap-%s.sh\n' "$current" >> "$TMP/bootstrap/.gitignore"
git -C "$TMP/bootstrap" add .gitignore scripts README.md hosts/ex44
git -C "$TMP/bootstrap" -c user.name=jedarden -c user.email=github@jedarden.com commit -qm 'test: bootstrap adoption fixture'
current=$(cat "$TMP/bootstrap/hosts/ex44/start.sh.version")
IFS=. read -r major minor patch <<< "$current"
next="$major.$minor.$((patch + 1))"
cp "$ROOT/scripts/adopt-bootstrap.sh" "$TMP/release/scripts/adopt-bootstrap.sh"
bash "$TMP/release/scripts/adopt-bootstrap.sh" "$TMP/bootstrap" "$next"
ARTIFACT_SIGNING_KEY="$TMP/test-signing.pem" "$TMP/bootstrap/scripts/start-sh-release.sh" manifest "$next"
"$TMP/bootstrap/scripts/start-sh-release.sh" --check > "$TMP/check.log"
python3 - "$TMP/bootstrap" <<'PY'
from pathlib import Path
import re
import sys
host = Path(sys.argv[1]) / 'hosts/ex44'
launcher = (host / 'start.sh').read_text()
bootstrap = (host / 'bootstrap.sh').read_text()
old = 'https://raw.githubusercontent.com/jedarden/bootstrap/main/hosts/ex44'
new = 'https://raw.githubusercontent.com/jedarden/harness-start/main'
assert re.search(r'^REPO_URL="([^"]+)"$', launcher, re.M).group(1) == old
assert re.search(r'^REPO_URL="([^"]+)"$', bootstrap, re.M).group(1) == old
assert f'UPDATE_REPO_URL="${{START_SH_UPDATE_URL:-{new}}}"' in launcher
PY
echo 'Checking dirty bootstrap checkout is rejected...'
if bash "$TMP/release/scripts/adopt-bootstrap.sh" "$TMP/bootstrap" "$major.$minor.$((patch + 2))" > "$TMP/error.log" 2>&1; then
    echo 'FAIL: adoption modified a dirty checkout' >&2; exit 1
fi
echo 'Release and bootstrap adoption tests passed.'
