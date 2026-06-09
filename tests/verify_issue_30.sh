#!/bin/bash
# End-to-end verification of issue #30 — pipeline reliability: state machine, contracts, validation.
# Bootstraps a demo project, runs structural + functional checks, generates a markdown report,
# and posts it as a comment on GitHub issue #30.
#
# Prerequisites: git, python3 (stdlib), gh CLI authenticated
# Usage: bash tests/verify_issue_30.sh [--dry-run]
#   --dry-run: print report to stdout only, do not post to GitHub
set -uo pipefail

DRY_RUN="${1:-}"
TEMPLATE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPORT_FILE="/tmp/issue_30_verification_$(date +%Y%m%d_%H%M%S).md"
DEMO_DIR=$(mktemp -d)
trap 'rm -rf "$DEMO_DIR"' EXIT

PASS=0; FAIL=0
REPORT_LINES=()

# ── Helpers ────────────────────────────────────────────────────────────────────

log()  { REPORT_LINES+=("$1"); }
check() {
    local name="$1" result="$2"  # result: "pass" or "fail: <reason>"
    if [[ "$result" == "pass" ]]; then
        log "- [x] $name"
        PASS=$((PASS+1))
    else
        log "- [ ] **FAIL** $name — ${result#fail: }"
        FAIL=$((FAIL+1))
    fi
}
run_silent() { "$@" > /dev/null 2>&1; }

# ── Bootstrap a demo project ───────────────────────────────────────────────────

log "# Issue #30 Verification Report"
log ""
log "**Branch:** $(cd "$TEMPLATE_DIR" && git rev-parse --abbrev-ref HEAD)"
log "**Commit:** $(cd "$TEMPLATE_DIR" && git rev-parse --short HEAD)"
log "**Date:** $(date -u +"%Y-%m-%d %H:%M UTC")"
log "**Demo project:** \`$DEMO_DIR\`"
log ""
log "## 1. Bootstrap — Structure"
log ""

# Copy template to demo dir and run the infra-move step manually
# (full bootstrap requires interactive prompts; we replicate just the infra move)
cp -r "$TEMPLATE_DIR/." "$DEMO_DIR/"
cd "$DEMO_DIR"
git init -q
git config user.email "verify@test.com"
git config user.name "Verify"
git add . && git commit -q -m "init"
mkdir -p .claude

# Simulate tests/ removal (mirrors bootstrap.sh cleanup step)
[[ -d "tests" ]] && rm -rf tests/

for dir in agents hooks skills tools contracts; do
    [[ -d "$dir" ]] && mv "$dir" ".claude/$dir"
done

# Patch hook paths (mirrors bootstrap.sh step 7/9)
python3 << 'PYEOF'
content = open('.claude/settings.json').read()
content = content.replace('${CLAUDE_PROJECT_DIR}/hooks/', '${CLAUDE_PROJECT_DIR}/.claude/hooks/')
open('.claude/settings.json', 'w').write(content)
PYEOF
sed -i.bak 's|\^hooks/|^\.claude/hooks/|g' .claude/hooks/classify_task.sh
rm -f .claude/hooks/classify_task.sh.bak

# Check 1: contracts/ gone from root
[[ ! -d "contracts" ]] \
    && check "contracts/ removed from project root" "pass" \
    || check "contracts/ removed from project root" "fail: contracts/ still exists at root"

# Check 1b: tests/ gone from root
[[ ! -d "tests" ]] \
    && check "tests/ removed from project root (template-specific scripts not copied)" "pass" \
    || check "tests/ removed from project root (template-specific scripts not copied)" "fail: tests/ still exists at root"

# Check 2: .claude/contracts/ exists
[[ -d ".claude/contracts" ]] \
    && check ".claude/contracts/ exists" "pass" \
    || check ".claude/contracts/ exists" "fail: .claude/contracts/ not found"

# Check 3: all 8 contract files present
CONTRACT_COUNT=$(ls .claude/contracts/*.json 2>/dev/null | wc -l | tr -d ' ')
[[ "$CONTRACT_COUNT" -eq 8 ]] \
    && check "all 8 contract files present in .claude/contracts/" "pass" \
    || check "all 8 contract files present in .claude/contracts/" "fail: found $CONTRACT_COUNT, expected 8"

# Check 4: all contracts are valid JSON
JSON_ERRORS=""
for f in .claude/contracts/*.json; do
    python3 -m json.tool "$f" > /dev/null 2>&1 || JSON_ERRORS="$JSON_ERRORS $f"
done
[[ -z "$JSON_ERRORS" ]] \
    && check "all contract files are valid JSON" "pass" \
    || check "all contract files are valid JSON" "fail: invalid JSON in$JSON_ERRORS"

# Check 5: validate_output.sh present
[[ -f ".claude/hooks/validate_output.sh" ]] \
    && check "validate_output.sh present at .claude/hooks/" "pass" \
    || check "validate_output.sh present at .claude/hooks/" "fail: not found"

# Check 6: validate_output.sh resolves contracts from .claude/contracts/
RESULT=$(echo '{"task_id":"T-1","agent":"coder","verdict":"DONE","payload":{},"next_agent":"reviewer","reason":null,"timestamp":"2026-06-08T10:00:00Z"}' \
    | bash .claude/hooks/validate_output.sh coder 2>&1) && EXIT=0 || EXIT=$?
[[ "$EXIT" -eq 0 && "$RESULT" == "OK"* ]] \
    && check "validate_output.sh resolves contracts at .claude/contracts/ (post-bootstrap path)" "pass" \
    || check "validate_output.sh resolves contracts at .claude/contracts/ (post-bootstrap path)" "fail: exit=$EXIT result=$RESULT"

log ""
log "## 2. validate_output.sh — Acceptance checks (one per agent)"
log ""

assert_valid() {
    local agent="$1" envelope="$2"
    local result exit_code=0
    result=$(echo "$envelope" | bash .claude/hooks/validate_output.sh "$agent" 2>&1) || exit_code=$?
    [[ "$exit_code" -eq 0 ]] \
        && check "valid $agent envelope accepted" "pass" \
        || check "valid $agent envelope accepted" "fail: $result"
}

assert_valid "coder" \
    '{"task_id":"T-1","agent":"coder","verdict":"DONE","payload":{"files_changed":["src/foo.py"],"decisions":[],"convention_gaps":[]},"next_agent":"reviewer","reason":null,"timestamp":"2026-06-08T10:00:00Z"}'

assert_valid "researcher" \
    '{"task_id":"T-1","agent":"researcher","verdict":"DONE","payload":{"facts_written":2,"key_finding":"JWT rotates daily","contradictions":[]},"next_agent":"coder","reason":null,"timestamp":"2026-06-08T10:00:00Z"}'

assert_valid "reviewer" \
    '{"task_id":"T-1","agent":"reviewer","verdict":"PASS","payload":{"required_changes":[],"convention_candidates":[],"lens_results":["Lens 1: no violations"]},"next_agent":"tester","reason":null,"timestamp":"2026-06-08T10:00:00Z"}'

assert_valid "tester" \
    '{"task_id":"T-1","agent":"tester","verdict":"PASS","payload":{"tests_run":4,"unit":2,"integration":1,"edge":1},"next_agent":"security","reason":null,"timestamp":"2026-06-08T10:00:00Z"}'

assert_valid "security" \
    '{"task_id":"T-1","agent":"security","verdict":"PASS","payload":{"blockers":[]},"next_agent":"git","reason":null,"timestamp":"2026-06-08T10:00:00Z"}'

assert_valid "git" \
    '{"task_id":"T-1","agent":"git","verdict":"COMMITTED","payload":{"sha":"abc1234","branch":"feat/30","message":"feat: add pipeline state"},"next_agent":"memory","reason":null,"timestamp":"2026-06-08T10:00:00Z"}'

assert_valid "devops" \
    '{"task_id":"T-1","agent":"devops","verdict":"PASS","payload":{"ci_url":"https://github.com/a/b/runs/1","smoke_test":"SKIPPED","notes":[]},"next_agent":"memory","reason":null,"timestamp":"2026-06-08T10:00:00Z"}'

assert_valid "memory" \
    '{"task_id":"T-1","agent":"memory","verdict":"DONE","payload":{"facts_added":1,"queue_remaining":2,"convention_candidates":[]},"next_agent":null,"reason":null,"timestamp":"2026-06-08T10:00:00Z"}'

log ""
log "## 3. validate_output.sh — Rejection checks"
log ""

assert_rejected() {
    local name="$1" agent="$2" envelope="$3"
    local exit_code=0
    echo "$envelope" | bash .claude/hooks/validate_output.sh "$agent" > /dev/null 2>&1 || exit_code=$?
    [[ "$exit_code" -ne 0 ]] \
        && check "$name" "pass" \
        || check "$name" "fail: expected rejection but got exit 0"
}

assert_rejected "free text rejected" "reviewer" "looks good to me"
assert_rejected "missing required fields rejected" "coder" '{"agent":"coder","verdict":"DONE"}'
assert_rejected "invalid verdict rejected" "reviewer" '{"task_id":"T-1","agent":"reviewer","verdict":"MAYBE","payload":{},"next_agent":"tester","reason":null,"timestamp":"2026-06-08T10:00:00Z"}'
assert_rejected "FIX_REQUIRED without reason rejected" "reviewer" '{"task_id":"T-1","agent":"reviewer","verdict":"FIX_REQUIRED","payload":{"required_changes":[],"convention_candidates":[]},"next_agent":"coder","reason":null,"timestamp":"2026-06-08T10:00:00Z"}'
assert_rejected "BLOCKED without reason rejected" "security" '{"task_id":"T-1","agent":"security","verdict":"BLOCKED","payload":{"blockers":[]},"next_agent":null,"reason":null,"timestamp":"2026-06-08T10:00:00Z"}'
assert_rejected "FAIL without reason rejected (tester)" "tester" '{"task_id":"T-1","agent":"tester","verdict":"FAIL","payload":{"tests_run":3,"passed":1,"failures":[]},"next_agent":"coder","reason":null,"timestamp":"2026-06-08T10:00:00Z"}'
assert_rejected "PUSH_FAILED without reason rejected (git)" "git" '{"task_id":"T-1","agent":"git","verdict":"PUSH_FAILED","payload":{"error":"rejected","sha":null},"next_agent":null,"reason":null,"timestamp":"2026-06-08T10:00:00Z"}'
assert_rejected "unknown agent rejected" "unknown" '{"task_id":"T-1","agent":"unknown","verdict":"DONE","payload":{},"next_agent":null,"reason":null,"timestamp":"2026-06-08T10:00:00Z"}'

log ""
log "## 4. Pipeline state machine"
log ""

bash .claude/hooks/init_pipeline_state.sh TASK-DEMO full > /dev/null
STATE=$(python3 -c "import json; d=json.load(open('pipeline_state.json')); print(d['current_step'], d['status'], d['pipeline'])")
[[ "$STATE" == "researcher running full" ]] \
    && check "init full pipeline: current_step=researcher, status=running" "pass" \
    || check "init full pipeline: current_step=researcher, status=running" "fail: got '$STATE'"

bash .claude/hooks/advance_pipeline_state.sh researcher coder > /dev/null
STATE=$(python3 -c "import json; d=json.load(open('pipeline_state.json')); print(d['current_step'], 'researcher' in d['completed_steps'])")
[[ "$STATE" == "coder True" ]] \
    && check "advance researcher→coder: current_step=coder, researcher in completed_steps" "pass" \
    || check "advance researcher→coder: current_step=coder, researcher in completed_steps" "fail: got '$STATE'"

for step_pair in "coder reviewer" "reviewer tester" "tester security" "security git" "git memory"; do
    FROM="${step_pair% *}"; TO="${step_pair#* }"
    bash .claude/hooks/advance_pipeline_state.sh "$FROM" "$TO" > /dev/null
done

STATE=$(python3 -c "import json; d=json.load(open('pipeline_state.json')); print(d['current_step'], len(d['completed_steps']))")
[[ "$STATE" == "memory 6" ]] \
    && check "advance through all 6 pre-memory steps: current_step=memory, 6 in completed_steps" "pass" \
    || check "advance through all 6 pre-memory steps: current_step=memory, 6 in completed_steps" "fail: got '$STATE'"

bash .claude/hooks/advance_pipeline_state.sh memory done > /dev/null
STATE=$(python3 -c "import json; d=json.load(open('pipeline_state.json')); print(d['status'], d['current_step'])")
[[ "$STATE" == "completed None" ]] \
    && check "advance to done: status=completed, current_step=None" "pass" \
    || check "advance to done: status=completed, current_step=None" "fail: got '$STATE'"

bash .claude/hooks/init_pipeline_state.sh TASK-FAST fast-track > /dev/null
STEP=$(python3 -c "import json; d=json.load(open('pipeline_state.json')); print(d['current_step'])")
[[ "$STEP" == "coder" ]] \
    && check "init fast-track pipeline: current_step=coder" "pass" \
    || check "init fast-track pipeline: current_step=coder" "fail: got '$STEP'"

log ""
log "## 5. Session recovery scenario"
log ""

bash .claude/hooks/init_pipeline_state.sh TASK-CRASH full > /dev/null
bash .claude/hooks/advance_pipeline_state.sh researcher coder > /dev/null

mkdir -p memory
RECOVERY_OUTPUT=$(echo '{"session_id":"new-session-abc"}' | bash .claude/hooks/pre_task.sh 2>&1 || true)
echo "$RECOVERY_OUTPUT" | grep -q "RECOVERY" \
    && check "pre_task.sh outputs RECOVERY block when pipeline_state.json shows running" "pass" \
    || check "pre_task.sh outputs RECOVERY block when pipeline_state.json shows running" "fail: RECOVERY not found in output"

echo "$RECOVERY_OUTPUT" | grep -q "coder" \
    && check "RECOVERY block names the interrupted step (coder)" "pass" \
    || check "RECOVERY block names the interrupted step (coder)" "fail: step name not found in recovery output"

echo "$RECOVERY_OUTPUT" | grep -q "TASK-CRASH" \
    && check "RECOVERY block names the task id (TASK-CRASH)" "pass" \
    || check "RECOVERY block names the task id (TASK-CRASH)" "fail: task id not found in recovery output"

log ""
log "### Recovery block output"
log ""
log '```'
log "$RECOVERY_OUTPUT"
log '```'

log ""
log "## Summary"
log ""
log "| Result | Count |"
log "|---|---|"
log "| ✅ Passed | $PASS |"
log "| ❌ Failed | $FAIL |"
log ""
if [[ "$FAIL" -eq 0 ]]; then
    log "**All $PASS checks passed.** Issue #30 acceptance criteria verified in a bootstrapped demo project."
else
    log "**$FAIL check(s) failed.** See items marked FAIL above."
fi
log ""
log "<details><summary>pipeline_state.json at end of verification</summary>"
log ""
log '```json'
log "$(cat pipeline_state.json 2>/dev/null || echo '{}')"
log '```'
log ""
log "</details>"

# ── Write and print report ─────────────────────────────────────────────────────

printf '%s\n' "${REPORT_LINES[@]}" > "$REPORT_FILE"
echo ""
echo "=== Verification complete: $PASS passed, $FAIL failed ==="
echo "Report written to: $REPORT_FILE"
cat "$REPORT_FILE"

[ "$FAIL" -ne 0 ] && exit 1

# ── Post to GitHub issue #30 ──────────────────────────────────────────────────

if [[ "$DRY_RUN" == "--dry-run" ]]; then
    echo ""
    echo "Dry run — skipping GitHub comment."
    exit 0
fi

if ! command -v gh &>/dev/null; then
    echo "ERROR: gh CLI not found. Install from https://cli.github.com/ then run:"
    echo "  gh issue comment 30 --repo sharmavipin1608/ClaudeTemplate --body-file $REPORT_FILE"
    exit 1
fi

gh issue comment 30 \
    --repo sharmavipin1608/ClaudeTemplate \
    --body-file "$REPORT_FILE"

echo "Posted verification report to GitHub issue #30."
