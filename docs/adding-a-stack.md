# Adding Support for a New Technology Stack

ClaudeTemplate ships with built-in support for Python, Node.js/TypeScript, and Java. This document explains exactly what to create and change to add full support for another stack (Go, Ruby, Rust, etc.).

There are four layers to a stack: what the Reviewer checks at runtime, what the Coder/Tester/Security agents know at runtime, what CONVENTIONS.md says to humans, and what bootstrap.sh does at setup time. All four need to match.

---

## What "full support" means

| Layer | File | Used by | When |
|---|---|---|---|
| Reviewer overlay | `skills/overlays/reliability-<stack>.md` | Reviewer agent | Every code review |
| Agent overlay | `agents/overlays/<stack>.md` | Coder, Tester, Security agents (merged at bootstrap) | Every task after bootstrap |
| Conventions overlay | `conventions/<stack>.md` | Developers reading CONVENTIONS.md (merged at bootstrap) | Project lifetime |
| Bootstrap detection | `bootstrap.sh` Step 3b | `bootstrap.sh` wizard | Once, at project setup |

---

## Step 1 — Create the Reviewer overlay

**File:** `skills/overlays/reliability-<stack>.md`

This supplements `skills/reliability-patterns.md` with syntax-level checks the Reviewer applies to every diff. Keep items tightly scoped — each rule should be detectable from reading the diff alone, without running the code.

Structure to follow (use the existing Python and Java overlays as templates):

```markdown
# Reliability Patterns — <Stack> Overlay

Supplements `reliability-patterns.md` with <stack>-specific syntax checks. Apply in addition to the base checklist, never instead of it.

---

## <Stack>-Specific Checks

Apply each item to every function or block in the diff where the condition matches.

**X1 — <Short name>**
<Condition to look for in the diff> → flag as violation of Pattern #<N from reliability-patterns.md>.

**X2 — ...**
```

Number checks sequentially (X1, X2, … where X is the stack prefix, e.g. G for Go, R for Ruby). Each check must name which base pattern it is a violation of — never invent new base patterns here.

Add the new overlay to the Reviewer routing table in `CLAUDE.md`:

```
Stack contains <keywords>   → skills/overlays/reliability-<stack>.md
```

---

## Step 2 — Create the agent overlay

**File:** `agents/overlays/<stack>.md`

This is merged at bootstrap time into `agents/coder.md`, `agents/tester.md`, and `agents/security.md`. It tells each agent the stack-specific commands and patterns to use.

Structure to follow:

```markdown
# <Stack> Stack Overlay

Appended to agent definitions by `bootstrap.sh` when stack is <stack>. Extends base agent rules with <stack>-specific commands and patterns.

---

## Coder — <Stack> additions

- **Build/run command:** ...
- **Formatter:** ...
- **Type safety rules:** ...
- **Tests:** framework, file layout, TDD command
- **Imports:** conventions
- **Dependency pinning:** how to pin

## Tester — <Stack> additions

- **Test runner command:** ...
- **Coverage:** tool, threshold, enforcement flag
- **Isolation:** how to isolate filesystem/network/time in tests
- **HTTP testing:** recommended library
- **Common patterns:** ...

## Security — <Stack> additions

- Check for <injection vector 1> ...
- Check for <injection vector 2> ...
- Check for hardcoded secrets ...
- Check dependencies for CVEs via <tool> ...
```

Cover all three sections. The Security section is the most important — it is the agent's checklist before every commit.

---

## Step 3 — Create the conventions overlay

**File:** `conventions/<stack>.md`

This is merged at bootstrap time into `CONVENTIONS.md`. It is the human-readable version of the same information — coding standards for developers, not agent instructions.

Structure to follow:

```markdown
# <Stack> Conventions Overlay

Merged into `CONVENTIONS.md` by `bootstrap.sh` when stack is <stack>.

---

## Code Style — <Stack>

- **Formatter:** ...
- **Linter:** ...
- **Naming conventions:** ...
- **Import rules:** ...

## Folder Structure — <Stack>

\`\`\`
src/
  ...
tests/
  ...
\`\`\`

## Testing — <Stack>

- **Runner:** ...
- **Coverage target:** ...
- **Test naming:** ...
- **Fixtures/mocking:** ...

## Dependencies — <Stack>

- Pinning strategy: ...
- CVE scanning: ...
```

---

## Step 4 — Add detection to bootstrap.sh

**File:** `bootstrap.sh`, Step 3b block.

Add a new `elif` branch to the auto-detection chain:

```bash
elif echo "$TECH_LOWER" | grep -qiE "<keyword1>|<keyword2>|<keyword3>"; then
  STACK_KEY="<stack>"
```

Choose keywords that match what a user would naturally type as their tech stack (e.g. for Go: `go|golang`). Place the branch after the existing ones.

Also update the manual-selection prompt to include the new stack name:

```bash
prompt "  Apply stack overlay? Options: python, nodejs, java, <stack>, none [none]: "
```

---

## Step 5 — Update README.md

Add a row to the "Stack support" table in `README.md`:

```markdown
| <Stack> | <bootstrap auto-detect keywords> | Full |
```

---

## Checklist

- [ ] `skills/overlays/reliability-<stack>.md` — Reviewer runtime checks
- [ ] Reviewer routing entry added to `CLAUDE.md` Skills section
- [ ] `agents/overlays/<stack>.md` — Coder/Tester/Security agent additions
- [ ] `conventions/<stack>.md` — human coding standards
- [ ] `bootstrap.sh` auto-detection `elif` branch added
- [ ] `bootstrap.sh` manual-selection prompt text updated
- [ ] `README.md` stack support table updated

All five files plus two bootstrap.sh changes. That is the complete surface area for adding a new stack.

---

## Example: adding Go support

To illustrate the scope, here is what a Go addition would touch:

- `skills/overlays/reliability-go.md` — checks for unchecked errors (`if err != nil` missing), nil pointer dereference risks, goroutine leak patterns
- `agents/overlays/go.md` — `go fmt`, `golangci-lint`, `go test ./...`, `-race` flag, `httptest` package, `govulncheck` for CVEs
- `conventions/go.md` — standard Go project layout (`cmd/`, `internal/`, `pkg/`), table-driven tests, error wrapping with `%w`
- `bootstrap.sh` — detect `go|golang`
- `README.md` — add Go row to stack support table
