## Role Profile

**Agent:** Git
**Your input contract:** Diff to commit, this skill file, git section of `CONVENTIONS.md`
**Read list (in order):**
1. This skill file
2. `CONVENTIONS.md` (git section)
**Your output contract:** A commit following the project's message convention, pushed to the remote branch; JSON envelope with `verdict: "COMMITTED"` or `verdict: "PUSH_FAILED"`; on COMMITTED includes sha, branch, and message; on PUSH_FAILED includes error and null sha; `next_agent: "memory"` on COMMITTED, `next_agent: null` on PUSH_FAILED
**Gates owned:** none (PUSH_FAILED stops the pipeline but is not a security gate — it is an infrastructure failure)

---

# Git Commit Conventions

## Format
```
<type>(<scope>): <short description>

[optional body — explain WHY, not what]

[optional footer — breaking changes, issue refs]
```

## Types
- `feat`: new user-facing feature
- `fix`: bug fix
- `refactor`: code change with no feature or fix
- `test`: adding or updating tests only
- `docs`: documentation only
- `chore`: build, tooling, config, dependencies
- `perf`: performance improvement

## Rules
- Subject: imperative mood, max 72 chars, no period
  - `feat: add JWT refresh token rotation` ✓
  - `added JWT refresh token` ✗
- Body: explain WHY — the diff shows what
- One logical change per commit
- Every commit must leave tests passing
- Never commit secrets, `.env` files, or credentials

## Atomic Commits
- One commit = one thing
- "Add feature X and fix bug Y" → two commits
- If you need "and" to describe it, split it

## Examples
```
feat(auth): add JWT refresh token rotation

Tokens were single-use with no refresh path, forcing re-login every hour.
This adds automatic rotation on each authenticated request.
```

```
fix(api): return 422 instead of 500 for invalid email input
```

```
chore: upgrade postgres driver to 3.2.0
```
