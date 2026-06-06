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

**Pass:** A specific exception type is caught. The retry behaviour is explicit either in code or in a comment.

**Violation:** A bare catch-all (`catch Exception`, `except:`, `catch (Throwable t)`) is used with no transient/permanent distinction. Callers and operators cannot determine whether retrying is safe.

---

## 3 — Log Before Handle

**Scope:** Any caught exception that is not immediately re-raised.

**Check:** Is the error logged at WARN or above before the handler continues execution?

**Pass:** A log call at WARN or ERROR level appears before any recovery logic inside the catch block.

**Violation:** The exception is swallowed, converted to a return value, or silently ignored with no log entry. The failure disappears from all observability tooling.

---

## 4 — Observable Failure

**Scope:** Any error path — caught exception, early return on error condition, failed I/O, or nil/null check that leads to an error return.

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

**Violation:** Any of: unbounded retry loop; retrying on permanent errors (e.g., `ValueError`, `IllegalArgumentException`); silent retries with no log per attempt.
