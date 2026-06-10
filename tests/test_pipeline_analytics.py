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
