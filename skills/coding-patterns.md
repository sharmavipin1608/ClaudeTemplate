## Role Profile

**Agent:** Coder
**Your input contract:** Task description, `memory/scratchpad.md` (current working context), `CONVENTIONS.md` (coding standards), this skill file
**Read list (in order):**
1. This skill file
2. `CONVENTIONS.md`
3. `memory/scratchpad.md`
**Your output contract:** Implementation code + unit tests; a brief summary (what was built, what tests cover, any decisions made); JSON envelope with `verdict: "DONE"` and `next_agent: "reviewer"`
**Gates owned:** none

---

# Coding Patterns

Generic patterns for any language or stack. Supplement with stack-specific conventions in `CONVENTIONS.md`.

## Naming
- Names reveal intent. If you need a comment to explain a name, rename it.
- Functions: verb phrases (`getUserById`, `calculate_total`, `fetchConfig`)
- Booleans: `is`, `has`, `can`, `should` prefix (`isActive`, `hasPermission`)
- Collections: plural nouns (`users`, `items`, `errors`)
- Constants: SCREAMING_SNAKE_CASE

## Functions
- One function, one responsibility. If "and" appears in the description, split it.
- Under 20 lines as a soft limit — if longer, it's probably doing too much
- Pure functions preferred: same input → same output, no side effects
- Use early returns and guard clauses to avoid deep nesting

## Error Handling
- Validate at system boundaries (user input, external APIs, file I/O)
- Trust internal code — no defensive checks inside already-validated flows
- Error messages: what went wrong + what to do about it
- Never silently swallow exceptions

## Dependencies
- Inject dependencies — don't instantiate them inside functions you want to test
- Depend on abstractions, not concrete implementations

## YAGNI
- No abstractions until you have 3+ concrete cases
- No configuration for things that don't vary yet
- No design for hypothetical future requirements
- Three similar lines is better than a premature abstraction

## Input Liveness
- Every declared input — function parameter, constructor argument, CLI flag, config key, environment variable — must be **read on at least one reachable code path** in the same change. If you add `timeout_ms` to a signature, some branch of the function must actually use it. Dead inputs lie to the caller about what the function does; they also bypass type checkers because the parameter is technically referenced in the signature.
- When a declared input is intentionally reserved for a future change, mark it with an explicit `_` prefix (`_timeout_ms`) or a `# reserved: <ticket>` comment so the next reader knows it is wired but inert.
- The Reviewer rejects a diff that adds an input read on zero branches.

## No Import-Time Side Effects in Library Modules
- A library module — anything imported by another module rather than executed as `__main__` — must perform no I/O, no network calls, no subprocess spawning, no global state mutation, and no logger configuration at import time.
- Acceptable at import time: function/class definitions, plain constant assignments from literals or `os.environ.get(...)` with a default, type aliases, and decorator application that does not itself perform I/O.
- Not acceptable at import time: opening files, reading config files, building HTTP/SDK/database clients, calling `logging.basicConfig`, registering signal handlers, mutating shared state on another module, or any code path that can raise on a misconfiguration.
- The pragmatic test: can this module be imported inside a unit test with no network, no filesystem outside the package directory, and no environment variables set? If not, the import-time work must move into a factory function or a `main()` entry point.
