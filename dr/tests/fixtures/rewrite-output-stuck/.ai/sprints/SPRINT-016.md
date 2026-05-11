# Sprint 016 — Staff Assignment Review & Override

## Scope
Build the staff-facing assignment review interface with drag-and-drop volunteer movement between stations, constraint re-validation on every manual change with warnings on violations, assignment locking, and notes/flags on assignments.

## Non-goals
- No run-of-show. No weekly planning. No reporting.

## Requirements
- **FR58**: Allow staff to drag and drop volunteers between stations and override any auto-assignment.
- **FR59**: Allow staff to add notes/flags to assignments and lock assignments to prevent re-optimization.
- **FR60**: Re-validate constraints after each manual change and warn or flag on violations such as over-capacity or split groups.

## Dependencies
- Sprint 015 — Auto-Assignment Engine

## Expected Artifacts
- `src/ui/staff/AssignmentBoard.*` — Drag-and-drop assignment review UI
- `src/api/assignment_overrides.*` — Override, lock, and note endpoints
- `src/services/constraint_validator.*` — Post-override constraint checking
- `tests/ui/staff/assignment_board.test.*`
- `tests/services/constraint_validator.test.*`

## DoD
- [ ] Staff can view the draft assignment plan with volunteers mapped to stations
- [ ] Staff can drag-and-drop volunteers between stations and the change persists
- [ ] System warns when a manual change violates constraints (over-capacity, group split, accessibility mismatch)
- [ ] Staff can lock an assignment to prevent re-optimization by the auto-assignment engine
- [ ] Staff can add notes and flags to individual assignments
- [ ] Constraint validator re-runs after every manual change (not just on-demand)
- [ ] `make test` passes

## Validation
```bash
make test
```
