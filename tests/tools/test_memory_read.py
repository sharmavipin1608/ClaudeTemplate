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
