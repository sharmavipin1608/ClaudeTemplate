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
