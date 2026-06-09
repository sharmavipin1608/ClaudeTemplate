# Python Stack Overlay

Appended to agent definitions by `bootstrap.sh` when stack is Python. Extends base agent rules with Python-specific commands and patterns.

---

## Coder — Python additions

- **Formatter:** run `black .` and `isort .` before committing
- **Type hints:** required on all public function signatures; use `from __future__ import annotations` for forward refs
- **Tests:** use `pytest`; test files in `tests/` mirroring `src/` structure; fixtures in `conftest.py`
- **TDD command:** `pytest tests/path/to/test_file.py::test_name -v`
- **Imports:** stdlib → third-party → local; enforced by isort profile `black`
- **Dependency pinning:** use `requirements.txt` with pinned versions (`==`) for reproducibility

## Tester — Python additions

- **Test runner:** `pytest --tb=short -v`
- **Coverage:** `pytest --cov=src --cov-report=term-missing`; fail below 80%: `--cov-fail-under=80`
- **Filesystem isolation:** use `tmp_path` pytest fixture — never use `tempfile` directly
- **HTTP testing:** use `httpx.AsyncClient` or `requests` with `responses` mock library
- **Fixtures:** prefer `conftest.py` fixtures over setUp/tearDown; scope carefully (`function` default, `session` for expensive setup)

## Security — Python additions

- Check for `subprocess.shell=True` with user-controlled input → command injection
- Check for `eval()`, `exec()`, `__import__()` with dynamic strings → code injection
- Check for SQL string formatting (f-string/%-format into queries) → SQL injection
- Check for hardcoded secrets in source (API keys, passwords, tokens)
- Check for `pickle.loads()` on untrusted input → arbitrary code execution
- Check `requirements.txt` for packages with known CVEs (flag for manual review)
