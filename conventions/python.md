# Python Conventions Overlay

Merged into `CONVENTIONS.md` by `bootstrap.sh` when stack is Python.

---

## Code Style — Python

- **Formatter:** `black` (line length 100) + `isort` (profile: black)
- **Linter:** `flake8` or `ruff`; zero warnings policy
- **Type hints:** required on all public functions and methods; run `mypy --strict` in CI
- **Docstrings:** Google style for public modules, classes, and functions; omit for private helpers
- **String formatting:** f-strings preferred; no `%` formatting

## Folder Structure — Python

```
src/
  <package_name>/
    __init__.py
    models/
    services/
    utils/
tests/
  conftest.py
  <package_name>/
    test_models.py
    test_services.py
requirements.txt          ← pinned production deps
requirements-dev.txt      ← pinned dev deps (pytest, black, mypy, etc.)
```

## Testing — Python

- **Runner:** `pytest`
- **Coverage target:** 80% minimum; enforced with `--cov-fail-under=80`
- **Test naming:** `test_<function>_<scenario>` e.g. `test_create_user_returns_id_on_success`
- **Fixtures:** in `conftest.py`; scope to smallest necessary (`function` default)
- **No mocking of internal code** — only mock external I/O (HTTP, DB, filesystem) at boundaries

## Dependencies — Python

- Pin all versions in `requirements.txt` (`package==1.2.3`)
- Separate dev dependencies in `requirements-dev.txt`
- Run `pip-audit` or `safety check` in CI for CVE scanning
