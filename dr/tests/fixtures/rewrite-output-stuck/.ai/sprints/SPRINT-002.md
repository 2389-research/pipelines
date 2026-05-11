# Sprint 002 — Hello World End-to-End Proof

## Scope
Create one API endpoint, one database table, one UI page, and one integration test that exercise the full stack: browser → frontend → API → database → response. This proves the scaffold works end-to-end before feature work begins.

## Non-goals
- No real domain models. This is a throwaway proof, not production code.

## Requirements
- (none — bootstrap)

## Dependencies
- Sprint 001 — External Services & Dev Environment

## Expected Artifacts
- `src/api/hello.*` — sample endpoint
- `db/migrations/002_hello.*` — sample table migration
- `src/ui/HelloPage.*` — sample UI page
- `tests/e2e/hello.test.*` — integration test

## DoD
- [x] Sample API endpoint reads from and writes to the database
- [x] Sample UI page renders in a browser and calls the API endpoint
- [x] One passing integration test exercises the full stack: HTTP request → API → DB → response assertion
- [x] `make test` passes including the new integration test
- [x] `make build` produces a runnable artifact (server starts and serves the UI page)

## Validation
```bash
make build && make test
```
