# Sprint 011 — Group Volunteer Registration & Waiver Management

## Scope
Implement group leader registration (group name, size, contact info, ages, type, date preferences), group identity tracking, and group waiver handling (leader signs for self, members can sign at arrival). Group registration renders within the conversational UI. Individual member names are not required in advance.

## Non-goals
- No group check-in. No on-site member capture. No station assignment.

## Requirements
- **FR24**: Capture group leader registration fields: group name/organization, approximate group size, leader contact information, group ages, group type, and desired date/time preferences.
- **FR25**: Do not require individual member names and contact details in advance; collect them at arrival through quick check-in.
- **FR26**: Track group identity so groups can be kept together during station assignment.
- **FR27**: Track waiver status for groups and require signed waivers before group members work.
- **FR36**: For groups, have the leader sign for themselves and allow individual members to sign at arrival if not completed in advance.

## Dependencies
- Sprint 005 — Volunteer Registration, Profile & Website-Embedded UI Shell
- Sprint 007 — Digital Waiver Management

## Expected Artifacts
- `db/migrations/011_groups.*` — Group registration tables
- `src/models/group.*` — Group model with identity tracking
- `src/models/group_member.*` — Group member model
- `src/api/groups.*` — Group registration and management endpoints
- `src/ui/groups/GroupRegistration.*` — Group leader registration in conversational UI
- `src/services/group_waiver.*` — Group waiver tracking logic
- `tests/api/groups.test.*`
- `tests/services/group_waiver.test.*`

## DoD
- [ ] Group leader can register with group name, size, contact info, ages, type, and date preferences via conversational UI
- [ ] Individual member names/details are NOT required at registration time (test: group created with zero member records)
- [ ] Group identity is stored and trackable across the system (group ID persists on shift registration)
- [ ] Group waiver status tracks leader signature separately from member signatures
- [ ] Leader signs waiver for themselves; members can sign individually at arrival (test for both paths)
- [ ] Group registration renders within the conversational UI framework, not as a standalone form
- [ ] `make test` passes

## Validation
```bash
make test
```
