# Test Strategy

## Test Pyramid
- **Unit (most):** Test individual functions in isolation. No I/O. Milliseconds to run.
- **Integration (some):** Test components working together with real infrastructure. Seconds to run.
- **End-to-end (few):** Test full user journeys. Minutes to run. Use sparingly.

## What Makes a Good Test
- Tests one thing — one concept per test
- Name is a specification: `test_login_fails_with_expired_token` not `test_login_2`
- Arrange-Act-Assert structure
- Independent — tests do not depend on each other or share mutable state
- Deterministic — same result on every run, regardless of order

## Unit Test Rules
- No file I/O, no network, no database, no `time.sleep`
- Use dependency injection to swap real dependencies for test doubles
- Test the public interface — not implementation details
- Always test: happy path, empty/null inputs, boundary values, error paths

## Integration Test Rules
- Use real infrastructure (real DB, real filesystem in tmpdir) over mocks
- Use transactions or tmp directories for isolation — clean up after each test
- Test the seam between components, not every internal detail

## What NOT to Test
- Framework internals (ORM queries, HTTP routing — they have their own test suites)
- Trivial pass-through code with no logic
- Code that only calls other well-tested code

## TDD Discipline
1. Write the failing test first — confirm it fails for the right reason
2. Write minimal code to pass — only what the test requires
3. Refactor — clean up while keeping tests green
4. Commit when green — never commit with failing tests
