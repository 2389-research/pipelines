# Sprint 007 — Digital Waiver Management

## Scope
Implement the digital waiver system: in-flow presentation within the conversational UI after shift selection and before confirmation, click-to-sign e-signature with timestamp, attachment to volunteer record, and completion status tracking. Returning volunteers with a completed waiver are not re-prompted.

## Non-goals
- No group waiver handling. No check-in waiver validation. No orientation.

## Requirements
- **FR16**: Do not remind returning volunteers to complete a waiver if their waiver is already completed.
- **FR32**: Present the waiver as an online clickable e-sign in the conversational flow rather than PDF or paper.
- **FR33**: Present the digital waiver during registration after shift selection and before confirmation.
- **FR34**: Support click-to-sign with timestamp and attachment of the signed waiver to the volunteer record.
- **FR35**: Store waiver completion status on the volunteer record and validate it at check-in, prompting on-site completion if incomplete.

## Dependencies
- Sprint 005 — Volunteer Registration, Profile & Website-Embedded UI Shell

## Expected Artifacts
- `db/migrations/007_waivers.*` — Waiver table
- `src/models/waiver.*` — Waiver model (content, signature, timestamp)
- `src/ui/waiver/WaiverPresentation.*` — Waiver display in conversational flow
- `src/ui/waiver/ESignCapture.*` — Click-to-sign component
- `src/api/waivers.*` — Waiver signing and status endpoints
- `src/services/waiver.*` — Waiver validation logic
- `tests/api/waivers.test.*`
- `tests/services/waiver.test.*`

## DoD
- [ ] Waiver content renders within the conversational UI flow after shift selection
- [ ] Click-to-sign captures volunteer consent with timestamp and content hash, attached to volunteer record
- [ ] Waiver completion status is queryable per-volunteer via API
- [ ] Returning volunteer with completed waiver is not prompted to sign again (automated test)
- [ ] Unsigned waiver status returns "incomplete"; signed returns "complete" with timestamp
- [ ] Waiver is presented before shift registration confirmation (ordering enforced in flow)
- [ ] `make test` passes with waiver unit and integration tests

## Validation
```bash
make test
```
