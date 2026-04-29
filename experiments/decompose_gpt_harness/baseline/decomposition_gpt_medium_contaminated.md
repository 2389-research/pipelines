# Decomposition (reasoning_effort: medium): Food Bank Volunteer Portal Redesign

Assumptions for verifiable sprints (created/locked in Sprint 001):
- Monorepo with `apps/api` (backend) and `apps/web` (public + staff UI).
- Local runtime via `docker compose`.
- Canonical commands are exposed via `Makefile` so all DoD items can reference exact commands even though the final language/framework isn’t specified in the spec.

---

## Sprint 001 — Repo, CI, and local runtime foundation

**Scope:** Create a runnable project skeleton: API service, web app shell, and database container, plus CI that runs lint and tests. Establish a shared command surface (`Makefile`) that subsequent sprints use for machine-verifiable validation.

**Non-goals:**
- No real volunteer functionality (auth, discovery, registration, etc.).
- No external integrations.

**Requirements covered:** FR28 (process foundation only)

**Dependencies:** _None_

**Expected artifacts:**
- `Makefile` with targets: `dev-up`, `dev-down`, `test`, `lint`, `db-migrate`
- `docker-compose.yml` (web, api, db)
- `apps/api/` skeleton with `GET /health`
- `apps/web/` skeleton that calls API health
- CI config: `.github/workflows/ci.yml`
- `README.md` with local dev instructions

**DoD items:**
1. `make dev-up` starts all services successfully (exit 0).
2. `curl -fsS http://localhost:<api_port>/health` returns 200.
3. Web app loads and displays a value returned from `/health`.
4. `make db-migrate` runs successfully against a clean DB.
5. `make test` runs in CI and locally (includes at least 1 trivial unit test per app).
6. `make lint` runs in CI and locally (exit 0).

**Complexity:** Medium

---

## Sprint 002 — Core domain schema + persistence (volunteers, locations, shifts, registrations)

**Scope:** Implement the minimum durable data model needed for discovery and signup: volunteers, locations, shifts/opportunities, and registrations (with capacity fields and audit timestamps). Add API endpoints sufficient for staff/admin seeding and for later public browse.

**Non-goals:**
- No authentication.
- No guided discovery UX.
- No group rosters yet.

**Requirements covered:** FR1 (data foundations), FR9 (capacity foundations), FR16 (data foundations)

**Dependencies:** 001

**Expected artifacts:**
- DB migrations in `db/migrations/` for `volunteers`, `locations`, `shifts`, `registrations`
- API models + basic routes under `apps/api/src/*`
- Seed data for one pilot location: `db/seed/pilot_location.*`

**DoD items:**
1. `make db-migrate` creates schema from scratch (fresh database).
2. `make test` includes DB/API tests for create/read: volunteer, shift, registration.
3. API supports listing shifts with remaining capacity.
4. Seed script creates 1 location and ≥3 shifts; verification test asserts counts.
5. `make lint` passes.

**Complexity:** Medium

---

## Sprint 003 — Identity & auth v1 (minimal signup + existing-account detection + SMS OTP)

**Scope:** Implement low-friction authentication centered on phone/email with SMS one-time passcodes, including “existing account” detection (by normalized email/phone) and clear UX when a user tries to re-register. Allow browsing/selecting a shift before forcing login (“opportunities-first”).

**Non-goals:**
- No Google/Apple social login in this sprint.
- No full volunteer profile editing beyond minimal fields.

**Requirements covered:** FR3, FR4, FR5, FR6

**Dependencies:** 001, 002

**Expected artifacts:**
- API auth routes: `apps/api/src/routes/auth/*` (request OTP, verify OTP, lookup)
- Volunteer auth fields (normalized phone/email, verification timestamps)
- SMS provider interface + fake provider for tests: `apps/api/src/integrations/sms/*`
- Web login UI and “select shift → then login” guard flow

**DoD items:**
1. `make test` includes unit tests for normalization + existing-account detection.
2. `make test` includes API integration test of OTP verify using fake SMS provider.
3. Anonymous user can view shift listing and click into a shift before login prompt (FR4).
4. Attempt to create an account with an existing email/phone produces a deterministic “log in instead” state (FR5).
5. `make lint` passes.

**Complexity:** Medium

---

## Sprint 004 — Opportunity browse (pilot) + “site-native” shell

**Scope:** Deliver a baseline public discovery experience: opportunity/shift listing with filters (date/time) and capacity visibility (open slots). Implement a simple website-embedded shell layout (header/footer, routes) so the portal feels like part of the main site.

**Non-goals:**
- No preference-based matching yet.
- No group signup.

**Requirements covered:** FR2, FR9, FR7 (baseline browse only)

**Dependencies:** 002, 003

**Expected artifacts:**
- API: `GET /shifts` with filters and capacity fields
- Web: `apps/web/src/pages/opportunities/*` (list + filters)
- UI test harness (headless) for list page load

**DoD items:**
1. `make test` includes API tests for shift filtering and “has open slots”.
2. Web opportunity list renders seeded shifts (assert via UI test).
3. Shift cards show capacity + remaining slots.
4. `make test` includes at least one headless UI test for listing page.
5. `make lint` passes.

**Complexity:** Medium

---

## Sprint 005 — Guided discovery v1 (preferences → ranked recommendations)

**Scope:** Add a guided matching flow that asks a small set of structured questions (inside/outside/mobile, time of day, group size) and returns ranked recommended shifts. Keep matching deterministic and explainable to support iteration.

**Non-goals:**
- No conversational AI.
- No personalization from volunteer history.

**Requirements covered:** FR7, FR8

**Dependencies:** 004

**Expected artifacts:**
- Web guided flow: `apps/web/src/pages/match/*`
- Matching rules module: `packages/shared/matching/*` (or equivalent)
- (Optional) API recommendation endpoint if server-side

**DoD items:**
1. `make test` includes unit tests for matching rules (fixtures: preferences → expected ordering).
2. Guided flow completes end-to-end and links to shift detail.
3. Recommended results are stable for the same inputs (snapshot or golden-file test).
4. `make lint` passes.

**Complexity:** Medium

---

## Sprint 006 — Individual self-serve registration (open slot → confirmed signup)

**Scope:** Implement end-to-end individual registration: select shift → confirm → create registration with no staff approval when capacity exists. Add a minimal volunteer “My shifts” view to confirm linkage between identity and participation.

**Non-goals:**
- Group registrations.
- Waiver/orientation.

**Requirements covered:** FR9, FR1 (participation/history foundations)

**Dependencies:** 003, 004

**Expected artifacts:**
- API: `POST /registrations` with capacity enforcement
- Web: shift detail + registration confirmation pages
- Web: `apps/web/src/pages/me/*` (upcoming shifts)

**DoD items:**
1. `make test` includes API integration test: registration succeeds when capacity > 0.
2. `make test` includes API integration test: registration fails when capacity == 0 with deterministic error code.
3. Web flow registers an authenticated user and shows confirmation.
4. “My shifts” shows the newly created registration.
5. `make lint` passes.

**Complexity:** Medium

---

## Sprint 007 — Group registration + roster model (partial attendee info)

**Scope:** Add group signup where a group lead reserves N seats on a shift and optionally enters partial member details. Persist a roster so check-in can later fill missing details on site.

**Non-goals:**
- Onsite check-in UI and editing (next sprint(s)).
- Skills-based/court/benefits pathways.

**Requirements covered:** FR10, FR15 (data readiness)

**Dependencies:** 006

**Expected artifacts:**
- DB: `groups`, `group_members` (or equivalent)
- API: group registration endpoints
- Web: group signup UI (reserve seats, optional member info)

**DoD items:**
1. `make db-migrate` adds group/roster schema.
2. `make test` includes integration tests for reserving N seats within capacity.
3. `make test` includes validation tests allowing placeholder/unknown member details.
4. Web: group lead can complete signup for N seats and see roster summary.
5. `make lint` passes.

**Complexity:** Medium-High

---

## Sprint 008 — Waiver + orientation module + completion tracking

**Scope:** Implement a digital waiver associated to a volunteer record plus an orientation page (arrival instructions + video placeholder) with completion/acknowledgement tracking. Expose waiver/orientation status so downstream steps (check-in, messaging) can reference it.

**Non-goals:**
- Final content production (use placeholders).
- Hard enforcement policy at check-in (can be configured later).

**Requirements covered:** FR11, FR12

**Dependencies:** 006, 007

**Expected artifacts:**
- DB: waiver/orientation status tables
- API: endpoints to fetch/update completion status
- Web: waiver form page + orientation page

**DoD items:**
1. `make test` includes unit tests for waiver state transitions.
2. `make test` includes integration test ensuring waiver completion attaches to correct volunteer.
3. Web: volunteer can complete waiver and see “completed” status.
4. Web: volunteer can acknowledge orientation and see timestamped status.
5. `make lint` passes.

**Complexity:** Medium

---

## Sprint 009 — Messaging engine v1 (SMS templates + triggers)

**Scope:** Introduce an event-driven messaging layer for SMS confirmations/reminders and post-shift follow-up (placeholder copy). Use a provider adapter and message log so behavior is testable without a real SMS vendor.

**Non-goals:**
- Two-way SMS.
- Email.

**Requirements covered:** FR13

**Dependencies:** 003, 006, 008

**Expected artifacts:**
- Messaging module + outbound log: `apps/api/src/messaging/*`
- SMS templates in `apps/api/src/messaging/templates/*`
- Deterministic reminder runner: `make run-reminders`

**DoD items:**
1. `make test` includes unit tests verifying template selection per event type.
2. `make test` includes integration tests verifying fake SMS provider receives expected payload.
3. Registration confirmation SMS is emitted on successful signup.
4. `make run-reminders` sends reminders for shifts within a fixed test window (assert via tests).
5. `make lint` passes.

**Complexity:** Medium

---

## Sprint 010 — QR check-in + attendance records + onsite roster completion

**Scope:** Implement QR-code-based check-in for individual and group registrations, creating attendance records. Provide a staff-facing check-in screen that supports scanning (with a token-entry fallback) and allows capturing missing group member details on site.

**Non-goals:**
- Station assignments surfaced at check-in.
- Hardware-specific scan performance tuning.

**Requirements covered:** FR14, FR15

**Dependencies:** 007, 008

**Expected artifacts:**
- API: check-in endpoints + attendance table
- Web staff UI: `apps/web/src/pages/staff/checkin/*`
- QR code generation component on registration confirmation

**DoD items:**
1. `make test` includes API integration test: check-in marks attendance for individual registration.
2. `make test` includes API integration test: group check-in updates missing member name/contact.
3. Web: registration confirmation renders a QR code encoding a check-in token.
4. Staff UI supports scanning or pasting token and confirms attendance creation.
5. `make lint` passes.

**Complexity:** Medium

---

## Sprint 011 — Operations configuration model (stations, capacities, constraints)

**Scope:** Build staff configuration for operational planning: locations’ stations, station capacities, and volunteer constraints metadata (e.g., “needs to sit”). This creates the structured inputs required for automated assignment planning.

**Non-goals:**
- No assignment algorithm yet.
- No run-of-show dashboard.

**Requirements covered:** FR16

**Dependencies:** 002

**Expected artifacts:**
- DB: stations + constraint tables
- API: CRUD endpoints for ops configuration
- Staff UI: `apps/web/src/pages/staff/ops/*`

**DoD items:**
1. `make test` includes API tests for station create/update with capacity validations.
2. Staff UI can create/edit stations for pilot location.
3. Constraint flags can be attached to a volunteer or registration (schema + API).
4. `make test` includes a UI test that ops config saves and reloads.
5. `make lint` passes.

**Complexity:** Medium

---

## Sprint 012 — Assignment planning v1 + staff override workflow

**Scope:** Implement a first-pass assignment planning engine that assigns (checked-in) volunteers to stations under capacity and basic constraints, keeping groups together when possible. Provide staff UI to view the plan and override assignments, with server-side validation for hard constraints.

**Non-goals:**
- Proving global optimality; use explainable heuristics.
- Multi-location optimization.

**Requirements covered:** FR17, FR18

**Dependencies:** 010, 011

**Expected artifacts:**
- Planning module: `apps/api/src/planning/*`
- API: `POST /shifts/:id/plan`, `PATCH /assignments/:id`
- Staff UI: `apps/web/src/pages/staff/shifts/[id]/assignments/*`

**DoD items:**
1. `make test` includes unit tests asserting: capacity respected; groups co-located when feasible.
2. `make test` includes integration test that generates a plan from seeded check-ins.
3. Staff UI displays assignments by station.
4. Override persists and reloads correctly.
5. API rejects overrides that exceed station capacity (tested).
6. `make lint` passes.

**Complexity:** High

---

## Sprint 013 — Staff run-of-show dashboard (daily operations view)

**Scope:** Provide a staff “run of show” view for a given day: shifts, expected headcount, checked-in count, and whether a plan exists. This is the operational hub linking to check-in and assignment pages.

**Non-goals:**
- Photo/picture-station workflow.
- Advanced analytics beyond the daily view.

**Requirements covered:** FR19

**Dependencies:** 010, 012

**Expected artifacts:**
- API: `GET /staff/run-of-show?date=YYYY-MM-DD`
- Staff UI: `apps/web/src/pages/staff/run-of-show/*`

**DoD items:**
1. `make test` includes API tests verifying expected vs checked-in counts.
2. Run-of-show UI loads and renders seeded pilot day.
3. Each shift row links to check-in and assignments.
4. `make test` includes a UI test for run-of-show page load.
5. `make lint` passes.

**Complexity:** Medium

---

## Sprint 014 — Post-shift experience (impact card + next commitment prompts)

**Scope:** Deliver a post-shift volunteer experience: digital impact card page (placeholder data acceptable) and prompts for next commitment (sign up for another shift) plus a monthly-giving CTA. Trigger post-shift SMS only when attendance is present.

**Non-goals:**
- Full donor stewardship workflows.
- Final content/creative.

**Requirements covered:** FR20, FR21, FR13 (post-shift portion)

**Dependencies:** 009, 010

**Expected artifacts:**
- Web: `apps/web/src/pages/impact/[attendanceId]/*`
- API: impact-card data endpoint
- Event wiring: post-shift SMS linking to impact page

**DoD items:**
1. `make test` includes test that post-shift messages only send for `present=true` attendance.
2. Impact page renders for a completed attendance record (UI test).
3. “Next shift” CTA routes back to browse/match flow.
4. Monthly-giving CTA click is recorded as an event (DB + API + test).
5. `make lint` passes.

**Complexity:** Medium

---

## Sprint 015 — Raiser’s Edge NXT integration v1 (matching, sync job, exception queue)

**Scope:** Implement a sync pipeline to Raiser’s Edge NXT (or a mockable adapter if the live API is not yet available) that links volunteers to external constituent records. Add deterministic matching on email/phone with confidence scoring, and an exception queue for staff review below threshold.

**Non-goals:**
- Replacing stewardship workflows in Raiser’s Edge.
- Full bidirectional real-time sync of all fields.

**Requirements covered:** FR22, FR23, FR24

**Dependencies:** 002, 003, 006

**Expected artifacts:**
- Integration adapter: `apps/api/src/integrations/raisers-edge/*`
- DB: external IDs, sync state, exception queue tables
- Staff UI: `apps/web/src/pages/staff/crm-exceptions/*`
- Job runner: `make run-crm-sync`

**DoD items:**
1. `make test` includes unit tests for confidence scoring (exact vs partial matches).
2. `make test` includes integration tests using a mocked Raiser’s Edge HTTP server.
3. `make run-crm-sync` processes pending volunteers and records success/failure in sync tables (tested).
4. Exceptions appear in staff UI with actions: link / dismiss / retry.
5. `make lint` passes.

**Complexity:** High

---

## Sprint 016 — Special-case pathway routing (skills-based, court-required, benefits-hours)

**Scope:** Add distinct routing and minimum viable intake flows for skills-based volunteering (resume upload + review states), court-required community service, and benefits-related hours. Ensure these cases don’t get forced through the standard self-serve shift signup without capturing needed flags/state.

**Non-goals:**
- Fully-specified legal/reporting document generation.
- SLA automation beyond basic status tracking.

**Requirements covered:** FR25, FR26, FR27

**Dependencies:** 003, 004, 006

**Expected artifacts:**
- Web: `apps/web/src/pages/special/*` (routing + forms)
- API: application entities + review state machine endpoints
- File upload adapter for resumes (local + pluggable)

**DoD items:**
1. `make test` includes unit tests for state transitions (submitted → under_review → accepted/rejected).
2. Skills-based flow accepts a resume upload and stores a file reference (tested).
3. Court-required and benefits-related flows store pathway flags on the volunteer/application (tested).
4. Staff can list/filter special-pathway submissions (API + UI test).
5. `make lint` passes.

**Complexity:** High

---

## Sprint 017 — End-to-end simulation harness (“perfectly planned shift” regression gate)

**Scope:** Build the spec’s explicit validation scenario: seed one pilot location with stations/constraints, generate diverse volunteers (individuals, groups, constraints), run them through signup, waiver/orientation, check-in, assignment planning, and (optionally) CRM sync in a deterministic, PII-free simulation. Make this a CI gate to prevent regressions.

**Non-goals:**
- Load/performance benchmarking.
- Multi-location rollout.

**Requirements covered:** FR28

**Dependencies:** 008, 010, 011, 012, 015

**Expected artifacts:**
- Simulation runner: `apps/api/src/simulations/perfect_shift/*`
- PII-free fixtures/golden outputs: `apps/api/src/simulations/perfect_shift/fixtures/*`
- `Makefile` target: `make test-e2e`
- CI job to run `make test-e2e`

**DoD items:**
1. `make test` includes unit tests asserting fixtures contain no real PII (pattern-based checks).
2. `make test-e2e` runs the full scenario and exits 0.
3. Simulation asserts: registrations created, waiver/orientation completed, attendance recorded.
4. Simulation asserts: assignment plan generated and station capacities not exceeded.
5. Simulation asserts: group members are assigned together when feasible.
6. CI runs `make test-e2e` on every PR and blocks merges on failure.

**Complexity:** High
