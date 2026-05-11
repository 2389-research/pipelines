# Sprint 000 — Project Scaffold & Toolchain

## Scope
Initialize the repository with chosen language/framework, package manager, linter configuration, test harness, and CI skeleton. Since the spec does not prescribe a tech stack, this sprint makes and documents those choices.

## Non-goals
- No application logic, no database, no external services.

## Requirements
- (none — bootstrap)

## Dependencies
- None

## Expected Artifacts
- `package.json` — (or equivalent manifest)
- `.eslintrc` — / linter config
- `jest.config.*` — / test harness config
- `Makefile` — or `scripts/` with `make build`, `make test`, `make lint`
- `.github/workflows/ci.yml` — (or equivalent CI config)
- `README.md` — with setup instructions
- `docs/adr/001-tech-stack.md` — Architecture Decision Record for stack choices

## DoD
- [x] `make build` (or equivalent) completes without errors
- [x] `make lint` passes with zero warnings on the empty project
- [x] `make test` runs the test harness successfully (0 tests, 0 failures)
- [x] CI config file exists and defines build + lint + test steps
- [x] README documents local setup steps, chosen stack, and available commands
- [x] ADR documents language, framework, database, test framework, and linter choices with rationale

## Validation
```bash
make build && make lint && make test
```
