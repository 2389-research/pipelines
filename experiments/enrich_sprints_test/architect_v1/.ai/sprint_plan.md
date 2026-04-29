# Merged Sprint Plan — NIFB Volunteer Portal Redesign

## Summary

**Total sprint count:** 16

**Overall approach:** Backend-first with a frontend shell established early (in parallel), followed by feature-complete frontend pages, integrations, and a capstone E2E validation sprint. The plan favors building the full data model and API layer before wiring up UI, which reduces rework and keeps each sprint's scope testable via API-level assertions. The frontend shell lands early enough to unblock UI work in the middle sprints.

**Key decisions made during merge:**

1. **Adopted Claude's dependency ordering** for the operations data model (locations/stations/shifts) landing in Sprint 002, well before check-in (Sprint 006). This directly addresses Critique #1 (GPT had check-in before ops model, requiring rework).

2. **Split special-case pathways** (Critique #2): Skills-based volunteering (with file upload/resume handling) is separated from Court-required and Benefits-related pathways, following Gemini's approach. This reduces per-sprint complexity.

3. **Added individual-level compliance filtering** to the Run-of-Show sprint DoD (Critique #3): Staff can filter checked-in volunteers by "missing waiver" or "incomplete orientation" status.

4. **Strengthened next-commitment DoD** (Critique #4): The "book your next shift" prompt must create a valid registration record, verified by test.

5. **Added match-confidence scoring test** (Critique #5): Unit test verifies that conflicting secondary fields produce a "Low Confidence" flag routing to the exception queue.

6. **Refined group check-in DoD** (Critique #6): Integration test explicitly verifies adding a previously unlisted member (name + contact info) to an existing group registration.

7. **Technology posture:** The plan uses Python/FastAPI for the backend and a modern JS framework for the frontend, consistent with Claude's decomposition, but artifact paths are kept general enough for adaptation. Tech-stack specifics (package manager, test runner) are noted in Sprint 001.

8. **Frontend consolidated into fewer sprints** than GPT/Gemini to keep focus. Three frontend sprints (shell, volunteer flows, staff flows) plus one for pathway/CRM UIs.

---

## FR Coverage Matrix

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
| FR22 | 011 | Volunteer records sync to Raiser's Edge NXT |
| FR23 | 011 | Donor/volunteer record matching |
| FR24 | 011 | Exception workflow for uncertain matches |
| FR25 | 012 | Skills-based volunteering pathway |
| FR26 | 013 | Court-required community service pathway |
| FR27 | 013 | Benefits-related volunteer hours pathway |
| FR28 | 015 | End-to-end validation / simulation harness |

All 28 FRs covered. No orphans.

---

### Sprint 001 — Core Backend Foundation & Authentication

**Scope:** Establish the foundational backend: project scaffolding (FastAPI, SQLAlchemy async, PostgreSQL), core database models (Volunteer, OTP), configuration management, and phone-based OTP authentication with JWT tokens. Includes existing-account detection on duplicate email/phone, a dev OTP bypass, and the test harness (pytest-asyncio + httpx).

**Non-goals:** No shift/location/station models beyond stubs in the ORM. No frontend/UI. No SMS delivery to real phones (dev bypass only). No social login (Google/Apple) implementation — stubs at most.

**Requirements:** FR1 (foundational model), FR3, FR5, FR6

**Dependencies:** None — this is the first sprint.

**Expected Artifacts:**
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

**DoD:**
- [ ] `cd backend && uv run pytest tests/test_config.py -v` passes (settings load from env)
- [ ] `cd backend && uv run pytest tests/test_auth.py -v` passes (OTP send, verify new user, verify returning user, invalid code rejection, register endpoint)
- [ ] `cd backend && uv run pytest tests/test_health.py -v` passes (`/health` returns `{"status":"ok"}`)
- [ ] `POST /auth/register` with an already-registered email returns HTTP 409 with `ACCOUNT_EXISTS` error code
- [ ] `POST /auth/otp/verify` with dev bypass code `000000` returns a JWT for known users and `is_new=true` for unknown users
- [ ] All ORM models in `models.py` import without error: `cd backend && python -c "from app.models import Volunteer, OTP"`
- [ ] `cd backend && uv run ruff check app/ tests/` reports zero errors
- [ ] Total test count ≥ 8

**Validation:**
- `cd backend && uv run pytest -v --tb=short`
- `cd backend && uv run ruff check app/ tests/`

**Complexity:** medium

---

### Sprint 002 — Locations, Shifts & Individual Registration

**Scope:** Build the operational data layer: CRUD for locations, stations (with capacity, labor conditions like standing/sitting), and shifts. Add the registration endpoint so a single volunteer can browse open shifts, register, and cancel. Volunteer profile read/update endpoints land here. This establishes the operational model needed by all downstream sprints (check-in, assignment, run-of-show).

**Non-goals:** No group registration (Sprint 003). No waivers or orientation (Sprint 003). No preference-based matching/recommendation engine (Sprint 004). No frontend.

**Requirements:** FR1 (participation history via registration records), FR9, FR16

**Dependencies:** 001

**Expected Artifacts:**
- `backend/app/routers/volunteers.py` — `/volunteers/me` GET/PATCH
- `backend/app/routers/locations.py` — CRUD for locations + nested stations
- `backend/app/routers/shifts.py` — CRUD + `/shifts/browse` with filters
- `backend/app/routers/registrations.py` — register, cancel, list own
- `backend/app/models.py` — Location, Station (with `environment_type`, `labor_condition`), Shift, Registration models
- `backend/tests/test_volunteers.py`
- `backend/tests/test_locations.py`
- `backend/tests/test_shifts.py`
- `backend/tests/test_registrations.py`

**DoD:**
- [ ] `cd backend && uv run pytest tests/test_volunteers.py -v` passes (get profile, update profile, unauthorized access blocked)
- [ ] `cd backend && uv run pytest tests/test_locations.py -v` passes (create/list/get/update location; create/list stations with capacity and labor conditions)
- [ ] `cd backend && uv run pytest tests/test_shifts.py -v` passes (create shift, browse, filter by location, filter by date, get, update)
- [ ] `cd backend && uv run pytest tests/test_registrations.py -v` passes (register, duplicate blocked, list own, cancel, nonexistent shift 404)
- [ ] Registering for a full shift (max_volunteers reached) returns HTTP 409
- [ ] Cancelled registrations preserve the record (status = `cancelled`, not deleted)
- [ ] Station model includes `labor_condition` field (e.g., standing, sitting, mobile)
- [ ] `cd backend && uv run pytest -v --tb=short` — all tests pass, total count ≥ 20
- [ ] `cd backend && uv run ruff check app/ tests/` reports zero errors

**Validation:**
- `cd backend && uv run pytest -v --tb=short`
- `cd backend && uv run ruff check app/ tests/`

**Complexity:** medium

---

### Sprint 003 — Groups, Waivers & Orientation

**Scope:** Add group volunteer management (create group, group leader flow, group registration linking members to a shift). Implement digital waivers (sign, track completion per volunteer) and orientation tracking (mark viewed, query status). These are prerequisites for the check-in and assignment systems.

**Non-goals:** No QR check-in (Sprint 006). No station assignment logic (Sprint 007). No SMS delivery (Sprint 005). No special-case pathways beyond the `pathway` enum (Sprint 012/013).

**Requirements:** FR10, FR11, FR12

**Dependencies:** 002

**Expected Artifacts:**
- `backend/app/routers/groups.py` — create group, list groups, add/remove members, group registration
- `backend/app/routers/waivers.py` — sign waiver, check waiver status
- `backend/app/routers/orientation.py` — mark orientation viewed, check status
- `backend/app/models.py` — Group, GroupMember, WaiverAcceptance, OrientationCompletion models
- `backend/tests/test_groups.py`
- `backend/tests/test_waivers.py`
- `backend/tests/test_orientation.py`

**DoD:**
- [ ] `cd backend && uv run pytest tests/test_groups.py -v` passes (create group, list groups, add members, group registration links all members to a shift)
- [ ] `cd backend && uv run pytest tests/test_waivers.py -v` passes (sign waiver, duplicate sign idempotent, check waiver status returns signed/unsigned per volunteer)
- [ ] `cd backend && uv run pytest tests/test_orientation.py -v` passes (mark viewed, query completion status, returns false before viewing)
- [ ] Group registration decrements available capacity by group size, not by 1
- [ ] A group leader creating a group of size N can register all N members for a shift in one request
- [ ] Waiver and orientation status are queryable per-volunteer (for downstream check-in gating)
- [ ] `cd backend && uv run pytest -v --tb=short` — all tests pass, total count ≥ 30
- [ ] `cd backend && uv run ruff check app/ tests/` reports zero errors

**Validation:**
- `cd backend && uv run pytest -v --tb=short`
- `cd backend && uv run ruff check app/ tests/`

**Complexity:** medium-high

---

### Sprint 004 — Opportunity Discovery & Preference Matching

**Scope:** Build the guided opportunity discovery engine: accept volunteer preferences (indoor/outdoor/mobile, time-of-day, group size) and return ranked shift recommendations. This is the backend logic for FR7's "conversational matching" — the API that the frontend discovery UX will call.

**Non-goals:** No frontend UX (Sprint 009 builds the conversational UI). No full-text search or keyword matching. No machine learning — rule-based ranking only.

**Requirements:** FR7

**Dependencies:** 002 (shifts and locations must exist to recommend against)

**Expected Artifacts:**
- `backend/app/services/discovery.py` — preference-matching scoring engine
- `backend/app/routers/discovery.py` — `POST /discover` endpoint accepting preferences, returning ranked shifts
- `backend/app/schemas.py` — `DiscoveryRequest`, `DiscoveryResult` schemas
- `backend/tests/test_discovery.py`

**DoD:**
- [ ] `cd backend && uv run pytest tests/test_discovery.py -v` passes (at least 5 test cases)
- [ ] Sending `{"environment": "indoor", "time_of_day": "morning", "group_size": 1}` returns shifts sorted by match score
- [ ] Shifts at capacity are excluded from results
- [ ] Sending empty preferences returns all available shifts (graceful fallback)
- [ ] Response includes match score and explanation snippet per shift
- [ ] `cd backend && uv run pytest -v --tb=short` — all tests pass
- [ ] `cd backend && uv run ruff check app/ tests/` reports zero errors

**Validation:**
- `cd backend && uv run pytest -v --tb=short`
- `cd backend && uv run ruff check app/ tests/`

**Complexity:** medium

---

### Sprint 005 — Messaging Engine & Post-Shift Engagement

**Scope:** Implement the event-driven messaging/notification engine with templates for confirmations, reminders, arrival instructions, and post-shift impact. Build the post-shift engagement endpoints: generate digital impact card data and prompt for next-shift signup (must create a valid registration) or monthly giving opt-in. SMS delivery uses a pluggable adapter (console/log in dev, Twilio-ready interface).

**Non-goals:** No Twilio production integration (adapter interface only). No frontend rendering of impact cards (Sprint 009). No donor system integration for "Serving Hope" membership (Sprint 011).

**Requirements:** FR13, FR20, FR21

**Dependencies:** 001 (contact data), 002 (registration events)

**Expected Artifacts:**
- `backend/app/services/messaging.py` — message template engine + send adapter interface
- `backend/app/services/messaging_adapters.py` — `ConsoleAdapter`, `TwilioAdapter` (stub)
- `backend/app/routers/messages.py` — trigger message send, list message history
- `backend/app/routers/engagement.py` — `GET /engagement/impact-card/{registration_id}`, `POST /engagement/next-commitment`
- `backend/app/models.py` — `Message` model (type, status, sent_at, volunteer_id), `GivingInterest` model
- `backend/tests/test_messaging.py`
- `backend/tests/test_engagement.py`

**DoD:**
- [ ] `cd backend && uv run pytest tests/test_messaging.py -v` passes (send confirmation, send reminder, template rendering with variables, adapter selection)
- [ ] `cd backend && uv run pytest tests/test_engagement.py -v` passes (impact card generation, next-commitment capture creates a valid registration record, monthly-giving opt-in flag)
- [ ] Console adapter logs full message text to stdout (verifiable in test output)
- [ ] Message model records delivery status per volunteer
- [ ] Impact card endpoint returns structured data (shift date, hours, meals-packed equivalent or placeholder metric)
- [ ] `POST /engagement/next-commitment` with a valid shift_id creates a new registration record for the volunteer (Critique #4 fix)
- [ ] `cd backend && uv run pytest -v --tb=short` — all tests pass
- [ ] `cd backend && uv run ruff check app/ tests/` reports zero errors

**Validation:**
- `cd backend && uv run pytest -v --tb=short`
- `cd backend && uv run ruff check app/ tests/`

**Complexity:** medium

---

### Sprint 006 — QR Check-In & Onsite Intake

**Scope:** Build QR-code generation (per registration), QR scanning/check-in endpoint, and the onsite intake flow that captures missing group member details at arrival — including adding entirely new members not in the original registration. Check-in transitions registration status from `registered` to `checked_in` and records the timestamp. Waiver completion is checked at scan time (configurable gating).

**Non-goals:** No station assignment at check-in time (Sprint 007). No frontend check-in kiosk UI (Sprint 010). No orientation enforcement gating (policy TBD — noted in open questions).

**Requirements:** FR14, FR15

**Dependencies:** 003 (groups and waivers must exist; check-in reads waiver/orientation status)

**Expected Artifacts:**
- `backend/app/services/qr.py` — QR code generation (returns PNG bytes or base64)
- `backend/app/routers/checkin.py` — `POST /checkin/scan` (accept QR payload), `POST /checkin/group/{group_id}` (batch check-in), `POST /checkin/group/{group_id}/add-member` (add unlisted member), `POST /checkin/capture-info` (update existing member data)
- `backend/app/schemas.py` — `CheckinRequest`, `GroupCheckinRequest`, `MemberInfoCapture`, `NewMemberCapture`
- `backend/tests/test_checkin.py`
- `backend/tests/test_qr.py`

**DoD:**
- [ ] `cd backend && uv run pytest tests/test_qr.py -v` passes (QR generation returns non-empty bytes, encoded data round-trips correctly)
- [ ] `cd backend && uv run pytest tests/test_checkin.py -v` passes (individual scan, group batch scan, missing-info capture, duplicate scan idempotent, invalid QR rejected)
- [ ] After check-in, `registration.status == "checked_in"` and `registration.checked_in_at` is set
- [ ] Group check-in updates all member registrations in one call
- [ ] Integration test verifies adding a previously unlisted member (name + contact info) to an existing group registration creates a new volunteer record and registration (Critique #6 fix)
- [ ] `POST /checkin/capture-info` updates an existing volunteer record with newly provided name/email/phone
- [ ] If waiver gating is enabled, check-in for a volunteer with incomplete waiver returns HTTP 403
- [ ] `cd backend && uv run pytest -v --tb=short` — all tests pass
- [ ] `cd backend && uv run ruff check app/ tests/` reports zero errors

**Validation:**
- `cd backend && uv run pytest -v --tb=short`
- `cd backend && uv run ruff check app/ tests/`

**Complexity:** medium

---

### Sprint 007 — Assignment Planning Engine & Staff Operations View

**Scope:** Build the constraint-based station assignment engine: given checked-in volunteers, station capacities, labor needs, conditions (standing/sitting), and group-togetherness constraints, produce an optimal initial assignment plan. Add a staff-facing API for the daily "run of show" view (including individual-level compliance status) and override endpoints to reassign individuals.

**Non-goals:** No frontend staff dashboard (Sprint 010). No real-time WebSocket push for live updates. No ML-based optimization — deterministic heuristic/constraint solver.

**Requirements:** FR17, FR18, FR19

**Dependencies:** 002 (stations, shifts), 003 (groups), 006 (check-in status)

**Expected Artifacts:**
- `backend/app/services/assignment.py` — constraint solver: inputs (volunteers, stations, groups, conditions) → assignment map
- `backend/app/routers/assignments.py` — `POST /assignments/generate/{shift_id}`, `GET /assignments/{shift_id}`, `PATCH /assignments/{assignment_id}` (manual override)
- `backend/app/routers/runofshow.py` — `GET /operations/run-of-show?date=YYYY-MM-DD` (aggregated day view), `GET /operations/run-of-show/{shift_id}/compliance` (individual compliance list)
- `backend/app/models.py` — `Assignment` model (volunteer_id, station_id, shift_id, is_manual_override)
- `backend/tests/test_assignment_engine.py` — unit tests for the solver
- `backend/tests/test_assignments_api.py` — integration tests for endpoints
- `backend/tests/test_runofshow.py`

**DoD:**
- [ ] `cd backend && uv run pytest tests/test_assignment_engine.py -v` passes (≥ 6 cases: basic assignment, respects capacity, keeps groups together, accommodates sitting need, handles over-capacity gracefully, handles zero volunteers)
- [ ] `cd backend && uv run pytest tests/test_assignments_api.py -v` passes (generate, get, override, regenerate after override preserves manual assignments)
- [ ] `cd backend && uv run pytest tests/test_runofshow.py -v` passes (returns shifts/stations/counts for a given date, empty date returns empty)
- [ ] Generated assignments do not exceed any station's `max_capacity`
- [ ] All members of a group are assigned to the same station
- [ ] Manual override via PATCH persists and is not overwritten on regenerate
- [ ] Run-of-show API supports filtering checked-in volunteers by "missing waiver" or "incomplete orientation" status (Critique #3 fix)
- [ ] `cd backend && uv run pytest -v --tb=short` — all tests pass
- [ ] `cd backend && uv run ruff check app/ tests/` reports zero errors

**Validation:**
- `cd backend && uv run pytest -v --tb=short`
- `cd backend && uv run ruff check app/ tests/`

**Complexity:** high

---

### Sprint 008 — Frontend Shell & Conversational UI Core

**Scope:** Establish the frontend application: framework scaffolding, routing, design system/component library, and the conversational UI component that powers the guided volunteer experience. The shell integrates with the food bank website branding and provides the "feels native" wrapper for all volunteer-facing pages.

**Non-goals:** No complete page implementations beyond the shell + discovery prototype. No staff/admin pages (Sprint 010). No real API integration (mock data acceptable for this sprint).

**Requirements:** FR2

**Dependencies:** 001 (API contract awareness for auth token handling)

**Expected Artifacts:**
- `frontend/package.json` — project manifest
- `frontend/src/App.tsx` (or equivalent) — app shell with routing
- `frontend/src/components/ConversationalFlow.tsx` — reusable step-by-step guided UI component
- `frontend/src/components/Layout.tsx` — branded shell (NIFB header, nav, footer)
- `frontend/src/lib/api.ts` — API client with auth token injection
- `frontend/src/styles/` — design tokens aligned with NIFB branding
- `frontend/tests/` or `frontend/src/**/*.test.tsx` — component tests
- `frontend/README.md`

**DoD:**
- [ ] `cd frontend && npm test -- --watchAll=false` passes (or equivalent: `pnpm test`, `vitest run`)
- [ ] Layout component renders NIFB-branded header and footer (snapshot or DOM assertion test)
- [ ] ConversationalFlow component renders sequential steps, advances on user input, and emits completion event (unit test)
- [ ] API client attaches `Authorization: Bearer <token>` header when token is present (unit test)
- [ ] App shell renders at `/` without console errors (smoke test)
- [ ] `cd frontend && npm run lint` reports zero errors
- [ ] `cd frontend && npm run build` succeeds with zero errors

**Validation:**
- `cd frontend && npm test -- --watchAll=false`
- `cd frontend && npm run build`
- `cd frontend && npm run lint`

**Complexity:** medium

---

### Sprint 009 — Frontend: Opportunity Discovery & Signup Flow

**Scope:** Build the volunteer-facing discovery and signup pages that wire the conversational UI to the backend discovery and registration APIs. Implements the "opportunities first, then login" flow where a volunteer can browse/filter shifts, pick one, and is prompted to log in or create an account only when they commit. Includes the post-shift engagement screen (impact card display, next-commitment prompt that creates a real registration).

**Non-goals:** No group signup UI (Sprint 010). No staff views (Sprint 010). No check-in kiosk UI (Sprint 010).

**Requirements:** FR2 (continued), FR4, FR8

**Dependencies:** 004 (discovery API), 005 (engagement API), 008 (frontend shell)

**Expected Artifacts:**
- `frontend/src/pages/DiscoverPage.tsx` — preference input → recommended shifts
- `frontend/src/pages/ShiftDetailPage.tsx` — shift info + register CTA
- `frontend/src/pages/AuthPage.tsx` — login/register triggered after shift selection
- `frontend/src/pages/ConfirmationPage.tsx` — registration confirmation
- `frontend/src/pages/ImpactCardPage.tsx` — post-shift impact display + next-commitment
- `frontend/src/hooks/useDiscovery.ts` — API hook for discovery
- `frontend/src/hooks/useRegistration.ts` — API hook for registration
- `frontend/tests/` — page-level integration tests

**DoD:**
- [ ] `cd frontend && npm test -- --watchAll=false` passes (all new page tests)
- [ ] Discovery page submits preferences and renders ranked shift cards (integration test with mocked API)
- [ ] Clicking "Sign Up" on a shift when unauthenticated redirects to AuthPage, then back to registration on success (flow test)
- [ ] ConfirmationPage renders shift details and a "what to bring/where to go" summary (DOM assertion)
- [ ] ImpactCardPage renders impact data and shows "Book Next Shift" + "Join Serving Hope" CTAs (DOM assertion)
- [ ] "Book Next Shift" CTA triggers a registration API call and shows confirmation on success (Critique #4 UI verification)
- [ ] `cd frontend && npm run build` succeeds with zero errors
- [ ] `cd frontend && npm run lint` reports zero errors

**Validation:**
- `cd frontend && npm test -- --watchAll=false`
- `cd frontend && npm run build`
- `cd frontend && npm run lint`

**Complexity:** medium-high

---

### Sprint 010 — Frontend: Staff Dashboard, Group Management & Check-In Kiosk

**Scope:** Build the staff-facing operational views: run-of-show daily dashboard (with individual compliance filtering), station assignment board (with drag-drop override), and check-in kiosk mode for scanning QR codes. Also includes the group management UI for group leaders and the volunteer profile/history page.

**Non-goals:** No Raiser's Edge UI (exception queue is Sprint 014). No special-case pathway admin screens (Sprint 014).

**Requirements:** (UI layer for FR14, FR15, FR17, FR18, FR19 — backend delivered in earlier sprints)

**Dependencies:** 006 (check-in API), 007 (assignment + run-of-show API), 008 (frontend shell)

**Expected Artifacts:**
- `frontend/src/pages/staff/RunOfShowPage.tsx`
- `frontend/src/pages/staff/AssignmentBoardPage.tsx`
- `frontend/src/pages/staff/CheckInKioskPage.tsx`
- `frontend/src/pages/GroupManagePage.tsx`
- `frontend/src/pages/ProfilePage.tsx` — volunteer history & hours
- `frontend/src/components/QRScanner.tsx` — camera-based QR reader component
- `frontend/src/components/DragDropBoard.tsx` — station assignment drag-drop
- `frontend/tests/` — page tests for each

**DoD:**
- [ ] `cd frontend && npm test -- --watchAll=false` passes
- [ ] RunOfShowPage renders shifts grouped by location for a selected date (mock data test)
- [ ] RunOfShowPage supports filtering volunteers by "missing waiver" or "incomplete orientation" status (Critique #3 UI verification)
- [ ] AssignmentBoardPage renders stations as columns with volunteer cards; drag-drop fires PATCH call (interaction test)
- [ ] CheckInKioskPage scans a QR code string and calls `/checkin/scan` (mock integration test)
- [ ] GroupManagePage lists members and allows adding a previously unlisted member with name + contact info (Critique #6 UI verification)
- [ ] ProfilePage shows volunteer name, total hours, and registration history (DOM assertion)
- [ ] `cd frontend && npm run build` succeeds with zero errors
- [ ] `cd frontend && npm run lint` reports zero errors

**Validation:**
- `cd frontend && npm test -- --watchAll=false`
- `cd frontend && npm run build`
- `cd frontend && npm run lint`

**Complexity:** high

---

### Sprint 011 — Raiser's Edge NXT Integration & Donor Matching

**Scope:** Build the CRM integration layer: sync volunteer records to Raiser's Edge NXT, implement donor/volunteer matching (by email and phone with confidence scoring), and surface an exception queue for uncertain matches (below 90% confidence threshold). Uses a pluggable adapter so integration can start with ImportOmatic-style batch export and later upgrade to direct API sync.

**Non-goals:** No replacement of Raiser's Edge stewardship workflows (explicitly out of scope per spec). No real-time bidirectional sync in v1 (one-way: volunteer platform → RE NXT). No donor solicitation features.

**Requirements:** FR22, FR23, FR24

**Dependencies:** 001 (volunteer records), 002 (registration data), 006 (attendance confirmation)

**Expected Artifacts:**
- `backend/app/services/crm_sync.py` — sync orchestrator (batch or event-driven)
- `backend/app/services/crm_adapters.py` — `ImportOMaticAdapter` (CSV export), `RENxtApiAdapter` (stub/real)
- `backend/app/services/donor_matching.py` — matching engine (email, phone, name fuzzy) with confidence scoring
- `backend/app/routers/crm.py` — `POST /crm/sync`, `GET /crm/exceptions`, `POST /crm/exceptions/{id}/resolve`
- `backend/app/models.py` — `SyncRecord`, `MatchException` models
- `backend/tests/test_donor_matching.py`
- `backend/tests/test_crm_sync.py`
- `backend/tests/test_crm_api.py`

**DoD:**
- [ ] `cd backend && uv run pytest tests/test_donor_matching.py -v` passes (exact email match → 100% confidence, phone-only match → high confidence, no match → creates new record, fuzzy name + email → medium confidence)
- [ ] Unit test verifies that a match with conflicting secondary fields (e.g., same email, different phone) results in a "Low Confidence" flag and routes to the exception queue (Critique #5 fix)
- [ ] `cd backend && uv run pytest tests/test_crm_sync.py -v` passes (sync creates records, sync is idempotent, adapter selection works)
- [ ] `cd backend && uv run pytest tests/test_crm_api.py -v` passes (trigger sync, list exceptions, resolve exception)
- [ ] Matches below 90% confidence appear in the exception queue
- [ ] ImportOMaticAdapter generates a valid CSV file with required Raiser's Edge import fields
- [ ] Resolving an exception links the volunteer record to the RE NXT constituent ID
- [ ] `cd backend && uv run pytest -v --tb=short` — all tests pass
- [ ] `cd backend && uv run ruff check app/ tests/` reports zero errors

**Validation:**
- `cd backend && uv run pytest -v --tb=short`
- `cd backend && uv run ruff check app/ tests/`

**Complexity:** high

---

### Sprint 012 — Skills-Based Volunteering Pathway

**Scope:** Implement the skills-based volunteering pathway: application-style flow with resume/file upload, staff review queue with approve/reject workflow, and notification upon approval. This pathway requires file storage handling (resume uploads) which distinguishes it from the compliance-oriented pathways.

**Non-goals:** No court-required or benefits-related pathways (Sprint 013). No SLA enforcement or automated notifications for review queue deadlines.

**Requirements:** FR25

**Dependencies:** 002 (registration foundation), 003 (pathway enum)

**Expected Artifacts:**
- `backend/app/routers/pathways_skills.py` — `POST /pathways/skills-based/apply`, `GET /pathways/skills-based/applications` (staff list), `PATCH /pathways/skills-based/applications/{id}` (approve/reject)
- `backend/app/services/file_upload.py` — file upload handling (local storage in dev, S3-ready interface)
- `backend/app/models.py` — `SkillsApplication` (resume_url, review_status, reviewer_notes)
- `backend/tests/test_pathways_skills.py`
- `backend/tests/test_file_upload.py`

**DoD:**
- [ ] `cd backend && uv run pytest tests/test_pathways_skills.py -v` passes (apply with resume URL, staff can list pending, staff can approve/reject, approved volunteer is notified)
- [ ] `cd backend && uv run pytest tests/test_file_upload.py -v` passes (upload returns URL, file type validation, file size validation)
- [ ] Skills-based applications cannot self-confirm — status starts as `pending` and requires staff action
- [ ] Approved applications transition to `approved` status; rejected to `rejected` with reviewer notes
- [ ] `cd backend && uv run pytest -v --tb=short` — all tests pass
- [ ] `cd backend && uv run ruff check app/ tests/` reports zero errors

**Validation:**
- `cd backend && uv run pytest -v --tb=short`
- `cd backend && uv run ruff check app/ tests/`

**Complexity:** medium

---

### Sprint 013 — Court-Required & Benefits-Related Volunteer Pathways

**Scope:** Implement the two compliance-oriented special-case pathways: court-required community service (dedicated intake with case number, required hours tracking, proof-of-service export) and benefits-related/SNAP volunteer hours (dedicated intake, hour tracking, proof-of-hours output). These share a common "managed intake + hour tracking + proof document" pattern.

**Non-goals:** No automated reporting to external agencies. No SLA enforcement on review queues.

**Requirements:** FR26, FR27

**Dependencies:** 002 (registration foundation), 003 (pathway enum)

**Expected Artifacts:**
- `backend/app/routers/pathways_compliance.py` — `POST /pathways/court-required/intake`, `POST /pathways/benefits/intake`, `GET /pathways/{type}/records` (staff list), `GET /pathways/{type}/records/{id}/proof` (export proof document)
- `backend/app/services/proof_generator.py` — generates proof-of-service / proof-of-hours documents
- `backend/app/models.py` — `CourtServiceRecord` (case_number, required_hours, completed_hours), `BenefitsRecord` (program_type, required_hours, completed_hours)
- `backend/tests/test_pathways_court.py`
- `backend/tests/test_pathways_benefits.py`

**DoD:**
- [ ] `cd backend && uv run pytest tests/test_pathways_court.py -v` passes (intake with case number, hours tracked per shift attendance, proof-of-service document exportable)
- [ ] `cd backend && uv run pytest tests/test_pathways_benefits.py -v` passes (intake with program type, hours tracked, proof-of-hours document generated)
- [ ] Pathway routing correctly tags registrations with the appropriate `VolunteerPathway` enum value
- [ ] Completed hours auto-increment based on checked-in shift attendance
- [ ] `cd backend && uv run pytest -v --tb=short` — all tests pass
- [ ] `cd backend && uv run ruff check app/ tests/` reports zero errors

**Validation:**
- `cd backend && uv run pytest -v --tb=short`
- `cd backend && uv run ruff check app/ tests/`

**Complexity:** medium

---

### Sprint 014 — Frontend: Pathway UIs & CRM Exception Dashboard

**Scope:** Add frontend pages for the three special-case pathways (skills-based application form with file upload, court-service intake, benefits intake) and the staff-facing CRM exception resolution dashboard. Also adds the pathway routing screen that directs volunteers to the correct flow at signup based on their stated purpose.

**Non-goals:** No Raiser's Edge stewardship replacement. No advanced analytics or reporting dashboards.

**Requirements:** (UI layer for FR24, FR25, FR26, FR27 — backend delivered in Sprints 011-013)

**Dependencies:** 009 (signup flow), 011 (CRM exception API), 012 (skills pathway API), 013 (compliance pathway APIs)

**Expected Artifacts:**
- `frontend/src/pages/pathways/SkillsApplyPage.tsx`
- `frontend/src/pages/pathways/CourtIntakePage.tsx`
- `frontend/src/pages/pathways/BenefitsIntakePage.tsx`
- `frontend/src/pages/pathways/PathwayRouterPage.tsx` — "Why are you volunteering?" routing screen
- `frontend/src/pages/staff/CRMExceptionsPage.tsx` — match review + resolve UI
- `frontend/src/pages/staff/ReviewQueuePage.tsx` — skills-based application review
- `frontend/tests/` — page tests

**DoD:**
- [ ] `cd frontend && npm test -- --watchAll=false` passes
- [ ] PathwayRouterPage renders options and navigates to correct sub-page (flow test)
- [ ] SkillsApplyPage submits resume upload and shows "application received" confirmation (DOM assertion)
- [ ] CourtIntakePage collects case number and required hours (form validation test)
- [ ] BenefitsIntakePage collects program type and required hours (form validation test)
- [ ] CRMExceptionsPage lists pending exceptions with confidence scores and allows resolve/dismiss (mock API test)
- [ ] ReviewQueuePage lists pending skills applications and allows approve/reject (mock API test)
- [ ] `cd frontend && npm run build` succeeds with zero errors
- [ ] `cd frontend && npm run lint` reports zero errors

**Validation:**
- `cd frontend && npm test -- --watchAll=false`
- `cd frontend && npm run build`
- `cd frontend && npm run lint`

**Complexity:** medium

---

### Sprint 015 — End-to-End Validation & Simulation Harness

**Scope:** Build the validation/simulation harness that the spec explicitly calls for: simulate a fully planned shift at one location with diverse volunteers (individuals, groups, different preferences, accessibility needs, special pathways), and verify the system moves them through signup → waiver → orientation → check-in → assignment → post-shift engagement → CRM sync without a human in the loop. This is the "perfectly planned shift" acceptance test.

**Non-goals:** No load testing / performance benchmarking. No production data — uses synthetic test fixtures only. No UI-driven E2E (API-level simulation).

**Requirements:** FR28

**Dependencies:** 005 (messaging), 006 (check-in), 007 (assignment engine), 011 (CRM sync), 012 (skills pathway), 013 (compliance pathways)

**Expected Artifacts:**
- `backend/tests/e2e/test_full_shift_simulation.py` — the master end-to-end test
- `backend/tests/e2e/conftest.py` — fixtures for location, stations, shifts, diverse volunteer pool
- `backend/tests/e2e/test_scenarios.py` — individual scenario variants (solo volunteer, large group, accessibility need, skills-based, court-required, benefits)
- `backend/scripts/simulate_shift.py` — standalone script to run the simulation outside pytest
- `docs/validation_report_template.md` — template for recording simulation results

**DoD:**
- [ ] `cd backend && uv run pytest tests/e2e/test_full_shift_simulation.py -v` passes
- [ ] Simulation creates ≥ 20 volunteers (mix of individuals and groups)
- [ ] All volunteers complete: account creation → registration → waiver → orientation → check-in → assignment
- [ ] Assignment engine produces valid assignments (no over-capacity, groups together, seated needs honored)
- [ ] Post-shift messaging is triggered for all checked-in volunteers (verified via console adapter logs)
- [ ] CRM sync processes all volunteer records without errors
- [ ] Exception queue contains expected uncertain matches (seeded test data with conflicting fields)
- [ ] At least one skills-based, one court-required, and one benefits-related volunteer complete their respective pathway flows
- [ ] `cd backend && uv run pytest tests/e2e/ -v --tb=short` — all E2E tests pass
- [ ] `cd backend && python scripts/simulate_shift.py` completes without error and prints summary
- [ ] `cd backend && uv run ruff check tests/e2e/` reports zero errors

**Validation:**
- `cd backend && uv run pytest tests/e2e/ -v --tb=short`
- `cd backend && python scripts/simulate_shift.py`
- `cd backend && uv run ruff check tests/e2e/`

**Complexity:** high

---

### Sprint 016 — Deployment Infrastructure & Monitoring

**Scope:** Containerize the application (Docker), set up CI/CD pipeline configuration, add structured logging, health check probes, and basic monitoring/alerting hooks. Prepare the system for pilot deployment at one location.

**Non-goals:** No production cloud provisioning (infra-as-code stubs only). No CDN or edge caching setup. No custom monitoring dashboards.

**Requirements:** (Operational readiness supporting all FRs for pilot deployment)

**Dependencies:** 015 (validation must pass before deployment prep)

**Expected Artifacts:**
- `Dockerfile` (backend)
- `frontend/Dockerfile` (frontend)
- `docker-compose.yml` — full local stack (backend, frontend, postgres)
- `.github/workflows/ci.yml` (or equivalent CI config)
- `backend/app/middleware/logging.py` — structured JSON logging
- `backend/app/middleware/metrics.py` — request timing + error rate
- `docs/deployment.md` — deployment runbook

**DoD:**
- [ ] `docker compose up --build` starts all services without errors
- [ ] `curl http://localhost:8000/health` returns `{"status":"ok"}` from the containerized backend
- [ ] `curl http://localhost:3000` returns the frontend shell from the containerized frontend
- [ ] CI pipeline config runs `uv run pytest` and `npm test` (validates config syntax / dry-run)
- [ ] Structured logs output JSON to stdout with request_id, timestamp, level
- [ ] `docker compose down` cleans up all containers
- [ ] `docs/deployment.md` exists and documents the startup procedure

**Validation:**
- `docker compose up --build`
- `curl http://localhost:8000/health`
- `curl http://localhost:3000`
- `docker compose down`

**Complexity:** medium

---

## Dependency Graph

```
SPRINT-001  (Foundation + Auth)
  ├── SPRINT-002  (Locations, Shifts, Registration)
  │     ├── SPRINT-003  (Groups, Waivers, Orientation)
  │     │     ├── SPRINT-006  (QR Check-In & Onsite Intake)
  │     │     │     ├── SPRINT-007  (Assignment Engine + Run-of-Show)
  │     │     │     │     └── SPRINT-010  (Frontend: Staff Dashboard + Kiosk) ←─ also 006, 008
  │     │     │     └── SPRINT-011  (Raiser's Edge Integration) ←─ also 001, 002
  │     │     ├── SPRINT-012  (Skills-Based Pathway)
  │     │     └── SPRINT-013  (Court & Benefits Pathways)
  │     └── SPRINT-004  (Discovery Engine)
  │           └── SPRINT-009  (Frontend: Discovery + Signup) ←─ also 005, 008
  ├── SPRINT-005  (Messaging + Post-Shift Engagement) ←─ also 002
  └── SPRINT-008  (Frontend Shell + Conversational UI)
        ├── SPRINT-009
        └── SPRINT-010

SPRINT-009 + 011 + 012 + 013
  └── SPRINT-014  (Frontend: Pathway UIs + CRM Dashboard)

SPRINT-005 + 006 + 007 + 011 + 012 + 013
  └── SPRINT-015  (E2E Validation)
        └── SPRINT-016  (Deployment & Monitoring)
```

---

## Summary Table

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
| 010 | Frontend: Staff Dashboard, Groups & Kiosk | High | (UI: FR14-19) | 006, 007, 008 |
| 011 | Raiser's Edge NXT Integration & Donor Matching | High | FR22,23,24 | 001, 002, 006 |
| 012 | Skills-Based Volunteering Pathway | Medium | FR25 | 002, 003 |
| 013 | Court-Required & Benefits Pathways | Medium | FR26,27 | 002, 003 |
| 014 | Frontend: Pathway UIs & CRM Dashboard | Medium | (UI: FR24-27) | 009, 011, 012, 013 |
| 015 | End-to-End Validation & Simulation Harness | High | FR28 | 005, 006, 007, 011, 012, 013 |
| 016 | Deployment Infrastructure & Monitoring | Medium | (operational) | 015 |

**Total: 16 sprints** (within 8–20 target range)
**All 28 FRs covered** — see coverage matrix at top.
