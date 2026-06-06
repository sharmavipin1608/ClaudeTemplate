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
A catch block that is not already covered by J2 (i.e., not an empty block) and contains neither `log.error(...)`, `logger.error(...)`, `log.warn(...)`, nor an explicit `throw` → flag as violation of Pattern #3.

**J4 — Swallowed checked exception**
A checked exception wrapped in `RuntimeException` or similar without a log call before the wrap (i.e., `throw new RuntimeException(e)` with no preceding `log.error(...)`) → flag as violation of Pattern #3.

**J5 — Null as error signal**
A method returning `null` as an error signal without `@Nullable` annotation on the return type and without `Optional<T>` wrapper, where any call site in the diff uses the result without a null check → flag as violation of Pattern #1.

**J6 — Exception without root cause**
`throw new RuntimeException("message")` or `throw new SomeException("message")` without attaching the root cause as a constructor argument (correct form: `new RuntimeException("message", cause)`) → original exception lost, stack trace broken.
