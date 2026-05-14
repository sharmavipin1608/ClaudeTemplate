#!/usr/bin/env python3
"""Write to memory files."""
import argparse
import sys
from datetime import date
from pathlib import Path


class MemoryWriter:
    def __init__(self, memory_dir: str = "memory"):
        self.memory_dir = Path(memory_dir)

    def append_fact(self, tag: str, fact: str) -> None:
        facts_file = self.memory_dir / "facts.md"
        entry = f"[{tag}] {fact} — {date.today()}\n"
        with facts_file.open("a") as f:
            f.write(entry)

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


def main():
    parser = argparse.ArgumentParser(description="Write to memory files")
    parser.add_argument("--tag", help="Tag for new fact")
    parser.add_argument("--fact", help="Fact content to append")
    parser.add_argument("--stale", help="Mark this fact text as stale")
    parser.add_argument("--checkpoint", help="Content for session_checkpoint.md")
    parser.add_argument("--episodic", help="Entry for today's episodic log")
    parser.add_argument("--memory-dir", default="memory")
    args = parser.parse_args()

    writer = MemoryWriter(memory_dir=args.memory_dir)

    if args.tag and args.fact:
        writer.append_fact(tag=args.tag, fact=args.fact)
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
