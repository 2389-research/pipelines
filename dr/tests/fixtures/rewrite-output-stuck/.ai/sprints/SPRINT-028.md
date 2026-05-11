# Sprint 028 — Social & Fallback Authentication (Google, Apple, Email/Password)

## Scope
Add secondary and tertiary authentication methods on top of the session infrastructure built in Sprint 027. Implement Google sign-in and Apple sign-in (with mocked providers for testing) and email + password as a fallback. Each method creates or links a volunteer record and issues a JWT via the existing session module. This sprint focuses purely on the auth-provider layer — no cross-provider returning-user detection or staff roles.

## Non-goals
- No cross-provider returning-user detection (e.g., matching a Google email to an existing phone-only account) — deferred to Sprint 029
- No staff RBAC — deferred to Sprint 029
- No UI changes beyond auth endpoints
- No SMS flows
- No modifications to phone OTP or session infrastructure from Sprint 027

## Requirements
- **FR10**: Support Google sign-in and Apple sign-in as secondary authentication methods.
- **FR11**: Support email plus password as a tertiary fallback authentication method.

## Dependencies
- Sprint 027 — Phone OTP Authentication, Session Infrastructure & SMS Consent Gating

## Expected Artifacts
- `db/migrations/028_social_email_auth.sql` — Additional columns/tables for OAuth provider IDs and password hashes
- `src/auth/social_auth.js` — Google/Apple OAuth verification and volunteer linking
- `src/auth/email_password.js` — Email/password registration and login
- `tests/auth/social_auth.test.js` — Google and Apple auth integration tests (mocked providers)
- `tests/auth/email_password.test.js` — Email/password auth unit and integration tests

## DoD
- [ ] Google sign-in flow verifies an ID token (mocked provider), creates a new volunteer record or links to an existing one by email, and issues a session JWT
- [ ] Apple sign-in flow verifies an ID token (mocked provider), creates a new volunteer record or links to an existing one by email, and issues a session JWT
- [ ] Email + password registration creates a volunteer record with a securely hashed password and issues a session JWT
- [ ] Email + password login authenticates against stored credentials and issues a session JWT
- [ ] Email + password login links to an existing volunteer record when the email matches (no duplicate creation)
- [ ] All three new auth flows reuse the session infrastructure from Sprint 027 (JWT creation/validation)
- [ ] `make test` passes with Google, Apple, and email/password auth tests alongside existing phone OTP tests

## Validation
```bash
make build && make lint && make test
```
