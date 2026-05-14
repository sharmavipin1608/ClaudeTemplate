# ClaudeTemplate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build out the ClaudeTemplate repository from a single CLAUDE.md into a fully wired multi-agent Claude Code orchestration system ready to use as a GitHub template.

**Architecture:** Static snapshot template. 9 specialized agents in a pipeline (Researcher → Coder → Reviewer → Tester → Security → Git → Memory → Changelog + Writer on-demand), with a first-class Memory agent ensuring session continuity via `session_checkpoint.md`. Hooks automate logging, budget guarding, and error handling. Python stdlib tools handle memory I/O.

**Tech Stack:** Bash, Python 3 (stdlib only), Markdown

---

## File Map

**Create:**
```
.claude/settings.json
agents/AGENTS.md  ← routing registry (also top-level AGENTS.md)
agents/researcher.md
agents/coder.md
agents/reviewer.md
agents/tester.md
agents/security.md
agents/git.md
agents/memory.md
agents/changelog.md
agents/writer.md
skills/coding-patterns.md
skills/api-design.md
skills/test-strategy.md
skills/git-commit.md
skills/security-rules.md
memory/core.md               ← template with {{placeholders}}
memory/facts.md              ← empty with format comment
memory/scratchpad.md         ← empty template
memory/session_checkpoint.md ← initial state template
memory/episodic/.gitkeep
hooks/pre_task.sh
hooks/post_task.sh
hooks/log_tool.sh
hooks/budget_guard.sh
hooks/on_error.sh
logs/tool_calls.log          ← empty
logs/token_usage.log         ← empty
logs/traces/.gitkeep
tools/memory_read.py
tools/memory_write.py
tools/search.py
tests/tools/test_memory_read.py
tests/tools/test_memory_write.py
tests/tools/test_search.py
tools/__init__.py
tests/__init__.py
tests/tools/__init__.py
scripts/new-project.sh
AGENTS.md                    ← top-level registry
TASKS.md                     ← template
CONVENTIONS.md               ← template with TODOs
CHANGELOG.md                 ← empty
bootstrap.sh
README_TEMPLATE.md
README.md                    ← template project docs
```

**Modify:**
```
CLAUDE.md  ← add Memory agent to pipeline, session_checkpoint to memory load strategy
```

---

## Phase 1: Foundation

### Task 1: Create directory structure and placeholder files

**Files:**
- Create: all directories listed in the file map

- [ ] **Step 1: Create all directories and empty placeholder files**

```bash
mkdir -p .claude agents skills memory/episodic hooks logs/traces tools tests/tools scripts
touch logs/tool_calls.log logs/token_usage.log
touch memory/episodic/.gitkeep logs/traces/.gitkeep
touch tools/__init__.py tests/__init__.py tests/tools/__init__.py
```

- [ ] **Step 2: Verify structure**

```bash
find . -type d | sort | grep -v ".git"
```

Expected output includes: `.claude`, `agents`, `skills`, `memory`, `memory/episodic`, `hooks`, `logs`, `logs/traces`, `tools`, `tests`, `tests/tools`, `scripts`

- [ ] **Step 3: Commit**

```bash
git init  # if not already a repo
git add .
git commit -m "chore: scaffold directory structure"
```

---

### Task 2: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Replace the Agent Pipeline section**

Find the pipeline line and replace with the updated version including Memory agent:

Old:
```
Researcher → Coder → Reviewer → Tester → Security → Git → Changelog
```

New:
```
Researcher → Coder → Reviewer → Tester → Security → Git → Memory → Changelog
```

- [ ] **Step 2: Replace the Memory System load strategy section**

Find:
```markdown
4. Load `memory/scratchpad.md` for current working context
```

Replace with:
```markdown
4. Read `memory/session_checkpoint.md` for session recovery context
5. Load `memory/scratchpad.md` for current working context
```

- [ ] **Step 3: Update the Agents table in CLAUDE.md**

Add the memory agent row to the table:
```markdown
| `memory` | After git + ad-hoc on significant decisions | task output + scratchpad + facts | updated memory files + checkpoint |
```

- [ ] **Step 4: Update the Bootstrap Checklist**

Replace:
```markdown
## 🚀 Bootstrap Checklist (New Project)

- [ ] Run `bootstrap.sh` to fill `{{PROJECT_NAME}}` and `{{TECH_STACK}}`
- [ ] Fill `memory/core.md` with project identity
- [ ] Fill `CONVENTIONS.md` with your coding style
- [ ] Populate initial `TASKS.md` with first set of tasks
- [ ] Set budget limit in `hooks/budget_guard.sh`
- [ ] Confirm `settings.json` hooks are wired
```

With:
```markdown
## 🚀 Bootstrap Checklist (New Project)

- [ ] Run `new-project.sh` or use GitHub template → runs `bootstrap.sh` automatically
- [ ] `bootstrap.sh` handles: placeholders, memory/core.md, CONVENTIONS.md, TASKS.md, git init, optional GitHub repo
- [ ] First task after bootstrap: review and complete `CONVENTIONS.md`
- [ ] Adjust `budget.daily_token_limit` in `.claude/settings.json` if needed
```

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md with memory agent and session checkpoint"
```

---

### Task 3: Create `.claude/settings.json`

**Files:**
- Create: `.claude/settings.json`

- [ ] **Step 1: Write settings.json**

```json
{
  "hooks": {
    "PreToolUse": [
      { "command": "bash hooks/pre_task.sh" },
      { "command": "bash hooks/budget_guard.sh" },
      { "command": "bash hooks/log_tool.sh \"$TOOL_NAME\" \"$AGENT_NAME\"" }
    ],
    "PostToolUse": [
      { "command": "bash hooks/post_task.sh" },
      { "command": "bash hooks/log_tool.sh \"$TOOL_NAME\" \"$AGENT_NAME\"" }
    ],
    "Stop": [
      { "command": "bash hooks/on_error.sh" }
    ]
  },
  "budget": {
    "daily_token_limit": 100000,
    "mode": "warn"
  },
  "memory": {
    "checkpoint_on_task_complete": true,
    "stale_facts_after_days": 30
  },
  "agents": {
    "default_model": "claude-sonnet-4-6",
    "orchestrator_model": "claude-opus-4-7"
  }
}
```

- [ ] **Step 2: Verify valid JSON**

```bash
python3 -c "import json; json.load(open('.claude/settings.json')); print('valid')"
```

Expected: `valid`

- [ ] **Step 3: Commit**

```bash
git add .claude/settings.json
git commit -m "chore: add Claude Code settings with hooks and budget config"
```

---

## Phase 2: Python Memory Tools

### Task 4: memory_read.py (TDD)

**Files:**
- Create: `tools/memory_read.py`
- Test: `tests/tools/test_memory_read.py`

- [ ] **Step 1: Write failing tests**

`tests/tools/test_memory_read.py`:
```python
import pytest
from pathlib import Path
from tools.memory_read import MemoryReader


def test_read_by_tag_returns_matching_entries(tmp_path):
    facts = tmp_path / "facts.md"
    facts.write_text(
        "[auth] JWT rotates daily — 2026-01-01\n"
        "[database] PostgreSQL 15 — 2026-01-01\n"
        "[auth] Sessions disabled — 2026-01-02\n"
    )
    reader = MemoryReader(memory_dir=tmp_path)
    results = reader.read_by_tag("auth")
    assert len(results) == 2
    assert all("[auth]" in r for r in results)


def test_read_by_tag_excludes_stale_by_default(tmp_path):
    facts = tmp_path / "facts.md"
    facts.write_text(
        "[auth] JWT rotates daily — 2026-01-01\n"
        "[stale][auth] Old session auth — 2026-01-01\n"
    )
    reader = MemoryReader(memory_dir=tmp_path)
    results = reader.read_by_tag("auth")
    assert len(results) == 1
    assert "stale" not in results[0]


def test_read_by_tag_includes_stale_when_flagged(tmp_path):
    facts = tmp_path / "facts.md"
    facts.write_text(
        "[auth] JWT rotates daily — 2026-01-01\n"
        "[stale][auth] Old session auth — 2026-01-01\n"
    )
    reader = MemoryReader(memory_dir=tmp_path)
    results = reader.read_by_tag("auth", include_stale=True)
    assert len(results) == 2


def test_read_by_tag_returns_empty_when_no_match(tmp_path):
    facts = tmp_path / "facts.md"
    facts.write_text("[auth] JWT rotates daily — 2026-01-01\n")
    reader = MemoryReader(memory_dir=tmp_path)
    results = reader.read_by_tag("database")
    assert results == []


def test_read_by_tag_returns_empty_when_facts_missing(tmp_path):
    reader = MemoryReader(memory_dir=tmp_path)
    results = reader.read_by_tag("auth")
    assert results == []


def test_read_file_returns_full_content(tmp_path):
    core = tmp_path / "core.md"
    core.write_text("# Core\nProject info here")
    reader = MemoryReader(memory_dir=tmp_path)
    content = reader.read_file("core")
    assert "Project info here" in content


def test_read_file_raises_for_unknown_file(tmp_path):
    reader = MemoryReader(memory_dir=tmp_path)
    with pytest.raises(FileNotFoundError):
        reader.read_file("nonexistent")


def test_read_file_raises_for_missing_file(tmp_path):
    reader = MemoryReader(memory_dir=tmp_path)
    with pytest.raises(FileNotFoundError):
        reader.read_file("core")


def test_read_by_tag_skips_comment_lines(tmp_path):
    facts = tmp_path / "facts.md"
    facts.write_text(
        "# This is a comment\n"
        "[auth] JWT rotates daily — 2026-01-01\n"
    )
    reader = MemoryReader(memory_dir=tmp_path)
    results = reader.read_by_tag("auth")
    assert len(results) == 1
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
cd /Users/vipin/Projects/ClaudeTemplate
python3 -m pytest tests/tools/test_memory_read.py -v 2>&1 | head -20
```

Expected: `ModuleNotFoundError` or `ImportError` — tools/memory_read.py does not exist yet.

- [ ] **Step 3: Implement memory_read.py**

`tools/memory_read.py`:
```python
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
```

- [ ] **Step 4: Run tests — verify they pass**

```bash
python3 -m pytest tests/tools/test_memory_read.py -v
```

Expected: all 9 tests PASS

- [ ] **Step 5: Commit**

```bash
git add tools/__init__.py tools/memory_read.py tests/__init__.py tests/tools/__init__.py tests/tools/test_memory_read.py
git commit -m "feat: add memory_read.py with tag-based grep and file reader"
```

---

### Task 5: memory_write.py (TDD)

**Files:**
- Create: `tools/memory_write.py`
- Test: `tests/tools/test_memory_write.py`

- [ ] **Step 1: Write failing tests**

`tests/tools/test_memory_write.py`:
```python
import pytest
from datetime import date
from pathlib import Path
from tools.memory_write import MemoryWriter


def test_append_fact_creates_tagged_entry(tmp_path):
    facts = tmp_path / "facts.md"
    facts.write_text("")
    writer = MemoryWriter(memory_dir=tmp_path)
    writer.append_fact(tag="auth", fact="JWT rotates every 24h")
    content = facts.read_text()
    assert "[auth] JWT rotates every 24h" in content
    assert str(date.today()) in content


def test_append_fact_creates_facts_file_if_missing(tmp_path):
    writer = MemoryWriter(memory_dir=tmp_path)
    writer.append_fact(tag="auth", fact="JWT rotates every 24h")
    assert (tmp_path / "facts.md").exists()


def test_append_fact_appends_not_overwrites(tmp_path):
    facts = tmp_path / "facts.md"
    facts.write_text("[database] PostgreSQL 15 — 2026-01-01\n")
    writer = MemoryWriter(memory_dir=tmp_path)
    writer.append_fact(tag="auth", fact="JWT rotates every 24h")
    content = facts.read_text()
    assert "[database] PostgreSQL 15" in content
    assert "[auth] JWT rotates every 24h" in content


def test_mark_stale_prefixes_matching_entry(tmp_path):
    facts = tmp_path / "facts.md"
    facts.write_text("[auth] JWT rotates every 24h — 2026-01-01\n")
    writer = MemoryWriter(memory_dir=tmp_path)
    writer.mark_stale("JWT rotates every 24h")
    content = facts.read_text()
    assert "[stale][auth] JWT rotates every 24h" in content


def test_mark_stale_does_nothing_if_not_found(tmp_path):
    facts = tmp_path / "facts.md"
    original = "[auth] JWT rotates every 24h — 2026-01-01\n"
    facts.write_text(original)
    writer = MemoryWriter(memory_dir=tmp_path)
    writer.mark_stale("nonexistent fact")
    assert facts.read_text() == original


def test_mark_stale_does_not_double_prefix(tmp_path):
    facts = tmp_path / "facts.md"
    facts.write_text("[stale][auth] JWT rotates every 24h — 2026-01-01\n")
    writer = MemoryWriter(memory_dir=tmp_path)
    writer.mark_stale("JWT rotates every 24h")
    content = facts.read_text()
    assert content.count("[stale]") == 1


def test_write_checkpoint_overwrites_file(tmp_path):
    checkpoint = tmp_path / "session_checkpoint.md"
    checkpoint.write_text("old content")
    writer = MemoryWriter(memory_dir=tmp_path)
    writer.write_checkpoint("new content")
    assert checkpoint.read_text() == "new content"


def test_write_checkpoint_creates_file_if_missing(tmp_path):
    writer = MemoryWriter(memory_dir=tmp_path)
    writer.write_checkpoint("content")
    assert (tmp_path / "session_checkpoint.md").read_text() == "content"


def test_append_episodic_creates_daily_file(tmp_path):
    episodic_dir = tmp_path / "episodic"
    episodic_dir.mkdir()
    writer = MemoryWriter(memory_dir=tmp_path)
    writer.append_episodic("Task: init | Outcome: success")
    today = str(date.today())
    daily_file = episodic_dir / f"{today}.md"
    assert daily_file.exists()
    assert "Task: init" in daily_file.read_text()


def test_append_episodic_creates_episodic_dir_if_missing(tmp_path):
    writer = MemoryWriter(memory_dir=tmp_path)
    writer.append_episodic("Task: init | Outcome: success")
    episodic_dir = tmp_path / "episodic"
    assert episodic_dir.exists()
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
python3 -m pytest tests/tools/test_memory_write.py -v 2>&1 | head -10
```

Expected: `ModuleNotFoundError`

- [ ] **Step 3: Implement memory_write.py**

`tools/memory_write.py`:
```python
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
```

- [ ] **Step 4: Run tests — verify they pass**

```bash
python3 -m pytest tests/tools/test_memory_write.py -v
```

Expected: all 10 tests PASS

- [ ] **Step 5: Commit**

```bash
git add tools/memory_write.py tests/tools/test_memory_write.py
git commit -m "feat: add memory_write.py with fact append, stale marking, and checkpoint write"
```

---

### Task 6: search.py (TDD)

**Files:**
- Create: `tools/search.py`
- Test: `tests/tools/test_search.py`

- [ ] **Step 1: Write failing tests**

`tests/tools/test_search.py`:
```python
import pytest
from pathlib import Path
from tools.search import MemorySearch


def test_exact_search_finds_matching_text(tmp_path):
    facts = tmp_path / "facts.md"
    facts.write_text(
        "[auth] JWT rotates daily — 2026-01-01\n"
        "[database] PostgreSQL 15 — 2026-01-01\n"
    )
    searcher = MemorySearch(memory_dir=tmp_path)
    results = searcher.search("JWT rotates")
    assert len(results) == 1
    assert "JWT rotates daily" in results[0]["text"]


def test_search_returns_file_and_line_number(tmp_path):
    facts = tmp_path / "facts.md"
    facts.write_text("[auth] JWT rotates daily — 2026-01-01\n")
    searcher = MemorySearch(memory_dir=tmp_path)
    results = searcher.search("JWT")
    assert results[0]["file"] == "facts.md"
    assert results[0]["line"] == 1


def test_search_is_case_insensitive(tmp_path):
    facts = tmp_path / "facts.md"
    facts.write_text("[auth] JWT Rotates Daily — 2026-01-01\n")
    searcher = MemorySearch(memory_dir=tmp_path)
    results = searcher.search("jwt rotates")
    assert len(results) == 1


def test_search_returns_empty_when_no_match(tmp_path):
    facts = tmp_path / "facts.md"
    facts.write_text("[auth] JWT rotates daily — 2026-01-01\n")
    searcher = MemorySearch(memory_dir=tmp_path)
    results = searcher.search("nonexistent")
    assert results == []


def test_fuzzy_search_finds_approximate_match(tmp_path):
    facts = tmp_path / "facts.md"
    facts.write_text("[auth] JWT rotates daily — 2026-01-01\n")
    searcher = MemorySearch(memory_dir=tmp_path)
    results = searcher.search("JWT rotaets", fuzzy=True)  # intentional typo
    assert len(results) == 1


def test_search_limited_to_specified_files(tmp_path):
    facts = tmp_path / "facts.md"
    facts.write_text("[auth] JWT token — 2026-01-01\n")
    core = tmp_path / "core.md"
    core.write_text("JWT mentioned here too\n")
    searcher = MemorySearch(memory_dir=tmp_path)
    results = searcher.search("JWT", files=["facts"])
    assert len(results) == 1
    assert results[0]["file"] == "facts.md"


def test_search_across_multiple_files(tmp_path):
    facts = tmp_path / "facts.md"
    facts.write_text("[auth] JWT token — 2026-01-01\n")
    core = tmp_path / "core.md"
    core.write_text("JWT is used here\n")
    searcher = MemorySearch(memory_dir=tmp_path)
    results = searcher.search("JWT")
    assert len(results) == 2


def test_search_skips_blank_lines(tmp_path):
    facts = tmp_path / "facts.md"
    facts.write_text("\n\n[auth] JWT token — 2026-01-01\n\n")
    searcher = MemorySearch(memory_dir=tmp_path)
    results = searcher.search("JWT")
    assert len(results) == 1


def test_fuzzy_results_sorted_by_score(tmp_path):
    facts = tmp_path / "facts.md"
    facts.write_text(
        "[auth] JWT authentication token — 2026-01-01\n"
        "[auth] JWT auth — 2026-01-01\n"
    )
    searcher = MemorySearch(memory_dir=tmp_path)
    results = searcher.search("JWT auth", fuzzy=True)
    assert len(results) >= 1
    if len(results) > 1:
        assert results[0]["score"] >= results[1]["score"]
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
python3 -m pytest tests/tools/test_search.py -v 2>&1 | head -10
```

Expected: `ModuleNotFoundError`

- [ ] **Step 3: Implement search.py**

`tools/search.py`:
```python
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

    def search(self, query: str, files=None, fuzzy: bool = False) -> list:
        results = []
        for path in self._get_search_paths(files):
            for line_num, line in enumerate(path.read_text().splitlines(), start=1):
                stripped = line.strip()
                if not stripped:
                    continue
                if fuzzy:
                    ratio = SequenceMatcher(
                        None, query.lower(), stripped.lower()
                    ).ratio()
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
```

- [ ] **Step 4: Run all Python tool tests**

```bash
python3 -m pytest tests/tools/ -v
```

Expected: all tests PASS (9 + 10 + 9 = 28 tests)

- [ ] **Step 5: Commit**

```bash
git add tools/search.py tests/tools/test_search.py
git commit -m "feat: add search.py with exact and fuzzy search across memory files"
```

---

## Phase 3: Hook Scripts

### Task 7: Write all five hook scripts

**Files:**
- Create: `hooks/log_tool.sh`, `hooks/pre_task.sh`, `hooks/post_task.sh`, `hooks/budget_guard.sh`, `hooks/on_error.sh`

- [ ] **Step 1: Write hooks/log_tool.sh**

```bash
#!/bin/bash
# Usage: log_tool.sh "$TOOL_NAME" "$AGENT_NAME"
TOOL_NAME="${1:-unknown}"
AGENT_NAME="${2:-unknown}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
LOG_FILE="logs/tool_calls.log"
mkdir -p logs
echo "${TIMESTAMP} | ${AGENT_NAME} | ${TOOL_NAME}" >> "${LOG_FILE}"
```

- [ ] **Step 2: Write hooks/pre_task.sh**

```bash
#!/bin/bash
# Load relevant memory context before each tool call.
# Outputs to stderr so it appears in Claude's context without polluting stdout.
MEMORY_DIR="memory"

if [ -f "${MEMORY_DIR}/session_checkpoint.md" ]; then
    CHECKPOINT_SIZE=$(wc -c < "${MEMORY_DIR}/session_checkpoint.md")
    if [ "${CHECKPOINT_SIZE}" -gt 50 ]; then
        echo "=== SESSION CHECKPOINT ===" >&2
        cat "${MEMORY_DIR}/session_checkpoint.md" >&2
        echo "=========================" >&2
    fi
fi

if [ -f "${MEMORY_DIR}/scratchpad.md" ]; then
    SCRATCHPAD_SIZE=$(wc -c < "${MEMORY_DIR}/scratchpad.md")
    if [ "${SCRATCHPAD_SIZE}" -gt 100 ]; then
        echo "=== SCRATCHPAD ===" >&2
        cat "${MEMORY_DIR}/scratchpad.md" >&2
        echo "=================" >&2
    fi
fi
```

- [ ] **Step 3: Write hooks/post_task.sh**

```bash
#!/bin/bash
# Post-tool-call state update.
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
mkdir -p logs
echo "${TIMESTAMP} | POST_TOOL | done" >> "logs/tool_calls.log"
```

- [ ] **Step 4: Write hooks/budget_guard.sh**

```bash
#!/bin/bash
# Check daily token spend. Warn or halt based on CLAUDE_BUDGET_MODE.
# Set CLAUDE_DAILY_TOKEN_LIMIT and CLAUDE_BUDGET_MODE in your environment
# or rely on defaults below.
DAILY_LIMIT="${CLAUDE_DAILY_TOKEN_LIMIT:-100000}"
BUDGET_MODE="${CLAUDE_BUDGET_MODE:-warn}"
TOKEN_LOG="logs/token_usage.log"
mkdir -p logs

TODAYS_TOKENS=0
if [ -f "${TOKEN_LOG}" ]; then
    TODAY=$(date +"%Y-%m-%d")
    TODAYS_TOKENS=$(grep "^${TODAY}" "${TOKEN_LOG}" \
        | awk -F'|' '{sum += $4 + $5} END {print sum+0}')
fi

if [ "${TODAYS_TOKENS}" -ge "${DAILY_LIMIT}" ]; then
    echo "[BUDGET] Daily limit reached: ${TODAYS_TOKENS}/${DAILY_LIMIT} tokens used today." >&2
    if [ "${BUDGET_MODE}" = "halt" ]; then
        echo "[BUDGET] BUDGET_MODE=halt — stopping." >&2
        exit 1
    else
        echo "[BUDGET] BUDGET_MODE=warn — continuing." >&2
    fi
fi
```

- [ ] **Step 5: Write hooks/on_error.sh**

```bash
#!/bin/bash
# On agent failure: log error, update scratchpad, requeue task.
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
ERROR_MSG="${CLAUDE_ERROR_MESSAGE:-Unknown error}"
CURRENT_TASK="${CLAUDE_CURRENT_TASK:-Unknown task}"
LOG_FILE="logs/tool_calls.log"
TASKS_FILE="TASKS.md"
mkdir -p logs

echo "${TIMESTAMP} | ERROR | ${CURRENT_TASK} | ${ERROR_MSG}" >> "${LOG_FILE}"

if [ -f "memory/scratchpad.md" ]; then
    cat >> "memory/scratchpad.md" << EOF

## ERROR (${TIMESTAMP})
Task: ${CURRENT_TASK}
Error: ${ERROR_MSG}
Action required: Investigate and retry
EOF
fi

if [ -f "${TASKS_FILE}" ]; then
    # Use perl for portable in-place edit (sed -i differs on macOS vs Linux)
    perl -i -pe "s/\[ \] \Q${CURRENT_TASK}\E/[FAILED] ${CURRENT_TASK} — ${TIMESTAMP}/" "${TASKS_FILE}"
fi

echo "[ERROR] Task failed: ${CURRENT_TASK}. Check logs/tool_calls.log for details." >&2
```

- [ ] **Step 6: Make all hooks executable**

```bash
chmod +x hooks/pre_task.sh hooks/post_task.sh hooks/log_tool.sh hooks/budget_guard.sh hooks/on_error.sh
```

- [ ] **Step 7: Syntax check all hooks**

```bash
for f in hooks/*.sh; do bash -n "$f" && echo "OK: $f"; done
```

Expected: `OK: hooks/budget_guard.sh`, `OK: hooks/log_tool.sh`, `OK: hooks/on_error.sh`, `OK: hooks/post_task.sh`, `OK: hooks/pre_task.sh`

- [ ] **Step 8: Smoke test log_tool.sh**

```bash
mkdir -p logs
bash hooks/log_tool.sh "Read" "coder"
cat logs/tool_calls.log
```

Expected: a line like `2026-05-14T12:00:00Z | coder | Read`

- [ ] **Step 9: Smoke test budget_guard.sh in warn mode**

```bash
CLAUDE_DAILY_TOKEN_LIMIT=0 CLAUDE_BUDGET_MODE=warn bash hooks/budget_guard.sh
echo "exit: $?"
```

Expected: prints `[BUDGET] Daily limit reached` warning, exit code 0

- [ ] **Step 10: Smoke test budget_guard.sh in halt mode**

```bash
CLAUDE_DAILY_TOKEN_LIMIT=0 CLAUDE_BUDGET_MODE=halt bash hooks/budget_guard.sh
echo "exit: $?"
```

Expected: prints `[BUDGET] BUDGET_MODE=halt — stopping.`, exit code 1

- [ ] **Step 11: Commit**

```bash
git add hooks/
git commit -m "feat: add all five hook scripts (log, pre/post task, budget guard, error handler)"
```

---

## Phase 4: Memory File Templates

### Task 8: Write memory file templates

**Files:**
- Create: `memory/core.md`, `memory/facts.md`, `memory/scratchpad.md`, `memory/session_checkpoint.md`

- [ ] **Step 1: Write memory/core.md**

```markdown
# Project Core

**Name:** {{PROJECT_NAME}}
**Stack:** {{TECH_STACK}}
**Description:** {{DESCRIPTION}}
**Created:** {{DATE}}
**Owner:** {{OWNER_EMAIL}}

## Architecture Overview
_Fill this in as the architecture becomes clear._

## Key External Dependencies
_List major external services, APIs, or databases here._
```

- [ ] **Step 2: Write memory/facts.md**

```markdown
# Facts

_Format: [domain] fact — YYYY-MM-DD_
_Mark outdated entries with [stale] prefix — never delete._

```

- [ ] **Step 3: Write memory/scratchpad.md**

```markdown
# Scratchpad

_Current working context. Written by orchestrator at task start. Cleared by memory agent after task completion._

## Current Task
none

## Working Notes
none

## Decisions Made This Session
none
```

- [ ] **Step 4: Write memory/session_checkpoint.md**

```markdown
# Session Checkpoint

_Written by the memory agent after every task. A new Claude session reads this first._

**Last updated:** never
**Last completed task:** none

## Current State
Project just initialized. No tasks completed yet.

## Open Questions
none

## Next Task
Review and fill in CONVENTIONS.md (see TASKS.md)
```

- [ ] **Step 5: Commit**

```bash
git add memory/
git commit -m "feat: add memory file templates (core, facts, scratchpad, checkpoint)"
```

---

## Phase 5: Agent Files

_Tasks 9-11 can be worked in parallel — each agent file is independent._

### Task 9: Write researcher, coder, and reviewer agents

**Files:**
- Create: `agents/researcher.md`, `agents/coder.md`, `agents/reviewer.md`

- [ ] **Step 1: Write agents/researcher.md**

```markdown
# Researcher Agent

## Role
You are a researcher. Gather factual context about an unknown domain, technology, or requirement. You do NOT write code or make implementation decisions.

## You receive
- Task description
- Relevant sections from `memory/core.md`
- Relevant facts from `memory/facts.md` (pre-filtered by tag)

## You produce
A structured findings document, followed by new `facts.md` entries in this exact format:
```
[domain] fact — YYYY-MM-DD
```

## Rules
1. Facts and context only — no code, no opinions, no implementation suggestions
2. Cite sources when possible (URL, doc version, spec section)
3. If you cannot find reliable information, say so explicitly — do not guess
4. Flag contradictions with existing facts rather than silently overwriting them
5. Keep each fact atomic — one fact per line
6. Use specific domain tags: [auth], [database], [api], [infra], [testing], [security], or create a new tag if none fit
```

- [ ] **Step 2: Write agents/coder.md**

```markdown
# Coder Agent

## Role
You implement features using Test-Driven Development at the unit level.

## You receive
- Task description
- `memory/scratchpad.md` (current working context)
- `CONVENTIONS.md` (coding standards for this project)
- `skills/coding-patterns.md` (generic patterns)

## TDD cycle — mandatory for every unit of code
1. Write a failing test that describes expected behavior
2. Run the test — confirm it fails for the right reason (not a syntax error)
3. Write the minimal implementation to make it pass — no more than the test requires
4. Run the test — confirm it passes
5. Refactor if needed, keeping tests green
6. Commit when green

## You produce
- Implementation code + unit tests
- A brief summary: what was built, what tests cover, any decisions made

## Rules
1. If the task description is ambiguous — STOP. Report back to orchestrator with specific questions. Never assume.
2. Follow `CONVENTIONS.md` strictly. If a convention is missing for your situation, flag it in your summary.
3. No integration tests — that is the tester agent's responsibility
4. Each commit must be atomic and leave tests green
5. Do not refactor code outside the scope of your task
6. Use dependency injection so your code can be tested without real I/O
```

- [ ] **Step 3: Write agents/reviewer.md**

```markdown
# Reviewer Agent

## Role
You review code for quality and convention compliance. You also surface emerging patterns that should become conventions.

## You receive
- The code diff to review
- `CONVENTIONS.md`
- `skills/api-design.md`

## You produce
```
STATUS: PASS | FIX_REQUIRED

REQUIRED CHANGES (if any):
1. [file:line] Issue. Expected: X. Found: Y.
2. ...

CONVENTION CANDIDATES (if any):
- Pattern: [description]. Suggested rule: [rule text]
```

## Rules
1. Clearly separate "must fix" (blocks pipeline) from "suggested" (goes to convention candidates only — never blocks)
2. Reference `CONVENTIONS.md` when flagging required changes — do not invent rules not in the conventions
3. Do not review code outside the scope of the current task
4. Be specific: file, line number, what's wrong, what's expected
5. If a pattern appears 3+ times in the diff, add it as a convention candidate
```

- [ ] **Step 4: Commit**

```bash
git add agents/researcher.md agents/coder.md agents/reviewer.md
git commit -m "feat: add researcher, coder, and reviewer agent prompts"
```

---

### Task 10: Write tester, security, and git agents

**Files:**
- Create: `agents/tester.md`, `agents/security.md`, `agents/git.md`

- [ ] **Step 1: Write agents/tester.md**

```markdown
# Tester Agent

## Role
You write integration tests, edge case tests, and acceptance criteria tests. The coder agent has already written unit tests — your layer goes above those.

## You receive
- The implemented code
- `CONVENTIONS.md` (testing section)
- `skills/test-strategy.md`

## You produce
- Integration tests
- Edge case tests (boundary values, null inputs, empty collections, error paths)
- Acceptance criteria tests
- Full test suite run results

## Rules
1. Do NOT rewrite or replace the coder's unit tests — add to them
2. Every test name must describe the scenario and expected outcome: `test_login_fails_with_expired_token` not `test_login`
3. All tests must pass before handoff to security — do not proceed with failing tests
4. If tests fail: attempt one fix. If still failing, report back to orchestrator with the exact failure and what you tried.
5. Test the seams between components, not every internal detail
6. Use real infrastructure where possible (real DB, real filesystem with tmp isolation) — do not mock what you can use
```

- [ ] **Step 2: Write agents/security.md**

```markdown
# Security Agent

## Role
You are a hard gate. This pipeline STOPS if you find blockers. No exceptions.

## You receive
- The full diff of changes
- `skills/security-rules.md`

## You produce
```
STATUS: PASS | BLOCKED

BLOCKERS (if any):
1. [SEVERITY: HIGH|MEDIUM] [file:line] Vulnerability description. Attack vector: X. Recommended fix: Y.
2. ...
```

## Rules
1. This is a hard gate — `BLOCKED` stops the pipeline completely, no negotiation
2. Never soften a blocker into a suggestion
3. If you are uncertain whether something is a vulnerability, flag it as a blocker — false positives are acceptable; false negatives are not
4. Check every diff for: injection (SQL, command, path), exposed secrets, insecure defaults, missing auth checks, unvalidated input at system boundaries, insecure direct object references
5. Do not approve code that contains hardcoded secrets or credentials under any circumstances
```

- [ ] **Step 3: Write agents/git.md**

```markdown
# Git Agent

## Role
You commit and push completed, reviewed, tested, and security-cleared code.

## You receive
- The diff to commit
- `skills/git-commit.md`
- The git section of `CONVENTIONS.md`

## You produce
- A commit following the project's message convention
- The commit pushed to the remote branch

## Rules
1. Follow the commit message format from `skills/git-commit.md` exactly
2. Never force push under any circumstances
3. Never commit: secrets, credentials, `.env` files, build artifacts, or generated files unless explicitly required by the task
4. Stage only files relevant to this task — do not `git add .` blindly
5. If the push fails: report back to orchestrator with the exact error — do not retry destructively
6. Commit message describes WHY, not what (the diff shows what)
```

- [ ] **Step 4: Commit**

```bash
git add agents/tester.md agents/security.md agents/git.md
git commit -m "feat: add tester, security, and git agent prompts"
```

---

### Task 11: Write memory, changelog, and writer agents

**Files:**
- Create: `agents/memory.md`, `agents/changelog.md`, `agents/writer.md`

- [ ] **Step 1: Write agents/memory.md**

```markdown
# Memory Agent

## Role
You maintain all memory files and ensure session continuity. You are the only agent that writes to memory files — other agents flag things for you to write.

## You receive
- The completed task output
- `memory/scratchpad.md` (current working context)
- `memory/facts.md` (current facts)
- `CONVENTIONS.md` (to identify convention candidates)

## You produce
All five outputs on every pipeline run:

**1. New facts** — extract decisions, discoveries, and architectural choices. Append to `memory/facts.md`:
```
[domain] fact — YYYY-MM-DD
```

**2. Updated session checkpoint** — overwrite `memory/session_checkpoint.md`:
```
# Session Checkpoint

**Last updated:** YYYY-MM-DD
**Last completed task:** [task name]

## Current State
[1-3 sentences describing where the project stands right now]

## Key Decisions This Session
- [decision 1 — enough context for a fresh session to understand it]
- [decision 2]

## Open Questions
- [anything unresolved that the next session should know about]

## Next Task
[next item from TASKS.md]
```

**3. Episodic log entry** — append to `memory/episodic/YYYY-MM-DD.md`:
```
[HH:MM] Task: [name] | Outcome: [one sentence] | Decisions: [key decisions]
```

**4. Clear scratchpad** — overwrite `memory/scratchpad.md` with the empty template:
```
# Scratchpad

## Current Task
none

## Working Notes
none

## Decisions Made This Session
none
```

**5. Convention candidates** — if any patterns from this task should be added to `CONVENTIONS.md`, list them for the orchestrator in your summary output.

## When called ad-hoc (not end of pipeline)
Update scratchpad and checkpoint only. Do NOT clear the scratchpad — the task is still in progress.

## Rules
1. Always write the checkpoint — even if nothing significant happened this task
2. Never delete facts — mark outdated entries `[stale]` and append a replacement
3. The checkpoint must be readable by a fresh Claude session with zero prior context — write it that way
4. Keep facts atomic — one fact per line, one claim per fact
5. Use `tools/memory_write.py` when available for reliable file writes
```

- [ ] **Step 2: Write agents/changelog.md**

```markdown
# Changelog Agent

## Role
You maintain `CHANGELOG.md` in a human-readable format. You run at end of day or end of sprint.

## You receive
- `git log --oneline` output since the last changelog entry
- Today's episodic log (`memory/episodic/YYYY-MM-DD.md`)

## You produce
An updated `CHANGELOG.md` with new entries prepended, grouped by feature.

## Format
```markdown
## [YYYY-MM-DD]

### Added
- Plain-language description of new capability

### Changed
- What changed and why (user-facing impact)

### Fixed
- What was broken and what the fix resolves
```

## Rules
1. Write for a human reading it months later — not a developer reading the diff
2. Group related commits into single feature descriptions — do not dump raw commit messages
3. Omit purely internal changes (refactors, test cleanup) unless they affect observable behavior
4. Each entry should answer: what changed, and why does it matter to someone using this project
```

- [ ] **Step 3: Write agents/writer.md**

```markdown
# Writer Agent

## Role
You write documentation on demand. You run outside the main pipeline, triggered explicitly by the orchestrator.

## You receive
- Task description (what to document and for whom)
- `memory/core.md`
- Relevant source code
- The docs section of `CONVENTIONS.md`

## You produce
Markdown documentation files.

## Rules
1. No implementation — documentation only
2. Follow doc style from `CONVENTIONS.md`
3. Write for the stated audience: README for newcomers, API docs for integrators, ADRs for future maintainers
4. Every document must answer three questions: what is this, how do I use it, what do I need to know
5. Include working examples wherever possible
6. Do not describe what the code does — describe what the user can do with it
```

- [ ] **Step 4: Write agents/AGENTS.md (agent index)**

```markdown
# Agents

Quick index. Full routing rules and triggering conditions: see top-level `AGENTS.md`.

| Agent | File | Role |
|---|---|---|
| Researcher | `researcher.md` | Context gathering for unknown domains |
| Coder | `coder.md` | TDD implementation |
| Reviewer | `reviewer.md` | Code quality + convention enforcement |
| Tester | `tester.md` | Integration + acceptance tests |
| Security | `security.md` | Hard security gate |
| Git | `git.md` | Commit and push |
| Memory | `memory.md` | Memory maintenance + session continuity |
| Changelog | `changelog.md` | CHANGELOG.md updates |
| Writer | `writer.md` | Documentation (on demand) |
```

- [ ] **Step 5: Commit**

```bash
git add agents/memory.md agents/changelog.md agents/writer.md agents/AGENTS.md
git commit -m "feat: add memory, changelog, writer agents and agents index"
```

---

## Phase 6: Skill Files

_All five skill files are independent and can be written in parallel._

### Task 12: Write all five skill files

**Files:**
- Create: `skills/coding-patterns.md`, `skills/api-design.md`, `skills/test-strategy.md`, `skills/git-commit.md`, `skills/security-rules.md`

- [ ] **Step 1: Write skills/coding-patterns.md**

```markdown
# Coding Patterns

Generic patterns for any language or stack. Supplement with stack-specific conventions in `CONVENTIONS.md`.

## Naming
- Names reveal intent. If you need a comment to explain a name, rename it.
- Functions: verb phrases (`getUserById`, `calculate_total`, `fetchConfig`)
- Booleans: `is`, `has`, `can`, `should` prefix (`isActive`, `hasPermission`)
- Collections: plural nouns (`users`, `items`, `errors`)
- Constants: SCREAMING_SNAKE_CASE

## Functions
- One function, one responsibility. If "and" appears in the description, split it.
- Under 20 lines as a soft limit — if longer, it's probably doing too much
- Pure functions preferred: same input → same output, no side effects
- Use early returns and guard clauses to avoid deep nesting

## Error Handling
- Validate at system boundaries (user input, external APIs, file I/O)
- Trust internal code — no defensive checks inside already-validated flows
- Error messages: what went wrong + what to do about it
- Never silently swallow exceptions

## Dependencies
- Inject dependencies — don't instantiate them inside functions you want to test
- Depend on abstractions, not concrete implementations

## YAGNI
- No abstractions until you have 3+ concrete cases
- No configuration for things that don't vary yet
- No design for hypothetical future requirements
- Three similar lines is better than a premature abstraction
```

- [ ] **Step 2: Write skills/api-design.md**

```markdown
# API Design Principles

## Response Envelope
All API responses use a consistent structure:

Success:
```json
{
  "data": { ... },
  "error": null,
  "meta": { "timestamp": "2026-05-14T12:00:00Z", "version": "1" }
}
```

Error:
```json
{
  "data": null,
  "error": { "code": "RESOURCE_NOT_FOUND", "message": "User 123 not found" },
  "meta": { "timestamp": "2026-05-14T12:00:00Z" }
}
```

## HTTP Conventions
- GET: retrieve only, never mutate
- POST: create
- PUT: full replacement
- PATCH: partial update
- DELETE: remove
- Resource names are nouns: `/users/123` not `/getUser?id=123`

## Status Codes
- 200: success
- 201: created (POST)
- 400: client error — invalid input
- 401: unauthenticated — who are you?
- 403: unauthorized — I know who you are, but no
- 404: not found
- 409: conflict (e.g. duplicate)
- 422: validation error
- 500: server error — never expose internals in the message

## Versioning
- Version in URL path: `/v1/users`
- Never break a published version — add a new version instead

## Error Messages
- Machine-readable: consistent `code` field (SCREAMING_SNAKE_CASE)
- Human-readable: plain language `message`
- Actionable: tell the caller what to fix

## Pagination
- Cursor-based for large or frequently-changing datasets
- Always return a `next_cursor` and total count
- Default page size: 20. Maximum: 100.

## Input Validation
- Validate at the API boundary, not inside service logic
- Return all validation errors at once — not just the first one
- Be strict on input; lenient on output
```

- [ ] **Step 3: Write skills/test-strategy.md**

```markdown
# Test Strategy

## Test Pyramid
- **Unit (most):** Test individual functions in isolation. No I/O. Milliseconds to run.
- **Integration (some):** Test components working together with real infrastructure. Seconds to run.
- **End-to-end (few):** Test full user journeys. Minutes to run. Use sparingly.

## What Makes a Good Test
- Tests one thing — one concept per test
- Name is a specification: `test_login_fails_with_expired_token` not `test_login_2`
- Arrange-Act-Assert structure
- Independent — tests do not depend on each other or share mutable state
- Deterministic — same result on every run, regardless of order

## Unit Test Rules
- No file I/O, no network, no database, no `time.sleep`
- Use dependency injection to swap real dependencies for test doubles
- Test the public interface — not implementation details
- Always test: happy path, empty/null inputs, boundary values, error paths

## Integration Test Rules
- Use real infrastructure (real DB, real filesystem in tmpdir) over mocks
- Use transactions or tmp directories for isolation — clean up after each test
- Test the seam between components, not every internal detail

## What NOT to Test
- Framework internals (ORM queries, HTTP routing — they have their own test suites)
- Trivial pass-through code with no logic
- Code that only calls other well-tested code

## TDD Discipline
1. Write the failing test first — confirm it fails for the right reason
2. Write minimal code to pass — only what the test requires
3. Refactor — clean up while keeping tests green
4. Commit when green — never commit with failing tests
```

- [ ] **Step 4: Write skills/git-commit.md**

```markdown
# Git Commit Conventions

## Format
```
<type>(<scope>): <short description>

[optional body — explain WHY, not what]

[optional footer — breaking changes, issue refs]
```

## Types
- `feat`: new user-facing feature
- `fix`: bug fix
- `refactor`: code change with no feature or fix
- `test`: adding or updating tests only
- `docs`: documentation only
- `chore`: build, tooling, config, dependencies
- `perf`: performance improvement

## Rules
- Subject: imperative mood, max 72 chars, no period
  - `feat: add JWT refresh token rotation` ✓
  - `added JWT refresh token` ✗
- Body: explain WHY — the diff shows what
- One logical change per commit
- Every commit must leave tests passing
- Never commit secrets, `.env` files, or credentials

## Atomic Commits
- One commit = one thing
- "Add feature X and fix bug Y" → two commits
- If you need "and" to describe it, split it

## Examples
```
feat(auth): add JWT refresh token rotation

Tokens were single-use with no refresh path, forcing re-login every hour.
This adds automatic rotation on each authenticated request.
```

```
fix(api): return 422 instead of 500 for invalid email input
```

```
chore: upgrade postgres driver to 3.2.0
```
```

- [ ] **Step 5: Write skills/security-rules.md**

```markdown
# Security Rules

## Injection
- Never concatenate user input into SQL, shell commands, HTML, or file paths
- Use parameterized queries / prepared statements for all database access
- Validate and sanitize all user input at system boundaries
- Escape output for its rendering context (HTML entity encoding, shell quoting)

## Authentication & Authorization
- Never implement custom crypto or auth — use established, audited libraries
- Hash passwords with bcrypt, argon2, or scrypt — never MD5 or SHA1 alone
- Check authorization on every request — a logged-in user is not automatically authorized for everything
- Invalidate tokens/sessions on logout and password change

## Secrets
- No hardcoded secrets, API keys, or credentials in source code — ever
- Never commit `.env` files
- Use environment variables or a secrets manager
- Rotate secrets regularly; short lifetimes are better than long ones

## Input Validation
- Validate type, format, length, and allowed range for every input
- Reject unknown fields — do not pass them through silently
- Server-side validation is authoritative — never trust client-side validation alone

## Security Checklist (run on every diff)
- [ ] SQL injection: all queries use parameterized statements
- [ ] Command injection: no user input passed to shell commands
- [ ] Path traversal: file paths validated and sandboxed
- [ ] XSS: user content escaped before rendering in HTML
- [ ] CSRF: state-changing requests protected (if using cookie auth)
- [ ] Exposed secrets: no credentials, tokens, or keys in code or logs
- [ ] Exposed error detail: no stack traces or internal paths in API responses
- [ ] Missing auth checks: every endpoint checks authentication and authorization
- [ ] Insecure direct object references: access to resources checked by ownership/permission
- [ ] Mass assignment: only explicitly allowed fields accepted from user input
- [ ] Missing rate limiting: auth endpoints have rate limits
```

- [ ] **Step 6: Commit**

```bash
git add skills/
git commit -m "feat: add all five skill files (coding patterns, API design, test strategy, git, security)"
```

---

## Phase 7: Supporting Files

### Task 13: Write AGENTS.md, TASKS.md, CONVENTIONS.md, and CHANGELOG.md

**Files:**
- Create: `AGENTS.md`, `TASKS.md`, `CONVENTIONS.md`, `CHANGELOG.md`

- [ ] **Step 1: Write AGENTS.md (top-level routing registry)**

```markdown
# Agent Registry

## Pipeline

Run in order for implementation tasks:

| Agent | File | Trigger | Reads | Produces |
|---|---|---|---|---|
| Researcher | `agents/researcher.md` | Unknown domain or requirement | task + core.md + facts | findings → facts.md |
| Coder | `agents/coder.md` | Implementation task | task + scratchpad + CONVENTIONS.md + skills/coding-patterns.md | code + unit tests |
| Reviewer | `agents/reviewer.md` | After coder | diff + CONVENTIONS.md + skills/api-design.md | PASS or fix list |
| Tester | `agents/tester.md` | After reviewer PASS | code + CONVENTIONS.md + skills/test-strategy.md | integration tests + results |
| Security | `agents/security.md` | After tester | diff + skills/security-rules.md | PASS or BLOCKERS |
| Git | `agents/git.md` | After security PASS | diff + skills/git-commit.md | commit + push |
| Memory | `agents/memory.md` | After git + ad-hoc | task output + scratchpad + facts | updated memory files |
| Changelog | `agents/changelog.md` | End of day/sprint | git log + episodic log | CHANGELOG.md updated |

## On-Demand

| Agent | File | Trigger |
|---|---|---|
| Writer | `agents/writer.md` | Docs explicitly needed |

## Routing Rules

**Use Researcher first when:**
- The technology or library is unfamiliar
- Requirements are unclear or contradictory
- Existing facts.md entries conflict with each other

**Skip Researcher when:**
- Task is in a well-understood domain with adequate facts

**Call Memory ad-hoc when:**
- A significant architectural decision was just made
- The session may end soon and context would be lost
- A blocker was resolved that future sessions should know about

**Pipeline stops when:**
- Security returns `BLOCKED` — do not proceed to git under any circumstances
```

- [ ] **Step 2: Write TASKS.md**

```markdown
# Tasks

## Active
- [ ] Review and fill in CONVENTIONS.md

## Backlog

## Completed

## Failed
```

- [ ] **Step 3: Write CONVENTIONS.md**

```markdown
# Conventions — {{PROJECT_NAME}}

_Actively maintained by the reviewer and memory agents. When patterns emerge they get promoted here._

---

## Code Style
# TODO: Define naming conventions for {{TECH_STACK}}
# TODO: Define formatting rules (linter/formatter? which tool?)
# TODO: Language-specific patterns to follow

## Architecture
# TODO: Define folder structure conventions
# TODO: Which patterns to use (e.g. repository pattern, service layer)
# TODO: Anti-patterns to avoid in this project

## Testing
# TODO: Unit vs. integration test boundary for this project
# TODO: Where tests live relative to source
# TODO: Minimum coverage expectations

## Git
- Branch naming: `feature/<name>`, `fix/<name>`, `chore/<name>`
- Commit style: see `skills/git-commit.md`
# TODO: PR size expectations
# TODO: Review requirements (how many approvals?)

## API / Interface Design
# TODO: Request/response format (if applicable)
# TODO: Error format
# TODO: Versioning approach

## Agent Rules
# TODO: Project-specific rules for agents (what to always/never do here)

## Docs
# TODO: Documentation style
# TODO: What must be documented (public APIs? all modules? only README?)
```

- [ ] **Step 4: Write CHANGELOG.md**

```markdown
# Changelog
```

- [ ] **Step 5: Commit**

```bash
git add AGENTS.md TASKS.md CONVENTIONS.md CHANGELOG.md
git commit -m "feat: add AGENTS.md registry, TASKS.md, CONVENTIONS.md template, CHANGELOG.md"
```

---

## Phase 8: Bootstrap System

### Task 14: Write bootstrap.sh

**Files:**
- Create: `bootstrap.sh`

- [ ] **Step 1: Write bootstrap.sh**

```bash
#!/bin/bash
set -e

TEMPLATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${TEMPLATE_DIR}"

echo ""
echo "╔══════════════════════════════════════╗"
echo "║     ClaudeTemplate Bootstrap         ║"
echo "╚══════════════════════════════════════╝"
echo ""

# ── Step 1: Gather project information ──────────────────────────────────────
FOLDER_NAME=$(basename "${TEMPLATE_DIR}")
read -rp "Project name [${FOLDER_NAME}]: " PROJECT_NAME
PROJECT_NAME="${PROJECT_NAME:-$FOLDER_NAME}"

read -rp "Tech stack (e.g. 'Python + FastAPI + PostgreSQL'): " TECH_STACK
while [ -z "${TECH_STACK}" ]; do
    echo "Tech stack is required."
    read -rp "Tech stack: " TECH_STACK
done

read -rp "One-line project description: " DESCRIPTION
while [ -z "${DESCRIPTION}" ]; do
    echo "Description is required."
    read -rp "Description: " DESCRIPTION
done

OWNER_EMAIL=$(git config user.email 2>/dev/null || echo "")
read -rp "Owner email [${OWNER_EMAIL}]: " INPUT_EMAIL
OWNER_EMAIL="${INPUT_EMAIL:-$OWNER_EMAIL}"

TODAY=$(date +"%Y-%m-%d")

echo ""
echo "→ Setting up: ${PROJECT_NAME} (${TECH_STACK})"
echo ""

# ── Step 2: Replace placeholders ────────────────────────────────────────────
echo "→ Replacing placeholders..."
find . -type f \( -name "*.md" -o -name "*.sh" -o -name "*.json" -o -name "*.py" \) \
    ! -path "./.git/*" ! -path "./logs/*" | while IFS= read -r file; do
    perl -i \
        -pe "s/\{\{PROJECT_NAME\}\}/${PROJECT_NAME}/g" \
        -pe "s/\{\{TECH_STACK\}\}/${TECH_STACK}/g" \
        -pe "s/\{\{DESCRIPTION\}\}/${DESCRIPTION}/g" \
        -pe "s/\{\{DATE\}\}/${TODAY}/g" \
        -pe "s/\{\{OWNER_EMAIL\}\}/${OWNER_EMAIL}/g" \
        "${file}" 2>/dev/null || true
done

# ── Step 3: Populate memory/core.md ─────────────────────────────────────────
echo "→ Populating memory/core.md..."
mkdir -p memory/episodic
cat > memory/core.md << EOF
# Project Core

**Name:** ${PROJECT_NAME}
**Stack:** ${TECH_STACK}
**Description:** ${DESCRIPTION}
**Created:** ${TODAY}
**Owner:** ${OWNER_EMAIL}

## Architecture Overview
_Fill this in as the architecture becomes clear._

## Key External Dependencies
_List major external services, APIs, or databases here._
EOF

# ── Step 4: Initialize memory files ─────────────────────────────────────────
echo "→ Initializing memory files..."
cat > memory/facts.md << 'EOF'
# Facts

_Format: [domain] fact — YYYY-MM-DD_
_Mark outdated entries with [stale] prefix — never delete._

EOF

cat > memory/scratchpad.md << 'EOF'
# Scratchpad

## Current Task
none

## Working Notes
none

## Decisions Made This Session
none
EOF

cat > memory/session_checkpoint.md << EOF
# Session Checkpoint

**Last updated:** ${TODAY}
**Last completed task:** none

## Current State
Project initialized from ClaudeTemplate. No tasks completed yet.

## Next Task
Review and fill in CONVENTIONS.md (see TASKS.md)
EOF

# ── Step 5: Write TASKS.md ───────────────────────────────────────────────────
echo "→ Writing TASKS.md..."
cat > TASKS.md << EOF
# Tasks — ${PROJECT_NAME}

## Active
- [ ] Review and fill in CONVENTIONS.md

## Backlog

## Completed

## Failed
EOF

# ── Step 6: Write CONVENTIONS.md ────────────────────────────────────────────
echo "→ Writing CONVENTIONS.md..."
cat > CONVENTIONS.md << EOF
# Conventions — ${PROJECT_NAME}

_Actively maintained by the reviewer and memory agents._

---

## Code Style
# TODO: Define naming conventions for ${TECH_STACK}
# TODO: Define formatting rules

## Architecture
# TODO: Define folder structure
# TODO: Which patterns to use/avoid

## Testing
# TODO: Unit vs. integration boundary
# TODO: Where tests live
# TODO: Minimum coverage expectations

## Git
- Branch naming: \`feature/<name>\`, \`fix/<name>\`, \`chore/<name>\`
- Commit style: see \`skills/git-commit.md\`
# TODO: PR size and review requirements

## API / Interface Design
# TODO: Request/response format (if applicable)

## Agent Rules
# TODO: Project-specific agent rules

## Docs
# TODO: Documentation style and requirements
EOF

# ── Step 7: Generate README.md ───────────────────────────────────────────────
echo "→ Generating README.md..."
if [ -f "README_TEMPLATE.md" ]; then
    cp README_TEMPLATE.md README.md
    perl -i \
        -pe "s/\{\{PROJECT_NAME\}\}/${PROJECT_NAME}/g" \
        -pe "s/\{\{TECH_STACK\}\}/${TECH_STACK}/g" \
        -pe "s/\{\{DESCRIPTION\}\}/${DESCRIPTION}/g" \
        -pe "s/\{\{DATE\}\}/${TODAY}/g" \
        README.md
    rm README_TEMPLATE.md
fi

# ── Step 8: Write CHANGELOG.md ───────────────────────────────────────────────
cat > CHANGELOG.md << EOF
# Changelog — ${PROJECT_NAME}

## [${TODAY}]
### Added
- Project initialized from ClaudeTemplate
EOF

# ── Step 9: Reinitialize git ─────────────────────────────────────────────────
echo "→ Reinitializing git..."
rm -rf .git
git init
git add -A
git commit -m "chore: init ${PROJECT_NAME} from ClaudeTemplate"

# ── Step 10: Optionally create GitHub repo ───────────────────────────────────
echo ""
read -rp "Create GitHub repo? (y/n) [n]: " CREATE_REPO
CREATE_REPO="${CREATE_REPO:-n}"

if [ "${CREATE_REPO}" = "y" ] || [ "${CREATE_REPO}" = "Y" ]; then
    read -rp "Visibility (public/private) [private]: " VISIBILITY
    VISIBILITY="${VISIBILITY:-private}"

    if command -v gh &>/dev/null; then
        echo "→ Creating GitHub repo..."
        gh repo create "${PROJECT_NAME}" "--${VISIBILITY}" --source=. --remote=origin --push
        echo "✓ Repository created and pushed."
    else
        echo "⚠  gh CLI not found. Install from https://cli.github.com/"
        echo "   Then run: gh repo create ${PROJECT_NAME} --${VISIBILITY} --source=. --remote=origin --push"
    fi
fi

echo ""
echo "✓ ${PROJECT_NAME} is ready."
echo ""
echo "Next steps:"
echo "  1. Open this project in Claude Code"
echo "  2. First task: Review and complete CONVENTIONS.md"
echo "  3. Start building!"
```

- [ ] **Step 2: Make executable and syntax check**

```bash
chmod +x bootstrap.sh
bash -n bootstrap.sh && echo "syntax OK"
```

Expected: `syntax OK`

- [ ] **Step 3: Commit**

```bash
git add bootstrap.sh
git commit -m "feat: add bootstrap.sh project setup wizard"
```

---

### Task 15: Write new-project.sh

**Files:**
- Create: `scripts/new-project.sh`

- [ ] **Step 1: Write scripts/new-project.sh**

```bash
#!/bin/bash
# new-project.sh — copy this to ~/Projects/ and run it to start a new project.
# Edit TEMPLATE_REPO below to point to your ClaudeTemplate GitHub repo.
set -e

TEMPLATE_REPO="https://github.com/YOUR_GITHUB_USERNAME/ClaudeTemplate.git"
PROJECTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo "╔══════════════════════════════════════╗"
echo "║       New Claude Project             ║"
echo "╚══════════════════════════════════════╝"
echo ""

read -rp "Project folder name: " PROJECT_NAME
while [ -z "${PROJECT_NAME}" ]; do
    echo "Project name is required."
    read -rp "Project folder name: " PROJECT_NAME
done

TARGET_DIR="${PROJECTS_DIR}/${PROJECT_NAME}"

if [ -d "${TARGET_DIR}" ]; then
    echo "Error: '${TARGET_DIR}' already exists."
    exit 1
fi

echo "→ Cloning template into ${TARGET_DIR}..."
git clone "${TEMPLATE_REPO}" "${TARGET_DIR}"

echo "→ Running bootstrap..."
cd "${TARGET_DIR}"
bash bootstrap.sh
```

- [ ] **Step 2: Make executable and syntax check**

```bash
chmod +x scripts/new-project.sh
bash -n scripts/new-project.sh && echo "syntax OK"
```

Expected: `syntax OK`

- [ ] **Step 3: Commit**

```bash
git add scripts/new-project.sh
git commit -m "feat: add new-project.sh local project creation script"
```

---

## Phase 9: README Files

### Task 16: Write README.md and README_TEMPLATE.md

**Files:**
- Create: `README.md`, `README_TEMPLATE.md`

- [ ] **Step 1: Write README.md (template project documentation)**

```markdown
# ClaudeTemplate

A reusable GitHub template for AI-assisted software development with Claude Code. Ships a fully wired multi-agent orchestration system — ready to use on day one.

## What's Included

- **9 specialized agents** — Researcher, Coder (TDD), Reviewer, Tester, Security (hard gate), Git, Memory, Changelog, Writer
- **Session-persistent memory** — `session_checkpoint.md` survives session close; new sessions reconstruct context from files
- **Automated hooks** — tool call logging, budget guard (warn or halt), error handler with task requeue
- **Python memory tools** — read by tag, write facts, fuzzy search across memory files (stdlib only)
- **Bootstrap wizard** — `bootstrap.sh` initializes a new project in under 2 minutes

## Using This Template

### Option A — GitHub (recommended for most projects)
1. Click **"Use this template"** on GitHub
2. Create your new repo
3. Clone it locally: `git clone <your-new-repo> && cd <your-new-repo>`
4. Run: `bash bootstrap.sh`

### Option B — Local script
1. Copy `scripts/new-project.sh` to `~/Projects/`
2. Edit it: replace `YOUR_GITHUB_USERNAME` with your GitHub username
3. Run: `bash ~/Projects/new-project.sh`

## What bootstrap.sh Does

1. Prompts for project name, tech stack, description, owner email
2. Replaces all `{{placeholders}}` across all files
3. Populates `memory/core.md`
4. Generates `CONVENTIONS.md` with TODO markers and `TASKS.md` with first task
5. Generates `README.md` from `README_TEMPLATE.md`
6. `git init` + initial commit
7. Optionally creates GitHub repo via `gh` CLI and pushes

## Daily Workflow

```
Open project in Claude Code
        ↓
Claude reads memory/session_checkpoint.md  ← picks up where you left off
        ↓
Describe your task
        ↓
Orchestrator delegates to pipeline agents
        ↓
Memory agent writes checkpoint after task  ← safe to close at any time
```

## Agent Pipeline

```
Researcher → Coder → Reviewer → Tester → Security → Git → Memory → Changelog
```

Writer runs on demand outside the pipeline.

## Memory System

| File | Purpose |
|---|---|
| `memory/core.md` | Project identity — populated by bootstrap.sh |
| `memory/facts.md` | Tagged facts: `[auth] JWT rotates daily — 2026-01-01` |
| `memory/scratchpad.md` | Current task context — cleared after each task |
| `memory/session_checkpoint.md` | **Session recovery** — first file read when a new session opens |
| `memory/episodic/YYYY-MM-DD.md` | Daily log |

## Configuration

`.claude/settings.json`:

```json
{
  "budget": {
    "daily_token_limit": 100000,
    "mode": "warn"
  }
}
```

- Change `mode` to `"halt"` for strict token enforcement
- Adjust `daily_token_limit` per project
- `agents.orchestrator_model` defaults to `claude-opus-4-7` (planning)
- `agents.default_model` defaults to `claude-sonnet-4-6` (execution)

## Memory Tools

```bash
# Read facts by tag
python3 tools/memory_read.py --tag auth

# Write a new fact
python3 tools/memory_write.py --tag auth --fact "JWT rotates every 24h"

# Search across all memory files
python3 tools/search.py "JWT" --fuzzy
```

## Running Tests

```bash
python3 -m pytest tests/ -v
```
```

- [ ] **Step 2: Write README_TEMPLATE.md**

```markdown
# {{PROJECT_NAME}}

{{DESCRIPTION}}

**Stack:** {{TECH_STACK}}
**Created:** {{DATE}}

## Getting Started

_Fill this in._

## Development

### Prerequisites
_Fill this in._

### Setup
_Fill this in._

### Running Tests
_Fill this in._

## Architecture

_Fill this in once the architecture stabilizes._

## Deployment

_Fill this in._
```

- [ ] **Step 3: Commit**

```bash
git add README.md README_TEMPLATE.md
git commit -m "docs: add README.md (template docs) and README_TEMPLATE.md (new project base)"
```

---

## Phase 10: Integration Test

### Task 17: End-to-end test of bootstrap.sh

- [ ] **Step 1: Run all Python tests to confirm baseline is green**

```bash
python3 -m pytest tests/ -v
```

Expected: all tests PASS

- [ ] **Step 2: Test bootstrap.sh in a temp directory**

```bash
# Create a copy of the template to test with
cp -r /Users/vipin/Projects/ClaudeTemplate /tmp/ClaudeTemplate-test
cd /tmp/ClaudeTemplate-test

# Run bootstrap with test values (non-interactive via stdin)
printf "TestProject\nPython + FastAPI\nA test project\ntest@example.com\nn\n" | bash bootstrap.sh
```

- [ ] **Step 3: Verify bootstrap output**

```bash
cd /tmp/ClaudeTemplate-test

# Check placeholders were replaced
grep -r "{{PROJECT_NAME}}" . --include="*.md" --include="*.sh" --include="*.json" | grep -v ".git"
```

Expected: no output (all placeholders replaced)

```bash
# Check memory files were populated
cat memory/core.md
```

Expected: `**Name:** TestProject`, `**Stack:** Python + FastAPI`

```bash
# Check README_TEMPLATE.md was removed
ls README_TEMPLATE.md 2>/dev/null && echo "FAIL: should be removed" || echo "OK: removed"
```

Expected: `OK: removed`

```bash
# Check git was reinitialized (no template history)
git log --oneline
```

Expected: exactly one commit: `chore: init TestProject from ClaudeTemplate`

- [ ] **Step 4: Clean up test directory**

```bash
cd /Users/vipin/Projects/ClaudeTemplate
rm -rf /tmp/ClaudeTemplate-test
```

- [ ] **Step 5: Final commit — verify repo is clean**

```bash
git status
```

Expected: `nothing to commit, working tree clean`

- [ ] **Step 6: Run full test suite one final time**

```bash
python3 -m pytest tests/ -v
```

Expected: all 28 tests PASS

---

## Summary

| Phase | Tasks | Key outputs |
|---|---|---|
| 1 Foundation | 1-3 | Directories, CLAUDE.md updated, settings.json |
| 2 Python Tools | 4-6 | memory_read.py, memory_write.py, search.py (28 tests) |
| 3 Hooks | 7 | 5 hook scripts, syntax-checked and smoke-tested |
| 4 Memory Templates | 8 | core.md, facts.md, scratchpad.md, session_checkpoint.md |
| 5 Agent Files | 9-11 | 9 agent prompt files |
| 6 Skill Files | 12 | 5 skill files |
| 7 Supporting Files | 13 | AGENTS.md, TASKS.md, CONVENTIONS.md, CHANGELOG.md |
| 8 Bootstrap | 14-15 | bootstrap.sh, new-project.sh |
| 9 README | 16 | README.md, README_TEMPLATE.md |
| 10 Integration | 17 | End-to-end bootstrap test |
