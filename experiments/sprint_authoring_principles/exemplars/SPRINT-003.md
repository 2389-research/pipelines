# Sprint 003 — Groups, Waivers & Orientation (additive)

## Scope
Add three router files: groups (volunteer-led signups; leader can add members), waiver acceptance (idempotent sign + status), orientation completion (idempotent complete + status). **Purely additive — no edits to any sprint 001 or sprint 002 file.** Sprint 001's `main.py` auto-discovers new files in `app/routers/` via `pkgutil`; sprint 001's `models.py` and `schemas.py` already declare every entity and request/response shape this sprint needs.

## Non-goals
- No `models.py` / `schemas.py` / `main.py` / `exceptions.py` / `database.py` / `config.py` edits — those are FROZEN.
- No QR check-in (Sprint 006 will read waiver+orientation status; this sprint just defines the endpoints).
- No admin UI for waiver/orientation review (frontend sprints).
- No new fixtures in `conftest.py` (sprint 001 provides everything this sprint needs).

## Dependencies (sprint 001 contracts this sprint imports — none get redefined here)

- **Models**: `Volunteer`, `Group`, `GroupMember`, `WaiverAcceptance`, `OrientationCompletion` from `app.models`.
- **Schemas**: `GroupCreate`, `GroupRead`, `GroupMemberAdd`, `WaiverSignRequest`, `WaiverStatusResponse`, `OrientationCompleteRequest`, `OrientationStatusResponse` from `app.schemas`.
- **DB / auth**: `get_db` from `app.database`, `get_current_volunteer` from `app.dependencies`.
- **Errors**: `AppError`, `NOT_FOUND`, `FORBIDDEN`, `UNAUTHORIZED` from `app.exceptions`.
- **Test fixtures**: `client`, `db_session`, `test_volunteer`, `auth_headers` — already in `conftest.py`.

## Conventions (inherited from Sprint 001 — listed for tight feedback)
- Router files declare `router = APIRouter(prefix="/<resource>", tags=["<resource>"])`. Sprint 001's `main.py` auto-discovers via `pkgutil`.
- Routers raise `AppError(status_code, detail, error_code)` — never raw `HTTPException`, never custom JSONResponse.
- All route handlers are `async def`. All DB queries `await`.
- Tests are `async def` (pytest-asyncio `mode=auto`). **Do NOT add `@pytest.mark.asyncio` decorators.**
- Tests take fixtures as **function parameters**. Never construct `AsyncClient`, engines, or sessions inline.
- Authenticated requests pass `headers=auth_headers`. Unauthenticated tests omit it and assert 401.
- Imports are full Python statements, never bare module names.
- Collection routes use empty-string path `""` (not `"/"`).

## Tricky semantics (load-bearing — read before writing routes)

1. **Idempotent endpoints (waiver sign, orientation complete) must not create duplicates.** Both `WaiverAcceptance` and `OrientationCompletion` have `unique=True` on `volunteer_id` (declared in sprint 001's models). If a row already exists for the volunteer, the endpoint returns the existing record's `signed_at` / `completed_at` rather than inserting a duplicate. Both calls return status 201 — second call is "201 + the existing data" not 200.
2. **Group leadership is the authorization principal for member-adds.** `Group.leader_id` is the only field that grants `POST /groups/{group_id}/members`. The auth-user comparison is `group.leader_id == leader.id`; anything else → `AppError(403, FORBIDDEN)`.
3. **Group not found takes precedence over leadership check.** Look up the group first; if missing, `AppError(404, NOT_FOUND)` — even if the auth user wouldn't have been the leader anyway. Never combine the two checks into one.
4. **`list_my_groups` returns ONLY groups where the auth user is the leader, not groups they're a member of.** The query filters `Group.leader_id == leader.id`. Membership is a separate concept (joins through `GroupMember`).
5. **"Unsigned waiver" / "incomplete orientation" status responses use `signed=False` (or `completed=False`) with `signed_at=None` (or `completed_at=None`)** — the `GET /<resource>/me/status` endpoints query for the existence of a row and return the empty-state response when none exists. They never raise 404 for missing status — empty status is a normal state.
6. **The `auth_headers` fixture provides headers for `test_volunteer` (the auth user).** Every API call made with `headers=auth_headers` is authenticated as `test_volunteer`, regardless of which other rows the test created. Tests that need a SECOND volunteer (e.g., `test_add_member_to_other_group_returns_403`) construct it directly via `db_session` (sprint 001's conftest does NOT provide a `volunteer_factory` or `second_volunteer` fixture — create the row inline within the test).

   **Use these EXACT values for the second volunteer** (different from `test_volunteer`'s `email="test@example.com"`, `phone="+15551234567"` to avoid `unique=True` constraint violations):
   ```python
   other_volunteer = Volunteer(
       email="other@example.com",
       phone="+15559999999",
       first_name="Other",
       last_name="User",
   )
   db_session.add(other_volunteer)
   await db_session.commit()
   await db_session.refresh(other_volunteer)
   ```

7. **`add_member` returns the parent `GroupRead` UNCHANGED** even though a new `GroupMember` row was just added. `GroupRead`'s fields (id, name, leader_id, created_at) don't expose member counts or member lists — those will arrive in a future sprint. The 201 status code communicates "a member was created"; the body is the parent group, not the new member, and not a member list. Do NOT return the new `GroupMember`; do NOT add fields to the response.

## Data contract (no new types — referenced from sprint 001)

This sprint adds NO new models, NO new schemas, NO new enums. All shapes are imported from sprint 001's frozen `app.models` and `app.schemas`.

For reference, the schemas this sprint USES (already declared in `app/schemas.py`):

```python
class GroupCreate(BaseModel):
    name: str

class GroupRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    name: str
    leader_id: uuid.UUID
    created_at: datetime

class GroupMemberAdd(BaseModel):
    volunteer_id: uuid.UUID

class WaiverSignRequest(BaseModel):
    accepted: bool = True

class WaiverStatusResponse(BaseModel):
    signed: bool
    signed_at: datetime | None

class OrientationCompleteRequest(BaseModel):
    completed: bool = True

class OrientationStatusResponse(BaseModel):
    completed: bool
    completed_at: datetime | None
```

## API contract

All routes auth-required (every handler in this sprint depends on `get_current_volunteer`). 401 `UNAUTHORIZED` is the response on missing/invalid token, returned by sprint 001's `get_current_volunteer` dependency.

| Method | Path | Request | Response (status) | Errors |
|---|---|---|---|---|
| POST | `/groups` | `GroupCreate` | `GroupRead` (201) | 401 `UNAUTHORIZED` |
| GET | `/groups` | — | `list[GroupRead]` (200) | 401 `UNAUTHORIZED` |
| POST | `/groups/{group_id}/members` | `GroupMemberAdd` | `GroupRead` (201) | 401 `UNAUTHORIZED`, 404 `NOT_FOUND` (group missing), 403 `FORBIDDEN` (caller not leader) |
| POST | `/waivers/sign` | `WaiverSignRequest` | `WaiverStatusResponse` (201) | 401 `UNAUTHORIZED` |
| GET | `/waivers/me/status` | — | `WaiverStatusResponse` (200) | 401 `UNAUTHORIZED` |
| POST | `/orientation/complete` | `OrientationCompleteRequest` | `OrientationStatusResponse` (201) | 401 `UNAUTHORIZED` |
| GET | `/orientation/me/status` | — | `OrientationStatusResponse` (200) | 401 `UNAUTHORIZED` |

**Path/query parameter types (use these EXACT Python annotations in route handler signatures — never default to `str`):**
- `group_id` (path, on `/groups/{group_id}/members`) — `uuid.UUID`.

No query parameters in this sprint.

**Route declaration order** within each router file (matches the table above and the algorithm sections below):

- `groups.py`: `POST ""` → `GET ""` → `POST "/{group_id}/members"`
- `waivers.py`: `POST "/sign"` → `GET "/me/status"`
- `orientation.py`: `POST "/complete"` → `GET "/me/status"`

(None of these routers has a parameterized path that overlaps with a static path, so order is less critical than for sprint 002's `shifts.py` — but keep the declaration order consistent with the table for readability.)

## Algorithm

### `POST /groups` — `create_group(req, leader, db)`
1. Insert `Group(name=req.name, leader_id=leader.id)`.
2. `await db.commit(); await db.refresh(group)`.
3. Return the group (FastAPI serializes via `GroupRead.from_attributes`).

### `GET /groups` — `list_my_groups(leader, db)`
1. Query `Group` where `leader_id == leader.id`. (Do NOT include groups where the leader is just a member; this endpoint is for "groups I lead" only.)
2. Return the list of groups.

### `POST /groups/{group_id}/members` — `add_member(group_id, req, leader, db)`
1. Look up `Group` by `group_id`. If none → `raise AppError(404, "Group not found", NOT_FOUND)`.
2. If `group.leader_id != leader.id` → `raise AppError(403, "Only the group leader can add members", FORBIDDEN)`.
3. Insert `GroupMember(group_id=group_id, volunteer_id=req.volunteer_id)`.
4. `await db.commit(); await db.refresh(group)`.
5. Return the group (the response is `GroupRead`, which doesn't expose members — it's the parent group post-modification).

### `POST /waivers/sign` — `sign_waiver(req, volunteer, db)` (idempotent)
**The `req.accepted` field's value is NOT validated.** The act of POSTing to this endpoint is the signal of intent to sign; the field is required by the schema for forward-compat but the handler must not branch on it. Do NOT add `if not req.accepted: raise ...`.

1. Look up `WaiverAcceptance` where `volunteer_id == volunteer.id`. (`volunteer_id` has `unique=True` so at most one exists.)
2. If found, return `WaiverStatusResponse(signed=True, signed_at=existing.signed_at)` — do NOT insert a new row.
3. Otherwise, insert `WaiverAcceptance(volunteer_id=volunteer.id)`; `await db.commit(); await db.refresh(waiver)`.
4. Return `WaiverStatusResponse(signed=True, signed_at=waiver.signed_at)`.

### `GET /waivers/me/status` — `my_waiver_status(volunteer, db)`
1. Look up `WaiverAcceptance` where `volunteer_id == volunteer.id`.
2. If found → return `WaiverStatusResponse(signed=True, signed_at=existing.signed_at)`.
3. Else → return `WaiverStatusResponse(signed=False, signed_at=None)`. **Do NOT raise 404; "not signed" is a valid status, not an error.**

### `POST /orientation/complete` — `complete_orientation(req, volunteer, db)` (idempotent)
**The `req.completed` field's value is NOT validated** (same pattern as waiver sign — field is required by the schema for forward-compat but the handler does not branch on it).

1. Look up `OrientationCompletion` where `volunteer_id == volunteer.id`. (`volunteer_id` has `unique=True`.)
2. If found, return `OrientationStatusResponse(completed=True, completed_at=existing.completed_at)`.
3. Otherwise, insert `OrientationCompletion(volunteer_id=volunteer.id)`; `await db.commit(); await db.refresh(completion)`.
4. Return `OrientationStatusResponse(completed=True, completed_at=completion.completed_at)`.

### `GET /orientation/me/status` — `my_orientation_status(volunteer, db)`
1. Look up `OrientationCompletion` where `volunteer_id == volunteer.id`.
2. If found → `OrientationStatusResponse(completed=True, completed_at=existing.completed_at)`.
3. Else → `OrientationStatusResponse(completed=False, completed_at=None)`. **Do NOT raise 404.**

## Test contract

All tests `async def`. None have decorators. All use the `client` fixture from sprint 001's conftest. Authenticated tests also use `auth_headers`. Tests that need a second volunteer construct it inline via `db_session`.

### `tests/test_groups.py` (5 tests)

| Test | Action | Asserts |
|---|---|---|
| `test_create_group_returns_201(client, auth_headers, test_volunteer)` | POST `/groups` `{"name":"Team A"}`, headers=auth_headers | 201, `body["name"] == "Team A"`, `body["leader_id"] == str(test_volunteer.id)`, `body["id"]` present |
| `test_list_my_groups(client, auth_headers, test_volunteer)` | Create a group via the API; then GET `/groups`, headers=auth_headers | 200, `len(body) == 1`, `body[0]["leader_id"] == str(test_volunteer.id)` |
| `test_add_member_to_my_group(client, auth_headers, test_volunteer, db_session)` | Create a group via the API; create a second `Volunteer` via `db_session` (different phone/email); POST `/groups/{group_id}/members` `{"volunteer_id": str(other_volunteer.id)}`, headers=auth_headers | 201, `body["id"]` matches the group id |
| `test_add_member_to_other_group_returns_403(client, auth_headers, test_volunteer, db_session)` | Create a SECOND volunteer via `db_session`; create a Group with `leader_id=other_volunteer.id` directly via `db_session`; POST `/groups/{other_group.id}/members` `{"volunteer_id": str(test_volunteer.id)}`, headers=auth_headers (auth user is `test_volunteer`, not the leader) | 403, `body["error_code"] == "FORBIDDEN"` |
| `test_add_member_to_nonexistent_group_returns_404(client, auth_headers, test_volunteer)` | POST `/groups/{uuid.uuid4()}/members` `{"volunteer_id": str(test_volunteer.id)}`, headers=auth_headers | 404, `body["error_code"] == "NOT_FOUND"` |

### `tests/test_waivers.py` (5 tests)

| Test | Action | Asserts |
|---|---|---|
| `test_sign_waiver(client, auth_headers)` | POST `/waivers/sign` `{"accepted": True}`, headers=auth_headers | 201, `body["signed"] is True`, `body["signed_at"]` is a non-empty string |
| `test_sign_waiver_idempotent(client, auth_headers)` | Sign once; capture `signed_at_1`; sign again; capture `signed_at_2` | both 201; `signed_at_1 == signed_at_2` (same row, no new insert) |
| `test_waiver_status_signed(client, auth_headers)` | Sign a waiver; then GET `/waivers/me/status`, headers=auth_headers | 200, `body["signed"] is True`, `body["signed_at"]` matches the sign timestamp |
| `test_waiver_status_unsigned(client, auth_headers)` | GET `/waivers/me/status` without prior sign, headers=auth_headers | 200, `body["signed"] is False`, `body["signed_at"] is None` |
| `test_waiver_sign_unauthenticated(client)` | POST `/waivers/sign` `{"accepted": True}` with NO headers | 401, `body["error_code"] == "UNAUTHORIZED"` |

### `tests/test_orientation.py` (4 tests)

| Test | Action | Asserts |
|---|---|---|
| `test_complete_orientation(client, auth_headers)` | POST `/orientation/complete` `{"completed": True}`, headers=auth_headers | 201, `body["completed"] is True`, `body["completed_at"]` is a non-empty string |
| `test_complete_orientation_idempotent(client, auth_headers)` | Complete once; capture `completed_at_1`; complete again; capture `completed_at_2` | both 201; `completed_at_1 == completed_at_2` |
| `test_orientation_status_completed(client, auth_headers)` | Complete orientation; then GET `/orientation/me/status`, headers=auth_headers | 200, `body["completed"] is True`, `body["completed_at"]` matches |
| `test_orientation_status_not_completed(client, auth_headers)` | GET `/orientation/me/status` without prior completion, headers=auth_headers | 200, `body["completed"] is False`, `body["completed_at"] is None` |

## New files
- `backend/app/routers/groups.py` — `router = APIRouter(prefix="/groups", tags=["groups"])`. Three handlers per "API contract" + "Algorithm" sections: `create_group`, `list_my_groups`, `add_member`. Imports (use these EXACT statements): `import uuid`, `from fastapi import APIRouter, Depends`, `from sqlalchemy import select`, `from sqlalchemy.ext.asyncio import AsyncSession`, `from app.database import get_db`, `from app.dependencies import get_current_volunteer`, `from app.exceptions import AppError, NOT_FOUND, FORBIDDEN`, `from app.models import Volunteer, Group, GroupMember`, `from app.schemas import GroupCreate, GroupRead, GroupMemberAdd`.

- `backend/app/routers/waivers.py` — `router = APIRouter(prefix="/waivers", tags=["waivers"])`. Two handlers: `sign_waiver`, `my_waiver_status`. Imports: `from fastapi import APIRouter, Depends`, `from sqlalchemy import select`, `from sqlalchemy.ext.asyncio import AsyncSession`, `from app.database import get_db`, `from app.dependencies import get_current_volunteer`, `from app.models import Volunteer, WaiverAcceptance`, `from app.schemas import WaiverSignRequest, WaiverStatusResponse`.

- `backend/app/routers/orientation.py` — `router = APIRouter(prefix="/orientation", tags=["orientation"])`. Two handlers: `complete_orientation`, `my_orientation_status`. Imports: `from fastapi import APIRouter, Depends`, `from sqlalchemy import select`, `from sqlalchemy.ext.asyncio import AsyncSession`, `from app.database import get_db`, `from app.dependencies import get_current_volunteer`, `from app.models import Volunteer, OrientationCompletion`, `from app.schemas import OrientationCompleteRequest, OrientationStatusResponse`.

- `backend/tests/test_groups.py` — 5 tests per "Test contract → test_groups.py" table. Imports: `import uuid`, `from httpx import AsyncClient`, `from sqlalchemy.ext.asyncio import AsyncSession`, `from app.models import Volunteer, Group, GroupMember`. Uses `client`, `auth_headers`, `test_volunteer`, `db_session` fixtures.

- `backend/tests/test_waivers.py` — 5 tests per "Test contract → test_waivers.py" table. Imports: `from httpx import AsyncClient`. Uses `client`, `auth_headers` fixtures.

- `backend/tests/test_orientation.py` — 4 tests per "Test contract → test_orientation.py" table. Imports: `from httpx import AsyncClient`. Uses `client`, `auth_headers` fixtures.

## Modified files
(none — Sprint 001's `main.py` auto-discovers new router files via `pkgutil`; no schema, model, or main.py edits required.)

## Rules
- All new files go under `backend/`. NO modifications to any sprint 001 or sprint 002 file.
- Routers expose their `APIRouter` instance as the module-level name `router` (sprint 001's `main.py` `pkgutil` discovery requires this exact attribute name).
- Routers use `prefix="/<resource>"` on the `APIRouter()` constructor; paths inside route decorators are relative.
- Imports use `from app.X import Y` form throughout. No relative imports.
- Imports are full Python statements, never bare module names.
- Tests take fixtures (`client`, `auth_headers`, `test_volunteer`, `db_session`) as **function parameters** — never construct `AsyncClient`, engines, or sessions inside test bodies.
- All test functions are `async def`. Do NOT add `@pytest.mark.asyncio` decorators.
- Authenticated requests pass `headers=auth_headers` to the client method.
- Idempotent endpoints (`/waivers/sign`, `/orientation/complete`) MUST check for an existing row first and return its data without inserting a duplicate. The `unique=True` on `volunteer_id` enforces this at the DB level too — but the handler MUST handle it cleanly without relying on integrity errors.
- "Empty status" GET endpoints (`/waivers/me/status`, `/orientation/me/status`) return `signed=False, signed_at=None` (or completed equivalents) when no row exists. They never raise 404; "not yet signed" is a valid state, not an error.
- 404 takes precedence over 403 in `add_member`: check the group exists first, then check leadership.
- Tests that need a second volunteer construct it inline via `db_session.add(Volunteer(phone=..., email=..., ...)); await db_session.commit(); await db_session.refresh(other)`. The fixtures don't provide a factory.
- Tests serialize `uuid.UUID` via `str(...)` and `date`/`time`/`datetime` via `.isoformat()` when passing to httpx `json=`.
- Tests parse string ids back to `uuid.UUID(...)` before using in any ORM `select(...).where(...)` query.
- Path/query parameters use real Python types (e.g., `group_id: uuid.UUID`) — never `str`.
- **Error-response assertions use the flat shape** — Sprint 001's `main.py` exception handler returns `{"detail": "<message>", "error_code": "<code>"}` (FLAT), not `{"detail": {"detail": "<message>", "error_code": "<code>"}}` (nested). Tests assert `body["error_code"]` directly, NOT `body["detail"]["error_code"]`. Same flat shape applies to 401 responses generated by `get_current_volunteer` (also raises `AppError`, so handled by the same handler).

## DoD
- [ ] `cd backend && uv run pytest tests/test_groups.py -v` passes (5 tests).
- [ ] `cd backend && uv run pytest tests/test_waivers.py -v` passes (5 tests).
- [ ] `cd backend && uv run pytest tests/test_orientation.py -v` passes (4 tests).
- [ ] All sprint 001 + 002 tests still green (cumulative ≥ 47 + 14 = 61 tests passing).
- [ ] `cd backend && uv run ruff check app/ tests/` exits 0.
- [ ] None of sprint 001's or sprint 002's files are modified by this sprint.

## Validation
```bash
cd backend
uv run pytest -v --tb=short
uv run ruff check app/ tests/
```
