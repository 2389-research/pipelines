# Merged Sprint Plan — Food Bank Volunteer Portal Redesign

This plan comprises **13 sprints** synthesized from three independent decompositions (Claude, Gemini, GPT) and six cross-critiques. Key merge decisions: (1) added an explicit shift-booking sprint to close the critical gap found in both Claude and Gemini decompositions; (2) gave FR20 (conversational discovery) a real implementation with testable DoD rather than deferring it; (3) split Claude's oversized final sprint into UX polish + validation harness; (4) merged Gemini's separate QR/group check-in sprints into one; (5) combined station setup with the assignment engine; (6) consolidated all special-case pathways into a single sprint; (7) ensured FR6 (warm/welcoming UX) and FR7 (confirmation with video link) have explicit DoD items. The stack is Next.js App Router + TypeScript, PostgreSQL + Prisma, NextAuth, Twilio SMS (mock in dev), Vitest + Playwright, Docker Compose (pg + redis), and BullMQ for background jobs.

---

### Sprint 001 — Project Scaffold & Data Models

**Scope:** Initialize the Next.js/TypeScript project with PostgreSQL and Redis via Docker Compose. Define all core Prisma models (volunteers, opportunities, shifts, stations, groups, waivers, orientations, messages, registrations, checkins, donor_match_exceptions). Create anonymized seed data, a PII-scan script, CI workflow, and environment templates.

**Non-goals:** No business logic, no API endpoints beyond health check, no UI.

**Requirements:** FR1 (partial — data model foundation), FR27

**Dependencies:** None

**Expected Artifacts:**
- `package.json` (scripts: lint, test, test:e2e, db:migrate, db:seed)
- `docker-compose.yml` (postgres + redis)
- `prisma/schema.prisma` (all core models)
- `prisma/seed.ts` (PII-free fixture data)
- `.env.example`
- `src/app/api/health/route.ts`
- `vitest.config.ts`
- `playwright.config.ts`
- `scripts/pii_scan.ts`
- `README.md`
- `__tests__/schema.test.ts`

**DoD:**
- [ ] `npm run build` succeeds
- [ ] `npm run db:migrate && npm run db:seed` succeeds
- [ ] `npm test` passes (≥1 schema validation test)
- [ ] `docker compose up -d` starts postgres + redis with passing healthchecks
- [ ] `GET /api/health` returns 200
- [ ] `node scripts/pii_scan.ts` exits 0
- [ ] `npm run lint` passes

**Validation:** `npm run build && npm test && npm run lint`

**Complexity:** Medium

---

### Sprint 002 — Auth & Minimal Registration

**Scope:** Implement minimal signup collecting name, phone, and email. Login with credentials. Clear "email already exists — please log in" handling (HTTP 409). Phone OTP endpoint behind a mock provider interface. Social login stubs for Google/Apple/Facebook. JWT/session management. Profile CRUD (GET/PATCH) with auth guard.

**Non-goals:** No opportunity browsing, no booking, no real social provider integration.

**Requirements:** FR1, FR2, FR4, FR5

**Dependencies:** 001

**Expected Artifacts:**
- `src/lib/auth/` (service, JWT utils, middleware)
- `src/app/api/auth/register/route.ts`
- `src/app/api/auth/login/route.ts`
- `src/app/api/auth/otp/route.ts` (mock)
- `src/app/api/auth/social/route.ts` (stub)
- `src/app/api/volunteers/[id]/route.ts` (profile CRUD)
- `__tests__/auth.test.ts`
- `__tests__/profile.test.ts`

**DoD:**
- [ ] `npm test` passes with ≥8 auth + profile tests
- [ ] Registration with name/email/phone creates record and returns session token
- [ ] Duplicate email returns HTTP 409 with "please log in" message
- [ ] Login with valid credentials returns session token
- [ ] Profile GET/PATCH returns 401 without auth
- [ ] OTP endpoint exists and returns 501 stub
- [ ] Social login endpoint exists and returns 501 stub
- [ ] `npm run lint` passes

**Validation:** `npm test && npm run lint`

**Complexity:** Medium

---

### Sprint 003 — Opportunity Catalog & Conversational Discovery

**Scope:** Build the public opportunity catalog (browsable without auth) with admin CRUD. Implement a conversational discovery Q&A flow that asks step-by-step preference questions (inside/outside/mobile, time of day, group size) and recommends matching shifts. The discovery UI uses a guided, conversational pattern — not just filters — per FR20.

**Non-goals:** No booking/registration for shifts yet. No shift planning.

**Requirements:** FR3, FR19, FR20

**Dependencies:** 001

**Expected Artifacts:**
- `src/app/(public)/opportunities/page.tsx` (catalog)
- `src/app/(public)/discover/page.tsx` (conversational Q&A)
- `src/app/api/opportunities/route.ts` (list + filter)
- `src/app/api/opportunities/[id]/route.ts` (detail)
- `src/app/api/admin/opportunities/route.ts` (CRUD)
- `src/lib/recommendation.ts` (rule-based matching)
- `__tests__/recommendation.test.ts`
- `e2e/discover.spec.ts`

**DoD:**
- [ ] `npm test` passes with ≥4 recommendation tests
- [ ] `GET /api/opportunities` returns paginated results without auth
- [ ] Discovery page presents step-by-step Q&A (not just filter dropdowns)
- [ ] Q&A responses produce filtered/ranked recommendations
- [ ] Admin CRUD endpoints require auth
- [ ] `npx playwright test e2e/discover.spec.ts` passes
- [ ] `npm run lint` passes

**Validation:** `npm test && npm run test:e2e && npm run lint`

**Complexity:** Medium

---

### Sprint 004 — Shift Booking & Volunteer Account

**Scope:** Allow authenticated volunteers to register for a shift from the opportunity page. Build the "my account" page showing upcoming registrations, past shifts, and total volunteer hours. Enforce shift capacity limits. This sprint closes the critical gap (identified in cross-critiques) where discovery existed but booking did not.

**Non-goals:** No waiver/orientation gating yet, no check-in.

**Requirements:** FR1 (account/history), FR3 (completes the discover → book flow)

**Dependencies:** 002, 003

**Expected Artifacts:**
- `src/app/api/registrations/route.ts` (POST — create booking)
- `src/app/api/registrations/[id]/route.ts` (GET/DELETE)
- `src/app/(volunteer)/account/page.tsx`
- `src/lib/registration.ts` (capacity check logic)
- `__tests__/registration.test.ts`
- `e2e/booking.spec.ts`

**DoD:**
- [ ] `npm test` passes with ≥4 registration tests
- [ ] `POST /api/registrations` creates registration and enforces capacity
- [ ] Account page shows upcoming shifts, past shifts, and total hours
- [ ] Booking beyond capacity returns HTTP 409
- [ ] `npx playwright test e2e/booking.spec.ts` passes
- [ ] `npm run lint` passes

**Validation:** `npm test && npm run test:e2e && npm run lint`

**Complexity:** Medium

---

### Sprint 005 — Waiver & Orientation

**Scope:** Implement digital waiver signing with timestamp and version tracking. Build orientation video page with completion tracking. Expose "ready to volunteer" gating status on the volunteer profile for downstream check-in enforcement.

**Non-goals:** No PDF generation, no video hosting (embed placeholder URL), no check-in enforcement yet.

**Requirements:** FR9, FR10

**Dependencies:** 002

**Expected Artifacts:**
- `src/app/api/volunteers/[id]/waiver/route.ts`
- `src/app/api/volunteers/[id]/orientation/route.ts`
- `src/app/(volunteer)/waiver/page.tsx`
- `src/app/(volunteer)/orientation/page.tsx`
- `src/lib/waiver.ts`
- `src/lib/orientation.ts`
- `__tests__/waiver.test.ts`
- `__tests__/orientation.test.ts`

**DoD:**
- [ ] `npm test` passes with ≥6 waiver + orientation tests
- [ ] Signing waiver records completion timestamp and version on volunteer record
- [ ] Orientation completion records timestamp; re-query returns `viewed: true`
- [ ] Unsigned waiver returns `status: pending`
- [ ] Unviewed orientation returns `status: pending`
- [ ] Both endpoints return 401 without auth
- [ ] `npm run lint` passes

**Validation:** `npm test && npm run lint`

**Complexity:** Medium

---

### Sprint 006 — Messaging Layer (SMS + Email)

**Scope:** Build a central messaging service with pluggable providers (mock for dev, Twilio SMS adapter, email adapter). Define templates for: confirmation (including orientation video link per FR7), pre-shift reminder ("bring tennis shoes"), arrival guidance, and post-shift follow-up. Implement BullMQ scheduled jobs for timed reminders. Wire event-driven triggers to volunteer lifecycle events (signup, booking, check-in, shift completion).

**Non-goals:** No end-of-shift engagement content (Sprint 011). No real Twilio account required.

**Requirements:** FR7, FR8

**Dependencies:** 002, 004

**Expected Artifacts:**
- `src/lib/messaging/service.ts` (provider interface)
- `src/lib/messaging/sms.ts` (mock + Twilio adapter)
- `src/lib/messaging/email.ts` (mock adapter)
- `src/lib/messaging/templates/` (confirmation, reminder, arrival, post-shift)
- `src/lib/jobs/reminders.ts` (BullMQ scheduled job)
- `__tests__/messaging.test.ts`

**DoD:**
- [ ] `npm test` passes with ≥8 messaging tests
- [ ] Registration event triggers confirmation message (logged in test mode)
- [ ] Confirmation template includes orientation video link (FR7)
- [ ] Reminder template includes shift-specific guidance text
- [ ] Templates render with volunteer name and shift details
- [ ] SMS/email adapters in test mode do not call external APIs
- [ ] Message send history queryable per volunteer
- [ ] `npm run lint` passes

**Validation:** `npm test && npm run lint`

**Complexity:** Medium

---

### Sprint 007 — QR Check-In (Individual + Group)

**Scope:** Generate per-registration QR codes with signed tokens. Check-in API validates QR and marks volunteer as arrived. Enforce waiver and orientation completion at check-in (warn/block if incomplete). Group lead check-in with quick-add form capturing name/email/phone for walk-in members. Search-by-name fallback if QR scan fails.

**Non-goals:** No station assignment at check-in, no kiosk hardware UI.

**Requirements:** FR11, FR12

**Dependencies:** 004, 005

**Expected Artifacts:**
- `src/lib/qr.ts` (generation + token signing/verification)
- `src/app/api/volunteers/[id]/qr/route.ts`
- `src/app/api/checkin/route.ts` (individual)
- `src/app/api/checkin/group/route.ts` (group with quick-add)
- `src/app/(checkin)/checkin/page.tsx`
- `__tests__/checkin.test.ts`

**DoD:**
- [ ] `npm test` passes with ≥8 check-in tests
- [ ] QR code contains valid signed token
- [ ] Check-in marks volunteer as arrived with timestamp
- [ ] Missing waiver produces warning flag in check-in response
- [ ] Missing orientation produces warning flag in check-in response
- [ ] Group check-in quick-add captures name/email/phone for walk-in members
- [ ] Duplicate check-in returns idempotent response
- [ ] Search-by-name fallback returns matching volunteers
- [ ] `npm run lint` passes

**Validation:** `npm test && npm run lint`

**Complexity:** Medium

---

### Sprint 008 — Pathway Routing & Special Cases

**Scope:** Implement pathway classification for the five volunteer types: individual, group, skills-based, court-required, and benefits-hours. Build the routing engine that directs volunteers into the correct flow. Skills-based pathway: resume upload (local + S3 interface), application status management, and admin review/approve UI. Court-required: metadata storage and hours tracking. Benefits: metadata and hours letter stub. Group pathway: group creation with member roster.

**Non-goals:** No automated skills matching, no advanced hours reporting.

**Requirements:** FR13, FR14

**Dependencies:** 002, 003

**Expected Artifacts:**
- `src/lib/pathways/` (enum, router, status state machine)
- `src/app/api/volunteers/[id]/pathway/route.ts`
- `src/app/api/volunteers/[id]/resume/route.ts`
- `src/app/api/groups/route.ts`
- `src/app/(admin)/applications/page.tsx` (skills-based review queue)
- `src/lib/storage.ts` (local + S3 interface)
- `__tests__/pathway.test.ts`
- `e2e/pathway.spec.ts`

**DoD:**
- [ ] `npm test` passes with ≥8 pathway tests
- [ ] All 5 pathway types can be assigned to a volunteer record
- [ ] Skills-based pathway accepts resume upload and creates "pending" application
- [ ] Admin can approve or deny skills-based application
- [ ] Court-required pathway stores court metadata fields
- [ ] Benefits pathway stores required metadata
- [ ] Group pathway creates group record with member roster
- [ ] `npx playwright test e2e/pathway.spec.ts` passes
- [ ] `npm run lint` passes

**Validation:** `npm test && npm run test:e2e && npm run lint`

**Complexity:** High

---

### Sprint 009 — Station Setup & Auto-Assignment Engine

**Scope:** Admin CRUD for locations, stations, capacity, and constraints (labor needs, sitting-only). Implement the auto-assignment algorithm that takes checked-in volunteers and produces station assignments respecting: capacity limits, group cohesion (keep groups together), and special accommodations (sitting-only). Staff override API for manual reassignment that persists across re-plans.

**Non-goals:** No real-time re-optimization, no multi-day planning.

**Requirements:** FR15, FR16, FR17

**Dependencies:** 001, 007, 008

**Expected Artifacts:**
- `prisma/` (station, capacity, constraint, assignment models — migration)
- `src/lib/planner/engine.ts`
- `src/lib/planner/constraints.ts` (group cohesion, sitting-only, capacity)
- `src/app/api/admin/stations/route.ts` (CRUD)
- `src/app/api/shifts/[id]/plan/route.ts` (generate plan)
- `src/app/api/shifts/[id]/assignments/route.ts` (list/override)
- `__tests__/planner.test.ts`

**DoD:**
- [ ] `npm test` passes with ≥10 planner tests
- [ ] Algorithm assigns all checked-in volunteers without exceeding station capacity
- [ ] Group members are assigned to the same station
- [ ] Volunteer with sitting-only need is assigned to a compatible station
- [ ] Unassignable volunteer is flagged (not silently dropped)
- [ ] Staff override persists and survives re-plan
- [ ] Plan generation completes in <2 seconds for 50 volunteers / 10 stations
- [ ] Admin station CRUD requires auth
- [ ] `npm run lint` passes

**Validation:** `npm test && npm run lint`

**Complexity:** High

---

### Sprint 010 — Staff Run-of-Show Dashboard

**Scope:** Build the daily run-of-show API returning all shifts, stations, assignments, and counts for a given date. Create a staff dashboard page with assignment overview, override controls, and clear distinction between mobile and center-based opportunities.

**Non-goals:** No volunteer-facing UI, no reporting/analytics.

**Requirements:** FR18

**Dependencies:** 009

**Expected Artifacts:**
- `src/app/api/admin/runofshow/route.ts`
- `src/app/(admin)/dashboard/page.tsx`
- `e2e/staff-dashboard.spec.ts`
- `__tests__/runofshow.test.ts`

**DoD:**
- [ ] `npm test` passes with ≥4 run-of-show tests
- [ ] API returns all shifts/stations/assignments for a given date
- [ ] Dashboard page renders without errors (Playwright test passes)
- [ ] View distinguishes mobile vs. center opportunities
- [ ] Override control calls assignment override API and persists changes
- [ ] `npm run lint` passes

**Validation:** `npm test && npm run test:e2e && npm run lint`

**Complexity:** Medium

---

### Sprint 011 — End-of-Shift Engagement

**Scope:** Generate a digital impact card after shift completion with volunteer stats. Produce a shareable link accessible without auth. Build next-shift recommendation using volunteer preference data from discovery (FR19). Include "Serving Hope" monthly giving prompt. Trigger post-shift messaging via the messaging layer.

**Non-goals:** No payment/donation processing, no social media API integration.

**Requirements:** FR21

**Dependencies:** 006, 007

**Expected Artifacts:**
- `src/lib/engagement/` (impact card generator, share link builder, next-shift recommender)
- `src/app/api/shifts/[id]/impact/route.ts`
- `src/app/(public)/impact/[id]/page.tsx`
- `__tests__/engagement.test.ts`

**DoD:**
- [ ] `npm test` passes with ≥6 engagement tests
- [ ] Impact card endpoint returns card data with shift stats after completion
- [ ] Share link is accessible without authentication
- [ ] Next-shift recommendation references volunteer preferences
- [ ] "Serving Hope" monthly giving prompt is present in the response
- [ ] Post-shift message triggered via messaging layer (logged in test mode)
- [ ] `npm run lint` passes

**Validation:** `npm test && npm run lint`

**Complexity:** Low

---

### Sprint 012 — Raiser's Edge NXT Integration

**Scope:** Build the RE NXT integration service with a mock API adapter and HTTP client interface. Implement record matcher using email and phone with confidence scoring. Records with ≥90% confidence auto-sync; <90% are queued for manual review as exceptions. Scheduled sync job via BullMQ. Admin exception review UI. Batch fallback mode generates an export file when the API is unavailable. Surface known donor/company context in the volunteer profile response for a warm welcome experience. First-wave scope: sync records into RE NXT only — do not replace RE.

**Non-goals:** No bi-directional sync, no stewardship/cultivation workflows.

**Requirements:** FR22, FR23, FR24, FR25

**Dependencies:** 002, 004

**Expected Artifacts:**
- `src/lib/raisersEdge/client.ts` (interface + mock)
- `src/lib/donorMatch/match.ts` (email + phone matching)
- `src/lib/donorMatch/confidence.ts`
- `src/lib/jobs/reSync.ts` (BullMQ)
- `src/app/api/admin/donor-sync/route.ts`
- `src/app/api/admin/donor-exceptions/route.ts`
- `src/app/(admin)/donor-exceptions/page.tsx`
- `__tests__/donor.test.ts`

**DoD:**
- [ ] `npm test` passes with ≥8 donor integration tests
- [ ] Email match returns ≥90% confidence and auto-syncs to mock RE NXT
- [ ] Phone-only match returns lower confidence score
- [ ] <90% confidence match creates exception record (not auto-synced)
- [ ] Batch fallback generates export file when API is unavailable
- [ ] Exception review UI lists pending matches for staff review
- [ ] Sync does not modify or replace existing RE NXT data
- [ ] Donor/company context surfaced in volunteer profile API response
- [ ] `npm run lint` passes

**Validation:** `npm test && npm run lint`

**Complexity:** High

---

### Sprint 013 — UX Polish, E2E Validation & Test Harness

**Scope:** Integrate all volunteer-facing flows into a cohesive, website-integrated experience that feels warm and welcoming (FR6) rather than an external portal redirect. Build a comprehensive Playwright E2E suite simulating diverse volunteer personas (individual, group lead, skills-based, court-required). Run the full "perfectly planned shift" simulation with diverse volunteers progressing from discovery through auto-generated station assignments. Verify PII-free compliance across all fixtures, seeds, and test data. Produce an FR traceability report mapping all 27 requirements to tests.

**Non-goals:** No production deployment, no performance/load testing, no actual website CMS integration.

**Requirements:** FR6, FR26, FR27

**Dependencies:** 001–012 (all previous sprints)

**Expected Artifacts:**
- `src/app/` (polished public volunteer flow pages)
- `e2e/volunteer-individual.spec.ts`
- `e2e/volunteer-group.spec.ts`
- `e2e/volunteer-skills.spec.ts`
- `e2e/volunteer-court.spec.ts`
- `e2e/perfect-shift.spec.ts`
- `docs/validation-report.md`
- `docs/fr-traceability.md`

**DoD:**
- [ ] `npx playwright test` passes all E2E specs
- [ ] E2E covers signup → planned shift for ≥3 distinct persona types
- [ ] `perfect-shift.spec.ts` simulates diverse volunteers through the complete flow ending with auto-generated station assignments
- [ ] All 27 FRs traceable to ≥1 test (documented in `docs/fr-traceability.md`)
- [ ] `node scripts/pii_scan.ts` exits 0 across all fixtures, seeds, and E2E data
- [ ] `grep -rn '@' prisma/seed.ts e2e/` returns only `@example.com` domains
- [ ] `npm run build` succeeds
- [ ] `npm test` full suite passes
- [ ] `npm run lint` passes
- [ ] Volunteer flow has no external-portal redirects — feels website-integrated
- [ ] `docs/validation-report.md` documents pass/fail status for each FR

**Validation:** `npm run build && npm test && npm run test:e2e && npm run lint && node scripts/pii_scan.ts`

**Complexity:** High

---

## FR Traceability Matrix

| FR | Sprint(s) | Description |
|----|-----------|-------------|
| FR1 | 001, 002, 004 | Account creation, login, history/hours |
| FR2 | 002 | Minimal registration fields |
| FR3 | 003, 004 | Opportunity-first discovery + booking |
| FR4 | 002 | Social sign-in + phone OTP |
| FR5 | 002 | Email-exists handling |
| FR6 | 013 | Warm, welcoming, website-integrated UX |
| FR7 | 006 | Confirmation messaging with video link |
| FR8 | 006 | SMS/texting throughout journey |
| FR9 | 005 | Digital waiver |
| FR10 | 005 | Orientation tracking |
| FR11 | 007 | QR check-in |
| FR12 | 007 | Group check-in + on-site info capture |
| FR13 | 008 | Volunteer pathway routing |
| FR14 | 008 | Skills-based application + resume upload |
| FR15 | 009 | Station/capacity/constraint setup |
| FR16 | 009 | Auto-assignment engine |
| FR17 | 009 | Staff override of assignments |
| FR18 | 010 | Run-of-show dashboard |
| FR19 | 003 | Preference-based recommendations |
| FR20 | 003 | Conversational discovery flow |
| FR21 | 011 | End-of-shift engagement + impact card |
| FR22 | 012 | RE NXT auto-sync |
| FR23 | 012 | Donor record matching + context |
| FR24 | 012 | Low-confidence exception workflow |
| FR25 | 012 | First-wave sync scope |
| FR26 | 013 | Validation tests + perfectly planned shift |
| FR27 | 001, 013 | PII-free artifacts |
