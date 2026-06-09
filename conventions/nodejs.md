# Node.js Conventions Overlay

Merged into `CONVENTIONS.md` by `bootstrap.sh` when stack is Node.js or TypeScript.

---

## Code Style — Node.js / TypeScript

- **Language:** TypeScript; `"strict": true` in `tsconfig.json`
- **Formatter:** `prettier` (single quotes, 2-space indent, trailing commas)
- **Linter:** `eslint` with `@typescript-eslint`; zero warnings policy
- **Imports:** ES modules (`import`/`export`); no `require()` in new code
- **Null safety:** use optional chaining (`?.`) and nullish coalescing (`??`); avoid `!` non-null assertions

## Folder Structure — Node.js

```
src/
  index.ts
  routes/
  services/
  models/
  utils/
tests/
  *.test.ts             ← co-located or in __tests__/
package.json            ← exact version pinning
tsconfig.json
.prettierrc
.eslintrc.json
```

## Testing — Node.js

- **Runner:** `jest` or `vitest`
- **Coverage target:** 80% lines and branches; configured in `jest.config.ts`
- **Test naming:** `describe` + `it` style; `it('returns 404 when user not found')`
- **HTTP tests:** `supertest` for route testing; `msw` for mocking external APIs
- **No `setTimeout` in tests** — use `jest.useFakeTimers()` or event-based waiting

## Dependencies — Node.js

- Exact versions in `package.json` (no `^` or `~` ranges in production deps)
- Separate `devDependencies` strictly
- Run `npm audit` in CI; fail on high-severity issues
