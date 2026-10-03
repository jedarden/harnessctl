#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/harness-release.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
python3 "$ROOT/tests/fixture.py" "$TMP/release"
release="$TMP/release/scripts/release.py"
echo 'Checking forward release preparation, signing, and immutable archives...'
python3 "$release" prepare-unsigned 99.0.0
python3 "$release" sign --key "$TMP/test-signing.pem"
python3 "$release" check
python3 "$release" archive
cmp "$TMP/release/start.sh" "$TMP/release/releases/v99.0.0/start.sh"
if python3 "$release" prepare-unsigned 99.0.0 > "$TMP/error.log" 2>&1; then
    echo 'FAIL: release helper accepted a non-forward version' >&2; exit 1
fi
if python3 "$release" archive > "$TMP/error.log" 2>&1; then
    echo 'FAIL: release helper overwrote an immutable archive' >&2; exit 1
fi
printf '\n# tampered\n' >> "$TMP/release/start.sh"
if python3 "$release" check > "$TMP/error.log" 2>&1; then
    echo 'FAIL: release helper accepted source/manifest drift' >&2; exit 1
fi
cp "$TMP/release/releases/v99.0.0/start.sh" "$TMP/release/start.sh"

echo 'Release tooling tests passed.'
