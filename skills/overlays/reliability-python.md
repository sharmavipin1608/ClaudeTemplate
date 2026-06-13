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

**P6 — Module-level client singleton**
A module-level statement that constructs a stateful network or SDK client — for example `client = anthropic.Anthropic()`, `openai_client = OpenAI()`, `httpx_client = httpx.Client()`, `session = requests.Session()`, `db = psycopg2.connect(...)`, or `redis_client = redis.Redis(...)` evaluated at import time — binds the configuration captured at first import for the life of the process. It also forces network or socket setup during test collection. Flag as a violation of Pattern #6 (Startup Config Validation). The construction must move into a factory function, lifecycle hook, or dependency-injection container; module-level constants that hold only credentials read from env are acceptable, instantiated clients are not.

**P7 — Compatible-release pinning**
Any new line added to `requirements.txt`, `setup.cfg`, `pyproject.toml` (`[project.dependencies]` / `[tool.poetry.dependencies]`), or `Pipfile` that pins a third-party package without a compatible-release operator. Required forms: `package~=1.2.3` (preferred), `package==1.2.3`, or an explicit range with both lower and upper bounds (`package>=1.2,<2.0`). Unbounded entries (`package`, `package>=1.2`, `package*`) are violations — a downstream minor release can break the build without notice. The Reviewer must request a `~=` pin or an explicit upper bound before approving.

**P8 — Sanitized exception messages on network errors**
Any logging call — `logger.error(...)`, `logger.warning(...)`, `logger.exception(...)`, `print(...)`, or string-formatted message — inside a `except` block whose caught type is a network/SDK error (`httpx.HTTPError`, `requests.RequestException`, `openai.APIError`, `anthropic.APIError`, `urllib.error.URLError`, `socket.error`, `ConnectionError`, `TimeoutError`, or any subclass) and which logs `str(e)`, `repr(e)`, `e.args`, `e.response.text`, or interpolates the exception into the message format with no redaction. Provider error messages routinely echo back the request URL with query-string tokens, the `Authorization` header, or the raw request body — logging them verbatim leaks secrets. Flag as a violation; require either a fixed message naming only the operation ("upstream call failed: GET /v1/models") plus exception *type*, or a redaction helper applied to the exception string.
