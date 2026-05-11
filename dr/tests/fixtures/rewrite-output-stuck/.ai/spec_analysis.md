# Spec Analysis

## Project Summary

**Name:** NIFB Volunteer Platform  
**Purpose:** Replace Galaxy Digital with a custom volunteer management platform for Northern Illinois Food Bank (NIFB).  
**Description:** The specification defines a volunteer platform that manages the full volunteer lifecycle across discovery, signup, registration, waiver/orientation completion, check-in, shift operations, post-shift engagement, and donor-system integration. The experience is designed to feel native to the NIFB website, use a conversational web interface for rich interactions, use SMS for logistical and relationship touchpoints, and give staff operational tools for station planning, assignment review, reporting, and RE NXT exception handling.

## Tech Stack

| Category | Extracted / Inferred Stack |
|---|---|
| Language | **Not specified** in the spec |
| Framework | **Not specified**; inferred as a **web application** with an embedded conversational UI plus a web-based staff dashboard |
| Database | **Not specified**; inferred need for an application database storing volunteer records, waivers, orientation status, assignments, group data, and reporting data |
| Test framework | **Not specified**; the spec defines **scenario-based validation and milestone acceptance tests** in Section 12 |
| Linter | **Not specified** |
| Package manager | **Not specified** |

## Functional Requirements (numbered)

### Architecture

| ID | Spec reference | One-line description | Acceptance criteria if specified |
|---|---|---|---|
| FR1 | Section 1, Architecture | The web and SMS interaction surfaces must share a single backend and volunteer record. | — |
| FR2 | Section 1, Architecture | Provide a web conversational UI embedded in the NIFB website for signup, opportunity discovery, registration, waivers, orientation, group management, and staff operations. | — |
| FR3 | Section 1, Architecture | Provide an SMS layer for confirmations, pre-shift reminders, post-shift impact messages, next-commitment prompts, and open-opportunity notifications. | Section 12.2, SMS test |
| FR4 | Section 1, Architecture | Provide a web-based staff operations dashboard for station planning, auto-assignment, run-of-show, and RE NXT exception reports. | — |

### Signup & Authentication

| ID | Spec reference | One-line description | Acceptance criteria if specified |
|---|---|---|---|
| FR5 | Section 2, Entry Point | Embed the volunteer experience directly in the NIFB website with no redirect to a separate portal. | — |
| FR6 | Section 2, First Interaction: Opportunities First | Show available volunteer opportunities immediately with no login gate. | — |
| FR7 | Section 2, First Interaction: Opportunities First | Surface dynamic urgency signals for high-need shifts. | — |
| FR8 | Section 2, First Interaction: Opportunities First | Delay login/account creation until after a visitor selects a shift of interest. | — |
| FR9 | Section 2, Authentication | Support phone number plus SMS verification code as the primary authentication method, with no password. | — |
| FR10 | Section 2, Authentication | Support Google sign-in and Apple sign-in as secondary authentication methods. | — |
| FR11 | Section 2, Authentication | Support email plus password as a tertiary fallback authentication method. | — |
| FR12 | Section 2, Authentication | Detect returning users from existing phone numbers or email addresses and handle sign-in gracefully without a separate create-account vs. login fork. | Section 12.2, Signup test: returning volunteer is recognized and not asked to re-register |
| FR13 | Section 2, Required Fields at Signup | Collect only name, phone number, and email during initial registration. | Section 12.2, Signup test: new volunteer completes registration with only name, phone, email |
| FR14 | Section 2, Required Fields at Signup | Defer collection of address, emergency contact, employer, demographic information, and other secondary data until later interactions or check-in. | — |
| FR15 | Section 2, Returning Volunteer Experience | Show returning volunteers personalized suggested opportunities based on history, preferred locations, and past shift types. | — |
| FR16 | Section 2, Returning Volunteer Experience | Do not remind returning volunteers to complete a waiver if their waiver is already completed. | — |

### Opportunity Discovery & Recommendation

| ID | Spec reference | One-line description | Acceptance criteria if specified |
|---|---|---|---|
| FR17 | Section 3, Conversational Matching | Ask volunteer preference questions conversationally and support nonlinear/adaptive conversations based on volunteer input. | — |
| FR18 | Section 3, Conversational Matching | Recommend matching shifts based on the volunteer's responses. | Section 12.2, Discovery test |
| FR19 | Section 3, Visual Browsing Fallback | Provide a visual calendar/list browse view that is available at any point in the conversation. | — |
| FR20 | Section 3, Visual Browsing Fallback | Keep the calendar view consistent across locations. | — |
| FR21 | Section 3, Urgency and Dynamic Signals | Surface urgency messaging for shifts with open spots. | — |
| FR22 | Section 3, Urgency and Dynamic Signals | Proactively push open opportunities or pop-up events by SMS to volunteers who have opted in. | Section 12.2, SMS test |

### Volunteer Pathways

| ID | Spec reference | One-line description | Acceptance criteria if specified |
|---|---|---|---|
| FR23 | Section 4.1, Individual Volunteers | Support the standard individual volunteer flow: select shift, register, complete digital waiver, complete orientation, receive confirmation, and check in on shift day. | Section 12.1, Big Test end-to-end pipeline |
| FR24 | Section 4.2, Group Volunteers | Capture group leader registration fields: group name/organization, approximate group size, leader contact information, group ages, group type, and desired date/time preferences. | — |
| FR25 | Section 4.2, Group Volunteers | Do not require individual member names and contact details in advance; collect them at arrival through quick check-in. | Section 12.1, Big Test group scenario |
| FR26 | Section 4.2, Group Volunteers | Track group identity so groups can be kept together during station assignment. | Section 12.1, Big Test: assignments respect group constraints |
| FR27 | Section 4.2, Group Volunteers | Track waiver status for groups and require signed waivers before group members work. | — |
| FR28 | Section 4.3, Skills-Based Volunteers | Provide a skills-based volunteer application flow with interest capture, resume upload, availability/skills capture, acknowledgement, response-time expectation, and queueing for human review. | — |
| FR29 | Section 4.3, Skills-Based Volunteers | Surface pending skills-based applications and time-since-submission to staff. | — |
| FR30 | Section 4.4, Court-Required Community Service | Identify court-required volunteers, collect required hours/documentation/supervising entity, route them to the designated staff member, and support verified-hours printing/export. | — |
| FR31 | Section 4.5, SNAP Benefit Volunteer Hours | Flag SNAP-benefit volunteers, track their hours, and support documentation/export for benefit compliance. | — |

### Waivers & Orientation

| ID | Spec reference | One-line description | Acceptance criteria if specified |
|---|---|---|---|
| FR32 | Section 5, Digital Waiver | Present the waiver as an online clickable e-sign in the conversational flow rather than PDF or paper. | Section 12.2, Waiver test |
| FR33 | Section 5, Digital Waiver | Present the digital waiver during registration after shift selection and before confirmation. | Section 12.2, Waiver test |
| FR34 | Section 5, Digital Waiver | Support click-to-sign with timestamp and attachment of the signed waiver to the volunteer record. | Section 12.2, Waiver test |
| FR35 | Section 5, Digital Waiver | Store waiver completion status on the volunteer record and validate it at check-in, prompting on-site completion if incomplete. | Section 12.2, Waiver test |
| FR36 | Section 5, Digital Waiver | For groups, have the leader sign for themselves and allow individual members to sign at arrival if not completed in advance. | — |
| FR37 | Section 5, Orientation | Provide a pre-shift digital orientation video and verify completion rather than only tracking a link click. | Section 12.2, Orientation test |
| FR38 | Section 5, Orientation | Support a complementary staff-led in-person orientation on-site rather than replacing it. | — |

### SMS Orchestration

| ID | Spec reference | One-line description | Acceptance criteria if specified |
|---|---|---|---|
| FR39 | Section 6, Pre-Shift | Send an immediate signup confirmation SMS after registration. | Section 12.2, SMS test |
| FR40 | Section 6, Pre-Shift | Send a reminder 24-48 hours before the shift with logistics and a link to video orientation if not completed. | Section 12.2, SMS test |
| FR41 | Section 6, Pre-Shift | Support an optional day-of arrival-information SMS with directions and entry instructions. | — |
| FR42 | Section 6, Post-Shift | Send an immediate post-shift impact card with personalized impact data and one-tap social sharing. | Section 12.2, SMS test |
| FR43 | Section 6, Post-Shift | Send a next-commitment SMS about 15 minutes later with three upcoming opportunities. | Section 12.2, SMS test |
| FR44 | Section 6, Post-Shift / Ongoing | Support deeper-engagement follow-up messages, open-opportunity alerts, and milestone celebration messages. | Section 12.2, SMS test |
| FR45 | Section 6, SMS Orchestration | Require opt-in for all outbound SMS and comply with TCPA/messaging regulations. | — |

### Check-In

| ID | Spec reference | One-line description | Acceptance criteria if specified |
|---|---|---|---|
| FR46 | Section 7, QR Code Check-In | Deliver a QR code to each volunteer via SMS and their web profile. | — |
| FR47 | Section 7, QR Code Check-In | Allow kiosk or staff-device QR scanning to check in an individual volunteer without login or staff assistance on the happy path. | Section 12.2, Check-in test |
| FR48 | Section 7, Group Check-In | Let a group leader scan their QR code, show the registered group size, and confirm headcount. | Section 12.2, Check-in test: group leader scan initiates group check-in flow |
| FR49 | Section 7, Group Check-In | Provide a quick on-site capture form on a tablet/kiosk for group members whose details were not collected in advance. | — |
| FR50 | Section 7, Donor Recognition at Check-In | Cross-reference check-ins with Raiser's Edge NXT and show donor/corporate-partner recognition flags to staff only. | Section 12.2, RE NXT match test |
| FR51 | Section 7, Missing Information Capture | At check-in, detect incomplete waiver, orientation, or secondary information and prompt or flag the missing items appropriately. | — |
| FR52 | Section 7, Missing Information Capture | Default to letting the volunteer proceed rather than turning them away while capturing missing information. | — |

### Station Assignment & Operations

| ID | Spec reference | One-line description | Acceptance criteria if specified |
|---|---|---|---|
| FR53 | Section 8, Location & Station Configuration | Allow staff to define locations, stations within locations, and per-station attributes including maximum capacity, minimum staffing, labor/accessibility conditions, and special notes. | — |
| FR54 | Section 8, Location & Station Configuration | Persist station configuration per location and update it as operations change instead of rebuilding it weekly. | — |
| FR55 | Section 8, Auto-Assignment Algorithm | Generate a draft station assignment plan from registered volunteers and station configuration. | Section 12.2, Assignment test |
| FR56 | Section 8, Auto-Assignment Algorithm | Enforce group cohesion, accessibility compatibility, capacity limits, minimum staffing priority, and balancing constraints in auto-assignment. | Section 12.1, Big Test; Section 12.2, Assignment test |
| FR57 | Section 8, Auto-Assignment Algorithm | Require staff review before the generated assignment plan is executed. | — |
| FR58 | Section 8, Staff Override & Adjustment | Allow staff to drag and drop volunteers between stations and override any auto-assignment. | Section 12.2, Assignment test: staff can override without breaking constraints |
| FR59 | Section 8, Staff Override & Adjustment | Allow staff to add notes/flags to assignments and lock assignments to prevent re-optimization. | — |
| FR60 | Section 8, Staff Override & Adjustment | Re-validate constraints after each manual change and warn or flag on violations such as over-capacity or split groups. | Section 12.2, Assignment test |
| FR61 | Section 8, Run of Show | Provide a daily operations view with all shifts across centers, mobile opportunities, per-shift attendee/assignment/flag data, staff assignments, and a timeline view. | — |
| FR62 | Section 8, Run of Show | Show each staff member their relevant operational slice while allowing operations staff to see the full picture. | — |
| FR63 | Section 8, Weekly Planning View | Provide a one-week planning view showing shifts, registrations, staffing status, assignment completion status, and issues requiring attention. | — |

### Raiser's Edge NXT Integration

| ID | Spec reference | One-line description | Acceptance criteria if specified |
|---|---|---|---|
| FR64 | Section 9, Target State | Support real-time or near-real-time record linking between the volunteer platform and Raiser's Edge NXT. | — |
| FR65 | Section 9, Target State | Recognize known donors during the volunteer flow and sync volunteer activity to RE NXT automatically. | Section 12.2, RE NXT match test |
| FR66 | Section 9, Record Matching | Use email address and cell phone number as the record-matching fields. | — |
| FR67 | Section 9, Record Matching | Query RE NXT on signup or login and auto-link records when the match confidence is at least 90%. | Section 12.2, RE NXT match test |
| FR68 | Section 9, Record Matching | Tag linked volunteer records with donor status, giving level, and corporate affiliation when applicable. | — |
| FR69 | Section 9, Record Matching | Personalize the conversational flow with donor acknowledgement when an early RE NXT match is found. | — |
| FR70 | Section 9, Sync Direction | Push new volunteer records, volunteer activity, and volunteer status tags into RE NXT while keeping RE NXT as the donor system of record. | — |
| FR71 | Section 9, Exception Report | Surface sub-90% potential matches in a staff-facing exception report. | — |
| FR72 | Section 9, Exception Report | Show volunteer details, candidate RE NXT matches, confidence score/reason, and actions to confirm, reject, or merge manually. | — |
| FR73 | Section 9, Technical Risk | If RE NXT API access is limited or unavailable, fall back to automated daily/weekly batch export formatted for ImportOmatic ingestion and still generate the exception report from the volunteer-platform side. | — |

### Website Integration

| ID | Spec reference | One-line description | Acceptance criteria if specified |
|---|---|---|---|
| FR74 | Section 10, Website Integration | Match NIFB brand, typography, and color scheme so the UI feels native rather than like a bolted-on chatbot widget. | — |
| FR75 | Section 10, Website Integration | Keep the volunteer flow under the NIFB domain instead of redirecting to an external domain. | — |
| FR76 | Section 10, Website Integration | Integrate navigation so the main Volunteer entry point and returning-user dashboard/upcoming/history are part of the same experience. | — |
| FR77 | Section 10, Website Integration | Avoid any “return to our website” pattern because the volunteer experience is already on the website. | — |

### Reporting & Data

| ID | Spec reference | One-line description | Acceptance criteria if specified |
|---|---|---|---|
| FR78 | Section 11, Volunteer-Facing | Provide a volunteer dashboard with hours volunteered, shift history, upcoming shifts, and impact stats. | — |
| FR79 | Section 11, Volunteer-Facing | Provide shareable digital impact cards. | — |
| FR80 | Section 11, Staff-Facing | Provide staff tools for volunteer roster/search, shift registration reports, station assignment plans, check-in reports, waiver/orientation completion status, RE NXT exception reporting, group management, skills-based queue, and court-required hours documentation. | — |
| FR81 | Section 11, Export | Automate data export to RE NXT. | — |
| FR82 | Section 11, Export | Support CSV/report export for any staff-facing dataset. | — |
| FR83 | Section 11, Export | Support hours-verification printouts for court-required and SNAP-benefit volunteers. | — |

## Architectural Layers / Components (numbered)

1. **Shared Backend & Volunteer Record**  
   Description: Central application layer and canonical volunteer record used by web, SMS, staff tools, and integrations.  
   Dependencies: None.

2. **Website-Embedded Conversational UI**  
   Description: Native-feeling NIFB web experience for discovery, signup, registration, waiver/orientation, and volunteer self-service.  
   Dependencies: Shared Backend & Volunteer Record; Authentication & Identity.

3. **Authentication & Identity**  
   Description: Phone/SMS verification, Google/Apple sign-in, email/password fallback, and returning-user detection.  
   Dependencies: Shared Backend & Volunteer Record; SMS Orchestration.

4. **Opportunity Discovery & Recommendation Engine**  
   Description: Conversational preference capture, matching logic, urgency surfacing, and browse/calendar fallback.  
   Dependencies: Website-Embedded Conversational UI; Shared Backend & Volunteer Record.

5. **Volunteer Registration & Profile Completion**  
   Description: Minimal initial registration, deferred profile completion, returning-volunteer personalization, and volunteer profile management.  
   Dependencies: Authentication & Identity; Shared Backend & Volunteer Record.

6. **Group Management**  
   Description: Group leader intake, on-arrival member capture, group identity tracking, and group waiver handling.  
   Dependencies: Volunteer Registration & Profile Completion; Waiver Management; Check-In & QR Intake.

7. **Skills-Based Volunteer Intake Queue**  
   Description: Application flow for skills-based volunteers with resume capture, queueing, and staff aging visibility.  
   Dependencies: Website-Embedded Conversational UI; Shared Backend & Volunteer Record; Staff Operations Dashboard.

8. **Special Program Routing (Court-Required / SNAP)**  
   Description: Dedicated handling for court-required and SNAP-hours volunteers including flagging, documentation, and export.  
   Dependencies: Volunteer Registration & Profile Completion; Reporting & Exports; Staff Operations Dashboard.

9. **Waiver Management**  
   Description: Digital waiver presentation, e-sign capture, timestamping, status tracking, and check-in validation.  
   Dependencies: Volunteer Registration & Profile Completion; Shared Backend & Volunteer Record.

10. **Orientation Tracking**  
    Description: Pre-shift video orientation delivery and verified completion tracking, plus support for on-site staff-led orientation.  
    Dependencies: Volunteer Registration & Profile Completion; Shared Backend & Volunteer Record.

11. **SMS Orchestration**  
    Description: Transactional and engagement texting for confirmations, reminders, impact messages, next-commitment prompts, and alerts.  
    Dependencies: Shared Backend & Volunteer Record.

12. **Check-In & QR Intake**  
    Description: QR issuance, kiosk/staff-device scan flows, group headcount confirmation, and incomplete-data capture at arrival.  
    Dependencies: SMS Orchestration; Volunteer Registration & Profile Completion; Waiver Management; Orientation Tracking.

13. **Location / Station Configuration**  
    Description: Staff-maintained model of locations, stations, capacity, minimum staffing, accessibility/labor conditions, and notes.  
    Dependencies: Shared Backend & Volunteer Record; Staff Operations Dashboard.

14. **Auto-Assignment Engine**  
    Description: Draft station assignment generation using group, accessibility, capacity, minimum staffing, and balancing constraints.  
    Dependencies: Location / Station Configuration; Group Management; Volunteer Registration & Profile Completion.

15. **Staff Operations Dashboard**  
    Description: Staff-facing interface for planning, assignment review/override, run of show, weekly planning, and operational visibility.  
    Dependencies: Shared Backend & Volunteer Record; Location / Station Configuration; Auto-Assignment Engine; Check-In & QR Intake; RE NXT Integration.

16. **RE NXT Integration & Matching**  
    Description: Donor matching, donor-recognition flags, activity sync, and low-confidence exception handling.  
    Dependencies: Shared Backend & Volunteer Record; Volunteer Registration & Profile Completion; Check-In & QR Intake.

17. **Reporting & Exports**  
    Description: Volunteer-facing dashboards, staff reporting, CSV exports, court/SNAP documentation, and RE NXT export support.  
    Dependencies: Shared Backend & Volunteer Record; Check-In & QR Intake; Staff Operations Dashboard; RE NXT Integration.

## Dependency Graph

### Core dependency chain

- **Shared Backend & Volunteer Record** is the foundation for every other component.
- **Authentication & Identity** depends on the backend and is an early prerequisite for personalized returning-user flows.
- **Volunteer Registration & Profile Completion** depends on authentication/identity and feeds waiver, orientation, group handling, check-in, donor matching, and reporting.
- **Waiver Management** and **Orientation Tracking** depend on registration/profile data and must be in place before complete check-in validation exists.
- **Check-In & QR Intake** depends on SMS (for QR delivery), registration/profile data, and waiver/orientation status.
- **Location / Station Configuration** must exist before the auto-assignment engine can produce valid plans.
- **Auto-Assignment Engine** depends on station configuration plus volunteer/group/accessibility data from registration.
- **Staff Operations Dashboard** depends on configuration, auto-assignment outputs, check-in data, and RE NXT donor flags.
- **Reporting & Exports** depends on activity captured across registration, check-in, operations, and integrations.

### Components that can be built in parallel

- After the **Shared Backend & Volunteer Record** exists, these can progress largely in parallel:
  - **Website-Embedded Conversational UI**
  - **SMS Orchestration**
  - **Location / Station Configuration**
  - **RE NXT Integration & Matching** (at least the discovery/spike and interface layer)
  - **Reporting & Exports** scaffolding
- After **Volunteer Registration & Profile Completion** exists, these can also proceed in parallel:
  - **Waiver Management**
  - **Orientation Tracking**
  - **Skills-Based Volunteer Intake Queue**
  - **Special Program Routing (Court-Required / SNAP)**

### Components that must be sequential

1. **Authentication & Identity → Registration & Profile Completion**  
   Why: returning-user recognition and minimal signup are prerequisites for an actual volunteer record.

2. **Registration & Profile Completion → Waiver / Orientation / Group Management**  
   Why: waiver state, orientation status, and group identity attach to a volunteer or group record.

3. **Location / Station Configuration + Group/Accessibility Data → Auto-Assignment Engine**  
   Why: the assignment algorithm cannot evaluate capacity, minimum staffing, accessibility, or group cohesion without those inputs.

4. **SMS Orchestration + Registration → Check-In & QR Intake**  
   Why: QR codes are delivered via SMS and profile, and check-in only works for registered volunteers/groups.

5. **RE NXT Integration → Donor Recognition in Signup and Check-In**  
   Why: donor acknowledgements and staff donor flags depend on a successful donor match.

6. **Check-In / Assignment / Activity Capture → Reporting & Exports**  
   Why: reports and documentation are downstream outputs of operational events.

## Complexity Assessment

| Component | Complexity | Justification |
|---|---|---|
| Shared Backend & Volunteer Record | High | It is the integration hub for web, SMS, operations, waivers, assignments, reporting, and RE NXT data. |
| Website-Embedded Conversational UI | Medium | It spans many flows and must feel native to the website, but the spec does not define advanced AI behavior beyond adaptive conversation. |
| Authentication & Identity | Medium | Multiple auth methods plus graceful returning-user detection increase edge cases. |
| Opportunity Discovery & Recommendation Engine | Medium | It must support conversational and browse modes, urgency surfacing, and matching logic, but the matching rules are lightly specified. |
| Volunteer Registration & Profile Completion | Medium | Minimal signup plus deferred data capture touches many downstream workflows. |
| Group Management | Medium | Group leader intake is straightforward, but arrival-day member capture and assignment cohesion add workflow complexity. |
| Skills-Based Volunteer Intake Queue | Low | The requirements are mostly form capture, queueing, and staff visibility. |
| Special Program Routing (Court-Required / SNAP) | Low | The core behavior is flagging, routing, tracking, and documentation export. |
| Waiver Management | Medium | E-sign capture, timestamping, storage, and check-in validation require durable workflow/state handling. |
| Orientation Tracking | Low | The required functionality is primarily content delivery plus verified completion tracking. |
| SMS Orchestration | Medium | It involves multiple timed touchpoints, personalization, opt-in management, and compliance constraints. |
| Check-In & QR Intake | Medium | It combines QR issuance/scanning, group handling, missing-data capture, and donor/staff flags in an on-site workflow. |
| Location / Station Configuration | Low | It is mostly structured administrative configuration. |
| Auto-Assignment Engine | High | It must satisfy multiple hard constraints and produce a valid, staff-reviewable draft plan. |
| Staff Operations Dashboard | High | It aggregates planning, override workflows, run-of-show visibility, and weekly operations views across locations and shifts. |
| RE NXT Integration & Matching | High | The spec flags this as the single largest open technical dependency and includes confidence-based matching and fallback behavior. |
| Reporting & Exports | Medium | The reporting surface is broad, but most outputs are straightforward views and exports of operational data. |

## Rollout Phases

The spec does **not** define named versions such as v0/v1/v2, but it does define an explicit rollout sequence in Section 12:

1. **Pilot phase: single-location validation**  
   Start with one location and validate the full loop: signup, waiver, orientation, check-in, station auto-assignment, post-shift engagement, and reporting/integration behaviors.

2. **Expansion phase: additional locations**  
   Expand to additional locations only after the single-location pilot passes.

## Open Questions

1. **RE NXT API dependency remains unresolved.** Section 9 states API availability/capabilities are unconfirmed and calls this the highest-priority technical investigation.
2. **Exact latency target for “real-time or near-real-time” sync is unspecified.** The target state is named, but no SLA or timing threshold is given.
3. **There is a direct tension between Section 8 and Section 12.** Section 8 says auto-assignment produces a draft plan that does not execute without staff review, while Section 12 Big Test says the system should produce a fully valid shift plan with no human intervention.
4. **Handling for groups of 20+ is ambiguous.** Section 3 says the system “could” direct them to a live person or ask additional probing questions, which leaves the exact behavior unspecified.
5. **The streamlined experience for repeat/frequent volunteers is not concretely defined.** Section 4.1 indicates it can reduce friction, but does not specify exact flow changes.
6. **Day-of arrival SMS is optional, but sending rules are undefined.** Section 6 does not define when it should fire or for whom.
7. **RE NXT exception-resolution cadence is left open.** Section 9 says daily or weekly depending on volume, but no default operating rule is defined.
8. **SMS provider selection is unresolved.** Open Items lists Twilio or equivalent as TBD, along with TCPA compliance implications.
9. **Website integration approach depends on the current NIFB website stack.** Open Items says embed/iframe/subdomain approach is still unknown.
10. **Orientation video ownership is unresolved.** The system requires the content to exist, but the spec says ownership/maintenance is unknown.
11. **Data warehouse interface is TBD.** The spec calls for CSV/report export support, but the actual downstream integration approach is not defined.
12. **Corporate/company recognition rules are unresolved.** Open Items says matching logic for corporate groups and donor relationships is TBD.
13. **Skills-based volunteer response SLA is unresolved.** The system should set expectations on response time, but the actual SLA is not specified.
14. **Additional source material may still be missing.** Open Items notes the hospitality framework PDF/proxy volunteer list and Galaxy Digital admin walkthrough may contain important workflow detail not yet incorporated.
15. **Implementation stack choices are unspecified.** The spec does not name language, framework, database, linter, package manager, or testing tools.
