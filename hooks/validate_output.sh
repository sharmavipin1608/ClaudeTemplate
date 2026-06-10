#!/bin/bash
# Validates agent JSON envelope output against contracts/<agent>.json
# Usage: bash hooks/validate_output.sh <agent_name>  (reads envelope from stdin)
# Exit 0: valid. Exit 1: invalid (error written to stderr).
set -euo pipefail

AGENT="${1:-}"
[ -z "$AGENT" ] && { echo "ERROR: agent name required" >&2; exit 1; }

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# Contracts live at .claude/contracts/ in bootstrapped projects, contracts/ in the template repo itself.
if [ -d "$PROJECT_ROOT/.claude/contracts" ]; then
    CONTRACTS_DIR="$PROJECT_ROOT/.claude/contracts"
else
    CONTRACTS_DIR="$PROJECT_ROOT/contracts"
fi
CONTRACT="$CONTRACTS_DIR/${AGENT}.json"

[ ! -f "$CONTRACT" ] && { echo "ERROR: no contract found for agent '${AGENT}' at ${CONTRACT}" >&2; exit 1; }

export VALIDATE_INPUT_B64
VALIDATE_INPUT_B64=$(cat | base64)
export VALIDATE_CONTRACT="$CONTRACT"
export VALIDATE_PROJECT_ROOT="$PROJECT_ROOT"
export VALIDATE_RUN_ID
VALIDATE_RUN_ID=$(python3 -c "import json; d=json.load(open('${PROJECT_ROOT}/pipeline_state.json')); print(d.get('run_id',''))" 2>/dev/null || echo "")

python3 - <<'PYEOF'
import sys, json, base64, os
from pathlib import Path
from datetime import datetime, timezone

input_b64 = os.environ.get("VALIDATE_INPUT_B64", "")
contract_path = os.environ.get("VALIDATE_CONTRACT", "")
project_root = os.environ.get("VALIDATE_PROJECT_ROOT", ".")

try:
    raw = base64.b64decode(input_b64).decode("utf-8")
    envelope = json.loads(raw)
except Exception as e:
    print(f"ERROR: output is not valid JSON: {e}", file=sys.stderr)
    sys.exit(1)

try:
    with open(contract_path) as f:
        contract = json.load(f)
except Exception as e:
    print(f"ERROR: failed to load contract '{contract_path}': {e}", file=sys.stderr)
    sys.exit(1)

errors = []

for field in contract["required_fields"]:
    if field not in envelope:
        errors.append(f"missing required field: '{field}'")

if "agent" in envelope and envelope["agent"] != contract["agent"]:
    errors.append(f"agent mismatch: expected '{contract['agent']}', got '{envelope['agent']}'")

if "verdict" in envelope:
    verdict = envelope["verdict"]
    if verdict not in contract["valid_verdicts"]:
        errors.append(f"invalid verdict '{verdict}': must be one of {contract['valid_verdicts']}")
    elif verdict in contract.get("reason_required_on", []):
        if not envelope.get("reason"):
            errors.append(f"verdict '{verdict}' requires a non-empty 'reason' field")

if errors:
    agent_name = contract.get("agent", "unknown")
    print(f"VALIDATION FAILED for agent '{agent_name}':", file=sys.stderr)
    for e in errors:
        print(f"  - {e}", file=sys.stderr)
    sys.exit(1)

# Append validated envelope to pipeline.jsonl, injecting run_id if available
try:
    log_dir = Path(project_root) / "logs"
    log_dir.mkdir(exist_ok=True)
    pipeline_log = log_dir / "pipeline.jsonl"
    run_id = os.environ.get("VALIDATE_RUN_ID", "")
    if run_id:
        envelope["run_id"] = run_id
    with pipeline_log.open("a") as f:
        f.write(json.dumps(envelope) + "\n")
except Exception as e:
    # Non-fatal: validation succeeded; log the write failure to stderr only
    print(f"WARN: failed to write to pipeline.jsonl: {e}", file=sys.stderr)

print(f"OK: {envelope.get('agent')} verdict={envelope.get('verdict')}")
PYEOF
