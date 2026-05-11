# Sprint 004 Recovery Analysis — Authentication & Returning User Detection

## Root Cause Category
**Scope failure**

## Specific Failure Detail
Sprint 004 attempted to implement a comprehensive authentication system featuring four distinct providers (Phone OTP, Google OAuth, Apple OAuth, and Email/Password fallback) alongside session management (JWT), returning-user detection logic, SMS consent gating (TCPA compliance), and Staff RBAC middleware. 

This high volume of work, combined with the technical overhead of implementing these features in raw Node.js `http` without a framework, proved too large for a single execution cycle. The complexity led to a significant scope-fence breach during Sprint 003 (where the agent erroneously started implementing Sprint 004/005 artifacts) and ultimately a failed Sprint 004 attempt that produced no valid implementation artifacts.

## PlanManager Alignment
**Yes**, PlanManager's risk flags for Sprint 004 correctly predicted this failure. Specifically:
- **Risk #1**: "Complexity of implementing four auth flows... in raw `http` without Passport.js."
- **Risk #2**: "Session management logic... needs clear design."
- **Risk #4**: "Consent gating for SMS must be robustly stored."

The accumulation of these risks materialized as a scope failure.

## Recommendation: REDECOMPOSE
The sprint is too large and touches too many subsystems (DB, Auth Logic, API, Middleware, UI). It should be broken into smaller, more focused sprints to ensure successful delivery and validation.

**Proposed Split:**
- **004A: Primary Auth (Phone OTP) & Session Infra** — Focuses on the core "Opportunities First" flow, JWT session management, and SMS consent gating.
- **004B: Social & Fallback Authentication** — Adds Google/Apple OAuth (mocked) and Email/Password fallback.
- **004C: Returning User Detection & Staff RBAC** — Implements the logic for linking identity providers and the staff-facing authorization layer.
