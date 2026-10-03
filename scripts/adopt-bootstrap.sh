#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
[[ $# -eq 2 ]] || { echo 'Usage: scripts/adopt-bootstrap.sh CLEAN-BOOTSTRAP-CHECKOUT NEXT-BOOTSTRAP-VERSION' >&2; exit 2; }
bootstrap=$(cd "$1" && pwd -P)
version=$2
command -v git >/dev/null 2>&1 || { echo 'Error: git is required to verify checkout cleanliness' >&2; exit 1; }
[[ -z "$(git -C "$bootstrap" status --porcelain)" ]] || { echo 'Error: bootstrap checkout must be clean' >&2; exit 1; }
python3 "$ROOT/scripts/release.py" check
python3 - "$ROOT" "$bootstrap" <<'PY'
from pathlib import Path
import re
import sys
source, bootstrap = map(Path, sys.argv[1:])
host = bootstrap / 'hosts/ex44'
if (source / 'keys/release-signing.pub').read_text().strip() != (host / 'keys/bootstrap-artifacts-signing.pub').read_text().strip():
    raise SystemExit('Pinned keys differ; an explicit overlap trust transition is required')
old = (host / 'start.sh').read_text()
old_url = re.search(r'^REPO_URL="([^"]+)"$', old, re.M).group(1)
current = (host / 'start.sh.version').read_text().strip()
launcher = (source / 'start.sh').read_text()
new_url = re.search(r'^REPO_URL="([^"]+)"$', launcher, re.M).group(1)
launcher = re.sub(r'^START_SH_VERSION="[^"]+"$', f'START_SH_VERSION="{current}"', launcher, count=1, flags=re.M)
launcher = re.sub(r'^REPO_URL="[^"]+"$', f'REPO_URL="{old_url}"', launcher, count=1, flags=re.M)
launcher = launcher.replace('UPDATE_REPO_URL="${START_SH_UPDATE_URL:-$REPO_URL}"',
                            f'UPDATE_REPO_URL="${{START_SH_UPDATE_URL:-{new_url}}}"')
(host / 'start.sh').write_text(launcher)
PY
# Keeping REPO_URL at bootstrap's old location preserves its independent key,
# archive, and SSH-key distribution. Only the launcher's updater migrates.
"$bootstrap/scripts/start-sh-release.sh" prepare-unsigned "$version"
echo "Prepared bootstrap $version with a signed-source harnessctl bridge."
