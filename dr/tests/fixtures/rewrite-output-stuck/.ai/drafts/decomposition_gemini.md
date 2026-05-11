# Project Decomposition: NIFB Volunteer Platform

## Sprint 001: Core Identity & Authentication
- **Scope**: Establish the canonical volunteer record and implement multi-modal authentication including phone/SMS, social logins, and email fallback.
- **Non-goals**: UI implementation, actual SMS delivery (using mock/logger for now), profile data collection beyond name/email/phone.
- **Requirements covered**: FR1, FR9, FR10, FR11, FR12
- **Dependencies**: None
- **Expected artifacts**: Database schema migrations, Auth service, Auth API endpoints.
- **DoD items**:
  - Volunteer and Identity database tables are migrated and verified.
  - `POST /api/auth/sms/send` successfully generates and stores a verification code.
  - `POST /api/auth/sms/verify` validates code and returns a session token.
  - Unit tests for Google/Apple OAuth callback logic pass with mocked provider responses.
  - Email/Password registration and login logic passes verification.
  - Returning user logic correctly matches records by phone OR email in automated tests.
  - Auth middleware correctly protects dummy routes.
- **Complexity**: Medium

## Sprint 002: Minimal Registration & Website Integration
- **Scope**: Create the initial web-entry surface that matches NIFB branding and allows minimal registration (Name, Phone, Email) without a redirect.
- **Non-goals**: Opportunity browsing, conversational logic, deferred data collection.
- **Requirements covered**: FR5, FR13, FR14, FR74, FR75, FR77
- **Dependencies**: 001
- **Expected artifacts**: Frontend shell (React/Vue/etc.), Shared CSS/Theme, Registration component.
- **DoD items**:
  - Frontend shell loads within a local test page mimicking the NIFB site (iframe or embed).
  - CSS variables/theme match NIFB brand guidelines (colors, typography).
  - Registration form validates input for Name, Email, and Phone number.
  - `POST /api/volunteers/register` persists minimal record to the database.
  - Automated tests confirm deferred fields (address, etc.) are NOT required for registration.
  - Frontend navigation prevents redirects to external domains.
- **Complexity**: Low

## Sprint 003: Opportunity Catalog & Calendar View
- **Scope**: Build the backend for volunteer opportunities and the visual calendar/list browse fallback.
- **Non-goals**: Conversational matching, urgency signals, registration integration.
- **Requirements covered**: FR6, FR19, FR20, FR76
- **Dependencies**: 002
- **Expected artifacts**: Opportunity database schema, Opportunity API, Calendar/List View components.
- **DoD items**:
  - Opportunity and Shift tables are migrated.
  - `GET /api/opportunities` returns a list of active shifts with location and capacity.
  - Calendar view displays shifts correctly across multiple locations.
  - List view correctly filters opportunities by location and date.
  - UI allows navigating between calendar and list views without page reload.
  - Unit tests for opportunity retrieval logic pass.
- **Complexity**: Medium

## Sprint 004: Conversational Discovery Engine - Phase 1
- **Scope**: Implement the conversational interface logic for capturing volunteer preferences and surfacing matching recommendations.
- **Non-goals**: Real-time urgency signals, SMS push, login-gate delay (already handled in 002).
- **Requirements covered**: FR17, FR18, FR21
- **Dependencies**: 003
- **Expected artifacts**: Conversation state machine, Recommendation engine, Chat UI component.
- **DoD items**:
  - Conversation engine supports branching logic based on user input.
  - Matching algorithm returns opportunities filtered by captured user preferences.
  - Chat UI renders "Urgency" badges for shifts with low availability/high need.
  - Users can transition from chat to the visual calendar view at any point.
  - Integration tests for "Matching" scenarios return expected shift IDs.
- **Complexity**: Medium

## Sprint 005: Digital Waiver Management
- **Scope**: Implement the digital e-sign waiver workflow and status tracking.
- **Non-goals**: Orientation tracking, check-in integration.
- **Requirements covered**: FR32, FR33, FR34, FR35
- **Dependencies**: 002
- **Expected artifacts**: Waiver template engine, E-sign component, Waiver status API.
- **DoD items**:
  - Waiver text is displayed as an interactive web component (not PDF).
  - Click-to-sign action captures timestamp and IP address.
  - `POST /api/volunteers/me/waiver` updates volunteer record and stores signature artifact.
  - Registration flow correctly redirects to waiver signing after shift selection.
  - Volunteer profile API returns correct `waiver_status`.
- **Complexity**: Medium

## Sprint 006: Orientation & Profile Maturity
- **Scope**: Deliver pre-shift video orientation and handle returning volunteer personalization.
- **Non-goals**: SMS reminders, Check-in validation.
- **Requirements covered**: FR15, FR16, FR37
- **Dependencies**: 004, 005
- **Expected artifacts**: Orientation video player component, Personalization API.
- **DoD items**:
  - Orientation video tracks "completion" event (not just click).
  - `orientation_completed` flag is persisted to the volunteer record.
  - Returning user dashboard shows "Suggested for You" based on past shift history.
  - Returning user flow skips waiver step if `waiver_status` is already valid.
  - Integration tests verify personalization logic for returning users with different histories.
- **Complexity**: Low

## Sprint 007: SMS Transactional Orchestration
- **Scope**: Integrate an SMS provider (Twilio or equivalent) and implement signup confirmations and reminders.
- **Non-goals**: Engagement SMS (impact, next-commitment), QR delivery.
- **Requirements covered**: FR3, FR39, FR40, FR45
- **Dependencies**: 001, 006
- **Expected artifacts**: SMS Service provider integration, SMS template manager.
- **DoD items**:
  - SMS provider API keys are configured and service is initialized.
  - Confirmation SMS is triggered and sent upon successful registration.
  - Reminder SMS (mocked cron/job) triggers 48 hours before a scheduled shift.
  - Opt-in/Opt-out logic (STOP/START) is handled according to TCPA compliance.
  - Unit tests for SMS template rendering pass.
- **Complexity**: Medium

## Sprint 008: Group Registration Foundation
- **Scope**: Build the intake flow for group leaders and track group identity/size.
- **Non-goals**: Group member individual check-in, group station assignment logic.
- **Requirements covered**: FR24, FR26, FR36
- **Dependencies**: 002
- **Expected artifacts**: Group database schema, Group Leader registration form.
- **DoD items**:
  - Group and GroupRegistration tables are migrated.
  - Registration form captures Group Name, Size, Org, and Leader contact info.
  - Group Leader can sign a waiver on behalf of the group (or self).
  - `POST /api/groups/register` creates linked records for leader and group entity.
  - Automated tests confirm group size constraints are respected during registration.
- **Complexity**: Medium

## Sprint 009: QR Issuance & Individual Check-In
- **Scope**: Generate QR codes for volunteers and implement the kiosk scanning workflow.
- **Non-goals**: Group check-in, donor recognition, station assignment display.
- **Requirements covered**: FR46, FR47, FR51, FR52
- **Dependencies**: 007, 008
- **Expected artifacts**: QR generation utility, Check-in API, Kiosk UI.
- **DoD items**:
  - QR code is generated and accessible via `GET /api/volunteers/me/qr`.
  - QR code link is sent via SMS confirmation.
  - `POST /api/check-in/scan` validates QR and marks volunteer as "Arrived".
  - Check-in logic flags missing waivers/orientation but allows proceeding (as per spec).
  - Kiosk UI displays "Welcome [Name]" after successful scan.
- **Complexity**: Medium

## Sprint 010: Group Check-In & On-site Recovery
- **Scope**: Implement headcount confirmation for groups and the tablet-based form for missing member details.
- **Non-goals**: Station assignment.
- **Requirements covered**: FR25, FR48, FR49
- **Dependencies**: 008, 009
- **Expected artifacts**: Group Check-in UI, On-site Member Intake form.
- **DoD items**:
  - Scanning a Group Leader QR initiates the "Group Headcount" flow.
  - Group Leader can confirm or adjust the final headcount at check-in.
  - Kiosk triggers "Member Detail Capture" form for anonymous group members.
  - `POST /api/groups/check-in` records arrival for the entire group block.
  - Unit tests for group headcount adjustments pass.
- **Complexity**: Medium

## Sprint 011: Location & Station Administration
- **Scope**: Provide staff tools for configuring locations, stations, and capacity.
- **Non-goals**: Assignment algorithm, run-of-show.
- **Requirements covered**: FR53, FR54
- **Dependencies**: 001
- **Expected artifacts**: Station Management UI, Station Configuration API.
- **DoD items**:
  - Staff can create/edit Locations (e.g., Joliet, Geneva).
  - Staff can define Stations within locations with Max/Min capacity and attributes.
  - Station attributes (accessibility, labor notes) are persisted and editable.
  - Station configurations are persisted across weeks (no weekly rebuild).
  - API validation prevents saving stations with invalid capacity ranges.
- **Complexity**: Low

## Sprint 012: Auto-Assignment Engine Logic
- **Scope**: Implement the core algorithm to generate draft station assignments based on constraints.
- **Non-goals**: Staff override UI, lock/unlock logic.
- **Requirements covered**: FR55, FR56
- **Dependencies**: 010, 011
- **Expected artifacts**: Assignment Algorithm module.
- **DoD items**:
  - Algorithm assigns all checked-in volunteers to available stations.
  - Hard constraint: Group members MUST be assigned to the same station.
  - Hard constraint: Accessibility needs MUST be matched to compatible stations.
  - Soft constraint: Balance staffing across priority stations (Min staffing first).
  - Unit tests with 100+ volunteers/groups generate a valid assignment plan in < 2 seconds.
- **Complexity**: High

## Sprint 013: Staff Assignment Review & Override
- **Scope**: Build the staff interface for reviewing and overriding the auto-assignment plan.
- **Non-goals**: Weekly planning view, Run of show.
- **Requirements covered**: FR57, FR58, FR59, FR60
- **Dependencies**: 012
- **Expected artifacts**: Assignment Review UI, Drag-and-drop implementation.
- **DoD items**:
  - Staff can view the auto-generated draft plan for a specific shift.
  - Drag-and-drop functionality allows moving volunteers between stations.
  - System displays "Warning" if a manual move violates capacity or group cohesion.
  - Staff can "Lock" a station to prevent further auto-optimization.
  - "Execute" action persists the final assignment plan.
- **Complexity**: High

## Sprint 014: Operational Run of Show & Planning
- **Scope**: Create the daily operational view and the weekly planning dashboard for staff.
- **Non-goals**: RE NXT integration, Reporting.
- **Requirements covered**: FR61, FR62, FR63
- **Dependencies**: 013
- **Expected artifacts**: Run of Show UI, Weekly Planning UI.
- **DoD items**:
  - Daily view shows timeline of all shifts across all centers.
  - Staff-specific views filter shifts by assigned staff member.
  - Weekly view highlights shifts with staffing gaps (Registrations < Min Staffing).
  - Run of show displays real-time check-in counts vs expected registrations.
  - Search/Filter by location and date works on both views.
- **Complexity**: Medium

## Sprint 015: RE NXT Integration - Discovery & Matching
- **Scope**: Connect to Raiser's Edge NXT and implement donor/corporate matching.
- **Non-goals**: Real-time activity sync, exception report UI.
- **Requirements covered**: FR64, FR65, FR66, FR67, FR68, FR69
- **Dependencies**: 001, 009
- **Expected artifacts**: RE NXT Client, Identity Matcher module.
- **DoD items**:
  - RE NXT API connection is established and authenticated.
  - Identity Matcher identifies existing donors by email/phone with >90% confidence.
  - Volunteer records are tagged with donor/corporate affiliation flags upon match.
  - Conversational UI shows personalized donor greeting if match is found during signup.
  - Check-in logic detects donor flag and surfaces it for staff-only visibility.
- **Complexity**: High

## Sprint 016: RE NXT Sync & Exception Management
- **Scope**: Implement activity syncing to RE NXT and the staff interface for low-confidence matches.
- **Non-goals**: Batch export fallbacks (unless API fails), volunteer-facing stats.
- **Requirements covered**: FR70, FR71, FR72, FR73
- **Dependencies**: 015
- **Expected artifacts**: Sync Worker, RE NXT Exception Report UI.
- **DoD items**:
  - Volunteer activity (shifts/hours) is pushed to RE NXT via API.
  - Exception report lists sub-90% matches with confidence scores.
  - Staff can manually "Confirm", "Reject", or "Merge" suggested matches.
  - Automated tests verify sync retry logic for API transient failures.
  - System generates a formatted CSV for ImportOmatic as a fallback.
- **Complexity**: High

## Sprint 017: Post-Shift Engagement
- **Scope**: Implement automated post-shift SMS touchpoints including impact cards and next commitments.
- **Non-goals**: SNAP/Court verification exports.
- **Requirements covered**: FR42, FR43, FR44, FR79
- **Dependencies**: 007, 009
- **Expected artifacts**: Impact Card generator, Engagement SMS triggers.
- **DoD items**:
  - Post-shift SMS triggers 15 minutes after shift end/checkout.
  - SMS includes a link to a personalized Impact Card with hours and social share links.
  - Second SMS follows with 3 suggested upcoming opportunities.
  - Milestone SMS (e.g., 50 hours) is triggered correctly.
  - Analytics track click-through rates on engagement links.
- **Complexity**: Medium

## Sprint 018: Special Volunteer Pathways (Skills & Court)
- **Scope**: Implement the intake flows for skills-based and court-required volunteers.
- **Non-goals**: SNAP hours, general reporting.
- **Requirements covered**: FR28, FR29, FR30
- **Dependencies**: 002, 014
- **Expected artifacts**: Skills Application form, Court Documentation intake.
- **DoD items**:
  - Skills-based flow captures interest, availability, and resume upload.
  - Pending skills applications are visible to staff in a prioritized queue.
  - Court-required flow collects supervising entity and required hours.
  - Records are correctly flagged as "Court-Required" for staff visibility.
  - Resume uploads are stored and accessible via staff dashboard.
- **Complexity**: Medium

## Sprint 019: SNAP Compliance & Verification
- **Scope**: Support SNAP-benefit volunteer tracking and official hours verification exports.
- **Non-goals**: General volunteer dashboard.
- **Requirements covered**: FR31, FR83
- **Dependencies**: 018
- **Expected artifacts**: SNAP tracking flags, Hours Verification PDF generator.
- **DoD items**:
  - SNAP-benefit volunteers are correctly flagged during registration/profile completion.
  - SNAP hours are tracked separately for compliance reporting.
  - Staff can generate a "Verified Hours" document (PDF/Print) for SNAP or Court volunteers.
  - Document includes official NIFB branding, volunteer name, hours, and date range.
  - Unit tests verify hours calculation for SNAP/Court exports.
- **Complexity**: Low

## Sprint 020: Dashboards & Reporting
- **Scope**: Finalize volunteer-facing impact dashboards and staff-facing operational reports.
- **Non-goals**: None.
- **Requirements covered**: FR78, FR80, FR81, FR82
- **Dependencies**: 014, 017, 019
- **Expected artifacts**: Volunteer Dashboard, Staff Reporting Suite, CSV Export utility.
- **DoD items**:
  - Volunteer Dashboard displays total hours, shift history, and upcoming shifts.
  - Staff Reporting Suite provides reports for registrations, check-ins, and assignments.
  - All staff reports support "Export to CSV" functionality.
  - Automated RE NXT data export (fallback/backup) runs on a weekly schedule.
  - User acceptance tests verify data consistency across all reporting views.
- **Complexity**: Medium
