# Sprint Decomposition — NIFB Volunteer Portal Redesign

> Generated from `.ai/spec_analysis.md`
> Model: claude
> Date: 2025-04-14

---

## FR Coverage Matrix (for traceability)

| FR | Sprint(s) | Description |
|----|-----------|-------------|
| FR1 | 001, 002 | Volunteer accounts tracking participation/history |
| FR2 | 008, 009 | Website-integrated volunteer experience |
| FR3 | 001 | Minimal-info signup (phone, email, name) |
| FR4 | 009 | Opportunities-first, then login/account creation |
| FR5 | 001 | Existing-account detection on duplicate email |
| FR6 | 001 | Low-friction auth (phone OTP, social login stubs) |
| FR7 | 004 | Guided opportunity matching by preferences |
| FR8 | 009 | Conversational/visual discovery UX |
| FR9 | 002 | Open-slot self-service signup |
| FR10 | 003 | Group volunteer signup flow |
| FR11 | 003 | Digital waiver process |
| FR12 | 003 | Orientation delivery and tracking |
| FR13 | 005 | Text-based pre/post shift communications |
| FR14 | 006 | QR-code-based check-in |
| FR15 | 006 | Capture missing group member details at check-in |
| FR16 | 002 | Model locations, stations, labor needs, capacity |
| FR17 | 007 | Auto-generate station assignment plan |
| FR18 | 007 | Staff override/adjust assignment plan |
| FR19 | 007 | Daily run-of-show staff view |
| FR20 | 005 | Digital post-shift impact card |
| FR21 | 005 | Capture next commitment post-shift |
| FR22 | 010 | Volunteer records sync to Raiser's Edge NXT |
| FR23 | 010 | Donor/volunteer record matching |
| FR24 | 010 | Exception workflow for uncertain matches |
| FR25 | 011 | Skills-based volunteering pathway |
| FR26 | 011 | Court-required community service pathway |
| FR27 | 011 | Benefits-related volunteer hours pathway |
| FR28 | 012 | End-to-end validation / simulation harness |

All 28 FRs covered. No orphans.

---

## Sprint 001 — Core Backend Foundation & Authentication

### Scope
Establish the foundational backend: project scaffolding (FastAPI, SQLAlchemy async, PostgreSQL), core database models (Volunteer, OTP), configuration management, and phone-based OTP authentication with JWT tokens. Includes existing-account detection, dev OTP bypass, and the test harness (pytest-asyncio + httpx).

### Non-goals
- No shift/location/station models beyond stubs in the ORM
- No frontend/UI
- No SMS delivery to real phones (dev bypass only)
- No social login (Google/Apple) implementation — stubs at most

### Requirements covered
FR1 (volunteer accounts — foundational model), FR3 (minimal signup), FR5 (duplicate email detection), FR6 (phone OTP auth)

### Dependencies
None — this is the first sprint.

### Expected artifacts
- `backend/pyproject.toml` — project manifest with all deps
- `backend/app/config.py` — Pydantic Settings configuration
- `backend/app/models.py` — SQLAlchemy models (Volunteer, OTP, and remaining entity stubs)
- `backend/app/database.py` — async engine + session factory
- `backend/app/auth.py` — JWT create/verify
- `backend/app/dependencies.py` — `get_current_volunteer` dependency
- `backend/app/schemas.py` — Pydantic request/response schemas
- `backend/app/routers/auth.py` — `/auth/otp/send`, `/auth/otp/verify`, `/auth/register`
- `backend/app/main.py` — FastAPI app factory with `/health`
- `backend/tests/conftest.py` — async DB fixtures, test client
- `backend/tests/test_config.py`
- `backend/tests/test_auth.py`
- `backend/tests/test_health.py`
- `backend/scripts/init_db.py`

### DoD
1. `cd backend && uv run pytest tests/test_config.py -v` passes (settings load)
2. `cd backend && uv run pytest tests/test_auth.py -v` passes (OTP send, verify new user, verify returning user, invalid code rejection, register)
3. `cd backend && uv run pytest tests/test_health.py -v` passes (`/health` returns `{"status":"ok"}`)
4. `POST /auth/register` with an already-registered phone returns HTTP 409
5. `POST /auth/otp/verify` with dev bypass code `000000` returns a token for known users and `is_new=true` for unknown users
6. All ORM models in `models.py` import without error: `cd backend && python -c "from app.models import Volunteer, OTP, Location, Station, Shift, Registration, Group, Waiver"`
7. `cd backend && uv run ruff check app/ tests/` reports zero errors
8. Total test count ≥ 8

### Complexity
Medium

---

## Sprint 002 — Locations, Shifts & Individual Registration

### Scope
Build the operational data layer: CRUD for locations, stations (with capacity/conditions), and shifts. Add the registration endpoint so a single volunteer can browse open shifts, register, and cancel. Volunteer profile read/update endpoints also land here.

### Non-goals
- No group registration (Sprint 003)
- No waivers or orientation (Sprint 003)
- No preference-based matching/recommendation engine (Sprint 004)
- No frontend

### Requirements covered
FR1 (participation history — registration records), FR9 (open-slot self-service signup), FR16 (locations, stations, labor needs, capacity)

### Dependencies
SPRINT-001

### Expected artifacts
- `backend/app/routers/volunteers.py` — `/volunteers/me` GET/PATCH
- `backend/app/routers/locations.py` — CRUD for locations + nested stations
- `backend/app/routers/shifts.py` — CRUD + `/shifts/browse` with filters
- `backend/app/routers/registrations.py` — register, cancel, list own
- `backend/tests/test_volunteers.py`
- `backend/tests/test_locations.py`
- `backend/tests/test_shifts.py`
- `backend/tests/test_registrations.py`

### DoD
1. `cd backend && uv run pytest tests/test_volunteers.py -v` passes (get profile, update profile, unauthorized access blocked)
2. `cd backend && uv run pytest tests/test_locations.py -v` passes (create/list/get/update location; create/list stations)
3. `cd backend && uv run pytest tests/test_shifts.py -v` passes (create shift, browse, filter by location, filter by date, get, update)
4. `cd backend && uv run pytest tests/test_registrations.py -v` passes (register, duplicate blocked, list own, cancel, nonexistent shift 404)
5. Registering for a full shift (max_volunteers reached) returns HTTP 409
6. Cancelled registrations preserve the record (status = `cancelled`, not deleted)
7. `cd backend && uv run pytest -v --tb=short` — all tests pass, total count ≥ 20
8. `cd backend && uv run ruff check app/ tests/` reports zero errors

### Complexity
Medium

---

## Sprint 003 — Groups, Waivers & Orientation

### Scope
Add group volunteer management (create group, group leader flow, group registration that links members to a shift). Implement digital waivers (sign, track completion per volunteer) and orientation tracking (mark viewed, query status). These are prerequisites for the check-in and assignment systems.

### Non-goals
- No QR check-in (Sprint 006)
- No station assignment logic (Sprint 007)
- No SMS delivery (Sprint 005)
- No special-case pathways beyond the `pathway` enum (Sprint 011)

### Requirements covered
FR10 (group signup flow), FR11 (digital waiver), FR12 (orientation delivery/tracking)

### Dependencies
SPRINT-002

### Expected artifacts
- `backend/app/routers/groups.py` — create group, list groups, add members
- `backend/app/routers/waivers.py` — sign waiver, check waiver status
- `backend/app/routers/orientation.py` — mark orientation viewed, check status
- `backend/app/models.py` — Orientation model addition (or field on Volunteer)
- `backend/tests/test_groups.py`
- `backend/tests/test_waivers.py`
- `backend/tests/test_orientation.py`

### DoD
1. `cd backend && uv run pytest tests/test_groups.py -v` passes (create group, list groups, group registration links all members to a shift)
2. `cd backend && uv run pytest tests/test_waivers.py -v` passes (sign waiver, duplicate sign idempotent, check waiver status returns signed/unsigned)
3. `cd backend && uv run pytest tests/test_orientation.py -v` passes (mark viewed, query completion status, returns false before viewing)
4. Group registration decrements available capacity by group size, not by 1
5. A group leader creating a group of size N can register all N members for a shift in one request
6. `cd backend && uv run pytest -v --tb=short` — all tests pass, total count ≥ 30
7. `cd backend && uv run ruff check app/ tests/` reports zero errors

### Complexity
Medium-High

---

## Sprint 004 — Opportunity Discovery & Preference Matching

### Scope
Build the guided opportunity discovery engine: accept volunteer preferences (indoor/outdoor/mobile, time-of-day, group size) and return ranked shift recommendations. This is the backend logic for FR7's "conversational matching" — the API that the frontend discovery UX will call.

### Non-goals
- No frontend UX (Sprint 009 builds the conversational UI)
- No full-text search or keyword matching
- No machine learning — rule-based ranking only

### Requirements covered
FR7 (guided matching based on preferences)

### Dependencies
SPRINT-002 (shifts and locations must exist to recommend against)

### Expected artifacts
- `backend/app/services/discovery.py` — preference-matching scoring engine
- `backend/app/routers/discovery.py` — `POST /discover` endpoint accepting preferences, returning ranked shifts
- `backend/app/schemas.py` — `DiscoveryRequest`, `DiscoveryResult` schemas
- `backend/app/models.py` — station/shift metadata extensions (tags, environment type) if needed
- `backend/tests/test_discovery.py`

### DoD
1. `cd backend && uv run pytest tests/test_discovery.py -v` passes (at least 5 test cases)
2. Sending `{"environment": "indoor", "time_of_day": "morning", "group_size": 1}` returns shifts sorted by match score
3. Shifts at capacity are excluded from results
4. Sending empty preferences returns all available shifts (no crash, graceful fallback)
5. Response includes match score and explanation snippet per shift
6. `cd backend && uv run pytest -v --tb=short` — all tests pass
7. `cd backend && uv run ruff check app/ tests/` reports zero errors

### Complexity
Medium

---

## Sprint 005 — Messaging Engine & Post-Shift Engagement

### Scope
Implement the event-driven messaging/notification engine. Define message templates for confirmations, reminders, arrival instructions, and post-shift impact. Build the post-shift engagement endpoints: generate digital impact card data and prompt for next-shift signup or monthly giving opt-in. SMS delivery uses a pluggable adapter (console/log in dev, Twilio-ready interface).

### Non-goals
- No Twilio production integration (adapter interface only)
- No frontend rendering of impact cards (Sprint 009/010)
- No donor system integration for "Serving Hope" membership (Sprint 010)

### Requirements covered
FR13 (text-based pre/post shift comms), FR20 (digital post-shift impact card), FR21 (capture next commitment post-shift)

### Dependencies
SPRINT-001 (contact data), SPRINT-002 (registration events)

### Expected artifacts
- `backend/app/services/messaging.py` — message template engine + send adapter interface
- `backend/app/services/messaging_adapters.py` — `ConsoleAdapter`, `TwilioAdapter` (stub)
- `backend/app/routers/messages.py` — trigger message send, list message history
- `backend/app/routers/engagement.py` — `GET /engagement/impact-card/{registration_id}`, `POST /engagement/next-commitment`
- `backend/app/models.py` — `Message` model (type, status, sent_at, volunteer_id)
- `backend/tests/test_messaging.py`
- `backend/tests/test_engagement.py`

### DoD
1. `cd backend && uv run pytest tests/test_messaging.py -v` passes (send confirmation, send reminder, template rendering with variables, adapter selection)
2. `cd backend && uv run pytest tests/test_engagement.py -v` passes (impact card generation, next-commitment capture, monthly-giving opt-in flag)
3. Console adapter logs full message text to stdout (verifiable in test output)
4. Message model records delivery status per volunteer
5. Impact card endpoint returns structured data (shift date, hours, meals-packed equivalent or placeholder metric)
6. `cd backend && uv run pytest -v --tb=short` — all tests pass
7. `cd backend && uv run ruff check app/ tests/` reports zero errors

### Complexity
Medium

---

## Sprint 006 — QR Check-In & Onsite Intake

### Scope
Build QR-code generation (per registration), QR scanning/check-in endpoint, and the onsite intake flow that captures missing group member details at arrival. Check-in transitions registration status from `registered` to `checked_in` and records the timestamp.

### Non-goals
- No station assignment at check-in time (Sprint 007)
- No frontend check-in kiosk UI (Sprint 010)
- No orientation enforcement gating (policy TBD — noted in open questions)

### Requirements covered
FR14 (QR-code-based check-in), FR15 (capture missing group member details on site)

### Dependencies
SPRINT-003 (groups and waivers must exist; check-in reads waiver/orientation status)

### Expected artifacts
- `backend/app/services/qr.py` — QR code generation (returns PNG bytes or base64)
- `backend/app/routers/checkin.py` — `POST /checkin/scan` (accept QR payload), `POST /checkin/group/{group_id}` (batch check-in), `POST /checkin/capture-info` (collect missing member data)
- `backend/app/schemas.py` — `CheckinRequest`, `GroupCheckinRequest`, `MemberInfoCapture`
- `backend/tests/test_checkin.py`
- `backend/tests/test_qr.py`

### DoD
1. `cd backend && uv run pytest tests/test_qr.py -v` passes (QR generation returns non-empty bytes, encoded data round-trips correctly)
2. `cd backend && uv run pytest tests/test_checkin.py -v` passes (individual scan, group batch scan, missing-info capture, duplicate scan idempotent, invalid QR rejected)
3. After check-in, `registration.status == "checked_in"` and `registration.checked_in_at` is set
4. Group check-in updates all member registrations in one call
5. `POST /checkin/capture-info` updates volunteer record with newly provided name/email/phone
6. `cd backend && uv run pytest -v --tb=short` — all tests pass
7. `cd backend && uv run ruff check app/ tests/` reports zero errors

### Complexity
Medium

---

## Sprint 007 — Assignment Planning Engine & Staff Operations View

### Scope
Build the constraint-based station assignment engine: given checked-in volunteers, station capacities, labor needs, conditions (standing/sitting), and group-togetherness constraints, produce an optimal initial assignment plan. Add a staff-facing API for the daily "run of show" view and a drag-and-drop-ready override endpoint to reassign individuals.

### Non-goals
- No frontend staff dashboard (Sprint 010)
- No real-time WebSocket push for live updates
- No ML-based optimization — deterministic heuristic/constraint solver

### Requirements covered
FR17 (auto-generate station assignment), FR18 (staff override assignments), FR19 (daily run-of-show view)

### Dependencies
SPRINT-002 (stations, shifts), SPRINT-003 (groups), SPRINT-006 (check-in status)

### Expected artifacts
- `backend/app/services/assignment.py` — constraint solver: inputs (volunteers, stations, groups, conditions) → assignment map
- `backend/app/routers/assignments.py` — `POST /assignments/generate/{shift_id}`, `GET /assignments/{shift_id}`, `PATCH /assignments/{assignment_id}` (manual override)
- `backend/app/routers/runofshow.py` — `GET /operations/run-of-show?date=YYYY-MM-DD` (aggregated day view)
- `backend/app/models.py` — `Assignment` model (volunteer_id, station_id, shift_id, is_manual_override)
- `backend/tests/test_assignment_engine.py` — unit tests for the solver
- `backend/tests/test_assignments_api.py` — integration tests for endpoints
- `backend/tests/test_runofshow.py`

### DoD
1. `cd backend && uv run pytest tests/test_assignment_engine.py -v` passes (≥ 6 cases: basic assignment, respects capacity, keeps groups together, accommodates sitting need, handles over-capacity gracefully, handles zero volunteers)
2. `cd backend && uv run pytest tests/test_assignments_api.py -v` passes (generate, get, override, regenerate after override)
3. `cd backend && uv run pytest tests/test_runofshow.py -v` passes (returns shifts/stations/counts for a given date, empty date returns empty)
4. Generated assignments do not exceed any station's `max_capacity`
5. All members of a group are assigned to the same station
6. Manual override via PATCH persists and is not overwritten on regenerate
7. `cd backend && uv run pytest -v --tb=short` — all tests pass
8. `cd backend && uv run ruff check app/ tests/` reports zero errors

### Complexity
High

---

## Sprint 008 — Frontend Shell & Conversational UI Core

### Scope
Establish the frontend application: framework scaffolding, routing, design system/component library, and the conversational UI component that powers the guided volunteer experience. The shell integrates with the food bank website branding and provides the "feels native" wrapper for all volunteer-facing pages.

### Non-goals
- No complete page implementations beyond the shell + discovery prototype
- No staff/admin pages (Sprint 010)
- No real API integration (mock data acceptable for this sprint)

### Requirements covered
FR2 (website-integrated feel)

### Dependencies
SPRINT-001 (API contract awareness for auth token handling)

### Expected artifacts
- `frontend/package.json` — project manifest
- `frontend/src/App.tsx` (or equivalent) — app shell with routing
- `frontend/src/components/ConversationalFlow.tsx` — reusable step-by-step guided UI component
- `frontend/src/components/Layout.tsx` — branded shell (NIFB header, nav, footer)
- `frontend/src/lib/api.ts` — API client with auth token injection
- `frontend/src/styles/` — design tokens aligned with NIFB branding
- `frontend/tests/` or `frontend/src/**/*.test.tsx` — component tests
- `frontend/README.md`

### DoD
1. `cd frontend && npm test -- --watchAll=false` passes (or equivalent: `pnpm test`, `vitest run`)
2. Layout component renders NIFB-branded header and footer (snapshot or DOM assertion test)
3. ConversationalFlow component renders sequential steps, advances on user input, and emits completion event (unit test)
4. API client attaches `Authorization: Bearer <token>` header when token is present (unit test)
5. App shell renders at `/` without console errors (smoke test)
6. `cd frontend && npm run lint` (or `pnpm lint`) reports zero errors
7. `cd frontend && npm run build` succeeds with zero errors

### Complexity
Medium

---

## Sprint 009 — Frontend: Opportunity Discovery & Signup Flow

### Scope
Build the volunteer-facing discovery and signup pages that wire the conversational UI to the backend discovery and registration APIs. Implements the "opportunities first, then login" flow where a volunteer can browse/filter shifts, pick one, and is prompted to log in or create an account only when they commit. Includes the post-shift engagement screen (impact card display, next-commitment prompt).

### Non-goals
- No group signup UI (Sprint 010)
- No staff views (Sprint 010)
- No check-in kiosk UI (Sprint 010)

### Requirements covered
FR2 (website-integrated experience, continued), FR4 (opportunities-first then auth), FR8 (conversational/visual discovery UX)

### Dependencies
SPRINT-004 (discovery API), SPRINT-005 (engagement API), SPRINT-008 (frontend shell)

### Expected artifacts
- `frontend/src/pages/DiscoverPage.tsx` — preference input → recommended shifts
- `frontend/src/pages/ShiftDetailPage.tsx` — shift info + register CTA
- `frontend/src/pages/AuthPage.tsx` — login/register triggered after shift selection
- `frontend/src/pages/ConfirmationPage.tsx` — registration confirmation
- `frontend/src/pages/ImpactCardPage.tsx` — post-shift impact display + next-commitment
- `frontend/src/hooks/useDiscovery.ts` — API hook for discovery
- `frontend/src/hooks/useRegistration.ts` — API hook for registration
- `frontend/tests/` — page-level integration tests

### DoD
1. `cd frontend && npm test -- --watchAll=false` passes (all new page tests)
2. Discovery page submits preferences and renders ranked shift cards (integration test with mocked API)
3. Clicking "Sign Up" on a shift when unauthenticated redirects to AuthPage, then back to registration on success (flow test)
4. ConfirmationPage renders shift details and a "what to bring/where to go" summary (DOM assertion)
5. ImpactCardPage renders impact data and shows "Book Next Shift" + "Join Serving Hope" CTAs (DOM assertion)
6. `cd frontend && npm run build` succeeds with zero errors
7. `cd frontend && npm run lint` reports zero errors

### Complexity
Medium-High

---

## Sprint 010 — Frontend: Staff Dashboard, Group Management & Check-In Kiosk

### Scope
Build the staff-facing operational views: run-of-show daily dashboard, station assignment board (with drag-drop override), and check-in kiosk mode for scanning QR codes. Also includes the group management UI for group leaders to manage members and the volunteer profile/history page.

### Non-goals
- No Raiser's Edge UI (exception queue is API-only in Sprint 010; staff dashboard extension in Sprint 012)
- No special-case pathway admin screens

### Requirements covered
(Supports FR14, FR15, FR17, FR18, FR19 on the UI layer — backend already delivered in earlier sprints)

### Dependencies
SPRINT-006 (check-in API), SPRINT-007 (assignment + run-of-show API), SPRINT-008 (frontend shell)

### Expected artifacts
- `frontend/src/pages/staff/RunOfShowPage.tsx`
- `frontend/src/pages/staff/AssignmentBoardPage.tsx`
- `frontend/src/pages/staff/CheckInKioskPage.tsx`
- `frontend/src/pages/GroupManagePage.tsx`
- `frontend/src/pages/ProfilePage.tsx` — volunteer history & hours
- `frontend/src/components/QRScanner.tsx` — camera-based QR reader component
- `frontend/src/components/DragDropBoard.tsx` — station assignment drag-drop
- `frontend/tests/` — page tests for each

### DoD
1. `cd frontend && npm test -- --watchAll=false` passes
2. RunOfShowPage renders shifts grouped by location for a selected date (mock data test)
3. AssignmentBoardPage renders stations as columns with volunteer cards; drag-drop fires PATCH call (interaction test)
4. CheckInKioskPage scans a QR code string and calls `/checkin/scan` (mock integration test)
5. GroupManagePage lists members and allows adding missing member info (form test)
6. ProfilePage shows volunteer name, total hours, and registration history (DOM assertion)
7. `cd frontend && npm run build` succeeds with zero errors
8. `cd frontend && npm run lint` reports zero errors

### Complexity
High

---

## Sprint 011 — Raiser's Edge NXT Integration & Donor Matching

### Scope
Build the CRM integration layer: sync volunteer records to Raiser's Edge NXT, implement donor/volunteer matching (by email and phone), and surface an exception queue for uncertain matches (below confidence threshold). Uses a pluggable adapter so the integration can start with ImportOmatic-style batch export and later upgrade to direct API sync.

### Non-goals
- No replacement of Raiser's Edge stewardship workflows (explicitly out of scope per spec)
- No real-time bidirectional sync in v1 (one-way: volunteer platform → RE NXT)
- No donor solicitation features

### Requirements covered
FR22 (sync to Raiser's Edge NXT), FR23 (donor/volunteer record matching), FR24 (exception workflow for uncertain matches)

### Dependencies
SPRINT-001 (volunteer records), SPRINT-002 (registration data), SPRINT-006 (attendance confirmation)

### Expected artifacts
- `backend/app/services/crm_sync.py` — sync orchestrator (batch or event-driven)
- `backend/app/services/crm_adapters.py` — `ImportOMaticAdapter` (CSV export), `RENxtApiAdapter` (stub/real)
- `backend/app/services/donor_matching.py` — matching engine (email, phone, name fuzzy) with confidence scoring
- `backend/app/routers/crm.py` — `POST /crm/sync`, `GET /crm/exceptions`, `POST /crm/exceptions/{id}/resolve`
- `backend/app/models.py` — `SyncRecord`, `MatchException` models
- `backend/tests/test_donor_matching.py`
- `backend/tests/test_crm_sync.py`
- `backend/tests/test_crm_api.py`

### DoD
1. `cd backend && uv run pytest tests/test_donor_matching.py -v` passes (exact email match → 100% confidence, phone match → high confidence, no match → low confidence, fuzzy name + email → medium confidence)
2. `cd backend && uv run pytest tests/test_crm_sync.py -v` passes (sync creates records, sync is idempotent, adapter selection works)
3. `cd backend && uv run pytest tests/test_crm_api.py -v` passes (trigger sync, list exceptions, resolve exception)
4. Matches below 90% confidence appear in the exception queue
5. ImportOMaticAdapter generates a valid CSV file with required Raiser's Edge import fields
6. Resolving an exception links the volunteer record to the RE NXT constituent ID
7. `cd backend && uv run pytest -v --tb=short` — all tests pass
8. `cd backend && uv run ruff check app/ tests/` reports zero errors

### Complexity
High

---

## Sprint 012 — Special-Case Volunteer Pathways

### Scope
Implement the three distinct volunteer pathways that diverge from the standard individual/group flow: skills-based volunteering (resume upload, staff review queue), court-required community service (dedicated intake, hour tracking/reporting), and benefits-related (SNAP) volunteer hours (dedicated intake, proof-of-hours output). Each pathway has routing logic that directs the volunteer at signup time.

### Non-goals
- No custom frontend pages per pathway (API + routing logic only; frontend extensions in Sprint 013)
- No SLA enforcement or automated notifications for review queues

### Requirements covered
FR25 (skills-based pathway), FR26 (court-required pathway), FR27 (benefits-related pathway)

### Dependencies
SPRINT-002 (registration foundation), SPRINT-003 (pathway enum already exists)

### Expected artifacts
- `backend/app/routers/pathways.py` — pathway routing: `POST /pathways/skills-based/apply`, `POST /pathways/court-required/intake`, `POST /pathways/benefits/intake`
- `backend/app/services/pathways.py` — pathway-specific business logic and validation
- `backend/app/models.py` — `SkillsApplication` (resume_url, review_status), `CourtServiceRecord` (case_number, required_hours, completed_hours), `BenefitsRecord` (program_type, required_hours)
- `backend/app/schemas.py` — pathway-specific request/response schemas
- `backend/tests/test_pathways_skills.py`
- `backend/tests/test_pathways_court.py`
- `backend/tests/test_pathways_benefits.py`

### DoD
1. `cd backend && uv run pytest tests/test_pathways_skills.py -v` passes (apply with resume URL, staff can list pending, staff can approve/reject)
2. `cd backend && uv run pytest tests/test_pathways_court.py -v` passes (intake with case number, hours tracked, proof-of-service exportable)
3. `cd backend && uv run pytest tests/test_pathways_benefits.py -v` passes (intake, hours tracked, proof document generated)
4. Pathway routing correctly tags registrations with the appropriate `VolunteerPathway` enum value
5. Skills-based applications cannot self-confirm — they require staff review (status starts as `pending`)
6. `cd backend && uv run pytest -v --tb=short` — all tests pass
7. `cd backend && uv run ruff check app/ tests/` reports zero errors

### Complexity
High

---

## Sprint 013 — Frontend: Pathway UIs & CRM Exception Dashboard

### Scope
Add frontend pages for the three special-case pathways (skills-based application form, court-service intake, benefits intake) and the staff-facing CRM exception resolution dashboard. Also adds the pathway routing screen that directs volunteers to the correct flow at signup based on their stated purpose.

### Non-goals
- No Raiser's Edge stewardship replacement
- No advanced analytics or reporting dashboards

### Requirements covered
(UI layer for FR25, FR26, FR27, FR24 — backend delivered in Sprints 011-012)

### Dependencies
SPRINT-009 (signup flow), SPRINT-011 (CRM exception API), SPRINT-012 (pathway APIs)

### Expected artifacts
- `frontend/src/pages/pathways/SkillsApplyPage.tsx`
- `frontend/src/pages/pathways/CourtIntakePage.tsx`
- `frontend/src/pages/pathways/BenefitsIntakePage.tsx`
- `frontend/src/pages/pathways/PathwayRouterPage.tsx` — "Why are you volunteering?" routing screen
- `frontend/src/pages/staff/CRMExceptionsPage.tsx` — match review + resolve UI
- `frontend/tests/` — page tests

### DoD
1. `cd frontend && npm test -- --watchAll=false` passes
2. PathwayRouterPage renders options and navigates to correct sub-page (flow test)
3. SkillsApplyPage submits resume URL and shows "application received" confirmation (DOM assertion)
4. CourtIntakePage collects case number and required hours (form validation test)
5. CRMExceptionsPage lists pending exceptions and allows resolve/dismiss (mock API test)
6. `cd frontend && npm run build` succeeds with zero errors
7. `cd frontend && npm run lint` reports zero errors

### Complexity
Medium

---

## Sprint 014 — End-to-End Validation & Simulation Harness

### Scope
Build the validation/simulation harness that the spec explicitly calls for: simulate a fully planned shift at one location with diverse volunteers (individuals, groups, different preferences, accessibility needs), and verify the system can move them through signup → waiver → orientation → check-in → assignment → post-shift engagement → CRM sync without a human in the loop. This is the "perfectly planned shift" acceptance test.

### Non-goals
- No load testing / performance benchmarking
- No production data — uses synthetic test fixtures only
- No UI-driven E2E (API-level simulation)

### Requirements covered
FR28 (end-to-end validation scenario)

### Dependencies
SPRINT-007 (assignment engine), SPRINT-006 (check-in), SPRINT-011 (CRM sync), SPRINT-005 (messaging)

### Expected artifacts
- `backend/tests/e2e/test_full_shift_simulation.py` — the master end-to-end test
- `backend/tests/e2e/conftest.py` — fixtures for location, stations, shifts, diverse volunteer pool
- `backend/tests/e2e/test_scenarios.py` — individual scenario variants (solo volunteer, large group, accessibility need, skills-based, court-required)
- `backend/scripts/simulate_shift.py` — standalone script to run the simulation outside pytest
- `docs/validation_report_template.md` — template for recording simulation results

### DoD
1. `cd backend && uv run pytest tests/e2e/test_full_shift_simulation.py -v` passes
2. Simulation creates ≥ 20 volunteers (mix of individuals and groups)
3. All volunteers complete: account creation → registration → waiver → orientation → check-in → assignment
4. Assignment engine produces valid assignments (no over-capacity, groups together)
5. Post-shift messaging is triggered for all checked-in volunteers (verified via console adapter logs)
6. CRM sync processes all volunteer records without errors
7. Exception queue contains expected uncertain matches (seeded test data)
8. `cd backend && uv run pytest tests/e2e/ -v --tb=short` — all E2E tests pass
9. `cd backend && python scripts/simulate_shift.py` completes without error and prints summary
10. `cd backend && uv run ruff check tests/e2e/` reports zero errors

### Complexity
High

---

## Sprint 015 — Deployment Infrastructure & Monitoring

### Scope
Containerize the application (Docker), set up CI/CD pipeline configuration, add structured logging, health check probes, and basic monitoring/alerting hooks. Prepare the system for pilot deployment at one location.

### Non-goals
- No production cloud provisioning (infra-as-code stubs only)
- No CDN or edge caching setup
- No custom monitoring dashboards

### Requirements covered
(Operational readiness supporting all FRs for pilot deployment)

### Dependencies
SPRINT-014 (validation must pass before deployment prep)

### Expected artifacts
- `Dockerfile` (backend)
- `frontend/Dockerfile` (frontend)
- `docker-compose.yml` — full local stack (backend, frontend, postgres)
- `.github/workflows/ci.yml` (or equivalent CI config)
- `backend/app/middleware/logging.py` — structured JSON logging
- `backend/app/middleware/metrics.py` — request timing + error rate
- `docs/deployment.md` — deployment runbook

### DoD
1. `docker compose up --build` starts all services without errors
2. `curl http://localhost:8000/health` returns `{"status":"ok"}` from the containerized backend
3. `curl http://localhost:3000` returns the frontend shell from the containerized frontend
4. CI pipeline config runs `uv run pytest` and `npm test` (validates config syntax / dry-run)
5. Structured logs output JSON to stdout with request_id, timestamp, level
6. `docker compose down` cleans up all containers
7. `docs/deployment.md` exists and documents the startup procedure

### Complexity
Medium

---

## Dependency Graph (visual)

```
SPRINT-001  (Foundation + Auth)
  ├── SPRINT-002  (Locations, Shifts, Registration)
  │     ├── SPRINT-003  (Groups, Waivers, Orientation)
  │     │     ├── SPRINT-006  (QR Check-In)
  │     │     │     ├── SPRINT-007  (Assignment Engine + Run-of-Show)
  │     │     │     │     └── SPRINT-010  (Frontend: Staff Dashboard + Kiosk)
  │     │     │     └── SPRINT-014  (E2E Validation) ←── also depends on 007, 011, 005
  │     │     └── SPRINT-012  (Special-Case Pathways)
  │     │           └── SPRINT-013  (Frontend: Pathway UIs + CRM Dashboard) ←── also depends on 009, 011
  │     └── SPRINT-004  (Discovery Engine)
  │           └── SPRINT-009  (Frontend: Discovery + Signup) ←── also depends on 005, 008
  ├── SPRINT-005  (Messaging + Post-Shift Engagement) ←── also depends on 002
  ├── SPRINT-008  (Frontend Shell + Conversational UI Core)
  │     ├── SPRINT-009
  │     └── SPRINT-010
  └── SPRINT-011  (Raiser's Edge Integration) ←── also depends on 002, 006
        └── SPRINT-013

SPRINT-014  (E2E Validation)
  └── SPRINT-015  (Deployment & Monitoring)
```

---

## Summary

| Sprint | Title | Complexity | FRs | Dependencies |
|--------|-------|-----------|-----|-------------|
| 001 | Core Backend Foundation & Authentication | Medium | FR1,3,5,6 | — |
| 002 | Locations, Shifts & Individual Registration | Medium | FR1,9,16 | 001 |
| 003 | Groups, Waivers & Orientation | Medium-High | FR10,11,12 | 002 |
| 004 | Opportunity Discovery & Preference Matching | Medium | FR7 | 002 |
| 005 | Messaging Engine & Post-Shift Engagement | Medium | FR13,20,21 | 001, 002 |
| 006 | QR Check-In & Onsite Intake | Medium | FR14,15 | 003 |
| 007 | Assignment Planning Engine & Staff Ops View | High | FR17,18,19 | 002, 003, 006 |
| 008 | Frontend Shell & Conversational UI Core | Medium | FR2 | 001 |
| 009 | Frontend: Discovery & Signup Flow | Medium-High | FR2,4,8 | 004, 005, 008 |
| 010 | Frontend: Staff Dashboard, Groups & Kiosk | High | (UI for FR14-19) | 006, 007, 008 |
| 011 | Raiser's Edge NXT Integration & Donor Matching | High | FR22,23,24 | 001, 002, 006 |
| 012 | Special-Case Volunteer Pathways | High | FR25,26,27 | 002, 003 |
| 013 | Frontend: Pathway UIs & CRM Dashboard | Medium | (UI for FR24-27) | 009, 011, 012 |
| 014 | End-to-End Validation & Simulation Harness | High | FR28 | 005, 006, 007, 011 |
| 015 | Deployment Infrastructure & Monitoring | Medium | (operational) | 014 |

**Total: 15 sprints** (within 8-20 target)
**All 28 FRs covered** — see coverage matrix at top.
