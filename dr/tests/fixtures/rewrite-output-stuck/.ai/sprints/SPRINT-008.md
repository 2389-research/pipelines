# Sprint 008 — Orientation Tracking

## Scope
Implement digital orientation video delivery with verified completion tracking (not just link clicks). Support staff-led in-person orientation as a complementary mode with a staff-facing endpoint to mark completion. Orientation renders within the conversational UI flow.

## Non-goals
- No orientation video content creation. No check-in enforcement. No SMS reminders.

## Requirements
- **FR37**: Provide a pre-shift digital orientation video and verify completion rather than only tracking a link click.
- **FR38**: Support a complementary staff-led in-person orientation on-site rather than replacing it.

## Dependencies
- Sprint 005 — Volunteer Registration, Profile & Website-Embedded UI Shell

## Expected Artifacts
- `db/migrations/008_orientation.*` — Orientation status table
- `src/models/orientation.*` — Orientation status model
- `src/ui/orientation/VideoPlayer.*` — Orientation video player with completion tracking
- `src/api/orientation.*` — Orientation status endpoints (volunteer + staff)
- `src/services/orientation.*` — Completion verification logic
- `tests/api/orientation.test.*`
- `tests/services/orientation.test.*`

## DoD
- [ ] Orientation video renders in the conversational UI with a tracked player
- [ ] Completion is recorded only after verified viewing threshold, not on link click alone (unit test)
- [ ] Orientation completion status is stored on the volunteer record and queryable via API
- [ ] Staff can mark in-person orientation as completed for a volunteer via staff-authenticated API endpoint
- [ ] Both digital and staff-led completion paths set the same orientation status flag
- [ ] `make test` passes with orientation unit and integration tests

## Validation
```bash
make test
```
