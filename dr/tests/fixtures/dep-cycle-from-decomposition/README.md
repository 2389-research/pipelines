# Fixture: dep-cycle-from-decomposition

Captures the failure mode from ISSUE-001 (see `dr/docs/known_issues.md`) — a
sprint plan whose `depends_on` graph contains a back-edge: a lower-ID sprint
depending on a higher-ID sprint.

Specifically, this fixture has 4 sprints (000-003) with **Sprint 002 depending
on Sprint 003** — a textbook back-edge.

## Expected validate_output behavior

Running the `validate_output` check (see
`dr/parts/decomposition/write_and_validate_sprint_artifacts.dip`) against this
fixture must emit a token `back-edge-002-003` (among possibly other errors).

The fixture is intentionally minimal — most other validate_output checks
pass — so the back-edge token is the headline failure.

## Use

Driven by `dr/scripts/test_back_edge_detection.sh`.
