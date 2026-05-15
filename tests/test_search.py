import pytest
from pathlib import Path
from tools.search import MemorySearch


@pytest.fixture
def memory_dir(tmp_path):
    facts = tmp_path / "facts.md"
    facts.write_text(
        "[auth] JWT secret rotates every 24h\n"
        "[database] PostgreSQL 15, schema in /db/schema.sql\n"
        "[api] All responses wrapped in {data, error, meta}\n"
    )
    core = tmp_path / "core.md"
    core.write_text("**Name:** TestProject\n**Stack:** Node.js + PostgreSQL\n")
    return tmp_path


def test_exact_search_finds_match(memory_dir):
    searcher = MemorySearch(memory_dir=str(memory_dir))
    results = searcher.search("JWT")
    assert len(results) == 1
    assert "JWT" in results[0]["text"]


def test_exact_search_is_case_insensitive(memory_dir):
    searcher = MemorySearch(memory_dir=str(memory_dir))
    results = searcher.search("jwt")
    assert len(results) == 1


def test_exact_search_returns_empty_for_no_match(memory_dir):
    searcher = MemorySearch(memory_dir=str(memory_dir))
    results = searcher.search("nonexistent_xyz")
    assert results == []


def test_exact_search_result_includes_file_and_line(memory_dir):
    searcher = MemorySearch(memory_dir=str(memory_dir))
    results = searcher.search("PostgreSQL")
    assert all("file" in r and "line" in r and "text" in r for r in results)


def test_exact_search_scoped_to_file(memory_dir):
    searcher = MemorySearch(memory_dir=str(memory_dir))
    results = searcher.search("PostgreSQL", files=["facts"])
    assert all(r["file"] == "facts.md" for r in results)


def test_fuzzy_search_finds_approximate_match(memory_dir):
    searcher = MemorySearch(memory_dir=str(memory_dir))
    results = searcher.search("Postgre", fuzzy=True)
    assert len(results) > 0


def test_fuzzy_search_results_sorted_by_score(memory_dir):
    searcher = MemorySearch(memory_dir=str(memory_dir))
    results = searcher.search("JWT", fuzzy=True)
    scores = [r["score"] for r in results]
    assert scores == sorted(scores, reverse=True)


def test_fuzzy_search_includes_score(memory_dir):
    searcher = MemorySearch(memory_dir=str(memory_dir))
    results = searcher.search("JWT", fuzzy=True)
    assert all("score" in r for r in results)


def test_search_across_multiple_files(memory_dir):
    searcher = MemorySearch(memory_dir=str(memory_dir))
    results = searcher.search("TestProject")
    assert any(r["file"] == "core.md" for r in results)


def test_search_skips_empty_lines(memory_dir):
    facts = memory_dir / "facts.md"
    facts.write_text("\n\n[auth] JWT\n\n")
    searcher = MemorySearch(memory_dir=str(memory_dir))
    results = searcher.search("JWT")
    assert len(results) == 1
