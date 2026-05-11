# Sprint 022 — Volunteer Dashboard, Post-Shift SMS & Engagement

## Scope
Build the volunteer-facing personal dashboard (hours, history, upcoming shifts, impact stats). Implement post-shift SMS sequence: immediate impact card with personalized data and one-tap social sharing, next-commitment prompt with three upcoming opportunities (~15 min later). Implement open-opportunity SMS alerts, milestone celebrations, and deeper engagement follow-ups. Complete the staff reporting suite (roster/search, registration reports, check-in reports, waiver/orientation status).

## Non-goals
- No new authentication or assignment features. No data warehouse integration.

## Requirements
- **FR15**: Show returning volunteers personalized suggested opportunities based on history, preferred locations, and past shift types.
- **FR22**: Proactively push open opportunities or pop-up events by SMS to volunteers who have opted in.
- **FR42**: Send an immediate post-shift impact card with personalized impact data and one-tap social sharing.
- **FR43**: Send a next-commitment SMS about 15 minutes later with three upcoming opportunities.
- **FR44**: Support deeper-engagement follow-up messages, open-opportunity alerts, and milestone celebration messages.
- **FR78**: Provide a volunteer dashboard with hours volunteered, shift history, upcoming shifts, and impact stats.
- **FR79**: Provide shareable digital impact cards.
- **FR80**: Provide staff tools for volunteer roster/search, shift registration reports, station assignment plans, check-in reports, waiver/orientation completion status, RE NXT exception reporting, group management, skills-based queue, and court-required hours documentation.
- **FR82**: Support CSV/report export for any staff-facing dataset.

## Dependencies
- Sprint 009 — SMS Orchestration Core (Transactional)
- Sprint 010 — Check-In & QR Code System (Individual)
- Sprint 014 — Individual Volunteer End-to-End Flow
- Sprint 017 — Staff Operations Dashboard (Run of Show & Weekly Planning)
- Sprint 018 — RE NXT Integration & Donor Matching

## Expected Artifacts
- `src/ui/volunteer/Dashboard.*` — Volunteer personal dashboard
- `src/ui/volunteer/ImpactCard.*` — Shareable digital impact card
- `src/sms/templates/impact_card.*` — Post-shift impact SMS template
- `src/sms/templates/next_commitment.*` — Next-commitment SMS template
- `src/sms/templates/open_opportunity.*` — Open-opportunity alert template
- `src/sms/templates/milestone.*` — Milestone celebration template
- `src/services/impact_data.*` — Personalized impact data generation
- `src/services/social_share.*` — One-tap social sharing link
- `src/ui/staff/Reports.*` — Staff reporting hub (roster, registration, check-in, waiver/orientation status)
- `tests/services/impact_data.test.*`
- `tests/sms/post_shift.test.*`
- `tests/ui/volunteer/dashboard.test.*`

## DoD
- [ ] Volunteer dashboard shows hours volunteered, shift history, upcoming shifts, and impact stats
- [ ] Volunteer dashboard is accessible via integrated navigation (same experience as discovery)
- [ ] Post-shift impact SMS fires immediately after shift ends with personalized impact data and social sharing link
- [ ] Next-commitment SMS fires ~15 minutes after impact card with exactly 3 upcoming opportunities
- [ ] Open-opportunity alerts send to opted-in volunteers when shifts need filling (proactive push per FR22)
- [ ] Milestone celebration SMS fires at configured hour milestones
- [ ] Staff reporting hub provides roster/search, registration reports, check-in reports, and waiver/orientation status with CSV export
- [ ] Shareable impact card page renders with volunteer data and is accessible by URL
- [ ] `make test` passes

## Validation
```bash
make test
```
