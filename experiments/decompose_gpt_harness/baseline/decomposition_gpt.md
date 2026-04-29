# Decomposition into Implementation Sprints (ordered)

Assumptions to make the plan independently verifiable (can be swapped later without changing FR intent):
- Monorepo with **Web** (Next.js) + **API** (Node/TypeScript) + **PostgreSQL**.
- Tests: **Jest** for unit/integration, **Playwright** for web E2E.
- Workspace runner: **pnpm** with root scripts (`pnpm test`, `pnpm lint`, `pnpm e2e`).
- SMS provider abstraction with a “dev” provider; Twilio can be plugged later.

---

## SPRINT-001 — Repo + Dev Environment + Website-Embedded Shell

**Scope:** Establish the runnable skeleton for the portal: monorepo structure, API/web apps, database container, migrations scaffolding, and CI-style commands. Deliver a website-embedded shell (layout, routing, theming hooks) so subsequent sprints can add real flows without reworking plumbing.

**Non-goals:** No real volunteer functionality yet (no auth, no opportunities, no signup). No integration to external systems.

**Requirements covered:** FR2 (foundation for “feels integrated”)

**Dependencies:** —

**Expected artifacts:**
- `pnpm-workspace.yaml`, root `package.json` with scripts (`lint`, `test`, `e2e`, `dev`)
- `apps/web/` (Next.js shell: layout, navigation, basic pages)
- `apps/api/` (API server scaffold with health endpoint)
- `docker-compose.yml` (Postgres)
- `apps/api/src/db/` migration scaffolding (tool of choice) + `seed` placeholder
- `README.md` with local run commands
- `.github/workflows/ci.yml` (or equivalent) running lint+tests

**DoD items (checkable):**
1. `pnpm -v` and `pnpm install` complete without errors.
2. `docker compose up -d db` starts Postgres container.
3. `pnpm -r lint` passes.
4. `pnpm -r test` passes (includes at least one trivial test per app).
5. `pnpm --filter api dev` serves `GET /health` returning 200.
6. `pnpm --filter web dev` serves the web shell and renders a landing page.
7. `pnpm -r e2e` runs a Playwright smoke test that asserts the landing page loads.

**Complexity:** medium

---

## SPRINT-002 — Identity + Volunteer Accounts (minimal signup, existing detection, low-friction login)

**Scope:** Implement volunteer identity and accounts with the minimum upfront fields (name optional, email + phone required) and low-friction authentication (SMS one-time code; optional OAuth can be queued). Include existing-account detection so duplicate email/phone results in a clear “log in” path. Provide a basic “My Profile” page showing account info.

**Non-goals:** No opportunity selection or registration yet. No Raiser’s Edge matching/sync yet.

**Requirements covered:** FR1 (account basis), FR3, FR5, FR6

**Dependencies:** 001

**Expected artifacts:**
- `apps/api/src/modules/auth/*` (OTP request/verify, session/JWT)
- `apps/api/src/modules/volunteer/*` (Volunteer model + CRUD for self)
- DB migrations: `volunteers`, `auth_otps` (or equivalent)
- `apps/web/app/(public)/login/*`, `apps/web/app/(authed)/profile/*`
- Unit/integration tests for auth flows

**DoD items (checkable):**
1. `pnpm --filter api db:migrate` applies migrations to a local DB.
2. `pnpm --filter api test` passes including tests for: create volunteer, request OTP, verify OTP.
3. Duplicate email/phone returns a deterministic error code (e.g., `ACCOUNT_EXISTS`) and test asserts message copy is present.
4. `pnpm --filter web test` passes (component tests for login/profile rendering).
5. `pnpm -r e2e` passes: Playwright test can create an account (using dev OTP provider) and reach `/profile`.

**Complexity:** medium

---

## SPRINT-003 — Opportunity Catalog + Guided Discovery (preferences → recommendations)

**Scope:** Create the core opportunity/shift catalog and a guided discovery UX that collects preferences (e.g., indoor/outdoor/mobile, time of day, party size) and returns recommended shifts. Provide a browsable list/calendar view as a fallback.

**Non-goals:** No registration/slot reservation yet (only discovery). No special-case pathways.

**Requirements covered:** FR7, FR8

**Dependencies:** 001, 002

**Expected artifacts:**
- DB migrations: `locations`, `opportunities`, `shifts` (min viable fields)
- `apps/api/src/modules/opportunities/*` (list/search/recommend endpoints)
- `apps/web/app/opportunities/*` (guided wizard + list/calendar page)
- Seed data for one pilot location

**DoD items (checkable):**
1. `pnpm --filter api test` passes including unit tests for recommendation rules (given preferences, recommended shifts are sorted/filtered).
2. `pnpm --filter api test` includes API integration test for `GET /opportunities` and `POST /recommendations`.
3. `pnpm --filter api db:seed` creates at least 1 location, 3 opportunities, 10 shifts.
4. `pnpm -r e2e` passes: Playwright test completes the wizard and sees recommended shifts.

**Complexity:** medium

---

## SPRINT-004 — Registration (opportunities-first) + Open-slot Signup + Group Signup

**Scope:** Implement the primary conversion funnel: volunteer chooses a shift first, then logs in/creates an account, then confirms signup. Support individual and group signup, with “regular” opportunities allowing immediate self-confirmation if capacity exists. Persist registrations and group membership.

**Non-goals:** No waivers/orientation yet. No QR check-in yet.

**Requirements covered:** FR4, FR9, FR10

**Dependencies:** 002, 003

**Expected artifacts:**
- DB migrations: `registrations`, `groups`, `group_members` (or equivalent)
- `apps/api/src/modules/registration/*` (capacity checks, create/cancel registration)
- `apps/web/app/shifts/[id]/signup/*` (opportunities-first flow)
- Concurrency-safe capacity enforcement (transaction or locking strategy)

**DoD items (checkable):**
1. `pnpm --filter api test` passes including capacity enforcement tests (cannot exceed shift capacity).
2. `pnpm --filter api test` includes tests for group signup keeping members associated to a group.
3. `pnpm -r e2e` passes: (a) anonymous user picks shift → prompted to login → completes signup, (b) group signup for party size N succeeds.
4. API exposes `GET /me/registrations` and test asserts a logged-in volunteer can retrieve their upcoming shift.

**Complexity:** medium-high

---

## SPRINT-005 — Digital Waiver + Orientation Content + Completion Tracking

**Scope:** Add waiver and orientation modules: volunteers can complete a digital waiver tied to their volunteer record, and view orientation/arrival content (video/link + checklist). Track completion status and expose it to staff views and check-in gating (configurable rule: required before check-in).

**Non-goals:** No SMS messaging yet (email/SMS triggers can be stubbed). No check-in yet.

**Requirements covered:** FR11, FR12

**Dependencies:** 002, 004

**Expected artifacts:**
- DB migrations: `waivers`, `waiver_acceptances`, `orientation_items`, `orientation_completions`
- `apps/api/src/modules/compliance/*` (waiver/orientation endpoints)
- `apps/web/app/compliance/*` (waiver signing UI, orientation page)
- Policy config (env or DB) for “waiver required before check-in”

**DoD items (checkable):**
1. `pnpm --filter api test` passes with tests proving waiver acceptance is linked to volunteer ID and timestamp.
2. `pnpm --filter api test` includes orientation completion test (mark viewed; verify status).
3. `pnpm -r e2e` passes: volunteer with a registration can complete waiver + orientation and sees “completed” state.
4. If waiver gating is enabled, API denies check-in eligibility (`403`) in a tested scenario.

**Complexity:** medium

---

## SPRINT-006 — Messaging Engine (SMS) + Confirmation/Reminder/Follow-up Triggers

**Scope:** Implement an event-driven messaging engine with templates and scheduled sends. Wire it to key lifecycle events: registration confirmation, pre-shift reminder with arrival instructions, and post-shift thank-you/impact link. Provide a dev SMS provider and a production-ready provider interface.

**Non-goals:** No full post-shift “impact card” UI yet (just message hooks/links). No Raiser’s Edge integration.

**Requirements covered:** FR13

**Dependencies:** 002, 004, 005

**Expected artifacts:**
- `apps/api/src/modules/messaging/*` (templates, send queue, scheduler)
- DB migrations: `message_templates`, `message_jobs`, `message_deliveries`
- Provider interface: `SmsProvider` with `DevSmsProvider` implementation
- Admin/dev page to inspect outbound messages (optional but recommended)

**DoD items (checkable):**
1. `pnpm --filter api test` passes including tests that creating a registration enqueues a confirmation SMS job.
2. `pnpm --filter api test` includes scheduler test: jobs due “now” are picked up and marked delivered via dev provider.
3. `pnpm -r e2e` passes: signup triggers a confirmation message visible in a dev “outbox” view.
4. `pnpm --filter api lint` passes.

**Complexity:** medium

---

## SPRINT-007 — QR Check-in + Onsite Intake (missing group member details) + Attendance Hours

**Scope:** Build the onsite check-in experience: generate QR codes per registration/group, scan to check in quickly, and allow capturing missing group member details on site. Record attendance and compute volunteer hours per shift so the volunteer profile can show participation history.

**Non-goals:** No station assignment planning yet. No run-of-show dashboard yet.

**Requirements covered:** FR14, FR15, FR1

**Dependencies:** 004, 005

**Expected artifacts:**
- DB migrations: `checkins`, `attendances` (or equivalent), optional `qr_tokens`
- API endpoints: generate QR token, validate token, check-in attendee(s), add missing member contact info
- `apps/web/app/checkin/*` (staff-facing scanner page + manual lookup fallback)
- Update `apps/web/app/(authed)/profile/*` to show attended shifts + total hours

**DoD items (checkable):**
1. `pnpm --filter api test` passes with unit tests for QR token validation (expired/invalid tokens rejected).
2. `pnpm --filter api test` includes group check-in test that creates placeholder members and then updates them with onsite details.
3. `pnpm -r e2e` passes: Playwright test simulates QR check-in and then verifies `/profile` shows updated hours/history.
4. `pnpm --filter api test` includes waiver gating integration (cannot check in if waiver required and incomplete).

**Complexity:** medium

---

## SPRINT-008 — Operations Data Model (locations, stations, capacities, conditions) + Staff Admin

**Scope:** Implement the operational configuration needed for planning: locations, stations, station capacities, labor conditions (e.g., standing/sitting), and per-shift station requirements. Provide a minimal staff admin UI to manage these entities for the pilot location.

**Non-goals:** No auto-assignment algorithm yet (just capturing constraints). No donor sync.

**Requirements covered:** FR16

**Dependencies:** 001, 003, 004

**Expected artifacts:**
- DB migrations: `stations`, `station_requirements`, `labor_conditions` (or a normalized equivalent)
- `apps/api/src/modules/ops/*` (CRUD for ops entities)
- `apps/web/app/staff/admin/*` (basic admin pages)
- Seeded example station setup for the pilot location

**DoD items (checkable):**
1. `pnpm --filter api test` passes including CRUD tests for station creation and capacity rules.
2. `pnpm -r e2e` passes: staff user can create/edit a station and see it reflected in shift configuration.
3. `pnpm --filter api db:seed` seeds at least 3 stations with different conditions (e.g., “standing” vs “seated”).

**Complexity:** medium

---

## SPRINT-009 — Assignment Planning Engine (auto plan) + Staff Override

**Scope:** Deliver the “planned shift” core: generate an initial station assignment plan from registered volunteers + group constraints + station requirements/conditions, then allow staff to override via a simple UI (move volunteer between stations while respecting capacity where possible). Persist the final plan.

**Non-goals:** No cross-location run-of-show aggregation yet. No advanced optimization beyond the defined constraints/heuristics.

**Requirements covered:** FR17, FR18

**Dependencies:** 004, 007, 008

**Expected artifacts:**
- DB migrations: `assignments`, `assignment_plans` (draft vs finalized)
- `apps/api/src/modules/planning/*` (plan generation + override endpoints)
- `apps/web/app/staff/shifts/[id]/plan/*` (plan view + drag/drop or equivalent control)
- Deterministic planning heuristics documented in `docs/planning.md`

**DoD items (checkable):**
1. `pnpm --filter api test` passes including deterministic planning unit tests (given seeded inputs, output assignment matches snapshot).
2. `pnpm --filter api test` includes group-cohesion test (group members assigned together unless impossible).
3. `pnpm --filter api test` includes condition test (volunteer marked “needs seated” is assigned to a seated station when available).
4. `pnpm -r e2e` passes: staff generates a plan for a shift and moves a volunteer to another station; API persists change.

**Complexity:** high

---

## SPRINT-010 — Staff Run-of-Show (daily operations view)

**Scope:** Provide a staff-facing daily view aggregating what’s happening across shifts for a day (per location initially): upcoming shifts, registration counts, check-in status, waiver/orientation completion rates, and links to assignment plans. This becomes the operational “home base.”

**Non-goals:** No mobile/photo-station workflow unless later specified. No multi-org or complex permissions.

**Requirements covered:** FR19

**Dependencies:** 007, 008, 009

**Expected artifacts:**
- `apps/api/src/modules/opsDashboard/*` (aggregate queries)
- `apps/web/app/staff/run-of-show/*` (day view UI)
- DB indexes for dashboard queries (as needed)

**DoD items (checkable):**
1. `pnpm --filter api test` passes including integration test for `GET /staff/run-of-show?date=...`.
2. `pnpm -r e2e` passes: staff can open run-of-show, select date, and navigate into a shift’s plan.
3. Basic performance guard: dashboard endpoint responds under a threshold in test (e.g., < 500ms) using seeded dataset (asserted in test).

**Complexity:** medium

---

## SPRINT-011 — Post-shift Engagement (impact card + next commitment prompts)

**Scope:** Build the post-shift volunteer experience: a digital impact card page (shareable link), a “book your next shift” prompt, and an optional monthly-giving CTA capture (store interest, do not implement full stewardship). Tie delivery to attendance and messaging hooks.

**Non-goals:** Do not replace Raiser’s Edge stewardship workflows (explicit boundary). No payment processing implementation.

**Requirements covered:** FR20, FR21

**Dependencies:** 006, 007, 003

**Expected artifacts:**
- `apps/api/src/modules/engagement/*` (impact card data, next-shift suggestions, giving-interest capture)
- DB migrations: `impact_cards`, `giving_interests`
- `apps/web/app/impact/[attendanceId]/*` (shareable impact page)
- Messaging templates updated to include post-shift impact link

**DoD items (checkable):**
1. `pnpm --filter api test` passes including test that attendance triggers post-shift message job with impact-card URL.
2. `pnpm -r e2e` passes: after check-in+attendance closeout, volunteer can open impact page and see next-shift CTA.
3. `pnpm --filter api test` includes test for giving-interest capture endpoint and persistence.

**Complexity:** medium

---

## SPRINT-012 — Special-case Pathways (skills-based, court-required, benefits-hours)

**Scope:** Add distinct routing and data capture for: (a) skills-based volunteering with resume upload + staff review queue, (b) court-required community service intake (separate form + staff review status), and (c) benefits-related hours pathway (separate intake; minimal rules pending). These pathways should not block the standard “regular opportunity” flow.

**Non-goals:** Do not over-specify approval SLAs or detailed reporting beyond what the transcript states. No document-generation for courts/benefits unless later specified.

**Requirements covered:** FR25, FR26, FR27

**Dependencies:** 002, 003, 004

**Expected artifacts:**
- DB migrations: `applications`, `application_reviews`, `uploads` (resume storage metadata)
- `apps/api/src/modules/specialPathways/*` (routing + submission + review queue)
- `apps/web/app/special/*` (entry routing + forms)
- `apps/web/app/staff/review-queue/*`

**DoD items (checkable):**
1. `pnpm --filter api test` passes including tests for skills-based application submission and status transitions (submitted → under_review → approved/rejected).
2. `pnpm --filter api test` includes upload validation tests (file type/size constraints).
3. `pnpm -r e2e` passes: volunteer submits a skills-based application; staff can see it in the review queue.
4. `pnpm -r e2e` includes court-required intake page renders and submission succeeds.

**Complexity:** medium-high

---

## SPRINT-013 — Raiser’s Edge NXT Integration: Record Matching, Sync, and Exceptions

**Scope:** Implement the donor/volunteer integration layer: match volunteers to existing Raiser’s Edge records using email/phone, sync volunteer participation data, and route uncertain matches into a staff exception queue. Provide an integration test harness using a mocked Raiser’s Edge API so development is not blocked on credentials.

**Non-goals:** Do not implement Raiser’s Edge stewardship workflows. Do not attempt to solve all identity matching edge cases beyond fields discussed (email/phone) without stakeholder confirmation.

**Requirements covered:** FR22, FR23, FR24

**Dependencies:** 002, 007 (attendance), 011 (optional for richer engagement signals)

**Expected artifacts:**
- `apps/api/src/integrations/raisersEdge/*` (client, mapping, retry/backoff)
- DB migrations: `crm_links`, `crm_sync_jobs`, `crm_match_exceptions`
- `apps/web/app/staff/crm-exceptions/*` (review/resolve UI)
- Mock RE server for tests: `apps/api/test/mocks/raisersEdgeServer.ts`

**DoD items (checkable):**
1. `pnpm --filter api test` passes including contract-like tests against the mock RE server.
2. `pnpm --filter api test` includes matching tests: exact email match → linked; phone match → linked; ambiguous → exception created.
3. `pnpm -r e2e` passes: staff can open CRM exceptions page and mark an exception as resolved.
4. Sync job retry logic is covered by a unit test (simulated 500/timeout → retries → failure recorded).

**Complexity:** high

---

## SPRINT-014 — End-to-End Validation / Simulation Harness (“perfectly planned shift”)

**Scope:** Deliver the explicit validation finish line: a deterministic end-to-end simulation for one pilot location that creates diverse volunteers (individuals/groups, different preferences/constraints), moves them through discovery → signup → waiver/orientation → check-in → assignment planning, and validates resulting station plans meet constraints. This sprint turns the spec’s validation scenario into an automated, repeatable gate.

**Non-goals:** No additional features beyond what’s needed to simulate and assert the scenario. No production analytics.

**Requirements covered:** FR28

**Dependencies:** 003, 004, 005, 007, 008, 009, 013

**Expected artifacts:**
- `apps/api/src/simulations/perfectShift/*` (scenario builder + assertions)
- `apps/api/test/e2e/perfectShift.e2e.test.ts` (or equivalent)
- `docs/validation/perfectly-planned-shift.md` (inputs/expected outputs)
- Seed dataset for the pilot location consistent with simulation

**DoD items (checkable):**
1. `pnpm --filter api test -- perfectShift` passes and is deterministic across runs.
2. The simulation asserts: no station exceeds capacity; groups kept together when possible; seated-required volunteers assigned to seated stations when available.
3. Simulation asserts waiver/orientation completion is recorded prior to check-in when gating enabled.
4. Simulation asserts a CRM sync job is created for each new volunteer and exceptions are created for ambiguous matches (using mock RE).
5. `pnpm -r test` passes in CI mode (single command for full suite).

**Complexity:** high
