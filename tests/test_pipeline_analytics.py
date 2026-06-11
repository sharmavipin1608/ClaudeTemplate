"""Tests for tools/pipeline_analytics.py — rework rate and core analyze() behavior."""
import io
import sys
from pathlib import Path

import pytest

# Allow imports from the repo root
sys.path.insert(0, str(Path(__file__).parent.parent))

from tools.pipeline_analytics import analyze, load_records


FIXTURES_DIR = Path(__file__).parent / "fixtures"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def capture_analyze(records):
    """Run analyze(records) and return captured stdout as a string."""
    buf = io.StringIO()
    old_stdout = sys.stdout
    sys.stdout = buf
    try:
        analyze(records)
    finally:
        sys.stdout = old_stdout
    return buf.getvalue()


# ---------------------------------------------------------------------------
# Test 1: rework rate from pipeline_rework.jsonl fixture
# ---------------------------------------------------------------------------

def test_rework_rate_from_fixture():
    fixture = FIXTURES_DIR / "pipeline_rework.jsonl"
    records = load_records(fixture)
    output = capture_analyze(records)

    assert "2/5" in output, f"Expected '2/5' in output:\n{output}"
    assert "40%" in output, f"Expected '40%' in output:\n{output}"
    assert "TASK-002" in output, f"Expected 'TASK-002' in output:\n{output}"


# ---------------------------------------------------------------------------
# Test 2: empty records list — no crash, prints "No records to analyze"
# ---------------------------------------------------------------------------

def test_analyze_empty_records():
    output = capture_analyze([])
    assert "No records to analyze" in output


# ---------------------------------------------------------------------------
# Test 3: records with no outcome_link events — prints "no data" message
# ---------------------------------------------------------------------------

def test_no_outcome_link_events():
    records = [
        {"event": "agent_end", "agent": "coder", "task_id": "TASK-001",
         "outcome": "DONE", "retry": 0, "timestamp": "2026-06-09T10:00:00+00:00"},
        {"event": "agent_end", "agent": "tester", "task_id": "TASK-002",
         "outcome": "PASS", "retry": 0, "timestamp": "2026-06-09T10:10:00+00:00"},
    ]
    output = capture_analyze(records)
    assert "no data" in output.lower(), f"Expected 'no data' in output:\n{output}"
    assert "outcome_link" in output, f"Expected 'outcome_link' mention in output:\n{output}"


# ---------------------------------------------------------------------------
# Test 4: rework rate calculation correctness — 2 rework tasks / 5 total = 40%
# ---------------------------------------------------------------------------

def test_rework_rate_calculation():
    records = [
        # 5 unique task_ids from agent_end
        {"event": "agent_end", "agent": "coder", "task_id": "TASK-001",
         "outcome": "DONE", "retry": 0, "timestamp": "2026-06-09T10:00:00+00:00"},
        {"event": "agent_end", "agent": "coder", "task_id": "TASK-002",
         "outcome": "DONE", "retry": 0, "timestamp": "2026-06-09T10:05:00+00:00"},
        {"event": "agent_end", "agent": "coder", "task_id": "TASK-003",
         "outcome": "DONE", "retry": 0, "timestamp": "2026-06-09T10:10:00+00:00"},
        {"event": "agent_end", "agent": "coder", "task_id": "TASK-004",
         "outcome": "DONE", "retry": 0, "timestamp": "2026-06-09T10:15:00+00:00"},
        {"event": "agent_end", "agent": "coder", "task_id": "TASK-005",
         "outcome": "DONE", "retry": 0, "timestamp": "2026-06-09T10:20:00+00:00"},
        # 2 outcome_link events (TASK-004 and TASK-005 are rework tasks)
        {"event": "outcome_link", "task_id": "TASK-004", "caused_by": "TASK-002",
         "timestamp": "2026-06-09T10:25:00+00:00"},
        {"event": "outcome_link", "task_id": "TASK-005", "caused_by": "TASK-002",
         "timestamp": "2026-06-09T10:30:00+00:00"},
    ]
    output = capture_analyze(records)

    assert "2/5" in output, f"Expected '2/5' in output:\n{output}"
    assert "40%" in output, f"Expected '40%' in output:\n{output}"
    # TASK-002 caused 2 reworks — should appear as top source
    assert "TASK-002" in output, f"Expected 'TASK-002' in output:\n{output}"
    # Verify the "2x" count for top source
    assert "2x" in output, f"Expected '2x' count in output:\n{output}"


# ---------------------------------------------------------------------------
# Test 5: --run-id filter excludes other runs
# ---------------------------------------------------------------------------

import json
import subprocess

_REPO = Path(__file__).resolve().parent.parent


def _run_analytics(args):
    return subprocess.run(
        [sys.executable, str(_REPO / "tools" / "pipeline_analytics.py"), *args],
        capture_output=True, text=True, check=True,
    ).stdout


def test_run_id_filter_excludes_other_runs(tmp_path):
    log = tmp_path / "pipeline.jsonl"
    recs = [
        {"event": "agent_start", "agent": "coder", "task_id": "TASK-1", "pipeline": "full",
         "timestamp": "2026-06-09T10:00:00Z", "run_id": "run-a"},
        {"event": "agent_end", "agent": "coder", "task_id": "TASK-1", "outcome": "DONE",
         "retry": 0, "timestamp": "2026-06-09T10:05:00Z", "run_id": "run-a"},
        {"event": "agent_end", "agent": "tester", "task_id": "TASK-2", "outcome": "FAIL",
         "reason": "other run", "retry": 0, "timestamp": "2026-06-09T11:00:00Z", "run_id": "run-b"},
    ]
    log.write_text("\n".join(json.dumps(r) for r in recs) + "\n")
    out = _run_analytics(["--log", str(log), "--run-id", "run-a"])
    assert "run-a" in out
    assert "run-b" not in out


# ---------------------------------------------------------------------------
# Test 6: runs summary lists each run
# ---------------------------------------------------------------------------

def test_runs_summary_lists_each_run(tmp_path):
    log = tmp_path / "pipeline.jsonl"
    recs = [
        {"event": "agent_start", "agent": "coder", "task_id": "TASK-1", "pipeline": "full",
         "timestamp": "2026-06-09T10:00:00Z", "run_id": "run-a"},
        {"event": "tool_call", "tool": "Bash", "agent": "coder", "task_id": "TASK-1",
         "timestamp": "2026-06-09T10:01:00Z", "run_id": "run-a"},
        {"event": "agent_end", "agent": "coder", "task_id": "TASK-1", "outcome": "DONE",
         "retry": 0, "timestamp": "2026-06-09T10:05:00Z", "run_id": "run-a"},
        {"event": "agent_start", "agent": "coder", "task_id": "TASK-2", "pipeline": "fast-track",
         "timestamp": "2026-06-09T11:00:00Z", "run_id": "run-b"},
    ]
    log.write_text("\n".join(json.dumps(r) for r in recs) + "\n")
    out = _run_analytics(["--log", str(log)])
    assert "Runs" in out
    assert "run-a" in out and "run-b" in out


# ---------------------------------------------------------------------------
# Test 7: retry duration pairing is FIFO (not overwrite)
# ---------------------------------------------------------------------------

def test_retry_duration_pairing_is_fifo(tmp_path):
    log = tmp_path / "pipeline.jsonl"
    recs = [
        {"event": "agent_start", "agent": "coder", "task_id": "TASK-1", "pipeline": "full",
         "timestamp": "2026-06-09T10:00:00Z", "run_id": "run-a"},
        {"event": "agent_end", "agent": "coder", "task_id": "TASK-1", "outcome": "DONE",
         "retry": 0, "timestamp": "2026-06-09T10:01:00Z", "run_id": "run-a"},
        {"event": "agent_start", "agent": "coder", "task_id": "TASK-1", "pipeline": "full",
         "timestamp": "2026-06-09T10:10:00Z", "run_id": "run-a"},
        {"event": "agent_end", "agent": "coder", "task_id": "TASK-1", "outcome": "DONE",
         "retry": 1, "timestamp": "2026-06-09T10:12:00Z", "run_id": "run-a"},
    ]
    log.write_text("\n".join(json.dumps(r) for r in recs) + "\n")
    out = _run_analytics(["--log", str(log)])
    # N=2 durations for coder; max is 120s (not 720s, which the overwrite bug produced)
    coder_line = next(l for l in out.splitlines() if l.strip().startswith("coder"))
    assert " 2" in coder_line
    assert "120.0" in coder_line
    assert "720.0" not in out
