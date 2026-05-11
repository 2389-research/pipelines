# Sprint 015 — Auto-Assignment Engine

## Scope
Implement the algorithm that generates draft station assignment plans from registered volunteers and station configuration. Enforce ALL five FR56 constraints: group cohesion, accessibility compatibility, capacity limits, minimum staffing priority, and balanced distribution. Output is a draft plan requiring explicit staff approval before execution.

## Non-goals
- No staff override UI. No run-of-show. Assignment does not auto-execute.

## Requirements
- **FR55**: Generate a draft station assignment plan from registered volunteers and station configuration.
- **FR56**: Enforce group cohesion, accessibility compatibility, capacity limits, minimum staffing priority, and balancing constraints in auto-assignment.
- **FR57**: Require staff review before the generated assignment plan is executed.

## Dependencies
- Sprint 011 — Group Volunteer Registration & Waiver Management
- Sprint 013 — Location & Station Configuration

## Expected Artifacts
- `src/services/auto_assignment.*` — Assignment algorithm
- `src/models/assignment.*` — Assignment model (volunteer-to-station mapping, draft/published state)
- `src/api/assignments.*` — Assignment generation and retrieval endpoints
- `tests/services/auto_assignment.test.*` — Comprehensive constraint tests

## DoD
- [ ] Algorithm generates a draft assignment plan given registered volunteers and station configuration
- [ ] Group cohesion: all members of a group are assigned to the same station (test with 3+ groups)
- [ ] Accessibility: volunteers with accessibility needs are assigned only to compatible stations (test with mixed accessibility)
- [ ] Capacity: no station exceeds its maximum capacity (test with over-subscription scenario)
- [ ] Minimum staffing: under-filled stations are prioritized before over-staffing any station (test)
- [ ] Balancing: volunteers are distributed as evenly as practical after hard constraints are met (test)
- [ ] Algorithm produces a valid partial plan and flags violations when constraints are unsatisfiable (graceful degradation test)
- [ ] Generated plan is flagged as "draft" requiring explicit staff approval to publish
- [ ] Integration test: generate assignment for 30+ volunteers across 5+ stations with mixed constraints passes
- [ ] `make test` passes

## Validation
```bash
make test
```
