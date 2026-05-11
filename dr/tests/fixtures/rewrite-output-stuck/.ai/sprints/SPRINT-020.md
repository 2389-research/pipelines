# Sprint 020 — Skills-Based Volunteer Intake

## Scope
Implement the skills-based volunteer application flow: interest capture, resume/file upload, availability and skills capture, acknowledgement with response-time expectation, and queueing for human review. Surface pending applications with time-since-submission aging to staff.

## Non-goals
- No court-required or SNAP flows. No general reporting.

## Requirements
- **FR28**: Provide a skills-based volunteer application flow with interest capture, resume upload, availability/skills capture, acknowledgement, response-time expectation, and queueing for human review.
- **FR29**: Surface pending skills-based applications and time-since-submission to staff.

## Dependencies
- Sprint 005 — Volunteer Registration, Profile & Website-Embedded UI Shell
- Sprint 017 — Staff Operations Dashboard (Run of Show & Weekly Planning)

## Expected Artifacts
- `src/api/skills_intake.*` — Skills-based application endpoint
- `src/models/skills_application.*` — Application model with resume storage
- `src/ui/volunteer/SkillsApplication.*` — Skills application form
- `src/ui/staff/SkillsQueue.*` — Staff queue with aging visibility
- `tests/api/skills_intake.test.*`

## DoD
- [ ] Skills-based application captures interest, resume upload, availability, and skills (integration test with file upload)
- [ ] Application confirmation shows acknowledgement with response-time expectation message
- [ ] Staff queue lists pending applications sorted by oldest first with time-since-submission
- [ ] Staff can view application details including resume download
- [ ] Staff routes are access-controlled (authorization test)
- [ ] `make test` passes

## Validation
```bash
make test
```
