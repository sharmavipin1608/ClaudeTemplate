#!/bin/bash
# Tests for the per-agent idle timeout in budget_guard.sh.
# Timestamp files live in <project>/.claude/tmp/last_tool_<agent>.
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
        mkdir -p hooks/lib contracts logs .claude/tmp
        cp "$PROJECT_ROOT/hooks/budget_guard.sh" hooks/
        cp "$PROJECT_ROOT/hooks/lib/common.sh" hooks/lib/
        cp "$PROJECT_ROOT/contracts/pipeline-slos.md" contracts/
        git add . && git commit -q -m "init"
    )
    echo "$tmpdir"
}

run_guard() {
    GUARD_EXIT=0
    GUARD_STDERR=$(cd "$1" && CLAUDE_CURRENT_AGENT=coder CLAUDE_BUDGET_MODE="$2" CLAUDE_IDLE_TIMEOUT_MINUTES="$3" \
        bash hooks/budget_guard.sh <<< '{}' 2>&1 >/dev/null) || GUARD_EXIT=$?
}

# Test 1: fresh timestamp → no warning, exit 0
DIR=$(setup_repo)
date +%s > "$DIR/.claude/tmp/last_tool_coder"
run_guard "$DIR" warn 10
assert_exit "fresh timestamp exits 0" 0 "$GUARD_EXIT"
assert_stderr_not_contains "fresh timestamp — no idle warning" "idle" "$GUARD_STDERR"

# Test 2: stale timestamp + warn → warning, exit 0
DIR=$(setup_repo)
echo $(( $(date +%s) - 700 )) > "$DIR/.claude/tmp/last_tool_coder"
run_guard "$DIR" warn 10
assert_exit "stale + warn exits 0" 0 "$GUARD_EXIT"
assert_stderr_contains "stale + warn prints idle warning" "Agent 'coder' idle" "$GUARD_STDERR"

# Test 3: stale timestamp + halt → exit 2 (blocking)
DIR=$(setup_repo)
echo $(( $(date +%s) - 700 )) > "$DIR/.claude/tmp/last_tool_coder"
run_guard "$DIR" halt 10
assert_exit "stale + halt exits 2" 2 "$GUARD_EXIT"

# Test 4: no timestamp file (first call) → no warning
DIR=$(setup_repo)
run_guard "$DIR" warn 10
assert_exit "no file exits 0" 0 "$GUARD_EXIT"
assert_stderr_not_contains "no file — no idle warning" "idle" "$GUARD_STDERR"

# Test 5: custom threshold — 90s old with 1-minute limit fires
DIR=$(setup_repo)
echo $(( $(date +%s) - 90 )) > "$DIR/.claude/tmp/last_tool_coder"
run_guard "$DIR" warn 1
assert_stderr_contains "90s old, 1-min limit fires" "Agent 'coder' idle" "$GUARD_STDERR"

# Test 6: custom threshold — 30s old with 1-minute limit does not fire
DIR=$(setup_repo)
echo $(( $(date +%s) - 30 )) > "$DIR/.claude/tmp/last_tool_coder"
run_guard "$DIR" warn 1
assert_stderr_not_contains "30s old, 1-min limit silent" "idle" "$GUARD_STDERR"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
