# Sprint 029 — Returning User Detection, Deferred Auth & Staff RBAC

## Scope
Implement the cross-provider returning-user detection logic that links identities across phone, Google, Apple, and email auth methods to the same volunteer record — ensuring no duplicate accounts are created. Implement the deferred-login flow where unauthenticated users can browse opportunities and are prompted to authenticate only when they select a specific shift (FR8). Establish staff roles and RBAC middleware to protect future staff dashboard endpoints. This sprint completes the full scope of the original Sprint 004 (Authentication & Returning User Detection).

## Non-goals
- No modifications to individual auth providers from Sprints 027/028
- No conversational UI
- No SMS orchestration
- No registration data collection beyond identity linking
- No volunteer-facing dashboard features

## Requirements
- **FR8**: Delay login/account creation until after a visitor selects a shift of interest.
- **FR12**: Detect returning users from existing phone numbers or email addresses and handle sign-in gracefully without a separate create-account vs. login fork.
- **Staff RBAC**: Role-based access control for staff dashboard routes (prerequisite for Sprints 013, 017, 020, 021).

## Dependencies
- Sprint 028 — Social & Fallback Authentication (Google, Apple, Email/Password)

## Expected Artifacts
- `db/migrations/029_roles_deferred_auth.sql` — Roles table, identity linking indexes
- `src/auth/returning_user.js` — Cross-provider identity resolution and linking
- `src/auth/roles.js` — Staff role definitions and assignment
- `src/middleware/rbac.js` — Role-based access control middleware
- `tests/auth/returning_user.test.js` — Cross-provider identity linking tests
- `tests/auth/roles.test.js` — Staff role and RBAC middleware tests
- `tests/auth/deferred_auth.test.js` — Deferred login flow integration tests

## DoD
- [ ] Returning user detection: entering an existing phone number or email triggers sign-in, not duplicate account creation, across all auth providers
- [ ] Cross-provider identity linking: a user who signed up by phone can later sign in via Google (matching email) and both identities resolve to the same volunteer record
- [ ] Auth is triggered only after shift selection — unauthenticated user can browse opportunities and is prompted to authenticate only upon selecting a specific shift (integration test)
- [ ] Staff RBAC: roles table and middleware protect staff routes — unauthenticated and non-staff users receive 403
- [ ] Staff role can be assigned to a volunteer record and verified by RBAC middleware
- [ ] All existing auth tests (phone OTP, Google, Apple, email/password) continue to pass
- [ ] `make test` passes with returning-user detection, deferred auth, and staff RBAC tests

## Validation
```bash
make build && make lint && make test
```
