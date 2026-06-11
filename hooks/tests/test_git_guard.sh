#!/bin/bash
# Tests for git_guard.sh: blocks git commit/push when pipeline step != git.
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

setup_repo() {
    local tmpdir
    tmpdir=$(mktemp -d)
    CLEANUP_DIRS+=("$tmpdir")
    (
        cd "$tmpdir"
        git init -q
        git config user.email "test@test.com"
        git config user.name "Test"
        mkdir -p hooks/lib
        cp "$PROJECT_ROOT/hooks/git_guard.sh" hooks/
        cp "$PROJECT_ROOT/hooks/lib/common.sh" hooks/lib/
        git add . && git commit -q -m "init"
    )
    echo "$tmpdir"
}

bash_event() {
    python3 -c "import json,sys; print(json.dumps({'tool_name':'Bash','tool_input':{'command':sys.argv[1]}}))" "$1"
}

write_state() {
    # args: dir step status
    python3 -c "
import json, sys
d = {'task_id':'TASK-001','pipeline':'fast-track','run_id':'r1',
     'current_step':sys.argv[2],'completed_steps':[],'status':sys.argv[3],'started_at':'2026-06-11T00:00:00Z'}
json.dump(d, open(sys.argv[1]+'/pipeline_state.json','w'))
" "$1" "$2" "$3"
}

# Test 1: git commit blocked when step is coder (not git)
DIR=$(setup_repo)
write_state "$DIR" coder running
EXIT=0
bash_event "git commit -m 'test'" | (cd "$DIR" && bash hooks/git_guard.sh 2>/dev/null) || EXIT=$?
assert_exit "git commit blocked when step=coder" 2 "$EXIT"

# Test 2: git push blocked when step is security (not git)
DIR=$(setup_repo)
write_state "$DIR" security running
EXIT=0
bash_event "git push origin main" | (cd "$DIR" && bash hooks/git_guard.sh 2>/dev/null) || EXIT=$?
assert_exit "git push blocked when step=security" 2 "$EXIT"

# Test 3: git commit ALLOWED when step is git
DIR=$(setup_repo)
write_state "$DIR" git running
EXIT=0
bash_event "git commit -m 'test'" | (cd "$DIR" && bash hooks/git_guard.sh 2>/dev/null) || EXIT=$?
assert_exit "git commit allowed when step=git" 0 "$EXIT"

# Test 4: git push ALLOWED when step is git
DIR=$(setup_repo)
write_state "$DIR" git running
EXIT=0
bash_event "git push origin main" | (cd "$DIR" && bash hooks/git_guard.sh 2>/dev/null) || EXIT=$?
assert_exit "git push allowed when step=git" 0 "$EXIT"

# Test 5: git commit ALLOWED when no pipeline running
DIR=$(setup_repo)
EXIT=0
bash_event "git commit -m 'test'" | (cd "$DIR" && bash hooks/git_guard.sh 2>/dev/null) || EXIT=$?
assert_exit "git commit allowed when no pipeline active" 0 "$EXIT"

# Test 6: git commit ALLOWED when pipeline status=completed
DIR=$(setup_repo)
write_state "$DIR" memory completed
EXIT=0
bash_event "git commit -m 'test'" | (cd "$DIR" && bash hooks/git_guard.sh 2>/dev/null) || EXIT=$?
assert_exit "git commit allowed when pipeline completed" 0 "$EXIT"

# Test 7: git status not blocked (read-only git command)
DIR=$(setup_repo)
write_state "$DIR" coder running
EXIT=0
bash_event "git status --short" | (cd "$DIR" && bash hooks/git_guard.sh 2>/dev/null) || EXIT=$?
assert_exit "git status not blocked" 0 "$EXIT"

# Test 8: git diff not blocked
DIR=$(setup_repo)
write_state "$DIR" reviewer running
EXIT=0
bash_event "git diff HEAD" | (cd "$DIR" && bash hooks/git_guard.sh 2>/dev/null) || EXIT=$?
assert_exit "git diff not blocked" 0 "$EXIT"

# Test 9: non-Bash tool not affected
DIR=$(setup_repo)
write_state "$DIR" coder running
EXIT=0
echo '{"tool_name":"Write","tool_input":{"file_path":"a.txt","content":"x"}}' | (cd "$DIR" && bash hooks/git_guard.sh 2>/dev/null) || EXIT=$?
assert_exit "Write tool not affected by git_guard" 0 "$EXIT"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
