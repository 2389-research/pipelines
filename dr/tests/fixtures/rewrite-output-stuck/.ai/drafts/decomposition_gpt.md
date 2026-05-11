# Decomposition — NIFB Volunteer Platform (Implementation Sprints)

Notes/assumptions used for verifiable DoD:
- Repo bootstrap will provide standard commands: `make test`, `make lint`, `make e2e`.
- Each sprint adds/updates automated tests so `make test` (and when applicable `make e2e`) is a concrete validation step.

---

## SPRINT-001 — Embedded Opportunity Discovery (Anon)
**Scope:** Deliver the on-site, no-login volunteer entry experience that immediately shows available opportunities (calendar/list) under the NIFB domain and styled to match NIFB branding. Includes urgency signals (e.g., “high need”) driven by open slots, and consistent cross-location calendar browsing.

**Non-goals:** Authentication, registration, waivers, orientation, SMS, check-in, staff dashboard.

**Requirements covered:** FR2, FR5, FR6, FR7, FR19, FR20, FR21, FR74, FR75, FR76, FR77

**Dependencies:** —

**Expected artifacts:**
- Backend models + API for `Location`, `Opportunity/Shift` availability (read-only)
- Volunteer web UI route(s): `/volunteer` (embedded) with calendar/list toggle
- Styling/theme tokens matching NIFB brand (CSS/theme module)
- Unit tests for availability/urgency computation

**DoD items:**
1. `GET /api/opportunities?from=...&to=...&locationId=...` returns opportunities with capacity + openSpots.
2. Urgency flag rules implemented server-side (e.g., `urgency=HIGH` when openSpots below threshold) and covered by unit tests.
3. Volunteer web page renders opportunity list without requiring login.
4. Calendar view and list view both work across 2+ locations with consistent layout.
5. No cross-domain redirect occurs during browsing (stays on-site paths).
6. UI matches configured theme tokens (snapshot/UI test verifying key typography/colors).
7. Automated tests pass: `make test`.

**Complexity:** medium

---

## SPRINT-002 — Conversational Matching + Recommendations
**Scope:** Add a conversational preference-capture flow that can recommend matching shifts and can be entered/exited at any time to the browse/calendar view. For returning volunteers, include a first-pass personalization heuristic (e.g., prefer past locations/shift types) when generating suggestions.

**Non-goals:** Any authentication changes, payment/donations, waivers/orientation, SMS messaging.

**Requirements covered:** FR17, FR18, FR15, FR19

**Dependencies:** 001

**Expected artifacts:**
- Backend “matching” endpoint/service (e.g., `POST /api/match`) that accepts preference answers
- Conversation state model (minimal) persisted per browser session (or anonymous conversation ID)
- Volunteer UI conversational components + “Switch to calendar” control
- Unit tests for matching rules + returning-personalization heuristic

**DoD items:**
1. `POST /api/match` accepts preference answers and returns ranked opportunities.
2. Conversation supports at least 2 nonlinear branches (test covers branching).
3. UI can switch from conversation to calendar and back without losing current answers.
4. Returning volunteer heuristic applied when an authenticated volunteer is present (covered by unit test with fixture history).
5. Discovery scenario test added (recommendations include expected location/type): `make test`.

**Complexity:** medium

---

## SPRINT-003 — Phone OTP Authentication + Returning User Detection
**Scope:** Implement phone-number-based authentication using SMS verification codes as the primary method, including graceful handling of returning users (no separate “create account vs login” fork). Add SMS opt-in capture/storage required for outbound messaging compliance.

**Non-goals:** Google/Apple login, email/password fallback, shift registration.

**Requirements covered:** FR1, FR9, FR12, FR45

**Dependencies:** 001

**Expected artifacts:**
- Backend endpoints: `POST /api/auth/sms/start`, `POST /api/auth/sms/verify`
- Volunteer identity model keyed by phone + email (returning-user lookup)
- Consent/opt-in fields + audit timestamp
- SMS provider adapter interface + test double
- Auth flow integration in volunteer UI

**DoD items:**
1. `POST /api/auth/sms/start` creates OTP challenge and triggers SMS via provider adapter.
2. `POST /api/auth/sms/verify` creates or resumes a volunteer identity and returns a session.
3. Returning volunteer with same phone is recognized and not forced through a separate “register” fork (automated test).
4. SMS opt-in is explicitly captured and stored before any non-transactional outbound SMS (unit test on consent gating).
5. OTP verification failure modes covered (expired code, wrong code) with tests.
6. Automated tests pass: `make test`.

**Complexity:** medium

---

## SPRINT-004 — Secondary Auth Methods (Google/Apple + Email/Password)
**Scope:** Add Google sign-in and Apple sign-in as secondary authentication methods, plus email/password as a fallback. Ensure all auth methods unify onto the same volunteer record and preserve returning-user detection.

**Non-goals:** Registration/waivers/orientation/SMS campaigns.

**Requirements covered:** FR10, FR11, FR1, FR12

**Dependencies:** 003

**Expected artifacts:**
- OAuth callback endpoints + identity linking logic
- Email/password auth endpoints (secure hashing, reset token plumbing if needed by stack)
- Tests for account linking (same email/phone merges correctly)

**DoD items:**
1. Google OAuth login flow creates/links volunteer identity (integration test with mocked provider).
2. Apple OAuth login flow creates/links volunteer identity (integration test with mocked provider).
3. Email/password signup + login works and links to existing phone/email identity when applicable.
4. Identity-link conflict rules documented in code and covered by unit tests.
5. Automated tests pass: `make test`.

**Complexity:** medium

---

## SPRINT-005 — Shift Registration (Minimal Fields) + Deferred Profile
**Scope:** Implement the core individual registration flow: after selecting a shift, prompt for login (if not already) and collect only name, phone, and email to register. Store secondary profile fields as optional/deferred and expose a minimal “My Profile” area to capture them later.

**Non-goals:** Waiver/orientation, check-in, group flows, staff tools.

**Requirements covered:** FR8, FR13, FR14, FR23

**Dependencies:** 003

**Expected artifacts:**
- Backend endpoints: `POST /api/registrations` and `GET /api/me/registrations`
- Data model for `Registration` (volunteerId, shiftId, status)
- Volunteer UI: “register” step after shift selection; minimal profile page
- Tests for minimal-field requirement and deferred-field allowance

**DoD items:**
1. Registration requires only name/phone/email (server-side validation test).
2. Secondary fields (address, emergency contact, employer, demographics) are optional and can be saved later (test verifies null allowed).
3. `GET /api/me/registrations` returns upcoming registrations for the logged-in volunteer.
4. UI flow: select shift → (login if needed) → minimal registration → success screen.
5. Automated tests pass: `make test`.

**Complexity:** medium

---

## SPRINT-006 — Digital Waiver (Click-to-Sign) + Status Enforcement
**Scope:** Add the digital waiver experience as an in-flow, clickable e-sign step after registration and before final confirmation. Store waiver completion status (timestamp + signed artifact reference) on the volunteer record and do not re-prompt returning volunteers who already completed it.

**Non-goals:** Orientation, check-in scanning, staff-led waiver capture UI.

**Requirements covered:** FR32, FR33, FR34, FR35, FR16

**Dependencies:** 005

**Expected artifacts:**
- Waiver template/versioning model
- Backend endpoint to record e-signature event and attach to volunteer
- Volunteer UI waiver step integrated into registration pipeline
- Tests for waiver gating + “do not re-prompt” behavior

**DoD items:**
1. Waiver is presented during registration after shift selection and before confirmation.
2. Click-to-sign records signer identity + timestamp and persists signed waiver reference.
3. Volunteer record stores waiver completion status and version.
4. Returning volunteer with completed waiver is not prompted again (automated test).
5. Automated tests pass: `make test`.

**Complexity:** medium

---

## SPRINT-007 — Orientation Video + Verified Completion
**Scope:** Implement pre-shift digital orientation delivery with verified completion (not just link click). Support staff-led on-site orientation as an alternate path (recorded as completed by staff or by kiosk flow later).

**Non-goals:** SMS reminder sending (handled separately), check-in enforcement.

**Requirements covered:** FR37, FR38

**Dependencies:** 005

**Expected artifacts:**
- Orientation content configuration (video URL/id) + completion events model
- Backend endpoints to start/complete orientation and verify completion token/event
- Volunteer UI orientation step (player + completion confirmation)
- Tests for “completion requires verified event”

**DoD items:**
1. Orientation completion is stored only after a verified completion event (unit test asserts link-click alone isn’t sufficient).
2. Volunteer UI provides orientation player and records completion.
3. Backend exposes `GET /api/me/orientationStatus` (or equivalent) used by UI.
4. Automated tests pass: `make test`.

**Complexity:** low

---

## SPRINT-008 — Transactional SMS (Confirmation + Reminders + Day-of)
**Scope:** Implement transactional SMS orchestration: immediate signup confirmation, 24–48 hour reminder with logistics and orientation link if incomplete, and optional day-of arrival info. Ensure messages are opt-in compliant and tied to the same backend volunteer record.

**Non-goals:** Post-shift engagement messages, open-opportunity alerts, QR check-in.

**Requirements covered:** FR3, FR39, FR40, FR41, FR45, FR1

**Dependencies:** 003, 005, 007

**Expected artifacts:**
- Message template system (at least confirmation + reminder + day-of)
- Job/scheduler hooks for future-dated reminders
- Tests using a fake SMS provider asserting correct message timing/contents

**DoD items:**
1. Confirmation SMS is sent immediately after successful registration (integration test with fake provider).
2. Reminder SMS is scheduled 24–48 hours pre-shift and includes orientation link only when orientation incomplete.
3. Day-of SMS can be toggled by configuration/flag and is not sent when disabled.
4. SMS send is blocked without opt-in except for strictly transactional messages (policy enforced by tests).
5. Automated tests pass: `make test`.

**Complexity:** medium

---

## SPRINT-009 — QR Issuance + Individual Check-In (Kiosk/Staff Scan)
**Scope:** Deliver QR codes to volunteers via SMS and in their web profile, and implement the happy-path individual check-in by scanning QR on a kiosk/staff device without requiring the volunteer to log in. At check-in, detect missing waiver/orientation/secondary info and prompt/flag while allowing the volunteer to proceed.

**Non-goals:** Group check-in, donor recognition, station assignment.

**Requirements covered:** FR46, FR47, FR51, FR52, FR35

**Dependencies:** 006, 007, 008

**Expected artifacts:**
- QR token issuance + validation model (time-bounded or shift-bounded)
- Kiosk/web route for scanner + check-in result screen
- Backend endpoints: `POST /api/checkin/scan`, `POST /api/checkin/:id/missingInfo` (or equivalent)
- Tests for scan validation + “allow proceed” behavior

**DoD items:**
1. QR code is available in volunteer web profile and included in SMS (test asserts payload contains QR link/token).
2. `POST /api/checkin/scan` checks in a volunteer from a valid QR token (integration test).
3. Scan flow does not require volunteer login on the happy path.
4. Missing waiver/orientation is detected and returned as flags, but check-in still succeeds (test).
5. Automated tests pass: `make test`.

**Complexity:** medium

---

## SPRINT-010 — Group Registration + Group Check-In + On-site Member Capture
**Scope:** Implement the group volunteer pathway: group leader intake (group name, size, ages, type, preferences), group identity tracking for cohesion, and group check-in where leader confirms headcount. Provide on-site quick capture for member details not collected in advance and support group waiver handling (leader signs self; members can sign at arrival).

**Non-goals:** Station assignment engine (cohesion enforcement comes later), RE NXT.

**Requirements covered:** FR24, FR25, FR26, FR27, FR36, FR48, FR49

**Dependencies:** 005, 006, 009

**Expected artifacts:**
- Backend models: `Group`, `GroupRegistration`, `GroupMember` (minimal)
- Volunteer UI: group leader registration flow
- Kiosk flow: group leader scan → confirm headcount → member capture + waiver capture prompts
- Tests for group identity persistence + headcount confirmation

**DoD items:**
1. Group leader can submit required group registration fields (server-side validation tests).
2. System does not require individual member details prior to arrival (test asserts group can be created with zero members).
3. Group leader QR scan initiates group check-in and requests headcount confirmation.
4. Kiosk supports capturing member minimal info on-site (name + optional contact) (test covers payload).
5. Group waiver handling supported: leader waiver separate from member waiver (unit test).
6. Automated tests pass: `make test`.

**Complexity:** medium

---

## SPRINT-011 — Staff Location & Station Configuration
**Scope:** Add staff tooling to define locations and stations within locations, including capacity, minimum staffing, accessibility/labor conditions, and notes. Persist station configuration so it can be reused/updated over time.

**Non-goals:** Auto-assignment algorithm, run-of-show views.

**Requirements covered:** FR53, FR54, FR4 (partial)

**Dependencies:** 001

**Expected artifacts:**
- Backend CRUD for locations/stations (staff-auth protected)
- Staff dashboard screens for station configuration
- Tests for station constraint fields and persistence

**DoD items:**
1. Staff can create/update stations with capacity + minimum staffing + condition flags.
2. Station configuration persists and is editable without recreating weekly (test uses update semantics).
3. Staff routes are access-controlled (authorization test).
4. Automated tests pass: `make test`.

**Complexity:** low

---

## SPRINT-012 — Auto-Assignment Engine v1 + Staff Review Gate
**Scope:** Implement draft station assignment generation from registrations and station configuration with core constraints (capacity + minimum staffing priority + group cohesion placeholder hooks). Require staff review/approval before the plan is considered “published”.

**Non-goals:** Drag/drop UI, advanced balancing, run-of-show.

**Requirements covered:** FR55, FR56 (partial), FR57

**Dependencies:** 010, 011

**Expected artifacts:**
- Backend assignment engine module + endpoint `POST /api/assignments/generate?shiftId=...`
- Assignment plan model with states: `DRAFT`, `PUBLISHED`
- Staff dashboard view to preview draft and publish
- Unit tests for constraint satisfaction (capacity + min staffing)

**DoD items:**
1. Draft assignment generation produces a plan for a shift with registered volunteers.
2. Capacity constraints are enforced (unit test with over-capacity fixture).
3. Minimum staffing is prioritized (unit test verifies under-filled stations are filled first).
4. Plan cannot be marked published without explicit staff action (authorization + state transition tests).
5. Automated tests pass: `make test`.

**Complexity:** high

---

## SPRINT-013 — Assignment Overrides (Drag/Drop) + Constraint Revalidation
**Scope:** Add staff override capabilities: move volunteers between stations, add notes/flags, lock assignments, and revalidate constraints after each change with warnings on violations (over-capacity, split groups, etc.).

**Non-goals:** Optimizing algorithm further; multi-location operational timeline.

**Requirements covered:** FR58, FR59, FR60, FR56 (manual enforcement)

**Dependencies:** 012

**Expected artifacts:**
- Staff UI drag/drop station board (or equivalent)
- Backend endpoints for manual move + lock + notes
- Constraint validation service returning warnings
- Tests for override behavior + validation warnings

**DoD items:**
1. Staff can move a volunteer between stations and the plan persists (integration test).
2. Constraint validator runs after each move and returns warnings for violations (unit test cases).
3. Staff can lock an assignment and subsequent auto-regen respects the lock (test).
4. Staff can attach notes/flags to assignments and retrieve them.
5. Automated tests pass: `make test`.

**Complexity:** high

---

## SPRINT-014 — Staff Operations Views (Run-of-Show + Weekly Planning) + Exports
**Scope:** Provide staff-facing operational visibility: daily run-of-show view (shifts across centers/mobile, attendee/assignment/flag data) and a one-week planning view (registrations, staffing status, assignment completion, issues). Include role-based filtering so staff see relevant slices, and add CSV export for these operational datasets.

**Non-goals:** RE NXT donor matching, exception workflows.

**Requirements covered:** FR61, FR62, FR63, FR82 (partial), FR80 (partial), FR4

**Dependencies:** 012, 013, 009

**Expected artifacts:**
- Staff dashboard pages: Run-of-Show, Weekly Planning
- Backend query endpoints optimized for these aggregated views
- CSV export utility for run-of-show and weekly planning datasets
- Tests for role-based filtering and export format

**DoD items:**
1. Run-of-show endpoint returns shifts with registration counts, check-in counts, and assignment status.
2. Weekly planning endpoint returns 7-day grouped view with “needs attention” flags.
3. Role-based filtering works (test: restricted staff sees subset).
4. CSV export produces deterministic headers/rows for run-of-show dataset (golden-file test).
5. Automated tests pass: `make test`.

**Complexity:** high

---

## SPRINT-015 — RE NXT Matching/Linking + Donor Flags
**Scope:** Implement the RE NXT integration layer for near-real-time matching and linking using email + cell phone with a confidence score. When confidence ≥ 90%, auto-link and tag the volunteer record with donor status/giving level/corporate affiliation, and enable donor acknowledgement hooks in the conversational flow.

**Non-goals:** Exception resolution UI/actions, batch export fallback.

**Requirements covered:** FR64, FR66, FR67, FR68, FR69, FR65 (partial)

**Dependencies:** 003, 005

**Expected artifacts:**
- RE NXT connector client module + mock
- Matching service computing confidence score + reasons
- Volunteer record fields for donor/corporate flags
- Tests for matching logic and 90% auto-link threshold

**DoD items:**
1. Matching query uses email + cell phone and returns confidence + reason codes.
2. Auto-link occurs when confidence ≥ 0.90 and stores RE NXT constituent id (test).
3. No auto-link when confidence < 0.90 (test).
4. Donor flags are stored on volunteer record and available via `GET /api/me` (or equivalent).
5. Automated tests pass: `make test`.

**Complexity:** high

---

## SPRINT-016 — Donor Recognition at Check-In + Exception Report UI + Manual Resolution
**Scope:** Cross-reference check-ins with RE NXT and display donor/corporate recognition flags to staff (not volunteers). Provide a staff exception report for sub-90% potential matches with candidate matches, confidence reasons, and actions to confirm/reject/merge.

**Non-goals:** ImportOmatic batch export formatting, broad reporting suite.

**Requirements covered:** FR50, FR71, FR72, FR65, FR67

**Dependencies:** 015, 009

**Expected artifacts:**
- Staff check-in monitor view shows donor flags (staff-only)
- Exception report page + backend endpoints to list and resolve matches
- Audit log of manual resolution actions
- Tests for staff-only visibility + resolution state transitions

**DoD items:**
1. Donor recognition flags appear in staff view for a checked-in volunteer and are not present in volunteer kiosk view (authorization test).
2. Exception report lists sub-90% candidates with confidence + reason codes.
3. Staff can confirm a match and system links records (integration test).
4. Staff can reject a match and it no longer appears as pending (test).
5. Manual actions are audit-logged with timestamp + staff user id (test).
6. Automated tests pass: `make test`.

**Complexity:** high

---

## SPRINT-017 — RE NXT Sync (Activity Push) + Batch Export Fallback (ImportOmatic)
**Scope:** Push new volunteer records and volunteer activity into RE NXT automatically while treating RE NXT as donor system of record. If API access is limited/unavailable, produce scheduled batch exports formatted for ImportOmatic ingestion and still generate exception reporting from the platform side.

**Non-goals:** Full data warehouse integration.

**Requirements covered:** FR70, FR73, FR81

**Dependencies:** 015

**Expected artifacts:**
- Background job(s) for activity sync and retry/backoff
- Batch export generator producing ImportOmatic-compatible files
- Operational logging/metrics for sync status
- Tests for export formatting and job retry semantics

**DoD items:**
1. Volunteer activity events (registration, check-in, hours) enqueue sync jobs (unit/integration test).
2. Sync job retries on transient failure with backoff (test using fake connector).
3. Batch export job produces a deterministic file for ImportOmatic (golden-file test).
4. Exception reporting remains available even when batch mode is enabled (test).
5. Automated tests pass: `make test`.

**Complexity:** medium

---

## SPRINT-018 — Staff Reporting Suite v1 (Roster/Search, Status Reports, CSV Framework)
**Scope:** Deliver staff-facing reporting tools: volunteer roster/search, shift registration reports, check-in reports, waiver/orientation completion status, and station assignment plan views—each with CSV export support via a shared export framework.

**Non-goals:** Court/SNAP verification printouts (handled later), skills queue.

**Requirements covered:** FR80 (partial), FR82

**Dependencies:** 005, 006, 007, 009, 012, 013

**Expected artifacts:**
- Staff dashboard modules: roster/search, check-in report, waiver/orientation status report, assignment plan report
- Shared CSV export helper used by all staff datasets
- Tests for search/filter correctness + CSV export headers

**DoD items:**
1. Staff roster/search supports search by name, phone, or email (tests cover each).
2. Staff can view per-shift check-in report (endpoint + UI).
3. Staff can view waiver/orientation completion status report with filters (test).
4. CSV export works for at least 3 datasets using the shared export helper (test verifies shared path).
5. Automated tests pass: `make test`.

**Complexity:** medium

---

## SPRINT-019 — Skills-Based Intake + Court/SNAP Programs (Tracking + Documentation)
**Scope:** Implement the skills-based volunteer application pathway (interest capture, resume upload, availability/skills, acknowledgement, queueing for human review) with staff visibility into pending applications and time-since-submission. Add special program routing for court-required and SNAP-benefit volunteers: flagging, hours tracking, staff routing, and printable/exportable verified-hours documentation.

**Non-goals:** Donor integration changes, auto-assignment changes.

**Requirements covered:** FR28, FR29, FR30, FR31, FR83

**Dependencies:** 005, 018

**Expected artifacts:**
- Skills application model + resume upload/storage adapter
- Staff queue UI (skills applications) with “age” sorting
- Court/SNAP flags on volunteer + hours ledger model
- Verification printout/export (PDF/HTML-to-print) for court/SNAP
- Tests for file upload, queue aging, and hours verification output

**DoD items:**
1. Skills-based application can be submitted with resume upload (integration test with fake storage).
2. Staff queue lists pending applications and shows time-since-submission; default sort by oldest (test).
3. Court-required volunteer flag captures required hours + supervising entity and routes to configured staff role (test).
4. SNAP volunteer hours are tracked and exportable (test for hours ledger totals).
5. Verified-hours documentation can be generated for a given volunteer/date range (golden-file test for output).
6. Automated tests pass: `make test`.

**Complexity:** medium

---

## SPRINT-020 — Volunteer Dashboard + Post-Shift Engagement SMS (Impact + Next Commitment + Alerts)
**Scope:** Provide the volunteer-facing dashboard (upcoming shifts, shift history, hours, impact stats) and shareable digital impact cards. Implement post-shift and ongoing SMS engagement: immediate impact message linking to the impact card, a next-commitment message with 3 recommended upcoming opportunities, and opt-in open-opportunity alerts/milestone messages.

**Non-goals:** Additional staff operational workflows beyond message configuration.

**Requirements covered:** FR78, FR79, FR42, FR43, FR44, FR22, FR3

**Dependencies:** 002, 008, 009

**Expected artifacts:**
- Volunteer dashboard UI pages + backend aggregation endpoints
- Impact card generator (shareable URL + metadata)
- SMS templates for post-shift impact, next-commitment, alerts/milestones
- Job triggers based on shift end time + opt-in state
- E2E test for “post-shift message → impact card → next commitment recs”

**DoD items:**
1. Volunteer dashboard shows upcoming shifts and history sourced from registrations/check-ins (integration test).
2. Volunteer hours totals computed from checked-in shifts (unit test for aggregation).
3. Impact card page renders with volunteer + shift impact data and is shareable by URL (snapshot test).
4. Post-shift SMS is sent immediately after shift completion and links to impact card (integration test with fake SMS provider).
5. Next-commitment SMS is sent ~15 minutes later containing exactly 3 recommended opportunities (test asserts count and relevance).
6. Open-opportunity alerts/milestones send only to opted-in volunteers (consent gating test).
7. Automated tests pass: `make test`.
8. End-to-end scenario test passes: `make e2e` (post-shift engagement flow).

**Complexity:** medium
