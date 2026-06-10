#!/bin/bash
# Tests for budget_guard.sh: SLO-file-driven limits, per-run per-agent
# counting from pipeline.jsonl, exit-2 blocking, UTC daily count, wall-clock.
set -euo pipefail

PASS=0; FAIL=0
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CLEANUP_DIRS=()
trap 'rm -rf "${CLEANUP_DIRS[@]:-}"' EXIT

assert_exit() {
    local name="$1" expected="$2" actual="$3"
    if [ "$actual" -eq "$expected" ]; then
        echo "PASS: $name"; PASS=$((PASS+1))
    else
        echo "FAIL: $name — expected exit $expected, got $actual"; FAIL=$((FAIL+1))
    fi
}

assert_stderr_contains() {
    local name="$1" pattern="$2" output="$3"
    if echo "$output" | grep -qF "$pattern"; then
        echo "PASS: $name"; PASS=$((PASS+1))
    else
        echo "FAIL: $name — expected '$pattern' in: $output"; FAIL=$((FAIL+1))
    fi
}

assert_stderr_not_contains() {
    local name="$1" pattern="$2" output="$3"
    if echo "$output" | grep -qF "$pattern"; then
        echo "FAIL: $name — did not expect '$pattern' in: $output"; FAIL=$((FAIL+1))
    else
        echo "PASS: $name"; PASS=$((PASS+1))
    fi
}

setup_repo() {
    local tmpdir
    tmpdir=$(mktemp -d)
    CLEANUP_DIRS+=("$tmpdir")
    (
        cd "$tmpdir"
        git init -q
        git config user.email "test@test.com"
        git config user.name "Test"
        mkdir -p hooks/lib contracts logs
        cp "$PROJECT_ROOT/hooks/budget_guard.sh" hooks/
        cp "$PROJECT_ROOT/hooks/lib/common.sh" hooks/lib/
        cp "$PROJECT_ROOT/contracts/pipeline-slos.md" contracts/
        git add . && git commit -q -m "init"
    )
    echo "$tmpdir"
}

write_state() {
    cat > "$1/pipeline_state.json" <<EOF
{"task_id":"TASK-001","pipeline":"$4","run_id":"$3","current_step":"$2","completed_steps":[],"status":"running","started_at":"$5"}
EOF
}

seed_tool_calls() {
    python3 - "$1" "$2" "$3" "$4" <<'PYEOF'
import json, sys
d, agent, run_id, n = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
with open(d + "/logs/pipeline.jsonl", "a") as f:
    for _ in range(n):
        f.write(json.dumps({"event": "tool_call", "tool": "Bash", "agent": agent,
                            "task_id": "TASK-001", "run_id": run_id,
                            "timestamp": "2026-06-10T10:00:00Z"}) + "\n")
PYEOF
}

run_guard() {
    GUARD_EXIT=0
    GUARD_STDERR=$(cd "$1" && CLAUDE_BUDGET_MODE="$2" bash hooks/budget_guard.sh <<< '{}' 2>&1 >/dev/null) || GUARD_EXIT=$?
}

NOW_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Test 1: agent at hard limit, halt mode → exit 2 (blocking)
DIR=$(setup_repo)
write_state "$DIR" security run-1 full "$NOW_ISO"
seed_tool_calls "$DIR" security run-1 12
run_guard "$DIR" halt
assert_exit "security hard limit + halt → exit 2" 2 "$GUARD_EXIT"
assert_stderr_contains "hard limit message names agent" "Agent 'security' hard limit" "$GUARD_STDERR"

# Test 2: same, warn mode → exit 0, warning printed
run_guard "$DIR" warn
assert_exit "security hard limit + warn → exit 0" 0 "$GUARD_EXIT"
assert_stderr_contains "warn mode still reports" "Agent 'security' hard limit" "$GUARD_STDERR"

# Test 3: other agents' calls don't count against the active agent
DIR=$(setup_repo)
write_state "$DIR" security run-1 full "$NOW_ISO"
seed_tool_calls "$DIR" coder run-1 12
run_guard "$DIR" halt
assert_exit "coder calls don't trip security limit" 0 "$GUARD_EXIT"
assert_stderr_not_contains "no agent limit message" "hard limit" "$GUARD_STDERR"

# Test 4: calls from a previous run don't count
DIR=$(setup_repo)
write_state "$DIR" security run-NEW full "$NOW_ISO"
seed_tool_calls "$DIR" security run-OLD 12
run_guard "$DIR" halt
assert_exit "previous run's calls don't count" 0 "$GUARD_EXIT"

# Test 5: editing the SLO file changes the limit — no script edit
DIR=$(setup_repo)
write_state "$DIR" security run-1 full "$NOW_ISO"
sed -i.bak 's/^| security | 8 | 12 |/| security | 2 | 3 |/' "$DIR/contracts/pipeline-slos.md"
seed_tool_calls "$DIR" security run-1 3
run_guard "$DIR" halt
assert_exit "SLO file edit lowers hard limit to 3" 2 "$GUARD_EXIT"

# Test 6: soft limit → warning, exit 0
DIR=$(setup_repo)
write_state "$DIR" coder run-1 full "$NOW_ISO"
seed_tool_calls "$DIR" coder run-1 20
run_guard "$DIR" halt
assert_exit "soft limit does not block" 0 "$GUARD_EXIT"
assert_stderr_contains "soft limit warning printed" "soft limit" "$GUARD_STDERR"

# Test 7: daily count ignores CLASSIFIER/POST_TOOL/STOP lines, uses UTC
DIR=$(setup_repo)
TODAY_UTC=$(date -u +"%Y-%m-%d")
{
    echo "${TODAY_UTC}T10:00:00Z | Bash"
    echo "${TODAY_UTC}T10:00:01Z | Read"
    echo "${TODAY_UTC}T10:00:02Z | CLASSIFIER | PIPELINE:full | REASON:test"
    echo "${TODAY_UTC}T10:00:03Z | POST_TOOL | done"
    echo "${TODAY_UTC}T10:00:04Z | STOP | end"
} > "$DIR/logs/tool_calls.log"
GUARD_EXIT=0
GUARD_STDERR=$(cd "$DIR" && CLAUDE_BUDGET_MODE=halt CLAUDE_DAILY_CALL_LIMIT=3 bash hooks/budget_guard.sh <<< '{}' 2>&1 >/dev/null) || GUARD_EXIT=$?
assert_exit "marker lines excluded from daily count (2 < 3)" 0 "$GUARD_EXIT"
echo "${TODAY_UTC}T10:00:05Z | Edit" >> "$DIR/logs/tool_calls.log"
GUARD_EXIT=0
GUARD_STDERR=$(cd "$DIR" && CLAUDE_BUDGET_MODE=halt CLAUDE_DAILY_CALL_LIMIT=3 bash hooks/budget_guard.sh <<< '{}' 2>&1 >/dev/null) || GUARD_EXIT=$?
assert_exit "3rd tool line trips daily halt → exit 2" 2 "$GUARD_EXIT"

# Test 8: wall-clock budget — full pipeline running 2000s → halt
DIR=$(setup_repo)
OLD_ISO=$(python3 -c "from datetime import datetime,timezone,timedelta; print((datetime.now(timezone.utc)-timedelta(seconds=2000)).strftime('%Y-%m-%dT%H:%M:%SZ'))")
write_state "$DIR" coder run-1 full "$OLD_ISO"
run_guard "$DIR" halt
assert_exit "wall-clock 2000s > full halt 1800s → exit 2" 2 "$GUARD_EXIT"
assert_stderr_contains "wall-clock message" "wall-clock" "$GUARD_STDERR"

# Test 9: wall-clock fine when fresh
DIR=$(setup_repo)
write_state "$DIR" coder run-1 full "$NOW_ISO"
run_guard "$DIR" halt
assert_exit "fresh pipeline passes wall-clock" 0 "$GUARD_EXIT"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
