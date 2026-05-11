# NIFB Volunteer Platform — System Design Spec

**Client:** Northern Illinois Food Bank (NIFB)
**Project Lead:** Justin Massa, Remix Partners
**Client Champion:** Colleen Ahearn, NIFB
**Date:** 2026-04-14
**Status:** Draft

## Overview

A custom volunteer management platform replacing Galaxy Digital for Northern Illinois Food Bank. The system covers the complete volunteer lifecycle: discovery, signup, registration, check-in, shift operations, post-shift engagement, and donor database integration.

## Design Principles

These principles are derived directly from NIFB's hospitality framework and the discovery call:

1. **Concierge, not portal.** The system feels like talking to a helpful person, not navigating a software product. Conversational where possible. No unnecessary pages, buttons, or steps.
2. **Lowest friction wins.** Collect only what's needed, when it's needed. Phone number and email first. Everything else later.
3. **Humans do human things.** The system handles logistics, routing, assignment, and communication. Staff are freed to greet, teach, tell stories, and build relationships.
4. **Integrated, not adjacent.** The volunteer experience is part of the NIFB website. It does not feel like a third-party tool. It does not feel like leaving.
5. **Prepared, Empowered, Impactful.** These are NIFB's three guiding volunteer experience principles. Every feature decision should reinforce at least one.

## Source Materials

This spec synthesizes the following artifacts:

- Email thread between Colleen Ahearn and Justin Massa (Feb 24-25, 2026)
- Discovery call transcript (Mar 6, 2026) — 50-minute recorded session
- Follow-up email from Colleen with hospitality framework + proxy list (Mar 11, 2026)
- "The Volunteer Experience: Our Hospitality Brand" PowerPoint presentation
- NIFB FY27 strategic plan phases (embedded in the PowerPoint)

---

## 1. Architecture

**Approach: Hybrid — Conversational Web + SMS Orchestration**

Two interaction surfaces sharing a single backend and volunteer record:

- **Web conversational UI** — embedded in the NIFB website. Handles all rich interactions: signup, opportunity discovery, registration, waivers, orientation, group management, and staff operations.
- **SMS layer** — handles the relationship and logistics channel: confirmations, pre-shift reminders, post-shift impact messages, next-commitment prompts, and open-opportunity notifications.

**Staff operations dashboard** — web-based. Station planning, auto-assignment, run-of-show, RE NXT exception reports.

Each channel does what it's best at. The web handles interactions that need visual richness (browsing shifts, managing groups, drag-and-drop station assignment). SMS handles interactions that need to meet people where they are (reminders, engagement, quick confirmations).

---

## 2. Volunteer Journey — Signup & Authentication

### Entry Point

The volunteer experience is embedded directly in the NIFB "Solve Hunger Today" website. When a visitor clicks "Volunteer," they enter the conversational interface. There is no redirect to a separate portal. The experience must feel native to the NIFB site.

### First Interaction: Opportunities First

The landing experience shows available volunteer opportunities immediately. No login gate. The visitor can browse what's available before committing to anything.

Dynamic urgency signals surface high-need shifts: "Volunteers urgently needed — spots going fast!" This draws people in and creates momentum.

Login/account creation happens after the visitor selects a shift they're interested in — not before.

### Authentication

**Primary method:** Phone number + SMS verification code. The visitor enters their phone number, receives a text with a code, enters the code. Done. No password. This is the Toast/airport-ordering model.

**Secondary methods:** Google sign-in, Apple sign-in. One-tap authentication via existing accounts.

**Tertiary fallback:** Email + password for users who prefer traditional login.

**Returning user detection:** If a phone number or email already exists in the system, the system recognizes them: "Welcome back, [name]!" There is no confusing "create account vs. log in" fork. The system figures it out. If an email is already registered and someone tries to create a new account, the system handles it gracefully: "Looks like you've been here before! Let's get you signed in."

### Required Fields at Signup

Only three fields are collected at initial registration:

1. Name
2. Phone number
3. Email

Everything else — address, emergency contact, employer, demographic information — is collected later. This happens either conversationally over subsequent interactions or at check-in. The principle: never ask for information you don't need right now.

### Returning Volunteer Experience

Returning volunteers land on personalized suggested opportunities based on their history, preferred locations, and past shift types. No "volunteer with us" splash page. No waiver reminders if the waiver is already completed. The system knows who they are and acts accordingly.

---

## 3. Opportunity Discovery & Recommendation

### Conversational Matching

The system asks preference questions conversationally:

- "What kind of volunteering are you looking for?" (sorting/packing inside, mobile distribution outside, etc.)
- "What times work for you?"
- "Are you coming alone or with a group?"
- "Do you have a preferred location?"

Based on responses, the system recommends matching shifts. The conversation can be nonlinear — a volunteer can lead with "I have a group of 20 on Saturday" and the system adapts.

If they have a group of 20+ then it could direct them to a live person that can provide an hospitable approach to designing their groups volunteer experience. Or it can ask other probing questions like — how many, ages, what is the goal of your experience, what dates or times work best — if there isn't a current match in the system then a live person can contact them.

### Visual Browsing Fallback

When a volunteer wants to browse rather than be guided, the system provides a visual calendar/list view. This is available at any point in the conversation — it's a tool, not the default experience.

The calendar view must be consistent across locations (unlike Galaxy Digital, where each location page has different information and layout).

### Urgency and Dynamic Signals

Shifts with open spots surface with urgency messaging. The system can proactively push open opportunities via SMS to volunteers who have opted in (automatic texts sharing open opportunities or pop-up events, per Colleen's request).

---

## 4. Volunteer Pathways

The system supports five distinct pathways, routed based on conversation:

### 4.1 Individual Volunteers

Standard flow: Select shift → Register (if new) → Digital waiver → Orientation → Confirmation → Check-in on shift day.

For repeat / frequent individual volunteers, we can offer them a streamlined experience that reduces friction; for less frequent / new volunteers we want to invite them to engage with NIFB in other ways.

### 4.2 Group Volunteers

The group leader registers with:

- Group name/organization
- Approximate group size
- Leader's contact information
- Ages of the group
- Type of group: sports team, girl scouts, corporate group etc.
- Desired date and times day or night, weekday or weekend

Individual member names and contact details are NOT required in advance. This is a major change from current process, which requires extensive back-and-forth to collect every name before the shift. Instead, individual details are collected at arrival via a quick check-in process.

The system tracks group identity to ensure groups are kept together during station assignment. All groups will need to sign a waiver before they can work; the system should track the status of the waiver.

### 4.3 Skills-Based Volunteers

This is an application, not a signup. Skills-based volunteering is essentially a part-time role (administrative work, database help, etc.).

Flow: Express interest → Upload resume → Describe availability and skills → System acknowledges receipt and sets expectations on response time → Queued for human review.

This pathway requires staff involvement. The system manages the intake and queuing. A staff member (currently one part-time person) reviews and matches. The system should surface pending applications and time-since-submission to prevent things from falling through the cracks.

### 4.4 Court-Required Community Service

Special pathway with dedicated staffing. The system:

- Identifies the volunteer as court-required during the conversational flow
- Collects relevant details (required hours, documentation needs, supervising entity)
- Routes to the specific staff member who manages this program
- Supports printing/exporting verified hours for submission to courts

### 4.5 SNAP Benefit Volunteer Hours

Emerging pathway. Volunteers needing documented hours for SNAP benefits are flagged in the system. The system tracks hours and supports documentation/export for benefit compliance. This pathway may evolve as the program develops.

---

## 5. Waivers & Orientation

### Digital Waiver

The waiver is a clickable e-sign presented within the conversational flow. No PDF. No paper. No downloading a document and emailing it back.

Requirements:

- Presented online during registration (after shift selection, before confirmation)
- Click-to-sign with timestamp and record attachment
- Completion status is stored on the volunteer record
- Validated at check-in: if incomplete, the system catches it and prompts completion on-site
- For groups: the leader signs for themselves; individual members sign at arrival if not completed in advance

The current waiver process (PDF download, paper backup at the site, weak tracking) is eliminated entirely.

### Orientation

Two modes, complementary:

**Digital orientation (pre-shift):** A video that covers logistics and safety. The system tracks whether the volunteer has watched it (completion verification, not just a link click). This handles the "what to wear, where to park, what to expect" content.

**In-person orientation (on-site):** Staff-led. This is the human element — storytelling, mission connection, group rituals. The system does not replace this. The hospitality framework is clear that pre/post-shift rituals and human connection are core to the experience.

The digital orientation reduces the burden on in-person time so staff can focus on warmth and mission rather than logistics.

---

## 6. SMS Orchestration

SMS is the relationship and logistics backbone. The system sends texts at these touchpoints:

### Pre-Shift

- **Signup confirmation:** Immediately after registration. Brief. "You're signed up for [shift] at [location] on [date]. We're excited to see you!"
- **Reminder (24-48 hrs before):** "Your shift is tomorrow! Wear closed-toed shoes. Park in Lot B. [Link to video orientation if not completed]"
- **Day-of arrival info:** Optional. Directions, door to enter, who to ask for.

### Post-Shift

- **Immediate — impact card:** Digital card with personalized impact data. "Today you packed 500 backpacks for kids in DuPage County." One-tap social sharing.
- **~15 minutes later — next commitment:** "We loved having you. Ready for your next shift? Here are three upcoming opportunities: [A] [B] [C]"
- **Follow-up — deeper engagement:** Option to join Serving Hope monthly giving program. Option to hear about other ways to support.

### Ongoing

- **Open opportunity alerts:** For opted-in volunteers, proactive texts when shifts need filling or pop-up events are scheduled.
- **Milestone celebrations:** Hour milestones, anniversary of first volunteer shift, etc.

All outbound SMS requires opt-in and must comply with TCPA/messaging regulations.

---

## 7. Check-In

### QR Code Check-In

Each volunteer receives a QR code — delivered via SMS (pre-shift reminder) and available in their web profile. At the site, they scan at a kiosk or with a staff member's device. Scan = checked in. No logging in. No staff assistance required for the happy path.

### Group Check-In

The group leader scans their QR code. The system shows the registered group size. Leader confirms headcount. For members whose individual details weren't collected in advance, the system presents a quick capture form (name, phone, email) that can be completed on a tablet/kiosk on-site.

### Donor Recognition at Check-In

When a volunteer checks in, the system cross-references with Raiser's Edge NXT (see Section 9). If the volunteer is a known donor, staff are notified: "This person is a Circle of Hope donor" or "This person's company [X] is a major corporate partner." The donor flag at check-in is staff-facing only — the volunteer does not see it. (Note: during the earlier signup flow, the system may warmly acknowledge a known donor's relationship — see Section 9, "During the conversational flow." These are distinct moments: the signup acknowledgment is volunteer-facing; the check-in flag is staff-facing.)

### Missing Information Capture

Check-in is a catch-all for anything incomplete:

- Waiver not signed? Prompted on-site.
- Orientation video not watched? Flagged for staff (in-person orientation covers it).
- Address or other secondary info missing? Quick prompt.

The principle: never turn someone away. Capture what's needed, but default to letting them through.

---

## 8. Station Assignment & Operations

This section addresses the largest manual workload: the weekly coordination between volunteer and operations teams that currently happens via spreadsheets and manual slotting.

### Location & Station Configuration

Staff defines the physical infrastructure:

- **Locations:** Geneva, Joliet, Lake Forest, Rockford, etc.
- **Stations within each location:** Packing Line 1, Packing Line 2, Sorting Station A, etc.
- **Per-station attributes:**
    - Maximum capacity (number of volunteers)
    - Minimum staffing need
    - Labor conditions (standing, sitting-available, accessibility-friendly, outdoor/indoor)
    - Any special requirements or notes

This configuration is set up once per location and updated as operations change. It is not rebuilt weekly.

### Auto-Assignment Algorithm

Given a set of registered volunteers for a shift and the station configuration, the system generates an optimal assignment plan. The algorithm respects these constraints:

1. **Group cohesion:** Volunteers who registered as a group are assigned to the same station.
2. **Accessibility needs:** Volunteers who indicated sitting-only or accessibility requirements are assigned to compatible stations.
3. **Capacity limits:** No station exceeds its maximum capacity.
4. **Minimum staffing:** The plan attempts to meet minimum staffing for all stations before over-staffing any single station.
5. **Balance:** Distribute volunteers as evenly as practical across stations after constraints are satisfied.

The algorithm produces a draft plan. It does not execute without staff review.

### Staff Override & Adjustment

After the draft plan is generated, staff can:

- Drag and drop volunteers between stations
- Override any auto-assignment
- Add notes or flags to individual assignments
- Lock assignments to prevent re-optimization

The system re-validates constraints after each manual change (warns if a station is over-capacity, flags if a group is split, etc.).

### Run of Show

A daily operations view that shows:

- All shifts across all centers for the day
- Mobile volunteer opportunities
- Per-shift: who's coming, station assignments, any flags (donor, accessibility, first-time, group leader)
- Staff assigned to each shift/station
- Timeline view of the day

This replaces the current spreadsheet-based coordination. Each staff member sees their relevant slice. Operations sees the full picture.

### Weekly Planning View

Operations can pull a one-week-at-a-time view showing:

- All shifts and volunteer registrations
- Staffing status (filled/open/overfilled per station)
- Assignment completion status
- Any flags or issues requiring attention

---

## 9. Raiser's Edge NXT Integration

### Current State

Monthly batch export from Galaxy Digital. Manual upload to RE NXT via ImportOmatic. Manual duplicate checking. Staff cannot tell if a volunteer is a donor at signup or arrival.

### Target State

Real-time or near-real-time record linking between the volunteer platform and RE NXT. Known donors are recognized during the volunteer flow. Volunteer activity syncs to RE NXT automatically.

### Record Matching

**Matching fields:** Email address and cell phone number. These are the two most reliable identifiers present in both systems.

**On signup or login:** The system queries RE NXT for a matching record. If a match is found with ≥90% confidence, records are linked automatically. The volunteer record is tagged with donor status, giving level, and corporate affiliation (if applicable).

**At check-in:** If a match was found, staff see the donor recognition flag (see Section 7).

**During the conversational flow:** If a match is found early (during signup), the system can personalize the experience: "We're so grateful you've been supporting us as a donor. It's wonderful to see you volunteering too!" (This is the experience Justin described in the transcript.)

### Sync Direction

The volunteer platform pushes data INTO Raiser's Edge NXT. It does not replace RE NXT or take over donor stewardship.

Data flowing to RE NXT:

- New volunteer records (for people not already in RE NXT)
- Volunteer activity: dates, hours, shifts, locations
- Volunteer status tags on existing donor records

RE NXT remains the system of record for donor data. Existing stewardship and cultivation processes continue unchanged.

### Exception Report

Matches below the 90% confidence threshold surface in a staff-facing exception report.

The report shows:

- Volunteer record details
- Potential RE NXT match(es)
- Confidence score and reason for low confidence (e.g., name mismatch, different phone number)
- Actions: confirm match, reject match, merge manually

Staff resolve exceptions on a defined cadence (daily or weekly, depending on volume). This replaces the current manual duplicate-checking workflow.

### Technical Risk

The RE NXT API availability and capabilities are unconfirmed as of the discovery call. This is the single largest open dependency in the system.

**If API access is available:** Real-time matching and automatic sync as described above.

**If API access is limited or unavailable:** Fallback to automated batch export from the volunteer platform on a daily or weekly cadence, formatted for ImportOmatic ingestion. The exception report is still generated from the volunteer platform side. This is better than the current monthly manual process but does not enable real-time donor recognition.

Resolving this dependency (confirming RE NXT API access, matching rules, and rate limits) should be a first-priority investigation item.

---

## 10. Website Integration

The volunteer experience must feel native to the NIFB website. Key requirements:

- **Visual consistency:** The conversational UI matches NIFB's brand, typography, and color scheme. It does not look like a chatbot widget bolted onto the page.
- **URL continuity:** The volunteer flow lives under the NIFB domain (e.g., solvehungertoday.org/volunteer), not a redirect to an external domain.
- **Navigation coherence:** The volunteer experience is accessible from the main "Volunteer" navigation item. Returning users can access their dashboard, upcoming shifts, and history from the same integrated experience.
- **No "return to our website" links.** The volunteer IS on the website. Always.

---

## 11. Reporting & Data

### Volunteer-Facing

- Personal dashboard: hours volunteered, shift history, upcoming shifts, impact stats
- Digital impact cards (shareable)

### Staff-Facing

- Volunteer roster and search
- Shift registration reports (per location, per date range)
- Station assignment plans
- Check-in reports (who showed up, no-shows)
- Waiver and orientation completion status
- RE NXT exception report
- Group management (corporate/organizational tracking)
- Skills-based volunteer application queue
- Court-required hours documentation

### Export

- Data export to RE NXT (automated, see Section 9)
- CSV/report export for any staff-facing data set (for the data warehouse project Colleen mentioned)
- Hours verification printout for court-required and SNAP benefit volunteers

---

## 12. Validation & Testing

### The Big Test

Simulate a fully planned shift at one location with maximum scenario diversity:

**Volunteer profiles to simulate:**

- First-time individual volunteer (brand new, no account)
- Returning individual volunteer (existing account, waiver complete)
- Group of 15 from a corporate partner (leader registers, members check in on-site)
- Volunteer with accessibility/sitting-only needs
- Skills-based volunteer applicant
- Court-required community service volunteer
- SNAP benefit volunteer
- Known donor volunteering for the first time (should be recognized via RE NXT match)
- Returning volunteer who is also a high-value donor (should be flagged at check-in)

**Pass criteria:** The system migrates all volunteers through the complete pipeline — signup → waiver → orientation → check-in → station auto-assignment → post-shift engagement — and produces a fully valid shift plan with no human intervention. Station assignments respect all constraints (groups together, accessibility, capacity).

### Intermediate Milestone Tests

Each of these should pass independently before the full integration test:

1. **Signup test:** A new volunteer can complete registration with only name, phone, email. A returning volunteer is recognized and not asked to re-register.
2. **Waiver test:** Digital waiver is presented, signed, and attached to the volunteer record. Completion is verifiable at check-in.
3. **Orientation test:** Video orientation is delivered and completion is tracked.
4. **Discovery test:** The conversational recommendation engine produces relevant shift suggestions given stated preferences.
5. **Check-in test:** QR code scan successfully checks in an individual. Group leader scan initiates group check-in flow.
6. **Assignment test:** Given a set of volunteers with mixed constraints, the auto-assignment algorithm produces a valid plan. Staff can override without breaking constraints.
7. **RE NXT match test:** A known donor's record is matched during signup. Donor status is visible to staff at check-in.
8. **SMS test:** The full text sequence fires correctly: confirmation → reminder → post-shift impact → next commitment prompt.

### Pilot Scope

Start with one location. Validate the full loop. Expand to additional locations after the single-location test passes.

---

## 13. Hospitality Framework Alignment

Every feature in this spec maps to NIFB's three guiding principles:

### Prepared

- Digital orientation ensures volunteers know what to expect before arrival
- Pre-shift SMS with logistics (what to wear, where to park, what door to enter)
- Station auto-assignment means staff aren't scrambling to place people
- Run of show gives every staff member a clear plan for the day

### Empowered

- Staff see donor flags, accessibility needs, and group info at check-in — they can act on it
- Override capability on station assignments — staff have final say
- Skills-based volunteer queue with visibility into pending applications — nothing falls through cracks
- Exception report puts matching decisions in staff hands, not an algorithm

### Impactful

- Digital impact cards with personalized data ("you packed 500 backpacks")
- One-tap social sharing from impact cards
- Post-shift SMS sequence captures the emotional high and converts to next commitment
- Serving Hope monthly giving integration connects volunteer energy to sustained support
- Hour tracking and celebration (milestones, anniversaries)

---

## Open Items

1. **Raiser's Edge NXT API access** — Confirm availability, authentication, rate limits, matching field capabilities. This is the highest-priority technical investigation.
2. **Hospitality framework PDF + proxy volunteer list** — Attachments from Colleen's Mar 11 email have not been downloaded. May contain additional detail on processes and scheduling formats.
3. **Galaxy Digital admin walkthrough** — A ~30-minute narrated screen recording of admin workflows was requested. This would inform staff dashboard design. Status unknown.
4. **Orientation video ownership** — Who creates and maintains the video content? This is content, not software, but the system needs it to exist.
5. **SMS provider selection** — Twilio or equivalent. TCPA compliance requirements.
6. **NIFB website platform** — Need to understand the current website stack for integration approach (embed, iframe, subdomain, etc.).
7. **Data warehouse connection** — Colleen mentioned a data warehouse project that will pull dashboard reports. Interface TBD.
8. **Corporate/company recognition rules** — How to identify and flag corporate groups and their relationship to donor records. Matching logic TBD.
9. **Skills-based volunteer response SLA** — What response time should the system promise applicants? Currently one part-time staff member manages this program. SLA depends on NIFB capacity.
