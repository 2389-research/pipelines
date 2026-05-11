# Sprint 003 — Shared Backend, Data Model & Anonymous Opportunity Browsing

## Scope
Define the core data model (volunteers, shifts, locations, groups) with database migrations. Build the public-facing opportunity listing API (no auth required) and the calendar/list browse UI with urgency signals. Visitors can browse shifts immediately with no login gate, matching NIFB brand styling. This establishes both the data foundation (FR1) and the "Opportunities First" entry point (FR6, FR8).

## Non-goals
- No authentication, no registration, no conversational UI, no SMS. No waiver or orientation flows.

## Requirements
- **FR1**: The web and SMS interaction surfaces must share a single backend and volunteer record.
- **FR5**: Embed the volunteer experience directly in the NIFB website with no redirect to a separate portal.
- **FR6**: Show available volunteer opportunities immediately with no login gate.
- **FR7**: Surface dynamic urgency signals for high-need shifts.
- **FR8**: Delay login/account creation until after a visitor selects a shift of interest.
- **FR19**: Provide a visual calendar/list browse view that is available at any point in the conversation.
- **FR20**: Keep the calendar view consistent across locations.
- **FR21**: Surface urgency messaging for shifts with open spots.
- **FR74**: Match NIFB brand, typography, and color scheme so the UI feels native rather than like a bolted-on chatbot widget.
- **FR75**: Keep the volunteer flow under the NIFB domain instead of redirecting to an external domain.
- **FR77**: Avoid any "return to our website" pattern because the volunteer experience is already on the website.

## Dependencies
- Sprint 002 — Hello World End-to-End Proof

## Expected Artifacts
- `db/migrations/003_core_schema.*` — volunteers, shifts, locations, groups tables
- `src/models/volunteer.*` — Volunteer record model
- `src/models/shift.*` — Shift model with capacity and location
- `src/models/location.*` — Location model
- `src/api/opportunities.*` — Public shift listing endpoint (no auth)
- `src/services/urgency.*` — Urgency calculation logic
- `src/ui/discovery/ShiftCalendar.*` — Calendar/list browse view
- `src/ui/discovery/ShiftCard.*` — Shift card with urgency badge
- `src/ui/styles/nifb-theme.*` — NIFB brand theming (colors, typography, spacing)
- `tests/models/` — Model unit tests
- `tests/api/opportunities.test.*` — Opportunity API tests
- `tests/services/urgency.test.*` — Urgency logic tests

## DoD
- [x] Database migration creates core tables (volunteers, shifts, locations, groups) with appropriate constraints
- [x] `GET /api/opportunities` returns available shifts with location, time, capacity, and open spots without requiring authentication
- [x] Calendar view displays shifts across multiple locations with consistent layout
- [x] List view displays shifts sortable/filterable by date, location, and availability
- [x] Urgency badges appear on shifts meeting urgency criteria (e.g., <20% spots remaining)
- [x] UI renders under NIFB domain path with no cross-domain redirects and no "return to website" links
- [x] CSS theme tokens match NIFB brand values (primary/secondary colors, font-family, spacing documented in theme file)
- [x] `make test` passes with all new unit and API tests

## Validation
```bash
make build && make lint && make test
```
