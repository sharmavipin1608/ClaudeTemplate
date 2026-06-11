#!/bin/bash
# log_agent.sh and validate_output.sh must write to the MAIN repo's logs
# even when invoked from inside a git worktree, and validated envelopes
# must carry an "event" field so analytics can see them.
set -euo pipefail

PASS=0; FAIL=0
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CLEANUP_DIRS=()
trap 'rm -rf "${CLEANUP_DIRS[@]:-}"' EXIT

tmpdir=$(mktemp -d)
CLEANUP_DIRS+=("$tmpdir")
(
    cd "$tmpdir"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"
    mkdir -p hooks/lib contracts logs
    cp "$PROJECT_ROOT/hooks/log_agent.sh" hooks/
    cp "$PROJECT_ROOT/hooks/validate_output.sh" hooks/
    cp "$PROJECT_ROOT/hooks/init_pipeline_state.sh" hooks/
    cp "$PROJECT_ROOT/hooks/lib/common.sh" hooks/lib/
    cp "$PROJECT_ROOT/contracts/coder.json" contracts/
    git add . && git commit -q -m "init"
    git worktree add -q wt -b test-wt
    rm -rf wt/logs
)

# Init pipeline state in the MAIN root
(cd "$tmpdir" && bash hooks/init_pipeline_state.sh TASK-001 full >/dev/null)
RUN_ID=$(python3 -c "import json; print(json.load(open('$tmpdir/pipeline_state.json'))['run_id'])")

# Test 1: log_agent.sh from inside the worktree writes to the MAIN pipeline.jsonl
(cd "$tmpdir/wt" && bash hooks/log_agent.sh coder START TASK-001 full >/dev/null)
LAST=$(tail -1 "$tmpdir/logs/pipeline.jsonl" 2>/dev/null || echo "{}")
GOT_RUN=$(echo "$LAST" | python3 -c "import json,sys; print(json.load(sys.stdin).get('run_id',''))")
if [ "$GOT_RUN" = "$RUN_ID" ]; then
    echo "PASS: worktree log_agent writes main log with run_id"; PASS=$((PASS+1))
else
    echo "FAIL: expected run_id '$RUN_ID' in main log, got '$GOT_RUN' (last: $LAST)"; FAIL=$((FAIL+1))
fi
if [ -f "$tmpdir/wt/logs/pipeline.jsonl" ]; then
    echo "FAIL: worktree got its own pipeline.jsonl"; FAIL=$((FAIL+1))
else
    echo "PASS: no fragmented log in worktree"; PASS=$((PASS+1))
fi

# Test 2: validated envelope gets event=agent_envelope and run_id, in MAIN log
ENVELOPE='{"task_id":"TASK-001","agent":"coder","verdict":"DONE","payload":{},"next_agent":"reviewer","timestamp":"2026-06-10T10:00:00Z"}'
(cd "$tmpdir/wt" && echo "$ENVELOPE" | bash hooks/validate_output.sh coder >/dev/null)
LAST=$(tail -1 "$tmpdir/logs/pipeline.jsonl")
GOT_EVENT=$(echo "$LAST" | python3 -c "import json,sys; print(json.load(sys.stdin).get('event',''))")
GOT_RUN=$(echo "$LAST" | python3 -c "import json,sys; print(json.load(sys.stdin).get('run_id',''))")
if [ "$GOT_EVENT" = "agent_envelope" ]; then
    echo "PASS: envelope tagged event=agent_envelope"; PASS=$((PASS+1))
else
    echo "FAIL: envelope event tag missing, got '$GOT_EVENT'"; FAIL=$((FAIL+1))
fi
if [ "$GOT_RUN" = "$RUN_ID" ]; then
    echo "PASS: envelope carries run_id from main state"; PASS=$((PASS+1))
else
    echo "FAIL: envelope run_id expected '$RUN_ID', got '$GOT_RUN'"; FAIL=$((FAIL+1))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
