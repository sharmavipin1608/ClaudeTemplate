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
