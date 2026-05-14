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
