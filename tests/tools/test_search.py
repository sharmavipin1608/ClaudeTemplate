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
