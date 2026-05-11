# Sprint 009 — SMS Orchestration Core (Transactional)

## Scope
Implement SMS infrastructure: provider integration (Twilio or equivalent), opt-in/opt-out management with TCPA compliance, and the core transactional message pipeline. Deliver signup confirmation, 24–48 hour pre-shift reminder (with orientation link if incomplete), and optional day-of arrival SMS.

## Non-goals
- No post-shift engagement messages, no impact cards, no open-opportunity alerts. No QR code delivery.

## Requirements
- **FR1**: The web and SMS interaction surfaces must share a single backend and volunteer record.
- **FR3**: Provide an SMS layer for confirmations, pre-shift reminders, post-shift impact messages, next-commitment prompts, and open-opportunity notifications.
- **FR39**: Send an immediate signup confirmation SMS after registration.
- **FR40**: Send a reminder 24-48 hours before the shift with logistics and a link to video orientation if not completed.
- **FR41**: Support an optional day-of arrival-information SMS with directions and entry instructions.
- **FR45**: Require opt-in for all outbound SMS and comply with TCPA/messaging regulations.

## Dependencies
- Sprint 004 — Authentication & Returning User Detection
- Sprint 005 — Volunteer Registration, Profile & Website-Embedded UI Shell

## Expected Artifacts
- `src/sms/provider.*` — SMS provider integration (Twilio adapter + test double)
- `src/sms/opt_in.*` — Opt-in/opt-out management
- `src/sms/templates/confirmation.*` — Signup confirmation template
- `src/sms/templates/reminder.*` — Pre-shift reminder template
- `src/sms/templates/day_of.*` — Day-of arrival template
- `src/sms/scheduler.*` — Timed message scheduler
- `src/api/sms_preferences.*` — Opt-in preferences endpoint
- `tests/sms/` — SMS unit and integration tests

## DoD
- [ ] SMS provider integration sends a test message via adapter (integration test with fake provider)
- [ ] Opt-in status is tracked per-volunteer; outbound messages blocked for opted-out volunteers (unit test)
- [ ] Signup confirmation SMS fires immediately after successful registration
- [ ] Pre-shift reminder SMS is scheduled 24–48 hours before shift and includes orientation link when orientation is incomplete
- [ ] Day-of arrival SMS sends logistics info when configured for the shift (toggleable)
- [ ] All outbound SMS includes opt-out instructions per TCPA compliance
- [ ] Web-created volunteer record and SMS-referenced record are the same record (integration test verifying FR1 shared backend)
- [ ] `make test` passes

## Validation
```bash
make test
```
