#!/usr/bin/env python3
"""Audit memory/facts.md for stale entries.

Usage:
    python3 tools/memory_audit.py [--days N] [--memory-dir PATH]

Lists all facts whose reviewed_at date is older than N days (default: 30).
"""
import argparse
import re
import sys
from datetime import date, timedelta
from pathlib import Path


def audit_facts(memory_dir: str = "memory", days: int = 30) -> list[dict]:
    facts_file = Path(memory_dir) / "facts.md"
    if not facts_file.exists():
        print(f"No facts file found at {facts_file}", file=sys.stderr)
        return []

    threshold = date.today() - timedelta(days=days)
    stale = []

    for i, line in enumerate(facts_file.read_text().splitlines(), start=1):
        line = line.strip()
        if not line or line.startswith("_") or line.startswith("#"):
            continue

        reviewed_match = re.search(r"reviewed_at:(\d{4}-\d{2}-\d{2})", line)
        if reviewed_match:
            reviewed_at = date.fromisoformat(reviewed_match.group(1))
            if reviewed_at < threshold:
                stale.append({"line": i, "fact": line, "reviewed_at": str(reviewed_at)})
        else:
            # Legacy entry — no reviewed_at field
            stale.append({"line": i, "fact": line, "reviewed_at": "legacy (no reviewed_at)"})

    return stale


def main():
    parser = argparse.ArgumentParser(description="Audit facts.md for stale entries")
    parser.add_argument("--days", type=int, default=30, help="Flag facts not reviewed in N days (default: 30)")
    parser.add_argument("--memory-dir", default="memory")
    args = parser.parse_args()

    stale = audit_facts(memory_dir=args.memory_dir, days=args.days)

    if not stale:
        print(f"All facts reviewed within the last {args.days} days.")
        return

    print(f"Found {len(stale)} fact(s) not reviewed in the last {args.days} days:\n")
    for entry in stale:
        print(f"  Line {entry['line']}: reviewed_at={entry['reviewed_at']}")
        print(f"    {entry['fact'][:120]}")
        print()


if __name__ == "__main__":
    main()
