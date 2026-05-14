#!/usr/bin/env python3
"""Read from memory files by tag or filename."""
import argparse
import sys
from pathlib import Path


class MemoryReader:
    def __init__(self, memory_dir: str = "memory"):
        self.memory_dir = Path(memory_dir)
        self._file_map = {
            "core": "core.md",
            "facts": "facts.md",
            "scratchpad": "scratchpad.md",
            "checkpoint": "session_checkpoint.md",
        }

    def read_by_tag(self, tag: str, include_stale: bool = False) -> list:
        facts_file = self.memory_dir / "facts.md"
        if not facts_file.exists():
            return []
        results = []
        for line in facts_file.read_text().splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if f"[{tag}]" not in line:
                continue
            if not include_stale and "[stale]" in line:
                continue
            results.append(line)
        return results

    def read_file(self, name: str) -> str:
        if name not in self._file_map:
            raise FileNotFoundError(f"Unknown memory file: {name}")
        path = self.memory_dir / self._file_map[name]
        if not path.exists():
            raise FileNotFoundError(f"Memory file not found: {path}")
        return path.read_text()


def main():
    parser = argparse.ArgumentParser(description="Read from memory files")
    parser.add_argument("--tag", help="Tag to grep from facts.md")
    parser.add_argument("--file", help="Memory file to read: core|scratchpad|checkpoint|facts")
    parser.add_argument("--include-stale", action="store_true")
    parser.add_argument("--memory-dir", default="memory")
    args = parser.parse_args()

    reader = MemoryReader(memory_dir=args.memory_dir)

    if args.tag:
        for r in reader.read_by_tag(args.tag, include_stale=args.include_stale):
            print(r)
    elif args.file:
        try:
            print(reader.read_file(args.file))
        except FileNotFoundError as e:
            print(f"Error: {e}", file=sys.stderr)
            sys.exit(1)
    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()
