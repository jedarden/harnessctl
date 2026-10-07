#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
export TMPDIR="$(cd /home/coding/scratch 2>/dev/null && pwd -P || printf '%s' "${TMPDIR:-/tmp}")"
for path in start.sh install.sh scripts/*.sh tests/*.sh; do
    bash -n "$path"
done
python3 scripts/release.py parity
for schema in docs/schemas/*.json; do
    python3 -m json.tool "$schema" >/dev/null
done
bash tests/start-sh-self-update-test.sh
bash tests/start-sh-interface-test.sh
bash tests/doctor-test.sh
bash tests/install-update-test.sh
bash tests/configuration-test.sh
bash tests/release-test.sh
if [[ -n "${BOOTSTRAP_SOURCE:-}" ]]; then
    bash tests/bootstrap-adoption-test.sh
fi
if (( EUID == 0 )); then
    # The runtime gate verifies agent execution without root privileges.
    runtime_tmp=$(mktemp -d /tmp/harnessctl-runtime.XXXXXX)
    trap 'rm -rf "$runtime_tmp"' EXIT
    chmod 1777 "$runtime_tmp"
    mkdir "$runtime_tmp/tests"
    cp start.sh "$runtime_tmp/start.sh"
    cp tests/start-sh-runtime-test.sh "$runtime_tmp/tests/"
    runuser -u nobody -- env TMPDIR="$runtime_tmp" bash "$runtime_tmp/tests/start-sh-runtime-test.sh"
else
    bash tests/start-sh-runtime-test.sh
fi
echo 'Complete harnessctl local gate passed.'
