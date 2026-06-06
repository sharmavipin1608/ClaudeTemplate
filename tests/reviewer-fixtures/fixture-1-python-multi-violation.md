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
5. `update_preferences`: retry loop runs up to 100 times with no bounded maximum enforced, retries on all errors including permanent [Pattern #5]
6. `update_preferences`: no log per retry attempt [Pattern #5]
7. `update_preferences`: exception swallowed with no log entry [Pattern #3]
8. `_parse_prefs`: unchecked `open()` call — not directly enclosed in try/except [P4]
9. `_parse_prefs`: `eval(data)` on external file content — security concern
10. Spec criterion not met: `get_user` does not guarantee returning a `User` object — returns raw DB row or `{}` [Lens 3]

## Expected clean (must NOT be flagged)
- `update_preferences` returning `False` when `rowcount == 0` — correct spec behaviour
- `_parse_prefs` merging defaults with raw prefs — acceptable logic
