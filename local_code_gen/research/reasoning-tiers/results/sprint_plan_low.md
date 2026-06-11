# Merged Sprint Plan — Food Bank Volunteer Portal Redesign

This plan comprises **14 sprints** (001–014) synthesized from three independent decompositions (Claude, Gemini, GPT) and six cross-critiques. The overall approach is sequential foundation → public UX → authentication → pathways (split across two sprints to manage complexity) → messaging → waiver/orientation → check-in → ops configuration → assignment planning → staff dashboard → post-shift engagement → Raiser's Edge NXT integration → full end-to-end simulation. Key merge decisions: pathways were split into individual/group (005) and special cases (006) per critique of overloaded sprint sizing; RE NXT integration (013) was separated from engagement (012); full simulation (014) was separated from RE NXT per cross-critique; FR29 donor recognition was moved earlier into the auth sprint (004) with full implementation in 013; FR8 video-based instructions are explicitly covered in the messaging sprint (007); and FR34 prototype artifact review is addressed in Sprint 001. Stack: Next.js 14 (App Router), TypeScript, Prisma + PostgreSQL, Vitest, Playwright, Tailwind + shadcn/ui, Twilio, pnpm.

---

### Sprint 001 — Repo Scaffold & CI Foundation

**Scope:** Initialize the Next.js 14 + TypeScript + pnpm project with ESLint, Prettier, Vitest, and Playwright configured. Set up Docker Compose for PostgreSQL, initialize Prisma with an empty schema, create a seed placeholder, and establish a CI script for lint/typecheck/tests. Review the Galaxy Digital transcript as a provocation artifact per FR34.

**Non-goals:** Any product features or UI beyond a health-check route.

**Requirements:** FR34

**Dependencies:** None

**Expected Artifacts:**
- `package.json`
- `next.config.ts`
- `tsconfig.json`
- `.eslintrc.js`
- `vitest.config.ts`
- `playwright.config.ts`
- `docker-compose.yml`
- `prisma/schema.prisma`
- `prisma/seed.ts`
- `.env.example`
- `src/app/api/health/route.ts`
- `docs/ARCHITECTURE.md`

**DoD:**
- [ ] `pnpm install` completes without errors
- [ ] `pnpm lint` passes with zero warnings
- [ ] `pnpm typecheck` passes
- [ ] `pnpm test` passes (at least 1 sample unit test)
- [ ] `pnpm playwright test` passes (1 smoke test loads `/`)
- [ ] `prisma migrate dev` succeeds
- [ ] `docker compose up` starts PostgreSQL
- [ ] Health-check route returns 200
- [ ] `docs/ARCHITECTURE.md` references Galaxy Digital transcript as provocation input

**Validation:** `pnpm lint && pnpm typecheck && pnpm test && pnpm playwright test`

**Complexity:** Low

---

### Sprint 002 — Domain Data Model & API Skeleton

**Scope:** Implement the full Prisma schema covering all core domain entities (Volunteer, Opportunity, Shift, Station, Group, GroupMember, Waiver, OrientationRecord, Signup, CheckInEvent, Assignment, MessageEvent, ImpactCard, RaisersEdgeSyncEvent, MatchException). Create route handlers for opportunity listing and detail. Seed sample opportunities and shifts.

**Non-goals:** Auth, SMS, waivers, or UI pages beyond API verification.

**Requirements:** None directly (data foundation sprint).

**Dependencies:** 001

**Expected Artifacts:**
- `prisma/schema.prisma` (full model)
- `src/app/api/opportunities/route.ts`
- `src/app/api/opportunities/[id]/route.ts`
- `prisma/seed.ts` with sample data
- `src/lib/db.ts`

**DoD:**
- [ ] `prisma migrate dev` applies all migrations successfully
- [ ] Seed script populates dev database
- [ ] `GET /api/opportunities` returns seeded data
- [ ] `GET /api/opportunities/[id]` returns a single opportunity
- [ ] Vitest covers repository/service functions
- [ ] Playwright test verifies opportunities API returns data

**Validation:** `pnpm prisma migrate dev && pnpm test && pnpm playwright test`

**Complexity:** Medium

---

### Sprint 003 — Public Landing & Opportunity Discovery

**Scope:** Build the public-facing landing page with food-bank-integrated look and feel, opportunity browse/search/filter page, shift detail page, and a guided preference quiz (inside/outside, time of day, group size) that filters and recommends shifts. Visual browsing is accessible without taking the quiz.

**Non-goals:** Account creation, booking/registration, SMS.

**Requirements:** FR1, FR2, FR4, FR22, FR23

**Dependencies:** 002

**Expected Artifacts:**
- `src/app/page.tsx`
- `src/app/opportunities/page.tsx`
- `src/app/opportunities/[id]/page.tsx`
- `src/components/OpportunityCard.tsx`
- `src/components/PreferenceQuiz.tsx`
- `src/lib/opportunities.ts`

**DoD:**
- [ ] Landing page renders without errors
- [ ] Opportunity list loads from database
- [ ] Preference quiz filters results correctly
- [ ] Visual browse accessible without taking quiz
- [ ] No login required to view opportunities (FR4)
- [ ] Responsive mobile layout renders correctly
- [ ] Vitest passes for filter/recommendation logic
- [ ] Playwright test: landing → quiz → filtered results → shift detail

**Validation:** `pnpm test && pnpm playwright test --grep "discovery"`

**Complexity:** Medium

---

### Sprint 004 — Authentication & Progressive Profile

**Scope:** Implement NextAuth with email magic link, Google OAuth, and a phone OTP stub (mocked Twilio provider). Build minimal-field signup (name, email, phone), returning-user detection with clear "email already exists" guidance, session management, and a profile page with progressive field collection. Add a donor recognition hook: on auth, check if the volunteer's email matches a known RE NXT donor flag stored locally and tag the session accordingly.

**Non-goals:** Full OAuth beyond Google, full RE NXT integration, pathway routing.

**Requirements:** FR3, FR5, FR6, FR29 (partial — early recognition hook)

**Dependencies:** 003

**Expected Artifacts:**
- `src/lib/auth.ts`
- `src/app/auth/signup/page.tsx`
- `src/app/auth/login/page.tsx`
- `src/app/auth/verify/page.tsx`
- `src/app/profile/page.tsx`
- `src/components/AuthForm.tsx`
- `src/components/ProfileForm.tsx`
- `src/lib/volunteer.ts`

**DoD:**
- [ ] Signup with name/email/phone creates volunteer record
- [ ] Duplicate email shows clear guidance message
- [ ] Phone OTP stub interface exists (mocked provider)
- [ ] Google OAuth login works
- [ ] Session persists across page navigations
- [ ] Logout clears session
- [ ] Profile page renders for authenticated user
- [ ] Progressive fields save incrementally
- [ ] Donor recognition flag checked on login and visible to staff
- [ ] Vitest passes for auth logic and profile CRUD
- [ ] Playwright test: signup → session → profile edit → logout
- [ ] Playwright test: existing email → guided to login

**Validation:** `pnpm test && pnpm playwright test --grep "auth"`

**Complexity:** High

---

### Sprint 005 — Pathway Routing: Individual & Group Signup

**Scope:** Implement the pathway router to detect individual vs. group volunteers. Build the individual shift registration flow and the group signup flow allowing deferred participant details (placeholder members). Include a group lead view showing tentative vs. confirmed slots and capacity management for group reservations.

**Non-goals:** Skills-based, court-required, or benefit-hours pathways; waivers; check-in.

**Requirements:** FR11, FR12

**Dependencies:** 004

**Expected Artifacts:**
- `src/lib/pathwayRouter.ts`
- `src/app/signup/individual/page.tsx`
- `src/app/signup/group/page.tsx`
- `src/components/GroupSignup.tsx`

**DoD:**
- [ ] Router correctly identifies individual vs. group pathway
- [ ] Individual can register for a shift
- [ ] Group lead can reserve slots without all member names
- [ ] Tentative vs. confirmed slot tracking works
- [ ] Capacity correctly accounts for group reservations
- [ ] Vitest passes for routing logic and capacity management
- [ ] Playwright test: individual signup flow completes
- [ ] Playwright test: group signup with deferred names reaches confirmation

**Validation:** `pnpm test && pnpm playwright test --grep "pathway"`

**Complexity:** Medium

---

### Sprint 006 — Special Pathways: Skills, Court-Required, Benefit-Hours

**Scope:** Build the skills-based volunteer pathway with resume upload and a "needs review" status, the court-required community service pathway with case worker info capture, and the benefit-hours pathway with configurable required fields. Include a basic admin page listing special-case submissions for staff review.

**Non-goals:** Sophisticated review workflows, automated approval logic.

**Requirements:** FR13, FR14, FR15

**Dependencies:** 005

**Expected Artifacts:**
- `src/app/signup/skills/page.tsx`
- `src/app/signup/court/page.tsx`
- `src/app/signup/benefit/page.tsx`
- `src/components/ResumeUpload.tsx`
- `src/app/admin/submissions/page.tsx`

**DoD:**
- [ ] Skills pathway accepts and stores resume file upload
- [ ] Court-required pathway collects case worker info
- [ ] Benefit-hours pathway collects required fields
- [ ] All special pathways tag volunteer record with correct pathway type
- [ ] Admin submissions page lists pending special-case signups
- [ ] Vitest passes for form validation per pathway
- [ ] Playwright test: skills path uploads resume → sees "needs review"
- [ ] Playwright test: court path submits with case worker info

**Validation:** `pnpm test && pnpm playwright test --grep "special-pathway"`

**Complexity:** Medium

---

### Sprint 007 — SMS/Messaging Layer

**Scope:** Build a message template system and Twilio provider abstraction (mock + real adapter). Implement event triggers for signup confirmation, scheduled pre-shift reminders, arrival guidance SMS with directions and video link (FR8 explicit), and a post-shift follow-up placeholder. Add a background job runner (cron endpoint) and a Twilio webhook for delivery status callbacks.

**Non-goals:** Impact cards, RE NXT sync, re-engagement content.

**Requirements:** FR7, FR8

**Dependencies:** 004

**Expected Artifacts:**
- `src/lib/messaging.ts`
- `src/lib/messageTemplates.ts`
- `src/lib/messageScheduler.ts`
- `src/app/api/webhooks/twilio/route.ts`

**DoD:**
- [ ] Confirmation SMS queued on signup
- [ ] Pre-shift reminder scheduled at configured time
- [ ] Arrival guidance SMS includes directions and video link (FR8)
- [ ] Message templates render correctly with volunteer data
- [ ] Webhook handles delivery status callbacks
- [ ] Vitest passes for template rendering, scheduler logic, and provider mock
- [ ] Playwright test: after signup, confirmation message event exists in database

**Validation:** `pnpm test && pnpm playwright test --grep "messaging"`

**Complexity:** Medium

---

### Sprint 008 — Digital Waiver & Orientation Tracking

**Scope:** Build the digital waiver form with e-signature capture (typed name + checkbox), attach waiver completion with timestamp to the volunteer record. Build an orientation content page with video embed and completion tracking. Create a prerequisite validation API that downstream components (check-in) can query to verify waiver + orientation completion.

**Non-goals:** Legal e-sign integrations, SCORM, check-in integration.

**Requirements:** FR9, FR10, FR33 (intermediate milestone)

**Dependencies:** 005

**Expected Artifacts:**
- `src/app/waiver/page.tsx`
- `src/app/orientation/page.tsx`
- `src/lib/waiver.ts`
- `src/lib/orientation.ts`
- `src/components/WaiverForm.tsx`
- `src/components/OrientationPlayer.tsx`

**DoD:**
- [ ] Waiver form submits and attaches signature + timestamp to volunteer record
- [ ] Orientation page tracks completion when video content is consumed
- [ ] Prerequisite status queryable via API endpoint
- [ ] Unsigned waiver status is distinguishable from signed
- [ ] Vitest passes for waiver/orientation status logic and prerequisite guard
- [ ] Playwright test: sign waiver → complete orientation → verify both complete via API

**Validation:** `pnpm test && pnpm playwright test --grep "waiver-orientation"`

**Complexity:** Medium

---

### Sprint 009 — QR Check-In & On-Site Data Capture

**Scope:** Generate unique QR codes per signup/group registration. Build a staff-facing check-in page that scans or manually enters a QR code and resolves it to the volunteer record. Display an on-site capture form for missing information (group member names, unsigned waivers). Enforce waiver/orientation prerequisites with a staff override option (with reason field). Ensure captured data is saved and flagged for later RE NXT sync.

**Non-goals:** Kiosk hardware integration, station assignment at check-in.

**Requirements:** FR16, FR17

**Dependencies:** 008

**Expected Artifacts:**
- `src/app/checkin/page.tsx`
- `src/app/checkin/scan/page.tsx`
- `src/lib/checkin.ts`
- `src/lib/qrcode.ts`
- `src/components/QRScanner.tsx`
- `src/components/OnsiteCapture.tsx`

**DoD:**
- [ ] QR code generated for each registration
- [ ] Scanning QR resolves to correct volunteer record
- [ ] Missing-info form appears for incomplete data
- [ ] Group check-in handles multiple participants
- [ ] Waiver/orientation prerequisites enforced (with override reason field)
- [ ] Check-in status updates in database
- [ ] On-site captured data (email, phone) saved and flagged for RE sync
- [ ] Vitest passes for QR generation and check-in state machine
- [ ] Playwright test: generate QR → scan → check-in complete
- [ ] Playwright test: group check-in adds missing members

**Validation:** `pnpm test && pnpm playwright test --grep "checkin"`

**Complexity:** High

---

### Sprint 010 — Station Configuration & Assignment Planning

**Scope:** Build admin CRUD for stations with capacities, labor needs, and constraints (accessibility/sitting-only). Associate stations with shifts. Implement an auto-assignment algorithm respecting group cohesion, accessibility constraints, and capacity limits. Provide a staff override/adjustment UI for generated plans that shows constraint reasons for each assignment (addressing the cross-critique about visibility of WHY assignments were made).

**Non-goals:** ILP/optimization solver, cross-day dashboard, real-time updates.

**Requirements:** FR18, FR19, FR20

**Dependencies:** 002, 009

**Expected Artifacts:**
- `src/app/admin/stations/page.tsx`
- `src/app/admin/planning/page.tsx`
- `src/lib/stationConfig.ts`
- `src/lib/assignmentPlanner.ts`
- `src/components/StationEditor.tsx`
- `src/components/PlanOverride.tsx`

**DoD:**
- [ ] Admin can create, edit, and delete stations with capacity and constraint fields
- [ ] Planner generates valid assignments not exceeding station capacity
- [ ] Groups are kept together in assignments
- [ ] Accessibility/sitting-only constraints are respected
- [ ] Staff can override individual assignments after plan generation
- [ ] Override UI shows constraint reasons for each assignment
- [ ] Vitest passes for planner edge cases (over-capacity, accessibility, group split)
- [ ] Playwright test: configure stations → run planner → override assignment

**Validation:** `pnpm test && pnpm playwright test --grep "planning"`

**Complexity:** High

---

### Sprint 011 — Run-of-Show Staff Dashboard

**Scope:** Build the daily operations dashboard showing all shifts across centers and mobile opportunities, with real-time check-in counts, station assignment status, multi-location filtering, and quick-action links to check-in and planning pages.

**Non-goals:** Analytics/report exports, editing plans (use Sprint 010), volunteer-facing views.

**Requirements:** FR21

**Dependencies:** 009, 010

**Expected Artifacts:**
- `src/app/admin/dashboard/page.tsx`
- `src/lib/runOfShow.ts`
- `src/components/DailyDashboard.tsx`
- `src/components/ShiftSummaryCard.tsx`

**DoD:**
- [ ] Dashboard displays all shifts for a selected day
- [ ] Check-in counts visible per shift/station
- [ ] Station assignments visible in the dashboard
- [ ] Multi-location filter works correctly
- [ ] Dashboard handles zero-shift days gracefully
- [ ] Vitest passes for data aggregation logic
- [ ] Playwright test: dashboard loads with seeded data and shows correct counts

**Validation:** `pnpm test && pnpm playwright test --grep "dashboard"`

**Complexity:** Medium

---

### Sprint 012 — End-of-Shift Engagement

**Scope:** Implement a shift completion trigger (staff marks shift done). Generate a digital impact card with shift statistics (hours, meals packed, etc.) and a shareable link/page. Send a post-shift SMS with the impact card link, a next-shift signup prompt, and a monthly giving CTA ("Serving Hope" member program). Recommend the next available shift.

**Non-goals:** Payment processing (link out only), RE NXT sync.

**Requirements:** FR24, FR25, FR26

**Dependencies:** 007, 009

**Expected Artifacts:**
- `src/app/impact/[id]/page.tsx`
- `src/lib/impactCard.ts`
- `src/components/ImpactCard.tsx`

**DoD:**
- [ ] Impact card generates with shift statistics
- [ ] Share link is publicly accessible
- [ ] Next-shift prompt renders on impact page
- [ ] Monthly giving CTA renders on impact page
- [ ] Post-shift SMS sent with impact card link
- [ ] Vitest passes for impact card generation
- [ ] Playwright test: volunteer checked-in → shift marked complete → impact card page accessible and shareable

**Validation:** `pnpm test && pnpm playwright test --grep "engagement"`

**Complexity:** Medium

---

### Sprint 013 — Raiser's Edge NXT Integration

**Scope:** Implement the RE NXT API client abstraction (mock + real HTTP adapter). Sync volunteer records and participation events. Match records by email and cell phone with confidence scoring. Auto-sync records with ≥90% confidence. Build an exception report UI for <90% confidence matches requiring human resolution. Implement the full donor recognition flag (pull known donors from RE NXT into local database, powering the Sprint 004 recognition hook). Ensure on-site captured data from Sprint 009 is included in sync payloads.

**Non-goals:** Replacing RE stewardship workflows, bidirectional sync, real-time sync (batch/near-real-time only).

**Requirements:** FR27, FR28, FR29 (full implementation), FR30, FR31

**Dependencies:** 004, 009, 012

**Expected Artifacts:**
- `src/lib/raisersEdge.ts`
- `src/lib/recordMatcher.ts`
- `src/app/admin/exceptions/page.tsx`
- `src/components/ExceptionReport.tsx`

**DoD:**
- [ ] RE NXT client creates/updates constituent records via mocked API
- [ ] Matcher auto-syncs records with ≥90% confidence
- [ ] Records below 90% confidence appear in exception queue
- [ ] Exception report lists pending matches for human resolution
- [ ] Donor recognition flag pulled from RE NXT and stored locally
- [ ] On-site captured data synced correctly
- [ ] Vitest passes for matching algorithm (exact match, fuzzy match, below-threshold)
- [ ] Vitest passes for sync client mock verification
- [ ] Playwright test: exception report shows seeded low-confidence match

**Validation:** `pnpm test && pnpm playwright test --grep "raiser"`

**Complexity:** High

---

### Sprint 014 — Full End-to-End Simulation & Validation

**Scope:** Build a comprehensive simulation harness running diverse volunteer scenarios through the complete journey from discovery to RE NXT sync. Implement intermediate milestone tests for each stage. Document an FR coverage matrix mapping all FR1–FR34 to tests. Integrate the full test suite into CI.

**Non-goals:** New features, PII in test data, production deployment.

**Requirements:** FR32, FR33

**Dependencies:** 001–013 (all)

**Expected Artifacts:**
- `tests/e2e/simulation/*.spec.ts`
- `tests/e2e/milestones/*.spec.ts`
- `src/lib/testFixtures.ts`
- `docs/FR_COVERAGE_MATRIX.md`

**DoD:**
- [ ] Scenario 1 passes: individual new volunteer (browse → signup → waiver → orientation → check-in → assignment → shift complete → impact card → RE sync)
- [ ] Scenario 2 passes: returning volunteer (login path clarity + session)
- [ ] Scenario 3 passes: group signup with deferred names → check-in captures missing members → group assigned together
- [ ] Scenario 4 passes: skills-based volunteer (resume upload → needs-review status)
- [ ] Scenario 5 passes: court-required volunteer (case worker info → pathway tagging)
- [ ] Scenario 6 passes: accessibility need (sitting-only constraint → assignment respects it)
- [ ] Scenario 7 passes: low-confidence RE match → exception report item
- [ ] Scenario 8 passes: donor recognition (known donor flagged during signup)
- [ ] All intermediate milestone tests pass independently
- [ ] FR coverage matrix documents all FR1–FR34 mapped to at least one test
- [ ] Test fixtures use PII-free synthetic data
- [ ] CI runs full suite successfully
- [ ] `pnpm test` passes
- [ ] `pnpm playwright test` passes with zero failures

**Validation:** `pnpm test && pnpm playwright test`

**Complexity:** High

---

## FR Coverage Matrix

| FR | Sprint(s) |
|----|-----------|
| FR1 | 003 |
| FR2 | 003 |
| FR3 | 004 |
| FR4 | 003, 004 |
| FR5 | 004 |
| FR6 | 004 |
| FR7 | 007 |
| FR8 | 007 |
| FR9 | 008 |
| FR10 | 008 |
| FR11 | 005 |
| FR12 | 005 |
| FR13 | 006 |
| FR14 | 006 |
| FR15 | 006 |
| FR16 | 009 |
| FR17 | 009 |
| FR18 | 010 |
| FR19 | 010 |
| FR20 | 010 |
| FR21 | 011 |
| FR22 | 003 |
| FR23 | 003 |
| FR24 | 012 |
| FR25 | 012 |
| FR26 | 012 |
| FR27 | 013 |
| FR28 | 013 |
| FR29 | 004, 013 |
| FR30 | 013 |
| FR31 | 013 |
| FR32 | 014 |
| FR33 | 008, 014 |
| FR34 | 001 |
