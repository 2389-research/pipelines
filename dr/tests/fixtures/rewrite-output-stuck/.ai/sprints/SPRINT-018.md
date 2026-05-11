# Sprint 018 — RE NXT Integration & Donor Matching

## Scope
Implement Raiser's Edge NXT integration: record matching on signup/login using email and phone, auto-linking at ≥90% confidence, donor status tagging on volunteer record, and donor acknowledgement personalization in the conversational flow. Implement the staff-facing exception report for sub-90% matches with confirm/reject/merge actions.

## Non-goals
- No outbound activity sync to RE NXT (Sprint 019). No batch export fallback (Sprint 019).

## Requirements
- **FR64**: Support real-time or near-real-time record linking between the volunteer platform and Raiser's Edge NXT.
- **FR65**: Recognize known donors during the volunteer flow and sync volunteer activity to RE NXT automatically.
- **FR66**: Use email address and cell phone number as the record-matching fields.
- **FR67**: Query RE NXT on signup or login and auto-link records when the match confidence is at least 90%.
- **FR68**: Tag linked volunteer records with donor status, giving level, and corporate affiliation when applicable.
- **FR69**: Personalize the conversational flow with donor acknowledgement when an early RE NXT match is found.
- **FR71**: Surface sub-90% potential matches in a staff-facing exception report.
- **FR72**: Show volunteer details, candidate RE NXT matches, confidence score/reason, and actions to confirm, reject, or merge manually.

## Dependencies
- Sprint 004 — Authentication & Returning User Detection
- Sprint 005 — Volunteer Registration, Profile & Website-Embedded UI Shell
- Sprint 026 — Nonlinear & Adaptive Conversational Logic (replaces Sprint 006)

## Expected Artifacts
- `src/integrations/renxt/client.*` — RE NXT API client
- `src/integrations/renxt/matcher.*` — Record matching logic (email, phone, confidence scoring)
- `src/services/donor_personalization.*` — Donor acknowledgement in conversational flow
- `src/ui/staff/ExceptionReport.*` — Staff exception report UI
- `src/api/renxt.*` — RE NXT match and exception endpoints
- `tests/integrations/renxt/matcher.test.*`
- `tests/services/donor_personalization.test.*`

## DoD
- [ ] On signup/login, system queries RE NXT for matching records by email and phone (integration test with mocked RE NXT)
- [ ] Records with ≥90% confidence are auto-linked; <90% are not (unit test with at least 5 match/no-match scenarios)
- [ ] Linked volunteer records are tagged with donor status, giving level, and corporate affiliation
- [ ] Conversational flow displays donor acknowledgement greeting when an early match is found (integration test verifying the UI message appears)
- [ ] Sub-90% matches surface in staff exception report with confidence scores, reasons, and candidate details
- [ ] Staff can confirm, reject, or merge exception matches via the UI with audit logging
- [ ] `make test` passes

## Validation
```bash
make test
```
