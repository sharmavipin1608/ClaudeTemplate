# Template Skill & Contract Fixes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix 17 confirmed template bugs — gaps in skill files, contracts, classifier rules, and bootstrap cleanup — discovered during a live end-to-end pipeline run on ResearchAgent.

**Architecture:** All changes are in skills/, contracts/, hooks/, and bootstrap.sh. No new files except additions to existing skill files. Changes are additive — no existing rules are removed, only extended.

**Tech Stack:** Bash, Python 3, JSON, Markdown

---

## Bug-to-Task Map

| Bug IDs | Symptom | Root cause | Fix task |
|---|---|---|---|
| #1, #2, #8, #13, #18 | Tester returned PASS with vacuous mocked tests | `contracts/tester.json` does not require any payload fields | Task 1 (P0) |
| #1, #2, #5, #21 | All 6 ResearchAgent tasks fast-tracked; Reviewer never ran on risky code | Classifier did not catch SDK imports, network I/O blocks, retry-keyword descriptions | Task 2 (P1) |
| #4, #7, #12, #14 | Missing startup config validation, unchecked external API response shape, no retry on flaky external I/O | `reliability-patterns.md` lacks three rules | Task 3 (P2) |
| #9, #19, #20 | Module-level client singletons, unpinned dependencies, raw exception messages in logs | `overlays/reliability-python.md` lacks three rules | Task 4 (P3) |
| #3, #10 | Declared inputs never read; import-time side effects executed during test collection | `coding-patterns.md` lacks two rules | Task 4 (P4) |
| #21 | Coder silently deviated from the approved spec; nothing forced disclosure | `contracts/coder.json` lacks `spec_deviations` payload field | Task 5 (P6) |
| #13, #20 | User-supplied filename without length cap; exception text with secrets logged verbatim | `security-rules.md` lacks two checklist items | Task 5 (P7) |
| #17 | `.env.telegram.example` and other template files leaked into bootstrapped project | `bootstrap.sh` Step 6 does not delete template artifacts at repo root | Task 6 (P5) |

---

## Task 1 — P0: Tester contract enforces non-vacuous test evidence

**Files touched:**
- `contracts/tester.json`
- `agents/tester.md`
- `hooks/validate_output.sh` (verification only — already supports `required_payload_fields`)

**Why:** The current Tester contract only validates that `verdict` is `PASS|FAIL`. A Tester that writes one assert-True test, mocks every external boundary, or returns no coverage data still passes contract validation. Fix: require structured evidence in the payload so the orchestrator (and downstream auditors) can see *what* was actually tested. Validation logic in `validate_output.sh` already enforces `required_payload_fields` (see lines 70-78), so this task is contract + agent docs only.

### Subtasks

- [ ] **1a.** Replace `contracts/tester.json` with the version below.

  **Full file content (overwrite):**
  ```json
  {
    "agent": "tester",
    "required_fields": [
      "task_id",
      "agent",
      "verdict",
      "payload",
      "next_agent"
    ],
    "valid_verdicts": [
      "PASS",
      "FAIL"
    ],
    "reason_required_on": [
      "FAIL"
    ],
    "required_payload_fields": [
      "test_counts",
      "acceptance_criteria_covered",
      "edge_cases_covered"
    ]
  }
  ```

- [ ] **1b.** Update `agents/tester.md` so the example envelopes match the new contract. Replace the PASS and FAIL example blocks with the versions below.

  **Replace the PASS block (currently around lines 36-50) with:**
  ````markdown
  **On PASS:**
  > Do NOT include a `timestamp` field — `validate_output.sh` injects the real wall-clock timestamp on validation. Agent-supplied timestamps were always fabricated placeholders.
  ```json
  {
    "task_id": "<task_id>",
    "agent": "tester",
    "verdict": "PASS",
    "payload": {
      "test_counts": {
        "unit": 2,
        "integration": 1,
        "edge": 1,
        "total": 4
      },
      "acceptance_criteria_covered": [
        {"criterion": "User can fetch by id", "test": "test_fetch_by_id_returns_user"},
        {"criterion": "Missing id returns 404", "test": "test_fetch_by_unknown_id_returns_404"}
      ],
      "edge_cases_covered": [
        "empty input",
        "boundary value (max length)",
        "external API 5xx response",
        "external API timeout"
      ]
    },
    "next_agent": "security",
    "reason": null
  }
  ```
  ````

  **Replace the FAIL block (currently around lines 52-69) with:**
  ````markdown
  **On FAIL:**
  ```json
  {
    "task_id": "<task_id>",
    "agent": "tester",
    "verdict": "FAIL",
    "payload": {
      "test_counts": {
        "unit": 3,
        "integration": 1,
        "edge": 1,
        "total": 5,
        "passed": 3
      },
      "acceptance_criteria_covered": [
        {"criterion": "User can fetch by id", "test": "test_fetch_by_id_returns_user"}
      ],
      "edge_cases_covered": [
        "empty input"
      ],
      "failures": [
        {"test": "test_login_with_expired_token", "reason": "AttributeError: 'NoneType' has no attribute 'token'"}
      ],
      "attempted_fix": "<one sentence describing what fix was tried>"
    },
    "next_agent": "coder",
    "reason": "<N tests failed after one fix attempt>"
  }
  ```
  ````

- [ ] **1c.** Add a Rule 8 to `agents/tester.md` immediately after Rule 7 ("Use the task's `Acceptance Criteria` as your test specification..."). Use this exact text:

  ```markdown
  8. Your `payload` must carry concrete evidence: `test_counts` (by type + total), `acceptance_criteria_covered` (one entry per acceptance criterion in the task, mapping criterion text → test name), and `edge_cases_covered` (free-text list of boundary/error scenarios exercised). Empty arrays mean you tested nothing — the orchestrator will reject the envelope.
  ```

- [ ] **1d.** Run the verification commands below from the ClaudeTemplate root.

  ```bash
  # Confirm JSON is well-formed and carries the new payload fields.
  python3 -c "import json; c=json.load(open('contracts/tester.json')); assert c['required_payload_fields']==['test_counts','acceptance_criteria_covered','edge_cases_covered'], c"

  # Confirm validate_output.sh already enforces required_payload_fields (line 70 area).
  grep -n "required_payload_fields" hooks/validate_output.sh

  # Negative test: a vacuous envelope must be rejected.
  printf '%s' '{"task_id":"T1","agent":"tester","verdict":"PASS","payload":{},"next_agent":"security","reason":null}' \
    | bash hooks/validate_output.sh tester ; echo "exit=$?"
  # Expected: exit=1, stderr lists three missing payload fields.

  # Positive test: a full envelope passes.
  printf '%s' '{"task_id":"T1","agent":"tester","verdict":"PASS","payload":{"test_counts":{"total":1},"acceptance_criteria_covered":[],"edge_cases_covered":[]},"next_agent":"security","reason":null}' \
    | bash hooks/validate_output.sh tester ; echo "exit=$?"
  # Expected: exit=0, prints "OK: tester verdict=PASS".

  # Confirm tester.md examples now reference the new payload keys.
  grep -n "acceptance_criteria_covered" agents/tester.md
  grep -n "edge_cases_covered" agents/tester.md
  ```

- [ ] **1e.** Commit.

  ```
  fix(contracts): tester payload must carry test_counts, acceptance_criteria_covered, edge_cases_covered (P0)
  ```

---

## Task 2 — P1: Classifier forces full pipeline on SDK imports, network I/O blocks, retry-keyword descriptions

**Files touched:**
- `hooks/classify_task.sh`

**Why:** During the ResearchAgent run, every task fell through the classifier as `AMBIGUOUS` and was fast-tracked. Tasks that imported external SDKs (`anthropic`, `httpx`, `slack-sdk`), opened sockets, or whose descriptions said "retry on 429" never saw the Reviewer. We add three new hard rules — SDK import detection, network-I/O catch detection, and a description-keyword scan — that escalate to `FORCE_FULL` before the AMBIGUOUS fallthrough.

### Subtasks

- [ ] **2a.** Open `hooks/classify_task.sh`. Insert the block below **between** the "Sensitive keywords in task description" block (currently ending around line 139) and the AMBIGUOUS fallthrough (currently starting at line 141 with `# No hard rule fired`). The insertion point is immediately after this existing line:

  ```bash
  echo "$TASK_DESC" | grep -qiE "pii|gdpr|privacy|user.?data|email.?template|base\s+class" && \
      force_full "sensitive domain keyword in task description"
  ```

  **Insert exactly this block:**

  ```bash
  # ── Reliability keywords in task description ──────────────────────────
  # Tasks that talk about recurring/retrying behavior, backoff, polling,
  # or scheduling carry latent reliability traps the Reviewer must inspect.
  echo "$TASK_DESC" | grep -qiE "\b(recur|recurring|iterate|iteration|retry|retries|backoff|exponential|poll|polling|schedul(e|ing)|cron|reconnect|resume|circuit.?breaker|rate.?limit|throttl)" && \
      force_full "reliability keyword in task description"

  # ── External SDK / network-client imports in the diff ─────────────────
  # New import lines that pull in HTTP, SDK, or socket libraries imply
  # external I/O. External I/O without Reviewer scrutiny is how retry,
  # timeout, and error-classification bugs reach production.
  if git rev-parse HEAD &>/dev/null; then
      SDK_DIFF=$(git diff HEAD 2>/dev/null; git diff --cached HEAD 2>/dev/null)
  else
      SDK_DIFF=$(git diff 2>/dev/null; git diff --cached 2>/dev/null)
  fi
  if [ -n "$SDK_DIFF" ]; then
      # Look only at ADDED lines (start with '+' but not '+++').
      ADDED_LINES=$(printf '%s\n' "$SDK_DIFF" | grep -E "^\+[^+]" || true)
      # Python: import / from X import
      echo "$ADDED_LINES" | grep -qE "^\+\s*(import|from)\s+(anthropic|openai|httpx|requests|aiohttp|urllib|urllib3|socket|websockets|websocket|slack_sdk|slack_bolt|google\.|boto3|botocore|stripe|telegram|telethon|smtplib|email\.smtp|paramiko|kafka|redis|pymongo|psycopg|psycopg2|sqlalchemy\.engine|grpc|grpcio)" \
          && force_full "external SDK / network client imported in diff"
      # JS/TS: import ... from 'pkg' or require('pkg')
      echo "$ADDED_LINES" | grep -qE "^\+.*(from\s+['\"]|require\(['\"])(@anthropic-ai|openai|axios|node-fetch|undici|got|ws|@slack/|@google-cloud/|aws-sdk|@aws-sdk/|stripe|telegraf|nodemailer|mongodb|pg|mysql2|ioredis|redis|grpc|@grpc/)" \
          && force_full "external SDK / network client imported in diff"
      # Network-I/O try/except (Python) — catching network errors implies network calls.
      echo "$ADDED_LINES" | grep -qE "^\+\s*except\s+(\w+\.)*(Timeout|TimeoutError|ConnectionError|ConnectionResetError|ConnectionRefusedError|HTTPError|RequestException|ClientError|APIError|RateLimitError|APIConnectionError|APIStatusError|ServerError)" \
          && force_full "network I/O exception caught in diff"
      # Network-I/O try/catch (JS/TS) — catching with HTTP-ish error names.
      echo "$ADDED_LINES" | grep -qE "^\+.*catch\s*\(\s*\w+\s*(:\s*(FetchError|AxiosError|HTTPError|TimeoutError|NetworkError))?\s*\)" \
          | grep -qE "fetch|axios|http" \
          && force_full "network I/O catch in diff"
  fi
  ```

- [ ] **2b.** Update the stale shell comment that wrongly describes the classifier as only writing `FORCE_FULL` or `AMBIGUOUS` "from task complexity". The header comment at lines 1-4 already says it writes `FORCE_FULL` or `AMBIGUOUS` — leave as-is; no edit needed unless lint flags drift. (Verification step 2c confirms.)

- [ ] **2c.** Run the verification commands below.

  ```bash
  # 1. Syntax check the modified script.
  bash -n hooks/classify_task.sh && echo "syntax OK"

  # 2. Confirm the three new rules are present.
  grep -n "reliability keyword in task description"      hooks/classify_task.sh
  grep -n "external SDK / network client imported"       hooks/classify_task.sh
  grep -n "network I/O exception caught"                 hooks/classify_task.sh

  # 3. Sanity-check the SDK regex with a manual sample.
  printf '+import anthropic\n+from openai import OpenAI\n+import httpx\n' \
    | grep -E "^\+\s*(import|from)\s+(anthropic|openai|httpx|requests|aiohttp|urllib|urllib3|socket|websockets|websocket|slack_sdk|slack_bolt|google\.|boto3|botocore|stripe|telegram|telethon|smtplib|email\.smtp|paramiko|kafka|redis|pymongo|psycopg|psycopg2|sqlalchemy\.engine|grpc|grpcio)"
  # Expected: three lines printed.

  # 4. Sanity-check the keyword regex.
  echo "implement exponential backoff retry on 429"      | grep -qiE "\b(recur|recurring|iterate|iteration|retry|retries|backoff|exponential|poll|polling|schedul(e|ing)|cron|reconnect|resume|circuit.?breaker|rate.?limit|throttl)" && echo "match: retry keyword"
  echo "add cron schedule for nightly digest"             | grep -qiE "\b(recur|recurring|iterate|iteration|retry|retries|backoff|exponential|poll|polling|schedul(e|ing)|cron|reconnect|resume|circuit.?breaker|rate.?limit|throttl)" && echo "match: schedule keyword"
  echo "rename a CSS class"                               | grep -qiE "\b(recur|recurring|iterate|iteration|retry|retries|backoff|exponential|poll|polling|schedul(e|ing)|cron|reconnect|resume|circuit.?breaker|rate.?limit|throttl)" || echo "no false positive on CSS rename"
  ```

- [ ] **2d.** Commit.

  ```
  fix(classifier): FORCE_FULL on SDK imports, network-I/O catches, and retry/poll/backoff keywords (P1)
  ```

---

## Task 3 — P2: reliability-patterns.md adds three rules (startup config, response shape, mandatory retry)

**File touched:**
- `skills/reliability-patterns.md`

**Why:** During the ResearchAgent run the Reviewer (when it ran at all) had no rule covering: (a) services that boot up without verifying required config values, (b) external API responses consumed without checking the response shape, (c) external I/O calls with no retry around them. We add three new sections to the Reviewer checklist.

### Subtasks

- [ ] **3a.** Open `skills/reliability-patterns.md`. Append the three sections below to the **end of the file** (after the existing Section 5 — Retry Discipline, which ends at line 80).

  **Append exactly:**

  ```markdown

  ---

  ## 6 — Startup Config Validation

  **Scope:** Any module that reads configuration at import time or in an application's main entry point — environment variables, config files, secret manager calls, CLI arguments — that the application requires to function.

  **Check:** Are all required configuration values validated at startup, before the application begins serving traffic or processing work? A required value is one whose absence would cause a downstream call to fail.

  **Pass:** A startup routine (entry point, factory function, lifecycle hook, or module-level `__init__` for the config module) reads each required value and either fails fast with a clear error naming the missing key, or substitutes a documented default. The failure path exits with non-zero status and logs at ERROR.

  **Violation:** A required environment variable or config key is referenced only at the call site (e.g., `os.environ["API_KEY"]` inside a request handler). The first request after a misconfigured deploy raises `KeyError` instead of the process refusing to start. Operators discover the misconfiguration through a user-facing 500 rather than a boot failure.

  ---

  ## 7 — External Response Structural Validation

  **Scope:** Any call to an external API, third-party SDK, or service the calling process does not own, whose return value is then read field-by-field.

  **Check:** Before the code accesses fields on the response, is the response structurally validated — type checked, schema validated, or guarded by explicit `.get()` calls with documented defaults — so that a missing field, wrong-typed field, or unexpected envelope produces a classified error rather than an `AttributeError` / `TypeError` / `KeyError`?

  **Pass:** One of the following is true on every external-response read path:
  1. The response is parsed through a typed model (Pydantic, dataclass with validation, JSON schema check, protobuf message, etc.) that raises a domain-specific error on mismatch.
  2. Every field access uses `.get()` (or equivalent) with an explicit default, and the absence path is handled with a log + classified return.
  3. The response handler wraps field access in a try/except for the relevant attribute/key/type error and converts it to a domain error before returning.

  **Violation:** Code reads `response["data"]["items"][0]["id"]` (or any nested dotted/indexed access) directly off an external response with no structural check. A vendor changing their envelope from `{"data": {...}}` to `{"result": {...}}` produces an opaque `KeyError` at the call site instead of a logged, classified failure at the boundary.

  ---

  ## 8 — Mandatory Retry on External I/O

  **Scope:** Any direct call to an external network endpoint, third-party SDK, or external process (HTTP, gRPC, database driver against a remote DB, message broker publish, blob storage upload/download). Does **not** apply to local filesystem I/O, in-process function calls, or unit-test stubs.

  **Check:** Is the call wrapped — directly or through a higher-level helper — in a bounded retry with backoff? The retry must satisfy Section 5 — Retry Discipline (bounded count, transient-only, logged per attempt).

  **Pass:** The call site, the helper it delegates to, or a documented client-level policy (e.g., SDK `max_retries` configuration explicitly set in code) provides bounded retry with backoff on transient failures. A code comment or docstring at the call site names where the retry lives if it is not at the call site itself.

  **Violation:** A one-shot external call with no retry, no surrounding policy, and no comment pointing to where the retry would live. The first transient hiccup — a `ConnectionResetError`, an HTTP 503, a gRPC `UNAVAILABLE` — surfaces as a user-visible failure. This is *not* satisfied by catching the exception and re-raising; the rule requires a retry attempt, not just observability.
  ```

- [ ] **3b.** Verify.

  ```bash
  # Confirm three new section headers are present.
  grep -n "^## 6 — Startup Config Validation"             skills/reliability-patterns.md
  grep -n "^## 7 — External Response Structural Validation" skills/reliability-patterns.md
  grep -n "^## 8 — Mandatory Retry on External I/O"       skills/reliability-patterns.md

  # Each section must have Scope / Check / Pass / Violation sub-headers.
  awk '/^## [678] —/{flag=1} /^---$/{flag=0} flag' skills/reliability-patterns.md \
    | grep -c "^\*\*Scope:\*\*"
  # Expected: 3
  awk '/^## [678] —/{flag=1} /^---$/{flag=0} flag' skills/reliability-patterns.md \
    | grep -c "^\*\*Violation:\*\*"
  # Expected: 3
  ```

- [ ] **3c.** Commit.

  ```
  feat(skills): reliability-patterns adds startup config, response shape, and mandatory retry rules (P2)
  ```

---

## Task 4 — P3 + P4: Python overlay adds 3 rules; coding-patterns adds 2 rules

**Files touched:**
- `skills/overlays/reliability-python.md`
- `skills/coding-patterns.md`

**Why (P3):** The Python overlay missed three patterns that bit ResearchAgent: module-level client singletons that bind a stale API key at import time, unpinned dependencies that break reproducibility, and raw exception messages from network calls that leaked secrets into logs.
**Why (P4):** `coding-patterns.md` had no rule against declared-but-unused inputs (Coder added a `timeout_ms` parameter and never read it) and no rule against import-time side effects (a module that called `httpx.get()` at import time, breaking test collection).

### Subtasks

- [ ] **4a.** Append to `skills/overlays/reliability-python.md` after the existing P5 block (line 24).

  **Append exactly:**

  ```markdown

  **P6 — Module-level client singleton**
  A module-level statement that constructs a stateful network or SDK client — for example `client = anthropic.Anthropic()`, `openai_client = OpenAI()`, `httpx_client = httpx.Client()`, `session = requests.Session()`, `db = psycopg2.connect(...)`, or `redis_client = redis.Redis(...)` evaluated at import time — binds the configuration captured at first import for the life of the process. It also forces network or socket setup during test collection. Flag as a violation of Pattern #6 (Startup Config Validation). The construction must move into a factory function, lifecycle hook, or dependency-injection container; module-level constants that hold only credentials read from env are acceptable, instantiated clients are not.

  **P7 — Compatible-release pinning**
  Any new line added to `requirements.txt`, `setup.cfg`, `pyproject.toml` (`[project.dependencies]` / `[tool.poetry.dependencies]`), or `Pipfile` that pins a third-party package without a compatible-release operator. Required forms: `package~=1.2.3` (preferred), `package==1.2.3`, or an explicit range with both lower and upper bounds (`package>=1.2,<2.0`). Unbounded entries (`package`, `package>=1.2`, `package*`) are violations — a downstream minor release can break the build without notice. The Reviewer must request a `~=` pin or an explicit upper bound before approving.

  **P8 — Sanitized exception messages on network errors**
  Any logging call — `logger.error(...)`, `logger.warning(...)`, `logger.exception(...)`, `print(...)`, or string-formatted message — inside a `except` block whose caught type is a network/SDK error (`httpx.HTTPError`, `requests.RequestException`, `openai.APIError`, `anthropic.APIError`, `urllib.error.URLError`, `socket.error`, `ConnectionError`, `TimeoutError`, or any subclass) and which logs `str(e)`, `repr(e)`, `e.args`, `e.response.text`, or interpolates the exception into the message format with no redaction. Provider error messages routinely echo back the request URL with query-string tokens, the `Authorization` header, or the raw request body — logging them verbatim leaks secrets. Flag as a violation; require either a fixed message naming only the operation ("upstream call failed: GET /v1/models") plus exception *type*, or a redaction helper applied to the exception string.
  ```

- [ ] **4b.** Append to `skills/coding-patterns.md` after the YAGNI section (line 46).

  **Append exactly:**

  ```markdown

  ## Input Liveness
  - Every declared input — function parameter, constructor argument, CLI flag, config key, environment variable — must be **read on at least one reachable code path** in the same change. If you add `timeout_ms` to a signature, some branch of the function must actually use it. Dead inputs lie to the caller about what the function does; they also bypass type checkers because the parameter is technically referenced in the signature.
  - When a declared input is intentionally reserved for a future change, mark it with an explicit `_` prefix (`_timeout_ms`) or a `# reserved: <ticket>` comment so the next reader knows it is wired but inert.
  - The Reviewer rejects a diff that adds an input read on zero branches.

  ## No Import-Time Side Effects in Library Modules
  - A library module — anything imported by another module rather than executed as `__main__` — must perform no I/O, no network calls, no subprocess spawning, no global state mutation, and no logger configuration at import time.
  - Acceptable at import time: function/class definitions, plain constant assignments from literals or `os.environ.get(...)` with a default, type aliases, and decorator application that does not itself perform I/O.
  - Not acceptable at import time: opening files, reading config files, building HTTP/SDK/database clients, calling `logging.basicConfig`, registering signal handlers, mutating shared state on another module, or any code path that can raise on a misconfiguration.
  - The pragmatic test: can this module be imported inside a unit test with no network, no filesystem outside the package directory, and no environment variables set? If not, the import-time work must move into a factory function or a `main()` entry point.
  ```

- [ ] **4c.** Verify.

  ```bash
  # Python overlay rules present
  grep -n "^\*\*P6 — Module-level client singleton\*\*"          skills/overlays/reliability-python.md
  grep -n "^\*\*P7 — Compatible-release pinning\*\*"             skills/overlays/reliability-python.md
  grep -n "^\*\*P8 — Sanitized exception messages on network errors\*\*" skills/overlays/reliability-python.md

  # coding-patterns rules present
  grep -n "^## Input Liveness"                                    skills/coding-patterns.md
  grep -n "^## No Import-Time Side Effects in Library Modules"    skills/coding-patterns.md

  # Sanity: file did not lose any of the original sections.
  for h in "## Naming" "## Functions" "## Error Handling" "## Dependencies" "## YAGNI"; do
    grep -qn "^${h}$" skills/coding-patterns.md && echo "kept: ${h}"
  done
  ```

- [ ] **4d.** Commit.

  ```
  feat(skills): python overlay + coding-patterns add singleton/pinning/sanitization/liveness rules (P3+P4)
  ```

---

## Task 5 — P6 + P7: coder.json declares spec_deviations; security-rules adds two checklist items; coder.md + security.md examples updated

**Files touched:**
- `contracts/coder.json`
- `agents/coder.md`
- `skills/security-rules.md`
- `agents/security.md`

**Why (P6):** During the ResearchAgent run the Coder shipped an implementation that diverged from the approved spec — the spec said "use exponential backoff with full jitter", the Coder used fixed 1s delays — and nothing in the envelope flagged the deviation. Reviewer and Tester both passed because the deviation was invisible. Fix: add a required `spec_deviations` payload field. An empty array is a positive affirmation ("I matched the spec"), not the absence of evidence.
**Why (P7):** The Security checklist was missing two items that bit the live run: (a) a user-supplied string used as a filename with no length cap, opening up disk-fill DoS, (b) raw `str(e)` from network exceptions logged verbatim (mirrors P8 in the Python overlay but the Security agent must also catch it independently).

### Subtasks

- [ ] **5a.** Replace `contracts/coder.json` with:

  ```json
  {
    "agent": "coder",
    "required_fields": [
      "task_id",
      "agent",
      "verdict",
      "payload",
      "next_agent"
    ],
    "valid_verdicts": [
      "DONE"
    ],
    "reason_required_on": [],
    "required_payload_fields": [
      "files_changed",
      "spec_deviations"
    ]
  }
  ```

- [ ] **5b.** Update `agents/coder.md`. Replace the example envelope (currently lines 45-58) with:

  ````markdown
  > Do NOT include a `timestamp` field — `validate_output.sh` injects the real wall-clock timestamp on validation. Agent-supplied timestamps were always fabricated placeholders.
  ```json
  {
    "task_id": "<task_id from your task entry>",
    "agent": "coder",
    "verdict": "DONE",
    "payload": {
      "files_changed": ["path/to/changed_file.py"],
      "decisions": [],
      "convention_gaps": [],
      "spec_deviations": []
    },
    "next_agent": "reviewer",
    "reason": null
  }
  ```

  `verdict` is always `"DONE"`. `reason` is always `null`. `decisions`, `convention_gaps`, and `spec_deviations` follow the same rules: max 3 bullets each, only if non-obvious or non-empty; `[]` otherwise. `spec_deviations` is mandatory — an empty array is a positive affirmation that the implementation matches the approved spec; a non-empty entry must name (a) what the spec said, (b) what you built, (c) why. Silently diverging from the spec is the most common cause of "passed all gates, shipped wrong behavior."
  ````

- [ ] **5c.** Add Rule 8 to `agents/coder.md` immediately after Rule 7 (the acceptance-criteria rule):

  ```markdown
  8. Declare every deviation from the approved spec or design doc in `payload.spec_deviations`. Each entry is an object with `{"spec": "<what the spec said>", "built": "<what you built>", "why": "<reason>"}`. If you matched the spec exactly, the field is `[]` — but you must still send the empty array. The Reviewer treats a missing or omitted `spec_deviations` field as a contract violation and the orchestrator will reject the envelope.
  ```

- [ ] **5d.** Update `skills/security-rules.md`. Append two new checklist items to the end of the "Security Checklist (run on every diff)" block (currently ending at line 49). Insert the two `- [ ]` lines immediately before the closing whitespace.

  **Append exactly (preserving leading whitespace):**

  ```markdown
  - [ ] Filename length bounds: any user-supplied string used as a filename, path component, S3 key, blob name, or cache key has an explicit max-length check (typically <= 255 bytes for filesystems; document the limit at the validation site)
  - [ ] Sanitized exception logging: no `str(e)`, `repr(e)`, `e.response.text`, or `f"...{e}..."` from network/SDK/database exceptions reaches a log call — provider error payloads echo back Authorization headers, query-string tokens, and raw request bodies; log a fixed operation description plus the exception *type*, or apply a redaction helper
  ```

- [ ] **5e.** Add a corresponding short bullet under the "Input Validation" subsection in `skills/security-rules.md` so the rule is reinforced in the prose section, not only the checklist. Replace the existing `- Reject unknown fields...` line block by appending one new bullet to the Input Validation list. Insert this single line directly after the `- Server-side validation is authoritative...` line:

  ```markdown
  - Any user-supplied string that becomes a filename, path component, object-storage key, or cache key must carry an explicit byte-length cap — unbounded strings are a disk-fill / quota-exhaust DoS vector
  ```

- [ ] **5f.** Update `agents/security.md`. Append one rule (Rule 6) immediately after the existing Rule 5 ("Do not approve code that contains hardcoded secrets..."):

  ```markdown
  6. Two checklist items added 2026-06-12 are *blocking* on every diff: (a) any user-supplied string used as a filename or object-storage key must have a documented max-length check; (b) no raw exception message from a network/SDK/database call may be passed to a log call without redaction. A diff that violates either is BLOCKED.
  ```

- [ ] **5g.** Verify.

  ```bash
  # coder.json valid + has spec_deviations
  python3 -c "import json; c=json.load(open('contracts/coder.json')); assert 'spec_deviations' in c['required_payload_fields'] and 'files_changed' in c['required_payload_fields'], c"

  # coder.md example shows spec_deviations and Rule 8 added
  grep -n '"spec_deviations"'            agents/coder.md
  grep -nE "^8\. Declare every deviation" agents/coder.md

  # security-rules checklist additions
  grep -n "Filename length bounds"        skills/security-rules.md
  grep -n "Sanitized exception logging"   skills/security-rules.md

  # security.md rule 6 present
  grep -nE "^6\. Two checklist items added 2026-06-12" agents/security.md

  # Negative test: coder envelope missing spec_deviations must fail validation.
  printf '%s' '{"task_id":"T1","agent":"coder","verdict":"DONE","payload":{"files_changed":["a.py"]},"next_agent":"reviewer","reason":null}' \
    | bash hooks/validate_output.sh coder ; echo "exit=$?"
  # Expected: exit=1, stderr names "payload.spec_deviations".

  # Positive test: coder envelope with both fields passes.
  printf '%s' '{"task_id":"T1","agent":"coder","verdict":"DONE","payload":{"files_changed":["a.py"],"spec_deviations":[]},"next_agent":"reviewer","reason":null}' \
    | bash hooks/validate_output.sh coder ; echo "exit=$?"
  # Expected: exit=0.
  ```

- [ ] **5h.** Commit.

  ```
  fix(contracts+skills): coder declares spec_deviations; security gates filename length & sanitized exception logging (P6+P7)
  ```

---

## Task 6 — P5: Bootstrap cleanup removes template artifacts at repo root

**File touched:**
- `bootstrap.sh`

**Why:** When a developer bootstraps a new project from ClaudeTemplate, `.env.telegram.example` (and any future template-internal dotfiles) is currently copied through unchanged and shows up as a stray file in the new repo. The Step 6 cleanup block only removes well-known files like `README_TEMPLATE.md`, `scripts/`, and `tests/` — it does not sweep template-specific environment example files or template-only root markdown files (`ISSUES.md` is template-internal sprint tracking, not project content).

### Subtasks

- [ ] **6a.** Open `bootstrap.sh` and locate the Step 6 cleanup section. The existing block ends with the `find . -type d -name "__pycache__" ...` and `rm -f bootstrap.sh` lines at around lines 493-499. Insert the new cleanup block **immediately before** the existing `# Remove this one-shot script` comment (the line `rm -f bootstrap.sh && success "  Removed bootstrap.sh."`).

  **Insert exactly:**

  ```bash
  # Remove template-internal artifacts at repo root that have no meaning
  # in a bootstrapped project. These files exist only to support the
  # ClaudeTemplate repo's own demos, examples, and sprint tracking.
  for artifact in \
      .env.telegram.example \
      .env.example \
      ISSUES.md \
      ; do
      if [[ -e "$artifact" ]]; then
          rm -rf "$artifact" && success "  Removed template artifact: ${artifact}."
      fi
  done

  # Sweep any remaining .env.*.example files the template might add later.
  # Whitelist .env.example because some projects do ship one as a real
  # placeholder; the loop above already removes it if it is the template's.
  # Anything matching .env.*.example beyond that is template residue.
  for stray in .env.*.example; do
      [[ -e "$stray" ]] || continue
      rm -f "$stray" && success "  Removed stray env example: ${stray}."
  done
  ```

- [ ] **6b.** Verify.

  ```bash
  # Syntax check the modified script.
  bash -n bootstrap.sh && echo "syntax OK"

  # The new cleanup block must appear before the rm -f bootstrap.sh line.
  awk '/Remove template-internal artifacts at repo root/{seen=NR} /rm -f bootstrap\.sh && success/{print (seen && NR>seen ? "OK: cleanup block precedes self-delete" : "FAIL: ordering wrong"); exit}' bootstrap.sh

  # The artifact list must contain .env.telegram.example.
  grep -n "\.env\.telegram\.example" bootstrap.sh

  # The stray-sweep glob must be present.
  grep -n "for stray in \.env\.\*\.example" bootstrap.sh

  # End-to-end shape: dry-run a tmp directory with a fake artifact and a
  # tiny shell that runs only the loop above to confirm it deletes.
  tmpdir=$(mktemp -d); pushd "$tmpdir" >/dev/null
  : > .env.telegram.example
  : > .env.slack.example
  : > ISSUES.md
  for artifact in .env.telegram.example .env.example ISSUES.md; do
      [[ -e "$artifact" ]] && rm -rf "$artifact"
  done
  for stray in .env.*.example; do
      [[ -e "$stray" ]] || continue
      rm -f "$stray"
  done
  ls -la .env.* ISSUES.md 2>&1 | grep -E "No such file|cannot access" >/dev/null && echo "OK: all artifacts removed"
  popd >/dev/null && rm -rf "$tmpdir"
  ```

- [ ] **6c.** Commit.

  ```
  fix(bootstrap): cleanup step removes .env.*.example and template-only root files (P5)
  ```

---

## Self-Review

This section is the author's pre-flight check. Each box is answered, not just ticked.

- [x] **Every new section is shown in full** — Task 3 prints the complete text of Sections 6, 7, 8 of `reliability-patterns.md`; Task 4 prints the complete text of P6, P7, P8 in the Python overlay and the two new headings in `coding-patterns.md`; Task 5 prints both new checklist lines for `security-rules.md` and the new Rule 8 for `coder.md`. No "similar to above" language; no "add an X rule here" placeholders.
- [x] **All verification commands are runnable from the ClaudeTemplate root** — every snippet uses repo-relative paths (`contracts/`, `hooks/`, `skills/`, `agents/`, `bootstrap.sh`), reads from stdin where the script expects it, and is sequenced so prerequisites (file edits) precede the check.
- [x] **Every task ends with a git commit step** — Tasks 1e, 2d, 3c, 4d, 5h, 6c each include the commit message.
- [x] **No placeholders remain** — text was searched for `TBD`, `TODO`, `insert here`, `placeholder`, `XXX`, `???`; none appear in any non-illustrative block. The single placeholder-like token (`<task_id>`, `<one sentence...>`) is preserved only inside JSON example envelopes that document the contract.

---

## Execution Order Note

Tasks may be executed in any order because they touch disjoint files. The recommended order is the numbered order (1 → 6) because the P0 Tester contract fix is the highest-leverage gate and benefits every subsequent live run; the Bootstrap fix (Task 6) is the lowest-leverage and can be deferred without affecting in-flight pipelines.
