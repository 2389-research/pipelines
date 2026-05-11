# Sprint 001 — Multi-Subsystem Sprint That Mixes Concerns

## Scope
Build authentication (phone+OTP, Google SSO, email+password), Stripe billing integration with subscription webhooks, daily and weekly reporting cron jobs, multi-channel notification dispatch (SMS, email, push, in-app), and an admin dashboard for inspecting all of the above — in one sprint.

## Non-goals
- (none specified)

## Requirements
- Auth across 3 mechanisms
- Stripe billing
- Reports
- Notifications
- Admin UI

## Dependencies
- None (first sprint)

## Expected Artifacts
- src/auth/
- src/billing/
- src/reports/
- src/notifications/
- src/admin/

## DoD
- 12 items spanning auth, billing, reports, notifications, admin

## Validation
- `npx vitest run` exits 0
