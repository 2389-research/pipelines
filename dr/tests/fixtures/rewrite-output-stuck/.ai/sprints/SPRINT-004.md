# Sprint 004 — Authentication & Returning User Detection

## Scope
Implement the multi-method authentication system: phone + SMS verification code (primary), Google sign-in, Apple sign-in, and email + password fallback. Implement returning-user detection that gracefully recognizes existing accounts by phone or email without a create-vs-login fork. Auth is triggered only after a visitor selects a shift (deferred login per FR8). Also establish staff authentication and role-based access control for future staff dashboard sprints.

## Non-goals
- No registration data collection beyond identity. No conversational UI. No waiver or orientation.

## Requirements
- **FR8**: Delay login/account creation until after a visitor selects a shift of interest.
- **FR9**: Support phone number plus SMS verification code as the primary authentication method, with no password.
- **FR10**: Support Google sign-in and Apple sign-in as secondary authentication methods.
- **FR11**: Support email plus password as a tertiary fallback authentication method.
- **FR12**: Detect returning users from existing phone numbers or email addresses and handle sign-in gracefully without a separate create-account vs. login fork.
- **FR45**: Require opt-in for all outbound SMS and comply with TCPA/messaging regulations.

## Dependencies
- Sprint 003 — Shared Backend, Data Model & Anonymous Opportunity Browsing

## Expected Artifacts
- `src/auth/phone_verification.*` — Phone + SMS OTP auth
- `src/auth/social_auth.*` — Google/Apple OAuth
- `src/auth/email_password.*` — Email + password fallback
- `src/auth/returning_user.*` — Returning user detection logic
- `src/auth/roles.*` — Staff role definitions and RBAC middleware
- `src/middleware/auth.*` — Auth middleware (volunteer + staff)
- `tests/auth/` — Auth unit and integration tests

## DoD
- [ ] Phone + SMS OTP flow creates a session for a new user and recognizes/signs in an existing user by phone
- [ ] Google sign-in flow creates or links a volunteer record (integration test with mocked provider)
- [ ] Apple sign-in flow creates or links a volunteer record (integration test with mocked provider)
- [ ] Email + password fallback creates and authenticates a user, linking to existing records when email matches
- [ ] Returning user detection: entering an existing phone or email triggers sign-in, not duplicate account creation
- [ ] Auth is triggered only after shift selection — unauthenticated user can browse opportunities and is prompted to authenticate only upon selecting a specific shift (integration test)
- [ ] Staff RBAC middleware protects a test staff route — unauthenticated and non-staff users receive 403
- [ ] SMS opt-in is captured and stored before any non-transactional outbound SMS (unit test on consent gating)
- [ ] `make test` passes with all auth tests (OTP, OAuth, email/password, returning user, staff RBAC)

## Validation
```bash
make test
```
