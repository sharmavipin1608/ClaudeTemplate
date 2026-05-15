import pytest
from pathlib import Path
from tools.memory_write import MemoryWriter


@pytest.fixture
def memory_dir(tmp_path):
    return tmp_path


def test_append_fact_creates_facts_file(memory_dir):
    writer = MemoryWriter(memory_dir=str(memory_dir))
    writer.append_fact("auth", "JWT expires in 1h")
    facts = (memory_dir / "facts.md").read_text()
    assert "[auth] JWT expires in 1h" in facts


def test_append_fact_includes_date(memory_dir):
    writer = MemoryWriter(memory_dir=str(memory_dir))
    writer.append_fact("auth", "JWT expires in 1h")
    facts = (memory_dir / "facts.md").read_text()
    import re
    assert re.search(r"\d{4}-\d{2}-\d{2}", facts)


def test_append_fact_appends_multiple(memory_dir):
    writer = MemoryWriter(memory_dir=str(memory_dir))
    writer.append_fact("auth", "first fact")
    writer.append_fact("db", "second fact")
    facts = (memory_dir / "facts.md").read_text()
    assert "first fact" in facts
    assert "second fact" in facts


def test_mark_stale_prefixes_matching_line(memory_dir):
    facts = memory_dir / "facts.md"
    facts.write_text("[auth] JWT secret rotates every 24h\n[db] PostgreSQL 15\n")
    writer = MemoryWriter(memory_dir=str(memory_dir))
    writer.mark_stale("JWT secret")
    lines = facts.read_text().splitlines()
    assert lines[0].startswith("[stale]")
    assert not lines[1].startswith("[stale]")


def test_mark_stale_does_not_double_prefix(memory_dir):
    facts = memory_dir / "facts.md"
    facts.write_text("[stale][auth] already stale\n")
    writer = MemoryWriter(memory_dir=str(memory_dir))
    writer.mark_stale("already stale")
    content = facts.read_text()
    assert content.count("[stale]") == 1


def test_mark_stale_is_noop_when_facts_missing(tmp_path):
    writer = MemoryWriter(memory_dir=str(tmp_path))
    writer.mark_stale("anything")  # should not raise


def test_write_checkpoint_creates_file(memory_dir):
    writer = MemoryWriter(memory_dir=str(memory_dir))
    writer.write_checkpoint("session state here")
    content = (memory_dir / "session_checkpoint.md").read_text()
    assert content == "session state here"


def test_write_checkpoint_overwrites(memory_dir):
    writer = MemoryWriter(memory_dir=str(memory_dir))
    writer.write_checkpoint("first")
    writer.write_checkpoint("second")
    content = (memory_dir / "session_checkpoint.md").read_text()
    assert content == "second"


def test_append_episodic_creates_dated_file(memory_dir):
    from datetime import date
    writer = MemoryWriter(memory_dir=str(memory_dir))
    writer.append_episodic("task completed")
    today = str(date.today())
    episodic_file = memory_dir / "episodic" / f"{today}.md"
    assert episodic_file.exists()
    assert "task completed" in episodic_file.read_text()


def test_append_episodic_appends_multiple(memory_dir):
    writer = MemoryWriter(memory_dir=str(memory_dir))
    writer.append_episodic("first entry")
    writer.append_episodic("second entry")
    from datetime import date
    content = (memory_dir / "episodic" / f"{date.today()}.md").read_text()
    assert "first entry" in content
    assert "second entry" in content
