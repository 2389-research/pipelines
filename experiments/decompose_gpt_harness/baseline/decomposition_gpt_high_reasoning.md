# Decomposition: Food Bank Volunteer Portal Redesign

Assumptions for verifiability (explicitly created in Sprint 001):
- A monorepo with `apps/web` (public & staff UI) and `apps/api` (backend).
- Local dev/runtime via `docker compose`.
- Standard commands via `Makefile` so later sprints can reference concrete validations even before a specific language/framework is finalized.

---

## Sprint 001 — Repo + runtime foundations (monorepo, CI, local env)

**Scope**: Establish a runnable skeleton for the portal with a backend API service, a web app shell, and a database container. Add CI to run lint/tests on every change and a `Makefile` that defines the canonical commands used by all later sprints.

**Non-goals**:
- No real volunteer features yet (auth, signup, discovery, etc.).
- No Raiser’s Edge connectivity.

**Requirements covered**: FR28 (only the “validation discipline” foundation; not the full scenario)

**Dependencies**: _None_

**Expected artifacts**:
- `Makefile` with targets: `make dev-up`, `make dev-down`, `make test`, `make lint`, `make db-migrate`
- `docker-compose.yml` (api, web, db)
- `apps/api/` skeleton with a health endpoint
- `apps/web/` skeleton with a landing page and API connectivity check
- CI config (e.g., `.github/workflows/ci.yml`)

**DoD items**:
1. `docker compose up -d` starts `web`, `api`, and `db` containers successfully.
2. `make dev-up` and `make dev-down` work end-to-end.
3. API health endpoint returns 200 (documented in `README.md`).
4. Web app loads and displays “API connected” by calling the health endpoint.
5. `make lint` exits 0 in CI and locally.
6. `make test` exits 0 in CI and locally (includes at least one trivial unit test per app).
7. `make db-migrate` applies an initial empty migration and exits 0.

**Complexity**: Medium

---

## Sprint 002 — Core data model (volunteers, shifts, registrations) + persistence layer

**Scope**: Define the minimum database schema and API-layer models to represent volunteers, opportunities/shifts, and registrations, including audit fields and basic validation. This sprint creates the durable “source of truth” needed for auth, discovery, and signup flows.

**Non-goals**:
- No public discovery UX yet.
- No group-specific behavior beyond data model support.

**Requirements covered**: FR1, FR9 (data prerequisites), FR10 (data prerequisites), FR16 (data prerequisites)

**Dependencies**: 001

**Expected artifacts**:
- DB migrations: `db/migrations/*` creating tables for `volunteers`, `locations`, `shifts`, `registrations`
- API modules: `apps/api/src/models/*`, `apps/api/src/routes/*`
- Seed data for one pilot location: `db/seed/pilot_location.*`

**DoD items**:
1. `make db-migrate` creates the schema from a clean database.
2. `make test` includes model/DB integration tests for create/read of volunteer + shift + registration.
3. API exposes CRUD endpoints (even if staff-only for now) for pilot `locations` and `shifts`.
4. Registration creation validates capacity at the database/API layer.
5. Seed script loads one location with at least 3 shifts.
6. `make lint` passes.

**Complexity**: Medium

---

## Sprint 003 — Identity: minimal signup, returning-user detection, SMS OTP login

**Scope**: Implement low-friction authentication centered on phone/email with SMS one-time codes, including graceful handling of existing accounts (no confusing duplicate-email failures). Provide an “opportunities-first” entry so users can browse/select a shift before being forced to create/login.

**Non-goals**:
- No Google/Apple social login (can be added later if desired).
- No deep volunteer profile editing beyond the minimal fields.

**Requirements covered**: FR2 (basic site-native entry shell), FR3, FR4, FR5, FR6

**Dependencies**: 001, 002

**Expected artifacts**:
- API auth endpoints: `apps/api/src/routes/auth/*` (request code, verify code, lookup)
- Data changes: add auth fields to `volunteers` (normalized phone/email, verification state)
- Web flow: `apps/web/src/pages/opportunities/*` (browse → select → prompt login)
- SMS provider adapter interface with a fake/test implementation: `apps/api/src/integrations/sms/*`

**DoD items**:
1. `make test` includes unit tests for: existing-account detection by email/phone; OTP verify success/failure.
2. `make test` includes an API integration test using the fake SMS adapter.
3. Web: user can select a shift while anonymous, then is prompted to login/create account (FR4).
4. Attempting to “create” with an existing email results in a clear “log in instead” UI state (FR5).
5. `make lint` passes.

**Complexity**: Medium

---

## Sprint 004 — Opportunity catalog API + basic browse UI (pilot location)

**Scope**: Deliver a usable opportunity listing/browse experience for one location, powered by the shift data model. Include filtering by date/time and basic capacity visibility so volunteers can understand what is available and self-sign-up into open slots.

**Non-goals**:
- No guided matching questions yet.
- No special-case pathways.

**Requirements covered**: FR2, FR7 (partial: discovery baseline), FR9

**Dependencies**: 002, 003

**Expected artifacts**:
- API: `GET /opportunities` / `GET /shifts` listing with capacity & open slots
- Web: `apps/web/src/pages/opportunities/index.*` browse + filters
- Tests for listing/filtering

**DoD items**:
1. `make test` includes API tests for filtering shifts by date range and “has open slots”.
2. Web page renders at least 3 seeded shifts from the API.
3. Shift cards show capacity and remaining open slots.
4. `make test` includes a basic UI test (headless) that the list loads.
5. `make lint` passes.

**Complexity**: Medium

---

## Sprint 005 — Guided discovery v1 (preference questions → recommended shifts)

**Scope**: Implement a guided matching flow that asks a small set of preference questions (e.g., inside/outside/mobile, time of day, group size) and outputs recommended shifts. Keep the logic deterministic and explainable to enable iteration.

**Non-goals**:
- No conversational AI; this is a structured guided form.
- No personalization based on history yet.

**Requirements covered**: FR7, FR8

**Dependencies**: 004

**Expected artifacts**:
- Web guided flow: `apps/web/src/pages/match/*`
- API endpoint for recommendations (optional if logic is server-side): `apps/api/src/routes/recommendations/*`
- Shared rule definitions: `packages/shared/matching/*`

**DoD items**:
1. `make test` includes unit tests for matching rules (given preferences → expected ranked shifts).
2. `make test` includes an integration test for the recommendation endpoint (if implemented).
3. Web guided flow completes in ≤ 5 steps and displays a ranked list.
4. Recommended results link directly to shift detail / registration.
5. `make lint` passes.

**Complexity**: Medium

---

## Sprint 006 — Individual registration flow (self-serve signup into open slots)

**Scope**: Implement end-to-end individual signup: select shift → confirm details → create registration record without staff approval when capacity exists. Add basic confirmation UI and ensure the registration is tied to the volunteer record.

**Non-goals**:
- Group signup and roster management (next sprint).
- Waivers/orientation enforcement (later).

**Requirements covered**: FR1 (history linkage), FR9

**Dependencies**: 003, 004

**Expected artifacts**:
- API: `POST /registrations` with capacity enforcement
- Web: `apps/web/src/pages/shifts/[id]/*` and `apps/web/src/pages/registrations/confirm/*`
- Volunteer “My shifts / hours” stub: `apps/web/src/pages/me/*`

**DoD items**:
1. `make test` includes an API integration test: signup succeeds when capacity > 0.
2. `make test` includes an API integration test: signup fails with a clear error when capacity is 0.
3. Web: authenticated user can register for a shift from shift detail.
4. Volunteer dashboard shows upcoming registration(s).
5. `make lint` passes.

**Complexity**: Medium

---

## Sprint 007 — Group registration + roster handling (including partial attendee info)

**Scope**: Add a group signup pathway where a “group lead” registers multiple seats, optionally entering partial attendee info up front. Model group/roster entities so later check-in can fill missing details on site.

**Non-goals**:
- Onsite data capture UI (handled in check-in sprint).
- Skills-based/court-required/benefits pathways (later).

**Requirements covered**: FR10, FR15 (data prerequisites)

**Dependencies**: 006

**Expected artifacts**:
- DB: group/roster tables (e.g., `groups`, `group_members`)
- API: group registration endpoints
- Web: group signup form and confirmation

**DoD items**:
1. `make db-migrate` adds group/roster schema without data loss.
2. `make test` includes tests for reserving N seats for a group within capacity.
3. `make test` includes validation tests allowing “unknown member details” placeholders.
4. Web: group lead can register a group of size N for a shift.
5. `make lint` passes.

**Complexity**: Medium-High

---

## Sprint 008 — Digital waiver + orientation delivery + completion tracking

**Scope**: Implement a digital waiver that is associated with each volunteer and has a clear completion status. Add an orientation module (video + arrival instructions) with tracking of whether the content was viewed/acknowledged pre-shift.

**Non-goals**:
- Producing final video/content; use placeholders.
- Enforcing waiver/orientation as a hard gate at check-in (policy can be toggled later).

**Requirements covered**: FR11, FR12

**Dependencies**: 006, 007

**Expected artifacts**:
- DB: waiver/orientation status tables
- Web: waiver form + orientation page
- API: endpoints to read/update completion status

**DoD items**:
1. `make test` includes unit tests for waiver state transitions (not started → completed).
2. `make test` includes integration tests: waiver completion attaches to the correct volunteer.
3. Web: volunteer can complete waiver and see completed status.
4. Web: volunteer can view orientation and “acknowledge” completion.
5. `make lint` passes.

**Complexity**: Medium

---

## Sprint 009 — Messaging engine v1 (SMS confirmations, reminders, post-shift templates)

**Scope**: Add an event-driven messaging layer with SMS templates and triggers for: registration confirmation, pre-shift reminder, and a post-shift thank-you/impact placeholder. Use a provider adapter with a fake implementation for tests.

**Non-goals**:
- Two-way SMS conversation handling.
- Email messaging.

**Requirements covered**: FR13

**Dependencies**: 003, 006, 008

**Expected artifacts**:
- API: event emitter + message queue abstraction (in-process acceptable initially)
- Templates: `apps/api/src/messaging/templates/*`
- Trigger wiring from registration + check-in + post-shift events

**DoD items**:
1. `make test` includes unit tests verifying correct template selection for each trigger.
2. `make test` includes integration tests that “sending” uses the fake SMS provider and records an outbound message log.
3. Registration confirmation SMS is triggered on successful signup.
4. Pre-shift reminder can be triggered via a deterministic scheduled job command (e.g., `make run-reminders`).
5. `make lint` passes.

**Complexity**: Medium

---

## Sprint 010 — QR check-in + onsite intake (including missing group member details)

**Scope**: Implement QR-code-based check-in for individuals and groups, with a staff-facing scan/check-in screen. Support capturing missing group member details on site and linking them to the registration roster.

**Non-goals**:
- Station assignment at check-in (planned later).
- Hardware-specific scanning optimization beyond browser camera support.

**Requirements covered**: FR14, FR15

**Dependencies**: 007, 008

**Expected artifacts**:
- API: check-in endpoints and attendance records
- Web staff UI: `apps/web/src/pages/staff/checkin/*`
- QR generation on registration confirmation: `apps/web/src/components/QRCode*`

**DoD items**:
1. `make test` includes API integration tests: check-in marks attendance for an individual registration.
2. `make test` includes API integration tests: group check-in supports updating missing member name/contact.
3. Web: registration confirmation displays a QR code that encodes a check-in token.
4. Web staff check-in page can scan (or paste token in a fallback input) and confirm attendance.
5. `make lint` passes.

**Complexity**: Medium

---

## Sprint 011 — Operations model + staff configuration (locations, stations, capacities, constraints)

**Scope**: Build the staff-facing configuration needed to describe operational reality: locations, stations, station capacities, labor conditions, and constraints metadata. This establishes the inputs required for automatic assignment planning.

**Non-goals**:
- No optimization/assignment algorithm yet.
- No run-of-show dashboard yet.

**Requirements covered**: FR16

**Dependencies**: 002

**Expected artifacts**:
- DB migrations: stations/constraints tables
- Staff UI: `apps/web/src/pages/staff/ops/*` for CRUD on stations and constraints
- API: CRUD endpoints for ops configuration

**DoD items**:
1. `make test` includes DB/API tests for creating stations with max capacity.
2. Staff UI can create/edit stations for the pilot location.
3. Constraints metadata can be attached to volunteers or registrations (e.g., “needs to sit”).
4. `make test` includes a UI test that ops config page loads and saves.
5. `make lint` passes.

**Complexity**: Medium

---

## Sprint 012 — Assignment planning engine v1 + staff override workflow

**Scope**: Implement an initial assignment planning engine that maps checked-in volunteers (or registrants) to stations given capacities and constraints, keeping groups together where possible. Provide a staff override UI to adjust assignments and persist the final plan.

**Non-goals**:
- “Perfectly optimal” solver; prioritize correctness and explainable heuristics first.
- Cross-location, multi-day optimization.

**Requirements covered**: FR17, FR18

**Dependencies**: 010, 011

**Expected artifacts**:
- Planning module: `apps/api/src/planning/*`
- API: `POST /shifts/:id/plan` + `PATCH /assignments/*`
- Staff UI: `apps/web/src/pages/staff/shifts/[id]/assignments/*`

**DoD items**:
1. `make test` includes unit tests for planning heuristics (capacity respected, groups kept together when feasible).
2. `make test` includes integration tests that generate a plan for seeded shift + registrations.
3. Staff UI displays station assignments and supports an override action that persists.
4. API rejects overrides that violate hard capacity constraints.
5. `make lint` passes.

**Complexity**: High

---

## Sprint 013 — Staff run-of-show dashboard (daily view across shifts/locations)

**Scope**: Provide a staff “run of show” page that summarizes the day: upcoming shifts, expected headcount, checked-in count, and assignment-plan status per shift. This is the operational control surface that reduces spreadsheet work.

**Non-goals**:
- Photo/picture-station workflows.
- Advanced analytics.

**Requirements covered**: FR19

**Dependencies**: 010, 012

**Expected artifacts**:
- API aggregation endpoint: `GET /staff/run-of-show?date=YYYY-MM-DD`
- Staff UI page: `apps/web/src/pages/staff/run-of-show/*`
- Tests for aggregation correctness

**DoD items**:
1. `make test` includes API tests verifying aggregation fields (expected vs checked-in counts).
2. Staff run-of-show page loads and renders the pilot day’s shifts.
3. Each shift row links to check-in and assignment pages.
4. `make test` includes a UI test that run-of-show loads.
5. `make lint` passes.

**Complexity**: Medium

---

## Sprint 014 — Post-shift engagement: impact card + next commitment prompts

**Scope**: Deliver a post-shift volunteer experience that shows a digital impact card and prompts for the next commitment (another shift) and an optional monthly giving CTA. Trigger post-shift messaging using attendance as the source of truth.

**Non-goals**:
- Full donor stewardship workflows in Raiser’s Edge.
- Final copywriting/creative assets.

**Requirements covered**: FR20, FR21, FR13 (post-shift portion)

**Dependencies**: 009, 010

**Expected artifacts**:
- Web page: `apps/web/src/pages/impact/[attendanceId]/*`
- API: endpoint to generate/store impact card data
- Messaging trigger: post-shift SMS links to impact page

**DoD items**:
1. `make test` includes tests that post-shift messages only send when attendance is marked present.
2. Impact page renders for a completed attendance record.
3. “Sign up for next shift” link returns to discovery/browse with state preserved.
4. Monthly giving CTA click is tracked in an audit/event table.
5. `make lint` passes.

**Complexity**: Medium

---

## Sprint 015 — Raiser’s Edge NXT integration: matching, sync, and exception queue

**Scope**: Implement a sync pipeline that can create/update constituent records (or equivalent) in Raiser’s Edge NXT and link them to portal volunteers. Add record matching based on email/phone with a confidence score and an exception workflow for staff review when confidence is below threshold.

**Non-goals**:
- Replacing Raiser’s Edge stewardship workflows.
- Attempting full real-time bidirectional sync of every field from day one.

**Requirements covered**: FR22, FR23, FR24

**Dependencies**: 002, 003, 006

**Expected artifacts**:
- Integration adapter: `apps/api/src/integrations/raisers-edge/*` with sandbox-friendly configuration
- Sync state tables: `db/migrations/*` for sync cursors, external IDs, exception queue
- Staff UI: `apps/web/src/pages/staff/crm-exceptions/*`

**DoD items**:
1. `make test` includes unit tests for confidence scoring (exact match on email/phone vs partial).
2. `make test` includes integration tests using a mocked Raiser’s Edge API server.
3. A deterministic job command (e.g., `make run-crm-sync`) processes pending volunteers and records success/failure.
4. Exceptions below threshold appear in staff UI with “link / dismiss / retry” actions.
5. `make lint` passes.

**Complexity**: High

---

## Sprint 016 — Special-case pathway routing (skills-based, court-required, benefits-hours)

**Scope**: Add routing and minimum viable flows for: skills-based volunteering (resume upload + review state), court-required community service (separate intake + staff-managed process flag), and benefits-related hours (distinct intake + hours reporting flag). The goal is to prevent these cases from being forced through the standard self-serve path while keeping data consistent.

**Non-goals**:
- Fully specified legal/reporting document generation (unless clarified).
- Full SLA automation for skills-based review.

**Requirements covered**: FR25, FR26, FR27

**Dependencies**: 003, 004, 006

**Expected artifacts**:
- Web: `apps/web/src/pages/special/*` routing entry and forms
- API: endpoints and state machines for applications/review
- Storage: resume upload support (local dev + pluggable adapter)

**DoD items**:
1. `make test` includes unit tests for application state transitions (submitted → under_review → accepted/rejected).
2. Skills-based flow supports resume upload and persists a file reference.
3. Court-required and benefits-related flows store a distinct pathway flag on the volunteer/application.
4. Staff can list and filter special-pathway submissions.
5. `make lint` passes.

**Complexity**: High

---

## Sprint 017 — End-to-end validation/simulation harness (“perfectly planned shift”)

**Scope**: Build the explicit end-to-end simulation harness that the spec calls for: seed one location with stations/constraints, generate diverse volunteers (individuals, groups, constraints), run them through signup, waiver/orientation, check-in, planning, and produce a verifiable “planned shift” output without human intervention. This becomes the baseline regression suite and release gate.

**Non-goals**:
- Load/performance benchmarking beyond basic runtime sanity.
- Multi-location rollout.

**Requirements covered**: FR28 (full)

**Dependencies**: 008, 010, 011, 012, 015

**Expected artifacts**:
- Simulation runner: `apps/api/src/simulations/perfect_shift/*`
- Golden outputs (PII-free): `apps/api/src/simulations/perfect_shift/fixtures/*`
- CI job: runs simulation on every main-branch build

**DoD items**:
1. `make test` includes simulation unit tests for fixture generation (PII-free).
2. `make test-e2e` runs the “perfectly planned shift” scenario end-to-end and exits 0.
3. Simulation asserts: all registrations created, waiver/orientation completed, attendance recorded, plan generated, and capacity constraints satisfied.
4. Simulation asserts: group members are assigned together when feasible.
5. CI runs `make test-e2e` on every PR and blocks merges on failure.

**Complexity**: High
