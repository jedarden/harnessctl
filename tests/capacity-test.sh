#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/harness-capacity.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/proc/self" "$TMP/cgroup/team"
printf 'cpu memory cpuset\n' > "$TMP/cgroup/cgroup.controllers"

cat > "$TMP/bin/claude" <<'AGENT'
#!/usr/bin/env bash
printf 'FAKE_LAUNCHED\n'
AGENT
chmod +x "$TMP/bin/claude"

printf 'processor\t: 0\nprocessor\t: 1\nprocessor\t: 2\nprocessor\t: 3\n' > "$TMP/proc/cpuinfo"
printf 'Cpus_allowed_list:\t0-3\n' > "$TMP/proc/self/status"
printf '0::/team\n' > "$TMP/proc/self/cgroup"
printf 'MemAvailable: 8388608 kB\n' > "$TMP/proc/meminfo"
printf '1.50 1.20 0.90 2/10 100\n' > "$TMP/proc/loadavg"
printf '200000 100000\n' > "$TMP/cgroup/team/cpu.max"
printf '0-3\n' > "$TMP/cgroup/team/cpuset.cpus.effective"
printf '4294967296\n' > "$TMP/cgroup/team/memory.max"
printf '1073741824\n' > "$TMP/cgroup/team/memory.current"

process() {
    local pid=$1 state=$2 uid=$3
    shift 3
    mkdir -p "$TMP/proc/$pid"
    printf 'State:\t%s\nUid:\t%s\t%s\t%s\t%s\n' "$state" "$uid" "$uid" "$uid" "$uid" > "$TMP/proc/$pid/status"
    printf '%s\0' "$@" > "$TMP/proc/$pid/cmdline"
}
process 101 S 1000 /usr/bin/claude --model sonnet
process 102 S 1001 /usr/bin/node /usr/lib/node_modules/@openai/codex/bin/codex.js
process 103 Z 1000 /usr/bin/codex
process 104 S 1000 /usr/bin/codex-helper
process 105 S 1000 /usr/bin/bash /usr/local/bin/start.sh codex
process 106 S 1000 /usr/bin/codex app-server
mkdir -p "$TMP/proc/107"
printf 'State:\tS\nUid:\t1000\n' > "$TMP/proc/107/status"
printf 'unrelated\n' > "$TMP/proc/107/comm"

# Existing CCDash hook state may enrich a live PID, but stale PID reuse is
# rejected and hook records never create inventory entries on their own.
mkdir -p "$TMP/.ccdash/sessions"
now=$(date +%s)
ticks=$(getconf CLK_TCK)
printf 'btime %d\n' "$((now - 100))" > "$TMP/proc/stat"
printf '101 (claude) S %s\n' "$(printf '0 %.0s' {1..18})$((95 * ticks))" > "$TMP/proc/101/stat"
printf '{"pid":101,"source":"claude","session_id":"stale","started_at":"%s"}\n' \
    "$(date -u -d "@$((now - 90))" +%Y-%m-%dT%H:%M:%SZ)" > "$TMP/.ccdash/sessions/old.json"
printf '{"pid":101,"source":"claude","session_id":"live-session","started_at":"%s"}\n' \
    "$(date -u -d "@$now" +%Y-%m-%dT%H:%M:%SZ)" > "$TMP/.ccdash/sessions/current.json"

start() {
    env HOME="$TMP" PATH="$TMP/bin:$PATH" \
        START_SH_CONFIG="$TMP/absent-config" START_SH_PROFILE=safe \
        START_SH_UPDATE_POLICY=never START_SH_AGENT_UPDATE_POLICY=never \
        START_SH_PROC_ROOT="$TMP/proc" START_SH_CGROUP_ROOT="$TMP/cgroup" \
        HERDR_ENV=capacity-fixture bash "$ROOT/start.sh" "$@"
}
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

json=$(start status --json)
if command -v jq >/dev/null 2>&1; then
    expect_enrichment=true
else
    expect_enrichment=false
fi
STATUS_JSON="$json" EXPECT_ENRICHMENT="$expect_enrichment" python3 - <<'PY'
import json, os
payload = json.loads(os.environ['STATUS_JSON'])
host = payload['host']
assert host['inventory']['complete'] is True
assert host['inventory']['counts'] == {'claude': 1, 'codex': 1, 'total': 2}
assert {item['pid'] for item in host['inventory']['agents']} == {101, 102}
claude = next(item for item in host['inventory']['agents'] if item['pid'] == 101)
if os.environ['EXPECT_ENRICHMENT'] == 'true':
    assert claude['session_id'] == 'live-session'
else:
    assert 'session_id' not in claude
assert 'session_id' not in next(item for item in host['inventory']['agents'] if item['pid'] == 102)
assert host['capacity'] == {
    'ready': False, 'reason': 'cpu', 'cpu_millicores': 2000,
    'cpu_load_millicores': 1500,
    'memory_available_bytes': 3221225472,
}
PY

if output=$(start claude --no-update --no-agent-update 2>&1); then
    fail 'CPU-constrained launch succeeded'
fi
[[ "$output" == *'N+1 capacity check failed (cpu)'* ]] || fail 'CPU failure not reported'
[[ "$output" != *'FAKE_LAUNCHED'* ]] || fail 'CPU failure launched an agent'
output=$(start claude --no-update --no-agent-update --force-capacity 2>&1)
[[ "$output" == *'overriding N+1 capacity check (cpu)'* && "$output" == *'FAKE_LAUNCHED'* ]] || fail 'operator override failed'

printf '400000 100000\n' > "$TMP/cgroup/team/cpu.max"
printf '0.20 0.30 0.40 1/10 100\n' > "$TMP/proc/loadavg"
printf '3489660928\n' > "$TMP/cgroup/team/memory.current"
json=$(start status --json)
STATUS_JSON="$json" python3 - <<'PY'
import json, os
capacity = json.loads(os.environ['STATUS_JSON'])['host']['capacity']
assert capacity['reason'] == 'memory', capacity
assert capacity['memory_available_bytes'] == 805306368, capacity
PY
if output=$(start claude --no-update --no-agent-update 2>&1); then
    fail 'memory-constrained launch succeeded'
fi
[[ "$output" == *'N+1 capacity check failed (memory)'* ]] || fail 'memory failure not reported'

rm "$TMP/proc/meminfo"
json=$(start status --json)
STATUS_JSON="$json" python3 - <<'PY'
import json, os
capacity = json.loads(os.environ['STATUS_JSON'])['host']['capacity']
assert capacity['ready'] is False and capacity['reason'] == 'metrics-unavailable', capacity
PY

printf 'MemAvailable: 8388608 kB\n' > "$TMP/proc/meminfo"
rm "$TMP/cgroup/cgroup.controllers"
json=$(start status --json)
STATUS_JSON="$json" python3 - <<'PY'
import json, os
capacity = json.loads(os.environ['STATUS_JSON'])['host']['capacity']
assert capacity['ready'] is False and capacity['reason'] == 'metrics-unavailable', capacity
PY
printf 'cpu memory cpuset\n' > "$TMP/cgroup/cgroup.controllers"
mkdir -p "$TMP/proc/108"
printf 'State:\tS\nUid:\t1000\n' > "$TMP/proc/108/status"
printf 'codex\n' > "$TMP/proc/108/comm"
json=$(start status --json)
STATUS_JSON="$json" python3 - <<'PY'
import json, os
host = json.loads(os.environ['STATUS_JSON'])['host']
assert host['inventory']['complete'] is False, host
assert host['capacity']['reason'] == 'inventory-unavailable', host
PY

printf 'Capacity fixture checks passed.\n'
