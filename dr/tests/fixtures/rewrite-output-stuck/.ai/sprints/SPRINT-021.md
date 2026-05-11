# Sprint 021 — Court-Required & SNAP Volunteer Programs

## Scope
Implement court-required volunteer flow (identify, collect required hours/documentation/supervising entity, route to designated staff member) and SNAP-benefit volunteer flow (flag, track hours, documentation export). Generate hours-verification printouts with print-friendly formatting for both programs.

## Non-goals
- No changes to auto-assignment. No general reporting dashboard.

## Requirements
- **FR30**: Identify court-required volunteers, collect required hours/documentation/supervising entity, route them to the designated staff member, and support verified-hours printing/export.
- **FR31**: Flag SNAP-benefit volunteers, track their hours, and support documentation/export for benefit compliance.
- **FR83**: Support hours-verification printouts for court-required and SNAP-benefit volunteers.

## Dependencies
- Sprint 005 — Volunteer Registration, Profile & Website-Embedded UI Shell
- Sprint 017 — Staff Operations Dashboard (Run of Show & Weekly Planning)

## Expected Artifacts
- `src/api/court_snap.*` — Court-required and SNAP endpoints
- `src/models/court_program.*` — Court/SNAP tracking model
- `src/models/snap_program.*` — SNAP tracking model
- `src/ui/volunteer/CourtIntake.*` — Court-required intake form
- `src/ui/volunteer/SnapIntake.*` — SNAP intake form
- `src/services/hours_verification.*` — Printable hours verification generator
- `src/ui/staff/CourtSnapManagement.*` — Staff management view
- `tests/api/court_snap.test.*`
- `tests/services/hours_verification.test.*`

## DoD
- [ ] Court-required volunteer flow captures required hours, documentation needs, and supervising entity
- [ ] Court-required volunteers are routed to designated staff member (notification or filtered staff view — test verifies routing)
- [ ] SNAP-benefit volunteers are flagged with hours tracked for compliance documentation
- [ ] Hours-verification printout generates with print-friendly CSS/formatting for both court and SNAP volunteers (golden-file test)
- [ ] Printout includes volunteer name, hours, date range, and NIFB branding
- [ ] `make test` passes

## Validation
```bash
make test
```
