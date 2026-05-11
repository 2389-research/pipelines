# Sprint 001 — External Services & Dev Environment

## Scope
Set up Docker Compose with the application database (PostgreSQL or equivalent), run initial schema migration tooling, implement health checks, and document environment variables. This sprint establishes the data persistence layer that all feature sprints depend on.

## Non-goals
- No application models, no API endpoints, no UI.

## Requirements
- (none — bootstrap)

## Dependencies
- Sprint 000 — Project Scaffold & Toolchain

## Expected Artifacts
- `docker-compose.yml` — database service definition
- `db/migrations/` — migration tooling scaffold (empty initial migration)
- `src/db/connection.*` — database connection module
- `src/health.*` — health check endpoint
- `.env.example` — documented environment variables

## DoD
- [x] `docker-compose up -d` starts database service without errors
- [x] Database health check endpoint returns 200 with `{"status":"healthy"}`
- [x] Application code connects to the database and executes a trivial query (e.g., `SELECT 1`)
- [x] Migration tooling runs against the database without errors (empty migration)
- [x] `.env.example` documents all required environment variables with descriptions
- [x] `make test` still passes (no regressions from Sprint 000)

## Validation
```bash
docker-compose up -d
make test
curl http://localhost:$PORT/health
```
