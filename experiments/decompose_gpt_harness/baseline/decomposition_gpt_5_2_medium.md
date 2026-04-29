# Decomposition (reasoning_effort: medium): Food Bank Volunteer Portal Redesign

Assumptions to keep sprint DoD machine-verifiable despite unspecified stack:
- Repo is organized as a small monorepo with `api/` (backend), `web/` (frontend), `infra/` (docker/ops), and `openapi/` (API contract).
- A top-level `Makefile` provides stable commands used in DoD:
  - `make lint` (format/lint)
  - `make test` (unit/integration tests)
  - `make e2e` (end-to-end tests)
  - `make dev` (local dev bring-up)
  - `make db-reset` / `make db-migrate` (DB lifecycle)
- Local environment uses `docker compose` for DB and supporting services.

> If the implementation chooses a different language/framework, keep the file/module boundaries and `make` targets stable so sprint validation remains consistent.

---

## Sprint 001 — Repo foundation, CI, and core scaffolding
**Scope:** Establish the repository structure, local dev environment, CI pipeline, and baseline “hello world” flows for both API and web. Define the initial DB schema/migration mechanism and an API contract placeholder to unblock parallel work.
**Non-goals:** Implementing real volunteer business logic; authentication; integration with external services.
**Requirements covered:** FR28 (foundation for validation harness; scenario definition stub)
**Dependencies:** 
**Expected artifacts:**
- `Makefile` with `lint/test/e2e/dev/db-migrate` targets
- `infra/docker-compose.yml` (DB + local dependencies placeholders)
- `api/` service skeleton (health endpoint)
- `web/` app skeleton (home page + API connectivity check)
- `openapi/volunteer-portal.yaml` (initial endpoints stub)
- `.github/workflows/ci.yml`
- `docs/adr/0001-repo-structure.md`
**DoD items:**
1. `make dev` starts DB and boots API + web locally without manual steps.
2. `make test` runs and passes a minimal unit test suite in CI.
3. `make lint` runs and passes in CI.
4. API exposes `/health` and is covered by a test (unit or integration).
5. Web renders a landing page and has a smoke test.
6. `openapi/volunteer-portal.yaml` exists and CI validates it (`make test` includes contract validation).
7. `make db-migrate` applies an initial empty migration successfully.
**Complexity:** medium

---

## Sprint 002 — Identity & low-friction authentication (MVP)
**Scope:** Implement minimal account creation and login focusing on phone/email-first onboarding. Include existing-account detection and user-friendly “you already have an account—log in” handling.
**Non-goals:** Social login beyond the selected MVP method; full volunteer dashboard; SMS message campaigns.
**Requirements covered:** FR3, FR5, FR6
**Dependencies:** 001
**Expected artifacts:**
- `api/src/modules/auth/*` (login, verification, account lookup)
- `api/src/modules/volunteers/volunteer.model` (identity fields only)
- DB migrations for `volunteers` table (minimal)
- `web/src/routes/auth/*` (signup/login screens)
- `openapi/` updates for auth endpoints
- Test doubles for SMS/OTP provider (local)
**DoD items:**
1. New volunteer can create an account with name + email + phone (minimal required set) via web.
2. Existing-email signup attempt returns a deterministic error code and a “log in instead” UI path.
3. `make test` passes with unit tests for: account creation, account lookup, and duplicate handling.
4. `make e2e` includes an auth smoke flow (signup then logout/login).
5. OTP/SMS provider is abstracted behind an interface and replaced by a local fake in tests.
6. OpenAPI contract updated and validated in CI.
**Complexity:** medium

---

## Sprint 003 — Volunteer record, profile, and participation history (read model)
**Scope:** Extend the volunteer domain model so each person has a durable record and can view participation history and hours. Provide staff-facing endpoints to lookup volunteers and view history.
**Non-goals:** Automatic hour calculation from assignments/check-ins (until those exist); Raiser’s Edge sync.
**Requirements covered:** FR1
**Dependencies:** 002
**Expected artifacts:**
- DB migrations for `participation_events` (or `shifts_attendance`) table
- `api/src/modules/volunteers/*` CRUD + history endpoints
- `web/src/routes/volunteer/*` basic dashboard (hours + history list)
- Seed script: `api/scripts/seed_dev_data.*`
**DoD items:**
1. Volunteer dashboard displays total hours and a list of participation events from the API.
2. Staff lookup endpoint supports search by email/phone.
3. `make test` passes with unit tests for hours aggregation logic.
4. `make e2e` includes “login → view history” scenario.
5. DB migration creates required tables and `make db-reset` recreates schema cleanly.
**Complexity:** medium

---

## Sprint 004 — Opportunity/shift catalog data model (single-location pilot)
**Scope:** Introduce the core opportunity/shift entities needed for discovery and registration: locations, opportunities, scheduled shifts, capacity, and open-slot computation. Target the pilot constraint of “one location” first while keeping the model extensible.
**Non-goals:** Guided matching UX; station-level operational constraints (next sprint); assignment planning.
**Requirements covered:** FR9 (open slots), (partial) FR7/FR8 (prereq)
**Dependencies:** 001
**Expected artifacts:**
- DB migrations: `locations`, `opportunities`, `shifts`, `shift_slots`
- `api/src/modules/opportunities/*` list/detail endpoints
- `web/src/routes/opportunities/*` browse list + shift detail
- `openapi/` updates for catalog endpoints
**DoD items:**
1. API lists upcoming shifts with computed `open_slots`.
2. Web can browse and view shift details for the pilot location.
3. `make test` passes with unit tests for capacity/open-slot computation.
4. `make e2e` includes “browse → open shift detail” scenario.
5. Seed data creates at least 3 opportunities and 10 shifts for local demo.
**Complexity:** medium

---

## Sprint 005 — Guided discovery (preferences → recommendations)
**Scope:** Implement a pragmatic, testable matching flow that collects volunteer preferences (e.g., inside/outside/mobile, time of day, party size) and recommends suitable shifts. Provide a guided (wizard-style) experience now; conversational UI can be layered later.
**Non-goals:** Full conversational agent; personalization from deep history beyond basic filters.
**Requirements covered:** FR7, FR8, FR4 (opportunities-first path)
**Dependencies:** 004, 002
**Expected artifacts:**
- `api/src/modules/discovery/*` recommendation endpoint
- `web/src/routes/discovery/*` guided preference wizard + recommended shifts
- Shared preference schema (e.g., `api/src/modules/discovery/preferences.schema.*`)
- Tests for ranking/filter behavior
**DoD items:**
1. User can start from “Find a shift” without logging in (opportunities-first), then is prompted to log in when selecting.
2. Recommendation endpoint returns deterministic results given a fixed seed dataset.
3. `make test` passes with unit tests for preference filtering/ranking.
4. `make e2e` includes “guided preferences → recommended shift list” flow.
5. OpenAPI includes discovery endpoints and CI validates contract.
**Complexity:** medium

---

## Sprint 006 — Shift registration (individual) + reservation integrity
**Scope:** Implement self-service registration into open slots with no staff approval for regular opportunities. Add server-side integrity to prevent overbooking and provide clear confirmation state.
**Non-goals:** Group registration; waiver/orientation; messaging.
**Requirements covered:** FR9, FR4
**Dependencies:** 002, 004
**Expected artifacts:**
- DB migrations: `registrations` (volunteer_id, shift_id, status)
- `api/src/modules/registrations/*` create/cancel endpoints with concurrency-safe capacity checks
- `web/src/routes/registration/*` confirm/cancel UI
- `openapi/` updates
**DoD items:**
1. Logged-in volunteer can register for a shift and see confirmation.
2. Overbooking is prevented under concurrency (test uses parallel requests).
3. Volunteer can cancel a registration; open slots update.
4. `make test` passes including a concurrency/integrity test.
5. `make e2e` includes “select shift → log in if needed → register → confirm” scenario.
**Complexity:** medium

---

## Sprint 007 — Group registration + partial attendee capture
**Scope:** Add group signup: a group organizer registers and optionally supplies some member details, with ability to leave members as “TBD” for onsite capture later. Preserve “keep group together” metadata for downstream assignment planning.
**Non-goals:** QR check-in; station assignments; special-case pathways.
**Requirements covered:** FR10, FR15 (data model prerequisite)
**Dependencies:** 006
**Expected artifacts:**
- DB migrations: `groups`, `group_members` (known/unknown placeholders)
- `api/src/modules/groups/*` and group registration endpoints
- `web/src/routes/groups/*` group signup UI
- Tests for capacity allocation with groups
**DoD items:**
1. Organizer can register N seats for a group against a shift capacity.
2. Group can be created with a mix of named members and placeholders.
3. Capacity accounting treats placeholders as seats.
4. `make test` passes with unit tests for group capacity allocation.
5. `make e2e` includes “group signup with 2 known + 3 TBD members” scenario.
**Complexity:** medium

---

## Sprint 008 — Digital waivers (sign + enforceable status)
**Scope:** Implement digital waiver templates, signing flow, and storage tied to the volunteer record and (where relevant) group members. Enforce waiver completion according to a configurable rule (e.g., must be complete before check-in).
**Non-goals:** Orientation video tracking; SMS reminders.
**Requirements covered:** FR11
**Dependencies:** 003, 006, 007
**Expected artifacts:**
- DB migrations: `waiver_templates`, `waiver_signatures`
- `api/src/modules/waivers/*` (template fetch, sign, status)
- `web/src/routes/waivers/*` signing UI
- Admin seed template for pilot waiver
**DoD items:**
1. Volunteer can view and sign a waiver; signature is persisted and auditable.
2. Waiver status endpoint returns complete/incomplete for a volunteer and (if applicable) group members.
3. Registration confirmation page shows waiver status and prompts completion.
4. `make test` passes with unit tests for waiver status and enforcement rules.
5. `make e2e` includes “register → waiver required → sign → proceed” scenario.
**Complexity:** medium

---

## Sprint 009 — Orientation delivery + completion tracking
**Scope:** Provide orientation content delivery (e.g., arrival instructions + video link/embed) and track completion/acknowledgement per volunteer per location (or per shift if needed). Staff can see who has completed orientation.
**Non-goals:** Creating/hosting actual video content pipeline; complex quizzes/certifications.
**Requirements covered:** FR12
**Dependencies:** 003, 006
**Expected artifacts:**
- DB migrations: `orientation_modules`, `orientation_completions`
- `api/src/modules/orientation/*` endpoints
- `web/src/routes/orientation/*` orientation page and acknowledgement
- Staff endpoint/view stub: completion list for a shift
**DoD items:**
1. Orientation module can be associated to a location/opportunity and rendered in web.
2. Volunteer completion/ack is recorded with timestamp.
3. Staff can retrieve a list of registrants with waiver + orientation status.
4. `make test` passes with unit tests for orientation completion logic.
5. `make e2e` includes “register → view orientation → mark complete → staff sees status”.
**Complexity:** medium

---

## Sprint 010 — Messaging engine (SMS) for confirmations/reminders/follow-ups
**Scope:** Implement an event-driven messaging subsystem with templating and a pluggable SMS provider. Trigger messages for registration confirmation, pre-shift reminder, and post-shift follow-up (initially time-simulated in tests).
**Non-goals:** Full marketing automation; complex segmentation; in-depth deliverability tooling.
**Requirements covered:** FR13
**Dependencies:** 006, 009
**Expected artifacts:**
- `api/src/modules/messaging/*` (templates, outbox, provider adapter)
- DB migrations: `message_templates`, `message_outbox`, `message_delivery_attempts`
- Background worker skeleton: `api/src/workers/messaging_worker.*`
- Test fake SMS provider
**DoD items:**
1. Registration confirmation triggers an SMS entry in outbox.
2. Pre-shift reminder can be scheduled relative to shift start.
3. Post-shift follow-up can be triggered from an attendance event placeholder.
4. `make test` passes with unit tests for template rendering and scheduling.
5. `make e2e` verifies that registration produces an outbox record (using fake provider).
**Complexity:** medium

---

## Sprint 011 — QR code check-in + onsite intake for missing attendees
**Scope:** Implement QR-code-based check-in for individuals and groups. Support onsite capture of missing group member details (name + contact) and convert placeholders into real attendee records.
**Non-goals:** Station assignment execution; post-shift impact card.
**Requirements covered:** FR14, FR15
**Dependencies:** 007, 008
**Expected artifacts:**
- `api/src/modules/checkin/*` (QR token issuance/validation, check-in endpoints)
- DB migrations: `checkins` and QR token table (or signed-token strategy documented)
- `web/src/routes/checkin/*` (scanner page + manual fallback + intake form)
- Staff check-in console page (basic)
**DoD items:**
1. System can generate a QR code for a registration (individual and group).
2. Scanning/entering the code marks attendance for the correct shift.
3. For group placeholders, staff can enter missing member details on site and record attendance.
4. `make test` passes with unit tests for QR validation and placeholder conversion.
5. `make e2e` includes “group check-in with 2 TBD → capture details → all checked in”.
**Complexity:** medium

---

## Sprint 012 — Operational shift structure: stations, capacities, constraints
**Scope:** Model station-level operational details needed for planning: stations per location, labor needs, conditions (e.g., sitting required/allowed), and per-station capacity. Staff can configure these for the pilot location and associate them to a shift.
**Non-goals:** Optimization/planning algorithm; drag/drop overrides; run-of-show dashboard.
**Requirements covered:** FR16
**Dependencies:** 004
**Expected artifacts:**
- DB migrations: `stations`, `station_constraints`, `shift_station_requirements`
- `api/src/modules/operations/*` CRUD endpoints
- `web/src/routes/staff/operations/*` configuration UI
- Seed data for pilot stations
**DoD items:**
1. Staff can define stations and required headcount per station for a shift.
2. Constraints like “must be seated” (or similar) can be represented in data.
3. API returns a shift’s operational requirements in a single endpoint.
4. `make test` passes with unit tests for validation (e.g., capacities non-negative, totals make sense).
5. `make e2e` includes “create/update station requirements for a shift” scenario.
**Complexity:** medium

---

## Sprint 013 — Assignment planning engine (MVP) + staff overrides
**Scope:** Produce an initial station assignment plan from registered/checked-in volunteers and operational constraints, including “keep groups together” and basic accommodation constraints. Provide staff tools to override (reassign) and persist the final plan.
**Non-goals:** Full optimization across many locations; advanced fairness/rotation; complex solver tuning.
**Requirements covered:** FR17, FR18
**Dependencies:** 012, 007, 011
**Expected artifacts:**
- `api/src/modules/planning/*` planning endpoints and plan persistence
- DB migrations: `assignment_plans`, `station_assignments`
- `web/src/routes/staff/planning/*` plan view + simple override UI (drag/drop or select)
- Planning algorithm module with deterministic seedable behavior for tests
**DoD items:**
1. Given a seeded dataset, `POST /planning/plan` returns a complete assignment plan with no station over capacity.
2. Group members are assigned to the same station unless impossible (and then a clear constraint-violation reason is returned).
3. Staff can override an assignment and the final plan persists.
4. `make test` passes including deterministic planner tests (fixed seed).
5. `make e2e` includes “generate plan → override 1 volunteer → reload and verify persisted”.
**Complexity:** high

---

## Sprint 014 — Staff run-of-show (daily operations view)
**Scope:** Provide staff a consolidated daily view across shifts for the pilot location: who is registered, who checked in, waiver/orientation status, and assignment readiness. Include filters and a “today at a glance” view.
**Non-goals:** Multi-center enterprise dashboards; analytics/BI; photo/picture-station coordination.
**Requirements covered:** FR19
**Dependencies:** 006, 011, 013
**Expected artifacts:**
- `api/src/modules/run_of_show/*` aggregation endpoints
- `web/src/routes/staff/run-of-show/*` dashboard UI
- Basic role-based access check (staff-only routes)
**DoD items:**
1. Staff dashboard shows all shifts for a selected date with counts (registered, checked-in, missing waiver/orientation).
2. Staff can drill into a shift to see assignments and check-in list.
3. Access to staff routes is blocked for non-staff users.
4. `make test` passes with unit tests for aggregation correctness.
5. `make e2e` includes “non-staff denied → staff allowed → view run-of-show”.
**Complexity:** medium

---

## Sprint 015 — Post-shift engagement: impact card + next commitment prompt
**Scope:** After attendance is recorded, deliver a digital “impact card” and prompt for next commitment (next shift signup) plus an optional monthly giving call-to-action. Implement as web pages linked from SMS and as an in-product experience.
**Non-goals:** Full donation processing (use outbound link); complex social sharing integrations.
**Requirements covered:** FR20, FR21
**Dependencies:** 010, 011
**Expected artifacts:**
- `api/src/modules/engagement/*` endpoints to generate impact-card data
- `web/src/routes/impact/*` impact card page + next-shift CTA
- Messaging templates for post-shift follow-up linking to impact card
**DoD items:**
1. A checked-in attendee receives (in outbox) a post-shift SMS containing an impact-card link.
2. Impact card page renders with shift/opportunity context and share-friendly metadata.
3. Page includes “sign up again” CTA that deep-links into discovery/shift signup.
4. `make test` passes with unit tests for impact card payload generation.
5. `make e2e` includes “check-in → trigger follow-up → open impact card page”.
**Complexity:** medium

---

## Sprint 016 — Raiser’s Edge NXT integration: matching + sync + exceptions (pilot)
**Scope:** Implement a pragmatic integration layer that (a) attempts donor/volunteer matching during volunteer flow using email/phone, (b) syncs volunteer + participation/attendance data, and (c) queues uncertain matches for staff review. Start with a sandbox/stub if the real API is not yet accessible, but keep interfaces and tests identical.
**Non-goals:** Replacing Raiser’s Edge stewardship workflows; advanced dedupe across multiple CRMs.
**Requirements covered:** FR22, FR23, FR24
**Dependencies:** 003, 006, 011
**Expected artifacts:**
- `api/src/integrations/raisers_edge/*` client + mapping layer
- DB migrations: `crm_sync_jobs`, `crm_match_candidates`, `crm_exceptions`
- `web/src/routes/staff/crm/*` exception review UI
- Feature flag/config: `config/crm.*` (sandbox vs production)
**DoD items:**
1. Matching endpoint returns: `match_found`, `no_match`, or `needs_review` with confidence score.
2. Attendance event enqueues a sync job; worker processes jobs against stub/sandbox.
3. Staff can list and mark exceptions as resolved (select correct match or “create new”).
4. `make test` passes with contract tests for the CRM client using a recorded/stubbed HTTP fixture.
5. `make e2e` includes “new volunteer → needs_review → staff resolves → sync job succeeds”.
**Complexity:** high

---

## Sprint 017 — Special-case pathways routing (skills-based, court-required, benefits-related)
**Scope:** Add explicit routing and data capture for three special pathways: skills-based volunteering (resume upload + application state), court-required community service (dedicated intake), and benefits-related hours (dedicated intake). Implement the minimum viable workflow states and staff queueing while keeping these flows isolated from regular “open slot” signup.
**Non-goals:** Fully defined legal/compliance reporting; complex SLA management; automated approvals.
**Requirements covered:** FR25, FR26, FR27
**Dependencies:** 002, 003, 004
**Expected artifacts:**
- `api/src/modules/special_paths/*` (intake forms, workflow states)
- DB migrations: `applications`, `application_documents`, `application_status_history`
- `web/src/routes/special/*` three entry flows + submission confirmation
- `web/src/routes/staff/applications/*` staff review queue (basic)
- File storage adapter abstraction (local + future cloud)
**DoD items:**
1. Each pathway has a distinct entry point and persists submissions.
2. Skills-based path supports resume upload (stored via adapter) and “submitted → in_review → accepted/rejected” states.
3. Court-required and benefits-related paths capture at least name/contact + required notes fields.
4. Staff can view submissions and update status.
5. `make test` passes with unit tests for workflow transitions and upload adapter.
6. `make e2e` includes one submission for each pathway and staff status update.
**Complexity:** high

---

## Sprint 018 — End-to-end validation harness (“perfectly planned shift” simulation)
**Scope:** Build the explicit validation scenario described in the spec: seed one location with stations/constraints, generate diverse volunteers (individuals and groups, different preferences/needs), run them through signup/forms/orientation, produce an assignment plan, check in attendees, and verify sync/match behaviors. This sprint turns the spec’s validation narrative into repeatable automated tests.
**Non-goals:** Load/performance testing at production scale; multi-location simulation.
**Requirements covered:** FR28 (and provides coverage evidence across FR1–FR24)
**Dependencies:** 005, 007, 009, 011, 013, 016
**Expected artifacts:**
- `e2e/` test suite with deterministic seed data generator
- `api/scripts/simulate_planned_shift.*` (CLI to run scenario locally)
- CI job step running the harness
- `docs/validation/perfectly_planned_shift.md`
**DoD items:**
1. `make e2e` runs a “perfectly planned shift” scenario end-to-end and passes in CI.
2. Simulation creates at least: 20 volunteers, 3 groups, and at least 1 accommodation constraint case.
3. Scenario asserts: no overbooking, waivers/orientation tracked, plan respects capacities, group-together rule satisfied.
4. Scenario asserts: check-in converts placeholders into real attendees.
5. Scenario asserts: CRM matching returns deterministic outcomes (stubbed) and exceptions workflow is exercised.
6. `make test` still passes (unit/integration remain green).
**Complexity:** high

---

## Sprint 019 — Website integration hardening (embedded shell + UX polish gates)
**Scope:** Make the volunteer experience feel website-native: embedded layout shell, consistent navigation, and deep-link support from SMS to specific steps (impact card, orientation, check-in instructions). Add accessibility and basic performance budgets to keep the “warm, welcoming” experience usable.
**Non-goals:** Full rebrand/redesign of the entire public site; advanced personalization.
**Requirements covered:** FR2, (supports) FR4, FR13
**Dependencies:** 005, 010, 015
**Expected artifacts:**
- `web/src/components/SiteShell/*` (embed-friendly)
- `web/src/routes/*` updates for deep links
- Accessibility test tooling config (e.g., axe)
- `docs/integration/website_embed.md`
**DoD items:**
1. Web app can run embedded under a configurable base path (e.g., `/volunteer`) without broken routes.
2. Deep links from SMS open the correct page/state (orientation, impact card, registration confirmation).
3. `make test` passes including automated accessibility checks for key pages.
4. `make e2e` includes at least one deep-link navigation test.
5. Lighthouse (or equivalent) CI check passes an agreed baseline (configured in repo and executed by `make test` or `make e2e`).
**Complexity:** medium

---

## Sprint 020 — Production readiness: security, observability, and operational runbooks
**Scope:** Harden the system for pilot operation: audit logging for critical actions (check-in, waiver signing, CRM sync), metrics/tracing hooks, error reporting, and backup/restore for the DB. Add runbooks for staff/admin and a pilot cutover checklist.
**Non-goals:** Full SOC2 program; enterprise SSO; multi-region deployment.
**Requirements covered:** (supports) FR1–FR24 reliability; FR28 pilotability
**Dependencies:** 014, 016, 018
**Expected artifacts:**
- `api/src/modules/audit/*` (audit events)
- `infra/observability/*` (metrics/logging config)
- `docs/runbooks/*` (ops + incident + pilot checklist)
- `scripts/backup_db.sh` and `scripts/restore_db.sh` (or equivalent)
**DoD items:**
1. Critical actions emit audit events persisted to DB (or log sink) with tests.
2. `make test` passes including tests asserting audit emission.
3. Health/readiness endpoints cover DB connectivity and worker queue status.
4. `make e2e` runs with observability enabled and produces logs/artifacts in CI.
5. Backup + restore scripts run successfully against local environment (`make db-reset` + restore produces same seeded state hash).
6. Runbooks exist and CI checks markdown links (`make test` includes doc lint).
**Complexity:** medium
