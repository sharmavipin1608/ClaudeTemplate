# Reliability Patterns — Node.js / TypeScript Overlay

Supplements `reliability-patterns.md` with Node.js and TypeScript-specific syntax checks. Apply in addition to the base checklist, never instead of it.

---

## Node.js-Specific Checks

Apply each item to every function or block in the diff where the condition matches.

**N1 — Unhandled Promise rejection**
An `async` function call or `.then()` chain that is neither inside a `try/catch` block in the immediate calling scope nor followed by `.catch()` → flag as violation of Pattern #2. This includes top-level `async` IIFE bodies and event handler callbacks that are `async` without a wrapping try/catch.

**N2 — Empty catch**
A `.catch(() => {})`, `.catch(_ => {})`, `.catch(function() {})`, or `catch (e) {}` block with no log call and no rethrow → flag as violations of Patterns #3 and #4. An empty handler makes the rejection/exception disappear silently.

**N3 — Exception not logged**
A catch block (try/catch or `.catch(handler)`) whose handler body contains neither `console.error`, `console.warn`, `logger.error`, `logger.warn`, nor an explicit `throw` or `Promise.reject` → flag as violation of Pattern #3. The error must be observable to an operator.

**N4 — Unchecked synchronous I/O**
A call to `fs.readFileSync`, `fs.writeFileSync`, `fs.unlinkSync`, `fs.mkdirSync`, `fs.appendFileSync`, or `JSON.parse` that is not directly wrapped in a try/catch block (or inside a function whose entire body is a try/catch) and no JSDoc documents that the caller is expected to handle the exception → flag as violation of Pattern #4. These throw synchronously on failure and will crash the process if uncaught.

**N5 — null/undefined as error signal**
A function that returns `null` or `undefined` on error (including TypeScript return types `T | null` or `T | undefined`) where any call site in the diff uses the result without a null-check (`if (!result)`, `if (result === null)`, `result?.`) → flag as violation of Pattern #1.

**N6 — Module-level client singleton**
A top-level (module scope) statement that constructs a stateful network or SDK client — e.g., `const client = new Anthropic()`, `const openai = new OpenAI()`, `const redis = new Redis()`, `const pool = new Pool()`, `const db = knex(config)`, `const axiosInstance = axios.create()` — evaluated at `import`/`require` time. This binds the configuration captured at module load for the life of the process and forces network setup during test collection. Flag as a violation of Pattern #6. Construction must move into a factory function, a dependency-injection container, or a framework lifecycle hook (e.g., `onModuleInit`). Module-level constants that only read credentials from `process.env` are acceptable; instantiated clients are not.

**N7 — Caret/tilde dependency pinning**
Any new line added to `package.json` `dependencies` or `devDependencies` that uses a `^` (caret) or `~` (tilde) prefix for a third-party package instead of an exact version string (`"dep": "1.2.3"`) or an explicit bounded range (`">=1.2.0 <2.0.0"`) → flag. Semver-range pins allow silent breakage: a patch release that introduces a regression will be pulled on the next `npm install` without any indication in the diff. Require an exact pin or an explicit upper bound before approving.

**N8 — Sanitized exception messages on network/HTTP errors**
Any log call — `console.error(...)`, `logger.error(...)`, `logger.warn(...)` — inside a `.catch()` handler or `catch` block whose caught type is a network or SDK error (`AxiosError`, `fetch` rejection, response from `got`, `undici`, or OpenAI/Anthropic SDK), and which logs `e.message`, `e.stack`, `error.response?.data`, `error.config`, `error.config?.headers`, or `JSON.stringify(error)` directly without redaction. HTTP client errors routinely echo back request headers (including `Authorization`) and request bodies. Flag as a violation; require either a fixed message naming only the operation plus the error type, or a redaction helper that strips credential fields before logging.

**N9 — `any` cast in catch block**
Inside a `catch` block, a type assertion `(e as any).property` or `(error as any).property` used to access error properties instead of an `instanceof` check or the standard `e instanceof Error ? e.message : String(e)` pattern → flag. TypeScript makes caught values `unknown` by design; casting to `any` bypasses this protection and can hide property-access errors at runtime if the thrown value is not an `Error` instance.
