---
title: Iron-clad Reviewer + Reliability Patterns
date: 2026-06-05
issue: "#29"
status: approved
---

## Problem

Three coupled failures cause silent pipeline degradation on non-HTTP projects:

1. `agents/reviewer.md` hardcodes `skills/api-design.md` in its input list regardless of project type. A Python CLI or background worker gets reviewed against HTTP response envelopes and REST conventions — irrelevant criteria that miss real issues.

2. `skills/reliability-patterns.md` does not exist. The concern "can an operator distinguish a clean result from a failed call?" belongs to nobody's checklist and falls through every pipeline stage.

3. Both `CLAUDE.md` and `.claude/orchestrator.md` hardcode `api-design.md` in the reviewer row of the Agents table and the Skills table. The orchestrator never routes by project type.

## Decision

### New files

| File | Purpose |
|---|---|
| `skills/reliability-patterns.md` | Language-agnostic scoped checklist — 5 categories |
| `skills/overlays/reliability-python.md` | Python-specific reliability rules |
| `skills/overlays/reliability-java.md` | Java-specific reliability rules |

### Modified files

| File | Change |
|---|---|
| `agents/reviewer.md` | Remove hardcoded `api-design.md`; add 5-lens sequential structure |
| `CLAUDE.md` | Add routing table; update Agents and Skills tables |
| `.claude/orchestrator.md` | Same routing table and table updates (duplication is intentional — see note below) |

**Note on duplication:** `CLAUDE.md` (template, dirs at root) and `.claude/orchestrator.md` (bootstrapped projects, dirs in `.claude/`) cannot share a single file because hook paths differ. Routing tables and agent/skill tables contain no paths and are identical in both files — update both whenever either changes. Path-sensitive deduplication is deferred to a future issue.

---

## reliability-patterns.md — base checklist

Five scoped categories. Each item states the check, the scope condition (when to apply it), and what a violation looks like. Language-agnostic — no syntax, only concepts.

### 1 — Error state distinguishability
**Scope:** any function with a non-void return value.
**Check:** can the caller distinguish success from failure from the return value alone, without reading the implementation?
**Pass:** success and failure return structurally different values (different types, distinct sentinel, raised exception).
**Violation:** `{}`, `None`, `0`, or `""` returned for both success and caught exception.

### 2 — Exception classification
**Scope:** any catch / except / rescue block.
**Check:** is the caught type specific? Is the exception documented or commented as transient (safe to retry) or permanent (do not retry)?
**Pass:** specific exception type caught; retry behaviour is explicit.
**Violation:** bare catch-all with no transient/permanent distinction; callers cannot determine retry safety.

### 3 — Log before handle
**Scope:** any caught exception that is not re-raised.
**Check:** is the error logged (at WARN or above) before the handler continues?
**Pass:** log call appears before any recovery logic.
**Violation:** exception swallowed with no log entry; failure disappears from observability.

### 4 — Observable failure
**Scope:** any error path (caught exception, early return on error condition, failed I/O).
**Check:** is there at least one observable signal — a log entry, a metric increment, or a structurally distinct return value — that an operator can detect without reading source code?
**Pass:** at least one signal present per error path.
**Violation:** silent failure — the call completes with no externally detectable difference from success.

### 5 — Retry discipline
**Scope:** only code that performs retries (explicit retry loops, backoff helpers, retry decorators/annotations).
**Check:** (a) is the retry count bounded? (b) does the retry only apply to transient errors? (c) is each retry attempt logged?
**Pass:** all three hold.
**Violation:** unbounded retries; retrying permanent errors; silent retries with no log.

---

## reliability-python.md — Python overlay

Supplements the base checklist with Python-specific syntax checks. Applied in addition to the base, never instead of it.

- Bare `except:` or `except Exception:` without a specific exception type → flag
- `except SomeError: pass` with no log call inside the block → flag
- Caught exception without `logging.exception()`, `logger.error(..., exc_info=True)`, or explicit `raise` → flag
- Unchecked return from stdlib I/O calls (`open`, `subprocess.run`, `os.*`) that can raise, where the caller does not handle the exception → flag
- `Optional[T]` return type used as a success/failure signal (returns `None` on error) without a `None` check at every call site in the diff → flag

---

## reliability-java.md — Java overlay

Supplements the base checklist with Java-specific syntax checks.

- Catching `Exception`, `Throwable`, or `Error` instead of a specific checked or unchecked type → flag
- Empty catch block `catch (Exception e) {}` with no log or rethrow → flag
- Caught exception without `log.error(...)` or `logger.error(...)` before handler → flag
- Checked exception swallowed by wrapping in `RuntimeException` without a log call → flag
- `null` returned as an error signal without `@Nullable` annotation or `Optional<T>` wrapper → flag
- `throw new RuntimeException("message")` or similar without a root cause attached (`new RuntimeException("msg", e)`) → flag

---

## reviewer.md — restructured input and lens sequence

### Input contract (updated)
```
{diff}
CONVENTIONS.md
reliability-patterns.md          ← always
{stack_overlay}                  ← optional: reliability-python.md or reliability-java.md
{domain_skill}                   ← optional: api-design.md for HTTP projects
```

### Mandatory lens sequence

The reviewer MUST work through all applicable lenses in order before producing output. Lenses are not optional.

**Lens 1 — Reliability (always)**
Apply the reliability-patterns.md scoped checklist to every relevant code path. Also apply the stack overlay if provided. For each checklist item, scope it: skip items whose scope condition does not apply to the code under review.

**Lens 2 — Domain skill (conditional)**
If a domain skill was provided, apply it. For `api-design.md`: check response envelope, HTTP status codes, validation at boundary. Skip this lens entirely if no domain skill was provided.

**Lens 3 — Spec coverage (always)**
For each acceptance criterion in the task entry, verify a code path satisfies it. A criterion with no corresponding implementation is a required change.

**Lens 4 — Edge cases (always)**
For each public function introduced or modified in the diff, check whether obvious inputs are handled: `null`/`None`, empty collection, zero/negative number, very large input. Flag every unhandled case as a required change.

**Lens 5 — Conventions and naming (always)**
Check compliance with `CONVENTIONS.md`. Check naming consistency across files in the diff. Every flag must cite a specific CONVENTIONS.md rule or a concrete `file:line` mismatch — do not invent rules.

---

## Routing table (CLAUDE.md + orchestrator.md)

Add to both files. Routing is done by the orchestrator before dispatching the Reviewer.

```
Reviewer always receives:
  reliability-patterns.md

Stack overlay (load first match, else none):
  Stack contains Python, Django, FastAPI, Flask, pytest  → skills/overlays/reliability-python.md
  Stack contains Java, Spring, Gradle, Maven, JUnit      → skills/overlays/reliability-java.md
  (none yet for CLI, worker, Go, Rust — add when built)

Domain skill (load first match, else none):
  Stack contains HTTP, API, REST, GraphQL, FastAPI,
               Express, Django, Rails, Flask, Spring     → skills/api-design.md
  (none yet for others — add when built)
```

For bootstrapped projects, replace `skills/` with `.claude/skills/` in all paths above.

---

## Verification

### Structural checks (automated)

```bash
# File structure
grep "reliability-patterns" agents/reviewer.md          # must match
grep "skills/api-design.md" agents/reviewer.md          # must return 0 matches (no longer hardcoded)
ls skills/overlays/                                     # reliability-python.md, reliability-java.md
grep "reliability-patterns" CLAUDE.md                   # must appear in routing table
grep "reliability-patterns" .claude/orchestrator.md     # must appear in routing table

# Content integrity
grep -c "Lens" agents/reviewer.md                       # must be >= 5
grep "stack overlay" CLAUDE.md                          # must match
grep "stack overlay" .claude/orchestrator.md            # must match
```

### Reviewer evaluation fixtures

These are evaluation fixtures, not automated tests. Run each by dispatching the Reviewer agent with the fixture code as the diff and the listed acceptance criteria as the task entry. Verify the output matches the expected verdict and that every listed violation is flagged. None of the expected clean items should be flagged.

Fixtures live in `tests/reviewer-fixtures/`. Each fixture is a self-contained `.md` file with: code, task acceptance criteria, expected FIX_REQUIRED items, and expected clean items.

---

#### Fixture 1 — Python multi-violation (Lenses 1, 2, 3, 4 + Python overlay)

**Inputs:** `reliability-patterns.md` + `reliability-python.md`
**Task acceptance criteria:**
- `UserService.get_user(user_id)` returns a `User` object on success
- `UserService.update_preferences(user_id, prefs)` returns `True` on success, `False` on failure
- Both methods handle missing users gracefully

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

**Expected FIX_REQUIRED (must all appear):**
1. `get_user`: returns `{}` for both success (empty result) and caught exception — caller cannot distinguish (Pattern #1)
2. `get_user`: bare `except Exception` — no specific exception type (Python overlay)
3. `get_user`: exception swallowed with no log entry (Pattern #3)
4. `update_preferences`: bare `except Exception` — no specific exception type (Python overlay)
5. `update_preferences`: retry loop runs up to 100 times on all failure conditions including permanent errors (Pattern #5)
6. `update_preferences`: retries not logged — silent retry storm possible (Pattern #5)
7. `update_preferences`: exception swallowed with no log entry (Pattern #3)
8. `_parse_prefs`: unchecked `open()` call — file not found raises unhandled exception (Python overlay)
9. `_parse_prefs`: `eval(data)` on external file content — security concern (also caught by Security agent, but reviewer flags it)
10. Spec criterion not met: `get_user` does not return a `User` object on success — returns raw DB row or `{}` (Lens 3)

**Expected clean (must NOT be flagged):**
- `update_preferences` correctly returns `False` when `rowcount == 0` — this is intentional spec behaviour
- `_parse_prefs` merging defaults with raw prefs is acceptable logic

---

#### Fixture 2 — Java multi-violation (Lenses 1, 2, 3, 4 + Java overlay)

**Inputs:** `reliability-patterns.md` + `reliability-java.md`
**Task acceptance criteria:**
- `PaymentProcessor.charge(customerId, amount)` returns a `PaymentResult` with status and transaction ID
- Insufficient funds must be distinguishable from network errors at the call site
- All payment attempts must be logged

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

**Expected FIX_REQUIRED (must all appear):**
1. `charge`: broad `catch (Exception e)` — swallows `InsufficientFundsException` and `NetworkException` identically, violating spec requirement that callers can distinguish them (Pattern #2, Java overlay)
2. `charge`: returns `new PaymentResult(null, null)` for both network failure and insufficient funds — indistinguishable at call site (Pattern #1)
3. `charge`: exception caught with no log — audit only records success, failures are invisible (Pattern #3, Pattern #4)
4. `refund`: `catch (InsufficientFundsException e) {}` — empty catch block, exception silently discarded (Java overlay)
5. `refund`: `throw new RuntimeException("refund failed")` — no root cause attached, original exception lost (Java overlay)
6. `retryCharge`: `maxAttempts` is caller-controlled and unbounded in practice — no upper bound enforced internally (Pattern #5)
7. `retryCharge`: calls `charge()` which itself swallows exceptions — retries on permanent failures (Pattern #5)
8. `retryCharge`: no logging per attempt (Pattern #5)
9. `getStatus`: returns `null` as error signal — `@Nullable` annotation missing, callers cannot distinguish "not found" from "error" (Java overlay, Pattern #1)
10. Spec criterion not met: `charge` logs success but audit.record is never called on failure (Lens 3)

**Expected clean (must NOT be flagged):**
- Constructor injection of `gateway` and `audit` is correct design
- `retryCharge` being private is acceptable

---

#### Fixture 3 — HTTP API project (Lenses 1, 2 with api-design.md + Lens 3)

**Inputs:** `reliability-patterns.md` + `api-design.md`
**Task acceptance criteria:**
- `POST /v1/orders` creates an order and returns the order ID
- Duplicate order reference returns a conflict response
- Invalid payload returns a validation error with all field errors listed

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

**Expected FIX_REQUIRED (must all appear):**
1. Route missing version prefix — `/orders` should be `/v1/orders` (api-design.md)
2. Success response `{'id': order.id}` does not use the `{data, error, meta}` envelope (api-design.md)
3. Error responses `{'error': '...'}` do not use the `{data, error, meta}` envelope (api-design.md)
4. Created resource returns `200` — should return `201` (api-design.md)
5. Duplicate reference returns `400` — should return `409` (api-design.md)
6. Validation only checks `reference` — spec requires all field errors returned at once; `items` is never validated (Lens 3, api-design.md)
7. `except Exception as e: return jsonify({'error': str(e)})` — exposes internal error details in response (api-design.md)
8. `except Exception` — bare catch-all (Python overlay)
9. No log on the bare `except Exception` path (Pattern #3)

**Expected clean (must NOT be flagged):**
- Checking `data.get('reference')` before DB call is correct validation-at-boundary
- `DuplicateKeyError` being caught specifically is correct

---

#### Fixture 4 — False positive trap (expected STATUS: PASS)

**Inputs:** `reliability-patterns.md` + `reliability-python.md`
**Task acceptance criteria:**
- `fetch_config(env)` returns a `Config` object on success
- Returns `ConfigNotFoundError` (raised, not returned) when env is unknown
- Network failures are retried up to 3 times with exponential backoff

```python
import logging
import time
from typing import Optional

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
                attempt, env, exc
            )
            if attempt == 3:
                raise
            time.sleep(2 ** attempt)
        except Exception as exc:
            logger.error("Unexpected error fetching config for env=%s", exc_info=True)
            raise
```

**Expected verdict: `STATUS: PASS`**

Reasoning the reviewer must demonstrate:
- Return type is `Config` (distinct from exception path) — Pattern #1 satisfied
- Specific exception types caught: `ConfigNotFoundError`, `TransientNetworkError`, bare `Exception` is a catch-all but re-raises immediately with log — Pattern #2 and #3 satisfied
- Each retry attempt is logged at WARNING — Pattern #5 satisfied
- Retry bounded at 3, only on `TransientNetworkError` — Pattern #5 satisfied
- Edge case: empty `env` raises `ValueError` — Lens 4 satisfied
- No convention violations assumable without CONVENTIONS.md content
