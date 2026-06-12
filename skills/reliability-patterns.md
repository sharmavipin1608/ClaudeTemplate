## Role Profile

**Agent:** Reviewer
**Your input contract:** Code diff, task entry (description + acceptance criteria), `CONVENTIONS.md`, this skill file (always), optional stack overlay (`reliability-python.md` or `reliability-java.md`), optional domain skill (`api-design.md` for HTTP projects)
**Read list (in order):**
1. This skill file
2. Stack overlay (if provided by orchestrator)
3. Domain skill (if provided by orchestrator)
4. `CONVENTIONS.md`
**Your output contract:** Single JSON envelope with `verdict: "PASS"` or `verdict: "FIX_REQUIRED"`; on PASS includes `lens_results` array; on FIX_REQUIRED includes `required_changes` with file:line references and lens citations; `next_agent: "tester"` on PASS, `next_agent: "coder"` on FIX_REQUIRED
**Gates owned:** none (FIX_REQUIRED returns to coder but does not halt the pipeline permanently; only two FIX_REQUIRED in a row marks task blocked)

---

# Reliability Patterns

Language-agnostic scoped checklist for the Reviewer agent. Apply each item only when its scope condition is met — do not apply all items to all code.

---

## 1 — Error State Distinguishability

**Scope:** Any function with a non-void return value.

**Check:** Can the caller distinguish success from failure from the return value alone, without reading the implementation?

**Pass:** Success and failure return structurally different values — different types, a distinct sentinel the caller can check, or a raised exception on failure.

**Violation:** The same value (`{}`, `None`, `0`, `""`, `false`) is returned for both a successful result and a caught error. The caller has no way to know the call failed.

---

## 2 — Exception Classification

**Scope:** Any catch / except / rescue / recover block.

**Check:** Is the caught exception type specific? Is the exception classified — or documented — as transient (safe to retry) or permanent (do not retry)?

**Pass:** A specific exception type is caught. If the call site retries on this exception, whether it is transient or permanent is documented in code or a comment. If no retry is performed at this site, transient/permanent classification is not required.

**Violation:** A bare catch-all (`catch Exception`, `except:`, `catch (Throwable t)`) is used with no transient/permanent distinction. Callers and operators cannot determine whether retrying is safe.

---

## 3 — Log Before Handle

**Scope:** Any caught exception that is not immediately re-raised.

**Check:** Is the error logged at WARN or above before the handler continues execution?

**Pass:** A log call at WARN or ERROR level appears before any recovery logic inside the catch block.

**Violation:** The exception is swallowed, converted to a return value, or silently ignored with no log entry. The failure disappears from all observability tooling.

---

## 4 — Observable Failure

**Scope:** Any error path — early return on error condition, failed I/O, or nil/null check that leads to an error return. For caught exceptions that are not re-raised, Section 3 already covers the log requirement — do not also flag this section for a missing log on the same caught exception. Only apply Section 4 to caught exceptions if Section 3 is not triggered (i.e., the exception is re-raised) but some other observable signal is still absent.

**Check:** Is there at least one observable signal on this path — a log entry at WARN/ERROR, a metric increment, or a structurally distinct return value — that an operator can detect without reading source code?

**Pass:** At least one signal is present per distinct error path.

**Violation:** The call completes with no externally detectable difference from success. Silent failure: no log, no metric, no distinct return.

---

## 5 — Retry Discipline

**Scope:** Only code that performs retries — explicit retry loops, backoff helpers, retry decorators, or retry annotations.

**Check:** All three must hold:
1. The retry count is bounded by a constant or configuration value enforced in this code
2. Retries apply only to errors classified as transient
3. Each retry attempt is logged at INFO or WARN with attempt number and error

**Pass:** All three conditions are met.

**Violation:** Any of: unbounded retry loop; retrying on permanent errors (e.g., validation errors, illegal argument errors that will never succeed on retry); silent retries with no log per attempt.

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
