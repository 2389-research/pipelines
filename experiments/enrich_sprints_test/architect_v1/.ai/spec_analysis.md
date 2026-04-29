# Spec Analysis: Food Bank Volunteer Portal Redesign

## Project Summary
- **Name:** Food Bank Volunteer Portal Redesign (Galaxy Digital replacement / redesign)
- **Purpose:** Replace or redesign the current Galaxy Digital volunteer experience for Northern Illinois Food Bank so volunteer discovery, signup, onboarding, check-in, shift operations, and downstream donor-system syncing are lower-friction and more hospitality-oriented.
- **Description:** The spec describes a volunteer platform that should feel fully integrated into the food bank website, minimize signup friction, support both individual and group volunteer journeys, modernize waivers/orientation/check-in, help staff plan and run shifts, and automatically connect volunteer activity to Raiser’s Edge NXT. The desired experience emphasizes warm, concierge-like guidance for volunteers while reducing spreadsheet-based manual work for staff. A major project boundary is that the first wave should improve the volunteer system and get records into Raiser’s Edge, but should not yet replace Raiser’s Edge stewardship workflows.

## Tech Stack

### Core stack signals from the spec
| Area | Extracted / inferred from spec |
|---|---|
| **Language** | **Unspecified**. No implementation language is named in the transcript. |
| **Framework** | **Unspecified web application / portal framework**. The system must be website-integrated and support conversational/guided flows, but no specific framework is named. |
| **Database** | **Unspecified transactional data store** for volunteers, opportunities, waivers, orientations, check-ins, assignments, and sync state. No specific database technology is named. |
| **Test framework** | **Unspecified**. The spec does define validation style: end-to-end simulation of signup, forms, orientation, and fully planned shifts. |
| **Linter** | **Unspecified**. |
| **Package manager** | **Unspecified**. |

### External systems / capabilities explicitly mentioned
| Area | Notes |
|---|---|
| **Existing system** | Galaxy Digital |
| **CRM / donor system** | Raiser’s Edge NXT |
| **Current import tool** | ImportOmatic |
| **Messaging** | SMS / text messaging is explicitly desired throughout the journey |
| **Check-in** | QR-code-based check-in is explicitly desired |
| **Content** | Video-based orientation / arrival guidance is explicitly desired |
| **Website integration** | Portal should feel native to the Northern Illinois Food Bank website |

## Functional Requirements (numbered)

| ID | Spec section reference | One-line description | Acceptance criteria if specified |
|---|---|---|---|
| **FR1** | **Transcript 00:03:19-00:04:50** | The system must maintain volunteer accounts that track participation/history for each person. | Volunteers can see how many hours they volunteered and when they volunteered; staff can track each person who comes in. |
| **FR2** | **Summary > Current state and core problems (Galaxy Digital volunteer portal); Summary > Reducing onboarding friction and improving authentication** | The volunteer experience must feel fully integrated into the food bank website rather than like a separate portal. | Acceptance criteria not formally specified beyond “feels fully integrated” and “warm, welcoming, concierge-like.” |
| **FR3** | **Summary > Reducing onboarding friction and improving authentication; Transcript 00:05:11-00:05:39; 00:30:24-00:31:14** | Initial signup should collect only minimal information up front. | Phone number and email are called out as most important; later the flow also references simple initial registration as name, phone number, and email, with everything else collected later. |
| **FR4** | **Summary > Reducing onboarding friction and improving authentication; Transcript 00:32:39-00:32:50** | The preferred flow is opportunities first, then login/account creation after a volunteer picks a shift. | Acceptance criteria not otherwise specified. |
| **FR5** | **Summary > Reducing onboarding friction and improving authentication; Transcript 00:36:47-00:37:21** | The system must handle existing-account detection gracefully instead of failing unclearly on duplicate email. | If an email already exists, the user should be told they need to log in rather than create an account. |
| **FR6** | **Summary > Reducing onboarding friction and improving authentication; Transcript 00:05:11-00:05:39; 00:35:33-00:36:14** | The system should support low-friction authentication methods. | Explicitly mentioned options are phone-number login via text code and sign-in with other accounts such as Google/Apple; Facebook is discussed but its usefulness is uncertain. |
| **FR7** | **Summary > Opportunity discovery and recommendations; Transcript 00:13:51-00:15:24** | The system must help volunteers discover opportunities through guided matching based on preferences. | Example inputs explicitly mentioned: inside/outside/mobile, time of day, and how many people are coming; output should recommend a suitable shift. |
| **FR8** | **Summary > Opportunity discovery and recommendations** | The discovery experience may use conversational guidance, with visual browsing shown when needed. | Acceptance criteria not formally specified beyond guided/conversational matching and optional visual calendar/table moments. |
| **FR9** | **Transcript 00:06:18-00:06:53** | For regular volunteering opportunities, the system must support sign-up into open slots without separate staff approval. | “There’s an open slot, I’ve signed up, I’m set” is the stated desired operating mode for regular opportunities. |
| **FR10** | **Summary > Group, special-case pathways, and routing; Transcript 00:06:53-00:07:36** | The system must support both individual and group volunteer signup flows. | Acceptance criteria not formally specified beyond handling group signup as a distinct pathway. |
| **FR11** | **Summary > Messaging, orientation, confirmations, and waivers; Summary > Group, special-case pathways, and routing** | The system must support a digital waiver process tied to each volunteer record. | Desired state is a clickable digital waiver that attaches to the volunteer record and has clearer completion tracking/validation. |
| **FR12** | **Summary > Messaging, orientation, confirmations, and waivers; Transcript 00:07:36-00:08:31** | The system must support orientation delivery and tracking. | Explicit examples: show arrival instructions, support online orientation/video, and let staff know whether someone clicked/saw the orientation before arrival. |
| **FR13** | **Summary > Messaging, orientation, confirmations, and waivers; Transcript 00:05:39-00:06:15; 00:16:25-00:17:11** | The system must send text-based communications before and after the shift. | Explicit examples: confirmation/pre-shift reminders, what-to-wear/where-to-go guidance, post-shift impact message, and easy follow-up prompts. |
| **FR14** | **Summary > Check-in modernization; Transcript 00:08:34-00:09:18** | The system must support QR-code-based check-in for volunteers. | It should allow quick scan-in for individuals and groups. |
| **FR15** | **Summary > Check-in modernization; Transcript 00:08:34-00:09:18** | The system should be able to capture missing group member details on site during check-in. | Explicitly discussed data: name and contact information for group members who were not fully entered in advance. |
| **FR16** | **Summary > Operations: shift staffing, station assignments, and “run of show”; Transcript 00:09:18-00:11:34** | The system must model locations, stations, labor needs/conditions, and capacity for volunteer shifts. | Explicitly mentioned inputs: stations, labor need per station, labor conditions, and maximum capacity per station. |
| **FR17** | **Summary > Operations: shift staffing, station assignments, and “run of show”; Transcript 00:10:24-00:11:34** | The system must auto-generate an initial station assignment plan from volunteers plus operational constraints. | Explicit constraints include keeping groups together and accommodating people who need to sit; the system should produce an “optimal” plan. |
| **FR18** | **Summary > Operations: shift staffing, station assignments, and “run of show”; Transcript 00:11:22-00:11:34** | Staff must be able to override and adjust the automatically generated assignment plan. | Example given: drag a person to a different station because they need to sit down. |
| **FR19** | **Summary > Operations: shift staffing, station assignments, and “run of show”; Transcript 00:13:19-00:13:39** | The system should provide a daily “run of show” view for staff. | It should show what is happening across shifts, centers, and mobile volunteer opportunities during the day. |
| **FR20** | **Summary > End-of-shift engagement and next commitment; Transcript 00:15:30-00:17:11** | The system should support a digital post-shift “impact card.” | Explicitly described as a digital version of the physical card that could be easy to share. |
| **FR21** | **Summary > End-of-shift engagement and next commitment; Transcript 00:16:25-00:17:11** | The system should capture the volunteer’s next commitment while post-shift motivation is high. | Explicit examples: sign up for the next shift and optionally join the monthly giving program (“Serving Hope member”). |
| **FR22** | **Summary > Donor database integration (Raiser’s Edge NXT) and record matching; Transcript 00:18:01-00:20:53** | Volunteer records must sync into Raiser’s Edge NXT without relying on the current monthly manual upload as the intended target state. | Desired state is automatic or real-time syncing rather than monthly export/import. |
| **FR23** | **Summary > Donor database integration (Raiser’s Edge NXT) and record matching; Transcript 00:18:43-00:20:34** | The system must perform donor/volunteer record matching during the volunteer flow. | Matching fields explicitly discussed: email and cell phone; desired outcome is early recognition of known donors/high-value people. |
| **FR24** | **Summary > Donor database integration (Raiser’s Edge NXT) and record matching; Transcript 00:20:34-00:20:53** | The system should surface an exception workflow for uncertain donor matches. | Explicit example: staff review cases where the system is below 90% confidence. |
| **FR25** | **Summary > Group, special-case pathways, and routing; Transcript 00:28:46-00:29:36** | The system must support a distinct skills-based volunteering pathway. | Explicit capabilities mentioned: opportunities for skills-based work, resume upload, and human review because it is more like applying than self-confirming. |
| **FR26** | **Summary > Group, special-case pathways, and routing; Transcript 00:29:36-00:30:13** | The system must support a distinct pathway for court-required community service volunteers. | Acceptance criteria not specified beyond routing through a dedicated process managed separately. |
| **FR27** | **Summary > Group, special-case pathways, and routing; Transcript 00:29:36-00:30:13** | The system should support a distinct pathway for people who need volunteer hours for benefits-related reasons. | The transcript mentions neighbors needing volunteer hours for SNAP benefits, but detailed rules/data requirements are not specified. |
| **FR28** | **Summary > Research/test workstream (PII-free artifacts, validation criteria, and prototyping); Transcript 00:41:37-00:43:05** | The project needs an end-to-end validation scenario that proves the system can handle a fully planned shift. | Explicit test idea: start with one location, simulate diverse volunteers (interests, skills, ages, groups/non-groups), and verify the system can move them through signup, forms, orientation, and automatic shift planning without a human in the loop. |

## Architectural Layers / Components (numbered)

| # | Component / layer | Description | Dependencies |
|---|---|---|---|
| **C1** | Public volunteer web experience | Website-embedded volunteer entry point and navigation shell for discovery, signup, and follow-up. | Depends on C2, C4, C5, C8 for real functionality. |
| **C2** | Identity, account lookup, and authentication | Handles minimal registration, returning-user detection, and low-friction login. | Foundational; no internal dependencies. |
| **C3** | Volunteer record / profile / history | Stores volunteer identity, participation history, hours, and related volunteer data. | Depends on C2. |
| **C4** | Opportunity catalog and guided discovery | Represents available opportunities and provides preference-based matching/recommendation. | Depends on C3 for personalization and C11/C10 for available shift data. |
| **C5** | Registration and group management | Supports individual and group registrations into shifts/opportunities. | Depends on C2, C3, and C4. |
| **C6** | Special-case pathway routing | Handles distinct flows for skills-based, court-required, and benefits-related volunteering. | Depends on C2, C3, C4, and C5. |
| **C7** | Waiver and orientation | Manages digital waivers, arrival guidance, and orientation status. | Depends on C3 and C5. |
| **C8** | Messaging and notification engine | Sends SMS confirmations, reminders, prep instructions, and post-shift messages. | Depends on C2/C3 for contact data and C5/C7/C9/C13 for event triggers. |
| **C9** | Check-in and onsite intake | QR-based arrival/check-in plus collection of any missing attendee information. | Depends on C5 and C7; can also use C11 assignment outputs. |
| **C10** | Shift structure and operational constraints | Models locations, stations, capacities, labor needs, and labor conditions. | Foundational for operations; depends on core data model in C3. |
| **C11** | Assignment planning engine | Generates station assignments based on registered volunteers and operational constraints. | Depends on C5 and C10. |
| **C12** | Staff run-of-show / operations view | Gives staff a coordinated day view across shifts, centers, and mobile opportunities. | Depends on C10, C11, and C9. |
| **C13** | Post-shift engagement and retention | Delivers digital impact cards, next-shift prompts, and monthly-giving prompts. | Depends on C9 and C8. |
| **C14** | Donor / CRM integration and match resolution | Syncs records to Raiser’s Edge NXT, performs matching, and surfaces exception cases. | Depends on C2, C3, C5, and possibly C9 for attendance confirmation. |
| **C15** | Validation / simulation harness | Simulates end-to-end flows and tests whether the system can produce a valid planned shift. | Depends on C5, C7, C9, C10, C11, and C14 to cover the stated finish line. |

## Dependency Graph

### Sequential backbone
1. **C2 Identity/authentication** must exist first because every later flow depends on being able to recognize new vs. returning volunteers.
2. **C3 Volunteer record/profile/history** follows identity so the system has a durable record for waivers, hours, communications, and syncing.
3. **C10 Shift structure and operational constraints** must be modeled before the system can recommend shifts accurately or plan assignments.
4. **C4 Opportunity catalog/discovery** depends on available opportunities being represented.
5. **C5 Registration/group management** depends on identity plus available opportunities.
6. **C7 Waiver/orientation** depends on a registered volunteer record.
7. **C11 Assignment planning** depends on both registered volunteers and defined station/capacity rules.
8. **C9 Check-in** depends on registration and waiver/orientation state; it may also consume assignment outputs.
9. **C13 Post-shift engagement** depends on attendance being captured.
10. **C14 CRM integration** depends on identity/profile data and registration/attendance events.
11. **C15 Validation harness** comes after the main flow exists, because it needs to exercise the whole chain.

### Components that can be built in parallel once the foundations are set
- **C1 Public volunteer web experience** can be developed in parallel with backend services after C2/C4/C5 interfaces are defined.
- **C8 Messaging/notifications** can be built in parallel with registration and check-in because its triggers can initially be mocked.
- **C14 CRM integration investigation** can start early in parallel because API availability, matching rules, and sync strategy are an open dependency independent of UI work.
- **C6 Special-case pathways** can branch from the common registration foundation and be implemented in parallel after the main intake model exists.
- **C12 Staff run-of-show** can progress in parallel with C11 once operational entities and assignment outputs are defined.
- **C15 Validation design** can begin early conceptually, but full automation depends on the core flow existing.

### Key gating dependencies / reasons
- **Discovery cannot be finalized before the opportunity/shift model exists**, otherwise recommendations have nothing structured to recommend.
- **Assignment planning cannot be done before stations/capacities and registrations exist**, because the optimization inputs are missing.
- **Post-shift follow-up should wait for trustworthy attendance capture**, otherwise the system may follow up with people who never arrived.
- **Raiser’s Edge syncing is gated by external-system knowledge**, especially API access, matching rules, and confidence thresholds.

## Complexity Assessment

| Component | Complexity | Justification |
|---|---|---|
| **C1 Public volunteer web experience** | Medium | UX scope is broad, but most complexity is orchestration of other services rather than deep business logic. |
| **C2 Identity, account lookup, and authentication** | Medium | Low-friction auth plus existing-account detection is straightforward conceptually but must be reliable and user-friendly. |
| **C3 Volunteer record / profile / history** | Medium | Core data modeling is standard, but it becomes the source of truth for many downstream workflows. |
| **C4 Opportunity catalog and guided discovery** | Medium | Discovery itself is manageable, but it depends on consistent opportunity structure and preference logic. |
| **C5 Registration and group management** | Medium-High | Group flows and partial/missing attendee data introduce more branching than a simple individual signup flow. |
| **C6 Special-case pathway routing** | High | Skills-based, court-required, and benefits-related paths have different rules and unclear details. |
| **C7 Waiver and orientation** | Medium | Digital forms/status tracking are tractable, but the split between online and human-led orientation is not fully settled. |
| **C8 Messaging and notification engine** | Medium | Event-driven texting is standard, but timing/content across the full journey adds coordination work. |
| **C9 Check-in and onsite intake** | Medium | QR-based arrival is straightforward, but group handling and missing-info capture add edge cases. |
| **C10 Shift structure and operational constraints** | Medium | Modeling stations/capacities/conditions is mostly data design, though correctness matters to later planning. |
| **C11 Assignment planning engine** | High | This is the core scheduling/constraint-solving problem and one of the most logic-heavy parts of the spec. |
| **C12 Staff run-of-show / operations view** | Medium | Mostly an aggregation/view problem, but it depends on several upstream systems being coherent. |
| **C13 Post-shift engagement and retention** | Medium | Flow logic is not deeply technical, but it must coordinate timing, messaging, and next-step actions. |
| **C14 Donor / CRM integration and match resolution** | High | External API/process uncertainty, duplicate handling, and confidence-based exception flows make this a major technical risk. |
| **C15 Validation / simulation harness** | High | The spec explicitly calls for realistic end-to-end simulation with diverse cases and a meaningful pass/fail finish line. |

## Rollout Phases
- **No phases defined.**
- The transcript does reference that the organization has hospitality-framework phases as part of a broader FY27 strategy, but those phases are **not defined in this spec file**.
- The spec does define two practical scope boundaries that are useful for planning:
  1. **First-wave boundary:** Replace/improve the volunteer experience through getting records into Raiser’s Edge NXT, but **do not replace Raiser’s Edge stewardship workflows yet**.
  2. **Pilot validation scope:** Start with **one location** for the end-to-end “perfectly planned shift” validation scenario.

## Open Questions
1. **Raiser’s Edge integration method:** Is there a usable API, or must the first implementation rely on import/export patterns? The transcript identifies this as the main open technical question.
2. **Authoritative match rules:** Is donor/volunteer matching based on email, phone, name, or some combination, and what constitutes a confident match?
3. **Confidence threshold details:** The transcript gives “below 90% confidence” as an example for exception handling, but does not define the actual threshold policy.
4. **Auth method scope:** Should the first version support only phone/SMS login, or also Google/Apple sign-in? Facebook is mentioned but not clearly desired.
5. **Exact required fields by pathway:** The spec clearly wants minimal upfront data, but does not fully define which later fields are mandatory for individuals, groups, skills-based volunteers, court-required volunteers, or benefits-related volunteers.
6. **Group member data timing:** Which group-member details must be collected before arrival versus at QR check-in on site?
7. **Waiver enforcement rules:** Must waiver completion be required before check-in, before assignment, or only before participation begins?
8. **Orientation ownership and rules:** What portion of orientation stays human-led on site versus completed online, and who owns creation/maintenance of orientation video content?
9. **Skills-based workflow details:** What review states, SLAs, and acceptance/rejection rules are needed for resume-based opportunities?
10. **Court-required community service workflow:** The spec says this goes through a specific managed process, but does not define the required data, approvals, or reporting.
11. **Benefits-related volunteer hours workflow:** This pathway is mentioned as emerging, but required data, proof/output documents, and business rules are not defined.
12. **Run-of-show scope:** Is photo-taking/picture-station coordination actually required in the first version, or just an idea to consider?
13. **Discovery UX scope:** Should the first version be fully conversational, guided-form based, visual-calendar based, or a hybrid?
14. **Volunteer dashboard scope:** The current system shows hours/history; the transcript implies those matter, but the desired replacement dashboard details are not fully specified.
15. **Operational planning algorithm details:** The transcript gives examples of constraints, but not the complete rule set for what counts as a “perfectly planned” shift.
16. **Admin workflow visibility:** The team still needs an admin walkthrough/screen recording; some back-office needs may be missing from this transcript alone.
17. **Success metrics beyond the simulation test:** The spec states a validation approach, but does not define production KPIs such as signup completion rate, waiver completion rate, or check-in time targets.
18. **Source artifacts not yet attached:** Hospitality framework docs, anonymized spreadsheets, and the blank planning document are referenced but not present in this file, so additional requirements may still surface from those materials.
