# Sprint Plan — Northern Illinois Food Bank Volunteer Portal Redesign

This plan comprises **12 sprints** delivering a full replacement of the Galaxy Digital volunteer portal. The plan was produced by merging three independent decompositions (Claude, Gemini, GPT) and incorporating six cross-critique findings. The **Claude decomposition** (12 sprints, highest DoD specificity, correct FR coverage matrix) was used as the structural base. Key merge decisions: (1) fixed dependency errors — messaging now depends on enrollment (Sprint 004), planning engine depends on attendance (Sprint 007), and can also run on enrollment data for pre-shift planning; (2) incorporated Gemini's explicit mobile opportunity modeling and station-as-distinct-concern approach; (3) adopted GPT's FakeRENXT adapter pattern and SyncOutbox pattern for Raiser's Edge integration; (4) added on-site waiver signing workflow to check-in sprint per critique; (5) defined the "perfectly planned shift" golden test scenario with concrete inputs (50 volunteers, 6 stations); (6) ensured FR18 guided discovery has explicit preference-question DoD items; (7) added social sharing verification and benefits/SNAP E2E test. All 22 functional requirements are covered with no dependency cycles.

---

### Sprint 001 — Project Scaffolding & Data Model Foundation

**Scope:** Initialize a Next.js (App Router) TypeScript project with TailwindCSS. Configure ESLint, Prettier, Vitest, and Playwright. Set up PostgreSQL via Docker Compose with Prisma ORM. Define all core domain entities — Volunteer, Location, Opportunity, Shift, Station, Group, Waiver, OrientationRecord, Attendance, Assignment, and PathwayType enum — in the Prisma schema. Create a seed script for development data and a health-check page.

**Non-goals:** No UI beyond a health page. No business logic. No external integrations.

**Requirements:** N/A (foundational — all FRs depend on this)

**Dependencies:** None

**Expected Artifacts:**
- `package.json` (with pnpm scripts: lint, typecheck, test, dev, build)
- `next.config.js`, `tsconfig.json`, `tailwind.config.ts`
- `prisma/schema.prisma` (all core models)
- `prisma/seed.ts`
- `src/lib/db.ts`
- `vitest.config.ts`, `playwright.config.ts`
- `.eslintrc.js`, `.prettierrc`
- `docker-compose.yml` (PostgreSQL)
- `src/app/health/page.tsx`
- `.env.example`

**DoD:**
- [ ] `pnpm install` succeeds with zero errors
- [ ] `pnpm lint` passes with zero warnings
- [ ] `pnpm vitest run` executes and passes (≥1 smoke test)
- [ ] `npx prisma migrate dev` creates all tables without error
- [ ] `npx prisma db seed` populates dev data (≥3 locations, ≥5 opportunities, ≥10 shifts, ≥2 stations per location)
- [ ] `pnpm playwright test` runs smoke test (`/health` renders 200)
- [ ] `docker compose up -d` starts PostgreSQL successfully

**Validation:** `pnpm install && pnpm lint && pnpm vitest run && pnpm playwright test`

**Complexity:** Medium

---

### Sprint 002 — Identity, Registration & Authentication

**Scope:** Implement the minimal registration flow collecting only name, phone number, and email. Build returning-user detection: if an existing email is entered during registration, return an `ACCOUNT_EXISTS` error code and redirect to the login flow. Implement magic-link authentication (email-based, with SMS OTP stubbed for future). The volunteer profile model supports progressive data capture — address and other fields are nullable and collected later. Session management via NextAuth.js.

**Non-goals:** No public-facing UI pages beyond the auth flow. No real SMS delivery (mock transport only). No waiver/orientation tracking. No social SSO (Google/Apple/Facebook).

**Requirements:** FR4, FR5

**Dependencies:** Sprint 001

**Expected Artifacts:**
- `src/app/api/auth/[...nextauth]/route.ts`
- `src/lib/auth.ts`
- `src/services/registration.ts`, `src/services/registration.test.ts`
- `prisma/migrations/*_identity`
- `src/app/(public)/register/page.tsx`
- `src/app/(public)/login/page.tsx`

**DoD:**
- [ ] Unit tests for registration service pass (`pnpm vitest run src/services/registration.test.ts`)
- [ ] Duplicate-email detection returns `ACCOUNT_EXISTS` error code (unit test)
- [ ] Magic-link generation works with mocked email transport (unit test)
- [ ] Prisma migration applies cleanly on fresh database
- [ ] Integration test: register → login → session valid (Playwright)
- [ ] Progressive profile: only name/phone/email required at registration; address fields nullable (schema test)
- [ ] `pnpm lint` passes

**Validation:** `pnpm vitest run src/services/registration.test.ts && pnpm playwright test`

**Complexity:** Medium

---

### Sprint 003 — Opportunity Catalog & Guided Discovery

**Scope:** Build the opportunity/shift data model with location, date, time, capacity, description, and type tags (including inside/outside/mobile). Create a public API to list, filter, and search opportunities by location, date range, and type. Ensure consistent shift detail rendering across all locations. Implement the guided discovery flow: a step-by-step preference questionnaire (inside/outside/mobile, time of day, group size) that produces filtered and ranked shift recommendations. Both calendar view and list view are supported. No login is required to browse.

**Non-goals:** No signup/enrollment. No staff management UI. No pathway routing.

**Requirements:** FR2, FR3, FR18

**Dependencies:** Sprint 001

**Expected Artifacts:**
- `src/services/opportunities.ts`, `src/services/opportunities.test.ts`
- `src/services/discovery.ts`, `src/services/discovery.test.ts`
- `src/app/(public)/opportunities/page.tsx`
- `src/app/(public)/opportunities/[id]/page.tsx`
- `src/app/(public)/discover/page.tsx`

**DoD:**
- [ ] Unit tests for opportunity listing/filtering pass (`pnpm vitest run src/services/opportunities.test.ts`)
- [ ] Unit tests for discovery recommendation engine pass — given preferences (inside, morning, group of 5), returns correctly filtered/ranked shifts (`pnpm vitest run src/services/discovery.test.ts`)
- [ ] Guided discovery page renders step-by-step preference questions (Playwright)
- [ ] Opportunity detail page renders all fields consistently across locations (Playwright snapshot)
- [ ] API returns opportunities without requiring authentication (integration test)
- [ ] Filter by location, date, and type returns correct results (unit test)
- [ ] Calendar view and list view both render (Playwright)
- [ ] `pnpm lint` passes

**Validation:** `pnpm vitest run src/services/opportunities.test.ts && pnpm vitest run src/services/discovery.test.ts && pnpm playwright test`

**Complexity:** Medium

---

### Sprint 004 — Website-Integrated UX Shell & Signup Flow

**Scope:** Build the website-integrated volunteer experience shell with a branded layout matching the NIFB site look and feel. Implement a conversational/chat-style signup flow that wraps opportunity discovery (Sprint 003) and registration (Sprint 002) into a seamless journey. Target flow: user lands on opportunities → selects a shift → is prompted for an account → registers or logs in → enrollment is created → confirmation is shown. Build the individual enrollment model (ShiftEnrollment) with capacity enforcement. The experience must feel native to the food bank website — like "talking to the Northern Illinois Food Bank."

**Non-goals:** No waiver/orientation integration within the flow. No group signup flow. No pathway routing beyond the default individual path.

**Requirements:** FR1, FR2

**Dependencies:** Sprint 002, Sprint 003

**Expected Artifacts:**
- `src/app/(public)/layout.tsx`
- `src/components/ConversationalFlow.tsx`, `src/components/ConversationalFlow.test.tsx`
- `src/app/(public)/signup-flow/page.tsx`
- `src/styles/brand.css`
- `src/services/enrollment.ts`, `src/services/enrollment.test.ts`
- `prisma/migrations/*_enrollment`

**DoD:**
- [ ] E2E test: user lands on opportunities, selects shift, is prompted for account, registers, sees confirmation (Playwright)
- [ ] Layout uses NIFB branding colors/logo (visual snapshot test)
- [ ] Conversational flow component unit tests pass
- [ ] Flow does NOT require login before showing opportunities (Playwright assertion)
- [ ] Enrollment creates ShiftEnrollment row and decrements available capacity (unit test)
- [ ] Capacity enforcement prevents overbooking (unit test)
- [ ] Mobile-responsive layout verified (Playwright viewport tests at 375px and 1280px)
- [ ] Prisma migration applies cleanly
- [ ] `pnpm lint` passes

**Validation:** `pnpm vitest run src/services/enrollment.test.ts && pnpm playwright test`

**Complexity:** Medium

---

### Sprint 005 — Messaging Service (SMS/Email), Waiver & Orientation

**Scope:** Build an abstract messaging service with Twilio SMS and email providers behind a provider interface (mock providers for tests). Implement confirmation messages on shift signup and pre-shift reminders (what to wear, where to go, parking/driving/entrance instructions). Build a digital waiver: a clickable acceptance flow that stores completion on the volunteer record. Build orientation tracking: mark completion status when a volunteer watches/clicks through orientation content. Provide a staff API endpoint to query waiver and orientation status per volunteer. Include an on-site waiver signing endpoint so staff/kiosks can facilitate waiver completion at arrival for volunteers who missed the pre-arrival SMS/email flow.

**Non-goals:** No post-shift messaging (Sprint 010). No QR check-in. No video hosting — orientation uses external links/embeds.

**Requirements:** FR6, FR7, FR8

**Dependencies:** Sprint 002, Sprint 004

**Expected Artifacts:**
- `src/services/messaging.ts`, `src/services/messaging.test.ts`
- `src/services/waiver.ts`, `src/services/waiver.test.ts`
- `src/services/orientation.ts`, `src/services/orientation.test.ts`
- `prisma/migrations/*_waiver_orientation`
- `src/app/(public)/waiver/[id]/page.tsx`
- `src/app/(public)/orientation/[id]/page.tsx`

**DoD:**
- [ ] Unit tests for messaging service pass with mocked Twilio/email (`pnpm vitest run src/services/messaging.test.ts`)
- [ ] Confirmation SMS/email sent on shift signup (integration test with mock provider)
- [ ] Pre-shift reminder scheduling logic tested — correct timing and content includes parking/arrival info (unit test)
- [ ] Waiver acceptance creates a record linked to the volunteer (unit test)
- [ ] On-site waiver signing endpoint allows staff to trigger waiver completion for a volunteer at check-in time (unit test)
- [ ] Orientation completion tracked and queryable per volunteer (unit test)
- [ ] Staff API endpoint returns waiver + orientation status per volunteer (integration test)
- [ ] Prisma migration applies cleanly
- [ ] `pnpm lint` passes

**Validation:** `pnpm vitest run src/services/messaging.test.ts && pnpm vitest run src/services/waiver.test.ts && pnpm vitest run src/services/orientation.test.ts && pnpm playwright test`

**Complexity:** Medium

---

### Sprint 006 — Pathway Routing: Groups, Skills-Based, Court-Required & Benefits

**Scope:** Implement the pathway routing engine that detects volunteer type (individual, group, skills-based, court-required, benefits-hours) and routes to the appropriate workflow. Group signup: leader creates a group, invites members via link, and allows partial member information (name/email/phone nullable for non-leader members) for on-site capture at arrival. Skills-based: resume/file upload plus a human review queue with Pending/Approved/Rejected states and notification on state change. Court-required: a managed sign-off flow with a printable hours verification document. Benefits/SNAP: hour tracking with a printable verification for benefits compliance.

**Non-goals:** No check-in integration. No assignment engine. No staff dashboard. No automated approval of skills-based applications.

**Requirements:** FR9, FR10, FR11, FR12

**Dependencies:** Sprint 002, Sprint 003

**Expected Artifacts:**
- `src/services/pathways.ts`, `src/services/pathways.test.ts`
- `src/services/groups.ts`, `src/services/groups.test.ts`
- `src/services/skills-review.ts`, `src/services/skills-review.test.ts`
- `src/services/court-service.ts`, `src/services/court-service.test.ts`
- `src/services/benefits-hours.ts`, `src/services/benefits-hours.test.ts`
- `prisma/migrations/*_pathways`
- `src/app/(public)/group/create/page.tsx`
- `src/app/(public)/skills-apply/page.tsx`

**DoD:**
- [ ] Unit tests for pathway routing engine pass — each volunteer type routes correctly (`pnpm vitest run src/services/pathways.test.ts`)
- [ ] Group creation and member invitation flow tested (unit test)
- [ ] Group schema allows incomplete member details — name/email/phone nullable for non-leader members (schema test)
- [ ] Skills-based application with file upload creates a review queue item in Pending state (unit test)
- [ ] Skills review state transitions (Pending → Approved/Rejected) work and trigger notification (unit test)
- [ ] Court-required pathway generates a printable hours verification document (unit test)
- [ ] Benefits-hours pathway tracks hours and produces printable verification (unit test)
- [ ] Prisma migration applies cleanly
- [ ] `pnpm lint` passes

**Validation:** `pnpm vitest run src/services/pathways.test.ts && pnpm vitest run src/services/groups.test.ts && pnpm playwright test`

**Complexity:** High

---

### Sprint 007 — QR Check-In & Attendance

**Scope:** Generate unique QR codes per volunteer per shift, delivered via the messaging service. Build a check-in endpoint: scan QR → validate enrollment + waiver status → mark attended. Implement group check-in: leader scans once and all group members are checked in. Build an on-site capture UI where staff or the group lead can enter name/email/phone for previously unnamed group members, creating full volunteer records. Include an on-site waiver signing workflow at the kiosk for those who missed the pre-arrival flow. Persist attendance records. Prevent duplicate check-ins (idempotent scan handling).

**Non-goals:** No facial recognition. No station assignment at check-in time. No post-shift flow.

**Requirements:** FR13, FR9 (group check-in aspect)

**Dependencies:** Sprint 002, Sprint 005, Sprint 006

**Expected Artifacts:**
- `src/services/checkin.ts`, `src/services/checkin.test.ts`
- `src/services/qr.ts`, `src/services/qr.test.ts`
- `src/app/(staff)/checkin/page.tsx`
- `src/app/(public)/checkin/[code]/page.tsx`
- `prisma/migrations/*_attendance`

**DoD:**
- [ ] QR code generation produces valid, unique codes per volunteer-shift pair (unit test)
- [ ] Check-in endpoint marks attendance correctly (integration test)
- [ ] Group check-in: leader scan checks in all group members (unit test)
- [ ] Staff can enter name/email/phone for unnamed group members at check-in, creating volunteer records (Playwright)
- [ ] Waiver status validated at check-in; warning surfaced if incomplete with option to complete on-site (unit test)
- [ ] Duplicate check-in prevented — second scan returns idempotent response (unit test)
- [ ] Prisma migration applies cleanly
- [ ] E2E: generate QR → scan → attendance recorded (Playwright)
- [ ] `pnpm lint` passes

**Validation:** `pnpm vitest run src/services/checkin.test.ts && pnpm vitest run src/services/qr.test.ts && pnpm playwright test`

**Complexity:** Medium

---

### Sprint 008 — Shift Planning & Assignment Engine

**Scope:** Model stations per location with capacities, labor needs, and labor conditions (accessibility/sitting-only, physical demands, temperature). Build the auto-assignment algorithm: given a shift's enrolled and/or checked-in volunteers plus station constraints, produce an optimal assignment plan. Constraints enforced: keep groups together at the same station, assign accessibility/sitting-only volunteers to compatible stations, respect station capacity limits. Output is a structured assignment plan with unassigned overflow reported. The engine can run on enrollment data (pre-shift planning) or attendance data (day-of refinement). Includes a "perfectly planned shift" golden test with a defined scenario: 50 volunteers (3 groups of 8, 5 sitting-only individuals, 21 general), 6 stations (1 sitting-compatible, 1 cooler with 8-person max, 4 general with 12-person max each), with expected output verified.

**Non-goals:** No staff UI for manual override (Sprint 009). No run-of-show view. No real-time updates.

**Requirements:** FR14, FR15

**Dependencies:** Sprint 006, Sprint 007

**Expected Artifacts:**
- `src/services/planning.ts`, `src/services/planning.test.ts`
- `src/services/assignment-engine.ts`, `src/services/assignment-engine.test.ts`
- `prisma/migrations/*_stations_assignments`
- `tests/fixtures/perfect-shift.json`

**DoD:**
- [ ] Station model with capacity, labor needs, and labor conditions persists correctly (schema test)
- [ ] Assignment engine produces valid plan respecting all capacity constraints (unit test)
- [ ] Groups are kept together at the same station (unit test)
- [ ] Accessibility/sitting-only volunteers assigned to compatible stations only (unit test)
- [ ] Over-capacity scenario handled gracefully — unassigned overflow reported in output (unit test)
- [ ] Engine works on enrollment data (pre-shift) and attendance data (day-of) (unit tests for both modes)
- [ ] "Perfectly planned shift" golden test: 50 volunteers (defined fixture) → expected assignment output verified (`pnpm vitest run src/services/assignment-engine.test.ts`)
- [ ] Performance: assignment for 200 volunteers across 10 stations completes in <2 seconds (benchmark test)
- [ ] Prisma migration applies cleanly
- [ ] `pnpm lint` passes

**Validation:** `pnpm vitest run src/services/assignment-engine.test.ts && pnpm vitest run src/services/planning.test.ts`

**Complexity:** High

---

### Sprint 009 — Staff Dashboard: Run of Show & Manual Overrides

**Scope:** Build the staff-facing operations dashboard. The run-of-show view displays all shifts, centers, stations, and mobile volunteer opportunities for a given day or week. The assignment override UI allows staff to drag-and-drop volunteers between stations. The dashboard shows check-in status, waiver/orientation status, and station fill levels. A weekly planning view shows the shift schedule across all locations. Mobile opportunities are explicitly modeled and displayed. Overrides persist with an audit trail recording who made the change and when. Overrides never violate station capacity constraints.

**Non-goals:** No volunteer-facing features. No Raiser's Edge integration. No post-shift engagement features.

**Requirements:** FR16, FR17

**Dependencies:** Sprint 007, Sprint 008

**Expected Artifacts:**
- `src/app/(staff)/dashboard/page.tsx`
- `src/app/(staff)/dashboard/dashboard.test.tsx`
- `src/app/(staff)/planning/page.tsx`
- `src/components/AssignmentBoard.tsx`, `src/components/AssignmentBoard.test.tsx`
- `src/components/RunOfShow.tsx`, `src/components/RunOfShow.test.tsx`

**DoD:**
- [ ] Run-of-show view renders all shifts for a given day across all centers (Playwright)
- [ ] Assignment override: dragging a volunteer between stations updates the assignment (unit test)
- [ ] Override persists to database correctly with audit log (integration test)
- [ ] Check-in status visible per volunteer in the dashboard (Playwright assertion)
- [ ] Waiver/orientation status indicators render correctly (unit test)
- [ ] Station fill levels update dynamically when volunteers are moved (unit test)
- [ ] Weekly view shows shift schedule across all locations (Playwright)
- [ ] Mobile opportunities appear in the run-of-show view (integration test)
- [ ] Overrides never violate station capacity (unit test)
- [ ] `pnpm lint` passes

**Validation:** `pnpm playwright test && pnpm vitest run`

**Complexity:** High

---

### Sprint 010 — Post-Shift Engagement & Retention

**Scope:** Build the post-shift engagement flow triggered after a shift ends. Generate a digital impact card (shareable via a unique URL) showing what the volunteer accomplished. Deliver the impact card via SMS/email. Include a next-shift commitment prompt that returns relevant upcoming opportunities. Include a monthly giving program ("Serving Hope") signup prompt with trackable interest capture (creates a database record). Support social sharing: Open Graph meta tags on the impact card page and a copy-to-clipboard share URL.

**Non-goals:** No donor database sync. No admin reporting. No physical card printing. No payment processing.

**Requirements:** FR19

**Dependencies:** Sprint 005, Sprint 007

**Expected Artifacts:**
- `src/services/post-shift.ts`, `src/services/post-shift.test.ts`
- `src/services/impact-card.ts`, `src/services/impact-card.test.ts`
- `src/app/(public)/impact/[id]/page.tsx`
- `src/app/(public)/next-shift/page.tsx`

**DoD:**
- [ ] Post-shift engagement triggered after shift end time (unit test with time mock)
- [ ] Impact card generated with shift-specific data (unit test)
- [ ] Impact card accessible via unique URL with Open Graph meta tags for social sharing (integration test)
- [ ] Copy-to-clipboard share functionality works (Playwright)
- [ ] SMS/email sent with impact card link (test with mock provider)
- [ ] Next-shift prompt returns relevant upcoming opportunities (unit test)
- [ ] Monthly giving interest capture creates a trackable record (unit test)
- [ ] E2E: shift ends → impact card generated → viewable at URL (Playwright)
- [ ] `pnpm lint` passes

**Validation:** `pnpm vitest run src/services/post-shift.test.ts && pnpm vitest run src/services/impact-card.test.ts && pnpm playwright test`

**Complexity:** Medium

---

### Sprint 011 — Raiser's Edge NXT Integration & Record Matching

**Scope:** Build the integration service for Raiser's Edge NXT with an API client abstracted behind a provider interface. Include a FakeRENXT adapter for CI that writes JSON to `var/raiser-sync/`. Use a SyncOutbox pattern: attendance events enqueue outbox items for processing. Implement volunteer-to-donor record matching using email and cell phone with confidence scoring. Automatic sync for high-confidence matches (≥90%, configurable threshold). Exception workflow for low-confidence matches: records below the threshold are surfaced to a staff review queue. Staff exception review UI allows confirm-match, create-new-record, or skip actions. Resolution triggers delayed sync for that record. Sync engine handles API failures with retry logic and is idempotent (re-run safe).

**Non-goals:** No replacement of Raiser's Edge stewardship workflows. No real-time bidirectional sync. No historical Galaxy Digital data migration.

**Requirements:** FR20, FR21, FR22

**Dependencies:** Sprint 002, Sprint 007

**Expected Artifacts:**
- `src/services/raisers-edge.ts`, `src/services/raisers-edge.test.ts`
- `src/services/record-matching.ts`, `src/services/record-matching.test.ts`
- `src/services/sync-engine.ts`, `src/services/sync-engine.test.ts`
- `src/lib/raiser/adapter.ts`
- `src/lib/raiser/adapters/fake.ts`
- `src/app/(staff)/exceptions/page.tsx`
- `src/app/(staff)/exceptions/exceptions.test.tsx`
- `prisma/migrations/*_re_sync`

**DoD:**
- [ ] RE NXT API client connects and authenticates via FakeRENXT adapter (test)
- [ ] Record matching by email returns correct match with confidence score (unit test)
- [ ] Record matching by phone returns correct match with confidence score (unit test)
- [ ] High-confidence match (≥90%) triggers automatic sync via outbox (unit test)
- [ ] Low-confidence match (<90%) creates exception record in staff queue (unit test)
- [ ] Exception queue lists pending records for staff review (integration test)
- [ ] Staff can resolve exception: confirm match, create new record, or skip (unit test)
- [ ] Resolution triggers delayed sync for that record (unit test)
- [ ] Sync engine handles API failure gracefully with retry logic (unit test)
- [ ] Sync is idempotent — re-run does not create duplicates (unit test)
- [ ] Prisma migration applies cleanly
- [ ] `pnpm lint` passes

**Validation:** `pnpm vitest run src/services/record-matching.test.ts && pnpm vitest run src/services/sync-engine.test.ts && pnpm playwright test`

**Complexity:** High

---

### Sprint 012 — End-to-End Integration, Validation & Polish

**Scope:** Full end-to-end validation of the complete volunteer journey: discover opportunity → register → receive confirmation SMS → complete waiver → complete orientation → receive pre-shift reminder → arrive and check in via QR → get assigned to station → complete shift → receive impact card → prompted for next shift → record synced to Raiser's Edge NXT. Includes the "perfectly planned shift" scenario test using the golden fixture defined in Sprint 008. All pathway E2E tests: individual, group, skills-based, court-required, and benefits/SNAP. Cross-browser and multi-device testing. Accessibility audit targeting Lighthouse score ≥90. Performance pass ensuring key pages load in <2 seconds. Bug fixes from integration testing.

**Non-goals:** No new feature development. No production deployment or infrastructure provisioning.

**Requirements:** FR1–FR22 (all requirements validated end-to-end)

**Dependencies:** Sprint 001–011 (all previous sprints)

**Expected Artifacts:**
- `tests/e2e/full-journey.spec.ts`
- `tests/e2e/perfect-shift.spec.ts`
- `tests/e2e/group-journey.spec.ts`
- `tests/e2e/skills-pathway.spec.ts`
- `tests/e2e/court-pathway.spec.ts`
- `tests/e2e/benefits-pathway.spec.ts`
- `docs/validation-report.md`

**DoD:**
- [ ] Full individual volunteer journey E2E test passes (`pnpm playwright test tests/e2e/full-journey.spec.ts`)
- [ ] Group volunteer journey E2E test passes (`pnpm playwright test tests/e2e/group-journey.spec.ts`)
- [ ] Skills-based pathway E2E test passes (`pnpm playwright test tests/e2e/skills-pathway.spec.ts`)
- [ ] Court-required pathway E2E test passes (`pnpm playwright test tests/e2e/court-pathway.spec.ts`)
- [ ] Benefits/SNAP hours pathway E2E test passes (`pnpm playwright test tests/e2e/benefits-pathway.spec.ts`)
- [ ] "Perfectly planned shift" scenario test passes with golden fixture (`pnpm playwright test tests/e2e/perfect-shift.spec.ts`)
- [ ] Raiser's Edge sync E2E test with FakeRENXT adapter passes
- [ ] All unit test suites pass (`pnpm vitest run` — zero failures)
- [ ] Lighthouse accessibility score ≥90 on key public pages (opportunities, register, discover)
- [ ] Performance: key pages load in <2s (Lighthouse performance audit)
- [ ] No critical or high-severity bugs remain open
- [ ] `pnpm lint` passes with zero warnings

**Validation:** `pnpm vitest run && pnpm playwright test`

**Complexity:** High

---

## FR-to-Sprint Coverage Matrix

| FR | Primary Sprint(s) | Description |
|----|--------------------|-------------|
| FR1 | 004 | Website-integrated UX shell |
| FR2 | 003, 004 | Browse before auth + signup flow |
| FR3 | 003 | Consistent opportunity listings |
| FR4 | 002 | Minimal registration |
| FR5 | 002 | Returning-user detection |
| FR6 | 005 | SMS/email messaging |
| FR7 | 005, 007 | Digital waiver + on-site signing |
| FR8 | 005 | Orientation tracking + arrival guidance |
| FR9 | 006, 007 | Group signup + group check-in |
| FR10 | 006 | Skills-based pathway |
| FR11 | 006 | Court-required pathway |
| FR12 | 006 | Benefits-hours pathway |
| FR13 | 007 | QR check-in |
| FR14 | 008 | Station modeling |
| FR15 | 008 | Auto-assignment engine |
| FR16 | 009 | Manual override |
| FR17 | 009 | Run of show |
| FR18 | 003 | Guided discovery questionnaire |
| FR19 | 010 | Post-shift engagement |
| FR20 | 011 | RE NXT sync |
| FR21 | 011 | Record matching |
| FR22 | 011 | Exception workflow |

**All 22 functional requirements are covered. All are validated in Sprint 012 E2E.**

---

## Dependency Graph

```
Sprint 001 (Foundation)
    ├──► Sprint 002 (Identity/Auth)
    │       ├──► Sprint 004 (UX Shell) ←── Sprint 003
    │       │       └──► Sprint 005 (Messaging/Waiver/Orientation)
    │       │               └──► Sprint 007 (QR Check-In) ←── Sprint 006
    │       │                       ├──► Sprint 008 (Assignment Engine) ←── Sprint 006
    │       │                       │       └──► Sprint 009 (Staff Dashboard)
    │       │                       ├──► Sprint 010 (Post-Shift) ←── Sprint 005
    │       │                       └──► Sprint 011 (Raiser's Edge) ←── Sprint 002
    │       └──► Sprint 006 (Pathways) ←── Sprint 003
    ├──► Sprint 003 (Opportunity Catalog)
    └──────────────────────────────────► Sprint 012 (E2E Validation) ←── All
```

**No dependency cycles. Sprint 001 is the sole root. Sprint 012 depends on all previous sprints.**
