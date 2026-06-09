## Role Profile

**Agent:** Tester
**Your input contract:** Implemented code (from coder), `CONVENTIONS.md` (testing section), this skill file
**Read list (in order):**
1. This skill file
2. `CONVENTIONS.md`
**Your output contract:** Integration tests, edge case tests (boundary values, null inputs, empty collections, error paths), acceptance criteria tests, full test suite run results; JSON envelope with `verdict: "PASS"` or `verdict: "FAIL"`; on PASS includes test counts by type; on FAIL includes failures list and attempted fix; `next_agent: "security"` on PASS, `next_agent: "coder"` on FAIL
**Gates owned:** none (FAIL returns to coder but does not halt the pipeline permanently; only two FAILs in a row marks task blocked)

---

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

## Mandatory HTTP Layer Test (non-negotiable)
Every feature that exposes or modifies an HTTP endpoint **must** include at least one test that:
- Starts a real application context (no mocked services at the HTTP boundary)
- Sends a real HTTP request through the full stack
- Asserts on the HTTP response status and body

The specific mechanism is stack-defined in `CONVENTIONS.md`. Generic examples:
- **Spring Boot:** `@SpringBootTest` + `MockMvc` or `TestRestTemplate`
- **FastAPI / Django:** `TestClient` with the real app instance
- **Express / Fastify:** `supertest` against the real app
- **Go:** `httptest.NewRecorder` with the real handler

This test must run in CI. If there is no CI pipeline, the DevOps agent must create one before this task is considered complete.

## Post-Deploy Smoke Test (required when a deploy step exists)
After every deployment, the DevOps agent must verify the service is alive by hitting the health or root endpoint and asserting a 2xx response. This is stack/infra-agnostic — the exact endpoint and method go in `memory/core.md` under `[infra]`.

## TDD Discipline
1. Write the failing test first — confirm it fails for the right reason
2. Write minimal code to pass — only what the test requires
3. Refactor — clean up while keeping tests green
4. Commit when green — never commit with failing tests
