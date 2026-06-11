#!/usr/bin/env python3
"""Analytical report from logs/pipeline.jsonl.

Usage:
    python3 tools/pipeline_analytics.py [--log PATH] [--last-days N]

Produces:
  - Agent timing statistics (min, p50, p95, max) derived from agent_start/agent_end pairs
  - Classifier verdict distribution and top rules fired
  - Reviewer rejection rate and most common reasons
  - Security block rate
  - Retry frequency per agent
"""
import argparse
import json
import sys
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path


def load_records(log_path: Path) -> list[dict]:
    if not log_path.exists():
        print(f"No pipeline log found at {log_path}", file=sys.stderr)
        return []
    records = []
    for i, line in enumerate(log_path.read_text().splitlines(), start=1):
        line = line.strip()
        if not line:
            continue
        try:
            records.append(json.loads(line))
        except json.JSONDecodeError as e:
            print(f"WARN: line {i} skipped ({e})", file=sys.stderr)
    return records


def percentile(values: list[float], p: int) -> float:
    if not values:
        return 0.0
    sorted_vals = sorted(values)
    idx = int(len(sorted_vals) * p / 100)
    idx = min(idx, len(sorted_vals) - 1)
    return round(sorted_vals[idx], 1)


def parse_ts(ts: str) -> datetime | None:
    try:
        return datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except Exception:
        return None


def analyze(records: list[dict]) -> None:
    if not records:
        print("No records to analyze.")
        return

    # Pair agent_start / agent_end by (agent, task_id) — FIFO queue per pair
    starts: dict[tuple, list[datetime]] = defaultdict(list)
    runs: dict[str, dict] = {}
    durations: dict[str, list[float]] = defaultdict(list)
    retries: dict[str, int] = defaultdict(int)
    outcomes: dict[str, dict[str, int]] = defaultdict(lambda: defaultdict(int))
    reviewer_reasons: list[str] = []
    security_blocks = 0
    security_total = 0
    classifier_verdicts: dict[str, int] = defaultdict(int)
    classifier_rules: dict[str, int] = defaultdict(int)

    outcome_links: list[dict] = []
    pipeline_task_ids: set[str] = set()

    for r in records:
        event = r.get("event", "")
        agent = r.get("agent", "unknown")
        task_id = r.get("task_id", "")
        ts = parse_ts(r.get("timestamp", ""))

        rid = r.get("run_id", "")
        if rid:
            info = runs.setdefault(rid, {"task_id": "", "pipeline": "", "tool_calls": 0, "outcome": ""})
            if task_id:
                info["task_id"] = task_id
            if event == "agent_start" and r.get("pipeline"):
                info["pipeline"] = r["pipeline"]
            elif event == "tool_call":
                info["tool_calls"] += 1
            elif event == "agent_end":
                info["outcome"] = f"{agent}:{r.get('outcome', '')}"

        if event == "agent_start" and ts:
            starts[(agent, task_id)].append(ts)

        elif event == "agent_end":
            outcome = r.get("outcome", "unknown")
            retry = int(r.get("retry", 0))
            reason = r.get("reason") or ""

            outcomes[agent][outcome] += 1
            retries[agent] += retry

            if task_id:
                pipeline_task_ids.add(task_id)

            if ts:
                pending = starts.get((agent, task_id))
                if pending:
                    start_ts = pending.pop(0)
                    dur = (ts - start_ts).total_seconds()
                    if dur >= 0:
                        durations[agent].append(dur)

            if agent == "reviewer" and outcome == "FIX_REQUIRED" and reason:
                reviewer_reasons.append(reason)

            if agent == "security":
                security_total += 1
                if outcome == "BLOCKED":
                    security_blocks += 1

        elif event == "classifier":
            verdict = r.get("verdict", "unknown")
            rule = r.get("rule_fired", "")
            classifier_verdicts[verdict] += 1
            if rule and verdict == "FORCE_FULL":
                classifier_rules[rule] += 1

        elif event == "outcome_link":
            outcome_links.append(r)

    print("=" * 60)
    print("PIPELINE ANALYTICS")
    print("=" * 60)
    print(f"Total records: {len(records)}\n")

    # Agent timing
    if durations:
        print("Agent Timing (seconds)")
        print(f"  {'Agent':<12} {'Min':>6} {'p50':>6} {'p95':>6} {'Max':>6} {'N':>4}")
        print(f"  {'-'*12} {'-'*6} {'-'*6} {'-'*6} {'-'*6} {'-'*4}")
        for agent in sorted(durations):
            vals = durations[agent]
            print(f"  {agent:<12} {min(vals):>6.1f} {percentile(vals,50):>6.1f} {percentile(vals,95):>6.1f} {max(vals):>6.1f} {len(vals):>4}")
        print()

    # Classifier
    if classifier_verdicts:
        total_clf = sum(classifier_verdicts.values())
        print("Classifier Verdicts")
        for v, n in sorted(classifier_verdicts.items(), key=lambda x: -x[1]):
            pct = 100 * n / total_clf if total_clf else 0
            print(f"  {v:<15} {n:>4}  ({pct:.0f}%)")
        if classifier_rules:
            print("  Top FORCE_FULL rules:")
            for rule, n in sorted(classifier_rules.items(), key=lambda x: -x[1])[:5]:
                print(f"    {n:>3}x  {rule}")
        print()

    # Agent outcomes
    if outcomes:
        print("Agent Outcomes")
        for agent in sorted(outcomes):
            parts = "  ".join(f"{o}:{n}" for o, n in sorted(outcomes[agent].items()))
            retry_n = retries.get(agent, 0)
            retry_str = f"  retries:{retry_n}" if retry_n else ""
            print(f"  {agent:<12} {parts}{retry_str}")
        print()

    # Reviewer rejection rate
    reviewer_ends = sum(outcomes.get("reviewer", {}).values())
    reviewer_rejected = outcomes.get("reviewer", {}).get("FIX_REQUIRED", 0)
    if reviewer_ends:
        rate = 100 * reviewer_rejected / reviewer_ends
        print(f"Reviewer rejection rate: {reviewer_rejected}/{reviewer_ends} ({rate:.0f}%)")
        if reviewer_reasons:
            print("  Recent rejection reasons:")
            for r in reviewer_reasons[-5:]:
                print(f"    - {r[:80]}")
        print()

    # Security block rate
    if security_total:
        block_rate = 100 * security_blocks / security_total
        print(f"Security block rate: {security_blocks}/{security_total} ({block_rate:.0f}%)")
        print()

    # Rework rate
    if not outcome_links:
        print("Rework rate: no data (no outcome_link events found)\n")
    else:
        rework_task_ids: set[str] = set()
        caused_by_counts: dict[str, int] = defaultdict(int)
        for link in outcome_links:
            link_task_id = link.get("task_id", "")
            caused_by = link.get("caused_by", "")
            if link_task_id:
                rework_task_ids.add(link_task_id)
            if caused_by:
                caused_by_counts[caused_by] += 1

        total_tasks = len(pipeline_task_ids)
        rework_count = len(rework_task_ids)
        rework_pct = 100 * rework_count / total_tasks if total_tasks else 0.0

        print("Rework Rate")
        print(f"  Rework tasks: {rework_count}/{total_tasks}  ({rework_pct:.0f}%)")
        if caused_by_counts:
            print("  Top rework sources:")
            for source, count in sorted(caused_by_counts.items(), key=lambda x: -x[1]):
                print(f"    {count}x  {source}")
        print()

    # Per-run summary
    if runs:
        print("Runs")
        print(f"  {'run_id':<38} {'task':<10} {'pipeline':<11} {'tools':>5}  last outcome")
        for rid, info in runs.items():
            print(f"  {rid:<38} {info['task_id']:<10} {info['pipeline']:<11} {info['tool_calls']:>5}  {info['outcome']}")
        print()

    print("=" * 60)


def main() -> None:
    parser = argparse.ArgumentParser(description="Analytical report from pipeline.jsonl")
    parser.add_argument("--log", default="logs/pipeline.jsonl")
    parser.add_argument("--run-id", default="", help="Only include records from this pipeline run")
    parser.add_argument("--last-days", type=int, default=0, help="Limit to last N days (0 = all)")
    args = parser.parse_args()

    records = load_records(Path(args.log))

    if args.run_id:
        records = [r for r in records if r.get("run_id") == args.run_id]

    if args.last_days:
        cutoff = datetime.now(timezone.utc).timestamp() - args.last_days * 86400
        records = [
            r for r in records
            if parse_ts(r.get("timestamp", "")) and
               parse_ts(r.get("timestamp", "")).timestamp() >= cutoff  # type: ignore
        ]

    analyze(records)


if __name__ == "__main__":
    main()
