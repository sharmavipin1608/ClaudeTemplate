#!/usr/bin/env python3
"""Search across memory files."""
import argparse
import sys
from difflib import SequenceMatcher
from pathlib import Path


class MemorySearch:
    def __init__(self, memory_dir: str = "memory"):
        self.memory_dir = Path(memory_dir)
        self._file_map = {
            "facts": "facts.md",
            "core": "core.md",
            "scratchpad": "scratchpad.md",
            "checkpoint": "session_checkpoint.md",
        }

    def _get_search_paths(self, files):
        if files:
            return [
                self.memory_dir / self._file_map[f]
                for f in files
                if f in self._file_map
            ]
        paths = [self.memory_dir / f for f in self._file_map.values()]
        episodic_dir = self.memory_dir / "episodic"
        if episodic_dir.exists():
            paths.extend(sorted(episodic_dir.glob("*.md")))
        return [p for p in paths if p.exists()]

    def _best_substring_ratio(self, query: str, text: str) -> float:
        """Return best SequenceMatcher ratio for query against any same-length window in text."""
        q = query.lower()
        t = text.lower()
        qlen = len(q)
        if qlen == 0:
            return 0.0
        if qlen > len(t):
            return SequenceMatcher(None, q, t).ratio()
        best = 0.0
        for i in range(len(t) - qlen + 1):
            r = SequenceMatcher(None, q, t[i:i + qlen]).ratio()
            if r > best:
                best = r
        return best

    def search(self, query: str, files=None, fuzzy: bool = False) -> list:
        results = []
        for path in self._get_search_paths(files):
            for line_num, line in enumerate(path.read_text().splitlines(), start=1):
                stripped = line.strip()
                if not stripped:
                    continue
                if fuzzy:
                    ratio = self._best_substring_ratio(query, stripped)
                    if ratio > 0.6:
                        results.append({
                            "file": path.name,
                            "line": line_num,
                            "text": stripped,
                            "score": ratio,
                        })
                else:
                    if query.lower() in stripped.lower():
                        results.append({
                            "file": path.name,
                            "line": line_num,
                            "text": stripped,
                        })
        if fuzzy:
            results.sort(key=lambda r: r["score"], reverse=True)
        return results


def main():
    parser = argparse.ArgumentParser(description="Search across memory files")
    parser.add_argument("query", help="Search query")
    parser.add_argument("--files", help="Comma-separated: facts,core,scratchpad,checkpoint")
    parser.add_argument("--fuzzy", action="store_true")
    parser.add_argument("--memory-dir", default="memory")
    args = parser.parse_args()

    files = args.files.split(",") if args.files else None
    searcher = MemorySearch(memory_dir=args.memory_dir)
    results = searcher.search(args.query, files=files, fuzzy=args.fuzzy)

    if not results:
        print("No results found.")
        sys.exit(0)

    for r in results:
        score = f" (score: {r['score']:.2f})" if "score" in r else ""
        print(f"{r['file']}:{r['line']}: {r['text']}{score}")


if __name__ == "__main__":
    main()
