#!/usr/bin/env bash
set -Eeuo pipefail

# Exercise start.sh's self-update path with local command doubles. The real
# launcher is copied into a disposable HOME so every case can inspect whether
# a failed update left the working file usable and unchanged.

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
START_SH="$ROOT/start.sh"
CURRENT_VERSION=$(sed -n 's/^START_SH_VERSION="\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)"$/\1/p' "$START_SH")
[[ -n "$CURRENT_VERSION" ]] || {
    echo "FAIL: could not read the committed launcher version" >&2
    exit 1
}
IFS=. read -r CURRENT_MAJOR CURRENT_MINOR CURRENT_PATCH <<< "$CURRENT_VERSION"
HIGHER_VERSION="$CURRENT_MAJOR.$CURRENT_MINOR.$((CURRENT_PATCH + 1))"
BASH_BIN_DIR=$(dirname "$(command -v bash)")
OPENSSL_BIN_DIR=$(dirname "$(command -v openssl)")
TMP=$(mktemp -d "${TMPDIR:-/tmp}/start-sh-self-update.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
python3 "$ROOT/tests/fixture.py" "$TMP/release"
ROOT="$TMP/release"
START_SH="$ROOT/start.sh"
WRONG_FORMAT_MANIFEST="$TMP/wrong-format-manifest.txt"
WRONG_FORMAT_SIGNATURE="$TMP/wrong-format-manifest.sig"
sed 's/^format=.*/format=another-artifact-protocol-v1/' \
    "$ROOT/artifact-manifest.txt" > "$WRONG_FORMAT_MANIFEST"
printf '%s\n' 'key_id=fixture-test' > "$WRONG_FORMAT_SIGNATURE"
printf 'signature=' >> "$WRONG_FORMAT_SIGNATURE"
openssl dgst -sha256 -sign "$TMP/test-signing.pem" "$WRONG_FORMAT_MANIFEST" | \
    base64 -w 0 >> "$WRONG_FORMAT_SIGNATURE"
printf '\n' >> "$WRONG_FORMAT_SIGNATURE"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_contains() {
    local expected=$1 actual=$2 description=$3
    [[ "$actual" == *"$expected"* ]] || fail "$description (missing $(printf '%q' "$expected"))"
}

assert_file_contains() {
    local expected=$1 path=$2 description=$3
    grep -Fq -- "$expected" "$path" || fail "$description (missing $(printf '%q' "$expected") in $path)"
}

assert_file_not_contains() {
    local unexpected=$1 path=$2 description=$3
    ! grep -Fq -- "$unexpected" "$path" || fail "$description (found $(printf '%q' "$unexpected") in $path)"
}

assert_unchanged() {
    cmp -s "$LAUNCHER" "$ORIGINAL" || fail "${1:-launcher changed unexpectedly}"
}

assert_no_update_temps() {
    local leftovers
    leftovers=$(find "$CASE_HOME" -maxdepth 1 \
        \( -name "$(basename "$LAUNCHER").tmp.*" -o \
           -name "$(basename "$LAUNCHER").manifest.*" \) -print)
    [[ -z "$leftovers" ]] || fail "temporary self-update files were not cleaned up: $leftovers"
}

setup_case() {
    local name=$1 mode=$2 installed_version=${3:-1.0.0}

    CASE_ROOT="$TMP/$name"
    CASE_HOME="$CASE_ROOT/home"
    FAKE_BIN="$CASE_ROOT/bin"
    LAUNCHER="$CASE_HOME/start.sh"
    ORIGINAL="$CASE_ROOT/original-start.sh"
    PAYLOAD_FILE="$CASE_ROOT/remote-start.sh"
    STALE_PAYLOAD_FILE="$CASE_ROOT/stale-start.sh"
    CURL_LOG="$CASE_ROOT/curl.log"
    MV_LOG="$CASE_ROOT/mv.log"

    mkdir -p "$CASE_HOME" "$FAKE_BIN"
    cp "$START_SH" "$LAUNCHER"
    sed -i "s/^START_SH_VERSION=\"[0-9][0-9]*\\.[0-9][0-9]*\\.[0-9][0-9]*\"$/START_SH_VERSION=\"$installed_version\"/" "$LAUNCHER"
    chmod +x "$LAUNCHER"
    cp "$LAUNCHER" "$ORIGINAL"

    # The valid payload is the signed committed launcher. The stale fixture
    # has the right syntax but an older internal version and must be rejected.
    cp "$START_SH" "$PAYLOAD_FILE"
    cp "$PAYLOAD_FILE" "$STALE_PAYLOAD_FILE"
    sed -i 's/^START_SH_VERSION="[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*"$/START_SH_VERSION="0.9.0"/' "$STALE_PAYLOAD_FILE"
    chmod +x "$PAYLOAD_FILE"

    # curl serves the committed signed manifest or the selected launcher
    # payload. Unknown URLs intentionally fail so the normal agent-version
    # check cannot reach the network during this test.
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'url="${!#}"' \
        'printf "%s\\n" "$url" >> "$FAKE_CURL_LOG"' \
        'case "$url" in' \
        '  */artifact-manifest.txt)' \
        '    case "$FAKE_CURL_MODE" in' \
        '      version-unavailable) exit 22 ;;' \
        '      version-malformed) printf "%s\\n" "not-a-manifest" ;;' \
        '      manifest-tampered) sed "s/^version=.*/version=9.9.9/" "$FAKE_MANIFEST_FILE" ;;' \
        '      signed-wrong-format) cat "$FAKE_WRONG_FORMAT_MANIFEST" ;;' \
        '      *) cat "$FAKE_MANIFEST_FILE" ;;' \
        '    esac' \
        '    ;;' \
        '  */artifact-manifest.sig)' \
        '    case "$FAKE_CURL_MODE" in' \
        '      version-unavailable|version-malformed) exit 22 ;;' \
        '      manifest-tampered) cat "$FAKE_SIGNATURE_FILE" | sed "s/^signature=.*/signature=AAAA/" ;;' \
        '      signed-wrong-format) cat "$FAKE_WRONG_FORMAT_SIGNATURE" ;;' \
        '      *) cat "$FAKE_SIGNATURE_FILE" ;;' \
        '    esac' \
        '    ;;' \
        '  */start.sh)' \
        '    case "$FAKE_CURL_MODE" in' \
        '      payload-unavailable) exit 22 ;;' \
        '      payload-empty) : ;;' \
        '      payload-interrupted) printf "%s\\n" "#!/usr/bin/env bash" "START_SH_VERSION=\\\"1.3.1\\\""; exit 18 ;;' \
        '      payload-malformed) printf "%s\\n" "#!/usr/bin/env bash" "if (" ;;' \
        '      payload-tampered) sed "s/START_SH_VERSION/START_SH_VERSION_TAMPERED/" "$FAKE_PAYLOAD_FILE" ;;' \
        '      payload-stale) cat "$FAKE_STALE_PAYLOAD_FILE" ;;' \
        '      *) cat "$FAKE_PAYLOAD_FILE" ;;' \
        '    esac' \
        '    ;;' \
        '  *) exit 22 ;;' \
        'esac' > "$FAKE_BIN/curl"
    chmod +x "$FAKE_BIN/curl"

    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'if [[ "${1:-}" == --version ]]; then' \
        '    printf "%s\\n" "claude 1.0.0"' \
        'else' \
        '    printf "AGENT_LAUNCHED"' \
        '    printf " %s" "$@"' \
        '    printf "\\n"' \
        'fi' > "$FAKE_BIN/claude"
    chmod +x "$FAKE_BIN/claude"

    # Record the replacement operation and optionally fail it. A valid update
    # must use one same-directory mv, rather than streaming into SELF_PATH.
    local mv_command
    mv_command=$(command -v mv)
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'printf "args=%s\\nsource=%s\\ntarget=%s\\n" "$*" "${2:-}" "${3:-}" > "$FAKE_MV_LOG"' \
        'if [[ "$FAKE_MV_FAILURE" == true ]]; then exit 1; fi' \
        "exec \"$mv_command\" \"\$@\"" > "$FAKE_BIN/mv"
    chmod +x "$FAKE_BIN/mv"

    CASE_MODE="$mode"
}

run_case() {
    local name=$1 mode=$2 installed_version=${3:-1.0.0}
    setup_case "$name" "$mode" "$installed_version"

    local output
    if ! output=$(
        HOME="$CASE_HOME" \
        PATH="$FAKE_BIN:$BASH_BIN_DIR:$OPENSSL_BIN_DIR:/usr/local/bin:/usr/bin:/bin" \
        HERDR_ENV=self-update-test \
        FAKE_CURL_MODE="$CASE_MODE" \
        FAKE_CURL_LOG="$CURL_LOG" \
        FAKE_PAYLOAD_FILE="$PAYLOAD_FILE" \
        FAKE_STALE_PAYLOAD_FILE="$STALE_PAYLOAD_FILE" \
        FAKE_MANIFEST_FILE="$ROOT/artifact-manifest.txt" \
        FAKE_SIGNATURE_FILE="$ROOT/artifact-manifest.sig" \
        FAKE_WRONG_FORMAT_MANIFEST="$WRONG_FORMAT_MANIFEST" \
        FAKE_WRONG_FORMAT_SIGNATURE="$WRONG_FORMAT_SIGNATURE" \
        FAKE_MV_LOG="$MV_LOG" \
        FAKE_MV_FAILURE=false \
        "$LAUNCHER" --agent claude 2>&1
    ); then
        printf '%s\n' "$output" >&2
        fail "$name launcher invocation failed"
    fi

    CASE_OUTPUT="$output"
}

echo 'Checking tmux OOM hardening in the standalone launcher...'
for launcher in "$START_SH"; do
    assert_file_contains \
        'sudo -n choom -n -1000 -p "$SERVER_PID"' \
        "$launcher" \
        'tmux server OOM protection drifted'
    assert_file_contains \
        'set -g history-limit 2000' \
        "$launcher" \
        'tmux history limit drifted'
    assert_file_contains \
        'AGENT_ARGV+=(--model "${START_SH_CLAUDE_MODEL:-sonnet}")' \
        "$launcher" \
        'Claude model pin drifted'
    assert_file_not_contains \
        'set -g history-limit 10000' \
        "$launcher" \
        'legacy tmux history limit was reintroduced'
done

echo 'Checking successful authenticated update and atomic replacement...'
run_case success success
assert_contains 'AGENT_LAUNCHED --dangerously-skip-permissions --model sonnet' "$CASE_OUTPUT" \
    'successful update did not re-exec the fetched launcher with original flags'
cmp -s "$LAUNCHER" "$PAYLOAD_FILE" || fail 'successful update did not install the fetched payload'
[[ -x "$LAUNCHER" ]] || fail 'successful update did not preserve launcher executability'
[[ -f "$MV_LOG" ]] || fail 'successful update did not replace through mv'
source_path=$(sed -n 's/^source=//p' "$MV_LOG")
target_path=$(sed -n 's/^target=//p' "$MV_LOG")
[[ "$target_path" == "$LAUNCHER" ]] || fail 'atomic replacement targeted the wrong launcher'
[[ "$source_path" == "$LAUNCHER.tmp."* ]] || fail 'replacement source was not a launcher-local temporary file'
[[ "$(dirname "$source_path")" == "$(dirname "$LAUNCHER")" ]] || fail 'replacement temporary file was not on the launcher filesystem'
assert_no_update_temps

echo 'Checking equal and lower remote versions do not replace the launcher...'
run_case equal success "$CURRENT_VERSION"
assert_unchanged 'equal release version changed the launcher'
[[ ! -f "$MV_LOG" ]] || fail 'equal release version reached the replacement step'
payload_fetches=$(grep -Ec '/start\.sh$' "$CURL_LOG" || true)
[[ "$payload_fetches" -eq 0 ]] || fail 'equal release version fetched a launcher payload'
assert_no_update_temps

run_case lower success "$HIGHER_VERSION"
assert_unchanged 'lower remote release version changed the launcher'
[[ ! -f "$MV_LOG" ]] || fail 'lower remote release version reached the replacement step'
payload_fetches=$(grep -Ec '/start\.sh$' "$CURL_LOG" || true)
[[ "$payload_fetches" -eq 0 ]] || fail 'lower remote release version fetched a launcher payload'
assert_no_update_temps

echo 'Checking unavailable and malformed signed release metadata...'
run_case version-unavailable version-unavailable
assert_unchanged 'unavailable release metadata damaged the launcher'
assert_contains 'could not download artifact-manifest.txt from the configured source' "$CASE_OUTPUT" \
    'unavailable release metadata did not report its failure stage'
assert_contains 'AGENT_LAUNCHED --dangerously-skip-permissions --model sonnet' "$CASE_OUTPUT" \
    'launcher did not continue with the installed agent after metadata became unavailable'
payload_fetches=$(grep -Ec '/start\.sh$' "$CURL_LOG" || true)
[[ "$payload_fetches" -eq 0 ]] || fail 'unavailable metadata unexpectedly fetched a launcher payload'
assert_no_update_temps

run_case version-malformed version-malformed
assert_unchanged 'malformed release metadata damaged the launcher'
payload_fetches=$(grep -Ec '/start\.sh$' "$CURL_LOG" || true)
[[ "$payload_fetches" -eq 0 ]] || fail 'malformed metadata unexpectedly fetched a launcher payload'
assert_no_update_temps

echo 'Checking tampered manifests and stale/tampered launcher payloads...'
run_case manifest-tampered manifest-tampered
assert_unchanged 'tampered release manifest damaged the launcher'
assert_contains 'release manifest signature verification failed' "$CASE_OUTPUT" \
    'tampered release manifest did not report the signature failure'
assert_contains 'release manifest verification failed' "$CASE_OUTPUT" \
    'tampered release manifest was not rejected'
assert_no_update_temps

run_case signed-wrong-format signed-wrong-format
assert_unchanged 'cross-protocol signed manifest damaged the launcher'
assert_contains 'signed manifest uses an unsupported format' "$CASE_OUTPUT" \
    'cross-protocol signed manifest did not report the format mismatch'
assert_contains 'release manifest verification failed' "$CASE_OUTPUT" \
    'cross-protocol signed manifest was not rejected'
assert_no_update_temps

echo 'Checking unavailable and syntax-invalid launcher payloads...'
run_case payload-unavailable payload-unavailable
assert_unchanged 'unavailable launcher payload damaged the launcher'
assert_contains 'could not download start.sh from the configured update source' "$CASE_OUTPUT" \
    'unavailable launcher payload did not report its failure stage'
assert_contains 'AGENT_LAUNCHED --dangerously-skip-permissions --model sonnet' "$CASE_OUTPUT" \
    'launcher did not continue with the installed agent after payload fetch failure'
payload_fetches=$(grep -Ec '/start\.sh$' "$CURL_LOG" || true)
[[ "$payload_fetches" -eq 1 ]] || fail 'unavailable payload did not fetch the launcher exactly once'
assert_no_update_temps

run_case payload-interrupted payload-interrupted
assert_unchanged 'interrupted launcher payload damaged the launcher'
assert_contains 'AGENT_LAUNCHED --dangerously-skip-permissions --model sonnet' "$CASE_OUTPUT" \
    'launcher did not remain usable after an interrupted payload download'
assert_no_update_temps

run_case payload-empty payload-empty
assert_unchanged 'empty launcher payload damaged the launcher'
assert_contains 'downloaded start.sh is empty' "$CASE_OUTPUT" \
    'empty launcher payload did not report its failure stage'
assert_contains 'AGENT_LAUNCHED --dangerously-skip-permissions --model sonnet' "$CASE_OUTPUT" \
    'launcher did not remain usable after an empty payload'
assert_no_update_temps

run_case payload-tampered payload-tampered
assert_unchanged 'tampered launcher payload damaged the launcher'
assert_contains 'does not match the signed release hash and version' "$CASE_OUTPUT" \
    'tampered launcher payload was not rejected'
assert_no_update_temps

run_case payload-stale payload-stale
assert_unchanged 'stale launcher payload damaged the launcher'
assert_contains 'does not match the signed release hash and version' "$CASE_OUTPUT" \
    'stale launcher payload was not rejected'
assert_no_update_temps

run_case payload-malformed payload-malformed
assert_unchanged 'syntax-invalid launcher payload damaged the launcher'
assert_contains 'does not match the signed release hash and version' "$CASE_OUTPUT" \
    'malformed payload failure was not reported'
assert_contains 'AGENT_LAUNCHED --dangerously-skip-permissions --model sonnet' "$CASE_OUTPUT" \
    'launcher did not remain usable after a syntax-gate failure'
[[ ! -f "$MV_LOG" ]] || fail 'syntax-invalid payload reached the replacement step'
assert_no_update_temps

echo 'Checking replacement failure preserves the existing launcher...'
setup_case replacement-failure success
output=$(
    HOME="$CASE_HOME" \
    PATH="$FAKE_BIN:$BASH_BIN_DIR:$OPENSSL_BIN_DIR:/usr/local/bin:/usr/bin:/bin" \
    HERDR_ENV=self-update-test \
    FAKE_CURL_MODE="$CASE_MODE" \
    FAKE_CURL_LOG="$CURL_LOG" \
    FAKE_PAYLOAD_FILE="$PAYLOAD_FILE" \
    FAKE_STALE_PAYLOAD_FILE="$STALE_PAYLOAD_FILE" \
    FAKE_MANIFEST_FILE="$ROOT/artifact-manifest.txt" \
    FAKE_SIGNATURE_FILE="$ROOT/artifact-manifest.sig" \
    FAKE_WRONG_FORMAT_MANIFEST="$WRONG_FORMAT_MANIFEST" \
    FAKE_WRONG_FORMAT_SIGNATURE="$WRONG_FORMAT_SIGNATURE" \
    FAKE_MV_LOG="$MV_LOG" \
    FAKE_MV_FAILURE=true \
    "$LAUNCHER" --agent claude 2>&1
)
assert_unchanged 'failed atomic replacement damaged the launcher'
assert_contains 'could not install fetched start.sh, keeping current version' "$output" \
    'replacement failure was not reported'
assert_contains 'AGENT_LAUNCHED --dangerously-skip-permissions --model sonnet' "$output" \
    'launcher did not remain usable after replacement failure'
assert_no_update_temps

echo 'Checking a present but unusable OpenSSL reports the dependency failure...'
setup_case broken-openssl success
printf '%s\n' '#!/usr/bin/env bash' 'exit 127' > "$FAKE_BIN/openssl"
chmod +x "$FAKE_BIN/openssl"
output=$(
    HOME="$CASE_HOME" \
    PATH="$FAKE_BIN:$BASH_BIN_DIR:$OPENSSL_BIN_DIR:/usr/local/bin:/usr/bin:/bin" \
    HERDR_ENV=self-update-test \
    FAKE_CURL_MODE="$CASE_MODE" \
    FAKE_CURL_LOG="$CURL_LOG" \
    FAKE_PAYLOAD_FILE="$PAYLOAD_FILE" \
    FAKE_STALE_PAYLOAD_FILE="$STALE_PAYLOAD_FILE" \
    FAKE_MANIFEST_FILE="$ROOT/artifact-manifest.txt" \
    FAKE_SIGNATURE_FILE="$ROOT/artifact-manifest.sig" \
    FAKE_WRONG_FORMAT_MANIFEST="$WRONG_FORMAT_MANIFEST" \
    FAKE_WRONG_FORMAT_SIGNATURE="$WRONG_FORMAT_SIGNATURE" \
    FAKE_MV_LOG="$MV_LOG" \
    FAKE_MV_FAILURE=false \
    "$LAUNCHER" --agent claude 2>&1
)
assert_unchanged 'unusable OpenSSL damaged the launcher'
assert_contains 'openssl exists but cannot run; check its shared libraries' "$output" \
    'unusable OpenSSL did not produce an actionable error'
assert_contains 'AGENT_LAUNCHED --dangerously-skip-permissions --model sonnet' "$output" \
    'launcher did not continue after the OpenSSL update-check failure'
assert_no_update_temps

echo 'start.sh self-update regression tests passed.'
