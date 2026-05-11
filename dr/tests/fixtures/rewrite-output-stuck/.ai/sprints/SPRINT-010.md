# Sprint 010 — Check-In & QR Code System (Individual)

## Scope
Implement QR code generation and delivery (via SMS and web profile), kiosk/staff-device QR scanning for individual check-in without requiring volunteer login. At check-in, detect incomplete waiver, orientation, and secondary information and prompt appropriately while allowing the volunteer to proceed (permissive policy).

## Non-goals
- No group check-in. No donor recognition at check-in. No station assignment display.

## Requirements
- **FR35**: Store waiver completion status on the volunteer record and validate it at check-in, prompting on-site completion if incomplete.
- **FR46**: Deliver a QR code to each volunteer via SMS and their web profile.
- **FR47**: Allow kiosk or staff-device QR scanning to check in an individual volunteer without login or staff assistance on the happy path.
- **FR51**: At check-in, detect incomplete waiver, orientation, or secondary information and prompt or flag the missing items appropriately.
- **FR52**: Default to letting the volunteer proceed rather than turning them away while capturing missing information.

## Dependencies
- Sprint 007 — Digital Waiver Management
- Sprint 008 — Orientation Tracking
- Sprint 009 — SMS Orchestration Core (Transactional)

## Expected Artifacts
- `src/services/qr_code.*` — QR code generation
- `src/sms/templates/qr_delivery.*` — QR code SMS delivery
- `src/ui/checkin/QRScanner.*` — Kiosk/device QR scanner
- `src/ui/checkin/CheckinFlow.*` — Check-in flow with missing-info prompts
- `src/api/checkin.*` — Check-in API endpoint
- `src/services/checkin_validation.*` — Missing-info detection logic
- `tests/api/checkin.test.*`
- `tests/services/checkin_validation.test.*`

## DoD
- [ ] QR code is generated for each registered volunteer and accessible from their web profile
- [ ] QR code is delivered via SMS as part of pre-shift communications
- [ ] Scanning QR code at kiosk/device checks in the volunteer without requiring volunteer login (integration test)
- [ ] Check-in detects incomplete waiver and prompts on-site completion
- [ ] Check-in detects incomplete orientation and flags for staff
- [ ] Check-in detects missing secondary info (address, emergency contact) and prompts for collection
- [ ] Volunteer proceeds through check-in even with missing items — permissive policy enforced (integration test)
- [ ] `make test` passes

## Validation
```bash
make test
```
