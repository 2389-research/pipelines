# NIFB Volunteer Platform — Final Sprint Plan

## Summary

**Total Sprints:** 24 (3 bootstrap + 20 feature + 1 capstone)  
**FR Coverage:** FR1–FR83 (all 83 functional requirements mapped)  
**Overall Approach:** Bottom-up build from shared backend through volunteer-facing flows, then staff operations, then integrations, then reporting/engagement. Bootstrap sprints establish toolchain, external services, and end-to-end proof before any feature work.

### Key Merge Decisions

1. **Bootstrap sprints prepended (000–002):** Tech stack is unspecified in the spec, so bootstrap sprints establish language/framework/DB choices, Docker services, and an end-to-end proof.

2. **Opportunity browsing before authentication:** All three decompositions agreed opportunities must be viewable anonymously (FR6, FR8). The merged plan places anonymous opportunity browsing (Sprint 003) before authentication (Sprint 004), fixing the Gemini ordering error where browsing depended on registration.

3. **Auto-assignment fully enforces all FR56 constraints:** The GPT decomposition left group cohesion as "placeholder hooks" and all three decompositions had gaps on accessibility enforcement. The merged plan requires the auto-assignment sprint (Sprint 015) to enforce ALL five FR56 constraints with dedicated DoD items for each.

4. **Group registration split from group check-in:** GPT's SPRINT-010 and Gemini's Sprint 010 both combined group registration with group check-in, violating the 3-subsystem limit. The merged plan splits these into Sprint 011 (group registration + waiver) and Sprint 012 (group check-in + on-site capture + donor flags).

5. **Skills-based intake split from court/SNAP programs:** GPT's SPRINT-019 mixed three unrelated pathways. The merged plan splits into Sprint 019 (skills-based intake) and Sprint 020 (court/SNAP programs).

6. **Staff auth/RBAC explicitly scoped:** The GPT review identified that no decomposition explicitly builds staff authentication. The merged plan adds staff auth to Sprint 005 (embedded UI + website integration) since it establishes the frontend shell and auth context for both volunteer and staff surfaces.

7. **RE NXT integration dependencies corrected:** Gemini's decomposition had RE NXT matching depend on check-in (Sprint 009→015). The merged plan corrects this: RE NXT matching depends on the volunteer record and auth (Sprint 004), not on check-in.

8. **FR69 (donor conversational personalization) gets explicit DoD:** All reviews flagged that donor acknowledgement in the conversational flow was claimed but never verified. The merged plan adds a dedicated DoD item in Sprint 018.

9. **FR22 (proactive open-opportunity SMS) explicitly covered:** The Gemini review flagged this as entirely missing. The merged plan includes it in Sprint 021 (post-shift + engagement SMS).

10. **Capstone sprint validates Section 12 "Big Test":** Both reviews flagged the missing end-to-end integration test. Sprint 023 is a capstone that depends on all other sprints and runs the full Big Test scenario.

11. **Conversational UI integration verified across flows:** The prior critique noted that waiver, orientation, and group flows used vague terms instead of verifying they run inside the conversational framework. The merged plan adds conversational-integration DoD items where applicable.

12. **Group member canonicalization addressed:** The prior critique noted that on-site group members might not integrate into the canonical Volunteer model. Sprint 012 DoD explicitly requires group members to be created as canonical volunteer records.

---

### Sprint 000 — Project Scaffold & Toolchain

**Scope:** Initialize the repository with chosen language/framework, package manager, linter configuration, test harness, and CI skeleton. Since the spec does not prescribe a tech stack, this sprint makes and documents those choices.

**Non-goals:** No application logic, no database, no external services.

**Requirements:** (none — bootstrap)

**Dependencies:** (none)

**Bootstrap:** true

**Expected Artifacts:**
- `package.json` (or equivalent manifest)
- `.eslintrc` / linter config
- `jest.config.*` / test harness config
- `Makefile` or `scripts/` with `make build`, `make test`, `make lint`
- `.github/workflows/ci.yml` (or equivalent CI config)
- `README.md` with setup instructions
- `docs/adr/001-tech-stack.md` — Architecture Decision Record for stack choices

**DoD:**
- [ ] `make build` (or equivalent) completes without errors
- [ ] `make lint` passes with zero warnings on the empty project
- [ ] `make test` runs the test harness successfully (0 tests, 0 failures)
- [ ] CI config file exists and defines build + lint + test steps
- [ ] README documents local setup steps, chosen stack, and available commands
- [ ] ADR documents language, framework, database, test framework, and linter choices with rationale

**Validation:**
```bash
make build && make lint && make test
```

**Complexity:** low

---

### Sprint 001 — External Services & Dev Environment

**Scope:** Set up Docker Compose with the application database (PostgreSQL or equivalent), run initial schema migration tooling, implement health checks, and document environment variables. This sprint establishes the data persistence layer that all feature sprints depend on.

**Non-goals:** No application models, no API endpoints, no UI.

**Requirements:** (none — bootstrap)

**Dependencies:** 000

**Bootstrap:** true

**Expected Artifacts:**
- `docker-compose.yml` — database service definition
- `db/migrations/` — migration tooling scaffold (empty initial migration)
- `src/db/connection.*` — database connection module
- `src/health.*` — health check endpoint
- `.env.example` — documented environment variables

**DoD:**
- [ ] `docker-compose up -d` starts database service without errors
- [ ] Database health check endpoint returns 200 with `{"status":"healthy"}`
- [ ] Application code connects to the database and executes a trivial query (e.g., `SELECT 1`)
- [ ] Migration tooling runs against the database without errors (empty migration)
- [ ] `.env.example` documents all required environment variables with descriptions
- [ ] `make test` still passes (no regressions from Sprint 000)

**Validation:**
```bash
docker-compose up -d
make test
curl http://localhost:$PORT/health
```

**Complexity:** low

---

### Sprint 002 — Hello World End-to-End Proof

**Scope:** Create one API endpoint, one database table, one UI page, and one integration test that exercise the full stack: browser → frontend → API → database → response. This proves the scaffold works end-to-end before feature work begins.

**Non-goals:** No real domain models. This is a throwaway proof, not production code.

**Requirements:** (none — bootstrap)

**Dependencies:** 001

**Bootstrap:** true

**Expected Artifacts:**
- `src/api/hello.*` — sample endpoint
- `db/migrations/002_hello.*` — sample table migration
- `src/ui/HelloPage.*` — sample UI page
- `tests/e2e/hello.test.*` — integration test

**DoD:**
- [ ] Sample API endpoint reads from and writes to the database
- [ ] Sample UI page renders in a browser and calls the API endpoint
- [ ] One passing integration test exercises the full stack: HTTP request → API → DB → response assertion
- [ ] `make test` passes including the new integration test
- [ ] `make build` produces a runnable artifact (server starts and serves the UI page)

**Validation:**
```bash
make build && make test
```

**Complexity:** low

---

### Sprint 003 — Shared Backend, Data Model & Anonymous Opportunity Browsing

**Scope:** Define the core data model (volunteers, shifts, locations, groups) with database migrations. Build the public-facing opportunity listing API (no auth required) and the calendar/list browse UI with urgency signals. Visitors can browse shifts immediately with no login gate, matching NIFB brand styling. This establishes both the data foundation (FR1) and the "Opportunities First" entry point (FR6, FR8).

**Non-goals:** No authentication, no registration, no conversational UI, no SMS. No waiver or orientation flows.

**Requirements:** FR1, FR5, FR6, FR7, FR8, FR19, FR20, FR21, FR74, FR75, FR77

**Dependencies:** 002

**Bootstrap:** false

**Expected Artifacts:**
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

**DoD:**
- [ ] Database migration creates core tables (volunteers, shifts, locations, groups) with appropriate constraints
- [ ] `GET /api/opportunities` returns available shifts with location, time, capacity, and open spots without requiring authentication
- [ ] Calendar view displays shifts across multiple locations with consistent layout
- [ ] List view displays shifts sortable/filterable by date, location, and availability
- [ ] Urgency badges appear on shifts meeting urgency criteria (e.g., <20% spots remaining)
- [ ] UI renders under NIFB domain path with no cross-domain redirects and no "return to website" links
- [ ] CSS theme tokens match NIFB brand values (primary/secondary colors, font-family, spacing documented in theme file)
- [ ] `make test` passes with all new unit and API tests

**Validation:**
```bash
make build && make lint && make test
```

**Complexity:** medium

---

### Sprint 004 — Authentication & Returning User Detection

**Scope:** Implement the multi-method authentication system: phone + SMS verification code (primary), Google sign-in, Apple sign-in, and email + password fallback. Implement returning-user detection that gracefully recognizes existing accounts by phone or email without a create-vs-login fork. Auth is triggered only after a visitor selects a shift (deferred login per FR8). Also establish staff authentication and role-based access control for future staff dashboard sprints.

**Non-goals:** No registration data collection beyond identity. No conversational UI. No waiver or orientation.

**Requirements:** FR8, FR9, FR10, FR11, FR12

**Dependencies:** 003

**Bootstrap:** false

**Expected Artifacts:**
- `src/auth/phone_verification.*` — Phone + SMS OTP auth
- `src/auth/social_auth.*` — Google/Apple OAuth
- `src/auth/email_password.*` — Email + password fallback
- `src/auth/returning_user.*` — Returning user detection logic
- `src/auth/roles.*` — Staff role definitions and RBAC middleware
- `src/middleware/auth.*` — Auth middleware (volunteer + staff)
- `tests/auth/` — Auth unit and integration tests

**DoD:**
- [ ] Phone + SMS OTP flow creates a session for a new user and recognizes/signs in an existing user by phone
- [ ] Google sign-in flow creates or links a volunteer record (integration test with mocked provider)
- [ ] Apple sign-in flow creates or links a volunteer record (integration test with mocked provider)
- [ ] Email + password fallback creates and authenticates a user, linking to existing records when email matches
- [ ] Returning user detection: entering an existing phone or email triggers sign-in, not duplicate account creation
- [ ] Auth is triggered only after shift selection — unauthenticated user can browse opportunities and is prompted to authenticate only upon selecting a specific shift (integration test)
- [ ] Staff RBAC middleware protects a test staff route — unauthenticated and non-staff users receive 403
- [ ] SMS opt-in is captured and stored before any non-transactional outbound SMS (unit test on consent gating)
- [ ] `make test` passes with all auth tests (OTP, OAuth, email/password, returning user, staff RBAC)

**Validation:**
```bash
make test
```

**Complexity:** medium

---

### Sprint 005 — Volunteer Registration, Profile & Website-Embedded UI Shell

**Scope:** Build the embeddable website UI shell (conversational container + browse mode toggle) and the minimal registration flow (name, phone, email only). Implement deferred profile completion for secondary fields. Establish the integrated navigation connecting the entry point, discovery, and (future) volunteer dashboard under a single experience. The registration flow is rendered within the conversational UI framework.

**Non-goals:** No conversational matching logic. No waiver, orientation, or SMS. No group registration.

**Requirements:** FR2, FR13, FR14, FR76

**Dependencies:** 003, 004

**Bootstrap:** false

**Expected Artifacts:**
- `src/ui/conversational/ChatShell.*` — Conversational UI container
- `src/ui/conversational/MessageBubble.*` — Message rendering
- `src/ui/conversational/InputArea.*` — User input component
- `src/ui/conversational/ModeToggle.*` — Conversation ↔ browse toggle
- `src/ui/navigation/AppNav.*` — Integrated navigation (discovery, dashboard, history)
- `src/api/registration.*` — Minimal registration endpoint
- `src/api/profile.*` — Profile completion endpoint (secondary fields)
- `src/services/profile_completion.*` — Profile completion tracking
- `tests/api/registration.test.*`
- `tests/ui/conversational/` — UI component tests

**DoD:**
- [ ] Conversational UI shell renders embedded in a host page with message bubbles, input area, and mode toggle
- [ ] Mode toggle switches between conversational view and calendar browse view without losing state
- [ ] Registration endpoint accepts only name, phone, email and creates a volunteer record (rejects if any missing)
- [ ] Profile completion endpoint accepts and stores secondary fields (address, emergency contact, employer, demographics) — all optional
- [ ] Registration flow is rendered within the conversational UI as a chat-style interaction, not a standalone form page
- [ ] Integrated navigation includes links to discovery, upcoming shifts, and history (dashboard placeholder)
- [ ] Profile completion status is tracked per-volunteer (which deferred fields remain uncollected)
- [ ] `make test` passes with registration, profile, and UI component tests

**Validation:**
```bash
make build && make lint && make test
```

**Complexity:** medium

---

### Sprint 006 — Conversational Matching & Recommendation Engine

**Scope:** Implement the conversational preference capture and shift recommendation logic. Support adaptive, nonlinear conversations where volunteers can lead with any preference (e.g., "I have a group of 20 on Saturday"). Map volunteer responses to matching shifts and return ranked recommendations. Returning volunteers see personalized suggestions based on history.

**Non-goals:** No SMS. No waiver or orientation. No group registration.

**Requirements:** FR15, FR17, FR18

**Dependencies:** 005

**Bootstrap:** false

**Expected Artifacts:**
- `src/services/conversation_engine.*` — Conversation state machine and adaptive logic
- `src/services/recommendation.*` — Shift matching and ranking algorithm
- `src/api/conversation.*` — Conversation API
- `src/ui/conversational/RecommendationCards.*` — Recommended shift display
- `tests/services/conversation_engine.test.*`
- `tests/services/recommendation.test.*`

**DoD:**
- [ ] Conversation engine asks preference questions (activity type, time, location, solo/group) and maps answers to matching shifts
- [ ] Conversation handles nonlinear input (integration test: "I have a group of 20 on Saturday" triggers appropriate follow-up without requiring ordered questions)
- [ ] Recommendation engine returns matching shifts ranked by relevance to stated preferences
- [ ] Returning volunteer with history receives personalized suggestions (preferred locations/shift types) when authenticated
- [ ] User can switch to browse view at any point during conversation and return without losing answers
- [ ] Unit tests for recommendation matching cover at least 5 distinct preference scenarios
- [ ] Integration test: full conversation flow from first question to shift recommendation completes successfully
- [ ] `make test` passes

**Validation:**
```bash
make test
```

**Complexity:** medium

---

### Sprint 007 — Digital Waiver Management

**Scope:** Implement the digital waiver system: in-flow presentation within the conversational UI after shift selection and before confirmation, click-to-sign e-signature with timestamp, attachment to volunteer record, and completion status tracking. Returning volunteers with a completed waiver are not re-prompted.

**Non-goals:** No group waiver handling. No check-in waiver validation. No orientation.

**Requirements:** FR16, FR32, FR33, FR34, FR35

**Dependencies:** 005

**Bootstrap:** false

**Expected Artifacts:**
- `db/migrations/007_waivers.*` — Waiver table
- `src/models/waiver.*` — Waiver model (content, signature, timestamp)
- `src/ui/waiver/WaiverPresentation.*` — Waiver display in conversational flow
- `src/ui/waiver/ESignCapture.*` — Click-to-sign component
- `src/api/waivers.*` — Waiver signing and status endpoints
- `src/services/waiver.*` — Waiver validation logic
- `tests/api/waivers.test.*`
- `tests/services/waiver.test.*`

**DoD:**
- [ ] Waiver content renders within the conversational UI flow after shift selection
- [ ] Click-to-sign captures volunteer consent with timestamp and content hash, attached to volunteer record
- [ ] Waiver completion status is queryable per-volunteer via API
- [ ] Returning volunteer with completed waiver is not prompted to sign again (automated test)
- [ ] Unsigned waiver status returns "incomplete"; signed returns "complete" with timestamp
- [ ] Waiver is presented before shift registration confirmation (ordering enforced in flow)
- [ ] `make test` passes with waiver unit and integration tests

**Validation:**
```bash
make test
```

**Complexity:** medium

---

### Sprint 008 — Orientation Tracking

**Scope:** Implement digital orientation video delivery with verified completion tracking (not just link clicks). Support staff-led in-person orientation as a complementary mode with a staff-facing endpoint to mark completion. Orientation renders within the conversational UI flow.

**Non-goals:** No orientation video content creation. No check-in enforcement. No SMS reminders.

**Requirements:** FR37, FR38

**Dependencies:** 005

**Bootstrap:** false

**Expected Artifacts:**
- `db/migrations/008_orientation.*` — Orientation status table
- `src/models/orientation.*` — Orientation status model
- `src/ui/orientation/VideoPlayer.*` — Orientation video player with completion tracking
- `src/api/orientation.*` — Orientation status endpoints (volunteer + staff)
- `src/services/orientation.*` — Completion verification logic
- `tests/api/orientation.test.*`
- `tests/services/orientation.test.*`

**DoD:**
- [ ] Orientation video renders in the conversational UI with a tracked player
- [ ] Completion is recorded only after verified viewing threshold, not on link click alone (unit test)
- [ ] Orientation completion status is stored on the volunteer record and queryable via API
- [ ] Staff can mark in-person orientation as completed for a volunteer via staff-authenticated API endpoint
- [ ] Both digital and staff-led completion paths set the same orientation status flag
- [ ] `make test` passes with orientation unit and integration tests

**Validation:**
```bash
make test
```

**Complexity:** low

---

### Sprint 009 — SMS Orchestration Core (Transactional)

**Scope:** Implement SMS infrastructure: provider integration (Twilio or equivalent), opt-in/opt-out management with TCPA compliance, and the core transactional message pipeline. Deliver signup confirmation, 24–48 hour pre-shift reminder (with orientation link if incomplete), and optional day-of arrival SMS.

**Non-goals:** No post-shift engagement messages, no impact cards, no open-opportunity alerts. No QR code delivery.

**Requirements:** FR3, FR39, FR40, FR41, FR45

**Dependencies:** 004, 005

**Bootstrap:** false

**Expected Artifacts:**
- `src/sms/provider.*` — SMS provider integration (Twilio adapter + test double)
- `src/sms/opt_in.*` — Opt-in/opt-out management
- `src/sms/templates/confirmation.*` — Signup confirmation template
- `src/sms/templates/reminder.*` — Pre-shift reminder template
- `src/sms/templates/day_of.*` — Day-of arrival template
- `src/sms/scheduler.*` — Timed message scheduler
- `src/api/sms_preferences.*` — Opt-in preferences endpoint
- `tests/sms/` — SMS unit and integration tests

**DoD:**
- [ ] SMS provider integration sends a test message via adapter (integration test with fake provider)
- [ ] Opt-in status is tracked per-volunteer; outbound messages blocked for opted-out volunteers (unit test)
- [ ] Signup confirmation SMS fires immediately after successful registration
- [ ] Pre-shift reminder SMS is scheduled 24–48 hours before shift and includes orientation link when orientation is incomplete
- [ ] Day-of arrival SMS sends logistics info when configured for the shift (toggleable)
- [ ] All outbound SMS includes opt-out instructions per TCPA compliance
- [ ] Web-created volunteer record and SMS-referenced record are the same record (integration test verifying FR1 shared backend)
- [ ] `make test` passes

**Validation:**
```bash
make test
```

**Complexity:** medium

---

### Sprint 010 — Check-In & QR Code System (Individual)

**Scope:** Implement QR code generation and delivery (via SMS and web profile), kiosk/staff-device QR scanning for individual check-in without requiring volunteer login. At check-in, detect incomplete waiver, orientation, and secondary information and prompt appropriately while allowing the volunteer to proceed (permissive policy).

**Non-goals:** No group check-in. No donor recognition at check-in. No station assignment display.

**Requirements:** FR46, FR47, FR51, FR52

**Dependencies:** 007, 008, 009

**Bootstrap:** false

**Expected Artifacts:**
- `src/services/qr_code.*` — QR code generation
- `src/sms/templates/qr_delivery.*` — QR code SMS delivery
- `src/ui/checkin/QRScanner.*` — Kiosk/device QR scanner
- `src/ui/checkin/CheckinFlow.*` — Check-in flow with missing-info prompts
- `src/api/checkin.*` — Check-in API endpoint
- `src/services/checkin_validation.*` — Missing-info detection logic
- `tests/api/checkin.test.*`
- `tests/services/checkin_validation.test.*`

**DoD:**
- [ ] QR code is generated for each registered volunteer and accessible from their web profile
- [ ] QR code is delivered via SMS as part of pre-shift communications
- [ ] Scanning QR code at kiosk/device checks in the volunteer without requiring volunteer login (integration test)
- [ ] Check-in detects incomplete waiver and prompts on-site completion
- [ ] Check-in detects incomplete orientation and flags for staff
- [ ] Check-in detects missing secondary info (address, emergency contact) and prompts for collection
- [ ] Volunteer proceeds through check-in even with missing items — permissive policy enforced (integration test)
- [ ] `make test` passes

**Validation:**
```bash
make test
```

**Complexity:** medium

---

### Sprint 011 — Group Volunteer Registration & Waiver Management

**Scope:** Implement group leader registration (group name, size, contact info, ages, type, date preferences), group identity tracking, and group waiver handling (leader signs for self, members can sign at arrival). Group registration renders within the conversational UI. Individual member names are not required in advance.

**Non-goals:** No group check-in. No on-site member capture. No station assignment.

**Requirements:** FR24, FR25, FR26, FR27, FR36

**Dependencies:** 005, 007

**Bootstrap:** false

**Expected Artifacts:**
- `db/migrations/011_groups.*` — Group registration tables
- `src/models/group.*` — Group model with identity tracking
- `src/models/group_member.*` — Group member model
- `src/api/groups.*` — Group registration and management endpoints
- `src/ui/groups/GroupRegistration.*` — Group leader registration in conversational UI
- `src/services/group_waiver.*` — Group waiver tracking logic
- `tests/api/groups.test.*`
- `tests/services/group_waiver.test.*`

**DoD:**
- [ ] Group leader can register with group name, size, contact info, ages, type, and date preferences via conversational UI
- [ ] Individual member names/details are NOT required at registration time (test: group created with zero member records)
- [ ] Group identity is stored and trackable across the system (group ID persists on shift registration)
- [ ] Group waiver status tracks leader signature separately from member signatures
- [ ] Leader signs waiver for themselves; members can sign individually at arrival (test for both paths)
- [ ] Group registration renders within the conversational UI framework, not as a standalone form
- [ ] `make test` passes

**Validation:**
```bash
make test
```

**Complexity:** medium

---

### Sprint 012 — Group Check-In, On-Site Member Capture & Donor Flags

**Scope:** Implement group check-in flow (leader scans QR, confirms headcount, triggers on-site member capture). Provide quick capture form for collecting member details on tablet/kiosk. Captured group members are created as canonical volunteer records (not orphaned data). Add donor/corporate recognition flag at check-in (staff-only, sourced from pre-matched RE NXT data).

**Non-goals:** No full RE NXT integration — uses pre-matched donor flags only. No station assignment.

**Requirements:** FR48, FR49, FR50

**Dependencies:** 010, 011

**Bootstrap:** false

**Expected Artifacts:**
- `src/ui/checkin/GroupCheckin.*` — Group check-in flow (leader scan → headcount → member capture)
- `src/ui/checkin/MemberCapture.*` — On-site member capture form (tablet/kiosk)
- `src/services/donor_flag.*` — Donor recognition flag lookup
- `src/ui/checkin/DonorBadge.*` — Staff-only donor/corporate badge
- `tests/ui/checkin/group_checkin.test.*`
- `tests/services/donor_flag.test.*`

**DoD:**
- [ ] Group leader QR scan initiates group check-in flow showing registered group size
- [ ] Leader confirms or adjusts headcount at check-in
- [ ] On-site capture form collects name, phone, email for each member not pre-registered
- [ ] Captured group members are created as canonical Volunteer records linked to their group (not orphaned — test verifies record exists in volunteers table)
- [ ] Group member waiver signing is prompted during on-site capture for members without completed waivers
- [ ] Donor/corporate-partner flag appears to staff for volunteers with donor_status populated on their record (test with seeded donor data; live RE NXT population in Sprint 018 — staff-facing only, NOT visible to volunteer — authorization test)
- [ ] `make test` passes

**Validation:**
```bash
make test
```

**Complexity:** medium

---

### Sprint 013 — Location & Station Configuration

**Scope:** Implement staff-facing location and station configuration. Staff define locations, stations within locations, and per-station attributes (max capacity, min staffing, labor/accessibility conditions, notes). Configuration persists and is updated incrementally, not rebuilt weekly.

**Non-goals:** No auto-assignment. No run-of-show. No weekly planning.

**Requirements:** FR53, FR54

**Dependencies:** 003

**Bootstrap:** false

**Expected Artifacts:**
- `db/migrations/013_stations.*` — Station configuration tables
- `src/models/station.*` — Station model with attributes
- `src/api/locations.*` — Location management endpoints (staff-auth)
- `src/api/stations.*` — Station CRUD endpoints (staff-auth)
- `src/ui/staff/LocationConfig.*` — Location configuration UI
- `src/ui/staff/StationConfig.*` — Station configuration UI
- `tests/api/locations.test.*`
- `tests/api/stations.test.*`

**DoD:**
- [ ] Staff can create and edit locations via the staff UI (staff-auth protected)
- [ ] Staff can add stations to a location with max capacity, min staffing, labor conditions, accessibility flags, and notes
- [ ] Station configurations persist across sessions (test: create → retrieve after restart)
- [ ] Station attributes are validated (min staffing ≤ max capacity; required fields enforced)
- [ ] Locations and stations are listable and filterable via API
- [ ] Non-staff users cannot access configuration endpoints (authorization test)
- [ ] `make test` passes

**Validation:**
```bash
make test
```

**Complexity:** low

---

### Sprint 014 — Individual Volunteer End-to-End Flow

**Scope:** Wire together the complete individual volunteer journey: browse opportunities → select shift → authenticate → register (minimal fields) → sign waiver → complete orientation → receive confirmation SMS → receive QR code. This sprint produces no new subsystems but validates the integrated pipeline and fills any gaps between previously-built components. Represents the FR23 end-to-end flow.

**Non-goals:** No group flow integration. No staff operations. No station assignment.

**Requirements:** FR23

**Dependencies:** 006, 007, 008, 009, 010

**Bootstrap:** false

**Expected Artifacts:**
- `tests/e2e/individual_volunteer_flow.test.*` — End-to-end integration test
- `src/services/registration_pipeline.*` — Pipeline orchestrator connecting all flow steps
- Documentation of the complete individual volunteer flow

**DoD:**
- [ ] End-to-end test: anonymous user browses opportunities → selects shift → is prompted to authenticate → registers with name/phone/email → signs waiver → completes orientation → receives confirmation SMS → receives QR code
- [ ] Returning volunteer path: recognized by phone → not asked to re-register → skips completed waiver → sees personalized suggestions
- [ ] All flow steps render within the conversational UI framework
- [ ] Flow gracefully handles partial completion (e.g., user drops off after registration, returns later to complete waiver)
- [ ] `make test` and `make e2e` pass

**Validation:**
```bash
make test && make e2e
```

**Complexity:** medium

---

### Sprint 015 — Auto-Assignment Engine

**Scope:** Implement the algorithm that generates draft station assignment plans from registered volunteers and station configuration. Enforce ALL five FR56 constraints: group cohesion, accessibility compatibility, capacity limits, minimum staffing priority, and balanced distribution. Output is a draft plan requiring explicit staff approval before execution.

**Non-goals:** No staff override UI. No run-of-show. Assignment does not auto-execute.

**Requirements:** FR55, FR56, FR57

**Dependencies:** 011, 013

**Bootstrap:** false

**Expected Artifacts:**
- `src/services/auto_assignment.*` — Assignment algorithm
- `src/models/assignment.*` — Assignment model (volunteer-to-station mapping, draft/published state)
- `src/api/assignments.*` — Assignment generation and retrieval endpoints
- `tests/services/auto_assignment.test.*` — Comprehensive constraint tests

**DoD:**
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

**Validation:**
```bash
make test
```

**Complexity:** high

---

### Sprint 016 — Staff Assignment Review & Override

**Scope:** Build the staff-facing assignment review interface with drag-and-drop volunteer movement between stations, constraint re-validation on every manual change with warnings on violations, assignment locking, and notes/flags on assignments.

**Non-goals:** No run-of-show. No weekly planning. No reporting.

**Requirements:** FR58, FR59, FR60

**Dependencies:** 015

**Bootstrap:** false

**Expected Artifacts:**
- `src/ui/staff/AssignmentBoard.*` — Drag-and-drop assignment review UI
- `src/api/assignment_overrides.*` — Override, lock, and note endpoints
- `src/services/constraint_validator.*` — Post-override constraint checking
- `tests/ui/staff/assignment_board.test.*`
- `tests/services/constraint_validator.test.*`

**DoD:**
- [ ] Staff can view the draft assignment plan with volunteers mapped to stations
- [ ] Staff can drag-and-drop volunteers between stations and the change persists
- [ ] System warns when a manual change violates constraints (over-capacity, group split, accessibility mismatch)
- [ ] Staff can lock an assignment to prevent re-optimization by the auto-assignment engine
- [ ] Staff can add notes and flags to individual assignments
- [ ] Constraint validator re-runs after every manual change (not just on-demand)
- [ ] `make test` passes

**Validation:**
```bash
make test
```

**Complexity:** high

---

### Sprint 017 — Staff Operations Dashboard (Run of Show & Weekly Planning)

**Scope:** Build the daily run-of-show view (all shifts across centers, attendees, assignments, flags, staff assignments, timeline) and the one-week planning view (registrations, staffing status, assignment completion, attention-needed flags). Each staff member sees their relevant operational slice; operations staff sees the full picture. Add CSV export for operational datasets.

**Non-goals:** No RE NXT exception reports. No skills queue. No court/SNAP management.

**Requirements:** FR4, FR61, FR62, FR63, FR82

**Dependencies:** 010, 015, 016

**Bootstrap:** false

**Expected Artifacts:**
- `src/ui/staff/RunOfShow.*` — Daily operations view
- `src/ui/staff/WeeklyPlanning.*` — Weekly planning view
- `src/api/operations.*` — Operational data endpoints
- `src/services/export.*` — CSV export utility
- `tests/ui/staff/run_of_show.test.*`
- `tests/api/operations.test.*`

**DoD:**
- [ ] Run-of-show view displays all shifts for a day with attendee counts, assignment status, and flags per shift
- [ ] Each staff member sees only their assigned location/shifts; operations staff sees all locations (role-based test for both cases)
- [ ] Weekly planning view shows 7-day aggregated view with registrations, staffing gaps, and attention-needed flags
- [ ] Shifts with registrations below minimum staffing are highlighted in both views
- [ ] CSV export produces valid files for run-of-show and weekly planning datasets (golden-file test)
- [ ] `make test` passes

**Validation:**
```bash
make test
```

**Complexity:** high

---

### Sprint 018 — RE NXT Integration & Donor Matching

**Scope:** Implement Raiser's Edge NXT integration: record matching on signup/login using email and phone, auto-linking at ≥90% confidence, donor status tagging on volunteer record, and donor acknowledgement personalization in the conversational flow. Implement the staff-facing exception report for sub-90% matches with confirm/reject/merge actions.

**Non-goals:** No outbound activity sync to RE NXT (Sprint 019). No batch export fallback (Sprint 019).

**Requirements:** FR64, FR65, FR66, FR67, FR68, FR69, FR71, FR72

**Dependencies:** 004, 005, 006

**Bootstrap:** false

**Expected Artifacts:**
- `src/integrations/renxt/client.*` — RE NXT API client
- `src/integrations/renxt/matcher.*` — Record matching logic (email, phone, confidence scoring)
- `src/services/donor_personalization.*` — Donor acknowledgement in conversational flow
- `src/ui/staff/ExceptionReport.*` — Staff exception report UI
- `src/api/renxt.*` — RE NXT match and exception endpoints
- `tests/integrations/renxt/matcher.test.*`
- `tests/services/donor_personalization.test.*`

**DoD:**
- [ ] On signup/login, system queries RE NXT for matching records by email and phone (integration test with mocked RE NXT)
- [ ] Records with ≥90% confidence are auto-linked; <90% are not (unit test with at least 5 match/no-match scenarios)
- [ ] Linked volunteer records are tagged with donor status, giving level, and corporate affiliation
- [ ] Conversational flow displays donor acknowledgement greeting when an early match is found (integration test verifying the UI message appears)
- [ ] Sub-90% matches surface in staff exception report with confidence scores, reasons, and candidate details
- [ ] Staff can confirm, reject, or merge exception matches via the UI with audit logging
- [ ] `make test` passes

**Validation:**
```bash
make test
```

**Complexity:** high

---

### Sprint 019 — RE NXT Activity Sync & Batch Export Fallback

**Scope:** Push new volunteer records, volunteer activity (dates, hours, shifts, locations), and status tags into RE NXT while keeping RE NXT as the donor system of record. Implement the batch-export fallback: if RE NXT API access is limited, generate automated daily/weekly ImportOmatic-formatted export files and still produce exception reporting from the platform side.

**Non-goals:** No new volunteer-facing features. No staff dashboard changes.

**Requirements:** FR70, FR73, FR81

**Dependencies:** 018

**Bootstrap:** false

**Expected Artifacts:**
- `src/integrations/renxt/sync.*` — Outbound activity sync
- `src/integrations/renxt/batch_export.*` — ImportOmatic-formatted batch export
- `src/services/sync_scheduler.*` — Sync job scheduler with retry/backoff
- `tests/integrations/renxt/sync.test.*`
- `tests/integrations/renxt/batch_export.test.*`

**DoD:**
- [ ] Volunteer activity events (registration, check-in, hours) enqueue sync jobs to RE NXT (integration test)
- [ ] Sync job retries on transient failure with configurable backoff (test using fake connector)
- [ ] Batch export job produces ImportOmatic-formatted files on a configurable schedule (golden-file test)
- [ ] Exception reporting remains available even when batch mode is active (test)
- [ ] Automated data export to RE NXT runs on schedule without manual intervention
- [ ] `make test` passes

**Validation:**
```bash
make test
```

**Complexity:** medium

---

### Sprint 020 — Skills-Based Volunteer Intake

**Scope:** Implement the skills-based volunteer application flow: interest capture, resume/file upload, availability and skills capture, acknowledgement with response-time expectation, and queueing for human review. Surface pending applications with time-since-submission aging to staff.

**Non-goals:** No court-required or SNAP flows. No general reporting.

**Requirements:** FR28, FR29

**Dependencies:** 005, 017

**Bootstrap:** false

**Expected Artifacts:**
- `src/api/skills_intake.*` — Skills-based application endpoint
- `src/models/skills_application.*` — Application model with resume storage
- `src/ui/volunteer/SkillsApplication.*` — Skills application form
- `src/ui/staff/SkillsQueue.*` — Staff queue with aging visibility
- `tests/api/skills_intake.test.*`

**DoD:**
- [ ] Skills-based application captures interest, resume upload, availability, and skills (integration test with file upload)
- [ ] Application confirmation shows acknowledgement with response-time expectation message
- [ ] Staff queue lists pending applications sorted by oldest first with time-since-submission
- [ ] Staff can view application details including resume download
- [ ] Staff routes are access-controlled (authorization test)
- [ ] `make test` passes

**Validation:**
```bash
make test
```

**Complexity:** medium

---

### Sprint 021 — Court-Required & SNAP Volunteer Programs

**Scope:** Implement court-required volunteer flow (identify, collect required hours/documentation/supervising entity, route to designated staff member) and SNAP-benefit volunteer flow (flag, track hours, documentation export). Generate hours-verification printouts with print-friendly formatting for both programs.

**Non-goals:** No changes to auto-assignment. No general reporting dashboard.

**Requirements:** FR30, FR31, FR83

**Dependencies:** 005, 017

**Bootstrap:** false

**Expected Artifacts:**
- `src/api/court_snap.*` — Court-required and SNAP endpoints
- `src/models/court_program.*` — Court/SNAP tracking model
- `src/models/snap_program.*` — SNAP tracking model
- `src/ui/volunteer/CourtIntake.*` — Court-required intake form
- `src/ui/volunteer/SnapIntake.*` — SNAP intake form
- `src/services/hours_verification.*` — Printable hours verification generator
- `src/ui/staff/CourtSnapManagement.*` — Staff management view
- `tests/api/court_snap.test.*`
- `tests/services/hours_verification.test.*`

**DoD:**
- [ ] Court-required volunteer flow captures required hours, documentation needs, and supervising entity
- [ ] Court-required volunteers are routed to designated staff member (notification or filtered staff view — test verifies routing)
- [ ] SNAP-benefit volunteers are flagged with hours tracked for compliance documentation
- [ ] Hours-verification printout generates with print-friendly CSS/formatting for both court and SNAP volunteers (golden-file test)
- [ ] Printout includes volunteer name, hours, date range, and NIFB branding
- [ ] `make test` passes

**Validation:**
```bash
make test
```

**Complexity:** medium

---

### Sprint 022 — Volunteer Dashboard, Post-Shift SMS & Engagement

**Scope:** Build the volunteer-facing personal dashboard (hours, history, upcoming shifts, impact stats). Implement post-shift SMS sequence: immediate impact card with personalized data and one-tap social sharing, next-commitment prompt with three upcoming opportunities (~15 min later). Implement open-opportunity SMS alerts, milestone celebrations, and deeper engagement follow-ups. Complete the staff reporting suite (roster/search, registration reports, check-in reports, waiver/orientation status).

**Non-goals:** No new authentication or assignment features. No data warehouse integration.

**Requirements:** FR15, FR22, FR42, FR43, FR44, FR78, FR79, FR80, FR82

**Dependencies:** 009, 010, 014, 017, 018

**Bootstrap:** false

**Expected Artifacts:**
- `src/ui/volunteer/Dashboard.*` — Volunteer personal dashboard
- `src/ui/volunteer/ImpactCard.*` — Shareable digital impact card
- `src/sms/templates/impact_card.*` — Post-shift impact SMS template
- `src/sms/templates/next_commitment.*` — Next-commitment SMS template
- `src/sms/templates/open_opportunity.*` — Open-opportunity alert template
- `src/sms/templates/milestone.*` — Milestone celebration template
- `src/services/impact_data.*` — Personalized impact data generation
- `src/services/social_share.*` — One-tap social sharing link
- `src/ui/staff/Reports.*` — Staff reporting hub (roster, registration, check-in, waiver/orientation status)
- `tests/services/impact_data.test.*`
- `tests/sms/post_shift.test.*`
- `tests/ui/volunteer/dashboard.test.*`

**DoD:**
- [ ] Volunteer dashboard shows hours volunteered, shift history, upcoming shifts, and impact stats
- [ ] Volunteer dashboard is accessible via integrated navigation (same experience as discovery)
- [ ] Post-shift impact SMS fires immediately after shift ends with personalized impact data and social sharing link
- [ ] Next-commitment SMS fires ~15 minutes after impact card with exactly 3 upcoming opportunities
- [ ] Open-opportunity alerts send to opted-in volunteers when shifts need filling (proactive push per FR22)
- [ ] Milestone celebration SMS fires at configured hour milestones
- [ ] Staff reporting hub provides roster/search, registration reports, check-in reports, and waiver/orientation status with CSV export
- [ ] Shareable impact card page renders with volunteer data and is accessible by URL
- [ ] `make test` passes

**Validation:**
```bash
make test
```

**Complexity:** high

---

### Sprint 023 — Integration Verification & Launch Readiness

**Scope:** Full integration test covering the Section 12 "Big Test" scenario with all 9 volunteer profiles through the complete pipeline. End-to-end smoke test of every major flow. Build verification, lint, and full test suite. No new features — this sprint validates that the entire system works together and is ready for single-location pilot deployment.

**Non-goals:** No new features. No multi-location expansion (that follows pilot validation).

**Requirements:** (all — integration verification of FR1–FR83)

**Dependencies:** 000, 001, 002, 003, 004, 005, 006, 007, 008, 009, 010, 011, 012, 013, 014, 015, 016, 017, 018, 019, 020, 021, 022

**Bootstrap:** false

**Expected Artifacts:**
- `tests/e2e/big_test.test.*` — Section 12.1 Big Test scenario (9 volunteer profiles)
- `tests/e2e/smoke.test.*` — Full system smoke test
- `tests/e2e/sms_sequence.test.*` — Complete SMS sequence test (confirmation → reminder → post-shift → next-commitment)
- `docs/pilot_readiness.md` — Pilot deployment checklist

**DoD:**
- [ ] Big Test scenario passes: 9 volunteer profiles (new individual, returning individual, group leader with 15 members, accessibility-needs volunteer, court-required volunteer, SNAP volunteer, skills-based applicant, RE NXT donor match, RE NXT low-confidence match) complete full pipeline
- [ ] Assignment test: mixed-constraint volunteer set produces valid auto-assignment plan; staff override does not break constraints
- [ ] SMS sequence test: full text sequence fires correctly (confirmation → reminder → post-shift impact → next-commitment prompt)
- [ ] `make build` succeeds
- [ ] `make lint` passes with zero warnings
- [ ] `make test` passes with zero failures
- [ ] `make e2e` passes with zero failures
- [ ] Application starts and serves traffic (health check returns 200, UI loads, API responds)
- [ ] System is validated at single pilot location (all flows tested against one location's data)
- [ ] No regressions from any prior sprint

**Validation:**
```bash
make build && make lint && make test && make e2e
curl http://localhost:$PORT/health
```

**Complexity:** low

---

## FR Traceability Matrix

| FR | Sprint(s) | Description |
|----|-----------|-------------|
| FR1 | 003, 009 | Single backend and volunteer record (schema in 003, shared-record integration test in 009) |
| FR2 | 005 | Web conversational UI shell |
| FR3 | 009 | SMS layer (transactional) |
| FR4 | 017 | Staff operations dashboard |
| FR5 | 003 | Embedded in NIFB website |
| FR6 | 003 | Opportunities shown without login |
| FR7 | 003 | Dynamic urgency signals |
| FR8 | 003, 004 | Deferred login gate (browsing in 003, auth-trigger-on-select in 004) |
| FR9 | 004 | Phone + SMS auth |
| FR10 | 004 | Google/Apple sign-in |
| FR11 | 004 | Email + password fallback |
| FR12 | 004 | Returning user detection |
| FR13 | 005 | Minimal registration fields |
| FR14 | 005 | Deferred data collection |
| FR15 | 006, 022 | Returning volunteer personalization (recommendation in 006, dashboard in 022) |
| FR16 | 007 | No waiver re-prompt for completed waivers |
| FR17 | 006 | Conversational preference capture |
| FR18 | 006 | Shift recommendation |
| FR19 | 003 | Calendar/list browse view |
| FR20 | 003 | Consistent calendar across locations |
| FR21 | 003 | Urgency messaging |
| FR22 | 022 | Proactive SMS open-opportunity alerts |
| FR23 | 014 | Individual volunteer end-to-end flow |
| FR24 | 011 | Group leader registration |
| FR25 | 011 | No individual names required in advance |
| FR26 | 011 | Group identity tracking |
| FR27 | 011 | Group waiver tracking |
| FR28 | 020 | Skills-based volunteer intake |
| FR29 | 020 | Skills-based queue staff visibility |
| FR30 | 021 | Court-required volunteer handling |
| FR31 | 021 | SNAP benefit tracking |
| FR32 | 007 | Digital waiver e-sign |
| FR33 | 007 | Waiver after shift selection |
| FR34 | 007 | Click-to-sign with timestamp |
| FR35 | 007, 010 | Waiver status on record (007) + check-in validation (010) |
| FR36 | 011, 012 | Group waiver handling (leader in 011, members at arrival in 012) |
| FR37 | 008 | Orientation video completion tracking |
| FR38 | 008 | Staff-led in-person orientation support |
| FR39 | 009 | Signup confirmation SMS |
| FR40 | 009 | Pre-shift reminder SMS |
| FR41 | 009 | Day-of arrival SMS |
| FR42 | 022 | Post-shift impact card SMS |
| FR43 | 022 | Next-commitment SMS |
| FR44 | 022 | Deeper engagement + milestone SMS + open-opportunity alerts |
| FR45 | 004, 009 | SMS opt-in (consent capture in 004, enforcement in 009) |
| FR46 | 010 | QR code generation + delivery |
| FR47 | 010 | QR scan individual check-in |
| FR48 | 012 | Group leader QR scan check-in |
| FR49 | 012 | On-site group member capture |
| FR50 | 012 | Donor recognition flag at check-in |
| FR51 | 010 | Missing info detection at check-in (waiver, orientation, secondary info) |
| FR52 | 010 | Permissive check-in policy |
| FR53 | 013 | Location/station configuration |
| FR54 | 013 | Persistent station config |
| FR55 | 015 | Auto-assignment draft plan generation |
| FR56 | 015 | All five constraint types enforced (group cohesion, accessibility, capacity, min staffing, balance) |
| FR57 | 015 | Staff review before execution |
| FR58 | 016 | Drag-and-drop override |
| FR59 | 016 | Notes/flags/locking on assignments |
| FR60 | 016 | Constraint re-validation on override |
| FR61 | 017 | Daily run-of-show view |
| FR62 | 017 | Staff operational slice view (role-based) |
| FR63 | 017 | Weekly planning view |
| FR64 | 018 | Real-time RE NXT record linking |
| FR65 | 018 | Donor recognition in volunteer flow |
| FR66 | 018 | Email + phone matching fields |
| FR67 | 018 | Auto-link at ≥90% confidence |
| FR68 | 018 | Donor status tagging on volunteer record |
| FR69 | 018 | Donor acknowledgement in conversational flow |
| FR70 | 019 | Outbound activity sync to RE NXT |
| FR71 | 018 | Exception report for sub-90% matches |
| FR72 | 018 | Exception report detail and actions |
| FR73 | 019 | Batch export fallback (ImportOmatic) |
| FR74 | 003 | NIFB brand matching |
| FR75 | 003 | NIFB domain URL continuity |
| FR76 | 005 | Integrated navigation |
| FR77 | 003 | No external-redirect pattern |
| FR78 | 022 | Volunteer personal dashboard |
| FR79 | 022 | Digital impact cards (shareable) |
| FR80 | 022 | Staff reporting tools |
| FR81 | 019 | Automated RE NXT data export |
| FR82 | 017, 022 | CSV/report export (operations in 017, staff reports in 022) |
| FR83 | 021 | Hours verification printouts (court + SNAP) |

---

## Dependency Graph

```
000 → 001 → 002 → 003 ──┬──→ 004 ──┬──→ 005 ──┬──→ 006 ──→ 014 ──→ 022
                         │          │          ├──→ 007 ──→ 010 ──→ 012 ──→ 022
                         │          │          ├──→ 008 ──→ 010
                         │          │          ├──→ 009 ──→ 010 ──→ 012
                         │          │          ├──→ 011 ──→ 012 ──→ 022
                         │          │          │          └──→ 015 ──→ 016 ──→ 017 ──→ 022
                         │          │          ├──→ 020
                         │          │          └──→ 021
                         │          └──→ 018 ──→ 019
                         └──→ 013 ──→ 015

023 depends on ALL (000–022)
```

### Critical Path
000 → 001 → 002 → 003 → 004 → 005 → 009 → 010 → 012 → 015 → 016 → 017 → 022 → 023

### Parallel Tracks (after Sprint 005)
- **Track A (Volunteer Flows):** 006, 007, 008 → 010 → 014
- **Track B (Groups):** 011 → 012
- **Track C (Operations):** 013 → 015 → 016 → 017
- **Track D (RE NXT):** 018 → 019
- **Track E (Special Programs):** 020, 021

---

## Complexity Distribution

| Complexity | Count | Sprints |
|------------|-------|---------|
| Low | 5 | 000, 001, 002, 008, 013 |
| Medium | 13 | 003, 004, 005, 006, 007, 009, 010, 011, 012, 014, 019, 020, 021 |
| High | 6 | 015, 016, 017, 018, 022, 023 (capstone is low but listed for completeness) |

*(Correction: Sprint 023 capstone is Low complexity)*

| Complexity | Count | Sprints |
|------------|-------|---------|
| Low | 6 | 000, 001, 002, 008, 013, 023 |
| Medium | 13 | 003, 004, 005, 006, 007, 009, 010, 011, 012, 014, 019, 020, 021 |
| High | 5 | 015, 016, 017, 018, 022 |
