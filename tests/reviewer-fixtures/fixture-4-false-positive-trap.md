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

- **Lens 1 — Reliability:** Return type is `Config` on success, exception raised on all failure paths — distinguishable [Pattern #1 ✓]. Specific exception types caught: `ConfigNotFoundError`, `TransientNetworkError`, broad `Exception` re-raises immediately [Pattern #2 ✓]. Each catch that doesn't re-raise logs before handling [Pattern #3 ✓]. Retries bounded at 3, only on `TransientNetworkError`, each attempt logged [Pattern #5 ✓].
- **Lens 1 — Python overlay:** No bare `except:`. No silent `pass`. Broad `except Exception` re-raises immediately — acceptable per P3 carve-out. No unchecked I/O. No Optional error signal [P1–P5 ✓].
- **Lens 2 — Domain skill:** Not provided — skipped.
- **Lens 3 — Spec coverage:** All three criteria satisfied [✓].
- **Lens 4 — Edge cases:** Empty `env` raises `ValueError` [✓].
- **Lens 5 — Conventions:** No CONVENTIONS.md violations detectable without content.

## Must NOT produce any FIX_REQUIRED items
