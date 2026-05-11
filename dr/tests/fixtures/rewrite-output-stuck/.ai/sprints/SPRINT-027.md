# Sprint 027 — Phone OTP Authentication, Session Infrastructure & SMS Consent Gating

## Scope
Implement the primary authentication method: phone number + SMS verification code (OTP). Build the session infrastructure (JWT creation, validation, refresh, middleware) that all subsequent auth providers will share. Implement SMS consent gating to ensure TCPA compliance before any non-transactional outbound SMS is sent. This sprint establishes the foundational auth layer that social and fallback auth providers (Sprint 028) will plug into.

## Non-goals
- No Google/Apple OAuth — deferred to Sprint 028
- No email + password fallback — deferred to Sprint 028
- No returning-user detection across different identity providers (cross-provider linking) — deferred to Sprint 029
- No staff RBAC — deferred to Sprint 029
- No conversational UI changes
- No registration data collection beyond identity

## Requirements
- **FR9**: Support phone number plus SMS verification code as the primary authentication method, with no password.
- **FR45**: Require opt-in for all outbound SMS and comply with TCPA/messaging regulations.

## Dependencies
- Sprint 003 — Shared Backend, Data Model & Anonymous Opportunity Browsing

## Expected Artifacts
- `db/migrations/027_auth_sessions.sql` — auth_identities, sessions, sms_consent tables
- `src/auth/phone_verification.js` — Phone + SMS OTP request/verify logic
- `src/auth/session.js` — JWT session creation, validation, and refresh
- `src/auth/sms_consent.js` — SMS opt-in consent capture and gating logic
- `src/middleware/auth.js` — Auth middleware for protected routes
- `tests/auth/phone_verification.test.js` — Phone OTP unit/integration tests
- `tests/auth/session.test.js` — Session management tests
- `tests/auth/sms_consent.test.js` — SMS consent gating tests

## DoD
- [ ] Database migration adds auth-related tables (auth_identities, sessions, sms_consent) with appropriate constraints
- [ ] Phone OTP request endpoint accepts a phone number, generates a verification code, and stores it with TTL
- [ ] Phone OTP verify endpoint validates the code and creates a session (JWT) for a new user
- [ ] Phone OTP verify endpoint recognizes an existing phone number and signs in without creating a duplicate volunteer record
- [ ] Auth middleware extracts and validates JWT from request, attaching volunteer identity to the request context
- [ ] Unauthenticated requests to protected endpoints receive 401; valid sessions pass through
- [ ] SMS opt-in consent is captured and stored before any non-transactional outbound SMS (unit test on consent gating)
- [ ] `make test` passes with all phone OTP, session, and SMS consent tests

## Validation
```bash
make build && make lint && make test
```
