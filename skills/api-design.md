## Role Profile

**Agent:** Reviewer (HTTP projects only)
**Your input contract:** Code diff, task entry (description + acceptance criteria), `CONVENTIONS.md`, `reliability-patterns.md` (always loaded before this file), this skill file (loaded only when Stack contains HTTP/API/REST/GraphQL/FastAPI/Express/Django/Rails/Flask/Spring)
**Read list (in order):**
1. `skills/reliability-patterns.md` (loaded first by orchestrator)
2. This skill file
3. Stack overlay (if provided by orchestrator)
4. `CONVENTIONS.md`
**Your output contract:** Single JSON envelope with `verdict: "PASS"` or `verdict: "FIX_REQUIRED"`; Lens 2 (Domain skill) checks response envelope, HTTP status codes, URL versioning, validation at API boundary, error message format, and whether internals are exposed in errors; `next_agent: "tester"` on PASS, `next_agent: "coder"` on FIX_REQUIRED
**Gates owned:** none

---

# API Design Principles

## Response Envelope
All API responses use a consistent structure:

Success:
```json
{
  "data": { ... },
  "error": null,
  "meta": { "timestamp": "2026-05-14T12:00:00Z", "version": "1" }
}
```

Error:
```json
{
  "data": null,
  "error": { "code": "RESOURCE_NOT_FOUND", "message": "User 123 not found" },
  "meta": { "timestamp": "2026-05-14T12:00:00Z" }
}
```

## HTTP Conventions
- GET: retrieve only, never mutate
- POST: create
- PUT: full replacement
- PATCH: partial update
- DELETE: remove
- Resource names are nouns: `/users/123` not `/getUser?id=123`

## Status Codes
- 200: success
- 201: created (POST)
- 400: client error — invalid input
- 401: unauthenticated — who are you?
- 403: unauthorized — I know who you are, but no
- 404: not found
- 409: conflict (e.g. duplicate)
- 422: validation error
- 500: server error — never expose internals in the message

## Versioning
- Version in URL path: `/v1/users`
- Never break a published version — add a new version instead

## Error Messages
- Machine-readable: consistent `code` field (SCREAMING_SNAKE_CASE)
- Human-readable: plain language `message`
- Actionable: tell the caller what to fix

## Pagination
- Cursor-based for large or frequently-changing datasets
- Always return a `next_cursor` and total count
- Default page size: 20. Maximum: 100.

## Input Validation
- Validate at the API boundary, not inside service logic
- Return all validation errors at once — not just the first one
- Be strict on input; lenient on output
