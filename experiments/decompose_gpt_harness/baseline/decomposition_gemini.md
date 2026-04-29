# Project Decomposition: Food Bank Volunteer Portal Redesign

## Sprint 001: Core Foundation & Domain Modeling
- **Scope**: Initialize the project structure and establish the core database schema for volunteers and opportunities. Define the base entities and relationships.
- **Non-goals**: UI development, authentication logic, external API integrations.
- **Requirements covered**: FR1, FR16
- **Dependencies**: None
- **Expected artifacts**: Project repository, database migrations, domain entity classes (Volunteer, Opportunity, Location, Station).
- **DoD items**:
    - Repository initialized with basic CI/CD pipeline.
    - Database schema for Volunteer and Opportunity entities is deployed.
    - Unit tests for the data access layer (CRUD operations) pass.
    - Seed script for initial locations and stations works.
    - API documentation for core entities is generated (e.g., Swagger/OpenAPI).
- **Complexity**: low

## Sprint 002: Identity & Authentication
- **Scope**: Implement minimal registration (name, phone, email) and low-friction login via SMS/Email OTP (One-Time Password). Include existing-account detection logic.
- **Non-goals**: OAuth (Google/Apple), full volunteer profile management.
- **Requirements covered**: FR3, FR5, FR6
- **Dependencies**: 001
- **Expected artifacts**: Auth service, OTP generation/validation modules, registration API.
- **DoD items**:
    - User can register with name, phone, and email via API.
    - System correctly detects existing email and returns a "Login Required" response instead of error.
    - OTP login via phone number works in a mocked environment.
    - JWT/Session-based authentication is implemented and verified.
    - Integration test for "Register -> OTP Request -> Verify -> Authenticated" flow passes.
- **Complexity**: medium

## Sprint 003: Opportunity Discovery
- **Scope**: Implement the opportunity catalog and preference-based filtering (inside/outside, time of day, location).
- **Non-goals**: Conversational AI interface, complex recommendation algorithms.
- **Requirements covered**: FR7, FR8
- **Dependencies**: 001
- **Expected artifacts**: Opportunity discovery API, preference filtering logic.
- **DoD items**:
    - API endpoint returns filtered opportunities based on location and time preferences.
    - Search functionality for shift dates is functional.
    - Unit tests for filtering logic pass with diverse test cases.
    - Mock UI for browsing opportunities allows selection of a shift.
- **Complexity**: medium

## Sprint 004: Individual Volunteer Signup
- **Scope**: Enable volunteers to pick a shift and sign up. Implement the "opportunity first, login later" flow logic.
- **Non-goals**: Group signups, waivers, orientation.
- **Requirements covered**: FR4, FR9
- **Dependencies**: 002, 003
- **Expected artifacts**: Registration/Signup flow logic, Shift booking API.
- **DoD items**:
    - Unauthenticated user can select a shift and is prompted to register/login.
    - After login, the previously selected shift is successfully booked.
    - API prevents booking when station capacity is reached.
    - E2E test: `curl` or automated script can complete a full booking flow.
- **Complexity**: medium

## Sprint 005: Group Management & Registration
- **Scope**: Support group signup flows. Allow volunteers to register as a group leader and reserve multiple slots.
- **Non-goals**: Capturing individual group member details (handled at check-in).
- **Requirements covered**: FR10
- **Dependencies**: 004
- **Expected artifacts**: Group entity, Group registration API.
- **DoD items**:
    - Volunteer can select "Group" signup and specify the number of attendees.
    - System reserves the requested number of slots for the group.
    - Validation ensures group size does not exceed remaining station capacity.
    - Group data is correctly persisted and linked to the lead volunteer.
    - Unit tests for group capacity logic pass.
- **Complexity**: medium

## Sprint 006: Digital Waivers & Orientation
- **Scope**: Implement digital waiver signing and orientation video tracking. Link completion status to the volunteer record.
- **Non-goals**: Dynamic waiver template editor, physical signature capture.
- **Requirements covered**: FR11, FR12
- **Dependencies**: 004
- **Expected artifacts**: Waiver service, Orientation status tracking, Waiver UI component.
- **DoD items**:
    - Digital waiver is presented post-signup and "Agreed" status is stored.
    - Orientation video "watched" status is tracked via API callback.
    - API returns waiver/orientation status for a given volunteer ID.
    - Check-in API rejects volunteers with incomplete waivers.
    - Unit tests for status transitions (e.g., Pending -> Completed) pass.
- **Complexity**: medium

## Sprint 007: QR Check-in & Onsite Intake
- **Scope**: Generate QR codes for registrations and implement scanning for check-in. Support onsite collection of missing attendee details.
- **Non-goals**: Automated printing of badges.
- **Requirements covered**: FR14, FR15
- **Dependencies**: 005, 006
- **Expected artifacts**: QR generation module, Check-in API, Onsite attendee intake form.
- **DoD items**:
    - QR code is generated and retrievable upon successful signup.
    - API endpoint for "Scan QR" marks the volunteer as checked-in.
    - Staff can add missing group member details (name, contact) during check-in via API/Form.
    - Integration test: Scanned check-in updates volunteer participation history in database.
- **Complexity**: medium

## Sprint 008: Messaging & Notifications
- **Scope**: Automated SMS notifications for shift confirmation, reminders, and arrival instructions.
- **Non-goals**: Marketing campaigns, two-way conversational SMS.
- **Requirements covered**: FR13
- **Dependencies**: 004
- **Expected artifacts**: Notification service, Message templates, Event-driven triggers.
- **DoD items**:
    - Shift confirmation message is sent immediately after booking.
    - Reminder message is triggered 24 hours before shift (verified via mock timer).
    - Arrival instructions (what to wear/where to go) are included in the reminder.
    - Unit tests for message template rendering pass.
- **Complexity**: medium

## Sprint 009: Assignment Planning Engine - Foundation
- **Scope**: Develop the engine that auto-assigns volunteers to stations based on capacity and labor needs.
- **Non-goals**: Proximity constraints (groups), specific accommodations (sitting).
- **Requirements covered**: FR17
- **Dependencies**: 001, 007
- **Expected artifacts**: Assignment engine module, Initial planning API.
- **DoD items**:
    - Engine fills stations up to their defined capacity.
    - Engine prioritizes critical labor needs based on station priority.
    - Automated test validates assignment distribution for a full shift (100+ volunteers).
    - Assignment plan is persisted and associated with the shift record.
- **Complexity**: high

## Sprint 010: Assignment Planning - Refinements & Overrides
- **Scope**: Handle group proximity (keeping groups together) and physical accommodations (sitting). Allow staff manual overrides.
- **Non-goals**: Real-time re-optimization during active check-in.
- **Requirements covered**: FR17, FR18
- **Dependencies**: 009
- **Expected artifacts**: Updated assignment engine, Staff override API/UI.
- **DoD items**:
    - Groups are kept at the same station if capacity permits.
    - Volunteers flagged as "needs sitting" are assigned to compatible stations.
    - Staff can manually move a volunteer to a different station via API.
    - Manual overrides are persisted and respected during subsequent planning runs.
- **Complexity**: high

## Sprint 011: Staff Run-of-Show
- **Scope**: Dashboard for staff to view daily activities across locations and manage shift operations.
- **Non-goals**: Detailed reporting/analytics, full CRM management.
- **Requirements covered**: FR19
- **Dependencies**: 009
- **Expected artifacts**: Run-of-Show UI, Staff Operations API.
- **DoD items**:
    - Dashboard displays all shifts for the current day filtered by location.
    - View shows registered vs. checked-in counts in real-time.
    - Staff can view the generated assignment plan for any active shift.
    - UI supports viewing volunteer details (waiver status, orientation status).
- **Complexity**: medium

## Sprint 012: Post-Shift Engagement
- **Scope**: Digital impact cards and next-commitment prompts (re-booking, monthly giving).
- **Non-goals**: Payment processing for monthly giving.
- **Requirements covered**: FR20, FR21
- **Dependencies**: 008, 011
- **Expected artifacts**: Impact card generator, Retention UI/API.
- **DoD items**:
    - Post-shift "Thank You" message includes a link to a digital impact card.
    - Impact card displays total hours volunteered by the individual.
    - Volunteer is prompted to book their next shift immediately after check-out.
    - "Serving Hope" monthly giving interest is tracked in the volunteer profile.
- **Complexity**: medium

## Sprint 013: CRM Integration - Sync Foundation
- **Scope**: Connect to Raiser’s Edge NXT API and implement basic volunteer profile sync.
- **Non-goals**: Exception handling (Sprint 014), complex matching rules.
- **Requirements covered**: FR22
- **Dependencies**: 002
- **Expected artifacts**: CRM integration service, Sync job/worker.
- **DoD items**:
    - Successful authentication and connection to Raiser’s Edge NXT API.
    - New volunteer records are created in CRM upon registration.
    - Volunteer participation hours are synced to CRM records.
    - Sync failures are logged and available for retry.
- **Complexity**: high

## Sprint 014: CRM Integration - Match & Exception Workflow
- **Scope**: Advanced record matching (email/phone) and a staff interface for resolving low-confidence matches.
- **Non-goals**: Automated merge of complex data conflicts.
- **Requirements covered**: FR23, FR24
- **Dependencies**: 013
- **Expected artifacts**: Match resolution UI, Confidence scoring logic.
- **DoD items**:
    - System calculates match confidence score based on email and phone.
    - Matches with <90% confidence are flagged as "Needs Review".
    - Staff UI allows "Link to Existing" or "Create New" decision for flagged records.
    - Integration test: Manual resolution correctly updates the CRM link.
- **Complexity**: high

## Sprint 015: Special Pathways - Skills-Based
- **Scope**: Application-style flow for skills-based volunteering. Includes resume upload and staff review.
- **Non-goals**: Court-required or SNAP pathways.
- **Requirements covered**: FR25
- **Dependencies**: 004, 011
- **Expected artifacts**: Skills-based application UI, Admin review API.
- **DoD items**:
    - Volunteers can upload a resume for specific skills-based opportunities.
    - Applications are assigned a "Pending" status for staff review.
    - Staff can approve/deny applications via the Admin UI.
    - Approved volunteers receive a notification and can then select relevant shifts.
- **Complexity**: medium

## Sprint 016: Special Pathways - Court & Benefits
- **Scope**: Distinct routing and specialized data collection for court-required and SNAP benefits volunteers.
- **Non-goals**: Automated reporting to external agencies.
- **Requirements covered**: FR26, FR27
- **Dependencies**: 004
- **Expected artifacts**: Specialized intake forms, Routing logic module.
- **DoD items**:
    - Volunteers can select "Court-Required" or "Benefits-Related" pathways at signup.
    - Specialized forms collect mandatory fields for these pathways.
    - Routing logic directs these volunteers into the appropriate management queue.
    - Basic reporting dashboard shows participation counts for these segments.
- **Complexity**: medium

## Sprint 017: End-to-End Validation & Polish
- **Scope**: Comprehensive simulation of a planned shift at one location. Final UX polish and website integration.
- **Non-goals**: Expanding to all locations (out of scope for first wave).
- **Requirements covered**: FR2, FR28
- **Dependencies**: All previous sprints.
- **Expected artifacts**: Validation report, Final integrated portal.
- **DoD items**:
    - Full shift simulation passes: 50+ diverse volunteers complete the entire journey.
    - System produces a valid, optimized assignment plan without manual intervention.
    - Portal styling is verified as "integrated" into a mock host website.
    - Load test: System handles 20 concurrent QR scans/check-ins.
    - All functional requirements (FR1-FR28) are verified via automated tests.
- **Complexity**: high
