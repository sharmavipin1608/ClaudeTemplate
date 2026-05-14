# CONVENTIONS.md

Living document — actively maintained by the reviewer and memory agents.
Last reviewed: {{DATE}}

---

## Code Style

### Naming
- Variables and functions: snake_case
- Classes: PascalCase
- Constants: UPPER_SNAKE_CASE
- Private methods: _leading_underscore
- TODO: Add language-specific naming rules for {{TECH_STACK}}

### Formatting
- Indentation: 4 spaces (no tabs)
- Max line length: 100 characters
- Blank lines between top-level definitions: 2
- TODO: Specify formatter (black, prettier, gofmt, etc.) and version

### Imports
- Standard library first, third-party second, local last
- Alphabetical within each group
- No wildcard imports (`from x import *`)
- TODO: Add project-specific import conventions

---

## Architecture

### Folder Structure
- Source code: `src/` or project root depending on stack
- Tests: `tests/` mirroring source structure
- Documentation: `docs/`
- Scripts: `scripts/`
- TODO: Define actual folder structure for {{TECH_STACK}}

### Patterns
- Prefer composition over inheritance
- One responsibility per module/file
- Interfaces before implementations
- TODO: Define stack-specific patterns (e.g., repository pattern, service layer, etc.)

### What to Avoid
- God objects / monolithic files
- Tight coupling between layers
- Global mutable state
- TODO: Add project-specific anti-patterns to avoid

---

## Testing

### Unit Tests
- Every public function has a unit test
- Tests are co-located in `tests/` mirroring source structure
- Test naming: `test_<function_name>_<scenario>`
- One assertion per test (prefer this over multi-assertion tests)
- TDD: write failing test first, then implement

### Integration Tests
- Cover cross-layer flows (API → service → database)
- Use real database/external services in integration tests — no mocks
- Tag with `@pytest.mark.integration` or equivalent

### Coverage
- Unit test coverage target: 80% minimum
- No coverage exceptions without a comment explaining why
- TODO: Set actual coverage targets and enforcement (CI check, pre-commit hook)

### What Not to Test
- Framework internals
- Third-party library behavior
- Trivial getters/setters with no logic

---

## Git

### Branch Naming
- Features: `feat/<short-description>`
- Bug fixes: `fix/<short-description>`
- Chores: `chore/<short-description>`
- Docs: `docs/<short-description>`

### Commit Style
- Format: `<type>: <short description>` (50 chars max for subject)
- Types: feat, fix, chore, docs, test, refactor, perf
- Body: wrap at 72 chars, explain WHY not WHAT
- No "WIP" commits on main — squash before merge

### PR Size
- Aim for < 400 lines changed per PR
- One logical change per PR
- Link to TASK-ID in PR description

### What Not to Do
- Never force push to main
- Never commit secrets, tokens, or credentials
- Never skip pre-commit hooks (`--no-verify`)

---

## API / Interface Design

### Request / Response Structure
- All responses: `{ "data": ..., "error": null, "meta": { "timestamp": ... } }`
- Errors: `{ "data": null, "error": { "code": "...", "message": "..." }, "meta": ... }`
- TODO: Define actual response envelope for this project

### Error Codes
- Use descriptive snake_case codes: `invalid_input`, `not_found`, `unauthorized`
- Always include a human-readable message alongside the code
- TODO: Define the full error code enum for this project

### Versioning
- TODO: Decide API versioning strategy (URL path, header, none)

---

## Agent Rules

### Must Do
- Memory agent runs after every completed pipeline — no exceptions
- Security agent is a hard gate — pipeline stops on BLOCKERS
- Coder agent writes unit tests before implementation (TDD)
- Reviewer agent must output `PASS` or `FIX_REQUIRED` — nothing else

### Must Not Do
- Sub-agents do not inherit full conversation history
- Sub-agents do not load all skill files — only the one relevant to their task
- Orchestrator does not write code directly
- No agent skips the memory step after a significant decision

### Convention Promotion
When reviewer or memory agent identifies a repeated pattern, flag it to the orchestrator as:
```
CONVENTION_CANDIDATE: [section] description of the convention
```
Orchestrator reviews and adds to this file if appropriate.

---

## Documentation

### What to Document
- Public APIs and their contracts
- Non-obvious design decisions (the WHY, not the WHAT)
- Setup and onboarding steps
- External service integrations

### What Not to Document
- Code that reads clearly on its own
- Trivial implementation details
- Temporary workarounds (fix them instead)

### Style
- Short sentences
- Active voice
- Examples over descriptions
- TODO: Define doc tooling (Sphinx, JSDoc, Godoc, etc.)
