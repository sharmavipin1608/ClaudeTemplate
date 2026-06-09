# Node.js Stack Overlay

Appended to agent definitions by `bootstrap.sh` when stack is Node.js or TypeScript. Extends base agent rules with Node-specific commands and patterns.

---

## Coder — Node.js additions

- **Language:** TypeScript preferred; strict mode (`"strict": true` in tsconfig)
- **Formatter:** `prettier --write .` before committing; config in `.prettierrc`
- **Tests:** use `jest` or `vitest`; test files as `*.test.ts` co-located or in `__tests__/`
- **TDD command:** `npx jest path/to/file.test.ts --watch` or `npx vitest run`
- **Imports:** use ES module imports (`import`/`export`); no `require()` in new code
- **Dependency pinning:** use exact versions in `package.json` (`"dep": "1.2.3"` not `"^1.2.3"`) for reproducibility

## Tester — Node.js additions

- **Test runner:** `npx jest --coverage` or `npx vitest run --coverage`
- **Coverage threshold:** 80% lines/branches; configure in `jest.config.ts` or `vitest.config.ts`
- **HTTP testing:** use `supertest` for Express/Fastify; `msw` for mocking external HTTP calls
- **Async tests:** always `await` async operations; use `jest.useFakeTimers()` for timer-dependent code
- **Module mocking:** use `jest.mock()` at module level; prefer dependency injection over module-level mocks

## Security — Node.js additions

- Check for prototype pollution: `obj[userInput] = value` where `userInput` could be `__proto__`
- Check for `eval()`, `Function()`, `new Function()` with dynamic strings
- Check for `child_process.exec()` with user-controlled input → command injection; prefer `execFile()`
- Check for XSS: unsanitised user input in HTML responses; ensure `helmet` middleware is present
- Check for path traversal: `path.join(baseDir, userInput)` without `path.resolve()` + prefix check
- Check `package.json` dependencies for known CVEs via `npm audit`
- Check for hardcoded secrets (API keys, JWTs, passwords) in source files
