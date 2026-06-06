# Reliability Patterns — Python Overlay

Supplements `reliability-patterns.md` with Python-specific syntax checks. Apply in addition to the base checklist, never instead of it.

---

## Python-Specific Checks

Apply each item to every function or block in the diff where the condition matches.

**P1 — Bare except**
Bare `except:` or `except Exception:` without a specific exception type → flag as violation of Pattern #2.

**P2 — Silent except**
`except SomeError: pass` with no log call inside the block → flag as violations of Patterns #3 and #4.

**P3 — Exception not logged**
A caught exception block that is not already covered by P2 (i.e., not a bare `pass` block) and contains neither `logging.exception()`, `logger.error(..., exc_info=True)`, `logger.warning(...)`, nor an explicit `raise` → flag as violation of Pattern #3.

**P4 — Unchecked I/O**
A call to `open()`, `subprocess.run()`, `subprocess.check_output()`, `os.remove()`, `os.rename()`, or similar stdlib I/O functions where the call is not directly enclosed in a try/except block (or inside a function whose entire body is a try/except) and no docstring documents that the caller is expected to handle the exception → flag as violation of Pattern #4.

**P5 — Optional as error signal**
A function with `Optional[T]` or `T | None` return type that returns `None` on error, where any call site in the diff uses the result without first checking for `None` → flag as violation of Pattern #1.
