# Sprint 013 — Location & Station Configuration

## Scope
Implement staff-facing location and station configuration. Staff define locations, stations within locations, and per-station attributes (max capacity, min staffing, labor/accessibility conditions, notes). Configuration persists and is updated incrementally, not rebuilt weekly.

## Non-goals
- No auto-assignment. No run-of-show. No weekly planning.

## Requirements
- **FR53**: Allow staff to define locations, stations within locations, and per-station attributes including maximum capacity, minimum staffing, labor/accessibility conditions, and special notes.
- **FR54**: Persist station configuration per location and update it as operations change instead of rebuilding it weekly.

## Dependencies
- Sprint 003 — Shared Backend, Data Model & Anonymous Opportunity Browsing

## Expected Artifacts
- `db/migrations/013_stations.*` — Station configuration tables
- `src/models/station.*` — Station model with attributes
- `src/api/locations.*` — Location management endpoints (staff-auth)
- `src/api/stations.*` — Station CRUD endpoints (staff-auth)
- `src/ui/staff/LocationConfig.*` — Location configuration UI
- `src/ui/staff/StationConfig.*` — Station configuration UI
- `tests/api/locations.test.*`
- `tests/api/stations.test.*`

## DoD
- [ ] Staff can create and edit locations via the staff UI (staff-auth protected)
- [ ] Staff can add stations to a location with max capacity, min staffing, labor conditions, accessibility flags, and notes
- [ ] Station configurations persist across sessions (test: create → retrieve after restart)
- [ ] Station attributes are validated (min staffing ≤ max capacity; required fields enforced)
- [ ] Locations and stations are listable and filterable via API
- [ ] Non-staff users cannot access configuration endpoints (authorization test)
- [ ] `make test` passes

## Validation
```bash
make test
```
