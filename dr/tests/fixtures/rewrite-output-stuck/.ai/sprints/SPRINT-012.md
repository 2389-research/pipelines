# Sprint 012 — Group Check-In, On-Site Member Capture & Donor Flags

## Scope
Implement group check-in flow (leader scans QR, confirms headcount, triggers on-site member capture). Provide quick capture form for collecting member details on tablet/kiosk. Captured group members are created as canonical volunteer records (not orphaned data). Add donor/corporate recognition flag at check-in (staff-only, sourced from pre-matched RE NXT data).

## Non-goals
- No full RE NXT integration — uses pre-matched donor flags only. No station assignment.

## Requirements
- **FR48**: Let a group leader scan their QR code, show the registered group size, and confirm headcount.
- **FR49**: Provide a quick on-site capture form on a tablet/kiosk for group members whose details were not collected in advance.
- **FR50**: Cross-reference check-ins with Raiser's Edge NXT and show donor/corporate-partner recognition flags to staff only.

## Dependencies
- Sprint 010 — Check-In & QR Code System (Individual)
- Sprint 011 — Group Volunteer Registration & Waiver Management

## Expected Artifacts
- `src/ui/checkin/GroupCheckin.*` — Group check-in flow (leader scan → headcount → member capture)
- `src/ui/checkin/MemberCapture.*` — On-site member capture form (tablet/kiosk)
- `src/services/donor_flag.*` — Donor recognition flag lookup
- `src/ui/checkin/DonorBadge.*` — Staff-only donor/corporate badge
- `tests/ui/checkin/group_checkin.test.*`
- `tests/services/donor_flag.test.*`

## DoD
- [ ] Group leader QR scan initiates group check-in flow showing registered group size
- [ ] Leader confirms or adjusts headcount at check-in
- [ ] On-site capture form collects name, phone, email for each member not pre-registered
- [ ] Captured group members are created as canonical Volunteer records linked to their group (not orphaned — test verifies record exists in volunteers table)
- [ ] Group member waiver signing is prompted during on-site capture for members without completed waivers
- [ ] Donor/corporate-partner flag appears to staff for volunteers with donor_status populated on their record (test with seeded donor data; live RE NXT population in Sprint 018 — staff-facing only, NOT visible to volunteer — authorization test)
- [ ] `make test` passes

## Validation
```bash
make test
```
