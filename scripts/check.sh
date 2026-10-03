#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
export TMPDIR="$(cd /home/coding/scratch 2>/dev/null && pwd -P || printf '%s' "${TMPDIR:-/tmp}")"
for path in start.sh install.sh scripts/*.sh tests/*.sh; do
    bash -n "$path"
done
python3 scripts/release.py parity
bash tests/start-sh-self-update-test.sh
bash tests/start-sh-interface-test.sh
bash tests/install-update-test.sh
bash tests/configuration-test.sh
bash tests/release-test.sh
if [[ -n "${BOOTSTRAP_SOURCE:-}" ]]; then
    bash tests/bootstrap-adoption-test.sh
fi
bash tests/start-sh-runtime-test.sh
echo 'Complete harness-start local gate passed.'
