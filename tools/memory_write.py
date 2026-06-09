#!/usr/bin/env python3
"""Write to memory files."""
import argparse
import re
import sys
from datetime import date
from pathlib import Path


VALID_SCOPES = {"project", "team", "org"}


class MemoryWriter:
    def __init__(self, memory_dir: str = "memory"):
        self.memory_dir = Path(memory_dir)

    def _load_taxonomy_tags(self) -> set:
        taxonomy_file = self.memory_dir / "taxonomy.md"
        if not taxonomy_file.exists():
            return set()
        tags = set()
        for line in taxonomy_file.read_text().splitlines():
            # Lines like: - **pipeline** — description
            m = re.match(r"^- \*\*(\w[\w-]*)\*\*", line)
            if m:
                tags.add(m.group(1))
        return tags

    def append_fact(self, tag: str, fact: str, source: str = "", task: str = "", scope: str = "") -> None:
        """Write a fact to facts.md. Deduplicates by [tag] + overlapping keywords.

        Requires source (agent name), task (task ID), and scope (project|team|org) for provenance tracking.
        """
        if not source:
            print("ERROR: --source (agent name) is required when writing a fact", file=sys.stderr)
            sys.exit(1)
        if not task:
            print("ERROR: --task (task ID) is required when writing a fact", file=sys.stderr)
            sys.exit(1)
        if not scope:
            print("ERROR: --scope (project|team|org) is required when writing a fact", file=sys.stderr)
            sys.exit(1)
        if scope not in VALID_SCOPES:
            print(f"ERROR: --scope must be one of {sorted(VALID_SCOPES)}, got '{scope}'", file=sys.stderr)
            sys.exit(1)

        known_tags = self._load_taxonomy_tags()
        if known_tags and tag not in known_tags:
            print(f"ERROR: tag '[{tag}]' not in taxonomy. Known tags: {sorted(known_tags)}. Add it to memory/taxonomy.md first.", file=sys.stderr)
            sys.exit(1)

        facts_file = self.memory_dir / "facts.md"
        today = str(date.today())
        new_entry = f"[{tag}] {fact} — {today} — reviewed_at:{today} — source:{source} — task:{task} — scope:{scope}\n"

        if facts_file.exists():
            lines = facts_file.read_text().splitlines(keepends=True)
            tag_pattern = re.compile(r"^\[" + re.escape(tag) + r"\]")
            fact_words = set(re.findall(r"\b\w{4,}\b", fact.lower()))

            for i, line in enumerate(lines):
                if not tag_pattern.match(line):
                    continue
                existing_words = set(re.findall(r"\b\w{4,}\b", line.lower()))
                overlap = fact_words & existing_words
                if len(overlap) >= 2:
                    # Near-duplicate: update the existing line in place
                    lines[i] = new_entry
                    facts_file.write_text("".join(lines))
                    return

        with facts_file.open("a") as f:
            f.write(new_entry)

    def mark_stale(self, fact_text: str) -> None:
        facts_file = self.memory_dir / "facts.md"
        if not facts_file.exists():
            return
        lines = facts_file.read_text().splitlines(keepends=True)
        updated = []
        for line in lines:
            if fact_text in line and not line.startswith("[stale]"):
                line = "[stale]" + line
            updated.append(line)
        facts_file.write_text("".join(updated))

    def write_checkpoint(self, content: str) -> None:
        checkpoint = self.memory_dir / "session_checkpoint.md"
        checkpoint.write_text(content)

    def append_episodic(self, entry: str) -> None:
        episodic_dir = self.memory_dir / "episodic"
        episodic_dir.mkdir(exist_ok=True)
        today_file = episodic_dir / f"{date.today()}.md"
        with today_file.open("a") as f:
            f.write(f"{entry}\n")

    def append_candidate(self, domain: str, candidate: str, rationale: str, seen_in: list[str]) -> None:
        candidates_file = self.memory_dir / "candidates.md"
        today = str(date.today())
        seen_str = ", ".join(seen_in) if seen_in else "unknown"
        entry = f"[{domain}] {candidate} — {today} — rationale:{rationale} — seen_in:{seen_str}\n"
        with candidates_file.open("a") as f:
            f.write(entry)


def main():
    parser = argparse.ArgumentParser(description="Write to memory files")
    parser.add_argument("--tag", help="Tag for new fact (e.g. 'auth', 'database')")
    parser.add_argument("--fact", help="Fact content to append")
    parser.add_argument("--source", default="", help="Agent that produced this fact (required with --fact)")
    parser.add_argument("--task", default="", help="Task ID this fact came from (required with --fact)")
    parser.add_argument("--scope", default="", help="Scope of fact: project, team, or org (required with --fact)")
    parser.add_argument("--stale", help="Mark this fact text as stale")
    parser.add_argument("--checkpoint", help="Content for session_checkpoint.md")
    parser.add_argument("--episodic", help="Entry for today's episodic log")
    parser.add_argument("--candidate", help="Convention candidate text")
    parser.add_argument("--candidate-domain", help="Domain tag for candidate")
    parser.add_argument("--rationale", default="", help="Why this is a candidate")
    parser.add_argument("--seen-in", default="", help="Comma-separated task IDs where this pattern appeared")
    parser.add_argument("--memory-dir", default="memory")
    args = parser.parse_args()

    writer = MemoryWriter(memory_dir=args.memory_dir)

    if args.tag and args.fact:
        writer.append_fact(tag=args.tag, fact=args.fact, source=args.source, task=args.task, scope=args.scope)
    elif args.candidate and args.candidate_domain:
        seen = [t.strip() for t in args.seen_in.split(",") if t.strip()] if args.seen_in else []
        writer.append_candidate(domain=args.candidate_domain, candidate=args.candidate, rationale=args.rationale, seen_in=seen)
    elif args.stale:
        writer.mark_stale(args.stale)
    elif args.checkpoint:
        writer.write_checkpoint(args.checkpoint)
    elif args.episodic:
        writer.append_episodic(args.episodic)
    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()
