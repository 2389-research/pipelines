# Sprint Plan

This plan contains **14 sprints** synthesized from three independent decompositions (Claude/10, Gemini/18, GPT/12) and six cross-critiques. Key merge decisions: mega-sprints (Claude S009, Gemini S012, GPT S012) were split into focused units; thin Gemini sprints (SMS 007+008, check-in 009+010) were consolidated; dependency errors were fixed (catalog doesn't require identity; booking doesn't require guided matching); court-required and benefit-related pathway schemas are flagged as stubs pending stakeholder confirmation; monthly giving prompt added to end-of-shift engagement per FR15; RE NXT uses batch-first adapter with API stub; and a final integration sprint provides golden-path validation.

---

### Sprint 001 — Project Scaffolding & Core Schema

**Scope:** Initialize a Next.js 14 + TypeScript monorepo with Prisma ORM, full database schema (Users, VolunteerProfiles, Opportunities, Shifts, Stations, Registrations, Pathways, Waivers, OrientationCompletions, CheckIns, Messages, REQueue, MatchExceptions), Docker Compose for PostgreSQL, seed script, Vitest + Playwright configuration, and a health endpoint.

**Non-goals:** No business logic, no UI beyond health page, no external integrations.

**Requirements:** Foundation for all FRs (none completed here).

**Dependencies:** None.

**Expected Artifacts:**
- `package.json` with lint/test/test:e2e/build scripts
- `prisma/schema.prisma`
- `prisma/seed.ts`
- `docker-compose.yml`
- `vitest.config.ts`, `playwright.config.ts`
- `src/app/health/page.tsx`
- `.eslintrc.json`, `.prettierrc`
- `README.md`

**DoD:**
- [ ] `npm run lint` exits 0
- [ ] `npm run test` passes health smoke test
- [ ] `npx prisma migrate dev` creates all tables
- [ ] `npx prisma db seed` succeeds
- [ ] `npm run build` exits 0

**Validation:** `npm ci && npm run lint && npm run test && npm run build`

**Complexity:** Low

---

### Sprint 002 — Opportunity Catalog & Public Discovery

**Scope:** Build the public-facing volunteer landing page with branded "warm/welcoming" shell, opportunity listing with filters (date, location, indoor/outdoor, time-of-day, group-size), shift detail pages, and a guided matching flow (preference quiz → ranked results with "I'd rather browse" escape). No authentication required to browse, supporting the browse-first pattern from FR2.

**Non-goals:** Booking/registration logic, personalization from volunteer history, admin CRUD for opportunities (seeded data).

**Requirements:** FR1, FR14

**Dependencies:** 001

**Expected Artifacts:**
- `src/app/opportunities/page.tsx`
- `src/app/shifts/[shiftId]/page.tsx`
- `src/app/api/opportunities/route.ts`
- `src/app/api/shifts/[shiftId]/route.ts`
- `src/server/opportunities/guidedMatch.ts`
- `src/components/opportunities/`

**DoD:**
- [ ] `GET /api/opportunities` returns paginated list without authentication
- [ ] Filter by indoor/outdoor, date, and time-of-day works correctly
- [ ] Guided match endpoint returns ranked shifts from preference payload
- [ ] "I'd rather browse" button links back to catalog listing
- [ ] Landing page renders branded, welcoming shell
- [ ] Playwright e2e: browse list → open shift detail without login
- [ ] Vitest unit tests for filtering and ranking logic pass

**Validation:** `npm run test && npm run test:e2e`

**Complexity:** Medium

---

### Sprint 003 — Identity & Minimal Signup

**Scope:** Implement minimal-data volunteer signup collecting only name, email, and phone. Passwordless magic-code authentication (simulated in dev). Session management via signed cookie. Login flow triggered only after shift selection (deferred signup pattern). Duplicate email detection returns 409.

**Non-goals:** OAuth/social login (Google/Apple), profile editing beyond basic contact info, phone-number OTP with real provider.

**Requirements:** FR2, FR3

**Dependencies:** 001

**Expected Artifacts:**
- `src/server/auth/`
- `src/app/api/auth/signup/route.ts`
- `src/app/api/auth/login/route.ts`
- `src/app/api/profile/route.ts`
- `src/app/auth/page.tsx`

**DoD:**
- [ ] `POST /api/auth/signup` with `{name, email, phone}` returns 201
- [ ] Duplicate email returns 409
- [ ] `POST /api/auth/login` returns session token
- [ ] `GET /api/profile` with valid session returns user data
- [ ] Vitest unit tests for auth logic (create, login, duplicate) pass
- [ ] Playwright: select shift → prompted to sign up → session persists across reload

**Validation:** `npm run test && npm run test:e2e`

**Complexity:** Medium

---

### Sprint 004 — Pathway Rules Engine

**Scope:** Define five volunteer pathway types (individual, group, skills-based, court-required, benefit-related) with per-pathway JSON validation schemas. Individual requires base fields only. Group requires group-size and group-name. Skills-based requires skills list (stub schema — rules TBD per spec open question 7). Court-required requires case-number (stub — rules TBD per open question 8). Benefit-related requires benefit-program-id (stub — rules TBD). Middleware attaches pathway context to downstream flows.

**Non-goals:** Full workflow orchestration per pathway, external verification systems for court/benefit programs.

**Requirements:** FR8

**Dependencies:** 001, 003

**Expected Artifacts:**
- `src/server/pathways/`
- `src/server/pathways/validators.ts`
- `src/app/api/pathways/route.ts`

**DoD:**
- [ ] `GET /api/pathways` returns all 5 types with their required-field schemas
- [ ] Individual pathway requires only base fields (name, email, phone)
- [ ] Group pathway requires group-size and group-name
- [ ] Court-required and benefit-related schemas marked as stubs pending stakeholder confirmation
- [ ] Validation rejects payload missing pathway-required fields
- [ ] Vitest tests for all 5 pathway validators pass

**Validation:** `npm run test`

**Complexity:** High

---

### Sprint 005 — Registration & Booking

**Scope:** Shift booking linking a user, opportunity, and pathway. Enforces shift capacity limits, pathway-required fields, and duplicate booking prevention. Supports cancellation (frees slot). Concurrent booking handled via database transaction. Completes the browse → auth → book flow from FR2.

**Non-goals:** Waitlist management, payment, calendar sync.

**Requirements:** FR2 (completion of deferred-signup flow)

**Dependencies:** 002, 003, 004

**Expected Artifacts:**
- `src/server/registrations/`
- `src/app/api/registrations/route.ts`
- `src/app/register/[shiftId]/page.tsx`

**DoD:**
- [ ] `POST /api/registrations` with valid user + opportunity + pathway returns 201
- [ ] Duplicate booking for same user + opportunity returns 409
- [ ] Booking beyond shift capacity returns 422
- [ ] Pathway-required fields enforced at booking time
- [ ] `DELETE /api/registrations/:id` cancels and frees the slot
- [ ] `GET /api/registrations?userId=X` returns user's bookings
- [ ] Vitest unit + integration tests pass
- [ ] Playwright: full browse → auth → book flow

**Validation:** `npm run test && npm run test:e2e`

**Complexity:** Medium

---

### Sprint 006 — Digital Waiver & Orientation

**Scope:** Digital waiver signing flow (typed name + checkbox + timestamp/IP), waiver status tracking per volunteer profile, and orientation video completion tracking with basic verification (embed URL + startedAt/completedAt duration tracking). Waiver completion becomes a check-in prerequisite (enforced in Sprint 008). Idempotent re-signing returns existing record.

**Non-goals:** Waiver template builder/admin, video hosting, paper waiver scanning, legal review.

**Requirements:** FR6, FR7

**Dependencies:** 003, 004

**Expected Artifacts:**
- `src/server/waiver/`
- `src/server/orientation/`
- `src/app/waiver/[registrationId]/page.tsx`
- `src/app/orientation/[registrationId]/page.tsx`
- `src/app/api/waiver/sign/route.ts`
- `src/app/api/orientation/complete/route.ts`

**DoD:**
- [ ] `POST /api/waiver/sign` creates signature with timestamp
- [ ] `GET` waiver status returns signed/unsigned with timestamp
- [ ] `POST /api/orientation/complete` stores completion with duration data (startedAt/completedAt)
- [ ] Idempotent re-sign returns existing record
- [ ] Vitest unit tests for waiver and orientation services pass
- [ ] Playwright: register → sign waiver → complete orientation → statuses visible

**Validation:** `npm run test && npm run test:e2e`

**Complexity:** Medium

---

### Sprint 007 — Communications Layer (SMS Confirmations & Reminders)

**Scope:** SMS provider abstraction (`SmsProvider` interface with `FakeSmsProvider` default and optional Twilio stub). Event-driven messaging: booking confirmation SMS and 24-hour pre-shift reminder with full arrival guidance (what to wear, where to go, parking). Message templates with variable rendering. Background job for scheduled sends. Outbound message log in database. Staff outbox view.

**Non-goals:** Two-way SMS conversations, marketing campaigns, post-shift messages (Sprint 011), SMS compliance/stop handling (deferred).

**Requirements:** FR4

**Dependencies:** 003, 005

**Expected Artifacts:**
- `src/server/comms/SmsProvider.ts`
- `src/server/comms/FakeSmsProvider.ts`
- `src/server/comms/templates/confirmation.ts`
- `src/server/comms/templates/reminder.ts`
- `src/server/jobs/reminders.ts`
- `src/app/staff/messages/page.tsx`
- Prisma `OutboundMessage`

**DoD:**
- [ ] Booking event triggers confirmation SMS (verified via fake provider log in DB)
- [ ] Reminder job sends messages 24h before shift start
- [ ] Templates render with volunteer name, shift details, what-to-wear, and where-to-go guidance
- [ ] Outbound messages logged in DB for audit
- [ ] Staff outbox page lists sent messages
- [ ] Vitest: template rendering, job scheduling logic
- [ ] `npm run jobs:reminders` executes successfully

**Validation:** `npm run test`

**Complexity:** Medium

---

### Sprint 008 — QR Check-In (Individual & Group)

**Scope:** QR code generation per registration (via `qrcode` npm). Staff check-in page with camera scanning (`@zxing/browser`) and manual token entry fallback. Validates waiver and orientation status (blocks check-in if incomplete, returns 403 with message). Group check-in: single scan checks in all group members. On-site missing-data capture form for group walk-ins (name, email, phone), creating placeholder volunteer records. Duplicate check-in is idempotent.

**Non-goals:** Hardware scanner integration, NFC, geofencing, self-service kiosk.

**Requirements:** FR9

**Dependencies:** 005, 006

**Expected Artifacts:**
- `src/server/checkin/`
- `src/app/api/checkin/route.ts`
- `src/app/api/registrations/[id]/qr/route.ts`
- `src/app/staff/checkin/page.tsx`
- Prisma `CheckIn`, `QrToken`

**DoD:**
- [ ] `GET /api/registrations/:id/qr` returns QR code data
- [ ] `POST /api/checkin` with QR token marks volunteer as arrived
- [ ] Group registration QR checks in all group members
- [ ] Check-in returns 403 if waiver is incomplete with clear message
- [ ] Missing group member data capture form creates placeholder records
- [ ] Duplicate check-in is idempotent (no error)
- [ ] Vitest: token validation, waiver gating, group logic
- [ ] Playwright: check-in flow with manual token entry

**Validation:** `npm run test && npm run test:e2e`

**Complexity:** Medium

---

### Sprint 009 — Station Configuration & Shift Planning

**Scope:** Staff-facing CRUD for stations: name, numeric capacity, constraint flags (accessibility/sitting-only, required-skills). Attach stations to shifts. Admin view showing total capacity vs. total booked volunteers per shift.

**Non-goals:** Dynamic station creation during a live shift, auto-assignment (Sprint 010).

**Requirements:** FR10

**Dependencies:** 002

**Expected Artifacts:**
- `src/server/stations/`
- `src/app/api/stations/route.ts`
- `src/app/staff/stations/page.tsx`
- `src/app/staff/shifts/[shiftId]/stations/page.tsx`
- Prisma `Station`, `ShiftStationRequirement`

**DoD:**
- [ ] `POST /api/stations` creates station with capacity and constraint flags
- [ ] `GET /api/stations?shiftId=X` lists stations with capacity vs. booked count
- [ ] `PUT /api/stations/:id` updates station configuration
- [ ] Vitest CRUD service tests pass
- [ ] Playwright: create station → attach to shift → persists

**Validation:** `npm run test && npm run test:e2e`

**Complexity:** Medium

---

### Sprint 010 — Auto Station Assignment & Manual Overrides

**Scope:** Heuristic assignment engine that distributes all checked-in volunteers to stations. Respects capacity limits, keeps group members at the same station, and routes sitting-only/accessibility-flagged volunteers to compatible stations. Generates a viewable draft plan. Staff UI for manual override (drag-drop or dropdown reassignment). Overrides logged in audit trail.

**Non-goals:** Optimization solver, real-time WebSocket updates.

**Requirements:** FR11, FR12

**Dependencies:** 008, 009

**Expected Artifacts:**
- `src/server/planning/assign.ts`
- `src/app/api/planning/auto-assign/route.ts`
- `src/app/api/planning/assignments/[id]/route.ts`
- `src/app/staff/planning/[shiftId]/page.tsx`
- Prisma `StationPlan`, `StationAssignment`

**DoD:**
- [ ] `GET /api/planning/auto-assign?shiftId=X` returns draft assignment plan
- [ ] Group members assigned to the same station
- [ ] Sitting-only volunteers not assigned to high-mobility stations
- [ ] 100% of checked-in volunteers assigned
- [ ] `PUT /api/planning/assignments/:id` allows staff override
- [ ] Overrides logged in audit trail
- [ ] Vitest: algorithm constraints (capacity, group cohesion, accessibility)
- [ ] Playwright: generate plan → override assignment → saved

**Validation:** `npm run test && npm run test:e2e`

**Complexity:** High

---

### Sprint 011 — Run-of-Show Dashboard & Post-Shift Engagement

**Scope:** Staff run-of-show daily view showing all shifts, stations, assignments, and check-in counts (distinguishing mobile vs. center shifts). Post-shift workflow: mark shift complete → trigger impact SMS via comms layer + digital impact card page (metrics derived from actual check-in data) + social share buttons (OpenGraph metadata) + "Book Next Shift" CTA linking to catalog + monthly giving prompt link. Post-shift SMS includes link to impact card.

**Non-goals:** Historical reporting, physical printouts, new feature work.

**Requirements:** FR13, FR5, FR15

**Dependencies:** 007, 008, 010

**Expected Artifacts:**
- `src/app/staff/run-of-show/page.tsx`
- `src/app/api/runofshow/[date]/route.ts`
- `src/server/comms/postShift.ts`
- `src/app/impact/[registrationId]/page.tsx`
- `src/server/jobs/postshift.ts`

**DoD:**
- [ ] `GET /api/runofshow/:date` returns shifts, stations, assignments, and check-in counts
- [ ] Mobile vs. center shifts distinguished in response
- [ ] Post-shift job sends impact SMS via comms layer
- [ ] Impact card displays "You helped X families" derived from real check-in data
- [ ] Social share buttons render correct OpenGraph metadata
- [ ] "Book Next Shift" button links to catalog with user info
- [ ] Monthly giving prompt link present on impact card
- [ ] Vitest: run-of-show data assembly, impact metric calculation
- [ ] Playwright: run-of-show loads with seeded data
- [ ] `npm run jobs:postshift` executes successfully

**Validation:** `npm run test && npm run test:e2e`

**Complexity:** Medium

---

### Sprint 012 — Raiser's Edge NXT Sync & Batch Export

**Scope:** RE NXT adapter interface abstracting batch vs. API integration paths. Batch export implementation generating JSON/CSV of volunteer profiles and activity (check-in hours). Sync job writes to REQueue table. Retry logic for failed exports. Sync log recording each run with counts (synced, failed, new). Does not replace RE NXT; existing stewardship workflows untouched.

**Non-goals:** Real-time bidirectional sync, replacing RE NXT, modifying existing stewardship processes, real API calls (API path is a stub).

**Requirements:** FR16, FR19

**Dependencies:** 003, 008

**Expected Artifacts:**
- `src/server/integrations/raisersEdge/adapter.ts`
- `src/server/integrations/raisersEdge/batchExport.ts`
- `src/server/integrations/raisersEdge/apiStub.ts`
- `src/server/jobs/reSync.ts`
- Prisma `REQueue`, `SyncLog`

**DoD:**
- [ ] Sync job exports volunteer records + check-in activity to batch file (JSON/CSV)
- [ ] Adapter interface abstracts batch vs. API path
- [ ] Sync log records each run with counts (synced, failed, new)
- [ ] Retry logic handles export failures
- [ ] Vitest: batch export format, sync log recording
- [ ] `npm run jobs:re-sync` executes successfully

**Validation:** `npm run test`

**Complexity:** High

---

### Sprint 013 — RE NXT Record Matching & Exception Handling

**Scope:** Matching engine scoring volunteer records against RE NXT by email (exact match) and phone (normalized), with a configurable matching strategy (not hardcoded to only email+phone). Auto-match at ≥90% confidence (configurable threshold). Records below threshold routed to exception report for human review. Staff exception review UI with confirm-match, create-new, and skip actions. Downloadable CSV export of exception report.

**Non-goals:** Automated merging of RE NXT records, bidirectional sync.

**Requirements:** FR17, FR18

**Dependencies:** 012

**Expected Artifacts:**
- `src/server/integrations/raisersEdge/matching.ts`
- `src/server/integrations/raisersEdge/exceptions.ts`
- `src/app/api/resync/exceptions/route.ts`
- `src/app/staff/re-exceptions/page.tsx`

**DoD:**
- [ ] Matching engine scores by email + phone with configurable strategy
- [ ] Records with confidence ≥ 90% auto-matched in sync log
- [ ] Records with confidence < 90% appear in exception report
- [ ] `GET /api/resync/exceptions` returns pending unresolved exceptions
- [ ] `POST /api/resync/exceptions/:id/resolve` marks exception as resolved
- [ ] CSV export of exception report available
- [ ] Configurable confidence threshold (default 0.9)
- [ ] Vitest: confidence scoring with 10+ edge cases, threshold configuration
- [ ] Playwright: exception review flow (view → resolve)

**Validation:** `npm run test && npm run test:e2e`

**Complexity:** High

---

### Sprint 014 — E2E Validation & Integration Hardening

**Scope:** Golden-path end-to-end test covering the full volunteer lifecycle (signup → discover → book → waiver → orientation → check-in → station assignment → impact card → RE sync). Activity hours sync verification in RE batch export. Accessibility audit targeting Lighthouse score ≥ 90. Final UX review against "warm/welcoming" acceptance criteria. Production environment configuration.

**Non-goals:** New feature development.

**Requirements:** All FRs (validation pass)

**Dependencies:** 011, 013

**Expected Artifacts:**
- `tests/e2e/golden-path.spec.ts`
- `.env.production.example`
- Deployment documentation in `README.md`

**DoD:**
- [ ] Golden-path Playwright test passes end-to-end
- [ ] Shift hours appear in RE batch export after volunteer check-out
- [ ] Lighthouse accessibility score ≥ 90
- [ ] All `npm run test` pass
- [ ] All `npm run test:e2e` pass
- [ ] `npm run build` succeeds
- [ ] README updated with production setup instructions

**Validation:** `npm ci && npm run lint && npm run test && npm run test:e2e && npm run build`

**Complexity:** Medium
