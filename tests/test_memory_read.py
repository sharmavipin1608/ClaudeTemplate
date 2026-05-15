import pytest
from pathlib import Path
from tools.memory_read import MemoryReader


@pytest.fixture
def memory_dir(tmp_path):
    facts = tmp_path / "facts.md"
    facts.write_text(
        "# Facts\n"
        "[auth] JWT secret rotates every 24h\n"
        "[database] PostgreSQL 15\n"
        "[auth] tokens stored in httpOnly cookies [stale]\n"
    )
    core = tmp_path / "core.md"
    core.write_text("# Project Core\n**Name:** TestProject\n")
    return tmp_path


def test_read_by_tag_returns_matching_lines(memory_dir):
    reader = MemoryReader(memory_dir=str(memory_dir))
    results = reader.read_by_tag("auth")
    assert len(results) == 1
    assert "JWT secret" in results[0]


def test_read_by_tag_excludes_stale_by_default(memory_dir):
    reader = MemoryReader(memory_dir=str(memory_dir))
    results = reader.read_by_tag("auth")
    assert not any("[stale]" in r for r in results)


def test_read_by_tag_includes_stale_when_requested(memory_dir):
    reader = MemoryReader(memory_dir=str(memory_dir))
    results = reader.read_by_tag("auth", include_stale=True)
    assert len(results) == 2


def test_read_by_tag_returns_empty_for_unknown_tag(memory_dir):
    reader = MemoryReader(memory_dir=str(memory_dir))
    assert reader.read_by_tag("nonexistent") == []


def test_read_by_tag_returns_empty_when_facts_missing(tmp_path):
    reader = MemoryReader(memory_dir=str(tmp_path))
    assert reader.read_by_tag("auth") == []


def test_read_file_returns_content(memory_dir):
    reader = MemoryReader(memory_dir=str(memory_dir))
    content = reader.read_file("core")
    assert "TestProject" in content


def test_read_file_raises_for_unknown_name(memory_dir):
    reader = MemoryReader(memory_dir=str(memory_dir))
    with pytest.raises(FileNotFoundError, match="Unknown memory file"):
        reader.read_file("unknown")


def test_read_file_raises_when_file_missing(tmp_path):
    reader = MemoryReader(memory_dir=str(tmp_path))
    with pytest.raises(FileNotFoundError):
        reader.read_file("core")
