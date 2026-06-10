#!/bin/bash
# Tests for the per-agent idle timeout feature.
# Covers log_tool.sh timestamp writing and budget_guard.sh idle detection.
set -euo pipefail

PASS=0; FAIL=0
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CLEANUP_FILES=()
trap 'rm -f "${CLEANUP_FILES[@]:-}" /tmp/claude_last_tool_coder /tmp/claude_last_tool_testonly 2>/dev/null || true' EXIT

assert_exit() {
    local name="$1" expected="$2" actual="$3"
    if [ "$actual" -eq "$expected" ]; then
        echo "PASS: $name"; PASS=$((PASS+1))
    else
        echo "FAIL: $name — expected exit $expected, got $actual"; FAIL=$((FAIL+1))
    fi
}

assert_stderr_contains() {
    local name="$1" pattern="$2" stderr_output="$3"
    if echo "$stderr_output" | grep -qF "$pattern"; then
        echo "PASS: $name"; PASS=$((PASS+1))
    else
        echo "FAIL: $name — expected stderr to contain '$pattern', got: $stderr_output"; FAIL=$((FAIL+1))
    fi
}

assert_stderr_not_contains() {
    local name="$1" pattern="$2" stderr_output="$3"
    if echo "$stderr_output" | grep -qF "$pattern"; then
        echo "FAIL: $name — expected stderr NOT to contain '$pattern', got: $stderr_output"; FAIL=$((FAIL+1))
    else
        echo "PASS: $name"; PASS=$((PASS+1))
    fi
}

# ── Test 1: log_tool.sh writes timestamp file when CLAUDE_CURRENT_AGENT is set ──
rm -f /tmp/claude_last_tool_coder
BEFORE=$(date +%s)
(
    cd "$PROJECT_ROOT"
    export CLAUDE_CURRENT_AGENT=coder
    unset CLAUDE_TASK_ID 2>/dev/null || true
    echo '{"tool_name":"Bash"}' | bash hooks/log_tool.sh
)
AFTER=$(date +%s)
if [ -f /tmp/claude_last_tool_coder ]; then
    TS=$(cat /tmp/claude_last_tool_coder)
    if [ "$TS" -ge "$BEFORE" ] && [ "$TS" -le "$AFTER" ]; then
        echo "PASS: log_tool.sh writes recent epoch timestamp for CLAUDE_CURRENT_AGENT=coder"
        PASS=$((PASS+1))
    else
        echo "FAIL: log_tool.sh timestamp out of range: got $TS, expected $BEFORE..$AFTER"
        FAIL=$((FAIL+1))
    fi
else
    echo "FAIL: log_tool.sh did not create /tmp/claude_last_tool_coder"
    FAIL=$((FAIL+1))
fi

# ── Test 2: budget_guard.sh with fresh timestamp — no warning, exits 0 ──
FRESH_TS=$(date +%s)
echo "$FRESH_TS" > /tmp/claude_last_tool_coder
STDERR=$(
    cd "$PROJECT_ROOT"
    export CLAUDE_CURRENT_AGENT=coder
    export CLAUDE_BUDGET_MODE=warn
    export CLAUDE_IDLE_TIMEOUT_MINUTES=10
    echo '{}' | bash hooks/budget_guard.sh 2>&1 >/dev/null || true
)
EXIT_CODE=0
(
    cd "$PROJECT_ROOT"
    export CLAUDE_CURRENT_AGENT=coder
    export CLAUDE_BUDGET_MODE=warn
    export CLAUDE_IDLE_TIMEOUT_MINUTES=10
    echo '{}' | bash hooks/budget_guard.sh 2>/dev/null
) && EXIT_CODE=0 || EXIT_CODE=$?
assert_exit "fresh timestamp — exits 0" 0 "$EXIT_CODE"
assert_stderr_not_contains "fresh timestamp — no idle warning" "[BUDGET] Agent 'coder' idle" "$STDERR"

# ── Test 3: stale timestamp + BUDGET_MODE=warn → prints warning, exits 0 ──
STALE_TS=$(( $(date +%s) - 700 ))  # ~11.6 minutes ago
echo "$STALE_TS" > /tmp/claude_last_tool_coder
STDERR=$(
    cd "$PROJECT_ROOT"
    export CLAUDE_CURRENT_AGENT=coder
    export CLAUDE_BUDGET_MODE=warn
    export CLAUDE_IDLE_TIMEOUT_MINUTES=10
    echo '{}' | bash hooks/budget_guard.sh 2>&1 >/dev/null || true
)
EXIT_CODE=0
(
    cd "$PROJECT_ROOT"
    export CLAUDE_CURRENT_AGENT=coder
    export CLAUDE_BUDGET_MODE=warn
    export CLAUDE_IDLE_TIMEOUT_MINUTES=10
    echo '{}' | bash hooks/budget_guard.sh 2>/dev/null
) && EXIT_CODE=0 || EXIT_CODE=$?
assert_exit "stale timestamp + warn mode — exits 0" 0 "$EXIT_CODE"
assert_stderr_contains "stale timestamp + warn mode — prints idle warning" "[BUDGET] Agent 'coder' idle" "$STDERR"

# ── Test 4: stale timestamp + BUDGET_MODE=halt → exits 1 ──
STALE_TS=$(( $(date +%s) - 700 ))
echo "$STALE_TS" > /tmp/claude_last_tool_coder
EXIT_CODE=0
(
    cd "$PROJECT_ROOT"
    export CLAUDE_CURRENT_AGENT=coder
    export CLAUDE_BUDGET_MODE=halt
    export CLAUDE_IDLE_TIMEOUT_MINUTES=10
    echo '{}' | bash hooks/budget_guard.sh 2>/dev/null
) && EXIT_CODE=0 || EXIT_CODE=$?
assert_exit "stale timestamp + halt mode — exits 1" 1 "$EXIT_CODE"

# ── Test 5: no timestamp file (first call of session) → no warning, exits 0 ──
rm -f /tmp/claude_last_tool_coder
STDERR=$(
    cd "$PROJECT_ROOT"
    export CLAUDE_CURRENT_AGENT=coder
    export CLAUDE_BUDGET_MODE=warn
    export CLAUDE_IDLE_TIMEOUT_MINUTES=10
    echo '{}' | bash hooks/budget_guard.sh 2>&1 >/dev/null || true
)
EXIT_CODE=0
(
    cd "$PROJECT_ROOT"
    export CLAUDE_CURRENT_AGENT=coder
    export CLAUDE_BUDGET_MODE=warn
    export CLAUDE_IDLE_TIMEOUT_MINUTES=10
    echo '{}' | bash hooks/budget_guard.sh 2>/dev/null
) && EXIT_CODE=0 || EXIT_CODE=$?
assert_exit "no timestamp file — exits 0" 0 "$EXIT_CODE"
assert_stderr_not_contains "no timestamp file — no idle warning" "[BUDGET] Agent 'coder' idle" "$STDERR"

# ── Test 6a: CLAUDE_IDLE_TIMEOUT_MINUTES=1, 90s old timestamp → fires ──
OLD_TS=$(( $(date +%s) - 90 ))
echo "$OLD_TS" > /tmp/claude_last_tool_coder
STDERR=$(
    cd "$PROJECT_ROOT"
    export CLAUDE_CURRENT_AGENT=coder
    export CLAUDE_BUDGET_MODE=warn
    export CLAUDE_IDLE_TIMEOUT_MINUTES=1
    echo '{}' | bash hooks/budget_guard.sh 2>&1 >/dev/null || true
)
assert_stderr_contains "1-min limit, 90s old timestamp — fires" "[BUDGET] Agent 'coder' idle" "$STDERR"

# ── Test 6b: CLAUDE_IDLE_TIMEOUT_MINUTES=1, 30s old timestamp → does not fire ──
RECENT_TS=$(( $(date +%s) - 30 ))
echo "$RECENT_TS" > /tmp/claude_last_tool_coder
STDERR=$(
    cd "$PROJECT_ROOT"
    export CLAUDE_CURRENT_AGENT=coder
    export CLAUDE_BUDGET_MODE=warn
    export CLAUDE_IDLE_TIMEOUT_MINUTES=1
    echo '{}' | bash hooks/budget_guard.sh 2>&1 >/dev/null || true
)
assert_stderr_not_contains "1-min limit, 30s old timestamp — does not fire" "[BUDGET] Agent 'coder' idle" "$STDERR"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
