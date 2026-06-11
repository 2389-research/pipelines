# Implementation Sprints (expanded from notes)

## Global decisions

- Project: Galaxy Digital Volunteer Portal Redesign
- Total Sprints: 015
- Sources: Claude (12 sprints), GPT (14 sprints), Gemini (17 sprints)
- Merge approach: GPT tech stack decisions adopted (Node 20, TS, Express+zod+Prisma, React+Vite+Tailwind, Vitest, Playwright, monorepo). Claude's compact grouping used as base, with targeted splits from Gemini (pathways split into two, RE NXT kept as one consolidated sprint). Critique findings integrated: FR7 video link explicit in messaging, FR35 blank spreadsheet explicit in artifacts sprint, group check-in validation logic made explicit, planning DoD tightened for groups-not-split and accessibility assertions.
- Monorepo layout: apps/api (Express), apps/web (Vite React), packages/shared (types+zod). Root workspaces + docker-compose.yml.
- Standard commands: npm ci, npm run dev, npm run lint, npm run typecheck, npm run test, npm run test:e2e, npm run db:up, npm run db:migrate, npm run db:seed
- SMS: abstract provider interface + fake/stub provider writing to DB/log
- QR: qrcode lib (generate) + @zxing/browser (scan) + manual fallback
- Planning algorithm: deterministic heuristic (groups first, then individuals, apply constraints); not an optimizer

## Sprints

### Sprint 001: Repo Scaffolding & Dev Loop

- **Sprint number:** 001
- **Title:** Repo Scaffolding & Dev Loop
- **Scope:** Monorepo setup with Node 20 + TypeScript, docker-compose postgres, hello-world API (/healthz) + Web ("Volunteer Portal Prototype"), shared package, lint/typecheck/test/e2e configs, CI stub (.github/workflows/ci.yml).
- **Non-goals:** Any business logic beyond health check endpoint.
- **Requirements covered:** FR33, FR34
- **Dependencies:** 
- **Expected artifacts:**
  - root package.json (workspaces), docker-compose.yml, .env.example, README.md
  - apps/api/src/index.ts with /healthz endpoint
  - apps/web/src/App.tsx renders "Volunteer Portal Prototype"
  - packages/shared/src/index.ts
  - eslint + prettier config, tsconfig refs, vitest config, playwright config
  - .github/workflows/ci.yml running lint/typecheck/test
- **DoD items:**
  - npm ci succeeds
  - npm run db:up starts postgres container
  - npm run dev launches api+web; curl localhost:PORT/healthz returns 200
  - npm run lint passes
  - npm run typecheck passes
  - npm run test passes with at least 1 unit test for /healthz
  - npm run test:e2e passes with 1 playwright test loading home page
- **Complexity:** medium

### Sprint 002: Core Data Model & Seed Data

- **Sprint number:** 002
- **Title:** Core Data Model & Seed Data
- **Scope:** Prisma schema + migrations for Volunteer, UserAccount, Shift, Opportunity, Signup, Group, GroupMember, Station (placeholder), CheckInEvent (placeholder). REST API routes for opportunities and signups. PII-free seed script with stable fake IDs for research artifacts.
- **Non-goals:** Authentication, messaging, QR, planning logic, any UI beyond API.
- **Requirements covered:** FR2, FR35
- **Dependencies:** 001
- **Expected artifacts:**
  - apps/api/prisma/schema.prisma with all core models
  - migration files under apps/api/prisma/migrations/
  - apps/api/prisma/seed.ts with PII-free sample data
  - API routes: GET /opportunities, GET /shifts, POST /signups
  - packages/shared zod schemas for all models
- **DoD items:**
  - npm run db:migrate applies cleanly on empty DB
  - npm run db:seed inserts sample data with zero PII values
  - npm run test includes API tests for GET /opportunities and POST /signups
  - npm run typecheck passes
  - npm run lint passes
- **Complexity:** high

### Sprint 003: Public Portal & Opportunity Browsing

- **Sprint number:** 003
- **Title:** Public Portal & Opportunity Browsing
- **Scope:** Web UI for browsing opportunities/shifts without auth (opportunity-first flow). Shift detail page with "Select this shift" CTA. Basic warm/concierge styling baseline with design tokens, header/footer, friendly copy, accessibility baseline. Filters for date, location, and type.
- **Non-goals:** Account creation/login, recommendations, pathway-specific filtering.
- **Requirements covered:** FR1, FR3, FR22
- **Dependencies:** 002
- **Expected artifacts:**
  - apps/web routes: /opportunities list page, /shifts/:id detail page
  - API integration client in web with loading/error states
  - Design tokens/components: header, footer, card, friendly copy baseline
  - Filter logic module for date/location/type
- **DoD items:**
  - Shifts render on /opportunities without requiring authentication
  - Filters (date, location, type) return correct subsets
  - Shift detail page shows full shift information
  - "Select this shift" CTA is visible on detail page
  - npm run test includes RTL tests for opportunity list and shift detail
  - npm run test:e2e includes playwright: browse opportunities -> open shift detail
  - npm run lint and npm run typecheck pass
- **Complexity:** medium

### Sprint 004: Authentication & Progressive Profile

- **Sprint number:** 004
- **Title:** Authentication & Progressive Profile
- **Scope:** Login vs create-account flow triggered after shift selection. Minimal signup collecting only name, email, phone. Improved "email already exists" error with clear recovery/login path. Session/token management via auth middleware. Progressive profile update endpoint (PATCH /volunteer/me) for later field collection.
- **Non-goals:** Social login (Google/Apple/Facebook), donor matching, pathway routing.
- **Requirements covered:** FR2, FR3, FR4
- **Dependencies:** 003
- **Expected artifacts:**
  - apps/api auth module: POST /auth/register, POST /auth/login, auth middleware
  - PATCH /volunteer/me endpoint for progressive profile
  - apps/web auth modal/page with Create Account and Sign In tabs
  - Improved error response codes and messages for email-exists case
- **DoD items:**
  - Signup with name+email+phone creates a volunteer record
  - Duplicate email attempt returns specific actionable error message (not generic 500)
  - Login with valid credentials returns session/token
  - Profile update endpoint accepts additional fields on existing record
  - npm run test includes unit tests for auth (register, login, email-exists path)
  - npm run test:e2e includes playwright: select shift -> register with minimal fields -> signup created
  - npm run lint and npm run typecheck pass
- **Complexity:** high

### Sprint 005: Volunteer Pathways — Individual, Group, Court, Benefits

- **Sprint number:** 005
- **Title:** Volunteer Pathways — Individual, Group, Court, Benefits
- **Scope:** PathwayType enum and routing logic. Individual pathway assigned by default for solo signup. Group pathway with group creation and member linking. Court-required pathway storing case number and hours-needed metadata. Benefit-related pathway storing program type and hours metadata. Pathway selection step in signup flow with conditional forms per pathway.
- **Non-goals:** Skills-based pathway (deferred to Sprint 006), full admin UI for pathway review.
- **Requirements covered:** FR11, FR13, FR14
- **Dependencies:** 004
- **Expected artifacts:**
  - PathwayType enum in Prisma schema
  - SignupPathwayData JSON schema (zod) per pathway
  - Group and GroupMember model extensions
  - Pathway router module in apps/api
  - apps/web pathway selection step with conditional forms
- **DoD items:**
  - Individual pathway assigned by default for solo signup
  - Group pathway creates group and links members
  - Court-required pathway stores case number and hours needed
  - Benefit-related pathway stores program type and hours
  - npm run test includes zod validation tests per pathway type
  - npm run test:e2e includes playwright: group pathway signup flow end-to-end
  - npm run lint and npm run typecheck pass
- **Complexity:** medium

### Sprint 006: Skills-Based Pathway & Staff Review Queue

- **Sprint number:** 006
- **Title:** Skills-Based Pathway & Staff Review Queue
- **Scope:** Skills-based volunteering pathway with resume upload (local file storage in dev). Staff review queue: ReviewRequest model with status workflow, staff endpoints to list pending reviews and resolve them. Minimal staff review web page at /staff/reviews.
- **Non-goals:** Automated resume parsing, S3/cloud storage (local only), other pathway changes.
- **Requirements covered:** FR12
- **Dependencies:** 005
- **Expected artifacts:**
  - POST /uploads/resume endpoint with local file storage
  - ResumeUpload model in Prisma schema
  - ReviewRequest model with status enum (pending/approved/rejected)
  - GET /staff/reviews and POST /staff/reviews/:id/decision API routes
  - apps/web /staff/reviews page with list and approve/reject actions
- **DoD items:**
  - Skills-based signup accepts resume upload and flags record for human review
  - Uploaded files stored in local uploads directory
  - Staff can list all pending reviews via API
  - Staff can approve or reject a review via API
  - npm run test includes unit tests for upload handler and review workflow
  - npm run test:e2e includes playwright: skills signup with resume -> item appears in staff review queue
  - npm run lint and npm run typecheck pass
- **Complexity:** medium

### Sprint 007: Digital Waiver & Orientation Tracking

- **Sprint number:** 007
- **Title:** Digital Waiver & Orientation Tracking
- **Scope:** Digital waiver sign/accept flow attached to volunteer record with signedAt timestamp and signature name. Orientation video page with completion tracking requiring at least 90 percent watched. Expose waiver-completion and orientation-completion status flags for downstream check-in module.
- **Non-goals:** Hosting actual video content (use placeholder URLs), producing orientation video.
- **Requirements covered:** FR8, FR9, FR10
- **Dependencies:** 004
- **Expected artifacts:**
  - Waiver model (signedAt, signatureName, version) in Prisma
  - OrientationCompletion model (watchedSeconds, completedAt) in Prisma
  - POST /waivers/sign and GET /waivers/status API endpoints
  - POST /orientation/progress and POST /orientation/complete API endpoints
  - apps/web waiver signing page
  - apps/web orientation page with embedded video player and progress tracking
- **DoD items:**
  - Volunteer can sign digital waiver; waiver attached to record with timestamp
  - Waiver status queryable as signed or unsigned per volunteer
  - Orientation completion requires at least 90 percent of video watched
  - Orientation status queryable as complete or incomplete per volunteer
  - Both status flags available via API for check-in validation
  - npm run test includes unit tests for waiver and orientation models
  - npm run test:e2e includes playwright: sign waiver -> complete orientation -> both statuses show complete
  - npm run lint and npm run typecheck pass
- **Complexity:** medium

### Sprint 008: Messaging & Notification Layer (SMS)

- **Sprint number:** 008
- **Title:** Messaging & Notification Layer (SMS)
- **Scope:** SMS provider abstraction with send method and fake/stub provider that logs to DB. Confirmation SMS on shift signup including link to video-based instructions per FR7. Pre-shift reminder SMS with what-to-wear and where-to-go guidance. Post-shift impact message template. Notification event triggers at signup/reminder/post-shift lifecycle points. OutboundMessage log table. Scheduled message job runner using node-cron.
- **Non-goals:** Real SMS vendor integration (Twilio etc), social sharing links, next-shift prompts.
- **Requirements covered:** FR5, FR6, FR7
- **Dependencies:** 004, 007
- **Expected artifacts:**
  - OutboundMessage model and MessageTemplate model in Prisma
  - SMS provider interface with send method + FakeProvider implementation
  - Event trigger hooks for signup confirmation, pre-shift reminder, post-shift impact
  - Cron job: sendScheduledMessages
  - apps/web minimal message preferences section in volunteer profile
- **DoD items:**
  - SMS provider interface defined with send method
  - Stub provider logs all messages to DB without external API calls
  - Shift signup triggers confirmation SMS containing video instruction link (FR7)
  - Pre-shift reminder sent at configured interval before shift start
  - Post-shift impact message sent after shift ends
  - Message log persisted in OutboundMessage table
  - npm run test includes unit tests for template rendering and scheduling logic
  - npm run test:e2e includes playwright: signup triggers confirmation message record in DB
  - npm run lint and npm run typecheck pass
- **Complexity:** medium

### Sprint 009: QR Check-In (Individual + Group)

- **Sprint number:** 009
- **Title:** QR Check-In (Individual + Group)
- **Scope:** QR code generation per volunteer+shift combination. Staff check-in screen with QR scan via camera plus manual token entry fallback. Individual check-in marks attendance with timestamp. Group check-in where scanning one group members QR checks in all linked members. Missing-info capture form when required fields are incomplete at check-in. Waiver/orientation validation gate that is configurable to block or warn. Decision for groups: group leader info must be complete; other members prompted individually for missing info at check-in.
- **Non-goals:** Hardware-specific kiosk mode, station assignment at check-in time.
- **Requirements covered:** FR15, FR16, FR9
- **Dependencies:** 005, 006, 007
- **Expected artifacts:**
  - QR generation utility using qrcode library
  - GET /signups/:id/qr endpoint
  - POST /checkins/scan endpoint (token to check-in)
  - CheckInEvent model with capturedFields JSON column
  - apps/web volunteer view showing their QR code
  - apps/web /staff/checkin page with scan, manual entry, and missing-info form
- **DoD items:**
  - QR code generated for each volunteer+shift combination
  - QR scan marks volunteer as checked-in with timestamp
  - Group QR scan checks in all linked group members
  - Missing-info form presented when required fields are incomplete
  - Check-in blocked or warned if waiver unsigned or orientation incomplete (configurable)
  - For groups: leader info validated first then other members prompted individually
  - npm run test includes unit tests for check-in logic (reject if waiver/orientation incomplete, group check-in)
  - npm run test:e2e includes playwright: generate QR -> scan -> attendance recorded -> missing info captured
  - npm run lint and npm run typecheck pass
- **Complexity:** high

### Sprint 010: Guided Matching & Recommendation Engine

- **Sprint number:** 010
- **Title:** Guided Matching & Recommendation Engine
- **Scope:** Conversational guided wizard capturing volunteer preferences for inside vs outside/mobile, time of day, and group size. Rule-based scoring algorithm that ranks available shifts against stated preferences. Returns ranked list with match scores. Falls back to full browse listing when no strong matches exist. Applies pathway constraints so court-required volunteers see only eligible shifts.
- **Non-goals:** Machine learning, AI personalization, historical preference learning.
- **Requirements covered:** FR21, FR22
- **Dependencies:** 003, 005
- **Expected artifacts:**
  - apps/web /match wizard route with preference capture steps
  - POST /recommendations API endpoint returning scored shifts
  - packages/shared scoring rules module with deterministic algorithm
  - Ranked results display component in web
- **DoD items:**
  - Preference capture accepts inside/outside, time-of-day, and group-size inputs
  - Algorithm scores shifts against stated preferences
  - Ranked list returned with match scores
  - Empty or low-match results fall back to full browse listing
  - Pathway constraints filter recommendations (court-required see only eligible shifts)
  - npm run test includes scoring unit tests (given prefs returns expected ordering)
  - npm run test:e2e includes playwright: complete wizard -> see recommended shifts -> open detail
  - npm run lint and npm run typecheck pass
- **Complexity:** medium

### Sprint 011: Shift/Station Planning Engine

- **Sprint number:** 011
- **Title:** Shift/Station Planning Engine
- **Scope:** Station CRUD with name, capacity, labor needs, and accessibility/sitting-only flags. Deterministic assignment algorithm: sort groups first then individuals, respect capacity limits, keep groups together, honor accessibility constraints. Plan generation endpoint for staff. Staff override endpoint for manual assignment adjustments.
- **Non-goals:** Optimal solver or optimizer, real-time websocket updates, cross-center aggregated view.
- **Requirements covered:** FR17, FR18, FR19
- **Dependencies:** 002, 005
- **Expected artifacts:**
  - Station model with StationConstraint in Prisma
  - ShiftPlan and StationAssignment models in Prisma
  - POST /staff/shifts/:id/stations endpoint
  - POST /staff/shifts/:id/plan/generate endpoint
  - PATCH /staff/shifts/:id/plan/assignments endpoint
  - Planning algorithm module with deterministic heuristic
  - apps/web staff shift planning page with generated plan and override controls
- **DoD items:**
  - Stations created with capacity and accessibility flags
  - Auto-assignment generates plan respecting capacity constraints
  - Groups are NOT split across stations (explicit test assertion required)
  - Accessibility and sitting-only needs are respected (explicit test assertion required)
  - Staff can override individual assignments via API
  - Regeneration after override preserves manual overrides or warns about conflicts
  - npm run test includes unit tests for planner with fixtures (groups + accessibility -> expected assignments)
  - npm run test:e2e includes playwright: create stations -> generate plan -> override one assignment -> verify persisted
  - npm run lint and npm run typecheck pass
- **Complexity:** high

### Sprint 012: Staff Run-of-Show Dashboard

- **Sprint number:** 012
- **Title:** Staff Run-of-Show Dashboard
- **Scope:** Daily run-of-show endpoint aggregating all shifts by day across centers and mobile volunteer opportunities. Staffing status showing filled vs unfilled per station. Check-in status overlay showing arrival counts. Staff web dashboard at /staff/run-of-show with date and center filters.
- **Non-goals:** Real-time websocket updates, advanced analytics or reporting exports.
- **Requirements covered:** FR20
- **Dependencies:** 009, 011
- **Expected artifacts:**
  - GET /staff/run-of-show?date=YYYY-MM-DD API endpoint
  - Aggregation service combining shifts, plans, and check-in stats
  - apps/web /staff/run-of-show page with date and center filters
- **DoD items:**
  - Endpoint returns all shifts for a given day across all centers
  - Mobile volunteer opportunities included in results
  - Staffing status shows filled vs capacity per station
  - Check-in counts reflected in the run-of-show data
  - npm run test includes unit tests for aggregation query/service
  - npm run test:e2e includes playwright: run-of-show page loads seeded day and shows correct counts
  - npm run lint and npm run typecheck pass
- **Complexity:** medium

### Sprint 013: End-of-Shift Engagement & Retention

- **Sprint number:** 013
- **Title:** End-of-Shift Engagement & Retention
- **Scope:** Digital impact card generation after shift completion with volunteer stats. Post-shift SMS sequence: impact message, shareable content link with social sharing URL, next-shift prompt with personalized recommendation from the recommendation engine. Monthly-giving CTA presenting Serving Hope membership with signup link. No payment processing.
- **Non-goals:** Donation processing, payment gateway integration, producing physical impact cards.
- **Requirements covered:** FR6, FR23, FR24, FR25, FR26
- **Dependencies:** 008, 009, 010
- **Expected artifacts:**
  - ImpactCard model and ImpactCardDelivery model in Prisma
  - Impact card generator service
  - Post-shift sequence scheduler triggered after check-in
  - Next-shift prompt logic using recommendation engine from Sprint 010
  - Giving-link generator for Serving Hope
  - apps/web /impact/:token public page with share buttons and next shift recommendations
- **DoD items:**
  - Digital impact card generated after shift with volunteer stats
  - Post-shift SMS sequence fires: impact message then share link then next-shift prompt
  - Share link generates shareable URL with impact summary
  - Next-shift prompt includes personalized recommendation from recommendation engine
  - Monthly-giving option presented with Serving Hope signup link
  - npm run test includes unit tests for impact card generation and trigger-only-for-checked-in logic
  - npm run test:e2e includes playwright: check-in complete -> post-shift trigger -> impact card link works -> CTA visible
  - npm run lint and npm run typecheck pass
- **Complexity:** low

### Sprint 014: Raiser's Edge NXT Integration

- **Sprint number:** 014
- **Title:** Raiser's Edge NXT Integration
- **Scope:** RE NXT sync adapter with abstract interface supporting API or batch plus mock client for testing. Match logic using email and cell phone fields with confidence scoring. Auto-sync high-confidence matches at or above 90 percent. Low-confidence matches below 90 percent routed to exception report for human resolution. Human resolution queue with accept, reject, and manual-match actions. Recognized supporter badge shown in volunteer portal when a match exists, retrofitting portal views from Sprints 003 and 004. First-wave constraint enforced: feed records into RE NXT without replacing it.
- **Non-goals:** Replacing Raiser's Edge NXT, bi-directional stewardship workflows, deep CRM unification.
- **Requirements covered:** FR27, FR28, FR29, FR30, FR31
- **Dependencies:** 004
- **Expected artifacts:**
  - packages/shared match scoring module
  - apps/api/src/integrations/raisersEdge/ adapter and mock client
  - DonorMatch model (confidence, status) in Prisma
  - SyncJobRun model in Prisma
  - ExceptionItem model in Prisma
  - POST /sync/raisers-edge/run API endpoint
  - GET /staff/sync/exceptions API endpoint
  - POST /staff/sync/exceptions/:id/resolve API endpoint
  - apps/web recognized supporter badge component in volunteer portal
  - apps/web /staff/sync/exceptions page
- **DoD items:**
  - Sync adapter sends volunteer records to RE NXT mock
  - Match logic uses email and cell phone fields
  - High-confidence matches at or above 90 percent are auto-synced
  - Low-confidence matches below 90 percent routed to exception report
  - Exception report lists all unresolved matches for human review
  - Human resolution endpoint supports accept, reject, and manual-match actions
  - Recognized supporter badge visible in volunteer portal for matched volunteers
  - First-wave constraint enforced: records feed into RE NXT, no replacement
  - npm run test includes unit tests for matching (email+phone exact = 100 percent, partial < 90 percent) and exception generation
  - npm run test:e2e includes playwright: seeded donor match shows badge; low-confidence appears in staff exceptions and can be resolved
  - npm run lint and npm run typecheck pass
- **Complexity:** high

### Sprint 015: PII-Free Artifacts & End-to-End Validation

- **Sprint number:** 015
- **Title:** PII-Free Artifacts & End-to-End Validation
- **Scope:** Generate blank planning spreadsheet with consistent unique non-PII identifiers produced in one shot (FR35 explicit deliverable). Generate anonymized sample datasets. Implement full E2E validation test for fully planned shift lifecycle covering signup, waiver, orientation, shift selection, station planning, check-in, post-shift engagement, and RE NXT sync. Package all PII-free artifacts with documentation.
- **Non-goals:** Adding new functional features, production-grade reporting exports.
- **Requirements covered:** FR32, FR33, FR34, FR35
- **Dependencies:** 012, 013, 014
- **Expected artifacts:**
  - scripts/generate_pii_free_artifacts.ts
  - artifacts/blank_planning.csv with unique non-PII identifiers
  - artifacts/sample_data.json with anonymized data
  - artifacts/README.md explaining no-PII guarantees
  - apps/web/e2e/fully_planned_shift.spec.ts with milestone assertions
- **DoD items:**
  - npm run artifacts generates blank_planning.csv and sample_data.json with no PII (only fake IDs)
  - Blank planning spreadsheet explicitly produced as deliverable with unique non-PII identifiers generated in one shot
  - E2E test passes asserting milestones: volunteer selects shift, registers, completes waiver, completes orientation, staff generates station plan, staff overrides one assignment, staff checks in volunteer via QR, post-shift impact card link works, RE NXT sync triggered
  - PII scan of all artifacts returns clean
  - npm run test passes
  - npm run lint and npm run typecheck pass
- **Complexity:** medium
