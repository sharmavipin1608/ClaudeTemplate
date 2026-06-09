# Reviewer Reliability Patterns Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Reviewer agent iron-clad by creating language-agnostic reliability pattern checklists, stack-specific overlays for Python and Java, restructuring reviewer.md with a mandatory 5-lens sequential review process, and adding routing logic so the orchestrator passes the right skills per project type.

**Architecture:** Three new skill files (base + two overlays) define what to check. reviewer.md is rewritten to enforce a sequential lens structure. CLAUDE.md and orchestrator.md both get a routing table that tells the orchestrator which skills to load before dispatching the Reviewer. Evaluation fixtures in tests/reviewer-fixtures/ provide a manual regression suite.

**Tech Stack:** Markdown only. No code changes. Verification is grep/ls for structure and manual Reviewer agent dispatch for functional validation.

---

## File Map

| Action | File | Responsibility |
|---|---|---|
| Create | `skills/reliability-patterns.md` | Language-agnostic base checklist — 5 scoped categories |
| Create | `skills/overlays/reliability-python.md` | Python-specific syntax checks (5 rules) |
| Create | `skills/overlays/reliability-java.md` | Java-specific syntax checks (6 rules) |
| Modify | `agents/reviewer.md` | Remove hardcoded api-design.md; add 5-lens sequential structure |
| Modify | `CLAUDE.md` | Update reviewer row, update Skills table, add routing section |
| Modify | `.claude/orchestrator.md` | Same updates as CLAUDE.md but with .claude/skills/ paths |
| Create | `tests/reviewer-fixtures/fixture-1-python-multi-violation.md` | 10-violation Python fixture |
| Create | `tests/reviewer-fixtures/fixture-2-java-multi-violation.md` | 10-violation Java fixture |
| Create | `tests/reviewer-fixtures/fixture-3-http-api.md` | 9-violation Flask + api-design fixture |
| Create | `tests/reviewer-fixtures/fixture-4-false-positive-trap.md` | Well-written Python, must pass |

---

### Task 1: Create skills/reliability-patterns.md

**Files:**
- Create: `skills/reliability-patterns.md`

- [ ] **Step 1: Write the file**

```markdown
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
```

- [ ] **Step 2: Verify**

```bash
grep -c "^## [0-9]" skills/reliability-patterns.md
```
Expected output: `5`

- [ ] **Step 3: Commit**

```bash
git add skills/reliability-patterns.md
git commit -m "feat(reviewer): add reliability-patterns.md base checklist"
```

---

### Task 2: Create skills/overlays/reliability-python.md

**Files:**
- Create: `skills/overlays/reliability-python.md`

- [ ] **Step 1: Create the overlays directory and write the file**

```markdown
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
A caught exception block that contains neither `logging.exception()`, `logger.error(..., exc_info=True)`, `logger.warning(...)`, nor an explicit `raise` → flag as violation of Pattern #3.

**P4 — Unchecked I/O**
A call to `open()`, `subprocess.run()`, `subprocess.check_output()`, `os.remove()`, `os.rename()`, or similar stdlib I/O functions where the call is not wrapped in try/except and no docstring documents that the caller is expected to handle the exception → flag as violation of Pattern #4.

**P5 — Optional as error signal**
A function with `Optional[T]` or `T | None` return type that returns `None` on error, where any call site in the diff uses the result without first checking for `None` → flag as violation of Pattern #1.
```

- [ ] **Step 2: Verify**

```bash
ls skills/overlays/
```
Expected output includes: `reliability-python.md`

```bash
grep -c "^\*\*P[0-9]" skills/overlays/reliability-python.md
```
Expected output: `5`

- [ ] **Step 3: Commit**

```bash
git add skills/overlays/reliability-python.md
git commit -m "feat(reviewer): add Python reliability overlay"
```

---

### Task 3: Create skills/overlays/reliability-java.md

**Files:**
- Create: `skills/overlays/reliability-java.md`

- [ ] **Step 1: Write the file**

```markdown
# Reliability Patterns — Java Overlay

Supplements `reliability-patterns.md` with Java-specific syntax checks. Apply in addition to the base checklist, never instead of it.

---

## Java-Specific Checks

Apply each item to every method or block in the diff where the condition matches.

**J1 — Broad catch**
Catching `Exception`, `Throwable`, or `Error` instead of a specific checked or unchecked type → flag as violation of Pattern #2.

**J2 — Empty catch block**
`catch (SomeException e) {}` with no log call and no rethrow → flag as violations of Patterns #3 and #4.

**J3 — Exception not logged**
A catch block that contains neither `log.error(...)`, `logger.error(...)`, `log.warn(...)`, nor an explicit `throw` → flag as violation of Pattern #3.

**J4 — Swallowed checked exception**
A checked exception wrapped in `RuntimeException` or similar without a log call before the wrap (i.e., `throw new RuntimeException(e)` with no preceding `log.error(...)`) → flag as violation of Pattern #3.

**J5 — Null as error signal**
A method returning `null` as an error signal without `@Nullable` annotation on the return type and without `Optional<T>` wrapper, where any call site in the diff uses the result without a null check → flag as violation of Pattern #1.

**J6 — Exception without root cause**
`throw new RuntimeException("message")` or `throw new SomeException("message")` without attaching the root cause as a constructor argument (correct form: `new RuntimeException("message", cause)`) → original exception lost, stack trace broken.
```

- [ ] **Step 2: Verify**

```bash
grep -c "^\*\*J[0-9]" skills/overlays/reliability-java.md
```
Expected output: `6`

```bash
ls skills/overlays/
```
Expected output: `reliability-java.md  reliability-python.md`

- [ ] **Step 3: Commit**

```bash
git add skills/overlays/reliability-java.md
git commit -m "feat(reviewer): add Java reliability overlay"
```

---

### Task 4: Rewrite agents/reviewer.md

**Files:**
- Modify: `agents/reviewer.md` (full rewrite — current file is 39 lines)

- [ ] **Step 1: Verify the hardcoded reference exists before removing it**

```bash
grep "skills/api-design.md" agents/reviewer.md
```
Expected: `- \`skills/api-design.md\``

- [ ] **Step 2: Write the new reviewer.md**

Replace the entire file content with:

```markdown
# Reviewer Agent

## Role
You review code for correctness, reliability, spec compliance, and convention adherence. You work through five mandatory lenses in sequence before producing any output. Do not skip lenses. Do not produce partial output mid-review.

## You receive
- The code diff to review
- The task entry (description + acceptance criteria)
- `CONVENTIONS.md`
- `reliability-patterns.md` — always present
- `{stack_overlay}` — optional: `reliability-python.md` or `reliability-java.md` if provided by orchestrator
- `{domain_skill}` — optional: `api-design.md` for HTTP projects if provided by orchestrator

## You produce
```
STATUS: PASS | FIX_REQUIRED

REQUIRED CHANGES (if any):
1. [file:line] Issue. Expected: X. Found: Y. [Pattern/Lens reference]
2. ...

CONVENTION CANDIDATES (if any):
- Pattern: [description]. Suggested rule: [rule text]
```

## Mandatory lens sequence

Work through every applicable lens before writing your output.

### Lens 1 — Reliability (always)
Apply each item in `reliability-patterns.md` to every relevant code path in the diff. Use the scope condition on each item to decide whether it applies — skip items whose scope condition is not met. If a stack overlay was provided, apply its checks immediately after the base checklist using the same scope discipline.

### Lens 2 — Domain skill (conditional)
If a domain skill was provided, apply it now. For `api-design.md`: check response envelope structure, HTTP status codes, URL versioning, validation at the API boundary, error message format, and whether internals are exposed in error responses. Skip this lens entirely if no domain skill was provided.

### Lens 3 — Spec coverage (always)
Read every acceptance criterion in the task entry. For each criterion, find the code path in the diff that satisfies it. If no code path satisfies a criterion, that is a required change: `[file] Criterion not implemented: "<criterion text>"`.

### Lens 4 — Edge cases (always)
For each public function introduced or modified in the diff, check whether the following inputs are explicitly handled: `null`/`None`, empty collection or string, zero or negative numbers where the domain makes them meaningful, very large input where overflow or performance matters. Flag every unhandled case as a required change.

### Lens 5 — Conventions and naming (always)
Check compliance with every rule in `CONVENTIONS.md`. Scan the diff for inconsistent names — function names, method names, type names used across multiple files. Every flag must cite a specific CONVENTIONS.md rule or a concrete `file:line` mismatch. Do not invent rules not in CONVENTIONS.md.

## Rules
1. Clearly separate "must fix" (required change, blocks pipeline) from "suggested" (convention candidate only — never blocks)
2. Every required change must reference the lens and item that triggered it: e.g., `[Pattern #3]`, `[Lens 4]`, `[api-design.md: status codes]`, `[P2]`, `[J5]`
3. Do not review code outside the scope of the current task
4. Be specific: file, line number, what is wrong, what is expected
5. If a pattern appears 3+ times in the diff, add it as a convention candidate

## Output for STATUS: PASS
Include a one-line per-lens confirmation:
```
STATUS: PASS

Lens 1 (Reliability): no violations found
Lens 2 (Domain skill): not provided — skipped / no violations found
Lens 3 (Spec coverage): all N criteria satisfied
Lens 4 (Edge cases): all public functions handle obvious edge inputs
Lens 5 (Conventions): no violations found
```

## Output to orchestrator
The structured block above is your entire output — do not add prose around it.
```

- [ ] **Step 3: Verify**

```bash
grep "skills/api-design.md" agents/reviewer.md
```
Expected: no output (zero matches)

```bash
grep -c "Lens [1-5]" agents/reviewer.md
```
Expected: `5` or more

```bash
grep "reliability-patterns.md" agents/reviewer.md
```
Expected: matches line in "You receive" section

- [ ] **Step 4: Commit**

```bash
git add agents/reviewer.md
git commit -m "feat(reviewer): rewrite with 5-lens sequential structure, remove hardcoded api-design.md"
```

---

### Task 5: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md` (update reviewer row at line ~149, update Skills table at lines ~162-168, add routing section after Skills table)

- [ ] **Step 1: Update the reviewer row in the Agents table**

Find and replace this exact line in the `## 🤖 Agents` table:
```
| `reviewer` | After coder | code + api-design.md | pass / fix list |
```

Replace with:
```
| `reviewer` | After coder | code + reliability-patterns.md + {stack_overlay} + {domain_skill} | pass / fix list |
```

- [ ] **Step 2: Replace the Skills table**

Find and replace this entire block:
```markdown
## 🔧 Skills (Lazy Load — Never Dump All)

| Skill file | Load when |
|---|---|
| `skills/coding-patterns.md` | Coder agent runs |
| `skills/api-design.md` | Reviewer agent runs |
| `skills/test-strategy.md` | Tester agent runs |
| `skills/security-rules.md` | Security agent runs |
| `skills/git-commit.md` | Git agent runs |
```

Replace with:
```markdown
## 🔧 Skills (Lazy Load — Never Dump All)

| Skill file | Load when |
|---|---|
| `skills/coding-patterns.md` | Coder agent runs |
| `skills/reliability-patterns.md` | Reviewer agent runs — always |
| `skills/api-design.md` | Reviewer agent runs — HTTP/API projects only (see routing below) |
| `skills/test-strategy.md` | Tester agent runs |
| `skills/security-rules.md` | Security agent runs |
| `skills/git-commit.md` | Git agent runs |

### Reviewer Routing

The orchestrator reads `memory/core.md` Stack field and loads the appropriate skills before dispatching the Reviewer. Routing is a judgment call based on the Stack description — apply the first match.

```
Reviewer always receives:
  skills/reliability-patterns.md

Stack overlay (first match wins, else none):
  Stack contains Python, Django, FastAPI, Flask, pytest  → skills/overlays/reliability-python.md
  Stack contains Java, Spring, Gradle, Maven, JUnit      → skills/overlays/reliability-java.md
  (add more overlays to skills/overlays/ as needed)

Domain skill (first match wins, else none):
  Stack contains HTTP, API, REST, GraphQL, FastAPI,
               Express, Django, Rails, Flask, Spring     → skills/api-design.md
  (none for CLI, worker, library projects — add when built)
```

Note: matching is case-insensitive. A Stack of "FastAPI + PostgreSQL" matches both the Python overlay and the api-design.md domain skill.
```

- [ ] **Step 3: Verify**

```bash
grep "reliability-patterns" CLAUDE.md
```
Expected: 2+ matches (Skills table + routing section)

```bash
grep "stack overlay" CLAUDE.md
```
Expected: matches routing section

```bash
grep "skills/api-design.md" CLAUDE.md | grep "Reviewer"
```
Expected: the updated Skills table row with "HTTP/API projects only"

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "feat(reviewer): add routing table and reliability-patterns to CLAUDE.md"
```

---

### Task 6: Update .claude/orchestrator.md

**Files:**
- Modify: `.claude/orchestrator.md` (same changes as Task 5 but with `.claude/skills/` paths)

- [ ] **Step 1: Update the reviewer row in the Agents table**

Find and replace this exact line:
```
| `reviewer` | After coder | code + `.claude/skills/api-design.md` | pass / fix list |
```

Replace with:
```
| `reviewer` | After coder | code + `.claude/skills/reliability-patterns.md` + {stack_overlay} + {domain_skill} | pass / fix list |
```

- [ ] **Step 2: Replace the Skills table**

Find and replace this entire block:
```markdown
## 🔧 Skills (Lazy Load — Never Dump All)

| Skill file | Load when |
|---|---|
| `.claude/skills/coding-patterns.md` | Coder agent runs |
| `.claude/skills/api-design.md` | Reviewer agent runs |
| `.claude/skills/test-strategy.md` | Tester agent runs |
| `.claude/skills/security-rules.md` | Security agent runs |
| `.claude/skills/git-commit.md` | Git agent runs |
```

Replace with:
```markdown
## 🔧 Skills (Lazy Load — Never Dump All)

| Skill file | Load when |
|---|---|
| `.claude/skills/coding-patterns.md` | Coder agent runs |
| `.claude/skills/reliability-patterns.md` | Reviewer agent runs — always |
| `.claude/skills/api-design.md` | Reviewer agent runs — HTTP/API projects only (see routing below) |
| `.claude/skills/test-strategy.md` | Tester agent runs |
| `.claude/skills/security-rules.md` | Security agent runs |
| `.claude/skills/git-commit.md` | Git agent runs |

### Reviewer Routing

The orchestrator reads `memory/core.md` Stack field and loads the appropriate skills before dispatching the Reviewer. Routing is a judgment call based on the Stack description — apply the first match.

```
Reviewer always receives:
  .claude/skills/reliability-patterns.md

Stack overlay (first match wins, else none):
  Stack contains Python, Django, FastAPI, Flask, pytest  → .claude/skills/overlays/reliability-python.md
  Stack contains Java, Spring, Gradle, Maven, JUnit      → .claude/skills/overlays/reliability-java.md
  (add more overlays to .claude/skills/overlays/ as needed)

Domain skill (first match wins, else none):
  Stack contains HTTP, API, REST, GraphQL, FastAPI,
               Express, Django, Rails, Flask, Spring     → .claude/skills/api-design.md
  (none for CLI, worker, library projects — add when built)
```

Note: matching is case-insensitive. A Stack of "FastAPI + PostgreSQL" matches both the Python overlay and the api-design.md domain skill.
```

- [ ] **Step 3: Verify**

```bash
grep "reliability-patterns" .claude/orchestrator.md
```
Expected: 2+ matches

```bash
grep "stack overlay" .claude/orchestrator.md
```
Expected: matches routing section

- [ ] **Step 4: Commit**

```bash
git add .claude/orchestrator.md
git commit -m "feat(reviewer): add routing table and reliability-patterns to orchestrator.md"
```

---

### Task 7: Create reviewer evaluation fixtures

**Files:**
- Create: `tests/reviewer-fixtures/fixture-1-python-multi-violation.md`
- Create: `tests/reviewer-fixtures/fixture-2-java-multi-violation.md`
- Create: `tests/reviewer-fixtures/fixture-3-http-api.md`
- Create: `tests/reviewer-fixtures/fixture-4-false-positive-trap.md`

These are evaluation fixtures — not automated tests. Each file contains code, task acceptance criteria, expected violations, and expected clean items. Run by dispatching the Reviewer agent with the fixture content as input.

- [ ] **Step 1: Create fixture-1-python-multi-violation.md**

```markdown
# Fixture 1 — Python Multi-Violation

**Purpose:** Verify Lens 1 (Reliability), Python overlay, and Lens 3 (Spec coverage) all fire.
**Inputs to Reviewer:** `reliability-patterns.md` + `reliability-python.md`

## Task acceptance criteria
- `UserService.get_user(user_id)` returns a `User` object on success
- `UserService.update_preferences(user_id, prefs)` returns `True` on success, `False` on failure
- Both methods handle missing users gracefully

## Code (treat as diff)

```python
import requests

class UserService:
    def __init__(self, db, cache):
        self.db = db
        self.cache = cache

    def get_user(self, user_id):
        try:
            cached = self.cache.get(f"user:{user_id}")
            if cached:
                return cached
            user = self.db.query("SELECT * FROM users WHERE id = %s", user_id)
            self.cache.set(f"user:{user_id}", user)
            return user
        except Exception:
            return {}

    def update_preferences(self, user_id, prefs):
        try:
            result = self.db.execute(
                "UPDATE users SET prefs = %s WHERE id = %s", prefs, user_id
            )
            if result.rowcount == 0:
                return False
            sync_url = f"http://prefs-service/sync/{user_id}"
            for attempt in range(100):
                r = requests.post(sync_url, json=prefs)
                if r.status_code == 200:
                    return True
            return False
        except Exception:
            return False

    def _parse_prefs(self, raw):
        data = open(f"/config/defaults/{raw['locale']}.json").read()
        return {**raw, **eval(data)}
```

## Expected FIX_REQUIRED (all must appear)
1. `get_user`: returns `{}` for both success (empty result) and caught exception — caller cannot distinguish [Pattern #1]
2. `get_user`: bare `except Exception` — no specific exception type [P1]
3. `get_user`: exception swallowed with no log entry [Pattern #3]
4. `update_preferences`: bare `except Exception` — no specific exception type [P1]
5. `update_preferences`: retry loop runs up to 100 times with no upper bound enforced, retries on all errors including permanent [Pattern #5]
6. `update_preferences`: no log per retry attempt [Pattern #5]
7. `update_preferences`: exception swallowed with no log entry [Pattern #3]
8. `_parse_prefs`: unchecked `open()` call [P4]
9. `_parse_prefs`: `eval(data)` on external file content — security concern
10. Spec criterion not met: `get_user` does not guarantee returning a `User` object — returns raw DB row or `{}` [Lens 3]

## Expected clean (must NOT be flagged)
- `update_preferences` returning `False` when `rowcount == 0` — correct spec behaviour
- `_parse_prefs` merging defaults with raw prefs — acceptable logic
```

- [ ] **Step 2: Create fixture-2-java-multi-violation.md**

```markdown
# Fixture 2 — Java Multi-Violation

**Purpose:** Verify Lens 1 (Reliability), Java overlay, and Lens 3 (Spec coverage) all fire.
**Inputs to Reviewer:** `reliability-patterns.md` + `reliability-java.md`

## Task acceptance criteria
- `PaymentProcessor.charge(customerId, amount)` returns a `PaymentResult` with status and transaction ID
- Insufficient funds must be distinguishable from network errors at the call site
- All payment attempts must be logged

## Code (treat as diff)

```java
public class PaymentProcessor {
    private final PaymentGateway gateway;
    private final AuditLog audit;

    public PaymentResult charge(String customerId, double amount) {
        try {
            GatewayResponse resp = gateway.submit(customerId, amount);
            audit.record(customerId, amount, "success");
            return new PaymentResult(resp.getTxId(), null);
        } catch (Exception e) {
            return new PaymentResult(null, null);
        }
    }

    public void refund(String txId) {
        try {
            gateway.reverse(txId);
        } catch (InsufficientFundsException e) {
        } catch (Exception e) {
            throw new RuntimeException("refund failed");
        }
    }

    private PaymentResult retryCharge(String customerId, double amount, int maxAttempts) {
        PaymentResult result = null;
        for (int i = 0; i < maxAttempts; i++) {
            result = charge(customerId, amount);
            if (result.isSuccess()) return result;
        }
        return result;
    }

    public String getStatus(String txId) {
        try {
            return gateway.lookup(txId).getStatus();
        } catch (Exception e) {
            return null;
        }
    }
}
```

## Expected FIX_REQUIRED (all must appear)
1. `charge`: `catch (Exception e)` swallows `InsufficientFundsException` and network errors identically — violates spec requirement that callers can distinguish them [Pattern #2, J1]
2. `charge`: `new PaymentResult(null, null)` returned for all failures — indistinguishable at call site [Pattern #1]
3. `charge`: exception caught with no log — failures are invisible to operators [Pattern #3, Pattern #4]
4. `refund`: `catch (InsufficientFundsException e) {}` — empty catch block [J2]
5. `refund`: `throw new RuntimeException("refund failed")` — no root cause attached [J6]
6. `retryCharge`: `maxAttempts` is caller-controlled with no upper bound enforced internally [Pattern #5]
7. `retryCharge`: delegates to `charge()` which swallows all exceptions — retries permanent failures [Pattern #5]
8. `retryCharge`: no log per retry attempt [Pattern #5]
9. `getStatus`: returns `null` as error signal — `@Nullable` annotation missing [J5, Pattern #1]
10. Spec criterion not met: `charge` logs success via audit.record but never logs failure [Lens 3]

## Expected clean (must NOT be flagged)
- Constructor injection of `gateway` and `audit` — correct design
- `retryCharge` being private — acceptable
```

- [ ] **Step 3: Create fixture-3-http-api.md**

```markdown
# Fixture 3 — HTTP API Multi-Violation

**Purpose:** Verify Lens 1 (Reliability), Lens 2 (api-design.md), Python overlay, and Lens 3 (Spec coverage) all fire together.
**Inputs to Reviewer:** `reliability-patterns.md` + `reliability-python.md` + `api-design.md`

## Task acceptance criteria
- `POST /v1/orders` creates an order and returns the order ID
- Duplicate order reference returns a conflict response
- Invalid payload returns a validation error with all field errors listed

## Code (treat as diff)

```python
from flask import Flask, request, jsonify

app = Flask(__name__)

@app.route('/orders', methods=['POST'])
def create_order():
    data = request.json
    if not data.get('reference'):
        return jsonify({'error': 'reference required'}), 400

    try:
        order = db.create_order(data['reference'], data.get('items', []))
        return jsonify({'id': order.id}), 200
    except DuplicateKeyError:
        return jsonify({'error': 'duplicate reference'}), 400
    except Exception as e:
        return jsonify({'error': str(e)}), 500
```

## Expected FIX_REQUIRED (all must appear)
1. Route is `/orders` — missing version prefix, should be `/v1/orders` [api-design.md: versioning]
2. Success response `{'id': order.id}` does not use `{data, error, meta}` envelope [api-design.md: response envelope]
3. Error responses `{'error': '...'}` do not use `{data, error, meta}` envelope [api-design.md: response envelope]
4. Created resource returns `200` — should return `201` [api-design.md: status codes]
5. Duplicate reference returns `400` — should return `409` [api-design.md: status codes]
6. Spec criterion not met: validation only checks `reference`; spec requires all field errors at once but `items` is never validated [Lens 3, api-design.md: input validation]
7. `except Exception as e: return jsonify({'error': str(e)})` exposes internal error details [api-design.md: error messages]
8. `except Exception` — bare catch-all [P1]
9. No log on the `except Exception` path [Pattern #3]

## Expected clean (must NOT be flagged)
- Checking `data.get('reference')` before DB call — correct validation-at-boundary
- Catching `DuplicateKeyError` specifically — correct
```

- [ ] **Step 4: Create fixture-4-false-positive-trap.md**

```markdown
# Fixture 4 — False Positive Trap

**Purpose:** Verify the Reviewer does NOT over-flag well-written code. Expected verdict: STATUS: PASS.
**Inputs to Reviewer:** `reliability-patterns.md` + `reliability-python.md`

## Task acceptance criteria
- `fetch_config(env)` returns a `Config` object on success
- Raises `ConfigNotFoundError` (not returns) when env is unknown
- Network failures are retried up to 3 times with exponential backoff

## Code (treat as diff)

```python
import logging
import time

logger = logging.getLogger(__name__)


class ConfigNotFoundError(ValueError):
    pass


class TransientNetworkError(IOError):
    pass


def fetch_config(env: str) -> "Config":
    if not env:
        raise ValueError("env must not be empty")

    for attempt in range(1, 4):
        try:
            response = config_service.get(env)
            if response.status == 404:
                raise ConfigNotFoundError(f"No config for env: {env}")
            return Config.from_response(response)
        except ConfigNotFoundError:
            raise
        except TransientNetworkError as exc:
            logger.warning(
                "fetch_config attempt %d/3 failed for env=%s: %s",
                attempt, env, exc,
            )
            if attempt == 3:
                raise
            time.sleep(2 ** attempt)
        except Exception as exc:
            logger.error(
                "Unexpected error fetching config for env=%s",
                env,
                exc_info=True,
            )
            raise
```

## Expected verdict: STATUS: PASS

The Reviewer must confirm each lens was applied and found no issues:

- **Lens 1 — Reliability:** Return type is `Config` on success, exception raised on all failure paths — distinguishable [Pattern #1 ✓]. Specific exception types caught: `ConfigNotFoundError`, `TransientNetworkError`, broad `Exception` re-raises immediately [Pattern #2 ✓]. Each catch that doesn't re-raise logs before continuing [Pattern #3 ✓]. Retries bounded at 3, only on `TransientNetworkError`, each attempt logged [Pattern #5 ✓].
- **Lens 1 — Python overlay:** No bare `except:`. No silent `pass`. Broad `except Exception` re-raises — acceptable. No unchecked I/O. No Optional error signal [all P1-P5 ✓].
- **Lens 2 — Domain skill:** Not provided — skipped.
- **Lens 3 — Spec coverage:** All three criteria satisfied [✓].
- **Lens 4 — Edge cases:** Empty `env` raises `ValueError` [✓].
- **Lens 5 — Conventions:** No CONVENTIONS.md violations detectable without content.

## Must NOT produce any FIX_REQUIRED items
```

- [ ] **Step 5: Verify all four fixtures exist**

```bash
ls tests/reviewer-fixtures/
```
Expected output:
```
fixture-1-python-multi-violation.md
fixture-2-java-multi-violation.md
fixture-3-http-api.md
fixture-4-false-positive-trap.md
```

- [ ] **Step 6: Commit**

```bash
git add tests/reviewer-fixtures/
git commit -m "test(reviewer): add evaluation fixtures for reliability patterns"
```

---

### Task 8: Run all structural verification checks

**Files:** None — verification only.

- [ ] **Step 1: Run all structural checks from the spec**

```bash
grep "reliability-patterns" agents/reviewer.md
```
Expected: matches `reliability-patterns.md` in "You receive" section

```bash
grep "skills/api-design.md" agents/reviewer.md
```
Expected: no output (zero matches — it is no longer hardcoded)

```bash
ls skills/overlays/
```
Expected: `reliability-java.md  reliability-python.md`

```bash
grep "reliability-patterns" CLAUDE.md
```
Expected: 2+ matches

```bash
grep "reliability-patterns" .claude/orchestrator.md
```
Expected: 2+ matches

```bash
grep -c "Lens [1-5]" agents/reviewer.md
```
Expected: `5` or higher

```bash
grep "stack overlay" CLAUDE.md
```
Expected: matches routing section

```bash
grep "stack overlay" .claude/orchestrator.md
```
Expected: matches routing section

- [ ] **Step 2: Fix any check that fails, then re-run until all pass**

- [ ] **Step 3: Final commit**

```bash
git add -A
git commit -m "feat(#29): iron-clad reviewer with reliability patterns and routing

- skills/reliability-patterns.md: language-agnostic 5-category checklist
- skills/overlays/reliability-python.md: 5 Python-specific rules
- skills/overlays/reliability-java.md: 6 Java-specific rules
- agents/reviewer.md: 5-lens sequential mandatory review structure
- CLAUDE.md + orchestrator.md: routing table for stack-aware skill loading
- tests/reviewer-fixtures/: 4 evaluation fixtures (3 violation cases + 1 pass trap)

Closes #29"
```

- [ ] **Step 4: Run evaluation fixture smoke test (manual)**

Dispatch the Reviewer agent with Fixture 4 (false positive trap) as input plus `reliability-patterns.md` and `reliability-python.md`. Confirm the output is `STATUS: PASS` with per-lens confirmations and zero FIX_REQUIRED items. This is the most important check — if the Reviewer over-flags clean code, the lens scoping rules in the skill files need tightening.
