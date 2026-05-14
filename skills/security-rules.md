# Security Rules

## Injection
- Never concatenate user input into SQL, shell commands, HTML, or file paths
- Use parameterized queries / prepared statements for all database access
- Validate and sanitize all user input at system boundaries
- Escape output for its rendering context (HTML entity encoding, shell quoting)

## Authentication & Authorization
- Never implement custom crypto or auth — use established, audited libraries
- Hash passwords with bcrypt, argon2, or scrypt — never MD5 or SHA1 alone
- Check authorization on every request — a logged-in user is not automatically authorized for everything
- Invalidate tokens/sessions on logout and password change

## Secrets
- No hardcoded secrets, API keys, or credentials in source code — ever
- Never commit `.env` files
- Use environment variables or a secrets manager
- Rotate secrets regularly; short lifetimes are better than long ones

## Input Validation
- Validate type, format, length, and allowed range for every input
- Reject unknown fields — do not pass them through silently
- Server-side validation is authoritative — never trust client-side validation alone

## Security Checklist (run on every diff)
- [ ] SQL injection: all queries use parameterized statements
- [ ] Command injection: no user input passed to shell commands
- [ ] Path traversal: file paths validated and sandboxed
- [ ] XSS: user content escaped before rendering in HTML
- [ ] CSRF: state-changing requests protected (if using cookie auth)
- [ ] Exposed secrets: no credentials, tokens, or keys in code or logs
- [ ] Exposed error detail: no stack traces or internal paths in API responses
- [ ] Missing auth checks: every endpoint checks authentication and authorization
- [ ] Insecure direct object references: access to resources checked by ownership/permission
- [ ] Mass assignment: only explicitly allowed fields accepted from user input
- [ ] Missing rate limiting: auth endpoints have rate limits
