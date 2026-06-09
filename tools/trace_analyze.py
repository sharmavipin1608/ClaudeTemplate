#!/usr/bin/env python3
"""Analyze logs/pipeline.jsonl and print a human-readable pipeline summary.

Usage:
    python3 tools/trace_analyze.py [--log PATH] [--last N]

Options:
    --log PATH    Path to pipeline.jsonl (default: logs/pipeline.jsonl)
    --last N      Only show the last N agent_end events (default: all)
"""
import argparse
import json
import sys
from collections import defaultdict
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
            print(f"WARN: line {i} is not valid JSON ({e}), skipping", file=sys.stderr)
    return records


def summarize(records: list[dict], last: int = 0) -> None:
    if not records:
        print("No pipeline records found.")
        return

    # Counts
    agent_starts = [r for r in records if r.get("event") == "agent_start"]
    agent_ends   = [r for r in records if r.get("event") == "agent_end"]
    classifier   = [r for r in records if r.get("event") == "classifier"]
    tool_calls   = [r for r in records if r.get("event") == "tool_call"]

    if last:
        agent_ends = agent_ends[-last:]

    print(f"Pipeline log: {len(records)} total records")
    print(f"  agent_start events : {len(agent_starts)}")
    print(f"  agent_end events   : {len(agent_ends)}")
    print(f"  tool_call events   : {len(tool_calls)}")
    print(f"  classifier events  : {len(classifier)}")
    print()

    # Classifier distribution
    if classifier:
        verdict_counts: dict[str, int] = defaultdict(int)
        rule_counts: dict[str, int] = defaultdict(int)
        for c in classifier:
            verdict_counts[c.get("verdict", "unknown")] += 1
            rule = c.get("rule_fired", "")
            if rule:
                rule_counts[rule] += 1
        print("Classifier verdicts:")
        for verdict, count in sorted(verdict_counts.items(), key=lambda x: -x[1]):
            print(f"  {verdict:<15} {count}")
        if rule_counts:
            print("Top classifier rules fired:")
            for rule, count in sorted(rule_counts.items(), key=lambda x: -x[1])[:5]:
                print(f"  {count:>3}x  {rule}")
        print()

    # Agent outcome summary
    if agent_ends:
        outcome_by_agent: dict[str, dict[str, int]] = defaultdict(lambda: defaultdict(int))
        retry_total = 0
        for e in agent_ends:
            agent = e.get("agent", "unknown")
            outcome = e.get("outcome", "unknown")
            outcome_by_agent[agent][outcome] += 1
            retry_total += int(e.get("retry", 0))

        print("Agent outcomes:")
        for agent in sorted(outcome_by_agent):
            outcomes = outcome_by_agent[agent]
            outcome_str = "  ".join(f"{o}:{n}" for o, n in sorted(outcomes.items()))
            print(f"  {agent:<12} {outcome_str}")
        if retry_total:
            print(f"Total retries across all agents: {retry_total}")
        print()

    # Tool call distribution (top 10)
    if tool_calls:
        tool_counts: dict[str, int] = defaultdict(int)
        for t in tool_calls:
            tool_counts[t.get("tool", "unknown")] += 1
        print("Tool call distribution (top 10):")
        for tool, count in sorted(tool_counts.items(), key=lambda x: -x[1])[:10]:
            print(f"  {count:>4}x  {tool}")
        print()


def main() -> None:
    parser = argparse.ArgumentParser(description="Analyze pipeline.jsonl")
    parser.add_argument("--log", default="logs/pipeline.jsonl", help="Path to pipeline.jsonl")
    parser.add_argument("--last", type=int, default=0, help="Show last N agent_end events only")
    args = parser.parse_args()

    records = load_records(Path(args.log))
    summarize(records, last=args.last)


if __name__ == "__main__":
    main()
