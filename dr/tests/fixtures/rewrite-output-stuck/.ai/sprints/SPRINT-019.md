# Sprint 019 — RE NXT Activity Sync & Batch Export Fallback

## Scope
Push new volunteer records, volunteer activity (dates, hours, shifts, locations), and status tags into RE NXT while keeping RE NXT as the donor system of record. Implement the batch-export fallback: if RE NXT API access is limited, generate automated daily/weekly ImportOmatic-formatted export files and still produce exception reporting from the platform side.

## Non-goals
- No new volunteer-facing features. No staff dashboard changes.

## Requirements
- **FR70**: Push new volunteer records, volunteer activity, and volunteer status tags into RE NXT while keeping RE NXT as the donor system of record.
- **FR73**: If RE NXT API access is limited or unavailable, fall back to automated daily/weekly batch export formatted for ImportOmatic ingestion and still generate the exception report from the volunteer-platform side.
- **FR81**: Automate data export to RE NXT.

## Dependencies
- Sprint 018 — RE NXT Integration & Donor Matching

## Expected Artifacts
- `src/integrations/renxt/sync.*` — Outbound activity sync
- `src/integrations/renxt/batch_export.*` — ImportOmatic-formatted batch export
- `src/services/sync_scheduler.*` — Sync job scheduler with retry/backoff
- `tests/integrations/renxt/sync.test.*`
- `tests/integrations/renxt/batch_export.test.*`

## DoD
- [ ] Volunteer activity events (registration, check-in, hours) enqueue sync jobs to RE NXT (integration test)
- [ ] Sync job retries on transient failure with configurable backoff (test using fake connector)
- [ ] Batch export job produces ImportOmatic-formatted files on a configurable schedule (golden-file test)
- [ ] Exception reporting remains available even when batch mode is active (test)
- [ ] Automated data export to RE NXT runs on schedule without manual intervention
- [ ] `make test` passes

## Validation
```bash
make test
```
