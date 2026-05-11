# Sprint 017 — Staff Operations Dashboard (Run of Show & Weekly Planning)

## Scope
Build the daily run-of-show view (all shifts across centers, attendees, assignments, flags, staff assignments, timeline) and the one-week planning view (registrations, staffing status, assignment completion, attention-needed flags). Each staff member sees their relevant operational slice; operations staff sees the full picture. Add CSV export for operational datasets.

## Non-goals
- No RE NXT exception reports. No skills queue. No court/SNAP management.

## Requirements
- **FR4**: Provide a web-based staff operations dashboard for station planning, auto-assignment, run-of-show, and RE NXT exception reports.
- **FR61**: Provide a daily operations view with all shifts across centers, mobile opportunities, per-shift attendee/assignment/flag data, staff assignments, and a timeline view.
- **FR62**: Show each staff member their relevant operational slice while allowing operations staff to see the full picture.
- **FR63**: Provide a one-week planning view showing shifts, registrations, staffing status, assignment completion status, and issues requiring attention.
- **FR82**: Support CSV/report export for any staff-facing dataset.

## Dependencies
- Sprint 010 — Check-In & QR Code System (Individual)
- Sprint 015 — Auto-Assignment Engine
- Sprint 016 — Staff Assignment Review & Override

## Expected Artifacts
- `src/ui/staff/RunOfShow.*` — Daily operations view
- `src/ui/staff/WeeklyPlanning.*` — Weekly planning view
- `src/api/operations.*` — Operational data endpoints
- `src/services/export.*` — CSV export utility
- `tests/ui/staff/run_of_show.test.*`
- `tests/api/operations.test.*`

## DoD
- [ ] Run-of-show view displays all shifts for a day with attendee counts, assignment status, and flags per shift
- [ ] Each staff member sees only their assigned location/shifts; operations staff sees all locations (role-based test for both cases)
- [ ] Weekly planning view shows 7-day aggregated view with registrations, staffing gaps, and attention-needed flags
- [ ] Shifts with registrations below minimum staffing are highlighted in both views
- [ ] CSV export produces valid files for run-of-show and weekly planning datasets (golden-file test)
- [ ] `make test` passes

## Validation
```bash
make test
```
