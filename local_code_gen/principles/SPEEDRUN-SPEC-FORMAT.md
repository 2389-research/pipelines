# Speedrun Spec Format

The section structure of a well-written sprint spec for local-LLM-driven generation. Named after the [`speed-run` skill](~/.claude/plugins/cache/2389-research-marketplace/speed-run/) whose contract style it generalizes.

## Why this format vs full-file bodies

Two strategies for "tight enough that qwen can transcribe it":

| Strategy | Architect work | qwen behavior | Pros | Cons |
|---|---|---|---|---|
| **Full file bodies** (one-shot transcription) | Architect writes lint-clean impl-grade code in the spec | qwen copies the spec's bodies verbatim | Maximum determinism — qwen invents nothing | Architect must produce production-quality code; spec gets impl-grade bugs (unused imports, dead code) that qwen faithfully transcribes |
| **Speedrun (signatures + algorithm prose + rules)** | Architect writes shapes + step-by-step prose for non-trivial logic + project-wide rules | qwen writes idiomatic bodies that match the contract | Architect produces only shapes — much less code to write/maintain; qwen-produced bodies are lint-clean by default | Slightly more variance per file (qwen makes minor stylistic choices); a tight spec still produces consistent results |

We validated speedrun-style on three NIFB sprints. Sprint 001 (390 lines) generated 21/21 first try; sprint 002 (196 lines) needed one LocalFix round; sprint 003 (239 lines) generated 14/14 first try. Speedrun is the right default.

Use full-file bodies for **tiny data-shaped files** where exact text matters more than logic: `pyproject.toml`, `app/exceptions.py` (~20 lines of error code constants + AppError), `app/main.py` (the auto-discovery factory — small but load-bearing), `app/config.py`, `app/database.py`, `scripts/init_db.py`. These get a "Verbatim files" section with full fenced code.

## Section structure

A SPRINT-NNN.md spec has these sections, in this order:

### 1. `# Sprint NNN — <Title>`

One-line title. Front-loaded foundation sprints: "Sprint 001 — Foundation (full schema + auth, front-loaded)". Additive sprints: "Sprint NNN — <Feature> (additive)".

### 2. `## Scope`

2-4 sentences describing what the sprint delivers. For additive sprints, explicitly note: "Purely additive — no edits to any sprint NNN file."

### 3. `## Non-goals`

Bulleted list of what this sprint does NOT include, with cross-references to which later sprint handles each excluded thing. Example: "No SMS gateway integration — OTP is logged to console (Sprint 005 adds Twilio)."

### 4. `## Dependencies`

For sprint 001: "None — first sprint." For sprints 002+: a tightly-scoped list of the prior sprints' contracts this sprint imports — by exact symbol name. Example:

```
- Models: Volunteer, Group, GroupMember, WaiverAcceptance, OrientationCompletion from app.models.
- Schemas: GroupCreate, GroupRead, ... from app.schemas.
- DB / auth: get_db from app.database, get_current_volunteer from app.dependencies.
- Errors: AppError, NOT_FOUND, FORBIDDEN, UNAUTHORIZED from app.exceptions.
- Test fixtures: client, db_session, test_volunteer, auth_headers — already in conftest.py.
```

### 5. `## Conventions`

Project-wide rules. Sprint 001 declares them in full. Sprints 002+ start with "Inherited from Sprint 001 — listed here for tight feedback" and re-iterate the load-bearing ones. Examples:

- Module path (`backend/app` package; absolute imports only)
- Python version + package manager
- Web framework + ASGI server
- ORM driver + style (`Mapped[...] / mapped_column(...)`)
- Validation library version
- Auth library
- Test framework + asyncio mode
- Lint rules
- All ID type
- Error-raising convention
- All timestamps timezone

### 6. `## Tricky semantics` (load-bearing — read FIRST)

The most important section. Lists project conventions that without explicit pinning would force the local model to guess. Numbered list, each rule has:
- The rule itself
- A brief explanation of WHY (often: a runtime symptom that occurs without it)
- A code-pattern example where useful

Examples (from the v7 NIFB SPRINT-001):
1. Settings singleton via `@lru_cache`
2. Database engine is lazy (`get_engine()` not eager)
3. Async loading: `lazy="selectin"` on every collection-side relationship
4. Bidirectional relationships use `back_populates` on both sides
5. Settings overrides in tests patch the instance, not the class
6. Tests use fixtures from conftest; never construct AsyncClient inline
7. Imports are complete Python statements, never bare module names
8. AppError is the only exception routers raise
9. Auto-discovering routers (load-bearing for front-loading)
10. Test config constants are literal values
11. Use `pop(get_db, None)` not `clear()` in fixture cleanup

### 7. `## Data contract` (signatures only, no bodies)

For sprint 001 (foundation): every enum, every ORM class, every Pydantic schema. Full field signatures. Relationships with `lazy="selectin"` and `back_populates`. No method bodies.

For sprints 002+: typically empty / "no new types — referenced from sprint 001's contract."

### 8. `## API contract`

Route table. Method, path, request schema, response schema (with status code), errors (with status_code + error_code). Plus:

- **Path/query parameter types** — explicit Python annotations (`location_id: uuid.UUID`, `on_date: date | None = None`). Defect class #7 closes here.
- **Route declaration order** — explicit ordering when static and parameterized paths share prefixes. Defect class #11 closes here.

### 9. `## Algorithm`

Per-route step-by-step prose. Not code, not pseudocode — natural language constrained to the contract types.

Format per route: `### <METHOD> <path> — <function_name>(<params>)` followed by numbered steps. Each step references types/exceptions by exact name. Example:

```
### POST /registrations — create_registration(req, volunteer, db)
1. Look up `Shift` by `req.shift_id`. If none → `raise AppError(404, "Shift not found", NOT_FOUND)`.
2. Look up duplicate `Registration` where `volunteer_id == volunteer.id AND shift_id == req.shift_id AND status != RegistrationStatus.cancelled`. If exists → `raise AppError(409, "Already registered for this shift", DUPLICATE_REGISTRATION)`.
3. ...
```

For routes that construct a Read schema explicitly with derived fields (e.g., `ShiftRead` with `registered_count`), name the EXACT field set: "construct ShiftRead with EXACTLY these fields and no others: id, location_id, ... — do NOT pass any other field." Defect class #8.

### 10. `## Test contract`

Per-file table. Each test row has: name (with fixtures listed as parameters), action (one sentence), asserts (status code + body assertion using the actual response shape).

Use the matching response-path form: `body["error_code"] == "..."` for flat error responses (when handler returns flat `{"detail": str, "error_code": str}`). Defect class #14.

For idempotent tests, name what to capture and what to compare. Example:

> `test_sign_waiver_idempotent(client, auth_headers)` | Sign once; capture `signed_at_1`; sign again; capture `signed_at_2` | both 201; `signed_at_1 == signed_at_2` (same row, no new insert)

For tests that need a second volunteer / location / etc., specify EXACT values to avoid unique-constraint collisions. Defect class implicit in the "second volunteer" sub-rule.

### 11. `## Verbatim files` (small data-shaped files only)

Files where exact text matters more than logic. For typical foundation sprint:
- `app/exceptions.py` — `AppError` class + error code constants
- `app/main.py` — full app factory with pkgutil discovery
- `app/database.py` — Base + lazy engine + get_db
- `app/config.py` — Settings + cached factory
- `scripts/init_db.py` — small async runner
- `pyproject.toml` — full TOML

Each file gets a `### filename` subsection with full fenced code. Annotate with `(load-bearing)` for files that are FROZEN.

### 12. `## New files`

Bullet list. Each entry includes:
- The path
- A one-line role summary referencing the contract sections (Algorithm / Test contract / etc.)
- **EXACT imports list** — full Python statements. Defect class #2 closes here.

Example:

```
- `backend/app/routers/groups.py` — `router = APIRouter(prefix="/groups", tags=["groups"])`. Three handlers per "API contract" + "Algorithm" sections: `create_group`, `list_my_groups`, `add_member`. Imports (use these EXACT statements): `import uuid`, `from fastapi import APIRouter, Depends`, `from sqlalchemy import select`, `from sqlalchemy.ext.asyncio import AsyncSession`, `from app.database import get_db`, `from app.dependencies import get_current_volunteer`, `from app.exceptions import AppError, NOT_FOUND, FORBIDDEN`, `from app.models import Volunteer, Group, GroupMember`, `from app.schemas import GroupCreate, GroupRead, GroupMemberAdd`.
```

### 13. `## Modified files`

For pure-additive sprints (the design goal under architect_v2): `(none — Sprint 001's main.py auto-discovers; no schema/model edits required.)`

If there's a real modification (e.g., sprint 005 appends Twilio to deps in pyproject.toml), the entry must specify the EXACT append/insert location and verbatim content.

### 14. `## Rules`

Negative constraints + reinforcements of tricky-semantic rules from section 6 (so they appear in two places — common sense, easy to miss in long docs). Plus structural rules unique to this sprint.

Examples:
- "All new files go under `backend/`. NO modifications to any sprint 001 file."
- "Routers expose their `APIRouter` instance as the module-level name `router` (sprint 001's main.py pkgutil discovery requires this exact attribute name)."
- "Tests take fixtures as function parameters — never construct AsyncClient/engines/sessions inline."
- "Idempotent endpoints MUST check for an existing row first."
- "Route handler path/query parameters typed as the actual Python type — never `str`."
- "Error-response assertions use the flat shape — `body["error_code"]`, not `body["detail"]["error_code"]`."

### 15. `## DoD`

Checklist of machine-verifiable items. Each is either an exact bash command (e.g., `cd backend && uv run pytest tests/test_groups.py -v passes`) OR a binary observable outcome (`POST /auth/register with duplicate email returns 409 with error_code=ACCOUNT_EXISTS`).

### 16. `## Validation`

Exact bash commands to verify the sprint, one per line. Typically:

```bash
cd backend
uv sync --all-extras
uv run pytest -v --tb=short
uv run ruff check app/ tests/
```

## Sprint-size guidance

Foundation sprint (sprint 001 with full schema): ~600-1000 lines depending on entity count. Most lines are `## Data contract` and `## Verbatim files`.

Additive sprint: ~150-300 lines. Most lines are `## API contract` table + `## Algorithm` prose + `## Test contract` table.

If a sprint exceeds 1500 lines, it's probably trying to do too much — split it.

## Decision rule (carried forward from `docs/simmer/write-sprint-docs/result.md`)

Where the spec or sprint plan is ambiguous about implementation details, **make a concrete choice and commit to it**. Do not hedge with "you may use X or Y". Do not write "choose based on your preference". The local model has no preference — it needs one answer.

## Syntax rule (carried forward)

Every type definition, function signature, import block, and test name must appear in actual Python syntax — not English. "Implement a token decoder function" is forbidden. `def verify_token(token: str) -> dict` is correct.

## When to use full-file bodies vs speedrun

| File category | Style |
|---|---|
| Tiny config-shaped files (~20-50 lines, exact text matters): `pyproject.toml`, `exceptions.py`, `main.py` (auto-discovery factory), `database.py`, `config.py`, `init_db.py`, all `__init__.py` empty markers | **Verbatim** — full fenced code in `## Verbatim files` |
| ORM models (signatures with relationships matter, but Python's `Mapped[...] = mapped_column(...)` is itself near-syntax) | **Verbatim signatures** — declared as code in `## Data contract` |
| Pydantic schemas (signatures only) | **Verbatim signatures** — declared as code in `## Data contract` |
| Routers, services, business logic | **Speedrun** — Algorithm prose + per-file imports list |
| Test files | **Speedrun** — Test contract table + per-file imports list |
| Auth helpers, dependencies (small functions with mostly-deterministic bodies) | **Either** — current preference is signatures + brief algorithm prose |
